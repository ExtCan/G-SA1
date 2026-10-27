// G-SA1 core: Source BSP -> collision triangles (see bsp.hpp).
#include "bsp.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <deque>
#include <iterator>
#include <map>
#include <unordered_map>

namespace gsa1 {

bool MemoryByteSource::read(uint64_t offset, void *dst, size_t n)
{
    if (offset > n_ || n > n_ - offset) {
        return false;
    }
    if (n) {
        std::memcpy(dst, p_ + offset, n);
    }
    return true;
}

bool RangeByteSource::add(uint64_t offset, const void *p, size_t n)
{
    if (offset > size_ || n > size_ - offset) {
        return false;
    }
    if (n == 0) {
        return true;
    }
    const uint64_t end = offset + n;
    // the chunk that starts before `offset` and reaches into the new range keeps its head (and its tail beyond end)
    auto it = chunks_.lower_bound(offset);
    if (it != chunks_.begin()) {
        auto pv = std::prev(it);
        uint64_t pe = pv->first + pv->second.size();
        if (pe > offset) {
            std::string tail;
            if (pe > end) {
                tail = pv->second.substr((size_t)(end - pv->first));
            }
            bytes_ -= pv->second.size();
            pv->second.resize((size_t)(offset - pv->first));
            bytes_ += pv->second.size();
            if (!tail.empty()) {
                bytes_ += tail.size();
                chunks_[end] = std::move(tail);
            }
        }
    }
    // chunks starting inside the new range are replaced (their tail beyond end kept)
    it = chunks_.lower_bound(offset);
    while (it != chunks_.end() && it->first < end) {
        uint64_t ce = it->first + it->second.size();
        bytes_ -= it->second.size();
        if (ce > end) {
            std::string tail = it->second.substr((size_t)(end - it->first));
            chunks_.erase(it);
            bytes_ += tail.size();
            chunks_[end] = std::move(tail);
            break;
        }
        it = chunks_.erase(it);
    }
    chunks_[offset].assign((const char *)p, n);
    bytes_ += n;
    return true;
}

bool RangeByteSource::read(uint64_t offset, void *dst, size_t n)
{
    if (offset > size_ || n > size_ - offset) {
        return false;
    }
    uint8_t *d = (uint8_t *)dst;
    uint64_t pos = offset;
    const uint64_t end = offset + n;
    while (pos < end) {
        auto it = chunks_.upper_bound(pos);
        if (it == chunks_.begin()) {
            return false;
        }
        --it;
        uint64_t cs = it->first, ce = cs + it->second.size();
        if (pos >= ce) {
            return false;
        }
        size_t take = (size_t)std::min<uint64_t>(ce - pos, end - pos);
        std::memcpy(d + (pos - offset), it->second.data() + (pos - cs), take);
        pos += take;
    }
    return true;
}

bool RangeByteSource::has(uint64_t offset, uint64_t n) const
{
    if (offset > size_ || n > size_ - offset) {
        return false;
    }
    uint64_t pos = offset;
    const uint64_t end = offset + n;
    while (pos < end) {
        auto it = chunks_.upper_bound(pos);
        if (it == chunks_.begin()) {
            return false;
        }
        --it;
        uint64_t ce = it->first + it->second.size();
        if (pos >= ce) {
            return false;
        }
        pos = std::min(ce, end);
    }
    return true;
}

void RangeByteSource::missing(uint64_t offset, uint64_t n, std::vector<std::pair<uint64_t, uint64_t>> &out) const
{
    if (offset > size_ || n > size_ - offset) {
        return;
    }
    uint64_t pos = offset;
    const uint64_t end = offset + n;
    while (pos < end) {
        auto it = chunks_.upper_bound(pos);
        if (it != chunks_.begin()) {
            auto pv = std::prev(it);
            uint64_t ce = pv->first + pv->second.size();
            if (pos < ce) {
                pos = std::min(ce, end);   // covered up to the chunk's end
                continue;
            }
        }
        // a gap from pos to the next chunk (or the end)
        uint64_t gap_end = it == chunks_.end() ? end : std::min(it->first, end);
        out.push_back({pos, gap_end - pos});
        pos = gap_end;
    }
}

namespace {

enum {
    LUMP_ENTITIES = 0,
    LUMP_PLANES = 1,
    LUMP_TEXDATA = 2,
    LUMP_VERTEXES = 3,
    LUMP_NODES = 5,
    LUMP_TEXINFO = 6,
    LUMP_FACES = 7,
    LUMP_LEAFS = 10,
    LUMP_EDGES = 12,
    LUMP_SURFEDGES = 13,
    LUMP_MODELS = 14,
    LUMP_LEAFBRUSHES = 17,
    LUMP_BRUSHES = 18,
    LUMP_BRUSHSIDES = 19,
    LUMP_DISPINFO = 26,
    LUMP_DISP_VERTS = 33,
    LUMP_GAME_LUMP = 35,
    LUMP_TEXDATA_STRING_DATA = 43,
    LUMP_TEXDATA_STRING_TABLE = 44,
    LUMP_DISP_TRIS = 48,
};

// the lumps G-SA1 reads (Bsp::needed_ranges)
const int kNeededLumps[] = {LUMP_ENTITIES,  LUMP_PLANES,   LUMP_VERTEXES,    LUMP_NODES,      LUMP_TEXINFO,
                            LUMP_FACES,     LUMP_LEAFS,    LUMP_EDGES,       LUMP_SURFEDGES,  LUMP_MODELS,
                            LUMP_LEAFBRUSHES, LUMP_BRUSHES, LUMP_BRUSHSIDES, LUMP_DISPINFO,   LUMP_DISP_VERTS,
                            LUMP_GAME_LUMP, LUMP_DISP_TRIS, LUMP_TEXDATA, LUMP_TEXDATA_STRING_DATA,
                            LUMP_TEXDATA_STRING_TABLE};

const uint32_t CONTENTS_SOLID = 0x1u, CONTENTS_WINDOW = 0x2u, CONTENTS_GRATE = 0x8u, CONTENTS_SLIME = 0x10u,
               CONTENTS_WATER = 0x20u, CONTENTS_MOVEABLE = 0x4000u, CONTENTS_PLAYERCLIP = 0x10000u;
const int32_t SURF_SKY2D = 0x2, SURF_SKY = 0x4, SURF_NODRAW = 0x80;
const uint16_t DISPTRI_TAG_WALKABLE = 0x2;   // vbsp: the triangle's normal (engine winding) has z >= 0.7
const double kDispBlendAlpha = 382.5;        // a displacement triangle whose corner alphas add up to more takes the
                                             // material's $surfaceprop2 (Source's DISP_ALPHA_PROP_DELTA; UNVERIFIED)
const uint32_t kSprpId = 0x73707270u;        // 'sprp'

#pragma pack(push, 1)
struct DPlane {
    float n[3];
    float d;
    int32_t type;
};
struct DVertex {
    float p[3];
};
struct DEdge {
    uint16_t v[2];
};
struct DFace {
    uint16_t planenum;
    uint8_t side, on_node;
    int32_t firstedge;
    int16_t numedges, texinfo, dispinfo, fog;
    uint8_t styles[4];
    int32_t lightofs;
    float area;
    int32_t lm_mins[2], lm_size[2];
    int32_t orig_face;
    uint16_t num_prims, first_prim;
    uint32_t smoothing;
};
struct DTexinfo {
    float tv[2][4];
    float lv[2][4];
    int32_t flags;
    int32_t texdata;
};
struct DNode {
    int32_t planenum;
    int32_t children[2];
    int16_t mins[3], maxs[3];
    uint16_t firstface, numfaces;
    int16_t area, pad;
};
struct DLeafHead {   // the prefix shared by the 56-byte (lump version 0) and 32-byte (version 1) leaves
    int32_t contents;
    int16_t cluster;
    int16_t areaflags;
    int16_t mins[3], maxs[3];
    uint16_t firstleafface, numleaffaces, firstleafbrush, numleafbrushes;
};
struct DModel {
    float mins[3], maxs[3], origin[3];
    int32_t headnode, firstface, numfaces;
};
struct DBrush {
    int32_t firstside, numsides, contents;
};
struct DBrushSide {
    uint16_t planenum;
    int16_t texinfo;
    int16_t dispinfo;
    uint8_t bevel;
    uint8_t thin;
};
struct DDispInfo {
    float start[3];
    int32_t vert_start, tri_start, power, min_tess;
    float smoothing;
    int32_t contents;
    uint16_t map_face;
    uint16_t pad;
    int32_t lm_alpha_start, lm_sample_start;
    uint8_t neighbors[88];
    uint32_t allowed[10];
};
struct DDispVert {
    float vec[3];
    float dist;
    float alpha;
};
struct DTexdata {
    float reflectivity[3];
    int32_t name_string;              // index into the TEXDATA_STRING_TABLE lump
    int32_t width, height, view_width, view_height;
};
#pragma pack(pop)

static_assert(sizeof(DPlane) == 20, "dplane_t");
static_assert(sizeof(DVertex) == 12, "dvertex_t");
static_assert(sizeof(DEdge) == 4, "dedge_t");
static_assert(sizeof(DFace) == 56, "dface_t");
static_assert(sizeof(DTexinfo) == 72, "texinfo_t");
static_assert(sizeof(DNode) == 32, "dnode_t");
static_assert(sizeof(DLeafHead) == 28, "dleaf_t prefix");
static_assert(sizeof(DModel) == 48, "dmodel_t");
static_assert(sizeof(DBrush) == 12, "dbrush_t");
static_assert(sizeof(DBrushSide) == 8, "dbrushside_t");
static_assert(sizeof(DDispInfo) == 176, "ddispinfo_t");
static_assert(sizeof(DDispVert) == 20, "CDispVert");
static_assert(sizeof(DTexdata) == 32, "dtexdata_t");

struct D3 {
    double x, y, z;
};
inline D3 operator+(D3 a, D3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline D3 operator-(D3 a, D3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline D3 operator*(D3 a, double s) { return {a.x * s, a.y * s, a.z * s}; }
inline double dot(D3 a, D3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline D3 cross(D3 a, D3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
inline double length(D3 a) { return std::sqrt(dot(a, a)); }
inline D3 lerp(D3 a, D3 b, double t) { return a + (b - a) * t; }
inline D3 d3(const float *f) { return {f[0], f[1], f[2]}; }
inline bool finite3(const float *f) { return std::isfinite(f[0]) && std::isfinite(f[1]) && std::isfinite(f[2]); }
inline D3 dmin(D3 a, D3 b) { return {std::min(a.x, b.x), std::min(a.y, b.y), std::min(a.z, b.z)}; }
inline D3 dmax(D3 a, D3 b) { return {std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z)}; }

const double kMaxCoord = 262144.0;   // beyond any Source coordinate (maps live within +-16384, some +-32768)
// 0.9.3 (front-only ceilings): a one-way underside this flat (n.z at most this: within 14 degrees of level) stays as a
// front-only ceiling; a steeper one is left out as before. libsa1's GRID c2 uses the same bound (CA_UNDER_FLAT_NY): the
// ceiling doc's -0.9 (25.8 degrees) let a runner at dash-panel speed dip under thin plank ramps of 20-25 degrees at their
// foot, where the front-only underside - in front of the sphere by then - pushed it down through the plank
const double kFrontOnlyNz = -0.97;

struct Plane {
    D3 n;
    double d;
    bool ok;
};

void base_winding(const Plane &p, std::vector<D3> &w)
{
    double ax = std::fabs(p.n.x), ay = std::fabs(p.n.y), az = std::fabs(p.n.z);
    D3 up = (az >= ax && az >= ay) ? D3{1, 0, 0} : D3{0, 0, 1};
    up = up - p.n * dot(up, p.n);
    up = up * (1.0 / length(up));
    D3 right = cross(up, p.n);
    D3 org = p.n * p.d;
    up = up * kMaxCoord;
    right = right * kMaxCoord;
    w.clear();
    w.push_back(org - right + up);
    w.push_back(org + right + up);
    w.push_back(org + right - up);
    w.push_back(org - right - up);
}

// keeps the part of the convex polygon behind the plane (dot(n, p) - d <= eps)
void clip_back(std::vector<D3> &w, const Plane &p, double eps, std::vector<D3> &tmp)
{
    tmp.clear();
    size_t n = w.size();
    for (size_t i = 0; i < n; i++) {
        const D3 &a = w[i];
        const D3 &b = w[(i + 1) % n];
        double da = dot(p.n, a) - p.d, db = dot(p.n, b) - p.d;
        if (da <= eps) {
            tmp.push_back(a);
        }
        if ((da < -eps && db > eps) || (da > eps && db < -eps)) {
            double t = da / (da - db);
            tmp.push_back(a + (b - a) * t);
        }
    }
    w.swap(tmp);
}

// splits the convex polygon w by the plane: front = the part with dot(n, p) - d >= -eps, back = <= eps (points
// within eps of the plane go to both); an empty part has no points
void split_poly(const std::vector<D3> &w, const Plane &p, double eps, std::vector<D3> &front, std::vector<D3> &back)
{
    front.clear();
    back.clear();
    size_t n = w.size();
    for (size_t i = 0; i < n; i++) {
        const D3 &a = w[i];
        const D3 &b = w[(i + 1) % n];
        double da = dot(p.n, a) - p.d, db = dot(p.n, b) - p.d;
        if (da >= -eps) {
            front.push_back(a);
        }
        if (da <= eps) {
            back.push_back(a);
        }
        if ((da < -eps && db > eps) || (da > eps && db < -eps)) {
            D3 m = a + (b - a) * (da / (da - db));
            front.push_back(m);
            back.push_back(m);
        }
    }
    if (front.size() < 3) {
        front.clear();
    }
    if (back.size() < 3) {
        back.clear();
    }
}

void plane_range(const std::vector<D3> &w, const Plane &p, double &dmn, double &dmx)
{
    dmn = dmx = 0.0;
    for (size_t k = 0; k < w.size(); k++) {
        double d = dot(p.n, w[k]) - p.d;
        dmn = k == 0 ? d : std::min(dmn, d);
        dmx = k == 0 ? d : std::max(dmx, d);
    }
}

void dedupe(std::vector<D3> &w)
{
    std::vector<D3> o;
    o.reserve(w.size());
    for (const D3 &p : w) {
        if (o.empty() || length(p - o.back()) > 1e-3) {
            o.push_back(p);
        }
    }
    while (o.size() > 1 && length(o.front() - o.back()) <= 1e-3) {
        o.pop_back();
    }
    w.swap(o);
}

D3 newell(const std::vector<D3> &w)
{
    D3 nn{0, 0, 0};
    size_t n = w.size();
    for (size_t i = 0; i < n; i++) {
        const D3 &p = w[i];
        const D3 &q = w[(i + 1) % n];
        nn.x += (p.y - q.y) * (p.z + q.z);
        nn.y += (p.z - q.z) * (p.x + q.x);
        nn.z += (p.x - q.x) * (p.y + q.y);
    }
    return nn;
}

D3 centroid(const std::vector<D3> &w)
{
    D3 c{0, 0, 0};
    for (const D3 &p : w) {
        c = c + p;
    }
    return w.empty() ? c : c * (1.0 / (double)w.size());
}

// keeps the parts of the fragments (convex pieces of one face with normal fn) outside the convex volume bounded by
// `planes` (outward normals). Inside counts: lying on one of its planes and facing into it (two solids touching);
// lying on one of its planes facing the same way (a coplanar duplicate) unless keep_dups. Returns whether a fragment
// was cut or removed. next / inside / front / back are scratch.
bool cut_by_volume(std::vector<std::vector<D3>> &frags, const D3 &fn, bool keep_dups,
                   const std::vector<const Plane *> &planes, std::vector<std::vector<D3>> &next, std::vector<D3> &inside,
                   std::vector<D3> &front, std::vector<D3> &back)
{
    next.clear();
    bool touched = false;
    for (const std::vector<D3> &fr : frags) {
        // separated from the volume by one of its planes, or a coplanar duplicate that is kept: unchanged
        bool keep = false;
        for (const Plane *pl : planes) {
            double dmn, dmx;
            plane_range(fr, *pl, dmn, dmx);
            if (dmn >= -0.01 && dmx > 0.05) {
                keep = true;
                break;
            }
            if (keep_dups && dmx <= 0.05 && dmn >= -0.05 && dot(pl->n, fn) > 0.99) {
                keep = true;
                break;
            }
        }
        if (keep) {
            next.push_back(fr);
            continue;
        }
        // overlaps it: keep the parts in front of its planes, drop the rest
        touched = true;
        inside = fr;
        for (const Plane *pl : planes) {
            double dmn, dmx;
            plane_range(inside, *pl, dmn, dmx);
            if ((dmx <= 0.05 && dmn >= -0.05) || dmx <= 0.01) {
                continue;   // on this plane (looking into the volume, or a dropped duplicate) or behind it
            }
            split_poly(inside, *pl, 0.01, front, back);
            if (!front.empty()) {
                next.push_back(front);
            }
            inside.swap(back);
            if (inside.empty()) {
                break;
            }
        }
    }
    frags.swap(next);
    return touched;
}

struct P2 {
    double u, v;
};

double cross2(const P2 &o, const P2 &a, const P2 &b)
{
    return (a.u - o.u) * (b.v - o.v) - (a.v - o.v) * (b.u - o.u);
}

// convex hull, counter-clockwise, collinear points dropped (Andrew's monotone chain)
void hull2(std::vector<P2> p, std::vector<P2> &h)
{
    std::sort(p.begin(), p.end(), [](const P2 &a, const P2 &b) { return a.u < b.u || (a.u == b.u && a.v < b.v); });
    h.assign(2 * p.size() + 1, P2{0, 0});
    size_t k = 0;
    for (size_t i = 0; i < p.size(); i++) {
        while (k >= 2 && cross2(h[k - 2], h[k - 1], p[i]) <= 1e-9) {
            k--;
        }
        h[k++] = p[i];
    }
    for (size_t i = p.size() - 1, t = k + 1; i > 0; i--) {
        while (k >= t && cross2(h[k - 2], h[k - 1], p[i - 1]) <= 1e-9) {
            k--;
        }
        h[k++] = p[i - 1];
    }
    h.resize(k > 1 ? k - 1 : k);
}

double area2(const std::vector<P2> &h)
{
    double a = 0.0;
    for (size_t i = 0; i < h.size(); i++) {
        const P2 &p = h[i], &q = h[(i + 1) % h.size()];
        a += p.u * q.v - q.u * p.v;
    }
    return 0.5 * a;
}

// a plane's 2D chart: drop the normal's largest axis (to2), and back onto the plane (to3)
struct Chart {
    D3 n;
    double d;
    int drop;
    Chart(const D3 &fn, double dd) : n(fn), d(dd)
    {
        double ax = std::fabs(fn.x), ay = std::fabs(fn.y), az = std::fabs(fn.z);
        drop = (ax >= ay && ax >= az) ? 0 : (ay >= az ? 1 : 2);
    }
    P2 to2(const D3 &p) const { return drop == 0 ? P2{p.y, p.z} : drop == 1 ? P2{p.x, p.z} : P2{p.x, p.y}; }
    D3 to3(const P2 &q) const
    {
        if (drop == 0) {
            return D3{(d - n.y * q.u - n.z * q.v) / n.x, q.u, q.v};
        }
        if (drop == 1) {
            return D3{q.u, (d - n.x * q.u - n.z * q.v) / n.y, q.v};
        }
        return D3{q.u, q.v, (d - n.x * q.u - n.y * q.v) / n.z};
    }
};

// merges convex pieces of one plane (normal fn) whose union is convex (pieces left by cutting, e.g. a wall beside
// stairs once the stairs are a ramp); at most `limit` pieces are looked at
void merge_coplanar(std::vector<std::vector<D3>> &frags, const D3 &fn, size_t limit)
{
    if (frags.size() < 2 || frags.size() > limit) {
        return;
    }
    Chart ch(fn, dot(fn, frags[0][0]));
    std::vector<std::vector<P2>> p2(frags.size());
    std::vector<double> area(frags.size());
    std::vector<bool> merged(frags.size(), false);
    for (size_t i = 0; i < frags.size(); i++) {
        for (const D3 &p : frags[i]) {
            p2[i].push_back(ch.to2(p));
        }
        area[i] = std::fabs(area2(p2[i]));
    }
    std::vector<P2> pts, h;
    bool changed = true;
    while (changed) {
        changed = false;
        for (size_t i = 0; i < p2.size(); i++) {
            if (merged[i]) {
                continue;
            }
            for (size_t j = i + 1; j < p2.size(); j++) {
                if (merged[j]) {
                    continue;
                }
                pts = p2[i];
                pts.insert(pts.end(), p2[j].begin(), p2[j].end());
                hull2(pts, h);
                double ah = std::fabs(area2(h)), sum = area[i] + area[j];
                if (h.size() >= 3 && std::fabs(ah - sum) <= 1e-7 * sum + 1e-4) {
                    p2[i] = h;   // touching along an edge, their union convex
                    area[i] = ah;
                    merged[j] = true;
                    changed = true;
                }
            }
        }
    }
    std::vector<std::vector<D3>> out;
    for (size_t i = 0; i < p2.size(); i++) {
        if (merged[i]) {
            continue;
        }
        std::vector<D3> w;
        for (const P2 &q : p2[i]) {
            w.push_back(ch.to3(q));
        }
        if (dot(newell(w), fn) < 0.0) {
            std::reverse(w.begin(), w.end());
        }
        out.push_back(std::move(w));
    }
    frags.swap(out);
}

// cuts a convex polygon (normal fn) into cells no longer than e: strips across its longest edge's direction, then
// across the strips (diag_maps' tess_tri for polygons): well-shaped pieces instead of the needles that halving the
// longest edge makes. Returns false (out untouched) when the polygon is short enough already.
bool tessellate(const std::vector<D3> &poly, const D3 &fn, double e, std::vector<std::vector<D3>> &out)
{
    if (poly.size() < 3 || !(e > 0.0)) {
        return false;
    }
    size_t k = 0;
    double best = -1.0;
    for (size_t i = 0; i < poly.size(); i++) {
        double l = length(poly[(i + 1) % poly.size()] - poly[i]);
        if (l > best) {
            best = l;
            k = i;
        }
    }
    if (!(best > 1e-6)) {
        return false;
    }
    D3 d1 = (poly[(k + 1) % poly.size()] - poly[k]) * (1.0 / best);
    D3 d2 = cross(fn, d1);
    double l2 = length(d2);
    if (!(l2 > 1e-9)) {
        return false;
    }
    d2 = d2 * (1.0 / l2);
    auto range = [](const std::vector<D3> &p, const D3 &d, double &mn, double &mx) {
        mn = 1e300;
        mx = -1e300;
        for (const D3 &v : p) {
            double t = dot(d, v);
            mn = std::min(mn, t);
            mx = std::max(mx, t);
        }
    };
    double mn1, mx1, mn2, mx2;
    range(poly, d1, mn1, mx1);
    range(poly, d2, mn2, mx2);
    if (mx1 - mn1 <= e && mx2 - mn2 <= e) {
        return false;
    }
    int n1 = std::max(1, (int)std::ceil((mx1 - mn1) / e - 1e-9));
    if (n1 > 4096) {
        return false;   // a damaged file: kept whole
    }
    std::vector<D3> rest = poly, strip, front, back, r2, cell;
    for (int i = 1; i <= n1; i++) {
        if (i < n1) {
            Plane pl{d1, mn1 + (mx1 - mn1) * i / n1, true};
            split_poly(rest, pl, 1e-7, front, back);
            strip = back;
            rest = front;
        } else {
            strip = rest;
        }
        if (strip.size() < 3) {
            continue;
        }
        double s0, s1;
        range(strip, d2, s0, s1);
        int n2 = std::max(1, (int)std::ceil((s1 - s0) / e - 1e-9));
        if (n2 > 4096) {
            n2 = 4096;
        }
        r2 = strip;
        for (int j = 1; j <= n2; j++) {
            if (j < n2) {
                Plane pl{d2, s0 + (s1 - s0) * j / n2, true};
                split_poly(r2, pl, 1e-7, front, back);
                cell = back;
                r2 = front;
            } else {
                cell = r2;
            }
            dedupe(cell);
            if (cell.size() >= 3) {
                out.push_back(cell);
            }
            if (r2.size() < 3) {
                break;
            }
        }
        if (rest.size() < 3) {
            break;
        }
    }
    return true;
}

struct TriSink {
    std::vector<sa1_collision_tri> *out;
    uint32_t max;
    bool overflow = false;
    uint32_t out_of_range = 0;
    std::vector<uint32_t> *tags = nullptr;   // parallel to out: each triangle's surface-type tag (surface_tag)
    uint32_t tagged = 0;
    // the guard (BspWorldOptions::guard, 0.9.2): a triangle with a corner outside lo..hi is left out (the kill plane
    // excepted)
    bool bounded = false;
    D3 lo{0, 0, 0}, hi{0, 0, 0};
    uint32_t outside = 0;
    void bound(const float mins[3], const float maxs[3], double margin)
    {
        bounded = true;
        lo = D3{(double)mins[0] - margin, (double)mins[1] - margin, (double)mins[2] - margin};
        hi = D3{(double)maxs[0] + margin, (double)maxs[1] + margin, (double)maxs[2] + margin};
    }
    bool add(const D3 &a, const D3 &b, const D3 &c, uint32_t surface, uint32_t tag = kNoSurfaceTag)
    {
        for (const D3 *p : {&a, &b, &c}) {
            if (!(std::fabs(p->x) <= 65536.0 && std::fabs(p->y) <= 65536.0 && std::fabs(p->z) <= 65536.0)) {
                out_of_range++;   // non-finite or beyond any map (a damaged file): left out
                return false;
            }
        }
        if (bounded && !(surface & SA1_SURFACE_KILL)) {
            for (const D3 *p : {&a, &b, &c}) {
                if (p->x < lo.x || p->y < lo.y || p->z < lo.z || p->x > hi.x || p->y > hi.y || p->z > hi.z) {
                    outside++;   // nobody can reach it (a prop in the void, a face through the whole map)
                    return false;
                }
            }
        }
        D3 cr = cross(b - a, c - a);
        if (length(cr) < 1e-3) {
            return false;   // degenerate (area below 0.0005 square units)
        }
        if (out->size() >= max) {
            overflow = true;
            return false;
        }
        sa1_collision_tri t;
        const D3 *v[3] = {&a, &b, &c};
        for (int k = 0; k < 3; k++) {
            t.v[k][0] = (float)v[k]->x;
            t.v[k][1] = (float)v[k]->y;
            t.v[k][2] = (float)v[k]->z;
        }
        t.surface = surface;
        out->push_back(t);
        if (tags) {
            tags->push_back(tag);
        }
        tagged += tag != kNoSurfaceTag;
        return true;
    }
};

}  // namespace

const std::string *BspEntity::get(const char *key) const
{
    for (const auto &p : kv) {
        if (p.first == key) {
            return &p.second;
        }
    }
    return nullptr;
}

bool BspEntity::get_vec3(const char *key, float out[3]) const
{
    const std::string *v = get(key);
    if (!v) {
        return false;
    }
    float a, b, c;
    if (std::sscanf(v->c_str(), "%f %f %f", &a, &b, &c) != 3 || !std::isfinite(a) || !std::isfinite(b) ||
        !std::isfinite(c)) {
        return false;
    }
    out[0] = a;
    out[1] = b;
    out[2] = c;
    return true;
}

bool Bsp::open(ByteSource &src, std::string &err)
{
    src_ = nullptr;
    data_.reset();
    uint8_t h[1036];
    if (src.size() < sizeof h || !src.read(0, h, sizeof h)) {
        err = "not a BSP file (too short)";
        return false;
    }
    if (std::memcmp(h, "VBSP", 4) != 0) {
        err = "not a Source BSP file (no VBSP header)";
        return false;
    }
    std::memcpy(&version_, h + 4, 4);
    if (version_ != 19 && version_ != 20) {
        err = format("BSP version %d is not supported (Garry's Mod maps are version 19 or 20)", (int)version_);
        return false;
    }
    for (int i = 0; i < 64; i++) {
        const uint8_t *l = h + 8 + 16 * i;
        std::memcpy(&lumps_[i].ofs, l, 4);
        std::memcpy(&lumps_[i].len, l + 4, 4);
        std::memcpy(&lumps_[i].version, l + 8, 4);
        std::memcpy(&lumps_[i].fourcc, l + 12, 4);
    }
    std::memcpy(&revision_, h + 8 + 16 * 64, 4);
    src_ = &src;
    return true;
}

bool Bsp::lump_range(int index, uint64_t &ofs, uint64_t &len) const
{
    ofs = len = 0;
    if (index < 0 || index >= 64 || lumps_[index].ofs < 0 || lumps_[index].len < 0) {
        return false;
    }
    ofs = (uint64_t)lumps_[index].ofs;
    len = (uint64_t)lumps_[index].len;
    return true;
}

bool Bsp::lump_raw(int index, size_t elem, size_t max_count, std::vector<uint8_t> &out, size_t &count,
                   std::string &err)
{
    out.clear();
    count = 0;
    if (!src_ || index < 0 || index >= 64 || elem == 0) {
        err = "internal: bad lump request";
        return false;
    }
    const Lump &l = lumps_[index];
    if (l.len == 0) {
        return true;
    }
    if (l.ofs < 0 || l.len < 0 || (uint64_t)l.ofs + (uint64_t)l.len > src_->size()) {
        err = format("lump %d lies outside the file", index);
        return false;
    }
    if (l.fourcc != 0) {
        err = format("lump %d is LZMA-compressed (bspzip -repack); compressed maps are not supported yet", index);
        return false;
    }
    if ((size_t)l.len % elem != 0) {
        err = format("lump %d has a size (%d) that is not a multiple of %u", index, (int)l.len, (unsigned)elem);
        return false;
    }
    count = (size_t)l.len / elem;
    if (count > max_count) {
        err = format("lump %d has %u entries (limit %u)", index, (unsigned)count, (unsigned)max_count);
        count = 0;
        return false;
    }
    out.resize((size_t)l.len);
    if (!src_->read((uint64_t)l.ofs, out.data(), out.size())) {
        err = format("cannot read lump %d", index);
        out.clear();
        count = 0;
        return false;
    }
    return true;
}

bool Bsp::sprp_range(uint64_t &ofs, uint64_t &len, uint16_t &version, bool &compressed, std::string &err)
{
    ofs = len = 0;
    version = 0;
    compressed = false;
    std::vector<uint8_t> raw;
    size_t n = 0;
    if (!lump_raw(LUMP_GAME_LUMP, 1, 1u << 20, raw, n, err)) {
        return false;
    }
    if (n < 4) {
        return true;   // no game lumps
    }
    int32_t count = 0;
    std::memcpy(&count, raw.data(), 4);
    if (count < 0 || (size_t)count > (n - 4) / 16) {
        err = "the game lump directory is damaged";
        return false;
    }
    for (int32_t i = 0; i < count; i++) {
        const uint8_t *e = raw.data() + 4 + 16 * (size_t)i;
        uint32_t id;
        uint16_t fl, ver;
        int32_t fo, flen;
        std::memcpy(&id, e, 4);
        std::memcpy(&fl, e + 4, 2);
        std::memcpy(&ver, e + 6, 2);
        std::memcpy(&fo, e + 8, 4);
        std::memcpy(&flen, e + 12, 4);
        if (id != kSprpId) {
            continue;
        }
        if (fo < 0 || flen < 0 || (uint64_t)fo + (uint64_t)flen > src_->size()) {
            err = "the static prop lump lies outside the file";
            return false;
        }
        ofs = (uint64_t)fo;
        len = (uint64_t)flen;
        version = ver;
        compressed = (fl & 1u) != 0;
        return true;
    }
    return true;
}

void Bsp::needed_ranges(std::vector<std::pair<uint64_t, uint64_t>> &out)
{
    out.clear();
    if (!src_) {
        return;
    }
    for (int i : kNeededLumps) {
        uint64_t o, l;
        if (lump_range(i, o, l) && l > 0 && o + l <= src_->size()) {
            out.push_back({o, l});
        }
    }
    uint64_t o = 0, l = 0;
    uint16_t ver = 0;
    bool comp = false;
    std::string e;
    if (sprp_range(o, l, ver, comp, e) && l > 0 && !comp) {
        out.push_back({o, l});
    }
}

struct BspData {
    std::vector<uint8_t> planes_raw, verts_raw, edges_raw, surfedges_raw, faces_raw, texinfo_raw, nodes_raw,
        leafs_raw, models_raw, leafbrushes_raw, brushes_raw, sides_raw, dispinfo_raw, dispverts_raw, disptris_raw,
        texdata_raw, tdstr_data_raw, tdstr_table_raw;
    size_t nplanes = 0, nverts = 0, nedges = 0, nsurfedges = 0, nfaces = 0, ntexinfo = 0, nnodes = 0, nleafs = 0,
           nmodels = 0, nleafbrushes = 0, nbrushes = 0, nsides = 0, ndispinfo = 0, ndispverts = 0, ndisptris = 0,
           ntexdata = 0, ntdstr_data = 0, ntdstr_table = 0;
    size_t leaf_stride = 32;
    std::vector<Plane> planes;

    const DVertex *verts() const { return (const DVertex *)verts_raw.data(); }
    const DEdge *edges() const { return (const DEdge *)edges_raw.data(); }
    const int32_t *surfedges() const { return (const int32_t *)surfedges_raw.data(); }
    const DFace *faces() const { return (const DFace *)faces_raw.data(); }
    const DTexinfo *texinfo() const { return (const DTexinfo *)texinfo_raw.data(); }
    const DNode *nodes() const { return (const DNode *)nodes_raw.data(); }
    const DModel *models() const { return (const DModel *)models_raw.data(); }
    const uint16_t *leafbrushes() const { return (const uint16_t *)leafbrushes_raw.data(); }
    const DBrush *brushes() const { return (const DBrush *)brushes_raw.data(); }
    const DBrushSide *sides() const { return (const DBrushSide *)sides_raw.data(); }
    const DDispInfo *dispinfo() const { return (const DDispInfo *)dispinfo_raw.data(); }
    const DDispVert *dispverts() const { return (const DDispVert *)dispverts_raw.data(); }
    const uint16_t *disptris() const { return (const uint16_t *)disptris_raw.data(); }
    const DTexdata *texdata() const { return (const DTexdata *)texdata_raw.data(); }
    const int32_t *tdstr_table() const { return (const int32_t *)tdstr_table_raw.data(); }

    // the TEXDATA index of a texinfo (-1: none or out of range)
    int32_t texinfo_texdata(int32_t ti) const
    {
        if (ti < 0 || (size_t)ti >= ntexinfo) {
            return -1;
        }
        int32_t td = texinfo()[ti].texdata;
        return (td >= 0 && (size_t)td < ntexdata) ? td : -1;
    }
    // the surface-type slot of a texinfo's material (sp2: its $surfaceprop2 slot, kNoSurface when there is none)
    uint16_t texinfo_slot(const BspSurfaceSlots *slots, int32_t ti, bool sp2 = false) const
    {
        if (!slots) {
            return kNoSurface;
        }
        int32_t td = texinfo_texdata(ti);
        const std::vector<uint16_t> &v = sp2 ? slots->sp2 : slots->sp;
        return (td >= 0 && (size_t)td < v.size()) ? v[(size_t)td] : kNoSurface;
    }
    const DLeafHead *leaf(size_t i) const { return (const DLeafHead *)(leafs_raw.data() + i * leaf_stride); }

    bool face_corners(size_t f, D3 c[4]) const
    {
        if (f >= nfaces) {
            return false;
        }
        const DFace &fc = faces()[f];
        if (fc.numedges != 4 || fc.firstedge < 0 || (size_t)fc.firstedge + 4 > nsurfedges) {
            return false;
        }
        for (int e = 0; e < 4; e++) {
            int32_t se = surfedges()[fc.firstedge + e];
            if (se == INT32_MIN) {
                return false;
            }
            uint32_t ei = (uint32_t)(se < 0 ? -se : se);
            if (ei >= nedges) {
                return false;
            }
            uint32_t vi = edges()[ei].v[se < 0 ? 1 : 0];
            if (vi >= nverts || !finite3(verts()[vi].p)) {
                return false;
            }
            c[e] = d3(verts()[vi].p);
        }
        return true;
    }

    // the n x n grid of displacement d: row r runs from corner 0 towards corner 1, column c from the
    // edge 0-1 towards the edge 3-2 (Valve's CCoreDispInfo order); corner 0 is the base-face corner nearest to
    // startPosition. normal: the base face's PLANE normal (not turned round by the face's side flag); side: the flag.
    // false: malformed (skipped).
    bool disp_grid(size_t d, bool transpose, uint32_t &n_out, std::vector<D3> &pts, D3 corners_out[4], D3 &normal,
                   bool &side) const
    {
        const DDispInfo &di = dispinfo()[d];
        if (di.power < 1 || di.power > 4) {
            return false;
        }
        D3 c[4];
        if (!face_corners(di.map_face, c) || !finite3(di.start)) {
            return false;
        }
        const DFace &fc = faces()[di.map_face];
        if (fc.planenum >= nplanes || !planes[fc.planenum].ok) {
            return false;
        }
        normal = planes[fc.planenum].n;
        side = fc.side != 0;
        D3 sp = d3(di.start);
        int first = 0;
        double best = 1e300;
        for (int k = 0; k < 4; k++) {
            double dd = length(c[k] - sp);
            if (dd < best) {
                best = dd;
                first = k;
            }
        }
        D3 r[4];
        for (int k = 0; k < 4; k++) {
            r[k] = c[(first + k) & 3];
        }
        if (transpose) {
            D3 t = r[1];
            r[1] = r[3];
            r[3] = t;
        }
        uint32_t n = (1u << di.power) + 1u;
        if (di.vert_start < 0 || (size_t)di.vert_start + (size_t)n * n > ndispverts) {
            return false;
        }
        pts.resize((size_t)n * n);
        for (uint32_t row = 0; row < n; row++) {
            double t = (double)row / (double)(n - 1);
            D3 a = lerp(r[0], r[1], t);
            D3 b = lerp(r[3], r[2], t);
            for (uint32_t col = 0; col < n; col++) {
                double s = (double)col / (double)(n - 1);
                const DDispVert &v = dispverts()[(size_t)di.vert_start + (size_t)row * n + col];
                if (!finite3(v.vec) || !std::isfinite(v.dist) || std::fabs(v.dist) > kMaxCoord) {
                    return false;
                }
                pts[(size_t)row * n + col] = lerp(a, b, s) + d3(v.vec) * (double)v.dist;
            }
        }
        for (int k = 0; k < 4; k++) {
            corners_out[k] = r[k];
        }
        n_out = n;
        return true;
    }

    // the brushes in the leaves reachable from a model's head node (iterative, every node once)
    void model_brushes(int32_t model, std::vector<uint8_t> &mark) const
    {
        mark.assign(nbrushes, 0);
        if (model < 0 || (size_t)model >= nmodels) {
            return;
        }
        std::vector<uint8_t> node_seen(nnodes, 0);
        std::vector<int32_t> stack;
        stack.push_back(models()[model].headnode);
        while (!stack.empty()) {
            int32_t c = stack.back();
            stack.pop_back();
            if (c >= 0) {
                if ((size_t)c >= nnodes || node_seen[(size_t)c]) {
                    continue;
                }
                node_seen[(size_t)c] = 1;
                stack.push_back(nodes()[c].children[0]);
                stack.push_back(nodes()[c].children[1]);
            } else {
                size_t lf_i = (size_t)(-1 - (int64_t)c);
                if (lf_i >= nleafs) {
                    continue;
                }
                const DLeafHead *lf = leaf(lf_i);
                size_t first = lf->firstleafbrush, num = lf->numleafbrushes;
                for (size_t i = first; i < first + num && i < nleafbrushes; i++) {
                    uint16_t b = leafbrushes()[i];
                    if (b < nbrushes) {
                        mark[b] = 1;
                    }
                }
            }
        }
    }
};

bool load_bsp_data(Bsp &bsp, BspData &w, std::string &err)
{
    if (!bsp.lump_raw(LUMP_PLANES, sizeof(DPlane), 1u << 20, w.planes_raw, w.nplanes, err) ||
        !bsp.lump_raw(LUMP_VERTEXES, sizeof(DVertex), 1u << 20, w.verts_raw, w.nverts, err) ||
        !bsp.lump_raw(LUMP_EDGES, sizeof(DEdge), 1u << 22, w.edges_raw, w.nedges, err) ||
        !bsp.lump_raw(LUMP_SURFEDGES, 4, 1u << 23, w.surfedges_raw, w.nsurfedges, err) ||
        !bsp.lump_raw(LUMP_FACES, sizeof(DFace), 1u << 20, w.faces_raw, w.nfaces, err) ||
        !bsp.lump_raw(LUMP_TEXINFO, sizeof(DTexinfo), 1u << 20, w.texinfo_raw, w.ntexinfo, err) ||
        !bsp.lump_raw(LUMP_NODES, sizeof(DNode), 1u << 20, w.nodes_raw, w.nnodes, err) ||
        !bsp.lump_raw(LUMP_MODELS, sizeof(DModel), 1u << 16, w.models_raw, w.nmodels, err) ||
        !bsp.lump_raw(LUMP_LEAFBRUSHES, 2, 1u << 20, w.leafbrushes_raw, w.nleafbrushes, err) ||
        !bsp.lump_raw(LUMP_BRUSHES, sizeof(DBrush), 1u << 20, w.brushes_raw, w.nbrushes, err) ||
        !bsp.lump_raw(LUMP_BRUSHSIDES, sizeof(DBrushSide), 1u << 22, w.sides_raw, w.nsides, err) ||
        !bsp.lump_raw(LUMP_DISPINFO, sizeof(DDispInfo), 1u << 18, w.dispinfo_raw, w.ndispinfo, err) ||
        !bsp.lump_raw(LUMP_DISP_VERTS, sizeof(DDispVert), 1u << 26, w.dispverts_raw, w.ndispverts, err)) {
        return false;
    }
    // the displacements' triangle tags are optional (the winding check falls back to the plane normal)
    std::string terr;
    if (!bsp.lump_raw(LUMP_DISP_TRIS, 2, 1u << 26, w.disptris_raw, w.ndisptris, terr)) {
        w.disptris_raw.clear();
        w.ndisptris = 0;
    }
    // the material names are optional too (without them no surface types: plain land, as before 0.8)
    if (!bsp.lump_raw(LUMP_TEXDATA, sizeof(DTexdata), 1u << 16, w.texdata_raw, w.ntexdata, terr) ||
        !bsp.lump_raw(LUMP_TEXDATA_STRING_TABLE, 4, 1u << 16, w.tdstr_table_raw, w.ntdstr_table, terr) ||
        !bsp.lump_raw(LUMP_TEXDATA_STRING_DATA, 1, 1u << 22, w.tdstr_data_raw, w.ntdstr_data, terr)) {
        w.texdata_raw.clear();
        w.tdstr_table_raw.clear();
        w.tdstr_data_raw.clear();
        w.ntexdata = w.ntdstr_table = w.ntdstr_data = 0;
    }
    // leaves: 56 bytes in lump version 0 (with the ambient light cube), 32 bytes in version 1
    std::vector<uint8_t> tmp;
    size_t nbytes = 0;
    if (!bsp.lump_raw(LUMP_LEAFS, 1, 1u << 26, tmp, nbytes, err)) {
        return false;
    }
    size_t len = tmp.size(), stride;
    if (len % 32 == 0 && len % 56 == 0) {
        stride = bsp.version() == 19 ? 56 : 32;
    } else if (len % 56 == 0) {
        stride = 56;
    } else if (len % 32 == 0) {
        stride = 32;
    } else {
        err = "the leaf lump has an unexpected size";
        return false;
    }
    w.leafs_raw.swap(tmp);
    w.leaf_stride = stride;
    w.nleafs = len / stride;
    if (w.nmodels == 0) {
        err = "the map has no world model";
        return false;
    }
    w.planes.resize(w.nplanes);
    const DPlane *pl = (const DPlane *)w.planes_raw.data();
    for (size_t i = 0; i < w.nplanes; i++) {
        Plane &p = w.planes[i];
        p.ok = finite3(pl[i].n) && std::isfinite(pl[i].d) && std::fabs(pl[i].d) < kMaxCoord;
        p.n = d3(pl[i].n);
        p.d = pl[i].d;
        double l = length(p.n);
        if (!p.ok || l < 0.5 || l > 1.5) {
            p.ok = false;
            continue;
        }
        p.n = p.n * (1.0 / l);
        p.d = p.d / l;
    }
    return true;
}

bool Bsp::load(std::string &err)
{
    if (data_) {
        return true;
    }
    if (!src_) {
        err = "no BSP opened";
        return false;
    }
    std::shared_ptr<BspData> d = std::make_shared<BspData>();
    if (!load_bsp_data(*this, *d, err)) {
        return false;
    }
    data_ = d;
    return true;
}

int32_t Bsp::model_count()
{
    std::string e;
    return load(e) ? (int32_t)data_->nmodels : 0;
}

bool Bsp::model_bounds(int32_t model, float mins[3], float maxs[3])
{
    std::string e;
    if (!load(e) || model < 0 || (size_t)model >= data_->nmodels) {
        return false;
    }
    const DModel &m = data_->models()[model];
    if (!finite3(m.mins) || !finite3(m.maxs)) {
        return false;
    }
    for (int k = 0; k < 3; k++) {
        mins[k] = m.mins[k];
        maxs[k] = m.maxs[k];
    }
    return true;
}

bool Bsp::materials(BspMaterials &out, std::string &err)
{
    out = BspMaterials();
    if (!load(err)) {
        return false;
    }
    const BspData &w = *data_;
    out.texdata = (uint32_t)w.ntexdata;
    out.texdata_name.assign(w.ntexdata, -1);
    std::map<std::string, int32_t> index;
    const char *sd = (const char *)w.tdstr_data_raw.data();
    for (size_t i = 0; i < w.ntexdata; i++) {
        int32_t si = w.texdata()[i].name_string;
        if (si < 0 || (size_t)si >= w.ntdstr_table) {
            out.bad++;
            continue;
        }
        int32_t o = w.tdstr_table()[si];
        if (o < 0 || (size_t)o >= w.ntdstr_data) {
            out.bad++;
            continue;
        }
        size_t e = (size_t)o;
        while (e < w.ntdstr_data && sd[e] != 0 && e - (size_t)o <= 256) {
            e++;
        }
        if (e >= w.ntdstr_data || sd[e] != 0) {
            out.bad++;   // not terminated within the lump, or longer than 256 bytes
            continue;
        }
        std::string name(sd + o, e - (size_t)o);
        bool ok = !name.empty() && name.find("..") == std::string::npos && name.find(':') == std::string::npos;
        for (char &c : name) {
            if (c == '\\') {
                c = '/';
            } else if (c >= 'A' && c <= 'Z') {
                c = (char)(c + 32);
            }
            ok = ok && (unsigned char)c >= 0x20 && (unsigned char)c <= 0x7E;
        }
        while (ok && !name.empty() && name[0] == '/') {
            name.erase(0, 1);
        }
        if (!ok || name.empty() || name.size() > 180) {
            out.bad++;
            continue;
        }
        auto it = index.find(name);
        if (it == index.end()) {
            it = index.emplace(name, (int32_t)out.names.size()).first;
            out.names.push_back(name);
        }
        out.texdata_name[i] = it->second;
    }
    // the materials a collision face uses: sides of solid / water brushes, displacements
    out.used.assign(out.names.size(), 0);
    auto use = [&](int32_t ti) {
        int32_t td = w.texinfo_texdata(ti);
        if (td >= 0 && out.texdata_name[(size_t)td] >= 0) {
            out.used[(size_t)out.texdata_name[(size_t)td]] = 1;
        }
    };
    const uint32_t solid_or_water = CONTENTS_SOLID | CONTENTS_WINDOW | CONTENTS_GRATE | CONTENTS_MOVEABLE |
                                    CONTENTS_PLAYERCLIP | CONTENTS_WATER | CONTENTS_SLIME;
    for (size_t b = 0; b < w.nbrushes; b++) {
        const DBrush &br = w.brushes()[b];
        if (!((uint32_t)br.contents & solid_or_water) || br.firstside < 0 || br.numsides < 1 || br.numsides > 256 ||
            (size_t)br.firstside + (size_t)br.numsides > w.nsides) {
            continue;
        }
        for (int32_t k = 0; k < br.numsides; k++) {
            const DBrushSide &bs = w.sides()[br.firstside + k];
            if (!bs.bevel) {
                use(bs.texinfo);
            }
        }
    }
    for (size_t d = 0; d < w.ndispinfo; d++) {
        uint16_t f = w.dispinfo()[d].map_face;
        if (f < w.nfaces) {
            use(w.faces()[f].texinfo);
        }
    }
    return true;
}

namespace {

// ---- solids: the convex volumes whose faces become collision -------------------------------------------------------
struct SFace {
    std::vector<D3> poly;
    D3 n, lo, hi;
    uint32_t surface;
    int32_t flags;
    bool sky, clip_only, drop;
    uint16_t sp = kNoSurface, sp_also = kNoSurface;   // surface-type slots (bsp.hpp surface_tag; thin walls: also)
    bool one_way = false;   // 0.9.3: a near-horizontal underside of a one-way solid (one_way_solid): cross_one_way keeps
                            // its pieces front-only unless they are low ceilings
    bool curved = false;    // 0.9.3: part of a curved surface (detect_curved; surface has SA1_SURFACE_CURVED)
};

struct FaceCounts {
    uint32_t faces = 0, degenerate = 0, bevel = 0;
};

struct Solid {
    std::vector<Plane> planes;      // the volume, outward (bevels left out)
    std::vector<SFace> faces;
    D3 lo{0, 0, 0}, hi{0, 0, 0};
    uint8_t kind = 1;               // 1 brush (solid), 2 water, 3 an extra convex solid (a hull)
    bool closed = false;            // every side made a face within range: a closed convex volume
    bool clipper = false;           // cuts the faces of the other solids (remove_hidden)
    bool one_way = false;           // a down face was left out or made a one-way candidate (one_way_max)
    bool curved = false;            // 0.9.3: owns a face of a curved surface (detect_curved)
    int32_t brush = -1;             // 0.9.3: the BSP brush it was made of (brush_rules rebuilds a thickened floor)
    FaceCounts fc;                  // brush_faces' counts (stats, added by brush_rules)
};

void face_bounds(SFace &f)
{
    f.lo = f.hi = f.poly[0];
    for (const D3 &p : f.poly) {
        f.lo = dmin(f.lo, p);
        f.hi = dmax(f.hi, p);
    }
}

// a brush's faces from its side planes sp (one per side; sp[s].ok): every side clipped by the others (bevel planes
// only touch the brush: they make no face and clip nothing, and would undo a thickened floor)
void brush_faces(const BspData &w, const DBrush &br, const std::vector<Plane> &sp, uint32_t base, bool clip_only,
                 uint8_t kind, Solid &S, FaceCounts &fc, const BspSurfaceSlots *slots)
{
    fc = FaceCounts();
    S.faces.clear();
    S.planes.clear();
    S.kind = kind;
    bool closed = true;
    D3 lo{1e300, 1e300, 1e300}, hi{-1e300, -1e300, -1e300};
    std::vector<D3> poly, tmp;
    for (int32_t s = 0; s < br.numsides; s++) {
        const DBrushSide &sd = w.sides()[br.firstside + s];
        if (!sp[(size_t)s].ok) {
            fc.degenerate++;
            closed = false;
            continue;
        }
        if (sd.bevel) {
            fc.bevel++;
            continue;
        }
        const Plane &pl = sp[(size_t)s];
        S.planes.push_back(pl);
        base_winding(pl, poly);
        for (int32_t o = 0; o < br.numsides && poly.size() >= 3; o++) {
            if (o == s) {
                continue;
            }
            const DBrushSide &so = w.sides()[br.firstside + o];
            if (!sp[(size_t)o].ok || so.planenum == sd.planenum || so.bevel) {
                continue;
            }
            clip_back(poly, sp[(size_t)o], 0.01, tmp);
        }
        dedupe(poly);
        if (poly.size() < 3) {
            fc.degenerate++;
            continue;
        }
        bool out_of_range = false;
        for (const D3 &p : poly) {
            if (std::fabs(p.x) > 65536.0 || std::fabs(p.y) > 65536.0 || std::fabs(p.z) > 65536.0) {
                out_of_range = true;   // an open brush (missing sides): not a closed solid
            }
        }
        if (out_of_range) {
            fc.degenerate++;
            closed = false;
            continue;
        }
        if (dot(newell(poly), pl.n) < 0.0) {
            std::reverse(poly.begin(), poly.end());
        }
        SFace f;
        f.surface = base;
        f.flags = 0;
        if (sd.texinfo >= 0 && (size_t)sd.texinfo < w.ntexinfo) {
            f.flags = w.texinfo()[sd.texinfo].flags;
        }
        f.sky = (f.flags & (SURF_SKY | SURF_SKY2D)) != 0;
        if (f.sky && kind == 1) {
            f.surface |= SA1_SURFACE_NO_CLIMB;
        }
        f.clip_only = clip_only;
        f.drop = false;
        f.sp = w.texinfo_slot(slots, sd.texinfo);
        f.n = pl.n;
        f.poly.swap(poly);
        face_bounds(f);
        lo = dmin(lo, f.lo);
        hi = dmax(hi, f.hi);
        fc.faces++;
        S.faces.push_back(std::move(f));
    }
    S.closed = closed && S.faces.size() >= 4;
    S.clipper = kind == 1 && S.closed;
    S.lo = lo;
    S.hi = hi;
}

// one-way thin platform (one_way_max): the down faces (n.z <= -0.5) under which the solid's own top - the lowest of
// its upward planes over the point - is walkable and at most one_way_max above, at the face's centre and near each
// of its corners (10 % in, so a bevelled rim does not count). Returns the faces selected. 0.9.3 (one_way_front_only,
// gsa1_091b_ceiling.md FIX-C3 with its Review R.5.1 a/b/d): a near-horizontal one (n.z <= kFrontOnlyNz) is only
// marked (SFace::one_way) and cross_one_way decides (a low ceiling is left out, otherwise its pieces stay front-only);
// a steeper one is left out as before; a curved face (detect_curved) is never selected. The solid counts as one-way
// either way (S.one_way: it is not thickened).
uint32_t one_way_solid(Solid &S, const BspWorldOptions &opt, uint32_t *curved_skipped = nullptr)
{
    if (!(opt.one_way_max > 0.0f) || S.kind == 2 || !S.closed) {
        return 0;
    }
    const double D = (double)opt.one_way_max, walk = (double)opt.one_way_walkable;
    uint32_t dropped = 0;
    std::vector<D3> samples;
    for (SFace &f : S.faces) {
        if (f.n.z > -0.5) {
            continue;
        }
        if (f.curved) {
            if (curved_skipped) {
                (*curved_skipped)++;
            }
            continue;   // a loop's ceiling segment: never one-way (gsa1_091a_loop.md 5.2)
        }
        D3 c = centroid(f.poly);
        samples.clear();
        samples.push_back(c);
        for (const D3 &v : f.poly) {
            samples.push_back(v + (c - v) * 0.1);
        }
        bool ok = true;
        for (const D3 &p : samples) {
            double top = 1e300;
            bool top_walk = false;
            for (const Plane &pl : S.planes) {
                if (pl.n.z <= 0.05) {
                    continue;
                }
                double z = (pl.d - pl.n.x * p.x - pl.n.y * p.y) / pl.n.z;
                if (z < top) {
                    top = z;
                    top_walk = pl.n.z >= walk;
                }
            }
            double t = top - p.z;
            if (!top_walk || !(t > 0.01) || t > D + 0.01) {
                ok = false;
                break;
            }
        }
        if (ok) {
            if (opt.one_way_front_only && f.n.z <= kFrontOnlyNz) {
                f.one_way = true;   // a candidate: cross_one_way keeps it front-only unless it is a low ceiling
            } else {
                f.drop = true;
            }
            dropped++;
        }
    }
    if (dropped) {
        S.one_way = true;
    }
    return dropped;
}

// thin walls (thin_wall_max): two antiparallel faces of a closed solid, both steeper than walkable (|n.z| < 0.5) and
// at most thin_wall_max apart, become ONE double-sided face on the plane halfway between them (the solid's
// cross-section there). SA1 touches a single-sided polygon from behind within the sphere's radius: a character that
// steps into one side of a wall deeper than the wall is thick touches the other side's polygon from behind as well,
// whose pushback points the other way (the game averages the pushbacks of a land object), so it is not pushed out and
// walks, slides or sinks through the wall (gm_freespace_13's 8-unit fences and panes; doors). A double-sided polygon
// pushes the sphere out to the side its centre is on, whichever way it came. Returns the faces replaced (2 per pair).
// 0.9.2 (GRID-TW1, gsa1_090_water.md with its review R4; gsa1_090_collision.md F4): the middle face is clipped by every
// plane but A's and B's OWN (until 0.9.1 every plane within 0.999 of A's was skipped, so the end plane of a wedge brush
// 2.6 degrees off the wall, or a sliver hull's near-parallel second planes, bounded nothing and the "middle face" of
// base_winding's 524,288-unit square ran through the whole map), then by the solid's box +-0.5 units (a convex solid's
// cross-section lies inside it); a middle face larger than both faces plus one square unit is not a cross-section:
// the pair is left as it is (kept: counted).
// 0.9.3 (curved surfaces, gsa1_091a_loop.md LOOP-G1 5.2 with its Review R.4.2): a pair with a curved face is left as
// two single-sided faces (the running surface of a loop must not step out to a middle face), unless the solid is a
// curved ribbon at most curved_ribbon_max thick: then the pair becomes one double-sided middle face whatever its slope
// (a loop's floor and ceiling segments too: two single-sided faces that close are both within a sphere's reach).
struct ThinWallCounts {
    uint32_t mixed = 0, kept = 0, curved_kept = 0, ribbons = 0;
};
uint32_t thin_wall_solid(Solid &S, const BspWorldOptions &opt, ThinWallCounts *cnt = nullptr)
{
    if (!(opt.thin_wall_max > 0.0f) || S.kind == 2 || !S.closed) {
        return 0;
    }
    const double T = (double)opt.thin_wall_max;
    const double RB = S.curved ? std::max(0.0, (double)opt.curved_ribbon_max) : 0.0;
    uint32_t replaced = 0;
    const size_t nf = S.faces.size();
    std::vector<D3> poly, tmp;
    std::vector<SFace> add;
    const Plane box[6] = {{D3{1, 0, 0}, S.hi.x + 0.5, true},   {D3{-1, 0, 0}, -(S.lo.x - 0.5), true},
                          {D3{0, 1, 0}, S.hi.y + 0.5, true},   {D3{0, -1, 0}, -(S.lo.y - 0.5), true},
                          {D3{0, 0, 1}, S.hi.z + 0.5, true},   {D3{0, 0, -1}, -(S.lo.z - 0.5), true}};
    for (size_t a = 0; a < nf; a++) {
        if (S.faces[a].drop || S.faces[a].poly.empty() || (std::fabs(S.faces[a].n.z) >= 0.5 && !S.curved)) {
            continue;
        }
        for (size_t b = a + 1; b < nf; b++) {
            SFace &A = S.faces[a], &B = S.faces[b];
            if (B.drop || B.poly.empty() || dot(A.n, B.n) > -0.999) {
                continue;
            }
            const bool curved = A.curved || B.curved;
            if (!curved && std::fabs(A.n.z) >= 0.5) {
                continue;   // (a curved solid's other faces: the plain rule)
            }
            double dA = dot(A.n, centroid(A.poly)), dB = dot(B.n, centroid(B.poly));
            double t = dA + dB;   // B's plane is A's normal at -dB: the slab between them is t thick
            if (curved) {
                if (!(t > 0.01) || t > RB + 0.01) {
                    if (cnt && t > 0.01 && t <= T + 0.01 && std::fabs(A.n.z) < 0.5) {
                        cnt->curved_kept++;   // a thin wall the plain rule would have made one face
                    }
                    continue;
                }
            } else if (!(t > 0.01) || t > T + 0.01) {
                continue;
            }
            Plane M{A.n, dA - 0.5 * t, true};
            base_winding(M, poly);
            for (const Plane &pl : S.planes) {
                double c = dot(pl.n, A.n);
                if ((c > 0.999 && std::fabs(pl.d - dA) < 0.05) || (c < -0.999 && std::fabs(pl.d - dB) < 0.05)) {
                    continue;   // A's and B's own planes
                }
                clip_back(poly, pl, 0.01, tmp);
                if (poly.size() < 3) {
                    break;
                }
            }
            for (int k = 0; k < 6 && poly.size() >= 3; k++) {
                clip_back(poly, box[k], 0.01, tmp);
            }
            dedupe(poly);
            D3 nw = poly.size() >= 3 ? newell(poly) : D3{0, 0, 0};
            if (poly.size() < 3 || length(nw) < 2.0) {
                continue;   // no cross-section (or less than one square unit)
            }
            if (0.5 * length(nw) > std::max(0.5 * length(newell(A.poly)), 0.5 * length(newell(B.poly))) + 1.0) {
                if (cnt) {
                    cnt->kept++;   // larger than both faces: no cross-section of this solid (thin stacks may join them)
                }
                continue;
            }
            if (dot(nw, A.n) < 0.0) {
                std::reverse(poly.begin(), poly.end());
            }
            SFace m = A;
            m.poly.swap(poly);
            m.surface |= SA1_SURFACE_DOUBLE_SIDED;
            m.drop = false;
            m.one_way = false;
            if (curved) {
                m.curved = true;   // the middle surface of a thin curved ribbon
                m.surface |= SA1_SURFACE_CURVED;
                if (cnt) {
                    cnt->ribbons++;
                }
            }
            // surface types (Review G7): the side facing more upward gives the slot; the other side's hurts /
            // no-climbing kinds apply as well (the tag's second slot), its diggable / slippery ones do not
            const SFace &U = B.n.z > A.n.z ? B : A, &O = B.n.z > A.n.z ? A : B;
            m.sp = U.sp;
            m.sp_also = O.sp != U.sp ? O.sp : kNoSurface;
            if (cnt && O.sp != U.sp) {
                cnt->mixed++;
            }
            face_bounds(m);
            A.drop = true;
            B.drop = true;
            add.push_back(std::move(m));
            replaced += 2;
            break;
        }
    }
    for (SFace &m : add) {
        S.faces.push_back(std::move(m));
    }
    return replaced;
}

// the thin-wall rule with its stats
void thin_wall_rule(Solid &S, const BspWorldOptions &opt, BspWorldStats &st)
{
    ThinWallCounts c;
    uint32_t tw = thin_wall_solid(S, opt, &c);
    st.thin_walls_mixed += c.mixed;
    st.thin_wall_kept += c.kept;
    st.curved_thin_walls += c.curved_kept;
    st.curved_ribbons += c.ribbons;
    if (tw) {
        st.thin_walls++;
        st.thin_wall_faces += tw;
    }
}

// the per-solid rules after its faces are made (and after detect_curved): one-way thin platforms, thin walls (stats)
void solid_rules(Solid &S, const BspWorldOptions &opt, BspWorldStats &st)
{
    uint32_t ow = one_way_solid(S, opt, &st.curved_one_way);
    if (ow) {
        st.one_way_solids++;
        st.one_way_faces += ow;
    }
    thin_wall_rule(S, opt, st);
}

// a brush's surface word, whether it only clips the player, and its side planes (sp[s].ok: a usable plane)
void brush_setup(const BspData &w, const DBrush &br, uint8_t kind, uint32_t &base, bool &clip_only, std::vector<Plane> &sp)
{
    uint32_t ct = (uint32_t)br.contents;
    clip_only = false;
    if (kind == 1) {
        base = SA1_SURFACE_SOLID;
        if (!(ct & CONTENTS_SOLID) && (ct & (CONTENTS_WINDOW | CONTENTS_GRATE | CONTENTS_PLAYERCLIP))) {
            base |= SA1_SURFACE_NO_CLIMB;
            clip_only = (ct & CONTENTS_PLAYERCLIP) != 0;
        }
    } else {
        base = SA1_SURFACE_WATER;
    }
    sp.assign((size_t)br.numsides, Plane{D3{0, 0, 0}, 0.0, false});
    for (int32_t s = 0; s < br.numsides; s++) {
        const DBrushSide &sd = w.sides()[br.firstside + s];
        Plane &q = sp[(size_t)s];
        q.ok = sd.planenum < w.nplanes && w.planes[sd.planenum].ok;
        if (q.ok) {
            q = w.planes[sd.planenum];
        }
    }
}

// the solids of the marked brushes (kind[b] 1 solid / 2 water; disp_brush: dropped): their faces only. 0.9.3
// (gsa1_091a_loop.md Review R.3.1 / R.4.3): the rules run in a second pass (brush_rules), after detect_curved has
// seen every solid's faces
void brush_solids(const BspData &w, const std::vector<uint8_t> &mark, const std::vector<uint8_t> &kind,
                  const std::vector<uint8_t> &disp_brush, std::vector<Solid> &S, const BspSurfaceSlots *slots)
{
    std::vector<Plane> sp;
    for (size_t b = 0; b < w.nbrushes; b++) {
        if (!mark[b] || !kind[b] || (!disp_brush.empty() && disp_brush[b])) {
            continue;
        }
        const DBrush &br = w.brushes()[b];
        uint32_t base;
        bool clip_only;
        brush_setup(w, br, kind[b], base, clip_only, sp);
        Solid s;
        brush_faces(w, br, sp, base, clip_only, kind[b], s, s.fc, slots);
        s.brush = (int32_t)b;
        S.push_back(std::move(s));
    }
}

// the rules of the brush solids S[0 .. n) (brush_solids), after detect_curved: one-way thin platforms, thin floors
// thickened (solids that are neither one-way nor curved), thin walls
void brush_rules(const BspData &w, std::vector<Solid> &S, size_t n, const BspWorldOptions &opt, BspWorldStats &st,
                 const BspSurfaceSlots *slots)
{
    std::vector<Plane> sp;
    for (size_t i = 0; i < n && i < S.size(); i++) {
        Solid &s = S[i];
        if (s.brush < 0 || (size_t)s.brush >= w.nbrushes) {
            continue;
        }
        const DBrush &br = w.brushes()[(size_t)s.brush];
        const uint8_t kind = s.kind;
        uint32_t ow = one_way_solid(s, opt, &st.curved_one_way);
        if (ow) {
            st.one_way_solids++;
            st.one_way_faces += ow;
        } else if (kind == 1 && opt.thin_floor_min > 0.0f && !s.curved) {
            uint32_t base;
            bool clip_only;
            brush_setup(w, br, kind, base, clip_only, sp);
            FaceCounts &fc = s.fc;
            // a walkable top side with an anti-parallel bottom side closer than thin_floor_min: SA1's land collision
            // reaches a floor's underside from above when it is less than about 2 SA1 units (8 Hammer units) below
            // the top, and its pushback then pulls the character down through the floor (solids that are not
            // one-way only)
            bool thick = false;
            for (int32_t t = 0; t < br.numsides; t++) {
                const Plane &top = sp[(size_t)t];
                if (!top.ok || top.n.z < 0.7 || w.sides()[br.firstside + t].bevel) {
                    continue;
                }
                for (int32_t u = 0; u < br.numsides; u++) {
                    Plane &bot = sp[(size_t)u];
                    if (u == t || !bot.ok || w.sides()[br.firstside + u].bevel || dot(top.n, bot.n) > -0.999) {
                        continue;
                    }
                    double th = top.d + bot.d;
                    if (th > 0.01 && th < (double)opt.thin_floor_min) {
                        bot.d += (double)opt.thin_floor_min - th;
                        st.thickened_floors++;
                        thick = true;
                    }
                }
            }
            if (thick) {
                brush_faces(w, br, sp, base, clip_only, kind, s, fc, slots);   // (keeps s.brush; s is not curved)
            }
        }
        if (kind == 1) {
            thin_wall_rule(s, opt, st);
        }
        st.brush_faces += s.fc.faces;
        st.degenerate_faces += s.fc.degenerate;
        st.bevel_sides += s.fc.bevel;
    }
}

// a convex hull (triangles, any winding) as a solid: its planes (outward, from the hull's centre), its faces (the
// points on each plane, their convex hull). Not convex (a damaged hull): its faces are kept, it clips nothing.
bool hull_solid(const ConvexSolid &cs, Solid &S)
{
    size_t nt = cs.tris.size() / 9;
    S = Solid();
    S.kind = 3;
    if (nt < 4 || nt > 65536 || cs.tris.size() % 9 != 0) {
        return false;
    }
    std::vector<D3> pts;
    pts.reserve(nt * 3);
    D3 c{0, 0, 0};
    for (size_t i = 0; i < nt * 3; i++) {
        const float *f = &cs.tris[3 * i];
        if (!finite3(f) || std::fabs(f[0]) > 65536.0f || std::fabs(f[1]) > 65536.0f || std::fabs(f[2]) > 65536.0f) {
            return false;
        }
        pts.push_back(d3(f));
        c = c + pts.back();
    }
    c = c * (1.0 / (double)pts.size());
    for (size_t t = 0; t < nt; t++) {
        const D3 &a = pts[3 * t], &b = pts[3 * t + 1], &cc = pts[3 * t + 2];
        D3 nn = cross(b - a, cc - a);
        double l = length(nn);
        if (!(l > 1e-4)) {
            continue;   // a sliver: its plane is not reliable
        }
        nn = nn * (1.0 / l);
        if (dot(nn, (a + b + cc) * (1.0 / 3.0) - c) < 0.0) {
            nn = nn * -1.0;
        }
        double d = dot(nn, a);
        bool dup = false;
        for (const Plane &P : S.planes) {
            if (dot(P.n, nn) > 0.99995 && std::fabs(P.d - d) < 0.02) {
                dup = true;
                break;
            }
        }
        if (!dup) {
            S.planes.push_back(Plane{nn, d, true});
        }
        if (S.planes.size() > 4096) {
            return false;
        }
    }
    // the hull's distinct points
    std::vector<D3> up = pts;
    std::sort(up.begin(), up.end(), [](const D3 &a, const D3 &b) {
        return a.x < b.x || (a.x == b.x && (a.y < b.y || (a.y == b.y && a.z < b.z)));
    });
    std::vector<D3> uniq;
    for (const D3 &p : up) {
        bool same = false;
        for (size_t k = uniq.size(); k > 0 && uniq[k - 1].x > p.x - 1e-3; k--) {
            if (length(uniq[k - 1] - p) <= 1e-3) {
                same = true;
                break;
            }
        }
        if (!same) {
            uniq.push_back(p);
        }
    }
    bool convex = true;
    for (const Plane &P : S.planes) {
        for (const D3 &p : uniq) {
            if (dot(P.n, p) - P.d > 0.1) {
                convex = false;
                break;
            }
        }
        if (!convex) {
            break;
        }
    }
    D3 lo{1e300, 1e300, 1e300}, hi{-1e300, -1e300, -1e300};
    std::vector<P2> q, h;
    for (const Plane &P : S.planes) {
        Chart ch(P.n, P.d);
        q.clear();
        for (const D3 &p : uniq) {
            if (std::fabs(dot(P.n, p) - P.d) <= 0.05) {
                q.push_back(ch.to2(p));
            }
        }
        if (q.size() < 3) {
            continue;
        }
        hull2(q, h);
        if (h.size() < 3) {
            continue;
        }
        SFace f;
        for (const P2 &hp : h) {
            f.poly.push_back(ch.to3(hp));
        }
        if (dot(newell(f.poly), P.n) < 0.0) {
            std::reverse(f.poly.begin(), f.poly.end());
        }
        dedupe(f.poly);
        if (f.poly.size() < 3) {
            continue;
        }
        f.n = P.n;
        f.surface = cs.surface;
        f.sp = cs.sp;
        f.flags = 0;
        f.sky = f.clip_only = f.drop = false;
        face_bounds(f);
        lo = dmin(lo, f.lo);
        hi = dmax(hi, f.hi);
        S.faces.push_back(std::move(f));
    }
    S.lo = lo;
    S.hi = hi;
    // 0.9.2 (GRID-TW1, gsa1_090_water.md): a sliver - thinner than 0.1 units on an axis, or planes in fewer than 3
    // directions (rp_rockford_v2b's prop hulls: 4 planes in two nearly coincident antiparallel pairs) - encloses no
    // volume: not closed (no thin wall, clips nothing); its faces stay (thin stacks join the steep ones)
    std::vector<D3> dirs;
    for (const Plane &P : S.planes) {
        bool same = false;
        for (const D3 &d : dirs) {
            if (std::fabs(dot(P.n, d)) > 0.999) {
                same = true;
                break;
            }
        }
        if (!same) {
            dirs.push_back(P.n);
            if (dirs.size() >= 3) {
                break;
            }
        }
    }
    bool flat = !S.faces.empty() && (hi.x - lo.x < 0.1 || hi.y - lo.y < 0.1 || hi.z - lo.z < 0.1);
    S.closed = convex && S.faces.size() >= 4 && dirs.size() >= 3 && !flat;
    S.clipper = S.closed;
    return !S.faces.empty();
}

// ---- curved surfaces (0.9.3: sadc docs/research/gsa1_091a_loop.md LOOP-G1, 5.1 with its Review R.2.9, R.3.1, R.4.2,
// R.4.3) ----------------------------------------------------------------------------------------------------------------
// On the faces of all solids, BEFORE any rule (one-way, thin floors, thin walls; the rules pass of brush_rules /
// solid_rules runs after this): two faces of DIFFERENT solids are neighbours along an edge when an edge of each lies on
// one line (within 0.05 units) and the two overlap by at least 1 unit (a corkscrew's segments share their seam lines
// but not their end points; within one convex solid every edge is convex, so only faces of different solids can bend
// toward each other). Neighbours are joined when they are coplanar, or when the edge is smooth (normals within
// curved_max_angle), concave (the neighbour bends toward the face's front: one of its corners at least 0.01 units in
// front of the face's plane) and of a large curve (the distance of the two centroids over the bend in radians at least
// curved_min_radius: ladder rungs, chamfers and small cylinders stay out). Floors (n.z >= 0.5) never take part (the
// search does not pass through a floor), nor do sky faces. A group that holds a wall-like face (-0.1 <= n.z < 0.5) and a
// ceiling-like face (n.z <= -0.5) is a curved surface: a loop's, a pipe's or an arch's inside; all its faces are curved
// (those turned down, n.z < -0.1, are its "undersides"). A group of walls alone never is (the review's R.2.9: otherwise
// every wall would be exempt from the thin-wall rule), nor is a group whose faces only lean a little (the loop doc's
// n.z < -0.1 alone made rp_rockford_v2b's slightly bent lamp posts - stacked hull pieces - 724 "curved surfaces" whose
// 4,853 pieces the thin-stack rule then left alone). A plank's underside meets its sides at convex edges and is never
// reached. Displacements take no part (they are built after the solids' rules).
// Its faces get SFace::curved and SA1_SURFACE_CURVED, their solids Solid::curved.
void detect_curved(std::vector<Solid> &S, const BspWorldOptions &opt, BspWorldStats &st)
{
    if (!opt.curved) {
        return;
    }
    const double cosmax = std::cos((double)std::max(0.0f, std::min(89.0f, opt.curved_max_angle)) * 3.14159265358979 / 180.0);
    const double minr = std::max(0.0, (double)opt.curved_min_radius);
    struct CF {
        uint32_t s, f;
    };
    std::vector<CF> cf;
    for (size_t s = 0; s < S.size(); s++) {
        if (S[s].kind == 2) {
            continue;
        }
        for (size_t f = 0; f < S[s].faces.size(); f++) {
            const SFace &F = S[s].faces[f];
            if (F.drop || F.sky || F.poly.size() < 3 || !(F.n.z < 0.5)) {
                continue;
            }
            if (!std::isfinite(F.lo.x + F.lo.y + F.lo.z + F.hi.x + F.hi.y + F.hi.z) || std::fabs(F.lo.x) > kMaxCoord ||
                std::fabs(F.lo.y) > kMaxCoord || std::fabs(F.lo.z) > kMaxCoord || std::fabs(F.hi.x) > kMaxCoord ||
                std::fabs(F.hi.y) > kMaxCoord || std::fabs(F.hi.z) > kMaxCoord) {
                continue;
            }
            cf.push_back(CF{(uint32_t)s, (uint32_t)f});
        }
    }
    if (cf.size() < 2) {
        return;
    }
    auto face = [&](uint32_t i) -> const SFace & { return S[cf[i].s].faces[cf[i].f]; };
    // 3D bins (kCell units) of the faces' boxes; a face over more than kBigCells bins goes to `big`, which every face meets
    const double kCell = 128.0;
    const int64_t kBigCells = 512;
    auto ckey = [](int64_t x, int64_t y, int64_t z) {
        return ((uint64_t)(x & 0x1FFFFF) << 42) | ((uint64_t)(y & 0x1FFFFF) << 21) | (uint64_t)(z & 0x1FFFFF);
    };
    std::unordered_map<uint64_t, std::vector<uint32_t>> bins;
    std::vector<uint8_t> is_big(cf.size(), 0);
    std::vector<uint32_t> big;
    auto range = [&](const SFace &F, int64_t r[6]) {
        r[0] = (int64_t)std::floor((F.lo.x - 0.1) / kCell);
        r[1] = (int64_t)std::floor((F.hi.x + 0.1) / kCell);
        r[2] = (int64_t)std::floor((F.lo.y - 0.1) / kCell);
        r[3] = (int64_t)std::floor((F.hi.y + 0.1) / kCell);
        r[4] = (int64_t)std::floor((F.lo.z - 0.1) / kCell);
        r[5] = (int64_t)std::floor((F.hi.z + 0.1) / kCell);
        return (r[1] - r[0] + 1) * (r[3] - r[2] + 1) * (r[5] - r[4] + 1);
    };
    for (uint32_t i = 0; i < (uint32_t)cf.size(); i++) {
        int64_t r[6];
        if (range(face(i), r) > kBigCells) {
            is_big[i] = 1;
            big.push_back(i);
            continue;
        }
        for (int64_t x = r[0]; x <= r[1]; x++) {
            for (int64_t y = r[2]; y <= r[3]; y++) {
                for (int64_t z = r[4]; z <= r[5]; z++) {
                    bins[ckey(x, y, z)].push_back(i);
                }
            }
        }
    }
    // union-find over cf
    std::vector<uint32_t> parent(cf.size());
    for (uint32_t i = 0; i < (uint32_t)parent.size(); i++) {
        parent[i] = i;
    }
    auto find = [&](uint32_t x) {
        while (parent[x] != x) {
            parent[x] = parent[parent[x]];
            x = parent[x];
        }
        return x;
    };
    // an edge of each on one line, overlapping by at least 1 unit
    auto shared_edge = [](const std::vector<D3> &P, const std::vector<D3> &Q) {
        for (size_t i = 0; i < P.size(); i++) {
            const D3 &a0 = P[i], &a1 = P[(i + 1) % P.size()];
            D3 e = a1 - a0;
            double L = length(e);
            if (!(L >= 1.0)) {
                continue;
            }
            D3 u = e * (1.0 / L);
            for (size_t j = 0; j < Q.size(); j++) {
                D3 w0 = Q[j] - a0, w1 = Q[(j + 1) % Q.size()] - a0;
                double t0 = dot(w0, u), t1 = dot(w1, u);
                D3 p0 = w0 - u * t0, p1 = w1 - u * t1;
                if (dot(p0, p0) > 0.0025 || dot(p1, p1) > 0.0025) {
                    continue;
                }
                double lo = std::max(0.0, std::min(t0, t1)), hi = std::min(L, std::max(t0, t1));
                if (hi - lo >= 1.0) {
                    return true;
                }
            }
        }
        return false;
    };
    auto try_pair = [&](uint32_t i, uint32_t j) {
        if (cf[i].s == cf[j].s) {
            return;
        }
        const SFace &A = face(i), &B = face(j);
        if (A.lo.x > B.hi.x + 0.1 || A.hi.x < B.lo.x - 0.1 || A.lo.y > B.hi.y + 0.1 || A.hi.y < B.lo.y - 0.1 ||
            A.lo.z > B.hi.z + 0.1 || A.hi.z < B.lo.z - 0.1) {
            return;
        }
        double c = dot(A.n, B.n);
        if (c < cosmax) {
            return;
        }
        uint32_t ri = find(i), rj = find(j);
        if (ri == rj) {
            return;   // joined already
        }
        const double dA = dot(A.n, A.poly[0]), dB = dot(B.n, B.poly[0]);
        bool coplanar = c > 1.0 - 1e-5 && std::fabs(dA - dB) < 0.05;
        if (!coplanar) {
            double far = -1e300;
            for (const D3 &v : B.poly) {
                far = std::max(far, dot(A.n, v) - dA);
            }
            if (far < 0.01) {
                return;   // convex (or flat): an outside corner
            }
            double ang = std::acos(std::min(1.0, c));
            if (!(ang > 1e-9) || length(centroid(A.poly) - centroid(B.poly)) / ang < minr) {
                return;   // too sharp a curve
            }
        }
        if (!shared_edge(A.poly, B.poly)) {
            return;
        }
        parent[ri] = rj;
    };
    std::vector<uint32_t> stamp(cf.size(), 0);
    uint32_t now = 0;
    for (uint32_t i = 0; i < (uint32_t)cf.size(); i++) {
        if (is_big[i]) {
            continue;
        }
        now++;
        int64_t r[6];
        range(face(i), r);
        for (int64_t x = r[0]; x <= r[1]; x++) {
            for (int64_t y = r[2]; y <= r[3]; y++) {
                for (int64_t z = r[4]; z <= r[5]; z++) {
                    auto it = bins.find(ckey(x, y, z));
                    if (it == bins.end()) {
                        continue;
                    }
                    for (uint32_t j : it->second) {
                        if (j > i && stamp[j] != now) {
                            stamp[j] = now;
                            try_pair(i, j);
                        }
                    }
                }
            }
        }
        for (uint32_t j : big) {
            try_pair(i, j);
        }
    }
    for (size_t a = 0; a < big.size(); a++) {
        for (size_t b = a + 1; b < big.size(); b++) {
            try_pair(big[a], big[b]);
        }
    }
    // the groups with a wall-like face and a ceiling-like face
    std::vector<uint8_t> has(cf.size(), 0);   // per root: 1 a seed, 2 a ceiling-like face
    for (uint32_t i = 0; i < (uint32_t)cf.size(); i++) {
        double nz = face(i).n.z;
        has[find(i)] |= (nz >= -0.1 ? 1u : 0u) | (nz <= -0.5 ? 2u : 0u);
    }
    std::vector<uint8_t> counted(cf.size(), 0);
    for (uint32_t i = 0; i < (uint32_t)cf.size(); i++) {
        uint32_t r = find(i);
        if (has[r] != 3) {
            continue;
        }
        if (!counted[r]) {
            counted[r] = 1;
            st.curved_surfaces++;
        }
        Solid &so = S[cf[i].s];
        SFace &F = so.faces[cf[i].f];
        F.curved = true;
        F.surface |= SA1_SURFACE_CURVED;
        st.curved_faces++;
        st.curved_undersides += F.n.z < -0.1;
        if (!so.curved) {
            so.curved = true;
            st.curved_solids++;
        }
    }
}

// ---- the cleaning pipeline -----------------------------------------------------------------------------------------
struct Vis {
    const SFace *f;
    uint8_t kind;
    std::vector<std::vector<D3>> frags;
    bool stair_cut;
    bool boxed = false;             // lo..hi: the box of the face's solid (the guard: pieces outside it + 1 unit)
    D3 lo{0, 0, 0}, hi{0, 0, 0};
};

// Hidden faces (remove_hidden) and stair ramps (stairs && stair_ramps) of the solids: vis gets the visible pieces of
// every face (ramps: the generated ramp faces, which vis points into).
void clean(std::vector<Solid> &S, const BspWorldOptions &opt, bool stairs, std::vector<SFace> &ramps,
           std::vector<Vis> &vis, BspWorldStats &st)
{
    // the clippers by column (kClipCell x kClipCell Hammer units in x / y); a solid over more than kClipBig cells
    // (the sky box, a damaged file) goes to `big`, which every face checks
    const double kClipCell = 512.0;
    const int64_t kClipBig = 256;
    std::map<std::pair<int32_t, int32_t>, std::vector<uint32_t>> cells;
    std::vector<uint32_t> big;
    if (opt.remove_hidden) {
        for (size_t b = 0; b < S.size(); b++) {
            if (!S[b].clipper) {
                continue;
            }
            int32_t x0 = (int32_t)std::floor(S[b].lo.x / kClipCell), x1 = (int32_t)std::floor(S[b].hi.x / kClipCell);
            int32_t y0 = (int32_t)std::floor(S[b].lo.y / kClipCell), y1 = (int32_t)std::floor(S[b].hi.y / kClipCell);
            if ((int64_t)(x1 - x0 + 1) * (int64_t)(y1 - y0 + 1) > kClipBig) {
                big.push_back((uint32_t)b);
                continue;
            }
            for (int32_t cx = x0; cx <= x1; cx++) {
                for (int32_t cy = y0; cy <= y1; cy++) {
                    cells[{cx, cy}].push_back((uint32_t)b);
                }
            }
        }
    }
    std::vector<std::vector<const Plane *>> cplanes(S.size());
    for (size_t b = 0; b < S.size(); b++) {
        if (S[b].clipper) {
            for (const Plane &pl : S[b].planes) {
                cplanes[b].push_back(&pl);
            }
        }
    }
    std::vector<std::vector<D3>> frags, next;
    std::vector<uint32_t> cand, stamp(S.size(), 0);
    uint32_t stamp_now = 0;
    std::vector<D3> inside, front, back;
    // the clippers whose box meets lo..hi (+pad), in index order, `self` left out
    auto clippers_near = [&](const D3 &lo, const D3 &hi, size_t self) {
        const double pad = 0.1;
        cand.clear();
        stamp_now++;
        int32_t x0 = (int32_t)std::floor((lo.x - pad) / kClipCell), x1 = (int32_t)std::floor((hi.x + pad) / kClipCell);
        int32_t y0 = (int32_t)std::floor((lo.y - pad) / kClipCell), y1 = (int32_t)std::floor((hi.y + pad) / kClipCell);
        auto consider = [&](uint32_t o) {
            if (stamp[o] == stamp_now || o == self) {
                return;
            }
            stamp[o] = stamp_now;
            if (S[o].lo.x > hi.x + pad || S[o].hi.x < lo.x - pad || S[o].lo.y > hi.y + pad || S[o].hi.y < lo.y - pad ||
                S[o].lo.z > hi.z + pad || S[o].hi.z < lo.z - pad) {
                return;
            }
            cand.push_back(o);
        };
        if ((int64_t)(x1 - x0 + 1) * (int64_t)(y1 - y0 + 1) <= (int64_t)cells.size()) {
            for (int32_t cx = x0; cx <= x1; cx++) {
                for (int32_t cy = y0; cy <= y1; cy++) {
                    auto it = cells.find({cx, cy});
                    if (it != cells.end()) {
                        for (uint32_t o : it->second) {
                            consider(o);
                        }
                    }
                }
            }
        } else {
            for (const auto &kv : cells) {   // a face larger than the occupied cells
                if (kv.first.first >= x0 && kv.first.first <= x1 && kv.first.second >= y0 && kv.first.second <= y1) {
                    for (uint32_t o : kv.second) {
                        consider(o);
                    }
                }
            }
        }
        for (uint32_t o : big) {
            consider(o);
        }
        std::sort(cand.begin(), cand.end());
    };
    // cuts fr (pieces of a face with normal fn of solid `self`; SIZE_MAX: a generated face) by the clippers near
    // lo..hi; of coplanar duplicates the lower solid index keeps the overlap (a generated face never does)
    auto cut_by_solids = [&](std::vector<std::vector<D3>> &fr, const D3 &fn, const D3 &lo, const D3 &hi, size_t self) {
        bool cut = false;
        clippers_near(lo, hi, self);
        for (uint32_t o : cand) {
            cut |= cut_by_volume(fr, fn, self < (size_t)o, cplanes[o], next, inside, front, back);
            if (fr.empty() || fr.size() > 4096) {
                break;   // gone, or cut into more pieces than any real map makes (a damaged file): kept so
            }
        }
        return cut;
    };

    // hidden parts (remove_hidden): a face loses its parts inside another closed solid o, which includes the parts
    // lying on a face of o that looks into o's volume (two solids touching); where it lies on a face of o facing the
    // same way (coplanar duplicates), the lower solid index keeps the overlap
    for (size_t b = 0; b < S.size(); b++) {
        for (const SFace &f : S[b].faces) {
            if (f.drop) {
                continue;   // one-way: left out
            }
            frags.clear();
            frags.push_back(f.poly);
            bool cut = opt.remove_hidden && cut_by_solids(frags, f.n, f.lo, f.hi, b);
            if (cut && f.sp != kNoSurface) {
                // Review G6: a coplanar face of a lower solid facing the same way keeps the overlap - with its own
                // surface type; counted where that type differs (cand: the clippers cut_by_solids looked at, sorted)
                const double fd = dot(f.n, f.poly[0]);
                bool mixed = false;
                for (uint32_t o : cand) {
                    if ((size_t)o >= b || mixed) {
                        break;
                    }
                    for (const SFace &g : S[o].faces) {
                        if (g.sp == f.sp || g.drop || g.poly.empty() || dot(g.n, f.n) < 0.99 ||
                            std::fabs(dot(g.n, g.poly[0]) - fd) > 0.05 || g.lo.x > f.hi.x + 0.1 || g.hi.x < f.lo.x - 0.1 ||
                            g.lo.y > f.hi.y + 0.1 || g.hi.y < f.lo.y - 0.1 || g.lo.z > f.hi.z + 0.1 ||
                            g.hi.z < f.lo.z - 0.1) {
                            continue;
                        }
                        mixed = true;
                        break;
                    }
                }
                st.coplanar_mixed += mixed;
            }
            if (frags.empty()) {
                st.hidden_faces++;
                continue;
            }
            if (cut) {
                st.clipped_faces++;
            }
            vis.push_back(Vis{&f, S[b].kind, frags, false, true, S[b].lo, S[b].hi});
        }
    }

    // stairs (stair_ramps): runs of at least stair_min_steps risers (visible vertical faces of brushes at most
    // stair_max_rise high, each one tread further and one rise higher than the one before, facing the same way,
    // overlapping sideways) become a ramp: a wedge from the floor in front of the first riser up to the top nosing,
    // as wide as all risers, cuts the treads and risers away (and the walls beside them below the ramp), and its top
    // is emitted as SOLID | STAIRS. Dense steps would otherwise overflow the game's NEAR-poly list (8C028BFE: the
    // floor under the character drops out of it) and SA1's own stairs are ramps with the stair bit.
    if (stairs && opt.remove_hidden && opt.stair_ramps && opt.stair_min_steps >= 2) {
        struct Riser {
            size_t vi, fi;
            D3 c, lat;
            double s, zmin, zmax, l0, l1;
            int next = -1, prev = -1;
        };
        std::vector<Riser> risers;
        for (size_t vi = 0; vi < vis.size(); vi++) {
            const SFace &f = *vis[vi].f;
            if (vis[vi].kind != 1 || std::fabs(f.n.z) > 0.01) {
                continue;
            }
            double hl = std::sqrt(f.n.x * f.n.x + f.n.y * f.n.y);
            if (hl < 0.5) {
                continue;
            }
            D3 c{-f.n.x / hl, -f.n.y / hl, 0.0}, lat{-c.y, c.x, 0.0};
            for (size_t fi = 0; fi < vis[vi].frags.size(); fi++) {
                const std::vector<D3> &p = vis[vi].frags[fi];
                Riser R;
                R.vi = vi;
                R.fi = fi;
                R.c = c;
                R.lat = lat;
                R.s = dot(c, p[0]);
                R.zmin = R.zmax = p[0].z;
                R.l0 = R.l1 = dot(lat, p[0]);
                for (const D3 &q : p) {
                    R.zmin = std::min(R.zmin, q.z);
                    R.zmax = std::max(R.zmax, q.z);
                    R.l0 = std::min(R.l0, dot(lat, q));
                    R.l1 = std::max(R.l1, dot(lat, q));
                }
                double h = R.zmax - R.zmin, width = R.l1 - R.l0;
                if (h < 1.0 || h > (double)opt.stair_max_rise || width < 16.0) {
                    continue;
                }
                // a rectangle-like piece: its top and bottom edges span most of its width
                double top0 = 1e300, top1 = -1e300, bot0 = 1e300, bot1 = -1e300;
                for (const D3 &q : p) {
                    double l = dot(lat, q);
                    if (q.z >= R.zmax - 0.1) {
                        top0 = std::min(top0, l);
                        top1 = std::max(top1, l);
                    }
                    if (q.z <= R.zmin + 0.1) {
                        bot0 = std::min(bot0, l);
                        bot1 = std::max(bot1, l);
                    }
                }
                if (top1 - top0 < 0.8 * width || bot1 - bot0 < 0.8 * width) {
                    continue;
                }
                risers.push_back(R);
            }
        }
        std::sort(risers.begin(), risers.end(), [](const Riser &a, const Riser &b) {
            return a.zmin != b.zmin ? a.zmin < b.zmin : a.s < b.s;
        });
        // the next riser up: one rise higher, a tread (4 .. 64 units) further, facing the same way, overlapping
        for (size_t i = 0; i < risers.size(); i++) {
            Riser &R = risers[i];
            int best = -1;
            double best_ds = 1e300;
            for (size_t j = i + 1; j < risers.size() && risers[j].zmin < R.zmax + 0.6; j++) {
                const Riser &Q = risers[j];
                if (Q.prev >= 0 || std::fabs(Q.zmin - R.zmax) > 0.6 || dot(R.c, Q.c) < 0.9995) {
                    continue;
                }
                double ds = Q.s - R.s;
                double overlap = std::min(R.l1, Q.l1) - std::max(R.l0, Q.l0);
                if (ds < 4.0 || ds > 64.0 || overlap < 0.6 * std::min(R.l1 - R.l0, Q.l1 - Q.l0)) {
                    continue;
                }
                if (ds < best_ds) {
                    best_ds = ds;
                    best = (int)j;
                }
            }
            if (best >= 0) {
                R.next = best;
                risers[(size_t)best].prev = (int)i;
            }
        }
        struct Wedge {
            std::vector<Plane> planes;
            std::vector<const Plane *> pp;
            D3 lo, hi;
        };
        std::vector<Wedge> wedges;
        for (size_t i = 0; i < risers.size(); i++) {
            if (risers[i].prev >= 0 || risers[i].next < 0) {
                continue;
            }
            std::vector<size_t> chain;
            for (int k = (int)i; k >= 0; k = risers[(size_t)k].next) {
                chain.push_back((size_t)k);
            }
            if (chain.size() < (size_t)opt.stair_min_steps) {
                continue;
            }
            const Riser &R0 = risers[chain.front()], &RN = risers[chain.back()];
            D3 c = R0.c, lat = R0.lat;
            double L0 = -1e300, L1 = 1e300, ms = 0, mz = 0;
            for (size_t k : chain) {
                L0 = std::max(L0, risers[k].l0);
                L1 = std::min(L1, risers[k].l1);
                ms += risers[k].s;
                mz += risers[k].zmax;
            }
            ms /= (double)chain.size();
            mz /= (double)chain.size();
            double sxx = 0, sxz = 0;
            for (size_t k : chain) {
                sxx += (risers[k].s - ms) * (risers[k].s - ms);
                sxz += (risers[k].s - ms) * (risers[k].zmax - mz);
            }
            if (L1 - L0 < 16.0 || !(sxx > 0.0)) {
                continue;
            }
            double m = sxz / sxx;   // rise per unit along c
            if (m < 0.15 || m > 1.6) {
                continue;
            }
            double a = -1e300, worst = 0.0;
            for (size_t k : chain) {
                a = std::max(a, risers[k].zmax - m * risers[k].s);   // the ramp passes over every nosing
            }
            for (size_t k : chain) {
                worst = std::max(worst, a + m * risers[k].s - risers[k].zmax);
            }
            if (worst > 0.75 * (RN.zmax - R0.zmin) / (double)chain.size() + 1.0) {
                continue;   // not evenly spaced (a landing in the run): a ramp would float over a step
            }
            double z0 = R0.zmin, sa = (z0 - a) / m, se = RN.s;
            double q = std::sqrt(1.0 + m * m);
            Wedge W;
            W.planes.push_back(Plane{D3{-m * c.x / q, -m * c.y / q, 1.0 / q}, a / q, true});   // the ramp
            W.planes.push_back(Plane{D3{0, 0, -1}, -(z0 - 0.5), true});                      // below the floor
            W.planes.push_back(Plane{c * -1.0, -sa, true});                                  // front: s >= sa
            W.planes.push_back(Plane{c, se + 0.01, true});                                   // back: s <= se
            W.planes.push_back(Plane{lat * -1.0, -L0, true});                                // sides
            W.planes.push_back(Plane{lat, L1, true});
            D3 corner[8];
            for (int k = 0; k < 8; k++) {
                double s = (k & 1) ? se : sa, l = (k & 2) ? L1 : L0, z = (k & 4) ? a + m * se : z0 - 0.5;
                corner[k] = c * s + lat * l + D3{0, 0, z};
            }
            W.lo = W.hi = corner[0];
            for (const D3 &p : corner) {
                W.lo = dmin(W.lo, p);
                W.hi = dmax(W.hi, p);
            }
            // the ramp face, counter-clockwise seen from above it
            SFace rf;
            rf.poly = {c * sa + lat * L0 + D3{0, 0, z0}, c * se + lat * L0 + D3{0, 0, a + m * se},
                       c * se + lat * L1 + D3{0, 0, a + m * se}, c * sa + lat * L1 + D3{0, 0, z0}};
            rf.n = W.planes[0].n;
            if (dot(newell(rf.poly), rf.n) < 0.0) {
                std::reverse(rf.poly.begin(), rf.poly.end());
            }
            rf.surface = SA1_SURFACE_SOLID | (opt.stair_flag ? SA1_SURFACE_STAIRS : 0u);
            rf.flags = 0;
            rf.sky = rf.clip_only = rf.drop = false;
            rf.lo = W.lo;
            rf.hi = W.hi;
            ramps.push_back(rf);
            wedges.push_back(std::move(W));
            st.stairs++;
            st.stair_steps += (uint32_t)chain.size();
        }
        for (Wedge &W : wedges) {
            W.pp.clear();
            for (const Plane &pl : W.planes) {
                W.pp.push_back(&pl);
            }
        }
        // cut every visible piece by the wedges (the generated ramps keep nothing of theirs: keep_dups for faces); the
        // area of the treads (walkable faces) each ramp replaces, by surface type
        auto frags_area = [](const std::vector<std::vector<D3>> &fr) {
            double a = 0.0;
            for (const std::vector<D3> &q : fr) {
                a += q.size() >= 3 ? 0.5 * length(newell(q)) : 0.0;
            }
            return a;
        };
        std::vector<std::map<uint16_t, double>> treads(wedges.size());
        for (Vis &v : vis) {
            const SFace &f = *v.f;
            for (size_t wi = 0; wi < wedges.size(); wi++) {
                const Wedge &W = wedges[wi];
                if (W.lo.x > f.hi.x + 0.1 || W.hi.x < f.lo.x - 0.1 || W.lo.y > f.hi.y + 0.1 || W.hi.y < f.lo.y - 0.1 ||
                    W.lo.z > f.hi.z + 0.1 || W.hi.z < f.lo.z - 0.1 || v.frags.empty()) {
                    continue;
                }
                bool tread = f.n.z >= 0.7 && f.sp != kNoSurface;
                double before = tread ? frags_area(v.frags) : 0.0;
                bool c = cut_by_volume(v.frags, f.n, true, W.pp, next, inside, front, back);
                v.stair_cut |= c;
                if (tread && c) {
                    treads[wi][f.sp] += before - frags_area(v.frags);
                }
            }
        }
        for (size_t wi = 0; wi < wedges.size() && wi < ramps.size(); wi++) {
            double best = 0.0;
            for (const auto &kv : treads[wi]) {
                if (kv.second > best) {
                    best = kv.second;
                    ramps[wi].sp = kv.first;
                }
            }
            st.stairs_tagged += ramps[wi].sp != kNoSurface;
        }
    }
    for (SFace &rf : ramps) {
        frags.clear();
        frags.push_back(rf.poly);
        cut_by_solids(frags, rf.n, rf.lo, rf.hi, SIZE_MAX);
        if (!frags.empty()) {
            vis.push_back(Vis{&rf, 1, frags, true});
        }
    }
}

// a displacement triangle (oriented; drop: left out by the one-way rule or a thin stack; sp: its surface-type slot;
// surface / sp_also: a thin stack's kept triangle is double-sided with the dropped face's slot as its second one)
struct DispTri {
    D3 a, b, c, n;
    bool drop;
    uint16_t sp = kNoSurface;
    uint32_t surface = SA1_SURFACE_SOLID;
    uint16_t sp_also = kNoSurface;
};

// a displacement's footprint (disp_cover, 0.9.3): the XY convex hull of its points (counter-clockwise seen from above),
// its box and its triangles in build_disp's list (first .. first + count)
struct DispFoot {
    std::vector<P2> hull;
    double x0 = 0, y0 = 0, x1 = 0, y1 = 0, zmin = 0, zmax = 0;
    size_t first = 0, count = 0;
};

// the walkable surfaces (n.z >= one_way_walkable) by 2D bins, for the one-way rule across solids
struct WalkIndex {
    struct Poly {
        std::vector<P2> xy;
        D3 n;
        double d, zmin, zmax;
    };
    std::vector<Poly> polys;
    std::unordered_map<uint64_t, std::vector<uint32_t>> bins;
    std::vector<uint32_t> big;
    static constexpr double kBin = 128.0;
    static uint64_t key(int64_t x, int64_t y) { return ((uint64_t)(uint32_t)(int32_t)x << 32) | (uint32_t)(int32_t)y; }

    void add(const std::vector<D3> &poly, const D3 &n)
    {
        if (poly.size() < 3 || !(n.z > 0.05)) {
            return;
        }
        Poly P;
        P.n = n;
        P.d = dot(n, poly[0]);
        P.zmin = P.zmax = poly[0].z;
        double x0 = poly[0].x, x1 = x0, y0 = poly[0].y, y1 = y0;
        for (const D3 &p : poly) {
            P.xy.push_back(P2{p.x, p.y});
            P.zmin = std::min(P.zmin, p.z);
            P.zmax = std::max(P.zmax, p.z);
            x0 = std::min(x0, p.x);
            x1 = std::max(x1, p.x);
            y0 = std::min(y0, p.y);
            y1 = std::max(y1, p.y);
        }
        if (!std::isfinite(x0 + x1 + y0 + y1 + P.zmin + P.zmax + P.d) || std::fabs(x0) > kMaxCoord ||
            std::fabs(x1) > kMaxCoord || std::fabs(y0) > kMaxCoord || std::fabs(y1) > kMaxCoord) {
            return;   // damaged input: never binned (the bin range below would not end)
        }
        uint32_t id = (uint32_t)polys.size();
        polys.push_back(std::move(P));
        int64_t bx0 = (int64_t)std::floor(x0 / kBin), bx1 = (int64_t)std::floor(x1 / kBin);
        int64_t by0 = (int64_t)std::floor(y0 / kBin), by1 = (int64_t)std::floor(y1 / kBin);
        if ((bx1 - bx0 + 1) * (by1 - by0 + 1) > 4096) {
            big.push_back(id);
            return;
        }
        for (int64_t bx = bx0; bx <= bx1; bx++) {
            for (int64_t by = by0; by <= by1; by++) {
                bins[key(bx, by)].push_back(id);
            }
        }
    }

    bool covers(const Poly &P, const D3 &p, double dmax) const
    {
        if (P.zmax < p.z + 0.01 || P.zmin > p.z + dmax + 0.01) {
            return false;
        }
        size_t n = P.xy.size();
        for (size_t i = 0; i < n; i++) {
            const P2 &a = P.xy[i], &b = P.xy[(i + 1) % n];
            double ex = b.u - a.u, ey = b.v - a.v;
            double cr = ex * (p.y - a.v) - ey * (p.x - a.u);
            if (cr < -0.01 * std::sqrt(ex * ex + ey * ey)) {
                return false;   // outside (walkable faces are counter-clockwise seen from above)
            }
        }
        double z = (P.d - P.n.x * p.x - P.n.y * p.y) / P.n.z;
        double t = z - p.z;
        return t > 0.01 && t <= dmax + 0.01;
    }

    // a walkable surface below p, at most gmax lower (touching counts)
    bool under(const Poly &P, const D3 &p, double gmax) const
    {
        if (P.zmin > p.z + 0.01 || P.zmax < p.z - gmax - 0.01) {
            return false;
        }
        size_t n = P.xy.size();
        for (size_t i = 0; i < n; i++) {
            const P2 &a = P.xy[i], &b = P.xy[(i + 1) % n];
            double ex = b.u - a.u, ey = b.v - a.v;
            double cr = ex * (p.y - a.v) - ey * (p.x - a.u);
            if (cr < -0.01 * std::sqrt(ex * ex + ey * ey)) {
                return false;
            }
        }
        double z = (P.d - P.n.x * p.x - P.n.y * p.y) / P.n.z;
        double t = p.z - z;
        return t >= -0.01 && t <= gmax + 0.01;
    }

    // the polygons binned in x0..x1 / y0..y1, each once (stamp / mark: scratch)
    void near(double x0, double y0, double x1, double y1, std::vector<uint32_t> &out, std::vector<uint32_t> &mark,
              uint32_t &stamp) const
    {
        out.clear();
        if (mark.size() != polys.size()) {
            mark.assign(polys.size(), 0);
        }
        stamp++;
        auto take = [&](uint32_t id) {
            if (mark[id] != stamp) {
                mark[id] = stamp;
                out.push_back(id);
            }
        };
        int64_t bx0 = (int64_t)std::floor(x0 / kBin), bx1 = (int64_t)std::floor(x1 / kBin);
        int64_t by0 = (int64_t)std::floor(y0 / kBin), by1 = (int64_t)std::floor(y1 / kBin);
        if ((bx1 - bx0 + 1) * (by1 - by0 + 1) <= 4096) {
            for (int64_t bx = bx0; bx <= bx1; bx++) {
                for (int64_t by = by0; by <= by1; by++) {
                    auto it = bins.find(key(bx, by));
                    if (it != bins.end()) {
                        for (uint32_t id : it->second) {
                            take(id);
                        }
                    }
                }
            }
        } else {
            for (const auto &kv : bins) {   // a piece larger than the bins (rare): every binned polygon
                for (uint32_t id : kv.second) {
                    take(id);
                }
            }
        }
        for (uint32_t id : big) {
            take(id);
        }
    }

    // a walkable surface above p, at most dmax higher (below > 0: or one below it, at most `below` lower)
    bool covered(const D3 &p, double dmax, double below = 0.0) const
    {
        auto test = [&](uint32_t id) {
            return covers(polys[id], p, dmax) || (below > 0.0 && under(polys[id], p, below));
        };
        auto it = bins.find(key((int64_t)std::floor(p.x / kBin), (int64_t)std::floor(p.y / kBin)));
        if (it != bins.end()) {
            for (uint32_t id : it->second) {
                if (test(id)) {
                    return true;
                }
            }
        }
        for (uint32_t id : big) {
            if (test(id)) {
                return true;
            }
        }
        return false;
    }

    // 0.9.3 (disp_cover): the nearest surface over p - the smallest t = (its height over p's x / y) - p.z with
    // dmin < t <= dmax; 1e300: none
    double lowest(const D3 &p, double dmin, double dmax) const
    {
        double best = 1e300;
        auto test = [&](uint32_t id) {
            const Poly &P = polys[id];
            if (P.zmax < p.z + dmin || P.zmin > p.z + dmax + 0.01) {
                return;
            }
            size_t n = P.xy.size();
            for (size_t i = 0; i < n; i++) {
                const P2 &a = P.xy[i], &b = P.xy[(i + 1) % n];
                double ex = b.u - a.u, ey = b.v - a.v;
                double cr = ex * (p.y - a.v) - ey * (p.x - a.u);
                if (cr < -0.01 * std::sqrt(ex * ex + ey * ey)) {
                    return;
                }
            }
            double t = (P.d - P.n.x * p.x - P.n.y * p.y) / P.n.z - p.z;
            if (t > dmin && t <= dmax && t < best) {
                best = t;
            }
        };
        auto it = bins.find(key((int64_t)std::floor(p.x / kBin), (int64_t)std::floor(p.y / kBin)));
        if (it != bins.end()) {
            for (uint32_t id : it->second) {
                test(id);
            }
        }
        for (uint32_t id : big) {
            test(id);
        }
        return best;
    }
};

// one-way across solids (one_way_cross): a down-facing piece (n.z <= -0.5) of a solid, or a down-facing displacement
// triangle, with a walkable surface of anything at most one_way_max above it - or at most low_ceiling_max below it
// (a low ceiling) - at its centre and near each corner is left out.
// 0.9.3 (one_way_front_only: gsa1_091b_ceiling.md FIX-C3 with its Review R.5.1 b/c/d): a low ceiling - a walkable
// surface 0..low_ceiling_max below every sample - is left out FIRST; otherwise a near-horizontal piece (n.z <=
// kFrontOnlyNz) the one-way rule selects (a walkable surface within one_way_max above everywhere, or its own solid's
// top: one_way_solid's candidates) with room under it (room_below) is kept as a front-only ceiling: its pieces move to
// a copy of the face (in `made`) with
// SA1_SURFACE_FRONT_ONLY, so merge_coplanar / tessellate / emit never mix them with the face's ordinary pieces; a
// steeper one is left out as before. Pieces of curved faces (detect_curved) are left alone (never one-way, never a low
// ceiling, never front-only: a loop's ceiling must stay an ordinary single-sided polygon - the review's R.4.8).
void cross_one_way(std::vector<Vis> &vis, std::vector<DispTri> *disp, const BspWorldOptions &opt, BspWorldStats &st,
                   std::deque<SFace> &made)
{
    if (!(opt.one_way_max > 0.0f)) {
        return;
    }
    const bool fo = opt.one_way_front_only;
    const double D = (double)opt.one_way_max, walk = (double)opt.one_way_walkable;
    const double G = std::max(0.0, (double)opt.low_ceiling_max);
    WalkIndex W;
    if (opt.one_way_cross) {
        for (const Vis &v : vis) {
            if (v.kind != 2 && v.f->n.z >= walk) {
                for (const std::vector<D3> &fr : v.frags) {
                    W.add(fr, v.f->n);
                }
            }
        }
        if (disp) {
            std::vector<D3> t3(3);
            for (const DispTri &t : *disp) {
                if (t.n.z >= walk) {
                    t3[0] = t.a;
                    t3[1] = t.b;
                    t3[2] = t.c;
                    W.add(t3, t.n);
                }
            }
        }
    }
    const bool have_w = !W.polys.empty();
    bool candidates = false;   // one_way_solid's front-only candidates need a decision even without walkable faces
    for (const Vis &v : vis) {
        candidates |= v.f->one_way && !v.frags.empty();
    }
    if (!have_w && !candidates) {
        return;
    }
    // a walkable surface 0..G below every sample (the low-ceiling test that comes first, Review R.5.1 b)
    auto all_below = [&](const std::vector<D3> &poly) {
        if (!(G > 0.0) || !have_w) {
            return false;
        }
        D3 c = centroid(poly);
        if (!W.covered(c, 0.0, G)) {
            return false;
        }
        for (const D3 &v : poly) {
            if (!W.covered(v + (c - v) * 0.1, 0.0, G)) {
                return false;
            }
        }
        return true;
    };
    // room under a front-only ceiling: a walkable surface at most kRoomBelow under the piece's centre or a corner (10 %
    // in). A one-way underside with nothing under it - the floor slab of a map's lowest level over the void - is no
    // ceiling anyone can reach: it is left out as until 0.9.2, so it takes no land-object slot of the game's collision
    // query from the floor above it (rp_downtown_v4c: the extra object under the street let a spin dash through a
    // low wall beside it)
    const double kRoomBelow = 1024.0;
    auto room_below = [&](const std::vector<D3> &poly) {
        if (!have_w) {
            return true;   // nothing to tell (one_way_cross off): one_way_solid's candidates stay front-only
        }
        D3 c = centroid(poly);
        if (W.covered(c, 0.0, kRoomBelow)) {
            return true;
        }
        for (const D3 &v : poly) {
            if (W.covered(v + (c - v) * 0.1, 0.0, kRoomBelow)) {
                return true;
            }
        }
        return false;
    };
    // 1: a walkable surface above everywhere (one-way), 2: above or below (a low ceiling), 0: neither
    auto all_covered = [&](const std::vector<D3> &poly) {
        if (!have_w) {
            return 0;
        }
        if (all_below(poly)) {
            return 2;
        }
        D3 c = centroid(poly);
        bool above = W.covered(c, D);
        if (!above && !(G > 0.0 && W.covered(c, D, G))) {
            return 0;
        }
        for (const D3 &v : poly) {
            D3 q = v + (c - v) * 0.1;
            if (above && W.covered(q, D)) {
                continue;
            }
            above = false;
            if (!(G > 0.0 && W.covered(q, D, G))) {
                return 0;
            }
        }
        return above ? 1 : 2;
    };
    // coplanar down faces (coplanar_down, 0.9.2, gsa1_090_collision.md F6): a kept down piece lying exactly on a walkable
    // polygon (facing the other way, 0 units apart) loses the part over that polygon (its vertical prism: cut as the
    // hidden-face removal cuts). The rules above need a gap (t > 0.01) or the whole piece covered; rp_nycity's down face
    // at z 640 half over a floor at z 640 let Knuckles fall through.
    std::vector<uint32_t> cand, mark;
    uint32_t stamp = 0;
    std::vector<std::vector<D3>> pieces, next;
    std::vector<D3> inside, front, back;
    std::vector<Plane> prism;
    std::vector<const Plane *> pp;
    auto coplanar_cut = [&](const std::vector<D3> &fr, const D3 &fn) {
        pieces.clear();
        pieces.push_back(fr);
        double x0 = 1e300, y0 = 1e300, x1 = -1e300, y1 = -1e300;
        for (const D3 &p : fr) {
            x0 = std::min(x0, p.x);
            y0 = std::min(y0, p.y);
            x1 = std::max(x1, p.x);
            y1 = std::max(y1, p.y);
        }
        if (!std::isfinite(x0 + x1 + y0 + y1)) {
            return false;
        }
        const double df = dot(fn, centroid(fr));
        W.near(x0 - 0.1, y0 - 0.1, x1 + 0.1, y1 + 0.1, cand, mark, stamp);
        bool changed = false;
        for (uint32_t id : cand) {
            const WalkIndex::Poly &P = W.polys[id];
            if (dot(P.n, fn) > -0.9999 || std::fabs(P.d + df) > 0.05 || P.xy.size() < 3) {
                continue;   // not on the piece's plane facing the other way
            }
            double px0 = 1e300, py0 = 1e300, px1 = -1e300, py1 = -1e300;
            for (const P2 &q : P.xy) {
                px0 = std::min(px0, q.u);
                py0 = std::min(py0, q.v);
                px1 = std::max(px1, q.u);
                py1 = std::max(py1, q.v);
            }
            if (px0 > x1 + 0.05 || px1 < x0 - 0.05 || py0 > y1 + 0.05 || py1 < y0 - 0.05) {
                continue;
            }
            prism.clear();
            const size_t n = P.xy.size();
            for (size_t i = 0; i < n; i++) {
                const P2 &a = P.xy[i], &b = P.xy[(i + 1) % n];
                double ex = b.u - a.u, ey = b.v - a.v, l = std::sqrt(ex * ex + ey * ey);
                if (!(l > 1e-9)) {
                    continue;
                }
                D3 nn{ey / l, -ex / l, 0.0};   // outward (the polygon is counter-clockwise seen from above)
                prism.push_back(Plane{nn, nn.x * a.u + nn.y * a.v, true});
            }
            if (prism.size() < 3) {
                continue;
            }
            pp.clear();
            for (const Plane &pl : prism) {
                pp.push_back(&pl);
            }
            changed |= cut_by_volume(pieces, fn, false, pp, next, inside, front, back);
            if (pieces.empty()) {
                break;
            }
        }
        return changed;
    };
    std::vector<std::vector<D3>> keep, front_only;
    std::vector<Vis> add;
    for (Vis &v : vis) {
        if (v.kind == 2 || v.f->n.z > -0.5) {
            continue;
        }
        if (v.f->curved) {
            st.curved_one_way += (uint32_t)v.frags.size();   // a loop's ceiling: left as it is
            continue;
        }
        const bool flat = fo && v.f->n.z <= kFrontOnlyNz;
        keep.clear();
        front_only.clear();
        for (std::vector<D3> &fr : v.frags) {
            int how = fr.size() >= 3 ? all_covered(fr) : 0;
            if (how == 2) {
                st.low_ceilings++;   // first: no character fits under it (Review R.5.1 b)
            } else if (how == 1 || (v.f->one_way && fr.size() >= 3)) {
                if (how == 1 && !v.f->one_way) {
                    st.one_way_cross++;
                }
                if (flat && room_below(fr)) {
                    st.one_way_front_only++;
                    front_only.push_back(std::move(fr));   // a ceiling from below, nothing from above
                } else if (flat) {
                    st.front_only_no_room++;               // nothing under it: left out
                }
            } else if (opt.coplanar_down && fr.size() >= 3 && coplanar_cut(fr, v.f->n)) {
                st.coplanar_cut++;
                for (std::vector<D3> &p : pieces) {
                    keep.push_back(std::move(p));
                }
            } else {
                keep.push_back(std::move(fr));
            }
        }
        v.frags.swap(keep);
        if (!front_only.empty()) {
            made.push_back(*v.f);
            SFace &m = made.back();
            m.surface |= SA1_SURFACE_FRONT_ONLY;
            m.one_way = false;
            add.push_back(Vis{&m, v.kind, std::move(front_only), v.stair_cut, v.boxed, v.lo, v.hi});
            front_only = std::vector<std::vector<D3>>();
        }
    }
    for (Vis &a : add) {
        vis.push_back(std::move(a));
    }
    if (disp) {
        std::vector<D3> t3(3);
        for (DispTri &t : *disp) {
            if (t.n.z > -0.5) {
                continue;
            }
            t3[0] = t.a;
            t3[1] = t.b;
            t3[2] = t.c;
            int how = all_covered(t3);
            if (how == 1 && fo && t.n.z <= kFrontOnlyNz && !t.drop && room_below(t3)) {
                t.surface |= SA1_SURFACE_FRONT_ONLY;   // a displacement's flat underside: front-only as well
                st.one_way_front_only++;
                st.one_way_disp_tris++;
            } else if (how) {
                st.front_only_no_room += how == 1 && fo && t.n.z <= kFrontOnlyNz && !t.drop;
                t.drop = true;
                (how == 1 ? st.one_way_disp_tris : st.low_ceilings)++;
            }
        }
    }
}

// thin stacks (thin_stacks, 0.9.2: sadc docs/research/gsa1_090_collision.md C2 / F3 with its review R.3.8, R.4.7;
// emulated there on the triangles as coll_diag --fix-thin2 16, which took gm_highway14800's falls at the owner's own
// fall sites from 33 of 60 to 0 of 60 together with libsa1's F2). The steep pieces (|n.z| < 0.5) of the visible faces
// and the steep displacement triangles, single- or double-sided, of any solid: in rank order (double-sided first, then
// the lower solid index, the displacements after the solids) a piece is left out when, at every sample point (its
// centroid and its corners 10 % in), a parallel steep piece of a lower rank that is kept (|dot| >= 0.9, either facing)
// lies within thin_wall_max along -n or +n (nearest first); the pieces it found become double-sided and take its
// surface type as their tag's second slot (and its no-climbing). A second pass, from the highest rank down, leaves
// out a piece that took nothing in and is covered everywhere by kept pieces of any rank (a smaller piece of a lower
// rank in front of a larger one: a tapered hull's narrow side, a thin panel on a wall); a piece that took another in
// stays, so no stack moves by more than thin_wall_max. SA1's TOUCH (8C029B00) averages the push-backs of one land
// object's polygons and touches a single-sided polygon from behind: two faces back to back, two thin solids side by
// side, displacement walls on both sides of a brush or a tapered prop hull held the sphere between opposite push-backs
// (the fence trap) or let it through (wall clips, and floors left with a third of their lift). A large face is never
// left out for a small one flush in front of it (its other sample points are not covered).
void thin_stacks(std::vector<Vis> &vis, std::vector<DispTri> *disp, const BspWorldOptions &opt, std::deque<SFace> &made,
                 BspWorldStats &st)
{
    const double T = (double)opt.thin_wall_max;
    if (!opt.thin_stacks || !(T > 0.0)) {
        return;
    }
    const uint32_t kDisp = UINT32_MAX;
    struct F {
        D3 n;
        double d;
        const std::vector<D3> *poly;
        uint32_t vi, fi;                 // vis[vi].frags[fi], or (*disp)[fi] (vi == kDisp)
        const SFace *face;               // nullptr: a displacement triangle
        D3 lo, hi;
        uint64_t rank;
        uint16_t sp;
        bool ds, nclimb;
        bool dropped, absorbed, also_nclimb;
        uint16_t also;
    };
    std::vector<F> fs;
    std::vector<std::vector<int32_t>> fidx(vis.size());
    std::vector<std::vector<D3>> dpoly;
    auto area_ok = [](const std::vector<D3> &p) { return p.size() >= 3 && 0.5 * length(newell(p)) > 0.25; };
    auto box_of = [](const std::vector<D3> &p, D3 &lo, D3 &hi) {
        lo = hi = p[0];
        for (const D3 &q : p) {
            lo = dmin(lo, q);
            hi = dmax(hi, q);
        }
    };
    uint64_t seq = 0;
    for (size_t vi = 0; vi < vis.size(); vi++) {
        const Vis &v = vis[vi];
        const SFace &f = *v.f;
        if (v.kind == 2 || (f.surface & SA1_SURFACE_WATER) || !(std::fabs(f.n.z) < 0.5)) {
            continue;
        }
        if (f.curved) {
            st.curved_thin_stacks += (uint32_t)v.frags.size();   // 0.9.3: a loop's surface is never stacked (R.2.2)
            continue;
        }
        fidx[vi].assign(v.frags.size(), -1);
        for (size_t fi = 0; fi < v.frags.size(); fi++) {
            const std::vector<D3> &p = v.frags[fi];
            seq++;
            if (!area_ok(p)) {
                continue;
            }
            F e;
            e.n = f.n;
            e.d = dot(f.n, centroid(p));
            e.poly = &p;
            e.vi = (uint32_t)vi;
            e.fi = (uint32_t)fi;
            e.face = &f;
            box_of(p, e.lo, e.hi);
            e.ds = (f.surface & SA1_SURFACE_DOUBLE_SIDED) != 0;
            e.rank = (e.ds ? 0ull : 1ull << 40) + seq;
            e.sp = f.sp;
            e.nclimb = (f.surface & SA1_SURFACE_NO_CLIMB) != 0;
            e.dropped = e.absorbed = e.also_nclimb = false;
            e.also = kNoSurface;
            fidx[vi][fi] = (int32_t)fs.size();
            fs.push_back(e);
        }
    }
    if (disp) {
        dpoly.reserve(disp->size());
        for (size_t i = 0; i < disp->size(); i++) {
            const DispTri &t = (*disp)[i];
            seq++;
            if (t.drop || !(std::fabs(t.n.z) < 0.5) || !(length(t.n) > 0.5)) {
                continue;
            }
            dpoly.push_back({t.a, t.b, t.c});
            if (!area_ok(dpoly.back())) {
                dpoly.pop_back();
                continue;
            }
            F e;
            e.n = t.n;
            e.d = dot(t.n, t.a);
            e.poly = &dpoly.back();
            e.vi = kDisp;
            e.fi = (uint32_t)i;
            e.face = nullptr;
            box_of(dpoly.back(), e.lo, e.hi);
            e.ds = (t.surface & SA1_SURFACE_DOUBLE_SIDED) != 0;
            e.rank = (e.ds ? 0ull : 1ull << 40) + seq;
            e.sp = t.sp;
            e.nclimb = (t.surface & SA1_SURFACE_NO_CLIMB) != 0;
            e.dropped = e.absorbed = e.also_nclimb = false;
            e.also = kNoSurface;
            fs.push_back(e);
        }
    }
    if (fs.size() < 2) {
        return;
    }
    // 2D bins (x, y) of the pieces' boxes grown by T: a sample point's bin holds every piece within T of it
    const double kBin = 128.0;
    auto key = [](int64_t x, int64_t y) { return ((uint64_t)(uint32_t)(int32_t)x << 32) | (uint32_t)(int32_t)y; };
    std::unordered_map<uint64_t, std::vector<uint32_t>> bins;
    std::vector<uint32_t> big;
    for (uint32_t i = 0; i < (uint32_t)fs.size(); i++) {
        const F &e = fs[i];
        if (!std::isfinite(e.lo.x + e.lo.y + e.hi.x + e.hi.y) || std::fabs(e.lo.x) > kMaxCoord ||
            std::fabs(e.hi.x) > kMaxCoord || std::fabs(e.lo.y) > kMaxCoord || std::fabs(e.hi.y) > kMaxCoord) {
            big.push_back(i);
            continue;
        }
        int64_t x0 = (int64_t)std::floor((e.lo.x - T - 0.1) / kBin), x1 = (int64_t)std::floor((e.hi.x + T + 0.1) / kBin);
        int64_t y0 = (int64_t)std::floor((e.lo.y - T - 0.1) / kBin), y1 = (int64_t)std::floor((e.hi.y + T + 0.1) / kBin);
        if ((x1 - x0 + 1) * (y1 - y0 + 1) > 4096) {
            big.push_back(i);
            continue;
        }
        for (int64_t x = x0; x <= x1; x++) {
            for (int64_t y = y0; y <= y1; y++) {
                bins[key(x, y)].push_back(i);
            }
        }
    }
    auto inside = [](const F &q, const D3 &x, double tol) {
        const std::vector<D3> &p = *q.poly;
        for (size_t k = 0; k < p.size(); k++) {
            D3 e = p[(k + 1) % p.size()] - p[k];
            if (dot(cross(e, x - p[k]), q.n) < -tol * length(e)) {
                return false;
            }
        }
        return true;
    };
    // the nearest kept piece (of a lower rank unless any_rank) along dir from p (within -0.05 .. T), -1: none
    bool any_rank = false;
    auto probe = [&](const D3 &p, const D3 &dir, uint32_t me) -> int64_t {
        const F &m = fs[me];
        int64_t best = -1;
        double bt = T + 1.0;
        auto test = [&](uint32_t c) {
            const F &q = fs[c];
            if (c == me || q.dropped || (!any_rank && q.rank >= m.rank) || (q.face && q.face == m.face) ||
                p.x < q.lo.x - T - 0.1 || p.x > q.hi.x + T + 0.1 || p.y < q.lo.y - T - 0.1 || p.y > q.hi.y + T + 0.1 ||
                p.z < q.lo.z - T - 0.1 || p.z > q.hi.z + T + 0.1 || std::fabs(dot(q.n, m.n)) < 0.9) {
                return;
            }
            double den = dot(q.n, dir);
            if (std::fabs(den) < 1e-6) {
                return;
            }
            double t = (q.d - dot(q.n, p)) / den;
            if (t < -0.05 || t > T + 0.01 || t >= bt || !inside(q, p + dir * t, 0.05)) {
                return;
            }
            bt = t;
            best = c;
        };
        auto it = bins.find(key((int64_t)std::floor(p.x / kBin), (int64_t)std::floor(p.y / kBin)));
        if (it != bins.end()) {
            for (uint32_t c : it->second) {
                test(c);
            }
        }
        for (uint32_t c : big) {
            test(c);
        }
        return best;
    };
    std::vector<uint32_t> order(fs.size());
    for (uint32_t i = 0; i < (uint32_t)order.size(); i++) {
        order[i] = i;
    }
    std::sort(order.begin(), order.end(), [&](uint32_t a, uint32_t b) { return fs[a].rank < fs[b].rank; });
    std::vector<D3> samples;
    std::vector<int64_t> hits;
    auto stack = [&](uint32_t me) {
        F &m = fs[me];
        const std::vector<D3> &p = *m.poly;
        D3 c = centroid(p);
        samples.clear();
        samples.push_back(c);
        for (const D3 &v : p) {
            samples.push_back(v + (c - v) * 0.1);
        }
        hits.clear();
        for (const D3 &s : samples) {
            int64_t h = probe(s, m.n * -1.0, me);
            if (h < 0) {
                h = probe(s, m.n, me);
            }
            if (h < 0) {
                break;
            }
            hits.push_back(h);
        }
        if (hits.size() != samples.size()) {
            return;   // not covered everywhere: kept
        }
        m.dropped = true;
        st.thin_stack_faces++;
        for (int64_t h : hits) {
            F &k = fs[(size_t)h];
            k.absorbed = true;
            if (k.also == kNoSurface && m.sp != kNoSurface && m.sp != k.sp) {
                k.also = m.sp;
            }
            k.also_nclimb |= m.nclimb;
        }
    };
    // 1: in rank order, covered by kept pieces of a lower rank (of a stack the lowest rank stays)
    for (uint32_t me : order) {
        stack(me);
    }
    // 2: from the highest rank down, a piece that took nothing in and is covered by kept pieces of any rank: a smaller
    // piece of a lower rank in front of a larger one (pass 1 keeps both; the larger is never covered by it). A piece that
    // took another in stays (what it covers must stay covered: no stack collapses by more than thin_wall_max).
    any_rank = true;
    for (size_t i = order.size(); i-- > 0;) {
        if (!fs[order[i]].dropped && !fs[order[i]].absorbed) {
            stack(order[i]);
        }
    }
    // the result: dropped pieces out; absorbing pieces double-sided (vis: a copy of the face per (slot, no-climbing))
    for (const F &e : fs) {
        st.thin_stacks += e.absorbed && !e.dropped;
        if (e.vi != kDisp) {
            continue;
        }
        DispTri &t = (*disp)[e.fi];
        if (e.dropped) {
            t.drop = true;
        } else if (e.absorbed) {
            t.surface |= SA1_SURFACE_DOUBLE_SIDED | (e.also_nclimb ? SA1_SURFACE_NO_CLIMB : 0u);
            if (t.sp_also == kNoSurface && e.also != t.sp) {
                t.sp_also = e.also;
            }
        }
    }
    const size_t nv = vis.size();
    for (size_t vi = 0; vi < nv; vi++) {
        if (fidx[vi].empty()) {
            continue;
        }
        std::vector<std::vector<D3>> stay;
        std::map<std::pair<uint16_t, bool>, std::vector<std::vector<D3>>> groups;
        for (size_t fi = 0; fi < vis[vi].frags.size(); fi++) {
            int32_t k = fidx[vi][fi];
            if (k < 0 || (!fs[(size_t)k].dropped && !fs[(size_t)k].absorbed)) {
                stay.push_back(std::move(vis[vi].frags[fi]));
            } else if (!fs[(size_t)k].dropped) {
                groups[{fs[(size_t)k].also, fs[(size_t)k].also_nclimb}].push_back(std::move(vis[vi].frags[fi]));
            }
        }
        vis[vi].frags.swap(stay);
        for (auto &g : groups) {
            made.push_back(*vis[vi].f);
            SFace &m = made.back();
            m.surface |= SA1_SURFACE_DOUBLE_SIDED | (g.first.second ? SA1_SURFACE_NO_CLIMB : 0u);
            if (m.sp_also == kNoSurface && g.first.first != m.sp) {
                m.sp_also = g.first.first;
            }
            Vis nvis{&m, vis[vi].kind, std::move(g.second), vis[vi].stair_cut, vis[vi].boxed, vis[vi].lo, vis[vi].hi};
            vis.push_back(std::move(nvis));
        }
    }
}

// the visible pieces as triangles: the pieces of a face merged again where their union is convex (fewer and less
// slender triangles: each one counts against the NEAR-poly list wherever its bounding sphere reaches), cut into cells
// (tess_max), each piece a fan (consecutive triangles of one face with one surface word)
bool emit(std::vector<Vis> &vis, const BspWorldOptions &opt, TriSink &sink, BspWorldStats &st, std::string &err)
{
    std::vector<std::vector<D3>> cells;
    for (Vis &v : vis) {
        const SFace &f = *v.f;
        merge_coplanar(v.frags, f.n, v.stair_cut ? 256 : 64);
        for (std::vector<D3> &fr : v.frags) {
            dedupe(fr);
            if (fr.size() < 3) {
                continue;
            }
            if (opt.guard && v.boxed) {
                // the guard (GRID-GUARD): a piece of a solid's face outside the solid's box + 1 unit
                bool out = false;
                for (const D3 &p : fr) {
                    out |= p.x < v.lo.x - 1.0 || p.y < v.lo.y - 1.0 || p.z < v.lo.z - 1.0 || p.x > v.hi.x + 1.0 ||
                           p.y > v.hi.y + 1.0 || p.z > v.hi.z + 1.0;
                }
                if (out) {
                    st.frags_outside++;
                    continue;
                }
            }
            st.face_fragments++;
            cells.clear();
            // the tag's second slot: a thin wall's other side, or the mark of a face the engine never draws
            const uint16_t also = (f.sp != kNoSurface && f.sp_also == kNoSurface &&
                                   (f.sky || f.clip_only || (f.flags & SURF_NODRAW))) ? kHiddenSurface : f.sp_also;
            if (opt.tess_max > 0.0f && tessellate(fr, f.n, (double)opt.tess_max, cells)) {
                st.tessellated++;
            } else {
                cells.push_back(fr);
            }
            for (const std::vector<D3> &cell : cells) {
                for (size_t k = 1; k + 1 < cell.size(); k++) {
                    if (!sink.add(cell[0], cell[k], cell[k + 1], f.surface, surface_tag(f.sp, also))) {
                        continue;
                    }
                    if (v.kind == 2) {
                        st.tris_water++;
                    } else {
                        st.tris_solid++;
                    }
                    if (v.kind == 3) {
                        st.tris_extra++;
                    }
                    if (f.surface & SA1_SURFACE_NO_CLIMB) {
                        st.tris_noclimb++;
                    }
                    if (f.sky) {
                        st.tris_sky++;
                    }
                    if (f.flags & SURF_NODRAW) {
                        st.tris_nodraw++;
                    }
                    if (f.clip_only) {
                        st.tris_clip++;
                    }
                    if (f.surface & SA1_SURFACE_STAIRS) {
                        st.tris_stairs++;
                    }
                }
            }
        }
        if (sink.overflow) {
            err = format("the map has more than %u collision triangles", (unsigned)sink.max);
            return false;
        }
    }
    return true;
}

// a displacement point a sane map can have (the emitted triangles are limited to +-65536 anyway)
bool disp_point_ok(const D3 &p)
{
    return std::isfinite(p.x) && std::isfinite(p.y) && std::isfinite(p.z) && std::fabs(p.x) <= 65536.0 &&
           std::fabs(p.y) <= 65536.0 && std::fabs(p.z) <= 65536.0;
}

// the displacements' triangles (Valve's corner order; the base face's plane normal and the map's walkable tags
// decide the winding, see bsp.hpp)
void build_disp(const BspData &w, const BspWorldOptions &opt, std::vector<DispTri> &out, BspWorldStats &st,
                const BspSurfaceSlots *slots, std::vector<DispFoot> *feet = nullptr)
{
    std::vector<D3> g;
    std::vector<DispTri> tri;
    for (size_t d = 0; d < w.ndispinfo; d++) {
        uint32_t n = 0;
        D3 corners[4], normal;
        bool side = false;
        // vbsp writes minTess = the displacement's surface flags | 0x80000000; SURF_NOHULL_COLL (0x4): the engine's hull
        // traces pass it (Source SDK 2013 dispcoll_common.cpp), so the player walks through it - leave it out
        // (disp_nohull, gsa1_090_water.md WTR-DISP; 0x2-only, no physics collision, keeps the player's hull: it stays)
        const uint32_t mt = (uint32_t)w.dispinfo()[d].min_tess;
        if (opt.disp_nohull && (mt & 0x80000000u) && (mt & 0x4u)) {
            st.displacements_nohull++;
            continue;
        }
        if (!w.disp_grid(d, opt.disp_transpose, n, g, corners, normal, side)) {
            st.displacements_skipped++;
            continue;
        }
        st.displacements++;
        if (side) {
            st.disp_back_faces++;
        }
        D3 ref = (opt.disp_side_flip && side) ? normal * -1.0 : normal;
        double s = dot(cross(corners[1] - corners[0], corners[3] - corners[0]), ref);
        // the material's surface types: $surfaceprop, and $surfaceprop2 where the blend's alpha is high
        const DDispInfo &dinfo = w.dispinfo()[d];
        const int32_t face_ti = w.faces()[dinfo.map_face].texinfo;
        const uint16_t sp1 = w.texinfo_slot(slots, face_ti), sp2 = w.texinfo_slot(slots, face_ti, true);
        auto alpha_at = [&](const D3 *p) {
            size_t idx = (size_t)(p - g.data());
            float a = w.dispverts()[(size_t)dinfo.vert_start + idx].alpha;
            return std::isfinite(a) ? (double)a : 0.0;
        };
        tri.clear();
        for (uint32_t r = 0; r + 1 < n; r++) {
            for (uint32_t c = 0; c + 1 < n; c++) {
                const D3 &a = g[(size_t)r * n + c];
                const D3 &b = g[(size_t)r * n + c + 1];
                const D3 &cc = g[(size_t)(r + 1) * n + c];
                const D3 &dd = g[(size_t)(r + 1) * n + c + 1];
                // the loop a -> cc -> dd -> b turns like (corner1 - corner0) x (corner3 - corner0)
                const D3 *t[2][3];
                if (((r + c) & 1u) == 0) {
                    t[0][0] = &a; t[0][1] = &cc; t[0][2] = &dd;
                    t[1][0] = &a; t[1][1] = &dd; t[1][2] = &b;
                } else {
                    t[0][0] = &a; t[0][1] = &cc; t[0][2] = &b;
                    t[1][0] = &cc; t[1][1] = &dd; t[1][2] = &b;
                }
                for (int k = 0; k < 2; k++) {
                    if (!disp_point_ok(*t[k][0]) || !disp_point_ok(*t[k][1]) || !disp_point_ok(*t[k][2])) {
                        // a damaged map (vertex or offset lumps): left out here, before the one-way index and the
                        // emission (bins over unbounded coordinates would never end)
                        st.tris_out_of_range++;
                        continue;
                    }
                    DispTri dt;
                    dt.a = *t[k][0];
                    dt.b = s >= 0.0 ? *t[k][1] : *t[k][2];
                    dt.c = s >= 0.0 ? *t[k][2] : *t[k][1];
                    dt.sp = sp1;
                    if (sp2 != kNoSurface && alpha_at(t[k][0]) + alpha_at(t[k][1]) + alpha_at(t[k][2]) > kDispBlendAlpha) {
                        dt.sp = sp2;
                        st.disp_tris_blend++;
                    }
                    D3 nn = cross(dt.b - dt.a, dt.c - dt.a);
                    double l = length(nn);
                    dt.n = l > 1e-12 ? nn * (1.0 / l) : D3{0, 0, 0};
                    dt.drop = false;
                    tri.push_back(dt);
                }
            }
        }
        // the map's own walkable tags (DISP_TRIS, one per triangle in the engine's order: vbsp sets the walkable bit
        // when the triangle's normal in the ENGINE's winding has z >= 0.7): when the counts of up-facing triangles in
        // this winding and in the reversed one differ, the one closer to the tagged count is the engine's
        const DDispInfo &di = w.dispinfo()[d];
        size_t nt = 2u * (size_t)(n - 1) * (size_t)(n - 1);
        if (opt.disp_tags && !opt.disp_side_flip && w.ndisptris && di.tri_start >= 0 &&
            (size_t)di.tri_start + nt <= w.ndisptris && tri.size() == nt) {
            long ours = 0, rev = 0, tagged = 0;
            for (const DispTri &t : tri) {
                ours += t.n.z >= 0.7;
                rev += -t.n.z >= 0.7;
            }
            for (size_t i = 0; i < nt; i++) {
                tagged += (w.disptris()[(size_t)di.tri_start + i] & DISPTRI_TAG_WALKABLE) != 0;
            }
            if (ours != rev) {
                st.disp_tag_checked++;
                if (std::labs(ours - tagged) > std::labs(rev - tagged)) {
                    st.disp_tag_reversed++;
                    for (DispTri &t : tri) {
                        std::swap(t.b, t.c);
                        t.n = t.n * -1.0;
                    }
                }
            }
        }
        if (feet && !tri.empty()) {
            // the footprint for disp_cover: the XY hull of the points (a wall's displacement has next to none: left out)
            DispFoot F;
            std::vector<P2> pts;
            pts.reserve(g.size());
            F.x0 = F.y0 = F.zmin = 1e300;
            F.x1 = F.y1 = F.zmax = -1e300;
            for (const D3 &p : g) {
                if (!disp_point_ok(p)) {
                    continue;
                }
                pts.push_back(P2{p.x, p.y});
                F.x0 = std::min(F.x0, p.x);
                F.y0 = std::min(F.y0, p.y);
                F.x1 = std::max(F.x1, p.x);
                F.y1 = std::max(F.y1, p.y);
                F.zmin = std::min(F.zmin, p.z);
                F.zmax = std::max(F.zmax, p.z);
            }
            if (pts.size() >= 3) {
                hull2(pts, F.hull);
                if (F.hull.size() >= 3 && area2(F.hull) > 16.0) {
                    F.first = out.size();
                    F.count = tri.size();
                    feet->push_back(std::move(F));
                }
            }
        }
        out.insert(out.end(), tri.begin(), tri.end());
    }
}

// buried displacement triangles (remove_hidden): a triangle whose corners all lie inside one closed solid (more than
// half a unit from each of its planes) is left out, as the brush faces inside solids are. Displacements are not
// clipped by brushes in the engine either; gm_freespace_13 has terrain 8 units under its brush floors, which the
// sphere reached from the floor above (stacked floors: the character bobbed into the floor and through it).
void bury_disp(const std::vector<Solid> &S, std::vector<DispTri> &dt, BspWorldStats &st)
{
    const double kCell = 512.0, eps = 0.5;
    std::unordered_map<uint64_t, std::vector<uint32_t>> cells;
    auto key = [](int64_t x, int64_t y) { return ((uint64_t)(uint32_t)(int32_t)x << 32) | (uint32_t)(int32_t)y; };
    for (size_t b = 0; b < S.size(); b++) {
        const Solid &s = S[b];
        if (!s.clipper || s.kind != 1 || std::fabs(s.lo.x) > kMaxCoord || std::fabs(s.hi.x) > kMaxCoord ||
            std::fabs(s.lo.y) > kMaxCoord || std::fabs(s.hi.y) > kMaxCoord) {
            continue;
        }
        int64_t x0 = (int64_t)std::floor(s.lo.x / kCell), x1 = (int64_t)std::floor(s.hi.x / kCell);
        int64_t y0 = (int64_t)std::floor(s.lo.y / kCell), y1 = (int64_t)std::floor(s.hi.y / kCell);
        if ((x1 - x0 + 1) * (y1 - y0 + 1) > 1024) {
            continue;   // the sky box and other huge brushes: nothing is buried in them
        }
        for (int64_t x = x0; x <= x1; x++) {
            for (int64_t y = y0; y <= y1; y++) {
                cells[key(x, y)].push_back((uint32_t)b);
            }
        }
    }
    auto inside = [&](const Solid &s, const D3 &p) {
        if (p.x < s.lo.x || p.x > s.hi.x || p.y < s.lo.y || p.y > s.hi.y || p.z < s.lo.z || p.z > s.hi.z) {
            return false;
        }
        for (const Plane &pl : s.planes) {
            if (dot(pl.n, p) - pl.d > -eps) {
                return false;
            }
        }
        return true;
    };
    for (DispTri &t : dt) {
        if (t.drop) {
            continue;
        }
        D3 c = (t.a + t.b + t.c) * (1.0 / 3.0);
        auto it = cells.find(key((int64_t)std::floor(c.x / kCell), (int64_t)std::floor(c.y / kCell)));
        if (it == cells.end()) {
            continue;
        }
        for (uint32_t b : it->second) {
            if (inside(S[b], t.a) && inside(S[b], t.b) && inside(S[b], t.c)) {
                t.drop = true;
                st.disp_buried++;
                break;
            }
        }
    }
}

// up faces buried under displacement ground (disp_cover, 0.9.3; the coll-tunnel diagnosis of the 0.9.2 owner notes "some
// sinking into the ground", gm_construct_in_flatgrass_v3's spot (-1834 -36): emulated there per triangle as DISP-COVER,
// gm_highway14800's random play went from 61 frames with the feet more than 4 units under the face above them to 1, the
// deepest from 33.8 to 4.1 units). bury_disp leaves out displacement triangles inside brushes; this is the other way
// round: the parts of a solid's or a hull's up-facing piece (n.z >= 0.5; water stays) that lie under a displacement are
// left out where the displacement ground is over them everywhere - at every sample point (the centroid, the corners 10 %
// in, inner points at most `grid` apart) the nearest displacement surface above, 0.5 .. disp_cover_max away, faces up, and
// no down face (a solid's piece or a down-facing displacement triangle) lies between: that would make the space a room (a
// tunnel or a cellar under the terrain). The piece is cut along the displacement's footprint (the XY hull of its points);
// where the ground over the footprint is mixed (it crosses the face, or a room is under part of it), along each of the
// displacement's triangles and the line where the triangle rises 0.5 above the face. A cut is made only where a part is
// left out (elsewhere the piece stays whole). In the engine a displacement is a surface and the brush it was made of is
// gone (vbsp), so a brush top under the ground is never seen; within a sphere's reach under the ground it made the
// character sink into roads covered by flat ground, and a slab top in the void under the terrain held him there.
void disp_cover(std::vector<Vis> &vis, const std::vector<DispTri> &dt, const std::vector<DispFoot> &feet,
                const BspWorldOptions &opt, BspWorldStats &st)
{
    const double C = (double)opt.disp_cover_max, walk = 0.5;
    if (!(C > 0.0) || feet.empty() || dt.empty()) {
        return;
    }
    // the ground: the up-facing displacement triangles; the rooms: the down faces of the solids and the down-facing
    // displacement triangles, turned over (a WalkIndex holds polygons counter-clockwise seen from above)
    WalkIndex up, down;
    std::vector<D3> t3(3);
    for (const DispTri &t : dt) {
        if (t.drop) {
            continue;
        }
        t3[0] = t.a;
        t3[1] = t.b;
        t3[2] = t.c;
        if (t.n.z > 0.05) {
            up.add(t3, t.n);
        } else if (t.n.z < -0.05) {
            std::reverse(t3.begin(), t3.end());
            down.add(t3, t.n * -1.0);
        }
    }
    if (up.polys.empty()) {
        return;
    }
    std::vector<D3> rev;
    for (const Vis &v : vis) {
        if (v.kind == 2 || !(v.f->n.z < -0.05)) {
            continue;
        }
        for (const std::vector<D3> &fr : v.frags) {
            rev.assign(fr.rbegin(), fr.rend());
            down.add(rev, v.f->n * -1.0);
        }
    }
    // the footprints by bins
    const double kBin = 512.0;
    auto key = [](int64_t x, int64_t y) { return ((uint64_t)(uint32_t)(int32_t)x << 32) | (uint32_t)(int32_t)y; };
    std::unordered_map<uint64_t, std::vector<uint32_t>> bins;
    std::vector<uint32_t> bigf;
    for (uint32_t i = 0; i < (uint32_t)feet.size(); i++) {
        const DispFoot &F = feet[i];
        if (!std::isfinite(F.x0 + F.x1 + F.y0 + F.y1) || std::fabs(F.x0) > kMaxCoord || std::fabs(F.x1) > kMaxCoord ||
            std::fabs(F.y0) > kMaxCoord || std::fabs(F.y1) > kMaxCoord) {
            continue;
        }
        int64_t bx0 = (int64_t)std::floor(F.x0 / kBin), bx1 = (int64_t)std::floor(F.x1 / kBin);
        int64_t by0 = (int64_t)std::floor(F.y0 / kBin), by1 = (int64_t)std::floor(F.y1 / kBin);
        if ((bx1 - bx0 + 1) * (by1 - by0 + 1) > 4096) {
            bigf.push_back(i);
            continue;
        }
        for (int64_t bx = bx0; bx <= bx1; bx++) {
            for (int64_t by = by0; by <= by1; by++) {
                bins[key(bx, by)].push_back(i);
            }
        }
    }
    // a point of a face under the ground
    auto ground = [&](const D3 &q) {
        double tu = up.lowest(q, 0.5, C);
        if (!(tu <= C)) {
            return false;
        }
        return !(down.lowest(q, 0.5, tu - 0.5) <= tu - 0.5);
    };
    // the sample points of a convex piece of a face with normal n under the ground: 2 all, 1 some, 0 none
    std::vector<D3> smp;
    auto status = [&](const std::vector<D3> &poly, const D3 &n, double grid) {
        smp.clear();
        const D3 c = centroid(poly);
        smp.push_back(c);
        for (const D3 &p : poly) {
            smp.push_back(p + (c - p) * 0.1);
        }
        double x0 = 1e300, y0 = 1e300, x1 = -1e300, y1 = -1e300;
        for (const D3 &p : poly) {
            x0 = std::min(x0, p.x);
            y0 = std::min(y0, p.y);
            x1 = std::max(x1, p.x);
            y1 = std::max(y1, p.y);
        }
        double g = grid;
        if ((x1 - x0) * (y1 - y0) > 4096.0 * g * g) {
            g = std::sqrt((x1 - x0) * (y1 - y0) / 4096.0);
        }
        const double d = dot(n, poly[0]);
        const size_t m = poly.size();
        for (double x = x0 + 0.5 * g; x < x1; x += g) {
            for (double y = y0 + 0.5 * g; y < y1; y += g) {
                bool in = true;
                for (size_t i = 0; i < m && in; i++) {
                    const D3 &a = poly[i], &b = poly[(i + 1) % m];
                    double ex = b.x - a.x, ey = b.y - a.y;
                    in = ex * (y - a.y) - ey * (x - a.x) >= 0.5 * std::sqrt(ex * ex + ey * ey);
                }
                if (in) {
                    smp.push_back(D3{x, y, (d - n.x * x - n.y * y) / n.z});
                }
            }
        }
        bool any_in = false, any_out = false;
        for (const D3 &q : smp) {
            (ground(q) ? any_in : any_out) = true;
            if (any_in && any_out) {
                return 1;
            }
        }
        return any_in ? 2 : 0;
    };
    // poly cut by the vertical prism of the counter-clockwise XY polygon h: `in` (fewer than 3 points: none) and `outside`
    std::vector<D3> in, front, back;
    std::vector<std::vector<D3>> outside;
    auto split_prism = [&](const std::vector<D3> &poly, const P2 *h, size_t nh) {
        outside.clear();
        in = poly;
        for (size_t i = 0; i < nh && in.size() >= 3; i++) {
            const P2 &a = h[i], &b = h[(i + 1) % nh];
            double ex = b.u - a.u, ey = b.v - a.v, l = std::sqrt(ex * ex + ey * ey);
            if (!(l > 1e-9)) {
                continue;
            }
            const Plane pl{D3{ey / l, -ex / l, 0.0}, (ey * a.u - ex * a.v) / l, true};
            double dmn, dmx;
            plane_range(in, pl, dmn, dmx);
            if (dmx <= 0.01) {
                continue;   // inside this edge
            }
            if (dmn >= -0.01) {
                outside.push_back(in);   // wholly outside
                in.clear();
                break;
            }
            split_poly(in, pl, 0.01, front, back);
            if (!front.empty()) {
                outside.push_back(front);
            }
            in.swap(back);
        }
    };
    auto area = [](const std::vector<D3> &p) { return 0.5 * length(newell(p)); };
    std::vector<uint32_t> cand, mark(feet.size(), 0);
    uint32_t stamp = 0;
    std::vector<std::vector<D3>> result, work, next, R, R2, outF, outT;
    std::vector<D3> cov, unc;
    for (Vis &v : vis) {
        if (v.kind == 2 || v.f->n.z < walk || v.frags.empty()) {
            continue;
        }
        const D3 fn = v.f->n;
        const double fd = dot(fn, v.f->poly[0]);
        bool lost = false;
        result.clear();
        for (std::vector<D3> &fr : v.frags) {
            if (fr.size() < 3) {
                result.push_back(std::move(fr));
                continue;
            }
            double x0 = 1e300, y0 = 1e300, x1 = -1e300, y1 = -1e300, z0 = 1e300, z1 = -1e300;
            for (const D3 &p : fr) {
                x0 = std::min(x0, p.x);
                y0 = std::min(y0, p.y);
                z0 = std::min(z0, p.z);
                x1 = std::max(x1, p.x);
                y1 = std::max(y1, p.y);
                z1 = std::max(z1, p.z);
            }
            cand.clear();
            if (std::isfinite(x0 + x1 + y0 + y1) && std::fabs(x0) <= kMaxCoord && std::fabs(x1) <= kMaxCoord &&
                std::fabs(y0) <= kMaxCoord && std::fabs(y1) <= kMaxCoord) {
                stamp++;
                auto take = [&](uint32_t i) {
                    if (mark[i] == stamp) {
                        return;
                    }
                    mark[i] = stamp;
                    const DispFoot &F = feet[i];
                    if (F.x0 <= x1 && F.x1 >= x0 && F.y0 <= y1 && F.y1 >= y0 && F.zmax > z0 + 0.5 && F.zmin < z1 + C) {
                        cand.push_back(i);
                    }
                };
                int64_t bx0 = (int64_t)std::floor(x0 / kBin), bx1 = (int64_t)std::floor(x1 / kBin);
                int64_t by0 = (int64_t)std::floor(y0 / kBin), by1 = (int64_t)std::floor(y1 / kBin);
                if ((bx1 - bx0 + 1) * (by1 - by0 + 1) <= 4096) {
                    for (int64_t bx = bx0; bx <= bx1; bx++) {
                        for (int64_t by = by0; by <= by1; by++) {
                            auto it = bins.find(key(bx, by));
                            if (it != bins.end()) {
                                for (uint32_t i : it->second) {
                                    take(i);
                                }
                            }
                        }
                    }
                } else {
                    for (const auto &kv : bins) {
                        for (uint32_t i : kv.second) {
                            take(i);
                        }
                    }
                }
                for (uint32_t i : bigf) {
                    take(i);
                }
                std::sort(cand.begin(), cand.end());
            }
            if (cand.empty()) {
                result.push_back(std::move(fr));
                continue;
            }
            work.clear();
            work.push_back(std::move(fr));
            for (uint32_t fi : cand) {
                const DispFoot &F = feet[fi];
                next.clear();
                for (std::vector<D3> &q : work) {
                    split_prism(q, F.hull.data(), F.hull.size());
                    if (in.size() < 3) {
                        next.push_back(std::move(q));
                        continue;
                    }
                    const int s = status(in, fn, 64.0);
                    if (s == 2) {
                        st.disp_cover_pieces++;
                        st.disp_cover_area += area(in);
                        lost = true;
                        for (std::vector<D3> &o : outside) {
                            next.push_back(std::move(o));
                        }
                        continue;
                    }
                    if (s == 0) {
                        next.push_back(std::move(q));
                        continue;
                    }
                    // mixed: along the displacement's triangles and the lines where they rise 0.5 above the face
                    outF.swap(outside);
                    R.clear();
                    R.push_back(in);
                    bool changed = false;
                    for (size_t ti = F.first; ti < F.first + F.count && ti < dt.size(); ti++) {
                        const DispTri &T = dt[ti];
                        if (T.drop || !(T.n.z > 0.05)) {
                            continue;
                        }
                        const P2 tri[3] = {{T.a.x, T.a.y}, {T.b.x, T.b.y}, {T.c.x, T.c.y}};
                        const double tz1 = std::max(T.a.z, std::max(T.b.z, T.c.z));
                        // where the triangle is more than 0.5 above the face: g(x, y) = A x + B y + D0 > 0
                        const double A = fn.x / fn.z - T.n.x / T.n.z, B = fn.y / fn.z - T.n.y / T.n.z;
                        const double D0 = dot(T.n, T.a) / T.n.z - fd / fn.z - 0.5, L = std::sqrt(A * A + B * B);
                        R2.clear();
                        for (std::vector<D3> &S : R) {
                            double sz0 = 1e300;
                            for (const D3 &p : S) {
                                sz0 = std::min(sz0, p.z);
                            }
                            if (tz1 < sz0 + 0.5) {
                                R2.push_back(std::move(S));   // the triangle is lower everywhere
                                continue;
                            }
                            split_prism(S, tri, 3);
                            if (in.size() < 3) {
                                R2.push_back(std::move(S));
                                continue;
                            }
                            outT.swap(outside);
                            cov.clear();
                            unc.clear();
                            if (L > 1e-9) {
                                split_poly(in, Plane{D3{A / L, B / L, 0.0}, -D0 / L, true}, 0.01, cov, unc);
                            } else if (D0 > 0.0) {
                                cov = in;
                            }
                            if (cov.size() < 3 || status(cov, fn, 32.0) != 2) {
                                R2.push_back(std::move(S));
                                continue;
                            }
                            st.disp_cover_pieces++;
                            st.disp_cover_area += area(cov);
                            changed = true;
                            for (std::vector<D3> &o : outT) {
                                R2.push_back(std::move(o));
                            }
                            if (unc.size() >= 3) {
                                R2.push_back(unc);
                            }
                        }
                        R.swap(R2);
                    }
                    if (changed) {
                        lost = true;
                        for (std::vector<D3> &o : outF) {
                            next.push_back(std::move(o));
                        }
                        for (std::vector<D3> &r : R) {
                            next.push_back(std::move(r));
                        }
                    } else {
                        next.push_back(std::move(q));
                    }
                }
                work.swap(next);
                if (work.empty() || work.size() > 4096) {
                    break;   // gone, or cut into more pieces than a real map makes (a damaged file)
                }
            }
            for (std::vector<D3> &q : work) {
                result.push_back(std::move(q));
            }
        }
        v.frags.swap(result);
        if (lost) {
            st.disp_cover_faces++;
        }
    }
}

// the brushes of `mark`: 1 solid, 2 water, 0 skipped (stats as world_brushes etc.)
void classify(const BspData &w, const std::vector<uint8_t> &mark, const BspWorldOptions &opt, std::vector<uint8_t> &kind,
              BspWorldStats &st)
{
    const uint32_t solid_mask = CONTENTS_SOLID | CONTENTS_WINDOW | CONTENTS_GRATE | CONTENTS_MOVEABLE |
                                (opt.playerclip ? CONTENTS_PLAYERCLIP : 0u);
    kind.assign(w.nbrushes, 0);
    for (size_t b = 0; b < w.nbrushes; b++) {
        if (!mark[b]) {
            continue;
        }
        st.world_brushes++;
        const DBrush &br = w.brushes()[b];
        uint32_t ct = (uint32_t)br.contents;
        if (br.firstside < 0 || br.numsides < 1 || br.numsides > 256 ||
            (size_t)br.firstside + (size_t)br.numsides > w.nsides) {
            st.other_brushes++;
            continue;
        }
        if (ct & solid_mask) {
            kind[b] = 1;
            st.solid_brushes++;
        } else if (opt.water && (ct & (CONTENTS_WATER | CONTENTS_SLIME))) {
            kind[b] = 2;
            st.water_brushes++;
        } else {
            st.other_brushes++;
        }
        for (int32_t s = 0; s < br.numsides; s++) {
            const DBrushSide &sd = w.sides()[br.firstside + s];
            if (sd.dispinfo != 0 && sd.dispinfo != -1) {
                st.sides_with_dispinfo++;
            }
        }
    }
}

// 0.9.3 (disp_brush_exact): the side of brush br on `plane` IS the quad face with corners c (a displacement's base face):
// its polygon (the side clipped by the brush's other sides, as brush_faces makes it) has the four corners, within 1 unit,
// and the face's area, within 1 % + 1 square unit. The coll-tunnel diagnosis checked 10 maps: vbsp writes no displacement's
// own brush into the brush lump, so this holds for no brush of a real map; 0.9.2's test (the face's centre inside a brush
// with a side on its plane) dropped the brushes NEXT to a displacement on the same plane instead: the tunnel floors of
// gm_highway14800 (brushes 53-59 / 76-82 / 120-126 beside the flat displacements 682-688 / 816-826 / 862-870)
bool side_is_face(const BspData &w, const DBrush &br, uint32_t plane, const D3 c[4])
{
    std::vector<D3> poly, tmp;
    for (int32_t s = 0; s < br.numsides; s++) {
        const DBrushSide &sd = w.sides()[br.firstside + s];
        if ((uint32_t)sd.planenum != plane || sd.bevel || sd.planenum >= w.nplanes || !w.planes[sd.planenum].ok) {
            continue;
        }
        base_winding(w.planes[sd.planenum], poly);
        for (int32_t o = 0; o < br.numsides && poly.size() >= 3; o++) {
            const DBrushSide &so = w.sides()[br.firstside + o];
            if (o == s || so.bevel || so.planenum == sd.planenum || so.planenum >= w.nplanes || !w.planes[so.planenum].ok) {
                continue;
            }
            clip_back(poly, w.planes[so.planenum], 0.01, tmp);
        }
        dedupe(poly);
        if (poly.size() < 3) {
            continue;
        }
        bool corners = true;
        for (int k = 0; k < 4 && corners; k++) {
            double best = 1e300;
            for (const D3 &q : poly) {
                best = std::min(best, length(q - c[k]));
            }
            corners = best <= 1.0;
        }
        if (!corners) {
            continue;
        }
        D3 a{0, 0, 0};
        for (size_t i = 1; i + 1 < poly.size(); i++) {
            a = a + cross(poly[i] - poly[0], poly[i + 1] - poly[0]);
        }
        const double ap = 0.5 * length(a);
        const double aq = 0.5 * length(cross(c[1] - c[0], c[2] - c[0]) + cross(c[2] - c[0], c[3] - c[0]));
        if (std::fabs(ap - aq) <= 0.01 * aq + 1.0) {
            return true;
        }
    }
    return false;
}

}  // namespace

bool Bsp::build_world(const BspWorldOptions &opt, const std::vector<ConvexSolid> *extra,
                      std::vector<sa1_collision_tri> &out, BspWorldStats &st, std::string &err,
                      const BspSurfaceSlots *slots, std::vector<uint32_t> *tags)
{
    double t0 = now_ms();
    st = BspWorldStats();
    out.clear();
    if (tags) {
        tags->clear();
    }
    if (!load(err)) {
        return false;
    }
    const BspData &w = *data_;
    st.version = version_;
    st.revision = revision_;
    st.brushes = (uint32_t)w.nbrushes;
    const DModel &m0 = w.models()[0];
    if (!finite3(m0.mins) || !finite3(m0.maxs)) {
        err = "the world model has invalid bounds";
        return false;
    }
    for (int k = 0; k < 3; k++) {
        st.mins[k] = m0.mins[k];
        st.maxs[k] = m0.maxs[k];
    }

    // 1. the world model's brushes: every brush in a leaf reachable from model 0's head node; 2. classified
    std::vector<uint8_t> world_brush, kind;
    w.model_brushes(0, world_brush);
    classify(w, world_brush, opt, kind, st);

    // 3. brushes that carry a displacement: a side on the displacement face's plane, the face inside the brush, and
    // (disp_brush_exact, 0.9.3) that side IS the base face; a brush only beside it on the same plane stays (counted once)
    std::vector<uint8_t> disp_brush(w.nbrushes, 0), kept_brush;
    if (opt.displacements && opt.skip_displacement_brushes && w.ndispinfo) {
        if (opt.disp_brush_exact) {
            kept_brush.assign(w.nbrushes, 0);
        }
        std::vector<std::vector<uint32_t>> by_plane(w.nplanes);
        for (size_t b = 0; b < w.nbrushes; b++) {
            if (kind[b] != 1) {
                continue;
            }
            const DBrush &br = w.brushes()[b];
            for (int32_t s = 0; s < br.numsides; s++) {
                const DBrushSide &sd = w.sides()[br.firstside + s];
                if (sd.planenum < w.nplanes) {
                    by_plane[sd.planenum].push_back((uint32_t)b);
                }
            }
        }
        for (size_t d = 0; d < w.ndispinfo; d++) {
            const DDispInfo &di = w.dispinfo()[d];
            D3 c[4];
            if (!w.face_corners(di.map_face, c)) {
                continue;
            }
            D3 centre = (c[0] + c[1] + c[2] + c[3]) * 0.25;
            uint32_t pn = w.faces()[di.map_face].planenum;
            const uint32_t cands[2] = {pn, pn ^ 1u};
            for (uint32_t cand_plane : cands) {
                if (cand_plane >= w.nplanes) {
                    continue;
                }
                for (uint32_t b : by_plane[cand_plane]) {
                    if (disp_brush[b]) {
                        continue;
                    }
                    const DBrush &br = w.brushes()[b];
                    bool inside = true;
                    for (int32_t s = 0; s < br.numsides && inside; s++) {
                        const DBrushSide &sd = w.sides()[br.firstside + s];
                        if (sd.planenum >= w.nplanes || !w.planes[sd.planenum].ok) {
                            continue;
                        }
                        const Plane &p = w.planes[sd.planenum];
                        if (dot(p.n, centre) - p.d > 0.5) {
                            inside = false;
                        }
                    }
                    if (inside && opt.disp_brush_exact && !side_is_face(w, br, cand_plane, c)) {
                        kept_brush[b] = 1;
                        inside = false;
                    }
                    if (inside) {
                        disp_brush[b] = 1;
                        st.displacement_brushes++;
                    }
                }
            }
        }
        for (size_t b = 0; b < kept_brush.size(); b++) {
            st.disp_brushes_kept += kept_brush[b] && !disp_brush[b];
        }
    }

    // 4. the solids: brushes, then the extra convex solids (static props' hulls) - their faces; the curved surfaces
    // among them (0.9.3); then the rules (one-way / thin floors / thin walls)
    std::vector<Solid> S;
    S.reserve(w.nbrushes + (extra ? extra->size() : 0));
    brush_solids(w, world_brush, kind, disp_brush, S, slots);
    const size_t nbrush = S.size();
    if (extra) {
        for (const ConvexSolid &cs : *extra) {
            Solid s;
            if (!hull_solid(cs, s)) {
                st.extra_bad++;
                continue;
            }
            st.extra_solids++;
            st.extra_faces += (uint32_t)s.faces.size();
            if (!s.clipper) {
                st.extra_bad++;
            }
            S.push_back(std::move(s));
        }
    }
    detect_curved(S, opt, st);
    brush_rules(w, S, nbrush, opt, st, slots);
    for (size_t i = nbrush; i < S.size(); i++) {
        solid_rules(S[i], opt, st);
    }
    std::vector<SFace> ramps;
    std::vector<Vis> vis;
    clean(S, opt, true, ramps, vis, st);

    // 5. displacements (0.9.3: the up faces under their ground left out, before the one-way rule looks for walkable
    // faces); one-way across solids and displacements (front-only ceilings); thin stacks
    std::vector<DispTri> dt;
    if (opt.displacements) {
        std::vector<DispFoot> feet;
        build_disp(w, opt, dt, st, slots, opt.disp_cover_max > 0.0f ? &feet : nullptr);
        if (opt.remove_hidden) {
            bury_disp(S, dt, st);
        }
        disp_cover(vis, dt, feet, opt, st);
    }
    std::deque<SFace> made;
    cross_one_way(vis, &dt, opt, st, made);
    thin_stacks(vis, &dt, opt, made, st);

    TriSink sink;
    sink.out = &out;
    sink.max = opt.max_triangles;
    sink.tags = tags;
    if (opt.guard) {
        sink.bound(st.mins, st.maxs, 64.0);   // the world model's bounds + 64 units (GRID-GUARD)
    }
    out.reserve(w.nbrushes * 8 + dt.size() + 1024);
    if (tags) {
        tags->reserve(out.capacity());
    }
    if (!emit(vis, opt, sink, st, err)) {
        return false;
    }
    for (const DispTri &t : dt) {
        if (!t.drop && sink.add(t.a, t.b, t.c, t.surface, surface_tag(t.sp, t.sp_also))) {
            st.displacement_tris++;
            st.tris_solid++;
        }
    }
    if (sink.overflow) {
        err = format("the map has more than %u collision triangles", (unsigned)opt.max_triangles);
        return false;
    }

    // 6. kill plane below the world model
    if (opt.kill_plane) {
        double z = (double)st.mins[2] - (double)opt.kill_margin;
        double x0 = (double)st.mins[0] - 64.0, x1 = (double)st.maxs[0] + 64.0;
        double y0 = (double)st.mins[1] - 64.0, y1 = (double)st.maxs[1] + 64.0;
        if (x1 > x0 && y1 > y0 && std::fabs(z) < 65536.0) {
            D3 p0{x0, y0, z}, p1{x1, y0, z}, p2{x1, y1, z}, p3{x0, y1, z};
            if (sink.add(p0, p1, p2, SA1_SURFACE_KILL)) {
                st.tris_kill++;
            }
            if (sink.add(p0, p2, p3, SA1_SURFACE_KILL)) {
                st.tris_kill++;
            }
        }
    }
    st.tris = (uint32_t)out.size();
    st.tris_out_of_range += sink.out_of_range;   // (+ the displacement triangles build_disp left out)
    st.tris_outside = sink.outside;
    st.tris_tagged = sink.tagged;
    st.ms = now_ms() - t0;
    return true;
}

bool Bsp::build_model(int32_t model, const BspWorldOptions &opt, std::vector<sa1_collision_tri> &out,
                      BspWorldStats &st, std::string &err)
{
    double t0 = now_ms();
    st = BspWorldStats();
    out.clear();
    if (!load(err)) {
        return false;
    }
    const BspData &w = *data_;
    if (model <= 0 || (size_t)model >= w.nmodels) {
        err = format("the map has no brush model *%d", (int)model);
        return false;
    }
    st.version = version_;
    st.revision = revision_;
    st.brushes = (uint32_t)w.nbrushes;
    const DModel &md = w.models()[model];
    if (!finite3(md.mins) || !finite3(md.maxs)) {
        err = format("brush model *%d has invalid bounds", (int)model);
        return false;
    }
    for (int k = 0; k < 3; k++) {
        st.mins[k] = md.mins[k];
        st.maxs[k] = md.maxs[k];
    }
    std::vector<uint8_t> mark, kind, none;
    w.model_brushes(model, mark);
    classify(w, mark, opt, kind, st);
    std::vector<Solid> S;
    brush_solids(w, mark, kind, none, S, nullptr);   // no surface types (Review G4: moving objects)
    detect_curved(S, opt, st);
    brush_rules(w, S, S.size(), opt, st, nullptr);
    std::vector<SFace> ramps;
    std::vector<Vis> vis;
    clean(S, opt, false, ramps, vis, st);
    std::deque<SFace> made;
    cross_one_way(vis, nullptr, opt, st, made);
    thin_stacks(vis, nullptr, opt, made, st);
    TriSink sink;
    sink.out = &out;
    sink.max = opt.max_triangles;
    if (opt.guard) {
        sink.bound(st.mins, st.maxs, 64.0);   // the model's bounds + 64 units
    }
    if (!emit(vis, opt, sink, st, err)) {
        return false;
    }
    st.tris = (uint32_t)out.size();
    st.tris_out_of_range = sink.out_of_range;
    st.tris_outside = sink.outside;
    st.ms = now_ms() - t0;
    return true;
}

bool clean_solids(const std::vector<ConvexSolid> &solids, const BspWorldOptions &opt, std::vector<sa1_collision_tri> &out,
                  BspWorldStats &st, std::string &err, std::vector<uint32_t> *tags)
{
    double t0 = now_ms();
    st = BspWorldStats();
    out.clear();
    if (tags) {
        tags->clear();
    }
    std::vector<Solid> S;
    S.reserve(solids.size());
    D3 lo{1e300, 1e300, 1e300}, hi{-1e300, -1e300, -1e300};
    for (const ConvexSolid &cs : solids) {
        Solid s;
        if (!hull_solid(cs, s)) {
            st.extra_bad++;
            continue;
        }
        st.extra_solids++;
        st.extra_faces += (uint32_t)s.faces.size();
        if (!s.clipper) {
            st.extra_bad++;
        }
        lo = dmin(lo, s.lo);
        hi = dmax(hi, s.hi);
        S.push_back(std::move(s));
    }
    detect_curved(S, opt, st);   // 0.9.3: the faces of every hull first, then the rules
    for (Solid &s : S) {
        solid_rules(s, opt, st);
    }
    if (!S.empty()) {
        st.mins[0] = (float)lo.x;
        st.mins[1] = (float)lo.y;
        st.mins[2] = (float)lo.z;
        st.maxs[0] = (float)hi.x;
        st.maxs[1] = (float)hi.y;
        st.maxs[2] = (float)hi.z;
    }
    std::vector<SFace> ramps;
    std::vector<Vis> vis;
    clean(S, opt, false, ramps, vis, st);
    std::deque<SFace> made;
    cross_one_way(vis, nullptr, opt, st, made);
    thin_stacks(vis, nullptr, opt, made, st);   // a moving object's hulls too (gsa1_090_collision.md 8: C2 applies)
    TriSink sink;
    sink.out = &out;
    sink.max = opt.max_triangles;
    sink.tags = tags;
    if (opt.guard && !S.empty()) {
        sink.bound(st.mins, st.maxs, 64.0);   // the hulls' box + 64 units
    }
    if (!emit(vis, opt, sink, st, err)) {
        return false;
    }
    st.tris = (uint32_t)out.size();
    st.tris_out_of_range = sink.out_of_range;
    st.tris_outside = sink.outside;
    st.tris_tagged = sink.tagged;
    st.ms = now_ms() - t0;
    return true;
}

bool Bsp::displacement_grids(const BspWorldOptions &opt, std::vector<BspDispGrid> &out, std::string &err)
{
    out.clear();
    if (!load(err)) {
        return false;
    }
    const BspData &w = *data_;
    std::vector<D3> g;
    for (size_t d = 0; d < w.ndispinfo; d++) {
        BspDispGrid dg;
        D3 corners[4], normal;
        bool side = false;
        if (!w.disp_grid(d, opt.disp_transpose, dg.n, g, corners, normal, side)) {
            dg.n = 0;
            out.push_back(dg);
            continue;
        }
        for (int k = 0; k < 4; k++) {
            dg.corners[k][0] = (float)corners[k].x;
            dg.corners[k][1] = (float)corners[k].y;
            dg.corners[k][2] = (float)corners[k].z;
        }
        dg.pos.resize(g.size() * 3);
        for (size_t i = 0; i < g.size(); i++) {
            dg.pos[3 * i] = (float)g[i].x;
            dg.pos[3 * i + 1] = (float)g[i].y;
            dg.pos[3 * i + 2] = (float)g[i].z;
        }
        out.push_back(dg);
    }
    return true;
}

bool Bsp::entities(std::vector<BspEntity> &out, std::string &err)
{
    out.clear();
    std::vector<uint8_t> raw;
    size_t n = 0;
    if (!lump_raw(LUMP_ENTITIES, 1, 32u << 20, raw, n, err)) {
        return false;
    }
    size_t i = 0;
    auto ws = [&]() {
        while (i < n && (raw[i] == ' ' || raw[i] == '\t' || raw[i] == '\r' || raw[i] == '\n')) {
            i++;
        }
    };
    auto str = [&](std::string &s) -> bool {
        if (i >= n || raw[i] != '"') {
            return false;
        }
        size_t j = i + 1;
        while (j < n && raw[j] != '"' && raw[j] != 0) {
            j++;
        }
        if (j >= n || raw[j] != '"' || j - i - 1 > 4096) {
            return false;
        }
        s.assign((const char *)raw.data() + i + 1, j - i - 1);
        i = j + 1;
        return true;
    };
    while (true) {
        ws();
        if (i >= n || raw[i] == 0) {
            break;
        }
        if (raw[i] != '{') {
            err = format("entity lump: '{' expected at byte %u", (unsigned)i);
            return false;
        }
        i++;
        BspEntity e;
        while (true) {
            ws();
            if (i < n && raw[i] == '}') {
                i++;
                break;
            }
            std::string k, v;
            if (!str(k)) {
                err = format("entity lump: key expected at byte %u", (unsigned)i);
                return false;
            }
            ws();
            if (!str(v)) {
                err = format("entity lump: value expected at byte %u", (unsigned)i);
                return false;
            }
            if (e.kv.size() < 1024) {
                e.kv.emplace_back(std::move(k), std::move(v));
            }
        }
        out.push_back(std::move(e));
        if (out.size() > 65536) {
            err = "entity lump: too many entities";
            return false;
        }
    }
    return true;
}

bool Bsp::static_props(std::vector<BspStaticProp> &out, BspPropInfo &info, std::string &err)
{
    out.clear();
    info = BspPropInfo();
    if (!src_) {
        err = "no BSP opened";
        return false;
    }
    uint64_t ofs = 0, len = 0;
    uint16_t ver = 0;
    bool comp = false;
    if (!sprp_range(ofs, len, ver, comp, err)) {
        return false;
    }
    info.present = len > 0;
    info.version = ver;
    info.compressed = comp;
    if (len == 0) {
        return true;
    }
    if (comp) {
        err = "the static prop lump is LZMA-compressed (not supported yet)";
        return false;
    }
    if (len > (64u << 20) || len < 12) {
        err = "the static prop lump has an unexpected size";
        return false;
    }
    std::vector<uint8_t> b((size_t)len);
    if (!src_->read(ofs, b.data(), b.size())) {
        err = "cannot read the static prop lump";
        return false;
    }
    size_t pos = 0;
    auto rd_i32 = [&](int32_t &v) {
        if (pos + 4 > b.size()) {
            return false;
        }
        std::memcpy(&v, b.data() + pos, 4);
        pos += 4;
        return true;
    };
    int32_t nnames = 0, nleaves = 0, nprops = 0;
    if (!rd_i32(nnames) || nnames < 0 || nnames > 65536 || pos + (size_t)nnames * 128u > b.size()) {
        err = "the static prop lump's model names are damaged";
        return false;
    }
    std::vector<std::string> names((size_t)nnames);
    for (int32_t i = 0; i < nnames; i++) {
        const char *s = (const char *)b.data() + pos + (size_t)i * 128u;
        size_t l = 0;
        while (l < 128 && s[l]) {
            l++;
        }
        std::string nm(s, l);
        bool ok = l > 0 && l < 128;
        for (char &ch : nm) {
            if ((unsigned char)ch < 0x20 || (unsigned char)ch > 0x7e) {
                ok = false;
            }
            if (ch == '\\') {
                ch = '/';
            }
            if (ch >= 'A' && ch <= 'Z') {
                ch = (char)(ch + 32);
            }
        }
        names[(size_t)i] = ok ? nm : std::string();
    }
    pos += (size_t)nnames * 128u;
    if (!rd_i32(nleaves) || nleaves < 0 || pos + (size_t)nleaves * 2u > b.size()) {
        err = "the static prop lump's leaf list is damaged";
        return false;
    }
    pos += (size_t)nleaves * 2u;
    if (!rd_i32(nprops) || nprops < 0 || nprops > (1 << 20)) {
        err = "the static prop lump's prop count is damaged";
        return false;
    }
    info.names = (uint32_t)nnames;
    info.props = (uint32_t)nprops;
    if (nprops == 0) {
        return true;
    }
    size_t rem = b.size() - pos;
    if (rem % (size_t)nprops != 0) {
        err = "the static props have an unexpected size";
        return false;
    }
    size_t stride = rem / (size_t)nprops;
    info.stride = (uint32_t)stride;
    if (stride < 56 || stride > 512) {
        err = format("static props of %u bytes are not supported (lump version %u)", (unsigned)stride, (unsigned)ver);
        return false;
    }
    out.reserve((size_t)nprops);
    for (int32_t i = 0; i < nprops; i++) {
        const uint8_t *p = b.data() + pos + (size_t)i * stride;
        BspStaticProp sp;
        float f[6];
        std::memcpy(f, p, 24);
        uint16_t type;
        std::memcpy(&type, p + 24, 2);
        sp.solid = p[30];
        sp.flags = p[31];
        bool ok = type < names.size() && !names[type].empty();
        for (int k = 0; k < 6; k++) {
            ok = ok && std::isfinite(f[k]) && std::fabs(f[k]) < 65536.0f;
        }
        if (!ok) {
            continue;
        }
        sp.model = names[type];
        for (int k = 0; k < 3; k++) {
            sp.origin[k] = f[k];
            sp.angles[k] = f[3 + k];
        }
        if (ver >= 11 && stride >= 80) {
            float sc;
            std::memcpy(&sc, p + 76, 4);
            if (std::isfinite(sc) && sc > 0.01f && sc < 100.0f) {
                sp.scale = sc;
            }
        }
        out.push_back(std::move(sp));
    }
    return true;
}

void angle_matrix(const float angles[3], float m[9])
{
    const double k = 3.14159265358979323846 / 180.0;
    double sp = std::sin(angles[0] * k), cp = std::cos(angles[0] * k);
    double sy = std::sin(angles[1] * k), cy = std::cos(angles[1] * k);
    double sr = std::sin(angles[2] * k), cr = std::cos(angles[2] * k);
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

}  // namespace gsa1
