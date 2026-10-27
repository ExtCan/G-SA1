// G-SA1 core: collision shapes of moving objects (brush entities, physics props, vehicles), in the object's own
// space (Hammer units). libsa1 takes moving objects as they are (sa1_collision_object_add: no splitting, at most
// SA1_MAX_OBJECT_TRIS triangles within SA1_MAX_OBJECT_RADIUS of the object's origin), so a shape is cleaned and cut
// into well-shaped pieces here (bsp.hpp: clean_solids / build_model with tess_max) and split into CHUNKS of at most
// max_tris triangles within max_radius of the chunk's centre; each chunk becomes one libsa1 object placed by the
// entity's transform times the chunk's centre (movers.hpp).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "bsp.hpp"
#include "phy.hpp"

namespace gsa1 {

struct ShapeChunk {
    float center[3] = {0, 0, 0};             // in the shape's space
    float radius = 0.0f;                     // of the triangles around the centre
    std::vector<sa1_collision_tri> tris;     // relative to `center`
};

struct Shape {
    std::vector<ShapeChunk> chunks;
    float mins[3] = {0, 0, 0}, maxs[3] = {0, 0, 0};
    uint32_t tris = 0;
};

const uint32_t kChunkTris = 1024;            // triangles per chunk (libsa1 allows 4096 per object)
const float kChunkRadius = 1500.0f;          // Hammer units (libsa1 allows 4000: SA1_MAX_OBJECT_RADIUS 1000 SA1 units)
const float kMoverTess = 512.0f;             // Hammer units: the longest piece of a moving object (128 SA1 units, the
                                             // static world's GRID max_edge)

// the cleaning options of moving objects: one-way thin platforms (0.9.3: front-only ceilings - libsa1 honours
// SA1_SURFACE_FRONT_ONLY on moving objects too, SA1_API_CEILING), curved surfaces, hidden faces, thin walls
// (thin_wall_max: the map's setting, BspWorldOptions::thin_wall_max), cut into kMoverTess pieces; no water, no stair
// ramps, no kill plane
BspWorldOptions mover_options(float thin_wall_max = 16.0f);

// triangles (shape space) -> chunks
void make_shape(const std::vector<sa1_collision_tri> &tris, Shape &out, uint32_t max_tris = kChunkTris,
                float max_radius = kChunkRadius);
// a physics model's convex pieces, cleaned like brushes (mover_options(thin_wall_max))
bool shape_from_phy(const PhyModel &m, Shape &out, std::string &err, float thin_wall_max = 16.0f);
// a box (an entity's collision bounds: SOLID_BBOX)
bool shape_box(const float mins[3], const float maxs[3], Shape &out, std::string &err, float thin_wall_max = 16.0f);
// the 12 triangles of a box as a convex solid (static props with SOLID_BBOX), transformed by m (row-major 3x3) and t
void box_solid(const float mins[3], const float maxs[3], const float m[9], const float t[3], ConvexSolid &out);

}  // namespace gsa1
