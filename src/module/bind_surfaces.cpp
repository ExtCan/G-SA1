// G-SA1 module: the surfaces feature "surfaces" (sadc docs/research/gsa1_060_dig.md 6.3 item 5 / 6.4 / F6 with its Review
// R4; plan gsa1_rounds_plan.md 14.1d). Ground types from Garry's Mod's materials (src/core/surfaces.hpp): the map job
// tags the static world with each triangle's Source surface type and applies the CLASS TABLE set here (diggable,
// slippery, sand, hurts, no climbing; 0.9.2: snow, fast ground, sliding floor, speed track, stairs, not a floor,
// slide-off wall, footprints); the Q-menu page is the addon's gsa1/feat/cl_surfaces.lua.
//
// Lua API (feature version 2; GSA1.HasFeature("surfaces", 2)). Version 2 (round 0.9.2, sadc
// docs/research/gsa1_090_surfaces.md F2 with its Review C3 / C4, plan gsa1_090_plan.md 6.9): the kind words of every SA1
// ground bit (snow fast slide speedpath stairs noland wallslide footprints besides 0.8's five), "noland" / "wallslide"
// only on triangles that are no floor (and never on a physics prop), SurfaceInfo's per-kind fields (each word's walkable
// area, `wall`, `walls`, `kind_tris`, `wall_only_floors`). Version 1 (0.8) had the five kinds of 0.8.
//   gsa1.SetSurfaceTable(overrides, options) -> true, hash, changed, skipped | false, message
//       overrides: { "<surface type>=<kinds>", ... } (an array; kinds "dig", "slippery", "sand", "hurt", "noclimb",
//       "snow", "fast", "slide", "speedpath", "stairs", "noland", "wallslide", "footprints", "normal" or several joined
//       by ',', e.g. "concrete=dig", "sand=dig,sand", "ice=snow,fast"; the words of gsa1::kind_table, aliases as
//       parse_kinds): the owner's entries over the built-in defaults (at most 1024; a bad entry is skipped and counted);
//       options: { enabled = true (gsa1_surfaces), dig_anywhere = false (gsa1_dig_anywhere) }. The settings go into the
//       next map job (gsa1.MapStart / MapStartData: a cache hit re-applies them and prepares the world again - the addon
//       puts `hash` into its world key so that a change starts one) and into the physics props' shapes (gsa1.ShapePhy;
//       a change drops the props' shapes and the moving objects, which the addon then rebuilds).
//   gsa1.SurfaceDefaults() -> { [type] = kinds string }, { [letter] = kinds string }   (the built-in table)
//   gsa1.SurfaceKind(name [, letter]) -> kinds string, how   (what the current table makes of a surface type: the
//       applied map's base chain when it knows the type; letter: the game-material letter, a one-character string or its
//       code, for types the map does not know; how: "listed", "base <name>", "letter <L>" or "")
//   gsa1.SurfaceInfo([out]) -> out | nil (no map applied yet)
//       {map, enabled, dig_anywhere, hash, overrides, materials, materials_used, materials_bad, vmt_found, vmt_missing,
//        vmt_bad, vmt_patches, vmt_includes_missing, vmt_default, vmt_blends, scripts, type_count, props_surfaceprop,
//        walkable, dig, slippery, sand, hurt, noclimb (walkable areas, square Hammer units), tris, tris_classed,
//        tris_dig, tris_slippery, tris_untagged, coplanar_mixed, thin_walls_mixed, disp_tris_blend, stairs_tagged,
//        classes_ms, props_classed, props_capped,
//        version 2: snow, fast, slide, speedpath, stairs, noland, wallslide, footprints (walkable areas, as dig ...),
//        wall (the land that is no walkable ground: walls, steep slopes, ceilings), walls = { [word] = area of that
//        land with the kind } (all 13 words), kind_tris = { [word] = land triangles with the kind }, wall_only_floors
//        (floor triangles of a noland / wallslide type left without it),
//        types = { {name, kinds, how, area, tris, chain ("grass > dirt"), letter}, ... } (by area, largest first, then
//        every other type of the map's surfaceproperties scripts by name)}
// Moving objects: brush entities get no surface classes (Review G4); physics props get their .phy solids' types without
// DIG (the game never digs a DynamicCOL object), without noland / wallslide (a prop can turn over: its wall becomes its
// top) and at most SA1_MAX_OBJECT_GROUPS COL words per chunk (Review G3).
#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/mapjob.hpp"
#include "../core/surfaces.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;

