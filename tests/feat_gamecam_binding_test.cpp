// feat_gamecam_binding_test: Big's fishing camera through the module's Lua function (feature "gamecam"; round 0.9.8: sadc
// docs/research/gsa1_098_plan.md 5.5, 6.9 task 8 with its review R98.1, R98.7, R98.14; fish098.md 6.3 G2) - src/module/bind_gamecam.cpp:
// gsa1.Camera, gsa1.INPUT_GAME_CAMERA, gsa1.CAMSTATE_*, gsa1.CAMKIND_*. Linked like binding_test (the module's objects, libsa1, the mock
// Lua stack of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi; the play part uses gm_construct from the Garry's Mod install (read
// only) for gsa1.WorldLoadData and then an island of its own (Session::set_world).
//
//   feat_gamecam_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
// Two parts (review R98.14):
//   * THE API PART runs whenever libsa1.h has SA1_API_CAMERA: gsa1.FEATURES.gamecam == 1, the constants equal the header's, gsa1.Camera's
//     arguments ("bad_argument" before anything else), an unknown id false ("not_found"). It writes build/<target>/gamecam_api.txt next to
//     this test (the Lua test checks its mock against it: tests/feat_gamecam_test.lua).
//   * THE BEHAVIOUR PART prints exactly one line "SKIP behaviour: gamecam is not built yet" and passes while libsa1's sa1_character_camera
//     answers SA1_ERR_UNSUPPORTED (its gate is closed: gsa1_098_plan.md 5.3); otherwise it runs in full: Big casts on an island through
//     gsa1.Tick with gsa1.INPUT_GAME_CAMERA: AIM (level 2, adjust 3, RUNNING), then LURE (level 4, about 60 HU from the lure), then L + R:
//     CUT back at AIM, then no request; gsa1.Camera's every field a finite number, forward a unit vector, fov 70 degrees; no table made per
//     call (the mock counts them); the same cast without the bit: reported, never RUNNING. Final gates fail when the SKIP line appears.
//
// API NOTES: the Lua API is the header of src/module/bind_gamecam.cpp. gamecam_api.txt's records, one per line, tab-separated:
//   feature gamecam 1       function Camera id,alpha,out true|false,message,code <codes, comma separated>
//   const <NAME> <number>   field Camera <field> number       behaviour <SKIP | RAN> <what>
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

// a mock that counts the tables the module makes (gsa1.Camera with `out` must make none)
class CountingLua : public MockLua {
public:
    uint64_t tables = 0;
    void CreateTable() override
    {
        tables++;
        MockLua::CreateTable();
    }
};

#if defined(SA1_API_CAMERA)
const char *const k_fields[] = {"flags", "kind", "level", "adjust", "fn", "px", "py", "pz", "fx", "fy", "fz", "tx", "ty", "tz", "fov"};

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1e9;
}

bool is_true(const std::vector<Val> &r)
{
    return r.size() >= 1 && r[0].type == Type::Bool && r[0].b;
}

bool is_false(const std::vector<Val> &r)
{
    return r.size() >= 1 && r[0].type == Type::Bool && !r[0].b;
}

std::string code_of(const std::vector<Val> &r)
{
    return r.size() >= 3 && r[2].type == Type::String ? r[2].str : std::string();
}

double field_num(const Val &t, const char *k)
{
    Val v = t.tab ? t.tab->field(k) : Val();
    return v.type == Type::Number ? v.num : -1e9;
}

// a rectangle of tiles at height z (host space, z up): the island of tests/core_test.cpp, review_probe's scene
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

// what one cast showed: the first pair of each stage (-1: never)
struct Cast {
    bool ok = true;
    int aim = -1, lure = -1, cut = -1, end = -1;
    int running_pairs = 0, active_pairs = 0;
    double aim_level = -1, aim_adjust = -1, aim_fn = 0, lure_level = -1, lure_adjust = -1, lure_fn = 0;
    double lure_dist_min = 1e9, lure_dist_max = -1;
    double forward_err = 0, fov_min = 1e9, fov_max = -1;
    bool all_finite = true;
    uint64_t tables = 0, calls = 0;
};

