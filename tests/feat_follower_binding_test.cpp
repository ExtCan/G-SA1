// feat_follower_binding_test: the follower feature through the module's Lua functions (round 0.9.8: sadc
// docs/research/gsa1_098_plan.md 2.4, 3.1, 5.5, 6.6; gsa1_096_plan.md 5.5, 6.4 task 6 with its Review R.5; follow096_gsa1.md 9.3) -
// the feature "follower" (src/module/bind_follower.cpp), the session's follower parts. Linked like binding_test (the module's objects,
// libsa1, the mock Lua stack of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi; the play checks use gm_construct from the
// Garry's Mod install (read only) for gsa1.WorldLoadData and then a floor of their own (Session::set_world).
//
//   feat_follower_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
// Two parts:
//   * THE API PART runs whenever libsa1.h has SA1_API_FOLLOWER: gsa1.FEATURES.follower == 1 (2 with SA1_API_FOLLOWER 2), every 5.5 function registered with its
//     arguments checked ("bad_argument" before anything else), the codes (no disc: "not_ready"), gsa1.FOLLOWER's constants - and
//     writes them to build/<target>/follower_api.txt next to this test (098-gsa1-followlua checks its mock module against it).
//   * THE BEHAVIOUR PART prints exactly one line "SKIP behaviour: follower is not built yet" and passes while libsa1 answers that
//     (sa1_follower_kinds() is 0: the contract snapshot); otherwise it runs in full (096 6.4 task 6). The final gates fail when the
//     SKIP line appears.
//   * ROUND 0.9.9 (sadc docs/research/gsa1_099_plan.md 5.3 item 4, 5.5; follow099.md 9), SA1_API_FOLLOWER 2: gsa1.FollowerSpeed, gsa1.FollowerSpot,
//     gsa1.FOLLOWER.SPEED_MAX, FollowerInfo's speed_factor. Their arguments in the API part; their behaviour and the emotes on a follower id in
//     behaviour099, which prints exactly one line "SKIP behaviour: follower speed is not built yet" while libsa1 answers that (the contract snapshots).
//
// API NOTES (098-gsa1-followmod's report, also in r098/lanes/followmod_contract.txt): the Lua API is the header of
// src/module/bind_follower.cpp. follower_api.txt's records, one per line, tab-separated:
//   feature <name> <version>
//   function <Name> <arguments> <returns> <codes, comma separated>
//   option FollowerCreate <field> <lua type> <values>
//   const FOLLOWER.<NAME> <number | true | false>  |  const FOLLOWER.MODE.<NAME> <number>
//   field FollowerInfo <field> <lua type>    field FollowersTick <field> <lua type>    field FollowersTick[i] <field> <lua type>
//   field FollowersStats <field> <lua type>  field FollowerKinds [kind] <the kinds, comma separated>
//   reason <code> <text>
//   behaviour <SKIP | RAN> <what>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#endif

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

#include "mock_lua.hpp"
#include "../src/core/config.hpp"
#include "../src/core/follower.hpp"
#include "../src/core/pool.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

#ifndef INFO
#define INFO(...)                                            \
    do {                                                     \
        std::printf("  info  ");                             \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)
#endif

namespace {

class CountingLua : public MockLua {
public:
    uint64_t tables = 0;
    void CreateTable() override
    {
        tables++;
        MockLua::CreateTable();
    }
};

#if defined(SA1_API_FOLLOWER)
bool field_bool(const Val &t, const char *k)
{
    Val v = t.type == Type::Table ? t.tab->field(k) : Val();
    return v.type == Type::Bool && v.b;
}

double field_num(const Val &t, const char *k)
{
    Val v = t.type == Type::Table ? t.tab->field(k) : Val();
    return v.type == Type::Number ? v.num : -1e9;
}

bool is_true(const std::vector<Val> &r)
{
    return r.size() >= 1 && r[0].type == Type::Bool && r[0].b;
}

std::string fmt_num(double v)
{
    if (v == std::floor(v) && std::fabs(v) < 1e15) {
        return gsa1::format("%.0f", v);
    }
    return gsa1::format("%.9g", v);
}

const char *type_word(int t)
{
    switch (t) {
    case Type::Nil: return "nil";
    case Type::Bool: return "boolean";
    case Type::Number: return "number";
    case Type::String: return "string";
    case Type::Table: return "table";
    default: return "other";
    }
}

void quad(std::vector<sa1_collision_tri> &out, const float a[3], const float b[3], const float c[3], const float d[3])
{
    sa1_collision_tri t1, t2;
    std::memset(&t1, 0, sizeof t1);
    std::memset(&t2, 0, sizeof t2);
    std::memcpy(t1.v[0], a, 12);
    std::memcpy(t1.v[1], b, 12);
    std::memcpy(t1.v[2], c, 12);
    std::memcpy(t2.v[0], a, 12);
    std::memcpy(t2.v[1], c, 12);
    std::memcpy(t2.v[2], d, 12);
    t1.surface = t2.surface = SA1_SURFACE_SOLID;
    out.push_back(t1);
    out.push_back(t2);
}

// the fixture: a flat SOLID floor at z 0 (host space), half extent 16384, tiles of 256; a block x 6000..7024, y -512..512, 200 HU
// high, with its walls ("Sonic on a 200 HU ledge")
const float kLedgeX0 = 6000.0f, kLedgeX1 = 7024.0f, kLedgeY = 512.0f, kLedgeZ = 200.0f;
std::vector<sa1_collision_tri> fixture()
{
    std::vector<sa1_collision_tri> out;
    const float half = 16384.0f, tile = 256.0f;
    for (float x = -half; x < half - 0.5f; x += tile) {
        for (float y = -half; y < half - 0.5f; y += tile) {
            if (x + tile > kLedgeX0 && x < kLedgeX1 && y + tile > -kLedgeY && y < kLedgeY) {
                continue;
            }
            const float a[3] = {x, y, 0}, b[3] = {x + tile, y, 0}, c[3] = {x + tile, y + tile, 0}, d[3] = {x, y + tile, 0};
            quad(out, a, b, c, d);
        }
    }
    // the hole's own tiles: the block's top in tiles of 128, and the rest of the hole's tile row at the floor
    const float x0 = std::floor(kLedgeX0 / tile) * tile, x1 = std::ceil(kLedgeX1 / tile) * tile;
    const float y0 = std::floor(-kLedgeY / tile) * tile, y1 = std::ceil(kLedgeY / tile) * tile;
    for (float x = x0; x < x1 - 0.5f; x += 128.0f) {
        for (float y = y0; y < y1 - 0.5f; y += 128.0f) {
            bool top = x >= kLedgeX0 && x + 128.0f <= kLedgeX1 && y >= -kLedgeY && y + 128.0f <= kLedgeY;
            float z = top ? kLedgeZ : 0.0f;
            const float a[3] = {x, y, z}, b[3] = {x + 128.0f, y, z}, c[3] = {x + 128.0f, y + 128.0f, z}, d[3] = {x, y + 128.0f, z};
            quad(out, a, b, c, d);
        }
    }
    auto wall = [&](float ax, float ay, float bx, float by) {
        const float a[3] = {ax, ay, 0}, b[3] = {bx, by, 0}, c[3] = {bx, by, kLedgeZ}, d[3] = {ax, ay, kLedgeZ};
        quad(out, a, b, c, d);
    };
    for (float x = kLedgeX0; x < kLedgeX1 - 0.5f; x += 128.0f) {
        wall(x, -kLedgeY, x + 128.0f, -kLedgeY);
        wall(x + 128.0f, kLedgeY, x, kLedgeY);
    }
    for (float y = -kLedgeY; y < kLedgeY - 0.5f; y += 128.0f) {
        wall(kLedgeX0, y + 128.0f, kLedgeX0, y);
        wall(kLedgeX1, y, kLedgeX1, y + 128.0f);
    }
    return out;
}

double median_of(std::vector<double> v)
{
    if (v.empty()) {
        return 0.0;
    }
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}

double private_mb()
{
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS_EX pm;
    std::memset(&pm, 0, sizeof pm);
    pm.cb = sizeof pm;
    if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS *>(&pm), sizeof pm)) {
        return (double)pm.PrivateUsage / 1048576.0;
    }
#endif
    return 0.0;
}

// the leader's script of the research (follow096_lib.md 3.5, the probe's script_run): running, turning, stops and jumps
void script_run(int p, double &sx, double &sy, uint32_t &buttons)
{
    sx = sy = 0.0;
    buttons = 0u;
    p %= 600;
    if (p >= 30 && p < 150) {
        sy = 1.0;
    } else if (p >= 150 && p < 210) {
        sy = 1.0;
        sx = 0.6;
    } else if (p == 300) {
        buttons = SA1_BUTTON_JUMP;
    } else if (p >= 360 && p < 450) {
        sy = 1.0;
        if (p == 380 || p == 381 || p == 420 || p == 421) {
            buttons = SA1_BUTTON_JUMP;
        }
    }
}

