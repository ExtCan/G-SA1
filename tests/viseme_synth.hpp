// G-SA1 tests: a small Klatt-style formant synthesiser and the synthetic speech corpus for the sound classifier's tests
// (round 0.9.4c; tests/feat_viseme_test.cpp). TEST-ONLY: nothing here ships in the module. A C++ port of the research
// prototype's synth.c (SADC/build/research/phoneme/audio/, our own code; phoneme_audio.md 5), with the same arithmetic and
// seeds so the corpus equals the prototype's sample for sample; the speech is made in memory at test time - no WAV file,
// no recording of anyone is in the repository.
//
// Method after D. Klatt, "Software for a cascade/parallel formant synthesizer" (JASA 1980): two-pole digital resonators in
// cascade for voiced sounds, a nasal pole / zero pair, a parallel noise branch for frication; voicing = a Rosenberg
// glottal pulse with jitter and shimmer. Vowel targets: Hillenbrand, Getty, Clark & Wheeler (1995) group averages (men /
// women / children, F1-F3; published measurements used as numbers, typed from memory: UNVERIFIED to the hertz). The
// classifier's references are a different study (Peterson & Barney 1952, src/core/viseme.cpp), so the test is not
// circular.
#pragma once

#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "../src/core/viseme.hpp"

namespace gsa1test {
namespace synth {

const int RATE = 16000;
enum { GRP_MEN = 0, GRP_WOMEN, GRP_CHILD, GRP_COUNT };
enum { SET_VOWELS = 0, SET_CV, SET_SENT, SET_COUNT };

struct Seg {
    int phone;          // index into the phone table
    int ms;             // duration
    int trans;          // formant transition into this segment, ms
    float f[5];         // formant targets (Hz) of this token
    float f0a, f0b;     // F0 at the start / end (Hz)
    float gain_db;      // per-syllable level (prosody)
};

namespace detail {

const double PI_D = 3.14159265358979323846;

struct Rng {
    uint32_t s;
};
inline uint32_t rnext(Rng *r)
{
    uint32_t x = r->s ? r->s : 0x9E3779B9u;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    r->s = x;
    return x;
}
inline double runi(Rng *r) { return (rnext(r) >> 8) * (1.0 / 16777216.0); }
inline double rgauss(Rng *r)
{
    double u = runi(r) + 1e-12, v = runi(r);
    return std::sqrt(-2.0 * std::log(u)) * std::cos(2.0 * PI_D * v);
}
inline double rrange(Rng *r, double a, double b) { return a + (b - a) * runi(r); }

enum { K_SIL, K_VOWEL, K_GLIDE, K_NASAL, K_FRIC, K_VFRIC, K_CLOS, K_VCLOS, K_BURST, K_ASP };

struct Phone {
    const char *lab;
    int kind;
    float f[3][3];      // targets (men / women / children; F1-F3): vowels and glides; consonants: the locus (men)
    float fric_f, fric_bw, fric_hp, level_db;
    float nz;           // nasal zero (Hz, men)
    unsigned truth;     // the classes a frame of this phone may show (bit = gsa1::viseme class); 0 = not scored
};

#define GSA1T_B(c) (1u << (c))
#define GSA1T_LAB {{250, 900, 2200}, {0, 0, 0}, {0, 0, 0}}
#define GSA1T_ALV {{250, 1700, 2600}, {0, 0, 0}, {0, 0, 0}}
#define GSA1T_PAL {{250, 2000, 2700}, {0, 0, 0}, {0, 0, 0}}
#define GSA1T_VEL {{250, 1500, 2300}, {0, 0, 0}, {0, 0, 0}}

inline const Phone *phones(int &n)
{
    using namespace gsa1::viseme;
    static const Phone PH[] = {
        {"sil", K_SIL, GSA1T_LAB, 0, 0, 0, -99, 0, GSA1T_B(SIL)},
        // Hillenbrand et al. 1995 (F1 F2 F3): men, women, children
        {"i", K_VOWEL, {{342, 2322, 3000}, {437, 2761, 3372}, {452, 3081, 3702}}, 0, 0, 0, 0, 0, GSA1T_B(EE)},
        {"I", K_VOWEL, {{427, 2034, 2684}, {483, 2365, 3053}, {511, 2552, 3403}}, 0, 0, 0, 0, 0, GSA1T_B(EE)},
        {"e", K_VOWEL, {{476, 2089, 2691}, {536, 2530, 3047}, {564, 2656, 3323}}, 0, 0, 0, 0, 0, GSA1T_B(EH)},
        {"E", K_VOWEL, {{580, 1799, 2605}, {731, 2058, 2979}, {749, 2267, 3310}}, 0, 0, 0, 0, 0, GSA1T_B(EH)},
        {"ae", K_VOWEL, {{588, 1952, 2601}, {669, 2349, 2972}, {717, 2501, 3289}}, 0, 0, 0, 0, 0, GSA1T_B(AA)},
        {"A", K_VOWEL, {{768, 1333, 2522}, {936, 1551, 2815}, {1002, 1688, 2950}}, 0, 0, 0, 0, 0, GSA1T_B(AA)},
        {"O", K_VOWEL, {{652, 997, 2538}, {781, 1136, 2824}, {803, 1210, 2982}}, 0, 0, 0, 0, 0, GSA1T_B(OH)},
        {"o", K_VOWEL, {{497, 910, 2459}, {555, 1035, 2828}, {597, 1137, 2987}}, 0, 0, 0, 0, 0, GSA1T_B(OH)},
        {"U", K_VOWEL, {{469, 1122, 2434}, {519, 1225, 2827}, {568, 1490, 3072}}, 0, 0, 0, 0, 0, GSA1T_B(OO)},
        {"u", K_VOWEL, {{378, 997, 2343}, {459, 1105, 2735}, {494, 1345, 2988}}, 0, 0, 0, 0, 0, GSA1T_B(OO)},
        {"V", K_VOWEL, {{623, 1200, 2550}, {753, 1426, 2933}, {749, 1546, 3145}}, 0, 0, 0, 0, 0, GSA1T_B(AA)},
        {"3r", K_VOWEL, {{474, 1379, 1710}, {523, 1588, 1929}, {586, 1719, 2143}}, 0, 0, 0, 0, 0, GSA1T_B(EH)},
        // glides / liquids (men; women x1.15, children x1.30)
        {"w", K_GLIDE, {{300, 700, 2200}, {0, 0, 0}, {0, 0, 0}}, 0, 0, 0, 0, 0, GSA1T_B(OO)},
        {"y", K_GLIDE, {{280, 2200, 2950}, {0, 0, 0}, {0, 0, 0}}, 0, 0, 0, 0, 0, GSA1T_B(EE)},
        {"l", K_GLIDE, {{360, 1050, 2700}, {0, 0, 0}, {0, 0, 0}}, 0, 0, 0, 0, 0, 0},
        {"r", K_GLIDE, {{330, 1100, 1500}, {0, 0, 0}, {0, 0, 0}}, 0, 0, 0, 0, 0, 0},
        // nasals: murmur about 12 dB under the open vowel
        {"m", K_NASAL, GSA1T_LAB, 0, 0, 0, -12, 1000, GSA1T_B(MBP)},
        {"n", K_NASAL, GSA1T_ALV, 0, 0, 0, -12, 1700, GSA1T_B(MBP) | GSA1T_B(EH)},
        {"ng", K_NASAL, GSA1T_VEL, 0, 0, 0, -12, 2500, GSA1T_B(MBP) | GSA1T_B(EH)},
        // fricatives: frication resonance, high-pass, level re the open vowel
        {"s", K_FRIC, GSA1T_ALV, 5500, 1600, 3500, -12, 0, GSA1T_B(SS)},
        {"z", K_VFRIC, GSA1T_ALV, 5500, 1600, 3500, -15, 0, GSA1T_B(SS)},
        {"sh", K_FRIC, GSA1T_PAL, 2900, 900, 1800, -9, 0, GSA1T_B(SS)},
        {"zh", K_VFRIC, GSA1T_PAL, 2900, 900, 1800, -12, 0, GSA1T_B(SS)},
        {"f", K_FRIC, GSA1T_LAB, 0, 0, 1200, -27, 0, GSA1T_B(FV)},
        {"v", K_VFRIC, GSA1T_LAB, 0, 0, 1200, -30, 0, GSA1T_B(FV)},
        {"th", K_FRIC, GSA1T_ALV, 0, 0, 1500, -29, 0, GSA1T_B(FV)},
        {"dh", K_VFRIC, GSA1T_ALV, 0, 0, 1500, -30, 0, GSA1T_B(FV)},
        {"h", K_ASP, GSA1T_LAB, 0, 0, 0, -20, 0, 0},
        // stops: closure (silent / voice bar), burst, aspiration
        {"pcl", K_CLOS, GSA1T_LAB, 0, 0, 0, -99, 0, GSA1T_B(MBP) | GSA1T_B(SIL)},
        {"tcl", K_CLOS, GSA1T_ALV, 0, 0, 0, -99, 0, GSA1T_B(MBP) | GSA1T_B(SIL)},
        {"kcl", K_CLOS, GSA1T_VEL, 0, 0, 0, -99, 0, GSA1T_B(MBP) | GSA1T_B(SIL)},
        {"bcl", K_VCLOS, GSA1T_LAB, 0, 0, 0, -26, 0, GSA1T_B(MBP) | GSA1T_B(SIL)},
        {"dcl", K_VCLOS, GSA1T_ALV, 0, 0, 0, -26, 0, GSA1T_B(MBP) | GSA1T_B(SIL)},
        {"gcl", K_VCLOS, GSA1T_VEL, 0, 0, 0, -26, 0, GSA1T_B(MBP) | GSA1T_B(SIL)},
        {"pb", K_BURST, GSA1T_LAB, 0, 0, 500, -16, 0, 0},
        {"tb", K_BURST, GSA1T_ALV, 4200, 2000, 2500, -10, 0, 0},
        {"kb", K_BURST, GSA1T_VEL, 2000, 800, 1200, -10, 0, 0},
        {"asp", K_ASP, GSA1T_LAB, 0, 0, 0, -20, 0, 0},
        // test-only (the end-to-end tests, never in the corpus): a clearly rounded "oh" - the "law" vowel at Peterson &
        // Barney's group averages (F1 F2; F3 Hillenbrand's). Hillenbrand's own "law" sits on the classifier's AA / OH
        // boundary (V1 counts it as it falls); the end-to-end test needs the OH mouth itself
        {"oh", K_VOWEL, {{570, 840, 2499}, {590, 920, 2826}, {680, 1060, 2985}}, 0, 0, 0, 0, 0, GSA1T_B(OH)},
    };
    n = (int)(sizeof PH / sizeof PH[0]);
    return PH;
}

#undef GSA1T_B
#undef GSA1T_LAB
#undef GSA1T_ALV
#undef GSA1T_PAL
#undef GSA1T_VEL

inline const Phone &ph(int p)
{
    int n = 0;
    return phones(n)[p];
}

const float GRP_SCALE[GRP_COUNT] = {1.0f, 1.15f, 1.30f};   // consonant loci / glides
const float GRP_F0[GRP_COUNT][2] = {{95, 150}, {175, 250}, {210, 290}};
const float GRP_F45[GRP_COUNT][2] = {{3400, 3900}, {4100, 4700}, {4400, 5200}};

}  // namespace detail

inline int phone_count()
{
    int n = 0;
    detail::phones(n);
    return n;
}
inline const char *phone_label(int p) { return p >= 0 && p < phone_count() ? detail::ph(p).lab : "?"; }
inline unsigned phone_truth(int p) { return p >= 0 && p < phone_count() ? detail::ph(p).truth : 0u; }
inline bool phone_is_vowel(int p) { return p >= 0 && p < phone_count() && detail::ph(p).kind == detail::K_VOWEL; }
inline int phone_find(const char *l)
{
    int n = 0;
    const detail::Phone *P = detail::phones(n);
    for (int i = 0; i < n; i++) {
        if (std::strcmp(P[i].lab, l) == 0) {
            return i;
        }
    }
    return -1;
}
inline const char *group_name(int g)
{
    static const char *const n[] = {"men", "women", "children"};
    return g >= 0 && g < GRP_COUNT ? n[g] : "?";
}
inline const char *set_name(int s)
{
    static const char *const n[] = {"vowels", "cv", "sentences"};
    return s >= 0 && s < SET_COUNT ? n[s] : "?";
}

namespace detail {

inline void targets(int p, int g, float scale, float *f)
{
    const Phone &P = ph(p);
    if (P.kind == K_VOWEL) {
        f[0] = P.f[g][0] * scale;
        f[1] = P.f[g][1] * scale;
        f[2] = P.f[g][2] * scale;
    } else {
        f[0] = P.f[0][0] * GRP_SCALE[g] * scale;
        f[1] = P.f[0][1] * GRP_SCALE[g] * scale;
        f[2] = P.f[0][2] * GRP_SCALE[g] * scale;
    }
    f[3] = GRP_F45[g][0] * scale;
    f[4] = GRP_F45[g][1] * scale;
    if (f[2] > f[3] - 300.0f) {
        f[3] = f[2] + 300.0f;
    }
    if (f[3] > f[4] - 300.0f) {
        f[4] = f[3] + 300.0f;
    }
}

inline bool add(std::vector<Seg> &s, int p, int ms, int trans, const float *f, float f0a, float f0b, float gdb)
{
    Seg g;
    g.phone = p;
    g.ms = ms;
    g.trans = trans;
    std::memcpy(g.f, f, sizeof g.f);
    g.f0a = f0a;
    g.f0b = f0b;
    g.gain_db = gdb;
    s.push_back(g);
    return true;
}

inline void token(Rng *r, int p, int g, float spk, float *f)
{
    targets(p, g, spk, f);
    for (int k = 0; k < 3; k++) {
        f[k] *= (float)std::exp(0.04 * rgauss(r));
    }
}

// a consonant (with its stop parts) before / after vowel formants vf
inline void add_cons(std::vector<Seg> &s, Rng *r, int c, int g, float spk, float f0, float gdb, int shortish, const float *vf)
{
    const Phone &P = ph(c);
    float f[5];
    token(r, c, g, spk, f);
    if (P.kind == K_CLOS || P.kind == K_VCLOS) {
        bool voiceless = P.kind == K_CLOS;
        const char *bl = P.lab[0] == 'p' || P.lab[0] == 'b' ? "pb" : (P.lab[0] == 't' || P.lab[0] == 'd' ? "tb" : "kb");
        add(s, c, shortish ? (int)rrange(r, 45, 70) : (int)rrange(r, 60, 90), 20, f, f0, f0, gdb);
        add(s, phone_find(bl), (int)rrange(r, 8, 14), 5, f, f0, f0, gdb);
        if (voiceless) {
            float af[5];
            std::memcpy(af, vf, sizeof af);
            add(s, phone_find("asp"), (int)rrange(r, 30, 55), 30, af, f0, f0, gdb);
        }
        return;
    }
    if (P.kind == K_ASP) {
        add(s, c, shortish ? (int)rrange(r, 50, 80) : (int)rrange(r, 70, 110), 20, vf, f0, f0, gdb);
        return;
    }
    if (P.kind == K_NASAL) {
        add(s, c, shortish ? (int)rrange(r, 50, 80) : (int)rrange(r, 80, 120), 25, f, f0, f0, gdb);
        return;
    }
    if (P.kind == K_GLIDE) {
        add(s, c, shortish ? (int)rrange(r, 50, 80) : (int)rrange(r, 70, 100), 40, f, f0, f0, gdb);
        return;
    }
    add(s, c, shortish ? (int)rrange(r, 70, 120) : (int)rrange(r, 120, 170), 30, f, f0, f0, gdb);
}

static const char *const VOWELS[] = {"i", "I", "e", "E", "ae", "A", "O", "o", "U", "u", "V", "3r"};
static const char *const CONS[] = {"pcl", "tcl", "kcl", "bcl", "dcl", "gcl", "m", "n", "ng", "s", "z", "sh", "zh",
                                   "f", "v", "th", "dh", "h", "w", "y", "l", "r"};
const int NV = 12, NC = 22;

}  // namespace detail

// the corpus' segments for a set and speaker group (synth.c sy_build; max 8192 segments as the prototype's)
inline std::vector<Seg> build(int set, int group, uint32_t seed, float seconds)
{
    using namespace detail;
    const size_t max = 8192;
    std::vector<Seg> s;
    Rng r;
    float spk, f[5], sil[5];
    r.s = seed * 2654435761u + 12345u + (uint32_t)group * 977u + (uint32_t)set * 7919u;
    spk = (float)std::exp(0.05 * rgauss(&r));
    targets(0, group, spk, sil);
    add(s, 0, 300, 0, sil, 0, 0, 0);
    if (set == SET_VOWELS) {
        for (int t = 0; t < 6; t++) {
            for (int i = 0; i < NV; i++) {
                float f0 = (float)rrange(&r, GRP_F0[group][0], GRP_F0[group][1]);
                int v = phone_find(VOWELS[i]);
                token(&r, v, group, spk, f);
                add(s, v, (int)rrange(&r, 240, 330), 0, f, f0 * 1.04f, f0 * 0.94f, (float)rrange(&r, -3, 3));
                add(s, 0, (int)rrange(&r, 120, 200), 0, f, 0, 0, 0);
            }
        }
    } else if (set == SET_CV) {
        static const char *const CVV[] = {"A", "i", "u"};
        for (int t = 0; t < 2; t++) {
            for (int i = 0; i < NC; i++) {
                for (int v = 0; v < 3; v++) {
                    float f0 = (float)rrange(&r, GRP_F0[group][0], GRP_F0[group][1]), vf[5];
                    int vp = phone_find(CVV[v]), c = phone_find(CONS[i]);
                    float gdb = (float)rrange(&r, -3, 3);
                    token(&r, vp, group, spk, vf);
                    add_cons(s, &r, c, group, spk, f0, gdb, 0, vf);
                    add(s, vp, (int)rrange(&r, 200, 260), 45, vf, f0 * 1.03f, f0 * 0.95f, gdb);
                    add(s, 0, (int)rrange(&r, 130, 200), 0, vf, 0, 0, 0);
                }
            }
        }
    } else {
        // pseudo-sentences: phrases of 4-9 (C)V(C) syllables with declining F0, pauses between phrases
        double total = 0.3;
        while (total < seconds && s.size() < max - 16) {
            int syl = 4 + (int)(runi(&r) * 6);
            float f0top = (float)rrange(&r, GRP_F0[group][0] * 1.05, GRP_F0[group][1]);
            for (int k = 0; k < syl && s.size() < max - 12; k++) {
                float f0 = f0top * (1.0f - 0.25f * k / syl), vf[5], gdb = (float)rrange(&r, -4, 3);
                int vp = phone_find(VOWELS[(int)(runi(&r) * NV)]);
                size_t m0 = s.size();
                token(&r, vp, group, spk, vf);
                if (runi(&r) < 0.8) {
                    add_cons(s, &r, phone_find(CONS[(int)(runi(&r) * NC)]), group, spk, f0, gdb, 1, vf);
                }
                add(s, vp, (int)rrange(&r, 70, 190), 40, vf, f0, f0 * 0.97f, gdb);
                if (runi(&r) < 0.3) {
                    int c = phone_find(CONS[(int)(runi(&r) * NC)]);
                    if (ph(c).kind != K_ASP) {
                        add_cons(s, &r, c, group, spk, f0 * 0.97f, gdb, 1, vf);
                    }
                }
                for (size_t j = m0; j < s.size(); j++) {
                    total += s[j].ms / 1000.0;
                }
            }
            int pms = (int)rrange(&r, 150, 450);
            add(s, 0, pms, 0, sil, 0, 0, 0);
            total += pms / 1000.0;
        }
    }
    add(s, 0, 300, 0, sil, 0, 0, 0);
    return s;
}

namespace detail {

struct Res2 {
    float a, b, c, y1, y2;
};
inline void res_set(Res2 *r, double f, double bw)
{
    double T = 1.0 / RATE, c = -std::exp(-2.0 * PI_D * bw * T), b = 2.0 * std::exp(-PI_D * bw * T) * std::cos(2.0 * PI_D * f * T);
    r->c = (float)c;
    r->b = (float)b;
    r->a = (float)(1.0 - b - c);
}
inline float res_run(Res2 *r, float x)
{
    float y = r->a * x + r->b * r->y1 + r->c * r->y2;
    r->y2 = r->y1;
    r->y1 = y;
    return y;
}
struct Anti2 {
    float a, b, c, x1, x2;
};
inline void anti_set(Anti2 *z, double f, double bw)
{
    Res2 r;
    res_set(&r, f, bw);
    z->a = 1.0f / r.a;
    z->b = -r.b / r.a;
    z->c = -r.c / r.a;
}
inline float anti_run(Anti2 *z, float x)
{
    float y = z->a * x + z->b * z->x1 + z->c * z->x2;
    z->x2 = z->x1;
    z->x1 = x;
    return y;
}
struct Hp1 {
    float alpha, x1, y1;
};
inline void hp_set(Hp1 *h, double fc)
{
    double rc = 1.0 / (2.0 * PI_D * fc), dt = 1.0 / RATE;
    h->alpha = (float)(rc / (rc + dt));
}
inline float hp_run(Hp1 *h, float x)
{
    float y = h->alpha * (h->y1 + x - h->x1);
    h->x1 = x;
    h->y1 = y;
    return y;
}

struct Sy {
    Rng r;
    double t, L;
    float shim;
    Res2 cas[5], nasp, fr;
    Anti2 nasz;
    Hp1 h1, h2;
    float yprev;
};

struct Amp {
    float av, ah, af, bar;
};

inline Amp seg_amp(const Phone &P, const float *cal)
{
    Amp a = {0, 0, 0, 0};
    switch (P.kind) {
    case K_VOWEL: case K_GLIDE: a.av = 1.0f; break;
    case K_NASAL: a.av = cal[0]; break;
    case K_FRIC: case K_BURST: a.af = cal[1]; break;
    case K_VFRIC: a.af = cal[1]; a.av = 0.18f; a.bar = 1.0f; break;
    case K_VCLOS: a.av = 0.05f; a.bar = 1.0f; break;
    case K_ASP: a.ah = cal[2]; break;
    default: break;
    }
    return a;
}

inline float sy_sample(Sy *S, float f0, Amp a)
{
    float g = 0.0f, u, y, noise = (float)rgauss(&S->r), out;
    if (a.av > 0.0f && f0 > 0.0f) {
        double tp = 0.40 * S->L, tn = 0.16 * S->L;
        if (S->t < tp) {
            g = (float)(0.5 * (1.0 - std::cos(PI_D * S->t / tp)));
        } else if (S->t < tp + tn) {
            g = (float)std::cos(PI_D * (S->t - tp) / (2.0 * tn));
        }
        g *= S->shim;
        S->t += 1.0;
        if (S->t >= S->L) {
            S->t -= S->L;
            S->L = RATE / (f0 * (1.0 + 0.01 * rgauss(&S->r)));
            S->shim = (float)(1.0 + 0.06 * rgauss(&S->r));
        }
    } else {
        S->t = 0.0;
        S->L = f0 > 0.0f ? RATE / f0 : 160.0;
    }
    u = a.av * g + a.av * 0.03f * noise * (g > 0.0f ? 1.0f : 0.3f) + a.ah * noise;
    u = anti_run(&S->nasz, u);
    u = res_run(&S->nasp, u);
    y = u;
    for (int k = 0; k < 5; k++) {
        if (a.bar > 0.0f && k > 0) {
            break;
        }
        y = res_run(&S->cas[k], y);
    }
    out = y - S->yprev;
    S->yprev = y;
    if (a.af > 0.0f) {
        float fn = a.af * noise;
        if (S->fr.a != 0.0f) {
            fn = res_run(&S->fr, fn);
        }
        fn = hp_run(&S->h2, hp_run(&S->h1, fn));
        out += fn;
    }
    return out;
}

inline void set_filters(Sy *S, const Phone &P, const float *f, int g)
{
    static const float BW[5] = {70, 90, 150, 250, 300};
    for (int k = 0; k < 5; k++) {
        float bw = BW[k] * (k == 0 ? (1.0f + 0.1f * g) : 1.0f);
        if (P.kind == K_NASAL && k > 0) {
            bw *= 2.5f;
        }
        if (P.kind == K_ASP) {
            bw *= 1.6f;
        }
        res_set(&S->cas[k], f[k], bw);
    }
    if (P.kind == K_NASAL) {
        anti_set(&S->nasz, P.nz * GRP_SCALE[g], 120.0);
        res_set(&S->nasp, 270.0 * GRP_SCALE[g], 100.0);
    } else {
        anti_set(&S->nasz, 270.0, 100.0);
        res_set(&S->nasp, 270.0, 100.0);
    }
    if (P.fric_f > 0.0f) {
        double ff = P.fric_f * (P.kind == K_BURST ? 1.0 : (0.85 + 0.15 * GRP_SCALE[g]));
        if (ff > 7200.0) {
            ff = 7200.0;
        }
        res_set(&S->fr, ff, P.fric_bw);
    } else {
        S->fr.a = 0.0f;
    }
    hp_set(&S->h1, P.fric_hp > 0.0f ? P.fric_hp : 100.0);
    hp_set(&S->h2, P.fric_hp > 0.0f ? P.fric_hp : 100.0);
}

inline void sy_init(Sy *S, uint32_t seed)
{
    std::memset(S, 0, sizeof *S);
    S->r.s = seed ^ 0xA5A5F00Du;
    S->L = 160.0;
    S->shim = 1.0f;
}

inline double calib_rms(int p, int g, int branch)
{
    Sy S;
    float f[5];
    Amp a = {0, 0, 0, 0};
    double e = 0.0;
    int n = RATE * 3 / 10;
    sy_init(&S, 777u);
    const Phone &P = ph(p);
    targets(p, g, 1.0f, f);
    if (P.kind == K_ASP) {
        targets(phone_find("A"), g, 1.0f, f);
    }
    set_filters(&S, P, f, g);
    if (branch == 0) a.av = 1.0f;
    if (branch == 1) a.af = 1.0f;
    if (branch == 2) a.ah = 1.0f;
    for (int i = 0; i < n; i++) {
        float v = sy_sample(&S, (GRP_F0[g][0] + GRP_F0[g][1]) * 0.5f, a);
        if (i >= RATE / 20 && i < RATE / 4) {
            e += (double)v * v;
        }
    }
    return std::sqrt(e / (RATE / 4 - RATE / 20));
}

}  // namespace detail

// renders segments to samples (16 kHz, about -20 dBFS for an open vowel) (synth.c sy_render)
inline std::vector<float> render(const std::vector<Seg> &segs, int group, uint32_t seed)
{
    using namespace detail;
    const int NPH = phone_count();
    std::vector<float> out;
    Sy S;
    float prevf[5], gain;
    std::vector<float> cal((size_t)NPH * 3);
    double ref = calib_rms(phone_find("A"), group, 0);
    Amp prev = {0, 0, 0, 0};
    float prevf0 = 0.0f, prevg = 0.0f;
    for (int k = 0; k < NPH; k++) {
        const Phone &P = ph(k);
        double t = std::pow(10.0, P.level_db / 20.0);
        cal[k * 3 + 0] = P.kind == K_NASAL ? (float)(t * ref / calib_rms(k, group, 0)) : 1.0f;
        cal[k * 3 + 1] = (P.kind == K_FRIC || P.kind == K_VFRIC || P.kind == K_BURST) ?
                         (float)(t * ref / calib_rms(k, group, 1)) : 0.0f;
        cal[k * 3 + 2] = P.kind == K_ASP ? (float)(t * ref / calib_rms(k, group, 2)) : 0.0f;
    }
    gain = (float)(0.1 / ref);
    sy_init(&S, seed);
    std::memcpy(prevf, segs[0].f, sizeof prevf);
    for (size_t si = 0; si < segs.size(); si++) {
        const Seg &sg = segs[si];
        const Phone &P = ph(sg.phone);
        Amp a = seg_amp(P, &cal[(size_t)sg.phone * 3]);
        int len = sg.ms * RATE / 1000, tr = sg.trans * RATE / 1000, ramp = RATE * 8 / 1000;
        float g = (float)std::pow(10.0, sg.gain_db / 20.0), f[5] = {0, 0, 0, 0, 0};
        if (P.kind == K_SIL) {
            g = prevg;
        }
        for (int i = 0; i < len; i++) {
            float w = tr > 0 && i < tr ? (float)i / tr : 1.0f, wa = i < ramp ? (float)i / ramp : 1.0f, f0;
            Amp ai;
            if ((i & 15) == 0) {
                for (int k = 0; k < 5; k++) {
                    f[k] = prevf[k] + (sg.f[k] - prevf[k]) * w;
                }
                set_filters(&S, P, f, group);
            }
            ai.av = prev.av + (a.av - prev.av) * wa;
            ai.ah = prev.ah + (a.ah - prev.ah) * wa;
            ai.af = prev.af + (a.af - prev.af) * wa;
            ai.bar = a.bar;
            f0 = sg.f0a + (sg.f0b - sg.f0a) * ((float)i / (len > 1 ? len : 1));
            if (f0 <= 0.0f) {
                f0 = prevf0;
            }
            out.push_back(gain * (prevg + (g - prevg) * wa) * sy_sample(&S, f0, ai));
        }
        for (int k = 0; k < 5; k++) {
            prevf[k] = prevf[k] + (sg.f[k] - prevf[k]) * 1.0f;
        }
        prev = a;
        if (sg.f0b > 0.0f) {
            prevf0 = sg.f0b;
        }
        prevg = g;
    }
    return out;
}

// adds noise at snr dB relative to the RMS of the samples where speech is (speech[i] != 0); kind 0 white, 1 pink
inline void add_noise(std::vector<float> &x, const std::vector<unsigned char> &speech, float snr_db, int kind, uint32_t seed)
{
    using namespace detail;
    Rng r;
    double es = 0.0, en = 0.0;
    int ns = 0, n = (int)x.size();
    float b0 = 0, b1 = 0, b2 = 0;
    std::vector<float> nz((size_t)n);
    r.s = seed * 7u + 1u;
    for (int i = 0; i < n; i++) {
        float w = (float)rgauss(&r);
        if (kind == 1) {
            // pink: a three-pole -3 dB/octave approximation
            b0 = 0.99765f * b0 + w * 0.0990460f;
            b1 = 0.96300f * b1 + w * 0.2965164f;
            b2 = 0.57000f * b2 + w * 1.0526913f;
            w = b0 + b1 + b2 + w * 0.1848f;
        }
        nz[i] = w;
        en += (double)w * w;
        if (speech[i]) {
            es += (double)x[i] * x[i];
            ns++;
        }
    }
    if (ns == 0 || en <= 0.0) {
        return;
    }
    double ps = es / ns, pn = en / n, k = std::sqrt(ps / pn / std::pow(10.0, snr_db / 10.0));
    for (int i = 0; i < n; i++) {
        x[i] += (float)(k * nz[i]);
    }
}

// a corpus file as the prototype's driver sees it: the samples after the 16-bit WAV round trip (written x 32767 rounded,
// read back / 32768, the last sample dropped as the prototype's reader does), the segments, and per sample the phone,
// the segment and whether it is speech
struct Corpus {
    std::vector<Seg> segs;
    std::vector<float> x;
    std::vector<short> phone;
    std::vector<int> segof;
    std::vector<int> segstart;      // segs.size() + 1 entries
    std::vector<unsigned char> speech;
};

inline void label(Corpus &c)
{
    int n = (int)c.x.size(), pos = 0;
    c.phone.assign(n, 0);
    c.segof.assign(n, 0);
    c.speech.assign(n, 0);
    c.segstart.assign(c.segs.size() + 1, 0);
    for (size_t k = 0; k < c.segs.size(); k++) {
        int len = c.segs[k].ms * RATE / 1000;
        c.segstart[k] = pos;
        for (int i = 0; i < len && pos < n; i++, pos++) {
            c.phone[pos] = (short)c.segs[k].phone;
            c.segof[pos] = (int)k;
            c.speech[pos] = std::strcmp(phone_label(c.segs[k].phone), "sil") != 0;
        }
    }
    c.segstart[c.segs.size()] = pos;
}

// the prototype's corpus file for (set, group): sy_build(set, g, 1 + g, ..., 40 s for sentences), sy_render(..., 99 + g x
// 3 + set), the WAV round trip
inline Corpus corpus(int set, int g)
{
    Corpus c;
    c.segs = build(set, g, 1u + (uint32_t)g, set == SET_SENT ? 40.0f : 0.0f);
    std::vector<float> x = render(c.segs, g, 99u + (uint32_t)(g * 3 + set));
    int n = (int)x.size();
    for (int i = 0; i < n; i++) {
        float v = x[i] * 32767.0f;
        int16_t q = (int16_t)(v > 32767.0f ? 32767 : (v < -32768.0f ? -32768 : (int)std::lrint(v)));
        x[i] = (float)(q / 32768.0);
    }
    if (n > 0) {
        x.resize((size_t)n - 1);
    }
    c.x = x;
    label(c);
    return c;
}

// a test utterance (the end-to-end tests): lead_ms of silence, then per item a sound (a vowel with the group's F0 and
// this speaker's formants, or a consonant s / f / m ... as in the CV set) of sound_ms[i] followed by gap_ms[i] of silence;
// rendered and labelled (no WAV round trip)
inline Corpus utterance(int group, uint32_t seed, const std::vector<std::string> &labels, const std::vector<int> &sound_ms,
                        const std::vector<int> &gap_ms, int lead_ms)
{
    using namespace detail;
    Corpus c;
    Rng r;
    float f[5], sil[5];
    r.s = seed * 2654435761u + 777u + (uint32_t)group * 977u;
    float spk = (float)std::exp(0.05 * rgauss(&r));
    targets(0, group, spk, sil);
    add(c.segs, 0, lead_ms, 0, sil, 0, 0, 0);
    for (size_t i = 0; i < labels.size(); i++) {
        int p = phone_find(labels[i].c_str());
        if (p < 0) {
            continue;
        }
        float f0 = (float)rrange(&r, GRP_F0[group][0], GRP_F0[group][1]);
        token(&r, p, group, spk, f);
        if (ph(p).kind == K_VOWEL || ph(p).kind == K_GLIDE) {
            add(c.segs, p, sound_ms[i], 0, f, f0 * 1.04f, f0 * 0.94f, 0.0f);
        } else {
            add(c.segs, p, sound_ms[i], 30, f, f0, f0, 0.0f);
        }
        add(c.segs, 0, gap_ms[i], 0, f, 0, 0, 0);
    }
    c.x = render(c.segs, group, seed * 3u + 11u);
    label(c);
    return c;
}

// the prototype's conditions: 0 clean (a -75 dBFS floor), 1 white 30 dB, 2 white 20, 3 white 10, 4 pink 20, 5 pink 10
struct Condition {
    const char *name;
    float snr;
    int kind;
};
inline const Condition &condition(int ci)
{
    static const Condition C[6] = {{"clean", 99, 0}, {"white 30 dB", 30, 0}, {"white 20 dB", 20, 0},
                                   {"white 10 dB", 10, 0}, {"pink 20 dB", 20, 1}, {"pink 10 dB", 10, 1}};
    return C[ci < 0 ? 0 : (ci > 5 ? 5 : ci)];
}
inline std::vector<float> with_condition(const Corpus &c, int ci, int g)
{
    std::vector<float> y = c.x;
    const Condition &cd = condition(ci);
    if (cd.snr < 90) {
        add_noise(y, c.speech, cd.snr, cd.kind, 31u + (uint32_t)(ci * 7 + g));
    } else {
        for (size_t j = 0; j < y.size(); j++) {
            y[j] += 0.0002f * (float)((uint32_t)(j * 1103515245u + 12345u) >> 16 & 0x7FFF) / 32768.0f - 0.0001f;
        }
    }
    return y;
}

// the review's channel effects (SADC/build/research/phoneme/review/audio/phoneme.c apply_fx): RBJ biquads in place
inline void biquad(std::vector<float> &x, int hp, double f0, double q)
{
    double w = 2.0 * 3.14159265358979 * f0 / RATE, c = std::cos(w), al = std::sin(w) / (2.0 * q), b0, b1, b2, a0, a1, a2;
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    if (hp) {
        b0 = (1 + c) / 2;
        b1 = -(1 + c);
        b2 = (1 + c) / 2;
    } else {
        b0 = (1 - c) / 2;
        b1 = 1 - c;
        b2 = (1 - c) / 2;
    }
    a0 = 1 + al;
    a1 = -2 * c;
    a2 = 1 - al;
    for (size_t i = 0; i < x.size(); i++) {
        double y = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
        x2 = x1;
        x1 = x[i];
        y2 = y1;
        y1 = y;
        x[i] = (float)y;
    }
}
// fx 1 band 300-3400 Hz (a narrowband / Bluetooth hands-free link), 3 clip at +-1, 4 mains hum 50 Hz + harmonics at
// -35 dBFS, 5 a crude noise-suppression gate (10 ms blocks under -50 dBFS zeroed)
inline void apply_fx(std::vector<float> &x, int fx)
{
    if (fx == 1) {
        biquad(x, 1, 300.0, 0.5412);
        biquad(x, 1, 300.0, 1.3066);
        biquad(x, 0, 3400.0, 0.5412);
        biquad(x, 0, 3400.0, 1.3066);
    } else if (fx == 3) {
        for (float &v : x) {
            v = v > 1.0f ? 1.0f : (v < -1.0f ? -1.0f : v);
        }
    } else if (fx == 4) {
        for (size_t i = 0; i < x.size(); i++) {
            double t = (double)i / RATE;
            x[i] += (float)(0.0178 * std::sin(2 * 3.14159265358979 * 50 * t) + 0.006 * std::sin(2 * 3.14159265358979 * 150 * t) +
                            0.003 * std::sin(2 * 3.14159265358979 * 250 * t));
        }
    } else if (fx == 5) {
        for (size_t i = 0; i < x.size(); i += 160) {
            size_t m = x.size() - i < 160 ? x.size() - i : 160;
            double e = 0;
            for (size_t j = 0; j < m; j++) e += (double)x[i + j] * x[i + j];
            e = 10.0 * std::log10(e / m + 1e-30);
            if (e < -50.0) {
                for (size_t j = 0; j < m; j++) x[i + j] = 0.0f;
            }
        }
    }
}

}  // namespace synth
}  // namespace gsa1test
