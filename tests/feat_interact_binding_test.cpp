// feat_interact_binding_test: the interaction feature's Lua functions (src/module/bind_interact.cpp; plan
// gsa1_rounds_plan.md 9.3). build.py links it like binding_test - the module's objects and the mock Lua stack of
// tests/mock_lua.hpp - and runs it with --gdi GAME.gdi when there is one.
//
//   feat_interact_binding_test [--gdi GAME.gdi] [--gm GARRYSMOD_DIR] [--verbose]
//
// Without the disc: gsa1.FEATURES.interact, the 16 functions, gsa1.INTERACT against libsa1.h and against the addon's own
// table (addon/lua/gsa1/feat/sh_interact.lua I.K, which the server uses without the module), bad arguments answered with
// nil / false and a message (never a Lua error), the table shapes of ObjEvents / Contacts / ObjInfo without a world,
// "not_ready" before the disc. With the disc, through the module the way the addon calls it, on gm_construct (fed the
// addon's way, read-only from Garry's Mod's own files): Sonic at the map's player start; a "zombie" registered as the
// addon registers an NPC (its OBB: a cylinder at the OBB's centre, entity index 4242) ahead of him; he runs and jumps on
// it: ObjEvents has a HIT naming entity 4242, the jump (SPIN), BOUNCED, the score +10 in StateEx; ObjMove / ObjAdd of
// an unchanged object are not sent again (ObjInfo); a physics crate as a moving object (ShapeBox + MoverUpdate, entity
// 777) he runs into: Contacts names entity 777 with side contacts and an approach speed; Damage from behind with
// FACE_SOURCE: a HURT event (14), the rings gone from StateEx; AddRings; SetCharOption NO_DEATH; ObjHeld nil when nothing
// is held; ObjClear.
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

#include "../src/core/bsp.hpp"
#include "../src/core/config.hpp"
#include "../src/core/util.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

#include "gamefs.hpp"
#include "mock_lua.hpp"
#include "../src/module/gsa1_feature.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

static bool g_verbose = false;

static double numf(const Val &t, const char *k)
{
    return t.type == Type::Table ? t.tab->field(k).num : -1e300;
}

static std::vector<Val> obj_add_args(double ent, double kind, double flags, float x, float y, float z, double form, float cx,
                                     float cy, float cz, float sx, float sy, float sz)
{
    return {Val::number(ent), Val::number(kind), Val::number(flags), Val::number(x), Val::number(y), Val::number(z),
            Val::number(0), Val::number(-1), Val::number(-1), Val::number(0), Val::number(1), Val::number(form),
            Val::number(cx), Val::number(cy), Val::number(cz), Val::number(sx), Val::number(sy), Val::number(sz),
            Val::number(0), Val::number(0)};
}

// the addon's I.K table: "NAME = value" pairs between "I.K = {" and the closing "}"
static std::map<std::string, double> addon_constants(const std::string &path)
{
    std::map<std::string, double> out;
    std::string text, err;
    if (!gsa1::read_small_file(path, 1u << 20, text, err)) {
        return out;
    }
    size_t a = text.find("I.K = {");
    size_t b = a == std::string::npos ? a : text.find("\n}", a);
    if (a == std::string::npos || b == std::string::npos) {
        return out;
    }
    std::string body = text.substr(a + 7, b - a - 7);
    size_t i = 0;
    while (i < body.size()) {
        while (i < body.size() && !(std::isalpha((unsigned char)body[i]) || body[i] == '_')) {
            i++;
        }
        size_t s = i;
        while (i < body.size() && (std::isalnum((unsigned char)body[i]) || body[i] == '_')) {
            i++;
        }
        std::string name = body.substr(s, i - s);
        while (i < body.size() && body[i] == ' ') {
            i++;
        }
        if (name.empty() || i >= body.size() || body[i] != '=') {
            continue;
        }
        i++;
        while (i < body.size() && body[i] == ' ') {
            i++;
        }
        size_t vs = i;
        while (i < body.size() && (std::isxdigit((unsigned char)body[i]) || body[i] == 'x')) {
            i++;
        }
        out[name] = (double)std::strtol(body.substr(vs, i - vs).c_str(), nullptr, 0);
    }
    return out;
}

