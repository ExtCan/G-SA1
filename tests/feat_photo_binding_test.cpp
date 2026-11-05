// feat_photo_binding_test: the claim photo mode rests on (sadc docs/research/photo099d.md section 11, RP.13), against the real game code with the disc: looking at frozen worlds writes nothing into them. Linked like binding_test (the module's
// objects, libsa1, the mock Lua stack of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi. It PASSES on 0.9.9c too and must stay passing: no module or libsa1 file changes for photo mode.
//
//   feat_photo_binding_test [--gdi GAME.gdi]
//
// Two sets, on a floor of their own (Session::set_world): Sonic with Knuckles, Tails and Big as followers; Super Sonic (General Gameplay) with two followers. One scripted input, three runs of each set:
//   run B: no freeze;
//   run A: stops at pair 60 and makes 300 "frozen frames" of what a frozen frame may call: gsa1.PrepareView from 5 far eyes, EmitBatch, ObjHeld, StateEx, HudCounters, Camera, Contacts;
//   run C (the test's teeth): the same frames also call gsa1.Tick with no time and a button press, the way the plan rejected: this must differ.
// Then each goes on for 600 pairs, with the same PrepareView from the same eye at every pair. Every pair's gsa1.GetState fields and every render's vertices must be equal between A and B, bit for bit, except the clock readings tick_ms, render_ms, view_ms (never
// equal), mesh_calls (the process's own count of mesh calls) and blend_layers, sprite_layers in the first pair (the eye's coverage from the last PrepareView: READ gsa1_module.cpp gsa1_lua_GetState, session.cpp prepare_view).
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

struct V3 {
    float x, y, z;
};

void floor_world(std::vector<sa1_collision_tri> &o)
{
    const float s = 8192;
    const float a[3][3] = {{-s, -s, 0}, {s, -s, 0}, {s, s, 0}}, b[3][3] = {{-s, -s, 0}, {s, s, 0}, {-s, s, 0}};
    sa1_collision_tri t;
    std::memset(&t, 0, sizeof t);
    std::memcpy(t.v, a, sizeof a);
    t.surface = SA1_SURFACE_SOLID;
    o.push_back(t);
    std::memcpy(t.v, b, sizeof b);
    o.push_back(t);
}

uint64_t fnv(uint64_t h, const void *p, size_t n)
{
    const unsigned char *c = static_cast<const unsigned char *>(p);
    for (size_t i = 0; i < n; i++) {
        h ^= c[i];
        h *= 1099511628211ull;
    }
    return h;
}

const uint64_t kSeed = 14695981039346656037ull;

// every field of gsa1.GetState's table but the clocks; first: also without what the last PrepareView's eye leaves
uint64_t hash_state(const Val &t, bool first, std::string *keys = nullptr)
{
    uint64_t h = kSeed;
    for (const auto &kv : t.tab->s) {
        const std::string &k = kv.first;
        if (k == "tick_ms" || k == "render_ms" || k == "view_ms" || k == "mesh_calls") continue;     // (mesh_calls: the process's count of EmitBatch's mesh calls, g_emit_calls, READ gsa1_module.cpp; photo099d.md's list missed it)
        if (first && (k == "blend_layers" || k == "sprite_layers")) continue;
        h = fnv(h, k.data(), k.size());
        const Val &v = kv.second;
        if (v.type == Type::Number) h = fnv(h, &v.num, sizeof v.num);
        else if (v.type == Type::Bool) h = fnv(h, &v.b, sizeof v.b);
        else if (v.type == Type::String) h = fnv(h, v.str.data(), v.str.size());
        if (keys) {
            *keys += k;
            *keys += ' ';
        }
    }
    return h;
}

uint64_t hash_vertices(uint64_t h)
{
    if (!g_mesh.vp.empty()) h = fnv(h, g_mesh.vp.data(), g_mesh.vp.size() * sizeof(float));
    if (!g_mesh.vn.empty()) h = fnv(h, g_mesh.vn.data(), g_mesh.vn.size() * sizeof(float));
    if (!g_mesh.vuv.empty()) h = fnv(h, g_mesh.vuv.data(), g_mesh.vuv.size() * sizeof(float));
    if (!g_mesh.vc.empty()) h = fnv(h, g_mesh.vc.data(), g_mesh.vc.size() * sizeof(double));
    g_mesh.vp.clear();
    g_mesh.vn.clear();
    g_mesh.vuv.clear();
    g_mesh.vc.clear();
    return h;
}

struct Set {
    const char *name;
    int kind;
    Val extras;
    std::vector<int> followers;
};

// run: 'B' no freeze, 'A' the frozen frames, 'C' those with a tick of no time and a press
struct Run {
    std::vector<uint64_t> states, verts;
    uint64_t emitted = 0;
    std::string keys;
    bool ok = false;
    double rings = 0;
};

