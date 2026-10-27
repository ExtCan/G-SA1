// G-SA1 core: Source engine BSP (versions 19 and 20, the ones Garry's Mod loads) -> collision triangles.
//
// Every map is untrusted input (servers send their own maps): all lump offsets, sizes, counts and indices are
// checked. The collision is built the way sadc docs/research/gsa1_ramp_freeze.md recommends: G64's SOURCES (world
// brushes, displacements, static props with their physics models, brush entities and props as moving objects), but
// the triangles are always CLEANED before they reach libsa1, because SA1's land collision is surface based (a
// sphere tested against every polygon near it, a 96 / 256-entry NEAR-poly list): raw hull data (G64's) makes the
// characters fall through floors more often, not less (48 -> 80 ramp falls on gm_freespace_13).
//
// The pipeline (one set of convex SOLIDS: the brushes of a model, plus extra convex solids such as static props'
// physics hulls):
//   * each solid's faces: a brush side clipped by the brush's other sides (bevels left out), a hull's faces from
//     its coplanar triangles; counter-clockwise seen from outside (right-handed, Z up);
//   * curved surfaces (curved, 0.9.3: sadc docs/research/gsa1_091a_loop.md LOOP-G1 with its Review R.4): BEFORE the
//     rules below, the faces of all solids (not the floors: n.z < 0.5) are joined across solids along shared edges
//     (collinear, overlapping by 1 unit or more) that are coplanar, or smooth (normals within curved_max_angle), concave
//     and of a large curve (the centroids' distance over the bend at least curved_min_radius); a group that holds a
//     wall-like face (-0.1 <= n.z < 0.5) and a ceiling-like face (n.z <= -0.5) is a curved surface - a loop's, a pipe's
//     or an arch's inside (a plank's underside meets its sides at convex edges: never). Its faces carry SA1_SURFACE_CURVED (libsa1's
//     GRID never leaves them out as undersides within reach) and the one-way, low-ceiling, thin-wall and thin-stack
//     rules leave them alone: the running surface of a loop stays continuous (gm_genesis: with thin walls at 32 the
//     loop's steep segments became middle faces 16 units off the running surface and Sonic was put on top of the loop).
//     A curved ribbon at most curved_ribbon_max thick becomes ONE double-sided middle surface over all its curved faces
//     (two single-sided faces that close are both within a sphere's reach); its solids are never thickened;
//   * one-way thin platforms (one_way_max, fix 2): a down-facing face (n.z <= -0.5) of a solid whose walkable top
//     (n.z >= one_way_walkable) lies at most one_way_max above it everywhere is not an ordinary land face: SA1 touches
//     a single-sided polygon from behind within the sphere's radius: at speed the first step onto a slope dips 5-10
//     units into it, and a plank's underside then pushed the character out BELOW the plank (it ran on under the
//     ramp). These solids are not thickened. one_way_cross extends the rule to a down face with a walkable face
//     of ANY solid (or a displacement) that close above it (planks made of several brushes, props on brushes).
//     Until 0.9.2 such faces were left out (the platform collided from above only: every thin roof and ceiling could
//     be jumped through, the owner's gm_bigcity / gm_construct_in_flatgrass_v3 notes). 0.9.3 (one_way_front_only,
//     sadc docs/research/gsa1_091b_ceiling.md FIX-C3 with its Review R.5.1): a near-horizontal one (n.z <= -0.97, within
//     14 degrees of level, as libsa1's GRID c2: the doc's -0.9 let dash-panel runs dip under 20-25 degree plank ramps) is
//     kept as a FRONT-ONLY ceiling (SA1_SURFACE_FRONT_ONLY: libsa1's sphere test skips it when the sphere starts behind
//     it, i.e. above it - exactly as if it were left out - and from below it is the ceiling the game's head contact
//     stops a jump at); steeper ones are left out as before, and so are those with nothing walkable under them within
//     1024 units (the floor slab of a map's lowest level: no one can be below it, and every front-only ceiling takes a
//     land-object slot of the game's collision query). The low-ceiling test below comes first;
//   * low ceilings (low_ceiling_max): a down face at most 32 units above a walkable surface is left out too: no
//     character fits under it (Sonic is 40 units tall), and touched from behind it pushes the character down
//     through the floor below (the bottom board of a warehouse shelf 8 units above the floor, a prop hovering a
//     unit above it: gm_driversheaven_tdm's random play);
//   * thin walls (thin_wall_max): two opposite steep faces (|n.z| < 0.5) of a solid at most thin_wall_max apart
//     become ONE double-sided face (SA1_SURFACE_DOUBLE_SIDED) halfway between them. Stepping into one side of a wall
//     deeper than the wall is thick, the character touched the other side's polygon from behind as well, whose
//     pushback cancelled the first one (the game averages an object's pushbacks): it walked, slid or sank through
//     8-unit fences, panes and doors (gm_freespace_13's random play). A double-sided polygon pushes the sphere out to
//     the side its centre is on; the character stops at most half the wall's thickness inside the drawn wall. 0.9.2
//     (sadc docs/research/gsa1_090_water.md GRID-TW1 = gsa1_090_collision.md F4): the middle face is clipped by every
//     plane of the solid except A's and B's own and by the solid's box (+-0.5 units); a middle face larger than both
//     faces is no cross-section (the pair is kept as it is); a hull is not closed (no thin wall, clips nothing) when it
//     is flatter than 0.1 units or its planes have fewer than 3 directions. Until 0.9.1 a plane within 2.6 degrees of
//     the wall's was skipped, so sliver prop hulls and wedge brushes made middle faces through the whole map
//     (rp_rockford_v2b: 136,791 triangles beyond +-16384 and a GRID over its limit; rp_nycity: invisible walls 464
//     units high);
//   * thin stacks (thin_stacks, 0.9.2, gsa1_090_collision.md F3): after the one-way rule, the steep faces (|n.z| < 0.5)
//     of any solid or displacement, single- or double-sided, that have a parallel steep face (|dot| >= 0.9, either
//     facing) within thin_wall_max along +-n at every sample point (the centroid, the corners 10 % in) are left out,
//     and the faces they found become double-sided (ranked: double-sided faces first, then the lower solid index;
//     displacements after the solids; a second pass leaves out a smaller face of a lower rank covered by a larger
//     one). What the per-solid rule misses: displacement walls on both sides of a brush, tapered hulls, two solids
//     back to back, coincident faces, two thin solids side by side (a fence of two panels: the character was held
//     between the two faces' opposite push-backs, or crossed them). A large face is never left out for a small one in
//     front of it (not every sample point is covered); the kept face takes the dropped face's surface type as its
//     tag's second slot (and its no-climbing);
//   * guard (0.9.2, gsa1_090_water.md GRID-GUARD): triangles with a corner outside the model's bounds + 64 units (the
//     kill plane excepted) and pieces of a solid's face outside that solid's box + 1 unit are left out and counted
//     (tris_outside, frags_outside): the next geometry bug of this kind is a count, not a GRID failure;
//   * coplanar down faces (coplanar_down, 0.9.2, gsa1_090_collision.md F6): a down face lying exactly on a walkable
//     face of another solid or a displacement (0 units apart, facing the other way) loses the overlapping part (the
//     one-way rule needs a gap, and the low-ceiling rule the whole face covered: rp_nycity, Knuckles fell through);
//   * thin floors thickened (thin_floor_min): only solids that are not one-way (with one-way on: practically none);
//   * hidden faces removed (remove_hidden): the parts of a face that lie inside another closed solid, or on
//     another solid's face looking into it (the faces where two solids touch), are cut away, and of two coplanar
//     faces facing the same way the lower solid index keeps the overlap. Buried faces would be polygons the player
//     collides with from inside the solid, and every one of them counts against the game's NEAR-poly list
//     (8C028BFE), whose overflow drops the rest of the polygons around the character (falling through upper
//     floors and roofs);
//   * stairs made ramps (stair_ramps, world brushes): a run of 3 or more risers becomes a wedge from the floor in
//     front of it to its top nosing, emitted SOLID | STAIRS, as SA1's own stairs are;
//   * the pieces of a face merged again where their union is convex; optionally cut into well-shaped cells no
//     longer than tess_max (moving objects: libsa1 does not split their triangles; the static world is cut by
//     libsa1's GRID); each piece's triangles are emitted consecutively as a fan with one surface word (libsa1 joins
//     them back into the face before its own cutting);
//   * displacements (DISPINFO + DISP_VERTS) triangulated on their base face; the brushes that carry one are
//     dropped, as the engine does - 0.9.3 (disp_brush_exact): a brush whose side IS the base face (corners within 1
//     unit, area within 1 %); vbsp writes no displacement's own brush into the brush lump (no brush side is a base face
//     on 10 maps checked), so 0.9.2's rule (a side on the face's plane, the face's centre inside the brush) only dropped
//     innocent brushes beside a displacement on the same plane: gm_highway14800's tunnel floors (brushes 53-59, 76-82,
//     120-126 next to short flat displacements: the owner's four falls into the death zone), 29 brushes there, 3 on
//     gm_construct_in_flatgrass_v3 (4.6 M square units of floor); a displacement whose minTess carries vbsp's flag bit 0x80000000 and
//     SURF_NOHULL_COLL (0x4) is left out (disp_nohull, 0.9.2, gsa1_090_water.md WTR-DISP: the engine's hull traces
//     pass it - Source SDK 2013 dispcoll_common.cpp; rp_nycity's river surface, 4 units above the water, was a floor);
//     triangles buried inside a solid brush (all corners inside) are left out like
//     hidden brush faces (terrain a few units under a brush floor is within the sphere's reach); and the other way round
//     (disp_cover, 0.9.3): the parts of the up faces (n.z >= 0.5) of solids and hulls that lie under displacement ground
//     - in a displacement's footprint (the XY hull of its points), an up-facing displacement triangle 0.5 .. disp_cover_max
//     above them everywhere and no down face (a solid's or a displacement's) between, which would make it a room - are
//     cut out along the footprint (and, where the ground crosses the face, along its triangles): a brush top a few units
//     under flat ground made the character sink into roads, and a slab top in the void under the terrain held him there
//     (gm_construct_in_flatgrass_v3 at (-1834 -36): the slab at -8600 under the terrain at -8505). Winding (fix 5):
//     the engine's displacement surface faces along its base face's PLANE normal (the face's side flag does not turn it round: on gm_driversheaven_tdm 85 of 85 decidable
//     displacements on back-side faces), and where the map's own triangle tags (DISP_TRIS: the walkable bit vbsp
//     sets for n.z >= 0.7 in the engine's winding) decide, they are followed;
//   * kill plane: an upward-facing rectangle below the world model's bounds (SA1_SURFACE_KILL).
// Surface flags (SA1_SURFACE_*):
//   SOLID | WINDOW | GRATE | MOVEABLE | PLAYERCLIP contents  -> SOLID (glass, grates and clips: + NO_CLIMB)
//   WATER | SLIME contents                                    -> WATER (libsa1 keeps the upward faces)
//   sides with SURF_SKY / SURF_SKY2D                          -> SOLID + NO_CLIMB (counted as sky)
//   SURF_NODRAW sides                                         -> SOLID (counted)
// Brush models (*1, *2, ...: doors, func_brush, trains): build_model, in the model's own space (the entity's
// origin and angles place it). Static props: static_props (the sprp game lump); their physics hulls are parsed by
// phy.hpp and passed back to build_world as ConvexSolids. Not supported: LZMA-compressed lumps (reported).
// Surface types (sadc docs/research/gsa1_060_dig.md F1 with its Review R4.3; surfaces.hpp): materials() lists the
// TEXDATA lumps' material names; given BspSurfaceSlots (per TEXDATA entry the slot of its material's $surfaceprop /
// $surfaceprop2), build_world tags every triangle with surface_tag(slot): a brush face with its side's material, a
// displacement triangle with $surfaceprop2 when the alphas of its three corners add up to more than 382.5 (Source's
// DISP_ALPHA_PROP_DELTA, recalled: UNVERIFIED), a static prop's hull with ConvexSolid::sp, the pieces of a face cut by
// other solids with their face's slot. Rules where faces meet: of two coplanar faces facing the same way the lower
// solid index keeps the overlap - its slot too (G6; how often another surface type loses that way: coplanar_mixed);
// a thin wall takes the slot of the side facing more upward and the other side's slot as the tag's second slot, which
// adds only hurts / no-climbing (G7); a stair ramp takes the slot with the largest tread area it replaces. The
// triangles themselves (and their surface words) are the same with or without slots.
#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "libsa1_internal_api.hpp"
#include "util.hpp"

