// G-SA1 module: the feature "board" (round 0.9.5: sadc docs/research/gsa1_095_plan.md 4.4-4.13, 5.4 with its Review R.5 /
// R.6 / R.12; board095_gsa1.md 4.2; libsa1.h "the board", SA1_API_BOARD). Sonic's and Tails' sand / snow board by the
// game's own code, per CHARACTER (0.9.6's followers board through their own ids). The core part is src/core/board.{hpp,cpp}
// (the per-character Track the session keeps: libsa1's board state after every tick, the one-shot refusal / frees of
// SA1_EVENT_BOARD, the board's stage rules); the addon's side is gsa1/feat/{sh,cl,sv}_board.lua (the open wheel's B / RS,
// the Board page, the Board On / Board Off boxes, the left-behind boards).
//
// Lua API (feature version 1; GSA1.HasFeature("board", 1); only with a libsa1 that has SA1_API_BOARD, else the feature is
// absent). Every function runs on the game's thread between ticks, never raises a Lua error, and returns `true | nil,
// message, code` unless noted; codes "unsupported" (the plain reason: "only Sonic and Tails ride a board", "Super Sonic
// doesn't ride a board", "not riding", "no board left behind", "a puppet doesn't ride a board", or libsa1's own words),
// "not_ready" (no disc; a world image without the board's actions), "fault" (the character's world faulted), "bad_argument",
// "not_found" (no such character). Units: Hammer units and degrees, host axes. id: a character of this client.
//   gsa1.Board(id, on [, opts]) -> true | nil, message, code
//       on true: sa1_character_board(ON) - libsa1 posts the game's order 44 and makes a new board task (a kept board of an
//       earlier ride is freed first: nobody gets back on a left board); whether the game TOOK it shows after the next pair
//       (BoardState.on, or .refused once). Riding: only the terrain changes. opts (all optional): terrain =
//       gsa1.BOARD.TERRAIN_MAP (default) | TERRAIN_SNOW | TERRAIN_SAND (Ice Cap's snow / Sand Hill's sand under every
//       surface while riding: a host override); push = true (Ice Cap's start push 0C90E810 at the get-on: 4.0 u/step, 960
//       HU/s, for 102 steps or until the ride ends); tails_jump = true (keep the game's Tails jump x1.2 per ride:
//       FAITHFUL_EXIT; default: restored at the exit); reuse = true (the game's re-entry: the kept board snaps back;
//       G-SA1 0.9.5 never sets it); remove = true (the board is freed in the step the ride ends instead of staying).
//       on false: sa1_character_board(OFF) - order 24 (Ice Cap's goal) when riding, else nothing (true); opts.remove as
//       above (libsa1 reads it at OFF too: Review R.5).
//   gsa1.BoardPush(id) -> true | nil, message, code      riding on the ground: the start push again (no 0.9.5 control)
//   gsa1.BoardFree(id) -> true | nil, message, code      a kept (left-behind) board: freed now (the host's own copy takes
//       over: the left-board entity)
//   gsa1.BoardState(id [, out]) -> out | nil, message, code     per frame (no table is made when `out` is given; the
//       state after the last tick or board call): out.on, out.pending (order 44 posted, not answered yet), out.held (the
//       board follows the player), out.kept (a board lies, not held), out.settled (kept and at rest 30 steps), out.board
//       (a board task lives) - booleans; out.mode, out.action (player 0's taskwk.mode / action), out.speed (playerwk spd.x,
//       SA1 units per step: 1.0 = 240 HU/s), out.terrain, out.push_steps, out.kind (0 / 2: whose board; -1 none),
//       out.variant (Sonic: 0 MIW_B001, 1 SB_BOARD1), out.x, out.y, out.z (the board model's origin as the game drew it,
//       HU), out.pitch, out.yaw, out.roll (its rotation as a Source Angle, degrees), out.still (steps at rest), out.jump
//       (Tails' saved jmp_y_spd, 0 none); out.refused (true ONCE after a refusal) with out.reason ("carrying something" when
//       the character holds an object, else "can't get on a board now"; nil otherwise); out.freed (boards freed since the
//       last call) with out.freed_why (the last one's: 0 remove-on-exit, 1 fell, 2 replaced by a new ON, 3 BoardFree; -1
//       none)
//   gsa1.BoardSounds(on) -> true                        module-wide (default on): the board's stage rules (Ice Cap's tones
//       208-238 from stage 8, Sand Hill's 690-698 from stage 38) for every rider; off: a rider's board tones are stopped
//       and kept out of the mixer (the events still reach Lua)
//   gsa1.BoardInfo([out]) -> out                        {available (libsa1 has the board), version 1, kinds = {0, 2},
//       textures = {[0] = n, [2] = n} (the board texture archives the disc gave each kind: Sonic 2, Tails 1), rules (this
//       libsa1 has stage rules), sounds (gsa1.BoardSounds), tones_dropped}
//   gsa1.BOARD = {TERRAIN_MAP 0, TERRAIN_SNOW 1, TERRAIN_SAND 2, DRAW 0x4000 (SA1_DRAW_BOARD), SETTLE_STEPS 30,
//       SONIC_MODES {62, 68}, TAILS_MODES {48, 54}, FREED_REMOVED 0, FREED_FELL 1, FREED_REPLACED 2, FREED_FREE 3,
//       SNOW_TONES {208, 238}, SAND_TONES {690, 698}}
// Related features: "preview" 2 (gsa1.PREVIEW.BOARD: the board model alone, bind_preview.cpp), "surfaces" 3 (the board-time
// kinds "boardsnow" / "boardsand", bind_surfaces.cpp); gsa1.TICK_HOST_CAMERA (the host camera, session.cpp).
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>

