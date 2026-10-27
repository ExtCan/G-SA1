// G-SA1 module: the render feature "render" (0.8; sadc docs/research/gsa1_060_render.md 4.5 item 2 and its review R7.3,
// gsa1_060_shadow.md G1 with its review). What the addon's renderer (cl_render.lua) checks with GSA1.HasFeature("render"):
//
//   * camera-relative drawing: gsa1.PrepareView's 12th argument, origin (a Vector), makes EmitBatch write every position
//     minus origin (Session::prepare_view, subtracted in double before the float conversion); the addon draws the
//     batches under a view whose eye is EyePos() - origin. Far from the map's centre (the owner's gm_bigcity run at
//     x ~ 5400, y ~ 3900-11750) the GPU's float32 transform of absolute positions put Big's eye layers behind the face at
//     the pair frames, with Big standing still (review R3.1). The built-in function takes the argument; this feature only
//     says that the module does.
//   * the blob shadow: SA1_DRAW_SHADOW batches (gsa1.DRAW_SHADOW) with their own batch key, and the mask path for a
//     shadow texture that is black in every texel (the batch's wrap has WRAP_MASK = 8: its vertex colours are
//     (a, a, a, 255); src/core/session.hpp).
//
// Lua API (feature version 1):
//   gsa1.DrawList(id, out) -> count | nil, message
//       One frame's draw list as libsa1 returned it (the last gsa1.Render) for the session log's gsa1_logdraws (the Tails
//       report "the motion-blur tails don't disappear when spinning", gsa1_060_render.md 4.5: what was drawn, in which
//       pass, with which texture and alpha). out = { count =, gen = (sa1_render.generation), alpha =, [i] = {
//         order (the game's draw order), prim (0 triangles, 1 sprites, 2 lines), source (SA1_SOURCE_*), flags (SA1_DRAW_*),
//         archive, tex, texname (the texture's name on the disc, "" untextured), aname (the archive's name), mat (the
//         Ninja attribute word), src, dst (SA1_BLEND_*), first, n (primitives), amin, amax (the vertex / sprite / line
//         colours' alpha range, 0..255), diffuse (0xRRGGBBAA, the material's, informational), batch (1-based gsa1.Batches
//         index the draw went into, 0: left out - an empty range or more triangles than one batch takes), pass (the
//         batch's: 0 opaque, 1 blended; -1 left out) } }. Entries past count are left as they were (read out.count).
//       nil, message: no such character / no render yet. Model addresses are not in libsa1's sa1_draw (UNVERIFIED which
//       model a draw is; texture, flags and order identify the Tails cases).
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/session.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;

namespace {

// the colours' alpha range of draw d (0..255; 255 / 0 when it has no colours)
void alpha_range(const gsa1::Character &c, const sa1_draw &d, int &amin, int &amax)
{
    amin = 255;
    amax = 0;
    if (d.prim == SA1_PRIM_TRIANGLES) {
        uint32_t end = std::min(d.first + d.count, c.r_triangles);
        for (uint32_t t = d.first; t < end; t++) {
            for (int k = 0; k < 3; k++) {
                int a = c.r_tcol[(size_t)t * 12u + (size_t)k * 4u + 3u];
                amin = std::min(amin, a);
                amax = std::max(amax, a);
            }
        }
    } else if (d.prim == SA1_PRIM_SPRITES) {
        uint32_t end = std::min(d.first + d.count, (uint32_t)c.r_sprites.size());
        for (uint32_t s = d.first; s < end; s++) {
            int a = c.r_sprites[s].color[3];
            amin = std::min(amin, a);
            amax = std::max(amax, a);
        }
    } else if (d.prim == SA1_PRIM_LINES) {
        uint32_t end = std::min(d.first + d.count, (uint32_t)c.r_lines.size() / 2u);
        for (uint32_t s = d.first; s < end; s++) {
            for (int k = 0; k < 2; k++) {
                int a = c.r_lines[2u * s + (uint32_t)k].color[3];
                amin = std::min(amin, a);
                amax = std::max(amax, a);
            }
        }
    }
    if (amin > amax) {
        amin = amax = 0;
    }
}

}  // namespace

