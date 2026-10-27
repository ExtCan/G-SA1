// feat_hear_test: the lip-sync fix's hearing, the module's side (round 0.9.4e, feature "faces" 3; sadc docs/research/
// lipsync2_plan.md 6.1 V1c, V1g, V3, V4, V6f, V7w, V7d, V13, V14 with its Review R.1 / R.3 / R.4 / R.5 / R.7; lipsync2_hear.md
// 4-6). Linked like core_test (the core and libsa1) by build.py; needs no disc.
//
//   feat_hear_test [--verbose]
//
// The speech is synthetic, made in memory by tests/viseme_corpus2.hpp ("corpus 2": the lipsync2 research prototype's
// synthesiser, English-like corpus, channels and scoring, ported bit for bit; fixed seeds): no WAV file, no recording of
// anyone, no owner number. The default set is US men, US women and British-like men, 2 speakers each, 30 s of speech plus
// each speaker's guided warm-up part; V1c runs on the research's whole set (5 groups x 6 speakers x 50 s, the USB channel).
//   V13 agreement golden: the default set through v2 (src/core/viseme.cpp) gives exactly the prototype's truth x shown count
//       matrices, configurations P and W (the guided warm-up) on all five channels (clean, USB room, narrowband, USB + a
//       noise suppressor, quiet microphone). The constants come from r094e/hear/agree/proto_golden.txt: the review's
//       vis_new.cpp (var_guard 4 = the category cap, plus rule set B in warm_end) run on the same in-memory corpus. The
//       whole-corpus agreement (every frame of 13 configurations x 150 runs) is r094e/hear/agree/compare_out.txt.
//   V1c corpus 2's whole set, USB: v2's class accuracy >= its own run minus 3 points; EE <= 12 % and >= 2.5 % of the vowel
//       frames; EE precision >= 50 % (fewer than 50 shown EE frames fails it); EE recall >= 25 %; vowel frames shown closed
//       (MBP) <= 12 %; /s/ shown SS >= 75 %. NEGATIVE CONTROL: v1 (0.9.4c's) on the same frames closes > 25 % of the vowel
//       frames and shows EE on > 18 % of them. Both confusion matrices printed.
//   V1g British-like men, USB: with the guided warm-up GOOSE ("oo") -> OO >= 60 %, GOAT ("oh") -> OH or OO >= 55 %; without
//       it GOOSE -> OO < 25 % (the case needs the warm-up).
//   V3  latency and flicker (clean and USB): v2's medians open <= 30 ms, close <= 40 ms, shape change <= 60 ms and within
//       +2 ms of v1's on the same frames; face changes at the 30 Hz pair rate <= 12 per s. p90s reported.
//   V4  cost per 10 ms block with FTZ / DAZ, best of 3: v2 mean <= 12 us and p99 <= 25 us; v1 reported.
//   V6f atomic 2 (the frame's features) round-trips within its quantisation (lowr / zcr included: review R.3); through the
//       RECORDPROC its seq equals atomic 1's and its numbers are the frame's; cat / raw 15 read as -1.
//   V7w the guided warm-up through the fake BASS (engine 2, a British-like man's sustained ah / ee / oo / oh with gaps):
//       result 1, ah / ee / oo >= 20 frames, warmed, the "oo" category moved toward the speaker's "oo"; 0.15 s corners ->
//       result 2 with the speaker statistics bit-identical; cancel -> result 3, the sums cleared; refused with engine 1,
//       "adapt" 0, nothing open; every step applied on the RECORDPROC thread only; a held vowel during "ready" and the
//       gaps teaches nothing (review R.1); "oo" said for "ee" -> result 4, the statistics bit-identical (review R.5).
//   V7d one held vowel must not retrain the voice (review R.1): 15 s of each speaker's warm-up "ah" (or "ee") with its room
//       silence, then the speech: accuracy >= the fresh run minus 3 and EE <= 12 % (with "ee": >= 2.5 %) of the vowel
//       frames; 30 s of game-like sound first: v2 >= v1 + 10 points. NEGATIVE CONTROL: cat_cap 0 loses > 8 points.
//   V14 a fake BASS whose device 6 is "Speakers (Example Audio)" with the loopback flag (invented names only): devices()
//       flags it; open2(6) -> OPEN_LOOPBACK with the text and nothing opened; an input opens; force re-opens it (RecordStart
//       again, the voice kept); device_name() is the opened device's name.
//   R.3 (reported, the next round's baseline) the per-RAW-class medians of rel_loc / per / nbr / lowr / zcr on the default
//       set, USB, as atomic 2 quantises them (the frames of the speech whose raw class is not SIL; 2026-10-27):
//         MBP -12.5/0.94/0.98/0.84/0.06 n1518   AA 0.0/0.85/0.98/0.39/0.14 n1613   EH -0.2/0.91/0.97/0.65/0.11 n5899
//         EE 0.0/0.95/0.91/0.71/0.14 n348       OH 0.0/0.95/1.00/0.61/0.06 n403    OO 0.0/0.95/1.00/0.77/0.05 n1146
//         SS -7.0/0.36/0.07/0.00/0.63 n1037     FV -17.8/0.40/0.38/0.10/0.40 n285
//       The owner's numbers log (feature "faces" 3, "Log my voice's numbers") keys its medians the same way: compare like
//       with like (a per-rule domain shift), not with the thresholds alone (review R.3).
//
// MEASURED (2026-10-27; the port, v2 with the category cap): V13 0 of 810 cells differ (106,640 frames); the whole-corpus
// agreement 9,990,505 of 9,990,505 frames (13 configurations x 150 runs; r094e/hear/agree/compare_out.txt); V1c accuracy
// 77.9 % (v1 62.7), EE 4.4 % of vowel frames, precision 59.0 %, recall 28.6 %, vowels closed 5.9 % (v1 38.6), /s/ -> SS
// 86.7 %; V1g GOOSE -> OO 61.8 % with the warm-up (5.6 without), GOAT 90.1 %; V3 USB open 30 / close 27 / shape 47 ms (v1
// 39 / 25 / 49), 9.7 face changes / s; V4 v2 about 6.5-10 us per block depending on the machine's load (v1 4-7); V7d fresh
// 77.6 %, held "ah" 78.2, held "ee" 77.2, game-like v2 50.0 against v1 33.9, cat_cap 0 after the held "ah" 61.1 %.
// Corpus 2's synthesiser (synth2.c, ported bit for bit) makes loud glitches (|x| up to about 20) in about half of the seconds
// of every speaker's speech - in the prototype's numbers too; V7w / V14 pick glitch-free windows (clean_speech).
//
// API NOTES (094e-gsa1-hear; lipsync2_plan.md 5.3 as built - for 094e-gsa1-mouths, 094e-gsa1-lua, the verifier):
//   src/core/viseme.hpp (v2, namespace gsa1::viseme): classes SIL..FV and kRate / kWin / kHop / kRing / kDecTaps / kDecN as
//     0.9.4c; kMaxOrder 14, kCats 12. Params / Frame / State = the prototype's hear2:: ones (Frame + eep, the EE posterior;
//     Params + cat_cap 2.5; State + cat_h / cat_H, prior_tot, warmed). default_params, init, feed, reset_press, reset_voice,
//     reinit_keep_voice, warm_begin (0-3 corners, 4 a gap), warm_end -> 1 learned / 2 too short / 4 unclear, warm_cancel,
//     prior_g, voice_g, name, word, cat_name, cat_class. No decide_only / learn_only.
//   src/core/viseme_v1.hpp (namespace gsa1::viseme_v1): 0.9.4c's viseme.hpp verbatim.
//   src/core/mic.hpp: kDeviceLoopback 8, Device.loopback; open2(device, force, err) -> OPEN_OK / OPEN_FAILED /
//     OPEN_LOOPBACK ("that device records what your PC plays (a speaker output), not a microphone"; nothing opened or
//     closed); "engine" tune 1 / 2 (default 2; anything else refused); viseme_engine(); viseme_warm(WARM_AH .. WARM_CANCEL)
//     refused (false + err) for a bad step ("MicVisemeWarmup: no step N"), engine 1 ("needs 'Sound detection' 0.9.4e"),
//     adapt 0 ("needs 'Learn my voice'"), nothing open ("the microphone is not open"); WarmState {phase -1..4, n[4] 0..255,
//     result 0 none / 1 learned / 2 too short / 3 cancelled / 4 unclear}; viseme_voice2(g, frames, f1, f2, warmed) (f1 /
//     f2 = the learned means in 4 Hz steps, 0 before learning and with engine 1); viseme_features (atomic 2) with
//     features_pack / features_unpack; viseme_debug_states (tests only). A new warm-up (a step while none runs) clears the
//     last result; the RECORDPROC applies the newest step at its next block.
//   PRIVACY (owner PQ7): the voice and the warm-up live in the two States and the atomics for the session only; close(),
//     "reset_voice" and "adapt" 0 forget both engines' voices and the warm-up. Lua may SHOW MicVisemeVoice /
//     MicVisemeWarmupState; it never writes them anywhere (file, ConVar, cookie, sqlite / PData, log line, net message).
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
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <xmmintrin.h>
#define FH_TEST_MXCSR 1
#endif

