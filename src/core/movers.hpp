// G-SA1 core: moving collision - brush entities (doors, trains, lifts, func_brush, breakables), physics props and
// vehicles - as libsa1 moving objects (sa1_collision_object_*), placed every frame by the entity's transform as a
// MATRIX (G64 passed Euler angles, which libsm64 rebuilt in another order: wrong past 90 degrees of pitch).
//
// libsa1 gives each world at most 64 moving objects, in the order they were added, and counts the polygons of the
// ones near the character against the land collision's polygon pool (8192; the static window gets the rest). So
// only what is near the character is in libsa1: the chunks (shape.hpp) whose sphere comes within `range` of the
// character, nearest first, at most `max_active` objects and `max_tris` triangles. A chunk that drops out of that
// set, or whose entity is not solid any more (a func_brush switched off, a broken window, a door set non-solid), is
// PARKED: moved far below the map with its libsa1 object kept (no reallocation, a re-enable is one move), and
// removed only when more than `max_parked` are parked (least recently used first).
#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "libsa1_internal_api.hpp"
#include "shape.hpp"

namespace gsa1 {

struct MoverOptions {
    float range = 2400.0f;        // Hammer units from the character to a chunk's sphere (the game gathers within 400
                                  // SA1 units = 1600 HU of the character)
    uint32_t max_active = 40;     // libsa1 objects in use
    uint32_t max_tris = 2048;     // their triangles (the static window keeps the rest of the game's 8192 pool)
    uint32_t max_parked = 16;     // parked objects kept (active + parked < 64, libsa1's objects per world)
    double stale = 1.0;           // seconds: an entity not updated for this long is forgotten
};

struct MoverStats {
    uint32_t entities = 0, solid = 0, unknown_shape = 0;
    uint32_t active = 0, active_tris = 0, parked = 0;
    uint32_t candidates = 0, over_budget = 0;
    uint64_t adds = 0, removes = 0, moves = 0, parks = 0, unparks = 0, failures = 0;
    std::string last_error;
};

class Movers {
public:
    // shapes by key ("b<N>" brush model N of the current map, "m:<model path>" a physics model, "x:..." a box)
    void set_shape(const std::string &key, Shape s);
    bool has_shape(const std::string &key) const { return shapes_.count(key) != 0; }
    const Shape *shape(const std::string &key) const;
    size_t shape_count() const { return shapes_.size(); }
    // drops the shapes whose key starts with prefix (the brush models of the previous map: "b")
    void drop_shapes(const std::string &prefix);
    // an entity this frame: its shape, position (Hammer units), angles (pitch yaw roll, degrees), solid or not
    void update(int32_t ent, const std::string &key, const float pos[3], const float ang[3], bool solid, double now);
    void forget(int32_t ent);
    // applies the selection around `focus` (the character; nullptr: everything parked) to libsa1
    void commit(sa1_context *ctx, const float *focus, double now);
    // every libsa1 object removed, the entities forgotten (ctx may be null: the context is gone)
    void clear(sa1_context *ctx);
    MoverOptions opt;
    const MoverStats &stats() const { return st_; }
    // the libsa1 object ids in use (tests)
    std::vector<uint32_t> object_ids() const;
    // the entity (and its chunk) a libsa1 object belongs to: false when no entity has it (round 5, the interaction
    // feature: libsa1's contact reports name the collision object, the push goes to the entity)
    bool entity_of(uint32_t object_id, int32_t &ent, uint32_t *chunk = nullptr) const;

private:
    struct Chunk {
        uint32_t id = 0;          // libsa1 object (0: none)
        bool parked = false;
        double used = 0.0;        // last time it was active
        float pos[3] = {0, 0, 0}, rot[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};   // the transform libsa1 has
    };
    struct Ent {
        std::string key;
        std::shared_ptr<const Shape> shape;
        float pos[3] = {0, 0, 0}, rot[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};
        bool solid = false;
        double seen = 0.0;
        std::vector<Chunk> chunks;
    };
    void drop_ent(sa1_context *ctx, Ent &e);
    std::map<std::string, std::shared_ptr<const Shape>> shapes_;
    std::map<int32_t, Ent> ents_;
    MoverStats st_;
};

}  // namespace gsa1
