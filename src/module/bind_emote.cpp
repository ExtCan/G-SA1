// G-SA1 module: the feature "emote" (round 0.9.4a: sadc docs/research/faces_wheel_plan.md 4.5, 4.6, 5.6 with its Review
// R.9 / R.16 / R.18; faces_wheel_ui.md 6.2; emote_wheel_lib.md 5; libsa1.h "emotes", SA1_API_EMOTE; round 0.9.4b: the end
// mode HOLD, objects2_plan.md 11.2, libsa1's SA1_API_EMOTE_HOLD; round 0.9.4e, the owner's "being able to change the
// animation's play rate": the play rate, gsa1_rounds_plan.md 14.1aa, lipsync2_plan.md 5.2's wheel row). The addon's side is
// gsa1/feat/{sh,cl}_wheel.lua (the emote wheel, its face trigger and the Q-menu page "Emote wheel"); the shared core part
// is src/core/emote.{hpp,cpp}.
//
// What libsa1 gives: any of a character's animations played the way the game's cutscenes animate a live player - the
// event action queue of the player's event work (EV_SetAction / EV_SetMotion / EV_ClrAction's bodies), drawn by the
// character's own display while the gameplay keeps running underneath; started at the character's next pair; cancelled
// by movement input and when the gameplay leaves the standing state. Only the entries of the catalogue are accepted.
//
// Lua API (feature version 3; GSA1.HasFeature("emote")). id: a ticking character of this client (not a puppet). Keys:
// "a<row>" (an action row) / "x<extra>" (an extra motion: its index among the kind's offered extras, in list order).
//   gsa1.EmoteList(kind [, form]) -> {n, [i] = {key, source, index, name, label, class, group, frames, play, flags, dup,
//        dup_key}} | nil, message, code
//       the catalogue of a character entry without a world (sa1_emote_count / sa1_emote_get on the loaded disc): kind
//       0..8, form gsa1.EMOTE.FORM_NORMAL (0) / FORM_SUPER (1: the General form while Super). name: the internal name
//       ("s_kimepose0"; names are NOT unique: the stand rows), label: the SA Tools label, class:
//       gsa1.EMOTE.CLASS_*, group: its word ("stand", "idle", "pose", ...), frames, play: "loop" / "once" / "hold", flags:
//       gsa1.EMOTE.F_*, dup: the list position (1-based) of the first entry with the same drawn object and motion (0:
//       none), dup_key its key. Eggman / Tikal: {n = 0}. code "not_ready" before the disc is loaded, "bad_argument".
//   gsa1.Emote(id, key [, flags [, speed]]) -> true | nil, reason, code
//       sa1_character_emote with one item, SA1_EMOTE_CHAIN (a once row plays the game's own follow-up chain), link -1 (8
//       blend frames); speed (version 3, round 0.9.4e: the wheel's play rate, the slot's x gsa1_wheel_speed): the item's
//       sa1_emote_item.speed, a multiplier of the game's rate (2 = twice as fast; libsa1 multiplies every entry of the
//       chain's frames per step by it), gsa1.EMOTE.SPEED_MIN (1/64) .. SPEED_MAX (16); nil or 0 = 1 (the game's rate, as
//       versions 1 and 2 played); anything else (out of range, not a number) "bad_argument". flags: gsa1.EMOTE.LOOP (the item loops until the character moves), IN_AIR (may start while not
//       standing), KEEP_INPUT, NO_PROPS, NO_TRAIL, HOLD (version 2, round 0.9.4b: an animation that ends in a pose - its
//       last entry plays once - stays on its last frame until the character moves, jumps, presses the action button, gets
//       another emote or EmoteStop; a looping one ignores it; implies NO_TRAIL). reason: libsa1's plain words ("in the
//       air", "moving", "hurt", "carrying
//       something", "on the board", "busy", "the game's memory is full", "s_kimepose0 is not available for Tails"); code
//       "bad_argument" (an unknown key: "unknown animation key ...", a flag, an entry not offered), "not_found" (no such
//       character), "unsupported" (refused now), "limit", "not_ready", "fault"
//   gsa1.EmoteStop(id [, how]) -> true | nil, message, code
//       how gsa1.EMOTE.STOP_NOW (default: the gameplay pose from the next pair) / STOP_BLEND (back to the gameplay's
//       pose at once, by a bridge, also from a loop)
//   gsa1.EmoteState(id) -> state, key, item, frame | nil
//       from the character's state after its last tick (sa1_state_ex): state gsa1.EMOTE.STATE_NONE / PLAYING / ENDING /
//       HOLDING (version 2: HOLD keeps the last frame; frame = nbFrame - 1, key / item the held entry's), key the playing
//       entry ("a75"; nil: none; a CHAIN row reports the row playing now: 75, then 76), item (-1 none; the trailing stand
//       = the item count), frame the queue head's frame. No table: multiple returns.
//   gsa1.EMOTE = {LOOP, IN_AIR, KEEP_INPUT, NO_PROPS, NO_TRAIL, CHAIN, STOP_NOW, STOP_BLEND, STATE_NONE, STATE_PLAYING,
//       STATE_ENDING, ROW, EXTRA, PLAY_DEFAULT, PLAY_ONCE, PLAY_LOOP, MAX_ITEMS, FORM_NORMAL, FORM_SUPER, CLASS_* (15),
//       F_NEEDS_PROP, F_HOLD, F_SUPER_ONLY, F_BOARD, F_OTHER_OBJECT, F_EXTRA; version 2: HOLD, STATE_HOLDING; version 3:
//       SPEED_MIN, SPEED_MAX} - libsa1's numbers (LOOP is G-SA1's own; the speed range is sa1_character_emote's check,
//       libsa1 src/sa1_emote.c). F_HOLD is a catalogue flag (the game's hold row: play "hold"); HOLD is the play flag.
// Version 4 (round 100-EV, G-SA1 1.0.0-beta1, libsa1's SA1_API_EMOTE_EVENT; sadc docs/research/emotes_ev.md 4, 7.2): the
// cutscene animations. EmoteList rows of source gsa1.EMOTE.SOURCE_EVENT (2) with key "e<n>" (n: the place among the kind's
// cutscene animations; group "cutscene"), and on them: event (the cutscene's number, 3 = EV0003), event_order (#2), cast (a
// table of the characters' names with animations in that cutscene: "sonic", "tails", ...), pace (the cutscene's speed,
// frames per 1/30 s), lift (SA1 units, flag F_LIFTED), events (a table of the cutscenes using it), notes (plain words:
// "moves away", "lifted onto the floor", "made to sit on something", "in 21 cutscenes"), ready (loaded now).
//   gsa1.EmoteEventLoad(kind, index) -> true | nil, message, code   queues the load on the module's loader thread (one file of
//       the disc of the session, about 10 ms warm) and returns at once; true also when it is loaded or queued already;
//       code "bad_argument", "not_ready" (no disc), "limit" (1024 waiting)
//   gsa1.EmoteEventReady(kind, index) -> true | false | nil, message, code   true: loaded; false: not yet; nil: the load
//       failed, message in plain words ("your disc's EV0003.PRS does not match the US 1.005 disc"), code "bad_disc" /
//       "error". G-SA1 logs it once (review RX.6: the loader never logs on its thread)
//   gsa1.Emote(id, "e<n>", ...): code "not_loaded" when the animation is not loaded yet (the load is queued then: ask again)
//   gsa1.EMOTE.SOURCE_EVENT, EVENT (= SOURCE_EVENT), CLASS_EVENT, F_EVENT, F_ROOT_MOVES, F_LIFTED, F_RESTS_ON, COPT_LIFT (the
//       character option 10 G-SA1 sets from gsa1_wheel_ev_lift with gsa1.SetCharacterOption where the module has it)
//   The loader is drained (queued loads dropped, the running one waited for) at gsa1.Shutdown and at the module's close,
//   before the session unloads the disc (libsa1.h: never beside sa1_unload_disc / sa1_shutdown).
#include <cstddef>
#include <cstring>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/emote.hpp"
#include "../core/session.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;

