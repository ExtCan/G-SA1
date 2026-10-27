// diag_maps.cpp - G-SA1 0.3 diagnostics on real maps (offline, no Garry's Mod): map load cost, ramps at speed, tick
// cost and hangs ("going up a ramp too fast makes you fall through it", "the game is randomly freezing up").
// Not a pass / fail test: it measures and prints. Build and run: tests/build_diag_maps.py.
//
//   diag_maps --gdi GAME.gdi [--ramps N] [--random N] [--secs S] [--kinds LIST] [--watchdog S] [--verbose]
//             [--trace "x y z yaw approach kind"] MAP.bsp...
//
// It runs the module's path without the module: since 0.5 the map job (src/core/mapjob.*: what gsa1.MapStart ...
// MapApply do - world brushes, displacements and static props with their physics models from the game's files, all
// cleaned: hidden faces, one-way thin platforms, displacement winding; tests/gamefs.hpp stands in for Garry's Mod's
// file system), then libsa1 directly the way gsa1::Session does it (SOURCE coordinates, 4 Hammer units per SA1 unit;
// since 0.5.1 the world prepared by the map job's worker - sa1_collision_prepare_tris - and installed with
// sa1_collision_set_prepared, as gsa1.MapApply does; --set-static: sa1_collision_set_static as before, the GRID
// synthesis in the first world; sa1_character_create_ex(SA1_CREATE_WORLD); sa1_character_tick with the inverse
// dead-zone stick; 60 frames per second). The variants that change the triangles after the job or the GRID parameters
// (--tess, --drop-*, --max-edge, --cell, --cut, --dc-limits) and --legacy use set_static. The NEAR-poly lists printed by
// --trace / --replay come from sa1_debug_near_polys (libsa1 request 12). --legacy: 0.4's path instead (Bsp::build_world without one-way platforms, with
// thickened floors and 0.4's displacement winding, no static props). --no-props: the map job without static props.
//
// Per map:
//   load     Bsp::open + build_world time (and with remove_hidden off: the cost of the hidden-face removal), the
//            triangle counts, sa1_collision_set_static, the first character (the GRID synthesis) and a second one.
//   ramps    up to N ramps found in the triangle soup (land faces of 8..55 degrees whose run uphill reaches at least
//            48 units higher; the foot = where the floor below flattens out, with an open run-up in front of it);
//            each driven up by Sonic / Knuckles / Tails at top running speed (long run-up), with the ground speed set
//            to 10 and 16 SA1 units per step 200 units before the foot (a dash panel), and by spin dash (Sonic).
//            A fall-through = the body (8 units above the feet) crossing an up-facing land triangle from above with
//            that floor around the crossing point (24 units each way), as tests/collision_test.cpp counts it.
//   random   N runs from random open floors with random input (stick, jump, action, spin dash) for S seconds each,
//            every character kind in turn: every tick timed (pairs run, the longest tick, ticks > 16 / 50 ms), the
//            NEAR-poly list (full), the Ninja matrix stack depth (B_8C88F69C: leaks one slot per TOUCH overflow),
//            fall-throughs, faults. A watchdog thread prints the run and the last input and exits when one tick
//            takes longer than --watchdog seconds (default 20): a hang in native game code. Also every frame's
//            sa1_character_render, the game's events (no sounds), characters stuck for 3 s, process memory.
//
// Emulated fixes (the triangles are changed before set_static): --tess HU (cut every face into well-shaped pieces),
// --drop-under HU (no down-facing face with a walkable face that close above it), --drop-sliver HU, --thin HU
// (BspWorldOptions::thin_floor_min), --thin-wall HU (BspWorldOptions::thin_wall_max; 0 off), --no-hidden, --max-edge / --cell / --cut (GRID parameters). Debugging: --trace
// "foot_x foot_y foot_z uphill_yaw approach kind [runup]" (one ramp run frame by frame, the NEAR-poly list and its
// uncapped census at the first fall-through), --dump "x y z r" (the triangles near a point), --water (random runs
// above water). Findings: sadc/docs/research/gsa1_ramp_freeze.md.
//
// 0.9.3 (sadc docs/research/gsa1_091b_ceiling.md, gsa1_091a_loop.md; G-SA1 0.9.2 owner notes "every single ceiling can
// be jumped through", "going through loop forces me up onto the top of it"):
//   --ceiljump "x y z ceil_z"      the faces on the vertical line, then every kind of --jkinds (default 023567) jumps
//                                  from the floor at x y z under the ceiling plane ceil_z (and jumps twice): THROUGH
//                                  (the feet got above the plane), blocked (the head reached it) or short
//   --ceilgrid "x0 y0 x1 y1 step z ceil_z"   Sonic and Tails jump at every point of a grid
//   --loop "cx cy cz R T" --looprun "x y z yaw [frames]" [--speeds 6,8,10,12,16] [--loopkinds 0235] [--loopspin]
//                                  runs into a loop (axis along y) with the ground speed set like a dash panel:
//                                  COMPLETED / ON TOP / fell off; --looptop: Sonic and Knuckles land and run on the
//                                  loop's outer top (100 runs each: none may fall into the loop)
//   --undersides-drop / --no-front-only / --no-curved   the switches of the fixes (PrepareOptions::undersides_drop =
//                                  "Solid ceilings" off; BspWorldOptions::one_way_front_only / curved off)
//   --gmas                         every workshop GMA mounted (the static props of workshop maps)
//   --old-disp-brushes / --disp-cover-max HU   the tunnel switches (BspWorldOptions::disp_brush_exact = false: 0.9.2's
//                                  displacement-brush rule; disp_cover_max: 0 = up faces under displacement ground kept)
// and the random runs count the walls entered at body height (a steep face crossed into its back, or across a
// double-sided one), as sadc/build/research/collision/coll_diag does.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <array>
#include <map>
#include <set>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include <psapi.h>
#endif

static double private_mb()
{
    PROCESS_MEMORY_COUNTERS_EX pmc;
    std::memset(&pmc, 0, sizeof pmc);
    pmc.cb = sizeof pmc;
    if (!GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS *)&pmc, sizeof pmc)) {
        return -1.0;
    }
    return (double)pmc.PrivateUsage / (1024.0 * 1024.0);
}

#include "bsp.hpp"
#include "gamefs.hpp"
#include "libsa1_internal_api.hpp"
#include "mapdrive.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)
#include "mapjob.hpp"
#include "util.hpp"

using namespace gsa1;

extern "C" {
void *sa1g_world_ptr(const struct sa1g_world *w, uint32_t guest);
struct diag_player_ptrs {
    uint32_t tp, twp, mwp, pwp, csts;
};
void sa1g_world_player(const struct sa1g_world *w, struct diag_player_ptrs *out);
}

static const uint32_t kNearCount = 0x8C73E27Cu;   // B_8C73E27C (8C028BFE: 96 on the DC; libsa1's GRID worlds 256)
static int g_near_cap = 256;                      // the list's capacity in these worlds (--dc-limits: 96)
static const uint32_t kTouchCount = 0x8C73E400u;  // B_8C73E400 (8C029B00, 16 max)
static const uint32_t kMtxDepth = 0x8C88F69Cu;    // B_8C88F69C (Ninja matrix stack depth, limit 128)
static const float kDeg = 3.14159265f / 180.0f;
static bool g_verbose = false;

// ---- the triangle soup (tests/collision_test.cpp's Soup, Hammer units, Z up) ----------------------------------------
struct Hit {
    float z;
    int dir;   // +1 facing up, -1 down, 0 vertical
    uint32_t tri;
};

// the playable region: around the player starts, away from the 3D skybox (sky_camera)
struct Region {
    bool have_start = false, have_sky = false;
    float start[3] = {0, 0, 0}, sky[3] = {0, 0, 0};
    bool inside(float x, float y, float z) const
    {
        if (have_sky && std::fabs(z - sky[2]) < 2000.0f && std::fabs(x - sky[0]) < 8000.0f && std::fabs(y - sky[1]) < 8000.0f) {
            return false;
        }
        if (have_start && (z < start[2] - 3000.0f || z > start[2] + 5000.0f)) {
            return false;
        }
        return true;
    }
};

struct Soup {
    Region region;
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
                continue;   // the kill plane and the like
            }
            for (int32_t bx = (int32_t)std::floor(lo[0] / kBin); bx <= (int32_t)std::floor(hi[0] / kBin); bx++) {
                for (int32_t by = (int32_t)std::floor(lo[1] / kBin); by <= (int32_t)std::floor(hi[1] / kBin); by++) {
                    bins[{bx, by}].push_back(i);
                }
            }
        }
    }

    // the land faces a vertical line through (x, y) meets, highest first (no water, no kill plane)
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

    // the highest up-facing face at (x, y) not higher than z + up and not lower than z - down; -1 none
    int floor_near(float x, float y, float z, float up, float down, float *fz) const
    {
        std::vector<Hit> c;
        column(x, y, c);
        for (const Hit &h : c) {
            if (h.dir > 0 && h.z <= z + up && h.z >= z - down) {
                *fz = h.z;
                return (int)h.tri;
            }
        }
        return -1;
    }

    // anything (any face) between z + lo and z + hi above (x, y)
    bool blocked_above(float x, float y, float z, float lo, float hi) const
    {
        std::vector<Hit> c;
        column(x, y, c);
        for (const Hit &h : c) {
            if (h.z > z + lo && h.z < z + hi) {
                return true;
            }
        }
        return false;
    }

    // a wall-like face (|n.z| < 0.5) within r of (x, y) horizontally, overlapping z .. z + h
    bool wall_near(float x, float y, float z, float r, float h) const
    {
        std::set<uint32_t> seen;
        for (int32_t bx = (int32_t)std::floor((x - r) / kBin); bx <= (int32_t)std::floor((x + r) / kBin); bx++) {
            for (int32_t by = (int32_t)std::floor((y - r) / kBin); by <= (int32_t)std::floor((y + r) / kBin); by++) {
                auto it = bins.find({bx, by});
                if (it == bins.end()) {
                    continue;
                }
                for (uint32_t i : it->second) {
                    if (!seen.insert(i).second || std::fabs(n[3 * i + 2]) >= 0.5f ||
                        (t[i].surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER))) {
                        continue;
                    }
                    const sa1_collision_tri &q = t[i];
                    float zlo = std::min(q.v[0][2], std::min(q.v[1][2], q.v[2][2]));
                    float zhi = std::max(q.v[0][2], std::max(q.v[1][2], q.v[2][2]));
                    if (zhi < z + 1.0f || zlo > z + h) {
                        continue;
                    }
                    float d = n[3 * i] * (x - q.v[0][0]) + n[3 * i + 1] * (y - q.v[0][1]) + n[3 * i + 2] * (z + 0.5f * h - q.v[0][2]);
                    if (std::fabs(d) > r) {
                        continue;
                    }
                    float px = x - d * n[3 * i], py = y - d * n[3 * i + 1];
                    float xlo = std::min(q.v[0][0], std::min(q.v[1][0], q.v[2][0])) - 1.0f;
                    float xhi = std::max(q.v[0][0], std::max(q.v[1][0], q.v[2][0])) + 1.0f;
                    float ylo = std::min(q.v[0][1], std::min(q.v[1][1], q.v[2][1])) - 1.0f;
                    float yhi = std::max(q.v[0][1], std::max(q.v[1][1], q.v[2][1])) + 1.0f;
                    if (px >= xlo && px <= xhi && py >= ylo && py <= yhi) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    // segment p0 -> p1 (both lifted by `lift`) crossing an up-facing triangle from above, with that floor around the
    // crossing point (`around` units in x and y): falling through a floor, not off its edge. *tri: the first one
    int fall_throughs(const float p0[3], const float p1[3], float lift, float around, int *tri = nullptr) const
    {
        float a[3] = {p0[0], p0[1], p0[2] + lift}, c[3] = {p1[0], p1[1], p1[2] + lift};
        int count = 0;
        std::set<uint32_t> seen;
        int32_t bx0 = (int32_t)std::floor(std::min(a[0], c[0]) / kBin), bx1 = (int32_t)std::floor(std::max(a[0], c[0]) / kBin);
        int32_t by0 = (int32_t)std::floor(std::min(a[1], c[1]) / kBin), by1 = (int32_t)std::floor(std::max(a[1], c[1]) / kBin);
        if ((int64_t)(bx1 - bx0 + 1) * (by1 - by0 + 1) > 64) {
            return 0;   // a teleport / respawn
        }
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
                    bool interior = true;
                    for (int k = 0; k < 4 && interior; k++) {
                        float ox = (k == 0 ? around : k == 1 ? -around : 0.0f);
                        float oy = (k == 2 ? around : k == 3 ? -around : 0.0f);
                        float oz = -(nn[0] * ox + nn[1] * oy) / nn[2];
                        interior = floor_at(x[0] + ox, x[1] + oy, x[2] + oz, 1.5f);
                    }
                    if (interior) {
                        if (count == 0 && tri) {
                            *tri = (int)i;
                        }
                        count++;
                    }
                }
            }
        }
        return count;
    }

    // 0.9.3 (sadc build/research/collision coll_diag's measure, gsa1_090_collision.md): the segment a -> c crossing a
    // steep face (|n.z| < 0.5) into its back (single-sided) or across it (double-sided): a wall entered at body height
    int wall_entries(const float a[3], const float c[3], int *tri = nullptr) const
    {
        float d[3] = {c[0] - a[0], c[1] - a[1], c[2] - a[2]};
        float len = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
        if (len > 400.0f || len < 1e-3f) {
            return 0;   // a teleport / respawn, or no move
        }
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
                    if ((q.surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER)) || std::fabs(nn[2]) >= 0.5f) {
                        continue;
                    }
                    float da = 0.0f, dc = 0.0f;
                    for (int k = 0; k < 3; k++) {
                        da += nn[k] * (a[k] - q.v[0][k]);
                        dc += nn[k] * (c[k] - q.v[0][k]);
                    }
                    bool ds = (q.surface & SA1_SURFACE_DOUBLE_SIDED) != 0;
                    if (!((da >= -0.01f && dc < -0.01f) || (ds && da <= 0.01f && dc > 0.01f))) {
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
                    if (inside) {
                        if (count == 0 && tri) {
                            *tri = (int)i;
                        }
                        count++;
                    }
                }
            }
        }
        return count;
    }
};

// ---- libsa1 the way gsa1::Session drives it -------------------------------------------------------------------------
// gsa1::exact_stick (session.cpp): the inverse of the game's dead zone, so the game decodes the intended direction
static void exact_stick(float x, float y, float &sx, float &sy)
{
    float m = std::sqrt(x * x + y * y);
    if (!(m >= 1e-4f)) {
        sx = sy = 0.0f;
        return;
    }
    if (m > 1.0f) {
        x /= m;
        y /= m;
    }
    float dx = x * 115.0f, dy = -y * 115.0f;
    float px = std::round(dx + (dx >= 0.0f ? 12.0f : -12.0f));
    float py = std::round(dy + (dy >= 0.0f ? 12.0f : -12.0f));
    px = std::max(-127.0f, std::min(127.0f, px));
    py = std::max(-127.0f, std::min(127.0f, py));
    sx = px / 127.0f;
    sy = -py / 127.0f;
}

