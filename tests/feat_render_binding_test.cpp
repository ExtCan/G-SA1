// feat_render_binding_test: the render feature's binding test (0.8; src/module/bind_render.cpp, gsa1.PrepareView's
// origin, gsa1.DRAW_SHADOW). Linked like binding_test (the module's objects, libsa1, the mock Lua stack of
// tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi when one is given.
//
//   feat_render_binding_test [--gdi GAME.gdi]
//
// Without the disc: gsa1.FEATURES.render = 1, gsa1.DrawList registered, gsa1.DRAW_SHADOW = 0x800; DrawList's bad
// arguments come back as nil + message (no Lua error).
// With the disc (Sonic standing on a floor at the owner's gm_bigcity coordinates, set through the module's session):
// Render + Batches give a pass-1 batch flagged DRAW_SHADOW whose address mode has the mask bit (8); PrepareView with the
// drawn root as origin makes EmitBatch write every vertex within a few hundred HU of 0 (without it: absolute, about
// 11000) and the shadow's colours (204, 204, 204, 255) with gsa1_vertexcolor 0; GetState says shadow_draws 1 and
// relative; DrawList lists every draw - the shadow with texture "shadow" of archive "OBJ_REGULAR", its batch and pass 1 -
// with the alpha range of its colours.
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

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::printf("G-SA1 feat_render_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    // a private configuration directory (the module reads the disc's path from it)
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_render_appdata");
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
    Val feats = g.type == Type::Table ? g.tab->field("FEATURES") : Val();
    CHECK(g.type == Type::Table && feats.type == Type::Table && feats.tab->field("render").num == 1 &&
              g.tab->field("DrawList").type == Type::Function && g.tab->field("DRAW_SHADOW").num == 0x800 && L.st.empty(),
          "gsa1.FEATURES.render = %g, gsa1.DrawList registered, gsa1.DRAW_SHADOW = 0x%X",
          feats.type == Type::Table ? feats.tab->field("render").num : -1.0,
          g.type == Type::Table ? (unsigned)g.tab->field("DRAW_SHADOW").num : 0u);
    if (g.type != Type::Table) return 1;
    int bad = 0;
    bad += is_nil_msg(L.call("DrawList", {}));
    bad += is_nil_msg(L.call("DrawList", {Val::number(1)}));
    bad += is_nil_msg(L.call("DrawList", {Val::number(77), Val::table()}));
    bad += is_nil_msg(L.call("DrawList", {Val::string("1"), Val::table()}));
    CHECK(bad == 4 && L.st.empty(), "DrawList's bad arguments (none, no table, no such character, a string id): %d of 4 "
          "answered with nil + message, no Lua error", bad);

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the shadow and origin checks need the disc\n");
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
    std::string st = "loading";
    for (int polls = 0; st == "loading" && polls < 30000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        st = str_of(L.call("InitPoll", {}), 0);
    }
    gsa1::Session *se = gsa1::mod::session();
    const float X = 5400.0f, Y = 9000.0f, Z = -11136.0f;
    std::vector<sa1_collision_tri> floor;
    for (int i = -2; i < 2; i++) {
        for (int j = -2; j < 2; j++) {
            float x0 = X + 512.0f * i, y0 = Y + 512.0f * j, x1 = x0 + 512.0f, y1 = y0 + 512.0f;
            sa1_collision_tri a = {{{x0, y0, Z}, {x1, y0, Z}, {x1, y1, Z}}, SA1_SURFACE_SOLID};
            sa1_collision_tri b = {{{x0, y0, Z}, {x1, y1, Z}, {x0, y1, Z}}, SA1_SURFACE_SOLID};
            floor.push_back(a);
            floor.push_back(b);
        }
    }
    bool world = st == "ready" && se && se->set_world(floor, err);
    CHECK(world, "the disc (%s) and a floor at (%.0f, %.0f, %.0f) through the module's session%s%s", st.c_str(), X, Y, Z,
          err.empty() ? "" : ": ", err.c_str());
    if (!world) {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    install_mesh_library(L);
    // created through the session (gsa1.Create also wants a world loaded through gsa1.WorldLoad / MapApply)
    const float spawn[3] = {X + 13.7f, Y + 7.3f, Z + 8.0f};
    double id = se->create(SA1_CHAR_SONIC, spawn, 0.0f, err);
    std::vector<Val> r;
    for (int f = 0; f < 48 && id > 0; f++) {
        L.call("Tick", {Val::number(id), Val::number(0), Val::number(0), Val::number(0), Val::number(0),
                        Val::number(1.0 / 60.0)});
    }
    r = L.call("Render", {Val::number(id), Val::number(-1)});
    double rx = r.size() >= 5 ? r[2].num : 0, ry = r.size() >= 5 ? r[3].num : 0, rz = r.size() >= 5 ? r[4].num : 0;
    Val batches = Val::table();
    L.call("Batches", {Val::number(id), batches});
    int nb = (int)batches.tab->field("count").num, shadow_b = 0;
    for (int b = 1; b <= nb; b++) {
        Val e = batches.tab->at(b);
        if (e.type == Type::Table && ((uint32_t)e.tab->field("flags").num & 0x800u)) {
            shadow_b = shadow_b ? -1 : b;
        }
    }
    Val sbt = shadow_b > 0 ? batches.tab->at(shadow_b) : Val();
    CHECK(id > 0 && shadow_b > 0 && sbt.tab->field("pass").num == 1 && ((uint32_t)sbt.tab->field("wrap").num & 8u) &&
              sbt.tab->field("tris").num == 2,
          "Sonic standing at (%.0f, %.0f, %.0f): batch %d of %d is the blob shadow (DRAW_SHADOW), pass %g, address mode %g "
          "(mask bit 8), %g triangles, key %s", rx, ry, rz, shadow_b, nb, shadow_b > 0 ? sbt.tab->field("pass").num : -1.0,
          shadow_b > 0 ? sbt.tab->field("wrap").num : -1.0, shadow_b > 0 ? sbt.tab->field("tris").num : -1.0,
          shadow_b > 0 ? sbt.tab->field("key").str.c_str() : "-");
    // absolute, then relative to the drawn root
    auto emit_all = [&](double &farthest, double &shadow_col_ok) {
        g_mesh = MeshRec();
        farthest = 0.0;
        shadow_col_ok = 1.0;
        for (int b = 1; b <= nb; b++) {
            size_t v0 = g_mesh.vp.size() / 3;
            L.call("EmitBatch", {Val::number(id), Val::number(b)});
            size_t v1 = g_mesh.vp.size() / 3;
            Val e = batches.tab->at(b);
            bool lines = e.type == Type::Table && ((uint32_t)e.tab->field("prims").num & 4u);
            for (size_t v = v0; v < v1; v++) {
                for (int k = 0; k < 3 && !lines; k++) farthest = std::max(farthest, (double)std::fabs(g_mesh.vp[v * 3 + k]));
                if (b == shadow_b) {
                    shadow_col_ok = shadow_col_ok && g_mesh.vc[v * 4] == 204 && g_mesh.vc[v * 4 + 1] == 204 &&
                                    g_mesh.vc[v * 4 + 2] == 204 && g_mesh.vc[v * 4 + 3] == 255;
                }
            }
        }
    };
    Val eye = Val::vector((float)rx - 150.0f, (float)ry, (float)rz + 40.0f);
    L.call("PrepareView", {Val::number(id), eye, Val::vector(0, -1, 0), Val::vector(0, 0, 1), Val::boolean(false),
                           Val::boolean(false), Val::number(2), Val::boolean(true)});
    double far_abs = 0, cols_abs = 0;
    emit_all(far_abs, cols_abs);
    Val origin = Val::vector((float)rx, (float)ry, (float)rz);
    r = L.call("PrepareView", {Val::number(id), eye, Val::vector(0, -1, 0), Val::vector(0, 0, 1), Val::boolean(false),
                               Val::boolean(false), Val::number(2), Val::boolean(true), Val(), Val(), Val(), origin});
    double far_rel = 0, cols_rel = 0;
    emit_all(far_rel, cols_rel);
    Val state_t = Val::table();
    L.call("GetState", {Val::number(id), state_t});
    CHECK(r.size() == 1 && r[0].b && far_abs > 10000.0 && far_rel < 400.0 && cols_abs == 1.0 && cols_rel == 1.0 &&
              state_t.tab->field("shadow_draws").num == 1 && state_t.tab->field("relative").b && L.st.empty(),
          "EmitBatch: absolute up to %.0f HU; PrepareView(..., origin = the drawn root): every vertex within %.0f HU of 0; "
          "the shadow's colours (204, 204, 204, 255) with gsa1_vertexcolor 0 (both); GetState: shadow_draws %g, relative %s",
          far_abs, far_rel, state_t.tab->field("shadow_draws").num, state_t.tab->field("relative").b ? "true" : "false");
    Val list = Val::table();
    r = L.call("DrawList", {Val::number(id), list});
    int n = r.size() == 1 && r[0].type == Type::Number ? (int)r[0].num : -1, sh = 0, batched = 0, named = 0;
    std::string desc;
    for (int i = 1; i <= n; i++) {
        Val e = list.tab->at(i);
        if (e.type != Type::Table) continue;
        batched += e.tab->field("batch").num > 0;
        named += !e.tab->field("texname").str.empty();
        if ((uint32_t)e.tab->field("flags").num & 0x800u) {
            sh++;
            desc = gsa1::format("order %g, texture %g \"%s\" of %s, batch %g pass %g, alpha %g..%g, blend %g/%g",
                                e.tab->field("order").num, e.tab->field("tex").num, e.tab->field("texname").str.c_str(),
                                e.tab->field("aname").str.c_str(), e.tab->field("batch").num, e.tab->field("pass").num,
                                e.tab->field("amin").num, e.tab->field("amax").num, e.tab->field("src").num,
                                e.tab->field("dst").num);
            CHECK(e.tab->field("texname").str == "shadow" && e.tab->field("aname").str == "OBJ_REGULAR" &&
                      e.tab->field("batch").num == shadow_b && e.tab->field("pass").num == 1 &&
                      e.tab->field("amin").num == 204 && e.tab->field("amax").num == 204,
                  "DrawList: the shadow draw: %s", desc.c_str());
        }
    }
    CHECK(n > 10 && list.tab->field("count").num == n && sh == 1 && batched == n && named > 10 && L.st.empty(),
          "DrawList: %d draws (%d in batches, %d with a texture name), %d shadow draw", n, batched, named, sh);
    L.call("Destroy", {Val::number(id)});
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
