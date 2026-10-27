// G-SA1 core: the interaction feature (see interact.hpp).
#include "interact.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace gsa1 {
namespace interact {

namespace {

const double kPi = 3.14159265358979323846;

bool fin3(const float v[3])
{
    return std::isfinite(v[0]) && std::isfinite(v[1]) && std::isfinite(v[2]);
}

bool within(const float v[3], float lim)
{
    return std::fabs(v[0]) <= lim && std::fabs(v[1]) <= lim && std::fabs(v[2]) <= lim;
}

float clampf(float v, float lo, float hi)
{
    return v < lo ? lo : (v > hi ? hi : v);
}

// degrees -> radians, reduced to (-pi, pi] first (libsa1 takes |yaw| <= 10000)
float yaw_rad(float deg)
{
    double d = std::fmod((double)deg, 360.0);
    if (d > 180.0) {
        d -= 360.0;
    } else if (d <= -180.0) {
        d += 360.0;
    }
    return (float)(d * kPi / 180.0);
}

float dot3(const float a[3], const float b[3])
{
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

}  // namespace

uint32_t known_flags()
{
    return SA1_HOSTOBJ_SOLID | SA1_HOSTOBJ_NOT_SOLID | SA1_HOSTOBJ_NO_HOMING | SA1_HOSTOBJ_NO_LOCKON |
           SA1_HOSTOBJ_NO_BONUS | SA1_HOSTOBJ_DISABLED | SA1_HOSTOBJ_REPORT_TOUCH | SA1_HOSTOBJ_HOLD_HITS |
           SA1_HOSTOBJ_HOLD_LOCKED | SA1_HOSTOBJ_HEAVY | SA1_HOSTOBJ_POP_ON_TOUCH | SA1_HOSTOBJ_LAUNCH_BOUNCE |
           SA1_HOSTOBJ_KEEP_HSPEED;
}

bool make_desc(const ObjArgs &a, sa1_hostobj_desc &d, std::string &err)
{
    std::memset(&d, 0, sizeof d);
    d.struct_size = sizeof d;
    if (a.ent < 1 || a.ent > kMaxEnt) {
        err = "an entity index 1..1048576";
        return false;
    }
    if (a.kind < SA1_HOSTOBJ_ENEMY || a.kind > SA1_HOSTOBJ_BALLOON) {
        err = "kind: 1 enemy, 2 target, 3 breakable, 4 hazard, 5 holdable, 6 balloon";
        return false;
    }
    if (a.flags & ~known_flags()) {
        err = "unknown flags";
        return false;
    }
    if (!fin3(a.pos) || !within(a.pos, kMaxCoord) || !std::isfinite(a.yaw_deg) || std::fabs(a.yaw_deg) > 1.0e6f) {
        err = "position or yaw not finite (or beyond 65536 units)";
        return false;
    }
    if (a.armor < -1 || a.armor > 3 || a.touch < -1 || a.touch > 3) {
        err = "armor and touch: -1 (the kind's default) .. 3";
        return false;
    }
    if (a.cooldown > 3600u) {
        err = "cooldown: at most 3600 steps";
        return false;
    }
    if (a.nshapes < 1u || a.nshapes > kMaxShapes) {
        err = "1..4 shapes";
        return false;
    }
    if (!std::isfinite(a.launch_speed) || a.launch_speed < 0.0f || a.launch_speed > 60000.0f ||
        !std::isfinite(a.grab_reach) || a.grab_reach < 0.0f || a.grab_reach > 1000.0f) {
        err = "launch speed 0..60000 HU/s, grab reach 0..1000 HU";
        return false;
    }
    d.kind = a.kind;
    d.flags = a.flags;
    std::memcpy(d.position, a.pos, sizeof d.position);
    d.yaw = yaw_rad(a.yaw_deg);
    d.armor = a.armor;
    d.touch = a.touch;
    d.cooldown_steps = a.cooldown;
    d.user = (uint64_t)(uint32_t)a.ent;
    d.num_shapes = a.nshapes;
    for (uint32_t i = 0; i < a.nshapes; i++) {
        const ShapeArgs &s = a.shapes[i];
        sa1_hostobj_shape &o = d.shapes[i];
        uint32_t need = s.form == SA1_SHAPE_SPHERE ? 1u : s.form == SA1_SHAPE_CYLINDER ? 2u : 3u;
        if (s.form != SA1_SHAPE_SPHERE && s.form != SA1_SHAPE_CYLINDER && s.form != SA1_SHAPE_BOX) {
            err = "shape form: 0 sphere, 1 cylinder, 4 box";
            return false;
        }
        if (s.flags & ~(SA1_HSHAPE_NO_DAMAGE | SA1_HSHAPE_NO_TOUCH | SA1_HSHAPE_OFF)) {
            err = "unknown shape flags";
            return false;
        }
        if (!fin3(s.center) || !within(s.center, kMaxSize) || !std::isfinite(s.yaw_deg) ||
            std::fabs(s.yaw_deg) > 1.0e6f) {
            err = "shape centre or yaw not finite (or the centre beyond 4000 units)";
            return false;
        }
        o.form = s.form;
        std::memcpy(o.center, s.center, sizeof o.center);
        o.yaw = s.form == SA1_SHAPE_BOX ? yaw_rad(s.yaw_deg) : 0.0f;
        o.flags = s.flags;
        for (uint32_t k = 0; k < need; k++) {
            if (!std::isfinite(s.size[k]) || !(s.size[k] > 0.0f)) {
                err = "shape sizes: finite and positive";
                return false;
            }
            o.size[k] = clampf(s.size[k], kMinSize, kMaxSize);
        }
        // a sphere's height and a cylinder's third size are not used (libsa1 takes them as 0)
    }
    if (a.kind == SA1_HOSTOBJ_HOLDABLE) {
        // the body from shape 0: its horizontal radius (a box: its horizontal half diagonal) at most 128 HU
        sa1_hostobj_shape &o = d.shapes[0];
        if (o.form == SA1_SHAPE_BOX) {
            float r = std::sqrt(o.size[0] * o.size[0] + o.size[1] * o.size[1]);
            if (r > kMaxHoldSize) {
                // scaled together: the proportions kept, the diagonal just inside the limit (a prop the server lets
                // be carried is at most 256 units across, so the factor is at least 0.7)
                float k = kMaxHoldSize / r * 0.999f;
                o.size[0] *= k;
                o.size[1] *= k;
            }
        } else if (o.size[0] > kMaxHoldSize) {
            o.size[0] = kMaxHoldSize * 0.999f;
        }
        d.grab_reach = a.grab_reach;
    }
    if (a.kind == SA1_HOSTOBJ_BALLOON) {
        d.launch_speed = a.launch_speed;
    }
    return true;
}

// ---- Registry -------------------------------------------------------------------------------------------------------
void Registry::forget()
{
    if (!by_ent_.empty()) {
        st_.forgets++;
    }
    by_ent_.clear();
    by_id_.clear();
    gen_++;
}

void Registry::bind(sa1_context *ctx)
{
    if (ctx != ctx_) {
        forget();
        ctx_ = ctx;
    }
}

sa1_status Registry::set(sa1_context *ctx, const ObjArgs &a, uint32_t &id, bool *added, std::string &err)
{
    id = 0;
    if (added) {
        *added = false;
    }
    bind(ctx);
    if (!ctx) {
        err = "no libsa1 context (the disc is not loaded)";
        return SA1_ERR_NOT_LOADED;
    }
    sa1_hostobj_desc d;
    if (!make_desc(a, d, err)) {
        return SA1_ERR_INVALID_ARGUMENT;
    }
    auto it = by_ent_.find(a.ent);
    if (it != by_ent_.end()) {
        Obj &o = it->second;
        if (std::memcmp(&o.desc, &d, sizeof d) == 0) {
            st_.unchanged++;
            id = o.id;
            return SA1_OK;
        }
        sa1_status s = sa1_hostobj_update(ctx, o.id, &d);
        if (s == SA1_OK) {
            o.desc = d;
            std::memcpy(o.pos, d.position, sizeof o.pos);
            o.yaw = d.yaw;
            st_.updates++;
            id = o.id;
            return SA1_OK;
        }
        if (s != SA1_ERR_NOT_FOUND) {
            st_.failures++;
            err = sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_hostobj_update failed";
            st_.last_error = err;
            return s;
        }
        // libsa1 lost it (should not happen): added again below
        by_id_.erase(o.id);
        by_ent_.erase(it);
    }
    uint32_t nid = 0;
    sa1_status s = sa1_hostobj_add(ctx, &d, &nid);
    if (s != SA1_OK || nid == 0) {
        st_.failures++;
        err = sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_hostobj_add failed";
        st_.last_error = err;
        return s != SA1_OK ? s : SA1_ERR_LIMIT;
    }
    Obj o;
    o.id = nid;
    o.desc = d;
    std::memcpy(o.pos, d.position, sizeof o.pos);
    o.yaw = d.yaw;
    by_ent_[a.ent] = o;
    by_id_[nid] = a.ent;
    st_.adds++;
    id = nid;
    if (added) {
        *added = true;
    }
    return SA1_OK;
}

sa1_status Registry::move(sa1_context *ctx, int32_t ent, const float pos[3], float yaw_deg)
{
    bind(ctx);
    auto it = by_ent_.find(ent);
    if (!ctx || it == by_ent_.end()) {
        return SA1_ERR_NOT_FOUND;
    }
    if (!pos || !fin3(pos) || !within(pos, kMaxCoord) || !std::isfinite(yaw_deg) || std::fabs(yaw_deg) > 1.0e6f) {
        return SA1_ERR_INVALID_ARGUMENT;
    }
    Obj &o = it->second;
    float yaw = yaw_rad(yaw_deg);
    if (std::memcmp(o.pos, pos, sizeof o.pos) == 0 && o.yaw == yaw) {
        st_.moves_skipped++;
        return SA1_OK;
    }
    sa1_status s = sa1_hostobj_move(ctx, o.id, pos, yaw);
    if (s == SA1_OK) {
        std::memcpy(o.pos, pos, sizeof o.pos);
        o.yaw = yaw;
        // the description follows, so that set() with the same arguments sees no change
        std::memcpy(o.desc.position, pos, sizeof o.desc.position);
        o.desc.yaw = yaw;
        st_.moves++;
    } else {
        st_.failures++;
        st_.last_error = sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_hostobj_move failed";
        if (s == SA1_ERR_NOT_FOUND) {
            by_id_.erase(o.id);
            by_ent_.erase(it);
        }
    }
    return s;
}

bool Registry::remove(sa1_context *ctx, int32_t ent, bool killed)
{
    bind(ctx);
    auto it = by_ent_.find(ent);
    if (it == by_ent_.end()) {
        return false;
    }
    if (ctx) {
        sa1_hostobj_remove(ctx, it->second.id, killed ? SA1_HOSTOBJ_REMOVE_KILLED : SA1_HOSTOBJ_REMOVE_SILENT);
    }
    by_id_.erase(it->second.id);
    by_ent_.erase(it);
    st_.removes++;
    return true;
}

size_t Registry::clear(sa1_context *ctx)
{
    bind(ctx);
    size_t n = by_ent_.size();
    if (ctx) {
        for (const auto &kv : by_ent_) {
            sa1_hostobj_remove(ctx, kv.second.id, SA1_HOSTOBJ_REMOVE_SILENT);
        }
    }
    st_.removes += n;
    by_ent_.clear();
    by_id_.clear();
    return n;
}

bool Registry::id_of(int32_t ent, uint32_t &id) const
{
    auto it = by_ent_.find(ent);
    if (it == by_ent_.end()) {
        return false;
    }
    id = it->second.id;
    return true;
}

bool Registry::ent_of(uint32_t id, int32_t &ent) const
{
    auto it = by_id_.find(id);
    if (it == by_id_.end()) {
        return false;
    }
    ent = it->second;
    return true;
}

// ---- contacts -------------------------------------------------------------------------------------------------------
std::vector<ContactSum> summarize(const sa1_contact *c, size_t n, const EntityLookup &lookup)
{
    std::vector<ContactSum> out;
    std::map<int32_t, size_t> at;
    for (size_t i = 0; c && i < n; i++) {
        const sa1_contact &k = c[i];
        int32_t ent = 0;
        uint32_t chunk = 0;
        if (!lookup || !lookup(k.object, ent, chunk)) {
            continue;
        }
        if (!fin3(k.normal) || !fin3(k.point) || !fin3(k.velocity) || !fin3(k.velocity_after) ||
            !std::isfinite(k.depth)) {
            continue;
        }
        auto f = at.find(ent);
        if (f == at.end()) {
            ContactSum s;
            s.ent = ent;
            s.object = k.object;
            s.chunk = chunk;
            at[ent] = out.size();
            out.push_back(s);
            f = at.find(ent);
        }
        ContactSum &s = out[f->second];
        s.steps++;
        s.side += k.type == SA1_CONTACT_SIDE;
        s.landing += k.type == SA1_CONTACT_LANDING;
        s.head += k.type == SA1_CONTACT_HEAD;
        s.riding += (k.flags & SA1_CONTACTF_RIDING) != 0;
        s.wall += (k.flags & SA1_CONTACTF_WALL) != 0;
        s.first += (k.flags & SA1_CONTACTF_FIRST) != 0;
        s.depth = std::max(s.depth, k.depth);
        s.last_step = std::max(s.last_step, k.step);
        float into[3] = {-k.normal[0], -k.normal[1], -k.normal[2]};
        float vin = std::max(0.0f, dot3(k.velocity, into));
        float vout = std::max(0.0f, dot3(k.velocity_after, into));
        bool pushy = k.type == SA1_CONTACT_SIDE || k.type == SA1_CONTACT_HEAD;
        bool have_pushy = s.type == SA1_CONTACT_SIDE || s.type == SA1_CONTACT_HEAD;
        bool take;
        if (pushy) {
            // the strongest side / head contact: the largest approach speed, then the deepest
            take = !have_pushy || vin > s.vin || (vin == s.vin && k.depth > s.depth);
        } else {
            take = !have_pushy;          // only landings so far: the last one
        }
        if (take) {
            s.type = k.type;
            std::memcpy(s.normal, k.normal, sizeof s.normal);
            std::memcpy(s.point, k.point, sizeof s.point);
            std::memcpy(s.velocity, k.velocity, sizeof s.velocity);
            s.vin = pushy ? vin : 0.0f;
            s.vout = pushy ? vout : 0.0f;
        }
    }
    return out;
}

}  // namespace interact
}  // namespace gsa1
