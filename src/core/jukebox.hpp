// G-SA1 core: the jukebox engine (sadc docs/research/jukebox.md 6.3 with its Review, plan gsa1_rounds_plan.md 10.2,
// work item J1). The game's music from the player's own disc, played through Garry's Mod's BASS while the Lua thread
// hitches: no GMod dependency, so tests/feat_jukebox_test.cpp drives exactly the code the module runs.
//
// Threads and ownership (Review G1):
//   * one worker thread owns a libsa1 context of its own and a music-only audio object on it (SA1_AUDIO_MUSIC_ONLY |
//     SA1_AUDIO_LAZY_STREAMS | SA1_AUDIO_SYNC_LOADS: no banks, no voice archive, no loader thread; a stream's open reads
//     2 sectors and the file is read on as decoding reaches it), and EVERY BASS handle of the jukebox: it creates,
//     feeds, slides, pauses and frees them. libsa1's one-thread-per-object rule holds because only it touches them.
//   * the Lua thread (the module's bindings) only posts commands and targets (volume, place, listener, GMod's volume
//     and music volume, the game's pause) into a mutex-protected mailbox and reads the worker's published snapshot; it
//     never calls BASS. Every new stream gets the current gain and pan before its first BASS_ChannelPlay.
//   * the worker wakes on a command or every 20 ms.
// Disc and track list (Review G5, G15): the .gdi path is given by the caller (the module reads it with
//   gsa1::load_config, as gsa1.Init does), so the jukebox works without a character and before gsa1.Init. At start the
//   worker reads sa1_audio_music_info for every music number (ADVERTISE.PRS once, 2 sectors per ADX header) and
//   publishes the immutable list of the 109 tracks on the disc (69 NIGHTS_K.ADX is named by the game but absent).
// Channels: 0 = the personal jukebox (2D); 1-4 exist for placed (3D) jukeboxes, unused until the owner approves the
//   world jukebox (J3); their gain is the game's distance curve (libsa1's sa1_audio_mix.c spatial) with
//   near = far / 30 (SA1A_NEAR 20 / SA1A_FAR 600, Review R2.7).
// Plans (jukebox.md 6.3): "forever" loops at the header loop like the game and its sound test (a file without a loop
//   starts again at 0: a jukebox choice, the sound test plays such a file once, Review R2.2); "loops" n plays to
//   loop_start + n x loop length, then fades out over fade_out seconds (a file without a loop plays once); "once" plays
//   to the end of the file, the loop ignored. Plan time t is a source frame (jb_source_frame). A start beyond the plan's
//   end is "ended" at once.
// Feeding (Review G2): one push stream per playing channel at the track's own rate (BASS resamples 32 kHz tracks), with
//   3 s queued; the PCM is the decoder's (fades are envelopes on it), the volume and pan are BASS attributes. Every wake
//   tops every channel up first; then at most one blocking open (a stream open + seek: with lazy streams the seek reads
//   the file up to the start); a seek or a track change makes a new stream and slides the old one to 0 over 50 ms.
//   No prefetch: with lazy streams an open reads 2 sectors (the first decode about 256 KB), and the Lua API has no
//   "next track" call, so a playlist's next track starts with a fresh open.
// Start anchoring (Review G3): a play carries the module clock of the call; the start frame is computed when pushing
//   begins: start + (now - call). Position = frames pushed - frames queued, as plan time.
// Level (Review G8): volume 1 is the game's music level, 8C6445EA(h, -10) = -1.0 dB (gain 0.891; that 8C6445EA is
//   ADXT_SetOutVol in 0.1 dB is UNVERIFIED, the pause value -960 supports it); 99 of 109 files peak at full scale.
// BASS errors (Review G10): a failed BASS_StreamPutData or a stream that BASS no longer knows is re-created at its
//   position and counted (status: recoveries, error). Shutdown joins the worker, which may be inside one disc read
//   (bounded by one read call: a lazy stream reads 256 KB at a time); every BASS stream is freed there, BASS itself is
//   GMod's and stays.
#pragma once

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "audio.hpp"
#include "bass.hpp"
#include "util.hpp"