#include "viseme_corpus2.hpp"
#include "../src/core/mic.hpp"
#include "../src/core/util.hpp"
#include "../src/core/viseme.hpp"
#include "../src/core/viseme_v1.hpp"

using namespace gsa1;
namespace V = gsa1::viseme;
namespace V1 = gsa1::viseme_v1;
namespace C2 = gsa1test::corpus2;

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

// ---- a fake of BASS's recording API: devices 0-7, 6 and 7 loopbacks (invented names; review R.7) ----------------------
struct Fake {
    std::atomic<mic::RecordProc *> proc{nullptr};
    std::atomic<int> starts{0}, stops{0}, inits{0};
};
static Fake g_fake;
static uint32_t g_fake_dev = 0;
static int GSA1_MICCALL f_init(int device)
{
    g_fake.inits++;
    g_fake_dev = device < 0 ? 0u : (uint32_t)device;
    return 1;
}
static int GSA1_MICCALL f_free(void) { return 1; }
static int GSA1_MICCALL f_info(uint32_t device, mic::DeviceInfo *info)
{
    static const char *names[] = {"Default", "Microphone (Example USB Mic)", "Headset Microphone (Example Pad)",
                                  "Stereo Mix (Example Audio)", "Line In (Example Audio)", "Microphone (Example Voice Changer)",
                                  "Speakers (Example Audio)", "Speakers (Example USB Mic)"};
    if (device > 7) {
        return 0;
    }
    info->name = names[device];
    info->driver = "fake";
    info->flags = mic::kDeviceEnabled | (device == 0 || device == 5 ? mic::kDeviceDefault : 0u) |
                  (device >= 6 ? mic::kDeviceLoopback : 0u);
    return 1;
}
static int GSA1_MICCALL f_set(uint32_t d)
{
    g_fake_dev = d;
    return 1;
}
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

static void deliver(const float *x, int n)
{
    mic::RecordProc *p = g_fake.proc.load();
    if (p && n > 0) {
        p(0x42, x, (uint32_t)(n * sizeof(float)), nullptr);
    }
}
// blocks [a, b) of x through the RECORDPROC; with g_bass_thread on BASS's own (a thread of its own, joined): the test's
// thread then plays the Lua thread only (V7w: every step must be applied on the RECORDPROC's thread)
static bool g_bass_thread = false;
static void deliver_all(const std::vector<float> &x, size_t a, size_t b)
{
    auto run = [&x, a, b]() {
        for (size_t i = a; i + 160 <= b && i + 160 <= x.size(); i += 160) deliver(x.data() + i, 160);
    };
    if (g_bass_thread) {
        std::thread t(run);
        t.join();
    } else {
        run();
    }
}
// a window of `seconds` of a speaker's speech without the synthesiser's loud glitches (its nasal-coupling resonators now and
// then make samples of |x| > 1 - in the prototype's corpus too, e.g. the default set's first British-like man; a glitch
// right before a warm-up holds the slow peak high for seconds): its start sample, or SIZE_MAX when there is none
static size_t clean_speech(const std::vector<float> &y, int speech_start, int seconds)
{
    const size_t len = (size_t)seconds * 16000u;
    for (size_t a = (size_t)speech_start; a + len <= y.size(); a += 16000u) {
        float mx = 0.0f;
        for (size_t i = a; i < a + len; i++) mx = std::max(mx, std::fabs(y[i]));
        if (mx < 0.9f) return a;
    }
    return SIZE_MAX;
}
// a fresh microphone on the fake (engine 2): open, analysis on, listening
static bool fresh_mic(int device = 1)
{
    mic::set_test_api(&k_fake);     // closes: the classifiers forget everything
    std::string err;
    mic::viseme_tune("engine", 2, err);
    mic::viseme_tune("adapt", 1, err);
    bool ok = mic::open(device, err);
    mic::viseme_on(true);
    ok = ok && mic::listen(true, err);
    return ok;
}

// ---- running the classifiers the way the prototype's driver does (run_cfg) ----------------------------------------------
// v2 over the corpus' speech in 160-sample blocks; warm: first the warm-up part with the page's prompts (each prompt's
// window runs from the end of the previous vowel to the end of its own), then a press. frames: every v2 frame (optional)
static void run_v2(const C2::Corpus &C, const std::vector<float> &x, const V::Params &p, bool warm, std::vector<C2::Out> &out,
                   std::vector<V::Frame> *frames = nullptr, int *warm_result = nullptr)
{
    out.clear();
    if (frames) frames->clear();
#if defined(FH_TEST_MXCSR)
    unsigned csr = _mm_getcsr();
    _mm_setcsr(csr | 0x8040u);
#endif
    V::State *s = new V::State;
    V::init(*s, p);
    if (warm) {
        int cur = -1, res = 0;
        for (int i = 0; i + 160 <= C.speech_start; i += 160) {
            int ph = -1;
            for (int c = 0; c < 4; c++) {
                int a = c == 0 ? 0 : C.warm_bounds[2 * c - 1], b = C.warm_bounds[2 * c + 1];
                if (i >= a && i < b) ph = c;
            }
            if (ph != cur) {
                if (cur == 3) res = V::warm_end(*s, 800.0f);
                if (ph >= 0) V::warm_begin(*s, ph);
                cur = ph;
            }
            V::Frame f;
            V::feed(*s, x.data() + i, 160, &f, 1);
        }
        if (cur == 3) res = V::warm_end(*s, 800.0f);
        if (warm_result) *warm_result = res;
        V::reset_press(*s);
    }
    for (int i = C.speech_start; i + 160 <= (int)x.size(); i += 160) {
        V::Frame f;
        if (V::feed(*s, x.data() + i, 160, &f, 1)) {
            out.push_back({f.cls, f.raw, f.f1, f.f2, i + 160});
            if (frames) frames->push_back(f);
        }
    }
    delete s;
#if defined(FH_TEST_MXCSR)
    _mm_setcsr(csr);
#endif
}
// v1 (0.9.4c's classifier) over the same speech
static void run_v1(const C2::Corpus &C, const std::vector<float> &x, std::vector<C2::Out> &out)
{
    out.clear();
#if defined(FH_TEST_MXCSR)
    unsigned csr = _mm_getcsr();
    _mm_setcsr(csr | 0x8040u);
#endif
    V1::Params p;
    V1::default_params(p);
    V1::State *s = new V1::State;
    V1::init(*s, p);
    for (int i = C.speech_start; i + 160 <= (int)x.size(); i += 160) {
        V1::Frame f;
        if (V1::feed(*s, x.data() + i, 160, &f, 1)) out.push_back({f.cls, f.raw, f.f1, f.f2, i + 160});
    }
    delete s;
#if defined(FH_TEST_MXCSR)
    _mm_setcsr(csr);
#endif
}

// the default set: US men, US women, British-like men (corpus groups 0, 1, 3), 2 speakers each, 30 s; built first, in this
// order, so the unit registry is the prototype's (viseme_corpus2.hpp's note)
struct Spk {
    int group;
    C2::Speaker sp;
    C2::Corpus C;
    std::vector<float> ch[C2::CH_COUNT];
};
static std::vector<Spk> g_set;
static void build_default_set()
{
    for (int g : {0, 1, 3}) {
        for (int k = 0; k < 2; k++) {
            Spk s;
            s.group = g;
            s.sp = C2::make_speaker(g, k);
            C2::build_corpus(s.C, s.sp, 30.0);
            for (int ci = 0; ci < C2::CH_COUNT; ci++) s.ch[ci] = C2::apply_cond(s.C, ci, C2::cond_seed(s.sp, ci));
            g_set.push_back(std::move(s));
        }
    }
}

