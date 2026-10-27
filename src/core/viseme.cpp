// G-SA1 core: the live sound classifier v2 (see viseme.hpp). A port of the research prototype vis_new.cpp (our own code);
// the arithmetic is kept in the prototype's order and types, so every frame equals the prototype's (tests/feat_hear_test.cpp
// V13 against the review's copy with the category cap and the warm-up's plausibility rule).
#include "viseme.hpp"

#include <cmath>
#include <cstring>

namespace gsa1 {
namespace viseme {

namespace {

const double kPi = 3.14159265358979323846;

// The classifier's vowel categories: average F1 / F2 of Peterson & Barney (1952), men / women / children (the same numbers
// as the 0.9.4c classifier; typed from memory, UNVERIFIED to the hertz); /o/ interpolated between U and O (geometric means;
// P&B has no /o/); schwa from the uniform tube (500 / 1500 Hz for a 17.5 cm tract, x1.17 women, x1.30 children). Not
// Hillenbrand: the test corpus is synthesised from Hillenbrand et al. (1995), so the test is not circular.
// prior = an estimate of each category's share of vowel TIME in conversational American English (diphthong onsets and
// offglides folded into their monophthongs), from memory: UNVERIFIED (lipsync2_hear.md 4.4; the result barely depends on
// them). Published averages are numbers, not game data.
struct Cat {
    const char *name;
    int cls;          // the class it shows
    float f[3][2];    // F1 / F2 (Hz): men, women, children
    float prior;      // share of vowel time (%)
    float s1, s2;     // the category's spread, ln units (F1, F2)
};
const Cat kCat[kCats] = {
    {"i", EE, {{270, 2290}, {310, 2790}, {370, 3200}}, 10.3f, 0.11f, 0.075f},
    {"I", EH, {{390, 1990}, {430, 2480}, {530, 2730}}, 21.2f, 0.11f, 0.085f},
    {"E", EH, {{530, 1840}, {610, 2330}, {690, 2610}}, 7.7f, 0.11f, 0.085f},
    {"ae", AA, {{660, 1720}, {860, 2050}, {1010, 2320}}, 8.0f, 0.11f, 0.085f},
    {"A", AA, {{730, 1090}, {850, 1220}, {1030, 1370}}, 11.6f, 0.11f, 0.085f},
    {"O", OH, {{570, 840}, {590, 920}, {680, 1060}}, 4.0f, 0.11f, 0.085f},
    {"o", OH, {{501, 926}, {527, 1033}, {617, 1223}}, 3.5f, 0.11f, 0.085f},
    {"U", OO, {{440, 1020}, {470, 1160}, {560, 1410}}, 6.7f, 0.11f, 0.10f},
    {"u", OO, {{300, 870}, {370, 950}, {430, 1170}}, 4.9f, 0.11f, 0.11f},
    {"V", AA, {{640, 1190}, {760, 1400}, {850, 1590}}, 4.4f, 0.11f, 0.085f},
    {"3r", EH, {{490, 1350}, {500, 1640}, {560, 1820}}, 5.9f, 0.11f, 0.10f},
    {"@", EH, {{500, 1500}, {585, 1755}, {650, 1950}}, 11.7f, 0.16f, 0.13f},
};
const int kCatI = 0, kCatA = 4, kCatU = 8, kCatOo = 6;

int cat_class_of(int c, int i_is_ee)
{
    if (c < 0 || c >= kCats) {
        return SIL;
    }
    if (c == 1 && i_is_ee) {
        return EE;
    }
    return kCat[c].cls;
}

// Levinson-Durbin: a[0] = 1, a[1..p]; returns the prediction error (0 when degenerate)
double levinson(const double *r, int p, double *a)
{
    double err = r[0], tmp[kMaxOrder + 1];
    a[0] = 1.0;
    for (int i = 1; i <= p; i++) {
        a[i] = 0.0;
    }
    if (err <= 0.0) {
        return 0.0;
    }
    for (int i = 1; i <= p; i++) {
        double acc = r[i], k;
        for (int j = 1; j < i; j++) {
            acc += a[j] * r[i - j];
        }
        k = -acc / err;
        for (int j = 1; j < i; j++) {
            tmp[j] = a[j] + k * a[i - j];
        }
        for (int j = 1; j < i; j++) {
            a[j] = tmp[j];
        }
        a[i] = k;
        err *= 1.0 - k * k;
        if (err <= 0.0) {
            return 0.0;
        }
    }
    return err;
}

// roots of z^p + a1 z^(p-1) + ... + ap (Durand-Kerner); warm = start from the previous frame's roots. Returns the
// iterations, or -1 when it did not converge.
int roots_dk(const double *a, int p, double *re, double *im, int warm)
{
    if (!warm) {
        for (int i = 0; i < p; i++) {
            double ang = 2.0 * kPi * i / p + 0.4;
            re[i] = 0.9 * std::cos(ang);
            im[i] = 0.9 * std::sin(ang);
        }
    } else {
        for (int i = 0; i < p; i++) {     // separate exact conjugates / reals a little
            re[i] += 1e-7 * (i + 1);
            im[i] += 1e-7 * (2 * i + 1);
        }
    }
    for (int it = 0; it < 100; it++) {
        double maxd = 0.0;
        for (int i = 0; i < p; i++) {
            double zr = re[i], zi = im[i], pr = 1.0, pi_ = 0.0, dr = 1.0, di = 0.0, den, qr, qi, t;
            for (int k = 1; k <= p; k++) {
                t = pr * zr - pi_ * zi + a[k];
                pi_ = pr * zi + pi_ * zr;
                pr = t;
            }
            for (int j = 0; j < p; j++) {
                double xr, xi;
                if (j == i) {
                    continue;
                }
                xr = zr - re[j];
                xi = zi - im[j];
                t = dr * xr - di * xi;
                di = dr * xi + di * xr;
                dr = t;
            }
            den = dr * dr + di * di;
            if (den < 1e-300) {
                re[i] += 1e-6;
                im[i] += 1e-6;
                maxd = 1.0;
                continue;
            }
            qr = (pr * dr + pi_ * di) / den;
            qi = (pi_ * dr - pr * di) / den;
            re[i] -= qr;
            im[i] -= qi;
            t = qr * qr + qi * qi;
            if (t > maxd) {
                maxd = t;
            }
        }
        if (maxd < 1e-16) {
            return it + 1;
        }
    }
    return -1;
}

// F1 / F2 (and their bandwidths) from candidates sorted by frequency (0.9.4c's rule)
void pick_f1f2(const float *f, const float *bw, int n, float *f1, float *f2, float *b1, float *b2)
{
    int i1 = -1;
    *f1 = *f2 = *b1 = *b2 = 0.0f;
    for (int i = 0; i < n; i++) {
        if (f[i] >= 180.0f && f[i] <= 1200.0f && bw[i] < 500.0f) {
            i1 = i;
            break;
        }
    }
    if (i1 < 0) {
        return;
    }
    *f1 = f[i1];
    *b1 = bw[i1];
    for (int i = i1 + 1; i < n; i++) {
        if (f[i] > f[i1] + 150.0f && f[i] >= 550.0f && f[i] <= 3500.0f && bw[i] < 600.0f) {
            *f2 = f[i];
            *b2 = bw[i];
            return;
        }
    }
}

void formants_roots(State &s, const double *a, float *f1, float *f2, float *b1, float *b2, int *iters)
{
    const int p = s.p.order, lpc_rate = kRate / 2;
    int n = 0;
    float f[kMaxOrder], bw[kMaxOrder];
    int it = roots_dk(a, p, s.rre, s.rim, s.have_roots);
    if (it < 0 && s.have_roots) {
        it = roots_dk(a, p, s.rre, s.rim, 0);     // cold restart
    }
    *iters = it;
    s.have_roots = it > 0;
    if (it < 0) {
        *f1 = *f2 = *b1 = *b2 = 0.0f;
        return;
    }
    for (int i = 0; i < p; i++) {
        double r = std::sqrt(s.rre[i] * s.rre[i] + s.rim[i] * s.rim[i]), fr, b;
        if (s.rim[i] <= 1e-6 || r <= 0.0) {
            continue;
        }
        fr = std::atan2(s.rim[i], s.rre[i]) * lpc_rate / (2.0 * kPi);
        b = -std::log(r) * lpc_rate / kPi;
        if (fr < 120.0 || fr > 3900.0) {
            continue;
        }
        int j = n++;           // insertion sort by frequency
        while (j > 0 && f[j - 1] > fr) {
            f[j] = f[j - 1];
            bw[j] = bw[j - 1];
            j--;
        }
        f[j] = (float)fr;
        bw[j] = (float)b;
    }
    pick_f1f2(f, bw, n, f1, f2, b1, b2);
}

// the normalised position of (f1, f2) for the speaker
inline void norm_xy(const State &s, float f1, float f2, float *x1, float *x2)
{
    double l1 = std::log((double)f1), l2 = std::log((double)f2);
    if (s.p.norm == 2) {
        *x1 = (float)((l1 - s.mu[0]) / std::sqrt(s.var[0]));
        *x2 = (float)((l2 - s.mu[1]) / std::sqrt(s.var[1]));
    } else {
        *x1 = (float)(l1 - s.mu[0]);
        *x2 = (float)(l2 - s.mu[1]);
    }
}

// the vowel decision: the argmax of the summed category posteriors per class, EE behind its posterior gate. Returns the
// class; *conf = its posterior; *alt = the best other class; *cat the nearest category; *eep the EE posterior (reported)
int classify_vowel(const State &s, float x1, float x2, float *conf, int *alt, int *cat, float *eep)
{
    double ll[kCats], mx = -1e30, pc[COUNT] = {0}, tot = 0.0;
    int bc = 0;
    for (int c = 0; c < kCats; c++) {
        double d1 = (x1 - s.ref_x[c][0] - s.shift[c][0]) / s.ref_s[c][0],
               d2 = (x2 - s.ref_x[c][1] - s.shift[c][1]) / s.ref_s[c][1];
        ll[c] = -0.5 * (d1 * d1 + d2 * d2) - std::log((double)s.ref_s[c][0] * s.ref_s[c][1]) + s.ref_lp[c];
        if (ll[c] > mx) {
            mx = ll[c];
            bc = c;
        }
    }
    for (int c = 0; c < kCats; c++) {
        double e = std::exp(ll[c] - mx);
        pc[cat_class_of(c, s.p.i_is_ee)] += e;
        tot += e;
    }
    int best = -1, second = -1;
    for (int k = AA; k <= OO; k++) {
        if (best < 0 || pc[k] > pc[best]) {
            second = best;
            best = k;
        } else if (second < 0 || pc[k] > pc[second]) {
            second = k;
        }
    }
    *cat = bc;
    *eep = (float)(pc[EE] / tot);
    if (best == EE && s.p.ee_min > 0.0f && pc[EE] < s.p.ee_min * tot) {
        best = second;
        second = EE;
    }
    *conf = (float)(pc[best] / tot);
    *alt = second;
    return best;
}

// one nucleus frame into the speaker statistics (cat: the frame's category, for the balance cap)
void learn(State &s, float f1, float f2, int cat)
{
    double x[2] = {std::log((double)f1), std::log((double)f2)};
    if (s.voice_frames > 50) {
        for (int k = 0; k < 2; k++) {
            double d = (x[k] - s.mu[k]) / std::sqrt(s.var[k]);
            if (d > 3.5 || d < -3.5) {
                return;    // an outlier (a tracking error) teaches nothing
            }
        }
    }
    // review R.1: the category-balance cap - after 50 learned frames, a frame whose category already holds more than
    // cat_cap x its prior share of the (decaying) learned frames teaches nothing, so one held vowel cannot retrain the voice
    if (s.p.cat_cap > 0.0f && cat >= 0 && cat < kCats) {
        if (s.cat_H > 50.0f && s.cat_h[cat] > s.p.cat_cap * (kCat[cat].prior / s.prior_tot) * s.cat_H) {
            return;
        }
        const float dk = 1.0f - 1.0f / 1000.0f;
        for (int c = 0; c < kCats; c++) {
            s.cat_h[c] *= dk;
        }
        s.cat_H = s.cat_H * dk + 1.0f;
        s.cat_h[cat] += 1.0f;
    }
    s.voice_frames++;
    double n = s.voice_frames < s.p.nmax ? (double)s.voice_frames : (double)s.p.nmax;
    double w = 1.0 / (s.wn + n);
    for (int k = 0; k < 2; k++) {
        double d = x[k] - s.mu[k];
        s.mu[k] += w * d;
        s.var[k] = (1.0 - w) * (s.var[k] + w * d * d);
        if (s.var[k] < 1e-4) {
            s.var[k] = 1e-4;
        }
    }
}

// one analysis of the newest kWin samples
void analyse(State &s, Frame &o)
{
    const int N = kWin, P = s.p.order, M = kDecN;
    float x[kWin], y[kDecN];
    double r[kMaxOrder + 1], a[kMaxOrder + 1], err, e = 0.0, r0 = 0.0, r1 = 0.0, el = 0.0, mean = 0.0;
    int zc = 0, start = s.pos - N, speech, raw, alt = -1;
    float f1 = 0.0f, f2 = 0.0f, b1 = 0.0f, b2 = 0.0f, conf = 1.0f, gate;

    o = Frame();
    if (start < 0) {
        start += kRing;
    }
    for (int i = 0; i < N; i++) {
        x[i] = s.ring[(start + i) & (kRing - 1)];
        mean += x[i];
    }
    mean /= N;
    {
        // energy, lag-1 product, zero crossings, low-band energy (two one-pole low-passes at 900 Hz)
        float l1 = 0.0f, l2 = 0.0f, al = 0.2978f;     // 1 - exp(-2 pi 900 / 16000)
        for (int i = 0; i < N; i++) {
            x[i] -= (float)mean;
            e += (double)x[i] * x[i];
            l1 += al * (x[i] - l1);
            l2 += al * (l1 - l2);
            el += (double)l2 * l2;
            if (i > 0) {
                r1 += (double)x[i] * x[i - 1];
                zc += (x[i] < 0.0f) != (x[i - 1] < 0.0f);
            }
        }
    }
    r0 = e;
    e /= N;
    o.db = (float)(10.0 * std::log10(e + 1e-12));
    if (s.p.gate_recent) {
        double eh = 0.0;
        const int h = kHop < N ? kHop : N;
        for (int i = N - h; i < N; i++) {
            eh += (double)x[i] * x[i];
        }
        o.db_recent = (float)(10.0 * std::log10(eh / h + 1e-12));
    } else {
        o.db_recent = o.db;
    }
    o.level = (o.db + 60.0f) / 50.0f;
    o.level = o.level < 0.0f ? 0.0f : (o.level > 1.0f ? 1.0f : o.level);
    o.zcr = (float)zc / (N - 1);

    // noise floor (at once down, 2 dB/s up), the loudest recent frame (at once up, 3 dB/s down), the adaptive gate
    if (s.frames == 0) {
        s.floor_db = o.db;
        s.peak_db = o.db;
    }
    s.frames++;
    if (o.db_recent < s.floor_db) {
        s.floor_db = o.db_recent;
    } else {
        s.floor_db += 0.02f;
    }
    s.peak_db = o.db > s.peak_db ? o.db : s.peak_db - 0.03f;
    if (s.peak_db < s.floor_db) {
        s.peak_db = s.floor_db;
    }
    // the local peak (the syllable's nucleus): up at once, down 40 dB/s
    if (s.frames == 1) {
        s.lpk_db = o.db;
    }
    s.lpk_db = o.db > s.lpk_db ? o.db : s.lpk_db - 0.4f;
    if (s.lpk_db < s.floor_db) {
        s.lpk_db = s.floor_db;
    }
    o.rel_loc = o.db - s.lpk_db;
    gate = s.p.gate_adapt ? 0.4f * (s.peak_db - s.floor_db) : s.p.gate_db;
    if (gate > s.p.gate_db) {
        gate = s.p.gate_db;
    }
    if (gate < s.p.gate_min_db) {
        gate = s.p.gate_min_db;
    }
    speech = o.db_recent > s.floor_db + gate && o.db_recent > s.p.abs_gate_db;
    o.rel_db = o.db - s.peak_db;

    // the LPC input: low-passed and decimated to 8 kHz (and its energy: the share under 3.4 kHz)
    double eband = 0.0;
    for (int i = 0; i < M; i++) {
        float acc = 0.0f;
        const float *src = x + 2 * i;
        for (int k = 0; k < kDecTaps; k++) {
            acc += s.dec_h[k] * src[k];
        }
        y[i] = acc;
        eband += (double)acc * acc;
    }
    // the decimated frame covers the window's middle M x 2 samples
    o.nbr = r0 > 0.0 ? (float)(eband * 2.0 / (r0 * (double)(2 * M) / N)) : 1.0f;
    if (o.nbr > 1.0f) {
        o.nbr = 1.0f;
    }
    {
        // periodicity on a 4 kHz copy (pairs of the 8 kHz frame averaged): lags 10..66 = F0 400..60 Hz
        float z[kDecN / 2];
        const int Z = kDecN / 2;
        double z0 = 0.0, best = 0.0;
        for (int i = 0; i < Z; i++) {
            z[i] = 0.5f * (y[2 * i] + y[2 * i + 1]);
            z0 += (double)z[i] * z[i];
        }
        if (z0 > 0.0) {
            for (int L = 10; L <= 66 && L < Z - 8; L++) {
                double c = 0.0, e1 = 0.0, e2 = 0.0;
                for (int i = 0; i + L < Z; i++) {
                    c += (double)z[i] * z[i + L];
                    e1 += (double)z[i] * z[i];
                    e2 += (double)z[i + L] * z[i + L];
                }
                double v = e1 > 0.0 && e2 > 0.0 ? c / std::sqrt(e1 * e2) : 0.0;
                if (v > best) {
                    best = v;
                }
            }
        }
        o.per = (float)best;
    }
    // pre-emphasis and the Hamming window
    for (int i = M - 1; i > 0; i--) {
        y[i] = (y[i] - 0.94f * y[i - 1]) * s.window[i];
    }
    y[0] *= s.window[0];
    o.r1 = r0 > 0.0 ? (float)(r1 / r0) : 1.0f;
    o.lowr = r0 > 0.0 ? (float)(el / r0) : 1.0f;
    if (o.lowr > 1.0f) {
        o.lowr = 1.0f;
    }
    // a weak fricative (f, th) passes a gate 4 dB lower when its shape is clearly a fricative's
    if (!speech && s.p.fric_gate && o.zcr > 0.3f && o.lowr < 0.12f && (s.p.fe < 2 || o.per < s.p.voiced_per) &&
        o.db_recent > s.floor_db + gate - 4.0f && o.db_recent > s.p.abs_gate_db - 6.0f) {
        speech = 2;
    }
    const int fe2 = s.p.fe >= 2;
    const bool fric = fe2 ? ((o.lowr < 0.25f && o.zcr > 0.3f && o.per < s.p.voiced_per) ||
                             (o.zcr > 0.42f && o.nbr < 0.45f && o.lowr < 0.35f))
                          : (o.lowr < s.p.fric_lowr && o.zcr > s.p.fric_zcr);
    if (speech) {
        for (int k = 0; k <= P; k++) {
            double acc = 0.0;
            for (int i = k; i < M; i++) {
                acc += (double)y[i] * y[i - k];
            }
            r[k] = acc;
        }
    }

    if (!speech) {
        raw = SIL;
    } else {
        for (int k = 0; k <= P; k++) {
            r[k] *= s.lagwin[k];
        }
        r[0] *= 1.0001;
        r[0] += 1e-12;
        err = levinson(r, P, a);
        o.gain_db = err > 0.0 ? (float)(10.0 * std::log10(r[0] / err)) : 0.0f;
        if (fric) {
            // fe 2: hiss above 3.4 kHz (s, z) or a loud one (sh) is a sibilant, else f / v / th
            if (fe2) {
                raw = (o.nbr < 0.12f || o.zcr > 0.64f || o.rel_loc > -12.0f) ? SS : FV;
            } else {
                raw = o.rel_db > s.p.ss_rel_db ? SS : FV;
            }
        } else if (speech == 2) {
            raw = SIL;
        } else {
            if (err > 0.0) {
                formants_roots(s, a, &f1, &f2, &b1, &b2, &o.iters);
            }
            o.f1 = f1;
            o.f2 = f2;
            o.bw1 = b1;
            o.bw2 = b2;
            o.voiced = 1;
            // fe 2: a murmur is a nasal's weak, wide F2 under the nucleus, a weak voiced closure, or very weak voicing
            bool murmur = fe2 ? ((o.lowr > 0.72f && (f2 <= 0.0f || b2 > s.p.murmur_bw2) && o.rel_loc < -4.0f) ||
                                 (o.rel_loc < -16.0f && o.lowr > 0.6f) || o.rel_db < -32.0f)
                              : ((o.lowr > s.p.nasal_lowr && o.rel_db < s.p.nasal_rel_db) || o.rel_db < s.p.weak_rel_db);
            if (murmur) {
                raw = MBP;
            } else if (f1 > 0.0f && f2 > 0.0f) {
                float x1, x2;
                int cat = -1;
                norm_xy(s, f1, f2, &x1, &x2);
                o.x1 = x1;
                o.x2 = x2;
                // a nasal murmur: F1 under the speaker's /i/ F1 with most energy low
                if (s.p.nasal_f1 && o.lowr > s.p.nasal_lowr2 && o.rel_db < -4.0f &&
                    x1 < s.ref_x[kCatI][0] - s.p.nasal_f1_margin / (s.p.norm == 2 ? (float)std::sqrt(s.var0[0]) : 1.0f)) {
                    raw = MBP;
                } else {
                    raw = classify_vowel(s, x1, x2, &conf, &alt, &cat, &o.eep);
                    o.cat = cat;
                    s.last_vowel = raw;
                    // the speaker learns from syllable nuclei with stable roots, never during a warm-up (review R.1)
                    bool nucleus = s.p.learn_loc ? (o.rel_loc > -3.0f && o.rel_db > -25.0f) : o.rel_db > -12.0f;
                    if (s.p.adapt && s.warm_phase < 0 && nucleus && b1 < 300.0f && b2 < 450.0f) {
                        learn(s, f1, f2, cat);
                    }
                }
                // the warm-up's corners count the voiced frames within 14 dB of the slow peak (phase 4, a gap, none)
                if (s.warm_phase >= 0 && s.warm_phase <= 3 && o.rel_db > -14.0f) {
                    s.warm_sum[s.warm_phase][0] += std::log((double)f1);
                    s.warm_sum[s.warm_phase][1] += std::log((double)f2);
                    s.warm_n[s.warm_phase] += 1.0;
                }
            } else if ((fe2 ? o.rel_loc : o.rel_db) < -12.0f) {
                raw = MBP;
            } else {
                raw = s.last_vowel;
                conf = 0.0f;
            }
        }
    }
    // EE needs ee_need raw EE frames in a row; before that the frame counts as its runner-up
    if (raw == EE) {
        s.ee_run++;
        if (s.ee_run < s.p.ee_need && alt >= 0) {
            raw = alt;
        }
    } else {
        s.ee_run = 0;
    }
    o.raw = raw;
    o.conf = conf;

    // smoothing: 1 = 2-of-3 vote; 2 = that, and a vowel-to-vowel change needs 3 frames unless it is confident;
    // 3 = the vote except into / out of silence (at once)
    s.hist[0] = s.hist[1];
    s.hist[1] = s.hist[2];
    s.hist[2] = raw;
    if (!s.p.smooth) {
        s.cur = raw;
    } else if (s.p.smooth == 3 && (raw == SIL || s.cur == SIL)) {
        s.cur = raw;
    } else {
        int cnt = (s.hist[0] == raw) + (s.hist[1] == raw) + 1;
        if (cnt >= 2) {
            int vv = raw >= AA && raw <= OO && s.cur >= AA && s.cur <= OO && raw != s.cur;
            if (s.p.smooth != 2 || !vv || cnt == 3 || conf > 0.35f) {
                s.cur = raw;
            }
        } else if (s.hist[0] == s.hist[1] && s.p.smooth != 2) {
            s.cur = s.hist[1];
        }
    }
    o.cls = s.cur;
}

// the high-pass's coefficients (RBJ biquad, Q 0.5412 and 1.3066: 4th-order Butterworth)
void hp_setup(State &s)
{
    std::memset(s.hp_c, 0, sizeof s.hp_c);
    std::memset(s.hp_m, 0, sizeof s.hp_m);
    s.hp_on = s.p.hp_hz > 0.0f && s.p.hp_hz < 4000.0f;
    if (!s.hp_on) {
        return;
    }
    static const double q[2] = {0.5412, 1.3066};
    for (int k = 0; k < 2; k++) {
        double w = 2.0 * 3.14159265358979 * (double)s.p.hp_hz / kRate, c = std::cos(w), al = std::sin(w) / (2.0 * q[k]);
        s.hp_c[k][0] = (1 + c) / 2;
        s.hp_c[k][1] = -(1 + c);
        s.hp_c[k][2] = (1 + c) / 2;
        s.hp_c[k][3] = 1 + al;
        s.hp_c[k][4] = -2 * c;
        s.hp_c[k][5] = 1 - al;
    }
}

inline float hp_run(State &s, float v)
{
    for (int k = 0; k < 2; k++) {
        const double *c = s.hp_c[k];
        double *m = s.hp_m[k];    // x1 x2 y1 y2
        double yv = (c[0] * v + c[1] * m[0] + c[2] * m[1] - c[4] * m[2] - c[5] * m[3]) / c[3];
        m[1] = m[0];
        m[0] = v;
        m[3] = m[2];
        m[2] = yv;
        v = (float)yv;
    }
    return v;
}

// the reference statistics per group (prior-weighted mean and spread of ln F1 / ln F2 over the categories, plus a
// within-category 0.10 / 0.08) and their total prior
void group_stats(double mu[3][2], double var[3][2], double *tot_out)
{
    double tot = 0.0;
    const double within[2] = {0.10, 0.08};
    for (int c = 0; c < kCats; c++) {
        tot += kCat[c].prior;
    }
    for (int g = 0; g < 3; g++) {
        for (int k = 0; k < 2; k++) {
            double m = 0.0, v = 0.0;
            for (int c = 0; c < kCats; c++) {
                m += kCat[c].prior / tot * std::log((double)kCat[c].f[g][k]);
            }
            for (int c = 0; c < kCats; c++) {
                double d = std::log((double)kCat[c].f[g][k]) - m;
                v += kCat[c].prior / tot * d * d;
            }
            mu[g][k] = m;
            var[g][k] = v + within[k] * within[k];
        }
    }
    *tot_out = tot;
}

// the speaker's prior (between the men's and the women's statistics) and the normalised categories
void ref_setup(State &s)
{
    double mu[3][2], var[3][2], tot = 0.0;
    group_stats(mu, var, &tot);
    s.prior_tot = tot;
    for (int k = 0; k < 2; k++) {
        s.mu0[k] = 0.5 * (mu[0][k] + mu[1][k]);
        s.var0[k] = 0.5 * (var[0][k] + var[1][k]);
    }
    for (int c = 0; c < kCats; c++) {
        for (int k = 0; k < 2; k++) {
            double acc = 0.0, sd = 0.0;
            for (int g = 0; g < 3; g++) {
                double d = std::log((double)kCat[c].f[g][k]) - mu[g][k];
                acc += s.p.norm == 2 ? d / std::sqrt(var[g][k]) : d;
                sd += std::sqrt(var[g][k]) / 3.0;
            }
            s.ref_x[c][k] = (float)(acc / 3.0);
            double sp = k == 0 ? kCat[c].s1 : kCat[c].s2;
            if (k == 0 && (c == kCatI || c == kCatU)) {
                sp = s.p.close_s1;
            }
            s.ref_s[c][k] = (float)(sp / (s.p.norm == 2 ? sd : 1.0));
        }
        s.ref_lp[c] = (float)(s.p.prior_alpha * std::log(kCat[c].prior / tot));
    }
}

void clamp_params(Params &p)
{
    if (p.order < 2) p.order = 2;
    if (p.order > kMaxOrder) p.order = kMaxOrder;
    if (p.smooth < 0 || p.smooth > 3) p.smooth = 3;
    if (p.norm < 1 || p.norm > 2) p.norm = 1;
    if (p.ee_need < 1) p.ee_need = 1;
    if (!(p.hp_hz >= 0.0f)) p.hp_hz = 0.0f;
    if (!(p.cat_cap >= 0.0f)) p.cat_cap = 0.0f;
}

}  // namespace

void default_params(Params &p)
{
    p = Params();
}

const char *cat_name(int c)
{
    return c >= 0 && c < kCats ? kCat[c].name : "?";
}

int cat_class(int c)
{
    return cat_class_of(c, 0);
}

float prior_g()
{
    double mu[3][2], var[3][2], tot = 0.0;
    group_stats(mu, var, &tot);
    double m1 = 0.5 * (mu[0][0] + mu[1][0]), m2 = 0.5 * (mu[0][1] + mu[1][1]);
    return (float)(0.5 * (m1 + m2));
}

float voice_g(const State &s)
{
    return (float)(0.5 * (s.mu[0] + s.mu[1]));
}

void init(State &s, const Params &p)
{
    std::memset(&s, 0, sizeof s);
    s.p = p;
    clamp_params(s.p);
    {
        // the decimation low-pass: windowed sinc (Blackman), cut-off 3.4 kHz at 16 kHz, unity DC gain
        double sum = 0.0, fc = 3400.0 / kRate, m = (kDecTaps - 1) / 2.0;
        for (int i = 0; i < kDecTaps; i++) {
            double t = i - m, h = t == 0.0 ? 2.0 * fc : std::sin(2.0 * kPi * fc * t) / (kPi * t);
            h *= 0.42 - 0.5 * std::cos(2.0 * kPi * i / (kDecTaps - 1)) + 0.08 * std::cos(4.0 * kPi * i / (kDecTaps - 1));
            s.dec_h[i] = (float)h;
            sum += h;
        }
        for (int i = 0; i < kDecTaps; i++) {
            s.dec_h[i] = (float)(s.dec_h[i] / sum);
        }
    }
    for (int i = 0; i < kDecN; i++) {
        s.window[i] = (float)(0.54 - 0.46 * std::cos(2.0 * kPi * i / (kDecN - 1)));
    }
    // a Gaussian lag window (about 50 Hz of bandwidth expansion): keeps a high voice's harmonics out of the formants
    for (int k = 0; k <= s.p.order; k++) {
        double xx = 2.0 * kPi * 50.0 * k / (kRate / 2);
        s.lagwin[k] = (float)std::exp(-0.5 * xx * xx);
    }
    ref_setup(s);
    reset_voice(s);
    s.cur = SIL;
    s.last_vowel = EH;
    s.hist[0] = s.hist[1] = s.hist[2] = SIL;
    s.warm_phase = -1;
    hp_setup(s);
}

int feed(State &s, const float *x, int n, Frame *out, int max)
{
    int made = 0;
    if (!x || n <= 0) {
        return 0;
    }
    if (max < 0) {
        max = 0;
    }
    for (int i = 0; i < n; i++) {
        float v = x[i];
        if (!std::isfinite(v)) {
            v = 0.0f;
        }
        if (s.hp_on) {
            v = hp_run(s, v);
        }
        s.ring[s.pos] = v;
        s.pos = (s.pos + 1) & (kRing - 1);
        if (s.fill < kRing) {
            s.fill++;
        }
        if (++s.since >= kHop && s.fill >= kWin) {
            s.since = 0;
            // every hop is analysed (the trackers, the vote and the warm start see every frame); out keeps the newest
            Frame f;
            analyse(s, f);
            if (max > 0) {
                if (made >= max) {
                    for (int k = 1; k < max; k++) {
                        out[k - 1] = out[k];
                    }
                    out[max - 1] = f;
                } else {
                    out[made] = f;
                }
            }
            made++;
        }
    }
    return made;
}

void reset_press(State &s)
{
    std::memset(s.ring, 0, sizeof s.ring);
    s.fill = kWin;          // the window counts as silence: the first analysis comes one hop after the press
    s.since = 0;
    std::memset(s.hp_m, 0, sizeof s.hp_m);
    s.hist[0] = s.hist[1] = s.hist[2] = SIL;
    s.cur = SIL;
    s.ee_run = 0;
}

void reset_voice(State &s)
{
    for (int k = 0; k < 2; k++) {
        s.mu[k] = s.mu0[k];
        s.var[k] = s.var0[k];
    }
    s.wn = s.p.n0;
    s.voice_frames = 0;
    std::memset(s.shift, 0, sizeof s.shift);
    std::memset(s.cat_h, 0, sizeof s.cat_h);
    s.cat_H = 0.0f;
    s.warmed = 0;
    s.warm_phase = -1;
    std::memset(s.warm_sum, 0, sizeof s.warm_sum);
    std::memset(s.warm_n, 0, sizeof s.warm_n);
}

void reinit_keep_voice(State &s, const Params &p)
{
    double mu[2] = {s.mu[0], s.mu[1]}, var[2] = {s.var[0], s.var[1]}, wn = s.wn, ws[4][2], wcnt[4];
    uint32_t vf = s.voice_frames;
    float ch[kCats], cH = s.cat_H, sh[kCats][2];
    int warmed = s.warmed, phase = s.warm_phase;
    std::memcpy(ch, s.cat_h, sizeof ch);
    std::memcpy(sh, s.shift, sizeof sh);
    std::memcpy(ws, s.warm_sum, sizeof ws);
    std::memcpy(wcnt, s.warm_n, sizeof wcnt);
    init(s, p);
    for (int k = 0; k < 2; k++) {
        s.mu[k] = mu[k];
        s.var[k] = var[k];
    }
    s.wn = wn;
    s.voice_frames = vf;
    std::memcpy(s.cat_h, ch, sizeof ch);
    s.cat_H = cH;
    std::memcpy(s.shift, sh, sizeof sh);
    s.warmed = warmed;
    s.warm_phase = phase;
    std::memcpy(s.warm_sum, ws, sizeof ws);
    std::memcpy(s.warm_n, wcnt, sizeof wcnt);
}

void warm_begin(State &s, int corner)
{
    if (corner < 0 || corner > 4) {
        s.warm_phase = -1;
        return;
    }
    if (corner == 0) {
        std::memset(s.warm_n, 0, sizeof s.warm_n);
        std::memset(s.warm_sum, 0, sizeof s.warm_sum);
    }
    s.warm_phase = corner;
}

int warm_end(State &s, float n0w)
{
    s.warm_phase = -1;
    static const int corner_cat[4] = {kCatA, kCatI, kCatU, kCatOo};
    int nc = s.warm_n[3] >= 20.0 ? 4 : 3;     // "oh" is optional
    for (int c = 0; c < 3; c++) {
        if (s.warm_n[c] < 20.0) {
            return 2;
        }
    }
    double m[4][2], r[4][2];
    for (int c = 0; c < nc; c++) {
        for (int k = 0; k < 2; k++) {
            m[c][k] = s.warm_sum[c][k] / s.warm_n[c];
            r[c][k] = s.ref_x[corner_cat[c]][k];
        }
    }
    // review R.5: the corners must be where an ah, an ee and an oo can be (ln units), else nothing changes
    if (m[1][1] - m[0][1] < 0.15 || m[1][1] - m[2][1] < 0.05 || m[0][0] - m[1][0] < 0.25 || m[0][0] - m[2][0] < 0.20) {
        return 4;
    }
    for (int k = 0; k < 2; k++) {
        // the means (and spreads) from the three main corners: m = mu + sd * r
        double mm = 0.0, rm = 0.0, cov = 0.0, vr = 0.0;
        for (int c = 0; c < 3; c++) {
            mm += m[c][k] / 3.0;
            rm += r[c][k] / 3.0;
        }
        if (s.p.norm == 2) {
            for (int c = 0; c < 3; c++) {
                cov += (m[c][k] - mm) * (r[c][k] - rm);
                vr += (r[c][k] - rm) * (r[c][k] - rm);
            }
            double sd = vr > 0.0 ? cov / vr : std::sqrt(s.var0[k]), sd0 = std::sqrt(s.var0[k]);
            if (!(sd > 0.5 * sd0 && sd < 2.0 * sd0)) {
                sd = sd0;
            }
            s.mu[k] = mm - sd * rm;
            s.var[k] = sd * sd;
        } else {
            s.mu[k] = mm - rm;
        }
    }
    std::memset(s.shift, 0, sizeof s.shift);
    if (s.p.anchor) {
        // where this speaker's corners land in the normalised space, against the references: each category moves by the
        // inverse-distance weighted shift of the corners (a corner's own category moves by its whole shift)
        double d[4][2];
        for (int c = 0; c < nc; c++) {
            for (int k = 0; k < 2; k++) {
                double x = s.p.norm == 2 ? (m[c][k] - s.mu[k]) / std::sqrt(s.var[k]) : m[c][k] - s.mu[k];
                d[c][k] = x - r[c][k];
            }
        }
        for (int q = 0; q < kCats; q++) {
            double wsum = 0.0, sx = 0.0, sy = 0.0;
            int own = -1;
            for (int c = 0; c < nc; c++) {
                if (corner_cat[c] == q) {
                    own = c;
                }
            }
            if (own >= 0) {
                s.shift[q][0] = (float)d[own][0];
                s.shift[q][1] = (float)d[own][1];
                continue;
            }
            for (int c = 0; c < nc; c++) {
                double e1 = s.ref_x[q][0] - r[c][0], e2 = s.ref_x[q][1] - r[c][1];
                double w = 1.0 / (e1 * e1 + e2 * e2 + 1e-3);
                wsum += w;
                sx += w * d[c][0];
                sy += w * d[c][1];
            }
            s.shift[q][0] = (float)(s.p.anchor_spread * sx / wsum);
            s.shift[q][1] = (float)(s.p.anchor_spread * sy / wsum);
        }
    }
    s.wn = n0w;
    s.voice_frames = 0;
    s.warmed = 1;
    return 1;
}

void warm_cancel(State &s)
{
    s.warm_phase = -1;
    std::memset(s.warm_n, 0, sizeof s.warm_n);
    std::memset(s.warm_sum, 0, sizeof s.warm_sum);
}

const char *name(int cls)
{
    static const char *const n[COUNT] = {"SIL", "MBP", "AA", "EH", "EE", "OH", "OO", "SS", "FV"};
    return cls >= 0 && cls < COUNT ? n[cls] : "?";
}

const char *word(int cls)
{
    static const char *const n[COUNT] = {"silence", "m b p", "ah", "eh", "ee", "oh", "oo", "s z sh", "f v th"};
    return cls >= 0 && cls < COUNT ? n[cls] : "?";
}

}  // namespace viseme
}  // namespace gsa1
