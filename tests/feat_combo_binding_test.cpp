// feat_combo_binding_test: what no single feature's test covers, through the module's Lua functions with the real module and the disc
// (round 0.9.8: sadc docs/research/gsa1_098_plan.md 6.6, recheck098.md 4.5 items 3-5). A separate program, so its failure names itself.
// Each part stands behind gsa1.FEATURES and libsa1's gate: a feature not built (or dropped) prints exactly one line "SKIP behaviour:
// <feature> is not built yet" and its part is left out; the whole-tree gate fails on that line unless lanes/drops.txt names the feature.
//
//   feat_combo_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
// Part 1, Big fishing with a Tails follower: the camera bit on the player only, 600 pairs, 0 faults, FollowersTick with the chase camera
// passed, no SA1_EVENT_CAMERA with the follower's id.
// Part 2, the front end open with 3 followers ticking: followers' state hashes equal to the run without; a pick's switch -> hold ->
// release behind the new character, no follower event in FrontendEvents.
// Part 3, 99 silent Knuckles plus the player and an open front end: the player's whoosh rule status OK, the mixer's character table not
// full (D5).
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "mock_lua.hpp"
#include "../src/core/config.hpp"
#include "../src/core/follower.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"

#ifndef INFO
#define INFO(...)                                            \
    do {                                                     \
        std::printf("  info  ");                             \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)
#endif

namespace {

#if defined(SA1_API_FOLLOWER)
const uint32_t kEventCamera = 17u;      // SA1_EVENT_CAMERA (plan 5.3)

double field_num(const Val &t, const char *k)
{
    Val v = t.type == Type::Table ? t.tab->field(k) : Val();
    return v.type == Type::Number ? v.num : -1e9;
}

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1e9;
}

void rect(std::vector<sa1_collision_tri> &o, float x0, float y0, float x1, float y1, float z, float tile, uint32_t surface)
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

const float kFlatX = 11000.0f;     // the middle of the flat part of the fixture

std::vector<sa1_collision_tri> fixture()
{
    std::vector<sa1_collision_tri> o;
    // Big's island (tests/feat_gamecam_binding_test.cpp)
    rect(o, -300, -300, 300, 300, 0, 300, SA1_SURFACE_SOLID);
    rect(o, -6000, -6000, 6000, -300, -20, 1000, SA1_SURFACE_WATER);
    rect(o, -6000, 300, 6000, 6000, -20, 1000, SA1_SURFACE_WATER);
    rect(o, -6000, -300, -300, 300, -20, 600, SA1_SURFACE_WATER);
    rect(o, 300, -300, 6000, 300, -20, 600, SA1_SURFACE_WATER);
    rect(o, -6000, -6000, 6000, 6000, -600, 1000, SA1_SURFACE_SOLID);
    // a flat floor for the runs
    rect(o, kFlatX - 4096, -4096, kFlatX + 4096, 4096, 0, 256, SA1_SURFACE_SOLID);
    return o;
}

struct Rig {
    MockLua *L = nullptr;
    gsa1::Session *se = nullptr;
    Val out = Val::table();
    void pair(double id, double sx = 0.0, double sy = 0.0, double buttons = 0.0, double flags = 0.0)
    {
        L->call("Tick", {Val::number(id), Val::number(sx), Val::number(sy), Val::number(0), Val::number(buttons), Val::number(1.0 / 30.0),
                         Val::boolean(true), Val::number(flags)});
    }
    void ftick(const float *eye = nullptr, const float *target = nullptr)
    {
        Val a, b;
        if (eye) {
            a = Val::vector(eye[0], eye[1], eye[2]);
            b = Val::vector(target[0], target[1], target[2]);
        }
        L->call("FollowersTick", {Val::number(1.0 / 30.0), Val::number(0), a, b, out});
    }
    double create_char(int kind, float x, float y, float z)
    {
        return num_of(L->call("Create", {Val::number(kind), Val::vector(x, y, z), Val::number(0)}), 0);
    }
    double follower(int kind, float x, float y, float z, double leader, const Val &opts)
    {
        std::vector<Val> r = L->call("FollowerCreate", {Val::number(kind), Val::vector(x, y, z), Val::number(0),
                                                        leader > 0 ? Val::number(leader) : Val(), opts});
        if (r.empty() || r[0].type != Type::Number) {
            std::printf("  info  FollowerCreate: %s\n", str_of(r, 1).c_str());
            return -1.0;
        }
        return r[0].num;
    }
    gsa1::Character *ch(double id) { return se->get((int32_t)id); }
    void clear()
    {
        for (int32_t id : se->ids()) {
            L->call("Destroy", {Val::number(id)});
        }
        L->call("PollEvents", {Val::table()});
    }
};