// gm_construct fed the addon's way (as feat_surfaces_binding_test does)
static std::string load_map(MockLua &L, const std::string &map, gamefs::GameFs &fs)
{
    Val o = Val::table();
    o.tab->set(Val::string("cache"), Val::boolean(true));
    auto r = L.call("MapStartData", {Val::string("gm_construct"), Val::string(map.substr(0, 1036)),
                                     Val::number((double)map.size()), o});
    if (r.size() < 1 || r[0].type != Type::Bool || !r[0].b) {
        return "MapStartData: " + str_of(r, 1);
    }
    Val poll = Val::table();
    std::string state;
    for (int polls = 0; polls < 2000000; polls++) {
        r = L.call("MapPoll", {poll});
        if (r.size() != 1 || r[0].type != Type::Table) {
            return "MapPoll: no job";
        }
        state = r[0].tab->field("state").str;
        if (state == "ready" || state == "failed") {
            break;
        }
        Val needs = r[0].tab->field("needs"), fl = r[0].tab->field("files");
        for (double i = 1; needs.type == Type::Table && needs.tab->at(i).type == Type::Table; i++) {
            double ofs = needs.tab->at(i).tab->field("ofs").num, len = needs.tab->at(i).tab->field("len").num;
            L.call("MapFeed", {Val::number(ofs), Val::string(map.substr((size_t)ofs, (size_t)len))});
        }
        for (double i = 1; fl.type == Type::Table && fl.tab->at(i).type == Type::Table; i++) {
            std::string path = fl.tab->at(i).tab->field("path").str, data;
            uint32_t max = (uint32_t)fl.tab->at(i).tab->field("max").num;
            bool ok = fs.read(path, data, max);
            L.call("MapFeedFile", {Val::string(path), ok ? Val::string(data) : Val()});
        }
        if (state != "reading" && state != "files") {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }
    if (state != "ready") {
        return "the map job: " + state;
    }
    r = L.call("MapApply", {});
    if (r.size() < 1 || r[0].type != Type::Bool || !r[0].b) {
        return "MapApply: " + str_of(r, 1);
    }
    return std::string();
}

static bool player_start(const std::string &map_path, float pos[3], float &yaw_deg)
{
    gsa1::FileByteSource src;
    std::string e;
    gsa1::Bsp bsp;
    std::vector<gsa1::BspEntity> ents;
    if (!src.open(map_path, e) || !bsp.open(src, e) || !bsp.entities(ents, e)) {
        return false;
    }
    for (const gsa1::BspEntity &en : ents) {
        const std::string *cls = en.get("classname");
        float ang[3] = {0, 0, 0};
        if (cls && *cls == "info_player_start" && en.get_vec3("origin", pos)) {
            en.get_vec3("angles", ang);
            yaw_deg = ang[1];
            return true;
        }
    }
    return false;
}

// one pair per call (1/30 s), the camera along yaw
static Val tick(MockLua &L, double id, double sy, double yaw, double buttons)
{
    auto r = L.call("Tick", {Val::number(id), Val::number(0), Val::number(sy), Val::number(yaw), Val::number(buttons),
                             Val::number(1.0 / 30.0)});
    return r.empty() ? Val() : r[0];
}

int main(int argc, char **argv)
{
    std::string gdi, gm = gsa1_garrysmod_dir();
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--gdi" && i + 1 < argc) gdi = argv[++i];
        else if (a == "--gm" && i + 1 < argc) gm = argv[++i];
        else if (a == "--verbose") g_verbose = true;
    }
    std::printf("G-SA1 feat_interact_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_interact_appdata");
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
    static const char *kFns[] = {"ObjAdd", "ObjUpdate", "ObjMove", "ObjRemove", "ObjClear", "ObjEvents", "ObjConfig",
                                 "ObjHeld", "ObjRelease", "ObjWorldMask", "ObjInfo", "Damage", "SetCharOption", "AddRings",
                                 "StateEx", "Contacts"};
    int fns = 0;
    for (const char *n : kFns) {
        fns += g.type == Type::Table && g.tab->field(n).type == Type::Function;
    }
    Val errs = g.type == Type::Table ? g.tab->field("FEATURE_ERRORS") : Val();
    CHECK(g.type == Type::Table && feats.type == Type::Table && feats.tab->field("interact").num == 2 && fns == 16 &&
              errs.type == Type::Table && errs.tab->at(1).type == Type::Nil && L.st.empty(),
          "gsa1.FEATURES.interact = %g; the 16 functions registered, no clash with the built-in ones",
          feats.type == Type::Table ? feats.tab->field("interact").num : -1.0);
    if (g.type != Type::Table) return 1;
    Val C = g.tab->field("INTERACT");
    bool lib_ok = C.type == Type::Table && numf(C, "ENEMY") == SA1_HOSTOBJ_ENEMY && numf(C, "BALLOON") == SA1_HOSTOBJ_BALLOON &&
                  numf(C, "HOLDABLE") == SA1_HOSTOBJ_HOLDABLE && numf(C, "KEEP_HSPEED") == SA1_HOSTOBJ_KEEP_HSPEED &&
                  numf(C, "EVENT_RELEASED") == SA1_HOSTOBJ_EVENT_RELEASED && numf(C, "BOX") == SA1_SHAPE_BOX &&
                  numf(C, "CONTACT_HEAD") == SA1_CONTACT_HEAD && numf(C, "COPT_NO_DAMAGE") == SA1_COPT_NO_DAMAGE &&
                  numf(C, "EVENT_HURT") == SA1_EVENT_HURT;
    // the addon's copy (the server has no module)
    // the source tree: this file's own directory's parent (build.py compiles it by its absolute path)
    std::string root = gsa1::parent_dir(gsa1::parent_dir(__FILE__));
    std::string addon = gsa1::join_path(gsa1::join_path(gsa1::join_path(gsa1::join_path(root, "addon"), "lua"), "gsa1"),
                                        gsa1::join_path("feat", "sh_interact.lua"));
    std::map<std::string, double> ak = addon_constants(addon);
    int compared = 0, differ = 0;
    std::string diff;
    for (const auto &kv : ak) {
        Val v = C.type == Type::Table ? C.tab->field(kv.first.c_str()) : Val();
        if (v.type != Type::Number) {
            continue;
        }
        compared++;
        if (v.num != kv.second) {
            differ++;
            diff += " " + kv.first;
        }
    }
    CHECK(lib_ok && compared >= 50 && differ == 0,
          "gsa1.INTERACT = libsa1.h's numbers; the addon's own table (sh_interact.lua I.K, the server's) agrees in all %d "
          "it shares%s", compared, differ ? (": differ" + diff).c_str() : "");
    // bad arguments
    int answered = 0;
    answered += is_nil_msg(L.call("ObjAdd", {Val::number(5)}));
    answered += is_nil_msg(L.call("ObjAdd", obj_add_args(0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0)));      // entity 0
    answered += is_nil_msg(L.call("ObjAdd", obj_add_args(5, 1, 0, 0, 0, 0, 0, 0, 0, 0, NAN, 0, 0)));     // NaN size
    std::vector<Val> two = obj_add_args(5, 1, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0);
    two[10] = Val::number(2);                                                                             // 2 shapes, 1 given
    answered += is_nil_msg(L.call("ObjAdd", two));
    answered += is_nil_msg(L.call("ObjMove", {Val::number(5), Val::string("x")}));
    answered += is_nil_msg(L.call("ObjConfig", {Val::number(99)}));
    answered += is_nil_msg(L.call("Damage", {Val::number(77), Val::number(0), Val::number(0), Val::number(0), Val::number(0)}));
    answered += is_nil_msg(L.call("SetCharOption", {Val::number(77), Val::number(1), Val::number(1)}));
    answered += is_nil_msg(L.call("AddRings", {Val::number(77), Val::number(5000)}));
    answered += is_nil_msg(L.call("ObjRelease", {Val::number(5)}));
    answered += is_nil_msg(L.call("ObjWorldMask", {Val::string("a")}));
    auto nr = L.call("ObjAdd", obj_add_args(5, 1, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0));
    auto se = L.call("StateEx", {Val::number(77)});
    auto he = L.call("ObjHeld", {Val::number(77)});
    auto ev = L.call("ObjEvents", {});
    auto co = L.call("Contacts", {Val::number(77)});
    auto in = L.call("ObjInfo", {});
    auto rm = L.call("ObjRemove", {Val::number(5)});
    CHECK(answered == 11 && is_nil_msg(nr) && str_of(nr, 2) == "not_ready" && se.size() == 1 && se[0].type == Type::Nil &&
              he.size() == 1 && he[0].type == Type::Nil && ev.size() == 1 && numf(ev[0], "count") == 0 && co.size() == 1 &&
              numf(co[0], "count") == 0 && in.size() == 1 && numf(in[0], "registered") == 0 && rm.size() == 1 &&
              rm[0].type == Type::Bool && !rm[0].b && L.st.empty(),
          "%d of 11 bad calls answered with nil / false + a message (no Lua error); before the disc ObjAdd says not_ready; "
          "StateEx / ObjHeld of no character nil; ObjEvents / Contacts {count = 0}; ObjInfo {registered = 0}", answered);

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the checks through the game need the disc\n");
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    std::string bsp = gsa1::join_path(gsa1::join_path(gm, "maps"), "gm_construct.bsp"), map, err;
    float spawn[3] = {0, 0, 0};
    float syaw = 0;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || !player_start(bsp, spawn, syaw)) {
        std::printf("  info  %s is missing or has no player start: the map checks are skipped\n", bsp.c_str());
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    gsa1::make_dirs(fake_appdata);
    gsa1::Config cfg;
    cfg.disc = gdi;
    CHECK(gsa1::save_config(cfg, err), "config written to the scratch APPDATA (%s)", err.c_str());
    L.call("Init", {});
    std::string st = "loading";
    for (int polls = 0; st == "loading" && polls < 30000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        st = str_of(L.call("InitPoll", {}), 0);
    }
    gamefs::GameFs fs(gm);
    fs.set_map(bsp);
    std::string e = st == "ready" ? load_map(L, map, fs) : "the disc: " + st;
    CHECK(e.empty(), "the disc and gm_construct loaded the addon's way (%s)", e.c_str());
    if (!e.empty()) {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    auto cr = L.call("Create", {Val::number(SA1_CHAR_SONIC), Val::vector(spawn[0], spawn[1], spawn[2] + 32.0f),
                                Val::number(syaw)});
    double id = cr.size() >= 1 && cr[0].type == Type::Number ? cr[0].num : 0;
    CHECK(id > 0, "Sonic at gm_construct's player start (%.0f %.0f %.0f), facing %.0f degrees (%s)", spawn[0], spawn[1],
          spawn[2], syaw, str_of(cr, 1).c_str());
    if (id <= 0) {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    Val state_t = Val::table();
    for (int i = 0; i < 30; i++) {
        tick(L, id, 0, syaw, 0);
    }
    L.call("GetState", {Val::number(id), state_t});
    float sx = (float)numf(state_t, "x"), sy = (float)numf(state_t, "y"), sz = (float)numf(state_t, "z");
    double yr = syaw * 3.14159265358979 / 180.0;
    float fx = (float)std::cos(yr), fy = (float)std::sin(yr);
    // the zombie: 32 x 32 x 72, registered at its OBB's centre with a cylinder (r 0.4 x the mean width, half height 36)
    float zx = sx + 120.0f * fx, zy = sy + 120.0f * fy, zz = sz + 36.0f;
    auto za = L.call("ObjAdd", obj_add_args(4242, SA1_HOSTOBJ_ENEMY, SA1_HOSTOBJ_SOLID, zx, zy, zz, SA1_SHAPE_CYLINDER, 0, 0,
                                            0, 12.8f, 36.0f, 0));
    auto zb = L.call("ObjAdd", obj_add_args(4242, SA1_HOSTOBJ_ENEMY, SA1_HOSTOBJ_SOLID, zx, zy, zz, SA1_SHAPE_CYLINDER, 0, 0,
                                            0, 12.8f, 36.0f, 0));
    L.call("ObjMove", {Val::number(4242), Val::number(zx), Val::number(zy), Val::number(zz), Val::number(0)});
    auto i1 = L.call("ObjInfo", {Val::number(id)});
    CHECK(za.size() == 2 && za[0].type == Type::Number && za[1].b && zb.size() == 2 && zb[0].num == za[0].num && !zb[1].b &&
              numf(i1[0], "registered") == 1 && numf(i1[0], "unchanged") == 1 && numf(i1[0], "moves_skipped") == 1,
          "a zombie (entity 4242) registered 120 units ahead (id %g); the same ObjAdd again and an unchanged ObjMove are "
          "not sent", za.empty() ? 0.0 : za[0].num);
    Val evs = Val::table();
    double hit_ent = 0, hit_attack = -1, hit_flags = 0, events = 0;
    bool jumped = false;
    for (int i = 0; i < 150 && hit_ent == 0; i++) {
        L.call("GetState", {Val::number(id), state_t});
        double px = numf(state_t, "x") - sx, py = numf(state_t, "y") - sy;
        double along = px * fx + py * fy;
        double b = 0;
        if (!jumped && along >= 120.0 - 40.0) {
            b = 1;
            jumped = true;
        }
        tick(L, id, 1, syaw, b);
        L.call("ObjEvents", {evs});
        for (double k = 1; k <= numf(evs, "count"); k++) {
            Val ev1 = evs.tab->at(k);
            events++;
            if (numf(ev1, "type") == SA1_HOSTOBJ_EVENT_HIT && hit_ent == 0) {
                hit_ent = numf(ev1, "ent");
                hit_attack = numf(ev1, "attack");
                hit_flags = numf(ev1, "flags");
            }
        }
    }
    for (int i = 0; i < 4; i++) {
        tick(L, id, 0, syaw, 0);
    }
    Val sx_t = Val::table();
    L.call("StateEx", {Val::number(id), sx_t});
    CHECK(hit_ent == 4242 && hit_attack == SA1_ATTACK_SPIN && ((uint32_t)hit_flags & SA1_HITF_BOUNCED) &&
              numf(sx_t, "score") == 10,
          "he runs and jumps on it on gm_construct: ObjEvents has a HIT naming entity %g, attack %g (SPIN), flags 0x%X "
          "(BOUNCED); StateEx score %g (+10 from the game's damage check)", hit_ent, hit_attack, (unsigned)hit_flags,
          numf(sx_t, "score"));
    L.call("ObjRemove", {Val::number(4242), Val::boolean(true)});
    // a physics crate (64 x 64 x 48) as a moving object, entity 777, 160 units ahead of where he stands now
    for (int i = 0; i < 20; i++) {
        tick(L, id, 0, syaw, 0);
    }
    L.call("GetState", {Val::number(id), state_t});
    float cx = (float)numf(state_t, "x") + 200.0f * fx, cy = (float)numf(state_t, "y") + 200.0f * fy,
          cz = (float)numf(state_t, "z");
    auto sb = L.call("ShapeBox", {Val::string("x:crate"), Val::vector(-32, -32, 0), Val::vector(32, 32, 48)});
    Val cont = Val::table();
    double side = 0, vin = 0, ents_other = 0;
    for (int i = 0; i < 120; i++) {
        L.call("MoverUpdate", {Val::number(777), Val::string("x:crate"), Val::vector(cx, cy, cz), Val::angle(0, syaw, 0),
                               Val::boolean(true)});
        L.call("MoverCommit", {});
        tick(L, id, 1, syaw, 0);
        L.call("Contacts", {Val::number(id), cont});
        for (double k = 1; k <= numf(cont, "count"); k++) {
            Val c1 = cont.tab->at(k);
            if (numf(c1, "ent") != 777) {
                ents_other++;
                continue;
            }
            side += numf(c1, "side");
            vin = std::max(vin, numf(c1, "vin"));
            if (g_verbose && numf(c1, "first") > 0) {
                std::printf("        first contact at pair %d: vin %.0f, normal %.2f %.2f %.2f, velocity %.0f %.0f %.0f\n", i,
                            numf(c1, "vin"), numf(c1, "nx"), numf(c1, "ny"), numf(c1, "nz"), numf(c1, "vx"),
                            numf(c1, "vy"), numf(c1, "vz"));
            }
        }
        if (g_verbose && i % 10 == 0) {
            L.call("GetState", {Val::number(id), state_t});
            std::printf("        crate run pair %d: %.0f %.0f %.0f (the crate at %.0f %.0f %.0f), speed %.0f %.0f\n", i,
                        numf(state_t, "x"), numf(state_t, "y"), numf(state_t, "z"), cx, cy, cz, numf(state_t, "vx"),
                        numf(state_t, "vy"));
        }
    }
    CHECK(sb.size() >= 1 && sb[0].b && side > 20 && vin > 0 && ents_other == 0,
          "he runs into a crate (a moving object of entity 777): Contacts names entity 777 - %g side contact steps, the "
          "largest approach speed %.0f HU/s (he slowed down before reaching it here, cause not "
          "examined; feat_interact_test measures the full run speed on a flat floor) - and nothing else", side, vin);
    // the character's side
    L.call("AddRings", {Val::number(id), Val::number(5)});
    tick(L, id, 0, syaw, 0);
    L.call("StateEx", {Val::number(id), sx_t});
    double rings5 = numf(sx_t, "rings");
    L.call("GetState", {Val::number(id), state_t});
    double bx = numf(state_t, "x") - 100.0 * fx, by = numf(state_t, "y") - 100.0 * fy, bz = numf(state_t, "z") + 20.0;
    auto dm = L.call("Damage", {Val::number(id), Val::number(SA1_DAMAGE_FACE_SOURCE), Val::number(bx), Val::number(by),
                                Val::number(bz)});
    double hurt = 0, hurt_arg = 0;
    Val pe = Val::table();
    for (int i = 0; i < 8; i++) {
        tick(L, id, 0, syaw, 0);
        L.call("PollEvents", {pe});
        for (double k = 1; k <= numf(pe, "count"); k++) {
            Val e1 = pe.tab->at(k);
            if (numf(e1, "type") == SA1_EVENT_HURT && hurt == 0) {
                hurt = 1;
                hurt_arg = numf(e1, "arg");
            }
        }
    }
    L.call("StateEx", {Val::number(id), sx_t});
    CHECK(rings5 == 5 && dm.size() == 1 && dm[0].b && hurt == 1 && ((uint32_t)hurt_arg & 0xFFFF) == 5 &&
              numf(sx_t, "rings") < 5 && numf(sx_t, "invuln") > 0 && numf(sx_t, "hurt_steps") >= 0,
          "AddRings 5 -> StateEx rings %g; Damage from behind (FACE_SOURCE): a HURT event (rings lost %u), rings %g, "
          "invulnerable %g steps", rings5, (unsigned)((uint32_t)hurt_arg & 0xFFFF), numf(sx_t, "rings"), numf(sx_t, "invuln"));
    auto o1 = L.call("SetCharOption", {Val::number(id), Val::number(SA1_COPT_NO_DEATH), Val::number(1)});
    auto o2 = L.call("SetCharOption", {Val::number(id), Val::number(99), Val::number(1)});
    auto hd = L.call("ObjHeld", {Val::number(id)});
    auto cf = L.call("ObjConfig", {Val::number(48)});
    L.call("ObjAdd", obj_add_args(10, SA1_HOSTOBJ_TARGET, 0, cx, cy, cz + 20, SA1_SHAPE_BOX, 0, 0, 0, 30, 30, 20));
    auto cl = L.call("ObjClear", {});
    auto i2 = L.call("ObjInfo", {});
    CHECK(o1.size() == 1 && o1[0].b && is_nil_msg(o2) && hd.size() == 1 && hd[0].type == Type::Nil && cf.size() == 1 &&
              cf[0].b && cl.size() == 1 && cl[0].num == 1 && numf(i2[0], "registered") == 0 && L.st.empty(),
          "SetCharOption NO_DEATH (an unknown option refused), ObjHeld nil with nothing held, ObjConfig 48, ObjClear "
          "removes what is registered");
    if (g_verbose) {
        std::printf("  info  %g host object events in the run\n", events);
    }
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