static long vowel_all(const C2::Score &s)
{
    long v = 0;
    for (int c = 0; c < C2::COUNT; c++) v += s.vowel_out[c];
    return v;
}
static void print_conf(const char *title, const long conf[C2::COUNT][C2::COUNT])
{
    std::printf("        %s (rows truth, columns shown, %% of the row)\n              ", title);
    for (int b = 0; b < C2::COUNT; b++) std::printf("%6s", C2::CLS[b]);
    std::printf("      n\n");
    for (int a = 0; a < C2::COUNT; a++) {
        long t = 0;
        for (int b = 0; b < C2::COUNT; b++) t += conf[a][b];
        if (!t) continue;
        std::printf("          %-4s", C2::CLS[a]);
        for (int b = 0; b < C2::COUNT; b++) std::printf("%6.1f", C2::pct(conf[a][b], t));
        std::printf(" %6ld\n", t);
    }
}
static double unit_share(const C2::Score &s, const char *unit, unsigned classes, long *n_out = nullptr)
{
    int u = C2::unit_find(unit);
    long t = 0, ok = 0;
    if (u >= 0 && (size_t)u < s.unit.size()) {
        for (int b = 0; b < C2::COUNT; b++) {
            t += s.unit[(size_t)u][b];
            if (classes & (1u << b)) ok += s.unit[(size_t)u][b];
        }
    }
    if (n_out) *n_out = t;
    return C2::pct(ok, t);
}

// ---- V13: the agreement golden --------------------------------------------------------------------------------------
// r094e/hear/agree/proto_golden.txt (2026-10-27): the review's vis_new.cpp (var_guard 4 by default, rule set B in
// warm_end) run by the prototype's driver ("hear.exe golden") on the default set: [P, W][channel][truth][shown] counts
static const long k_golden[2][C2::CH_COUNT][C2::COUNT][C2::COUNT] = {{
    // P, clean (-70 dB floor): 10664 scored frames, accuracy 79.04 %
    {{4190, 77, 5, 47, 2, 2, 1, 3, 0}, {0, 213, 8, 122, 16, 2, 12, 1, 0}, {0, 19, 649, 293, 5, 1, 50, 2, 0},
     {0, 131, 235, 1728, 25, 4, 86, 12, 5}, {0, 44, 4, 277, 116, 1, 3, 5, 1}, {0, 14, 123, 259, 3, 174, 115, 1, 0},
     {0, 40, 8, 96, 1, 34, 132, 3, 2}, {0, 7, 9, 92, 1, 1, 3, 544, 48}, {0, 274, 16, 98, 9, 1, 0, 16, 143}},
    // P, USB mic, room (pink 30 dB, proximity +5 dB, 7 kHz): 10664 scored frames, accuracy 75.52 %
    {{4325, 0, 0, 2, 0, 0, 0, 0, 0}, {42, 190, 10, 93, 15, 1, 19, 4, 0}, {0, 28, 630, 300, 4, 12, 43, 2, 0},
     {0, 159, 232, 1685, 31, 2, 109, 5, 3}, {0, 48, 5, 291, 102, 1, 0, 4, 0}, {0, 31, 108, 243, 0, 192, 114, 1, 0},
     {0, 38, 9, 111, 1, 35, 119, 3, 0}, {18, 9, 9, 114, 2, 1, 4, 479, 69}, {368, 135, 2, 44, 2, 0, 0, 0, 6}},
    // P, narrowband headset 300-3400 + white 25 dB: 10664 scored frames, accuracy 67.07 %
    {{4325, 0, 0, 0, 0, 0, 0, 2, 0}, {358, 7, 0, 9, 0, 0, 0, 0, 0}, {35, 9, 645, 286, 2, 2, 31, 7, 2},
     {242, 57, 165, 1667, 7, 3, 64, 19, 2}, {18, 25, 4, 279, 108, 1, 1, 15, 0}, {17, 6, 134, 280, 0, 158, 91, 3, 0},
     {42, 27, 8, 117, 0, 25, 97, 0, 0}, {632, 0, 2, 6, 0, 0, 0, 45, 20}, {549, 0, 0, 7, 0, 0, 0, 1, 0}},
    // P, USB + noise suppressor: 10664 scored frames, accuracy 70.60 %
    {{3985, 156, 67, 98, 3, 5, 5, 6, 2}, {86, 159, 8, 97, 4, 3, 13, 4, 0}, {0, 47, 617, 294, 2, 10, 46, 2, 1},
     {0, 247, 231, 1599, 27, 2, 111, 6, 3}, {0, 48, 6, 278, 110, 1, 3, 4, 1}, {1, 41, 112, 230, 5, 187, 112, 1, 0},
     {0, 46, 12, 102, 2, 35, 117, 2, 0}, {105, 5, 9, 90, 2, 1, 6, 442, 45}, {400, 86, 13, 52, 4, 1, 0, 1, 0}},
    // P, quiet mic -20 dB + room: 10664 scored frames, accuracy 73.99 %
    {{4327, 0, 0, 0, 0, 0, 0, 0, 0}, {100, 154, 8, 86, 8, 2, 14, 2, 0}, {0, 27, 619, 310, 2, 10, 49, 2, 0},
     {0, 150, 235, 1675, 27, 3, 127, 6, 3}, {0, 50, 4, 280, 112, 1, 1, 3, 0}, {0, 33, 112, 243, 3, 186, 111, 1, 0},
     {0, 42, 9, 110, 4, 34, 114, 3, 0}, {65, 9, 9, 91, 2, 1, 5, 473, 50}, {507, 33, 0, 15, 2, 0, 0, 0, 0}},
}, {
    // W, clean (-70 dB floor): 10664 scored frames, accuracy 82.76 %
    {{4209, 103, 1, 7, 1, 1, 4, 1, 0}, {0, 295, 4, 33, 18, 4, 15, 5, 0}, {0, 23, 572, 347, 2, 9, 63, 3, 0},
     {0, 211, 95, 1564, 116, 13, 217, 9, 1}, {0, 109, 1, 96, 217, 1, 26, 1, 0}, {0, 23, 33, 81, 2, 231, 314, 5, 0},
     {0, 76, 2, 7, 13, 33, 182, 2, 1}, {0, 2, 7, 34, 4, 1, 5, 601, 51}, {0, 326, 8, 38, 4, 0, 9, 13, 159}},
    // W, USB mic, room (pink 30 dB, proximity +5 dB, 7 kHz): 10664 scored frames, accuracy 78.07 %
    {{4326, 0, 0, 0, 0, 0, 1, 0, 0}, {34, 299, 3, 21, 6, 1, 9, 1, 0}, {0, 36, 567, 330, 3, 12, 69, 2, 0},
     {0, 295, 89, 1494, 88, 20, 232, 7, 1}, {0, 112, 0, 92, 218, 1, 27, 1, 0}, {0, 44, 51, 72, 0, 225, 295, 2, 0},
     {0, 72, 5, 18, 16, 36, 169, 0, 0}, {19, 6, 5, 47, 8, 3, 17, 526, 74}, {372, 163, 2, 5, 2, 0, 7, 0, 6}},
    // W, narrowband headset 300-3400 + white 25 dB: 10664 scored frames, accuracy 68.67 %
    {{4327, 0, 0, 0, 0, 0, 0, 0, 0}, {360, 13, 0, 1, 0, 0, 0, 0, 0}, {32, 10, 558, 317, 3, 18, 79, 2, 0},
     {241, 53, 81, 1388, 83, 11, 360, 9, 0}, {17, 58, 9, 131, 184, 0, 31, 21, 0}, {17, 6, 27, 72, 3, 254, 306, 4, 0},
     {38, 33, 5, 42, 1, 28, 169, 0, 0}, {630, 0, 2, 2, 0, 0, 2, 48, 21}, {550, 6, 0, 0, 0, 1, 0, 0, 0}},
    // W, USB + noise suppressor: 10664 scored frames, accuracy 71.56 %
    {{3875, 214, 161, 60, 3, 3, 7, 4, 0}, {106, 228, 4, 17, 6, 2, 9, 2, 0}, {0, 55, 560, 312, 4, 14, 72, 2, 0},
     {2, 381, 91, 1415, 82, 21, 231, 3, 0}, {0, 112, 1, 89, 217, 0, 31, 1, 0}, {1, 56, 52, 76, 3, 212, 288, 1, 0},
     {0, 75, 7, 14, 15, 36, 169, 0, 0}, {112, 4, 6, 42, 7, 3, 8, 472, 51}, {408, 108, 12, 17, 2, 0, 9, 0, 1}},
    // W, quiet mic -20 dB + room: 10664 scored frames, accuracy 76.27 %
    {{4327, 0, 0, 0, 0, 0, 0, 0, 0}, {99, 240, 2, 12, 5, 1, 13, 2, 0}, {0, 35, 571, 322, 3, 15, 71, 2, 0},
     {0, 278, 93, 1506, 96, 19, 228, 6, 0}, {0, 107, 0, 96, 220, 1, 26, 1, 0}, {0, 44, 51, 71, 3, 235, 283, 2, 0},
     {0, 77, 5, 15, 16, 37, 165, 1, 0}, {66, 3, 5, 34, 8, 3, 19, 508, 59}, {507, 43, 0, 0, 4, 0, 3, 0, 0}},
}};

