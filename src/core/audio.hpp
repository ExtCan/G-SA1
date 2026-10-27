// G-SA1 core: sound. libsa1's audio layer (libsa1_audio.h) decodes the game's sound banks, voices and music
// from the player's disc in memory and mixes them (positional, keep-alive / stop rules, envelopes, voices,
// jingles); Audio owns that mixer. AudioOut hands the mixed stereo PCM16 to an output device: Garry's Mod's
// own BASS library (bass.dll / libbass.so, which GMod loads and initialises for its sound.Play* API), found
// in the running process - G-SA1 never loads a library itself and writes no files. The mixer runs on the caller's
// thread (the Lua main thread in GMod); since libsa1_audio.h version 2 the disc reads (voices, jingles, music) and
// the tone decoding run on libsa1's own loader thread, so a sound event never waits for the disc there
// (sadc docs/research/gsa1_ramp_freeze.md fix 7: 27-430 ms reads on the Lua thread were the likeliest freeze).
//
// 0.5.1: opening the banks (sa1_audio_open: 1ST_READ.BIN checked, the stage and character banks and the voice
// archive's index read - 85 reads, 19-31 ms warm, seconds from a slow disc) and closing them (the loader thread is
// joined) happen on a worker thread too. The objects live on a libsa1 context of their own (sa1_init with the default,
// thread-safe allocator and files, the SOURCE coordinates, a thread-safe log callback), so the open shares nothing
// with the context the game's thread ticks; poll() hands the finished objects to the game's thread, which alone uses
// them from then on (libsa1_audio.h: one thread at a time). Sound events that come while the banks open are dropped:
// the sounds just start a little later.
//
// 0.7.0 (jukebox, plan 10.2 J1): the BASS binding lives in bass.hpp, shared with the jukebox's worker; Audio::set_duck
// lowers the game's background music while a jukebox plays (sa1_audio_mixer_duck: libsa1 ramps it, 0.5 s for a full
// swing, and spares the jingles unless asked, so the drowning countdown stays audible).
//
// 0.9.1 (sadc docs/research/gsa1_070_drown.md J1 with its review R4.4): Audio::music_state reports the game's music in
// the mixer - the jingle it plays or is about to play (drowning countdown, invincibility, speed shoes, fishing), its kind,
// length and time left, the game's music stop at the drown - from libsa1_audio.h version 4
// (sa1_audio_mixer_music_state), so the jukebox can step aside for the game's jingles; Audio::end_music ends a jingle
// whose character is gone (a respawn, a removal: the game's own restart would restart the act's music).
//
// 0.9.2a (sadc docs/research/gsa1_091a_perf.md A0 + A2 with its review RC3; the owner hears crackles): the output's queue
// is BASS's push queue only (bass_queued_frames; BASS's playback buffer, 41-49 ms on the owner's 192 kHz device, is
// latency, not cushion), and AudioOut::top_up keeps a lead of OutputLead: two frames + 30 ms as before, and at least the
// slowest frame of the last 4 s x 1.25 + 20 ms (60..250 ms). Measured with Garry's Mod's own bass.dll on the owner's PC
// (gsa1_091a_perf.md 2.3, review R.1): 0.9.1's feed ran dry 90-116 times a minute in his frame mix, the push queue alone
// 6-8, with the adaptive lead 3 (a click or a short drop-out once in 20 s instead of twice a second). In smooth play the
// lead stays at 60-63 ms as in 0.9.1 (the sound is not later); after a hitch it covers the hitches that follow it.
//
// 0.9.4a (sadc docs/research/super2_plan.md 6.4 task 4 with its review, super2_sound.md 7.1): libsa1's stage rules
// (libsa1_audio.h version 5, sa1_audio_mixer_stage_rule): a range of tones of ONE character resolves from another stage's
// sound banks, read and decoded on libsa1's loader thread - Super Sonic's aura whoosh 1035 / 1036 from the Perfect Chaos
// stage (CHAOS7B.MLT bank 5) while every other sound keeps Emerald Coast's banks. Audio keeps a registry of the rules per
// character and slot (kRuleWhoosh 0, kRuleBoardSnow 1, kRuleBoardSand 2, kRuleSpare 3: the board of 0.9.5 reuses it) and
// applies it to every mixer it installs (the first open, the Japanese-voices re-open, a disc change); stop(id) forgets the
// character with its rules. Everything runs on the mixer's thread (the Lua thread). The rings (super2_plan.md 10.3): the
// mixer option SA1_AUDIO_MIX_RESTART_REPEATS (AudioOptions::restart_repeats) keeps a fast ring line at one ring's level.
#pragma once

