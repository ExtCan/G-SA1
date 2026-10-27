// feat_super_test: Super Sonic in G-SA1's core (round 6a in round 0.9.3: sadc docs/research/gsa1_rounds_plan.md 11.3 with
// the owner's answer 14.1a, gsa1_090_plan.md 7.5; libsa1 API 0.4), offline. build.py links it like core_test (the core and
// libsa1) and runs it with --gdi when there is one.
//
//   feat_super_test [--gdi GAME.gdi] [--verbose] [--census-lua]
//
// Without the disc: the playable kinds hold Super Sonic, the extra create flags and Super flags G-SA1 passes.
// With the disc, through gsa1::Session (the module's code path) on a flat floor:
//   * Super Sonic (kind 8) from the character list: Super by his second pair (SA1_STATE_SUPER, equipment 0x8000), 50
//     rings (libsa1's start), his archives (SUPERSONIC first, Sonic's SONIC / SON_EFF after the common ones);
//   * the options round trip (CreateExtra -> sa1_character_desc -> the game): the drain (50 -> 49 after 60 steps), no
//     drain, "stay Super at 0 rings" (KEEP_AT_ZERO), back to normal Sonic at 0 rings in the same world (he keeps running:
//     the revert fix) and FAITHFUL_REVERT (the game's bug: a slower run afterwards), the refusals (a flag G-SA1 does not
//     pass, the sea plane, SUPER_CAPABLE for another character, Super flags without a Super world);
//   * the transformation (owner 14.1a): a running SUPER_CAPABLE Sonic turns Super with Session::order(SA1_ORDER_SUPER) in
//     the next pair with his speed, facing and rings, and back with SA1_ORDER_NORMAL; a Sonic without SUPER_CAPABLE and
//     another order are refused; a reverted Super Sonic (kind 8) turns Super again;
//   * a hit (sa1_character_damage, what the interaction feature sends) only halves Super Sonic's speed: no ring lost, no
//     knock-back, no death (the game's rule, code_8C0AFB10.c);
//   * drawing: his body (SUPERSONIC, not an effect), the game's blob shadow, the aura (additive effect of SUPERSONIC)
//     when he runs; after the revert the body from SONIC, still not an effect;
//   * sound: the aura's whoosh (1035 above speed 7) reaches the events but not the mixer (Emerald Coast's stage bank has
//     other programs there: Session::take_events), unless Session::set_stage_tones(false);
//   * the game's HUD (rings, lives, time: what feat/cl_hud.lua draws) for Super Sonic and for a transformed Sonic, with
//     his own CON_REGULAR textures, and the drained ring on it;
//   * "run on water" (SA1_CREATE_WATER_FLOOR): Super Sonic stands and runs on a WATER box's top, with the host's water
//     flags KNOWN | IN_WATER and KNOWN alone; without it he sinks;
//   * the material census for the pre-warm (cl_warm.lua; the SUPERSONIC archive): every render state Super Sonic (kind 8)
//     draws in 16 s of scripted play - standing, running into both dash auras, jumps, homing attacks, the air stop, then
//     the drain's revert and normal Sonic's moves - and every SUPERSONIC state of a transformed Sonic (kind 0, archive 5),
//     written to material_census_super.txt next to the test (tests/feat_super_test.lua checks that feat/cl_super.lua's
//     census data covers every line exactly); --census-lua prints that data as Lua.
// Round 0.9.3a (sadc docs/research/super_general_design.md 8.3 with its Review R.4), with the disc:
//   * Super Sonic (General Gameplay): the General entry (GENERAL | START) Super right after his first pair in Sonic's own
//     modes with his SUPERSONIC body; without START he stays normal (RC1); the transformation in a jump keeps mode 8 and
//     the speed and plays the voice 1116 once; Super run is faster than Sonic on the ground; back with SA1_ORDER_NORMAL;
//     the body anchored like kind 8's at 144 fps (RC15); upgrades kept both ways; the voice Preview into the mixer;
//   * Super Sonic (Vs. Perfect Chaos): find_upgrade(8, ...) gives Sonic's rows; one 600-pair script with and without
//     Sonic's three upgrades plays identically up to the revert (RC8), 0x8007 / 0x0007; SA1_SUPER_START_NORMAL starts
//     normal and two orders in a frame give one voice (RC1 / RC11); the game's trigger plays none;
//   * the aura animation through Session's render (RC9): texture changes per second at 60 and 144 fps for Dreamcast,
//     Calm and Slow, both versions;
//   * the census of kind 0 is now the General form's (G-SA1's transformed Sonic and its list entry).
// Round 0.9.4a (sadc docs/research/super2_plan.md 6.4 with its review and the owner's answers of 10.1), with the disc:
//   * N1 (SA1_SUPOPT_SUPER_ANIMS): the General entry's stand through Session's render floats like Vs. Perfect Chaos (the
//     lowest body point within 0.1 HU of kind 8's over 140 pairs, inside -1.17..-0.40 units); without the option Sonic's
//     stand (-0.15..0.08); 2, kind 8 and a plain Sonic refused;
//   * N2 (SA1_SUPOPT_LSD_GOLD, SUPER_EFFECTS 3): two General worlds in lockstep with the option 0 / 1 - with the Crystal
//     Ring its green lcharge03 / 04 never WRAP_GOLD (owner answer O3), with the shoes alone lcharge01 / 02 WRAP_GOLD and
//     nothing else, every other key the option-0 run's; the glow's vertex colours max + min - c of the option-0 run's
//     (review R.3); the spin dash sparks SUPERSONIC ss_ball; the golden variant through Session::texture_runs equals
//     libsa1's (review R.6); SUPER_EFFECTS 1 keeps the blue sparks;
//   * N3 (stage rules): who holds the whoosh rule, the whoosh heard through the mixer from CHAOS7B.MLT with the option on,
//     kept out and silent with it off, re-applied after a re-open, gone with its character; 1033 stays out (admit_sound);
//   * test_sound: the whoosh off keeps 1035 out as 0.9.4 did; on, it passes the guard;
//   * the census: the golden charge's rows (SON_EFF lcharge01 / 02 with WRAP_GOLD, from a shoes-alone charge; review R.2)
//     and the same SUPERSONIC body states with the poses on and off.
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <thread>
#include <vector>

#include "../src/core/session.hpp"
#include "../src/core/util.hpp"

using namespace gsa1;

static int g_fail = 0, g_checks = 0;
static bool g_verbose = false;

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

#if defined(SA1_API_SUPER)

const uint32_t J = SA1_BUTTON_JUMP, B = SA1_BUTTON_ACTION;
const uint32_t kPlayerPwp = 0x8C78C668u;      // playerpwp[8] (1ST_READ data; LIB tests/super_test.c A_PLAYER_PWP)
const uint32_t kSpdX = 0x38u;                 // playerwk.spd.x

// ---- scenes -----------------------------------------------------------------------------------------------------------
static void quad(std::vector<sa1_collision_tri> &out, const float p[4][3], const float n[3], uint32_t surface)
{
    float e1[3], e2[3], c[3];
    for (int k = 0; k < 3; k++) {
        e1[k] = p[1][k] - p[0][k];
        e2[k] = p[2][k] - p[0][k];
    }
    c[0] = e1[1] * e2[2] - e1[2] * e2[1];
    c[1] = e1[2] * e2[0] - e1[0] * e2[2];
    c[2] = e1[0] * e2[1] - e1[1] * e2[0];
    bool same = c[0] * n[0] + c[1] * n[1] + c[2] * n[2] >= 0.0f;
    sa1_collision_tri a, b;
    std::memset(&a, 0, sizeof a);
    std::memset(&b, 0, sizeof b);
    const int ia[3] = {0, same ? 1 : 2, same ? 2 : 1}, ib[3] = {0, same ? 2 : 3, same ? 3 : 2};
    for (int v = 0; v < 3; v++) {
        std::memcpy(a.v[v], p[ia[v]], 12);
        std::memcpy(b.v[v], p[ib[v]], 12);
    }
    a.surface = b.surface = surface;
    out.push_back(a);
    out.push_back(b);
}

// a floor (host space, z up) in tiles
static void floor_tiles(std::vector<sa1_collision_tri> &out, float x0, float x1, float y0, float y1, float z, float tile)
{
    const float up[3] = {0, 0, 1};
    for (float x = x0; x < x1 - 0.5f; x += tile) {
        for (float y = y0; y < y1 - 0.5f; y += tile) {
            const float p[4][3] = {{x, y, z}, {x + tile, y, z}, {x + tile, y + tile, z}, {x, y + tile, z}};
            quad(out, p, up, SA1_SURFACE_SOLID);
        }
    }
}

// a closed box with outward faces
static void box(std::vector<sa1_collision_tri> &out, float x0, float x1, float y0, float y1, float z0, float z1, uint32_t s)
{
    const float top[4][3] = {{x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1}};
    const float bot[4][3] = {{x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0}};
    const float wx0[4][3] = {{x0, y0, z0}, {x0, y1, z0}, {x0, y1, z1}, {x0, y0, z1}};
    const float wx1[4][3] = {{x1, y0, z0}, {x1, y1, z0}, {x1, y1, z1}, {x1, y0, z1}};
    const float wy0[4][3] = {{x0, y0, z0}, {x1, y0, z0}, {x1, y0, z1}, {x0, y0, z1}};
    const float wy1[4][3] = {{x0, y1, z0}, {x1, y1, z0}, {x1, y1, z1}, {x0, y1, z1}};
    const float up[3] = {0, 0, 1}, down[3] = {0, 0, -1}, mx[3] = {-1, 0, 0}, px[3] = {1, 0, 0}, my[3] = {0, -1, 0},
                py[3] = {0, 1, 0};
    quad(out, top, up, s);
    quad(out, bot, down, s);
    quad(out, wx0, mx, s);
    quad(out, wx1, px, s);
    quad(out, wy0, my, s);
    quad(out, wy1, py, s);
}

// ---- running ------------------------------------------------------------------------------------------------------------
static std::vector<sa1_event> g_ev;
static std::vector<sa1_event> g_all;          // every event of the last run()

static bool pair(Session &s, int32_t id, float sy, uint32_t b, const TickExtra *x = nullptr)
{
    sa1_status st = s.tick(id, 0.0f, sy, 0.0f, b, 1.0f / 30.0f, false, x);
    s.poll_events(g_ev);
    for (const sa1_event &e : g_ev) {
        if (e.character == (sa1_character_id)id) {
            g_all.push_back(e);
        }
    }
    if (st != SA1_OK) {
        std::printf("        tick: %s\n", s.last_error().c_str());
    }
    return st == SA1_OK;
}

static bool run(Session &s, int32_t id, int pairs, float sy, uint32_t b = 0, const TickExtra *x = nullptr)
{
    for (int i = 0; i < pairs; i++) {
        if (!pair(s, id, sy, b, x)) {
            return false;
        }
    }
    return true;
}

static int count_ev(uint32_t type, uint32_t id)
{
    int n = 0;
    for (const sa1_event &e : g_all) {
        n += e.type == type && e.id == id;
    }
    return n;
}

static int count_type(uint32_t type)
{
    int n = 0;
    for (const sa1_event &e : g_all) {
        n += e.type == type;
    }
    return n;
}

// the world's playerwk.spd.x set directly (the LIB test's way to reach the dash auras' speeds)
static bool set_speed(Session &s, int32_t id, float spd)
{
    struct sa1g_world *w = sa1_character_world(s.ctx(), id);
    uint32_t pwp = 0, v = 0;
    if (!w || sa1g_world_rd32(w, kPlayerPwp, &pwp) != 0 || pwp == 0) {
        return false;
    }
    std::memcpy(&v, &spd, 4);
    return sa1g_world_wr32(w, pwp + kSpdX, v) == 0;
}

static int32_t mk(Session &s, int32_t kind, const float pos[3], int32_t rings, uint32_t flags, bool super_given,
                  uint32_t super_flags, std::string &err)
{
    CreateExtra ex;
    ex.flags = flags;
    ex.super_given = super_given;
    ex.super_flags = super_flags;
    return s.create(kind, pos, 0.0f, err, nullptr, nullptr, rings, &ex);
}

static int32_t archive_named(Session &s, int32_t kind, const char *name)
{
    for (uint32_t a = 0, na = s.texture_archives(kind); a < na; a++) {
        uint32_t n = 0;
        std::string e, nm;
        if (s.texture_count(kind, a, n, e, &nm) && nm == name) {
            return (int32_t)a;
        }
    }
    return -1;
}

static std::string archive_list(Session &s, int32_t kind)
{
    std::string out;
    for (uint32_t a = 0, na = s.texture_archives(kind); a < na; a++) {
        uint32_t n = 0;
        std::string e, nm;
        s.texture_count(kind, a, n, e, &nm);
        out += format("%s%s %u", out.empty() ? "" : ", ", nm.c_str(), n);
    }
    return out;
}

// what a render drew: body draws (not effects, not the shadow) by archive, additive effects by archive, shadow draws
struct Drawn {
    uint32_t body = 0, body_effect = 0, body_other = 0, additive = 0, shadow = 0;
};
static Drawn drawn(Session &s, int32_t id, int32_t body_archive, int32_t fx_archive)
{
    Drawn d;
    s.render(id, 1.0f);
    const Character *c = s.get(id);
    if (!c) {
        return d;
    }
    for (uint32_t i = 0; i < c->batch_count; i++) {
        const RenderBatch &b = c->batches[i];
        if (b.flags & SA1_DRAW_SHADOW) {
            d.shadow++;
        } else if (b.archive == body_archive && !(b.flags & SA1_DRAW_EFFECT) && b.pass == 0) {
            d.body++;
        } else if (b.archive == fx_archive && (b.flags & SA1_DRAW_EFFECT) && (b.flags & SA1_DRAW_ADDITIVE)) {
            d.additive++;
        }
        if (b.archive == body_archive && !(b.flags & SA1_DRAW_SHADOW) && (b.flags & SA1_DRAW_EFFECT) && b.pass == 0) {
            d.body_effect++;
        }
    }
    d.shadow = c->shadow_draws;
    return d;
}

