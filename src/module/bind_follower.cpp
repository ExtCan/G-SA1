// G-SA1 module: the feature "follower" (round 0.9.8: sadc docs/research/gsa1_098_plan.md 2.4, 5.5, 6.6; gsa1_096_plan.md 5.5, 6.4;
// follow096_gsa1.md 4.3; libsa1.h "followers", SA1_API_FOLLOWER). A follower runs the game's own 1.5P AI in a libsa1 world of
// its own. The core is src/core/follower.{hpp,cpp}, src/core/pool.{hpp,cpp} and the session's follower parts; the addon's side is
// gsa1/feat/{sh,cl,sv}_follower.lua.
//
// Lua API (feature version 1; GSA1.HasFeature("follower", 1); only with a libsa1 that has SA1_API_FOLLOWER, else the feature is
// absent). Every function runs on the game's thread (Lua never runs during a pool job), never raises a Lua error, and returns
// `true | nil, message, code` unless noted; codes "unsupported" (libsa1's plain reason: "Big cannot follow yet: ...", "followers
// do not take emotes, faces or orders"), "limit", "not_ready" (no disc / no map collision yet), "fault", "bad_argument",
// "not_found". Per-frame functions fill a passed table without allocating. Units: HU, HU/s, degrees, host axes.
//   gsa1.FollowerKinds([out]) -> out   [kind] = true | "the plain reason" for kinds 0, 2, 3, 5, 6, 7 and (0.9.9e) 1, 4
//   gsa1.FollowerCreate(kind, pos, yawDeg, leaderId | nil, opts) -> id | nil, msg, code
//       opts (optional) = { upgrades = { "name", ... }, objects = 0 | 1, sounds = bool, seed = n, fix_view = bool (default true =
//       not SA1_FOLLOW_GAME_VIEW), fix_respawn = bool (default true = not SA1_FOLLOW_GAME_HISTORY) }. leaderId: a character id
//       of this session (exact, per step); nil = host-fed (first snapshot: pos / yawDeg standing). 0.9.9h (gsa1.FOLLOWER.SKIN): opts.skin = GSA1.Skins.DescOf(entry), kind 0:
//       a Sonic follower wearing it (libsa1 SA1_FOLLOW_SKIN: its world is a Sonic follower's, byte for byte), opts.voiceless = bool. "limit" at kMaxFollowers 112 or
//       kMaxCharacters 128, and "limit" with "not enough free memory" below 2,073 MB of available physical memory
//   gsa1.FollowerLeader(id, leaderId | nil) -> true | nil, msg, code      "bad_argument" for itself / its own followers
//   gsa1.FollowerFeed(id, pos, vel, yawDeg, ground [, kind]) -> true | nil, msg, code   for the next FollowersTick
//   gsa1.FollowerHostFlags(id, flags) -> true | nil, msg, code    the host's water bits for its next tick (gsa1.Tick's rule; the
//       game's camera request is the player's only: it is masked here)
//   gsa1.FollowerHold(id, on) -> true | nil, msg, code      the game's hold flag (sa1_follower_hold)
//   gsa1.FollowerRespawn(id) -> true | nil, msg, code       the game's respawn 8C081C36 (in from 50 units above the camera)
//   gsa1.FollowerDraw(id, level [, rate]) -> true | nil, msg, code
//       1 full: rendered in every FollowersTick (alpha as the player's); 2 far: rendered at alpha 1 `rate` times a second (5-30,
//       default 15), staggered by id over the frames; 3 none: not rendered (still ticked). Default 1
//   gsa1.FollowersTick(dt, viewYawDeg, camOrigin | nil, camTarget | nil, out [, interpolate]) -> out | nil, msg, code
//       every follower, chain level by chain level (leaders first), as jobs on the pool; returns after the join. out.count; out[i] =
//       { id, pairs, ok, code, msg, rendered (a new render this frame), restructured (the batches changed: call gsa1.Batches),
//       x, y, z, yaw (degrees), interpolated, alpha, tris } (tables reused: read out.count, entries above it are old); out.workers,
//       out.ms (wall), out.ms_join (the game thread's wait). camOrigin / camTarget only reach followers whose chain root is this
//       client's character (and only when gsa1.TICK_HOST_CAMERA and the camera is valid). interpolate (optional, default true):
//       the player's alpha rule of level 1 (gsa1_interpolate)
//   gsa1.FollowerInfo(id [, out]) -> out | nil, msg, code
//       out.kind, out.leader (id, 0 host-fed), out.mode, out.smode, out.offscreen (steps), out.distance (HU), out.respawns,
//       out.respawns_distance, out.respawns_offscreen, out.held, out.lost (the leader was lost), out.hidden (0..1, the last 300
//       pairs), out.pairs, out.dropped, out.objects, out.sounds, out.level
//       (feature version 2) out.speed_factor: the factor of the last step (sa1_follower_speed; 1 near its spot)
//   gsa1.FollowerSpeed(id, m) -> true | nil, msg, code      (feature version 2, round 0.9.9, sadc docs/research/gsa1_099_plan.md 5.5, libsa1's
//       SA1_API_FOLLOWER 2) sa1_follower_speed: how much faster than the game's own numbers it may run while it is behind its spot,
//       m 1 (the game's own: nothing is ever written) .. gsa1.FOLLOWER.SPEED_MAX
//   gsa1.FollowerSpot(id, x, y) -> true | nil, msg, code    (feature version 2) sa1_follower_spot: where it stands around its leader, an
//       offset in host units in Source's axes with z 0 (two numbers: no engine Vector, the hook budget of 098 D10); 0, 0: the game's own place
//   gsa1.FollowerStand(id, on) -> true | nil, msg, code     (round 0.9.9a, sadc build/research/r099a/stop/diagnosis.md; asked for by name, the feature's version stays 2) sa1_follower_stand: on, a follower
//       that stops reaches the game's own stand and idle; off, the game's AI keeps its stick at 0.005 and the follower stays in its walk at speed 0 on one frame, as the real game's Tails does
//   gsa1.FollowerThreads(n) -> workers | nil, msg, code     module-wide; 0 automatic; the pool is rebuilt between frames
//   gsa1.FollowersStats([out]) -> out                       the last second: followers, workers, ms_tick, ms_render, ms_join,
//       ms_wall, frames
//   gsa1.FOLLOWER = { MAX = 112, MAX_CHARACTERS = 128, OBJECTS_NONE = 0, OBJECTS_OWN = 1, DRAW_FULL = 1, DRAW_FAR = 2,
//       DRAW_NONE = 3, RATE_MIN = 5, RATE_MAX = 30, RATE_DEFAULT = 15, POOL_MAX = 16, LIB_PARALLEL = bool,
//       MODE = { PLACE = 0, RESPAWN = 2, NORMAL = 4, TAKEOVER = 5, PARKED = 6 }, SPEED_MAX (feature version 2: libsa1's 8) }
// Valid for a follower id, unchanged: gsa1.Batches, gsa1.PrepareView, gsa1.EmitBatch, gsa1.GetState, gsa1.StateEx, gsa1.Destroy,
// gsa1.SetGameOption, gsa1.ObjWorldMask, 0.9.5's gsa1.Board / BoardPush / BoardFree / BoardState (slot 1). gsa1.Render(followerId,
// ...) renders nothing and answers the values of its last pool render (the pool renders followers: FollowerDraw).
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/follower.hpp"
#include "../core/pool.hpp"
#include "../core/session.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"
#include "skin_args.hpp"            // 0.9.9h: opts.skin

