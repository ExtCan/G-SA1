// G-SA1 module: the character options feature "charopt" (round 0.9.1; libsa1 API 0.3, SA1_API_CHAROPT): the life
// counter across respawns (sadc docs/research/gsa1_070_drown.md E2 / G1), Amy's bird (gsa1_070_bird.md F1 / F4 with the
// review's R.4), Tails' tail blend (gsa1_rounds_plan.md 14.1h, the owner's answer) and "Characters can drown" (drown.md
// owner question 3). The addon's side is gsa1/feat/cl_charopt.lua (the Character page's options) and cl_character.lua
// (deaths, respawns).
//
// Lua API (feature version 1; GSA1.HasFeature("charopt")). id: a ticking character of this client (not a puppet):
//   gsa1.SetLives(id, n) -> lives | nil, message, code
//       The life counter of the character's world (B_8C752BE0; the HUD shows it), clamped to 0..127 like the game's
//       8C08A120; returns the value set. Before the first tick it is in place for the world's first step. Without a call
//       a world starts with the game's 4.
//   gsa1.GetLives(id) -> lives | nil      the counter now (sa1_state_ex.lives, read at the call)
//   gsa1.SetCompanion(id, companion, on) -> true | nil, message, code
//       gsa1.CHAROPT.COMPANION_BIRD: Amy's Birdie, the game's own task (8C0DECDA / 8C0DE964): made (on) or freed (off)
//       with the game's calls, against the game's gate; idempotent; kept for a world built later. "invalid argument"
//       for another kind than Amy, "unsupported" for a world whose player 0 is not that Amy (a follower world).
//   gsa1.Companion(id, companion) -> present (bool) | nil, message    the companion's task is in the world now
//   gsa1.SetGameOption(id, option, value) -> true | nil, message, code
//       gsa1.CHAROPT.TAILS_SNAP_TAILS: 1 = Tails' tails switch at once between the bent tails and the propeller (no
//       in-between morph), 0 = the game's morph (the default). A PC-only switch inside the lowered game code (SA1_GA);
//       any kind may set it (only Tails' code reads it).
//   gsa1.HoldAir(id) -> breath | nil, message, code
//       "Characters can drown" off: holds the game's air timer (playerwk.breathtimer) at 0 between ticks, so the
//       drowning countdown (it starts at 1080 steps under water) never begins and one that runs ends at once (the game's
//       own rule: the countdown task frees itself when the timer is under 60, as when the character gets air). Returns
//       the timer it found (steps). A host deviation behind an option, as SA1_COPT_NO_DEATH is; libsa1 has no option for
//       it yet (README "libsa1 API requests"), so it uses libsa1's bounded word access to the character's world (the
//       one the upgrade flags use, libsa1_internal_api.hpp) and checks the field against sa1_state_ex.breath_timer first.
//   gsa1.CHAROPT = {COMPANION_BIRD, TAILS_SNAP_TAILS, DEATH_OTHER, DEATH_HURT, DEATH_HOST, DEATH_DROWN, DEATH_ZONE,
//       EVENT_DEATH, EVENT_RESTART, EVENT_TIME_UP, LIVES_START (4), LIVES_MAX (127), BREATH_COUNTDOWN (1080)}
#include <cstring>
#include <string>

#include "GarrysMod/Lua/Interface.h"

#include "../core/session.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;

