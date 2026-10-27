// G-SA1 collision tests (offline, no Garry's Mod needed): the map -> collision conversion against a real map and the
// game's own land collision on it through gsa1::Session (the module's code path).
//
//   collision_test [--bsp MAP.bsp] [--gdi GAME.gdi] [--verbose]
//
//   --bsp  default maps\gm_construct.bsp of Garry's Mod's garrysmod folder, found by tests/gmod_paths.hpp (opened read-only)
//   --gdi  default $SA1_TEST_GDI; without a disc only the map checks run
//
// The bug this guards (owner's first in-game test, 2026-10-20): "Collision seems to break when there's a floor above
// a floor (the top of the garage you'll fall into the floor of it)". Root cause: the conversion emitted every side of
// every brush, including the faces buried between touching brushes (gm_construct's garage roof is a 16-unit floor
// brush under a 16-unit roof brush: up- and down-facing faces at z 48 inside the roof, wall tops inside it, ...).
// SA1's land collision gathers the polygons near the character into the 96-entry NEAR-poly list (8C028BFE) and
// stops when it is full, so with the buried faces around the list overflowed and the roof's own top was never
// tested: Sonic fell into the garage. bsp.cpp now cuts the hidden parts away (BspWorldOptions::remove_hidden) and
// makes stairs ramps (stair_ramps: 8 x 12-unit steps put 250 polygons into the NEAR-poly list's reach). Since 0.5 thin
// platforms are one-way (one_way_max: a down face with a walkable top at most 24 units above it is left out; 0.4
// thickened floors thinner than 12 units instead, thin_floor_min): a floor's underside within the sphere's reach was
// what pulled the character through it from above (sadc docs/research/gsa1_ramp_freeze.md, mechanism B).
//
// Map checks: hidden-face removal, one-way and displacement statistics; the column structure (along vertical lines
// the faces of the solid brushes alternate up / down, nothing buried: checked without the one-way rule) and what the
// one-way rule takes away (down faces only); the garage roof's column. Session checks (gm_construct):
// the garage roof (landing, a sweep of runs and jumps over the whole roof: never below the roof, the NEAR-poly list
// never full), the two-storey building west of the spawn whose upper floor Sonic fell through, every stacked floor
// the map has (found from the columns: a floor with headroom over another floor), named places (the walkway, the
// tall building's floors, the pool platform), up and down a staircase, then six runs on the garage roof with and
// without the fix (what the owner saw). GSA1_COLLISION_TRACE="x y z yaw idle run jump" prints one run step by step,
// GSA1_COLLISION_RANDOM="N seed" surveys N runs from random open floors. Positions are Hammer units; "fall-through" = Sonic's body (8 units above the feet) crossing an up-facing
// triangle from above with that floor around him (24 units in x and y), i.e. not sliding off an edge.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "../src/core/bsp.hpp"
#include "../src/core/prepare.hpp"
#include "../src/core/shape.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

using namespace gsa1;

// libsa1 internals (static linkage; test diagnostics only): a character's world and its guest memory
extern "C" {
struct sa1g_world;
struct sa1g_world *sa1_character_world(const sa1_context *ctx, sa1_character_id id);
void *sa1g_world_ptr(const struct sa1g_world *w, uint32_t guest);
}
static const uint32_t kNearCount = 0x8C73E27Cu;   // B_8C73E27C: entries of the NEAR-poly list (8C028BFE)
static const int kNearMax = 96;                   // B_8C73E280[96]

static int g_fail = 0, g_checks = 0, g_known = 0;
static bool g_verbose = false;

#define CHECK(cond, ...)                                     \
    do {                                                     \
        g_checks++;                                          \
        if (cond) {                                          \
            std::printf("  ok    ");                         \
        } else {                                             \
            std::printf("  FAIL  ");                         \
            g_fail++;                                        \
        }                                                    \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

#define INFO(...)                                            \
    do {                                                     \
        std::printf("  info  ");                             \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

// ---- the triangle soup, indexed by 2D bins ----------------------------------------------------------------------
struct Hit {
    float z;
    int dir;   // +1 facing up, -1 down, 0 vertical
    uint32_t tri = 0;   // (0.9.3) the triangle
};

struct Soup {
    std::vector<sa1_collision_tri> t;
    std::vector<float> n;   // unit normals
    std::map<std::pair<int32_t, int32_t>, std::vector<uint32_t>> bins;
    static constexpr float kBin = 128.0f;

    void build(const std::vector<sa1_collision_tri> &tris)
    {
        t = tris;
        n.assign(t.size() * 3, 0.0f);
        bins.clear();
        for (uint32_t i = 0; i < t.size(); i++) {
            float e1[3], e2[3];
            for (int k = 0; k < 3; k++) {
                e1[k] = t[i].v[1][k] - t[i].v[0][k];
                e2[k] = t[i].v[2][k] - t[i].v[0][k];
            }
            float c[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
            float l = std::sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2]);
            if (l > 0.0f) {
                for (int k = 0; k < 3; k++) {
                    n[3 * i + k] = c[k] / l;
                }
            }
            float lo[2] = {1e9f, 1e9f}, hi[2] = {-1e9f, -1e9f};
            for (int k = 0; k < 3; k++) {
                for (int a = 0; a < 2; a++) {
                    lo[a] = std::min(lo[a], t[i].v[k][a]);
                    hi[a] = std::max(hi[a], t[i].v[k][a]);
                }
            }
            if (hi[0] - lo[0] > 20000.0f || hi[1] - lo[1] > 20000.0f) {
                continue;   // the kill plane and the like: never a floor of interest
            }
            for (int32_t bx = (int32_t)std::floor(lo[0] / kBin); bx <= (int32_t)std::floor(hi[0] / kBin); bx++) {
                for (int32_t by = (int32_t)std::floor(lo[1] / kBin); by <= (int32_t)std::floor(hi[1] / kBin); by++) {
                    bins[{bx, by}].push_back(i);
                }
            }
        }
    }

    // the faces a vertical line through (x, y) meets, highest first (land only: no water, no kill plane)
    void column(float x, float y, std::vector<Hit> &out) const
    {
        out.clear();
        auto it = bins.find({(int32_t)std::floor(x / kBin), (int32_t)std::floor(y / kBin)});
        if (it == bins.end()) {
            return;
        }
        for (uint32_t i : it->second) {
            const sa1_collision_tri &q = t[i];
            if (q.surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER)) {
                continue;
            }
            float ax = q.v[0][0], ay = q.v[0][1], bx = q.v[1][0], by = q.v[1][1], cx = q.v[2][0], cy = q.v[2][1];
            float d = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
            if (std::fabs(d) < 1e-6f) {
                continue;
            }
            float l1 = ((bx - x) * (cy - y) - (by - y) * (cx - x)) / d;
            float l2 = ((cx - x) * (ay - y) - (cy - y) * (ax - x)) / d;
            float l3 = 1.0f - l1 - l2;
            if (l1 < 0.0f || l2 < 0.0f || l3 < 0.0f) {
                continue;
            }
            float z = l1 * q.v[0][2] + l2 * q.v[1][2] + l3 * q.v[2][2];
            float nz = n[3 * i + 2];
            out.push_back({z, nz > 1e-3f ? 1 : (nz < -1e-3f ? -1 : 0), i});
        }
        std::sort(out.begin(), out.end(), [](const Hit &a, const Hit &b) { return a.z != b.z ? a.z > b.z : a.dir > b.dir; });
    }

    // is there an up-facing surface at height z (+-tol) at (x, y)?
    bool floor_at(float x, float y, float z, float tol) const
    {
        std::vector<Hit> c;
        column(x, y, c);
        for (const Hit &h : c) {
            if (h.dir > 0 && std::fabs(h.z - z) <= tol) {
                return true;
            }
        }
        return false;
    }

    // segment p0 -> p1 (both lifted by `lift`) crossing an up-facing triangle from above, with that floor around
    // the crossing point (`around` units in x and y): falling through a floor, not off its edge
    int fall_throughs(const float p0[3], const float p1[3], float lift, float around) const
    {
        float a[3] = {p0[0], p0[1], p0[2] + lift}, c[3] = {p1[0], p1[1], p1[2] + lift};
        int count = 0;
        std::set<uint32_t> seen;
        int32_t bx0 = (int32_t)std::floor(std::min(a[0], c[0]) / kBin), bx1 = (int32_t)std::floor(std::max(a[0], c[0]) / kBin);
        int32_t by0 = (int32_t)std::floor(std::min(a[1], c[1]) / kBin), by1 = (int32_t)std::floor(std::max(a[1], c[1]) / kBin);
        for (int32_t bx = bx0; bx <= bx1; bx++) {
            for (int32_t by = by0; by <= by1; by++) {
                auto it = bins.find({bx, by});
                if (it == bins.end()) {
                    continue;
                }
                for (uint32_t i : it->second) {
                    if (!seen.insert(i).second) {
                        continue;
                    }
                    const sa1_collision_tri &q = t[i];
                    const float *nn = &n[3 * i];
                    if ((q.surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER)) || nn[2] < 0.5f) {
                        continue;
                    }
                    float da = 0.0f, dc = 0.0f;
                    for (int k = 0; k < 3; k++) {
                        da += nn[k] * (a[k] - q.v[0][k]);
                        dc += nn[k] * (c[k] - q.v[0][k]);
                    }
                    if (!(da >= -0.01f && dc < -0.01f)) {
                        continue;
                    }
                    float s = da / (da - dc), x[3];
                    for (int k = 0; k < 3; k++) {
                        x[k] = a[k] + (c[k] - a[k]) * s;
                    }
                    bool inside = true;
                    for (int e = 0; e < 3 && inside; e++) {
                        const float *u = q.v[e], *v = q.v[(e + 1) % 3];
                        float ex[3] = {v[0] - u[0], v[1] - u[1], v[2] - u[2]};
                        float qx[3] = {x[0] - u[0], x[1] - u[1], x[2] - u[2]};
                        float cr[3] = {ex[1] * qx[2] - ex[2] * qx[1], ex[2] * qx[0] - ex[0] * qx[2],
                                       ex[0] * qx[1] - ex[1] * qx[0]};
                        if (cr[0] * nn[0] + cr[1] * nn[1] + cr[2] * nn[2] < -1e-3f) {
                            inside = false;
                        }
                    }
                    if (!inside) {
                        continue;
                    }
                    // the same plane around the crossing point (a slope keeps its height change)
                    bool interior = true;
                    for (int k = 0; k < 4 && interior; k++) {
                        float ox = (k == 0 ? around : k == 1 ? -around : 0.0f);
                        float oy = (k == 2 ? around : k == 3 ? -around : 0.0f);
                        float oz = -(nn[0] * ox + nn[1] * oy) / nn[2];
                        interior = floor_at(x[0] + ox, x[1] + oy, x[2] + oz, 1.5f);
                    }
                    if (interior) {
                        count++;
                    }
                }
            }
        }
        return count;
    }
};

