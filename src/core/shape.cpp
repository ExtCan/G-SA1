// G-SA1 core: shapes of moving objects (see shape.hpp).
#include "shape.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>

namespace gsa1 {

BspWorldOptions mover_options(float thin_wall_max)
{
    BspWorldOptions o;
    o.thin_wall_max = std::isfinite(thin_wall_max) && thin_wall_max > 0.0f ? thin_wall_max : 0.0f;
    o.water = false;
    o.displacements = false;
    o.kill_plane = false;
    o.stair_ramps = false;
    o.tess_max = kMoverTess;
    o.max_triangles = 1u << 20;
    return o;
}

namespace {

void tri_centroid(const sa1_collision_tri &t, double c[3])
{
    for (int k = 0; k < 3; k++) {
        c[k] = ((double)t.v[0][k] + t.v[1][k] + t.v[2][k]) / 3.0;
    }
}

void chunk_of(const std::vector<sa1_collision_tri> &tris, const std::vector<uint32_t> &idx, ShapeChunk &ch)
{
    double lo[3] = {1e300, 1e300, 1e300}, hi[3] = {-1e300, -1e300, -1e300};
    for (uint32_t i : idx) {
        for (int v = 0; v < 3; v++) {
            for (int k = 0; k < 3; k++) {
                lo[k] = std::min(lo[k], (double)tris[i].v[v][k]);
                hi[k] = std::max(hi[k], (double)tris[i].v[v][k]);
            }
        }
    }
    double c[3];
    for (int k = 0; k < 3; k++) {
        c[k] = 0.5 * (lo[k] + hi[k]);
        ch.center[k] = (float)c[k];
    }
    double r2 = 0.0;
    ch.tris.clear();
    ch.tris.reserve(idx.size());
    for (uint32_t i : idx) {
        sa1_collision_tri t = tris[i];
        for (int v = 0; v < 3; v++) {
            double d2 = 0.0;
            for (int k = 0; k < 3; k++) {
                t.v[v][k] = (float)((double)tris[i].v[v][k] - (double)ch.center[k]);
                d2 += (double)t.v[v][k] * t.v[v][k];
            }
            r2 = std::max(r2, d2);
        }
        ch.tris.push_back(t);
    }
    ch.radius = (float)std::sqrt(r2);
}

void split(const std::vector<sa1_collision_tri> &tris, std::vector<uint32_t> &idx, uint32_t max_tris, float max_radius,
           int depth, std::vector<ShapeChunk> &out)
{
    ShapeChunk ch;
    chunk_of(tris, idx, ch);
    if ((idx.size() <= max_tris && ch.radius <= max_radius) || idx.size() < 2 || depth > 40) {
        out.push_back(std::move(ch));
        return;
    }
    // split at the median of the centroids along their longest extent
    double lo[3] = {1e300, 1e300, 1e300}, hi[3] = {-1e300, -1e300, -1e300}, c[3];
    for (uint32_t i : idx) {
        tri_centroid(tris[i], c);
        for (int k = 0; k < 3; k++) {
            lo[k] = std::min(lo[k], c[k]);
            hi[k] = std::max(hi[k], c[k]);
        }
    }
    int ax = 0;
    for (int k = 1; k < 3; k++) {
        if (hi[k] - lo[k] > hi[ax] - lo[ax]) {
            ax = k;
        }
    }
    size_t mid = idx.size() / 2;
    std::nth_element(idx.begin(), idx.begin() + (std::ptrdiff_t)mid, idx.end(), [&](uint32_t a, uint32_t b) {
        double ca[3], cb[3];
        tri_centroid(tris[a], ca);
        tri_centroid(tris[b], cb);
        return ca[ax] < cb[ax];
    });
    std::vector<uint32_t> left(idx.begin(), idx.begin() + (std::ptrdiff_t)mid), right(idx.begin() + (std::ptrdiff_t)mid, idx.end());
    split(tris, left, max_tris, max_radius, depth + 1, out);
    split(tris, right, max_tris, max_radius, depth + 1, out);
}

}  // namespace

void make_shape(const std::vector<sa1_collision_tri> &tris, Shape &out, uint32_t max_tris, float max_radius)
{
    out = Shape();
    out.tris = (uint32_t)tris.size();
    if (tris.empty()) {
        return;
    }
    for (int k = 0; k < 3; k++) {
        out.mins[k] = out.maxs[k] = tris[0].v[0][k];
    }
    for (const sa1_collision_tri &t : tris) {
        for (int v = 0; v < 3; v++) {
            for (int k = 0; k < 3; k++) {
                out.mins[k] = std::min(out.mins[k], t.v[v][k]);
                out.maxs[k] = std::max(out.maxs[k], t.v[v][k]);
            }
        }
    }
    std::vector<uint32_t> idx(tris.size());
    std::iota(idx.begin(), idx.end(), 0u);
    split(tris, idx, max_tris, max_radius, 0, out.chunks);
}

bool shape_from_phy(const PhyModel &m, Shape &out, std::string &err, float thin_wall_max)
{
    std::vector<ConvexSolid> solids;
    for (const std::vector<float> &h : m.hulls) {
        ConvexSolid cs;
        cs.tris = h;
        solids.push_back(std::move(cs));
    }
    std::vector<sa1_collision_tri> tris;
    BspWorldStats st;
    if (!clean_solids(solids, mover_options(thin_wall_max), tris, st, err)) {
        return false;
    }
    if (tris.empty()) {
        err = "the physics model left no collision";
        return false;
    }
    make_shape(tris, out);
    return true;
}

void box_solid(const float mins[3], const float maxs[3], const float m[9], const float t[3], ConvexSolid &out)
{
    static const int faces[6][4] = {{0, 2, 3, 1}, {4, 5, 7, 6}, {0, 1, 5, 4}, {2, 6, 7, 3}, {0, 4, 6, 2}, {1, 3, 7, 5}};
    float corner[8][3];
    for (int i = 0; i < 8; i++) {
        float p[3] = {(i & 1) ? maxs[0] : mins[0], (i & 2) ? maxs[1] : mins[1], (i & 4) ? maxs[2] : mins[2]};
        for (int r = 0; r < 3; r++) {
            corner[i][r] = (m ? m[3 * r] * p[0] + m[3 * r + 1] * p[1] + m[3 * r + 2] * p[2] : p[r]) + (t ? t[r] : 0.0f);
        }
    }
    out.tris.clear();
    for (const auto &f : faces) {
        const int tri[2][3] = {{f[0], f[1], f[2]}, {f[0], f[2], f[3]}};
        for (const auto &tr : tri) {
            for (int v = 0; v < 3; v++) {
                out.tris.insert(out.tris.end(), corner[tr[v]], corner[tr[v]] + 3);
            }
        }
    }
}

bool shape_box(const float mins[3], const float maxs[3], Shape &out, std::string &err, float thin_wall_max)
{
    for (int k = 0; k < 3; k++) {
        if (!std::isfinite(mins[k]) || !std::isfinite(maxs[k]) || !(maxs[k] - mins[k] > 0.5f) ||
            maxs[k] - mins[k] > 8000.0f) {
            err = "the box is empty or too large";
            return false;
        }
    }
    std::vector<ConvexSolid> solids(1);
    box_solid(mins, maxs, nullptr, nullptr, solids[0]);
    std::vector<sa1_collision_tri> tris;
    BspWorldStats st;
    if (!clean_solids(solids, mover_options(thin_wall_max), tris, st, err)) {
        return false;
    }
    make_shape(tris, out);
    return !tris.empty();
}

}  // namespace gsa1
