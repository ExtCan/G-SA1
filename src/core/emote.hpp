// G-SA1 core: the shared part of the feature "emote" (round 0.9.4a: sadc docs/research/faces_wheel_plan.md 4.5, 4.6,
// 5.6 with its Review R.9 / R.16 / R.18; libsa1.h "emotes", SA1_API_EMOTE). The module's Lua functions
// (src/module/bind_emote.cpp) and the offline test on the disc (tests/feat_emote_test.cpp) use it: the slot keys, a
// character's catalogue as a vector, one play call. Nothing here keeps state; everything runs on the caller's thread
// (the game's: the context is not thread-safe).
//
// Keys: an action row is "a<row>" (SA1_EMOTE_ROW), an extra motion "x<index>" (SA1_EMOTE_EXTRA, the index among the
// kind's offered extras in list order) - the keys of data/gsa1/emote_wheel.txt (faces_wheel_plan.md 8.1); round 100-EV
// (sadc docs/research/emotes_ev.md 7.2): a cutscene animation "e<index>" (SA1_EMOTE_EVENT, its place among the kind's
// cutscene animations), loaded from the disc first (EmoteEventPool below: never on the game's thread).
#ifndef GSA1_EMOTE_HPP
#define GSA1_EMOTE_HPP

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "libsa1.h"

