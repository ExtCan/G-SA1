// feat_skinhud_binding_test: the skins' names and nameplates on Character Select through the module's REAL Lua functions in Garry's Mod's own LuaJIT (the names fix after 1.0.0-beta1a,
// sadc/build/research/b1a2).
//
//   feat_skinhud_binding_test [--gdi GAME.gdi] [--module gmcl_gsa1_win64.dll] [--lua ADDON_LUA_DIR]
//
// --module and --lua: a built G-SA1 module and an addon/lua folder of this project in place of the linked module and the working tree's (by hand, THE NEGATIVE CONTROL: with
// build/release_1.0.0-beta1a's dll and addon/lua this test FAILS the way the owner's game did: the picture's texels turned black, nothing noticed it, black to the end). build.py --test runs the
// linked module on the working tree's addon.
//
// THE OWNER, on beta 1a in the game (2026-11-09): "The pulsating names appear for a second and then turn into black squares". Beta 1a made each skin's name and plate in a render target of its own
// (feat/cl_text.lua T.Canvas) and never read it again: the trace lane MEASURED that a canvas filled with Source's opaque black creation colour draws a letterless pulsing black box for good, silently.
// THIS TEST loads Garry's Mod's bin/win64/lua_shared.dll read-only (as tests/lua_host.c does; GMOD_LUA_SHARED overrides the path), opens the module in a real LuaJIT state through
// tests/luajit_base.hpp (gmod13_open: the module's own gsa1 table) and runs tests/feat_skinhud_real.lua there: the addon's whole client Lua through its own autorun on tests/lua_mock.lua and
// tests/lua_mock_rt.lua at 3440 x 1440, Character Select opened from the disc through the real gsa1.Frontend* calls, Up to Metal Sonic, Mecha Sonic, Sonic, Metal Sonic again (the owner's keys), and
// a negative control: the name's picture filled with opaque black on the second visit. With the disc only (--gdi or SA1_TEST_GDI); without it the script says so and checks nothing.
// b1a2-fix2: the self-check never captures a page (each read is one capture of the 16 x 4 target the texels are drawn into through the page's material), what one such read costs on the Lua side
// here, and the canary's rule (a copy that reads colours at 3/4: the page's canary said once and compared with its make's read, nothing made again).
// What only the game shows: what Garry's Mod's engine does to a render target in the owner's session (the log's "skin pictures check" lines), and the screen itself.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <chrono>
#include <vector>
#include <algorithm>

#include "GarrysMod/Lua/Interface.h"
#include "../src/core/config.hpp"
#include "../src/core/util.hpp"
#include "gmod_paths.hpp"
#include "luajit_base.hpp"

extern "C" int gmod13_open(lua_State *L);
extern "C" int gmod13_close(lua_State *L);

