// G-SA1 module: the HUD feature "hud" (round 0.9.1; sadc docs/research/gsa1_070_hud.md F8 with its review R.5.7). The
// game's own HUD and the 2D draws of a character's world, as libsa1 captures them (libsa1.h "screen / HUD", API 0.4
// draft: sa1_character_screen, SA1_COPT_HUD_PARTS / CLOCK / E102_NO_TIME_LIMIT, sa1_character_set_time, the
// sa1_state_ex time fields). The addon's side is gsa1/feat/cl_hud.lua: it scales the 640 x 480 screen to Garry's Mod's,
// anchors each element to its corner and draws it in HUDPaint with the textures' render targets.
//
// Lua API (feature version 1; GSA1.HasFeature("hud")). Flat numbers, no tables on the hot path:
//   gsa1.HudSettings(id, parts, clock, e102_no_limit) -> true | nil, message[, code]
//       parts: the mask of gsa1.HUD.RINGS / LIVES / TIME / CHARACTER (0: no HUD pass, an empty screen); clock 1: the game
//       clock runs (the game's 8C08A5AE), 0: stopped (8C08A5B6); e102_no_limit 1: E-102's clock is held every step (no
//       time-up death; other characters ignore it), 0: the game's 3-minute rule. libsa1 applies them to a live world at
//       once (between ticks) and keeps them for a world built later (before its first step). Call it when one changes.
//   gsa1.HudSetTime(id, minutes, seconds, frames) -> true | nil, message[, code]
//       The world's time (the game's 8C08AB20; clamped 0..99, 0..59, 0..59). E-102: 00:00:00 is his time-up, it gives the
//       game's restart time 03:00:00. For a respawn: the old character's HudCounters, then this on the new one.
//   gsa1.HudCounters(id) -> minutes, seconds, frames, clock_running, score, rings, lives | nil
//       The character's sa1_state_ex after its last tick (clock_running: a boolean; frames 0..59, the HUD shows them as
//       hundredths x 1.6667).
//   gsa1.HudScreen(id, out [, force]) -> generation, changed | nil, message[, code]
//       The 2D draws of the character's last pair (sa1_character_screen; the game's 640 x 480 screen, +y down), copied
//       into the caller's table only when they changed (another generation or character, or force):
//         out.id, out.gen, out.w, out.h (640, 480), out.nd, out.ns, out.nv (counts),
//         out.d = { draws, gsa1.HUD.D (11) numbers each: prim (0 triangles, 1 sprites, 2 lines), first (0-based into the
//                   sprites or the vertices), count, archive, texture (the character's: gsa1.Texture(kind, texture,
//                   archive); -1 untextured), flags (SA1_DRAW_*), blend_src, blend_dst (SA1_BLEND_*), priority, part
//                   (gsa1.HUD.*), source (the drawing task's exec address, 0 for the HUD pass) },
//         out.s = { sprites, gsa1.HUD.S (15) numbers each: x0, y0, x1, y1 (the rectangle around the pivot, before the
//                   angle), px, py (the pivot), angle (radians, +x towards +y), u0, v0, u1, v1 (u0 v0 at x0 y0), r, g, b, a
//                   (0..255) },
//         out.v = { vertices, gsa1.HUD.V (8) numbers each: x, y, u, v, r, g, b, a }.
//       Entries past the counts are left as they were. The draws come in drawing order (opaque first, then blended,
//       each from the most negative priority up). Not interpolated: the game draws its HUD once per 1/30 s pair.
//   gsa1.HUD = { RINGS = 1, LIVES = 2, TIME = 4, CHARACTER = 8, ALL = 15, D = 11, S = 15, V = 8 }
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>

#include "GarrysMod/Lua/Interface.h"

#include "../core/session.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;

namespace {

const int kDrawStride = 11;
const int kSpriteStride = 15;
const int kVertexStride = 8;

// a ticking character of the session (not a puppet) by its Lua id
gsa1::Character *char_arg(ILuaBase *L, int i, int32_t &id)
{
    gsa1::Session *se = session();
    if (!se || !arg_int(L, i, id, 1, 2147483647.0)) {
        return nullptr;
    }
    gsa1::Character *c = se->get(id);
    return c && !c->puppet ? c : nullptr;
}

// the session's context when the disc is loaded (else pushes nil, message and sets ret)
sa1_context *ctx_or(ILuaBase *L, int &ret)
{
    gsa1::Session *se = session();
    if (!se || !se->ready() || !se->ctx()) {
        ret = push_nil_msg(L, "G-SA1 is not initialised", "not_ready");
        return nullptr;
    }
    return se->ctx();
}

int fail(ILuaBase *L, sa1_context *ctx, sa1_status st, const char *what)
{
    const char *e = ctx ? sa1_last_error(ctx) : nullptr;
    return push_nil_msg(L, scrubbed(std::string(what) + ": " + (e && *e ? e : sa1_status_string(st))),
                        sa1_status_string(st));
}

// t[k] (string key, rawget) when it is a table, else a new table stored there; returns its absolute index
int raw_subtable_s(ILuaBase *L, int t, const char *k)
{
    L->PushString(k);
    L->RawGet(t);
    if (!L->IsType(-1, LT::Table)) {
        L->Pop();
        L->CreateTable();
        L->PushString(k);
        L->Push(-2);
        L->RawSet(t);
    }
    return L->Top();
}

inline void set_i(ILuaBase *L, int t, int i, double v)
{
    L->PushNumber(i);
    L->PushNumber(v);
    L->RawSet(t);
}

}  // namespace

