// feat_look_binding_test: the head look through the module's Lua functions (round 0.9.8: sadc docs/research/gsa1_098_plan.md 5.5, 6.8;
// gsa1_096_plan.md 5.5, 6.6 with its review R.13; look096.md 7.2.1, 8.3) - the feature "look" (src/module/bind_look.cpp: gsa1.Look,
// gsa1.LookState, the constants). Linked like binding_test (the module's objects, libsa1, the mock Lua stack of tests/mock_lua.hpp) by
// build.py, run with --gdi GAME.gdi. The world is a flat SOLID floor of its own (Session::set_world), so no map is needed.
//
//   feat_look_binding_test [--gdi GAME.gdi]
//
// Three parts:
//   * THE API PART runs whenever libsa1.h has SA1_API_LOOK: gsa1.FEATURES.look == 1, the functions and constants, every bad argument
//     answered ("bad_argument" before anything else, never a Lua error), "not_ready" before the disc - and writes
//     build/<target>/look_api.txt next to this test (tests/feat_look_test.lua checks its mock module against it).
//   * THE BEHAVIOUR PART prints exactly one line "SKIP behaviour: look is not built yet" and passes while libsa1's sa1_character_look
//     answers that text; otherwise it runs in full: POINT left -> after 2 pairs LookState head_y +45 (Sonic, Knuckles, Amy) / +33.75
//     (Tails, Big), right the negative, straight ahead 0, up -33.75; another facing; ANGLES; CAMERA with the camera passed to gsa1.Tick,
//     towards it; OFF -> 0 within 2 pairs; E-102 false with libsa1's message and "unsupported"; COPT_SUPER_LOOK 1 against option 0 at the
//     same steps: at least 400 of kind 8's triangles differ, and two worlds at option 0 do not differ (review R.13: "moves" alone is met
//     by the animation); no table made by gsa1.Look, or by LookState with its out table.
//   * THE FOLLOWER CASE (after followmod_real.txt: 098 plan 6.8) prints exactly one line "SKIP behaviour: follower is not built yet" while
//     the module or libsa1 has no follower; otherwise a Tails follower of a Sonic: POINT at its left -> its LookState head_y +33.75, kind
//     POINT, owner 1; LOOK_CAMERA reaches it (kind CAMERA); OFF -> 0.
//
// look_api.txt's records, one per line, tab-separated:
//   feature <name> <version>                       function <Name> <arguments> <returns> <codes, comma separated>
//   const <NAME> <number>                          field LookState <field> <lua type>
//   reason <code> <text>                           behaviour <RAN | SKIP> <what>
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