static bool load_map(const std::string &path, const BspWorldOptions &opt, std::vector<sa1_collision_tri> &tris,
                     BspWorldStats &st, std::string &e)
{
    FileByteSource src;
    Bsp bsp;
    return src.open(path, e) && bsp.open(src, e) && bsp.build_world(opt, tris, st, e);
}

// ---- 1. the map --------------------------------------------------------------------------------------------------
// faces met by vertical lines on a lattice (displacements off: every face then belongs to a brush): the land faces
// must alternate up / down from the top (entering, leaving solid); a repeat is a buried face
static void column_structure(const Soup &s, float x0, float x1, float y0, float y1, float step, uint32_t &cols,
                             uint32_t &bad, std::string &first_bad)
{
    cols = bad = 0;
    std::vector<Hit> c;
    for (float x = x0; x <= x1; x += step) {
        for (float y = y0; y <= y1; y += step) {
            s.column(x, y, c);
            std::vector<Hit> m;   // coincident hits of one surface (a line through a shared edge) merged
            for (const Hit &h : c) {
                if (h.dir == 0) {
                    continue;
                }
                if (!m.empty() && m.back().dir == h.dir && std::fabs(m.back().z - h.z) < 0.02f) {
                    continue;
                }
                m.push_back(h);
            }
            if (m.empty()) {
                continue;
            }
            cols++;
            bool ok = m[0].dir > 0;
            for (size_t k = 1; k < m.size() && ok; k++) {
                ok = m[k].dir == -m[k - 1].dir;
            }
            if (!ok) {
                if (bad == 0) {
                    first_bad = format("(%.2f %.2f):", x, y);
                    for (const Hit &h : m) {
                        first_bad += format(" %.1f%s", h.z, h.dir > 0 ? "u" : "d");
                    }
                }
                bad++;
            }
        }
    }
}

// the faces a vertical line meets, coincident hits of one surface merged, vertical ones left out
static void merged_column(const Soup &s, float x, float y, std::vector<Hit> &m)
{
    std::vector<Hit> c;
    s.column(x, y, c);
    m.clear();
    for (const Hit &h : c) {
        if (h.dir == 0) {
            continue;
        }
        if (!m.empty() && m.back().dir == h.dir && std::fabs(m.back().z - h.z) < 0.02f) {
            continue;
        }
        m.push_back(h);
    }
}

static void test_map(const std::string &bsp_path, std::vector<sa1_collision_tri> &tris)
{
    std::printf("map: %s\n", bsp_path.c_str());
    std::string e;
    BspWorldOptions raw_opt;            // 0.1: every brush face
    raw_opt.remove_hidden = false;
    raw_opt.thin_floor_min = 0.0f;
    raw_opt.one_way_max = 0.0f;
    BspWorldOptions v04;                // 0.4: hidden faces removed, thin floors thickened, no one-way platforms
    v04.one_way_max = 0.0f;
    v04.disp_side_flip = true;
    std::vector<sa1_collision_tri> raw, old;
    BspWorldStats rs, os, st;
    bool ok = load_map(bsp_path, raw_opt, raw, rs, e) && load_map(bsp_path, v04, old, os, e) &&
              load_map(bsp_path, BspWorldOptions(), tris, st, e);
    CHECK(ok, "build_world without and with the hidden-face removal (%s)", ok ? "" : e.c_str());
    if (!ok) {
        tris.clear();
        return;
    }
    CHECK(st.hidden_faces > 0 && st.clipped_faces > 0 && st.tris < rs.tris,
          "hidden faces removed: %u of %u brush faces entirely, %u in part (%u visible pieces); %u -> %u triangles; "
          "%.1f ms (%.1f ms without)", st.hidden_faces, st.brush_faces, st.clipped_faces, st.face_fragments, rs.tris,
          st.tris, st.ms, rs.ms);
    CHECK(os.thickened_floors > 0 && st.thickened_floors == 0 && st.one_way_solids > 0 && st.tris < os.tris,
          "one-way thin platforms replace the thickening: 0.4 thickened %u floors; now %u solids are one-way (%u "
          "undersides left out, %u more pieces under a walkable face of another solid), %u thickened; %u -> %u triangles",
          os.thickened_floors, st.one_way_solids, st.one_way_faces, st.one_way_cross, st.thickened_floors, os.tris,
          st.tris);
    CHECK(st.stairs > 0 && st.tris_stairs > 0, "stairs made ramps: %u runs of %u steps, %u ramp triangles (SOLID | STAIRS)",
          st.stairs, st.stair_steps, st.tris_stairs);
    CHECK(st.displacements == 110 && st.disp_tag_checked == st.displacements && st.disp_tag_reversed == 0,
          "displacements: %u, wound along their base plane; the map's walkable tags decided %u and agree with all of them",
          st.displacements, st.disp_tag_checked);
    // column structure (no displacements, no kill plane): the hidden-face removal alone (no one-way rule), then what
    // the one-way rule takes away from it
    BspWorldOptions nd = BspWorldOptions(), nd_raw = raw_opt, nw = BspWorldOptions();
    nd.one_way_max = 0.0f;
    nd.thin_floor_min = 0.0f;
    nd.displacements = nd_raw.displacements = nw.displacements = false;
    nd.kill_plane = nd_raw.kill_plane = nw.kill_plane = false;
    std::vector<sa1_collision_tri> a, b, c;
    BspWorldStats sa, sb, sc;
    if (load_map(bsp_path, nd_raw, a, sa, e) && load_map(bsp_path, nd, b, sb, e) && load_map(bsp_path, nw, c, sc, e)) {
        Soup sr, scl, sow;
        sr.build(a);
        scl.build(b);
        sow.build(c);
        float x0 = std::max(-8000.0f, st.mins[0]) + 0.37f, x1 = std::min(8000.0f, st.maxs[0]);
        float y0 = std::max(-8000.0f, st.mins[1]) + 0.29f, y1 = std::min(8000.0f, st.maxs[1]);
        uint32_t cr, br, cc, bc;
        std::string fr, fc;
        column_structure(sr, x0, x1, y0, y1, 64.0f, cr, br, fr);
        column_structure(scl, x0, x1, y0, y1, 64.0f, cc, bc, fc);
        INFO("without the removal: %u of %u columns (64-unit lattice) meet buried faces, e.g. %s", br, cr, fr.c_str());
        CHECK(bc * 1000u <= cc, "column structure: %u of %u columns break the up / down alternation (at most 0.1%%)%s%s",
              bc, cc, bc ? ", first " : "", fc.c_str());
        // one-way: along every column only down faces disappear, nothing appears
        uint32_t cols = 0, thinner = 0, removed = 0, bad = 0;
        std::string first_bad;
        std::vector<Hit> m0, m1;
        for (float x = x0; x <= x1; x += 64.0f) {
            for (float y = y0; y <= y1; y += 64.0f) {
                merged_column(scl, x, y, m0);
                merged_column(sow, x, y, m1);
                if (m0.empty()) {
                    continue;
                }
                cols++;
                size_t j = 0;
                uint32_t gone = 0;
                bool col_bad = false;
                for (const Hit &h : m0) {
                    if (j < m1.size() && m1[j].dir == h.dir && std::fabs(m1[j].z - h.z) < 0.05f) {
                        j++;
                    } else if (h.dir < 0) {
                        gone++;
                    } else {
                        col_bad = true;
                    }
                }
                col_bad = col_bad || j != m1.size();
                removed += gone;
                thinner += gone > 0;
                if (col_bad) {
                    bad++;
                    if (first_bad.empty()) {
                        first_bad = format("(%.2f %.2f)", x, y);
                    }
                }
            }
        }
        CHECK(thinner > 0 && bad * 1000u <= cols,
              "one-way: in %u of %u columns %u undersides are left out; only down faces disappear (%u columns differ "
              "otherwise%s%s)", thinner, cols, removed, bad, bad ? ", first " : "", first_bad.c_str());
    } else {
        CHECK(false, "build_world without displacements: %s", e.c_str());
    }
    // the garage roof: roof top 64, the garage floor -144; nothing in between but the garage's ceiling at 32: not the
    // buried faces at 48 - the 16-unit slab under the roof is one-way (0.4: its underside at 32 an ordinary face;
    // 0.5-0.9.2: left out, the garage's ceiling could be jumped through; 0.9.3: a FRONT-ONLY ceiling, gsa1_091b_ceiling.md
    // FIX-C3: nothing from above, a ceiling from below)
    Soup s;
    s.build(tris);
    std::vector<Hit> col_hits;
    s.column(1400.37f, 0.29f, col_hits);
    std::string col;
    int between = 0;
    bool top = false, floor = false, ceiling = false;
    for (const Hit &h : col_hits) {
        if (h.z < 2000.0f && h.z > -200.0f) {
            col += format(" %.1f%s%s", h.z, h.dir > 0 ? "u" : h.dir < 0 ? "d" : "w",
                          (s.t[h.tri].surface & SA1_SURFACE_FRONT_ONLY) ? "(front-only)" : "");
        }
        top |= h.dir > 0 && std::fabs(h.z - 64.0f) < 0.1f;
        floor |= h.dir > 0 && std::fabs(h.z + 144.0f) < 0.1f;
        bool fo_ceiling = h.dir < 0 && std::fabs(h.z - 32.0f) < 0.1f && (s.t[h.tri].surface & SA1_SURFACE_FRONT_ONLY);
        ceiling |= fo_ceiling;
        between += h.z > -143.9f && h.z < 63.9f && !fo_ceiling;
    }
    CHECK(top && floor && ceiling && between == 0,
          "the garage roof's column at (1400, 0): roof 64 up, garage floor -144 up, between them only the garage's "
          "ceiling at 32, front-only (0.3: the floor brush's top and the roof brush's bottom at 48 too):%s", col.c_str());
    // a 4-unit ledge of the building west of the garage (z 508..512): one-way, no ordinary underside below it (0.4:
    // thickened to 500); 0.9.3: a front-only one
    s.column(-2700.3f, -2270.3f, col_hits);
    bool ledge_top = false, ledge_bottom = false, ledge_fo = false;
    for (const Hit &h : col_hits) {
        ledge_top |= h.dir > 0 && std::fabs(h.z - 512.0f) < 0.1f;
        bool under = h.dir < 0 && h.z > 480.0f && h.z < 511.9f;
        bool fo = under && (s.t[h.tri].surface & SA1_SURFACE_FRONT_ONLY);
        ledge_bottom |= under && !fo;
        ledge_fo |= fo;
    }
    CHECK(ledge_top && !ledge_bottom && ledge_fo,
          "a 4-unit ledge (top 512) is one-way: no ordinary underside below it, a front-only one (a ceiling from below)");
}

