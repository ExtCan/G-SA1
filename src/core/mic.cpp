// G-SA1 core: the microphone's loudness for lip sync (see mic.hpp).
#include "mic.hpp"

#include <atomic>
#include <cmath>
#include <cstring>
#include <functional>
#include <mutex>
#include <thread>

#include "util.hpp"
#include "viseme.hpp"
#include "viseme_v1.hpp"

#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <xmmintrin.h>
#define GSA1_MIC_MXCSR 1
#endif

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace gsa1 {
namespace mic {

namespace {

// the state the RECORDPROC touches: atomics only
std::atomic<float> g_level{0.0f}, g_peak{0.0f};
std::atomic<uint64_t> g_blocks{0};
std::atomic<bool> g_listening{false};

// ---- 0.9.4c: the sound classifier (phoneme_plan.md 4.2 step 2, review R.8 / R.9); 0.9.4e: two engines, the warm-up ----
// Lua thread -> RECORDPROC: atomics only, applied at the start of the RECORDPROC's next block
std::atomic<bool> g_vis_on{false};
std::atomic<uint32_t> g_epoch{0};             // +1 per press (listen(true)) and per analysis start (viseme_on(true))
const uint32_t kPendReinit = 1u;              // another device / a forced re-open: start again, keep the voice
const uint32_t kPendForget = 2u;              // the session ended (close): start again, forget the voice (both engines)
const uint32_t kPendResetVoice = 4u;          // "reset_voice" (both engines)
std::atomic<uint32_t> g_pending{0};
std::atomic<float> g_tune_gate{6.0f};
std::atomic<int> g_tune_adapt{1}, g_tune_smooth{3};
// 0.9.4e: the engine (1 = 0.9.4c's classifier, 2 = lipsync2's); the one the RECORDPROC last applied (0: none yet)
std::atomic<int> g_tune_engine{2}, g_engine_applied{0};
// 0.9.4e: the warm-up's pending step (-1 none; the newest step wins)
std::atomic<int> g_warm_step{-1};
// RECORDPROC -> Lua: the newest frame (atomic 1), its features (atomic 2, features_pack's layout; "none" = cat / raw 15),
// the voice summary and the warm-up's state (one atomic each; voice_pack / warm_pack below)
const uint32_t kClsNone = 15u;
std::atomic<uint64_t> g_frame{(uint64_t)kClsNone << 16};   // "none" (viseme_pack's layout)
const uint64_t kFeaturesNone = ((uint64_t)15u << 45) | ((uint64_t)15u << 49);
std::atomic<uint64_t> g_features{kFeaturesNone};
std::atomic<uint64_t> g_voice{0};             // frames 0, not warmed: the prior
std::atomic<uint64_t> g_warm{0};              // phase -1, nothing counted, no result
// the RECORDPROC's own: never touched on another thread (review R.9)
viseme::State g_vs;                           // engine 2
viseme_v1::State g_vs1;                       // engine 1 (0.9.4c's)
bool g_vs_ready = false;
int g_vs_engine = 0;                          // the engine fed last (0: none since the forget)
uint32_t g_vs_epoch = 0;
uint32_t g_vs_seq = 0;
int g_vs_adapt = 1;
int g_warm_result = 0;                        // the warm-up's last result (WarmState::result)
// tests: entries into the State, overlapping entries, entries on the marked thread
std::atomic<int> g_dbg_inside{0};
std::atomic<uint64_t> g_dbg_entries{0}, g_dbg_overlaps{0}, g_dbg_marked{0};
std::atomic<size_t> g_dbg_mark{0};

size_t thread_hash()
{
    return std::hash<std::thread::id>()(std::this_thread::get_id()) | 1u;
}

struct StateEntry {
    StateEntry()
    {
        if (g_dbg_inside.fetch_add(1, std::memory_order_acq_rel) != 0) {
            g_dbg_overlaps.fetch_add(1, std::memory_order_relaxed);
        }
        g_dbg_entries.fetch_add(1, std::memory_order_relaxed);
        size_t m = g_dbg_mark.load(std::memory_order_relaxed);
        if (m != 0 && m == thread_hash()) {
            g_dbg_marked.fetch_add(1, std::memory_order_relaxed);
        }
    }
    ~StateEntry() { g_dbg_inside.fetch_sub(1, std::memory_order_acq_rel); }
};

// flush-to-zero and denormals-are-zero for the analysis (decaying signals make denormal floats in the FIR and the LPC:
// p99 about 100 microseconds without), MXCSR restored on every path (the thread is BASS's)
struct FtzScope {
#if defined(GSA1_MIC_MXCSR)
    unsigned int csr;
    FtzScope() : csr(_mm_getcsr()) { _mm_setcsr(csr | 0x8040u); }
    ~FtzScope() { _mm_setcsr(csr); }
#endif
};

// the whole RECORDPROC leaves MXCSR exactly as it found it - the control bits and the sticky exception flags its own
// arithmetic sets (the loudness and the classifier's maths) - on every path (feat_viseme_test V5)
struct MxcsrKeep {
#if defined(GSA1_MIC_MXCSR)
    unsigned int csr;
    MxcsrKeep() : csr(_mm_getcsr()) {}
    ~MxcsrKeep() { _mm_setcsr(csr); }
#endif
};

// the speaker number before any learning: engine 2's (the default) or 0.9.4c's
float g_prior(int engine)
{
    static const float p2 = viseme::prior_g(), p1 = viseme_v1::prior_g();
    return engine == ENGINE_V1 ? p1 : p2;
}

uint32_t qround(float v, float scale, uint32_t max)
{
    if (!(v > 0.0f)) {
        return 0u;
    }
    float q = v * scale + 0.5f;
    return q >= (float)max ? max : (uint32_t)q;
}

// the voice summary (one atomic): bits 0-15 g ((g - 4) x 10000, 1e-4 steps, clamped), 16-35 the frames learned from
// (saturating), 36-45 F1 / 4 Hz, 46-56 F2 / 4 Hz (0 = none), 57 warmed, 58-59 the engine that published it
uint64_t voice_pack(float g, uint32_t frames, float f1, float f2, bool warmed, int engine)
{
    float gq = (g - 4.0f) * 10000.0f + 0.5f;
    uint64_t g16 = !(gq > 0.0f) ? 0u : (gq >= 65535.0f ? 65535u : (uint64_t)gq);
    uint64_t fr = frames > 0xFFFFFu ? 0xFFFFFu : frames;
    return g16 | (fr << 16) | ((uint64_t)qround(f1, 0.25f, 1023u) << 36) | ((uint64_t)qround(f2, 0.25f, 2047u) << 46) |
           ((uint64_t)(warmed ? 1u : 0u) << 57) | ((uint64_t)(engine & 3) << 58);
}

void voice_unpack(uint64_t v, float &g, uint32_t &frames, float &f1, float &f2, bool &warmed, int &engine)
{
    g = 4.0f + (float)(v & 0xFFFFu) / 10000.0f;
    frames = (uint32_t)((v >> 16) & 0xFFFFFu);
    f1 = (float)((v >> 36) & 0x3FFu) * 4.0f;
    f2 = (float)((v >> 46) & 0x7FFu) * 4.0f;
    warmed = ((v >> 57) & 1u) != 0u;
    engine = (int)((v >> 58) & 3u);
}

void publish_none_voice()
{
    int e = g_tune_engine.load(std::memory_order_relaxed);
    g_voice.store(voice_pack(g_prior(e), 0u, 0.0f, 0.0f, false, e), std::memory_order_release);
}

// the warm-up's state (one atomic): bits 0-2 phase + 1 (0 = none, 1-4 the corners, 5 a gap), 3-34 the four corners'
// frames (8 bits each, saturating), 35-37 the result
uint64_t warm_pack(int phase, const double n[4], int result)
{
    uint64_t v = (uint64_t)(phase < -1 || phase > 4 ? 0 : phase + 1);
    for (int c = 0; c < 4; c++) {
        double k = n[c];
        uint64_t q = !(k > 0.0) ? 0u : (k >= 255.0 ? 255u : (uint64_t)k);
        v |= q << (3 + 8 * c);
    }
    return v | ((uint64_t)(result < 0 || result > 7 ? 0 : result) << 35);
}

void publish_none_warm()
{
    const double zero[4] = {0, 0, 0, 0};
    g_warm.store(warm_pack(-1, zero, 0), std::memory_order_release);
}

// one block through the chosen classifier (the RECORDPROC, while listening with the analysis on)
void analyse_block(const float *x, uint32_t n)
{
    StateEntry entry;
    uint32_t pend = g_pending.exchange(0u, std::memory_order_acq_rel);
    int step = g_warm_step.exchange(-1, std::memory_order_acq_rel);
    const int eng = g_tune_engine.load(std::memory_order_relaxed) == ENGINE_V1 ? ENGINE_V1 : ENGINE_V2;
    const float gate = g_tune_gate.load(std::memory_order_relaxed);
    const int adapt = g_tune_adapt.load(std::memory_order_relaxed), smooth = g_tune_smooth.load(std::memory_order_relaxed);
    viseme::Params p2;
    viseme::default_params(p2);
    p2.gate_min_db = gate;
    p2.adapt = adapt;
    p2.smooth = smooth;
    viseme_v1::Params p1;
    viseme_v1::default_params(p1);
    p1.gate_min_db = gate;
    p1.adapt = adapt;
    p1.smooth = smooth;
    if (!g_vs_ready || (pend & kPendForget)) {
        // a new session: both engines from scratch (their voices and the warm-up forgotten)
        viseme::init(g_vs, p2);
        viseme_v1::init(g_vs1, p1);
        g_vs_ready = true;
        g_vs_adapt = adapt;
        g_vs_engine = eng;
        g_vs_seq = 0u;            // close() published "none" with seq 0: a new session counts from there
        g_warm_result = 0;          // (close() dropped any step sent before it; a step sent since applies below)
    } else if ((pend & kPendReinit) || eng != g_vs_engine) {
        // another device, a forced re-open or the other engine chosen: the chosen engine starts again keeping its own
        // voice (the other one keeps what it learned, unfed)
        if (eng == ENGINE_V2) {
            viseme::reinit_keep_voice(g_vs, p2);
        } else {
            viseme_v1::reinit_keep_voice(g_vs1, p1);
        }
        g_vs_engine = eng;
    }
    if (pend & kPendResetVoice) {
        viseme::reset_voice(g_vs);
        viseme_v1::reset_voice(g_vs1);
        g_warm_result = 0;
    }
    uint32_t ep = g_epoch.load(std::memory_order_acquire);
    if (ep != g_vs_epoch) {
        if (eng == ENGINE_V2) {
            viseme::reset_press(g_vs);
        } else {
            viseme_v1::reset_press(g_vs1);
        }
        g_vs_epoch = ep;
    }
    // the tunes (applied at the start of this block)
    g_vs.p.gate_min_db = gate;
    g_vs.p.smooth = smooth;
    g_vs1.p.gate_min_db = gate;
    g_vs1.p.smooth = smooth;
    if (adapt != g_vs_adapt) {
        g_vs.p.adapt = adapt;
        g_vs1.p.adapt = adapt;
        g_vs_adapt = adapt;
        if (adapt == 0) {
            viseme::reset_voice(g_vs);     // "learn my voice" off: the adult prior again (the warm-up's work too)
            viseme_v1::reset_voice(g_vs1);
            g_warm_result = 0;
        }
    }
    // the warm-up's step (engine 2's State; lipsync2_plan.md 4.4)
    if (step >= WARM_AH && step <= WARM_CANCEL) {
        if (step <= WARM_GAP && g_vs.warm_phase < 0) {
            g_warm_result = 0;            // a new warm-up begins: the last result is gone
        }
        if (step <= WARM_OH) {
            viseme::warm_begin(g_vs, step);
        } else if (step == WARM_GAP) {
            viseme::warm_begin(g_vs, 4);
        } else if (step == WARM_DONE) {
            g_warm_result = viseme::warm_end(g_vs, 800.0f);
        } else {
            viseme::warm_cancel(g_vs);
            g_warm_result = 3;
        }
    }
    g_engine_applied.store(eng, std::memory_order_relaxed);
    const int cnt = (int)(n > 0x7FFFFFFFu ? 0x7FFFFFFFu : n);
    if (eng == ENGINE_V2) {
        viseme::Frame f;
        int made;
        {
            FtzScope ftz;
            made = viseme::feed(g_vs, x, cnt, &f, 1);
        }
        if (made > 0) {
            g_vs_seq = (g_vs_seq + 1u) & 0xFFFFu;
            VisemeFeatures ft;
            ft.rel_loc = f.rel_loc;
            ft.per = f.per;
            ft.nbr = f.nbr;
            ft.eep = f.eep;
            ft.cat = f.cat;
            ft.raw = f.raw;
            ft.seq = g_vs_seq;
            ft.lowr = f.lowr;
            ft.zcr = f.zcr;
            // atomic 2 first: a reader that sees atomic 1's seq finds atomic 2 at that seq or later (it compares them)
            g_features.store(features_pack(ft), std::memory_order_release);
            g_frame.store(viseme_pack(f.cls, f.level, f.f1, f.f2, f.conf, g_vs_seq, ep), std::memory_order_release);
        }
        float f1 = 0.0f, f2 = 0.0f;
        if (g_vs.voice_frames > 0u || g_vs.warmed) {
            f1 = (float)std::exp(g_vs.mu[0]);
            f2 = (float)std::exp(g_vs.mu[1]);
        }
        g_voice.store(voice_pack(viseme::voice_g(g_vs), g_vs.voice_frames, f1, f2, g_vs.warmed != 0, ENGINE_V2),
                      std::memory_order_release);
    } else {
        viseme_v1::Frame f;
        int made;
        {
            FtzScope ftz;
            made = viseme_v1::feed(g_vs1, x, cnt, &f, 1);
        }
        if (made > 0) {
            g_vs_seq = (g_vs_seq + 1u) & 0xFFFFu;
            VisemeFeatures ft;          // 0.9.4c's classifier has no local level, periodicity, band share or posterior
            ft.raw = f.raw;
            ft.seq = g_vs_seq;
            ft.lowr = f.lowr;
            ft.zcr = f.zcr;
            g_features.store(features_pack(ft), std::memory_order_release);
            g_frame.store(viseme_pack(f.cls, f.level, f.f1, f.f2, f.conf, g_vs_seq, ep), std::memory_order_release);
        }
        g_voice.store(voice_pack(g_vs1.g, g_vs1.voice_frames, 0.0f, 0.0f, false, ENGINE_V1), std::memory_order_release);
    }
    g_warm.store(warm_pack(g_vs.warm_phase, g_vs.warm_n, g_warm_result), std::memory_order_release);
}

// the rest: the Lua thread only
const Api *g_test = nullptr;
#ifdef _WIN32
Api g_real;
bool g_real_bound = false;
#endif
const Api *g_api = nullptr;          // the table the open device uses
uint32_t g_chan = 0;                  // the recording channel (HRECORD), 0: none
int g_device = -2;                    // the device number open (-2: none)
bool g_inited_here = false;
std::string g_name;
std::string g_failed;                 // the last failure (the state "failed: ...") until a successful open or close

template <class F>
bool sym(void *lib, const char *name, F &out)
{
#ifdef _WIN32
    FARPROC p = GetProcAddress((HMODULE)lib, name);
    std::memcpy(&out, &p, sizeof out);
    return p != nullptr;
#else
    (void)lib;
    (void)name;
    out = nullptr;
    return false;
#endif
}

// the table to use now: the test's, or Garry's Mod's bass.dll (resolved once; never loaded by us)
const Api *api(std::string &err)
{
    if (g_test) {
        return g_test;
    }
#ifdef _WIN32
    if (!g_real_bound) {
        void *lib = (void *)GetModuleHandleW(L"bass.dll");
        if (!lib) {
            err = "Garry's Mod's BASS audio library is not loaded in this process";
            return nullptr;
        }
        Api f;
        std::memset(&f, 0, sizeof f);
        bool ok = sym(lib, "BASS_RecordInit", f.RecordInit) && sym(lib, "BASS_RecordFree", f.RecordFree) &&
                  sym(lib, "BASS_RecordGetDeviceInfo", f.RecordGetDeviceInfo) &&
                  sym(lib, "BASS_RecordSetDevice", f.RecordSetDevice) &&
                  sym(lib, "BASS_RecordGetDevice", f.RecordGetDevice) && sym(lib, "BASS_RecordStart", f.RecordStart) &&
                  sym(lib, "BASS_ChannelPlay", f.ChannelPlay) && sym(lib, "BASS_ChannelPause", f.ChannelPause) &&
                  sym(lib, "BASS_ChannelStop", f.ChannelStop) && sym(lib, "BASS_ErrorGetCode", f.ErrorGetCode);
        if (!ok) {
            err = "Garry's Mod's BASS audio library has no recording functions";
            return nullptr;
        }
        g_real = f;
        g_real_bound = true;
    }
    return &g_real;
#else
    err = "not available";
    return nullptr;
#endif
}

// a device name as UTF-8: BASS gives ANSI names on Windows unless BASS_CONFIG_UNICODE is set (then UTF-8 already)
std::string utf8_name(const char *s)
{
    if (!s) {
        return std::string();
    }
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, nullptr, 0);
    if (n > 0) {
        return std::string(s);
    }
    n = MultiByteToWideChar(CP_ACP, 0, s, -1, nullptr, 0);
    if (n <= 0) {
        return std::string(s);
    }
    std::wstring w((size_t)n, L'\0');
    MultiByteToWideChar(CP_ACP, 0, s, -1, &w[0], n);
    int m = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (m <= 0) {
        return std::string(s);
    }
    std::string out((size_t)m, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, &out[0], m, nullptr, nullptr);
    if (!out.empty() && out.back() == '\0') {
        out.pop_back();
    }
    return out;
#else
    return std::string(s);
#endif
}

int GSA1_MICCALL record_proc(uint32_t handle, const void *buffer, uint32_t length, void *user)
{
    (void)handle;
    (void)user;
    MxcsrKeep keep;
    if (g_listening.load(std::memory_order_relaxed) && buffer && length >= sizeof(float)) {
        // the block's REAL sample count: BASS may deliver more or fewer than one 10 ms period (review R.8)
        uint32_t n = length / (uint32_t)sizeof(float);
        feed((const float *)buffer, n);
        if (g_vis_on.load(std::memory_order_acquire)) {
            analyse_block((const float *)buffer, n);
        }
    }
    return 1;    // TRUE: keep recording
}

// a failure in plain words; the Windows privacy hint for the codes a blocked or busy microphone gives (UNVERIFIED which
// one Windows' privacy switch produces: BASS reports the driver's refusal)
std::string fail_text(const char *what, int code)
{
    std::string t = format("%s (%s)", what, error_text(code).c_str());
    if (code == kErrorDriver || code == kErrorNotAvail || code == kErrorBusy || code == kErrorDenied ||
        code == kErrorUnknown || code == kErrorStart || code == kErrorDx) {
        t += ": Windows may not let desktop apps use the microphone (Settings > Privacy & security > Microphone), or "
             "another program holds it";
    }
    return t;
}

int default_device(const Api *f)
{
    for (uint32_t i = 0; i < 64; i++) {
        DeviceInfo d;
        std::memset(&d, 0, sizeof d);
        if (!f->RecordGetDeviceInfo(i, &d)) {
            break;
        }
        if ((d.flags & kDeviceDefault) && (d.flags & kDeviceEnabled)) {
            return (int)i;
        }
    }
    return 0;
}

std::string name_of(const Api *f, int device)
{
    DeviceInfo d;
    std::memset(&d, 0, sizeof d);
    if (device >= 0 && f->RecordGetDeviceInfo((uint32_t)device, &d)) {
        return utf8_name(d.name);
    }
    return std::string();
}

}  // namespace

static void teardown();

std::string error_text(int code)
{
    switch (code) {
    case 0: return "no error";
    case 1: return "out of memory";
    case kErrorDriver: return "no usable driver";
    case kErrorHandle: return "not open";
    case kErrorInit: return "not initialised";
    case kErrorStart: return "it could not start";
    case kErrorAlready: return "already initialised";
    case kErrorIllParam: return "a bad parameter";
    case kErrorDevice: return "no such device";
    case kErrorNotAvail: return "not available";
    case kErrorDx: return "no DirectSound / WASAPI";
    case kErrorBusy: return "the device is busy";
    case kErrorDenied: return "access denied";
    case kErrorUnknown: return "unknown error";
    default: return format("BASS error %d", code);
    }
}

float level_of_rms(float rms)
{
    if (!(rms > 0.0f)) {
        return 0.0f;
    }
    float db = 20.0f * std::log10(rms);
    float l = (db + 60.0f) / 50.0f;
    return l < 0.0f ? 0.0f : (l > 1.0f ? 1.0f : l);
}

void feed(const float *samples, uint32_t count)
{
    if (!samples || count == 0) {
        return;
    }
    double sum = 0.0;
    float peak = 0.0f;
    for (uint32_t i = 0; i < count; i++) {
        float v = samples[i];
        if (!std::isfinite(v)) {
            continue;
        }
        sum += (double)v * (double)v;
        float a = std::fabs(v);
        if (a > peak) {
            peak = a;
        }
    }
    float rms = (float)std::sqrt(sum / (double)count);
    g_level.store(level_of_rms(rms), std::memory_order_relaxed);
    g_peak.store(peak > 1.0f ? 1.0f : peak, std::memory_order_relaxed);
    g_blocks.fetch_add(1, std::memory_order_relaxed);
}

void set_test_api(const Api *f)
{
    close();
    g_test = f;
    g_failed.clear();
}

bool devices(std::vector<Device> &out, std::string &err)
{
    out.clear();
    const Api *f = api(err);
    if (!f) {
        return false;
    }
    for (uint32_t i = 0; i < 64; i++) {
        DeviceInfo d;
        std::memset(&d, 0, sizeof d);
        if (!f->RecordGetDeviceInfo(i, &d)) {
            break;
        }
        Device dv;
        dv.index = (int)i;
        dv.name = utf8_name(d.name);
        dv.is_default = (d.flags & kDeviceDefault) != 0;
        dv.enabled = (d.flags & kDeviceEnabled) != 0;
        dv.loopback = (d.flags & kDeviceLoopback) != 0;
        out.push_back(dv);
    }
    return true;
}

bool open(int device, std::string &err)
{
    return open2(device, false, err) == OPEN_OK;
}

int open2(int device, bool force, std::string &err)
{
    if (device < -1 || device > 63) {
        err = format("no microphone %d (-1 = Windows' default, 0..63)", device);
        return OPEN_FAILED;
    }
    if (!force && g_chan && (device == g_device || (device == -1 && g_device >= 0 && g_api &&
                                                    default_device(g_api) == g_device))) {
        return OPEN_OK;
    }
    // 0.9.4e: a loopback device (what the PC plays) is refused before anything is closed (lipsync2_plan.md 4.5)
    if (device >= 0) {
        std::string lerr;
        const Api *lf = api(lerr);
        DeviceInfo d;
        std::memset(&d, 0, sizeof d);
        if (lf && lf->RecordGetDeviceInfo((uint32_t)device, &d) && (d.flags & kDeviceLoopback)) {
            err = "that device records what your PC plays (a speaker output), not a microphone";
            return OPEN_LOOPBACK;
        }
    }
    teardown();
    const Api *f = api(err);
    if (!f) {
        g_failed = err;
        return OPEN_FAILED;
    }
    bool inited = false;
    if (f->RecordInit(device)) {
        inited = true;
    } else {
        int code = f->ErrorGetCode();
        if (code != kErrorAlready) {
            err = fail_text("the microphone could not be opened", code);
            g_failed = err;
            return OPEN_FAILED;
        }
        // Garry's Mod (or another part of the process) has this device open: use it, never free it
        int dev = device >= 0 ? device : default_device(f);
        if (!f->RecordSetDevice((uint32_t)dev)) {
            err = fail_text("the microphone is in use and could not be shared", f->ErrorGetCode());
            g_failed = err;
            return OPEN_FAILED;
        }
    }
    int dev = (int)f->RecordGetDevice();
    if (dev < 0 || dev == (int)0xFFFFFFFF) {
        dev = device >= 0 ? device : default_device(f);
    }
    g_listening.store(false);
    uint32_t flags = kSampleFloat | kRecordPause | (kPeriodMs << 16);
    uint32_t h = f->RecordStart(kRate, 1, flags, record_proc, nullptr);
    if (!h) {
        int code = f->ErrorGetCode();
        if (inited) {
            f->RecordFree();
        }
        err = fail_text("the microphone could not start", code);
        g_failed = err;
        return OPEN_FAILED;
    }
    g_api = f;
    g_chan = h;
    g_device = dev;
    g_inited_here = inited;
    g_name = name_of(f, dev);
    g_failed.clear();
    g_blocks.store(0);
    g_level.store(0.0f);
    g_peak.store(0.0f);
    // 0.9.4c: the classifier starts again on this device's first block, keeping the speaker number (review R.9)
    g_pending.fetch_or(kPendReinit, std::memory_order_acq_rel);
    return OPEN_OK;
}

bool listen(bool on, std::string &err)
{
    if (!g_chan || !g_api) {
        err = "the microphone is not open";
        return false;
    }
    if (on == g_listening.load()) {
        return true;
    }
    if (on) {
        g_level.store(0.0f);
        g_peak.store(0.0f);
        // 0.9.4c: a press - the classifier's ring and vote start from silence at the next block (the floor, the peak
        // and the speaker number survive); frames of the earlier press read as "none" from now on (review R.9)
        g_epoch.fetch_add(1u, std::memory_order_acq_rel);
        if (!g_api->ChannelPlay(g_chan, 0)) {
            err = fail_text("the microphone could not start", g_api->ErrorGetCode());
            return false;
        }
        g_listening.store(true);
    } else {
        g_listening.store(false);
        g_api->ChannelPause(g_chan);
        g_level.store(0.0f);
        g_peak.store(0.0f);
    }
    return true;
}

// stops capture and frees what this file initialised; the classifier's speaker number survives (a device change)
static void teardown()
{
    g_listening.store(false);
    if (g_api && g_chan) {
        g_api->ChannelStop(g_chan);
        if (g_inited_here && g_device >= 0) {
            g_api->RecordSetDevice((uint32_t)g_device);
            g_api->RecordFree();
        }
    }
    g_api = nullptr;
    g_chan = 0;
    g_device = -2;
    g_inited_here = false;
    g_name.clear();
    g_failed.clear();
    g_level.store(0.0f);
    g_peak.store(0.0f);
}

void close()
{
    teardown();
    // 0.9.4c: the session ends - the classifier forgets everything, the speaker number too (owner, PQ7: session memory
    // only). Its State is the RECORDPROC's: it starts from scratch at the next block; what Lua can read is reset now.
    g_vis_on.store(false, std::memory_order_release);
    g_pending.fetch_or(kPendForget, std::memory_order_acq_rel);
    g_epoch.fetch_add(1u, std::memory_order_acq_rel);
    g_frame.store((uint64_t)kClsNone << 16, std::memory_order_release);
    // 0.9.4e: both engines' voices, the warm-up (its pending step too) and the features are forgotten as well
    g_warm_step.store(-1, std::memory_order_release);
    g_features.store(kFeaturesNone, std::memory_order_release);
    publish_none_voice();
    publish_none_warm();
}

void level(float &lv, float &pk, std::string &state)
{
    if (!g_chan) {
        lv = pk = 0.0f;
        state = g_failed.empty() ? "off" : "failed: " + g_failed;
        return;
    }
    if (!g_listening.load()) {
        lv = pk = 0.0f;
        state = "paused";
        return;
    }
    lv = g_level.load(std::memory_order_relaxed);
    pk = g_peak.load(std::memory_order_relaxed);
    state = "on";
}

uint64_t blocks()
{
    return g_blocks.load();
}

std::string device_name()
{
    return g_chan ? g_name : std::string();
}

int device_index()
{
    return g_chan ? g_device : -2;
}

bool initialised_here()
{
    return g_chan != 0 && g_inited_here;
}

// ---- 0.9.4c: the sound classifier ----------------------------------------------------------------------------------
// the packing: bits 0-15 seq, 16-19 cls (15 none), 20-26 conf (0..127), 27-35 level (0..511), 36-45 F1 / 4, 46-55 F2 / 4,
// 56-63 the press epoch's low 8 bits
uint64_t viseme_pack(int cls, float level, float f1, float f2, float conf, uint32_t seq, uint32_t epoch)
{
    uint64_t c = (cls >= 0 && cls < viseme::COUNT) ? (uint64_t)cls : (uint64_t)kClsNone;
    return (uint64_t)(seq & 0xFFFFu) | (c << 16) | ((uint64_t)qround(conf, 127.0f, 127u) << 20) |
           ((uint64_t)qround(level, 511.0f, 511u) << 27) | ((uint64_t)qround(f1, 0.25f, 1023u) << 36) |
           ((uint64_t)qround(f2, 0.25f, 1023u) << 46) | ((uint64_t)(epoch & 0xFFu) << 56);
}

void viseme_unpack(uint64_t v, VisemeFrame &out, uint32_t &epoch)
{
    uint32_t c = (uint32_t)(v >> 16) & 0xFu;
    out.seq = (uint32_t)(v & 0xFFFFu);
    out.cls = c < (uint32_t)viseme::COUNT ? (int)c : -1;
    out.conf = (float)((v >> 20) & 0x7Fu) / 127.0f;
    out.level = (float)((v >> 27) & 0x1FFu) / 511.0f;
    out.f1 = (float)((v >> 36) & 0x3FFu) * 4.0f;
    out.f2 = (float)((v >> 46) & 0x3FFu) * 4.0f;
    epoch = (uint32_t)(v >> 56) & 0xFFu;
}

void viseme_on(bool on)
{
    if (on && !g_vis_on.load(std::memory_order_acquire)) {
        g_epoch.fetch_add(1u, std::memory_order_acq_rel);     // like a press: no frame from before the analysis started
    }
    g_vis_on.store(on, std::memory_order_release);
}

bool viseme_is_on()
{
    return g_vis_on.load(std::memory_order_acquire);
}

bool viseme_tune(const std::string &name, double value, std::string &err)
{
    if (name == "reset_voice") {
        g_pending.fetch_or(kPendResetVoice, std::memory_order_acq_rel);
        // what Lua reads now; the States follow at the next block (both engines; the warm-up's work too)
        publish_none_voice();
        publish_none_warm();
        return true;
    }
    if (!std::isfinite(value)) {
        err = format("MicVisemeTune(\"%s\", value): the value is not a number", name.c_str());
        return false;
    }
    if (name == "gate_min_db") {
        if (value < 3.0 || value > 12.0) {
            err = "MicVisemeTune(\"gate_min_db\", 3..12 dB)";
            return false;
        }
        g_tune_gate.store((float)value, std::memory_order_relaxed);
        return true;
    }
    if (name == "adapt") {
        if (value != 0.0 && value != 1.0) {
            err = "MicVisemeTune(\"adapt\", 0 or 1)";
            return false;
        }
        g_tune_adapt.store((int)value, std::memory_order_relaxed);
        if (value == 0.0) {
            publish_none_voice();
            publish_none_warm();
        }
        return true;
    }
    if (name == "smooth") {
        if (value < 0.0 || value > 3.0 || value != std::floor(value)) {
            err = "MicVisemeTune(\"smooth\", 0 instant .. 3 quick)";
            return false;
        }
        g_tune_smooth.store((int)value, std::memory_order_relaxed);
        return true;
    }
    if (name == "engine") {
        if (value != 1.0 && value != 2.0) {
            err = "MicVisemeTune(\"engine\", 1 (0.9.4c's sound detection) or 2 (0.9.4e's))";
            return false;
        }
        g_tune_engine.store((int)value, std::memory_order_relaxed);
        return true;
    }
    err = "MicVisemeTune(name, value): name is one of \"gate_min_db\", \"adapt\", \"smooth\", \"reset_voice\", \"engine\"";
    return false;
}

void viseme_frame(VisemeFrame &out)
{
    uint32_t ep = 0;
    viseme_unpack(g_frame.load(std::memory_order_acquire), out, ep);
    bool live = g_chan != 0 && g_listening.load(std::memory_order_acquire) && g_vis_on.load(std::memory_order_acquire) &&
                ep == (g_epoch.load(std::memory_order_acquire) & 0xFFu);
    if (!live || out.cls < 0) {
        out.cls = -1;
        out.level = out.f1 = out.f2 = out.conf = 0.0f;
    }
}

void viseme_voice(float &g, uint32_t &frames)
{
    float f1, f2;
    bool warmed;
    viseme_voice2(g, frames, f1, f2, warmed);
}

void viseme_debug(VisemeDebug &out)
{
    out.entries = g_dbg_entries.load();
    out.overlaps = g_dbg_overlaps.load();
    out.marked_thread_entries = g_dbg_marked.load();
}

void viseme_debug_mark_thread()
{
    g_dbg_mark.store(thread_hash());
}

// ---- 0.9.4e ---------------------------------------------------------------------------------------------------------
int viseme_engine()
{
    int e = g_engine_applied.load(std::memory_order_relaxed);
    return e ? e : g_tune_engine.load(std::memory_order_relaxed);
}

bool viseme_warm(int step, std::string &err)
{
    if (step < WARM_AH || step > WARM_CANCEL) {
        err = format("MicVisemeWarmup: no step %d", step);
        return false;
    }
    if (g_tune_engine.load(std::memory_order_relaxed) != ENGINE_V2) {
        err = "needs 'Sound detection' 0.9.4e";
        return false;
    }
    if (g_tune_adapt.load(std::memory_order_relaxed) == 0) {
        err = "needs 'Learn my voice'";
        return false;
    }
    if (!g_chan) {
        err = "the microphone is not open";
        return false;
    }
    g_warm_step.store(step, std::memory_order_release);
    return true;
}

void viseme_warm_state(WarmState &out)
{
    uint64_t v = g_warm.load(std::memory_order_acquire);
    out.phase = (int)(v & 7u) - 1;
    for (int c = 0; c < 4; c++) {
        out.n[c] = (uint32_t)((v >> (3 + 8 * c)) & 0xFFu);
    }
    out.result = (int)((v >> 35) & 7u);
}

void viseme_voice2(float &g, uint32_t &frames, float &f1_hz, float &f2_hz, bool &warmed)
{
    int engine = 0;
    voice_unpack(g_voice.load(std::memory_order_acquire), g, frames, f1_hz, f2_hz, warmed, engine);
    // a forget / reset the RECORDPROC has not applied yet (a block in flight may have published the old voice after it
    // was asked), learning off, or nothing learned: the prior of the chosen engine
    bool forgotten = (g_pending.load(std::memory_order_acquire) & (kPendForget | kPendResetVoice)) != 0u ||
                     g_tune_adapt.load(std::memory_order_relaxed) == 0;
    if (forgotten || (frames == 0u && !warmed) || engine == 0) {
        g = g_prior(engine ? engine : g_tune_engine.load(std::memory_order_relaxed));
        frames = 0u;
        f1_hz = f2_hz = 0.0f;
        warmed = false;
    }
}

uint64_t features_pack(const VisemeFeatures &f)
{
    float loc = -f.rel_loc;
    uint64_t c = (f.cat >= 0 && f.cat < 15) ? (uint64_t)f.cat : 15u;
    uint64_t r = (f.raw >= 0 && f.raw < 15) ? (uint64_t)f.raw : 15u;
    return (uint64_t)(f.seq & 0xFFFFu) | ((uint64_t)qround(loc, 4.0f, 255u) << 16) |
           ((uint64_t)qround(f.per, 127.0f, 127u) << 24) | ((uint64_t)qround(f.nbr, 127.0f, 127u) << 31) |
           ((uint64_t)qround(f.eep, 127.0f, 127u) << 38) | (c << 45) | (r << 49) |
           ((uint64_t)qround(f.lowr, 31.0f, 31u) << 53) | ((uint64_t)qround(f.zcr, 63.0f, 63u) << 58);
}

void features_unpack(uint64_t v, VisemeFeatures &out)
{
    out.seq = (uint32_t)(v & 0xFFFFu);
    out.rel_loc = -(float)((v >> 16) & 0xFFu) / 4.0f;
    out.per = (float)((v >> 24) & 0x7Fu) / 127.0f;
    out.nbr = (float)((v >> 31) & 0x7Fu) / 127.0f;
    out.eep = (float)((v >> 38) & 0x7Fu) / 127.0f;
    uint32_t c = (uint32_t)(v >> 45) & 0xFu, r = (uint32_t)(v >> 49) & 0xFu;
    out.cat = c == 15u ? -1 : (int)c;
    out.raw = r == 15u ? -1 : (int)r;
    out.lowr = (float)((v >> 53) & 0x1Fu) / 31.0f;
    out.zcr = (float)((v >> 58) & 0x3Fu) / 63.0f;
}

void viseme_features(VisemeFeatures &out)
{
    features_unpack(g_features.load(std::memory_order_acquire), out);
}

void viseme_debug_states(viseme::State *v2, viseme_v1::State *v1)
{
    // tests only, with no block in flight (a single-threaded test after the RECORDPROC returned)
    if (v2) {
        std::memcpy((void *)v2, (const void *)&g_vs, sizeof g_vs);
    }
    if (v1) {
        std::memcpy((void *)v1, (const void *)&g_vs1, sizeof g_vs1);
    }
}

}  // namespace mic
}  // namespace gsa1
