// G-SA1 core: the jukebox engine (see jukebox.hpp).
#include "jukebox.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>

namespace gsa1 {

// ---- names --------------------------------------------------------------------------------------------------------
const char *jb_plan_name(JbPlan p)
{
    switch (p) {
    case JbPlan::Forever: return "forever";
    case JbPlan::Loops: return "loops";
    case JbPlan::Once: return "once";
    }
    return "?";
}

bool jb_plan_parse(const std::string &s, JbPlan &out)
{
    if (s == "forever") out = JbPlan::Forever;
    else if (s == "loops") out = JbPlan::Loops;
    else if (s == "once") out = JbPlan::Once;
    else return false;
    return true;
}

const char *jb_state_name(JbState s)
{
    switch (s) {
    case JbState::Idle: return "idle";
    case JbState::Loading: return "loading";
    case JbState::Playing: return "playing";
    case JbState::Paused: return "paused";
    case JbState::Ended: return "ended";
    case JbState::Failed: return "failed";
    }
    return "?";
}

// ---- the plan's arithmetic ----------------------------------------------------------------------------------------
static uint64_t fade_frames(double s, uint32_t rate)
{
    return (std::isfinite(s) && s > 0.0) ? (uint64_t)std::llround(s * (double)rate) : 0u;
}

uint64_t jb_plan_end(const JbTrack &t, const JbPlanSpec &p)
{
    switch (p.plan) {
    case JbPlan::Forever: return t.frames ? kJbForever : 0u;
    case JbPlan::Once: return t.frames;
    case JbPlan::Loops:
        if (!t.loop || t.loop_end <= t.loop_start) {
            return t.frames;        // a file without a loop plays once
        }
        return (uint64_t)t.loop_start + (uint64_t)std::max(1, p.loops) * (t.loop_end - t.loop_start) +
               fade_frames(p.fade_out, t.rate);
    }
    return t.frames;
}

bool jb_plan_wraps(const JbTrack &t, const JbPlanSpec &p)
{
    if (p.plan == JbPlan::Forever) {
        return t.frames > 0;        // a file without a loop starts again at 0
    }
    return p.plan == JbPlan::Loops && t.loop && t.loop_end > t.loop_start;
}

// the region a wrapping plan repeats: the header loop, or the whole file (forever, no loop)
static void wrap_region(const JbTrack &t, uint32_t &ls, uint32_t &le)
{
    if (t.loop && t.loop_end > t.loop_start) {
        ls = t.loop_start;
        le = t.loop_end;
    } else {
        ls = 0;
        le = t.frames;
    }
}

uint32_t jb_source_frame(const JbTrack &t, const JbPlanSpec &p, uint64_t pf)
{
    if (!jb_plan_wraps(t, p)) {
        return (uint32_t)std::min<uint64_t>(pf, t.frames);
    }
    uint32_t ls, le;
    wrap_region(t, ls, le);
    if (le <= ls || pf < le) {
        return (uint32_t)std::min<uint64_t>(pf, t.frames);
    }
    return ls + (uint32_t)((pf - ls) % (uint64_t)(le - ls));
}

uint32_t jb_loops_done(const JbTrack &t, const JbPlanSpec &p, uint64_t pf)
{
    if (!jb_plan_wraps(t, p)) {
        return 0;
    }
    uint32_t ls, le;
    wrap_region(t, ls, le);
    if (le <= ls || pf < ls) {
        return 0;
    }
    return (uint32_t)std::min<uint64_t>((pf - ls) / (uint64_t)(le - ls), 0xFFFFFFFFu);
}

// ---- gain ---------------------------------------------------------------------------------------------------------
static double clamp01(double v)
{
    return std::isfinite(v) ? std::max(0.0, std::min(1.0, v)) : 0.0;
}

void jb_spatial(const float eye[3], const float fwd[3], const float up[3], const float pos[3], double radius,
                float &gain, float &pan)
{
    // libsa1 sa1_audio_mix.c spatial(): CC7 = 106 - 127 f over [near, far], gain (CC7 / 106)^2, pan 0.6 x the
    // listener's right component; near = far / 30 (the game's SA1A_NEAR 20 / SA1A_FAR 600)
    double far_d = std::isfinite(radius) && radius > 0.0 ? radius : 0.0;
    double near_d = far_d / 30.0;
    double dx = (double)pos[0] - eye[0], dy = (double)pos[1] - eye[1], dz = (double)pos[2] - eye[2];
    double d = std::sqrt(dx * dx + dy * dy + dz * dz);
    double g = 1.0, p = 0.0;
    if (far_d <= 0.0) {
        g = 0.0;
    } else if (d > near_d) {
        double f = far_d > near_d ? (d - near_d) / (far_d - near_d) : 1.0;
        if (f > 1.0) {
            f = 1.0;
        }
        double cc = 106.0 - 127.0 * f;
        g = cc > 0.0 ? (cc / 106.0) * (cc / 106.0) : 0.0;
    }
    double r[3] = {(double)fwd[1] * up[2] - (double)fwd[2] * up[1], (double)fwd[2] * up[0] - (double)fwd[0] * up[2],
                   (double)fwd[0] * up[1] - (double)fwd[1] * up[0]};
    double rl = std::sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2]);
    if (d > 1e-3 && rl > 1e-6) {
        p = 0.6 * (dx * r[0] + dy * r[1] + dz * r[2]) / (rl * d);
    }
    gain = (float)g;
    pan = (float)std::max(-1.0, std::min(1.0, p));
}

double jb_gain(double volume, double gmod_volume, int32_t gvol, double music_volume, double spatial)
{
    double g = clamp01(volume) * kJukeboxReference;
    if (gvol < 0 || gvol == 10000) {
        g *= clamp01(gmod_volume);      // GMod does not scale BASS's streams itself (gsa1.AudioUpdate's rule)
    }
    return g * clamp01(music_volume) * clamp01(spatial);
}

