// G-SA1: the Garry's Mod client module (gmcl_gsa1_win64.dll / gmcl_gsa1_linux64.dll), require("gsa1").
//
// A thin Lua binding over the core (src/core): every function runs on the Lua main thread, validates its
// arguments without raising Lua errors (no ThrowError / ArgError / Check*: a Lua error would longjmp or unwind
// through C++ frames), and reports failures as return values: `nil, message` (or `false, message`).
// 0.5.1 (API 6): nothing slow runs in a call any more - the disc (Init / InitPoll), the sound banks (AudioOpen /
// AudioPoll) and the map's collision with libsa1's GRID synthesis (MapStart ... MapApply) load on worker threads, a
// replaced or cancelled map job is dropped without waiting for its worker, and MapApply installs prepared geometry
// in O(1) (tests/binding_test.cpp "game thread" measures every call of a spawn, respawn, switch and map reload).
// 0.6.0 (API 6, round 4c; nothing breaking): Render draws exactly what libsa1 renders (libsa1 moves unmatched draws with
// the root and roots the frame at the drawn step itself: the 0.5.0 vertical flicker); PrepareView takes the lighting
// setting (EmitBatch leaves out mesh.Normal / mesh.TexCoord where the material ignores them) and the screen (the blended
// batches' coverage for the session log); GetState / Status report more; PollEvents reuses the caller's table.
// Features (gsa1_feature.hpp; plan G0): later parts (interaction, Super Sonic, followers, jukebox) add their own
// functions from src/module/bind_<feature>.cpp without editing this file; gsa1.FEATURES lists them by version, the base
// API_VERSION changes only for a breaking change of the functions below. The helpers the bindings share are declared in
// gsa1_module_internal.hpp (namespace gsa1::mod).
// Security rules (sadc docs/research/critique.md 5.2), because any server's clientside Lua can call these:
//   * no function takes a filesystem path: the disc path comes from the module-owned config file (outside the
//     game directory), maps are looked up by a validated bare name below the module's own garrysmod directory;
//   * messages never contain the disc's or the config's directory (Session::scrub);
//   * caller tables are written with rawset (no metamethods run); every number is checked for finiteness.
// Units: Hammer units and degrees in Lua; the core uses radians.
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/audio.hpp"
#include "../core/bsp.hpp"
#include "../core/config.hpp"
#include "../core/mapjob.hpp"
#include "../core/pad.hpp"
#include "../core/paths.hpp"
#include "../core/session.hpp"
#include "../core/shape.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <commdlg.h>
#endif

// the surfaces feature (bind_surfaces.cpp; sadc docs/research/gsa1_060_dig.md F3 / F6, Review G10): its class table for
// the map job, the applied map's surface types, the physics props' shapes with their surface kinds
namespace gsa1 {
namespace mod {
void surfaces_map_options(gsa1::MapJobOptions &o);
void surfaces_map_applied(const gsa1::MapResult &r);
bool surfaces_shape_phy(const gsa1::PhyModel &m, gsa1::Shape &out, std::string &err, float thin_wall_max);
}  // namespace mod
}  // namespace gsa1

static_assert(offsetof(lua_State, luabase) == (sizeof(void *) == 8 ? 120 : 72),
              "gmod-module-base picked the wrong lua_State layout for this target");

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;

#define GSA1_MODULE_VERSION "0.9.4d"
#define GSA1_API_VERSION 6

namespace {

const double kPi = 3.14159265358979323846;
gsa1::Session *g_session = nullptr;
std::string g_gmod_dir;
std::string g_world_map;
gsa1::BspWorldStats g_world;
bool g_world_ok = false;
// the map's collision as the addon loads it (gsa1.MapStart ... MapApply: mapjob.hpp)
gsa1::MapJob *g_job = nullptr;
// jobs that were replaced or cancelled while a worker ran: deleted once it has finished (reap_jobs), never waited for
std::vector<gsa1::MapJob *> g_retired_jobs;
// the applied map's preparation (prepare.hpp) and thin-wall threshold (also used for the props' shapes)
gsa1::PrepareResult g_prep_info;     // its numbers (the geometry itself is in the session)
bool g_world_prepared = false;
std::string g_prep_note;             // why the world was not prepared ahead ("" = it was)
std::string g_world_refused;         // 0.9.2a: the applied map's collision is too big for the game (prep.too_big): why, in
                                     // plain words; gsa1.Create refuses at once instead of re-running the GRID synthesis
float g_thin_wall = 16.0f;           // BspWorldOptions::thin_wall_max of the applied map (Hammer units, 0 = off)
gsa1::MapStats g_map;               // of the applied map (static props, brush models; g_world = g_map.world)
bool g_map_from_cache = false, g_map_cache_written = false, g_map_full = false;
double g_map_cache_ms = 0.0, g_map_apply_ms = 0.0;
std::string g_map_cache_note, g_map_props_note;
gsa1::AudioOut *g_out = nullptr;
gsa1::Controller *g_pad = nullptr;   // XInput controller (src/core/pad.hpp)
double g_out_retry = -1e9;
std::vector<int16_t> g_pcm;
// mesh emission: the mesh library's Vector arguments (see EmitBatch)
int g_vec_mode = -1;            // -1 unknown, 0 a new Vector per call, 1 two scratch Vectors written in place
int g_vec_ref[2] = {-1, -1};
uint64_t g_emit_calls = 0, g_emit_errors = 0;
uint64_t g_emit_saved = 0;      // mesh.Normal / mesh.TexCoord calls left out because the material ignores them (E1)
#ifdef _WIN32
double g_last_dialog = -1e9;
#endif

}  // namespace

// ---- helpers shared with the feature bindings (gsa1_module_internal.hpp, gsa1_feature.hpp) ----------------------------
namespace gsa1 {
namespace mod {

gsa1::Session *session() { return g_session; }
gsa1::AudioOut *audio_out() { return g_out; }
const std::string &gmod_dir() { return g_gmod_dir; }

float deg2rad(double d) { return (float)(d * kPi / 180.0); }
double now_s() { return gsa1::now_ms() / 1000.0; }
double rad2deg(double r) { return r * 180.0 / kPi; }

int absidx(ILuaBase *L, int i) { return i < 0 ? L->Top() + i + 1 : i; }

bool arg_number(ILuaBase *L, int i, double &out)
{
    if (!L->IsType(i, LT::Number)) {
        return false;
    }
    out = L->GetNumber(i);
    return std::isfinite(out);
}

bool arg_int(ILuaBase *L, int i, int32_t &out, double lo, double hi)
{
    double d;
    if (!arg_number(L, i, d) || d < lo || d > hi || d != std::floor(d)) {
        return false;
    }
    out = (int32_t)d;
    return true;
}

bool arg_string(ILuaBase *L, int i, std::string &out, size_t max)
{
    if (!L->IsType(i, LT::String)) {
        return false;
    }
    unsigned int len = 0;
    const char *s = L->GetString(i, &len);
    if (!s || len > max) {
        return false;
    }
    out.assign(s, len);
    return true;
}

bool arg_vector(ILuaBase *L, int i, float out[3])
{
    if (!L->IsType(i, LT::Vector)) {
        return false;
    }
    const Vector &v = L->GetVector(i);
    out[0] = v.x;
    out[1] = v.y;
    out[2] = v.z;
    return std::isfinite(out[0]) && std::isfinite(out[1]) && std::isfinite(out[2]);
}

int push_nil_msg(ILuaBase *L, const std::string &msg, const char *code)
{
    L->PushNil();
    L->PushString(msg.c_str(), (unsigned int)msg.size());
    if (code) {
        L->PushString(code);
        return 3;
    }
    return 2;
}

int push_false_msg(ILuaBase *L, const std::string &msg, const char *code)
{
    L->PushBool(false);
    L->PushString(msg.c_str(), (unsigned int)msg.size());
    if (code) {
        L->PushString(code);
        return 3;
    }
    return 2;
}

// raw table writes (t: absolute index of a table)
void raw_num(ILuaBase *L, int t, const char *k, double v)
{
    L->PushString(k);
    L->PushNumber(v);
    L->RawSet(t);
}

void raw_bool(ILuaBase *L, int t, const char *k, bool v)
{
    L->PushString(k);
    L->PushBool(v);
    L->RawSet(t);
}

void raw_str(ILuaBase *L, int t, const char *k, const std::string &v)
{
    L->PushString(k);
    L->PushString(v.c_str(), (unsigned int)v.size());
    L->RawSet(t);
}

// t[k] (rawget) when it is a finite number / a boolean
bool raw_get_number(ILuaBase *L, int t, const char *k, double &out)
{
    L->PushString(k);
    L->RawGet(t);
    bool ok = L->IsType(-1, LT::Number) && std::isfinite(L->GetNumber(-1));
    if (ok) {
        out = L->GetNumber(-1);
    }
    L->Pop();
    return ok;
}

bool raw_get_bool(ILuaBase *L, int t, const char *k, bool &out)
{
    L->PushString(k);
    L->RawGet(t);
    bool ok = L->IsType(-1, LT::Bool);
    if (ok) {
        out = L->GetBool(-1);
    }
    L->Pop();
    return ok;
}

// pushes t[i] if it is a table, else a new table stored at t[i]; returns its absolute index
int raw_subtable_i(ILuaBase *L, int t, int i)
{
    L->PushNumber(i);
    L->RawGet(t);
    if (!L->IsType(-1, LT::Table)) {
        L->Pop();
        L->CreateTable();
        L->PushNumber(i);
        L->Push(-2);
        L->RawSet(t);
    }
    return L->Top();
}

// the caller's table at index i (or a new one), left on the top of the stack; returns its absolute index
int out_table(ILuaBase *L, int i)
{
    if (L->IsType(i, LT::Table)) {
        L->Push(i);
    } else {
        L->CreateTable();
    }
    return L->Top();
}

bool ready_or(ILuaBase *L, int &ret)
{
    if (!g_session || !g_session->ready()) {
        ret = push_nil_msg(L, "G-SA1 is not initialised: run gsa1.Init() first (it loads your disc)", "not_ready");
        return false;
    }
    return true;
}

}  // namespace mod
}  // namespace gsa1
using namespace gsa1::mod;

namespace {

int world_info_table(ILuaBase *L)
{
    L->CreateTable();
    int t = L->Top();
    raw_str(L, t, "map", g_world_map);
    raw_num(L, t, "triangles", g_world.tris);
    raw_num(L, t, "brushes", g_world.world_brushes);
    raw_num(L, t, "solid_brushes", g_world.solid_brushes);
    raw_num(L, t, "water_brushes", g_world.water_brushes);
    raw_num(L, t, "displacements", g_world.displacements);
    raw_num(L, t, "displacement_triangles", g_world.displacement_tris);
    raw_num(L, t, "water_triangles", g_world.tris_water);
    raw_num(L, t, "hidden_faces", g_world.hidden_faces);
    raw_num(L, t, "thickened_floors", g_world.thickened_floors);
    raw_num(L, t, "stairs", g_world.stairs);
    raw_num(L, t, "parse_ms", g_world.ms);
    raw_num(L, t, "set_ms", g_session ? g_session->world_set_ms() : 0.0);
    raw_num(L, t, "min_z", g_world.mins[2]);
    raw_num(L, t, "max_z", g_world.maxs[2]);
    raw_num(L, t, "one_way_solids", g_world.one_way_solids);
    raw_num(L, t, "one_way_faces", g_world.one_way_faces + g_world.one_way_cross);
    raw_num(L, t, "one_way_disp_tris", g_world.one_way_disp_tris);
    raw_num(L, t, "disp_back_faces", g_world.disp_back_faces);
    raw_num(L, t, "disp_tag_checked", g_world.disp_tag_checked);
    raw_num(L, t, "disp_tag_reversed", g_world.disp_tag_reversed);
    raw_bool(L, t, "full", g_map_full);          // through MapStart: static props and brush models included
    raw_num(L, t, "props", g_map.props);
    raw_num(L, t, "props_solid", g_map.props_solid);
    raw_num(L, t, "props_placed", g_map.props_placed);
    raw_num(L, t, "prop_hulls", g_map.props_hulls);
    raw_num(L, t, "props_missing", g_map.props_missing);
    raw_num(L, t, "props_small", g_map.props_small);
    raw_num(L, t, "prop_triangles", g_world.tris_extra);
    raw_num(L, t, "prop_models", g_map.prop_models);
    raw_num(L, t, "prop_models_missing", g_map.prop_models_missing + g_map.prop_models_bad);
    raw_str(L, t, "props_note", g_map_props_note);
    raw_num(L, t, "brush_models", g_map.brush_models);
    raw_num(L, t, "brush_model_triangles", g_map.brush_model_tris);
    raw_num(L, t, "brush_entities", g_map.brush_entities);
    raw_bool(L, t, "from_cache", g_map_from_cache);
    raw_bool(L, t, "cache_written", g_map_cache_written);
    raw_num(L, t, "cache_ms", g_map_cache_ms);
    raw_str(L, t, "cache_note", g_map_cache_note);
    raw_num(L, t, "build_ms", g_map.total_ms);
    raw_num(L, t, "apply_ms", g_map_apply_ms);
    raw_num(L, t, "bytes_fed", (double)g_map.bytes_fed);
    // 0.5.1: libsa1's GRID synthesis, done by the map job's worker (prepare.hpp)
    raw_bool(L, t, "prepared", g_world_prepared);
    raw_num(L, t, "prepare_ms", g_world_prepared ? g_prep_info.ms : 0.0);
    raw_num(L, t, "grid_triangles", g_prep_info.grid_triangles);
    raw_num(L, t, "grid_objects", g_prep_info.grid_objects);
    raw_num(L, t, "grid_undersides", g_prep_info.grid_undersides);
    raw_str(L, t, "prepare_note", g_prep_note);
    raw_num(L, t, "thin_walls", g_world.thin_walls);
    raw_num(L, t, "thin_wall_max", g_thin_wall);
    // 0.9.2a (the 0.9.2 verifier's leftover, gsa1_090_plan.md 6.6 task 2): 0.9.2's collision guard, thin stacks and the
    // preparation's fallback, for the map line and the session log
    raw_num(L, t, "thin_wall_kept", g_world.thin_wall_kept);
    raw_num(L, t, "thin_stacks", g_world.thin_stacks);
    raw_num(L, t, "tris_outside", g_world.tris_outside);
    raw_num(L, t, "frags_outside", g_world.frags_outside);
    raw_num(L, t, "displacements_nohull", g_world.displacements_nohull);
    raw_num(L, t, "props_outside", g_map.props_outside);
    raw_bool(L, t, "prepare_retried", g_prep_info.retried);
    raw_num(L, t, "prepare_left_out", g_prep_info.left_out);
    raw_bool(L, t, "too_big", !g_world_refused.empty());
    raw_str(L, t, "too_big_note", g_world_refused);
    return 1;
}

std::string cache_dir();   // below (the map job's bindings)
void drop_job();

int load_world_from(ILuaBase *L, gsa1::ByteSource &src, const std::string &name)
{
    std::string err;
    gsa1::Bsp bsp;
    if (!bsp.open(src, err)) {
        return push_false_msg(L, "map " + name + ": " + err, "bad_map");
    }
    std::vector<sa1_collision_tri> tris;
    gsa1::BspWorldStats st;
    gsa1::BspWorldOptions opt;
    if (!bsp.build_world(opt, tris, st, err)) {
        return push_false_msg(L, "map " + name + ": " + err, "bad_map");
    }
    if (!g_session->set_world(tris, err)) {
        return push_false_msg(L, err, "error");
    }
    g_world = st;
    g_world_map = name;
    g_world_ok = true;
    g_map = gsa1::MapStats();
    g_map.world = st;
    g_map_full = g_map_from_cache = g_map_cache_written = false;
    g_map_cache_note.clear();
    g_map_props_note.clear();
    g_world_prepared = false;
    g_prep_info = gsa1::PrepareResult();
    g_prep_note = "WorldLoad: synthesized by the first character";
    g_world_refused.clear();
    L->PushBool(true);
    world_info_table(L);
    return 2;
}

}  // namespace

