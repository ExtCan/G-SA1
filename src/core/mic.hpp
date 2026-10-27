// G-SA1 core: the microphone's loudness for lip sync (round 0.9.4a, feature "faces": sadc docs/research/faces_wheel_ui.md
// 5 and 6.1, faces_wheel_plan.md 4.7 / 6.4 task 2).
//
// Garry's Mod's 64-bit bass.dll exports BASS's recording API (BASS_RecordInit ... BASS_RecordStart). G-SA1 already binds
// that library by GetModuleHandleW + GetProcAddress for its sound (bass.cpp); this file resolves the recording functions
// the same way (bass.cpp is not touched) and never loads a library. What it does with the microphone:
//   * open(device): BASS_RecordInit(device) (-1 = Windows' default input). BASS_ERROR_ALREADY means somebody in the
//     process (Garry's Mod) initialised that device already: then BASS_RecordSetDevice, and close() never frees it. Then
//     BASS_RecordStart(16000 Hz, mono, float, a 10 ms period, PAUSED) with a RECORDPROC that only reduces each block to
//     its RMS and peak (atomics; no Lua, no allocation, nothing kept or written on that thread).
//   * listen(on): BASS_ChannelPlay / BASS_ChannelPause - capture runs only while the talk key is held by default.
//   * level(): the last block's RMS as dBFS mapped -60..-10 dB -> 0..1 (level_of_rms), its peak, and the state "off",
//     "paused", "on" or "failed: <why in plain words>".
//   * close(): BASS_ChannelStop, and BASS_RecordFree only for a device this file initialised.
// Nothing is recorded, stored or sent: one loudness number lives in memory. Every call is made on the Lua (game) thread
// (BASS's recording device is per thread); only the RECORDPROC runs on BASS's recording thread. Linux: "not available".
// Tests inject a fake function table (set_test_api) and feed blocks through the RECORDPROC it was given.
//
// Round 0.9.4c (feature "faces" 2; sadc docs/research/phoneme_plan.md 4.2 step 2 with its Review R.8 / R.9): while
// listening and while the analysis is on (viseme_on), the RECORDPROC also runs the sound classifier (viseme.hpp) on the
// block's REAL sample count - every 10 ms hop analysed, only the newest frame published - with MXCSR's flush-to-zero and
// denormals-are-zero set around it and restored after (x86 / x86-64). The newest frame crosses to Lua in ONE 64-bit
// atomic: seq 16 bits (+1 per published frame), cls 4 (15 = none), conf 7, level 9, F1 / 4 10, F2 / 4 10, and the press
// epoch's low 8 bits (a frame of an earlier press or analysis start is "none"). The classifier's State is touched ONLY on
// the RECORDPROC's thread: a press (listen(true)), the analysis turned on, a device change (a re-init that keeps the
// speaker number), "reset_voice", close() and the tunes are atomics the RECORDPROC applies at the start of its next block
// (review R.9). The speaker number ("learn my voice") lives in that State and one published atomic, for the session only:
// it is never written to a file, a setting or the log, and never sent (owner, phoneme_plan.md 10.1 PQ7); close() - the
// module's close hook at the end of the session - forgets it. Nothing of the sound is kept beyond the 32 ms ring.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#ifdef _WIN32
#define GSA1_MICCALL __stdcall
#else
#define GSA1_MICCALL
#endif