// ---- 1. Super Sonic from the list ---------------------------------------------------------------------------------------
static void test_kind8(Session &s)
{
    std::printf("Super Sonic (kind 8) from the character list\n");
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    int32_t a_ss = archive_named(s, SA1_CHAR_SUPER_SONIC, "SUPERSONIC");
    int32_t a_son = archive_named(s, SA1_CHAR_SUPER_SONIC, "SONIC");
    int32_t a_son_eff = archive_named(s, SA1_CHAR_SUPER_SONIC, "SON_EFF");
    CHECK(a_ss == 0 && a_son > a_ss && a_son_eff > a_son, "his archives: %s (SUPERSONIC %d, SONIC %d, SON_EFF %d)",
          archive_list(s, SA1_CHAR_SUPER_SONIC).c_str(), a_ss, a_son, a_son_eff);
    int32_t a5 = archive_named(s, SA1_CHAR_SONIC, "SUPERSONIC");
    CHECK(s.super_forms() && a5 >= 1, "Sonic's Super forms are loaded: his archives %s (SUPERSONIC %d)",
          archive_list(s, SA1_CHAR_SONIC).c_str(), a5);
    // no extras at all: libsa1's defaults (the drain on, 50 rings)
    int32_t id = s.create(SA1_CHAR_SUPER_SONIC, at, 0.0f, err);
    CHECK(id > 0, "create(kind 8) with no extras: id %d %s", id, err.c_str());
    if (id <= 0) {
        return;
    }
    const Character *c = s.get(id);
    bool before = c->super;
    int super_pair = -1;
    for (int p = 1; p <= 6; p++) {
        pair(s, id, 0.0f, 0);
        if (super_pair < 0 && c->super) {
            super_pair = p;
        }
    }
    CHECK(!before && super_pair >= 1 && super_pair <= 2 && (c->st.equipment & 0x8000u) && (c->st.flags & SA1_STATE_SUPER) &&
              c->super_capable && c->super_changes == 1 && c->st.rings == 50 && c->st.mode >= 71 && c->st.mode <= 78,
          "Super from pair %d (equipment %04X, mode %d, action %d), %d rings, capable, %u form change", super_pair,
          (unsigned)c->st.equipment, (int)c->st.mode, (int)c->st.action, (int)c->st.rings, (unsigned)c->super_changes);
    Drawn d = drawn(s, id, a_ss, a_ss);
    CHECK(d.body > 0 && d.body_effect == 0 && d.shadow >= 1, "standing: %u body batches from SUPERSONIC (none an effect), "
          "the game's blob shadow (%u draws)", d.body, d.shadow);
    s.destroy(id);
}

// ---- 2. the options round trip ----------------------------------------------------------------------------------------
static void test_options(Session &s)
{
    std::printf("the options: the drain, back to normal Sonic, stay Super at 0, the game's physics bug\n");
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    // the drain (super_flags 0 given): 50 -> 49 after 60 steps, 48 after 120
    int32_t id = mk(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, true, 0u, err);
    const Character *c = id > 0 ? s.get(id) : nullptr;
    int at49 = -1, at48 = -1;
    for (int p = 0; p < 70 && c; p++) {
        pair(s, id, 0.0f, 0);
        if (at49 < 0 && c->st.rings == 49) at49 = (int)c->st.step;
        if (at48 < 0 && c->st.rings == 48) at48 = (int)c->st.step;
    }
    CHECK(c && at49 >= 58 && at49 <= 66 && at48 - at49 >= 58 && at48 - at49 <= 62 && c->super,
          "the drain (gsa1_super_drain 1): 50 -> 49 at step %d, -> 48 at step %d, still Super", at49, at48);
    if (id > 0) s.destroy(id);
    // no drain
    id = mk(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, true, SA1_SUPER_NO_DRAIN, err);
    c = id > 0 ? s.get(id) : nullptr;
    if (c) run(s, id, 100, 0.0f);
    CHECK(c && c->st.rings == 50 && c->super, "NO_DRAIN (gsa1_super_drain 0): %d rings after 100 pairs, Super %s",
          c ? (int)c->st.rings : -1, c && c->super ? "yes" : "no");
    if (id > 0) s.destroy(id);
    // stay Super at 0 (KEEP_AT_ZERO), from 1 ring
    id = mk(s, SA1_CHAR_SUPER_SONIC, at, 1, 0, true, SA1_SUPER_KEEP_AT_ZERO, err);
    c = id > 0 ? s.get(id) : nullptr;
    if (c) run(s, id, 120, 0.0f);
    CHECK(c && c->st.rings == 0 && c->super && c->super_changes == 1,
          "KEEP_AT_ZERO (gsa1_super_keep 1): %d rings after 120 pairs and still Super (%u form changes)",
          c ? (int)c->st.rings : -1, c ? (unsigned)c->super_changes : 0u);
    if (id > 0) s.destroy(id);
    // back to normal Sonic at 0 rings (the game's rule, the default) in the same world: with the revert fix he runs on;
    // FAITHFUL_REVERT keeps the game's bug (max_x_spd / run_accel left at the air resistances: a slower run)
    float top[2] = {0.0f, 0.0f};
    int rev_step[2] = {-1, -1}, rev_mode[2] = {-1, -1};
    for (int k = 0; k < 2; k++) {
        id = mk(s, SA1_CHAR_SUPER_SONIC, at, 1, 0, true, k ? SA1_SUPER_FAITHFUL_REVERT : 0u, err);
        c = id > 0 ? s.get(id) : nullptr;
        for (int p = 0; p < 60 && c; p++) {
            pair(s, id, 0.0f, 0);
            if (rev_step[k] < 0 && c->super_changes == 2) {
                rev_step[k] = (int)c->st.step;
                rev_mode[k] = (int)c->st.mode;
            }
        }
        for (int p = 0; p < 90 && c; p++) {
            pair(s, id, 1.0f, 0);
            top[k] = std::max(top[k], c->st.player_speed[0]);
        }
        if (k == 0) {
            CHECK(c && rev_step[0] > 0 && !c->super && !(c->st.equipment & 0x8000u) && c->st.rings == 0 && top[0] > 3.3f &&
                      (c->st.mode < 71 || c->st.mode > 78),
                  "at 0 rings (gsa1_super_keep 0): back to normal Sonic in his world at step %d (mode %d), then a run "
                  "reaches %.2f units per step (the revert fix)", rev_step[0], rev_mode[0], (double)top[0]);
            if (c) {
                int32_t a_son = archive_named(s, SA1_CHAR_SUPER_SONIC, "SONIC");
                Drawn d = drawn(s, id, a_son, -2);
                CHECK(d.body > 0 && d.body_effect == 0, "reverted: %u body batches from SONIC (archive %d), none an effect",
                      d.body, a_son);
            }
        }
        if (id > 0) s.destroy(id);
    }
    CHECK(rev_step[1] > 0 && top[1] > 0.5f && top[1] < top[0] - 0.2f,
          "FAITHFUL_REVERT (gsa1_super_faithful_revert 1): reverted at step %d, the run reaches only %.2f (the game's bug) "
          "against %.2f", rev_step[1], (double)top[1], (double)top[0]);
    // the refusals
    int refused = 0;
    std::string e1, e2, e3, e4, e5;
    refused += mk(s, SA1_CHAR_SUPER_SONIC, at, -1, 0x20u, false, 0u, e1) == 0;                       // SA1_CREATE_STAGE
    refused += mk(s, SA1_CHAR_SUPER_SONIC, at, -1, 0, true, SA1_SUPER_SEA_PLANE, e2) == 0;
    refused += mk(s, SA1_CHAR_TAILS, at, -1, SA1_CREATE_SUPER_CAPABLE, false, 0u, e3) == 0;
    refused += mk(s, SA1_CHAR_SONIC, at, -1, 0, true, SA1_SUPER_NO_DRAIN, e4) == 0;
    refused += mk(s, SA1_CHAR_KNUCKLES, at, -1, 0, true, 0u, e5) == 0;
    CHECK(refused == 5 && e2.find("sea plane") != std::string::npos && e3.find("only Sonic") != std::string::npos,
          "refused: a create flag G-SA1 does not pass (%s); the sea plane (%s); SUPER_CAPABLE Tails (%s); Super flags for a "
          "plain Sonic (%s) and for Knuckles", e1.c_str(), e2.c_str(), e3.c_str(), e4.c_str());
}

// ---- 3. the transformation ----------------------------------------------------------------------------------------------
static void test_transform(Session &s)
{
    // 0.9.3a (review RC10): G-SA1 itself makes the General form now (test_general); this is libsa1's 0.9.3 path for API
    // users (SUPER_CAPABLE without GENERAL: a level-19 world, the game's request 46 into the Super modes), still offered
    std::printf("the 0.9.3 transformation path (libsa1 API users; G-SA1 makes the General form): Sonic turns Super in his "
                "own world and back\n");
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    int32_t id = mk(s, SA1_CHAR_SONIC, at, 50, SA1_CREATE_SUPER_CAPABLE, true, SA1_SUPER_NO_DRAIN, err);
    const Character *c = id > 0 ? s.get(id) : nullptr;
    CHECK(c && c->super_capable && !c->super, "a SUPER_CAPABLE Sonic: %s", err.c_str());
    if (!c) {
        return;
    }
    run(s, id, 60, 1.0f);
    sa1_state_ex x0 = c->st;
    sa1_status st = s.order(id, SA1_ORDER_SUPER);
    pair(s, id, 1.0f, 0);
    sa1_state_ex x1 = c->st;
    float d = std::hypot(x1.sa1_position[0] - x0.sa1_position[0], x1.sa1_position[2] - x0.sa1_position[2]);
    CHECK(st == SA1_OK && c->super && x1.player_speed[0] > 0.9f * x0.player_speed[0] && d > 1.5f * x0.player_speed[0] &&
              ((x1.angle[1] - x0.angle[1]) & 0xFFFF) < 0x200 && x1.rings == x0.rings && c->super_changes == 1,
          "running at %.2f, SA1_ORDER_SUPER: Super in the next pair at %.2f (moved %.1f, ang.y %04X -> %04X, rings %d -> %d)",
          (double)x0.player_speed[0], (double)x1.player_speed[0], (double)d, (unsigned)(x0.angle[1] & 0xFFFF),
          (unsigned)(x1.angle[1] & 0xFFFF), (int)x0.rings, (int)x1.rings);
    int32_t a5 = archive_named(s, SA1_CHAR_SONIC, "SUPERSONIC");
    run(s, id, 30, 1.0f);
    Drawn dr = drawn(s, id, a5, a5);
    CHECK(c->super && dr.body > 0 && dr.body_effect == 0 && dr.additive > 0,
          "30 pairs later: Super; body %u batches from his SUPERSONIC archive (%d, none an effect), the aura %u additive",
          dr.body, a5, dr.additive);
    x0 = c->st;
    st = s.order(id, SA1_ORDER_NORMAL);
    pair(s, id, 1.0f, 0);
    CHECK(st == SA1_OK && !c->super && c->st.player_speed[0] > 0.8f * x0.player_speed[0] && c->super_changes == 2,
          "SA1_ORDER_NORMAL: normal Sonic in the next pair, speed %.2f -> %.2f", (double)x0.player_speed[0],
          (double)c->st.player_speed[0]);
    sa1_status twice = s.order(id, SA1_ORDER_NORMAL);
    sa1_status bad = s.order(id, 3);
    s.destroy(id);
    // a Sonic without SUPER_CAPABLE
    id = s.create(SA1_CHAR_SONIC, at, 0.0f, err);
    sa1_status plain = id > 0 ? s.order(id, SA1_ORDER_SUPER) : SA1_OK;
    std::string why = s.last_error();
    CHECK(twice == SA1_OK && bad == SA1_ERR_INVALID_ARGUMENT && plain == SA1_ERR_UNSUPPORTED,
          "NORMAL while normal: OK (nothing sent); order 3: refused; a plain Sonic: %s (%s)", sa1_status_string(plain),
          why.c_str());
    if (id > 0) s.destroy(id);
    // kind 8 after the drain's revert takes SA1_ORDER_SUPER again
    id = mk(s, SA1_CHAR_SUPER_SONIC, at, 1, 0, true, 0u, err);
    c = id > 0 ? s.get(id) : nullptr;
    if (c) run(s, id, 45, 0.0f);
    bool reverted = c && !c->super;
    if (c) {
        sa1_character_add_rings(s.ctx(), id, 50);
        st = s.order(id, SA1_ORDER_SUPER);
        run(s, id, 2, 0.0f);
    }
    CHECK(reverted && c && c->super && st == SA1_OK && c->super_changes == 3,
          "Super Sonic after the revert: +50 rings and SA1_ORDER_SUPER: Super again (%u form changes, %d rings)",
          c ? (unsigned)c->super_changes : 0u, c ? (int)c->st.rings : -1);
    if (id > 0) s.destroy(id);
}

// ---- 4. a hit ---------------------------------------------------------------------------------------------------------------
static void test_hit(Session &s)
{
    std::printf("a hit on Super Sonic (the interaction feature's sa1_character_damage)\n");
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    int32_t id = mk(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, true, SA1_SUPER_NO_DRAIN, err);
    const Character *c = id > 0 ? s.get(id) : nullptr;
    if (!c) {
        CHECK(false, "create: %s", err.c_str());
        return;
    }
    run(s, id, 60, 1.0f);
    sa1_state_ex x0 = c->st;
    sa1_damage dm;
    std::memset(&dm, 0, sizeof dm);
    dm.struct_size = sizeof dm;
    std::memcpy(dm.source, c->st.position, sizeof dm.source);
    dm.source[0] += 64.0f;
    g_all.clear();
    sa1_status st = sa1_character_damage(s.ctx(), id, &dm);
    pair(s, id, 1.0f, 0);
    sa1_state_ex x1 = c->st;
    for (int p = 0; p < 10; p++) {
        pair(s, id, 1.0f, 0);       // a knock-back or a death would show within these pairs
    }
    int deaths = count_type(SA1_EVENT_DEATH);
    CHECK(st == SA1_OK && x1.player_speed[0] < 0.75f * x0.player_speed[0] && x1.player_speed[0] > 0.2f * x0.player_speed[0] &&
              x1.rings == x0.rings && c->super && deaths == 0 && x1.invulnerable_steps > 60 &&
              ((x1.angle[1] - x0.angle[1]) & 0xFFFF) < 0x400,
          "hit while running at %.2f: %.2f after the pair (halved), rings %d -> %d, still Super, blinking %u steps, no "
          "death, no turn", (double)x0.player_speed[0], (double)x1.player_speed[0], (int)x0.rings, (int)x1.rings,
          (unsigned)x1.invulnerable_steps);
    s.destroy(id);
}

