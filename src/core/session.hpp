// G-SA1 core: one libsa1 context and the characters of one Lua state (no GMod dependency, so the
// offline tests drive exactly the code the module runs).
//
// Units: everything is host space = Source / Hammer units (libsa1's SOURCE preset: 4.0 HU per SA1 unit,
// host = 4 * (x, -z, y)); yaws are radians here (the module converts Lua degrees).
//
// Rendering (libsa1 render API, SA1_API_RENDER): every host frame Session::render() takes
// sa1_character_render (the game's draws of the last pair, interpolated between the last two pairs by libsa1)
// and sorts the draws into batches: one batch per render state (texture archive / index / address mode,
// SA1_DRAW_* flags, blend factors). Opaque batches merge every draw of the same state; blended batches keep
// the game's draw order (consecutive draws of the same state merge). Session::prepare_view() then writes each
// batch's vertices in Source's winding for the current camera (sprites and lines become camera-facing quads,
// environment maps get sphere-map UVs); the module streams them into GMod's mesh builder.
//
// Threads (0.5.1): the disc loads on a worker (init_async: sa1_init + sa1_load_disc with SA1_LOAD_WORLD_IMAGES, so
// the first world of every kind is cheap too) and poll_init() installs the context on the game's thread; the sound
// banks open on a worker of their own (Audio, a private libsa1 context); the map's collision is prepared by the map
// job (prepare.hpp) and installed with set_world_prepared (O(1)). Everything else runs on the game's thread. The log
// callback is the one thing libsa1 may call from a worker: log_line is thread-safe.
#pragma once

#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "audio.hpp"
#include "libsa1_internal_api.hpp"
#include "movers.hpp"
#include "prepare.hpp"
#include "util.hpp"

