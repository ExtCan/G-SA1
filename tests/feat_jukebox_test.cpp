// feat_jukebox_test: the jukebox engine (src/core/jukebox.hpp; plan gsa1_rounds_plan.md 10.2, J1; sadc
// docs/research/jukebox.md 6.3 and 7 J1 with its Review G1-G4, G8-G10) and the game music's duck (Audio::set_duck),
// linked like core_test (the core objects and libsa1; no module, no Lua). The output is FakeBass (src/core/bass.hpp):
// push streams that drain in real time, keep the PCM pushed and record every BASS call with its thread.
//
//   feat_jukebox_test [--gdi GAME.gdi] [--verbose]
//
// Without the disc: the plan's arithmetic, the 3D curve (the game's, near = far / 30) and the gain rule. With it:
// the track list (109 on the disc, 104 in the sound test, titles, 69 absent, 87 truncated, the jingle set); the PCM at
// gain 1 equals sa1_audio_stream_read sample for sample (track 28 from 0 s and from 70 s, the loop seam, "forever"
// restarting a file without a loop); "loops 2" ends at loop_start + 2 x loop length + the fade, with the fade-out
// envelope; "once" ends at the file's end; a start beyond the plan's end is "ended" at once; pause / resume keep the
// position; seek forward and back (the old stream slid to 0 and freed); 69 fails; start anchoring; the volume is the
// game's -1 dB and every stream has its gain and pan before its first play; 3D gain and pan; the audible count; BASS
// errors re-create the stream; a slow disc (10 ms per file read) with two deep opens in a row leaves no underrun on a
// playing channel; 5 channels at once; shutdown with every channel playing frees every BASS stream and every
// allocation of the jukebox's context; no BASS call ever comes from the calling (Lua) thread; the duck ramps the game's
// background music down and spares its jingles unless asked.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <map>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "audio.hpp"
#include "bass.hpp"
#include "jukebox.hpp"
#include "util.hpp"

using namespace gsa1;

static int g_fail = 0, g_checks = 0;
static bool g_verbose = false;
#define CHECK(cond, ...)                      \
    do {                                      \
        g_checks++;                           \
        std::printf((cond) ? "  ok    " : "  FAIL  "); \
        if (!(cond)) g_fail++;                \
        std::printf(__VA_ARGS__);             \
        std::printf("\n");                    \
        std::fflush(stdout);                  \
    } while (0)

static void sleep_ms(double ms)
{
    std::this_thread::sleep_for(std::chrono::microseconds((int64_t)(ms * 1000.0)));
}

static bool wait_for(const std::function<bool()> &f, double timeout_ms)
{
    double t0 = now_ms();
    while (!f()) {
        if (now_ms() - t0 > timeout_ms) {
            return false;
        }
        sleep_ms(5);
    }
    return true;
}

static void test_log(void *, int32_t level, const char *m)
{
    if (g_verbose || level >= SA1_LOG_WARN) {
        std::printf("        log: %s\n", m);
    }
}

// ---- without the disc -------------------------------------------------------------------------------------------
static void test_plan_math()
{
    JbTrack t;
    t.music = 1;
    t.rate = 44100;
    t.frames = 100000;
    t.loop = true;
    t.loop_start = 20000;
    t.loop_end = 90000;
    JbPlanSpec f, l, o;
    l.plan = JbPlan::Loops;
    l.loops = 2;
    l.fade_out = 1.0;
    o.plan = JbPlan::Once;
    CHECK(jb_plan_end(t, f) == kJbForever && jb_source_frame(t, f, 50000) == 50000 && jb_source_frame(t, f, 89999) == 89999 &&
              jb_source_frame(t, f, 90000) == 20000 && jb_source_frame(t, f, 160000) == 20000 &&
              jb_source_frame(t, f, 160001) == 20001 && jb_loops_done(t, f, 19999) == 0 && jb_loops_done(t, f, 89999) == 0 &&
              jb_loops_done(t, f, 90000) == 1 && jb_loops_done(t, f, 230000) == 3,
          "plan \"forever\" on a looping file: plan frame -> source frame wraps from loop_end to loop_start, loops counted");
    CHECK(jb_plan_end(t, l) == 20000u + 2u * 70000u + 44100u && jb_source_frame(t, l, 150000) == 80000 &&
              jb_loops_done(t, l, 160000) == 2,
          "plan \"loops\" 2, fade 1 s: ends at loop_start + 2 x loop length + the fade (%llu)",
          (unsigned long long)jb_plan_end(t, l));
    CHECK(jb_plan_end(t, o) == 100000 && jb_source_frame(t, o, 95000) == 95000 && !jb_plan_wraps(t, o) &&
              jb_loops_done(t, o, 95000) == 0,
          "plan \"once\": to the end of the file, the loop ignored (the tail after loop_end plays)");
    JbTrack n = t;
    n.loop = false;
    n.loop_start = 0;
    n.loop_end = n.frames = 50000;
    CHECK(jb_plan_end(n, f) == kJbForever && jb_source_frame(n, f, 60000) == 10000 && jb_loops_done(n, f, 120000) == 2 &&
              jb_plan_end(n, l) == 50000 && !jb_plan_wraps(n, l),
          "a file without a loop: \"forever\" starts again at 0, \"loops\" plays it once");
    JbPlan p;
    CHECK(jb_plan_parse("forever", p) && p == JbPlan::Forever && jb_plan_parse("loops", p) && p == JbPlan::Loops &&
              jb_plan_parse("once", p) && p == JbPlan::Once && !jb_plan_parse("Forever", p) && !jb_plan_parse("", p) &&
              std::string(jb_state_name(JbState::Failed)) == "failed",
          "plan names parse exactly; state names");
}

