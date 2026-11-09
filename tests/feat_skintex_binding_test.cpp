// feat_skintex_binding_test: the skins' textures through the module's REAL Lua functions in Garry's Mod's own LuaJIT (1.0.0-beta1a, lane b1a-tex).
//
//   feat_skintex_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp] [--module gmcl_gsa1_win64.dll]
//
// --module: a built G-SA1 module of this project in place of the linked one (by hand, the negative control: build/release_1.0.0-beta1's copy fails every
// skin texture with its usage line, as in the owner's log). build.py --test runs the linked module.
//
// THE OWNER, on beta 1 in the game: "Metal Sonic and Mecha Sonic are PURE WHITE". THE ROOT CAUSE, MEASURED in the owner's log: libsa1 1.0.0-beta1 draws a skin's
// parts from archive SA1_ARCHIVE_SKIN_FIRST + the skin's slot (64 for the first skin loaded, 65 for the second), and the module's gsa1.Texture (and TextureCount,
// TexturePixel, the Frontend* texture calls) refused every archive above 63 with its usage line: "msg texture 2 of archive 64 of character 0: Texture(kind,
// index [, archive [, variant]])" for each of the 9 textures of archive 64 and the 22 of archive 65, then "material gsa1m_white_..." for every batch of them.
// Beta 1's tests never saw it: tests/lua_mock.lua's gsa1.Texture takes any archive, and feat_skins_binding_test asked gsa1.Texture(0, 6, 61) (61 answers the
// first skin for this version only) while it counted the batches' archives 64 .. 79 as "textured".
// THIS TEST loads Garry's Mod's bin/win64/lua_shared.dll read-only (as tests/lua_host.c does; GMOD_LUA_SHARED overrides the path), opens the module in a real
// LuaJIT state through tests/luajit_base.hpp (gmod13_open: the module's own gsa1 table) and runs tests/feat_skintex_real.lua there. With the disc, that script:
//   * makes Sonic wearing Metal Sonic and Sonic wearing Mecha Sonic (feat/sh_skins.lua's own entries, K.DescOf), and a follower wearing each; for each,
//     gsa1.SkinArchive, gsa1.TextureCount and gsa1.Texture for EVERY texture index of its archive (each returns runs), gsa1.TexturePixel at each first run,
//     and every textured batch's own (archive, texture) through gsa1.Texture;
//   * Character Select: gsa1.FrontendSkin with each skin, the circle's batches (FrontendRender / FrontendBatches) and their textures through gsa1.Texture
//     with the holder's kind, the menu's own archives through FrontendTextureArchives / FrontendTextureCount / FrontendTexture / FrontendTexturePixel;
//   * the range is libsa1's: archive SA1_ARCHIVE_SKIN_LAST + 1 is refused by the binding, an unloaded skin archive inside the range is answered by libsa1.
//   * the ADDON'S OWN cl_textures.lua on those real answers (Character Select's circle wearing Metal Sonic, Mecha Sonic in play): its two self-check lines per
//     skin ("the module gives 9 of 9 ...", then "9 of 9 made (painted; read back ...)"), its painter on tests/lua_mock_rt.lua's render-target pixel model,
//     every texel of the skins' render targets against gsa1.TexturePixel, no skin batch material on vgui/white.
// What only the game shows: Garry's Mod's own render targets painted from those runs and the materials drawn with them, on screen.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "GarrysMod/Lua/Interface.h"
#include "../src/core/config.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"
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

// a flat SOLID floor under the characters (Create needs a world; the textures do not care where they stand)
int host_flat_floor(State *J)
{
    gsa1::Session *se = gsa1::mod::session();
    std::string err;
    bool ok = se && se->set_world(flat_floor(4096.0f), err);
    lb().a.lua_pushboolean(J, ok ? 1 : 0);
    lb().a.lua_pushstring(J, err.c_str());
    return 2;
}
#endif

}  // namespace

