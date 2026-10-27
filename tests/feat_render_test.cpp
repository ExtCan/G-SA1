// feat_render_test: the render feature's core test (0.8; sadc docs/research/gsa1_060_shadow.md G1 / G3 / T4 with its
// review R.3.3, gsa1_060_render.md review R3.1 / R7.3). Linked like core_test (the core objects and libsa1, no module,
// no Lua) by build.py, run with --gdi GAME.gdi when one is given.
//
//   feat_render_test [--gdi GAME.gdi]
//
// Without the disc:
//   * prepare_view's vertex colours of the blob shadow: a SA1_DRAW_SHADOW batch keeps its vertex colour with
//     gsa1_vertexcolor 0 (its diffuse alpha is the shadow's darkness: review R.3.3a; before: RGB 255), and a mask batch
//     (wrap WRAP_MASK) gets (a, a, a, 255) - (204, 204, 204, 255) for the game's diffuse alpha 204 - either way;
//   * camera-relative positions: with ViewOptions::relative every written position is p - origin (triangles, sprites,
//     lines, the filler), sprites still face the eye, and the screen coverage is the same as with absolute positions;
//   * the GPU depth path at the owner's gm_bigcity coordinates, emulated (float32 vertices and vertex shader dot
//     products, a D24 depth buffer, LESSEQUAL with the front layer drawn later; the review's zsim): two layers 0.04 HU
//     apart at (5400, 9000, -11136) seen from 220 HU at 16 azimuths - with absolute positions the front layer loses in
//     some samples (z-fighting with the character standing still), with positions relative to the character in none.
// With the disc (a flat floor at the owner's gm_bigcity height and position):
//   * each of the six characters standing has exactly one shadow batch: blended (pass 1), its own key, 2 triangles,
//     OBJ_REGULAR's texture 58 "shadow" (black in every texel: the mask path, wrap WRAP_MASK), corner colours (204, 204,
//     204, 255) with gsa1_vertexcolor 0, 1.2 HU (the game's 0.3 units) above the floor;
//   * PrepareView with the character's root as the origin writes every position within a few hundred HU of 0 (absolute:
//     about 11000), and relative + origin = absolute.
// 0.9.1, the lit see-through batches (sadc docs/research/gsa1_070_translucency.md T1 / T2.1 with its review R2.1, R2.2,
// R3.2): Source's VertexLitGeneric ignores the vertex alpha, so a lit blended batch carries its draws' alpha
// (RenderBatch::alpha, key ".a<alpha>") for the material's $alpha:
//   * without the disc (Session::rebatch on made-up draws): equal alphas merge, other alphas start a batch of their own
//     with their own key; alpha 255 keeps the old key; unlit batches are not keyed (their alphas change every pair); an
//     opaque batch neither; a draw whose alpha is not constant takes the mean (logged once); a state's ninth and later
//     alphas are rounded to steps of 17;
//   * with the disc: Tails idle, running and in the air, Amy's hammer, E-102 running (all their upgrades), each pair at
//     render alpha 1 and 0.5: every lit blended batch's vertex alphas are one value, equal to RenderBatch::alpha and to
//     its key's suffix; a key never stands for two alphas; Tails draws 170 and 85, Amy 51 and 76 (77 before libsa1's T4),
//     E-102 216. 0.9.0's keys stood for several alphas (Tails' mtx_tail copies at 170 and 85 shared 0.15.21.4.5.3.1).
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "session.hpp"

using namespace gsa1;

static int g_fail = 0, g_checks = 0;
#define CHECK(cond, ...)                               \
    do {                                               \
        g_checks++;                                    \
        std::printf((cond) ? "  ok    " : "  FAIL  "); \
        if (!(cond)) g_fail++;                         \
        std::printf(__VA_ARGS__);                      \
        std::printf("\n");                             \
    } while (0)

// ---- prepare_view rules (no disc) -----------------------------------------------------------------------------------
static void add_tri(Character &c, const float p[9], const uint8_t col[4])
{
    for (int k = 0; k < 9; k++) {
        c.r_tpos.push_back(p[k]);
        c.r_tnrm.push_back(k % 3 == 2 ? 1.0f : 0.0f);
    }
    for (int k = 0; k < 6; k++) {
        c.r_tuv.push_back(0.5f);
    }
    for (int k = 0; k < 3; k++) {
        c.r_tcol.insert(c.r_tcol.end(), col, col + 4);
    }
    c.r_triangles++;
}

static RenderBatch &add_batch(Character &c, uint32_t prim, uint32_t first, int32_t archive, uint32_t flags, uint32_t pass,
                              uint32_t wrap, uint32_t tris)
{
    sa1_draw d;
    std::memset(&d, 0, sizeof d);
    d.prim = prim;
    d.first = first;
    d.count = 1;
    d.archive = archive;
    d.texture = archive >= 0 ? 58 : -1;
    d.flags = flags;
    d.blend_src = SA1_BLEND_SRC_ALPHA;
    d.blend_dst = SA1_BLEND_INV_SRC_ALPHA;
    c.r_draws.push_back(d);
    if (c.batches.size() <= c.batch_count) {
        c.batches.resize(c.batch_count + 1);
    }
    RenderBatch &rb = c.batches[c.batch_count++];
    rb = RenderBatch();
    rb.pass = pass;
    rb.archive = archive;
    rb.texture = d.texture;
    rb.flags = flags;
    rb.wrap = wrap;
    rb.prims = (uint8_t)(1u << prim);
    rb.triangles = tris;
    rb.draws.assign(1, (uint32_t)c.r_draws.size() - 1u);
    return rb;
}