namespace gsa1 {

// Host stick -> sa1_input stick through the inverse of the game's dead zone. The game's analog conversion
// (8C05117E) subtracts 12 pad units from each axis and counts 0 as positive, so an axis at exactly 0 (any keyboard
// direction along an axis) would turn the run direction by about 6 degrees; mapped through this inverse the game
// decodes the intended direction and stroke exactly (the game code itself is unchanged).
void exact_stick(float x, float y, float &stick_x, float &stick_y);

// The characters' upgrades. In the game they are event flags (one byte each at B_8C799920[flag], set by the story
// when an upgrade is found): PInitialize (8C06C350, the player's first step) turns the character's flags into
// playerwk.equipment bits, which the character code tests; Big's four lures have no equipment bit, the fishing code
// counts their flags (8C0E6E80) whenever it needs the lure. Super Sonic (equipment 0x8000, the story's last stage)
// is not offered. The table is in session.cpp (upgrade_table) with the decompiled code each entry comes from.
// 0.9.3a (sadc docs/research/super_general_design.md 6.5, D12): Super Sonic (Vs. Perfect Chaos, kind 8) has Sonic's rows
// (upgrade_kind 8 -> 0): find_upgrade(8, name) finds Sonic's, and create() writes Sonic's event flags into a kind-8 world
// (the game keeps the low equipment bits when he turns back: 0x8007 while Super, 0x0007 afterwards).
int32_t upgrade_kind(int32_t kind);
struct UpgradeDef {
    int32_t kind;              // SA1_CHAR_*
    const char *name;          // API / ConVar name (gsa1_upgrade_<name>)
    const char *title;
    uint16_t flag;             // the game's event flag (0..511)
    uint16_t equipment;        // the playerwk.equipment bit PInitialize sets for it (0: none, Big's lures)
};
const UpgradeDef *upgrade_table(size_t &count);
const UpgradeDef *find_upgrade(int32_t kind, const std::string &name);
const uint32_t kEventFlagsAddr = 0x8C799920u;   // B_8C799920: the game's 512 event flags (func_8C09068E reads them)

// Texture variant of a batch (the render target's sampler state; the Lua side keeps one render target per
// (kind, archive, texture, wrap)).
enum : uint32_t {
    WRAP_CLAMP_U = 0x1u,   // SA1_MAT_CLAMP_U
    WRAP_CLAMP_V = 0x2u,   // SA1_MAT_CLAMP_V
    WRAP_POINT = 0x4u,     // SA1_MAT_FILTER 0 (point sampling)
    // 0.8 (sadc docs/research/gsa1_060_shadow.md G3 with its review R.3.3): the blob shadow drawn as a darkening mask.
    // A SA1_DRAW_SHADOW batch blended SRC_ALPHA / INV_SRC_ALPHA whose texture is black in every texel (OBJ_REGULAR's
    // "shadow") gives dst * (1 - a * tex.a) with a = the diffuse alpha: the Lua side paints that texture's render target
    // with RGB = the texel's alpha and draws the batch with ZERO / ONE_MINUS_SRC_COLOR; prepare_view writes the vertex
    // colours (a, a, a, 255). It needs no alpha in the render target.
    WRAP_MASK = 0x8u,
    // 0.9.4a (sadc docs/research/super2_plan.md 6.4 task 2; libsa1's SA1_DRAW_SUPER_GOLD of SA1_SUPOPT_LSD_GOLD): a textured
    // draw libsa1 marked gold (the Light Speed charge's plain sparkles and streaks while General Super Sonic is Super)
    // draws the texture's SA1_TEXTURE_VARIANT_SUPER_GOLD (gsa1.Texture(kind, index, archive, 1)): its own render target
    // and material, never merged with the game-coloured ones. Untextured gold draws (the charged glow) need nothing: libsa1
    // gives them gold vertex colours
    WRAP_GOLD = 0x10u,
};

// SA1_DRAW_* bits that select a batch's material (the others are informational). SA1_DRAW_SHADOW (libsa1 of G-SA1 0.8):
// the game's blob shadow gets batches of its own, drawn with their own switch (gsa1_shadow) before the effects test.
// 0.9.4 (sadc docs/research/gsa1_094_plan.md review R.1): SA1_DRAW_OBJECT (libsa1 0.4: a ring, a ring's sparkle or blob
// shadow, an item box, drawn by its own task) too, so a game object's draw never shares a batch with the character's
// own (a ring's blob shadow and Sonic's are two batches) and the batch's flags show it: the addon draws OBJECT batches
// with its object switch (gsa1_set_draw), in first person too
#if defined(SA1_DRAW_OBJECT)
const uint32_t kBatchObjectFlag = SA1_DRAW_OBJECT;
#else
const uint32_t kBatchObjectFlag = 0u;
#endif
const uint32_t kBatchKeyFlags = SA1_DRAW_BLEND | SA1_DRAW_ALPHA_TEST | SA1_DRAW_DOUBLE_SIDED | SA1_DRAW_ENV_MAP |
                                SA1_DRAW_UNLIT | SA1_DRAW_PALETTE_LIT | SA1_DRAW_EFFECT | SA1_DRAW_NO_TEXTURE |
                                SA1_DRAW_ADDITIVE | SA1_DRAW_SHADOW | kBatchObjectFlag;
// a batch never holds more triangles than this (one mesh.Begin; Source's dynamic vertex buffer). 0.9.4 (review R.1): a
// libsa1 draw above it (libsa1 merges consecutive same-state draws: 84+ rings in a row) is split over batches (0.9.3a
// skipped it whole)
const uint32_t kMaxBatchTriangles = 8000;
// 0.9.1 (translucency T1, sadc docs/research/gsa1_070_translucency.md section 7 with its review R3.2): the exact vertex
// alphas a character's lit translucent batch state keeps in its key; more are rounded to multiples of 17 (16 steps), so a
// future fading lit draw cannot make a material per frame
const uint32_t kMaxLitAlphas = 8;

struct RenderBatch {
    uint32_t pass = 0;              // 0: opaque (ENT:Draw), 1: blended (ENT:DrawTranslucent, in this list's order)
    int32_t archive = -1;           // sa1_texture_get(kind, archive, texture); -1 = untextured
    int32_t texture = -1;
    uint32_t flags = 0;             // SA1_DRAW_* of the batch (kBatchKeyFlags bits are the same for every draw)
    uint32_t all_flags = 0;         // OR of every draw's SA1_DRAW_* (AFTERIMAGE, USE_ALPHA, ...)
    uint32_t material = 0;          // the first draw's Ninja attribute word
    uint8_t blend_src = SA1_BLEND_ONE, blend_dst = SA1_BLEND_ZERO;
    uint8_t source = 0;             // SA1_SOURCE_* of the first draw
    uint8_t prims = 0;              // bit (1 << SA1_PRIM_*) per primitive kind in the batch
    uint32_t wrap = 0;              // WRAP_*
    uint32_t order = 0;             // the first draw's game order
    uint32_t triangles = 0;         // output triangles (sprites and line segments: 2 each)
    // 0.9.1 (translucency T1): the draws' vertex alpha of a lit translucent batch (pass 1, not SA1_DRAW_UNLIT, not the
    // shadow's mask): Source's VertexLitGeneric ignores $vertexalpha, so the Lua side puts it into the material ($alpha).
    // Every draw of such a batch has this alpha (draws of other alphas start a batch of their own); the key ends in
    // ".a<alpha>" when it is below 255. 255 for every other batch (unlit materials honour the vertex alpha themselves).
    uint8_t alpha = 255;
    std::string key;                // the render state as text (the Lua side's material cache key)
    std::vector<uint32_t> draws;    // indices into Character::r_draws, in the game's order
    // prepare_view(): 3 vertices per triangle, Source winding (clockwise fronts unless flipped)
    std::vector<float> pos;         // 3 per vertex, host space (absolute, or relative to ViewOptions::origin)
    std::vector<float> nrm;         // 3 per vertex
    std::vector<float> uv;          // 2 per vertex
    std::vector<uint8_t> col;       // 4 per vertex (RGBA8)
    // prepare_view() (round 4c E1, sadc docs/research/gsa1_lsd_lag.md 7.2): what the batch's material reads, so EmitBatch
    // skips the mesh calls it would ignore - mesh.Normal for unlit materials (UnlitGeneric: SA1_DRAW_UNLIT or the
    // lighting off), mesh.TexCoord for untextured ones (vgui/white is the same at every UV) unless sphere-mapped
    bool need_normal = true;
    bool need_uv = true;
};

struct ViewOptions {
    bool flip = false;              // keep libsa1's counter-clockwise fronts (gsa1_flip_winding)
    bool vertex_color = true;       // multiply textured non-palette-lit draws by their vertex colour (gsa1_vertexcolor;
                                    // untextured draws always keep it: round 4c F6)
    float line_pixels = 2.0f;       // njDrawLine3D segments: width in pixels (75 degree view, 1080 lines)
    bool lit = true;                // the materials are lit (gsa1_lighting): VertexLitGeneric unless SA1_DRAW_UNLIT
    // the screen (round 4c E5): fov_desired-style horizontal field of view in degrees for a 4:3 view (Source widens it
    // for wider screens: Hor+) and the size in pixels; with all three > 0 prepare_view measures how much of the screen
    // the blended batches cover (Character::view_cover)
    float fov = 0.0f, width = 0.0f, height = 0.0f;
    // 0.8, camera-relative drawing (sadc docs/research/gsa1_060_render.md review R3.1 / R7.3): the vertices are written
    // as position - origin (subtracted in double before the float conversion), so the GPU's float32 vertex transform
    // works on small numbers; the addon draws them under a view whose eye is the real eye - origin. Far from the map's
    // centre (gm_bigcity, |x| or |y| above about 5000) absolute positions made Big's eye layers z-fight even standing
    // still. relative false: absolute positions (0.7)
    bool relative = false;
    float origin[3] = {0.0f, 0.0f, 0.0f};
};

// 0.9.2: what the host adds to a tick's sa1_input (sadc docs/research/gsa1_090_plan.md 6.10 tasks 4 and 8).
//   host_flags: SA1_INPUT_HOST_WATER_KNOWN | SA1_INPUT_HOST_IN_WATER (gsa1_090_water.md WTR-A): the host's own water at the
//     character's probe point, from the state after the previous tick (the addon tests util.PointContents there); 0 = the
//     game's own rule (also every tick without a TickExtra). Bits libsa1 does not define are dropped.
//   camera: the host's view (origin and a target point, host space) for sa1_input.host_cam_pos / host_cam_target, which
//     libsa1 reads from round 0.9.4 on (the SET round's camera position). Copied only when libsa1.h defines
//     SA1_INPUT_HOST_CAMERA (kHostCameraInput); otherwise recorded in the Character (host_camera_*) and nothing else.
struct TickExtra {
    uint32_t host_flags = 0;
    bool camera = false;
    float cam_pos[3] = {0.0f, 0.0f, 0.0f};
    float cam_target[3] = {0.0f, 0.0f, 0.0f};
};
#if defined(SA1_INPUT_HOST_CAMERA)
const bool kHostCameraInput = true;
#else
const bool kHostCameraInput = false;
#endif
// the sa1_input.host_flags bits this build passes on (0 with a libsa1.h before round 0.9.2)
#if defined(SA1_API_092)
const uint32_t kHostFlagsKnown = SA1_INPUT_HOST_WATER_KNOWN | SA1_INPUT_HOST_IN_WATER;
#else
const uint32_t kHostFlagsKnown = 0u;
#endif
// the game's ring count a start may give (SA1_CREATE_START_RINGS: libsa1 clamps to 0..99, so a start never gives a 1-up)
const int32_t kStartRingsMax = 99;

// 0.9.3 (round 6a, 093-gsa1-super: sadc docs/research/gsa1_rounds_plan.md 11.3 / 14.1a, gsa1_090_plan.md 7.5; libsa1 API
// 0.4 "Super Sonic"): what a create adds for Super Sonic (kind 8, SA1_CHAR_SUPER_SONIC) and for a Sonic who can turn Super
// in play. flags: SA1_CREATE_SUPER_CAPABLE (Sonic: his world is a Perfect Chaos world - level 19 act 0 - in which
// Session::order's SA1_ORDER_SUPER / SA1_ORDER_NORMAL turn him Super and back with position, facing, speed and rings kept;
// kind 8 always is one) and SA1_CREATE_WATER_FLOOR (host water is a solid floor for this character: "run on water");
// super_given: super_flags is passed (SA1_CREATE_SUPER) - SA1_SUPER_NO_DRAIN, SA1_SUPER_KEEP_AT_ZERO,
// SA1_SUPER_FAITHFUL_REVERT; the sea plane (SA1_SUPER_SEA_PLANE: the Perfect Chaos water that kills a reverted Sonic) is
// never passed: G-SA1's GRID worlds do not have it, so at 0 rings he only turns back into normal Sonic.
struct CreateExtra {
    uint32_t flags = 0;
    bool super_given = false;
    uint32_t super_flags = 0;
};
#if defined(SA1_API_SUPER)
const bool kSuperApi = true;
const uint32_t kCreateExtraFlags = SA1_CREATE_SUPER_CAPABLE | SA1_CREATE_WATER_FLOOR;
// 0.9.3a (sadc docs/research/super_general_design.md 5 / 6.2 with its Review RC1; libsa1.h "THE GENERAL FORM"): the
// General form (SA1_SUPER_GENERAL: a Sonic world on the host's stage, never level 19), SA1_SUPER_START (Super right after
// the first pair: the General entry when it is spawned, switched to or respawned, or re-created while Super), water while
// Super (SA1_SUPER_WATER_WHILE_SUPER) and SA1_SUPER_START_NORMAL (a kind 8 re-created after it had turned back)
#if defined(SA1_API_SUPER_GENERAL)
const bool kSuperGeneralApi = true;
const uint32_t kSuperGeneralFlags = SA1_SUPER_GENERAL | SA1_SUPER_START | SA1_SUPER_WATER_WHILE_SUPER |
                                    SA1_SUPER_START_NORMAL;
#else
const bool kSuperGeneralApi = false;
const uint32_t kSuperGeneralFlags = 0u;
#endif
const uint32_t kSuperHostFlags = SA1_SUPER_NO_DRAIN | SA1_SUPER_KEEP_AT_ZERO | SA1_SUPER_FAITHFUL_REVERT |
                                 kSuperGeneralFlags;
const int32_t kKindSuperSonic = SA1_CHAR_SUPER_SONIC;
#else
const bool kSuperGeneralApi = false;
const uint32_t kSuperGeneralFlags = 0u;
const bool kSuperApi = false;
const uint32_t kCreateExtraFlags = 0u;
const uint32_t kSuperHostFlags = 0u;
const int32_t kKindSuperSonic = 8;
#endif
// the Perfect Chaos stage range of the game's tone table (0x8C1C19B4: tones 1027-1038 -> bank 5 of the stage's MLT; the
// aura's whoosh 1035 / 1036, super_sonic.md 1.10). G-SA1's sound banks are Emerald Coast's, whose bank 5 holds other
// programs: tones of this range from a Super world are kept out of the mixer (not played from the wrong bank; the
// events still reach Lua) until the mixer has the Perfect Chaos stage bank (Session::set_stage_tones)
const uint32_t kStageTonesFirst = 1027u, kStageTonesLast = 1038u;
// 0.9.4a (sadc docs/research/super2_sound.md 2, 3.1 and 7.2; super2_plan.md 6.4 task 5 with its review R.14): the aura's
// whoosh - 1035 above speed 7, 1036 above 13 (B_CHAOS7's aura exec 0C91D486) - resolves from the Perfect Chaos stage's
// sound bank (stage 19: CHAOS7B.MLT bank 5) through a libsa1 stage rule in Audio's slot kRuleWhoosh; the rest of the
// stage range (the stage's ambient loop 1033, the boss tones) stays out of the mixer
const uint32_t kWhooshFirst = 1035u, kWhooshLast = 1036u;
const int32_t kStagePerfectChaos = 19;
// the character kinds Session::create takes (SA1_CHAR_* bits)
uint32_t playable_kinds();

// Screen area (pixels) of a triangle for an eye (right / up / forward unit vectors), near-clipped at 3 HU and clipped to
// a width x height screen whose half-extents are tan_h / tan_v at distance 1 (sadc build/research/lsd_lag/lsd_frame.cpp
// tri_pixels, without allocations)
double triangle_pixels(const float eye[3], const float right[3], const float up[3], const float fwd[3], double tan_h,
                       double tan_v, double width, double height, const float *a, const float *b, const float *c);

struct Character {
    sa1_character_id id = 0;
    int32_t kind = 0;
    bool puppet = false;
    // 0.9.2 (sadc docs/research/gsa1_090_faults.md F3.2 with its review R.2.5): the world died in a tick - a game code
    // fault (SA1_ERR_GAME_FAULT) or a fatal stub (SA1_ERR_NOT_IMPLEMENTED: libsa1 would enter the step again every tick and
    // fail in the same stub with the world half-stepped each time); every later tick returns SA1_ERR_GAME_FAULT
    bool faulted = false;
    sa1_status fault_status = SA1_OK;  // the status of the tick that faulted
    int32_t start_rings = -1;          // the start rings given to create() (-1: the game's 0; Super Sonic: libsa1's 50)
    // 0.9.3 (Super Sonic): the CreateExtra given to create() and the form after the last tick
    uint32_t create_extra = 0;         // CreateExtra::flags
    bool super_given = false;          // CreateExtra::super_given
    uint32_t super_flags = 0;          // CreateExtra::super_flags (with super_given)
    bool super_capable = false;        // kind 8, or Sonic with SA1_CREATE_SUPER_CAPABLE: Session::order works
    bool super = false;                // player 0 is Super after the last tick (SA1_STATE_SUPER)
    uint32_t super_changes = 0;        // form changes seen by tick() (either way)
    uint32_t super_step = 0;           // the world's step after the tick that changed the form last
    uint64_t stage_tones_muted = 0;    // Perfect Chaos stage tones kept out of the mixer (kStageTonesFirst..Last)
    // 0.9.2: what the last tick passed in sa1_input (TickExtra; tests and the session log)
    uint32_t host_flags_last = 0;
    uint64_t host_flag_ticks = 0;      // ticks that passed host flags (nonzero)
    bool host_camera_last = false;     // the last tick had a host camera (passed to libsa1 only with kHostCameraInput)
    float host_cam_last[6] = {0, 0, 0, 0, 0, 0};
    sa1_state_ex st{};
    float prev_pos[3] = {0, 0, 0};     // position at the start of the last pair (informational)
    double acc = 0.0;                  // mirror of libsa1's pair accumulator (seconds)
    float alpha = 0.0f;                // acc / (1/30)
    uint32_t pairs_last = 0;           // pairs run by the last tick
    uint64_t pairs_total = 0;
    double tick_ms_last = 0.0, tick_ms_max = 0.0;
    uint32_t num_archives = 0;
    // upgrades given to create(): their event flags, the equipment bits PInitialize must set, the check after the
    // first step (sa1_state_ex.equipment)
    std::vector<uint16_t> upgrade_flags;
    uint32_t upgrade_bits = 0;
    bool upgrades_checked = false;
    bool upgrades_ok = true;

