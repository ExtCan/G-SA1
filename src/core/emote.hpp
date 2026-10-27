// G-SA1 core: the shared part of the feature "emote" (round 0.9.4a: sadc docs/research/faces_wheel_plan.md 4.5, 4.6,
// 5.6 with its Review R.9 / R.16 / R.18; libsa1.h "emotes", SA1_API_EMOTE). The module's Lua functions
// (src/module/bind_emote.cpp) and the offline test on the disc (tests/feat_emote_test.cpp) use it: the slot keys, a
// character's catalogue as a vector, one play call. Nothing here keeps state; everything runs on the caller's thread
// (the game's: the context is not thread-safe).
//
// Keys: an action row is "a<row>" (SA1_EMOTE_ROW), an extra motion "x<index>" (SA1_EMOTE_EXTRA, the index among the
// kind's offered extras in list order) - the keys of data/gsa1/emote_wheel.txt (faces_wheel_plan.md 8.1).
#ifndef GSA1_EMOTE_HPP
#define GSA1_EMOTE_HPP

#include <cstdint>
#include <string>
#include <vector>

#include "libsa1.h"

namespace gsa1 {

#if defined(SA1_API_EMOTE)
const bool kEmoteApi = true;
#else
const bool kEmoteApi = false;
#endif

// G-SA1's own play flag (gsa1.EMOTE.LOOP): the item plays SA1_EMOTE_PLAY_LOOP ("loop it" on a wheel slot)
const uint32_t kEmoteLoop = 0x100u;
// the libsa1 flags a caller may pass through (SA1_EMOTE_IN_AIR | KEEP_INPUT | NO_PROPS | NO_TRAIL, and SA1_EMOTE_HOLD
// with SA1_API_EMOTE_HOLD: round 0.9.4b, the wheel's "Hold the last pose"); SA1_EMOTE_CHAIN is always set by emote_play
// (0 without SA1_API_EMOTE)
uint32_t emote_pass_flags();
// the highest key index accepted ("a999")
const uint32_t kEmoteKeyMax = 999u;

struct EmoteEntry {
    std::string key;            // "a75" / "x3"
    uint32_t source = 0;        // SA1_EMOTE_ROW / SA1_EMOTE_EXTRA
    uint32_t index = 0;
    std::string name;           // the internal name ("s_kimepose0"); may be empty
    std::string label;          // the SA Tools label
    uint32_t cls = 0;           // SA1_EMOTE_CLASS_*
    uint32_t flags = 0;         // SA1_EMOTE_F_*
    uint32_t frames = 0;        // NJS_MOTION.nbFrame
    int32_t play = 0;           // SA1_EMOTE_PLAY_LOOP / SA1_EMOTE_PLAY_ONCE
    int32_t dup_of = -1;        // the list position (0-based) of the first entry with the same drawn object and motion
};

// "a<row>" / "x<extra>" with 0..kEmoteKeyMax (no sign, no blanks, no leading zeros but "0") -> source, index
bool emote_parse_key(const std::string &key, uint32_t &source, uint32_t &index);
std::string emote_key(uint32_t source, uint32_t index);
// how an entry plays by default: "hold" (SA1_EMOTE_F_HOLD: once, the game holds the last frame), "loop", "once"
const char *emote_play_name(int32_t play, uint32_t flags);
// the class's word ("stand", "idle", "pose", ..., "super"); "?" for an unknown class
const char *emote_class_name(uint32_t cls);
// the catalogue of (kind, form): sa1_emote_count / sa1_emote_get. false + err without the disc or the API; an empty list
// (Eggman, Tikal, a kind without the form) is true
bool emote_list(const sa1_context *ctx, int32_t kind, uint32_t form, std::vector<EmoteEntry> &out, std::string &err);
// plays one entry on character id (latched by libsa1, started at the character's next pair): one item, SA1_EMOTE_CHAIN,
// link -1 (8 frames), speed 1; flags = kEmoteLoop | emote_pass_flags() bits. SA1_ERR_UNSUPPORTED without the API
sa1_status emote_play(sa1_context *ctx, int32_t id, uint32_t source, uint32_t index, uint32_t flags);
// sa1_character_emote_stop (how: SA1_EMOTE_STOP_NOW / STOP_BLEND)
sa1_status emote_stop(sa1_context *ctx, int32_t id, uint32_t how);
// the reason of a failed call in libsa1's plain words (sa1_last_error, else the status text)
std::string emote_error(const sa1_context *ctx, sa1_status st);
// the module's code word of a failed status: "unsupported", "bad_argument", "not_found", "limit", "not_ready", "fault",
// "error"
const char *emote_code(sa1_status st);

}  // namespace gsa1

#endif
