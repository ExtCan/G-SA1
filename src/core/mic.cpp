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

// ---- 0.9.4c: the sound classifier (phoneme_plan.md 4.2 step 2, review R.8 / R.9) ----
// Lua thread -> RECORDPROC: atomics only, applied at the start of the RECORDPROC's next block
std::atomic<bool> g_vis_on{false};
std::atomic<uint32_t> g_epoch{0};             // +1 per press (listen(true)) and per analysis start (viseme_on(true))
const uint32_t kPendReinit = 1u;              // another device: start again, keep the speaker number
const uint32_t kPendForget = 2u;              // the session ended (close): start again, forget the speaker number
const uint32_t kPendResetVoice = 4u;          // "reset_voice"
std::atomic<uint32_t> g_pending{0};
std::atomic<float> g_tune_gate{6.0f};
std::atomic<int> g_tune_adapt{1}, g_tune_smooth{3};
// RECORDPROC -> Lua: the newest frame and the speaker number (float bits | frames << 32)
const uint32_t kClsNone = 15u;
std::atomic<uint64_t> g_frame{(uint64_t)kClsNone << 16};   // "none" (viseme_pack's layout)
std::atomic<uint64_t> g_voice{0};             // frames 0: the prior
// the RECORDPROC's own: never touched on another thread (review R.9)
viseme::State g_vs;
bool g_vs_ready = false;
uint32_t g_vs_epoch = 0;
uint32_t g_vs_seq = 0;
int g_vs_adapt = 1;
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

float g_prior()
{
    static const float p = viseme::prior_g();
    return p;
}

uint32_t qround(float v, float scale, uint32_t max)
{
    if (!(v > 0.0f)) {
        return 0u;
    }
    float q = v * scale + 0.5f;
    return q >= (float)max ? max : (uint32_t)q;
}

void publish_voice(float g, uint32_t frames)
{
    uint32_t bits;
    std::memcpy(&bits, &g, sizeof bits);
    g_voice.store((uint64_t)bits | ((uint64_t)frames << 32), std::memory_order_release);
}

// one block through the classifier (the RECORDPROC, while listening with the analysis on)
void analyse_block(const float *x, uint32_t n)
{
    StateEntry entry;
    uint32_t pend = g_pending.exchange(0u, std::memory_order_acq_rel);
    viseme::Params p;
    viseme::default_params(p);
    p.gate_min_db = g_tune_gate.load(std::memory_order_relaxed);
    p.adapt = g_tune_adapt.load(std::memory_order_relaxed);
    p.smooth = g_tune_smooth.load(std::memory_order_relaxed);
    if (!g_vs_ready || (pend & kPendForget)) {
        viseme::init(g_vs, p);
        g_vs_ready = true;
        g_vs_adapt = p.adapt;
        g_vs_seq = 0u;            // close() published "none" with seq 0: a new session counts from there
    } else if (pend & kPendReinit) {
        viseme::reinit_keep_voice(g_vs, p);
    }
    if (pend & kPendResetVoice) {
        viseme::reset_voice(g_vs);
    }
    uint32_t ep = g_epoch.load(std::memory_order_acquire);
    if (ep != g_vs_epoch) {
        viseme::reset_press(g_vs);
        g_vs_epoch = ep;
    }
    // the tunes (applied at the start of this block)
    g_vs.p.gate_min_db = p.gate_min_db;
    g_vs.p.smooth = p.smooth;
    if (p.adapt != g_vs_adapt) {
        g_vs.p.adapt = p.adapt;
        g_vs_adapt = p.adapt;
        if (p.adapt == 0) {
            viseme::reset_voice(g_vs);     // "learn my voice" off: the adult prior again
        }
    }
    viseme::Frame f;
    int made;
    {
        FtzScope ftz;
        made = viseme::feed(g_vs, x, (int)(n > 0x7FFFFFFFu ? 0x7FFFFFFFu : n), &f, 1);
    }
    if (made > 0) {
        g_vs_seq = (g_vs_seq + 1u) & 0xFFFFu;
        g_frame.store(viseme_pack(f.cls, f.level, f.f1, f.f2, f.conf, g_vs_seq, ep), std::memory_order_release);
    }
    publish_voice(g_vs.g, g_vs.voice_frames);
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
        out.push_back(dv);
    }
    return true;
}

bool open(int device, std::string &err)
{
    if (device < -1 || device > 63) {
        err = format("no microphone %d (-1 = Windows' default, 0..63)", device);
        return false;
    }
    if (g_chan && (device == g_device || (device == -1 && g_device >= 0 && g_api &&
                                          default_device(g_api) == g_device))) {
        return true;
    }
    teardown();
    const Api *f = api(err);
    if (!f) {
        g_failed = err;
        return false;
    }
    bool inited = false;
    if (f->RecordInit(device)) {
        inited = true;
    } else {
        int code = f->ErrorGetCode();
        if (code != kErrorAlready) {
            err = fail_text("the microphone could not be opened", code);
            g_failed = err;
            return false;
        }
        // Garry's Mod (or another part of the process) has this device open: use it, never free it
        int dev = device >= 0 ? device : default_device(f);
        if (!f->RecordSetDevice((uint32_t)dev)) {
            err = fail_text("the microphone is in use and could not be shared", f->ErrorGetCode());
            g_failed = err;
            return false;
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
        return false;
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
    return true;
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
    publish_voice(g_prior(), 0u);
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
        // what Lua reads now; the State follows at the next block
        publish_voice(g_prior(), 0u);
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
            publish_voice(g_prior(), 0u);
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
    err = "MicVisemeTune(name, value): name is one of \"gate_min_db\", \"adapt\", \"smooth\", \"reset_voice\"";
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
    uint64_t v = g_voice.load(std::memory_order_acquire);
    uint32_t bits = (uint32_t)v;
    frames = (uint32_t)(v >> 32);
    std::memcpy(&g, &bits, sizeof g);
    // a forget / reset the RECORDPROC has not applied yet (a block in flight may have published the old number after
    // it was asked), or learning off: the prior
    bool forgotten = (g_pending.load(std::memory_order_acquire) & (kPendForget | kPendResetVoice)) != 0u ||
                     g_tune_adapt.load(std::memory_order_relaxed) == 0;
    if (forgotten || frames == 0u || !std::isfinite(g)) {
        g = g_prior();
        frames = 0u;
    }
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

}  // namespace mic
}  // namespace gsa1