    // the last sa1_character_render, copied (stays valid across ticks)
    bool rendered = false;
    uint32_t r_gen = 0;                // sa1_render.generation
    float r_alpha = 0.0f;
    uint32_t r_interpolated = 0;
    float r_pos[3] = {0, 0, 0};        // sa1_render.position: the drawn step's root (SA1_RENDER_DRAWN_ROOT), the camera's
    float r_yaw = 0.0f;
    // A frame libsa1 could not interpolate (no draw of the last pair matched the previous pair: an action change,
    // Knuckles' jump drawing the ball and the curled body in turn) comes from libsa1 already moved along with the
    // interpolated root (sa1_render.flags SA1_RENDER_MOVED_WITH_ROOT). G-SA1 0.4-0.5.1 moved such a frame a second time
    // (Session::follow_root): the body ran at twice the root's speed and snapped back at every pair - the 0.5.0
    // "forward and backward" flicker, also vertical (sadc docs/research/gsa1_vertical_flicker.md, cause A). 0.6.0 draws
    // what libsa1 returns and only reports it.
    uint32_t r_flags = 0;              // sa1_render.flags (0 from a libsa1 without the field)
    bool r_shifted = false;            // the last render was the last pair moved with the root by libsa1
    bool r_drawn_root = false;         // r_pos is the drawn step's root (SA1_RENDER_DRAWN_ROOT)
    uint64_t shifted_count = 0;        // renders libsa1 moved along with the root
    float sprite_max = 0.0f;           // the widest sprite of the last render (HU; the 0.4 / 0.5 sprite size bug: 256)
    uint32_t r_triangles = 0;
    std::vector<sa1_draw> r_draws;
    std::vector<float> r_tpos, r_tnrm, r_tuv;
    std::vector<uint8_t> r_tcol;
    std::vector<sa1_sprite> r_sprites;
    std::vector<sa1_line_vertex> r_lines;
    uint64_t render_count = 0;
    double render_ms = 0.0;