#if defined(SA1_API_EMOTE)

namespace {

// a ticking character of the session (not a puppet) by its Lua id
gsa1::Character *emote_char_arg(ILuaBase *L, int i, int32_t &id)
{
    gsa1::Session *se = session();
    if (!se || !arg_int(L, i, id, 1, 2147483647.0)) {
        return nullptr;
    }
    gsa1::Character *c = se->get(id);
    return c && !c->puppet ? c : nullptr;
}

bool arg_absent(ILuaBase *L, int i)
{
    int t = L->GetType(i);
    return t == LT::Nil || t == LT::None;
}

// round 0.9.4e: the play rate libsa1 accepts for an item (sa1_character_emote: 0 = 1, else 1/64..16; libsa1
// src/sa1_emote.c's item check) - checked here first, so a bad rate is "bad_argument" before the character is looked up
const double kEmoteSpeedMin = 1.0 / 64.0;
const double kEmoteSpeedMax = 16.0;

bool emote_speed_ok(double v)
{
    return v == 0.0 || (v >= kEmoteSpeedMin && v <= kEmoteSpeedMax);
}

// gsa1::emote_play (src/core/emote.cpp, the core's offline path: speed 1) with the item's play rate: the same sa1_emote
// (one item, SA1_EMOTE_CHAIN, link -1, the LOOP and pass-through flags), only items[0].speed differs (0 = the game's rate)
sa1_status emote_play_speed(sa1_context *ctx, int32_t id, uint32_t source, uint32_t index, uint32_t flags, float speed)
{
    if (!ctx) {
        return SA1_ERR_NOT_LOADED;
    }
    sa1_emote e;
    std::memset(&e, 0, sizeof e);
    e.struct_size = sizeof e;
    e.count = 1;
    e.items[0].source = source;
    e.items[0].index = index;
    e.items[0].play = (flags & gsa1::kEmoteLoop) ? SA1_EMOTE_PLAY_LOOP : SA1_EMOTE_PLAY_DEFAULT;
    e.items[0].speed = speed;
    e.link = -1;
    e.flags = SA1_EMOTE_CHAIN | (flags & gsa1::emote_pass_flags());
    return sa1_character_emote(ctx, id, &e);
}

// round 100-EV: the module's cutscene loader (drained at gsa1.Shutdown and at the close: emote_shutdown)
gsa1::EmoteEventPool g_ev_pool;

// a new table at key k of the table at absolute index t, left on the stack: its absolute index
int sub_named(ILuaBase *L, int t, const char *k)
{
    L->CreateTable();
    L->PushString(k);
    L->Push(-2);
    L->RawSet(t);
    return L->Top();
}

}  // namespace