namespace {

const size_t kMaxOverrides = 1024;

gsa1::SurfaceSettings g_settings;           // the current settings (the built-in table until SetSurfaceTable)
uint32_t g_hash = 0;
bool g_hash_set = false;
// the applied map (MapApply)
bool g_have_map = false;
std::string g_map;
std::vector<gsa1::SurfaceType> g_types;
std::map<std::string, size_t> g_type_index;
gsa1::SurfaceSummary g_summary;
gsa1::MapStats g_stats;
uint32_t g_props_classed = 0, g_props_capped = 0;

uint32_t current_hash()
{
    if (!g_hash_set) {
        g_hash = g_settings.hash();
        g_hash_set = true;
    }
    return g_hash;
}

gsa1::SurfaceType type_of(const std::string &name, char letter = 0)
{
    auto it = g_type_index.find(name);
    if (it != g_type_index.end() && it->second < g_types.size()) {
        return g_types[it->second];
    }
    gsa1::SurfaceType t;
    t.chain.push_back(name);
    t.letter = letter;
    return t;
}

std::string chain_text(const gsa1::SurfaceType &t)
{
    std::string s;
    for (const std::string &n : t.chain) {
        s += (s.empty() ? "" : " > ") + n;
    }
    return s;
}

}  // namespace

// ---- what gsa1_module.cpp calls (declared there) ----------------------------------------------------------------------
namespace gsa1 {
namespace mod {

// MapStart / MapStartData: the job applies the current class table
void surfaces_map_options(gsa1::MapJobOptions &o)
{
    o.surfaces = g_settings;
}

// MapApply: the applied map's surface types and classes (for SurfaceInfo, SurfaceKind and the props' shapes)
void surfaces_map_applied(const gsa1::MapResult &r)
{
    g_have_map = true;
    g_map = r.map;
    g_types = r.types;
    g_type_index.clear();
    for (size_t i = 0; i < g_types.size(); i++) {
        g_type_index[g_types[i].name()] = i;
    }
    g_summary = r.surf;
    g_stats = r.st;
}

// ShapePhy: a physics prop's shape with its solids' surface kinds (no DIG; capped to libsa1's word limit)
bool surfaces_shape_phy(const gsa1::PhyModel &m, gsa1::Shape &out, std::string &err, float thin_wall_max)
{
    if (!g_settings.enabled) {
        return gsa1::shape_from_phy(m, out, err, thin_wall_max);
    }
    std::vector<uint32_t> bits(m.solid_surfaceprop.size(), 0u);
    bool any = false;
    for (size_t i = 0; i < m.solid_surfaceprop.size(); i++) {
        if (m.solid_surfaceprop[i].empty()) {
            continue;
        }
        uint32_t k = g_settings.table.kinds_of(type_of(m.solid_surfaceprop[i])) & ~gsa1::kMoverNeverKinds;
        bits[i] = gsa1::kinds_surface(k);
        any = any || bits[i] != 0;
    }
    if (!any) {
        return gsa1::shape_from_phy(m, out, err, thin_wall_max);   // exactly 0.7's shape
    }
    uint32_t capped = 0;
    if (!gsa1::shape_from_phy_classed(m, bits, out, err, thin_wall_max, &capped)) {
        return false;
    }
    g_props_classed++;
    g_props_capped += capped;
    return true;
}

}  // namespace mod
}  // namespace gsa1

// gsa1.SetSurfaceTable(overrides, options) -> true, hash, changed, skipped | false, message
GSA1_FN(gsa1_surfaces_SetSurfaceTable)
{
    if (!LUA->IsType(1, LT::Table) && !LUA->IsType(1, LT::Nil)) {
        return push_false_msg(LUA, "SetSurfaceTable(overrides {\"type=kinds\", ...}, options {enabled =, dig_anywhere =})");
    }
    gsa1::SurfaceSettings s;
    s.enabled = true;
    s.dig_anywhere = false;
    if (LUA->IsType(2, LT::Table)) {
        int t = absidx(LUA, 2);
        bool b;
        if (raw_get_bool(LUA, t, "enabled", b)) s.enabled = b;
        if (raw_get_bool(LUA, t, "dig_anywhere", b)) s.dig_anywhere = b;
    }
    const gsa1::SurfaceTable defaults = gsa1::SurfaceTable::defaults();
    uint32_t skipped = 0;
    if (LUA->IsType(1, LT::Table)) {
        int t = absidx(LUA, 1);
        for (int i = 1; i <= (int)kMaxOverrides + 1; i++) {
            LUA->PushNumber(i);
            LUA->RawGet(t);
            if (LUA->IsType(-1, LT::Nil)) {
                LUA->Pop(1);
                break;
            }
            bool ok = false;
            if (LUA->IsType(-1, LT::String) && i <= (int)kMaxOverrides) {
                unsigned int len = 0;
                const char *p = LUA->GetString(-1, &len);
                std::string e = p && len <= 160 ? std::string(p, len) : std::string();
                size_t eq = e.find('=');
                if (eq != std::string::npos) {
                    std::string name = gsa1::to_lower(e.substr(0, eq)), kinds_s = e.substr(eq + 1);
                    while (!name.empty() && name.back() == ' ') {
                        name.pop_back();
                    }
                    while (!name.empty() && name.front() == ' ') {
                        name.erase(0, 1);
                    }
                    uint32_t kinds = 0;
                    if (gsa1::valid_surface_name(name) && gsa1::parse_kinds(kinds_s, kinds)) {
                        s.table.names[name] = kinds;
                        ok = true;
                    }
                }
            }
            skipped += !ok;
            LUA->Pop(1);
        }
    }
    for (const auto &kv : s.table.names) {
        auto d = defaults.names.find(kv.first);
        s.overrides += d == defaults.names.end() || d->second != kv.second;
    }
    uint32_t h = s.hash();
    bool changed = h != current_hash();
    g_settings = s;
    g_hash = h;
    g_hash_set = true;
    if (changed) {
        // the physics props' shapes carry the old classes: dropped (the addon builds them again when it sees them),
        // and the moving objects in libsa1 with them (MapApply does the same when the map changes)
        gsa1::Session *se = session();
        if (se) {
            se->movers().clear(se->ctx());
            se->movers().drop_shapes("m:");
        }
    }
    LUA->PushBool(true);
    LUA->PushNumber((double)h);
    LUA->PushBool(changed);
    LUA->PushNumber(skipped);
    return 4;
}

