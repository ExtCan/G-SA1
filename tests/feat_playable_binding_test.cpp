// feat_playable_binding_test: Dr. Eggman and Tikal through the module's Lua functions (round 0.9.9; sadc docs/research/gsa1_099_plan.md 5.5,
// 5.10, 6.5 tasks 1, 9 with its review R99.7; playable099.md 7.4). Linked like binding_test (the module's objects, libsa1, the mock Lua stack
// of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi; gm_construct from the Garry's Mod install gives gsa1.Create its world, a flat
// floor of its own (Session::set_world) is what they stand on.
//
//   feat_playable_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
//   * THE API PART runs whenever libsa1.h has SA1_API_PLAYABLE: gsa1.BUTTON_X is libsa1's 0x40, gsa1.Characters() calls kinds 1 and 4 playable,
//     Create before the disc answers nil + message; it writes build/<target>/playable_api.txt (tests/feat_playable_test.lua checks its mock
//     against it).
//   * THE BEHAVIOUR PART prints exactly one line per kind, "SKIP behaviour: tikal is not built yet" and "SKIP behaviour: eggman is not built
//     yet", and passes while libsa1 still refuses that kind's world (5.3). Otherwise: gsa1.Create(kind) on the floor; THE TICK MASK BY
//     BEHAVIOUR (review R99.7, a constant would hold with the mask untouched): gsa1.Tick(id, 0, 0, 0, gsa1.BUTTON_X, 1/30) then
//     gsa1.GetState(id).mode is 11 (Tikal), 17 (Eggman), and a twin world with no button is not; gsa1.Tick's other buttons still pass; A leaves
//     the mode; "not here": emotes, the face, the look and the board answer a refusal with its words, never a fault. 0.9.9e: sa1_follower_create takes them (tests/feat_follower_binding_test.cpp, libsa1's FPL).
//
// playable_api.txt's records, one per line, tab-separated:
//   const BUTTON_X <number>       playable <kind>       behaviour <RAN | SKIP> <what>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

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
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

namespace {

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1.0;
}

// a refusal: nil or false, then a message
bool refused(const std::vector<Val> &r)
{
    return r.size() >= 2 && (r[0].type == Type::Nil || (r[0].type == Type::Bool && !r[0].b)) && r[1].type == Type::String && !r[1].str.empty();
}

#if defined(SA1_API_PLAYABLE)
// a flat SOLID floor (host space, z up) at z = 0, of 256-HU tiles
std::vector<sa1_collision_tri> flat_floor(float half)
{
    std::vector<sa1_collision_tri> out;
    const float tile = 256.0f;
    for (float x = -half; x < half - 0.5f; x += tile) {
        for (float y = -half; y < half - 0.5f; y += tile) {
            const float p[4][3] = {{x, y, 0.0f}, {x + tile, y, 0.0f}, {x + tile, y + tile, 0.0f}, {x, y + tile, 0.0f}};
            sa1_collision_tri a, b;
            std::memset(&a, 0, sizeof a);
            std::memset(&b, 0, sizeof b);
            std::memcpy(a.v[0], p[0], 12);
            std::memcpy(a.v[1], p[1], 12);
            std::memcpy(a.v[2], p[2], 12);
            std::memcpy(b.v[0], p[0], 12);
            std::memcpy(b.v[1], p[2], 12);
            std::memcpy(b.v[2], p[3], 12);
            a.surface = b.surface = SA1_SURFACE_SOLID;
            out.push_back(a);
            out.push_back(b);
        }
    }
    return out;
}
#endif

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
    std::printf("G-SA1 feat_playable_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_playable_appdata");
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
    auto finish = [&]() {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    };
#if !defined(SA1_API_PLAYABLE)
    CHECK(g.type == Type::Table && g.tab->field("BUTTON_X").type == Type::Nil, "libsa1.h has no SA1_API_PLAYABLE: no gsa1.BUTTON_X");
    return finish();
