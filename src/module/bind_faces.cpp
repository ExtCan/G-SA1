// G-SA1 module: the event faces feature "faces" (round 0.9.4a: sadc docs/research/faces_wheel_plan.md 5.6 and 6.4 task 2
// with its Review R.2 / R.6 / R.19; faces_wheel_ui.md 6.1; libsa1.h "faces", SA1_API_FACE). The addon's side is
// gsa1/feat/{sh,cl}_faces.lua (the Faces page, the face animation maker, the switch, the hotkeys, lip sync).
//
// libsa1 takes the place of a cutscene's face script: the game's own EV head (a second head whose vertices the game blends
// between shape keys) with the game's face block, reader and blend. Every call is latched and applied at the character's
// next game pair; a world that never gets a call is the game's. Characters with a face: Sonic, Tails, Knuckles, Amy (all 31
// face animations 'A'-'Z', 'a'-'e'), Big (14 of them); E-102 and Super Sonic have none in the game ("unsupported").
//
// Lua API (feature version 2 since round 0.9.4c, 1 in 0.9.4a; GSA1.HasFeature("faces", 2)). id: a ticking character of
// this client (not a puppet). Every function returns true | nil, message, code unless noted; codes "bad_argument",
// "not_ready", "not_found", "unsupported", "fault", "error".
//   gsa1.FaceInfo(kind) -> {has_face, keys, letters (bit n: face animation n can show), ladder ("0,5,4,6,7"), ladder_len,
//       steps = {[0..30] = 60 Hz steps}, first = {[0..30]}, last = {[0..30]}} | nil, message, code
//       No world needed, but libsa1 reads 1ST_READ.BIN from the disc on every call (17-25 ms; review R.2): the addon calls it
//       once per kind per session (GSA1.Faces.Info caches).
//   gsa1.FaceMode(id, event, pace)        event / pace booleans: SA1_FACE_MODE_EVENT [| SA1_FACE_PACE_CUTSCENE] or GAME
//   gsa1.FaceSequence(id, spec [, flags]) a face animation: spec "b:10:90,A:8:0" = letter:enter:hold entries (letter A-Z
//       a-e, enter 0..127 frames (0 = the game's first step), hold 0..3600 frames; 1..32 entries; 60 frames = 1 s), parsed
//       and checked here (the reason in the message); flags gsa1.FACE.HOLD_LAST (the last face stays until the next call)
//   gsa1.FaceScript(id, letters [, flags]) the game's EV_SetFace path (tests, the console, 2.0): 0..64 of A-Z a-e 0 ("" =
//       stop); flags gsa1.FACE.NOW | LOOP
//   gsa1.FaceStop(id)                     the face animation / script ends (the switch's face: the idle or the regular face)
//   gsa1.FaceLevel(id, level, style [, flags]) lip sync, every frame while talking: level 0..1, < 0 = off; style
//       LEVEL_LADDER (0) / LEVEL_TALK (1); 0.9.4c: flags gsa1.FACE.SAME_PAIR with style 0 -> SA1_FACE_LEVEL_LADDER |
//       SA1_FACE_SAME_PAIR (dropped with style 1). Numbers only: no table, returns nothing, never an error (a bad argument
//       or no character: nothing). The ladder is the character's own (sa1_face_info.ladder: 0.9.4c's per-character
//       ladders, e.g. Sonic "0,4,16", Big "0,4,5")
//   gsa1.FaceState(id) -> mode, shown, from, to, rate, letter, activity (multiple returns; nil without the character): the
//       face fields of the character's last sa1_state_ex (shown a boolean)
//   gsa1.MicDevices() -> { {index, name, default, enabled}, ... } | nil, message
//   gsa1.MicOpen(device)                  -1 = Windows' default input; the device stays open (paused) for the session
//   gsa1.MicListen(on)                    capture on / paused (the talk key)
//   gsa1.MicClose()                       -> true
//   gsa1.MicLevel() -> level, peak, state  the last 10 ms block's loudness (RMS as dBFS -60..-10 -> 0..1), its peak, and
//       "off" / "paused" / "on" / "failed: <why>" (src/core/mic.hpp). Nothing is recorded, stored or sent.
//   gsa1.FACE = {MODE_GAME, MODE_EVENT, PACE_CUTSCENE, NOW, LOOP, HOLD_LAST, LEVEL_LADDER, LEVEL_TALK, ACT_NONE,
//       ACT_SEQUENCE, ACT_SCRIPT, ACT_HELD, ACT_LIPSYNC, ACT_GAMEPLAY, SEQ_MAX, HOLD_MAX, ENTER_MAX; 0.9.4c: MOUTH = 1,
//       SAME_PAIR (only when libsa1.h defines SA1_FACE_SAME_PAIR: libsa1 built the faster mouth; review R.2)}
// Round 0.9.4c, phoneme lip sync (sadc docs/research/phoneme_plan.md 5.5 with its Review; src/core/viseme.hpp: the
// classifier on the microphone's blocks; src/core/mouth.hpp: the per-character mouth table). "Per frame" functions take
// and return numbers only, push no table and never throw (a bad argument: nothing, or 0, 0, 0):
//   gsa1.MicViseme() -> cls, level, f1, f2, conf, seq   per frame: the classifier's newest frame (one atomic load). cls
//       gsa1.VISEME.SIL .. FV (0..8), or -1 while not listening, with the analysis off, without a device or before the
//       first frame of a press; level 0..1 (the 25 ms window), f1 / f2 Hz (0 none), conf 0..1, seq 0..65535 (+1 per frame)
//   gsa1.MicVisemeOn(on)                  the analysis in the microphone's callback on / off (off: only MicLevel's
//       loudness); turning it on starts like a press
//   gsa1.MicVisemeTune(name, value)       "gate_min_db" 3..12, "adapt" 0 / 1, "smooth" 0..3 (0 instant, 1 vote, 2 steadier,
//       3 quick), "reset_voice" (value ignored); applied at the next 10 ms block; other names / ranges: nil, message,
//       "bad_argument"
//   gsa1.MicVisemeVoice() -> g, frames    per frame allowed: the speaker number in use and the vowel frames it learned
//       from (0: the adult prior). Session memory only: never saved, logged or sent (owner, phoneme_plan.md 10.1 PQ7)
//   gsa1.VisemeMouth(kind, cls, s, size, variant, big) -> a, b, w   per frame: the mouth table's rule (no world): keys a, b
//       and the weight for gsa1.FaceMouth; variant 0 normal, 1 quiet, 2 loud; big: bigger mouths for loud speech;
//       SIL / MBP -> 0, 0, 0; a ladder entry (f v th) -> -1, -1, min(s, fv_level): send gsa1.FaceLevel(id, w, 0) instead
//       (review R.1); a kind without a face or a bad argument -> 0, 0, 0
//   gsa1.VisemeTable(kind) -> { kind, keys, floor, ladder_cap, fv_level, [0..8] = { a, b, w, how ("closed" / "scales" /
//       "fixed" / "ladder"), expression, quiet = {a, b, w, how, expression} | nil, loud = ..., plain = ... } } | nil,
//       message, code   for the Faces page (not per frame)
//   gsa1.FaceMouth(id, key_a, key_b, weight [, flags])   per frame, returns nothing: sa1_character_face_mouth (the face
//       block's two keys and the weight between them; weight < 0 = off; flags gsa1.FACE.SAME_PAIR)
//   gsa1.VISEME = { SIL = 0, MBP = 1, AA = 2, EH = 3, EE = 4, OH = 5, OO = 6, SS = 7, FV = 8, COUNT = 9,
//       NAMES = {[0] = "SIL", ...}, WORDS = {[0] = "silence", "m b p", "ah", "eh", "ee", "oh", "oo", "s z sh", "f v th"} }
// The microphone closes with the module (the close hook), frees only what it initialised and forgets the speaker number.
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/mic.hpp"
#include "../core/mouth.hpp"
#include "../core/session.hpp"
#include "../core/viseme.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;