#include <array>
#include <cstdint>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#ifndef SA1_STATIC
#define SA1_STATIC
#endif
#include "libsa1_audio.h"
#include "bass.hpp"
#include "util.hpp"

namespace gsa1 {

typedef void (*AudioLogFn)(void *user, int32_t level, const char *message);   // must be thread-safe

struct AudioOptions {
    float master = 1.0f, sfx = 1.0f, voice = 1.0f, music = 1.0f;   // 0..4 (sa1_audio_mixer_volume)
    bool voices = true;          // character voices
    bool jingles = true;         // invincibility / speed up / drowning / 1-up
    bool bgm = false;            // background music changes the game asks for
    bool voices_3d = true;       // other players' voices from their position
    // 0.9.4a (sadc docs/research/super2_plan.md 10.3; libsa1_audio.h version 5): a one-shot sound effect a character starts
    // again while it still plays restarts instead of piling up (SA1_AUDIO_MIX_RESTART_REPEATS: a fast ring line stays at
    // one ring's level; the Dreamcast lets the same tone pile up). Without the flag in libsa1 (audio header < 5): no effect
    bool restart_repeats = true;
};

// 0.9.4a: a libsa1 stage rule (libsa1_audio.h version 5): tones first..last of one character resolve as on `stage`
// (stage -1: none - setting it clears the slot)
struct StageRule {
    int32_t stage = -1;
    uint32_t first = 0, last = 0;
};
// the slots of a character's rules (sa1_audio_mixer_stage_rule's 0..3; super2_plan.md 8: the board of 0.9.5 reuses them)
const uint32_t kRuleWhoosh = 0u, kRuleBoardSnow = 1u, kRuleBoardSand = 2u, kRuleSpare = 3u, kRuleSlots = 4u;
// Audio::rule_status: the rule is recorded but no mixer had it yet (the banks are not open); otherwise SA1_OK (0) or the
// sa1_status libsa1 refused it with (SA1_ERR_LIMIT: a fifth extra stage)
const int32_t kRuleNotApplied = 1;

// The game's music in the mixer (Audio::music_state; libsa1_audio.h version 4: sa1_audio_music_state)
struct MusicState {
    bool valid = false;          // the banks are open and libsa1 reported it (false: an older libsa1 or no mixer)
    int32_t jingle = -1;         // the music number of the jingle playing or about to play (-1 none; always -1 with
                                 // the jingles off: SA1_AUDIO_MIX_NO_JINGLES)
    float jingle_left = 0.0f;    // seconds until it ends by itself (-1: it loops, or its length is not known yet)
    bool stopped = false;        // after the game's music stop (the drown) until its next MUSIC / JINGLE / RESTORE cue
    int32_t bgm = -1;            // the background music the game asked for (-1 none)
    int32_t kind = 0;            // SA1_AUDIO_JINGLE_* (0 none, 2 the drowning countdown, 3 invincibility, 4 speed up ...)
    bool waiting = false;        // not heard yet (its file being read, its delay running)
    bool loops = false;          // its file loops (45 FISHING.ADX): until the game ends it
    float length = 0.0f;         // seconds of its file (0 while it is read)
    float time = 0.0f;           // seconds of it heard
    uint32_t started = 0, ended = 0;   // jingles started / ended since the mixer was made
    int32_t last_jingle = -1;    // the last one that ended (-1 none)
    int32_t last_end = 0;        // how: SA1_AUDIO_JINGLE_END_* (1 played, 2 restore, 3 stop, 4 music, 5 replaced, 6 host,
                                 // 7 failed)
    bool bgm_playing = false;    // the mixer's own background music is heard now
};

class Audio {
public:
    Audio() {}
    ~Audio();
    Audio(const Audio &) = delete;
    Audio &operator=(const Audio &) = delete;

