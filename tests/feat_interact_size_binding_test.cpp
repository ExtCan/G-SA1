// feat_interact_size_binding_test: the characters' sizes the addon keeps for the server (addon/lua/gsa1/feat/sh_interact.lua
// GSA1.CHAR_SIZE; sadc docs/research/gsa1_090_player.md L1 with its review, round 0.9.2) against what the module reads from
// the disc (gsa1.CharacterInfo: the game's physics table, sa1_physics_get rad / height / eyes_height / center_height x the
// Source scale). build.py links it like binding_test - the module's objects and the mock Lua stack of tests/mock_lua.hpp -
// and runs it with --gdi GAME.gdi when there is one.
//
//   feat_interact_size_binding_test [--gdi GAME.gdi] [--verbose]
//
// Without the disc: the table parses (six kinds, radius / height / eyes / center each) and the module answers
// CharacterInfo with "not ready" (no Lua error). With the disc: every kind of the table equals CharacterInfo(kind) within
// 0.05 Hammer units in each of the four sizes.
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <thread>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../src/core/config.hpp"
#include "../src/core/util.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

#include "mock_lua.hpp"
#include "../src/module/gsa1_module_internal.hpp"

static bool g_verbose = false;

struct Size {
    double radius = -1, height = -1, eyes = -1, center = -1;
};

// the addon's GSA1.CHAR_SIZE: "[kind] = { radius = R, height = H, eyes = E, center = C }," lines between
// "GSA1.CHAR_SIZE = {" and the closing "}"
static std::map<int, Size> addon_sizes(const std::string &path)
{
    std::map<int, Size> out;
    std::string text, err;
    if (!gsa1::read_small_file(path, 1u << 20, text, err)) {
        return out;
    }
    size_t a = text.find("GSA1.CHAR_SIZE = {");
    size_t b = a == std::string::npos ? a : text.find("\n}", a);
    if (a == std::string::npos || b == std::string::npos) {
        return out;
    }
    std::string body = text.substr(a, b - a);
    size_t pos = 0;
    while ((pos = body.find('[', pos)) != std::string::npos) {
        int kind = -1;
        Size s;
        if (std::sscanf(body.c_str() + pos, "[%d] = { radius = %lf, height = %lf, eyes = %lf, center = %lf }", &kind,
                        &s.radius, &s.height, &s.eyes, &s.center) == 5) {
            out[kind] = s;
        }
        pos++;
    }
    return out;
}

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--gdi" && i + 1 < argc) gdi = argv[++i];
        else if (a == "--verbose") g_verbose = true;
    }
    std::printf("G-SA1 feat_interact_size_binding_test\n");
    // the source tree: this file's own directory's parent (build.py compiles it by its absolute path)
    std::string root = gsa1::parent_dir(gsa1::parent_dir(__FILE__));
    std::string addon = gsa1::join_path(gsa1::join_path(gsa1::join_path(gsa1::join_path(root, "addon"), "lua"), "gsa1"),
                                        gsa1::join_path("feat", "sh_interact.lua"));
    std::map<int, Size> table = addon_sizes(addon);
    static const int kKinds[] = {0, 2, 3, 5, 6, 7};
    int rows = 0;
    for (int k : kKinds) {
        auto it = table.find(k);
        rows += it != table.end() && it->second.radius > 0 && it->second.height > 0 && it->second.eyes > 0 &&
                it->second.center > 0;
    }
    CHECK(rows == 6 && table.size() == 6, "GSA1.CHAR_SIZE in sh_interact.lua: %d of the six kinds (0 2 3 5 6 7) with "
          "radius, height, eyes and center (%d rows)", rows, (int)table.size());

    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_interact_size_appdata");
#ifdef _WIN32
    char full[4096];
    GetFullPathNameA(fake_appdata.c_str(), sizeof full, full, nullptr);
    fake_appdata = full;
    SetEnvironmentVariableW(L"APPDATA", gsa1::widen(fake_appdata).c_str());
#else
    setenv("XDG_CONFIG_HOME", fake_appdata.c_str(), 1);
#endif
    gmod13_open(&state);
    auto nr = L.call("CharacterInfo", {Val::number(0)});
    CHECK(nr.size() >= 1 && nr[0].type == Type::Nil && L.st.empty(),
          "before the disc CharacterInfo(0) answers nil + a message, no Lua error (%s)", str_of(nr, 1).c_str());
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the comparison with the disc needs it\n");
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    std::string err;
    gsa1::make_dirs(fake_appdata);
    gsa1::Config cfg;
    cfg.disc = gdi;
    CHECK(gsa1::save_config(cfg, err), "config written to the scratch APPDATA (%s)", err.c_str());
    L.call("Init", {});
    std::string st = "loading";
    for (int polls = 0; st == "loading" && polls < 60000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        st = str_of(L.call("InitPoll", {}), 0);
    }
    CHECK(st == "ready", "the disc loaded (%s)", st.c_str());
    if (st != "ready") {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    int same = 0;
    std::string diff;
    for (int k : kKinds) {
        auto r = L.call("CharacterInfo", {Val::number(k)});
        Size disc;
        if (r.size() >= 1 && r[0].type == Type::Table) {
            disc.radius = r[0].tab->field("radius").num;
            disc.height = r[0].tab->field("height").num;
            disc.eyes = r[0].tab->field("eyes").num;
            disc.center = r[0].tab->field("center").num;
        }
        const Size &a = table[k];
        bool ok = std::fabs(a.radius - disc.radius) <= 0.05 && std::fabs(a.height - disc.height) <= 0.05 &&
                  std::fabs(a.eyes - disc.eyes) <= 0.05 && std::fabs(a.center - disc.center) <= 0.05;
        same += ok;
        char line[256];
        std::snprintf(line, sizeof line, " kind %d: disc %.2f / %.2f / %.2f / %.2f, table %.2f / %.2f / %.2f / %.2f%s;", k,
                      disc.radius, disc.height, disc.eyes, disc.center, a.radius, a.height, a.eyes, a.center,
                      ok ? "" : " DIFFERS");
        diff += line;
        if (g_verbose) std::printf("  info %s\n", line);
    }
    CHECK(same == 6, "GSA1.CHAR_SIZE = gsa1.CharacterInfo(kind) within 0.05 units (radius / height / eyes / center) for "
          "%d of 6 kinds:%s", same, diff.c_str());
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