// gsa1.DrawList(id, out) -> count | nil, message
GSA1_FN(gsa1_render_DrawList)
{
    int32_t id;
    gsa1::Session *s = session();
    gsa1::Character *c = nullptr;
    if (!s || !arg_int(LUA, 1, id, 1, 2147483647.0) || !(c = s->get(id)) || !LUA->IsType(2, LT::Table)) {
        return push_nil_msg(LUA, "DrawList(id, out): a character and a table", "bad_argument");
    }
    if (!c->rendered) {
        return push_nil_msg(LUA, "the character has not been rendered yet", "not_rendered");
    }
    int t = absidx(LUA, 2);
    std::vector<int32_t> owner(c->r_draws.size(), 0);
    for (uint32_t b = 0; b < c->batch_count; b++) {
        for (uint32_t di : c->batches[b].draws) {
            if (di < owner.size()) {
                owner[di] = (int32_t)b + 1;
            }
        }
    }
    // texture and archive names (sa1_texture_get / sa1_texture_archive; a few per call)
    std::vector<std::pair<uint64_t, std::string>> names;
    auto name_of = [&](int32_t archive, int32_t tex) -> std::string {
        if (archive < 0 || !s->ctx()) {
            return std::string();
        }
        uint64_t key = ((uint64_t)(uint32_t)archive << 32) | (uint32_t)tex;
        for (const auto &e : names) {
            if (e.first == key) {
                return e.second;
            }
        }
        std::string nm;
        if (tex < 0) {
            uint32_t count = 0;
            std::string err;
            s->texture_count(c->kind, (uint32_t)archive, count, err, &nm);
        } else {
            sa1_texture_info ti;
            std::memset(&ti, 0, sizeof ti);
            ti.struct_size = sizeof ti;
            if (sa1_texture_get(s->ctx(), c->kind, (uint32_t)archive, (uint32_t)tex, &ti) == SA1_OK && ti.name) {
                nm = ti.name;
            }
        }
        names.emplace_back(key, nm);
        return nm;
    };
    raw_num(LUA, t, "count", (double)c->r_draws.size());
    raw_num(LUA, t, "gen", c->r_gen);
    raw_num(LUA, t, "alpha", c->r_alpha);
    for (size_t i = 0; i < c->r_draws.size(); i++) {
        const sa1_draw &d = c->r_draws[i];
        int et = raw_subtable_i(LUA, t, (int)i + 1);
        int amin = 0, amax = 0;
        alpha_range(*c, d, amin, amax);
        int32_t b = owner[i];
        raw_num(LUA, et, "order", d.order);
        raw_num(LUA, et, "prim", d.prim);
        raw_num(LUA, et, "source", d.source);
        raw_num(LUA, et, "flags", d.flags);
        raw_num(LUA, et, "archive", d.archive);
        raw_num(LUA, et, "tex", d.texture);
        raw_str(LUA, et, "texname", d.texture >= 0 ? name_of(d.archive, d.texture) : std::string());
        raw_str(LUA, et, "aname", name_of(d.archive, -1));
        raw_num(LUA, et, "mat", d.material);
        raw_num(LUA, et, "src", d.blend_src);
        raw_num(LUA, et, "dst", d.blend_dst);
        raw_num(LUA, et, "first", d.first);
        raw_num(LUA, et, "n", d.count);
        raw_num(LUA, et, "amin", amin);
        raw_num(LUA, et, "amax", amax);
        raw_num(LUA, et, "diffuse", (double)(((uint32_t)d.diffuse[0] << 24) | ((uint32_t)d.diffuse[1] << 16) |
                                             ((uint32_t)d.diffuse[2] << 8) | (uint32_t)d.diffuse[3]));
        raw_num(LUA, et, "batch", b);
        raw_num(LUA, et, "pass", b > 0 ? (double)c->batches[(size_t)b - 1].pass : -1.0);
        LUA->Pop();
    }
    LUA->PushNumber((double)c->r_draws.size());
    return 1;
}

static const gsa1::FeatureFn k_render_fns[] = {
    {"DrawList", gsa1_render_DrawList},
};

GSA1_FEATURE(render, 1, k_render_fns, nullptr, nullptr, gsa1::kCloseDefault);