static void test_view_rules()
{
    std::printf("prepare_view: the blob shadow's colours, camera-relative positions (no disc):\n");
    Session s;
    Character c;
    const uint32_t SH = SA1_DRAW_BLEND | SA1_DRAW_EFFECT | SA1_DRAW_SHADOW;
    const uint8_t grey[4] = {178, 178, 178, 204}, body[4] = {10, 200, 30, 255};
    // 0: a shadow batch on the ordinary path, 1: the same on the mask path, 2: an ordinary textured effect, 3: a sprite,
    // 4: a line segment; at the owner's gm_bigcity coordinates
    const float X = 5400.25f, Y = 9000.5f, Z = -11134.75f;
    const float t0[9] = {X - 15, Y - 12, Z, X + 15, Y - 12, Z, X + 15, Y + 12, Z};
    add_tri(c, t0, grey);
    add_tri(c, t0, grey);
    add_tri(c, t0, body);
    add_batch(c, SA1_PRIM_TRIANGLES, 0, 2, SH, 1, WRAP_CLAMP_U | WRAP_CLAMP_V, 1);
    add_batch(c, SA1_PRIM_TRIANGLES, 1, 2, SH, 1, WRAP_CLAMP_U | WRAP_CLAMP_V | WRAP_MASK, 1);
    add_batch(c, SA1_PRIM_TRIANGLES, 2, 1, SA1_DRAW_BLEND | SA1_DRAW_EFFECT, 1, WRAP_CLAMP_U | WRAP_CLAMP_V, 1);
    sa1_sprite sp;
    std::memset(&sp, 0, sizeof sp);
    sp.position[0] = X + 40.0f;
    sp.position[1] = Y;
    sp.position[2] = Z + 30.0f;
    sp.rect[0] = -8;
    sp.rect[1] = -8;
    sp.rect[2] = 8;
    sp.rect[3] = 8;
    sp.uv[2] = sp.uv[3] = 1.0f;
    std::memset(sp.color, 255, 4);
    c.r_sprites.push_back(sp);
    add_batch(c, SA1_PRIM_SPRITES, 0, 1, SA1_DRAW_BLEND | SA1_DRAW_EFFECT | SA1_DRAW_DOUBLE_SIDED, 1, 3, 2);
    sa1_line_vertex lv[2];
    std::memset(lv, 0, sizeof lv);
    lv[0].position[0] = X;
    lv[0].position[1] = Y;
    lv[0].position[2] = Z + 20.0f;
    lv[1].position[0] = X + 200.0f;
    lv[1].position[1] = Y + 50.0f;
    lv[1].position[2] = Z + 20.0f;
    lv[0].color[3] = lv[1].color[3] = 255;
    c.r_lines.assign(lv, lv + 2);
    add_batch(c, SA1_PRIM_LINES, 0, -1, SA1_DRAW_BLEND | SA1_DRAW_EFFECT | SA1_DRAW_UNLIT, 1, 0, 2);
    std::memcpy(c.r_pos, t0, sizeof c.r_pos);
    c.r_pos[0] = X;
    c.r_pos[1] = Y;

    const float eye[3] = {X - 220.0f, Y, Z + 40.0f}, right[3] = {0, -1, 0}, up[3] = {0, 0, 1};
    ViewOptions o;
    auto rgba = [&](uint32_t b) {
        const RenderBatch &rb = c.batches[b];
        return format("%u %u %u %u", rb.col[0], rb.col[1], rb.col[2], rb.col[3]);
    };
    o.vertex_color = false;
    s.prepare_view(c, eye, right, up, o);
    std::string s0 = rgba(0), s1 = rgba(1), s2 = rgba(2);
    o.vertex_color = true;
    s.prepare_view(c, eye, right, up, o);
    std::string s0b = rgba(0), s1b = rgba(1);
    CHECK(s0 == "178 178 178 204" && s1 == "204 204 204 255" && s2 == "255 255 255 255" && s0b == s0 && s1b == s1,
          "the blob shadow with gsa1_vertexcolor 0: the ordinary path keeps its colour (%s; 0.7 made RGB 255: a 100%% "
          "black core), the mask path (wrap WRAP_MASK) writes (a, a, a, 255) = %s either way; an ordinary textured "
          "effect still turns white (%s)", s0.c_str(), s1.c_str(), s2.c_str());

    // camera-relative: the same view with the character's root as the origin
    o.fov = 90.0f;
    o.width = 1920.0f;
    o.height = 1080.0f;
    s.prepare_view(c, eye, right, up, o);
    std::vector<std::vector<float>> abs_pos;
    for (uint32_t b = 0; b < c.batch_count; b++) abs_pos.push_back(c.batches[b].pos);
    std::vector<float> abs_nrm = c.batches[3].nrm;
    float cover_abs = c.view_cover;
    ViewOptions r = o;
    r.relative = true;
    r.origin[0] = X;
    r.origin[1] = Y;
    r.origin[2] = Z;
    s.prepare_view(c, eye, right, up, r);
    double worst = 0.0, far_rel = 0.0, far_abs = 0.0, worst_n = 0.0;
    for (uint32_t b = 0; b < c.batch_count; b++) {
        const std::vector<float> &a = abs_pos[b], &p = c.batches[b].pos;
        for (size_t i = 0; i < p.size() && i < a.size(); i++) {
            double o3 = r.origin[i % 3];
            worst = std::max(worst, std::fabs((double)p[i] + o3 - (double)a[i]));
            far_rel = std::max(far_rel, std::fabs((double)p[i]));
            far_abs = std::max(far_abs, std::fabs((double)a[i]));
        }
    }
    for (size_t i = 0; i < abs_nrm.size(); i++) worst_n = std::max(worst_n, std::fabs((double)abs_nrm[i] - c.batches[3].nrm[i]));
    // exactly p - origin for the triangles (libsa1's float positions minus the origin in double; the written corners are
    // in Source's winding order, so each is matched with one of the triangle's corners)
    bool exact = c.batches[0].pos.size() == 9;
    for (int v = 0; v < 3 && exact; v++) {
        bool found = false;
        for (int k = 0; k < 3 && !found; k++) {
            found = true;
            for (int m = 0; m < 3; m++) {
                found = found && c.batches[0].pos[3 * v + m] == (float)((double)t0[3 * k + m] - (double)r.origin[m]);
            }
        }
        exact = found;
    }
    CHECK(c.view_opt.relative && exact && worst < 0.002 && far_rel < 300.0 && far_abs > 10000.0 && worst_n < 1e-5 &&
              std::fabs(c.view_cover - cover_abs) < 1e-5f,
          "camera-relative: every position written as p - origin (largest %.1f HU, absolute %.0f HU; relative + origin = "
          "absolute within %.4f HU, triangles exactly), sprites face the eye as before (normals within %.1g), the screen "
          "coverage unchanged (%.5f / %.5f)", far_rel, far_abs, worst, worst_n, c.view_cover, cover_abs);
}