#if defined(SA1_API_FOLLOWER)

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;

namespace {

const int kFollowerKinds[] = {SA1_CHAR_SONIC, SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA, SA1_CHAR_BIG, SA1_CHAR_EGGMAN, SA1_CHAR_TIKAL};

bool arg_absent(ILuaBase *L, int i)
{
    int t = L->GetType(i);
    return t == LT::Nil || t == LT::None;
}

void raw_nil(ILuaBase *L, int t, const char *k)
{
    L->PushString(k);
    L->PushNil();
    L->RawSet(t);
}

// the code word of a failed libsa1 status
const char *code_of(sa1_status st)
{
    switch (st) {
    case SA1_ERR_UNSUPPORTED: return "unsupported";
    case SA1_ERR_NOT_LOADED: return "not_ready";
    case SA1_ERR_LIMIT: return "limit";
    case SA1_ERR_INVALID_ARGUMENT: return "bad_argument";
    case SA1_ERR_NOT_FOUND: return "not_found";
    case SA1_ERR_GAME_FAULT:
    case SA1_ERR_NOT_IMPLEMENTED: return "fault";
    default: return "error";
    }
}

// the follower `id` of this session; otherwise nullptr with the failure pushed (ret)
gsa1::Character *follower_char(ILuaBase *L, int32_t id, int &ret)
{
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        ret = push_nil_msg(L, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
        return nullptr;
    }
    gsa1::Character *c = se->get(id);
    if (!c) {
        ret = push_nil_msg(L, "no such character", "not_found");
        return nullptr;
    }
    if (!c->follower) {
        ret = push_nil_msg(L, "this character is not a follower", "bad_argument");
        return nullptr;
    }
    return c;
}

// libsa1's failure of a follower call on c, pushed
int push_lib_failure(ILuaBase *L, gsa1::Session *se, sa1_status st)
{
    const char *why = sa1_last_error(se->ctx());
    return push_nil_msg(L, scrubbed(why && *why ? std::string(why) : std::string(sa1_status_string(st))), code_of(st));
}

// t[k] when present: a boolean (ok false: present and not a boolean)
void opt_bool(ILuaBase *L, int t, const char *k, bool &out, bool &ok)
{
    L->PushString(k);
    L->RawGet(t);
    int ty = L->GetType(-1);
    if (ty != LT::Nil && ty != LT::None) {
        if (ty == LT::Bool) {
            out = L->GetBool(-1);
        } else {
            ok = false;
        }
    }
    L->Pop();
}

// opts.upgrades: an array of at most 32 upgrade names of `kind`
bool opt_upgrades(ILuaBase *L, int t, int32_t kind, std::vector<const gsa1::UpgradeDef *> &out, std::string &err)
{
    L->PushString("upgrades");
    L->RawGet(t);
    int ty = L->GetType(-1);
    if (ty == LT::Nil || ty == LT::None) {
        L->Pop();
        return true;
    }
    if (ty != LT::Table) {
        L->Pop();
        err = "opts.upgrades: a table of upgrade names (gsa1.Upgrades(kind))";
        return false;
    }
    int u = L->Top();
    for (int k = 1; k <= 33; k++) {
        L->PushNumber(k);
        L->RawGet(u);
        if (L->IsType(-1, LT::Nil)) {
            L->Pop();
            break;
        }
        std::string name;
        bool ok = k <= 32 && L->IsType(-1, LT::String);
        if (ok) {
            unsigned int len = 0;
            const char *str = L->GetString(-1, &len);
            ok = str && len <= 64;
            if (ok) {
                name.assign(str, len);
            }
        }
        L->Pop();
        const gsa1::UpgradeDef *d = ok ? gsa1::find_upgrade(kind, name) : nullptr;
        if (!d) {
            L->Pop();
            err = ok ? "opts.upgrades: this character has no upgrade of that name (gsa1.Upgrades(kind))"
                     : "opts.upgrades: at most 32 names";
            return false;
        }
        out.push_back(d);
    }
    L->Pop();
    return true;
}

}  // namespace

