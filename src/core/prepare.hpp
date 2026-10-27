// G-SA1 core: the map's collision prepared for libsa1 off the game's thread (0.5.1; libsa1.h "Preparation on host
// threads", SA1_API_PREPARE, which answers G-SA1's request 11).
//
// libsa1 turns a triangle soup into the game's own land collision (the GRID synthesis: cells of land objects, a
// landtable, the triangles cut into well-shaped pieces; 0.1-0.4 s for a big map). Until 0.5.0 that ran in the first
// sa1_character_create after sa1_collision_set_static, on the game's thread (the first spawn after a map load was one
// long frame). Now the map job's worker calls sa1_collision_prepare_tris (prepare_world below) after building the
// cleaned triangles, and the game's thread only installs the result: sa1_collision_set_prepared, O(1). Every world
// created while it is the context's geometry (the first spawn, respawns, character switches, re-creations) maps the
// same immutable collision segment by reference.
//
// The preparation runs on a PRIVATE libsa1 context of its own (sa1_init with the default host: malloc / free, no log;
// the SOURCE coordinate preset every G-SA1 context uses), so it shares nothing with the context the game's thread
// ticks - it may run before the disc is loaded and survive a re-initialisation. A sa1_collision_prepared keeps a copy
// of the allocator it was made with and may be installed into any context of the process (libsa1.h).
#pragma once

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include "libsa1_internal_api.hpp"

namespace gsa1 {

// One reference to a sa1_collision_prepared (immutable, reference-counted by libsa1 on any thread). Copying retains,
// destruction releases; the geometry is freed with its last reference (the host's, the contexts', the worlds').
class PreparedRef {
public:
    PreparedRef() = default;
    explicit PreparedRef(sa1_collision_prepared *adopt) : p_(adopt) {}   // takes over one reference
    PreparedRef(const PreparedRef &o);
    PreparedRef(PreparedRef &&o) noexcept : p_(o.p_) { o.p_ = nullptr; }
    PreparedRef &operator=(PreparedRef o) noexcept
    {
        std::swap(p_, o.p_);
        return *this;
    }
    ~PreparedRef() { reset(); }
    void reset();
    sa1_collision_prepared *get() const { return p_; }
    explicit operator bool() const { return p_ != nullptr; }
    bool info(sa1_collision_prepared_info &out) const;

private:
    sa1_collision_prepared *p_ = nullptr;
};

// GRID parameters of the preparation (not part of the map cache's key: the cache holds the cleaned triangles)
struct PrepareOptions {
    float under_reach = 0.0f;        // SA1 units: downward triangles this close behind an upward one are left out
                                     // (libsa1 GRID c2, mechanism B of sadc docs/research/gsa1_ramp_freeze.md 8);
                                     // 0 = libsa1's default, 12 SA1 units = 48 Hammer units
    bool keep_undersides = false;    // SA1_GRID_KEEP_UNDERSIDES (every underside stays land)
    bool undersides_drop = false;    // 0.9.3: SA1_GRID_UNDERSIDES_DROP - the one-way behaviour until 0.9.2: the undersides
                                     // within reach and every SA1_SURFACE_FRONT_ONLY triangle (bsp.hpp one_way_front_only)
                                     // are left out, so thin roofs and ceilings can be jumped through again (the Q menu's
                                     // "Solid ceilings" switched off). By default near-horizontal ones are front-only
                                     // ceilings (sadc docs/research/gsa1_091b_ceiling.md FIX-C)
};

struct PrepareResult {
    PreparedRef prepared;            // the geometry (empty when the preparation failed)
    bool ok = false;
    std::string error;               // why it failed ("" = fine)
    double ms = 0.0;                 // on the worker
    uint32_t triangles = 0;          // given
    uint32_t grid_triangles = 0;     // after cutting (land + kill)
    uint32_t grid_objects = 0;       // land objects
    uint32_t grid_undersides = 0;    // left out by under_reach
    uint32_t grid_front_only = 0;    // 0.9.3: front-only GRID triangles (the input's and the near-horizontal undersides)
    uint32_t grid_curved = 0;        // 0.9.3: SA1_SURFACE_CURVED triangles kept that under_reach would have left out
    uint32_t bytes = 0;              // of the collision segment
    // 0.9.2 (GRID-FALLBACK, prepare_world_guarded)
    sa1_status status = SA1_OK;      // libsa1's status of the last preparation
    bool too_big = false;            // more than the game's collision memory holds, also after the retry: `error` says
                                     // so in plain words (MapApply's triangles would fail the same way in the first
                                     // character, on the game's thread)
    bool retried = false;            // a second preparation ran without the triangles outside the world
    uint32_t left_out = 0;           // ... the triangles it left out (ok: the prepared world lacks them)
};

// the coordinate system of every G-SA1 libsa1 context: libsa1's SOURCE preset (4 Hammer units per SA1 unit, Z up)
void source_coords(sa1_coords &out);

// The GRID synthesis of `tris` (host space) on the calling thread (any thread), through a private libsa1 context.
// Returns out.ok.
bool prepare_world(const std::vector<sa1_collision_tri> &tris, const PrepareOptions &o, PrepareResult &out);

// GRID-FALLBACK (0.9.2, sadc docs/research/gsa1_090_water.md 6.4 and G3): prepare_world, and when libsa1 refuses the
// world for a safety limit (SA1_ERR_LIMIT: more pieces than the game's 64 MB collision segment holds - about 2.6 to 3
// million after cutting - or a face cut into too many) once more without the triangles that have a corner outside the
// world's bounds + 64 units (the guard's filter: nobody reaches them; the kill plane stays). mins / maxs: the world
// model's bounds (nullptr, or empty bounds: no retry). When that fails too, or leaves nothing out, out.too_big and
// out.error says in plain words that the map is too big for the game's collision and how much it has (libsa1's own
// message, with its estimate, follows) - instead of "cannot create Sonic: safety limit exceeded" later.
bool prepare_world_guarded(const std::vector<sa1_collision_tri> &tris, const float *mins, const float *maxs,
                           const PrepareOptions &o, PrepareResult &out);

}  // namespace gsa1