void emit_all(MockLua &L, double id, const Val &batches)
{
    std::vector<Val> b = L.call("Batches", {Val::number(id), batches});
    const double n = b.size() >= 1 && b[0].type == Type::Number ? b[0].num : 0;
    for (int i = 1; i <= (int)n; i++) L.call("EmitBatch", {Val::number(id), Val::number(i)});
}

void prepare(MockLua &L, double id, float ex, float ey, float ez)
{
    L.call("PrepareView", {Val::number(id), Val::vector(ex, ey, ez), Val::vector(0, -1, 0), Val::vector(0, 0, 1)});
}

Run one_run(MockLua &L, gsa1::Session *se, const Set &set, char mode)
{
    Run R;
    std::string e;
    std::vector<Val> cr = L.call("Create", {Val::number(set.kind), Val::vector(0, 0, 8), Val::number(0), Val(), Val(), set.extras});
    if (cr.size() < 1 || cr[0].type != Type::Number) {
        CHECK(false, "%s: Create (%s)", set.name, str_of(cr, 1).c_str());
        return R;
    }
    const double id = cr[0].num;
    std::vector<double> fs;
    int n = 0;
    for (int kind : set.followers) {
        n++;
        Val opts = Val::table();
        opts.tab->set(Val::string("seed"), Val::number(1000 + n));
        std::vector<Val> fr = L.call("FollowerCreate", {Val::number(kind), Val::vector(-40.0f * n, 0, 8), Val::number(0), Val::number(fs.empty() ? id : fs.back()), opts});
        if (fr.size() < 1 || fr[0].type != Type::Number) {
            CHECK(false, "%s: FollowerCreate(%d) (%s)", set.name, kind, str_of(fr, 1).c_str());
        } else {
            fs.push_back(fr[0].num);
        }
    }
    Val tick_out = Val::table(), st = Val::table(), batches = Val::table(), ex = Val::table(), cam = Val::table(), con = Val::table();
    const int kFreezeAt = 60, kAfter = 600;
    auto pair_step = [&](int pair) {
        // the script: runs, turns, jumps, jumps and presses the action button in the air
        const double sy = pair % 200 < 150 ? 1 : 0, sx = pair % 90 < 30 ? 0.5 : 0;
        const double b = (pair % 80 < 6 ? (double)SA1_BUTTON_JUMP : 0) + (pair % 160 >= 8 && pair % 160 < 12 ? (double)SA1_BUTTON_ACTION : 0);
        std::vector<Val> tr = L.call("Tick", {Val::number(id), Val::number(sx), Val::number(sy), Val::number(90), Val::number(b), Val::number(1.0 / 30.0), Val::boolean(false), Val::number(0)});
        if (tr.empty() || tr[0].type != Type::Number) CHECK(false, "%s: Tick at pair %d", set.name, pair);
        if (!fs.empty()) L.call("FollowersTick", {Val::number(1.0 / 30.0), Val::number(90), Val(), Val(), tick_out});
    };
    for (int p = 0; p < kFreezeAt; p++) pair_step(p);
    if (mode != 'B') {
        const V3 eyes[5] = {{500, 0, 100}, {-500, 300, 40}, {0, 900, 400}, {0, -900, 10}, {4000, 4000, 900}};
        for (int f = 0; f < 300; f++) {
            for (const V3 &eye : eyes) {
                prepare(L, id, eye.x, eye.y, eye.z);
                emit_all(L, id, batches);
                for (double fid : fs) {
                    prepare(L, fid, eye.x, eye.y, eye.z);
                    emit_all(L, fid, batches);
                }
                hash_vertices(kSeed);
            }
            L.call("ObjHeld", {Val::number(id)});
            L.call("StateEx", {Val::number(id), ex});
            L.call("HudCounters", {Val::number(id)});
            L.call("Camera", {Val::number(id), Val::number(0.5), cam});
            L.call("Contacts", {Val::number(id), con});
            if (mode == 'C') {
                // the way the plan rejected: a tick of no time still takes the button as a press
                L.call("Tick", {Val::number(id), Val::number(0), Val::number(0), Val::number(90), Val::number(f % 2 ? (double)SA1_BUTTON_JUMP : 0), Val::number(0.0), Val::boolean(false), Val::number(0)});
            }
        }
    }
    for (int p = kFreezeAt; p < kFreezeAt + kAfter; p++) {
        pair_step(p);
        const bool first = p == kFreezeAt;
        L.call("GetState", {Val::number(id), st});
        R.states.push_back(hash_state(st, first, first && mode == 'B' ? &R.keys : nullptr));
        if (first) R.rings = st.tab->field("x").num;
        L.call("Render", {Val::number(id), Val::number(1)});
        prepare(L, id, 300, 300, 200);
        emit_all(L, id, batches);
        uint64_t h = hash_vertices(kSeed);
        for (double fid : fs) {
            L.call("GetState", {Val::number(fid), st});
            R.states.push_back(hash_state(st, first));
            prepare(L, fid, 300, 300, 200);
            emit_all(L, fid, batches);
            R.emitted += g_mesh.adv;
            h = hash_vertices(h);
        }
        R.verts.push_back(h);
    }
    R.emitted += g_mesh.adv;
    for (double fid : fs) L.call("Destroy", {Val::number(fid)});
    L.call("Destroy", {Val::number(id)});
    L.call("PollEvents", {Val::table()});
    (void)se;
    R.ok = true;
    return R;
}

