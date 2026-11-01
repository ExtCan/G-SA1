// G-SA1 core: the feature "board" (round 0.9.5: sadc docs/research/gsa1_095_plan.md 4.4-4.13, 5.3 / 5.4 with its Review
// R.1-R.13; board095_gsa1.md 4.2-4.5, 7; libsa1.h "the board", SA1_API_BOARD). No GMod dependency: the module's
// src/module/bind_board.cpp and the offline tests (tests/feat_board_test.cpp, the census ride of tests/core_test.cpp) drive
// exactly this code.
//
// What libsa1 gives (5.3): Sonic's and Tails' sand / snow board by the game's own code - sa1_character_board(ON) posts the
// stage code's order 44 and makes the board task (8C0B2EE6 / 8C0BF7CE) in the character's world, OFF posts Ice Cap's goal
// order 24; the board task follows the player while his action is a board action and is the game's free object (a KEPT
// board) otherwise; sa1_character_board_state reports the board (its drawn pose, held / kept / settled, the push, Tails' saved
// jump) and SA1_EVENT_BOARD the edges (ON, OFF, REFUSED, FREED, PUSH).
//
// What G-SA1 keeps here, per CHARACTER (Character::board: 0.9.6's followers board through their own characters):
//   * the last sa1_board_state as G-SA1's own View (read after every tick and after every board call), so Lua reads it per
//     frame without a libsa1 call;
//   * the one-shot answers fed from SA1_EVENT_BOARD by the session's event pump: a refusal (true once, with its reason:
//     "carrying something" when the character holds an object, else "can't get on a board now") and the frees (how many
//     since the last read, and why: 0 REMOVE_ON_EXIT, 1 fell, 2 replaced by a new ON, 3 FREE);
//   * whether the session holds the character's two board stage rules (Session::board_rules: Ice Cap's tones 208-238 from
//     stage 8, Sand Hill's 690-698 from stage 38, libsa1_audio.h's stage rules; audio.hpp kRuleBoardSnow / kRuleBoardSand).
// A character re-created gets a new Character, hence a fresh Track (the board core is reset with it).
//
// The numbers below are the contract's (gsa1_095_plan.md 5.3) as G-SA1's own constants, so the pure parts build and are
// tested against any libsa1.h; with the 0.9.5 header board.cpp ties each one to libsa1's macro (static_assert). Everything
// that calls libsa1's board API compiles only #if defined(SA1_API_BOARD) (the round-start snapshot has none: the calls then
// answer "this libsa1 has no board").
#pragma once

#include <cstdint>
#include <string>

#include "libsa1_internal_api.hpp"