namespace {

// the game's player work pointers (1ST_READ data; LIB src/world/sa1_world.h SA1G_ADDR_PLAYER_*): playerpwp[8], and
// playermwp[8] whose work.pwp is the fallback libsa1's own sa1g_world_player takes
const uint32_t kPlayerPwp = 0x8C78C668u;
const uint32_t kPlayerMwp = 0x8C78C628u;
const uint32_t kBreathOffset = 0x0Cu;          // playerwk.breathtimer (Sint16; waittimer is the next half word)

// the session's context when the disc is loaded, else nullptr
sa1_context *ready_ctx()
{
    gsa1::Session *se = session();
    return se && se->ready() ? se->ctx() : nullptr;
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

int status_fail(ILuaBase *L, sa1_context *ctx, sa1_status st, const char *what)
{
    const char *e = ctx ? sa1_last_error(ctx) : nullptr;
    std::string m = e && *e ? std::string(e) : std::string(sa1_status_string(st));
    if (m.compare(0, std::strlen(what), what) != 0) {
        m = std::string(what) + ": " + m;       // libsa1's message names its function already
    }
    return push_nil_msg(L, scrubbed(m), sa1_status_string(st));
}

// on / off: a boolean or a number (0 = off)
bool arg_onoff(ILuaBase *L, int i, int32_t &out)
{
    if (L->IsType(i, LT::Bool)) {
        out = L->GetBool(i) ? 1 : 0;
        return true;
    }
    double d = 0.0;
    if (!arg_number(L, i, d)) {
        return false;
    }
    out = d != 0.0 ? 1 : 0;
    return true;
}

}  // namespace

// gsa1.SetLives(id, n) -> lives | nil, message, code
GSA1_FN(gsa1_charopt_SetLives)
{
    int32_t id = 0, n = 0;
    if (!char_arg(LUA, 1, id) || !arg_int(LUA, 2, n, -1000000.0, 1000000.0)) {
        return push_nil_msg(LUA, "SetLives(id of a character of yours, lives)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_status st = sa1_character_set_lives(ctx, id, n);
    if (st != SA1_OK) {
        return status_fail(LUA, ctx, st, "sa1_character_set_lives");
    }
    LUA->PushNumber(n < 0 ? 0 : (n > 127 ? 127 : n));
    return 1;
}

// gsa1.GetLives(id) -> lives | nil
GSA1_FN(gsa1_charopt_GetLives)
{
    int32_t id = 0;
    sa1_context *ctx = ready_ctx();
    if (!char_arg(LUA, 1, id) || !ctx) {
        LUA->PushNil();
        return 1;
    }
    sa1_state_ex s;
    std::memset(&s, 0, sizeof s);
    s.struct_size = sizeof s;
    if (sa1_character_state_ex(ctx, id, &s) != SA1_OK) {
        LUA->PushNil();
        return 1;
    }
    LUA->PushNumber(s.lives);
    return 1;
}

// gsa1.SetCompanion(id, companion, on) -> true | nil, message, code
GSA1_FN(gsa1_charopt_SetCompanion)
{
    int32_t id = 0, companion = 0, on = 0;
    if (!char_arg(LUA, 1, id) || !arg_int(LUA, 2, companion, 0, 255) || !arg_onoff(LUA, 3, on)) {
        return push_nil_msg(LUA, "SetCompanion(id of a character of yours, companion, on)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_status st = sa1_character_set_companion(ctx, id, (uint32_t)companion, on);
    if (st != SA1_OK) {
        return status_fail(LUA, ctx, st, "sa1_character_set_companion");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.Companion(id, companion) -> present | nil, message, code
GSA1_FN(gsa1_charopt_Companion)
{
    int32_t id = 0, companion = 0;
    if (!char_arg(LUA, 1, id) || !arg_int(LUA, 2, companion, 0, 255)) {
        return push_nil_msg(LUA, "Companion(id of a character of yours, companion)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    int32_t present = 0;
    sa1_status st = sa1_character_companion(ctx, id, (uint32_t)companion, &present);
    if (st != SA1_OK) {
        return status_fail(LUA, ctx, st, "sa1_character_companion");
    }
    LUA->PushBool(present != 0);
    return 1;
}

// gsa1.SetGameOption(id, option, value) -> true | nil, message, code
GSA1_FN(gsa1_charopt_SetGameOption)
{
    int32_t id = 0, option = 0, value = 0;
    if (!char_arg(LUA, 1, id) || !arg_int(LUA, 2, option, 0, 255) || !arg_int(LUA, 3, value, -1000000.0, 1000000.0)) {
        return push_nil_msg(LUA, "SetGameOption(id of a character of yours, option, value)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_status st = sa1_character_set_game_option(ctx, id, (uint32_t)option, value);
    if (st != SA1_OK) {
        return status_fail(LUA, ctx, st, "sa1_character_set_game_option");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.HoldAir(id) -> breath | nil, message, code
GSA1_FN(gsa1_charopt_HoldAir)
{
    int32_t id = 0;
    gsa1::Character *c = char_arg(LUA, 1, id);
    if (!c) {
        return push_nil_msg(LUA, "HoldAir(id of a character of yours)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    struct sa1g_world *w = sa1_character_world(ctx, id);
    if (!w) {
        LUA->PushNumber(0);             // no world yet (it is built at the first tick): no timer to hold
        return 1;
    }
    uint32_t pwp = 0, word = 0;
    if (sa1g_world_rd32(w, kPlayerPwp, &pwp) != 0 || pwp == 0 || sa1g_world_rd32(w, pwp + kBreathOffset, &word) != 0) {
        uint32_t mwp = 0;
        pwp = 0;
        if (sa1g_world_rd32(w, kPlayerMwp, &mwp) != 0 || mwp == 0 || sa1g_world_rd32(w, mwp, &pwp) != 0 || pwp == 0 ||
            sa1g_world_rd32(w, pwp + kBreathOffset, &word) != 0) {
            LUA->PushNumber(0);         // no player work (yet): nothing to hold
            return 1;
        }
    }
    int32_t breath = (int16_t)(uint16_t)(word & 0xFFFFu);
    // the field must be the one sa1_state_ex reports (refreshed after every tick): never write a word that is not it
    if (breath != c->st.breath_timer) {
        return push_nil_msg(LUA, gsa1::format("the air timer was not where it was expected (%d, the state says %d)",
                                              (int)breath, (int)c->st.breath_timer), "mismatch");
    }
    if (breath != 0 && sa1g_world_wr32(w, pwp + kBreathOffset, word & 0xFFFF0000u) != 0) {
        return push_nil_msg(LUA, "the air timer could not be written", "failed");
    }
    c->st.breath_timer = 0;
    LUA->PushNumber(breath);
    return 1;
}

namespace {

void charopt_open(ILuaBase *L, int t)
{
    L->PushString("CHAROPT");
    L->CreateTable();
    int c = L->Top();
    raw_num(L, c, "COMPANION_BIRD", SA1_COMPANION_BIRD);
    raw_num(L, c, "TAILS_SNAP_TAILS", SA1_GOPT_TAILS_SNAP_TAILS);
    raw_num(L, c, "DEATH_OTHER", SA1_DEATH_OTHER);
    raw_num(L, c, "DEATH_HURT", SA1_DEATH_HURT);
    raw_num(L, c, "DEATH_HOST", SA1_DEATH_HOST);
    raw_num(L, c, "DEATH_DROWN", SA1_DEATH_DROWN);
    raw_num(L, c, "DEATH_ZONE", SA1_DEATH_ZONE);
    raw_num(L, c, "EVENT_DEATH", SA1_EVENT_DEATH);
    raw_num(L, c, "EVENT_RESTART", SA1_EVENT_RESTART);
    raw_num(L, c, "EVENT_TIME_UP", SA1_EVENT_TIME_UP);
    raw_num(L, c, "LIVES_START", 4);
    raw_num(L, c, "LIVES_MAX", 127);
    raw_num(L, c, "BREATH_COUNTDOWN", 0x438);
    L->RawSet(t);
}

const gsa1::FeatureFn k_charopt_fns[] = {
    {"SetLives", gsa1_charopt_SetLives},
    {"GetLives", gsa1_charopt_GetLives},
    {"SetCompanion", gsa1_charopt_SetCompanion},
    {"Companion", gsa1_charopt_Companion},
    {"SetGameOption", gsa1_charopt_SetGameOption},
    {"HoldAir", gsa1_charopt_HoldAir},
};

}  // namespace

GSA1_FEATURE(charopt, 1, k_charopt_fns, charopt_open, nullptr, gsa1::kCloseDefault);