    // the log callback of the sound banks' context (thread-safe; called on the worker too)
    void set_log(AudioLogFn fn, void *user)
    {
        log_fn_ = fn;
        log_user_ = user;
    }
    // Starts opening on a worker thread: sa1_audio_open (Emerald Coast's stage banks, every character's banks) and a
    // 44.1 kHz stereo mixer on a private context. The banks open now (and an open still running) are closed on a
    // worker, without waiting. poll() installs the result.
    void open_async(const std::string &gdi, bool japanese);
    // game thread: 1 = opened just now (msg: what opened), -1 = failed just now (msg: why), 0 = nothing new
    int poll(std::string &msg);
    bool opening() const { return pending_ != nullptr; }
    void wait();                         // blocks until a running open has finished (tests); poll() afterwards
    // the same on the calling thread (tests)
    bool open(const std::string &gdi, bool japanese, std::string &err);
    // closes without waiting (the objects are closed on a worker); shutdown() also joins every worker (unload)
    void close();
    void shutdown();
    bool is_open() const { return cur_.mixer != nullptr; }
    bool japanese() const { return japanese_; }
    double open_ms() const { return open_ms_; }          // on the worker
    double opening_ms() const;                           // how long the running open has taken so far
    const std::string &notes() const { return notes_; }  // "" or what is missing (SA1_PARTIAL)
    const std::string &open_error() const { return open_error_; }

    void apply(const AudioOptions &o);
    const AudioOptions &options() const { return opt_; }
    // the host's duck of the game's music (gsa1.AudioDuck, while a jukebox plays): the background music x gain (0..1),
    // the jingles too only with jingles = true; libsa1 ramps it (sa1_audio_mixer_duck). Kept across a re-open (a new
    // mixer starts ducked). On top of the music volume (AudioOptions::music keeps its value). false: a bad argument.
    bool set_duck(float gain, bool jingles);
    float duck() const { return duck_; }
    bool duck_jingles() const { return duck_jingles_; }
    void event(const sa1_event &e);
    void character(int32_t id, const float pos[3], bool local);
    void stop(int32_t id);           // 0 = everything (the rules stay); id: its sounds end and its rules are forgotten
    void listener(const float pos[3], const float fwd[3], const float up[3]);
    bool render(int16_t *out, uint32_t frames);
    uint32_t active() const;
    // the loader thread's counters (sa1_audio_get_stats); false when not open
    bool stats(sa1_audio_stats &out) const;
    // the game's music state in the mixer (0.9.1; on the mixer's thread, the Lua thread: no lock, no allocation, no disc
    // access); false (out.valid false) when the banks are not open or libsa1_audio.h is older than version 4
    bool music_state(MusicState &out) const;
    // the file of a music number ("TIMER.ADX"); "" when the banks are not open or there is no such number
    std::string music_name(int32_t music) const;
    // ends the game's music in the mixer - the jingle (its end: SA1_AUDIO_JINGLE_END_HOST) and the music stop flag - and
    // every sound (sa1_audio_mixer_stop(mixer, 0)); false when the banks are not open
    bool end_music();
    // 0.9.4a: stage rules (above). has_stage_rules: this libsa1 has them (SA1_AUDIO_HAS_STAGE_RULES). set_stage_rule
    // records the rule of `slot` for character id (> 0; r.stage -1 clears the slot) and applies it to the mixer when there
    // is one (otherwise at the next install); false: a bad id or slot, no stage rules, or the mixer refused it (then
    // rule_status says why; the rule stays recorded and is tried again at the next install). stage_rule: the registry's
    // rule (false: none in that slot). rule_status: kRuleNotApplied, SA1_OK or libsa1's refusal (-1000: no rule).
    // stage_state: SA1_AUDIO_STAGE_* of an extra stage in the open banks (-1 without stage rules or banks; no disc access).
    // rule_characters: characters with at least one rule.
    bool has_stage_rules() const;
    bool set_stage_rule(int32_t id, uint32_t slot, const StageRule &r);
    bool stage_rule(int32_t id, uint32_t slot, StageRule &out) const;
    int32_t rule_status(int32_t id, uint32_t slot) const;
    int32_t stage_state(int32_t stage) const;
    size_t rule_characters() const;
    uint64_t rules_applied() const { return rules_applied_; }   // sa1_audio_mixer_stage_rule calls that succeeded
    uint64_t rules_refused() const { return rules_refused_; }   // ... and that libsa1 refused
    uint64_t events() const { return events_; }
    uint64_t sound_events() const { return sound_events_; }
    uint64_t frames_rendered() const { return frames_; }
    static const uint32_t kRate = 44100;