// GSA1_FN (gsa1_module_internal.hpp) wraps a binding: no C++ exception may reach Lua.

// gsa1.Init() -> true, "loading" | true, "already initialised" | false, message, code ("no_config" | "disc")
// 0.5.1: starts loading the disc on a worker thread (the playable characters and their world images: 0.1-0.3 s, off
// the game's thread) and returns at once; gsa1.InitPoll() installs it when it is done. The disc path comes from the
// module's own config file, never from Lua.
GSA1_FN(gsa1_lua_Init)
{
    if (!g_session) {
        return push_false_msg(LUA, "the module failed to start");
    }
    if (g_session->ready()) {
        LUA->PushBool(true);
        LUA->PushString("already initialised");
        return 2;
    }
    if (g_session->disc_state() == gsa1::DiscState::Loading) {
        LUA->PushBool(true);
        LUA->PushString("loading");
        return 2;
    }
    gsa1::Config cfg;
    std::string err;
    if (!gsa1::load_config(cfg, err)) {
        return push_false_msg(LUA, err, "no_config");
    }
    if (!g_session->init_async(cfg.disc, err)) {
        return push_false_msg(LUA, scrubbed(err), "disc");
    }
    LUA->PushBool(true);
    LUA->PushString("loading");
    return 2;
}

// gsa1.InitPoll() -> state, message, ms, changed
// state: "idle" (gsa1.Init not called) | "loading" | "ready" | "failed"; ms: the load's time (ready) or how long it has
// taken so far; changed: true in the call that saw it finish. Call it once per frame while the disc loads: a finished
// load is installed by this call, on this thread (cheap: the worker did the work).
GSA1_FN(gsa1_lua_InitPoll)
{
    if (!g_session) {
        LUA->PushString("failed");
        LUA->PushString("the module failed to start");
        LUA->PushNumber(0);
        LUA->PushBool(false);
        return 4;
    }
    int r = g_session->poll_init();
    gsa1::DiscState s = g_session->disc_state();
    std::string msg;
    double ms = 0.0;
    switch (s) {
    case gsa1::DiscState::Idle: msg = "not loaded (gsa1.Init starts it)"; break;
    case gsa1::DiscState::Loading:
        ms = g_session->disc_wait_ms();
        msg = "loading your disc on a worker thread";
        break;
    case gsa1::DiscState::Ready:
        ms = g_session->disc_load_ms();
        msg = gsa1::format("disc loaded in %.0f ms on a worker thread", ms);
        break;
    case gsa1::DiscState::Failed: msg = g_session->init_error(); break;
    }
    LUA->PushString(gsa1::disc_state_name(s));
    LUA->PushString(msg.c_str(), (unsigned int)msg.size());
    LUA->PushNumber(ms);
    LUA->PushBool(r != 0);
    return 4;
}

// gsa1.Shutdown()
GSA1_FN(gsa1_lua_Shutdown)
{
    gsa1::shutdown_features();   // features (gsa1_feature.hpp) let go of their characters first
    drop_job();
    if (g_out) {
        g_out->stop();
    }
    if (g_pad) {
        g_pad->stop();
    }
    if (g_session) {
        g_session->shutdown();
    }
    g_world_ok = false;
    g_world_map.clear();
    g_world_prepared = false;
    return 0;
}

// gsa1.IsReady() -> bool
GSA1_FN(gsa1_lua_IsReady)
{
    LUA->PushBool(g_session && g_session->ready());
    return 1;
}

// gsa1.Status() -> table
GSA1_FN(gsa1_lua_Status)
{
    LUA->CreateTable();
    int t = LUA->Top();
    raw_bool(LUA, t, "ready", g_session && g_session->ready());
    raw_str(LUA, t, "disc_state", g_session ? gsa1::disc_state_name(g_session->disc_state()) : "failed");
    raw_str(LUA, t, "disc_error", g_session ? g_session->init_error() : std::string("the module failed to start"));
    raw_num(LUA, t, "disc_wait_ms", g_session ? g_session->disc_wait_ms() : 0.0);
    raw_str(LUA, t, "version", GSA1_MODULE_VERSION);
    raw_num(LUA, t, "api", GSA1_API_VERSION);
    raw_str(LUA, t, "libsa1", sa1_version_string());
    raw_str(LUA, t, "config", gsa1::config_file_display());
    raw_bool(LUA, t, "garrysmod_dir", !g_gmod_dir.empty());
    raw_num(LUA, t, "disc_ms", g_session ? g_session->disc_load_ms() : 0.0);
    raw_bool(LUA, t, "world", g_world_ok);
    raw_str(LUA, t, "world_map", g_world_map);
    raw_num(LUA, t, "world_triangles", g_world_ok ? g_world.tris : 0);
    raw_bool(LUA, t, "world_full", g_world_ok && g_map_full);
    raw_bool(LUA, t, "world_prepared", g_world_ok && g_world_prepared);
    raw_num(LUA, t, "retired_jobs", (double)g_retired_jobs.size());
    raw_str(LUA, t, "map_state", g_job ? gsa1::map_state_name(g_job->state()) : "idle");
    raw_str(LUA, t, "map_loading", g_job ? g_job->map() : std::string());
    raw_num(LUA, t, "map_progress", g_job ? g_job->progress() : 0.0);
    raw_bool(LUA, t, "cache_dir", !cache_dir().empty());
    raw_num(LUA, t, "characters", g_session ? (double)g_session->ids().size() : 0.0);
    raw_bool(LUA, t, "audio", g_session && g_session->audio().is_open());
    raw_bool(LUA, t, "audio_opening", g_session && g_session->audio().opening());
    raw_bool(LUA, t, "audio_output", g_out && g_out->running());
    raw_str(LUA, t, "audio_backend", g_out ? g_out->name() : std::string("none"));
    raw_str(LUA, t, "audio_error", g_out ? g_out->last_error() : std::string());
    raw_num(LUA, t, "vector_mode", g_vec_mode);
    raw_num(LUA, t, "mesh_calls", (double)g_emit_calls);
    raw_num(LUA, t, "mesh_errors", (double)g_emit_errors);
    raw_num(LUA, t, "mesh_saved", (double)g_emit_saved);
    // the build (session log header): build.py passes -DGSA1_BUILD_INFO="<date> libsa1 <sha1 prefix>"
#ifdef GSA1_BUILD_INFO
    raw_str(LUA, t, "build", GSA1_BUILD_INFO);
#else
    raw_str(LUA, t, "build", "unknown");
#endif
    return 1;
}

// gsa1.ChooseDisc() -> true, message | false, message   (Windows: native file dialog; writes the config)
GSA1_FN(gsa1_lua_ChooseDisc)
{
#ifdef _WIN32
    double now = gsa1::now_ms();
    if (now - g_last_dialog < 3000.0) {
        return push_false_msg(LUA, "the disc dialog was opened a moment ago");
    }
    g_last_dialog = now;
    std::vector<wchar_t> buf(4096, L'\0');
    OPENFILENAMEW ofn;
    std::memset(&ofn, 0, sizeof ofn);
    ofn.lStructSize = sizeof ofn;
    ofn.hwndOwner = GetActiveWindow();
    ofn.lpstrFilter = L"GD-ROM dump (*.gdi)\0*.gdi\0\0";
    ofn.lpstrFile = buf.data();
    ofn.nMaxFile = (DWORD)buf.size();
    ofn.lpstrTitle = L"G-SA1: choose your Sonic Adventure (US, v1.005) .gdi";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_HIDEREADONLY | OFN_DONTADDTORECENT;
    BOOL ok = GetOpenFileNameW(&ofn);
    g_last_dialog = gsa1::now_ms();
    if (!ok) {
        return push_false_msg(LUA, "no file chosen");
    }
    gsa1::Config cfg;
    cfg.disc = gsa1::narrow(std::wstring(buf.data()));
    std::string err;
    if (!gsa1::validate_disc_path(cfg.disc, err)) {
        return push_false_msg(LUA, err);
    }
    if (!gsa1::save_config(cfg, err)) {
        return push_false_msg(LUA, err);
    }
    std::string msg = std::string("saved to ") + gsa1::config_file_display();
    LUA->PushBool(true);
    LUA->PushString(msg.c_str());
    return 2;
#else
    return push_false_msg(LUA, std::string("no file dialog on this platform: edit ") + gsa1::config_file_display());
#endif
}

// gsa1.Characters() -> { {kind=, name=, loaded=, playable=}, ... }
GSA1_FN(gsa1_lua_Characters)
{
    LUA->CreateTable();
    int t = LUA->Top();
    int n = 0;
    for (int32_t k = 0; k < SA1_CHAR_COUNT; k++) {
        bool playable = ((gsa1::playable_kinds() >> k) & 1u) != 0;     // 0.9.3: Super Sonic too (session.cpp)
        sa1_character_info info;
        std::memset(&info, 0, sizeof info);
        info.struct_size = sizeof info;
        bool loaded = g_session && g_session->ready() &&
                      sa1_character_info_get(g_session->ctx(), k, &info) == SA1_OK && info.loaded;
        LUA->PushNumber(++n);
        LUA->CreateTable();
        int e = LUA->Top();
        raw_num(LUA, e, "kind", k);
        raw_str(LUA, e, "name", sa1_character_name(k));
        raw_bool(LUA, e, "loaded", loaded);
        raw_bool(LUA, e, "playable", playable);
        LUA->RawSet(t);
    }
    return 1;
}

// gsa1.CharacterInfo(kind) -> {name, radius, height, eyes, center (Hammer units), textures, triangles} | nil, msg
GSA1_FN(gsa1_lua_CharacterInfo)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t kind;
    if (!arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1)) {
        return push_nil_msg(LUA, "CharacterInfo(kind): kind 0..8");
    }
    sa1_character_info info;
    std::memset(&info, 0, sizeof info);
    info.struct_size = sizeof info;
    sa1_physics ph;
    std::memset(&ph, 0, sizeof ph);
    if (sa1_character_info_get(g_session->ctx(), kind, &info) != SA1_OK || !info.loaded ||
        sa1_physics_get(g_session->ctx(), kind, &ph) != SA1_OK) {
        return push_nil_msg(LUA, "this character is not loaded");
    }
    sa1_coords co;
    std::memset(&co, 0, sizeof co);
    co.struct_size = sizeof co;
    sa1_get_coords(g_session->ctx(), &co);
    uint32_t ntex = 0;
    std::string err;
    g_session->texture_count(kind, 0, ntex, err);
    LUA->CreateTable();
    int t = LUA->Top();
    raw_str(LUA, t, "name", sa1_character_name(kind));
    raw_num(LUA, t, "radius", ph.rad * co.scale);
    raw_num(LUA, t, "height", ph.height * co.scale);
    raw_num(LUA, t, "eyes", ph.eyes_height * co.scale);
    raw_num(LUA, t, "center", ph.center_height * co.scale);
    raw_num(LUA, t, "scale", co.scale);
    raw_num(LUA, t, "textures", ntex);
    raw_num(LUA, t, "max_triangles", info.max_triangles);
    raw_num(LUA, t, "archives", info.num_archives);
    return 1;
}

// gsa1.WorldLoad(mapName) -> true, info | false, message, code ("bad_name" | "not_found" | "bad_map" | "error")
GSA1_FN(gsa1_lua_WorldLoad)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    std::string name;
    if (!arg_string(LUA, 1, name, 64) || !gsa1::valid_map_name(name)) {
        return push_false_msg(LUA, "WorldLoad(mapName): a bare map name like gm_construct", "bad_name");
    }
    if (g_gmod_dir.empty()) {
        return push_false_msg(LUA, "the module is not in garrysmod/lua/bin: maps cannot be found", "not_found");
    }
    std::string path, searched;
    if (!gsa1::find_map_file(g_gmod_dir, name, path, searched)) {
        return push_false_msg(LUA, name + ".bsp is not in " + searched + " (a mounted or workshop map: use WorldLoadData)",
                              "not_found");
    }
    gsa1::FileByteSource src;
    std::string err;
    if (!src.open(path, err)) {
        return push_false_msg(LUA, "map " + name + ": " + err, "error");
    }
    return load_world_from(LUA, src, name);
}

// gsa1.WorldLoadData(bspBytes, mapName) -> as WorldLoad (maps inside .gma / .vpk: the addon reads them with file.Read)
GSA1_FN(gsa1_lua_WorldLoadData)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    if (!LUA->IsType(1, LT::String)) {
        return push_false_msg(LUA, "WorldLoadData(bspBytes, mapName)", "bad_map");
    }
    unsigned int len = 0;
    const char *data = LUA->GetString(1, &len);
    std::string name;
    if (!arg_string(LUA, 2, name, 64) || !gsa1::valid_map_name(name)) {
        name = "map";
    }
    if (!data || len < 1036 || len > (512u << 20)) {
        return push_false_msg(LUA, "WorldLoadData: not a BSP file", "bad_map");
    }
    gsa1::MemoryByteSource src(data, len);
    return load_world_from(LUA, src, name);
}

// gsa1.WorldInfo() -> table | nil
GSA1_FN(gsa1_lua_WorldInfo)
{
    if (!g_world_ok) {
        LUA->PushNil();
        return 1;
    }
    return world_info_table(LUA);
}

// ---- the map's collision, loaded in the background (mapjob.hpp) ------------------------------------------------------
namespace {

std::string cache_dir()
{
    if (g_gmod_dir.empty()) {
        return std::string();
    }
    return gsa1::join_path(gsa1::join_path(gsa1::join_path(g_gmod_dir, "data"), "gsa1"), "cache");
}

// MapStart / MapStartData options: {static_props=, brush_models=, cache=, prop_min_size=, thin_wall_max=, prepare=}
gsa1::MapJobOptions map_options(ILuaBase *L, int i)
{
    gsa1::MapJobOptions o;
    bool b, cache = true;
    double d;
    if (L->IsType(i, LT::Table)) {
        int t = absidx(L, i);
        if (raw_get_bool(L, t, "static_props", b)) o.static_props = b;
        if (raw_get_bool(L, t, "brush_models", b)) o.brush_models = b;
        if (raw_get_bool(L, t, "cache", b)) cache = b;
        if (raw_get_number(L, t, "prop_min_size", d)) o.prop_min_size = (float)std::max(0.0, std::min(256.0, d));
        // thin walls (bsp.hpp BspWorldOptions::thin_wall_max): two opposite steep faces of a solid at most this far
        // apart become one double-sided face; 0 = off (whole Hammer units, at most 64)
        if (raw_get_number(L, t, "thin_wall_max", d)) o.world.thin_wall_max = (float)std::floor(std::max(0.0, std::min(64.0, d)));
        if (raw_get_bool(L, t, "prepare", b)) o.prepare = b;
        // 0.9.3: the Collision page's "Solid ceilings over thin roofs" (cl_menu.lua MapOptionHooks.solid_ceilings);
        // off = the one-way undersides until 0.9.2 (PrepareOptions::undersides_drop; a new preparation, no rebuild)
        if (raw_get_bool(L, t, "solid_ceilings", b)) o.grid.undersides_drop = !b;
    }
    gsa1::mod::surfaces_map_options(o);   // the surface class table (gsa1.SetSurfaceTable)
    if (cache) {
        o.cache_dir = cache_dir();
    }
    return o;
}

// deletes the retired jobs whose worker has finished (never waits)
void reap_jobs()
{
    for (size_t k = 0; k < g_retired_jobs.size();) {
        if (g_retired_jobs[k]->idle()) {
            delete g_retired_jobs[k];   // its worker is done: the join inside returns at once
            g_retired_jobs.erase(g_retired_jobs.begin() + (std::ptrdiff_t)k);
        } else {
            k++;
        }
    }
}

// drops the current job without waiting: a worker still running (a libsa1 preparation cannot be interrupted, a
// stage stops at its next check) finishes in the background and the job is deleted by a later reap_jobs()
void drop_job()
{
    if (g_job) {
        g_job->request_cancel();
        g_retired_jobs.push_back(g_job);
        g_job = nullptr;
    }
    reap_jobs();
}

// module unload: waits for every worker
void drop_all_jobs()
{
    delete g_job;
    g_job = nullptr;
    for (gsa1::MapJob *j : g_retired_jobs) {
        j->request_cancel();
    }
    for (gsa1::MapJob *j : g_retired_jobs) {
        delete j;
    }
    g_retired_jobs.clear();
}

}  // namespace