#if defined(SA1_API_FACE)

namespace {

// a ticking character of the session (not a puppet) by its Lua id
gsa1::Character *face_char(ILuaBase *L, int i, int32_t &id)
{
    gsa1::Session *se = session();
    if (!se || !arg_int(L, i, id, 1, 2147483647.0)) {
        return nullptr;
    }
    gsa1::Character *c = se->get(id);
    return c && !c->puppet ? c : nullptr;
}

const char *face_code(sa1_status st)
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

int lib_result(ILuaBase *L, gsa1::Session *se, sa1_status st)
{
    if (SA1_FAILED(st)) {
        const char *e = sa1_last_error(se->ctx());
        return push_nil_msg(L, scrubbed(e && *e ? e : sa1_status_string(st)), face_code(st));
    }
    L->PushBool(true);
    return 1;
}

// an optional flags argument: nil / none = 0, else a whole number with only `allowed` bits
bool arg_flags(ILuaBase *L, int i, uint32_t allowed, uint32_t &out)
{
    int t = L->GetType(i);
    out = 0;
    if (t == LT::Nil || t == LT::None) {
        return true;
    }
    int32_t v = 0;
    if (!arg_int(L, i, v, 0, 65535) || ((uint32_t)v & ~allowed) != 0u) {
        return false;
    }
    out = (uint32_t)v;
    return true;
}

// an optional boolean (nil / none = false; numbers 0 / 1 too)
bool arg_bool(ILuaBase *L, int i, bool &out)
{
    int t = L->GetType(i);
    if (t == LT::Nil || t == LT::None) {
        out = false;
        return true;
    }
    if (t == LT::Bool) {
        out = L->GetBool(i);
        return true;
    }
    int32_t v = 0;
    if (arg_int(L, i, v, 0, 1)) {
        out = v != 0;
        return true;
    }
    return false;
}

// 0.9.4c: the mouth calls' flags - SA1_FACE_SAME_PAIR when libsa1 built the faster mouth (review R.2: no define, no flag)
#if defined(SA1_FACE_SAME_PAIR)
const uint32_t kMouthFlags = SA1_FACE_SAME_PAIR;
#else
const uint32_t kMouthFlags = 0u;
#endif

// an optional per-frame flags argument: nil / none / anything else = 0; a number keeps only kMouthFlags' bits
uint32_t mouth_flags(ILuaBase *L, int i)
{
    double v = 0.0;
    if (!arg_number(L, i, v) || v < 0.0 || v > 65535.0 || v != std::floor(v)) {
        return 0u;
    }
    return (uint32_t)v & kMouthFlags;
}

int letter_index(char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'e') return 26 + (c - 'a');
    return -1;
}

