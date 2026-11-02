// feat_charselect_binding_test: the module's feature "frontend" (round 0.9.8; sadc docs/research/gsa1_098_plan.md 5.5, 6.10 with its
// review R98.11, R98.14, R98.20; charsel098.md 6.6, 7 "G-SA1" item 2; src/module/bind_frontend.cpp, src/core/frontend.*). Linked like
// binding_test (the module's objects, libsa1, the mock Lua stack of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi.
//
//   feat_charselect_binding_test [--gdi GAME.gdi] [--verbose]
//
// A libsa1 without SA1_API_FRONTEND: no feature "frontend", no gsa1.Frontend*, and the addon's simple chooser is what plays.
// With it:
//   * WITHOUT THE DISC: gsa1.FEATURES.frontend = 1, every function registered, gsa1.FRONTEND has libsa1's numbers; bad arguments and
//     calls with nothing open answer nil, message, code; never a Lua error; gsa1.Texture stays range-checked (2.4 C2). It writes
//     build/<target>/frontend_api.txt (5.5; the Lua test checks its mock against it);
//   * THE BEHAVIOUR PART prints exactly one line "SKIP behaviour: frontend is not built yet" and passes while libsa1 answers that
//     text (the gate of src/sa1_frontend.c is closed; the plan's 5.3). The final gates fail when the SKIP line appears. Otherwise
//     with the disc: open, RIGHT, A -> "select" 1, "pick" 1, kind 2, voice 1800 in the mixer's stats, FrontendScreen nd > 40,
//     FrontendRender batches > 0, the first sphe_7 draw and its six others, the textures through FrontendTexture, the tick under 2 ms
//     (reported, on a quiet machine), close, reopen; a second open "open"; R98.20: gsa1.Shutdown and the module's close leave nothing
//     dangling, every call answers "not_ready" afterwards.
//
// API NOTES (098-gsa1-charsel, the full text; the report carries a summary):
//   Module: gsa1.Frontend* as the head of src/module/bind_frontend.cpp lists them; code "not_ready" also means "no front end is open".
//   Lua: GSA1.CharSelect = S (feat/sh_charselect.lua: the pure part; feat/cl_charselect.lua: S.Open(how), S.Close(why), S.IsOpen(),
//   S.Toggle(how), S.st (nil: closed; design "R" or "S", slot, how, panel, picked), S.cv); chains GSA1.InputBlocked; a pick is GSA1.Spawn.
//   cl_textures.lua: T.Archives, T.Get, T.Prepare and T.Material take gsa1.FRONTEND.KIND; T.Info(kind, archive, index); T.PaintNow(kind)
//   paints every texture of a kind at once, in PostRender. cl_jukebox.lua: P.SelectPlay(music), P.SelectStop(fade), P.CH_SELECT 1,
//   holdWhy "charselect" (the personal channel's own pause: the engine's hold and the volume factor are for every channel).
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
#include "../src/core/config.hpp"
#include "../src/core/frontend.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"

#if !defined(GSA1_HAS_FRONTEND)

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    std::printf("G-SA1 feat_charselect_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    gmod13_open(&state);
    Val g = L.globals.tab->field("gsa1");
    Val feats = g.type == Type::Table ? g.tab->field("FEATURES") : Val();
    CHECK(g.type == Type::Table && feats.type == Type::Table && feats.tab->field("frontend").type == Type::Nil &&
              g.tab->field("FrontendOpen").type == Type::Nil,
          "this libsa1 has no SA1_API_FRONTEND: no feature \"frontend\" (the addon's simple chooser plays)");
    std::printf("  info  frontend_api.txt is written only with libsa1's front end (SA1_API_FRONTEND)\n");
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}

#else

namespace {

bool g_verbose = false;

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1.0;
}
// nil, a message, this code
bool is_refusal(const std::vector<Val> &r, const char *code)
{
    return r.size() >= 2 && r[0].type == Type::Nil && r[1].type == Type::String && !r[1].str.empty() && str_of(r, 2) == code;
}

