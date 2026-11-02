// G-SA1 core: the feature "follower" (round 0.9.8: sadc docs/research/gsa1_098_plan.md 2.4, 5.5, 6.6; gsa1_096_plan.md 4.10-4.17,
// 5.5, 6.4; follow096_gsa1.md 4.2): what G-SA1 keeps per follower. The world itself is libsa1's (sa1_follower_*, libsa1.h
// "followers"): the game's own 1.5P AI steers slot 1 of a world of its own. A follower is an ordinary Character of the
// session (Character::follower); this set holds the leader links and the host-fed leaders' states. No GMod dependency; nothing
// here calls libsa1, so tests/feat_follower_test.cpp drives it without a disc and against any libsa1.h.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace gsa1 {

struct UpgradeDef;

// a host-fed leader's state for the next tick (host space: HU, HU/s, radians here; the module converts Lua's degrees)
struct LeaderFeed {
    bool valid = false;
    float pos[3] = {0, 0, 0}, vel[3] = {0, 0, 0};
    float yaw = 0.0f;
    bool ground = true;
    int32_t kind = -1;                 // the SA1_CHAR_* whose physics row gives the jog / run speeds the AI compares; -1: Sonic's
};

// FollowerCreate's opts (plan 5.5)
struct FollowerOpts {
    std::vector<const UpgradeDef *> upgrades;
    uint32_t objects = 1;              // 0: no SET records in its world (SA1_FOLLOW_NO_SET); 1: its own game's
    bool sounds = true;                // false: no sound of this follower reaches the mixer, and it never registers there
    bool seed_given = false;
    uint32_t seed = 0;                 // SA1_FOLLOW_SEED: srand of the world
    bool fix_view = true;              // false: SA1_FOLLOW_GAME_VIEW
    bool fix_respawn = true;           // false: SA1_FOLLOW_GAME_HISTORY
};

// the draw levels (gsa1.FollowerDraw, gsa1.FOLLOWER.DRAW_*; decision 096 4.10)
const uint32_t kFollowerDrawFull = 1, kFollowerDrawFar = 2, kFollowerDrawNone = 3;
const uint32_t kFollowerRateMin = 5, kFollowerRateMax = 30, kFollowerRateDefault = 15;
// a level 2 follower renders on the frames (frame + id) % follower_far_every(rate) == 0: round(60 / rate) frames apart,
// staggered by id (rate pictures a second at 60 frames a second)
uint32_t follower_far_every(uint32_t rate);
bool follower_far_due(uint64_t frame, int32_t id, uint32_t rate);

// The followers of one session. A leader is a character id of the same session (a libsa1 leader: exact, per step) or 0 (host-fed:
// feed() before every tick). levels() puts every leader before its followers (Kahn's algorithm over the leader links): one job
// phase per level (a follower whose leader is not a follower is in level 0), so a chain ticks in one pass.
class FollowerSet {
public:
    bool is_follower(int32_t id) const;
    int32_t leader_of(int32_t id) const;                  // 0: host-fed, -1: not a follower
    int32_t kind_of(int32_t id) const;                    // -1: not a follower
    const FollowerOpts *opts_of(int32_t id) const;
    // false + err "a follower cannot follow itself or one of its own followers" for a cycle (follower 0: a follower to be)
    bool can_follow(int32_t follower, int32_t leader, std::string &err) const;
    void add(int32_t id, int32_t kind, int32_t leader, const FollowerOpts &o);
    void set_leader(int32_t id, int32_t leader);          // leader 0: host-fed (the last feed stays valid)
    void feed(int32_t id, const LeaderFeed &f);
    const LeaderFeed *feed_of(int32_t id) const;
    void remove(int32_t id);
    // a destroyed character: every follower of it becomes host-fed with the leader's last state (libsa1 does the same in its
    // worlds: SA1_FOLLOW_EV_LEADER_LOST arg 0); returns how many
    size_t leader_gone(int32_t id, const float last_pos[3], float last_yaw);
    // the head of id's chain: the leader of the chain's first follower (a character that is no follower), 0 when the chain is
    // host-fed, -1 when id is no follower
    int32_t root_of(int32_t id) const;
    // the chain levels and all of them in order; recomputed only after a change of the links (no allocation per frame)
    const std::vector<std::vector<int32_t>> &levels() const;
    const std::vector<int32_t> &order() const;
    size_t count() const { return list_.size(); }
    uint32_t generation() const { return gen_; }          // changes with the links

private:
    struct Entry {
        int32_t id, kind, leader;
        FollowerOpts opt;
        LeaderFeed feed;
    };
    const Entry *find(int32_t id) const;
    Entry *find(int32_t id);
    void rebuild() const;
    std::vector<Entry> list_;
    uint32_t gen_ = 0;
    mutable bool dirty_ = true;
    mutable std::vector<std::vector<int32_t>> levels_;
    mutable std::vector<int32_t> order_;
};

// ---- the sound rules of a follower's events (decision 096 4.17, 3.6; Session::admit_sound and Session::take_events) ---------
// SA1_EVENT_* numbers are libsa1's (session.cpp ties them to the macros with a static_assert)
const uint32_t kEventSound = 1u, kEventSoundStop = 2u, kEventVoice = 3u, kEventJingle = 4u, kEventRumble = 5u;
// may a follower's event go on to the mixer's guards? A jingle or music cue never; a stop always (what plays ends); a sound or
// a voice only with the follower's sounds on. Every other event: yes (the mixer ignores it)
bool follower_event_mixes(uint32_t type, bool sounds);
// does a follower's event reach Lua? Its SOUND, SOUND_STOP, VOICE, JINGLE and RUMBLE are mixed (or dropped) in the module and
// never queued (99 followers' footsteps); every other event (DEATH, RESTART, FAULT, CAPACITY, BOARD, FOLLOW, the SET and
// host-object queues) reaches Lua with e.character = the follower's id
bool follower_event_for_lua(uint32_t type);

// ---- the memory guard (decision 096 4.14; follow096_scale.md 3.2: a playing follower holds about 21 MB) -----------------------
const uint64_t kFollowerMemoryGuardMb = 2073;     // 2 GB + 25 MB
// the system's available physical memory in bytes (GlobalMemoryStatusEx ullAvailPhys; /proc/meminfo MemAvailable on Linux);
// UINT64_MAX when it cannot be read
uint64_t available_physical_bytes();
// tests: the value the guard reads instead (nullptr: the real one)
using MemoryProbe = uint64_t (*)();
void set_memory_probe(MemoryProbe p);
// false: refuse a new follower ("limit", kReasonMemory)
bool follower_memory_ok();

extern const char *const kReasonCycle;     // "a follower cannot follow itself or one of its own followers"
extern const char *const kReasonMemory;    // "not enough free memory"
extern const char *const kReasonMaxChars;  // "too many characters"
extern const char *const kReasonMaxFollowers;   // "too many followers"
extern const char *const kReasonNoApi;     // "this libsa1 has no followers (round 0.9.8, SA1_API_FOLLOWER)"

}  // namespace gsa1