std::string gsa1::mod::scrubbed(const std::string &m)
{
    return g_session ? g_session->scrub(m) : m;
}

// gsa1.MapStart(mapName [, options]) -> true, "file" | false, message, code ("bad_name" | "not_found" | "bad_map")
// Starts loading the map's collision in the background: a map the module finds itself (garrysmod/maps,
// download/maps, addons/*/maps). not_found: a workshop or mounted map, which the addon reads (gsa1.MapStartData).
// options: {static_props = true, brush_models = true, cache = true, prop_min_size = 8, thin_wall_max = 16 (Hammer
// units, 0 = off), prepare = true (libsa1's GRID synthesis on the worker too)}. A job before is dropped without
// waiting for it. The world that is applied stays in use until MapApply swaps in the new one.
GSA1_FN(gsa1_lua_MapStart)
{
    std::string name;
    if (!arg_string(LUA, 1, name, 64) || !gsa1::valid_map_name(name)) {
        return push_false_msg(LUA, "MapStart(mapName): a bare map name like gm_construct", "bad_name");
    }
    drop_job();
    if (g_gmod_dir.empty()) {
        return push_false_msg(LUA, "the module is not in garrysmod/lua/bin: maps cannot be found", "not_found");
    }
    std::string path, searched;
    if (!gsa1::find_map_file(g_gmod_dir, name, path, searched)) {
        return push_false_msg(LUA, name + ".bsp is not in " + searched + " (a mounted or workshop map: MapStartData)",
                              "not_found");
    }
    gsa1::MapJobOptions o = map_options(LUA, 2);
    gsa1::MapJob *j = new gsa1::MapJob();
    std::string err;
    if (!j->start_file(name, path, o, err)) {
        delete j;
        return push_false_msg(LUA, "map " + name + ": " + scrubbed(err), "bad_map");
    }
    g_job = j;
    LUA->PushBool(true);
    LUA->PushString("file");
    return 2;
}

// gsa1.MapStartData(mapName, header, size [, options]) -> true, "fed" | false, message, code
// The addon opened the map through Garry's Mod's own file system: its first 1036 bytes and its size in bytes. The
// module then asks for the byte ranges it reads (gsa1.MapPoll().needs: a few MB of the file) and the addon hands
// them over (gsa1.MapFeed).
GSA1_FN(gsa1_lua_MapStartData)
{
    std::string name, header;
    double size = 0;
    if (!arg_string(LUA, 1, name, 64) || !gsa1::valid_map_name(name)) {
        return push_false_msg(LUA, "MapStartData(mapName, header, size): a bare map name", "bad_name");
    }
    if (!arg_string(LUA, 2, header, 4096) || header.size() < 1036 || !arg_number(LUA, 3, size) || size < 1036.0 ||
        size > 4294967296.0 || size != std::floor(size)) {
        return push_false_msg(LUA, "MapStartData(mapName, header (the first 1036 bytes), size)", "bad_map");
    }
    drop_job();
    gsa1::MapJobOptions o = map_options(LUA, 4);
    gsa1::MapJob *j = new gsa1::MapJob();
    std::string err;
    if (!j->start_fed(name, header.data(), header.size(), (uint64_t)size, o, err)) {
        delete j;
        return push_false_msg(LUA, "map " + name + ": " + scrubbed(err), "bad_map");
    }
    g_job = j;
    LUA->PushBool(true);
    LUA->PushString("fed");
    return 2;
}

// gsa1.MapPoll([out]) -> out | nil (no map loading)
// Once per frame while a map loads: advances the job (joins a finished worker, starts the next stage).
// out = {map, state ("cache" | "reading" | "parsing" | "files" | "building" | "preparing" | "ready" | "failed"),
//        progress (0..1),
//        error, ms, fed (the addon reads the map), bytes_fed, bytes_needed, files_total, files_done,
//        needs = { {ofs=, len=}, ... } (reading: up to 32 ranges of at most 1 MB, in file order),
//        files = { {path=, max=}, ... } (files: up to 64 model files; max = the bytes wanted, 0 = the whole file)}
GSA1_FN(gsa1_lua_MapPoll)
{
    reap_jobs();
    if (!g_job) {
        LUA->PushNil();
        return 1;
    }
    g_job->poll();
    int t = out_table(LUA, 1);
    gsa1::MapState s = g_job->state();
    raw_str(LUA, t, "map", g_job->map());
    raw_str(LUA, t, "state", gsa1::map_state_name(s));
    raw_num(LUA, t, "progress", g_job->progress());
    raw_str(LUA, t, "error", scrubbed(g_job->error()));
    raw_num(LUA, t, "ms", g_job->elapsed_ms());
    raw_bool(LUA, t, "fed", g_job->fed());
    raw_num(LUA, t, "bytes_fed", (double)g_job->bytes_fed());
    raw_num(LUA, t, "files_total", g_job->files_total());
    raw_num(LUA, t, "files_done", g_job->files_done());
    std::vector<std::pair<uint64_t, uint64_t>> needs;
    uint64_t need_total = 0;
    if (s == gsa1::MapState::Reading) {
        g_job->needs(needs, 32, 1u << 20);
        need_total = g_job->bytes_needed();
    }
    raw_num(LUA, t, "bytes_needed", (double)need_total);
    LUA->PushString("needs");
    LUA->CreateTable();
    int nt = LUA->Top();
    for (size_t i = 0; i < needs.size(); i++) {
        LUA->PushNumber((double)(i + 1));
        LUA->CreateTable();
        int e = LUA->Top();
        raw_num(LUA, e, "ofs", (double)needs[i].first);
        raw_num(LUA, e, "len", (double)needs[i].second);
        LUA->RawSet(nt);
    }
    LUA->RawSet(t);
    std::vector<std::pair<std::string, uint32_t>> files;
    if (s == gsa1::MapState::Files) {
        g_job->files(files, 64);
    }
    LUA->PushString("files");
    LUA->CreateTable();
    int ft = LUA->Top();
    for (size_t i = 0; i < files.size(); i++) {
        LUA->PushNumber((double)(i + 1));
        LUA->CreateTable();
        int e = LUA->Top();
        raw_str(LUA, e, "path", files[i].first);
        raw_num(LUA, e, "max", files[i].second);
        LUA->RawSet(ft);
    }
    LUA->RawSet(t);
    return 1;
}