namespace {

int g_checks = 0, g_fail = 0;

[[maybe_unused]] void check(bool ok, const std::string &what)
{
    g_checks++;
    if (!ok) {
        g_fail++;
    }
    std::printf("  %s  %s\n", ok ? "ok  " : "FAIL", what.c_str());
}

int finish()
{
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}

#ifdef _WIN32
using luajit::LuajitBase;
using luajit::State;

LuajitBase &lb() { return *LuajitBase::self(); }

// the script's helpers (raw C functions of the test, not the module's)
int host_write(State *J)
{
    size_t n = 0;
    const char *s = lb().a.lua_tolstring(J, 1, &n);
    if (s) {
        std::fwrite(s, 1, n, stdout);
    }
    std::fflush(stdout);
    return 0;
}

int host_read(State *J)
{
    size_t n = 0;
    const char *p = lb().a.lua_tolstring(J, 1, &n);
    std::string data, err;
    if (!p || !gsa1::read_small_file(std::string(p, n), 512u << 20, data, err)) {
        lb().a.lua_pushnil(J);
        return 1;
    }
    lb().a.lua_pushlstring(J, data.data(), data.size());
    return 1;
}

int host_load(State *J)
{
    size_t n = 0;
    const char *src = lb().a.lua_tolstring(J, 1, &n);
    const char *name = lb().a.lua_tolstring(J, 2, nullptr);
    if (!src) {
        lb().a.lua_pushnil(J);
        return 1;
    }
    if (lb().a.luaL_loadbuffer(J, src, n, name ? name : "chunk") != 0) {
        lb().a.lua_pushnil(J);
        lb().a.lua_insert(J, -2);
        return 2;
    }
    return 1;
}

int host_sleep(State *J)
{
    double ms = lb().a.lua_tonumber(J, 1);
    std::this_thread::sleep_for(std::chrono::microseconds((long long)(ms * 1000.0)));
    return 0;
}

// host_list(dir, pattern) -> { file names } (the files - not folders - of dir matching pattern, sorted), as tests/lua_host.c's: the addon's autorun lists its feature files with it
int host_list(State *J)
{
    size_t n = 0;
    const char *d = lb().a.lua_tolstring(J, 1, &n);
    const char *pat = lb().a.lua_tolstring(J, 2, nullptr);
    std::vector<std::string> names;
    if (d) {
        std::string path = std::string(d, n) + "\\" + (pat ? pat : "*");
        for (char &ch : path) {
            if (ch == '/') ch = '\\';
        }
        WIN32_FIND_DATAA fd;
        HANDLE h = FindFirstFileA(path.c_str(), &fd);
        if (h != INVALID_HANDLE_VALUE) {
            do {
                if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) names.push_back(fd.cFileName);
            } while (FindNextFileA(h, &fd));
            FindClose(h);
        }
    }
    std::sort(names.begin(), names.end());
    lb().a.lua_createtable(J, (int)names.size(), 0);
    for (size_t i = 0; i < names.size(); i++) {
        lb().a.lua_pushstring(J, names[i].c_str());
        lb().a.lua_rawseti(J, -2, (int)i + 1);
    }
    return 1;
}
#endif

}  // namespace

int main(int argc, char **argv)
{
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_skinhud_binding_test\n");
    std::string gdi, module_dll, lua_dir;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
        else if (std::string(argv[i]) == "--module") module_dll = argv[++i];
        else if (std::string(argv[i]) == "--lua") lua_dir = argv[++i];
    }
#ifndef _WIN32
    std::printf("  info  Garry's Mod's lua_shared.dll is a Windows DLL: this test runs on Windows\n");
    return finish();
