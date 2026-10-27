// G-SA1 core: Garry's Mod's BASS (see bass.hpp).
#include "bass.hpp"

#include <algorithm>
#include <cstring>

#include "util.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace gsa1 {

namespace {
std::mutex g_bass_m;
const BassApi *g_test_api = nullptr;
BassApi g_api;
bool g_bound = false;
int g_refs = 0;
void *g_lib = nullptr;

template <class F>
bool sym(void *lib, const char *name, F &out)
{
#ifdef _WIN32
    FARPROC p = GetProcAddress((HMODULE)lib, name);
#else
    void *p = dlsym(lib, name);
#endif
    std::memcpy(&out, &p, sizeof out);
    return p != nullptr;
}
}  // namespace

const BassApi *bass_acquire(std::string &err)
{
    std::lock_guard<std::mutex> g(g_bass_m);
    if (g_test_api) {
        g_refs++;
        return g_test_api;
    }
    if (!g_bound) {
#ifdef _WIN32
        // Garry's Mod's gmod_audio.dll imports bass.dll, so it is in the process: never load a library here
        void *lib = (void *)GetModuleHandleW(L"bass.dll");
#else
        void *lib = dlopen("libbass.so", RTLD_LAZY | RTLD_NOLOAD);
#endif
        if (!lib) {
            err = "Garry's Mod's BASS audio library is not loaded in this process";
            return nullptr;
        }
        BassApi f;
        std::memset(&f, 0, sizeof f);
        bool ok = sym(lib, "BASS_GetVersion", f.GetVersion) && sym(lib, "BASS_GetDevice", f.GetDevice) &&
                  sym(lib, "BASS_ErrorGetCode", f.ErrorGetCode) && sym(lib, "BASS_GetConfig", f.GetConfig) &&
                  sym(lib, "BASS_StreamCreate", f.StreamCreate) && sym(lib, "BASS_StreamFree", f.StreamFree) &&
                  sym(lib, "BASS_StreamPutData", f.StreamPutData) && sym(lib, "BASS_ChannelPlay", f.ChannelPlay) &&
                  sym(lib, "BASS_ChannelPause", f.ChannelPause) &&
                  sym(lib, "BASS_ChannelSetAttribute", f.ChannelSetAttribute) &&
                  sym(lib, "BASS_ChannelGetData", f.ChannelGetData) &&
                  sym(lib, "BASS_ChannelIsActive", f.ChannelIsActive) &&
                  sym(lib, "BASS_ChannelSlideAttribute", f.ChannelSlideAttribute);
        uint32_t v = ok ? f.GetVersion() : 0u;
        if (!ok || (v >> 16) != 0x0204u) {
            err = ok ? format("BASS version %08X is not 2.4", v) : "the BASS library in this process lacks a function G-SA1 needs";
#ifndef _WIN32
            dlclose(lib);
#endif
            return nullptr;
        }
        f.version = v;
        g_api = f;
        g_lib = lib;
        g_bound = true;
    }
    g_refs++;
    return &g_api;
}

void bass_release()
{
    std::lock_guard<std::mutex> g(g_bass_m);
    if (g_refs > 0) {
        g_refs--;
    }
    if (g_refs == 0 && g_bound) {
#ifndef _WIN32
        if (g_lib) {
            dlclose(g_lib);
        }
#endif
        g_lib = nullptr;
        g_bound = false;
    }
}

std::string bass_name(const BassApi *api)
{
    if (!api) {
        return "none";
    }
    {
        std::lock_guard<std::mutex> g(g_bass_m);
        if (api == g_test_api) {
            return "fake BASS (tests)";
        }
    }
    uint32_t v = api->version;
    return format("BASS %u.%u.%u.%u (Garry's Mod)", (v >> 24) & 255u, (v >> 16) & 255u, (v >> 8) & 255u, v & 255u);
}

uint32_t bass_push_stream(const BassApi *api, uint32_t rate, std::string &err)
{
    // STREAMPROC_PUSH: the stream plays what BASS_StreamPutData queues; 16-bit stereo
    uint32_t h = api->StreamCreate(rate, 2, 0, (void *)(intptr_t)-1, nullptr);
    if (!h) {
        err = format("BASS_StreamCreate failed (BASS error %d)", api->ErrorGetCode());
        return 0;
    }
    api->ChannelSetAttribute(h, bass::kAttribBuffer, 0.0f);
    return h;
}