struct Rig {
    MockLua *L = nullptr;
    gsa1::Session *se = nullptr;
    Val out = Val::table();
    void pair(double id, double sx = 0.0, double sy = 0.0, uint32_t buttons = 0)
    {
        L->call("Tick", {Val::number(id), Val::number(sx), Val::number(sy), Val::number(0), Val::number(buttons),
                         Val::number(1.0 / 30.0)});
    }
    // gsa1.FollowersTick for one pair (or a frame of dt); the camera when given
    std::vector<Val> ftick(double dt = 1.0 / 30.0, const float *eye = nullptr, const float *target = nullptr)
    {
        Val cam1, cam2;
        if (eye) {
            cam1 = Val::vector(eye[0], eye[1], eye[2]);
            cam2 = Val::vector(target[0], target[1], target[2]);
        }
        return L->call("FollowersTick", {Val::number(dt), Val::number(0), cam1, cam2, out});
    }
    double create_char(int kind, float x, float y, float z = 40.0f, double yaw = 0.0)
    {
        std::vector<Val> r = L->call("Create", {Val::number(kind), Val::vector(x, y, z), Val::number(yaw)});
        return r.size() == 1 && r[0].type == Type::Number ? r[0].num : -1.0;
    }
    // nil leader: host-fed. Returns the id, -1 on a failure (msg set)
    std::string msg;
    double follower(int kind, float x, float y, double leader, const Val &opts = Val(), float z = 40.0f)
    {
        Val lead = leader > 0 ? Val::number(leader) : Val();
        std::vector<Val> r = L->call("FollowerCreate", {Val::number(kind), Val::vector(x, y, z), Val::number(0), lead, opts});
        if (r.size() == 1 && r[0].type == Type::Number) {
            return r[0].num;
        }
        msg = str_of(r, 1) + " (" + str_of(r, 2) + ")";
        return -1.0;
    }
    gsa1::Character *ch(double id) { return se ? se->get((int32_t)id) : nullptr; }
    double info_num(double id, const char *k)
    {
        Val o = Val::table();
        L->call("FollowerInfo", {Val::number(id), o});
        Val v = o.tab->field(k);
        return v.type == Type::Number ? v.num : -1e9;
    }
    bool info_bool(double id, const char *k)
    {
        Val o = Val::table();
        L->call("FollowerInfo", {Val::number(id), o});
        Val v = o.tab->field(k);
        return v.type == Type::Bool && v.b;
    }
    double dist(double a, double b)
    {
        gsa1::Character *ca = ch(a), *cb = ch(b);
        if (!ca || !cb) {
            return 1e9;
        }
        double dx = ca->st.position[0] - cb->st.position[0], dy = ca->st.position[1] - cb->st.position[1],
               dz = ca->st.position[2] - cb->st.position[2];
        return std::sqrt(dx * dx + dy * dy + dz * dz);
    }
    void clear()
    {
        for (int32_t id : se->ids()) {
            L->call("Destroy", {Val::number(id)});
        }
        L->call("PollEvents", {Val::table()});
    }
};

// what the session's event pump does with every event (tests: Session::set_event_tap)
struct Tap {
    gsa1::Session *se = nullptr;
    std::vector<sa1_event> ev;
    std::vector<bool> mixed;
    std::vector<float> from_char;   // how far the event's position is from its character's state, at the event
    static void cb(void *user, const sa1_event &e, bool mix)
    {
        Tap *t = static_cast<Tap *>(user);
        t->ev.push_back(e);
        t->mixed.push_back(mix);
        gsa1::Character *c = t->se ? t->se->get((int32_t)e.character) : nullptr;
        float d = -1.0f;
        if (c) {
            float dx = e.position[0] - c->st.position[0], dy = e.position[1] - c->st.position[1], dz = e.position[2] - c->st.position[2];
            d = std::sqrt(dx * dx + dy * dy + dz * dz);
        }
        t->from_char.push_back(d);
    }
};

