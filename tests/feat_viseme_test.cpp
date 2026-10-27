// feat_viseme_test: phoneme lip sync, the module's side (round 0.9.4c, feature "faces" 2; sadc docs/research/
// phoneme_plan.md 6.2 V1-V8, V11, V12 with its Review R.4 / R.7 - R.9 / R.12 / R.13, and 10.1 PQ7). Linked like core_test
// (the core and libsa1) by build.py, run with --gdi GAME.gdi.
//
//   feat_viseme_test [--gdi GAME.gdi] [--verbose]
//
// The speech is synthetic, made in memory by tests/viseme_synth.hpp (a port of the research prototype's formant
// synthesiser, fixed seeds; men, women and children): no WAV file and no recording of anyone is in the repository.
//   V1  accuracy: the classifier (src/core/viseme.cpp) on the prototype's corpus (vowels / syllables / pseudo-sentences x
//       clean / white / pink noise), scored as the prototype scores (phoneme_audio.md 5.3), against the thresholds of 6.2;
//       every number next to the prototype's (vis.c, out_all.txt)
//   V1b channels (review R.7): mains hum (fails without the 100 Hz high-pass - checked), a 300-3400 Hz band; reported:
//       a quiet microphone, clipping, a crude noise-suppression gate, the "s" row in the band
//   V2  silence: 30 s of digital silence, white noise at -50 dBFS, pink noise at -45 dBFS: at most 0.5 % of frames not SIL
//   V3  the classifier's latency (open / close / shape change medians) and the face changes per second at 30 Hz
//   V4  cost per 10 ms block with and without FTZ / DAZ
//   V5  src/core/mic.cpp's RECORDPROC (through a fake BASS): MXCSR restored exactly (two sentinels) while frames were made;
//       a denormal-producing tail costs no more than 4x the median; blocks of 80 / 160 / 320 / 480 samples give the frames
//       of 160-sample blocks (review R.8)
//   V6  the 64-bit frame atomic: the packing round-trips; cls -1 while paused, with the analysis off, before a press'
//       first frame; seq +1 per published frame
//   V7  a press keeps the floor, the peak and the speaker number; reset_voice; a device change keeps the number; tunes:
//       ranges refused, applied at the next block (a 12 dB gate silences a quiet vowel 3 dB lets through); a 10,000-toggle
//       stress run with BASS's callback on its own thread: no torn frame, the State never entered twice at once nor on
//       the test's ("Lua") thread (review R.9)
//   V7p privacy (owner, phoneme_plan.md 10.1 PQ7): the speaker number is learned in memory, forgotten by close() (the
//       session's end) and on the next session's first block; the classifier's and the microphone's files contain no
//       file, setting, log or network call; the module links no network library (BUILD_INFO's imports)
//   V8  the mouth table (src/core/mouth.cpp) against a SECOND transcription of phoneme_plan.md 4.3 written here as text, for
//       every face kind x class x s x size x variant x big; keys below each kind's count; LADDER entries
//   V11 (with the disc) end to end: synthetic a / i / u / oh / s / f / m (after 12.5 s of the twelve vowels, so the
//       speaker number has settled) through the fake BASS, the classifier, the table and sa1_character_face_mouth (or
//       _face_level for f) with SAME_PAIR into the real libsa1 world of Sonic, Tails, Knuckles, Amy and Big, a man and a
//       woman each, 60 fps frames on a simulated clock: in the middle 60 % of each sound at least 75 % of the pairs show
//       the true class' mouth (keys AND weight; review R.12), the silences closed, Big only keys 0 / 4 / 5; a negative
//       control with the analysis off (the loudness ladder) fails the vowel checks
//   V12 (with the disc) the latency from a vowel's first sample to the frame whose tick runs the first pair that shows its
//       mouth: median <= 50 ms, p90 <= 80 ms (review R.13: the tick's frame time)
//
// API NOTES (094c-gsa1-voice; phoneme_plan.md 5.5 as built - for 094c-gsa1-lipsync, the verifier and the README):
//   gsa1.FEATURES.faces = 2. The "per frame" functions take and return numbers only, push no table, never throw.
//   gsa1.MicViseme() -> cls, level, f1, f2, conf, seq          (always 6 numbers)
//       cls 0..8 (gsa1.VISEME), or -1 while not listening, with the analysis off, without a device, or before the first
//       frame of a press (then level / f1 / f2 / conf are 0); level 0..1 (the 25 ms window, 1/511 steps), f1 / f2 Hz (4 Hz
//       steps, 0 = none), conf 0..1, seq 0..65535: +1 per published frame (one per BASS block holding >= one 10 ms hop;
//       a session's first frame is 1). A seq unchanged for 0.1 s while listening = a stalled device (count it as SIL).
//   gsa1.MicVisemeOn(on) -> true | nil, message, "bad_argument"
//       the analysis in the microphone's callback; turning it on starts like a press (-1 until the next block's frame).
//   gsa1.MicVisemeTune(name, value) -> true | nil, message, "bad_argument"; applied at the next 10 ms block
//       "gate_min_db" 3..12 (gsa1_lipsync_shapes_gate); "adapt" 0 / 1 or a boolean (gsa1_lipsync_shapes_adapt; 0 also
//       returns to the adult prior); "smooth" 0 instant, 1 a 2-of-3 vote, 2 steadier, 3 quick (gsa1_lipsync_shapes_steady
//       0 quick -> 3, 1 steadier -> 2, 2 instant -> 0); "reset_voice" (value ignored; the "Forget my voice" button).
//       The tunes live in the module's memory from 6 / 1 / 3: send the current values whenever the analysis is turned on.
//   gsa1.MicVisemeVoice() -> g, frames                         (2 numbers; the prior 6.759 and 0 before learning)
//       PRIVACY (owner, phoneme_plan.md 10.1 PQ7): the learned number lives in the module's memory for the session only;
//       MicClose / the module's close forgets it. Lua must never put g or frames into a ConVar, a cookie, a file, a log
//       line (the per-sentence statistics line too) or a net message - the page may SHOW it.
//   gsa1.VisemeMouth(kind, cls, s, size, variant, big) -> a, b, w   (always 3 numbers)
//       variant 0 normal, 1 quiet, 2 loud; big a boolean (nil = false); SIL / MBP -> 0, 0, 0 (closed: still send it while
//       talking); f v th -> -1, -1, min(s, fv_level): send gsa1.FaceLevel(id, w, 0, flags) with THAT w (review R.1);
//       a kind without a face (E-102, Eggman, Tikal, Super Sonic) or a bad argument -> 0, 0, 0.
//   gsa1.VisemeTable(kind) -> { kind, keys, floor, ladder_cap, fv_level, [0..8] = { a, b, w, how = "closed" | "scales" |
//       "fixed" | "ladder", expression = bool, quiet = {a, b, w, how, expression} | nil, loud = ..., plain = ... } }
//       | nil, message, "unsupported" (no face) / "bad_argument". Not per frame (it builds a table).
//   gsa1.FaceMouth(id, key_a, key_b, weight [, flags]) -> nothing   (weight < 0 = off; flags gsa1.FACE.SAME_PAIR or nil -
//       any other bit is dropped; no character / NaN / a key the face lacks: nothing, the error only in sa1_last_error)
//   gsa1.FaceLevel(id, level, style [, flags]) -> nothing       (flags SAME_PAIR with style 0 only; dropped with style 1)
//   gsa1.VISEME = { SIL = 0, MBP = 1, AA = 2, EH = 3, EE = 4, OH = 5, OO = 6, SS = 7, FV = 8, COUNT = 9,
//       NAMES = {[0] = "SIL", ...}, WORDS = {[0] = "silence", "m b p", "ah", "eh", "ee", "oh", "oo", "s z sh", "f v th"} }
//   gsa1.FACE.MOUTH = 1; gsa1.FACE.SAME_PAIR = 512 only when libsa1 built the faster mouth (else absent: grey the switch)
//   build/<target>/faces2_api.txt: the above as built, written by tests/feat_faces_binding_test.cpp (review R.11).
//   The ladders (sa1_face_info / gsa1.FaceInfo): Sonic 0,4,16; Tails 0,4,7,8; Knuckles 0,4,7,16; Amy 0,7,4,8,16; Big 0,4,5.
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <thread>
#include <vector>

#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <xmmintrin.h>
#define FV_TEST_MXCSR 1
#endif

#include "viseme_synth.hpp"
#include "../src/core/mic.hpp"
#include "../src/core/mouth.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"
#include "../src/core/viseme.hpp"

using namespace gsa1;
namespace V = gsa1::viseme;
namespace SY = gsa1test::synth;

static int g_fail = 0, g_checks = 0;
static bool g_verbose = false;