uint32_t bass_queued_frames(const BassApi *api, uint32_t h)
{
    if (!api || !h) {
        return 0;
    }
    // 0.9.2a (A0): the push queue only; BASS's playback buffer is latency, not cushion (bass.hpp)
    uint32_t q = api->StreamPutData(h, nullptr, 0);
    return q == bass::kFail ? 0u : std::min<uint32_t>(q / 4u, 0x7FFFFFFFu);
}

uint32_t bass_playback_frames(const BassApi *api, uint32_t h)
{
    if (!api || !h) {
        return 0;
    }
    uint32_t b = api->ChannelGetData(h, nullptr, bass::kDataAvailable);
    return b == bass::kFail ? 0u : std::min<uint32_t>(b / 4u, 0x7FFFFFFFu);
}

void bass_set_test_api(const BassApi *api)
{
    std::lock_guard<std::mutex> g(g_bass_m);
    g_test_api = api;
}

// ---- FakeBass -------------------------------------------------------------------------------------------------------
namespace {
thread_local int t_fake_err = 0;
}

FakeBass &FakeBass::get()
{
    static FakeBass f;
    return f;
}

FakeBass::FakeBass()
{
    std::memset(&api_, 0, sizeof api_);
    api_.GetVersion = &FakeBass::GetVersion;
    api_.GetDevice = &FakeBass::GetDevice;
    api_.ErrorGetCode = &FakeBass::ErrorGetCode;
    api_.GetConfig = &FakeBass::GetConfig;
    api_.StreamCreate = &FakeBass::StreamCreate;
    api_.StreamFree = &FakeBass::StreamFree;
    api_.StreamPutData = &FakeBass::StreamPutData;
    api_.ChannelPlay = &FakeBass::ChannelPlay;
    api_.ChannelPause = &FakeBass::ChannelPause;
    api_.ChannelSetAttribute = &FakeBass::ChannelSetAttribute;
    api_.ChannelGetData = &FakeBass::ChannelGetData;
    api_.ChannelIsActive = &FakeBass::ChannelIsActive;
    api_.ChannelSlideAttribute = &FakeBass::ChannelSlideAttribute;
    api_.version = 0x02041100u;
}

const BassApi *FakeBass::api() { return &api_; }

void FakeBass::reset()
{
    std::lock_guard<std::mutex> g(m_);
    s_.clear();
    speed_ = 1.0;
    record_ = false;
    gvol_ = 10000;
    fail_creates_ = 0;
    created_ = 0;
    calls_ = 0;
    by_thread_.clear();
    playback_ms_ = 0.0;
    manual_ = false;
    manual_now_ = 0.0;
}

double FakeBass::clock() const
{
    return manual_ ? manual_now_ : now_ms();
}

void FakeBass::set_playback_buffer_ms(double ms)
{
    std::lock_guard<std::mutex> g(m_);
    playback_ms_ = std::max(0.0, ms);
}

void FakeBass::set_manual_clock(bool on)
{
    std::lock_guard<std::mutex> g(m_);
    double now = clock();
    for (auto &kv : s_) {
        drain(kv.second, now);
    }
    manual_ = on;
    manual_now_ = 0.0;
    now = clock();
    for (auto &kv : s_) {
        kv.second.last = now;
        kv.second.dry_since = now;
    }
}

void FakeBass::advance_ms(double ms)
{
    std::lock_guard<std::mutex> g(m_);
    if (manual_ && ms > 0.0) {
        manual_now_ += ms;
    }
}

void FakeBass::set_speed(double s)
{
    std::lock_guard<std::mutex> g(m_);
    double now = clock();
    for (auto &kv : s_) {
        drain(kv.second, now);
    }
    speed_ = s;
}

void FakeBass::set_record_pcm(bool on)
{
    std::lock_guard<std::mutex> g(m_);
    record_ = on;
}

void FakeBass::set_gvol(uint32_t v)
{
    std::lock_guard<std::mutex> g(m_);
    gvol_ = v;
}

void FakeBass::fail_creates(int n)
{
    std::lock_guard<std::mutex> g(m_);
    fail_creates_ = n;
}