#else
    if (g.type != Type::Table) {
        CHECK(false, "the gsa1 table");
        return 1;
    }
    // ---- the API part --------------------------------------------------------------------------------------------------------
    std::vector<std::string> api;
    auto write_api = [&](const char *behaviour) {
        std::string path = gsa1::join_path(self.empty() ? "." : self, "playable_api.txt");
        std::string text = "# G-SA1 playable_api.txt: the module contract of round 0.9.9 (sadc docs/research/gsa1_099_plan.md 5.5), written by\n"
                           "# tests/feat_playable_binding_test.cpp from the module as built against this target's build/deps/include/libsa1.h (" +
                           std::string(sa1_version_string()) + ")\n";
        for (const std::string &r : api) text += r + "\n";
        text += std::string("behaviour\t") + behaviour + "\n";
        std::FILE *f = std::fopen(path.c_str(), "wb");
        bool ok = f && std::fwrite(text.data(), 1, text.size(), f) == text.size();
        if (f) std::fclose(f);
        CHECK(ok, "playable_api.txt written: %s (%zu records)", path.c_str(), api.size() + 1);
    };
    Val bx = g.tab->field("BUTTON_X");
    CHECK(bx.type == Type::Number && bx.num == SA1_BUTTON_X && bx.num == 0x40, "gsa1.BUTTON_X = %g: libsa1's SA1_BUTTON_X (0x40)", bx.num);
    api.push_back(gsa1::format("const\tBUTTON_X\t%.0f", bx.num));
    std::vector<Val> ch = L.call("Characters", {});
    int listed = 0;
    if (ch.size() == 1 && ch[0].type == Type::Table) {
        for (int i = 1; i <= 16; i++) {
            Val e = ch[0].tab->at(i);
            if (e.type == Type::Table && (e.tab->field("kind").num == SA1_CHAR_EGGMAN || e.tab->field("kind").num == SA1_CHAR_TIKAL) &&
                e.tab->field("playable").b) {
                listed++;
                api.push_back(gsa1::format("playable\t%.0f", e.tab->field("kind").num));
            }
        }
    }
    CHECK(listed == 2, "gsa1.Characters() calls %d of Eggman and Tikal playable", listed);
    std::vector<Val> nd = L.call("Create", {Val::number(SA1_CHAR_TIKAL), Val::vector(0, 0, 0), Val::number(0)});
    CHECK(refused(nd) && L.st.empty(), "before the disc Create(Tikal) answers nil + a message, no Lua error (%s)", str_of(nd, 1).c_str());
    if (gdi.empty()) {
        std::printf("  info  no disc: the behaviour part needs --gdi\n");
        write_api("SKIP\tno disc");
        return finish();
    }
    gsa1::make_dirs(fake_appdata);
    gsa1::Config cfg;
    cfg.disc = gdi;
    std::string err;
    CHECK(gsa1::save_config(cfg, err), "config written to the scratch APPDATA (%s)", err.c_str());
    L.call("Init", {});
    std::string ist = "loading";
    for (int polls = 0; ist == "loading" && polls < 60000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        ist = str_of(L.call("InitPoll", {}), 0);
    }
    CHECK(ist == "ready", "the disc: %s", ist.c_str());
    if (ist != "ready") {
        write_api("SKIP\tno disc");
        return finish();
    }
    ch = L.call("Characters", {});
    int loaded = 0;
    for (int i = 1; ch.size() == 1 && ch[0].type == Type::Table && i <= 16; i++) {
        Val e = ch[0].tab->at(i);
        if (e.type == Type::Table && (e.tab->field("kind").num == SA1_CHAR_EGGMAN || e.tab->field("kind").num == SA1_CHAR_TIKAL) &&
            e.tab->field("loaded").b) {
            loaded++;
        }
    }
    CHECK(loaded == 2, "the disc load read %d of Eggman and Tikal (kPlayableMask)", loaded);
    std::string map;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
        std::printf("  info  no gm_construct (%s): the behaviour part is skipped\n", bsp.c_str());
        write_api("SKIP\tno gm_construct");
        return finish();
    }
    std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct) (Create needs a world)");
    gsa1::Session *se = gsa1::mod::session();
    bool world = se && se->set_world(flat_floor(4096.0f), err);
    CHECK(world, "a flat SOLID floor (%s)", err.c_str());

    // ---- the behaviour part, per kind ---------------------------------------------------------------------------------------------
    const double kDt = 1.0 / 30.0;
    auto tick = [&](double id, double buttons, double sx = 0.0, double sy = 0.0) {
        return L.call("Tick", {Val::number(id), Val::number(sx), Val::number(sy), Val::number(0), Val::number(buttons), Val::number(kDt)});
    };
    Val st = Val::table();
    auto mode_of = [&](double id) {
        L.call("GetState", {Val::number(id), st});
        Val m = st.tab->field("mode");
        return m.type == Type::Number ? m.num : -1.0;
    };
    auto z_of = [&](double id) {
        L.call("GetState", {Val::number(id), st});
        return st.tab->field("z").num;
    };
    auto create = [&](int kind) {
        return L.call("Create", {Val::number(kind), Val::vector(0, 0, 8), Val::number(0)});
    };
    int ran = 0;
    struct Kind { int kind; const char *name; const char *title; double debug_mode; } kinds[] = {
        {SA1_CHAR_TIKAL, "tikal", "Tikal", 11.0}, {SA1_CHAR_EGGMAN, "eggman", "Eggman", 17.0},
    };
    for (const Kind &K : kinds) {
        std::vector<Val> r = create(K.kind);
        double id = num_of(r, 0);
        if (id <= 0.0) {
            // libsa1 has no row for this kind yet: its refusal, by its code in the message (5.3)
            std::string msg = str_of(r, 1);
            bool gated = refused(r) && (msg.find("(unsupported)") != std::string::npos || msg.find("not built yet") != std::string::npos);
            CHECK(gated, "%s: not created, and the answer is libsa1's refusal (%s)", K.title, msg.c_str());
            std::printf("SKIP behaviour: %s is not built yet\n", K.name);
            continue;
        }
        ran++;
        CHECK(L.st.empty(), "gsa1.Create(%s) = id %.0f on the floor", K.title, id);
        for (int i = 0; i < 40; i++) tick(id, 0);
        std::vector<Val> twin_r = create(K.kind);
        double twin = num_of(twin_r, 0);
        for (int i = 0; i < 40; i++) tick(twin, 0);
        double stand = mode_of(id);
        // THE TICK MASK, BY BEHAVIOUR (review R99.7)
        std::vector<Val> t1 = tick(id, bx.num);
        double in_debug = mode_of(id);
        tick(twin, 0);
        double twin_mode = mode_of(twin);
        CHECK(t1.size() >= 1 && in_debug == K.debug_mode && twin_mode != K.debug_mode,
              "%s: gsa1.Tick(id, 0, 0, 0, gsa1.BUTTON_X, 1/30): GetState(id).mode %.0f -> %.0f (the game's debug mode); its twin with no button "
              "stays at %.0f", K.title, stand, in_debug, twin_mode);
        // the debug mode as playable099.md 2.4 measured it: no gravity, the stick with the button held goes up; jump (A) leaves it
        double z0 = z_of(id);
        for (int i = 0; i < 20; i++) tick(id, 0);
        double z1 = z_of(id);
        CHECK(std::fabs(z1 - z0) < 0.01 && mode_of(id) == K.debug_mode, "%s: in debug no gravity: z %.2f -> %.2f over 20 pairs, mode %.0f",
              K.title, z0, z1, mode_of(id));
        for (int i = 0; i < 10; i++) tick(id, bx.num, 0.0, 1.0);
        double z2 = z_of(id);
        CHECK(z2 > z1 + 1.0, "%s: the button held with the stick forward flies up: z %.2f -> %.2f", K.title, z1, z2);
        tick(id, SA1_BUTTON_JUMP);
        for (int i = 0; i < 3; i++) tick(id, 0);
        double left = mode_of(id);
        CHECK(left != K.debug_mode, "%s: jump (A) leaves it: mode %.0f", K.title, left);
        // "not here": a refusal with its words, never a fault
        std::vector<Val> no[4];
        no[0] = L.call("Emote", {Val::number(id), Val::string("a0")});
        no[1] = L.call("FaceMode", {Val::number(id), Val::boolean(true), Val::boolean(false)});
        no[2] = L.call("Look", {Val::number(id), Val::number(1), Val::number(0), Val::number(0), Val::number(0)});
        no[3] = L.call("Board", {Val::number(id), Val::boolean(true)});
        int nr = 0;
        for (const auto &n : no) nr += refused(n) ? 1 : 0;
        CHECK(nr == 4, "%s: not here: emote \"%s\" (%s), face \"%s\", look \"%s\", board \"%s\"", K.title, str_of(no[0], 1).c_str(),
              str_of(no[0], 2).c_str(), str_of(no[1], 1).c_str(), str_of(no[2], 1).c_str(), str_of(no[3], 1).c_str());
        // 0.9.9e: it can be a follower now, of itself too
        {
            std::vector<Val> fc = L.call("FollowerCreate", {Val::number(K.kind), Val::vector(32, 0, 8), Val::number(0), Val::number(id)});
            CHECK(fc.size() >= 1 && fc[0].type == Type::Number, "%s: a follower of its kind is made: %s", K.title, str_of(fc, 1).c_str());
            if (fc.size() >= 1 && fc[0].type == Type::Number) {
                L.call("Destroy", {fc[0]});
            }
        }
        std::vector<Val> again = tick(id, 0);
        CHECK(again.size() >= 1 && again[0].type == Type::Number, "%s: the world still ticks after those refusals", K.title);
        // a plain jump: their own code, no fault
        tick(id, SA1_BUTTON_JUMP);
        for (int i = 0; i < 30; i++) tick(id, SA1_BUTTON_ACTION, 0.0, 1.0);
        std::vector<Val> after = tick(id, 0);
        CHECK(after.size() >= 1 && after[0].type == Type::Number, "%s: run, jump and action tick with no fault", K.title);
        L.call("Destroy", {Val::number(id)});
        L.call("Destroy", {Val::number(twin)});
    }
    // the mask stays closed for everyone else's game code: a Sonic with the bit is the game's action button (the addon never sends it for him)
    {
        std::vector<Val> r = create(SA1_CHAR_SONIC);
        double sonic = num_of(r, 0);
        CHECK(sonic > 0.0, "a Sonic for the control (id %.0f)", sonic);
        if (sonic > 0.0) {
            for (int i = 0; i < 40; i++) tick(sonic, 0);
            std::vector<Val> t = tick(sonic, bx.num);
            CHECK(t.size() >= 1 && t[0].type == Type::Number && mode_of(sonic) != 11.0 && mode_of(sonic) != 17.0,
                  "the bit on a Sonic: no debug mode (mode %.0f)", mode_of(sonic));
            L.call("Destroy", {Val::number(sonic)});
        }
    }
    write_api(ran == 2 ? "RAN\ttikal and eggman" : ran == 1 ? "RAN\ttikal" : "SKIP\tneither is built yet");
    return finish();
#endif
}