    // batches of the last render
    std::vector<RenderBatch> batches;  // [0, batch_count) valid
    uint32_t batch_count = 0;
    uint64_t batch_sig = 0;
    uint32_t batch_gen = 0;            // changes whenever the batch structure (states, triangle counts) changes
    uint32_t out_triangles = 0;        // sum of the batches' triangles
    bool view_ready = false;           // prepare_view() ran after the last render()
    float view_eye[3] = {0, 0, 0}, view_right[3] = {0, 1, 0}, view_up[3] = {0, 0, 1};
    ViewOptions view_opt;              // (view_opt.relative / origin: the batches' positions are relative to origin)
    uint32_t shadow_draws = 0;         // SA1_DRAW_SHADOW draws of the last render (the session log, gsa1.GetState)
    double view_ms = 0.0;
    // prepare_view() with a screen (ViewOptions fov / width / height): the screen area the blended batches cover, in
    // screens (1 = the whole screen once; additive effects drawn over each other add up), and of those the sprites
    float view_cover = 0.0f, view_cover_sprites = 0.0f;
    // 0.9.1 (translucency T1): the exact alphas each lit translucent batch state (archive, texture, flags, blend, wrap)
    // has keyed (at most kMaxLitAlphas; later ones are rounded), and how often a draw's vertex alpha was not constant
    // (its mean is used) or was rounded; the first time either happens one line goes into the session log
    std::unordered_map<uint64_t, std::vector<uint8_t>> lit_alphas;
    uint64_t lit_alpha_varied = 0, lit_alpha_rounded = 0;
    bool lit_alpha_logged = false;
    // 0.9.4 (review R.1): libsa1 draws above kMaxBatchTriangles that build_batches split into pieces (each a draw of
    // r_draws then), in the last render and in all
    uint32_t split_draws = 0;
    uint64_t split_draws_total = 0;
};

struct TextureRuns {
    uint32_t width = 0, height = 0;
    uint32_t pixel_format = 0, data_format = 0;
    uint32_t alpha = 0;                // SA1_TEXTURE_ALPHA_*
    std::string name;
    // run-length rows: per run u16 x, u16 y, u16 length, u8 r, g, b, a (10 bytes, little-endian);
    // fully transparent black pixels (0,0,0,0) are left out (the render target is cleared to that)
    std::string runs;
    uint32_t run_count = 0;
    bool has_canary = false;           // a pixel with alpha 255 for the device-reset check
    uint32_t canary_x = 0, canary_y = 0;
    uint8_t canary[4] = {0, 0, 0, 0};
};

// Decodes TextureRuns::runs into an RGBA8 image cleared to (0,0,0,0): what the addon paints into its render
// target. Returns false if a run lies outside the image.
bool paint_runs(const TextureRuns &t, std::vector<uint8_t> &rgba);

enum class DiscState : int { Idle = 0, Loading, Ready, Failed };
const char *disc_state_name(DiscState s);

class Session {
public:
    Session();
    ~Session();
    Session(const Session &) = delete;
    Session &operator=(const Session &) = delete;