struct Tap {
    uint32_t camera_of_player = 0, camera_of_follower = 0;
    int32_t player = 0;
    static void cb(void *user, const sa1_event &e, bool)
    {
        Tap *t = static_cast<Tap *>(user);
        if (e.type == kEventCamera) {
            if ((int32_t)e.character == t->player) {
                t->camera_of_player++;
            } else {
                t->camera_of_follower++;
            }
        }
    }
};

bool feature_on(const Val &g, const char *name)
{
    Val f = g.tab->field("FEATURES");
    return f.type == Type::Table && f.tab->field(name).type == Type::Number;
}

// ---- part 1 ---------------------------------------------------------------------------------------------------------------------
void part_fishing(MockLua &L, Rig &R, const Val &g)
{
    std::printf("part 1: Big fishing with a Tails follower\n");
    bool on = feature_on(g, "gamecam");
    if (on) {
        double probe = R.create_char(SA1_CHAR_BIG, 0.0f, 0.0f, 8.0f);
        Val t = Val::table();
        std::vector<Val> c = L.call("Camera", {Val::number(probe), Val::number(-1), t});
        on = c.size() >= 1 && c[0].type == Type::Bool && c[0].b;
        L.call("Destroy", {Val::number(probe)});
    }
    if (!on) {
        std::printf("SKIP behaviour: gamecam is not built yet\n");
        return;
    }
    double big = R.create_char(SA1_CHAR_BIG, 0.0f, 0.0f, 8.0f);
    double tails = R.follower(SA1_CHAR_TAILS, 0.0f, 0.0f, 8.0f, big, Val());
    CHECK(big > 0 && tails > 0, "Big and a Tails follower on the island");
    Tap tap;
    tap.player = (int32_t)big;
    R.se->set_event_tap(Tap::cb, &tap);
    const double bit = g.tab->field("INPUT_GAME_CAMERA").num;
    L.call("FollowerHostFlags", {Val::number(tails), Val::number(bit)});
    int active = 0, cam_rows = 0;
    Val cam = Val::table();
    const float eye[3] = {0.0f, -240.0f, 160.0f}, target[3] = {0.0f, 0.0f, 40.0f};
    for (int p = 0; p < 600; p++) {
        int q = p % 260;        // bigfish 2.4's inputs, again and again (fish098 2.1)
        double sy = (q >= 25 && q < 50) ? 1.0 : 0.0;
        double b = (q >= 10 && q < 50) ? (double)SA1_BUTTON_ACTION : (q >= 200 && q < 220) ? (double)(SA1_BUTTON_L | SA1_BUTTON_R) : 0.0;
        R.pair(big, 0.0, sy, b, bit);
        R.ftick(eye, target);
        std::vector<Val> c = L.call("Camera", {Val::number(big), Val::number(-1), cam});
        cam_rows += c.size() >= 1 && c[0].type == Type::Bool && c[0].b;
        active += ((uint32_t)field_num(cam, "flags") & (uint32_t)g.tab->field("CAMSTATE_ACTIVE").num) != 0;
    }
    R.se->set_event_tap(nullptr, nullptr);
    gsa1::Character *cb = R.ch(big), *ct = R.ch(tails);
    CHECK(cb && ct && !cb->faulted && !ct->faulted, "600 pairs: 0 faults");
    CHECK(active > 100 && cam_rows == 600, "the player's request ran: %d of 600 pairs ACTIVE", active);
    CHECK(tap.camera_of_player > 0 && tap.camera_of_follower == 0, "SA1_EVENT_CAMERA: %u of the player, %u with the follower's id",
          tap.camera_of_player, tap.camera_of_follower);
    CHECK(ct && (ct->host_flags_last & (uint32_t)bit) == 0u && ct->host_camera_ticks >= 600u && ct->host_camera_passed,
          "the follower: no camera bit in its flags (FollowerHostFlags masks it), the chase camera passed in %llu ticks",
          ct ? (unsigned long long)ct->host_camera_ticks : 0ull);
    R.clear();
}

uint64_t fnv_state(uint64_t h, const sa1_state_ex &st)
{
    const uint8_t *b = reinterpret_cast<const uint8_t *>(&st);
    for (size_t i = 0; i < sizeof st; i++) {
        h = (h ^ b[i]) * 1099511628211ull;
    }
    return h;
}

