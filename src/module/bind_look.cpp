// G-SA1 module: the feature "look" (round 0.9.8: sadc docs/research/gsa1_098_plan.md 5.5, 6.8; gsa1_096_plan.md 4.20, 5.5, 6.6
// with its review R.12 / R.13; look096.md 7.2.1; libsa1.h "head look", SA1_API_LOOK). The game's own head and eye look: libsa1
// drives the look tasks of the world's character slot (the game's setters 8C07C318 / 8C07C34C / 8C07C376, the pad's Z bit for
// the camera look); no game state changes (look096.md 5.4). The addon's side is gsa1/feat/{sh,cl}_look.lua (the targets, the
// Head look page).
//
// Lua API (feature version 1; GSA1.HasFeature("look", 1); only with a libsa1 that has SA1_API_LOOK, else the feature is absent).
// Units: Hammer units, degrees, host axes. id: a ticking character of this client, a follower included (a follower's look is
// its world's slot 1). Calls run on the game's thread between ticks (decision 096 4.11 d: Lua never runs during a pool job, so a
// direct call is right and the session latches nothing). They never raise a Lua error.
//   gsa1.Look(id, kind [, a, b, c] [, flags]) -> true | false, message, code
//       kind gsa1.LOOK_OFF / LOOK_POINT (a, b, c = the point: x, y, z) / LOOK_ANGLES (a = yaw, b = pitch: degrees from the body,
//       + yaw = the character's left, + pitch = up) / LOOK_CAMERA; flags gsa1.LOOK_OVERRIDE_GAME (POINT and ANGLES: also over a
//       look the game set). The arguments stay in their places: flags is always argument 6. Latched in libsa1 until the next
//       call; cheap enough for every frame: numbers only, no table, no string unless it fails. Codes: "bad_argument" (a missing
//       or wrong argument, a kind that does not exist, a value above 1e30), "not_ready" (no disc), "not_found" (no such
//       character, a puppet), "unsupported" (libsa1's plain reason: E-102's game never makes a look task, replays, previews; the
//       text "the head look is not built yet" while libsa1's gate is closed), "fault" (the world faulted).
//   gsa1.LookState(id [, out]) -> out | nil, message, code
//       { kind (SA1_LOOK_* in force), owner (0: no event look, 1: the host's, 2: a look the game set), head_y, head_z, eye_y,
//       eye_z } in degrees (+ y = the character's left, + z = down), from the character's last sa1_state_ex: after its next
//       tick; 0 without a look task or a call. out is filled with raw sets and nothing is made when it is passed.
//   gsa1.LOOK_OFF = 0, gsa1.LOOK_POINT = 1, gsa1.LOOK_ANGLES = 2, gsa1.LOOK_CAMERA = 3, gsa1.LOOK_OVERRIDE_GAME = 1,
//   gsa1.COPT_SUPER_LOOK = 7 (the option goes through the existing gsa1.SetCharOption(id, option, value):
//   bind_interact.cpp passes any option number to sa1_character_set_option; kind 8 and super-capable Sonic worlds).
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>

#include "GarrysMod/Lua/Interface.h"

#include "../core/session.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

#if defined(SA1_API_LOOK)

using namespace gsa1::mod;
namespace LT = GarrysMod::Lua::Type;

namespace {

const char *look_code(sa1_status st)
{
    switch (st) {
    case SA1_ERR_UNSUPPORTED: return "unsupported";
    case SA1_ERR_NOT_FOUND: return "not_found";
    case SA1_ERR_NOT_LOADED: return "not_ready";
    case SA1_ERR_GAME_FAULT:
    case SA1_ERR_NOT_IMPLEMENTED: return "fault";
    case SA1_ERR_INVALID_ARGUMENT: return "bad_argument";
    default: return "error";
    }
}

bool arg_absent(ILuaBase *L, int i)
{
    int t = L->GetType(i);
    return t == LT::Nil || t == LT::None;
}

// a number libsa1 can take as a float
bool arg_coord(ILuaBase *L, int i, double &out)
{
    return arg_number(L, i, out) && std::fabs(out) <= 1e30;
}

// a ticking character of the session (not a puppet) by its Lua id, or nullptr with `false, message, code` pushed
gsa1::Character *look_char(ILuaBase *L, int32_t id, int &ret)
{
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        ret = push_false_msg(L, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
        return nullptr;
    }
    gsa1::Character *c = se->get(id);
    if (!c || c->puppet) {
        ret = push_false_msg(L, "no such character", "not_found");
        return nullptr;
    }
    return c;
}

double bams_deg(int32_t a)
{
    return (double)a * 360.0 / 65536.0;
}

}  // namespace