// ---- the worker's side ------------------------------------------------------------------------------------------
namespace {

// the private context's callbacks: counts the allocations (status memory, the shutdown balance), forwards to the
// caller's (tests) allocator and files, prefixes the log
struct Hooks {
    sa1_host orig;
    bool have_orig = false;
    AudioLogFn log = nullptr;
    void *log_user = nullptr;
    std::atomic<int64_t> bytes{0}, blocks{0};
};

const size_t kHdr = 16;     // keeps the caller's alignment for any C type

void hk_log(void *u, int32_t level, const char *msg)
{
    Hooks *h = (Hooks *)u;
    if (h->log) {
        std::string s = std::string("jukebox: ") + (msg ? msg : "");
        h->log(h->log_user, level, s.c_str());
    }
}

void *hk_alloc(void *u, size_t size)
{
    Hooks *h = (Hooks *)u;
    void *b = (h->have_orig && h->orig.alloc) ? h->orig.alloc(h->orig.user, size + kHdr) : std::malloc(size + kHdr);
    if (!b) {
        return nullptr;
    }
    std::memcpy(b, &size, sizeof size);
    h->bytes += (int64_t)size;
    h->blocks++;
    return (char *)b + kHdr;
}

void hk_free(void *u, void *p)
{
    if (!p) {
        return;
    }
    Hooks *h = (Hooks *)u;
    char *b = (char *)p - kHdr;
    size_t size;
    std::memcpy(&size, b, sizeof size);
    h->bytes -= (int64_t)size;
    h->blocks--;
    if (h->have_orig && h->orig.free) {
        h->orig.free(h->orig.user, b);
    } else {
        std::free(b);
    }
}

void *hk_open(void *u, const char *path)
{
    Hooks *h = (Hooks *)u;
    return h->orig.file_open(h->orig.user, path);
}

int32_t hk_size(void *u, void *f, uint64_t *size)
{
    Hooks *h = (Hooks *)u;
    return h->orig.file_size(h->orig.user, f, size);
}

int32_t hk_read(void *u, void *f, uint64_t off, void *buf, size_t n)
{
    Hooks *h = (Hooks *)u;
    return h->orig.file_read(h->orig.user, f, off, buf, n);
}

void hk_close(void *u, void *f)
{
    Hooks *h = (Hooks *)u;
    h->orig.file_close(h->orig.user, f);
}

struct WChan {
    int32_t music = -1;
    const JbTrack *tr = nullptr;
    JbPlanSpec spec;
    JbState state = JbState::Idle;
    std::string error;
    uint64_t end = kJbForever;
    sa1_audio_stream *stream = nullptr;
    int32_t stream_music = -1;
    // the BASS stream (the worker's alone)
    uint32_t h = 0;
    bool h_playing = false;         // BASS_ChannelPlay was called on h
    bool h_paused = false;          // BASS-paused now
    uint64_t start_frame = 0;       // plan frame of h's first frame
    uint64_t next = 0;              // plan frame of the next frame to decode
    uint64_t pushed = 0;            // frames pushed into h
    uint32_t queued = 0;            // frames queued in BASS (last measured)
    bool end_sent = false;
    bool stalled = false;
    float vol_applied = -1.0f, pan_applied = -9.0f;
    // what the channel was asked for
    bool user_paused = false;
    bool want_open = false;         // an open (or a re-position of the open stream) is pending
    double start_s = 0.0, call = 0.0;   // the plan time asked for and the module clock of the call
    double fade_in_once = 0.0;      // seconds of fade-in from start_frame (play: fade_in; seek: 0.03 against a click)
    int create_failures = 0;
    double retry_at = 0.0;
    uint64_t gen = 0;
};

struct Dying {
    uint32_t h;
    double free_at;
};

}  // namespace

struct Jukebox::Impl {
    Hooks hooks;
    sa1_host host;
    sa1_context *ctx = nullptr;
    sa1_audio *audio = nullptr;
    const BassApi *bass = nullptr;
    std::vector<JbTrack> tracks;
    std::vector<int32_t> index;
    uint32_t music_count = 0;
    WChan ch[kJukeboxChannels];
    std::vector<Dying> dying;
    std::vector<int16_t> buf;
    // the mailbox's targets, copied every wake
    Target tgt[kJukeboxChannels];
    bool have_listener = false;
    float eye[3] = {0, 0, 0}, fwd[3] = {1, 0, 0}, up[3] = {0, 0, 1};
    double gmod_volume = 1.0, music_volume = 1.0;
    bool game_paused = false;
    int32_t gvol = -1;
    double queue_s = 3.0, block_s = 0.25;
    uint64_t opens = 0, underruns = 0, recoveries = 0;
    double max_open_ms = 0.0, list_ms = 0.0;
    bool failed = false, ready = false, titles = false;
    uint32_t listed = 0;
    std::string error, bass_error;
    int next_open = 0;

    void log(int32_t level, const std::string &m) { hk_log(&hooks, level, m.c_str()); }
    static double clock() { return now_ms() / 1000.0; }

    void retire(WChan &c, double fade_s, double now)
    {
        if (!c.h) {
            return;
        }
        if (bass) {
            if (c.h_playing && !c.h_paused) {
                // slide the old stream to 0 and free it then: no queue flush, no click (jukebox.md 6.3)
                uint32_t ms = (uint32_t)std::llround(std::max(0.05, fade_s) * 1000.0);
                bass->ChannelSlideAttribute(c.h, bass::kAttribVol, 0.0f, ms);
                dying.push_back({c.h, now + ms / 1000.0 + 0.03});
            } else {
                bass->StreamFree(c.h);      // never heard or paused: nothing to fade
            }
        }
        c.h = 0;
        c.h_playing = c.h_paused = false;
        c.vol_applied = -1.0f;
        c.pan_applied = -9.0f;
        c.stalled = false;
        c.queued = 0;
        c.pushed = 0;
        c.end_sent = false;
    }

    void close_stream(WChan &c)
    {
        if (c.stream) {
            sa1_audio_stream_close(c.stream);
            c.stream = nullptr;
        }
        c.stream_music = -1;
    }

    void fail(WChan &c, int i, const std::string &msg, double now)
    {
        retire(c, 0.05, now);
        close_stream(c);
        c.state = JbState::Failed;
        c.error = msg;
        c.want_open = false;
        log(SA1_LOG_WARN, format("channel %d: %s", i, msg.c_str()));
    }

    void ended(WChan &c, double now)
    {
        retire(c, 0.05, now);
        close_stream(c);            // a finished track does not keep its file in memory
        c.state = JbState::Ended;
        c.want_open = false;
    }

    uint64_t frame_at(const WChan &c, double now) const
    {
        double t = c.start_s + std::max(0.0, now - c.call);
        return (uint64_t)std::llround(std::max(0.0, t) * (double)c.tr->rate);
    }