static void test_golden()
{
    std::printf("V13 agreement golden (the default set, configurations P and W, every channel):\n");
    long frames = 0, differ = 0;
    std::string first;
    std::vector<C2::Out> out;
    for (int w = 0; w < 2; w++) {
        for (int ci = 0; ci < C2::CH_COUNT; ci++) {
            C2::Score all;
            for (const Spk &s : g_set) {
                V::Params p;
                V::default_params(p);
                run_v2(s.C, s.ch[ci], p, w != 0, out);
                C2::Score sc;
                C2::score(sc, s.C, out);
                all.add(sc);
            }
            for (int a = 0; a < C2::COUNT; a++) {
                for (int b = 0; b < C2::COUNT; b++) {
                    frames += all.conf[a][b];
                    if (all.conf[a][b] != k_golden[w][ci][a][b]) {
                        differ++;
                        if (first.empty()) {
                            first = format("%s %s truth %s shown %s: %ld, the prototype %ld", w ? "W" : "P", C2::CH_NAME[ci],
                                           C2::CLS[a], C2::CLS[b], all.conf[a][b], k_golden[w][ci][a][b]);
                        }
                    }
                }
            }
            if (g_verbose) {
                std::printf("        %s %-52s accuracy %.2f %%\n", w ? "W" : "P", C2::CH_NAME[ci], C2::pct(all.ok_new, all.n));
            }
        }
    }
    CHECK(differ == 0 && frames > 100000,
          "V13: v2 gives exactly the prototype's truth x shown matrices on the default set - 2 configurations (P, W) x 5 "
          "channels x 81 cells, %ld scored frames: %ld cells differ%s%s", frames, differ, first.empty() ? "" : "; first: ",
          first.c_str());
}

// ---- V1c: corpus 2's whole set, USB ------------------------------------------------------------------------------------
// v2's own run on it (r094e/hear/agree/port_all.txt, the port with the category cap: USB "P" row, 2026-10-27): 77.9 %
static const double k_v1c_own = 77.9;

static void test_v1c()
{
    std::printf("V1c corpus 2, the whole set (5 groups x 6 speakers x 50 s), USB microphone in a room:\n");
    double t0 = now_us();
    C2::Score s2, s1;
    std::vector<C2::Out> out;
    for (int g = 0; g < 5; g++) {
        for (int k = 0; k < 6; k++) {
            C2::Speaker sp = C2::make_speaker(g, k);
            C2::Corpus C;
            C2::build_corpus(C, sp, 50.0);
            std::vector<float> y = C2::apply_cond(C, C2::CH_USB, C2::cond_seed(sp, C2::CH_USB));
            V::Params p;
            V::default_params(p);
            run_v2(C, y, p, false, out);
            C2::Score a;
            C2::score(a, C, out);
            s2.add(a);
            run_v1(C, y, out);
            C2::Score b;
            C2::score(b, C, out);
            s1.add(b);
        }
    }
    struct Num {
        double acc, ee_share, prec, rec, mbp, s_ss;
        long shown;
    };
    auto nums = [](const C2::Score &s) {
        Num n;
        n.acc = C2::pct(s.ok_new, s.n);
        n.ee_share = C2::pct(s.vowel_out[C2::EE], s.vowel_frames());
        n.shown = s.ee_tp + s.ee_fp;
        n.prec = C2::pct(s.ee_tp, n.shown);
        n.rec = C2::pct(s.ee_tp, s.ee_tp + s.ee_fn);
        n.mbp = C2::pct(s.vowel_out[C2::MBP], vowel_all(s));
        n.s_ss = unit_share(s, "s", 1u << C2::SS);
        return n;
    };
    Num a = nums(s2), b = nums(s1);
    std::printf("        %.1f s; v2: accuracy %.1f %%, EE %.1f %% of the shown vowel frames (truth %.1f), precision %.1f %% of %ld "
                "shown, recall %.1f %%, vowel frames closed %.1f %%, /s/ -> SS %.1f %%\n", (now_us() - t0) / 1e6, a.acc,
                a.ee_share, C2::pct(s2.vowel_truth[C2::EE], s2.vowel_truth[2] + s2.vowel_truth[3] + s2.vowel_truth[4] +
                s2.vowel_truth[5] + s2.vowel_truth[6]), a.prec, a.shown, a.rec, a.mbp, a.s_ss);
    std::printf("        v1 on the same frames: accuracy %.1f %%, EE %.1f %%, precision %.1f %%, recall %.1f %%, vowel frames "
                "closed %.1f %%, /s/ -> SS %.1f %%\n", b.acc, b.ee_share, b.prec, b.rec, b.mbp, b.s_ss);
    print_conf("v2 (0.9.4e)", s2.conf);
    print_conf("v1 (0.9.4c)", s1.conf);
    CHECK(a.acc >= k_v1c_own - 3.0 && a.ee_share <= 12.0 && a.ee_share >= 2.5 && a.shown >= 50 && a.prec >= 50.0 &&
              a.rec >= 25.0 && a.mbp <= 12.0 && a.s_ss >= 75.0,
          "V1c: v2 accuracy %.1f %% (>= %.1f: its own run %.1f minus 3); EE %.1f %% of the vowel frames (2.5..12); EE precision "
          "%.1f %% of %ld shown (>= 50 %% of at least 50); EE recall %.1f %% (>= 25); vowel frames shown closed %.1f %% (<= 12); "
          "/s/ -> SS %.1f %% (>= 75)", a.acc, k_v1c_own - 3.0, k_v1c_own, a.ee_share, a.prec, a.shown, a.rec, a.mbp, a.s_ss);
    CHECK(b.mbp > 25.0 && b.ee_share > 18.0,
          "V1c negative control: v1 on the same frames closes %.1f %% of the vowel frames (> 25) and shows EE on %.1f %% of "
          "them (> 18) - the corpus sees the defects v2 fixes", b.mbp, b.ee_share);
}

// ---- V1g: British-like men, USB: GOOSE and GOAT with and without the warm-up ---------------------------------------------
static void test_v1g()
{
    std::printf("V1g British-like men (the default set's), USB microphone:\n");
    C2::Score sp, sw;
    std::vector<C2::Out> out;
    int learned = 0, tried = 0;
    for (const Spk &s : g_set) {
        if (s.group != 3) continue;
        V::Params p;
        V::default_params(p);
        run_v2(s.C, s.ch[C2::CH_USB], p, false, out);
        C2::Score a;
        C2::score(a, s.C, out);
        sp.add(a);
        int res = 0;
        run_v2(s.C, s.ch[C2::CH_USB], p, true, out, nullptr, &res);
        C2::Score b;
        C2::score(b, s.C, out);
        sw.add(b);
        tried++;
        learned += res == 1;
    }
    const unsigned oo = 1u << C2::OO, ohoo = (1u << C2::OH) | (1u << C2::OO);
    long n_goose = 0, n_g1 = 0, n_g2 = 0;
    double goose_p = unit_share(sp, "u", oo), goose_w = unit_share(sw, "u", oo, &n_goose);
    double g1w = unit_share(sw, "oU.1", ohoo, &n_g1), g2w = unit_share(sw, "oU.2", ohoo, &n_g2);
    double g1p = unit_share(sp, "oU.1", ohoo), g2p = unit_share(sp, "oU.2", ohoo);
    double goat_w = (n_g1 + n_g2) ? (g1w * n_g1 + g2w * n_g2) / (double)(n_g1 + n_g2) : 0.0;
    double goat_p = (n_g1 + n_g2) ? (g1p * n_g1 + g2p * n_g2) / (double)(n_g1 + n_g2) : 0.0;
    CHECK(learned == tried && tried == 2 && n_goose > 0 && goose_w >= 60.0 && goat_w >= 55.0 && goose_p < 25.0,
          "V1g: with the guided warm-up (%d of %d learned) GOOSE \"oo\" -> OO %.1f %% of %ld frames (>= 60), GOAT \"oh\" (onset / "
          "glide %.1f / %.1f) -> OH or OO %.1f %% (>= 55); without it GOOSE -> OO %.1f %% (< 25: the case needs the warm-up), "
          "GOAT %.1f %%", learned, tried, goose_w, n_goose, g1w, g2w, goat_w, goose_p, goat_p);
}