#define CHECK(cond, ...)                                     \
    do {                                                     \
        g_checks++;                                          \
        if (cond) {                                          \
            std::printf("  ok    ");                         \
        } else {                                             \
            std::printf("  FAIL  ");                         \
            g_fail++;                                        \
        }                                                    \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

static double now_us()
{
    return std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

// ---- a fake of BASS's recording API (the RECORDPROC pointer is atomic: the stress run calls it from its own thread) ----
struct Fake {
    std::atomic<mic::RecordProc *> proc{nullptr};
    std::atomic<int> starts{0}, stops{0};
};
static Fake g_fake;
static uint32_t g_fake_dev = 0;
static int GSA1_MICCALL f_init(int device)
{
    g_fake_dev = device < 0 ? 0u : (uint32_t)device;
    return 1;
}
static int GSA1_MICCALL f_free(void) { return 1; }
static int GSA1_MICCALL f_info(uint32_t device, mic::DeviceInfo *info)
{
    static const char *names[] = {"Fake Headset", "Fake Line In"};
    if (device > 1) {
        return 0;
    }
    info->name = names[device];
    info->driver = "fake";
    info->flags = device == 0 ? (mic::kDeviceEnabled | mic::kDeviceDefault) : mic::kDeviceEnabled;
    return 1;
}
static int GSA1_MICCALL f_set(uint32_t) { return 1; }
static uint32_t GSA1_MICCALL f_get(void) { return g_fake_dev; }
static uint32_t GSA1_MICCALL f_start(uint32_t, uint32_t, uint32_t, mic::RecordProc *proc, void *)
{
    g_fake.starts++;
    g_fake.proc.store(proc);
    return 0x42;
}
static int GSA1_MICCALL f_play(uint32_t, int) { return 1; }
static int GSA1_MICCALL f_pause(uint32_t) { return 1; }
static int GSA1_MICCALL f_stop(uint32_t)
{
    g_fake.stops++;
    g_fake.proc.store(nullptr);
    return 1;
}
static int GSA1_MICCALL f_error(void) { return 0; }
static const mic::Api k_fake = {f_init, f_free, f_info, f_set, f_get, f_start, f_play, f_pause, f_stop, f_error};

// one block through the RECORDPROC BASS was given (n samples)
static void deliver(const float *x, int n)
{
    mic::RecordProc *p = g_fake.proc.load();
    if (p && n > 0) {
        p(0x42, x, (uint32_t)(n * sizeof(float)), nullptr);
    }
}

// a fresh microphone on the fake: open, analysis on, listening (tunes as given)
static bool fresh_mic(int device = -1)
{
    mic::set_test_api(&k_fake);     // closes: the classifier forgets everything
    std::string err;
    bool ok = mic::open(device, err);
    mic::viseme_on(true);
    ok = ok && mic::listen(true, err);
    return ok;
}

// ---- scoring (the prototype's phoneme.c score_frames / pair_flicker) ----------------------------------------------------
enum { F_CLOSED, F_OPEN, F_MID, F_WIDE, F_ROUND, F_TEETH };
static const int FACE_OF[V::COUNT] = {F_CLOSED, F_CLOSED, F_OPEN, F_MID, F_WIDE, F_ROUND, F_ROUND, F_TEETH, F_TEETH};
static unsigned face_mask(unsigned m)
{
    unsigned r = 0;
    for (int c = 0; c < V::COUNT; c++) {
        if (m & (1u << c)) r |= 1u << FACE_OF[c];
    }
    return r;
}
static unsigned face_near(unsigned fm)
{
    unsigned r = fm;
    if (fm & (1u << F_MID)) r |= (1u << F_OPEN) | (1u << F_WIDE);
    if (fm & (1u << F_OPEN)) r |= 1u << F_MID;
    if (fm & (1u << F_WIDE)) r |= (1u << F_MID) | (1u << F_TEETH);
    if (fm & (1u << F_TEETH)) r |= 1u << F_WIDE;
    return r;
}
static int primary(unsigned m)
{
    for (int c = 0; c < V::COUNT; c++) {
        if (m & (1u << c)) return c;
    }
    return -1;
}

struct Score {
    long n = 0, ok = 0, face_ok = 0, near_ok = 0, sil_n = 0, sil_fa = 0, pch = 0, ptch = 0;
    long conf[V::COUNT][V::COUNT] = {};
    std::vector<float> lt[3];      // latency: 0 onset (from silence), 1 offset (to silence), 2 other (shape change)
    long lt_miss[3] = {0, 0, 0};
    double speech_s = 0.0;
    void add(const Score &o)
    {
        n += o.n; ok += o.ok; face_ok += o.face_ok; near_ok += o.near_ok; sil_n += o.sil_n; sil_fa += o.sil_fa;
        pch += o.pch; ptch += o.ptch; speech_s += o.speech_s;
        for (int a = 0; a < V::COUNT; a++)
            for (int b = 0; b < V::COUNT; b++) conf[a][b] += o.conf[a][b];
        for (int t = 0; t < 3; t++) {
            lt[t].insert(lt[t].end(), o.lt[t].begin(), o.lt[t].end());
            lt_miss[t] += o.lt_miss[t];
        }
    }
    double pct() const { return n ? 100.0 * ok / n : 0.0; }
    double near_pct() const { return n ? 100.0 * near_ok / n : 0.0; }
    double flicker() const { return speech_s > 0 ? pch / speech_s : 0.0; }
};

static double pct(long a, long b) { return b ? 100.0 * a / b : 0.0; }

static float median(std::vector<float> v)
{
    if (v.empty()) return -1.0f;
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}
static float p90(std::vector<float> v)
{
    if (v.empty()) return -1.0f;
    std::sort(v.begin(), v.end());
    return v[v.size() * 9 / 10];
}

// the classifier on samples in 160-sample blocks (as the prototype's run_vis); every frame
static std::vector<V::Frame> classify(const std::vector<float> &y, const V::Params &p)
{
    V::State *st = new V::State;
    V::init(*st, p);
    std::vector<V::Frame> out;
    out.reserve(y.size() / 160 + 4);
    for (size_t i = 0; i < y.size(); i += 160) {
        V::Frame f[4];
        int m = (int)std::min<size_t>(160, y.size() - i);
        int got = V::feed(*st, y.data() + i, m, f, 4);
        for (int k = 0; k < got && k < 4; k++) out.push_back(f[k]);
    }
    delete st;
    return out;
}

static void score(Score &sc, const SY::Corpus &c, const std::vector<V::Frame> &fr, int set)
{
    const int n = (int)c.x.size(), guard = (set == SY::SET_VOWELS ? 40 : 20) * SY::RATE / 1000;
    for (size_t j = 0; j < fr.size(); j++) {
        int e = V::kWin - 1 + (int)j * V::kHop, ce = e - V::kWin / 2;
        if (ce < 0 || ce >= n) continue;
        int ph = c.phone[ce], k = c.segof[ce], a = c.segstart[k], b = c.segstart[k + 1];
        unsigned m = SY::phone_truth(ph);
        if (c.speech[ce]) sc.speech_s += V::kHop / (double)SY::RATE;
        if (!m || ce - a < guard || b - ce < guard) continue;
        const V::Frame &o = fr[j];
        sc.n++;
        sc.ok += (m >> o.cls) & 1u;
        sc.face_ok += (face_mask(m) >> FACE_OF[o.cls]) & 1u;
        sc.near_ok += (face_near(face_mask(m)) >> FACE_OF[o.cls]) & 1u;
        sc.conf[primary(m)][o.cls]++;
        if (!SY::phone_is_vowel(ph) && m == (1u << V::SIL) && ce - a >= 800 && b - ce >= 800) {
            sc.sil_n++;
            sc.sil_fa += o.cls != V::SIL;
        }
    }
    // latency: boundaries into a scored segment of >= 60 ms whose classes differ from the previous segment's
    for (size_t k = 1; k < c.segs.size(); k++) {
        unsigned m0 = SY::phone_truth(c.segs[k - 1].phone), m1 = SY::phone_truth(c.segs[k].phone);
        int a = c.segstart[k], b = c.segstart[k + 1];
        int ty = m0 == (1u << V::SIL) ? 0 : (m1 == (1u << V::SIL) ? 1 : 2);
        if (!m1 || (m0 & m1) || b - a < SY::RATE * 60 / 1000 || a >= n) continue;
        bool found = false;
        for (size_t j = 0; j < fr.size(); j++) {
            int e = V::kWin - 1 + (int)j * V::kHop;
            if (e < a) continue;
            if (e >= b) break;
            if ((m1 >> fr[j].cls) & 1u) {
                sc.lt[ty].push_back((e - a) * 1000.0f / SY::RATE);
                found = true;
                break;
            }
        }
        if (!found) sc.lt_miss[ty]++;
    }
    // face-class changes at the face's pair rate (every 1/30 s): output vs truth
    int prev = -1, prevt = -1;
    for (double t = V::kWin; t < n; t += SY::RATE / 30.0) {
        int j = (int)((t - (V::kWin - 1)) / V::kHop);
        if (j < 0 || j >= (int)fr.size()) continue;
        int ce = (int)t - V::kWin / 2;
        unsigned m = SY::phone_truth(c.phone[ce]);
        int tr = m ? FACE_OF[primary(m)] : prevt;
        if (prev >= 0 && FACE_OF[fr[j].cls] != prev) sc.pch++;
        if (prevt >= 0 && tr != prevt) sc.ptch++;
        prev = FACE_OF[fr[j].cls];
        prevt = tr;
    }
}

// the review's channel conditions applied the review's way: gain, the clean floor (or noise), then the effect
static std::vector<float> channel(const SY::Corpus &c, int g, float gain_db, int fx)
{
    std::vector<float> y = c.x;
    if (gain_db != 0.0f) {
        float gg = (float)std::pow(10.0, gain_db / 20.0);
        for (float &v : y) v *= gg;
    }
    for (size_t j = 0; j < y.size(); j++) {
        y[j] += 0.0002f * (float)((uint32_t)(j * 1103515245u + 12345u) >> 16 & 0x7FFF) / 32768.0f - 0.0001f;
    }
    (void)g;
    SY::apply_fx(y, fx);
    return y;
}

static std::vector<SY::Corpus> g_corpus;     // [set * 3 + group]

static const SY::Corpus &corp(int set, int g)
{
    return g_corpus[(size_t)(set * SY::GRP_COUNT + g)];
}

// ---- V1, V1b, V2, V3, V4 -------------------------------------------------------------------------------------------------
static void test_accuracy()
{
    std::printf("V1 accuracy (class %% of scored frames; the prototype vis.c's in brackets, out_all.txt):\n");
    // the prototype's default rows (SADC/build/research/phoneme/audio/out_all.txt; reproduced by 094c-gsa1-voice's
    // baseline): [set][condition] class %, and sentences' face near-right %
    static const double proto[3][6] = {{84.5, 84.4, 83.3, 66.2, 84.2, 76.4},
                                       {93.6, 91.0, 87.7, 65.3, 89.6, 75.6},
                                       {72.4, 69.6, 66.7, 48.7, 68.7, 57.1}};
    static const double proto_near_sent[6] = {85.1, 82.2, 79.5, 61.1, 81.6, 71.6};
    V::Params p;
    V::default_params(p);
    Score all[3][6];
    for (int set = 0; set < SY::SET_COUNT; set++) {
        for (int g = 0; g < SY::GRP_COUNT; g++) {
            const SY::Corpus &c = corp(set, g);
            for (int ci = 0; ci < 6; ci++) {
                std::vector<float> y = SY::with_condition(c, ci, g);
                Score sc;
                score(sc, c, classify(y, p), set);
                all[set][ci].add(sc);
            }
        }
        std::string row;
        for (int ci = 0; ci < 6; ci++) {
            row += format("%s %s %.1f (%.1f)", ci ? ";" : "", SY::condition(ci).name, all[set][ci].pct(), proto[set][ci]);
        }
        std::printf("        %-9s%s\n", SY::set_name(set), row.c_str());
    }
    std::string nearrow;
    for (int ci = 0; ci < 6; ci++) {
        nearrow += format("%s %s %.1f (%.1f)", ci ? ";" : "", SY::condition(ci).name, all[2][ci].near_pct(), proto_near_sent[ci]);
    }
    std::printf("        sentences, face near-right:%s\n", nearrow.c_str());
    const Score &vc = all[0][0], &cc = all[1][0], &sc = all[2][0], &vw = all[0][2], &sw = all[2][2], &sp = all[2][5];
    CHECK(vc.pct() >= 80.0 && cc.pct() >= 90.0 && sc.pct() >= 68.0 && vw.pct() >= 78.0 && sw.pct() >= 62.0 &&
              sp.pct() >= 50.0 && sc.near_pct() >= 80.0,
          "V1: vowels clean %.1f %% (>= 80; prototype 84.5), syllables clean %.1f (>= 90; 93.6), sentences clean %.1f (>= 68; "
          "72.4), vowels white 20 dB %.1f (>= 78; 83.3), sentences white 20 dB %.1f (>= 62; 66.7), sentences pink 10 dB %.1f "
          "(>= 50; 57.1); face near-right on sentences clean %.1f (>= 80; 85.1)", vc.pct(), cc.pct(), sc.pct(), vw.pct(),
          sw.pct(), sp.pct(), sc.near_pct());

    // V3 from the clean runs
    std::printf("V3 the classifier's latency (clean; ms from a segment's start to the end of the block that shows it):\n");
    bool lat_ok = true;
    static const char *proto_lat[3] = {"onset 11, offset 30", "onset 15, offset 31, change 44",
                                       "onset 12, offset 27, change 46; 12.2 face changes / s (truth 8.8)"};
    for (int set = 0; set < 3; set++) {
        const Score &s = all[set][0];
        float on = median(s.lt[0]), off = median(s.lt[1]), ch = median(s.lt[2]);
        lat_ok = lat_ok && on >= 0.0f && on <= 20.0f && off >= 0.0f && off <= 40.0f && (s.lt[2].empty() || ch <= 60.0f);
        std::printf("        %-9s onset median %.0f p90 %.0f (%zu, %ld never); offset median %.0f p90 %.0f; change median %.0f "
                    "p90 %.0f (%zu); face changes at 30 Hz %.1f / s vs truth %.1f   [prototype: %s]\n", SY::set_name(set),
                    on, p90(s.lt[0]), s.lt[0].size(), s.lt_miss[0], off, p90(s.lt[1]), ch, p90(s.lt[2]), s.lt[2].size(),
                    s.flicker(), s.speech_s > 0 ? s.ptch / s.speech_s : 0.0, proto_lat[set]);
    }
    const Score &ss = all[2][0];
    CHECK(lat_ok && ss.flicker() <= 14.0,
          "V3: every set's medians: open <= 20 ms, close <= 40 ms, shape change <= 60 ms; sentences' face changes at the 30 Hz "
          "pair rate %.1f / s (<= 14; truth %.1f)", ss.flicker(), ss.speech_s > 0 ? ss.ptch / ss.speech_s : 0.0);

    // V1b: the review's channels (sentences, the three groups)
    std::printf("V1b channels (sentences, class %%; the review's runs in brackets):\n");
    struct Ch {
        const char *name;
        float gain;
        int fx;
        float hp;
        double review;
    };
    const Ch chans[] = {{"mains hum -35 dBFS, high-pass 100 Hz", 0, 4, 100.0f, 68.2},
                        {"mains hum -35 dBFS, high-pass off", 0, 4, 0.0f, 58.5},
                        {"band 300-3400 Hz, high-pass 100 Hz", 0, 1, 100.0f, 70.2},
                        {"quiet microphone -25 dB", -25, 0, 100.0f, 61.9},
                        {"hot microphone +18 dB, clipped", 18, 3, 100.0f, 71.5},
                        {"crude noise-suppression gate", 0, 5, 100.0f, 71.6}};
    double res[6] = {0, 0, 0, 0, 0, 0};
    long ssrow[V::COUNT] = {};
    for (int k = 0; k < 6; k++) {
        V::Params q;
        V::default_params(q);
        q.hp_hz = chans[k].hp;
        Score acc;
        for (int g = 0; g < SY::GRP_COUNT; g++) {
            const SY::Corpus &c = corp(SY::SET_SENT, g);
            Score s1;
            score(s1, c, classify(channel(c, g, chans[k].gain, chans[k].fx), q), SY::SET_SENT);
            acc.add(s1);
        }
        res[k] = acc.pct();
        if (k == 2) {
            for (int b = 0; b < V::COUNT; b++) ssrow[b] = acc.conf[V::SS][b];
        }
        std::printf("        %-40s %.1f %% (%.1f)\n", chans[k].name, res[k], chans[k].review);
    }
    long ssn = 0;
    for (int b = 0; b < V::COUNT; b++) ssn += ssrow[b];
    std::printf("        the \"s\" row in the band (reported, not gated): SS %.1f %%, MBP %.1f %%, FV %.1f %% (review: 51.5 / "
                "19.6 / 19.6 without the high-pass)\n", pct(ssrow[V::SS], ssn), pct(ssrow[V::MBP], ssn), pct(ssrow[V::FV], ssn));
    CHECK(res[0] >= 64.0 && res[1] < 64.0 && res[2] >= 65.0,
          "V1b: mains hum with the 100 Hz high-pass %.1f %% (>= 64; review 68.2) - without it %.1f %% (the case fails "
          "without the high-pass: < 64); a 300-3400 Hz band %.1f %% (>= 65)", res[0], res[1], res[2]);
}

static void test_silence()
{
    std::printf("V2 silence:\n");
    V::Params p;
    V::default_params(p);
    const int n = 30 * SY::RATE;
    std::vector<float> zero((size_t)n, 0.0f), white((size_t)n), pink((size_t)n);
    uint32_t s = 12345u;
    auto gauss = [&s]() {
        auto u = [&s]() {
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            return (s >> 8) * (1.0 / 16777216.0) + 1e-12;
        };
        double a = u(), b = u();
        return std::sqrt(-2.0 * std::log(a)) * std::cos(2.0 * 3.14159265358979 * b);
    };
    double ew = 0, ep = 0;
    float b0 = 0, b1 = 0, b2 = 0;
    for (int i = 0; i < n; i++) {
        white[i] = (float)gauss();
        float w = (float)gauss();
        b0 = 0.99765f * b0 + w * 0.0990460f;
        b1 = 0.96300f * b1 + w * 0.2965164f;
        b2 = 0.57000f * b2 + w * 1.0526913f;
        pink[i] = b0 + b1 + b2 + w * 0.1848f;
        ew += (double)white[i] * white[i];
        ep += (double)pink[i] * pink[i];
    }
    float kw = (float)(std::pow(10.0, -50.0 / 20.0) / std::sqrt(ew / n)), kp = (float)(std::pow(10.0, -45.0 / 20.0) / std::sqrt(ep / n));
    for (int i = 0; i < n; i++) {
        white[i] *= kw;
        pink[i] *= kp;
    }
    double share[3];
    const std::vector<float> *sig[3] = {&zero, &white, &pink};
    for (int k = 0; k < 3; k++) {
        std::vector<V::Frame> fr = classify(*sig[k], p);
        long moved = 0;
        for (const V::Frame &f : fr) moved += f.cls != V::SIL;
        share[k] = pct(moved, (long)fr.size());
    }
    CHECK(share[0] <= 0.5 && share[1] <= 0.5 && share[2] <= 0.5,
          "V2: 30 s without speech - digital silence %.2f %%, white noise at -50 dBFS %.2f %%, pink noise at -45 dBFS %.2f %% of "
          "the frames not SIL (each <= 0.5 %%)", share[0], share[1], share[2]);
}

static void test_cost()
{
    std::printf("V4 cost per 10 ms block (61 s of pseudo-sentences, men; the prototype: 4.7-6.4 us, p99 7.7-22 with FTZ / DAZ):\n");
    std::vector<SY::Seg> seg = SY::build(SY::SET_SENT, SY::GRP_MEN, 5u, 60.0f);
    std::vector<float> x = SY::render(seg, SY::GRP_MEN, 7u);
    const int n = (int)x.size();
    double mean_ftz = 1e30, mean_raw = 1e30, med[2] = {0, 0}, p99[2] = {0, 0};
    for (int ftz = 0; ftz < 2; ftz++) {
#if defined(FV_TEST_MXCSR)
        unsigned csr = _mm_getcsr();
        _mm_setcsr(ftz ? (csr | 0x8040u) : (csr & ~0x8040u));
#endif
        V::Params p;
        V::default_params(p);
        V::State *st = new V::State;
        double best = 1e30;
        int nf = 0;
        for (int rep = 0; rep < 3; rep++) {
            V::init(*st, p);
            nf = 0;
            double t0 = now_us();
            for (int i = 0; i < n; i += 160) {
                V::Frame f;
                nf += V::feed(*st, x.data() + i, std::min(160, n - i), &f, 1);
            }
            best = std::min(best, now_us() - t0);
        }
        std::vector<float> per;
        V::init(*st, p);
        for (int i = 0; i < n; i += 160) {
            V::Frame f;
            double t0 = now_us();
            int got = V::feed(*st, x.data() + i, std::min(160, n - i), &f, 1);
            if (got) per.push_back((float)(now_us() - t0));
        }
        std::sort(per.begin(), per.end());
        med[ftz] = per[per.size() / 2];
        p99[ftz] = per[per.size() * 99 / 100];
        (ftz ? mean_ftz : mean_raw) = best / nf;
        delete st;
#if defined(FV_TEST_MXCSR)
        _mm_setcsr(csr);
#endif
    }
    CHECK(mean_ftz < 50.0,
          "V4: %.2f us per block with FTZ / DAZ (median %.2f, p99 %.2f; < 50); without: %.2f us (median %.2f, p99 %.2f); the "
          "State is %u bytes", mean_ftz, med[1], p99[1], mean_raw, med[0], p99[0], (unsigned)sizeof(V::State));
}

// ---- V5, V6: the microphone's RECORDPROC ---------------------------------------------------------------------------------
// a speech signal for the microphone tests: the men's syllable file's first seconds with the clean floor
static std::vector<float> speech_signal(int seconds = 6)
{
    std::vector<float> y = SY::with_condition(corp(SY::SET_CV, SY::GRP_MEN), 0, SY::GRP_MEN);
    y.resize(std::min(y.size(), (size_t)(seconds * SY::RATE)));
    return y;
}

static void test_mxcsr_blocks()
{
    std::printf("V5 the RECORDPROC (fake BASS):\n");
    std::vector<float> y = speech_signal();
#if defined(FV_TEST_MXCSR)
    const unsigned saved = _mm_getcsr();
    const unsigned sentinel[2] = {0x3F80u, 0x9FC0u};    // round down with FTZ / DAZ off; round nearest with FTZ / DAZ on
    bool same = true;
    uint32_t seq0 = 0, seq1 = 0;
    unsigned got[2] = {0, 0};
    for (int k = 0; k < 2; k++) {
        fresh_mic();
        mic::VisemeFrame f0;
        mic::viseme_frame(f0);
        seq0 = f0.seq;
        for (size_t i = 0; i + 160 <= 3 * (size_t)SY::RATE; i += 160) {
            _mm_setcsr(sentinel[k]);
            deliver(y.data() + i, 160);
            got[k] = _mm_getcsr();
            _mm_setcsr(saved);
            same = same && got[k] == sentinel[k];
        }
        mic::VisemeFrame f1;
        mic::viseme_frame(f1);
        seq1 = f1.seq;
        same = same && seq1 != seq0 && f1.cls >= 0;
    }
    _mm_setcsr(saved);
    CHECK(same, "V5: MXCSR is exactly as the RECORDPROC found it (0x%04X -> 0x%04X, 0x%04X -> 0x%04X; one with FTZ off) and "
          "the same calls made frames (seq %u -> %u, the analysis ran)", sentinel[0], got[0], sentinel[1], got[1], seq0, seq1);
#else
    std::printf("  info  not an x86 CPU: no MXCSR\n");
#endif
    // a decaying tail (denormal floats in the FIR, the low-band filters and the LPC without FTZ / DAZ)
    {
        fresh_mic();
        std::vector<float> per_speech, per_tail;
        for (size_t i = 0; i + 160 <= y.size(); i += 160) {
            double t0 = now_us();
            deliver(y.data() + i, 160);
            per_speech.push_back((float)(now_us() - t0));
        }
        std::vector<float> tail(160 * 300);
        for (size_t i = 0; i < tail.size(); i++) {
            tail[i] = (float)(1e-30 * std::pow(0.9995, (double)i) * std::sin(0.3 * (double)i));
        }
        for (size_t i = 0; i < tail.size(); i += 160) {
            double t0 = now_us();
            deliver(tail.data() + i, 160);
            per_tail.push_back((float)(now_us() - t0));
        }
        // the same tail straight into the classifier without FTZ / DAZ (reported: what the flush saves)
        float raw_tail = 0.0f;
#if defined(FV_TEST_MXCSR)
        {
            unsigned csr = _mm_getcsr();
            _mm_setcsr(csr & ~0x8040u);
            V::Params p;
            V::default_params(p);
            V::State *st = new V::State;
            V::init(*st, p);
            for (size_t i = 0; i + 160 <= y.size(); i += 160) {
                V::Frame f;
                V::feed(*st, y.data() + i, 160, &f, 1);
            }
            std::vector<float> per;
            for (size_t i = 0; i < tail.size(); i += 160) {
                V::Frame f;
                double t0 = now_us();
                V::feed(*st, tail.data() + i, 160, &f, 1);
                per.push_back((float)(now_us() - t0));
            }
            raw_tail = median(per);
            delete st;
            _mm_setcsr(csr);
        }
#endif
        float ms = median(per_speech), mt = median(per_tail);
        CHECK(mt <= 4.0f * ms,
              "V5: a decaying denormal tail costs %.2f us per block (median) through the RECORDPROC against %.2f for speech (<= "
              "4x); straight into the classifier without FTZ / DAZ it costs %.2f us", mt, ms, raw_tail);
    }
    // block sizes (review R.8): the classifier sees every hop whatever the block
    {
        V::Params p;
        V::default_params(p);
        std::vector<V::Frame> ref;
        {
            V::State *st = new V::State;
            V::init(*st, p);
            V::reset_press(*st);     // as the microphone starts a press
            for (size_t i = 0; i < y.size(); i += 160) {
                V::Frame f[4];
                int got = V::feed(*st, y.data() + i, (int)std::min<size_t>(160, y.size() - i), f, 4);
                for (int k = 0; k < got; k++) ref.push_back(f[k]);
            }
            delete st;
        }
        bool direct_same = true, mic_same = true;
        std::string seen;
        for (int bs : {80, 160, 320, 480, 7, 1000}) {
            // straight: every frame
            V::State *st = new V::State;
            V::init(*st, p);
            V::reset_press(*st);
            std::vector<V::Frame> all;
            for (size_t i = 0; i < y.size(); i += (size_t)bs) {
                V::Frame f[8];
                int got = V::feed(*st, y.data() + i, (int)std::min<size_t>((size_t)bs, y.size() - i), f, 8);
                for (int k = 0; k < got && k < 8; k++) all.push_back(f[k]);
            }
            delete st;
            bool eq = all.size() == ref.size();
            for (size_t k = 0; eq && k < all.size(); k++) {
                eq = all[k].cls == ref[k].cls && all[k].raw == ref[k].raw && all[k].f1 == ref[k].f1 && all[k].f2 == ref[k].f2 &&
                     all[k].db == ref[k].db && all[k].g == ref[k].g;
            }
            direct_same = direct_same && eq;
            // through the microphone: each block publishes its newest frame
            fresh_mic();
            size_t fed = 0, bad = 0, pubs = 0;
            uint32_t last_seq = 0;
            {
                mic::VisemeFrame f;
                mic::viseme_frame(f);
                last_seq = f.seq;
            }
            for (size_t i = 0; i < y.size(); i += (size_t)bs) {
                int m = (int)std::min<size_t>((size_t)bs, y.size() - i);
                deliver(y.data() + i, m);
                fed += (size_t)m;
                mic::VisemeFrame f;
                mic::viseme_frame(f);
                size_t frames_so_far = fed / 160;    // hops completed since the press
                if (f.seq != last_seq) {
                    pubs++;
                    last_seq = f.seq;
                    if (frames_so_far == 0 || frames_so_far > ref.size()) {
                        bad++;
                        continue;
                    }
                    const V::Frame &r = ref[frames_so_far - 1];
                    mic::VisemeFrame want;
                    uint32_t ep = 0;
                    mic::viseme_unpack(mic::viseme_pack(r.cls, r.level, r.f1, r.f2, r.conf, 0, 0), want, ep);
                    bad += f.cls != want.cls || f.level != want.level || f.f1 != want.f1 || f.f2 != want.f2;
                }
            }
            mic_same = mic_same && bad == 0 && pubs > 0;
            seen += format("%s%d: %zu frames %s, %zu published%s", seen.empty() ? "" : "; ", bs, all.size(),
                           eq ? "equal" : "DIFFER", pubs, bad ? " (some differ)" : "");
        }
        CHECK(direct_same && mic_same,
              "V5: blocks of 80 / 160 / 320 / 480 (and 7 / 1000) samples give the frames of 160-sample blocks (%zu frames), and "
              "through the RECORDPROC each block publishes its newest of them (%s)", ref.size(), seen.c_str());
    }
}

static void test_atomic()
{
    std::printf("V6 the frame atomic:\n");
    int bad = 0, n = 0;
    for (int cls = -1; cls <= 8; cls++) {
        for (float lv : {0.0f, 0.004f, 0.37f, 0.999f, 1.0f, 1.5f}) {
            for (float f1 : {0.0f, 271.0f, 1199.0f}) {
                for (float f2 : {0.0f, 850.0f, 3497.0f, 5000.0f}) {
                    for (float cf : {0.0f, 0.5f, 1.0f}) {
                        for (uint32_t seq : {0u, 1u, 65535u, 65536u}) {
                            uint32_t ep = 0;
                            mic::VisemeFrame f;
                            mic::viseme_unpack(mic::viseme_pack(cls, lv, f1, f2, cf, seq, 0x1FFu), f, ep);
                            n++;
                            bool ok = f.cls == cls && std::fabs(f.level - std::min(lv, 1.0f)) <= 0.5f / 511.0f + 1e-6f &&
                                      std::fabs(f.f1 - f1) <= 2.0f && std::fabs(f.f2 - std::min(f2, 4092.0f)) <= 2.0f &&
                                      std::fabs(f.conf - cf) <= 0.5f / 127.0f + 1e-6f && f.seq == (seq & 0xFFFFu) &&
                                      ep == 0xFFu;
                            bad += !ok;
                        }
                    }
                }
            }
        }
    }
    CHECK(bad == 0, "V6: the packing round-trips %d frames (cls -1..8, level 1/511, F1 / F2 4 Hz, conf 1/127, seq 16 bits, "
          "the epoch 8 bits): %d differ", n, bad);
    std::vector<float> y = speech_signal(2);
    fresh_mic();
    mic::VisemeFrame a, b, c, d, e;
    mic::viseme_frame(a);                       // listening, analysis on, nothing delivered yet
    deliver(y.data() + 4000, 80);              // half a hop
    mic::viseme_frame(b);
    deliver(y.data() + 4080, 80);              // the first hop of the press: a frame
    mic::viseme_frame(c);
    std::string err;
    mic::listen(false, err);
    mic::viseme_frame(d);                       // paused
    mic::listen(true, err);
    mic::viseme_frame(e);                       // a new press, no frame of it yet
    mic::VisemeFrame f, g;
    deliver(y.data() + 4160, 160);
    mic::viseme_frame(f);
    mic::viseme_on(false);
    deliver(y.data() + 4320, 160);
    mic::viseme_frame(g);                       // the analysis off
    uint32_t s0 = f.seq;
    mic::viseme_on(true);
    for (int k = 0; k < 5; k++) deliver(y.data() + 4480 + 160 * k, 160);
    mic::VisemeFrame h;
    mic::viseme_frame(h);
    CHECK(a.cls == -1 && b.cls == -1 && c.cls >= 0 && d.cls == -1 && e.cls == -1 && f.cls >= 0 && g.cls == -1 &&
              h.cls >= 0 && h.seq == ((s0 + 5u) & 0xFFFFu) && d.level == 0.0f && c.seq == ((a.seq + 1u) & 0xFFFFu),
          "V6: cls -1 before the press' first frame (%d, after half a hop %d), a frame after the first hop (%d), -1 paused (%d) "
          "and after a new press until its first frame (%d), a frame (%d), -1 with the analysis off (%d); seq +1 per frame "
          "(%u -> %u after 5 blocks)", a.cls, b.cls, c.cls, d.cls, e.cls, f.cls, g.cls, s0, h.seq);
}

// ---- V7: presses, the speaker number, tunes, the stress run; V7p: privacy -----------------------------------------------
static std::vector<float> silence_block()
{
    std::vector<float> s(160);
    for (size_t j = 0; j < s.size(); j++) {
        s[j] = 0.0002f * (float)((uint32_t)(j * 1103515245u + 12345u) >> 16 & 0x7FFF) / 32768.0f - 0.0001f;
    }
    return s;
}

static void test_press_voice()
{
    std::printf("V7 presses, the speaker number, tunes:\n");
    const float prior = V::prior_g();
    // the classifier itself: a press keeps the floor, the peak and the speaker number
    {
        V::Params p;
        V::default_params(p);
        V::State *st = new V::State;
        V::init(*st, p);
        std::vector<float> y = SY::with_condition(corp(SY::SET_VOWELS, SY::GRP_WOMEN), 0, SY::GRP_WOMEN);
        for (size_t i = 0; i + 160 <= 8 * (size_t)SY::RATE; i += 160) {
            V::Frame f;
            V::feed(*st, y.data() + i, 160, &f, 1);
        }
        float fl = st->floor_db, pk = st->peak_db, g = st->g;
        uint32_t vf = st->voice_frames;
        V::reset_press(*st);
        bool kept = st->floor_db == fl && st->peak_db == pk && st->g == g && st->voice_frames == vf && st->cur == V::SIL;
        V::reset_voice(*st);
        CHECK(kept && vf > 0 && g != prior && st->g == prior && st->voice_frames == 0,
              "V7: a press (reset_press) keeps the floor %.1f dB, the peak %.1f dB and the speaker number %.3f (learned from %u "
              "vowel frames; the prior is %.3f); reset_voice -> the prior, 0 frames", fl, pk, g, vf, prior);
        delete st;
    }
    // through the microphone
    std::vector<float> y = SY::with_condition(corp(SY::SET_VOWELS, SY::GRP_MEN), 0, SY::GRP_MEN);
    std::vector<float> sil = silence_block();
    std::string err;
    fresh_mic();
    for (size_t i = 0; i + 160 <= 8 * (size_t)SY::RATE; i += 160) deliver(y.data() + i, 160);
    float g1 = 0, g2 = 0, g3 = 0, g4 = 0, g5 = 0;
    uint32_t n1 = 0, n2 = 0, n3 = 0, n4 = 0, n5 = 0;
    mic::viseme_voice(g1, n1);
    mic::listen(false, err);
    mic::listen(true, err);
    deliver(sil.data(), 160);
    mic::viseme_voice(g2, n2);
    bool reopened = mic::open(1, err) && mic::listen(true, err);
    deliver(sil.data(), 160);
    deliver(sil.data(), 160);
    mic::viseme_voice(g3, n3);
    bool tuned = mic::viseme_tune("reset_voice", 0.0, err);
    mic::viseme_voice(g4, n4);
    deliver(sil.data(), 160);
    mic::viseme_voice(g5, n5);
    CHECK(n1 > 0 && std::fabs(g1 - prior) > 1e-3f && g2 == g1 && n2 == n1 && reopened && g3 == g1 && n3 == n1 && tuned &&
              g4 == prior && n4 == 0 && g5 == prior && n5 == 0,
          "V7: through the microphone: learned %.3f from %u vowel frames; a release and a press keep it (%.3f, %u); another "
          "device keeps it (%.3f, %u); \"reset_voice\" -> the prior %.3f at once and after the next block (%.3f, %u)", g1, n1,
          g2, n2, g3, n3, g4, g5, n5);
    // tunes: names and ranges
    int refused = 0;
    refused += !mic::viseme_tune("gate_min_db", 2.9, err);
    refused += !mic::viseme_tune("gate_min_db", 12.5, err);
    refused += !mic::viseme_tune("gate_min_db", std::nan(""), err);
    refused += !mic::viseme_tune("adapt", 0.5, err);
    refused += !mic::viseme_tune("smooth", 4, err);
    refused += !mic::viseme_tune("smooth", 1.5, err);
    refused += !mic::viseme_tune("loudness", 1, err);
    int taken = mic::viseme_tune("gate_min_db", 3, err) + mic::viseme_tune("gate_min_db", 12, err) +
                mic::viseme_tune("adapt", 0, err) + mic::viseme_tune("adapt", 1, err) + mic::viseme_tune("smooth", 0, err) +
                mic::viseme_tune("smooth", 3, err);
    CHECK(refused == 7 && taken == 6, "V7: tunes out of range or unknown refused (%d of 7: \"%s\"), in range taken (%d of 6)",
          refused, err.c_str(), taken);
    // a tune applies at the next block: a quiet vowel 9-10 dB over a -60 dBFS noise floor
    {
        SY::Corpus u = SY::utterance(SY::GRP_MEN, 5u, {"A"}, {1200}, {400}, 1500);
        std::vector<float> x = u.x;
        int a = u.segstart[1], b = u.segstart[2];
        double e = 0;
        for (int i = a; i < b; i++) e += (double)x[i] * x[i];
        float k = (float)(std::pow(10.0, -51.0 / 20.0) / std::sqrt(e / (b - a)));
        uint32_t s = 99u;
        for (size_t i = 0; i < x.size(); i++) {
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            double u1 = (s >> 8) * (1.0 / 16777216.0) + 1e-12;
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            double u2 = (s >> 8) * (1.0 / 16777216.0);
            x[i] = x[i] * k + (float)(0.001 * std::sqrt(-2.0 * std::log(u1)) * std::cos(6.283185307179586 * u2));
        }
        int heard[2] = {0, 0}, frames[2] = {0, 0}, first_after = -2;
        for (int run = 0; run < 2; run++) {
            fresh_mic();
            mic::viseme_tune("gate_min_db", 3, err);
            int mid = (a + b) / 2;
            for (size_t i = 0; i + 160 <= x.size(); i += 160) {
                if (run == 1 && (int)i >= mid && (int)i < mid + 160) {
                    mic::viseme_tune("gate_min_db", 12, err);       // during the vowel
                }
                deliver(x.data() + i, 160);
                mic::VisemeFrame f;
                mic::viseme_frame(f);
                int e2 = (int)i + 160;
                bool inside = e2 - 200 >= a + (b - a) / 5 && e2 - 200 < b - (b - a) / 5;
                bool after = run == 0 || (int)i >= mid;
                if (run == 1 && (int)i >= mid && first_after == -2) first_after = f.cls;
                if (inside && after) {
                    frames[run]++;
                    heard[run] += f.cls > 0;
                }
            }
        }
        mic::viseme_tune("gate_min_db", 6, err);
        CHECK(heard[0] * 10 >= frames[0] * 8 && heard[1] == 0 && first_after == V::SIL && frames[1] > 10,
              "V7: a vowel 9-10 dB over the noise floor: with the gate at 3 dB %d of %d frames heard as sound; the gate set to "
              "12 dB in the middle of it: the very next block is SIL (%s) and %d of the next %d frames are sound", heard[0],
              frames[0], V::name(first_after), heard[1], frames[1]);
    }
}

static void test_stress()
{
    std::printf("V7 the stress run (review R.9):\n");
    fresh_mic();
    std::vector<float> y = speech_signal(6);
    mic::VisemeDebug d0;
    mic::viseme_debug(d0);
    mic::viseme_debug_mark_thread();     // this thread plays the Lua thread from here on
    std::atomic<bool> stop{false};
    std::atomic<long> calls{0};
    std::thread bass([&]() {
        size_t i = 0;
        while (!stop.load()) {
            mic::RecordProc *p = g_fake.proc.load();
            int n = 80 * (1 + (int)(i / 160) % 6);     // 80 .. 480 samples
            if (i + (size_t)n > y.size()) {
                i = 0;
                continue;
            }
            if (p) {
                p(0x42, y.data() + i, (uint32_t)(n * sizeof(float)), nullptr);
                calls++;
            }
            i += (size_t)n;
        }
    });
    long bad = 0;
    std::string err;
    for (int spin = 0; calls.load() < 20 && spin < 2000000; spin++) std::this_thread::yield();
    for (int k = 0; k < 10000; k++) {
        // one toggle per callback (or after about 0.2 ms without one: a device change stops the callback a moment)
        long c0 = calls.load();
        double w0 = now_us();
        while (calls.load() == c0 && now_us() - w0 < 200.0) {
        }
        switch (k % 8) {
        case 0: mic::listen(false, err); break;
        case 1: mic::listen(true, err); break;
        case 2:
            mic::open((k / 8) % 2, err);       // another device: teardown + a pending re-init
            mic::listen(true, err);
            break;
        case 3: mic::viseme_tune("gate_min_db", 3 + k % 10, err); break;
        case 4:
            mic::viseme_tune("smooth", k % 4, err);
            mic::viseme_tune("adapt", (k / 8) % 3 ? 1 : 0, err);
            break;
        case 5: mic::viseme_tune("reset_voice", 0, err); break;
        case 6: mic::viseme_on((k / 8) % 5 != 0); break;
        default: mic::viseme_on(true); break;
        }
        mic::VisemeFrame f;
        mic::viseme_frame(f);
        float g = 0;
        uint32_t fr = 0;
        mic::viseme_voice(g, fr);
        bool ok = f.cls >= -1 && f.cls < V::COUNT && f.level >= 0.0f && f.level <= 1.0f && f.f1 >= 0.0f && f.f1 <= 4092.0f &&
                  f.f2 >= 0.0f && f.f2 <= 4092.0f && f.conf >= 0.0f && f.conf <= 1.0f && f.seq <= 65535u &&
                  std::isfinite(g) && g > 4.0f && g < 9.0f;
        bad += !ok;
    }
    stop = true;
    bass.join();
    mic::VisemeDebug d1;
    mic::viseme_debug(d1);
    std::string err2;
    mic::viseme_tune("gate_min_db", 6, err2);
    mic::viseme_tune("smooth", 3, err2);
    mic::viseme_tune("adapt", 1, err2);
    CHECK(bad == 0 && d1.overlaps == d0.overlaps && d1.marked_thread_entries == d0.marked_thread_entries &&
              d1.entries > d0.entries + 100 && calls.load() > 100,
          "V7: 10,000 listen / device / tune / analysis toggles on this thread while BASS's callback ran %ld blocks (80-480 "
          "samples) on its own: %ld frames out of range or torn; the classifier's State entered %llu times, never two at once "
          "(%llu) and never on this thread (%llu)", calls.load(), bad, (unsigned long long)(d1.entries - d0.entries),
          (unsigned long long)(d1.overlaps - d0.overlaps), (unsigned long long)(d1.marked_thread_entries - d0.marked_thread_entries));
}

// the code of a source file without comments and string literals
static std::string code_only(const std::string &s)
{
    std::string o;
    for (size_t i = 0; i < s.size(); i++) {
        if (s.compare(i, 2, "//") == 0) {
            while (i < s.size() && s[i] != '\n') i++;
            o += '\n';
        } else if (s.compare(i, 2, "/*") == 0) {
            size_t e = s.find("*/", i + 2);
            i = e == std::string::npos ? s.size() : e + 1;
            o += ' ';
        } else if (s[i] == '"' || s[i] == '\'') {
            char q = s[i++];
            while (i < s.size() && s[i] != q) {
                if (s[i] == '\\') i++;
                i++;
            }
            o += "\"\"";
        } else {
            o += s[i];
        }
    }
    return o;
}

static std::string g_src;     // --src: the g-sa1 tree (default: two levels above this program, build/<target>/../..)

static void test_privacy(const std::string &self)
{
    std::printf("V7p privacy (owner, phoneme_plan.md 10.1 PQ7: the voice-pitch learning in session memory only):\n");
    const float prior = V::prior_g();
    std::vector<float> y = SY::with_condition(corp(SY::SET_VOWELS, SY::GRP_CHILD), 0, SY::GRP_CHILD);
    std::vector<float> sil = silence_block();
    std::string err;
    fresh_mic();
    for (size_t i = 0; i + 160 <= 8 * (size_t)SY::RATE; i += 160) deliver(y.data() + i, 160);
    float g1, g2, g3;
    uint32_t n1, n2, n3;
    mic::viseme_voice(g1, n1);
    mic::close();                      // the module's close hook: the session ends
    mic::viseme_voice(g2, n2);
    // the next session: the same process, the same device
    std::string e2;
    bool again = mic::open(-1, e2);
    mic::viseme_on(true);
    again = again && mic::listen(true, e2);
    deliver(sil.data(), 160);
    deliver(sil.data(), 160);
    mic::viseme_voice(g3, n3);
    CHECK(n1 > 0 && std::fabs(g1 - prior) > 1e-3f && g2 == prior && n2 == 0 && again && g3 == prior && n3 == 0,
          "V7p: learned %.3f from %u vowel frames (memory); the session's end (close) forgets it at once (%.3f, %u) and the "
          "next session starts from the prior %.3f (%.3f, %u)", g1, n1, g2, n2, prior, g3, n3);
    // the files that hold or hand out the learned number: no file, setting, log or network call in their code
    std::string root = !g_src.empty() ? g_src : join_path(join_path(self.empty() ? std::string(".") : self, ".."), "..");
    const char *files[] = {"src/core/viseme.cpp", "src/core/viseme.hpp", "src/core/mic.cpp", "src/core/mic.hpp",
                           "src/core/mouth.cpp", "src/core/mouth.hpp", "src/module/bind_faces.cpp"};
    const char *banned[] = {"fopen", "freopen", "fwrite", "fputs", "fprintf", "printf", "puts(", "ofstream", "fstream",
                            "FILE", "CreateFile", "WriteFile", "write_file", "write_small", "save_config", "Config",
                            "socket", "send(", "sendto", "connect(", "WSA", "http", "Http", "InternetOpen", "curl",
                            "RegSet", "RegCreate", "log_line", "Log(", "getenv", "SetEnvironment", "cookie"};
    std::string found;
    int read = 0;
    for (const char *f : files) {
        std::string text, rerr;
        if (!read_small_file(join_path(root, f), 4u << 20, text, rerr)) {
            found += format(" (%s not readable: %s)", f, rerr.c_str());
            continue;
        }
        read++;
        std::string code = code_only(text);
        for (const char *b : banned) {
            if (code.find(b) != std::string::npos) found += format(" %s: %s;", f, b);
        }
    }
    CHECK(read == 7 && found.empty(),
          "V7p: the classifier, the microphone, the mouth table and the faces binding (%d files) contain no file, setting, "
          "registry, environment, log or network call in their code%s", read, found.c_str());
    // the module links no network library
    std::string info, ierr;
    if (read_small_file(join_path(join_path(self.empty() ? std::string(".") : self, ".."), "BUILD_INFO.txt"), 1u << 20, info,
                        ierr)) {
        std::string net;
        size_t at = 0;
        int lines = 0;
        while ((at = info.find("imports:", at)) != std::string::npos) {
            size_t end = info.find('\n', at);
            std::string line = info.substr(at, end == std::string::npos ? std::string::npos : end - at);
            std::string low = line;
            for (char &ch : low) ch = (char)std::tolower((unsigned char)ch);
            for (const char *dll : {"ws2_32", "wsock32", "wininet", "winhttp", "urlmon", "mswsock", "iphlpapi", "dnsapi"}) {
                if (low.find(dll) != std::string::npos) net += format(" %s", dll);
            }
            lines++;
            at = end == std::string::npos ? info.size() : end;
        }
        CHECK(lines > 0 && net.empty(), "V7p: the module imports no network library (%d import line(s) of BUILD_INFO.txt)%s",
              lines, net.c_str());
    } else {
        std::printf("  info  no BUILD_INFO.txt next to the build (%s): the import check is skipped\n", ierr.c_str());
    }
}

// ---- V8: the mouth table against a second transcription of phoneme_plan.md 4.3 -----------------------------------------
// Written from the plan's table as text (not a copy of mouth.cpp's arrays): "kind K keys N floor F cap C fv V" opens a
// kind; "K CLASS entry | quiet entry | loud entry | plain entry" with entry = "a>b@w S|F [X]" or "L". SIL and MBP are
// closed for every kind.
static const char *const k_plan_43[] = {
    "kind 0 keys 21 floor 0.8 cap 0.5 fv 0.25",
    "0 AA 4>16@.30 F X | quiet 0>7@1 F | loud 4>16@.60 F X | plain 0>7@1 F",
    "0 EH 0>4@1 S",
    "0 EE 0>4@1 S",
    "0 OH 6>16@.40 F X | quiet 6>7@.30 F | plain 6>7@.30 F",
    "0 OO 0>6@1 F",
    "0 SS 0>4@.50 S",
    "0 FV L",
    "kind 2 keys 20 floor 0 cap 0.667 fv 0.1667",
    "2 AA 0>16@1 S | loud 16>8@.50 F X",
    "2 EH 0>4@1 S",
    "2 EE 0>6@1 S",
    "2 OH 0>7@1 S",
    "2 OO 0>5@1 S",
    "2 SS 0>4@1 S",
    "2 FV L",
    "kind 3 keys 20 floor 0.8 cap 0.667 fv 0.1667",
    "3 AA 7>16@.30 F X | quiet 0>7@1 F | loud 7>16@.60 F X | plain 0>7@1 F",
    "3 EH 0>5@1 S",
    "3 EE 0>5@1 S",
    "3 OH 7>14@.30 F X | quiet 0>7@1 F | plain 0>7@1 F",
    "3 OO 0>7@1 F",
    "3 SS 0>4@1 S",
    "3 FV L",
    "kind 5 keys 20 floor 0 cap 1 fv 0.125",
    "5 AA 0>8@1 S | loud 8>16@.50 F",
    "5 EH 0>7@1 S",
    "5 EE 0>10@1 S | quiet 0>5@1 S",
    "5 OH 4>6@.30 F | quiet 0>4@1 S",
    "5 OO 0>6@1 S",
    "5 SS 0>7@1 S",
    "5 FV L",
    "kind 7 keys 8 floor 0 cap 1 fv 0.125",
    "7 AA 0>4@1 S | loud 0>5@1 S",
    "7 EH 0>4@.40 S",
    "7 EE 0>4@.40 S",
    "7 OH 0>4@.70 S",
    "7 OO 0>4@.30 S",
    "7 SS 0>4@.40 S",
    "7 FV L",
};

struct TEntry {
    int a = 0, b = 0;
    float w = 0.0f;
    char how = 'C';      // C closed, S scales, F fixed, L ladder
    bool x = false, present = false;
};
struct TKind {
    int keys = 0;
    float floor = 0, cap = 1, fv = 0;
    TEntry e[V::COUNT][4];      // normal, quiet, loud, plain
};

static bool parse_entry(const std::string &t0, TEntry &e)
{
    std::string t = t0;
    while (!t.empty() && t.front() == ' ') t.erase(t.begin());
    while (!t.empty() && t.back() == ' ') t.pop_back();
    e = TEntry();
    e.present = true;
    if (t == "L") {
        e.how = 'L';
        e.a = e.b = -1;
        return true;
    }
    char how = 0, x = 0;
    int a = -9, b = -9;
    float w = -1;
    int n = std::sscanf(t.c_str(), "%d>%d@%f %c %c", &a, &b, &w, &how, &x);
    if (n < 4 || (how != 'S' && how != 'F')) return false;
    e.a = a;
    e.b = b;
    e.w = w;
    e.how = how;
    e.x = n == 5 && x == 'X';
    return true;
}

static bool parse_plan(std::map<int, TKind> &out, std::string &why)
{
    int cur = -1;
    for (const char *line : k_plan_43) {
        std::string s = line;
        if (s.compare(0, 5, "kind ") == 0) {
            TKind k;
            if (std::sscanf(line, "kind %d keys %d floor %f cap %f fv %f", &cur, &k.keys, &k.floor, &k.cap, &k.fv) != 5) {
                why = s;
                return false;
            }
            for (int c = 0; c < V::COUNT; c++) {
                k.e[c][0].present = true;     // closed (SIL, MBP; every class is given below otherwise)
            }
            out[cur] = k;
            continue;
        }
        int kind = -1;
        char cls[8] = {0};
        int used = 0;
        if (std::sscanf(line, "%d %7s %n", &kind, cls, &used) < 2 || kind != cur) {
            why = s;
            return false;
        }
        int c = -1;
        for (int k = 0; k < V::COUNT; k++) {
            if (std::string(V::name(k)) == cls) c = k;
        }
        if (c < 0) {
            why = s;
            return false;
        }
        std::string rest = s.substr((size_t)used);
        size_t pos = 0;
        int part = 0;
        while (pos <= rest.size()) {
            size_t bar = rest.find('|', pos);
            std::string item = rest.substr(pos, bar == std::string::npos ? std::string::npos : bar - pos);
            int slot = 0;
            for (int k = 1; k < 4; k++) {
                static const char *const names[4] = {"", "quiet ", "loud ", "plain "};
                size_t at = item.find(names[k]);
                if (at != std::string::npos) {
                    slot = k;
                    item = item.substr(at + std::strlen(names[k]));
                }
            }
            if ((part == 0) != (slot == 0) || !parse_entry(item, out[cur].e[c][slot])) {
                why = s;
                return false;
            }
            part++;
            if (bar == std::string::npos) break;
            pos = bar + 1;
        }
    }
    return true;
}

// 4.3's rule, implemented here again from the plan's words
static void plan_pick(const TKind &k, int cls, float s, float size, int variant, bool big, int &a, int &b, float &w)
{
    a = b = 0;
    w = 0.0f;
    if (cls == V::SIL || cls == V::MBP) return;
    const TEntry *E = k.e[cls];
    const TEntry *e = &E[0];
    if (variant == 1 && E[1].present) e = &E[1];
    if (variant == 2 && E[2].present) e = &E[2];
    if (e->x && !big) {
        if (E[3].present) e = &E[3];
        else if (E[1].present) e = &E[1];
        else if (!E[0].x) e = &E[0];
    }
    s = std::max(0.0f, std::min(1.0f, s));
    if (e->how == 'L') {
        a = b = -1;
        w = std::min(s, k.fv);
    } else if (e->how == 'S') {
        float f = std::max(1.0f - size, k.floor);
        a = e->a;
        b = e->b;
        w = std::max(0.0f, std::min(1.0f, e->w * (f + (1.0f - f) * s)));
    } else if (e->how == 'F') {
        a = e->a;
        b = e->b;
        w = e->w;
    }
}

static void test_table()
{
    std::printf("V8 the mouth table:\n");
    std::map<int, TKind> plan;
    std::string why;
    bool parsed = parse_plan(plan, why);
    CHECK(parsed && plan.size() == 5, "V8: the second transcription of 4.3 parses (%zu kinds)%s%s", plan.size(),
          why.empty() ? "" : ": bad line ", why.c_str());
    if (!parsed) return;
    int n = 0, bad = 0, keybad = 0, ladder = 0, ladder_bad = 0;
    std::string first;
    for (const auto &kv : plan) {
        int kind = kv.first;
        const TKind &k = kv.second;
        const mouth::Table *t = mouth::table(kind);
        if (!t || t->keys != k.keys || std::fabs(t->floor - k.floor) > 1e-6f || std::fabs(t->ladder_cap - k.cap) > 1e-6f ||
            std::fabs(t->fv_level - k.fv) > 1e-6f) {
            bad++;
            if (first.empty()) first = format("kind %d: the table's numbers", kind);
            continue;
        }
        for (int c = 0; c < V::COUNT; c++) {
            const mouth::Row &r = t->rows[c];
            const mouth::Entry *es[4] = {&r.normal, &r.quiet, &r.loud, &r.plain};
            for (int v = 0; v < 4; v++) {
                if (!es[v]->present) continue;
                if (es[v]->how == mouth::LADDER) {
                    ladder++;
                    ladder_bad += c != V::FV || es[v]->a != -1 || es[v]->b != -1;
                } else {
                    keybad += es[v]->a < 0 || es[v]->b < 0 || es[v]->a >= k.keys || es[v]->b >= k.keys ||
                              (kind == 7 && (es[v]->a > 5 || es[v]->b > 5));
                }
            }
            for (float s : {0.2f, 0.6f, 1.0f}) {
                for (float size : {0.0f, 0.5f, 1.0f}) {
                    for (int variant = 0; variant < 3; variant++) {
                        for (int big = 0; big < 2; big++) {
                            int a1, b1, a2, b2;
                            float w1, w2;
                            mouth::pick(kind, c, s, size, variant, big != 0, a1, b1, w1);
                            plan_pick(k, c, s, size, variant, big != 0, a2, b2, w2);
                            n++;
                            if (a1 != a2 || b1 != b2 || std::fabs(w1 - w2) > 1e-6f) {
                                bad++;
                                if (first.empty()) {
                                    first = format("kind %d %s s %.1f size %.1f variant %d big %d: %d>%d@%.3f, the plan %d>%d@%.3f",
                                                   kind, V::name(c), s, size, variant, big, a1, b1, w1, a2, b2, w2);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    int others = 0;
    for (int kind : {1, 4, 6, 8, -1, 9, 63}) {
        for (int c = -1; c <= 9; c++) {
            int a, b;
            float w;
            mouth::pick(kind, c, 1.0f, 0.5f, 0, true, a, b, w);
            others += a != 0 || b != 0 || w != 0.0f;
        }
        others += mouth::table(kind) != nullptr;
    }
    int a, b;
    float w;
    mouth::pick(0, 99, 1.0f, 0.5f, 0, true, a, b, w);
    others += a != 0 || b != 0 || w != 0.0f;
    mouth::pick(0, V::AA, std::nanf(""), std::nanf(""), 0, true, a, b, w);    // NaN s / size: clamped, no NaN out
    others += !std::isfinite(w);
    CHECK(bad == 0 && keybad == 0 && ladder == 5 && ladder_bad == 0 && others == 0,
          "V8: mouth::pick equals 4.3 for %d cases (5 face kinds x 9 classes x s 0.2 / 0.6 / 1 x size 0 / 0.5 / 1 x variant 0-2 "
          "x big 0 / 1)%s%s; every key below its kind's count (Sonic 21, Tails / Knuckles / Amy 20, Big 8 and never above "
          "5): %d bad; LADDER entries only on f v th (%d, %d elsewhere); E-102, Eggman, Tikal, Super Sonic and bad "
          "arguments closed (%d wrong)", n, first.empty() ? "" : ": first difference ", first.c_str(), keybad, ladder,
          ladder_bad, others);
}

// ---- V11, V12: end to end through the real libsa1 world (the disc) ------------------------------------------------------
#if defined(SA1_FACE_SAME_PAIR)
static const uint32_t kSamePair = SA1_FACE_SAME_PAIR;
#else
static const uint32_t kSamePair = 0u;
#endif

static void floor_tiles(std::vector<sa1_collision_tri> &out, float x0, float x1, float y0, float y1, float z, float tile)
{
    for (float x = x0; x < x1 - 0.5f; x += tile) {
        for (float y = y0; y < y1 - 0.5f; y += tile) {
            const float p[4][3] = {{x, y, z}, {x + tile, y, z}, {x + tile, y + tile, z}, {x, y + tile, z}};
            sa1_collision_tri a, b;
            std::memset(&a, 0, sizeof a);
            std::memset(&b, 0, sizeof b);
            const int ia[3] = {0, 1, 2}, ib[3] = {0, 2, 3};
            for (int v = 0; v < 3; v++) {
                std::memcpy(a.v[v], p[ia[v]], 12);
                std::memcpy(b.v[v], p[ib[v]], 12);
            }
            a.surface = b.surface = SA1_SURFACE_SOLID;
            out.push_back(a);
            out.push_back(b);
        }
    }
}

// how far apart two two-key blends are: half the L1 distance of their key weights (0 = the same shape; keys equal to each
// other merge, so 4>16@1 and 16>16@x are the same mouth)
static float mix_dist(int a1, int b1, float w1, int a2, int b2, float w2)
{
    std::map<int, float> m;
    m[a1] += 1.0f - w1;
    m[b1] += w1;
    m[a2] -= 1.0f - w2;
    m[b2] -= w2;
    float d = 0.0f;
    for (const auto &kv : m) d += std::fabs(kv.second);
    return 0.5f * d;
}

// the keys libsa1 writes for a level on the kind's ladder (sa1_world_face.c sf_lipsync; q rounded as sa1_face.c does)
static void ladder_keys(const sa1_face_info &fi, float level, int &a, int &b, float &w)
{
    uint32_t q = level >= 1.0f ? 4096u : (level <= 0.0f ? 0u : (uint32_t)(int32_t)(level * 4096.0f + 0.5f));
    uint32_t n = fi.ladder_len < 2u ? 2u : fi.ladder_len, p64 = (q * (n - 1u) * 64u + 2048u) / 4096u, i = p64 / 64u;
    if (i > n - 2u) i = n - 2u;
    a = fi.ladder[i];
    b = fi.ladder[i + 1u];
    w = (float)(p64 - 64u * i) / 64.0f;
}

// the mouth that should show for a class at openness s (the frame's own s), as keys and a weight
static void expected_mouth(int kind, int cls, float s, const sa1_face_info &fi, int &a, int &b, float &w)
{
    mouth::pick(kind, cls, s, 0.5f, mouth::VARIANT_NORMAL, true, a, b, w);
    if (a < 0) {
        ladder_keys(fi, w, a, b, w);
    } else {
        // libsa1 quantises the weight to 1/64 steps (r64)
        uint32_t q = w >= 1.0f ? 4096u : (uint32_t)(int32_t)(w * 4096.0f + 0.5f);
        w = (float)((q * 64u + 2048u) / 4096u) / 64.0f;
    }
}

struct PairRec {
    double t;             // ms: the simulated time of the frame whose tick ran the pair
    int from, to;
    float rate;
    float s;              // the openness this frame sent with
    int cls;              // the class the frame read (-1 none)
};

// an utterance through the fake BASS -> the classifier -> the mouth table -> libsa1, at 60 fps on a simulated clock: audio
// blocks of 160 samples arrive at their end time; each frame reads the newest classifier frame (GSA1PreTick's order),
// sends one mouth call with SAME_PAIR, then ticks 1/60 s (a pair on every other frame); every pair's face state is kept.
// analysis false: the negative control - cls -1, the loudness ladder at the 0.9.4a loudness (mic::level)
static void e2e_run(Session &s, int32_t id, int kind, const SY::Corpus &u, bool analysis, std::vector<PairRec> &out)
{
    out.clear();
    fresh_mic();
    if (!analysis) {
        mic::viseme_on(false);
    }
    std::vector<float> x = u.x;
    for (size_t j = 0; j < x.size(); j++) {
        x[j] += 0.0002f * (float)((uint32_t)(j * 1103515245u + 12345u) >> 16 & 0x7FFF) / 32768.0f - 0.0001f;
    }
    size_t next = 0;
    const Character *c = s.get(id);
    for (int f = 0; c; f++) {
        double t = f * 1000.0 / 60.0;
        while ((double)(next + 160) * 1000.0 / SY::RATE <= t && next + 160 <= x.size()) {
            deliver(x.data() + next, 160);
            next += 160;
        }
        if (next + 160 > x.size()) {
            break;
        }
        mic::VisemeFrame fr;
        mic::viseme_frame(fr);
        float sopen;
        if (fr.cls >= 0) {
            sopen = std::min(1.0f, fr.level * 2.0f);
            int a, b;
            float w;
            mouth::pick(kind, fr.cls, sopen, 0.5f, mouth::VARIANT_NORMAL, true, a, b, w);
            if (a < 0) {
                sa1_character_face_level(s.ctx(), id, w, SA1_FACE_LEVEL_LADDER | kSamePair);
            } else {
                sa1_character_face_mouth(s.ctx(), id, (uint32_t)a, (uint32_t)b, w, kSamePair);
            }
        } else {
            float lv = 0, pk = 0;
            std::string st;
            mic::level(lv, pk, st);
            sopen = std::min(1.0f, lv * 2.0f);
            sa1_character_face_level(s.ctx(), id, sopen, SA1_FACE_LEVEL_LADDER | kSamePair);
        }
        std::vector<sa1_event> ev;
        s.tick(id, 0.0f, 0.0f, 0.0f, 0u, 1.0f / 60.0f);
        s.poll_events(ev);
        c = s.get(id);
        if (c && c->pairs_last > 0) {
            PairRec r;
            r.t = t;
            r.from = c->st.face_from;
            r.to = c->st.face_to;
            r.rate = c->st.face_rate;
            r.s = sopen;
            r.cls = fr.cls;
            out.push_back(r);
        }
    }
}

static int truth_of(const char *label)
{
    std::string l = label;
    if (l == "A") return V::AA;
    if (l == "i") return V::EE;
    if (l == "u") return V::OO;
    if (l == "oh" || l == "O") return V::OH;
    if (l == "s") return V::SS;
    if (l == "f") return V::FV;
    if (l == "m") return V::MBP;
    return V::SIL;
}

static void test_e2e(const std::string &gdi)
{
    std::printf("V11 / V12 end to end (fake BASS -> classifier -> mouth table -> libsa1 world, SAME_PAIR %s):\n",
                kSamePair ? "on" : "not built");
    Session s;
    std::string err;
    bool ok = s.init(gdi, err);
    std::vector<sa1_collision_tri> fl;
    floor_tiles(fl, -4096.0f, 4096.0f, -2048.0f, 2048.0f, 0.0f, 1024.0f);
    ok = ok && s.set_world(fl, err);
    CHECK(ok, "the disc and a flat floor (%s)", err.c_str());
    if (!ok) {
        s.shutdown();
        return;
    }
    // the scored sounds come after a warm-up of the twelve vowels four times (12.5 s: the speaker number settles; V7 shows
    // the learning itself); "a" comes twice so that f and m follow a loud vowel, as in speech; "oh" is the synthesiser's
    // test-only rounded vowel (Hillenbrand's "law" sits on the classifier's AA / OH boundary: V1 counts it as it falls)
    static const char *const vowels12[] = {"i", "I", "e", "E", "ae", "A", "O", "o", "U", "u", "V", "3r"};
    std::vector<std::string> warm;
    for (int r = 0; r < 4; r++) {
        for (const char *v : vowels12) warm.push_back(v);
    }
    const std::vector<std::string> scored = {"oh", "A", "f", "A", "m", "i", "s", "u"};
    std::vector<std::string> labels = warm;
    labels.insert(labels.end(), scored.begin(), scored.end());
    std::vector<int> snd_ms(warm.size(), 200), gap_ms(warm.size(), 60);
    snd_ms.insert(snd_ms.end(), scored.size(), 450);
    gap_ms.insert(gap_ms.end(), scored.size(), 250);
    const size_t first_scored = warm.size();
    const float tol = 2.0f / 64.0f + 1e-3f;     // 1/64 (the weight's quantisation) + one step of the face task
    struct KindRes {
        int kind;
        long ok = 0, n = 0, ctl_ok = 0, ctl_n = 0, sil_ok = 0, sil_n = 0;
        long per_ok[8] = {}, per_n[8] = {};
        bool big_keys = true;
    };
    std::vector<KindRes> res;
    for (int kind : {0, 2, 3, 5, 7}) {
        KindRes kr;
        kr.kind = kind;
        sa1_face_info fi;
        std::memset(&fi, 0, sizeof fi);
        fi.struct_size = sizeof fi;
        sa1_face_info_get(s.ctx(), kind, &fi);
        for (int g : {SY::GRP_MEN, SY::GRP_WOMEN}) {
            SY::Corpus u = SY::utterance(g, 31u + (uint32_t)kind, labels, snd_ms, gap_ms, 500);
            for (int analysis = 1; analysis >= 0; analysis--) {
                const float at[3] = {(float)(-3000 + 1000 * (kind % 5)), 0.0f, 8.0f};
                int32_t id = s.create(kind, at, 0.0f, err);
                if (id <= 0) {
                    CHECK(false, "kind %d created (%s)", kind, err.c_str());
                    continue;
                }
                for (int p = 0; p < 4; p++) {
                    std::vector<sa1_event> ev;
                    s.tick(id, 0, 0, 0, 0u, 1.0f / 30.0f);
                    s.poll_events(ev);
                }
                std::vector<PairRec> recs;
                e2e_run(s, id, kind, u, analysis != 0, recs);
                s.destroy(id);
                for (size_t k = 1; k < u.segs.size(); k++) {
                    double a = u.segstart[k] * 1000.0 / SY::RATE, b = u.segstart[k + 1] * 1000.0 / SY::RATE;
                    double lo = a + 0.2 * (b - a), hi = a + 0.8 * (b - a);
                    int item = (int)(k - 1) / 2;
                    if ((size_t)item < first_scored) continue;      // the warm-up
                    item -= (int)first_scored;
                    bool sound = (k % 2) == 1;
                    int cls = sound ? truth_of(scored[(size_t)item].c_str()) : V::SIL;
                    for (const PairRec &r : recs) {
                        if (r.t < lo || r.t > hi) continue;
                        int ea, eb;
                        float ew;
                        expected_mouth(kind, cls, r.s, fi, ea, eb, ew);
                        bool same = mix_dist(ea, eb, ew, r.from, r.to, r.rate) <= tol;
                        if (g_verbose && !same && analysis) {
                            std::printf("        kind %d %s %s t %.0f: heard %s, shows %d>%d@%.3f, expected %d>%d@%.3f (s %.2f)\n",
                                        kind, SY::group_name(g), sound ? scored[(size_t)item].c_str() : "silence", r.t,
                                        r.cls >= 0 ? V::name(r.cls) : "-", r.from, r.to, r.rate, ea, eb, ew, r.s);
                        }
                        if (kind == 7 && analysis) {
                            kr.big_keys = kr.big_keys && r.from <= 5 && r.to <= 5;
                        }
                        if (!sound) {
                            if (analysis) {
                                kr.sil_n++;
                                kr.sil_ok += same;
                            }
                        } else if (analysis) {
                            kr.n++;
                            kr.ok += same;
                            kr.per_n[item]++;
                            kr.per_ok[item] += same;
                        } else if (cls >= V::AA && cls <= V::OO) {
                            kr.ctl_n++;
                            kr.ctl_ok += same;
                        }
                    }
                }
            }
        }
        res.push_back(kr);
    }
    bool all_ok = true, ctl_fails = true;
    for (const KindRes &kr : res) {
        std::string per;
        bool each = true;
        for (size_t i = 0; i < scored.size(); i++) {
            per += format(" %s %ld/%ld", scored[i].c_str(), kr.per_ok[i], kr.per_n[i]);
            each = each && kr.per_n[i] > 0 && kr.per_ok[i] * 4 >= kr.per_n[i] * 3;
        }
        bool sil = kr.sil_n > 0 && kr.sil_ok * 4 >= kr.sil_n * 3;
        bool ctl = kr.ctl_n > 0 && kr.ctl_ok * 4 < kr.ctl_n * 3;
        all_ok = all_ok && each && sil && kr.big_keys;
        ctl_fails = ctl_fails && ctl;
        std::printf("        kind %d: sounds%s; silences closed %ld/%ld; negative control (analysis off) vowels %ld/%ld%s\n",
                    kr.kind, per.c_str(), kr.sil_ok, kr.sil_n, kr.ctl_ok, kr.ctl_n, kr.kind == 7 ? (kr.big_keys ?
                    "; Big only keys 0 / 4 / 5" : "; Big: a key above 5!") : "");
    }
    CHECK(all_ok, "V11: Sonic, Tails, Knuckles, Amy and Big, a man and a woman: in the middle 60 %% of each oh / a / f / i / s / u / "
          "m at least 75 %% of the pairs show the true class' mouth (keys AND weight within 1/64 + one step; f on the "
          "ladder at most at the kind's fv_level; m closed), the silences closed, Big only keys 0 / 4 / 5");
    CHECK(ctl_fails, "V11: the negative control - the same runs with the analysis off (the loudness ladder) - FAILS the vowel "
          "checks for every kind (below 75 %%)");

    // V12: 50 vowel onsets after silence at random phases of block, frame and pair (Tails' "ah": 0>16)
    std::vector<float> lat;
    {
        uint32_t r = 4242u;
        for (int g : {SY::GRP_MEN, SY::GRP_WOMEN}) {
            std::vector<std::string> l(25, "A");
            std::vector<int> snd(25, 250), gap(25);
            for (int k = 0; k < 25; k++) {
                r = r * 1664525u + 1013904223u;
                gap[k] = 300 + (int)((r >> 8) % 211u);
            }
            SY::Corpus u = SY::utterance(g, 77u + (uint32_t)g, l, snd, gap, 400);
            const float at[3] = {0.0f, 0.0f, 8.0f};
            int32_t id = s.create(2, at, 0.0f, err);
            if (id <= 0) continue;
            sa1_face_info fi;
            std::memset(&fi, 0, sizeof fi);
            fi.struct_size = sizeof fi;
            sa1_face_info_get(s.ctx(), 2, &fi);
            std::vector<PairRec> recs;
            e2e_run(s, id, 2, u, true, recs);
            s.destroy(id);
            for (size_t k = 1; k < u.segs.size(); k += 2) {
                double t0 = u.segstart[k] * 1000.0 / SY::RATE, t1 = u.segstart[k + 1] * 1000.0 / SY::RATE;
                for (const PairRec &rr : recs) {
                    if (rr.t < t0) continue;
                    if (rr.t > t1) break;
                    int ea, eb;
                    float ew;
                    expected_mouth(2, V::AA, rr.s, fi, ea, eb, ew);
                    if (mix_dist(ea, eb, ew, rr.from, rr.to, rr.rate) <= tol) {
                        lat.push_back((float)(rr.t - t0));
                        break;
                    }
                }
            }
        }
    }
    std::sort(lat.begin(), lat.end());
    std::string dist;
    for (size_t i = 0; i < lat.size(); i += std::max<size_t>(1, lat.size() / 10)) dist += format(" %.0f", lat[i]);
    float med = median(lat), p9 = p90(lat);
    CHECK(lat.size() >= 45 && med <= 50.0f && p9 <= 80.0f,
          "V12: %zu of 50 vowel onsets reach the face: from the vowel's first sample to the frame whose tick runs the first "
          "pair that shows it, median %.0f ms (<= 50; the plan expects 30-40), p90 %.0f ms (<= 80); every tenth:%s ms. "
          "Drawn: %s (LIB F33 / F35); Windows' capture (about 15 ms) and the render's interpolation (17-33 ms) come on top",
          lat.size(), med, p9, dist.c_str(), kSamePair ? "in that same pair with SAME_PAIR (+0), one pair later without (+33 ms)"
                                                       : "one pair later (+33 ms: SAME_PAIR not built)");
    s.shutdown();
}

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--gdi" && i + 1 < argc) {
            gdi = argv[++i];
        } else if (a == "--verbose") {
            g_verbose = true;
        } else if (a == "--src" && i + 1 < argc) {
            g_src = argv[++i];
        } else {
            std::printf("usage: feat_viseme_test [--gdi GAME.gdi] [--src G-SA1-TREE] [--verbose]\n");
            return 2;
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_viseme_test (libsa1 %s)\n", sa1_version_string());
    double t0 = now_us();
    for (int set = 0; set < SY::SET_COUNT; set++) {
        for (int g = 0; g < SY::GRP_COUNT; g++) {
            g_corpus.push_back(SY::corpus(set, g));
        }
    }
    size_t samples = 0;
    for (const SY::Corpus &c : g_corpus) samples += c.x.size();
    std::printf("  info  the synthetic corpus: 9 files, %.0f s of speech made in memory in %.1f s\n",
                (double)samples / SY::RATE, (now_us() - t0) / 1e6);
    test_accuracy();
    test_silence();
    test_cost();
    test_mxcsr_blocks();
    test_atomic();
    test_press_voice();
    test_stress();
    test_privacy(parent_dir(argv[0]));
    test_table();
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: V11 / V12 need the disc\n");
    } else {
        test_e2e(gdi);
    }
    mic::set_test_api(nullptr);
    std::printf("\n%d checks, %d failed (%.1f s)\n", g_checks, g_fail, (now_us() - t0) / 1e6);
    return g_fail ? 1 : 0;
}