    // the plan frame the listener hears now (last measurement)
    uint64_t heard(const WChan &c) const
    {
        if (c.h) {
            return c.start_frame + c.pushed - std::min<uint64_t>(c.pushed, c.queued);
        }
        if (c.state == JbState::Ended && c.end != kJbForever) {
            return c.end;
        }
        return c.tr ? (uint64_t)std::llround(std::max(0.0, c.start_s) * (double)c.tr->rate) : 0u;
    }

    void target(int i, float &g, float &p) const
    {
        const Target &t = tgt[i];
        float sg = 1.0f, sp = 0.0f;
        if (t.placed) {
            if (have_listener) {
                jb_spatial(eye, fwd, up, t.pos, t.radius, sg, sp);
            }
        }
        g = (float)jb_gain(t.volume, gmod_volume, gvol, music_volume, sg);
        p = sp;
    }

    // ---- commands ----
    void reposition(WChan &c, double t, double call, double fade_in, double now)
    {
        if (!c.tr) {
            return;
        }
        c.gen++;
        if (c.want_open && !c.h) {
            c.start_s = std::max(0.0, t);
            c.call = call;
            c.fade_in_once = fade_in;
            return;
        }
        retire(c, 0.05, now);
        c.start_s = std::max(0.0, t);
        c.call = call;
        c.fade_in_once = fade_in;
        c.want_open = true;
        c.create_failures = 0;
        c.retry_at = 0.0;
        if (c.state == JbState::Ended) {
            c.state = JbState::Loading;
        }
    }

    void cmd(const Cmd &k, double now)
    {
        WChan &c = ch[k.ch];
        switch (k.type) {
        case Cmd::Play: {
            retire(c, 0.05, now);
            if (c.stream && c.stream_music != (int32_t)k.music) {
                close_stream(c);
            }
            c.gen++;
            c.music = (int32_t)k.music;
            c.spec = k.spec;
            c.user_paused = false;
            c.error.clear();
            c.want_open = false;
            c.create_failures = 0;
            c.retry_at = 0.0;
            c.tr = nullptr;
            int32_t idx = k.music < index.size() ? index[k.music] : -1;
            if (idx < 0) {
                const char *name = audio && k.music < music_count ? sa1_audio_music_name(audio, k.music) : nullptr;
                fail(c, k.ch,
                     k.music < music_count ? format("music %u (%s) is not on your disc", (unsigned)k.music, name ? name : "?")
                                           : format("music %u does not exist (0..%u)", (unsigned)k.music,
                                                    (unsigned)(music_count ? music_count - 1 : 0)),
                     now);
                return;
            }
            c.tr = &tracks[(size_t)idx];
            c.end = jb_plan_end(*c.tr, c.spec);
            c.start_s = std::max(0.0, k.t);
            c.call = k.call;
            c.fade_in_once = c.spec.fade_in;
            c.state = JbState::Loading;
            c.want_open = true;
            if (c.end != kJbForever && (uint64_t)std::llround(c.start_s * c.tr->rate) >= c.end) {
                ended(c, now);      // a late joiner of a finished track
            }
            return;
        }
        case Cmd::Stop:
            retire(c, k.fade, now);
            close_stream(c);
            c.gen++;
            c.state = JbState::Idle;
            c.music = -1;
            c.tr = nullptr;
            c.want_open = false;
            c.user_paused = false;
            c.error.clear();
            return;
        case Cmd::Pause:
            c.user_paused = k.paused;
            if (c.state == JbState::Playing && k.paused) {
                c.state = JbState::Paused;
            } else if (c.state == JbState::Paused && !k.paused) {
                c.state = JbState::Playing;
            }
            return;
        case Cmd::Seek:
            if (c.tr && c.state != JbState::Idle && c.state != JbState::Failed) {
                reposition(c, k.t, k.call, 0.03, now);
            }
            return;
        case Cmd::Sync: {
            if (!c.tr || c.state == JbState::Idle || c.state == JbState::Failed) {
                return;
            }
            if (c.want_open && !c.h) {
                c.start_s = std::max(0.0, k.t);
                c.call = k.call;
                return;
            }
            double expected = k.t + std::max(0.0, now - k.call);
            if (c.h) {
                measure(c, k.ch, now);
            }
            double cur = (double)heard(c) / c.tr->rate;
            if (std::fabs(cur - expected) > 0.25 &&
                (c.end == kJbForever || (uint64_t)std::llround(expected * c.tr->rate) < c.end)) {
                reposition(c, k.t, k.call, 0.03, now);
            }
            return;
        }
        }
    }

    // ---- decoding and feeding ----
    // n frames of the plan from the decoder (which stands at the source frame of c.next)
    sa1_status decode(WChan &c, int16_t *out, uint32_t n)
    {
        bool wraps = jb_plan_wraps(*c.tr, c.spec);
        int32_t loop = (wraps && c.tr->loop) ? 1 : 0;
        uint32_t done = 0;
        int restarts = 0;
        while (done < n) {
            uint32_t got = 0;
            sa1_status st = sa1_audio_stream_read(c.stream, out + (size_t)done * 2u, n - done, loop, &got);
            if (st != SA1_OK) {
                return st;
            }
            done += got;
            if (done < n) {
                if (wraps && !c.tr->loop && restarts < 4) {
                    restarts++;
                    st = sa1_audio_stream_seek(c.stream, 0);   // "forever" without a loop: from the start again
                    if (st != SA1_OK) {
                        return st;
                    }
                    continue;
                }
                std::memset(out + (size_t)done * 2u, 0, (size_t)(n - done) * 4u);   // past the file's end
                break;
            }
        }
        return SA1_OK;
    }