// ---- 5. the aura's whoosh -----------------------------------------------------------------------------------------------
static void test_sound(Session &s)
{
    std::printf("sound: the aura's whoosh (Perfect Chaos stage tones) never plays from Emerald Coast's bank\n");
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    // k 0: the whoosh off (0.9.4's guard: kept out); k 1 (0.9.4a, the default): the whoosh on - its stage rule recorded
    // (no sound banks open here: applied when they open), so 1035 passes the guard; k 2: set_stage_tones(false)
    for (int k = 0; k < 3; k++) {
        s.set_stage_tones(k != 2);
        s.set_super_whoosh(k != 0);
        int32_t id = mk(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, true, SA1_SUPER_NO_DRAIN, err);
        const Character *c = id > 0 ? s.get(id) : nullptr;
        if (!c) {
            CHECK(false, "create: %s", err.c_str());
            continue;
        }
        run(s, id, 10, 0.0f);
        g_all.clear();
        uint64_t dropped0 = s.stage_tones_dropped();
        set_speed(s, id, 8.5f);
        pair(s, id, 0.0f, 0);
        int whoosh = count_ev(SA1_EVENT_SOUND, 1035);
        if (k == 0) {
            CHECK(whoosh == 1 && c->stage_tones_muted >= 1 && s.stage_tones_dropped() > dropped0 && s.stage_tones_muted(),
                  "the whoosh off: speed 8.5: SOUND 1035 reaches Lua (%d), kept out of the mixer (%llu for this world)",
                  whoosh, (unsigned long long)c->stage_tones_muted);
        } else if (k == 1) {
#if defined(SA1_AUDIO_HAS_STAGE_RULES)
            CHECK(whoosh == 1 && c->stage_tones_muted == 0 && s.stage_tones_dropped() == dropped0 && s.whoosh_routed(id) &&
                      !s.stage_tones_muted(),
                  "0.9.4a, the whoosh on (the default): SOUND 1035 passes the guard to the mixer, through its stage rule "
                  "(none kept out; routed %d)", (int)s.whoosh_routed(id));
#else
            CHECK(false, "libsa1_audio.h has no stage rules (version 5): the whoosh cannot be routed");
#endif
        } else {
            CHECK(whoosh == 1 && c->stage_tones_muted == 0 && s.stage_tones_dropped() == dropped0,
                  "set_stage_tones(false): SOUND 1035 goes to the mixer (none kept out)");
        }
        s.destroy(id);
    }
    s.set_stage_tones(true);
    s.set_super_whoosh(true);
}

// ---- 5b. the game's HUD (feat/cl_hud.lua: SA1_COPT_HUD_PARTS, sa1_character_screen) -----------------------------------
// what the HUD drew: draws, the textured ones from the character's CON_REGULAR, any without its texture
static void hud_of(Session &s, int32_t id, int32_t con, uint32_t &draws, uint32_t &con_draws, uint32_t &foreign)
{
    draws = con_draws = foreign = 0;
    const sa1_screen *scr = nullptr;
    if (sa1_character_screen(s.ctx(), id, &scr) != SA1_OK || !scr) {
        return;
    }
    draws = scr->num_draws;
    for (uint32_t i = 0; i < scr->num_draws; i++) {
        con_draws += scr->draws[i].archive == con;
        foreign += (scr->draws[i].flags & SA1_DRAW_NO_TEXTURE) != 0;
    }
}

static void test_hud(Session &s)
{
    std::printf("the game's HUD (rings, lives, time) for Super Sonic and through the transformation\n");
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    for (int k = 0; k < 2; k++) {
        int32_t kind = k == 0 ? SA1_CHAR_SUPER_SONIC : SA1_CHAR_SONIC;
        // a transformed Sonic as G-SA1 makes him (0.9.3a: the General form)
#if defined(SA1_API_SUPER_GENERAL)
        const uint32_t sonic_flags = SA1_SUPER_GENERAL;
#else
        const uint32_t sonic_flags = 0u;
#endif
        int32_t id = k == 0 ? mk(s, kind, at, 50, 0, true, 0u, err)
                            : mk(s, kind, at, 50, SA1_CREATE_SUPER_CAPABLE, true, sonic_flags, err);
        if (id <= 0) {
            CHECK(false, "create: %s", err.c_str());
            continue;
        }
        sa1_character_set_option(s.ctx(), id, SA1_COPT_HUD_PARTS, (int32_t)(SA1_HUD_RINGS | SA1_HUD_LIVES | SA1_HUD_TIME));
        int32_t con = archive_named(s, kind, "CON_REGULAR");
        run(s, id, 4, 0.0f);
        if (k == 1) {
            s.order(id, SA1_ORDER_SUPER);
            run(s, id, 2, 0.0f);
        }
        const Character *c = s.get(id);
        uint32_t d0 = 0, c0 = 0, f0 = 0;
        hud_of(s, id, con, d0, c0, f0);
        run(s, id, 65, 0.0f);      // the drain takes a ring meanwhile
        uint32_t d1 = 0, c1 = 0, f1 = 0;
        hud_of(s, id, con, d1, c1, f1);
        CHECK(c && c->super && d0 > 5 && c0 > 5 && f0 == 0 && d1 > 5 && c1 > 5 && f1 == 0 && c->st.rings >= 47 &&
                  c->st.rings <= 49,
              "%s Super: the HUD draws %u (%u from his CON_REGULAR, archive %d; none untextured), %u after the drain "
              "(%d rings)", k == 0 ? "Super Sonic" : "a transformed Sonic", d0, c0, con, d1, (int)(c ? c->st.rings : -1));
        s.destroy(id);
    }
}

// ---- 6. run on water ----------------------------------------------------------------------------------------------------
static void test_water(Session &s)
{
    std::printf("run on water (SA1_CREATE_WATER_FLOOR): a WATER box 400 HU deep over a floor\n");
    std::vector<sa1_collision_tri> tris;
    floor_tiles(tris, -4096.0f, 4096.0f, -4096.0f, 4096.0f, -400.0f, 1024.0f);
    box(tris, -3000.0f, 3000.0f, -3000.0f, 3000.0f, -400.0f, 0.0f, SA1_SURFACE_WATER);
    std::string err;
    if (!s.set_world(tris, err)) {
        CHECK(false, "set_world: %s", err.c_str());
        return;
    }
    const float at[3] = {0.0f, 0.0f, 12.0f};
    struct Case {
        uint32_t flags, host;
        const char *what;
    } cases[] = {
        {SA1_CREATE_WATER_FLOOR, 0, "run on water"},
        {SA1_CREATE_WATER_FLOOR, SA1_INPUT_HOST_WATER_KNOWN | SA1_INPUT_HOST_IN_WATER, "run on water, host KNOWN | IN_WATER"},
        {SA1_CREATE_WATER_FLOOR, SA1_INPUT_HOST_WATER_KNOWN, "run on water, host KNOWN (dry)"},
        {0, 0, "without it"},
    };
    for (const Case &cs : cases) {
        int32_t id = mk(s, SA1_CHAR_SUPER_SONIC, at, 50, cs.flags, true, SA1_SUPER_NO_DRAIN, err);
        const Character *c = id > 0 ? s.get(id) : nullptr;
        if (!c) {
            CHECK(false, "%s: create: %s", cs.what, err.c_str());
            continue;
        }
        TickExtra x;
        x.host_flags = cs.host;
        float zmin = 1e9f;
        for (int p = 0; p < 150; p++) {
            pair(s, id, p < 30 ? 0.0f : 1.0f, 0, &x);
            if (p >= 10) zmin = std::min(zmin, c->st.position[2]);
        }
        float run = std::hypot(c->st.position[0], c->st.position[1]);
        if (cs.flags) {
            CHECK(zmin > -6.0f && run > 300.0f && (c->st.flags & SA1_STATE_ON_GROUND),
                  "%s: lowest z %.1f over 140 pairs (on the water's top), %.0f HU run, on the ground", cs.what, (double)zmin,
                  (double)run);
        } else {
            CHECK(zmin < -300.0f, "%s: he sinks to z %.1f (the floor at -400)", cs.what, (double)zmin);
        }
        s.destroy(id);
    }
}

// ---- 6b. round 0.9.3a: the two Super Sonics (sadc docs/research/super_general_design.md 8.3 with its Review R.4) --------
#if defined(SA1_API_SUPER_GENERAL)
static const char *const kSonicUpgrades[3] = {"light_speed_shoes", "crystal_ring", "ancient_light"};

// Sonic's three upgrades as the module passes them (find_upgrade by the character's kind: kind 8 finds Sonic's rows)
static std::vector<const UpgradeDef *> sonic_upgrades(int32_t kind, int n = 3)
{
    std::vector<const UpgradeDef *> out;
    for (int i = 0; i < n; i++) {
        if (const UpgradeDef *u = find_upgrade(kind, kSonicUpgrades[i])) out.push_back(u);
    }
    return out;
}

static int32_t mk_up(Session &s, int32_t kind, const float pos[3], int32_t rings, uint32_t flags, uint32_t super_flags,
                     const std::vector<const UpgradeDef *> *ups, std::string &err)
{
    CreateExtra ex;
    ex.flags = flags;
    ex.super_given = true;
    ex.super_flags = super_flags;
    return s.create(kind, pos, 0.0f, err, nullptr, ups, rings, &ex);
}

// a General world as G-SA1 makes it (design 6.2): SUPER_CAPABLE, super flags GENERAL | extra
static int32_t mk_gen(Session &s, const float pos[3], int32_t rings, uint32_t extra, std::string &err,
                      const std::vector<const UpgradeDef *> *ups = nullptr)
{
    return mk_up(s, SA1_CHAR_SONIC, pos, rings, SA1_CREATE_SUPER_CAPABLE, SA1_SUPER_GENERAL | extra, ups, err);
}

// the body batches of a render by archive (not effects, not the shadow)
static uint32_t body_batches(const Character *c, int32_t archive)
{
    uint32_t n = 0;
    for (uint32_t i = 0; i < c->batch_count; i++) {
        const RenderBatch &b = c->batches[i];
        n += b.archive == archive && !(b.flags & (SA1_DRAW_EFFECT | SA1_DRAW_SHADOW)) && b.pass == 0;
    }
    return n;
}

// the flat floor of main() again (test_water leaves its water scene behind)
static bool flat_floor(Session &s)
{
    std::vector<sa1_collision_tri> floor;
    floor_tiles(floor, -8192.0f, 8192.0f, -2048.0f, 2048.0f, 0.0f, 1024.0f);
    std::string err;
    bool ok = s.set_world(floor, err);
    if (!ok) CHECK(false, "set_world: %s", err.c_str());
    return ok;
}