// bigfish 2.4's inputs (fish098 2.1): 10 pairs idle, the action held 40 pairs (the stick forward from pair 25), release, 150 idle, L + R 20,
// 40 idle. With the bit: AIM at about pair 23, LURE at 82, the cut at 200, no request at 209 (fish098 6.1 T2)
Cast one_cast(CountingLua &L, double id, double flags)
{
    Cast r;
    Val out = Val::table();
    for (int p = 0; p < 260 && r.ok; p++) {
        const double sy = (p >= 25 && p < 50) ? 1.0 : 0.0;
        const double b = (p >= 10 && p < 50) ? (double)SA1_BUTTON_ACTION : (p >= 200 && p < 220) ? (double)(SA1_BUTTON_L | SA1_BUTTON_R) : 0.0;
        std::vector<Val> t = L.call("Tick", {Val::number(id), Val::number(0), Val::number(sy), Val::number(0), Val::number(b),
                                             Val::number(1.0 / 30.0), Val::boolean(true), Val::number(flags)});
        if (t.empty() || t[0].type != Type::Number) {
            r.ok = false;
            break;
        }
        uint64_t t0 = L.tables;
        std::vector<Val> c = L.call("Camera", {Val::number(id), Val::number(-1), out});
        r.tables += L.tables - t0;
        r.calls++;
        if (!is_true(c)) {
            r.ok = false;
            break;
        }
        const uint32_t fl = (uint32_t)field_num(out, "flags");
        const int kind = (int)field_num(out, "kind");
        if (fl & SA1_CAMSTATE_ACTIVE) {
            r.active_pairs++;
        }
        if (kind == (int)SA1_CAMKIND_AIM && r.aim < 0) {
            r.aim = p;
            r.aim_level = field_num(out, "level");
            r.aim_adjust = field_num(out, "adjust");
            r.aim_fn = field_num(out, "fn");
        }
        if (kind == (int)SA1_CAMKIND_LURE && r.lure < 0) {
            r.lure = p;
            r.lure_level = field_num(out, "level");
            r.lure_adjust = field_num(out, "adjust");
            r.lure_fn = field_num(out, "fn");
        }
        if ((fl & SA1_CAMSTATE_CUT) && r.cut < 0) {
            r.cut = p;
        }
        if (r.lure >= 0 && !(fl & SA1_CAMSTATE_ACTIVE) && r.end < 0) {
            r.end = p;
        }
        if (fl & SA1_CAMSTATE_RUNNING) {
            r.running_pairs++;
            for (const char *f : k_fields) {
                double v = field_num(out, f);
                if (!std::isfinite(v) || v == -1e9) {
                    r.all_finite = false;
                }
            }
            const double fx = field_num(out, "fx"), fy = field_num(out, "fy"), fz = field_num(out, "fz");
            r.forward_err = std::max(r.forward_err, std::fabs(std::sqrt(fx * fx + fy * fy + fz * fz) - 1.0));
            r.fov_min = std::min(r.fov_min, field_num(out, "fov"));
            r.fov_max = std::max(r.fov_max, field_num(out, "fov"));
            if (kind == (int)SA1_CAMKIND_LURE && p >= r.lure + 8 && p < 200) {
                const double dx = field_num(out, "px") - field_num(out, "tx"), dy = field_num(out, "py") - field_num(out, "ty"),
                             dz = field_num(out, "pz") - field_num(out, "tz");
                const double d = std::sqrt(dx * dx + dy * dy + dz * dz);
                r.lure_dist_min = std::min(r.lure_dist_min, d);
                r.lure_dist_max = std::max(r.lure_dist_max, d);
            }
        }
    }
    return r;
}
#endif  // SA1_API_CAMERA

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
    std::printf("G-SA1 feat_gamecam_binding_test\n");
    CountingLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_gamecam_appdata");
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
#if !defined(SA1_API_CAMERA)
    // a snapshot before the contract: no camera in libsa1, so no feature "gamecam"
    CHECK(feats.type == Type::Table && feats.tab->field("gamecam").type == Type::Nil && g.tab->field("Camera").type == Type::Nil &&
              g.tab->field("INPUT_GAME_CAMERA").type == Type::Nil,
          "this libsa1.h has no SA1_API_CAMERA: gsa1.FEATURES.gamecam is absent and nothing of it is registered "
          "(GSA1.HasFeature(\"gamecam\") is false)");
    std::printf("  info  gamecam_api.txt is written only with libsa1's camera API (SA1_API_CAMERA)\n");