    void envelope(const WChan &c, int16_t *pcm, uint32_t n) const
    {
        double rate = c.tr->rate;
        double fi = std::max(0.0, c.fade_in_once) * rate;
        uint64_t fo = 0, fo_start = kJbForever;
        if (c.spec.plan == JbPlan::Loops && c.tr->loop && c.end != kJbForever) {
            fo = fade_frames(c.spec.fade_out, c.tr->rate);
            if (fo > 0) {
                fo_start = c.end - std::min(fo, c.end);
            }
        }
        bool in_fade = fi > 0.0 && (double)(c.next - c.start_frame) < fi;
        bool out_fade = fo > 0 && c.next + n > fo_start;
        if (!in_fade && !out_fade) {
            return;
        }
        for (uint32_t i = 0; i < n; i++) {
            uint64_t p = c.next + i;
            double g = 1.0;
            if (in_fade) {
                double k = (double)(p - c.start_frame);
                if (k < fi) {
                    g *= k / fi;
                }
            }
            if (out_fade && p >= fo_start) {
                g *= (double)(c.end > p ? c.end - p : 0) / (double)fo;
            }
            if (g < 1.0) {
                pcm[2 * i] = (int16_t)std::lrint(pcm[2 * i] * g);
                pcm[2 * i + 1] = (int16_t)std::lrint(pcm[2 * i + 1] * g);
            }
        }
    }

    void on_bass_error(WChan &c, int i, int code, double now)
    {
        // GMod freed or re-initialised BASS, or the stream broke: re-create it where the listener was (Review G10)
        recoveries++;
        uint64_t pf = heard(c);
        error = format("BASS error %d on jukebox channel %d: its stream was re-created", code, i);
        log(SA1_LOG_WARN, format("channel %d: BASS error %d; re-creating its stream at %.2f s", i, code,
                                 (double)pf / c.tr->rate));
        if (bass && c.h) {
            bass->StreamFree(c.h);  // may fail (an invalid handle): nothing else to do with it
        }
        c.h = 0;
        c.h_playing = c.h_paused = false;
        c.vol_applied = -1.0f;
        c.pan_applied = -9.0f;
        c.stalled = false;
        c.queued = 0;
        c.pushed = 0;
        c.end_sent = false;
        c.start_s = (double)pf / c.tr->rate;
        c.call = now;
        c.fade_in_once = 0.03;
        c.want_open = true;
    }

    void fill(WChan &c, int i, double now)
    {
        if (!c.h || c.end_sent || !c.stream) {
            return;
        }
        uint32_t rate = c.tr->rate;
        uint64_t target = (uint64_t)(queue_s * rate);
        uint32_t block = std::max<uint32_t>(32u, (uint32_t)(block_s * rate));
        uint64_t q = c.queued;
        while (q < target && !c.end_sent) {
            uint64_t want = std::min<uint64_t>(block, target - q);
            if (c.end != kJbForever) {
                want = std::min<uint64_t>(want, c.end - c.next);
            }
            bool last = c.end != kJbForever && c.next + want >= c.end;
            if (want > 0) {
                buf.resize((size_t)want * 2u);
                sa1_status st = decode(c, buf.data(), (uint32_t)want);
                if (st != SA1_OK) {
                    fail(c, i, format("music %d (%s): disc read failed: %s", (int)c.music, c.tr->file.c_str(),
                                      sa1_status_string(st)), now);
                    return;
                }
                envelope(c, buf.data(), (uint32_t)want);
            } else {
                buf.assign(2, 0);
            }
            uint32_t r = bass->StreamPutData(c.h, buf.data(), (uint32_t)(want * 4u) | (last ? bass::kStreamEnd : 0u));
            if (r == bass::kFail) {
                on_bass_error(c, i, bass->ErrorGetCode(), now);
                return;
            }
            c.next += want;
            c.pushed += want;
            q = r / 4u;
            c.queued = (uint32_t)std::min<uint64_t>(q, 0x7FFFFFFFu);
            if (last) {
                c.end_sent = true;
            }
        }
    }

    // reads the stream's queue and state; false when it had to be re-created
    bool measure(WChan &c, int i, double now)
    {
        uint32_t q = bass->StreamPutData(c.h, nullptr, 0);
        if (q == bass::kFail) {
            on_bass_error(c, i, bass->ErrorGetCode(), now);
            return false;
        }
        uint32_t b = bass->ChannelGetData(c.h, nullptr, bass::kDataAvailable);
        uint64_t bytes = (uint64_t)q + (b == bass::kFail ? 0u : b);
        c.queued = (uint32_t)std::min<uint64_t>(bytes / 4u, 0x7FFFFFFFu);
        return true;
    }

    void poll(WChan &c, int i, double now)
    {
        if (!c.h) {
            return;
        }
        if (!measure(c, i, now)) {
            return;
        }
        uint32_t act = bass->ChannelIsActive(c.h);
        bool should = c.h_playing && !c.h_paused;
        if (should && act == bass::kActiveStalled) {
            if (!c.stalled) {
                c.stalled = true;
                underruns++;
                log(SA1_LOG_INFO, format("channel %d: underrun (the queue ran dry)", i));
            }
        } else if (act == bass::kActivePlaying) {
            c.stalled = false;
        }
        if (c.end_sent && should && act == bass::kActiveStopped && c.queued == 0) {
            ended(c, now);
        }
    }

    void apply_pause(WChan &c)
    {
        if (!c.h) {
            return;
        }
        bool hold = c.user_paused || game_paused;
        if (hold) {
            if (c.h_playing && !c.h_paused) {
                bass->ChannelPause(c.h);
                c.h_paused = true;
            }
        } else if (!c.h_playing) {
            if (c.pushed > 0 || c.end_sent) {
                bass->ChannelPlay(c.h, 0);
                c.h_playing = true;
            }
        } else if (c.h_paused) {
            bass->ChannelPlay(c.h, 0);
            c.h_paused = false;
        }
    }

    void apply_attributes(WChan &c, int i)
    {
        if (!c.h) {
            return;
        }
        float g, p;
        target(i, g, p);
        if (std::fabs(g - c.vol_applied) > 1e-4f) {
            bass->ChannelSlideAttribute(c.h, bass::kAttribVol, g, 100);
            c.vol_applied = g;
        }
        if (std::fabs(p - c.pan_applied) > 1e-4f) {
            bass->ChannelSlideAttribute(c.h, bass::kAttribPan, p, 100);
            c.pan_applied = p;
        }
    }