static void test_spatial()
{
    const float eye[3] = {0, 0, 0}, fwd[3] = {1, 0, 0}, up[3] = {0, 0, 1};
    // Source axes: forward x up = right = -Y
    auto expect = [](double d, double far_d) {
        double near_d = far_d / 30.0, g = 1.0;
        if (d > near_d) {
            double f = std::min(1.0, (d - near_d) / (far_d - near_d));
            double cc = 106.0 - 127.0 * f;
            g = cc > 0.0 ? (cc / 106.0) * (cc / 106.0) : 0.0;
        }
        return g;
    };
    float g, p;
    const float right[3] = {0, -100, 0};
    jb_spatial(eye, fwd, up, right, 600.0, g, p);
    bool a = std::fabs(g - expect(100, 600)) < 1e-5 && std::fabs(p - 0.6f) < 1e-5;
    const float left[3] = {0, 300, 0};
    float g2, p2;
    jb_spatial(eye, fwd, up, left, 600.0, g2, p2);
    bool b = std::fabs(g2 - expect(300, 600)) < 1e-5 && std::fabs(p2 + 0.6f) < 1e-5;
    const float near_p[3] = {15, 0, 0}, front[3] = {400, 0, 0}, far_p[3] = {505, 0, 0};
    float g3, p3, g4, p4, g5, p5;
    jb_spatial(eye, fwd, up, near_p, 600.0, g3, p3);
    jb_spatial(eye, fwd, up, front, 600.0, g4, p4);
    jb_spatial(eye, fwd, up, far_p, 600.0, g5, p5);
    CHECK(a && b && g3 == 1.0f && p3 == 0.0f && std::fabs(g4 - expect(400, 600)) < 1e-5 && std::fabs(p4) < 1e-6 && g5 == 0.0f,
          "3D: the game's curve (CC7 = 106 - 127 f, gain (CC7 / 106)^2, near = far / 30, silent from 0.84 x far) and pan "
          "0.6 x the listener's right: right %.4f / %+.2f, left %.4f / %+.2f, inside near %.0f, at 0.84 far %.3f",
          g, p, g2, p2, g3, g5);
    CHECK(std::fabs(jb_gain(1, 0.5, 10000, 1, 1) - 0.5 * kJukeboxReference) < 1e-9 &&
              std::fabs(jb_gain(1, 0.5, -1, 1, 1) - 0.5 * kJukeboxReference) < 1e-9 &&
              std::fabs(jb_gain(1, 0.5, 5000, 1, 1) - kJukeboxReference) < 1e-9 &&
              std::fabs(jb_gain(0.5, 1, 10000, 0.5, 0.5) - 0.125 * kJukeboxReference) < 1e-9 &&
              jb_gain(2.0, 1, 10000, 1, 1) == kJukeboxReference && std::fabs(kJukeboxReference - std::pow(10.0, -1.0 / 20.0)) < 1e-9,
          "gain: volume 1 = the game's music level %.4f (-1 dB, 8C6445EA(h, -10)); GMod's volume applies unless GMod "
          "scales BASS's streams (BASS_CONFIG_GVOL_STREAM not 10000); x music volume x the 3D gain; never above 1",
          kJukeboxReference);
}

// ---- the disc: a reference decoder (libsa1's own streams) --------------------------------------------------------
struct Ref {
    sa1_context *ctx = nullptr;
    sa1_audio *audio = nullptr;
    bool open(const std::string &gdi)
    {
        if (sa1_init(nullptr, &ctx) != SA1_OK) {
            return false;
        }
        sa1_audio_desc d;
        std::memset(&d, 0, sizeof d);
        d.struct_size = sizeof d;
        d.gdi_path = gdi.c_str();
        d.flags = SA1_AUDIO_MUSIC_ONLY | SA1_AUDIO_SYNC_LOADS;
        d.stage = SA1_AUDIO_STAGE_DEFAULT;
        return sa1_audio_open(ctx, &d, &audio) == SA1_OK;
    }
    ~Ref()
    {
        if (audio) sa1_audio_close(audio);
        if (ctx) sa1_shutdown(ctx);
    }
    // n frames of the plan from plan frame pf: libsa1's stream from the plan's source frame, with the plan's loop
    // flag; "forever" on a file without a loop goes on from frame 0 at the file's end
    std::vector<int16_t> plan_read(const JbTrack &t, const JbPlanSpec &spec, uint64_t pf, uint32_t n)
    {
        std::vector<int16_t> out((size_t)n * 2u, 0);
        sa1_audio_stream *s = nullptr;
        if (sa1_audio_stream_open(audio, SA1_AUDIO_SOURCE_MUSIC, t.music, &s, nullptr) != SA1_OK) {
            return std::vector<int16_t>();
        }
        sa1_audio_stream_seek(s, jb_source_frame(t, spec, pf));
        bool wraps = jb_plan_wraps(t, spec);
        int32_t loop = wraps && t.loop ? 1 : 0;
        uint32_t done = 0;
        for (int k = 0; k < 8 && done < n; k++) {
            uint32_t got = 0;
            sa1_audio_stream_read(s, out.data() + (size_t)done * 2u, n - done, loop, &got);
            done += got;
            if (done < n && wraps && !t.loop) {
                sa1_audio_stream_seek(s, 0);
            } else if (done < n) {
                break;
            }
        }
        sa1_audio_stream_close(s);
        return out;
    }
};

