// G-SA1 core: which kind of sound the microphone hears, live - classifier v2 (round 0.9.4e, feature "faces" 3: the lip-sync
// fix; sadc docs/research/lipsync2_plan.md 4.3 / 4.4 / 5.3 with its Review R.1 / R.5, lipsync2_hear.md 4).
//
// A C++17 port of the research prototype SADC/build/research/lipsync2/hear/src/vis_new.cpp (our own code) at its defaults,
// with the review's category-balance cap (SADC/build/research/lipsync2/review/hear/src/vis_new.cpp, var_guard & 4; its mean /
// spread bounds are not adopted), the warm-up's gap phase and its plausibility rule (review R.1 / R.5). The arithmetic is kept
// in the prototype's order and types, so every frame equals the prototype's (tests/feat_hear_test.cpp V13).
//   * The front end is 0.9.4c's (viseme_v1.hpp): a 512-sample ring, a 100 Hz high-pass, a 25 ms window every 10 ms, an
//     adaptive speech gate on the newest 10 ms, the low-band share and the zero crossings, LPC order 8 on the frame decimated
//     to 8 kHz, formants from the polynomial's roots (warm-started Durand-Kerner), the 2-of-3 vote (modes 0-3).
//   * New per frame: the level against a LOCAL peak (40 dB/s), periodicity on a 4 kHz copy, the energy share under 3.4 kHz,
//     the formants' bandwidths, and the EE posterior (eep; reported, it changes no decision).
//   * Consonant rules from those (fricative, s against f, murmur, a weak-fricative gate, a low-F1 nasal rule).
//   * Speaker normalisation (Lobanov): running mean and spread of ln F1 and ln F2, learned from syllable nuclei, against a
//     reference built from 12 vowel categories with English-like weights; a category-balance cap keeps one held vowel from
//     retraining it (review R.1).
//   * The vowel decision: 12 Gaussian categories with priors; EE only for /i/, behind a posterior gate (0.55) and a 2-frame
//     hysteresis.
//   * An optional guided warm-up ("ah", "ee", "oo", "oh"): fits the speaker's corners and moves the categories toward them;
//     corners that cannot be the asked vowels change nothing (review R.5).
//
// What it keeps: a ring of the last 512 samples (32 ms) and a few hundred numbers - the trackers, the vote, and the speaker
// statistics (two means, two spreads, twelve category counts and shifts, the warm-up's sums) for the SESSION ONLY: nothing is
// stored, written or sent (owner, phoneme_plan.md 10.1 PQ7), and nothing survives the State. No allocation, no globals, no
// locale or CRT state, no I/O. Plain data: the caller owns one State per microphone (src/core/mic.cpp keeps it, and only BASS's
// recording thread touches it). Cost: about 6 microseconds per 10 ms block with denormals flushed (MXCSR FTZ | DAZ, which
// mic.cpp sets around feed()). 0.9.4c's classifier is kept verbatim as viseme_v1.hpp (the "Sound detection" choice).
#pragma once

#include <cstdint>

