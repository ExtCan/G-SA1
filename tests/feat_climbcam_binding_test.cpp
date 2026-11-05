// feat_climbcam_binding_test: what the climbing camera (addon/lua/gsa1/feat/cl_climbcam.lua, round 0.9.9c) reads from the module: gsa1.GetState's
// upx, upy, upz, the character's up vector in Garry's Mod's axes, through the module's Lua function. Linked like binding_test (the module's objects,
// libsa1, the mock Lua stack of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi. The world is one of its own (Session::set_world): a floor, a
// wall, a roof behind the wall's top, so no map is needed. Game code plays: Knuckles walks, jumps and glides into the wall (the input of the 099b
// climb verifier's probe), then climbs over the top, jumps off, climbs down, climbs across and off the wall's edge, or goes round a corner.
//
//   feat_climbcam_binding_test [--gdi GAME.gdi]
//
// The other ways off the wall too: hit (gsa1.Damage with rings), killed (without), switched to Sonic and re-created where it stands (Destroy, then Session::create at the
// root, as GSA1.Spawn and GSA1.Recreate do), the file's "X <kind>" line tells where.
//
// Checks: up is a unit vector on every frame; straight up while standing; the wall's normal on the wall at each of five facings (MEASURED by the
// earlier probe for one facing only); Knuckles' position stays on the wall's plane there; mode 25 starts with up still on the wall (the reason the
// camera cannot wait for up to come back); old fields unchanged; no table per call with `out`.
//
// It writes build/<target>/climb_trajectory.txt next to this test: every frame of every scene at 60 frames a second, as the addon sees it (the root
// gsa1.Render returns, the mode, up). tests/feat_climbcam_test.lua replays the file through the real CalcView against walls of its own. Positions and
// angles are numbers the game's code computed: no game bytes.
//   S <name> <nx> <ny> <nz> <top> <half width>          a scene: the wall's normal; the wall stands on the plane through the origin
//   F <mode> <action> <x> <y> <z> <upx> <upy> <upz> <step> <alpha>      a frame (alpha: the one gsa1.Render used for that root)
//   X <kind>                                                            the character is replaced here by a new one of that kind, at the root
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

namespace {

// a mock that counts the tables the module makes (gsa1.GetState with `out` must make none)
class CountingLua : public MockLua {
public:
    uint64_t tables = 0;
    void CreateTable() override
    {
        tables++;
        MockLua::CreateTable();
    }
};

double field_num(const Val &t, const char *k)
{
    Val v = t.tab ? t.tab->field(k) : Val();
    return v.type == Type::Number ? v.num : -1e9;
}

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1e9;
}

struct V3 {
    float x, y, z;
};

void tri(std::vector<sa1_collision_tri> &o, V3 a, V3 b, V3 c)
{
    sa1_collision_tri t;
    std::memset(&t, 0, sizeof t);
    const float p[3][3] = {{a.x, a.y, a.z}, {b.x, b.y, b.z}, {c.x, c.y, c.z}};
    std::memcpy(t.v, p, sizeof p);
    t.surface = SA1_SURFACE_SOLID;
    o.push_back(t);
}

// a quad whose triangles' normal (right-hand winding) points along `want`: the game's polygons have a front
void quad(std::vector<sa1_collision_tri> &o, V3 a, V3 b, V3 c, V3 d, V3 want)
{
    const float e1[3] = {b.x - a.x, b.y - a.y, b.z - a.z}, e2[3] = {c.x - a.x, c.y - a.y, c.z - a.z};
    const float n[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
    if (n[0] * want.x + n[1] * want.y + n[2] * want.z >= 0) {
        tri(o, a, b, c);
        tri(o, a, c, d);
    } else {
        tri(o, a, c, b);
        tri(o, a, d, c);
    }
}

// a floor at z 0, a wall on the plane through the origin with the normal (nx, ny, 0), `lo` .. `hi` along its tangent (-ny, nx), from the floor to
// `top`, and a roof behind its top
void wall_world(std::vector<sa1_collision_tri> &o, float nx, float ny, float top, float lo, float hi)
{
    const float tx = -ny, ty = nx;
    quad(o, {-4096, -4096, 0}, {4096, -4096, 0}, {4096, 4096, 0}, {-4096, 4096, 0}, {0, 0, 1});
    V3 a = {tx * lo, ty * lo, 0}, b = {tx * hi, ty * hi, 0};
    quad(o, a, {a.x, a.y, top}, {b.x, b.y, top}, b, {nx, ny, 0});
    V3 c = {b.x - nx * 512, b.y - ny * 512, top}, d = {a.x - nx * 512, a.y - ny * 512, top};
    quad(o, {a.x, a.y, top}, d, c, {b.x, b.y, top}, {0, 0, 1});
}

struct Scene {
    const char *name;
    float nx, ny;
    int phase;      // what happens 60 pairs after the grab: 0 over the top, 1 jump off, 2 climb down, 3 across (off the edge or round a corner), 4 rest, 5 hit, 6 killed,
                    // 7 switched to Sonic, 8 re-created
    float lo, hi;   // the wall's extent along its tangent (-ny, nx)
    int corner;     // 0 none, 1 an outer corner at `hi` (a second wall going back from it), 2 an inner corner at `hi` (a second wall coming out from it)
};

}  // namespace

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_climbcam_binding_test\n");
    CountingLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_climbcam_appdata");
