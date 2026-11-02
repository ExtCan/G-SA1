// G-SA1 module: the feature "gamecam" (round 0.9.8: sadc docs/research/gsa1_098_plan.md 5.5, 6.9; fish098.md 4.1; libsa1.h "the game's
// camera requests", SA1_API_CAMERA). Big's fishing camera: the game's own push / pop and camera core run in libsa1 while
// sa1_input.host_flags has SA1_INPUT_GAME_CAMERA; this file only reads what they did. The bit reaches libsa1 through gsa1.Tick's host
// flags (session.hpp kHostFlagsKnown, seam M1). No session patch: the call goes straight to libsa1 with Session::ctx(). The addon's side
// is gsa1/feat/cl_gamecam.lua (the view, the blends, the render bounds, the mouse, the ways to leave, the Camera page's rows).
//
// Lua API (feature version 1; GSA1.HasFeature("gamecam", 1); only with a libsa1 that has SA1_API_CAMERA, else the feature is absent):
//   gsa1.Camera(id, alpha, out) -> true | false, message, code
//       On the game's thread, between ticks (a parallel tick's job never calls it). Fills the caller's table with raw sets, no table is
//       made and no string is kept per call (per frame, as gsa1.GetState):
//         flags   gsa1.CAMSTATE_* (ACTIVE a request above level 0, KNOWN libsa1 can run its function, RUNNING it ran in the last pair:
//                 position, forward, target and fov are valid, CUT the request changed with adjust 0 and the camera jumped: no interpolation)
//         kind    gsa1.CAMKIND_* (NONE, AIM 8C0239C2, LURE 8C0EAF28, CATCH 8C0EAA80, OTHER: reported, not run)
//         level   0 NORMAL, 2 EVENT, 4 COLI        adjust   the game's adjust index (0 NONE, 3 SLOW, ...)
//         fn      the mode function's Dreamcast address (0: none)
//         px, py, pz   position, fx, fy, fz   forward (unit), tx, ty, tz   the camera work's target (Hammer units, host axes; during a SLOW
//                 blend the view does not point at the target yet: use forward)
//         fov     radians, libsa1's number (70 degrees, 4:3)
//       alpha as gsa1.Render: 0..1 between the last two drawn pairs; below 0: libsa1's accumulator.
//       false for: bad arguments ("bad_argument"); an id that is not a ticking character of this client ("not_found"); libsa1's refusal, in
//       sa1_status_string's words ("unsupported" while its gate is closed; "not loaded" without a world). `out` is left as it was.
//   gsa1.INPUT_GAME_CAMERA           the host flag (gsa1.Tick's hostFlags)
//   gsa1.CAMSTATE_ACTIVE, _KNOWN, _RUNNING, _CUT, gsa1.CAMKIND_NONE, _AIM, _LURE, _CATCH, _OTHER
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>

#include "GarrysMod/Lua/Interface.h"

#include "../core/session.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

#if defined(SA1_API_CAMERA)

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;

namespace {

inline void raw_float(ILuaBase *L, int t, const char *k, float v)
{
    raw_num(L, t, k, std::isfinite(v) ? (double)v : 0.0);
}

void gamecam_open(ILuaBase *L, int t)
{
    raw_num(L, t, "INPUT_GAME_CAMERA", SA1_INPUT_GAME_CAMERA);
    raw_num(L, t, "CAMSTATE_ACTIVE", SA1_CAMSTATE_ACTIVE);
    raw_num(L, t, "CAMSTATE_KNOWN", SA1_CAMSTATE_KNOWN);
    raw_num(L, t, "CAMSTATE_RUNNING", SA1_CAMSTATE_RUNNING);
    raw_num(L, t, "CAMSTATE_CUT", SA1_CAMSTATE_CUT);
    raw_num(L, t, "CAMKIND_NONE", SA1_CAMKIND_NONE);
    raw_num(L, t, "CAMKIND_AIM", SA1_CAMKIND_AIM);
    raw_num(L, t, "CAMKIND_LURE", SA1_CAMKIND_LURE);
    raw_num(L, t, "CAMKIND_CATCH", SA1_CAMKIND_CATCH);
    raw_num(L, t, "CAMKIND_OTHER", SA1_CAMKIND_OTHER);
}

}  // namespace

// gsa1.Camera(id, alpha, out) -> true | false, message, code
GSA1_FN(gsa1_gamecam_Camera)
{
    int32_t id = 0;
    double alpha = -1.0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_number(LUA, 2, alpha) || !LUA->IsType(3, LT::Table)) {
        return push_false_msg(LUA, "Camera(id, alpha, out): a character's id, a number, a table", "bad_argument");
    }
    gsa1::Session *se = session();
    gsa1::Character *c = se ? se->get(id) : nullptr;
    if (!c || c->puppet) {
        return push_false_msg(LUA, "no such character", "not_found");
    }
    sa1_camera_state cs;
    std::memset(&cs, 0, sizeof cs);
    cs.struct_size = sizeof cs;
    sa1_status st = sa1_character_camera(se->ctx(), c->id, (float)alpha, &cs);
    if (st != SA1_OK) {
        const char *word = sa1_status_string(st);
        return push_false_msg(LUA, word, st == SA1_ERR_UNSUPPORTED ? "unsupported" : word);
    }
    const int t = absidx(LUA, 3);
    raw_num(LUA, t, "flags", cs.flags);
    raw_num(LUA, t, "kind", cs.kind);
    raw_num(LUA, t, "level", cs.level);
    raw_num(LUA, t, "adjust", cs.adjust);
    raw_num(LUA, t, "fn", cs.function);
    raw_float(LUA, t, "px", cs.position[0]);
    raw_float(LUA, t, "py", cs.position[1]);
    raw_float(LUA, t, "pz", cs.position[2]);
    raw_float(LUA, t, "fx", cs.forward[0]);
    raw_float(LUA, t, "fy", cs.forward[1]);
    raw_float(LUA, t, "fz", cs.forward[2]);
    raw_float(LUA, t, "tx", cs.target[0]);
    raw_float(LUA, t, "ty", cs.target[1]);
    raw_float(LUA, t, "tz", cs.target[2]);
    raw_float(LUA, t, "fov", cs.fov);
    LUA->PushBool(true);
    return 1;
}

namespace {

const gsa1::FeatureFn k_gamecam_fns[] = {
    {"Camera", gsa1_gamecam_Camera},
};

}  // namespace

// version 1 (0.9.8): Camera, INPUT_GAME_CAMERA, CAMSTATE_*, CAMKIND_*
GSA1_FEATURE(gamecam, 1, k_gamecam_fns, gamecam_open, nullptr, gsa1::kCloseDefault);

#endif  // SA1_API_CAMERA (a libsa1 without it: no feature "gamecam"; GSA1.HasFeature("gamecam") is false)