size_t first_diff(const std::vector<uint64_t> &a, const std::vector<uint64_t> &b)
{
    const size_t n = a.size() < b.size() ? a.size() : b.size();
    for (size_t i = 0; i < n; i++) {
        if (a[i] != b[i]) return i;
    }
    return a.size() == b.size() ? (size_t)-1 : n;
}

}  // namespace

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_photo_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_photo_appdata");
#ifdef _WIN32
    char full[4096];
    GetFullPathNameA(fake_appdata.c_str(), sizeof full, full, nullptr);
    fake_appdata = full;
    SetEnvironmentVariableW(L"APPDATA", gsa1::widen(fake_appdata).c_str());
#else
    setenv("XDG_CONFIG_HOME", fake_appdata.c_str(), 1);
#endif
    gmod13_open(&state);
    install_mesh_library(L);
    auto finish = [&]() {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    };
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: this test is about the game's own code and needs the disc\n");
        return finish();
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
    gsa1::Session *se = gsa1::mod::session();
    CHECK(ist == "ready" && se, "the disc: %s", ist.c_str());
    if (ist != "ready" || !se) return finish();
    // gsa1.Create asks for a world: gm_construct from the Garry's Mod install, read only, as feat_follower_binding_test; then a floor of our own
    std::string bsp = gsa1_garrysmod_dir()[0] ? std::string(gsa1_garrysmod_dir()) + "/maps/gm_construct.bsp" : std::string();
    std::string map;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
        CHECK(false, "no gm_construct (%s): a gate fails on this line", bsp.c_str());
        return finish();
    }
    std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct) (Create needs a world)");
    std::vector<sa1_collision_tri> w;
    floor_world(w);
    CHECK(se->set_world(w, err), "the world (%s)", err.c_str());

    Val general = Val::table();
    general.tab->set(Val::string("create_flags"), Val::number(SA1_CREATE_SUPER_CAPABLE));
    general.tab->set(Val::string("super_flags"), Val::number(SA1_SUPER_GENERAL | SA1_SUPER_START | SA1_SUPER_NO_DRAIN));
    general.tab->set(Val::string("start_rings"), Val::number(50));
    const Set sets[] = {
        {"Sonic with Knuckles, Tails and Big", SA1_CHAR_SONIC, Val(), {SA1_CHAR_KNUCKLES, SA1_CHAR_TAILS, SA1_CHAR_BIG}},
        {"Super Sonic (General Gameplay) with two followers", SA1_CHAR_SONIC, general, {SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES}},
    };
    for (const Set &set : sets) {
        Run b = one_run(L, se, set, 'B');
        Run b2 = one_run(L, se, set, 'B');
        Run a = one_run(L, se, set, 'A');
        Run c = one_run(L, se, set, 'C');
        if (!(a.ok && b.ok && b2.ok && c.ok)) continue;
        std::printf("  info  %s: state fields: %s\n", set.name, b.keys.c_str());
        size_t same = first_diff(b.states, b2.states), samev = first_diff(b.verts, b2.verts);
        CHECK(same == (size_t)-1 && samev == (size_t)-1, "%s: the same run twice is the same (the test's premise; states differ at %d, vertices at %d)", set.name, (int)same, (int)samev);
        size_t ds = first_diff(a.states, b.states), dv = first_diff(a.verts, b.verts);
        CHECK(a.states.size() >= 600 && ds == (size_t)-1, "%s: 300 frozen frames, then 600 pairs: every gsa1.GetState field as without them, bit for bit, but the clocks (%d records; first difference %d)", set.name, (int)a.states.size(), (int)ds);
        CHECK(a.verts.size() == 600 && dv == (size_t)-1, "%s: and every render's vertices (%d renders; first difference %d)", set.name, (int)a.verts.size(), (int)dv);
        size_t dc = first_diff(c.states, b.states), dcv = first_diff(c.verts, b.verts);
        CHECK(dc != (size_t)-1 || dcv != (size_t)-1, "%s: the test has teeth: gsa1.Tick with no time and a press in those frames differs (states at %d, vertices at %d)", set.name, (int)dc, (int)dcv);
    }
    return finish();
}