struct Rig {
    Jukebox jb;
    std::shared_ptr<const std::vector<JbTrack>> list;
    std::map<uint32_t, JbTrack> by;
    const JbTrack *track(uint32_t m) const
    {
        auto it = by.find(m);
        return it == by.end() ? nullptr : &it->second;
    }
};

static bool start_rig(Rig &r, const std::string &gdi, const sa1_host *host, double &ready_ms)
{
    JukeboxConfig c;
    c.gdi = gdi;
    c.bass = FakeBass::get().api();
    c.host = host;
    c.log = test_log;
    std::string err;
    double t0 = now_ms();
    if (!r.jb.start(c, err)) {
        std::printf("        start: %s\n", err.c_str());
        return false;
    }
    std::string msg;
    bool ok = wait_for([&]() { return r.jb.tracks(r.list, msg) != 0; }, 60000);
    ready_ms = now_ms() - t0;
    if (!ok || !r.list) {
        std::printf("        the track list: %s\n", msg.c_str());
        return false;
    }
    for (const JbTrack &t : *r.list) {
        r.by[t.music] = t;
    }
    return true;
}

// plays and waits until the channel plays this play (generation moved on) with a BASS stream
static JbChannelInfo play_wait(Rig &r, int ch, uint32_t music, double start, const JbPlanSpec &spec, double call,
                               bool &ok, std::string &err, JbState want = JbState::Playing)
{
    uint64_t g0 = r.jb.state(ch).generation;
    ok = r.jb.play(ch, music, start, spec, call, err);
    JbChannelInfo s;
    wait_for([&]() {
        s = r.jb.state(ch);
        return s.generation > g0 && (s.state == want || s.state == JbState::Failed || s.state == JbState::Ended) &&
               (want != JbState::Playing || s.handle != 0 || s.state != JbState::Playing);
    }, 15000);
    return s;
}

static uint32_t mismatches(const std::vector<int16_t> &a, const std::vector<int16_t> &b, size_t n, size_t &first)
{
    uint32_t bad = 0;
    first = (size_t)-1;
    for (size_t i = 0; i < n; i++) {
        if (i >= a.size() || i >= b.size() || a[i] != b[i]) {
            if (!bad) first = i;
            bad++;
        }
    }
    return bad;
}

static void test_list(Rig &r, double ready_ms)
{
    const auto &L = *r.list;
    uint32_t listed = 0, shorts = 0, pages[6] = {0, 0, 0, 0, 0, 0};
    std::set<uint32_t> jingles, truncated;
    for (const JbTrack &t : L) {
        listed += t.listed();
        shorts += t.is_short();
        if (t.listed() && t.page >= 0 && t.page < 6) pages[t.page]++;
        if (t.jingle()) jingles.insert(t.music);
        if (t.truncated()) truncated.insert(t.music);
    }
    JbStatusInfo st = r.jb.status();
    CHECK(L.size() == 109 && listed == 104 && !r.track(69) && st.ready && st.tracks == 109 && st.listed == 104 && st.titles,
          "the track list in %.0f ms (on the worker): %u tracks on the disc, %u in the game's sound test, 69 NIGHTS_K.ADX "
          "not listed", ready_ms, (unsigned)L.size(), (unsigned)listed);
    CHECK(pages[0] == 11 && pages[1] == 40 && pages[2] == 11 && pages[3] == 12 && pages[4] == 10 && pages[5] == 20,
          "sound-test pages %u / %u / %u / %u / %u / %u", pages[0], pages[1], pages[2], pages[3], pages[4], pages[5]);
    const JbTrack *a = r.track(66), *b = r.track(28), *c = r.track(61), *d = r.track(87), *e = r.track(68);
    CHECK(a && a->title == "Open Your Heart" && a->has_title && b && b->title == "Emerald Coast:  Type 1" && b->page == 1 &&
              b->entry == 0 && c && c->title == "Jingle#E" && c->page == 5 && c->entry == 19 && d && !d->listed() &&
              !d->has_title && d->title == "SSRACING.ADX" && e && e->page == -1,
          "titles from the disc: 66 \"%s\", 28 \"%s\" (page %d entry %d), 61 \"%s\"; 87 and 68 unlisted under their "
          "file names", a ? a->title.c_str() : "?", b ? b->title.c_str() : "?", b ? b->page : -9, b ? b->entry : -9,
          c ? c->title.c_str() : "?");
    std::set<uint32_t> want_j = {26, 44, 45, 46, 55, 56, 85, 96};
    CHECK(jingles == want_j && truncated == std::set<uint32_t>{87} && d && d->frames == 5632416u && shorts == 15,
          "jingles = {26 44 45 46 55 56 85 96}, truncated = {87} (%u frames present), %u short tracks (no loop, under "
          "25 s)", d ? d->frames : 0u, shorts);
    const JbTrack *w = r.track(108);
    CHECK(b && b->rate == 44100 && b->loop && w && w->rate == 32000 && w->loop && w->loop_end < w->frames,
          "28 ECOAST1: %u Hz, loop %.2f-%.2f s of %.2f; 108 WNDYVLY2: %u Hz, loop %.2f-%.2f s of %.2f",
          b ? b->rate : 0, b ? b->loop_start / 44100.0 : 0, b ? b->loop_end / 44100.0 : 0, b ? b->seconds() : 0,
          w ? w->rate : 0, w ? w->loop_start / 32000.0 : 0, w ? w->loop_end / 32000.0 : 0, w ? w->seconds() : 0);
}