// gsa1.FollowerKinds([out]) -> out
GSA1_FN(gsa1_follower_FollowerKinds)
{
    int t = out_table(LUA, 1);
    uint32_t mask = sa1_follower_kinds();
    for (int kind : kFollowerKinds) {
        LUA->PushNumber(kind);
        if ((mask >> kind) & 1u) {
            LUA->PushBool(true);
        } else {
            const char *why = sa1_follower_kind_reason(kind);
            LUA->PushString(why && *why ? why : "this character cannot follow yet");
        }
        LUA->RawSet(t);
    }
    return 1;
}

// gsa1.FollowerCreate(kind, pos, yawDeg, leaderId | nil, opts) -> id | nil, msg, code
GSA1_FN(gsa1_follower_FollowerCreate)
{
    static const char *usage = "FollowerCreate(kind, Vector pos, yawDegrees, leaderId | nil [, {upgrades = {names}, objects = 0 | 1, "
                               "sounds = bool, seed = n, fix_view = bool, fix_respawn = bool, skin = GSA1.Skins.DescOf(entry), voiceless = bool}])";
    int32_t kind = 0, leader = 0;
    float pos[3];
    double yaw = 0.0;
    if (!arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1) || !arg_vector(LUA, 2, pos) || !arg_number(LUA, 3, yaw) ||
        (!arg_absent(LUA, 4) && !arg_int(LUA, 4, leader, 1, 2147483647.0)) ||
        (!arg_absent(LUA, 5) && !LUA->IsType(5, LT::Table))) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    gsa1::FollowerOpts o;
    std::string err;
