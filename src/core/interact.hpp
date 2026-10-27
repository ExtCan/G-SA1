// G-SA1 core: the interaction feature (round 5; sadc docs/libsa1_interaction.md section 3 and its addendum, section 6;
// plan docs/research/gsa1_rounds_plan.md 9.3 with the owner's additions: pushing props, the interact button, the HUD).
// No GMod dependency: the module's bind_interact.cpp and the offline tests drive exactly this code.
//
// * Registry: GMod entities as libsa1 host objects (sa1_hostobj_*), keyed by the entity's index (the object's `user`
//   tag, so every event names the entity). A description that did not change is not sent again; a move that did not
//   change is not sent again; a new libsa1 context (the disc loaded again) forgets every id, the host registers again.
// * make_desc: the flat arguments of gsa1.ObjAdd (host units, degrees) -> sa1_hostobj_desc (host units, radians),
//   validated (finite, kinds and flags known) and clamped (sizes 16..4000 HU = 4..1000 SA1 units, sadc 3.1;
//   a HOLDABLE's body at most 128 HU across its radius, addendum 6.1.2).
// * summarize: libsa1's per-step contacts with moving collision objects (sa1_character_contacts) folded into one entry
//   per entity for the frame - how many steps it touched the character from the side, from above (the character
//   stands on it) or from below, the strongest side contact's normal, point and approach speed - which the addon turns
//   into a push of the GMod physics prop on the server (owner addition A; the push itself is sh_interact.lua's, the
//   server has no module).
//
// Units: host space = Source / Hammer units (libsa1's SOURCE preset, 4 HU per SA1 unit); yaws: degrees in the
// arguments, radians towards libsa1 (the sa1_pose.yaw convention).
#pragma once

#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "libsa1_internal_api.hpp"

