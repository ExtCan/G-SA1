// feat_follower_test: the follower feature's core (round 0.9.8: sadc docs/research/gsa1_098_plan.md 2.4, 6.6; gsa1_096_plan.md 6.4
// task 6 with its Review R.1; follow096_gsa1.md 9.2) - src/core/follower.{hpp,cpp} and the session's follower parts
// (session.cpp admit_sound, take_event, commit_movers, destroy, batch_black; session.hpp kMaxCharacters, rumble_allowed), offline:
// linked like core_test (the core and libsa1) by build.py and run with --gdi when there is one.
//
//   feat_follower_test [--gdi GAME.gdi]
//
// Without the disc (fails before 0.9.8: nothing of it exists):
//   * FollowerSet: the levels of a chain of 4 and of two trees; cycles refused; set_leader; leader_gone turns the followers
//     host-fed with the last state; root_of; the levels are recomputed only after a change of the links;
//   * the far rate: round(60 / rate) frames apart, staggered by id;
//   * the sound rules through Session::admit_sound: a follower's SOUND / VOICE out with sounds off and in with sounds on, its
//     JINGLE always out, SOUND_STOP always in, the player's unchanged;
//   * Session::take_event keeps a follower's sound events out of the Lua queue and hands every other event on with its id;
//   * Session::destroy of a leader: host-fed followers; of a follower: gone from the set; its queued events dropped;
//   * commit_movers' many foci: chunks near either of two foci 3,000 HU apart are active (Movers on a real libsa1 context
//     without a disc), one focus or none as before;
//   * kMaxCharacters 128, kMaxFollowers 112; seam M1 (kHostFlagsKnown);
//   * the rumble rule (a follower id: no pad call); the memory guard with a mocked available-memory value.
// With the disc (--gdi), review R.1: build_batches in a job never inserts into the session's black_ map (a miss: no WRAP_MASK, the
// key queued); on the game thread the same draw gets WRAP_MASK.
//
// API NOTES (098-gsa1-followmod): the Lua API is the header of src/module/bind_follower.cpp (gsa1_098_plan.md 5.5 with D8; one
// addition: FollowersTick's optional 6th argument interpolate, the player's alpha rule of level 1). Session: create_follower,
// set_follower_leader, tick_followers, set_follower_threads, follower_workers, follower_stats; a follower job writes only its own
// Character (session.cpp follower_job; the ruling list is r098/lanes/followmod_done.txt). Pool: src/core/pool.hpp.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "../src/core/follower.hpp"
#include "../src/core/session.hpp"
#include "../src/core/shape.hpp"
#include "../src/core/util.hpp"

using namespace gsa1;

static int g_fail = 0, g_checks = 0;