    // the blocking part: a stream open (lazy: 2 sectors) and the seek to the start (reads the file up to it)
    void open(WChan &c, int i)
    {
        double t0 = now_ms();
        if (!bass) {
            fail(c, i, bass_error, clock());
            return;
        }
        if (c.tr->channels != 2) {
            fail(c, i, format("music %d (%s) is not stereo", (int)c.music, c.tr->file.c_str()), clock());
            return;
        }
        if (!c.stream) {
            sa1_audio_stream_info info;
            std::memset(&info, 0, sizeof info);
            info.struct_size = sizeof info;
            sa1_status st = sa1_audio_stream_open(audio, SA1_AUDIO_SOURCE_MUSIC, (uint32_t)c.music, &c.stream, &info);
            if (st != SA1_OK || !c.stream) {
                c.stream = nullptr;
                fail(c, i, format("music %d (%s): %s", (int)c.music, c.tr->file.c_str(), sa1_status_string(st)), clock());
                return;
            }
            c.stream_music = c.music;
            opens++;
        }
        double now = clock();
        uint64_t pf = frame_at(c, now);
        if (c.end != kJbForever && pf >= c.end) {
            ended(c, now);
            return;
        }
        sa1_status st = sa1_audio_stream_seek(c.stream, jb_source_frame(*c.tr, c.spec, pf));
        if (st != SA1_OK) {
            fail(c, i, format("music %d (%s): disc read failed: %s", (int)c.music, c.tr->file.c_str(), sa1_status_string(st)),
                 clock());
            return;
        }
        // start anchoring (Review G3): the start frame is the plan time when pushing begins; what the seek took is
        // decoded and dropped
        c.next = pf;
        c.start_frame = pf;
        uint64_t pf2 = frame_at(c, clock());
        if (c.end != kJbForever && pf2 >= c.end) {
            ended(c, clock());
            return;
        }
        while (c.next < pf2) {
            uint32_t n = (uint32_t)std::min<uint64_t>(pf2 - c.next, 8192u);
            buf.resize((size_t)n * 2u);
            st = decode(c, buf.data(), n);
            if (st != SA1_OK) {
                fail(c, i, format("music %d (%s): disc read failed: %s", (int)c.music, c.tr->file.c_str(),
                                  sa1_status_string(st)), clock());
                return;
            }
            c.next += n;
        }
        c.start_frame = c.next;
        std::string err;
        uint32_t h = bass->GetDevice() == bass::kFail ? 0u : bass_push_stream(bass, c.tr->rate, err);
        if (!h) {
            if (err.empty()) {
                err = "Garry's Mod's BASS has no output device (not initialised)";
            }
            c.create_failures++;
            c.error = err;
            error = err;
            if (c.create_failures >= 5) {
                fail(c, i, err, clock());
            } else {
                c.retry_at = clock() + 1.0;
                log(SA1_LOG_WARN, format("channel %d: %s (retrying)", i, err.c_str()));
            }
            return;
        }
        c.create_failures = 0;
        c.retry_at = 0.0;
        c.h = h;
        c.pushed = 0;
        c.queued = 0;
        c.end_sent = false;
        c.h_playing = c.h_paused = false;
        c.stalled = false;
        // Review G1: the current gain and pan before the first BASS_ChannelPlay
        float g, p;
        target(i, g, p);
        bass->ChannelSetAttribute(h, bass::kAttribVol, g);
        bass->ChannelSetAttribute(h, bass::kAttribPan, p);
        c.vol_applied = g;
        c.pan_applied = p;
        c.want_open = false;
        if (c.state == JbState::Loading || c.state == JbState::Ended) {
            c.state = c.user_paused ? JbState::Paused : JbState::Playing;
        }
        c.error.clear();
        double ms = now_ms() - t0;
        max_open_ms = std::max(max_open_ms, ms);
        fill(c, i, clock());
        apply_pause(c);
        if (c.h) {
            log(SA1_LOG_INFO, format("channel %d: music %d %s from %.2f s (%s, %u Hz) in %.1f ms", i, (int)c.music,
                                     c.tr->file.c_str(), (double)c.start_frame / c.tr->rate, jb_plan_name(c.spec.plan),
                                     (unsigned)c.tr->rate, ms));
        }
    }

    bool open_one(double now)
    {
        for (int k = 0; k < kJukeboxChannels; k++) {
            int i = (next_open + k) % kJukeboxChannels;
            WChan &c = ch[i];
            if (!c.want_open || !c.tr || now < c.retry_at) {
                continue;
            }
            next_open = (i + 1) % kJukeboxChannels;
            open(c, i);
            return true;
        }
        return false;
    }

    void free_dying(double now, bool all)
    {
        size_t w = 0;
        for (size_t r = 0; r < dying.size(); r++) {
            if (all || now >= dying[r].free_at) {
                if (bass) {
                    bass->StreamFree(dying[r].h);
                }
            } else {
                dying[w++] = dying[r];
            }
        }
        dying.resize(w);
    }

    JbChannelInfo info(int i) const
    {
        const WChan &c = ch[i];
        JbChannelInfo s;
        s.music = c.state == JbState::Idle ? -1 : c.music;
        s.state = c.state;
        s.spec = c.spec;
        s.error = c.error;
        s.paused = c.user_paused;
        s.placed = tgt[i].placed;
        s.volume = tgt[i].volume;
        s.gain = c.vol_applied < 0.0f ? 0.0 : c.vol_applied;
        s.generation = c.gen;
        s.handle = c.h;
        s.snapshot_ms = now_ms();
        if (c.tr && c.state != JbState::Idle) {
            double rate = c.tr->rate;
            uint64_t pf = heard(c);
            s.rate = c.tr->rate;
            s.length = c.tr->seconds();
            s.plan_length = c.end == kJbForever ? 0.0 : (double)c.end / rate;
            s.position = (double)pf / rate;
            s.track_position = (double)jb_source_frame(*c.tr, c.spec, pf) / rate;
            s.loops_done = jb_loops_done(*c.tr, c.spec, pf);
            s.queued = c.h ? (double)c.queued / rate : 0.0;
            s.start_frame = c.start_frame;
        }
        return s;
    }
};

// ---- Jukebox: the Lua thread's side ---------------------------------------------------------------------------------
Jukebox::Jukebox() : impl_(new Impl()) {}

Jukebox::~Jukebox()
{
    shutdown();
}

double Jukebox::clock_s() const
{
    return now_ms() / 1000.0;
}