bool parse_uint(const std::string &s, uint32_t max, uint32_t &out)
{
    if (s.empty() || s.size() > 5) {
        return false;
    }
    uint32_t v = 0;
    for (char c : s) {
        if (c < '0' || c > '9') {
            return false;
        }
        v = v * 10u + (uint32_t)(c - '0');
    }
    if (v > max) {
        return false;
    }
    out = v;
    return true;
}

std::string trim(const std::string &s)
{
    size_t a = 0, b = s.size();
    while (a < b && (s[a] == ' ' || s[a] == '\t')) a++;
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t')) b--;
    return s.substr(a, b - a);
}

}  // namespace

namespace gsa1 {
namespace faces {
// "b:10:90,A:8:0" -> entries; false with why (plain words). 1..SA1_FACE_SEQ_MAX entries.
bool parse_spec(const std::string &spec, std::vector<sa1_face_entry> &out, std::string &why)
{
    out.clear();
    std::string s = trim(spec);
    if (s.empty()) {
        why = "an empty face animation (use FaceStop to stop)";
        return false;
    }
    size_t pos = 0;
    int n = 0;
    while (pos <= s.size()) {
        size_t comma = s.find(',', pos);
        std::string item = trim(s.substr(pos, comma == std::string::npos ? std::string::npos : comma - pos));
        n++;
        if (n > (int)SA1_FACE_SEQ_MAX) {
            why = format("more than %u entries", (unsigned)SA1_FACE_SEQ_MAX);
            return false;
        }
        size_t c1 = item.find(':'), c2 = c1 == std::string::npos ? std::string::npos : item.find(':', c1 + 1);
        if (c1 != 1 || c2 == std::string::npos || item.find(':', c2 + 1) != std::string::npos) {
            why = format("entry %d \"%s\" is not letter:enter:hold (e.g. b:10:90)", n, item.c_str());
            return false;
        }
        int a = letter_index(item[0]);
        if (a < 0) {
            why = format("entry %d: '%c' is not a face letter (A-Z, a-e)", n, (item[0] >= 32 && item[0] < 127) ? item[0] : '?');
            return false;
        }
        uint32_t enter = 0, hold = 0;
        if (!parse_uint(item.substr(c1 + 1, c2 - c1 - 1), 127u, enter)) {
            why = format("entry %d: enter \"%s\" is not 0..127 frames", n, item.substr(c1 + 1, c2 - c1 - 1).c_str());
            return false;
        }
        if (!parse_uint(item.substr(c2 + 1), SA1_FACE_HOLD_MAX, hold)) {
            why = format("entry %d: hold \"%s\" is not 0..%u frames", n, item.substr(c2 + 1).c_str(),
                         (unsigned)SA1_FACE_HOLD_MAX);
            return false;
        }
        sa1_face_entry e;
        std::memset(&e, 0, sizeof e);
        e.anim = (uint8_t)a;
        e.enter = (uint16_t)enter;
        e.hold = (uint16_t)hold;
        out.push_back(e);
        if (comma == std::string::npos) {
            break;
        }
        pos = comma + 1;
    }
    return true;
}
}  // namespace faces
}  // namespace gsa1

