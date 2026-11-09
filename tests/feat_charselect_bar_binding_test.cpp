// feat_charselect_bar_binding_test: Character Select's bar against the game's own screen, through the module (1.0.0-beta1a, lane b1a-bar; sadc
// docs/research/gsa1_100_select.md 4.4; src/module/bind_frontend.cpp, src/core/frontend.*). Linked like binding_test (the module's objects, libsa1,
// the mock Lua stack of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi.
//
//   feat_charselect_bar_binding_test [--gdi GAME.gdi] [--verbose]
//
// THE LESSON OF BETA 1: the bar's tests ran on a stand-in where every sphere was a draw of its own, and the owner's game showed Sonic's ball red.
// This test opens the game's own screen with the disc, runs it to idle and MEASURES what gsa1.FrontendScreen hands the addon:
//   * where the bar's two spheres are: each is the game's tinted base (a 50 x 50 quad centred on (128, 418) and (504, 418), LANDING.md C) and a
//     white shine; libsa1 sorts the screen's draws by priority and merges neighbours of one state (sa1_screen.c s_draw), so the two bases
//     come out as quads 8 and 9 of ONE draw of nine with the ring's seven (54 vertices; the shines as another). The draw filter of beta 1
//     looked for a draw of exactly one quad and never found the left ball (MEASURED: run of 2026-11-08, beta 1a lane b1a-bar);
//   * the bar's own draws (every draw with a vertex below y 340): their boxes, for the bar's extent; the two end quads of the bar (they reach x -68
//     and 700: S.PlaceX sent them to the screen's edges in beta 1) with their u at each x; the title bar, an untextured draw;
//   * and it writes build/<target>/charselect_screen.lua: the idle screen as the addon gets it (the draws, the vertices, each draw's texture
//     name: numbers and names only, made at test time from the disc, never kept), which tests/feat_charselect_bar_test.lua runs through the
//     addon's own paint (S.PaintR) and draw filter.
// Without the disc: one info line, and the Lua test says it ran on its stand-in only.
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
#include "../src/core/frontend.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"

#if !defined(GSA1_HAS_FRONTEND)

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    std::printf("G-SA1 feat_charselect_bar_binding_test\n");
    std::printf("  info  this libsa1 has no SA1_API_FRONTEND: nothing to measure\n");
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return 0;
}

#else