bool Jukebox::start(const JukeboxConfig &cfg, std::string &err)
{
    shutdown();
    if (cfg.gdi.empty()) {
        err = "no disc is configured";
        return false;
    }
    cfg_ = cfg;
    impl_.reset(new Impl());
    {
        std::lock_guard<std::mutex> g(m_);
        sh_.cmds.clear();
        sh_.quit = false;
        sh_.kicks++;
    }
    {
        std::lock_guard<std::mutex> g(snap_m_);
        for (int i = 0; i < kJukeboxChannels; i++) {
            snap_[i] = JbChannelInfo();
        }
        status_ = JbStatusInfo();
        status_.started = true;
        status_.backend = cfg.bass ? bass_name(cfg.bass) : "none";
        list_.reset();
        index_.clear();
        music_count_ = 0;
    }
    started_ = true;
    worker_.reset(new Worker());
    worker_->start([this]() { run(); });
    return true;
}

void Jukebox::shutdown()
{
    if (!started_) {
        return;
    }
    {
        std::lock_guard<std::mutex> g(m_);
        sh_.quit = true;
    }
    cv_.notify_all();
    if (worker_) {
        worker_->join();
        worker_.reset();
    }
    started_ = false;
    std::lock_guard<std::mutex> g(snap_m_);
    status_.started = false;
    status_.ready = false;
    status_.active = 0;
    status_.memory_mb = (double)impl_->hooks.bytes.load() / 1048576.0;
    status_.memory_blocks = impl_->hooks.blocks.load();
    for (int i = 0; i < kJukeboxChannels; i++) {
        snap_[i] = JbChannelInfo();
    }
    list_.reset();
    index_.clear();
}

void Jukebox::post(const Cmd &c)
{
    {
        std::lock_guard<std::mutex> g(m_);
        sh_.cmds.push_back(c);
        sh_.kicks++;
    }
    cv_.notify_all();
}

int Jukebox::tracks(std::shared_ptr<const std::vector<JbTrack>> &out, std::string &msg) const
{
    std::lock_guard<std::mutex> g(snap_m_);
    if (list_) {
        out = list_;
        return 1;
    }
    if (status_.failed) {
        msg = status_.error;
        return -1;
    }
    msg = started_ ? "loading" : "the jukebox is not started";
    return started_ ? 0 : -1;
}

static bool ch_ok(int ch)
{
    return ch >= 0 && ch < kJukeboxChannels;
}

bool Jukebox::play(int ch, uint32_t music, double start_s, const JbPlanSpec &spec, double call_time_s, std::string &err)
{
    if (!started_) {
        err = "the jukebox is not started";
        return false;
    }
    if (!ch_ok(ch)) {
        err = format("channel %d: 0..%d", ch, kJukeboxChannels - 1);
        return false;
    }
    if (!std::isfinite(start_s) || start_s < 0.0 || !std::isfinite(call_time_s) || !std::isfinite(spec.fade_in) ||
        !std::isfinite(spec.fade_out) || spec.fade_in < 0.0 || spec.fade_out < 0.0 || spec.loops < 1) {
        err = "bad plan";
        return false;
    }
    Cmd c;
    c.type = Cmd::Play;
    c.ch = ch;
    c.music = music;
    c.spec = spec;
    c.t = start_s;
    c.call = call_time_s;
    post(c);
    std::lock_guard<std::mutex> g(snap_m_);
    if (list_ && (music >= index_.size() || index_[music] < 0)) {
        err = music < music_count_ ? format("music %u is not on your disc", (unsigned)music)
                                   : format("music %u does not exist (0..%u)", (unsigned)music,
                                            (unsigned)(music_count_ ? music_count_ - 1 : 0));
        return false;
    }
    return true;
}

bool Jukebox::stop(int ch, double fade_s)
{
    if (!started_ || !ch_ok(ch)) {
        return false;
    }
    Cmd c;
    c.type = Cmd::Stop;
    c.ch = ch;
    c.fade = std::isfinite(fade_s) ? std::max(0.0, std::min(60.0, fade_s)) : 0.0;
    post(c);
    return true;
}

bool Jukebox::pause(int ch, bool paused)
{
    if (!started_ || !ch_ok(ch)) {
        return false;
    }
    Cmd c;
    c.type = Cmd::Pause;
    c.ch = ch;
    c.paused = paused;
    post(c);
    return true;
}

bool Jukebox::seek(int ch, double t_s)
{
    if (!started_ || !ch_ok(ch) || !std::isfinite(t_s) || t_s < 0.0) {
        return false;
    }
    Cmd c;
    c.type = Cmd::Seek;
    c.ch = ch;
    c.t = t_s;
    c.call = clock_s();
    post(c);
    return true;
}

bool Jukebox::sync(int ch, double t_s, double call_time_s)
{
    if (!started_ || !ch_ok(ch) || !std::isfinite(t_s) || t_s < 0.0 || !std::isfinite(call_time_s)) {
        return false;
    }
    Cmd c;
    c.type = Cmd::Sync;
    c.ch = ch;
    c.t = t_s;
    c.call = call_time_s;
    post(c);
    return true;
}

bool Jukebox::volume(int ch, double v)
{
    if (!ch_ok(ch) || !std::isfinite(v)) {
        return false;
    }
    {
        std::lock_guard<std::mutex> g(m_);
        sh_.tgt[ch].volume = std::max(0.0, std::min(1.0, v));
        sh_.kicks++;
    }
    cv_.notify_all();
    return true;
}

bool Jukebox::place(int ch, const float pos[3], double radius)
{
    if (!ch_ok(ch) || !std::isfinite(pos[0]) || !std::isfinite(pos[1]) || !std::isfinite(pos[2]) ||
        !std::isfinite(radius) || radius <= 0.0) {
        return false;
    }
    std::lock_guard<std::mutex> g(m_);
    sh_.tgt[ch].placed = true;
    std::memcpy(sh_.tgt[ch].pos, pos, sizeof sh_.tgt[ch].pos);
    sh_.tgt[ch].radius = radius;
    return true;
}

bool Jukebox::place_2d(int ch)
{
    if (!ch_ok(ch)) {
        return false;
    }
    std::lock_guard<std::mutex> g(m_);
    sh_.tgt[ch].placed = false;
    sh_.kicks++;
    return true;
}

