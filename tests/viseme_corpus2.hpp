// viseme_corpus2.hpp (test-only, header-only): the lipsync2 corpus for tests/feat_hear_test.cpp (round 0.9.4e; sadc docs/
// research/lipsync2_hear.md 5, lipsync2_plan.md 6.1 task 4). A C++ port of the research prototype's synthesiser
// (SADC/build/research/lipsync2/hear/src/synth2.c: res-audio's Klatt-style cascade / parallel formant synthesiser with nasal
// coupling, a per-speaker glottal open quotient and schwa / reduced-vowel phones) and of its driver's corpus builder, channels
// and scoring (hear.cpp + hear_part2.inc: English-like phrases with stress and reduction, diphthongs, flaps, the guided
// warm-up part; clean, USB room, narrowband headset, USB + a noise suppressor, quiet microphone; lipsync2's class
// definitions, the face and Sonic views, latency and flicker). Our own code; the arithmetic is kept in the prototype's order
// and types so the samples are the prototype's, bit for bit (feat_hear_test V13 depends on it). Everything is made in memory
// with fixed seeds: no WAV, no recording of anyone, no owner number. Vowel tables are published averages typed from memory
// (Hillenbrand et al. 1995; a British-like set after Deterding 1997 / Hawkins & Midgley 2005): UNVERIFIED to the hertz - a
// synthetic test, not a reference.
//
// Note on the unit registry: as in the prototype, a sound's accepted classes are fixed by the FIRST corpus that names it (the
// British-like "o" adds EH only when a British-like speaker registers it first). Build the American groups first, as the
// prototype's runs do, to get the prototype's scores.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace gsa1test {
namespace corpus2 {

const int RATE = 16000;
enum { SIL = 0, MBP, AA, EH, EE, OH, OO, SS, FV, COUNT };     // = gsa1::viseme's classes
inline unsigned bit(int c) { return 1u << c; }

// ---- random (the prototype's xorshift; the synthesiser and the driver use the same one) --------------------------------
struct Rng {
    uint32_t s;
    uint32_t next()
    {
        uint32_t x = s ? s : 0x9E3779B9u;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        return s = x;
    }
    double uni() { return (next() >> 8) * (1.0 / 16777216.0); }
    double gauss()
    {
        double u = uni() + 1e-12, v = uni();
        return std::sqrt(-2.0 * std::log(u)) * std::cos(2.0 * 3.14159265358979 * v);
    }
    double range(double a, double b) { return a + (b - a) * uni(); }
};

// ---- the synthesiser (synth2.c) -----------------------------------------------------------------------------------------
namespace sy {

const double PI_D = 3.14159265358979323846;
inline double rgauss(Rng *r)
{
    double u = r->uni() + 1e-12, v = r->uni();
    return std::sqrt(-2.0 * std::log(u)) * std::cos(2.0 * PI_D * v);
}
inline double rrange(Rng *r, double a, double b) { return a + (b - a) * r->uni(); }

enum { K_SIL, K_VOWEL, K_GLIDE, K_NASAL, K_FRIC, K_VFRIC, K_CLOS, K_VCLOS, K_BURST, K_ASP };

struct Phone {
    const char *lab;
    int kind;
    float f[3][3];      // targets (men / women / children; F1-F3): vowels and glides; consonants: the locus (men)
    float fric_f, fric_bw, fric_hp, level_db;   // frication shaping, level re the open vowel
    float nz;           // nasal zero (Hz, men)
    unsigned truth;
};

#define GSA1C2_LAB {{250, 900, 2200}, {0, 0, 0}, {0, 0, 0}}
#define GSA1C2_ALV {{250, 1700, 2600}, {0, 0, 0}, {0, 0, 0}}
#define GSA1C2_PAL {{250, 2000, 2700}, {0, 0, 0}, {0, 0, 0}}
#define GSA1C2_VEL {{250, 1500, 2300}, {0, 0, 0}, {0, 0, 0}}
#define GSA1C2_B(c) (1u << (c))

inline const Phone *phones(int *count)
{
    static const Phone PH[] = {
        {"sil", K_SIL, GSA1C2_LAB, 0, 0, 0, -99, 0, GSA1C2_B(SIL)},
        // Hillenbrand et al. 1995 (F1 F2 F3): men, women, children
        {"i", K_VOWEL, {{342, 2322, 3000}, {437, 2761, 3372}, {452, 3081, 3702}}, 0, 0, 0, 0, 0, GSA1C2_B(EE)},
        {"I", K_VOWEL, {{427, 2034, 2684}, {483, 2365, 3053}, {511, 2552, 3403}}, 0, 0, 0, 0, 0, GSA1C2_B(EE)},
        {"e", K_VOWEL, {{476, 2089, 2691}, {536, 2530, 3047}, {564, 2656, 3323}}, 0, 0, 0, 0, 0, GSA1C2_B(EH)},
        {"E", K_VOWEL, {{580, 1799, 2605}, {731, 2058, 2979}, {749, 2267, 3310}}, 0, 0, 0, 0, 0, GSA1C2_B(EH)},
        {"ae", K_VOWEL, {{588, 1952, 2601}, {669, 2349, 2972}, {717, 2501, 3289}}, 0, 0, 0, 0, 0, GSA1C2_B(AA)},
        {"A", K_VOWEL, {{768, 1333, 2522}, {936, 1551, 2815}, {1002, 1688, 2950}}, 0, 0, 0, 0, 0, GSA1C2_B(AA)},
        {"O", K_VOWEL, {{652, 997, 2538}, {781, 1136, 2824}, {803, 1210, 2982}}, 0, 0, 0, 0, 0, GSA1C2_B(OH)},
        {"o", K_VOWEL, {{497, 910, 2459}, {555, 1035, 2828}, {597, 1137, 2987}}, 0, 0, 0, 0, 0, GSA1C2_B(OH)},
        {"U", K_VOWEL, {{469, 1122, 2434}, {519, 1225, 2827}, {568, 1490, 3072}}, 0, 0, 0, 0, 0, GSA1C2_B(OO)},
        {"u", K_VOWEL, {{378, 997, 2343}, {459, 1105, 2735}, {494, 1345, 2988}}, 0, 0, 0, 0, 0, GSA1C2_B(OO)},
        {"V", K_VOWEL, {{623, 1200, 2550}, {753, 1426, 2933}, {749, 1546, 3145}}, 0, 0, 0, 0, 0, GSA1C2_B(AA)},
        {"@", K_VOWEL, {{500, 1500, 2500}, {580, 1750, 2900}, {650, 1950, 3200}}, 0, 0, 0, 0, 0, GSA1C2_B(EH)},
        {"ix", K_VOWEL, {{440, 1750, 2600}, {500, 2050, 3000}, {560, 2300, 3300}}, 0, 0, 0, 0, 0, GSA1C2_B(EH)},
        {"3r", K_VOWEL, {{474, 1379, 1710}, {523, 1588, 1929}, {586, 1719, 2143}}, 0, 0, 0, 0, 0, GSA1C2_B(EH)},
        // glides / liquids (men; women x1.15, children x1.30)
        {"w", K_GLIDE, {{300, 700, 2200}, {0, 0, 0}, {0, 0, 0}}, 0, 0, 0, 0, 0, GSA1C2_B(OO)},
        {"y", K_GLIDE, {{280, 2200, 2950}, {0, 0, 0}, {0, 0, 0}}, 0, 0, 0, 0, 0, GSA1C2_B(EE)},
        {"l", K_GLIDE, {{360, 1050, 2700}, {0, 0, 0}, {0, 0, 0}}, 0, 0, 0, 0, 0, 0},
        {"r", K_GLIDE, {{330, 1100, 1500}, {0, 0, 0}, {0, 0, 0}}, 0, 0, 0, 0, 0, 0},
        // nasals: murmur about 12 dB under the open vowel (scored as the closed mouth; n / ng also accept EH)
        {"m", K_NASAL, GSA1C2_LAB, 0, 0, 0, -12, 1000, GSA1C2_B(MBP)},
        {"n", K_NASAL, GSA1C2_ALV, 0, 0, 0, -12, 1700, GSA1C2_B(MBP) | GSA1C2_B(EH)},
        {"ng", K_NASAL, GSA1C2_VEL, 0, 0, 0, -12, 2500, GSA1C2_B(MBP) | GSA1C2_B(EH)},
        // fricatives: frication resonance, high-pass, level re the open vowel
        {"s", K_FRIC, GSA1C2_ALV, 5500, 1600, 3500, -12, 0, GSA1C2_B(SS)},
        {"z", K_VFRIC, GSA1C2_ALV, 5500, 1600, 3500, -15, 0, GSA1C2_B(SS)},
        {"sh", K_FRIC, GSA1C2_PAL, 2900, 900, 1800, -9, 0, GSA1C2_B(SS)},
        {"zh", K_VFRIC, GSA1C2_PAL, 2900, 900, 1800, -12, 0, GSA1C2_B(SS)},
        {"f", K_FRIC, GSA1C2_LAB, 0, 0, 1200, -27, 0, GSA1C2_B(FV)},
        {"v", K_VFRIC, GSA1C2_LAB, 0, 0, 1200, -30, 0, GSA1C2_B(FV)},
        {"th", K_FRIC, GSA1C2_ALV, 0, 0, 1500, -29, 0, GSA1C2_B(FV)},
        {"dh", K_VFRIC, GSA1C2_ALV, 0, 0, 1500, -30, 0, GSA1C2_B(FV)},
        {"h", K_ASP, GSA1C2_LAB, 0, 0, 0, -20, 0, 0},
        // stops: closure (silent / voice bar), burst, aspiration
        {"pcl", K_CLOS, GSA1C2_LAB, 0, 0, 0, -99, 0, GSA1C2_B(MBP) | GSA1C2_B(SIL)},
        {"tcl", K_CLOS, GSA1C2_ALV, 0, 0, 0, -99, 0, GSA1C2_B(MBP) | GSA1C2_B(SIL)},
        {"kcl", K_CLOS, GSA1C2_VEL, 0, 0, 0, -99, 0, GSA1C2_B(MBP) | GSA1C2_B(SIL)},
        {"bcl", K_VCLOS, GSA1C2_LAB, 0, 0, 0, -26, 0, GSA1C2_B(MBP) | GSA1C2_B(SIL)},
        {"dcl", K_VCLOS, GSA1C2_ALV, 0, 0, 0, -26, 0, GSA1C2_B(MBP) | GSA1C2_B(SIL)},
        {"gcl", K_VCLOS, GSA1C2_VEL, 0, 0, 0, -26, 0, GSA1C2_B(MBP) | GSA1C2_B(SIL)},
        {"pb", K_BURST, GSA1C2_LAB, 0, 0, 500, -16, 0, 0},
        {"tb", K_BURST, GSA1C2_ALV, 4200, 2000, 2500, -10, 0, 0},
        {"kb", K_BURST, GSA1C2_VEL, 2000, 800, 1200, -10, 0, 0},
        {"asp", K_ASP, GSA1C2_LAB, 0, 0, 0, -20, 0, 0},
    };
    if (count) *count = (int)(sizeof PH / sizeof PH[0]);
    return PH;
}
#undef GSA1C2_LAB
#undef GSA1C2_ALV
#undef GSA1C2_PAL
#undef GSA1C2_VEL
#undef GSA1C2_B

inline int phone_count()
{
    int n = 0;
    phones(&n);
    return n;
}
inline const char *phone_label(int p) { return p >= 0 && p < phone_count() ? phones(nullptr)[p].lab : "?"; }
inline unsigned phone_truth(int p) { return p >= 0 && p < phone_count() ? phones(nullptr)[p].truth : 0u; }
inline int phone_kind(int p) { return p >= 0 && p < phone_count() ? phones(nullptr)[p].kind : -1; }
inline int phone_find(const char *l)
{
    int n = 0;
    const Phone *PH = phones(&n);
    for (int i = 0; i < n; i++) {
        if (std::strcmp(PH[i].lab, l) == 0) return i;
    }
    return -1;
}

const float GRP_SCALE[3] = {1.0f, 1.15f, 1.30f};   // consonant loci / glides
const float GRP_F0[3][2] = {{95, 150}, {175, 250}, {210, 290}};
const float GRP_F45[3][2] = {{3400, 3900}, {4100, 4700}, {4400, 5200}};

struct Seg {
    int phone;       // index into the phone table
    int ms;          // duration
    int trans;       // formant transition into this segment, ms
    float f[5];      // formant targets (Hz) of this token
    float f0a, f0b;  // F0 at the start / end (Hz)
    float gain_db;   // per-syllable level (prosody)
    float nas;       // nasal coupling of a vowel 0..1
};

inline void targets(int p, int g, float scale, float *f)
{
    const Phone *ph = &phones(nullptr)[p];
    if (ph->kind == K_VOWEL) {
        f[0] = ph->f[g][0] * scale;
        f[1] = ph->f[g][1] * scale;
        f[2] = ph->f[g][2] * scale;
    } else {
        f[0] = ph->f[0][0] * GRP_SCALE[g] * scale;
        f[1] = ph->f[0][1] * GRP_SCALE[g] * scale;
        f[2] = ph->f[0][2] * GRP_SCALE[g] * scale;
    }
    f[3] = GRP_F45[g][0] * scale;
    f[4] = GRP_F45[g][1] * scale;
    if (f[2] > f[3] - 300.0f) f[3] = f[2] + 300.0f;
    if (f[3] > f[4] - 300.0f) f[4] = f[3] + 300.0f;
}

inline int add(std::vector<Seg> &s, int p, int ms, int trans, const float *f, float f0a, float f0b, float gdb)
{
    Seg g;
    g.phone = p;
    g.ms = ms;
    g.trans = trans;
    std::memcpy(g.f, f, sizeof g.f);
    g.f0a = f0a;
    g.f0b = f0b;
    g.gain_db = gdb;
    g.nas = 0.0f;
    s.push_back(g);
    return 1;
}

inline void token(Rng *r, int p, int g, float spk, float *f)
{
    targets(p, g, spk, f);
    for (int k = 0; k < 3; k++) f[k] *= (float)std::exp(0.04 * rgauss(r));
}

// a consonant (with its stop parts) before / after vowel formants vf (synth2.c add_cons)
inline int add_cons(std::vector<Seg> &s, Rng *r, int c, int g, float spk, float f0, float gdb, int shortish, const float *vf)
{
    const Phone *ph = &phones(nullptr)[c];
    float f[5];
    token(r, c, g, spk, f);
    if (ph->kind == K_CLOS || ph->kind == K_VCLOS) {
        int voiceless = ph->kind == K_CLOS;
        const char *bl = ph->lab[0] == 'p' || ph->lab[0] == 'b' ? "pb" : (ph->lab[0] == 't' || ph->lab[0] == 'd' ? "tb" : "kb");
        float af[5];
        int ok = add(s, c, shortish ? (int)rrange(r, 45, 70) : (int)rrange(r, 60, 90), 20, f, f0, f0, gdb) &&
                 add(s, phone_find(bl), (int)rrange(r, 8, 14), 5, f, f0, f0, gdb);
        if (ok && voiceless) {
            std::memcpy(af, vf, sizeof af);
            ok = add(s, phone_find("asp"), (int)rrange(r, 30, 55), 30, af, f0, f0, gdb);
        }
        return ok;
    }
    if (ph->kind == K_ASP) {
        return add(s, c, shortish ? (int)rrange(r, 50, 80) : (int)rrange(r, 70, 110), 20, vf, f0, f0, gdb);
    }
    if (ph->kind == K_NASAL) {
        return add(s, c, shortish ? (int)rrange(r, 50, 80) : (int)rrange(r, 80, 120), 25, f, f0, f0, gdb);
    }
    if (ph->kind == K_GLIDE) {
        return add(s, c, shortish ? (int)rrange(r, 50, 80) : (int)rrange(r, 70, 100), 40, f, f0, f0, gdb);
    }
    return add(s, c, shortish ? (int)rrange(r, 70, 120) : (int)rrange(r, 120, 170), 30, f, f0, f0, gdb);
}

// sy2_add_cons: a consonant with its own random stream (*seed in / out); its segments carry no nasal coupling
inline int add_cons_seeded(std::vector<Seg> &s, uint32_t *seed, int c, int g, float spk, float f0, float gdb, int shortish,
                           const float *vf)
{
    Rng r{*seed ? *seed : 1u};
    size_t k = s.size();
    int ok = add_cons(s, &r, c, g, spk, f0, gdb, shortish, vf);
    for (; k < s.size(); k++) s[k].nas = 0.0f;
    *seed = r.s;
    return ok;
}

// the filters
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

struct Synth {
    Rng r;
    double t, L;             // position in the glottal period, period length (samples)
    float shim;
    Res2 cas[5], nasp, fr;
    Anti2 nasz;
    Hp1 h1, h2;
    float yprev;
    double oq;               // the glottal open quotient (synth2.c's g_oq; a parameter here, not a global)
};

struct Amp {
    float av, ah, af, bar;
};

inline Amp seg_amp(const Phone *ph, const float *cal)
{
    Amp a = {0, 0, 0, 0};
    switch (ph->kind) {
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

// one sample with the current filter settings
inline float sample(Synth *S, float f0, Amp a)
{
    float g = 0.0f, u, y, noise = (float)rgauss(&S->r), out;
    if (a.av > 0.0f && f0 > 0.0f) {
        double tp = S->oq * S->L, tn = 0.16 * S->L;
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
        if (a.bar > 0.0f && k > 0) break;     // voice bar / voiced frication: only F1 (low murmur)
        y = res_run(&S->cas[k], y);
    }
    out = y - S->yprev;
    S->yprev = y;
    if (a.af > 0.0f) {
        float fn = a.af * noise;
        if (S->fr.a != 0.0f) fn = res_run(&S->fr, fn);
        fn = hp_run(&S->h2, hp_run(&S->h1, fn));
        out += fn;
    }
    return out;
}

inline void set_filters(Synth *S, const Phone *ph, const float *f, int g, float nas)
{
    static const float BW[5] = {70, 90, 150, 250, 300};
    for (int k = 0; k < 5; k++) {
        float bw = BW[k] * (k == 0 ? (1.0f + 0.1f * g) * (1.0f + 0.6f * nas) : 1.0f);
        if (ph->kind == K_NASAL && k > 0) bw *= 2.5f;
        if (ph->kind == K_ASP) bw *= 1.6f;
        res_set(&S->cas[k], f[k], bw);
    }
    if (ph->kind == K_NASAL) {
        anti_set(&S->nasz, ph->nz * GRP_SCALE[g], 120.0);
        res_set(&S->nasp, 270.0 * GRP_SCALE[g], 100.0);
    } else if (nas > 0.0f && (ph->kind == K_VOWEL || ph->kind == K_GLIDE)) {
        // a nasalised vowel: a nasal pole near 270 Hz and its zero moved up by the coupling
        anti_set(&S->nasz, 270.0 * GRP_SCALE[g] * (1.0 + 0.9 * nas), 110.0);
        res_set(&S->nasp, 270.0 * GRP_SCALE[g], 110.0);
    } else {
        anti_set(&S->nasz, 270.0, 100.0);
        res_set(&S->nasp, 270.0, 100.0);
    }
    if (ph->fric_f > 0.0f) {
        double ff = ph->fric_f * (ph->kind == K_BURST ? 1.0 : (0.85 + 0.15 * GRP_SCALE[g]));
        if (ff > 7200.0) ff = 7200.0;
        res_set(&S->fr, ff, ph->fric_bw);
    } else {
        S->fr.a = 0.0f;
    }
    hp_set(&S->h1, ph->fric_hp > 0.0f ? ph->fric_hp : 100.0);
    hp_set(&S->h2, ph->fric_hp > 0.0f ? ph->fric_hp : 100.0);
}

inline void synth_init(Synth *S, uint32_t seed, double oq)
{
    std::memset(S, 0, sizeof *S);
    S->r.s = seed ^ 0xA5A5F00Du;
    S->L = 160.0;
    S->shim = 1.0f;
    S->oq = oq;
}

// calibration: RMS of 300 ms of a phone alone (unit amplitudes), middle 200 ms
inline double calib_rms(int p, int g, int branch, double oq)
{
    const Phone *PH = phones(nullptr), *ph = &PH[p];
    Synth S;
    float f[5];
    Amp a = {0, 0, 0, 0};
    double e = 0.0;
    int n = RATE * 3 / 10;
    synth_init(&S, 777u, oq);
    targets(p, g, 1.0f, f);
    if (ph->kind == K_ASP) targets(phone_find("A"), g, 1.0f, f);
    set_filters(&S, ph, f, g, 0.0f);
    if (branch == 0) a.av = 1.0f;
    if (branch == 1) a.af = 1.0f;
    if (branch == 2) a.ah = 1.0f;
    for (int i = 0; i < n; i++) {
        float v = sample(&S, (GRP_F0[g][0] + GRP_F0[g][1]) * 0.5f, a);
        if (i >= RATE / 20 && i < RATE / 4) e += (double)v * v;
    }
    return std::sqrt(e / (RATE / 4 - RATE / 20));
}

// the open quotient as synth2.c's sy2_set_voice clamps it
inline double voice_oq(double oq) { return oq < 0.3 ? 0.3 : (oq > 0.75 ? 0.75 : oq); }

// renders segments (16 kHz, about -20 dBFS for an open vowel); returns the sample count (synth2.c sy_render)
inline int render(const Seg *segs, int n, int group, uint32_t seed, double oq_in, float *out, int max)
{
    const Phone *PH = nullptr;
    int NPH = 0;
    PH = phones(&NPH);
    const double oq = voice_oq(oq_in);
    Synth S;
    int pos = 0;
    float prevf[5], gain;
    std::vector<float> calv((size_t)NPH * 3);
    double ref = calib_rms(phone_find("A"), group, 0, oq);
    Amp prev = {0, 0, 0, 0};
    float prevf0 = 0.0f, prevg = 0.0f;
    for (int k = 0; k < NPH; k++) {
        double t = std::pow(10.0, PH[k].level_db / 20.0);
        calv[(size_t)k * 3 + 0] = PH[k].kind == K_NASAL ? (float)(t * ref / calib_rms(k, group, 0, oq)) : 1.0f;
        calv[(size_t)k * 3 + 1] = (PH[k].kind == K_FRIC || PH[k].kind == K_VFRIC || PH[k].kind == K_BURST)
                                      ? (float)(t * ref / calib_rms(k, group, 1, oq)) : 0.0f;
        calv[(size_t)k * 3 + 2] = PH[k].kind == K_ASP ? (float)(t * ref / calib_rms(k, group, 2, oq)) : 0.0f;
    }
    gain = (float)(0.1 / ref);      // the open vowel at about -20 dBFS
    synth_init(&S, seed, oq);
    std::memcpy(prevf, segs[0].f, sizeof prevf);
    float f[5] = {0, 0, 0, 0, 0};
    for (int si = 0; si < n; si++) {
        const Seg *sg = &segs[si];
        const Phone *ph = &PH[sg->phone];
        Amp a = seg_amp(ph, &calv[(size_t)sg->phone * 3]);
        int len = sg->ms * RATE / 1000, tr = sg->trans * RATE / 1000, ramp = RATE * 8 / 1000;
        float g = (float)std::pow(10.0, sg->gain_db / 20.0);
        if (ph->kind == K_SIL) g = prevg;
        for (int i = 0; i < len && pos < max; i++, pos++) {
            float w = tr > 0 && i < tr ? (float)i / tr : 1.0f, wa = i < ramp ? (float)i / ramp : 1.0f, f0;
            Amp ai;
            if ((i & 15) == 0) {
                for (int k = 0; k < 5; k++) f[k] = prevf[k] + (sg->f[k] - prevf[k]) * w;
                set_filters(&S, ph, f, group, sg->nas);
            }
            ai.av = prev.av + (a.av - prev.av) * wa;
            ai.ah = prev.ah + (a.ah - prev.ah) * wa;
            ai.af = prev.af + (a.af - prev.af) * wa;
            ai.bar = a.bar;
            f0 = sg->f0a + (sg->f0b - sg->f0a) * ((float)i / (len > 1 ? len : 1));
            if (f0 <= 0.0f) f0 = prevf0;
            out[pos] = gain * (prevg + (g - prevg) * wa) * sample(&S, f0, ai);
        }
        for (int k = 0; k < 5; k++) prevf[k] = prevf[k] + (sg->f[k] - prevf[k]) * 1.0f;
        prev = a;
        if (sg->f0b > 0.0f) prevf0 = sg->f0b;
        prevg = g;
    }
    return pos;
}

}  // namespace sy

// ---- the driver (hear.cpp): units, speakers, the corpus ------------------------------------------------------------------
const char *const CLS[COUNT] = {"SIL", "MBP", "AA", "EH", "EE", "OH", "OO", "SS", "FV"};

// the corpus' vowels: Hillenbrand et al. (1995) group averages (F1 F2 F3; men / women / children)
enum { V_i, V_I, V_e, V_E, V_ae, V_A, V_O, V_o, V_U, V_u, V_V, V_3r, V_COUNT };
const char *const VNAME[V_COUNT] = {"i", "I", "e", "E", "ae", "A", "O", "o", "U", "u", "V", "3r"};
const float HIL[V_COUNT][3][3] = {
    {{342, 2322, 3000}, {437, 2761, 3372}, {452, 3081, 3702}},
    {{427, 2034, 2684}, {483, 2365, 3053}, {511, 2552, 3403}},
    {{476, 2089, 2691}, {536, 2530, 3047}, {564, 2656, 3323}},
    {{580, 1799, 2605}, {731, 2058, 2979}, {749, 2267, 3310}},
    {{588, 1952, 2601}, {669, 2349, 2972}, {717, 2501, 3289}},
    {{768, 1333, 2522}, {936, 1551, 2815}, {1002, 1688, 2950}},
    {{652, 997, 2538}, {781, 1136, 2824}, {803, 1210, 2982}},
    {{497, 910, 2459}, {555, 1035, 2828}, {597, 1137, 2987}},
    {{469, 1122, 2434}, {519, 1225, 2827}, {568, 1490, 3072}},
    {{378, 997, 2343}, {459, 1105, 2735}, {494, 1345, 2988}},
    {{623, 1200, 2550}, {753, 1426, 2933}, {749, 1546, 3145}},
    {{474, 1379, 1710}, {523, 1588, 1929}, {586, 1719, 2143}},
};
// a young southern-British-like male set (FLEECE KIT FACE-onset DRESS TRAP BATH THOUGHT GOAT-onset FOOT GOOSE STRUT NURSE in
// the slots i I e E ae A O o U u V 3r): fronted GOOSE / FOOT / GOAT, close-mid THOUGHT; women x1.13 / 1.16 / 1.12.
// UNVERIFIED to the hertz - a dialect stress test, not a reference.
const float GB[V_COUNT][3] = {
    {285, 2250, 2900}, {375, 1850, 2550}, {450, 2000, 2600}, {510, 1750, 2500}, {760, 1580, 2450}, {640, 1100, 2500},
    {420, 760, 2500},  {480, 1300, 2400}, {400, 1350, 2350}, {300, 1650, 2200}, {650, 1250, 2500}, {480, 1420, 2450},
};

// what a segment is (the fine truth)
struct Unit {
    std::string name;
    unsigned mask_new, mask_old;   // accepted classes: lipsync2's (EE = /i/ only) and 0.9.4c's definitions
    int strict_new;                // the class the face should show (lipsync2)
    int vowel;                     // 1 vowel nucleus (incl. diphthong parts and reduced vowels)
};
inline std::vector<Unit> &units()
{
    static std::vector<Unit> u;
    return u;
}
inline int unit_of(const std::string &name, unsigned mn, unsigned mo, int strict, int vowel)
{
    std::vector<Unit> &U = units();
    for (size_t i = 0; i < U.size(); i++) {
        if (U[i].name == name) return (int)i;
    }
    U.push_back({name, mn, mo, strict, vowel});
    return (int)U.size() - 1;
}
inline int unit_find(const char *name)
{
    const std::vector<Unit> &U = units();
    for (size_t i = 0; i < U.size(); i++) {
        if (U[i].name == name) return (int)i;
    }
    return -1;
}
inline int unit_phone(int phone)
{
    const char *lab = sy::phone_label(phone);
    unsigned m = sy::phone_truth(phone);
    int strict = -1;
    for (int c = 0; c < COUNT; c++) {
        if (m & bit(c)) {
            strict = c;
            break;
        }
    }
    if (std::string(lab) == "n" || std::string(lab) == "ng") strict = MBP;
    if (std::string(lab) == "v" || std::string(lab) == "dh") m |= bit(MBP);   // closed lips are acceptable for v / dh
    return unit_of(lab, m, m, m ? strict : -1, 0);
}

struct Speaker {
    int group;                      // the synthesiser's group (0 men, 1 women, 2 children)
    int dialect;                    // 0 American (Hillenbrand), 1 British-like (GB table)
    float vt;                       // vocal-tract factor
    float dv[V_COUNT][3];           // per-vowel deviation (this speaker's habit)
    float f0;                       // mean F0
    float oq;                       // glottal open quotient
    uint32_t seed;
};

// corpus groups: 0 men, 1 women, 2 children (American), 3 men, 4 women (British-like)
const char *const GRP_LABEL[5] = {"men", "women", "child", "men-GB", "wom-GB"};
inline Speaker make_speaker(int cg, int idx)
{
    Rng r{0x1234567u + (uint32_t)cg * 7919u + (uint32_t)idx * 104729u};
    Speaker s;
    int group = cg >= 3 ? cg - 3 : cg;
    s.group = group;
    s.dialect = cg >= 3;
    s.seed = r.next();
    s.vt = (float)std::exp(0.05 * r.gauss());
    for (int v = 0; v < V_COUNT; v++) {
        s.dv[v][0] = (float)std::exp(0.045 * r.gauss());
        s.dv[v][1] = (float)std::exp(0.035 * r.gauss());
        s.dv[v][2] = (float)std::exp(0.025 * r.gauss());
    }
    static const float F0M[3] = {118, 205, 245}, F0S[3] = {15, 20, 25};
    s.f0 = (float)(F0M[group] + F0S[group] * r.gauss());
    if (group == 0) s.f0 = std::min(std::max(s.f0, 85.0f), 160.0f);
    s.oq = (float)r.range(0.35, 0.65);
    return s;
}

inline void vowel_f(const Speaker &sp, int v, Rng &r, float *f)
{
    static const float GBW[3] = {1.13f, 1.16f, 1.12f};
    for (int k = 0; k < 3; k++) {
        float base = sp.dialect ? GB[v][k] * (sp.group == 1 ? GBW[k] : 1.0f) : HIL[v][sp.group][k];
        f[k] = base * sp.vt * sp.dv[v][k] * (float)std::exp((k == 0 ? 0.035 : 0.03) * r.gauss());
    }
    float t[5];
    sy::targets(0, sp.group, sp.vt, t);
    f[3] = t[3];
    f[4] = t[4];
    if (f[2] > f[3] - 300.0f) f[3] = f[2] + 300.0f;
    if (f[3] > f[4] - 300.0f) f[4] = f[3] + 300.0f;
}
// the vowel-space centre of this speaker (schwa's target): geometric mean of V E 3r U I
inline void centre_f(const Speaker &sp, float *f)
{
    static const int cv[5] = {V_V, V_E, V_3r, V_U, V_I};
    static const float GBW[3] = {1.13f, 1.16f, 1.12f};
    for (int k = 0; k < 3; k++) {
        double a = 0;
        for (int i = 0; i < 5; i++) {
            float base = sp.dialect ? GB[cv[i]][k] * (sp.group == 1 ? GBW[k] : 1.0f) : HIL[cv[i]][sp.group][k];
            a += std::log(base * sp.vt * sp.dv[cv[i]][k]);
        }
        f[k] = (float)std::exp(a / 5);
    }
    float t[5];
    sy::targets(0, sp.group, sp.vt, t);
    f[3] = t[3];
    f[4] = t[4];
}
inline void toward(float *f, const float *c, float lam)
{
    for (int k = 0; k < 3; k++) f[k] = (float)std::exp(std::log(f[k]) + lam * (std::log(c[k]) - std::log(f[k])));
}

struct Corpus {
    std::vector<sy::Seg> segs;
    std::vector<int> unit;           // per segment
    std::vector<int> start;          // sample start per segment (+1 end)
    std::vector<float> x;            // samples
    int speech_start = 0;            // the main speech starts here (after the warm-up part)
    int warm_bounds[8] = {0};        // the warm-up's ah / ee / oo / oh segments: start, end samples
};

enum { N_MONO, N_DIPH };
struct Nuc {
    const char *name;
    int kind;
    int v1, v2;     // vowels (v2 for diphthong offglides; -1 for the centre, -2 the "a" of aI / aU)
    float w;        // relative frequency (tokens)
};
const Nuc STRESSED[] = {
    {"i", N_MONO, V_i, 0, 12}, {"I", N_MONO, V_I, 0, 14}, {"eI", N_DIPH, V_e, V_I, 9}, {"E", N_MONO, V_E, 0, 9},
    {"ae", N_MONO, V_ae, 0, 10}, {"A", N_MONO, V_A, 0, 7}, {"O", N_MONO, V_O, 0, 4}, {"oU", N_DIPH, V_o, V_U, 8},
    {"U", N_MONO, V_U, 0, 2}, {"u", N_MONO, V_u, 0, 6}, {"V", N_MONO, V_V, 0, 8}, {"3r", N_MONO, V_3r, 0, 5},
    {"aI", N_DIPH, -2, V_I, 9}, {"aU", N_DIPH, -2, V_U, 3}, {"OI", N_DIPH, V_O, V_I, 0.5f},
};
const Nuc UNSTRESSED[] = {
    {"@", N_MONO, -1, 0, 55}, {"ix", N_MONO, V_I, 0, 25}, {"3r", N_MONO, V_3r, 0, 10}, {"i", N_MONO, V_i, 0, 6},
    {"o", N_MONO, V_o, 0, 2}, {"u", N_MONO, V_u, 0, 2},
};
struct ConsW {
    const char *lab;
    float onset, coda;
};
const ConsW CONS[] = {
    {"n", 6, 11}, {"tcl", 9, 10}, {"dcl", 6, 6}, {"s", 7, 7}, {"dh", 7, 0.5f}, {"r", 6, 4}, {"l", 5, 5}, {"m", 5, 4},
    {"kcl", 5, 3}, {"z", 1, 7}, {"w", 5, 0}, {"h", 4, 0}, {"v", 2, 3}, {"bcl", 4, 0.5f}, {"f", 3, 1.5f},
    {"pcl", 3, 1}, {"ng", 0, 2}, {"gcl", 2, 0.5f}, {"sh", 1.5f, 0.5f}, {"y", 1.5f, 0}, {"th", 1, 1}, {"zh", 0, 0.2f},
};
template <class T, size_t N> inline int pick(Rng &r, const T (&a)[N], float T::*w)
{
    double tot = 0;
    for (size_t i = 0; i < N; i++) tot += a[i].*w;
    double u = r.uni() * tot;
    for (size_t i = 0; i < N; i++) {
        u -= a[i].*w;
        if (u <= 0) return (int)i;
    }
    return (int)N - 1;
}

inline unsigned vmask_new(int v)
{
    switch (v) {
    case V_i: return bit(EE);
    case V_I: case V_e: case V_E: return bit(EH);
    case V_ae: case V_A: case V_V: return bit(AA);
    case V_O: return bit(OH);
    case V_o: return bit(OH) | bit(OO);
    case V_U: return bit(OO) | bit(OH);
    case V_u: return bit(OO);
    case V_3r: return bit(EH) | bit(OO);
    }
    return bit(EH);
}
inline unsigned vmask_old(int v)
{
    switch (v) {
    case V_i: case V_I: return bit(EE);
    case V_e: case V_E: return bit(EH);
    default: return vmask_new(v);
    }
}
inline int first_cls(unsigned m)
{
    for (int c = 0; c < COUNT; c++) {
        if (m & bit(c)) return c;
    }
    return -1;
}

inline void add_seg(Corpus &C, int phone, int ms, int trans, const float *f, float f0a, float f0b, float gdb, int unit,
                    float nas)
{
    sy::Seg s;
    std::memset(&s, 0, sizeof s);
    s.phone = phone;
    s.ms = ms;
    s.trans = trans;
    std::memcpy(s.f, f, sizeof s.f);
    s.f0a = f0a;
    s.f0b = f0b;
    s.gain_db = gdb;
    s.nas = nas;
    C.segs.push_back(s);
    C.unit.push_back(unit);
}

inline int add_consonant(Corpus &C, Rng &r, const char *lab, const Speaker &sp, float f0, float gdb, const float *vf,
                         int flap)
{
    int ph = sy::phone_find(lab);
    if (flap) {   // an American flap: a short voiced dip, no burst
        float f[5];
        sy::targets(sy::phone_find("dcl"), sp.group, sp.vt, f);
        add_seg(C, sy::phone_find("dcl"), (int)r.range(18, 30), 10, f, f0, f0, gdb, unit_phone(sy::phone_find("dcl")), 0);
        return 1;
    }
    std::vector<sy::Seg> tmp;
    uint32_t seed = r.next();
    sy::add_cons_seeded(tmp, &seed, ph, sp.group, sp.vt, f0, gdb, 1, vf);
    for (size_t i = 0; i < tmp.size() && i < 8; i++) {
        C.segs.push_back(tmp[i]);
        C.unit.push_back(unit_phone(tmp[i].phone));
    }
    return (int)tmp.size();
}

inline int is_nasal(const char *lab) { return !std::strcmp(lab, "m") || !std::strcmp(lab, "n") || !std::strcmp(lab, "ng"); }

// the guided warm-up part: "ah", "ee", "oo", "oh" (1.3-1.7 s each) with pauses
inline void build_warm(Corpus &C, const Speaker &sp, Rng &r)
{
    float sil[5];
    sy::targets(0, sp.group, sp.vt, sil);
    int u = unit_of("warm", 0, 0, -1, 0);
    add_seg(C, 0, 400, 0, sil, 0, 0, 0, unit_of("sil", bit(SIL), bit(SIL), SIL, 0), 0);
    static const int corner[4] = {V_A, V_i, V_u, V_o};
    for (int c = 0; c < 4; c++) {
        float f[5];
        vowel_f(sp, corner[c], r, f);
        add_seg(C, sy::phone_find(VNAME[corner[c]]), (int)r.range(1300, 1700), 30, f, sp.f0 * 1.05f, sp.f0 * 0.95f, 0, u, 0);
        add_seg(C, 0, (int)r.range(500, 800), 0, sil, 0, 0, 0, unit_of("sil", bit(SIL), bit(SIL), SIL, 0), 0);
    }
}

// English-like phrases: stressed / unstressed syllables, diphthongs, nasal coupling, flaps (hear.cpp build_speech)
inline void build_speech(Corpus &C, const Speaker &sp, Rng &r, double seconds)
{
    float sil[5], cen[5];
    sy::targets(0, sp.group, sp.vt, sil);
    centre_f(sp, cen);
    int usil = unit_of("sil", bit(SIL), bit(SIL), SIL, 0);
    add_seg(C, 0, 300, 0, sil, 0, 0, 0, usil, 0);
    double total = 0.3;
    while (total < seconds) {
        int syl = 3 + (int)(r.uni() * 8);
        float f0top = sp.f0 * (float)r.range(1.0, 1.18);
        size_t m0 = C.segs.size();
        const char *prev_coda = nullptr;
        for (int k = 0; k < syl; k++) {
            float f0 = f0top * (1.0f - 0.22f * k / syl), gdb = (float)r.range(-4, 2);
            int stressed = r.uni() < 0.45;
            if (stressed) {
                f0 *= 1.08f;
                gdb += 2.0f;
            }
            // the nucleus
            const Nuc &nu = stressed ? STRESSED[pick(r, STRESSED, &Nuc::w)] : UNSTRESSED[pick(r, UNSTRESSED, &Nuc::w)];
            float f1[5], f2[5];
            int v1 = nu.v1;
            if (v1 == -1) {
                std::memcpy(f1, cen, sizeof f1);
                for (int q = 0; q < 3; q++) f1[q] *= (float)std::exp(0.07 * r.gauss());
            } else if (v1 == -2) {   // the "a" of aI / aU: between ae and A
                float a[5], b[5];
                vowel_f(sp, V_ae, r, a);
                vowel_f(sp, V_A, r, b);
                for (int q = 0; q < 5; q++) f1[q] = std::sqrt(a[q] * b[q]);
            } else {
                vowel_f(sp, v1, r, f1);
            }
            if (!stressed && v1 >= 0) toward(f1, cen, (float)r.range(0.25, 0.55));   // reduction
            int diph = nu.kind == N_DIPH;
            if (diph) {
                vowel_f(sp, nu.v2, r, f2);
                if (nu.v2 == V_I) {   // the offglide aims between I and i
                    float ii[5];
                    vowel_f(sp, V_i, r, ii);
                    toward(f2, ii, 0.4f);
                }
            }
            // the onset
            const char *onset = nullptr, *coda = nullptr;
            float vf[5];
            std::memcpy(vf, f1, sizeof vf);
            if (r.uni() < 0.78) onset = CONS[pick(r, CONS, &ConsW::onset)].lab;
            if (r.uni() < 0.42) coda = CONS[pick(r, CONS, &ConsW::coda)].lab;
            float nas = 0.0f;
            if (onset && is_nasal(onset)) nas = (float)r.range(0.3, 0.6);
            if (coda && is_nasal(coda)) nas = std::max(nas, (float)r.range(0.6, 1.0));
            if (onset) {
                int flap = prev_coda == nullptr && k > 0 && (!std::strcmp(onset, "tcl") || !std::strcmp(onset, "dcl")) &&
                           r.uni() < 0.5;
                add_consonant(C, r, onset, sp, f0, gdb, vf, flap);
            }
            prev_coda = coda;
            // the vowel segment(s)
            int dur = stressed ? (int)r.range(diph ? 150 : 90, diph ? 250 : 200) : (int)r.range(45, 90);
            std::string vname = nu.name;
            int vph = sy::phone_find(v1 >= 0 ? VNAME[v1] : (v1 == -1 ? "@" : "A"));
            if (!std::strcmp(nu.name, "ix")) vph = sy::phone_find("ix");
            unsigned mn = v1 >= 0 ? vmask_new(v1) : (v1 == -1 ? bit(EH) : bit(AA));
            if (sp.dialect && v1 == V_o) mn |= bit(EH);   // a fronted GOAT onset is neutral at first
            unsigned mo = v1 >= 0 ? (vmask_old(v1) | (sp.dialect && v1 == V_o ? bit(EH) : 0u)) : mn;
            if (!std::strcmp(nu.name, "ix")) mn = bit(EH), mo = bit(EE);
            if (!std::strcmp(nu.name, "3r") && !stressed) mn = mo = bit(EH) | bit(OO);
            if (diph) {
                int d1 = (int)(dur * r.range(0.40, 0.55)), d2 = dur - d1;
                int u1 = unit_of(vname + ".1", mn, mo, first_cls(mn), 1);
                unsigned m2n = nu.v2 == V_I ? bit(EH) : bit(OO) | bit(OH);
                unsigned m2o = nu.v2 == V_I ? bit(EE) : bit(OO) | bit(OH);
                int u2 = unit_of(vname + ".2", m2n, m2o, first_cls(m2n), 1);
                add_seg(C, vph, d1, 35, f1, f0, f0 * 0.99f, gdb, u1, nas * 0.5f);
                add_seg(C, sy::phone_find(VNAME[nu.v2]), d2, (int)(d2 * 0.8), f2, f0 * 0.99f, f0 * 0.97f, gdb, u2, nas);
            } else {
                int u1 = unit_of(stressed ? vname : vname + "~", mn, mo, first_cls(mn), 1);
                add_seg(C, vph, dur, 35, f1, f0, f0 * 0.97f, gdb, u1, nas);
            }
            if (coda) add_consonant(C, r, coda, sp, f0 * 0.97f, gdb, diph ? f2 : f1, 0);
        }
        for (size_t j = m0; j < C.segs.size(); j++) total += C.segs[j].ms / 1000.0;
        int pms = (int)r.range(150, 600);
        add_seg(C, 0, pms, 0, sil, 0, 0, 0, usil, 0);
        total += pms / 1000.0;
    }
    add_seg(C, 0, 300, 0, sil, 0, 0, 0, usil, 0);
}

inline void render(Corpus &C, const Speaker &sp)
{
    int tot = 0;
    for (auto &s : C.segs) tot += s.ms * RATE / 1000;
    C.x.assign(tot + 16, 0.0f);
    int n = sy::render(C.segs.data(), (int)C.segs.size(), sp.group, sp.seed, sp.oq, C.x.data(), (int)C.x.size());
    C.x.resize(n);
    C.start.resize(C.segs.size() + 1);
    int pos = 0;
    for (size_t i = 0; i < C.segs.size(); i++) {
        C.start[i] = pos;
        pos += C.segs[i].ms * RATE / 1000;
    }
    C.start[C.segs.size()] = pos;
}

// one speaker's corpus: the warm-up part (segments 1, 3, 5, 7 are ah ee oo oh), then `seconds` of speech
inline void build_corpus(Corpus &C, const Speaker &sp, double seconds)
{
    Rng r{sp.seed ^ 0xC0FFEEu};
    C = Corpus();
    build_warm(C, sp, r);
    size_t nwarm = C.segs.size();
    build_speech(C, sp, r, seconds);
    render(C, sp);
    for (int c = 0; c < 4; c++) {
        C.warm_bounds[2 * c] = C.start[1 + 2 * c];
        C.warm_bounds[2 * c + 1] = C.start[2 + 2 * c];
    }
    C.speech_start = C.start[nwarm];
}

// ---- channels (hear.cpp apply_cond) ---------------------------------------------------------------------------------------
inline void biquad(float *x, int n, int type, double f0, double q, double gain_db = 0)
{
    // type 0 low-pass, 1 high-pass, 2 low shelf (RBJ)
    double w = 2.0 * 3.14159265358979 * f0 / RATE, c = std::cos(w), sn = std::sin(w), al = sn / (2.0 * q);
    double b0, b1, b2, a0, a1, a2;
    if (type == 0) {
        b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al;
    } else if (type == 1) {
        b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al;
    } else {
        double A = std::pow(10.0, gain_db / 40.0), sa = 2 * std::sqrt(A) * al;
        b0 = A * ((A + 1) - (A - 1) * c + sa); b1 = 2 * A * ((A - 1) - (A + 1) * c); b2 = A * ((A + 1) - (A - 1) * c - sa);
        a0 = (A + 1) + (A - 1) * c + sa; a1 = -2 * ((A - 1) + (A + 1) * c); a2 = (A + 1) + (A - 1) * c - sa;
    }
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (int i = 0; i < n; i++) {
        double y = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
        x2 = x1; x1 = x[i]; y2 = y1; y1 = y; x[i] = (float)y;
    }
}
inline void add_noise(std::vector<float> &x, const Corpus &C, double snr_db, int pink, uint32_t seed)
{
    Rng r{seed};
    std::vector<float> nz(x.size());
    double es = 0, en = 0;
    long ns = 0;
    float b0 = 0, b1 = 0, b2 = 0;
    for (size_t i = 0; i < x.size(); i++) {
        float w = (float)r.gauss();
        if (pink) {
            b0 = 0.99765f * b0 + w * 0.0990460f;
            b1 = 0.96300f * b1 + w * 0.2965164f;
            b2 = 0.57000f * b2 + w * 1.0526913f;
            w = b0 + b1 + b2 + w * 0.1848f;
        }
        nz[i] = w;
        en += (double)w * w;
    }
    for (size_t sgi = 0; sgi < C.segs.size(); sgi++) {
        if (units()[(size_t)C.unit[sgi]].vowel) {
            for (int i = C.start[sgi]; i < C.start[sgi + 1] && i < (int)x.size(); i++) {
                es += (double)x[i] * x[i];
                ns++;
            }
        }
    }
    double ps = ns ? es / ns : 1e-4, pn = en / x.size(), k = std::sqrt(ps / pn / std::pow(10.0, snr_db / 10.0));
    for (size_t i = 0; i < x.size(); i++) x[i] += (float)(k * nz[i]);
}
enum { CH_CLEAN = 0, CH_USB, CH_NARROW, CH_SUPPRESS, CH_QUIET, CH_COUNT };
const char *const CH_NAME[CH_COUNT] = {"clean (-70 dB floor)", "USB mic, room (pink 30 dB, proximity +5 dB, 7 kHz)",
                                       "narrowband headset 300-3400 + white 25 dB", "USB + noise suppressor",
                                       "quiet mic -20 dB + room"};
inline std::vector<float> apply_cond(const Corpus &C, int ci, uint32_t seed)
{
    std::vector<float> y = C.x;
    int n = (int)y.size();
    if (ci == 0) {
        add_noise(y, C, 55.0, 1, seed);
    } else if (ci == 1 || ci == 3 || ci == 4) {
        biquad(y.data(), n, 2, 200.0, 0.7071, 5.0);
        biquad(y.data(), n, 0, 7000.0, 0.5412);
        biquad(y.data(), n, 0, 7000.0, 1.3066);
        add_noise(y, C, 30.0, 1, seed);
        if (ci == 4) {
            for (auto &v : y) v *= 0.1f;
        }
        if (ci == 3) {
            // a crude noise suppressor: 10 ms blocks more than 28 dB under the running speech peak are cut by 25 dB, with a
            // 20 ms hang
            double peak = -100;
            int hang = 0;
            for (int i = 0; i < n; i += 160) {
                int m = std::min(160, n - i);
                double e = 0;
                for (int j = 0; j < m; j++) e += (double)y[i + j] * y[i + j];
                e = 10 * std::log10(e / m + 1e-20);
                peak = e > peak ? e : peak - 0.03;
                if (e > peak - 28) hang = 2;
                else if (hang > 0) hang--;
                else for (int j = 0; j < m; j++) y[i + j] *= 0.056f;
            }
        }
    } else if (ci == 2) {
        biquad(y.data(), n, 1, 300.0, 0.5412);
        biquad(y.data(), n, 1, 300.0, 1.3066);
        biquad(y.data(), n, 0, 3400.0, 0.5412);
        biquad(y.data(), n, 0, 3400.0, 1.3066);
        add_noise(y, C, 25.0, 0, seed);
    }
    return y;
}
// the channel's seed for a speaker (the prototype's)
inline uint32_t cond_seed(const Speaker &sp, int ci) { return sp.seed * 31u + (uint32_t)ci; }

// ---- game-like sound (tones + noise bursts; the review's drift prefix and the non-speech control) -------------------------
inline void gen_game(std::vector<float> &x, int n, uint32_t seed)
{
    Rng r{seed};
    x.assign(n, 0.0f);
    static const double scale[7] = {1.0, 9.0 / 8, 5.0 / 4, 4.0 / 3, 3.0 / 2, 5.0 / 3, 15.0 / 8};
    int pos = 0;
    while (pos < n) {
        int len = (int)(RATE * r.range(0.15, 0.5));
        double f0 = 110.0 * std::pow(2.0, (int)(r.uni() * 3)) * scale[(int)(r.uni() * 7)];
        int voices = 1 + (int)(r.uni() * 3);
        for (int v = 0; v < voices; v++) {
            double fv = f0 * scale[(int)(r.uni() * 7)] * (v ? 2 : 1), ph = 0;
            for (int i = 0; i < len && pos + i < n; i++) {
                double env = std::min(1.0, i / 160.0) * std::exp(-3.0 * i / len), s = 0;
                ph += 2 * 3.14159265358979 * fv / RATE;
                for (int h = 1; h <= 8; h++) s += std::sin(h * ph) / h;
                x[pos + i] += (float)(0.03 * env * s);
            }
        }
        if (r.uni() < 0.4) {
            for (int i = 0; i < 1600 && pos + i < n; i++) x[pos + i] += (float)(0.05 * r.gauss() * std::exp(-i / 300.0));
        }
        pos += len;
        if (r.uni() < 0.3) pos += (int)(RATE * r.range(0.1, 0.6));
    }
}

// ---- scoring (hear_part2.inc score; lipsync2_hear.md 5.4) ------------------------------------------------------------------
const int FACE_OF[COUNT] = {0, 0, 1, 2, 3, 4, 4, 5, 5};    // closed open mid wide round teeth
// what Sonic can show (phoneme_plan.md 4.3 in 0.9.4c): closed (SIL MBP FV), his slit key 4 (EH EE SS), open, round-open, pucker
const int SONIC_OF[COUNT] = {0, 0, 2, 1, 1, 3, 4, 1, 0};
inline unsigned sonic_mask(unsigned m)
{
    unsigned f = 0;
    for (int c = 0; c < COUNT; c++) {
        if (m & bit(c)) f |= 1u << SONIC_OF[c];
    }
    return f;
}
inline unsigned face_mask(unsigned m)
{
    unsigned f = 0;
    for (int c = 0; c < COUNT; c++) {
        if (m & bit(c)) f |= 1u << FACE_OF[c];
    }
    return f;
}

// one classifier frame as the scoring sees it
struct Out {
    int cls, raw;
    float f1, f2;
    int end;           // the sample just after the frame's window
};

struct Score {
    long conf[COUNT][COUNT] = {};   // truth (lipsync2's strict class) x output
    long n = 0, ok_new = 0, ok_old = 0, ok_face = 0, ok_lenient = 0, ok_sonic = 0;
    long n_early = 0, ok_early = 0;
    long out_all[COUNT] = {};       // output over every frame of the main speech
    long vowel_truth[COUNT] = {}, vowel_out[COUNT] = {};
    long ee_tp = 0, ee_fp = 0, ee_fn = 0;
    std::vector<std::vector<long>> unit;    // unit x output
    std::vector<float> lat_on, lat_off, lat_shape;
    long lat_never = 0;
    long fc_out = 0, fc_truth = 0;
    double secs = 0;
    void add(const Score &o)
    {
        for (int a = 0; a < COUNT; a++)
            for (int b = 0; b < COUNT; b++) conf[a][b] += o.conf[a][b];
        n += o.n; ok_new += o.ok_new; ok_old += o.ok_old; ok_face += o.ok_face; ok_lenient += o.ok_lenient;
        ok_sonic += o.ok_sonic; n_early += o.n_early; ok_early += o.ok_early;
        for (int c = 0; c < COUNT; c++) {
            out_all[c] += o.out_all[c];
            vowel_truth[c] += o.vowel_truth[c];
            vowel_out[c] += o.vowel_out[c];
        }
        ee_tp += o.ee_tp; ee_fp += o.ee_fp; ee_fn += o.ee_fn;
        if (unit.size() < o.unit.size()) unit.resize(o.unit.size(), std::vector<long>(COUNT, 0));
        for (size_t u = 0; u < o.unit.size(); u++)
            for (int c = 0; c < COUNT; c++) unit[u][c] += o.unit[u][c];
        lat_on.insert(lat_on.end(), o.lat_on.begin(), o.lat_on.end());
        lat_off.insert(lat_off.end(), o.lat_off.begin(), o.lat_off.end());
        lat_shape.insert(lat_shape.end(), o.lat_shape.begin(), o.lat_shape.end());
        lat_never += o.lat_never;
        fc_out += o.fc_out; fc_truth += o.fc_truth; secs += o.secs;
    }
    // the shares the tests gate on
    long vowel_frames() const
    {
        long v = 0;
        for (int c = 2; c <= 6; c++) v += vowel_out[c];
        return v;
    }
};

inline double pct(long a, long b) { return b ? 100.0 * a / b : 0.0; }
inline float quant(std::vector<float> v, double q)
{
    if (v.empty()) return 0;
    std::sort(v.begin(), v.end());
    return v[std::min(v.size() - 1, (size_t)(v.size() * q))];
}

inline int seg_at(const Corpus &C, int sample)
{
    auto it = std::upper_bound(C.start.begin(), C.start.end(), sample);
    int i = (int)(it - C.start.begin()) - 1;
    return i < 0 ? 0 : (i >= (int)C.segs.size() ? (int)C.segs.size() - 1 : i);
}

inline void score(Score &S, const Corpus &C, const std::vector<Out> &out)
{
    const std::vector<Unit> &U = units();
    S.unit.assign(U.size(), std::vector<long>(COUNT, 0));
    const int guard = 320;   // 20 ms from a segment's edges
    for (const Out &o : out) {
        S.out_all[o.cls]++;
        int c = o.end - 200, si = seg_at(C, c);
        const Unit &u = U[(size_t)C.unit[(size_t)si]];
        if (u.strict_new < 0) continue;
        if (c - C.start[si] < guard || C.start[si + 1] - c < guard) continue;
        S.unit[(size_t)C.unit[(size_t)si]][o.cls]++;
        S.conf[u.strict_new][o.cls]++;
        S.n++;
        int okn = (u.mask_new >> o.cls) & 1;
        S.ok_new += okn;
        S.ok_old += (u.mask_old >> o.cls) & 1;
        S.ok_lenient += ((u.mask_new | u.mask_old) >> o.cls) & 1;
        S.ok_face += (face_mask(u.mask_new) >> FACE_OF[o.cls]) & 1;
        S.ok_sonic += (sonic_mask(u.mask_new) >> SONIC_OF[o.cls]) & 1;
        if (o.end - C.speech_start < 10 * RATE) {
            S.n_early++;
            S.ok_early += okn;
        }
        if (u.vowel) {
            S.vowel_truth[u.strict_new]++;
            S.vowel_out[o.cls]++;
        }
        int t_ee = u.strict_new == EE, o_ee = o.cls == EE;
        S.ee_tp += t_ee && o_ee;
        S.ee_fp += !t_ee && o_ee;
        S.ee_fn += t_ee && !o_ee;
    }
    // latency: segments of >= 60 ms whose class differs from the previous scored segment's
    int prev = SIL;
    size_t oi = 0;
    for (size_t si = 0; si < C.segs.size(); si++) {
        if (C.start[si] < C.speech_start) continue;
        const Unit &u = U[(size_t)C.unit[si]];
        if (u.strict_new < 0) continue;
        int len = C.start[si + 1] - C.start[si];
        if (len >= 60 * 16 && !((u.mask_new >> prev) & 1)) {
            while (oi < out.size() && out[oi].end <= C.start[si]) oi++;
            size_t k = oi;
            for (; k < out.size() && out[k].end <= C.start[si + 1]; k++)
                if ((u.mask_new >> out[k].cls) & 1) break;
            if (k < out.size() && out[k].end <= C.start[si + 1]) {
                float ms = (out[k].end - C.start[si]) / 16.0f;
                if (prev == SIL) S.lat_on.push_back(ms);
                else if (u.strict_new == SIL) S.lat_off.push_back(ms);
                else S.lat_shape.push_back(ms);
            } else {
                S.lat_never++;
            }
        }
        prev = u.strict_new;
    }
    // flicker at the 30 Hz pair rate
    int lf_o = -1, lf_t = -1, truth = SIL;
    size_t k = 0;
    for (double t = C.speech_start + 1000; t < (double)C.x.size() - 400; t += RATE / 30.0) {
        while (k + 1 < out.size() && out[k + 1].end <= t) k++;
        if (k >= out.size()) break;
        int fo = FACE_OF[out[k].cls];
        int si = seg_at(C, (int)t - 200);
        if (U[(size_t)C.unit[(size_t)si]].strict_new >= 0) truth = U[(size_t)C.unit[(size_t)si]].strict_new;
        int ft = FACE_OF[truth];
        if (lf_o >= 0 && fo != lf_o) S.fc_out++;
        if (lf_t >= 0 && ft != lf_t) S.fc_truth++;
        lf_o = fo;
        lf_t = ft;
        S.secs += 1.0 / 30.0;
    }
}

}  // namespace corpus2
}  // namespace gsa1test