#define CHECK(cond, ...)                                     \
    do {                                                     \
        g_checks++;                                          \
        if (cond) {                                          \
            std::printf("  ok    ");                         \
        } else {                                             \
            std::printf("  FAIL  ");                         \
            g_fail++;                                        \
        }                                                    \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

#define INFO(...)                                            \
    do {                                                     \
        std::printf("  info  ");                             \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

static std::string join(const std::vector<int32_t> &v)
{
    std::string s;
    for (int32_t x : v) {
        s += (s.empty() ? "" : " ") + std::to_string(x);
    }
    return s;
}

static std::string levels_text(const FollowerSet &f)
{
    std::string s;
    for (const auto &l : f.levels()) {
        s += "[" + join(l) + "]";
    }
    return s;
}

static void test_set()
{
    std::printf("FollowerSet: chain levels (Kahn), cycles, leader_gone\n");
    FollowerOpts o;
    // a chain of 4 made leaders first: 11 follows the player 1, 12 follows 11, ...
    FollowerSet a;
    a.add(11, 2, 1, o);
    a.add(12, 2, 11, o);
    a.add(13, 2, 12, o);
    a.add(14, 2, 13, o);
    CHECK(levels_text(a) == "[11][12][13][14]" && join(a.order()) == "11 12 13 14" && a.count() == 4,
          "a chain of 4: one level each, leaders first: %s", levels_text(a).c_str());
    // rewired so that the list order is the wrong way round: Kahn's order, not the list's
    FollowerSet b;
    b.add(14, 2, 13, o);
    b.add(13, 2, 12, o);
    b.add(12, 2, 11, o);
    b.add(11, 2, 1, o);
    CHECK(levels_text(b) == "[11][12][13][14]", "the same chain added last link first: %s", levels_text(b).c_str());
    // two trees: 21 and 22 follow the player 1; 31 follows 21, 32 and 33 follow 22, 41 follows 33; 51 is host-fed, 52 follows 51
    FollowerSet t;
    t.add(21, 2, 1, o);
    t.add(22, 2, 1, o);
    t.add(31, 2, 21, o);
    t.add(32, 2, 22, o);
    t.add(33, 2, 22, o);
    t.add(41, 2, 33, o);
    t.add(51, 2, 0, o);
    t.add(52, 2, 51, o);
    CHECK(levels_text(t) == "[21 22 51][31 32 33 52][41]" && t.order().size() == 8, "two trees and a host-fed tree: %s",
          levels_text(t).c_str());
    CHECK(t.root_of(41) == 1 && t.root_of(21) == 1 && t.root_of(52) == 0 && t.root_of(51) == 0 && t.root_of(1) == -1,
          "root_of: 41 -> the player 1, 52 -> host-fed 0, a non-follower -1");
    CHECK(t.leader_of(41) == 33 && t.leader_of(51) == 0 && t.leader_of(1) == -1 && t.is_follower(41) && !t.is_follower(1) &&
              t.kind_of(41) == 2 && t.kind_of(1) == -1,
          "leader_of, is_follower, kind_of");

    std::string err;
    bool self = t.can_follow(41, 41, err);
    std::string e1 = err;
    err.clear();
    bool own = t.can_follow(21, 31, err);      // 31 follows 21
    std::string e2 = err;
    err.clear();
    bool deep = t.can_follow(22, 41, err);     // 41 -> 33 -> 22
    std::string e3 = err;
    err.clear();
    bool other = t.can_follow(21, 41, err);    // another tree
    bool player = t.can_follow(41, 1, err);
    bool fed = t.can_follow(41, 0, err);
    bool fresh = t.can_follow(0, 41, err);     // a follower to be
    CHECK(!self && !own && !deep && e1 == kReasonCycle && e2 == kReasonCycle && e3 == kReasonCycle && other && player && fed &&
              fresh && err.empty(),
          "cycles refused (itself, its own follower, its own follower's follower: \"%s\"); another tree, a character, host-fed "
          "and a new follower allowed", e1.c_str());

    t.set_leader(41, 21);
    CHECK(levels_text(t) == "[21 22 51][31 32 33 41 52]", "set_leader moves it a level (each level in creation order): %s", levels_text(t).c_str());
    uint32_t g0 = t.generation();
    const std::vector<std::vector<int32_t>> *p = &t.levels();
    (void)t.levels();
    LeaderFeed lf;
    lf.valid = true;
    t.feed(51, lf);
    CHECK(t.generation() == g0 && p == &t.levels() && t.feed_of(51) && t.feed_of(51)->valid && !t.feed_of(1),
          "a feed changes no link; feed_of");

    const float last[3] = {100.0f, 200.0f, 300.0f};
    size_t n = t.leader_gone(22, last, 1.5f);
    const LeaderFeed *f32 = t.feed_of(32);
    CHECK(n == 2 && t.leader_of(32) == 0 && t.leader_of(33) == 0 && f32 && f32->valid && f32->pos[0] == 100.0f &&
              f32->pos[2] == 300.0f && f32->yaw == 1.5f && f32->vel[0] == 0.0f && t.generation() != g0 && t.root_of(32) == 0,
          "leader_gone(22): its 2 followers host-fed with the last state; %s", levels_text(t).c_str());
    t.remove(22);
    CHECK(!t.is_follower(22) && t.count() == 7 && levels_text(t) == "[21 32 33 51][31 41 52]", "remove: %s",
          levels_text(t).c_str());
    t.add(21, 7, 1, o);
    CHECK(t.count() == 7 && t.kind_of(21) == 2, "an id added twice is ignored");
    FollowerSet e;
    CHECK(e.levels().empty() && e.order().empty() && e.count() == 0, "an empty set has no level");
}

static void test_far_rate()
{
    std::printf("the far rate (096 4.10)\n");
    CHECK(follower_far_every(15) == 4 && follower_far_every(30) == 2 && follower_far_every(5) == 12 && follower_far_every(20) == 3 &&
              follower_far_every(1) == 12 && follower_far_every(1000) == 2,
          "round(60 / rate) frames apart: 30 -> 2, 20 -> 3, 15 -> 4, 5 -> 12; out of range clamped to 5..30");
    int due = 0, due_other = 0;
    bool same_frame_ever = false;
    for (uint64_t fr = 1; fr <= 180; fr++) {
        bool a = follower_far_due(fr, 7, 15), b = follower_far_due(fr, 8, 15);
        due += a;
        due_other += b;
        same_frame_ever = same_frame_ever || (a && b);
    }
    CHECK(due == 45 && due_other == 45 && !same_frame_ever, "rate 15: %d renders in 180 frames (3 s), ids 7 and 8 never in one frame",
          due);
}

static sa1_event ev(uint32_t type, int32_t character, uint32_t id = 100)
{
    sa1_event e;
    std::memset(&e, 0, sizeof e);
    e.type = type;
    e.id = id;
    e.character = (sa1_character_id)character;
    return e;
}

static void test_sound_rules()
{
    std::printf("a follower's sound rules (096 4.17, 4.21; Session::admit_sound, Session::take_event)\n");
    Session s;
    s.test_add_character(1, SA1_CHAR_SONIC);
    s.test_add_character(2, SA1_CHAR_TAILS, true, true, 1);
    s.test_add_character(3, SA1_CHAR_KNUCKLES, true, false, 1);
    CHECK(s.admit_sound(ev(SA1_EVENT_SOUND, 2)) && s.admit_sound(ev(SA1_EVENT_VOICE, 2)), "sounds on: its SOUND and VOICE go in");
    CHECK(!s.admit_sound(ev(SA1_EVENT_SOUND, 3)) && !s.admit_sound(ev(SA1_EVENT_VOICE, 3)), "sounds off: its SOUND and VOICE stay out");
    CHECK(!s.admit_sound(ev(SA1_EVENT_JINGLE, 2)) && !s.admit_sound(ev(SA1_EVENT_JINGLE, 3)), "its JINGLE always stays out");
    CHECK(s.admit_sound(ev(SA1_EVENT_SOUND_STOP, 2)) && s.admit_sound(ev(SA1_EVENT_SOUND_STOP, 3)), "a SOUND_STOP always goes in");
    CHECK(s.admit_sound(ev(SA1_EVENT_SOUND, 1)) && s.admit_sound(ev(SA1_EVENT_VOICE, 1)) && s.admit_sound(ev(SA1_EVENT_JINGLE, 1)) &&
              s.admit_sound(ev(SA1_EVENT_SOUND_STOP, 1)) && s.admit_sound(ev(SA1_EVENT_SOUND, 0)) &&
              s.admit_sound(ev(SA1_EVENT_JINGLE, 0)),
          "the player's and a world-less event's are unchanged");

    uint64_t audio0 = s.audio().events();
    for (uint32_t t : {SA1_EVENT_SOUND, SA1_EVENT_SOUND_STOP, SA1_EVENT_VOICE, SA1_EVENT_JINGLE, SA1_EVENT_RUMBLE, SA1_EVENT_DEATH,
                       SA1_EVENT_RESTART, SA1_EVENT_FAULT, SA1_EVENT_CAPACITY}) {
        s.take_event(ev(t, 2));
    }
    uint64_t mixed = s.audio().events() - audio0;
    std::vector<sa1_event> q;
    s.poll_events(q);
    bool only_rest = q.size() == 4;
    for (const sa1_event &e : q) {
        only_rest = only_rest && e.character == 2 &&
                    (e.type == SA1_EVENT_DEATH || e.type == SA1_EVENT_RESTART || e.type == SA1_EVENT_FAULT ||
                     e.type == SA1_EVENT_CAPACITY);
    }
    // what reached the mixer: everything but the jingle (9 events, 1 kept out)
    CHECK(only_rest && mixed == 8, "take_event: its SOUND, STOP, VOICE, JINGLE and RUMBLE never reach the Lua queue; DEATH, RESTART, "
          "FAULT, CAPACITY do, with its id (%zu queued, %llu handed to the mixer)", q.size(), (unsigned long long)mixed);

    for (uint32_t t : {SA1_EVENT_SOUND, SA1_EVENT_SOUND_STOP, SA1_EVENT_VOICE, SA1_EVENT_JINGLE, SA1_EVENT_RUMBLE}) {
        s.take_event(ev(t, 1));
    }
    s.poll_events(q);
    CHECK(q.size() == 5, "the player's five sound events reach Lua as before (%zu)", q.size());

    bool lua = true;
    for (int t : {SA1_EVENT_DEATH, SA1_EVENT_RESTART, SA1_EVENT_RESPAWN, SA1_EVENT_CAPACITY, SA1_EVENT_FAULT, SA1_EVENT_HURT, 15, 16}) {
        lua = lua && follower_event_for_lua((uint32_t)t);
    }
    CHECK(lua, "DEATH, RESTART, RESPAWN, CAPACITY, FAULT, HURT, BOARD (15) and FOLLOW (16) of a follower world reach Lua");
}

static void test_destroy()
{
    std::printf("Session::destroy (096 6.4 task 2)\n");
    Session s;
    s.test_add_character(1, SA1_CHAR_SONIC);
    Character *p = s.get(1);
    p->st.position[0] = 500.0f;
    p->st.yaw = 0.5f;
    s.test_add_character(2, SA1_CHAR_TAILS, true, true, 1);
    s.test_add_character(3, SA1_CHAR_TAILS, true, true, 2);
    s.take_event(ev(SA1_EVENT_DEATH, 3));
    CHECK(s.destroy(1), "the leader destroyed");
    const LeaderFeed *f = s.followers().feed_of(2);
    CHECK(s.followers().leader_of(2) == 0 && f && f->valid && f->pos[0] == 500.0f && f->yaw == 0.5f && s.followers().leader_of(3) == 2,
          "its follower is host-fed with its last state, the chain below stays");
    uint64_t dropped0 = s.stale_events_dropped();
    CHECK(s.destroy(3) && !s.followers().is_follower(3) && s.followers().count() == 1 && s.stale_events_dropped() == dropped0 + 1,
          "a follower destroyed: gone from the set, its queued event dropped");
    s.destroy_all();
    CHECK(s.followers().count() == 0 && s.ids().empty(), "destroy_all empties the set");
    std::vector<FollowerTickResult> out;
    s.tick_followers(1.0f / 60.0f, 0.0f, nullptr, true, out);
    CHECK(out.empty() && s.follower_workers() == 0, "tick_followers without a context or followers does nothing");
}

static void test_foci()
{
    std::printf("commit_movers' foci (follow096_gsa1.md 4.2): chunks near any focus are active\n");
    sa1_context *ctx = nullptr;
    sa1_host h;
    sa1_host_defaults(&h);
    if (SA1_FAILED(sa1_init(&h, &ctx)) || !ctx) {
        CHECK(false, "sa1_init");
        return;
    }
    {
        Movers m;
        std::string e;
        float mn[3] = {-32.0f, -32.0f, 0.0f}, mx[3] = {32.0f, 32.0f, 48.0f};
        Shape sh;
        bool ok = shape_box(mn, mx, sh, e);
        m.set_shape("x:box", std::move(sh));
        m.opt.range = 1000.0f;
        double now = 100.0;
        // a box near each focus and one between them, out of range of both
        const float ang[3] = {0.0f, 0.0f, 0.0f};
        const float pa[3] = {100.0f, 0.0f, 0.0f}, pb[3] = {2900.0f, 0.0f, 0.0f}, pc[3] = {1500.0f, 4000.0f, 0.0f};
        auto update = [&]() {
            m.update(1, "x:box", pa, ang, true, now);
            m.update(2, "x:box", pb, ang, true, now);
            m.update(3, "x:box", pc, ang, true, now);
        };
        update();
        const float f1[3] = {0.0f, 0.0f, 0.0f}, f2[3] = {3000.0f, 0.0f, 0.0f};
        const float *both[2] = {f1, f2};
        m.commit(ctx, both, 2, now);
        uint32_t act2 = m.stats().active, cand2 = m.stats().candidates;
        now += 0.016;
        update();
        m.commit(ctx, f1, now);
        uint32_t act1 = m.stats().active;
        now += 0.016;
        update();
        m.commit(ctx, both + 1, 1, now);
        uint32_t act1b = m.stats().active;
        int32_t ent = 0;
        std::vector<uint32_t> ids = m.object_ids();
        now += 0.016;
        update();
        m.commit(ctx, nullptr, 0, now);
        uint32_t act0 = m.stats().active, parked0 = m.stats().parked;
        CHECK(ok && cand2 > 0 && act2 == cand2 && act1 > 0 && act1 < act2 && act1b == act1 && act0 == 0 && parked0 >= act2 && !ids.empty() &&
                  m.entity_of(ids[0], ent),
              "two foci 3,000 HU apart: the %u chunks near either are active (one focus: %u, the other: %u, none: %u with %u parked); "
              "the box far from both never is", act2, act1, act1b, act0, parked0);
        m.clear(ctx);
    }
    sa1_shutdown(ctx);
}

static void test_limits()
{
    std::printf("the limits and the rules that need no world\n");
    CHECK(kMaxCharacters == 128 && kMaxFollowers == 112, "kMaxCharacters %zu (0.9.5: 16), kMaxFollowers %zu", kMaxCharacters, kMaxFollowers);
#if defined(SA1_INPUT_GAME_CAMERA)
    CHECK((kHostFlagsKnown & SA1_INPUT_GAME_CAMERA) != 0u && (kHostWaterFlags & SA1_INPUT_GAME_CAMERA) == 0u,
          "seam M1: kHostFlagsKnown has the game's camera bit, a follower's water flags do not");
#else
    CHECK(kHostFlagsKnown == kHostWaterFlags, "seam M1: this libsa1.h has no SA1_INPUT_GAME_CAMERA: the water bits only");
#endif
#if defined(SA1_INPUT_HOST_CAMERA)
    CHECK((kHostFlagsKnown & SA1_INPUT_HOST_CAMERA) == 0u, "the host camera's bit stays out of the Lua flags");
#endif
    Character player, puppet, fol;
    puppet.puppet = true;
    fol.follower = true;
    CHECK(rumble_allowed(&player) && !rumble_allowed(&puppet) && !rumble_allowed(&fol) && !rumble_allowed(nullptr),
          "the rumble rule (gsa1.PollEvents): the player's moves the pad, a puppet's and a follower's never");

    static uint64_t mocked = 0;
    set_memory_probe([]() -> uint64_t { return mocked; });
    mocked = (uint64_t)2072 * 1024u * 1024u;
    bool low = follower_memory_ok();
    mocked = (uint64_t)2073 * 1024u * 1024u;
    bool enough = follower_memory_ok();
    mocked = UINT64_MAX;
    bool unknown = follower_memory_ok();
    set_memory_probe(nullptr);
    uint64_t real = available_physical_bytes();
    CHECK(!low && enough && unknown && std::string(kReasonMemory) == "not enough free memory",
          "the memory guard (mocked): 2,072 MB refused (\"%s\"), 2,073 MB allowed, unreadable allowed", kReasonMemory);
    CHECK(real > 0, "the system's available physical memory is read: %.0f MB", real == UINT64_MAX ? -1.0 : (double)real / 1048576.0);
}

// review R.1: two workers inserting into the session-wide black_ map at once would corrupt the heap
static void test_job_batches(const std::string &gdi)
{
    std::printf("build_batches in a job never inserts (review R.1)\n");
    if (gdi.empty()) {
        INFO("no --gdi: needs the disc's textures");
        return;
    }
    Session s;
    std::string err;
    if (!s.init(gdi, err)) {
        CHECK(false, "the disc: %s", err.c_str());
        return;
    }
    // the blob shadow's black texture of Sonic's archives
    int32_t ar = -1, tx = -1;
    uint32_t na = s.texture_archives(SA1_CHAR_SONIC);
    Character c;
    c.kind = SA1_CHAR_SONIC;
    c.num_archives = na;
    // a draw per texture: which are black is asked only after the job's run, so the map is empty of them now
    c.r_triangles = 1;
    c.r_tpos.assign(9, 0.0f);
    c.r_tnrm.assign(9, 0.0f);
    c.r_tuv.assign(6, 0.0f);
    c.r_tcol.assign(12, 255);
    sa1_draw d;
    std::memset(&d, 0, sizeof d);
    d.prim = SA1_PRIM_TRIANGLES;
    d.count = 1;
    d.flags = SA1_DRAW_SHADOW | SA1_DRAW_BLEND;
    d.blend_src = SA1_BLEND_SRC_ALPHA;
    d.blend_dst = SA1_BLEND_INV_SRC_ALPHA;
    uint32_t misses = 0, total = 0;
    for (uint32_t a = 0; a < na && total < 512; a++) {
        uint32_t n = 0;
        std::string e;
        if (!s.texture_count(SA1_CHAR_SONIC, a, n, e)) {
            continue;
        }
        for (uint32_t i = 0; i < n && total < 512; i++) {
            d.archive = (int32_t)a;
            d.texture = (int32_t)i;
            c.r_draws.assign(1, d);
            c.job_running = true;
            c.black_misses.clear();
            s.rebatch(c);
            c.job_running = false;
            total++;
            bool mask = c.batch_count == 1 && (c.batches[0].wrap & WRAP_MASK);
            misses += !c.black_misses.empty() && !mask;
            if (ar < 0 && s.texture_black(SA1_CHAR_SONIC, (int32_t)a, (int32_t)i)) {
                ar = (int32_t)a;
                tx = (int32_t)i;
                // the answer is in the map now: a job finds it and queues nothing
                c.job_running = true;
                c.black_misses.clear();
                s.rebatch(c);
                c.job_running = false;
                bool found = c.black_misses.empty() && c.batch_count == 1 && (c.batches[0].wrap & WRAP_MASK);
                CHECK(found, "after the game thread asked (texture %d of archive %d is black): a job finds the answer, WRAP_MASK, no miss",
                      tx, ar);
            }
        }
    }
    CHECK(misses == total && total > 0, "every texture of Sonic's archives unknown to the map: the job's batch has no WRAP_MASK and the "
          "key is queued (%u of %u)", misses, total);
    CHECK(ar >= 0, "a black texture exists among Sonic's archives (the blob shadow's): texture %d of archive %d", tx, ar);
    if (ar >= 0) {
        d.archive = ar;
        d.texture = tx;
        c.r_draws.assign(1, d);
        c.black_misses.clear();
        s.rebatch(c);
        CHECK(c.batch_count == 1 && (c.batches[0].wrap & WRAP_MASK) && c.black_misses.empty(), "on the game thread: WRAP_MASK");
    }
    s.shutdown();
}

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) {
        gdi = e;
    }
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") {
            gdi = argv[++i];
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_follower_test\n");
    test_set();
    test_far_rate();
    test_sound_rules();
    test_destroy();
    test_foci();
    test_limits();
    test_job_batches(gdi);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