#include "GarrysMod/Lua/Interface.h"

#include "../core/board.hpp"
#include "../core/session.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

#if defined(SA1_API_BOARD)

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;
namespace bd = gsa1::board;

namespace {

bool arg_absent(ILuaBase *L, int i)
{
    int t = L->GetType(i);
    return t == LT::Nil || t == LT::None;
}

// t[k] when present: a boolean (ok false: present and not a boolean)
bool opt_bool(ILuaBase *L, int t, const char *k, bool &out, bool &ok)
{
    L->PushString(k);
    L->RawGet(t);
    int ty = L->GetType(-1);
    bool present = ty != LT::Nil && ty != LT::None;
    if (present) {
        if (ty == LT::Bool) {
            out = L->GetBool(-1);
        } else {
            ok = false;
        }
    }
    L->Pop();
    return present;
}

// the board's character: a character of this session that may ride (Sonic or Tails, not a puppet, not faulted); otherwise
// nullptr with the failure pushed (ret)
gsa1::Character *board_char(ILuaBase *L, int32_t id, int &ret)
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
    if (c->puppet) {
        ret = push_nil_msg(L, bd::kReasonPuppet, "unsupported");
        return nullptr;
    }
    if (c->kind == bd::kKindSuperSonic) {
        ret = push_nil_msg(L, bd::kReasonSuper, "unsupported");
        return nullptr;
    }
    if (c->kind != bd::kKindSonic && c->kind != bd::kKindTails) {
        ret = push_nil_msg(L, bd::kReasonKind, "unsupported");
        return nullptr;
    }
    if (c->faulted) {
        ret = push_nil_msg(L, "the character's world faulted earlier; recreate the character", "fault");
        return nullptr;
    }
    return c;
}

// libsa1's answer of a board call; the state read again either way (the next BoardState sees the call's effect)
int board_result(ILuaBase *L, gsa1::Session *se, gsa1::Character *c, sa1_status st, const std::string &err)
{
    bd::refresh(se->ctx(), c->id, c->board);
    if (SA1_FAILED(st)) {
        return push_nil_msg(L, scrubbed(err), bd::code_of(st));
    }
    L->PushBool(true);
    return 1;
}