const char *const kFunctions[][3] = {
    {"FrontendOpen", "{slot, language, dialog}", "true | nil, message, code"},
    {"FrontendClose", "", "true"},
    {"FrontendTick", "dt, sx, sy, buttons", "frames | nil, message, code"},
    {"FrontendState", "[out]", "out | nil, message, code"},
    {"FrontendEvents", "[out]", "n, out | nil, message, code"},
    {"FrontendScreen", "out [, force]", "generation, changed | nil, message, code"},
    {"FrontendRender", "", "batches, generation, kind | nil, message, code"},
    {"FrontendBatches", "[out]", "count, out | nil"},
    {"FrontendPrepareView", "eye, right, up [, flip, vertexColor, linePixels, lit]", "true | nil"},
    {"FrontendEmitBatch", "b", "vertices | nil, message"},
    {"FrontendView", "", "eye, angles, fov | nil, message, code"},
    {"FrontendTextureArchives", "", "list | nil, message, code"},
    {"FrontendTextureCount", "[archive]", "n | nil, message"},
    {"FrontendTexture", "index [, archive]", "table | nil, message"},
    {"FrontendTexturePixel", "archive, index, x, y", "r, g, b, a | nil"},
    {"FrontendStats", "[out]", "out"},
};

Val open_args(int slot, int language = 1, bool dialog = false)
{
    Val t = Val::table();
    t.tab->set(Val::string("slot"), Val::number(slot));
    t.tab->set(Val::string("language"), Val::number(language));
    t.tab->set(Val::string("dialog"), Val::boolean(dialog));
    return t;
}

struct Rig {
    MockLua *L = nullptr;
    Val events, screen, state;
    int select_slot = -1, pick_slot = -1, done = 0, cancel = 0, music = -2;
    uint32_t frames = 0;
    double tick_ms_max = 0.0;