static uint32_t g_warns = 0;
static void log_cb(void *user, int32_t level, const char *msg)
{
    (void)user;
    if (level >= SA1_LOG_WARN) {
        g_warns++;
        if (g_verbose || g_warns <= 20) {
            std::printf("      [libsa1] %s\n", msg);
        }
    }
}

static const uint32_t kPlayable = (1u << SA1_CHAR_SONIC) | (1u << SA1_CHAR_TAILS) | (1u << SA1_CHAR_KNUCKLES) |
                                  (1u << SA1_CHAR_AMY) | (1u << SA1_CHAR_GAMMA) | (1u << SA1_CHAR_BIG);

static const char *kind_name(int k)
{
    static const char *names[] = {"Sonic", "Eggman", "Tails", "Knuckles", "Tikal", "Amy", "Gamma", "Big", "Super Sonic"};
    return k >= 0 && k <= 8 ? names[k] : "?";
}

// a kind's collision sphere radius (SA1 units: the physics table 8C1BDFE4, height / 2)
static float kind_radius(int k)
{
    switch (k) {
    case SA1_CHAR_TAILS: return 4.5f;
    case SA1_CHAR_KNUCKLES: return 5.7f;
    case SA1_CHAR_GAMMA: return 10.5f;
    case SA1_CHAR_BIG: return 8.5f;
    default: return 5.0f;
    }
}

static bool g_world_images = true;   // SA1_LOAD_WORLD_IMAGES (--no-world-images: each kind's first world composes it)

struct Lib {
    sa1_context *ctx = nullptr;
    double disc_ms = 0.0;

    bool init(const std::string &gdi, std::string &err)
    {
        sa1_host h;
        sa1_host_defaults(&h);
        h.log = log_cb;
        h.log_level = SA1_LOG_WARN;
        if (SA1_FAILED(sa1_init(&h, &ctx)) || !ctx) {
            err = "sa1_init";
            return false;
        }
        sa1_coords co;
        std::memset(&co, 0, sizeof co);
        co.struct_size = sizeof co;
        sa1_coords_preset(SA1_COORDS_PRESET_SOURCE, &co);
        sa1_set_coords(ctx, &co);
        sa1_load_options lo;
        std::memset(&lo, 0, sizeof lo);
        lo.struct_size = sizeof lo;
        lo.characters = kPlayable;
        lo.flags = SA1_LOAD_DEFAULT | (g_world_images ? SA1_LOAD_WORLD_IMAGES : 0u);   // as the module (0.5.1)
        double t0 = now_ms();
        sa1_status st = sa1_load_disc(ctx, gdi.c_str(), &lo);
        disc_ms = now_ms() - t0;
        if (SA1_FAILED(st)) {
            err = format("sa1_load_disc: %s: %s", sa1_status_string(st), sa1_last_error(ctx));
            return false;
        }
        return true;
    }
    void shutdown()
    {
        if (ctx) {
            sa1_shutdown(ctx);
            ctx = nullptr;
        }
    }
};

// ---- the watchdog ---------------------------------------------------------------------------------------------------
static volatile LONG g_in_tick = 0;
static volatile ULONGLONG g_tick_t0 = 0;
static char g_what[1024];
static double g_watchdog_s = 20.0;

static DWORD WINAPI watchdog(LPVOID)
{
    for (;;) {
        Sleep(200);
        if (g_in_tick && GetTickCount64() - g_tick_t0 > (ULONGLONG)(g_watchdog_s * 1000.0)) {
            std::printf("\nHANG: one sa1_character_tick has run for more than %.0f s\n  %s\n", g_watchdog_s, g_what);
            std::fflush(stdout);
            ExitProcess(3);
        }
    }
    return 0;
}

// ---- one character --------------------------------------------------------------------------------------------------
struct Chr {
    sa1_context *ctx = nullptr;
    sa1_character_id id = 0;
    int kind = 0;
    struct sa1g_world *w = nullptr;
    sa1_state_ex st{};
    double tick_ms = 0.0;
    uint32_t pairs = 0;     // pairs the last tick ran

    bool create(sa1_context *c, int k, const float pos[3], float yaw, double *ms, std::string &err)
    {
        ctx = c;
        kind = k;
        sa1_character_desc d;
        std::memset(&d, 0, sizeof d);
        d.struct_size = sizeof d;
        d.kind = k;
        d.flags = SA1_CREATE_WORLD;
        for (int a = 0; a < 3; a++) {
            d.position[a] = pos[a];
        }
        d.yaw = yaw;
        double t0 = now_ms();
        sa1_status s = sa1_character_create_ex(ctx, &d, &id);
        if (ms) {
            *ms = now_ms() - t0;
        }
        if (SA1_FAILED(s)) {
            err = format("create %s: %s: %s", kind_name(k), sa1_status_string(s), sa1_last_error(ctx));
            id = 0;
            return false;
        }
        w = sa1_character_world(ctx, id);
        refresh();
        return true;
    }
    void destroy()
    {
        if (id) {
            sa1_character_destroy(ctx, id);
            id = 0;
        }
    }
    void refresh()
    {
        std::memset(&st, 0, sizeof st);
        st.struct_size = sizeof st;
        sa1_character_state_ex(ctx, id, &st);
    }
    sa1_status tick(float sx, float sy, float cam_yaw, uint32_t buttons, float dt)
    {
        sa1_input in;
        std::memset(&in, 0, sizeof in);
        in.struct_size = sizeof in;
        exact_stick(sx, sy, in.stick_x, in.stick_y);
        in.camera_yaw = cam_yaw;
        in.buttons = buttons;
        uint32_t step0 = st.step;
        g_tick_t0 = GetTickCount64();
        g_in_tick = 1;
        double t0 = now_ms();
        sa1_status s = sa1_character_tick(ctx, id, &in, dt, nullptr, nullptr);
        tick_ms = now_ms() - t0;
        g_in_tick = 0;
        refresh();
        pairs = (st.step - step0) / 2u;
        return s;
    }
    uint32_t word(uint32_t g) const
    {
        uint32_t v = 0;
        if (w) {
            sa1g_world_rd32(w, g, &v);
        }
        return v;
    }
    // the ground speed (playerwk.spd.x, SA1 units per step), as a dash panel sets it
    void set_ground_speed(float v)
    {
        diag_player_ptrs pp;
        std::memset(&pp, 0, sizeof pp);
        if (!w) {
            return;
        }
        sa1g_world_player(w, &pp);
        if (pp.pwp) {
            std::memcpy((uint8_t *)sa1g_world_ptr(w, pp.pwp) + 0x38, &v, 4);
        }
    }
    float speed() const   // SA1 units per step
    {
        return std::sqrt(st.speed[0] * st.speed[0] + st.speed[1] * st.speed[1] + st.speed[2] * st.speed[2]);
    }
    bool ground() const { return (st.flags & SA1_STATE_ON_GROUND) != 0; }
};

// ---- ramps ------------------------------------------------------------------------------------------------------------
struct Ramp {
    float foot[3];      // where the floor in front of the slope flattens out (Hammer units)
    float u[2];         // uphill direction
    float top[3];
    float slope;        // degrees (of the triangle it was found from)
    float runup;        // open flat floor in front of the foot
    uint32_t tri;
};

static float tri_area(const sa1_collision_tri &q)
{
    float e1[3], e2[3];
    for (int k = 0; k < 3; k++) {
        e1[k] = q.v[1][k] - q.v[0][k];
        e2[k] = q.v[2][k] - q.v[0][k];
    }
    float c[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
    return 0.5f * std::sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2]);
}

static void find_ramps(const Soup &s, size_t want, std::vector<Ramp> &out)
{
    std::vector<std::pair<float, uint32_t>> cand;
    const float lo = std::cos(55.0f * kDeg), hi = std::cos(8.0f * kDeg), flat = std::cos(5.0f * kDeg);
    for (uint32_t i = 0; i < s.t.size(); i++) {
        float nz = s.n[3 * i + 2];
        if ((s.t[i].surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER)) || nz < lo || nz > hi) {
            continue;
        }
        float a = tri_area(s.t[i]);
        if (a > 1500.0f) {
            cand.push_back({a, i});
        }
    }
    std::sort(cand.begin(), cand.end(), [](const std::pair<float, uint32_t> &a, const std::pair<float, uint32_t> &b) {
        return a.first > b.first;
    });
    for (size_t ci = 0; ci < cand.size() && ci < 6000 && out.size() < want; ci++) {
        uint32_t i = cand[ci].second;
        const sa1_collision_tri &q = s.t[i];
        float nx = s.n[3 * i], ny = s.n[3 * i + 1], h = std::sqrt(nx * nx + ny * ny);
        if (h < 1e-3f) {
            continue;
        }
        float u[2] = {-nx / h, -ny / h};
        float c[3] = {(q.v[0][0] + q.v[1][0] + q.v[2][0]) / 3, (q.v[0][1] + q.v[1][1] + q.v[2][1]) / 3,
                      (q.v[0][2] + q.v[1][2] + q.v[2][2]) / 3};
        if (!s.region.inside(c[0], c[1], c[2])) {
            continue;
        }
        // down to the foot
        float p[3] = {c[0], c[1], c[2]}, foot[3] = {0, 0, 0};
        int flatrun = 0, ok = 0;
        for (int k = 0; k < 500; k++) {
            float fz;
            p[0] -= 8.0f * u[0];
            p[1] -= 8.0f * u[1];
            int t = s.floor_near(p[0], p[1], p[2], 6.0f, 20.0f, &fz);
            if (t < 0) {
                break;
            }
            p[2] = fz;
            if (s.n[3 * t + 2] >= flat) {
                if (flatrun == 0) {
                    foot[0] = p[0];
                    foot[1] = p[1];
                    foot[2] = p[2];
                }
                if (++flatrun >= 6) {
                    ok = 1;
                    break;
                }
            } else {
                flatrun = 0;
            }
        }
        if (!ok) {
            continue;
        }
        // up to the top
        float tp[3] = {c[0], c[1], c[2]};
        flatrun = 0;
        for (int k = 0; k < 800; k++) {
            float fz, x = tp[0] + 8.0f * u[0], y = tp[1] + 8.0f * u[1];
            int t = s.floor_near(x, y, tp[2], 20.0f, 6.0f, &fz);
            if (t < 0) {
                break;
            }
            tp[0] = x;
            tp[1] = y;
            tp[2] = fz;
            if (s.n[3 * t + 2] >= flat && ++flatrun >= 6) {
                break;
            }
            if (s.n[3 * t + 2] < flat) {
                flatrun = 0;
            }
        }
        if (tp[2] - foot[2] < 48.0f) {
            continue;
        }
        // headroom over the slope's middle and the foot, the slope 32 units to each side
        float lat[2] = {-u[1], u[0]};
        if (s.blocked_above(foot[0], foot[1], foot[2], 1.0f, 120.0f) || s.blocked_above(c[0], c[1], c[2], 1.0f, 120.0f)) {
            continue;
        }
        float fz;
        if (s.floor_near(c[0] + 32.0f * lat[0], c[1] + 32.0f * lat[1], c[2], 24.0f, 24.0f, &fz) < 0 ||
            s.floor_near(c[0] - 32.0f * lat[0], c[1] - 32.0f * lat[1], c[2], 24.0f, 24.0f, &fz) < 0) {
            continue;
        }
        // the run-up: flat, open floor in front of the foot
        float r[3] = {foot[0], foot[1], foot[2]}, runup = 0.0f;
        for (int k = 0; k < 300; k++) {
            float x = r[0] - 8.0f * u[0], y = r[1] - 8.0f * u[1];
            int t = s.floor_near(x, y, r[2], 2.0f, 2.0f, &fz);
            if (t < 0 || s.n[3 * t + 2] < 0.98f || s.blocked_above(x, y, fz, 1.0f, 100.0f) ||
                s.wall_near(x, y, fz, 40.0f, 64.0f)) {
                break;
            }
            r[0] = x;
            r[1] = y;
            r[2] = fz;
            runup += 8.0f;
        }
        if (runup < 256.0f) {
            continue;
        }
        bool dup = false;
        for (const Ramp &o : out) {
            float dx = o.foot[0] - foot[0], dy = o.foot[1] - foot[1];
            if (dx * dx + dy * dy < 300.0f * 300.0f && std::fabs(o.foot[2] - foot[2]) < 64.0f &&
                o.u[0] * u[0] + o.u[1] * u[1] > 0.8f) {
                dup = true;
                break;
            }
        }
        if (dup) {
            continue;
        }
        Ramp R;
        std::memcpy(R.foot, foot, sizeof foot);
        R.u[0] = u[0];
        R.u[1] = u[1];
        std::memcpy(R.top, tp, sizeof tp);
        R.slope = std::acos(std::max(-1.0f, std::min(1.0f, s.n[3 * i + 2]))) / kDeg;
        R.runup = runup;
        R.tri = i;
        out.push_back(R);
    }
}

// What 8C028BFE would have collected without its 96-entry cap, for player 0's csts as it is now: every polygon of
// every cached land object that is in the gathered list (B_8C754EF4 / B_8C754EF0) and passes the sphere test
// |c - pos|^2 <= 1.3 * ((|spd| + radius)^2 + rr). up_after: polygons facing up (n.y > 0.5, SA1 space) that come
// after the 96th in list order (the order the game walks; the cap drops them). Diagnostics only (reads guest memory).
// the NEAR-poly list of the character's last query (libsa1 request 12: sa1_debug_near_polys); returns the entries
static uint32_t near_polys(const Chr &C, sa1_near_info &ni, std::vector<sa1_near_poly> &out)
{
    std::memset(&ni, 0, sizeof ni);
    ni.struct_size = sizeof ni;
    out.assign(256, sa1_near_poly());
    uint32_t n = 0;
    if (sa1_debug_near_polys(C.ctx, C.id, &ni, out.data(), (uint32_t)out.size(), &n) != SA1_OK) {
        n = 0;
    }
    out.resize(n);
    return n;
}

struct NearCensus {
    int total = 0, up_total = 0, up_after = 0, lists = 0;
};

static float gf(const Chr &C, uint32_t g)
{
    uint32_t v = C.word(g);
    float f;
    std::memcpy(&f, &v, 4);
    return f;
}

