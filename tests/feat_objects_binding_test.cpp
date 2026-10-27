// feat_objects_binding_test: spawnable Rings and Item Boxes through the module's Lua functions - the feature "objects"
// (src/module/bind_objects.cpp, src/core/objects.*; round 0.9.4, sadc docs/research/gsa1_094_plan.md 6.5 with its Review
// R.1 / R.17). Linked like binding_test (the module's objects, libsa1, the mock Lua stack of tests/mock_lua.hpp) by
// build.py, run with --gdi GAME.gdi.
//
//   feat_objects_binding_test [--gdi GAME.gdi] [--verbose]
//
// Without the disc: gsa1.FEATURES.objects = 3 (0.9.4b; 2 = 0.9.4.1), the functions registered, gsa1.OBJECTS holds libsa1's numbers; bad
// arguments come back as nil + message (no Lua error); SetAdd says "not_ready"; SetEvents is empty.
// With the disc, through the module's session on a flat floor:
//   * ObjectInfo: the four types (RING, O_GRING, ITEMBOX, ITEMBOX_AIR) available, range 1,600 HU;
//   * a RING 60 HU ahead of Sonic, Sonic runs: one GONE whose user is the entity index, the touch within 64 HU of the
//     ring, rings 1;
//   * a Ring line of 8 (40 HU apart) ahead of Sonic along his run: USERBITS of record 0 until every bit (0xFF) - the
//     line runs along the entity's forward in the game too - and rings 8;
//   * 0.9.4.1, THE LAYOUT MEASURED (the owner's refusals "the touch was 216 units from it (at most 64)"): the game's own
//     ring tasks (the O_GRING task's ring children) of lines of 10 / 20 and a circle of 7 at yaw 0 / 37 / 90 / 200, pitch
//     30 and (-60 120 20) within 1 HU of ring_positions for their record and bit; Sonic put on each ring: the USERBITS
//     event names exactly its record and bit; the line's ring draws at the predicted places; Sonic RUNNING through a
//     line: every event's touch within 64 HU of a ring of its record but some > 64 HU from the rings the event adds (the
//     record's latest touched ring - the cause of the refusals; feat/sh_objects.lua O.CheckEvent allows for it);
//   * 0.9.4.1, circles of 7, 12, 64, 127 and 128 rings made of several records (n rings each, record k turned by
//     k * 360 / N), each at two angles: every ring where ring_positions says (the evenly spaced places; records added in
//     slices of the 70-ring window), and touches name their record and bit;
//   * a ground Item Box with 10 Rings (content 3): Sonic dropped onto its lid once it has grown: one BROKEN (cause BODY,
//     the touch within 80 HU), no GONE, rings + 10;
//   * an Item Box (Air) with an Extra Life (content 6) 40 HU above the floor (the entity's default height), Sonic runs
//     into it: lives + 1, one GONE;
//   * SetState(BROKEN) with a second character (Tails, review R.17): in his world the intact box becomes the shell -
//     condition & 0x0004, task mode >= 4 - with his rings unchanged, no item sound (SE 11) in his world and no GONE /
//     BROKEN / USERBITS event (a forced write raises none; DESPAWNED / SPAWNED are the slot's);
//   * 120 RINGs ahead of Sonic (ring window 70: the 70 nearest run): no draw skipped (the batches hold every triangle of
//     the render, none above 8,000), the ring batches carry SA1_DRAW_OBJECT, Sonic's own blob shadow is in a batch
//     without it (review R.1); ObjectBounds covers the rings drawn;
//   * SetGameOption(GOPT_ITEM_ICON_LIMIT, 1) accepted (the charopt feature's function, the icon guard of cl_objects.lua);
//   * SetRemove / SetClear: the records gone (SetGeneration's count); gsa1.Shutdown: a new generation;
//   * 0.9.4b (objects2_plan.md 6.3 task 1 with owner answer O1, feature "objects" 3): SetConfig{range = 4800} -> ObjectInfo
//     range 4,800 HU; a RING 3,000 HU ahead of a ticking Sonic runs (SetLive) and draws with range 4,800 and not with the
//     game's 1,600; with view_tan 1.873 (3440 x 1440 at fov 92.5) a RING 50 degrees off the camera's forward is drawn,
//     with 0 (the game's 4:3) it is not; SetConfig range 13,000 / 1,000 HU, ring_window 201, box_window 101, view_tan 5
//     and 0.5 refused ("bad_argument", nothing changed); gsa1.OBJECTS RANGE_MIN_HU 1,600, RANGE_MAX_HU 12,000.
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "mock_lua.hpp"
#include "../src/core/config.hpp"
#include "../src/core/objects.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"

namespace ob = gsa1::objects;