// the PCM a channel pushed equals libsa1's stream read from the channel's start frame
static void test_pcm(Rig &r, Ref &ref, uint32_t music, double start, JbPlan plan, const char *what)
{
    FakeBass &fb = FakeBass::get();
    const JbTrack *t = r.track(music);
    if (!t) {
        CHECK(false, "%s: track %u missing", what, (unsigned)music);
        return;
    }
    JbPlanSpec spec;
    spec.plan = plan;
    bool ok;
    std::string err;
    double call = r.jb.clock_s();
    JbChannelInfo s = play_wait(r, 0, music, start, spec, call, ok, err);
    double t_play = r.jb.clock_s();
    sleep_ms(60);
    s = r.jb.state(0);
    FakeBass::Stream fs = fb.stream(s.handle);
    uint32_t n = (uint32_t)(fs.pcm.size() / 2u);
    std::vector<int16_t> want = ref.plan_read(*t, spec, s.start_frame, n);
    size_t first;
    uint32_t bad = mismatches(fs.pcm, want, (size_t)n * 2u, first);
    double late = (double)s.start_frame / t->rate - start;
    CHECK(ok && s.state == JbState::Playing && n >= (uint32_t)(2.9 * t->rate) && bad == 0 && late >= 0.0 &&
              late <= t_play - call + 0.05,
          "%s: %u frames (%.2f s queued at once) equal sa1_audio_stream_read sample for sample from the start frame "
          "(%.3f s: the asked %.1f s + %.1f ms the open took, anchored)%s", what, n, (double)n / t->rate,
          (double)s.start_frame / t->rate, start, late * 1000.0,
          bad ? format("; %u samples differ, the first at frame %zu", bad, first / 2u).c_str() : "");
}