void FakeBass::break_all()
{
    std::lock_guard<std::mutex> g(m_);
    for (auto &kv : s_) {
        if (!kv.second.freed) {
            kv.second.broken = true;
        }
    }
}

std::map<uint32_t, FakeBass::Stream> FakeBass::streams()
{
    std::lock_guard<std::mutex> g(m_);
    double now = clock();
    for (auto &kv : s_) {
        drain(kv.second, now);
    }
    return s_;
}

FakeBass::Stream FakeBass::stream(uint32_t h)
{
    std::lock_guard<std::mutex> g(m_);
    auto it = s_.find(h);
    if (it == s_.end()) {
        return Stream();
    }
    drain(it->second, clock());
    return it->second;
}

uint64_t FakeBass::calls() const
{
    std::lock_guard<std::mutex> g(m_);
    return calls_;
}

uint64_t FakeBass::calls_from(std::thread::id t) const
{
    std::lock_guard<std::mutex> g(m_);
    auto it = by_thread_.find(t);
    return it == by_thread_.end() ? 0u : it->second;
}

uint32_t FakeBass::live() const
{
    std::lock_guard<std::mutex> g(m_);
    uint32_t n = 0;
    for (auto &kv : s_) {
        n += !kv.second.freed && !kv.second.broken;
    }
    return n;
}

uint32_t FakeBass::created() const
{
    std::lock_guard<std::mutex> g(m_);
    return created_;
}

void FakeBass::note_call()
{
    calls_++;
    by_thread_[std::this_thread::get_id()]++;
}

FakeBass::Stream *FakeBass::find(uint32_t h)
{
    auto it = s_.find(h);
    if (it == s_.end() || it->second.freed || it->second.broken) {
        t_fake_err = bass::kErrorHandle;
        return nullptr;
    }
    t_fake_err = 0;
    return &it->second;
}

void FakeBass::drain(Stream &s, double now)
{
    if (!s.started || s.paused || s.freed || s.broken) {
        s.last = now;
        return;
    }
    double want = std::max(0.0, now - s.last) / 1000.0 * (double)s.rate * speed_;
    s.last = now;
    double avail = (double)s.pushed - s.played;
    if (want <= avail) {
        s.played += want;
        return;
    }
    s.played = (double)s.pushed;
    if (!s.ended) {
        s.stall_frames += want - avail;
        if (!s.dry) {
            s.stalls++;
            s.dry = true;
            // (the moment it ran dry, for the playback buffer model)
            s.dry_since = now - (want - avail) / ((double)s.rate * speed_) * 1000.0;
        }
    }
}

uint32_t GSA1_BASSCALL FakeBass::GetVersion(void)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    return f.api_.version;
}

uint32_t GSA1_BASSCALL FakeBass::GetDevice(void)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    return 1;
}

int GSA1_BASSCALL FakeBass::ErrorGetCode(void)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    return t_fake_err;
}

uint32_t GSA1_BASSCALL FakeBass::GetConfig(uint32_t option)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    return option == bass::kConfigGvolStream ? f.gvol_ : bass::kFail;
}

uint32_t GSA1_BASSCALL FakeBass::StreamCreate(uint32_t freq, uint32_t chans, uint32_t flags, void *proc, void *user)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    if (f.fail_creates_ > 0) {
        f.fail_creates_--;
        t_fake_err = bass::kErrorInit;
        return 0;
    }
    if (proc != (void *)(intptr_t)-1 || chans < 1 || chans > 2 || freq < 1000 || flags != 0) {
        t_fake_err = 6;   // BASS_ERROR_FORMAT
        return 0;
    }
    uint32_t h = f.next_++;
    Stream s;
    s.rate = freq;
    s.chans = chans;
    s.last = f.clock();
    s.dry_since = s.last;
    f.s_[h] = s;
    f.created_++;
    t_fake_err = 0;
    return h;
}

int GSA1_BASSCALL FakeBass::StreamFree(uint32_t handle)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    Stream *s = f.find(handle);
    if (!s) {
        return 0;
    }
    f.drain(*s, f.clock());
    s->freed = true;
    return 1;
}

