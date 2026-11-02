// G-SA1 module: the feature "frontend" (round 0.9.8; sadc docs/research/gsa1_098_plan.md 5.5, 6.10 with its review R98.11, R98.20;
// charsel098.md 6.6; libsa1's SA1_API_FRONTEND). The Dreamcast's own Character Select, run by the game's own code from your disc in
// a private world; the addon's side is gsa1/feat/cl_charselect.lua. The core is src/core/frontend.{hpp,cpp}. No session patch.
//
// Lua API (feature version 1; GSA1.HasFeature("frontend", 1)). Flat like gsa1.HudScreen and gsa1.Preview*. Every function runs on
// the game's thread, never raises a Lua error; failures are `nil, message, code` with code "not_ready" (no disc, or no front end
// open: also after gsa1.Shutdown and the module's close), "open" (one is open already), "fault" (the game's code faulted: close it,
// the addon falls back to its simple chooser), "bad_argument".
//   gsa1.FrontendOpen({slot =, language =, dialog =}) -> true | nil, message, code
//       slot: the first selection 0..6 (default 0); language: 0 Japanese, 1 English (default); dialog true: the game's Game /
//       Instruction / Cancel dialog after a pick. Runs the menu's init and its 131 frames to the first drawn frame (about 40 ms)
//   gsa1.FrontendClose() -> true                  frees the world; the menu's textures stay
//   gsa1.FrontendTick(dt, sx, sy, buttons) -> frames | nil, message, code
//       whole frames of 1/60 s for dt (the rest kept; at most 8), the stick -1..1, gsa1.FRONTEND.LEFT.. held; a press goes to the
//       first of the frames
//   gsa1.FrontendState([out]) -> out {slot, slots, phase, frame, pose_frames, kind, faults} | nil, message, code
//       phase: 0 idle, 1 sliding, 2 dialog, 3 picked (the pose), 4 leaving; kind: SA1_CHAR_* of the selected slot, KIND for "?"
//   gsa1.FrontendEvents([out]) -> n, out {{kind =, id =}, ...} | nil, message, code
//       since the last call: kind "select" (the slide ended; id the slot), "pick" (the pose starts; the voice next frame), "done"
//       (the game's 300 frames ended), "cancel" (B), "music" (id: the track to play, -1: stop). SOUND and VOICE went to the mixer
//       already: non-positional, character 0. The music never does: the addon plays it on a jukebox channel (one source of it)
//   gsa1.FrontendScreen(out [, force]) -> generation, changed | nil, message, code
//       the 2D draws of the last frame in the layout of gsa1.HudScreen (out.d, out.v; out.w, out.h 640 x 480): SA1 draws, opaque
//       then blended, each by priority; a draw with priority above FRONTEND.PRI_3D is in front of the 3D
//   gsa1.FrontendRender() -> batches, generation, kind | nil, message, code     the selected slot's 3D, sorted into batches
//   gsa1.FrontendBatches([out]) -> count, out | nil                             as gsa1.Batches
//   gsa1.FrontendPrepareView(eye, right, up [, flip, vertexColor, linePixels, lit]) -> true | nil      as gsa1.PrepareView
//   gsa1.FrontendEmitBatch(b) -> vertices | nil, message                        as gsa1.EmitBatch (between mesh.Begin and mesh.End)
//   gsa1.FrontendView() -> eye (Vector), angles (Angle), fov | nil, message, code       the game's view in host space
//   gsa1.FrontendTextureArchives() -> list {{name =, count =}, ...} | nil, message, code   (the shape of gsa1.TextureArchives)
//   gsa1.FrontendTextureCount([archive]) -> n | nil, message
//   gsa1.FrontendTexture(index [, archive]) -> the table of gsa1.Texture | nil, message
//   gsa1.FrontendTexturePixel(archive, index, x, y) -> r, g, b, a | nil
//   gsa1.FrontendStats([out]) -> out {opens, closes, ticks, frames, sounds, voices, last_sound, last_voice, faults, open_ms, tick_ms,
//       tick_ms_max, last_error, open}
//   gsa1.FRONTEND = {KIND = 32, PRI_3D = -20, LEFT, RIGHT, UP, DOWN, A, B, START}
// gsa1.Texture and gsa1.TextureArchives keep their range checks (2.4 C2): the menu's textures come through these functions.
#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/frontend.hpp"
#include "../core/session.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

#if defined(GSA1_HAS_FRONTEND)

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;
namespace fe = gsa1::frontend;