namespace gsa1 {
namespace viseme {

// the sound classes (unchanged from 0.9.4c: Lua and mouth.cpp use them)
enum : int {
    SIL = 0,    // silence, a pause, noise under the gate: the mouth at rest
    MBP,        // a quiet voiced murmur (m n ng) or a closure: the lips together
    AA,         // open vowels: father, cat, cup
    EH,         // mid vowels: bed, sit, day, bird, the unstressed schwa
    EE,         // the close front vowel of "see" (and y)
    OH,         // rounded mid / open: law, go
    OO,         // rounded close: who, put (and w)
    SS,         // sibilants: s z sh zh (ch j)
    FV,         // weak fricatives: f v th (h)
    COUNT
};

const int kRate = 16000;                          // Hz (the module's microphone)
const int kWin = 400;                             // the analysis window, samples (25 ms)
const int kHop = 160;                             // one analysis per 160 samples (10 ms = one BASS block)
const int kRing = 512;                            // the ring (the window plus the decimator's taps fit)
const int kDecTaps = 31;                          // the decimating low-pass (3.4 kHz, Blackman-windowed sinc)
const int kDecN = (kWin - kDecTaps) / 2 + 1;      // samples of the 8 kHz frame (185)
const int kMaxOrder = 14;                         // LPC order at most (8 by default)
const int kCats = 12;                             // the vowel categories: i I E ae A O o U u V 3r @

struct Params {
    int order = 8;                // LPC order at 8 kHz (2..kMaxOrder; 10 was tested: no better for men, worse for children)
    int norm = 2;                 // 1 Nearey-2 (a mean per formant), 2 Lobanov (mean and spread per formant)
    int i_is_ee = 0;              // 1: the /I/ category counts as EE (0.9.4c's classes); 0: /I/ is EH
    float prior_alpha = 1.0f;     // weight of the categories' log priors (0 = none)
    float ee_min = 0.55f;         // EE needs this posterior (0 = no gate)
    int ee_need = 2;              // raw EE frames in a row before EE is shown (1 = the vote only)
    int nasal_f1 = 1;             // the low-F1 nasal rule
    float nasal_f1_margin = 0.12f;  // ln units under the speaker's /i/ F1
    float nasal_lowr2 = 0.62f;    // ... with a low-band share over this
    int fric_gate = 1;            // a weak fricative passes a gate 4 dB lower
    int fe = 2;                   // the consonant rules: 1 = 0.9.4c's (low-band share + level re the slow peak), 2 =
                                  // lipsync2's (periodicity, F2 bandwidth, level re the LOCAL peak)
    float voiced_per = 0.6f;      // fe 2: periodic (voiced) above this
    float murmur_bw2 = 330.0f;    // fe 2: a murmur's F2 is weak / wide (Hz)
    int learn_loc = 1;            // learn from syllable nuclei (level re the local peak) instead of loud vowels only
    int anchor = 1;               // the warm-up's corners move the categories (a vowel-space fit), not only the means
    float anchor_spread = 0.5f;   // how much of the corners' shift the other categories take
    float close_s1 = 0.15f;       // F1 spread of the close vowels i / u (LPC's F1 is least sure there)
    int adapt = 1;                // learn the speaker ("Learn my voice"; session memory only)
    float cat_cap = 2.5f;         // review R.1: a category teaches nothing above cat_cap x its prior share (0 = off)
    float n0 = 200.0f;            // the prior's weight in vowel frames
    float nmax = 2000.0f;         // the running statistics' longest memory in vowel frames
    // the front end (as 0.9.4c)
    int gate_recent = 1;          // 1: the speech gate looks at the newest hop (10 ms) only
    int gate_adapt = 1;           // 1: gate = 0.4 x (recent peak - floor), clamped to gate_min_db .. gate_db
    float gate_min_db = 6.0f;     // "Ignore background noise below (dB)" (3..12)
    float gate_db = 12.0f;        // the gate's top (and the fixed gate without gate_adapt)
    float abs_gate_db = -55.0f;   // speech is also above this absolute level (dBFS)
    int smooth = 3;               // 0 none (instant), 1 2-of-3 vote, 2 that + vowel hysteresis (steadier), 3 the vote
                                  // except into / out of silence (quick, the default)
    // fe 1 only (0.9.4c's consonant rules)
    float fric_lowr = 0.18f, fric_zcr = 0.2f, weak_rel_db = -18.0f, ss_rel_db = -22.0f, nasal_lowr = 0.78f,
          nasal_rel_db = -7.0f;
    float hp_hz = 100.0f;         // the high-pass in front; 0 = off
};

struct Frame {
    int cls = SIL;                // the class after smoothing (what the face uses)
    int raw = SIL;                // this frame's own class (after the EE hysteresis, before the vote)
    int voiced = 0;               // 1: classified as a vowel / murmur
    int cat = -1;                 // the nearest vowel category (0..kCats-1), -1 for a non-vowel
    float db = 0, db_recent = 0, level = 0, rel_db = 0;   // dBFS, the newest hop's dBFS, 0..1, re the slow peak (<= 0)
    float f1 = 0, f2 = 0, bw1 = 0, bw2 = 0;               // formants and their bandwidths, Hz (0 = none)
    float r1 = 0, zcr = 0, lowr = 0;                      // lag-1 autocorrelation, zero crossings per sample, share < 1 kHz
    float conf = 0;               // 0..1 the posterior of the shown vowel class (1 for non-vowels)
    float x1 = 0, x2 = 0;         // the normalised position of (F1, F2)
    float gain_db = 0;            // the LPC prediction gain at 8 kHz
    float nbr = 0;                // the share of the frame's energy under 3.4 kHz
    float rel_loc = 0;            // the level re the LOCAL peak (40 dB/s decay: the syllable's nucleus), <= 0
    float per = 0;                // periodicity: the best normalised autocorrelation for F0 60-400 Hz (0..1)
    float eep = 0;                // the EE posterior of the vowel decision (0 for non-vowels; reported only)
    int iters = 0;                // root-finder iterations (-1: did not converge)
};

struct State {
    Params p;
    // the samples
    float ring[kRing];
    int pos, fill, since;
    // the high-pass: two biquads (b0 b1 b2 a0 a1 a2 each), their memories
    double hp_c[2][6], hp_m[2][4];
    int hp_on;
    // the analysis' constants
    float window[kDecN], dec_h[kDecTaps], lagwin[kMaxOrder + 1];
    // the warm start of the root finder
    double rre[kMaxOrder], rim[kMaxOrder];
    int have_roots;
    // the trackers and the vote
    float floor_db, peak_db, lpk_db;
    int frames;
    int hist[3], cur, last_vowel, ee_run;
    // the reference (computed at init from the category table): per category the normalised position, spreads, log prior
    float ref_x[kCats][2], ref_s[kCats][2], ref_lp[kCats];
    double prior_tot;             // the sum of the categories' priors (the cap's denominator)
    // the speaker (SESSION MEMORY ONLY): running mean / variance of ln F1, ln F2 and the prior they start from; the frames
    // learned from; the cap's decaying counts per category; the warm-up's shifts of every category; warmed = a warm-up
    // succeeded since init / reset_voice
    double mu[2], var[2], mu0[2], var0[2], wn;
    uint32_t voice_frames;
    float cat_h[kCats], cat_H;
    float shift[kCats][2];
    int warmed;
    // the guided warm-up: the phase (-1 none, 0-3 the corner being said, 4 a gap) and per corner (0 ah, 1 ee, 2 oo, 3 oh)
    // the sums of ln F1 / ln F2 of its good frames
    int warm_phase;
    double warm_sum[4][2], warm_n[4];
};

// the defaults (lipsync2_plan.md 4.3)
void default_params(Params &p);
// a fresh state: empty ring, floor and peak unknown, the speaker at the adult prior
void init(State &s, const Params &p);
// feeds n samples (floats, -1..1; NaN / Inf count as 0). Every completed hop is analysed; out receives the NEWEST
// min(made, max) frames in order (max may be 0). Returns how many hops were analysed (made).
int feed(State &s, const float *x, int n, Frame *out, int max);
// a talk-key press: the ring, the high-pass memory, the vote and the EE run start from silence; the floor, the peaks and the
// speaker's voice survive
void reset_press(State &s);
// forget the voice: means / spreads to the prior, wn n0, voice_frames 0, the cap's counts, the shifts and warmed cleared,
// the warm-up's sums and phase cleared
void reset_voice(State &s);
// another device (or a forced re-open): everything starts again except the voice (means, spreads, wn, voice_frames, the
// cap's counts, the shifts, warmed) and the warm-up in progress - the params are p
void reinit_keep_voice(State &s, const Params &p);
// the guided warm-up: corner 0 "ah" (the sums restart), 1 "ee", 2 "oo", 3 "oh"; 4 a gap (sums kept, nothing counted);
// < 0 or > 4: no warm-up. While a phase >= 0 runs the speaker learns nothing (review R.1).
void warm_begin(State &s, int corner);
// ends the warm-up (phase -1) and fits the corners: 1 learned (the means / spreads from the corners, the categories moved,
// the running statistics continue from the fit with the weight n0w); 2 too short (ah, ee or oo under 20 frames); 4 unclear
// (review R.5: in ln units of the corners' means ee F2 >= ah F2 + 0.15 and >= oo F2 + 0.05, ah F1 >= ee F1 + 0.25 and >=
// oo F1 + 0.20 must hold). Nothing of the voice changes unless 1.
int warm_end(State &s, float n0w);
// stops the warm-up: phase -1, the sums cleared, the voice unchanged
void warm_cancel(State &s);
// (mu1 + mu2) / 2 of the adult prior in ln Hz (the page's "speaker number" before any learning)
float prior_g();
// (mu1 + mu2) / 2 of the state's learned means (the same number for the speaker)
float voice_g(const State &s);
// "SIL", "MBP", "AA", ... ("?" outside 0..8); the page's words: "silence", "m b p", "ah", ...
const char *name(int cls);
const char *word(int cls);
// the vowel categories: "i", "I", "E", "ae", "A", "O", "o", "U", "u", "V", "3r", "@" ("?" outside); their class
const char *cat_name(int c);
int cat_class(int c);

}  // namespace viseme
}  // namespace gsa1