// ---- 2. Sonic on the map -----------------------------------------------------------------------------------------
struct Probe {
    int pairs = 0, near_max = 0, near_full = 0, falls = 0;
    bool landed = false, grounded = false;
    float land_z = 0.0f, min_z = 1e9f, end[3] = {0, 0, 0};
    bool fault = false;
};

static int near_count(Session &s, int32_t id)
{
    Character *c = s.get(id);
    if (!c) {
        return -1;
    }
    sa1g_world *w = sa1_character_world(s.ctx(), c->id);
    const void *p = w ? sa1g_world_ptr(w, kNearCount) : nullptr;
    int32_t n = -1;
    if (p) {
        std::memcpy(&n, p, 4);
    }
    return (int)n;
}

// Sonic created at `pos` facing `yaw` (radians), idle for `idle` s, then the stick forward along the yaw for `run` s
// with a jump at `jump_at` s into the run (< 0: none); 60 frames per second
static Probe drive(Session &s, const Soup &soup, const float pos[3], float yaw, float idle, float run, float jump_at,
                   bool print = false)
{
    Probe P;
    std::string e;
    int32_t id = s.create(SA1_CHAR_SONIC, pos, yaw, e);
    if (id <= 0) {
        std::printf("        create at (%.0f %.0f %.0f): %s\n", pos[0], pos[1], pos[2], e.c_str());
        P.fault = true;
        return P;
    }
    float prev[3] = {pos[0], pos[1], pos[2]};
    int frames = (int)((idle + run) * 60.0f + 0.5f);
    for (int f = 0; f < frames; f++) {
        float t = f / 60.0f;
        float stick = t >= idle ? 1.0f : 0.0f;
        uint32_t btn = (jump_at >= 0.0f && t >= idle + jump_at && t < idle + jump_at + 0.2f) ? SA1_BUTTON_JUMP : 0u;
        sa1_status st = s.tick(id, 0.0f, stick, yaw, btn, 1.0f / 60.0f);
        Character *c = s.get(id);
        if (st != SA1_OK || !c) {
            P.fault = true;
            break;
        }
        if (c->pairs_last == 0) {
            continue;
        }
        P.pairs++;
        int n = near_count(s, id);
        P.near_max = std::max(P.near_max, n);
        P.near_full += n >= kNearMax;
        const float *p = c->st.position;
        int fl = soup.fall_throughs(prev, p, 8.0f, 24.0f);
        P.falls += fl;
        bool ground = (c->st.flags & SA1_STATE_ON_GROUND) != 0;
        if (!P.landed && ground) {
            P.landed = true;
            P.land_z = p[2];
        }
        P.min_z = std::min(P.min_z, p[2]);
        if (print || (g_verbose && fl)) {
            std::printf("        t %5.2f pos (%8.1f %8.1f %8.1f) %s mode %2d action %3d NEAR %2d%s\n", t, p[0], p[1], p[2],
                        ground ? "ground" : "air   ", (int)c->st.mode, (int)c->st.action, n, fl ? "  FALL-THROUGH" : "");
        }
        std::memcpy(prev, p, sizeof prev);
    }
    Character *c = s.get(id);
    if (c) {
        std::memcpy(P.end, c->st.position, sizeof P.end);
        P.grounded = (c->st.flags & SA1_STATE_ON_GROUND) != 0;
    }
    s.destroy(id);
    return P;
}

// stacked floors: a floor with at least 64 units of air above it, solid below it down to an underside, and another
// floor at least 48 below that underside; clusters of lattice samples with the same top
struct Stack {
    float x, y, top, thick, gap;
    uint32_t samples;
    float lo[2], hi[2];
};

