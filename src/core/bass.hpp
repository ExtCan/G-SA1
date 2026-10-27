// G-SA1 core: Garry's Mod's BASS 2.4 (bass.dll / libbass.so), shared by the game sound's push stream (AudioOut,
// audio.hpp) and the jukebox (jukebox.hpp; sadc docs/research/jukebox.md 6.3, plan 10.2 J1).
//
// GMod's own gmod_audio imports BASS and initialises it for its sound.Play* API, so the library is already in the
// process: bass_acquire() finds it there (GetModuleHandleW / dlopen with RTLD_NOLOAD) and binds the functions G-SA1
// calls. G-SA1 never loads a library and never initialises or frees BASS itself; it only creates, feeds and frees its
// own push streams. The table is immutable once bound, so any thread may call through it; the jukebox's rule (plan
// 10.2, Review G1) is that every BASS call for a jukebox stream comes from the jukebox's worker thread.
//
// Tests install a fake (FakeBass below: push streams that drain in real time and record every call with its thread)
// with bass_set_test_api(); bass_acquire() then returns that table.
#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#define GSA1_BASSCALL __stdcall
#else
#define GSA1_BASSCALL
#endif

namespace gsa1 {

namespace bass {
const uint32_t kAttribVol = 2;
const uint32_t kAttribPan = 3;
const uint32_t kAttribBuffer = 13;          // playback buffer length; 0 = the output pulls straight from the queue
const uint32_t kConfigGvolStream = 5;       // BASS_CONFIG_GVOL_STREAM, 0..10000
const uint32_t kDataAvailable = 0;          // BASS_ChannelGetData: bytes in the playback buffer
const uint32_t kActiveStopped = 0, kActivePlaying = 1, kActiveStalled = 2, kActivePaused = 3, kActivePausedDevice = 4;
const uint32_t kFail = 0xFFFFFFFFu;         // (DWORD)-1
const uint32_t kStreamEnd = 0x80000000u;    // BASS_STREAMPROC_END: BASS_StreamPutData's length flag, the stream ends
const int kErrorHandle = 5;                 // BASS_ERROR_HANDLE: invalid handle (GMod freed or re-initialised BASS)
const int kErrorInit = 8;                   // BASS_ERROR_INIT: BASS_Init has not been called
const int kErrorEnded = 45;                 // BASS_ERROR_ENDED: the stream has ended (data after BASS_STREAMPROC_END)
}  // namespace bass

// The functions G-SA1 calls (BASS 2.4 signatures; BOOL = int, DWORD / HSTREAM = uint32_t).
struct BassApi {
    uint32_t(GSA1_BASSCALL *GetVersion)(void);
    uint32_t(GSA1_BASSCALL *GetDevice)(void);
    int(GSA1_BASSCALL *ErrorGetCode)(void);
    uint32_t(GSA1_BASSCALL *GetConfig)(uint32_t option);
    uint32_t(GSA1_BASSCALL *StreamCreate)(uint32_t freq, uint32_t chans, uint32_t flags, void *proc, void *user);
    int(GSA1_BASSCALL *StreamFree)(uint32_t handle);
    uint32_t(GSA1_BASSCALL *StreamPutData)(uint32_t handle, const void *buffer, uint32_t length);
    int(GSA1_BASSCALL *ChannelPlay)(uint32_t handle, int restart);
    int(GSA1_BASSCALL *ChannelPause)(uint32_t handle);
    int(GSA1_BASSCALL *ChannelSetAttribute)(uint32_t handle, uint32_t attrib, float value);
    uint32_t(GSA1_BASSCALL *ChannelGetData)(uint32_t handle, void *buffer, uint32_t length);
    uint32_t(GSA1_BASSCALL *ChannelIsActive)(uint32_t handle);
    // the jukebox's (jukebox.md 3: BASS_ATTRIB_PAN, BASS_ChannelSlideAttribute)
    int(GSA1_BASSCALL *ChannelSlideAttribute)(uint32_t handle, uint32_t attrib, float value, uint32_t time_ms);
    uint32_t version;               // GetVersion() at bind time
};

// The process's BASS (or the test's fake): nullptr with err when it is not loaded, lacks a function or is not 2.4.
// Reference counted: every successful acquire is paired with one bass_release() (on Linux the last release closes the
// RTLD_NOLOAD reference). Thread-safe.
const BassApi *bass_acquire(std::string &err);
void bass_release();
// "BASS 2.4.17.0 (Garry's Mod)" / "fake BASS (tests)"
std::string bass_name(const BassApi *api);
// a push stream (STREAMPROC_PUSH) of 16-bit stereo at `rate` with BASS's playback buffer set to 0, so the push queue is
// the whole latency; 0 with err (the BASS error code in it)
uint32_t bass_push_stream(const BassApi *api, uint32_t rate, std::string &err);
// frames still waiting in the push queue (BASS_StreamPutData(h, NULL, 0); 16-bit stereo). 0.9.2a (sadc
// docs/research/gsa1_091a_perf.md A0 with its review RC3): only this is a cushion against a slow frame. Until 0.9.1 this
// also added BASS's playback buffer (BASS_DATA_AVAILABLE) - 41-49 ms on the owner's 192 kHz device even with
// BASS_ATTRIB_BUFFER 0 - which has already left the queue for the device: the feed then kept only about 25 ms really
// queued and every frame longer than 20-30 ms ran the stream dry (about 109 underruns a minute in the owner's log).
uint32_t bass_queued_frames(const BassApi *api, uint32_t handle);
// frames in BASS's playback buffer (BASS_DATA_AVAILABLE): latency, not cushion (diagnostics: gsa1.AudioStatus)
uint32_t bass_playback_frames(const BassApi *api, uint32_t handle);
// tests: bass_acquire() returns `api` (nullptr: the process's BASS again)
void bass_set_test_api(const BassApi *api);

// ---- a fake BASS for tests ----------------------------------------------------------------------------------------
// One process-wide instance (BASS's API has no user pointer). Push streams drain in real time (times `speed`) like a
// device with no playback buffer: a stream that runs dry without BASS_STREAMPROC_END is STALLED and counts the frames
// it missed; it plays on when data arrives. Every call is recorded with its thread; the PCM pushed can be kept.
// 0.9.2a (gsa1_091a_perf.md review RC6, opt-in, default off so the jukebox tests keep their numbers):
// set_playback_buffer_ms models the real BASS's playback buffer - the drained frames of the last `ms` still wait in it
// (BASS_DATA_AVAILABLE reports them; it empties while the queue is dry) - and set_manual_clock replaces the wall clock
// by advance_ms() steps, so a feed's timing can be tested exactly.
class FakeBass {
public:
    struct Stream {
        uint32_t rate = 0, chans = 0;
        bool started = false, paused = false, freed = false, ended = false;   // ended: BASS_STREAMPROC_END was queued
        bool broken = false;                // invalidated (break_all): every call fails with BASS_ERROR_HANDLE
        uint64_t pushed = 0;                // frames
        double played = 0;                  // frames drained
        double last = 0;                    // ms of the last drain
        double stall_frames = 0;            // frames the device wanted but the queue did not have (not after END)
        uint32_t stalls = 0;                // times it ran dry
        bool dry = false;
        double dry_since = 0;               // ms (the fake's clock) when it last ran dry
        float vol = 1.0f, pan = 0.0f, buffer = -1.0f;
        float slide_vol = -1.0f, slide_pan = -2.0f;   // last slide targets (-1 / -2: none)
        uint32_t slide_vol_ms = 0, slides = 0;
        double vol_set_before_play = -1.0;  // the volume when the first BASS_ChannelPlay came (-1: never played)
        double pan_set_before_play = -2.0;
        bool vol_set = false, pan_set = false;   // a volume / pan attribute was set or slid
        bool attrs_before_play = false;     // both were, before the first BASS_ChannelPlay
        std::vector<int16_t> pcm;           // when record_pcm
    };
    static FakeBass &get();
    const BassApi *api();                   // the table (install it with bass_set_test_api)
    void reset();                           // forgets every stream and call
    void set_speed(double s);               // drain speed (1 = real time)
    void set_playback_buffer_ms(double ms); // the playback buffer model (0 = none, the default; the real BASS: 41-49 ms)
    void set_manual_clock(bool on);         // true: time moves only by advance_ms (from 0); false: the wall clock
    void advance_ms(double ms);
    void set_record_pcm(bool on);
    void set_gvol(uint32_t v);              // BASS_CONFIG_GVOL_STREAM (10000 default)
    void fail_creates(int n);               // the next n BASS_StreamCreate calls fail (BASS_ERROR_INIT)
    void break_all();                       // every live stream becomes invalid (as if GMod re-initialised BASS)
    // snapshot accessors (the drain is brought up to date first)
    std::map<uint32_t, Stream> streams();
    Stream stream(uint32_t h);
    uint64_t calls() const;
    uint64_t calls_from(std::thread::id t) const;   // calls made on thread t
    uint32_t live() const;                  // streams created and not freed
    uint32_t created() const;