// gsa1.MapFeed(ofs, bytes) -> true | false, message   (reading: a piece of a range MapPoll asked for; at most 16 MB)
GSA1_FN(gsa1_lua_MapFeed)
{
    double ofs = 0;
    if (!g_job || !arg_number(LUA, 1, ofs) || ofs < 0.0 || ofs != std::floor(ofs) || !LUA->IsType(2, LT::String)) {
        return push_false_msg(LUA, "MapFeed(offset, bytes): while a map is being read");
    }
    unsigned int len = 0;
    const char *p = LUA->GetString(2, &len);
    if (!p || len > (16u << 20)) {
        return push_false_msg(LUA, "MapFeed: at most 16 MB per call");
    }
    std::string err;
    if (!g_job->feed((uint64_t)ofs, p, len, err)) {
        return push_false_msg(LUA, err);
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.MapFeedFile(path, bytes | nil) -> true | false, message   (files: a model file MapPoll asked for; nil: it is
// missing or cannot be read)
GSA1_FN(gsa1_lua_MapFeedFile)
{
    std::string path;
    if (!g_job || !arg_string(LUA, 1, path, 260)) {
        return push_false_msg(LUA, "MapFeedFile(path, bytes | nil): while a map waits for model files");
    }
    std::string err;
    bool ok;
    if (LUA->IsType(2, LT::String)) {
        unsigned int len = 0;
        const char *p = LUA->GetString(2, &len);
        ok = g_job->feed_file(path, p, p ? len : 0, err);
    } else {
        ok = g_job->feed_file(path, nullptr, 0, err);
    }
    if (!ok) {
        return push_false_msg(LUA, err);
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.MapApply() -> true, info | false, message, code ("not_ready": no disc yet, "busy": still loading, "failed",
// "idle": nothing loaded)
// Hands the loaded map to libsa1: the static world - since 0.5.1 already synthesized by the job's worker
// (sa1_collision_set_prepared: O(1), info.prepared) and shared by every character created afterwards; existing ones
// keep their world until they are re-created - and the brush models' shapes for the moving objects (gsa1.MoverUpdate
// with key "b<N>"). The props' shapes are dropped too when the thin-wall threshold changed (they are rebuilt).
GSA1_FN(gsa1_lua_MapApply)
{
    if (!g_session || !g_session->ready()) {
        return push_false_msg(LUA, "G-SA1 is not initialised: run gsa1.Init() first (it loads your disc)", "not_ready");
    }
    if (!g_job) {
        return push_false_msg(LUA, "no map is loading (gsa1.MapStart)", "idle");
    }
    g_job->poll();
    gsa1::MapState s = g_job->state();
    if (s == gsa1::MapState::Failed) {
        std::string m = "map " + g_job->map() + ": " + scrubbed(g_job->error());
        drop_job();
        return push_false_msg(LUA, m, "failed");
    }
    if (s != gsa1::MapState::Ready) {
        return push_false_msg(LUA, "the map is still loading", "busy");
    }
    gsa1::MapResult r;
    if (!g_job->take(r)) {
        drop_job();
        return push_false_msg(LUA, "the map was applied already", "idle");
    }
    float thin = g_job->options().world.thin_wall_max;
    drop_job();
    double t0 = gsa1::now_ms();
    std::string err;
    bool prepared = r.prep.ok && r.prep.prepared;
    g_world_refused.clear();
    if (!prepared && r.prep.too_big) {
        // 0.9.2a (the 0.9.2 verifier's leftover): more than the game's collision memory holds, also after the retry
        // without the triangles outside the map (prepare_world_guarded). Handing libsa1 the triangles would make the
        // first character run the same failing GRID synthesis on the game's thread (seconds) and fail with "safety limit
        // exceeded": the map gets no collision (the old map's goes) and gsa1.Create says why at once
        if (!g_session->set_world(std::vector<sa1_collision_tri>(), err)) {
            return push_false_msg(LUA, err, "error");
        }
        g_world_refused = scrubbed(r.prep.error);
        g_prep_note = g_world_refused;
        g_session->log_line(SA1_LOG_WARN, ("map collision: " + g_world_refused).c_str());
    } else if (prepared) {
        if (!g_session->set_world_prepared(r.prep.prepared, err)) {
            return push_false_msg(LUA, err, "error");
        }
        g_prep_note.clear();
    } else {
        // not prepared ahead (the preparation failed, or prepare = false): the first character synthesizes it
        if (!g_session->set_world(r.world, err)) {
            return push_false_msg(LUA, err, "error");
        }
        g_prep_note = r.prep.error.empty() ? std::string("not prepared ahead (prepare = false)")
                                           : scrubbed("the preparation failed: " + r.prep.error);
        g_session->log_line(SA1_LOG_WARN, ("map collision " + g_prep_note + "; the first character builds it").c_str());
    }
    g_world_prepared = prepared;
    g_prep_info = r.prep;
    g_prep_info.prepared.reset();   // the session holds the geometry
    gsa1::Movers &mv = g_session->movers();
    mv.clear(g_session->ctx());
    mv.drop_shapes("b");
    if (thin != g_thin_wall) {
        mv.drop_shapes("m:");   // the props' shapes were cleaned with the old thin-wall threshold
        mv.drop_shapes("x:");
        g_thin_wall = thin;
    }
    for (auto &kv : r.models) {
        mv.set_shape(gsa1::format("b%d", (int)kv.first), std::move(kv.second));
    }
    g_world = r.st.world;
    g_world_map = r.map;
    g_world_ok = true;
    g_map = r.st;
    g_map_full = true;
    g_map_from_cache = r.from_cache;
    g_map_cache_written = r.cache_written;
    g_map_cache_ms = r.cache_ms;
    g_map_cache_note = r.cache_note;
    g_map_props_note = r.props_note;
    gsa1::mod::surfaces_map_applied(r);   // its surface types (gsa1.SurfaceInfo)
    g_map_apply_ms = gsa1::now_ms() - t0;
    LUA->PushBool(true);
    world_info_table(LUA);
    return 2;
}

// gsa1.MapCancel()
GSA1_FN(gsa1_lua_MapCancel)
{
    drop_job();
    return 0;
}

// ---- moving collision (movers.hpp): brush entities, physics props, vehicles -----------------------------------------
namespace {

// "m:<model path>" (a physics model), "x:<anything>" (a box): printable, at most 260 characters
bool shape_key(const std::string &k, char kind)
{
    if (k.size() < 3 || k.size() > 260 || k[0] != kind || k[1] != ':') {
        return false;
    }
    for (char c : k) {
        if ((unsigned char)c < 0x20 || (unsigned char)c > 0x7e) {
            return false;
        }
    }
    return true;
}

}  // namespace

bool gsa1::mod::arg_angle(ILuaBase *L, int i, float out[3])
{
    if (!L->IsType(i, LT::Angle)) {
        return false;
    }
    const QAngle &a = L->GetAngle(i);
    out[0] = a.x;
    out[1] = a.y;
    out[2] = a.z;
    return std::isfinite(out[0]) && std::isfinite(out[1]) && std::isfinite(out[2]);
}

namespace {

const size_t kMaxShapes = 4096;

}  // namespace

// gsa1.ShapeKnown(key) -> bool   ("b<N>": brush model N of the applied map; "m:<model>"; "x:<name>")
GSA1_FN(gsa1_lua_ShapeKnown)
{
    std::string key;
    LUA->PushBool(g_session && arg_string(LUA, 1, key, 260) && g_session->movers().has_shape(key));
    return 1;
}

// gsa1.ShapePhy(key, phyBytes) -> true, triangles, chunks | false, message
// A physics model (the .phy next to the .mdl, read by the addon through Garry's Mod's file system) as a moving
// object's shape: its convex pieces cleaned like brushes and cut into well-shaped pieces. key: "m:<model path>".
GSA1_FN(gsa1_lua_ShapePhy)
{
    std::string key;
    if (!g_session || !arg_string(LUA, 1, key, 260) || !shape_key(key, 'm') || !LUA->IsType(2, LT::String)) {
        return push_false_msg(LUA, "ShapePhy(\"m:<model>\", phyBytes)");
    }
    if (g_session->movers().shape_count() >= kMaxShapes) {
        return push_false_msg(LUA, "too many shapes");
    }
    unsigned int len = 0;
    const char *p = LUA->GetString(2, &len);
    if (!p || len > (16u << 20)) {
        return push_false_msg(LUA, "ShapePhy: at most 16 MB");
    }
    gsa1::PhyModel m;
    std::string err;
    gsa1::Shape sh;
    if (!gsa1::parse_phy(p, len, m, err) || !gsa1::mod::surfaces_shape_phy(m, sh, err, g_thin_wall)) {
        return push_false_msg(LUA, err);
    }
    uint32_t tris = sh.tris, chunks = (uint32_t)sh.chunks.size();
    g_session->movers().set_shape(key, std::move(sh));
    LUA->PushBool(true);
    LUA->PushNumber(tris);
    LUA->PushNumber(chunks);
    return 3;
}

// gsa1.ShapeBox(key, mins, maxs) -> true, triangles | false, message   (an entity's collision box; key "x:<name>")
GSA1_FN(gsa1_lua_ShapeBox)
{
    std::string key;
    float mn[3], mx[3];
    if (!g_session || !arg_string(LUA, 1, key, 260) || !shape_key(key, 'x') || !arg_vector(LUA, 2, mn) ||
        !arg_vector(LUA, 3, mx)) {
        return push_false_msg(LUA, "ShapeBox(\"x:<name>\", Vector mins, Vector maxs)");
    }
    if (g_session->movers().shape_count() >= kMaxShapes) {
        return push_false_msg(LUA, "too many shapes");
    }
    gsa1::Shape sh;
    std::string err;
    if (!gsa1::shape_box(mn, mx, sh, err, g_thin_wall)) {
        return push_false_msg(LUA, err);
    }
    uint32_t tris = sh.tris;
    g_session->movers().set_shape(key, std::move(sh));
    LUA->PushBool(true);
    LUA->PushNumber(tris);
    return 2;
}

// gsa1.MoverUpdate(entIndex, key, pos, ang, solid) -> bool
// An entity's state this frame (call it every frame for the entities near the character): its shape key, its
// position and angles (the module builds the rotation MATRIX), whether it is solid now. Entities not updated for a
// second are dropped.
GSA1_FN(gsa1_lua_MoverUpdate)
{
    int32_t ent;
    std::string key;
    float pos[3], ang[3];
    if (!g_session || !arg_int(LUA, 1, ent, -2147483647.0, 2147483647.0) || !arg_string(LUA, 2, key, 260) ||
        key.empty() || !arg_vector(LUA, 3, pos) || !arg_angle(LUA, 4, ang)) {
        LUA->PushBool(false);
        return 1;
    }
    bool solid = !LUA->IsType(5, LT::Bool) || LUA->GetBool(5);
    g_session->movers().update(ent, key, pos, ang, solid, now_s());
    LUA->PushBool(true);
    return 1;
}

// gsa1.MoverForget(entIndex)   (the entity was removed)
GSA1_FN(gsa1_lua_MoverForget)
{
    int32_t ent;
    if (g_session && arg_int(LUA, 1, ent, -2147483647.0, 2147483647.0)) {
        g_session->movers().forget(ent);
    }
    return 0;
}

// gsa1.MoverCommit() -> active, parked   (once per frame, before gsa1.Tick: the objects near the character into libsa1)
GSA1_FN(gsa1_lua_MoverCommit)
{
    if (!g_session || !g_session->ready()) {
        LUA->PushNumber(0);
        LUA->PushNumber(0);
        return 2;
    }
    g_session->commit_movers(now_s());
    const gsa1::MoverStats &st = g_session->movers().stats();
    LUA->PushNumber(st.active);
    LUA->PushNumber(st.parked);
    return 2;
}

// gsa1.MoverStatus() -> {entities, solid, unknown_shape, shapes, active, active_tris, parked, candidates, over_budget,
//                        adds, removes, moves, parks, unparks, failures, error}
GSA1_FN(gsa1_lua_MoverStatus)
{
    LUA->CreateTable();
    int t = LUA->Top();
    if (!g_session) {
        return 1;
    }
    const gsa1::Movers &mv = g_session->movers();
    const gsa1::MoverStats &st = mv.stats();
    raw_num(LUA, t, "entities", st.entities);
    raw_num(LUA, t, "solid", st.solid);
    raw_num(LUA, t, "unknown_shape", st.unknown_shape);
    raw_num(LUA, t, "shapes", (double)mv.shape_count());
    raw_num(LUA, t, "active", st.active);
    raw_num(LUA, t, "active_tris", st.active_tris);
    raw_num(LUA, t, "parked", st.parked);
    raw_num(LUA, t, "candidates", st.candidates);
    raw_num(LUA, t, "over_budget", st.over_budget);
    raw_num(LUA, t, "adds", (double)st.adds);
    raw_num(LUA, t, "removes", (double)st.removes);
    raw_num(LUA, t, "moves", (double)st.moves);
    raw_num(LUA, t, "parks", (double)st.parks);
    raw_num(LUA, t, "unparks", (double)st.unparks);
    raw_num(LUA, t, "failures", (double)st.failures);
    raw_str(LUA, t, "error", scrubbed(st.last_error));
    return 1;
}

// gsa1.MoverOptions({range=, max_active=, max_tris=, max_parked=}) -> true   (fields left out keep their value)
GSA1_FN(gsa1_lua_MoverOptions)
{
    if (!g_session || !LUA->IsType(1, LT::Table)) {
        LUA->PushBool(false);
        return 1;
    }
    gsa1::MoverOptions &o = g_session->movers().opt;
    double d;
    if (raw_get_number(LUA, 1, "range", d)) o.range = (float)std::max(200.0, std::min(8000.0, d));
    if (raw_get_number(LUA, 1, "max_active", d)) o.max_active = (uint32_t)std::max(0.0, std::min(48.0, d));
    if (raw_get_number(LUA, 1, "max_tris", d)) o.max_tris = (uint32_t)std::max(0.0, std::min(6000.0, d));
    if (raw_get_number(LUA, 1, "max_parked", d)) o.max_parked = (uint32_t)std::max(0.0, std::min(16.0, d));
    LUA->PushBool(true);
    return 1;
}

// gsa1.Upgrades([kind]) -> { {kind=, name=, title=, flag=, bit=}, ... }
// The characters' upgrades (every character's without kind): name for Create, the game's event flag, the
// playerwk.equipment bit PInitialize derives from it (0: Big's lures, counted by the fishing code).
GSA1_FN(gsa1_lua_Upgrades)
{
    int32_t kind = -1;
    if (LUA->IsType(1, LT::Number) && !arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1)) {
        kind = -2;
    }
    size_t n = 0;
    const gsa1::UpgradeDef *tab = gsa1::upgrade_table(n);
    LUA->CreateTable();
    int t = LUA->Top();
    int k = 0;
    for (size_t i = 0; i < n; i++) {
        if (kind != -1 && tab[i].kind != kind) {
            continue;
        }
        LUA->PushNumber(++k);
        LUA->CreateTable();
        int e = LUA->Top();
        raw_num(LUA, e, "kind", tab[i].kind);
        raw_str(LUA, e, "name", tab[i].name);
        raw_str(LUA, e, "title", tab[i].title);
        raw_num(LUA, e, "flag", tab[i].flag);
        raw_num(LUA, e, "bit", tab[i].equipment);
        LUA->RawSet(t);
    }
    return 1;
}

// the upgrades argument of Create: a table of at most 32 upgrade names of `kind` (array part); false + message
static bool arg_upgrades(ILuaBase *L, int i, int32_t kind, std::vector<const gsa1::UpgradeDef *> &out, std::string &err)
{
    out.clear();
    int type = L->GetType(i);
    if (type == LT::Nil || type == LT::None) {
        return true;
    }
    if (type != LT::Table) {
        err = "upgrades: a table of upgrade names (gsa1.Upgrades(kind))";
        return false;
    }
    int t = absidx(L, i);
    for (int k = 1; k <= 33; k++) {
        L->PushNumber(k);
        L->RawGet(t);
        if (L->IsType(-1, LT::Nil)) {
            L->Pop();
            return true;
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
        const gsa1::UpgradeDef *u = ok ? gsa1::find_upgrade(kind, name) : nullptr;
        if (!u) {
            err = ok ? "upgrades: this character has no upgrade of that name (gsa1.Upgrades(kind))"
                     : "upgrades: a table of at most 32 upgrade names";
            return false;
        }
        out.push_back(u);
    }
    return true;
}

// the extras table of Create (0.9.3, Super Sonic: sadc docs/research/gsa1_rounds_plan.md 11.3): t[k] when it is a whole
// number in [lo, hi] (found = false: absent); false: present but not such a number
static bool extra_int(ILuaBase *L, int t, const char *k, double lo, double hi, double &out, bool &found)
{
    found = false;
    L->PushString(k);
    L->RawGet(t);
    int type = L->GetType(-1);
    bool ok = true;
    if (type != LT::Nil && type != LT::None) {
        found = true;
        double v = 0.0;
        ok = type == LT::Number && arg_number(L, -1, v) && v == std::floor(v) && v >= lo && v <= hi;
        out = v;
    }
    L->Pop();
    return ok;
}

// gsa1.Create(kind, pos, yawDeg [, upgrades [, startRings [, extras]]]) -> id | nil, message
// upgrades: names of the character's upgrades it has (gsa1.Upgrades(kind)); none = the game's start
// startRings (0.9.2, sadc docs/research/gsa1_090_rings.md F7): 0..99 = the rings the world starts with, through the game's
// own ring calls before its first step (SA1_CREATE_START_RINGS; larger values are clamped to 99: a start never gives a
// 1-up); nil or a negative number = the game's 0 (Super Sonic: libsa1's 50, the Perfect Chaos boss's start)
// extras (0.9.3, round 6a; feature "super", bind_super.cpp, has the constants gsa1.SUPER): a table with
//   create_flags = gsa1.SUPER.CREATE_SUPER_CAPABLE | CREATE_WATER_FLOOR (Sonic who can turn Super in play / host water is
//                  a floor for this character), super_flags = gsa1.SUPER.NO_DRAIN | KEEP_AT_ZERO | FAITHFUL_REVERT (given:
//                  SA1_CREATE_SUPER; Super Sonic and a SUPER_CAPABLE Sonic only), start_rings = 0..99 (instead of
//                  startRings; -1 = the game's)
// nil = 0.9.2's create. A bad extras table: nil, message, "bad_extra"
GSA1_FN(gsa1_lua_Create)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t kind;
    float pos[3];
    double yaw = 0.0;
    if (!arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1) || !arg_vector(LUA, 2, pos) ||
        (!LUA->IsType(3, LT::Nil) && !arg_number(LUA, 3, yaw))) {
        return push_nil_msg(LUA, "Create(kind, Vector pos, yawDegrees [, {upgrade names} [, startRings [, extras]]])");
    }
    std::vector<const gsa1::UpgradeDef *> ups;
    std::string err;
    if (!arg_upgrades(LUA, 4, kind, ups, err)) {
        return push_nil_msg(LUA, err, "bad_upgrade");
    }
    int32_t start_rings = -1;
    int t5 = LUA->GetType(5);
    if (t5 != LT::Nil && t5 != LT::None) {
        double r = 0.0;
        if (!arg_number(LUA, 5, r) || r != std::floor(r) || r > 1e6) {
            return push_nil_msg(LUA, "startRings: a whole number (0..99; nil or negative = the game's 0)", "args");
        }
        start_rings = r < 0.0 ? -1 : (int32_t)std::min(r, (double)gsa1::kStartRingsMax);
    }
    // 0.9.3: the extras table (Super Sonic's world)
    gsa1::CreateExtra extra;
    int t6 = LUA->GetType(6);
    if (t6 != LT::Nil && t6 != LT::None) {
        if (t6 != LT::Table) {
            return push_nil_msg(LUA, "extras: a table {create_flags, super_flags, start_rings}", "bad_extra");
        }
        int t = absidx(LUA, 6);
        double v = 0.0;
        bool found = false;
        if (!extra_int(LUA, t, "create_flags", 0.0, 65535.0, v, found)) {
            return push_nil_msg(LUA, "extras.create_flags: a whole number (gsa1.SUPER.CREATE_*)", "bad_extra");
        }
        extra.flags = found ? (uint32_t)v : 0u;
        if (!extra_int(LUA, t, "super_flags", 0.0, 65535.0, v, found)) {
            return push_nil_msg(LUA, "extras.super_flags: a whole number (gsa1.SUPER.NO_DRAIN ...)", "bad_extra");
        }
        extra.super_given = found;
        extra.super_flags = found ? (uint32_t)v : 0u;
        if (!extra_int(LUA, t, "start_rings", -1e6, 1e6, v, found)) {
            return push_nil_msg(LUA, "extras.start_rings: a whole number (0..99; -1 = the game's)", "bad_extra");
        }
        if (found) {
            start_rings = v < 0.0 ? -1 : (int32_t)std::min(v, (double)gsa1::kStartRingsMax);
        }
    }
    if (!g_world_ok) {
        return push_nil_msg(LUA, "no world collision yet: call gsa1.WorldLoad(game.GetMap()) first");
    }
    if (!g_world_refused.empty()) {
        return push_nil_msg(LUA, g_world_refused, "too_big");   // 0.9.2a: MapApply found the map too big for the game
    }
    int32_t id = g_session->create(kind, pos, deg2rad(yaw), err, nullptr, &ups, start_rings, &extra);
    if (id <= 0) {
        return push_nil_msg(LUA, err);
    }
    LUA->PushNumber(id);
    return 1;
}

// gsa1.CreatePuppet(kind) -> id | nil, message   (posed only: the remote-player path)
GSA1_FN(gsa1_lua_CreatePuppet)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t kind;
    if (!arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1)) {
        return push_nil_msg(LUA, "CreatePuppet(kind)");
    }
    std::string err;
    int32_t id = g_session->create_puppet(kind, err);
    if (id <= 0) {
        return push_nil_msg(LUA, err);
    }
    LUA->PushNumber(id);
    return 1;
}

// gsa1.Destroy(id) -> bool
GSA1_FN(gsa1_lua_Destroy)
{
    int32_t id;
    bool ok = g_session && arg_int(LUA, 1, id, 1, 2147483647.0) && g_session->destroy(id);
    LUA->PushBool(ok);
    return 1;
}

// gsa1.Tick(id, stickX, stickY, cameraYawDeg, buttons, dt [, rawStick [, hostFlags [, camOrigin, camTarget]]])
//     -> pairsRun | nil, message, code
// stick: -1..1, +y forward relative to the camera; mapped through the inverse of the game's dead zone (exact
// directions for keyboard input) unless rawStick is true (the DC pad's own behaviour)
// 0.9.2 (sadc docs/research/gsa1_090_plan.md 6.10): hostFlags = gsa1.INPUT_HOST_WATER_KNOWN | INPUT_HOST_IN_WATER (the
// host's water at the character's probe point, from the state after the previous tick: gsa1_090_water.md WTR-A), nil = 0
// (the game's own rule); camOrigin, camTarget (Vectors) = the host camera for libsa1's sa1_input.host_cam_pos / target,
// passed when libsa1 declares them (gsa1.TICK_HOST_CAMERA true), else ignored. code "fault": the character's world died
// in this tick or earlier - a game code fault or a fatal stub (libsa1 SA1_ERR_GAME_FAULT / SA1_ERR_NOT_IMPLEMENTED;
// gsa1_090_faults.md F3.2) - and every later tick of this id fails the same way: re-create the character
GSA1_FN(gsa1_lua_Tick)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t id, buttons;
    double sx, sy, yaw, dt;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_number(LUA, 2, sx) || !arg_number(LUA, 3, sy) ||
        !arg_number(LUA, 4, yaw) || !arg_int(LUA, 5, buttons, 0, 255) || !arg_number(LUA, 6, dt)) {
        return push_nil_msg(LUA, "Tick(id, stickX, stickY, cameraYawDegrees, buttons, dt)", "args");
    }
    bool raw = LUA->IsType(7, LT::Bool) && LUA->GetBool(7);
    gsa1::TickExtra extra;
    int t8 = LUA->GetType(8);
    if (t8 != LT::Nil && t8 != LT::None) {
        int32_t hf = 0;
        if (!arg_int(LUA, 8, hf, 0, 255)) {
            return push_nil_msg(LUA, "Tick(..., rawStick, hostFlags 0..255 [, camOrigin, camTarget])", "args");
        }
        extra.host_flags = (uint32_t)hf;
    }
    if (LUA->IsType(9, LT::Vector) && LUA->IsType(10, LT::Vector)) {
        extra.camera = arg_vector(LUA, 9, extra.cam_pos) && arg_vector(LUA, 10, extra.cam_target);
    }
    sa1_status st = g_session->tick(id, (float)sx, (float)sy, deg2rad(yaw), (uint32_t)buttons, (float)dt, raw, &extra);
    if (st != SA1_OK) {
        const char *code = (st == SA1_ERR_GAME_FAULT || st == SA1_ERR_NOT_IMPLEMENTED) ? "fault"
                           : st == SA1_ERR_NOT_FOUND                                ? "not_found"
                                                                                    : "error";
        return push_nil_msg(LUA, g_session->last_error(), code);
    }
    gsa1::Character *c = g_session->get(id);
    LUA->PushNumber(c ? c->pairs_last : 0);
    return 1;
}

