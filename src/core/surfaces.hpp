// G-SA1 core: ground types from Garry's Mod's materials (sadc docs/research/gsa1_060_dig.md 6 / 7 F2-F4 with its Review
// R4: G1 the chain cached per slot, G3 moving objects, G7 thin walls, G13 the displacement blend rule).
//
// SA1 decides per land object what a character can do on the ground: Knuckles digs only where the land carries COL bit
// 0x100 (the game's 8C0C8330: hold action, press jump), Ice Cap's ice is 0x4 (no friction), Sand Hill's sand 0x10 (slower).
// A Garry's Mod map says the same per MATERIAL: every brush side and displacement has a material whose .vmt names a
// Source surface type ($surfaceprop "grass"; a blended displacement also $surfaceprop2), and scripts/surfaceproperties.txt
// arranges the types in a hierarchy (grass -> dirt) with a game-material letter (GMod: D dirt, N sand, U grass, J snow).
// This file reads those - every byte bounds-checked: maps, materials and scripts come from servers and workshop addons -
// and maps a surface type to SA1 surface kinds through a CLASS TABLE whose every entry the owner can change on the Q menu
// (Options > G-SA1 > Surfaces). Defaults (the owner's, plan gsa1_rounds_plan.md 14.1d):
//   diggable  dirt grass mud sand gravel snow quicksand antlionsand; game-material letters D N U J  -> SA1_SURFACE_DIG
//   slippery  ice gmod_ice slipperyslime slipperymetal friction_00 friction_10 frictionm_00 frictionm_10 -> SLIPPERY
//   plain     carpet plaster cardboard paper papercup ceiling_tile rubber floatingstandable foliage rock: listed, so the
//             base-chain walk stops there (GMod derives most of them from dirt: "derives from dirt" is no dig rule)
// A type's kinds: its exact name in the table, else the first listed name along its base chain, else its game-material
// letter; nothing found: plain land. Kinds the owner may give a type: diggable, slippery, sand (Sand Hill's slow sand,
// COL 0x10), hurts (0x10000), no climbing (0x1000); "dig anywhere" (not the game's rule) makes every static land triangle
// diggable. Water stays what the brush CONTENTS say (never from a $surfaceprop). Moving objects (brush entities, physics
// props) never get DIG - the game ignores it on DynamicCOL objects (0x08000000) - and keep at most SA1_MAX_OBJECT_GROUPS
// distinct COL words (libsa1 refuses more: class bits are dropped first).
// Round 0.9.2 (sadc docs/research/gsa1_090_surfaces.md sections 2-5, F2 with its Review R.2.3-R.2.5, C3, C4; plan
// gsa1_090_plan.md 6.9): every SA1 ground bit the game's code reads, eight more kinds - snow (COL 0x8, Ice Cap's snow
// slope: a seventh of the acceleration), fast (0x80), slide (0x20000), speedpath (0x800000), stairs (0x4000), noland
// (0x40), wallslide (0x200000), footprints (0x100000; read only by Emerald Coast's footprint task, which G-SA1 worlds do
// not create yet: the page hides it). "noland" and "wallslide" go ONLY on triangles that are no floor (normal z < 0.7 in
// Source space; a double-sided triangle also not with normal z <= -0.7): SA1 puts them only on walls, and on a floor they
// are an inescapable trap (Review R.3: Sonic moves 4.1 units in 60 pairs and cannot jump). Moving objects never get them
// either (a prop can turn over: its wall becomes its top). New kinds are opt-in: the defaults are 0.8's.
//
// Where the pieces go: the map job (mapjob.hpp) reads the materials' .vmt and the scripts through the addon (Garry's
// Mod's file system: map pak, workshop .gma, VPKs), tags every static triangle with the SLOT of its surface type
// (bsp.hpp surface_tag) and caches tags + slots (each slot with its base chain and letter: Review G1), so a change of the
// table only re-applies the classes (apply_surface_classes) and re-prepares the world - no rebuild.
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "bsp.hpp"
#include "phy.hpp"
#include "shape.hpp"

