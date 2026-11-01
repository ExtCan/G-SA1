// G-SA1 core: the feature "board" (round 0.9.5; see board.hpp).
#include "board.hpp"

#include <cmath>
#include <cstring>

#include "audio.hpp"

namespace gsa1 {
namespace board {

const char *const kReasonKind = "only Sonic and Tails ride a board";
const char *const kReasonSuper = "Super Sonic doesn't ride a board";
const char *const kReasonNotRiding = "not riding";
const char *const kReasonNoKept = "no board left behind";
const char *const kReasonCarrying = "carrying something";
const char *const kReasonRefused = "can't get on a board now";
const char *const kReasonPuppet = "a puppet doesn't ride a board";
const char *const kReasonNoApi = "this libsa1 has no board (round 0.9.5, SA1_API_BOARD)";

#if defined(SA1_API_BOARD)
// the contract (gsa1_095_plan.md 5.3): G-SA1's numbers are libsa1's
static_assert(kOff == SA1_BOARD_OFF && kOn == SA1_BOARD_ON && kPush == SA1_BOARD_PUSH && kFree == SA1_BOARD_FREE,
              "sa1_board_desc.on");
static_assert(kTerrainMap == SA1_BOARD_TERRAIN_MAP && kTerrainSnow == SA1_BOARD_TERRAIN_SNOW &&
                  kTerrainSand == SA1_BOARD_TERRAIN_SAND,
              "SA1_BOARD_TERRAIN_*");
static_assert(kFlagStartPush == SA1_BOARD_START_PUSH && kFlagRemoveOnExit == SA1_BOARD_REMOVE_ON_EXIT &&
                  kFlagFaithfulExit == SA1_BOARD_FAITHFUL_EXIT && kFlagKeepFallen == SA1_BOARD_KEEP_FALLEN &&
                  kFlagReuseKept == SA1_BOARD_REUSE_KEPT && kFlagsKnown == SA1_BOARD_KNOWN_FLAGS,
              "SA1_BOARD_* flags");
static_assert(kStateOnBoard == SA1_STATE_ON_BOARD, "SA1_STATE_ON_BOARD");
static_assert(kEventBoard == SA1_EVENT_BOARD && kEvOn == SA1_BOARD_EV_ON && kEvOff == SA1_BOARD_EV_OFF &&
                  kEvRefused == SA1_BOARD_EV_REFUSED && kEvFreed == SA1_BOARD_EV_FREED && kEvPush == SA1_BOARD_EV_PUSH,
              "SA1_EVENT_BOARD / SA1_BOARD_EV_*");
static_assert(kBsOn == SA1_BSTATE_ON && kBsPending == SA1_BSTATE_PENDING && kBsHeld == SA1_BSTATE_HELD &&
                  kBsKept == SA1_BSTATE_KEPT && kBsSettled == SA1_BSTATE_SETTLED && kSettleSteps == SA1_BOARD_SETTLE_STEPS,
              "SA1_BSTATE_*");
#endif
#if defined(SA1_DRAW_BOARD)
static_assert(kDrawBoard == SA1_DRAW_BOARD, "SA1_DRAW_BOARD");
#endif
#if defined(SA1_PREVIEW_BOARD)
static_assert(kPreviewBoard == SA1_PREVIEW_BOARD, "SA1_PREVIEW_BOARD");
#endif
#if defined(SA1_SURFACE_BOARD_SNOW)
static_assert(kSurfaceBoardSnow == SA1_SURFACE_BOARD_SNOW && kSurfaceBoardSand == SA1_SURFACE_BOARD_SAND,
              "SA1_SURFACE_BOARD_*");
#endif

bool rider(int32_t kind, int32_t mode, uint32_t state_flags)
{
    if (kind == kKindSonic) {
        return (state_flags & kStateOnBoard) != 0 || (mode >= kSonicModeFirst && mode <= kSonicModeLast);
    }
    if (kind == kKindTails) {
        return (state_flags & kStateOnBoard) != 0 || (mode >= kTailsModeFirst && mode <= kTailsModeLast);
    }
    return false;
}

bool board_tone(uint32_t tone)
{
    return (tone >= kSnowToneFirst && tone <= kSnowToneLast) || (tone >= kSandToneFirst && tone <= kSandToneLast);
}

void stage_rules(bool on, StageRule &snow, StageRule &sand)
{
    snow = StageRule();
    sand = StageRule();
    if (on) {
        snow.stage = kStageIceCap;
        snow.first = kSnowToneFirst;
        snow.last = kSnowToneLast;
        sand.stage = kStageSandHill;
        sand.first = kSandToneFirst;
        sand.last = kSandToneLast;
    }
}

bool apply_rules(Audio &audio, int32_t id, bool on)
{
    if (!audio.has_stage_rules() || id <= 0) {
        return false;
    }
    StageRule snow, sand;
    stage_rules(on, snow, sand);
    audio.set_stage_rule(id, kRuleBoardSnow, snow);   // (a refusal stays recorded: tried again at the next install)
    audio.set_stage_rule(id, kRuleBoardSand, sand);
    return true;
}

bool admit(bool sounds_on, bool is_rider, uint32_t event_type, uint32_t tone)
{
    if (sounds_on || !is_rider || event_type != (uint32_t)SA1_EVENT_SOUND) {
        return true;
    }
    return !board_tone(tone);
}

void on_event(Track &t, uint32_t id, uint32_t arg, bool holding)
{
    switch (id) {
    case kEvOn:
        t.ev_on++;
        t.last_on_mode = arg;
        break;
    case kEvOff:
        t.ev_off++;
        t.last_off_arg = arg;
        break;
    case kEvRefused:
        t.ev_refused++;
        t.refused = true;
        t.refused_reason = holding ? kReasonCarrying : kReasonRefused;
        break;
    case kEvFreed:
        t.ev_freed++;
        t.freed++;
        t.freed_why = arg <= 3u ? (int32_t)arg : 3;
        break;
    case kEvPush:
        t.ev_push++;
        break;
    default:
        break;
    }
}

bool take_refusal(Track &t, std::string &reason)
{
    if (!t.refused) {
        return false;
    }
    t.refused = false;
    reason = t.refused_reason;
    return true;
}

uint32_t take_freed(Track &t, int32_t &why)
{
    uint32_t n = t.freed;
    why = n ? t.freed_why : -1;
    t.freed = 0;
    t.freed_why = -1;
    return n;
}

// Source's MatrixAngles (mathlib): forward = column 0, left = column 1, up = column 2
void rotation_angles(const float rot[9], float out[3])
{
    const double rad2deg = 57.29577951308232;
    double fx = rot[0], fy = rot[3], fz = rot[6];
    double lx = rot[1], ly = rot[4], lz = rot[7];
    double uz = rot[8];
    double xy = std::sqrt(fx * fx + fy * fy);
    double p, y, r;
    if (xy > 0.001) {
        y = std::atan2(fy, fx);
        p = std::atan2(-fz, xy);
        r = std::atan2(lz, uz);
    } else {
        y = std::atan2(-lx, ly);
        p = std::atan2(-fz, xy);
        r = 0.0;
    }
    out[0] = (float)(p * rad2deg);
    out[1] = (float)(y * rad2deg);
    out[2] = (float)(r * rad2deg);
    for (int k = 0; k < 3; k++) {
        if (!std::isfinite(out[k])) {
            out[k] = 0.0f;
        }
    }
}

// Source's AngleMatrix
void angles_rotation(const float ang[3], float rot[9])
{
    const double deg2rad = 0.017453292519943295;
    double sp = std::sin(ang[0] * deg2rad), cp = std::cos(ang[0] * deg2rad);
    double sy = std::sin(ang[1] * deg2rad), cy = std::cos(ang[1] * deg2rad);
    double sr = std::sin(ang[2] * deg2rad), cr = std::cos(ang[2] * deg2rad);
    rot[0] = (float)(cp * cy);
    rot[3] = (float)(cp * sy);
    rot[6] = (float)(-sp);
    rot[1] = (float)(sr * sp * cy - cr * sy);
    rot[4] = (float)(sr * sp * sy + cr * cy);
    rot[7] = (float)(sr * cp);
    rot[2] = (float)(cr * sp * cy + sr * sy);
    rot[5] = (float)(cr * sp * sy - sr * cy);
    rot[8] = (float)(cr * cp);
}

const char *code_of(sa1_status st)
{
    switch (st) {
    case SA1_ERR_UNSUPPORTED: return "unsupported";
    case SA1_ERR_NOT_LOADED: return "not_ready";
    case SA1_ERR_GAME_FAULT:
    case SA1_ERR_NOT_IMPLEMENTED: return "fault";
    case SA1_ERR_INVALID_ARGUMENT: return "bad_argument";
    case SA1_ERR_NOT_FOUND: return "not_found";
    default: return "error";
    }
}

#if defined(SA1_API_BOARD)

bool refresh(sa1_context *ctx, int32_t id, Track &t)
{
    View v;
    if (!ctx) {
        t.view = v;
        return false;
    }
    sa1_board_state s;
    std::memset(&s, 0, sizeof s);
    s.struct_size = sizeof s;
    if (sa1_character_board_state(ctx, (sa1_character_id)id, &s) != SA1_OK) {
        t.view = v;
        return false;
    }
    v.valid = true;
    v.flags = s.flags;
    v.terrain = s.terrain;
    v.board_task = s.board_task;
    v.push_steps = s.push_steps;
    v.saved_jmp_y_spd = s.saved_jmp_y_spd;
    v.kind = s.board_kind;
    v.variant = s.board_variant;
    bool finite = true, zero = true;
    for (int k = 0; k < 3; k++) {
        finite = finite && std::isfinite(s.model_position[k]);
    }
    for (int k = 0; k < 9; k++) {
        finite = finite && std::isfinite(s.model_rotation[k]);
        zero = zero && s.model_rotation[k] == 0.0f;
    }
    if (finite) {
        std::memcpy(v.pos, s.model_position, sizeof v.pos);
        if (!zero) {
            std::memcpy(v.rot, s.model_rotation, sizeof v.rot);
        }
    }
    v.still_steps = s.still_steps;
    t.view = v;
    return true;
}

sa1_status call(sa1_context *ctx, int32_t id, int32_t on, uint32_t terrain, uint32_t flags, std::string &err)
{
    if (!ctx) {
        err = "G-SA1 is not initialised";
        return SA1_ERR_NOT_LOADED;
    }
    sa1_board_desc d;
    std::memset(&d, 0, sizeof d);
    d.struct_size = sizeof d;
    d.on = on;
    d.terrain = terrain;
    d.flags = flags;
    sa1_status st = sa1_character_board(ctx, (sa1_character_id)id, &d);
    if (SA1_FAILED(st)) {
        const char *e = sa1_last_error(ctx);
        err = (e && *e) ? std::string(e) : std::string(sa1_status_string(st));
    }
    return st;
}

#else  // a libsa1 without the board: nothing to read, every call refused

bool refresh(sa1_context *, int32_t, Track &t)
{
    t.view = View();
    return false;
}

sa1_status call(sa1_context *, int32_t, int32_t, uint32_t, uint32_t, std::string &err)
{
    err = kReasonNoApi;
    return SA1_ERR_UNSUPPORTED;
}

#endif

}  // namespace board
}  // namespace gsa1