// gsa1.Pose(id, action, frame, pos, yawDeg) -> true | nil, message   (puppets)
GSA1_FN(gsa1_lua_Pose)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t id, action;
    double frame, yaw;
    float pos[3];
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_int(LUA, 2, action, 0, 4096) || !arg_number(LUA, 3, frame) ||
        !arg_vector(LUA, 4, pos) || !arg_number(LUA, 5, yaw)) {
        return push_nil_msg(LUA, "Pose(id, action, frame, Vector pos, yawDegrees)");
    }
    sa1_status st = g_session->pose(id, action, (float)frame, pos, deg2rad(yaw));
    if (st != SA1_OK) {
        return push_nil_msg(LUA, g_session->last_error());
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.GetState(id [, out]) -> out | nil
GSA1_FN(gsa1_lua_GetState)
{
    int32_t id;
    gsa1::Character *c = nullptr;
    if (!g_session || !arg_int(LUA, 1, id, 1, 2147483647.0) || !(c = g_session->get(id))) {
        LUA->PushNil();
        return 1;
    }
    int t = out_table(LUA, 2);
    const sa1_state_ex &s = c->st;
    raw_num(LUA, t, "x", s.position[0]);
    raw_num(LUA, t, "y", s.position[1]);
    raw_num(LUA, t, "z", s.position[2]);
    raw_num(LUA, t, "px", c->prev_pos[0]);
    raw_num(LUA, t, "py", c->prev_pos[1]);
    raw_num(LUA, t, "pz", c->prev_pos[2]);
    raw_num(LUA, t, "vx", s.velocity[0]);
    raw_num(LUA, t, "vy", s.velocity[1]);
    raw_num(LUA, t, "vz", s.velocity[2]);
    raw_num(LUA, t, "yaw", rad2deg(s.yaw));
    raw_num(LUA, t, "action", s.action);
    raw_num(LUA, t, "frame", s.frame);
    raw_num(LUA, t, "flags", s.flags);
    raw_bool(LUA, t, "ground", (s.flags & SA1_STATE_ON_GROUND) != 0);
    raw_num(LUA, t, "surface", s.surface);
    raw_num(LUA, t, "mode", s.mode);
    raw_num(LUA, t, "smode", s.smode);
    raw_num(LUA, t, "step", s.step);
    raw_num(LUA, t, "alpha", c->alpha);
    raw_num(LUA, t, "pairs", c->pairs_last);
    raw_num(LUA, t, "kind", c->kind);
    raw_bool(LUA, t, "faulted", c->faulted);
    raw_num(LUA, t, "render_gen", c->r_gen);
    raw_num(LUA, t, "batches", c->batch_count);
    raw_num(LUA, t, "triangles", c->out_triangles);
    raw_num(LUA, t, "render_ms", c->render_ms);
    raw_num(LUA, t, "view_ms", c->view_ms);
    raw_num(LUA, t, "tick_ms", c->tick_ms_last);
    raw_num(LUA, t, "item", s.item);
    raw_num(LUA, t, "breath", s.breath_timer);
    raw_num(LUA, t, "equipment", s.equipment & 0xFFFFu);
    raw_num(LUA, t, "upgrade_bits", c->upgrade_bits);
    raw_num(LUA, t, "upgrades", (double)c->upgrade_flags.size());
    raw_bool(LUA, t, "upgrades_ok", !c->upgrades_checked || c->upgrades_ok);
    raw_bool(LUA, t, "shifted", c->r_shifted);
    raw_num(LUA, t, "shifted_count", (double)c->shifted_count);
    raw_num(LUA, t, "render_flags", c->r_flags);
    raw_bool(LUA, t, "drawn_root", c->r_drawn_root);
    // 0.8: the game's blob shadow draws of the last Render (SA1_DRAW_SHADOW) and whether the last PrepareView wrote
    // positions relative to an origin (camera-relative drawing)
    raw_num(LUA, t, "shadow_draws", c->shadow_draws);
    raw_bool(LUA, t, "relative", c->view_opt.relative);
    // what the last Render drew (the session log's context lines, sadc docs/research/gsa1_lsd_lag.md 6.3)
    uint32_t blended = 0, sprite_batches = 0;
    for (uint32_t b = 0; b < c->batch_count; b++) {
        blended += c->batches[b].pass ? 1u : 0u;
        sprite_batches += (c->batches[b].prims & (1u << SA1_PRIM_SPRITES)) ? 1u : 0u;
    }
    raw_num(LUA, t, "draws", (double)c->r_draws.size());
    raw_num(LUA, t, "sprites", (double)c->r_sprites.size());
    raw_num(LUA, t, "lines", (double)(c->r_lines.size() / 2u));
    raw_num(LUA, t, "blended", blended);
    raw_num(LUA, t, "sprite_batches", sprite_batches);
    raw_num(LUA, t, "vertices", (double)c->out_triangles * 3.0);
    raw_num(LUA, t, "mesh_calls", (double)g_emit_calls);
    raw_num(LUA, t, "sprite_max", c->sprite_max);
    // the last PrepareView with a screen (fov, width, height): the screen area of the blended batches, in screens
    raw_num(LUA, t, "blend_layers", c->view_cover);
    raw_num(LUA, t, "sprite_layers", c->view_cover_sprites);
    // 0.9.2 (sadc docs/research/gsa1_090_water.md WTR-LOG): the game's water probe after the last step (sa1_state_ex
    // water_attr: the COL bits of the lowest water surface above the character, & 0x400002 = the game counts it in water;
    // water_level: that surface's height in Hammer units), and the host flags the last tick passed (WTR-A)
#if defined(SA1_API_092)
    raw_num(LUA, t, "water_attr", s.water_attr);
    raw_num(LUA, t, "water_level", s.water_level);
    raw_bool(LUA, t, "in_water", (s.water_attr & 0x400002u) != 0);
#endif
    raw_num(LUA, t, "host_flags", c->host_flags_last);
    raw_num(LUA, t, "start_rings", c->start_rings);
    return 1;
}

// gsa1.Render(id, alpha) -> gen, batchGen, x, y, z, yawDeg, interpolated, alphaUsed, triangles, movedWithRoot
//                            | nil, message
// alpha: < 0 = libsa1's accumulator (interpolated between the last two pairs), 1 = the last pair as it is.
// The draws of the character (sa1_character_render) sorted into batches (gsa1.Batches); x y z yaw: the root
// at alpha - the root of the step the game drew (libsa1 SA1_RENDER_DRAWN_ROOT), which the camera follows.
// movedWithRoot: no draw of the last pair matched the previous pair (an action change; Knuckles' jump draws the ball
// and the curled body in turn), so libsa1 drew the last pair moved along with the interpolated root
// (SA1_RENDER_MOVED_WITH_ROOT). It is only reported: 0.6.0 draws it as libsa1 returns it (0.4-0.5.1 moved it a second
// time: the "forward and backward" flicker, sadc docs/research/gsa1_vertical_flicker.md).
GSA1_FN(gsa1_lua_Render)
{
    int32_t id;
    double alpha;
    gsa1::Character *c = nullptr;
    if (!g_session || !arg_int(LUA, 1, id, 1, 2147483647.0) || !arg_number(LUA, 2, alpha) ||
        !(c = g_session->get(id))) {
        return push_nil_msg(LUA, "Render(id, alpha)");
    }
    sa1_status st = g_session->render(id, (float)std::max(-1.0, std::min(1.0, alpha)));
    if (st != SA1_OK) {
        return push_nil_msg(LUA, g_session->last_error());
    }
    LUA->PushNumber(c->r_gen);
    LUA->PushNumber(c->batch_gen);
    LUA->PushNumber(c->r_pos[0]);
    LUA->PushNumber(c->r_pos[1]);
    LUA->PushNumber(c->r_pos[2]);
    LUA->PushNumber(rad2deg(c->r_yaw));
    LUA->PushBool(c->r_interpolated != 0);
    LUA->PushNumber(c->r_alpha);
    LUA->PushNumber(c->out_triangles);
    LUA->PushBool(c->r_shifted);
    return 10;
}

// gsa1.Batches(id, out) -> count | nil
// out = { gen=, count=, triangles=, [i] = { key=, pass=, archive=, tex=, flags=, all=, src=, dst=, mat=, wrap=,
//         tris=, order=, source=, prims= } }   (pass 0: opaque; pass 1: blended, drawn in this order)
GSA1_FN(gsa1_lua_Batches)
{
    int32_t id;
    gsa1::Character *c = nullptr;
    if (!g_session || !arg_int(LUA, 1, id, 1, 2147483647.0) || !(c = g_session->get(id)) ||
        !LUA->IsType(2, LT::Table)) {
        LUA->PushNil();
        return 1;
    }
    int t = absidx(LUA, 2);
    raw_num(LUA, t, "gen", c->batch_gen);
    raw_num(LUA, t, "count", c->batch_count);
    raw_num(LUA, t, "triangles", c->out_triangles);
    for (uint32_t b = 0; b < c->batch_count; b++) {
        const gsa1::RenderBatch &rb = c->batches[b];
        int bt = raw_subtable_i(LUA, t, (int)b + 1);
        raw_str(LUA, bt, "key", rb.key);
        raw_num(LUA, bt, "pass", rb.pass);
        raw_num(LUA, bt, "archive", rb.archive);
        raw_num(LUA, bt, "tex", rb.texture);
        raw_num(LUA, bt, "flags", rb.flags);
        raw_num(LUA, bt, "all", rb.all_flags);
        raw_num(LUA, bt, "src", rb.blend_src);
        raw_num(LUA, bt, "dst", rb.blend_dst);
        raw_num(LUA, bt, "mat", rb.material);
        raw_num(LUA, bt, "wrap", rb.wrap);
        raw_num(LUA, bt, "tris", rb.triangles);
        raw_num(LUA, bt, "order", rb.order);
        raw_num(LUA, bt, "source", rb.source);
        raw_num(LUA, bt, "prims", rb.prims);
        LUA->Pop();
    }
    LUA->PushNumber(c->batch_count);
    return 1;
}

// gsa1.PrepareView(id, eyePos, right, up [, flip, vertexColor, linePixels, lit, fov, width, height, origin]) -> true | nil
// the batches' vertices for this camera (sprites and lines face it, sphere maps follow it). lit (default true): the
// materials are lit (gsa1_lighting), so EmitBatch leaves mesh.Normal out only for SA1_DRAW_UNLIT batches; false: for
// every batch. fov (4:3 horizontal degrees, as CalcView's), width, height (pixels): measure the screen area the blended
// batches cover (GetState blend_layers / sprite_layers). origin (a Vector, 0.8, feature "render"): EmitBatch writes every
// position minus origin (subtracted in double), for a view whose eye is eyePos - origin (camera-relative drawing: the
// GPU's float32 transform on small numbers; sadc docs/research/gsa1_060_render.md review R7.3); nil: absolute positions.
GSA1_FN(gsa1_lua_PrepareView)
{
    int32_t id;
    float eye[3], right[3], up[3];
    gsa1::Character *c = nullptr;
    if (!g_session || !arg_int(LUA, 1, id, 1, 2147483647.0) || !(c = g_session->get(id)) || !arg_vector(LUA, 2, eye) ||
        !arg_vector(LUA, 3, right) || !arg_vector(LUA, 4, up)) {
        LUA->PushNil();
        return 1;
    }
    gsa1::ViewOptions o;
    o.flip = LUA->IsType(5, LT::Bool) && LUA->GetBool(5);
    o.vertex_color = !LUA->IsType(6, LT::Bool) || LUA->GetBool(6);
    double lp;
    if (arg_number(LUA, 7, lp)) {
        o.line_pixels = (float)std::max(0.5, std::min(16.0, lp));
    }
    o.lit = !LUA->IsType(8, LT::Bool) || LUA->GetBool(8);
    double fov, w, h;
    if (arg_number(LUA, 9, fov) && arg_number(LUA, 10, w) && arg_number(LUA, 11, h) && fov > 1.0 && fov < 179.0 &&
        w >= 16.0 && w <= 16384.0 && h >= 16.0 && h <= 16384.0) {
        o.fov = (float)fov;
        o.width = (float)w;
        o.height = (float)h;
    }
    float org[3];
    if (arg_vector(LUA, 12, org)) {
        o.relative = true;
        std::memcpy(o.origin, org, sizeof org);
    }
    g_session->prepare_view(*c, eye, right, up, o);
    LUA->PushBool(true);
    return 1;
}

namespace {

// pcall of the function + nargs on the stack; an error (message popped) counts and returns false
bool pcall0(ILuaBase *L, int nargs)
{
    g_emit_calls++;
    if (L->PCall(nargs, 0, 0) != 0) {
        L->Pop();
        g_emit_errors++;
        return false;
    }
    return true;
}

// Decides once per Lua state how Vectors reach mesh.Position / mesh.Normal: two scratch Vectors (registry
// references) written in place through ILuaBase::GetVector's reference - checked by reading the component back
// through Lua - or, if that does not hold, a new Vector per call.
void init_vectors(ILuaBase *L)
{
    if (g_vec_mode >= 0) {
        return;
    }
    g_vec_mode = 0;
    for (int i = 0; i < 2; i++) {
        Vector z;
        z.x = z.y = z.z = 0.0f;
        L->PushVector(z);
        g_vec_ref[i] = L->ReferenceCreate();
    }
    L->ReferencePush(g_vec_ref[0]);
    if (L->IsType(-1, LT::Vector)) {
        Vector &w = const_cast<Vector &>(L->GetVector(-1));
        w.x = 1234.5f;
        w.y = -2.25f;
    }
    L->Pop();
    // read back through Lua (the Vector's own __index), not through GetVector
    L->ReferencePush(g_vec_ref[0]);
    bool ok = false;
    if (L->IsType(-1, LT::Vector)) {
        L->GetField(-1, "x");
        L->GetField(-2, "y");
        ok = L->IsType(-2, LT::Number) && L->IsType(-1, LT::Number) && L->GetNumber(-2) == 1234.5 &&
             L->GetNumber(-1) == -2.25;
        L->Pop(2);
    }
    L->Pop();
    g_vec_mode = ok ? 1 : 0;
}

}  // namespace

// gsa1.EmitBatch(id, b) -> vertices | nil, message
// Call between mesh.Begin(MATERIAL_TRIANGLES, batch.tris) (dynamic or an IMesh) and mesh.End(): streams batch b's
// vertices (gsa1.PrepareView) through mesh.Position / Normal / TexCoord / Color / AdvanceVertex - no Lua tables.
// 0.6.0 (round 4c E1): mesh.Normal is left out where the batch's material is unlit (UnlitGeneric reads no normal) and
// mesh.TexCoord where it is untextured (vgui/white is white at every UV) and not sphere-mapped.
GSA1_FN(gsa1_lua_EmitBatch)
{
    int32_t id, b;
    gsa1::Character *c = nullptr;
    if (!g_session || !arg_int(LUA, 1, id, 1, 2147483647.0) || !(c = g_session->get(id)) ||
        !arg_int(LUA, 2, b, 1, 65535) || (uint32_t)b > c->batch_count) {
        return push_nil_msg(LUA, "EmitBatch(id, batch)");
    }
    return gsa1::mod::emit_batch(LUA, *c, b);
}

// 0.9.4b (objects2_plan.md 6.3 task 2): gsa1.EmitBatch's vertex streaming as a helper - also gsa1.PreviewEmitBatch's
// (bind_preview.cpp: a preview copy's render-state holder), unchanged in behaviour (EmitBatch's tests unchanged)
int gsa1::mod::emit_batch(ILuaBase *LUA, gsa1::Character &cr, int32_t b)
{
    gsa1::Character *c = &cr;
    if (!g_session || b < 1 || (uint32_t)b > c->batch_count) {
        return push_nil_msg(LUA, "EmitBatch(id, batch)");
    }
    if (!c->view_ready) {
        g_session->prepare_view(*c, c->view_eye, c->view_right, c->view_up, c->view_opt);
    }
    const gsa1::RenderBatch &rb = c->batches[(size_t)b - 1];
    size_t nv = (size_t)rb.triangles * 3u;
    if (rb.pos.size() < nv * 3u || rb.uv.size() < nv * 2u || rb.col.size() < nv * 4u) {
        return push_nil_msg(LUA, "batch not prepared");
    }
    init_vectors(LUA);
    int base = LUA->Top();
    LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    LUA->PushString("mesh");
    LUA->RawGet(-2);
    if (!LUA->IsType(-1, LT::Table)) {
        LUA->Pop(LUA->Top() - base);
        return push_nil_msg(LUA, "the mesh library is missing");
    }
    int mt = LUA->Top();
    static const char *const names[5] = {"Position", "Normal", "TexCoord", "Color", "AdvanceVertex"};
    for (const char *nm : names) {
        LUA->PushString(nm);
        LUA->RawGet(mt);
        if (!LUA->IsType(-1, LT::Function)) {
            LUA->Pop(LUA->Top() - base);
            return push_nil_msg(LUA, std::string("mesh.") + nm + " is missing");
        }
    }
    const int f_pos = mt + 1, f_nrm = mt + 2, f_tc = mt + 3, f_col = mt + 4, f_adv = mt + 5;
    int v_pos = 0, v_nrm = 0;
    Vector *w_pos = nullptr, *w_nrm = nullptr;
    if (g_vec_mode == 1) {
        LUA->ReferencePush(g_vec_ref[0]);
        v_pos = LUA->Top();
        LUA->ReferencePush(g_vec_ref[1]);
        v_nrm = LUA->Top();
        if (LUA->IsType(v_pos, LT::Vector) && LUA->IsType(v_nrm, LT::Vector)) {
            w_pos = &const_cast<Vector &>(LUA->GetVector(v_pos));
            w_nrm = &const_cast<Vector &>(LUA->GetVector(v_nrm));
        }
    }
    uint64_t err0 = g_emit_errors;
    const bool want_nrm = rb.need_normal, want_uv = rb.need_uv;
    g_emit_saved += (uint64_t)nv * ((want_nrm ? 0u : 1u) + (want_uv ? 0u : 1u));
    for (size_t v = 0; v < nv; v++) {
        const float *p = &rb.pos[v * 3u], *n = &rb.nrm[v * 3u], *uv = &rb.uv[v * 2u];
        const uint8_t *col = &rb.col[v * 4u];
        LUA->Push(f_pos);
        if (w_pos) {
            w_pos->x = p[0];
            w_pos->y = p[1];
            w_pos->z = p[2];
            LUA->Push(v_pos);
        } else {
            Vector t;
            t.x = p[0];
            t.y = p[1];
            t.z = p[2];
            LUA->PushVector(t);
        }
        pcall0(LUA, 1);
        if (want_nrm) {
            LUA->Push(f_nrm);
            if (w_nrm) {
                w_nrm->x = n[0];
                w_nrm->y = n[1];
                w_nrm->z = n[2];
                LUA->Push(v_nrm);
            } else {
                Vector t;
                t.x = n[0];
                t.y = n[1];
                t.z = n[2];
                LUA->PushVector(t);
            }
            pcall0(LUA, 1);
        }
        if (want_uv) {
            LUA->Push(f_tc);
            LUA->PushNumber(0);
            LUA->PushNumber(uv[0]);
            LUA->PushNumber(uv[1]);
            pcall0(LUA, 3);
        }
        LUA->Push(f_col);
        LUA->PushNumber(col[0]);
        LUA->PushNumber(col[1]);
        LUA->PushNumber(col[2]);
        LUA->PushNumber(col[3]);
        pcall0(LUA, 4);
        LUA->Push(f_adv);
        pcall0(LUA, 0);
        if (g_emit_errors - err0 > 64) {
            break;      // something is wrong with the mesh library: stop wasting time (the builder pads the rest)
        }
    }
    LUA->Pop(LUA->Top() - base);
    if (g_emit_errors != err0) {
        return push_nil_msg(LUA, gsa1::format("mesh calls failed (%llu errors)", (unsigned long long)(g_emit_errors - err0)));
    }
    LUA->PushNumber((double)nv);
    return 1;
}
// gsa1.TextureArchives(kind) -> { {name=, count=}, ... } (entry i = archive i - 1; archive 0 = the model's) | nil, msg
GSA1_FN(gsa1_lua_TextureArchives)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t kind;
    if (!arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1)) {
        return push_nil_msg(LUA, "TextureArchives(kind)");
    }
    uint32_t na = g_session->texture_archives(kind);
    LUA->CreateTable();
    int t = LUA->Top();
    for (uint32_t a = 0; a < na; a++) {
        uint32_t n = 0;
        std::string err, name;
        g_session->texture_count(kind, a, n, err, &name);
        LUA->PushNumber(a + 1);
        LUA->CreateTable();
        int e = LUA->Top();
        raw_str(LUA, e, "name", name);
        raw_num(LUA, e, "count", n);
        LUA->RawSet(t);
    }
    return 1;
}