static void find_stacks(const Soup &s, float x0, float x1, float y0, float y1, float step, float zmax,
                        std::vector<Stack> &out)
{
    struct Cand {
        int ix, iy;
        float top, thick, gap;
        int cl;
    };
    std::vector<Cand> cands;
    std::map<std::pair<int, int>, std::vector<int>> at;
    std::vector<Hit> c;
    for (int ix = 0; x0 + ix * step <= x1; ix++) {
        for (int iy = 0; y0 + iy * step <= y1; iy++) {
            s.column(x0 + ix * step, y0 + iy * step, c);
            std::vector<Hit> m;
            for (const Hit &h : c) {
                if (h.dir != 0 && (m.empty() || m.back().dir != h.dir || std::fabs(m.back().z - h.z) >= 0.02f)) {
                    m.push_back(h);
                }
            }
            for (size_t i = 0; i < m.size(); i++) {
                if (m[i].dir != 1 || m[i].z > zmax) {
                    continue;
                }
                if (i > 0 && !(m[i - 1].dir == -1 && m[i - 1].z >= m[i].z + 64.0f)) {
                    continue;
                }
                if (i + 2 >= m.size() || m[i + 1].dir != -1 || m[i + 2].dir != 1) {
                    continue;
                }
                float under = m[i + 1].z, below = m[i + 2].z;
                if (under - below < 48.0f) {
                    continue;
                }
                at[{ix, iy}].push_back((int)cands.size());
                cands.push_back({ix, iy, m[i].z, m[i].z - under, under - below, -1});
            }
        }
    }
    int ncl = 0;
    for (size_t k = 0; k < cands.size(); k++) {
        if (cands[k].cl >= 0) {
            continue;
        }
        std::vector<int> stack{(int)k}, members;
        cands[k].cl = ncl;
        while (!stack.empty()) {
            int m = stack.back();
            stack.pop_back();
            members.push_back(m);
            const int d4[4][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
            for (const auto &d : d4) {
                auto it = at.find({cands[m].ix + d[0], cands[m].iy + d[1]});
                if (it == at.end()) {
                    continue;
                }
                for (int o : it->second) {
                    if (cands[o].cl < 0 && std::fabs(cands[o].top - cands[m].top) < 1.0f) {
                        cands[o].cl = ncl;
                        stack.push_back(o);
                    }
                }
            }
        }
        ncl++;
        if (members.size() < 6) {
            continue;   // a sill or a beam
        }
        // the member nearest the centroid with members 2 steps away in all 8 directions: an interior point
        double cx = 0, cy = 0, th = 0, gp = 0;
        Stack S;
        S.lo[0] = S.lo[1] = 1e9f;
        S.hi[0] = S.hi[1] = -1e9f;
        for (int m : members) {
            float x = x0 + cands[m].ix * step, y = y0 + cands[m].iy * step;
            cx += x;
            cy += y;
            th += cands[m].thick;
            gp += cands[m].gap;
            S.lo[0] = std::min(S.lo[0], x);
            S.lo[1] = std::min(S.lo[1], y);
            S.hi[0] = std::max(S.hi[0], x);
            S.hi[1] = std::max(S.hi[1], y);
        }
        cx /= members.size();
        cy /= members.size();
        int best = -1;
        double bd = 1e300;
        for (int m : members) {
            bool inner = true;
            for (int dx = -2; dx <= 2 && inner; dx += 2) {
                for (int dy = -2; dy <= 2 && inner; dy += 2) {
                    auto it = at.find({cands[m].ix + dx, cands[m].iy + dy});
                    bool found = false;
                    if (it != at.end()) {
                        for (int o : it->second) {
                            found |= cands[o].cl == cands[m].cl;
                        }
                    }
                    inner = found;
                }
            }
            if (!inner) {
                continue;
            }
            double x = x0 + cands[m].ix * step, y = y0 + cands[m].iy * step;
            double d = (x - cx) * (x - cx) + (y - cy) * (y - cy);
            if (d < bd) {
                bd = d;
                best = m;
            }
        }
        if (best < 0) {
            continue;
        }
        S.x = x0 + cands[best].ix * step;
        S.y = y0 + cands[best].iy * step;
        S.top = cands[best].top;
        S.thick = (float)(th / members.size());
        S.gap = (float)(gp / members.size());
        S.samples = (uint32_t)members.size();
        out.push_back(S);
    }
    std::sort(out.begin(), out.end(), [](const Stack &a, const Stack &b) { return a.samples > b.samples; });
}

static const float kDeg = 3.14159265f / 180.0f;

// runs from a lattice of points on a rectangle of floor at height z, four directions in turn, a jump half-way: no
// fall-through, never ending below the floor while over it, the NEAR-poly list never full
struct Sweep {
    int runs = 0, falls = 0, below = 0, near_full = 0, near_max = 0, not_landed = 0, faults = 0, skipped = 0;
};

static Sweep sweep(Session &s, const Soup &soup, float x0, float x1, float y0, float y1, float z, int nx, int ny,
                   float run, bool verbose_fail)
{
    Sweep W;
    int k = 0;
    for (int i = 0; i < nx; i++) {
        for (int j = 0; j < ny; j++, k++) {
            float pos[3] = {x0 + (x1 - x0) * (i + 0.5f) / nx, y0 + (y1 - y0) * (j + 0.5f) / ny, z + 24.0f};
            float yaw = (float)(k % 4) * 90.0f * kDeg + 0.3f;
            bool floor = soup.floor_at(pos[0], pos[1], z, 0.5f);
            for (int q = 0; q < 4 && floor; q++) {
                floor = soup.floor_at(pos[0] + (q == 0 ? 24.0f : q == 1 ? -24.0f : 0.0f),
                                      pos[1] + (q == 2 ? 24.0f : q == 3 ? -24.0f : 0.0f), z, 0.5f);
            }
            if (!floor) {
                W.skipped++;   // a hole in the floor (a stairwell, a light well) or its edge
                continue;
            }
            Probe P = drive(s, soup, pos, yaw, 0.4f, run, run * 0.5f);
            W.runs++;
            W.faults += P.fault;
            W.not_landed += !(P.landed && std::fabs(P.land_z - z) < 1.0f);
            W.falls += P.falls;
            W.near_full += P.near_full;
            W.near_max = std::max(W.near_max, P.near_max);
            // below the floor while over it (a run that leaves the floor over an edge has no floor under its end)
            bool over = P.end[0] > x0 && P.end[0] < x1 && P.end[1] > y0 && P.end[1] < y1;
            bool bad = over && P.end[2] < z - 2.0f && soup.floor_at(P.end[0], P.end[1], z, 0.5f);
            W.below += bad;
            if (verbose_fail && (P.falls || bad || P.near_full)) {
                std::printf("        from (%.0f %.0f %.0f) yaw %.0f: end (%.1f %.1f %.1f), %d fall-throughs, NEAR full "
                            "in %d pairs (largest %d)\n", pos[0], pos[1], z, yaw / kDeg, P.end[0], P.end[1], P.end[2],
                            P.falls, P.near_full, P.near_max);
            }
        }
    }
    return W;
}

static void test_session(const std::string &gdi, const std::string &bsp_path, const std::vector<sa1_collision_tri> &tris)
{
    std::printf("Sonic on the map (gsa1::Session, 60 fps):\n");
    Session s;
    std::string e;
    bool ok = s.init(gdi, e) && s.set_world(tris, e);
    CHECK(ok, "init, disc and the map's collision (%s)", ok ? "" : e.c_str());
    if (!ok) {
        return;
    }
    Soup soup;
    soup.build(tris);
    if (const char *tr = std::getenv("GSA1_COLLISION_TRACE")) {
        // a trace for debugging: "x y z yaw_deg idle run jump_at" (Hammer units, seconds)
        float pos[3] = {0, 0, 0}, yaw = 0, idle = 0.4f, run = 1.2f, jump = -1.0f;
        if (std::sscanf(tr, "%f %f %f %f %f %f %f", &pos[0], &pos[1], &pos[2], &yaw, &idle, &run, &jump) >= 3) {
            std::printf("      trace from (%.1f %.1f %.1f) yaw %.1f, idle %.2f s, run %.2f s, jump at %.2f s\n", pos[0],
                        pos[1], pos[2], yaw, idle, run, jump);
            drive(s, soup, pos, yaw * kDeg, idle, run, jump, true);
        }
    }

    if (const char *rnd = std::getenv("GSA1_COLLISION_RANDOM")) {
        // a survey for debugging: "N seed": N runs from random points of the map's floors (open ones: the floor
        // 24 units around, 64 units of headroom), idle 0.5 s, run 1.5 s along a random yaw, a jump 1 s into the run
        int n = 0;
        unsigned seed = 1;
        std::sscanf(rnd, "%d %u", &n, &seed);
        std::vector<uint32_t> ups;
        std::vector<double> cum;
        double tot = 0.0;
        for (uint32_t i = 0; i < soup.t.size(); i++) {
            const sa1_collision_tri &q = soup.t[i];
            if ((q.surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER)) || soup.n[3 * i + 2] < 0.9f) {
                continue;
            }
            float cx = (q.v[0][0] + q.v[1][0] + q.v[2][0]) / 3, cy = (q.v[0][1] + q.v[1][1] + q.v[2][1]) / 3;
            float cz = (q.v[0][2] + q.v[1][2] + q.v[2][2]) / 3;
            if (std::fabs(cx) > 7000.0f || std::fabs(cy) > 7000.0f || cz > 2000.0f) {
                continue;
            }
            float e1x = q.v[1][0] - q.v[0][0], e1y = q.v[1][1] - q.v[0][1], e2x = q.v[2][0] - q.v[0][0], e2y = q.v[2][1] - q.v[0][1];
            double area = 0.5 * std::fabs(e1x * e2y - e1y * e2x);
            ups.push_back(i);
            tot += std::sqrt(area);
            cum.push_back(tot);
        }
        int runs = 0, falls = 0, full = 0;
        std::vector<Hit> col;
        for (int k = 0; k < n * 20 && runs < n && !ups.empty(); k++) {
            auto next = [&]() {
                seed = seed * 1664525u + 1013904223u;
                return (seed >> 8) / 16777216.0;
            };
            size_t j = std::lower_bound(cum.begin(), cum.end(), next() * tot) - cum.begin();
            const sa1_collision_tri &q = soup.t[ups[std::min(j, ups.size() - 1)]];
            double u = next(), v = next();
            if (u + v > 1.0) {
                u = 1.0 - u;
                v = 1.0 - v;
            }
            float pos[3];
            for (int a = 0; a < 3; a++) {
                pos[a] = (float)(q.v[0][a] + u * (q.v[1][a] - q.v[0][a]) + v * (q.v[2][a] - q.v[0][a]));
            }
            float yaw = (float)(next() * 360.0);
            bool open = true;
            for (int d = 0; d < 4 && open; d++) {
                open = soup.floor_at(pos[0] + (d == 0 ? 24.0f : d == 1 ? -24.0f : 0.0f),
                                     pos[1] + (d == 2 ? 24.0f : d == 3 ? -24.0f : 0.0f), pos[2], 1.0f);
            }
            soup.column(pos[0], pos[1], col);
            for (const Hit &h : col) {
                if (h.z > pos[2] + 0.5f && h.z < pos[2] + 64.0f) {
                    open = false;
                }
            }
            if (!open) {
                continue;
            }
            runs++;
            float start[3] = {pos[0], pos[1], pos[2] + 8.0f};
            Probe P = drive(s, soup, start, yaw * kDeg, 0.5f, 1.5f, 1.0f);
            falls += P.falls > 0;
            full += P.near_full > 0;
            if (P.falls || P.near_full) {
                std::printf("      from (%.0f %.0f %.0f) yaw %.0f: %d fall-throughs, NEAR-poly list full in %d pairs (largest "
                            "%d), end (%.0f %.0f %.0f)\n", pos[0], pos[1], pos[2], yaw, P.falls, P.near_full, P.near_max,
                            P.end[0], P.end[1], P.end[2]);
            }
        }
        INFO("survey: %d runs from open floors, %d with a fall-through, %d with the NEAR-poly list full", runs, falls, full);
    }

    // the garage (east of the spawn: walls x 1024..1856, y -896..896; roof top 64, ceiling 32, floor -144)
    {
        float pos[3] = {1400.0f, 0.0f, 104.0f};
        Probe P = drive(s, soup, pos, 0.0f, 1.5f, 0.0f, -1.0f);
        CHECK(P.landed && P.grounded && std::fabs(P.end[2] - 64.0f) < 1.0f && P.falls == 0 && P.near_full == 0,
              "the garage roof: lands at z %.1f and stands at %.1f (roof 64); NEAR-poly list up to %d of %d",
              P.land_z, P.end[2], P.near_max, kNearMax);
        Sweep W = sweep(s, soup, 1060.0f, 1820.0f, -860.0f, 860.0f, 64.0f, 5, 9, 1.2f, true);
        CHECK(W.faults == 0 && W.not_landed == 0 && W.falls == 0 && W.below == 0 && W.near_full == 0,
              "the garage roof, %d runs with a jump from a 5 x 9 lattice over the whole roof (%d points off the roof): "
              "%d fall-throughs, %d ends below the roof, NEAR-poly list full in %d pairs (largest %d), %d not landed",
              W.runs, W.skipped, W.falls, W.below, W.near_full, W.near_max, W.not_landed);
    }
    // the two-storey building west of the spawn: upper floor 48 (16 thick) over a floor at -96, ceiling 208
    {
        float pos[3] = {-3040.0f, -1344.0f, 72.0f};
        Probe P = drive(s, soup, pos, 0.0f, 1.0f, 0.0f, -1.0f);
        CHECK(P.landed && std::fabs(P.land_z - 48.0f) < 1.0f && std::fabs(P.end[2] - 48.0f) < 1.0f && P.falls == 0,
              "the two-storey building's upper floor (it was fallen through): lands at z %.1f, stands at %.1f (floor "
              "48); NEAR-poly list up to %d", P.land_z, P.end[2], P.near_max);
        Sweep W = sweep(s, soup, -3180.0f, -2780.0f, -1820.0f, -920.0f, 48.0f, 3, 6, 0.8f, true);
        CHECK(W.runs >= 10 && W.faults == 0 && W.not_landed == 0 && W.falls == 0 && W.below == 0 && W.near_full == 0,
              "its upper floor, %d runs (%d points over its stairwell or off it): %d fall-throughs, %d ends below it, "
              "NEAR-poly list full in %d pairs (largest %d)", W.runs, W.skipped, W.falls, W.below, W.near_full,
              W.near_max);
    }
    // every stacked floor of the map
    {
        std::vector<Stack> stacks;
        find_stacks(soup, -7000.37f, 7000.0f, -7000.29f, 7000.0f, 32.0f, 2000.0f, stacks);
        int tested = 0, passed = 0, near_full = 0;
        std::string failed;
        for (const Stack &S : stacks) {
            float pos[3] = {S.x, S.y, S.top + 24.0f};
            Probe P = drive(s, soup, pos, 0.0f, 1.2f, 0.0f, -1.0f);
            bool good = P.landed && P.grounded && std::fabs(P.end[2] - S.top) < 2.0f && P.falls == 0;
            tested++;
            passed += good;
            near_full += P.near_full > 0;
            if (!good || g_verbose || P.near_full) {
                std::string line = format("        %s floor %7.1f (%5.1f thick, %6.1f above the next floor, %4u samples, "
                                          "x %.0f..%.0f y %.0f..%.0f) at (%.0f %.0f): ends at %.1f %s, NEAR up to %d\n",
                                          good ? "ok  " : "FAIL", S.top, S.thick, S.gap, S.samples, S.lo[0], S.hi[0],
                                          S.lo[1], S.hi[1], S.x, S.y, P.end[2], P.grounded ? "on the ground" : "in the air",
                                          P.near_max);
                if (good) {
                    std::printf("%s", line.c_str());
                } else {
                    failed += line;
                }
            }
        }
        if (!failed.empty()) {
            std::printf("%s", failed.c_str());
        }
        CHECK(tested >= 12 && passed == tested,
              "every stacked floor of the map (a floor with 64 units of headroom over another floor, from 32-unit "
              "columns): Sonic dropped on %d of them stays on %d (the NEAR-poly list was full on %d: stairs nearby)",
              tested, passed, near_full);
    }
    // named places
    {
        struct Place {
            const char *name;
            float x, y, z, yaw;
            float run;
        };
        const Place places[] = {
            {"the walkway west of the spawn (z 240, a 38-unit floor over the street)", -2368.0f, -1504.0f, 240.0f, 0.0f, 1.0f},
            {"the tall building's floor at 768", -2304.0f, -2784.0f, 768.0f, 90.0f, 1.0f},
            {"the tall building's floor at 1280", -2304.0f, -2784.0f, 1280.0f, 180.0f, 1.0f},
            {"the pool platform (z -32 over the water)", 1312.0f, 4352.0f, -32.0f, 90.0f, 1.0f},
            {"the garage floor under the roof", 1440.0f, 0.0f, -144.0f, 0.0f, 1.0f},
        };
        for (const Place &pl : places) {
            float pos[3] = {pl.x, pl.y, pl.z + 24.0f};
            Probe P = drive(s, soup, pos, pl.yaw * kDeg, 0.6f, pl.run, pl.run * 0.4f);
            CHECK(P.landed && std::fabs(P.land_z - pl.z) < 1.0f && P.falls == 0 && P.near_full == 0 && P.min_z > pl.z - 2.0f,
                  "%s: lands at %.1f, runs and jumps, lowest %.1f, ends at (%.0f %.0f %.1f); NEAR-poly list up to %d",
                  pl.name, P.land_z, P.min_z, P.end[0], P.end[1], P.end[2], P.near_max);
        }
    }
    // stairs: the 8 x 12-unit steps west of the tall building (z 0 at y -2792 up to 136 at y -2996, 360 wide); as
    // steps they put 250 polygons into the NEAR-poly list's reach and Sonic fell through them; now a ramp
    {
        float pos[3] = {-5460.0f, -2820.0f, 64.0f};
        Probe P = drive(s, soup, pos, -90.0f * kDeg, 0.6f, 1.0f, -1.0f);
        CHECK(P.landed && P.falls == 0 && P.near_full == 0 && P.land_z > 16.0f && P.end[2] > P.land_z + 40.0f,
              "the stairs west of the tall building: lands on them at z %.1f, runs up to (%.0f %.0f %.1f); NEAR-poly "
              "list up to %d (full in %d pairs)", P.land_z, P.end[0], P.end[1], P.end[2], P.near_max, P.near_full);
        float down[3] = {-5460.0f, -3060.0f, 200.0f};
        P = drive(s, soup, down, 90.0f * kDeg, 0.6f, 1.0f, -1.0f);
        CHECK(P.landed && P.falls == 0 && P.near_full == 0 && P.end[2] < P.land_z - 60.0f && P.min_z > -20.0f,
              "and down them from the landing at z %.1f to (%.0f %.0f %.1f), lowest %.1f; NEAR-poly list up to %d",
              P.land_z, P.end[0], P.end[1], P.end[2], P.min_z, P.near_max);
    }
    // the garage roof as the owner played it: without the hidden-face removal and the thin-floor rule; runs that
    // fell into the garage then (fall-throughs measured against the real surfaces)
    {
        BspWorldOptions old;
        old.remove_hidden = false;
        old.thin_floor_min = 0.0f;
        old.one_way_max = 0.0f;
        old.disp_side_flip = true;
        std::vector<sa1_collision_tri> raw;
        BspWorldStats st;
        struct Run {
            float x, y, yaw;
        };
        const Run runs[] = {{1146, -810, 296}, {1251, -794, 331}, {1787, 147, 21}, {1498, -892, 243},
                            {1625, -861, 230}, {1062, -845, 226}};
        int fell_new = 0, fell_old = 0, full_new = 0, full_old = 0;
        for (int pass = 0; pass < 2; pass++) {
            if (pass == 1 && !(load_map(bsp_path, old, raw, st, e) && s.set_world(raw, e))) {
                CHECK(false, "the map without the fix: %s", e.c_str());
                break;
            }
            for (const Run &r : runs) {
                float pos[3] = {r.x, r.y, 72.0f};
                Probe P = drive(s, soup, pos, r.yaw * kDeg, 0.5f, 1.5f, 1.0f);
                bool fell = P.falls > 0 || (P.end[2] < 60.0f && soup.floor_at(P.end[0], P.end[1], 64.0f, 0.5f));
                (pass ? fell_old : fell_new) += fell;
                (pass ? full_old : full_new) += P.near_full;
            }
        }
        CHECK(fell_new == 0 && full_new == 0,
              "six runs on the garage roof that fell into the garage before the fix: %d fall now (NEAR-poly list full "
              "in %d pairs); without the fix (all %u brush faces): %d fall, the list full in %d pairs", fell_new,
              full_new, (unsigned)raw.size(), fell_old, full_old);
        s.set_world(tris, e);
    }
    s.shutdown();
}