// gsa1.SurfaceDefaults() -> { [type] = kinds }, { [letter] = kinds }
GSA1_FN(gsa1_surfaces_SurfaceDefaults)
{
    gsa1::SurfaceTable d = gsa1::SurfaceTable::defaults();
    LUA->CreateTable();
    int t = LUA->Top();
    for (const auto &kv : d.names) {
        raw_str(LUA, t, kv.first.c_str(), gsa1::kinds_string(kv.second));
    }
    LUA->CreateTable();
    int l = LUA->Top();
    for (const auto &kv : d.letters) {
        char k[2] = {kv.first, 0};
        raw_str(LUA, l, k, gsa1::kinds_string(kv.second));
    }
    return 2;
}

// gsa1.SurfaceKind(name [, letter]) -> kinds, how | nil, message
GSA1_FN(gsa1_surfaces_SurfaceKind)
{
    std::string name;
    if (!arg_string(LUA, 1, name, 64)) {
        return push_nil_msg(LUA, "SurfaceKind(surface type name [, game-material letter])");
    }
    name = gsa1::to_lower(name);
    char letter = 0;
    std::string ls;
    double lc = 0;
    if (arg_string(LUA, 2, ls, 1) && ls.size() == 1) {
        letter = ls[0];
    } else if (arg_number(LUA, 2, lc) && lc > 32 && lc < 127) {
        letter = (char)lc;
    }
    if (letter >= 'a' && letter <= 'z') {
        letter = (char)(letter - 32);
    }
    std::string how;
    uint32_t k = g_settings.table.kinds_of(type_of(name, letter), &how);
    if (!g_settings.enabled) {
        k = 0;
        how = "off";
    }
    LUA->PushString(gsa1::kinds_string(k).c_str());
    LUA->PushString(how.c_str());
    return 2;
}

