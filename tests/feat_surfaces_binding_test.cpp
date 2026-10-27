// feat_surfaces_binding_test: the surfaces feature's Lua functions (src/module/bind_surfaces.cpp; sadc
// docs/research/gsa1_060_dig.md F6 with its Review R4 G3 / G10). build.py links it like binding_test - the module's
// objects and the mock Lua stack of tests/mock_lua.hpp - and runs it with --gdi GAME.gdi when there is one.
//
//   feat_surfaces_binding_test [--gdi GAME.gdi] [--gm GARRYSMOD_DIR]
//
// Without the disc: gsa1.FEATURES.surfaces, SetSurfaceTable's round trip (entries taken and skipped, the hash, "changed"
// only when it changes), SurfaceDefaults, SurfaceKind (listed, through a letter, an owner's entry, off), SurfaceInfo nil
// before a map, bad arguments answered without a Lua error. With the disc: gm_construct fed the addon's way (MapStartData,
// MapPoll / MapFeed / MapFeedFile with the materials from Garry's Mod's own files, read-only), MapApply, SurfaceInfo
// (the map's types by area: grass first and diggable), a physics prop's shape (ShapePhy) with its .phy's surface type -
// slippery but never diggable - dropped and built again when the table changes, and the map loaded again with the
// changed table (its classes in SurfaceInfo; outside garrysmod/lua/bin the module has no cache directory, so this
// rebuilds: map_test checks the cache hit). 0.9.2 (feature version 2; gsa1_090_surfaces.md F2 with its Review C3):
// SetSurfaceTable takes every SA1 ground kind's word, SurfaceKind prints them in the module's order, and on
// gm_construct "concrete = noland" reaches the walls only (SurfaceInfo walls.noland > 0, walkable noland 0).
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
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

#include "gamefs.hpp"
#include "mock_lua.hpp"
#include "../src/module/gsa1_feature.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

static Val list_of(std::initializer_list<const char *> items)
{
    Val t = Val::table();
    double i = 1;
    for (const char *s : items) {
        t.tab->set(Val::number(i++), Val::string(s));
    }
    return t;
}

static Val opts(bool enabled, bool anywhere)
{
    Val t = Val::table();
    t.tab->set(Val::string("enabled"), Val::boolean(enabled));
    t.tab->set(Val::string("dig_anywhere"), Val::boolean(anywhere));
    return t;
}

// gm_construct fed the addon's way; the files from Garry's Mod's own file system (read-only)
static std::string load_map(MockLua &L, const std::string &map, gamefs::GameFs &fs, int &files_fed)
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
            files_fed++;
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

static const Val *find_type(const Val &info, const char *name, int *index = nullptr)
{
    static Val found;
    Val types = info.tab->field("types");
    for (double i = 1; types.type == Type::Table && types.tab->at(i).type == Type::Table; i++) {
        if (types.tab->at(i).tab->field("name").str == name) {
            found = types.tab->at(i);
            if (index) {
                *index = (int)i;
            }
            return &found;
        }
    }
    return nullptr;
}