// gsa1.TextureCount(kind [, archive]) -> n | nil, message
GSA1_FN(gsa1_lua_TextureCount)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t kind, archive = 0;
    if (!arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1) ||
        (!LUA->IsType(2, LT::Nil) && !LUA->IsType(2, LT::None) && !arg_int(LUA, 2, archive, 0, 63))) {
        return push_nil_msg(LUA, "TextureCount(kind [, archive])");
    }
    uint32_t n = 0;
    std::string err;
    if (!g_session->texture_count(kind, (uint32_t)archive, n, err)) {
        return push_nil_msg(LUA, err);
    }
    LUA->PushNumber(n);
    return 1;
}

// gsa1.Texture(kind, index [, archive [, variant]]) -> {w, h, fmt, dfmt, alpha, name, runs, nruns, canary, cx, cy, cr, cg,
// cb, ca}
// runs: 10 bytes per run: u16 x, u16 y, u16 length, u8 r, g, b, a (little-endian); (0,0,0,0) pixels left out
// variant (0.9.4a, sadc docs/research/super2_plan.md 6.4 task 1 with its review R.6): absent or 0 = the texture; > 0 =
// libsa1's variant of it (sa1_texture_variant_get: gsa1.SUPER.TEXTURE_VARIANT_SUPER_GOLD 1 for SON_EFF lcharge01-04 of
// Sonic; nil + message for any other texture)
GSA1_FN(gsa1_lua_Texture)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t kind, index, archive = 0, variant = 0;
    if (!arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1) || !arg_int(LUA, 2, index, 0, 65535) ||
        (!LUA->IsType(3, LT::Nil) && !LUA->IsType(3, LT::None) && !arg_int(LUA, 3, archive, 0, 63)) ||
        (!LUA->IsType(4, LT::Nil) && !LUA->IsType(4, LT::None) && !arg_int(LUA, 4, variant, 0, 255))) {
        return push_nil_msg(LUA, "Texture(kind, index [, archive [, variant]])");
    }
    gsa1::TextureRuns tr;
    std::string err;
    if (!g_session->texture_runs(kind, (uint32_t)archive, (uint32_t)index, tr, err, (uint32_t)variant)) {
        return push_nil_msg(LUA, err);
    }
    LUA->CreateTable();
    int t = LUA->Top();
    raw_num(LUA, t, "w", tr.width);
    raw_num(LUA, t, "h", tr.height);
    raw_num(LUA, t, "fmt", tr.pixel_format);
    raw_num(LUA, t, "dfmt", tr.data_format);
    raw_num(LUA, t, "alpha", tr.alpha);
    raw_str(LUA, t, "name", tr.name);
    raw_str(LUA, t, "runs", tr.runs);
    raw_num(LUA, t, "nruns", tr.run_count);
    raw_bool(LUA, t, "canary", tr.has_canary);
    raw_num(LUA, t, "cx", tr.canary_x);
    raw_num(LUA, t, "cy", tr.canary_y);
    raw_num(LUA, t, "cr", tr.canary[0]);
    raw_num(LUA, t, "cg", tr.canary[1]);
    raw_num(LUA, t, "cb", tr.canary[2]);
    raw_num(LUA, t, "ca", tr.canary[3]);
    return 1;
}

// gsa1.TexturePixel(kind, archive, index, x, y) -> r, g, b, a | nil   (the decoded texel: in-game texture checks)
GSA1_FN(gsa1_lua_TexturePixel)
{
    int32_t kind, archive, index, x, y;
    uint8_t px[4];
    if (!g_session || !arg_int(LUA, 1, kind, 0, SA1_CHAR_COUNT - 1) || !arg_int(LUA, 2, archive, 0, 63) ||
        !arg_int(LUA, 3, index, 0, 65535) || !arg_int(LUA, 4, x, 0, 4095) || !arg_int(LUA, 5, y, 0, 4095) ||
        !g_session->texture_pixel(kind, (uint32_t)archive, (uint32_t)index, (uint32_t)x, (uint32_t)y, px)) {
        LUA->PushNil();
        return 1;
    }
    for (int k = 0; k < 4; k++) {
        LUA->PushNumber(px[k]);
    }
    return 4;
}

// ---- sound ------------------------------------------------------------------------------------------------------
namespace {

std::string g_audio_msg;          // the last finished open, for gsa1.AudioPoll
bool g_audio_msg_ok = false, g_audio_msg_new = false;

bool start_output(std::string &err)
{
    if (!g_out) {
        g_out = new gsa1::AudioOut();
    }
    g_out_retry = gsa1::now_ms();
    return g_out->start(gsa1::Audio::kRate, err);
}

void stop_output()
{
    if (g_out) {
        g_out->stop();
    }
}

}  // namespace

// the sound banks' worker finished: install them (and start the output); 1 opened, -1 failed, 0 nothing new
static int poll_audio_open(std::string &msg)
{
    if (!g_session) {
        return 0;
    }
    int r = g_session->poll_audio(msg);
    if (r > 0) {
        std::string oerr;
        bool out_ok = start_output(oerr);
        msg += "; output: " + (out_ok ? g_out->name() : oerr);
    }
    return r;
}

// gsa1.AudioOpen([japanese]) -> true, message | false, message, code
// The game's sound banks, voices and music from the disc (in memory) and a stereo mixer; the output is a push
// stream on Garry's Mod's own BASS (gsa1.AudioUpdate feeds it every frame). 0.5.1: the banks open on a worker thread
// (85 reads of the disc; the banks open now are closed there too) and this returns at once ("opening");
// gsa1.AudioPoll() reports when they are open; sounds start then.
GSA1_FN(gsa1_lua_AudioOpen)
{
    if (!g_session || !g_session->ready()) {
        return push_false_msg(LUA, "G-SA1 is not initialised: run gsa1.Init() first", "not_ready");
    }
    bool jp = LUA->IsType(1, LT::Bool) && LUA->GetBool(1);
    std::string err;
    if (!g_session->audio_open_async(jp, err)) {
        return push_false_msg(LUA, err);
    }
    std::string msg = gsa1::format("opening the sound banks on a worker thread (%s voices)", jp ? "Japanese" : "English");
    LUA->PushBool(true);
    LUA->PushString(msg.c_str());
    return 2;
}

// gsa1.AudioPoll() -> nil | true, message | false, message
// While the sound banks open: nil until they are; then once true, "sound banks opened in N ms ...; output: ..." or
// false, why. (gsa1.AudioUpdate installs them too; the message waits for this call.)
GSA1_FN(gsa1_lua_AudioPoll)
{
    std::string msg;
    int r = poll_audio_open(msg);
    if (r != 0) {
        g_audio_msg = msg;
        g_audio_msg_ok = r > 0;
        g_audio_msg_new = true;
    }
    if (!g_audio_msg_new) {
        LUA->PushNil();
        return 1;
    }
    g_audio_msg_new = false;
    LUA->PushBool(g_audio_msg_ok);
    LUA->PushString(g_audio_msg.c_str(), (unsigned int)g_audio_msg.size());
    return 2;
}

// gsa1.AudioClose()
GSA1_FN(gsa1_lua_AudioClose)
{
    stop_output();
    if (g_session) {
        g_session->audio_close();
    }
    return 0;
}

// gsa1.AudioSettings(master, sfx, voice, music, voices, jingles, bgm, voices3d [, no_stack]) -> true
// volumes 0..4 (1 = the game's level); voices / jingles / background music / other players' voices from their
// position: booleans. Switching a kind off stops what plays of it. no_stack (0.9.4a, sadc docs/research/super2_plan.md
// 10.3; absent: unchanged, the module's default true): a sound effect a character starts again while it still plays
// restarts instead of piling up (libsa1's SA1_AUDIO_MIX_RESTART_REPEATS: a fast ring line stays at one ring's level).
GSA1_FN(gsa1_lua_AudioSettings)
{
    if (!g_session) {
        LUA->PushBool(false);
        return 1;
    }
    gsa1::AudioOptions o = g_session->audio().options();
    double v;
    if (arg_number(LUA, 1, v)) o.master = (float)v;
    if (arg_number(LUA, 2, v)) o.sfx = (float)v;
    if (arg_number(LUA, 3, v)) o.voice = (float)v;
    if (arg_number(LUA, 4, v)) o.music = (float)v;
    if (LUA->IsType(5, LT::Bool)) o.voices = LUA->GetBool(5);
    if (LUA->IsType(6, LT::Bool)) o.jingles = LUA->GetBool(6);
    if (LUA->IsType(7, LT::Bool)) o.bgm = LUA->GetBool(7);
    if (LUA->IsType(8, LT::Bool)) o.voices_3d = LUA->GetBool(8);
    if (LUA->IsType(9, LT::Bool)) o.restart_repeats = LUA->GetBool(9);
    g_session->audio().apply(o);
    LUA->PushBool(true);
    return 1;
}