int Jukebox::update(const float eye[3], const float fwd[3], const float up[3], double gmod_volume, double music_volume,
                    bool paused)
{
    Target tgt[kJukeboxChannels];
    float le[3], lf[3], lu[3];
    bool listener, kicked = false;
    {
        std::lock_guard<std::mutex> g(m_);
        if (eye && fwd && up && std::isfinite(eye[0] + eye[1] + eye[2] + fwd[0] + fwd[1] + fwd[2] + up[0] + up[1] + up[2])) {
            std::memcpy(sh_.eye, eye, sizeof sh_.eye);
            std::memcpy(sh_.fwd, fwd, sizeof sh_.fwd);
            std::memcpy(sh_.up, up, sizeof sh_.up);
            sh_.have_listener = true;
        }
        sh_.gmod_volume = std::isfinite(gmod_volume) ? std::max(0.0, std::min(1.0, gmod_volume)) : 1.0;
        sh_.music_volume = std::isfinite(music_volume) ? std::max(0.0, std::min(1.0, music_volume)) : 1.0;
        if (sh_.game_paused != paused) {
            sh_.game_paused = paused;
            sh_.kicks++;
            kicked = true;
        }
        for (int i = 0; i < kJukeboxChannels; i++) {
            tgt[i] = sh_.tgt[i];
        }
        listener = sh_.have_listener;
        std::memcpy(le, sh_.eye, sizeof le);
        std::memcpy(lf, sh_.fwd, sizeof lf);
        std::memcpy(lu, sh_.up, sizeof lu);
        gmod_volume = sh_.gmod_volume;
        music_volume = sh_.music_volume;
    }
    if (kicked) {
        cv_.notify_all();       // the pause acts at once; the listener and volumes are taken at the next wake (20 ms)
    }
    if (paused) {
        return 0;
    }
    // audible: playing (not paused) with a gain above 0.05 (the addon ducks the game's music while one is)
    int n = 0;
    std::lock_guard<std::mutex> g(snap_m_);
    for (int i = 0; i < kJukeboxChannels; i++) {
        if (snap_[i].state != JbState::Playing) {
            continue;
        }
        float sg = 1.0f, sp = 0.0f;
        if (tgt[i].placed && listener) {
            jb_spatial(le, lf, lu, tgt[i].pos, tgt[i].radius, sg, sp);
        }
        n += jb_gain(tgt[i].volume, gmod_volume, status_.gvol, music_volume, sg) > 0.05;
    }
    return n;
}

JbChannelInfo Jukebox::state(int ch) const
{
    if (!ch_ok(ch)) {
        return JbChannelInfo();
    }
    bool game_paused;
    {
        std::lock_guard<std::mutex> g(m_);
        game_paused = sh_.game_paused;
    }
    std::lock_guard<std::mutex> g(snap_m_);
    JbChannelInfo s = snap_[ch];
    if (s.state == JbState::Playing && !game_paused && s.rate) {
        // the worker measures every 20 ms; between its snapshots the music moved on
        double dt = std::min(std::max(0.0, (now_ms() - s.snapshot_ms) / 1000.0), s.queued);
        s.position += dt;
        if (list_ && s.music >= 0 && (size_t)s.music < index_.size() && index_[(size_t)s.music] >= 0) {
            const JbTrack &t = (*list_)[(size_t)index_[(size_t)s.music]];
            uint64_t pf = (uint64_t)std::llround(s.position * t.rate);
            s.track_position = (double)jb_source_frame(t, s.spec, pf) / t.rate;
            s.loops_done = jb_loops_done(t, s.spec, pf);
        }
    }
    return s;
}

JbStatusInfo Jukebox::status() const
{
    std::lock_guard<std::mutex> g(snap_m_);
    return status_;
}