namespace {

// a subtable t[k] = {[0..30] = v[i]}
template <class T>
void raw_array31(ILuaBase *L, int t, const char *k, const T *v)
{
    L->PushString(k);
    L->CreateTable();
    int a = L->Top();
    for (int i = 0; i < 31; i++) {
        L->PushNumber(i);
        L->PushNumber((double)v[i]);
        L->RawSet(a);
    }
    L->RawSet(t);
}

}  // namespace

// gsa1.FaceInfo(kind) -> table | nil, message, code
GSA1_FN(gsa1_faces_FaceInfo)
{
    int32_t kind = 0;
    if (!arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1)) {
        return push_nil_msg(LUA, "FaceInfo(kind 0..8)", "bad_argument");
    }
    int ret = 0;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    sa1_face_info fi;
    std::memset(&fi, 0, sizeof fi);
    fi.struct_size = sizeof fi;
    sa1_status st = sa1_face_info_get(se->ctx(), kind, &fi);
    if (SA1_FAILED(st)) {
        const char *e = sa1_last_error(se->ctx());
        return push_nil_msg(LUA, scrubbed(e && *e ? e : sa1_status_string(st)), face_code(st));
    }
    LUA->CreateTable();
    int t = LUA->Top();
    raw_bool(LUA, t, "has_face", fi.keys > 0 && fi.letters != 0);
    raw_num(LUA, t, "keys", fi.keys);
    raw_num(LUA, t, "letters", fi.letters);
    std::string ladder;
    uint32_t n = fi.ladder_len > 8u ? 8u : fi.ladder_len;
    for (uint32_t i = 0; i < n; i++) {
        ladder += (i ? "," : "") + std::to_string((unsigned)fi.ladder[i]);
    }
    raw_str(LUA, t, "ladder", ladder);
    raw_num(LUA, t, "ladder_len", n);
    raw_array31(LUA, t, "steps", fi.steps);
    raw_array31(LUA, t, "first", fi.first);
    raw_array31(LUA, t, "last", fi.last_key);
    return 1;
}