#if SA1_API_FOLLOWER >= 2
// ---- round 0.9.9: the catch-up, the spots, the emotes on a follower id, through the module's functions (the deep cases: libsa1's tests/follower_test.c) --------
void behaviour099(MockLua &L, Rig &R)
{
    auto is_code = [&](const std::vector<Val> &r, const char *code) { return is_nil_msg(r) && str_of(r, 2) == code; };
    double sonic = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
    double tails = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, sonic);
    CHECK(sonic > 0 && tails > 0, "0.9.9: Sonic and a Tails follower made (%s)", R.msg.c_str());
    // what is checked before the gate
    {
        int bad = 0;
        bad += !is_code(L.call("FollowerSpeed", {Val::number(sonic), Val::number(2)}), "bad_argument");
        bad += !is_code(L.call("FollowerSpeed", {Val::number(99999), Val::number(2)}), "not_found");
        bad += !is_code(L.call("FollowerSpeed", {Val::number(tails), Val::number(0.5)}), "bad_argument");
        bad += !is_code(L.call("FollowerSpeed", {Val::number(tails), Val::number(8.5)}), "bad_argument");
        bad += !is_code(L.call("FollowerSpot", {Val::number(sonic), Val::number(1), Val::number(1)}), "bad_argument");
        bad += !is_code(L.call("FollowerSpot", {Val::number(99999), Val::number(1), Val::number(1)}), "not_found");
        CHECK(bad == 0, "FollowerSpeed, FollowerSpot: a character that is not a follower and a speed out of range -> bad_argument, no such id -> not_found (%d wrong)", bad);
    }
    std::vector<Val> sp = L.call("FollowerSpeed", {Val::number(tails), Val::number(1)});
    std::vector<Val> em = L.call("Emote", {Val::number(tails), Val::string("a54")});
    bool speed_gated = is_nil_msg(sp) && str_of(sp, 1).find("not built yet") != std::string::npos;
    bool emote_gated = is_nil_msg(em) && str_of(em, 1).find("followers do not take emotes") != std::string::npos;
    if (speed_gated || emote_gated) {
        std::printf("SKIP behaviour: follower speed is not built yet\n");
        CHECK(!speed_gated || str_of(sp, 2) == "unsupported", "the contract's answer: %s (%s)", str_of(sp, 1).c_str(), str_of(sp, 2).c_str());
        R.clear();
        return;
    }
    CHECK(is_true(sp), "FollowerSpeed(id, 1) -> true");
    if (is_true(em)) {
        L.call("EmoteStop", {Val::number(tails), Val::number(SA1_EMOTE_STOP_NOW)});
    }
    R.clear();

    // the stand (0.9.9a, N7, sadc build/research/r099a/stop/diagnosis.md): after a stop, on: the game's own stand with its frames moving; off: the game's own walk at speed 0 on one frame
    {
        double s = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        double on = R.follower(SA1_CHAR_SONIC, 0.0f, 0.0f, s), off = R.follower(SA1_CHAR_SONIC, 0.0f, 0.0f, s);
        int bad = 0;
        bad += !is_code(L.call("FollowerStand", {Val::number(s), Val::boolean(true)}), "bad_argument");
        bad += !is_code(L.call("FollowerStand", {Val::number(99999), Val::boolean(true)}), "not_found");
        bad += !is_code(L.call("FollowerStand", {Val::number(on), Val::number(1)}), "bad_argument");
        CHECK(bad == 0, "FollowerStand: not a follower or not a boolean -> bad_argument, no such id -> not_found (%d wrong)", bad);
        CHECK(is_true(L.call("FollowerStand", {Val::number(on), Val::boolean(true)})), "FollowerStand(id, true) -> true");
        for (int t = 0; t < 120; t++) {
            R.pair(s, 0.0, 1.0);
            R.ftick();
        }
        double frame0 = 0.0;
        for (int t = 0; t < 300; t++) {
            R.pair(s);
            R.ftick();
            if (t == 280 && R.ch(on)) {
                frame0 = R.ch(on)->st.frame;
            }
        }
        gsa1::Character *a = R.ch(on), *b = R.ch(off);
        CHECK(a && a->st.action == 0 && a->st.frame != frame0, "on: 300 pairs after the stop action %d, the frame moves (%.2f, %.2f)", a ? (int)a->st.action : -1, frame0, a ? (double)a->st.frame : 0.0);
        double fb = b ? b->st.frame : 0.0;
        for (int t = 0; t < 20; t++) {
            R.pair(s);
            R.ftick();
        }
        CHECK(b && b->st.action != 0 && b->st.frame == fb, "off: the game's own: action %d, the frame stands still (%.2f, %.2f)", b ? (int)b->st.action : -1, fb, b ? (double)b->st.frame : 0.0);
        R.clear();
    }

    // the catch-up: a Tails at 3 stays with a running Sonic, its factor above 1 while it is behind, 1 near its spot
    {
        double s = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        double t3 = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, s);
        std::vector<Val> ok = L.call("FollowerSpeed", {Val::number(t3), Val::number(3)});
        CHECK(is_true(ok), "FollowerSpeed(id, 3) -> true (%s)", str_of(ok, 1).c_str());
        for (int t = 0; t < 60; t++) {
            R.pair(s);
            R.ftick();
        }
        double f_near = R.info_num(t3, "speed_factor");
        double f_max = 0.0, d_max = 0.0;
        int faulted = 0;
        for (int t = 0; t < 300; t++) {
            R.pair(s, 0.0, 1.0);
            std::vector<Val> r = R.ftick();
            Val row = r.size() == 1 && r[0].type == Type::Table ? r[0].tab->at(1) : Val();
            faulted += !(row.type == Type::Table && field_bool(row, "ok"));
            f_max = std::max(f_max, R.info_num(t3, "speed_factor"));
            d_max = std::max(d_max, R.dist(s, t3));
        }
        double resp = R.info_num(t3, "respawns");
        INFO("Tails at 3 behind a running Sonic, 300 pairs: factor %.2f at most, farthest %.0f HU, %g drop-ins", f_max, d_max, resp);
        CHECK(faulted == 0 && resp == 0.0 && f_max > 1.0 && f_max <= 3.0, "the catch-up: no drop-in in 300 pairs of running (the factor up to %.2f, at most 3)", f_max);
        for (int t = 0; t < 180; t++) {
            R.pair(s);
            R.ftick();
        }
        double f_stop = R.info_num(t3, "speed_factor");
        CHECK(f_near == 1.0 && f_stop == 1.0 && R.dist(s, t3) < 240.0, "near its spot the factor is 1 (standing %.2f, after the stop %.2f, %.0f HU away)", f_near, f_stop, R.dist(s, t3));
        CHECK(is_true(L.call("FollowerSpeed", {Val::number(t3), Val::number(1)})), "FollowerSpeed(id, 1): back to the game's own");
        R.clear();
    }

    // the spots: two followers stand where they are told, on Source's axes
    {
        double s = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        double a = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, s);
        double b = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, s);
        for (int t = 0; t < 120; t++) {
            R.pair(s);
            R.ftick();
        }
        double together = R.dist(a, b);
        CHECK(is_true(L.call("FollowerSpot", {Val::number(a), Val::number(160), Val::number(0)})) &&
                  is_true(L.call("FollowerSpot", {Val::number(b), Val::number(-160), Val::number(0)})), "FollowerSpot(id, x, y) -> true");
        for (int t = 0; t < 240; t++) {
            R.pair(s);
            R.ftick();
        }
        gsa1::Character *ca = R.ch(a), *cb = R.ch(b), *cs = R.ch(s);
        double apart = R.dist(a, b);
        CHECK(ca && cb && cs && ca->st.position[0] > cs->st.position[0] && cb->st.position[0] < cs->st.position[0],
              "the offset's x is Source's x: %.0f and %.0f either side of the leader's %.0f", ca ? ca->st.position[0] : 0.0f, cb ? cb->st.position[0] : 0.0f,
              cs ? cs->st.position[0] : 0.0f);
        CHECK(apart > together + 100.0, "two followers given spots stand apart: %.0f HU (%.0f without)", apart, together);
        CHECK(is_true(L.call("FollowerSpot", {Val::number(a), Val::number(0), Val::number(0)})), "FollowerSpot(id, 0, 0): the game's own place again");
        R.clear();
    }

    // the emote on a follower id
    {
        double s = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        double t = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, s);
        for (int i = 0; i < 240; i++) {
            R.pair(s);
            R.ftick();
        }
        CHECK(is_code(L.call("Emote", {Val::number(t), Val::string("a54"), Val::number(SA1_EMOTE_IN_AIR)}), "bad_argument"), "SA1_EMOTE_IN_AIR on a follower id is refused");
        std::vector<Val> ok = L.call("Emote", {Val::number(t), Val::string("a54"), Val::number(SA1_EMOTE_HOLD)});
        CHECK(is_true(ok), "gsa1.Emote on a follower near its spot -> true (%s)", str_of(ok, 1).c_str());
        gsa1::Character *c = R.ch(t);
        float x0 = c ? c->st.position[0] : 0.0f, y0 = c ? c->st.position[1] : 0.0f;
        double state = 0.0;
        for (int i = 0; i < 90; i++) {
            R.pair(s);
            R.ftick();
            std::vector<Val> es = L.call("EmoteState", {Val::number(t)});
            if (!es.empty() && es[0].type == Type::Number) {
                state = es[0].num;
            }
        }
        double moved = c ? std::hypot(c->st.position[0] - x0, c->st.position[1] - y0) : 1e9;
        CHECK(state != SA1_EMOTE_STATE_NONE && moved < 1.0, "it plays: state %.0f after 90 pairs, moved %.2f HU, its AI's output dropped", state, moved);
        std::vector<Val> st = L.call("EmoteStop", {Val::number(t), Val::number(SA1_EMOTE_STOP_NOW)});
        CHECK(is_true(st), "gsa1.EmoteStop on a follower id -> true (%s)", str_of(st, 1).c_str());
        R.pair(s);
        R.ftick();
        R.pair(s);
        R.ftick();
        std::vector<Val> es = L.call("EmoteState", {Val::number(t)});
        CHECK(!es.empty() && es[0].type == Type::Number && es[0].num == SA1_EMOTE_STATE_NONE, "... it ended");
        R.clear();
    }
}
#endif  // SA1_API_FOLLOWER >= 2