// gsa1.HudSettings(id, parts, clock, e102_no_limit) -> true | nil, message[, code]
GSA1_FN(gsa1_hud_HudSettings)
{
    int32_t id = 0, parts = 0, clock = 0, free_clock = 0;
    if (!char_arg(LUA, 1, id) || !arg_int(LUA, 2, parts, 0, (double)SA1_HUD_ALL) || !arg_int(LUA, 3, clock, 0, 1) ||
        !arg_int(LUA, 4, free_clock, 0, 1)) {
        return push_nil_msg(LUA, "HudSettings(id, parts 0..15, clock 0/1, e102_no_limit 0/1): a character of this "
                                 "session", "bad_argument");
    }
    int ret = 0;
    sa1_context *ctx = ctx_or(LUA, ret);
    if (!ctx) {
        return ret;
    }
    sa1_status st = sa1_character_set_option(ctx, id, SA1_COPT_HUD_PARTS, parts);
    if (st != SA1_OK) {
        return fail(LUA, ctx, st, "the HUD parts");
    }
    st = sa1_character_set_option(ctx, id, SA1_COPT_CLOCK, clock);
    if (st != SA1_OK) {
        return fail(LUA, ctx, st, "the game clock");
    }
    st = sa1_character_set_option(ctx, id, SA1_COPT_E102_NO_TIME_LIMIT, free_clock);
    if (st != SA1_OK) {
        return fail(LUA, ctx, st, "E-102's time limit");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.HudSetTime(id, minutes, seconds, frames) -> true | nil, message[, code]
GSA1_FN(gsa1_hud_HudSetTime)
{
    int32_t id = 0, m = 0, s = 0, f = 0;
    if (!char_arg(LUA, 1, id) || !arg_int(LUA, 2, m, 0, 99) || !arg_int(LUA, 3, s, 0, 59) || !arg_int(LUA, 4, f, 0, 59)) {
        return push_nil_msg(LUA, "HudSetTime(id, minutes 0..99, seconds 0..59, frames 0..59): a character of this "
                                 "session", "bad_argument");
    }
    int ret = 0;
    sa1_context *ctx = ctx_or(LUA, ret);
    if (!ctx) {
        return ret;
    }
    sa1_status st = sa1_character_set_time(ctx, id, m, s, f);
    if (st != SA1_OK) {
        return fail(LUA, ctx, st, "the time");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.HudCounters(id) -> minutes, seconds, frames, clock_running, score, rings, lives | nil
GSA1_FN(gsa1_hud_HudCounters)
{
    int32_t id = 0;
    gsa1::Character *c = char_arg(LUA, 1, id);
    if (!c) {
        LUA->PushNil();
        return 1;
    }
    const sa1_state_ex &s = c->st;
    LUA->PushNumber(s.time_minutes);
    LUA->PushNumber(s.time_seconds);
    LUA->PushNumber(s.time_frames);
    LUA->PushBool(s.clock_running != 0);
    LUA->PushNumber(s.score);
    LUA->PushNumber(s.rings);
    LUA->PushNumber(s.lives);
    return 7;
}

// gsa1.HudScreen(id, out [, force]) -> generation, changed | nil, message[, code]
GSA1_FN(gsa1_hud_HudScreen)
{
    int32_t id = 0;
    if (!char_arg(LUA, 1, id) || !LUA->IsType(2, LT::Table)) {
        return push_nil_msg(LUA, "HudScreen(id, out [, force]): a character of this session and a table", "bad_argument");
    }
    int ret = 0;
    sa1_context *ctx = ctx_or(LUA, ret);
    if (!ctx) {
        return ret;
    }
    const sa1_screen *scr = nullptr;
    sa1_status st = sa1_character_screen(ctx, id, &scr);
    if (st != SA1_OK || !scr) {
        return fail(LUA, ctx, st, "sa1_character_screen");
    }
    int t = absidx(LUA, 2);
    bool force = LUA->IsType(3, LT::Bool) && LUA->GetBool(3);
    double old_id = -1.0, old_gen = -1.0;
    if (!force && raw_get_number(LUA, t, "id", old_id) && raw_get_number(LUA, t, "gen", old_gen) && old_id == id &&
        old_gen == (double)scr->generation) {
        LUA->PushNumber(scr->generation);
        LUA->PushBool(false);
        return 2;
    }
    uint32_t nd = scr->draws ? scr->num_draws : 0u;
    uint32_t ns = scr->sprites ? scr->num_sprites : 0u;
    uint32_t nv = scr->vertices ? scr->num_vertices : 0u;
    raw_num(LUA, t, "id", id);
    raw_num(LUA, t, "gen", scr->generation);
    raw_num(LUA, t, "w", scr->width);
    raw_num(LUA, t, "h", scr->height);
    raw_num(LUA, t, "nd", nd);
    raw_num(LUA, t, "ns", ns);
    raw_num(LUA, t, "nv", nv);
    int td = raw_subtable_s(LUA, t, "d");
    for (uint32_t i = 0; i < nd; i++) {
        const sa1_screen_draw &d = scr->draws[i];
        int k = (int)i * kDrawStride;
        set_i(LUA, td, k + 1, d.prim);
        set_i(LUA, td, k + 2, d.first);
        set_i(LUA, td, k + 3, d.count);
        set_i(LUA, td, k + 4, d.archive);
        set_i(LUA, td, k + 5, d.texture);
        set_i(LUA, td, k + 6, d.flags);
        set_i(LUA, td, k + 7, d.blend_src);
        set_i(LUA, td, k + 8, d.blend_dst);
        set_i(LUA, td, k + 9, std::isfinite(d.priority) ? d.priority : 0.0);
        set_i(LUA, td, k + 10, d.part);
        set_i(LUA, td, k + 11, d.source);
    }
    LUA->Pop();
    int ts = raw_subtable_s(LUA, t, "s");
    for (uint32_t i = 0; i < ns; i++) {
        const sa1_screen_sprite &s = scr->sprites[i];
        int k = (int)i * kSpriteStride;
        const float f[11] = {s.rect[0], s.rect[1], s.rect[2], s.rect[3], s.pivot[0], s.pivot[1], s.angle,
                             s.uv[0],   s.uv[1],   s.uv[2],   s.uv[3]};
        for (int j = 0; j < 11; j++) {
            set_i(LUA, ts, k + 1 + j, std::isfinite(f[j]) ? (double)f[j] : 0.0);
        }
        for (int j = 0; j < 4; j++) {
            set_i(LUA, ts, k + 12 + j, s.color[j]);
        }
    }
    LUA->Pop();
    int tv = raw_subtable_s(LUA, t, "v");
    for (uint32_t i = 0; i < nv; i++) {
        const sa1_screen_vertex &v = scr->vertices[i];
        int k = (int)i * kVertexStride;
        const float f[4] = {v.x, v.y, v.u, v.v};
        for (int j = 0; j < 4; j++) {
            set_i(LUA, tv, k + 1 + j, std::isfinite(f[j]) ? (double)f[j] : 0.0);
        }
        for (int j = 0; j < 4; j++) {
            set_i(LUA, tv, k + 5 + j, v.color[j]);
        }
    }
    LUA->Pop();
    LUA->PushNumber(scr->generation);
    LUA->PushBool(true);
    return 2;
}

namespace {

// gsa1.HUD: the parts and the strides of HudScreen's flat arrays
void hud_open(ILuaBase *L, int g)
{
    L->PushString("HUD");
    L->CreateTable();
    int t = L->Top();
    raw_num(L, t, "RINGS", SA1_HUD_RINGS);
    raw_num(L, t, "LIVES", SA1_HUD_LIVES);
    raw_num(L, t, "TIME", SA1_HUD_TIME);
    raw_num(L, t, "CHARACTER", SA1_HUD_CHARACTER);
    raw_num(L, t, "ALL", SA1_HUD_ALL);
    raw_num(L, t, "D", kDrawStride);
    raw_num(L, t, "S", kSpriteStride);
    raw_num(L, t, "V", kVertexStride);
    L->RawSet(g);
}

}  // namespace

static const gsa1::FeatureFn k_hud_fns[] = {
    {"HudSettings", gsa1_hud_HudSettings},
    {"HudSetTime", gsa1_hud_HudSetTime},
    {"HudCounters", gsa1_hud_HudCounters},
    {"HudScreen", gsa1_hud_HudScreen},
};

GSA1_FEATURE(hud, 1, k_hud_fns, hud_open, nullptr, gsa1::kCloseDefault);