#else
    std::vector<std::string> api;
    auto rec = [&](const std::string &line) { api.push_back(line); };

    // THE API PART -------------------------------------------------------------------------------------------------------------------
    CHECK(feats.type == Type::Table && field_num(feats, "gamecam") == 1.0, "gsa1.FEATURES.gamecam == 1");
    rec("feature\tgamecam\t1");
    CHECK(g.tab->field("Camera").type == Type::Function, "gsa1.Camera is registered");
    rec("function\tCamera\tid,alpha,out\ttrue|false,message,code\tbad_argument,not_found,unsupported,not loaded");
    {
        const struct { const char *name; double v; } constants[] = {
            {"INPUT_GAME_CAMERA", SA1_INPUT_GAME_CAMERA}, {"CAMSTATE_ACTIVE", SA1_CAMSTATE_ACTIVE}, {"CAMSTATE_KNOWN", SA1_CAMSTATE_KNOWN},
            {"CAMSTATE_RUNNING", SA1_CAMSTATE_RUNNING}, {"CAMSTATE_CUT", SA1_CAMSTATE_CUT}, {"CAMKIND_NONE", SA1_CAMKIND_NONE},
            {"CAMKIND_AIM", SA1_CAMKIND_AIM}, {"CAMKIND_LURE", SA1_CAMKIND_LURE}, {"CAMKIND_CATCH", SA1_CAMKIND_CATCH},
            {"CAMKIND_OTHER", SA1_CAMKIND_OTHER},
        };
        int bad = 0;
        for (const auto &c : constants) {
            if (field_num(g, c.name) != c.v) {
                bad++;
            }
            rec(gsa1::format("const\t%s\t%.0f", c.name, c.v));
        }
        CHECK(bad == 0, "gsa1.INPUT_GAME_CAMERA, CAMSTATE_*, CAMKIND_* equal libsa1.h's (%d differ)", bad);
    }
    for (const char *f : k_fields) {
        rec(std::string("field\tCamera\t") + f + "\tnumber");
    }
    {
        Val t = Val::table();
        std::vector<Val> a = L.call("Camera", {});
        std::vector<Val> b = L.call("Camera", {Val::number(1)});
        std::vector<Val> c = L.call("Camera", {Val::number(1), Val::number(-1)});
        std::vector<Val> d = L.call("Camera", {Val::string("x"), Val::number(-1), t});
        std::vector<Val> e = L.call("Camera", {Val::number(1), Val::number(std::nan("")), t});
        std::vector<Val> f = L.call("Camera", {Val::number(1), Val::number(-1), Val::number(3)});
        CHECK(is_false(a) && code_of(a) == "bad_argument" && is_false(b) && code_of(b) == "bad_argument" && is_false(c) &&
                  code_of(c) == "bad_argument" && is_false(d) && code_of(d) == "bad_argument" && is_false(e) && code_of(e) == "bad_argument" &&
                  is_false(f) && code_of(f) == "bad_argument",
              "Camera's arguments are checked: false, a message, \"bad_argument\"");
        std::vector<Val> u = L.call("Camera", {Val::number(999), Val::number(-1), t});
        CHECK(is_false(u) && code_of(u) == "not_found" && t.tab->s.empty(), "an unknown id: false, \"not_found\", the table untouched");
    }

    std::string behaviour = "SKIP\tno disc";
    auto write_api = [&]() {
        std::string path = gsa1::join_path(self.empty() ? "." : self, "gamecam_api.txt");
        std::string text = "# G-SA1 gamecam_api.txt: the module contract of round 0.9.8 (sadc docs/research/gsa1_098_plan.md 5.5)\n";
        for (const std::string &l : api) {
            text += l + "\n";
        }
        text += "behaviour\t" + behaviour + "\n";
        std::FILE *f = std::fopen(path.c_str(), "wb");
        bool ok = f && std::fwrite(text.data(), 1, text.size(), f) == text.size();
        if (f) std::fclose(f);
        CHECK(ok, "gamecam_api.txt written: %s (%zu records)", path.c_str(), api.size() + 1);
    };

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: a real cast needs the disc\n");
        write_api();
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    gsa1::make_dirs(fake_appdata);
    gsa1::Config cfg;
    cfg.disc = gdi;
    std::string err;
    CHECK(gsa1::save_config(cfg, err), "config written to the scratch APPDATA (%s)", err.c_str());
    L.call("Init", {});
    std::string ist = "loading";
    for (int polls = 0; ist == "loading" && polls < 30000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        std::vector<Val> r = L.call("InitPoll", {});
        ist = r.size() >= 1 && r[0].type == Type::String ? r[0].str : std::string();
    }
    CHECK(ist == "ready", "the disc: %s", ist.c_str());
    std::string map;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
        std::printf("  info  no gm_construct (%s): the play part is skipped\n", bsp.c_str());
        behaviour = "SKIP\tno gm_construct";
        write_api();
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct) (Create needs a world)");
    gsa1::Session *se = gsa1::mod::session();
    // the island: 600 x 600 HU at z 0, water at z -20 around it, a sea bed at -600 (review_probe's scene; tests/core_test.cpp G1)
    std::vector<sa1_collision_tri> isl;
    rect(isl, -300, -300, 300, 300, 0, 300, SA1_SURFACE_SOLID);
    rect(isl, -6000, -6000, 6000, -300, -20, 1000, SA1_SURFACE_WATER);
    rect(isl, -6000, 300, 6000, 6000, -20, 1000, SA1_SURFACE_WATER);
    rect(isl, -6000, -300, -300, 300, -20, 600, SA1_SURFACE_WATER);
    rect(isl, 300, -300, 6000, 300, -20, 600, SA1_SURFACE_WATER);
    rect(isl, -6000, -6000, 6000, 6000, -600, 1000, SA1_SURFACE_SOLID);
    CHECK(se && se->set_world(isl, err), "the island as the static collision (%s)", err.c_str());
    auto create_big = [&]() {
        std::vector<Val> r = L.call("Create", {Val::number(SA1_CHAR_BIG), Val::vector(0.0f, 0.0f, 8.0f), Val::number(0)});
        return num_of(r, 0);
    };
    double id = create_big();
    CHECK(id > 0, "Big on the island");
    // (one neutral pair first: libsa1 answers "not loaded" for a character whose world is not there yet)
    L.call("Tick", {Val::number(id), Val::number(0), Val::number(0), Val::number(0), Val::number(0), Val::number(1.0 / 30.0), Val::boolean(true), Val::number(0)});
    Val probe = Val::table();
    std::vector<Val> first = L.call("Camera", {Val::number(id), Val::number(-1), probe});
    if (is_false(first) && code_of(first) == "unsupported") {
        // exactly this one line while libsa1's gate is closed (5.3): the final gate fails on it
        std::printf("SKIP behaviour: gamecam is not built yet\n");
        behaviour = "SKIP\tgamecam is not built yet";
        L.call("Destroy", {Val::number(id)});
        write_api();
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }

    // THE BEHAVIOUR PART -------------------------------------------------------------------------------------------------------------
    behaviour = "RAN\tAIM, LURE, CUT, the end; without the bit never RUNNING";
    CHECK(is_true(first) && field_num(probe, "kind") == SA1_CAMKIND_NONE && field_num(probe, "level") == 0.0 && probe.tab->s.size() == 15,
          "a new Big: gsa1.Camera fills the table's 15 fields: no request, kind NONE, level 0");
    Cast w = one_cast(L, id, (double)SA1_INPUT_GAME_CAMERA);
    CHECK(w.ok, "a whole cast with the bit, 260 pairs");
    CHECK(w.aim >= 15 && w.aim <= 40 && w.aim_level == 2.0 && w.aim_adjust == 3.0 && w.aim_fn == (double)0x8C0239C2u,
          "AIM from pair %d: level %.0f, adjust %.0f (SLOW), function %08X", w.aim, w.aim_level, w.aim_adjust, (unsigned)w.aim_fn);
    CHECK(w.lure > w.aim && w.lure <= 140 && w.lure_level == 4.0 && w.lure_adjust == 0.0 && w.lure_fn == (double)0x8C0EAF28u,
          "then LURE from pair %d, the lure in the water: level %.0f, adjust %.0f, function %08X", w.lure, w.lure_level, w.lure_adjust,
          (unsigned)w.lure_fn);
    CHECK(w.lure_dist_min >= 40.0 && w.lure_dist_max <= 120.0, "the lure camera stays near the lure: %.1f .. %.1f HU", w.lure_dist_min, w.lure_dist_max);
    CHECK(w.cut >= 200 && w.cut <= 212, "L + R (from pair 200): a CUT at pair %d", w.cut);
    CHECK(w.end > w.cut && w.end <= 225, "then no request from pair %d", w.end);
    CHECK(w.running_pairs >= 100 && w.all_finite && w.forward_err < 1e-3 && std::fabs(w.fov_min - 1.2217) < 0.01 && std::fabs(w.fov_max - 1.2217) < 0.01,
          "RUNNING for %d pairs: every field finite, forward a unit vector (off by at most %.1e), fov %.4f rad (70 degrees)", w.running_pairs, w.forward_err,
          w.fov_min);
    CHECK(w.calls == 260 && w.tables == 0, "%llu calls of gsa1.Camera with `out` made %llu tables", (unsigned long long)w.calls, (unsigned long long)w.tables);
    L.call("Destroy", {Val::number(id)});

    id = create_big();
    Cast n = one_cast(L, id, 0.0);
    CHECK(n.ok && n.running_pairs == 0 && n.aim >= 0 && n.lure > n.aim && n.active_pairs > 0,
          "the same cast without the bit: reported (AIM from pair %d, LURE from pair %d), RUNNING in none of them", n.aim, n.lure);
    L.call("Destroy", {Val::number(id)});

    // a Sonic: nothing known ever runs, with the bit
    {
        std::vector<Val> r = L.call("Create", {Val::number(SA1_CHAR_SONIC), Val::vector(0.0f, 0.0f, 8.0f), Val::number(0)});
        double sid = num_of(r, 0);
        Val out = Val::table();
        int running = 0;
        for (int p = 0; p < 60; p++) {
            L.call("Tick", {Val::number(sid), Val::number(0), Val::number(p > 10 ? 1 : 0), Val::number(0), Val::number(0), Val::number(1.0 / 30.0),
                            Val::boolean(true), Val::number((double)SA1_INPUT_GAME_CAMERA)});
            L.call("Camera", {Val::number(sid), Val::number(-1), out});
            if ((uint32_t)field_num(out, "flags") & SA1_CAMSTATE_RUNNING) {
                running++;
            }
        }
        CHECK(sid > 0 && running == 0, "Sonic with the bit: nothing runs (%d pairs)", running);
        L.call("Destroy", {Val::number(sid)});
    }
    write_api();
#endif  // SA1_API_CAMERA
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