static void test_general(Session &s)
{
    std::printf("Super Sonic (General Gameplay): the General form in G-SA1's core (design 6.2, review RC1 / RC15)\n");
    if (!flat_floor(s)) return;
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    int32_t a5 = archive_named(s, SA1_CHAR_SONIC, "SUPERSONIC"), a0 = archive_named(s, SA1_CHAR_SONIC, "SONIC");
    // 1. the list entry: GENERAL | START with 50 rings (the drain on, G-SA1's default)
    int32_t id = mk_gen(s, at, 50, SA1_SUPER_START, err);
    const Character *c = id > 0 ? s.get(id) : nullptr;
    CHECK(c && c->super_capable && !c->super, "the General entry: Create(0, SUPER_CAPABLE, GENERAL | START, 50 rings) %s",
          err.c_str());
    if (!c) return;
    pair(s, id, 0.0f, 0);
    bool after1 = c->super;
    pair(s, id, 0.0f, 0);
    s.render(id, 1.0f);
    uint32_t sb = body_batches(c, a5), nb = body_batches(c, a0);
    CHECK(after1 && c->super && (c->st.equipment & 0x8000u) && c->st.rings == 50 && (c->st.mode < 71 || c->st.mode > 78) &&
              c->super_changes == 1 && sb > 0 && nb == 0,
          "Super right after his first pair (SA1_SUPER_START), %d rings, mode %d (Sonic's own modes, not the game's Super "
          "modes 71-78); %u body batches from his SUPERSONIC archive (%d), none from SONIC", (int)c->st.rings,
          (int)c->st.mode, sb, a5);
    s.destroy(id);
    // 2. review RC1: without START (a re-created General entry that was normal) he stays normal, whatever his rings
    id = mk_gen(s, at, 50, 0u, err);
    c = id > 0 ? s.get(id) : nullptr;
    if (c) run(s, id, 30, 0.0f);
    CHECK(c && !c->super && c->super_changes == 0 && c->st.rings == 50, "without START (RC1): normal Sonic for 30 pairs with "
          "50 rings (%u form changes)", c ? (unsigned)c->super_changes : 99u);
    if (id > 0) s.destroy(id);
    // 3. the transformation in a jump (the gesture's order): mode 8 and the speed kept, the voice once
    id = mk_gen(s, at, 50, SA1_SUPER_NO_DRAIN, err);
    c = id > 0 ? s.get(id) : nullptr;
    if (!c) {
        CHECK(false, "General create: %s", err.c_str());
        return;
    }
    sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_VOICE, 1116);
    sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SPEED, SA1_SUPER_SPEED_RUN);
    for (int p = 0; p < 60; p++) {
        pair(s, id, 1.0f, 0);
        if (g_verbose && p % 5 == 0) {
            std::printf("        run pair %d: mode %d action %d pos %.1f %.1f %.1f speed %.2f flags 0x%X\n", p, (int)c->st.mode,
                        (int)c->st.action, (double)c->st.position[0], (double)c->st.position[1], (double)c->st.position[2],
                        (double)c->st.player_speed[0], (unsigned)c->st.flags);
        }
    }
    for (int p = 0; p < 3; p++) {
        pair(s, id, 1.0f, J);
        if (g_verbose) {
            std::printf("        jump pair %d: mode %d action %d z %.1f speed %.2f\n", p, (int)c->st.mode, (int)c->st.action,
                        (double)c->st.position[2], (double)c->st.player_speed[0]);
        }
    }
    sa1_state_ex x0 = c->st;
    g_all.clear();
    sa1_status st = s.order(id, SA1_ORDER_SUPER);
    pair(s, id, 1.0f, J);
    sa1_state_ex x1 = c->st;
    int voice = count_ev(SA1_EVENT_SOUND, 1116);
    CHECK(st == SA1_OK && x0.mode == 8 && c->super && x1.mode == 8 && x1.player_speed[0] > 0.9f * x0.player_speed[0] &&
              voice == 1 && x1.rings == x0.rings,
          "in the jump (mode %d) at %.2f: SA1_ORDER_SUPER -> Super in mode %d at %.2f (the jump goes on), the voice 1116 "
          "once (%d), rings %d", (int)x0.mode, (double)x0.player_speed[0], (int)x1.mode, (double)x1.player_speed[0], voice,
          (int)x1.rings);
    // landed and running: faster than Sonic on the ground (RUN: the game's Super ground drag), his SUPERSONIC body
    float top = 0.0f;
    for (int p = 0; p < 150; p++) {
        pair(s, id, 1.0f, 0);
        top = std::max(top, c->st.player_speed[0]);
    }
    s.render(id, 1.0f);
    uint32_t sb2 = body_batches(c, a5);
    CHECK(c->super && top > 4.5f && sb2 > 0 && (c->st.mode < 71 || c->st.mode > 78),
          "150 pairs of running (Super run): %.2f units per step (plain Sonic's top 4.31), body from SUPERSONIC (%u)",
          (double)top, sb2);
    // 4. RC15 (G-SA1 part): the General body is anchored as kind 8's - every frame of a 144 fps run renders at the drawn
    //    step's root, and no more frames come "moved with the root" (a draw without a counterpart) than kind 8's
    auto anchoring = [&](int32_t cid, int frames, uint32_t &drawn_root, uint32_t &moved) {
        drawn_root = moved = 0;
        const Character *cc = s.get(cid);
        for (int f = 0; f < frames && cc; f++) {
            s.tick(cid, 0.0f, 1.0f, 0.0f, 0, 1.0f / 144.0f);
            s.poll_events(g_ev);
            s.render(cid, -1.0f);
            drawn_root += cc->r_drawn_root;
            moved += (cc->r_flags & SA1_RENDER_MOVED_WITH_ROOT) != 0;
            if (g_verbose && (cc->r_flags & SA1_RENDER_MOVED_WITH_ROOT)) {
                std::printf("        moved with the root: kind %d frame %d mode %d action %d speed %.2f alpha %.2f draws %u\n",
                            (int)cc->kind, f, (int)cc->st.mode, (int)cc->st.action, (double)cc->st.player_speed[0],
                            (double)cc->r_alpha, (unsigned)cc->r_draws.size());
            }
        }
    };
    // (the aura switched off for the measurement: its model changes at speed 7 and 13, and a new model has no counterpart in
    // the pair before, so that one pair of frames is moved with the root - the body's anchoring is what RC15 asks about)
    uint32_t g_root = 0, g_moved = 0, k_root = 0, k_moved = 0;
    sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_NO_AURA, 1);
    anchoring(id, 432, g_root, g_moved);
    sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_NO_AURA, 0);
    // 5. back: SA1_ORDER_NORMAL - Sonic's body, the speed kept
    sa1_state_ex x2 = c->st;
    st = s.order(id, SA1_ORDER_NORMAL);
    pair(s, id, 1.0f, 0);
    s.render(id, 1.0f);
    CHECK(st == SA1_OK && !c->super && body_batches(c, a0) > 0 && body_batches(c, a5) == 0 &&
              c->st.player_speed[0] > 0.8f * x2.player_speed[0],
          "SA1_ORDER_NORMAL: Sonic again (his SONIC body), running on at %.2f", (double)c->st.player_speed[0]);
    s.destroy(id);
    int32_t id8 = mk(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, true, SA1_SUPER_NO_DRAIN, err);
    if (id8 > 0) {
        run(s, id8, 60, 1.0f);
        anchoring(id8, 432, k_root, k_moved);
        s.destroy(id8);
    }
    CHECK(g_root == 432 && k_root == 432 && g_moved == 0 && k_moved == 0,
          "anchoring (RC15) over 3 s at 144 fps running: the General body drawn at the drawn root %u / 432 frames, %u frames "
          "moved with the root (no counterpart in the pair before); Vs. Perfect Chaos %u / 432, %u", g_root, g_moved, k_root,
          k_moved);
    // 6. upgrades are kept both ways (D12): the shoes give 0x8002 while Super, 0x0002 back
    std::vector<const UpgradeDef *> ups = sonic_upgrades(SA1_CHAR_SONIC, 1);
    id = mk_gen(s, at, 50, SA1_SUPER_START | SA1_SUPER_NO_DRAIN, err, &ups);
    c = id > 0 ? s.get(id) : nullptr;
    uint32_t eq_super = 0;
    if (c) {
        run(s, id, 3, 0.0f);
        eq_super = c->st.equipment;
        s.order(id, SA1_ORDER_NORMAL);
        run(s, id, 2, 0.0f);
    }
    CHECK(c && eq_super == 0x8002u && c->st.equipment == 0x0002u,
          "with the Light Speed Shoes: equipment %04X while Super, %04X after turning back", (unsigned)eq_super,
          c ? (unsigned)c->st.equipment : 0u);
    if (id > 0) s.destroy(id);
    // 7. the voice Preview (Session::preview_sound): into the mixer without any world
    std::string aerr;
    bool audio = s.audio_open(false, aerr);
    uint64_t e0 = s.audio().sound_events();
    bool pv = audio && s.preview_sound(0, 1116);
    bool pv_bad = s.preview_sound(0, 0) || s.preview_sound(0, 4096);
    CHECK(pv && !pv_bad && s.audio().sound_events() == e0 + 1,
          "the voice Preview: tone 1116 into the mixer once (sound events %llu -> %llu); tone 0 / 4096 refused (%s)",
          (unsigned long long)e0, (unsigned long long)s.audio().sound_events(), audio ? "banks open" : aerr.c_str());
    // review R.3.11: the tone is heard (the mixer resolves 1116 through the game's tone table to Sonic's voice bank; the
    // event's bank field is 0, as in the game's own push grunt): up to 3 s of output in 0.1 s pieces (a tone not decoded
    // yet waits in the mixer for a moment)
    double rms_best = 0.0;
    if (pv) {
        std::vector<int16_t> buf(4410 * 2);
        for (int piece = 0; piece < 30 && rms_best < 300.0; piece++) {
            s.audio().render(buf.data(), 4410);
            double acc = 0.0;
            for (int16_t v : buf) acc += (double)v * v;
            rms_best = std::max(rms_best, std::sqrt(acc / buf.size()));
            if (rms_best < 300.0) std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }
    CHECK(pv && rms_best >= 300.0, "the Preview is heard: rms %.0f in its loudest 0.1 s", rms_best);
    // 0.9.3b: the owner's "HM!" is Super Sonic's line 396, a voice clip (Session::preview_voice: an SA1_EVENT_VOICE, read
    // from the voice archive by the loader thread): one voice event, heard within 5 s; voice 4096 refused
    if (pv) {
        std::vector<int16_t> buf(4410 * 2);
        for (int piece = 0; piece < 20; piece++) s.audio().render(buf.data(), 4410);    // the tone has ended
    }
    uint64_t e1 = s.audio().sound_events();
    bool pc = audio && s.preview_voice(0, 396);
    bool pc_bad = s.preview_voice(0, 4096);
    double rms_clip = 0.0;
    if (pc) {
        std::vector<int16_t> buf(4410 * 2);
        for (int piece = 0; piece < 100 && rms_clip < 300.0; piece++) {
            s.audio().render(buf.data(), 4410);
            double acc = 0.0;
            for (int16_t v : buf) acc += (double)v * v;
            rms_clip = std::max(rms_clip, std::sqrt(acc / buf.size()));
            if (rms_clip < 300.0) std::this_thread::sleep_for(std::chrono::milliseconds(40));
        }
    }
    CHECK(pc && !pc_bad && s.audio().sound_events() == e1 + 1 && rms_clip >= 300.0,
          "Super Sonic's \"Hm!\" (voice clip 396): one voice event, heard (rms %.0f); voice 4096 refused", rms_clip);
    s.audio_close();
}

// the per-pair record of a kind-8 run (RC8): what the game does and draws
struct K8Rec {
    float pos[3], spd[3];
    int32_t mode, action;
    uint32_t draws, triangles;
    bool super;
    uint32_t sonic_body;    // body batches from the SONIC archive (the pair that takes request 46 still draws Sonic)
};

// RC8 input script (pairs): stand, run, jumps, homing, the air stop, run again
static void k8_input(int p, float &sy, uint32_t &b)
{
    sy = 0.0f;
    b = 0;
    if (p >= 20 && p < 120) sy = 1.0f;
    if ((p >= 90 && p < 99) || (p >= 104 && p < 108)) b = J;
    if (p >= 140 && p < 260) sy = 1.0f;
    if (p >= 200 && p < 206) b = J;
    if (p >= 215 && p < 218) b = B;                                  // the air stop (mode 74)
    if (p >= 280 && p < 285) b = J;
    if (p >= 290 && p < 294) b = J;
    if (p >= 320 && p < 600) sy = (p / 40) % 2 ? 1.0f : 0.6f;
}

static void test_vspc(Session &s)
{
    std::printf("Super Sonic (Vs. Perfect Chaos) in 0.9.3a: Sonic's upgrades (RC8), SA1_SUPER_START_NORMAL (RC1), one voice "
                "(RC11)\n");
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    // the module's upgrade names for kind 8 find Sonic's rows (find_upgrade), and create takes them
    std::vector<const UpgradeDef *> ups = sonic_upgrades(SA1_CHAR_SUPER_SONIC);
    CHECK(ups.size() == 3 && ups[0]->kind == SA1_CHAR_SONIC && upgrade_kind(SA1_CHAR_SUPER_SONIC) == SA1_CHAR_SONIC &&
              upgrade_kind(SA1_CHAR_TAILS) == SA1_CHAR_TAILS && find_upgrade(SA1_CHAR_SUPER_SONIC, "jet_anklet") == nullptr,
          "find_upgrade(8, name): Sonic's three rows (flags 0x8D 0x8E 0x9F); not Tails'");
    // RC8: one 600-pair script with and without the upgrades, 12 rings (the drain's revert at about 12 s): identical while
    // Super (position, speed, mode, action, draws per pair) up to the revert
    std::vector<K8Rec> rec[2];
    int32_t a_son = archive_named(s, SA1_CHAR_SUPER_SONIC, "SONIC");
    uint32_t eq_super[2] = {0, 0}, eq_after[2] = {0, 0};
    int revert_pair[2] = {-1, -1};
    for (int k = 0; k < 2; k++) {
        int32_t id = mk_up(s, SA1_CHAR_SUPER_SONIC, at, 12, 0, 0u, k ? &ups : nullptr, err);
        const Character *c = id > 0 ? s.get(id) : nullptr;
        if (!c) {
            CHECK(false, "kind 8 create (%s): %s", k ? "upgrades" : "none", err.c_str());
            return;
        }
        for (int p = 0; p < 600; p++) {
            float sy;
            uint32_t b;
            k8_input(p, sy, b);
            pair(s, id, sy, b);
            s.render(id, 1.0f);
            K8Rec r;
            std::memcpy(r.pos, c->st.position, sizeof r.pos);
            std::memcpy(r.spd, c->st.player_speed, sizeof r.spd);
            r.mode = c->st.mode;
            r.action = c->st.action;
            r.draws = (uint32_t)c->r_draws.size();
            r.triangles = c->r_triangles;
            r.super = c->super;
            r.sonic_body = body_batches(c, a_son);
            rec[k].push_back(r);
            if (c->super && p > 4 && !eq_super[k]) eq_super[k] = c->st.equipment;
            if (revert_pair[k] < 0 && c->super_changes >= 2) revert_pair[k] = p;
        }
        eq_after[k] = c->st.equipment;
        s.destroy(id);
    }
    // the game state at every pair up to the revert; the draws while he is Super (before the trigger's pair normal Sonic
    // draws the upgrades' parts on Sonic's own body, as in the game)
    int upto = revert_pair[0] < 0 ? 600 : revert_pair[0];
    int differ = -1, super_pairs = 0, sonic_drawn = 0;
    for (int p = 0; p < upto && differ < 0; p++) {
        const K8Rec &a = rec[0][p], &b = rec[1][p];
        // drawn as Super Sonic: one of the game's Super actions 130-141 (the pairs that take request 46 still show action 0:
        // Sonic's own tree, which carries the upgrades' parts - the game's display of those two pairs)
        bool super_drawn = a.super && b.super && a.action >= 130 && a.action <= 141 && b.action >= 130 && b.action <= 141;
        bool draws_differ = super_drawn && (a.draws != b.draws || a.triangles != b.triangles);
        super_pairs += super_drawn;
        sonic_drawn += a.super && !super_drawn;
        if (std::memcmp(a.pos, b.pos, sizeof a.pos) || std::memcmp(a.spd, b.spd, sizeof a.spd) || a.mode != b.mode ||
            a.action != b.action || draws_differ || a.super != b.super) {
            differ = p;
        }
    }
    CHECK(differ < 0 && revert_pair[0] > 100 && super_pairs > 300 && sonic_drawn <= 2 && revert_pair[0] == revert_pair[1] &&
              eq_super[0] == 0x8000u &&
              eq_super[1] == 0x8007u && eq_after[1] == 0x0007u,
          "RC8: kind 8 plays the same with Sonic's three upgrades (%s; %d pairs compared up to the drain's revert at pair "
          "%d / %d, %d of them in the Super actions with their draws; %d Super pair(s) before the first Super action, drawn "
          "with Sonic's tree as the game does); equipment %04X / %04X while Super, %04X after the revert (he has his "
          "upgrades again)",
          differ < 0 ? "every pair identical" : "DIFFERS", differ < 0 ? upto : differ, revert_pair[0], revert_pair[1],
          super_pairs, sonic_drawn,
          (unsigned)eq_super[0], (unsigned)eq_super[1], (unsigned)eq_after[1]);
    if (g_verbose) {
        for (int p = 0; p < 12 && p < upto; p++) {
            const K8Rec &a = rec[0][p], &b = rec[1][p];
            std::printf("        RC8 pair %d: super %d/%d mode %d/%d action %d/%d draws %u/%u tris %u/%u sonic body %u/%u\n", p,
                        (int)a.super, (int)b.super, (int)a.mode, (int)b.mode, (int)a.action, (int)b.action, a.draws, b.draws,
                        a.triangles, b.triangles, a.sonic_body, b.sonic_body);
        }
        int game_differ = 0, draw_differ = 0;
        for (int p = 0; p < upto; p++) {
            const K8Rec &a = rec[0][p], &b = rec[1][p];
            game_differ += std::memcmp(a.pos, b.pos, sizeof a.pos) || std::memcmp(a.spd, b.spd, sizeof a.spd) ||
                           a.mode != b.mode || a.action != b.action || a.super != b.super;
            draw_differ += a.draws != b.draws || a.triangles != b.triangles;
        }
        std::printf("        RC8: %d pairs with another game state, %d with other draws (of %d)\n", game_differ, draw_differ, upto);
    }
    if (differ >= 0) {
        const K8Rec &a = rec[0][differ], &b = rec[1][differ];
        INFO("pair %d: mode %d / %d, action %d / %d, draws %u / %u, x %.4f / %.4f", differ, (int)a.mode, (int)b.mode,
             (int)a.action, (int)b.action, a.draws, b.draws, (double)a.pos[0], (double)b.pos[0]);
    }
    // RC1: SA1_SUPER_START_NORMAL - a re-created kind 8 that had turned back starts as normal Sonic (no trigger) and takes
    // the transformation; RC11: two orders in one frame give one voice
    int32_t id = mk_up(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, SA1_SUPER_START_NORMAL, &ups, err);
    const Character *c = id > 0 ? s.get(id) : nullptr;
    if (c) {
        sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_VOICE, 1116);
        run(s, id, 10, 0.0f);
    }
    bool normal = c && !c->super && c->super_changes == 0 && c->st.equipment == 0x0007u;
    g_all.clear();
    sa1_status o1 = c ? s.order(id, SA1_ORDER_SUPER) : SA1_ERR_NOT_FOUND;
    sa1_status o2 = c ? s.order(id, SA1_ORDER_SUPER) : SA1_ERR_NOT_FOUND;
    if (c) run(s, id, 4, 0.0f);
    int voices = count_ev(SA1_EVENT_SOUND, 1116);
    CHECK(normal && o1 == SA1_OK && o2 == SA1_OK && c->super && c->st.mode >= 71 && c->st.mode <= 78 && voices == 1,
          "START_NORMAL: normal Sonic for 10 pairs (equipment %04X, no form change); two orders in a frame: Super (the "
          "game's mode %d) with the voice 1116 once (%d)", c ? (unsigned)c->st.equipment : 0u, c ? (int)c->st.mode : -1,
          voices);
    if (id > 0) s.destroy(id);
    // the game's own trigger plays no voice
    id = mk_up(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, SA1_SUPER_NO_DRAIN, nullptr, err);
    c = id > 0 ? s.get(id) : nullptr;
    g_all.clear();
    if (c) {
        sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_VOICE, 1116);
        run(s, id, 6, 0.0f);
    }
    CHECK(c && c->super && count_ev(SA1_EVENT_SOUND, 1116) == 0, "the game's own trigger: Super, no voice");
    // the options a kind 8 takes: VOICE and the two game options; SPEED / NO_AURA / SUPER_EFFECTS are General only
    if (c) {
        sa1_status a = sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_NO_AURA, 1);
        sa1_status b = sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SPEED, 1);
        sa1_status g1 = sa1_character_set_game_option(s.ctx(), id, SA1_GOPT_SUPER_IDLE_BY_FORM, 1);
        sa1_status g2 = sa1_character_set_game_option(s.ctx(), id, SA1_GOPT_SUPER_AURA_ANIM, SA1_AURA_ANIM_CALM);
        CHECK(a == SA1_ERR_UNSUPPORTED && b == SA1_ERR_UNSUPPORTED && g1 == SA1_OK && g2 == SA1_OK,
              "kind 8: NO_AURA / SPEED unsupported (his aura and physics stay the game's); idle voices by form and the aura "
              "animation taken");
    }
    if (id > 0) s.destroy(id);
}