// ---- the GPU depth path, emulated (the review's zsim: review_probe.c zs_vert / zs_depth) -----------------------------
struct V3 {
    double x, y, z;
};
static V3 v3(double x, double y, double z) { return V3{x, y, z}; }
static V3 sub(V3 a, V3 b) { return v3(a.x - b.x, a.y - b.y, a.z - b.z); }
static V3 add(V3 a, V3 b) { return v3(a.x + b.x, a.y + b.y, a.z + b.z); }
static V3 mul(V3 a, double k) { return v3(a.x * k, a.y * k, a.z * k); }
static double dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static V3 cross(V3 a, V3 b) { return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x); }
static V3 unit(V3 a) { return mul(a, 1.0 / std::sqrt(dot(a, a))); }

struct ZView {
    float M[16];      // clip = M * (x, y, z, 1): what the GPU uses (float32)
    double Md[16];    // the same in double, for the exact reference
};

// view-projection of a camera at `cam` looking at `at` (Source-like: x forward, z up), horizontal fov 106 at 3440 x 1440
static ZView make_view(V3 cam, V3 at, double zn, double zf)
{
    V3 f = unit(sub(at, cam)), r = unit(v3(f.y, -f.x, 0.0)), u = cross(r, f);
    double V[16] = {r.x, r.y, r.z, -dot(r, cam), u.x, u.y, u.z, -dot(u, cam), f.x, f.y, f.z, -dot(f, cam), 0, 0, 0, 1};
    double P[16] = {0};
    P[0] = 1.0 / std::tan(0.5 * 106.0 * 3.14159265358979323846 / 180.0);
    P[5] = P[0] * 3440.0 / 1440.0;
    P[10] = zf / (zf - zn);
    P[11] = -zn * zf / (zf - zn);
    P[14] = 1.0;
    ZView z;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            double m = 0.0;
            for (int k = 0; k < 4; k++) m += P[4 * i + k] * V[4 * k + j];
            z.Md[4 * i + j] = m;
            z.M[4 * i + j] = (float)m;
        }
    }
    return z;
}

// float32 path: the vertex as the GPU gets it (float), dot products in float32 (no FMA)
static void zv_float(const ZView &z, const float p[3], double &sx, double &sy, double &zw)
{
    float c[4];
    for (int i = 0; i < 4; i++) {
        float t = z.M[4 * i] * p[0];
        t = t + z.M[4 * i + 1] * p[1];
        t = t + z.M[4 * i + 2] * p[2];
        c[i] = t + z.M[4 * i + 3];
    }
    sx = (double)(c[0] / c[3]);
    sy = (double)(c[1] / c[3]);
    zw = (double)(c[2] / c[3]);
}

static void zv_exact(const ZView &z, V3 p, double &sx, double &sy, double &zw)
{
    double c[4];
    for (int i = 0; i < 4; i++) c[i] = z.Md[4 * i] * p.x + z.Md[4 * i + 1] * p.y + z.Md[4 * i + 2] * p.z + z.Md[4 * i + 3];
    sx = c[0] / c[3];
    sy = c[1] / c[3];
    zw = c[2] / c[3];
}