void raw_nil(ILuaBase *L, int t, const char *k)
{
    L->PushString(k);
    L->PushNil();
    L->RawSet(t);
}

// t[k] as a table (made when it is not one); returns its absolute index, left on the stack
int sub_table(ILuaBase *L, int t, const char *k)
{
    L->PushString(k);
    L->RawGet(t);
    if (L->IsType(-1, LT::Table)) {
        return L->Top();
    }
    L->Pop();
    L->PushString(k);
    L->CreateTable();
    L->RawSet(t);
    L->PushString(k);
    L->RawGet(t);
    return L->Top();
}

void raw_num_i(ILuaBase *L, int t, int i, double v)
{
    L->PushNumber(i);
    L->PushNumber(v);
    L->RawSet(t);
}

// a pair {a, b} at t[k]
void raw_pair(ILuaBase *L, int t, const char *k, double a, double b)
{
    L->PushString(k);
    L->CreateTable();
    int p = L->Top();
    raw_num_i(L, p, 1, a);
    raw_num_i(L, p, 2, b);
    L->RawSet(t);
}

// the board texture archives of a kind (the disc's MIW_B001 / SB_BOARD1 for Sonic, MTX_BOARD0 for Tails)
uint32_t board_archives(gsa1::Session *se, int32_t kind)
{
    if (!se || !se->ready()) {
        return 0;
    }
    uint32_t n = 0;
    for (uint32_t a = 0, na = se->texture_archives(kind); a < na; a++) {
        uint32_t count = 0;
        std::string e, name;
        if (se->texture_count(kind, a, count, e, &name)) {
            std::string u = gsa1::to_lower(name);
            if (u.compare(0, 8, "miw_b001") == 0 || u.compare(0, 9, "sb_board1") == 0 || u.compare(0, 10, "mtx_board0") == 0) {
                n++;
            }
        }
    }
    return n;
}

}  // namespace

// gsa1.Board(id, on [, opts]) -> true | nil, message, code
GSA1_FN(gsa1_board_Board)
{
    static const char *usage = "Board(id, on [, {terrain = gsa1.BOARD.TERRAIN_MAP | _SNOW | _SAND, push = bool, tails_jump = "
                               "bool, reuse = bool, remove = bool}])";
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !LUA->IsType(2, LT::Bool) ||
        (!arg_absent(LUA, 3) && !LUA->IsType(3, LT::Table))) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    bool on = LUA->GetBool(2);
    uint32_t terrain = bd::kTerrainMap, flags = 0;
    if (LUA->IsType(3, LT::Table)) {
        int t = absidx(LUA, 3);
        double v = 0.0;
        LUA->PushString("terrain");
        LUA->RawGet(t);
        int ty = LUA->GetType(-1);
        LUA->Pop();
        if (ty != LT::Nil && ty != LT::None) {
            if (!raw_get_number(LUA, t, "terrain", v) || v < 0.0 || v > 2.0 || std::floor(v) != v) {
                return push_nil_msg(LUA, usage, "bad_argument");
            }
            terrain = (uint32_t)v;
        }
        bool ok = true, b = false;
        if (opt_bool(LUA, t, "push", b, ok) && ok && b) flags |= bd::kFlagStartPush;
        b = false;
        if (opt_bool(LUA, t, "tails_jump", b, ok) && ok && b) flags |= bd::kFlagFaithfulExit;
        b = false;
        if (opt_bool(LUA, t, "reuse", b, ok) && ok && b) flags |= bd::kFlagReuseKept;
        b = false;
        if (opt_bool(LUA, t, "remove", b, ok) && ok && b) flags |= bd::kFlagRemoveOnExit;
        if (!ok) {
            return push_nil_msg(LUA, usage, "bad_argument");
        }
    }
    int ret = 0;
    gsa1::Character *c = board_char(LUA, id, ret);
    if (!c) {
        return ret;
    }
    gsa1::Session *se = session();
    std::string err;
    sa1_status st = on ? bd::call(se->ctx(), id, bd::kOn, terrain, flags, err)
                       : bd::call(se->ctx(), id, bd::kOff, bd::kTerrainMap, flags & bd::kFlagRemoveOnExit, err);
    return board_result(LUA, se, c, st, err);
}