    // n game frames of 1/60 s with these buttons held on the first; the events kept
    bool run(int n, double buttons, double sx = 0.0, double sy = 0.0)
    {
        for (int i = 0; i < n; i++) {
            double t0 = gsa1::now_ms();
            std::vector<Val> r = L->call("FrontendTick", {Val::number(1.0 / 60.0 + 1e-6), Val::number(sx), Val::number(sy),
                                                          Val::number(i == 0 ? buttons : 0.0)});
            tick_ms_max = std::max(tick_ms_max, gsa1::now_ms() - t0);
            if (r.empty() || r[0].type != Type::Number) {
                std::printf("  info  FrontendTick: %s\n", str_of(r, 1).c_str());
                return false;
            }
            frames += (uint32_t)r[0].num;
            std::vector<Val> e = L->call("FrontendEvents", {events});
            int m = (int)num_of(e, 0);
            for (int k = 1; k <= m; k++) {
                Val v = events.tab->get(Val::number(k));
                std::string kind = v.tab->field("kind").str;
                int id = (int)v.tab->field("id").num;
                if (kind == "select") {
                    select_slot = id;
                } else if (kind == "pick") {
                    pick_slot = id;
                } else if (kind == "done") {
                    done++;
                } else if (kind == "cancel") {
                    cancel++;
                } else if (kind == "music") {
                    music = id;
                }
            }
        }
        return true;
    }
};

}  // namespace

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i < argc; i++) {
        if (std::string(argv[i]) == "--gdi" && i + 1 < argc) gdi = argv[++i];
        else if (std::string(argv[i]) == "--verbose") g_verbose = true;
    }
    std::printf("G-SA1 feat_charselect_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_charselect_appdata");
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
    Val F = g.type == Type::Table ? g.tab->field("FRONTEND") : Val();
    Val ferr = g.type == Type::Table ? g.tab->field("FEATURE_ERRORS") : Val();
    bool fns = g.type == Type::Table;
    for (auto &f : kFunctions) {
        fns = fns && g.tab->field(f[0]).type == Type::Function;
    }
    CHECK(fns && feats.type == Type::Table && feats.tab->field("frontend").num == 1 && ferr.type == Type::Table && ferr.tab->n.empty() &&
              L.st.empty(), "gsa1.FEATURES.frontend = 1, every function registered, no clash");
    if (g.type != Type::Table || F.type != Type::Table) {
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    CHECK(F.tab->field("KIND").num == SA1_KIND_FRONTEND && F.tab->field("KIND").num == 32 && F.tab->field("PRI_3D").num == -20 &&
              F.tab->field("LEFT").num == SA1_FRONTEND_B_LEFT && F.tab->field("RIGHT").num == SA1_FRONTEND_B_RIGHT &&
              F.tab->field("UP").num == SA1_FRONTEND_B_UP && F.tab->field("DOWN").num == SA1_FRONTEND_B_DOWN &&
              F.tab->field("A").num == SA1_FRONTEND_B_A && F.tab->field("B").num == SA1_FRONTEND_B_B &&
              F.tab->field("START").num == SA1_FRONTEND_B_START,
          "gsa1.FRONTEND has libsa1's numbers (KIND 32, PRI_3D -20)");
    // the angles of the game's view
    {
        const float fw[3] = {0.0f, 1.0f, 0.0f}, up[3] = {0.0f, 0.0f, 1.0f};
        float a[3] = {9, 9, 9};
        gsa1::frontend::view_angles(fw, up, a);
        const float fw2[3] = {0.0f, 0.0f, -1.0f}, up2[3] = {1.0f, 0.0f, 0.0f};
        float b[3] = {9, 9, 9};
        gsa1::frontend::view_angles(fw2, up2, b);
        CHECK(std::fabs(a[0]) < 1e-3f && std::fabs(a[1] - 90.0f) < 1e-3f && std::fabs(a[2]) < 1e-3f && std::fabs(b[0] - 90.0f) < 1e-3f,
              "view_angles: looking along +y: yaw 90 (%.2f %.2f %.2f); straight down: pitch 90 (%.2f)", a[0], a[1], a[2], b[0]);
    }
    // no disc, nothing open, bad arguments: answers, never a Lua error
    int bad = 0;
    bad += !is_refusal(L.call("FrontendOpen", {}), "not_ready");
    bad += !is_refusal(L.call("FrontendOpen", {Val::string("x")}), "bad_argument");
    bad += !is_refusal(L.call("FrontendOpen", {open_args(7)}), "bad_argument");
    bad += !is_refusal(L.call("FrontendOpen", {open_args(1, 5)}), "bad_argument");
    bad += !is_refusal(L.call("FrontendTick", {Val::number(1)}), "bad_argument");
    bad += !is_refusal(L.call("FrontendTick", {Val::number(-1), Val::number(0), Val::number(0), Val::number(0)}), "bad_argument");
    bad += !is_refusal(L.call("FrontendTick", {Val::number(0.1), Val::number(0), Val::number(0), Val::number(0)}), "not_ready");
    bad += !is_refusal(L.call("FrontendState", {}), "not_ready");
    bad += !is_refusal(L.call("FrontendEvents", {}), "not_ready");
    bad += !is_refusal(L.call("FrontendScreen", {Val::table()}), "not_ready");
    bad += !is_refusal(L.call("FrontendScreen", {}), "bad_argument");
    bad += !is_refusal(L.call("FrontendRender", {}), "not_ready");
    bad += !is_refusal(L.call("FrontendView", {}), "not_ready");
    bad += !is_refusal(L.call("FrontendEmitBatch", {Val::number(1)}), "bad_argument");
    bad += L.call("FrontendBatches", {}).at(0).type != Type::Nil;
    bad += L.call("FrontendPrepareView", {Val::number(1)}).at(0).type != Type::Nil;
    bad += L.call("FrontendTexturePixel", {Val::number(0)}).at(0).type != Type::Nil;
    bad += L.call("FrontendClose", {}).at(0).type != Type::Bool;
    CHECK(bad == 0 && L.st.empty(), "bad arguments and calls with nothing open: nil, message, code (%d wrong)", bad);
    // gsa1.Texture stays range-checked (2.4 C2)
    std::vector<Val> tr = L.call("TextureCount", {Val::number(SA1_KIND_FRONTEND)});
    CHECK(tr.size() >= 2 && tr[0].type == Type::Nil, "gsa1.TextureCount(32) stays a refusal: the menu's textures come through gsa1.FrontendTexture");

    std::vector<std::string> api;
    auto rec = [&](const std::string &s) { api.push_back(s); };
    rec("feature\tfrontend\t1");
    for (auto &f : kFunctions) {
        rec(gsa1::format("function\t%s\t%s\t%s", f[0], f[1], f[2]));
    }
    for (const char *c : {"KIND", "PRI_3D", "LEFT", "RIGHT", "UP", "DOWN", "A", "B", "START", "SLOTS"}) {
        rec(gsa1::format("const\t%s\t%g", c, F.tab->field(c).num));
    }
    for (const char *c : {"slot", "slots", "phase", "frame", "pose_frames", "kind", "faults"}) {
        rec(gsa1::format("field\tFrontendState\t%s\tnumber", c));
    }
    for (const char *c : {"select", "pick", "done", "cancel", "music"}) {
        rec(gsa1::format("event\t%s", c));
    }
    for (const char *c : {"not_ready", "open", "fault", "bad_argument"}) {
        rec(gsa1::format("code\t%s", c));
    }
    auto write_api = [&](const char *behaviour) {
        std::string path = gsa1::join_path(self.empty() ? "." : self, "frontend_api.txt");
        std::string text = "# G-SA1 frontend_api.txt: the module contract of round 0.9.8 (sadc docs/research/gsa1_098_plan.md 5.5)\n"
                           "# written by tests/feat_charselect_binding_test.cpp from the module as built against this target's\n"
                           "# build/deps/include/libsa1.h (" + std::string(sa1_version_string()) + "). Tab-separated records:\n"
                           "# feature | function | const | field | event | code | behaviour\n";
        for (const std::string &r : api) {
            text += r + "\n";
        }
        text += std::string("behaviour\t") + behaviour + "\n";
        std::FILE *f = std::fopen(path.c_str(), "wb");
        bool ok = f && std::fwrite(text.data(), 1, text.size(), f) == text.size();
        if (f) std::fclose(f);
        CHECK(ok, "frontend_api.txt written: %s (%zu records)", path.c_str(), api.size() + 1);
    };

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the behaviour part needs the disc\n");
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
    if (ist != "ready") {
        write_api("SKIP\tthe disc did not load");
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }

    std::vector<Val> op = L.call("FrontendOpen", {open_args(0)});
    if (op.size() >= 2 && op[0].type == Type::Nil && str_of(op, 1).find("not built yet") != std::string::npos) {
        std::printf("SKIP behaviour: frontend is not built yet\n");
        write_api("SKIP\tfrontend is not built yet");
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    CHECK(!op.empty() && op[0].type == Type::Bool && op[0].b, "FrontendOpen: %s %s", str_of(op, 1).c_str(), str_of(op, 2).c_str());
    if (op.empty() || op[0].type != Type::Bool) {
        write_api("SKIP\tthe open failed");
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    CHECK(is_refusal(L.call("FrontendOpen", {open_args(0)}), "open"), "a second open: \"open\"");

    // the sound banks: the voice has to reach the mixer's stats
    L.call("AudioOpen", {Val::boolean(false)});
    for (int k = 0; k < 20000; k++) {
        std::vector<Val> ap = L.call("AudioPoll", {});
        if (!ap.empty() && ap[0].type == Type::Bool) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    Rig R;
    R.L = &L;
    R.events = Val::table();
    R.screen = Val::table();
    R.state = Val::table();
    // the first drawn frame: the game's music request and 48 + 1 draws
    CHECK(R.run(1, 0), "the first tick");
    CHECK(R.music == 24, "the game asks for its music: \"music\" 24 (Choose Your Buddy!) (%d)", R.music);
    std::vector<Val> sc = L.call("FrontendScreen", {R.screen});
    double nd = R.screen.tab->field("nd").num;
    // (libsa1 merges neighbours of one state into one draw: the game's 48 + 1 quads are fewer draws, 6 vertices a quad)
    CHECK(num_of(sc, 0) >= 0 && nd >= 25 && R.screen.tab->field("w").num == 640 && R.screen.tab->field("h").num == 480 &&
              R.screen.tab->field("nv").num >= 40 * 6, "FrontendScreen: %g draws, %g vertices (over 40 quads), 640 x 480", nd, R.screen.tab->field("nv").num);
    std::vector<Val> sc2 = L.call("FrontendScreen", {R.screen});
    CHECK(sc2.size() == 2 && sc2[1].type == Type::Bool && !sc2[1].b, "the same frame asked again: not copied");
    // the archives and the draws' textures resolve
    Val arch = L.call("FrontendTextureArchives", {}).at(0);
    size_t narch = arch.type == Type::Table ? arch.tab->n.size() : 0;
    CHECK(narch == 9, "FrontendTextureArchives: the menu's nine archives (%zu)", narch);
    bool names_ok = narch > 0;
    double total = 0;
    int back_archive = -1;
    for (size_t a = 1; a <= narch; a++) {
        Val e = arch.tab->get(Val::number((double)a));
        std::string nm = e.tab->field("name").str;
        double count = e.tab->field("count").num;
        total += count;
        names_ok = names_ok && !nm.empty() && count > 0;
        if (nm == "AVA_BACK") back_archive = (int)a - 1;
        if (g_verbose) std::printf("  info  archive %zu: %s, %g textures\n", a - 1, nm.c_str(), count);
    }
    CHECK(names_ok && total > 40 && back_archive >= 0, "each with a name and textures: %g in all, the sky's AVA_BACK is archive %d", total, back_archive);
    Val td = R.screen.tab->field("d");
    int spheres = 0, unresolved = 0, behind = 0, sky = 0;
    std::map<std::string, int> used;
    for (int d = 0; d < (int)nd; d++) {
        int k = d * 11;
        double archive = td.tab->get(Val::number(k + 4)).num, texture = td.tab->get(Val::number(k + 5)).num;
        double flags = td.tab->get(Val::number(k + 6)).num, pri = td.tab->get(Val::number(k + 9)).num;
        behind += pri < -20.0;
        sky += (int)archive == back_archive;
        if (archive >= 0 && texture >= 0) {
            std::vector<Val> ti = L.call("FrontendTexture", {Val::number(texture), Val::number(archive)});
            if (ti.empty() || ti[0].type != Type::Table) {
                unresolved++;
            } else {
                std::string nm = ti[0].tab->field("name").str;
                used[nm]++;
                if (nm == "sphe_7") {
                    // (libsa1 merges neighbours of one state: 6 vertices a quad)
                    spheres += (int)(td.tab->get(Val::number(k + 3)).num / 6.0);
                }
            }
        } else if (!((uint32_t)flags & SA1_DRAW_NO_TEXTURE) && g_verbose) {
            std::printf("  info  draw %d has no texture (flags 0x%x)\n", d, (unsigned)flags);
        }
    }
    CHECK(unresolved == 0, "every draw's texture comes through gsa1.FrontendTexture (%d unresolved)", unresolved);
    CHECK(spheres >= 7, "the ring's seven sphe_7 quads and the bottom bar's (%d)", spheres);
    CHECK(sky >= 1, "the sky's draws are found by the archive AVA_BACK (%d)", sky);
    CHECK(behind == (int)nd, "all %d draws are behind the 3D (priority below PRI_3D; the dialog's are in front)", behind);
    if (g_verbose) {
        for (auto &u : used) std::printf("  info  texture %s: %d draws\n", u.first.c_str(), u.second);
    }
    // the game's screen takes a press from its 10th drawn frame on (charsel098 3.1), and the character stands in the circle by
    // frame 199 of the screen (131 ran at the open)
    CHECK(R.run(80, 0), "80 frames: the character is there");
    // the view
    std::vector<Val> vw = L.call("FrontendView", {});
    CHECK(vw.size() == 3 && vw[0].type == Type::Vector && vw[1].type == Type::Angle && std::fabs(num_of(vw, 2) - 70.0) < 0.5,
          "FrontendView: an eye, angles and the game's 70 degrees (%.2f)", num_of(vw, 2));
    // the selected character's 3D
    std::vector<Val> rd = L.call("FrontendRender", {});
    CHECK(rd.size() == 3 && num_of(rd, 0) > 0 && num_of(rd, 2) == 0, "FrontendRender: %g batches of kind %g", num_of(rd, 0), num_of(rd, 2));
    Val bt = Val::table();
    std::vector<Val> br = L.call("FrontendBatches", {bt});
    CHECK(num_of(br, 0) == num_of(rd, 0) && bt.tab->field("triangles").num > 500,
          "FrontendBatches: %g triangles of Sonic (charsel098 3.3: 1,001)", bt.tab->field("triangles").num);
    {
        std::vector<Val> pv = L.call("FrontendPrepareView", {vw[0], Val::vector(1, 0, 0), Val::vector(0, 0, 1)});
        CHECK(!pv.empty() && pv[0].type == Type::Bool, "FrontendPrepareView");
        install_mesh_library(L);
        g_mesh = MeshRec();
        std::vector<Val> em = L.call("FrontendEmitBatch", {Val::number(1)});
        Val b1 = bt.tab->get(Val::number(1));
        CHECK(!em.empty() && em[0].type == Type::Number && em[0].num == b1.tab->field("tris").num * 3 && g_mesh.bad == 0,
              "FrontendEmitBatch streams the batch's vertices (%g)", num_of(em, 0));
    }
    // the ring: the first sphe_7 quad is the selected slot's, at the bottom of the ring (S.SphereAt: the k-th quad is slot + k)
    {
        Val scr = Val::table();
        L.call("FrontendScreen", {scr, Val::boolean(true)});
        Val d2 = scr.tab->field("d"), v2 = scr.tab->field("v");
        double first_y = -1.0, first_x = -1.0;
        int quads = 0;
        for (int d = 0; d < (int)scr.tab->field("nd").num; d++) {
            int k = d * 11;
            std::vector<Val> ti = L.call("FrontendTexture", {d2.tab->get(Val::number(k + 5)), d2.tab->get(Val::number(k + 4))});
            if (!ti.empty() && ti[0].type == Type::Table && ti[0].tab->field("name").str == "sphe_7") {
                double first = d2.tab->get(Val::number(k + 2)).num, count = d2.tab->get(Val::number(k + 3)).num;
                quads += (int)(count / 6.0);
                if (first_y < 0) {
                    first_x = v2.tab->get(Val::number(first * 8 + 1)).num;
                    first_y = v2.tab->get(Val::number(first * 8 + 2)).num;
                }
            }
        }
        CHECK(quads >= 7 && first_y > 300 && first_x > 250 && first_x < 400, "the first of the %d sphe_7 quads stands at the ring's bottom (%.0f, %.0f)", quads, first_x, first_y);
    }
    // RIGHT, the slide, A: the pose and the voice
    Val st0 = L.call("FrontendState", {R.state}).at(0);
    CHECK(st0.type == Type::Table && st0.tab->field("slot").num == 0 && st0.tab->field("slots").num == 7 && st0.tab->field("kind").num == 0,
          "FrontendState: slot 0 of 7, kind 0");
    CHECK(R.run(1, F.tab->field("RIGHT").num) && R.run(30, 0), "RIGHT, then 30 frames");
    CHECK(R.select_slot == 1, "\"select\" 1 (%d)", R.select_slot);
    Val st1 = L.call("FrontendState", {R.state}).at(0);
    CHECK(st1.tab->field("slot").num == 1 && st1.tab->field("kind").num == 2 && st1.tab->field("phase").num == 0,
          "slot 1, kind 2 (Tails), idle (slot %g, kind %g, phase %g)", st1.tab->field("slot").num, st1.tab->field("kind").num,
          st1.tab->field("phase").num);
    std::vector<Val> rd2 = L.call("FrontendRender", {});
    CHECK(num_of(rd2, 2) == 2, "FrontendRender says Tails' textures (kind %g)", num_of(rd2, 2));
    Val stats0 = L.call("FrontendStats", {}).at(0);
    double voices0 = stats0.tab->field("voices").num;
    CHECK(R.run(1, F.tab->field("A").num) && R.run(5, 0), "A, then 5 frames");
    CHECK(R.pick_slot == 1, "\"pick\" 1 (%d)", R.pick_slot);
    Val stats1 = L.call("FrontendStats", {}).at(0);
    CHECK(stats1.tab->field("voices").num > voices0 && stats1.tab->field("last_voice").num == 1800,
          "the voice came: Tails' 1800, as the reference (voices %g -> %g, the last %g)", voices0, stats1.tab->field("voices").num,
          stats1.tab->field("last_voice").num);
    {
        Val as = L.call("AudioStatus", {}).at(0);
        double playing = -1.0;
        for (int k = 0; k < 400 && playing <= 0.0; k++) {
            std::vector<Val> u = L.call("AudioUpdate", {Val::vector(0, 0, 0), Val::vector(1, 0, 0), Val::vector(0, 0, 1), Val::number(1),
                                                        Val::boolean(false), Val::number(1.0 / 60.0)});
            playing = num_of(u, 0);
            if (playing <= 0.0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
        }
        CHECK(as.tab->field("open").b && as.tab->field("events").num > 0 && playing > 0.0,
              "and went to the mixer, a local sound of no character: %g sound events, %g playing", as.tab->field("events").num, playing);
    }
    Val st2 = L.call("FrontendState", {R.state}).at(0);
    CHECK(st2.tab->field("phase").num == 3 && st2.tab->field("pose_frames").num > 0, "phase 3: the pose (%g frames)", st2.tab->field("pose_frames").num);
    // (the pose's 300 frames and the 21 of the game's own leaving)
    CHECK(R.run(330, 0) && R.done == 1, "the game's 300 frames: \"done\" once (%d)", R.done);
    std::printf("  info  the tick at most %.2f ms over %u frames (under 2 ms on a quiet machine)\n", R.tick_ms_max, R.frames);
    // close, reopen: another first slot, the cancel
    CHECK(L.call("FrontendClose", {}).at(0).type == Type::Bool && is_refusal(L.call("FrontendState", {}), "not_ready"), "closed: \"not_ready\"");
    std::vector<Val> op2 = L.call("FrontendOpen", {open_args(2)});
    CHECK(!op2.empty() && op2[0].type == Type::Bool, "reopened on slot 2");
    Val st3 = L.call("FrontendState", {R.state}).at(0);
    CHECK(st3.type == Type::Table && st3.tab->field("slot").num == 2 && st3.tab->field("kind").num == 3, "it starts on Knuckles (slot %g, kind %g)", st3.tab->field("slot").num,
          st3.tab->field("kind").num);
    R.cancel = 0;
    CHECK(R.run(20, 0) && R.run(1, F.tab->field("B").num) && R.run(14, 0) && R.cancel == 1, "B: \"cancel\" within the game's 9 frames (%d)", R.cancel);
    // how early a pick is taken: the game's own screen drops A in its first 10 frames, the host's skip of the dialog (libsa1) may not
    L.call("FrontendClose", {});
    L.call("FrontendOpen", {open_args(0)});
    R.run(1, F.tab->field("A").num);
    R.run(3, 0);
    std::printf("  info  A on the first frame after an open: phase %g (the panel's own rule keeps a held button out)\n",
                L.call("FrontendState", {R.state}).at(0).tab->field("phase").num);
    // R98.20: gsa1.Shutdown closes an open front end first, every call then answers "not_ready"; the module's close too
    L.call("FrontendClose", {});
    std::vector<Val> op3 = L.call("FrontendOpen", {open_args(0)});
    CHECK(!op3.empty() && op3[0].type == Type::Bool, "open again, then gsa1.Shutdown");
    L.call("Shutdown", {});
    CHECK(is_refusal(L.call("FrontendTick", {Val::number(0.02), Val::number(0), Val::number(0), Val::number(0)}), "not_ready") &&
              is_refusal(L.call("FrontendState", {}), "not_ready") && is_refusal(L.call("FrontendScreen", {Val::table()}), "not_ready") &&
              L.call("FrontendClose", {}).at(0).type == Type::Bool,
          "gsa1.Shutdown: nothing dangles, every call answers \"not_ready\" (R98.20)");
    write_api("RAN\tthe screen, a pick, a cancel, gsa1.Shutdown");
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}

#endif