namespace {

// a mock that counts the tables the module makes (gsa1.Look and LookState with `out` must make none)
class CountingLua : public MockLua {
public:
    uint64_t tables = 0;
    void CreateTable() override
    {
        tables++;
        MockLua::CreateTable();
    }
};

#if defined(SA1_API_LOOK)
bool is_true(const std::vector<Val> &r)
{
    return r.size() >= 1 && r[0].type == Type::Bool && r[0].b;
}

bool is_false_msg(const std::vector<Val> &r, const char *code)
{
    return r.size() >= 3 && r[0].type == Type::Bool && !r[0].b && r[1].type == Type::String && !r[1].str.empty() &&
           str_of(r, 2) == code;
}

double field_num(const Val &t, const char *k)
{
    Val v = t.tab ? t.tab->field(k) : Val();
    return v.type == Type::Number ? v.num : -1e9;
}

bool close_to(double a, double b, double eps = 0.02)
{
    return std::fabs(a - b) <= eps;
}

// a flat SOLID floor (host space, z up) at z = 0, of 256-HU tiles
std::vector<sa1_collision_tri> flat_floor(float half)
{
    std::vector<sa1_collision_tri> out;
    const float tile = 256.0f;
    for (float x = -half; x < half - 0.5f; x += tile) {
        for (float y = -half; y < half - 0.5f; y += tile) {
            const float p[4][3] = {{x, y, 0}, {x + tile, y, 0}, {x + tile, y + tile, 0}, {x, y + tile, 0}};
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

// the triangles (of the first min(a, b)) with a vertex more than eps apart: positions are 9 floats a triangle
int differing_triangles(const gsa1::Character &a, const gsa1::Character &b, float eps)
{
    size_t n = std::min(a.r_tpos.size(), b.r_tpos.size()) / 9;
    int d = 0;
    for (size_t t = 0; t < n; t++) {
        for (size_t k = 0; k < 9; k++) {
            if (std::fabs(a.r_tpos[t * 9 + k] - b.r_tpos[t * 9 + k]) > eps) {
                d++;
                break;
            }
        }
    }
    return d;
}
#endif  // SA1_API_LOOK

}  // namespace

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_look_binding_test\n");
    CountingLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_look_appdata");
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
#if !defined(SA1_API_LOOK)
    CHECK(feats.type == Type::Table && feats.tab->field("look").type == Type::Nil,
          "libsa1.h has no SA1_API_LOOK: no feature \"look\" (GSA1.HasFeature false), the addon's page says what it needs");
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
#else
    // ---- the API part --------------------------------------------------------------------------------------------------------
    std::vector<std::string> api;
    auto rec = [&](const std::string &s) { api.push_back(s); };
    if (g.type != Type::Table) {
        CHECK(false, "the gsa1 table");
        return 1;
    }
    CHECK(feats.type == Type::Table && feats.tab->field("look").num == 1 && g.tab->field("Look").type == Type::Function &&
              g.tab->field("LookState").type == Type::Function && L.st.empty(),
          "gsa1.FEATURES.look = %g; Look and LookState registered", feats.type == Type::Table ? feats.tab->field("look").num : -1.0);
    rec("feature\tlook\t1");
    rec("function\tLook\tid, kind [, a, b, c] [, flags]\ttrue | false, message, code\tbad_argument,not_ready,not_found,unsupported,fault");
    rec("function\tLookState\tid [, out]\tout | nil, message, code\tbad_argument,not_ready,not_found");
    struct { const char *name; double value, want; } consts[] = {
        {"LOOK_OFF", (double)SA1_LOOK_OFF, 0}, {"LOOK_POINT", (double)SA1_LOOK_POINT, 1}, {"LOOK_ANGLES", (double)SA1_LOOK_ANGLES, 2},
        {"LOOK_CAMERA", (double)SA1_LOOK_CAMERA, 3}, {"LOOK_OVERRIDE_GAME", (double)SA1_LOOKF_OVERRIDE_GAME, 1},
        {"COPT_SUPER_LOOK", (double)SA1_COPT_SUPER_LOOK, 7},
    };
    bool const_ok = true;
    for (const auto &c : consts) {
        Val v = g.tab->field(c.name);
        const_ok = const_ok && v.type == Type::Number && v.num == c.value && v.num == c.want;
        rec(gsa1::format("const\t%s\t%.0f", c.name, c.value));
    }
    CHECK(const_ok, "gsa1.LOOK_OFF 0, LOOK_POINT 1, LOOK_ANGLES 2, LOOK_CAMERA 3, LOOK_OVERRIDE_GAME 1, COPT_SUPER_LOOK 7: libsa1's numbers");
    for (const char *f : {"kind", "owner", "head_y", "head_z", "eye_y", "eye_z"}) {
        rec(gsa1::format("field\tLookState\t%s\tnumber", f));
    }
    const double kOff = SA1_LOOK_OFF, kPoint = SA1_LOOK_POINT, kAngles = SA1_LOOK_ANGLES, kCamera = SA1_LOOK_CAMERA;
    int bad = 0, bad_of = 0;
    auto bad_call = [&](std::vector<Val> a) {
        bad_of++;
        bad += is_false_msg(L.call("Look", a), "bad_argument") ? 1 : 0;
    };
    bad_call({});
    bad_call({Val::number(1)});
    bad_call({Val::string("1"), Val::number(kOff)});
    bad_call({Val::number(0), Val::number(kOff)});
    bad_call({Val::number(1.5), Val::number(kOff)});
    bad_call({Val::number(1), Val::number(99)});
    bad_call({Val::number(1), Val::number(-1)});
    bad_call({Val::number(1), Val::string("point")});
    bad_call({Val::number(1), Val::number(kPoint)});
    bad_call({Val::number(1), Val::number(kPoint), Val::number(1), Val::number(2)});
    bad_call({Val::number(1), Val::number(kPoint), Val::number(1e31), Val::number(2), Val::number(3)});
    bad_call({Val::number(1), Val::number(kAngles), Val::number(1)});
    bad_call({Val::number(1), Val::number(kOff), Val(), Val(), Val(), Val::string("x")});
    bad_call({Val::number(1), Val::number(kOff), Val(), Val(), Val(), Val::number(0.5)});
    std::vector<Val> ls0 = L.call("LookState", {});
    std::vector<Val> nr1 = L.call("Look", {Val::number(1), Val::number(kOff)});
    std::vector<Val> nr2 = L.call("LookState", {Val::number(1)});
    CHECK(bad == bad_of && is_nil_msg(ls0) && str_of(ls0, 2) == "bad_argument" && L.st.empty(),
          "bad arguments: %d of %d answered false, message, \"bad_argument\" (no Lua error); LookState() nil, message, \"%s\"", bad, bad_of,
          str_of(ls0, 2).c_str());
    CHECK(is_false_msg(nr1, "not_ready") && is_nil_msg(nr2) && str_of(nr2, 2) == "not_ready",
          "before the disc: Look false, \"%s\", \"not_ready\"; LookState nil, \"not_ready\"", str_of(nr1, 1).c_str());

    auto write_api = [&](const char *behaviour) {
        std::string path = gsa1::join_path(self.empty() ? "." : self, "look_api.txt");
        std::string text = "# G-SA1 look_api.txt: the module contract of round 0.9.8 (sadc docs/research/gsa1_098_plan.md 5.5)\n"
                           "# written by tests/feat_look_binding_test.cpp from the module as built against this target's\n"
                           "# build/deps/include/libsa1.h (" + std::string(sa1_version_string()) + "). Tab-separated records:\n"
                           "# feature | function | const | field | reason | behaviour\n";
        for (const std::string &r : api) {
            text += r + "\n";
        }
        text += std::string("behaviour\t") + behaviour + "\n";
        std::FILE *f = std::fopen(path.c_str(), "wb");
        bool ok = f && std::fwrite(text.data(), 1, text.size(), f) == text.size();
        if (f) std::fclose(f);
        CHECK(ok, "look_api.txt written: %s (%zu records)", path.c_str(), api.size() + 1);
    };
    auto finish = [&]() {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    };

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the behaviour part needs the disc\n");
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
    for (int polls = 0; ist == "loading" && polls < 30000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        ist = str_of(L.call("InitPoll", {}), 0);
    }
    gsa1::Session *se = gsa1::mod::session();
    bool world = ist == "ready" && se && se->set_world(flat_floor(4096.0f), err);
    CHECK(world, "the disc (%s), a flat SOLID floor%s%s", ist.c_str(), err.empty() ? "" : ": ", err.c_str());
    if (!world) {
        write_api("SKIP\tno disc");
        return finish();
    }
    install_mesh_library(L);
    const double kEyes = 28.0;      // about any kind's eyes (HU): only the sign of a small z difference depends on it
    auto make = [&](int kind, double yaw_deg = 0.0) -> double {
        const float pos[3] = {0.0f, 0.0f, 8.0f};
        std::string e;
        return se->create(kind, pos, gsa1::mod::deg2rad(yaw_deg), e);
    };
    // one pair (Tick with dt 1/30), the camera as the addon passes it when asked
    auto pair = [&](double id) {
        L.call("Tick", {Val::number(id), Val::number(0), Val::number(0), Val::number(0), Val::number(0), Val::number(1.0 / 30.0)});
    };
    auto pairs = [&](double id, int n) {
        for (int i = 0; i < n; i++) pair(id);
    };
    auto look_point = [&](double id, double x, double y, double z) {
        return L.call("Look", {Val::number(id), Val::number(kPoint), Val::number(x), Val::number(y), Val::number(z)});
    };
    Val out = Val::table();
    auto state_of = [&](double id) { L.call("LookState", {Val::number(id), out}); };

    // ---- SKIP while libsa1's gate is closed ------------------------------------------------------------------------------------
    double sonic = make(SA1_CHAR_SONIC);
    CHECK(sonic > 0, "a Sonic on the floor (id %.0f)", sonic);
    pairs(sonic, 10);
    std::vector<Val> first = L.call("Look", {Val::number(sonic), Val::number(kOff)});
    bool gated = first.size() >= 2 && first[0].type == Type::Bool && !first[0].b &&
                 str_of(first, 1).find("not built yet") != std::string::npos;
    if (gated) {
        std::printf("SKIP behaviour: look is not built yet\n");
        write_api("SKIP\tlook is not built yet");
        return finish();
    }
    CHECK(is_true(first), "gsa1.Look(id, LOOK_OFF) on a world with no look: true (%s)", str_of(first, 1).c_str());
    std::vector<Val> nf = L.call("Look", {Val::number(777777), Val::number(kOff)});
    std::vector<Val> nf2 = L.call("LookState", {Val::number(777777)});
    CHECK(is_false_msg(nf, "not_found") && is_nil_msg(nf2) && str_of(nf2, 2) == "not_found", "no such character: \"not_found\" from both");
    CHECK(L.call("LookState", {Val::number(sonic), out}).size() == 1 && out.tab->field("kind").type == Type::Number &&
              out.tab->field("owner").type == Type::Number && out.tab->field("head_y").type == Type::Number &&
              out.tab->field("head_z").type == Type::Number && out.tab->field("eye_y").type == Type::Number &&
              out.tab->field("eye_z").type == Type::Number,
          "LookState fills its out table: kind %g, owner %g, head_y %g, head_z %g, eye_y %g, eye_z %g", field_num(out, "kind"),
          field_num(out, "owner"), field_num(out, "head_y"), field_num(out, "head_z"), field_num(out, "eye_y"), field_num(out, "eye_z"));

    // ---- POINT, per kind: left, right, straight ahead, up ---------------------------------------------------------------------------
    struct { int kind; const char *name; double limit; } kinds[] = {
        {SA1_CHAR_SONIC, "Sonic", 45.0}, {SA1_CHAR_TAILS, "Tails", 33.75}, {SA1_CHAR_KNUCKLES, "Knuckles", 45.0}, {SA1_CHAR_AMY, "Amy", 45.0},
        {SA1_CHAR_BIG, "Big", 33.75},
    };
    for (const auto &k : kinds) {
        double id = make(k.kind);
        pairs(id, 10);
        const float z = 8.0f + (float)kEyes;
        bool ok1 = is_true(look_point(id, 0.0, 200.0, z));
        pairs(id, 2);
        state_of(id);
        double left = field_num(out, "head_y"), kd = field_num(out, "kind"), ow = field_num(out, "owner");
        bool ok2 = is_true(look_point(id, 0.0, -200.0, z));
        pairs(id, 3);
        state_of(id);
        double right = field_num(out, "head_y");
        L.call("Look", {Val::number(id), Val::number(kOff)});
        pairs(id, 2);
        state_of(id);
        double off = field_num(out, "head_y"), offk = field_num(out, "kind");
        CHECK(ok1 && ok2 && close_to(left, k.limit) && close_to(right, -k.limit) && kd == kPoint && ow == 1 && close_to(off, 0.0) && offk == kOff,
              "%s: POINT to its left: after 2 pairs head_y %+g (want %+g), kind %g, owner %g; to its right %+g; OFF: %+g within 2 pairs, "
              "kind %g", k.name, left, k.limit, kd, ow, right, off, offk);
        L.call("Destroy", {Val::number(id)});
    }
    {
        double id = make(SA1_CHAR_SONIC);
        pairs(id, 10);
        const float z = 8.0f + (float)kEyes;
        look_point(id, 200.0, 0.0, z);
        pairs(id, 2);
        state_of(id);
        double ahead = field_num(out, "head_y");
        look_point(id, 40.0, 0.0, z + 400.0);
        pairs(id, 3);
        state_of(id);
        double up = field_num(out, "head_z");
        CHECK(std::fabs(ahead) < 6.0 && close_to(up, -33.75), "Sonic: straight ahead head_y %+g (near 0); far above head_z %+g (want -33.75: + is down)",
              ahead, up);
        L.call("Destroy", {Val::number(id)});
        // another facing: yaw 90 faces +y, so its left is -x (the chooser's cone uses the same yaw: feat/sh_look.lua L.SetFacing)
        id = make(SA1_CHAR_SONIC, 90.0);
        pairs(id, 10);
        Val st = Val::table();
        L.call("GetState", {Val::number(id), st});
        double yaw = field_num(st, "yaw");
        look_point(id, -200.0, 0.0, z);
        pairs(id, 2);
        state_of(id);
        double left = field_num(out, "head_y");
        look_point(id, 0.0, 200.0, z);
        pairs(id, 2);
        state_of(id);
        double ah = field_num(out, "head_y");
        CHECK(close_to(yaw, 90.0, 0.5) && close_to(left, 45.0) && std::fabs(ah) < 6.0,
              "created with yaw 90: state.yaw %g, -x is its left (head_y %+g), +y straight ahead (%+g)", yaw, left, ah);
        L.call("Destroy", {Val::number(id)});
    }

    // ---- ANGLES -----------------------------------------------------------------------------------------------------------------------
    {
        double id = make(SA1_CHAR_KNUCKLES);
        pairs(id, 10);
        std::vector<Val> a = L.call("Look", {Val::number(id), Val::number(kAngles), Val::number(30), Val::number(0)});
        pairs(id, 2);
        state_of(id);
        double y30 = field_num(out, "head_y"), kd = field_num(out, "kind");
        std::vector<Val> b = L.call("Look", {Val::number(id), Val::number(kAngles), Val::number(0), Val::number(20)});
        pairs(id, 2);
        state_of(id);
        double p20 = field_num(out, "head_z");
        CHECK(is_true(a) && is_true(b) && close_to(y30, 30.0, 0.05) && kd == kAngles && close_to(p20, -20.0, 0.05),
              "ANGLES: yaw +30 -> head_y %+g (the character's left), kind %g; pitch +20 -> head_z %+g (+ pitch = up, + z = down)", y30, kd, p20);
        L.call("Destroy", {Val::number(id)});
    }

    // ---- CAMERA: the game's Z look at the camera passed to gsa1.Tick -------------------------------------------------------------------
    {
        Val thc = g.tab->field("TICK_HOST_CAMERA");
        CHECK(thc.type == Type::Bool && thc.b, "gsa1.TICK_HOST_CAMERA: libsa1 takes the host camera");
        double id = make(SA1_CHAR_TAILS);
        pairs(id, 10);
        auto cam_pairs = [&](int n, float cx, float cy) {
            for (int i = 0; i < n; i++) {
                L.call("Tick", {Val::number(id), Val::number(0), Val::number(0), Val::number(0), Val::number(0), Val::number(1.0 / 30.0),
                                Val::boolean(false), Val::number(0), Val::vector(cx, cy, 8.0f + (float)kEyes),
                                Val::vector(0.0f, 0.0f, 8.0f + (float)kEyes)});
            }
        };
        std::vector<Val> a = L.call("Look", {Val::number(id), Val::number(kCamera)});
        cam_pairs(3, 0.0f, 300.0f);
        state_of(id);
        double left = field_num(out, "head_y"), kd = field_num(out, "kind"), ow = field_num(out, "owner");
        cam_pairs(3, 0.0f, -300.0f);
        state_of(id);
        double right = field_num(out, "head_y");
        L.call("Look", {Val::number(id), Val::number(kOff)});
        cam_pairs(3, 0.0f, -300.0f);
        state_of(id);
        double off = field_num(out, "head_y");
        CHECK(is_true(a) && close_to(left, 33.75) && close_to(right, -33.75) && kd == kCamera && ow == 0 && close_to(off, 0.0),
              "CAMERA on Tails, the camera at its left: head_y %+g, kind %g, owner %g; at its right: %+g; OFF: %+g", left, kd, ow, right, off);
        L.call("Destroy", {Val::number(id)});
    }

    // ---- E-102: no look task in the game ----------------------------------------------------------------------------------------------
    {
        double id = make(SA1_CHAR_GAMMA);
        pairs(id, 3);
        std::vector<Val> a = look_point(id, 0.0, 200.0, 36.0);
        CHECK(is_false_msg(a, "unsupported"), "E-102: false, \"%s\", \"%s\"", str_of(a, 1).c_str(), str_of(a, 2).c_str());
        rec("reason\tunsupported\t" + str_of(a, 1));
        L.call("Destroy", {Val::number(id)});
    }

    // ---- no table per call, on the mock's stack -------------------------------------------------------------------------------------------
    {
        uint64_t t0 = L.tables;
        auto c0 = std::chrono::steady_clock::now();
        for (int i = 0; i < 1000; i++) {
            look_point(sonic, 0.0, 200.0 + i * 0.01, 36.0);
        }
        double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - c0).count();
        uint64_t t1 = L.tables;
        for (int i = 0; i < 1000; i++) {
            state_of(sonic);
        }
        CHECK(t1 == t0 && L.tables == t1, "gsa1.Look x 1000 and LookState(id, out) x 1000 make no table (%llu, %llu)",
              (unsigned long long)(t1 - t0), (unsigned long long)(L.tables - t1));
        std::printf("  info  gsa1.Look: %.2f us a call through the mock's stack\n", ms);
        L.call("Look", {Val::number(sonic), Val::number(kOff)});
    }

    // ---- COPT_SUPER_LOOK: option 1 against option 0 at the same steps (review R.13) ------------------------------------------------------
    {
        double a = make(8), b = make(8), c = make(8);
        bool made = a > 0 && b > 0 && c > 0;
        std::vector<Val> o1 = L.call("SetCharOption", {Val::number(a), Val::number(SA1_COPT_SUPER_LOOK), Val::number(1)});
        CHECK(made && is_true(o1), "gsa1.SetCharOption(kind 8, gsa1.COPT_SUPER_LOOK, 1): true (%s)", str_of(o1, 1).c_str());
        for (int p = 0; p < 40; p++) {
            for (double id : {a, b, c}) {
                if (p == 20) look_point(id, 0.0, 200.0, 36.0);
                pair(id);
            }
        }
        for (double id : {a, b, c}) {
            L.call("Render", {Val::number(id), Val::number(1.0)});
        }
        gsa1::Character *ca = se->get((int32_t)a), *cb = se->get((int32_t)b), *cc = se->get((int32_t)c);
        int differ = ca && cb ? differing_triangles(*ca, *cb, 0.01f) : -1;
        int control = cb && cc ? differing_triangles(*cb, *cc, 0.01f) : -1;
        CHECK(differ >= 400 && control == 0, "kind 8 looking left: option 1 against option 0 at the same steps: %d of %u triangles differ (at "
              "least 400); two worlds at option 0: %d", differ, ca ? ca->r_triangles : 0u, control);
        for (double id : {a, b, c}) {
            L.call("Destroy", {Val::number(id)});
        }
        double t = make(SA1_CHAR_TAILS);
        std::vector<Val> o2 = L.call("SetCharOption", {Val::number(t), Val::number(SA1_COPT_SUPER_LOOK), Val::number(1)});
        CHECK(is_nil_msg(o2), "on Tails: nil, \"%s\" (kind 8 and super-capable Sonic worlds only)", str_of(o2, 1).c_str());
        L.call("Destroy", {Val::number(t)});
    }

    // ---- the follower case (098 plan 6.8: after lanes/followmod_real.txt) -------------------------------------------------------------------
#if defined(SA1_API_FOLLOWER)
    {
        Val fc = g.tab->field("FollowerCreate");
        std::vector<Val> made;
        double leader = make(SA1_CHAR_SONIC);
        if (fc.type == Type::Function) {
            const float pos[3] = {-100.0f, 0.0f, 8.0f};
            made = L.call("FollowerCreate", {Val::number(SA1_CHAR_TAILS), Val::vector(pos[0], pos[1], pos[2]), Val::number(0), Val::number(leader),
                                             Val::table()});
        }
        double fid = made.size() >= 1 && made[0].type == Type::Number ? made[0].num : -1.0;
        if (fid <= 0) {
            // only the gate's own answer skips: any other refusal is a failure of the follower case
            bool not_built = fc.type != Type::Function || str_of(made, 1).find("not built yet") != std::string::npos;
            if (not_built) {
                std::printf("SKIP behaviour: follower is not built yet\n");
            } else {
                CHECK(false, "the follower case: FollowerCreate(Tails): %s (%s)", str_of(made, 1).c_str(), str_of(made, 2).c_str());
            }
            write_api("RAN\tthe follower case did not run");
            return finish();
        }
        Val tick_out = Val::table();
        auto fpairs = [&](int n) {
            for (int i = 0; i < n; i++) {
                pair(leader);
                L.call("FollowersTick", {Val::number(1.0 / 30.0), Val::number(0), Val(), Val(), tick_out});
            }
        };
        fpairs(10);
        Val st = Val::table();
        L.call("GetState", {Val::number(fid), st});
        double fx = field_num(st, "x"), fy = field_num(st, "y"), fz = field_num(st, "z"), fyaw = field_num(st, "yaw") * 3.14159265358979 / 180.0;
        // its left: 90 degrees from its facing, far enough for a follower that moves on a little
        std::vector<Val> a = look_point(fid, fx - std::sin(fyaw) * 400.0, fy + std::cos(fyaw) * 400.0, fz + kEyes);
        fpairs(2);
        state_of(fid);
        double left = field_num(out, "head_y"), kd = field_num(out, "kind"), ow = field_num(out, "owner");
        CHECK(is_true(a) && close_to(left, 33.75) && kd == kPoint && ow == 1,
              "a Tails follower looking left: its LookState head_y %+g (want +33.75), kind %g, owner %g (%s)", left, kd, ow, str_of(a, 1).c_str());
        std::vector<Val> b = L.call("Look", {Val::number(fid), Val::number(kCamera)});
        fpairs(2);
        state_of(fid);
        double ck = field_num(out, "kind");
        L.call("Look", {Val::number(fid), Val::number(kOff)});
        fpairs(2);
        state_of(fid);
        double off = field_num(out, "head_y");
        CHECK(is_true(b) && ck == kCamera && close_to(off, 0.0, 12.0), "LOOK_CAMERA reaches the follower (kind %g); OFF: head_y %+g (the game's own "
              "lead into a curve may remain)", ck, off);
        L.call("Destroy", {Val::number(fid)});
        L.call("Destroy", {Val::number(leader)});
    }
#else
    std::printf("SKIP behaviour: follower is not built yet\n");
#endif
    write_api("RAN\tall");
    L.call("Destroy", {Val::number(sonic)});
    return finish();
#endif  // SA1_API_LOOK
}