static void test_engine(Rig &r, Ref &ref)
{
    FakeBass &fb = FakeBass::get();
    fb.set_record_pcm(true);
    bool ok;
    std::string err;
    JbPlanSpec forever;

    // the PCM, the loop seam, a restart of a file without a loop
    test_pcm(r, ref, 28, 0.0, JbPlan::Forever, "28 from 0 s");
    test_pcm(r, ref, 28, 70.0, JbPlan::Forever, "28 from 70 s");
    const JbTrack *t28 = r.track(28), *t108 = r.track(108), *t44 = r.track(44);
    if (t28) {
        test_pcm(r, ref, 28, t28->loop_end / 44100.0 - 1.0, JbPlan::Forever, "28 across its loop seam (1 s before loop_end)");
    }
    if (t108) {
        test_pcm(r, ref, 108, t108->loop_end / 32000.0 - 1.5, JbPlan::Forever, "108 (32 kHz) across its loop seam");
    }
    if (t44) {
        test_pcm(r, ref, 44, t44->seconds() - 1.0, JbPlan::Forever, "44 (no loop) \"forever\": from its end on to frame 0");
    }
    {
        JbChannelInfo s = r.jb.state(0);
        FakeBass::Stream fs = fb.stream(s.handle);
        CHECK(fs.started && std::fabs(fs.vol_set_before_play - kJukeboxReference) < 1e-6 && fs.pan_set_before_play == 0.0f &&
                  fs.buffer == 0.0f && fs.rate == 32000,
              "the stream: the track's own rate (%u Hz: BASS resamples), playback buffer 0, volume %.4f (= the game's -1 dB) "
              "and pan 0 set before its first play", fs.rate, fs.vol_set_before_play);
    }

    // loops 2 with a fade-out: where it ends, and the envelope
    if (t108) {
        JbPlanSpec l;
        l.plan = JbPlan::Loops;
        l.loops = 2;
        l.fade_out = 1.0;
        uint64_t end = jb_plan_end(*t108, l);
        uint64_t F = 32000;
        JbChannelInfo s = play_wait(r, 0, 108, (double)end / 32000.0 - 2.0, l, r.jb.clock_s(), ok, err);
        uint32_t h = s.handle;
        uint64_t start_frame = s.start_frame;
        wait_for([&]() { return r.jb.state(0).state == JbState::Ended; }, 6000);
        sleep_ms(150);      // the ended stream is slid to 0 and freed a moment later
        JbChannelInfo e = r.jb.state(0);
        FakeBass::Stream fs = fb.stream(h);
        uint64_t last = start_frame + fs.pushed;
        std::vector<int16_t> raw = ref.plan_read(*t108, l, start_frame, (uint32_t)fs.pushed);
        uint32_t bad = 0;
        double peak_tail = 0;
        for (uint64_t i = 0; i < fs.pushed && i * 2 + 1 < fs.pcm.size(); i++) {
            uint64_t p = start_frame + i;
            double g = p >= end - F ? (double)(end - p) / (double)F : 1.0;
            for (int k = 0; k < 2; k++) {
                int16_t want = (int16_t)std::lrint(raw[2 * i + k] * g);
                bad += fs.pcm[2 * i + k] != want;
                if (p >= end - 320) peak_tail = std::max(peak_tail, (double)std::abs((int)fs.pcm[2 * i + k]));
            }
        }
        CHECK(ok && last == end && fs.ended && fs.freed && e.state == JbState::Ended && e.loops_done == 2 &&
                  std::fabs(e.position - (double)end / 32000.0) < 1e-6 && bad == 0 && peak_tail < 1100,
              "108 \"loops\" 2, fade 1 s: ends at plan frame %llu = loop_start + 2 x loop length + 32000 (pushed to %llu, "
              "BASS_STREAMPROC_END, freed), state ended, loops_done %u; the fade-out envelope on the decoder's PCM (%u "
              "samples off; last 10 ms peak %.0f)", (unsigned long long)end, (unsigned long long)last, e.loops_done, bad,
              peak_tail);
    }
    // once: to the file's end (the tail after loop_end included)
    if (t108) {
        JbPlanSpec o;
        o.plan = JbPlan::Once;
        JbChannelInfo s = play_wait(r, 0, 108, t108->seconds() - 1.0, o, r.jb.clock_s(), ok, err);
        uint32_t h = s.handle;
        uint64_t sf = s.start_frame;
        wait_for([&]() { return r.jb.state(0).state == JbState::Ended; }, 5000);
        FakeBass::Stream fs = fb.stream(h);
        CHECK(sf + fs.pushed == t108->frames && r.jb.state(0).state == JbState::Ended,
              "108 \"once\" ends at the file's end, frame %u (loop_end %u)", (unsigned)(sf + fs.pushed), t108->loop_end);
        uint32_t created = fb.created();
        s = play_wait(r, 0, 108, t108->seconds() + 5.0, o, r.jb.clock_s(), ok, err, JbState::Ended);
        CHECK(ok && s.state == JbState::Ended && s.handle == 0 && fb.created() == created,
              "a start beyond the plan's end: \"ended\" at once, no stream made (a late joiner of a finished track)");
    }

    // pause / resume keep the position
    {
        JbChannelInfo s = play_wait(r, 0, 28, 10.0, forever, r.jb.clock_s(), ok, err);
        uint32_t h = s.handle;
        sleep_ms(400);
        r.jb.pause(0, true);
        wait_for([&]() { return r.jb.state(0).state == JbState::Paused; }, 2000);
        sleep_ms(50);
        double p1 = r.jb.state(0).position;
        bool held = fb.stream(h).paused;
        sleep_ms(600);
        double p2 = r.jb.state(0).position;
        r.jb.pause(0, false);
        wait_for([&]() { return r.jb.state(0).state == JbState::Playing; }, 2000);
        sleep_ms(600);
        double p3 = r.jb.state(0).position;
        CHECK(held && std::fabs(p2 - p1) < 0.03 && std::fabs(p3 - p1 - 0.6) < 0.12 && r.jb.state(0).handle == h,
              "pause holds the position (%.3f s -> %.3f s over 0.6 s, the BASS stream paused), resume goes on (+%.3f s "
              "over 0.6 s), the same stream", p1, p2, p3 - p1);
    }
    // seek forward and back: a new stream each, the old one slid to 0 and freed
    {
        JbChannelInfo s0 = r.jb.state(0);
        uint64_t g0 = s0.generation;
        r.jb.seek(0, 60.0);
        JbChannelInfo s;
        wait_for([&]() { s = r.jb.state(0); return s.generation > g0 && s.handle != 0 && s.handle != s0.handle; }, 5000);
        sleep_ms(300);
        double pf = r.jb.state(0).position;
        FakeBass::Stream old = fb.stream(s0.handle);
        uint32_t h1 = s.handle;
        g0 = s.generation;
        r.jb.seek(0, 5.0);
        wait_for([&]() { s = r.jb.state(0); return s.generation > g0 && s.handle != 0 && s.handle != h1; }, 5000);
        sleep_ms(300);
        double pb = r.jb.state(0).position;
        sleep_ms(100);
        FakeBass::Stream o1 = fb.stream(h1);
        CHECK(pf >= 60.0 && pf < 60.5 && pb >= 5.0 && pb < 5.5 && old.slide_vol == 0.0f && old.slide_vol_ms == 50 &&
                  old.freed && o1.slide_vol == 0.0f && o1.freed,
              "seek forward to 60 s (position %.3f after 0.3 s) and back to 5 s (%.3f): a new stream each, the old one "
              "slid to 0 over %u ms and freed", pf, pb, old.slide_vol_ms);
    }
    // 69: not on the disc
    {
        JbPlanSpec sp;
        JbChannelInfo s = play_wait(r, 0, 69, 0.0, sp, r.jb.clock_s(), ok, err, JbState::Failed);
        CHECK(!ok && s.state == JbState::Failed && s.error.find("not on your disc") != std::string::npos && s.handle == 0,
              "play(69): refused (\"%s\"), the channel fails: \"%s\"", err.c_str(), s.error.c_str());
        s = play_wait(r, 0, 110, 0.0, sp, r.jb.clock_s(), ok, err, JbState::Failed);
        CHECK(!ok && s.state == JbState::Failed, "play(110): \"%s\"", err.c_str());
        r.jb.stop(0, 0.0);
        wait_for([&]() { return r.jb.state(0).state == JbState::Idle; }, 2000);
    }
    // start anchoring (Review G3): a play whose call was 0.5 s ago starts 0.5 s further in
    {
        double call = r.jb.clock_s() - 0.5;
        double t0 = r.jb.clock_s();
        JbChannelInfo s = play_wait(r, 1, 28, 10.0, forever, call, ok, err);
        double waited = r.jb.clock_s() - t0;
        double st = (double)s.start_frame / 44100.0;
        CHECK(ok && st >= 10.5 && st <= 10.5 + waited + 0.03,
              "anchoring: JukeboxPlay(start 10 s) called 0.5 s before the worker took it starts at %.3f s (10.5 + %.1f ms "
              "of open)", st, (st - 10.5) * 1000.0);
        r.jb.stop(1, 0.0);
    }
    // 3D gain and pan, the audible count, the game's pause
    {
        const float eye[3] = {0, 0, 0}, fwd[3] = {1, 0, 0}, up[3] = {0, 0, 1};
        const float right[3] = {0, -100, 0}, left[3] = {0, 100, 0};
        r.jb.update(eye, fwd, up, 1.0, 1.0, false);
        r.jb.place(2, right, 600.0);
        JbChannelInfo s = play_wait(r, 2, 108, 0.0, forever, r.jb.clock_s(), ok, err);
        float g, p;
        jb_spatial(eye, fwd, up, right, 600.0, g, p);
        FakeBass::Stream fs = fb.stream(s.handle);
        bool first = std::fabs(fs.vol_set_before_play - jb_gain(1, 1, 10000, 1, g)) < 1e-5 &&
                     std::fabs(fs.pan_set_before_play - 0.6) < 1e-5;
        r.jb.place(2, left, 600.0);
        sleep_ms(80);
        fs = fb.stream(s.handle);
        bool moved = std::fabs(fs.slide_pan + 0.6f) < 1e-5;
        JbChannelInfo s0 = play_wait(r, 0, 28, 0.0, forever, r.jb.clock_s(), ok, err);
        int n2 = r.jb.update(eye, fwd, up, 1.0, 1.0, false);
        r.jb.volume(0, 0.01);
        int n1 = r.jb.update(eye, fwd, up, 1.0, 1.0, false);
        int n0 = r.jb.update(eye, fwd, up, 1.0, 1.0, true);
        sleep_ms(80);
        bool held = fb.stream(s0.handle).paused && fb.stream(s.handle).paused;
        r.jb.update(eye, fwd, up, 1.0, 1.0, false);
        sleep_ms(80);
        bool resumed = !fb.stream(s0.handle).paused && std::fabs(fb.stream(s0.handle).vol - jb_gain(0.01, 1, 10000, 1, 1)) < 1e-5;
        CHECK(first && moved && n2 == 2 && n1 == 1 && n0 == 0 && held && resumed,
              "3D: the placed channel's first volume %.4f and pan %+.2f are the game's curve before its first play; moved "
              "left the pan slides to %+.2f; audible channels %d (both), %d (personal at volume 0.01), %d (game paused: "
              "both BASS streams pause, and play on after)", fs.vol_set_before_play, fs.pan_set_before_play, fs.slide_pan,
              n2, n1, n0);
        r.jb.volume(0, 1.0);
        r.jb.place_2d(2);
        r.jb.stop(2, 0.0);
        r.jb.stop(0, 0.0);
    }
    // BASS errors (Review G10): GMod re-initialised BASS -> the stream is made again where it was
    {
        JbChannelInfo s = play_wait(r, 0, 28, 20.0, forever, r.jb.clock_s(), ok, err);
        sleep_ms(300);
        double p0 = r.jb.state(0).position;
        uint64_t rec0 = r.jb.status().recoveries;
        fb.break_all();
        JbChannelInfo s2;
        wait_for([&]() { s2 = r.jb.state(0); return r.jb.status().recoveries > rec0 && s2.handle && s2.handle != s.handle; }, 3000);
        sleep_ms(50);
        double p1 = r.jb.state(0).position;
        JbStatusInfo st = r.jb.status();
        CHECK(st.recoveries == rec0 + 1 && s2.state == JbState::Playing && s2.handle != s.handle && std::fabs(p1 - p0) < 0.5 &&
                  st.error.find("BASS error 5") != std::string::npos,
              "BASS error: every stream invalid -> re-created at %.2f s (was %.2f s), counted, reported: \"%s\"", p1, p0,
              st.error.c_str());
        fb.fail_creates(2);
        fb.break_all();
        double t0 = now_ms();
        JbChannelInfo s3;
        bool back = wait_for([&]() { s3 = r.jb.state(0); return s3.handle && s3.handle != s2.handle; }, 6000);
        CHECK(back && now_ms() - t0 > 1500 && s3.state == JbState::Playing,
              "two failed BASS_StreamCreate in a row (no device yet): retried every second, playing again after %.1f s",
              (now_ms() - t0) / 1000.0);
        r.jb.stop(0, 0.0);
    }
    fb.set_record_pcm(false);
}