namespace gsa1 {

const int kJukeboxChannels = 5;                 // 0 personal (2D), 1-4 placed (3D; unused until J3)
const double kJukeboxReference = 0.89125093813; // volume 1 = the game's music level (-1 dB)
const double kJukeboxShort = 25.0;              // jukebox.md 1.5: "short" = no loop and under 25 s

enum class JbPlan : int { Forever = 0, Loops = 1, Once = 2 };
enum class JbState : int { Idle = 0, Loading, Playing, Paused, Ended, Failed };
const char *jb_plan_name(JbPlan p);
bool jb_plan_parse(const std::string &s, JbPlan &out);    // "forever" | "loops" | "once"
const char *jb_state_name(JbState s);                     // "idle" "loading" "playing" "paused" "ended" "failed"

// one track on the disc (sa1_audio_music_info)
struct JbTrack {
    uint32_t music = 0;
    std::string file;               // "ECOAST1.ADX"
    std::string title;              // the game's sound-test title, or the file name (has_title false)
    bool has_title = false;
    int32_t page = -1, entry = -1;  // sound-test page 0..5 and position 0..; -1 when not in the sound test
    uint32_t flags = 0;             // SA1_AUDIO_MUSIC_*
    uint32_t channels = 0, rate = 0, frames = 0, file_size = 0;
    bool loop = false;
    uint32_t loop_start = 0, loop_end = 0;   // frames; without a loop 0 and frames
    bool listed() const { return (flags & SA1_AUDIO_MUSIC_LISTED) != 0; }
    bool jingle() const { return (flags & SA1_AUDIO_MUSIC_JINGLE) != 0; }
    bool truncated() const { return (flags & SA1_AUDIO_MUSIC_TRUNCATED) != 0; }
    bool is_short() const { return !loop && rate && (double)frames < kJukeboxShort * rate; }
    double seconds() const { return rate ? (double)frames / rate : 0.0; }
};

struct JbPlanSpec {
    JbPlan plan = JbPlan::Forever;
    int32_t loops = 2;              // "loops": complete passes through the loop
    double fade_in = 0.0;           // seconds at the start of the play
    double fade_out = 0.0;          // "loops": seconds after the last loop
};

// the plan's arithmetic, in frames of the track's rate (pure; tests)
const uint64_t kJbForever = ~(uint64_t)0;
uint64_t jb_plan_end(const JbTrack &t, const JbPlanSpec &p);                     // plan frame of the end, kJbForever
bool jb_plan_wraps(const JbTrack &t, const JbPlanSpec &p);                       // the plan repeats a region
uint32_t jb_source_frame(const JbTrack &t, const JbPlanSpec &p, uint64_t plan_frame);
uint32_t jb_loops_done(const JbTrack &t, const JbPlanSpec &p, uint64_t plan_frame);

// a placed channel's gain and pan (BASS pan: -1 left .. +1 right) for a listener; radius = the far distance (silent
// from 0.84 x radius on), host units. The game's curve: libsa1 sa1_audio_mix.c spatial with near = far / 30.
void jb_spatial(const float eye[3], const float fwd[3], const float up[3], const float pos[3], double radius,
                float &gain, float &pan);
// a channel's BASS volume: volume (0..1) x the game's reference level x Garry's Mod's volume when GMod does not scale
// BASS's streams itself (gvol: BASS_CONFIG_GVOL_STREAM, -1 unknown; the rule of gsa1.AudioUpdate) x the music volume
// (snd_musicvolume when the addon follows it, else 1) x the spatial gain
double jb_gain(double volume, double gmod_volume, int32_t gvol, double music_volume, double spatial);

struct JbChannelInfo {
    int32_t music = -1;
    JbState state = JbState::Idle;
    JbPlanSpec spec;
    double position = 0.0;          // plan seconds (frames pushed - frames queued)
    double track_position = 0.0;    // seconds in the file (the loop folded in)
    double length = 0.0;            // the track's length, seconds
    double plan_length = 0.0;       // plan seconds to the plan's end (0: forever)
    uint32_t loops_done = 0;
    std::string error;
    bool paused = false;            // JukeboxPause
    bool placed = false;
    double volume = 1.0;
    double gain = 0.0;              // the BASS volume applied last
    double queued = 0.0;            // seconds queued in BASS
    uint32_t rate = 0;
    uint64_t start_frame = 0;       // plan frame of the current stream's first frame
    uint64_t generation = 0;        // plays and seeks made (tests)
    uint32_t handle = 0;            // the current BASS stream (tests)
    double snapshot_ms = 0.0;
};

struct JbStatusInfo {
    bool started = false, ready = false, failed = false, titles = false;
    uint32_t tracks = 0, listed = 0;
    uint32_t active = 0;            // channels loading, playing or paused
    double memory_mb = 0.0;         // the jukebox context's live allocations (streams hold their file)
    int64_t memory_blocks = 0;
    double max_open_ms = 0.0;       // the slowest open (stream open + seek)
    double list_ms = 0.0;           // the track list's build
    uint64_t opens = 0, underruns = 0, recoveries = 0;
    int32_t gvol = -1;
    std::string error, backend;
};

struct JukeboxConfig {
    std::string gdi;                    // the player's .gdi
    const BassApi *bass = nullptr;      // the output (a test's FakeBass); nullptr: plays fail, unless acquire_bass
    bool acquire_bass = false;          // the worker binds the process's BASS itself (bass_acquire / bass_release on
                                        // the worker: the module's way, so the Lua thread makes no BASS call at all)
    AudioLogFn log = nullptr;           // thread-safe (called on the worker)
    void *log_user = nullptr;
    const sa1_host *host = nullptr;     // tests: allocator / file callbacks (thread-safe) of the private context
    double queue_s = 3.0;               // seconds kept queued per channel
    double block_s = 0.25;              // decode block
    double wake_ms = 20.0;
};

class Jukebox {
public:
    Jukebox();
    ~Jukebox();
    Jukebox(const Jukebox &) = delete;
    Jukebox &operator=(const Jukebox &) = delete;