// depth of a triangle (screen-space corners x, y, depth z) at the screen point q; inside: covered
static double tri_depth(const double x[3], const double y[3], const double z[3], double qx, double qy, bool *inside)
{
    double den = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2]);
    if (std::fabs(den) < 1e-30) {
        if (inside) *inside = false;
        return 2.0;
    }
    double l0 = ((y[1] - y[2]) * (qx - x[2]) + (x[2] - x[1]) * (qy - y[2])) / den;
    double l1 = ((y[2] - y[0]) * (qx - x[2]) + (x[0] - x[2]) * (qy - y[2])) / den;
    double l2 = 1.0 - l0 - l1;
    if (inside) *inside = l0 >= -1e-12 && l1 >= -1e-12 && l2 >= -1e-12;
    return l0 * z[0] + l1 * z[1] + l2 * z[2];
}

struct ZResult {
    uint32_t samples = 0, fails = 0;
    double min_exact = 1e30, min_quant = 1e30;
};

// two layers (a 12 x 8 HU grid of 6 x 4 quads, the front one `gap` HU nearer the camera along the layers' normal) at
// `centre`, 220 HU from the camera 20 HU up, 16 azimuths; relative: positions and the camera minus `origin`
static ZResult zsim(V3 centre, V3 origin, double gap, bool relative)
{
    ZResult res;
    const double zn = 3.0, zf = 30000.0;
    for (int az = 0; az < 16; az++) {
        double a = az * 3.14159265358979323846 / 8.0;
        V3 cam = v3(centre.x + 220.0 * std::cos(a), centre.y + 220.0 * std::sin(a), centre.z + 20.0);
        // the layers face the camera, tilted 30 degrees off the view direction (eye whites on a turned head)
        V3 to_cam = unit(sub(cam, centre));
        double ta = std::atan2(to_cam.y, to_cam.x) + 0.52;
        V3 n = unit(v3(std::cos(ta), std::sin(ta), 0.15));
        V3 e1 = unit(cross(v3(0, 0, 1), n)), e2 = cross(n, e1);
        // GMod's side: the eye is a float Vector; camera-relative, the view's eye is EyePos() - origin (float subtract)
        float camf[3] = {(float)cam.x, (float)cam.y, (float)cam.z}, of[3] = {(float)origin.x, (float)origin.y, (float)origin.z};
        V3 camv = relative ? v3((double)(camf[0] - of[0]), (double)(camf[1] - of[1]), (double)(camf[2] - of[2]))
                           : v3(camf[0], camf[1], camf[2]);
        V3 at = relative ? sub(centre, v3(of[0], of[1], of[2])) : centre;
        ZView zv = make_view(camv, at, zn, zf);
        // exact reference: the same view in absolute double coordinates
        ZView ze = make_view(cam, centre, zn, zf);
        const int NX = 6, NY = 4;
        auto vert = [&](int layer, int i, int j) {
            V3 p = add(centre, add(mul(e1, -6.0 + 12.0 * i / NX), mul(e2, -4.0 + 8.0 * j / NY)));
            // a slight bend, so the layers are not planar (as the eye models are not)
            p = add(p, mul(n, 0.15 * std::sin(1.3 * i + 0.7 * j) + (layer ? gap : 0.0)));
            return p;
        };
        for (int i = 0; i < NX; i++) {
            for (int j = 0; j < NY; j++) {
                for (int half = 0; half < 2; half++) {
                    int ci[3][2] = {{i, j}, {i + 1, j}, {i + 1, j + 1}};
                    if (half) {
                        ci[1][0] = i + 1; ci[1][1] = j + 1;
                        ci[2][0] = i; ci[2][1] = j + 1;
                    }
                    V3 P[2][3];
                    double fx[2][3], fy[2][3], fz[2][3], ex[2][3], ey[2][3], ez[2][3];
                    for (int L = 0; L < 2; L++) {
                        for (int k = 0; k < 3; k++) {
                            P[L][k] = vert(L, ci[k][0], ci[k][1]);
                            // libsa1's float position, then the module's p - origin in double, rounded to float
                            float pf[3] = {(float)P[L][k].x, (float)P[L][k].y, (float)P[L][k].z};
                            float pw[3];
                            for (int m = 0; m < 3; m++) pw[m] = relative ? (float)((double)pf[m] - (double)of[m]) : pf[m];
                            zv_float(zv, pw, fx[L][k], fy[L][k], fz[L][k]);
                            zv_exact(ze, P[L][k], ex[L][k], ey[L][k], ez[L][k]);
                        }
                    }
                    // samples: the centroid and three points towards the corners
                    for (int sidx = 0; sidx < 4; sidx++) {
                        double w[3] = {1.0 / 3, 1.0 / 3, 1.0 / 3};
                        if (sidx > 0) {
                            for (int k = 0; k < 3; k++) w[k] = k == sidx - 1 ? 0.8 : 0.1;
                        }
                        V3 q = add(add(mul(P[1][0], w[0]), mul(P[1][1], w[1])), mul(P[1][2], w[2]));
                        double qx, qy, qz;
                        zv_exact(ze, q, qx, qy, qz);
                        bool inA = false, inB = false;
                        double eA = tri_depth(ex[0], ey[0], ez[0], qx, qy, &inA), eB = tri_depth(ex[1], ey[1], ez[1], qx, qy, &inB);
                        if (!inA || !inB) continue;
                        // the float32 path at the same pixel: its screen position from the float32 transform of the
                        // reference point is the same pixel up to rounding; the depths come from each path's corners
                        double fA = tri_depth(fx[0], fy[0], fz[0], qx, qy, nullptr);
                        double fB = tri_depth(fx[1], fy[1], fz[1], qx, qy, nullptr);
                        double me = (eA - eB) * 16777215.0;
                        double mq = std::floor(fA * 16777215.0 + 0.5) - std::floor(fB * 16777215.0 + 0.5);
                        res.samples++;
                        res.min_exact = std::min(res.min_exact, me);
                        if (me > 0) {
                            res.min_quant = std::min(res.min_quant, mq);
                            if (mq < 0) res.fails++;   // the front layer (drawn later) fails LESSEQUAL
                        }
                    }
                }
            }
        }
    }
    return res;
}