    // the BASS functions (static: they find the instance)
    static uint32_t GSA1_BASSCALL GetVersion(void);
    static uint32_t GSA1_BASSCALL GetDevice(void);
    static int GSA1_BASSCALL ErrorGetCode(void);
    static uint32_t GSA1_BASSCALL GetConfig(uint32_t option);
    static uint32_t GSA1_BASSCALL StreamCreate(uint32_t freq, uint32_t chans, uint32_t flags, void *proc, void *user);
    static int GSA1_BASSCALL StreamFree(uint32_t handle);
    static uint32_t GSA1_BASSCALL StreamPutData(uint32_t handle, const void *buffer, uint32_t length);
    static int GSA1_BASSCALL ChannelPlay(uint32_t handle, int restart);
    static int GSA1_BASSCALL ChannelPause(uint32_t handle);
    static int GSA1_BASSCALL ChannelSetAttribute(uint32_t handle, uint32_t attrib, float value);
    static uint32_t GSA1_BASSCALL ChannelGetData(uint32_t handle, void *buffer, uint32_t length);
    static uint32_t GSA1_BASSCALL ChannelIsActive(uint32_t handle);
    static int GSA1_BASSCALL ChannelSlideAttribute(uint32_t handle, uint32_t attrib, float value, uint32_t time_ms);

private:
    FakeBass();
    void note_call();                       // under m_
    Stream *find(uint32_t h);               // under m_; nullptr (and the HANDLE error) when invalid
    void drain(Stream &s, double now);      // under m_
    double clock() const;                   // under m_: the wall clock, or the manual one
    mutable std::mutex m_;
    double playback_ms_ = 0.0;
    bool manual_ = false;
    double manual_now_ = 0.0;
    BassApi api_;
    std::map<uint32_t, Stream> s_;
    uint32_t next_ = 0x10001;
    double speed_ = 1.0;
    bool record_ = false;
    uint32_t gvol_ = 10000;
    int fail_creates_ = 0;
    uint32_t created_ = 0;
    uint64_t calls_ = 0;
    std::map<std::thread::id, uint64_t> by_thread_;
};

}  // namespace gsa1