uint32_t GSA1_BASSCALL FakeBass::StreamPutData(uint32_t handle, const void *buffer, uint32_t length)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    Stream *s = f.find(handle);
    if (!s) {
        return bass::kFail;
    }
    f.drain(*s, f.clock());
    uint32_t bytes = length & ~bass::kStreamEnd;
    if (buffer && (bytes || (length & bass::kStreamEnd))) {
        if (s->ended) {
            t_fake_err = bass::kErrorEnded;
            return bass::kFail;
        }
        uint32_t frames = bytes / (2u * s->chans);
        if (f.record_) {
            const int16_t *p = (const int16_t *)buffer;
            s->pcm.insert(s->pcm.end(), p, p + (size_t)frames * s->chans);
        }
        s->pushed += frames;
        if (frames) {
            s->dry = false;
        }
        if (length & bass::kStreamEnd) {
            s->ended = true;
        }
    }
    double q = std::max(0.0, (double)s->pushed - s->played) * 2.0 * s->chans;
    return (uint32_t)q;
}

int GSA1_BASSCALL FakeBass::ChannelPlay(uint32_t handle, int restart)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    Stream *s = f.find(handle);
    if (!s) {
        return 0;
    }
    double now = f.clock();
    f.drain(*s, now);
    if (!s->started) {
        s->vol_set_before_play = s->vol;
        s->pan_set_before_play = s->pan;
        s->attrs_before_play = s->vol_set && s->pan_set;
        s->started = true;
    }
    s->paused = false;
    s->last = now;
    return 1;
}

int GSA1_BASSCALL FakeBass::ChannelPause(uint32_t handle)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    Stream *s = f.find(handle);
    if (!s) {
        return 0;
    }
    f.drain(*s, f.clock());
    s->paused = true;
    return 1;
}

int GSA1_BASSCALL FakeBass::ChannelSetAttribute(uint32_t handle, uint32_t attrib, float value)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    Stream *s = f.find(handle);
    if (!s) {
        return 0;
    }
    if (attrib == bass::kAttribVol) {
        s->vol = value;
        s->vol_set = true;
    } else if (attrib == bass::kAttribPan) {
        s->pan = value;
        s->pan_set = true;
    } else if (attrib == bass::kAttribBuffer) {
        s->buffer = value;
    }
    return 1;
}

uint32_t GSA1_BASSCALL FakeBass::ChannelGetData(uint32_t handle, void *buffer, uint32_t length)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    Stream *s = f.find(handle);
    if (!s) {
        return bass::kFail;
    }
    if (buffer || length != bass::kDataAvailable) {
        return bass::kFail;
    }
    // the playback buffer model (set_playback_buffer_ms; 0 = none: nothing waits outside the push queue): the frames
    // drained during the last playback_ms_ are still in it; while the queue is dry the device plays it empty
    if (f.playback_ms_ <= 0.0 || !s->started) {
        return 0u;
    }
    double now = f.clock();
    f.drain(*s, now);
    double cap = f.playback_ms_ / 1000.0 * (double)s->rate * f.speed_;
    double held = std::min(cap, s->played);
    if (s->dry) {
        held -= std::max(0.0, now - s->dry_since) / 1000.0 * (double)s->rate * f.speed_;
    }
    return held <= 0.0 ? 0u : (uint32_t)(held * 2.0 * s->chans);
}

uint32_t GSA1_BASSCALL FakeBass::ChannelIsActive(uint32_t handle)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    Stream *s = f.find(handle);
    if (!s) {
        return bass::kActiveStopped;
    }
    f.drain(*s, f.clock());
    if (s->paused) return bass::kActivePaused;
    if (!s->started) return bass::kActiveStopped;
    if (s->played >= (double)s->pushed) return s->ended ? bass::kActiveStopped : bass::kActiveStalled;
    return bass::kActivePlaying;
}

int GSA1_BASSCALL FakeBass::ChannelSlideAttribute(uint32_t handle, uint32_t attrib, float value, uint32_t time_ms)
{
    FakeBass &f = get();
    std::lock_guard<std::mutex> g(f.m_);
    f.note_call();
    Stream *s = f.find(handle);
    if (!s) {
        return 0;
    }
    s->slides++;
    if (attrib == bass::kAttribVol) {
        s->slide_vol = value;
        s->slide_vol_ms = time_ms;
        s->vol = value;       // the fake slides at once
        s->vol_set = true;
    } else if (attrib == bass::kAttribPan) {
        s->slide_pan = value;
        s->pan = value;
        s->pan_set = true;
    }
    return 1;
}

}  // namespace gsa1
