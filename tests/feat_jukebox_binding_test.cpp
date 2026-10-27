// feat_jukebox_binding_test: the jukebox feature's Lua functions (src/module/bind_jukebox.cpp; plan
// gsa1_rounds_plan.md 10.2, J1), linked like binding_test (the module's objects, the core and libsa1) with the mock Lua
// stack of tests/mock_lua.hpp. The output is FakeBass (src/core/bass.hpp, installed with bass_set_test_api before
// gmod13_open; the engine's worker binds it as it binds GMod's BASS). The config file is written to a scratch APPDATA
// next to this program (yours is not touched).
//
//   feat_jukebox_binding_test [--gdi GAME.gdi]
//
// Checks: gsa1.FEATURES.jukebox = 1 with its 12 functions and gsa1.JUKEBOX_CHANNELS, no FEATURE_ERRORS of its own;
// every function follows the binding rules (no Lua error, false / nil + message + "bad_argument" for bad arguments, the
// caller's stack untouched); before a config: MusicList says why, JukeboxStatus / JukeboxState have their shapes;
// AudioDuck's arguments. With the disc: MusicList is nil, "loading" and then the list (109 entries of the documented
// shape, the sound-test titles, 87 truncated, no 69); JukeboxPlay / State / Seek / Pause / Volume / Place / Update /
// Sync / Stop; 69 refused with "not_found"; JukeboxStatus while playing; no BASS call from the Lua thread; no message
// holds the disc's or the config's directory; gmod13_close stops the engine and frees every BASS stream.
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "mock_lua.hpp"
#include "../src/core/bass.hpp"
#include "../src/core/config.hpp"
#include "../src/core/util.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

static const char *kFns[] = {"MusicList", "JukeboxPlay", "JukeboxStop", "JukeboxPause", "JukeboxSeek", "JukeboxSync",
                             "JukeboxVolume", "JukeboxPlace", "JukeboxUpdate", "JukeboxState", "JukeboxStatus",
                             "AudioDuck"};

static bool is_bad_arg(const std::vector<Val> &r)
{
    return is_nil_msg(r) && r.size() == 3 && str_of(r, 2) == "bad_argument";
}

static bool is_true(const std::vector<Val> &r)
{
    return !r.empty() && r[0].type == Type::Bool && r[0].b;
}

static std::string g_appdata, g_disc_dir;

// a message must not name the scratch APPDATA (the config's directory) or the disc's directory
static bool clean(const std::string &m)
{
    return (g_appdata.size() < 3 || m.find(g_appdata) == std::string::npos) &&
           (g_disc_dir.size() < 3 || m.find(g_disc_dir) == std::string::npos);
}

static Table *state_of(MockLua &L, int ch)
{
    static Val keep;
    auto r = L.call("JukeboxState", {Val::number(ch)});
    if (r.size() != 1 || r[0].type != Type::Table) return nullptr;
    keep = r[0];
    return keep.tab.get();
}

