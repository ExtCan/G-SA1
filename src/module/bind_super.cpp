// G-SA1 module: the Super Sonic feature "super" (round 6a in round 0.9.3: sadc docs/research/gsa1_rounds_plan.md 11.3
// with the owner's answer 14.1a, gsa1_090_plan.md 7.5; research super_sonic.md 4.3-4.7 with its Review R.4; libsa1 API
// 0.4, the "Super Sonic (API 0.4)" section of libsa1.h). The addon's side is gsa1/feat/{sh,cl}_super.lua.
//
// What libsa1 gives: Super Sonic (kind 8) ticks - a Sonic world on the Perfect Chaos stage (level 19 act 0) in which the
// game turns him Super itself (the stage's trigger task sends the game's request 46 in its second step), with the ring
// drain (the boss's 0C917088: a ring a second, back to normal Sonic at 0 rings, the game's request 47), the revert fix and
// his archives (SUPERSONIC 0, OBJ_REGULAR 1, EFF_REGULAR 2, CON_REGULAR 3, SONIC 4, SON_EFF 5); and a Sonic created
// SA1_CREATE_SUPER_CAPABLE (his Super forms loaded: SA1_LOAD_SUPER_FORMS, the SUPERSONIC archive as his archive 5) turns
// Super in play through sa1_character_order(SA1_ORDER_SUPER) - the game's request 46 in his own world - and back with
// SA1_ORDER_NORMAL, keeping position, facing, speed, state and rings (owner 14.1a). How a world is made: gsa1.Create's
// extras table (gsa1_module.cpp: create_flags, super_flags, start_rings; src/core/session.hpp CreateExtra).
//
// Lua API (feature version 1; GSA1.HasFeature("super")). id: a ticking character of this client (not a puppet):
//   gsa1.SuperOrder(id, order) -> true | nil, message, code
//       gsa1.SUPER.ORDER_SUPER (46) / ORDER_NORMAL (47): the game's player request in the character's world now, taken at
//       its next step (in almost every state; the super states ignore a second 46). Only for kind 8 and a SUPER_CAPABLE
//       Sonic; code "unsupported" otherwise, "fault" for a faulted world, "bad_argument", "not_ready". The ring rule (50
//       rings and a button) is the addon's: libsa1 does not check rings.
//   gsa1.SuperState(id [, out]) -> out | nil
//       {super (player 0 is Super now: SA1_STATE_SUPER), capable (orders work), kind, rings, equipment, mode, action,
//        speed (the game's forward speed, Hammer units per second), changes (form changes seen by the module's ticks),
//        change_step (the world's step after the last one), step, create_flags, super_flags, super_given, water_floor,
//        start_rings (-1: the game's; kind 8: libsa1's 50), tones_muted (Perfect Chaos stage tones of this world kept out
//        of the mixer)} - read from the state after the last tick, no allocation besides the table.
//   gsa1.SuperInfo([out]) -> out: {api (libsa1 has Super Sonic), playable (kind 8 can be created), forms (Sonic's Super
//        forms are loaded: SUPER_CAPABLE works), ready (the disc is loaded), stage_tones (true: Perfect Chaos stage tones
//        of Super worlds are kept out of the mixer), tones_muted (all of them since the disc loaded)}
//   gsa1.SUPER = {KIND, ORDER_SUPER, ORDER_NORMAL, NO_DRAIN, KEEP_AT_ZERO, FAITHFUL_REVERT, SEA_PLANE, CREATE_SUPER,
//        CREATE_SUPER_CAPABLE, CREATE_WATER_FLOOR, STATE_SUPER, EQUIPMENT (0x8000), START_RINGS (50), DRAIN_STEPS (60),
//        STAGE_TONES_FIRST, STAGE_TONES_LAST, WHOOSH_SLOW (1035), WHOOSH_FAST (1036), MUSIC_THEME (86 SPRSONIC.ADX),
//        MUSIC_CHAOS_1 (22), MUSIC_CHAOS_2 (23)}
//
// Feature version 2 (round 0.9.3a: sadc docs/research/super_general_design.md 6.9 with its Review R.4; libsa1.h "THE
// GENERAL FORM", SA1_API_SUPER_GENERAL). Two Super Sonics: "Vs. Perfect Chaos" (kind 8, as in 0.9.3) and "General
// Gameplay" (a Sonic world created SUPER_CAPABLE with super_flags GENERAL: Sonic's own moves while Super, on the host's
// stage, never level 19); a transformation-capable Sonic is a General world too.
//   gsa1.SuperOption(id, option, value) -> true | nil, message, code
//       sa1_character_set_super_option: gsa1.SUPER.SUPOPT_SPEED (SPEED_GAME / RUN / HALF / SONIC), SUPOPT_NO_AURA (0 / 1),
//       SUPOPT_VOICE (a tone, 0 = none), SUPOPT_SUPER_EFFECTS (0 / 1; 0.9.4a: the bits SUPER_EFFECTS_CLONES | _DUST, 0..3),
//       0.9.4a: SUPOPT_SUPER_ANIMS (0 / 1: Super poses), SUPOPT_LSD_GOLD (0 / 1: the golden Light Speed charge). Applies
//       at once (between ticks); kept for a world built later. code "unsupported" (SPEED / NO_AURA / SUPER_EFFECTS /
//       SUPER_ANIMS / LSD_GOLD on a world that is not General, kind 8 included; VOICE on one that cannot turn Super),
//       "bad_argument", "not_found", "fault", "not_ready"
//   gsa1.SuperGameOption(id, option, value) -> true | nil, message, code
//       sa1_character_set_game_option for the two Super game options only: gsa1.SUPER.GOPT_IDLE_BY_FORM (0 / 1: Sonic's
//       idle voices by his form) and GOPT_AURA_ANIM (AURA_DREAMCAST 0 / AURA_CALM 1 / AURA_SLOW 2); other options:
//       "bad_argument"
//   gsa1.SuperVoicePreview(tone [, id]) -> true | nil, message, code
//       plays the tone once through the mixer (Session::preview_sound: the game's SA1_EVENT_SOUND, as the character's own
//       sound when id is a character of yours), so the page's Preview button works without transforming; "not_ready"
//       while the sound banks are not open
//   gsa1.SuperVoiceClip(voice [, id]) -> true | nil, message, code (0.9.3b)
//       plays voice clip `voice` (an entry of the voice archive: the game's PlayVoice, an SA1_EVENT_VOICE) once through the
//       mixer (Session::preview_voice); the owner's "HM!" is Super Sonic's line 396, which the Lua side plays at the
//       transformation when it is the chosen voice (libsa1's own transformation voice takes tones only)
//   gsa1.SuperState gains general (the world is a General one: super_flags GENERAL) and start (SA1_SUPER_START given)
//   gsa1.SuperInfo gains general (libsa1 has the General form)
//   gsa1.SUPER gains GENERAL, START, WATER_WHILE_SUPER, START_NORMAL, SUPOPT_SPEED / NO_AURA / VOICE / SUPER_EFFECTS,
//       SPEED_GAME / RUN / HALF / SONIC, GOPT_IDLE_BY_FORM, GOPT_AURA_ANIM, AURA_DREAMCAST / CALM / SLOW, WATER_TOLERANCE,
//       VOICE_DEFAULT (1116, Sonic's push grunt: 0.9.3a's tone default; since 0.9.3b the addon's default is Super
//       Sonic's voice clip 396, played through SuperVoiceClip)
// Feature version 4 (round 0.9.4a: sadc docs/research/super2_plan.md 6.4 with its review; libsa1.h "THE GENERAL FORM",
// SA1_API_SUPER_POLISH; libsa1_audio.h version 5): the owner's three notes on 0.9.3a.
//   gsa1.SuperOption also takes SUPOPT_SUPER_ANIMS (0 / 1: the game's own Super Sonic motions for standing and moving -
//       the floating stand 130 and the flying run 131-134, lifted to the game's placement; Sonic's foot-tapping idle and
//       every other move stay Sonic's on the golden body), SUPOPT_LSD_GOLD (0 / 1: the Light Speed charge's plain sparkles
//       and streaks drawn with libsa1's golden texture variant, the charged glow in the complementary colours of the
//       game's blue; the Crystal Ring's green ones stay green: owner answer O3) and SUPOPT_SUPER_EFFECTS as bits 0..3
//       (SUPER_EFFECTS_CLONES 1: the golden trail and ball after-images; SUPER_EFFECTS_DUST 2: the spin dash sparks take
//       the after-images' golden texture); all three General worlds only ("unsupported" for kind 8)
//   gsa1.SuperWhoosh(on) -> true | nil, message, code ("unsupported": this module's libsa1 has no stage rules)
//       the aura's whoosh (below) on or off for every super-capable character, at once
//   gsa1.SuperInfo gains whoosh (libsa1 has stage rules), whoosh_on (the option), whoosh_bank ("absent", "loading", "ready",
//       "failed": the Perfect Chaos stage's banks in the open sound banks; "closed" while the banks are not open),
//       whoosh_characters (super-capable characters whose whoosh is routed); gsa1.SuperState gains whoosh (this one's is)
//   gsa1.SUPER gains SUPOPT_SUPER_ANIMS, SUPOPT_LSD_GOLD, SUPER_EFFECTS_CLONES, SUPER_EFFECTS_DUST, DRAW_SUPER_GOLD,
//       TEXTURE_VARIANT_SUPER_GOLD (from libsa1's macros) and WHOOSH_STAGE (19); gsa1.WRAP_GOLD and gsa1.Texture's variant
//       are the base module's (gsa1_module.cpp)
// Sound: the aura's whoosh (tones 1035 / 1036 above speed 7 / 13, B_CHAOS7's aura exec) belongs to the Perfect Chaos
// stage's sound bank (CHAOS7B.MLT bank 5); the module's banks are Emerald Coast's. Since 0.9.4a every super-capable
// character holds a libsa1 stage rule {19, 1035, 1036} (Audio's slot kRuleWhoosh, re-applied to every new mixer), so the
// mixer plays them from CHAOS7B, read on libsa1's loader thread; Session::take_events still keeps the rest of the stage
// range (the stage's ambient loop 1033, the boss tones) out of the mixer, and the whoosh too while the option is off, a
// rule was refused or the libsa1 has no stage rules (super2_sound.md 7, review R.14) - the events always reach Lua.
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