// ---- the behaviour part (096 6.4 task 6) -----------------------------------------------------------------------------------------
void behaviour(MockLua &L, Rig &R)
{
    gsa1::Session *se = R.se;

    // FollowerKinds
    {
        std::vector<Val> k = L.call("FollowerKinds", {});
        uint32_t mask = sa1_follower_kinds();
        std::string wrong;
        for (int kind : {0, 2, 3, 5, 6, 7}) {
            Val v = k.size() == 1 && k[0].type == Type::Table ? k[0].tab->at(kind) : Val();
            bool can = (mask >> kind) & 1u;
            if (can ? !(v.type == Type::Bool && v.b) : !(v.type == Type::String && !v.str.empty())) {
                wrong += " " + std::to_string(kind);
            }
            if (!can) {
                INFO("kind %d cannot follow: %s", kind, v.str.c_str());
            }
        }
        CHECK(wrong.empty() && ((mask >> SA1_CHAR_TAILS) & 1u), "FollowerKinds equals sa1_follower_kinds() 0x%X with libsa1's reasons%s",
              (unsigned)mask, wrong.c_str());
    }

    // a Tails follower of a scripted Sonic: 600 pairs of running and turning
    {
        double sonic = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        double tails = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, sonic);
        CHECK(sonic > 0 && tails > 0, "Sonic and a Tails follower made (%s)", R.msg.c_str());
        CHECK(R.se->followers().leader_of((int32_t)tails) == (int32_t)sonic && R.ch(tails) && R.ch(tails)->follower,
              "the session knows the follower and its leader");
        std::vector<double> d;
        Val row;
        uint32_t pairs = 0;
        int bad_rows = 0;
        for (int t = 0; t < 600; t++) {
            double sx, sy;
            uint32_t bt;
            script_run(t, sx, sy, bt);
            R.pair(sonic, sx, sy, bt);
            std::vector<Val> r = R.ftick();
            row = r.size() == 1 && r[0].type == Type::Table ? r[0].tab->at(1) : Val();
            if (row.type != Type::Table || field_num(r[0], "count") != 1 || field_num(row, "id") != tails || !field_bool(row, "ok")) {
                bad_rows++;
            } else {
                pairs += (uint32_t)field_num(row, "pairs");
            }
            if (t > 30) {
                d.push_back(R.dist(sonic, tails));
            }
        }
        CHECK(bad_rows == 0 && pairs >= 590, "FollowersTick: one row per frame, ok (%u pairs run)", pairs);
        double med = median_of(d);
        CHECK(med < 400.0, "600 pairs of running and turning: the median distance %.0f HU (< 400)", med);
        INFO("distance over the run: max %.0f HU; respawns %g", *std::max_element(d.begin(), d.end()), R.info_num(tails, "respawns"));
        // D8: the row's drawn root is the session's
        gsa1::Character *c = R.ch(tails);
        CHECK(c && row.type == Type::Table && (float)field_num(row, "x") == c->r_pos[0] && (float)field_num(row, "z") == c->r_pos[2] &&
                  field_num(row, "tris") == c->out_triangles && row.tab->field("rendered").type == Type::Bool &&
                  row.tab->field("restructured").type == Type::Bool && row.tab->field("interpolated").type == Type::Bool,
              "out[i] has the drawn root x, y, z, yaw, interpolated, alpha, tris (D8): %.0f %.0f %.0f, %g triangles",
              field_num(row, "x"), field_num(row, "y"), field_num(row, "z"), field_num(row, "tris"));

        // the fields of FollowerInfo
        Val o = Val::table();
        std::vector<Val> fi = L.call("FollowerInfo", {Val::number(tails), o});
        bool same = fi.size() == 1 && fi[0].type == Type::Table && fi[0].tab == o.tab;
        CHECK(same && field_num(o, "kind") == SA1_CHAR_TAILS && field_num(o, "leader") == sonic && field_num(o, "mode") == 4 &&
                  field_num(o, "level") == 1 && field_bool(o, "sounds") && field_num(o, "objects") == 1 && !field_bool(o, "held") &&
                  !field_bool(o, "lost") && field_num(o, "pairs") >= 590 && field_num(o, "hidden") >= 0.0 && field_num(o, "hidden") <= 1.0,
              "FollowerInfo fills the given table: kind 2, leader, mode 4 (following), smode %g, offscreen %g, distance %.0f, hidden %.2f",
              field_num(o, "smode"), field_num(o, "offscreen"), field_num(o, "distance"), field_num(o, "hidden"));

        // Sonic moved 8,000 HU in one tick (a new leader there): one respawn, in from above the camera eye passed
        double lead2 = R.create_char(SA1_CHAR_SONIC, 8000.0f, -6000.0f);
        std::vector<Val> fl = L.call("FollowerLeader", {Val::number(tails), Val::number(lead2)});
        double respawns0 = R.info_num(tails, "respawns");
        const float eye[3] = {8000.0f, -6000.0f + 240.0f, 200.0f}, target[3] = {8000.0f, -6000.0f, 60.0f};
        bool came = false;
        double hd = 1e9, above = -1e9;
        for (int t = 0; t < 60 && !came; t++) {
            R.pair(lead2);
            R.ftick(1.0 / 30.0, eye, target);
            if (R.info_num(tails, "respawns") > respawns0) {
                gsa1::Character *cc = R.ch(tails);
                hd = std::hypot(cc->st.position[0] - eye[0], cc->st.position[1] - eye[1]);
                above = cc->st.position[2] - eye[2];
                came = true;
            }
        }
        CHECK(is_true(fl) && came && R.info_num(tails, "respawns") == respawns0 + 1.0 && hd < 400.0 && above > 0.0,
              "the leader 8,000 HU away: one respawn, %.0f HU horizontally from the camera eye passed and %.0f above it (the host camera "
              "reaches the follower)", hd, above);
        CHECK(R.ch(tails)->host_camera_passed && R.ch(tails)->host_camera_ticks > 0, "the camera tail went to the follower of a local leader");

        // FollowerHold on -> parked; off -> placed behind Sonic, then it follows again (review R.5)
        L.call("FollowerHold", {Val::number(tails), Val::boolean(true)});
        for (int t = 0; t < 10; t++) {
            R.pair(lead2);
            R.ftick();
        }
        CHECK(R.info_num(tails, "mode") == 6 && R.info_bool(tails, "held"), "FollowerHold on: mode 6 (parked), held");
        L.call("FollowerHold", {Val::number(tails), Val::boolean(false)});
        bool placed = false;
        double place_d = 1e9;
        for (int t = 0; t < 30 && !placed; t++) {
            R.pair(lead2);
            R.ftick();
            place_d = R.dist(lead2, tails);
            placed = R.info_num(tails, "mode") == 4 && place_d < 88.0;
        }
        CHECK(placed && !R.info_bool(tails, "held"), "FollowerHold off: back to following, %.0f HU from the leader (the point 40 HU behind it, "
              "within 48)", place_d);
        std::vector<double> after;
        for (int t = 0; t < 300; t++) {
            R.pair(lead2, 0.0, t < 100 ? 1.0 : 0.0);
            R.ftick();
            after.push_back(R.dist(lead2, tails));
        }
        CHECK(median_of(after) < 400.0, "then the leader runs on: Tails' median distance over 300 pairs %.0f HU (< 400): it was not left parked",
              median_of(after));

        // a leader destroyed -> host-fed, no fault
        L.call("Destroy", {Val::number(lead2)});
        for (int t = 0; t < 30; t++) {
            R.ftick();
        }
        CHECK(R.info_num(tails, "leader") == 0 && R.ch(tails) && !R.ch(tails)->faulted && R.info_bool(tails, "lost"),
              "the leader destroyed: host-fed with its last state, no fault, lost true");
        R.clear();
    }

    // a leader above: Tails flies (action 37)
    {
        double a = R.create_char(SA1_CHAR_SONIC, 5800.0f, 0.0f);
        double tails = R.follower(SA1_CHAR_TAILS, 5800.0f, 0.0f, a);
        for (int t = 0; t < 30; t++) {
            R.pair(a);
            R.ftick();
        }
        double up = R.create_char(SA1_CHAR_SONIC, 6500.0f, 0.0f, kLedgeZ + 40.0f);
        L.call("FollowerLeader", {Val::number(tails), Val::number(up)});
        bool flew = false;
        for (int t = 0; t < 300 && !flew; t++) {
            R.pair(up);
            R.ftick();
            flew = R.ch(tails) && R.ch(tails)->st.action == 37;
        }
        CHECK(flew, "Sonic on a 200 HU ledge: Tails flies (action 37 seen); on the ledge after it: %.0f HU from Sonic", R.dist(up, tails));
        R.clear();
    }

    // a host-fed leader along a circle
    {
        double tails = R.follower(SA1_CHAR_TAILS, 300.0f, 0.0f, 0.0);
        CHECK(tails > 0, "a host-fed Tails (%s)", R.msg.c_str());
        std::vector<double> d;
        for (int t = 0; t < 300; t++) {
            double a = t * 0.01;
            float x = (float)(300.0 * std::cos(a)), y = (float)(300.0 * std::sin(a));
            float vx = (float)(-300.0 * std::sin(a) * 0.3), vy = (float)(300.0 * std::cos(a) * 0.3);
            std::vector<Val> f = L.call("FollowerFeed", {Val::number(tails), Val::vector(x, y, 0.0f), Val::vector(vx, vy, 0.0f),
                                                         Val::number(a * 57.29578 + 90.0), Val::boolean(true)});
            if (!is_true(f)) {
                d.clear();
                break;
            }
            R.ftick();
            gsa1::Character *c = R.ch(tails);
            d.push_back(std::hypot(c->st.position[0] - x, c->st.position[1] - y));
        }
        CHECK(d.size() == 300 && !R.ch(tails)->faulted, "FollowerFeed along a circle of 300 HU: 300 pairs, no fault");
        INFO("host-fed circle: median distance %.0f HU, last %.0f HU, respawns %g", median_of(d), d.empty() ? 0.0 : d.back(),
             R.info_num(tails, "respawns"));
        CHECK(R.info_num(tails, "leader") == 0, "FollowerInfo.leader 0: host-fed");
        R.clear();
    }

    // the mixer
    {
        Tap tap;
        tap.se = se;
        se->set_event_tap(Tap::cb, &tap);
        double sonic = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        double tails = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, sonic);
        double knux = R.follower(SA1_CHAR_KNUCKLES, 0.0f, 0.0f, sonic);
        double gamma = R.follower(SA1_CHAR_GAMMA, 0.0f, 0.0f, sonic);    // (the most sounds of the research's run: 2-38 in 600 pairs)
        Val quiet = Val::table();
        quiet.tab->set(Val::string("sounds"), Val::boolean(false));
        double mute = R.follower(SA1_CHAR_KNUCKLES, 0.0f, 0.0f, sonic, quiet);
        for (int t = 0; t < 600; t++) {
            double sx, sy;
            uint32_t bt;
            script_run(t, sx, sy, bt);
            R.pair(sonic, sx, sy, bt);
            R.ftick();
        }
        se->set_event_tap(nullptr, nullptr);
        int t_sounds = 0, k_sounds = 0, k_near = 0, m_sounds = 0, m_mixed = 0, f_jingle = 0, f_rumble = 0;
        double far_most = 0.0;
        for (size_t i = 0; i < tap.ev.size(); i++) {
            const sa1_event &e = tap.ev[i];
            bool snd = e.type == SA1_EVENT_SOUND || e.type == SA1_EVENT_VOICE;
            if (e.character == (sa1_character_id)tails && snd) {
                t_sounds++;
            }
            if ((e.character == (sa1_character_id)knux || e.character == (sa1_character_id)gamma) && snd && tap.mixed[i]) {
                k_sounds++;
                k_near += tap.from_char[i] >= 0.0f && tap.from_char[i] < 400.0f;
                far_most = std::max(far_most, (double)tap.from_char[i]);
            }
            if (e.character == (sa1_character_id)mute && snd) {
                m_sounds++;
                m_mixed += tap.mixed[i] ? 1 : 0;
            }
            bool fol = e.character == (sa1_character_id)tails || e.character == (sa1_character_id)knux ||
                       e.character == (sa1_character_id)gamma || e.character == (sa1_character_id)mute;
            if (fol && e.type == SA1_EVENT_JINGLE && tap.mixed[i]) {
                f_jingle++;
            }
            if (fol && e.type == SA1_EVENT_RUMBLE) {
                f_rumble++;
            }
        }
        CHECK(t_sounds == 0, "a following Tails emits no sound of his own (the game mutes player-1 Tails, code_8C0BF804.c:291-296): %d", t_sounds);
        CHECK(k_sounds > 0 && k_near == k_sounds, "the Knuckles and E-102 followers' sounds reach the mixer, each near its own position: %d (the "
              "farthest %.0f HU from its character)", k_sounds, far_most);
        CHECK(m_mixed == 0, "with sounds off none reaches the mixer (%d kept out)", m_sounds);
        CHECK(f_jingle == 0, "no follower's jingle reaches the mixer");
        INFO("rumble events of the followers' worlds: %d (never queued for Lua, no pad call)", f_rumble);
        // the queue for Lua
        Val ev = Val::table();
        L.call("PollEvents", {ev});
        int leaked = 0;
        for (int i = 1; i <= (int)field_num(ev, "count"); i++) {
            Val e = ev.tab->at(i);
            double ty = field_num(e, "type"), ch = field_num(e, "character");
            if ((ch == tails || ch == knux || ch == gamma || ch == mute) && (ty == SA1_EVENT_SOUND || ty == SA1_EVENT_SOUND_STOP || ty == SA1_EVENT_VOICE ||
                                                              ty == SA1_EVENT_JINGLE || ty == SA1_EVENT_RUMBLE)) {
                leaked++;
            }
        }
        CHECK(leaked == 0, "gsa1.PollEvents: no sound, voice, jingle or rumble event of a follower (%d)", leaked);
        R.clear();
    }

    // a follower breaks an invincibility box (libsa1's FI1 with kind 1): the game's jingle never plays, the item is reported
    {
        Tap tap;
        tap.se = se;
        se->set_event_tap(Tap::cb, &tap);
        std::vector<Val> box = L.call("SetAdd", {Val::number(SA1_OBJTYPE_ITEMBOX), Val::vector(120.0f, 0.0f, 0.0f), Val::angle(0, 0, 0),
                                                 Val::number(1), Val::number(0), Val::number(0), Val::number(601)});
        double f = R.follower(SA1_CHAR_SONIC, 0.0f, 0.0f, 0.0, Val(), 0.0f);
        CHECK(box.size() == 1 && box[0].type == Type::Number && f > 0, "an invincibility box and a host-fed Sonic follower (%s)", R.msg.c_str());
        int items = 0;
        for (int t = 0; t < 600 && items == 0; t++) {
            // the leader in the air right above the box: the AI jumps after him and the jump ball breaks it
            L.call("FollowerFeed", {Val::number(f), t < 30 ? Val::vector(0, 0, 0) : Val::vector(136.0f, 0.0f, 96.0f), Val::vector(0, 0, 0), Val::number(0),
                                    Val::boolean(t < 30)});
            R.ftick();
            Val ev = Val::table();
            L.call("PollEvents", {ev});
            for (int i = 1; i <= (int)field_num(ev, "count"); i++) {
                Val e = ev.tab->at(i);
                items += field_num(e, "type") == SA1_EVENT_FOLLOW && field_num(e, "id") == SA1_FOLLOW_EV_ITEM && field_num(e, "character") == f &&
                         field_num(e, "arg") == 1;
            }
        }
        se->set_event_tap(nullptr, nullptr);
        int jingles = 0, jingles_mixed = 0;
        for (size_t i = 0; i < tap.ev.size(); i++) {
            if (tap.ev[i].character == (sa1_character_id)f && tap.ev[i].type == SA1_EVENT_JINGLE) {
                jingles++;
                jingles_mixed += tap.mixed[i] ? 1 : 0;
            }
        }
        // (libsa1 reports an invincibility box twice in the pair it breaks: 2 events here; only the log reads them)
        CHECK(items >= 1, "the box broken: SA1_EVENT_FOLLOW, SA1_FOLLOW_EV_ITEM arg 1 (invincibility) reached Lua with the follower's id (x%d)", items);
        CHECK(jingles_mixed == 0, "the follower world's jingle stays out of the mixer (%d jingle events, %d mixed)", jingles, jingles_mixed);
        L.call("SetClear", {});
        R.clear();
    }

    // the board
    for (int kind : {SA1_CHAR_SONIC, SA1_CHAR_TAILS}) {
        double sonic = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        double f = R.follower(kind, 0.0f, 0.0f, sonic);
        for (int t = 0; t < 20; t++) {
            R.pair(sonic);
            R.ftick();
        }
        std::vector<Val> b = L.call("Board", {Val::number(f), Val::boolean(true)});
        bool on = false;
        Val st = Val::table();
        int ticks = 0;
        for (; ticks < 30 && !on; ticks++) {
            R.pair(sonic);
            R.ftick();
            L.call("BoardState", {Val::number(f), st});
            on = field_bool(st, "on");
        }
        bool flagged = false;
        gsa1::Character *c = R.ch(f);
        int after_on = 0;
        for (; after_on < 60 && !flagged && on; after_on++) {
            R.pair(sonic);
            R.ftick();
            for (uint32_t i = 0; c && i < c->batch_count; i++) {
                flagged = flagged || (c->batches[i].flags & 0x4000u) != 0;
            }
        }
        CHECK(is_true(b) && on, "Board(follower of kind %d, true): BoardState.on within %d ticks", kind, ticks);
        CHECK(flagged, "its board batch has the flags 0x4000, %d frames after the ride began", after_on);
        L.call("Board", {Val::number(f), Val::boolean(false)});
        bool kept = false;
        for (int t = 0; t < 120 && !kept; t++) {
            R.pair(sonic);
            R.ftick();
            L.call("BoardState", {Val::number(f), st});
            kept = field_bool(st, "kept") && !field_bool(st, "on");
        }
        CHECK(kept, "Board(follower of kind %d, false): the board is kept", kind);
        R.clear();
    }

    // FollowerDraw
    {
        double sonic = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        double f = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, sonic);
        gsa1::Character *c = R.ch(f);
        auto count_renders = [&](int frames) {
            uint64_t r0 = c->render_count;
            for (int t = 0; t < frames; t++) {
                L.call("Tick", {Val::number(sonic), Val::number(0), Val::number(0), Val::number(0), Val::number(0), Val::number(1.0 / 60.0)});
                R.ftick(1.0 / 60.0);
            }
            return c->render_count - r0;
        };
        uint64_t full = count_renders(60);
        CHECK(full == 60, "level 1 (the default): rendered in every FollowersTick (%llu of 60)", (unsigned long long)full);
        CHECK(is_true(L.call("FollowerDraw", {Val::number(f), Val::number(2), Val::number(20)})), "FollowerDraw(id, 2, 20)");
        uint64_t far_renders = count_renders(180);
        CHECK(far_renders == 60, "level 2 at rate 20: %llu renders in 3 s of frames (3 x 20)", (unsigned long long)far_renders);
        float a1 = c->r_alpha;
        CHECK(a1 == 1.0f, "level 2 renders at alpha 1");
        CHECK(is_true(L.call("FollowerDraw", {Val::number(f), Val::number(3)})), "FollowerDraw(id, 3)");
        uint64_t none = count_renders(60);
        Val last = R.out.tab->at(1);
        CHECK(none == 0 && !field_bool(last, "rendered") && R.info_num(f, "level") == 3, "level 3: never rendered, still ticked");
        CHECK((float)field_num(last, "x") == c->st.position[0], "level 3's row has the state's position (the Lua side's distance reads it)");
        uint64_t r0 = c->render_count;
        std::vector<Val> rr = L.call("Render", {Val::number(f), Val::number(-1)});
        CHECK(c->render_count == r0 && rr.size() >= 1 && rr[0].type == Type::Number, "gsa1.Render(followerId) answers (a true value) and renders nothing");
        CHECK(is_true(L.call("FollowerDraw", {Val::number(f), Val::number(1)})), "back to level 1");
        std::vector<Val> bad = L.call("FollowerDraw", {Val::number(sonic), Val::number(1)});
        CHECK(is_nil_msg(bad) && str_of(bad, 2) == "bad_argument", "FollowerDraw on the player: bad_argument (%s)", str_of(bad, 1).c_str());
        R.clear();
    }

    // refusals with a world: a cycle, the memory guard, the limit
    {
        double sonic = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        double a = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, sonic);
        double b = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, a);
        std::vector<Val> c1 = L.call("FollowerLeader", {Val::number(a), Val::number(a)});
        std::vector<Val> c2 = L.call("FollowerLeader", {Val::number(a), Val::number(b)});
        CHECK(is_nil_msg(c1) && str_of(c1, 2) == "bad_argument" && is_nil_msg(c2) && str_of(c2, 2) == "bad_argument" &&
                  str_of(c2, 1) == gsa1::kReasonCycle,
              "FollowerLeader: itself or its own follower -> bad_argument, \"%s\"", str_of(c2, 1).c_str());
        CHECK(se->followers().levels().size() == 2, "a chain of 2: two job phases");
        static uint64_t low = (uint64_t)2072 * 1024u * 1024u;
        gsa1::set_memory_probe([]() -> uint64_t { return low; });
        std::vector<Val> m = L.call("FollowerCreate", {Val::number(SA1_CHAR_TAILS), Val::vector(0, 0, 40), Val::number(0), Val::number(sonic)});
        gsa1::set_memory_probe(nullptr);
        CHECK(is_nil_msg(m) && str_of(m, 2) == "limit" && str_of(m, 1) == gsa1::kReasonMemory, "below 2,073 MB of free memory: \"%s\" (limit)",
              str_of(m, 1).c_str());
        std::vector<Val> ne = L.call("FollowerCreate", {Val::number(SA1_CHAR_TAILS), Val::vector(0, 0, 40), Val::number(0), Val::number(9999)});
        CHECK(is_nil_msg(ne) && str_of(ne, 2) == "not_found", "a leader that does not exist: not_found");
        Val th = Val::number(3);
        std::vector<Val> w3 = L.call("FollowerThreads", {th});
        CHECK(w3.size() == 1 && w3[0].type == Type::Number && w3[0].num == (gsa1::kPoolLibParallel ? 3.0 : 0.0), "FollowerThreads(3) -> %g workers (LIB_PARALLEL %s)",
              w3.size() ? w3[0].num : -1.0, gsa1::kPoolLibParallel ? "true" : "false");
        L.call("FollowerThreads", {Val::number(0)});
        R.ftick();
        Val stats = Val::table();
        std::vector<Val> sr = L.call("FollowersStats", {stats});
        CHECK(sr.size() == 1 && sr[0].type == Type::Table && field_num(stats, "followers") == 2 && field_num(stats, "frames") >= 1,
              "FollowersStats: followers 2, workers %g, frames %g", field_num(stats, "workers"), field_num(stats, "frames"));
        R.clear();
    }

    // the session holds the player and 8 followers, the mixer's table is not filled by silent ones (D5)
    {
        double sonic = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        int made = 0;
        for (int i = 0; i < 8; i++) {
            made += R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, sonic) > 0;
        }
        for (int t = 0; t < 60; t++) {
            R.pair(sonic, 0.0, 1.0);
            R.ftick();
        }
        int faults = 0;
        for (int32_t id : se->ids()) {
            faults += se->get(id)->faulted;
        }
        CHECK(made == 8 && faults == 0, "the player and 8 followers: 60 pairs, 0 faults");
        R.clear();
    }

    // 99 Knuckles (the egg): objects 0, silent
    {
        std::string err;
        bool banks = se->audio_open(false, err);
        CHECK(banks, "the sound banks are open for the mixer's table (%s)", err.c_str());
        double sonic = R.create_char(SA1_CHAR_SONIC, 0.0f, 0.0f);
        Val o = Val::table();
        o.tab->set(Val::string("objects"), Val::number(0));
        o.tab->set(Val::string("sounds"), Val::boolean(false));
        double m0 = private_mb();
        std::vector<double> ids;
        double t0 = gsa1::now_ms();
        for (int i = 0; i < 99; i++) {
            double id = R.follower(SA1_CHAR_KNUCKLES, 0.0f, 0.0f, sonic, o);
            if (id <= 0) {
                break;
            }
            ids.push_back(id);
        }
        double create_ms = (gsa1::now_ms() - t0) / std::max<size_t>(1, ids.size());
        double m1 = private_mb();
        CHECK(ids.size() == 99, "99 Knuckles made (%zu: %s)", ids.size(), R.msg.c_str());
        INFO("create: %.2f ms each; private memory +%.0f MB (%.2f MB each)", create_ms, m1 - m0, (m1 - m0) / std::max<size_t>(1, ids.size()));
        // D5: the player's whoosh rule: a super-capable Sonic made after the 99
        gsa1::CreateExtra ex;
#if defined(SA1_API_SUPER)
        ex.flags = SA1_CREATE_SUPER_CAPABLE;
#endif
        const float p2[3] = {200.0f, 0.0f, 40.0f};
        int32_t sup = se->super_forms() ? se->create(SA1_CHAR_SONIC, p2, 0.0f, err, nullptr, nullptr, -1, &ex) : 0;
        if (sup > 0) {
            int32_t rs = se->audio().rule_status(sup, gsa1::kRuleWhoosh);
            CHECK(rs == (int32_t)SA1_OK && se->whoosh_routed(sup), "99 silent followers: the player's whoosh rule status OK (%d), the mixer's character table is not full", rs);
            L.call("Destroy", {Val::number(sup)});
        } else {
            INFO("no super-capable Sonic on this disc load: %s", err.c_str());
        }
        auto run = [&](uint32_t threads, int frames, double &ms_mean) {
            L.call("FollowerThreads", {Val::number(threads)});
            int faults = 0;
            double sum = 0.0;
            for (int t = 0; t < frames; t++) {
                R.pair(sonic, std::sin(t * 0.02), std::cos(t * 0.02));
                std::vector<Val> r = R.ftick();
                sum += r.size() == 1 && r[0].type == Type::Table ? field_num(r[0], "ms") : 0.0;
            }
            for (double id : ids) {
                faults += R.ch(id)->faulted;
            }
            ms_mean = sum / frames;
            return faults;
        };
        double ms_auto = 0.0;
        int faults = run(0, 600, ms_auto);
        CHECK(faults == 0, "99 Knuckles: 0 faults in 600 pairs (automatic workers: %u)", se->pool().workers());
        INFO("99 Knuckles: FollowersTick %.2f ms a pair, %u workers", ms_auto, se->pool().workers());
        if (std::getenv("GSA1_TEST_TIMING")) {
            for (uint32_t w : {1u, 0u}) {
                std::vector<double> v;
                for (int k = 0; k < 3; k++) {
                    double ms = 0.0;
                    run(w, 300, ms);
                    v.push_back(ms);
                }
                std::sort(v.begin(), v.end());
                INFO("timing: 99 Knuckles, FollowerThreads(%u): FollowersTick median %.2f ms, spread %.2f..%.2f (3 runs of 300 pairs)", (unsigned)w, v[1], v[0], v[2]);
            }
        } else {
            INFO("GSA1_TEST_TIMING is not set: the 3-run timing repeats are off (review R98.17)");
        }
        L.call("FollowerThreads", {Val::number(0)});
        R.clear();
        se->audio_close();
    }
}
#endif  // SA1_API_FOLLOWER

}  // namespace

