// feat_surfaces_test: the surfaces feature's core (src/core/surfaces.*, phy.cpp's surface types; sadc
// docs/research/gsa1_060_dig.md F2 / F4 with its Review R4: G3, G7, G9, G13), offline. build.py links it like core_test
// (the core and libsa1) and runs it with --gdi when there is one (not needed here).
//
//   feat_surfaces_test [--gm GARRYSMOD_DIR]   (default Garry's Mod's garrysmod folder, found by tests/gmod_paths.hpp: read-only,
//                                              for GMod's own scripts/surfaceproperties.txt and a prop's .phy)
//
// Checks: KeyValues / .vmt parsing (plain, bare words, comments, [$X360] conditions, blends' $surfaceprop2, patch
// include + insert / replace, a missing or looping include, damaged input refused, never a crash on 4000 damaged
// copies), material paths, the surfaceproperties hierarchy (base chains, letters, the first definition wins, the
// manifest), the class table (listed / base chain / letter; carpet is no dig even though it derives from dirt; GMod's
// 126 types: 8 diggable, 8 slippery, 110 normal), the classes on a tagged world (water and kill planes untouched; a thin
// wall's second slot adds only hurts / no climbing; dig anywhere; off), moving objects (DIG never; at most 4 COL words:
// an object libsa1 refused with SA1_ERR_LIMIT registers after cap_object_words), a .phy's solids' surface types
// (synthetic text section: "dirt" -> its hull's land diggable, "wood_crate" -> not), the classed prop shape (no class:
// exactly shape_from_phy's).
// Round 0.9.2 (sadc docs/research/gsa1_090_surfaces.md F2 with its Review C3 / C4; plan gsa1_090_plan.md 6.9): every SA1
// ground kind (snow fast slide speedpath stairs noland wallslide footprints: words, aliases, round trips, their
// SA1_SURFACE_* bits and COL words; 0.8's strings unchanged), "fast,stairs" -> BOOST | STAIRS, "noland" / "wallslide"
// only on triangles that are no floor (walls and ceilings get them, floors - also a thin floor's other side and a
// double-sided floor seen from its back - do not; the per-kind summary), a moving object with 5 distinct words made of
// the new kinds (libsa1 refuses it; cap_object_words counts them and it registers) and a prop never getting the
// walls-only kinds; with --gdi: Sonic on a "concrete = noland" floor runs more than 100 units in 60 pairs (the floor
// with the bit, as a per-type kind without the walls-only rule makes it, traps him: about 4 units).
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "../src/core/bsp.hpp"
#include "../src/core/phy.hpp"
#include "../src/core/shape.hpp"
#include "../src/core/surfaces.hpp"
#include "../src/core/util.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)
#include "gamefs.hpp"

using namespace gsa1;

static int g_fail = 0, g_checks = 0;

