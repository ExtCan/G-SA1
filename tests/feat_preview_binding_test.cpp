// feat_preview_binding_test: the game's own rings and item boxes without a character - the feature "preview"
// (src/module/bind_preview.cpp, src/core/preview.*; round 0.9.4b, sadc docs/research/objects2_plan.md 6.3 task 2 with its
// Review R.5 / R.6) - and the objects feature's SetLive (bind_objects.cpp, review R.6). Linked like binding_test (the
// module's objects, libsa1, the mock Lua stack of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi.
//
//   feat_preview_binding_test [--gdi GAME.gdi] [--verbose]
//
// Without the disc: gsa1.FEATURES.preview = 1, the functions registered, gsa1.PREVIEW holds libsa1's numbers; bad
// arguments come back as nil + message; PreviewAdd says "not_ready".
// With the disc (libsa1's numbers: LIB tests/preview_test.c, 094b-lib-preview's api_notes):
//   * PreviewTypes: RING / O_GRING / ITEMBOX / ITEMBOX_AIR available, rotation OUTER / INNER / NONE / OUTER, settle 0 / 0 /
//     47 / 23;
//   * 0.9.4d: a RING copy's bounds over one turn (90 pairs) - its height constant, its width / height from below 0.4 to
//     above 0.95, at least 4 pairs inside the spawn-menu pictures' three-quarter window 0.72-0.90 (feat/cl_objicons.lua
//     I.FACE, I.RingAspect: the ring stands upright and turns about z);
//   * PreviewAdd of every class and contents (the nine of both boxes, a broken ground box) with the kinds Sonic and
//     Knuckles: once settled, PreviewRender's batches hold the triangle counts of libsa1's measurement (ring 96, ground
//     box 116, broken 54, air box 98), every draw is an OBJECT draw, every textured batch's texture resolves through
//     gsa1.Texture(kind, ...), the object-space bounds are libsa1's (x 4 HU); the Extra Life box draws its kind's panel
//     texture (Sonic 2:31, Knuckles 2:0: the table feat/cl_objview.lua uses for the Dreamcast logo) and 10 Rings does not;
//   * kinds 1, 4 and 8 (Eggman, Tikal, Super Sonic): "unsupported";
//   * PreviewRingPlaces of a Ring line (10 at 40 HU) and Ring circles (7 at 80 HU, 12 and 128 as 0.9.4.1 splits them),
//     each at yaw 0 / 37 / 200 and given as the ENTITY's description (review R.5): every ring within 0.01 HU of
//     objects::ring_positions (0.9.4.1's layout, measured against the game by feat_objects_binding_test) with the same
//     record and bit;
//   * PreviewEmitBatch streams like EmitBatch (the vertices of the batch through the mesh library);
//   * a fault injected through libsa1's test hook (sa1pv_test_fault): PreviewTick says "fault", PreviewClear and a new
//     PreviewAdd work again; PreviewRemove -> PreviewInfo "not_found";
//   * SetLive (review R.6): with Sonic on a flat floor, a RING near him, one 9,000 HU away, a Ring line of 20 (3 records)
//     and an Item Box: SetLive lists exactly the (object, record) pairs that had a SPAWNED and no later DESPAWNED, the far
//     ring not; an unknown character: "not_found";
//   * gsa1.Shutdown: every id "not_ready" / "not_found" afterwards.
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
#include <map>
#include <set>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "mock_lua.hpp"
#include "../src/core/config.hpp"
#include "../src/core/objects.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"

namespace ob = gsa1::objects;

// libsa1's test hook (LIB src/sa1_preview.h): a fault forced into a copy - its kind's showcase faults at its next pair
extern "C" sa1_status sa1pv_test_fault(sa1_context *ctx, uint32_t id);

namespace {

bool g_verbose = false;

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1.0;
}

Val nums(std::initializer_list<double> v)
{
    Val t = Val::table();
    int i = 1;
    for (double d : v) t.tab->set(Val::number(i++), Val::number(d));
    return t;
}

Val desc(int kind, int type, double p1, double p2, double p3, int state = 1, int bits = 0)
{
    Val t = Val::table();
    t.tab->set(Val::string("kind"), Val::number(kind));
    t.tab->set(Val::string("type"), Val::number(type));
    t.tab->set(Val::string("params"), nums({p1, p2, p3}));
    t.tab->set(Val::string("state"), Val::number(state));
    t.tab->set(Val::string("user_bits"), Val::number(bits));
    return t;
}

