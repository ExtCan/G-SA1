// feat_gamecam_test: Big's fishing camera through the session (feature "gamecam"; round 0.9.8: sadc docs/research/gsa1_098_plan.md 5.5, 6.9
// task 8 with its review R98.14; fish098.md 6.3 G1, without Session::camera: 2.4 C5) - the bit through Session::tick (session.hpp
// kHostFlagsKnown, seam M1) and libsa1's sa1_character_camera on Session::ctx(). Offline, linked like core_test (the core and libsa1) by
// build.py and run with --gdi when there is one.
//
//   feat_gamecam_test [--gdi GAME.gdi]
//
// Without SA1_API_CAMERA in libsa1.h: one info line. Without the disc: the mask's constant only. With the disc: prints exactly one line
// "SKIP behaviour: gamecam is not built yet" and passes while libsa1's gate is closed (5.3); otherwise Big casts on an island with the bit:
// AIM, then LURE, the flags as libsa1's; TickExtra's host_flags carries 0x8, host_flags_last says so; the same cast without the bit: never
// RUNNING, host_flags_last 0 and the water bits as they were (the existing check, core_test.cpp, sees water bits when no camera bit is
// passed); a host-flag bit nobody knows is dropped.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "../src/core/session.hpp"
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

#if defined(SA1_API_CAMERA)
static const float kPair = 1.0f / 30.0f;

static void rect(std::vector<sa1_collision_tri> &o, float x0, float y0, float x1, float y1, float z, float tile, uint32_t surface)
{
    for (float x = x0; x < x1 - 0.01f; x += tile) {
        for (float y = y0; y < y1 - 0.01f; y += tile) {
            float xe = std::min(x + tile, x1), ye = std::min(y + tile, y1);
            const float p[4][3] = {{x, y, z}, {xe, y, z}, {xe, ye, z}, {x, ye, z}};
            sa1_collision_tri a, b;
            std::memset(&a, 0, sizeof a);
            std::memset(&b, 0, sizeof b);
            std::memcpy(a.v[0], p[0], 12);
            std::memcpy(a.v[1], p[1], 12);
            std::memcpy(a.v[2], p[2], 12);
            std::memcpy(b.v[0], p[0], 12);
            std::memcpy(b.v[1], p[2], 12);
            std::memcpy(b.v[2], p[3], 12);
            a.surface = b.surface = surface;
            o.push_back(a);
            o.push_back(b);
        }
    }
}

struct Seen {
    bool ok = true;
    int aim = -1, lure = -1, running = 0, active = 0;
    uint32_t last_flags = 0;
    bool flag_mismatch = false;
};

// the action held pairs 10-49, the stick forward 25-49; then the lure waits: 160 pairs (tests/core_test.cpp G1's cast)
static Seen cast(Session &s, int32_t id, uint32_t host_flags, uint32_t want_last)
{
    Seen r;
    for (int p = 0; p < 160 && r.ok; p++) {
        TickExtra x;
        x.host_flags = host_flags;
        float sy = (p >= 25 && p < 50) ? 1.0f : 0.0f;
        uint32_t b = (p >= 10 && p < 50) ? SA1_BUTTON_ACTION : 0u;
        if (s.tick(id, 0.0f, sy, 0.0f, b, kPair, true, &x) != SA1_OK) {
            r.ok = false;
            break;
        }
        Character *c = s.get(id);
        if (!c || c->host_flags_last != want_last) {
            r.flag_mismatch = true;
        }
        sa1_camera_state cs;
        std::memset(&cs, 0, sizeof cs);
        cs.struct_size = sizeof cs;
        if (!c || sa1_character_camera(s.ctx(), c->id, -1.0f, &cs) != SA1_OK) {
            r.ok = false;
            break;
        }
        if (cs.kind == SA1_CAMKIND_AIM && r.aim < 0) {
            r.aim = p;
        }
        if (cs.kind == SA1_CAMKIND_LURE && r.lure < 0) {
            r.lure = p;
        }
        if (cs.flags & SA1_CAMSTATE_RUNNING) {
            r.running++;
        }
        if (cs.flags & SA1_CAMSTATE_ACTIVE) {
            r.active++;
        }
        r.last_flags = cs.flags;
    }
    return r;
}
#endif  // SA1_API_CAMERA

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_gamecam_test\n");
#if !defined(SA1_API_CAMERA)
    INFO("this libsa1.h has no SA1_API_CAMERA: nothing to test yet");
    CHECK(true, "the tree builds without the camera API");
