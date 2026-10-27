// G-SA1 module: the feature "objects" (round 0.9.4: spawnable Rings and Item Boxes; libsa1 0.4, SA1_API_SET; sadc
// docs/research/gsa1_094_plan.md 6.5 with its Review). The game's own objects - a Ring, a Ring line, a Ring circle, the
// Item Box on the ground and the Item Box in the air - run by the game's SET manager and spawner in every character world
// of this client. The core is src/core/objects.{hpp,cpp} (records, the line layout, the registry); the addon's side is
// feat/{sh,cl,sv}_objects.lua and the entities addon/lua/entities/gsa1_*.lua.
//
// Lua API (feature version 3 since 0.9.4b: SetConfig's range and view_tan, SetLive, the OBJECTS limits of the range;
// version 2 = 0.9.4.1: lines and circles of up to 128 rings, a circle made of several records, a record index 0..127;
// version 1 = 0.9.4; GSA1.HasFeature("objects", 3)). Units: Hammer units and degrees.
//   gsa1.ObjectInfo([out]) -> out {count = 4, [type] = {type, name, exec, available, range (HU), states, budget, cls,
//       rotation}} | nil, message, code        libsa1's catalogue: a type with available false cannot be placed
//   gsa1.SetAdd(type, pos, ang, p1, p2, p3, user [, state]) -> id | nil, message, code
//       a new object (type gsa1.OBJECTS.RING / O_GRING / ITEMBOX / ITEMBOX_AIR) at pos (Vector) turned by ang (Angle);
//       RING: p1..p3 unused; O_GRING: p1 rings (line 1..128 in records of 8, circle 1..128 in records of n = the
//       largest of 7..1 dividing it, each record turned by its share of the circle), p2 spacing / radius (HU), p3 0 line /
//       1 circle; ITEMBOX: p1 contents 0..8, p2 the item panel's start angle (degrees); ITEMBOX_AIR: p1 contents 0..8.
//       user: the host's tag (the entity index), returned in events. state: its first state word (default PRESENT).
//       The records belong to the session's libsa1 context: every character world of this client runs them, a
//       character created later too. Codes: "not_ready", "bad_argument", "unsupported" (the type's code is not in this
//       build), "limit".
//   gsa1.SetUpdate(id, pos, ang, p1, p2, p3) -> true | nil, message, code     a new place / description (a live task
//       is made again there: a ground box grows in again); the state and bits stay
//   gsa1.SetRemove(id) -> true | false, message                               silent
//   gsa1.SetClear() -> count                                                  every object of this client
//   gsa1.SetState(id, state [, bits, index]) -> true | nil, message, code
//       the shared state: state = STATE_PRESENT | STATE_BROKEN (BROKEN: the ground box only); with index (0 ..
//       records - 1, at most MAX_RECORDS - 1 = 127) also that record's user bits (a ring group's collected rings, 0..0xFF). Applied in every world at
//       its next pair start, without sound, rings, item or event. A group whose bits go down is made again.
//   gsa1.SetConfig({ring_window =, box_window =, margin =, range =, view_tan =}) -> true | nil, message, code
//       the window (sa1_set_configure): ring tasks 1..RING_WINDOW_MAX, boxes 1..BOX_WINDOW_MAX, margin 0..1000 SA1
//       units; kept and given again to a new context. 0.9.4b (objects2_plan.md 6.3 task 1, owner answer O1): range (HU;
//       0 = the game's 1,600 = 400 SA1 units, else RANGE_MIN_HU..RANGE_MAX_HU = 1,600..12,000: the game's own per-type
//       range of the object list, sa1_set_config.range = HU / 4) and view_tan (0 = the game's 4:3 screen, else
//       VIEW_TAN_MIN..VIEW_TAN_MAX = 0.700..4.0: tan of the host view's horizontal half angle, the four SET types'
//       sideways test only). A ring_window / box_window above the maxima, a range or view_tan outside those limits:
//       nil, message, "bad_argument" (nothing changed). A libsa1 without SA1_API_SET_RANGE ignores range and view_tan
//   gsa1.SetLive(charId [, out]) -> n, out {object1, record1, object2, record2, ...} | nil, message, code
//       0.9.4b (review R.6, sa1_set_live): the objects whose records have a live task in character charId's world after
//       its last pair - n (object, record index) pairs, the records mapped back to their objects. The pictures' running
//       set (never rebuilt from the events: a world queues 256 and a re-made world raises no DESPAWNED). Codes
//       "not_found" (an unknown character), "not_ready"
//   gsa1.SetEvents([out]) -> out {count = n, [i] = {kind, character, id, user, index, type, condition, bits, step,
//       touch_step, x, y, z, cause, ax, ay, az, exec}}
//       libsa1's SET events of every world since the last call, mapped to their objects (events of objects removed
//       since are dropped). kind: EVENT_*; x, y, z: the touch (the character at the hit; UNKNOWN: the object's place);
//       ax, ay, az: the attacker (BODY: the character; PROJECTILE: the shot; MAGNET: the ring itself).
//   gsa1.SetGeneration() -> generation, objects, records     the generation changes whenever the objects were
//       forgotten (a new disc load, gsa1.Shutdown): the addon adds them all again
//   gsa1.SetStats([out]) -> out {adds, updates, removes, states, remakes, failures, forgets, events, dropped, objects,
//       records, generation, last_error}
//   gsa1.ObjectBounds(id) -> minx, miny, minz, maxx, maxy, maxz | nil     the host-space box of the SA1_DRAW_OBJECT
//       draws of character id's last Render (the render entity's bounds cover them: rings review 6.1 item 5)
//   gsa1.OBJECTS = {RING, O_GRING, ITEMBOX, ITEMBOX_AIR, STATE_PRESENT, STATE_BROKEN, EVENT_SPAWNED, EVENT_DESPAWNED,
//       EVENT_GONE, EVENT_USERBITS, EVENT_BROKEN, CAUSE_UNKNOWN, CAUSE_BODY, CAUSE_PROJECTILE, CAUSE_MAGNET,
//       GOPT_ITEM_ICON_LIMIT, DRAW_OBJECT, RING_WINDOW_MAX, BOX_WINDOW_MAX, RING_WINDOW_DEFAULT, BOX_WINDOW_DEFAULT,
//       MARGIN_DEFAULT, LINE_MAX, LINE_GROUP, CIRCLE_MAX, CIRCLE_GROUP, MAX_RECORDS, CONTENTS_MAX, CAPACITY_SET_WINDOW,
//       CAPACITY_SET_HEAP, RANGE (HU: the game's spawner range, 1,600), and 0.9.4b RANGE_MIN_HU (1,600), RANGE_MAX_HU
//       (12,000; 1,600 with a libsa1 before 0.9.4b), VIEW_TAN_MIN (0.700), VIEW_TAN_MAX (4.0; 0.700 before), TIER_HOLD,
//       HU_PER_UNIT (4)}
#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/objects.hpp"
#include "../core/session.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;
namespace ob = gsa1::objects;