// a ticking character of the session (not a puppet) by its Lua id
gsa1::Character *super_char_arg(ILuaBase *L, int i, int32_t &id)
{
    gsa1::Session *se = session();
    if (!se || !arg_int(L, i, id, 1, 2147483647.0)) {
        return nullptr;
    }
    gsa1::Character *c = se->get(id);
    return c && !c->puppet ? c : nullptr;
}

// the create's super flags of the General form (0 with a libsa1 before round 0.9.3a)
#if defined(SA1_API_SUPER_GENERAL)
const uint32_t kGeneralFlag = SA1_SUPER_GENERAL, kStartFlag = SA1_SUPER_START;
#else
const uint32_t kGeneralFlag = 0u, kStartFlag = 0u;
#endif

const char *super_code(sa1_status st)
{
    switch (st) {
    case SA1_ERR_UNSUPPORTED: return "unsupported";
    case SA1_ERR_NOT_FOUND: return "not_found";
    case SA1_ERR_GAME_FAULT:
    case SA1_ERR_NOT_IMPLEMENTED: return "fault";
    case SA1_ERR_INVALID_ARGUMENT: return "bad_argument";
    default: return "error";
    }
}

}  // namespace

// gsa1.SuperOrder(id, order) -> true | nil, message, code
GSA1_FN(gsa1_super_SuperOrder)
{
    int32_t id = 0, order = 0;
    gsa1::Character *c = super_char_arg(LUA, 1, id);
    if (!c || !arg_int(LUA, 2, order, 0, 255)) {
        return push_nil_msg(LUA, "SuperOrder(id of a character of yours, gsa1.SUPER.ORDER_SUPER | ORDER_NORMAL)",
                            "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_status st = se->order(id, order);
    if (SA1_FAILED(st)) {
        return push_nil_msg(LUA, scrubbed(se->last_error()), super_code(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.SuperState(id [, out]) -> out | nil
GSA1_FN(gsa1_super_SuperState)
{
    int32_t id = 0;
    gsa1::Character *c = super_char_arg(LUA, 1, id);
    if (!c) {
        LUA->PushNil();
        return 1;
    }
    int t = out_table(LUA, 2);
    const sa1_state_ex &s = c->st;
    raw_bool(LUA, t, "super", c->super);
    raw_bool(LUA, t, "capable", c->super_capable);
    raw_num(LUA, t, "kind", c->kind);
    raw_num(LUA, t, "rings", s.rings);
    raw_num(LUA, t, "equipment", s.equipment & 0xFFFFu);
    raw_num(LUA, t, "mode", s.mode);
    raw_num(LUA, t, "action", s.action);
    // playerwk.spd.x (SA1 units per 60 Hz step) in Hammer units per second (4 HU per unit)
    raw_num(LUA, t, "speed", (double)s.player_speed[0] * 4.0 * 60.0);
    raw_num(LUA, t, "changes", c->super_changes);
    raw_num(LUA, t, "change_step", c->super_step);
    raw_num(LUA, t, "step", s.step);
    raw_num(LUA, t, "create_flags", c->create_extra);
    raw_num(LUA, t, "super_flags", c->super_flags);
    raw_bool(LUA, t, "super_given", c->super_given);
#if defined(SA1_API_SUPER)
    raw_bool(LUA, t, "water_floor", (c->create_extra & SA1_CREATE_WATER_FLOOR) != 0);
#else
    raw_bool(LUA, t, "water_floor", false);
#endif
    raw_num(LUA, t, "start_rings", c->start_rings);
    raw_num(LUA, t, "tones_muted", (double)c->stage_tones_muted);
    // 0.9.3a: the General form (from the create's super flags)
    raw_bool(LUA, t, "general", (c->super_flags & kGeneralFlag) != 0);
    raw_bool(LUA, t, "start", (c->super_flags & kStartFlag) != 0);
    // 0.9.4a: this character's whoosh goes to the mixer (its stage rule holds)
    gsa1::Session *se = session();
    raw_bool(LUA, t, "whoosh", se && c->super_capable && se->whoosh_routed(id));
    return 1;
}

namespace {

// 0.9.4a: the Perfect Chaos stage's banks in the open sound banks (Audio::stage_state)
const char *bank_state_name(int32_t s)
{
#if defined(SA1_AUDIO_HAS_STAGE_RULES)
    switch (s) {
    case SA1_AUDIO_STAGE_ABSENT: return "absent";
    case SA1_AUDIO_STAGE_LOADING: return "loading";
    case SA1_AUDIO_STAGE_READY: return "ready";
    case SA1_AUDIO_STAGE_FAILED: return "failed";
    default: break;
    }
#endif
    return s < 0 ? "closed" : "absent";
}

}  // namespace

// gsa1.SuperInfo([out]) -> out
GSA1_FN(gsa1_super_SuperInfo)
{
    gsa1::Session *se = session();
    int t = out_table(LUA, 1);
    raw_bool(LUA, t, "api", gsa1::kSuperApi);
    raw_bool(LUA, t, "playable", ((gsa1::playable_kinds() >> gsa1::kKindSuperSonic) & 1u) != 0);
    raw_bool(LUA, t, "ready", se && se->ready());
    raw_bool(LUA, t, "forms", se && se->super_forms());
    raw_bool(LUA, t, "stage_tones", se ? se->stage_tones_muted() : true);
    raw_num(LUA, t, "tones_muted", se ? (double)se->stage_tones_dropped() : 0.0);
    raw_bool(LUA, t, "general", gsa1::kSuperGeneralApi);
    // 0.9.4a: the aura's whoosh (libsa1's stage rules)
    raw_bool(LUA, t, "whoosh", se && se->audio().has_stage_rules());
    raw_bool(LUA, t, "whoosh_on", se ? se->super_whoosh() : true);
    raw_str(LUA, t, "whoosh_bank", bank_state_name(se ? se->audio().stage_state(gsa1::kStagePerfectChaos) : -1));
    raw_num(LUA, t, "whoosh_characters", se ? se->whoosh_characters() : 0);
#if defined(SA1_API_SUPER_POLISH)
    raw_bool(LUA, t, "polish", true);
#else
    raw_bool(LUA, t, "polish", false);
#endif
    return 1;
}

// gsa1.SuperWhoosh(on) -> true | nil, message, code
GSA1_FN(gsa1_super_SuperWhoosh)
{
    if (!LUA->IsType(1, LT::Bool) && !LUA->IsType(1, LT::Number)) {
        return push_nil_msg(LUA, "SuperWhoosh(on: a boolean)", "bad_argument");
    }
    bool on = LUA->IsType(1, LT::Bool) ? LUA->GetBool(1) : LUA->GetNumber(1) != 0.0;
    gsa1::Session *se = session();
    if (!se) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    if (!se->set_super_whoosh(on)) {
        return push_nil_msg(LUA, "this module's libsa1 has no stage rules (libsa1_audio.h version 5): the whoosh stays "
                                 "silent", "unsupported");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.SuperOption(id, option, value) -> true | nil, message, code
GSA1_FN(gsa1_super_SuperOption)
{
    int32_t id = 0, option = 0, value = 0;
    gsa1::Character *c = super_char_arg(LUA, 1, id);
    if (!c || !arg_int(LUA, 2, option, 0, 255) || !arg_int(LUA, 3, value, -1000000.0, 1000000.0)) {
        return push_nil_msg(LUA, "SuperOption(id of a character of yours, gsa1.SUPER.SUPOPT_*, value)", "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
#if defined(SA1_API_SUPER_GENERAL)
    sa1_status st = sa1_character_set_super_option(se->ctx(), id, (uint32_t)option, value);
    if (SA1_FAILED(st)) {
        const char *e = sa1_last_error(se->ctx());
        return push_nil_msg(LUA, scrubbed(e && *e ? e : sa1_status_string(st)), super_code(st));
    }
    LUA->PushBool(true);
    return 1;
#else
    return push_nil_msg(LUA, "this libsa1 has no General Super Sonic (round 0.9.3a)", "unsupported");
#endif
}

// gsa1.SuperGameOption(id, option, value) -> true | nil, message, code
GSA1_FN(gsa1_super_SuperGameOption)
{
    int32_t id = 0, option = 0, value = 0;
    gsa1::Character *c = super_char_arg(LUA, 1, id);
    if (!c || !arg_int(LUA, 2, option, 0, 255) || !arg_int(LUA, 3, value, -1000000.0, 1000000.0)) {
        return push_nil_msg(LUA, "SuperGameOption(id of a character of yours, gsa1.SUPER.GOPT_*, value)", "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
#if defined(SA1_API_SUPER_GENERAL)
    if (option != (int32_t)SA1_GOPT_SUPER_IDLE_BY_FORM && option != (int32_t)SA1_GOPT_SUPER_AURA_ANIM) {
        return push_nil_msg(LUA, "SuperGameOption: only gsa1.SUPER.GOPT_IDLE_BY_FORM and GOPT_AURA_ANIM", "bad_argument");
    }
    sa1_status st = sa1_character_set_game_option(se->ctx(), id, (uint32_t)option, value);
    if (SA1_FAILED(st)) {
        const char *e = sa1_last_error(se->ctx());
        return push_nil_msg(LUA, scrubbed(e && *e ? e : sa1_status_string(st)), super_code(st));
    }
    LUA->PushBool(true);
    return 1;
#else
    return push_nil_msg(LUA, "this libsa1 has no Super game options (round 0.9.3a)", "unsupported");
#endif
}

// gsa1.SuperVoicePreview(tone [, id]) -> true | nil, message, code
GSA1_FN(gsa1_super_SuperVoicePreview)
{
    int32_t tone = 0, id = 0;
    if (!arg_int(LUA, 1, tone, 1, 2047)) {
        return push_nil_msg(LUA, "SuperVoicePreview(tone 1..2047 [, id])", "bad_argument");
    }
    int t2 = LUA->GetType(2);
    if (t2 != LT::Nil && t2 != LT::None && !super_char_arg(LUA, 2, id)) {
        return push_nil_msg(LUA, "SuperVoicePreview(tone, id of a character of yours)", "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se || !se->preview_sound(id, (uint32_t)tone)) {
        return push_nil_msg(LUA, "the sound is not ready (the sound banks are not open)", "not_ready");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.SuperVoiceClip(voice [, id]) -> true | nil, message, code
GSA1_FN(gsa1_super_SuperVoiceClip)
{
    int32_t voice = 0, id = 0;
    if (!arg_int(LUA, 1, voice, 0, 4095)) {
        return push_nil_msg(LUA, "SuperVoiceClip(voice 0..4095 [, id])", "bad_argument");
    }
    int t2 = LUA->GetType(2);
    if (t2 != LT::Nil && t2 != LT::None && !super_char_arg(LUA, 2, id)) {
        return push_nil_msg(LUA, "SuperVoiceClip(voice, id of a character of yours)", "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se || !se->preview_voice(id, (uint32_t)voice)) {
        return push_nil_msg(LUA, "the voice is not ready (the sound banks are not open)", "not_ready");
    }
    LUA->PushBool(true);
    return 1;
}

namespace {

void super_open(ILuaBase *L, int t)
{
    L->PushString("SUPER");
    L->CreateTable();
    int c = L->Top();
    raw_num(L, c, "KIND", gsa1::kKindSuperSonic);
#if defined(SA1_API_SUPER)
    raw_num(L, c, "ORDER_SUPER", SA1_ORDER_SUPER);
    raw_num(L, c, "ORDER_NORMAL", SA1_ORDER_NORMAL);
    raw_num(L, c, "NO_DRAIN", SA1_SUPER_NO_DRAIN);
    raw_num(L, c, "KEEP_AT_ZERO", SA1_SUPER_KEEP_AT_ZERO);
    raw_num(L, c, "FAITHFUL_REVERT", SA1_SUPER_FAITHFUL_REVERT);
    raw_num(L, c, "SEA_PLANE", SA1_SUPER_SEA_PLANE);
    raw_num(L, c, "CREATE_SUPER", SA1_CREATE_SUPER);
    raw_num(L, c, "CREATE_SUPER_CAPABLE", SA1_CREATE_SUPER_CAPABLE);
    raw_num(L, c, "CREATE_WATER_FLOOR", SA1_CREATE_WATER_FLOOR);
    raw_num(L, c, "STATE_SUPER", SA1_STATE_SUPER);
#endif
    raw_num(L, c, "EQUIPMENT", 0x8000);
    raw_num(L, c, "START_RINGS", 50);
    raw_num(L, c, "DRAIN_STEPS", 60);
    raw_num(L, c, "STAGE_TONES_FIRST", gsa1::kStageTonesFirst);
    raw_num(L, c, "STAGE_TONES_LAST", gsa1::kStageTonesLast);
    raw_num(L, c, "WHOOSH_SLOW", 1035);
    raw_num(L, c, "WHOOSH_FAST", 1036);
    // the music the game has for him (the track table 0x8C5FB8A8: jukebox.md; super_sonic.md Review R.2.7)
    raw_num(L, c, "MUSIC_THEME", 86);
    raw_num(L, c, "MUSIC_CHAOS_1", 22);
    raw_num(L, c, "MUSIC_CHAOS_2", 23);
    // 0.9.3a (feature version 2): the General form, the Super options, the Super game options
#if defined(SA1_API_SUPER_GENERAL)
    raw_num(L, c, "GENERAL", SA1_SUPER_GENERAL);
    raw_num(L, c, "START", SA1_SUPER_START);
    raw_num(L, c, "WATER_WHILE_SUPER", SA1_SUPER_WATER_WHILE_SUPER);
    raw_num(L, c, "START_NORMAL", SA1_SUPER_START_NORMAL);
    raw_num(L, c, "WATER_TOLERANCE", SA1_SUPER_WATER_TOLERANCE);
    raw_num(L, c, "SUPOPT_SPEED", SA1_SUPOPT_SPEED);
    raw_num(L, c, "SUPOPT_NO_AURA", SA1_SUPOPT_NO_AURA);
    raw_num(L, c, "SUPOPT_VOICE", SA1_SUPOPT_VOICE);
    raw_num(L, c, "SUPOPT_SUPER_EFFECTS", SA1_SUPOPT_SUPER_EFFECTS);
    raw_num(L, c, "SPEED_GAME", SA1_SUPER_SPEED_GAME);
    raw_num(L, c, "SPEED_RUN", SA1_SUPER_SPEED_RUN);
    raw_num(L, c, "SPEED_HALF", SA1_SUPER_SPEED_HALF);
    raw_num(L, c, "SPEED_SONIC", SA1_SUPER_SPEED_SONIC);
    raw_num(L, c, "GOPT_IDLE_BY_FORM", SA1_GOPT_SUPER_IDLE_BY_FORM);
    raw_num(L, c, "GOPT_AURA_ANIM", SA1_GOPT_SUPER_AURA_ANIM);
    raw_num(L, c, "AURA_DREAMCAST", SA1_AURA_ANIM_DREAMCAST);
    raw_num(L, c, "AURA_CALM", SA1_AURA_ANIM_CALM);
    raw_num(L, c, "AURA_SLOW", SA1_AURA_ANIM_SLOW);
#endif
    // Sonic's push grunt (code_8C0A77BC.c:377: the game's "Hm!"), the design's default transformation voice (4.9)
    raw_num(L, c, "VOICE_DEFAULT", 1116);
    // 0.9.4a (feature version 4): the Super poses, the golden Light Speed charge, the golden spin dash sparks, the whoosh
#if defined(SA1_API_SUPER_POLISH)
    raw_num(L, c, "SUPOPT_SUPER_ANIMS", SA1_SUPOPT_SUPER_ANIMS);
    raw_num(L, c, "SUPOPT_LSD_GOLD", SA1_SUPOPT_LSD_GOLD);
    raw_num(L, c, "SUPER_EFFECTS_CLONES", SA1_SUPER_EFFECTS_CLONES);
    raw_num(L, c, "SUPER_EFFECTS_DUST", SA1_SUPER_EFFECTS_DUST);
    raw_num(L, c, "DRAW_SUPER_GOLD", SA1_DRAW_SUPER_GOLD);
    raw_num(L, c, "TEXTURE_VARIANT_SUPER_GOLD", SA1_TEXTURE_VARIANT_SUPER_GOLD);
#endif
    raw_num(L, c, "WHOOSH_STAGE", gsa1::kStagePerfectChaos);
    L->RawSet(t);
}

const gsa1::FeatureFn k_super_fns[] = {
    {"SuperOrder", gsa1_super_SuperOrder},
    {"SuperState", gsa1_super_SuperState},
    {"SuperInfo", gsa1_super_SuperInfo},
    {"SuperOption", gsa1_super_SuperOption},
    {"SuperGameOption", gsa1_super_SuperGameOption},
    {"SuperVoicePreview", gsa1_super_SuperVoicePreview},
    {"SuperVoiceClip", gsa1_super_SuperVoiceClip},
    {"SuperWhoosh", gsa1_super_SuperWhoosh},
};

}  // namespace

#if defined(SA1_API_SUPER)
// version 2 (0.9.3a): SuperOption, SuperGameOption, SuperVoicePreview, the General constants, SuperState.general / start
// version 3 (0.9.3b): SuperVoiceClip (Super Sonic's own "Hm!", voice 396, as the transformation voice)
// version 4 (0.9.4a): SuperWhoosh, SuperInfo.whoosh / whoosh_on / whoosh_bank / whoosh_characters / polish,
//                     SuperState.whoosh, gsa1.SUPER's SUPOPT_SUPER_ANIMS, SUPOPT_LSD_GOLD, SUPER_EFFECTS_*, DRAW_SUPER_GOLD,
//                     TEXTURE_VARIANT_SUPER_GOLD, WHOOSH_STAGE
GSA1_FEATURE(super, 4, k_super_fns, super_open, nullptr, gsa1::kCloseDefault);
#endif
