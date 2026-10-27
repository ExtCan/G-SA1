// feat_viseme_test: phoneme lip sync, the module's side (round 0.9.4c, feature "faces" 2; sadc docs/research/
// phoneme_plan.md 6.2 V1-V8, V11, V12 with its Review R.4 / R.7 - R.9 / R.12 / R.13, and 10.1 PQ7). Round 0.9.4e (feature
// "faces" 3; lipsync2_plan.md 6.1 with its Review R.1 / R.4 / R.7): the classifier is v2 (src/core/viseme.cpp, the default
// engine 2) and 0.9.4c's is kept verbatim as engine 1 (src/core/viseme_v1.cpp); the lipsync2 corpus' tests (V1c, V1g, V3,
// V4, V6f, V7w, V7d, V13, V14) are in tests/feat_hear_test.cpp. Linked like core_test (the core and libsa1) by build.py, run
// with --gdi GAME.gdi.
//
//   feat_viseme_test [--gdi GAME.gdi] [--src G-SA1-TREE] [--verbose]
//
// The speech is synthetic, made in memory by tests/viseme_synth.hpp (a port of the 0.9.4c research prototype's formant
// synthesiser, fixed seeds; men, women and children; "corpus 1"): no WAV file and no recording of anyone is in the repository.
//   V1  accuracy of v2 on corpus 1 (vowels / syllables / pseudo-sentences x clean / white / pink noise) scored with
//       lipsync2's class definitions (/I/ = EH, /o/ OH or OO, /U/ OO or OH, /3r/ EH or OO): the gates are v2's own measured
//       numbers minus 3 points, each reported next to v1's on the same frames
//   V1o v1 (viseme_v1, the kept engine) on corpus 1 with 0.9.4c's definitions passes 0.9.4c's V1 gates unchanged
//   V1b channels (review R.7 of phoneme_plan.md): mains hum at -35 dBFS with the 100 Hz high-pass and a 300-3400 Hz band for
//       v2 (gates = v2's numbers minus 3), reported with v1's; v2 without the high-pass and the other channels reported
//   V2  silence (both engines): 30 s of digital silence, white noise at -50 dBFS, pink noise at -45 dBFS: at most 0.5 % of
//       frames not SIL
//   V5  src/core/mic.cpp's RECORDPROC (through a fake BASS), for engine 1 AND engine 2: MXCSR restored exactly (two
//       sentinels) while frames were made; a denormal-producing tail costs no more than 4x the median; blocks of 80 / 160 /
//       320 / 480 samples give the frames of 160-sample blocks (review R.8)
//   V6  the 64-bit frame atomic: the packing round-trips; cls -1 while paused, with the analysis off, before a press'
//       first frame; seq +1 per published frame
//   V7  (both engines) a press keeps the floor, the peak and the voice; reset_voice -> the prior (and clears the shifts); a
//       device change and a forced re-open keep the voice; adapt 0 forgets it; "engine" switches at the next block and a
//       value other than 1 / 2 is refused; tunes: ranges refused, applied at the next block (a 12 dB gate silences a quiet
//       vowel 3 dB lets through)
//   V7s the stress run (review R.9 of phoneme_plan.md, extended): BASS's callback on its own thread while this thread
//       toggles listen, reopens (with and without force), switches engines, sends warm-up steps and tunes 10,000 times: no
//       torn frame (atomic 1, atomic 2, the voice and the warm-up state in range), no overlapping entry, the States never
//       entered on this ("Lua") thread
//   V7p privacy (owner PQ7, binding: the voice learning AND the warm-up in session memory only): (a) both classifiers, the
//       microphone and the faces binding's MicViseme* functions contain no file, setting, registry, environment, log or
//       network call in their code; (b) after a warm-up and 20 s of speech close() forgets everything: both engines'
//       speaker fields equal a fresh init's (memcmp), voice2 frames 0 / warmed 0, the warm state "none"; (c) the module
//       links no network library (BUILD_INFO's imports)
//   V8  moved to tests/feat_mouth_test.cpp (0.9.4e: the mouth table v2 is 094e-gsa1-mouths')
//   V11 (with the disc) end to end on engine 2 and the mouth table as built (the expected keys from mouth::pick, so any
//       table passes or fails on its own rows): synthetic oh / a / f / a / m / i / s / u (after 12.5 s of the twelve vowels,
//       so the voice has settled) through the fake BASS, the classifier, the table and sa1_character_face_mouth (or
//       _face_level for f) with SAME_PAIR into the real libsa1 world of Sonic, Tails, Knuckles, Amy and Big, a man and a
//       woman each, 60 fps frames on a simulated clock: in the middle 60 % of each VOWEL at least 75 % of the pairs show the
//       true class' mouth (keys AND weight), the silences closed, Big only keys 0 / 4 / 5; "i" (review R.4d: fixed gates)
//       at least 50 % without and 75 % after the same speaker's guided warm-up (MicVisemeWarmup's steps through the fake
//       BASS), POOLED over the ten voices (accepted by the orchestrator at 0.9.4e's release: one synthetic woman per
//       character makes a per-character gate a coin flip - Knuckles' seed-34 voice reaches 6/16 and 8/16); f / m / s are
//       reported, not gated (engine 2 opens the mouth on a held "mmm"); a negative control with the analysis off (the
//       loudness ladder) fails the vowel checks
//   V12 (with the disc) the latency from a vowel's first sample to the frame whose tick runs the first pair that shows its
//       mouth (Tails' "ah", keys from mouth::pick): median <= 50 ms, p90 <= 80 ms
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
#include "../src/core/viseme_v1.hpp"

using namespace gsa1;
namespace V = gsa1::viseme;
namespace V1 = gsa1::viseme_v1;
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

// the classifiers on samples in 160-sample blocks (as the prototype's run_vis): every frame's shown class
static std::vector<int> classify2(const std::vector<float> &y, const V::Params &p)
{
    V::State *st = new V::State;
    V::init(*st, p);
    std::vector<int> out;
    out.reserve(y.size() / 160 + 4);
    for (size_t i = 0; i < y.size(); i += 160) {
        V::Frame f[4];
        int m = (int)std::min<size_t>(160, y.size() - i);
        int got = V::feed(*st, y.data() + i, m, f, 4);
        for (int k = 0; k < got && k < 4; k++) out.push_back(f[k].cls);
    }
    delete st;
    return out;
}
static std::vector<int> classify1(const std::vector<float> &y, const V1::Params &p)
{
    V1::State *st = new V1::State;
    V1::init(*st, p);
    std::vector<int> out;
    out.reserve(y.size() / 160 + 4);
    for (size_t i = 0; i < y.size(); i += 160) {
        V1::Frame f[4];
        int m = (int)std::min<size_t>(160, y.size() - i);
        int got = V1::feed(*st, y.data() + i, m, f, 4);
        for (int k = 0; k < got && k < 4; k++) out.push_back(f[k].cls);
    }
    delete st;
    return out;
}

