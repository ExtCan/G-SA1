// G-SA1 core: the feature "objects" (round 0.9.4). See objects.hpp.
#include "objects.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

#include "session.hpp"
#include "util.hpp"

namespace gsa1 {
namespace objects {

namespace {

const double kPi = 3.14159265358979323846;

bool finite3(const float v[3])
{
    return std::isfinite(v[0]) && std::isfinite(v[1]) && std::isfinite(v[2]);
}

// a whole number in [lo, hi]
bool whole(float f, float lo, float hi)
{
    return std::isfinite(f) && f >= lo && f <= hi && std::floor(f) == f;
}

sa1_set_record blank(uint32_t type, uint32_t object, uint32_t index)
{
    sa1_set_record r;
    std::memset(&r, 0, sizeof r);
    r.struct_size = sizeof r;
    r.type = type;
    r.flags = 0;
    r.kinds = 0;
    r.user = ((uint64_t)object << 8) | (uint64_t)(index & 0xFFu);
    return r;
}

// the line's record g of `count` rings: its ring count k and the place (0 .. count - 1) of its ring 0
void line_record(uint32_t count, uint32_t g, uint32_t &k, uint32_t &centre)
{
    k = std::min(kLineGroup, count - kLineGroup * g);
    centre = kLineGroup * g + (k - 1u) / 2u;
}

// place p of a line of `count` rings -> its offset along the forward axis in spacings (the line is centred)
double line_offset(uint32_t count, double place)
{
    return place - ((double)count - 1.0) * 0.5;
}

// a group's ring count, spacing and shape; false with err when they are not usable
bool group_args(const Desc &d, uint32_t &count, float &s, uint32_t &shape, std::string &err)
{
    if (!whole(d.p[2], 0.0f, 1.0f)) {
        err = format("a ring group's shape is 0 (line) or 1 (circle), not %g", (double)d.p[2]);
        return false;
    }
    shape = (uint32_t)d.p[2];
    float hi = shape == kShapeLine ? (float)kLineMax : (float)kCircleMax;
    if (!whole(d.p[0], 1.0f, hi)) {
        err = format("a Ring %s has 1 to %u rings, not %g", shape == kShapeLine ? "line" : "circle", (unsigned)hi,
                     (double)d.p[0]);
        return false;
    }
    count = (uint32_t)d.p[0];
    if (!std::isfinite(d.p[1]) || d.p[1] < kMinSpacing || d.p[1] > kMaxSpacing) {
        err = format("a Ring %s's %s is %g to %g units, not %g", shape == kShapeLine ? "line" : "circle",
                     shape == kShapeLine ? "spacing" : "radius", (double)kMinSpacing, (double)kMaxSpacing, (double)d.p[1]);
        return false;
    }
    s = d.p[1];
    return true;
}

bool common_args(const Desc &d, std::string &err)
{
    if (d.type < SA1_OBJTYPE_RING || d.type > SA1_OBJTYPE_ITEMBOX_AIR) {
        err = format("unknown object type %u (1 Ring, 2 ring group, 3 Item Box, 4 Item Box (Air))", (unsigned)d.type);
        return false;
    }
    if (!finite3(d.pos) || !finite3(d.ang) || !finite3(d.p)) {
        err = "a position, angle or parameter is not a finite number";
        return false;
    }
    for (int k = 0; k < 3; k++) {
        if (std::fabs(d.pos[k]) > kMaxCoord) {
            err = format("position %g is outside the map (%g)", (double)d.pos[k], (double)kMaxCoord);
            return false;
        }
    }
    return true;
}

// m = a x Rz(t degrees) (row-major): a host rotation turned about its own local up (the game's local +y)
void turn_about_up(const float a[9], double t_deg, float m[9])
{
    double c = std::cos(t_deg * kPi / 180.0), s = std::sin(t_deg * kPi / 180.0);
    for (int r = 0; r < 3; r++) {
        double x = a[3 * r + 0], y = a[3 * r + 1];
        m[3 * r + 0] = (float)(x * c + y * s);
        m[3 * r + 1] = (float)(-x * s + y * c);
        m[3 * r + 2] = a[3 * r + 2];
    }
}

}  // namespace

void circle_split(uint32_t count, uint32_t &n, uint32_t &m)
{
    n = 1;
    for (uint32_t k = kCircleGroup; k >= 1; k--) {
        if (count % k == 0) {
            n = k;
            break;
        }
    }
    m = count == 0 ? 0 : count / n;
}

void angle_matrix(const float ang_deg[3], float m[9])
{
    double sp = std::sin(ang_deg[0] * kPi / 180.0), cp = std::cos(ang_deg[0] * kPi / 180.0);
    double sy = std::sin(ang_deg[1] * kPi / 180.0), cy = std::cos(ang_deg[1] * kPi / 180.0);
    double sr = std::sin(ang_deg[2] * kPi / 180.0), cr = std::cos(ang_deg[2] * kPi / 180.0);
    // Source's AngleMatrix: columns forward, left, up
    m[0] = (float)(cp * cy);
    m[3] = (float)(cp * sy);
    m[6] = (float)(-sp);
    m[1] = (float)(sp * sr * cy - cr * sy);
    m[4] = (float)(sp * sr * sy + cr * cy);
    m[7] = (float)(sr * cp);
    m[2] = (float)(sp * cr * cy + sr * sy);
    m[5] = (float)(sp * cr * sy - sr * cy);
    m[8] = (float)(cr * cp);
}

void record_matrix(const float ang_deg[3], float m[9])
{
    float a[9];
    angle_matrix(ang_deg, a);
    // a x Rz(90 degrees): columns left, -forward, up
    for (int r = 0; r < 3; r++) {
        m[3 * r + 0] = a[3 * r + 1];
        m[3 * r + 1] = -a[3 * r + 0];
        m[3 * r + 2] = a[3 * r + 2];
    }
}

uint32_t record_count(const Desc &d)
{
    std::string err;
    if (!common_args(d, err)) {
        return 0;
    }
    if (d.type != SA1_OBJTYPE_O_GRING) {
        return 1;
    }
    uint32_t count = 0, shape = 0;
    float s = 0.0f;
    if (!group_args(d, count, s, shape, err)) {
        return 0;
    }
    if (shape == kShapeCircle) {
        uint32_t n = 0, m = 0;
        circle_split(count, n, m);
        return m;
    }
    return (count + kLineGroup - 1u) / kLineGroup;
}

bool make_records(const Desc &d, float hu_per_unit, uint32_t object, std::vector<sa1_set_record> &out, std::string &err)
{
    out.clear();
    if (!common_args(d, err)) {
        return false;
    }
    if (!(hu_per_unit > 0.0f) || !std::isfinite(hu_per_unit)) {
        err = "no host scale";
        return false;
    }
    float rot[9], am[9];
    record_matrix(d.ang, rot);
    angle_matrix(d.ang, am);
    const float fwd[3] = {am[0], am[3], am[6]};
    switch (d.type) {
    case SA1_OBJTYPE_RING: {
        sa1_set_record r = blank(d.type, object, 0);
        std::memcpy(r.position, d.pos, sizeof r.position);
        std::memcpy(r.rotation, rot, sizeof r.rotation);
        out.push_back(r);
        return true;
    }
    case SA1_OBJTYPE_O_GRING: {
        uint32_t count = 0, shape = 0;
        float s = 0.0f;
        if (!group_args(d, count, s, shape, err)) {
            return false;
        }
        if (shape == kShapeCircle) {
            // m records of n rings (n | count, n <= 7), record k turned by k * 360 / count about the circle's axis
            uint32_t n = 0, m = 0;
            circle_split(count, n, m);
            for (uint32_t k = 0; k < m; k++) {
                sa1_set_record r = blank(d.type, object, k);
                std::memcpy(r.position, d.pos, sizeof r.position);
                turn_about_up(rot, (double)k * 360.0 / (double)count, r.rotation);
                r.params[0] = (float)n;                 // a circle of n rings: ring i = 1 .. n
                r.params[1] = s / hu_per_unit;
                r.params[2] = 1.0f;
                out.push_back(r);
            }
            return true;
        }
        uint32_t groups = (count + kLineGroup - 1u) / kLineGroup;
        for (uint32_t g = 0; g < groups; g++) {
            uint32_t k = 0, centre = 0;
            line_record(count, g, k, centre);
            double off = (double)s * line_offset(count, (double)centre);
            sa1_set_record r = blank(d.type, object, g);
            for (int c = 0; c < 3; c++) {
                r.position[c] = (float)((double)d.pos[c] + (double)fwd[c] * off);
            }
            std::memcpy(r.rotation, rot, sizeof r.rotation);
            r.params[0] = (float)(k - 1u);              // a line of n + 1 rings
            r.params[1] = s / hu_per_unit;
            r.params[2] = 0.0f;
            out.push_back(r);
        }
        return true;
    }
    case SA1_OBJTYPE_ITEMBOX:
    case SA1_OBJTYPE_ITEMBOX_AIR: {
        if (!whole(d.p[0], 0.0f, (float)kContentsMax)) {
            err = format("an item box holds one of the game's 9 items (0 .. 8), not %g", (double)d.p[0]);
            return false;
        }
        sa1_set_record r = blank(d.type, object, 0);
        std::memcpy(r.position, d.pos, sizeof r.position);
        r.params[0] = d.p[0];
        if (d.type == SA1_OBJTYPE_ITEMBOX) {
            // upright whatever the entity's angles (decision 10): no rotation; the panel's start angle (scl.y)
            float a = std::fmod(d.p[1], 360.0f);
            r.params[1] = std::isfinite(a) ? a : 0.0f;
        } else {
            std::memcpy(r.rotation, rot, sizeof r.rotation);
        }
        out.push_back(r);
        return true;
    }
    default:
        break;
    }
    err = format("unknown object type %u", (unsigned)d.type);
    return false;
}

bool ring_positions(const Desc &d, std::vector<RingPos> &out)
{
    out.clear();
    std::string err;
    if (!common_args(d, err)) {
        return false;
    }
    float am[9];
    angle_matrix(d.ang, am);
    const float fwd[3] = {am[0], am[3], am[6]}, left[3] = {am[1], am[4], am[7]};
    if (d.type == SA1_OBJTYPE_RING) {
        RingPos r;
        std::memcpy(r.pos, d.pos, sizeof r.pos);
        out.push_back(r);
        return true;
    }
    if (d.type != SA1_OBJTYPE_O_GRING) {
        return false;
    }
    uint32_t count = 0, shape = 0;
    float s = 0.0f;
    if (!group_args(d, count, s, shape, err)) {
        return false;
    }
    if (shape == kShapeCircle) {
        // record k's ring i (bit 1 << i) at the place (i * m + k) mod count (func_8C088000 on the turned record)
        uint32_t n = 0, m = 0;
        circle_split(count, n, m);
        for (uint32_t k = 0; k < m; k++) {
            for (uint32_t i = 1; i <= n; i++) {
                uint32_t place = (i * m + k) % count;
                double a = (double)place * 360.0 / (double)count * kPi / 180.0;
                RingPos r;
                r.record = k;
                r.bit = 1u << i;
                r.place = place;
                for (int c = 0; c < 3; c++) {
                    r.pos[c] = (float)((double)d.pos[c] + (double)s * (std::cos(a) * fwd[c] + std::sin(a) * left[c]));
                }
                out.push_back(r);
            }
        }
        return true;
    }
    uint32_t groups = (count + kLineGroup - 1u) / kLineGroup;
    for (uint32_t g = 0; g < groups; g++) {
        uint32_t k = 0, centre = 0;
        line_record(count, g, k, centre);
        for (uint32_t i = 0; i < k; i++) {
            // func_8C087EEE: odd i at +ceil(i / 2), even i at -(i / 2) spacings from the record's ring 0
            int32_t rel = (i & 1u) ? (int32_t)((i + 1u) / 2u) : -(int32_t)(i / 2u);
            RingPos r;
            r.record = g;
            r.bit = 1u << i;
            r.place = (uint32_t)((int32_t)centre + rel);
            double off = (double)s * line_offset(count, (double)r.place);
            for (int c = 0; c < 3; c++) {
                r.pos[c] = (float)((double)d.pos[c] + (double)fwd[c] * off);
            }
            out.push_back(r);
        }
    }
    return true;
}

// ---- the registry ---------------------------------------------------------------------------------------------------
void Registry::bind(const void *ctx)
{
    if (ctx != ctx_) {
        if (!objs_.empty() || ctx_ != nullptr) {
            forget();
        }
        ctx_ = ctx;
    }
}

void Registry::forget()
{
    if (!objs_.empty()) {
        st_.forgets++;
    }
    objs_.clear();
    ctx_ = nullptr;         // (a new context may come back at the old one's address)
    gen_++;
    if (gen_ == 0) {
        gen_ = 1;
    }
}

size_t Registry::record_total() const
{
    size_t n = 0;
    for (const auto &kv : objs_) {
        n += kv.second.records.size();
    }
    return n;
}

const Obj *Registry::find(uint32_t id) const
{
    auto it = objs_.find(id);
    return it == objs_.end() ? nullptr : &it->second;
}

static bool state_ok(uint32_t type, uint32_t state, std::string &err)
{
    if (state & ~(SA1_SET_STATE_PRESENT | SA1_SET_STATE_BROKEN)) {
        err = format("state 0x%X (PRESENT 1, BROKEN 2)", (unsigned)state);
        return false;
    }
    if ((state & SA1_SET_STATE_BROKEN) && type != SA1_OBJTYPE_ITEMBOX) {
        err = "BROKEN is the ground Item Box's state only";
        return false;
    }
    return true;
}

sa1_status Registry::add(const Desc &d, uint64_t user, uint32_t state, Sink &s, uint32_t &id, std::string &err)
{
    id = 0;
    uint32_t oid = next_;
    std::vector<sa1_set_record> recs;
    if (!make_records(d, hu_per_unit, oid, recs, err) || !state_ok(d.type, state, err)) {
        st_.failures++;
        st_.last_error = err;
        return SA1_ERR_INVALID_ARGUMENT;
    }
    Obj o;
    o.id = oid;
    o.user = user;
    o.desc = d;
    o.state = state;
    for (const sa1_set_record &r : recs) {
        uint32_t rid = 0;
        sa1_status st = s.add(r, rid);
        if (st != SA1_OK) {
            err = s.error();
            if (err.empty()) {
                err = sa1_status_string(st);
            }
            for (uint32_t done : o.records) {
                s.remove(done);
            }
            st_.failures++;
            st_.last_error = err;
            return st;
        }
        o.records.push_back(rid);
    }
    o.bits.assign(o.records.size(), 0u);
    if (state != SA1_SET_STATE_PRESENT) {
        for (uint32_t rid : o.records) {
            s.state(rid, state, 0u);
        }
    }
    next_++;
    if (next_ == 0 || next_ > 0xFFFFFFu) {
        next_ = 1;          // (16 M objects in one context; the user tag keeps 24 bits of it)
    }
    objs_[oid] = o;
    id = oid;
    st_.adds++;
    return SA1_OK;
}

sa1_status Registry::update(uint32_t id, const Desc &d, Sink &s, std::string &err)
{
    auto it = objs_.find(id);
    if (it == objs_.end()) {
        err = "no such object";
        return SA1_ERR_NOT_FOUND;
    }
    Obj &o = it->second;
    std::vector<sa1_set_record> recs;
    if (!make_records(d, hu_per_unit, o.id, recs, err)) {
        st_.failures++;
        st_.last_error = err;
        return SA1_ERR_INVALID_ARGUMENT;
    }
    if (d.type != o.desc.type) {
        err = "an object keeps its type";
        st_.failures++;
        st_.last_error = err;
        return SA1_ERR_INVALID_ARGUMENT;
    }
    size_t keep = std::min(recs.size(), o.records.size());
    sa1_status worst = SA1_OK;
    for (size_t k = 0; k < keep; k++) {
        sa1_status st = s.update(o.records[k], recs[k]);
        if (st != SA1_OK) {
            worst = st;
        }
    }
    while (o.records.size() > recs.size()) {
        s.remove(o.records.back());
        o.records.pop_back();
    }
    for (size_t k = o.records.size(); k < recs.size(); k++) {
        uint32_t rid = 0;
        sa1_status st = s.add(recs[k], rid);
        if (st != SA1_OK) {
            worst = st;
            break;
        }
        o.records.push_back(rid);
        if (o.state != SA1_SET_STATE_PRESENT) {
            s.state(rid, o.state, 0u);
        }
    }
    o.bits.resize(o.records.size(), 0u);
    o.desc = d;
    st_.updates++;
    if (worst != SA1_OK) {
        err = s.error();
        if (err.empty()) {
            err = sa1_status_string(worst);
        }
        st_.failures++;
        st_.last_error = err;
    }
    return worst;
}

sa1_status Registry::remove(uint32_t id, Sink &s)
{
    auto it = objs_.find(id);
    if (it == objs_.end()) {
        return SA1_ERR_NOT_FOUND;
    }
    for (uint32_t rid : it->second.records) {
        s.remove(rid);
    }
    objs_.erase(it);
    st_.removes++;
    return SA1_OK;
}

sa1_status Registry::set_state(uint32_t id, uint32_t state, int32_t index, uint32_t bits, Sink &s, std::string &err)
{
    auto it = objs_.find(id);
    if (it == objs_.end()) {
        err = "no such object";
        return SA1_ERR_NOT_FOUND;
    }
    Obj &o = it->second;
    if (!state_ok(o.desc.type, state, err)) {
        return SA1_ERR_INVALID_ARGUMENT;
    }
    if (index >= (int32_t)o.records.size()) {
        err = format("record %d of %u", (int)index, (unsigned)o.records.size());
        return SA1_ERR_INVALID_ARGUMENT;
    }
    if (index >= 0 && (bits > 0xFFu || (bits != 0 && o.desc.type != SA1_OBJTYPE_O_GRING))) {
        err = format("user bits 0x%X (a ring group's: 0 .. 0xFF; other objects: 0)", (unsigned)bits);
        return SA1_ERR_INVALID_ARGUMENT;
    }
    bool state_changed = state != o.state;
    o.state = state;
    std::vector<sa1_set_record> recs;
    bool have_recs = false;
    sa1_status worst = SA1_OK;
    for (size_t k = 0; k < o.records.size(); k++) {
        bool mine = index < 0 || (size_t)index == k;
        if (!mine && !state_changed) {
            continue;
        }
        uint32_t old = o.bits[k];
        if (mine && index >= 0) {
            o.bits[k] = bits;
        }
        sa1_status st = s.state(o.records[k], state, o.bits[k]);
        if (st != SA1_OK) {
            worst = st;
            continue;
        }
        st_.states++;
        if (o.desc.type == SA1_OBJTYPE_O_GRING && (old & ~o.bits[k]) != 0) {
            // libsa1's state only adds a group's bits: rings coming back need the group made again from the registry
            if (!have_recs) {
                std::string e2;
                have_recs = make_records(o.desc, hu_per_unit, o.id, recs, e2);
            }
            if (have_recs && k < recs.size() && s.update(o.records[k], recs[k]) == SA1_OK) {
                st_.remakes++;
            }
        }
    }
    if (worst != SA1_OK) {
        err = s.error();
        if (err.empty()) {
            err = sa1_status_string(worst);
        }
        st_.failures++;
        st_.last_error = err;
    }
    return worst;
}

size_t Registry::clear(Sink &s)
{
    size_t n = objs_.size();
    for (auto &kv : objs_) {
        for (uint32_t rid : kv.second.records) {
            s.remove(rid);
        }
    }
    objs_.clear();
    st_.removes += n;
    return n;
}

bool Registry::map(const sa1_set_event &e, Event &out)
{
    uint32_t oid = (uint32_t)(e.user >> 8);
    uint32_t idx = (uint32_t)(e.user & 0xFFu);
    auto it = objs_.find(oid);
    if (it == objs_.end() || idx >= it->second.records.size() || it->second.records[idx] != e.record) {
        st_.dropped++;
        return false;
    }
    out.object = oid;
    out.user = it->second.user;
    out.index = idx;
    out.type = it->second.desc.type;
    out.ev = e;
    st_.events++;
    return true;
}

// ---- drawing --------------------------------------------------------------------------------------------------------
bool object_draw_bounds(const Character &c, float mn[3], float mx[3])
{
    bool any = false;
    auto add = [&](const float *p, float r) {
        if (!std::isfinite(p[0]) || !std::isfinite(p[1]) || !std::isfinite(p[2])) {
            return;
        }
        for (int k = 0; k < 3; k++) {
            if (!any || p[k] - r < mn[k]) mn[k] = p[k] - r;
            if (!any || p[k] + r > mx[k]) mx[k] = p[k] + r;
        }
        any = true;
    };
    for (const sa1_draw &d : c.r_draws) {
        if (!(d.flags & SA1_DRAW_OBJECT) || d.count == 0) {
            continue;
        }
        if (d.prim == SA1_PRIM_TRIANGLES) {
            uint32_t end = std::min(d.first + d.count, c.r_triangles);
            for (uint32_t t = d.first; t < end; t++) {
                for (int k = 0; k < 3; k++) {
                    add(&c.r_tpos[(size_t)t * 9u + (size_t)k * 3u], 0.0f);
                }
            }
        } else if (d.prim == SA1_PRIM_SPRITES) {
            uint32_t end = std::min(d.first + d.count, (uint32_t)c.r_sprites.size());
            for (uint32_t s = d.first; s < end; s++) {
                const sa1_sprite &sp = c.r_sprites[s];
                float r = 0.0f;
                for (int k = 0; k < 4; k++) {
                    if (std::isfinite(sp.rect[k])) {
                        r = std::max(r, std::fabs(sp.rect[k]));
                    }
                }
                add(sp.position, std::min(r * 1.4143f, 4096.0f));
            }
        } else if (d.prim == SA1_PRIM_LINES) {
            uint32_t end = std::min(d.first + d.count, (uint32_t)(c.r_lines.size() / 2u));
            for (uint32_t s = d.first; s < end; s++) {
                add(c.r_lines[2u * s].position, 0.0f);
                add(c.r_lines[2u * s + 1u].position, 0.0f);
            }
        }
    }
    return any;
}

}  // namespace objects
}  // namespace gsa1