namespace gsa1 {
namespace interact {

const uint32_t kMaxShapes = SA1_HOSTOBJ_MAX_SHAPES;
const int32_t kMaxEnt = 1 << 20;            // entity indices taken (GMod's networked ones are 1..8191)
const float kMinSize = 16.0f;               // HU: 4 SA1 units (sadc libsa1_interaction.md 3.1)
const float kMaxSize = 4000.0f;             // HU: libsa1's 1000 SA1 units
const float kMaxHoldSize = 128.0f;          // HU: a HOLDABLE body's radius / half extent (addendum 6.1.2: 32 SA1 units)
const float kMaxCoord = 65536.0f;           // HU: positions and offsets

struct ShapeArgs {
    uint32_t form = SA1_SHAPE_SPHERE;       // SA1_SHAPE_SPHERE / CYLINDER / BOX
    float center[3] = {0.0f, 0.0f, 0.0f};   // HU, offset from the object's position (not turned by its yaw)
    float size[3] = {0.0f, 0.0f, 0.0f};     // HU: sphere radius; cylinder radius, half height; box half extents
    float yaw_deg = 0.0f;                   // BOX: degrees about the vertical
    uint32_t flags = 0;                     // SA1_HSHAPE_*
};

struct ObjArgs {
    int32_t ent = 0;                        // the GMod entity index (1 .. kMaxEnt): the object's user tag
    uint32_t kind = 0;                      // SA1_HOSTOBJ_ENEMY .. SA1_HOSTOBJ_BALLOON
    uint32_t flags = 0;                     // SA1_HOSTOBJ_* flags
    float pos[3] = {0.0f, 0.0f, 0.0f};      // HU
    float yaw_deg = 0.0f;
    int32_t armor = -1, touch = -1;         // 0..3, -1 = the kind's default
    uint32_t cooldown = 0;                  // steps (0 = libsa1's 20)
    uint32_t nshapes = 0;                   // 1..4
    ShapeArgs shapes[kMaxShapes];
    float launch_speed = 0.0f;              // BALLOON: HU/s upward (0 = the game's spring)
    float grab_reach = 0.0f;                // HOLDABLE: HU added to the body radius for the grab cylinder (0 = 8 SA1 units)
};

// every SA1_HOSTOBJ_* flag bit libsa1 knows (sa1_hostobj_desc.flags)
uint32_t known_flags();
// the description of a, validated and clamped; false with err when an argument is not usable
bool make_desc(const ObjArgs &a, sa1_hostobj_desc &d, std::string &err);

struct RegistryStats {
    uint64_t adds = 0, updates = 0, unchanged = 0, moves = 0, moves_skipped = 0, removes = 0, failures = 0, forgets = 0;
    std::string last_error;
};

class Registry {
public:
    // the context the ids belong to: another context (or none) forgets every id - they went with the old context
    void bind(sa1_context *ctx);
    // forgets every id without calling libsa1 (the context is gone or going)
    void forget();
    // adds the object of entity a.ent, or replaces its description when it changed; id: its libsa1 id
    sa1_status set(sa1_context *ctx, const ObjArgs &a, uint32_t &id, bool *added, std::string &err);
    // moves it (HU, degrees); SA1_ERR_NOT_FOUND when the entity has no object
    sa1_status move(sa1_context *ctx, int32_t ent, const float pos[3], float yaw_deg);
    // removes it (killed: SA1_HOSTOBJ_REMOVE_KILLED, else SILENT); false when the entity had none
    bool remove(sa1_context *ctx, int32_t ent, bool killed);
    // removes every object; returns how many
    size_t clear(sa1_context *ctx);
    bool id_of(int32_t ent, uint32_t &id) const;
    bool ent_of(uint32_t id, int32_t &ent) const;
    size_t size() const { return by_ent_.size(); }
    uint32_t generation() const { return gen_; }    // raised whenever the ids were forgotten
    const RegistryStats &stats() const { return st_; }

private:
    struct Obj {
        uint32_t id = 0;
        sa1_hostobj_desc desc{};
        float pos[3] = {0.0f, 0.0f, 0.0f};          // the last position / yaw libsa1 has
        float yaw = 0.0f;
    };
    sa1_context *ctx_ = nullptr;
    std::map<int32_t, Obj> by_ent_;
    std::map<uint32_t, int32_t> by_id_;
    uint32_t gen_ = 1;
    RegistryStats st_;
};

// ---- contacts with moving collision objects, per entity --------------------------------------------------------------
struct ContactSum {
    int32_t ent = 0;
    uint32_t object = 0, chunk = 0;
    uint32_t steps = 0;                     // contact steps (one per object and step)
    uint32_t side = 0, landing = 0, head = 0;   // ... of each type
    uint32_t riding = 0, wall = 0, first = 0;   // ... with SA1_CONTACTF_RIDING / WALL / FIRST
    // the strongest side or head contact (largest approach speed, then depth); only landings: the last one
    uint32_t type = 0;                      // its SA1_CONTACT_*
    float normal[3] = {0.0f, 0.0f, 0.0f};   // unit, from the object towards the character
    float point[3] = {0.0f, 0.0f, 0.0f};    // HU: the object's point nearest to the character
    float velocity[3] = {0.0f, 0.0f, 0.0f}; // HU/s: the character's velocity entering that step
    float vin = 0.0f;                       // HU/s, >= 0: that velocity's speed into the object (velocity . -normal)
    float vout = 0.0f;                      // HU/s, >= 0: the same after the step (the game's push-back applied)
    float depth = 0.0f;                     // HU: the deepest of all its contacts
    uint32_t last_step = 0;
};

// maps a moving collision object to its entity (false: not one of the host's entities: dropped)
using EntityLookup = std::function<bool(uint32_t object, int32_t &ent, uint32_t &chunk)>;
// one entry per entity, in the order the entities first appear in c
std::vector<ContactSum> summarize(const sa1_contact *c, size_t n, const EntityLookup &lookup);

}  // namespace interact
}  // namespace gsa1