// five channels at once, then shutdown with all of them playing
static void test_five_and_shutdown(Rig &r)
{
    FakeBass &fb = FakeBass::get();
    const uint32_t m[5] = {28, 108, 63, 79, 6};
    JbPlanSpec forever;
    bool all = true;
    uint32_t h[5];
    uint64_t u0 = r.jb.status().underruns;
    for (int ch = 0; ch < 5; ch++) {
        bool ok;
        std::string err;
        JbChannelInfo s = play_wait(r, ch, m[ch], 30.0, forever, r.jb.clock_s(), ok, err);
        all = all && ok && s.state == JbState::Playing;
        h[ch] = s.handle;
    }
    sleep_ms(1500);
    uint32_t stalls = 0;
    for (int ch = 0; ch < 5; ch++) stalls += fb.stream(h[ch]).stalls;
    JbStatusInfo st = r.jb.status();
    CHECK(all && stalls == 0 && st.underruns == u0 && st.active == 5,
          "5 channels at once (28, 108, 63, 79, 6): all playing, no underrun in 1.5 s; %.1f MB held by the jukebox's "
          "context (the streams' files), slowest open %.1f ms", st.memory_mb, st.max_open_ms);
    r.jb.shutdown();
    st = r.jb.status();
    bool freed = true;
    for (int ch = 0; ch < 5; ch++) freed = freed && fb.stream(h[ch]).freed;
    CHECK(freed && fb.live() == 0 && st.memory_blocks == 0 && st.memory_mb == 0.0 && !st.started,
          "shutdown with 5 channels playing: every BASS stream freed (%u live), the jukebox's context balanced its "
          "allocations (%lld blocks left)", fb.live(), (long long)st.memory_blocks);
}