// ---- 0.9.2: bounded thin-wall middle faces (sadc docs/research/gsa1_090_water.md GRID-TW1 = gsa1_090_collision.md F4,
// with both reviews) ------------------------------------------------------------------------------------------------
// Until 0.9.1 thin_wall_solid skipped every plane within 0.999 of the wall's own when it clipped the middle face, so a
// sliver prop hull (4 planes in two nearly coincident antiparallel pairs: rp_rockford_v2b's
// models/props_rooftop/chimneypipe_cluster02a and others) or a wedge brush whose end plane is 2.6 degrees off the wall
// (rockford's (3304 -288 528)..(3312 1664 544), rp_nycity's two at x 13816 / 13320) left a "middle face" through the
// whole map: the hidden-face removal cut it by every solid it crossed (rockford's GRID went over its limit: no
// character; nycity got invisible walls 464 units high). Here each fixture stands in a closed room 12,000 units wide
// (six slabs), which cuts such a face into pieces inside the room as the map's solids did; every triangle that is not
// on one of the room's planes is the fixture's, and every one must lie inside the fixture's box + 1 unit - with the
// guard (the default) and without it (the clip alone). Measured with 0.9.1's bsp.cpp: the sliver left 24.8 million
// square units of middle face in the room (6,000 units out), each wedge 0.1-3.2 million (5,000-5,600 units out).
static ConvexSolid faces_solid(const std::vector<std::array<float, 3>> &v, const std::vector<std::vector<int>> &faces)
{
    ConvexSolid cs;
    for (const std::vector<int> &f : faces) {
        for (size_t k = 1; k + 1 < f.size(); k++) {
            for (int idx : {f[0], f[k], f[k + 1]}) {
                cs.tris.insert(cs.tris.end(), v[(size_t)idx].begin(), v[(size_t)idx].end());
            }
        }
    }
    return cs;
}