static NearCensus near_census(const Chr &C)
{
    NearCensus N;
    diag_player_ptrs pp;
    std::memset(&pp, 0, sizeof pp);
    if (!C.w) {
        return N;
    }
    sa1g_world_player(C.w, &pp);
    if (!pp.csts) {
        return N;
    }
    float radius = gf(C, pp.csts), pos[3] = {gf(C, pp.csts + 4), gf(C, pp.csts + 8), gf(C, pp.csts + 12)};
    float spd[3] = {gf(C, pp.csts + 16), gf(C, pp.csts + 20), gf(C, pp.csts + 24)};
    float r = std::sqrt(spd[0] * spd[0] + spd[1] * spd[1] + spd[2] * spd[2]) + radius, rr = r * r;
    int32_t ngath = (int32_t)C.word(0x8C754EF0u);
    std::set<uint32_t> gathered;
    for (int32_t i = 0; i < ngath && i < 1024; i++) {
        gathered.insert(C.word(0x8C754EF4u + 12u * (uint32_t)i + 4u));
    }
    int guard = 0;
    for (uint32_t lp = C.word(0x8C02D548u); lp && guard < 256; lp = C.word(lp), guard++) {
        if (!gathered.count(C.word(lp + 8))) {
            continue;
        }
        N.lists++;
        int g2 = 0;
        for (uint32_t np = C.word(lp + 0x10); np && g2 < 8192; np = C.word(np), g2++) {
            float c[3] = {gf(C, np + 8), gf(C, np + 12), gf(C, np + 16)}, prr = gf(C, np + 20);
            float d = (c[0] - pos[0]) * (c[0] - pos[0]) + (c[1] - pos[1]) * (c[1] - pos[1]) + (c[2] - pos[2]) * (c[2] - pos[2]);
            if (d > (rr + prr) * 1.3f) {
                continue;
            }
            float v[9];
            for (int k = 0; k < 9; k++) {
                v[k] = gf(C, np + 0x18 + 4u * (uint32_t)k);
            }
            float e1[3] = {v[3] - v[0], v[4] - v[1], v[5] - v[2]}, e2[3] = {v[6] - v[0], v[7] - v[1], v[8] - v[2]};
            float n[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
            float l = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
            bool up = l > 0.0f && std::fabs(n[1] / l) > 0.5f;   // the winding may be either way: |n.y|
            N.total++;
            N.up_total += up;
            if (up && N.total > 96) {
                N.up_after++;
            }
        }
    }
    return N;
}

struct Approach {
    const char *name;
    float runup;        // HU in front of the foot (at most the ramp's own)
    float boost;        // SA1 units per step set 200 HU before the foot; 0 none
    bool spin;
    float stick = 1.0f;
    bool trace_only = false;    // only through --trace
};
static const Approach kApproaches[] = {
    {"top", 2400.0f, 0.0f, false},
    {"boost10", 900.0f, 10.0f, false},
    {"boost16", 900.0f, 16.0f, false},
    {"spindash", 500.0f, 0.0f, true},
    {"jog", 2400.0f, 0.0f, false, 0.55f, true},
    {"walk", 2400.0f, 0.0f, false, 0.35f, true},
};

struct RunResult {
    bool created = false, fault = false;
    int falls = 0, frames = 0;
    float foot_speed = 0.0f, max_speed = 0.0f, max_along = -1e9f;
    float fall_pos[3] = {0, 0, 0}, fall_prev[3] = {0, 0, 0};
    int fall_tri = -1, fall_frame = -1, near_max = 0, near_full = 0;
    uint32_t mtx_max = 0;
    double tick_max = 0.0;
    std::string err, log;
};

// one run up a ramp; print: every frame with a pair
static RunResult ramp_run(Lib &L, const Soup &s, const Ramp &R, const Approach &A, int kind, bool print)
{
    RunResult res;
    float run = std::min(R.runup, A.runup);
    float start[3] = {R.foot[0] - run * R.u[0], R.foot[1] - run * R.u[1], R.foot[2] + 8.0f};
    float yaw = std::atan2(R.u[1], R.u[0]);
    float len = std::sqrt((R.top[0] - R.foot[0]) * (R.top[0] - R.foot[0]) + (R.top[1] - R.foot[1]) * (R.top[1] - R.foot[1]));
    Chr C;
    std::snprintf(g_what, sizeof g_what, "ramp run: %s %s from (%.1f %.1f %.1f) yaw %.1f", kind_name(kind), A.name,
                  start[0], start[1], start[2], yaw / kDeg);
    if (!C.create(L.ctx, kind, start, yaw, nullptr, res.err)) {
        return res;
    }
    res.created = true;
    float prev[3] = {C.st.position[0], C.st.position[1], C.st.position[2]};
    bool boosted = false, crossed = false;
    int frames = (int)(60.0f * (0.5f + (A.spin ? 1.0f : 0.0f) + 4.0f + run / 400.0f) / (A.stick < 0.9f ? A.stick * A.stick : 1.0f));
    for (int f = 0; f < frames; f++) {
        float t = f / 60.0f, sy = A.stick;
        uint32_t btn = 0;
        if (t < 0.4f) {
            sy = 0.0f;
        } else if (A.spin && t < 1.4f) {
            sy = 0.0f;
            btn = SA1_BUTTON_ACTION;
        }
        sa1_status st = C.tick(0.0f, sy, yaw, btn, 1.0f / 60.0f);
        res.tick_max = std::max(res.tick_max, C.tick_ms);
        if (SA1_FAILED(st)) {
            res.fault = true;
            res.err = format("tick: %s: %s", sa1_status_string(st), sa1_last_error(L.ctx));
            break;
        }
        const float *p = C.st.position;
        float along = (p[0] - R.foot[0]) * R.u[0] + (p[1] - R.foot[1]) * R.u[1];
        if (A.boost > 0.0f && !boosted && along > -200.0f) {
            C.set_ground_speed(A.boost);
            boosted = true;
        }
        if (C.pairs == 0) {
            continue;
        }
        res.frames++;
        float v = C.speed();
        res.max_speed = std::max(res.max_speed, v);
        if (!crossed && along > 0.0f) {
            crossed = true;
            res.foot_speed = v;
        }
        res.max_along = std::max(res.max_along, along);
        int nn = (int)C.word(kNearCount);
        res.near_max = std::max(res.near_max, nn);
        res.near_full += nn >= g_near_cap;
        res.mtx_max = std::max(res.mtx_max, C.word(kMtxDepth));
        int tri = -1;
        int fl = s.fall_throughs(prev, p, 8.0f, 24.0f, &tri);
        if (fl && res.falls == 0) {
            std::memcpy(res.fall_pos, p, sizeof res.fall_pos);
            std::memcpy(res.fall_prev, prev, sizeof res.fall_prev);
            res.fall_tri = tri;
            res.fall_frame = f;
        }
        res.falls += fl;
        if (print || (fl && g_verbose)) {
            std::printf("        f %4d pos (%8.1f %8.1f %8.1f) along %7.1f %s v %5.2f mode %2d act %3d NEAR %2d TOUCH %2d mtx "
                        "%u%s\n", f, p[0], p[1], p[2], along, C.ground() ? "G" : "-", v, (int)C.st.mode, (int)C.st.action,
                        nn, (int)C.word(kTouchCount), C.word(kMtxDepth), fl ? "  FALL-THROUGH" : "");
        }
        if (print && fl && res.falls == fl) {
            // the NEAR-poly list of the last query (sa1_debug_near_polys, libsa1 request 12: the raised list of 256 in
            // GRID worlds, the game's B_8C73E280[96] with --dc-limits), host space, and the land objects gathered for it
            sa1_near_info ni;
            std::vector<sa1_near_poly> np;
            uint32_t got = near_polys(C, ni, np);
            NearCensus N = near_census(C);
            std::printf("        NEAR-poly list at this frame: %u entries (capacity %u, list at %08X, full %u times in this "
                        "world); without the cap the query would have collected %d polygons from %d land objects (%d "
                        "facing up or down, %d of them after the 96th)\n", ni.count, ni.capacity, ni.list, ni.full, N.total,
                        N.lists, N.up_total, N.up_after);
            for (uint32_t k = 0; k < got; k++) {
                const sa1_near_poly &q = np[k];
                float e[3];
                for (int a = 0; a < 3; a++) {
                    const float *u = q.v[a], *v = q.v[(a + 1) % 3];
                    e[a] = std::sqrt((u[0] - v[0]) * (u[0] - v[0]) + (u[1] - v[1]) * (u[1] - v[1]) + (u[2] - v[2]) * (u[2] - v[2]));
                }
                float dx = q.center[0] - p[0], dy = q.center[1] - p[1], dz = q.center[2] - p[2];
                std::printf("          %3u centre (%8.1f %8.1f %8.1f) %6.1f away, radius %6.1f, edges %6.1f %6.1f %6.1f, attr "
                            "%08X\n", k, q.center[0], q.center[1], q.center[2], std::sqrt(dx * dx + dy * dy + dz * dz),
                            q.radius, e[0], e[1], e[2], q.attr);
            }
        }
        std::memcpy(prev, p, sizeof prev);
        if (along > len + 300.0f || p[2] < R.foot[2] - 600.0f || (crossed && along < -run - 200.0f)) {
            break;
        }
        if (res.falls && f > res.fall_frame + 60) {
            break;
        }
    }
    C.destroy();
    return res;
}

// the polygons of the last NEAR-poly query within `within` HU of p (sa1_debug_near_polys: host space, the list the
// query filled - libsa1's raised list of 256 in GRID worlds, the game's B_8C73E280 otherwise): the normal of the game's
// winding and the body point's (20 HU above the feet) height above the polygon's plane
static void print_near_polys(const Chr &C, const float p[3], float within)
{
    sa1_near_info ni;
    std::vector<sa1_near_poly> np;
    uint32_t got = near_polys(C, ni, np);
    std::printf("          (the list at %08X: %s, capacity %u, %u entries, full %u times, peak %u)\n", ni.list,
                ni.block && ni.list == ni.block + 0x14u ? "libsa1's raised list" : "B_8C73E280", ni.capacity, ni.count,
                ni.full, ni.peak_life);
    int shown = 0;
    for (uint32_t k = 0; k < got; k++) {
        const sa1_near_poly &q = np[k];
        const float(*v)[3] = q.v;
        float e1[3] = {v[1][0] - v[0][0], v[1][1] - v[0][1], v[1][2] - v[0][2]};
        float e2[3] = {v[2][0] - v[0][0], v[2][1] - v[0][1], v[2][2] - v[0][2]};
        float n[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
        float l = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        if (l > 0.0f) {
            for (int a = 0; a < 3; a++) {
                n[a] /= l;
            }
        }
        float dx = q.center[0] - p[0], dy = q.center[1] - p[1], dz = q.center[2] - p[2];
        if (std::sqrt(dx * dx + dy * dy + dz * dz) > within + q.radius) {
            continue;
        }
        float h = n[0] * (p[0] - v[0][0]) + n[1] * (p[1] - v[0][1]) + n[2] * (p[2] + 20.0f - v[0][2]);
        std::printf("          %3u n (%5.2f %5.2f %5.2f) body %+7.1f%s; (%.1f %.1f %.1f) (%.1f %.1f %.1f) (%.1f %.1f %.1f)\n",
                    k, n[0], n[1], n[2], h, (q.attr & 0x800000u) ? " both sides" : "", v[0][0], v[0][1], v[0][2],
                    v[1][0], v[1][1], v[1][2], v[2][0], v[2][1], v[2][2]);
        shown++;
    }
    std::printf("          (%d of %u listed polygons shown)\n", shown, got);
}

// ---- random play (freeze hunt) ---------------------------------------------------------------------------------------
struct RandStats {
    int runs = 0, falls = 0, fall_runs = 0, faults = 0, near_full_runs = 0, creates = 0;
    int wall_runs = 0, walls = 0;                // 0.9.3: runs that entered a wall at body height (crossings)
    std::vector<std::string> wall_notes, fall_notes;
    uint64_t ticks = 0, pairs = 0, ticks16 = 0, ticks50 = 0;
    double sum_ms = 0.0, tick_max = 0.0, create_max = 0.0, render_max = 0.0, render_sum = 0.0;
    uint64_t renders = 0, renders16 = 0;
    std::string worst_render;
    // events and stuck characters
    std::map<std::string, int> events;          // "type id" -> count (no sounds)
    int stuck = 0, deaths = 0;
    std::vector<std::string> stuck_notes;
    uint32_t mtx_max = 0;
    int mtx_runs = 0;   // runs that ended with the matrix stack deeper than 1
    std::string worst;
};

static uint32_t g_seed = 1;
static double rnd()
{
    g_seed = g_seed * 1664525u + 1013904223u;
    return (g_seed >> 8) / 16777216.0;
}

static bool g_water_spawn = false;   // --water: spawn above water surfaces instead of floors
// --replay "x y z kind seed": one random run again (the start, the character and the rng state its fall-through line
// printed), every frame printed from 40 frames before the first fall-through, and the polygons around it then
static bool g_replay = false;
static float g_replay_pos[3] = {0, 0, 0};
static int g_replay_kind = 0;
static uint32_t g_replay_seed = 0;
static void print_near_polys(const Chr &C, const float p[3], float within);

static void random_runs(Lib &L, const Soup &s, int n, float secs, const std::vector<int> &kinds, RandStats &R,
                        const char *map)
{
    std::vector<uint32_t> ups;
    std::vector<double> cum;
    double tot = 0.0;
    for (uint32_t i = 0; i < s.t.size(); i++) {
        const sa1_collision_tri &q = s.t[i];
        if (g_water_spawn ? !(q.surface & SA1_SURFACE_WATER) || s.n[3 * i + 2] < 0.9f
                          : (q.surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER)) || s.n[3 * i + 2] < 0.9f) {
            continue;
        }
        float cx = (q.v[0][0] + q.v[1][0] + q.v[2][0]) / 3, cy = (q.v[0][1] + q.v[1][1] + q.v[2][1]) / 3;
        float cz = (q.v[0][2] + q.v[1][2] + q.v[2][2]) / 3;
        if (std::fabs(cx) > 16000.0f || std::fabs(cy) > 16000.0f || !s.region.inside(cx, cy, cz)) {
            continue;
        }
        ups.push_back(i);
        tot += std::sqrt((double)tri_area(q));
        cum.push_back(tot);
    }
    if (ups.empty()) {
        return;
    }
    std::vector<Hit> col;
    for (int k = 0; k < n * 30 && R.runs < n; k++) {
        if (g_replay && R.runs > 0) {
            break;
        }
        size_t j = std::lower_bound(cum.begin(), cum.end(), rnd() * tot) - cum.begin();
        const sa1_collision_tri &q = s.t[ups[std::min(j, ups.size() - 1)]];
        double a = rnd(), b = rnd();
        if (a + b > 1.0) {
            a = 1.0 - a;
            b = 1.0 - b;
        }
        float pos[3];
        for (int c = 0; c < 3; c++) {
            pos[c] = (float)(q.v[0][c] + a * (q.v[1][c] - q.v[0][c]) + b * (q.v[2][c] - q.v[0][c]));
        }
        bool open = true;
        for (int d = 0; d < 4 && open && !g_water_spawn; d++) {
            open = s.floor_at(pos[0] + (d == 0 ? 24.0f : d == 1 ? -24.0f : 0.0f), pos[1] + (d == 2 ? 24.0f : d == 3 ? -24.0f : 0.0f),
                              pos[2], 1.0f);
        }
        if (g_replay) {
            open = true;
            g_seed = g_replay_seed;
            std::memcpy(pos, g_replay_pos, sizeof pos);
            pos[2] -= 8.0f;
        }
        if (!open || (!g_water_spawn && !g_replay && (s.blocked_above(pos[0], pos[1], pos[2], 0.5f, 72.0f) ||
                                                      s.wall_near(pos[0], pos[1], pos[2], 32.0f, 64.0f)))) {
            continue;
        }
        int kind = g_replay ? g_replay_kind : kinds[(size_t)R.runs % kinds.size()];
        uint32_t run_seed = g_seed;
        float start[3] = {pos[0], pos[1], pos[2] + 8.0f}, yaw = (float)(rnd() * 6.2831853);
        Chr C;
        std::string e;
        double cms = 0.0;
        std::snprintf(g_what, sizeof g_what, "%s random run %d: create %s at (%.1f %.1f %.1f)", map, R.runs, kind_name(kind),
                      start[0], start[1], start[2]);
        g_tick_t0 = GetTickCount64();
        g_in_tick = 1;
        bool ok = C.create(L.ctx, kind, start, yaw, &cms, e);
        g_in_tick = 0;
        R.creates++;
        R.create_max = std::max(R.create_max, cms);
        if (!ok) {
            std::printf("      %s\n", e.c_str());
            R.faults++;
            R.runs++;
            continue;
        }
        R.runs++;
        float prev[3] = {C.st.position[0], C.st.position[1], C.st.position[2]};
        float sx = 0, sy = 0, cam = yaw;
        uint32_t hold = 0;
        int hold_frames = 0, spin = 0, falls = 0, nfull = 0, walls = 0;
        std::vector<std::string> hist;
        bool replay_done = false;
        int replay_left = 0;
        int frames = (int)(secs * 60.0f);
        for (int f = 0; f < frames; f++) {
            if (f % 30 == 0) {
                double r = rnd(), ang = rnd() * 6.2831853;
                bool moving = rnd() < 0.75;
                sx = moving ? (float)std::sin(ang) : 0.0f;
                sy = moving ? (float)std::cos(ang) : 0.0f;
                hold = 0;
                hold_frames = 0;
                spin = 0;
                if (r < 0.2) {
                    hold = SA1_BUTTON_JUMP;
                    hold_frames = 6 + (int)(rnd() * 20);
                } else if (r < 0.3) {
                    hold = SA1_BUTTON_ACTION;
                    hold_frames = 4;
                } else if (r < 0.42) {
                    spin = 1;     // charge (stick released), then go
                } else if (r < 0.47) {
                    hold = SA1_BUTTON_ACTION2;
                    hold_frames = 4;
                }
            }
            cam += 0.004f;
            uint32_t btn = 0;
            float isx = sx, isy = sy;
            if (spin && f % 30 < 24) {
                btn = SA1_BUTTON_ACTION;
                isx = isy = 0.0f;
            } else if (hold && f % 30 < hold_frames) {
                btn = hold;
            }
            std::snprintf(g_what, sizeof g_what, "%s random run %d (seed state %u): %s from (%.1f %.1f %.1f) yaw %.1f, frame "
                          "%d, at (%.1f %.1f %.1f) mode %d action %d, stick (%.2f %.2f) camera %.2f buttons %u", map, R.runs - 1,
                          g_seed, kind_name(kind), start[0], start[1], start[2], yaw / kDeg, f, C.st.position[0],
                          C.st.position[1], C.st.position[2], (int)C.st.mode, (int)C.st.action, isx, isy, cam, btn);
            sa1_status st = C.tick(isx, isy, cam, btn, 1.0f / 60.0f);
            R.ticks++;
            R.pairs += C.pairs;
            R.sum_ms += C.tick_ms;
            R.ticks16 += C.tick_ms > 16.0;
            R.ticks50 += C.tick_ms > 50.0;
            if (C.tick_ms > R.tick_max) {
                R.tick_max = C.tick_ms;
                R.worst = std::string(g_what) + format(" -> %.2f ms (%u pairs)", C.tick_ms, C.pairs);
            }
            if (SA1_FAILED(st)) {
                R.faults++;
                std::printf("      FAULT %s: %s: %s\n", g_what, sa1_status_string(st), sa1_last_error(L.ctx));
                break;
            }
            {
                // the module renders every frame (gsa1.Render -> sa1_character_render at the accumulator's alpha)
                const sa1_render *rr = nullptr;
                g_tick_t0 = GetTickCount64();
                g_in_tick = 1;
                double r0 = now_ms();
                sa1_character_render(L.ctx, C.id, -1.0f, &rr);
                double rms = now_ms() - r0;
                g_in_tick = 0;
                R.renders++;
                R.render_sum += rms;
                R.renders16 += rms > 16.0;
                if (rms > R.render_max) {
                    R.render_max = rms;
                    R.worst_render = std::string(g_what) + format(" -> render %.2f ms", rms);
                }
            }
            {
                sa1_event ev[64];
                uint32_t ne = 0;
                while (sa1_poll_events(L.ctx, ev, 64, &ne) == SA1_OK && ne > 0) {
                    for (uint32_t k = 0; k < ne; k++) {
                        uint32_t ty = ev[k].type;
                        if (ty == SA1_EVENT_SOUND || ty == SA1_EVENT_SOUND_STOP || ty == SA1_EVENT_VOICE || ty == SA1_EVENT_RUMBLE) {
                            continue;
                        }
                        R.deaths += ty == SA1_EVENT_DEATH;
                        static const char *tn[] = {"?", "sound", "stop", "voice", "jingle", "rumble", "death", "restart",
                                                   "respawn", "missing_action", "unimplemented", "capacity", "time_up",
                                                   "fault"};
                        R.events[format("%s %08X", ty < 14 ? tn[ty] : "?", ev[k].id)]++;
                    }
                    if (ne < 64) {
                        break;
                    }
                }
            }
            // stuck: the stick held for 3 s and the character moved less than 8 units
            {
                static float anchor[3];
                static int held = 0;
                bool pushing = (isx != 0.0f || isy != 0.0f);
                if (f == 0 || !pushing) {
                    held = 0;
                    std::memcpy(anchor, C.st.position, sizeof anchor);
                } else if (++held == 180) {
                    float dx = C.st.position[0] - anchor[0], dy = C.st.position[1] - anchor[1], dz = C.st.position[2] - anchor[2];
                    if (dx * dx + dy * dy + dz * dz < 64.0f) {
                        R.stuck++;
                        if (R.stuck_notes.size() < 6) {
                            R.stuck_notes.push_back(format("%s at (%.0f %.0f %.0f) mode %d action %d %s", kind_name(kind),
                                                           C.st.position[0], C.st.position[1], C.st.position[2], (int)C.st.mode,
                                                           (int)C.st.action, C.ground() ? "on the ground" : "in the air"));
                        }
                    }
                }
            }
            if (C.pairs == 0) {
                continue;
            }
            const float *p = C.st.position;
            int tri = -1, fl = s.fall_throughs(prev, p, 8.0f, 24.0f, &tri);
            if (fl && falls == 0 && g_verbose) {
                std::printf("      fall-through: %s; --replay \"%.2f %.2f %.2f %d %u\"\n", g_what, start[0], start[1], start[2],
                            kind, run_seed);
            }
            if (g_replay) {
                hist.push_back(format("        f %4d pos (%8.1f %8.1f %8.1f) %s v %5.2f mode %2d act %3d NEAR %3d TOUCH %2d "
                                      "stick (%.2f %.2f) btn %u%s", f, p[0], p[1], p[2], C.ground() ? "G" : "-", C.speed(),
                                      (int)C.st.mode, (int)C.st.action, (int)C.word(kNearCount),
                                      (int)C.word(kTouchCount), isx, isy, btn, fl ? "  FALL-THROUGH" : ""));
                if (fl && !replay_done) {
                    replay_done = true;
                    size_t from = hist.size() > 40 ? hist.size() - 40 : 0;
                    for (size_t h = from; h < hist.size(); h++) {
                        std::printf("%s\n", hist[h].c_str());
                    }
                    if (tri >= 0) {
                        const sa1_collision_tri &q = s.t[(size_t)tri];
                        std::printf("        crossed tri %d n (%.2f %.2f %.2f) surf %x (%.1f %.1f %.1f) (%.1f %.1f %.1f) "
                                    "(%.1f %.1f %.1f)\n", tri, s.n[3 * (size_t)tri], s.n[3 * (size_t)tri + 1],
                                    s.n[3 * (size_t)tri + 2], q.surface, q.v[0][0], q.v[0][1], q.v[0][2], q.v[1][0],
                                    q.v[1][1], q.v[1][2], q.v[2][0], q.v[2][1], q.v[2][2]);
                    }
                    std::printf("        the NEAR-poly list at this frame, polygons within 60 HU of the body:\n");
                    print_near_polys(C, p, 60.0f);
                    replay_left = 12;
                } else if (replay_done && replay_left > 0) {
                    replay_left--;
                    std::printf("%s\n", hist.back().c_str());
                }
            }
            if (fl && falls == 0 && R.fall_notes.size() < 12) {
                R.fall_notes.push_back(format("%s f%d (%.0f %.0f %.0f) -> (%.0f %.0f %.0f) v %.1f mode %d act %d; --replay "
                                              "\"%.2f %.2f %.2f %d %u\"", kind_name(kind), f, prev[0], prev[1], prev[2], p[0],
                                              p[1], p[2], C.speed(), (int)C.st.mode, (int)C.st.action, start[0], start[1],
                                              start[2], kind, run_seed));
            }
            falls += fl;
            {
                // 0.9.3: a wall entered at body height (the sphere's centre: the feet + its radius)
                float lift = 4.0f * kind_radius(kind);
                float wa[3] = {prev[0], prev[1], prev[2] + lift}, wc[3] = {p[0], p[1], p[2] + lift};
                int wt = -1, we = s.wall_entries(wa, wc, &wt);
                if (we && walls == 0 && R.wall_notes.size() < 12) {
                    const float *wn = &s.n[3 * (size_t)wt];
                    R.wall_notes.push_back(format("%s f%d (%.0f %.0f %.0f) -> (%.0f %.0f %.0f) v %.1f mode %d act %d, face n "
                                                  "(%.2f %.2f %.2f) surface %X; --replay \"%.2f %.2f %.2f %d %u\"",
                                                  kind_name(kind), f, prev[0], prev[1], prev[2], p[0], p[1], p[2], C.speed(),
                                                  (int)C.st.mode, (int)C.st.action, wn[0], wn[1], wn[2],
                                                  s.t[(size_t)wt].surface, start[0], start[1], start[2], kind, run_seed));
                }
                if (g_replay && we && walls == 0 && !replay_done) {
                    // --replay: the frames before the first wall entry and the polygons around it then
                    replay_done = true;
                    size_t from = hist.size() > 40 ? hist.size() - 40 : 0;
                    for (size_t h = from; h < hist.size(); h++) {
                        std::printf("%s%s\n", hist[h].c_str(), h + 1 == hist.size() ? "  WALL ENTRY" : "");
                    }
                    const sa1_collision_tri &q = s.t[(size_t)wt];
                    std::printf("        entered tri %d n (%.2f %.2f %.2f) surf %x (%.1f %.1f %.1f) (%.1f %.1f %.1f) (%.1f %.1f "
                                "%.1f)\n", wt, s.n[3 * (size_t)wt], s.n[3 * (size_t)wt + 1], s.n[3 * (size_t)wt + 2], q.surface,
                                q.v[0][0], q.v[0][1], q.v[0][2], q.v[1][0], q.v[1][1], q.v[1][2], q.v[2][0], q.v[2][1],
                                q.v[2][2]);
                    std::printf("        the NEAR-poly list at this frame, polygons within 60 HU of the body:\n");
                    print_near_polys(C, p, 60.0f);
                    replay_left = 12;
                }
                walls += we;
            }
            int nn = (int)C.word(kNearCount);
            nfull += nn >= g_near_cap;
            R.mtx_max = std::max(R.mtx_max, C.word(kMtxDepth));
            std::memcpy(prev, p, sizeof prev);
        }
        if (g_replay && g_verbose) {
            for (const std::string &h : hist) {   // --replay --verbose: every frame of the run
                std::printf("%s\n", h.c_str());
            }
        }
        R.walls += walls;
        R.wall_runs += walls > 0;
        R.falls += falls;
        R.fall_runs += falls > 0;
        R.near_full_runs += nfull > 0;
        R.mtx_runs += C.word(kMtxDepth) > 1;
        C.destroy();
    }
}

// ---- 0.9.3: ceilings and loops (sadc docs/research/gsa1_091b_ceiling.md, gsa1_091a_loop.md; their tools ceil_diag /
// loop_diag in sadc/build/research) -------------------------------------------------------------------------------------
// one jump under a ceiling: the character is created with its feet at pos (+2), stands 20 frames, then holds jump
// (approach 0: 40 frames; 2: twice) with the stick idle. "through": its feet got above the ceiling plane within 96 units.
struct JumpResult {
    bool ok = false, fault = false, through = false, ontop = false, bonk = false, end_ground = false;
    float maxz = -1e30f, top_max = -1e30f, end[3] = {0, 0, 0};
};
static JumpResult jump_test(Lib &L, const float pos[3], int kind, int approach, float ceil_z, bool trace)
{
    JumpResult r;
    Chr C;
    std::string e;
    float start[3] = {pos[0], pos[1], pos[2] + 2.0f};
    std::snprintf(g_what, sizeof g_what, "ceiling jump %s approach %d at (%.1f %.1f %.1f)", kind_name(kind), approach,
                  start[0], start[1], start[2]);
    if (!C.create(L.ctx, kind, start, 0.0f, nullptr, e)) {
        std::printf("      %s\n", e.c_str());
        return r;
    }
    r.ok = true;
    const float h = 8.0f * kind_radius(kind);   // the character's height (Hammer units)
    for (int f = 0; f < 200; f++) {
        uint32_t btn = 0;
        if (approach == 0) {
            btn = (f >= 20 && f < 60) ? SA1_BUTTON_JUMP : 0u;
        } else {
            btn = ((f >= 20 && f < 60) || (f >= 110 && f < 150)) ? SA1_BUTTON_JUMP : 0u;
        }
        sa1_status st = C.tick(0.0f, 0.0f, 0.0f, btn, 1.0f / 60.0f);
        if (SA1_FAILED(st)) {
            r.fault = true;
            std::printf("      FAULT %s: %s\n", g_what, sa1_last_error(L.ctx));
            break;
        }
        const float *p = C.st.position;
        r.maxz = std::max(r.maxz, p[2]);
        r.top_max = std::max(r.top_max, p[2] + h);
        if (!r.through && std::fabs(p[0] - pos[0]) < 96.0f && std::fabs(p[1] - pos[1]) < 96.0f && p[2] > ceil_z + 1.0f) {
            r.through = true;
        }
        if (trace) {
            std::printf("      f %3d feet (%8.1f %8.1f %8.1f) top %8.1f %s mode %2d act %3d A %u\n", f, p[0], p[1], p[2], p[2] + h,
                        C.ground() ? "G" : "-", (int)C.st.mode, (int)C.st.action, btn ? 1u : 0u);
        }
    }
    std::memcpy(r.end, C.st.position, sizeof r.end);
    r.end_ground = C.ground();
    r.ontop = r.end_ground && r.end[2] > ceil_z - 1.0f;
    r.bonk = !r.through && r.top_max >= ceil_z - 4.0f;
    C.destroy();
    return r;
}

static const char *jump_word(const JumpResult &r)
{
    if (!r.ok) {
        return "ERR";
    }
    if (r.fault) {
        return "FAULT";
    }
    if (r.through) {
        return r.ontop ? "THROUGH(on top)" : "THROUGH";
    }
    return r.bonk ? "blocked" : "short";
}

static std::string g_jkinds = "023567";   // --jkinds: the kinds of --ceiljump

// --ceiljump "x y z ceil_z": the faces on the vertical line, then every kind jumps (and jumps twice)
static void ceil_spot(Lib &L, const Soup &s, const std::string &spec, bool trace)
{
    float q[4];
    if (std::sscanf(spec.c_str(), "%f %f %f %f", &q[0], &q[1], &q[2], &q[3]) != 4) {
        std::printf("  --ceiljump needs \"x y z ceil_z\"\n");
        return;
    }
    std::vector<Hit> col;
    s.column(q[0], q[1], col);
    std::printf("  faces on the vertical line through (%.0f %.0f), %.0f..%.0f:\n", q[0], q[1], q[2] - 16.0f, q[3] + 200.0f);
    for (const Hit &h : col) {
        if (h.z < q[2] - 16.0f || h.z > q[3] + 200.0f) {
            continue;
        }
        const sa1_collision_tri &t = s.t[h.tri];
        std::printf("    z %9.2f %s tri %6u n (%5.2f %5.2f %5.2f) surface %X%s%s%s\n", h.z, h.dir > 0 ? "up  " : h.dir < 0 ? "down" : "vert",
                    h.tri, s.n[3 * h.tri], s.n[3 * h.tri + 1], s.n[3 * h.tri + 2], t.surface,
                    (t.surface & SA1_SURFACE_DOUBLE_SIDED) ? " double-sided" : "",
#ifdef SA1_API_CEILING
                    (t.surface & SA1_SURFACE_FRONT_ONLY) ? " FRONT-ONLY" : "", (t.surface & SA1_SURFACE_CURVED) ? " curved" : "");
#else
                    "", "");
#endif
    }
    std::printf("  jumps at (%.1f %.1f %.1f) under the ceiling plane z %.1f (%.0f units of room):\n", q[0], q[1], q[2], q[3],
                q[3] - q[2]);
    int through = 0, n = 0;
    for (char ch : g_jkinds) {
        int kind = ch - '0';
        for (int ap : {0, 2}) {
            JumpResult r = jump_test(L, q, kind, ap, q[3], trace && n == 0);
            n++;
            through += r.through;
            std::printf("    %-8s %-10s %-16s feet up to %8.1f, top up to %8.1f; end (%.1f %.1f %.1f) %s\n", kind_name(kind),
                        ap == 0 ? "jump" : "jump twice", jump_word(r), r.maxz, r.top_max, r.end[0], r.end[1], r.end[2],
                        r.end_ground ? "on the ground" : "in the air");
        }
    }
    std::printf("  ceiling at (%.0f %.0f): %d of %d jumps went through\n", q[0], q[1], through, n);
}