namespace {

fe::Frontend g_fe;
std::vector<fe::Event> g_events;

const int kDrawStride = 11;      // gsa1.HudScreen's flat arrays
const int kSpriteStride = 15;
const int kVertexStride = 8;

// the open front end's session, bound to its context; nullptr: pushes nil, message, "not_ready" and sets ret
gsa1::Session *open_or(ILuaBase *L, int &ret)
{
    gsa1::Session *se = session();
    sa1_context *ctx = se && se->ready() ? se->ctx() : nullptr;
    g_fe.bind(ctx);
    if (!ctx) {
        ret = push_nil_msg(L, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
        return nullptr;
    }
    if (!g_fe.is_open()) {
        ret = push_nil_msg(L, "no front end is open (gsa1.FrontendOpen)", "not_ready");
        return nullptr;
    }
    return se;
}

const char *code_of(sa1_status st)
{
    switch (st) {
    case SA1_ERR_NOT_LOADED:
    case SA1_ERR_NOT_FOUND:
        return "not_ready";
    case SA1_ERR_LIMIT:
        return "open";
    case SA1_ERR_GAME_FAULT:
    case SA1_ERR_NOT_IMPLEMENTED:
        return "fault";
    case SA1_ERR_INVALID_ARGUMENT:
        return "bad_argument";
    case SA1_ERR_UNSUPPORTED:
        return "unsupported";
    default:
        return sa1_status_string(st);
    }
}

int fail(ILuaBase *L, sa1_status st, const std::string &err)
{
    return push_nil_msg(L, scrubbed(err), code_of(st));
}

// t[k] (string key, rawget) when it is a table, else a new table stored there; returns its absolute index
int raw_subtable_s(ILuaBase *L, int t, const char *k)
{
    L->PushString(k);
    L->RawGet(t);
    if (!L->IsType(-1, LT::Table)) {
        L->Pop();
        L->CreateTable();
        L->PushString(k);
        L->Push(-2);
        L->RawSet(t);
    }
    return L->Top();
}

inline void set_i(ILuaBase *L, int t, int i, double v)
{
    L->PushNumber(i);
    L->PushNumber(v);
    L->RawSet(t);
}

bool absent(ILuaBase *L, int i)
{
    return L->IsType(i, LT::Nil) || L->IsType(i, LT::None);
}

void push_vector(ILuaBase *L, const float v[3])
{
    Vector t;
    t.x = v[0];
    t.y = v[1];
    t.z = v[2];
    L->PushVector(t);
}

void push_angle(ILuaBase *L, const float a[3])
{
    QAngle t;
    t.x = a[0];
    t.y = a[1];
    t.z = a[2];
    L->PushAngle(t);
}

}  // namespace

// gsa1.FrontendOpen({slot =, language =, dialog =}) -> true | nil, message, code
GSA1_FN(gsa1_frontend_FrontendOpen)
{
    static const char *usage = "FrontendOpen({slot = 0..6, language = 0 | 1, dialog = boolean})";
    int32_t slot = 0, language = 1;
    bool dialog = false;
    if (!absent(LUA, 1)) {
        if (!LUA->IsType(1, LT::Table)) {
            return push_nil_msg(LUA, usage, "bad_argument");
        }
        int t = absidx(LUA, 1);
        double v = 0.0;
        if (raw_get_number(LUA, t, "slot", v)) {
            if (v != std::floor(v) || v < 0.0 || v > 6.0) {
                return push_nil_msg(LUA, usage, "bad_argument");
            }
            slot = (int32_t)v;
        }
        if (raw_get_number(LUA, t, "language", v)) {
            if (v != 0.0 && v != 1.0) {
                return push_nil_msg(LUA, usage, "bad_argument");
            }
            language = (int32_t)v;
        }
        raw_get_bool(LUA, t, "dialog", dialog);
    }
    gsa1::Session *se = session();
    if (!se || !se->ready() || !se->ctx()) {
        return push_nil_msg(LUA, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
    }
    std::string err;
    sa1_status st = g_fe.open(*se, slot, language, dialog, err);
    if (st != SA1_OK) {
        return fail(LUA, st, err);
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.FrontendClose() -> true
GSA1_FN(gsa1_frontend_FrontendClose)
{
    g_fe.close();
    LUA->PushBool(true);
    return 1;
}

// gsa1.FrontendTick(dt, sx, sy, buttons) -> frames | nil, message, code
GSA1_FN(gsa1_frontend_FrontendTick)
{
    double dt = 0.0, sx = 0.0, sy = 0.0;
    int32_t buttons = 0;
    if (!arg_number(LUA, 1, dt) || dt < 0.0 || !arg_number(LUA, 2, sx) || !arg_number(LUA, 3, sy) ||
        !arg_int(LUA, 4, buttons, 0, 255)) {
        return push_nil_msg(LUA, "FrontendTick(dt >= 0, sx, sy, buttons 0..255)", "bad_argument");
    }
    int ret = 0;
    if (!open_or(LUA, ret)) {
        return ret;
    }
    std::string err;
    uint32_t frames = 0;
    sa1_status st = g_fe.tick((float)std::min(dt, 1.0), (float)std::max(-1.0, std::min(1.0, sx)),
                              (float)std::max(-1.0, std::min(1.0, sy)), (uint32_t)buttons, frames, err);
    if (st != SA1_OK) {
        return fail(LUA, st, err);
    }
    LUA->PushNumber(frames);
    return 1;
}

// gsa1.FrontendState([out]) -> out | nil, message, code
GSA1_FN(gsa1_frontend_FrontendState)
{
    int ret = 0;
    if (!open_or(LUA, ret)) {
        return ret;
    }
    sa1_frontend_state s;
    std::string err;
    sa1_status st = g_fe.state(s, err);
    if (st != SA1_OK) {
        return fail(LUA, st, err);
    }
    int t = out_table(LUA, 1);
    raw_num(LUA, t, "slot", s.slot);
    raw_num(LUA, t, "slots", s.slots);
    raw_num(LUA, t, "phase", s.phase);
    raw_num(LUA, t, "frame", s.frame);
    raw_num(LUA, t, "pose_frames", s.pose_frames);
    raw_num(LUA, t, "kind", s.kind);
    raw_num(LUA, t, "faults", s.faults);
    return 1;
}

// gsa1.FrontendEvents([out]) -> n, out | nil, message, code
GSA1_FN(gsa1_frontend_FrontendEvents)
{
    int ret = 0;
    gsa1::Session *se = open_or(LUA, ret);
    if (!se) {
        return ret;
    }
    std::string err;
    sa1_status st = g_fe.events(&se->audio(), g_events, err);
    if (st != SA1_OK) {
        return fail(LUA, st, err);
    }
    int t = out_table(LUA, 1);
    int n = 0;
    for (const fe::Event &e : g_events) {
        n++;
        int et = raw_subtable_i(LUA, t, n);
        raw_str(LUA, et, "kind", fe::event_name(e.kind));
        raw_num(LUA, et, "id", e.id);
        LUA->Pop();
    }
    raw_num(LUA, t, "count", n);
    LUA->PushNumber(n);
    LUA->Push(t);
    return 2;
}

// gsa1.FrontendScreen(out [, force]) -> generation, changed | nil, message, code
GSA1_FN(gsa1_frontend_FrontendScreen)
{
    if (!LUA->IsType(1, LT::Table)) {
        return push_nil_msg(LUA, "FrontendScreen(out [, force])", "bad_argument");
    }
    int ret = 0;
    if (!open_or(LUA, ret)) {
        return ret;
    }
    const sa1_screen *scr = nullptr;
    std::string err;
    sa1_status st = g_fe.screen(scr, err);
    if (st != SA1_OK) {
        return fail(LUA, st, err);
    }
    int t = absidx(LUA, 1);
    bool force = LUA->IsType(2, LT::Bool) && LUA->GetBool(2);
    double old_gen = -1.0;
    if (!force && raw_get_number(LUA, t, "gen", old_gen) && old_gen == (double)scr->generation) {
        LUA->PushNumber(scr->generation);
        LUA->PushBool(false);
        return 2;
    }
    uint32_t nd = scr->draws ? scr->num_draws : 0u;
    uint32_t ns = scr->sprites ? scr->num_sprites : 0u;
    uint32_t nv = scr->vertices ? scr->num_vertices : 0u;
    raw_num(LUA, t, "gen", scr->generation);
    raw_num(LUA, t, "w", scr->width);
    raw_num(LUA, t, "h", scr->height);
    raw_num(LUA, t, "nd", nd);
    raw_num(LUA, t, "ns", ns);
    raw_num(LUA, t, "nv", nv);
    int td = raw_subtable_s(LUA, t, "d");
    for (uint32_t i = 0; i < nd; i++) {
        const sa1_screen_draw &d = scr->draws[i];
        int k = (int)i * kDrawStride;
        set_i(LUA, td, k + 1, d.prim);
        set_i(LUA, td, k + 2, d.first);
        set_i(LUA, td, k + 3, d.count);
        set_i(LUA, td, k + 4, d.archive);
        set_i(LUA, td, k + 5, d.texture);
        set_i(LUA, td, k + 6, d.flags);
        set_i(LUA, td, k + 7, d.blend_src);
        set_i(LUA, td, k + 8, d.blend_dst);
        set_i(LUA, td, k + 9, std::isfinite(d.priority) ? d.priority : 0.0);
        set_i(LUA, td, k + 10, d.part);
        set_i(LUA, td, k + 11, d.source);
    }
    LUA->Pop();
    int ts = raw_subtable_s(LUA, t, "s");
    for (uint32_t i = 0; i < ns; i++) {
        const sa1_screen_sprite &s = scr->sprites[i];
        int k = (int)i * kSpriteStride;
        const float f[11] = {s.rect[0], s.rect[1], s.rect[2], s.rect[3], s.pivot[0], s.pivot[1], s.angle,
                             s.uv[0],   s.uv[1],   s.uv[2],   s.uv[3]};
        for (int j = 0; j < 11; j++) {
            set_i(LUA, ts, k + 1 + j, std::isfinite(f[j]) ? (double)f[j] : 0.0);
        }
        for (int j = 0; j < 4; j++) {
            set_i(LUA, ts, k + 12 + j, s.color[j]);
        }
    }
    LUA->Pop();
    int tv = raw_subtable_s(LUA, t, "v");
    for (uint32_t i = 0; i < nv; i++) {
        const sa1_screen_vertex &v = scr->vertices[i];
        int k = (int)i * kVertexStride;
        const float f[4] = {v.x, v.y, v.u, v.v};
        for (int j = 0; j < 4; j++) {
            set_i(LUA, tv, k + 1 + j, std::isfinite(f[j]) ? (double)f[j] : 0.0);
        }
        for (int j = 0; j < 4; j++) {
            set_i(LUA, tv, k + 5 + j, v.color[j]);
        }
    }
    LUA->Pop();
    LUA->PushNumber(scr->generation);
    LUA->PushBool(true);
    return 2;
}

// gsa1.FrontendRender() -> batches, generation, kind | nil, message, code
GSA1_FN(gsa1_frontend_FrontendRender)
{
    int ret = 0;
    gsa1::Session *se = open_or(LUA, ret);
    if (!se) {
        return ret;
    }
    std::string err;
    int32_t kind = 0;
    sa1_status st = g_fe.render(*se, kind, err);
    if (st != SA1_OK) {
        return fail(LUA, st, err);
    }
    const gsa1::Character &c = g_fe.holder();
    LUA->PushNumber(c.batch_count);
    LUA->PushNumber(c.r_gen);
    LUA->PushNumber(kind);
    return 3;
}

// gsa1.FrontendBatches([out]) -> count, out | nil
GSA1_FN(gsa1_frontend_FrontendBatches)
{
    if (!g_fe.is_open()) {
        LUA->PushNil();
        return 1;
    }
    const gsa1::Character *c = &g_fe.holder();
    int t = out_table(LUA, 1);
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
    for (int b = (int)c->batch_count + 1; b <= (int)c->batch_count + 8; b++) {
        LUA->PushNumber(b);
        LUA->PushNil();
        LUA->RawSet(t);
    }
    LUA->PushNumber(c->batch_count);
    LUA->Push(t);
    return 2;
}

// gsa1.FrontendPrepareView(eye, right, up [, flip, vertexColor, linePixels, lit]) -> true | nil
GSA1_FN(gsa1_frontend_FrontendPrepareView)
{
    float eye[3], right[3], up[3];
    gsa1::Session *se = session();
    if (!g_fe.is_open() || !se || !arg_vector(LUA, 1, eye) || !arg_vector(LUA, 2, right) || !arg_vector(LUA, 3, up)) {
        LUA->PushNil();
        return 1;
    }
    gsa1::ViewOptions o;
    o.flip = LUA->IsType(4, LT::Bool) && LUA->GetBool(4);
    o.vertex_color = !LUA->IsType(5, LT::Bool) || LUA->GetBool(5);
    double lp;
    if (arg_number(LUA, 6, lp)) {
        o.line_pixels = (float)std::max(0.5, std::min(16.0, lp));
    }
    o.lit = !LUA->IsType(7, LT::Bool) || LUA->GetBool(7);
    se->prepare_view(g_fe.holder(), eye, right, up, o);
    LUA->PushBool(true);
    return 1;
}

// gsa1.FrontendEmitBatch(b) -> vertices | nil, message
GSA1_FN(gsa1_frontend_FrontendEmitBatch)
{
    int32_t b = 0;
    if (!g_fe.is_open() || !arg_int(LUA, 1, b, 1, 65535) || (uint32_t)b > g_fe.holder().batch_count) {
        return push_nil_msg(LUA, "FrontendEmitBatch(batch)", "bad_argument");
    }
    return emit_batch(LUA, g_fe.holder(), b);
}

// gsa1.FrontendView() -> eye (Vector), angles (Angle), fov | nil, message, code
GSA1_FN(gsa1_frontend_FrontendView)
{
    int ret = 0;
    if (!open_or(LUA, ret)) {
        return ret;
    }
    float eye[3], forward[3], up[3], fov = 0.0f, ang[3];
    std::string err;
    sa1_status st = g_fe.view(eye, forward, up, fov, err);
    if (st != SA1_OK) {
        return fail(LUA, st, err);
    }
    fe::view_angles(forward, up, ang);
    push_vector(LUA, eye);
    push_angle(LUA, ang);
    LUA->PushNumber(fov);
    return 3;
}

// gsa1.FrontendTextureArchives() -> list {{name =, count =}, ...} | nil, message, code   (the shape of gsa1.TextureArchives)
GSA1_FN(gsa1_frontend_FrontendTextureArchives)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    gsa1::Session *se = session();
    LUA->CreateTable();
    int t = LUA->Top();
    for (uint32_t a = 0; a < 64u; a++) {
        uint32_t n = 0;
        std::string err, name;
        if (!se->texture_count(SA1_KIND_FRONTEND, a, n, err, &name)) {
            break;
        }
        LUA->PushNumber(a + 1);
        LUA->CreateTable();
        int e = LUA->Top();
        raw_str(LUA, e, "name", name);
        raw_num(LUA, e, "count", n);
        LUA->RawSet(t);
    }
    return 1;
}

// gsa1.FrontendTextureCount([archive]) -> n | nil, message
GSA1_FN(gsa1_frontend_FrontendTextureCount)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t archive = 0;
    if (!absent(LUA, 1) && !arg_int(LUA, 1, archive, 0, 63)) {
        return push_nil_msg(LUA, "FrontendTextureCount([archive])", "bad_argument");
    }
    uint32_t n = 0;
    std::string err;
    if (!session()->texture_count(SA1_KIND_FRONTEND, (uint32_t)archive, n, err)) {
        return push_nil_msg(LUA, err);
    }
    LUA->PushNumber(n);
    return 1;
}

// gsa1.FrontendTexture(index [, archive]) -> {w, h, fmt, dfmt, alpha, name, runs, nruns, canary, cx, cy, cr, cg, cb, ca} | nil, message
GSA1_FN(gsa1_frontend_FrontendTexture)
{
    int ret;
    if (!ready_or(LUA, ret)) {
        return ret;
    }
    int32_t index = 0, archive = 0;
    if (!arg_int(LUA, 1, index, 0, 65535) || (!absent(LUA, 2) && !arg_int(LUA, 2, archive, 0, 63))) {
        return push_nil_msg(LUA, "FrontendTexture(index [, archive])", "bad_argument");
    }
    gsa1::TextureRuns tr;
    std::string err;
    if (!session()->texture_runs(SA1_KIND_FRONTEND, (uint32_t)archive, (uint32_t)index, tr, err)) {
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

// gsa1.FrontendTexturePixel(archive, index, x, y) -> r, g, b, a | nil
GSA1_FN(gsa1_frontend_FrontendTexturePixel)
{
    int32_t archive, index, x, y;
    uint8_t px[4];
    gsa1::Session *se = session();
    if (!se || !arg_int(LUA, 1, archive, 0, 63) || !arg_int(LUA, 2, index, 0, 65535) || !arg_int(LUA, 3, x, 0, 4095) ||
        !arg_int(LUA, 4, y, 0, 4095) ||
        !se->texture_pixel(SA1_KIND_FRONTEND, (uint32_t)archive, (uint32_t)index, (uint32_t)x, (uint32_t)y, px)) {
        LUA->PushNil();
        return 1;
    }
    for (int k = 0; k < 4; k++) {
        LUA->PushNumber(px[k]);
    }
    return 4;
}

// gsa1.FrontendStats([out]) -> out
GSA1_FN(gsa1_frontend_FrontendStats)
{
    int t = out_table(LUA, 1);
    const fe::Stats &s = g_fe.stats();
    raw_num(LUA, t, "opens", (double)s.opens);
    raw_num(LUA, t, "closes", (double)s.closes);
    raw_num(LUA, t, "ticks", (double)s.ticks);
    raw_num(LUA, t, "frames", (double)s.frames);
    raw_num(LUA, t, "sounds", (double)s.sounds);
    raw_num(LUA, t, "voices", (double)s.voices);
    raw_num(LUA, t, "last_sound", (double)s.last_sound);
    raw_num(LUA, t, "last_voice", (double)s.last_voice);
    raw_num(LUA, t, "faults", (double)s.faults);
    raw_num(LUA, t, "open_ms", s.open_ms);
    raw_num(LUA, t, "tick_ms", s.tick_ms_last);
    raw_num(LUA, t, "tick_ms_max", s.tick_ms_max);
    raw_str(LUA, t, "last_error", scrubbed(s.last_error));
    raw_bool(LUA, t, "open", g_fe.is_open());
    return 1;
}

namespace {

void frontend_open_hook(ILuaBase *L, int t)
{
    L->PushString("FRONTEND");
    L->CreateTable();
    int c = L->Top();
    raw_num(L, c, "KIND", SA1_KIND_FRONTEND);
    raw_num(L, c, "PRI_3D", SA1_FRONTEND_3D_PRIORITY);
    raw_num(L, c, "LEFT", SA1_FRONTEND_B_LEFT);
    raw_num(L, c, "RIGHT", SA1_FRONTEND_B_RIGHT);
    raw_num(L, c, "UP", SA1_FRONTEND_B_UP);
    raw_num(L, c, "DOWN", SA1_FRONTEND_B_DOWN);
    raw_num(L, c, "A", SA1_FRONTEND_B_A);
    raw_num(L, c, "B", SA1_FRONTEND_B_B);
    raw_num(L, c, "START", SA1_FRONTEND_B_START);
    raw_num(L, c, "SLOTS", SA1_FRONTEND_SLOTS);
    L->RawSet(t);
}

// libsa1 closes an open front end with the context and with the disc (R98.20): the pointer goes first, and afterwards every call
// answers "not_ready"
void frontend_shutdown()
{
    g_fe.close();
}

void frontend_close_hook(ILuaBase *)
{
    frontend_shutdown();
}

const gsa1::FeatureFn k_frontend_fns[] = {
    {"FrontendOpen", gsa1_frontend_FrontendOpen},
    {"FrontendClose", gsa1_frontend_FrontendClose},
    {"FrontendTick", gsa1_frontend_FrontendTick},
    {"FrontendState", gsa1_frontend_FrontendState},
    {"FrontendEvents", gsa1_frontend_FrontendEvents},
    {"FrontendScreen", gsa1_frontend_FrontendScreen},
    {"FrontendRender", gsa1_frontend_FrontendRender},
    {"FrontendBatches", gsa1_frontend_FrontendBatches},
    {"FrontendPrepareView", gsa1_frontend_FrontendPrepareView},
    {"FrontendEmitBatch", gsa1_frontend_FrontendEmitBatch},
    {"FrontendView", gsa1_frontend_FrontendView},
    {"FrontendTextureArchives", gsa1_frontend_FrontendTextureArchives},
    {"FrontendTextureCount", gsa1_frontend_FrontendTextureCount},
    {"FrontendTexture", gsa1_frontend_FrontendTexture},
    {"FrontendTexturePixel", gsa1_frontend_FrontendTexturePixel},
    {"FrontendStats", gsa1_frontend_FrontendStats},
};

}  // namespace

GSA1_FEATURE(frontend, 1, k_frontend_fns, frontend_open_hook, frontend_close_hook, gsa1::kCloseDefault);
GSA1_FEATURE_ON_SHUTDOWN(frontend, frontend_shutdown);

#endif  // GSA1_HAS_FRONTEND (a libsa1 without the front end: no feature "frontend"; the addon keeps its simple chooser)