namespace {

ob::Registry g_reg;
// the window the addon asked for (given again to a new context)
bool g_cfg_set = false;
sa1_set_config g_cfg;
const void *g_cfg_ctx = nullptr;
std::vector<sa1_set_event> g_evbuf;
// 0.9.4b (SetLive): every libsa1 record id this module added -> its user tag ((object << 8) | record index), kept by the
// sink below (every record goes through it); cleared with the registry's generation (a new context)
std::unordered_map<uint32_t, uint64_t> g_rec_user;
uint32_t g_rec_gen = 0;
std::vector<uint32_t> g_livebuf;

// libsa1 as the registry's sink
class LibSink : public ob::Sink {
public:
    explicit LibSink(sa1_context *c) : ctx(c) {}
    sa1_status add(const sa1_set_record &r, uint32_t &id) override
    {
        sa1_status st = sa1_set_add(ctx, &r, &id);
        if (st == SA1_OK) {
            g_rec_user[id] = r.user;
        }
        return st;
    }
    sa1_status update(uint32_t id, const sa1_set_record &r) override
    {
        sa1_status st = sa1_set_update(ctx, id, &r);
        if (st == SA1_OK) {
            g_rec_user[id] = r.user;
        }
        return st;
    }
    sa1_status remove(uint32_t id) override
    {
        g_rec_user.erase(id);
        return sa1_set_remove(ctx, id);
    }
    sa1_status state(uint32_t id, uint32_t st, uint32_t bits) override { return sa1_set_state(ctx, id, st, bits); }
    std::string error() override
    {
        const char *e = sa1_last_error(ctx);
        return scrubbed(e ? e : "");
    }
    sa1_context *ctx;
};

const char *code_of(sa1_status st)
{
    switch (st) {
    case SA1_ERR_INVALID_ARGUMENT:
        return "bad_argument";
    case SA1_ERR_UNSUPPORTED:
        return "unsupported";
    case SA1_ERR_LIMIT:
        return "limit";
    case SA1_ERR_NOT_FOUND:
        return "not_found";
    default:
        return sa1_status_string(st);
    }
}

// the session's context when the disc is loaded (the registry bound to it, the window given to it), else nullptr
sa1_context *ready_ctx()
{
    gsa1::Session *se = session();
    sa1_context *ctx = se && se->ready() ? se->ctx() : nullptr;
    g_reg.bind(ctx);
    if (g_rec_gen != g_reg.generation()) {
        g_rec_gen = g_reg.generation();
        g_rec_user.clear();        // the records went with the old context
    }
    if (ctx && g_cfg_set && g_cfg_ctx != ctx) {
        g_cfg_ctx = ctx;
        sa1_set_configure(ctx, &g_cfg);
    }
    if (!ctx) {
        g_cfg_ctx = nullptr;
    }
    return ctx;
}

int not_ready(ILuaBase *L)
{
    return push_nil_msg(L, "G-SA1 is not initialised (the disc is not loaded yet)", "not_ready");
}

// type, pos, ang, p1, p2, p3 at stack index i (i, i+1, ...) -> d
bool desc_args(ILuaBase *L, int i, ob::Desc &d)
{
    int32_t type = 0;
    double p = 0.0;
    if (!arg_int(L, i, type, 1, 4) || !arg_vector(L, i + 1, d.pos) || !arg_angle(L, i + 2, d.ang)) {
        return false;
    }
    d.type = (uint32_t)type;
    for (int k = 0; k < 3; k++) {
        if (L->IsType(i + 3 + k, LT::Nil) || L->IsType(i + 3 + k, LT::None)) {
            d.p[k] = 0.0f;
        } else if (arg_number(L, i + 3 + k, p) && std::fabs(p) <= 1.0e6) {
            d.p[k] = (float)p;
        } else {
            return false;
        }
    }
    return true;
}

}  // namespace