// a wedge brush: x0..x1 thick, from y0 to ya (at x0) / yb (at x1), z0..z1 (its +y end is the slanted plane)
static ConvexSolid wedge_solid(float x0, float x1, float y0, float ya, float yb, float z0, float z1)
{
    std::vector<std::array<float, 3>> v = {{x0, y0, z0}, {x0, ya, z0}, {x1, yb, z0}, {x1, y0, z0},
                                           {x0, y0, z1}, {x0, ya, z1}, {x1, yb, z1}, {x1, y0, z1}};
    return faces_solid(v, {{0, 1, 2, 3}, {4, 7, 6, 5}, {0, 4, 5, 1}, {3, 2, 6, 7}, {0, 3, 7, 4}, {1, 5, 6, 2}});
}

struct Fixture {
    const char *what;
    std::vector<ConvexSolid> solids;
    float lo[3], hi[3];   // its box
};

static void tw1_fixture(const Fixture &fx)
{
    float c[3];
    for (int k = 0; k < 3; k++) {
        c[k] = 0.5f * (fx.lo[k] + fx.hi[k]);
    }
    // the room: interior c +- 6000 in x / y, z from 1000 below to 1000 above; walls 64 thick
    const float H = 6000.0f, Z = 1000.0f, W = 64.0f;
    float rlo[3] = {c[0] - H, c[1] - H, c[2] - Z}, rhi[3] = {c[0] + H, c[1] + H, c[2] + Z};
    for (int guard = 1; guard >= 0; guard--) {
        std::vector<ConvexSolid> solids = fx.solids;
        for (int wall = 0; wall < 6; wall++) {
            int ax = wall / 2;
            float a[3], b[3];
            for (int k = 0; k < 3; k++) {
                a[k] = rlo[k] - W;
                b[k] = rhi[k] + W;
            }
            if (wall % 2 == 0) {
                b[ax] = rlo[ax];
            } else {
                a[ax] = rhi[ax];
            }
            ConvexSolid cs;
            box_solid(a, b, nullptr, nullptr, cs);
            solids.push_back(std::move(cs));
        }
        BspWorldOptions o;
        o.guard = guard != 0;
        std::vector<sa1_collision_tri> out;
        BspWorldStats st;
        std::string e;
        bool ok = clean_solids(solids, o, out, st, e);
        uint32_t mine = 0, far = 0;
        double worst = 0.0;
        for (const sa1_collision_tri &t : out) {
            bool room = false;   // a triangle of the room: on one of its slabs' planes
            for (int k = 0; k < 3 && !room; k++) {
                for (float q : {rlo[k], rhi[k], rlo[k] - W, rhi[k] + W}) {
                    bool on = true;
                    for (int v = 0; v < 3; v++) {
                        on = on && std::fabs(t.v[v][k] - q) < 0.01f;
                    }
                    room = room || on;
                }
            }
            if (room) {
                continue;
            }
            mine++;
            bool out_box = false;
            for (int v = 0; v < 3; v++) {
                for (int k = 0; k < 3; k++) {
                    double d = std::max((double)fx.lo[k] - 1.0 - t.v[v][k], (double)t.v[v][k] - fx.hi[k] - 1.0);
                    if (d > 0.0) {
                        out_box = true;
                        worst = std::max(worst, d);
                    }
                }
            }
            far += out_box;
        }
        CHECK(ok && mine > 0 && far == 0 && st.tris_out_of_range == 0,
              "%s%s: %u triangles of it, %u outside its box + 1 (up to %.0f units out), %u thin walls, %u kept as two "
              "faces, %u thin stacks (%u faces left out), %u beyond any map", fx.what, guard ? "" : " (no guard)", mine,
              far, worst, st.thin_walls, st.thin_wall_kept, st.thin_stacks, st.thin_stack_faces, st.tris_out_of_range);
    }
}

static void test_thin_wall_bounds()
{
    std::printf("thin-wall middle faces stay inside their solid (GRID-TW1, 0.9.2)\n");
    // the sliver: a flat tetrahedron at rp_rockford_v2b's place, normal (0.9677 -0.0187 0.2513) (water doc G1 / its
    // review; the real hull's 4 planes lie within 0.0001 of each other, d 3559.76 / 3560.27 / -3560.25 / -3559.78):
    // two edges 4.7 and 1.2 units long crossing 0.001 units apart, so far from the origin that float rounding leaves
    // its 4 planes as two nearly coincident antiparallel pairs a few units "thick" by their d - the case 0.9.1 turned
    // into a middle face through the room (24.8 million square units of it inside the room, measured with 0.9.1's
    // bsp.cpp)
    double N[3] = {0.9677, -0.0187, 0.2513}, l = std::sqrt(N[0] * N[0] + N[1] * N[1] + N[2] * N[2]);
    for (double &x : N) {
        x /= l;
    }
    double U[3] = {-N[0] * N[2], -N[1] * N[2], 1.0 - N[2] * N[2]}, lu = std::sqrt(U[0] * U[0] + U[1] * U[1] + U[2] * U[2]);
    for (double &x : U) {
        x /= lu;
    }
    double V[3] = {N[1] * U[2] - N[2] * U[1], N[2] * U[0] - N[0] * U[2], N[0] * U[1] - N[1] * U[0]};
    const double C[3] = {-3951.55, -7369.0, 503.95}, a = 2.35, b = 0.6, h = 0.0005;
    std::vector<std::array<float, 3>> sv(4);
    for (int k = 0; k < 3; k++) {
        sv[0][k] = (float)(C[k] + U[k] * a + N[k] * h);
        sv[1][k] = (float)(C[k] - U[k] * a + N[k] * h);
        sv[2][k] = (float)(C[k] + V[k] * b - N[k] * h);
        sv[3][k] = (float)(C[k] - V[k] * b - N[k] * h);
    }
    Fixture sliver{"the rockford sliver hull", {faces_solid(sv, {{0, 1, 2}, {1, 0, 3}, {2, 3, 0}, {3, 2, 1}})}, {}, {}};
    for (int k = 0; k < 3; k++) {
        sliver.lo[k] = std::min(std::min(sv[0][k], sv[1][k]), std::min(sv[2][k], sv[3][k]));
        sliver.hi[k] = std::max(std::max(sv[0][k], sv[1][k]), std::max(sv[2][k], sv[3][k]));
    }
    tw1_fixture(sliver);
    // rockford's wedge brush (3304 -288 528)..(3312 1664 544), end plane (-0.9993 0.0370 0) d -3248.14 (as a hull)
    const double rn[2] = {-0.9993, 0.0370}, rd = -3248.14;
    float ra = (float)((rd - rn[0] * 3304.0) / rn[1]), rb = (float)((rd - rn[0] * 3312.0) / rn[1]);
    tw1_fixture(Fixture{"rockford's 8-unit wedge brush (end plane 2.1 degrees off the wall)",
                        {wedge_solid(3304, 3312, -288, ra, rb, 528, 544)}, {3304, -288, 528}, {3312, 1664, 544}});
    // rp_nycity's wedges: (13808 -14320 -280)..(13824 -12320 184), end plane (-0.9991 0.0425 0) through the corner
    // (13824 -12320); (13312 -13104 -280)..(13328 -12320 184), (0.9991 0.0425 0) through (13312 -12320)
    {
        const double n0 = -0.9991, n1 = 0.0425, d = n0 * 13824.0 + n1 * -12320.0;
        float ya = (float)((d - n0 * 13808.0) / n1);
        tw1_fixture(Fixture{"rp_nycity's wedge at x 13816", {wedge_solid(13808, 13824, -14320, ya, -12320, -280, 184)},
                            {13808, -14320, -280}, {13824, -12320, 184}});
    }
    {
        const double n0 = 0.9991, n1 = 0.0425, d = n0 * 13312.0 + n1 * -12320.0;
        float yb = (float)((d - n0 * 13328.0) / n1);
        tw1_fixture(Fixture{"rp_nycity's wedge at x 13320", {wedge_solid(13312, 13328, -13104, -12320, yb, -280, 184)},
                            {13312, -13104, -280}, {13328, -12320, 184}});
    }
    // a plain 8-unit wall still becomes one double-sided middle face (the 0.6 rule is unchanged)
    {
        const float wlo[3] = {-64, -4, 0}, whi[3] = {64, 4, 128};
        std::vector<ConvexSolid> s(1);
        box_solid(wlo, whi, nullptr, nullptr, s[0]);
        std::vector<sa1_collision_tri> out;
        BspWorldStats st;
        std::string e;
        clean_solids(s, BspWorldOptions(), out, st, e);
        uint32_t ds = 0, steep = 0;
        for (const sa1_collision_tri &t : out) {
            float e1[3], e2[3];
            for (int k = 0; k < 3; k++) {
                e1[k] = t.v[1][k] - t.v[0][k];
                e2[k] = t.v[2][k] - t.v[0][k];
            }
            float cz = e1[0] * e2[1] - e1[1] * e2[0], cx = e1[1] * e2[2] - e1[2] * e2[1], cy = e1[2] * e2[0] - e1[0] * e2[2];
            if (std::fabs(cy) > 0.99f * std::sqrt(cx * cx + cy * cy + cz * cz)) {
                steep++;
                ds += (t.surface & SA1_SURFACE_DOUBLE_SIDED) && std::fabs(t.v[0][1]) < 0.01f &&
                      std::fabs(t.v[1][1]) < 0.01f && std::fabs(t.v[2][1]) < 0.01f;
            }
        }
        CHECK(st.thin_walls == 1 && steep > 0 && ds == steep,
              "an 8-unit wall: one double-sided middle face at y 0 (%u of %u triangles facing +-y), %u thin walls", ds,
              steep, st.thin_walls);
    }
}