namespace gsa1 {

#if defined(SA1_API_EMOTE)
const bool kEmoteApi = true;
#else
const bool kEmoteApi = false;
#endif

// G-SA1's own play flag (gsa1.EMOTE.LOOP): the item plays SA1_EMOTE_PLAY_LOOP ("loop it" on a wheel slot)
const uint32_t kEmoteLoop = 0x100u;
// the libsa1 flags a caller may pass through (SA1_EMOTE_IN_AIR | KEEP_INPUT | NO_PROPS | NO_TRAIL, and SA1_EMOTE_HOLD
// with SA1_API_EMOTE_HOLD: round 0.9.4b, the wheel's "Hold the last pose"); SA1_EMOTE_CHAIN is always set by emote_play
// (0 without SA1_API_EMOTE)
uint32_t emote_pass_flags();
// the highest key index accepted ("a999")
const uint32_t kEmoteKeyMax = 999u;

struct EmoteEntry {
    std::string key;            // "a75" / "x3"
    uint32_t source = 0;        // SA1_EMOTE_ROW / SA1_EMOTE_EXTRA
    uint32_t index = 0;
    std::string name;           // the internal name ("s_kimepose0"); may be empty
    std::string label;          // the SA Tools label
    uint32_t cls = 0;           // SA1_EMOTE_CLASS_*
    uint32_t flags = 0;         // SA1_EMOTE_F_*
    uint32_t frames = 0;        // NJS_MOTION.nbFrame
    int32_t play = 0;           // SA1_EMOTE_PLAY_LOOP / SA1_EMOTE_PLAY_ONCE
    int32_t dup_of = -1;        // the list position (0-based) of the first entry with the same drawn object and motion
    // round 100-EV: a cutscene animation's fields (sa1_emote_info; 0 / empty for rows and extras)
    uint32_t event = 0;         // its cutscene (3 = EV0003)
    uint32_t event_order = 0;   // 1.. ("EV0003 #2")
    uint32_t cast = 0;          // bit (1 << SA1_CHAR_*) per character with animations in that cutscene
    float pace = 0.0f;          // the cutscene's speed (frames per 1/30 s)
    float lift = 0.0f;          // SA1 units (SA1_EMOTE_F_LIFTED)
    std::vector<uint32_t> events;   // the cutscenes that use it, ascending
};

// round 100-EV: the source number of a cutscene animation (SA1_EMOTE_EVENT; 2 without the API)
const uint32_t kEmoteSourceEvent = 2u;
// round 100-EV: the Notes column's plain words of an entry ("lifted onto the floor, in 21 cutscenes"; "" for none)
std::string emote_notes(const EmoteEntry &e);
// round 100-EV: the names of the characters of a cast mask ("sonic", "tails", ...: GSA1.CHARACTERS' names of the kinds)
std::vector<std::string> emote_cast_names(uint32_t cast);
// round 100-EV: the plain words of a failed cutscene load (sa1_emote_event_load / _ready's status)
std::string emote_event_error(sa1_status st, uint32_t event);

// round 100-EV (emotes_ev.md 3.3, 4.2 with its review RX.6): the cutscene loads on a thread of their own, one at a time,
// for one context. queue() never blocks (a key already queued or ready is not queued again); drain() drops what is queued
// and waits for the load that runs - G-SA1 calls it before anything unloads the disc or ends the context (gsa1.Shutdown,
// the module's close), as libsa1's rule asks (sa1_emote_event_load never runs beside sa1_unload_disc / sa1_shutdown).
class EmoteEventPool {
public:
    EmoteEventPool() = default;
    ~EmoteEventPool() { drain(); }
    EmoteEventPool(const EmoteEventPool &) = delete;
    EmoteEventPool &operator=(const EmoteEventPool &) = delete;
    // false: no API, or more than 1024 waiting
    bool queue(sa1_context *ctx, int32_t kind, uint32_t index);
    void drain();
    size_t waiting();
    // loads finished (any status) and dropped by drain(), since the pool was made (tests)
    uint64_t done() const { return done_; }
    uint64_t dropped() const { return dropped_; }
    // r1-fix-ev: loads put in the queue (a key already queued or running is not counted again), since the pool was made
    // (tests: every queued load is done or dropped, queued() == done() + dropped() once none is waiting)
    uint64_t queued() const { return queued_; }
    // the last finished load's status (tests)
    sa1_status last_status() const { return last_; }

private:
    struct Job {
        sa1_context *ctx;
        int32_t kind;
        uint32_t index;
    };
    void run();
    std::mutex m_;
    std::condition_variable cv_;
    std::deque<Job> q_;
    std::thread t_;
    bool busy_ = false, stop_ = false;
    Job cur_ = {nullptr, 0, 0};
    volatile uint64_t done_ = 0, dropped_ = 0, queued_ = 0;
    volatile sa1_status last_ = 0;
};

// "a<row>" / "x<extra>" with 0..kEmoteKeyMax (no sign, no blanks, no leading zeros but "0") -> source, index
bool emote_parse_key(const std::string &key, uint32_t &source, uint32_t &index);
std::string emote_key(uint32_t source, uint32_t index);
// how an entry plays by default: "hold" (SA1_EMOTE_F_HOLD: once, the game holds the last frame), "loop", "once"
const char *emote_play_name(int32_t play, uint32_t flags);
// the class's word ("stand", "idle", "pose", ..., "super"); "?" for an unknown class
const char *emote_class_name(uint32_t cls);
// the catalogue of (kind, form): sa1_emote_count / sa1_emote_get. false + err without the disc or the API; an empty list
// (Eggman, Tikal, a kind without the form) is true
bool emote_list(const sa1_context *ctx, int32_t kind, uint32_t form, std::vector<EmoteEntry> &out, std::string &err);
// plays one entry on character id (latched by libsa1, started at the character's next pair): one item, SA1_EMOTE_CHAIN,
// link -1 (8 frames), speed 1; flags = kEmoteLoop | emote_pass_flags() bits. SA1_ERR_UNSUPPORTED without the API
sa1_status emote_play(sa1_context *ctx, int32_t id, uint32_t source, uint32_t index, uint32_t flags);
// sa1_character_emote_stop (how: SA1_EMOTE_STOP_NOW / STOP_BLEND)
sa1_status emote_stop(sa1_context *ctx, int32_t id, uint32_t how);
// the reason of a failed call in libsa1's plain words (sa1_last_error, else the status text)
std::string emote_error(const sa1_context *ctx, sa1_status st);
// the module's code word of a failed status: "unsupported", "bad_argument", "not_found", "limit", "not_ready", "fault",
// "error"
const char *emote_code(sa1_status st);

}  // namespace gsa1

#endif