void tick_pairs(MockLua &L, int n)
{
    for (int i = 0; i < n; i++) L.call("PreviewTick", {Val::number(1.0 / 30.0)});
}

struct Shot {
    bool ok = false;
    int batches = 0, tris = 0, object_tris = 0, textured = 0, resolved = 0;
    double gen = -1;
    std::set<std::pair<int, int>> tex;          // (archive, texture) of the textured batches
    double b[6] = {0, 0, 0, 0, 0, 0};           // PreviewInfo bounds
    bool settled = false;
    double steps = 0;
};

// renders copy id (alpha 1) and reads its batches, textures and bounds
Shot shot(MockLua &L, double id, int kind)
{
    Shot s;
    std::vector<Val> r = L.call("PreviewRender", {Val::number(id), Val::number(1)});
    if (r.size() != 4 || r[0].type != Type::Number) {
        if (g_verbose) std::printf("    render %g: %s\n", id, str_of(r, 1).c_str());
        return s;
    }
    s.gen = r[1].num;
    Val bt = Val::table();
    std::vector<Val> br = L.call("PreviewBatches", {Val::number(id), bt});
    int n = (int)num_of(br, 0);
    s.batches = n;
    for (int i = 1; i <= n; i++) {
        Val b = bt.tab->at(i);
        if (b.type != Type::Table) continue;
        int tris = (int)b.tab->field("tris").num;
        s.tris += tris;
        if ((int)b.tab->field("flags").num & SA1_DRAW_OBJECT) s.object_tris += tris;
        int ar = (int)b.tab->field("archive").num, tx = (int)b.tab->field("tex").num;
        if (g_verbose) {
            std::printf("    copy %g batch %d: archive %d tex %d tris %d flags %X key %s\n", id, i, ar, tx, tris,
                        (unsigned)b.tab->field("flags").num, b.tab->field("key").str.c_str());
        }
        if (ar >= 0 && tx >= 0) {
            s.textured++;
            s.tex.insert(std::make_pair(ar, tx));
            std::vector<Val> ti = L.call("Texture", {Val::number(kind), Val::number(tx), Val::number(ar)});
            if (ti.size() >= 1 && ti[0].type == Type::Table) s.resolved++;
        }
    }
    std::vector<Val> in = L.call("PreviewInfo", {Val::number(id)});
    if (in.size() == 10) {
        s.steps = in[0].num;
        s.settled = in[1].type == Type::Bool && in[1].b;
        for (int k = 0; k < 6; k++) s.b[k] = in[2 + k].num;
    }
    s.ok = true;
    return s;
}

