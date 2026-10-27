// G-SA1 core: which kind of sound the microphone hears, live (round 0.9.4c, feature "faces" 2: phoneme lip sync; sadc
// docs/research/phoneme_plan.md 4.2 / 5.5 with its Review R.7 - R.9, phoneme_audio.md 3-7).
//
// A C++17 port of the research prototype's classifier (SADC/build/research/phoneme/audio/vis.c, our own code), method 0
// only: LPC order 8 on the frame low-passed and decimated to 8 kHz, formants from the polynomial's roots (warm-started
// Durand-Kerner), an adaptive speech gate on the newest 10 ms, two cheap spectral-shape numbers for the fricatives,
// Nearey-style log-mean speaker normalisation against published vowel averages (Peterson & Barney 1952: numbers), and a
// 2-of-3 vote. The prototype's envelope-peak path, its tables and its noise subtraction are not ported. New here: a
// 4th-order Butterworth high-pass (two biquads, Params::hp_hz, 100 Hz by default; 0 = off, as vis.c) in front of the ring
// (review R.7: mains hum), every hop analysed whatever `max` is (review R.8), and the number of vowel frames the speaker
// number learned from (State::voice_frames).
//
// What it keeps: a ring of the last 512 samples (32 ms), a few dozen numbers and the speaker number g - all overwritten
// as blocks arrive; nothing is stored, written or sent, and nothing survives the State. No allocation, no globals, no
// locale or CRT state, no I/O. Plain data: the caller owns one State per microphone (src/core/mic.cpp keeps it, and only
// BASS's recording thread touches it). Cost: about 4 microseconds per 10 ms block with denormals flushed (MXCSR FTZ |
// DAZ, which mic.cpp sets around feed()).
#pragma once

#include <cstdint>

namespace gsa1 {
namespace viseme_v1 {

// the sound classes (vis.h VIS_*; phoneme_audio.md 3)
enum : int {
    SIL = 0,    // silence, a pause, noise under the gate: the mouth at rest
    MBP,        // a quiet voiced murmur (m n ng) or a closure: the lips together
    AA,         // open vowels: father, cat, cup
    EH,         // mid vowels: bed, day, bird
    EE,         // close front vowels: see, sit (and y)
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
const int kMaxOrder = 12;                         // LPC order at most (8 by default)
const int kRefs = 10;                             // the reference vowels

struct Params {
    int order = 8;                // LPC order at 8 kHz (2..kMaxOrder)
    int gate_recent = 1;          // 1: the speech gate looks at the newest hop (10 ms) only
    int gate_adapt = 1;           // 1: gate = 0.4 x (recent peak - floor), clamped to gate_min_db .. gate_db
    float gate_min_db = 6.0f;     // "Ignore background noise below (dB)" (3..12)
    float gate_db = 12.0f;        // the gate's top (and the fixed gate without gate_adapt)
    float abs_gate_db = -55.0f;   // speech is also above this absolute level (dBFS)
    int adapt = 1;                // the speaker number: 0 the adult prior, 1 learned while talking, 2 fixed at norm_g
    float norm_g = 0.0f;          // adapt 2 (tests: the oracle)
    float adapt_rate = 0.01f;     // weight of one vowel frame (a time constant of 100 frames, 1-2 s of talking)
    int smooth = 3;               // 0 none (instant), 1 2-of-3 vote, 2 that + vowel hysteresis (steadier), 3 the vote
                                  // except into / out of silence (quick, the default)
    float fric_lowr = 0.18f;      // a fricative: the low-band share under this ...
    float fric_zcr = 0.2f;        // ... and the zero-crossing rate over this
    float weak_rel_db = -18.0f;   // a voiced frame this far under the recent peak is a murmur (MBP)
    float ss_rel_db = -22.0f;     // a fricative louder than this re the recent peak is a sibilant (SS), else FV
    float nasal_lowr = 0.78f;     // a murmur (MBP): the low-band share over this ...
    float nasal_rel_db = -7.0f;   // ... and the level under this re the recent peak
    float hp_hz = 100.0f;         // the high-pass in front (review R.7); 0 = off (the prototype's behaviour)
};

struct Frame {
    int cls = SIL;                // the class after smoothing (what the face uses)
    int raw = SIL;                // this frame's own class
    int voiced = 0;               // 1: classified as a vowel / murmur
    float db = 0.0f;              // the window's level, dBFS (a full-scale sine is -3)
    float db_recent = 0.0f;       // the newest hop's level (the speech gate's)
    float level = 0.0f;           // 0..1: db mapped -60..-10 dB (mic.cpp level_of_rms)
    float rel_db = 0.0f;          // the level re the recent loud speech (<= 0)
    float f1 = 0.0f, f2 = 0.0f;   // formants, Hz (0 = none)
    float r1 = 0.0f;              // the lag-1 autocorrelation (+1 low ... -1 high frequency)
    float zcr = 0.0f;             // zero crossings per sample
    float lowr = 0.0f;            // the energy share under about 1 kHz
    float gain_db = 0.0f;         // the LPC prediction gain
    float conf = 0.0f;            // 0..1 margin of the vowel decision (1 for non-vowels)
    float g = 0.0f;               // the speaker number in use for this frame
    int iters = 0;                // root-finder iterations (-1: did not converge)
};

struct State {
    Params p;
    // the samples
    float ring[kRing];
    int pos, fill, since;
    // the high-pass: two biquads (b0 b1 b2 a0 a1 a2 each), their memories (x1 x2 as the float inputs, y1 y2 unrounded)
    double hp_c[2][6];
    double hp_m[2][4];
    int hp_on;
    // the analysis' constants
    float window[kDecN];
    float dec_h[kDecTaps];
    float lagwin[kMaxOrder + 1];
    float ref_n[kRefs][2];        // the reference vowels, normalised (the three groups' log-means removed, averaged)
    float prior_g;                // the adult prior of the speaker number
    // the warm start of the root finder
    double rre[kMaxOrder], rim[kMaxOrder];
    int have_roots;
    // the trackers
    float floor_db, peak_db;
    int frames;
    float g;                      // the speaker number: a running mean of (ln F1 + ln F2) / 2 over vowel frames
    uint32_t voice_frames;        // vowel frames g learned from since init / reset_voice (0: the prior)
    int hist[3];
    int cur;
    int last_vowel;
};

// the defaults (vis_default_params' values for method 0, plus hp_hz 100)
void default_params(Params &p);
// a fresh state: empty ring, floor and peak unknown, g = the adult prior (adapt 2: norm_g)
void init(State &s, const Params &p);
// feeds n samples (floats, -1..1; NaN / Inf count as 0). Every completed hop is analysed; out receives the NEWEST
// min(made, max) frames in order (max may be 0). Returns how many hops were analysed (made).
int feed(State &s, const float *x, int n, Frame *out, int max);
// a talk-key press: the ring, the high-pass memory and the vote start from silence; the floor, the peak and the speaker
// number survive (the first analysis comes one hop after the press)
void reset_press(State &s);
// forget the speaker number (back to the adult prior, voice_frames 0)
void reset_voice(State &s);
// another device: everything starts again except the speaker number (g, voice_frames) - the params are p
void reinit_keep_voice(State &s, const Params &p);
// the adult prior of the speaker number (between the men's and the women's log-means of the reference table)
float prior_g();
// "SIL", "MBP", "AA", ... ("?" outside 0..8); the page's words: "silence", "m b p", "ah", ...
const char *name(int cls);
const char *word(int cls);

}  // namespace viseme_v1
}  // namespace gsa1