// RC9: the standing aura's texture changes per second through Session's render (what G-SA1 draws) at 60 and 144 fps
static int32_t aura_texture(const Character *c, int32_t ss)
{
    int32_t tex = -1;
    uint32_t best = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < c->batch_count; i++) {
        const RenderBatch &b = c->batches[i];
        if (b.archive == ss && (b.flags & SA1_DRAW_ADDITIVE) && (b.flags & SA1_DRAW_EFFECT) &&
            (b.prims & (1u << SA1_PRIM_TRIANGLES)) && b.order < best) {
            best = b.order;
            tex = b.texture;
        }
    }
    return tex;
}

static void test_aura_rate(Session &s)
{
    std::printf("the aura animation through G-SA1's render (RC9): texture changes per second at 60 and 144 fps\n");
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    static const char *const names[3] = {"Dreamcast", "Calm", "Slow"};
    int32_t ss8 = archive_named(s, SA1_CHAR_SUPER_SONIC, "SUPERSONIC"), ss0 = archive_named(s, SA1_CHAR_SONIC, "SUPERSONIC");
    for (int k = 0; k < 2; k++) {
        for (int v = 0; v < 3; v++) {
            for (int fps : {60, 144}) {
                int32_t id = k == 0 ? mk(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, true, SA1_SUPER_NO_DRAIN, err)
                                    : mk_gen(s, at, 50, SA1_SUPER_START | SA1_SUPER_NO_DRAIN, err);
                const Character *c = id > 0 ? s.get(id) : nullptr;
                if (!c) {
                    CHECK(false, "aura: create: %s", err.c_str());
                    return;
                }
                sa1_character_set_game_option(s.ctx(), id, SA1_GOPT_SUPER_AURA_ANIM, v);
                run(s, id, 8, 0.0f);
                int changes = 0, frames = 2 * fps, last = -1, bad_order = 0;
                uint32_t seen = 0;
                for (int f = 0; f < frames; f++) {
                    s.tick(id, 0.0f, 0.0f, 0.0f, 0, 1.0f / (float)fps);
                    s.poll_events(g_ev);
                    s.render(id, -1.0f);
                    int32_t t = aura_texture(c, k == 0 ? ss8 : ss0);
                    if (t >= 0 && t < 32) seen |= 1u << t;
                    if (last >= 0 && t != last) {
                        changes++;
                        // Calm and Slow: the next frame in order (16..23, wrapping)
                        if (v != 0 && t >= 16 && t <= 23 && last >= 16 && last <= 23 && ((last - 16 + 1) & 7) != t - 16) {
                            bad_order++;
                        }
                    }
                    last = t;
                }
                int distinct = 0;
                for (int b = 16; b <= 23; b++) distinct += (seen >> b) & 1u;
                double per_s = changes / 2.0;
                bool ok = v == 0 ? (distinct == 4 && per_s >= 28.0 && per_s <= 31.0)
                                 : v == 1 ? (distinct == 8 && per_s >= 28.0 && per_s <= 31.0 && bad_order == 0)
                                          : (distinct == 8 && per_s >= 14.0 && per_s <= 15.5 && bad_order == 0);
                CHECK(ok, "%s, %s at %d fps: %.1f texture changes per second, %d of the standing aura's 8 textures%s",
                      k == 0 ? "Vs. Perfect Chaos" : "General", names[v], fps, per_s, distinct,
                      bad_order ? " (OUT OF ORDER)" : (v ? ", in order" : ""));
                s.destroy(id);
            }
        }
    }
}

// ---- 6c. round 0.9.4a: Super Sonic polish (sadc docs/research/super2_plan.md 6.4 with its review and the owner's answers
// of 10.1): N1 his own poses, N2 the golden Light Speed charge and spin dash sparks, N3 the aura's whoosh -----------------
#if defined(SA1_API_SUPER_POLISH)
// the body's lowest point above the drawn root, in HU (the character's own textured triangle draws, not the shadow, not
// additive: LIB tests/super_test.c ext_of, through Session's copy of the render); false when nothing was drawn
static bool body_low(const Character *c, float &lo)
{
    lo = 1e9f;
    uint32_t n = 0;
    if (!c) return false;
    for (const sa1_draw &d : c->r_draws) {
        if (d.prim != SA1_PRIM_TRIANGLES || d.source != SA1_SOURCE_CHARACTER || d.archive < 0 ||
            (d.flags & (SA1_DRAW_SHADOW | SA1_DRAW_ADDITIVE))) {
            continue;
        }
        uint32_t end = std::min(d.first + d.count, c->r_triangles);
        for (uint32_t t = d.first; t < end; t++) {
            for (int k = 0; k < 3; k++) {
                lo = std::min(lo, c->r_tpos[(size_t)t * 9u + (size_t)k * 3u + 2u]);
                n++;
            }
        }
    }
    lo -= c->r_pos[2];
    return n > 0;
}

// the index of a texture of an archive by its name (-1: none)
static int32_t tex_named(Session &s, int32_t kind, int32_t archive, const char *name)
{
    uint32_t n = 0;
    std::string e;
    if (archive < 0 || !s.texture_count(kind, (uint32_t)archive, n, e)) return -1;
    for (uint32_t i = 0; i < n; i++) {
        sa1_texture_info ti;
        std::memset(&ti, 0, sizeof ti);
        ti.struct_size = sizeof ti;
        if (sa1_texture_get(s.ctx(), kind, (uint32_t)archive, i, &ti) == SA1_OK && ti.name && std::strcmp(ti.name, name) == 0) {
            return (int32_t)i;
        }
    }
    return -1;
}

// N1 (SA1_SUPOPT_SUPER_ANIMS): the General entry's stand drawn through Session's render, against kind 8's (the game's own
// placement of action 130; 094a-lib-anim measured -1.165..-0.402 units, kind 8 -1.164..-0.404; option 0 -0.150..0.078)
static void test_poses(Session &s)
{
    std::printf("Super Sonic's own poses (0.9.4a N1, SA1_SUPOPT_SUPER_ANIMS): the General entry's stand through Session's "
                "render against Vs. Perfect Chaos\n");
    if (!flat_floor(s)) return;
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    struct Band {
        float lo = 1e9f, hi = -1e9f;
        int n = 0;
    };
    auto stand = [&](int32_t id, Band &b) {
        run(s, id, 20, 0.0f);   // landed (the spawn is 8 HU up) and Super
        for (int p = 0; p < 140; p++) {
            pair(s, id, 0.0f, 0);
            s.render(id, 1.0f);
            float lo = 0.0f;
            if (body_low(s.get(id), lo)) {
                b.lo = std::min(b.lo, lo);
                b.hi = std::max(b.hi, lo);
                b.n++;
            }
        }
    };
    Band k8, g1, g0;
    int32_t id = mk(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, true, SA1_SUPER_NO_DRAIN, err);
    sa1_status k8a = SA1_OK, k8l = SA1_OK;
    if (id > 0) {
        // kind 8 refuses both options of this round (it is the game's own Super Sonic already)
        k8a = sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_ANIMS, 1);
        k8l = sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_LSD_GOLD, 1);
        stand(id, k8);
        s.destroy(id);
    }
    sa1_status opt_st[2] = {SA1_ERR_GAME_FAULT, SA1_ERR_GAME_FAULT}, bad2 = SA1_OK;
    for (int opt = 1; opt >= 0; opt--) {
        id = mk_gen(s, at, 50, SA1_SUPER_START | SA1_SUPER_NO_DRAIN, err);
        if (id <= 0) {
            CHECK(false, "General create: %s", err.c_str());
            continue;
        }
        opt_st[opt] = sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_ANIMS, opt);
        if (opt == 1) bad2 = sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_ANIMS, 2);
        stand(id, opt ? g1 : g0);
        s.destroy(id);
    }
    // a plain Sonic (not General) refuses it too
    id = s.create(SA1_CHAR_SONIC, at, 0.0f, err);
    sa1_status plain = id > 0 ? sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_ANIMS, 1) : SA1_OK;
    if (id > 0) s.destroy(id);
    CHECK(opt_st[0] == SA1_OK && opt_st[1] == SA1_OK && bad2 == SA1_ERR_INVALID_ARGUMENT && k8a == SA1_ERR_UNSUPPORTED &&
              k8l == SA1_ERR_UNSUPPORTED && plain == SA1_ERR_UNSUPPORTED,
          "SA1_SUPOPT_SUPER_ANIMS 0 / 1 taken by the General entry, 2 refused (%s); kind 8 refuses SUPER_ANIMS and "
          "LSD_GOLD (%s / %s), a plain Sonic SUPER_ANIMS (%s)", sa1_status_string(bad2), sa1_status_string(k8a),
          sa1_status_string(k8l), sa1_status_string(plain));
    const float u = 4.0f;   // HU per SA1 unit
    INFO("lowest body point above the drawn root over 140 standing pairs (HU): Vs. Perfect Chaos %.3f..%.3f, General "
         "with the poses %.3f..%.3f, without %.3f..%.3f", (double)k8.lo, (double)k8.hi, (double)g1.lo, (double)g1.hi,
         (double)g0.lo, (double)g0.hi);
    CHECK(k8.n == 140 && g1.n == 140 && g1.lo >= -1.17f * u - 0.1f && g1.hi <= -0.40f * u + 0.1f &&
              std::fabs(g1.lo - k8.lo) <= 0.1f && std::fabs(g1.hi - k8.hi) <= 0.1f && g1.hi - g1.lo > 0.5f * u,
          "N1: with the poses the General entry floats like Vs. Perfect Chaos (the game's stand 130 and its bob): lowest "
          "point %.2f..%.2f HU (kind 8 %.2f..%.2f; the range -4.68..-1.60 +-0.1)", (double)g1.lo, (double)g1.hi,
          (double)k8.lo, (double)k8.hi);
    CHECK(g0.n == 140 && g0.lo >= -0.15f * u - 0.1f && g0.hi <= 0.078f * u + 0.1f,
          "without them (0.9.3a's look) Sonic's stand on the golden body: lowest point %.2f..%.2f HU (-0.60..0.31 +-0.1)",
          (double)g0.lo, (double)g0.hi);
}

static bool is_glow(const sa1_draw &d)
{
    return d.prim == SA1_PRIM_TRIANGLES && d.archive < 0 && d.material == 0x26182400u && d.source == SA1_SOURCE_MODEL;
}