namespace {

bool g_verbose = false;

double num_at(const Val &t, int i)
{
    Val v = t.tab->get(Val::number(i));
    return v.type == Type::Number ? v.num : 0.0;
}

// a quad of the screen's vertices: six in a row of one draw
struct Quad {
    int draw = -1, vfirst = -1, dcount = 0;
    double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    int r = 0, g = 0, b = 0, a = 0;
};

// the quads of a draw (libsa1 writes each njDrawTexture quad as six vertices, two triangles)
std::vector<Quad> quads_of(const Val &d, const Val &v, int draw)
{
    std::vector<Quad> out;
    int k = draw * 11;
    int first = (int)num_at(d, k + 2), count = (int)num_at(d, k + 3);
    for (int q = 0; q + 6 <= count; q += 6) {
        Quad o;
        o.draw = draw;
        o.vfirst = first + q;
        o.dcount = count;
        o.x0 = o.y0 = 1e30;
        o.x1 = o.y1 = -1e30;
        for (int j = 0; j < 6; j++) {
            int vo = (first + q + j) * 8;
            double x = num_at(v, vo + 1), y = num_at(v, vo + 2);
            o.x0 = std::min(o.x0, x);
            o.y0 = std::min(o.y0, y);
            o.x1 = std::max(o.x1, x);
            o.y1 = std::max(o.y1, y);
        }
        int vo = (first + q) * 8;
        o.r = (int)num_at(v, vo + 5);
        o.g = (int)num_at(v, vo + 6);
        o.b = (int)num_at(v, vo + 7);
        o.a = (int)num_at(v, vo + 8);
        out.push_back(o);
    }
    return out;
}

bool is_bar_base(const Quad &q, double cx, double cy)
{
    double w = q.x1 - q.x0, h = q.y1 - q.y0;
    return std::fabs(w - 50.0) <= 1.5 && std::fabs(h - 50.0) <= 1.5 && std::fabs((q.x0 + q.x1) / 2 - cx) <= 3.0 &&
           std::fabs((q.y0 + q.y1) / 2 - cy) <= 3.0 && !(q.r >= 250 && q.g >= 250 && q.b >= 250);
}

std::string lua_num(double x)
{
    if (!std::isfinite(x)) return "0";
    if (x == std::floor(x) && std::fabs(x) < 1e15) return gsa1::format("%.0f", x);
    return gsa1::format("%.9g", x);
}

std::string lua_str(const std::string &s)
{
    std::string o = "\"";
    for (char c : s) {
        if (c == '"' || c == '\\') {
            o += '\\';
            o += c;
        } else if ((unsigned char)c < 32 || (unsigned char)c >= 127) {
            o += gsa1::format("\\%03u", (unsigned)(unsigned char)c);
        } else {
            o += c;
        }
    }
    return o + "\"";
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
    std::printf("G-SA1 feat_charselect_bar_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_charselect_bar_appdata");
    std::string dump = gsa1::join_path(self.empty() ? "." : self, "charselect_screen.lua");
#ifdef _WIN32
    char full[4096];
    GetFullPathNameA(fake_appdata.c_str(), sizeof full, full, nullptr);
    fake_appdata = full;
    SetEnvironmentVariableW(L"APPDATA", gsa1::widen(fake_appdata).c_str());
#else
    setenv("XDG_CONFIG_HOME", fake_appdata.c_str(), 1);
#endif
    std::remove(dump.c_str());      // (a dump of an older build never stands in for this one)
    gmod13_open(&state);
    Val g = L.globals.tab->field("gsa1");
    CHECK(g.type == Type::Table && g.tab->field("FrontendScreen").type == Type::Function && g.tab->field("FrontendTexture").type == Type::Function,
          "gsa1.FrontendScreen and gsa1.FrontendTexture are there");
    if (gdi.empty() || g.type != Type::Table) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: nothing measured, no charselect_screen.lua (the Lua test runs on its stand-in only)\n");
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
    Val open = Val::table();
    open.tab->set(Val::string("slot"), Val::number(0));
    open.tab->set(Val::string("language"), Val::number(1));
    open.tab->set(Val::string("dialog"), Val::boolean(false));
    std::vector<Val> op = ist == "ready" ? L.call("FrontendOpen", {open}) : std::vector<Val>();
    CHECK(!op.empty() && op[0].type == Type::Bool && op[0].b, "the game's Character Select opens on Sonic (%s)", str_of(op, 1).c_str());
    if (op.empty() || op[0].type != Type::Bool) {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    // idle: the character stands in the circle by frame 199 of the screen (131 ran at the open)
    int frames = 0;
    for (int i = 0; i < 120; i++) {
        std::vector<Val> r = L.call("FrontendTick", {Val::number(1.0 / 60.0 + 1e-6), Val::number(0), Val::number(0), Val::number(0)});
        if (r.empty() || r[0].type != Type::Number) break;
        frames += (int)r[0].num;
    }
    Val state_t = Val::table();
    L.call("FrontendState", {state_t});
    double phase = state_t.tab->field("phase").num, frame = state_t.tab->field("frame").num;
    CHECK(frames >= 100 && phase == 0, "120 ticks: %d frames, idle (phase %g, the screen's frame %g)", frames, phase, frame);
    Val scr = Val::table();
    std::vector<Val> sc = L.call("FrontendScreen", {scr, Val::boolean(true)});
    int nd = (int)scr.tab->field("nd").num, nv = (int)scr.tab->field("nv").num;
    Val d = scr.tab->field("d"), v = scr.tab->field("v");
    CHECK(!sc.empty() && sc[0].type == Type::Number && nd > 0 && nv > 0 && d.type == Type::Table && v.type == Type::Table,
          "gsa1.FrontendScreen: %d draws, %d vertices", nd, nv);
    if (nd <= 0 || d.type != Type::Table || v.type != Type::Table) {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return 1;
    }
    // each draw's texture name, through the module (gsa1.FrontendTexture: what cl_charselect.lua's name_of asks GSA1.Tex.Info for)
    std::vector<std::string> names((size_t)nd);
    for (int i = 0; i < nd; i++) {
        int k = i * 11;
        double archive = num_at(d, k + 4), texture = num_at(d, k + 5);
        if (archive >= 0 && texture >= 0) {
            std::vector<Val> ti = L.call("FrontendTexture", {Val::number(texture), Val::number(archive)});
            if (!ti.empty() && ti[0].type == Type::Table) names[(size_t)i] = ti[0].tab->field("name").str;
        }
    }
    // the bar's spheres
    std::vector<Quad> lbase, rbase, lshine, rshine;
    for (int i = 0; i < nd; i++) {
        for (const Quad &q : quads_of(d, v, i)) {
            if (is_bar_base(q, 128, 418)) lbase.push_back(q);
            if (is_bar_base(q, 504, 418)) rbase.push_back(q);
            bool white = q.r >= 250 && q.g >= 250 && q.b >= 250;
            if (white && std::fabs(q.x1 - q.x0 - 50) <= 1.5 && std::fabs((q.x0 + q.x1) / 2 - 128) <= 3 && std::fabs((q.y0 + q.y1) / 2 - 418) <= 3) lshine.push_back(q);
            if (white && std::fabs(q.x1 - q.x0 - 50) <= 1.5 && std::fabs((q.x0 + q.x1) / 2 - 504) <= 3 && std::fabs((q.y0 + q.y1) / 2 - 418) <= 3) rshine.push_back(q);
        }
    }
    CHECK(lbase.size() == 1 && rbase.size() == 1 && lshine.size() == 1 && rshine.size() == 1,
          "the bar's two spheres: one tinted base and one white shine each (left %zu + %zu, right %zu + %zu)", lbase.size(), lshine.size(), rbase.size(),
          rshine.size());
    if (lbase.size() == 1 && rbase.size() == 1) {
        const Quad &l = lbase[0], &r = rbase[0];
        std::printf("  info  MEASURED the left ball's base: draw %d (\"%s\"), vertices %d..%d of the draw's %d (%d quads), box %.1f..%.1f x %.1f..%.1f, colour %d %d %d %d\n",
                    l.draw, names[(size_t)l.draw].c_str(), l.vfirst, l.vfirst + 5, l.dcount, l.dcount / 6, l.x0, l.x1, l.y0, l.y1, l.r, l.g, l.b, l.a);
        std::printf("  info  MEASURED the right ball's base: draw %d, vertices %d..%d of the draw's %d\n", r.draw, r.vfirst, r.vfirst + 5, r.dcount);
        CHECK(l.r == 255 && l.g == 0 && l.b == 0, "the game draws the left ball red (FFFF0000: %d %d %d)", l.r, l.g, l.b);
        // THE ROOT CAUSE OF THE RED BALL: the base shares its draw with the right ball's (both texture 2 of the item spheres at one depth)
        std::printf("  info  %s\n", l.draw == r.draw && l.dcount > 6
                                        ? "MEASURED: both balls' bases are ONE merged draw: beta 1's filter wanted a draw of exactly 6 vertices, so it never tinted the left ball"
                                        : "the left ball's base is a draw of its own here");
        CHECK(l.dcount >= 6 && (l.dcount % 6) == 0, "its draw is whole quads (%d vertices)", l.dcount);
    }
    // the bar's draws (a vertex below y 340): for its extent on wide screens (where x <= 0 and x >= 640 go)
    for (int i = 0; i < nd; i++) {
        int k = i * 11;
        int first = (int)num_at(d, k + 2), count = (int)num_at(d, k + 3);
        double x0 = 1e30, y0 = 1e30, x1 = -1e30, y1 = -1e30;
        for (int j = first; j < first + count; j++) {
            x0 = std::min(x0, num_at(v, j * 8 + 1));
            x1 = std::max(x1, num_at(v, j * 8 + 1));
            y0 = std::min(y0, num_at(v, j * 8 + 2));
            y1 = std::max(y1, num_at(v, j * 8 + 2));
        }
        if (y1 > 340 && (g_verbose || x0 <= 0.0 || x1 >= 640.0)) {
            std::printf("  info  bar draw %d \"%s\": %d vertices, x %.1f..%.1f, y %.1f..%.1f, priority %g\n", i, names[(size_t)i].c_str(), count, x0, x1,
                        y0, y1, num_at(d, k + 9));
        }
    }
    // the bar's two end quads (beta 1a): they reach outside the picture, so feat/cl_charselect_bar.lua S.KeepEnds cuts them at x 0 and 640
    // (beta 1's S.PlaceX sent x -68 and 700 to the screen's edges: the bar ran into the side bars, the owner's 16.jpg); x and u of each side
    {
        int ends = 0;
        for (int i = 0; i < nd; i++) {
            int k = i * 11;
            int first = (int)num_at(d, k + 2), count = (int)num_at(d, k + 3);
            for (int q = 0; q + 6 <= count; q += 6) {
                double x0 = 1e30, x1 = -1e30, y0 = 1e30, y1 = -1e30, u0 = 0, u1 = 0;
                for (int j = first + q; j < first + q + 6; j++) {
                    double x = num_at(v, j * 8 + 1), y = num_at(v, j * 8 + 2);
                    if (x < x0) { x0 = x; u0 = num_at(v, j * 8 + 3); }
                    if (x > x1) { x1 = x; u1 = num_at(v, j * 8 + 3); }
                    y0 = std::min(y0, y);
                    y1 = std::max(y1, y);
                }
                if (y0 >= 380 && y1 <= 460 && (x0 < 0 || x1 > 640)) {
                    ends++;
                    std::printf("  info  MEASURED a bar end quad: draw %d \"%s\", x %.1f (u %.3f) .. %.1f (u %.3f), y %.1f..%.1f\n", i, names[(size_t)i].c_str(), x0, u0, x1, u1,
                                y0, y1);
                }
            }
            if ((num_at(d, k + 4) < 0 || num_at(d, k + 5) < 0) && count >= 3) {
                // (the title bar: cl_hud.lua H.Material gives it a white material, drawn with the game's blend: its flags and blend factors here)
                std::printf("  info  MEASURED an untextured draw: draw %d, flags 0x%X, blend %d / %d, x %.1f..%.1f y %.1f..%.1f, colour %d %d %d, alpha %d at its first vertex, %d at its third\n",
                            i, (unsigned)num_at(d, k + 6), (int)num_at(d, k + 7), (int)num_at(d, k + 8), num_at(v, first * 8 + 1), num_at(v, (first + 2) * 8 + 1),
                            num_at(v, first * 8 + 2), num_at(v, (first + 1) * 8 + 2), (int)num_at(v, first * 8 + 5), (int)num_at(v, first * 8 + 6),
                            (int)num_at(v, first * 8 + 7), (int)num_at(v, first * 8 + 8), (int)num_at(v, (first + 2) * 8 + 8));
            }
        }
        CHECK(ends == 2, "the bar's two end quads reach outside the game's 0 .. 640 (%d): the premise of the bar's cut (S.KeepEnds)", ends);
    }
    // the dump for the Lua test: the screen exactly as gsa1.FrontendScreen fills the addon's table (d and v from 1, 11 and 8 a record)
    {
        std::string text = "-- G-SA1 charselect_screen.lua: the game's Character Select at idle on Sonic, as gsa1.FrontendScreen hands it to the addon.\n"
                           "-- Written by tests/feat_charselect_bar_binding_test.cpp at test time from the disc (numbers and texture names only; never kept);\n"
                           "-- read by tests/feat_charselect_bar_test.lua (the real screen). " + std::string(sa1_version_string()) + "\n";
        text += gsa1::format("return {\n    gen = %s, w = 640, h = 480, nd = %d, ns = 0, nv = %d, frame = %s,\n", lua_num(scr.tab->field("gen").num).c_str(), nd, nv,
                             lua_num(frame).c_str());
        text += "    d = {\n";
        for (int i = 0; i < nd * 11; i++) {
            text += (i % 11 == 0 ? "        " : " ") + lua_num(num_at(d, i + 1)) + ",";
            if (i % 11 == 10) text += "\n";
        }
        text += "    },\n    v = {\n";
        for (int i = 0; i < nv * 8; i++) {
            text += (i % 8 == 0 ? "        " : " ") + lua_num(num_at(v, i + 1)) + ",";
            if (i % 8 == 7) text += "\n";
        }
        text += "    },\n    names = {\n";
        for (int i = 0; i < nd; i++) {
            text += gsa1::format("        [%d] = %s,\n", i, lua_str(names[(size_t)i]).c_str());
        }
        text += "    },\n}\n";
        std::string werr;
        bool ok = gsa1::write_file_replace(dump, text, werr);
        CHECK(ok, "the idle screen written for the Lua test: %s (%zu bytes) %s", dump.c_str(), text.size(), werr.c_str());
    }
    L.call("FrontendClose", {});
    L.call("Shutdown", {});
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}

#endif