namespace {

bool g_verbose = false;

// ---- guest addresses (US v1.005; LIB tests/set_test.c) ----------------------------------------------------------------
const uint32_t A_TASK_LISTS = 0x8C79F04Cu;     // task *B_8C79F04C[8]
const uint32_t A_PLAYER_TWP = 0x8C78C608u;
const uint32_t A_PLAYER_MWP = 0x8C78C628u;
const uint32_t A_PLAYER_PWP = 0x8C78C668u;
const uint32_t X_GBOX = 0x8C05D10Cu;           // objexec_O_ITEMBOX
const uint32_t SE_ITEM = 11u;

uint32_t rd32(const struct sa1g_world *w, uint32_t g)
{
    uint32_t v = 0;
    return w && sa1g_world_rd32(w, g, &v) == 0 ? v : 0u;
}

bool arena(uint32_t g)
{
    return g >= 0x8C000000u && g < 0x8D000000u;
}

void wrf(struct sa1g_world *w, uint32_t g, float f)
{
    uint32_t v;
    std::memcpy(&v, &f, 4);
    sa1g_world_wr32(w, g, v);
}

// Sonic's SA1 position written (set_test's tele: the speeds zeroed)
void tele(struct sa1g_world *w, float x, float y, float z)
{
    uint32_t t = rd32(w, A_PLAYER_TWP), m = rd32(w, A_PLAYER_MWP), p = rd32(w, A_PLAYER_PWP);
    if (!arena(t)) return;
    wrf(w, t + 0x20u, x);
    wrf(w, t + 0x24u, y);
    wrf(w, t + 0x28u, z);
    for (uint32_t k = 0; k < 3; k++) {
        if (arena(m)) wrf(w, m + 0x04u + 4u * k, 0.0f);
        if (arena(p)) wrf(w, p + 0x38u + 4u * k, 0.0f);
    }
}

// the first top-level task with this exec (0: none)
uint32_t find_task(const struct sa1g_world *w, uint32_t exec)
{
    for (uint32_t lv = 0; lv < 8; lv++) {
        uint32_t tp = rd32(w, A_TASK_LISTS + 4u * lv), guard = 0;
        while (arena(tp) && guard++ < 0x2000u) {
            if ((rd32(w, tp + 0x10u) & 0x1FFFFFFFu) == (exec & 0x1FFFFFFFu)) return tp;
            tp = rd32(w, tp);
        }
    }
    return 0;
}

uint32_t task_mode(const struct sa1g_world *w, uint32_t tp)
{
    uint32_t twp = arena(tp) ? rd32(w, tp + 0x20u) : 0u;
    return arena(twp) ? (rd32(w, twp) & 0xFFu) : 0xEEu;
}

uint32_t task_cond(const struct sa1g_world *w, uint32_t tp)
{
    uint32_t ocp = arena(tp) ? rd32(w, tp + 0x1Cu) : 0u;
    return arena(ocp) ? (rd32(w, ocp) >> 16) & 0xFFFFu : 0xFFFFFFFFu;
}

// a quad as two triangles facing +z
void floor_quad(std::vector<sa1_collision_tri> &out, float x0, float x1, float y0, float y1)
{
    sa1_collision_tri a, b;
    std::memset(&a, 0, sizeof a);
    std::memset(&b, 0, sizeof b);
    const float p[4][3] = {{x0, y0, 0}, {x1, y0, 0}, {x1, y1, 0}, {x0, y1, 0}};
    std::memcpy(a.v[0], p[0], 12);
    std::memcpy(a.v[1], p[1], 12);
    std::memcpy(a.v[2], p[2], 12);
    std::memcpy(b.v[0], p[0], 12);
    std::memcpy(b.v[1], p[2], 12);
    std::memcpy(b.v[2], p[3], 12);
    a.surface = b.surface = SA1_SURFACE_SOLID;
    out.push_back(a);
    out.push_back(b);
}

struct Ev {
    int kind = 0, index = 0, cause = 0, type = 0;
    double character = 0, user = 0, id = 0, bits = 0, cond = 0, step = 0, touch_step = 0;
    float pos[3] = {0, 0, 0}, att[3] = {0, 0, 0};
};

std::vector<Ev> poll(MockLua &L)
{
    std::vector<Ev> out;
    Val t = Val::table();
    std::vector<Val> r = L.call("SetEvents", {t});
    if (r.size() != 1 || r[0].type != Type::Table) return out;
    int n = (int)t.tab->field("count").num;
    for (int i = 1; i <= n; i++) {
        Val e = t.tab->at(i);
        if (e.type != Type::Table) continue;
        Ev v;
        v.kind = (int)e.tab->field("kind").num;
        v.index = (int)e.tab->field("index").num;
        v.cause = (int)e.tab->field("cause").num;
        v.type = (int)e.tab->field("type").num;
        v.character = e.tab->field("character").num;
        v.user = e.tab->field("user").num;
        v.id = e.tab->field("id").num;
        v.bits = e.tab->field("bits").num;
        v.cond = e.tab->field("condition").num;
        v.step = e.tab->field("step").num;
        v.touch_step = e.tab->field("touch_step").num;
        v.pos[0] = (float)e.tab->field("x").num;
        v.pos[1] = (float)e.tab->field("y").num;
        v.pos[2] = (float)e.tab->field("z").num;
        v.att[0] = (float)e.tab->field("ax").num;
        v.att[1] = (float)e.tab->field("ay").num;
        v.att[2] = (float)e.tab->field("az").num;
        if (g_verbose) {
            std::printf("    event kind %d character %g user %g index %d bits %02X cond %04X step %g touch %g cause %d "
                        "at (%.1f %.1f %.1f) attacker (%.1f %.1f %.1f)\n", v.kind, v.character, v.user, v.index,
                        (unsigned)v.bits, (unsigned)v.cond, v.step, v.touch_step, v.cause, (double)v.pos[0],
                        (double)v.pos[1], (double)v.pos[2], (double)v.att[0], (double)v.att[1], (double)v.att[2]);
        }
        out.push_back(v);
    }
    return out;
}

float dist(const float a[3], const float b[3])
{
    float d0 = a[0] - b[0], d1 = a[1] - b[1], d2 = a[2] - b[2];
    return std::sqrt(d0 * d0 + d1 * d1 + d2 * d2);
}

double add(MockLua &L, int type, float x, float y, float z, double p1, double p2, double p3, double user, float yaw = 0)
{
    std::vector<Val> r = L.call("SetAdd", {Val::number(type), Val::vector(x, y, z), Val::angle(0, yaw, 0), Val::number(p1),
                                           Val::number(p2), Val::number(p3), Val::number(user)});
    if (r.size() == 1 && r[0].type == Type::Number) return r[0].num;
    std::printf("  info  SetAdd(%d): %s (%s)\n", type, str_of(r, 1).c_str(), str_of(r, 2).c_str());
    return 0;
}

int count_kind(const std::vector<Ev> &ev, int kind, double user)
{
    int n = 0;
    for (const Ev &e : ev) n += e.kind == kind && e.user == user;
    return n;
}

const Ev *first_kind(const std::vector<Ev> &ev, int kind, double user)
{
    for (const Ev &e : ev) {
        if (e.kind == kind && e.user == user) return &e;
    }
    return nullptr;
}


// ---- 0.9.4.1: the game's own ring places (the group tasks' ring children) -------------------------------------------
const uint32_t X_GRING = 0x8C087B80u;          // objexec_O_GRING

float rdf(const struct sa1g_world *w, uint32_t g)
{
    uint32_t v = rd32(w, g);
    float f;
    std::memcpy(&f, &v, 4);
    return f;
}

// SA1 -> host (the SOURCE preset: host = 4 (x, -z, y)) and back
void host_of(const float s[3], float h[3])
{
    h[0] = 4.0f * s[0];
    h[1] = -4.0f * s[2];
    h[2] = 4.0f * s[1];
}
void sa1_of(const float h[3], float s[3])
{
    s[0] = h[0] / 4.0f;
    s[1] = h[2] / 4.0f;
    s[2] = -h[1] / 4.0f;
}

// a live O_GRING task: its place (the record's position) and its ring children (timer.b[0] = the ring's bit, the
// child's twp->pos = where the ring's display draws it: func_8C086D00 njTranslate(twp->pos))
struct GKid {
    uint32_t bit = 0, mode = 0;
    float h[3] = {0, 0, 0};
};
struct GTask {
    uint32_t tp = 0;
    float h[3] = {0, 0, 0};
    std::vector<GKid> kids;
};
std::vector<GTask> gring_tasks(const struct sa1g_world *w)
{
    std::vector<GTask> out;
    for (uint32_t lv = 0; lv < 8; lv++) {
        uint32_t tp = rd32(w, A_TASK_LISTS + 4u * lv), guard = 0;
        while (arena(tp) && guard++ < 0x4000u) {
            if ((rd32(w, tp + 0x10u) & 0x1FFFFFFFu) == (X_GRING & 0x1FFFFFFFu)) {
                GTask g;
                g.tp = tp;
                uint32_t twp = rd32(w, tp + 0x20u);
                const float s[3] = {rdf(w, twp + 0x20u), rdf(w, twp + 0x24u), rdf(w, twp + 0x28u)};
                host_of(s, g.h);
                uint32_t c = rd32(w, tp + 0x0Cu), cg = 0;
                while (arena(c) && cg++ < 64u) {
                    uint32_t ct = rd32(w, c + 0x20u);
                    if (arena(ct)) {
                        GKid k;
                        k.bit = rd32(w, ct + 0x0Cu) & 0xFFu;
                        k.mode = rd32(w, ct) & 0xFFu;
                        const float cs[3] = {rdf(w, ct + 0x20u), rdf(w, ct + 0x24u), rdf(w, ct + 0x28u)};
                        host_of(cs, k.h);
                        g.kids.push_back(k);
                    }
                    c = rd32(w, c);
                }
                out.push_back(g);
            }
            tp = rd32(w, tp);
        }
    }
    return out;
}

// the live rings of the given records against ring_positions: each live group task is matched to the record (of
// want_recs, at its place) whose predicted rings fit all its children best (every record of a circle has the circle's
// centre); worst: the largest offset of a live ring from its record's and bit's predicted place; records: how many
// different records were matched (a turn the wrong way would match no record, or the touches name another)
struct PlaceCheck {
    float worst = 0.0f;
    int rings = 0, groups = 0, records = 0;
};
PlaceCheck check_places(const struct sa1g_world *w, const std::vector<sa1_set_record> &recs,
                        const std::vector<uint32_t> &want_recs, const std::vector<gsa1::objects::RingPos> &pred)
{
    PlaceCheck pc;
    std::vector<bool> seen(recs.size(), false);
    for (const GTask &g : gring_tasks(w)) {
        int best_r = -1;
        float best_e = 1e9f;
        for (uint32_t r : want_recs) {
            if (dist(g.h, recs[r].position) > 2.0f) {
                continue;
            }
            float worst = 0.0f;
            for (const GKid &kd : g.kids) {
                float e = 1e9f;
                for (const gsa1::objects::RingPos &p : pred) {
                    if (p.record == r && p.bit == kd.bit) {
                        e = dist(p.pos, kd.h);
                    }
                }
                worst = std::max(worst, e);
            }
            if (worst < best_e) {
                best_e = worst;
                best_r = (int)r;
            }
        }
        if (best_r < 0) {
            continue;                       // not one of these records
        }
        pc.groups++;
        pc.rings += (int)g.kids.size();
        pc.worst = std::max(pc.worst, best_e);
        if (!seen[(size_t)best_r]) {
            seen[(size_t)best_r] = true;
            pc.records++;
        }
    }
    return pc;
}

}  // namespace

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i < argc; i++) {
        if (std::string(argv[i]) == "--gdi" && i + 1 < argc) gdi = argv[++i];
        else if (std::string(argv[i]) == "--verbose") g_verbose = true;
    }
    std::printf("G-SA1 feat_objects_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_objects_appdata");
