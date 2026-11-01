// feat_board_binding_test: the board feature through the module's Lua functions (round 0.9.5: sadc
// docs/research/gsa1_095_plan.md 5.4 and 6.3 tasks 6-7 with its Review R.2 / R.5 / R.6 / R.12 / R.13; board095_gsa1.md 10) -
// the feature "board" (src/module/bind_board.cpp: Board, BoardPush, BoardFree, BoardState, BoardSounds, BoardInfo,
// gsa1.BOARD; the core src/core/board.cpp and the session's board parts), with the related "preview" 2 (gsa1.PREVIEW.BOARD)
// and "surfaces" 3 (the board-time kinds). Linked like binding_test (the module's objects, libsa1, the mock Lua stack of
// tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi; the play checks use gm_construct from the Garry's Mod install
// (read only) for gsa1.WorldLoadData and then a flat floor of their own (Session::set_world).
//
//   feat_board_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
// Two parts (review R.6):
//   * THE API PART runs whenever libsa1.h has SA1_API_BOARD: gsa1.FEATURES.board == 1, every 5.4 function registered with its
//     arguments checked ("bad_argument" before anything else), the codes (no disc: "not_ready"; no character: "not_found";
//     Knuckles / Super Sonic / BoardPush not riding / BoardFree without a left board: "unsupported" with the plain reason),
//     gsa1.BOARD's constants, BoardState's fields and their types (one call on a Sonic), BoardInfo's fields, the preview
//     type (gsa1.PREVIEW.BOARD, PreviewTypes[0x100]), the surface words (SetSurfaceTable / SurfaceKind / SurfaceDefaults) -
//     and writes them to build/<target>/board_api.txt next to this test (the Lua lanes check their mock module against it:
//     tests/feat_board_test.lua).
//   * THE BEHAVIOUR PART prints exactly one line "SKIP behaviour: libsa1's board is not built yet" and passes while libsa1's
//     sa1_character_board answers that (095-lib-board's contract snapshot); otherwise it runs in full: Sonic / Tails on and
//     off (the actions 102-124 / 107-127, then 18 / 19 in the first pair after OFF: review R.13), the kept board settled
//     within 120 ticks with its pose within 64 HU, BoardFree, ON after OFF (a new board, freed_why 2), a carrying Sonic
//     refused once ("carrying something"), terrain SNOW on a flat SOLID plane (attr & 8 while riding, not after), the push
//     (>= 3.99 100 pairs later), the push ended with the ride (review R.2: < 3.99 within 3 ticks on foot), OFF with remove
//     (review R.5: no board one tick later), the stage rules only for the rider and re-applied with the sound banks,
//     BoardSounds(false) stopping the board tones (review R.12), the board's batches (0x4000, never merged with the body's,
//     textured), the BOARD preview (44 triangles, archive >= 0), BoardState's cost per call and no table made with `out`.
//     The final gates (095-gsa1-boardmod's and the verifier's) fail when the SKIP line appears.
//
// API NOTES (095-gsa1-boardmod's report, also in r095/lanes/boardmod_contract.txt): the Lua API is the header of
// src/module/bind_board.cpp (gsa1_095_plan.md 5.4 as built). board_api.txt's records, one per line, tab-separated:
//   feature <name> <version>
//   function <Name> <arguments> <returns> <codes, comma separated>
//   option Board <field> <lua type> <values>
//   const BOARD.<NAME> <number>  |  const BOARD.<NAME> <a>,<b> (a pair {a, b})  |  const PREVIEW.BOARD <number>
//   field BoardState <field> <lua type>        info BoardInfo <field> <lua type>
//   reason <code> <text>
//   preview BOARD <type> rotation <n> settle <n> available <0|1>
//   surface <word> kind <n> bit <0x...> aliases <a,b,...>       default <type | #letter> <kinds string>
//   behaviour <SKIP | RAN> <what>
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
#include <string>
#include <thread>
#include <vector>

#include "mock_lua.hpp"
#include "../src/core/board.hpp"
#include "../src/core/config.hpp"
#include "../src/core/interact.hpp"
#include "../src/core/surfaces.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

#ifndef INFO
#define INFO(...)                                            \
    do {                                                     \
        std::printf("  info  ");                             \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)
#endif

namespace {

// a mock that counts the tables the module makes (BoardState with `out` must make none)
class CountingLua : public MockLua {
public:
    uint64_t tables = 0;
    void CreateTable() override
    {
        tables++;
        MockLua::CreateTable();
    }
};

#if defined(SA1_API_BOARD)
double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1e9;
}

bool is_true(const std::vector<Val> &r)
{
    return r.size() >= 1 && r[0].type == Type::Bool && r[0].b;
}

const char *type_word(int t)
{
    switch (t) {
    case Type::Nil: return "nil";
    case Type::Bool: return "boolean";
    case Type::Number: return "number";
    case Type::String: return "string";
    case Type::Table: return "table";
    default: return "other";
    }
}

std::string fmt_num(double v)
{
    if (v == std::floor(v) && std::fabs(v) < 1e15) {
        return gsa1::format("%.0f", v);
    }
    return gsa1::format("%.9g", v);
}

// a flat SOLID floor (host space, z up): half extent `half`, tiles of `tile`, at height z
std::vector<sa1_collision_tri> floor_of(float half, float tile, float z, uint32_t surface)
{
    std::vector<sa1_collision_tri> out;
    for (float x = -half; x < half - 0.5f; x += tile) {
        for (float y = -half; y < half - 0.5f; y += tile) {
            const float p[4][3] = {{x, y, z}, {x + tile, y, z}, {x + tile, y + tile, z}, {x, y + tile, z}};
            sa1_collision_tri a, b;
            std::memset(&a, 0, sizeof a);
            std::memset(&b, 0, sizeof b);
            std::memcpy(a.v[0], p[0], 12);
            std::memcpy(a.v[1], p[1], 12);
            std::memcpy(a.v[2], p[2], 12);
            std::memcpy(b.v[0], p[0], 12);
            std::memcpy(b.v[1], p[2], 12);
            std::memcpy(b.v[2], p[3], 12);
            a.surface = b.surface = surface;
            out.push_back(a);
            out.push_back(b);
        }
    }
    return out;
}