// ---- the worker -----------------------------------------------------------------------------------------------------
void Jukebox::run()
{
    Impl &I = *impl_;
    I.bass = cfg_.bass;
    bool acquired = false;
    if (!I.bass && cfg_.acquire_bass) {
        // the module's way: BASS is bound here, so every BASS call of the jukebox is made on this thread
        I.bass = bass_acquire(I.bass_error);
        acquired = I.bass != nullptr;
    }
    if (!I.bass && I.bass_error.empty()) {
        I.bass_error = "Garry's Mod's BASS audio library is not loaded in this process";
    }
    {
        std::lock_guard<std::mutex> g(snap_m_);
        status_.backend = I.bass ? bass_name(I.bass) : "none (" + I.bass_error + ")";
    }
    I.queue_s = std::max(0.5, cfg_.queue_s);
    I.block_s = std::max(0.02, std::min(I.queue_s, cfg_.block_s));
    double wake = std::max(1.0, cfg_.wake_ms);
    I.hooks.log = cfg_.log;
    I.hooks.log_user = cfg_.log_user;
    sa1_host_defaults(&I.host);
    if (cfg_.host) {
        I.hooks.orig = *cfg_.host;
        I.hooks.have_orig = true;
    }
    I.host.user = &I.hooks;
    I.host.log = hk_log;
    I.host.log_level = SA1_LOG_INFO;
    I.host.alloc = hk_alloc;
    I.host.free = hk_free;
    if (I.hooks.have_orig && I.hooks.orig.file_open) {
        I.host.file_open = hk_open;
        I.host.file_size = hk_size;
        I.host.file_read = hk_read;
        I.host.file_close = hk_close;
    }
    auto quitting = [this]() {
        std::lock_guard<std::mutex> g(m_);
        return sh_.quit;
    };
    auto publish = [this, &I]() {
        JbChannelInfo s[kJukeboxChannels];
        for (int i = 0; i < kJukeboxChannels; i++) {
            s[i] = I.info(i);
        }
        std::lock_guard<std::mutex> g(snap_m_);
        for (int i = 0; i < kJukeboxChannels; i++) {
            snap_[i] = s[i];
        }
        status_.ready = I.ready;
        status_.failed = I.failed;
        status_.titles = I.titles;
        status_.tracks = (uint32_t)I.tracks.size();
        status_.listed = I.listed;
        uint32_t active = 0;
        for (int i = 0; i < kJukeboxChannels; i++) {
            active += s[i].state == JbState::Loading || s[i].state == JbState::Playing || s[i].state == JbState::Paused;
        }
        status_.active = active;
        status_.memory_mb = (double)I.hooks.bytes.load() / 1048576.0;
        status_.memory_blocks = I.hooks.blocks.load();
        status_.max_open_ms = I.max_open_ms;
        status_.list_ms = I.list_ms;
        status_.opens = I.opens;
        status_.underruns = I.underruns;
        status_.recoveries = I.recoveries;
        status_.gvol = I.gvol;
        status_.error = I.error;
    };

    // the private context and the music-only audio object
    double t0 = now_ms();
    sa1_status st = sa1_init(&I.host, &I.ctx);
    if (SA1_FAILED(st) || !I.ctx) {
        I.ctx = nullptr;
        I.failed = true;
        I.error = format("sa1_init: %s", sa1_status_string(st));
    } else {
        sa1_audio_desc d;
        std::memset(&d, 0, sizeof d);
        d.struct_size = sizeof d;
        d.gdi_path = cfg_.gdi.c_str();
        d.flags = SA1_AUDIO_MUSIC_ONLY | SA1_AUDIO_LAZY_STREAMS | SA1_AUDIO_SYNC_LOADS;
        d.stage = SA1_AUDIO_STAGE_DEFAULT;
        d.characters = 0;
        st = sa1_audio_open(I.ctx, &d, &I.audio);
        if (SA1_FAILED(st) || !I.audio) {
            I.audio = nullptr;
            I.failed = true;
            I.error = format("the music on your disc could not be opened: %s: %s", sa1_status_string(st),
                             sa1_last_error(I.ctx));
        }
    }
    if (I.audio) {
        // the track list: every music number's info (ADVERTISE.PRS once, 2 sectors per ADX header; Review G15)
        I.music_count = sa1_audio_music_count(I.audio);
        I.index.assign(I.music_count, -1);
        uint32_t errors = 0;
        for (uint32_t m = 0; m < I.music_count && !quitting(); m++) {
            sa1_audio_music mi;
            std::memset(&mi, 0, sizeof mi);
            mi.struct_size = sizeof mi;
            sa1_status s = sa1_audio_music_info(I.audio, m, &mi);
            if (s != SA1_OK) {
                errors++;
                continue;
            }
            if (!(mi.flags & SA1_AUDIO_MUSIC_ON_DISC) || !mi.sample_rate || !mi.num_frames) {
                continue;
            }
            JbTrack t;
            t.music = m;
            t.file = mi.file ? mi.file : "";
            t.has_title = mi.title != nullptr;
            t.title = mi.title ? mi.title : t.file;
            t.page = mi.page;
            t.entry = mi.entry;
            t.flags = mi.flags;
            t.channels = mi.channels;
            t.rate = mi.sample_rate;
            t.frames = mi.num_frames;
            t.file_size = mi.file_size;
            t.loop = mi.loop != 0 && mi.loop_end > mi.loop_start;
            t.loop_start = t.loop ? mi.loop_start : 0u;
            t.loop_end = t.loop ? mi.loop_end : mi.num_frames;
            I.titles = I.titles || t.has_title;
            I.listed += t.listed();
            I.index[m] = (int32_t)I.tracks.size();
            I.tracks.push_back(t);
        }
        I.list_ms = now_ms() - t0;
        I.ready = true;
        I.log(SA1_LOG_INFO, format("%u tracks on the disc (%u in the game's sound test%s) listed in %.0f ms%s",
                                   (unsigned)I.tracks.size(), (unsigned)I.listed,
                                   I.titles ? "" : "; ADVERTISE.PRS is not the supported one: file names as titles",
                                   I.list_ms,
                                   errors ? format("; %u music numbers could not be read", (unsigned)errors).c_str() : ""));
        auto list = std::make_shared<const std::vector<JbTrack>>(I.tracks);
        // the channels point into I.tracks, the Lua thread reads its own copy
        std::lock_guard<std::mutex> g(snap_m_);
        list_ = list;
        index_ = I.index;
        music_count_ = I.music_count;
    } else {
        I.log(SA1_LOG_WARN, I.error);
    }
    publish();

    uint64_t last_kick = ~(uint64_t)0;
    for (;;) {
        std::deque<Cmd> cmds;
        {
            std::unique_lock<std::mutex> g(m_);
            if (!sh_.quit && sh_.cmds.empty() && sh_.kicks == last_kick) {
                cv_.wait_for(g, std::chrono::microseconds((int64_t)(wake * 1000.0)));
            }
            if (sh_.quit) {
                break;
            }
            cmds.swap(sh_.cmds);
            last_kick = sh_.kicks;
            for (int i = 0; i < kJukeboxChannels; i++) {
                I.tgt[i] = sh_.tgt[i];
            }
            I.have_listener = sh_.have_listener;
            std::memcpy(I.eye, sh_.eye, sizeof I.eye);
            std::memcpy(I.fwd, sh_.fwd, sizeof I.fwd);
            std::memcpy(I.up, sh_.up, sizeof I.up);
            I.gmod_volume = sh_.gmod_volume;
            I.music_volume = sh_.music_volume;
            I.game_paused = sh_.game_paused;
        }
        double now = Impl::clock();
        for (const Cmd &k : cmds) {
            if (!I.audio) {
                // the disc did not open: every play fails with why
                if (k.type == Cmd::Play) {
                    WChan &c = I.ch[k.ch];
                    c.music = (int32_t)k.music;
                    c.gen++;
                    c.state = JbState::Failed;
                    c.error = I.error;
                } else if (k.type == Cmd::Stop) {
                    I.ch[k.ch] = WChan();
                }
                continue;
            }
            I.cmd(k, now);
        }
        if (I.bass) {
            uint32_t gv = I.bass->GetConfig(bass::kConfigGvolStream);
            I.gvol = gv == bass::kFail ? -1 : (int32_t)gv;
            // top every channel up first (Review G2), then the attributes and pauses, then at most one open
            for (int i = 0; i < kJukeboxChannels; i++) {
                WChan &c = I.ch[i];
                I.poll(c, i, now);
                I.fill(c, i, now);
                I.apply_attributes(c, i);
                I.apply_pause(c);
            }
            I.free_dying(now, false);
        }
        if (I.audio) {
            I.open_one(Impl::clock());
        }
        publish();
    }

    // shutdown: every BASS stream, then the libsa1 objects (the worker's alone)
    for (int i = 0; i < kJukeboxChannels; i++) {
        WChan &c = I.ch[i];
        if (c.h && I.bass) {
            I.bass->StreamFree(c.h);
        }
        c.h = 0;
        I.close_stream(c);
    }
    I.free_dying(0.0, true);
    if (I.audio) {
        sa1_audio_close(I.audio);
        I.audio = nullptr;
    }
    if (I.ctx) {
        sa1_shutdown(I.ctx);
        I.ctx = nullptr;
    }
    if (acquired) {
        bass_release();
    }
    I.bass = nullptr;
}

}  // namespace gsa1