int main(int argc, char **argv)
{
    std::string gdi, gm = gsa1_garrysmod_dir();
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
        else if (std::string(argv[i]) == "--gm") gm = argv[++i];
    }
    std::printf("G-SA1 feat_surfaces_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    // a private configuration directory (the module reads the disc's path from it)
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_surfaces_appdata");
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
    CHECK(g.type == Type::Table && feats.type == Type::Table && feats.tab->field("surfaces").num == 2 &&
              g.tab->field("SetSurfaceTable").type == Type::Function && g.tab->field("SurfaceInfo").type == Type::Function &&
              L.st.empty(),
          "gsa1.FEATURES.surfaces = %g (2: 0.9.2's kinds); SetSurfaceTable, SurfaceDefaults, SurfaceKind, SurfaceInfo "
          "registered", feats.type == Type::Table ? feats.tab->field("surfaces").num : -1.0);
    if (g.type != Type::Table) return 1;

    // the table without a map
    auto r0 = L.call("SetSurfaceTable", {Val(), opts(true, false)});
    double h0 = r0.size() >= 2 ? r0[1].num : 0;
    auto r1 = L.call("SetSurfaceTable", {list_of({"concrete=dig", "grass=normal", "no equals sign", "lava=lava", "Ice = sand",
                                                  "../x=dig"}),
                                         opts(true, false)});
    auto r2 = L.call("SetSurfaceTable", {list_of({"concrete=dig", "grass=normal", "ice=sand"}), opts(true, false)});
    CHECK(r1.size() == 4 && r1[0].b && r1[1].num != h0 && r1[2].b && r1[3].num == 3 && r2.size() == 4 && r2[0].b &&
              r2[1].num == r1[1].num && !r2[2].b && r2[3].num == 0 && L.st.empty(),
          "SetSurfaceTable: 3 entries taken, 3 skipped (no '=', an unknown kind, a bad name); the hash changes with the "
          "table, and \"changed\" only when it does");
    auto k1 = L.call("SurfaceKind", {Val::string("concrete")});
    auto k2 = L.call("SurfaceKind", {Val::string("grass")});
    auto k3 = L.call("SurfaceKind", {Val::string("somemod_soil"), Val::string("d")});
    auto k4 = L.call("SurfaceKind", {Val::string("ice")});
    auto k5 = L.call("SurfaceKind", {Val::string("snow"), Val::number('J')});
    CHECK(str_of(k1, 0) == "dig" && str_of(k1, 1) == "listed" && str_of(k2, 0) == "normal" && str_of(k3, 0) == "dig" &&
              str_of(k3, 1) == "letter D" && str_of(k4, 0) == "sand" && str_of(k5, 0) == "dig",
          "SurfaceKind: concrete %s (the owner's entry), grass %s, an unknown type with letter D %s (%s), ice %s, snow %s",
          str_of(k1, 0).c_str(), str_of(k2, 0).c_str(), str_of(k3, 0).c_str(), str_of(k3, 1).c_str(), str_of(k4, 0).c_str(),
          str_of(k5, 0).c_str());
    // 0.9.2: every SA1 ground kind
    auto r3 = L.call("SetSurfaceTable", {list_of({"concrete=noland,fast", "ice=Snow, fast", "metal=speedpath+stairs",
                                                  "tile=wallslide|slide|footprints", "mud=snowboard"}),
                                         opts(true, false)});
    auto k7 = L.call("SurfaceKind", {Val::string("concrete")});
    auto k8 = L.call("SurfaceKind", {Val::string("ice")});
    auto k9 = L.call("SurfaceKind", {Val::string("metal")});
    auto k10 = L.call("SurfaceKind", {Val::string("tile")});
    CHECK(r3.size() == 4 && r3[0].b && r3[3].num == 1 && str_of(k7, 0) == "fast,noland" && str_of(k8, 0) == "snow,fast" &&
              str_of(k9, 0) == "speedpath,stairs" && str_of(k10, 0) == "slide,wallslide,footprints" && L.st.empty(),
          "0.9.2's kinds: 4 entries taken, 1 skipped (an unknown word); concrete %s, ice %s, metal %s, tile %s",
          str_of(k7, 0).c_str(), str_of(k8, 0).c_str(), str_of(k9, 0).c_str(), str_of(k10, 0).c_str());
    L.call("SetSurfaceTable", {list_of({"concrete=dig"}), opts(false, false)});
    auto k6 = L.call("SurfaceKind", {Val::string("grass")});
    auto d = L.call("SurfaceDefaults", {});
    bool defaults_ok = d.size() == 2 && d[0].type == Type::Table && d[0].tab->field("grass").str == "dig" &&
                       d[0].tab->field("ice").str == "slippery" && d[0].tab->field("carpet").str == "normal" &&
                       d[1].type == Type::Table && d[1].tab->field("J").str == "dig";
    CHECK(str_of(k6, 0) == "normal" && str_of(k6, 1) == "off" && defaults_ok,
          "ground types off: SurfaceKind says normal (off); SurfaceDefaults: grass dig, ice slippery, carpet normal, letter "
          "J dig");
    auto i0 = L.call("SurfaceInfo", {});
    int bad = 0;
    bad += is_nil_msg(L.call("SetSurfaceTable", {Val::string("concrete=dig")}));
    bad += is_nil_msg(L.call("SurfaceKind", {Val::number(5)}));
    bad += is_nil_msg(L.call("SurfaceKind", {Val::string(std::string(100, 'a'))}));
    CHECK(i0.size() == 1 && i0[0].type == Type::Nil && bad == 3 && L.st.empty(),
          "SurfaceInfo before a map: nil; %d of 3 bad calls answered with false / nil + message, no Lua error", bad);
    L.call("SetSurfaceTable", {Val(), opts(true, false)});

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the map checks need the disc\n");
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    std::string bsp = gsa1::join_path(gsa1::join_path(gm, "maps"), "gm_construct.bsp"), map, err;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err)) {
        std::printf("  info  %s is missing: the map checks are skipped\n", bsp.c_str());
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
    int files = 0;
    double t0 = gsa1::now_ms();
    std::string e = st == "ready" ? load_map(L, map, fs, files) : "the disc: " + st;
    double load_ms = gsa1::now_ms() - t0;
    auto info = L.call("SurfaceInfo", {});
    bool have = e.empty() && info.size() == 1 && info[0].type == Type::Table;
    const Val *grass = have ? find_type(info[0], "grass") : nullptr;
    Val first = have ? info[0].tab->field("types").tab->at(1) : Val();
    double walkable = have ? info[0].tab->field("walkable").num : 0, dig = have ? info[0].tab->field("dig").num : 0;
    CHECK(have && grass && first.type == Type::Table && first.tab->field("name").str == "grass" &&
              grass->tab->field("kinds").str == "dig" && grass->tab->field("chain").str.compare(0, 12, "grass > dirt") == 0 &&
              info[0].tab->field("materials").num > 100 && info[0].tab->field("vmt_found").num > 100 && dig > 0.8 * walkable,
          "gm_construct fed with %d files (%.1f s): SurfaceInfo - %g materials, the largest type %s (%s, %s), %.0f%% of the "
          "walkable ground diggable%s%s", files, load_ms / 1000.0, have ? info[0].tab->field("materials").num : 0.0,
          first.type == Type::Table ? first.tab->field("name").str.c_str() : "?",
          grass ? grass->tab->field("kinds").str.c_str() : "?", grass ? grass->tab->field("chain").str.c_str() : "?",
          walkable > 0 ? 100.0 * dig / walkable : 0.0, e.empty() ? "" : ": ", e.c_str());
    // a physics prop's shape with its .phy's surface type ("dirt" on the couch: diggable kinds never reach a moving object)
    std::string couch;
    gsa1::Session *se = gsa1::mod::session();
    if (se && fs.read("models/props_c17/furniturecouch001a.phy", couch)) {
        const char *key = "m:models/props_c17/furniturecouch001a.mdl";
        auto shape_words = [&](uint32_t &slip, uint32_t &digs, uint32_t &total) {
            slip = digs = total = 0;
            const gsa1::Shape *sh = se->movers().shape(key);
            for (size_t c = 0; sh && c < sh->chunks.size(); c++) {
                for (const sa1_collision_tri &t : sh->chunks[c].tris) {
                    total++;
                    slip += (t.surface & SA1_SURFACE_SLIPPERY) != 0;
                    digs += (t.surface & SA1_SURFACE_DIG) != 0;
                }
            }
        };
        auto s1 = L.call("ShapePhy", {Val::string(key), Val::string(couch)});
        uint32_t sl1, dg1, tt1;
        shape_words(sl1, dg1, tt1);
        auto set = L.call("SetSurfaceTable", {list_of({"concrete=noland", "dirt=dig,slippery", "grass=dig,slippery"}),
                                              opts(true, false)});
        auto known = L.call("ShapeKnown", {Val::string(key)});
        auto s2 = L.call("ShapePhy", {Val::string(key), Val::string(couch)});
        uint32_t sl2, dg2, tt2;
        shape_words(sl2, dg2, tt2);
        CHECK(s1.size() >= 1 && s1[0].b && tt1 > 0 && sl1 == 0 && dg1 == 0 && set.size() == 4 && set[2].b &&
                  known.size() == 1 && !known[0].b && s2.size() >= 1 && s2[0].b && sl2 == tt2 && dg2 == 0,
              "ShapePhy of the couch (its .phy says \"dirt\"): plain land with the defaults (%u triangles: diggable never "
              "reaches a moving object); the table changed -> the props' shapes dropped (ShapeKnown false), built again: "
              "%u of %u triangles slippery, none diggable", tt1, sl2, tt2);
        // the map again with the changed table (in the game: a cache hit, classes and preparation only)
        int files2 = 0;
        double t1 = gsa1::now_ms();
        std::string e2 = load_map(L, map, fs, files2);
        double ms2 = gsa1::now_ms() - t1;
        auto info2 = L.call("SurfaceInfo", {});
        bool have2 = e2.empty() && info2.size() == 1 && info2[0].type == Type::Table;
        const Val *g2 = have2 ? find_type(info2[0], "grass") : nullptr;
        double slip_area = have2 ? info2[0].tab->field("slippery").num : 0, walk2 = have2 ? info2[0].tab->field("walkable").num : 0;
        CHECK(have2 && g2 && g2->tab->field("kinds").str == "dig,slippery" && slip_area > 0.8 * walk2,
              "the map again with dirt and grass diggable and slippery (%d files fed, %.1f s): grass %s, %.0f%% of the "
              "walkable ground slippery%s%s", files2, ms2 / 1000.0,
              g2 ? g2->tab->field("kinds").str.c_str() : "?", walk2 > 0 ? 100.0 * slip_area / walk2 : 0.0,
              e2.empty() ? "" : ": ", e2.c_str());
        // 0.9.2 (gsa1_090_surfaces.md Review C3): concrete = noland on gm_construct - its walls get it, its floors not
        Val walls = have2 ? info2[0].tab->field("walls") : Val(), ktris = have2 ? info2[0].tab->field("kind_tris") : Val();
        double wall = have2 ? info2[0].tab->field("wall").num : 0, nl_floor = have2 ? info2[0].tab->field("noland").num : -1;
        double nl_wall = walls.type == Type::Table ? walls.tab->field("noland").num : 0;
        double kept = have2 ? info2[0].tab->field("wall_only_floors").num : 0;
        double nl_tris = ktris.type == Type::Table ? ktris.tab->field("noland").num : 0;
        const Val *conc = have2 ? find_type(info2[0], "concrete") : nullptr;
        CHECK(conc && conc->tab->field("kinds").str == "noland" && wall > 0 && nl_wall > 0 && nl_floor == 0 && kept > 0 &&
                  nl_tris > 0 && walls.tab->field("snow").type == Type::Number,
              "concrete = noland on gm_construct: SurfaceInfo walls.noland %.0f of %.0f HU^2 of walls, walkable noland %.0f, "
              "%.0f floor triangles kept as floors, %.0f triangles with it", nl_wall, wall, nl_floor, kept, nl_tris);
    } else {
        std::printf("  info  no session or no couch .phy: the prop checks are skipped\n");
    }
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