namespace gsa1 {
namespace mic {

// BASS 2.4 (bass.h)
const uint32_t kDeviceEnabled = 1, kDeviceDefault = 2, kDeviceInit = 4;   // BASS_DEVICE_ENABLED / _DEFAULT / _INIT
const uint32_t kSampleFloat = 256;                                        // BASS_SAMPLE_FLOAT
const uint32_t kRecordPause = 0x8000;                                     // BASS_RECORD_PAUSE
const int kErrorDriver = 3, kErrorHandle = 5, kErrorInit = 8, kErrorStart = 9, kErrorAlready = 14, kErrorIllParam = 20,
          kErrorDevice = 23, kErrorNotAvail = 37, kErrorDx = 39, kErrorBusy = 46, kErrorDenied = 49, kErrorUnknown = -1;
const uint32_t kRate = 16000;                 // Hz, mono float
const uint32_t kPeriodMs = 10;                // RECORDPROC period (BASS_RecordStart's HIWORD of the flags)

struct DeviceInfo {                           // BASS_DEVICEINFO (ANSI or UTF-8 names)
    const char *name;
    const char *driver;
    uint32_t flags;
};
typedef int(GSA1_MICCALL RecordProc)(uint32_t handle, const void *buffer, uint32_t length, void *user);

struct Api {
    int(GSA1_MICCALL *RecordInit)(int device);
    int(GSA1_MICCALL *RecordFree)(void);
    int(GSA1_MICCALL *RecordGetDeviceInfo)(uint32_t device, DeviceInfo *info);
    int(GSA1_MICCALL *RecordSetDevice)(uint32_t device);
    uint32_t(GSA1_MICCALL *RecordGetDevice)(void);
    uint32_t(GSA1_MICCALL *RecordStart)(uint32_t freq, uint32_t chans, uint32_t flags, RecordProc *proc, void *user);
    int(GSA1_MICCALL *ChannelPlay)(uint32_t handle, int restart);
    int(GSA1_MICCALL *ChannelPause)(uint32_t handle);
    int(GSA1_MICCALL *ChannelStop)(uint32_t handle);
    int(GSA1_MICCALL *ErrorGetCode)(void);
};

struct Device {
    int index = 0;                // BASS's recording device number
    std::string name;             // UTF-8
    bool is_default = false;
    bool enabled = false;
};

// tests: a fake function table (nullptr: Garry's Mod's bass.dll again); closes what is open first
void set_test_api(const Api *api);

// the recording devices (BASS_RecordGetDeviceInfo); false with err when BASS's recording API is not available
bool devices(std::vector<Device> &out, std::string &err);
// opens the device (-1 = Windows' default input) paused; true when it is open (also when it was already open on it);
// false with err (the state then says "failed: <err>")
bool open(int device, std::string &err);
// starts (on) or pauses capture; false with err when nothing is open
bool listen(bool on, std::string &err);
// stops capture and frees what this file initialised (the close hook; idempotent); 0.9.4c: the session ends, so the
// classifier forgets the speaker number too (open() of another device keeps it)
void close();
// the last block's loudness (0..1, see level_of_rms) and peak (0..1, absolute sample) while capturing (0, 0 otherwise),
// and the state: "off", "paused", "on", "failed: <why>"
void level(float &level, float &peak, std::string &state);
// blocks the RECORDPROC counted since open (tests: a paused device counts none)
uint64_t blocks();
// the open device's name ("" when nothing is open); the device number
std::string device_name();
int device_index();
// true when this file initialised the open device itself (close() frees it); false when Garry's Mod had (ALREADY)
bool initialised_here();
// the RMS as dBFS mapped -60..-10 dB -> 0..1 (0 for silence)
float level_of_rms(float rms);
// one block of float samples (what the RECORDPROC does; tests may call it directly)
void feed(const float *samples, uint32_t count);
// the words for a BASS error code ("busy", "no such device", ...)
std::string error_text(int code);

// ---- round 0.9.4c: the sound classifier on the microphone's blocks (viseme.hpp) -------------------------------------
// the newest classifier frame, unpacked from the atomic. cls -1: not listening, the analysis off, no device, or no frame
// of this press yet (then level, f1, f2 and conf are 0; seq stays the last published one)
struct VisemeFrame {
    int cls = -1;                 // gsa1::viseme SIL .. FV, or -1
    float level = 0.0f;           // 0..1 (the 25 ms window, mapped like level_of_rms; 1/511 steps)
    float f1 = 0.0f, f2 = 0.0f;   // Hz (4 Hz steps; 0 = none)
    float conf = 0.0f;            // 0..1 (1/127 steps)
    uint32_t seq = 0;             // 0..65535, +1 per published frame (one per block of at least one hop)
};
// the analysis in the RECORDPROC on / off (off: only the loudness runs); turning it on starts like a press
void viseme_on(bool on);
bool viseme_is_on();
// a tune, applied at the start of the next block: "gate_min_db" 3..12 (dB), "adapt" 0 / 1 (0 also forgets the learned
// speaker number), "smooth" 0..3 (0 instant, 1 a 2-of-3 vote, 2 steadier, 3 quick), "reset_voice" (value ignored).
// false with err ("bad_argument" cases) for another name or a value out of range
bool viseme_tune(const std::string &name, double value, std::string &err);
// the newest frame (one atomic load; any thread)
void viseme_frame(VisemeFrame &out);
// the speaker number in use and the vowel frames it learned from (0: the adult prior). Session memory only.
void viseme_voice(float &g, uint32_t &frames);
// the packing (tests): frame + seq + epoch -> 64 bits, and back (cls 15 = none -> -1)
uint64_t viseme_pack(int cls, float level, float f1, float f2, float conf, uint32_t seq, uint32_t epoch);
void viseme_unpack(uint64_t v, VisemeFrame &out, uint32_t &epoch);
// tests (review R.9): how often the classifier's State was entered, how often two entries overlapped, and how often it
// was entered on the thread marked with viseme_debug_mark_thread() (the test's "Lua" thread; must stay 0)
struct VisemeDebug {
    uint64_t entries = 0, overlaps = 0, marked_thread_entries = 0;
};
void viseme_debug(VisemeDebug &out);
void viseme_debug_mark_thread();

}  // namespace mic
}  // namespace gsa1