// ---- 0.9.3: ceilings from below, thin planks from above, loops (sadc docs/research/gsa1_091b_ceiling.md FIX-C,
// gsa1_091a_loop.md LOOP-G1 / LOOP-L1, with their reviews) through gsa1::Session and libsa1's GRID -------------------------
extern "C" {
struct diag_player_ptrs {
    uint32_t tp, twp, mwp, pwp, csts;
};
void sa1g_world_player(const struct sa1g_world *w, struct diag_player_ptrs *out);
}
// the ground speed (playerwk spd.x, SA1 units per step), as a dash panel sets it (tests/diag_maps.cpp)
static void set_ground_speed(Session &s, int32_t id, float v)
{
    Character *c = s.get(id);
    sa1g_world *w = c ? sa1_character_world(s.ctx(), c->id) : nullptr;
    if (!w) {
        return;
    }
    diag_player_ptrs pp;
    std::memset(&pp, 0, sizeof pp);
    sa1g_world_player(w, &pp);
    void *p = pp.pwp ? sa1g_world_ptr(w, pp.pwp + 0x38) : nullptr;
    if (p) {
        std::memcpy(p, &v, 4);
    }
}

static void box_into(std::vector<ConvexSolid> &s, float x0, float y0, float z0, float x1, float y1, float z1)
{
    const float a[3] = {x0, y0, z0}, b[3] = {x1, y1, z1};
    s.emplace_back();
    box_solid(a, b, nullptr, nullptr, s.back());
}
static ConvexSolid corner_solid(const std::vector<std::array<double, 3>> &v, const std::vector<std::vector<int>> &faces)
{
    ConvexSolid cs;
    for (const std::vector<int> &f : faces) {
        for (size_t k = 1; k + 1 < f.size(); k++) {
            for (int idx : {f[0], f[k], f[k + 1]}) {
                for (int c = 0; c < 3; c++) {
                    cs.tris.push_back((float)v[(size_t)idx][(size_t)c]);
                }
            }
        }
    }
    return cs;
}
// the gm_bigcity house (as tests/map_test.cpp house_solids: x 0..288, y 0..384, floor z 0, ceiling 128, ridge 160)
static void house_world(std::vector<ConvexSolid> &s)
{
    box_into(s, -64, -64, -16, 352, 448, 0);
    box_into(s, 16, 0, 0, 24, 384, 128);
    box_into(s, 264, 0, 0, 272, 384, 128);
    box_into(s, 16, 0, 0, 272, 8, 128);
    box_into(s, 16, 376, 0, 88, 384, 128);
    box_into(s, 88, 376, 0, 216, 384, 42);
    box_into(s, 88, 376, 84, 216, 384, 128);
    box_into(s, 216, 376, 0, 272, 384, 128);
    s.push_back(corner_solid({{0, 0, 128}, {288, 0, 128}, {144, 0, 160}, {0, 384, 128}, {288, 384, 128}, {144, 384, 160}},
                             {{0, 1, 4, 3}, {0, 2, 1}, {3, 4, 5}, {0, 3, 5, 2}, {1, 2, 5, 4}}));
}

// a world (clean_solids with o) installed the way the module does (prepared; undersides_drop = "Solid ceilings" off)
static bool install(Session &s, const std::vector<ConvexSolid> &solids, const BspWorldOptions &o, bool undersides_drop,
                    std::vector<sa1_collision_tri> &w, std::string &err)
{
    BspWorldStats st;
    if (!clean_solids(solids, o, w, st, err)) {
        return false;
    }
    PrepareOptions po;
    po.undersides_drop = undersides_drop;
    PrepareResult pr;
    if (!prepare_world(w, po, pr)) {
        err = pr.error;
        return false;
    }
    return s.set_world_prepared(pr.prepared, err);
}

// a jump from the floor at (x, y, 0) with the stick idle: did the feet get above z_ceil (within 96 units)?
static bool jump_through(Session &s, int kind, float x, float y, float z_ceil)
{
    std::string e;
    const float pos[3] = {x, y, 2.0f};
    int32_t id = s.create(kind, pos, 0.0f, e);
    if (id <= 0) {
        std::printf("        create: %s\n", e.c_str());
        return true;
    }
    bool through = false;
    for (int f = 0; f < 200; f++) {
        s.tick(id, 0.0f, 0.0f, 0.0f, f >= 20 && f < 60 ? SA1_BUTTON_JUMP : 0u, 1.0f / 60.0f);
        Character *c = s.get(id);
        if (!c) {
            break;
        }
        const float *p = c->st.position;
        through |= p[2] > z_ceil + 1.0f && std::fabs(p[0] - x) < 96.0f && std::fabs(p[1] - y) < 96.0f;
    }
    s.destroy(id);
    return through;
}

// one run into the synthetic loop (tests/map_test.cpp loop_solids: centre (0, 0, R), axis y) from (2424, 0, 8) toward -x,
// the ground speed set every step on the ground until x < 0.6 R; progress = the angle around the axis while on the ground
// within 24 units of the inner radius. 'C' completed (>= 300 degrees: the kept segments end at 303), 'T' on top of the
// loop, 'f' fell off inside
static char loop_run_session(Session &s, double R, double T, int kind, float speed, double *progress)
{
    std::string e;
    const float pos[3] = {2424.0f, 0.0f, 8.0f};
    const float yaw = 3.14159265f;
    int32_t id = s.create(kind, pos, yaw, e);
    if (id <= 0) {
        std::printf("        create: %s\n", e.c_str());
        return '?';
    }
    double phi_un = 0, phi_prev = 0, phi_max = -1e9;
    bool have = false, entered = false, top = false;
    for (int f = 0; f < 900; f++) {
        s.tick(id, 0.0f, f < 24 ? 0.0f : 1.0f, yaw, 0, 1.0f / 60.0f);
        Character *c = s.get(id);
        if (!c) {
            break;
        }
        const float *p = c->st.position;
        bool ground = (c->st.flags & SA1_STATE_ON_GROUND) != 0;
        double dx = p[0], dz = p[2] - R, r = std::sqrt(dx * dx + dz * dz);
        if (speed > 0.0f && ground && dx > 0.6 * R && !entered) {
            set_ground_speed(s, id, speed);
        }
        if (c->pairs_last == 0) {
            continue;
        }
        double phi = std::atan2(-dx, -dz) * 180.0 / 3.14159265358979;
        if (!have) {
            phi_un = phi;
            have = true;
        } else {
            double d = phi - phi_prev;
            while (d > 180) {
                d -= 360;
            }
            while (d < -180) {
                d += 360;
            }
            phi_un += d;
        }
        phi_prev = phi;
        bool on = ground && std::fabs(r - R) < 24.0;
        if (!entered && on && std::fabs(dx) < 0.25 * R) {
            entered = true;
            phi_un = phi;
        }
        if (entered && on) {
            phi_max = std::max(phi_max, phi_un);
        }
        top |= dz > 0 && r > R + T - 6.0 && std::fabs(dx) < R + T;
    }
    s.destroy(id);
    *progress = phi_max < -1e8 ? 0.0 : phi_max;
    return !entered ? '?' : phi_max >= 300.0 ? 'C' : top ? 'T' : 'f';
}