namespace gsa1 {

class Session;
struct Character;
struct StageRule;
class Audio;

namespace board {

#if defined(SA1_API_BOARD)
const bool kAvailable = true;
#else
const bool kAvailable = false;
#endif

// sa1_board_desc.on
const int32_t kOff = 0, kOn = 1, kPush = 2, kFree = 3;
// sa1_board_desc.terrain (gsa1.BOARD.TERRAIN_*)
const uint32_t kTerrainMap = 0u, kTerrainSnow = 1u, kTerrainSand = 2u;
// sa1_board_desc.flags
const uint32_t kFlagStartPush = 0x01u, kFlagRemoveOnExit = 0x02u, kFlagFaithfulExit = 0x04u, kFlagKeepFallen = 0x08u,
               kFlagReuseKept = 0x10u, kFlagsKnown = 0x1Fu;
// sa1_state.flags: player 0 is in a board mode
const uint32_t kStateOnBoard = 0x10u;
// sa1_event.type of the board's events, and their ids
const uint32_t kEventBoard = 15u;
const uint32_t kEvOn = 1u, kEvOff = 2u, kEvRefused = 3u, kEvFreed = 4u, kEvPush = 5u;
// sa1_board_state.flags
const uint32_t kBsOn = 0x01u, kBsPending = 0x02u, kBsHeld = 0x04u, kBsKept = 0x08u, kBsSettled = 0x10u;
const uint32_t kSettleSteps = 30u;
// SA1_DRAW_BOARD, SA1_PREVIEW_BOARD, SA1_SURFACE_BOARD_SNOW / _SAND
const uint32_t kDrawBoard = 0x4000u;
const uint32_t kPreviewBoard = 0x100u;
const uint32_t kSurfaceBoardSnow = 0x100000u, kSurfaceBoardSand = 0x200000u;
// the board modes (taskwk.mode of player 0): Sonic 62-68, Tails 48-54 (libsa1's rider test, sa1_world_emote.c)
const int32_t kSonicModeFirst = 62, kSonicModeLast = 68, kTailsModeFirst = 48, kTailsModeLast = 54;
// the board's tones and the stages whose banks hold them (board095_lib.md 2.3 H, 2.4; libsa1_audio.h's stage rules)
const uint32_t kSnowToneFirst = 208u, kSnowToneLast = 238u;     // Ice Cap's: 237 the snow lean, 231 the jump loop ...
const uint32_t kSandToneFirst = 690u, kSandToneLast = 698u;     // Sand Hill's: 690 the ride loop (18.6 s), 691 the lean
const int32_t kStageIceCap = 8, kStageSandHill = 38;
// sa1_character_kind numbers G-SA1 boards (SA1_CHAR_SONIC / SA1_CHAR_TAILS) and Super Sonic's (kind 8: never)
const int32_t kKindSonic = 0, kKindTails = 2, kKindSuperSonic = 8;

// the plain reasons (gsa1_095_plan.md 5.4)
extern const char *const kReasonKind;          // "only Sonic and Tails ride a board"
extern const char *const kReasonSuper;         // "Super Sonic doesn't ride a board"
extern const char *const kReasonNotRiding;     // "not riding"
extern const char *const kReasonNoKept;        // "no board left behind"
extern const char *const kReasonCarrying;      // "carrying something"
extern const char *const kReasonRefused;       // "can't get on a board now"
extern const char *const kReasonPuppet;        // "a puppet doesn't ride a board"
extern const char *const kReasonNoApi;         // "this libsa1 has no board (round 0.9.5, SA1_API_BOARD)"

// G-SA1's copy of sa1_board_state (host space; zero / identity / -1 without a board)
struct View {
    bool valid = false;            // read from libsa1 (false: no board API, no character, or the read failed)
    uint32_t flags = 0;            // kBs*
    uint32_t terrain = 0;          // kTerrain* in force (MAP when not riding)
    uint32_t board_task = 0;       // guest address of the world's board task (0: none)
    uint32_t push_steps = 0;       // steps the running start push still has
    float saved_jmp_y_spd = 0.0f;  // Tails: restored at the end of the ride (0: none saved)
    int32_t kind = -1;             // whose board: 0 Sonic / 2 Tails, -1 none
    uint32_t variant = 0;          // Sonic: 0 MIW_B001, 1 SB_BOARD1; Tails 0 (MTX_BOARD0)
    float pos[3] = {0, 0, 0};      // the board model's origin as the game drew it in the last pair (HU)
    float rot[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};   // that model's rotation, row-major, host axes
    uint32_t still_steps = 0;      // steps a kept board has rested
};

// one character's board (Character::board)
struct Track {
    View view;
    // from the event pump (SA1_EVENT_BOARD); the one-shot fields are cleared by take_refusal / take_freed
    bool refused = false;          // a refusal not read yet
    std::string refused_reason;    // its plain reason
    uint32_t freed = 0;            // frees since the last read
    int32_t freed_why = -1;        // the last free's EV_FREED arg (0..3), -1 none since the last read
    uint64_t ev_on = 0, ev_off = 0, ev_refused = 0, ev_freed = 0, ev_push = 0;   // all the character's board events
    uint32_t last_on_mode = 0, last_off_arg = 0;   // EV_ON's / EV_OFF's arg
    // the session's sound side
    bool rider = false;            // player 0 is in a board mode after the last tick (rider())
    bool rules_on = false;         // the two board stage rules are set for this character
    uint64_t tones_muted = 0;      // board tones of this rider kept out of the mixer (gsa1.BoardSounds(false))
};

// player 0 of a world of kind `kind` rides a board: kStateOnBoard in the state's flags, or a board mode of its kind
bool rider(int32_t kind, int32_t mode, uint32_t state_flags);
// a tone of the board's two stage rules (208-238 Ice Cap, 690-698 Sand Hill)
bool board_tone(uint32_t tone);
// the two stage rules of a rider (on) or the cleared slots (off: stage -1)
void stage_rules(bool on, StageRule &snow, StageRule &sand);
// the board's rules of character id into audio's registry (kRuleBoardSnow / kRuleBoardSand); false when this libsa1 has no
// stage rules (nothing recorded)
bool apply_rules(Audio &audio, int32_t id, bool on);
// the sound guard of gsa1.BoardSounds: false = keep the event out of the mixer (only SA1_EVENT_SOUND of a board tone from a
// rider while the board sounds are off; a SOUND_STOP always passes, so a loop playing ends)
bool admit(bool sounds_on, bool is_rider, uint32_t event_type, uint32_t tone);

// SA1_EVENT_BOARD of the character: the counters and the one-shot fields; `holding` = the character holds an object now
// (sa1_state_ex.held_object), which names the refusal's reason
void on_event(Track &t, uint32_t id, uint32_t arg, bool holding);
// the one-shot refusal (true once after an EV_REFUSED, with its reason); clears it
bool take_refusal(Track &t, std::string &reason);
// the frees since the last read and the last one's why (-1: none); clears them
uint32_t take_freed(Track &t, int32_t &why);

// a host-axes rotation (row-major; columns = the model's forward / left / up in host space, Source's matrix3x4 layout) ->
// a Source Angle (pitch, yaw, roll in degrees, as Angle:Forward() / :Right() / :Up() would rebuild it; Source's MatrixAngles)
void rotation_angles(const float rot[9], float out[3]);
// the inverse (Source's AngleMatrix), for the tests
void angles_rotation(const float ang[3], float rot[9]);

// libsa1's state of character id into t.view (false: no board API / no such character: t.view.valid false)
bool refresh(sa1_context *ctx, int32_t id, Track &t);
// sa1_character_board(id, {on, terrain, flags}): SA1_OK or libsa1's status, err = libsa1's plain words. Without the board
// API: SA1_ERR_UNSUPPORTED, kReasonNoApi
sa1_status call(sa1_context *ctx, int32_t id, int32_t on, uint32_t terrain, uint32_t flags, std::string &err);
// the module's code word of a failed status: "unsupported", "not_ready", "fault", "bad_argument", "not_found", "error"
const char *code_of(sa1_status st);

}  // namespace board
}  // namespace gsa1