// --ceilgrid "x0 y0 x1 y1 step z ceil_z": Sonic and Tails jump at every point of a grid
static void ceil_grid(Lib &L, const std::string &spec)
{
    float x0, y0, x1, y1, st, z, cz;
    if (std::sscanf(spec.c_str(), "%f %f %f %f %f %f %f", &x0, &y0, &x1, &y1, &st, &z, &cz) != 7 || !(st > 0.0f)) {
        std::printf("  --ceilgrid needs \"x0 y0 x1 y1 step z ceil_z\"\n");
        return;
    }
    int n = 0, ts = 0, tt = 0;
    for (float x = x0; x <= x1 + 0.01f; x += st) {
        for (float y = y0; y <= y1 + 0.01f; y += st) {
            float p[3] = {x, y, z};
            JumpResult a = jump_test(L, p, SA1_CHAR_SONIC, 0, cz, false);
            JumpResult b = jump_test(L, p, SA1_CHAR_TAILS, 0, cz, false);
            n++;
            ts += a.through;
            tt += b.through;
            if (g_verbose || a.through || b.through) {
                std::printf("    (%6.0f %6.0f): Sonic %-16s Tails %-16s\n", x, y, jump_word(a), jump_word(b));
            }
        }
    }
    std::printf("  ceiling grid: %d spots; through the ceiling: Sonic %d, Tails %d\n", n, ts, tt);
}