static void test_ceilings_loops_093(const std::string &gdi)
{
    std::printf("0.9.3: ceilings from below, thin planks from above, loops (the owner's 0.9.1a / 0.9.2 notes)\n");
    Session s;
    std::string err;
    if (!s.init(gdi, err)) {
        CHECK(false, "init: %s", err.c_str());
        return;
    }
    const int kinds[] = {SA1_CHAR_SONIC, SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA, SA1_CHAR_BIG};
    // the house: jumps under its ceiling (z 128) - under the roof's thin west / east ends, in the middle, beside the walls
    {
        std::vector<ConvexSolid> solids;
        house_world(solids);
        const float spots[][2] = {{56, 192}, {232, 192}, {144, 192}, {44, 100}, {144, 28}};
        int through[2] = {0, 0}, n = 0;
        for (int on = 1; on >= 0; on--) {
            std::vector<sa1_collision_tri> w;
            if (!install(s, solids, BspWorldOptions(), on == 0, w, err)) {
                CHECK(false, "the house: %s", err.c_str());
                return;
            }
            for (const auto &sp : spots) {
                for (int kind : kinds) {
                    bool t = jump_through(s, kind, sp[0], sp[1], 128.0f);
                    through[on] += t;
                    n += on;
                    if (t && on && g_verbose) {
                        std::printf("        %d through at (%.0f %.0f)\n", kind, sp[0], sp[1]);
                    }
                }
            }
        }
        CHECK(through[1] == 0, "the gm_bigcity house: %d of %d jumps of the six kinds went through its ceiling (with "
              "\"Solid ceilings\" off, as until 0.9.2: %d)", through[1], n, through[0]);
    }
    // thin planks from above (round 4b2's mechanism B, which the one-way rule fixed): Sonic and Knuckles run up a plank
    // ramp 8 units thick at dash speed and drop onto it; no fall-through. 10 degrees: its underside is front-only now; 20
    // degrees: left out as before (steeper than kFrontOnlyNz: libsa1's ramp_diag found dash-panel runs dipping under it)
    for (double deg : {10.0, 20.0}) {
        std::vector<ConvexSolid> solids;
        box_into(solids, -2000, -400, -16, 3000, 400, 0);
        const double a = deg * 3.14159265358979 / 180.0, L = 600.0, th = 8.0;
        const double ux = std::cos(a), uz = std::sin(a), nx = -std::sin(a), nz = std::cos(a);
        std::vector<std::array<double, 3>> v;
        for (double t : {0.0, L}) {
            for (double h : {0.0, th}) {
                for (double y : {-128.0, 128.0}) {
                    v.push_back({t * ux + h * nx, y, t * uz + h * nz});
                }
            }
        }
        solids.push_back(corner_solid(v, {{0, 1, 5, 4}, {2, 6, 7, 3}, {0, 4, 6, 2}, {1, 3, 7, 5}, {0, 2, 3, 1}, {4, 5, 7, 6}}));
        int falls[2] = {0, 0}, runs = 0;
        uint32_t fo = 0;
        for (int on = 1; on >= 0; on--) {
            std::vector<sa1_collision_tri> w;
            if (!install(s, solids, BspWorldOptions(), on == 0, w, err)) {
                CHECK(false, "the plank ramp: %s", err.c_str());
                return;
            }
            for (const sa1_collision_tri &t : w) {
                fo += on && (t.surface & SA1_SURFACE_FRONT_ONLY) != 0;
            }
            Soup soup;
            soup.build(w);
            for (int kind : {SA1_CHAR_SONIC, SA1_CHAR_KNUCKLES}) {
                for (float speed : {0.0f, 10.0f, 16.0f, -1.0f}) {
                    std::string e;
                    const float pos[3] = {speed < 0 ? 300.0f : -900.0f, 0.0f, speed < 0 ? 400.0f : 4.0f};
                    int32_t id = s.create(kind, pos, 0.0f, e);
                    if (id <= 0) {
                        continue;
                    }
                    runs += on;
                    float prev[3] = {pos[0], pos[1], pos[2]};
                    for (int f = 0; f < 240; f++) {
                        Character *c = s.get(id);
                        if (!c) {
                            break;
                        }
                        if (speed > 0.0f && (c->st.flags & SA1_STATE_ON_GROUND) && c->st.position[0] < -40.0f) {
                            set_ground_speed(s, id, speed);
                        }
                        s.tick(id, 0.0f, f < 10 || speed < 0 ? 0.0f : 1.0f, 0.0f, 0, 1.0f / 60.0f);
                        c = s.get(id);
                        if (!c || c->pairs_last == 0) {
                            continue;
                        }
                        falls[on] += soup.fall_throughs(prev, c->st.position, 8.0f, 24.0f) > 0;
                        std::memcpy(prev, c->st.position, sizeof prev);
                    }
                    s.destroy(id);
                }
            }
        }
        CHECK(falls[1] == 0 && (deg > 15.0 ? fo == 0 : fo > 0),
              "a %.0f-degree plank ramp 8 units thick (%u front-only underside triangles): %d of %d runs and landings fell "
              "through it (with \"Solid ceilings\" off: %d)", deg, fo, falls[1], runs, falls[0]);
    }
    // the synthetic loop (radius 512, 32 thick) at the owner's thin walls 32: completed at loop speed, as the game runs a
    // loop on plain collision (gsa1_091a_loop.md 4); without the curved-surface rule Sonic was put on top of the loop
    {
        const double R = 512, T = 32;
        std::vector<ConvexSolid> solids;
        const double PI = 3.14159265358979;
        for (int k = 0; k < 16; k++) {
            double a0 = -PI / 2 - 2 * PI * k / 16, a1 = -PI / 2 - 2 * PI * (k + 1) / 16;
            double zmin = 1e300;
            for (double an : {a0, a1}) {
                for (double r : {R, R + T}) {
                    zmin = std::min(zmin, R + r * std::sin(an));
                }
            }
            if (k >= 8 && zmin < 60.0) {
                continue;
            }
            std::vector<std::array<double, 3>> pt;
            for (double an : {a0, a1}) {
                for (double r : {R, R + T}) {
                    for (double y : {-160.0, 160.0}) {
                        pt.push_back({r * std::cos(an), y, R + r * std::sin(an)});
                    }
                }
            }
            solids.push_back(corner_solid(pt, {{0, 1, 5, 4}, {2, 6, 7, 3}, {0, 4, 6, 2}, {1, 3, 7, 5}, {0, 2, 3, 1}, {4, 5, 7, 6}}));
        }
        box_into(solids, -4000, -1200, -64, 4000, 1200, 0);
        std::string runs[2];
        int done[2] = {0, 0}, top[2] = {0, 0};
        char slow = '?';
        for (int fix = 1; fix >= 0; fix--) {
            BspWorldOptions o;
            o.thin_wall_max = 32.0f;
            o.curved = fix != 0;
            std::vector<sa1_collision_tri> w;
            if (!install(s, solids, o, false, w, err)) {
                CHECK(false, "the loop: %s", err.c_str());
                return;
            }
            for (float speed : {8.0f, 10.0f, 12.0f, 16.0f}) {
                double prog = 0;
                char r = loop_run_session(s, R, T, SA1_CHAR_SONIC, speed, &prog);
                done[fix] += r == 'C' && speed >= 10.0f;
                top[fix] += r == 'T';
                runs[fix] += format(" %.0f:%c(%.0f)", speed, r, prog);
            }
            if (fix) {
                double prog = 0;
                slow = loop_run_session(s, R, T, SA1_CHAR_SONIC, 4.0f, &prog);
                runs[fix] += format("; running alone (4.0): %c(%.0f)", slow, prog);
            }
        }
        CHECK(done[1] == 3 && top[1] == 0 && slow != 'T',
              "a loop 32 units thick with thin walls 32: Sonic completes it at 10 / 12 / 16 units per step and is never put "
              "on top of it (C = completed, T = on top, f = fell off inside, as the game at 8 and below: gsa1_091a_loop.md "
              "5.3):%s; without the curved-surface rule:%s", runs[1].c_str(), runs[0].c_str());
    }
}

int main(int argc, char **argv)
{
    std::string bsp = gsa1_garrysmod_dir()[0] ? std::string(gsa1_garrysmod_dir()) + "\\maps\\gm_construct.bsp" : std::string();
    std::string gdi;
    const char *env = std::getenv("SA1_TEST_GDI");
    if (env) {
        gdi = env;
    }
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--bsp" && i + 1 < argc) {
            bsp = argv[++i];
        } else if (a == "--gdi" && i + 1 < argc) {
            gdi = argv[++i];
        } else if (a == "--verbose") {
            g_verbose = true;
        } else {
            std::printf("usage: collision_test [--bsp MAP.bsp] [--gdi GAME.gdi] [--verbose]\n");
            return 2;
        }
    }
    std::printf("G-SA1 collision_test (libsa1 %s)\n", sa1_version_string());
    double t0 = now_ms();
    test_thin_wall_bounds();
    std::vector<sa1_collision_tri> tris;
    test_map(bsp, tris);
    if (tris.empty()) {
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    if (gdi.empty()) {
        std::printf("Sonic on the map: skipped (no --gdi and no SA1_TEST_GDI)\n");
    } else {
        test_session(gdi, bsp, tris);
        test_ceilings_loops_093(gdi);
    }
    std::printf("\n%d checks, %d failed, %d known issue(s) (%.1f s)\n", g_checks, g_fail, g_known,
                (now_ms() - t0) / 1000.0);
    return g_fail ? 1 : 0;
}