// gsa1.SurfaceInfo([out]) -> out | nil
GSA1_FN(gsa1_surfaces_SurfaceInfo)
{
    if (!g_have_map) {
        LUA->PushNil();
        return 1;
    }
    int t = out_table(LUA, 1);
    const gsa1::SurfaceSummary &u = g_summary;
    const gsa1::MapStats &st = g_stats;
    raw_str(LUA, t, "map", g_map);
    raw_bool(LUA, t, "enabled", u.enabled);
    raw_bool(LUA, t, "dig_anywhere", u.dig_anywhere);
    raw_num(LUA, t, "hash", u.hash);
    raw_num(LUA, t, "overrides", u.overrides);
    raw_num(LUA, t, "materials", st.materials);
    raw_num(LUA, t, "materials_used", st.materials_used);
    raw_num(LUA, t, "materials_bad", st.materials_bad);
    raw_num(LUA, t, "vmt_found", st.vmt_found);
    raw_num(LUA, t, "vmt_missing", st.vmt_missing);
    raw_num(LUA, t, "vmt_bad", st.vmt_bad);
    raw_num(LUA, t, "vmt_patches", st.vmt_patches);
    raw_num(LUA, t, "vmt_includes_missing", st.vmt_includes_missing);
    raw_num(LUA, t, "vmt_default", st.vmt_default);
    raw_num(LUA, t, "vmt_blends", st.vmt_blends);
    raw_num(LUA, t, "scripts", st.surface_scripts);
    raw_num(LUA, t, "type_count", (double)g_types.size());
    raw_num(LUA, t, "props_surfaceprop", st.props_surfaceprop);
    raw_num(LUA, t, "walkable", u.walkable);
    raw_num(LUA, t, "dig", u.dig);
    raw_num(LUA, t, "slippery", u.slippery);
    raw_num(LUA, t, "sand", u.sand);
    raw_num(LUA, t, "hurt", u.hurt);
    raw_num(LUA, t, "noclimb", u.noclimb);
    raw_num(LUA, t, "tris", u.tris);
    raw_num(LUA, t, "tris_classed", u.tris_classed);
    raw_num(LUA, t, "tris_dig", u.tris_dig);
    raw_num(LUA, t, "tris_slippery", u.tris_slippery);
    raw_num(LUA, t, "tris_untagged", u.tris_untagged);
    raw_num(LUA, t, "coplanar_mixed", st.world.coplanar_mixed);
    raw_num(LUA, t, "thin_walls_mixed", st.world.thin_walls_mixed);
    raw_num(LUA, t, "disp_tris_blend", st.world.disp_tris_blend);
    raw_num(LUA, t, "stairs_tagged", st.world.stairs_tagged);
    raw_num(LUA, t, "classes_ms", u.ms);
    raw_num(LUA, t, "props_classed", g_props_classed);
    raw_num(LUA, t, "props_capped", g_props_capped);
    // version 2: every kind
    const gsa1::KindInfo *kt = gsa1::kind_table();
    for (unsigned i = 0; i < gsa1::kKindCount; i++) {
        if (kt[i].kind & (gsa1::kKindDig | gsa1::kKindSlippery | gsa1::kKindSand | gsa1::kKindHurt | gsa1::kKindNoClimb)) {
            continue;   // 0.8's fields above (the same numbers)
        }
        raw_num(LUA, t, kt[i].word, u.kind_area[i]);
    }
    raw_num(LUA, t, "wall", u.wall);
    raw_num(LUA, t, "wall_only_floors", u.wall_only_floors);
    LUA->PushString("walls");
    LUA->CreateTable();
    int wt = LUA->Top();
    for (unsigned i = 0; i < gsa1::kKindCount; i++) {
        raw_num(LUA, wt, kt[i].word, u.kind_wall[i]);
    }
    LUA->RawSet(t);
    LUA->PushString("kind_tris");
    LUA->CreateTable();
    int kt_tab = LUA->Top();
    for (unsigned i = 0; i < gsa1::kKindCount; i++) {
        raw_num(LUA, kt_tab, kt[i].word, u.kind_tris[i]);
    }
    LUA->RawSet(t);
    // the map's types: the ones with land first (by area, then triangles), then the rest by name
    std::vector<size_t> order(g_types.size());
    for (size_t i = 0; i < order.size(); i++) {
        order[i] = i;
    }
    auto use = [&](size_t i) -> const gsa1::SurfaceTypeUse * { return i < u.types.size() ? &u.types[i] : nullptr; };
    std::sort(order.begin(), order.end(), [&](size_t a, size_t b) {
        const gsa1::SurfaceTypeUse *ua = use(a), *ub = use(b);
        double aa = ua ? ua->area : 0.0, ab = ub ? ub->area : 0.0;
        uint32_t ta = ua ? ua->tris : 0u, tb = ub ? ub->tris : 0u;
        if (aa != ab) return aa > ab;
        if (ta != tb) return ta > tb;
        return g_types[a].name() < g_types[b].name();
    });
    LUA->PushString("types");
    LUA->CreateTable();
    int tt = LUA->Top();
    int k = 0;
    for (size_t i : order) {
        const gsa1::SurfaceType &ty = g_types[i];
        LUA->PushNumber(++k);
        LUA->CreateTable();
        int e = LUA->Top();
        std::string how;
        uint32_t kinds = g_settings.table.kinds_of(ty, &how);
        raw_str(LUA, e, "name", ty.name());
        raw_str(LUA, e, "kinds", gsa1::kinds_string(kinds));
        raw_str(LUA, e, "how", how);
        raw_num(LUA, e, "area", use(i) ? use(i)->area : 0.0);
        raw_num(LUA, e, "tris", use(i) ? use(i)->tris : 0u);
        raw_str(LUA, e, "chain", chain_text(ty));
        raw_str(LUA, e, "letter", ty.letter ? std::string(1, ty.letter) : std::string());
        LUA->RawSet(tt);
    }
    LUA->RawSet(t);
    return 1;
}

static const gsa1::FeatureFn k_surfaces_fns[] = {
    {"SetSurfaceTable", gsa1_surfaces_SetSurfaceTable},
    {"SurfaceDefaults", gsa1_surfaces_SurfaceDefaults},
    {"SurfaceKind", gsa1_surfaces_SurfaceKind},
    {"SurfaceInfo", gsa1_surfaces_SurfaceInfo},
};
GSA1_FEATURE(surfaces, 2, k_surfaces_fns, nullptr, nullptr, gsa1::kCloseDefault);
