// G-SA1 module: the interaction feature "interact" (round 5: sadc docs/libsa1_interaction.md section 3 and its
// addendum, section 6; plan gsa1_rounds_plan.md 9.3 with the owner's additions - pushing props, the interact button, the
// ring HUD). libsa1's host objects (API 0.3) through src/core/interact.*; the addon's side is gsa1/feat/*_interact.lua
// and feat/cl_hud.lua.
//
// Lua API (feature version 1; GSA1.HasFeature("interact")). Hammer units, degrees; flat numbers on the hot path:
//   gsa1.ObjAdd(ent, kind, flags, x, y, z, yaw, armor, touch, cooldown, nshapes,
//               form, cx, cy, cz, sx, sy, sz, syaw, sflags,   (once per shape)
//               [launch_speed, grab_reach]) -> id, added | nil, message
//       Registers the GMod entity `ent` (its index: every event names it) as a host object, or replaces its
//       description when it changed (an unchanged description is not sent again). kind: gsa1.INTERACT.ENEMY ..
//       BALLOON; flags: gsa1.INTERACT.SOLID ...; armor / touch -1 = the kind's default; cooldown 0 = 20 steps; shapes:
//       form SPHERE (sx radius) / CYLINDER (sx radius, sy half height) / BOX (sx sy sz half extents, syaw), centre (cx
//       cy cz) offset from the position, not turned; sizes clamped to 16..4000 HU; a HOLDABLE's body to 128 HU.
//   gsa1.ObjUpdate(...)                     the same as ObjAdd
//   gsa1.ObjMove(ent, x, y, z, yaw) -> true | false, message      (once per game pair is enough: libsa1 interpolates)
//   gsa1.ObjRemove(ent [, killed]) -> bool (killed: E-102's time bonus and the marker's release, as a kill)
//   gsa1.ObjClear() -> removed
//   gsa1.ObjEvents([out]) -> out: { count, [i] = {character, type, ent, object, attack, level, damage, shape, flags,
//       x, y, z (the attacking shape), dx, dy, dz, speed (HU/s), step, reason, target (the aimed throw's entity, 0)} }
//       (the event tables are reused; read out.count)
//   gsa1.ObjConfig(window [, enter, leave]) -> true | nil, message     (proxies per world 1..64, radii in HU, 0 = default)
//   gsa1.ObjHeld(id) -> ent, phase, x, y, z, px, py, pz, yaw, hx, hy, hz | nil   (what character `id` holds: the prop's
//       position after the last step and the step before (interpolate with the character's alpha), the holder's yaw,
//       the hand anchor; phase gsa1.INTERACT.HOLD_LIFTING / CARRYING / THROWING)
//       0.9.3a (sadc docs/research/super_general_design.md 4.12 / 6.7, D13; libsa1 SA1_API_SUPER_GENERAL): then also
//       dx, dy, dz, dpx, dpy, dpz, dyaw, dpyaw - the prop at the DRAWN steps of the last pair and of the pair before
//       (sa1_hostobj_held.drawn / drawn_prev, yaws in degrees): the body is drawn between those two, so the addon
//       interpolates these with the character's render alpha (no 30 Hz sawtooth). Absent with an older libsa1.
//   gsa1.ObjRelease(ent) -> true | nil, message                     (the holder drops it: its own drop function)
//   gsa1.ObjWorldMask(id, mask) -> true | nil, message              (followers: which kinds the world mirrors)
//   gsa1.ObjInfo([id]) -> {registered, objects, proxies, created, destroyed, refused, events_dropped, heap_free,
//       heap_largest, generation, adds, updates, unchanged, moves, moves_skipped, removes, failures, error}
//   gsa1.Damage(id, flags, sx, sy, sz [, ent]) -> true | nil, message   (FACE_SOURCE / KILL; ent: the credited object)
//   gsa1.SetCharOption(id, option, value) -> true | nil, message    (NO_DEATH, KEEP_RINGS, NO_DAMAGE)
//   gsa1.AddRings(id, n) -> true | nil, message                     (the game's own ring counter: the 1-up at 100)
//   gsa1.StateEx(id [, out]) -> out | nil: {rings, lives, score, invuln (steps), hurt_steps (-1: never), held (the held
//       entity, 0), held_object, game_flags, player_flags, ball (the jump / roll ball), mode, smode, item, equipment,
//       dead (item 0x4000), forward (the game's forward speed, HU/s), kind}
//   gsa1.Contacts(id [, out]) -> out: { count, [i] = {ent, steps, side, landing, head, riding, wall, first, type, nx, ny,
//       nz, px, py, pz, vx, vy, vz, vin, vout, depth} }: the character's contacts with the moving objects (physics
//       props, doors ...) since the last call, one entry per entity (src/core/interact.hpp summarize); the owner's
//       pushing props (addition A)
//   gsa1.INTERACT = { kinds, flags, events, attacks, release reasons, hold phases, options, damage flags, contact types }
#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/interact.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;
namespace gi = gsa1::interact;