// N2 (SA1_SUPOPT_LSD_GOLD, SA1_SUPOPT_SUPER_EFFECTS 3): two General worlds in lockstep with the option 0 and 1, as libsa1's
// gold_test (2): 8 pairs standing, the action button held 130 pairs (the Light Speed charge), released and pushed 40 pairs;
// (A) the owner's three upgrades (the Crystal Ring: its green lcharge03 / 04 never gold, owner answer O3), (B) the shoes
// alone (the plain lcharge01 / 02 gold). The batches as G-SA1 builds them: WRAP_GOLD exactly on the plain charge's, keys
// otherwise the option-0 run's; the glow's vertex colours max + min - c of the option-0 run's (+-1; review R.3); the spin
// dash sparks SUPERSONIC ss_ball (SA1_SUPER_EFFECTS_DUST), never SON_EFF s_ball; the variant through Session::texture_runs
// (gsa1.Texture's path) equals libsa1's sa1_texture_variant_get
static void test_gold(Session &s)
{
    std::printf("the golden Light Speed charge (0.9.4a N2, SA1_SUPOPT_LSD_GOLD) and spin dash sparks (SUPER_EFFECTS 3)\n");
    if (!flat_floor(s)) return;
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    int32_t eff = archive_named(s, SA1_CHAR_SONIC, "SON_EFF"), a5 = archive_named(s, SA1_CHAR_SONIC, "SUPERSONIC");
    int32_t l[4];
    for (int i = 0; i < 4; i++) {
        char nm[16];
        std::snprintf(nm, sizeof nm, "lcharge0%d", i + 1);
        l[i] = tex_named(s, SA1_CHAR_SONIC, eff, nm);
    }
    int32_t sb[2] = {tex_named(s, SA1_CHAR_SONIC, eff, "s_ball_a"), tex_named(s, SA1_CHAR_SONIC, eff, "s_ball_b")};
    int32_t ssb[2] = {tex_named(s, SA1_CHAR_SONIC, a5, "ss_ball_a"), tex_named(s, SA1_CHAR_SONIC, a5, "ss_ball_b")};
    CHECK(eff >= 0 && a5 >= 0 && l[0] >= 0 && l[1] >= 0 && l[2] >= 0 && l[3] >= 0 && sb[0] >= 0 && ssb[0] >= 0,
          "Sonic's SON_EFF (%d: lcharge01-04 = %d %d %d %d, s_ball_a %d) and SUPERSONIC (%d: ss_ball_a %d)", eff, l[0], l[1],
          l[2], l[3], sb[0], a5, ssb[0]);
    if (eff < 0 || a5 < 0 || l[0] < 0 || l[1] < 0 || l[2] < 0 || l[3] < 0) return;
    // the variant through Session::texture_runs (review R.6: gsa1.Texture(kind, index, archive, 1))
    int same = 0, alpha_kept = 0, recoloured = 0;
    for (int i = 0; i < 4; i++) {
        TextureRuns base, var;
        std::string e1, e2;
        std::vector<uint8_t> pb, pv;
        sa1_texture_info ti;
        std::memset(&ti, 0, sizeof ti);
        ti.struct_size = sizeof ti;
        if (!s.texture_runs(SA1_CHAR_SONIC, (uint32_t)eff, (uint32_t)l[i], base, e1) ||
            !s.texture_runs(SA1_CHAR_SONIC, (uint32_t)eff, (uint32_t)l[i], var, e2, SA1_TEXTURE_VARIANT_SUPER_GOLD) ||
            !paint_runs(base, pb) || !paint_runs(var, pv) ||
            sa1_texture_variant_get(s.ctx(), SA1_CHAR_SONIC, (uint32_t)eff, (uint32_t)l[i], SA1_TEXTURE_VARIANT_SUPER_GOLD,
                                    &ti) != SA1_OK || !ti.rgba || pv.size() != (size_t)ti.width * ti.height * 4u) {
            continue;
        }
        same += std::memcmp(pv.data(), ti.rgba, pv.size()) == 0;
        bool akept = pb.size() == pv.size(), rgb = false;
        for (size_t p = 0; akept && p < pv.size(); p += 4) {
            akept = pb[p + 3] == pv[p + 3];
            rgb = rgb || std::memcmp(&pb[p], &pv[p], 3) != 0;
        }
        alpha_kept += akept;
        recoloured += rgb;
    }
    TextureRuns refused;
    std::string eref;
    bool ball_refused = sb[0] >= 0 && !s.texture_runs(SA1_CHAR_SONIC, (uint32_t)eff, (uint32_t)sb[0], refused, eref,
                                                      SA1_TEXTURE_VARIANT_SUPER_GOLD);
    CHECK(same == 4 && alpha_kept == 4 && recoloured == 4 && ball_refused,
          "the golden variant of lcharge01-04 through Session::texture_runs: %d of 4 equal to libsa1's, alpha kept in %d, "
          "recoloured in %d; s_ball_a has none (%s)", same, alpha_kept, recoloured, eref.c_str());
    for (int scen = 0; scen < 2; scen++) {
        std::vector<const UpgradeDef *> ups = sonic_upgrades(SA1_CHAR_SONIC, scen == 0 ? 3 : 1);
        int32_t id0 = mk_gen(s, at, 50, SA1_SUPER_START | SA1_SUPER_NO_DRAIN, err, &ups);
        int32_t id1 = mk_gen(s, at, 50, SA1_SUPER_START | SA1_SUPER_NO_DRAIN, err, &ups);
        if (id0 <= 0 || id1 <= 0) {
            CHECK(false, "General create: %s", err.c_str());
            if (id0 > 0) s.destroy(id0);
            if (id1 > 0) s.destroy(id1);
            continue;
        }
        int opts = 0;
        for (int32_t id : {id0, id1}) {
            opts += sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SPEED, SA1_SUPER_SPEED_RUN) == SA1_OK;
            opts += sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_EFFECTS,
                                                   SA1_SUPER_EFFECTS_CLONES | SA1_SUPER_EFFECTS_DUST) == SA1_OK;
            opts += sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_ANIMS, 1) == SA1_OK;
            opts += sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_LSD_GOLD, id == id1 ? 1 : 0) == SA1_OK;
        }
        uint32_t pairs = 0, gold0 = 0, key_bad = 0, ring_batches = 0, ring_gold = 0, plain_gold[2] = {0, 0}, glow = 0;
        uint32_t glow_bad = 0, glow_pairs = 0, ss_ball = 0, s_ball = 0;
        std::string first_bad;
        const Character *c0 = s.get(id0), *c1 = s.get(id1);
        for (int p = 0; p < 8 + 130 + 40 && c0 && c1; p++) {
            uint32_t b = (p >= 8 && p < 138) ? B : 0;
            float sy = p >= 138 ? 1.0f : 0.0f;
            pair(s, id0, sy, b);
            pair(s, id1, sy, b);
            s.render(id0, 1.0f);
            s.render(id1, 1.0f);
            pairs++;
            if (c0->batch_count != c1->batch_count || c0->r_draws.size() != c1->r_draws.size() ||
                c0->r_triangles != c1->r_triangles) {
                key_bad++;
                if (first_bad.empty()) first_bad = format("pair %d: %u / %u batches", p, c0->batch_count, c1->batch_count);
                continue;
            }
            for (uint32_t i = 0; i < c1->batch_count; i++) {
                const RenderBatch &b0 = c0->batches[i], &b1 = c1->batches[i];
                gold0 += (b0.wrap & WRAP_GOLD) != 0;
                bool gold = (b1.wrap & WRAP_GOLD) != 0;
                bool same_state = b0.archive == b1.archive && b0.texture == b1.texture && b0.flags == b1.flags &&
                                  b0.blend_src == b1.blend_src && b0.blend_dst == b1.blend_dst && b0.pass == b1.pass &&
                                  b0.wrap == (b1.wrap & ~WRAP_GOLD) && b0.triangles == b1.triangles;
                if (!same_state || (!gold && b0.key != b1.key)) {
                    key_bad++;
                    if (first_bad.empty()) first_bad = format("pair %d batch %u: %s / %s", p, i, b0.key.c_str(), b1.key.c_str());
                }
                if (b1.archive == eff && (b1.texture == l[2] || b1.texture == l[3])) {
                    ring_batches++;
                    ring_gold += gold;
                }
                if (gold && b1.archive == eff && b1.texture == l[0]) plain_gold[0]++;
                if (gold && b1.archive == eff && b1.texture == l[1]) plain_gold[1]++;
                if (gold && !(b1.archive == eff && (b1.texture == l[0] || b1.texture == l[1]))) key_bad++;
                if (b1.archive == eff && (b1.texture == sb[0] || b1.texture == sb[1])) s_ball++;
                if (b1.archive == a5 && (b1.texture == ssb[0] || b1.texture == ssb[1])) ss_ball++;
            }
            bool had_glow = false;
            for (size_t di = 0; di < c1->r_draws.size(); di++) {
                const sa1_draw &d0 = c0->r_draws[di], &d1 = c1->r_draws[di];
                if (!is_glow(d1)) continue;
                glow++;
                had_glow = true;
                if (!is_glow(d0) || d0.first != d1.first || d0.count != d1.count) {
                    glow_bad++;
                    continue;
                }
                uint32_t end = std::min(d1.first + d1.count, c1->r_triangles);
                for (uint32_t t = d1.first; t < end; t++) {
                    for (int k = 0; k < 3; k++) {
                        const uint8_t *q0 = &c0->r_tcol[(size_t)t * 12u + (size_t)k * 4u];
                        const uint8_t *q1 = &c1->r_tcol[(size_t)t * 12u + (size_t)k * 4u];
                        int mx = std::max(q0[0], std::max(q0[1], q0[2])), mn = std::min(q0[0], std::min(q0[1], q0[2]));
                        bool ok = std::abs((int)q1[3] - (int)q0[3]) <= 1;
                        for (int ch = 0; ch < 3; ch++) ok = ok && std::abs((int)q1[ch] - (mx + mn - (int)q0[ch])) <= 1;
                        glow_bad += !ok;
                    }
                }
            }
            glow_pairs += had_glow;
        }
        s.destroy(id0);
        s.destroy(id1);
        if (scen == 0) {
            CHECK(opts == 8 && pairs == 178 && key_bad == 0 && gold0 == 0 && ring_batches > 0 && ring_gold == 0 &&
                      plain_gold[0] == 0 && plain_gold[1] == 0 && glow_pairs > 0 && glow_bad == 0,
                  "(A) the shoes, the Crystal Ring and the Ancient Light, the charge with the option 0 / 1 in lockstep: the "
                  "Crystal Ring's sparkles / streaks (lcharge03 / 04) in %u batches, none WRAP_GOLD (owner answer O3); the "
                  "glow in %u pairs (%u draws) = max + min - c of the option-0 run's (%u corners off); every other batch "
                  "and key as the option-0 run's (%u differ%s%s), which has no gold batch (%u)", ring_batches, glow_pairs,
                  glow, glow_bad, key_bad, first_bad.empty() ? "" : ": ", first_bad.c_str(), gold0);
        } else {
            CHECK(opts == 8 && pairs == 178 && key_bad == 0 && gold0 == 0 && plain_gold[0] > 0 && plain_gold[1] > 0 &&
                      ring_gold == 0 && glow_pairs > 0 && glow_bad == 0,
                  "(B) the shoes alone: the plain streaks (lcharge01: %u batches) and sparkles (lcharge02: %u) carry "
                  "WRAP_GOLD (their archive and texture the game's), nothing else; the glow gold in %u pairs (%u corners "
                  "off); every key otherwise the option-0 run's (%u differ%s%s); the option-0 run has none (%u)",
                  plain_gold[0], plain_gold[1], glow_pairs, glow_bad, key_bad, first_bad.empty() ? "" : ": ",
                  first_bad.c_str(), gold0);
        }
        CHECK(ss_ball > 0 && s_ball == 0, "%s: the spin dash sparks with SUPER_EFFECTS 3 (CLONES | DUST) are SUPERSONIC "
              "ss_ball (%u batches), never SON_EFF s_ball (%u)", scen == 0 ? "(A)" : "(B)", ss_ball, s_ball);
    }
    // SUPER_EFFECTS 1 (0.9.3a's value: the clones only): the sparks stay Sonic's blue s_ball
    int32_t id = mk_gen(s, at, 50, SA1_SUPER_START | SA1_SUPER_NO_DRAIN, err);
    uint32_t blue = 0, gold_ball = 0;
    if (id > 0) {
        sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_EFFECTS, SA1_SUPER_EFFECTS_CLONES);
        const Character *c = s.get(id);
        for (int p = 0; p < 60 && c; p++) {
            pair(s, id, 0.0f, (p >= 8 && p < 40) ? B : 0);
            s.render(id, 1.0f);
            for (uint32_t i = 0; i < c->batch_count; i++) {
                const RenderBatch &rb = c->batches[i];
                blue += rb.archive == eff && (rb.texture == sb[0] || rb.texture == sb[1]);
                gold_ball += rb.archive == a5 && (rb.texture == ssb[0] || rb.texture == ssb[1]);
            }
        }
        s.destroy(id);
    }
    // (the golden ss_ball draws that remain are the Super ball's after-image clones, SA1_SUPER_EFFECTS_CLONES)
    CHECK(blue > 0, "SUPER_EFFECTS 1 (the clones only, 0.9.3a's value): a spin dash's sparks stay Sonic's blue SON_EFF "
          "s_ball (%u batches; %u golden ss_ball batches of the ball's after-images)", blue, gold_ball);
}
#endif  // SA1_API_SUPER_POLISH

#if defined(SA1_AUDIO_HAS_STAGE_RULES)
// the character's whoosh rule {19, 1035, 1036} in Audio's slot 0
static bool whoosh_rule_of(Session &s, int32_t id)
{
    StageRule r;
    return s.audio().stage_rule(id, kRuleWhoosh, r) && r.stage == kStagePerfectChaos && r.first == kWhooshFirst &&
           r.last == kWhooshLast;
}

// no rule in any slot
static bool no_rules(Session &s, int32_t id)
{
    StageRule r;
    for (uint32_t k = 0; k < kRuleSlots; k++) {
        if (s.audio().stage_rule(id, k, r)) return false;
    }
    return true;
}

// renders the mixer for `ms` milliseconds in 0.1 s pieces; the loudest piece's rms
static double mix_for(Session &s, int ms)
{
    std::vector<int16_t> buf(4410 * 2);
    double best = 0.0;
    for (int t = 0; t < ms; t += 100) {
        s.audio().render(buf.data(), 4410);
        double acc = 0.0;
        for (int16_t v : buf) acc += (double)v * v;
        best = std::max(best, std::sqrt(acc / buf.size()));
    }
    return best;
}

// the Perfect Chaos stage's banks: READY (or FAILED) within `ms` (the loader thread reads CHAOS7B.MLT)
static int32_t wait_stage(Session &s, int ms)
{
    int32_t st = s.audio().stage_state(kStagePerfectChaos);
    for (int t = 0; t < ms && st != SA1_AUDIO_STAGE_READY && st != SA1_AUDIO_STAGE_FAILED; t += 10) {
        mix_for(s, 0);
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        st = s.audio().stage_state(kStagePerfectChaos);
    }
    return st;
}