// tests (feat_emote_binding_test.cpp): the module's loader
gsa1::EmoteEventPool &gsa1_emote_event_pool()
{
    return g_ev_pool;
}

// gsa1.EmoteList(kind [, form]) -> {n, [i] = {...}} | nil, message, code
GSA1_FN(gsa1_emote_EmoteList)
{
    int32_t kind = -1, form = 0;
    if (!arg_int(LUA, 1, kind, 0, 8) || (!arg_absent(LUA, 2) && !arg_int(LUA, 2, form, 0, 1))) {
        return push_nil_msg(LUA, "EmoteList(kind 0..8 [, form gsa1.EMOTE.FORM_NORMAL | FORM_SUPER])", "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
    }
    std::vector<gsa1::EmoteEntry> list;
    std::string err;
    if (!gsa1::emote_list(se->ctx(), kind, (uint32_t)form, list, err)) {
        return push_nil_msg(LUA, scrubbed(err), "error");
    }
    LUA->CreateTable();
    int t = LUA->Top();
    raw_num(LUA, t, "n", (double)list.size());
    for (size_t i = 0; i < list.size(); i++) {
        const gsa1::EmoteEntry &e = list[i];
        int r = raw_subtable_i(LUA, t, (int)i + 1);
        raw_str(LUA, r, "key", e.key);
        raw_num(LUA, r, "source", e.source);
        raw_num(LUA, r, "index", e.index);
        raw_str(LUA, r, "name", e.name);
        raw_str(LUA, r, "label", e.label);
        raw_num(LUA, r, "class", e.cls);
        raw_str(LUA, r, "group", gsa1::emote_class_name(e.cls));
        raw_num(LUA, r, "frames", e.frames);
        raw_str(LUA, r, "play", gsa1::emote_play_name(e.play, e.flags));
        raw_num(LUA, r, "flags", e.flags);
        bool dup = e.dup_of >= 0 && (size_t)e.dup_of < list.size() && (size_t)e.dup_of != i;
        raw_num(LUA, r, "dup", dup ? (double)e.dup_of + 1.0 : 0.0);
        raw_str(LUA, r, "dup_key", dup ? list[(size_t)e.dup_of].key : std::string());
        if (e.source == gsa1::kEmoteSourceEvent) {
            // round 100-EV (version 4): a cutscene animation's fields
            raw_num(LUA, r, "event", e.event);
            raw_num(LUA, r, "event_order", e.event_order);
            raw_num(LUA, r, "pace", e.pace);
            raw_num(LUA, r, "lift", e.lift);
            raw_str(LUA, r, "notes", gsa1::emote_notes(e));
#if defined(SA1_API_EMOTE_EVENT)
            LUA->PushBool(sa1_emote_event_ready(se->ctx(), kind, e.index) == 1);
#else
            LUA->PushBool(false);
#endif
            LUA->SetField(r, "ready");
            int ct = sub_named(LUA, r, "cast");
            std::vector<std::string> names = gsa1::emote_cast_names(e.cast);
            for (size_t k = 0; k < names.size(); k++) {
                LUA->PushNumber((double)k + 1.0);
                LUA->PushString(names[k].c_str());
                LUA->RawSet(ct);
            }
            LUA->Pop();
            int et = sub_named(LUA, r, "events");
            for (size_t k = 0; k < e.events.size(); k++) {
                LUA->PushNumber((double)k + 1.0);
                LUA->PushNumber((double)e.events[k]);
                LUA->RawSet(et);
            }
            LUA->Pop();
        }
        LUA->Pop();
    }
    return 1;
}

// gsa1.Emote(id, key [, flags [, speed]]) -> true | nil, reason, code
GSA1_FN(gsa1_emote_Emote)
{
    std::string key;
    uint32_t source = 0, index = 0;
    if (!arg_string(LUA, 2, key, 16) || !gsa1::emote_parse_key(key, source, index)) {
        std::string shown = LUA->GetType(2) == LT::String ? key : std::string("?");
        if (shown.size() > 16) shown.resize(16);
        return push_nil_msg(LUA, "unknown animation key '" + shown + "' (a<row> or x<extra>, as gsa1.EmoteList gives)",
                            "bad_argument");
    }
    int32_t flags = 0;
    const uint32_t known = gsa1::kEmoteLoop | gsa1::emote_pass_flags();
    if (!arg_absent(LUA, 3) && (!arg_int(LUA, 3, flags, 0, 65535) || ((uint32_t)flags & ~known) != 0)) {
        return push_nil_msg(LUA, "Emote(id, key, flags): flags of gsa1.EMOTE.LOOP | IN_AIR | KEEP_INPUT | NO_PROPS | "
                            "NO_TRAIL | HOLD", "bad_argument");
    }
    // round 0.9.4e: the play rate (nil / 0 = the game's rate)
    double speed = 0.0;
    if (!arg_absent(LUA, 4) && (!arg_number(LUA, 4, speed) || !emote_speed_ok(speed))) {
        return push_nil_msg(LUA, "Emote(id, key, flags, speed): speed a multiplier of the game's rate, gsa1.EMOTE.SPEED_MIN "
                            "(1/64) .. SPEED_MAX (16); nil or 0 = 1", "bad_argument");
    }
    int32_t id = 0;
    gsa1::Character *c = emote_char_arg(LUA, 1, id);
    if (!c) {
        return push_nil_msg(LUA, "no such character (Emote(id of a character of yours, key [, flags]))", "not_found");
    }
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_status st = emote_play_speed(se->ctx(), id, source, index, (uint32_t)flags, (float)speed);
    if (SA1_FAILED(st)) {
        if (source == gsa1::kEmoteSourceEvent && st == SA1_ERR_NOT_LOADED) {
            // round 100-EV: not loaded yet - the load is queued (the character's kind: a skin plays its base kind's), ask again
            g_ev_pool.queue(se->ctx(), c->kind, index);
            return push_nil_msg(LUA, scrubbed(gsa1::emote_error(se->ctx(), st)), "not_loaded");
        }
        return push_nil_msg(LUA, scrubbed(gsa1::emote_error(se->ctx(), st)), gsa1::emote_code(st));
    }
    LUA->PushBool(true);
    return 1;
}

#if defined(SA1_API_EMOTE_EVENT)
namespace {

// the (kind, index) of a cutscene animation: an EVENT entry of the kind's normal list
bool event_args(ILuaBase *L, int32_t &kind, uint32_t &index, uint32_t &event)
{
    int32_t k = -1, i = -1;
    if (!arg_int(L, 1, k, 0, 8) || !arg_int(L, 2, i, 0, 9999)) {
        return false;
    }
    kind = k;
    index = (uint32_t)i;
    event = 0;
    gsa1::Session *se = session();
    if (se && se->ready()) {
        // the cutscene animations end the normal list: the last entry's index says how many there are (two calls, no scan:
        // the page asks for every one of them twice a second)
        uint32_t n = sa1_emote_count(se->ctx(), kind, SA1_EMOTE_FORM_NORMAL);
        sa1_emote_info last, info;
        std::memset(&last, 0, sizeof last);
        last.struct_size = sizeof last;
        if (n == 0 || sa1_emote_get(se->ctx(), kind, SA1_EMOTE_FORM_NORMAL, n - 1, &last) != SA1_OK ||
            last.source != SA1_EMOTE_EVENT || index > last.index) {
            return false;
        }
        std::memset(&info, 0, sizeof info);
        info.struct_size = sizeof info;
        if (sa1_emote_get(se->ctx(), kind, SA1_EMOTE_FORM_NORMAL, n - 1 - (last.index - index), &info) != SA1_OK ||
            info.source != SA1_EMOTE_EVENT || info.index != index) {
            return false;
        }
        event = info.event;
        return true;
    }
    return true;
}

}  // namespace

// gsa1.EmoteEventLoad(kind, index) -> true | nil, message, code
GSA1_FN(gsa1_emote_EmoteEventLoad)
{
    int32_t kind = 0;
    uint32_t index = 0, event = 0;
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
    }
    if (!event_args(LUA, kind, index, event)) {
        return push_nil_msg(LUA, "EmoteEventLoad(kind 0..8, index of a cutscene animation of that kind)", "bad_argument");
    }
    if (sa1_emote_event_ready(se->ctx(), kind, index) == 1) {
        LUA->PushBool(true);
        return 1;
    }
    if (!g_ev_pool.queue(se->ctx(), kind, index)) {
        return push_nil_msg(LUA, "too many cutscene animations are waiting to load", "limit");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.EmoteEventReady(kind, index) -> true | false | nil, message, code
GSA1_FN(gsa1_emote_EmoteEventReady)
{
    int32_t kind = 0;
    uint32_t index = 0, event = 0;
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
    }
    if (!event_args(LUA, kind, index, event)) {
        return push_nil_msg(LUA, "EmoteEventReady(kind 0..8, index of a cutscene animation of that kind)", "bad_argument");
    }
    int32_t r = sa1_emote_event_ready(se->ctx(), kind, index);
    if (r < 0) {
        return push_nil_msg(LUA, gsa1::emote_event_error(r, event), r == SA1_ERR_BAD_HASH || r == SA1_ERR_BAD_FORMAT ? "bad_disc" : "error");
    }
    LUA->PushBool(r == 1);
    return 1;
}
#endif

// gsa1.EmoteStop(id [, how]) -> true | nil, message, code
GSA1_FN(gsa1_emote_EmoteStop)
{
    int32_t id = 0, how = (int32_t)SA1_EMOTE_STOP_NOW;
    if (!arg_absent(LUA, 2) && !arg_int(LUA, 2, how, 0, 1)) {
        return push_nil_msg(LUA, "EmoteStop(id [, gsa1.EMOTE.STOP_NOW | STOP_BLEND])", "bad_argument");
    }
    gsa1::Character *c = emote_char_arg(LUA, 1, id);
    if (!c) {
        return push_nil_msg(LUA, "no such character (EmoteStop(id of a character of yours [, how]))", "not_found");
    }
    gsa1::Session *se = session();
    if (!se || !se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    sa1_status st = gsa1::emote_stop(se->ctx(), id, (uint32_t)how);
    if (SA1_FAILED(st)) {
        return push_nil_msg(LUA, scrubbed(gsa1::emote_error(se->ctx(), st)), gsa1::emote_code(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.EmoteState(id) -> state, key, item, frame | nil
GSA1_FN(gsa1_emote_EmoteState)
{
    int32_t id = 0;
    gsa1::Character *c = emote_char_arg(LUA, 1, id);
    if (!c) {
        LUA->PushNil();
        return 1;
    }
    const sa1_state_ex &s = c->st;
    // a state libsa1 never filled (struct_size short of the emote fields): nothing plays
    bool has = s.struct_size >= offsetof(sa1_state_ex, emote_frame) + sizeof(float);
    uint32_t state = has ? s.emote_state : 0u;
    LUA->PushNumber(state);
    if (has && state != 0u && s.emote_row >= 0) {
        LUA->PushString(gsa1::emote_key(SA1_EMOTE_ROW, (uint32_t)s.emote_row).c_str());
    } else if (has && state != 0u && s.emote_extra >= 0) {
        LUA->PushString(gsa1::emote_key(SA1_EMOTE_EXTRA, (uint32_t)s.emote_extra).c_str());
    } else {
        LUA->PushNil();
    }
    LUA->PushNumber(has && state != 0u ? (double)s.emote_item : -1.0);
    LUA->PushNumber(has && state != 0u ? (double)s.emote_frame : 0.0);
    return 4;
}

namespace {

void emote_open(ILuaBase *L, int t)
{
    L->PushString("EMOTE");
    L->CreateTable();
    int c = L->Top();
    raw_num(L, c, "LOOP", gsa1::kEmoteLoop);
    raw_num(L, c, "IN_AIR", SA1_EMOTE_IN_AIR);
    raw_num(L, c, "KEEP_INPUT", SA1_EMOTE_KEEP_INPUT);
    raw_num(L, c, "NO_PROPS", SA1_EMOTE_NO_PROPS);
    raw_num(L, c, "NO_TRAIL", SA1_EMOTE_NO_TRAIL);
    raw_num(L, c, "CHAIN", SA1_EMOTE_CHAIN);
    raw_num(L, c, "STOP_NOW", SA1_EMOTE_STOP_NOW);
    raw_num(L, c, "STOP_BLEND", SA1_EMOTE_STOP_BLEND);
    raw_num(L, c, "STATE_NONE", SA1_EMOTE_STATE_NONE);
    raw_num(L, c, "STATE_PLAYING", SA1_EMOTE_STATE_PLAYING);
    raw_num(L, c, "STATE_ENDING", SA1_EMOTE_STATE_ENDING);
    raw_num(L, c, "ROW", SA1_EMOTE_ROW);
    raw_num(L, c, "EXTRA", SA1_EMOTE_EXTRA);
    raw_num(L, c, "PLAY_DEFAULT", SA1_EMOTE_PLAY_DEFAULT);
    raw_num(L, c, "PLAY_ONCE", SA1_EMOTE_PLAY_ONCE);
    raw_num(L, c, "PLAY_LOOP", SA1_EMOTE_PLAY_LOOP);
    raw_num(L, c, "MAX_ITEMS", SA1_EMOTE_MAX_ITEMS);
    raw_num(L, c, "FORM_NORMAL", SA1_EMOTE_FORM_NORMAL);
    raw_num(L, c, "FORM_SUPER", SA1_EMOTE_FORM_SUPER);
    raw_num(L, c, "CLASS_STAND", SA1_EMOTE_CLASS_STAND);
    raw_num(L, c, "CLASS_IDLE", SA1_EMOTE_CLASS_IDLE);
    raw_num(L, c, "CLASS_POSE", SA1_EMOTE_CLASS_POSE);
    raw_num(L, c, "CLASS_MOVE", SA1_EMOTE_CLASS_MOVE);
    raw_num(L, c, "CLASS_AIR", SA1_EMOTE_CLASS_AIR);
    raw_num(L, c, "CLASS_BRAKE", SA1_EMOTE_CLASS_BRAKE);
    raw_num(L, c, "CLASS_BALL", SA1_EMOTE_CLASS_BALL);
    raw_num(L, c, "CLASS_ATTACK", SA1_EMOTE_CLASS_ATTACK);
    raw_num(L, c, "CLASS_CARRY", SA1_EMOTE_CLASS_CARRY);
    raw_num(L, c, "CLASS_SETPIECE", SA1_EMOTE_CLASS_SETPIECE);
    raw_num(L, c, "CLASS_HURT", SA1_EMOTE_CLASS_HURT);
    raw_num(L, c, "CLASS_FISH", SA1_EMOTE_CLASS_FISH);
    raw_num(L, c, "CLASS_SWIM", SA1_EMOTE_CLASS_SWIM);
    raw_num(L, c, "CLASS_BOARD", SA1_EMOTE_CLASS_BOARD);
    raw_num(L, c, "CLASS_SUPER", SA1_EMOTE_CLASS_SUPER);
    raw_num(L, c, "F_NEEDS_PROP", SA1_EMOTE_F_NEEDS_PROP);
    raw_num(L, c, "F_HOLD", SA1_EMOTE_F_HOLD);
    raw_num(L, c, "F_SUPER_ONLY", SA1_EMOTE_F_SUPER_ONLY);
    raw_num(L, c, "F_BOARD", SA1_EMOTE_F_BOARD);
    raw_num(L, c, "F_OTHER_OBJECT", SA1_EMOTE_F_OTHER_OBJECT);
    raw_num(L, c, "F_EXTRA", SA1_EMOTE_F_EXTRA);
#if defined(SA1_API_EMOTE_HOLD)
    // version 2 (round 0.9.4b, objects2_plan.md 11.2): the end mode HOLD and its state
    raw_num(L, c, "HOLD", SA1_EMOTE_HOLD);
    raw_num(L, c, "STATE_HOLDING", SA1_EMOTE_STATE_HOLDING);
    // version 3 (round 0.9.4e): Emote's play rate, the range libsa1 accepts
    raw_num(L, c, "SPEED_MIN", kEmoteSpeedMin);
    raw_num(L, c, "SPEED_MAX", kEmoteSpeedMax);
#endif
#if defined(SA1_API_EMOTE_EVENT)
    // version 4 (round 100-EV): the cutscene animations
    raw_num(L, c, "SOURCE_EVENT", SA1_EMOTE_EVENT);
    raw_num(L, c, "EVENT", SA1_EMOTE_EVENT);
    raw_num(L, c, "CLASS_EVENT", SA1_EMOTE_CLASS_EVENT);
    raw_num(L, c, "F_EVENT", SA1_EMOTE_F_EVENT);
    raw_num(L, c, "F_ROOT_MOVES", SA1_EMOTE_F_ROOT_MOVES);
    raw_num(L, c, "F_LIFTED", SA1_EMOTE_F_LIFTED);
    raw_num(L, c, "F_RESTS_ON", SA1_EMOTE_F_RESTS_ON);
    raw_num(L, c, "COPT_LIFT", SA1_COPT_EMOTE_LIFT);
#endif
    L->RawSet(t);
}

// round 100-EV: the loader is drained before the session unloads the disc (gsa1.Shutdown) and at the module's close
void emote_shutdown()
{
    g_ev_pool.drain();
}

void emote_close(ILuaBase *L)
{
    (void)L;
    g_ev_pool.drain();
}

const gsa1::FeatureFn k_emote_fns[] = {
    {"EmoteList", gsa1_emote_EmoteList},
    {"Emote", gsa1_emote_Emote},
    {"EmoteStop", gsa1_emote_EmoteStop},
    {"EmoteState", gsa1_emote_EmoteState},
#if defined(SA1_API_EMOTE_EVENT)
    {"EmoteEventLoad", gsa1_emote_EmoteEventLoad},
    {"EmoteEventReady", gsa1_emote_EmoteEventReady},
#endif
};

}  // namespace

// version 1 (0.9.4a): EmoteList, Emote, EmoteStop, EmoteState, gsa1.EMOTE; version 2 (0.9.4b, with libsa1's
// SA1_API_EMOTE_HOLD): Emote's flag gsa1.EMOTE.HOLD, EmoteState's STATE_HOLDING; version 3 (0.9.4e): Emote's play rate
// (its 4th argument; sa1_emote_item.speed is libsa1's since SA1_API_EMOTE), gsa1.EMOTE.SPEED_MIN / SPEED_MAX. A libsa1
// without HOLD stays version 1 (the versions are cumulative); its Emote takes the speed all the same
// version 4 (round 100-EV, with libsa1's SA1_API_EMOTE_EVENT): the cutscene animations (EmoteList's "e<n>" rows,
// EmoteEventLoad, EmoteEventReady, Emote's "not_loaded", the EMOTE constants of the header comment)
#if defined(SA1_API_EMOTE_EVENT) && defined(SA1_API_EMOTE_HOLD)
GSA1_FEATURE(emote, 4, k_emote_fns, emote_open, emote_close, gsa1::kCloseDefault);
#elif defined(SA1_API_EMOTE_HOLD)
GSA1_FEATURE(emote, 3, k_emote_fns, emote_open, emote_close, gsa1::kCloseDefault);
#else
GSA1_FEATURE(emote, 1, k_emote_fns, emote_open, emote_close, gsa1::kCloseDefault);
#endif
GSA1_FEATURE_ON_SHUTDOWN(emote, emote_shutdown);

#endif