double add_copy(MockLua &L, const Val &d, std::string *code = nullptr)
{
    std::vector<Val> r = L.call("PreviewAdd", {d});
    if (r.size() == 1 && r[0].type == Type::Number) return r[0].num;
    if (code) *code = str_of(r, 2);
    if (g_verbose) std::printf("    PreviewAdd: %s (%s)\n", str_of(r, 1).c_str(), str_of(r, 2).c_str());
    return 0;
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

double set_add(MockLua &L, int type, float x, float y, float z, double p1, double p2, double p3, double user)
{
    std::vector<Val> r = L.call("SetAdd", {Val::number(type), Val::vector(x, y, z), Val::angle(0, 0, 0), Val::number(p1),
                                           Val::number(p2), Val::number(p3), Val::number(user)});
    if (r.size() == 1 && r[0].type == Type::Number) return r[0].num;
    std::printf("  info  SetAdd(%d): %s (%s)\n", type, str_of(r, 1).c_str(), str_of(r, 2).c_str());
    return 0;
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
    std::printf("G-SA1 feat_preview_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_preview_appdata");
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
    Val P = g.type == Type::Table ? g.tab->field("PREVIEW") : Val();
    bool fns = g.type == Type::Table;
    for (const char *f : {"PreviewTypes", "PreviewAdd", "PreviewRemove", "PreviewClear", "PreviewTick", "PreviewRender",
                          "PreviewBatches", "PreviewPrepareView", "PreviewEmitBatch", "PreviewInfo", "PreviewRingPlaces",
                          "PreviewStats", "SetLive"}) {
        fns = fns && g.tab->field(f).type == Type::Function;
    }
    Val ferr = g.type == Type::Table ? g.tab->field("FEATURE_ERRORS") : Val();
    CHECK(fns && feats.type == Type::Table && feats.tab->field("preview").num == 1 &&
              feats.tab->field("objects").num == 3 && ferr.type == Type::Table && ferr.tab->n.empty() && L.st.empty(),
          "gsa1.FEATURES.preview = %g, objects = %g; the twelve Preview functions and SetLive registered, no clash",
          feats.type == Type::Table ? feats.tab->field("preview").num : -1.0,
          feats.type == Type::Table ? feats.tab->field("objects").num : -1.0);
    if (g.type != Type::Table || P.type != Type::Table) {
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    CHECK(P.tab->field("ROT_NONE").num == SA1_PREVIEW_ROT_NONE && P.tab->field("ROT_OUTER").num == SA1_PREVIEW_ROT_OUTER &&
              P.tab->field("ROT_INNER").num == SA1_PREVIEW_ROT_INNER && P.tab->field("MAX").num == SA1_PREVIEW_MAX &&
              P.tab->field("IDLE_PAIRS").num == SA1_PREVIEW_IDLE_PAIRS,
          "gsa1.PREVIEW: libsa1's numbers (rotations 0 / 1 / 2, %g copies a kind, freed %g pairs after the last)",
          P.tab->field("MAX").num, P.tab->field("IDLE_PAIRS").num);
    int bad = 0;
    bad += is_nil_msg(L.call("PreviewAdd", {}));
    bad += is_nil_msg(L.call("PreviewAdd", {Val::number(3)}));
    {
        Val d = desc(0, 1, 0, 0, 0);
        d.tab->set(Val::string("params"), Val::string("x"));
        bad += is_nil_msg(L.call("PreviewAdd", {d}));
        Val d2 = desc(0, 1, 0, 0, 0, 9);
        bad += is_nil_msg(L.call("PreviewAdd", {d2}));
    }
    bad += is_nil_msg(L.call("PreviewTick", {Val::number(-1)}));
    bad += is_nil_msg(L.call("PreviewRender", {Val::string("a")}));
    bad += is_nil_msg(L.call("PreviewRingPlaces", {Val::number(0)}));
    bad += is_nil_msg(L.call("SetLive", {Val::string("x")}));
    std::vector<Val> nr = L.call("PreviewAdd", {desc(0, 1, 0, 0, 0)});
    std::vector<Val> ni = L.call("PreviewInfo", {Val::number(5)});
    std::vector<Val> nb = L.call("PreviewBatches", {Val::number(5), Val::table()});
    std::vector<Val> ns = L.call("PreviewStats", {});
    CHECK(bad == 8 && is_nil_msg(nr) && str_of(nr, 2) == "not_ready" && is_nil_msg(ni) && nb.size() == 1 &&
              nb[0].type == Type::Nil && ns.size() == 1 && ns[0].type == Type::Table && L.st.empty(),
          "bad arguments (missing, a number, params a string, state 9, a negative dt, a string id, too few, SetLive of a "
          "string): %d of 8 answered with nil + message; PreviewAdd without the disc: nil, \"%s\"; PreviewInfo of an "
          "unknown id: nil + message; PreviewBatches: nil; PreviewStats: a table", bad, str_of(nr, 2).c_str());

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the preview checks need the disc\n");
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
    CHECK(st == "ready" && se, "the disc (%s)", st.c_str());
    if (st != "ready" || !se) {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    install_mesh_library(L);

    // ---- PreviewTypes ---------------------------------------------------------------------------------------------------
    {
        Val ty = Val::table();
        L.call("PreviewTypes", {ty});
        auto f = [&](int t, const char *k) {
            Val e = ty.tab->at(t);
            return e.type == Type::Table ? e.tab->field(k) : Val();
        };
        bool avail = true;
        for (int t = 1; t <= 4; t++) avail = avail && f(t, "available").type == Type::Bool && f(t, "available").b;
        CHECK(avail && f(1, "rotation").num == SA1_PREVIEW_ROT_OUTER && f(2, "rotation").num == SA1_PREVIEW_ROT_INNER &&
                  f(3, "rotation").num == SA1_PREVIEW_ROT_NONE && f(4, "rotation").num == SA1_PREVIEW_ROT_OUTER &&
                  f(1, "settle").num == 0 && f(2, "settle").num == 0 && f(3, "settle").num == 47 &&
                  f(4, "settle").num == 23,
              "PreviewTypes: the four types available; rotation RING outer, O_GRING inner, ITEMBOX none, ITEMBOX_AIR "
              "outer; settle %g / %g / %g / %g steps (libsa1's measurement: 0 / 0 / 47 / 23)", f(1, "settle").num,
              f(2, "settle").num, f(3, "settle").num, f(4, "settle").num);
    }

    // ---- 0.9.4d: the ring's turn in its bounds (feat/cl_objicons.lua I.RingAspect / I.FACE: the spawn-menu pictures of
    // the ring classes wait for a three-quarter moment) - the copy stands upright and turns about z, so its height (z extent)
    // stays while its width seen along x (the y extent) goes from about its thickness to its height and back -------------
    {
        double id = add_copy(L, desc(SA1_CHAR_SONIC, SA1_OBJTYPE_RING, 0, 0, 0));
        double wmin = 1e9, wmax = -1e9, hmin = 1e9, hmax = -1e9;
        int inside = 0, pairs = 0;
        for (int p = 0; p < 90 && id > 0; p++) {     // 90 pairs: one turn at 4 degrees a pair
            tick_pairs(L, 1);
            std::vector<Val> in = L.call("PreviewInfo", {Val::number(id)});
            if (in.size() != 10) continue;
            double h = in[7].num - in[4].num, w = in[6].num - in[3].num;
            if (!(h > 0)) continue;
            pairs++;
            hmin = std::min(hmin, h);
            hmax = std::max(hmax, h);
            wmin = std::min(wmin, w / h);
            wmax = std::max(wmax, w / h);
            if (w / h >= 0.72 && w / h <= 0.90) inside++;
        }
        CHECK(id > 0 && pairs >= 80 && hmax - hmin < 0.02 * hmax && wmin < 0.4 && wmax > 0.95 && inside >= 4,
              "the ring's turn in its bounds over one turn (%d pairs): height %.2f-%.2f HU (constant), width / height "
              "%.2f-%.2f, %d pairs inside the pictures' three-quarter window 0.72-0.90", pairs, hmin, hmax, wmin, wmax,
              inside);
        if (id > 0) L.call("PreviewRemove", {Val::number(id)});
    }

    // ---- every class and contents, kinds Sonic and Knuckles ------------------------------------------------------------
    struct Want {
        const char *name;
        int type;
        double p1;
        int state;
        int tris;
    };
    std::vector<Want> wants;
    wants.push_back({"Ring", SA1_OBJTYPE_RING, 0, 1, 96});
    for (int c = 0; c <= 8; c++) wants.push_back({"Item Box", SA1_OBJTYPE_ITEMBOX, (double)c, 1, 116});
    wants.push_back({"broken Item Box", SA1_OBJTYPE_ITEMBOX, 3, 3, 54});
    for (int c = 0; c <= 8; c++) wants.push_back({"Item Box (Air)", SA1_OBJTYPE_ITEMBOX_AIR, (double)c, 1, 98});
    const int kinds[2] = {SA1_CHAR_SONIC, SA1_CHAR_KNUCKLES};
    // the Extra Life panel texture per kind (094b-lib-preview's measurement; feat/cl_objview.lua's table)
    const std::pair<int, int> panel[2] = {std::make_pair(2, 31), std::make_pair(2, 0)};
    for (int ki = 0; ki < 2; ki++) {
        int kind = kinds[ki];
        std::vector<double> ids;
        for (const Want &w : wants) ids.push_back(add_copy(L, desc(kind, w.type, w.p1, 0, 0, w.state)));
        tick_pairs(L, 32);          // 64 steps: past the ground box's 47-step grow-in
        int good = 0, all_obj = 0, tex_ok = 0, settled = 0;
        std::string badlist;
        Shot ring, box10, box1up, air;
        for (size_t i = 0; i < wants.size(); i++) {
            Shot s = shot(L, ids[i], kind);
            bool ok = ids[i] > 0 && s.ok && s.tris == wants[i].tris;
            good += ok ? 1 : 0;
            all_obj += (s.ok && s.object_tris == s.tris && s.tris > 0) ? 1 : 0;
            tex_ok += (s.ok && s.textured > 0 && s.resolved == s.textured) ? 1 : 0;
            settled += s.settled ? 1 : 0;
            if (!ok) badlist += gsa1::format(" %s(%g): %d tris", wants[i].name, wants[i].p1, s.tris);
            if (i == 0) ring = s;
            if (wants[i].type == SA1_OBJTYPE_ITEMBOX && wants[i].state == 1 && wants[i].p1 == 3) box10 = s;
            if (wants[i].type == SA1_OBJTYPE_ITEMBOX && wants[i].state == 1 && wants[i].p1 == 6) box1up = s;
            if (wants[i].type == SA1_OBJTYPE_ITEMBOX_AIR && wants[i].p1 == 3) air = s;
        }
        CHECK(good == (int)wants.size() && all_obj == (int)wants.size() && tex_ok == (int)wants.size() &&
                  settled == (int)wants.size(),
              "kind %d: %d of %d descriptions draw libsa1's triangles (ring 96, ground box 116 x 9 contents, broken 54, "
              "air box 98 x 9), %d all OBJECT draws, %d with every texture resolving through gsa1.Texture(kind, ...), "
              "%d settled%s", kind, good, (int)wants.size(), all_obj, tex_ok, settled, badlist.c_str());
        // bounds (libsa1, Sonic, SA1 units x 4 HU; host = 4 (x, -z, y)): RING about +-12.2 around the origin; ITEMBOX
        // z 0..60; ITEMBOX_AIR z -3.2..88.4, x within +-40
        // (the ring turns about the vertical: its x / y extents trade places, the larger of them is 8.6 .. 12.2)
        double rx = std::max(std::max(std::fabs(ring.b[0]), std::fabs(ring.b[3])),
                             std::max(std::fabs(ring.b[1]), std::fabs(ring.b[4]))), rz = ring.b[5];
        CHECK(rx > 8.0 && rx < 13.5 && std::fabs(ring.b[2] + 12.24) < 1.0 && std::fabs(rz - 12.24) < 1.0 &&
                  std::fabs(box10.b[2]) < 1.0 && std::fabs(box10.b[5] - 60.0) < 1.5 && std::fabs(box10.b[0]) < 32.0 &&
                  std::fabs(air.b[2] + 3.2) < 1.5 && std::fabs(air.b[5] - 88.4) < 2.0 && std::fabs(air.b[0]) < 44.0,
              "kind %d object-space bounds (HU): ring x %.1f..%.1f z %.2f..%.2f; ground box z %.1f..%.1f; air box z "
              "%.1f..%.1f (libsa1's numbers x 4)", kind, ring.b[0], ring.b[3], ring.b[2], ring.b[5], box10.b[2],
              box10.b[5], air.b[2], air.b[5]);
        bool panel_in = box1up.tex.count(panel[ki]) == 1, panel_out = box10.tex.count(panel[ki]) == 0;
        CHECK(panel_in && panel_out,
              "kind %d: the Extra Life box draws the kind's panel texture %d:%d (the Dreamcast logo's place without a "
              "character) and the 10 Rings box does not", kind, panel[ki].first, panel[ki].second);
        L.call("PreviewClear", {});
    }
    // the kinds without a showcase
    {
        std::string c1, c4, c8;
        double a1 = add_copy(L, desc(1, SA1_OBJTYPE_RING, 0, 0, 0), &c1);
        double a4 = add_copy(L, desc(4, SA1_OBJTYPE_RING, 0, 0, 0), &c4);
        double a8 = add_copy(L, desc(8, SA1_OBJTYPE_RING, 0, 0, 0), &c8);
        CHECK(a1 == 0 && a4 == 0 && a8 == 0 && c1 == "unsupported" && c4 == "unsupported" && c8 == "unsupported",
              "kinds 1 (Eggman), 4 (Tikal), 8 (Super Sonic): \"%s\" / \"%s\" / \"%s\" (the addon uses Sonic's)",
              c1.c_str(), c4.c_str(), c8.c_str());
    }

    // ---- PreviewRingPlaces against 0.9.4.1's layout ----------------------------------------------------------------------
    {
        struct G {
            int count;
            float size;
            int shape;
        };
        const G groups[4] = {{10, 40.0f, 0}, {7, 80.0f, 1}, {12, 80.0f, 1}, {128, 800.0f, 1}};
        const float yaws[3] = {0.0f, 37.0f, 200.0f};
        int cases = 0, good = 0;
        double worst = 0.0;
        std::string badlist;
        for (const G &gr : groups) {
            for (float yaw : yaws) {
                cases++;
                ob::Desc d;
                d.type = SA1_OBJTYPE_O_GRING;
                d.ang[1] = yaw;
                d.p[0] = (float)gr.count;
                d.p[1] = gr.size;
                d.p[2] = (float)gr.shape;
                std::vector<ob::RingPos> want;
                ob::ring_positions(d, want);
                std::map<std::pair<uint32_t, uint32_t>, const ob::RingPos *> by;
                for (const ob::RingPos &r : want) by[std::make_pair(r.record, r.bit)] = &r;
                Val out = Val::table();
                std::vector<Val> r = L.call("PreviewRingPlaces", {Val::number(0), Val::number(SA1_OBJTYPE_O_GRING),
                                                                  Val::angle(0, yaw, 0), Val::number(gr.count),
                                                                  Val::number(gr.size), Val::number(gr.shape), out});
                int n = (int)num_of(r, 0);
                bool ok = n == (int)want.size() && n == gr.count;
                double w = 0.0;
                for (int i = 0; ok && i < n; i++) {
                    double x = out.tab->at(5 * i + 1).num, y = out.tab->at(5 * i + 2).num, z = out.tab->at(5 * i + 3).num;
                    uint32_t rec = (uint32_t)out.tab->at(5 * i + 4).num, bit = (uint32_t)out.tab->at(5 * i + 5).num;
                    auto it = by.find(std::make_pair(rec, bit));
                    if (it == by.end()) {
                        ok = false;
                        break;
                    }
                    const float *p = it->second->pos;
                    w = std::max(w, std::max(std::fabs(x - p[0]), std::max(std::fabs(y - p[1]), std::fabs(z - p[2]))));
                }
                // 0.01 HU, or the game's own sine table's step on a big circle (njSin / njCos of BAMS angles: about
                // 1e-4 of the radius - 0.08 HU at 800 HU; 0.9.4.1's own measurement held 0.01 HU at 80 HU)
                ok = ok && w <= std::max(0.01, 1.2e-4 * gr.size);
                worst = std::max(worst, w);
                good += ok ? 1 : 0;
                if (!ok) badlist += gsa1::format(" %d/%g/%d at %g: n %d (want %d) err %.4f", gr.count, (double)gr.size,
                                                 gr.shape, (double)yaw, n, (int)want.size(), w);
            }
        }
        CHECK(good == cases,
              "PreviewRingPlaces of the ENTITY's description (a line of 10 at 40 HU; circles of 7 and 12 at 80, 128 at "
              "800: 32 records) at yaw 0 / 37 / 200: %d of %d layouts equal objects::ring_positions (0.9.4.1) with the same "
              "record and bit per ring (within 0.01 HU, 1.2e-4 of a big circle's radius), worst %.4f HU%s", good, cases, worst, badlist.c_str());
        Val out = Val::table();
        std::vector<Val> r1 = L.call("PreviewRingPlaces", {Val::number(0), Val::number(SA1_OBJTYPE_RING),
                                                           Val::angle(0, 45, 0), Val::number(0), Val::number(0),
                                                           Val::number(0), out});
        std::vector<Val> rb = L.call("PreviewRingPlaces", {Val::number(0), Val::number(SA1_OBJTYPE_ITEMBOX),
                                                           Val::angle(0, 0, 0), Val::number(3), Val::number(0),
                                                           Val::number(0)});
        CHECK(num_of(r1, 0) == 1 && out.tab->at(1).num == 0 && out.tab->at(4).num == 0 && out.tab->at(5).num == 0 &&
                  is_nil_msg(rb) && str_of(rb, 2) == "bad_argument",
              "a RING's place is its own (record 0, bit 0); an item box has no ring places (\"%s\")", str_of(rb, 2).c_str());
    }

    // ---- PreviewEmitBatch streams like EmitBatch -------------------------------------------------------------------------
    {
        double id = add_copy(L, desc(0, SA1_OBJTYPE_RING, 0, 0, 0));
        tick_pairs(L, 2);
        std::vector<Val> rr = L.call("PreviewRender", {Val::number(id)});
        std::vector<Val> rr2 = L.call("PreviewRender", {Val::number(id)});
        Val bt = Val::table();
        L.call("PreviewBatches", {Val::number(id), bt});
        double tris = bt.tab->at(1).type == Type::Table ? bt.tab->at(1).tab->field("tris").num : -1;
        std::vector<Val> pv = L.call("PreviewPrepareView", {Val::number(id), Val::vector(-100, 0, 20), Val::vector(0, -1, 0),
                                                            Val::vector(0, 0, 1)});
        uint64_t adv0 = g_mesh.adv;
        g_mesh.vp.clear();
        std::vector<Val> em = L.call("PreviewEmitBatch", {Val::number(id), Val::number(1)});
        uint64_t adv = g_mesh.adv - adv0;
        float maxc = 0.0f;
        for (float v : g_mesh.vp) maxc = std::max(maxc, std::fabs(v));
        std::vector<Val> bad_b = L.call("PreviewEmitBatch", {Val::number(id), Val::number(99)});
        CHECK(id > 0 && rr.size() == 4 && rr[0].num >= 1 && rr[3].type == Type::Bool && rr2.size() == 4 &&
                  rr2[3].type == Type::Bool && !rr2[3].b && rr2[1].num == rr[1].num && pv.size() == 1 && pv[0].b &&
                  em.size() == 1 && em[0].num == tris * 3 && adv == (uint64_t)(tris * 3) && maxc > 5.0f && maxc < 14.0f &&
                  is_nil_msg(bad_b),
              "PreviewEmitBatch: the ring's batch 1 (%g triangles) streamed as %g vertices through the mesh library, in "
              "object space (|coordinate| <= %.1f HU); a second PreviewRender of the same pair copies nothing (changed "
              "false); batch 99: nil + message", tris, em.size() ? em[0].num : -1.0, (double)maxc);

        // a fault (libsa1's test hook), then the way out
        sa1_status fs = sa1pv_test_fault(se->ctx(), (uint32_t)id);
        std::vector<Val> tk;
        for (int i = 0; i < 3; i++) {
            tk = L.call("PreviewTick", {Val::number(1.0 / 30.0)});
            if (is_nil_msg(tk)) break;
        }
        std::vector<Val> rf = L.call("PreviewRender", {Val::number(id)});
        std::vector<Val> cl = L.call("PreviewClear", {});
        double id2 = add_copy(L, desc(0, SA1_OBJTYPE_RING, 0, 0, 0));
        tick_pairs(L, 2);
        Shot s2 = shot(L, id2, 0);
        CHECK(fs == SA1_OK && is_nil_msg(tk) && str_of(tk, 2) == "fault" && is_nil_msg(rf) && str_of(rf, 2) == "fault" &&
                  cl.size() == 1 && cl[0].num == 1 && id2 > 0 && s2.tris == 96,
              "a fault forced into a copy: PreviewTick -> nil, \"%s\"; PreviewRender -> \"%s\"; PreviewClear (%g copies) "
              "and a new ring draws %d triangles again", str_of(tk, 2).c_str(), str_of(rf, 2).c_str(),
              cl.size() ? cl[0].num : -1.0, s2.tris);
        std::vector<Val> rm = L.call("PreviewRemove", {Val::number(id2)});
        std::vector<Val> ri = L.call("PreviewInfo", {Val::number(id2)});
        std::vector<Val> rm2 = L.call("PreviewRemove", {Val::number(id2)});
        Val stt = Val::table();
        L.call("PreviewStats", {stt});
        CHECK(rm.size() == 1 && rm[0].b && is_nil_msg(ri) && str_of(ri, 2) == "not_found" && rm2.size() >= 2 &&
                  rm2[0].type == Type::Bool && !rm2[0].b && stt.tab->field("copies").num == 0 &&
                  stt.tab->field("faults").num >= 1,
              "PreviewRemove: true, then PreviewInfo \"%s\" and a second remove false; PreviewStats: %g copies, %g faults",
              str_of(ri, 2).c_str(), stt.tab->field("copies").num, stt.tab->field("faults").num);
        tick_pairs(L, 70);          // the empty showcase freed (60 idle pairs: review R.18)
    }

    // ---- SetLive (review R.6) ---------------------------------------------------------------------------------------------
    {
        std::vector<sa1_collision_tri> tris;
        floor_quad(tris, -6000, 14000, -4000, 4000);
        bool world = se->set_world(tris, err);
        const float sp[3] = {0.0f, 0.0f, 8.0f};
        int32_t cid = world ? se->create(SA1_CHAR_SONIC, sp, 0.0f, err) : 0;
        for (int i = 0; i < 6 && cid > 0; i++) se->tick(cid, 0, 0, 0, 0, 1.0f / 30.0f);
        L.call("SetEvents", {Val::table()});
        double near_ring = set_add(L, SA1_OBJTYPE_RING, 300, 0, 20, 0, 0, 0, 11);
        double far_ring = set_add(L, SA1_OBJTYPE_RING, 9000, 0, 20, 0, 0, 0, 12);
        double line = set_add(L, SA1_OBJTYPE_O_GRING, 0, 400, 20, 20, 40, 0, 13);
        double box = set_add(L, SA1_OBJTYPE_ITEMBOX, -300, 0, 0.5, 3, 0, 0, 14);
        std::map<std::pair<int, int>, int> live;        // (object, record) -> 1 after SPAWNED, 0 after DESPAWNED
        for (int i = 0; i < 12 && cid > 0; i++) {
            se->tick(cid, 0, 0, 0, 0, 1.0f / 30.0f);
            Val t = Val::table();
            L.call("SetEvents", {t});
            int n = (int)t.tab->field("count").num;
            for (int k = 1; k <= n; k++) {
                Val e = t.tab->at(k);
                if (e.type != Type::Table) continue;
                int kind = (int)e.tab->field("kind").num;
                auto key = std::make_pair((int)e.tab->field("id").num, (int)e.tab->field("index").num);
                if (kind == SA1_SET_EVENT_SPAWNED) live[key] = 1;
                if (kind == SA1_SET_EVENT_DESPAWNED) live[key] = 0;
            }
        }
        std::set<std::pair<int, int>> from_events;
        for (auto &kv : live) {
            if (kv.second) from_events.insert(kv.first);
        }
        Val out = Val::table();
        std::vector<Val> lr = L.call("SetLive", {Val::number(cid), out});
        std::set<std::pair<int, int>> from_live;
        int n = (int)num_of(lr, 0);
        for (int i = 0; i < n; i++) {
            from_live.insert(std::make_pair((int)out.tab->at(2 * i + 1).num, (int)out.tab->at(2 * i + 2).num));
        }
        bool far_out = from_live.count(std::make_pair((int)far_ring, 0)) == 0;
        bool has_all = from_live.count(std::make_pair((int)near_ring, 0)) && from_live.count(std::make_pair((int)box, 0)) &&
                       from_live.count(std::make_pair((int)line, 0)) && from_live.count(std::make_pair((int)line, 1)) &&
                       from_live.count(std::make_pair((int)line, 2));
        std::vector<Val> unk = L.call("SetLive", {Val::number(987654)});
        CHECK(world && cid > 0 && near_ring > 0 && far_ring > 0 && line > 0 && box > 0 && lr.size() == 2 &&
                  from_live == from_events && far_out && has_all && n == 5 && is_nil_msg(unk) &&
                  str_of(unk, 2) == "not_found",
              "SetLive (review R.6): %d live (object, record) pairs - exactly those with a SPAWNED and no later DESPAWNED "
              "(%d): the near ring, the box and the line's 3 records; the ring 9,000 HU away not; an unknown character: "
              "\"%s\"", n, (int)from_events.size(), str_of(unk, 2).c_str());
        L.call("SetClear", {});
        if (cid > 0) se->destroy(cid);
    }

    // ---- gsa1.Shutdown: the copies go with the context --------------------------------------------------------------------
    {
        double id = add_copy(L, desc(0, SA1_OBJTYPE_RING, 0, 0, 0));
        L.call("Shutdown", {});
        std::vector<Val> r = L.call("PreviewRender", {Val::number(id)});
        std::vector<Val> a = L.call("PreviewAdd", {desc(0, SA1_OBJTYPE_RING, 0, 0, 0)});
        Val stt = Val::table();
        L.call("PreviewStats", {stt});
        CHECK(id > 0 && is_nil_msg(r) && is_nil_msg(a) && str_of(a, 2) == "not_ready" && stt.tab->field("copies").num == 0,
              "gsa1.Shutdown: PreviewRender of an old id -> \"%s\", PreviewAdd -> \"%s\", no copy kept", str_of(r, 2).c_str(),
              str_of(a, 2).c_str());
    }
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