// a loop: centre (y = its axis), inner radius R, thickness T (Hammer units)
struct LoopSpec {
    bool have = false;
    double cx = 0, cy = 0, cz = 0, R = 0, T = 0;
};
struct LoopRun {
    bool ok = false, entered = false, outside_top = false, fin_ground = false;
    double entry_speed = 0, phi_max = -1e9, phi_detach = -1;
    float fin[3] = {0, 0, 0};
    std::string verdict;
};
static bool g_loop_spin = false;   // --loopspin: a spin dash (charged 1 s) instead of running
// one run toward the loop: the stick held forward (camera fixed at the start's yaw), the ground speed set to `speed`
// every frame on the ground until 0.6 R before the loop's centre (a dash panel; 0: the character's own speed);
// "progress" = the angle around the loop's axis while on the ground within 24 units of the inner radius (loop_diag)
static LoopRun loop_run(Lib &L, const LoopSpec &P, int kind, const float start[3], float yaw_deg, float speed, int frames,
                        double complete, bool print)
{
    LoopRun res;
    Chr C;
    std::string e;
    const float yaw = yaw_deg * kDeg;
    if (!C.create(L.ctx, kind, start, yaw, nullptr, e)) {
        std::printf("    create: %s\n", e.c_str());
        return res;
    }
    res.ok = true;
    const double sgn = std::cos(yaw) >= 0 ? 1.0 : -1.0;   // the loop lies across x (its axis along y)
    double phi_prev = 0, phi_un = 0;
    bool have_phi = false, detached = false;
    int entered_frame = -1;
    for (int f = 0; f < frames; f++) {
        float t = f / 60.0f, sy = 1.0f;
        uint32_t btn = 0;
        if (t < 0.4f) {
            sy = 0.0f;
        } else if (g_loop_spin && t < 1.4f) {
            sy = 0.0f;
            btn = SA1_BUTTON_ACTION;
        }
        std::snprintf(g_what, sizeof g_what, "loop run %s speed %.1f frame %d", kind_name(kind), speed, f);
        sa1_status st = C.tick(0.0f, sy, yaw, btn, 1.0f / 60.0f);
        if (SA1_FAILED(st)) {
            std::printf("    tick: %s: %s\n", sa1_status_string(st), sa1_last_error(L.ctx));
            break;
        }
        const float *p = C.st.position;
        double dx = p[0] - P.cx, dz = p[2] - P.cz, r = std::sqrt(dx * dx + dz * dz);
        if (speed > 0.0f && C.ground() && -(dx * sgn) > 0.6 * P.R && !res.entered) {
            C.set_ground_speed(speed);
        }
        if (C.pairs == 0) {
            continue;
        }
        double phi = std::atan2(dx * sgn, -dz) / kDeg;
        if (!have_phi) {
            phi_un = phi;
            have_phi = true;
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
        bool on_loop = C.ground() && std::fabs(r - P.R) < 24.0 && std::fabs(p[1] - P.cy) < 600.0;
        if (!res.entered && on_loop && std::fabs(dx) < 0.25 * P.R) {
            res.entered = true;
            entered_frame = f;
            res.entry_speed = C.speed();
            phi_un = phi;
        }
        if (res.entered && on_loop) {
            res.phi_max = std::max(res.phi_max, phi_un);
        }
        if (res.entered && !detached && !on_loop && res.phi_max > 20.0) {
            detached = true;
            res.phi_detach = phi_un;
        }
        if (dz > 0 && r > P.R + P.T - 6.0 && std::fabs(dx) < P.R + P.T) {
            res.outside_top = true;
        }
        if (print) {
            std::printf("    f %4d pos (%8.1f %8.1f %8.1f) r %6.1f phi %6.1f %s v %5.2f mode %2d act %3d%s\n", f, p[0], p[1], p[2], r,
                        phi_un, C.ground() ? "G" : "-", C.speed(), (int)C.st.mode, (int)C.st.action, on_loop ? "" : "  (off)");
        }
        if (res.entered && f > entered_frame + 600) {
            break;
        }
    }
    std::memcpy(res.fin, C.st.position, sizeof res.fin);
    res.fin_ground = C.ground();
    double dx = res.fin[0] - P.cx, dz = res.fin[2] - P.cz, r = std::sqrt(dx * dx + dz * dz);
    bool fin_top = dz > 0 && r > P.R + P.T - 6.0 && std::fabs(dx) < P.R + P.T;
    if (!res.entered) {
        res.verdict = "never reached the loop";
    } else if (res.phi_max >= complete) {
        res.verdict = "COMPLETED";
    } else if (fin_top || res.outside_top) {
        res.verdict = "ON TOP";
    } else if (res.phi_max >= 180.0) {
        res.verdict = "over the top, then off";
    } else {
        res.verdict = "fell off the wall / ceiling";
    }
    C.destroy();
    return res;
}

// the loop's sweep: every kind of --loopkinds at every speed of --speeds; then (--looptop) landings and runs on the
// loop's outer top (mechanism B with the loop's ceiling kept: nothing may fall into the loop)
static void loop_tests(Lib &L, const LoopSpec &P, const std::string &runspec, const std::string &speeds,
                       const std::string &kinds, bool top, bool trace)
{
    float start[3] = {0, 0, 0}, yaw = 180.0f, frames = 900.0f;
    if (std::sscanf(runspec.c_str(), "%f %f %f %f %f", &start[0], &start[1], &start[2], &yaw, &frames) < 4) {
        std::printf("  --looprun needs \"x y z yaw [frames]\"\n");
        return;
    }
    const double complete = 330.0;
    std::printf("  loop: centre (%.0f %.0f %.0f), inner radius %.0f, thickness %.0f; runs from (%.0f %.0f %.0f) yaw %.0f%s\n",
                P.cx, P.cy, P.cz, P.R, P.T, start[0], start[1], start[2], yaw, g_loop_spin ? ", spin dash" : "");
    int done = 0, ontop = 0, n = 0;
    for (char ch : kinds) {
        int kind = ch - '0';
        std::printf("    %-8s", kind_name(kind));
        size_t a = 0;
        while (a <= speeds.size()) {
            size_t b = speeds.find(',', a);
            if (b == std::string::npos) {
                b = speeds.size();
            }
            if (b > a) {
                float v = (float)std::atof(speeds.substr(a, b - a).c_str());
                LoopRun r = loop_run(L, P, kind, start, yaw, v, (int)frames, complete, trace && n == 0);
                n++;
                done += r.verdict == "COMPLETED";
                ontop += r.verdict == "ON TOP";
                std::printf(" %.0f:%s(%.0f deg, entry %.1f)", v, r.verdict == "COMPLETED" ? "COMPLETED" : r.verdict == "ON TOP" ?
                            "ON-TOP" : r.verdict.c_str(), r.phi_max < -1e8 ? 0.0 : r.phi_max, r.entry_speed);
                std::fflush(stdout);
            }
            a = b + 1;
        }
        std::printf("\n");
    }
    std::printf("  loop runs: %d, completed %d, ended on top of the loop %d\n", n, done, ontop);
    if (!top) {
        return;
    }
    int falls = 0, runs = 0;
    for (int kind : {SA1_CHAR_SONIC, SA1_CHAR_KNUCKLES}) {
        for (float speed : {0.0f, 4.0f, 8.0f, 12.0f, 16.0f}) {
            for (float off : {-200.0f, -100.0f, 0.0f, 100.0f, 200.0f}) {
                for (int dir = -1; dir <= 1; dir += 2) {
                    for (float drop : {0.0f, 200.0f}) {
                        double x = P.cx + off, dz = std::sqrt(std::max(0.0, (P.R + P.T) * (P.R + P.T) - off * off));
                        float st0[3] = {(float)x, (float)P.cy, (float)(P.cz + dz + 6.0 + drop)};
                        Chr C;
                        std::string e;
                        float y0 = dir > 0 ? 0.0f : 3.14159265f;
                        if (!C.create(L.ctx, kind, st0, y0, nullptr, e)) {
                            continue;
                        }
                        runs++;
                        bool inside = false;
                        for (int f = 0; f < 150; f++) {
                            if (speed > 0 && C.ground() && f < 20) {
                                C.set_ground_speed(speed);
                            }
                            C.tick(0.0f, f > 5 ? 1.0f : 0.0f, y0, 0, 1.0f / 60.0f);
                            const float *p = C.st.position;
                            double rx = p[0] - P.cx, rz = p[2] - P.cz;
                            inside |= std::sqrt(rx * rx + rz * rz) < P.R - 2.0 && rz > 0;
                        }
                        if (inside) {
                            falls++;
                            std::printf("    FELL INTO THE LOOP: %s speed %.0f, x offset %.0f, dir %d, drop %.0f\n", kind_name(kind),
                                        speed, off, dir, drop);
                        }
                        C.destroy();
                    }
                }
            }
        }
    }
    std::printf("  on top of the loop: %d of %d runs / landings fell through the top into the loop\n", falls, runs);
}

// --gmas: every workshop GMA mounted (the props' physics models of workshop maps; sadc build/research ceil_diag)
static bool g_gmas = false;
static void mount_dir(gamefs::GameFs *fs, const std::string &dir, int depth, int &n)
{
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA((dir + "\\*").c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE) {
        return;
    }
    do {
        std::string nm = fd.cFileName;
        if (nm == "." || nm == "..") {
            continue;
        }
        std::string p = dir + "\\" + nm;
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            if (depth > 0) {
                mount_dir(fs, p, depth - 1, n);
            }
        } else if (nm.size() > 4 && gamefs::lower(nm.substr(nm.size() - 4)) == ".gma") {
            n += fs->add_gma(p) ? 1 : 0;
        }
    } while (FindNextFileA(h, &fd));
    FindClose(h);
}