    // sa1_init + sa1_load_disc of the playable characters (SA1_LOAD_WORLD_IMAGES) on a worker thread; the disc path
    // comes from the module-owned config (or the test's command line), never from Lua. Returns false only when it
    // cannot start; a load already running or done is left alone (true). poll_init() (game thread, every frame)
    // installs the context: 1 = loaded just now, -1 = failed just now (init_error()), 0 = nothing new.
    bool init_async(const std::string &gdi_path, std::string &err);
    int poll_init();
    DiscState disc_state() const { return disc_state_; }
    const std::string &init_error() const { return init_error_; }
    double disc_wait_ms() const;           // how long the running load has taken so far
    // the same, waiting for the worker (tests and tools)
    bool init(const std::string &gdi_path, std::string &err);
    void shutdown();
    bool ready() const { return ctx_ != nullptr && disc_loaded_; }
    sa1_context *ctx() { return ctx_; }
    double disc_load_ms() const { return disc_ms_; }

    // static collision (Hammer units). Characters created afterwards collide with it; existing ones keep the
    // geometry their world was built with (recreate them). set_world: the triangles (libsa1 synthesizes them in the
    // first world created afterwards, on the creating thread); set_world_prepared: geometry the map job prepared on
    // its worker (sa1_collision_set_prepared, O(1)), kept here for the session (world_prepared()) and shared by
    // reference with every world created while it is the context's geometry.
    bool set_world(const std::vector<sa1_collision_tri> &tris, std::string &err);
    bool set_world_prepared(const PreparedRef &p, std::string &err);
    const PreparedRef &world_prepared() const { return world_prep_; }
    bool world_info(sa1_collision_info &out) const;
    double world_set_ms() const { return world_ms_; }
    // moving collision (brush entities, physics props): the shapes and the libsa1 objects near the character
    Movers &movers() { return movers_; }
    // Movers::commit around the first ticking character (none: everything parked); the module calls it each frame
    void commit_movers(double now);