// ---- V3: latency and flicker -------------------------------------------------------------------------------------------
static void test_latency()
{
    std::printf("V3 latency and flicker (the default set; ms from a segment's start to the end of the first frame that "
                "shows it; median / p90):\n");
    bool ok = true;
    std::string rows;
    for (int ci : {C2::CH_CLEAN, C2::CH_USB}) {
        C2::Score s2, s1;
        std::vector<C2::Out> out;
        for (const Spk &s : g_set) {
            V::Params p;
            V::default_params(p);
            run_v2(s.C, s.ch[ci], p, false, out);
            C2::Score a;
            C2::score(a, s.C, out);
            s2.add(a);
            run_v1(s.C, s.ch[ci], out);
            C2::Score b;
            C2::score(b, s.C, out);
            s1.add(b);
        }
        float on = C2::quant(s2.lat_on, 0.5), off = C2::quant(s2.lat_off, 0.5), sh = C2::quant(s2.lat_shape, 0.5);
        float sh1 = C2::quant(s1.lat_shape, 0.5);
        double fc = s2.secs > 0 ? s2.fc_out / s2.secs : 0.0;
        ok = ok && on <= 30.0f && off <= 40.0f && sh <= 60.0f && sh <= sh1 + 2.0f && fc <= 12.0;
        std::printf("        %-52s v2 opens %.0f / %.0f, closes %.0f / %.0f, shape %.0f / %.0f, %.1f face changes / s; v1 "
                    "opens %.0f / %.0f, closes %.0f / %.0f, shape %.0f / %.0f, %.1f / s (truth %.1f / s)\n", C2::CH_NAME[ci],
                    on, C2::quant(s2.lat_on, 0.9), off, C2::quant(s2.lat_off, 0.9), sh, C2::quant(s2.lat_shape, 0.9), fc,
                    C2::quant(s1.lat_on, 0.5), C2::quant(s1.lat_on, 0.9), C2::quant(s1.lat_off, 0.5),
                    C2::quant(s1.lat_off, 0.9), sh1, C2::quant(s1.lat_shape, 0.9), s1.secs > 0 ? s1.fc_out / s1.secs : 0.0,
                    s2.secs > 0 ? s2.fc_truth / s2.secs : 0.0);
        rows += format("%s %s: open %.0f, close %.0f, shape %.0f (v1 %.0f), %.1f changes / s", rows.empty() ? "" : ";",
                       ci == C2::CH_CLEAN ? "clean" : "USB", on, off, sh, sh1, fc);
    }
    CHECK(ok, "V3: v2's medians open <= 30 ms, close <= 40 ms, shape change <= 60 ms and within +2 ms of v1's; face changes at "
          "the 30 Hz pair rate <= 12 / s -%s", rows.c_str());
}

// ---- V4: the cost per block ----------------------------------------------------------------------------------------------
static void test_cost()
{
    std::printf("V4 cost per 10 ms block with FTZ / DAZ (the default set's first man, USB, the whole file; best of 3):\n");
    const Spk &s = g_set[0];
    const std::vector<float> &y = s.ch[C2::CH_USB];
    double best[2] = {1e30, 1e30}, p99[2] = {0, 0}, med[2] = {0, 0};
    for (int e = 0; e < 2; e++) {
        for (int rep = 0; rep < 3; rep++) {
            std::vector<float> per;
#if defined(FH_TEST_MXCSR)
            unsigned csr = _mm_getcsr();
            _mm_setcsr(csr | 0x8040u);
#endif
            if (e == 0) {
                V::Params p;
                V::default_params(p);
                V::State *st = new V::State;
                V::init(*st, p);
                for (size_t i = 0; i + 160 <= y.size(); i += 160) {
                    V::Frame f;
                    double t0 = now_us();
                    V::feed(*st, y.data() + i, 160, &f, 1);
                    per.push_back((float)(now_us() - t0));
                }
                delete st;
            } else {
                V1::Params p;
                V1::default_params(p);
                V1::State *st = new V1::State;
                V1::init(*st, p);
                for (size_t i = 0; i + 160 <= y.size(); i += 160) {
                    V1::Frame f;
                    double t0 = now_us();
                    V1::feed(*st, y.data() + i, 160, &f, 1);
                    per.push_back((float)(now_us() - t0));
                }
                delete st;
            }
#if defined(FH_TEST_MXCSR)
            _mm_setcsr(csr);
#endif
            double m = 0;
            for (float v : per) m += v;
            m /= per.empty() ? 1 : per.size();
            if (m < best[e]) {
                best[e] = m;
                med[e] = C2::quant(per, 0.5);
                p99[e] = C2::quant(per, 0.99);
            }
        }
    }
    CHECK(best[0] <= 12.0 && p99[0] <= 25.0,
          "V4: v2 %.2f us per block (median %.2f, p99 %.2f; <= 12 / 25); v1 %.2f us (median %.2f, p99 %.2f); the States are "
          "%u and %u bytes", best[0], med[0], p99[0], best[1], med[1], p99[1], (unsigned)sizeof(V::State),
          (unsigned)sizeof(V1::State));
}


