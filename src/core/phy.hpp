// G-SA1 core: Source physics models (.phy: the VPHYSICS collision of a model, IVP compact surfaces) -> convex hulls,
// and the hull box of a studio model header (.mdl), for static props with SOLID_BBOX.
//
// A .phy holds one or more solids (a prop: usually one, made of several convex pieces; a ragdoll: one per bone).
// Each solid is an IVP compact surface: convex "ledges" (triangle lists over a shared point array) under a ledge
// tree whose terminal nodes are the convex pieces (inner nodes may carry the hull of their subtree, which is NOT a
// piece). Points are IVP units: metres, x = Source x, y = -Source z, z = Source y. Every offset, count and index of
// the file is checked (models come from any server). The text section after the solids (key values: solid blocks with
// their "surfaceprop", ragdoll constraints, edit parameters) gives each solid's surface type.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace gsa1 {

struct PhyModel {
    std::vector<std::vector<float>> hulls;   // per convex piece: 9 floats per triangle, model space, Hammer units,
                                             // counter-clockwise seen from outside
    uint32_t solids = 0, solids_used = 0, ledges = 0, triangles = 0, skipped_solids = 0;
    bool ragdoll = false;                    // ragdoll constraints in the text section: only solid 0 is used
    float mins[3] = {0, 0, 0}, maxs[3] = {0, 0, 0};
    // surface types (sadc docs/research/gsa1_060_dig.md F4): the text section's `solid { "index" N "surfaceprop" "x" }`
    // per solid (lower case; "" when the file names none - Source then takes the model's own $surfaceprop, which is
    // not read here), and the solid each convex piece belongs to (parallel to hulls)
    std::vector<std::string> solid_surfaceprop;
    std::vector<uint16_t> hull_solid;
};

bool parse_phy(const void *data, size_t n, PhyModel &out, std::string &err);

// studiohdr_t's hull_min / hull_max (the collision box of SOLID_BBOX props); `n` may be just the first 136 bytes
bool parse_mdl_hull(const void *data, size_t n, float mins[3], float maxs[3], std::string &err);

}  // namespace gsa1