namespace {

gi::Registry g_reg;

const double kRad2Deg = 180.0 / 3.14159265358979323846;

// the session's context when the disc is loaded (the registry follows it), else nullptr
sa1_context *ready_ctx()
{
    gsa1::Session *se = session();
    sa1_context *c = se && se->ready() ? se->ctx() : nullptr;
    g_reg.bind(c);
    return c;
}

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

bool arg_u32(ILuaBase *L, int i, uint32_t &out, double hi)
{
    int32_t v = 0;
    if (!arg_int(L, i, v, 0, hi)) {
        return false;
    }
    out = (uint32_t)v;
    return true;
}

bool arg_f(ILuaBase *L, int i, float &out)
{
    double d = 0;
    if (!arg_number(L, i, d) || std::fabs(d) > 1.0e9) {
        return false;
    }
    out = (float)d;
    return true;
}

// ObjAdd / ObjUpdate's arguments
bool read_obj(ILuaBase *L, gi::ObjArgs &a, std::string &err)
{
    int32_t ent = 0, armor = -1, touch = -1;
    uint32_t nshapes = 0;
    if (!arg_int(L, 1, ent, 1, (double)gi::kMaxEnt) || !arg_u32(L, 2, a.kind, 64) || !arg_u32(L, 3, a.flags, 0xFFFF) ||
        !arg_f(L, 4, a.pos[0]) || !arg_f(L, 5, a.pos[1]) || !arg_f(L, 6, a.pos[2]) || !arg_f(L, 7, a.yaw_deg) ||
        !arg_int(L, 8, armor, -1, 3) || !arg_int(L, 9, touch, -1, 3) || !arg_u32(L, 10, a.cooldown, 3600) ||
        !arg_u32(L, 11, nshapes, gi::kMaxShapes) || nshapes < 1) {
        err = "ObjAdd(ent, kind, flags, x, y, z, yaw, armor, touch, cooldown, nshapes, {form, cx, cy, cz, sx, sy, sz, "
              "syaw, sflags} x nshapes [, launch_speed, grab_reach])";
        return false;
    }
    a.ent = ent;
    a.armor = armor;
    a.touch = touch;
    a.nshapes = nshapes;
    int k = 12;
    for (uint32_t i = 0; i < nshapes; i++, k += 9) {
        gi::ShapeArgs &s = a.shapes[i];
        if (!arg_u32(L, k, s.form, 16) || !arg_f(L, k + 1, s.center[0]) || !arg_f(L, k + 2, s.center[1]) ||
            !arg_f(L, k + 3, s.center[2]) || !arg_f(L, k + 4, s.size[0]) || !arg_f(L, k + 5, s.size[1]) ||
            !arg_f(L, k + 6, s.size[2]) || !arg_f(L, k + 7, s.yaw_deg) || !arg_u32(L, k + 8, s.flags, 0xFF)) {
            err = gsa1::format("ObjAdd: shape %u: form, cx, cy, cz, sx, sy, sz, syaw, sflags (numbers)", (unsigned)i + 1);
            return false;
        }
    }
    if (!L->IsType(k, LT::Nil) && !L->IsType(k, LT::None) && !arg_f(L, k, a.launch_speed)) {
        err = "ObjAdd: launch_speed (HU/s) must be a number";
        return false;
    }
    if (!L->IsType(k + 1, LT::Nil) && !L->IsType(k + 1, LT::None) && !arg_f(L, k + 1, a.grab_reach)) {
        err = "ObjAdd: grab_reach (HU) must be a number";
        return false;
    }
    return true;
}

int obj_add(ILuaBase *L)
{
    gi::ObjArgs a;
    std::string err;
    if (!read_obj(L, a, err)) {
        return push_nil_msg(L, err);
    }
    int ret = 0;
    if (!ready_or(L, ret)) {
        return ret;
    }
    sa1_context *ctx = ready_ctx();
    uint32_t id = 0;
    bool added = false;
    sa1_status st = g_reg.set(ctx, a, id, &added, err);
    if (st != SA1_OK) {
        return push_nil_msg(L, scrubbed(err), sa1_status_string(st));
    }
    L->PushNumber(id);
    L->PushBool(added);
    return 2;
}

const char *const kDamageUsage = "Damage(id, flags, sx, sy, sz [, ent])";

}  // namespace