struct Rig {
    MockLua *L = nullptr;
    gsa1::Session *se = nullptr;
    // one pair (Tick with dt 1/30): stick (sx, sy) in the camera frame of yaw 0, buttons
    void pair(double id, double sx = 0.0, double sy = 0.0, uint32_t buttons = 0)
    {
        L->call("Tick", {Val::number(id), Val::number(sx), Val::number(sy), Val::number(0), Val::number(buttons),
                         Val::number(1.0 / 30.0)});
    }
    void pairs(double id, int n, double sx = 0.0, double sy = 0.0)
    {
        for (int i = 0; i < n; i++) {
            pair(id, sx, sy, 0);
        }
    }
    // BoardState(id, out); the one-shot frees of every read are summed here (freed_total, last_why)
    double freed_total = 0.0, last_why = -1.0;
    std::vector<Val> state(double id, Val &out)
    {
        std::vector<Val> r = L->call("BoardState", {Val::number(id), out});
        Val f = out.tab ? out.tab->field("freed") : Val();
        if (f.type == Type::Number && f.num > 0) {
            freed_total += f.num;
            Val w = out.tab->field("freed_why");
            last_why = w.type == Type::Number ? w.num : -1.0;
        }
        return r;
    }
    gsa1::Character *ch(double id) { return se ? se->get((int32_t)id) : nullptr; }
    double create(int kind, float x = 0.0f, float y = 0.0f, float z = 40.0f, double yaw = 0.0)
    {
        std::vector<Val> r = L->call("Create", {Val::number(kind), Val::vector(x, y, z), Val::number(yaw)});
        return num_of(r, 0);
    }
};

bool field_bool(const Val &t, const char *k)
{
    Val v = t.tab ? t.tab->field(k) : Val();
    return v.type == Type::Bool && v.b;
}

double field_num(const Val &t, const char *k)
{
    Val v = t.tab ? t.tab->field(k) : Val();
    return v.type == Type::Number ? v.num : -1e9;
}
#endif  // SA1_API_BOARD

}  // namespace