int main(int argc, char **argv)
{
    std::string gdi;
    std::string bsp = gsa1_garrysmod_dir()[0] ? std::string(gsa1_garrysmod_dir()) + "\\maps\\gm_construct.bsp" : std::string();
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
        else if (std::string(argv[i]) == "--bsp") bsp = argv[++i];
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_follower_binding_test\n");
    CountingLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_follower_appdata");
#ifdef _WIN32
    char full[4096];
    GetFullPathNameA(fake_appdata.c_str(), sizeof full, full, nullptr);
    fake_appdata = full;
    SetEnvironmentVariableW(L"APPDATA", gsa1::widen(fake_appdata).c_str());
#else
    setenv("XDG_CONFIG_HOME", fake_appdata.c_str(), 1);
#endif
    gmod13_open(&state);
    Val g = L.globals.tab->field("gsa1");
    if (g.type != Type::Table) {
        CHECK(false, "gsa1 table");
        return 1;
    }
    Val feats = g.tab->field("FEATURES");
#if !defined(SA1_API_FOLLOWER)
    CHECK(feats.type == Type::Table && feats.tab->field("follower").type == Type::Nil && g.tab->field("FollowerCreate").type == Type::Nil &&
              g.tab->field("FOLLOWER").type == Type::Nil,
          "this libsa1.h has no SA1_API_FOLLOWER: gsa1.FEATURES.follower is absent and nothing of the feature is registered");
    std::printf("  info  follower_api.txt is written only with libsa1's follower API (SA1_API_FOLLOWER)\n");
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
#else
    std::vector<std::string> api;
    auto rec = [&](const std::string &s) { api.push_back(s); };

    // ---- the API part ------------------------------------------------------------------------------------------------------
    double fv = feats.type == Type::Table ? feats.tab->field("follower").num : -1.0;
    static const struct { const char *name, *args, *rets, *codes; } fns[] = {
        {"FollowerKinds", "[out]", "out", ""},
        {"FollowerCreate", "kind, pos, yawDeg, leaderId | nil [, opts]", "id | nil, message, code", "unsupported,limit,not_ready,fault,bad_argument,not_found"},
        {"FollowerLeader", "id, leaderId | nil", "true | nil, message, code", "unsupported,not_ready,bad_argument,not_found"},
        {"FollowerFeed", "id, pos, vel, yawDeg, ground [, kind]", "true | nil, message, code", "not_ready,bad_argument,not_found"},
        {"FollowerHostFlags", "id, flags", "true | nil, message, code", "not_ready,bad_argument,not_found"},
        {"FollowerHold", "id, on", "true | nil, message, code", "unsupported,not_ready,fault,bad_argument,not_found"},
        {"FollowerRespawn", "id", "true | nil, message, code", "unsupported,not_ready,fault,bad_argument,not_found"},
#if SA1_API_FOLLOWER >= 2
        {"FollowerStand", "id, on", "true | nil, message, code", "unsupported,not_ready,fault,bad_argument,not_found"},
        {"FollowerSpeed", "id, m", "true | nil, message, code", "unsupported,not_ready,fault,bad_argument,not_found"},
        {"FollowerSpot", "id, x, y", "true | nil, message, code", "unsupported,not_ready,fault,bad_argument,not_found"},
#endif
        {"FollowerDraw", "id, level [, rate]", "true | nil, message, code", "not_ready,bad_argument,not_found"},
        {"FollowersTick", "dt, viewYawDeg, camOrigin | nil, camTarget | nil, out [, interpolate]", "out | nil, message, code", "not_ready,bad_argument"},
        {"FollowerInfo", "id [, out]", "out | nil, message, code", "unsupported,not_ready,fault,bad_argument,not_found"},
        {"FollowerThreads", "n", "workers | nil, message, code", "not_ready,bad_argument"},
        {"FollowersStats", "[out]", "out", ""},
    };
    std::string missing;
    for (const auto &f : fns) {
        if (g.tab->field(f.name).type != Type::Function) missing += std::string(" ") + f.name;
        rec(gsa1::format("function\t%s\t%s\t%s\t%s", f.name, f.args, f.rets, f.codes));
    }
    rec(gsa1::format("feature\tfollower\t%s", fmt_num(fv).c_str()));
    CHECK(fv == (SA1_API_FOLLOWER >= 2 ? 2.0 : 1.0) && missing.empty(), "gsa1.FEATURES.follower = %g; every function of 5.5 registered%s", fv, missing.c_str());
    rec("option\tFollowerCreate\tupgrades\ttable\tupgrade names of the kind (gsa1.Upgrades(kind)), at most 32");
    rec("option\tFollowerCreate\tobjects\tnumber\t0,1 (gsa1.FOLLOWER.OBJECTS_*; default 1)");
    rec("option\tFollowerCreate\tsounds\tboolean\tdefault true");
    rec("option\tFollowerCreate\tseed\tnumber\ta whole number 0..2^32-1 (SA1_FOLLOW_SEED)");
    rec("option\tFollowerCreate\tfix_view\tboolean\tdefault true (false: SA1_FOLLOW_GAME_VIEW)");
    rec("option\tFollowerCreate\tfix_respawn\tboolean\tdefault true (false: SA1_FOLLOW_GAME_HISTORY)");

    Val C = g.tab->field("FOLLOWER");
    static const struct { const char *name; double v; } consts[] = {
        {"MAX", 112}, {"MAX_CHARACTERS", 128}, {"OBJECTS_NONE", 0}, {"OBJECTS_OWN", 1}, {"DRAW_FULL", 1}, {"DRAW_FAR", 2}, {"DRAW_NONE", 3},
        {"RATE_MIN", 5}, {"RATE_MAX", 30}, {"RATE_DEFAULT", 15}, {"POOL_MAX", 16},
#if SA1_API_FOLLOWER >= 2
        {"SPEED_MAX", SA1_FOLLOWER_SPEED_MAX},
#endif
    };
    static const struct { const char *name; double v; } modes[] = {{"PLACE", 0}, {"RESPAWN", 2}, {"NORMAL", 4}, {"TAKEOVER", 5}, {"PARKED", 6}};
    std::string wrong;
    for (const auto &c : consts) {
        Val v = C.type == Type::Table ? C.tab->field(c.name) : Val();
        if (v.type != Type::Number || v.num != c.v) wrong += std::string(" ") + c.name;
        rec(gsa1::format("const\tFOLLOWER.%s\t%s", c.name, fmt_num(v.type == Type::Number ? v.num : -1).c_str()));
    }
    Val M = C.type == Type::Table ? C.tab->field("MODE") : Val();
    for (const auto &c : modes) {
        Val v = M.type == Type::Table ? M.tab->field(c.name) : Val();
        if (v.type != Type::Number || v.num != c.v) wrong += std::string(" MODE.") + c.name;
        rec(gsa1::format("const\tFOLLOWER.MODE.%s\t%s", c.name, fmt_num(v.type == Type::Number ? v.num : -1).c_str()));
    }
    Val LP = C.type == Type::Table ? C.tab->field("LIB_PARALLEL") : Val();
    if (LP.type != Type::Bool) wrong += " LIB_PARALLEL";
    rec(gsa1::format("const\tFOLLOWER.LIB_PARALLEL\t%s", LP.b ? "true" : "false"));
    CHECK(C.type == Type::Table && wrong.empty(), "gsa1.FOLLOWER: MAX 112, MAX_CHARACTERS 128, OBJECTS_*, DRAW_*, RATE_*, POOL_MAX, LIB_PARALLEL %s, MODE {0, 2, 4, 5, 6}%s%s",
          LP.b ? "true" : "false", wrong.empty() ? "" : ": wrong", wrong.c_str());

    static const struct { const char *k; int type; } info_fields[] = {
        {"kind", Type::Number}, {"leader", Type::Number}, {"mode", Type::Number}, {"smode", Type::Number}, {"offscreen", Type::Number},
        {"distance", Type::Number}, {"respawns", Type::Number}, {"respawns_distance", Type::Number}, {"respawns_offscreen", Type::Number},
        {"held", Type::Bool}, {"lost", Type::Bool}, {"hidden", Type::Number}, {"pairs", Type::Number}, {"dropped", Type::Number},
        {"objects", Type::Number}, {"sounds", Type::Bool}, {"level", Type::Number},
#if SA1_API_FOLLOWER >= 2
        {"speed_factor", Type::Number},
#endif
    };
    for (const auto &f : info_fields) rec(gsa1::format("field\tFollowerInfo\t%s\t%s", f.k, type_word(f.type)));
    for (const char *k : {"count", "workers", "ms", "ms_join"}) rec(gsa1::format("field\tFollowersTick\t%s\tnumber", k));
    static const struct { const char *k; const char *type; } row_fields[] = {
        {"id", "number"}, {"pairs", "number"}, {"ok", "boolean"}, {"code", "string (only when ok is false, else nil)"},
        {"msg", "string (only when there is one, else nil)"}, {"rendered", "boolean"}, {"restructured", "boolean"}, {"x", "number"},
        {"y", "number"}, {"z", "number"}, {"yaw", "number"}, {"interpolated", "boolean"}, {"alpha", "number"}, {"tris", "number"},
    };
    for (const auto &f : row_fields) rec(gsa1::format("field\tFollowersTick[i]\t%s\t%s", f.k, f.type));
    for (const char *k : {"followers", "workers", "ms_tick", "ms_render", "ms_join", "ms_wall", "frames"}) rec(gsa1::format("field\tFollowersStats\t%s\tnumber", k));
    rec("field\tFollowerKinds\t[kind]\t0,2,3,5,6,7");
    rec(gsa1::format("reason\tbad_argument\t%s", gsa1::kReasonCycle));
    rec(gsa1::format("reason\tlimit\t%s", gsa1::kReasonMemory));
    rec(gsa1::format("reason\tlimit\t%s", gsa1::kReasonMaxChars));
    rec(gsa1::format("reason\tlimit\t%s", gsa1::kReasonMaxFollowers));
    rec("reason\tbad_argument\tthis character is not a follower");
    rec("reason\tnot_found\tno such character");

    // arguments and codes without the disc
    {
        int bad = 0;
        auto is_code = [&](const std::vector<Val> &r, const char *code) { return is_nil_msg(r) && str_of(r, 2) == code; };
        Val pos = Val::vector(0, 0, 0);
        bad += !is_code(L.call("FollowerCreate", {Val::string("x"), pos, Val::number(0)}), "bad_argument");
        bad += !is_code(L.call("FollowerCreate", {Val::number(99), pos, Val::number(0)}), "bad_argument");
        bad += !is_code(L.call("FollowerCreate", {Val::number(2), Val::number(1), Val::number(0)}), "bad_argument");
        bad += !is_code(L.call("FollowerCreate", {Val::number(2), pos, Val::number(0), Val::string("me")}), "bad_argument");
        bad += !is_code(L.call("FollowerCreate", {Val::number(2), pos, Val::number(0), Val(), Val::number(1)}), "bad_argument");
        Val o1 = Val::table();
        o1.tab->set(Val::string("objects"), Val::number(5));
        bad += !is_code(L.call("FollowerCreate", {Val::number(2), pos, Val::number(0), Val(), o1}), "bad_argument");
        Val o2 = Val::table();
        o2.tab->set(Val::string("sounds"), Val::string("yes"));
        bad += !is_code(L.call("FollowerCreate", {Val::number(2), pos, Val::number(0), Val(), o2}), "bad_argument");
        bad += !is_code(L.call("FollowerCreate", {Val::number(2), pos, Val::number(0)}), "not_ready");
        bad += !is_code(L.call("FollowerLeader", {Val::string("x")}), "bad_argument");
        bad += !is_code(L.call("FollowerLeader", {Val::number(1)}), "not_ready");
        bad += !is_code(L.call("FollowerFeed", {Val::number(1), pos}), "bad_argument");
        bad += !is_code(L.call("FollowerFeed", {Val::number(1), pos, pos, Val::number(0), Val::boolean(true)}), "not_ready");
        bad += !is_code(L.call("FollowerHostFlags", {Val::number(1), Val::number(999)}), "bad_argument");
        bad += !is_code(L.call("FollowerHostFlags", {Val::number(1), Val::number(1)}), "not_ready");
        bad += !is_code(L.call("FollowerHold", {Val::number(1), Val::number(1)}), "bad_argument");
        bad += !is_code(L.call("FollowerHold", {Val::number(1), Val::boolean(true)}), "not_ready");
        bad += !is_code(L.call("FollowerRespawn", {Val::string("x")}), "bad_argument");
        bad += !is_code(L.call("FollowerRespawn", {Val::number(1)}), "not_ready");
        bad += !is_code(L.call("FollowerDraw", {Val::number(1), Val::number(4)}), "bad_argument");
        bad += !is_code(L.call("FollowerDraw", {Val::number(1), Val::number(2), Val::number(4)}), "bad_argument");
        bad += !is_code(L.call("FollowerDraw", {Val::number(1), Val::number(2), Val::number(31)}), "bad_argument");
        bad += !is_code(L.call("FollowerDraw", {Val::number(1), Val::number(2)}), "not_ready");
        bad += !is_code(L.call("FollowersTick", {Val::string("x"), Val::number(0)}), "bad_argument");
        bad += !is_code(L.call("FollowersTick", {Val::number(0), Val::number(0), pos}), "bad_argument");
        bad += !is_code(L.call("FollowersTick", {Val::number(0), Val::number(0), Val(), Val(), Val::number(1)}), "bad_argument");
        bad += !is_code(L.call("FollowersTick", {Val::number(0), Val::number(0), Val(), Val(), Val::table()}), "not_ready");
        bad += !is_code(L.call("FollowerInfo", {Val::string("x")}), "bad_argument");
        bad += !is_code(L.call("FollowerInfo", {Val::number(1)}), "not_ready");
        bad += !is_code(L.call("FollowerThreads", {Val::number(17)}), "bad_argument");
#if SA1_API_FOLLOWER >= 2
        bad += !is_code(L.call("FollowerSpeed", {Val::string("x"), Val::number(2)}), "bad_argument");
        bad += !is_code(L.call("FollowerSpeed", {Val::number(1)}), "bad_argument");
        bad += !is_code(L.call("FollowerSpeed", {Val::number(1), Val::string("fast")}), "bad_argument");
        bad += !is_code(L.call("FollowerSpeed", {Val::number(1), Val::number(std::nan(""))}), "bad_argument");
        bad += !is_code(L.call("FollowerSpeed", {Val::number(1), Val::number(2)}), "not_ready");
        bad += !is_code(L.call("FollowerSpot", {Val::string("x"), Val::number(0), Val::number(0)}), "bad_argument");
        bad += !is_code(L.call("FollowerSpot", {Val::number(1), Val::number(0)}), "bad_argument");
        bad += !is_code(L.call("FollowerSpot", {Val::number(1), Val::vector(0, 0, 0)}), "bad_argument");
        bad += !is_code(L.call("FollowerSpot", {Val::number(1), Val::number(0), Val::number(std::nan(""))}), "bad_argument");
        bad += !is_code(L.call("FollowerSpot", {Val::number(1), Val::number(0), Val::number(0)}), "not_ready");
#endif
        std::vector<Val> k = L.call("FollowerKinds", {});
        std::vector<Val> s = L.call("FollowersStats", {});
        bool shapes = k.size() == 1 && k[0].type == Type::Table && s.size() == 1 && s[0].type == Type::Table &&
                      field_num(s[0], "followers") == 0 && field_num(s[0], "frames") == 0;
        CHECK(bad == 0 && shapes && L.st.empty(), "without the disc: every bad argument -> bad_argument, valid calls -> not_ready; FollowerKinds and "
              "FollowersStats -> tables; %d wrong", bad);
    }

    std::string behaviour_line = "SKIP\tno disc";
    int exit_at = 0;
    Rig R;
    R.L = &L;
    auto write_api = [&]() {
        std::string path = gsa1::join_path(self.empty() ? "." : self, "follower_api.txt");
        std::string text = "# G-SA1 follower_api.txt: the module contract of round 0.9.8 (sadc docs/research/gsa1_098_plan.md 5.5)\n"
                           "# written by tests/feat_follower_binding_test.cpp from the module as built against this target's\n"
                           "# build/deps/include/libsa1.h (" + std::string(sa1_version_string()) + "). Tab-separated records:\n"
                           "# feature | function | option | const | field | reason | behaviour\n";
        for (const std::string &r : api) {
            text += r + "\n";
        }
        text += std::string("behaviour\t") + behaviour_line + "\n";
        std::FILE *f = std::fopen(path.c_str(), "wb");
        bool ok = f && std::fwrite(text.data(), 1, text.size(), f) == text.size();
        if (f) std::fclose(f);
        CHECK(ok, "follower_api.txt written: %s (%zu records)", path.c_str(), api.size() + 1);
    };
    if (gdi.empty()) {
        INFO("no --gdi / SA1_TEST_GDI: the behaviour part needs the disc");
        write_api();
    } else if (sa1_follower_kinds() == 0) {
        // the contract snapshot: libsa1 answers "not built yet"
        const char *why = sa1_follower_kind_reason(SA1_CHAR_TAILS);
        behaviour_line = "SKIP\tfollower is not built yet";
        CHECK(why && std::string(why).find("not built yet") != std::string::npos, "sa1_follower_kind_reason answers \"%s\"", why ? why : "");
        std::vector<Val> kr = L.call("FollowerKinds", {});
        Val tails = kr.size() == 1 && kr[0].type == Type::Table ? kr[0].tab->at(SA1_CHAR_TAILS) : Val();
        CHECK(tails.type == Type::String && tails.str.find("not built yet") != std::string::npos, "FollowerKinds[2] = \"%s\"", tails.str.c_str());
        std::printf("SKIP behaviour: follower is not built yet\n");
        write_api();
    } else {
        gsa1::make_dirs(fake_appdata);
        gsa1::Config cfg;
        cfg.disc = gdi;
        std::string err;
        CHECK(gsa1::save_config(cfg, err), "config written to the scratch APPDATA (%s)", err.c_str());
        L.call("Init", {});
        std::string ist = "loading";
        for (int polls = 0; ist == "loading" && polls < 30000; polls++) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            ist = str_of(L.call("InitPoll", {}), 0);
        }
        CHECK(ist == "ready", "the disc: %s", ist.c_str());
        std::string map;
        if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
            std::printf("  info  no gm_construct (%s): the play checks are skipped\n", bsp.c_str());
            behaviour_line = "SKIP\tno gm_construct";
            CHECK(false, "no gm_construct: a gate fails on this line (review R98.7)");
            write_api();
            exit_at = 1;
        } else {
            std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
            CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct) (Create needs a world)");
            R.se = gsa1::mod::session();
            CHECK(R.se && R.se->set_world(fixture(), err), "the fixture: a flat floor with a 200 HU block (%s)", err.c_str());
            behaviour_line = "RAN\tfollower";
            write_api();
            behaviour(L, R);
#if SA1_API_FOLLOWER >= 2
            behaviour099(L, R);
#endif
        }
    }
    (void)exit_at;
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
#endif
}
