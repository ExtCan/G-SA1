// G-SA1 core: the feature "preview" (round 0.9.4b; sadc docs/research/objects2_plan.md 6.3 task 2 with its Review R.5 /
// R.8, objects2_view.md 5; libsa1's "object previews", SA1_API_PREVIEW). No GMod dependency: the module's
// bind_preview.cpp and the offline tests drive exactly this code.
//
// libsa1 runs the game's own rings, ring groups and item boxes in a private "showcase" world per character kind with no
// player in it (sa1_preview_add / tick / render): each COPY is the type's own task with the game's exec and display, and
// sa1_preview_render returns that copy's draws in OBJECT SPACE (host units and axes, origin = where the host puts the
// object). G-SA1 draws them for a player without a character, for the records a character's world is not running (far
// away) and as the spawn-menu pictures (feat/cl_objview.lua, feat/cl_objicons.lua).
//
// Here: the session context's copies - id -> {libsa1's id (the Lua id too), the description, a gsa1::Character used only as
// a render-state holder (no world: Session::rebatch / Session::prepare_view and the module's EmitBatch loop work on it as
// on a character's last render)} - and the ring places of an entity's ring group: the entity's description split into the
// game's records by objects.cpp make_records (0.9.4.1's lines of 8 and circles of n turned by k x 360 / N: the records
// gsa1.SetAdd gives libsa1, review R.5), each record's rings placed by the game's own layout (sa1_preview_ring_places:
// 8C087EEE / 8C088000 run in the kind's showcase), relative to the entity.
#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "libsa1_internal_api.hpp"
#include "objects.hpp"
#include "session.hpp"

#if defined(SA1_API_PREVIEW)
#define GSA1_HAS_PREVIEW 1
#endif

namespace gsa1 {
namespace preview {

#if defined(GSA1_HAS_PREVIEW)
const bool kAvailable = true;
#else
const bool kAvailable = false;
#endif

// G-SA1's host scale (libsa1's SOURCE preset: 4 Hammer units per SA1 unit), as objects::Registry::hu_per_unit
const float kHuPerUnit = 4.0f;
// rings of one game record at most (a line of n + 1 <= 8, a circle of n <= 7; libsa1 lays out up to 16)
const uint32_t kRingsPerRecord = 16;

// the kind whose showcase draws a picture for character kind `kind`: kinds without a showcase (Eggman 1, Tikal 4, Super
// Sonic 8 - the Vs. Perfect Chaos form; the General form is kind 0 already) and unknown kinds use Sonic's (0)
int32_t showcase_kind(int32_t kind);

// a preview's description (sa1_preview_desc): what makes two copies equal
struct Desc {
    int32_t kind = 0;                   // SA1_CHAR_*: libsa1 refuses a kind without a showcase (UNSUPPORTED)
    uint32_t type = 0;                  // SA1_OBJTYPE_*
    float rotation[9] = {0, 0, 0, 0, 0, 0, 0, 0, 0};   // SA1_PREVIEW_ROT_INNER types only (O_GRING); all zero: none
    float params[3] = {0, 0, 0};        // as sa1_set_record.params (SA1 units)
    uint32_t state = 1;                 // SA1_SET_STATE_PRESENT [| SA1_SET_STATE_BROKEN]
    uint32_t user_bits = 0;             // O_GRING: its taken rings
};

struct Copy {
    uint32_t id = 0;                    // libsa1's copy id (never 0); the Lua id
    Desc desc;
    Character holder;                   // the copy's last render, batches and prepared view (holder.kind = desc.kind)
    bool rendered_last = false;         // the holder holds the last pair as it is (alpha >= 1)
    uint32_t steps_rendered = 0;        // the copy's steps at that render
};

struct Stats {
    uint64_t adds = 0, removes = 0, clears = 0, renders = 0, skipped = 0, ticks = 0, faults = 0, forgets = 0;
    double tick_ms_last = 0.0, tick_ms_max = 0.0;
    std::string last_error;
};

// the copies of one libsa1 context
class Previews {
public:
    // the context the copies belong to: another context (or none) forgets every copy (libsa1 freed them with it)
    void bind(const void *ctx);
    // forgets every copy without calling libsa1 (the context is gone or its disc was reloaded)
    void forget();
    sa1_status add(sa1_context *ctx, const Desc &d, uint32_t &id, std::string &err);
    sa1_status remove(sa1_context *ctx, uint32_t id);
    // every copy; libsa1 frees every showcase now (also the way out of a fault). Returns the copies removed in count
    sa1_status clear(sa1_context *ctx, size_t &count);
    // the showcases' whole pairs for dt seconds (libsa1's accumulator); err: the first showcase's fault
    sa1_status tick(sa1_context *ctx, float dt, std::string &err);
    // the copy's draws into its holder and batches (Session::rebatch). alpha >= 1: the last pair as it is - skipped
    // (changed false) when the copy ran no new pair since the last such render; alpha < 0: libsa1's accumulator; else a
    // vertex lerp between the copy's last two pairs. changed: the holder was rebuilt (its view must be prepared again)
    sa1_status render(Session &se, uint32_t id, float alpha, bool &changed, std::string &err);
    Copy *find(uint32_t id);
    size_t size() const { return copies_.size(); }
    const Stats &stats() const { return st_; }

private:
    const void *ctx_ = nullptr;
    std::map<uint32_t, std::unique_ptr<Copy>> copies_;
    Stats st_;
};

// a libsa1 render into a Character's render fields (as Session::render copies sa1_character_render's): the holder's
// draws, triangles, sprites and lines; rendered, generation, alpha, position (0 for a preview), flags
void copy_render(Character &c, const sa1_render &r);

// the error code of a libsa1 status for Lua ("not_found", "fault", "unsupported", "limit", "not_ready", "bad_argument")
const char *code_of(sa1_status st);

// one ring of an entity's ring group (or of a RING: its own place)
struct Place {
    float pos[3] = {0, 0, 0};           // host units, relative to the entity's position, host axes
    uint32_t record = 0;                // the record (0 .. records - 1) whose user bits hold the ring
    uint32_t bit = 0;                   // its bit in the record's user flag (1 << i; a RING: 0)
};
// the places of the rings of entity description d (objects::Desc: type RING or O_GRING, the entity's angles and p1..p3
// as gsa1.SetAdd takes them; d.pos is ignored: the places are relative to the entity), by the game's layout in kind's
// showcase (showcase_kind is the caller's). SA1_ERR_INVALID_ARGUMENT for a description that is not a ring object
sa1_status ring_places(sa1_context *ctx, int32_t kind, const objects::Desc &d, std::vector<Place> &out,
                       std::string &err);

}  // namespace preview
}  // namespace gsa1