// a crossing of speed 7 (the slow whoosh 1035): below 6 first (the aura's state machine re-arms), then 8.5. voices: the
// mixer's voices that the crossing added (the whoosh is two looping layers; a released voice fades inaudibly for some
// seconds before the mixer frees it, so the count before the crossing is subtracted), rms: the loudest 0.1 s of the next
// 0.6 s
static void crossing(Session &s, int32_t id, int &events, uint32_t &voices, double &rms)
{
    set_speed(s, id, 2.0f);
    pair(s, id, 0.0f, 0);
    mix_for(s, 2800);               // what played ends (the whoosh's 120-frame lifetime: a 2 s swoosh)
    uint32_t before = s.audio().active();
    g_all.clear();
    set_speed(s, id, 8.5f);
    pair(s, id, 0.0f, 0);
    events = count_ev(SA1_EVENT_SOUND, kWhooshFirst);
    voices = 0;
    rms = 0.0;
    for (int piece = 0; piece < 6; piece++) {
        rms = std::max(rms, mix_for(s, 100));
        uint32_t now = s.audio().active();
        voices = std::max(voices, now > before ? now - before : 0u);
    }
    if (g_verbose) std::printf("        crossing: %u voices before, %u added, rms %.0f\n", before, voices, rms);
}

// N3 (super2_plan.md 6.4 task 5, super2_sound.md 8.3): (a) who holds the rule, (b) the whoosh through the mixer with the
// option on / off, (c) a re-open re-applies it, (d) destroying the character removes it, (e) the rest of the stage range
// stays out
static void test_whoosh(Session &s)
{
    std::printf("the aura's whoosh (0.9.4a N3): 1035 / 1036 from the Perfect Chaos stage's sound bank (libsa1 stage rules)\n");
    if (!flat_floor(s)) return;
    std::string err;
    const float at[3] = {-6000.0f, 0.0f, 8.0f};
    s.set_super_whoosh(true);
    s.set_stage_tones(true);
    // (a) kind 8, the General entry and a transformation-capable Sonic hold slot 0 = {19, 1035, 1036}; plain Sonic and
    //     Tails none
    int32_t id8 = mk(s, SA1_CHAR_SUPER_SONIC, at, 50, 0, true, SA1_SUPER_NO_DRAIN, err);
    int32_t idg = mk_gen(s, at, 50, SA1_SUPER_START | SA1_SUPER_NO_DRAIN, err);
    int32_t idt = mk_gen(s, at, 50, SA1_SUPER_NO_DRAIN, err);
    int32_t ids = s.create(SA1_CHAR_SONIC, at, 0.0f, err);
    int32_t idl = s.create(SA1_CHAR_TAILS, at, 0.0f, err);
    CHECK(id8 > 0 && idg > 0 && idt > 0 && ids > 0 && idl > 0 && whoosh_rule_of(s, id8) && whoosh_rule_of(s, idg) &&
              whoosh_rule_of(s, idt) && no_rules(s, ids) && no_rules(s, idl) &&
              s.audio().rule_status(idg, kRuleWhoosh) == kRuleNotApplied,
          "(a) Vs. Perfect Chaos, the General entry and a Sonic who can transform hold the stage rule {19, 1035, 1036} in "
          "slot 0 (recorded: no sound banks yet); plain Sonic and Tails have none");
    // (e) the guard: the stage's ambient loop 1033 of a super-capable world stays out, the whoosh passes; another
    //     character's tones are not the guard's
    sa1_event e;
    std::memset(&e, 0, sizeof e);
    e.type = SA1_EVENT_SOUND;
    e.character = (sa1_character_id)idt;
    uint64_t m0 = s.get(idt)->stage_tones_muted;
    e.id = 1033;
    bool a1033 = s.admit_sound(e);
    e.id = kWhooshFirst;
    bool a1035 = s.admit_sound(e);
    e.type = SA1_EVENT_SOUND_STOP;
    e.id = kWhooshLast;
    bool s1036 = s.admit_sound(e);
    e.type = SA1_EVENT_SOUND;
    e.id = 1033;
    e.character = (sa1_character_id)ids;
    bool plain1033 = s.admit_sound(e);
    CHECK(!a1033 && a1035 && s1036 && plain1033 && s.get(idt)->stage_tones_muted == m0 + 1,
          "(e) an injected 1033 from a Sonic who can transform stays out of the mixer (counted); his 1035 and the stop of "
          "1036 pass; plain Sonic's tones are not the guard's");
    s.destroy(ids);
    s.destroy(idl);
    // (d) destroying a character removes its rule
    s.destroy(id8);
    CHECK(no_rules(s, id8) && s.audio().rule_status(id8, kRuleWhoosh) == -1000, "(d) Vs. Perfect Chaos destroyed: his rule "
          "is gone from the registry");
    // (b) with the sound banks: the rule applied, the bank read on the loader thread, the whoosh heard
    bool audio = s.audio_open(false, err);
    int32_t st0 = audio ? wait_stage(s, 10000) : -1;
    CHECK(audio && s.audio().rule_status(idg, kRuleWhoosh) == SA1_OK && s.audio().rule_status(idt, kRuleWhoosh) == SA1_OK &&
              st0 == SA1_AUDIO_STAGE_READY && s.whoosh_characters() == 2,
          "the sound banks open (%s): both rules applied to the mixer; the Perfect Chaos stage's banks %d (READY 2)",
          audio ? "ok" : err.c_str(), (int)st0);
    if (!audio) return;
    run(s, idg, 10, 0.0f);
    const Character *cg = s.get(idg);
    uint64_t muted0 = cg ? cg->stage_tones_muted : 0;
    int ev = 0;
    uint32_t voices = 0;
    double rms = 0.0;
    crossing(s, idg, ev, voices, rms);
    CHECK(cg && cg->super && ev == 1 && cg->stage_tones_muted == muted0 && voices > 0 && rms > 100.0,
          "(b) the General entry, Super, crosses speed 7: SOUND 1035 (%d) goes to the mixer (none kept out), %u voices, rms "
          "%.0f (the slow whoosh from CHAOS7B.MLT)", ev, voices, rms);
    s.set_super_whoosh(false);
    uint64_t muted1 = cg ? cg->stage_tones_muted : 0;
    int ev_off = 0;
    uint32_t voices_off = 0;
    double rms_off = 0.0;
    crossing(s, idg, ev_off, voices_off, rms_off);
    // (the slow-down before it sends the aura's own stop of 1035, kept out too: the count goes up by 2)
    CHECK(!whoosh_rule_of(s, idg) && !whoosh_rule_of(s, idt) && ev_off == 1 && cg && cg->stage_tones_muted == muted1 + 2 &&
              voices_off == 0 && rms_off < 50.0 && s.whoosh_characters() == 0,
          "the whoosh off (gsa1_super_whoosh 0): the rules cleared; the next crossing's 1035 (%d) kept out with the aura's "
          "stop before it (+%llu), no voice added (%u), silence (rms %.0f)", ev_off,
          (unsigned long long)(cg ? cg->stage_tones_muted - muted1 : 0), voices_off, rms_off);
    s.set_super_whoosh(true);
    // (c) a re-open of the banks (the Japanese-voices switch: a new audio object and mixer) applies the rule again
    bool re = s.audio_open(true, err);
    int32_t st1 = re ? wait_stage(s, 10000) : -1;
    int ev_re = 0;
    uint32_t voices_re = 0;
    double rms_re = 0.0;
    if (re) crossing(s, idg, ev_re, voices_re, rms_re);
    CHECK(re && whoosh_rule_of(s, idg) && s.audio().rule_status(idg, kRuleWhoosh) == SA1_OK &&
              st1 == SA1_AUDIO_STAGE_READY && ev_re == 1 && voices_re > 0,
          "(c) the banks re-opened (Japanese voices): the rule applied to the new mixer, the stage's banks READY again, the "
          "whoosh heard (%u voices, rms %.0f)", voices_re, rms_re);
    s.destroy(idg);
    s.destroy(idt);
    CHECK(s.audio().rule_characters() == 0, "every rule gone with its character (%u left)",
          (unsigned)s.audio().rule_characters());
    s.audio_close();
}
#endif  // SA1_AUDIO_HAS_STAGE_RULES

#endif  // SA1_API_SUPER_GENERAL

// ---- 7. the material census (the SUPERSONIC archive) ------------------------------------------------------------------
// t: seconds; sy: stick forward; b: buttons; speed: > 0 sets playerwk.spd.x first (the dash auras); order: 46 / 47
struct Step7 {
    float sy = 0.0f;
    uint32_t b = 0;
    float speed = 0.0f;
    int order = 0;
};
static Step7 census_script(double t, bool transform)
{
    Step7 s;
    if (transform && t >= 1.0 && t < 1.02) s.order = SA1_ORDER_SUPER;
    if (t >= 1.2 && t < 3.0) s.sy = 1.0f;                           // run: the run actions and Aura_Dash_1 (above 7)
    if ((t >= 2.0 && t < 2.04) || (t >= 2.5 && t < 2.54)) s.speed = 14.5f;   // Aura_Dash_2 (above 13)
    if (t >= 3.0 && t < 3.3) s.b = J;                               // a jump (the Super jump ball)
    if (t >= 3.45 && t < 3.6) s.b = J;                              // jump again in the air: the homing attack
    if (t >= 4.2 && t < 5.2) s.sy = 1.0f;
    if (t >= 5.2 && t < 5.4) s.b = J;
    if (t >= 5.6 && t < 5.7) s.b = B;                               // the action button in the air: the air stop
    if (t >= 6.4 && t < 6.6) s.b = J;                               // a standing jump and a homing attack
    if (t >= 6.75 && t < 6.9) s.b = J;
    if (transform && t >= 8.0 && t < 8.02) s.order = SA1_ORDER_NORMAL;
    // normal Sonic (kind 8 after the drain, from about 8.5 s): run, jump, spin dash, roll
    if (t >= 9.0 && t < 10.5) s.sy = 1.0f;
    if (t >= 10.5 && t < 10.8) s.b = J;
    if (t >= 10.9 && t < 11.1) s.b = J;
    if (t >= 12.0 && t < 12.8) s.b = B;                             // a spin dash charged standing
    if (t >= 13.2 && t < 14.0) {
        s.sy = 1.0f;
        if (t >= 13.6) s.b = B;                                     // roll
    }
    return s;
}

// 0.9.3a: the General form's census (the list entry and a Sonic who transforms): the transformation in a jump, Sonic's
// moves while Super - running into both dash auras, the Super ball and homing, his own air action, a spin dash and its
// roll with the golden after-images (SA1_SUPOPT_SUPER_EFFECTS, G-SA1's default), the Light Speed charge with the shoes
// and the Crystal Ring - then the revert
static Step7 general_script(double t)
{
    Step7 s;
    if (t >= 0.5 && t < 0.8) s.b = J;                               // a jump ...
    if (t >= 0.65 && t < 0.67) s.order = SA1_ORDER_SUPER;           // ... and the transformation in it (the gesture's order)
    if (t >= 1.2 && t < 3.0) s.sy = 1.0f;                           // run: Aura_Dash_1 above 7 ...
    if ((t >= 2.0 && t < 2.04) || (t >= 2.5 && t < 2.54)) s.speed = 14.5f;   // ... and Aura_Dash_2 above 13
    if (t >= 3.0 && t < 3.3) s.b = J;                               // a jump (the Super ball)
    if (t >= 3.45 && t < 3.6) s.b = J;                              // the air dash (the game's Super homing)
    if (t >= 4.2 && t < 5.2) s.sy = 1.0f;
    if (t >= 5.2 && t < 5.4) s.b = J;
    if (t >= 5.6 && t < 5.7) s.b = B;                               // Sonic's own air action
    if (t >= 6.4 && t < 6.6) s.b = J;
    if (t >= 6.75 && t < 6.9) s.b = J;
    if (t >= 7.5 && t < 8.3) s.b = B;                               // a spin dash charged standing, released: the roll
    if (t >= 9.5 && t < 12.0) s.b = B;                              // the Light Speed charge (2 s with the ring), released
    if (t >= 12.5 && t < 13.5) {
        s.sy = 1.0f;
        if (t >= 13.0) s.b = B;                                     // run and roll
    }
    if (t >= 14.0 && t < 14.02) s.order = SA1_ORDER_NORMAL;
    if (t >= 14.2 && t < 15.5) s.sy = 1.0f;
    return s;
}

// 0.9.4a: the golden Light Speed charge with the shoes alone (the plain lcharge01 / 02 in gold; with the Crystal Ring they
// are lcharge03 / 04, which stay green: owner answer O3): Super from the start, the charge held 4 s, released, a run
static Step7 lsd_script(double t)
{
    Step7 s;
    if (t >= 0.5 && t < 4.5) s.b = B;
    if (t >= 4.8 && t < 6.0) s.sy = 1.0f;
    return s;
}