// ---- one map ----------------------------------------------------------------------------------------------------------
struct Options {
    std::string gdi;
    int ramps = 25, random = 30;
    float secs = 8.0f;
    bool cost = true;
    std::vector<int> kinds{SA1_CHAR_SONIC, SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA, SA1_CHAR_BIG};
    std::string trace;      // "x y z yaw approach kind [runup]"
    std::string dump;       // "x y z r": print the triangles within r of the point
    // emulated fixes (what the host / libsa1 could do differently)
    bool no_hidden = false;     // build_world without the hidden-face removal (and stair ramps)
    float max_edge = 0.0f;      // GRID max_edge (SA1 units) through sa1_collision_set_static_ex; 0 = set_static
    float cell = 0.0f;          // GRID cell size (SA1 units) with max_edge / cut
    bool cut = false;           // SA1_GRID_CUT
    float drop_sliver = 0.0f;   // drop land triangles narrower than this (smallest altitude, Hammer units)
    float drop_under = 0.0f;    // drop down-facing faces with an up-facing land face at most this far above them
    float thin = -1.0f;         // BspWorldOptions::thin_floor_min (Hammer units; < 0: the default)
    float thin_wall = -1.0f;    // BspWorldOptions::thin_wall_max (Hammer units; < 0: the default, 0: off)
    float tess = 0.0f;          // pre-tessellate: cut every triangle across its longest edge into pieces of at most this
                                // size (Hammer units), well shaped (no needles); 0 = off
    bool legacy = false;        // 0.4's conversion (no map job: no one-way platforms, thickened floors, no props)
    bool props = true;          // the map job's static props
    bool dc_limits = false;     // SA1_GRID_DC_LIMITS: the game's own 96-entry NEAR-poly list
    bool set_static = false;    // sa1_collision_set_static instead of the job's prepared world (0.5.1)
    std::string gm = gsa1_garrysmod_dir();   // the model files (gamefs.hpp; tests/gmod_paths.hpp)
    // 0.9.3 (gsa1_091b_ceiling.md, gsa1_091a_loop.md)
    bool undersides_drop = false;   // --undersides-drop: PrepareOptions::undersides_drop ("Solid ceilings" off)
    bool no_front_only = false;     // --no-front-only: BspWorldOptions::one_way_front_only = false (0.9.2's one-way)
    bool no_curved = false;         // --no-curved: BspWorldOptions::curved = false (no curved-surface detector)
    bool old_disp_brushes = false;  // --old-disp-brushes: BspWorldOptions::disp_brush_exact = false (0.9.2's rule)
    float disp_cover_max = -1.0f;   // --disp-cover-max HU: BspWorldOptions::disp_cover_max (0 = off, 0.9.2)
    std::string ceiljump;           // --ceiljump "x y z ceil_z"
    std::string ceilgrid;           // --ceilgrid "x0 y0 x1 y1 step z ceil_z"
    LoopSpec loop;                  // --loop "cx cy cz R T"
    std::string looprun;            // --looprun "x y z yaw [frames]"
    std::string speeds = "6,8,10,12,16";   // --speeds
    std::string loopkinds = "0";    // --loopkinds
    bool looptop = false;           // --looptop
    bool jtrace = false;            // --jtrace: frame by frame (the first ceiling jump / loop run)
    bool curved_report = false;     // --curved-report: the curved triangles (and front-only ones, --verbose) by cell
    std::string save_tris;          // --save-tris FILE: the world's triangles (raw sa1_collision_tri) for comparisons
};

// cut a convex polygon (3D) by the plane d . x = t into the part below and above
static void split_poly(const std::vector<std::array<float, 3>> &in, const float d[3], float t,
                       std::vector<std::array<float, 3>> &lo, std::vector<std::array<float, 3>> &hi)
{
    lo.clear();
    hi.clear();
    size_t n = in.size();
    for (size_t i = 0; i < n; i++) {
        const auto &a = in[i], &b = in[(i + 1) % n];
        float da = d[0] * a[0] + d[1] * a[1] + d[2] * a[2] - t, db = d[0] * b[0] + d[1] * b[1] + d[2] * b[2] - t;
        if (da <= 0.0f) {
            lo.push_back(a);
        }
        if (da >= 0.0f) {
            hi.push_back(a);
        }
        if ((da < 0.0f && db > 0.0f) || (da > 0.0f && db < 0.0f)) {
            float u = da / (da - db);
            std::array<float, 3> m = {a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u};
            lo.push_back(m);
            hi.push_back(m);
        }
    }
}

// a triangle cut into pieces no longer than `e` along its longest edge's direction and across it (strips, then cells),
// each piece fan-triangulated: well-shaped triangles instead of the needles that halving the longest edge makes
static void tess_tri(const sa1_collision_tri &q, float e, std::vector<sa1_collision_tri> &out)
{
    float l[3];
    for (int k = 0; k < 3; k++) {
        const float *a = q.v[k], *b = q.v[(k + 1) % 3];
        l[k] = std::sqrt((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1]) + (b[2] - a[2]) * (b[2] - a[2]));
    }
    int k = l[0] >= l[1] ? (l[0] >= l[2] ? 0 : 2) : (l[1] >= l[2] ? 1 : 2);
    if (l[k] <= e) {
        out.push_back(q);
        return;
    }
    float d1[3], d2[3], nn[3];
    for (int a = 0; a < 3; a++) {
        d1[a] = (q.v[(k + 1) % 3][a] - q.v[k][a]) / l[k];
    }
    {
        float e1[3], e2[3];
        for (int a = 0; a < 3; a++) {
            e1[a] = q.v[1][a] - q.v[0][a];
            e2[a] = q.v[2][a] - q.v[0][a];
        }
        nn[0] = e1[1] * e2[2] - e1[2] * e2[1];
        nn[1] = e1[2] * e2[0] - e1[0] * e2[2];
        nn[2] = e1[0] * e2[1] - e1[1] * e2[0];
        float m = std::sqrt(nn[0] * nn[0] + nn[1] * nn[1] + nn[2] * nn[2]);
        if (!(m > 0.0f)) {
            out.push_back(q);
            return;
        }
        for (int a = 0; a < 3; a++) {
            nn[a] /= m;
        }
    }
    d2[0] = nn[1] * d1[2] - nn[2] * d1[1];   // in the plane, across d1
    d2[1] = nn[2] * d1[0] - nn[0] * d1[2];
    d2[2] = nn[0] * d1[1] - nn[1] * d1[0];
    std::vector<std::array<float, 3>> poly = {{q.v[0][0], q.v[0][1], q.v[0][2]}, {q.v[1][0], q.v[1][1], q.v[1][2]},
                                              {q.v[2][0], q.v[2][1], q.v[2][2]}}, lo, hi, rest, a2, b2;
    auto range = [](const std::vector<std::array<float, 3>> &p, const float d[3], float &mn, float &mx) {
        mn = 1e30f;
        mx = -1e30f;
        for (const auto &v : p) {
            float t = d[0] * v[0] + d[1] * v[1] + d[2] * v[2];
            mn = std::min(mn, t);
            mx = std::max(mx, t);
        }
    };
    float mn1, mx1;
    range(poly, d1, mn1, mx1);
    int n1 = (int)std::ceil((mx1 - mn1) / e);
    rest = poly;
    for (int i = 1; i <= n1; i++) {
        std::vector<std::array<float, 3>> strip;
        if (i < n1) {
            split_poly(rest, d1, mn1 + (mx1 - mn1) * i / n1, lo, hi);
            strip = lo;
            rest = hi;
        } else {
            strip = rest;
        }
        if (strip.size() < 3) {
            continue;
        }
        float mn2, mx2;
        range(strip, d2, mn2, mx2);
        int n2 = std::max(1, (int)std::ceil((mx2 - mn2) / e));
        std::vector<std::array<float, 3>> r2 = strip;
        for (int j = 1; j <= n2; j++) {
            std::vector<std::array<float, 3>> cell;
            if (j < n2) {
                split_poly(r2, d2, mn2 + (mx2 - mn2) * j / n2, a2, b2);
                cell = a2;
                r2 = b2;
            } else {
                cell = r2;
            }
            for (size_t m = 1; m + 1 < cell.size(); m++) {
                sa1_collision_tri t;
                t.surface = q.surface;
                const std::array<float, 3> *c3[3] = {&cell[0], &cell[m], &cell[m + 1]};
                for (int v = 0; v < 3; v++) {
                    for (int a = 0; a < 3; a++) {
                        t.v[v][a] = (*c3[v])[a];
                    }
                }
                if (tri_area(t) > 1e-3f) {
                    out.push_back(t);
                }
            }
        }
    }
}

// the smallest altitude of a triangle (its width)
static float tri_width(const sa1_collision_tri &q)
{
    float l2max = 0.0f;
    for (int e = 0; e < 3; e++) {
        float d2 = 0.0f;
        for (int k = 0; k < 3; k++) {
            float d = q.v[(e + 1) % 3][k] - q.v[e][k];
            d2 += d * d;
        }
        l2max = std::max(l2max, d2);
    }
    float a2 = 0.0f;
    {
        float e1[3], e2[3];
        for (int k = 0; k < 3; k++) {
            e1[k] = q.v[1][k] - q.v[0][k];
            e2[k] = q.v[2][k] - q.v[0][k];
        }
        float c[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
        a2 = std::sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2]);   // twice the area
    }
    return l2max > 0.0f ? a2 / std::sqrt(l2max) : 0.0f;
}

static void apply_fixes(const Options &O, std::vector<sa1_collision_tri> &tris, uint32_t &dropped_slivers,
                        uint32_t &dropped_under)
{
    dropped_slivers = dropped_under = 0;
    if (O.drop_sliver > 0.0f) {
        std::vector<sa1_collision_tri> out;
        for (const sa1_collision_tri &q : tris) {
            if (!(q.surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER)) && tri_width(q) < O.drop_sliver) {
                dropped_slivers++;
                continue;
            }
            out.push_back(q);
        }
        tris.swap(out);
    }
    if (O.tess > 0.0f) {
        std::vector<sa1_collision_tri> out;
        for (const sa1_collision_tri &q : tris) {
            if (q.surface & SA1_SURFACE_KILL) {
                out.push_back(q);
            } else {
                tess_tri(q, O.tess, out);
            }
        }
        tris.swap(out);
    }
    if (O.drop_under > 0.0f) {
        Soup s;
        s.build(tris);
        std::vector<sa1_collision_tri> out;
        std::vector<Hit> col;
        for (uint32_t i = 0; i < tris.size(); i++) {
            const sa1_collision_tri &q = tris[i];
            if (s.n[3 * i + 2] < -0.5f && !(q.surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER))) {
                float c[3];
                for (int k = 0; k < 3; k++) {
                    c[k] = (q.v[0][k] + q.v[1][k] + q.v[2][k]) / 3.0f;
                }
                s.column(c[0], c[1], col);
                bool cover = false;
                for (const Hit &h : col) {
                    cover = cover || (h.dir > 0 && h.z > c[2] && h.z <= c[2] + O.drop_under);
                }
                if (cover) {
                    dropped_under++;
                    continue;
                }
            }
            out.push_back(q);
        }
        tris.swap(out);
    }
}

// sa1_collision_set_static, or set_static_ex with GRID parameters (one group per surface word)
static sa1_status set_world(Lib &L, const Options &O, const std::vector<sa1_collision_tri> &tris)
{
    if (!(O.max_edge > 0.0f) && !(O.cell > 0.0f) && !O.cut && !O.dc_limits && !O.undersides_drop) {
        return sa1_collision_set_static(L.ctx, tris.data(), (uint32_t)tris.size());
    }
    std::map<uint32_t, std::vector<uint32_t>> by;
    for (uint32_t i = 0; i < tris.size(); i++) {
        by[tris[i].surface].push_back(i);
    }
    std::vector<float> pts;
    std::vector<uint32_t> idx;
    std::vector<sa1_collision_group> groups;
    for (auto &kv : by) {
        sa1_collision_group g;
        std::memset(&g, 0, sizeof g);
        g.struct_size = sizeof g;
        g.surface = kv.first;
        g.first_point = (uint32_t)(pts.size() / 3);
        g.first_tri = (uint32_t)(idx.size() / 3);
        uint32_t k = 0;
        for (uint32_t i : kv.second) {
            for (int v = 0; v < 3; v++) {
                for (int a = 0; a < 3; a++) {
                    pts.push_back(tris[i].v[v][a]);
                }
                idx.push_back(k++);
            }
        }
        g.num_points = k;
        g.num_tris = (uint32_t)kv.second.size();
        groups.push_back(g);
    }
    sa1_collision_grid gp;
    std::memset(&gp, 0, sizeof gp);
    gp.struct_size = sizeof gp;
    gp.flags = (O.cut ? SA1_GRID_CUT : 0u) | (O.dc_limits ? SA1_GRID_DC_LIMITS : 0u);
#ifdef SA1_API_CEILING
    gp.flags |= O.undersides_drop ? SA1_GRID_UNDERSIDES_DROP : 0u;
#endif
    gp.cell_size = O.cell;
    gp.max_edge = O.max_edge;
    sa1_collision_static d;
    std::memset(&d, 0, sizeof d);
    d.struct_size = sizeof d;
    d.mode = SA1_COLLISION_MODE_GRID;
    d.points = pts.data();
    d.num_points = (uint32_t)(pts.size() / 3);
    d.indices = idx.data();
    d.num_tris = (uint32_t)(idx.size() / 3);
    d.groups = groups.data();
    d.num_groups = (uint32_t)groups.size();
    d.grid = &gp;
    return sa1_collision_set_static_ex(L.ctx, &d);
}