// a slow disc (Review G4): about 10 ms per file read; two deep opens in a row while a channel plays
struct SlowFiles {
    std::atomic<uint64_t> reads{0};
    double delay_ms = 10.0;
};

static void *sf_open(void *, const char *path)
{
    File *f = new File();
    std::string err;
    if (!f->open(path, err)) {
        delete f;
        return nullptr;
    }
    return f;
}
static int32_t sf_size(void *, void *f, uint64_t *size)
{
    *size = ((File *)f)->size();
    return 0;
}
static int32_t sf_read(void *u, void *f, uint64_t off, void *buf, size_t n)
{
    SlowFiles *s = (SlowFiles *)u;
    s->reads++;
    sleep_ms(s->delay_ms);
    return ((File *)f)->read_at(off, buf, n) ? 0 : -1;
}
static void sf_close(void *, void *f)
{
    delete (File *)f;
}

static void test_slow_disc(const std::string &gdi)
{
    FakeBass &fb = FakeBass::get();
    SlowFiles sf;
    sa1_host host;
    sa1_host_defaults(&host);
    host.user = &sf;
    host.file_open = sf_open;
    host.file_size = sf_size;
    host.file_read = sf_read;
    host.file_close = sf_close;
    Rig r;
    double ready_ms = 0;
    if (!start_rig(r, gdi, &host, ready_ms)) {
        CHECK(false, "slow disc: the jukebox did not start");
        return;
    }
    JbPlanSpec forever;
    bool ok;
    std::string err;
    JbChannelInfo s0 = play_wait(r, 0, 28, 0.0, forever, r.jb.clock_s(), ok, err);
    sleep_ms(300);
    uint64_t reads0 = sf.reads.load();
    double t0 = now_ms();
    // two of the largest files, from 90 % in: a lazy stream reads the file up to there (about 100 reads each)
    const JbTrack *a = r.track(6), *b = r.track(66);
    r.jb.play(1, 6, a ? a->seconds() * 0.9 : 200.0, forever, r.jb.clock_s(), err);
    r.jb.play(2, 66, b ? b->seconds() * 0.9 : 200.0, forever, r.jb.clock_s(), err);
    bool both = wait_for([&]() {
        return r.jb.state(1).state == JbState::Playing && r.jb.state(2).state == JbState::Playing && r.jb.state(1).handle &&
               r.jb.state(2).handle;
    }, 30000);
    double opened = now_ms() - t0;
    uint64_t reads = sf.reads.load() - reads0;
    sleep_ms(500);
    FakeBass::Stream fs = fb.stream(s0.handle);
    JbStatusInfo st = r.jb.status();
    CHECK(both && reads >= 150 && opened > 1500 && fs.stalls == 0 && st.underruns == 0 && st.max_open_ms > 700,
          "slow disc (10 ms per file read; list in %.0f ms): two deep opens in a row took %.1f s and %llu reads (slowest "
          "open %.0f ms); channel 0 never ran dry (%u stalls, %llu underruns): every channel is topped up before each "
          "blocking open and the queue is 3 s", ready_ms, opened / 1000.0, (unsigned long long)reads, st.max_open_ms,
          fs.stalls, (unsigned long long)st.underruns);
    r.jb.shutdown();
}