#if defined(SA1_API_SKIN)
    gsa1::skinargs::SkinArgs skin_args;     // 0.9.9h: lives through the create (libsa1 reads it then only)
#endif
    if (LUA->IsType(5, LT::Table)) {
        int t = absidx(LUA, 5);
        if (!opt_upgrades(LUA, t, kind, o.upgrades, err)) {
            return push_nil_msg(LUA, err, "bad_argument");
        }
        double v = 0.0;
        LUA->PushString("objects");
        LUA->RawGet(t);
        int ty = LUA->GetType(-1);
        LUA->Pop();
        if (ty != LT::Nil && ty != LT::None) {
            if (!raw_get_number(LUA, t, "objects", v) || (v != 0.0 && v != 1.0)) {
                return push_nil_msg(LUA, "opts.objects: 0 or 1 (gsa1.FOLLOWER.OBJECTS_NONE / _OWN)", "bad_argument");
            }
            o.objects = (uint32_t)v;
        }
        LUA->PushString("seed");
        LUA->RawGet(t);
        ty = LUA->GetType(-1);
        LUA->Pop();
        if (ty != LT::Nil && ty != LT::None) {
            if (!raw_get_number(LUA, t, "seed", v) || v < 0.0 || v > 4294967295.0 || v != std::floor(v)) {
                return push_nil_msg(LUA, "opts.seed: a whole number (0..2^32-1)", "bad_argument");
            }
            o.seed_given = true;
            o.seed = (uint32_t)v;
        }
        bool ok = true;
        opt_bool(LUA, t, "sounds", o.sounds, ok);
        opt_bool(LUA, t, "fix_view", o.fix_view, ok);
        opt_bool(LUA, t, "fix_respawn", o.fix_respawn, ok);
        opt_bool(LUA, t, "voiceless", o.voiceless, ok);
        if (!ok) {
            return push_nil_msg(LUA, usage, "bad_argument");
        }
        // 0.9.9h: opts.skin, a flat table (feat/sh_skins.lua GSA1.Skins.DescOf): the follower wears it over a Sonic follower's world
        LUA->PushString("skin");
        LUA->RawGet(t);
        int tsk = LUA->GetType(-1);
        if (tsk != LT::Nil && tsk != LT::None) {
#if defined(SA1_API_SKIN)
            std::string serr;
            bool sok = tsk == LT::Table && skin_args.read(LUA, LUA->Top(), serr);
            LUA->Pop();
            if (!sok) {
                return push_nil_msg(LUA, tsk == LT::Table ? serr : std::string("opts.skin: a skin's table (GSA1.Skins.DescOf)"), "bad_argument");
            }
            o.skin = &skin_args.d;
#else
            LUA->Pop();
            return push_nil_msg(LUA, "this libsa1 has no skins (SA1_API_SKIN)", "unsupported");
#endif
        } else {
            LUA->Pop();
        }
    }
    int ret = 0;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    sa1_collision_info ci;
    if (!se->world_info(ci) || ci.triangles == 0) {
        return push_nil_msg(LUA, "no world collision yet: call gsa1.WorldLoad(game.GetMap()) first", "not_ready");
    }
    const char *code = nullptr;
    int32_t id = se->create_follower(kind, pos, deg2rad(yaw), leader, o, err, &code);
    if (id <= 0) {
        return push_nil_msg(LUA, err, code ? code : "error");
    }
    LUA->PushNumber(id);
    return 1;
}