#ifdef _WIN32
    char full[4096];
    GetFullPathNameA(fake_appdata.c_str(), sizeof full, full, nullptr);
    fake_appdata = full;
    SetEnvironmentVariableW(L"APPDATA", gsa1::widen(fake_appdata).c_str());
#else
    setenv("XDG_CONFIG_HOME", fake_appdata.c_str(), 1);
#endif
    gmod13_open(&state);
    Val g = L.globals.tab->field("gsa1");
    Val feats = g.type == Type::Table ? g.tab->field("FEATURES") : Val();
    Val O = g.type == Type::Table ? g.tab->field("OBJECTS") : Val();
    bool fns = g.type == Type::Table;
    for (const char *f : {"ObjectInfo", "SetAdd", "SetUpdate", "SetRemove", "SetClear", "SetState", "SetConfig", "SetEvents",
                          "SetGeneration", "SetStats", "ObjectBounds", "SetLive"}) {
        fns = fns && g.tab->field(f).type == Type::Function;
    }
    Val ferr = g.type == Type::Table ? g.tab->field("FEATURE_ERRORS") : Val();
    CHECK(fns && feats.type == Type::Table && feats.tab->field("objects").num == 3 && ferr.type == Type::Table &&
              ferr.tab->n.empty() && L.st.empty(),
          "gsa1.FEATURES.objects = %g; ObjectInfo, SetAdd, SetUpdate, SetRemove, SetClear, SetState, SetConfig, SetEvents, "
          "SetGeneration, SetStats, ObjectBounds, SetLive registered, no clash",
          feats.type == Type::Table ? feats.tab->field("objects").num : -1.0);
    if (g.type != Type::Table || O.type != Type::Table) {
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    auto on = [&](const char *k) { return O.tab->field(k).num; };
    CHECK(on("RING") == SA1_OBJTYPE_RING && on("O_GRING") == SA1_OBJTYPE_O_GRING && on("ITEMBOX") == SA1_OBJTYPE_ITEMBOX &&
              on("ITEMBOX_AIR") == SA1_OBJTYPE_ITEMBOX_AIR && on("STATE_BROKEN") == SA1_SET_STATE_BROKEN &&
              on("EVENT_GONE") == SA1_SET_EVENT_GONE && on("EVENT_BROKEN") == SA1_SET_EVENT_BROKEN &&
              on("EVENT_USERBITS") == SA1_SET_EVENT_USERBITS && on("CAUSE_MAGNET") == SA1_SET_CAUSE_MAGNET &&
              on("CAUSE_PROJECTILE") == SA1_SET_CAUSE_PROJECTILE && on("GOPT_ITEM_ICON_LIMIT") == SA1_GOPT_ITEM_ICON_LIMIT &&
              on("DRAW_OBJECT") == SA1_DRAW_OBJECT && on("RING_WINDOW_MAX") == SA1_SET_RING_WINDOW_MAX &&
              on("BOX_WINDOW_MAX") == SA1_SET_BOX_WINDOW_MAX && on("LINE_MAX") == 128 && on("CIRCLE_MAX") == 128 &&
              on("CIRCLE_GROUP") == 7 && on("MAX_RECORDS") == 128 && on("RANGE") == 1600 && on("RANGE_MIN_HU") == 1600 &&
              on("RANGE_MAX_HU") == 12000 && std::fabs(on("VIEW_TAN_MAX") - 4.0) < 1e-6 &&
              std::fabs(on("VIEW_TAN_MIN") - 0.7) < 1e-6 && on("HU_PER_UNIT") == 4,
          "gsa1.OBJECTS: libsa1's numbers (DRAW_OBJECT 0x%X, GOPT_ITEM_ICON_LIMIT %g, windows %g / %g, line 128, circle 128 "
          "in records of up to 7, 128 records, range 1600 HU; 0.9.4b: the range 1600..12000 HU, view_tan 0.7..4)",
          (unsigned)on("DRAW_OBJECT"), on("GOPT_ITEM_ICON_LIMIT"), on("RING_WINDOW_MAX"),
          on("BOX_WINDOW_MAX"));
    int bad = 0;
    bad += is_nil_msg(L.call("SetAdd", {}));
    bad += is_nil_msg(L.call("SetAdd", {Val::number(9), Val::vector(0, 0, 0), Val::angle(0, 0, 0), Val::number(0),
                                        Val::number(0), Val::number(0), Val::number(1)}));
    bad += is_nil_msg(L.call("SetAdd", {Val::number(1), Val::number(0), Val::angle(0, 0, 0), Val::number(0), Val::number(0),
                                        Val::number(0), Val::number(1)}));
    bad += is_nil_msg(L.call("SetAdd", {Val::number(1), Val::vector(0, 0, 0), Val::angle(0, 0, 0), Val::number(0),
                                        Val::number(0), Val::number(0), Val::number(-1)}));
    bad += is_nil_msg(L.call("SetState", {Val::number(1), Val::number(9)}));
    bad += is_nil_msg(L.call("SetState", {Val::number(1), Val::number(1), Val::number(300), Val::number(0)}));
    bad += is_nil_msg(L.call("SetConfig", {Val::number(3)}));
    bad += is_nil_msg(L.call("SetUpdate", {Val::string("x")}));
    std::vector<Val> nr = L.call("SetAdd", {Val::number(1), Val::vector(0, 0, 0), Val::angle(0, 0, 0), Val::number(0),
                                            Val::number(0), Val::number(0), Val::number(5)});
    Val evt = Val::table();
    std::vector<Val> ev0 = L.call("SetEvents", {evt});
    std::vector<Val> gen0 = L.call("SetGeneration", {});
    std::vector<Val> ob0 = L.call("ObjectBounds", {Val::number(1)});
    CHECK(bad == 8 && is_nil_msg(nr) && str_of(nr, 2) == "not_ready" && ev0.size() == 1 &&
              evt.tab->field("count").num == 0 && gen0.size() == 3 && gen0[0].type == Type::Number && ob0.size() == 1 &&
              ob0[0].type == Type::Nil && L.st.empty(),
          "bad arguments (missing, type 9, no Vector, a negative user, state 9, bits 300, no table, a string id): %d of 8 "
          "answered with nil + message; SetAdd without the disc: nil, \"%s\"; SetEvents: count 0; ObjectBounds: nil", bad,
          str_of(nr, 2).c_str());

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the world checks need the disc\n");
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    gsa1::make_dirs(fake_appdata);
    gsa1::Config cfg;
    cfg.disc = gdi;
    std::string err;
    CHECK(gsa1::save_config(cfg, err), "config written to the scratch APPDATA (%s)", err.c_str());
    L.call("Init", {});
    std::string st = "loading";
    for (int polls = 0; st == "loading" && polls < 30000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        st = str_of(L.call("InitPoll", {}), 0);
    }
    gsa1::Session *se = gsa1::mod::session();
    std::vector<sa1_collision_tri> tris;
    floor_quad(tris, -6000, 12000, -4000, 4000);
    bool world = st == "ready" && se && se->set_world(tris, err);
    CHECK(world, "the disc (%s) and a flat floor%s%s", st.c_str(), err.empty() ? "" : ": ", err.c_str());
    if (!world) {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    install_mesh_library(L);
    std::vector<sa1_event> sev;
    auto pair = [&](int32_t id, float sy, uint32_t b) { se->tick(id, 0.0f, sy, 0.0f, b, 1.0f / 30.0f); };

    // ---- ObjectInfo -------------------------------------------------------------------------------------------------
    Val info = Val::table();
    L.call("ObjectInfo", {info});
    int avail = 0;
    bool names = true;
    for (int t = 1; t <= 4; t++) {
        Val e = info.tab->at(t);
        if (e.type != Type::Table) {
            names = false;
            continue;
        }
        avail += e.tab->field("available").b ? 1 : 0;
        names = names && e.tab->field("type").num == t && e.tab->field("range").num == 1600;
    }
    CHECK(info.tab->field("count").num == 4 && avail == 4 && names,
          "ObjectInfo: %g types, %d available (RING, O_GRING, ITEMBOX, ITEMBOX_AIR), range 1600 HU",
          info.tab->field("count").num, avail);

    // ---- a RING ahead of Sonic ------------------------------------------------------------------------------------------
    {
        const float sp[3] = {-4000.0f, 0.0f, 8.0f};
        int32_t id = se->create(SA1_CHAR_SONIC, sp, 0.0f, err);
        for (int i = 0; i < 10; i++) pair(id, 0, 0);
        poll(L);
        float x0 = se->get(id)->st.position[0], y0 = se->get(id)->st.position[1];
        const float rp[3] = {x0 + 60.0f, y0, 20.0f};
        double rid = add(L, SA1_OBJTYPE_RING, rp[0], rp[1], rp[2], 0, 0, 0, 321);
        int32_t r0 = se->get(id)->st.rings;
        std::vector<Ev> all;
        double gone_state_step = -1;        // the character's state step when the GONE was polled (cl_objects.lua's age)
        for (int i = 0; i < 40; i++) {
            pair(id, 1.0f, 0);
            std::vector<Ev> e = poll(L);
            for (const Ev &v : e) {
                if (v.kind == SA1_SET_EVENT_GONE && v.user == 321) gone_state_step = se->get(id)->st.step;
            }
            all.insert(all.end(), e.begin(), e.end());
        }
        const Ev *gone = first_kind(all, SA1_SET_EVENT_GONE, 321);
        float td = gone ? dist(gone->pos, rp) : -1.0f;
        // the age the addon sends ((state step - touch step) / 60): the touch 16 steps before bit 15 cleared (rings review
        // R.2.5), the event within the pair the state reports
        double age_steps = gone ? gone_state_step - gone->touch_step : -1;
        CHECK(gone && gone->touch_step > 0 && gone->step - gone->touch_step >= 14 && gone->step - gone->touch_step <= 18 &&
                  gone_state_step >= gone->step && gone_state_step - gone->step <= 2 && age_steps <= 20,
              "the GONE's steps: the touch at %g, the event at %g (%g steps: the sparkle), the character's state at %g - the "
              "report's age %.3f s", gone ? gone->touch_step : -1.0, gone ? gone->step : -1.0,
              gone ? gone->step - gone->touch_step : -1.0, gone_state_step, age_steps / 60.0);
        CHECK(rid > 0 && count_kind(all, SA1_SET_EVENT_GONE, 321) == 1 && gone && gone->type == SA1_OBJTYPE_RING &&
                  gone->id == rid && gone->character == id && td <= 64.0f && se->get(id)->st.rings - r0 == 1,
              "a RING 60 HU ahead, Sonic runs: %d GONE (user 321, character %g), the touch %.1f HU from the ring (cause %d), "
              "rings +%d", count_kind(all, SA1_SET_EVENT_GONE, 321), gone ? gone->character : -1.0, (double)td,
              gone ? gone->cause : -1, (int)(se->get(id)->st.rings - r0));
        L.call("SetRemove", {Val::number(rid)});
        se->destroy(id);
    }

    // ---- a Ring line of 8 along the run ---------------------------------------------------------------------------------
    {
        const float sp[3] = {-2500.0f, 0.0f, 8.0f};
        int32_t id = se->create(SA1_CHAR_SONIC, sp, 0.0f, err);
        for (int i = 0; i < 10; i++) pair(id, 0, 0);
        poll(L);
        float x0 = se->get(id)->st.position[0], y0 = se->get(id)->st.position[1];
        // centred 260 HU ahead: rings from x0 + 120 to x0 + 400 (the entity's forward = +x at yaw 0)
        double lid = add(L, SA1_OBJTYPE_O_GRING, x0 + 260.0f, y0, 20.0f, 8, 40, 0, 400);
        std::vector<Val> gn = L.call("SetGeneration", {});
        int32_t r0 = se->get(id)->st.rings;
        std::vector<Ev> all;
        double bits = 0;
        for (int i = 0; i < 60; i++) {
            pair(id, 1.0f, 0);
            std::vector<Ev> e = poll(L);
            for (const Ev &v : e) {
                if (v.kind == SA1_SET_EVENT_USERBITS && v.user == 400 && v.index == 0) bits = v.bits;
            }
            all.insert(all.end(), e.begin(), e.end());
        }
        CHECK(lid > 0 && gn.size() == 3 && gn[2].num >= 1 && bits == 255 && se->get(id)->st.rings - r0 == 8,
              "a Ring line of 8 ahead along Sonic's run: USERBITS of record 0 up to 0x%02X, rings +%d (the game's line "
              "runs along the entity's forward)", (unsigned)bits, (int)(se->get(id)->st.rings - r0));
        L.call("SetRemove", {Val::number(lid)});
        se->destroy(id);
    }

    // ---- 0.9.4.1: THE LAYOUT, measured (the owner's refusals: "the touch was 216 units from it (at most 64)") ----------
    // The game's own ring tasks (the O_GRING task's ring children: their twp->pos is where the ring's display draws it)
    // against ring_positions (the module's; feat/sh_objects.lua O.RingPositions is the same layout: feat_objects_test.lua
    // compares them), at several entity angles; Sonic put on each predicted ring: the USERBITS event names exactly that
    // ring's record and bit. Then Sonic RUNS through a line: each USERBITS event's touch is the record's last touched ring
    // (libsa1's frozen latch), not the rings it adds (their bits come ~16 steps later, after the sparkle) - the cause of
    // the 0.9.4 refusals, which the server's check now allows for (sh_objects.lua O.CheckEvent).
    {
        Val cfgt = Val::table();
        cfgt.tab->set(Val::string("ring_window"), Val::number(70));
        cfgt.tab->set(Val::string("box_window"), Val::number(32));
        L.call("SetConfig", {cfgt});
        const float base[3] = {0.0f, 2500.0f, 8.0f};
        int32_t id = se->create(SA1_CHAR_SONIC, base, 0.0f, err);
        for (int i = 0; i < 10; i++) pair(id, 0, 0);
        poll(L);
        struct sa1g_world *w = sa1_character_world(se->ctx(), id);
        float home[3];
        sa1_of(base, home);
        auto go_home = [&]() {
            tele(w, home[0], home[1] + 1.0f, home[2]);
            for (int i = 0; i < 4; i++) pair(id, 0, 0);
        };
        auto group_desc = [&](uint32_t count, float size, uint32_t shape, float p, float y, float r) {
            ob::Desc d;
            d.type = SA1_OBJTYPE_O_GRING;
            d.pos[0] = base[0] + 600.0f;
            d.pos[1] = base[1];
            d.pos[2] = 700.0f;
            d.ang[0] = p;
            d.ang[1] = y;
            d.ang[2] = r;
            d.p[0] = (float)count;
            d.p[1] = size;
            d.p[2] = (float)shape;
            return d;
        };
        auto add_desc = [&](const ob::Desc &d, double user) {
            std::vector<Val> r = L.call("SetAdd", {Val::number(d.type), Val::vector(d.pos[0], d.pos[1], d.pos[2]),
                                                   Val::angle(d.ang[0], d.ang[1], d.ang[2]), Val::number(d.p[0]),
                                                   Val::number(d.p[1]), Val::number(d.p[2]), Val::number(user)});
            return r.size() == 1 && r[0].type == Type::Number ? r[0].num : 0.0;
        };
        // the live rings of every record of d (all within the window) at their predicted places
        auto places = [&](const ob::Desc &d, std::string &note) {
            std::vector<ob::RingPos> pred;
            std::vector<sa1_set_record> recs;
            std::string e2;
            ob::ring_positions(d, pred);
            ob::make_records(d, 4.0f, 1, recs, e2);
            std::vector<uint32_t> all;
            for (uint32_t k = 0; k < recs.size(); k++) all.push_back(k);
            go_home();
            double oid = add_desc(d, 900);
            PlaceCheck pc;
            for (int i = 0; i < 60; i++) {
                pair(id, 0, 0);
                pc = check_places(w, recs, all, pred);
                if (pc.records == (int)recs.size() && pc.rings == (int)pred.size()) break;
            }
            poll(L);
            L.call("SetRemove", {Val::number(oid)});
            for (int i = 0; i < 3; i++) pair(id, 0, 0);
            poll(L);
            note = gsa1::format("%d / %zu records, %d / %zu rings, worst %.2f HU", pc.records, recs.size(), pc.rings, pred.size(),
                          (double)pc.worst);
            return oid > 0 && pc.records == (int)recs.size() && pc.rings == (int)pred.size() && pc.worst <= 1.0f;
        };
        // Sonic put on predicted rings (every one, or `sample` of the live ones): the event names its record and bit
        auto touches = [&](const ob::Desc &d, int sample, std::string &note) {
            std::vector<ob::RingPos> pred;
            std::vector<sa1_set_record> recs;
            std::string e2;
            ob::ring_positions(d, pred);
            ob::make_records(d, 4.0f, 1, recs, e2);
            go_home();
            double oid = add_desc(d, 901);
            std::vector<uint32_t> all;
            for (uint32_t k = 0; k < recs.size(); k++) all.push_back(k);
            for (int i = 0; i < 12; i++) pair(id, 0, 0);
            poll(L);
            // the live records (the window keeps the first 70 ring tasks of a big circle: every record at its centre)
            std::vector<bool> live(recs.size(), false);
            for (const GTask &g : gring_tasks(w)) {
                for (uint32_t r : all) {
                    bool fits = dist(g.h, recs[r].position) <= 2.0f && !g.kids.empty();
                    for (const GKid &kd : g.kids) {
                        bool one = false;
                        for (const ob::RingPos &p : pred) one = one || (p.record == r && p.bit == kd.bit && dist(p.pos, kd.h) < 1.0f);
                        fits = fits && one;
                    }
                    if (fits) live[r] = true;
                }
            }
            std::vector<const ob::RingPos *> todo;
            for (const ob::RingPos &p : pred) {
                if (live[p.record]) todo.push_back(&p);
            }
            if (sample > 0 && (int)todo.size() > sample) {
                std::vector<const ob::RingPos *> s2;
                for (int k = 0; k < sample; k++) s2.push_back(todo[(size_t)k * todo.size() / (size_t)sample]);
                todo = s2;
            }
            std::vector<uint32_t> have(recs.size(), 0u);
            int good = 0, extra = 0;
            float worst_touch = 0.0f;
            for (const ob::RingPos *p : todo) {
                float s[3];
                sa1_of(p->pos, s);
                bool named = false;
                for (int i = 0; i < 40 && !named; i++) {
                    if (i < 2) tele(w, s[0], s[1], s[2]);
                    pair(id, 0, 0);
                    for (const Ev &e : poll(L)) {
                        if (e.kind != SA1_SET_EVENT_USERBITS || e.user != 901 || e.index < 0 || e.index >= (int)have.size()) continue;
                        uint32_t add = (uint32_t)e.bits & ~have[(size_t)e.index];
                        have[(size_t)e.index] |= (uint32_t)e.bits;
                        if (e.index == (int)p->record && (add & p->bit)) {
                            named = true;
                            extra += add != p->bit;
                            worst_touch = std::max(worst_touch, dist(e.pos, p->pos));
                        } else {
                            extra++;
                        }
                    }
                }
                good += named;
                go_home();
                poll(L);
            }
            L.call("SetRemove", {Val::number(oid)});
            for (int i = 0; i < 3; i++) pair(id, 0, 0);
            poll(L);
            note = gsa1::format("%d of %zu touched rings named by their record and bit (%d other rings taken with them), the touch "
                          "within %.1f HU", good, todo.size(), extra, (double)worst_touch);
            return oid > 0 && !todo.empty() && good == (int)todo.size();
        };
        const float angs[6][3] = {{0, 0, 0}, {0, 37, 0}, {0, 90, 0}, {0, 200, 0}, {30, 37, 0}, {-60, 120, 20}};
        int pl_good = 0, pl_n = 0;
        std::string pl_bad;
        for (const auto &a : angs) {
            const ob::Desc ds[3] = {group_desc(10, 40, 0, a[0], a[1], a[2]), group_desc(20, 40, 0, a[0], a[1], a[2]),
                                    group_desc(7, 80, 1, a[0], a[1], a[2])};
            for (const ob::Desc &d : ds) {
                std::string note;
                pl_n++;
                if (places(d, note)) pl_good++;
                else pl_bad += gsa1::format(" [%s of %g at (%g %g %g): %s]", d.p[2] == 1 ? "circle" : "line", (double)d.p[0],
                                      (double)a[0], (double)a[1], (double)a[2], note.c_str());
            }
        }
        CHECK(pl_good == pl_n,
              "the game's own ring tasks of a line of 10 and of 20 (40 HU apart) and a circle of 7 (radius 80) at yaw 0 / 37 "
              "/ 90 / 200, pitch 30 and (-60 120 20): every ring within 1 HU of ring_positions' place for its record and bit "
              "(%d of %d objects)%s", pl_good, pl_n, pl_bad.c_str());
        int t_good = 0, t_n = 0;
        std::string t_notes;
        const ob::Desc td[4] = {group_desc(20, 100, 0, 0, 37, 0), group_desc(20, 100, 0, 30, 37, 0),
                                group_desc(7, 200, 1, 0, 200, 0), group_desc(7, 200, 1, -60, 120, 20)};
        for (const ob::Desc &d : td) {
            std::string note;
            t_n++;
            if (touches(d, 0, note)) t_good++;
            t_notes += gsa1::format(" [%s: %s]", d.p[2] == 1 ? "circle" : "line", note.c_str());
        }
        CHECK(t_good == t_n, "Sonic put on each predicted ring of a line of 20 (100 HU apart; yaw 37, then pitched 30) and a "
              "circle of 7 (radius 200; yaw 200, then (-60 120 20)): each USERBITS event names that ring's record and bit "
              "(%d of %d objects)%s", t_good, t_n, t_notes.c_str());

        // ---- the run: the touch a USERBITS event carries ----------------------------------------------------------------
        {
            ob::Desc d;
            d.type = SA1_OBJTYPE_O_GRING;
            d.pos[0] = base[0] + 900.0f;
            d.pos[1] = base[1];
            d.pos[2] = 20.0f;
            d.p[0] = 20;
            d.p[1] = 40;
            d.p[2] = 0;
            std::vector<ob::RingPos> pred;
            ob::ring_positions(d, pred);
            go_home();
            for (int i = 0; i < 20; i++) pair(id, 0, 0);
            double oid = add_desc(d, 902);
            for (int i = 0; i < 6; i++) pair(id, 0, 0);
            poll(L);
            // the visible ring draws: every ring of the line drawn at its predicted place, nothing of it drawn elsewhere
            se->render(id, 1.0f);
            gsa1::Character *c = se->get(id);
            std::vector<int> drawn_at(pred.size(), 0);
            int stray = 0;
            for (const sa1_draw &dr : c->r_draws) {
                if (!(dr.flags & SA1_DRAW_OBJECT) || (dr.flags & SA1_DRAW_SHADOW) || dr.prim != SA1_PRIM_TRIANGLES) continue;
                uint32_t end = std::min(dr.first + dr.count, c->r_triangles);
                for (uint32_t t = dr.first; t < end; t++) {
                    for (int k = 0; k < 3; k++) {
                        const float *v = &c->r_tpos[(size_t)t * 9u + (size_t)k * 3u];
                        int hit = -1;
                        for (size_t r = 0; r < pred.size() && hit < 0; r++) {
                            if (dist(v, pred[r].pos) <= 24.0f) hit = (int)r;
                        }
                        if (hit >= 0) drawn_at[(size_t)hit]++;
                        else stray++;
                    }
                }
            }
            int drawn = 0;
            for (int k : drawn_at) drawn += k > 0;
            CHECK(drawn == (int)pred.size() && stray == 0,
                  "the line's draws (SA1_DRAW_OBJECT, its blob shadows aside): %d of %zu rings drawn within 24 HU of their "
                  "predicted place, %d vertices elsewhere", drawn, pred.size(), stray);
            std::vector<uint32_t> have(4, 0u);
            int n = 0, far_added = 0, far_any = 0, taken = 0;
            float worst_added = 0.0f, worst_any = 0.0f;
            for (int i = 0; i < 240; i++) {
                pair(id, 1.0f, 0);
                for (const Ev &e : poll(L)) {
                    if (e.kind != SA1_SET_EVENT_USERBITS || e.user != 902 || e.index < 0 || e.index > 3) continue;
                    uint32_t add = (uint32_t)e.bits & ~have[(size_t)e.index];
                    have[(size_t)e.index] |= (uint32_t)e.bits;
                    float da = 1e9f, dany = 1e9f;
                    for (const ob::RingPos &p : pred) {
                        if ((int)p.record != e.index) continue;
                        dany = std::min(dany, dist(e.pos, p.pos));
                        if (p.bit & add) da = std::min(da, dist(e.pos, p.pos));
                    }
                    for (uint32_t b = add; b; b &= b - 1u) taken++;
                    n++;
                    far_added += da > 64.0f;
                    far_any += dany > 64.0f;
                    worst_added = std::max(worst_added, da);
                    worst_any = std::max(worst_any, dany);
                }
            }
            CHECK(n > 0 && taken == 20 && far_any == 0 && far_added > 0,
                  "Sonic runs through a line of 20 (40 HU apart): %d USERBITS events, %d rings; every event's touch within "
                  "64 HU of a ring of its record (worst %.0f HU), but %d of them more than 64 HU from every ring they add "
                  "(worst %.0f HU: the touch is the record's latest ring, the bits come after the sparkle - the owner's "
                  "0.9.4 refusals)", n, taken, (double)worst_any, far_added, (double)worst_added);
            L.call("SetRemove", {Val::number(oid)});
            for (int i = 0; i < 3; i++) pair(id, 0, 0);
            poll(L);
        }

        // ---- 0.9.4.1: circles of N rings from several records (N = 7, 12, 64, 127, 128) -----------------------------
        {
            struct CircleCase { uint32_t n; float r, yaw, pitch; };
            const CircleCase cases[] = {{7, 120, 0, 0},    {7, 120, 200, 30},  {12, 200, 0, 0},    {12, 200, 37, 30},
                                        {64, 800, 0, 0},   {64, 800, 90, -45}, {127, 1200, 0, 0},  {127, 1200, 200, 20},
                                        {128, 1200, 0, 0}, {128, 1200, 37, 30}};
            int good = 0, n = 0;
            std::string bad;
            for (const CircleCase &cc : cases) {
                n++;
                ob::Desc d = group_desc(cc.n, cc.r, 1, cc.pitch, cc.yaw, 0);
                std::vector<ob::RingPos> pred;
                std::vector<sa1_set_record> recs;
                std::string e2;
                ob::ring_positions(d, pred);
                ob::make_records(d, 4.0f, 0xFFFFF0u, recs, e2);
                // the records in slices of at most 70 ring tasks (the window), added straight to libsa1
                uint32_t per = (uint32_t)recs[0].params[0];
                uint32_t slice = std::max(1u, 70u / per);
                PlaceCheck tot;
                for (uint32_t a = 0; a < recs.size(); a += slice) {
                    go_home();
                    std::vector<uint32_t> ids, want;
                    for (uint32_t k = a; k < std::min<uint32_t>(a + slice, (uint32_t)recs.size()); k++) {
                        uint32_t rid = 0;
                        if (sa1_set_add(se->ctx(), &recs[k], &rid) == SA1_OK) ids.push_back(rid);
                        want.push_back(k);
                    }
                    PlaceCheck pc;
                    for (int i = 0; i < 60; i++) {
                        pair(id, 0, 0);
                        pc = check_places(w, recs, want, pred);
                        if (pc.records == (int)want.size() && pc.rings == (int)(want.size() * per)) break;
                    }
                    tot.records += pc.records;
                    tot.rings += pc.rings;
                    tot.worst = std::max(tot.worst, pc.worst);
                    for (uint32_t rid : ids) sa1_set_remove(se->ctx(), rid);
                    for (int i = 0; i < 3; i++) pair(id, 0, 0);
                    poll(L);
                }
                // the evenly spaced places (ring_positions: place p at p * 360 / N, at the radius, each once)
                std::vector<int> once(cc.n, 0);
                for (const ob::RingPos &p : pred) once[p.place]++;
                bool even = pred.size() == cc.n;
                for (int k : once) even = even && k == 1;
                // touches through SetAdd: every ring of N <= 64, 12 of the live ones of the bigger ones
                std::string tnote;
                bool touched = touches(d, cc.n <= 64 ? 0 : 12, tnote);
                bool ok = even && tot.records == (int)recs.size() && tot.rings == (int)cc.n && tot.worst <= 1.0f && touched;
                good += ok;
                if (!ok || g_verbose) {
                    bad += gsa1::format(" [%u rings (%zu records of %u) radius %g at yaw %g pitch %g: %d records %d rings live, "
                                  "worst %.2f HU, places %s; %s]", cc.n, recs.size(), per, (double)cc.r, (double)cc.yaw,
                                  (double)cc.pitch, tot.records, tot.rings, (double)tot.worst, even ? "even" : "NOT even",
                                  tnote.c_str());
                }
            }
            CHECK(good == n,
                  "Ring circles of 7, 12, 64, 127 and 128 rings (1 x 7, 2 x 6, 16 x 4, 127 x 1, 32 x 4 records, each turned "
                  "by k * 360 / N), each at two angles: the game puts every ring at its evenly spaced place (within 1 HU, "
                  "records added in slices of the 70-ring window), and Sonic put on a ring gets an event naming that ring's "
                  "record and bit (%d of %d)%s", good, n, bad.c_str());
        }
        L.call("SetClear", {});
        se->destroy(id);
    }

    // ---- a ground Item Box (10 Rings): Sonic lands on its lid ------------------------------------------------------------
    {
        const float bp[3] = {-1000.0f, 0.0f, 0.0f};
        const float sp[3] = {bp[0] - 200.0f, 0.0f, 8.0f};
        int32_t id = se->create(SA1_CHAR_SONIC, sp, 0.0f, err);
        double bid = add(L, SA1_OBJTYPE_ITEMBOX, bp[0], bp[1], bp[2], 3, 0, 0, 501);
        for (int i = 0; i < 32; i++) pair(id, 0, 0);
        poll(L);
        struct sa1g_world *w = sa1_character_world(se->ctx(), id);
        int32_t r0 = se->get(id)->st.rings;
        tele(w, bp[0] / 4.0f, 30.0f, -bp[1] / 4.0f);       // SA1 = (x, z, -y) / 4: 30 units above the lid
        std::vector<Ev> all;
        for (int i = 0; i < 60; i++) {
            pair(id, 0, 0);
            std::vector<Ev> e = poll(L);
            all.insert(all.end(), e.begin(), e.end());
        }
        const Ev *br = first_kind(all, SA1_SET_EVENT_BROKEN, 501);
        float td = br ? dist(br->pos, bp) : -1.0f;
        CHECK(bid > 0 && count_kind(all, SA1_SET_EVENT_BROKEN, 501) == 1 && count_kind(all, SA1_SET_EVENT_GONE, 501) == 0 &&
                  br && br->cause == SA1_SET_CAUSE_BODY && td <= 80.0f && ((uint32_t)br->cond & 4u) &&
                  se->get(id)->st.rings - r0 == 10,
              "a ground Item Box with 10 Rings, Sonic dropped on its lid: %d BROKEN (condition %04X, cause %d, the touch "
              "%.1f HU from the box), %d GONE, rings +%d", count_kind(all, SA1_SET_EVENT_BROKEN, 501),
              br ? (unsigned)br->cond : 0u, br ? br->cause : -1, (double)td, count_kind(all, SA1_SET_EVENT_GONE, 501),
              (int)(se->get(id)->st.rings - r0));
        L.call("SetRemove", {Val::number(bid)});
        se->destroy(id);
    }

    // ---- an Item Box (Air) with an Extra Life, 40 HU above the floor ------------------------------------------------------
    {
        const float sp[3] = {500.0f, 0.0f, 8.0f};
        int32_t id = se->create(SA1_CHAR_SONIC, sp, 0.0f, err);
        for (int i = 0; i < 10; i++) pair(id, 0, 0);
        float x0 = se->get(id)->st.position[0], y0 = se->get(id)->st.position[1];
        double aid = add(L, SA1_OBJTYPE_ITEMBOX_AIR, x0 + 160.0f, y0, 40.0f, 6, 0, 0, 502);
        for (int i = 0; i < 25; i++) pair(id, 0, 0);       // its 20-step open timer
        poll(L);
        int32_t l0 = se->get(id)->st.lives;
        std::vector<Ev> all;
        for (int i = 0; i < 60; i++) {
            pair(id, i < 30 ? 1.0f : 0.0f, 0);
            std::vector<Ev> e = poll(L);
            all.insert(all.end(), e.begin(), e.end());
        }
        const Ev *gone = first_kind(all, SA1_SET_EVENT_GONE, 502);
        CHECK(aid > 0 && se->get(id)->st.lives - l0 == 1 && count_kind(all, SA1_SET_EVENT_GONE, 502) == 1 && gone &&
                  gone->type == SA1_OBJTYPE_ITEMBOX_AIR,
              "an Item Box (Air) with an Extra Life 40 HU above the floor, Sonic runs into it: lives +%d, %d GONE (cause %d)",
              (int)(se->get(id)->st.lives - l0), count_kind(all, SA1_SET_EVENT_GONE, 502), gone ? gone->cause : -1);
        L.call("SetRemove", {Val::number(aid)});
        se->destroy(id);
    }

    // ---- SetState(BROKEN) in a second character's world (review R.17) ----------------------------------------------------
    {
        const float bp[3] = {2500.0f, 0.0f, 0.0f};
        const float sp[3] = {bp[0] - 200.0f, 0.0f, 8.0f};
        int32_t tid = se->create(SA1_CHAR_TAILS, sp, 0.0f, err);
        double bid = add(L, SA1_OBJTYPE_ITEMBOX, bp[0], bp[1], bp[2], 3, 0, 0, 503);
        for (int i = 0; i < 32; i++) pair(tid, 0, 0);
        se->poll_events(sev);
        struct sa1g_world *w = sa1_character_world(se->ctx(), tid);
        uint32_t tp0 = find_task(w, X_GBOX);
        uint32_t c0 = task_cond(w, tp0), m0 = task_mode(w, tp0);
        int32_t r0 = se->get(tid)->st.rings;
        std::vector<Val> ok = L.call("SetState", {Val::number(bid), Val::number(SA1_SET_STATE_PRESENT | SA1_SET_STATE_BROKEN)});
        int item_se = 0;
        std::vector<Ev> all;
        for (int i = 0; i < 8; i++) {
            pair(tid, 0, 0);
            se->poll_events(sev);
            for (const sa1_event &e : sev) {
                item_se += e.character == (sa1_character_id)tid && e.type == SA1_EVENT_SOUND && e.id == SE_ITEM;
            }
            std::vector<Ev> e = poll(L);
            all.insert(all.end(), e.begin(), e.end());
        }
        int shared = 0;
        for (const Ev &v : all) {
            shared += v.kind == SA1_SET_EVENT_GONE || v.kind == SA1_SET_EVENT_BROKEN || v.kind == SA1_SET_EVENT_USERBITS;
        }
        uint32_t tp1 = find_task(w, X_GBOX);
        uint32_t c1 = task_cond(w, tp1), m1 = task_mode(w, tp1);
        CHECK(ok.size() == 1 && ok[0].b && tp0 && !(c0 & 4u) && m0 < 3 && tp1 && (c1 & 4u) && m1 >= 4 &&
                  se->get(tid)->st.rings == r0 && item_se == 0 && shared == 0,
              "SetState(BROKEN) with Tails near the box: in his world condition %04X mode %u -> %04X mode %u (the shell), "
              "rings unchanged (%d), %d item sounds, %d GONE / BROKEN / USERBITS events (%u in all: the intact box "
              "DESPAWNED, the shell SPAWNED)", c0, m0, c1, m1, (int)se->get(tid)->st.rings, item_se, shared,
              (unsigned)all.size());
        L.call("SetRemove", {Val::number(bid)});
        se->destroy(tid);
    }

    // ---- 120 RINGs ahead of Sonic: the OBJECT batches, nothing skipped (review R.1) ---------------------------------------
    {
        Val cfgt = Val::table();
        cfgt.tab->set(Val::string("ring_window"), Val::number(70));
        cfgt.tab->set(Val::string("box_window"), Val::number(32));
        std::vector<Val> cr = L.call("SetConfig", {cfgt});
        const float sp[3] = {5000.0f, 0.0f, 8.0f};
        int32_t id = se->create(SA1_CHAR_SONIC, sp, 0.0f, err);
        for (int i = 0; i < 5; i++) pair(id, 0, 0);
        float x0 = se->get(id)->st.position[0], y0 = se->get(id)->st.position[1];
        std::vector<double> ids;
        for (int r = 0; r < 12; r++) {
            for (int c = 0; c < 10; c++) {
                ids.push_back(add(L, SA1_OBJTYPE_RING, x0 + 120.0f + 40.0f * r, y0 - 180.0f + 40.0f * c, 20.0f, 0, 0, 0,
                                  1000 + 10 * r + c));
            }
        }
        for (int i = 0; i < 6; i++) pair(id, 0, 0);
        poll(L);
        se->render(id, 1.0f);
        gsa1::Character *c = se->get(id);
        uint32_t want = 0, obj_tris = 0, max_tris = 0, obj_batches = 0, own_blob = 0, ring_blob = 0;
        for (const sa1_draw &d : c->r_draws) {
            uint32_t avail = d.prim == SA1_PRIM_TRIANGLES ? c->r_triangles
                             : d.prim == SA1_PRIM_SPRITES ? (uint32_t)c->r_sprites.size()
                                                          : (uint32_t)c->r_lines.size() / 2u;
            uint32_t n = d.first < avail ? std::min(d.count, avail - d.first) : 0u;
            want += d.prim == SA1_PRIM_TRIANGLES ? n : 2u * n;
            if ((d.flags & SA1_DRAW_OBJECT) && d.prim == SA1_PRIM_TRIANGLES) obj_tris += n;
        }
        for (uint32_t b = 0; b < c->batch_count; b++) {
            const gsa1::RenderBatch &rb = c->batches[b];
            max_tris = std::max(max_tris, rb.triangles);
            obj_batches += (rb.flags & SA1_DRAW_OBJECT) ? 1u : 0u;
            if (rb.flags & SA1_DRAW_SHADOW) {
                if (rb.flags & SA1_DRAW_OBJECT) ring_blob++;
                else own_blob++;
            }
        }
        std::vector<Val> bb = L.call("ObjectBounds", {Val::number(id)});
        // (the window keeps the 70 nearest: the rows from 120 to about 400 HU ahead)
        bool bounds = bb.size() == 6 && bb[0].num <= x0 + 140.0f && bb[3].num >= x0 + 300.0f && bb[1].num <= y0 - 100.0f &&
                      bb[4].num >= y0 + 100.0f;
        size_t added = 0;
        for (double v : ids) added += v > 0;
        CHECK(cr.size() == 1 && cr[0].b && added == 120 && c->out_triangles == want && want > 0 && max_tris <= 8000 &&
                  obj_batches > 0 && own_blob >= 1 && ring_blob >= 1 && obj_tris >= 96u * 20u && bounds,
              "120 RINGs ahead of Sonic (ring window 70): %u triangles drawn of %u in the render (none skipped), at most %u "
              "per batch, %u OBJECT triangles (%u rings' worth) in %u OBJECT batches; Sonic's blob in %u batch(es) without "
              "OBJECT, the rings' blobs in %u with it; ObjectBounds x %.0f .. %.0f", c->out_triangles, want, max_tris,
              obj_tris, obj_tris / 96u, obj_batches, own_blob, ring_blob, bb.size() == 6 ? bb[0].num - x0 : 0.0,
              bb.size() == 6 ? bb[3].num - x0 : 0.0);
        std::vector<Val> go = L.call("SetGameOption", {Val::number(id), Val::number(SA1_GOPT_ITEM_ICON_LIMIT), Val::number(1)});
        CHECK(go.size() == 1 && go[0].b, "SetGameOption(GOPT_ITEM_ICON_LIMIT, 1) accepted (the icon guard)");
        std::vector<Val> g1 = L.call("SetGeneration", {});
        L.call("SetRemove", {Val::number(ids[0])});
        std::vector<Val> g2 = L.call("SetGeneration", {});
        std::vector<Val> cl = L.call("SetClear", {});
        std::vector<Val> g3 = L.call("SetGeneration", {});
        CHECK(g1.size() == 3 && g1[1].num == 120 && g2[1].num == 119 && cl.size() == 1 && cl[0].num == 119 &&
                  g3[1].num == 0 && g3[2].num == 0 && g3[0].num == g1[0].num,
              "SetRemove: %g -> %g objects; SetClear removed %g, %g records left, the same generation", g1.size() ? g1[1].num : -1,
              g2.size() ? g2[1].num : -1, cl.size() ? cl[0].num : -1, g3.size() ? g3[2].num : -1);
        se->destroy(id);
    }

    // ---- 0.9.4b: the range and the screen width (objects2_plan.md 6.3 task 1, owner answer O1) -------------------------------
    {
        auto obj_tris = [&](int32_t cid) {
            se->render(cid, 1.0f);
            gsa1::Character *c = se->get(cid);
            uint32_t n = 0;
            for (const sa1_draw &d : c->r_draws) {
                if ((d.flags & SA1_DRAW_OBJECT) && d.prim == SA1_PRIM_TRIANGLES && d.first < c->r_triangles) {
                    n += std::min(d.count, c->r_triangles - d.first);
                }
            }
            return n;
        };
        auto live_has = [&](int32_t cid, double oid) {
            Val out = Val::table();
            std::vector<Val> r = L.call("SetLive", {Val::number(cid), out});
            int n = r.size() == 2 ? (int)r[0].num : 0;
            for (int i = 0; i < n; i++) {
                if (out.tab->at(2 * i + 1).num == oid) return true;
            }
            return false;
        };
        auto config = [&](double range, double view_tan) {
            Val t = Val::table();
            t.tab->set(Val::string("ring_window"), Val::number(64));
            t.tab->set(Val::string("box_window"), Val::number(32));
            t.tab->set(Val::string("range"), Val::number(range));
            t.tab->set(Val::string("view_tan"), Val::number(view_tan));
            return L.call("SetConfig", {t});
        };
        auto info_range = [&]() {
            Val info = Val::table();
            L.call("ObjectInfo", {info});
            Val e = info.tab->at(1);
            return e.type == Type::Table ? e.tab->field("range").num : -1.0;
        };
        // the range: a RING 3,000 HU ahead
        std::vector<Val> c0 = config(0, 0);
        double r0 = info_range();
        const float sp[3] = {-2000.0f, -3000.0f, 8.0f};
        int32_t id = se->create(SA1_CHAR_SONIC, sp, 0.0f, err);
        for (int i = 0; i < 6; i++) pair(id, 0, 0);
        float x0 = se->get(id)->st.position[0], y0 = se->get(id)->st.position[1];
        double ahead_ring = add(L, SA1_OBJTYPE_RING, x0 + 3000.0f, y0, 20.0f, 0, 0, 0, 3000);
        for (int i = 0; i < 6; i++) pair(id, 0, 0);
        bool live_1600 = live_has(id, ahead_ring);
        uint32_t tris_1600 = obj_tris(id);
        std::vector<Val> c1 = config(4800, 0);
        double r1 = info_range();
        for (int i = 0; i < 6; i++) pair(id, 0, 0);
        bool live_4800 = live_has(id, ahead_ring);
        uint32_t tris_4800 = obj_tris(id);
        CHECK(c0.size() == 1 && c0[0].b && c1.size() == 1 && c1[0].b && r0 == 1600 && r1 == 4800 && ahead_ring > 0 &&
                  !live_1600 && tris_1600 == 0 && live_4800 && tris_4800 >= 96,
              "SetConfig{range = 4800}: ObjectInfo range %g -> %g HU; a RING 3,000 HU ahead of Sonic: with the game's "
              "1,600 not running (%u object triangles drawn), with 4,800 running (SetLive) and drawn (%u triangles)", r0, r1,
              tris_1600, tris_4800);
        L.call("SetRemove", {Val::number(ahead_ring)});
        // the width: a RING 50 degrees off the camera's forward, 800 HU from the world's virtual eye (40 SA1 units = 160 HU
        // behind the character, 7 = 28 HU up, level; the camera yaw 0 looks along +x)
        const double a = 50.0 * 3.14159265358979 / 180.0;
        float ex = x0 - 160.0f, ez = se->get(id)->st.position[2] + 28.0f;
        double side = add(L, SA1_OBJTYPE_RING, ex + 800.0f * (float)std::cos(a), y0 + 800.0f * (float)std::sin(a), ez, 0, 0,
                          0, 3001);
        std::vector<Val> c2 = config(4800, 0);
        for (int i = 0; i < 6; i++) pair(id, 0, 0);
        bool side_live = live_has(id, side);
        uint32_t tris_43 = obj_tris(id);
        std::vector<Val> c3 = config(4800, 1.873);
        for (int i = 0; i < 4; i++) pair(id, 0, 0);
        uint32_t tris_wide = obj_tris(id);
        std::vector<Val> c4 = config(4800, 0);
        for (int i = 0; i < 4; i++) pair(id, 0, 0);
        uint32_t tris_back = obj_tris(id);
        CHECK(side > 0 && c2.size() == 1 && c3.size() == 1 && c3[0].b && side_live && tris_43 == 0 && tris_wide >= 96 &&
                  tris_back == 0,
              "a RING 50 degrees off the camera's forward (running: %s): view_tan 0 (the game's 4:3, +-35 degrees) draws "
              "%u object triangles, 1.873 (3440 x 1440 at fov 92.5) %u, 0 again %u", side_live ? "yes" : "no", tris_43,
              tris_wide, tris_back);
        // refusals change nothing
        std::vector<Val> b1 = config(13000, 0), b2 = config(1000, 0), b5 = config(4800, 5.0), b6 = config(4800, 0.5);
        Val t3 = Val::table();
        t3.tab->set(Val::string("ring_window"), Val::number(201));
        std::vector<Val> b3 = L.call("SetConfig", {t3});
        Val t4 = Val::table();
        t4.tab->set(Val::string("box_window"), Val::number(101));
        std::vector<Val> b4 = L.call("SetConfig", {t4});
        double r2 = info_range();
        std::vector<Val> c5 = config(12000, 4.0);
        double r3 = info_range();
        CHECK(is_nil_msg(b1) && str_of(b1, 2) == "bad_argument" && is_nil_msg(b2) && is_nil_msg(b3) && is_nil_msg(b4) &&
                  is_nil_msg(b5) && is_nil_msg(b6) && r2 == 4800 && c5.size() == 1 && c5[0].b && r3 == 12000,
              "refused (\"%s\", nothing changed: range still %g HU): range 13,000 and 1,000 HU, ring_window 201, box_window "
              "101, view_tan 5 and 0.5; the maxima accepted (range 12,000 HU -> %g, view_tan 4)", str_of(b1, 2).c_str(),
              r2, r3);
        config(0, 0);
        L.call("SetClear", {});
        se->destroy(id);
    }

    std::vector<Val> ga = L.call("SetGeneration", {});
    L.call("Shutdown", {});
    std::vector<Val> gb = L.call("SetGeneration", {});
    CHECK(ga.size() == 3 && gb.size() == 3 && gb[0].num != ga[0].num && L.st.empty(),
          "gsa1.Shutdown: the objects forgotten with the context (generation %g -> %g)", ga.size() ? ga[0].num : -1,
          gb.size() ? gb[0].num : -1);
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