// gsa1.Look(id, kind [, a, b, c] [, flags]) -> true | false, message, code
GSA1_FN(gsa1_look_Look)
{
    int32_t id = 0, kind = 0, flags = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_int(LUA, 2, kind, 0, 1000000.0)) {
        return push_false_msg(LUA, "Look(id, kind [, a, b, c] [, flags])", "bad_argument");
    }
    if (!arg_absent(LUA, 6) && !arg_int(LUA, 6, flags, 0, 1000000.0)) {
        return push_false_msg(LUA, "Look: flags is a whole number (gsa1.LOOK_OVERRIDE_GAME)", "bad_argument");
    }
    sa1_look look;
    std::memset(&look, 0, sizeof look);
    look.struct_size = sizeof look;
    look.kind = (uint32_t)kind;
    look.flags = (uint32_t)flags;
    switch ((uint32_t)kind) {
    case SA1_LOOK_OFF:
    case SA1_LOOK_CAMERA:
        break;
    case SA1_LOOK_POINT: {
        double x, y, z;
        if (!arg_coord(LUA, 3, x) || !arg_coord(LUA, 4, y) || !arg_coord(LUA, 5, z)) {
            return push_false_msg(LUA, "Look(id, gsa1.LOOK_POINT, x, y, z [, flags])", "bad_argument");
        }
        look.point[0] = (float)x;
        look.point[1] = (float)y;
        look.point[2] = (float)z;
        break;
    }
    case SA1_LOOK_ANGLES: {
        double yaw, pitch;
        if (!arg_coord(LUA, 3, yaw) || !arg_coord(LUA, 4, pitch)) {
            return push_false_msg(LUA, "Look(id, gsa1.LOOK_ANGLES, yaw, pitch [, nil, flags]): degrees", "bad_argument");
        }
        look.yaw = deg2rad(yaw);
        look.pitch = deg2rad(pitch);
        break;
    }
    default:
        return push_false_msg(LUA, "Look: kind is gsa1.LOOK_OFF, LOOK_POINT, LOOK_ANGLES or LOOK_CAMERA", "bad_argument");
    }
    int ret = 0;
    if (!look_char(LUA, id, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    sa1_status st = sa1_character_look(se->ctx(), id, &look);
    if (SA1_FAILED(st)) {
        const char *e = sa1_last_error(se->ctx());
        return push_false_msg(LUA, scrubbed(e && *e ? e : sa1_status_string(st)), look_code(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.LookState(id [, out]) -> out | nil, message, code
GSA1_FN(gsa1_look_LookState)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0)) {
        return push_nil_msg(LUA, "LookState(id [, out])", "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
    }
    gsa1::Character *c = se->get(id);
    if (!c || c->puppet) {
        return push_nil_msg(LUA, "no such character", "not_found");
    }
    int t = out_table(LUA, 2);
    const sa1_state_ex &s = c->st;
    // a state libsa1 never filled (struct_size short of the look's tail): no look
    bool has = s.struct_size >= offsetof(sa1_state_ex, eye_angle) + sizeof s.eye_angle;
    raw_num(LUA, t, "kind", has ? (double)s.look_kind : 0.0);
    raw_num(LUA, t, "owner", has ? (double)s.look_owner : 0.0);
    raw_num(LUA, t, "head_y", has ? bams_deg(s.head_angle[0]) : 0.0);
    raw_num(LUA, t, "head_z", has ? bams_deg(s.head_angle[1]) : 0.0);
    raw_num(LUA, t, "eye_y", has ? bams_deg(s.eye_angle[0]) : 0.0);
    raw_num(LUA, t, "eye_z", has ? bams_deg(s.eye_angle[1]) : 0.0);
    return 1;
}

namespace {

void look_open(ILuaBase *L, int t)
{
    raw_num(L, t, "LOOK_OFF", SA1_LOOK_OFF);
    raw_num(L, t, "LOOK_POINT", SA1_LOOK_POINT);
    raw_num(L, t, "LOOK_ANGLES", SA1_LOOK_ANGLES);
    raw_num(L, t, "LOOK_CAMERA", SA1_LOOK_CAMERA);
    raw_num(L, t, "LOOK_OVERRIDE_GAME", SA1_LOOKF_OVERRIDE_GAME);
    raw_num(L, t, "COPT_SUPER_LOOK", SA1_COPT_SUPER_LOOK);
}

const gsa1::FeatureFn k_look_fns[] = {
    {"Look", gsa1_look_Look},
    {"LookState", gsa1_look_LookState},
};

}  // namespace

// version 1 (0.9.8): Look, LookState, the constants
GSA1_FEATURE(look, 1, k_look_fns, look_open, nullptr, gsa1::kCloseDefault);

#endif  // SA1_API_LOOK (a libsa1 without the head look: no feature "look"; GSA1.HasFeature("look") is false)