static void do_map(Lib &L, const std::string &path, const Options &O)
{
    std::printf("\n=== %s\n", base_name(path).c_str());
    std::fflush(stdout);
    std::string e;
    FileByteSource src;
    Bsp bsp;
    double t0 = now_ms();
    if (!src.open(path, e) || !bsp.open(src, e)) {
        std::printf("  cannot open: %s\n", e.c_str());
        return;
    }
    double t_open = now_ms() - t0;
    BspWorldOptions opt;
    if (O.legacy) {
        opt.one_way_max = 0.0f;
        opt.disp_side_flip = true;
        opt.thin_wall_max = 0.0f;
    }
    if (O.thin_wall >= 0.0f) {
        opt.thin_wall_max = O.thin_wall;
    }
    if (O.no_hidden) {
        opt.remove_hidden = false;
        opt.stair_ramps = false;
    }
    if (O.thin >= 0.0f) {
        opt.thin_floor_min = O.thin;
    }
#ifndef DIAG_CORE092   // (build_diag_maps.py --core092: the 0.9.2 core, for comparisons)
    opt.one_way_front_only = !O.no_front_only;
    opt.curved = !O.no_curved;
    opt.disp_brush_exact = !O.old_disp_brushes;
    if (O.disp_cover_max >= 0.0f) {
        opt.disp_cover_max = O.disp_cover_max;
    }
#endif
    std::vector<sa1_collision_tri> tris;
    BspWorldStats st;
    // the variants that change the triangles after the job or the GRID parameters: set_static, not the prepared world
    bool post = O.drop_sliver > 0.0f || O.drop_under > 0.0f || O.tess > 0.0f || O.max_edge > 0.0f || O.cell > 0.0f ||
                O.cut || O.dc_limits;
    PrepareResult prep;
    std::snprintf(g_what, sizeof g_what, "%s: %s", base_name(path).c_str(), O.legacy ? "Bsp::build_world" : "the map job");
    g_tick_t0 = GetTickCount64();
    g_in_tick = 1;
    bool ok;
    if (O.legacy) {
        ok = bsp.build_world(opt, tris, st, e);
    } else {
        static gamefs::GameFs *fs = nullptr;
        if (!fs) {
            fs = new gamefs::GameFs(O.gm);
            if (g_gmas) {
                int n = 0;
                mount_dir(fs, join_path(join_path(O.gm, "cache"), "workshop"), 0, n);
                char steamws[1100];   // <Steam library>\steamapps\workshop\content\4000, next to Garry's Mod
                if (gsa1_garrysmod_rel(steamws, sizeof steamws, 3, "workshop\\content\\4000"))
                    mount_dir(fs, steamws, 1, n);
                std::printf("  file system: %d workshop GMAs mounted\n", n);
            }
        }
        fs->set_map(path);
        MapJobOptions mo;
        mo.world = opt;
        mo.static_props = O.props;
        mo.prepare = !O.set_static && !post;
#ifndef DIAG_CORE092
        mo.grid.undersides_drop = O.undersides_drop;
#endif
        MapJob job;
        MapResult res;
        MapDrive drv;
        std::string mapname = base_name(path);
        if (mapname.size() > 4) {
            mapname.resize(mapname.size() - 4);
        }
        ok = job.start_file(mapname, path, mo, e) && run_map_job(job, fs, nullptr, e, &drv) && job.take(res);
        if (ok) {
            tris.swap(res.world);
            st = res.st.world;
            prep = std::move(res.prep);
            if (mo.prepare) {
                std::printf("  prepared on the job's worker: %s in %.0f ms (%u triangles -> %u GRID triangles in %u objects, "
                            "%u undersides within reach left out)%s%s\n", prep.ok ? "ok" : "FAILED", prep.ms, prep.triangles,
                            prep.grid_triangles, prep.grid_objects, prep.grid_undersides, prep.ok ? "" : ": ",
                            prep.error.c_str());
            }
            std::printf("  map job: %.0f ms; static props %u (%u solid): %u placed (%u physics pieces -> %u triangles), %u "
                        "without a physics model, %u small; %u model files (%u found); %u brush entity models\n",
                        res.st.total_ms, res.st.props, res.st.props_solid, res.st.props_placed, res.st.props_hulls,
                        st.tris_extra, res.st.props_missing, res.st.props_small, drv.files, drv.files_found,
                        res.st.brush_models);
            std::printf("  cleaning: %u one-way solids (%u undersides, %u more pieces, %u displacement triangles left out), "
                        "%u low ceilings left out, %u thin walls (%u faces made double-sided mid faces), %u thickened; "
                        "displacements %u (%u on back faces, %u decided by tags, %u reversed by them, %u triangles buried)\n",
                        st.one_way_solids,
                        st.one_way_faces, st.one_way_cross, st.one_way_disp_tris, st.low_ceilings, st.thin_walls,
                        st.thin_wall_faces, st.thickened_floors, st.displacements, st.disp_back_faces, st.disp_tag_checked,
                        st.disp_tag_reversed, st.disp_buried);
            // 0.9.2 (bsp.hpp: GRID-TW1, thin stacks, the guard, no-hull displacements, coplanar down faces; GRID-FALLBACK)
            std::printf("  0.9.2: %u thin-wall pairs kept as two faces; thin stacks: %u faces made double-sided, %u left out; "
                        "guard: %u triangles outside the bounds + 64, %u pieces outside their solid's box, %u static props "
                        "outside the world; %u displacements without hull collision left out; %u down pieces cut by a "
                        "coplanar walkable face%s%s\n", st.thin_wall_kept, st.thin_stacks, st.thin_stack_faces,
                        st.tris_outside, st.frags_outside, res.st.props_outside, st.displacements_nohull, st.coplanar_cut,
                        prep.retried ? "; prepared on the second try without the triangles outside the map" : "",
                        prep.too_big ? "; TOO BIG for the game's collision" : "");
#ifndef DIAG_CORE092
            // 0.9.3 (front-only ceilings, curved surfaces)
            std::printf("  0.9.3: front-only ceilings %s: %u pieces kept front-only, %u left out with nothing under them (GRID: %u "
                        "front-only triangles%s); curved surfaces %s: %u surfaces, %u faces (%u turned down) in %u solids; left "
                        "alone by the one-way rules %u, thin walls %u, thin stacks %u; %u thin curved ribbons made one face; GRID "
                        "kept %u curved undersides\n",
                        opt.one_way_front_only ? "on" : "off", st.one_way_front_only, st.front_only_no_room, prep.grid_front_only,
                        O.undersides_drop ? ", undersides_drop" : "", opt.curved ? "on" : "off", st.curved_surfaces,
                        st.curved_faces, st.curved_undersides, st.curved_solids, st.curved_one_way, st.curved_thin_walls,
                        st.curved_thin_stacks, st.curved_ribbons, prep.grid_curved);
            // 0.9.3 tunnels (the brushes beside a displacement kept, the up faces under displacement ground left out)
            std::printf("  0.9.3 tunnels: %u brushes beside displacements kept (disp_brush_exact %s), %u dropped; %u up faces "
                        "cut under displacement ground (disp_cover_max %.0f: %u pieces, %.0f square units)\n",
                        st.disp_brushes_kept, opt.disp_brush_exact ? "on" : "off", st.displacement_brushes, st.disp_cover_faces,
                        opt.disp_cover_max, st.disp_cover_pieces, st.disp_cover_area);
#endif
        }
    }
    g_in_tick = 0;
    if (!ok) {
        std::printf("  build: %s (%.0f ms)\n", e.c_str(), now_ms() - t0);
        return;
    }
    std::printf("  load: BSP v%d, open %.0f ms, build_world %.0f ms: %u brushes (%u world, %u solid, %u water), %u brush faces "
                "(%u hidden, %u clipped -> %u pieces), %u thin floors thickened, %u stairs (%u steps), %u displacements "
                "(%u triangles), %u triangles (%u water, %u kill, %u out of range); bounds (%.0f %.0f %.0f) .. (%.0f %.0f "
                "%.0f)\n", st.version, t_open, st.ms, st.brushes, st.world_brushes, st.solid_brushes, st.water_brushes,
                st.brush_faces, st.hidden_faces, st.clipped_faces, st.face_fragments, st.thickened_floors, st.stairs,
                st.stair_steps, st.displacements, st.displacement_tris, st.tris, st.tris_water, st.tris_kill,
                st.tris_out_of_range, st.mins[0], st.mins[1], st.mins[2], st.maxs[0], st.maxs[1], st.maxs[2]);
    if (O.cost) {
        BspWorldOptions raw;
        raw.remove_hidden = false;
        raw.stair_ramps = false;
        std::vector<sa1_collision_tri> t2;
        BspWorldStats s2;
        if (bsp.build_world(raw, t2, s2, e)) {
            std::printf("        without hidden-face removal / stair ramps: %.0f ms, %u triangles (the removal costs %.0f ms)\n",
                        s2.ms, s2.tris, st.ms - s2.ms);
        }
    }
    std::fflush(stdout);
    // libsa1
    {
        uint32_t ds = 0, du = 0;
        Soup s0;
        apply_fixes(O, tris, ds, du);
        if (ds || du || O.no_hidden || O.max_edge > 0.0f || O.cell > 0.0f || O.cut || O.thin >= 0.0f || O.tess > 0.0f) {
            std::printf("  variant:%s%s thin_floor_min %.0f, max_edge %.0f, cell %.0f, tess %.0f HU%s; %u slivers (< %.1f HU wide) and %u undersides (an up-facing "
                        "face within %.0f HU above) dropped: %zu triangles\n", O.no_hidden ? " no hidden-face removal," : "",
                        O.cut ? " CUT," : "", O.thin >= 0.0f ? O.thin : BspWorldOptions().thin_floor_min, O.max_edge, O.cell, O.tess, "", ds, O.drop_sliver, du, O.drop_under, tris.size());
        }
    }
    t0 = now_ms();
    bool use_prep = prep.ok && !post;
    sa1_status ss = use_prep ? sa1_collision_set_prepared(L.ctx, prep.prepared.get()) : set_world(L, O, tris);
    double t_set = now_ms() - t0;
    if (SA1_FAILED(ss)) {
        std::printf("  %s: %s: %s\n", use_prep ? "sa1_collision_set_prepared" : "sa1_collision_set_static",
                    sa1_status_string(ss), sa1_last_error(L.ctx));
        return;
    }
    if (!O.save_tris.empty()) {
        // the world's triangles as they are (sa1_collision_tri array): comparisons between builds (cmp)
        FILE *fo = std::fopen(O.save_tris.c_str(), "wb");
        if (fo) {
            std::fwrite(tris.data(), sizeof(sa1_collision_tri), tris.size(), fo);
            std::fclose(fo);
            std::printf("  saved %zu triangles to %s\n", tris.size(), O.save_tris.c_str());
        }
    }
    Soup s;
    s.build(tris);
    {
        std::vector<BspEntity> ents;
        if (bsp.entities(ents, e)) {
            for (const BspEntity &en : ents) {
                const std::string *cn = en.get("classname");
                if (!cn) {
                    continue;
                }
                if (*cn == "sky_camera" && en.get_vec3("origin", s.region.sky)) {
                    s.region.have_sky = true;
                }
                if (!s.region.have_start && (*cn == "info_player_start" || *cn == "info_player_deathmatch") &&
                    en.get_vec3("origin", s.region.start)) {
                    s.region.have_start = true;
                }
            }
        }
        std::printf("  region: player start %s(%.0f %.0f %.0f), sky_camera %s(%.0f %.0f %.0f)\n",
                    s.region.have_start ? "" : "none ", s.region.start[0], s.region.start[1], s.region.start[2],
                    s.region.have_sky ? "" : "none ", s.region.sky[0], s.region.sky[1], s.region.sky[2]);
    }
    float spawn[3] = {0, 0, 0};
    {
        float best = 0.0f;
        for (uint32_t i = 0; i < s.t.size(); i++) {
            if (s.n[3 * i + 2] > 0.99f && !(s.t[i].surface & (SA1_SURFACE_KILL | SA1_SURFACE_WATER)) &&
                s.region.inside(s.t[i].v[0][0], s.t[i].v[0][1], s.t[i].v[0][2])) {
                float a = tri_area(s.t[i]);
                if (a > best) {
                    best = a;
                    for (int k = 0; k < 3; k++) {
                        spawn[k] = (s.t[i].v[0][k] + s.t[i].v[1][k] + s.t[i].v[2][k]) / 3.0f;
                    }
                }
            }
        }
        spawn[2] += 16.0f;
    }
    double c1 = 0, c2 = 0;
    Chr C;
    std::snprintf(g_what, sizeof g_what, "%s: first character (GRID synthesis)", base_name(path).c_str());
    g_tick_t0 = GetTickCount64();
    g_in_tick = 1;
    ok = C.create(L.ctx, SA1_CHAR_SONIC, spawn, 0.0f, &c1, e);
    g_in_tick = 0;
    if (!ok) {
        std::printf("  %s\n", e.c_str());
        return;
    }
    C.destroy();
    C.create(L.ctx, SA1_CHAR_SONIC, spawn, 0.0f, &c2, e);
    C.destroy();
    sa1_collision_info info;
    std::memset(&info, 0, sizeof info);
    info.struct_size = sizeof info;
    sa1_collision_info_get(L.ctx, &info);
    std::printf("  libsa1: %s %.3f ms; first character %.1f ms (%s: %u triangles -> %u in %u objects, %u split, %u cut, "
                "%u dropped, %u undersides left out), the next %.1f ms\n", use_prep ? "set_prepared" : "set_static", t_set,
                c1, use_prep ? "the GRID prepared by the job's worker" : "with the GRID synthesis",
                (unsigned)info.collidable_triangles, (unsigned)info.grid_triangles, (unsigned)info.grid_objects,
                (unsigned)info.grid_split, (unsigned)info.grid_cut, (unsigned)info.grid_dropped,
                (unsigned)info.grid_undersides, c2);
    std::fflush(stdout);

    if (!O.dump.empty()) {
        float q[4] = {0, 0, 0, 64};
        if (std::sscanf(O.dump.c_str(), "%f %f %f %f", &q[0], &q[1], &q[2], &q[3]) >= 3) {
            for (uint32_t i = 0; i < s.t.size(); i++) {
                const sa1_collision_tri &t = s.t[i];
                float c[3];
                for (int k = 0; k < 3; k++) {
                    c[k] = (t.v[0][k] + t.v[1][k] + t.v[2][k]) / 3.0f - q[k];
                }
                bool hit_v = false;
                for (int v = 0; v < 3 && !hit_v; v++) {
                    float d = 0;
                    for (int k = 0; k < 3; k++) {
                        d += (t.v[v][k] - q[k]) * (t.v[v][k] - q[k]);
                    }
                    hit_v = d < q[3] * q[3];
                }
                {
                    float d = s.n[3 * i] * (q[0] - t.v[0][0]) + s.n[3 * i + 1] * (q[1] - t.v[0][1]) + s.n[3 * i + 2] * (q[2] - t.v[0][2]);
                    bool inbox = true;
                    for (int k = 0; k < 3; k++) {
                        float lo = std::min(t.v[0][k], std::min(t.v[1][k], t.v[2][k])) - q[3];
                        float hi = std::max(t.v[0][k], std::max(t.v[1][k], t.v[2][k])) + q[3];
                        inbox = inbox && q[k] >= lo && q[k] <= hi;
                    }
                    hit_v = hit_v || (std::fabs(d) < q[3] && inbox);
                }
                if (hit_v || c[0] * c[0] + c[1] * c[1] + c[2] * c[2] < q[3] * q[3]) {
                    std::printf("    tri %6u n (%5.2f %5.2f %5.2f) surf %4X (%8.1f %8.1f %7.1f) (%8.1f %8.1f %7.1f) (%8.1f %8.1f %7.1f)\n", i,
                                s.n[3 * i], s.n[3 * i + 1], s.n[3 * i + 2], t.surface, t.v[0][0], t.v[0][1], t.v[0][2],
                                t.v[1][0], t.v[1][1], t.v[1][2], t.v[2][0], t.v[2][1], t.v[2][2]);
                }
            }
        }
        return;
    }
#ifdef SA1_API_CEILING
    // 0.9.3: where the curved surfaces and the front-only ceilings are (512-unit cells, the triangles' centroids)
    if (O.curved_report) {
        std::map<std::array<int32_t, 3>, std::array<uint32_t, 3>> cells;   // curved, curved down, front-only
        for (uint32_t i = 0; i < s.t.size(); i++) {
            uint32_t sf = s.t[i].surface;
            if (!(sf & (SA1_SURFACE_CURVED | SA1_SURFACE_FRONT_ONLY))) {
                continue;
            }
            std::array<int32_t, 3> k;
            for (int c = 0; c < 3; c++) {
                k[c] = (int32_t)std::floor((s.t[i].v[0][c] + s.t[i].v[1][c] + s.t[i].v[2][c]) / 3.0f / 512.0f);
            }
            auto &e = cells[k];
            e[0] += (sf & SA1_SURFACE_CURVED) != 0;
            e[1] += (sf & SA1_SURFACE_CURVED) != 0 && s.n[3 * i + 2] < -0.1f;
            e[2] += (sf & SA1_SURFACE_FRONT_ONLY) != 0;
        }
        std::printf("  curved / front-only triangles by 512-unit cell (centre of the cell):\n");
        for (auto &kv : cells) {
            if (kv.second[0] == 0 && !g_verbose) {
                continue;   // front-only alone: only with --verbose
            }
            std::printf("    (%6d %6d %6d): %4u curved (%u turned down), %4u front-only\n", kv.first[0] * 512 + 256,
                        kv.first[1] * 512 + 256, kv.first[2] * 512 + 256, kv.second[0], kv.second[1], kv.second[2]);
        }
    }
#endif
    // 0.9.3: ceilings (jumps from the floor under them) and loops (runs at loop speed, landings on the loop's top)
    if (!O.ceiljump.empty()) {
        ceil_spot(L, s, O.ceiljump, O.jtrace);
    }
    if (!O.ceilgrid.empty()) {
        ceil_grid(L, O.ceilgrid);
    }
    if (O.loop.have && !O.looprun.empty()) {
        loop_tests(L, O.loop, O.looprun, O.speeds, O.loopkinds, O.looptop, O.jtrace);
    }
    std::fflush(stdout);
    // a trace of one run
    if (!O.trace.empty()) {
        Ramp R;
        float yaw = 0;
        char ap[32] = "top";
        int kind = 0;
        std::memset(&R, 0, sizeof R);
        float runup = 2400.0f;
        if (std::sscanf(O.trace.c_str(), "%f %f %f %f %31s %d %f", &R.foot[0], &R.foot[1], &R.foot[2], &yaw, ap, &kind,
                        &runup) >= 4) {
            R.u[0] = std::cos(yaw * kDeg);
            R.u[1] = std::sin(yaw * kDeg);
            R.runup = runup;
            std::memcpy(R.top, R.foot, sizeof R.top);
            R.top[0] += 3000.0f * R.u[0];
            R.top[1] += 3000.0f * R.u[1];
            for (const Approach &A : kApproaches) {
                if (!std::strcmp(A.name, ap)) {
                    std::printf("  trace: %s %s, foot (%.1f %.1f %.1f) uphill yaw %.1f\n", kind_name(kind), A.name, R.foot[0],
                                R.foot[1], R.foot[2], yaw);
                    ramp_run(L, s, R, A, kind, true);
                }
            }
        }
        return;
    }

    // ramps
    std::vector<Ramp> ramps;
    t0 = now_ms();
    find_ramps(s, (size_t)O.ramps, ramps);
    std::printf("  ramps: %zu found (%.0f ms); per ramp: speed at the foot (SA1 units / step) and FALL when the body "
                "crossed an up-facing floor from above\n", ramps.size(), now_ms() - t0);
    struct Fall {
        size_t ramp;
        const Approach *A;
        int kind;
        RunResult r;
    };
    std::vector<Fall> falls;
    int runs = 0, fallruns = 0;
    double tick_max = 0.0;
    uint32_t mtx_max = 0;
    for (size_t rix = 0; rix < ramps.size(); rix++) {
        const Ramp &R = ramps[rix];
        std::printf("    #%-2zu foot (%7.0f %7.0f %6.0f) up %5.0f deg, %4.0f high, slope %4.1f deg, run-up %4.0f:", rix, R.foot[0],
                    R.foot[1], R.foot[2], std::atan2(R.u[1], R.u[0]) / kDeg, R.top[2] - R.foot[2], R.slope, R.runup);
        static const int kinds[] = {SA1_CHAR_SONIC, SA1_CHAR_KNUCKLES, SA1_CHAR_TAILS};
        for (int kind : kinds) {
            for (const Approach &A : kApproaches) {
                if (A.trace_only || (A.spin && kind != SA1_CHAR_SONIC) || (kind != SA1_CHAR_SONIC && A.boost == 10.0f)) {
                    continue;
                }
                RunResult r = ramp_run(L, s, R, A, kind, false);
                runs++;
                tick_max = std::max(tick_max, r.tick_max);
                mtx_max = std::max(mtx_max, r.mtx_max);
                if (!r.created || r.fault) {
                    std::printf(" %c%s:ERR", kind_name(kind)[0], A.name);
                    continue;
                }
                std::printf(" %c%s:%s%.1f", kind_name(kind)[0], A.name, r.falls ? "FALL@" : "", r.foot_speed);
                if (r.falls) {
                    fallruns++;
                    falls.push_back({rix, &A, kind, r});
                }
            }
        }
        std::printf("\n");
        std::fflush(stdout);
    }
    std::printf("  ramps: %d runs, %d fell through a floor; longest tick %.2f ms; matrix stack depth up to %u\n", runs,
                fallruns, tick_max, mtx_max);
    for (size_t k = 0; k < falls.size() && k < 8; k++) {
        const Fall &F = falls[k];
        const Ramp &R = ramps[F.ramp];
        const RunResult &r = F.r;
        std::printf("    fall %zu: ramp #%zu, %s %s (foot speed %.2f, max %.2f): frame %d from (%.1f %.1f %.1f) to (%.1f %.1f "
                    "%.1f)", k, F.ramp, kind_name(F.kind), F.A->name, r.foot_speed, r.max_speed, r.fall_frame, r.fall_prev[0],
                    r.fall_prev[1], r.fall_prev[2], r.fall_pos[0], r.fall_pos[1], r.fall_pos[2]);
        if (r.fall_tri >= 0) {
            const float *nn = &s.n[3 * r.fall_tri];
            const sa1_collision_tri &q = s.t[r.fall_tri];
            std::printf(" through triangle %d (normal %.2f %.2f %.2f, %.0f deg; (%.0f %.0f %.0f) (%.0f %.0f %.0f) (%.0f %.0f "
                        "%.0f), surface %X)", r.fall_tri, nn[0], nn[1], nn[2], std::acos(std::min(1.0f, nn[2])) / kDeg,
                        q.v[0][0], q.v[0][1], q.v[0][2], q.v[1][0], q.v[1][1], q.v[1][2], q.v[2][0], q.v[2][1], q.v[2][2],
                        q.surface);
        }
        std::printf("; NEAR up to %d (full %d)\n", r.near_max, r.near_full);
        std::printf("      repro: --trace \"%.1f %.1f %.1f %.1f %s %d %.0f\"\n", R.foot[0], R.foot[1], R.foot[2],
                    std::atan2(R.u[1], R.u[0]) / kDeg, F.A->name, F.kind, R.runup);
        if (k < 2) {
            ramp_run(L, s, R, *F.A, F.kind, true);
        }
    }
    std::fflush(stdout);

    // random play
    if (O.random > 0) {
        RandStats RS;
        double mem0 = private_mb();
        t0 = now_ms();
        random_runs(L, s, O.random, O.secs, O.kinds, RS, base_name(path).c_str());
        std::printf("  random: %d runs x %.0f s (%.1f s wall): %llu ticks, %llu pairs, mean %.3f ms per tick, longest %.2f ms, "
                    "%llu > 16 ms, %llu > 50 ms; creates up to %.0f ms; %d faults; %d runs fell through a floor (%d "
                    "crossings); NEAR-poly list full in %d runs; matrix stack up to %u (%d runs left it deeper than 1)\n",
                    RS.runs, O.secs, (now_ms() - t0) / 1000.0, (unsigned long long)RS.ticks, (unsigned long long)RS.pairs,
                    RS.ticks ? RS.sum_ms / (double)RS.ticks : 0.0, RS.tick_max, (unsigned long long)RS.ticks16,
                    (unsigned long long)RS.ticks50, RS.create_max, RS.faults, RS.fall_runs, RS.falls, RS.near_full_runs,
                    RS.mtx_max, RS.mtx_runs);
        std::printf("    walls: %d runs entered a wall at body height (%d crossings)\n", RS.wall_runs, RS.walls);
        for (const std::string &n : RS.fall_notes) {
            std::printf("      first fall: %s\n", n.c_str());
        }
        for (const std::string &n : RS.wall_notes) {
            std::printf("      first wall entry: %s\n", n.c_str());
        }
        std::printf("    longest tick: %s\n", RS.worst.c_str());
        std::printf("    private memory: %.0f MB before the runs, %.0f MB after (%d characters created and destroyed)\n",
                    mem0, private_mb(), RS.creates);
        std::printf("    events:");
        for (auto &kv : RS.events) {
            std::printf(" [%s] x%d", kv.first.c_str(), kv.second);
        }
        std::printf("\n    stuck (stick held 3 s, moved < 8 units): %d", RS.stuck);
        for (const std::string &n : RS.stuck_notes) {
            std::printf("; %s", n.c_str());
        }
        std::printf("\n");
        std::printf("    render (sa1_character_render every frame): mean %.3f ms, longest %.2f ms, %llu > 16 ms; %s\n",
                    RS.renders ? RS.render_sum / (double)RS.renders : 0.0, RS.render_max, (unsigned long long)RS.renders16,
                    RS.worst_render.c_str());
    }
    sa1_collision_set_static(L.ctx, nullptr, 0);
    std::fflush(stdout);
}