// gsa1.AudioUpdate(eyePos, forward, up, gameVolume, paused, frameTime) -> playing sounds
// Every frame: the listener, then mixes enough to keep about two frames (at least 60 ms; after a slow frame the slowest
// frame of the last 4 s x 1.25, up to 250 ms) queued in BASS's push queue.
// gameVolume (the `volume` ConVar) is applied unless Garry's Mod already scales BASS's streams itself.
GSA1_FN(gsa1_lua_AudioUpdate)
{
    if (g_session) {
        // installs banks that finished opening and reaps the workers that closed old ones (cheap when nothing is new)
        std::string msg;
        int r = poll_audio_open(msg);
        if (r != 0) {
            g_audio_msg = msg;
            g_audio_msg_ok = r > 0;
            g_audio_msg_new = true;
        }
    }
    if (!g_session || !g_session->audio().is_open()) {
        LUA->PushNumber(0);
        return 1;
    }
    gsa1::Audio &au = g_session->audio();
    float eye[3], fwd[3], up[3];
    double gv = 1.0, ft = 1.0 / 60.0;
    if (arg_vector(LUA, 1, eye) && arg_vector(LUA, 2, fwd) && arg_vector(LUA, 3, up)) {
        au.listener(eye, fwd, up);
    }
    arg_number(LUA, 4, gv);
    bool paused = LUA->IsType(5, LT::Bool) && LUA->GetBool(5);
    arg_number(LUA, 6, ft);
    if (!g_out || !g_out->running()) {
        std::string err;
        if (gsa1::now_ms() - g_out_retry < 5000.0 || !start_output(err)) {
            LUA->PushNumber(au.active());
            return 1;
        }
    }
    g_out->pause(paused);
    if (paused) {
        LUA->PushNumber(au.active());
        return 1;
    }
    int32_t gvol = g_out->global_stream_volume();
    double gain = (gvol < 0 || gvol == 10000) ? gv : 1.0;
    g_out->volume((float)std::max(0.0, std::min(1.0, gain)));
    // 0.9.2a (sadc docs/research/gsa1_091a_perf.md A0 + A2): the push queue alone against an adaptive lead (audio.hpp
    // OutputLead: two frames + 30 ms, and the slowest frame of the last 4 s x 1.25 + 20 ms, 60..250 ms)
    uint32_t frames = g_out->top_up(ft);
    if (frames > 0) {
        g_pcm.resize((size_t)frames * 2u);
        au.render(g_pcm.data(), frames);
        g_out->push(g_pcm.data(), frames);
    }
    LUA->PushNumber(au.active());
    return 1;
}

// gsa1.AudioStatus() -> table
GSA1_FN(gsa1_lua_AudioStatus)
{
    LUA->CreateTable();
    int t = LUA->Top();
    bool open = g_session && g_session->audio().is_open();
    raw_bool(LUA, t, "open", open);
    raw_bool(LUA, t, "opening", g_session && g_session->audio().opening());
    raw_num(LUA, t, "opening_ms", g_session ? g_session->audio().opening_ms() : 0.0);
    raw_str(LUA, t, "open_error", g_session ? g_session->scrub(g_session->audio().open_error()) : std::string());
    raw_bool(LUA, t, "japanese", open && g_session->audio().japanese());
    raw_bool(LUA, t, "output", g_out && g_out->running());
    raw_str(LUA, t, "backend", g_out ? g_out->name() : std::string("none"));
    raw_str(LUA, t, "error", g_out ? g_out->last_error() : std::string());
    raw_bool(LUA, t, "paused", g_out && g_out->paused());
    raw_num(LUA, t, "active", open ? g_session->audio().active() : 0);
    raw_num(LUA, t, "queued_ms", g_out ? g_out->queued_frames() * 1000.0 / gsa1::Audio::kRate : 0.0);
    // 0.9.2a: the lead the feed keeps queued and BASS's playback buffer (latency, not cushion)
    raw_num(LUA, t, "lead_ms", g_out ? g_out->lead_ms() : 0.0);
    raw_num(LUA, t, "playback_ms", g_out ? g_out->playback_frames() * 1000.0 / gsa1::Audio::kRate : 0.0);
    raw_num(LUA, t, "global_volume", g_out ? g_out->global_stream_volume() : -1);
    raw_num(LUA, t, "events", open ? (double)g_session->audio().sound_events() : 0.0);
    raw_num(LUA, t, "seconds", open ? (double)g_session->audio().frames_rendered() / gsa1::Audio::kRate : 0.0);
    raw_num(LUA, t, "underruns", g_out ? (double)g_out->underruns() : 0.0);
    raw_num(LUA, t, "open_ms", open ? g_session->audio().open_ms() : 0.0);
    // 0.9.4a: the rings' "no pile-up" option in effect (libsa1 has SA1_AUDIO_MIX_RESTART_REPEATS and it is on)
#if defined(SA1_AUDIO_MIX_RESTART_REPEATS)
    raw_bool(LUA, t, "no_stack", g_session && g_session->audio().options().restart_repeats);
#else
    raw_bool(LUA, t, "no_stack", false);
#endif
    sa1_audio_stats as;
    if (open && g_session->audio().stats(as)) {
        raw_bool(LUA, t, "loader_thread", as.loader_thread != 0);
        raw_bool(LUA, t, "preload_done", as.preload_done != 0);
        raw_num(LUA, t, "tones_decoded", as.tones_decoded);
        raw_num(LUA, t, "clips_cached", as.clips_cached);
        raw_num(LUA, t, "clips_waiting", as.clips_waiting);
        raw_num(LUA, t, "cache_mb", (double)as.cache_bytes / 1048576.0);
        raw_num(LUA, t, "clip_reads", as.clip_reads);
        raw_num(LUA, t, "clip_hits", as.clip_hits);
        raw_num(LUA, t, "read_errors", as.read_errors);
        raw_num(LUA, t, "caller_reads", as.caller_reads);
        raw_num(LUA, t, "cues_deferred", as.cues_deferred);
        raw_num(LUA, t, "cues_dropped", as.cues_dropped);
        raw_num(LUA, t, "max_read_ms", as.max_read_ms);
    }
    return 1;
}

// gsa1.PollEvents([out]) -> out = { {type, id, bank, x, y, z, arg, step, character}, ..., count = n }
// 0.6.0: a caller table is reused with its event tables (no garbage per frame): entries 1..count are this call's
// events and out[count + 1] is nil, so ipairs stops there; the event tables live in out.pool and are reused.
GSA1_FN(gsa1_lua_PollEvents)
{
    int t = out_table(LUA, 1);
    if (!g_session) {
        raw_num(LUA, t, "count", 0);
        LUA->PushNumber(1);
        LUA->PushNil();
        LUA->RawSet(t);
        return 1;
    }
    std::vector<sa1_event> ev;
    g_session->poll_events(ev);
    int n = 0;
    for (const sa1_event &e : ev) {
        if (e.type == SA1_EVENT_RUMBLE && g_pad) {
            gsa1::Character *c = g_session->get(e.character);
            if (c && !c->puppet) {
                g_pad->rumble_event(e.id, e.arg, now_s());   // id: power 1..7, arg: 1/60 s frames
            }
        }
        // the n-th event table of out.pool (made once), stored at out[n]
        LUA->PushString("pool");
        LUA->RawGet(t);
        if (!LUA->IsType(-1, LT::Table)) {
            LUA->Pop();
            LUA->CreateTable();
            LUA->PushString("pool");
            LUA->Push(-2);
            LUA->RawSet(t);
        }
        int pool = LUA->Top();
        int et = raw_subtable_i(LUA, pool, ++n);
        LUA->PushNumber(n);
        LUA->Push(et);
        LUA->RawSet(t);
        raw_num(LUA, et, "type", e.type);
        raw_num(LUA, et, "id", e.id);
        raw_num(LUA, et, "bank", e.bank);
        raw_num(LUA, et, "x", std::isfinite(e.position[0]) ? e.position[0] : 0.0);
        raw_num(LUA, et, "y", std::isfinite(e.position[1]) ? e.position[1] : 0.0);
        raw_num(LUA, et, "z", std::isfinite(e.position[2]) ? e.position[2] : 0.0);
        raw_num(LUA, et, "arg", e.arg);
        raw_num(LUA, et, "step", e.step);
        raw_num(LUA, et, "character", e.character);
        LUA->Pop(2);    // the event table and the pool
    }
    raw_num(LUA, t, "count", n);
    LUA->PushNumber(n + 1);
    LUA->PushNil();
    LUA->RawSet(t);
    return 1;
}

// gsa1.PollLog() -> { "line", ... }
GSA1_FN(gsa1_lua_PollLog)
{
    LUA->CreateTable();
    int t = LUA->Top();
    if (!g_session) {
        return 1;
    }
    int n = 0;
    for (const std::string &s : g_session->take_log()) {
        LUA->PushNumber(++n);
        LUA->PushString(s.c_str(), (unsigned int)s.size());
        LUA->RawSet(t);
    }
    return 1;
}

// ---- controller (XInput, read by the module itself) ---------------------------------------------------------------
// gsa1.PadSettings(t) -> true | false, message
// t = {enabled, index (0 automatic, 1..4), dead_left, dead_right, outer, trigger, cam_speed, cam_curve, invert_y,
//      dpad, rumble, rumble_strength, hold, map = {a=, b=, x=, y=, lb=, rb=, lt=, rt=, start=, back=, ls=, rs=}}
// (map values: gsa1.PAD_ACT_*). Fields left out keep their value; numbers are clamped into their ranges.
// Disabling the controller, switching rumble off or changing the index stops the motors.
GSA1_FN(gsa1_lua_PadSettings)
{
    if (!g_pad) {
        return push_false_msg(LUA, "the module failed to start");
    }
    if (!LUA->IsType(1, LT::Table)) {
        return push_false_msg(LUA, "PadSettings(table)");
    }
    const int t = 1;
    gsa1::PadSettings s = g_pad->settings();
    bool b;
    double d;
    if (raw_get_bool(LUA, t, "enabled", b)) s.enabled = b;
    if (raw_get_number(LUA, t, "index", d) && d == std::floor(d) && d >= 0.0 && d <= 4.0) s.slot = (int32_t)d - 1;
    if (raw_get_number(LUA, t, "dead_left", d)) s.dead_left = (float)d;
    if (raw_get_number(LUA, t, "dead_right", d)) s.dead_right = (float)d;
    if (raw_get_number(LUA, t, "outer", d)) s.outer = (float)d;
    if (raw_get_number(LUA, t, "trigger", d)) s.trigger = (float)d;
    if (raw_get_number(LUA, t, "cam_speed", d)) s.cam_speed = (float)d;
    if (raw_get_number(LUA, t, "cam_curve", d)) s.cam_curve = (float)d;
    if (raw_get_bool(LUA, t, "invert_y", b)) s.invert_y = b;
    if (raw_get_bool(LUA, t, "dpad", b)) s.dpad_moves = b;
    if (raw_get_bool(LUA, t, "rumble", b)) s.rumble = b;
    if (raw_get_number(LUA, t, "rumble_strength", d)) s.rumble_strength = (float)d;
    if (raw_get_number(LUA, t, "hold", d)) s.hold = (float)d;
    LUA->PushString("map");
    LUA->RawGet(t);
    if (LUA->IsType(-1, LT::Table)) {
        int m = LUA->Top();
        for (int32_t i = 0; i < gsa1::PAD_IN_COUNT; i++) {
            if (raw_get_number(LUA, m, gsa1::kPadInputNames[i], d)) {
                s.map[i] = d == std::floor(d) && d >= 0.0 && d < gsa1::PAD_ACT_COUNT ? (int32_t)d : gsa1::PAD_ACT_NONE;
            }
        }
    }
    LUA->Pop();
    g_pad->configure(s);
    LUA->PushBool(true);
    return 1;
}

// gsa1.PadPoll(dt, paused [, out]) -> out
// Once per frame: reads the controller (XInput is loaded by the first enabled poll) and maps it. dt: seconds of
// camera turning (0 while paused); paused: the motors stop. out = {available, enabled, connected, index (1..4, 0:
// none), input, active (priority over the keyboard), packet, lx, ly, rx, ry (-1..1, +y up), lt, rt (0..1), raw
// (gsa1.PAD_* held), pressed (since the last poll), sx, sy (the SA1 stick after the dead zone, +y forward), cx, cy
// (the right stick after its dead zone and curve), buttons (gsa1.BUTTON_*), yaw, pitch (degrees to add to the view:
// yaw + = left, pitch + = down), reset (camera reset pressed), rumble (low motor 0..1), rumble_high}
GSA1_FN(gsa1_lua_PadPoll)
{
    if (!g_pad) {
        LUA->PushNil();
        return 1;
    }
    double dt = 0.0;
    if (!arg_number(LUA, 1, dt)) {
        dt = 0.0;
    }
    bool paused = LUA->IsType(2, LT::Bool) && LUA->GetBool(2);
    const gsa1::PadFrame &f = g_pad->poll(now_s(), dt, paused);
    int t = out_table(LUA, 3);
    raw_bool(LUA, t, "available", f.available);
    raw_bool(LUA, t, "enabled", f.enabled);
    raw_bool(LUA, t, "connected", f.connected);
    raw_num(LUA, t, "index", f.slot + 1);
    raw_bool(LUA, t, "input", f.input);
    raw_bool(LUA, t, "active", f.active);
    raw_num(LUA, t, "packet", f.packet);
    raw_num(LUA, t, "lx", f.lx);
    raw_num(LUA, t, "ly", f.ly);
    raw_num(LUA, t, "rx", f.rx);
    raw_num(LUA, t, "ry", f.ry);
    raw_num(LUA, t, "lt", f.lt);
    raw_num(LUA, t, "rt", f.rt);
    raw_num(LUA, t, "raw", f.raw_buttons);
    raw_num(LUA, t, "pressed", f.pressed);
    raw_num(LUA, t, "sx", f.stick_x);
    raw_num(LUA, t, "sy", f.stick_y);
    raw_num(LUA, t, "cx", f.cam_x);
    raw_num(LUA, t, "cy", f.cam_y);
    raw_num(LUA, t, "buttons", f.sa1_buttons);
    raw_num(LUA, t, "yaw", f.look_yaw);
    raw_num(LUA, t, "pitch", f.look_pitch);
    raw_bool(LUA, t, "reset", f.cam_reset);
    raw_num(LUA, t, "rumble", f.rumble_low);
    raw_num(LUA, t, "rumble_high", f.rumble_high);
    return 1;
}