// gsa1.BoardPush(id) -> true | nil, message, code
GSA1_FN(gsa1_board_BoardPush)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0)) {
        return push_nil_msg(LUA, "BoardPush(id)", "bad_argument");
    }
    int ret = 0;
    gsa1::Character *c = board_char(LUA, id, ret);
    if (!c) {
        return ret;
    }
    if (!(c->board.view.flags & bd::kBsOn)) {
        return push_nil_msg(LUA, bd::kReasonNotRiding, "unsupported");
    }
    gsa1::Session *se = session();
    std::string err;
    sa1_status st = bd::call(se->ctx(), id, bd::kPush, bd::kTerrainMap, 0u, err);
    return board_result(LUA, se, c, st, err);
}

// gsa1.BoardFree(id) -> true | nil, message, code
GSA1_FN(gsa1_board_BoardFree)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0)) {
        return push_nil_msg(LUA, "BoardFree(id)", "bad_argument");
    }
    int ret = 0;
    gsa1::Character *c = board_char(LUA, id, ret);
    if (!c) {
        return ret;
    }
    if (!(c->board.view.flags & bd::kBsKept)) {
        return push_nil_msg(LUA, bd::kReasonNoKept, "unsupported");
    }
    gsa1::Session *se = session();
    std::string err;
    sa1_status st = bd::call(se->ctx(), id, bd::kFree, bd::kTerrainMap, 0u, err);
    return board_result(LUA, se, c, st, err);
}

// gsa1.BoardState(id [, out]) -> out | nil, message, code
GSA1_FN(gsa1_board_BoardState)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || (!arg_absent(LUA, 2) && !LUA->IsType(2, LT::Table))) {
        return push_nil_msg(LUA, "BoardState(id [, out])", "bad_argument");
    }
    gsa1::Session *se = session();
    gsa1::Character *c = se ? se->get(id) : nullptr;
    if (!c) {
        return push_nil_msg(LUA, "no such character", "not_found");
    }
    int t = out_table(LUA, 2);
    const bd::View &v = c->board.view;
    const sa1_state_ex &s = c->st;
    raw_bool(LUA, t, "on", (v.flags & bd::kBsOn) != 0);
    raw_bool(LUA, t, "pending", (v.flags & bd::kBsPending) != 0);
    raw_bool(LUA, t, "held", (v.flags & bd::kBsHeld) != 0);
    raw_bool(LUA, t, "kept", (v.flags & bd::kBsKept) != 0);
    raw_bool(LUA, t, "settled", (v.flags & bd::kBsSettled) != 0);
    raw_bool(LUA, t, "board", v.board_task != 0);
    raw_num(LUA, t, "mode", s.mode);
    raw_num(LUA, t, "action", s.action);
    raw_num(LUA, t, "speed", std::isfinite(s.player_speed[0]) ? s.player_speed[0] : 0.0);
    raw_num(LUA, t, "terrain", v.terrain);
    raw_num(LUA, t, "push_steps", v.push_steps);
    raw_num(LUA, t, "kind", v.kind);
    raw_num(LUA, t, "variant", v.variant);
    raw_num(LUA, t, "x", v.pos[0]);
    raw_num(LUA, t, "y", v.pos[1]);
    raw_num(LUA, t, "z", v.pos[2]);
    float ang[3];
    bd::rotation_angles(v.rot, ang);
    raw_num(LUA, t, "pitch", ang[0]);
    raw_num(LUA, t, "yaw", ang[1]);
    raw_num(LUA, t, "roll", ang[2]);
    raw_num(LUA, t, "still", v.still_steps);
    raw_num(LUA, t, "jump", std::isfinite(v.saved_jmp_y_spd) ? v.saved_jmp_y_spd : 0.0);
    std::string reason;
    bool refused = bd::take_refusal(c->board, reason);
    raw_bool(LUA, t, "refused", refused);
    if (refused) {
        raw_str(LUA, t, "reason", reason);
    } else {
        raw_nil(LUA, t, "reason");
    }
    int32_t why = -1;
    uint32_t freed = bd::take_freed(c->board, why);
    raw_num(LUA, t, "freed", freed);
    raw_num(LUA, t, "freed_why", why);
    return 1;
}