    // upgrades: the character's upgrades to give it (UpgradeDef of this kind; none = the game's start)
    // start_rings (0.9.2, sadc docs/research/gsa1_090_rings.md F7 with its review R4.11): 0..99 = the ring count the world
    // starts with (SA1_CREATE_START_RINGS: the game's own 8C08A074 then 8C08A198(n) before the first step); -1 = the game's
    // 0; values above 99 are clamped to 99 (libsa1's rule: a start never gives a 1-up)
    // extra (0.9.3): Super Sonic's world (CreateExtra); nullptr = none. Kind 8 without start_rings starts with libsa1's 50.
    int32_t create(int32_t kind, const float pos[3], float yaw, std::string &err, double *ms = nullptr,
                   const std::vector<const UpgradeDef *> *upgrades = nullptr, int32_t start_rings = -1,
                   const CreateExtra *extra = nullptr);
    // 0.9.3: the game's player request in the character's world now (sa1_character_order: SA1_ORDER_SUPER 46 /
    // SA1_ORDER_NORMAL 47); SA1_ERR_UNSUPPORTED for a world that cannot turn Super (last_error() says why)
    sa1_status order(int32_t id, int32_t order);
    // 0.9.3a (the Super Sonic page's voice Preview, design 6.9): plays the game's tone `tone` (1..2047) once through the
    // mixer as the character's own sound (id 0: no character, heard as a local sound), as the game's sound call would
    // (an SA1_EVENT_SOUND; tone 1116 resolves to Sonic's voice bank 6). false: no mixer (the sound banks are not open) or a
    // bad tone
    bool preview_sound(int32_t id, uint32_t tone);
    // 0.9.3b (owner: none of the four grunts was his "HM!"; it is one of Super Sonic's own lines, voice 396): plays voice
    // clip `voice` (an entry of the voice archive, as the game's PlayVoice 8C107BA0 would: an SA1_EVENT_VOICE) once through
    // the mixer, as the character's own voice when id is given. false: no mixer or a voice past the archive's 4096 limit
    bool preview_voice(int32_t id, uint32_t voice);
    // Sonic's Super forms are loaded (SA1_LOAD_SUPER_FORMS: his SUPERSONIC archive), so a Sonic can be created
    // SA1_CREATE_SUPER_CAPABLE
    bool super_forms() const { return super_forms_; }
    // false: tones of the Perfect Chaos stage range from Super worlds go to the mixer (it has that stage's bank);
    // true (the default): they are kept out of it (0.9.4a: except the whoosh while it is routed, below)
    void set_stage_tones(bool mute) { mute_stage_tones_ = mute; }
    // true while the stage range is kept out and the whoosh is not routed (the option off, or a libsa1 without stage rules)
    bool stage_tones_muted() const { return mute_stage_tones_ && !(whoosh_ && audio_.has_stage_rules()); }
    uint64_t stage_tones_dropped() const { return stage_tones_dropped_; }
    // 0.9.4a (super2_plan.md 6.4 task 5; gsa1.SuperWhoosh): the aura's whoosh. On (the default): every super-capable
    // character (kind 8; a Sonic created SUPER_CAPABLE: the General entry and the transformation) holds the stage rule
    // {kStagePerfectChaos, kWhooshFirst, kWhooshLast} in Audio's slot kRuleWhoosh - set at its creation and here - and
    // its 1035 / 1036 pass the stage-tone guard while that rule holds (review R.14: recorded for it and not refused by
    // libsa1); off: the rules cleared, the whoosh still playing stopped, the tones kept out as in 0.9.4. false: this
    // libsa1 has no stage rules (only the flag changes)
    bool set_super_whoosh(bool on);
    bool super_whoosh() const { return whoosh_; }
    // the character's whoosh tones go to the mixer now
    bool whoosh_routed(int32_t id) const;
    // super-capable characters whose whoosh is routed
    uint32_t whoosh_characters() const;
    // the stage-tone guard of take_events (0.9.3; 0.9.4a: the whoosh exception): false = the event is kept out of the
    // mixer (counted in Character::stage_tones_muted and stage_tones_dropped()); every other event: true
    bool admit_sound(const sa1_event &e);
    int32_t create_puppet(int32_t kind, std::string &err);
    // 0.9.2a (sadc docs/research/gsa1_091b_itembox.md E2 with its review R.4.1): destroying a character also drops its
    // events still queued for poll_events (a removed or restarted character's fault, death or sounds never reach the next
    // character); stale_events_dropped() counts them
    bool destroy(int32_t id);
    void destroy_all();
    uint64_t stale_events_dropped() const { return stale_events_dropped_; }
    Character *get(int32_t id);
    std::vector<int32_t> ids() const;