// gsa1.PadRumble(low, high, seconds) -> true | false, message   (both motors 0..1, at most 5 s; "Test rumble")
GSA1_FN(gsa1_lua_PadRumble)
{
    double lo, hi, sec;
    if (!g_pad || !arg_number(LUA, 1, lo) || !arg_number(LUA, 2, hi) || !arg_number(LUA, 3, sec)) {
        return push_false_msg(LUA, "PadRumble(low, high, seconds)");
    }
    if (!g_pad->settings().enabled) {
        return push_false_msg(LUA, "the controller is off");
    }
    if (!g_pad->settings().rumble) {
        return push_false_msg(LUA, "rumble is off");
    }
    if (!g_pad->frame().connected) {
        return push_false_msg(LUA, "no controller connected");
    }
    if (!g_pad->rumble((float)lo, (float)hi, sec, now_s())) {
        return push_false_msg(LUA, "PadRumble(low, high, seconds): seconds > 0");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.PadStatus() -> {enabled, available, backend, connected, index, slots (bit per connected slot), active,
//                      rumble (setting), rumble_low, rumble_high, polls}
GSA1_FN(gsa1_lua_PadStatus)
{
    LUA->CreateTable();
    int t = LUA->Top();
    if (!g_pad) {
        raw_bool(LUA, t, "enabled", false);
        raw_bool(LUA, t, "available", false);
        raw_str(LUA, t, "backend", "none");
        return 1;
    }
    const gsa1::PadFrame &f = g_pad->frame();
    raw_bool(LUA, t, "enabled", g_pad->settings().enabled);
    raw_bool(LUA, t, "available", f.available);
    raw_str(LUA, t, "backend", g_pad->backend());
    raw_bool(LUA, t, "connected", f.connected);
    raw_num(LUA, t, "index", f.slot + 1);
    raw_num(LUA, t, "slots", g_pad->connected_mask());
    raw_bool(LUA, t, "active", f.active);
    raw_bool(LUA, t, "rumble", g_pad->settings().rumble);
    raw_num(LUA, t, "rumble_low", f.rumble_low);
    raw_num(LUA, t, "rumble_high", f.rumble_high);
    raw_num(LUA, t, "polls", (double)g_pad->polls());
    return 1;
}

namespace {

struct Fn {
    const char *name;
    GarrysMod::Lua::CFunc fn;
};

void set_const(ILuaBase *L, int t, const char *k, double v)
{
    raw_num(L, t, k, v);
}

}  // namespace

GMOD_MODULE_OPEN()
{
    try {
        g_session = new gsa1::Session();
    } catch (...) {
        g_session = nullptr;
    }
    g_gmod_dir.clear();
    gsa1::garrysmod_dir_from_module(gsa1::self_module_path(), g_gmod_dir);
    try {
        g_pad = new gsa1::Controller();     // XInput is loaded by the first enabled poll, not here
    } catch (...) {
        g_pad = nullptr;
    }
    g_world_ok = false;
    g_world_map.clear();
    g_job = nullptr;
    g_retired_jobs.clear();
    g_world_prepared = false;
    g_prep_info = gsa1::PrepareResult();
    g_prep_note.clear();
    g_world_refused.clear();
    g_thin_wall = 16.0f;
    g_audio_msg.clear();
    g_audio_msg_new = false;
    g_map = gsa1::MapStats();
    g_map_full = g_map_from_cache = g_map_cache_written = false;
    g_map_cache_note.clear();
    g_map_props_note.clear();
    g_vec_mode = -1;
    g_vec_ref[0] = g_vec_ref[1] = -1;
    g_emit_calls = g_emit_errors = g_emit_saved = 0;

    static const Fn fns[] = {
        {"Init", gsa1_lua_Init},
        {"InitPoll", gsa1_lua_InitPoll},
        {"Shutdown", gsa1_lua_Shutdown},
        {"IsReady", gsa1_lua_IsReady},
        {"Status", gsa1_lua_Status},
        {"ChooseDisc", gsa1_lua_ChooseDisc},
        {"Characters", gsa1_lua_Characters},
        {"CharacterInfo", gsa1_lua_CharacterInfo},
        {"WorldLoad", gsa1_lua_WorldLoad},
        {"WorldLoadData", gsa1_lua_WorldLoadData},
        {"WorldInfo", gsa1_lua_WorldInfo},
        {"MapStart", gsa1_lua_MapStart},
        {"MapStartData", gsa1_lua_MapStartData},
        {"MapPoll", gsa1_lua_MapPoll},
        {"MapFeed", gsa1_lua_MapFeed},
        {"MapFeedFile", gsa1_lua_MapFeedFile},
        {"MapApply", gsa1_lua_MapApply},
        {"MapCancel", gsa1_lua_MapCancel},
        {"ShapeKnown", gsa1_lua_ShapeKnown},
        {"ShapePhy", gsa1_lua_ShapePhy},
        {"ShapeBox", gsa1_lua_ShapeBox},
        {"MoverUpdate", gsa1_lua_MoverUpdate},
        {"MoverForget", gsa1_lua_MoverForget},
        {"MoverCommit", gsa1_lua_MoverCommit},
        {"MoverStatus", gsa1_lua_MoverStatus},
        {"MoverOptions", gsa1_lua_MoverOptions},
        {"Upgrades", gsa1_lua_Upgrades},
        {"Create", gsa1_lua_Create},
        {"CreatePuppet", gsa1_lua_CreatePuppet},
        {"Destroy", gsa1_lua_Destroy},
        {"Tick", gsa1_lua_Tick},
        {"Pose", gsa1_lua_Pose},
        {"GetState", gsa1_lua_GetState},
        {"Render", gsa1_lua_Render},
        {"Batches", gsa1_lua_Batches},
        {"PrepareView", gsa1_lua_PrepareView},
        {"EmitBatch", gsa1_lua_EmitBatch},
        {"TextureArchives", gsa1_lua_TextureArchives},
        {"TextureCount", gsa1_lua_TextureCount},
        {"Texture", gsa1_lua_Texture},
        {"TexturePixel", gsa1_lua_TexturePixel},
        {"AudioOpen", gsa1_lua_AudioOpen},
        {"AudioPoll", gsa1_lua_AudioPoll},
        {"AudioClose", gsa1_lua_AudioClose},
        {"AudioSettings", gsa1_lua_AudioSettings},
        {"AudioUpdate", gsa1_lua_AudioUpdate},
        {"AudioStatus", gsa1_lua_AudioStatus},
        {"PollEvents", gsa1_lua_PollEvents},
        {"PollLog", gsa1_lua_PollLog},
        {"PadSettings", gsa1_lua_PadSettings},
        {"PadPoll", gsa1_lua_PadPoll},
        {"PadRumble", gsa1_lua_PadRumble},
        {"PadStatus", gsa1_lua_PadStatus},
    };
    LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    LUA->CreateTable();
    int t = LUA->Top();
    for (const Fn &f : fns) {
        LUA->PushString(f.name);
        LUA->PushCFunction(f.fn);
        LUA->RawSet(t);
    }
    raw_str(LUA, t, "VERSION", GSA1_MODULE_VERSION);
    set_const(LUA, t, "API_VERSION", GSA1_API_VERSION);
    raw_str(LUA, t, "LIBSA1_VERSION", sa1_version_string());
    set_const(LUA, t, "SCALE", 4.0);
    set_const(LUA, t, "CHAR_SONIC", SA1_CHAR_SONIC);
    set_const(LUA, t, "CHAR_TAILS", SA1_CHAR_TAILS);
    set_const(LUA, t, "CHAR_KNUCKLES", SA1_CHAR_KNUCKLES);
    set_const(LUA, t, "CHAR_AMY", SA1_CHAR_AMY);
    set_const(LUA, t, "CHAR_GAMMA", SA1_CHAR_GAMMA);
    set_const(LUA, t, "CHAR_BIG", SA1_CHAR_BIG);
    set_const(LUA, t, "CHAR_SUPER_SONIC", gsa1::kKindSuperSonic);     // 0.9.3 (feature "super": gsa1.SUPER)
    set_const(LUA, t, "BUTTON_JUMP", SA1_BUTTON_JUMP);
    set_const(LUA, t, "BUTTON_ACTION", SA1_BUTTON_ACTION);
    set_const(LUA, t, "BUTTON_ACTION2", SA1_BUTTON_ACTION2);
    set_const(LUA, t, "BUTTON_L", SA1_BUTTON_L);
    set_const(LUA, t, "BUTTON_R", SA1_BUTTON_R);
    set_const(LUA, t, "DRAW_BLEND", SA1_DRAW_BLEND);
    set_const(LUA, t, "DRAW_ALPHA_TEST", SA1_DRAW_ALPHA_TEST);
    set_const(LUA, t, "DRAW_DOUBLE_SIDED", SA1_DRAW_DOUBLE_SIDED);
    set_const(LUA, t, "DRAW_ENV_MAP", SA1_DRAW_ENV_MAP);
    set_const(LUA, t, "DRAW_UNLIT", SA1_DRAW_UNLIT);
    set_const(LUA, t, "DRAW_PALETTE_LIT", SA1_DRAW_PALETTE_LIT);
    set_const(LUA, t, "DRAW_EFFECT", SA1_DRAW_EFFECT);
    set_const(LUA, t, "DRAW_NO_TEXTURE", SA1_DRAW_NO_TEXTURE);
    set_const(LUA, t, "DRAW_AFTERIMAGE", SA1_DRAW_AFTERIMAGE);
    set_const(LUA, t, "DRAW_ADDITIVE", SA1_DRAW_ADDITIVE);
    set_const(LUA, t, "DRAW_USE_ALPHA", SA1_DRAW_USE_ALPHA);
    set_const(LUA, t, "DRAW_SHADOW", SA1_DRAW_SHADOW);
    set_const(LUA, t, "WRAP_CLAMP_U", gsa1::WRAP_CLAMP_U);
    set_const(LUA, t, "WRAP_CLAMP_V", gsa1::WRAP_CLAMP_V);
    set_const(LUA, t, "WRAP_POINT", gsa1::WRAP_POINT);
    set_const(LUA, t, "WRAP_GOLD", gsa1::WRAP_GOLD);    // 0.9.4a: draw the texture's golden variant (gsa1.Texture(.., 1))
    set_const(LUA, t, "TEXTURE_ALPHA_BINARY", SA1_TEXTURE_ALPHA_BINARY);
    set_const(LUA, t, "TEXTURE_ALPHA_BLEND", SA1_TEXTURE_ALPHA_BLEND);
    set_const(LUA, t, "STATE_ON_GROUND", SA1_STATE_ON_GROUND);
    set_const(LUA, t, "STATE_FAULTED", SA1_STATE_FAULTED);
    set_const(LUA, t, "SURFACE_WATER", SA1_SURFACE_WATER);
    set_const(LUA, t, "EVENT_SOUND", SA1_EVENT_SOUND);
    set_const(LUA, t, "EVENT_SOUND_STOP", SA1_EVENT_SOUND_STOP);
    set_const(LUA, t, "EVENT_VOICE", SA1_EVENT_VOICE);
    set_const(LUA, t, "EVENT_JINGLE", SA1_EVENT_JINGLE);
    set_const(LUA, t, "EVENT_RUMBLE", SA1_EVENT_RUMBLE);
    set_const(LUA, t, "EVENT_DEATH", SA1_EVENT_DEATH);
    set_const(LUA, t, "EVENT_RESTART", SA1_EVENT_RESTART);
    set_const(LUA, t, "EVENT_RESPAWN", SA1_EVENT_RESPAWN);
    set_const(LUA, t, "EVENT_MISSING_ACTION", SA1_EVENT_MISSING_ACTION);
    set_const(LUA, t, "EVENT_UNIMPLEMENTED", SA1_EVENT_UNIMPLEMENTED);
    set_const(LUA, t, "EVENT_CAPACITY", SA1_EVENT_CAPACITY);
    set_const(LUA, t, "EVENT_TIME_UP", SA1_EVENT_TIME_UP);
    set_const(LUA, t, "EVENT_FAULT", SA1_EVENT_FAULT);
    set_const(LUA, t, "CAPACITY_WINDOW_OBJECTS", SA1_CAPACITY_WINDOW_OBJECTS);
    set_const(LUA, t, "CAPACITY_WINDOW_POLYGONS", SA1_CAPACITY_WINDOW_POLYGONS);
    set_const(LUA, t, "CAPACITY_NEAR_OBJECTS", SA1_CAPACITY_NEAR_OBJECTS);
    set_const(LUA, t, "CAPACITY_MOVING_OBJECTS", SA1_CAPACITY_MOVING_OBJECTS);
    set_const(LUA, t, "CAPACITY_NEAR_POLYGONS", SA1_CAPACITY_NEAR_POLYGONS);
    set_const(LUA, t, "CAPACITY_MATRIX_STACK", SA1_CAPACITY_MATRIX_STACK);
    // 0.9.2 (sadc docs/research/gsa1_090_plan.md 6.10): the land-collision capacities of 092-lib-coll, the host flags of
    // the tick (WTR-A), whether libsa1 takes the host camera (0.9.4's sa1_input tail), the largest start ring count
#if defined(SA1_API_092)
    set_const(LUA, t, "CAPACITY_LAND_QUERY", SA1_CAPACITY_LAND_QUERY);
    set_const(LUA, t, "CAPACITY_LAND_HITS", SA1_CAPACITY_LAND_HITS);
    set_const(LUA, t, "INPUT_HOST_WATER_KNOWN", SA1_INPUT_HOST_WATER_KNOWN);
    set_const(LUA, t, "INPUT_HOST_IN_WATER", SA1_INPUT_HOST_IN_WATER);
#endif
    raw_bool(LUA, t, "TICK_HOST_FLAGS", gsa1::kHostFlagsKnown != 0u);
    raw_bool(LUA, t, "TICK_HOST_CAMERA", gsa1::kHostCameraInput);
    set_const(LUA, t, "START_RINGS_MAX", gsa1::kStartRingsMax);
    set_const(LUA, t, "PAD_ACT_NONE", gsa1::PAD_ACT_NONE);
    set_const(LUA, t, "PAD_ACT_JUMP", gsa1::PAD_ACT_JUMP);
    set_const(LUA, t, "PAD_ACT_ACTION", gsa1::PAD_ACT_ACTION);
    set_const(LUA, t, "PAD_ACT_ACTION2", gsa1::PAD_ACT_ACTION2);
    set_const(LUA, t, "PAD_ACT_L", gsa1::PAD_ACT_L);
    set_const(LUA, t, "PAD_ACT_R", gsa1::PAD_ACT_R);
    set_const(LUA, t, "PAD_ACT_CAM_LEFT", gsa1::PAD_ACT_CAM_LEFT);
    set_const(LUA, t, "PAD_ACT_CAM_RIGHT", gsa1::PAD_ACT_CAM_RIGHT);
    set_const(LUA, t, "PAD_ACT_CAM_RESET", gsa1::PAD_ACT_CAM_RESET);
    set_const(LUA, t, "PAD_ACT_COUNT", gsa1::PAD_ACT_COUNT);
    set_const(LUA, t, "PAD_DPAD_UP", gsa1::PAD_DPAD_UP);
    set_const(LUA, t, "PAD_DPAD_DOWN", gsa1::PAD_DPAD_DOWN);
    set_const(LUA, t, "PAD_DPAD_LEFT", gsa1::PAD_DPAD_LEFT);
    set_const(LUA, t, "PAD_DPAD_RIGHT", gsa1::PAD_DPAD_RIGHT);
    set_const(LUA, t, "PAD_START", gsa1::PAD_START);
    set_const(LUA, t, "PAD_BACK", gsa1::PAD_BACK);
    set_const(LUA, t, "PAD_LS", gsa1::PAD_LS);
    set_const(LUA, t, "PAD_RS", gsa1::PAD_RS);
    set_const(LUA, t, "PAD_LB", gsa1::PAD_LB);
    set_const(LUA, t, "PAD_RB", gsa1::PAD_RB);
    set_const(LUA, t, "PAD_A", gsa1::PAD_A);
    set_const(LUA, t, "PAD_B", gsa1::PAD_B);
    set_const(LUA, t, "PAD_X", gsa1::PAD_X);
    set_const(LUA, t, "PAD_Y", gsa1::PAD_Y);
    set_const(LUA, t, "PAD_LT", gsa1::PAD_LT);
    set_const(LUA, t, "PAD_RT", gsa1::PAD_RT);
    // the features (gsa1_feature.hpp): their functions, gsa1.FEATURES = {name = version}, gsa1.FEATURE_ERRORS
    gsa1::open_features(LUA, t);
    LUA->PushString("gsa1");
    LUA->Push(t);
    LUA->RawSet(-4);
    LUA->Pop(2);
    // how Vectors reach mesh.Position / mesh.Normal (EmitBatch) is decided here, not at the first EmitBatch, so the
    // session log's header (cl_log.lua) and the module line can say it (gsa1.Status().vector_mode)
    init_vectors(LUA);
    return 0;
}

GMOD_MODULE_CLOSE()
{
    gsa1::close_features(LUA);   // the features first (the jukebox's worker before the sound output), session alive
    drop_all_jobs();    // joins every worker still loading a map
    delete g_pad;       // motors off, XInput freed
    g_pad = nullptr;
    delete g_out;
    g_out = nullptr;
    delete g_session;
    g_session = nullptr;
    g_world_ok = false;
    g_world_map.clear();
    LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    LUA->PushString("gsa1");
    LUA->PushNil();
    LUA->RawSet(-3);
    LUA->Pop();
    return 0;
}