namespace gsa1 {

class ByteSource {
public:
    virtual ~ByteSource() {}
    virtual uint64_t size() const = 0;
    virtual bool read(uint64_t offset, void *dst, size_t n) = 0;
};

class FileByteSource : public ByteSource {
public:
    bool open(const std::string &utf8_path, std::string &err) { return f_.open(utf8_path, err); }
    uint64_t size() const override { return f_.size(); }
    bool read(uint64_t offset, void *dst, size_t n) override { return f_.read_at(offset, dst, n); }

private:
    File f_;
};

class MemoryByteSource : public ByteSource {
public:
    MemoryByteSource(const void *p, size_t n) : p_((const uint8_t *)p), n_(n) {}
    uint64_t size() const override { return n_; }
    bool read(uint64_t offset, void *dst, size_t n) override;

private:
    const uint8_t *p_;
    size_t n_;
};

// The ranges of a file a reader handed over: the addon reads only the lumps G-SA1 needs through Garry's Mod's own
// file system (workshop and mounted maps, which the module cannot open itself) and feeds them in pieces. Reading
// outside what was added fails.
class RangeByteSource : public ByteSource {
public:
    explicit RangeByteSource(uint64_t size) : size_(size) {}
    uint64_t size() const override { return size_; }
    bool read(uint64_t offset, void *dst, size_t n) override;
    // adds [offset, offset + n) (overlaps are fine; later bytes win); false: outside the file
    bool add(uint64_t offset, const void *p, size_t n);
    bool has(uint64_t offset, uint64_t n) const;
    // the parts of [offset, offset + n) not added yet
    void missing(uint64_t offset, uint64_t n, std::vector<std::pair<uint64_t, uint64_t>> &out) const;
    uint64_t bytes() const { return bytes_; }

private:
    uint64_t size_;
    uint64_t bytes_ = 0;
    std::map<uint64_t, std::string> chunks_;   // offset -> bytes (not overlapping each other)
};

struct BspWorldOptions {
    bool displacements = true;
    bool water = true;
    bool playerclip = true;               // collide with player-clip brushes
    bool skip_displacement_brushes = true;
    bool kill_plane = true;
    float kill_margin = 32.0f;            // Hammer units below the world model's lowest point
    uint32_t max_triangles = 3000000u;
    bool disp_transpose = false;          // diagnostics only: the other corner convention
    bool disp_tags = true;                // displacement winding: follow the map's walkable tags where they decide
    bool disp_side_flip = false;          // diagnostics only: 0.4's winding (the face's side flag turns it round)
    bool remove_hidden = true;            // cut away faces inside / between solid brushes (see above)
    float one_way_max = 24.0f;            // Hammer units; one-way thin platforms (see above); 0 = off
    float one_way_walkable = 0.5f;        // n.z of a walkable top (24.5-degree planks: 0.91; 60 degrees: 0.5)
    bool one_way_cross = true;            // also with a walkable face of another solid / a displacement above
    float low_ceiling_max = 32.0f;        // Hammer units: down faces this close above a walkable surface are left out
                                          // (no character fits under them; needs one_way_cross; 0 = off)
    float thin_wall_max = 16.0f;          // Hammer units: two opposite steep faces of a solid this close become one
                                          // double-sided face halfway between them (thin walls, see above); 0 = off
    float thin_floor_min = 12.0f;         // Hammer units; solids that are not one-way with a walkable top less thick
                                          // than this get their bottom side moved down to this thickness (0 = off)
    bool stair_ramps = true;              // runs of steps become ramps (needs remove_hidden; see above)
    int32_t stair_min_steps = 3;          // risers in a run
    float stair_max_rise = 20.0f;         // Hammer units: the highest riser of a step
    bool stair_flag = true;               // the ramps get SA1_SURFACE_STAIRS (the game's stair mode)
    float tess_max = 0.0f;                // Hammer units; > 0: faces longer than this are cut into well-shaped cells
    // 0.9.2 (sadc docs/research/gsa1_090_collision.md F3, F6 and gsa1_090_water.md GRID-GUARD, WTR-DISP, with their
    // reviews; see the comment at the top of this file)
    bool thin_stacks = true;              // steep faces (|n.z| < 0.5) of any source and sidedness with a parallel steep
                                          // face (|dot| >= 0.9, either facing) within thin_wall_max at every sample point
                                          // become ONE double-sided face (needs thin_wall_max > 0)
    bool guard = true;                    // triangles with a corner outside the model's bounds + 64 units (the kill plane
                                          // excepted) and pieces of a solid's face outside its box + 1 unit are left out
    bool disp_nohull = true;              // displacements without hull collision (SURF_NOHULL_COLL in their minTess
                                          // flags: the player's hull passes them in the engine) are left out
    bool coplanar_down = true;            // a down face exactly on a walkable face (0 units apart) loses the overlap
    // 0.9.3 (sadc docs/research/gsa1_091b_ceiling.md FIX-C3 and gsa1_091a_loop.md LOOP-G1, with their reviews; see the
    // comment at the top of this file)
    bool one_way_front_only = true;       // near-horizontal undersides (n.z <= -0.97) the one-way rules select stay as
                                          // SA1_SURFACE_FRONT_ONLY ceilings (false: left out, as until 0.9.2)
    bool curved = true;                   // the curved-surface detector (loops, pipes)
    float curved_max_angle = 30.0f;       // degrees: the largest bend between two faces of a curved surface
    float curved_min_radius = 64.0f;      // Hammer units: the smallest curve (centroid distance over the bend)
    float curved_ribbon_max = 16.0f;      // Hammer units: a curved ribbon this thin becomes one double-sided surface
                                          // (needs thin_wall_max > 0)
    // 0.9.3 tunnels and buried floors (the 0.9.2 owner note "I still fall through the ground with tunnels", "some
    // sinking into the ground"; sadc build/research/colltunnel; see the comment at the top of this file)
    bool disp_brush_exact = true;         // a brush is a displacement's own brush (dropped) only when one of its sides IS
                                          // the displacement's base face (false: 0.9.2's rule, a side on the face's
                                          // plane with the face's centre inside the brush, which dropped tunnel floors)
    float disp_cover_max = 128.0f;        // Hammer units: up faces under displacement ground at most this far below it,
                                          // with no down face between (a room), are left out (0 = off)
};

struct BspWorldStats {
    int32_t version = 0, revision = 0;
    uint32_t brushes = 0, world_brushes = 0, solid_brushes = 0, water_brushes = 0, other_brushes = 0;
    uint32_t displacement_brushes = 0, sides_with_dispinfo = 0, bevel_sides = 0;
    uint32_t brush_faces = 0, degenerate_faces = 0;
    uint32_t hidden_faces = 0;            // faces removed entirely (inside or between solids)
    uint32_t clipped_faces = 0;           // faces partly removed
    uint32_t face_fragments = 0;          // convex pieces emitted for the visible parts of the faces
    uint32_t thickened_floors = 0;        // thin floors whose bottom side was moved down (thin_floor_min)
    uint32_t one_way_solids = 0;          // solids whose underside was left out (one_way_max)
    uint32_t one_way_faces = 0;           // down faces left out by the solid's own top
    uint32_t one_way_cross = 0;           // down face pieces left out by another solid's walkable face above
    uint32_t one_way_disp_tris = 0;       // down-facing displacement triangles left out the same way
    uint32_t low_ceilings = 0;            // down face pieces / displacement triangles left out as low ceilings
    uint32_t thin_walls = 0;              // solids with a pair of faces made one double-sided face (thin_wall_max)
    uint32_t thin_wall_faces = 0;         // ... the faces replaced (2 per pair)
    uint32_t stairs = 0, stair_steps = 0; // runs of steps made ramps, their risers
    uint32_t tris_stairs = 0;             // ramp triangles (SA1_SURFACE_STAIRS)
    uint32_t displacements = 0, displacements_skipped = 0, displacement_tris = 0;
    uint32_t disp_buried = 0;             // displacement triangles inside a solid brush, left out (remove_hidden)
    uint32_t disp_back_faces = 0;         // displacements on a face whose side flag is set (0.4 wound them reversed)
    uint32_t disp_tag_checked = 0;        // displacements whose walkable tags decided the winding
    uint32_t disp_tag_reversed = 0;       // ... and reversed it against the plane normal
    uint32_t extra_solids = 0, extra_faces = 0, extra_bad = 0;   // ConvexSolids (static props' hulls); not closed
    uint32_t tris_extra = 0;              // their triangles
    uint32_t tessellated = 0;             // faces cut into cells (tess_max)
    uint32_t tris = 0, tris_solid = 0, tris_water = 0, tris_noclimb = 0, tris_sky = 0, tris_nodraw = 0;
    uint32_t tris_clip = 0, tris_kill = 0;
    uint32_t tris_out_of_range = 0;       // non-finite or beyond +-65536 units (damaged files): left out
    // surface types (with BspSurfaceSlots)
    uint32_t tris_tagged = 0;             // triangles with a surface-type slot
    uint32_t disp_tris_blend = 0;         // displacement triangles of the blend's second material ($surfaceprop2)
    uint32_t thin_walls_mixed = 0;        // thin walls whose two sides have different surface types (G7)
    uint32_t coplanar_mixed = 0;          // faces whose coplanar overlap went to a lower solid of another type (G6)
    uint32_t stairs_tagged = 0;           // stair ramps that took their treads' surface type
    float mins[3] = {0, 0, 0}, maxs[3] = {0, 0, 0};   // the model's bounds (Hammer units)
    double ms = 0.0;
    // 0.9.2
    uint32_t thin_wall_kept = 0;          // thin-wall pairs left as two faces: the middle face would be larger than both
    uint32_t thin_stacks = 0;             // faces made one double-sided face for a stack (thin_stacks)
    uint32_t thin_stack_faces = 0;        // ... the faces and displacement triangles of the stacks left out
    uint32_t tris_outside = 0;            // triangles with a corner outside the model's bounds + 64 units (guard)
    uint32_t frags_outside = 0;           // pieces of a solid's face outside the solid's box + 1 unit (guard)
    uint32_t displacements_nohull = 0;    // displacements without hull collision, left out (disp_nohull)
    uint32_t coplanar_cut = 0;            // down face pieces cut by a walkable face on their plane (coplanar_down)
    // 0.9.3
    uint32_t one_way_front_only = 0;      // down pieces and displacement triangles kept as front-only ceilings
    uint32_t front_only_no_room = 0;      // ... left out instead: nothing walkable under them within 1024 units
    uint32_t curved_surfaces = 0;         // curved surfaces found (loops, pipes)
    uint32_t curved_faces = 0;            // ... their faces (SA1_SURFACE_CURVED)
    uint32_t curved_undersides = 0;       // ... of them turned down (n.z < -0.1)
    uint32_t curved_solids = 0;           // solids that own a curved face (never thickened)
    uint32_t curved_one_way = 0;          // curved down faces the one-way / low-ceiling rules left alone
    uint32_t curved_thin_walls = 0;       // thin-wall pairs left as two faces because a face is curved
    uint32_t curved_ribbons = 0;          // curved pairs at most curved_ribbon_max apart made one double-sided face
    uint32_t curved_thin_stacks = 0;      // curved pieces the thin-stack rule left alone
    uint32_t disp_brushes_kept = 0;       // brushes on a displacement's plane kept: not its own (disp_brush_exact)
    uint32_t disp_cover_faces = 0;        // up faces that lost a part buried under displacement ground (disp_cover_max)
    uint32_t disp_cover_pieces = 0;       // ... the pieces left out
    double disp_cover_area = 0.0;         // ... their area (square Hammer units)
};

// One displacement's vertex grid (diagnostics / tests): n x n points, row r along corner 0 -> 1.
struct BspDispGrid {
    uint32_t n = 0;
    float corners[4][3];
    std::vector<float> pos;               // 3 per point, index r * n + c
};

struct BspEntity {
    std::vector<std::pair<std::string, std::string>> kv;
    const std::string *get(const char *key) const;
    bool get_vec3(const char *key, float out[3]) const;
};

// A static prop of the sprp game lump.
struct BspStaticProp {
    std::string model;                    // "models/....mdl", lower case, '/' separators
    float origin[3] = {0, 0, 0};          // Hammer units
    float angles[3] = {0, 0, 0};          // degrees: pitch, yaw, roll (Source's QAngle)
    uint8_t solid = 0;                    // 0 none, 2 bounding box, 6 physics model (.phy)
    uint8_t flags = 0;
    float scale = 1.0f;                   // lump version 11 (uniform scale)
};

struct BspPropInfo {
    int32_t version = 0;                  // sprp lump version
    uint32_t names = 0, props = 0, stride = 0;
    bool present = false, compressed = false;
};

// Surface-type tags: a triangle's slot (surfaces.hpp: an index into the map's surface types) in the low 16 bits, a
// second slot whose hurts / no-climbing kinds also apply (a thin wall's other side) in the high 16 bits - or
// kHiddenSurface there: a face the engine never draws (nodraw, sky, player clip), classed like the others but left out
// of the walkable-area statistics (the sky box's top is no ground).
const uint16_t kNoSurface = 0xFFFFu;
const uint16_t kHiddenSurface = 0xFFFEu;
const uint32_t kNoSurfaceTag = 0xFFFFFFFFu;
inline uint32_t surface_tag(uint16_t primary, uint16_t also = kNoSurface)
{
    return (uint32_t)primary | ((uint32_t)also << 16);
}

// The material names of the TEXDATA lumps (2, 43, 44).
struct BspMaterials {
    std::vector<std::string> names;       // unique, lower case, '/' separators (no "materials/", no ".vmt")
    std::vector<int32_t> texdata_name;    // per TEXDATA entry: its index in names (-1: a damaged or unusable name)
    std::vector<uint8_t> used;            // per name: a collision face uses it (a side of a solid or water brush, a
                                          // displacement); only these materials' .vmt are read
    uint32_t texdata = 0, bad = 0;        // TEXDATA entries, unusable names
};

// per TEXDATA entry: the slot of its material's $surfaceprop and $surfaceprop2 (kNoSurface: none / no blend)
struct BspSurfaceSlots {
    std::vector<uint16_t> sp, sp2;
};

// A closed convex solid given by its hull triangles (any winding), Hammer units: a static prop's physics hull placed
// in the map, or a moving object's hull. Cleaned like a brush (faces, one-way, hidden faces).
struct ConvexSolid {
    std::vector<float> tris;              // 9 floats per triangle
    uint32_t surface = SA1_SURFACE_SOLID;
    uint16_t sp = kNoSurface;             // surface-type slot (static props: the .phy solid's surfaceprop)
};

struct BspData;

class Bsp {
public:
    bool open(ByteSource &src, std::string &err);
    int32_t version() const { return version_; }
    int32_t revision() const { return revision_; }
    // the header's range of lump i (bytes)
    bool lump_range(int index, uint64_t &ofs, uint64_t &len) const;
    // Every byte range build_world / build_model / static_props / entities read: the lumps (the header's ranges),
    // and once the game lump directory (lump 35) is readable, the static prop lump's range too. For readers that
    // hand over only what is needed (RangeByteSource). Ranges of length 0 are left out.
    void needed_ranges(std::vector<std::pair<uint64_t, uint64_t>> &out);
    // reads the lumps once (build_* and static_props call it themselves)
    bool load(std::string &err);
    // model 0 (the world): brushes + displacements + kill plane, with the extra convex solids (static props) cleaned
    // together with the brushes. slots / tags (optional): the surface-type slots of the materials, and the tag of every
    // output triangle (parallel to out; kNoSurfaceTag: none, e.g. the kill plane)
    bool build_world(const BspWorldOptions &opt, const std::vector<ConvexSolid> *extra, std::vector<sa1_collision_tri> &out,
                     BspWorldStats &st, std::string &err, const BspSurfaceSlots *slots = nullptr,
                     std::vector<uint32_t> *tags = nullptr);
    bool build_world(const BspWorldOptions &opt, std::vector<sa1_collision_tri> &out, BspWorldStats &st, std::string &err)
    {
        return build_world(opt, nullptr, out, st, err);
    }
    // a brush model (*1, *2, ...: brush entities) in its own space: its brushes cleaned (no displacements, no kill
    // plane, no stair ramps). An empty output with true: the model has no solid brush.
    bool build_model(int32_t model, const BspWorldOptions &opt, std::vector<sa1_collision_tri> &out, BspWorldStats &st,
                     std::string &err);
    int32_t model_count();
    // a model's bounds (Hammer units; model 0: the world); false: no such model or invalid bounds
    bool model_bounds(int32_t model, float mins[3], float maxs[3]);
    // the TEXDATA lumps' material names (a map without them: an empty list, true)
    bool materials(BspMaterials &out, std::string &err);
    bool displacement_grids(const BspWorldOptions &opt, std::vector<BspDispGrid> &out, std::string &err);
    bool entities(std::vector<BspEntity> &out, std::string &err);
    bool static_props(std::vector<BspStaticProp> &out, BspPropInfo &info, std::string &err);

private:
    struct Lump {
        int32_t ofs, len, version;
        uint32_t fourcc;
    };
    bool lump_raw(int index, size_t elem, size_t max_count, std::vector<uint8_t> &out, size_t &count,
                  std::string &err);
    bool sprp_range(uint64_t &ofs, uint64_t &len, uint16_t &version, bool &compressed, std::string &err);
    friend bool load_bsp_data(Bsp &bsp, BspData &w, std::string &err);
    ByteSource *src_ = nullptr;
    int32_t version_ = 0, revision_ = 0;
    Lump lumps_[64] = {};
    std::shared_ptr<BspData> data_;
};

// The faces of convex solids alone (no map): a moving object's physics hulls cleaned like brushes (curved surfaces,
// one-way, hidden faces between touching hulls, tess_max). Triangles in the solids' space; tags (optional): each one's
// ConvexSolid::sp.
bool clean_solids(const std::vector<ConvexSolid> &solids, const BspWorldOptions &opt, std::vector<sa1_collision_tri> &out,
                  BspWorldStats &st, std::string &err, std::vector<uint32_t> *tags = nullptr);

// Source's AngleMatrix (degrees: pitch, yaw, roll): world = m * local, m row-major 3x3 (the columns are forward,
// left, up).
void angle_matrix(const float angles[3], float m[9]);

}  // namespace gsa1