// the classes a frame of a corpus-1 phone may show: 0.9.4c's definitions (the corpus' own labels; /I/ = EE), or lipsync2's
// (lipsync2_hear.md 5.4: EE only for /i/ and /j/; /I/ EH, /o/ OH or OO, /U/ OO or OH, /3r/ EH or OO)
enum { DEFS_094C = 0, DEFS_L2 = 1 };
static unsigned truth_of_phone(int ph, int defs)
{
    unsigned m = SY::phone_truth(ph);
    if (defs != DEFS_L2) return m;
    std::string l = SY::phone_label(ph);
    if (l == "I") return 1u << V::EH;
    if (l == "o") return (1u << V::OH) | (1u << V::OO);
    if (l == "U") return (1u << V::OO) | (1u << V::OH);
    if (l == "3r") return (1u << V::EH) | (1u << V::OO);
    return m;
}

static void score(Score &sc, const SY::Corpus &c, const std::vector<int> &fr, int set, int defs)
{
    const int n = (int)c.x.size(), guard = (set == SY::SET_VOWELS ? 40 : 20) * SY::RATE / 1000;
    for (size_t j = 0; j < fr.size(); j++) {
        int e = V::kWin - 1 + (int)j * V::kHop, ce = e - V::kWin / 2;
        if (ce < 0 || ce >= n) continue;
        int ph = c.phone[ce], k = c.segof[ce], a = c.segstart[k], b = c.segstart[k + 1];
        unsigned m = truth_of_phone(ph, defs);
        if (c.speech[ce]) sc.speech_s += V::kHop / (double)SY::RATE;
        if (!m || ce - a < guard || b - ce < guard) continue;
        const int o = fr[j];
        sc.n++;
        sc.ok += (m >> o) & 1u;
        sc.face_ok += (face_mask(m) >> FACE_OF[o]) & 1u;
        sc.near_ok += (face_near(face_mask(m)) >> FACE_OF[o]) & 1u;
        sc.conf[primary(m)][o]++;
        if (!SY::phone_is_vowel(ph) && m == (1u << V::SIL) && ce - a >= 800 && b - ce >= 800) {
            sc.sil_n++;
            sc.sil_fa += o != V::SIL;
        }
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

// ---- V1, V1o, V1b, V2 ------------------------------------------------------------------------------------------------------
// v2's own measured numbers on corpus 1 (lipsync2's definitions; this test's run when the gates were set, 2026-10-27; the
// gates are these minus 3 points): vowels clean, syllables clean, sentences clean, vowels white 20 dB, sentences white
// 20 dB, sentences pink 10 dB, sentences' face near-right clean; then V1b's mains hum with the high-pass and the band
static const double k_v2_corpus1[7] = {82.7, 75.8, 74.9, 81.4, 69.7, 59.3, 86.2};
static const double k_v2_v1b[2] = {71.0, 72.4};

static void test_accuracy()
{
    std::printf("V1 / V1o accuracy on corpus 1 (class %% of scored frames): v2 with lipsync2's definitions [v1 on the same frames "
                "and definitions] {v1 with 0.9.4c's definitions; the 0.9.4c prototype's in brackets}:\n");
    // the 0.9.4c prototype's default rows (SADC/build/research/phoneme/audio/out_all.txt): [set][condition] class %, and
    // sentences' face near-right %
    static const double proto[3][6] = {{84.5, 84.4, 83.3, 66.2, 84.2, 76.4},
                                       {93.6, 91.0, 87.7, 65.3, 89.6, 75.6},
                                       {72.4, 69.6, 66.7, 48.7, 68.7, 57.1}};
    V::Params p;
    V::default_params(p);
    V1::Params p1;
    V1::default_params(p1);
    Score a2[3][6], a1l[3][6], a1[3][6];     // v2 lipsync2 defs, v1 lipsync2 defs, v1 0.9.4c defs
    for (int set = 0; set < SY::SET_COUNT; set++) {
        for (int g = 0; g < SY::GRP_COUNT; g++) {
            const SY::Corpus &c = corp(set, g);
            for (int ci = 0; ci < 6; ci++) {
                std::vector<float> y = SY::with_condition(c, ci, g);
                std::vector<int> c2 = classify2(y, p), c1 = classify1(y, p1);
                Score s2, s1l, s1;
                score(s2, c, c2, set, DEFS_L2);
                score(s1l, c, c1, set, DEFS_L2);
                score(s1, c, c1, set, DEFS_094C);
                a2[set][ci].add(s2);
                a1l[set][ci].add(s1l);
                a1[set][ci].add(s1);
            }
        }
        std::string row;
        for (int ci = 0; ci < 6; ci++) {
            row += format("%s %s %.1f [%.1f] {%.1f (%.1f)}", ci ? ";" : "", SY::condition(ci).name, a2[set][ci].pct(),
                          a1l[set][ci].pct(), a1[set][ci].pct(), proto[set][ci]);
        }
        std::printf("        %-9s%s\n", SY::set_name(set), row.c_str());
    }
    std::printf("        sentences, face near-right (clean): v2 %.1f [v1 %.1f] {v1 0.9.4c defs %.1f (85.1)}\n", a2[2][0].near_pct(),
                a1l[2][0].near_pct(), a1[2][0].near_pct());
    const double v2n[7] = {a2[0][0].pct(), a2[1][0].pct(), a2[2][0].pct(), a2[0][2].pct(), a2[2][2].pct(), a2[2][5].pct(),
                           a2[2][0].near_pct()};
    const double v1n[7] = {a1l[0][0].pct(), a1l[1][0].pct(), a1l[2][0].pct(), a1l[0][2].pct(), a1l[2][2].pct(),
                           a1l[2][5].pct(), a1l[2][0].near_pct()};
    static const char *const rown[7] = {"vowels clean", "syllables clean", "sentences clean", "vowels white 20 dB",
                                        "sentences white 20 dB", "sentences pink 10 dB", "sentences face near-right"};
    bool v1ok = true;
    std::string rows;
    for (int k = 0; k < 7; k++) {
        bool ok = v2n[k] >= k_v2_corpus1[k] - 3.0;
        v1ok = v1ok && ok;
        rows += format("%s %s %.1f (>= %.1f; v1 %.1f)", k ? ";" : "", rown[k], v2n[k], k_v2_corpus1[k] - 3.0, v1n[k]);
    }
    CHECK(v1ok, "V1: v2 on corpus 1 with lipsync2's definitions, each row at least its measured number minus 3:%s", rows.c_str());
    const Score &vc = a1[0][0], &cc = a1[1][0], &sc = a1[2][0], &vw = a1[0][2], &sw = a1[2][2], &sp = a1[2][5];
    CHECK(vc.pct() >= 80.0 && cc.pct() >= 90.0 && sc.pct() >= 68.0 && vw.pct() >= 78.0 && sw.pct() >= 62.0 &&
              sp.pct() >= 50.0 && sc.near_pct() >= 80.0,
          "V1o: v1 (0.9.4c's classifier, kept as engine 1) passes 0.9.4c's V1 gates with 0.9.4c's definitions: vowels clean "
          "%.1f %% (>= 80; prototype 84.5), syllables clean %.1f (>= 90; 93.6), sentences clean %.1f (>= 68; 72.4), vowels "
          "white 20 dB %.1f (>= 78; 83.3), sentences white 20 dB %.1f (>= 62; 66.7), sentences pink 10 dB %.1f (>= 50; 57.1); "
          "face near-right on sentences clean %.1f (>= 80; 85.1)", vc.pct(), cc.pct(), sc.pct(), vw.pct(), sw.pct(),
          sp.pct(), sc.near_pct());

    // V1b: the review's channels (sentences, the three groups)
    std::printf("V1b channels (sentences, class %%): v2 with lipsync2's definitions [v1 on the same frames and definitions] {v1 "
                "with 0.9.4c's definitions; the 0.9.4c review's runs in brackets}:\n");
    struct Ch {
        const char *name;
        float gain;
        int fx;
        float hp;
        double review;
    };
    const Ch chans[] = {{"mains hum -35 dBFS, high-pass 100 Hz", 0, 4, 100.0f, 68.2},
                        {"band 300-3400 Hz, high-pass 100 Hz", 0, 1, 100.0f, 70.2},
                        {"mains hum -35 dBFS, high-pass off", 0, 4, 0.0f, 58.5},
                        {"quiet microphone -25 dB", -25, 0, 100.0f, 61.9},
                        {"hot microphone +18 dB, clipped", 18, 3, 100.0f, 71.5},
                        {"crude noise-suppression gate", 0, 5, 100.0f, 71.6}};
    double r2[6] = {0}, r1l[6] = {0}, r1[6] = {0};
    long ssrow[V::COUNT] = {};
    for (int k = 0; k < 6; k++) {
        V::Params q;
        V::default_params(q);
        q.hp_hz = chans[k].hp;
        V1::Params q1;
        V1::default_params(q1);
        q1.hp_hz = chans[k].hp;
        Score acc2, acc1l, acc1;
        for (int g = 0; g < SY::GRP_COUNT; g++) {
            const SY::Corpus &c = corp(SY::SET_SENT, g);
            std::vector<float> y = channel(c, g, chans[k].gain, chans[k].fx);
            std::vector<int> c2 = classify2(y, q), c1 = classify1(y, q1);
            Score s2, s1l, s1;
            score(s2, c, c2, SY::SET_SENT, DEFS_L2);
            score(s1l, c, c1, SY::SET_SENT, DEFS_L2);
            score(s1, c, c1, SY::SET_SENT, DEFS_094C);
            acc2.add(s2);
            acc1l.add(s1l);
            acc1.add(s1);
        }
        r2[k] = acc2.pct();
        r1l[k] = acc1l.pct();
        r1[k] = acc1.pct();
        if (k == 1) {
            for (int b = 0; b < V::COUNT; b++) ssrow[b] = acc2.conf[V::SS][b];
        }
        std::printf("        %-40s %.1f %% [%.1f] {%.1f (%.1f)}\n", chans[k].name, r2[k], r1l[k], r1[k], chans[k].review);
    }
    long ssn = 0;
    for (int b = 0; b < V::COUNT; b++) ssn += ssrow[b];
    std::printf("        v2's \"s\" row in the band (reported, not gated): SS %.1f %%, MBP %.1f %%, FV %.1f %%\n",
                pct(ssrow[V::SS], ssn), pct(ssrow[V::MBP], ssn), pct(ssrow[V::FV], ssn));
    CHECK(r2[0] >= k_v2_v1b[0] - 3.0 && r2[1] >= k_v2_v1b[1] - 3.0,
          "V1b: v2 with mains hum at -35 dBFS and the 100 Hz high-pass %.1f %% (>= %.1f; v1 %.1f), in a 300-3400 Hz band %.1f %% "
          "(>= %.1f; v1 %.1f); v2 without the high-pass %.1f %% (reported)", r2[0], k_v2_v1b[0] - 3.0, r1l[0], r2[1],
          k_v2_v1b[1] - 3.0, r1l[1], r2[2]);
}

static void test_silence()
{
    std::printf("V2 silence (both engines):\n");
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
    V::Params p;
    V::default_params(p);
    V1::Params p1;
    V1::default_params(p1);
    double share[2][3];
    const std::vector<float> *sig[3] = {&zero, &white, &pink};
    for (int e = 0; e < 2; e++) {
        for (int k = 0; k < 3; k++) {
            std::vector<int> fr = e == 0 ? classify2(*sig[k], p) : classify1(*sig[k], p1);
            long moved = 0;
            for (int c : fr) moved += c != V::SIL;
            share[e][k] = pct(moved, (long)fr.size());
        }
    }
    CHECK(share[1][0] <= 0.5 && share[1][1] <= 0.5 && share[1][2] <= 0.5,
          "V2 v1: 30 s without speech - digital silence, white noise at -50 dBFS, pink noise at -45 dBFS: %.2f / %.2f / %.2f %% "
          "of the frames not SIL (each <= 0.5 %%)", share[1][0], share[1][1], share[1][2]);
    // v2 at its defaults (lipsync2_plan.md 4.3; the prototype's behaviour, frame for frame): its weak-fricative gate (a
    // frame with a fricative's shape passes 4 dB under the speech gate, i.e. 2 dB over the floor) lets white noise near the
    // floor through as single "s" frames, and the "quick" vote (smooth 3) shows a frame out of silence at once.
    // ACCEPTED by the orchestrator at 0.9.4e's release (2026-10-27, after the verifier's report): white noise at -50 dBFS may
    // show up to 1.5 % single "s" frames under v2 (measured 1.13 %; silence and pink noise stay under 0.5 %); the
    // weak-fricative gate is re-tuned from the owner's logged numbers in the next lip-sync round
    CHECK(share[0][0] <= 0.5 && share[0][1] <= 1.5 && share[0][2] <= 0.5,
          "V2 v2: 30 s without speech - digital silence, white noise at -50 dBFS, pink noise at -45 dBFS: %.2f / %.2f / %.2f %% "
          "of the frames not SIL (silence and pink <= 0.5 %%, white <= 1.5 %%: accepted at 0.9.4e)", share[0][0],
          share[0][1], share[0][2]);
}

// ---- V5, V6: the microphone's RECORDPROC ---------------------------------------------------------------------------------
// a speech signal for the microphone tests: the men's syllable file's first seconds with the clean floor
static std::vector<float> speech_signal(int seconds = 6)
{
    std::vector<float> y = SY::with_condition(corp(SY::SET_CV, SY::GRP_MEN), 0, SY::GRP_MEN);
    y.resize(std::min(y.size(), (size_t)(seconds * SY::RATE)));
    return y;
}

// a frame of either engine, for the comparisons (extra: v2's rel_loc + per, v1's speaker number g)
struct AnyFrame {
    int cls, raw;
    float f1, f2, db, level, conf, extra;
};
static bool same_frame(const AnyFrame &a, const AnyFrame &b)
{
    return a.cls == b.cls && a.raw == b.raw && a.f1 == b.f1 && a.f2 == b.f2 && a.db == b.db && a.extra == b.extra;
}
// every frame of y fed straight into the engine's classifier in blocks of bs samples (press: as the microphone starts one)
static std::vector<AnyFrame> feed_all(int engine, const std::vector<float> &y, size_t bs, bool press)
{
    std::vector<AnyFrame> all;
    if (engine == mic::ENGINE_V2) {
        V::Params p;
        V::default_params(p);
        V::State *st = new V::State;
        V::init(*st, p);
        if (press) V::reset_press(*st);
        for (size_t i = 0; i < y.size(); i += bs) {
            V::Frame f[8];
            int got = V::feed(*st, y.data() + i, (int)std::min(bs, y.size() - i), f, 8);
            for (int k = 0; k < got && k < 8; k++) {
                all.push_back({f[k].cls, f[k].raw, f[k].f1, f[k].f2, f[k].db, f[k].level, f[k].conf, f[k].rel_loc + f[k].per});
            }
        }
        delete st;
    } else {
        V1::Params p;
        V1::default_params(p);
        V1::State *st = new V1::State;
        V1::init(*st, p);
        if (press) V1::reset_press(*st);
        for (size_t i = 0; i < y.size(); i += bs) {
            V1::Frame f[8];
            int got = V1::feed(*st, y.data() + i, (int)std::min(bs, y.size() - i), f, 8);
            for (int k = 0; k < got && k < 8; k++) {
                all.push_back({f[k].cls, f[k].raw, f[k].f1, f[k].f2, f[k].db, f[k].level, f[k].conf, f[k].g});
            }
        }
        delete st;
    }
    return all;
}
static void set_engine(int engine)
{
    std::string err;
    mic::viseme_tune("engine", engine, err);
}

static void test_mxcsr_blocks()
{
    std::printf("V5 the RECORDPROC (fake BASS), engine 2 (v2) and engine 1 (0.9.4c's):\n");
    std::vector<float> y = speech_signal();
    for (int engine : {mic::ENGINE_V2, mic::ENGINE_V1}) {
        set_engine(engine);
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
            same = same && seq1 != seq0 && f1.cls >= 0 && mic::viseme_engine() == engine;
        }
        _mm_setcsr(saved);
        CHECK(same, "V5 engine %d: MXCSR is exactly as the RECORDPROC found it (0x%04X -> 0x%04X, 0x%04X -> 0x%04X; one with FTZ "
              "off) and the same calls made frames (seq %u -> %u, the analysis ran on engine %d)", engine, sentinel[0], got[0],
              sentinel[1], got[1], seq0, seq1, mic::viseme_engine());
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
            float ms = median(per_speech), mt = median(per_tail);
            CHECK(mt <= 4.0f * ms, "V5 engine %d: a decaying denormal tail costs %.2f us per block (median) through the RECORDPROC "
                  "against %.2f for speech (<= 4x)", engine, mt, ms);
        }
        // block sizes (review R.8): the classifier sees every hop whatever the block
        {
            std::vector<AnyFrame> ref = feed_all(engine, y, 160, true);
            bool direct_same = true, mic_same = true;
            std::string seen;
            for (int bs : {80, 160, 320, 480, 7, 1000}) {
                std::vector<AnyFrame> all = feed_all(engine, y, (size_t)bs, true);
                bool eq = all.size() == ref.size();
                for (size_t k = 0; eq && k < all.size(); k++) eq = same_frame(all[k], ref[k]);
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
                        const AnyFrame &r = ref[frames_so_far - 1];
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
                  "V5 engine %d: blocks of 80 / 160 / 320 / 480 (and 7 / 1000) samples give the frames of 160-sample blocks (%zu "
                  "frames), and through the RECORDPROC each block publishes its newest of them (%s)", engine, ref.size(),
                  seen.c_str());
        }
    }
    // what the flush saves (reported): the tail straight into v2 without FTZ / DAZ
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
        std::vector<float> tail(160 * 300);
        for (size_t i = 0; i < tail.size(); i++) tail[i] = (float)(1e-30 * std::pow(0.9995, (double)i) * std::sin(0.3 * (double)i));
        for (size_t i = 0; i < tail.size(); i += 160) {
            V::Frame f;
            double t0 = now_us();
            V::feed(*st, tail.data() + i, 160, &f, 1);
            per.push_back((float)(now_us() - t0));
        }
        std::printf("  info  the same tail straight into v2 without FTZ / DAZ costs %.2f us per block (median)\n", median(per));
        delete st;
        _mm_setcsr(csr);
    }