// gsa1.FollowerLeader(id, leaderId | nil) -> true | nil, msg, code
GSA1_FN(gsa1_follower_FollowerLeader)
{
    int32_t id = 0, leader = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || (!arg_absent(LUA, 2) && !arg_int(LUA, 2, leader, 1, 2147483647.0))) {
        return push_nil_msg(LUA, "FollowerLeader(id, leaderId | nil)", "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
    }
    std::string err;
    const char *code = nullptr;
    if (!se->set_follower_leader(id, leader, err, &code)) {
        return push_nil_msg(LUA, err, code ? code : "error");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.FollowerFeed(id, pos, vel, yawDeg, ground [, kind]) -> true | nil, msg, code
GSA1_FN(gsa1_follower_FollowerFeed)
{
    int32_t id = 0, kind = -1;
    gsa1::LeaderFeed f;
    double yaw = 0.0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_vector(LUA, 2, f.pos) || !arg_vector(LUA, 3, f.vel) ||
        !arg_number(LUA, 4, yaw) || !LUA->IsType(5, LT::Bool) ||
        (!arg_absent(LUA, 6) && !arg_int(LUA, 6, kind, -1, SA1_CHAR_COUNT - 1))) {
        return push_nil_msg(LUA, "FollowerFeed(id, Vector pos, Vector vel, yawDegrees, onGround [, kind])", "bad_argument");
    }
    f.yaw = deg2rad(yaw);
    f.ground = LUA->GetBool(5);
    f.kind = kind;
    f.valid = true;
    int ret = 0;
    if (!follower_char(LUA, id, ret)) {
        return ret;
    }
    session()->followers().feed(id, f);
    LUA->PushBool(true);
    return 1;
}

// gsa1.FollowerHostFlags(id, flags) -> true | nil, msg, code
GSA1_FN(gsa1_follower_FollowerHostFlags)
{
    int32_t id = 0, flags = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_int(LUA, 2, flags, 0, 255)) {
        return push_nil_msg(LUA, "FollowerHostFlags(id, flags 0..255)", "bad_argument");
    }
    int ret = 0;
    gsa1::Character *c = follower_char(LUA, id, ret);
    if (!c) {
        return ret;
    }
    c->host_flags_next = (uint32_t)flags & gsa1::kHostWaterFlags;
    LUA->PushBool(true);
    return 1;
}