// the duck: the game's background music ramps down, its jingles are spared unless asked
static double rms_of(Audio &au, double seconds)
{
    uint32_t frames = (uint32_t)(seconds * 44100.0);
    std::vector<int16_t> pcm((size_t)frames * 2u);
    for (uint32_t at = 0; at < frames; at += 735) {
        uint32_t n = std::min<uint32_t>(735, frames - at);
        au.render(pcm.data() + (size_t)at * 2u, n);
    }
    double sum = 0;
    for (int16_t v : pcm) sum += (double)v * v;
    return std::sqrt(sum / (double)pcm.size());
}

static void test_duck(const std::string &gdi)
{
    Audio au;
    au.set_log(test_log, nullptr);
    std::string err;
    bool ok = au.open(gdi, false, err);
    CHECK(ok, "the game's sound banks opened (%s)", ok ? "for the duck" : err.c_str());
    if (!ok) return;
    AudioOptions o;
    o.bgm = true;
    au.apply(o);
    sa1_event e;
    std::memset(&e, 0, sizeof e);
    e.character = 1;
    e.type = SA1_EVENT_JINGLE;
    e.id = 28;
    e.arg = 0x8C107AC6u;    // 8C107AC6: background music
    au.event(e);
    double r0 = 0;
    wait_for([&]() { r0 = rms_of(au, 0.1); return r0 > 200.0; }, 8000);
    double music = rms_of(au, 0.5);
    CHECK(!au.set_duck(1.5f, false) && !au.set_duck(-0.1f, false) && !au.set_duck(NAN, false) && au.duck() == 1.0f,
          "set_duck refuses gains outside 0..1");
    au.set_duck(0.0f, false);
    double mid = rms_of(au, 0.05);      // gain 1 -> 0.9: a ramp, not a jump
    rms_of(au, 0.4);
    double late = rms_of(au, 0.05);     // gain 0.1 -> 0
    double after = rms_of(au, 0.5);
    e.id = 85;
    e.arg = 0x8C107C80u;    // 8C107C80: a jingle (SPEEDUP)
    au.event(e);
    double jingle = 0;
    wait_for([&]() { jingle = rms_of(au, 0.1); return jingle > 200.0; }, 8000);
    jingle = rms_of(au, 0.4);
    au.set_duck(0.0f, true);
    rms_of(au, 0.55);
    double both = rms_of(au, 0.3);
    au.set_duck(1.0f, false);
    rms_of(au, 0.55);
    double back = rms_of(au, 0.3);
    CHECK(music > 300.0 && mid > music * 0.3 && late < music * 0.2 && after < 1.0 && jingle > 300.0 && both < 1.0 &&
              back > 300.0 && au.duck() == 1.0f,
          "duck: the background music (rms %.0f) ramps down over 0.5 s (%.0f in its first 50 ms, %.0f in its last) to "
          "silence (%.1f) and keeps playing; a jingle meanwhile is heard (rms %.0f: spared, the drowning countdown stays "
          "audible); ducking the jingles too silences it (%.1f); gain 1 brings it back (%.0f)", music, mid, late, after,
          jingle, both, back);
    au.shutdown();
}

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i < argc; i++) {
        if (std::string(argv[i]) == "--gdi" && i + 1 < argc) gdi = argv[++i];
        else if (std::string(argv[i]) == "--verbose") g_verbose = true;
    }
    std::printf("G-SA1 feat_jukebox_test\n");
    std::thread::id lua_thread = std::this_thread::get_id();
    FakeBass &fb = FakeBass::get();
    fb.reset();
    bass_set_test_api(fb.api());
    test_plan_math();
    test_spatial();
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the disc checks are skipped\n");
    } else {
        Ref ref;
        CHECK(ref.open(gdi), "a reference music object (libsa1's own streams)");
        {
            Rig r;
            double ready_ms = 0;
            bool started = start_rig(r, gdi, nullptr, ready_ms);
            CHECK(started, "the jukebox started on a worker (music-only, lazy streams) and listed the disc's music");
            if (started) {
                test_list(r, ready_ms);
                test_engine(r, ref);
                test_five_and_shutdown(r);
            }
        }
        test_slow_disc(gdi);
        uint32_t early = 0;
        for (auto &kv : fb.streams()) {
            early += kv.second.started && !kv.second.attrs_before_play;
        }
        CHECK(fb.calls() > 0 && fb.calls_from(lua_thread) == 0 && early == 0 && fb.live() == 0,
              "handle ownership (Review G1): %llu BASS calls, none from the calling (Lua) thread; all %u streams had their "
              "volume and pan before their first play; none left", (unsigned long long)fb.calls(), fb.created());
        test_duck(gdi);
    }
    bass_set_test_api(nullptr);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