static void test_depth_precision()
{
    std::printf("the GPU depth path at gm_bigcity coordinates, emulated (float32 vertex transform, D24, LESSEQUAL):\n");
    const V3 owner = v3(5400.0, 9000.0, -11136.0 + 60.0), origin_pt = v3(0.0, 0.0, 60.0);
    // the character's root (the origin the addon passes) is its drawn position: 60 HU below the layers here
    ZResult a = zsim(owner, v3(5400.0, 9000.0, -11136.0), 0.04, false);
    ZResult r = zsim(owner, v3(5400.0, 9000.0, -11136.0), 0.04, true);
    ZResult a0 = zsim(origin_pt, v3(0.0, 0.0, 0.0), 0.04, false);
    CHECK(a.samples > 500 && r.samples == a.samples && a.fails > 0 && r.fails == 0 && a0.fails == 0,
          "two layers 0.04 HU apart (exact margin at least %.0f D24 steps): at (5400, 9000, -11136) with absolute "
          "positions the front layer loses %u of %u samples (quantised margin down to %.0f steps: z-fighting standing "
          "still), relative to the character %u (down to %.0f); at the map's centre with absolute positions %u",
          a.min_exact, a.fails, a.samples, a.min_quant, r.fails, r.min_quant, a0.fails);
}

// ---- lit see-through batches (no disc): the batch rules of Session::build_batches ---------------------------------------
static void push_draw(Character &c, uint32_t prim, uint32_t first, uint32_t count, int32_t texture, uint32_t flags)
{
    sa1_draw d;
    std::memset(&d, 0, sizeof d);
    d.prim = prim;
    d.first = first;
    d.count = count;
    d.archive = 0;
    d.texture = texture;
    d.flags = flags;
    d.blend_src = SA1_BLEND_SRC_ALPHA;
    d.blend_dst = SA1_BLEND_INV_SRC_ALPHA;
    d.order = (uint32_t)c.r_draws.size();
    c.r_draws.push_back(d);
}

static void test_alpha_rules()
{
    std::printf("lit see-through batches: the batch rules (no disc):\n");
    Session s;
    Character c;
    const uint32_t LIT = SA1_DRAW_BLEND | SA1_DRAW_PALETTE_LIT, FX = SA1_DRAW_BLEND | SA1_DRAW_UNLIT | SA1_DRAW_EFFECT;
    const float t0[9] = {0, 0, 0, 10, 0, 0, 10, 10, 0};
    auto tri = [&](uint8_t a0, uint8_t a1, uint8_t a2) {
        uint32_t i = c.r_triangles;
        const uint8_t w[4] = {255, 255, 255, a0};
        add_tri(c, t0, w);
        c.r_tcol[(size_t)i * 12u + 7u] = a1;
        c.r_tcol[(size_t)i * 12u + 11u] = a2;
        return i;
    };
    // Tails' two blur copies of one texture (two draws at 170, one at 85), the same texture at 255, two unlit sprites
    // (alpha 25 and 200), a lit draw of three alphas (100, 100, 200), an opaque lit draw of alpha 0 (Knuckles' opaque-list
    // copy parts), then ten draws of another texture at 10, 20, ..., 100
    push_draw(c, SA1_PRIM_TRIANGLES, tri(170, 170, 170), 1, 15, LIT);
    push_draw(c, SA1_PRIM_TRIANGLES, tri(170, 170, 170), 1, 15, LIT | SA1_DRAW_AFTERIMAGE);
    push_draw(c, SA1_PRIM_TRIANGLES, tri(85, 85, 85), 1, 15, LIT | SA1_DRAW_AFTERIMAGE);
    push_draw(c, SA1_PRIM_TRIANGLES, tri(255, 255, 255), 1, 15, LIT);
    for (int k = 0; k < 2; k++) {
        sa1_sprite sp;
        std::memset(&sp, 0, sizeof sp);
        sp.rect[0] = sp.rect[1] = -4;
        sp.rect[2] = sp.rect[3] = 4;
        sp.uv[2] = sp.uv[3] = 1.0f;
        std::memset(sp.color, 255, 4);
        sp.color[3] = k == 0 ? 25 : 200;
        c.r_sprites.push_back(sp);
    }
    push_draw(c, SA1_PRIM_SPRITES, 0, 1, 3, FX);
    push_draw(c, SA1_PRIM_SPRITES, 1, 1, 3, FX);
    push_draw(c, SA1_PRIM_TRIANGLES, tri(100, 100, 200), 1, 15, LIT);
    push_draw(c, SA1_PRIM_TRIANGLES, tri(0, 0, 0), 1, 15, SA1_DRAW_PALETTE_LIT);
    for (int k = 1; k <= 10; k++) {
        uint8_t a = (uint8_t)(10 * k);
        push_draw(c, SA1_PRIM_TRIANGLES, tri(a, a, a), 1, 16, LIT | SA1_DRAW_AFTERIMAGE);
    }
    s.take_log();
    s.rebatch(c);
    std::vector<std::string> log = s.take_log();
    std::string keys;
    for (uint32_t b = 0; b < c.batch_count; b++) {
        keys += format("%s%s/%u/%u", b ? " " : "", c.batches[b].key.c_str(), (unsigned)c.batches[b].alpha,
                       c.batches[b].triangles);
    }
    const std::string want =
        "0.15.21.4.5.0.1.a170/170/2 0.15.21.4.5.0.1.a85/85/1 0.15.21.4.5.0.1/255/1 0.3.55.4.5.3.1/255/4 "
        "0.15.21.4.5.0.1.a133/133/1 0.15.20.1.0.0.0/255/1 0.16.21.4.5.0.1.a10/10/1 0.16.21.4.5.0.1.a20/20/1 "
        "0.16.21.4.5.0.1.a30/30/1 0.16.21.4.5.0.1.a40/40/1 0.16.21.4.5.0.1.a50/50/1 0.16.21.4.5.0.1.a60/60/1 "
        "0.16.21.4.5.0.1.a70/70/1 0.16.21.4.5.0.1.a80/80/1 0.16.21.4.5.0.1.a85/85/1 0.16.21.4.5.0.1.a102/102/1";
    bool logged = log.size() == 1 && log[0].find("G-SA1 render") != std::string::npos &&
                  log[0].find("several vertex alphas") != std::string::npos;
    CHECK(keys == want && c.lit_alpha_varied == 1 && c.lit_alpha_rounded == 2 && logged,
          "batches (key/alpha/triangles): %s; varied %llu, rounded %llu; log: %s", keys.c_str(),
          (unsigned long long)c.lit_alpha_varied, (unsigned long long)c.lit_alpha_rounded,
          log.empty() ? "-" : log[0].c_str());
    // the same draws again: the same batches and the same keys (the state's exact alphas are remembered), no new log line
    std::string first = keys;
    s.rebatch(c);
    keys.clear();
    for (uint32_t b = 0; b < c.batch_count; b++) {
        keys += format("%s%s/%u/%u", b ? " " : "", c.batches[b].key.c_str(), (unsigned)c.batches[b].alpha,
                       c.batches[b].triangles);
    }
    CHECK(keys == first && s.take_log().empty(), "the same draws again: the same %u batches, no second log line",
          c.batch_count);
}