// gsa1.FaceMode(id, event, pace) -> true | nil, message, code
GSA1_FN(gsa1_faces_FaceMode)
{
    int32_t id = 0;
    bool event = false, pace = false;
    gsa1::Character *c = face_char(LUA, 1, id);
    if (!arg_bool(LUA, 2, event) || !arg_bool(LUA, 3, pace)) {
        return push_nil_msg(LUA, "FaceMode(id, event faces true / false, cutscene pace true / false)", "bad_argument");
    }
    if (!c) {
        return push_nil_msg(LUA, "FaceMode: no character of yours with that id", "not_found");
    }
    gsa1::Session *se = session();
    if (!se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    uint32_t mode = event ? (SA1_FACE_MODE_EVENT | (pace ? SA1_FACE_PACE_CUTSCENE : 0u)) : SA1_FACE_MODE_GAME;
    return lib_result(LUA, se, sa1_character_face_mode(se->ctx(), id, mode));
}

// gsa1.FaceSequence(id, spec [, flags]) -> true | nil, message, code
GSA1_FN(gsa1_faces_FaceSequence)
{
    int32_t id = 0;
    std::string spec;
    uint32_t flags = 0;
    gsa1::Character *c = face_char(LUA, 1, id);
    if (!arg_string(LUA, 2, spec, 1024) || !arg_flags(LUA, 3, SA1_FACE_HOLD_LAST, flags)) {
        return push_nil_msg(LUA, "FaceSequence(id, \"letter:enter:hold,...\" (at most 1024 bytes) [, gsa1.FACE.HOLD_LAST])",
                            "bad_argument");
    }
    std::vector<sa1_face_entry> entries;
    std::string why;
    if (!gsa1::faces::parse_spec(spec, entries, why)) {
        return push_nil_msg(LUA, "FaceSequence: " + why, "bad_argument");
    }
    if (!c) {
        return push_nil_msg(LUA, "FaceSequence: no character of yours with that id", "not_found");
    }
    gsa1::Session *se = session();
    if (!se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    return lib_result(LUA, se, sa1_character_face_sequence(se->ctx(), id, entries.data(), (uint32_t)entries.size(), flags));
}

// gsa1.FaceScript(id, letters [, flags]) -> true | nil, message, code
GSA1_FN(gsa1_faces_FaceScript)
{
    int32_t id = 0;
    std::string letters;
    uint32_t flags = 0;
    gsa1::Character *c = face_char(LUA, 1, id);
    if (!arg_string(LUA, 2, letters, 64) || !arg_flags(LUA, 3, SA1_FACE_NOW | SA1_FACE_LOOP, flags)) {
        return push_nil_msg(LUA, "FaceScript(id, 0..64 of A-Z a-e 0 [, gsa1.FACE.NOW | LOOP])", "bad_argument");
    }
    if (letters.find('\0') != std::string::npos) {
        return push_nil_msg(LUA, "FaceScript: the letters contain a zero byte", "bad_argument");
    }
    if (!c) {
        return push_nil_msg(LUA, "FaceScript: no character of yours with that id", "not_found");
    }
    gsa1::Session *se = session();
    if (!se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    return lib_result(LUA, se, sa1_character_face(se->ctx(), id, letters.c_str(), flags));
}

// gsa1.FaceStop(id) -> true | nil, message, code
GSA1_FN(gsa1_faces_FaceStop)
{
    int32_t id = 0;
    gsa1::Character *c = face_char(LUA, 1, id);
    if (!c) {
        return push_nil_msg(LUA, "FaceStop(id of a character of yours)", id > 0 ? "not_found" : "bad_argument");
    }
    gsa1::Session *se = session();
    if (!se->ready()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    return lib_result(LUA, se, sa1_character_face_sequence(se->ctx(), id, nullptr, 0u, 0u));
}

// gsa1.FaceLevel(id, level, style [, flags]): every frame while talking; nothing returned, never an error
GSA1_FN(gsa1_faces_FaceLevel)
{
    int32_t id = 0, style = 0;
    double level = -1.0;
    gsa1::Session *se = session();
    if (!se || !se->ready() || !arg_number(LUA, 2, level)) {
        return 0;
    }
    if (!arg_int(LUA, 3, style, 0, 1)) {
        style = 0;
    }
    gsa1::Character *c = face_char(LUA, 1, id);
    if (!c || c->faulted) {
        return 0;
    }
    float lv = level < 0.0 ? -1.0f : (level > 1.0 ? 1.0f : (float)level);
    uint32_t st = style ? SA1_FACE_LEVEL_TALK : SA1_FACE_LEVEL_LADDER;
    // 0.9.4c: the faster mouth with the ladder only (a SAME_PAIR with LEVEL_TALK, or any other bit, is dropped)
    if (style == 0) {
        st |= mouth_flags(LUA, 4);
    }
    sa1_character_face_level(se->ctx(), id, lv, st);
    return 0;
}

// ---- 0.9.4c: phoneme lip sync ------------------------------------------------------------------------------------------

// gsa1.FaceMouth(id, key_a, key_b, weight [, flags]): every frame while talking; nothing returned, never an error
GSA1_FN(gsa1_faces_FaceMouth)
{
    int32_t id = 0, a = 0, b = 0;
    double w = -1.0;
    gsa1::Session *se = session();
    if (!se || !se->ready() || !arg_int(LUA, 2, a, 0, 255) || !arg_int(LUA, 3, b, 0, 255) || !arg_number(LUA, 4, w)) {
        return 0;
    }
    gsa1::Character *c = face_char(LUA, 1, id);
    if (!c || c->faulted) {
        return 0;
    }
    float wt = w < 0.0 ? -1.0f : (w > 1.0 ? 1.0f : (float)w);
    // errors (a key beyond the character's keys, a kind without a face) stay in sa1_last_error: nothing latched
    sa1_character_face_mouth(se->ctx(), id, (uint32_t)a, (uint32_t)b, wt, mouth_flags(LUA, 5));
    return 0;
}

// gsa1.MicViseme() -> cls, level, f1, f2, conf, seq
GSA1_FN(gsa1_faces_MicViseme)
{
    gsa1::mic::VisemeFrame f;
    gsa1::mic::viseme_frame(f);
    LUA->PushNumber(f.cls);
    LUA->PushNumber(f.level);
    LUA->PushNumber(f.f1);
    LUA->PushNumber(f.f2);
    LUA->PushNumber(f.conf);
    LUA->PushNumber(f.seq);
    return 6;
}

// gsa1.MicVisemeOn(on) -> true | nil, message, code
GSA1_FN(gsa1_faces_MicVisemeOn)
{
    bool on = false;
    if (!arg_bool(LUA, 1, on)) {
        return push_nil_msg(LUA, "MicVisemeOn(true / false)", "bad_argument");
    }
    gsa1::mic::viseme_on(on);
    LUA->PushBool(true);
    return 1;
}

// gsa1.MicVisemeTune(name, value) -> true | nil, message, code
GSA1_FN(gsa1_faces_MicVisemeTune)
{
    std::string name;
    if (!arg_string(LUA, 1, name, 32)) {
        return push_nil_msg(LUA, "MicVisemeTune(\"gate_min_db\" | \"adapt\" | \"smooth\" | \"reset_voice\", value)",
                            "bad_argument");
    }
    double v = 0.0;
    if (name != "reset_voice") {
        if (LUA->GetType(2) == LT::Bool) {
            v = LUA->GetBool(2) ? 1.0 : 0.0;
        } else if (!arg_number(LUA, 2, v)) {
            return push_nil_msg(LUA, "MicVisemeTune(\"" + name + "\", a number)", "bad_argument");
        }
    }
    std::string err;
    if (!gsa1::mic::viseme_tune(name, v, err)) {
        return push_nil_msg(LUA, err, "bad_argument");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.MicVisemeVoice() -> g, frames
GSA1_FN(gsa1_faces_MicVisemeVoice)
{
    float g = 0.0f;
    uint32_t frames = 0;
    gsa1::mic::viseme_voice(g, frames);
    LUA->PushNumber(g);
    LUA->PushNumber(frames);
    return 2;
}

// gsa1.VisemeMouth(kind, cls, s, size, variant, big) -> a, b, w
GSA1_FN(gsa1_faces_VisemeMouth)
{
    int32_t kind = 0, cls = 0, variant = 0;
    double s = 0.0, size = 0.0;
    bool big = false;
    int a = 0, b = 0;
    float w = 0.0f;
    if (arg_int(LUA, 1, kind, 0, 63) && arg_int(LUA, 2, cls, -1, 8) && arg_number(LUA, 3, s) && arg_number(LUA, 4, size) &&
        arg_int(LUA, 5, variant, 0, 2) && arg_bool(LUA, 6, big)) {
        gsa1::mouth::pick(kind, cls, (float)s, (float)size, variant, big, a, b, w);
    }
    LUA->PushNumber(a);
    LUA->PushNumber(b);
    LUA->PushNumber(w);
    return 3;
}

namespace {

void entry_fields(ILuaBase *L, int t, const gsa1::mouth::Entry &e)
{
    raw_num(L, t, "a", e.a);
    raw_num(L, t, "b", e.b);
    raw_num(L, t, "w", e.w);
    raw_str(L, t, "how", gsa1::mouth::how_name(e.how));
    raw_bool(L, t, "expression", e.expression != 0);
}

void entry_sub(ILuaBase *L, int t, const char *k, const gsa1::mouth::Entry &e)
{
    if (!e.present) {
        return;
    }
    L->PushString(k);
    L->CreateTable();
    entry_fields(L, L->Top(), e);
    L->RawSet(t);
}

}  // namespace

// gsa1.VisemeTable(kind) -> table | nil, message, code
GSA1_FN(gsa1_faces_VisemeTable)
{
    int32_t kind = 0;
    if (!arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1)) {
        return push_nil_msg(LUA, "VisemeTable(kind 0..8)", "bad_argument");
    }
    const gsa1::mouth::Table *tb = gsa1::mouth::table(kind);
    if (!tb) {
        return push_nil_msg(LUA, "this character has no face in the game", "unsupported");
    }
    LUA->CreateTable();
    int t = LUA->Top();
    raw_num(LUA, t, "kind", tb->kind);
    raw_num(LUA, t, "keys", tb->keys);
    raw_num(LUA, t, "floor", tb->floor);
    raw_num(LUA, t, "ladder_cap", tb->ladder_cap);
    raw_num(LUA, t, "fv_level", tb->fv_level);
    for (int c = 0; c < gsa1::viseme::COUNT; c++) {
        const gsa1::mouth::Row &r = tb->rows[c];
        LUA->PushNumber(c);
        LUA->CreateTable();
        int e = LUA->Top();
        entry_fields(LUA, e, r.normal);
        entry_sub(LUA, e, "quiet", r.quiet);
        entry_sub(LUA, e, "loud", r.loud);
        entry_sub(LUA, e, "plain", r.plain);
        LUA->RawSet(t);
    }
    return 1;
}

// gsa1.FaceState(id) -> mode, shown, from, to, rate, letter, activity | nil
GSA1_FN(gsa1_faces_FaceState)
{
    int32_t id = 0;
    gsa1::Character *c = face_char(LUA, 1, id);
    if (!c) {
        LUA->PushNil();
        return 1;
    }
    const sa1_state_ex &s = c->st;
    LUA->PushNumber(s.face_mode);
    LUA->PushBool(s.face_shown != 0);
    LUA->PushNumber(s.face_from);
    LUA->PushNumber(s.face_to);
    LUA->PushNumber(s.face_rate);
    LUA->PushNumber(s.face_letter);
    LUA->PushNumber(s.face_activity);
    return 7;
}

// gsa1.MicDevices() -> { {index, name, default, enabled}, ... } | nil, message
GSA1_FN(gsa1_faces_MicDevices)
{
    std::vector<gsa1::mic::Device> devs;
    std::string err;
    if (!gsa1::mic::devices(devs, err)) {
        return push_nil_msg(LUA, err, "unsupported");
    }
    LUA->CreateTable();
    int t = LUA->Top();
    for (size_t i = 0; i < devs.size(); i++) {
        int e = raw_subtable_i(LUA, t, (int)i + 1);
        raw_num(LUA, e, "index", devs[i].index);
        raw_str(LUA, e, "name", devs[i].name);
        raw_bool(LUA, e, "default", devs[i].is_default);
        raw_bool(LUA, e, "enabled", devs[i].enabled);
        LUA->Pop();
    }
    return 1;
}

// gsa1.MicOpen(device) -> true | nil, message, code
GSA1_FN(gsa1_faces_MicOpen)
{
    int32_t device = -1;
    int t = LUA->GetType(1);
    if (t != LT::Nil && t != LT::None && !arg_int(LUA, 1, device, -1, 63)) {
        return push_nil_msg(LUA, "MicOpen(device -1 (Windows' default) .. 63)", "bad_argument");
    }
    std::string err;
    if (!gsa1::mic::open(device, err)) {
        return push_nil_msg(LUA, err, "error");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.MicListen(on) -> true | nil, message, code
GSA1_FN(gsa1_faces_MicListen)
{
    bool on = false;
    if (!arg_bool(LUA, 1, on)) {
        return push_nil_msg(LUA, "MicListen(true / false)", "bad_argument");
    }
    std::string err;
    if (!gsa1::mic::listen(on, err)) {
        return push_nil_msg(LUA, err, "error");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.MicClose() -> true
GSA1_FN(gsa1_faces_MicClose)
{
    gsa1::mic::close();
    LUA->PushBool(true);
    return 1;
}

// gsa1.MicLevel() -> level, peak, state
GSA1_FN(gsa1_faces_MicLevel)
{
    float lv = 0.0f, pk = 0.0f;
    std::string state;
    gsa1::mic::level(lv, pk, state);
    LUA->PushNumber(lv);
    LUA->PushNumber(pk);
    LUA->PushString(state.c_str(), (unsigned int)state.size());
    return 3;
}

namespace {

void faces_open(ILuaBase *L, int t)
{
    L->PushString("FACE");
    L->CreateTable();
    int c = L->Top();
    raw_num(L, c, "MODE_GAME", SA1_FACE_MODE_GAME);
    raw_num(L, c, "MODE_EVENT", SA1_FACE_MODE_EVENT);
    raw_num(L, c, "PACE_CUTSCENE", SA1_FACE_PACE_CUTSCENE);
    raw_num(L, c, "NOW", SA1_FACE_NOW);
    raw_num(L, c, "LOOP", SA1_FACE_LOOP);
    raw_num(L, c, "HOLD_LAST", SA1_FACE_HOLD_LAST);
    raw_num(L, c, "LEVEL_LADDER", SA1_FACE_LEVEL_LADDER);
    raw_num(L, c, "LEVEL_TALK", SA1_FACE_LEVEL_TALK);
    raw_num(L, c, "ACT_NONE", SA1_FACE_ACT_NONE);
    raw_num(L, c, "ACT_SEQUENCE", SA1_FACE_ACT_SEQUENCE);
    raw_num(L, c, "ACT_SCRIPT", SA1_FACE_ACT_SCRIPT);
    raw_num(L, c, "ACT_HELD", SA1_FACE_ACT_HELD);
    raw_num(L, c, "ACT_LIPSYNC", SA1_FACE_ACT_LIPSYNC);
    raw_num(L, c, "ACT_GAMEPLAY", SA1_FACE_ACT_GAMEPLAY);
    raw_num(L, c, "SEQ_MAX", SA1_FACE_SEQ_MAX);
    raw_num(L, c, "HOLD_MAX", SA1_FACE_HOLD_MAX);
    raw_num(L, c, "ENTER_MAX", 127);
    raw_num(L, c, "MOUTH", 1);                       // 0.9.4c: gsa1.FaceMouth exists (sa1_character_face_mouth)
#if defined(SA1_FACE_SAME_PAIR)
    raw_num(L, c, "SAME_PAIR", SA1_FACE_SAME_PAIR);  // 0.9.4c: libsa1 built the faster mouth (review R.2)
#endif
    L->RawSet(t);
    // 0.9.4c: gsa1.VISEME, the sound classes
    L->PushString("VISEME");
    L->CreateTable();
    int v = L->Top();
    for (int k = 0; k < gsa1::viseme::COUNT; k++) {
        raw_num(L, v, gsa1::viseme::name(k), k);
    }
    raw_num(L, v, "COUNT", gsa1::viseme::COUNT);
    const char *subs[2] = {"NAMES", "WORDS"};
    for (int j = 0; j < 2; j++) {
        L->PushString(subs[j]);
        L->CreateTable();
        int n = L->Top();
        for (int k = 0; k < gsa1::viseme::COUNT; k++) {
            L->PushNumber(k);
            L->PushString(j == 0 ? gsa1::viseme::name(k) : gsa1::viseme::word(k));
            L->RawSet(n);
        }
        L->RawSet(v);
    }
    L->RawSet(t);
}

void faces_close(ILuaBase *L)
{
    (void)L;
    gsa1::mic::close();
}

const gsa1::FeatureFn k_faces_fns[] = {
    {"FaceInfo", gsa1_faces_FaceInfo},     {"FaceMode", gsa1_faces_FaceMode},   {"FaceSequence", gsa1_faces_FaceSequence},
    {"FaceScript", gsa1_faces_FaceScript}, {"FaceStop", gsa1_faces_FaceStop},   {"FaceLevel", gsa1_faces_FaceLevel},
    {"FaceState", gsa1_faces_FaceState},   {"MicDevices", gsa1_faces_MicDevices}, {"MicOpen", gsa1_faces_MicOpen},
    {"MicListen", gsa1_faces_MicListen},   {"MicClose", gsa1_faces_MicClose},   {"MicLevel", gsa1_faces_MicLevel},
    // 0.9.4c (version 2)
    {"MicViseme", gsa1_faces_MicViseme},   {"MicVisemeOn", gsa1_faces_MicVisemeOn},
    {"MicVisemeTune", gsa1_faces_MicVisemeTune}, {"MicVisemeVoice", gsa1_faces_MicVisemeVoice},
    {"VisemeMouth", gsa1_faces_VisemeMouth}, {"VisemeTable", gsa1_faces_VisemeTable},
    {"FaceMouth", gsa1_faces_FaceMouth},
};

}  // namespace

// version 1 (0.9.4a): the functions up to MicLevel; version 2 (0.9.4c, phoneme lip sync): MicViseme, MicVisemeOn,
// MicVisemeTune, MicVisemeVoice, VisemeMouth, VisemeTable, FaceMouth, FaceLevel's flags, gsa1.VISEME, gsa1.FACE.MOUTH /
// SAME_PAIR
GSA1_FEATURE(faces, 2, k_faces_fns, faces_open, faces_close, gsa1::kCloseDefault);

#endif  // SA1_API_FACE