// a scripted Sonic and 3 Tails followers; with the front end open and ticking if asked. The followers' state hashes
std::vector<uint64_t> run_three(MockLua &L, Rig &R, bool open_frontend)
{
    std::vector<uint64_t> h(3, 1469598103934665603ull);
    double sonic = R.create_char(SA1_CHAR_SONIC, kFlatX, 0.0f, 40.0f);
    Val o = Val::table();
    o.tab->set(Val::string("seed"), Val::number(4242));
    double ids[3];
    for (int i = 0; i < 3; i++) {
        ids[i] = R.follower(SA1_CHAR_TAILS, kFlatX, 0.0f, 40.0f, sonic, o);
    }
    if (open_frontend) {
        Val a = Val::table();
        a.tab->set(Val::string("slot"), Val::number(0));
        std::vector<Val> f = L.call("FrontendOpen", {a});
        CHECK(f.size() >= 1 && f[0].type == Type::Bool && f[0].b, "FrontendOpen with 3 followers");
    }
    for (int p = 0; p < 300; p++) {
        R.pair(sonic, std::sin(p * 0.02), std::cos(p * 0.02));
        R.ftick();
        if (open_frontend) {
            L.call("FrontendTick", {Val::number(1.0 / 30.0), Val::number(0), Val::number(0), Val::number(0)});
        }
        for (int i = 0; i < 3; i++) {
            gsa1::Character *c = R.ch(ids[i]);
            if (c) {
                h[(size_t)i] = fnv_state(h[(size_t)i], c->st);
            }
        }
    }
    if (open_frontend) {
        L.call("FrontendClose", {});
    }
    R.clear();
    return h;
}

// ---- part 2 ---------------------------------------------------------------------------------------------------------------------
void part_frontend(MockLua &L, Rig &R, const Val &g)
{
    std::printf("part 2: the front end open with 3 followers ticking\n");
    bool on = feature_on(g, "frontend");
    if (on) {
        std::vector<Val> f = L.call("FrontendOpen", {Val::table()});
        on = f.size() >= 1 && f[0].type == Type::Bool && f[0].b;
        if (!on && str_of(f, 1).find("not built yet") == std::string::npos) {
            CHECK(false, "FrontendOpen: %s", str_of(f, 1).c_str());
        }
        L.call("FrontendClose", {});
    }
    if (!on) {
        std::printf("SKIP behaviour: frontend is not built yet\n");
        return;
    }
    std::vector<uint64_t> without = run_three(L, R, false), with = run_three(L, R, true);
    CHECK(without == with, "the followers' state hashes with the front end open equal the run without (%016llX ...)",
          (unsigned long long)without[0]);

    // a pick: the panel closes and the character is switched (cl_charselect: GSA1.Spawn): the hold, the switch, the release
    double sonic = R.create_char(SA1_CHAR_SONIC, kFlatX, 0.0f, 40.0f);
    double fol[3];
    for (double &f : fol) {
        f = R.follower(SA1_CHAR_TAILS, kFlatX, 0.0f, 40.0f, sonic, Val());
    }
    for (int p = 0; p < 30; p++) {
        R.pair(sonic);
        R.ftick();
    }
    Val a = Val::table();
    a.tab->set(Val::string("slot"), Val::number(1));
    L.call("FrontendOpen", {a});
    const double A = g.tab->field("FRONTEND").tab->field("A").num;
    Val ev = Val::table();
    int picks = 0, bad_kinds = 0;
    for (int p = 0; p < 120 && picks == 0; p++) {
        R.pair(sonic);
        R.ftick();
        std::vector<Val> t = L.call("FrontendTick", {Val::number(1.0 / 30.0), Val::number(0), Val::number(0), Val::number(p == 60 ? A : 0.0)});
        std::vector<Val> e = L.call("FrontendEvents", {ev});
        int m = (int)num_of(e, 0);
        for (int k = 1; k <= m; k++) {
            std::string kind = ev.tab->at(k).tab->field("kind").str;
            if (kind == "pick") {
                picks++;
            } else if (kind != "select" && kind != "done" && kind != "cancel" && kind != "music") {
                bad_kinds++;
            }
        }
    }
    CHECK(picks == 1 && bad_kinds == 0, "A in the open front end: one \"pick\"; no follower event among FrontendEvents (%d others)", bad_kinds);
    // the switch: hold, the old character goes, a new one, release behind it (096 4.16)
    for (double f : fol) {
        L.call("FollowerHold", {Val::number(f), Val::boolean(true)});
    }
    L.call("Destroy", {Val::number(sonic)});
    double knux = R.create_char(SA1_CHAR_KNUCKLES, kFlatX + 300.0f, 0.0f, 40.0f);
    for (double f : fol) {
        L.call("FollowerLeader", {Val::number(f), Val::number(knux)});
    }
    for (int p = 0; p < 5; p++) {
        R.pair(knux);
        R.ftick();
    }
    for (double f : fol) {
        L.call("FollowerHold", {Val::number(f), Val::boolean(false)});
    }
    L.call("FrontendClose", {});
    int close_by = 0, faults = 0;
    for (int p = 0; p < 60; p++) {
        R.pair(knux);
        R.ftick();
    }
    gsa1::Character *ck = R.ch(knux);
    for (double f : fol) {
        gsa1::Character *c = R.ch(f);
        faults += !c || c->faulted;
        if (c && ck) {
            double d = std::hypot(c->st.position[0] - ck->st.position[0], c->st.position[1] - ck->st.position[1]);
            close_by += d < 200.0;
        }
    }
    CHECK(faults == 0 && close_by == 3, "the switch: hold -> release: the 3 followers are behind the new character (%d within 200 HU), no fault", close_by);
    R.clear();
}