// gsa1.ObjectInfo([out]) -> out | nil, message, code
GSA1_FN(gsa1_objects_ObjectInfo)
{
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
    int t = out_table(LUA, 1);
    uint32_t n = sa1_object_count(ctx);
    raw_num(LUA, t, "count", n);
    for (uint32_t type = 1; type <= n && type <= 64u; type++) {
        sa1_object_info oi;
        std::memset(&oi, 0, sizeof oi);
        oi.struct_size = sizeof oi;
        if (sa1_object_info_get(ctx, type, &oi) != SA1_OK) {
            continue;
        }
        int e = raw_subtable_i(LUA, t, (int)type);
        raw_num(LUA, e, "type", oi.type);
        raw_str(LUA, e, "name", oi.name ? oi.name : "");
        raw_num(LUA, e, "exec", oi.exec);
        raw_bool(LUA, e, "available", oi.available != 0);
        raw_num(LUA, e, "range", oi.range);
        raw_num(LUA, e, "states", oi.states);
        raw_num(LUA, e, "budget", oi.budget);
        raw_num(LUA, e, "cls", oi.cls);
        raw_num(LUA, e, "rotation", oi.rotation_order);
        LUA->Pop();
    }
    return 1;
}

// gsa1.SetAdd(type, pos, ang, p1, p2, p3, user [, state]) -> id | nil, message, code
GSA1_FN(gsa1_objects_SetAdd)
{
    ob::Desc d;
    double user = 0.0;
    int32_t state = SA1_SET_STATE_PRESENT;
    if (!desc_args(LUA, 1, d) || !arg_number(LUA, 7, user) || user < 0.0 || user > 4294967295.0 ||
        std::floor(user) != user ||
        (!LUA->IsType(8, LT::Nil) && !LUA->IsType(8, LT::None) && !arg_int(LUA, 8, state, 0, 3))) {
        return push_nil_msg(LUA, "SetAdd(type 1..4, pos, ang, p1, p2, p3, user [, state])", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
    LibSink sink(ctx);
    uint32_t id = 0;
    std::string err;
    sa1_status st = g_reg.add(d, (uint64_t)user, (uint32_t)state, sink, id, err);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, "SetAdd: " + err, code_of(st));
    }
    LUA->PushNumber(id);
    return 1;
}