namespace gsa1 {

// ---- KeyValues: the text format of .vmt files, surfaceproperties scripts and the .phy text section ----------------
// Quoted and bare tokens, { } blocks, // comments, [$X360]-style conditions after a key or a value (evaluated for a PC:
// $WIN32 / $WINDOWS / $PC true, the consoles and the other systems false; ! && || allowed; a pair whose condition is
// false is left out). Keys are lower-cased; values keep their case. Limits: 32 levels, max_nodes pairs, 4096-byte tokens.
struct KvNode {
    std::string key, value;
    std::vector<KvNode> kids;
    bool block = false;
    const KvNode *find(const char *lower_key) const;   // the first child with this key (nullptr: none)
};
bool kv_parse(const char *p, size_t n, std::vector<KvNode> &out, std::string &err, size_t max_nodes = 200000);
bool kv_condition(const std::string &cond);            // "[$X360]" -> false, "[!$X360]" -> true

// ---- materials (.vmt) ------------------------------------------------------------------------------------------------
struct VmtInfo {
    std::string shader;                                // lower case: "lightmappedgeneric", "worldvertextransition", "patch"
    bool has_sp = false, has_sp2 = false;              // $surfaceprop / $surfaceprop2 set
    std::string sp, sp2;                               // lower case
    std::string include;                               // patch: the included material ("materials/....vmt"), "" none
    // patch: insert { } sets a parameter; replace { } only replaces one the included material has (Source's
    // ApplyPatchKeyValues as recalled: UNVERIFIED for replace without the parameter in the base)
    bool ins_sp = false, ins_sp2 = false, rep_sp = false, rep_sp2 = false;
    std::string ins_sp_v, ins_sp2_v, rep_sp_v, rep_sp2_v;
};
bool parse_vmt(const char *p, size_t n, VmtInfo &out, std::string &err);
// "materials/<name>.vmt" for a material name or a patch's include (lower case, '/' separators, "materials/" and ".vmt"
// added when missing); "" when it is not a usable path (empty, "..", ':', a leading '/', control bytes, over 200 bytes)
std::string vmt_path(const std::string &material_or_include);

// a material's surface types, patches followed through `lookup` (path -> its parsed .vmt, nullptr: missing / unreadable)
struct VmtSurface {
    std::string sp = "default", sp2;                   // sp2 "": the same as sp (no blend)
    bool found = false;                                // the .vmt was there
    bool explicit_sp = false, explicit_sp2 = false;    // set by the material (not Source's "default")
    bool patched = false;                              // a patch material (cubemaps, map-specific copies)
    bool include_missing = false;                      // a patch whose included material is missing (or nested too deep)
};
VmtSurface resolve_vmt(const std::string &path, const std::function<const VmtInfo *(const std::string &)> &lookup,
                       int max_depth = 4);

// ---- surface types (scripts/surfaceproperties*.txt) ------------------------------------------------------------------
struct SurfaceType {
    std::vector<std::string> chain;                    // the type's name, its base, the base's base ... (at most 16)
    char letter = 0;                                   // game material letter ('D', 'U', ...; inherited; 0 unknown)
    const std::string &name() const;
};

class SurfacePropDb {
public:
    // one surfaceproperties script; a type defined twice keeps its first definition (Source's lookup finds the first)
    bool add_script(const char *p, size_t n, std::string &err);
    // scripts/surfaceproperties_manifest.txt -> the files it lists (normalized paths), in order
    static bool parse_manifest(const char *p, size_t n, std::vector<std::string> &files, std::string &err);
    bool has(const std::string &name) const { return e_.count(name) != 0; }
    // chain and letter (a type without "base" derives from "default", whose letter it inherits; an unknown name: a
    // chain of itself, no letter - Source then uses "default", plain land)
    SurfaceType resolve(const std::string &name) const;
    const std::vector<std::string> &names() const { return order_; }   // in definition order
    size_t size() const { return order_.size(); }

private:
    struct Entry {
        std::string base;
        char letter = 0;
    };
    std::map<std::string, Entry> e_;
    std::vector<std::string> order_;
};

// ---- the class table ------------------------------------------------------------------------------------------------
// The kinds' bits are G-SA1's own (the words are what the addon, the overrides file and SetSurfaceTable use); 0.8's five
// keep their values, so 0.8's tables (and their hashes) are unchanged. The game's precedence among the grip kinds is one
// else-if chain (8C0751C0): of snow / slippery / sand / fast on one surface only the first in that order counts.
enum : uint32_t {
    kKindDig = 1u,          // SA1_SURFACE_DIG (COL 0x100)
    kKindSlippery = 2u,     // SA1_SURFACE_SLIPPERY (COL 0x4: Ice Cap's ice)
    kKindSand = 4u,         // SA1_SURFACE_SAND (COL 0x10: Sand Hill's sand, walking is slower)
    kKindHurt = 8u,         // SA1_SURFACE_HURT (COL 0x10000)
    kKindNoClimb = 16u,     // SA1_SURFACE_NO_CLIMB (COL 0x1000)
    // round 0.9.2 (gsa1_090_surfaces.md 5.1)
    kKindSnow = 32u,        // SA1_SURFACE_SNOW (COL 0x8: Ice Cap's snow slope, weight 0.15; stopping is normal)
    kKindFast = 64u,        // SA1_SURFACE_BOOST (COL 0x80: weight 1.5)
    kKindSlide = 128u,      // SA1_SURFACE_SLIDE (COL 0x20000: Speed Highway's sliding floor)
    kKindSpeedPath = 256u,  // SA1_SURFACE_SPEED_PATH (COL 0x800000: speed track, high-speed turns and slopes)
    kKindStairs = 512u,     // SA1_SURFACE_STAIRS (COL 0x4000: stair mode, upright on slopes)
    kKindNoLand = 1024u,    // SA1_SURFACE_NO_LAND (COL 0x40: never a floor) - walls only
    kKindWallSlide = 2048u, // SA1_SURFACE_WALL_SLIDE (COL 0x200000: no landing, no climbing) - walls only
    kKindFootprints = 4096u,// SA1_SURFACE_FOOTPRINTS (COL 0x100000: Emerald Coast's footprints; no task reads it yet)
    kKindsAll = 8191u,
    kKindsWallOnly = kKindNoLand | kKindWallSlide,                         // never on a floor, never on a moving object
    kKindsSecondSlot = kKindHurt | kKindNoClimb | kKindNoLand | kKindWallSlide,   // a thin wall's other side adds these
};
const unsigned kKindCount = 13;
struct KindInfo {
    uint32_t kind;                                     // kKind*
    const char *word;                                  // the module's word ("speedpath")
    uint32_t surface;                                  // SA1_SURFACE_*
};
// the kinds in the module's order (the order of kinds_string: 0.8's five first, then 0.9.2's eight), kKindCount entries
const KindInfo *kind_table();
// "normal" (0) or kind words joined by ',' ("dig,sand"; "snow,fast"); also "diggable", "ice", "hurts", "no_climb",
// "boost", "speed_path", "speedtrack", "stair", "no_land", "wall_slide", "footprint"; separators ',', ' ', '+', '|';
// false: an unknown word
bool parse_kinds(const std::string &s, uint32_t &out);
std::string kinds_string(uint32_t kinds);              // the module's order; "normal" for 0
uint32_t kinds_surface(uint32_t kinds);                // SA1_SURFACE_* bits
const uint32_t kClassSurfaceBits = SA1_SURFACE_DIG | SA1_SURFACE_SLIPPERY | SA1_SURFACE_SAND | SA1_SURFACE_HURT |
                                   SA1_SURFACE_NO_CLIMB | SA1_SURFACE_SNOW | SA1_SURFACE_BOOST | SA1_SURFACE_SLIDE |
                                   SA1_SURFACE_SPEED_PATH | SA1_SURFACE_STAIRS | SA1_SURFACE_NO_LAND |
                                   SA1_SURFACE_WALL_SLIDE | SA1_SURFACE_FOOTPRINTS;
// the class bits a moving object never gets: DIG (the game never digs a DynamicCOL object) and the walls-only kinds (a
// prop can turn over)
const uint32_t kMoverNeverSurfaceBits = SA1_SURFACE_DIG | SA1_SURFACE_NO_LAND | SA1_SURFACE_WALL_SLIDE;
const uint32_t kMoverNeverKinds = kKindDig | kKindsWallOnly;

struct SurfaceTable {
    std::map<std::string, uint32_t> names;             // listed types -> kinds (0: plain land; listed stops the chain walk)
    std::map<char, uint32_t> letters;                  // game-material letter -> kinds (the last fallback)
    static SurfaceTable defaults();
    // how: "listed", "base <name>", "letter <L>" or "" (nothing: plain land)
    uint32_t kinds_of(const SurfaceType &t, std::string *how = nullptr) const;
    uint32_t hash() const;
};

// a valid table key: 1..64 bytes of [a-z0-9_ .-]
bool valid_surface_name(const std::string &name);

struct SurfaceSettings {
    bool enabled = true;                               // gsa1_surfaces (false: no class bits, 0.6.0's ground)
    bool dig_anywhere = false;                         // gsa1_dig_anywhere: every static land triangle diggable
    SurfaceTable table = SurfaceTable::defaults();
    uint32_t overrides = 0;                            // entries that differ from the defaults (the session log)
    uint32_t hash() const;
};

// ---- the classes on a tagged static world ----------------------------------------------------------------------------
struct SurfaceTypeUse {
    double area = 0.0;                                 // walkable area (n.z >= 0.7), Hammer units^2
    uint32_t tris = 0;                                 // land triangles
    uint32_t kinds = 0;                                // the table's kinds for the type
    std::string how;                                   // SurfaceTable::kinds_of
};
struct SurfaceSummary {
    std::vector<SurfaceTypeUse> types;                 // parallel to the slots
    double walkable = 0.0;                             // walkable land area (Hammer units^2) ...
    double dig = 0.0, slippery = 0.0, sand = 0.0, hurt = 0.0, noclimb = 0.0;   // ... of which with these kinds
    uint32_t tris = 0, tris_classed = 0, tris_dig = 0, tris_slippery = 0, tris_untagged = 0;
    bool enabled = true, dig_anywhere = false;
    uint32_t hash = 0, overrides = 0;
    double ms = 0.0;
    // round 0.9.2: every kind (kind_table()'s order) - the walkable area with its bit, the area of the other land (walls,
    // slopes steeper than 45.6 degrees, ceilings; never-drawn faces left out) with its bit, and its land triangles. The
    // bits counted are the triangle's final ones (also the map's own: a GRATE's no climbing, G-SA1's stair ramps).
    double wall = 0.0;                                 // the land area that is no walkable ground (Hammer units^2)
    double kind_area[kKindCount] = {}, kind_wall[kKindCount] = {};
    uint32_t kind_tris[kKindCount] = {};
    uint32_t wall_only_floors = 0;                     // floor triangles of a noland / wallslide type left without it (C3)
};
// ORs the class bits into the land triangles of `world` (tags: bsp.hpp surface_tag per triangle, may be empty; water and
// kill triangles are left alone; a thin wall's second slot adds only its hurts / no-climbing / not-a-floor / slide-off
// kinds: Review G7; noland and wallslide only on triangles that are no floor, 0.9.2 Review C3)
void apply_surface_classes(std::vector<sa1_collision_tri> &world, const std::vector<uint32_t> &tags,
                           const std::vector<SurfaceType> &types, const SurfaceSettings &s, SurfaceSummary &out);

// ---- moving objects -------------------------------------------------------------------------------------------------
uint32_t surface_col(uint32_t surface);               // libsa1's COL word of a surface word (its sa1ca_surface_col)
// DIG removed always; then, when the triangles carry more than max_words distinct collidable COL words (libsa1's
// obj_create refuses such an object with SA1_ERR_LIMIT), the `droppable` class bits are removed as well. Returns the
// bits removed.
uint32_t cap_object_words(std::vector<sa1_collision_tri> &tris, uint32_t droppable,
                          uint32_t max_words = SA1_MAX_OBJECT_GROUPS);
// shape_from_phy (shape.hpp) with surface kinds: solid_bits[i] = the SA1_SURFACE_* class bits of the .phy's solid i
// (kMoverNeverSurfaceBits never apply); every chunk capped by cap_object_words. capped: chunks that lost class bits.
bool shape_from_phy_classed(const PhyModel &m, const std::vector<uint32_t> &solid_bits, Shape &out, std::string &err,
                            float thin_wall_max = 16.0f, uint32_t *capped = nullptr);

}  // namespace gsa1