int main(int argc, char **argv)
{
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_skintex_binding_test\n");
    std::string gdi, bsp = gsa1_garrysmod_dir()[0] ? std::string(gsa1_garrysmod_dir()) + "\\maps\\gm_construct.bsp" : std::string();
    std::string module_dll;     // --module DLL: a BUILT G-SA1 module of this project instead of the linked one (the negative control: beta 1's frozen copy)
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
        else if (std::string(argv[i]) == "--bsp") bsp = argv[++i];
        else if (std::string(argv[i]) == "--module") module_dll = argv[++i];
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
    std::string script = gsa1::join_path(gsa1::join_path(root, "tests"), "feat_skintex_real.lua");
    std::string addon_gsa1 = gsa1::join_path(gsa1::join_path(gsa1::join_path(root, "addon"), "lua"), "gsa1");
    std::string skins = gsa1::join_path(gsa1::join_path(addon_gsa1, "feat"), "sh_skins.lua");
    // (section 5 of the script: the addon's own cl_textures.lua on the module's answers, painting on tests/lua_mock_rt.lua's render-target pixel model)
    std::string textures = gsa1::join_path(addon_gsa1, "cl_textures.lua");
    std::string model = gsa1::join_path(gsa1::join_path(root, "tests"), "lua_mock_rt.lua");
    check(gsa1::file_exists(script) && gsa1::file_exists(skins) && gsa1::file_exists(textures) && gsa1::file_exists(model),
          "the script, the addon's feat/sh_skins.lua and cl_textures.lua, tests/lua_mock_rt.lua: " + script + ", " + skins + ", " + textures + ", " + model);

    // the module's config in a scratch APPDATA (as every binding test)
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_skintex_appdata");
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
    base.global_fn("host_flat_floor", host_flat_floor);
    luajit::Api &a = base.a;
    State *J = base.main;
    a.lua_createtable(J, 0, 6);
    a.lua_pushstring(J, gdi.c_str());
    a.lua_setfield(J, -2, "gdi");
    a.lua_pushstring(J, bsp.c_str());
    a.lua_setfield(J, -2, "bsp");
    a.lua_pushstring(J, skins.c_str());
    a.lua_setfield(J, -2, "skins");
    a.lua_pushstring(J, textures.c_str());
    a.lua_setfield(J, -2, "textures");
    a.lua_pushstring(J, model.c_str());
    a.lua_setfield(J, -2, "model");
    a.lua_setfield(J, luajit::kGlobals, "SKINTEX");

    int (*open_fn)(lua_State *) = gmod13_open;
    int (*close_fn)(lua_State *) = gmod13_close;
    if (!module_dll.empty()) {
        // (the floor is the linked module's: host_flat_floor answers false; the textures do not need it)
        HMODULE m = LoadLibraryW(gsa1::widen(module_dll).c_str());
        *(FARPROC *)&open_fn = m ? GetProcAddress(m, "gmod13_open") : nullptr;
        *(FARPROC *)&close_fn = m ? GetProcAddress(m, "gmod13_close") : nullptr;
        std::printf("  info  the module under test: %s (not the linked one)\n", module_dll.c_str());
        if (!open_fn || !close_fn) {
            check(false, "load " + module_dll);
            return finish();
        }
    }
    int rc = base.call_module(open_fn);
    a.lua_getfield(J, luajit::kGlobals, "gsa1");
    bool has_gsa1 = a.lua_type(J, -1) == 5;
    a.lua_settop(J, 0);
    check(rc == 0 && has_gsa1, "gmod13_open in Garry's Mod's LuaJIT: the module's gsa1 table is a real Lua table");

    std::string src;
    if (!gsa1::read_small_file(script, 4u << 20, src, err)) {
        check(false, "read " + script + " (" + err + ")");
    } else if (a.luaL_loadbuffer(J, src.data(), src.size(), "@feat_skintex_real.lua") != 0 || a.lua_pcall(J, 0, 2, 0) != 0) {
        size_t n = 0;
        const char *m = a.lua_tolstring(J, -1, &n);
        check(false, std::string("the script ran: ") + (m ? std::string(m, n) : "?"));
    } else {
        int lc = (int)a.lua_tonumber(J, -2), lf = (int)a.lua_tonumber(J, -1);
        g_checks += lc;
        g_fail += lf;
        std::printf("  info  the script: %d checks, %d failed; %llu calls of the module's functions through LuaJIT\n", lc, lf, (unsigned long long)base.calls);
        check(lc > 0, "the script made its checks");
    }
    a.lua_settop(J, 0);
    base.call_module(close_fn);
    base.close();
    return finish();
#endif
}