// gsa1.SetUpdate(id, pos, ang, p1, p2, p3) -> true | nil, message, code
GSA1_FN(gsa1_objects_SetUpdate)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 16777215.0)) {
        return push_nil_msg(LUA, "SetUpdate(id, pos, ang, p1, p2, p3)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
    const ob::Obj *o = g_reg.find((uint32_t)id);
    if (!o) {
        return push_nil_msg(LUA, "SetUpdate: no such object (added before a new disc load?)", "not_found");
    }
    ob::Desc d;
    d.type = o->desc.type;
    double p = 0.0;
    if (!arg_vector(LUA, 2, d.pos) || !arg_angle(LUA, 3, d.ang)) {
        return push_nil_msg(LUA, "SetUpdate(id, pos, ang, p1, p2, p3)", "bad_argument");
    }
    for (int k = 0; k < 3; k++) {
        if (LUA->IsType(4 + k, LT::Nil) || LUA->IsType(4 + k, LT::None)) {
            d.p[k] = 0.0f;
        } else if (arg_number(LUA, 4 + k, p) && std::fabs(p) <= 1.0e6) {
            d.p[k] = (float)p;
        } else {
            return push_nil_msg(LUA, "SetUpdate(id, pos, ang, p1, p2, p3)", "bad_argument");
        }
    }
    LibSink sink(ctx);
    std::string err;
    sa1_status st = g_reg.update((uint32_t)id, d, sink, err);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, "SetUpdate: " + err, code_of(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.SetRemove(id) -> true | false, message
GSA1_FN(gsa1_objects_SetRemove)
{
    int32_t id = 0;
    if (!arg_int(LUA, 1, id, 1, 16777215.0)) {
        return push_false_msg(LUA, "SetRemove(id)", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return push_false_msg(LUA, "G-SA1 is not initialised", "not_ready");
    }
    LibSink sink(ctx);
    if (g_reg.remove((uint32_t)id, sink) != SA1_OK) {
        return push_false_msg(LUA, "SetRemove: no such object", "not_found");
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.SetClear() -> count
GSA1_FN(gsa1_objects_SetClear)
{
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        LUA->PushNumber(0);
        return 1;
    }
    LibSink sink(ctx);
    LUA->PushNumber((double)g_reg.clear(sink));
    return 1;
}

// gsa1.SetState(id, state [, bits, index]) -> true | nil, message, code
GSA1_FN(gsa1_objects_SetState)
{
    int32_t id = 0, state = 0, bits = 0, index = -1;
    bool has_bits = !LUA->IsType(3, LT::Nil) && !LUA->IsType(3, LT::None);
    if (!arg_int(LUA, 1, id, 1, 16777215.0) || !arg_int(LUA, 2, state, 0, 3) ||
        (has_bits && (!arg_int(LUA, 3, bits, 0, 255) || !arg_int(LUA, 4, index, 0, ob::kMaxRecords - 1)))) {
        return push_nil_msg(LUA, "SetState(id, state 0..3 [, bits 0..255, record index 0..127])", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
    LibSink sink(ctx);
    std::string err;
    sa1_status st = g_reg.set_state((uint32_t)id, (uint32_t)state, has_bits ? index : -1, (uint32_t)bits, sink, err);
    if (st != SA1_OK) {
        return push_nil_msg(LUA, "SetState: " + err, code_of(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.SetConfig({ring_window =, box_window =, margin =, range =, view_tan =}) -> true | nil, message, code
GSA1_FN(gsa1_objects_SetConfig)
{
    static const char *usage = "SetConfig({ring_window =, box_window =, margin =, range = (HU), view_tan =})";
    if (!LUA->IsType(1, LT::Table)) {
        return push_nil_msg(LUA, usage, "bad_argument");
    }
    int t = absidx(LUA, 1);
    sa1_set_config c;
    std::memset(&c, 0, sizeof c);
    c.struct_size = sizeof c;
    c.ring_window = 64;
    c.box_window = 32;
    c.margin = 100.0f;
    c.list = SA1_SETLIST_LIBSA1;
    double v = 0.0;
    if (raw_get_number(LUA, t, "ring_window", v)) {
        // 0.9.4b: above the maximum refused (0.9.4 clamped; the addon clamps to gsa1.OBJECTS.RING_WINDOW_MAX itself)
        if (std::floor(v) > (double)SA1_SET_RING_WINDOW_MAX) {
            return push_nil_msg(LUA, gsa1::format("SetConfig: ring_window %g is above libsa1's maximum %u (the game's own "
                                             "collision list would drop rings)", v, (unsigned)SA1_SET_RING_WINDOW_MAX),
                                "bad_argument");
        }
        c.ring_window = (uint32_t)std::max(1.0, std::floor(v));
    }
    if (raw_get_number(LUA, t, "box_window", v)) {
        if (std::floor(v) > (double)SA1_SET_BOX_WINDOW_MAX) {
            return push_nil_msg(LUA, gsa1::format("SetConfig: box_window %g is above libsa1's maximum %u", v,
                                             (unsigned)SA1_SET_BOX_WINDOW_MAX),
                                "bad_argument");
        }
        c.box_window = (uint32_t)std::max(1.0, std::floor(v));
    }
    if (raw_get_number(LUA, t, "margin", v)) {
        c.margin = (float)std::max(0.0, std::min(1000.0, v));
    }
#if defined(SA1_API_SET_RANGE)
    // 0.9.4b (objects2_plan.md 6.3 task 1, owner answer O1): the spawner's range in HU (G-SA1's 4 HU per SA1 unit) and
    // the object displays' horizontal half view; refused outside libsa1's limits (a few thousandths of slack for the
    // HU <-> unit conversion and the addon's rounding)
    const double hu = (double)g_reg.hu_per_unit;
    if (raw_get_number(LUA, t, "range", v) && v != 0.0) {
        double u = v / hu;
        if (u < (double)SA1_SET_RANGE_MIN - 1e-3 || u > (double)SA1_SET_RANGE_MAX + 1e-3) {
            return push_nil_msg(LUA, gsa1::format("SetConfig: range %g HU is outside 0 and %g..%g HU", v,
                                             (double)SA1_SET_RANGE_MIN * hu, (double)SA1_SET_RANGE_MAX * hu),
                                "bad_argument");
        }
        c.range = (float)std::max((double)SA1_SET_RANGE_MIN, std::min((double)SA1_SET_RANGE_MAX, u));
    }
    if (raw_get_number(LUA, t, "view_tan", v) && v != 0.0) {
        if (v < 0.700 - 1e-4 || v > (double)SA1_SET_VIEW_TAN_MAX + 1e-4) {
            return push_nil_msg(LUA, gsa1::format("SetConfig: view_tan %g is outside 0 and 0.700..%g", v,
                                             (double)SA1_SET_VIEW_TAN_MAX),
                                "bad_argument");
        }
        c.view_tan = (float)std::max(0.700, std::min((double)SA1_SET_VIEW_TAN_MAX, v));
    }
#endif
    // (a libsa1 before round 0.9.4b: range and view_tan are not in its sa1_set_config and are ignored here)
    g_cfg = c;
    g_cfg_set = true;
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);     // kept: given to the context once the disc is loaded
    }
    sa1_status st = sa1_set_configure(ctx, &c);
    g_cfg_ctx = ctx;
    if (st != SA1_OK) {
        const char *e = sa1_last_error(ctx);
        return push_nil_msg(LUA, scrubbed(e ? e : "sa1_set_configure failed"), code_of(st));
    }
    LUA->PushBool(true);
    return 1;
}

// gsa1.SetLive(charId [, out]) -> n, out {object1, record1, ...} | nil, message, code
GSA1_FN(gsa1_objects_SetLive)
{
    int32_t cid = 0;
    if (!arg_int(LUA, 1, cid, 1, 2147483647.0)) {
        return push_nil_msg(LUA, "SetLive(charId [, out])", "bad_argument");
    }
    sa1_context *ctx = ready_ctx();
    if (!ctx) {
        return not_ready(LUA);
    }
#if defined(SA1_API_SET_LIVE)
    uint32_t count = 0;
    sa1_status st = SA1_OK;
    for (int tries = 0; tries < 4; tries++) {
        if (g_livebuf.empty()) {
            g_livebuf.resize(256);
        }
        count = 0;
        st = sa1_set_live(ctx, (sa1_character_id)cid, g_livebuf.data(), (uint32_t)g_livebuf.size(), &count);
        if (st != SA1_ERR_BUFFER_TOO_SMALL) {
            break;
        }
        g_livebuf.resize((size_t)count + 64u);
    }
    if (st == SA1_ERR_NOT_FOUND) {
        return push_nil_msg(LUA, "SetLive: no such character", "not_found");
    }
    if (st != SA1_OK) {
        const char *e = sa1_last_error(ctx);
        return push_nil_msg(LUA, "SetLive: " + scrubbed(e ? e : sa1_status_string(st)), code_of(st));
    }
#else
    uint32_t count = 0;
#endif
    int t = out_table(LUA, 2);
    int n = 0;
    for (uint32_t k = 0; k < count && k < (uint32_t)g_livebuf.size(); k++) {
        auto it = g_rec_user.find(g_livebuf[k]);
        if (it == g_rec_user.end()) {
            continue;
        }
        uint32_t oid = (uint32_t)(it->second >> 8), idx = (uint32_t)(it->second & 0xFFu);
        const ob::Obj *o = g_reg.find(oid);
        if (!o || idx >= o->records.size() || o->records[idx] != g_livebuf[k]) {
            continue;
        }
        LUA->PushNumber(2 * n + 1);
        LUA->PushNumber(oid);
        LUA->RawSet(t);
        LUA->PushNumber(2 * n + 2);
        LUA->PushNumber(idx);
        LUA->RawSet(t);
        n++;
    }
    for (int k = 2 * n + 1; k <= 2 * n + 2; k++) {
        LUA->PushNumber(k);
        LUA->PushNil();
        LUA->RawSet(t);
    }
    raw_num(LUA, t, "count", n);
    LUA->PushNumber(n);
    LUA->Push(t);
    return 2;
}

// gsa1.SetEvents([out]) -> out
GSA1_FN(gsa1_objects_SetEvents)
{
    sa1_context *ctx = ready_ctx();
    int t = out_table(LUA, 1);
    uint32_t count = 0;
    if (ctx) {
        g_evbuf.resize(256);
        uint32_t n = 0;
        for (int round = 0; round < 64; round++) {
            n = 0;
            if (sa1_poll_set_events(ctx, g_evbuf.data(), (uint32_t)g_evbuf.size(), &n) != SA1_OK) {
                break;
            }
            for (uint32_t k = 0; k < n && k < g_evbuf.size(); k++) {
                ob::Event m;
                if (!g_reg.map(g_evbuf[k], m)) {
                    continue;
                }
                const sa1_set_event &e = m.ev;
                int et = raw_subtable_i(LUA, t, (int)++count);
                raw_num(LUA, et, "kind", e.type);
                raw_num(LUA, et, "character", e.character);
                raw_num(LUA, et, "id", m.object);
                raw_num(LUA, et, "user", (double)m.user);
                raw_num(LUA, et, "index", m.index);
                raw_num(LUA, et, "type", m.type);
                raw_num(LUA, et, "condition", e.condition);
                raw_num(LUA, et, "bits", e.user_bits);
                raw_num(LUA, et, "step", e.step);
                raw_num(LUA, et, "touch_step", e.touch_step);
                raw_num(LUA, et, "x", e.position[0]);
                raw_num(LUA, et, "y", e.position[1]);
                raw_num(LUA, et, "z", e.position[2]);
                raw_num(LUA, et, "cause", e.cause);
                raw_num(LUA, et, "ax", e.attacker[0]);
                raw_num(LUA, et, "ay", e.attacker[1]);
                raw_num(LUA, et, "az", e.attacker[2]);
                raw_num(LUA, et, "exec", e.exec);
                LUA->Pop();
                if (count >= 4096u) {
                    break;
                }
            }
            if (n < g_evbuf.size() || count >= 4096u) {
                break;
            }
        }
    }
    raw_num(LUA, t, "count", count);
    return 1;
}

// gsa1.SetGeneration() -> generation, objects, records
GSA1_FN(gsa1_objects_SetGeneration)
{
    ready_ctx();
    LUA->PushNumber(g_reg.generation());
    LUA->PushNumber((double)g_reg.size());
    LUA->PushNumber((double)g_reg.record_total());
    return 3;
}

// gsa1.SetStats([out]) -> out
GSA1_FN(gsa1_objects_SetStats)
{
    ready_ctx();
    int t = out_table(LUA, 1);
    const ob::Stats &s = g_reg.stats();
    raw_num(LUA, t, "adds", (double)s.adds);
    raw_num(LUA, t, "updates", (double)s.updates);
    raw_num(LUA, t, "removes", (double)s.removes);
    raw_num(LUA, t, "states", (double)s.states);
    raw_num(LUA, t, "remakes", (double)s.remakes);
    raw_num(LUA, t, "failures", (double)s.failures);
    raw_num(LUA, t, "forgets", (double)s.forgets);
    raw_num(LUA, t, "events", (double)s.events);
    raw_num(LUA, t, "dropped", (double)s.dropped);
    raw_num(LUA, t, "objects", (double)g_reg.size());
    raw_num(LUA, t, "records", (double)g_reg.record_total());
    raw_num(LUA, t, "generation", g_reg.generation());
    raw_str(LUA, t, "last_error", s.last_error);
    return 1;
}

// gsa1.ObjectBounds(id) -> minx, miny, minz, maxx, maxy, maxz | nil
GSA1_FN(gsa1_objects_ObjectBounds)
{
    int32_t id = 0;
    gsa1::Session *se = session();
    gsa1::Character *c = nullptr;
    float mn[3] = {0, 0, 0}, mx[3] = {0, 0, 0};
    if (!se || !arg_int(LUA, 1, id, 1, 2147483647.0) || !(c = se->get(id)) || !c->rendered ||
        !ob::object_draw_bounds(*c, mn, mx)) {
        LUA->PushNil();
        return 1;
    }
    for (int k = 0; k < 3; k++) LUA->PushNumber(mn[k]);
    for (int k = 0; k < 3; k++) LUA->PushNumber(mx[k]);
    return 6;
}

namespace {

void objects_open(ILuaBase *L, int t)
{
    L->PushString("OBJECTS");
    L->CreateTable();
    int c = L->Top();
    raw_num(L, c, "RING", SA1_OBJTYPE_RING);
    raw_num(L, c, "O_GRING", SA1_OBJTYPE_O_GRING);
    raw_num(L, c, "ITEMBOX", SA1_OBJTYPE_ITEMBOX);
    raw_num(L, c, "ITEMBOX_AIR", SA1_OBJTYPE_ITEMBOX_AIR);
    raw_num(L, c, "STATE_PRESENT", SA1_SET_STATE_PRESENT);
    raw_num(L, c, "STATE_BROKEN", SA1_SET_STATE_BROKEN);
    raw_num(L, c, "EVENT_SPAWNED", SA1_SET_EVENT_SPAWNED);
    raw_num(L, c, "EVENT_DESPAWNED", SA1_SET_EVENT_DESPAWNED);
    raw_num(L, c, "EVENT_GONE", SA1_SET_EVENT_GONE);
    raw_num(L, c, "EVENT_USERBITS", SA1_SET_EVENT_USERBITS);
    raw_num(L, c, "EVENT_BROKEN", SA1_SET_EVENT_BROKEN);
    raw_num(L, c, "CAUSE_UNKNOWN", SA1_SET_CAUSE_UNKNOWN);
    raw_num(L, c, "CAUSE_BODY", SA1_SET_CAUSE_BODY);
    raw_num(L, c, "CAUSE_PROJECTILE", SA1_SET_CAUSE_PROJECTILE);
    raw_num(L, c, "CAUSE_MAGNET", SA1_SET_CAUSE_MAGNET);
    raw_num(L, c, "GOPT_ITEM_ICON_LIMIT", SA1_GOPT_ITEM_ICON_LIMIT);
    raw_num(L, c, "DRAW_OBJECT", SA1_DRAW_OBJECT);
    raw_num(L, c, "RING_WINDOW_MAX", SA1_SET_RING_WINDOW_MAX);
    raw_num(L, c, "BOX_WINDOW_MAX", SA1_SET_BOX_WINDOW_MAX);
    raw_num(L, c, "RING_WINDOW_DEFAULT", 64);
    raw_num(L, c, "BOX_WINDOW_DEFAULT", 32);
    raw_num(L, c, "MARGIN_DEFAULT", 100);
    raw_num(L, c, "LINE_MAX", ob::kLineMax);
    raw_num(L, c, "LINE_GROUP", ob::kLineGroup);
    raw_num(L, c, "CIRCLE_MAX", ob::kCircleMax);
    raw_num(L, c, "CIRCLE_GROUP", ob::kCircleGroup);
    raw_num(L, c, "MAX_RECORDS", ob::kMaxRecords);
    raw_num(L, c, "CONTENTS_MAX", ob::kContentsMax);
    raw_num(L, c, "CAPACITY_SET_WINDOW", SA1_CAPACITY_SET_WINDOW);
    raw_num(L, c, "CAPACITY_SET_HEAP", SA1_CAPACITY_SET_HEAP);
    raw_num(L, c, "RANGE", 400.0 * 4.0);     // HU: the spawner's 400 SA1 units
    raw_num(L, c, "HU_PER_UNIT", g_reg.hu_per_unit);
#if defined(SA1_API_SET_RANGE)
    // 0.9.4b: the spawner's range (owner answer O1: up to the far plane, 12,000 HU) and the displays' half view
    raw_num(L, c, "RANGE_MIN_HU", (double)SA1_SET_RANGE_MIN * g_reg.hu_per_unit);
    raw_num(L, c, "RANGE_MAX_HU", (double)SA1_SET_RANGE_MAX * g_reg.hu_per_unit);
    raw_num(L, c, "VIEW_TAN_MIN", 0.700);
    raw_num(L, c, "VIEW_TAN_MAX", SA1_SET_VIEW_TAN_MAX);
    raw_num(L, c, "TIER_HOLD", SA1_SET_TIER_HOLD);
#else
    raw_num(L, c, "RANGE_MIN_HU", 1600);
    raw_num(L, c, "RANGE_MAX_HU", 1600);
    raw_num(L, c, "VIEW_TAN_MIN", 0.700);
    raw_num(L, c, "VIEW_TAN_MAX", 0.700);
    raw_num(L, c, "TIER_HOLD", 0);
#endif
    L->RawSet(t);
}

// the context goes with gsa1.Shutdown and the module's close: the records with it
void objects_shutdown()
{
    g_reg.forget();
    g_rec_user.clear();
    g_rec_gen = g_reg.generation();
    g_cfg_ctx = nullptr;
}

void objects_close(ILuaBase *)
{
    objects_shutdown();
}

const gsa1::FeatureFn k_objects_fns[] = {
    {"ObjectInfo", gsa1_objects_ObjectInfo},
    {"SetAdd", gsa1_objects_SetAdd},
    {"SetUpdate", gsa1_objects_SetUpdate},
    {"SetRemove", gsa1_objects_SetRemove},
    {"SetClear", gsa1_objects_SetClear},
    {"SetState", gsa1_objects_SetState},
    {"SetConfig", gsa1_objects_SetConfig},
    {"SetLive", gsa1_objects_SetLive},
    {"SetEvents", gsa1_objects_SetEvents},
    {"SetGeneration", gsa1_objects_SetGeneration},
    {"SetStats", gsa1_objects_SetStats},
    {"ObjectBounds", gsa1_objects_ObjectBounds},
};

}  // namespace

GSA1_FEATURE(objects, 3, k_objects_fns, objects_open, objects_close, gsa1::kCloseDefault);
GSA1_FEATURE_ON_SHUTDOWN(objects, objects_shutdown);