#define CHECK(cond, ...)                                     \
    do {                                                     \
        g_checks++;                                          \
        if (cond) {                                          \
            std::printf("  ok    ");                         \
        } else {                                             \
            std::printf("  FAIL  ");                         \
            g_fail++;                                        \
        }                                                    \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

#define INFO(...)                                            \
    do {                                                     \
        std::printf("  info  ");                             \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

static uint32_t g_rng = 4242u;
static uint32_t rnd()
{
    g_rng = g_rng * 1664525u + 1013904223u;
    return g_rng >> 8;
}

static bool vmt(const char *text, VmtInfo &v)
{
    std::string e;
    return parse_vmt(text, std::strlen(text), v, e);
}

// ---- 1. materials --------------------------------------------------------------------------------------------------
static void test_vmt()
{
    std::printf("materials (.vmt)\n");
    VmtInfo a, b, c, d;
    bool ok = vmt("\"LightmappedGeneric\"\n{\n\t\"$basetexture\" \"gm_construct/grass_13\"\n\t\"$surfaceprop\" \"Grass\"\n}\n", a);
    CHECK(ok && a.shader == "lightmappedgeneric" && a.has_sp && a.sp == "grass" && !a.has_sp2,
          "a plain material: shader \"%s\", $surfaceprop \"%s\" (lower case)", a.shader.c_str(), a.sp.c_str());
    ok = vmt("WorldVertexTransition\n{\n  // a comment \"$surfaceprop\" \"metal\"\n  $basetexture nature/blendgrass\n"
             "  $surfaceprop dirt\n  \"$surfaceprop2\" \"sand\" [!$X360]\n  \"$surfaceprop\" \"rock\" [$X360]\n"
             "  \"$surfaceprop2\" \"snow\" [$X360 || $PS3]\n  \"%compilenodraw\" 1\n}", b);
    CHECK(ok && b.shader == "worldvertextransition" && b.sp == "dirt" && b.has_sp2 && b.sp2 == "sand",
          "a blend: bare words, comments, console conditions left out: $surfaceprop \"%s\", $surfaceprop2 \"%s\"",
          b.sp.c_str(), b.sp2.c_str());
    CHECK(kv_condition("[$WIN32]") && kv_condition("[!$X360]") && !kv_condition("[$X360]") && !kv_condition("[$OSX]") &&
              kv_condition("[$X360 || $WINDOWS]") && !kv_condition("[$WIN32 && $X360]") && kv_condition("[!$OSX && !$X360]"),
          "conditions: $WIN32, !$X360, $X360 || $WINDOWS and !$OSX && !$X360 hold; $X360, $OSX, $WIN32 && $X360 do not");
    // patches: cubemap copies in a map's pak
    ok = vmt("patch\n{\n\tinclude \"materials\\Concrete\\\\ConcreteFloor026A.vmt\"\n\tinsert\n\t{\n"
             "\t\t\"$envmap\" \"maps/gm_construct/c0_0_0\"\n\t}\n}\n", c);
    CHECK(ok && c.shader == "patch" && c.include == "materials/concrete/concretefloor026a.vmt" && !c.ins_sp,
          "a patch: include \"%s\" (normalized)", c.include.c_str());
    ok = vmt("\"patch\" { \"include\" \"materials/dev/a.vmt\" \"insert\" { \"$surfaceprop\" \"ice\" } \"replace\" { "
             "\"$surfaceprop2\" \"glass\" } }", d);
    std::map<std::string, VmtInfo> files;
    vmt("LightmappedGeneric { $surfaceprop concrete }", files["materials/concrete/concretefloor026a.vmt"]);
    vmt("LightmappedGeneric { $basetexture dev/a }", files["materials/dev/a.vmt"]);
    vmt("WorldVertexTransition { $surfaceprop grass $surfaceprop2 dirt }", files["materials/dev/b.vmt"]);
    vmt("patch { include materials/dev/b.vmt replace { $surfaceprop2 mud $surfaceprop metal } }", files["materials/p/rb.vmt"]);
    vmt("patch { include materials/p/loop2.vmt }", files["materials/p/loop1.vmt"]);
    vmt("patch { include materials/p/loop1.vmt }", files["materials/p/loop2.vmt"]);
    files["materials/p/c.vmt"] = c;
    files["materials/p/d.vmt"] = d;
    auto look = [&](const std::string &p) -> const VmtInfo * {
        auto it = files.find(p);
        return it == files.end() ? nullptr : &it->second;
    };
    VmtSurface rc = resolve_vmt("materials/p/c.vmt", look), rd = resolve_vmt("materials/p/d.vmt", look),
               rb = resolve_vmt("materials/p/rb.vmt", look), rx = resolve_vmt("materials/p/nothing.vmt", look),
               rl = resolve_vmt("materials/p/loop1.vmt", look), rn = resolve_vmt("materials/dev/a.vmt", look);
    CHECK(rc.found && rc.patched && rc.sp == "concrete" && rc.explicit_sp && !rc.include_missing,
          "a patch takes its include's $surfaceprop (\"%s\")", rc.sp.c_str());
    CHECK(rd.sp == "ice" && rd.explicit_sp && rd.sp2.empty(),
          "insert sets $surfaceprop (\"%s\"); replace does not add a $surfaceprop2 its include lacks (\"%s\")",
          rd.sp.c_str(), rd.sp2.c_str());
    CHECK(rb.sp == "metal" && rb.sp2 == "mud", "replace replaces what the include has: \"%s\" / \"%s\"", rb.sp.c_str(),
          rb.sp2.c_str());
    CHECK(!rx.found && rx.sp == "default" && rl.include_missing && rl.sp == "default" && rn.found && !rn.explicit_sp &&
              rn.sp == "default",
          "a missing .vmt and an include loop: \"default\" (Source's), the loop flagged; no $surfaceprop: \"default\"");
    // paths
    CHECK(vmt_path("Concrete\\Floor") == "materials/concrete/floor.vmt" &&
              vmt_path("materials/x.vmt") == "materials/x.vmt" && vmt_path("maps/gm_x/a_1_2") == "materials/maps/gm_x/a_1_2.vmt" &&
              vmt_path("../cfg/config") == "" && vmt_path("c:/windows/x") == "" && vmt_path("/abs") == "" &&
              vmt_path("") == "" && vmt_path(std::string(300, 'a')) == "" && vmt_path("a\x01" "b") == "",
          "material paths: lower case, materials/ and .vmt added; .., drive letters, absolute, empty, long and control "
          "bytes refused");
    // damaged input
    VmtInfo e;
    std::string err;
    bool r1 = vmt("\"LightmappedGeneric\" { \"$surfaceprop\" \"grass", e);
    bool r2 = vmt("{ }", e);
    bool r3 = vmt("", e);
    std::string deep;
    for (int i = 0; i < 40; i++) deep += "a { ";
    bool r4 = parse_vmt(deep.data(), deep.size(), e, err);
    CHECK(!r1 && !r2 && !r3 && !r4, "refused: an unterminated string, no shader block, an empty file, 40 levels (\"%s\")",
          err.c_str());
    // fuzz
    const std::string sample = "\"patch\"\n{\n  \"include\" \"materials/a/b.vmt\"\n  \"insert\" { \"$surfaceprop\" \"grass\" "
                               "[!$X360] \"$envmap\" \"env\" }\n  // x\n  replace { $surfaceprop2 sand }\n}\n";
    uint32_t parsed = 0, refused = 0;
    for (int i = 0; i < 4000; i++) {
        std::string t = sample;
        int flips = 1 + (int)(rnd() % 6);
        for (int f = 0; f < flips; f++) {
            if (rnd() % 3 == 0) {
                t.erase(rnd() % t.size(), 1 + rnd() % 8);
            } else {
                t[rnd() % t.size()] = (char)"\"{}[]/\\ \n\0ab$!|"[rnd() % 16];
            }
            if (t.empty()) {
                t = "x";
            }
        }
        VmtInfo v;
        std::string fe;
        (parse_vmt(t.data(), t.size(), v, fe) ? parsed : refused)++;
    }
    CHECK(parsed + refused == 4000, "4000 damaged copies of a patch material: %u parsed, %u refused, no crash", parsed,
          refused);
}

// ---- 2. surface types -----------------------------------------------------------------------------------------------
static const char kScript[] =
    "\"default\" { \"density\" \"2000\" \"gamematerial\" \"C\" }\n"
    "\"dirt\" { \"base\" \"default\" \"gamematerial\" \"D\" }\n"
    "\"grass\" { \"base\" \"dirt\" \"gamematerial\" \"U\" }\n"
    "\"carpet\" { \"base\" \"dirt\" }\n"
    "\"mygrass\" { \"base\" \"grass\" }\n"
    "\"mystery\" { \"base\" \"dirt\" \"gamematerial\" \"X\" }\n"
    "LetterOnly { gamematerial n }\n"
    "\"concrete\" { \"gamematerial\" \"67\" }\n"
    "\"dirt\" { \"gamematerial\" \"Z\" }\n"
    "\"loop_a\" { \"base\" \"loop_b\" }\n\"loop_b\" { \"base\" \"loop_a\" }\n";

static void test_types(gamefs::GameFs &fs)
{
    std::printf("surface types (surfaceproperties) and the class table\n");
    SurfacePropDb db;
    std::string err;
    bool ok = db.add_script(kScript, sizeof kScript - 1, err);
    SurfaceType mg = db.resolve("mygrass"), ca = db.resolve("carpet"), lo = db.resolve("letteronly"),
                co = db.resolve("concrete"), un = db.resolve("nonexistent"), lp = db.resolve("loop_a"),
                di = db.resolve("dirt");
    std::string chain;
    for (const std::string &n : mg.chain) chain += n + " ";
    CHECK(ok && db.size() == 10 && mg.chain.size() == 4 && mg.chain[1] == "grass" && mg.letter == 'U' && di.letter == 'D' &&
              lo.letter == 'N' && co.letter == 'C' && ca.letter == 'D' && un.chain.size() == 1 && un.letter == 0 &&
              lp.chain.size() == 2,
          "10 types (a second \"dirt\" ignored: letter %c); mygrass: %s(letter %c, inherited); \"67\" = C; a type without "
          "base takes default's letter; an unknown name: no letter; a base loop ends", di.letter, chain.c_str(), mg.letter);
    std::vector<std::string> files;
    const char man[] = "\"surfaceproperties_manifest\" { \"file\" \"scripts/surfaceproperties.txt\" "
                       "\"file\" \"Scripts\\SurfaceProperties_HL2.txt\" \"file\" \"../evil.txt\" "
                       "\"file\" \"cfg/autoexec.cfg\" \"file\" \"scripts/surfaceproperties.txt\" }";
    ok = SurfacePropDb::parse_manifest(man, sizeof man - 1, files, err);
    CHECK(ok && files.size() == 2 && files[1] == "scripts/surfaceproperties_hl2.txt",
          "the manifest: %zu scripts (outside scripts/, .. and duplicates left out)", files.size());
    // the class table
    SurfaceTable t = SurfaceTable::defaults();
    std::string h1, h2, h3, h4, h5;
    uint32_t k1 = t.kinds_of(db.resolve("grass"), &h1), k2 = t.kinds_of(ca, &h2), k3 = t.kinds_of(mg, &h3),
             k4 = t.kinds_of(db.resolve("mystery"), &h4), k5 = t.kinds_of(lo, &h5), k6 = t.kinds_of(co),
             k7 = t.kinds_of(un);
    CHECK(k1 == kKindDig && h1 == "listed" && k2 == 0 && h2 == "listed" && k3 == kKindDig && h3 == "base grass" &&
              k4 == kKindDig && h4 == "base dirt" && k5 == kKindDig && h5 == "letter N" && k6 == 0 && k7 == 0,
          "the table: grass dig (%s); carpet normal although it derives from dirt (%s); mygrass dig (%s); mystery dig (%s); "
          "an unlisted type with letter N dig (%s); concrete and an unknown name normal", h1.c_str(), h2.c_str(),
          h3.c_str(), h4.c_str(), h5.c_str());
    uint32_t k = 0;
    bool p1 = parse_kinds("Dig, sand", k) && k == (kKindDig | kKindSand);
    bool p2 = parse_kinds("normal", k) && k == 0;
    bool p3 = !parse_kinds("dig,lava", k);
    CHECK(p1 && p2 && p3 && kinds_string(kKindDig | kKindSand) == "dig,sand" && kinds_string(0) == "normal" &&
              kinds_surface(kKindsAll) == kClassSurfaceBits &&
              valid_surface_name("metal_box") && !valid_surface_name("Metal") && !valid_surface_name("") &&
              !valid_surface_name("a/b") && !valid_surface_name(std::string(65, 'a')),
          "kinds \"dig,sand\" / \"normal\" / unknown words refused; names: a-z 0-9 _ . - and spaces, 1..64");
    SurfaceSettings s1, s2 = s1, s3 = s1;
    s2.table.names["concrete"] = kKindDig;
    s3.dig_anywhere = true;
    CHECK(s1.hash() != s2.hash() && s1.hash() != s3.hash() && s1.hash() == SurfaceSettings().hash(),
          "the settings' hash follows the table and the switches");
    // Garry's Mod's own script (read-only from the installation)
    std::string sp;
    if (!fs.read("scripts/surfaceproperties.txt", sp)) {
        INFO("scripts/surfaceproperties.txt is not in this installation: GMod's types not checked");
        return;
    }
    SurfacePropDb g;
    double t0 = now_ms();
    ok = g.add_script(sp.data(), sp.size(), err);
    double ms = now_ms() - t0;
    uint32_t dig = 0, slip = 0, normal = 0;
    std::string digs, slips;
    for (const std::string &n : g.names()) {
        uint32_t kk = t.kinds_of(g.resolve(n));
        if (kk == kKindDig) {
            dig++;
            digs += n + " ";
        } else if (kk == kKindSlippery) {
            slip++;
            slips += n + " ";
        } else if (kk == 0) {
            normal++;
        }
    }
    SurfaceType gr = g.resolve("grass"), pa = g.resolve("paper"), gv = g.resolve("gravel");
    CHECK(ok && g.size() == 126 && dig == 8 && slip == 8 && normal == 110 && gr.letter == 'U' && pa.chain.size() >= 3 &&
              t.kinds_of(pa) == 0 && t.kinds_of(gv) == kKindDig,
          "GMod's scripts/surfaceproperties.txt (%.1f ms): %zu types, %u diggable (%s), %u slippery (%s), %u normal; paper "
          "(a kind of cardboard, then dirt) normal; gravel (a kind of rock) diggable", ms, g.size(), dig, digs.c_str(),
          slip, slips.c_str(), normal);
}

// ---- 3. the classes on a tagged world --------------------------------------------------------------------------------
static sa1_collision_tri tri(float x, float y, float z, float s, uint32_t surface, bool up = true)
{
    sa1_collision_tri t;
    float a[3] = {x, y, z}, b[3] = {x + s, y, z}, c[3] = {x, y + s, z};
    std::memcpy(t.v[0], a, 12);
    std::memcpy(t.v[1], up ? b : c, 12);
    std::memcpy(t.v[2], up ? c : b, 12);
    t.surface = surface;
    return t;
}

static void test_classes()
{
    std::printf("classes on a tagged world\n");
    SurfacePropDb db;
    std::string err;
    db.add_script(kScript, sizeof kScript - 1, err);
    std::vector<SurfaceType> types = {db.resolve("grass"), db.resolve("concrete"), db.resolve("lava"), db.resolve("ice_x")};
    SurfaceSettings s;
    s.table.names["lava"] = kKindHurt | kKindDig;
    s.table.names["ice_x"] = kKindSlippery | kKindNoClimb;
    std::vector<sa1_collision_tri> base = {
        tri(0, 0, 0, 100, SA1_SURFACE_SOLID),                              // 0 grass floor
        tri(0, 0, 50, 100, SA1_SURFACE_WATER),                             // 1 water tagged grass: never classed
        tri(0, 0, -900, 100, SA1_SURFACE_KILL),                            // 2 the kill plane
        tri(200, 0, 0, 100, SA1_SURFACE_SOLID),                            // 3 concrete floor
        tri(400, 0, 0, 100, SA1_SURFACE_SOLID | SA1_SURFACE_DOUBLE_SIDED), // 4 a thin wall: concrete, the other side lava
        tri(600, 0, 0, 100, SA1_SURFACE_SOLID | SA1_SURFACE_DOUBLE_SIDED), // 5 a thin wall: concrete, the other side ice_x
        tri(800, 0, 0, 100, SA1_SURFACE_SOLID),                            // 6 untagged
        tri(900, 0, 0, 100, SA1_SURFACE_SOLID | SA1_SURFACE_STAIRS),       // 7 a ramp of grass
    };
    std::vector<uint32_t> tags = {surface_tag(0), surface_tag(0), kNoSurfaceTag, surface_tag(1), surface_tag(1, 2),
                                  surface_tag(1, 3), kNoSurfaceTag, surface_tag(0)};
    std::vector<sa1_collision_tri> w = base;
    SurfaceSummary sum;
    apply_surface_classes(w, tags, types, s, sum);
    CHECK(w[0].surface == (SA1_SURFACE_SOLID | SA1_SURFACE_DIG) && w[1].surface == SA1_SURFACE_WATER &&
              w[2].surface == SA1_SURFACE_KILL && w[3].surface == SA1_SURFACE_SOLID &&
              w[7].surface == (SA1_SURFACE_SOLID | SA1_SURFACE_STAIRS | SA1_SURFACE_DIG) && w[6].surface == SA1_SURFACE_SOLID,
          "grass land diggable (stairs too); water, the kill plane, concrete and untagged land unchanged");
    CHECK(w[4].surface == (SA1_SURFACE_SOLID | SA1_SURFACE_DOUBLE_SIDED | SA1_SURFACE_HURT) &&
              w[5].surface == (SA1_SURFACE_SOLID | SA1_SURFACE_DOUBLE_SIDED | SA1_SURFACE_NO_CLIMB),
          "a thin wall's other side adds hurts / no climbing only (lava's dig and ice's slippery do not reach it: G7)");
    CHECK(sum.tris == 6 && sum.tris_dig == 2 && sum.tris_untagged == 1 && std::fabs(sum.walkable - 6 * 5000.0) < 1.0 &&
              std::fabs(sum.dig - 2 * 5000.0) < 1.0 && std::fabs(sum.types[0].area - 10000.0) < 1.0 &&
              sum.types[0].kinds == kKindDig && sum.types[0].how == "listed",
          "the summary: %u land triangles, %u diggable, %u untagged; walkable %.0f, diggable %.0f square units", sum.tris,
          sum.tris_dig, sum.tris_untagged, sum.walkable, sum.dig);
    w = base;
    s.dig_anywhere = true;
    apply_surface_classes(w, tags, types, s, sum);
    bool any_ok = w[1].surface == SA1_SURFACE_WATER && w[2].surface == SA1_SURFACE_KILL;
    for (int i : {0, 3, 4, 5, 6, 7}) {
        any_ok = any_ok && (w[i].surface & SA1_SURFACE_DIG);
    }
    CHECK(any_ok && sum.dig_anywhere, "dig anywhere: every land triangle diggable, water and the kill plane not");
    w = base;
    s.dig_anywhere = false;
    s.enabled = false;
    apply_surface_classes(w, tags, types, s, sum);
    bool same = true;
    for (size_t i = 0; i < w.size(); i++) {
        same = same && w[i].surface == base[i].surface;
    }
    CHECK(same && sum.tris_classed == 0, "ground types off: no triangle changed (0.7's ground)");
    std::vector<uint32_t> none;
    w = base;
    s.enabled = true;
    apply_surface_classes(w, none, types, s, sum);
    CHECK(w[0].surface == SA1_SURFACE_SOLID && sum.tris_untagged == 6, "no tags at all: nothing classed");
}

// ---- 4. moving objects ------------------------------------------------------------------------------------------------
static void test_moving(gamefs::GameFs &fs)
{
    std::printf("moving objects\n");
    // a brush model whose faces are SOLID, NO_CLIMB, DOUBLE_SIDED, STAIRS, SLIPPERY and DIG (Review G3)
    std::vector<sa1_collision_tri> t = {tri(0, 0, 0, 40, SA1_SURFACE_SOLID), tri(0, 0, 10, 40, SA1_SURFACE_SOLID | SA1_SURFACE_NO_CLIMB),
                                        tri(0, 0, 20, 40, SA1_SURFACE_SOLID | SA1_SURFACE_DOUBLE_SIDED),
                                        tri(0, 0, 30, 40, SA1_SURFACE_SOLID | SA1_SURFACE_STAIRS),
                                        tri(0, 0, 40, 40, SA1_SURFACE_SOLID | SA1_SURFACE_SLIPPERY),
                                        tri(0, 0, 50, 40, SA1_SURFACE_SOLID | SA1_SURFACE_DIG)};
    CHECK(surface_col(SA1_SURFACE_SOLID) == 1 && surface_col(SA1_SURFACE_SOLID | SA1_SURFACE_DOUBLE_SIDED) == 1 &&
              surface_col(SA1_SURFACE_DIG) == 0x101 && surface_col(SA1_SURFACE_SLIPPERY) == 0x5 &&
              surface_col(SA1_SURFACE_WATER) == 0x2 && surface_col(SA1_SURFACE_KILL) == 0,
          "COL words as libsa1 makes them (DOUBLE_SIDED is a material bit, not a COL bit)");
    sa1_host h;
    sa1_host_defaults(&h);
    h.log = nullptr;
    sa1_context *ctx = nullptr;
    if (SA1_FAILED(sa1_init(&h, &ctx)) || !ctx) {
        CHECK(false, "sa1_init");
        return;
    }
    uint32_t id = 0;
    const float origin[3] = {0, 0, 0};
    sa1_status before = sa1_collision_object_add(ctx, t.data(), (uint32_t)t.size(), origin, nullptr, &id);
    std::vector<sa1_collision_tri> c = t;
    uint32_t removed = cap_object_words(c, SA1_SURFACE_SLIPPERY);
    bool dig = false;
    for (const sa1_collision_tri &x : c) {
        dig = dig || (x.surface & SA1_SURFACE_DIG);
    }
    uint32_t id2 = 0;
    sa1_status after = sa1_collision_object_add(ctx, c.data(), (uint32_t)c.size(), origin, nullptr, &id2);
    CHECK(before == SA1_ERR_LIMIT && after == SA1_OK && !dig && removed == SA1_SURFACE_DIG &&
              (c[4].surface & SA1_SURFACE_SLIPPERY),
          "5 COL words: libsa1 refuses the object (%s); without DIG (never on a moving object) 4 words: registered (%s), "
          "slippery kept", sa1_status_string(before), sa1_status_string(after));
    c = t;
    c.push_back(tri(0, 0, 60, 40, SA1_SURFACE_SOLID | SA1_SURFACE_HURT));
    removed = cap_object_words(c, SA1_SURFACE_SLIPPERY | SA1_SURFACE_HURT);
    uint32_t id3 = 0;
    sa1_status after2 = sa1_collision_object_add(ctx, c.data(), (uint32_t)c.size(), origin, nullptr, &id3);
    CHECK(after2 == SA1_OK && removed == (SA1_SURFACE_DIG | SA1_SURFACE_SLIPPERY | SA1_SURFACE_HURT) &&
              !(c[4].surface & SA1_SURFACE_SLIPPERY) && (c[1].surface & SA1_SURFACE_NO_CLIMB),
          "6 words: the droppable class bits go too (the map's own no-climbing stays): registered (%s)",
          sa1_status_string(after2));
    // 0.9.2 (Review C4): 5 distinct words made of the new kinds - 0.9.1's surface_col saw SNOW / SPEED_PATH / FOOTPRINTS
    // as plain land (2 words: no cap), and libsa1, which maps them, refused the object
    const uint32_t newk = SA1_SURFACE_SNOW | SA1_SURFACE_SPEED_PATH | SA1_SURFACE_FOOTPRINTS | SA1_SURFACE_BOOST;
    std::vector<sa1_collision_tri> t5 = {tri(0, 0, 0, 40, SA1_SURFACE_SOLID), tri(0, 0, 10, 40, SA1_SURFACE_SOLID | SA1_SURFACE_SNOW),
                                         tri(0, 0, 20, 40, SA1_SURFACE_SOLID | SA1_SURFACE_SPEED_PATH),
                                         tri(0, 0, 30, 40, SA1_SURFACE_SOLID | SA1_SURFACE_FOOTPRINTS),
                                         tri(0, 0, 40, 40, SA1_SURFACE_SOLID | SA1_SURFACE_BOOST)};
    uint32_t id5 = 0, id6 = 0;
    sa1_status before5 = sa1_collision_object_add(ctx, t5.data(), (uint32_t)t5.size(), origin, nullptr, &id5);
    std::vector<sa1_collision_tri> c5 = t5;
    uint32_t removed5 = cap_object_words(c5, newk);
    std::vector<uint32_t> words;
    for (const sa1_collision_tri &x : c5) {
        if (std::find(words.begin(), words.end(), surface_col(x.surface)) == words.end()) {
            words.push_back(surface_col(x.surface));
        }
    }
    sa1_status after5 = sa1_collision_object_add(ctx, c5.data(), (uint32_t)c5.size(), origin, nullptr, &id6);
    CHECK(before5 == SA1_ERR_LIMIT && removed5 == newk && words.size() <= 4 && after5 == SA1_OK,
          "5 words of the new kinds (plain, snow, speed track, footprints, fast): libsa1 refuses the object (%s); "
          "cap_object_words counts them and drops the class bits (%zu word left): registered (%s)",
          sa1_status_string(before5), words.size(), sa1_status_string(after5));
    sa1_shutdown(ctx);
    // a prop's physics model: its solids' surface types (the .phy text section)
    std::string couch;
    if (!fs.read("models/props_c17/furniturecouch001a.phy", couch)) {
        INFO("models/props_c17/furniturecouch001a.phy is not in this installation: the .phy checks are skipped");
        return;
    }
    PhyModel m;
    std::string err;
    bool ok = parse_phy(couch.data(), couch.size(), m, err);
    CHECK(ok && m.solid_surfaceprop.size() == m.solids && !m.solid_surfaceprop.empty() && !m.solid_surfaceprop[0].empty() &&
              m.hull_solid.size() == m.hulls.size(),
          "the couch's .phy: solid 0 is \"%s\"; %zu convex pieces, each with its solid", ok ? m.solid_surfaceprop[0].c_str() : "?",
          m.hulls.size());
    // the same file with a synthetic text section
    int32_t hsize = 0, solids = 0;
    std::memcpy(&hsize, couch.data(), 4);
    std::memcpy(&solids, couch.data() + 8, 4);
    size_t pos = (size_t)hsize;
    for (int32_t i = 0; i < solids && pos + 4 <= couch.size(); i++) {
        int32_t sz;
        std::memcpy(&sz, couch.data() + pos, 4);
        pos += 4 + (size_t)sz;
    }
    auto with_text = [&](const char *text) { return couch.substr(0, pos) + text; };
    PhyModel md, mw, mb;
    std::string sd = with_text("solid {\n\"index\" \"0\"\n\"name\" \"couch\"\n\"mass\" \"80\"\n\"surfaceprop\" \"Dirt\"\n}\n"
                               "editparams {\n\"totalmass\" \"80\"\n}\n");
    std::string sw = with_text("solid { \"surfaceprop\" \"wood_crate\" }");
    std::string sb = with_text("solid { \"index\" \"0\" \"surfaceprop\" \"x\" \"broken");
    bool okd = parse_phy(sd.data(), sd.size(), md, err), okw = parse_phy(sw.data(), sw.size(), mw, err),
         okb = parse_phy(sb.data(), sb.size(), mb, err);
    CHECK(okd && okw && okb && md.solid_surfaceprop[0] == "dirt" && mw.solid_surfaceprop[0] == "wood_crate" &&
              mb.solid_surfaceprop[0].empty() && mb.hulls.size() == m.hulls.size(),
          "a synthetic text section: \"dirt\" (lower case), \"wood_crate\" (no index: the next solid), a damaged one only "
          "loses the type");
    // as static props: hull triangles tagged, then classed
    SurfacePropDb db;
    std::string sp;
    if (fs.read("scripts/surfaceproperties.txt", sp)) {
        db.add_script(sp.data(), sp.size(), err);
    }
    std::vector<SurfaceType> types = {db.resolve("dirt"), db.resolve("wood_crate")};
    uint32_t dig_land = 0, wood_dig = 0, land = 0;
    for (int which = 0; which < 2; which++) {
        const PhyModel &pm = which == 0 ? md : mw;
        std::vector<ConvexSolid> cs;
        for (size_t hh = 0; hh < pm.hulls.size(); hh++) {
            ConvexSolid x;
            x.tris = pm.hulls[hh];
            x.sp = (uint16_t)which;   // the slot of its .phy solid's type
            cs.push_back(std::move(x));
        }
        std::vector<sa1_collision_tri> out;
        std::vector<uint32_t> tg;
        BspWorldStats st;
        BspWorldOptions o;
        clean_solids(cs, o, out, st, err, &tg);
        SurfaceSummary sum;
        apply_surface_classes(out, tg, types, SurfaceSettings(), sum);
        for (size_t i = 0; i < out.size(); i++) {
            bool up = false;
            {
                double e1[3], e2[3];
                for (int k = 0; k < 3; k++) {
                    e1[k] = out[i].v[1][k] - out[i].v[0][k];
                    e2[k] = out[i].v[2][k] - out[i].v[0][k];
                }
                double nz = e1[0] * e2[1] - e1[1] * e2[0];
                up = nz > 0.0;
            }
            if (which == 0 && up) {
                land++;
                dig_land += (out[i].surface & SA1_SURFACE_DIG) != 0;
            }
            if (which == 1) {
                wood_dig += (out[i].surface & SA1_SURFACE_DIG) != 0;
            }
        }
    }
    CHECK(land > 0 && dig_land == land && wood_dig == 0,
          "as a static prop: the \"dirt\" couch's %u upward triangles are diggable (%u), the \"wood_crate\" one has none",
          land, dig_land);
    // as a moving object: the classed shape
    Shape plain, same, cls;
    std::vector<uint32_t> zero(m.solids, 0u), bits(m.solids, SA1_SURFACE_SLIPPERY | SA1_SURFACE_DIG);
    uint32_t capped = 0;
    bool s1 = shape_from_phy(m, plain, err), s2 = shape_from_phy_classed(m, zero, same, err),
         s3 = shape_from_phy_classed(m, bits, cls, err, 16.0f, &capped);
    bool identical = s1 && s2 && plain.tris == same.tris && plain.chunks.size() == same.chunks.size();
    for (size_t i = 0; identical && i < plain.chunks.size(); i++) {
        identical = plain.chunks[i].tris.size() == same.chunks[i].tris.size() &&
                    std::memcmp(plain.chunks[i].tris.data(), same.chunks[i].tris.data(),
                                plain.chunks[i].tris.size() * sizeof(sa1_collision_tri)) == 0;
    }
    uint32_t slip = 0, digs = 0, total = 0;
    for (const ShapeChunk &ch : cls.chunks) {
        for (const sa1_collision_tri &x : ch.tris) {
            total++;
            slip += (x.surface & SA1_SURFACE_SLIPPERY) != 0;
            digs += (x.surface & SA1_SURFACE_DIG) != 0;
        }
    }
    CHECK(identical && s3 && total > 0 && slip == total && digs == 0 && capped == 0,
          "as a moving object: without kinds exactly shape_from_phy's shape; slippery + dig -> %u of %u triangles slippery, "
          "none diggable", slip, total);
    // 0.9.2: the walls-only kinds never reach a prop (it can turn over), the other new kinds do
    Shape cw;
    std::vector<uint32_t> wbits(m.solids, SA1_SURFACE_NO_LAND | SA1_SURFACE_WALL_SLIDE | SA1_SURFACE_SNOW);
    bool s4 = shape_from_phy_classed(m, wbits, cw, err);
    uint32_t snow = 0, wl = 0, tot4 = 0;
    for (const ShapeChunk &ch : cw.chunks) {
        for (const sa1_collision_tri &x : ch.tris) {
            tot4++;
            snow += (x.surface & SA1_SURFACE_SNOW) != 0;
            wl += (x.surface & (SA1_SURFACE_NO_LAND | SA1_SURFACE_WALL_SLIDE)) != 0;
        }
    }
    CHECK(s4 && tot4 > 0 && snow == tot4 && wl == 0,
          "a prop whose type is noland + wallslide + snow: %u of %u triangles snow, %u not a floor / slide-off wall", snow,
          tot4, wl);
}

// ---- 5. round 0.9.2: every SA1 ground kind --------------------------------------------------------------------------
static void test_kinds_092()
{
    std::printf("every SA1 ground kind (0.9.2)\n");
    uint32_t k = 0, k2 = 0;
    bool sf = parse_kinds("snow,fast", k);
    bool rt = sf && parse_kinds(kinds_string(k), k2) && k2 == k;
    CHECK(sf && k == (kKindSnow | kKindFast) && kinds_string(k) == "snow,fast" && rt,
          "parse_kinds(\"snow,fast\") = %s (0x%X) and round-trips through \"%s\" (0.9.1: false)", sf ? "true" : "false",
          (unsigned)k, kinds_string(k).c_str());
    // every word, its bit, its COL word
    static const struct {
        const char *word;
        uint32_t kind, surface, col;
    } want[] = {{"dig", kKindDig, SA1_SURFACE_DIG, 0x100u},          {"slippery", kKindSlippery, SA1_SURFACE_SLIPPERY, 0x4u},
                {"sand", kKindSand, SA1_SURFACE_SAND, 0x10u},         {"hurt", kKindHurt, SA1_SURFACE_HURT, 0x10000u},
                {"noclimb", kKindNoClimb, SA1_SURFACE_NO_CLIMB, 0x1000u}, {"snow", kKindSnow, SA1_SURFACE_SNOW, 0x8u},
                {"fast", kKindFast, SA1_SURFACE_BOOST, 0x80u},        {"slide", kKindSlide, SA1_SURFACE_SLIDE, 0x20000u},
                {"speedpath", kKindSpeedPath, SA1_SURFACE_SPEED_PATH, 0x800000u},
                {"stairs", kKindStairs, SA1_SURFACE_STAIRS, 0x4000u}, {"noland", kKindNoLand, SA1_SURFACE_NO_LAND, 0x40u},
                {"wallslide", kKindWallSlide, SA1_SURFACE_WALL_SLIDE, 0x200000u},
                {"footprints", kKindFootprints, SA1_SURFACE_FOOTPRINTS, 0x100000u}};
    int bad = 0;
    std::string bads;
    const KindInfo *kt = kind_table();
    uint32_t all = 0;
    for (unsigned i = 0; i < kKindCount; i++) {
        const auto &w = want[i];
        uint32_t p = 0;
        bool ok = std::strcmp(kt[i].word, w.word) == 0 && kt[i].kind == w.kind && kt[i].surface == w.surface &&
                  parse_kinds(w.word, p) && p == w.kind && kinds_string(w.kind) == w.word &&
                  kinds_surface(w.kind) == w.surface && surface_col(SA1_SURFACE_SOLID | w.surface) == (0x1u | w.col);
        all |= kt[i].kind;
        if (!ok) {
            bad++;
            bads += std::string(" ") + w.word;
        }
    }
    CHECK(bad == 0 && all == kKindsAll && kKindCount == 13,
          "13 kinds (0.8's five, then snow fast slide speedpath stairs noland wallslide footprints): each word parses, "
          "prints, maps to its SA1_SURFACE_* bit and its COL word (surface_col)%s%s", bad ? ": wrong" : "", bads.c_str());
    uint32_t a1 = 0, a2 = 0;
    bool al = parse_kinds("Speed_Path + no_land|wall_slide boost footprint stair sliding", a1) &&
              parse_kinds("speedpath,noland,wallslide,fast,footprints,stairs,slide", a2) && a1 == a2;
    CHECK(al && kinds_string(kKindHurt | kKindNoClimb) == "hurt,noclimb" &&
              kinds_string(kKindDig | kKindSand | kKindSnow) == "dig,sand,snow" && !parse_kinds("snow,lava", k),
          "aliases (speed_path, no_land, wall_slide, boost, footprint, stair, sliding); 0.8's strings unchanged "
          "(\"hurt,noclimb\"), new words after them; an unknown word still refused");
    CHECK(surface_col(SA1_SURFACE_SNOW) == 0x9u && surface_col(SA1_SURFACE_SPEED_PATH) == 0x800001u &&
              surface_col(SA1_SURFACE_FOOTPRINTS) == 0x100001u,
          "surface_col: SNOW 0x9, SPEED_PATH 0x800001, FOOTPRINTS 0x100001 (libsa1's words; 0.9.1: all 0x1, Review C4)");
    // "fast,stairs" on a tagged floor
    SurfacePropDb db;
    std::string err;
    db.add_script(kScript, sizeof kScript - 1, err);
    std::vector<SurfaceType> types = {db.resolve("concrete"), db.resolve("grass"), db.resolve("metal_x"),
                                      db.resolve("ramp_x")};
    SurfaceSettings s;
    bool okp = parse_kinds("fast,stairs", s.table.names["ramp_x"]);
    std::vector<sa1_collision_tri> w = {tri(0, 0, 0, 100, SA1_SURFACE_SOLID)};
    std::vector<uint32_t> tags = {surface_tag(3)};
    SurfaceSummary sum;
    apply_surface_classes(w, tags, types, s, sum);
    CHECK(okp && w[0].surface == (SA1_SURFACE_SOLID | SA1_SURFACE_BOOST | SA1_SURFACE_STAIRS) &&
              sum.kind_tris[6] == 1 && sum.kind_tris[9] == 1 && std::fabs(sum.kind_area[6] - 5000.0) < 1.0,
          "\"ramp_x = fast,stairs\": its floor gets SA1_SURFACE_BOOST | STAIRS (0x%X); the per-kind summary counts it",
          (unsigned)w[0].surface);
}

// a quad (two triangles) whose front faces `n` (the corners in any order around the quad)
static void add_quad(std::vector<sa1_collision_tri> &out, std::vector<uint32_t> &tags, const float p[4][3],
                     const float n[3], uint32_t surface, uint32_t tag)
{
    for (int h = 0; h < 2; h++) {
        const float *a = p[0], *b = p[h + 1], *c = p[h + 2];
        float e1[3] = {b[0] - a[0], b[1] - a[1], b[2] - a[2]}, e2[3] = {c[0] - a[0], c[1] - a[1], c[2] - a[2]};
        float cx = e1[1] * e2[2] - e1[2] * e2[1], cy = e1[2] * e2[0] - e1[0] * e2[2], cz = e1[0] * e2[1] - e1[1] * e2[0];
        bool flip = cx * n[0] + cy * n[1] + cz * n[2] < 0.0f;
        sa1_collision_tri t;
        std::memcpy(t.v[0], a, 12);
        std::memcpy(t.v[1], flip ? c : b, 12);
        std::memcpy(t.v[2], flip ? b : c, 12);
        t.surface = surface;
        out.push_back(t);
        tags.push_back(tag);
    }
}

// a 2400 x 2400 HU concrete floor (Source space, z up) with 400-HU concrete walls around it, facing in
static void concrete_room(std::vector<sa1_collision_tri> &w, std::vector<uint32_t> &tags)
{
    const float L = 1200.0f, H = 400.0f;
    const float fl[4][3] = {{-L, -L, 0}, {L, -L, 0}, {L, L, 0}, {-L, L, 0}}, up[3] = {0, 0, 1};
    add_quad(w, tags, fl, up, SA1_SURFACE_SOLID, surface_tag(0));
    for (int side = 0; side < 4; side++) {
        float sx = side == 0 ? 1.0f : side == 1 ? -1.0f : 0.0f, sy = side == 2 ? 1.0f : side == 3 ? -1.0f : 0.0f;
        float tx = -sy, ty = sx;   // along the wall
        float q[4][3];
        for (int c = 0; c < 4; c++) {
            float along = (c == 0 || c == 3) ? -L : L, z = (c < 2) ? 0.0f : H;
            q[c][0] = sx * L + tx * along;
            q[c][1] = sy * L + ty * along;
            q[c][2] = z;
        }
        // corners: 0 (-L, 0), 1 (+L, 0), 2 (+L, H), 3 (-L, H)
        const float in[3] = {-sx, -sy, 0};
        add_quad(w, tags, q, in, SA1_SURFACE_SOLID, surface_tag(0));
    }
}

static void test_noland(const std::string &gdi)
{
    std::printf("\"not a floor\" / \"slide-off wall\": walls only (Review C3)\n");
    SurfacePropDb db;
    std::string err;
    db.add_script(kScript, sizeof kScript - 1, err);
    std::vector<SurfaceType> types = {db.resolve("concrete"), db.resolve("slick_x")};
    SurfaceSettings s;
    s.table.names["concrete"] = kKindNoLand;
    s.table.names["slick_x"] = kKindWallSlide | kKindSlippery;
    // core: a floor, a wall, a ceiling, a double-sided floor seen from its back, a thin wall and a thin floor whose other
    // side is slick_x (wallslide)
    std::vector<sa1_collision_tri> w;
    std::vector<uint32_t> tags;
    const float fl[4][3] = {{0, 0, 0}, {100, 0, 0}, {100, 100, 0}, {0, 100, 0}};
    const float wa[4][3] = {{0, 0, 0}, {100, 0, 0}, {100, 0, 100}, {0, 0, 100}};
    const float ce[4][3] = {{0, 0, 200}, {100, 0, 200}, {100, 100, 200}, {0, 100, 200}};
    const float up[3] = {0, 0, 1}, side[3] = {0, 1, 0}, down[3] = {0, 0, -1};
    add_quad(w, tags, fl, up, SA1_SURFACE_SOLID, surface_tag(0));                                   // 0-1 floor
    add_quad(w, tags, wa, side, SA1_SURFACE_SOLID, surface_tag(0));                                 // 2-3 wall
    add_quad(w, tags, ce, down, SA1_SURFACE_SOLID, surface_tag(0));                                 // 4-5 ceiling
    add_quad(w, tags, ce, down, SA1_SURFACE_SOLID | SA1_SURFACE_DOUBLE_SIDED, surface_tag(0));      // 6-7 thin floor, back
    add_quad(w, tags, wa, side, SA1_SURFACE_SOLID | SA1_SURFACE_DOUBLE_SIDED, surface_tag(0, 1));   // 8-9 thin wall
    add_quad(w, tags, fl, up, SA1_SURFACE_SOLID | SA1_SURFACE_DOUBLE_SIDED, surface_tag(0, 1));     // 10-11 thin floor
    SurfaceSummary sum;
    apply_surface_classes(w, tags, types, s, sum);
    auto has = [&](int i, uint32_t b) { return (w[i].surface & b) != 0; };
    const uint32_t NL = SA1_SURFACE_NO_LAND, WS = SA1_SURFACE_WALL_SLIDE;
    bool floors = !has(0, NL) && !has(1, NL) && !has(6, NL) && !has(7, NL) && !has(10, NL | WS) && !has(11, NL | WS);
    bool walls = has(2, NL) && has(3, NL) && has(4, NL) && has(5, NL) && has(8, NL) && has(8, WS) && has(9, WS) &&
                 !has(8, SA1_SURFACE_SLIPPERY);
    CHECK(floors && walls && sum.wall_only_floors == 6 && sum.kind_area[10] == 0.0 && sum.kind_wall[10] > 0.0 &&
              sum.kind_wall[11] > 0.0,
          "concrete = noland: its floors (also a double-sided floor seen from below and a thin floor whose other side "
          "slides off) keep no 0x40 / WALL_SLIDE; its walls and ceilings get 0x40, the thin wall also the other side's "
          "slide-off (not its ice); %u floor triangles left without it; walls: %.0f HU^2 not a floor",
          sum.wall_only_floors, sum.kind_wall[10]);
    // the game: Sonic on the concrete floor of a room whose concrete is "noland"
    if (gdi.empty()) {
        INFO("no --gdi / SA1_TEST_GDI: Sonic's run on the \"noland\" concrete floor is not checked");
        return;
    }
    std::vector<sa1_collision_tri> room, trap;
    std::vector<uint32_t> rtags;
    concrete_room(room, rtags);
    std::vector<SurfaceType> ct = {db.resolve("concrete")};
    SurfaceSettings sn;
    sn.table.names["concrete"] = kKindNoLand;
    apply_surface_classes(room, rtags, ct, sn, sum);
    uint32_t floor_nl = 0, wall_nl = 0;
    for (size_t i = 0; i < room.size(); i++) {
        (i < 2 ? floor_nl : wall_nl) += (room[i].surface & SA1_SURFACE_NO_LAND) != 0;
    }
    trap = room;
    for (sa1_collision_tri &t : trap) {
        t.surface |= SA1_SURFACE_NO_LAND;   // the bit on every concrete triangle (a per-type kind without the C3 rule)
    }
    sa1_host h;
    sa1_host_defaults(&h);
    h.log = nullptr;
    sa1_context *ctx = nullptr;
    if (SA1_FAILED(sa1_init(&h, &ctx)) || !ctx) {
        CHECK(false, "sa1_init");
        return;
    }
    sa1_coords co;
    std::memset(&co, 0, sizeof co);
    co.struct_size = sizeof co;
    sa1_coords_preset(SA1_COORDS_PRESET_SOURCE, &co);
    sa1_set_coords(ctx, &co);
    sa1_load_options lo;
    std::memset(&lo, 0, sizeof lo);
    lo.struct_size = sizeof lo;
    lo.characters = 1u << SA1_CHAR_SONIC;
    lo.flags = 0;
    double t0 = now_ms();
    sa1_status ls = sa1_load_disc(ctx, gdi.c_str(), &lo);
    if (SA1_FAILED(ls)) {
        CHECK(false, "sa1_load_disc(%s): %s", gdi.c_str(), sa1_status_string(ls));
        sa1_shutdown(ctx);
        return;
    }
    INFO("the disc loaded (Sonic) in %.1f s", (now_ms() - t0) / 1000.0);
    // as nolandtrap.c (gsa1_090_surfaces.md Review R.3): stick forward pairs 10..69, A at pairs 20 and 40, 80 pairs
    auto run = [&](const std::vector<sa1_collision_tri> &world, float &moved, int &air, uint32_t &surface_seen) -> bool {
        moved = 0.0f;
        air = 0;
        surface_seen = 0;
        if (SA1_FAILED(sa1_collision_set_static(ctx, world.data(), (uint32_t)world.size()))) {
            return false;
        }
        sa1_character_desc d;
        std::memset(&d, 0, sizeof d);
        d.struct_size = sizeof d;
        d.kind = SA1_CHAR_SONIC;
        d.flags = SA1_CREATE_WORLD;
        d.position[2] = 8.0f;   // 2 SA1 units above the floor
        sa1_character_id id = 0;
        if (SA1_FAILED(sa1_character_create_ex(ctx, &d, &id))) {
            return false;
        }
        float x0 = 0, z0 = 0;
        sa1_state_ex x;
        std::memset(&x, 0, sizeof x);
        for (int i = 0; i < 80; i++) {
            sa1_input in;
            std::memset(&in, 0, sizeof in);
            in.struct_size = sizeof in;
            in.stick_y = (i >= 10 && i < 70) ? 1.0f : 0.0f;
            in.buttons = (i == 20 || i == 40) ? SA1_BUTTON_JUMP : 0u;
            if (SA1_FAILED(sa1_character_tick(ctx, id, &in, 1.0f / 30.0f, nullptr, nullptr))) {
                sa1_character_destroy(ctx, id);
                return false;
            }
            std::memset(&x, 0, sizeof x);
            x.struct_size = sizeof x;
            sa1_character_state_ex(ctx, id, &x);
            if (i == 9) {
                x0 = x.sa1_position[0];
                z0 = x.sa1_position[2];
            }
            if (i >= 10 && !(x.game_flags & 3)) {
                air += 2;
            }
            if (x.game_flags & 3) {
                surface_seen |= x.surface;
            }
        }
        float dx = x.sa1_position[0] - x0, dz = x.sa1_position[2] - z0;
        moved = std::sqrt(dx * dx + dz * dz);
        sa1_character_destroy(ctx, id);
        return true;
    };
    float m_after = 0, m_trap = 0;
    int air_after = 0, air_trap = 0;
    uint32_t surf_after = 0, surf_trap = 0;
    bool r1 = run(room, m_after, air_after, surf_after), r2 = run(trap, m_trap, air_trap, surf_trap);
    CHECK(r1 && floor_nl == 0 && wall_nl == 8 && m_after > 100.0f && !(surf_after & SA1_SURFACE_NO_LAND),
          "Sonic on the concrete floor with concrete = noland: the floor keeps no 0x40 (walls: %u of 8 triangles), he "
          "moves %.1f units in 60 pairs (> 100), %d of 140 steps airborne, the game's ground 0x%X", wall_nl, m_after,
          air_after, (unsigned)surf_after);
    CHECK(r2 && m_trap < 20.0f && air_trap == 140,
          "the same floor WITH 0x40 (a per-type kind without the walls-only rule, Review R.3): trapped - %.1f units, %d of "
          "140 steps airborne (the review measured 4.1)", m_trap, air_trap);
    sa1_shutdown(ctx);
}

int main(int argc, char **argv)
{
    std::string gm = gsa1_garrysmod_dir(), gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) {
        gdi = e;
    }
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--gm" && i + 1 < argc) {
            gm = argv[++i];
        } else if (a == "--gdi" && i + 1 < argc) {
            gdi = argv[++i];   // build.py passes --gdi to every feature test: Sonic's run on a "noland" floor
        } else if (a == "--bsp" && i + 1 < argc) {
            ++i;
        }
    }
    std::printf("G-SA1 feat_surfaces_test\n");
    gamefs::GameFs fs(gm);
    test_vmt();
    test_types(fs);
    test_classes();
    test_moving(fs);
    test_kinds_092();
    test_noland(gdi);
    std::printf("feat_surfaces_test: %d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