static bool wait_state(MockLua &L, int ch, const char *want, double timeout_ms, std::string &got)
{
    double t0 = gsa1::now_ms();
    for (;;) {
        Table *s = state_of(L, ch);
        got = s ? s->field("state").str : "?";
        if (got == want) return true;
        if (gsa1::now_ms() - t0 > timeout_ms) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
}

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::printf("G-SA1 feat_jukebox_binding_test\n");
    std::thread::id lua_thread = std::this_thread::get_id();
    gsa1::FakeBass &fb = gsa1::FakeBass::get();
    fb.reset();
    gsa1::bass_set_test_api(fb.api());

    // a private configuration directory for this run
    std::string self = gsa1::parent_dir(argv[0]);
    g_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_jukebox_binding_test_appdata");
#ifdef _WIN32
    {
        char full[4096];
        GetFullPathNameA(g_appdata.c_str(), sizeof full, full, nullptr);
        g_appdata = full;
        SetEnvironmentVariableW(L"APPDATA", gsa1::widen(g_appdata).c_str());
    }
#else
    setenv("XDG_CONFIG_HOME", g_appdata.c_str(), 1);
#endif
    gsa1::make_dirs(g_appdata);
    std::remove(gsa1::join_path(gsa1::config_dir(), "config.txt").c_str());

    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    gmod13_open(&state);
    Val g = L.globals.tab->field("gsa1");
    CHECK(g.type == Type::Table && L.st.empty(), "gmod13_open registers the gsa1 table and leaves the stack empty");
    if (g.type != Type::Table) return 1;
    Val feats = g.tab->field("FEATURES"), errs = g.tab->field("FEATURE_ERRORS");
    int have = 0;
    for (const char *f : kFns) have += g.tab->field(f).type == Type::Function;
    std::string errtext;
    if (errs.type == Type::Table) {
        for (auto &kv : errs.tab->n) errtext += kv.second.str + "; ";
    }
    CHECK(feats.type == Type::Table && feats.tab->field("jukebox").num == 1 && have == 12 &&
              g.tab->field("JUKEBOX_CHANNELS").num == 5 && errtext.find("jukebox") == std::string::npos,
          "gsa1.FEATURES.jukebox = %g, %d of its 12 functions, JUKEBOX_CHANNELS %g, FEATURE_ERRORS: %s",
          feats.type == Type::Table ? feats.tab->field("jukebox").num : -1.0, have, g.tab->field("JUKEBOX_CHANNELS").num,
          errtext.empty() ? "none" : errtext.c_str());

    // before a config: the engine cannot start; the shapes
    auto r = L.call("MusicList", {});
    CHECK(is_nil_msg(r) && r.size() == 3 && str_of(r, 2) == "no_config" && clean(str_of(r, 1)) && L.st.empty(),
          "MusicList() without a config: nil, \"%s\", %s", str_of(r, 1).c_str(), str_of(r, 2).c_str());
    r = L.call("JukeboxStatus", {});
    Table *S = r.size() == 1 && r[0].type == Type::Table ? r[0].tab.get() : nullptr;
    CHECK(S && S->field("ready").type == Type::Bool && !S->field("ready").b && S->field("tracks").type == Type::Number &&
              S->field("active").type == Type::Number && S->field("memory_mb").type == Type::Number &&
              S->field("max_open_ms").type == Type::Number && S->field("underruns").type == Type::Number &&
              S->field("error").type == Type::String && clean(S->field("error").str),
          "JukeboxStatus() before the engine: {ready false, tracks, active, memory_mb, max_open_ms, underruns, error "
          "\"%s\"}", S ? S->field("error").str.c_str() : "?");
    Table *T = state_of(L, 0);
    CHECK(T && T->field("music").num == -1 && T->field("state").str == "idle" && T->field("position").type == Type::Number &&
              T->field("length").type == Type::Number && T->field("loops_done").type == Type::Number &&
              T->field("error").type == Type::String,
          "JukeboxState(0) before the engine: {music -1, state \"idle\", position, length, loops_done, error}");
    // argument checks (the engine is not needed for them)
    struct Bad {
        const char *fn;
        std::vector<Val> args;
    };
    std::vector<Bad> bads = {
        {"JukeboxPlay", {}},
        {"JukeboxPlay", {Val::number(5), Val::number(28)}},
        {"JukeboxPlay", {Val::number(-1), Val::number(28)}},
        {"JukeboxPlay", {Val::number(0.5), Val::number(28)}},
        {"JukeboxPlay", {Val::number(0), Val::string("28")}},
        {"JukeboxPlay", {Val::number(0), Val::number(28), Val::number(-1)}},
        {"JukeboxPlay", {Val::number(0), Val::number(28), Val::number(NAN)}},
        {"JukeboxPlay", {Val::number(0), Val::number(28), Val::number(0), Val::string("sometimes")}},
        {"JukeboxPlay", {Val::number(0), Val::number(28), Val::number(0), Val::number(1)}},
        {"JukeboxPlay", {Val::number(0), Val::number(28), Val::number(0), Val::string("loops"), Val::number(0)}},
        {"JukeboxPlay", {Val::number(0), Val::number(28), Val::number(0), Val::string("loops"), Val::number(2.5)}},
        {"JukeboxPlay", {Val::number(0), Val::number(28), Val::number(0), Val::string("loops"), Val::number(2), Val::number(61)}},
        {"JukeboxPlay", {Val::number(0), Val::number(28), Val::number(0), Val::string("loops"), Val::number(2), Val::number(0), Val::number(-1)}},
        {"JukeboxStop", {Val::string("0")}},
        {"JukeboxStop", {Val::number(0), Val::number(-2)}},
        {"JukeboxPause", {Val::number(0)}},
        {"JukeboxPause", {Val::number(9), Val::boolean(true)}},
        {"JukeboxSeek", {Val::number(0), Val::number(-3)}},
        {"JukeboxSeek", {Val::number(0)}},
        {"JukeboxSync", {Val::number(0), Val::string("x")}},
        {"JukeboxVolume", {Val::number(0), Val::number(1.5)}},
        {"JukeboxVolume", {Val::number(0), Val::number(INFINITY)}},
        {"JukeboxPlace", {Val::number(1), Val::vector(0, 0, 0), Val::number(-5)}},
        {"JukeboxPlace", {Val::number(1), Val::number(3), Val::number(600)}},
        {"JukeboxPlace", {Val::number(7), Val()}},
        {"AudioDuck", {Val::number(2)}},
        {"AudioDuck", {Val::number(-0.1)}},
        {"AudioDuck", {Val::number(0), Val::number(1)}},
    };
    int nbad = 0;
    std::string which;
    for (const Bad &b : bads) {
        r = L.call(b.fn, b.args);
        bool okb = is_bad_arg(r) && L.st.empty() && r[1].str.find(b.fn) != std::string::npos;
        nbad += okb;
        if (!okb) which += std::string(b.fn) + " ";
    }
    r = L.call("JukeboxState", {Val::number(5)});
    bool st_bad = is_nil_msg(r) && str_of(r, 2) == "bad_argument";
    CHECK(nbad == (int)bads.size() && st_bad,
          "%d of %d bad calls answer false / nil, a usage message naming the function, \"bad_argument\"%s%s", nbad,
          (int)bads.size(), which.empty() ? "" : "; wrong: ", which.c_str());
    r = L.call("AudioDuck", {Val::number(0.5), Val::boolean(true)});
    auto r2 = L.call("AudioDuck", {Val::number(1)});
    auto r3 = L.call("JukeboxVolume", {Val::number(0), Val::number(0.5)});
    auto r4 = L.call("JukeboxPlace", {Val::number(1), Val::vector(0, -100, 0), Val::number(600)});
    auto r5 = L.call("JukeboxPlace", {Val::number(1), Val()});
    auto r6 = L.call("JukeboxStop", {Val::number(0)});
    auto r7 = L.call("JukeboxPause", {Val::number(0), Val::boolean(true)});
    auto r8 = L.call("JukeboxUpdate", {Val::vector(0, 0, 0), Val::vector(1, 0, 0), Val::vector(0, 0, 1), Val::number(1),
                                       Val::number(1), Val::boolean(false)});
    CHECK(is_true(r) && is_true(r2) && is_true(r3) && is_true(r4) && is_true(r5) && is_true(r6) && is_nil_msg(r7) &&
              str_of(r7, 2) == "not_started" && r8.size() == 1 && r8[0].type == Type::Number && r8[0].num == 0,
          "before the engine: AudioDuck(0.5, true) / (1), JukeboxVolume, JukeboxPlace (3D and back to 2D), JukeboxStop: "
          "true; JukeboxPause: false, \"%s\", %s; JukeboxUpdate: %g audible", str_of(r7, 1).c_str(), str_of(r7, 2).c_str(),
          r8.empty() ? -1.0 : r8[0].num);

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the rest needs the disc\n");
    } else {
        g_disc_dir = gsa1::parent_dir(gdi);
        gsa1::Config cfg;
        cfg.disc = gdi;
        std::string err;
        CHECK(gsa1::save_config(cfg, err), "config written to the scratch APPDATA (%s)", err.c_str());
        double t0 = gsa1::now_ms();
        r = L.call("MusicList", {});
        double first_ms = gsa1::now_ms() - t0;
        bool loading = r.size() == 2 && r[0].type == Type::Nil && str_of(r, 1) == "loading";
        double tl = gsa1::now_ms();
        while (r.size() != 1 && gsa1::now_ms() - tl < 30000) {
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
            r = L.call("MusicList", {});
        }
        Table *M = r.size() == 1 && r[0].type == Type::Table ? r[0].tab.get() : nullptr;
        size_t n = M ? M->n.size() : 0;
        std::set<int> numbers;
        int shaped = 0, listed = 0, titled = 0;
        Table *e28 = nullptr, *e87 = nullptr, *e66 = nullptr;
        if (M) {
            for (auto &kv : M->n) {
                Table *e = kv.second.type == Type::Table ? kv.second.tab.get() : nullptr;
                if (!e) continue;
                int m = (int)e->field("music").num;
                numbers.insert(m);
                bool ok = e->field("music").type == Type::Number && e->field("file").type == Type::String &&
                          (e->field("title").type == Type::String || e->field("title").type == Type::Nil) &&
                          e->field("page").type == Type::Number && e->field("entry").type == Type::Number &&
                          e->field("seconds").num > 0 && e->field("loop").type == Type::Bool &&
                          e->field("loop_start").type == Type::Number && e->field("loop_end").num > 0 &&
                          (e->field("rate").num == 32000 || e->field("rate").num == 44100) &&
                          e->field("listed").type == Type::Bool && e->field("jingle").type == Type::Bool &&
                          e->field("short").type == Type::Bool && e->field("truncated").type == Type::Bool &&
                          (e->field("listed").b ? (e->field("page").num >= 0 && e->field("page").num <= 5 &&
                                                   e->field("entry").num >= 0 && e->field("title").type == Type::String)
                                                : (e->field("page").num == -1 && e->field("entry").num == -1 &&
                                                   e->field("title").type == Type::Nil));
                shaped += ok;
                listed += e->field("listed").b;
                titled += e->field("title").type == Type::String;
                if (m == 28) e28 = e;
                if (m == 87) e87 = e;
                if (m == 66) e66 = e;
            }
        }
        CHECK(loading && first_ms < 50.0 && n == 109 && shaped == 109 && listed == 104 && titled == 104 && !numbers.count(69),
              "MusicList(): nil, \"loading\" at once (%.2f ms), then %zu entries {music, file, title, page, entry, seconds, "
              "loop, loop_start, loop_end, rate, listed, jingle, short, truncated} (%d well-formed), %d in the sound test "
              "with titles, no 69", first_ms, n, shaped, listed);
        CHECK(e28 && e28->field("title").str == "Emerald Coast:  Type 1" && e28->field("page").num == 1 &&
                  e28->field("entry").num == 0 && e28->field("loop").b && std::fabs(e28->field("loop_start").num - 42.81) < 0.01 &&
                  std::fabs(e28->field("loop_end").num - e28->field("seconds").num) < 0.001 && e28->field("rate").num == 44100 &&
                  e66 && e66->field("title").str == "Open Your Heart" && !e66->field("loop").b &&
                  e87 && e87->field("truncated").b && !e87->field("listed").b && e87->field("file").str == "SSRACING.ADX" &&
                  std::fabs(e87->field("seconds").num - 176.0) < 0.1,
              "entries: 28 \"%s\" page %g entry %g, loop %.2f-%.2f s of %.2f; 66 \"%s\" without a loop; 87 %s truncated, "
              "%.1f s present, not listed (no title)", e28 ? e28->field("title").str.c_str() : "?",
              e28 ? e28->field("page").num : -9, e28 ? e28->field("entry").num : -9, e28 ? e28->field("loop_start").num : 0,
              e28 ? e28->field("loop_end").num : 0, e28 ? e28->field("seconds").num : 0,
              e66 ? e66->field("title").str.c_str() : "?", e87 ? e87->field("file").str.c_str() : "?",
              e87 ? e87->field("seconds").num : 0);

        // play, state, seek, pause, update, status, 69
        r = L.call("JukeboxPlay", {Val::number(0), Val::number(28), Val::number(0), Val::string("forever"), Val::number(2),
                                   Val::number(0), Val::number(0)});
        std::string got;
        bool playing = wait_state(L, 0, "playing", 10000, got);
        Table *P = state_of(L, 0);
        CHECK(is_true(r) && str_of(r, 1) == "loading" && playing && P && P->field("music").num == 28 &&
                  P->field("position").num >= 0 && std::fabs(P->field("length").num - 112.11) < 0.01 &&
                  P->field("loops_done").num == 0 && P->field("error").str.empty() && P->field("plan").str == "forever" &&
                  std::fabs(P->field("volume").num - 0.5) < 1e-9 && P->field("queued").num > 2.5,
              "JukeboxPlay(0, 28, 0, \"forever\", 2, 0, 0): true, \"%s\"; JukeboxState(0): {music %g, state \"%s\", position "
              "%.3f, length %.2f, loops_done %g, error \"\", plan %s, volume %g (set before), %.2f s queued}",
              str_of(r, 1).c_str(), P ? P->field("music").num : -1, got.c_str(), P ? P->field("position").num : -1,
              P ? P->field("length").num : -1, P ? P->field("loops_done").num : -1, P ? P->field("plan").str.c_str() : "?",
              P ? P->field("volume").num : -1, P ? P->field("queued").num : -1);
        Val out = Val::table();
        auto ro = L.call("JukeboxState", {Val::number(0), out});
        CHECK(ro.size() == 1 && ro[0].tab == out.tab && out.tab->field("state").str == "playing",
              "JukeboxState(0, out) fills the caller's table");
        r = L.call("JukeboxUpdate", {Val::vector(0, 0, 0), Val::vector(1, 0, 0), Val::vector(0, 0, 1), Val::number(1),
                                     Val::number(1), Val::boolean(false)});
        auto rq = L.call("JukeboxUpdate", {Val::vector(0, 0, 0), Val::vector(1, 0, 0), Val::vector(0, 0, 1),
                                           Val::number(0.05), Val::number(1), Val::boolean(false)});
        CHECK(r.size() == 1 && r[0].num == 1 && rq.size() == 1 && rq[0].num == 0,
              "JukeboxUpdate(eye, forward, up, 1, 1, false) = %g audible; with GMod's volume at 0.05: %g", r[0].num,
              rq.empty() ? -1.0 : rq[0].num);
        L.call("JukeboxUpdate", {Val::vector(0, 0, 0), Val::vector(1, 0, 0), Val::vector(0, 0, 1), Val::number(1),
                                 Val::number(1), Val::boolean(false)});
        r = L.call("JukeboxSeek", {Val::number(0), Val::number(30)});
        bool sought = false;
        double ts = gsa1::now_ms();
        while (!sought && gsa1::now_ms() - ts < 5000) {
            Table *s = state_of(L, 0);
            sought = s && s->field("position").num >= 30.0 && s->field("position").num < 31.0;
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
        auto rp = L.call("JukeboxPause", {Val::number(0), Val::boolean(true)});
        bool paused = wait_state(L, 0, "paused", 3000, got);
        auto rr = L.call("JukeboxPause", {Val::number(0), Val::boolean(false)});
        bool resumed = wait_state(L, 0, "playing", 3000, got);
        auto ry = L.call("JukeboxSync", {Val::number(0), Val::number(31)});
        CHECK(is_true(r) && sought && is_true(rp) && paused && is_true(rr) && resumed && is_true(ry),
              "JukeboxSeek(0, 30) -> position 30.x; JukeboxPause(0, true) -> \"paused\", (0, false) -> \"playing\"; "
              "JukeboxSync(0, 31): true");
        r = L.call("JukeboxPlay", {Val::number(1), Val::number(69)});
        CHECK(is_nil_msg(r) && str_of(r, 2) == "not_found" && clean(str_of(r, 1)),
              "JukeboxPlay(1, 69): false, \"%s\", %s", str_of(r, 1).c_str(), str_of(r, 2).c_str());
        std::this_thread::sleep_for(std::chrono::milliseconds(60));
        Table *F = state_of(L, 1);
        CHECK(F && F->field("state").str == "failed" && F->field("error").str.find("not on your disc") != std::string::npos &&
                  clean(F->field("error").str),
              "JukeboxState(1) after it: \"%s\", \"%s\"", F ? F->field("state").str.c_str() : "?",
              F ? F->field("error").str.c_str() : "?");
        r = L.call("JukeboxStatus", {});
        S = r.size() == 1 && r[0].type == Type::Table ? r[0].tab.get() : nullptr;
        CHECK(S && S->field("ready").b && S->field("tracks").num == 109 && S->field("active").num == 1 &&
                  S->field("memory_mb").num > 1.0 && S->field("max_open_ms").num > 0 && S->field("underruns").num == 0 &&
                  S->field("error").str.empty() && S->field("backend").str == "fake BASS (tests)" &&
                  S->field("titles").b && S->field("listed").num == 104,
              "JukeboxStatus() while playing: {ready, tracks %g, active %g, memory_mb %.1f, max_open_ms %.1f, underruns %g, "
              "error \"\", backend \"%s\"}", S ? S->field("tracks").num : -1, S ? S->field("active").num : -1,
              S ? S->field("memory_mb").num : -1, S ? S->field("max_open_ms").num : -1, S ? S->field("underruns").num : -1,
              S ? S->field("backend").str.c_str() : "?");
        r = L.call("JukeboxStop", {Val::number(0), Val::number(0.5)});
        bool idle = wait_state(L, 0, "idle", 3000, got);
        CHECK(is_true(r) && idle, "JukeboxStop(0, 0.5): true, the channel idle");
        // a second play left running for gmod13_close
        L.call("JukeboxPlay", {Val::number(0), Val::number(108)});
        wait_state(L, 0, "playing", 10000, got);
    }
    gmod13_close(&state);
    CHECK(L.globals.tab->field("gsa1").type == Type::Nil && fb.live() == 0 && fb.calls_from(lua_thread) == 0,
          "gmod13_close: the engine stopped first (%u BASS streams left), the gsa1 table is gone; %llu BASS calls, none "
          "from the Lua thread", fb.live(), (unsigned long long)fb.calls());
    gsa1::bass_set_test_api(nullptr);
    std::remove(gsa1::join_path(gsa1::config_dir(), "config.txt").c_str());
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