static void test_census(Session &s, const std::string &out_path, bool lua)
{
    std::printf("material census of Super Sonic (the pre-warm's reference for the SUPERSONIC archive):\n");
    std::vector<sa1_collision_tri> floor;
    floor_tiles(floor, -16384.0f, 16384.0f, -2048.0f, 2048.0f, 0.0f, 1024.0f);
    std::string err;
    if (!s.set_world(floor, err)) {
        CHECK(false, "set_world: %s", err.c_str());
        return;
    }
    std::map<std::string, int> states;        // "kind archive texture flags src dst wrap pass prims alpha"
    std::map<int32_t, std::string> archives;
    int32_t a5 = archive_named(s, SA1_CHAR_SONIC, "SUPERSONIC");
    uint32_t n8 = 0, n0 = 0, aura8 = 0, body8 = 0, body8_son = 0, aura0 = 0, body0 = 0;
    bool reverted8 = false, super0 = false, ok = true;
    int32_t a8_son = archive_named(s, SA1_CHAR_SUPER_SONIC, "SONIC");
    // 0.9.4a: k 2 = the General form with the shoes alone (the golden Light Speed charge's rows: SON_EFF with WRAP_GOLD,
    // review R.2), k 3 = k 1 without the Super poses (not written: its body states must equal k 1's, plan 6.4 task 7)
    int32_t a_eff = archive_named(s, SA1_CHAR_SONIC, "SON_EFF");
    std::map<std::string, int> body_poses[2];   // SUPERSONIC body states of k 1 (the poses on) and k 3 (off)
    uint32_t gold_rows = 0, gold_lsd2 = 0;
#if defined(SA1_API_SUPER_POLISH)
    const int kRuns = 4;
#else
    const int kRuns = 2;
#endif
    for (int k = 0; k < kRuns; k++) {
        int32_t kind = k == 0 ? SA1_CHAR_SUPER_SONIC : SA1_CHAR_SONIC;
        const float pos[3] = {-15000.0f, 0.0f, 40.0f};
        // kind 8: 8 rings and the drain, so he turns back at about 8 s; kind 0 (0.9.3a): the General form (G-SA1's
        // transformed Sonic and its list entry) with the shoes and the ring, the transformation by order in a jump.
        // Both with G-SA1's default options (the calm aura, the golden effects, Super run).
#if defined(SA1_API_SUPER_GENERAL)
        std::vector<const UpgradeDef *> ups = sonic_upgrades(SA1_CHAR_SONIC, k == 2 ? 1 : 2);
        int32_t id = k == 0 ? mk(s, kind, pos, 8, 0, true, 0u, err)
                            : mk_gen(s, pos, 50, SA1_SUPER_NO_DRAIN | (k == 2 ? SA1_SUPER_START : 0u), err, &ups);
#else
        int32_t id = k == 0 ? mk(s, kind, pos, 8, 0, true, 0u, err)
                            : mk(s, kind, pos, 50, SA1_CREATE_SUPER_CAPABLE, true, SA1_SUPER_NO_DRAIN, err);
#endif
        const Character *c = id > 0 ? s.get(id) : nullptr;
        if (!c) {
            CHECK(false, "census: create %d: %s", (int)kind, err.c_str());
            ok = false;
            continue;
        }
#if defined(SA1_API_SUPER_GENERAL)
        sa1_character_set_game_option(s.ctx(), id, SA1_GOPT_SUPER_AURA_ANIM, SA1_AURA_ANIM_CALM);
        sa1_character_set_game_option(s.ctx(), id, SA1_GOPT_SUPER_IDLE_BY_FORM, 1);
        sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_VOICE, 1116);
        if (k >= 1) {
            sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SPEED, SA1_SUPER_SPEED_RUN);
#if defined(SA1_API_SUPER_POLISH)
            // 0.9.4a: G-SA1's defaults - the golden clones and spin dash sparks (3), the Super poses, the golden charge
            sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_EFFECTS,
                                           SA1_SUPER_EFFECTS_CLONES | SA1_SUPER_EFFECTS_DUST);
            sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_ANIMS, k == 3 ? 0 : 1);
            sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_LSD_GOLD, 1);
#else
            sa1_character_set_super_option(s.ctx(), id, SA1_SUPOPT_SUPER_EFFECTS, 1);
#endif
        }
#endif
        archives[kind] = archive_list(s, kind);
        for (int f = 0; f < (k == 2 ? 60 * 6 : 60 * 16); f++) {
#if defined(SA1_API_SUPER_GENERAL)
            Step7 st = k == 2 ? lsd_script(f / 60.0) : k >= 1 ? general_script(f / 60.0) : census_script(f / 60.0, false);
#else
            Step7 st = census_script(f / 60.0, k == 1);
#endif
            if (st.order) s.order(id, st.order);
            if (st.speed > 0.0f) set_speed(s, id, st.speed);
            if (s.tick(id, 0.0f, st.sy, 0.0f, st.b, 1.0f / 60.0f) != SA1_OK || s.render(id, -1.0f) != SA1_OK) {
                CHECK(false, "census: tick / render of %d at frame %d: %s", (int)kind, f, s.last_error().c_str());
                ok = false;
                break;
            }
            s.poll_events(g_ev);
            if (k == 0 && c->super_changes >= 2) reverted8 = true;
            if (k == 1 && c->super) super0 = true;
            for (uint32_t bi = 0; bi < c->batch_count; bi++) {
                const RenderBatch &rb = c->batches[bi];
                // a transformed Sonic: only his SUPERSONIC states (core_test has Sonic's own) and (0.9.4a, review R.2)
                // the golden Light Speed charge's (WRAP_GOLD: SON_EFF), whatever their archive
                if (k >= 1 && rb.archive != a5 && !(rb.wrap & WRAP_GOLD)) {
                    continue;
                }
                if (k == 1 || k == 3) {
                    if (rb.archive == a5 && !(rb.flags & (SA1_DRAW_EFFECT | SA1_DRAW_SHADOW))) {
                        body_poses[k == 3].emplace(format("%d %d %X %u %u %u %u", rb.archive, rb.texture, rb.flags,
                                                          (unsigned)rb.blend_src, (unsigned)rb.blend_dst, rb.wrap, rb.pass),
                                                   1);
                    }
                    if (k == 3) continue;   // the comparison only
                }
                std::string key = format("%d %d %d %X %u %u %u %u %X %u", (int)kind, rb.archive, rb.texture, rb.flags,
                                         (unsigned)rb.blend_src, (unsigned)rb.blend_dst, rb.wrap, rb.pass, rb.prims,
                                         (unsigned)rb.alpha);
                if (states.emplace(key, 1).second) {
                    if (g_verbose) {
                        std::printf("        census %s: frame %d, mode %d, action %d, %s\n", key.c_str(), f, (int)c->st.mode,
                                    (int)c->st.action, c->super ? "Super" : "normal");
                    }
                    bool add = (rb.flags & SA1_DRAW_ADDITIVE) && (rb.flags & SA1_DRAW_EFFECT);
                    bool body = !(rb.flags & (SA1_DRAW_EFFECT | SA1_DRAW_SHADOW));
                    if (k == 0) {
                        n8++;
                        aura8 += rb.archive == 0 && add;
                        body8 += rb.archive == 0 && body;
                        body8_son += rb.archive == a8_son && body;
                    } else {
                        n0++;
                        aura0 += add;
                        body0 += body;
                        if (rb.wrap & WRAP_GOLD) {
                            gold_rows++;
                            gold_lsd2 += k == 2;
                        }
                    }
                }
            }
        }
        s.destroy(id);
    }
    std::FILE *f = std::fopen(out_path.c_str(), "wb");
    if (f) {
        std::fprintf(f, "# G-SA1 material census of Super Sonic (feat_super_test): kind archive texture flags(hex) src dst "
                        "wrap pass prims(hex) alpha\n");
        for (const auto &a : archives) {
            std::fprintf(f, "# archives %d: %s\n", (int)a.first, a.second.c_str());
        }
        for (const auto &kv : states) {
            std::fprintf(f, "%s\n", kv.first.c_str());
        }
        std::fclose(f);
    }
    CHECK(ok && f && reverted8 && super0 && n8 > 20 && aura8 >= 3 && body8 > 5 && body8_son > 5 && n0 > 10 && aura0 >= 3 &&
              body0 > 5,
          "%u render states of Super Sonic (%u additive aura / effect states and %u body states from SUPERSONIC, %u body "
          "states from SONIC after the drain's revert), %u SUPERSONIC states of a transformed Sonic (archive %d: %u aura / "
          "effect, %u body); written to %s", n8, aura8, body8, body8_son, n0, a5, aura0, body0, out_path.c_str());
#if defined(SA1_API_SUPER_POLISH)
    {
        // 0.9.4a (plan 6.4 task 7, review R.2): the golden charge's rows are in the census - SON_EFF lcharge01 / 02 with
        // WRAP_GOLD, never the Crystal Ring's lcharge03 / 04 (owner answer O3) - and the poses add no material state
        int32_t lc[4];
        uint32_t g[4] = {0, 0, 0, 0}, other = 0;
        for (int i = 0; i < 4; i++) {
            char nm[16];
            std::snprintf(nm, sizeof nm, "lcharge0%d", i + 1);
            lc[i] = tex_named(s, SA1_CHAR_SONIC, a_eff, nm);
        }
        for (const auto &kv : states) {
            int kk = 0, a = 0, t = 0;
            unsigned fl = 0, src = 0, dst = 0, w = 0;
            if (std::sscanf(kv.first.c_str(), "%d %d %d %X %u %u %u", &kk, &a, &t, &fl, &src, &dst, &w) < 7 || kk != 0 ||
                !(w & WRAP_GOLD)) {
                continue;
            }
            bool hit = false;
            for (int i = 0; i < 4; i++) {
                if (a == a_eff && t == lc[i]) {
                    g[i]++;
                    hit = true;
                }
            }
            other += !hit;
        }
        CHECK(gold_rows > 0 && gold_lsd2 > 0 && g[0] > 0 && g[1] > 0 && g[2] == 0 && g[3] == 0 && other == 0,
              "the golden Light Speed charge in the census (kind 0, WRAP_GOLD): lcharge01 %u, lcharge02 %u, lcharge03 %u, "
              "lcharge04 %u rows (the Crystal Ring's stay green), %u others; %u from the shoes-alone run", g[0], g[1], g[2],
              g[3], other, gold_lsd2);
        CHECK(!body_poses[0].empty() && body_poses[0] == body_poses[1],
              "the Super poses on and off draw the same %u SUPERSONIC body states (%u without them): no new material state",
              (unsigned)body_poses[0].size(), (unsigned)body_poses[1].size());
    }
#endif
    if (lua) {
        // the data of feat/cl_super.lua (S.CENSUS): { archive, texture, flags, src, dst, wrap, pass [, alpha] }
        for (int kind : {8, 0}) {
            std::printf("    [%d] = {\n", kind);
            std::string line = "       ";
            for (const auto &kv : states) {
                int kk = 0, a = 0, t = 0;
                unsigned fl = 0, src = 0, dst = 0, w = 0, p = 0, pr = 0, al = 255;
                if (std::sscanf(kv.first.c_str(), "%d %d %d %X %u %u %u %u %X %u", &kk, &a, &t, &fl, &src, &dst, &w, &p, &pr,
                                &al) < 9 || kk != kind) {
                    continue;
                }
                std::string e = al < 255 ? format(" { %d, %d, 0x%X, %u, %u, %u, %u, %u },", a, t, fl, src, dst, w, p, al)
                                         : format(" { %d, %d, 0x%X, %u, %u, %u, %u },", a, t, fl, src, dst, w, p);
                if (line.size() + e.size() > 120) {
                    std::printf("%s\n", line.c_str());
                    line = "       ";
                }
                line += e;
            }
            if (line.size() > 7) std::printf("%s\n", line.c_str());
            std::printf("    },\n");
        }
    }
}

#endif  // SA1_API_SUPER

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    bool lua = false;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--gdi" && i + 1 < argc) {
            gdi = argv[++i];
        } else if (a == "--verbose") {
            g_verbose = true;
        } else if (a == "--census-lua") {
            lua = true;
        } else {
            std::printf("usage: feat_super_test [--gdi GAME.gdi] [--verbose] [--census-lua]\n");
            return 2;
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_super_test (libsa1 %s)\n", sa1_version_string());
#if !defined(SA1_API_SUPER)
    CHECK(false, "libsa1.h has no Super Sonic section (API 0.4, SA1_API_SUPER)");
#else
    CHECK(kSuperApi && ((playable_kinds() >> SA1_CHAR_SUPER_SONIC) & 1u) && ((playable_kinds() >> SA1_CHAR_SONIC) & 1u) &&
              kCreateExtraFlags == (SA1_CREATE_SUPER_CAPABLE | SA1_CREATE_WATER_FLOOR) &&
              kSuperHostFlags == (SA1_SUPER_NO_DRAIN | SA1_SUPER_KEEP_AT_ZERO | SA1_SUPER_FAITHFUL_REVERT | kSuperGeneralFlags) &&
              !(kSuperHostFlags & SA1_SUPER_SEA_PLANE) && kKindSuperSonic == 8 && kStageTonesFirst <= 1035 &&
              kStageTonesLast >= 1036,
          "the playable kinds hold Super Sonic (0x%X); extra create flags 0x%X, Super flags 0x%X (no sea plane); the stage "
          "tone range %u-%u", (unsigned)playable_kinds(), (unsigned)kCreateExtraFlags, (unsigned)kSuperHostFlags,
          (unsigned)kStageTonesFirst, (unsigned)kStageTonesLast);
#if defined(SA1_API_SUPER_GENERAL)
    CHECK(kSuperGeneralApi && kSuperGeneralFlags == (SA1_SUPER_GENERAL | SA1_SUPER_START | SA1_SUPER_WATER_WHILE_SUPER |
                                                     SA1_SUPER_START_NORMAL) && !(kSuperHostFlags & SA1_SUPER_SEA_PLANE),
          "0.9.3a: the General form's Super flags pass (GENERAL 0x10, START 0x20, WATER_WHILE_SUPER 0x40, START_NORMAL 0x80)");
#else
    CHECK(false, "libsa1.h has no General form (round 0.9.3a, SA1_API_SUPER_GENERAL)");
#endif
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the world checks need the disc\n");
    } else {
        Session s;
        std::string err;
        bool ok = s.init(gdi, err);
        std::vector<sa1_collision_tri> floor;
        floor_tiles(floor, -8192.0f, 8192.0f, -2048.0f, 2048.0f, 0.0f, 1024.0f);
        ok = ok && s.set_world(floor, err);
        CHECK(ok, "the disc and a flat floor (%s)", err.c_str());
        if (ok) {
            test_kind8(s);
            test_options(s);
            test_transform(s);
            test_hit(s);
            test_sound(s);
            test_hud(s);
            test_water(s);
#if defined(SA1_API_SUPER_GENERAL)
            test_general(s);
            test_vspc(s);
            test_aura_rate(s);
#if defined(SA1_API_SUPER_POLISH)
            test_poses(s);
            test_gold(s);
#else
            CHECK(false, "libsa1.h has no Super Sonic polish (round 0.9.4a, SA1_API_SUPER_POLISH)");
#endif
#if defined(SA1_AUDIO_HAS_STAGE_RULES)
            test_whoosh(s);
#endif
#endif
            std::string census = join_path(parent_dir(argv[0]).empty() ? std::string(".") : parent_dir(argv[0]),
                                           "material_census_super.txt");
            test_census(s, census, lua);
        }
        for (const std::string &l : s.take_log()) {
            if (g_verbose || l.find("error") != std::string::npos) {
                std::printf("        %s\n", l.c_str());
            }
        }
        s.shutdown();
    }
#endif
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