#ifdef _WIN32
    char full[4096];
    GetFullPathNameA(fake_appdata.c_str(), sizeof full, full, nullptr);
    fake_appdata = full;
    SetEnvironmentVariableW(L"APPDATA", gsa1::widen(fake_appdata).c_str());
#else
    setenv("XDG_CONFIG_HOME", fake_appdata.c_str(), 1);
#endif
    gmod13_open(&state);
    auto finish = [&]() {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    };
    std::string path = gsa1::join_path(self.empty() ? "." : self, "climb_trajectory.txt");
    std::remove(path.c_str());      // (an old file must not stand in for this run)
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the game's climb needs the disc; tests/feat_climbcam_test.lua then replays its own climb only\n");
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
    if (ist != "ready" || !se) {
        return finish();
    }

    {
        std::vector<Val> ci = L.call("CharacterInfo", {Val::number(SA1_CHAR_KNUCKLES)});
        const Val &v = ci.empty() ? Val() : ci[0];
        const double center = v.type == Type::Table ? field_num(v, "center") : -1, eyes = v.type == Type::Table ? field_num(v, "eyes") : -1;
        CHECK(center > 20 && center < 25 && eyes > center, "Knuckles' center %.2f and eyes %.2f (the numbers tests/feat_climbcam_test.lua plays with)", center, eyes);
    }
    const float kDiag = 0.70710678f;
    const float kWide = 2048.0f;
    const Scene scenes[] = {
        // every facing, over the top
        {"py_over", 0, 1, 0, -kWide, kWide, 0},
        {"my_over", 0, -1, 0, -kWide, kWide, 0},
        {"px_over", 1, 0, 0, -kWide, kWide, 0},
        {"mx_over", -1, 0, 0, -kWide, kWide, 0},
        {"dg_over", kDiag, kDiag, 0, -kWide, kWide, 0},
        // the other ways off the wall
        {"py_jump", 0, 1, 1, -kWide, kWide, 0},
        {"mx_jump", -1, 0, 1, -kWide, kWide, 0},
        {"py_down", 0, 1, 2, -kWide, kWide, 0},
        {"px_down", 1, 0, 2, -kWide, kWide, 0},
        {"dg_down", kDiag, kDiag, 2, -kWide, kWide, 0},
        {"py_edge", 0, 1, 3, -240, 240, 0},
        {"my_edge", 0, -1, 3, -240, 240, 0},
        {"px_rest", 1, 0, 4, -kWide, kWide, 0},
        // corners: stick to the right while looking at the wall (the wall's tangent side `hi` or `lo`, whichever the stick reaches)
        {"py_outer", 0, 1, 3, -240, 240, 1},
        {"py_inner", 0, 1, 3, -240, 240, 2},
        // hit, killed, the character replaced
        {"py_hit", 0, 1, 5, -kWide, kWide, 0},
        {"mx_hit", -1, 0, 5, -kWide, kWide, 0},
        {"dg_hit", kDiag, kDiag, 5, -kWide, kWide, 0},
        {"py_die", 0, 1, 6, -kWide, kWide, 0},
        {"py_switch", 0, 1, 7, -kWide, kWide, 0},
        {"mx_switch", -1, 0, 7, -kWide, kWide, 0},
        {"py_recreate", 0, 1, 8, -kWide, kWide, 0},
    };
    std::string out_text;
    int scenes_on_wall = 0, up_bad = 0, on_plane_bad = 0;
    uint64_t state_calls = 0, state_tables = 0;
    double up_len_err = 0, up_wall_err = 0, stand_err = 0, mode25_dot = 2;
    int mode25_seen = 0, hits_seen = 0, damage_bad = 0, replaced = 0;
    for (const Scene &sc : scenes) {
        std::vector<sa1_collision_tri> w;
        const float top = 320;
        wall_world(w, sc.nx, sc.ny, top, sc.lo, sc.hi);
        if (sc.corner) {
            // a second wall at the tangent end `sc.lo` and `sc.hi`: going back behind the first (outer) or coming out in front of it (inner)
            const float tx = -sc.ny, ty = sc.nx, s = sc.corner == 1 ? -1.0f : 1.0f;
            for (float end : {sc.lo, sc.hi}) {
                V3 a = {tx * end, ty * end, 0}, b = {a.x + s * sc.nx * 512, a.y + s * sc.ny * 512, 0};
                const float out = (end > 0 ? 1.0f : -1.0f) * (sc.corner == 1 ? 1.0f : -1.0f);   // the outer one faces away from the first wall's middle
                quad(w, a, {a.x, a.y, top}, {b.x, b.y, top}, b, {out * tx, out * ty, 0});
            }
        }
        CHECK(se->set_world(w, err), "%s: the world (%s)", sc.name, err.c_str());
        const float start[3] = {sc.nx * 400, sc.ny * 400, 8.0f};
        const double yaw_deg = std::atan2(-(double)sc.ny, -(double)sc.nx) * 180.0 / 3.14159265358979323846;
        std::string e;
        double id = se->create(SA1_CHAR_KNUCKLES, start, gsa1::mod::deg2rad(yaw_deg), e);
        CHECK(id > 0, "%s: Knuckles (%s)", sc.name, e.c_str());
        if (id <= 0) continue;
        out_text += gsa1::format("S %s %.6f %.6f 0 %.1f %.1f\n", sc.name, sc.nx, sc.ny, top, sc.hi);
        if (sc.phase == 5) L.call("AddRings", {Val::number(id), Val::number(20)});
        Val out = Val::table();
        int on_wall = -1, left_at = -1, last_mode = -99;
        bool did = false;
        int kind = SA1_CHAR_KNUCKLES;
        for (int f = 0; f < 1500; f++) {
            const int pair = f / 2;
            double sx = 0, sy = 0, b = 0;
            if (on_wall < 0) {
                if (pair >= 20) sy = 1;
                if (pair >= 50 && (pair < 54 || pair >= 60)) b = (double)SA1_BUTTON_JUMP;
            } else {
                const int t = pair - on_wall;
                if (t >= 60) {
                    if (sc.phase == 0) sy = 1;
                    if (sc.phase == 1 && t < 64) b = (double)SA1_BUTTON_JUMP;
                    if (sc.phase == 2) sy = -1;
                    if (sc.phase == 3) sx = 1;
                    if ((sc.phase == 5 || sc.phase == 6) && !did) {
                        did = true;
                        // from the open side, a little to the side (an enemy next to the wall)
                        std::vector<Val> dr = L.call("Damage", {Val::number(id), Val::number(1), Val::number(field_num(out, "x") + sc.nx * 40 - sc.ny * 10),
                                                                Val::number(field_num(out, "y") + sc.ny * 40 + sc.nx * 10), Val::number(field_num(out, "z") + 10)});
                        if (dr.empty() || dr[0].type == Type::Nil) damage_bad++;
                    }
                    if ((sc.phase == 7 || sc.phase == 8) && !did) {
                        did = true;
                        std::vector<Val> rr = L.call("Render", {Val::number(id), Val::number(-1)});
                        const float p[3] = {(float)num_of(rr, 2), (float)num_of(rr, 3), (float)num_of(rr, 4) + (sc.phase == 8 ? 1.0f : 0.0f)};
                        L.call("Destroy", {Val::number(id)});
                        kind = sc.phase == 7 ? SA1_CHAR_SONIC : SA1_CHAR_KNUCKLES;
                        id = se->create(kind, p, gsa1::mod::deg2rad(yaw_deg), e);
                        CHECK(id > 0, "%s: the new character (%s)", sc.name, e.c_str());
                        if (id <= 0) break;
                        out_text += gsa1::format("X %d\n", kind);
                        replaced++;
                    }
                }
            }
            std::vector<Val> tr = L.call("Tick", {Val::number(id), Val::number(sx), Val::number(sy), Val::number(yaw_deg), Val::number(b), Val::number(1.0 / 60.0),
                                                  Val::boolean(false), Val::number(0)});
            if (tr.empty() || tr[0].type != Type::Number) {
                CHECK(false, "%s: Tick at frame %d", sc.name, f);
                break;
            }
            uint64_t t0 = L.tables;
            L.call("GetState", {Val::number(id), out});
            state_tables += L.tables - t0;
            state_calls++;
            std::vector<Val> rr = L.call("Render", {Val::number(id), Val::number(-1)});
            const double ux = field_num(out, "upx"), uy = field_num(out, "upy"), uz = field_num(out, "upz");
            const int mode = (int)field_num(out, "mode"), action = (int)field_num(out, "action");
            const double x = num_of(rr, 2), y = num_of(rr, 3), z = num_of(rr, 4);
            const double len = std::sqrt(ux * ux + uy * uy + uz * uz);
            if (!(std::fabs(len - 1.0) < 2e-3)) up_bad++;
            up_len_err = std::max(up_len_err, std::fabs(len - 1.0));
            if (f >= 4 && f < 30) {
                stand_err = std::max(stand_err, std::max(std::fabs(ux), std::max(std::fabs(uy), std::fabs(uz - 1.0))));
            }
            if (mode == 14 && last_mode == 24 && sc.phase == 5) hits_seen++;
            if (mode == 24 && !did) {
                if (on_wall < 0) on_wall = pair;
                const int t = pair - on_wall;
                if (!sc.corner && t >= 2) {
                    up_wall_err = std::max(up_wall_err, std::max(std::fabs(ux - sc.nx), std::max(std::fabs(uy - sc.ny), std::fabs(uz))));
                    const double sn = field_num(out, "x") * sc.nx + field_num(out, "y") * sc.ny;
                    if (std::fabs(sn) > 0.5) on_plane_bad++;
                }
            }
            if (mode == 25 && last_mode == 24) {
                mode25_seen++;
                mode25_dot = std::min(mode25_dot, ux * sc.nx + uy * sc.ny);
            }
            if (on_wall >= 0 && mode != 24 && left_at < 0) left_at = f;
            last_mode = mode;
            out_text += gsa1::format("F %d %d %.4f %.4f %.4f %.5f %.5f %.5f %.0f %.4f\n", mode, action, x, y, z, ux, uy, uz, field_num(out, "step"), num_of(rr, 7));
            if (on_wall >= 0 && pair - on_wall > 320) break;
            if (left_at >= 0 && f - left_at > 240) break;
        }
        if (on_wall >= 0) scenes_on_wall++;
        std::printf("  info  %s: on the wall from pair %d, left it at frame %d\n", sc.name, on_wall, left_at);
        if (id > 0) L.call("Destroy", {Val::number(id)});
    }
    const int nscenes = (int)(sizeof scenes / sizeof scenes[0]);
    CHECK(scenes_on_wall == nscenes, "Knuckles grabs the wall in every scene (%d of %d)", scenes_on_wall, nscenes);
    CHECK(up_bad == 0, "gsa1.GetState's upx, upy, upz: a unit vector on every frame (worst %.2e, %d bad)", up_len_err, up_bad);
    CHECK(stand_err < 1e-3, "standing: up is straight up (off by at most %.2e)", stand_err);
    CHECK(up_wall_err < 0.02, "on the wall: up is the wall's normal at every facing (off by at most %.4f)", up_wall_err);
    CHECK(on_plane_bad == 0, "on the wall: the state's position is on the wall's plane (%d frames off by more than 0.5)", on_plane_bad);
    CHECK(mode25_seen >= 5 && mode25_dot > 0.99, "the first frame of mode 25 (over the top, %d times) has up still on the wall (dot with the normal at least %.3f)", mode25_seen, mode25_dot);
    CHECK(damage_bad == 0 && hits_seen == 3, "hit on the wall: the game goes from mode 24 to mode 14 in %d of 3 scenes (%d calls of gsa1.Damage refused)", hits_seen, damage_bad);
    CHECK(replaced == 3, "the character replaced on the wall in %d of 3 scenes", replaced);
    CHECK(state_calls > 1000 && state_tables == 0, "%llu calls of gsa1.GetState with `out` made %llu tables", (unsigned long long)state_calls, (unsigned long long)state_tables);
    std::FILE *f = std::fopen(path.c_str(), "wb");
    bool ok = f && std::fwrite(out_text.data(), 1, out_text.size(), f) == out_text.size();
    if (f) std::fclose(f);
    CHECK(ok, "climb_trajectory.txt written: %s (%zu bytes)", path.c_str(), out_text.size());
    return finish();
}