GSA1_FN(gsa1_interact_ObjAdd)
{
    return obj_add(LUA);
}

GSA1_FN(gsa1_interact_ObjUpdate)
{
    return obj_add(LUA);
}

// gsa1.ObjMove(ent, x, y, z, yaw) -> true | false, message
GSA1_FN(gsa1_interact_ObjMove)
{
    int32_t ent = 0;
    float p[3], yaw;
    if (!arg_int(LUA, 1, ent, 1, (double)gi::kMaxEnt) || !arg_f(LUA, 2, p[0]) || !arg_f(LUA, 3, p[1]) ||
        !arg_f(LUA, 4, p[2]) || !arg_f(LUA, 5, yaw)) {
        return push_false_msg(LUA, "ObjMove(ent, x, y, z, yaw)");
    }
    sa1_context *ctx = ready_ctx();
    sa1_status st = g_reg.move(ctx, ent, p, yaw);
    if (st != SA1_OK) {
        return push_false_msg(LUA, st == SA1_ERR_NOT_FOUND ? "the entity is not registered" : "ObjMove: bad position",
                              sa1_status_string(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.ObjRemove(ent [, killed]) -> bool
GSA1_FN(gsa1_interact_ObjRemove)
{
    int32_t ent = 0;
    if (!arg_int(LUA, 1, ent, 1, (double)gi::kMaxEnt)) {
        LUA->PushBool(false);
        return 1;
    }
    bool killed = LUA->IsType(2, LT::Bool) && LUA->GetBool(2);
    LUA->PushBool(g_reg.remove(ready_ctx(), ent, killed));
    return 1;
}

// gsa1.ObjClear() -> removed
GSA1_FN(gsa1_interact_ObjClear)
{
    LUA->PushNumber((double)g_reg.clear(ready_ctx()));
    return 1;
}

// gsa1.ObjEvents([out]) -> out
GSA1_FN(gsa1_interact_ObjEvents)
{
    int t = out_table(LUA, 1);
    sa1_context *ctx = ready_ctx();
    int n = 0;
    if (ctx) {
        sa1_hostobj_event buf[64];
        for (int round = 0; round < 32; round++) {
            uint32_t got = 0;
            if (sa1_poll_hostobj_events(ctx, buf, 64, &got) != SA1_OK || got == 0) {
                break;
            }
            for (uint32_t i = 0; i < got; i++) {
                const sa1_hostobj_event &e = buf[i];
                int et = raw_subtable_i(LUA, t, ++n);
                int32_t target_ent = 0;
                if (e.target) {
                    g_reg.ent_of(e.target, target_ent);
                }
                raw_num(LUA, et, "character", e.character);
                raw_num(LUA, et, "type", e.type);
                raw_num(LUA, et, "ent", (double)e.user);
                raw_num(LUA, et, "object", e.object);
                raw_num(LUA, et, "attack", e.attack);
                raw_num(LUA, et, "level", e.level);
                raw_num(LUA, et, "damage", e.damage);
                raw_num(LUA, et, "shape", e.shape);
                raw_num(LUA, et, "flags", e.flags);
                raw_num(LUA, et, "x", e.position[0]);
                raw_num(LUA, et, "y", e.position[1]);
                raw_num(LUA, et, "z", e.position[2]);
                raw_num(LUA, et, "dx", e.direction[0]);
                raw_num(LUA, et, "dy", e.direction[1]);
                raw_num(LUA, et, "dz", e.direction[2]);
                raw_num(LUA, et, "speed", e.speed);
                raw_num(LUA, et, "step", e.step);
                raw_num(LUA, et, "reason", e.reason);
                raw_num(LUA, et, "target", target_ent);
                LUA->Pop(1);
            }
            if (got < 64) {
                break;
            }
        }
    }
    raw_num(LUA, t, "count", n);
    LUA->PushNumber(n + 1);   // ipairs stops after this call's events
    LUA->PushNil();
    LUA->RawSet(t);
    return 1;
}

// gsa1.ObjConfig(window [, enter, leave]) -> true | nil, message
GSA1_FN(gsa1_interact_ObjConfig)
{
    int32_t window = 0;
    double enter = 0, leave = 0;
    if (!arg_int(LUA, 1, window, 0, SA1_HOSTOBJ_MAX_WINDOW) ||
        (!LUA->IsType(2, LT::Nil) && !LUA->IsType(2, LT::None) && (!arg_number(LUA, 2, enter) || enter < 0 || enter > 1e6)) ||
        (!LUA->IsType(3, LT::Nil) && !LUA->IsType(3, LT::None) && (!arg_number(LUA, 3, leave) || leave < 0 || leave > 1e6))) {
        return push_nil_msg(LUA, "ObjConfig(window 0..64 [, enter, leave (HU, 0 = default)])");
    }
    int ret = 0;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    sa1_hostobj_config c;
    std::memset(&c, 0, sizeof c);
    c.struct_size = sizeof c;
    c.window = (uint32_t)window;
    c.enter_radius = (float)enter;
    c.leave_radius = (float)std::max(leave, enter);
    if (leave == 0 && enter == 0) {
        c.leave_radius = 0.0f;
    }
    sa1_context *ctx = ready_ctx();
    sa1_status st = sa1_hostobj_configure(ctx, &c);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, scrubbed(sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_hostobj_configure"),
                            sa1_status_string(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.ObjHeld(id) -> ent, phase, x, y, z, px, py, pz, yaw, hx, hy, hz | nil
GSA1_FN(gsa1_interact_ObjHeld)
{
    int32_t id = 0;
    sa1_context *ctx = ready_ctx();
    if (!ctx || !char_arg(LUA, 1, id)) {
        LUA->PushNil();
        return 1;
    }
    sa1_hostobj_held h;
    std::memset(&h, 0, sizeof h);
    h.struct_size = sizeof h;
    if (sa1_character_held(ctx, id, &h) != SA1_OK || h.object == 0) {
        LUA->PushNil();
        return 1;
    }
    int32_t ent = 0;
    g_reg.ent_of(h.object, ent);
    LUA->PushNumber(ent);
    LUA->PushNumber(h.phase);
    for (int k = 0; k < 3; k++) LUA->PushNumber(h.position[k]);
    for (int k = 0; k < 3; k++) LUA->PushNumber(h.position_prev[k]);
    LUA->PushNumber(h.yaw * kRad2Deg);
    for (int k = 0; k < 3; k++) LUA->PushNumber(h.hand[k]);
#if defined(SA1_API_SUPER_GENERAL)
    // 0.9.3a: the drawn steps (libsa1 fills them: struct_size covers the tail)
    for (int k = 0; k < 3; k++) LUA->PushNumber(h.drawn[k]);
    for (int k = 0; k < 3; k++) LUA->PushNumber(h.drawn_prev[k]);
    LUA->PushNumber(h.drawn_yaw * kRad2Deg);
    LUA->PushNumber(h.drawn_yaw_prev * kRad2Deg);
    return 20;
#else
    return 12;
#endif
}

// gsa1.ObjRelease(ent) -> true | nil, message
GSA1_FN(gsa1_interact_ObjRelease)
{
    int32_t ent = 0;
    uint32_t oid = 0;
    if (!arg_int(LUA, 1, ent, 1, (double)gi::kMaxEnt)) {
        return push_nil_msg(LUA, "ObjRelease(ent)");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx || !g_reg.id_of(ent, oid)) {
        return push_nil_msg(LUA, "the entity is not registered", "not_found");
    }
    sa1_status st = sa1_hostobj_release(ctx, oid);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, scrubbed(sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_hostobj_release"),
                            sa1_status_string(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.ObjWorldMask(id, mask) -> true | nil, message
GSA1_FN(gsa1_interact_ObjWorldMask)
{
    int32_t id = 0;
    uint32_t mask = 0;
    sa1_context *ctx = ready_ctx();
    if (!char_arg(LUA, 1, id) || !arg_u32(LUA, 2, mask, 0xFFFF)) {
        return push_nil_msg(LUA, "ObjWorldMask(id, mask)");
    }
    if (!ctx) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_status st = sa1_hostobj_world_mask(ctx, id, mask);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, scrubbed(sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_hostobj_world_mask"),
                            sa1_status_string(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.ObjInfo([id]) -> table
GSA1_FN(gsa1_interact_ObjInfo)
{
    int32_t id = 0;
    sa1_context *ctx = ready_ctx();
    bool with_char = LUA->IsType(1, LT::Number) && char_arg(LUA, 1, id);
    LUA->CreateTable();
    int t = LUA->Top();
    const gi::RegistryStats &rs = g_reg.stats();
    raw_num(LUA, t, "registered", (double)g_reg.size());
    raw_num(LUA, t, "generation", g_reg.generation());
    raw_num(LUA, t, "adds", (double)rs.adds);
    raw_num(LUA, t, "updates", (double)rs.updates);
    raw_num(LUA, t, "unchanged", (double)rs.unchanged);
    raw_num(LUA, t, "moves", (double)rs.moves);
    raw_num(LUA, t, "moves_skipped", (double)rs.moves_skipped);
    raw_num(LUA, t, "removes", (double)rs.removes);
    raw_num(LUA, t, "failures", (double)rs.failures);
    raw_str(LUA, t, "error", scrubbed(rs.last_error));
    if (ctx) {
        sa1_hostobj_info in;
        std::memset(&in, 0, sizeof in);
        in.struct_size = sizeof in;
        if (sa1_hostobj_info_get(ctx, with_char ? id : 0, &in) == SA1_OK) {
            raw_num(LUA, t, "objects", in.objects);
            raw_num(LUA, t, "proxies", in.proxies);
            raw_num(LUA, t, "created", in.created);
            raw_num(LUA, t, "destroyed", in.destroyed);
            raw_num(LUA, t, "refused", in.refused);
            raw_num(LUA, t, "events_dropped", in.events_dropped);
            raw_num(LUA, t, "heap_free", in.heap_free);
            raw_num(LUA, t, "heap_largest", in.heap_largest);
        }
    }
    return 1;
}

// gsa1.Damage(id, flags, sx, sy, sz [, ent]) -> true | nil, message
GSA1_FN(gsa1_interact_Damage)
{
    int32_t id = 0, ent = 0;
    uint32_t flags = 0;
    float src[3];
    if (!char_arg(LUA, 1, id) || !arg_u32(LUA, 2, flags, 0xFF) || !arg_f(LUA, 3, src[0]) || !arg_f(LUA, 4, src[1]) ||
        !arg_f(LUA, 5, src[2]) ||
        (!LUA->IsType(6, LT::Nil) && !LUA->IsType(6, LT::None) && !arg_int(LUA, 6, ent, 0, (double)gi::kMaxEnt))) {
        return push_nil_msg(LUA, kDamageUsage);
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_damage d;
    std::memset(&d, 0, sizeof d);
    d.struct_size = sizeof d;
    d.flags = flags;
    std::memcpy(d.source, src, sizeof d.source);
    uint32_t oid = 0;
    if (ent > 0 && g_reg.id_of(ent, oid)) {
        d.object = oid;
    }
    sa1_status st = sa1_character_damage(ctx, id, &d);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, scrubbed(sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_character_damage"),
                            sa1_status_string(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.SetCharOption(id, option, value) -> true | nil, message
GSA1_FN(gsa1_interact_SetCharOption)
{
    int32_t id = 0, value = 0;
    uint32_t option = 0;
    if (!char_arg(LUA, 1, id) || !arg_u32(LUA, 2, option, 64) || !arg_int(LUA, 3, value, -1000000.0, 1000000.0)) {
        return push_nil_msg(LUA, "SetCharOption(id, option, value)");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_status st = sa1_character_set_option(ctx, id, option, value);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, scrubbed(sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_character_set_option"),
                            sa1_status_string(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.AddRings(id, n) -> true | nil, message
GSA1_FN(gsa1_interact_AddRings)
{
    int32_t id = 0, n = 0;
    if (!char_arg(LUA, 1, id) || !arg_int(LUA, 2, n, -1000.0, 1000.0)) {
        return push_nil_msg(LUA, "AddRings(id, n -1000..1000)");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_status st = sa1_character_add_rings(ctx, id, n);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, scrubbed(sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_character_add_rings"),
                            sa1_status_string(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.StateEx(id [, out]) -> out | nil
GSA1_FN(gsa1_interact_StateEx)
{
    int32_t id = 0;
    gsa1::Character *c = char_arg(LUA, 1, id);
    if (!c) {
        LUA->PushNil();
        return 1;
    }
    int t = out_table(LUA, 2);
    const sa1_state_ex &s = c->st;
    int32_t held = 0;
    if (s.held_object) {
        g_reg.ent_of(s.held_object, held);
    }
    raw_num(LUA, t, "rings", s.rings);
    raw_num(LUA, t, "lives", s.lives);
    raw_num(LUA, t, "score", s.score);
    raw_num(LUA, t, "invuln", s.invulnerable_steps);
    raw_num(LUA, t, "hurt_steps", s.hurt_steps == 0xFFFFFFFFu ? -1.0 : (double)s.hurt_steps);
    raw_num(LUA, t, "held", held);
    raw_num(LUA, t, "held_object", s.held_object);
    raw_num(LUA, t, "game_flags", s.game_flags);
    raw_num(LUA, t, "player_flags", s.player_flags);
    raw_bool(LUA, t, "ball", (s.game_flags & 0x100u) != 0);
    raw_num(LUA, t, "mode", s.mode);
    raw_num(LUA, t, "smode", s.smode);
    raw_num(LUA, t, "item", s.item);
    raw_num(LUA, t, "equipment", s.equipment & 0xFFFFu);
    raw_bool(LUA, t, "dead", (s.item & 0x4000u) != 0);
    // the game's forward speed (playerwk.spd.x, SA1 units per step) in HU/s (the Source preset's 4 HU per unit)
    raw_num(LUA, t, "forward", s.player_speed[0] * 4.0 * 60.0);
    raw_num(LUA, t, "kind", c->kind);
    return 1;
}

// gsa1.Contacts(id [, out]) -> out
GSA1_FN(gsa1_interact_Contacts)
{
    int32_t id = 0;
    gsa1::Character *c = char_arg(LUA, 1, id);
    int t = out_table(LUA, 2);
    sa1_context *ctx = ready_ctx();
    gsa1::Session *se = session();
    int n = 0;
    if (c && ctx && se) {
        std::vector<sa1_contact> all;
        sa1_contact buf[128];
        for (int round = 0; round < 8; round++) {
            uint32_t got = 0;
            if (sa1_character_contacts(ctx, id, buf, 128, &got) != SA1_OK || got == 0) {
                break;
            }
            all.insert(all.end(), buf, buf + got);
            if (got < 128) {
                break;
            }
        }
        const gsa1::Movers &mv = se->movers();
        std::vector<gi::ContactSum> sum = gi::summarize(
            all.data(), all.size(),
            [&mv](uint32_t obj, int32_t &ent, uint32_t &chunk) { return mv.entity_of(obj, ent, &chunk); });
        for (const gi::ContactSum &k : sum) {
            int et = raw_subtable_i(LUA, t, ++n);
            raw_num(LUA, et, "ent", k.ent);
            raw_num(LUA, et, "steps", k.steps);
            raw_num(LUA, et, "side", k.side);
            raw_num(LUA, et, "landing", k.landing);
            raw_num(LUA, et, "head", k.head);
            raw_num(LUA, et, "riding", k.riding);
            raw_num(LUA, et, "wall", k.wall);
            raw_num(LUA, et, "first", k.first);
            raw_num(LUA, et, "type", k.type);
            raw_num(LUA, et, "nx", k.normal[0]);
            raw_num(LUA, et, "ny", k.normal[1]);
            raw_num(LUA, et, "nz", k.normal[2]);
            raw_num(LUA, et, "px", k.point[0]);
            raw_num(LUA, et, "py", k.point[1]);
            raw_num(LUA, et, "pz", k.point[2]);
            raw_num(LUA, et, "vx", k.velocity[0]);
            raw_num(LUA, et, "vy", k.velocity[1]);
            raw_num(LUA, et, "vz", k.velocity[2]);
            raw_num(LUA, et, "vin", k.vin);
            raw_num(LUA, et, "vout", k.vout);
            raw_num(LUA, et, "depth", k.depth);
            LUA->Pop(1);
        }
    }
    raw_num(LUA, t, "count", n);
    LUA->PushNumber(n + 1);
    LUA->PushNil();
    LUA->RawSet(t);
    return 1;
}

namespace {

void put(ILuaBase *L, int t, const char *k, double v)
{
    raw_num(L, t, k, v);
}

// gsa1.INTERACT: libsa1's numbers (sh_interact.lua has the same table for the server, which has no module;
// feat_interact_binding_test compares the two)
void interact_open(ILuaBase *L, int t)
{
    L->PushString("INTERACT");
    L->CreateTable();
    int c = L->Top();
    put(L, c, "ENEMY", SA1_HOSTOBJ_ENEMY);
    put(L, c, "TARGET", SA1_HOSTOBJ_TARGET);
    put(L, c, "BREAKABLE", SA1_HOSTOBJ_BREAKABLE);
    put(L, c, "HAZARD", SA1_HOSTOBJ_HAZARD);
    put(L, c, "HOLDABLE", SA1_HOSTOBJ_HOLDABLE);
    put(L, c, "BALLOON", SA1_HOSTOBJ_BALLOON);
    put(L, c, "SOLID", SA1_HOSTOBJ_SOLID);
    put(L, c, "NOT_SOLID", SA1_HOSTOBJ_NOT_SOLID);
    put(L, c, "NO_HOMING", SA1_HOSTOBJ_NO_HOMING);
    put(L, c, "NO_LOCKON", SA1_HOSTOBJ_NO_LOCKON);
    put(L, c, "NO_BONUS", SA1_HOSTOBJ_NO_BONUS);
    put(L, c, "DISABLED", SA1_HOSTOBJ_DISABLED);
    put(L, c, "REPORT_TOUCH", SA1_HOSTOBJ_REPORT_TOUCH);
    put(L, c, "HOLD_HITS", SA1_HOSTOBJ_HOLD_HITS);
    put(L, c, "HOLD_LOCKED", SA1_HOSTOBJ_HOLD_LOCKED);
    put(L, c, "HEAVY", SA1_HOSTOBJ_HEAVY);
    put(L, c, "POP_ON_TOUCH", SA1_HOSTOBJ_POP_ON_TOUCH);
    put(L, c, "LAUNCH_BOUNCE", SA1_HOSTOBJ_LAUNCH_BOUNCE);
    put(L, c, "KEEP_HSPEED", SA1_HOSTOBJ_KEEP_HSPEED);
    put(L, c, "SPHERE", SA1_SHAPE_SPHERE);
    put(L, c, "CYLINDER", SA1_SHAPE_CYLINDER);
    put(L, c, "BOX", SA1_SHAPE_BOX);
    put(L, c, "SHAPE_NO_DAMAGE", SA1_HSHAPE_NO_DAMAGE);
    put(L, c, "SHAPE_NO_TOUCH", SA1_HSHAPE_NO_TOUCH);
    put(L, c, "SHAPE_OFF", SA1_HSHAPE_OFF);
    put(L, c, "EVENT_HIT", SA1_HOSTOBJ_EVENT_HIT);
    put(L, c, "EVENT_LOCKED", SA1_HOSTOBJ_EVENT_LOCKED);
    put(L, c, "EVENT_TARGETED", SA1_HOSTOBJ_EVENT_TARGETED);
    put(L, c, "EVENT_UNLOCKED", SA1_HOSTOBJ_EVENT_UNLOCKED);
    put(L, c, "EVENT_TOUCH", SA1_HOSTOBJ_EVENT_TOUCH);
    put(L, c, "EVENT_LIFTED", SA1_HOSTOBJ_EVENT_LIFTED);
    put(L, c, "EVENT_RELEASED", SA1_HOSTOBJ_EVENT_RELEASED);
    put(L, c, "HITF_BOUNCED", SA1_HITF_BOUNCED);
    put(L, c, "HITF_PROJECTILE", SA1_HITF_PROJECTILE);
    put(L, c, "HITF_LOCKED", SA1_HITF_LOCKED);
    put(L, c, "HITF_LAUNCHED", SA1_HITF_LAUNCHED);
    put(L, c, "RELEASE_THROW", SA1_RELEASE_THROW);
    put(L, c, "RELEASE_THROW_AIMED", SA1_RELEASE_THROW_AIMED);
    put(L, c, "RELEASE_PUT_DOWN", SA1_RELEASE_PUT_DOWN);
    put(L, c, "RELEASE_DROP", SA1_RELEASE_DROP);
    put(L, c, "RELEASE_FORCED", SA1_RELEASE_FORCED);
    put(L, c, "HOLD_NONE", SA1_HOLD_NONE);
    put(L, c, "HOLD_LIFTING", SA1_HOLD_LIFTING);
    put(L, c, "HOLD_CARRYING", SA1_HOLD_CARRYING);
    put(L, c, "HOLD_THROWING", SA1_HOLD_THROWING);
    put(L, c, "COPT_NO_DEATH", SA1_COPT_NO_DEATH);
    put(L, c, "COPT_KEEP_RINGS", SA1_COPT_KEEP_RINGS);
    put(L, c, "COPT_NO_DAMAGE", SA1_COPT_NO_DAMAGE);
    put(L, c, "DAMAGE_FACE_SOURCE", SA1_DAMAGE_FACE_SOURCE);
    put(L, c, "DAMAGE_KILL", SA1_DAMAGE_KILL);
    put(L, c, "CONTACT_SIDE", SA1_CONTACT_SIDE);
    put(L, c, "CONTACT_LANDING", SA1_CONTACT_LANDING);
    put(L, c, "CONTACT_HEAD", SA1_CONTACT_HEAD);
    put(L, c, "EVENT_HURT", SA1_EVENT_HURT);
    put(L, c, "MAX_WINDOW", SA1_HOSTOBJ_MAX_WINDOW);
    L->RawSet(t);
}

// the libsa1 context is going (gsa1.Shutdown, the module's close): its ids go with it
void interact_forget()
{
    g_reg.forget();
}

void interact_close(ILuaBase *)
{
    g_reg.forget();
}

}  // namespace

static const gsa1::FeatureFn k_interact_fns[] = {
    {"ObjAdd", gsa1_interact_ObjAdd},
    {"ObjUpdate", gsa1_interact_ObjUpdate},
    {"ObjMove", gsa1_interact_ObjMove},
    {"ObjRemove", gsa1_interact_ObjRemove},
    {"ObjClear", gsa1_interact_ObjClear},
    {"ObjEvents", gsa1_interact_ObjEvents},
    {"ObjConfig", gsa1_interact_ObjConfig},
    {"ObjHeld", gsa1_interact_ObjHeld},
    {"ObjRelease", gsa1_interact_ObjRelease},
    {"ObjWorldMask", gsa1_interact_ObjWorldMask},
    {"ObjInfo", gsa1_interact_ObjInfo},
    {"Damage", gsa1_interact_Damage},
    {"SetCharOption", gsa1_interact_SetCharOption},
    {"AddRings", gsa1_interact_AddRings},
    {"StateEx", gsa1_interact_StateEx},
    {"Contacts", gsa1_interact_Contacts},
};
// version 2 (0.9.3a): ObjHeld also returns the prop at the drawn steps (the carried-object jitter, design 6.7)
#if defined(SA1_API_SUPER_GENERAL)
GSA1_FEATURE(interact, 2, k_interact_fns, interact_open, interact_close, gsa1::kCloseDefault);
#else
GSA1_FEATURE(interact, 1, k_interact_fns, interact_open, interact_close, gsa1::kCloseDefault);
#endif
GSA1_FEATURE_ON_SHUTDOWN(interact, interact_forget);