    // Runs whole 1/30 s pairs from libsa1's accumulator (dt clamped to [0, 0.25]); refreshes the state and takes
    // the events (sound events go to the audio mixer). Returns the libsa1 status (SA1_OK, or an error: see
    // last_error()). raw_stick: pass the stick unchanged (the DC pad's own behaviour) instead of exact_stick().
    // extra (0.9.2): the host flags and the host camera of this tick (TickExtra); nullptr = none.
    // A tick that fails with SA1_ERR_GAME_FAULT or SA1_ERR_NOT_IMPLEMENTED (a fatal stub) marks the character faulted
    // (Character::faulted): it returns that status once, then SA1_ERR_GAME_FAULT for every later tick.
    sa1_status tick(int32_t id, float stick_x, float stick_y, float camera_yaw, uint32_t buttons, float dt,
                    bool raw_stick = false, const TickExtra *extra = nullptr);
    // Puppet path (remote characters later): poses `action` at `frame`.
    sa1_status pose(int32_t id, int32_t action, float frame, const float pos[3], float yaw);

    // sa1_character_render(alpha) (alpha < 0: libsa1's accumulator, 1: the last pair as it is) -> batches.
    sa1_status render(int32_t id, float alpha);
    // Vertices of every batch for this camera (eye position, the view's right and up vectors, host space).
    void prepare_view(Character &c, const float eye[3], const float right[3], const float up[3],
                      const ViewOptions &opt);
    // the batches of c's draws again (render() does this; tests that fill Character::r_* themselves)
    void rebatch(Character &c) { build_batches(c); }