    // starts the worker (returns at once); a running jukebox is shut down first. Volumes, places and the listener
    // (posted before or between starts) are kept.
    bool start(const JukeboxConfig &cfg, std::string &err);
    // joins the worker (it may be inside one disc read), frees every BASS stream and closes the libsa1 objects
    void shutdown();
    bool started() const { return started_; }
    const std::string &gdi() const { return cfg_.gdi; }

    // ---- the Lua thread ----
    // 1: the list; 0: loading; -1: failed (msg)
    int tracks(std::shared_ptr<const std::vector<JbTrack>> &out, std::string &msg) const;
    // false with err for a bad argument or a track that is not on the disc (the channel then reports "failed")
    bool play(int ch, uint32_t music, double start_s, const JbPlanSpec &spec, double call_time_s, std::string &err);
    bool stop(int ch, double fade_s);
    bool pause(int ch, bool paused);
    bool seek(int ch, double t_s);
    bool sync(int ch, double t_s, double call_time_s);   // seeks when the position is more than 0.25 s off
    bool volume(int ch, double v);
    bool place(int ch, const float pos[3], double radius);
    bool place_2d(int ch);
    // every frame: the listener, GMod's volume, the music volume and the game's pause; returns the audible channels
    int update(const float eye[3], const float fwd[3], const float up[3], double gmod_volume, double music_volume,
               bool paused);
    JbChannelInfo state(int ch) const;
    JbStatusInfo status() const;
    double clock_s() const;            // the clock plays use (now_ms / 1000)

    struct Impl;                       // the worker's side (jukebox.cpp)

private:
    struct Cmd {
        enum Type { Play, Stop, Pause, Seek, Sync } type = Play;
        int ch = 0;
        uint32_t music = 0;
        JbPlanSpec spec;
        double t = 0.0, call = 0.0, fade = 0.0;
        bool paused = false;
    };
    struct Target {
        double volume = 1.0;
        bool placed = false;
        float pos[3] = {0, 0, 0};
        double radius = 1500.0;
    };
    struct Shared {                    // under m_
        std::deque<Cmd> cmds;
        Target tgt[kJukeboxChannels];
        bool have_listener = false;
        float eye[3] = {0, 0, 0}, fwd[3] = {1, 0, 0}, up[3] = {0, 0, 1};
        double gmod_volume = 1.0, music_volume = 1.0;
        bool game_paused = false;
        bool quit = false;
        uint64_t kicks = 0;
    };
    void post(const Cmd &c);
    void run();                        // the worker

    JukeboxConfig cfg_;
    bool started_ = false;
    std::unique_ptr<Worker> worker_;
    mutable std::mutex m_;             // the mailbox
    std::condition_variable cv_;
    Shared sh_;
    mutable std::mutex snap_m_;        // the published snapshot
    JbChannelInfo snap_[kJukeboxChannels];
    JbStatusInfo status_;
    std::shared_ptr<const std::vector<JbTrack>> list_;
    std::vector<int32_t> index_;       // music number -> list index (-1: not on the disc); with list_
    uint32_t music_count_ = 0;
    std::unique_ptr<Impl> impl_;
};

}  // namespace gsa1