int main(int argc, char **argv)
{
    Options O;
    std::vector<std::string> maps;
    const char *env = std::getenv("SA1_TEST_GDI");
    if (env) {
        O.gdi = env;
    }
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--gdi" && i + 1 < argc) {
            O.gdi = argv[++i];
        } else if (a == "--ramps" && i + 1 < argc) {
            O.ramps = std::atoi(argv[++i]);
        } else if (a == "--random" && i + 1 < argc) {
            O.random = std::atoi(argv[++i]);
        } else if (a == "--secs" && i + 1 < argc) {
            O.secs = (float)std::atof(argv[++i]);
        } else if (a == "--seed" && i + 1 < argc) {
            g_seed = (uint32_t)std::strtoul(argv[++i], nullptr, 0);
        } else if (a == "--watchdog" && i + 1 < argc) {
            g_watchdog_s = std::atof(argv[++i]);
        } else if (a == "--tess" && i + 1 < argc) {
            O.tess = (float)std::atof(argv[++i]);
        } else if (a == "--thin-wall" && i + 1 < argc) {
            O.thin_wall = (float)std::atof(argv[++i]);
        } else if (a == "--thin" && i + 1 < argc) {
            O.thin = (float)std::atof(argv[++i]);
        } else if (a == "--no-hidden") {
            O.no_hidden = true;
        } else if (a == "--max-edge" && i + 1 < argc) {
            O.max_edge = (float)std::atof(argv[++i]);
        } else if (a == "--cell" && i + 1 < argc) {
            O.cell = (float)std::atof(argv[++i]);
        } else if (a == "--cut") {
            O.cut = true;
        } else if (a == "--drop-sliver" && i + 1 < argc) {
            O.drop_sliver = (float)std::atof(argv[++i]);
        } else if (a == "--drop-under" && i + 1 < argc) {
            O.drop_under = (float)std::atof(argv[++i]);
        } else if (a == "--legacy") {
            O.legacy = true;
        } else if (a == "--set-static") {
            O.set_static = true;
        } else if (a == "--no-world-images") {
            g_world_images = false;
        } else if (a == "--no-props") {
            O.props = false;
        } else if (a == "--dc-limits") {
            O.dc_limits = true;
            g_near_cap = 96;
        } else if (a == "--gm" && i + 1 < argc) {
            O.gm = argv[++i];
        } else if (a == "--water") {
            g_water_spawn = true;
        } else if (a == "--no-cost") {
            O.cost = false;
        } else if (a == "--dump" && i + 1 < argc) {
            O.dump = argv[++i];
        } else if (a == "--trace" && i + 1 < argc) {
            O.trace = argv[++i];
        } else if (a == "--kinds" && i + 1 < argc) {
            O.kinds.clear();
            for (const char *p = argv[++i]; *p; p++) {
                if (*p >= '0' && *p <= '9') {
                    O.kinds.push_back(*p - '0');
                }
            }
        } else if (a == "--replay" && i + 1 < argc) {
            unsigned sd = 0;
            if (std::sscanf(argv[++i], "%f %f %f %d %u", &g_replay_pos[0], &g_replay_pos[1], &g_replay_pos[2],
                            &g_replay_kind, &sd) == 5) {
                g_replay = true;
                g_replay_seed = sd;
                O.random = 1;
                O.ramps = 0;
            }
        } else if (a == "--verbose") {
            g_verbose = true;
        } else if (a == "--gmas") {
            g_gmas = true;
        } else if (a == "--undersides-drop") {
            O.undersides_drop = true;
        } else if (a == "--no-front-only") {
            O.no_front_only = true;
        } else if (a == "--no-curved") {
            O.no_curved = true;
        } else if (a == "--old-disp-brushes") {
            O.old_disp_brushes = true;
        } else if (a == "--disp-cover-max" && i + 1 < argc) {
            O.disp_cover_max = (float)std::atof(argv[++i]);
        } else if (a == "--ceiljump" && i + 1 < argc) {
            O.ceiljump = argv[++i];
        } else if (a == "--ceilgrid" && i + 1 < argc) {
            O.ceilgrid = argv[++i];
        } else if (a == "--jkinds" && i + 1 < argc) {
            g_jkinds = argv[++i];
        } else if (a == "--jtrace") {
            O.jtrace = true;
        } else if (a == "--loop" && i + 1 < argc) {
            O.loop.have = std::sscanf(argv[++i], "%lf %lf %lf %lf %lf", &O.loop.cx, &O.loop.cy, &O.loop.cz, &O.loop.R,
                                      &O.loop.T) == 5;
        } else if (a == "--looprun" && i + 1 < argc) {
            O.looprun = argv[++i];
        } else if (a == "--speeds" && i + 1 < argc) {
            O.speeds = argv[++i];
        } else if (a == "--loopkinds" && i + 1 < argc) {
            O.loopkinds = argv[++i];
        } else if (a == "--looptop") {
            O.looptop = true;
        } else if (a == "--curved-report") {
            O.curved_report = true;
        } else if (a == "--save-tris" && i + 1 < argc) {
            O.save_tris = argv[++i];
        } else if (a == "--loopspin") {
            g_loop_spin = true;
        } else {
            maps.push_back(a);
        }
    }
    if (O.gdi.empty() || maps.empty()) {
        std::printf("usage: diag_maps --gdi GAME.gdi [--ramps N] [--random N] [--secs S] [--seed N] [--kinds 023567] "
                    "[--watchdog S] [--no-cost] [--trace \"x y z yaw approach kind\"] [--verbose] MAP.bsp...\n");
        return 2;
    }
    std::printf("G-SA1 diag_maps (libsa1 %s), watchdog %.0f s\n", sa1_version_string(), g_watchdog_s);
    CreateThread(nullptr, 0, watchdog, nullptr, 0, nullptr);
    Lib L;
    std::string e;
    std::snprintf(g_what, sizeof g_what, "sa1_load_disc");
    if (!L.init(O.gdi, e)) {
        std::printf("%s\n", e.c_str());
        return 1;
    }
    std::printf("disc loaded in %.0f ms\n", L.disc_ms);
    for (const std::string &m : maps) {
        do_map(L, m, O);
    }
    L.shutdown();
    std::printf("\ndone (%u libsa1 warnings)\n", g_warns);
    return 0;
}