int main(int argc, char **argv)
{
    std::string gdi;
    std::string bsp = gsa1_garrysmod_dir()[0] ? std::string(gsa1_garrysmod_dir()) + "\\maps\\gm_construct.bsp" : std::string();
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
        else if (std::string(argv[i]) == "--bsp") bsp = argv[++i];
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_board_binding_test\n");
    CountingLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_board_appdata");
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
    if (g.type != Type::Table) {
        CHECK(false, "gsa1 table");
        return 1;
    }
    Val feats = g.tab->field("FEATURES");
#if !defined(SA1_API_BOARD)
    // the round-start snapshot (libsa1 0.2.0 / 0.9.4f): no board in libsa1, so no feature "board"
    CHECK(feats.type == Type::Table && feats.tab->field("board").type == Type::Nil && g.tab->field("Board").type == Type::Nil &&
              g.tab->field("BOARD").type == Type::Nil,
          "this libsa1.h has no SA1_API_BOARD: gsa1.FEATURES.board is absent and nothing of the board is registered "
          "(GSA1.HasFeature(\"board\") is false)");
    std::printf("  info  board_api.txt is written only with libsa1's board API (SA1_API_BOARD)\n");
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
#else
    std::vector<std::string> api;   // board_api.txt's records
    auto rec = [&](const std::string &s) { api.push_back(s); };

    // ---- the API part: features, functions, constants ------------------------------------------------------------
    double fb = feats.type == Type::Table ? feats.tab->field("board").num : -1.0;
    double fp = feats.type == Type::Table ? feats.tab->field("preview").num : -1.0;
    double fs = feats.type == Type::Table ? feats.tab->field("surfaces").num : -1.0;
    bool fns = true;
    for (const char *f : {"Board", "BoardPush", "BoardFree", "BoardState", "BoardSounds", "BoardInfo"}) {
        fns = fns && g.tab->field(f).type == Type::Function;
    }
#if defined(SA1_PREVIEW_BOARD)
    const double want_preview = 2.0;
#else
    const double want_preview = 1.0;
#endif
#if defined(SA1_SURFACE_BOARD_SNOW)
    const double want_surfaces = 3.0;
#else
    const double want_surfaces = 2.0;
#endif
    CHECK(fb == 1.0 && fns && fp == want_preview && fs == want_surfaces && L.st.empty() &&
              g.tab->field("TICK_HOST_CAMERA").type == Type::Bool && g.tab->field("TICK_HOST_CAMERA").b,
          "gsa1.FEATURES.board = %g, preview = %g, surfaces = %g; Board, BoardPush, BoardFree, BoardState, BoardSounds, "
          "BoardInfo registered; gsa1.TICK_HOST_CAMERA true", fb, fp, fs);
    rec(gsa1::format("feature\tboard\t%s", fmt_num(fb).c_str()));
    rec(gsa1::format("feature\tpreview\t%s", fmt_num(fp).c_str()));
    rec(gsa1::format("feature\tsurfaces\t%s", fmt_num(fs).c_str()));
    rec("feature\tTICK_HOST_CAMERA\ttrue");
    const char *calls = "unsupported,not_ready,fault,bad_argument,not_found";
    rec(gsa1::format("function\tBoard\tid, on [, opts]\ttrue | nil, message, code\t%s", calls));
    rec(gsa1::format("function\tBoardPush\tid\ttrue | nil, message, code\t%s", calls));
    rec(gsa1::format("function\tBoardFree\tid\ttrue | nil, message, code\t%s", calls));
    rec("function\tBoardState\tid [, out]\tout | nil, message, code\tbad_argument,not_found");
    rec("function\tBoardSounds\ton\ttrue | nil, message, code\tbad_argument");
    rec("function\tBoardInfo\t[out]\tout\t");
    rec("option\tBoard\tterrain\tnumber\t0,1,2 (gsa1.BOARD.TERRAIN_*; default 0)");
    rec("option\tBoard\tpush\tboolean\tSA1_BOARD_START_PUSH (on only)");
    rec("option\tBoard\ttails_jump\tboolean\tSA1_BOARD_FAITHFUL_EXIT (on only)");
    rec("option\tBoard\treuse\tboolean\tSA1_BOARD_REUSE_KEPT (on only; G-SA1 0.9.5 never sets it)");
    rec("option\tBoard\tremove\tboolean\tSA1_BOARD_REMOVE_ON_EXIT (on and off)");
    Val B = g.tab->field("BOARD");
    struct C1 { const char *name; double v; } c1[] = {
        {"TERRAIN_MAP", 0}, {"TERRAIN_SNOW", 1}, {"TERRAIN_SAND", 2}, {"DRAW", SA1_DRAW_BOARD},
        {"SETTLE_STEPS", SA1_BOARD_SETTLE_STEPS}, {"FREED_REMOVED", 0}, {"FREED_FELL", 1}, {"FREED_REPLACED", 2},
        {"FREED_FREE", 3},
    };
    struct C2 { const char *name; double a, b; } c2[] = {
        {"SONIC_MODES", 62, 68}, {"TAILS_MODES", 48, 54}, {"SNOW_TONES", 208, 238}, {"SAND_TONES", 690, 698},
    };
    std::string wrong;
    for (const auto &c : c1) {
        Val v = B.type == Type::Table ? B.tab->field(c.name) : Val();
        if (v.type != Type::Number || v.num != c.v) wrong += std::string(" ") + c.name;
        rec(gsa1::format("const\tBOARD.%s\t%s", c.name, fmt_num(v.type == Type::Number ? v.num : -1).c_str()));
    }
    for (const auto &c : c2) {
        Val v = B.type == Type::Table ? B.tab->field(c.name) : Val();
        double a = v.type == Type::Table ? v.tab->at(1).num : -1, b = v.type == Type::Table ? v.tab->at(2).num : -1;
        if (a != c.a || b != c.b) wrong += std::string(" ") + c.name;
        rec(gsa1::format("const\tBOARD.%s\t%s,%s", c.name, fmt_num(a).c_str(), fmt_num(b).c_str()));
    }
    Val PV = g.tab->field("PREVIEW");
    double pvb = PV.type == Type::Table ? PV.tab->field("BOARD").num : -1;
#if defined(SA1_PREVIEW_BOARD)
    if (pvb != SA1_PREVIEW_BOARD) wrong += " PREVIEW.BOARD";
#endif
    rec(gsa1::format("const\tPREVIEW.BOARD\t%s", fmt_num(pvb).c_str()));
    CHECK(B.type == Type::Table && wrong.empty(),
          "gsa1.BOARD: TERRAIN_MAP 0, TERRAIN_SNOW 1, TERRAIN_SAND 2, DRAW 0x4000, SETTLE_STEPS 30, SONIC_MODES {62, 68}, "
          "TAILS_MODES {48, 54}, FREED_* 0..3, SNOW_TONES {208, 238}, SAND_TONES {690, 698}; gsa1.PREVIEW.BOARD %g%s%s", pvb,
          wrong.empty() ? "" : ": wrong", wrong.c_str());

    // ---- arguments and codes without the disc ----------------------------------------------------------------------
    {
        int bad = 0;
        auto is_code = [&](const std::vector<Val> &r, const char *code) { return is_nil_msg(r) && str_of(r, 2) == code; };
        bad += !is_code(L.call("Board", {Val::string("x"), Val::boolean(true)}), "bad_argument");
        bad += !is_code(L.call("Board", {Val::number(1), Val::string("yes")}), "bad_argument");
        bad += !is_code(L.call("Board", {Val::number(1), Val::boolean(true), Val::number(5)}), "bad_argument");
        Val o1 = Val::table();
        o1.tab->set(Val::string("terrain"), Val::number(7));
        bad += !is_code(L.call("Board", {Val::number(1), Val::boolean(true), o1}), "bad_argument");
        Val o2 = Val::table();
        o2.tab->set(Val::string("push"), Val::string("y"));
        bad += !is_code(L.call("Board", {Val::number(1), Val::boolean(true), o2}), "bad_argument");
        bad += !is_code(L.call("Board", {Val::number(1), Val::boolean(true)}), "not_ready");
        bad += !is_code(L.call("BoardPush", {Val::number(0)}), "bad_argument");
        bad += !is_code(L.call("BoardPush", {Val::number(1)}), "not_ready");
        bad += !is_code(L.call("BoardFree", {Val::number(1)}), "not_ready");
        bad += !is_code(L.call("BoardState", {Val::number(1)}), "not_found");
        bad += !is_code(L.call("BoardState", {Val::number(1), Val::number(2)}), "bad_argument");
        bad += !is_code(L.call("BoardSounds", {Val::number(1)}), "bad_argument");
        bad += !is_true(L.call("BoardSounds", {Val::boolean(true)}));
        std::vector<Val> bi = L.call("BoardInfo", {});
        bool info = bi.size() == 1 && bi[0].type == Type::Table && field_bool(bi[0], "available") &&
                    field_num(bi[0], "version") == 1 && bi[0].tab->field("kinds").type == Type::Table &&
                    bi[0].tab->field("textures").type == Type::Table && bi[0].tab->field("rules").type == Type::Bool;
        CHECK(bad == 0 && info && L.st.empty(),
              "without the disc: bad ids / on / opts / terrain 7 / push \"y\" -> bad_argument; Board / BoardPush / BoardFree "
              "-> not_ready; BoardState of no character -> not_found, a bad out -> bad_argument; BoardSounds(1) -> "
              "bad_argument, (true) -> true; BoardInfo -> a table (available, version 1, kinds, textures, rules); %d wrong",
              bad);
        if (info) {
            for (const auto &kv : bi[0].tab->s) {
                rec(gsa1::format("info\tBoardInfo\t%s\t%s", kv.first.c_str(), type_word(kv.second.type)));
            }
        }
    }
    rec(gsa1::format("reason\tunsupported\t%s", gsa1::board::kReasonKind));
    rec(gsa1::format("reason\tunsupported\t%s", gsa1::board::kReasonSuper));
    rec(gsa1::format("reason\tunsupported\t%s", gsa1::board::kReasonNotRiding));
    rec(gsa1::format("reason\tunsupported\t%s", gsa1::board::kReasonNoKept));
    rec(gsa1::format("reason\tunsupported\t%s", gsa1::board::kReasonPuppet));
    rec(gsa1::format("reason\trefused\t%s", gsa1::board::kReasonCarrying));
    rec(gsa1::format("reason\trefused\t%s", gsa1::board::kReasonRefused));

    // the surface words (the core's kind table, as SetSurfaceTable / SurfaceKind take them)
    {
        const gsa1::KindInfo *kt = gsa1::kind_table();
        bool have_snow = false, have_sand = false;
        for (unsigned i = 0; i < gsa1::kKindCount; i++) {
            std::string w = kt[i].word;
            if (w == "boardsnow" || w == "boardsand") {
                rec(gsa1::format("surface\t%s\tkind %u\tbit 0x%X\taliases %s", w.c_str(), (unsigned)kt[i].kind,
                                 (unsigned)kt[i].surface, w == "boardsnow" ? "board snow,board_snow,board-snow"
                                                                           : "board sand,board_sand,board-sand"));
                have_snow = have_snow || (w == "boardsnow" && kt[i].surface == SA1_SURFACE_BOARD_SNOW);
                have_sand = have_sand || (w == "boardsand" && kt[i].surface == SA1_SURFACE_BOARD_SAND);
            }
        }
        std::vector<Val> st1 = L.call("SetSurfaceTable", {[&] {
            Val t = Val::table();
            t.tab->set(Val::number(1), Val::string("concrete=Board Snow, dig"));
            t.tab->set(Val::number(2), Val::string("tile=boardsand"));
            return t;
        }(), Val()});
        std::vector<Val> k1 = L.call("SurfaceKind", {Val::string("concrete")});
        std::vector<Val> k2 = L.call("SurfaceKind", {Val::string("tile")});
        L.call("SetSurfaceTable", {Val(), Val()});
        std::vector<Val> k3 = L.call("SurfaceKind", {Val::string("snow")});
        std::vector<Val> k4 = L.call("SurfaceKind", {Val::string("sand")});
        std::vector<Val> k5 = L.call("SurfaceKind", {Val::string("mystery_soil"), Val::string("J")});
        std::vector<Val> k6 = L.call("SurfaceKind", {Val::string("mystery_soil"), Val::string("N")});
        std::vector<Val> d = L.call("SurfaceDefaults", {});
        bool defaults = d.size() == 2 && d[0].type == Type::Table && d[1].type == Type::Table &&
                        d[0].tab->field("snow").str == "dig,boardsnow" && d[0].tab->field("sand").str == "dig,boardsand" &&
                        d[1].tab->field("J").str == "dig,boardsnow" && d[1].tab->field("N").str == "dig,boardsand" &&
                        d[0].tab->field("grass").str == "dig";
        CHECK(have_snow && have_sand && st1.size() == 4 && st1[0].b && st1[3].num == 0 && str_of(k1, 0) == "dig,boardsnow" &&
                  str_of(k2, 0) == "boardsand" && str_of(k3, 0) == "dig,boardsnow" && str_of(k4, 0) == "dig,boardsand" &&
                  str_of(k5, 0) == "dig,boardsnow" && str_of(k6, 0) == "dig,boardsand" && defaults && L.st.empty(),
              "surfaces 3: the words boardsnow / boardsand (SA1_SURFACE_BOARD_SNOW / _SAND), \"Board Snow, dig\" -> %s, "
              "\"boardsand\" -> %s; the defaults snow %s, sand %s, letter J %s, N %s", str_of(k1, 0).c_str(),
              str_of(k2, 0).c_str(), str_of(k3, 0).c_str(), str_of(k4, 0).c_str(), str_of(k5, 0).c_str(),
              str_of(k6, 0).c_str());
        if (d.size() == 2 && d[0].type == Type::Table && d[1].type == Type::Table) {
            for (const char *n : {"snow", "sand"}) rec(gsa1::format("default\t%s\t%s", n, d[0].tab->field(n).str.c_str()));
            for (const char *n : {"J", "N"}) rec(gsa1::format("default\t#%s\t%s", n, d[1].tab->field(n).str.c_str()));
        }
    }

    auto write_api = [&](const char *behaviour) {
        std::string path = gsa1::join_path(self.empty() ? "." : self, "board_api.txt");
        std::string text = "# G-SA1 board_api.txt: the module contract of round 0.9.5 (sadc docs/research/gsa1_095_plan.md 5.4)\n"
                           "# written by tests/feat_board_binding_test.cpp from the module as built against this target's\n"
                           "# build/deps/include/libsa1.h (" + std::string(sa1_version_string()) + "). Tab-separated records:\n"
                           "# feature | function | option | const | field | info | reason | preview | surface | default | behaviour\n";
        for (const std::string &r : api) {
            text += r + "\n";
        }
        text += std::string("behaviour\t") + behaviour + "\n";
        std::FILE *f = std::fopen(path.c_str(), "wb");
        bool ok = f && std::fwrite(text.data(), 1, text.size(), f) == text.size();
        if (f) std::fclose(f);
        CHECK(ok, "board_api.txt written: %s (%zu records)", path.c_str(), api.size() + 1);
    };

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the codes with a character, BoardState's fields and the preview type "
                    "need the disc\n");
        write_api("SKIP\tno disc");
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
    std::string ist = "loading";
    for (int polls = 0; ist == "loading" && polls < 30000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        ist = str_of(L.call("InitPoll", {}), 0);
    }
    CHECK(ist == "ready", "the disc: %s", ist.c_str());
    std::string map;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
        std::printf("  info  no gm_construct (%s): the play checks are skipped\n", bsp.c_str());
        write_api("SKIP\tno gm_construct");
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct) (Create needs a world)");
    Rig R;
    R.L = &L;
    R.se = gsa1::mod::session();
    // 256-HU tiles (measured 0.9.5: on a floor of 1024-HU triangles a kept board's resting pose never repeats bit for bit,
    // so libsa1 never reports it SETTLED; 512 HU and smaller settle in about 15 pairs - G-SA1's map triangles are
    // tessellated to 256 HU)
    std::vector<sa1_collision_tri> flat = floor_of(16384.0f, 256.0f, 0.0f, SA1_SURFACE_SOLID);
    CHECK(R.se && R.se->set_world(flat, err), "a flat SOLID floor of 32768 HU (256-HU tiles) as the static collision (%s)",
          err.c_str());

    // the preview type
    {
        std::vector<Val> pt = L.call("PreviewTypes", {});
        Val e = pt.size() == 1 && pt[0].type == Type::Table ? pt[0].tab->at((double)gsa1::board::kPreviewBoard) : Val();
        bool listed = e.type == Type::Table && field_num(e, "type") == gsa1::board::kPreviewBoard;
        CHECK(listed, "PreviewTypes lists gsa1.PREVIEW.BOARD at [0x100]: rotation %g, settle %g, available %s",
              field_num(e, "rotation"), field_num(e, "settle"), field_bool(e, "available") ? "true" : "false");
        rec(gsa1::format("preview\tBOARD\t%u\trotation %s\tsettle %s\tavailable %d", (unsigned)gsa1::board::kPreviewBoard,
                         fmt_num(field_num(e, "rotation")).c_str(), fmt_num(field_num(e, "settle")).c_str(),
                         field_bool(e, "available") ? 1 : 0));
    }

    // the codes with characters, BoardState's fields
    double sonic = R.create(0);
    double knux = R.create(3, 400.0f, 0.0f);
    double sup = R.create(8, -400.0f, 0.0f);
    R.pairs(sonic, 10);
    R.pairs(knux, 2);
    if (sup > 0) R.pairs(sup, 2);
    {
        std::vector<Val> k1 = L.call("Board", {Val::number(knux), Val::boolean(true)});
        std::vector<Val> s1 = L.call("Board", {Val::number(sup), Val::boolean(true)});
        std::vector<Val> p1 = L.call("BoardPush", {Val::number(sonic)});
        std::vector<Val> f1 = L.call("BoardFree", {Val::number(sonic)});
        std::vector<Val> n1 = L.call("Board", {Val::number(9999), Val::boolean(true)});
        // not riding: nothing to do (true); the contract snapshot's libsa1 answers every valid call "not built yet"
        std::vector<Val> o1 = L.call("Board", {Val::number(sonic), Val::boolean(false)});
        bool off_ok = is_true(o1) || (is_nil_msg(o1) && str_of(o1, 1).find("not built yet") != std::string::npos);
        CHECK(is_nil_msg(k1) && str_of(k1, 1) == gsa1::board::kReasonKind && str_of(k1, 2) == "unsupported" &&
                  sup > 0 && is_nil_msg(s1) && str_of(s1, 1) == gsa1::board::kReasonSuper && str_of(s1, 2) == "unsupported" &&
                  is_nil_msg(p1) && str_of(p1, 1) == gsa1::board::kReasonNotRiding && is_nil_msg(f1) &&
                  str_of(f1, 1) == gsa1::board::kReasonNoKept && is_nil_msg(n1) && str_of(n1, 2) == "not_found" &&
                  off_ok && L.st.empty(),
              "Knuckles -> \"%s\"; Super Sonic (kind 8) -> \"%s\"; BoardPush not riding -> \"%s\"; BoardFree without a left "
              "board -> \"%s\" (all \"unsupported\"); no character -> not_found; Board(sonic, false) not riding -> %s",
              str_of(k1, 1).c_str(), str_of(s1, 1).c_str(), str_of(p1, 1).c_str(), str_of(f1, 1).c_str(),
              is_true(o1) ? "true" : str_of(o1, 1).c_str());
        Val out = Val::table();
        std::vector<Val> bs = R.state(sonic, out);
        static const struct { const char *k; int type; } fields[] = {
            {"on", Type::Bool}, {"pending", Type::Bool}, {"held", Type::Bool}, {"kept", Type::Bool}, {"settled", Type::Bool},
            {"board", Type::Bool}, {"mode", Type::Number}, {"action", Type::Number}, {"speed", Type::Number},
            {"terrain", Type::Number}, {"push_steps", Type::Number}, {"kind", Type::Number}, {"variant", Type::Number},
            {"x", Type::Number}, {"y", Type::Number}, {"z", Type::Number}, {"pitch", Type::Number}, {"yaw", Type::Number},
            {"roll", Type::Number}, {"still", Type::Number}, {"jump", Type::Number}, {"refused", Type::Bool},
            {"freed", Type::Number}, {"freed_why", Type::Number},
        };
        std::string missing;
        bool same = bs.size() == 1 && bs[0].type == Type::Table && bs[0].tab == out.tab;
        for (const auto &f : fields) {
            Val v = out.tab->field(f.k);
            if (v.type != f.type) missing += std::string(" ") + f.k;
            rec(gsa1::format("field\tBoardState\t%s\t%s", f.k, type_word(f.type)));
        }
        rec("field\tBoardState\treason\tstring (only when refused is true, else nil)");
        CHECK(same && missing.empty() && !field_bool(out, "on") && field_num(out, "kind") == -1 &&
                  field_num(out, "freed_why") == -1 && out.tab->field("reason").type == Type::Nil,
              "BoardState(sonic, out) fills the given table: %zu fields of the right types (on false, kind -1, freed_why "
              "-1, no reason)%s%s", sizeof fields / sizeof fields[0], missing.empty() ? "" : ": wrong", missing.c_str());
    }

    // ---- the behaviour part (review R.6) ------------------------------------------------------------------------------
    std::vector<Val> probe = L.call("Board", {Val::number(sonic), Val::boolean(true)});
    if (is_nil_msg(probe) && str_of(probe, 1).find("not built yet") != std::string::npos) {
        std::printf("SKIP behaviour: libsa1's board is not built yet\n");
        write_api("SKIP\tlibsa1's board is not built yet (the contract snapshot)");
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    CHECK(is_true(probe), "Board(sonic, true) -> true (%s)", str_of(probe, 1).c_str());
    Val out = Val::table();
    auto on_within = [&](double id, int max, int lo, int hi, int &at, double &action) {
        at = -1;
        for (int i = 1; i <= max && at < 0; i++) {
            R.pair(id);
            R.state(id, out);
            if (field_bool(out, "on") && field_num(out, "action") >= lo && field_num(out, "action") <= hi) {
                at = i;
                action = field_num(out, "action");
            }
        }
    };
    // B1 Sonic on
    int at_s = -1;
    double act_s = 0;
    on_within(sonic, 30, 102, 124, at_s, act_s);
    CHECK(at_s > 0 && field_bool(out, "held") && field_num(out, "kind") == 0,
          "Sonic: BoardState.on with action %g (102-124) after %d ticks, held, the board Sonic's (variant %g)", act_s, at_s,
          field_num(out, "variant"));
    // B14 the board's batches
    {
        R.pairs(sonic, 4);
        L.call("Render", {Val::number(sonic), Val::number(1)});
        gsa1::Character *c = R.ch(sonic);
        uint32_t board_b = 0, mixed = 0, textured = 0, body = 0;
        for (uint32_t b = 0; c && b < c->batch_count; b++) {
            const gsa1::RenderBatch &rb = c->batches[b];
            bool is_board = (rb.flags & SA1_DRAW_BOARD) != 0;
            board_b += is_board;
            body += !is_board;
            textured += is_board && rb.archive >= 0;
            for (uint32_t di : rb.draws) {
                mixed += ((c->r_draws[di].flags & SA1_DRAW_BOARD) != 0) != is_board;
            }
        }
        Val bt = Val::table();
        L.call("Batches", {Val::number(sonic), bt});
        bool lua_flag = false;
        for (uint32_t b = 1; b <= (uint32_t)field_num(bt, "count"); b++) {
            Val e = bt.tab->at(b);
            lua_flag = lua_flag || ((uint32_t)field_num(e, "flags") & 0x4000u) != 0;
        }
        CHECK(board_b > 0 && body > 0 && mixed == 0 && textured == board_b && lua_flag,
              "riding: %u board batch(es) with flags 0x4000, every one textured (archive >= 0), none merged with the body's "
              "%u batch(es); gsa1.Batches shows the flag", board_b, body);
    }
    // B12 the stage rules only for the rider; B13 BoardSounds
    {
        gsa1::Character *cs = R.ch(sonic), *ck = R.ch(knux);
        gsa1::StageRule r1, r2, r3;
        bool rider = cs && cs->board.rider && cs->board.rules_on &&
                     R.se->audio().stage_rule((int32_t)sonic, gsa1::kRuleBoardSnow, r1) && r1.stage == 8 &&
                     R.se->audio().stage_rule((int32_t)sonic, gsa1::kRuleBoardSand, r2) && r2.stage == 38;
        bool other = ck && !ck->board.rules_on && !R.se->audio().stage_rule((int32_t)knux, gsa1::kRuleBoardSnow, r3);
        std::string e;
        bool opened = R.se->audio_open(false, e);
        int32_t st1 = R.se->audio().rule_status((int32_t)sonic, gsa1::kRuleBoardSnow);
        int32_t st2 = R.se->audio().rule_status((int32_t)sonic, gsa1::kRuleBoardSand);
        CHECK(rider && other && opened && st1 == SA1_OK && st2 == SA1_OK,
              "the stage rules: the riding Sonic holds {8, 208-238} and {38, 690-698}, Knuckles (on foot) none; the sound "
              "banks opened: both installed for him (%d / %d)%s%s", (int)st1, (int)st2, opened ? "" : ": ", e.c_str());
        R.pairs(sonic, 20, 0.0, 1.0);
        uint64_t ev0 = R.se->audio().events();
        std::vector<Val> off = L.call("BoardSounds", {Val::boolean(false)});
        uint64_t stops = R.se->audio().events() - ev0;
        uint64_t muted0 = cs ? cs->board.tones_muted : 0;
        R.pairs(sonic, 40, 0.0, 1.0);
        uint64_t muted = cs ? cs->board.tones_muted - muted0 : 0;
        bool cleared = cs && !cs->board.rules_on;
        std::vector<Val> on = L.call("BoardSounds", {Val::boolean(true)});
        bool back = cs && cs->board.rules_on;
        CHECK(is_true(off) && stops == 40 && cleared && is_true(on) && back,
              "BoardSounds(false) while riding: %llu SOUND_STOPs (one per board tone 208-238 / 690-698: the playing 690 ends, "
              "review R.12), the rules cleared, %llu board tones kept out in 40 pairs; BoardSounds(true): the rules again",
              (unsigned long long)stops, (unsigned long long)muted);
        R.se->audio_close();
    }
    // B4 Sonic off: the action 18 in the first pair after OFF, the board kept and settled, its pose near him. Off while
    // riding forward (action 102, as the research's exit runs: board095_lib.md 2.3 E); from the board's stand (action 115,
    // a neutral stick) the first pair after OFF still shows 115 (measured), then 10
    {
        R.pairs(sonic, 10, 0.0, 1.0);
        std::vector<Val> o = L.call("Board", {Val::number(sonic), Val::boolean(false)});
        R.pair(sonic);
        R.state(sonic, out);
        double a1 = field_num(out, "action");
        bool on1 = field_bool(out, "on");
        int settled = -1;
        for (int i = 1; i <= 120 && settled < 0; i++) {
            R.pair(sonic);
            R.state(sonic, out);
            if (field_bool(out, "kept") && field_bool(out, "settled")) settled = i;
        }
        gsa1::Character *c = R.ch(sonic);
        double dx = c ? field_num(out, "x") - c->st.position[0] : 1e9, dy = c ? field_num(out, "y") - c->st.position[1] : 1e9,
               dz = c ? field_num(out, "z") - c->st.position[2] : 1e9;
        double d = std::sqrt(dx * dx + dy * dy + dz * dz);
        CHECK(is_true(o) && a1 == 18 && !on1 && settled > 0 && d < 64.0,
              "Sonic off: action %g in the first pair (18; the mode is not checked, review R.13), not on; the board kept and "
              "settled after %d more ticks, its pose %.1f HU from him (< 64; pitch %.1f yaw %.1f roll %.1f, still %g)", a1,
              settled, d, field_num(out, "pitch"), field_num(out, "yaw"), field_num(out, "roll"), field_num(out, "still"));
    }
    // B6 ON after OFF: a new board (the kept one freed: why 2); then B5 BoardFree
    {
        double f0 = R.freed_total;
        std::vector<Val> on = L.call("Board", {Val::number(sonic), Val::boolean(true)});
        int at = -1;
        double act = 0;
        on_within(sonic, 30, 102, 124, at, act);
        double freed = R.freed_total - f0, why = R.last_why;
        CHECK(is_true(on) && at > 0 && field_bool(out, "held") && !field_bool(out, "kept") && freed == 1 && why == 2,
              "ON with a kept board (gsa1_095_plan.md 4.4 a): on again after %d ticks with a NEW board held, none left lying; "
              "the kept one freed (%g, why %g: 2 = replaced by a new ON)", at, freed, why);
        std::vector<Val> off = L.call("Board", {Val::number(sonic), Val::boolean(false)});
        R.pairs(sonic, 40);
        R.state(sonic, out);
        bool kept = field_bool(out, "kept");
        double f1 = R.freed_total;
        std::vector<Val> fr = L.call("BoardFree", {Val::number(sonic)});
        R.state(sonic, out);
        bool gone_now = !field_bool(out, "board");
        R.pair(sonic);
        R.state(sonic, out);
        double nf = R.freed_total - f1, fw = R.last_why;
        std::vector<Val> fr2 = L.call("BoardFree", {Val::number(sonic)});
        std::vector<Val> off2 = L.call("Board", {Val::number(sonic), Val::boolean(false)});   // on foot, no board: nothing
        CHECK(is_true(off) && kept && is_true(fr) && gone_now && nf == 1 && fw == 3 && is_nil_msg(fr2) &&
                  str_of(fr2, 1) == gsa1::board::kReasonNoKept && is_true(off2),
              "off again, the board kept; BoardFree -> true, no board at once (review R.9), freed %g with why %g (3) after "
              "the next pair; BoardFree again -> \"%s\"; Board(sonic, false) on foot -> true (nothing to do)", nf, fw,
              str_of(fr2, 1).c_str());
    }
    // B11 OFF with remove (review R.5)
    {
        L.call("Board", {Val::number(sonic), Val::boolean(true)});
        int at = -1;
        double act = 0;
        on_within(sonic, 30, 102, 124, at, act);
        Val o = Val::table();
        o.tab->set(Val::string("remove"), Val::boolean(true));
        std::vector<Val> off = L.call("Board", {Val::number(sonic), Val::boolean(false), o});
        R.pair(sonic);
        R.state(sonic, out);
        bool none = !field_bool(out, "board") && !field_bool(out, "kept");
        R.pair(sonic);
        R.state(sonic, out);
        CHECK(at > 0 && is_true(off) && none && !field_bool(out, "board"),
              "Board(sonic, false, {remove = true}) while riding: no board one tick later (review R.5: libsa1 reads remove "
              "at OFF)");
    }
    // B9 the push; B10 the push ends with the ride (review R.2)
    {
        R.pairs(sonic, 20);
        Val o = Val::table();
        o.tab->set(Val::string("push"), Val::boolean(true));
        std::vector<Val> on = L.call("Board", {Val::number(sonic), Val::boolean(true), o});
        double sp100 = -1, steps = -1;
        for (int i = 1; i <= 100; i++) {
            R.pair(sonic, 0.0, i >= 60 ? 1.0 : 0.0);
            if (i == 2) {
                R.state(sonic, out);
                steps = field_num(out, "push_steps");
            }
        }
        R.state(sonic, out);
        sp100 = field_num(out, "speed");
        CHECK(is_true(on) && sp100 >= 3.99, "Board(sonic, true, {push = true}): speed %.3f u/step 100 pairs later (>= 3.99: "
              "Ice Cap's 4.0; push_steps %g two pairs in)", sp100, steps);
        L.call("Board", {Val::number(sonic), Val::boolean(false)});
        R.pairs(sonic, 30);
        L.call("Board", {Val::number(sonic), Val::boolean(true), o});
        R.pairs(sonic, 10);
        std::vector<Val> off = L.call("Board", {Val::number(sonic), Val::boolean(false)});
        double sp[3] = {0, 0, 0};
        for (int i = 0; i < 3; i++) {
            R.pair(sonic);
            R.state(sonic, out);
            sp[i] = field_num(out, "speed");
        }
        CHECK(is_true(off) && !field_bool(out, "on") && (sp[0] < 3.99 || sp[1] < 3.99 || sp[2] < 3.99) &&
                  field_num(out, "push_steps") == 0,
              "a pushed ride ended after 10 ticks: on foot the speed is %.3f / %.3f / %.3f in the next 3 ticks (one < 3.99), "
              "push_steps 0 (review R.2: the push ends with the ride)", sp[0], sp[1], sp[2]);
        R.pairs(sonic, 60);
    }
    // B8 terrain SNOW on the flat SOLID plane
    {
        Val o = Val::table();
        o.tab->set(Val::string("terrain"), Val::number(1));
        std::vector<Val> on = L.call("Board", {Val::number(sonic), Val::boolean(true), o});
        int at = -1;
        double act = 0;
        on_within(sonic, 30, 102, 124, at, act);
        R.pairs(sonic, 10);
        gsa1::Character *c = R.ch(sonic);
        uint32_t attr_on = c ? c->st.attr : 0;
        double terr = field_num(out, "terrain");
        L.call("Board", {Val::number(sonic), Val::boolean(false)});
        R.pairs(sonic, 20);
        uint32_t attr_off = c ? c->st.attr : 0xFFFFFFFFu;
        CHECK(is_true(on) && at > 0 && (attr_on & 0x8u) && terr == 1 && !(attr_off & 0x8u),
              "Board(sonic, true, {terrain = TERRAIN_SNOW}) on flat SOLID: the land's attr 0x%X while riding (0x8: Ice Cap's "
              "snow; BoardState.terrain %g), 0x%X on foot after OFF", (unsigned)attr_on, terr, (unsigned)attr_off);
        L.call("BoardFree", {Val::number(sonic)});
        R.pairs(sonic, 10);
    }
    // B7 a carrying Sonic is refused once
    {
        gsa1::interact::Registry HR;
        gsa1::Character *c = R.ch(sonic);
        float yaw = c ? c->st.yaw : 0.0f;
        gsa1::interact::ObjArgs hb;
        hb.ent = 202;
        hb.kind = SA1_HOSTOBJ_HOLDABLE;
        hb.flags = SA1_HOSTOBJ_NOT_SOLID;
        hb.pos[0] = (c ? c->st.position[0] : 0.0f) + 40.0f * std::cos(yaw);
        hb.pos[1] = (c ? c->st.position[1] : 0.0f) + 40.0f * std::sin(yaw);
        hb.pos[2] = (c ? c->st.position[2] : 0.0f) + 10.0f;
        hb.nshapes = 1;
        hb.shapes[0].form = SA1_SHAPE_BOX;
        hb.shapes[0].size[0] = hb.shapes[0].size[1] = hb.shapes[0].size[2] = 10.0f;
        uint32_t hid = 0;
        bool added = false;
        std::string e;
        sa1_status hs = HR.set(R.se->ctx(), hb, hid, &added, e);
        R.pairs(sonic, 2);
        int took = 0;
        for (int i = 0; i < 40 && !took; i++) {
            R.pair(sonic, 0.0, 0.0, i == 0 ? SA1_BUTTON_ACTION : 0u);
            took = c && c->st.held_object == hid && hid ? i + 1 : 0;
        }
        std::vector<Val> on = L.call("Board", {Val::number(sonic), Val::boolean(true)});
        bool refused = false;
        std::string reason;
        int when = -1;
        for (int i = 1; i <= 4 && !refused; i++) {
            R.pair(sonic);
            R.state(sonic, out);
            if (field_bool(out, "refused")) {
                refused = true;
                reason = out.tab->field("reason").str;
                when = i;
            }
        }
        R.state(sonic, out);
        bool once = !field_bool(out, "refused") && out.tab->field("reason").type == Type::Nil && !field_bool(out, "on") &&
                    !field_bool(out, "board");
        CHECK(hs == SA1_OK && took > 0 && is_true(on) && refused && reason == gsa1::board::kReasonCarrying && once,
              "Sonic carrying a HOLDABLE box (lifted after %d pairs): Board -> true (posted), refused after %d pair(s) with "
              "\"%s\", once; no board left, not on", took, when, reason.c_str());
        HR.clear(R.se->ctx());
        R.pairs(sonic, 30);
    }
    // B2 Tails on / off
    {
        double tails = R.create(2, 0.0f, 600.0f);
        R.pairs(tails, 10);
        std::vector<Val> on = L.call("Board", {Val::number(tails), Val::boolean(true)});
        int at = -1;
        double act = 0;
        on_within(tails, 30, 107, 127, at, act);
        bool kind2 = field_num(out, "kind") == 2;
        R.pairs(tails, 10);
        std::vector<Val> off = L.call("Board", {Val::number(tails), Val::boolean(false)});
        R.pair(tails);
        R.state(tails, out);
        double a1 = field_num(out, "action");
        CHECK(is_true(on) && at > 0 && kind2 && is_true(off) && a1 == 19 && !field_bool(out, "on"),
              "Tails: on with action %g (107-127) after %d ticks, the board Tails' (kind 2); off: action %g in the first pair "
              "(19), not on", act, at, a1);
        L.call("Destroy", {Val::number(tails)});
    }
    // B15 the BOARD preview
    {
        auto add = [&](int kind, int variant) {
            Val d = Val::table();
            d.tab->set(Val::string("kind"), Val::number(kind));
            d.tab->set(Val::string("type"), Val::number(gsa1::board::kPreviewBoard));
            Val p = Val::table();
            p.tab->set(Val::number(1), Val::number(variant));
            p.tab->set(Val::number(2), Val::number(0));
            p.tab->set(Val::number(3), Val::number(0));
            d.tab->set(Val::string("params"), p);
            d.tab->set(Val::string("state"), Val::number(1));
            return L.call("PreviewAdd", {d});
        };
        std::vector<Val> a0 = add(0, 0), a1 = add(0, 1), a2 = add(2, 0), a3 = add(3, 0);
        for (int i = 0; i < 6; i++) L.call("PreviewTick", {Val::number(1.0 / 30.0)});
        std::string seen;
        bool all = true;
        double minz = 0;
        for (const auto *a : {&a0, &a1, &a2}) {
            double id = num_of(*a, 0);
            std::vector<Val> r = L.call("PreviewRender", {Val::number(id), Val::number(1)});
            Val bt = Val::table();
            L.call("PreviewBatches", {Val::number(id), bt});
            double tris = field_num(bt, "triangles");
            bool tex = true, flag = true;
            for (uint32_t b = 1; b <= (uint32_t)field_num(bt, "count"); b++) {
                Val e = bt.tab->at(b);
                tex = tex && field_num(e, "archive") >= 0;
                flag = flag && ((uint32_t)field_num(e, "flags") & 0x4000u);
            }
            std::vector<Val> info = L.call("PreviewInfo", {Val::number(id)});
            if (a == &a0) minz = num_of(info, 4);
            seen += gsa1::format(" %g tris%s%s", tris, tex ? "" : " (untextured)", flag ? "" : " (no 0x4000)");
            all = all && id > 0 && r.size() == 4 && tris == 44 && tex && flag;
        }
        CHECK(all && is_nil_msg(a3) && str_of(a3, 2) == "unsupported",
              "PreviewAdd({kind 0 variant 0 / 1, kind 2, type gsa1.PREVIEW.BOARD}):%s, every batch textured and 0x4000; "
              "kind 3 -> unsupported; PreviewInfo's minz of Sonic's board %.2f HU (the lift the lying board needs)",
              seen.c_str(), minz);
        L.call("PreviewClear", {});
    }
    // B16 BoardState per frame: no table made with `out`, its cost
    {
        Val o = Val::table();
        uint64_t t0 = L.tables;
        double ms0 = gsa1::now_ms();
        const int n = 20000;
        for (int i = 0; i < n; i++) {
            L.call("BoardState", {Val::number(sonic), o});
        }
        double us = (gsa1::now_ms() - ms0) * 1000.0 / n;
        uint64_t made = L.tables - t0;
        CHECK(made == 0, "BoardState(id, out) x %d: %llu tables made (none: per frame, no garbage), %.2f us per call in the "
              "mock (the Lua stack's own cost included)", n, (unsigned long long)made, us);
    }
    // M1 (measured, no pass / fail): a kept board on gm_construct's own collision (the map loaded again, Sonic at its
    // spawn): does libsa1 report it SETTLED? (the Lua hand-over falls back to 2 s when it does not)
    {
        std::vector<Val> wl2 = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
        double gm = R.create(0, 704.0f, 132.0f, -139.0f, 180.0);
        R.pairs(gm, 20);
        L.call("Board", {Val::number(gm), Val::boolean(true)});
        R.pairs(gm, 25, 0.0, 1.0);
        L.call("Board", {Val::number(gm), Val::boolean(false)});
        int settled = -1;
        double still = 0;
        for (int i = 1; i <= 120 && settled < 0; i++) {
            R.pair(gm);
            R.state(gm, out);
            still = field_num(out, "still");
            if (field_bool(out, "settled")) settled = i;
        }
        INFO("M1 gm_construct (WorldLoadData %s): a board left after a 25-pair ride %s (still_steps %g; kept %s, pose %.1f "
             "%.1f %.1f)", wl2.size() == 2 && wl2[0].b ? "ok" : "failed",
             settled > 0 ? gsa1::format("settled %d pairs after the exit", settled).c_str() : "never settled in 120 pairs",
             still, field_bool(out, "kept") ? "yes" : "no", field_num(out, "x"), field_num(out, "y"), field_num(out, "z"));
        L.call("Destroy", {Val::number(gm)});
    }
    write_api("RAN\tthe behaviour part ran in full (libsa1's board is built)");
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
#endif
}