#else
    std::string dll;
    if (const char *e = std::getenv("GMOD_LUA_SHARED")) dll = e;
    char buf[1100];
    if (dll.empty() && gsa1_garrysmod_rel(buf, sizeof buf, 1, "bin\\win64\\lua_shared.dll")) dll = buf;
    if (dll.empty() || !gsa1::file_exists(dll)) {
        std::printf("SKIP the real binding: Garry's Mod's lua_shared.dll is not here (%s): set GMOD_LUA_SHARED or GARRYSMOD_DIR\n", dll.c_str());
        return finish();
    }
    // where the sources are: <g-sa1>/build/<target>/this.exe
    std::string self = gsa1::parent_dir(argv[0]);
    std::string root = gsa1::parent_dir(gsa1::parent_dir(self.empty() ? std::string(".") : self));
    char full[4096];
    if (GetFullPathNameA(root.empty() ? "." : root.c_str(), sizeof full, full, nullptr)) root = full;
    std::string tests = gsa1::join_path(root, "tests");
    std::string script = gsa1::join_path(tests, "feat_skinhud_real.lua");
    if (lua_dir.empty()) lua_dir = gsa1::join_path(gsa1::join_path(root, "addon"), "lua");
    if (GetFullPathNameA(lua_dir.c_str(), sizeof full, full, nullptr)) lua_dir = full;
    check(gsa1::file_exists(script) && gsa1::file_exists(gsa1::join_path(tests, "lua_mock.lua")) && gsa1::file_exists(gsa1::join_path(tests, "lua_mock_rt.lua")) &&
              gsa1::file_exists(gsa1::join_path(gsa1::join_path(lua_dir, "autorun"), "gsa1_autorun.lua")),
          "the script, tests/lua_mock.lua, tests/lua_mock_rt.lua and the addon's autorun: " + script + ", " + lua_dir);

    // the module's config in a scratch APPDATA (as every binding test)
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_skinhud_appdata");
    GetFullPathNameA(fake_appdata.c_str(), sizeof full, full, nullptr);
    fake_appdata = full;
    SetEnvironmentVariableW(L"APPDATA", gsa1::widen(fake_appdata).c_str());
    std::string err;
    if (!gdi.empty()) {
        gsa1::make_dirs(fake_appdata);
        gsa1::Config cfg;
        cfg.disc = gdi;
        check(gsa1::save_config(cfg, err), "the config in the scratch APPDATA (" + err + ")");
    }

    static LuajitBase base;
    bool loaded = base.load(dll, err);
    check(loaded, "Garry's Mod's LuaJIT, loaded read-only: " + dll + (loaded ? "" : " (" + err + ")"));
    if (!loaded || !base.open()) {
        check(false, "a LuaJIT state");
        return finish();
    }
    base.global_fn("host_write", host_write);
    base.global_fn("host_read", host_read);
    base.global_fn("host_load", host_load);
    base.global_fn("host_sleep", host_sleep);
    base.global_fn("host_list", host_list);
    luajit::Api &a = base.a;
    State *J = base.main;
    a.lua_createtable(J, 0, 4);
    a.lua_pushstring(J, gdi.c_str());
    a.lua_setfield(J, -2, "gdi");
    a.lua_pushstring(J, tests.c_str());
    a.lua_setfield(J, -2, "tests");
    a.lua_pushstring(J, lua_dir.c_str());
    a.lua_setfield(J, -2, "lua");
    a.lua_pushstring(J, module_dll.c_str());
    a.lua_setfield(J, -2, "module");
    a.lua_setfield(J, luajit::kGlobals, "SKINHUD");

    int (*open_fn)(lua_State *) = gmod13_open;
    int (*close_fn)(lua_State *) = gmod13_close;
    if (!module_dll.empty()) {
        HMODULE m = LoadLibraryW(gsa1::widen(module_dll).c_str());
        *(FARPROC *)&open_fn = m ? GetProcAddress(m, "gmod13_open") : nullptr;
        *(FARPROC *)&close_fn = m ? GetProcAddress(m, "gmod13_close") : nullptr;
        std::printf("  info  the module under test: %s (not the linked one)\n", module_dll.c_str());
        if (!open_fn || !close_fn) {
            check(false, "load " + module_dll);
            return finish();
        }
    }
    if (lua_dir != gsa1::join_path(gsa1::join_path(root, "addon"), "lua")) std::printf("  info  the addon under test: %s\n", lua_dir.c_str());
    int rc = base.call_module(open_fn);
    a.lua_getfield(J, luajit::kGlobals, "gsa1");
    bool has_gsa1 = a.lua_type(J, -1) == 5;
    a.lua_settop(J, 0);
    check(rc == 0 && has_gsa1, "gmod13_open in Garry's Mod's LuaJIT: the module's gsa1 table is a real Lua table");

    std::string src;
    if (!gsa1::read_small_file(script, 4u << 20, src, err)) {
        check(false, "read " + script + " (" + err + ")");
    } else if (a.luaL_loadbuffer(J, src.data(), src.size(), "@feat_skinhud_real.lua") != 0 || a.lua_pcall(J, 0, 2, 0) != 0) {
        size_t n = 0;
        const char *m = a.lua_tolstring(J, -1, &n);
        check(false, std::string("the script ran: ") + (m ? std::string(m, n) : "?"));
    } else {
        int lc = (int)a.lua_tonumber(J, -2), lf = (int)a.lua_tonumber(J, -1);
        g_checks += lc;
        g_fail += lf;
        std::printf("  info  the script: %d checks, %d failed; %llu calls of the module's functions through LuaJIT\n", lc, lf, (unsigned long long)base.calls);
        check(lc > 0 || gdi.empty(), "the script made its checks (or there is no disc)");
    }
    a.lua_settop(J, 0);
    base.call_module(close_fn);
    base.close();
    return finish();
#endif
}