    // one opened set: its context, the audio object and its mixer
    struct Handle {
        sa1_context *ctx = nullptr;
        sa1_audio *audio = nullptr;
        sa1_audio_mixer *mixer = nullptr;
    };

private:
    struct Pending {
        std::mutex m;
        bool done = false, abandoned = false;
        Handle h;
        bool ok = false, japanese = false;
        std::string error, notes;
        double ms = 0.0;
    };
    void abandon_pending();
    void close_later(Handle h);
    // 0.9.4a: one character's rules and the status of their last application
    struct RuleSet {
        std::array<StageRule, kRuleSlots> rule{};
        std::array<int32_t, kRuleSlots> status{};
    };
    int32_t apply_rule(int32_t id, uint32_t slot, const StageRule &r);   // to the mixer now (kRuleNotApplied: none)
    void apply_rules();                                                  // every recorded rule (a new mixer)

    std::map<int32_t, RuleSet> rules_;
    uint64_t rules_applied_ = 0, rules_refused_ = 0;
    Handle cur_;
    std::shared_ptr<Pending> pending_;
    std::unique_ptr<Worker> pending_worker_;
    double pending_t0_ = 0.0;
    Graveyard graveyard_;
    AudioLogFn log_fn_ = nullptr;
    void *log_user_ = nullptr;
    bool japanese_ = false;
    double open_ms_ = 0.0;
    std::string notes_, open_error_;
    AudioOptions opt_;
    float duck_ = 1.0f;
    bool duck_jingles_ = false;
    uint64_t events_ = 0, sound_events_ = 0, frames_ = 0;
};

// How far ahead the game's sound is kept queued (0.9.2a; gsa1_091a_perf.md 2.3 "adaptive lead", fix A2):
// max(2 x frame + 30 ms, the slowest frame of the last 4 s x 1.25 + 20 ms), clamped to 60..250 ms. update() is called
// once per Lua frame with that frame's time (RealFrameTime) before the top-up.
class OutputLead {
public:
    static constexpr double kMin = 0.06, kMax = 0.25, kWindow = 4.0;
    double update(double frame_s);         // records a frame (seconds), returns the lead (seconds)
    double lead() const { return lead_; }
    double slowest() const;                // the slowest frame in the window (seconds)
    void reset();

private:
    std::deque<double> win_;               // the frames of the last kWindow seconds, oldest first
    double sum_ = 0.0;
    double lead_ = kMin;
};

// The output device: a push stream on GMod's BASS (only if the process has already loaded it; bass.hpp).
class AudioOut {
public:
    AudioOut() {}
    ~AudioOut();
    AudioOut(const AudioOut &) = delete;
    AudioOut &operator=(const AudioOut &) = delete;

    bool start(uint32_t rate, std::string &err);
    void stop();
    bool running() const { return stream_ != 0; }
    // frames waiting in the push queue (0.9.2a: not BASS's playback buffer, which is latency; bass.hpp)
    uint32_t queued_frames() const;
    // frames in BASS's playback buffer (diagnostics)
    uint32_t playback_frames() const;
    // 0.9.2a: once per Lua frame (gsa1.AudioUpdate): records the frame time and returns how many frames to mix and push
    // now to keep the lead (OutputLead) queued (0: enough is queued); the caller renders them and calls push()
    uint32_t top_up(double frame_s);
    double lead_ms() const { return lead_.lead() * 1000.0; }
    bool push(const int16_t *pcm, uint32_t frames);
    void pause(bool paused);
    bool paused() const { return paused_; }
    void volume(float v);
    // BASS's global stream volume 0..10000 (Garry's Mod sets it from its own volume settings when it manages
    // it); -1 if unknown
    int32_t global_stream_volume() const;
    std::string name() const { return name_; }
    std::string last_error() const { return error_; }
    uint64_t underruns() const { return underruns_; }

private:
    bool bind(std::string &err);
    uint32_t stream_ = 0;
    uint32_t rate_ = 44100;
    bool paused_ = false;
    float volume_ = -1.0f;
    std::string name_ = "none";
    std::string error_;
    uint64_t underruns_ = 0;
    OutputLead lead_;
    const BassApi *fn_ = nullptr;    // bass_acquire (released by the destructor)
};

}  // namespace gsa1