// gsa1.FollowerHold(id, on) -> true | nil, msg, code
GSA1_FN(gsa1_follower_FollowerHold)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !LUA->IsType(2, LT::Bool)) {
        return push_nil_msg(LUA, "FollowerHold(id, on)", "bad_argument");
    }
    int ret = 0;
    if (!follower_char(LUA, id, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    sa1_status st = sa1_follower_hold(se->ctx(), id, LUA->GetBool(2) ? 1 : 0);
    if (SA1_FAILED(st)) {
        return push_lib_failure(LUA, se, st);
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.FollowerRespawn(id) -> true | nil, msg, code
GSA1_FN(gsa1_follower_FollowerRespawn)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0)) {
        return push_nil_msg(LUA, "FollowerRespawn(id)", "bad_argument");
    }
    int ret = 0;
    if (!follower_char(LUA, id, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    sa1_status st = sa1_follower_respawn(se->ctx(), id);
    if (SA1_FAILED(st)) {
        return push_lib_failure(LUA, se, st);
    }
    LUA->PushBool(true);
    return 1;
}

#if SA1_API_FOLLOWER >= 2
// gsa1.FollowerStand(id, on) -> true | nil, msg, code
GSA1_FN(gsa1_follower_FollowerStand)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !LUA->IsType(2, LT::Bool)) {
        return push_nil_msg(LUA, "FollowerStand(id, on)", "bad_argument");
    }
    int ret = 0;
    if (!follower_char(LUA, id, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    sa1_status st = sa1_follower_stand(se->ctx(), id, LUA->GetBool(2) ? 1 : 0);
    if (SA1_FAILED(st)) {
        return push_lib_failure(LUA, se, st);
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.FollowerSpeed(id, m) -> true | nil, msg, code
GSA1_FN(gsa1_follower_FollowerSpeed)
{
    int32_t id = 0;
    double m = 0.0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_number(LUA, 2, m)) {
        return push_nil_msg(LUA, "FollowerSpeed(id, multiplier 1..gsa1.FOLLOWER.SPEED_MAX)", "bad_argument");
    }
    int ret = 0;
    if (!follower_char(LUA, id, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    sa1_status st = sa1_follower_speed(se->ctx(), id, (float)m);
    if (SA1_FAILED(st)) {
        return push_lib_failure(LUA, se, st);
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.FollowerSpot(id, x, y) -> true | nil, msg, code
GSA1_FN(gsa1_follower_FollowerSpot)
{
    int32_t id = 0;
    double x = 0.0, y = 0.0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_number(LUA, 2, x) || !arg_number(LUA, 3, y)) {
        return push_nil_msg(LUA, "FollowerSpot(id, x, y): host units, Source's axes", "bad_argument");
    }
    int ret = 0;
    if (!follower_char(LUA, id, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    const float offset[3] = {(float)x, (float)y, 0.0f};
    sa1_status st = sa1_follower_spot(se->ctx(), id, offset);
    if (SA1_FAILED(st)) {
        return push_lib_failure(LUA, se, st);
    }
    LUA->PushBool(true);
    return 1;
}
#endif  // SA1_API_FOLLOWER >= 2

// gsa1.FollowerDraw(id, level [, rate]) -> true | nil, msg, code
GSA1_FN(gsa1_follower_FollowerDraw)
{
    int32_t id = 0, level = 0, rate = (int32_t)gsa1::kFollowerRateDefault;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_int(LUA, 2, level, 1, 3) ||
        (!arg_absent(LUA, 3) && !arg_int(LUA, 3, rate, gsa1::kFollowerRateMin, gsa1::kFollowerRateMax))) {
        return push_nil_msg(LUA, "FollowerDraw(id, level 1 | 2 | 3 [, rate 5..30])", "bad_argument");
    }
    int ret = 0;
    gsa1::Character *c = follower_char(LUA, id, ret);
    if (!c) {
        return ret;
    }
    c->draw_level = (uint32_t)level;
    c->draw_rate = (uint32_t)rate;
    LUA->PushBool(true);
    return 1;
}

// gsa1.FollowersTick(dt, viewYawDeg, camOrigin | nil, camTarget | nil, out [, interpolate]) -> out | nil, msg, code
GSA1_FN(gsa1_follower_FollowersTick)
{
    static const char *usage = "FollowersTick(dt, viewYawDegrees, camOrigin | nil, camTarget | nil, out [, interpolate])";
    double dt = 0.0, yaw = 0.0;
    gsa1::TickExtra cam;
    if (!arg_number(LUA, 1, dt) || !arg_number(LUA, 2, yaw) || (!arg_absent(LUA, 5) && !LUA->IsType(5, LT::Table)) ||
        (!arg_absent(LUA, 6) && !LUA->IsType(6, LT::Bool))) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    if (!arg_absent(LUA, 3) || !arg_absent(LUA, 4)) {
        if (!arg_vector(LUA, 3, cam.cam_pos) || !arg_vector(LUA, 4, cam.cam_target)) {
            return push_nil_msg(LUA, usage, "bad_argument");
        }
        cam.camera = true;
    }
    bool interpolate = !LUA->IsType(6, LT::Bool) || LUA->GetBool(6);
    int ret = 0;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    static std::vector<gsa1::FollowerTickResult> res;      // (only Lua's thread comes here: reused, no allocation per frame)
    se->tick_followers((float)dt, deg2rad(yaw), cam.camera ? &cam : nullptr, interpolate, res);
    int t = out_table(LUA, 5);
    int i = 0;
    for (const gsa1::FollowerTickResult &r : res) {
        int e = raw_subtable_i(LUA, t, ++i);
        raw_num(LUA, e, "id", r.id);
        raw_num(LUA, e, "pairs", r.pairs);
        bool ok = !SA1_FAILED(r.status);
        raw_bool(LUA, e, "ok", ok);
        if (ok) {
            raw_nil(LUA, e, "code");
        } else {
            raw_str(LUA, e, "code", code_of(r.status));
        }
        if (r.msg) {
            raw_str(LUA, e, "msg", *r.msg);
        } else {
            raw_nil(LUA, e, "msg");
        }
        raw_bool(LUA, e, "rendered", r.rendered);
        raw_bool(LUA, e, "restructured", r.restructured);
        raw_num(LUA, e, "x", std::isfinite(r.pos[0]) ? r.pos[0] : 0.0);
        raw_num(LUA, e, "y", std::isfinite(r.pos[1]) ? r.pos[1] : 0.0);
        raw_num(LUA, e, "z", std::isfinite(r.pos[2]) ? r.pos[2] : 0.0);
        raw_num(LUA, e, "yaw", std::isfinite(r.yaw) ? rad2deg(r.yaw) : 0.0);
        raw_bool(LUA, e, "interpolated", r.interpolated);
        raw_num(LUA, e, "alpha", r.alpha);
        raw_num(LUA, e, "tris", r.tris);
        LUA->Pop();     // the entry (raw_subtable_i left it)
    }
    raw_num(LUA, t, "count", i);
    raw_num(LUA, t, "workers", se->pool().workers());
    raw_num(LUA, t, "ms", se->follower_ms_last());
    raw_num(LUA, t, "ms_join", se->follower_join_ms_last());
    return 1;
}

// gsa1.FollowerInfo(id [, out]) -> out | nil, msg, code
GSA1_FN(gsa1_follower_FollowerInfo)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || (!arg_absent(LUA, 2) && !LUA->IsType(2, LT::Table))) {
        return push_nil_msg(LUA, "FollowerInfo(id [, out])", "bad_argument");
    }
    int ret = 0;
    gsa1::Character *c = follower_char(LUA, id, ret);
    if (!c) {
        return ret;
    }
    gsa1::Session *se = session();
    sa1_follower_info fi;
    std::memset(&fi, 0, sizeof fi);
    fi.struct_size = sizeof fi;
    sa1_status st = sa1_follower_info_get(se->ctx(), id, &fi);
    if (SA1_FAILED(st)) {
        return push_lib_failure(LUA, se, st);
    }
    int t = out_table(LUA, 2);
    raw_num(LUA, t, "kind", c->kind);
    raw_num(LUA, t, "leader", fi.leader);
    raw_num(LUA, t, "mode", fi.ai_mode);
    raw_num(LUA, t, "smode", fi.ai_smode);
    raw_num(LUA, t, "offscreen", fi.offscreen_steps);
    raw_num(LUA, t, "distance", std::isfinite(fi.distance) ? fi.distance : 0.0);
    raw_num(LUA, t, "respawns", fi.respawns);
    raw_num(LUA, t, "respawns_distance", fi.respawns_distance);
    raw_num(LUA, t, "respawns_offscreen", fi.respawns_offscreen);
    raw_bool(LUA, t, "held", (fi.flags & SA1_FINFO_HELD) != 0);
    raw_bool(LUA, t, "lost", (fi.flags & SA1_FINFO_LEADER_LOST) != 0);
    raw_num(LUA, t, "hidden", (double)fi.hidden_pairs / 300.0);
    raw_num(LUA, t, "pairs", (double)c->pairs_total);
    raw_num(LUA, t, "dropped", fi.steps_dropped);
    raw_num(LUA, t, "objects", c->follower_objects);
    raw_bool(LUA, t, "sounds", c->follower_sounds);
    raw_num(LUA, t, "level", c->draw_level);
#if SA1_API_FOLLOWER >= 2
    raw_num(LUA, t, "speed_factor", std::isfinite(fi.speed_factor) ? fi.speed_factor : 1.0);
#endif
    return 1;
}

// gsa1.FollowerThreads(n) -> workers | nil, msg, code
GSA1_FN(gsa1_follower_FollowerThreads)
{
    int32_t n = 0;
    if (!arg_int(LUA, 1, n, 0, gsa1::kPoolMaxWorkers)) {
        return push_nil_msg(LUA, "FollowerThreads(n 0..16: 0 = automatic)", "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    LUA->PushNumber(se->set_follower_threads((uint32_t)n));
    return 1;
}

// gsa1.FollowersStats([out]) -> out
GSA1_FN(gsa1_follower_FollowersStats)
{
    int t = out_table(LUA, 1);
    gsa1::Session *se = session();
    gsa1::FollowerStats st;
    if (se) {
        st = se->follower_stats();
    }
    raw_num(LUA, t, "followers", se ? (double)se->followers().count() : 0.0);
    raw_num(LUA, t, "workers", st.workers);
    raw_num(LUA, t, "ms_tick", st.ms_tick);
    raw_num(LUA, t, "ms_render", st.ms_render);
    raw_num(LUA, t, "ms_join", st.ms_join);
    raw_num(LUA, t, "ms_wall", st.ms_wall);
    raw_num(LUA, t, "frames", st.frames);
    return 1;
}

namespace {

void follower_open(ILuaBase *L, int t)
{
    L->PushString("FOLLOWER");
    L->CreateTable();
    int c = L->Top();
    raw_num(L, c, "MAX", (double)gsa1::kMaxFollowers);
    raw_num(L, c, "MAX_CHARACTERS", (double)gsa1::kMaxCharacters);
    raw_num(L, c, "OBJECTS_NONE", 0);
    raw_num(L, c, "OBJECTS_OWN", 1);
    raw_num(L, c, "DRAW_FULL", gsa1::kFollowerDrawFull);
    raw_num(L, c, "DRAW_FAR", gsa1::kFollowerDrawFar);
    raw_num(L, c, "DRAW_NONE", gsa1::kFollowerDrawNone);
    raw_num(L, c, "RATE_MIN", gsa1::kFollowerRateMin);
    raw_num(L, c, "RATE_MAX", gsa1::kFollowerRateMax);
    raw_num(L, c, "RATE_DEFAULT", gsa1::kFollowerRateDefault);
    raw_num(L, c, "POOL_MAX", gsa1::kPoolMaxWorkers);
    raw_bool(L, c, "LIB_PARALLEL", gsa1::kPoolLibParallel);
#if SA1_API_FOLLOWER >= 2
    raw_num(L, c, "SPEED_MAX", SA1_FOLLOWER_SPEED_MAX);
#endif
#if defined(SA1_API_SKIN) && SA1_API_SKIN >= 2
    raw_bool(L, c, "SKIN", true);      // 0.9.9h: FollowerCreate's opts.skin, opts.voiceless (libsa1's SA1_FOLLOW_SKIN); asked for by name, the feature's version stays 2
#endif
    L->PushString("MODE");
    L->CreateTable();
    int m = L->Top();
    raw_num(L, m, "PLACE", 0);
    raw_num(L, m, "RESPAWN", 2);
    raw_num(L, m, "NORMAL", 4);
    raw_num(L, m, "TAKEOVER", 5);
    raw_num(L, m, "PARKED", 6);
    L->RawSet(c);
    L->RawSet(t);
}

const gsa1::FeatureFn k_follower_fns[] = {
    {"FollowerKinds", gsa1_follower_FollowerKinds},
    {"FollowerCreate", gsa1_follower_FollowerCreate},
    {"FollowerLeader", gsa1_follower_FollowerLeader},
    {"FollowerFeed", gsa1_follower_FollowerFeed},
    {"FollowerHostFlags", gsa1_follower_FollowerHostFlags},
    {"FollowerHold", gsa1_follower_FollowerHold},
    {"FollowerRespawn", gsa1_follower_FollowerRespawn},
#if SA1_API_FOLLOWER >= 2
    {"FollowerStand", gsa1_follower_FollowerStand},
    {"FollowerSpeed", gsa1_follower_FollowerSpeed},
    {"FollowerSpot", gsa1_follower_FollowerSpot},
#endif
    {"FollowerDraw", gsa1_follower_FollowerDraw},
    {"FollowersTick", gsa1_follower_FollowersTick},
    {"FollowerInfo", gsa1_follower_FollowerInfo},
    {"FollowerThreads", gsa1_follower_FollowerThreads},
    {"FollowersStats", gsa1_follower_FollowersStats},
};

}  // namespace

// version 1 (0.9.8): the functions above, gsa1.FOLLOWER; version 2 (0.9.9, libsa1's SA1_API_FOLLOWER 2): FollowerSpeed, FollowerSpot,
// gsa1.FOLLOWER.SPEED_MAX, FollowerInfo's speed_factor. The addon's Fo.NEEDS stays version 1: it asks for the new calls by name
#if SA1_API_FOLLOWER >= 2
GSA1_FEATURE(follower, 2, k_follower_fns, follower_open, nullptr, gsa1::kCloseDefault);
#else
GSA1_FEATURE(follower, 1, k_follower_fns, follower_open, nullptr, gsa1::kCloseDefault);
#endif

#endif  // SA1_API_FOLLOWER (a libsa1 without followers: no feature "follower"; GSA1.HasFeature("follower") is false)