// ---- with the disc ---------------------------------------------------------------------------------------------------
static const char *kind_name(int32_t k)
{
    switch (k) {
    case SA1_CHAR_SONIC: return "Sonic";
    case SA1_CHAR_TAILS: return "Tails";
    case SA1_CHAR_KNUCKLES: return "Knuckles";
    case SA1_CHAR_AMY: return "Amy";
    case SA1_CHAR_GAMMA: return "E-102";
    case SA1_CHAR_BIG: return "Big";
    default: return "?";
    }
}

static void test_shadows(const std::string &gdi)
{
    std::printf("the blob shadow and camera-relative positions of the six characters (gm_bigcity's coordinates):\n");
    Session s;
    std::string err;
    if (!s.init(gdi, err)) {
        CHECK(false, "init: %s", err.c_str());
        return;
    }
    const float X = 5400.0f, Y = 9000.0f, Z = -11136.0f;
    std::vector<sa1_collision_tri> floor;
    for (int i = -4; i < 4; i++) {
        for (int j = -4; j < 4; j++) {
            float x0 = X + 512.0f * i, y0 = Y + 512.0f * j, x1 = x0 + 512.0f, y1 = y0 + 512.0f;
            sa1_collision_tri a = {{{x0, y0, Z}, {x1, y0, Z}, {x1, y1, Z}}, SA1_SURFACE_SOLID};
            sa1_collision_tri b = {{{x0, y0, Z}, {x1, y1, Z}, {x0, y1, Z}}, SA1_SURFACE_SOLID};
            floor.push_back(a);
            floor.push_back(b);
        }
    }
    CHECK(s.set_world(floor, err), "a flat floor of %u triangles at z %.0f around (%.0f, %.0f)%s%s", (unsigned)floor.size(),
          Z, X, Y, err.empty() ? "" : ": ", err.c_str());
    static const int32_t kinds[] = {SA1_CHAR_SONIC, SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA,
                                    SA1_CHAR_BIG};
    for (int32_t k : kinds) {
        const float pos[3] = {X + 13.7f, Y + 7.3f, Z + 8.0f};
        int32_t id = s.create(k, pos, 0.0f, err);
        if (id <= 0) {
            CHECK(false, "%s: create: %s", kind_name(k), err.c_str());
            continue;
        }
        for (int f = 0; f < 48; f++) {
            s.tick(id, 0.0f, 0.0f, 0.0f, 0, 1.0f / 60.0f);
        }
        s.render(id, -1.0f);
        Character *c = s.get(id);
        ViewOptions o;
        o.vertex_color = false;
        const float eye[3] = {c->r_pos[0] - 150.0f, c->r_pos[1], c->r_pos[2] + 40.0f}, right[3] = {0, -1, 0},
                    up[3] = {0, 0, 1};
        s.prepare_view(*c, eye, right, up, o);
        uint32_t shadows = 0, keys_same = 0;
        const RenderBatch *sb = nullptr;
        for (uint32_t b = 0; b < c->batch_count; b++) {
            const RenderBatch &rb = c->batches[b];
            if (rb.flags & SA1_DRAW_SHADOW) {
                shadows++;
                sb = &rb;
            }
        }
        std::string aname, tname, cols;
        bool colours = false, height = false;
        double zmin = 1e30, zmax = -1e30;
        if (sb) {
            for (uint32_t b = 0; b < c->batch_count; b++) keys_same += c->batches[b].key == sb->key && &c->batches[b] != sb;
            uint32_t n = 0;
            s.texture_count(k, (uint32_t)std::max(sb->archive, 0), n, err, &aname);
            sa1_texture_info ti;
            std::memset(&ti, 0, sizeof ti);
            ti.struct_size = sizeof ti;
            if (sa1_texture_get(s.ctx(), k, (uint32_t)std::max(sb->archive, 0), (uint32_t)std::max(sb->texture, 0), &ti) ==
                    SA1_OK && ti.name) {
                tname = ti.name;
            }
            colours = !sb->col.empty();
            for (size_t v = 0; v + 3 < sb->col.size() + 1 && v < sb->col.size(); v += 4) {
                colours = colours && sb->col[v] == 204 && sb->col[v + 1] == 204 && sb->col[v + 2] == 204 && sb->col[v + 3] == 255;
            }
            for (size_t v = 2; v < sb->pos.size(); v += 3) {
                zmin = std::min(zmin, (double)sb->pos[v]);
                zmax = std::max(zmax, (double)sb->pos[v]);
            }
            height = zmin > Z + 0.7 && zmax < Z + 1.7;
            cols = format("%u %u %u %u", sb->col[0], sb->col[1], sb->col[2], sb->col[3]);
        }
        CHECK(shadows == 1 && sb && c->shadow_draws == 1 && sb->pass == 1 && sb->triangles == 2 && keys_same == 0 &&
                  (sb->wrap & WRAP_MASK) && aname == "OBJ_REGULAR" && sb->texture == 58 && tname == "shadow" && colours &&
                  height,
              "%s standing: %u shadow batch (%u shadow draw): pass %u, %u triangles, key %s, archive %d %s, texture %d "
              "\"%s\", %s path, colours %s with gsa1_vertexcolor 0, %.2f..%.2f HU above the floor", kind_name(k), shadows,
              c->shadow_draws, sb ? sb->pass : 9, sb ? sb->triangles : 0, sb ? sb->key.c_str() : "-", sb ? sb->archive : -9,
              aname.c_str(), sb ? sb->texture : -9, tname.c_str(), sb && (sb->wrap & WRAP_MASK) ? "mask" : "ordinary",
              cols.c_str(), zmin - Z, zmax - Z);
        // camera-relative positions: the character's drawn root as the origin
        std::vector<std::vector<float>> abs_pos;
        for (uint32_t b = 0; b < c->batch_count; b++) abs_pos.push_back(c->batches[b].pos);
        ViewOptions r = o;
        r.relative = true;
        std::memcpy(r.origin, c->r_pos, sizeof r.origin);
        s.prepare_view(*c, eye, right, up, r);
        double far_rel = 0.0, far_abs = 0.0, worst = 0.0;
        for (uint32_t b = 0; b < c->batch_count; b++) {
            const std::vector<float> &a = abs_pos[b], &p = c->batches[b].pos;
            bool lines = (c->batches[b].prims & (1u << SA1_PRIM_LINES)) != 0;   // E-102's targeting reaches far
            for (size_t i = 0; i < p.size() && i < a.size(); i++) {
                worst = std::max(worst, std::fabs((double)p[i] + (double)r.origin[i % 3] - (double)a[i]));
                if (!lines) far_rel = std::max(far_rel, std::fabs((double)p[i]));
                far_abs = std::max(far_abs, std::fabs((double)a[i]));
            }
        }
        CHECK(far_rel < 400.0 && far_abs > 10000.0 && worst < 0.01,
              "%s: PrepareView relative to the drawn root: positions within %.0f HU of 0 (absolute up to %.0f HU); "
              "relative + origin = absolute within %.4f HU", kind_name(k), far_rel, far_abs, worst);
        s.destroy(id);
    }
    s.shutdown();
}