// ---- part 3 ---------------------------------------------------------------------------------------------------------------------
void part_mixer(MockLua &L, Rig &R, const Val &g)
{
    std::printf("part 3: 99 silent Knuckles, the player and an open front end\n");
    if (!((sa1_follower_kinds() >> SA1_CHAR_KNUCKLES) & 1u)) {
        CHECK(false, "Knuckles cannot follow in this build: %s", sa1_follower_kind_reason(SA1_CHAR_KNUCKLES));
        return;
    }
    std::string err;
    CHECK(R.se->audio_open(false, err), "the sound banks are open (%s)", err.c_str());
    const float at[3] = {kFlatX, 0.0f, 40.0f};
    gsa1::CreateExtra ex;
#if defined(SA1_API_SUPER)
    ex.flags = SA1_CREATE_SUPER_CAPABLE;
#endif
    int32_t player = R.se->create(SA1_CHAR_SONIC, at, 0.0f, err, nullptr, nullptr, -1, &ex);
    CHECK(player > 0, "a super-capable Sonic (%s)", err.c_str());
    Val o = Val::table();
    o.tab->set(Val::string("objects"), Val::number(0));
    o.tab->set(Val::string("sounds"), Val::boolean(false));
    int made = 0;
    for (int i = 0; i < 99; i++) {
        made += R.follower(SA1_CHAR_KNUCKLES, kFlatX, 0.0f, 40.0f, player, o) > 0;
    }
    CHECK(made == 99, "99 silent Knuckles (%d)", made);
    bool fe = feature_on(g, "frontend");
    if (fe) {
        std::vector<Val> f = L.call("FrontendOpen", {Val::table()});
        fe = f.size() >= 1 && f[0].type == Type::Bool && f[0].b;
    }
    if (!fe) {
        std::printf("SKIP behaviour: frontend is not built yet\n");
    }
    for (int p = 0; p < 60; p++) {
        R.pair(player);
        R.ftick();
        if (fe) {
            L.call("FrontendTick", {Val::number(1.0 / 30.0), Val::number(0), Val::number(0), Val::number(0)});
        }
    }
    int32_t rs = R.se->audio().rule_status(player, gsa1::kRuleWhoosh);
    CHECK(rs == (int32_t)SA1_OK && R.se->whoosh_routed(player), "the player's whoosh rule status OK (%d)", rs);
    // a late character still finds a place in the mixer's table
    int32_t late = R.se->create(SA1_CHAR_SONIC, at, 0.0f, err, nullptr, nullptr, -1, &ex);
    int32_t rs2 = late > 0 ? R.se->audio().rule_status(late, gsa1::kRuleWhoosh) : -999;
    CHECK(rs2 == (int32_t)SA1_OK, "the mixer's character table is not full: a character made now gets its rule (%d)", rs2);
    if (fe) {
        L.call("FrontendClose", {});
    }
    int faults = 0;
    for (int32_t id : R.se->ids()) {
        faults += R.se->get(id)->faulted;
    }
    CHECK(faults == 0, "0 faults");
    R.clear();
    R.se->audio_close();
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
    std::printf("G-SA1 feat_combo_binding_test\n");
#if !defined(SA1_API_FOLLOWER)
    (void)argc;
    std::printf("  info  this libsa1.h has no SA1_API_FOLLOWER: nothing to combine yet\n");
    std::printf("\n0 checks, 0 failed\n");
    return 0;
#else
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_combo_appdata");
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
    CHECK(g.type == Type::Table, "gsa1 table");
    if (gdi.empty()) {
        INFO("no --gdi / SA1_TEST_GDI: every part needs the disc");
    } else if (!((sa1_follower_kinds() >> SA1_CHAR_TAILS) & 1u)) {
        std::printf("SKIP behaviour: follower is not built yet\n");
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
        bool have = gsa1::read_small_file(bsp, 512u << 20, map, err) && !map.empty();
        CHECK(have, "gm_construct read (%s)", bsp.c_str());
        if (have) {
            std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
            CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct) (Create needs a world)");
            Rig R;
            R.L = &L;
            R.se = gsa1::mod::session();
            CHECK(R.se && R.se->set_world(fixture(), err), "the fixture: Big's island and a flat floor (%s)", err.c_str());
            part_fishing(L, R, g);
            part_frontend(L, R, g);
            part_mixer(L, R, g);
        }
    }
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
#endif
}