    bool texture_count(int32_t kind, uint32_t archive, uint32_t &count, std::string &err, std::string *name = nullptr);
    uint32_t texture_archives(int32_t kind);
    // variant (0.9.4a, review R.6): 0 = the texture (sa1_texture_get); > 0 = libsa1's variant of it
    // (sa1_texture_variant_get: SA1_TEXTURE_VARIANT_SUPER_GOLD 1 for SON_EFF lcharge01-04 of Sonic loaded with his Super
    // forms); the canary comes from the texels returned
    bool texture_runs(int32_t kind, uint32_t archive, uint32_t index, TextureRuns &out, std::string &err,
                      uint32_t variant = 0);
    bool texture_pixel(int32_t kind, uint32_t archive, uint32_t index, uint32_t x, uint32_t y, uint8_t out[4]);

    // events of every character since the last call (sound events have already gone to the audio mixer)
    void poll_events(std::vector<sa1_event> &out);
    std::vector<std::string> take_log();
    std::string last_error() const;

    // audio: the libsa1 mixer on the disc this session loaded (the output device is the module's business).
    // audio_open_async starts opening the sound banks on a worker (Audio: a private libsa1 context); poll_audio()
    // (game thread, every frame) installs them: 1 = opened just now, -1 = failed just now (msg), 0 = nothing new.
    // audio_open: the same, waiting (tests). audio_close never waits (the objects close on a worker).
    bool audio_open_async(bool japanese, std::string &err);
    int poll_audio(std::string &msg);
    bool audio_open(bool japanese, std::string &err);
    void audio_close();
    Audio &audio() { return audio_; }

    // Messages handed to Lua never contain the disc's or the config's directory.
    std::string scrub(const std::string &msg) const;
    void log_line(int32_t level, const char *msg);   // any thread

    // true when every texel of the texture has RGB (0, 0, 0) (cached per texture; the blob shadow's mask path, WRAP_MASK)
    bool texture_black(int32_t kind, int32_t archive, int32_t index);

private:
    void refresh_state(Character &c);
    void take_events();
    void build_batches(Character &c);
    bool set_event_flags(sa1_character_id id, const std::vector<uint16_t> &flags, std::string &err);

    struct InitResult {
        sa1_context *ctx = nullptr;     // loaded (owned by the result until poll_init installs it)
        sa1_status status = SA1_OK;
        std::string error;
        double ms = 0.0;
    };
    void finish_init_worker();          // joins a load and frees a context nobody installed

    sa1_context *ctx_ = nullptr;
    bool disc_loaded_ = false;
    DiscState disc_state_ = DiscState::Idle;
    std::string init_error_;
    std::unique_ptr<Worker> init_worker_;
    std::shared_ptr<InitResult> init_result_;
    double init_t0_ = 0.0;
    std::string gdi_path_;
    std::string disc_dir_;
    std::string config_dir_;
    double disc_ms_ = 0.0, world_ms_ = 0.0;
    PreparedRef world_prep_;
    std::vector<std::unique_ptr<Character>> chars_;
    mutable std::mutex log_m_;
    std::deque<std::string> log_;
    std::deque<sa1_event> events_;
    std::string last_error_;
    Audio audio_;
    Movers movers_;
    std::unordered_map<uint64_t, bool> black_;   // texture_black's answers (cleared with the context)
    // 0.9.3 (Super Sonic)
    bool super_forms_ = false;
    bool mute_stage_tones_ = true;
    uint64_t stage_tones_dropped_ = 0;
    bool whoosh_ = true;                  // 0.9.4a: set_super_whoosh
    void whoosh_rule(const Character &c); // 0.9.4a: the character's rule as whoosh_ says (a super-capable one)
    uint64_t stale_events_dropped_ = 0;   // 0.9.2a, E2
};

}  // namespace gsa1