// lit see-through batches of real characters: Tails, Amy, E-102 (sadc docs/research/gsa1_070_translucency.md T2.1)
static void test_alpha_batches(const std::string &gdi)
{
    std::printf("lit see-through batches of Tails, Amy and E-102 (each pair at render alpha 1 and 0.5):\n");
    Session s;
    std::string err;
    if (!s.init(gdi, err)) {
        CHECK(false, "init: %s", err.c_str());
        return;
    }
    std::vector<sa1_collision_tri> floor;
    for (int i = -8; i < 8; i++) {
        for (int j = -8; j < 8; j++) {
            float x0 = 512.0f * i, y0 = 512.0f * j, x1 = x0 + 512.0f, y1 = y0 + 512.0f;
            sa1_collision_tri a = {{{x0, y0, 0}, {x1, y0, 0}, {x1, y1, 0}}, SA1_SURFACE_SOLID};
            sa1_collision_tri b = {{{x0, y0, 0}, {x1, y1, 0}, {x0, y1, 0}}, SA1_SURFACE_SOLID};
            floor.push_back(a);
            floor.push_back(b);
        }
    }
    if (!s.set_world(floor, err)) {
        CHECK(false, "set_world: %s", err.c_str());
        return;
    }
    struct Case {
        int32_t kind;
        const char *script;   // per pair: n neutral, f forward, a action, j jump
        std::vector<int> want;
    };
    const Case cases[] = {
        {SA1_CHAR_TAILS, "10n20f4j10n", {170, 85}},
        {SA1_CHAR_AMY, "10n1a20n", {51}},
        {SA1_CHAR_GAMMA, "10n40f", {216}},
    };
    for (const Case &cs : cases) {
        size_t n = 0;
        const UpgradeDef *tab = upgrade_table(n);
        std::vector<const UpgradeDef *> ups;
        for (size_t i = 0; i < n; i++) {
            if (tab[i].kind == cs.kind) ups.push_back(&tab[i]);
        }
        const float pos[3] = {0.0f, 0.0f, 8.0f};
        int32_t id = s.create(cs.kind, pos, 0.0f, err, nullptr, &ups);
        if (id <= 0) {
            CHECK(false, "%s: create: %s", kind_name(cs.kind), err.c_str());
            continue;
        }
        std::map<std::string, std::set<int>> key_alphas;
        std::set<int> alphas;
        uint32_t lit = 0, mixed = 0, wrong_field = 0, wrong_key = 0, pairs = 0;
        std::string example;
        std::string script;
        for (const char *p = cs.script; *p;) {
            int cnt = 0;
            while (*p >= '0' && *p <= '9') cnt = cnt * 10 + (*p++ - '0');
            char cmd = *p ? *p++ : 'n';
            script.append((size_t)std::max(cnt, 1), cmd);
        }
        for (char cmd : script) {
            float sy = cmd == 'f' ? 1.0f : 0.0f;
            uint32_t buttons = cmd == 'a' ? SA1_BUTTON_ACTION : cmd == 'j' ? SA1_BUTTON_JUMP : 0u;
            s.tick(id, 0.0f, sy, 0.0f, buttons, 1.0f / 30.0f);
            pairs++;
            for (float ra : {1.0f, 0.5f}) {
                if (s.render(id, ra) != SA1_OK) continue;
                Character *c = s.get(id);
                const float eye[3] = {c->r_pos[0] - 150.0f, c->r_pos[1], c->r_pos[2] + 40.0f}, right[3] = {0, -1, 0},
                            up[3] = {0, 0, 1};
                s.prepare_view(*c, eye, right, up, ViewOptions());
                for (uint32_t b = 0; b < c->batch_count; b++) {
                    const RenderBatch &rb = c->batches[b];
                    if (rb.pass != 1 || (rb.flags & SA1_DRAW_UNLIT) || (rb.wrap & WRAP_MASK) || rb.col.size() < 4) continue;
                    lit++;
                    // the written vertex alphas (the filler vertices of an incomplete batch are (0, 0, 0, 0): none here)
                    int lo = 255, hi = 0;
                    for (size_t v = 3; v < rb.col.size(); v += 4) {
                        lo = std::min(lo, (int)rb.col[v]);
                        hi = std::max(hi, (int)rb.col[v]);
                    }
                    if (lo != hi) {
                        mixed++;
                        if (example.empty()) example = format("%s holds alphas %d..%d", rb.key.c_str(), lo, hi);
                    }
                    if (rb.alpha != lo) wrong_field++;
                    size_t at = rb.key.rfind(".a");
                    int suffix = at != std::string::npos ? std::atoi(rb.key.c_str() + at + 2) : 255;
                    if (suffix != rb.alpha) wrong_key++;
                    key_alphas[rb.key].insert(lo);
                    if (lo < 255) alphas.insert(lo);
                }
            }
        }
        uint32_t shared = 0;
        for (const auto &kv : key_alphas) shared += kv.second.size() > 1;
        bool want = true;
        for (int a : cs.want) want = want && alphas.count(a) != 0;
        std::string seen;
        for (int a : alphas) seen += format("%s%d", seen.empty() ? "" : " ", a);
        bool amy76 = cs.kind != SA1_CHAR_AMY || alphas.count(76) || alphas.count(77);
        CHECK(lit > 0 && mixed == 0 && wrong_field == 0 && wrong_key == 0 && shared == 0 && want && amy76,
              "%s (%u pairs): %u lit blended batches; alphas below 255: %s; one alpha per batch (%u mixed%s%s), "
              "RenderBatch::alpha and the key's suffix right (%u / %u wrong), %u keys standing for two alphas",
              kind_name(cs.kind), pairs, lit, seen.empty() ? "none" : seen.c_str(), mixed, example.empty() ? "" : ": ",
              example.c_str(), wrong_field, wrong_key, shared);
        s.destroy(id);
    }
    s.shutdown();
}

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::printf("G-SA1 feat_render_test\n");
    test_view_rules();
    test_depth_precision();
    test_alpha_rules();
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the shadow and see-through batch checks need the disc\n");
    } else {
        test_shadows(gdi);
        test_alpha_batches(gdi);
    }
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
