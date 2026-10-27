// G-SA1 core: the live sound classifier (see viseme.hpp). A port of the research prototype vis.c (our own code; method
// 0); the arithmetic is kept in vis.c's order and types so that, with hp_hz 0, every frame equals the prototype's
// (tests/feat_viseme_test.cpp checks it on the synthetic corpus).
#include "viseme_v1.hpp"

#include <cmath>
#include <cstring>

namespace gsa1 {
namespace viseme_v1 {

namespace {

const double kPi = 3.14159265358979323846;

// The classifier's vowel references: average F1 / F2 of ten American English vowels, Peterson & Barney (1952), men /
// women / children (published measurements, as commonly tabulated; numbers typed from memory, UNVERIFIED to the hertz -
// the speaker adaptation absorbs a uniform scale). Each group is normalised by its own log-mean (Nearey 1978); the three
// normalised groups are averaged. Not game data.
struct Ref {
    int cls;
    float f[3][2];
};
const Ref kRef[kRefs] = {
    /*        men            women          children */
    {EE, {{270, 2290}, {310, 2790}, {370, 3200}}},     // i
    {EE, {{390, 1990}, {430, 2480}, {530, 2730}}},     // I
    {EH, {{530, 1840}, {610, 2330}, {690, 2610}}},     // E
    {AA, {{660, 1720}, {860, 2050}, {1010, 2320}}},    // ae
    {AA, {{730, 1090}, {850, 1220}, {1030, 1370}}},    // A
    {OH, {{570, 840}, {590, 920}, {680, 1060}}},       // O
    {OO, {{440, 1020}, {470, 1160}, {560, 1410}}},     // U
    {OO, {{300, 870}, {370, 950}, {430, 1170}}},       // u
    {AA, {{640, 1190}, {760, 1400}, {850, 1590}}},     // V
    {EH, {{490, 1350}, {500, 1640}, {560, 1820}}},     // 3r
};

// the normalised references and the three groups' log-means (vis.c ref_init, the same arithmetic)
void refs(float ref_n[kRefs][2], float group_g[3])
{
    std::memset(ref_n, 0, sizeof(float) * kRefs * 2);
    for (int g = 0; g < 3; g++) {
        double m = 0;
        for (int v = 0; v < kRefs; v++) {
            m += 0.5 * (std::log((double)kRef[v].f[g][0]) + std::log((double)kRef[v].f[g][1]));
        }
        m /= kRefs;
        group_g[g] = (float)m;
        for (int v = 0; v < kRefs; v++) {
            ref_n[v][0] += (float)((std::log((double)kRef[v].f[g][0]) - m) / 3.0);
            ref_n[v][1] += (float)((std::log((double)kRef[v].f[g][1]) - m) / 3.0);
        }
    }
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

// F1 / F2 from candidate (frequency, bandwidth) pairs sorted by frequency
void pick_f1f2(const float *f, const float *bw, int n, float *f1, float *f2)
{
    int i1 = -1;
    *f1 = *f2 = 0.0f;
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
    for (int i = i1 + 1; i < n; i++) {
        if (f[i] > f[i1] + 150.0f && f[i] >= 550.0f && f[i] <= 3500.0f && bw[i] < 600.0f) {
            *f2 = f[i];
            return;
        }
    }
}

void formants_roots(State &s, const double *a, float *f1, float *f2, int *iters)
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
        *f1 = *f2 = 0.0f;
        return;
    }
    for (int i = 0; i < p; i++) {
        double r = std::sqrt(s.rre[i] * s.rre[i] + s.rim[i] * s.rim[i]);
        double fr, b;
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
    pick_f1f2(f, bw, n, f1, f2);
}

int classify_vowel(const State &s, float f1, float f2, float *conf)
{
    float n1 = std::log(f1) - s.g, n2 = std::log(f2) - s.g, best = 1e9f, second = 1e9f;
    int bestv = 0;
    for (int v = 0; v < kRefs; v++) {
        float d1 = n1 - s.ref_n[v][0], d2 = n2 - s.ref_n[v][1], d = d1 * d1 + d2 * d2;
        if (d < best) {
            second = best;
            best = d;
            bestv = v;
        } else if (d < second) {
            second = d;
        }
    }
    int cls = kRef[bestv].cls;
    second = 1e9f;    // the margin to the nearest reference of ANOTHER class
    for (int v = 0; v < kRefs; v++) {
        if (kRef[v].cls == cls) {
            continue;
        }
        float d1 = n1 - s.ref_n[v][0], d2 = n2 - s.ref_n[v][1], d = d1 * d1 + d2 * d2;
        if (d < second) {
            second = d;
        }
    }
    *conf = second > 0.0f ? 1.0f - std::sqrt(best / second) : 0.0f;
    return cls;
}

// one analysis of the newest kWin samples (vis.c analyse, method 0, decimated, no noise subtraction)
void analyse(State &s, Frame &o)
{
    const int N = kWin, P = s.p.order, M = kDecN;
    float x[kWin], y[kDecN];
    double r[kMaxOrder + 1], a[kMaxOrder + 1], err, e = 0.0, r0 = 0.0, r1 = 0.0, el = 0.0, mean = 0.0;
    int zc = 0, start = s.pos - N, speech, raw;
    float f1 = 0.0f, f2 = 0.0f, conf = 1.0f, gate;

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
    gate = s.p.gate_adapt ? 0.4f * (s.peak_db - s.floor_db) : s.p.gate_db;
    if (gate > s.p.gate_db) {
        gate = s.p.gate_db;
    }
    if (gate < s.p.gate_min_db) {
        gate = s.p.gate_min_db;
    }
    speech = o.db_recent > s.floor_db + gate && o.db_recent > s.p.abs_gate_db;
    o.rel_db = o.db - s.peak_db;
    o.g = s.g;

    // the LPC input: low-passed and decimated to 8 kHz; pre-emphasis; Hamming window
    for (int i = 0; i < M; i++) {
        float acc = 0.0f;
        const float *src = x + 2 * i;
        for (int k = 0; k < kDecTaps; k++) {
            acc += s.dec_h[k] * src[k];
        }
        y[i] = acc;
    }
    for (int i = M - 1; i > 0; i--) {
        y[i] = (y[i] - 0.94f * y[i - 1]) * s.window[i];
    }
    y[0] *= s.window[0];
    if (speech) {
        for (int k = 0; k <= P; k++) {
            double acc = 0.0;
            for (int i = k; i < M; i++) {
                acc += (double)y[i] * y[i - k];
            }
            r[k] = acc;
        }
    }
    o.r1 = r0 > 0.0 ? (float)(r1 / r0) : 1.0f;
    o.lowr = r0 > 0.0 ? (float)(el / r0) : 1.0f;
    if (o.lowr > 1.0f) {
        o.lowr = 1.0f;
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
        if (o.lowr < s.p.fric_lowr && o.zcr > s.p.fric_zcr) {
            // a fricative: little energy under 1 kHz; strong = a sibilant, weak = f / v / th
            raw = o.rel_db > s.p.ss_rel_db ? SS : FV;
        } else {
            if (err > 0.0) {
                formants_roots(s, a, &f1, &f2, &o.iters);
            }
            o.f1 = f1;
            o.f2 = f2;
            o.voiced = 1;
            if ((o.lowr > s.p.nasal_lowr && o.rel_db < s.p.nasal_rel_db) || o.rel_db < s.p.weak_rel_db) {
                raw = MBP;    // a murmur (m n ng) or weak voicing (voice bars, v / dh)
            } else if (f1 > 0.0f && f2 > 0.0f) {
                raw = classify_vowel(s, f1, f2, &conf);
                s.last_vowel = raw;
                if (s.p.adapt == 1 && o.rel_db > -14.0f) {
                    float gv = 0.5f * (std::log(f1) + std::log(f2));
                    s.g += s.p.adapt_rate * (gv - s.g);
                    s.voice_frames++;
                }
            } else if (o.rel_db < -12.0f) {
                raw = MBP;
            } else {
                raw = s.last_vowel;
                conf = 0.0f;
            }
        }
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

// the high-pass's coefficients (RBJ biquad, Q 0.5412 and 1.3066: 4th-order Butterworth), the review's arithmetic
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
        double y = (c[0] * v + c[1] * m[0] + c[2] * m[1] - c[4] * m[2] - c[5] * m[3]) / c[3];
        m[1] = m[0];
        m[0] = v;
        m[3] = m[2];
        m[2] = y;
        v = (float)y;
    }
    return v;
}

void clamp_params(Params &p)
{
    if (p.order < 2) p.order = 2;
    if (p.order > kMaxOrder) p.order = kMaxOrder;
    if (p.smooth < 0 || p.smooth > 3) p.smooth = 3;
    if (!(p.hp_hz >= 0.0f)) p.hp_hz = 0.0f;
}

}  // namespace

void default_params(Params &p)
{
    p = Params();
}

float prior_g()
{
    float ref_n[kRefs][2], group_g[3];
    refs(ref_n, group_g);
    return 0.5f * (group_g[0] + group_g[1]);    // adults: between men and women
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
        double x = 2.0 * kPi * 50.0 * k / (kRate / 2);
        s.lagwin[k] = (float)std::exp(-0.5 * x * x);
    }
    float group_g[3];
    refs(s.ref_n, group_g);
    s.prior_g = 0.5f * (group_g[0] + group_g[1]);
    s.g = s.p.adapt == 2 ? s.p.norm_g : s.prior_g;
    s.voice_frames = 0;
    s.cur = SIL;
    s.last_vowel = EH;
    s.hist[0] = s.hist[1] = s.hist[2] = SIL;
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
}

void reset_voice(State &s)
{
    s.g = s.p.adapt == 2 ? s.p.norm_g : s.prior_g;
    s.voice_frames = 0;
}

void reinit_keep_voice(State &s, const Params &p)
{
    float g = s.g;
    uint32_t vf = s.voice_frames;
    init(s, p);
    if (s.p.adapt != 2) {
        s.g = g;
        s.voice_frames = vf;
    }
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

}  // namespace viseme_v1
}  // namespace gsa1
