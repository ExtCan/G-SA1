// G-SA1 module: the feature "preview" (round 0.9.4b; sadc docs/research/objects2_plan.md 6.3 task 2 with its Review R.5 /
// R.8; libsa1's object previews, SA1_API_PREVIEW). The game's own rings, ring groups and item boxes without a character:
// libsa1 runs one live copy per description in a private playerless world of a character kind (the "showcase") and returns
// each copy's draws in OBJECT SPACE - host units and axes, origin = where the object stands. The Lua side
// (feat/cl_objview.lua: the pictures of the objects on the map; feat/cl_objicons.lua: the spawn-menu pictures) draws them
// through the same batch / material / mesh path as a character (cl_render.lua). The core is src/core/preview.{hpp,cpp}.
//
// Lua API (feature version 1; GSA1.HasFeature("preview", 1)). Units: Hammer units and degrees. Every function runs on the
// game's thread, never raises a Lua error; failures are `nil, message, code` with code "not_ready" (no disc),
// "bad_argument", "unsupported" (a kind without a showcase - Eggman 1, Tikal 4, Super Sonic 8: use Sonic's 0 - or a type
// the showcase cannot run), "limit" (256 copies of a kind, or the showcase's capture or heap is full; an O_GRING layout
// reaching beyond 990 SA1 units), "fault" (the kind's showcase faulted: PreviewClear, then add again), "not_found" (an
// unknown id: a disc reload frees every copy - add it again).
//   gsa1.PreviewTypes([out]) -> out {[type] = {type, available, rotation, settle}} | nil, message, code
//       rotation: gsa1.PREVIEW.ROT_NONE (ITEMBOX: drawn upright), ROT_OUTER (RING: only its yaw, the spin's start - G-SA1
//       ignores it; ITEMBOX_AIR: the record's full rotation is the host's model matrix), ROT_INNER (O_GRING: part of the
//       description); settle: 60 Hz steps until a new copy looks settled (ITEMBOX 47, ITEMBOX_AIR 23: the grow-in)
//   gsa1.PreviewAdd({kind =, type =, params = {p1, p2, p3}, rotation = {9} | nil, state =, user_bits =}) -> id | nil, msg,
//       code      a copy (params as the SET record's: SA1 units; RING (0, 0, 0) only; state PRESENT [| BROKEN]); the
//       same description twice gives two copies (the addon shares them)
//   gsa1.PreviewRemove(id) -> true | false, message, code
//   gsa1.PreviewClear() -> count                 every copy; libsa1 frees every showcase now (the way out of a fault)
//   gsa1.PreviewTick(dt) -> true | nil, message, code      the showcases' whole pairs for dt seconds (keep calling it
//       about 3 s after the last remove: libsa1 frees an empty showcase 60 pairs later)
//   gsa1.PreviewRender(id [, alpha]) -> batches, generation, batchGen, changed | nil, message, code
//       the copy's draws sorted into batches as gsa1.Render does a character's. alpha (default 1): >= 1 the last pair as
//       it is (the game's 30 Hz; nothing is copied when the copy ran no new pair since: changed false), < 0 libsa1's
//       accumulator (smoothed), 0..1 a vertex lerp between its last two pairs. generation: the copy's pair count
//   gsa1.PreviewBatches(id [, out]) -> count, out | nil   as gsa1.Batches (key, pass, archive, tex, flags, all, src, dst,
//       mat, wrap, tris, order, source, prims; gen, count, triangles)
//   gsa1.PreviewPrepareView(id, eye, right, up [, flip, vertexColor, linePixels, lit]) -> true | nil
//       as gsa1.PrepareView, the eye and axes in the copy's OBJECT space (sprites and lines face it, sphere maps follow it)
//   gsa1.PreviewEmitBatch(id, b) -> vertices | nil, message    as gsa1.EmitBatch (between mesh.Begin and mesh.End)
//   gsa1.PreviewInfo(id) -> steps, settled, minx, miny, minz, maxx, maxy, maxz, draws, triangles | nil, message, code
//       the copy's 60 Hz steps, whether it is settled (its type's settle steps), the bounds of its last pair's draws (HU,
//       object space; zero: none)
//   gsa1.PreviewRingPlaces(kind, type, ang, p1, p2, p3 [, out]) -> n, out {x1, y1, z1, record1, bit1, ...} | nil, msg, code
//       review R.5: the ENTITY's description as gsa1.SetAdd takes it (type gsa1.OBJECTS.O_GRING, its Angle, p1 rings, p2
//       spacing / radius in HU, p3 0 line / 1 circle; a RING: its own place), split into the game's records exactly as
//       SetAdd splits it (objects.cpp make_records) and each record's rings placed by the game's own layout in kind's
//       showcase: HU relative to the entity's position, host axes; record = 0 .. records - 1, bit = the ring's bit in that
//       record's user flag. A ring of the game's group is a RING drawn at its place with no rotation (angle 0)
//   gsa1.PreviewStats([out]) -> out {copies, adds, removes, clears, renders, skipped, ticks, faults, forgets, tick_ms,
//       tick_ms_max, last_error}
//   gsa1.PREVIEW = {ROT_NONE, ROT_OUTER, ROT_INNER, MAX, IDLE_PAIRS}
#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/objects.hpp"
#include "../core/preview.hpp"
#include "../core/session.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