#endif
    set_engine(mic::ENGINE_V2);
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
    std::printf("V7 presses, the voice, tunes (both engines):\n");
    std::vector<float> yw = SY::with_condition(corp(SY::SET_VOWELS, SY::GRP_WOMEN), 0, SY::GRP_WOMEN);
    // v2 itself: a press keeps the floor, the peaks and the voice; reset_voice -> the prior, the shifts and counts cleared
    {
        V::Params p;
        V::default_params(p);
        V::State *st = new V::State;
        V::init(*st, p);
        for (size_t i = 0; i + 160 <= 8 * (size_t)SY::RATE; i += 160) {
            V::Frame f;
            V::feed(*st, yw.data() + i, 160, &f, 1);
        }
        float fl = st->floor_db, pk = st->peak_db, lp = st->lpk_db;
        double m0 = st->mu[0], m1 = st->mu[1], v0 = st->var[0], v1 = st->var[1];
        uint32_t vf = st->voice_frames;
        V::reset_press(*st);
        bool kept = st->floor_db == fl && st->peak_db == pk && st->lpk_db == lp && st->mu[0] == m0 && st->mu[1] == m1 &&
                    st->var[0] == v0 && st->var[1] == v1 && st->voice_frames == vf && st->cur == V::SIL;
        st->shift[3][0] = 0.25f;     // as a warm-up leaves them
        st->warmed = 1;
        V::reset_voice(*st);
        bool cleared = true;
        for (int c = 0; c < V::kCats; c++) {
            cleared = cleared && st->shift[c][0] == 0.0f && st->shift[c][1] == 0.0f && st->cat_h[c] == 0.0f;
        }
        bool prior = st->mu[0] == st->mu0[0] && st->mu[1] == st->mu0[1] && st->var[0] == st->var0[0] &&
                     st->var[1] == st->var0[1] && st->wn == (double)p.n0 && st->voice_frames == 0 && st->warmed == 0 &&
                     st->cat_H == 0.0f && cleared;
        CHECK(kept && vf > 0 && (m0 != st->mu0[0] || m1 != st->mu0[1]) && prior,
              "V7 v2: a press (reset_press) keeps the floor %.1f dB, the peaks (%.1f, local %.1f dB) and the voice (ln F1 / F2 "
              "means %.3f / %.3f learned from %u vowel frames; the prior %.3f / %.3f); reset_voice -> the prior, 0 frames, the "
              "shifts, the category counts and warmed cleared", fl, pk, lp, m0, m1, vf, st->mu0[0], st->mu0[1]);
        delete st;
    }
    // v1 itself (0.9.4c's check)
    {
        const float prior1 = V1::prior_g();
        V1::Params p;
        V1::default_params(p);
        V1::State *st = new V1::State;
        V1::init(*st, p);
        for (size_t i = 0; i + 160 <= 8 * (size_t)SY::RATE; i += 160) {
            V1::Frame f;
            V1::feed(*st, yw.data() + i, 160, &f, 1);
        }
        float fl = st->floor_db, pk = st->peak_db, g = st->g;
        uint32_t vf = st->voice_frames;
        V1::reset_press(*st);
        bool kept = st->floor_db == fl && st->peak_db == pk && st->g == g && st->voice_frames == vf && st->cur == V1::SIL;
        V1::reset_voice(*st);
        CHECK(kept && vf > 0 && g != prior1 && st->g == prior1 && st->voice_frames == 0,
              "V7 v1: a press keeps the floor %.1f dB, the peak %.1f dB and the speaker number %.3f (from %u vowel frames; the "
              "prior is %.3f); reset_voice -> the prior, 0 frames", fl, pk, g, vf, prior1);
        delete st;
    }
    // through the microphone, each engine: release / press, another device, a forced re-open, reset_voice, adapt 0
    std::vector<float> y = SY::with_condition(corp(SY::SET_VOWELS, SY::GRP_MEN), 0, SY::GRP_MEN);
    std::vector<float> sil = silence_block();
    std::string err;
    for (int engine : {mic::ENGINE_V2, mic::ENGINE_V1}) {
        set_engine(engine);
        const float prior = engine == mic::ENGINE_V2 ? V::prior_g() : V1::prior_g();
        fresh_mic();
        for (size_t i = 0; i + 160 <= 8 * (size_t)SY::RATE; i += 160) deliver(y.data() + i, 160);
        float g1 = 0, g2 = 0, g3 = 0, g3f = 0, g4 = 0, g5 = 0, g6 = 0, g7 = 0;
        uint32_t n1 = 0, n2 = 0, n3 = 0, n3f = 0, n4 = 0, n5 = 0, n6 = 0, n7 = 0;
        mic::viseme_voice(g1, n1);
        mic::listen(false, err);
        mic::listen(true, err);
        deliver(sil.data(), 160);
        mic::viseme_voice(g2, n2);
        bool reopened = mic::open(1, err) && mic::listen(true, err);
        deliver(sil.data(), 160);
        deliver(sil.data(), 160);
        mic::viseme_voice(g3, n3);
        int starts0 = g_fake.starts.load();
        bool forced = mic::open2(1, true, err) == mic::OPEN_OK && mic::listen(true, err);
        int starts1 = g_fake.starts.load();
        deliver(sil.data(), 160);
        deliver(sil.data(), 160);
        mic::viseme_voice(g3f, n3f);
        bool tuned = mic::viseme_tune("reset_voice", 0.0, err);
        mic::viseme_voice(g4, n4);
        deliver(sil.data(), 160);
        mic::viseme_voice(g5, n5);
        // learn again, then "Learn my voice" off forgets it (at once and after the next block)
        for (size_t i = 0; i + 160 <= 8 * (size_t)SY::RATE; i += 160) deliver(y.data() + i, 160);
        float gl = 0;
        uint32_t nl = 0;
        mic::viseme_voice(gl, nl);
        mic::viseme_tune("adapt", 0, err);
        mic::viseme_voice(g6, n6);
        deliver(sil.data(), 160);
        mic::viseme_tune("adapt", 1, err);
        deliver(sil.data(), 160);
        mic::viseme_voice(g7, n7);
        CHECK(n1 > 0 && std::fabs(g1 - prior) > 1e-3f && g2 == g1 && n2 == n1 && reopened && g3 == g1 && n3 == n1 && forced &&
                  starts1 == starts0 + 1 && g3f == g1 && n3f == n1 && tuned && g4 == prior && n4 == 0 && g5 == prior &&
                  n5 == 0 && nl > 0 && g6 == prior && n6 == 0 && g7 == prior && n7 == 0,
              "V7 engine %d through the microphone: learned %.4f from %u vowel frames; a release and a press keep it (%.4f, %u); "
              "another device keeps it (%.4f, %u); a forced re-open of the same device (RecordStart again: %d) keeps it (%.4f, "
              "%u); \"reset_voice\" -> the prior %.4f at once and after the next block (%.4f, %u); learned again (%u frames), "
              "\"adapt\" 0 forgets it at once (%.4f, %u) and for good (%.4f, %u)", engine, g1, n1, g2, n2, g3, n3,
              starts1 - starts0, g3f, n3f, g4, g5, n5, nl, g6, n6, g7, n7);
    }
    // the engine switches at the next block; other values refused
    {
        set_engine(mic::ENGINE_V2);
        fresh_mic();
        deliver(y.data(), 160);
        deliver(y.data() + 160, 160);
        int e0 = mic::viseme_engine();
        bool t1 = mic::viseme_tune("engine", 1, err);
        int e1 = mic::viseme_engine();
        deliver(y.data() + 320, 160);
        int e2 = mic::viseme_engine();
        bool t2 = mic::viseme_tune("engine", 2, err);
        deliver(y.data() + 480, 160);
        int e3 = mic::viseme_engine();
        int bad = !mic::viseme_tune("engine", 0, err) + !mic::viseme_tune("engine", 3, err) +
                  !mic::viseme_tune("engine", 1.5, err) + !mic::viseme_tune("engine", std::nan(""), err);
        CHECK(e0 == 2 && t1 && e1 == 2 && e2 == 1 && t2 && e3 == 2 && bad == 4,
              "V7: \"engine\" 1 applies at the next block (2 before it, then %d), 2 again likewise (%d); 0, 3, 1.5 and NaN refused "
              "(%d of 4: \"%s\")", e2, e3, bad, err.c_str());
    }
    // tunes: names and ranges
    int refused = 0;
    refused += !mic::viseme_tune("gate_min_db", 2.9, err);
    refused += !mic::viseme_tune("gate_min_db", 12.5, err);
    refused += !mic::viseme_tune("gate_min_db", std::nan(""), err);
    refused += !mic::viseme_tune("adapt", 0.5, err);
    refused += !mic::viseme_tune("smooth", 4, err);
    refused += !mic::viseme_tune("smooth", 1.5, err);
    refused += !mic::viseme_tune("loudness", 1, err);
    refused += !mic::viseme_tune("engine", 4, err);
    std::string lasterr = err;
    int taken = mic::viseme_tune("gate_min_db", 3, err) + mic::viseme_tune("gate_min_db", 12, err) +
                mic::viseme_tune("adapt", 0, err) + mic::viseme_tune("adapt", 1, err) + mic::viseme_tune("smooth", 0, err) +
                mic::viseme_tune("smooth", 3, err) + mic::viseme_tune("engine", 1, err) + mic::viseme_tune("engine", 2, err);
    CHECK(refused == 8 && taken == 8, "V7: tunes out of range or unknown refused (%d of 8: \"%s\"), in range taken (%d of 8)",
          refused, lasterr.c_str(), taken);
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
    std::printf("V7s the stress run (review R.9 of phoneme_plan.md, extended for 0.9.4e):\n");
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
    long bad = 0, bad2 = 0;
    std::string err;
    for (int spin = 0; calls.load() < 20 && spin < 2000000; spin++) std::this_thread::yield();
    for (int k = 0; k < 10000; k++) {
        // one toggle per callback (or after about 0.2 ms without one: a device change stops the callback a moment)
        long c0 = calls.load();
        double w0 = now_us();
        while (calls.load() == c0 && now_us() - w0 < 200.0) {
        }
        switch (k % 12) {
        case 0: mic::listen(false, err); break;
        case 1: mic::listen(true, err); break;
        case 2:
            mic::open((k / 12) % 2, err);      // another device: teardown + a pending re-init
            mic::listen(true, err);
            break;
        case 3: mic::viseme_tune("gate_min_db", 3 + k % 10, err); break;
        case 4:
            mic::viseme_tune("smooth", k % 4, err);
            mic::viseme_tune("adapt", (k / 12) % 3 ? 1 : 0, err);
            break;
        case 5: mic::viseme_tune("reset_voice", 0, err); break;
        case 6: mic::viseme_on((k / 12) % 5 != 0); break;
        case 7:                                 // 0.9.4e: a forced re-open of the open device (a stalled stream)
            mic::open2(mic::device_index(), true, err);
            mic::listen(true, err);
            break;
        case 8: mic::viseme_tune("engine", (k / 12) % 4 == 3 ? 1 : 2, err); break;
        case 9:                                 // 0.9.4e: warm-up steps (ah ee oo oh gap done cancel)
        case 10: mic::viseme_warm((k / 12 + k) % 7, err); break;
        default: mic::viseme_on(true); break;
        }
        mic::VisemeFrame f;
        mic::viseme_frame(f);
        float g = 0, f1 = 0, f2 = 0;
        uint32_t fr = 0;
        bool warmed = false;
        mic::viseme_voice2(g, fr, f1, f2, warmed);
        mic::VisemeFeatures ft;
        mic::viseme_features(ft);
        mic::WarmState ws;
        mic::viseme_warm_state(ws);
        bool ok = f.cls >= -1 && f.cls < V::COUNT && f.level >= 0.0f && f.level <= 1.0f && f.f1 >= 0.0f && f.f1 <= 4092.0f &&
                  f.f2 >= 0.0f && f.f2 <= 4092.0f && f.conf >= 0.0f && f.conf <= 1.0f && f.seq <= 65535u &&
                  std::isfinite(g) && g > 4.0f && g < 9.0f && f1 >= 0.0f && f1 <= 4092.0f && f2 >= 0.0f && f2 <= 8188.0f;
        bool ok2 = ft.rel_loc <= 0.0f && ft.rel_loc >= -63.75f && ft.per >= 0.0f && ft.per <= 1.0f && ft.nbr >= 0.0f &&
                   ft.nbr <= 1.0f && ft.eep >= 0.0f && ft.eep <= 1.0f && ft.cat >= -1 && ft.cat < V::kCats && ft.raw >= -1 &&
                   ft.raw < V::COUNT && ft.lowr >= 0.0f && ft.lowr <= 1.0f && ft.zcr >= 0.0f && ft.zcr <= 1.0f &&
                   ws.phase >= -1 && ws.phase <= 4 && ws.result >= 0 && ws.result <= 4;
        bad += !ok;
        bad2 += !ok2;
    }
    stop = true;
    bass.join();
    mic::VisemeDebug d1;
    mic::viseme_debug(d1);
    std::string err2;
    mic::viseme_tune("gate_min_db", 6, err2);
    mic::viseme_tune("smooth", 3, err2);
    mic::viseme_tune("adapt", 1, err2);
    mic::viseme_tune("engine", 2, err2);
    mic::viseme_warm(mic::WARM_CANCEL, err2);
    CHECK(bad == 0 && bad2 == 0 && d1.overlaps == d0.overlaps && d1.marked_thread_entries == d0.marked_thread_entries &&
              d1.entries > d0.entries + 100 && calls.load() > 100,
          "V7s: 10,000 listen / device / forced re-open / engine / warm-up / tune / analysis toggles on this thread while BASS's "
          "callback ran %ld blocks (80-480 samples) on its own: %ld frames (atomic 1, the voice) and %ld feature / warm-up "
          "states (atomic 2, the warm-up atomic) out of range or torn; the classifiers' States entered %llu times, never two "
          "at once (%llu) and never on this thread (%llu)", calls.load(), bad, bad2, (unsigned long long)(d1.entries - d0.entries),
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

// the guided warm-up through the microphone as the Faces page drives it (lipsync2_plan.md 4.4): "ready" (a gap), then ah /
// ee / oo / oh with gaps between, then "done"; u = an utterance lead + A i u o (+ gaps) of one speaker. Returns the result
// (WarmState::result) or -1 when a step was refused; n receives the frames each corner counted.
static int warm_up_through_mic(const SY::Corpus &u, uint32_t n[4])
{
    std::string err;
    static const int step_at_seg[9] = {mic::WARM_GAP, mic::WARM_AH, mic::WARM_GAP, mic::WARM_EE, mic::WARM_GAP,
                                       mic::WARM_OO, mic::WARM_GAP, mic::WARM_OH, mic::WARM_DONE};
    size_t seg = 0;
    bool ok = true;
    for (size_t i = 0; i + 160 <= u.x.size(); i += 160) {
        while (seg < 9 && seg < u.segstart.size() && (size_t)u.segstart[seg] <= i) {
            ok = mic::viseme_warm(step_at_seg[seg], err) && ok;
            seg++;
        }
        deliver(u.x.data() + i, 160);
    }
    std::vector<float> sil = silence_block();
    deliver(sil.data(), 160);
    mic::WarmState ws;
    mic::viseme_warm_state(ws);
    for (int c = 0; c < 4; c++) n[c] = ws.n[c];
    return ok ? ws.result : -1;
}
static SY::Corpus warm_utterance(int group, uint32_t seed)
{
    return SY::utterance(group, seed, {"A", "i", "u", "o"}, {2000, 2000, 2000, 2000}, {600, 600, 600, 300}, 1000);
}

static void test_privacy(const std::string &self)
{
    std::printf("V7p privacy (owner PQ7, binding: the voice learning AND the warm-up in session memory only):\n");
    const float prior = V::prior_g();
    std::vector<float> sil = silence_block();
    std::string err;
    // (b) a warm-up and 20 s of speech, then the session's end
    set_engine(mic::ENGINE_V2);
    fresh_mic();
    uint32_t wn[4];
    int wres = warm_up_through_mic(warm_utterance(SY::GRP_MEN, 5u), wn);
    std::vector<float> y = SY::with_condition(corp(SY::SET_SENT, SY::GRP_MEN), 0, SY::GRP_MEN);
    for (size_t i = 0; i + 160 <= std::min(y.size(), (size_t)(20 * SY::RATE)); i += 160) deliver(y.data() + i, 160);
    float g1, g2, g3, f1a, f2a, f1b, f2b;
    uint32_t n1, n2, n3;
    bool w1, w2;
    mic::viseme_voice2(g1, n1, f1a, f2a, w1);
    mic::close();                      // the module's close hook: the session ends
    mic::viseme_voice2(g2, n2, f1b, f2b, w2);
    mic::WarmState ws2;
    mic::viseme_warm_state(ws2);
    // the next session: the same process, the same device; the forget is applied at its first block
    std::string e2;
    bool again = mic::open(-1, e2);
    mic::viseme_on(true);
    again = again && mic::listen(true, e2);
    deliver(sil.data(), 160);
    deliver(sil.data(), 160);
    mic::viseme_voice(g3, n3);
    V::State *s2 = new V::State, *f2 = new V::State;
    V1::State *s1 = new V1::State, *f1 = new V1::State;
    mic::viseme_debug_states(s2, s1);
    V::Params p;
    V::default_params(p);
    V::init(*f2, p);
    V1::Params q;
    V1::default_params(q);
    V1::init(*f1, q);
    bool same2 = std::memcmp(s2->mu, f2->mu, sizeof s2->mu) == 0 && std::memcmp(s2->var, f2->var, sizeof s2->var) == 0 &&
                 s2->wn == f2->wn && s2->voice_frames == f2->voice_frames && std::memcmp(s2->cat_h, f2->cat_h, sizeof s2->cat_h) == 0 &&
                 s2->cat_H == f2->cat_H && std::memcmp(s2->shift, f2->shift, sizeof s2->shift) == 0 && s2->warmed == f2->warmed &&
                 s2->warm_phase == f2->warm_phase && std::memcmp(s2->warm_sum, f2->warm_sum, sizeof s2->warm_sum) == 0 &&
                 std::memcmp(s2->warm_n, f2->warm_n, sizeof s2->warm_n) == 0;
    bool same1 = s1->g == f1->g && s1->voice_frames == f1->voice_frames;
    delete s2;
    delete f2;
    delete s1;
    delete f1;
    CHECK(wres == 1 && w1 && n1 > 0 && std::fabs(g1 - prior) > 1e-3f && g2 == prior && n2 == 0 && !w2 && f1b == 0.0f &&
              f2b == 0.0f && ws2.phase == -1 && ws2.result == 0 && ws2.n[0] == 0 && again && g3 == prior && n3 == 0 && same2 &&
              same1,
          "V7p: after a warm-up (result %d; ah %u ee %u oo %u oh %u frames) and 20 s of speech the voice is %.4f, F1 / F2 %.0f / "
          "%.0f Hz from %u frames, warmed %d (memory only); the session's end (close) forgets it at once (%.4f, %u frames, "
          "warmed %d, the warm-up %s) and at the next session's first block both engines' speaker fields equal a fresh "
          "init's (v2 %s, v1 %s; voice %.4f, %u)", wres, wn[0], wn[1], wn[2], wn[3], g1, f1a, f2a, n1, w1, g2, n2, w2,
          ws2.phase == -1 && ws2.result == 0 ? "none" : "NOT none", same2 ? "equal" : "DIFFER", same1 ? "equal" : "DIFFER", g3,
          n3);
    // the files that hold or hand out the learned number: no file, setting, log or network call in their code
    std::string root = !g_src.empty() ? g_src : join_path(join_path(self.empty() ? std::string(".") : self, ".."), "..");
    // 0.9.4e (lipsync2_plan.md 6.1 V7p a): both engines and the microphone in full; of the faces binding (094e-gsa1-mouths'
    // file, read only) the MicViseme* functions, which hand the learned voice and the warm-up to Lua
    const char *files[] = {"src/core/viseme.cpp", "src/core/viseme.hpp", "src/core/viseme_v1.cpp", "src/core/viseme_v1.hpp",
                           "src/core/mic.cpp", "src/core/mic.hpp", "src/module/bind_faces.cpp"};
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
        if (std::strstr(f, "bind_faces") != nullptr) {
            // only the MicViseme* functions (GSA1_FN(gsa1_faces_MicViseme...) up to the closing brace at column 0)
            std::string part;
            size_t at = 0;
            int fns = 0;
            while ((at = text.find("GSA1_FN(gsa1_faces_MicViseme", at)) != std::string::npos) {
                size_t end = text.find("\n}", at);
                part += text.substr(at, end == std::string::npos ? std::string::npos : end + 2 - at) + "\n";
                at = end == std::string::npos ? text.size() : end;
                fns++;
            }
            if (fns < 4) {
                found += format(" (%s: only %d MicViseme* functions found)", f, fns);
            }
            text = part;
        }
        std::string code = code_only(text);
        for (const char *b : banned) {
            if (code.find(b) != std::string::npos) found += format(" %s: %s;", f, b);
        }
    }
    CHECK(read == 7 && found.empty(),
          "V7p: both classifiers (v2 and 0.9.4c's), the microphone and the faces binding's MicViseme* functions (%d files) "
          "contain no file, setting, registry, environment, log or network call in their code%s", read, found.c_str());
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

// V8 (the mouth table against a transcription of the plan) moved to tests/feat_mouth_test.cpp in 0.9.4e (094e-gsa1-mouths).

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
// analysis false: the negative control - cls -1, the loudness ladder at the 0.9.4a loudness (mic::level). warmup: the same
// speaker's guided warm-up through the microphone first (0.9.4e; lipsync2_plan.md 6.1 V11)
static void e2e_run(Session &s, int32_t id, int kind, const SY::Corpus &u, bool analysis, std::vector<PairRec> &out,
                    const SY::Corpus *warmup = nullptr, int *warm_result = nullptr)
{
    out.clear();
    fresh_mic();
    if (warmup) {
        uint32_t n[4];
        int r = warm_up_through_mic(*warmup, n);
        if (warm_result) *warm_result = r;
        std::string err;
        mic::listen(false, err);      // as the page leaves it: the talk key's press starts the utterance
        mic::listen(true, err);
    }
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
        long per_ok[8] = {}, per_n[8] = {}, warm_ok[8] = {}, warm_n[8] = {};
        bool big_keys = true;
        int warm_bad = 0;            // warm-ups that did not learn
    };
    set_engine(mic::ENGINE_V2);
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
            SY::Corpus wu = warm_utterance(g, 31u + (uint32_t)kind);     // the same speaker (the same seed's vocal tract)
            for (int mode = 2; mode >= 0; mode--) {      // 2 the analysis after the warm-up, 1 the analysis, 0 the control
                const bool analysis = mode >= 1, warmed = mode == 2;
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
                int wres = 0;
                e2e_run(s, id, kind, u, analysis, recs, warmed ? &wu : nullptr, &wres);
                kr.warm_bad += warmed && wres != 1;
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
                        if (warmed) {
                            if (sound) {
                                kr.warm_n[item]++;
                                kr.warm_ok[item] += same;
                            }
                            continue;
                        }
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
    // review R.4d: the gates are constants fixed before the run - every vowel (oh, a, a, u) 75 % per character; "i" 50 %
    // without the warm-up and 75 % after it, over the five characters' ten synthetic voices together (one voice per
    // character and group draws its own "i" token: per voice it is a coin - 54 of 60 synthetic women reach 75 % after the
    // warm-up, every man does; r094e/hear/hear_done.txt); the consonants f, m, s are reported (v2's design: f / th sit
    // under a room's floor, and a 450 ms "m" outlasts the local peak it is measured against)
    const size_t k_i = 5;      // scored[5] == "i"
    bool all_ok = true, ctl_fails = true;
    long i_ok = 0, i_n = 0, iw_ok = 0, iw_n = 0;
    int warm_bad = 0;
    for (const KindRes &kr : res) {
        std::string per, perw;
        bool each = true;
        for (size_t i = 0; i < scored.size(); i++) {
            per += format(" %s %ld/%ld", scored[i].c_str(), kr.per_ok[i], kr.per_n[i]);
            perw += format(" %s %ld/%ld", scored[i].c_str(), kr.warm_ok[i], kr.warm_n[i]);
            int c = truth_of(scored[i].c_str());
            if (i != k_i && c >= V::AA && c <= V::OO) {
                each = each && kr.per_n[i] > 0 && kr.per_ok[i] * 4 >= kr.per_n[i] * 3;
            }
        }
        i_ok += kr.per_ok[k_i];
        i_n += kr.per_n[k_i];
        iw_ok += kr.warm_ok[k_i];
        iw_n += kr.warm_n[k_i];
        warm_bad += kr.warm_bad;
        bool sil = kr.sil_n > 0 && kr.sil_ok * 4 >= kr.sil_n * 3;
        bool ctl = kr.ctl_n > 0 && kr.ctl_ok * 4 < kr.ctl_n * 3;
        all_ok = all_ok && each && sil && kr.big_keys;
        ctl_fails = ctl_fails && ctl;
        std::printf("        kind %d: sounds%s; silences closed %ld/%ld; negative control (analysis off) vowels %ld/%ld%s\n",
                    kr.kind, per.c_str(), kr.sil_ok, kr.sil_n, kr.ctl_ok, kr.ctl_n, kr.kind == 7 ? (kr.big_keys ?
                    "; Big only keys 0 / 4 / 5" : "; Big: a key above 5!") : "");
        std::printf("        kind %d after the speaker's warm-up (%d warm-ups did not learn):%s\n", kr.kind, kr.warm_bad,
                    perw.c_str());
    }
    CHECK(all_ok, "V11: Sonic, Tails, Knuckles, Amy and Big, a man and a woman, engine 2 and the table as built: in the middle "
          "60 %% of each oh / a / a / u at least 75 %% of the pairs show the true class' mouth per character (keys AND weight "
          "within 1/64 + one step), the silences closed, Big only keys 0 / 4 / 5 (f / m / s reported above)");
    CHECK(i_n > 0 && i_ok * 2 >= i_n && iw_n > 0 && iw_ok * 4 >= iw_n * 3 && warm_bad == 0,
          "V11: \"i\" shows the ee mouth in %ld of %ld pairs without the warm-up (%.0f %%; >= 50) and in %ld of %ld after the same "
          "speaker's guided warm-up (%.0f %%; >= 75; MicVisemeWarmup's steps through the fake BASS, %d of 10 warm-ups did not "
          "learn)", i_ok, i_n, pct(i_ok, i_n), iw_ok, iw_n, pct(iw_ok, iw_n), warm_bad);
    CHECK(ctl_fails, "V11: the negative control - the same runs with the analysis off (the loudness ladder) - FAILS the vowel "
          "checks for every kind (below 75 %%)");

    // V12: 50 vowel onsets after silence at random phases of block, frame and pair (Tails' "ah", its keys from mouth::pick)
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
    test_mxcsr_blocks();
    test_atomic();
    test_press_voice();
    test_stress();
    test_privacy(parent_dir(argv[0]));
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: V11 / V12 need the disc\n");
    } else {
        test_e2e(gdi);
    }
    mic::set_test_api(nullptr);
    std::printf("\n%d checks, %d failed (%.1f s)\n", g_checks, g_fail, (now_us() - t0) / 1e6);
    return g_fail ? 1 : 0;
}