// gsa1.BoardSounds(on) -> true | nil, message, code
GSA1_FN(gsa1_board_BoardSounds)
{
    if (!LUA->IsType(1, LT::Bool)) {
        return push_nil_msg(LUA, "BoardSounds(on)", "bad_argument");
    }
    gsa1::Session *se = session();
    if (se) {
        se->set_board_sounds(LUA->GetBool(1));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.BoardInfo([out]) -> out
GSA1_FN(gsa1_board_BoardInfo)
{
    gsa1::Session *se = session();
    int t = out_table(LUA, 1);
    raw_bool(LUA, t, "available", bd::kAvailable);
    raw_num(LUA, t, "version", 1);
    int k = sub_table(LUA, t, "kinds");
    raw_num_i(LUA, k, 1, bd::kKindSonic);
    raw_num_i(LUA, k, 2, bd::kKindTails);
    LUA->Pop();
    int x = sub_table(LUA, t, "textures");
    raw_num_i(LUA, x, bd::kKindSonic, board_archives(se, bd::kKindSonic));
    raw_num_i(LUA, x, bd::kKindTails, board_archives(se, bd::kKindTails));
    LUA->Pop();
    raw_bool(LUA, t, "rules", se ? se->audio().has_stage_rules() : false);
    raw_bool(LUA, t, "sounds", se ? se->board_sounds() : true);
    raw_num(LUA, t, "tones_dropped", se ? (double)se->board_tones_dropped() : 0.0);
    return 1;
}

namespace {

void board_open(ILuaBase *L, int t)
{
    L->PushString("BOARD");
    L->CreateTable();
    int c = L->Top();
    raw_num(L, c, "TERRAIN_MAP", bd::kTerrainMap);
    raw_num(L, c, "TERRAIN_SNOW", bd::kTerrainSnow);
    raw_num(L, c, "TERRAIN_SAND", bd::kTerrainSand);
    raw_num(L, c, "DRAW", bd::kDrawBoard);
    raw_num(L, c, "SETTLE_STEPS", bd::kSettleSteps);
    raw_pair(L, c, "SONIC_MODES", bd::kSonicModeFirst, bd::kSonicModeLast);
    raw_pair(L, c, "TAILS_MODES", bd::kTailsModeFirst, bd::kTailsModeLast);
    raw_num(L, c, "FREED_REMOVED", 0);
    raw_num(L, c, "FREED_FELL", 1);
    raw_num(L, c, "FREED_REPLACED", 2);
    raw_num(L, c, "FREED_FREE", 3);
    raw_pair(L, c, "SNOW_TONES", bd::kSnowToneFirst, bd::kSnowToneLast);
    raw_pair(L, c, "SAND_TONES", bd::kSandToneFirst, bd::kSandToneLast);
    L->RawSet(t);
}

const gsa1::FeatureFn k_board_fns[] = {
    {"Board", gsa1_board_Board},
    {"BoardPush", gsa1_board_BoardPush},
    {"BoardFree", gsa1_board_BoardFree},
    {"BoardState", gsa1_board_BoardState},
    {"BoardSounds", gsa1_board_BoardSounds},
    {"BoardInfo", gsa1_board_BoardInfo},
};

}  // namespace

// version 1 (0.9.5): Board, BoardPush, BoardFree, BoardState, BoardSounds, BoardInfo, gsa1.BOARD
GSA1_FEATURE(board, 1, k_board_fns, board_open, nullptr, gsa1::kCloseDefault);

#endif  // SA1_API_BOARD (a libsa1 without the board: no feature "board"; GSA1.HasFeature("board") is false)