#else
    CHECK((kHostFlagsKnown & SA1_INPUT_GAME_CAMERA) != 0u && (kHostFlagsKnown & SA1_INPUT_HOST_CAMERA) == 0u,
          "seam M1: the session passes SA1_INPUT_GAME_CAMERA from TickExtra; the host camera's bit stays its own (flags known 0x%X)",
          (unsigned)kHostFlagsKnown);
    if (gdi.empty()) {
        INFO("no --gdi / SA1_TEST_GDI: a real cast needs the disc");
    } else {
        Session s;
        std::string e;
        if (!s.init(gdi, e)) {
            CHECK(false, "init: %s", e.c_str());
        } else {
            std::vector<sa1_collision_tri> isl;
            rect(isl, -300, -300, 300, 300, 0, 300, SA1_SURFACE_SOLID);
            rect(isl, -6000, -6000, 6000, -300, -20, 1000, SA1_SURFACE_WATER);
            rect(isl, -6000, 300, 6000, 6000, -20, 1000, SA1_SURFACE_WATER);
            rect(isl, -6000, -300, -300, 300, -20, 600, SA1_SURFACE_WATER);
            rect(isl, 300, -300, 6000, 300, -20, 600, SA1_SURFACE_WATER);
            rect(isl, -6000, -6000, 6000, 6000, -600, 1000, SA1_SURFACE_SOLID);
            CHECK(s.set_world(isl, e), "the island (%s)", e.c_str());
            const float pos[3] = {0.0f, 0.0f, 8.0f};
            int32_t id = s.create(SA1_CHAR_BIG, pos, 0.0f, e);
            CHECK(id > 0, "Big on the island (%s)", e.c_str());
            // (one neutral pair first: libsa1 answers "not loaded" for a character whose world is not there yet)
            if (id > 0) {
                s.tick(id, 0.0f, 0.0f, 0.0f, 0u, kPair);
            }
            Character *c = s.get(id);
            sa1_camera_state cs;
            std::memset(&cs, 0, sizeof cs);
            cs.struct_size = sizeof cs;
            sa1_status first = c ? sa1_character_camera(s.ctx(), c->id, -1.0f, &cs) : SA1_ERR_NOT_FOUND;
            if (first == SA1_ERR_UNSUPPORTED) {
                std::printf("SKIP behaviour: gamecam is not built yet\n");
            } else {
                CHECK(first == SA1_OK && cs.kind == SA1_CAMKIND_NONE && cs.flags == 0u, "a new Big: no request");
                const uint32_t bit_water = SA1_INPUT_GAME_CAMERA | SA1_INPUT_HOST_WATER_KNOWN;
                Seen on = cast(s, id, bit_water, bit_water);
                CHECK(on.ok && !on.flag_mismatch, "Session::tick passes the bit: host_flags_last 0x%X on every tick", (unsigned)bit_water);
                CHECK(on.aim >= 15 && on.aim <= 40 && on.lure > on.aim && on.lure <= 140 && on.running >= 60 && on.active >= on.running,
                      "with the bit: AIM from pair %d, LURE from pair %d, RUNNING %d of %d pairs with a request", on.aim, on.lure, on.running, on.active);
                CHECK((on.last_flags & (SA1_CAMSTATE_ACTIVE | SA1_CAMSTATE_KNOWN | SA1_CAMSTATE_RUNNING)) ==
                          (SA1_CAMSTATE_ACTIVE | SA1_CAMSTATE_KNOWN | SA1_CAMSTATE_RUNNING),
                      "the lure in the water: ACTIVE | KNOWN | RUNNING (0x%X)", (unsigned)on.last_flags);
                s.destroy(id);
                id = s.create(SA1_CHAR_BIG, pos, 0.0f, e);
                CHECK(id > 0, "Big again, a new world");
                Seen off = cast(s, id, SA1_INPUT_HOST_WATER_KNOWN, SA1_INPUT_HOST_WATER_KNOWN);
                CHECK(off.ok && !off.flag_mismatch && off.running == 0 && off.aim >= 0 && off.lure > off.aim,
                      "without the bit: the water bits as they were (host_flags_last 0x%X), the request reported (AIM %d, LURE %d), never RUNNING",
                      (unsigned)SA1_INPUT_HOST_WATER_KNOWN, off.aim, off.lure);
                CHECK((off.last_flags & SA1_CAMSTATE_RUNNING) == 0u && (off.last_flags & SA1_CAMSTATE_KNOWN) != 0u, "... KNOWN, not RUNNING (0x%X)",
                      (unsigned)off.last_flags);
                s.destroy(id);
                id = s.create(SA1_CHAR_BIG, pos, 0.0f, e);
                TickExtra x;
                x.host_flags = 0xF0u;
                sa1_status st = id > 0 ? s.tick(id, 0.0f, 0.0f, 0.0f, 0u, kPair, false, &x) : SA1_ERR_NOT_FOUND;
                c = s.get(id);
                CHECK(st == SA1_OK && c && c->host_flags_last == 0u, "a host flag nobody knows is dropped (0xF0 passed, 0x%X taken)", c ? (unsigned)c->host_flags_last : 99u);
            }
            if (id > 0) {
                s.destroy(id);
            }
        }
    }
#endif  // SA1_API_CAMERA
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