// ---- V6f: atomic 2 ---------------------------------------------------------------------------------------------------------
static void test_features_atomic()
{
    std::printf("V6f atomic 2 (the frame's features):\n");
    int n = 0, bad = 0;
    for (float rl : {0.0f, -0.1f, -12.3f, -63.75f, -80.0f}) {
        for (float per : {0.0f, 0.5f, 1.0f}) {
            for (float nbr : {0.0f, 0.04f, 1.0f}) {
                for (float eep : {0.0f, 0.55f, 1.0f}) {
                    for (int cat : {-1, 0, 11}) {
                        for (int raw : {-1, 0, 8}) {
                            for (uint32_t seq : {0u, 1u, 65535u, 65536u}) {
                                for (float lowr : {0.0f, 0.37f, 1.0f}) {
                                    for (float zcr : {0.0f, 0.5f, 1.0f}) {
                                        mic::VisemeFeatures a, b;
                                        a.rel_loc = rl;
                                        a.per = per;
                                        a.nbr = nbr;
                                        a.eep = eep;
                                        a.cat = cat;
                                        a.raw = raw;
                                        a.seq = seq;
                                        a.lowr = lowr;
                                        a.zcr = zcr;
                                        mic::features_unpack(mic::features_pack(a), b);
                                        n++;
                                        float rlc = std::max(rl, -63.75f);
                                        bool ok = std::fabs(b.rel_loc - rlc) <= 0.125f + 1e-5f &&
                                                  std::fabs(b.per - per) <= 0.5f / 127.0f + 1e-6f &&
                                                  std::fabs(b.nbr - nbr) <= 0.5f / 127.0f + 1e-6f &&
                                                  std::fabs(b.eep - eep) <= 0.5f / 127.0f + 1e-6f && b.cat == cat &&
                                                  b.raw == raw && b.seq == (seq & 0xFFFFu) &&
                                                  std::fabs(b.lowr - lowr) <= 0.5f / 31.0f + 1e-6f &&
                                                  std::fabs(b.zcr - zcr) <= 0.5f / 63.0f + 1e-6f;
                                        bad += !ok;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    mic::VisemeFeatures none;
    mic::features_unpack(((uint64_t)15u << 45) | ((uint64_t)15u << 49), none);
    CHECK(bad == 0 && none.cat == -1 && none.raw == -1,
          "V6f: the packing round-trips %d feature sets (rel_loc 0.25 dB down to -63.75, per / nbr / eep 1/127, cat / raw, seq "
          "16 bits, lowr 1/31, zcr 1/63): %d differ; cat / raw 15 read as -1 (%d, %d)", n, bad, none.cat, none.raw);
    // through the RECORDPROC: each block's atomic 2 carries atomic 1's seq and the newest frame's features
    const Spk &s = g_set[0];
    const std::vector<float> &y = s.ch[C2::CH_USB];
    V::Params p;
    V::default_params(p);
    V::State *st = new V::State;
    V::init(*st, p);
    V::reset_press(*st);     // as the microphone starts a press
    fresh_mic();
    long blocks = 0, seq_bad = 0, val_bad = 0, frames = 0;
    for (size_t i = 0; i + 160 <= std::min(y.size(), (size_t)(20 * C2::RATE)); i += 160) {
        V::Frame f;
#if defined(FH_TEST_MXCSR)
        unsigned csr = _mm_getcsr();
        _mm_setcsr(csr | 0x8040u);
#endif
        int got = V::feed(*st, y.data() + i, 160, &f, 1);
#if defined(FH_TEST_MXCSR)
        _mm_setcsr(csr);
#endif
        deliver(y.data() + i, 160);
        blocks++;
        mic::VisemeFrame fr;
        mic::viseme_frame(fr);
        mic::VisemeFeatures ft;
        mic::viseme_features(ft);
        if (!got) continue;
        frames++;
        seq_bad += ft.seq != fr.seq;
        mic::VisemeFeatures want, wq;
        want.rel_loc = f.rel_loc;
        want.per = f.per;
        want.nbr = f.nbr;
        want.eep = f.eep;
        want.cat = f.cat;
        want.raw = f.raw;
        want.seq = fr.seq;
        want.lowr = f.lowr;
        want.zcr = f.zcr;
        mic::features_unpack(mic::features_pack(want), wq);
        val_bad += wq.rel_loc != ft.rel_loc || wq.per != ft.per || wq.nbr != ft.nbr || wq.eep != ft.eep || wq.cat != ft.cat ||
                   wq.raw != ft.raw || wq.lowr != ft.lowr || wq.zcr != ft.zcr;
    }
    delete st;
    CHECK(frames > 1000 && seq_bad == 0 && val_bad == 0,
          "V6f: through the RECORDPROC (%ld blocks, %ld frames) atomic 2's seq equals atomic 1's every time (%ld differ) and its "
          "numbers are the frame's (the same classifier fed beside it; %ld differ)", blocks, frames, seq_bad, val_bad);
}

// ---- V7w: the guided warm-up through the fake BASS ----------------------------------------------------------------------
struct Voice {
    double mu[2], var[2], wn;
    float shift[V::kCats][2];
    uint32_t vf;
};
static Voice voice_of_mic()
{
    V::State *st = new V::State;
    mic::viseme_debug_states(st, nullptr);
    Voice v;
    std::memcpy(v.mu, st->mu, sizeof v.mu);
    std::memcpy(v.var, st->var, sizeof v.var);
    v.wn = st->wn;
    std::memcpy(v.shift, st->shift, sizeof v.shift);
    v.vf = st->voice_frames;
    delete st;
    return v;
}
static bool same_voice(const Voice &a, const Voice &b)
{
    return std::memcmp(a.mu, b.mu, sizeof a.mu) == 0 && std::memcmp(a.var, b.var, sizeof a.var) == 0 && a.wn == b.wn &&
           std::memcmp(a.shift, b.shift, sizeof a.shift) == 0 && a.vf == b.vf;
}
static int cat_index(const char *name)
{
    for (int c = 0; c < V::kCats; c++) {
        if (std::strcmp(V::cat_name(c), name) == 0) return c;
    }
    return -1;
}
// the page's flow on the warm-up part of a corpus-2 speaker: "ready" (a gap) on segment 0, then each corner with a gap
// after it, "done" on the last silence; src[c] = which corner's audio is played when corner c is asked (0..3), samples
// limits each corner's audio (0 = all of it)
static int warm_flow(const Spk &s, const int src[4], int samples, uint32_t n[4])
{
    const C2::Corpus &C = s.C;
    const std::vector<float> &y = s.ch[C2::CH_USB];
    std::string err;
    std::vector<float> sil(320, 0.0f);
    bool ok = mic::viseme_warm(mic::WARM_GAP, err);       // "ready"
    deliver_all(y, (size_t)C.start[0], (size_t)C.start[1]);
    static const int corner_step[4] = {mic::WARM_AH, mic::WARM_EE, mic::WARM_OO, mic::WARM_OH};
    for (int c = 0; c < 4; c++) {
        ok = mic::viseme_warm(corner_step[c], err) && ok;
        int a = C.start[1 + 2 * src[c]], b = C.start[2 + 2 * src[c]];
        if (samples > 0) b = std::min(b, a + samples);
        deliver_all(y, (size_t)a, (size_t)b);
        if (g_verbose) {
            mic::WarmState w;
            mic::viseme_warm_state(w);
            V::State *st = new V::State;
            mic::viseme_debug_states(st, nullptr);
            std::printf("        [warm_flow] corner %d (audio %d, %d..%d): phase %d n %u %u %u %u; state phase %d peak %.1f floor %.1f\n",
                        c, src[c], a, b, w.phase, w.n[0], w.n[1], w.n[2], w.n[3], st->warm_phase, st->peak_db, st->floor_db);
            delete st;
        }
        ok = mic::viseme_warm(mic::WARM_GAP, err) && ok;
        deliver_all(y, (size_t)C.start[2 + 2 * c], (size_t)C.start[3 + 2 * c]);
    }
    ok = mic::viseme_warm(mic::WARM_DONE, err) && ok;
    deliver_all(sil, 0, sil.size());
    mic::WarmState ws;
    mic::viseme_warm_state(ws);
    for (int c = 0; c < 4; c++) n[c] = ws.n[c];
    return ok ? ws.result : -1;
}

static void test_warmup()
{
    std::printf("V7w the guided warm-up through the fake BASS (engine 2; a British-like man of corpus 2, USB):\n");
    const Spk *gb = nullptr;
    for (const Spk &s : g_set) {
        if (s.group == 3) {
            gb = &s;
            break;
        }
    }
    const std::vector<float> &y = gb->ch[C2::CH_USB];
    const C2::Corpus &C = gb->C;
    std::string err;
    // 3 s of clean speech to learn a voice from first (the first default-set speaker that has such a window)
    const std::vector<float> *ysp = nullptr;
    size_t sp0 = SIZE_MAX;
    for (const Spk &s : g_set) {
        sp0 = clean_speech(s.ch[C2::CH_USB], s.C.speech_start, 3);
        if (sp0 != SIZE_MAX) {
            ysp = &s.ch[C2::CH_USB];
            break;
        }
    }
    if (!ysp) {
        CHECK(false, "V7w: a default-set speaker with 3 s of speech without a synthesiser glitch");
        return;
    }
    const size_t sp1 = sp0 + 3u * (size_t)C2::RATE;
    g_bass_thread = true;                 // every block on a thread of its own from here on (V7w)
    mic::VisemeDebug d0;
    mic::viseme_debug(d0);
    mic::viseme_debug_mark_thread();      // this thread plays the Lua thread
    // (1) the page's flow, said as asked
    fresh_mic();
    const int asked[4] = {0, 1, 2, 3};
    uint32_t n[4];
    int res = warm_flow(*gb, asked, 0, n);
    float g, f1, f2;
    uint32_t frames;
    bool warmed;
    mic::viseme_voice2(g, frames, f1, f2, warmed);
    V::State *st = new V::State;
    mic::viseme_debug_states(st, nullptr);
    int cu = cat_index("u");
    double m2 = st->warm_n[2] > 0 ? st->warm_sum[2][1] / st->warm_n[2] : 0.0;
    double x2 = (m2 - st->mu[1]) / std::sqrt(st->var[1]), ref = st->ref_x[cu][1], moved = ref + st->shift[cu][1];
    bool toward = std::fabs(x2 - moved) < std::fabs(x2 - ref);
    delete st;
    mic::VisemeDebug d1;
    mic::viseme_debug(d1);
    CHECK(res == 1 && n[0] >= 20 && n[1] >= 20 && n[2] >= 20 && warmed && f1 > 0.0f && f2 > 0.0f && toward &&
              d1.marked_thread_entries == d0.marked_thread_entries && d1.overlaps == d0.overlaps,
          "V7w: ready, ah, gap, ee, gap, oo, gap, oh, done -> result %d (1 learned), frames ah %u ee %u oo %u oh %u (>= 20), "
          "warmed %d, the learned means F1 / F2 %.0f / %.0f Hz; the \"oo\" category moved toward the speaker's \"oo\" (F2 z %.2f: "
          "the category from %.2f to %.2f); every step applied on the RECORDPROC's thread (entries on this one: %llu)", res, n[0],
          n[1], n[2], n[3], warmed, f1, f2, x2, ref, moved, (unsigned long long)(d1.marked_thread_entries - d0.marked_thread_entries));
    // (2) 0.15 s corners: too short, the voice bit-identical
    fresh_mic();
    deliver_all(*ysp, sp0, sp1);
    Voice before = voice_of_mic();
    int res2 = warm_flow(*gb, asked, C2::RATE * 15 / 100, n);
    Voice after = voice_of_mic();
    bool w2 = true;
    mic::viseme_voice2(g, frames, f1, f2, w2);
    CHECK(res2 == 2 && same_voice(before, after) && before.vf > 0 && !w2,
          "V7w: 0.15 s corners (ah %u ee %u oo %u frames) -> result %d (2 too short); the speaker statistics (means, spreads, "
          "weight, shifts, %u frames) are bit-identical to before, not warmed", n[0], n[1], n[2], res2, after.vf);
    // (3) cancel
    fresh_mic();
    bool c1 = mic::viseme_warm(mic::WARM_GAP, err) && mic::viseme_warm(mic::WARM_AH, err);
    deliver_all(y, (size_t)C.start[1], (size_t)C.start[1] + C2::RATE / 2);
    mic::WarmState mid;
    mic::viseme_warm_state(mid);
    bool c2 = mic::viseme_warm(mic::WARM_CANCEL, err);
    deliver_all(y, (size_t)C.start[2], (size_t)C.start[2] + 320);
    mic::WarmState ws;
    mic::viseme_warm_state(ws);
    st = new V::State;
    mic::viseme_debug_states(st, nullptr);
    bool cleared = st->warm_phase == -1 && st->warm_n[0] == 0.0 && st->warm_sum[0][0] == 0.0;
    delete st;
    CHECK(c1 && c2 && mid.phase == 0 && mid.n[0] > 0 && ws.result == 3 && ws.phase == -1 && ws.n[0] == 0 && cleared,
          "V7w: cancel during \"ah\" (phase %d, %u frames counted) -> result %d (3 cancelled), phase %d, the sums cleared (%s)",
          mid.phase, mid.n[0], ws.result, ws.phase, cleared ? "yes" : "NO");
    // (4) refusals
    std::string e1, e2, e3, e4;
    mic::viseme_tune("engine", 1, err);
    bool r1 = !mic::viseme_warm(mic::WARM_AH, e1);
    mic::viseme_tune("engine", 2, err);
    mic::viseme_tune("adapt", 0, err);
    bool r2 = !mic::viseme_warm(mic::WARM_AH, e2);
    mic::viseme_tune("adapt", 1, err);
    bool r4 = !mic::viseme_warm(7, e4) && !mic::viseme_warm(-1, err);
    mic::set_test_api(&k_fake);      // closes: nothing open
    bool r3 = !mic::viseme_warm(mic::WARM_AH, e3);
    CHECK(r1 && r2 && r3 && r4, "V7w: refused with engine 1 (\"%s\"), \"adapt\" 0 (\"%s\"), nothing open (\"%s\") and a bad step "
          "(\"%s\")", e1.c_str(), e2.c_str(), e3.c_str(), e4.c_str());
    // (5) review R.1: a held vowel during "ready" and the gaps teaches nothing
    fresh_mic();
    deliver_all(*ysp, sp0, sp1);
    Voice v0 = voice_of_mic();
    mic::viseme_warm(mic::WARM_GAP, err);                  // "ready" with a held "ah"
    deliver_all(y, (size_t)C.start[1], (size_t)C.start[2]);
    Voice v1 = voice_of_mic();
    mic::WarmState g1;
    mic::viseme_warm_state(g1);
    mic::viseme_warm(mic::WARM_AH, err);
    deliver_all(y, (size_t)C.start[1], (size_t)C.start[2]);
    mic::viseme_warm(mic::WARM_GAP, err);                  // a gap with the "ee" held
    mic::WarmState g2a;
    deliver_all(y, (size_t)C.start[3], (size_t)C.start[3] + 160);
    mic::viseme_warm_state(g2a);
    deliver_all(y, (size_t)C.start[3] + 160, (size_t)C.start[4]);
    mic::WarmState g2b;
    mic::viseme_warm_state(g2b);
    Voice v2 = voice_of_mic();
    mic::viseme_warm(mic::WARM_CANCEL, err);
    deliver_all(y, (size_t)C.start[4], (size_t)C.start[4] + 320);
    CHECK(same_voice(v0, v1) && same_voice(v0, v2) && v0.vf > 0 && g1.phase == 4 && g1.n[0] == 0 && g2b.phase == 4 &&
              g2b.n[1] == 0 && g2b.n[0] == g2a.n[0] && g2a.n[0] > 0,
          "V7w: a held \"ah\" during \"ready\" (phase %d, nothing counted) and a held \"ee\" during a gap (phase %d; ee %u, ah stays "
          "%u) teach the voice nothing - means, spreads, weight, shifts and its %u frames bit-identical (review R.1)", g1.phase,
          g2b.phase, g2b.n[1], g2b.n[0], v0.vf);
    // (6) review R.5: "oo" said for "ee" (and "ee" for "oo") -> unclear, nothing changes
    fresh_mic();
    deliver_all(*ysp, sp0, sp1);
    Voice s0 = voice_of_mic();
    const int swapped[4] = {0, 2, 1, 3};
    int res6 = warm_flow(*gb, swapped, 0, n);
    Voice s1 = voice_of_mic();
    mic::viseme_voice2(g, frames, f1, f2, w2);
    g_bass_thread = false;
    CHECK(res6 == 4 && same_voice(s0, s1) && !w2,
          "V7w: \"oo\" said for \"ee\" and \"ee\" for \"oo\" (counted %u / %u / %u) -> result %d (4 unclear); the speaker statistics "
          "bit-identical, not warmed (review R.5)", n[0], n[1], n[2], res6);
}

// ---- V7d: one held vowel must not retrain the voice (review R.1) ---------------------------------------------------------
static void run_prefixed(const Spk &s, const std::vector<float> &px, int engine, float cat_cap, C2::Score &sc)
{
    const std::vector<float> &y = s.ch[C2::CH_USB];
    std::vector<C2::Out> out;
#if defined(FH_TEST_MXCSR)
    unsigned csr = _mm_getcsr();
    _mm_setcsr(csr | 0x8040u);
#endif
    if (engine == 2) {
        V::Params p;
        V::default_params(p);
        p.cat_cap = cat_cap;
        V::State *st = new V::State;
        V::init(*st, p);
        for (size_t i = 0; i + 160 <= px.size(); i += 160) {
            V::Frame f;
            V::feed(*st, px.data() + i, 160, &f, 1);
        }
        V::reset_press(*st);
        for (int i = s.C.speech_start; i + 160 <= (int)y.size(); i += 160) {
            V::Frame f;
            if (V::feed(*st, y.data() + i, 160, &f, 1)) out.push_back({f.cls, f.raw, f.f1, f.f2, i + 160});
        }
        delete st;
    } else {
        V1::Params p;
        V1::default_params(p);
        V1::State *st = new V1::State;
        V1::init(*st, p);
        for (size_t i = 0; i + 160 <= px.size(); i += 160) {
            V1::Frame f;
            V1::feed(*st, px.data() + i, 160, &f, 1);
        }
        V1::reset_press(*st);
        for (int i = s.C.speech_start; i + 160 <= (int)y.size(); i += 160) {
            V1::Frame f;
            if (V1::feed(*st, y.data() + i, 160, &f, 1)) out.push_back({f.cls, f.raw, f.f1, f.f2, i + 160});
        }
        delete st;
    }
#if defined(FH_TEST_MXCSR)
    _mm_setcsr(csr);
#endif
    C2::Score a;
    C2::score(a, s.C, out);
    sc.add(a);
}

static void test_drift()
{
    std::printf("V7d one held vowel (review R.1; the default set, USB):\n");
    C2::Score fresh, ah, ee, ah0, game2, game1;
    for (const Spk &s : g_set) {
        const std::vector<float> &y = s.ch[C2::CH_USB];
        std::vector<float> none, pah, pee, pg;
        // the speaker's warm-up "ah" / "ee" with the room silence before it, repeated to 15 s
        while (pah.size() < (size_t)C2::RATE * 15) pah.insert(pah.end(), y.begin() + s.C.start[0], y.begin() + s.C.start[2]);
        while (pee.size() < (size_t)C2::RATE * 15) pee.insert(pee.end(), y.begin() + s.C.start[2], y.begin() + s.C.start[4]);
        C2::gen_game(pg, C2::RATE * 30, 777u + s.sp.seed);
        run_prefixed(s, none, 2, 2.5f, fresh);
        run_prefixed(s, pah, 2, 2.5f, ah);
        run_prefixed(s, pee, 2, 2.5f, ee);
        run_prefixed(s, pah, 2, 0.0f, ah0);
        run_prefixed(s, pg, 2, 2.5f, game2);
        run_prefixed(s, pg, 1, 0.0f, game1);
    }
    auto acc = [](const C2::Score &s) { return C2::pct(s.ok_new, s.n); };
    auto ees = [](const C2::Score &s) { return C2::pct(s.vowel_out[C2::EE], s.vowel_frames()); };
    double f = acc(fresh);
    CHECK(acc(ah) >= f - 3.0 && ees(ah) <= 12.0 && acc(ee) >= f - 3.0 && ees(ee) <= 12.0 && ees(ee) >= 2.5 &&
              acc(game2) >= acc(game1) + 10.0,
          "V7d: fresh %.1f %% (EE %.1f %% of the vowel frames); after 15 s of a held \"ah\" %.1f %% (>= %.1f; EE %.1f, <= 12); "
          "after a held \"ee\" %.1f %% (EE %.1f, 2.5..12); after 30 s of game-like sound v2 %.1f %% against v1 %.1f %% (+10)", f,
          ees(fresh), acc(ah), f - 3.0, ees(ah), acc(ee), ees(ee), acc(game2), acc(game1));
    CHECK(acc(ah0) < f - 8.0, "V7d negative control: without the category cap (cat_cap 0) the held \"ah\" costs %.1f points "
          "(%.1f %%; more than 8; review: 77.8 -> 60.8 %%), EE %.1f %% of the vowel frames", f - acc(ah0), acc(ah0), ees(ah0));
}

// ---- V14: the loopback device ------------------------------------------------------------------------------------------
static void test_loopback()
{
    std::printf("V14 a loopback device on the fake BASS (invented names):\n");
    mic::set_test_api(&k_fake);
    std::vector<mic::Device> devs;
    std::string err;
    bool listed = mic::devices(devs, err) && devs.size() == 8;
    int flagged = 0;
    for (const mic::Device &d : devs) flagged += d.loopback ? (d.index >= 6 ? 1 : 100) : 0;
    int inits0 = g_fake.inits.load(), starts0 = g_fake.starts.load();
    std::string e6;
    int r6 = mic::open2(6, false, e6);
    bool nothing = mic::device_index() == -2 && g_fake.inits.load() == inits0 && g_fake.starts.load() == starts0;
    std::string e1;
    int r1 = mic::open2(1, false, e1);
    std::string name1 = mic::device_name();
    mic::viseme_on(true);
    mic::listen(true, err);
    const std::vector<float> &y = g_set[2].ch[C2::CH_USB];
    size_t w0 = clean_speech(y, g_set[2].C.speech_start, 3);
    if (w0 == SIZE_MAX) w0 = (size_t)g_set[2].C.speech_start;
    deliver_all(y, w0, w0 + 3u * (size_t)C2::RATE);
    float ga, gb2;
    uint32_t na, nb;
    mic::viseme_voice(ga, na);
    std::string e7;
    int r7 = mic::open2(7, false, e7);
    bool still = mic::device_index() == 1;
    int starts1 = g_fake.starts.load();
    std::string ef;
    int rf = mic::open2(1, true, ef);
    int starts2 = g_fake.starts.load();
    mic::listen(true, err);
    deliver_all(y, 0, 320);
    mic::viseme_voice(gb2, nb);
    std::string name2 = mic::device_name();
    CHECK(listed && flagged == 2 && r6 == mic::OPEN_LOOPBACK && nothing &&
              e6 == "that device records what your PC plays (a speaker output), not a microphone" && r1 == mic::OPEN_OK &&
              name1 == "Microphone (Example USB Mic)" && na > 0 && r7 == mic::OPEN_LOOPBACK && still && rf == mic::OPEN_OK &&
              starts2 == starts1 + 1 && gb2 == ga && nb == na && name2 == name1,
          "V14: devices() lists %zu devices, the loopbacks flagged (6 \"Speakers (Example Audio)\", 7; %d); open2(6) -> %d "
          "(OPEN_LOOPBACK \"%s\"), nothing opened (%s); open2(1) -> %d, \"%s\"; with it open (voice %.4f from %u frames) "
          "open2(7) -> %d and device 1 stays open (%s); open2(1, force) -> %d, RecordStart again (%d), the voice kept (%.4f, "
          "%u), \"%s\"", devs.size(), flagged, r6, e6.c_str(), nothing ? "yes" : "NO", r1, name1.c_str(), ga, na, r7,
          still ? "yes" : "NO", rf, starts2 - starts1, gb2, nb, name2.c_str());
}

// ---- R.3: the per-raw-class medians (the next round's baseline) ---------------------------------------------------------
static void report_medians(std::string &table)
{
    std::printf("R.3 per-RAW-class medians on the default set, USB, as atomic 2 quantises them (rel_loc dB / per / nbr / lowr "
                "/ zcr; the frames of the speech whose raw class is not SIL):\n");
    std::vector<float> vals[C2::COUNT][5];
    std::vector<C2::Out> out;
    std::vector<V::Frame> fr;
    for (const Spk &s : g_set) {
        V::Params p;
        V::default_params(p);
        run_v2(s.C, s.ch[C2::CH_USB], p, false, out, &fr);
        for (const V::Frame &f : fr) {
            if (f.raw <= C2::SIL || f.raw >= C2::COUNT) continue;
            mic::VisemeFeatures a, q;
            a.rel_loc = f.rel_loc;
            a.per = f.per;
            a.nbr = f.nbr;
            a.eep = f.eep;
            a.cat = f.cat;
            a.raw = f.raw;
            a.lowr = f.lowr;
            a.zcr = f.zcr;
            mic::features_unpack(mic::features_pack(a), q);
            const float v5[5] = {q.rel_loc, q.per, q.nbr, q.lowr, q.zcr};
            for (int k = 0; k < 5; k++) vals[f.raw][k].push_back(v5[k]);
        }
    }
    for (int c = 1; c < C2::COUNT; c++) {
        if (vals[c][0].empty()) continue;
        std::string line = format("%s %.1f/%.2f/%.2f/%.2f/%.2f n%zu", C2::CLS[c], C2::quant(vals[c][0], 0.5) + 0.0f,
                                  C2::quant(vals[c][1], 0.5), C2::quant(vals[c][2], 0.5), C2::quant(vals[c][3], 0.5),
                                  C2::quant(vals[c][4], 0.5), vals[c][0].size());
        std::printf("        %s\n", line.c_str());
        table += (table.empty() ? "" : ", ") + line;
    }
}

int main(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--verbose") {
            g_verbose = true;
        } else if (a == "--gdi" && i + 1 < argc) {
            i++;                         // build.py passes the disc to every feature test; this one needs none
        } else {
            std::printf("usage: feat_hear_test [--verbose]\n");
            return 2;
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_hear_test\n");
    double t0 = now_us();
    build_default_set();
    std::printf("  info  the default set: %zu speakers, corpus 2 and five channels made in memory in %.1f s\n", g_set.size(),
                (now_us() - t0) / 1e6);
    test_golden();
    test_v1c();
    test_v1g();
    test_latency();
    test_cost();
    test_features_atomic();
    test_warmup();
    test_drift();
    test_loopback();
    std::string table;
    report_medians(table);
    mic::set_test_api(nullptr);
    std::printf("\n%d checks, %d failed (%.1f s)\n", g_checks, g_fail, (now_us() - t0) / 1e6);
    return g_fail ? 1 : 0;
}