#if defined(GSA1_HAS_PREVIEW)

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;
namespace pv = gsa1::preview;

namespace {

pv::Previews g_pv;
std::vector<pv::Place> g_places;

// the session's context when the disc is loaded (the copies bound to it), else nullptr
sa1_context *ready_ctx()
{
    gsa1::Session *se = session();
    sa1_context *ctx = se && se->ready() ? se->ctx() : nullptr;
    g_pv.bind(ctx);
    return ctx;
}

int not_ready(ILuaBase *L)
{
    return push_nil_msg(L, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
}

// n numbers of the array table at absolute index t (out[0..n-1]); false when one is missing or not finite
bool number_array(ILuaBase *L, int t, int n, float *out, double lim)
{
    for (int i = 0; i < n; i++) {
        L->PushNumber(i + 1);
        L->RawGet(t);
        bool ok = L->IsType(-1, LT::Number);
        double v = ok ? L->GetNumber(-1) : 0.0;
        L->Pop();
        if (!ok || !std::isfinite(v) || std::fabs(v) > lim) {
            return false;
        }
        out[i] = (float)v;
    }
    return true;
}

// t[k] as an array of n numbers (absent: false with present = false)
bool field_array(ILuaBase *L, int t, const char *k, int n, float *out, bool &present)
{
    L->PushString(k);
    L->RawGet(t);
    present = !L->IsType(-1, LT::Nil);
    bool ok = false;
    if (L->IsType(-1, LT::Table)) {
        ok = number_array(L, L->Top(), n, out, 1.0e6);
    }
    L->Pop();
    return ok;
}

pv::Copy *copy_arg(ILuaBase *L, int i)
{
    int32_t id = 0;
    if (!arg_int(L, i, id, 1, 2147483647.0)) {
        return nullptr;
    }
    ready_ctx();
    return g_pv.find((uint32_t)id);
}

}  // namespace

// gsa1.PreviewTypes([out]) -> out | nil, message, code
GSA1_FN(gsa1_preview_PreviewTypes)
{
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
    int t = out_table(LUA, 1);
    for (uint32_t type = 1; type <= 64u; type++) {
        sa1_preview_type pt;
        std::memset(&pt, 0, sizeof pt);
        pt.struct_size = sizeof pt;
        if (sa1_preview_type_get(ctx, type, &pt) != SA1_OK) {
            break;
        }
        int e = raw_subtable_i(LUA, t, (int)type);
        raw_num(LUA, e, "type", pt.type);
        raw_bool(LUA, e, "available", pt.available != 0);
        raw_num(LUA, e, "rotation", pt.rotation);
        raw_num(LUA, e, "settle", pt.settle_steps);
        LUA->Pop();
    }
    return 1;
}

// gsa1.PreviewAdd({kind, type, params, rotation, state, user_bits}) -> id | nil, message, code
GSA1_FN(gsa1_preview_PreviewAdd)
{
    static const char *usage =
        "PreviewAdd({kind = 0..8, type = 1..4, params = {p1, p2, p3}, rotation = {9 numbers} | nil, state = 1..3, "
        "user_bits = 0..255})";
    if (!LUA->IsType(1, LT::Table)) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    int t = absidx(LUA, 1);
    pv::Desc d;
    double v = 0.0;
    if (!raw_get_number(LUA, t, "kind", v) || v < 0.0 || v > 64.0 || std::floor(v) != v) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    d.kind = (int32_t)v;
    if (!raw_get_number(LUA, t, "type", v) || v < 1.0 || v > 64.0 || std::floor(v) != v) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    d.type = (uint32_t)v;
    bool present = false;
    if (!field_array(LUA, t, "params", 3, d.params, present) && present) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    if (!field_array(LUA, t, "rotation", 9, d.rotation, present) && present) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    d.state = SA1_SET_STATE_PRESENT;
    if (raw_get_number(LUA, t, "state", v)) {
        if (v < 0.0 || v > 3.0 || std::floor(v) != v) {
            return push_nil_msg(LUA, usage, "bad_argument");
        }
        d.state = (uint32_t)v;
    }
    if (raw_get_number(LUA, t, "user_bits", v)) {
        if (v < 0.0 || v > 255.0 || std::floor(v) != v) {
            return push_nil_msg(LUA, usage, "bad_argument");
        }
        d.user_bits = (uint32_t)v;
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
    uint32_t id = 0;
    std::string err;
    sa1_status st = g_pv.add(ctx, d, id, err);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, "PreviewAdd: " + scrubbed(err), pv::code_of(st));
    }
    LUA->PushNumber((double)id);
    return 1;
}

// gsa1.PreviewRemove(id) -> true | false, message, code
GSA1_FN(gsa1_preview_PreviewRemove)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0)) {
        return push_false_msg(LUA, "PreviewRemove(id)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    sa1_status st = g_pv.remove(ctx, (uint32_t)id);
    if (st != SA1_OK) {
        return push_false_msg(LUA, st == SA1_ERR_NOT_FOUND ? "PreviewRemove: no such preview" : "PreviewRemove failed",
                              pv::code_of(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.PreviewClear() -> count
GSA1_FN(gsa1_preview_PreviewClear)
{
    sa1_context *ctx = ready_ctx();
    size_t n = 0;
    g_pv.clear(ctx, n);
    LUA->PushNumber((double)n);
    return 1;
}

// gsa1.PreviewTick(dt) -> true | nil, message, code
GSA1_FN(gsa1_preview_PreviewTick)
{
    double dt = 0.0;
    if (!arg_number(LUA, 1, dt) || dt < 0.0) {
        return push_nil_msg(LUA, "PreviewTick(dt >= 0)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
    std::string err;
    sa1_status st = g_pv.tick(ctx, (float)std::min(dt, 1.0), err);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, "PreviewTick: " + scrubbed(err), pv::code_of(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.PreviewRender(id [, alpha]) -> batches, generation, batchGen, changed | nil, message, code
GSA1_FN(gsa1_preview_PreviewRender)
{
    int32_t id = 0;
    double alpha = 1.0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0) ||
        (!LUA->IsType(2, LT::Nil) && !LUA->IsType(2, LT::None) && !arg_number(LUA, 2, alpha))) {
        return push_nil_msg(LUA, "PreviewRender(id [, alpha])", "bad_argument");
    }
    gsa1::Session *se = session();
    sa1_context *ctx = ready_ctx();
    if (!ctx || !se) {
        return not_ready(LUA);
    }
    bool changed = false;
    std::string err;
    sa1_status st = g_pv.render(*se, (uint32_t)id, (float)std::max(-1.0, std::min(1.0, alpha)), changed, err);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, "PreviewRender: " + scrubbed(err), pv::code_of(st));
    }
    const pv::Copy *c = g_pv.find((uint32_t)id);
    LUA->PushNumber(c ? c->holder.batch_count : 0);
    LUA->PushNumber(c ? c->holder.r_gen : 0);
    LUA->PushNumber(c ? c->holder.batch_gen : 0);
    LUA->PushBool(changed);
    return 4;
}

// gsa1.PreviewBatches(id [, out]) -> count | nil
GSA1_FN(gsa1_preview_PreviewBatches)
{
    pv::Copy *cp = copy_arg(LUA, 1);
    if (!cp) {
        LUA->PushNil();
        return 1;
    }
    const gsa1::Character *c = &cp->holder;
    int t = out_table(LUA, 2);
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
    // entries beyond count from an earlier, longer render: removed (the addon loops over count anyway)
    for (int b = (int)c->batch_count + 1; b <= (int)c->batch_count + 8; b++) {
        LUA->PushNumber(b);
        LUA->PushNil();
        LUA->RawSet(t);
    }
    LUA->PushNumber(c->batch_count);
    LUA->Push(t);
    return 2;
}

// gsa1.PreviewPrepareView(id, eye, right, up [, flip, vertexColor, linePixels, lit]) -> true | nil
GSA1_FN(gsa1_preview_PreviewPrepareView)
{
    float eye[3], right[3], up[3];
    pv::Copy *cp = copy_arg(LUA, 1);
    gsa1::Session *se = session();
    if (!cp || !se || !arg_vector(LUA, 2, eye) || !arg_vector(LUA, 3, right) || !arg_vector(LUA, 4, up)) {
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
    se->prepare_view(cp->holder, eye, right, up, o);
    LUA->PushBool(true);
    return 1;
}

// gsa1.PreviewEmitBatch(id, b) -> vertices | nil, message
GSA1_FN(gsa1_preview_PreviewEmitBatch)
{
    int32_t b = 0;
    pv::Copy *cp = copy_arg(LUA, 1);
    if (!cp || !arg_int(LUA, 2, b, 1, 65535) || (uint32_t)b > cp->holder.batch_count) {
        return push_nil_msg(LUA, "PreviewEmitBatch(id, batch)");
    }
    return emit_batch(LUA, cp->holder, b);
}

// gsa1.PreviewInfo(id) -> steps, settled, minx, miny, minz, maxx, maxy, maxz, draws, triangles | nil, message, code
GSA1_FN(gsa1_preview_PreviewInfo)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 2147483647.0)) {
        return push_nil_msg(LUA, "PreviewInfo(id)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
    if (!g_pv.find((uint32_t)id)) {
        return push_nil_msg(LUA, "PreviewInfo: no such preview", "not_found");
    }
    sa1_preview_info pi;
    std::memset(&pi, 0, sizeof pi);
    pi.struct_size = sizeof pi;
    sa1_status st = sa1_preview_info_get(ctx, (uint32_t)id, &pi);
    if (st != SA1_OK) {
        const char *e = sa1_last_error(ctx);
        return push_nil_msg(LUA, "PreviewInfo: " + scrubbed(e ? e : sa1_status_string(st)), pv::code_of(st));
    }
    LUA->PushNumber(pi.steps);
    LUA->PushBool(pi.settled != 0);
    for (int k = 0; k < 6; k++) {
        LUA->PushNumber(std::isfinite(pi.bounds[k]) ? pi.bounds[k] : 0.0);
    }
    LUA->PushNumber(pi.draws);
    LUA->PushNumber(pi.triangles);
    return 10;
}

// gsa1.PreviewRingPlaces(kind, type, ang, p1, p2, p3 [, out]) -> n, out | nil, message, code
GSA1_FN(gsa1_preview_PreviewRingPlaces)
{
    static const char *usage = "PreviewRingPlaces(kind 0..8, type 1 | 2, ang, p1, p2, p3 [, out])";
    int32_t kind = 0, type = 0;
    gsa1::objects::Desc d;
    if (!arg_int(LUA, 1, kind, 0, 64) || !arg_int(LUA, 2, type, 1, 64) || !arg_angle(LUA, 3, d.ang)) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    d.type = (uint32_t)type;
    for (int k = 0; k < 3; k++) {
        double p = 0.0;
        if (LUA->IsType(4 + k, LT::Nil) || LUA->IsType(4 + k, LT::None)) {
            d.p[k] = 0.0f;
        } else if (arg_number(LUA, 4 + k, p) && std::fabs(p) <= 1.0e6) {
            d.p[k] = (float)p;
        } else {
            return push_nil_msg(LUA, usage, "bad_argument");
        }
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
    std::string err;
    sa1_status st = pv::ring_places(ctx, kind, d, g_places, err);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, "PreviewRingPlaces: " + scrubbed(err), pv::code_of(st));
    }
    int t = out_table(LUA, 7);
    int n = 0;
    for (const pv::Place &p : g_places) {
        int base = n * 5;
        const double vals[5] = {p.pos[0], p.pos[1], p.pos[2], (double)p.record, (double)p.bit};
        for (int k = 0; k < 5; k++) {
            LUA->PushNumber(base + k + 1);
            LUA->PushNumber(vals[k]);
            LUA->RawSet(t);
        }
        n++;
    }
    for (int k = n * 5 + 1; k <= n * 5 + 5; k++) {
        LUA->PushNumber(k);
        LUA->PushNil();
        LUA->RawSet(t);
    }
    raw_num(LUA, t, "count", n);
    LUA->PushNumber(n);
    LUA->Push(t);
    return 2;
}

// gsa1.PreviewStats([out]) -> out
GSA1_FN(gsa1_preview_PreviewStats)
{
    ready_ctx();
    int t = out_table(LUA, 1);
    const pv::Stats &s = g_pv.stats();
    raw_num(LUA, t, "copies", (double)g_pv.size());
    raw_num(LUA, t, "adds", (double)s.adds);
    raw_num(LUA, t, "removes", (double)s.removes);
    raw_num(LUA, t, "clears", (double)s.clears);
    raw_num(LUA, t, "renders", (double)s.renders);
    raw_num(LUA, t, "skipped", (double)s.skipped);
    raw_num(LUA, t, "ticks", (double)s.ticks);
    raw_num(LUA, t, "faults", (double)s.faults);
    raw_num(LUA, t, "forgets", (double)s.forgets);
    raw_num(LUA, t, "tick_ms", s.tick_ms_last);
    raw_num(LUA, t, "tick_ms_max", s.tick_ms_max);
    raw_str(LUA, t, "last_error", scrubbed(s.last_error));
    return 1;
}

namespace {

void preview_open(ILuaBase *L, int t)
{
    L->PushString("PREVIEW");
    L->CreateTable();
    int c = L->Top();
    raw_num(L, c, "ROT_NONE", SA1_PREVIEW_ROT_NONE);
    raw_num(L, c, "ROT_OUTER", SA1_PREVIEW_ROT_OUTER);
    raw_num(L, c, "ROT_INNER", SA1_PREVIEW_ROT_INNER);
    raw_num(L, c, "MAX", SA1_PREVIEW_MAX);
    raw_num(L, c, "IDLE_PAIRS", SA1_PREVIEW_IDLE_PAIRS);
    L->RawSet(t);
}

// the context goes with gsa1.Shutdown and the module's close: libsa1 frees the copies with it
void preview_shutdown()
{
    g_pv.forget();
}

void preview_close(ILuaBase *)
{
    preview_shutdown();
}

const gsa1::FeatureFn k_preview_fns[] = {
    {"PreviewTypes", gsa1_preview_PreviewTypes},
    {"PreviewAdd", gsa1_preview_PreviewAdd},
    {"PreviewRemove", gsa1_preview_PreviewRemove},
    {"PreviewClear", gsa1_preview_PreviewClear},
    {"PreviewTick", gsa1_preview_PreviewTick},
    {"PreviewRender", gsa1_preview_PreviewRender},
    {"PreviewBatches", gsa1_preview_PreviewBatches},
    {"PreviewPrepareView", gsa1_preview_PreviewPrepareView},
    {"PreviewEmitBatch", gsa1_preview_PreviewEmitBatch},
    {"PreviewInfo", gsa1_preview_PreviewInfo},
    {"PreviewRingPlaces", gsa1_preview_PreviewRingPlaces},
    {"PreviewStats", gsa1_preview_PreviewStats},
};

}  // namespace

GSA1_FEATURE(preview, 1, k_preview_fns, preview_open, preview_close, gsa1::kCloseDefault);
GSA1_FEATURE_ON_SHUTDOWN(preview, preview_shutdown);

#endif  // GSA1_HAS_PREVIEW (a libsa1 without previews: no feature "preview"; the addon keeps its outlines)
