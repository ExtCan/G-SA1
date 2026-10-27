// G-SA1 binding test: the module's Lua functions (src/module/gsa1_module.cpp, linked in) driven through a mock
// ILuaBase - a small Lua-like value stack with tables, strings, numbers and Vectors - without Garry's Mod.
//
//   binding_test [--bsp MAP.bsp] [--gdi GAME.gdi]
//
// Checks: gmod13_open registers the gsa1 table (functions, constants), every call leaves the caller's stack as it
// was and returns what it declares, no function ever raises a Lua error (ThrowError / ArgError / Check* abort the
// test), bad arguments come back as nil/false + message, the config file is read from %APPDATA%\gsa1\config.txt
// (the test points APPDATA at a scratch directory; your real one is not touched), WorldLoad refuses paths and
// reports not_found outside garrysmod/lua/bin, WorldLoadData parses the map, a character ticks, its state is filled,
// Render interpolates (alpha 0 / 0.5 / 1), Batches describes the render batches, EmitBatch streams every vertex
// through a mock of GMod's mesh library (protected calls only, two scratch Vectors), the texture runs paint the
// decoded texels exactly, the sound banks open and the sound events reach the mixer, the controller functions
// (PadSettings / PadPoll / PadRumble / PadStatus) map a fake XInput controller and the game's rumble events (Knuckles'
// punch) drive its motors, gmod13_close removes the table (and stops the motors). 0.5: the map's collision in the
// background (MapStartData / MapPoll / MapFeed / MapFeedFile / MapApply, the addon's way of reading a workshop map),
// moving objects (ShapeBox / ShapePhy / ShapeKnown / MoverUpdate with an Angle / MoverCommit / MoverStatus).
// 0.5.1 (API 6): the disc (Init + InitPoll), the sound banks (AudioOpen + AudioPoll) and libsa1's GRID synthesis
// (MapPoll state "preparing", MapApply info.prepared) on worker threads; "the game's thread": the addon's frames of a
// first spawn, a respawn, character switches, a map reload and an upgrade re-creation, every module call timed
// (p50 / p90 / max per function); no call may take more than 8 ms (--timing-bsp MAP.bsp: on another map too).
// G0 (the feature seam, gsa1_feature.hpp): two dummy features registered by this test reach gsa1.FEATURES, their
// functions the gsa1 table (a name clash with a built-in is refused and listed in gsa1.FEATURE_ERRORS), their open
// hook runs once, their shutdown hook at gsa1.Shutdown(), their close hooks at gmod13_close in close order with the
// session still there. The vector mode is decided at gmod13_open (the session log's header has it).
// The mock Lua stack is tests/mock_lua.hpp (shared with the features' binding tests).
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../src/core/config.hpp"
#include "../src/core/pad.hpp"
#include "../src/core/util.hpp"
#include "../src/core/libsa1_internal_api.hpp"

#ifdef _WIN32
#include <windows.h>
#endif

using namespace GarrysMod::Lua;

extern "C" int gmod13_open(lua_State *L);
extern "C" int gmod13_close(lua_State *L);

#include "mock_lua.hpp"
#include "../src/module/gsa1_feature.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

// ---- the feature seam (plan G0): two dummy features registered by this test ---------------------------------------
// seamtest_a: version 3, a function, a constant from its open hook, a shutdown hook, a close hook, and a function named
// like a built-in (Status: refused); seamtest_b: version 1, closes first. The hooks write what they saw into g_feat_log.
static std::vector<std::string> g_feat_log;
GSA1_FN(gsa1_seamtest_Echo)
{
    double d = 0;
    if (!gsa1::mod::arg_number(LUA, 1, d)) {
        return gsa1::mod::push_nil_msg(LUA, "SeamTestEcho(number)", "bad_argument");
    }
    LUA->PushNumber(d + 1);
    return 1;
}
GSA1_FN(gsa1_seamtest_NotStatus)
{
    LUA->PushString("a feature's Status");
    return 1;
}
GSA1_FN(gsa1_seamtest_Session)
{
    LUA->PushBool(gsa1::mod::session() != nullptr);
    return 1;
}
static const gsa1::FeatureFn k_seam_a_fns[] = {{"SeamTestEcho", gsa1_seamtest_Echo}, {"Status", gsa1_seamtest_NotStatus}};
static const gsa1::FeatureFn k_seam_b_fns[] = {{"SeamTestSession", gsa1_seamtest_Session}};
static void seam_a_open(ILuaBase *L, int t)
{
    gsa1::mod::raw_num(L, t, "SEAMTEST_CONST", 42);
    g_feat_log.push_back("open a");
}
static void seam_close(const char *who)
{
    g_feat_log.push_back(std::string("close ") + who + (gsa1::mod::session() ? " (session)" : " (no session)"));
}
static void seam_a_close(ILuaBase *) { seam_close("a"); }
static void seam_b_close(ILuaBase *) { seam_close("b"); }
static void seam_a_shutdown() { g_feat_log.push_back("shutdown a"); }
GSA1_FEATURE(seamtest_a, 3, k_seam_a_fns, seam_a_open, seam_a_close, gsa1::kCloseDefault);
GSA1_FEATURE_ON_SHUTDOWN(seamtest_a, seam_a_shutdown);
GSA1_FEATURE(seamtest_b, 1, k_seam_b_fns, nullptr, seam_b_close, gsa1::kCloseFirst);

// the real features the module links (src/module/bind_<feature>.cpp, e.g. the jukebox): how many, with how many functions
static size_t real_features(int *fns)
{
    size_t n = 0;
    int f = 0;
    for (gsa1::Feature *x = gsa1::feature_list(); x; x = x->next) {
        if (std::strncmp(x->name, "seamtest_", 9) == 0) {
            continue;
        }
        n++;
        for (size_t i = 0; i < x->nfns && x->fns[i].name; i++) {
            f++;
        }
    }
    if (fns) {
        *fns = f;
    }
    return n;
}

// after gmod13_open: gsa1.FEATURES, the functions, the refused clash, the open hook, the vector mode
static void test_features_open(MockLua &L, const Val &g)
{
    Val feats = g.tab->field("FEATURES"), errs = g.tab->field("FEATURE_ERRORS");
    bool listed = feats.type == Type::Table && feats.tab->field("seamtest_a").num == 3 &&
                  feats.tab->field("seamtest_b").num == 1 && feats.tab->s.size() == 2 + real_features(nullptr);
    std::string e1 = errs.type == Type::Table ? errs.tab->at(1).str : std::string();
    bool clash = errs.type == Type::Table && errs.tab->n.size() == 1 && e1.find("gsa1.Status exists already") != std::string::npos;
    auto echo = L.call("SeamTestEcho", {Val::number(41)});
    auto bad = L.call("SeamTestEcho", {Val::string("x")});
    auto sess = L.call("SeamTestSession", {});
    auto st = L.call("Status", {});
    CHECK(listed && clash && echo.size() == 1 && echo[0].num == 42 && is_nil_msg(bad) && sess.size() == 1 && sess[0].b &&
              st.size() == 1 && st[0].type == Type::Table && g.tab->field("SEAMTEST_CONST").num == 42 &&
              g_feat_log.size() == 1 && g_feat_log[0] == "open a",
          "features: gsa1.FEATURES {seamtest_a = %g, seamtest_b = %g}, SeamTestEcho(41) = %g, a bad argument -> nil, "
          "\"%s\", gsa1.Status stays the built-in (FEATURE_ERRORS[1] \"%s\"), the open hook ran once (%d log entries)",
          feats.type == Type::Table ? feats.tab->field("seamtest_a").num : -1.0,
          feats.type == Type::Table ? feats.tab->field("seamtest_b").num : -1.0, echo.empty() ? -1.0 : echo[0].num,
          str_of(bad, 1).c_str(), e1.c_str(), (int)g_feat_log.size());
    st = L.call("Status", {});
    CHECK(st.size() == 1 && st[0].type == Type::Table && st[0].tab->field("vector_mode").num == 1 && L.vectors_pushed == 2,
          "the vector mode is decided at gmod13_open (Status().vector_mode %g, %llu scratch Vectors made): the session "
          "log's header can name it", st.size() == 1 && st[0].type == Type::Table ? st[0].tab->field("vector_mode").num : -1.0,
          (unsigned long long)L.vectors_pushed);
}

// after gmod13_close: the close hooks ran in close order (b first), with the session still there
static void test_features_closed(bool shutdown_seen)
{
    size_t n = g_feat_log.size();
    bool order = n >= 3 && g_feat_log[n - 2] == "close b (session)" && g_feat_log[n - 1] == "close a (session)";
    int shutdowns = 0;
    for (const std::string &e : g_feat_log) {
        shutdowns += e == "shutdown a";
    }
    CHECK(order && (shutdowns > 0) == shutdown_seen,
          "gmod13_close: the features' close hooks ran %s, %s, with the session still there; the shutdown hook ran %d "
          "time(s) (once per gsa1.Shutdown)", n >= 2 ? g_feat_log[n - 2].c_str() : "-", n >= 1 ? g_feat_log[n - 1].c_str() : "-",
          shutdowns);
}

// the module's controller reads this fake XInput (gsa1::set_pad_provider_factory before gmod13_open)
static std::shared_ptr<gsa1::FakePad> g_fake_pad;
static std::unique_ptr<gsa1::PadProvider> fake_pad_factory()
{
    g_fake_pad = std::make_shared<gsa1::FakePad>();
    return std::unique_ptr<gsa1::PadProvider>(new gsa1::FakePadProvider(g_fake_pad));
}

// the controller functions (no disc needed); `out` is the caller's PadPoll table
static void test_pad(MockLua &L, Val &out)
{
    auto poll = [&](double dt) { return L.call("PadPoll", {Val::number(dt), Val::boolean(false), out}); };
    auto r = L.call("PadStatus", {});
    Table *P = r.size() == 1 && r[0].type == Type::Table ? r[0].tab.get() : nullptr;
    CHECK(P && P->field("enabled").b && P->field("backend").str == "fake" && !P->field("connected").b,
          "PadStatus(): enabled, backend \"%s\", nothing connected", P ? P->field("backend").str.c_str() : "?");
    r = poll(1.0 / 60.0);
    Table &O = *out.tab;
    CHECK(r.size() == 1 && r[0].type == Type::Table && r[0].tab == out.tab && O.field("available").b &&
              !O.field("connected").b && O.field("index").num == 0,
          "PadPoll(dt, paused, out) fills the caller's table: available, nothing connected (index 0)");
    g_fake_pad->set(1, gsa1::PAD_A, 0, 32767);
    for (int i = 0; i < 6 && !O.field("connected").b; i++) {
        poll(1.0 / 60.0);
    }
    CHECK(O.field("connected").b && O.field("index").num == 2 && O.field("active").b && O.field("input").b &&
              O.field("sx").num == 0 && std::fabs(O.field("sy").num - 1.0) < 1e-6 &&
              O.field("buttons").num == SA1_BUTTON_JUMP && ((uint32_t)O.field("pressed").num & gsa1::PAD_A) &&
              O.field("ly").num == 1.0 && O.field("yaw").num == 0 && O.field("reset").type == Type::Bool,
          "controller 2 (A, left stick up): index %g, active, SA1 stick (%g, %g), buttons %g (jump), pressed A",
          O.field("index").num, O.field("sx").num, O.field("sy").num, O.field("buttons").num);
    Val st = Val::table(), map = Val::table();
    map.tab->set(Val::string("start"), Val::number(gsa1::PAD_ACT_JUMP));
    map.tab->set(Val::string("a"), Val::number(99));
    st.tab->set(Val::string("map"), map);
    st.tab->set(Val::string("invert_y"), Val::boolean(true));
    st.tab->set(Val::string("cam_speed"), Val::number(120));
    st.tab->set(Val::string("dead_left"), Val::string("lots"));
    st.tab->set(Val::string("outer"), Val::number(NAN));
    st.tab->set(Val::string("index"), Val::number(2.5));
    r = L.call("PadSettings", {st});
    bool set_ok = r.size() == 1 && r[0].type == Type::Bool && r[0].b;
    g_fake_pad->set(1, gsa1::PAD_START | gsa1::PAD_A, 0, 0, 0, 32767);
    poll(0.25);
    CHECK(set_ok && O.field("buttons").num == SA1_BUTTON_JUMP && std::fabs(O.field("pitch").num - 30.0) < 1e-3 &&
              O.field("index").num == 2,
          "PadSettings{map = {start = jump, a = 99}, invert_y, cam_speed 120, junk fields}: true; Start jumps, A does "
          "nothing, right stick up looks down %.1f degrees in 0.25 s", O.field("pitch").num);
    int bad = 0;
    bad += is_nil_msg(L.call("PadSettings", {Val::string("x")}));
    bad += is_nil_msg(L.call("PadRumble", {Val::number(1)}));
    r = L.call("PadPoll", {Val::string("x"), Val::number(3)});
    bad += r.size() == 1 && r[0].type == Type::Table && r[0].tab != out.tab;
    CHECK(bad == 3, "%d of 3 bad controller calls answered without a Lua error (PadPoll(junk) -> a new table)", bad);
    r = L.call("PadRumble", {Val::number(1), Val::number(0.5), Val::number(0.25)});
    CHECK(r.size() == 1 && r[0].type == Type::Bool && r[0].b && g_fake_pad->vib_low[1] == 65535 &&
              g_fake_pad->vib_high[1] == 32768,
          "PadRumble(1, 0.5, 0.25): controller 2's motors at %u / %u", g_fake_pad->vib_low[1], g_fake_pad->vib_high[1]);
    Val off = Val::table();
    off.tab->set(Val::string("enabled"), Val::boolean(false));
    L.call("PadSettings", {off});
    poll(1.0 / 60.0);
    r = L.call("PadRumble", {Val::number(1), Val::number(1), Val::number(1)});
    CHECK(g_fake_pad->vib_low[1] == 0 && !O.field("connected").b && !O.field("enabled").b && is_nil_msg(r),
          "PadSettings{enabled = false}: motors off, nothing read, PadRumble -> false, \"%s\"", str_of(r, 1).c_str());
    Val on = Val::table(), dmap = Val::table();
    dmap.tab->set(Val::string("start"), Val::number(gsa1::PAD_ACT_NONE));
    dmap.tab->set(Val::string("a"), Val::number(gsa1::PAD_ACT_JUMP));
    on.tab->set(Val::string("map"), dmap);
    on.tab->set(Val::string("enabled"), Val::boolean(true));
    on.tab->set(Val::string("invert_y"), Val::boolean(false));
    on.tab->set(Val::string("cam_speed"), Val::number(180));
    on.tab->set(Val::string("index"), Val::number(0));
    L.call("PadSettings", {on});
    g_fake_pad->set(1, gsa1::PAD_START);
    for (int i = 0; i < 6; i++) {
        poll(1.0 / 60.0);
    }
    r = L.call("PadStatus", {});
    P = r.size() == 1 && r[0].type == Type::Table ? r[0].tab.get() : nullptr;
    CHECK(O.field("connected").b && O.field("buttons").num == 0 && P && P->field("slots").num == 2 &&
              P->field("index").num == 2 && P->field("polls").num > 10,
          "enabled again with the defaults: Start does nothing; PadStatus: slots %g, index %g, %g polls",
          P ? P->field("slots").num : -1.0, P ? P->field("index").num : -1.0, P ? P->field("polls").num : -1.0);
}

// ---- the game's thread (0.5.1): every module call of the addon's frames, timed ------------------------------------
// What cl_module.lua / cl_character.lua / cl_textures.lua / cl_render.lua call, frame by frame: InitPoll while the disc
// loads, MapPoll with MapFeed (at most 4 ms of feeding per frame, as READ_BUDGET) and MapFeedFile while the map loads,
// AudioPoll / AudioUpdate, the texture infos of a new character (at most 3 ms of Texture calls per frame, as the
// texture painter's budget), and with a character MoverCommit, Tick, GetState, Render, Batches (when its generation
// changes), PrepareView, EmitBatch per batch, PollEvents; PollLog twice a second.
struct Timing {
    std::map<std::string, std::vector<double>> calls;                 // function -> ms of every call
    std::map<std::string, std::pair<double, std::string>> worst;      // phase -> the slowest call
    std::vector<std::string> phases;
    std::string phase;
    std::map<std::string, double> frame_max;                          // phase -> the most module time in one frame
};

struct Driver {
    MockLua &L;
    Timing &T;
    const std::string &map;
    double id = 0;
    int frames = 0;
    bool disc_loading = false, map_loading = false, audio_opening = false;
    std::string map_state, disc_state, audio_msg, map_error;
    Val poll = Val::table(), state = Val::table(), batches = Val::table(), info = Val::table();
    double bgen = -1, frame_acc = 0;
    std::vector<std::array<int, 3>> textures;                         // (kind, archive, index) still to fetch
    std::set<int> kinds_textured;
    int texture_fails = 0, tick_fails = 0;

    Driver(MockLua &l, Timing &t, const std::string &m) : L(l), T(t), map(m) {}

    std::vector<Val> call(const char *name, std::vector<Val> args)
    {
        double t0 = gsa1::now_ms();
        std::vector<Val> r = L.call(name, std::move(args));
        double dt = gsa1::now_ms() - t0;
        T.calls[name].push_back(dt);
        auto &w = T.worst[T.phase];
        if (dt > w.first) {
            w.first = dt;
            w.second = name;
        }
        frame_acc += dt;
        return r;
    }
    void begin(const char *phase)
    {
        T.phase = phase;
        T.phases.push_back(phase);
    }
    void start_map()
    {
        Val opts = Val::table();
        opts.tab->set(Val::string("cache"), Val::boolean(false));   // build it every time (the worst case)
        auto r = call("MapStartData", {Val::string("gsa1_timing"), Val::string(map.substr(0, 1036)),
                                       Val::number((double)map.size()), opts});
        map_loading = r.size() == 2 && r[0].b;
        map_state = map_loading ? "started" : "failed";
    }
    bool apply_map()
    {
        auto r = call("MapApply", {});
        if (r.size() == 2 && r[0].b && r[1].type == Type::Table) {
            info = r[1];
            return true;
        }
        map_error = str_of(r, 1);
        return false;
    }
    void create(int kind, std::vector<Val> extra = {})
    {
        if (id > 0) {
            call("Destroy", {Val::number(id)});
            id = 0;
        }
        std::vector<Val> args{Val::number(kind), Val::vector(704, 132, -139), Val::number(180)};
        for (auto &v : extra) args.push_back(v);
        auto r = call("Create", args);
        id = r.size() == 1 && r[0].type == Type::Number ? r[0].num : 0;
        bgen = -1;
        if (id > 0 && !kinds_textured.count(kind)) {
            // GSA1.Tex.Prepare(kind): the archives now, the texture infos over the next frames
            kinds_textured.insert(kind);
            auto a = call("TextureArchives", {Val::number(kind)});
            if (a.size() == 1 && a[0].type == Type::Table) {
                for (double ai = 1; a[0].tab->at(ai).type == Type::Table; ai++) {
                    int count = (int)a[0].tab->at(ai).tab->field("count").num;
                    for (int i = 0; i < count; i++) {
                        textures.push_back({kind, (int)ai - 1, i});
                    }
                }
            }
        }
    }
    void frame()
    {
        frame_acc = 0;
        frames++;
        // the mock mesh library keeps every vertex it is given: start each frame empty (capacity kept), so the
        // test's own bookkeeping does not land in EmitBatch's times
        g_mesh.vp.clear();
        g_mesh.vn.clear();
        g_mesh.vuv.clear();
        g_mesh.vc.clear();
        if (disc_loading) {
            auto r = call("InitPoll", {});
            disc_state = str_of(r, 0);
            disc_loading = disc_state == "loading";
        }
        if (map_loading) {
            auto r = call("MapPoll", {poll});
            map_state = r.size() == 1 && r[0].type == Type::Table ? r[0].tab->field("state").str : "gone";
            if (map_state == "reading") {
                double t0 = gsa1::now_ms();
                Val needs = r[0].tab->field("needs");
                for (double i = 1; needs.tab->at(i).type == Type::Table && gsa1::now_ms() - t0 < 4.0; i++) {
                    double ofs = needs.tab->at(i).tab->field("ofs").num, len = needs.tab->at(i).tab->field("len").num;
                    call("MapFeed", {Val::number(ofs), Val::string(map.substr((size_t)ofs, (size_t)len))});
                }
            } else if (map_state == "files") {
                double t0 = gsa1::now_ms();
                Val fl = r[0].tab->field("files");
                for (double i = 1; fl.tab->at(i).type == Type::Table && gsa1::now_ms() - t0 < 4.0; i++) {
                    call("MapFeedFile", {fl.tab->at(i).tab->field("path"), Val()});
                }
            } else if (map_state == "ready" || map_state == "failed" || map_state == "gone") {
                map_loading = false;
            }
        }
        if (audio_opening) {
            auto r = call("AudioPoll", {});
            if (!(r.size() == 1 && r[0].type == Type::Nil)) {
                audio_opening = false;
                audio_msg = str_of(r, 1);
            }
        }
        if (id > 0) {
            call("MoverCommit", {});
            bool fwd = (frames / 90) % 2 == 1;
            int b = (frames % 120) == 100 ? 1 : 0;
            auto r = call("Tick", {Val::number(id), Val::number(0), Val::number(fwd ? 1 : 0), Val::number(180),
                                   Val::number(b), Val::number(1.0 / 60.0)});
            tick_fails += !(r.size() == 1 && r[0].type == Type::Number);
            call("GetState", {Val::number(id), state});
            auto m = call("Render", {Val::number(id), Val::number(-1)});
            if (m.size() == 10 && m[1].num != bgen) {
                bgen = m[1].num;
                call("Batches", {Val::number(id), batches});
            }
            call("PrepareView", {Val::number(id), Val::vector(704, 300, -100), Val::vector(1, 0, 0), Val::vector(0, 0, 1)});
            int count = (int)batches.tab->field("count").num;
            for (int b2 = 1; b2 <= count; b2++) {
                call("EmitBatch", {Val::number(id), Val::number(b2)});
            }
            call("PollEvents", {});
        }
        call("AudioUpdate", {Val::vector(704, 300, -100), Val::vector(0, -1, 0), Val::vector(0, 0, 1), Val::number(1),
                             Val::boolean(false), Val::number(1.0 / 60.0)});
        if (!textures.empty()) {
            double t0 = gsa1::now_ms();
            while (!textures.empty() && gsa1::now_ms() - t0 < 3.0) {
                std::array<int, 3> t = textures.front();
                textures.erase(textures.begin());
                auto r = call("Texture", {Val::number(t[0]), Val::number(t[2]), Val::number(t[1])});
                texture_fails += !(r.size() == 1 && r[0].type == Type::Table);
            }
        }
        if (frames % 30 == 0) {
            call("PollLog", {});
        }
        double &fm = T.frame_max[T.phase];
        fm = std::max(fm, frame_acc);
        std::this_thread::sleep_for(std::chrono::milliseconds(2));   // the rest of the frame: workers run meanwhile
    }
    void frames_n(int n)
    {
        for (int i = 0; i < n; i++) frame();
    }
};

static double pct(std::vector<double> v, double p)
{
    if (v.empty()) return 0.0;
    std::sort(v.begin(), v.end());
    size_t i = (size_t)std::min<double>((double)v.size() - 1, std::floor(p * (double)(v.size() - 1) + 0.5));
    return v[i];
}

static void game_thread_timing(MockLua &L, const std::string &map, const char *label)
{
    std::printf("the game's thread: %s (%.1f MB)\n", label, map.size() / 1048576.0);
    Timing T;
    Driver D(L, T, map);
    L.call("Shutdown", {});   // the module as at a map start: no disc, no world, no sound
    // the map starts: gsa1_preload loads the disc and the map's collision in the background
    D.begin("first spawn");
    auto r = D.call("Init", {});
    D.disc_loading = r.size() == 2 && r[0].b && str_of(r, 1) == "loading";
    D.start_map();
    int waited = 0;
    while ((D.disc_loading || D.map_loading) && waited < 30000) {
        D.frame();
        waited++;
    }
    bool applied = D.map_state == "ready" && D.disc_state == "ready" && D.apply_map();
    r = D.call("AudioOpen", {});
    D.audio_opening = r.size() == 2 && r[0].b;
    D.create(SA1_CHAR_SONIC);
    double first_id = D.id;
    D.frames_n(150);
    CHECK(applied && first_id > 0 && D.info.tab->field("prepared").b && !D.audio_opening && waited > 5,
          "first spawn: disc and map loaded in the background over %d frames, MapApply (prepared: %s), Sonic created, "
          "the sound banks opened meanwhile (%s)", waited, D.info.tab->field("prepared").b ? "yes" : "no",
          D.audio_msg.c_str());
    D.begin("respawn");
    for (int k = 0; k < 3; k++) {
        D.create(SA1_CHAR_SONIC);
        D.frames_n(40);
    }
    D.begin("character switch");
    const int kinds[] = {SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA, SA1_CHAR_BIG, SA1_CHAR_SONIC};
    int switched = 0;
    for (int k : kinds) {
        D.create(k);
        switched += D.id > 0;
        D.frames_n(60);
    }
    D.begin("map reload");
    D.start_map();
    int reload_frames = 0;
    while (D.map_loading && reload_frames < 30000) {
        D.frame();   // the character keeps playing on the old world meanwhile
        reload_frames++;
    }
    bool reapplied = D.map_state == "ready" && D.apply_map();
    D.create(SA1_CHAR_SONIC);   // GSA1.Recreate: the character on the new world
    D.frames_n(60);
    D.begin("upgrades");
    Val names = Val::table();
    names.tab->set(Val::number(1), Val::string("shovel_claw"));
    names.tab->set(Val::number(2), Val::string("fighting_gloves"));
    D.create(SA1_CHAR_KNUCKLES, {names});
    D.frames_n(60);
    D.frames_n(1);
    if (D.id > 0) {
        D.call("Destroy", {Val::number(D.id)});
        D.id = 0;
    }
    CHECK(switched == 6 && reapplied && reload_frames > 5 && D.tick_fails == 0 && D.texture_fails == 0 &&
              D.textures.empty(),
          "respawns, 6 character switches, a map reload over %d frames while playing (MapApply %s), an upgrade "
          "re-creation; %d frames in all, every texture info fetched", reload_frames, reapplied ? "ok" : D.map_error.c_str(),
          D.frames);
    std::printf("        %-16s %6s %8s %8s %8s\n", "call", "n", "p50 ms", "p90 ms", "max ms");
    double worst = 0;
    std::string worst_fn;
    for (auto &kv : T.calls) {
        double mx = *std::max_element(kv.second.begin(), kv.second.end());
        std::printf("        %-16s %6zu %8.3f %8.3f %8.3f%s\n", kv.first.c_str(), kv.second.size(), pct(kv.second, 0.5),
                    pct(kv.second, 0.9), mx, mx > 8.0 ? "  OVER 8 ms" : "");
        if (mx > worst) {
            worst = mx;
            worst_fn = kv.first;
        }
    }
    for (const std::string &ph : T.phases) {
        std::printf("        phase %-18s slowest call %-14s %7.3f ms; most module time in one frame %7.3f ms\n",
                    ph.c_str(), T.worst[ph].second.c_str(), T.worst[ph].first, T.frame_max[ph]);
    }
    CHECK(worst <= 8.0, "no call on the game's thread took more than 8 ms (the slowest: %s, %.3f ms)", worst_fn.c_str(),
          worst);
    L.call("Shutdown", {});
}

// ---- 0.9.2 (sadc docs/research/gsa1_090_plan.md 6.10): faults, host flags, start rings --------------------------------
// A world killed by a fatal stub (gsa1_090_faults.md F3.2 with its review R.2.5): a task whose exec is a function libsa1
// has only as a fatal stub, made inside the character's world with the game's CreateElementalTask (libsa1's
// sa1g_create_task through sa1g_world_call, the internal calls its own stage code uses); its next step runs into the stub.
// 0.9.1 answered "error" and every later tick re-entered the step; now gsa1.Tick answers code "fault" from that tick and
// from the one after it, and a new character runs normally.
extern "C" {
typedef void (*bt_world_fn)(struct sa1g_world *w, void *user);
sa1_status sa1g_world_call(struct sa1g_world *w, bt_world_fn fn, void *user);
uint32_t sa1g_create_task(uint16_t im, int32_t list, uint32_t exec);
const char *sa1_fn_name(uint32_t g);
}
struct FatalTask {
    uint32_t exec = 0, task = 0;
};
static void make_fatal_task(struct sa1g_world *, void *user)
{
    FatalTask *f = (FatalTask *)user;
    f->task = sa1g_create_task(2, 3, f->exec);
}
// a task exec (v:p) that libsa1 has only as a fatal stub (gen/policy/stubs.tsv "fatal"), or 0
static uint32_t fatal_exec_addr()
{
    static const uint32_t cand[] = {0x8C051D38u, 0x8C06BEA0u, 0x8C048528u, 0x8C048624u, 0x8C048B00u};
    for (uint32_t a : cand) {
        if (sa1_fn_name(a) != nullptr) {
            return a;
        }
    }
    return 0u;
}

static void test_092(MockLua &L, const Val &g)
{
    std::printf("  -- 0.9.2: faults, host flags, start rings\n");
    CHECK(g.tab->field("TICK_HOST_FLAGS").type == Type::Bool && g.tab->field("TICK_HOST_FLAGS").b &&
              g.tab->field("INPUT_HOST_WATER_KNOWN").num == 1 && g.tab->field("INPUT_HOST_IN_WATER").num == 2 &&
              g.tab->field("TICK_HOST_CAMERA").type == Type::Bool && g.tab->field("START_RINGS_MAX").num == 99 &&
              g.tab->field("CAPACITY_LAND_QUERY").num == 8 && g.tab->field("CAPACITY_LAND_HITS").num == 9,
          "constants: TICK_HOST_FLAGS, INPUT_HOST_WATER_KNOWN 1 / IN_WATER 2, TICK_HOST_CAMERA %s, START_RINGS_MAX 99, "
          "CAPACITY_LAND_QUERY 8 / LAND_HITS 9", g.tab->field("TICK_HOST_CAMERA").b ? "true" : "false");
    // start rings
    auto r = L.call("Create", {Val::number(0), Val::vector(704, 132, -139), Val::number(180), Val(), Val::number(25)});
    double rid = r.size() == 1 && r[0].type == Type::Number ? r[0].num : 0;
    Val st = Val::table();
    L.call("GetState", {Val::number(rid), st});
    auto ex = L.call("StateEx", {Val::number(rid)});
    double rings = ex.size() == 1 && ex[0].type == Type::Table ? ex[0].tab->field("rings").num : -1;
    CHECK(rid > 0 && st.tab->field("start_rings").num == 25 && rings == 25,
          "Create(sonic, pos, yaw, nil, 25): a world with 25 rings before its first tick (GetState start_rings %g, StateEx "
          "rings %g)", st.tab->field("start_rings").num, rings);
    int bad = 0;
    bad += is_nil_msg(L.call("Create", {Val::number(0), Val::vector(704, 132, -139), Val::number(180), Val(),
                                        Val::string("x")}));
    bad += is_nil_msg(L.call("Create", {Val::number(0), Val::vector(704, 132, -139), Val::number(180), Val(),
                                        Val::number(2.5)}));
    // host flags and the host camera
    r = L.call("Tick", {Val::number(rid), Val::number(0), Val::number(0), Val::number(180), Val::number(0),
                        Val::number(1.0 / 30.0), Val::boolean(false), Val::number(1), Val::vector(0, 0, 100),
                        Val::vector(10, 0, 100)});
    L.call("GetState", {Val::number(rid), st});
    gsa1::Character *c = gsa1::mod::session()->get((int32_t)rid);
    CHECK(r.size() == 1 && r[0].type == Type::Number && st.tab->field("host_flags").num == 1 && c && c->host_camera_last &&
              st.tab->field("water_attr").type == Type::Number && st.tab->field("in_water").type == Type::Bool &&
              st.tab->field("water_level").type == Type::Number,
          "Tick(..., rawStick, hostFlags 1, camOrigin, camTarget) -> %g pairs; GetState: host_flags %g, water_attr %g, "
          "in_water %s, the camera recorded", r.empty() ? -1.0 : r[0].num, st.tab->field("host_flags").num,
          st.tab->field("water_attr").num, st.tab->field("in_water").b ? "true" : "false");
    bad += is_nil_msg(L.call("Tick", {Val::number(rid), Val::number(0), Val::number(0), Val::number(180), Val::number(0),
                                      Val::number(1.0 / 30.0), Val::boolean(false), Val::string("water")}));
    bad += is_nil_msg(L.call("Tick", {Val::number(rid), Val::number(0), Val::number(0), Val::number(180), Val::number(0),
                                      Val::number(1.0 / 30.0), Val::boolean(false), Val::number(-1)}));
    CHECK(bad == 4, "%d of 4 bad start rings / host flags answered with nil + message", bad);
    L.call("Destroy", {Val::number(rid)});

    // a world killed by a fatal stub
    uint32_t fa = fatal_exec_addr();
    if (fa == 0u) {
        std::printf("  info  no fatal-stub task exec in this libsa1 (all candidates have C): the fault test is skipped\n");
        return;
    }
    r = L.call("Create", {Val::number(0), Val::vector(704, 132, -139), Val::number(180)});
    double fid = r.size() == 1 && r[0].type == Type::Number ? r[0].num : 0;
    L.call("Tick", {Val::number(fid), Val::number(0), Val::number(0), Val::number(180), Val::number(0),
                    Val::number(1.0 / 30.0)});
    sa1_context *ctx = gsa1::mod::session()->ctx();
    struct sa1g_world *w = ctx && fid > 0 ? sa1_character_world(ctx, (sa1_character_id)fid) : nullptr;
    FatalTask ft;
    ft.exec = fa;
    sa1_status cs = w ? sa1g_world_call(w, make_fatal_task, &ft) : SA1_ERR_NOT_FOUND;
    CHECK(cs == SA1_OK && ft.task != 0, "a task with the fatal stub %08X (%s) as its exec made in the world (task %08X)",
          (unsigned)fa, sa1_fn_name(fa) ? sa1_fn_name(fa) : "?", (unsigned)ft.task);
    auto t1 = L.call("Tick", {Val::number(fid), Val::number(0), Val::number(0), Val::number(180), Val::number(0),
                              Val::number(1.0 / 30.0)});
    gsa1::Character *fc = gsa1::mod::session()->get((int32_t)fid);
    bool first_fatal = fc && fc->faulted && fc->fault_status == SA1_ERR_NOT_IMPLEMENTED;
    std::printf("  info  the fatal tick's libsa1 status: %s\n", fc ? sa1_status_string(fc->fault_status) : "?");
    auto t2 = L.call("Tick", {Val::number(fid), Val::number(0), Val::number(0), Val::number(180), Val::number(0),
                              Val::number(1.0 / 30.0)});
    L.call("GetState", {Val::number(fid), st});
    CHECK(is_nil_msg(t1) && str_of(t1, 2) == "fault" && first_fatal && is_nil_msg(t2) && str_of(t2, 2) == "fault" &&
              st.tab->field("faulted").b,
          "the world dies in the fatal stub: Tick -> nil, \"%s\", %s (libsa1: not implemented); the tick after it -> nil, "
          "\"%s\", %s; GetState().faulted", str_of(t1, 1).c_str(), str_of(t1, 2).c_str(), str_of(t2, 1).c_str(),
          str_of(t2, 2).c_str());
    L.call("Destroy", {Val::number(fid)});
    r = L.call("Create", {Val::number(0), Val::vector(704, 132, -139), Val::number(180)});
    double nid = r.size() == 1 && r[0].type == Type::Number ? r[0].num : 0;
    int pairs = 0;
    for (int f = 0; f < 30 && nid > 0; f++) {
        auto t = L.call("Tick", {Val::number(nid), Val::number(0), Val::number(0), Val::number(180), Val::number(0),
                                 Val::number(1.0 / 30.0)});
        pairs += t.size() == 1 && t[0].type == Type::Number ? (int)t[0].num : -1000;
    }
    CHECK(nid > 0 && pairs == 30, "a new character after the fault runs normally (%d pairs in 30 ticks)", pairs);
    L.call("Destroy", {Val::number(nid)});
}

int main(int argc, char **argv)
{
    std::string bsp = gsa1_garrysmod_dir()[0] ? std::string(gsa1_garrysmod_dir()) + "\\maps\\gm_construct.bsp" : std::string();
    std::string gdi, timing_bsp;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--bsp") bsp = argv[++i];
        else if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
        else if (std::string(argv[i]) == "--timing-bsp") timing_bsp = argv[++i];
    }
    std::printf("G-SA1 binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;

    // a private configuration directory for this run
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "binding_test_appdata");
#ifdef _WIN32
    SetEnvironmentVariableW(L"APPDATA", gsa1::widen(fake_appdata).c_str());
    if (fake_appdata.size() < 3 || fake_appdata[1] != ':') {
        char full[4096];
        GetFullPathNameA(fake_appdata.c_str(), sizeof full, full, nullptr);
        fake_appdata = full;
        SetEnvironmentVariableW(L"APPDATA", gsa1::widen(fake_appdata).c_str());
    }
#else
    setenv("XDG_CONFIG_HOME", fake_appdata.c_str(), 1);
#endif

    gsa1::set_pad_provider_factory(fake_pad_factory);
    gmod13_open(&state);
    Val g = L.globals.tab->field("gsa1");
    CHECK(g.type == Type::Table && L.st.empty(), "gmod13_open registers the gsa1 table and leaves the stack empty");
    if (g.type != Type::Table) return 1;
    int fns = 0;
    for (auto &kv : g.tab->s) fns += kv.second.type == Type::Function;
    // 53 built-in functions + the dummy features' SeamTestEcho and SeamTestSession (their "Status" is refused) + the
    // real features' functions
    int real_fns = 0;
    real_features(&real_fns);
    CHECK(fns == 53 + 2 + real_fns && g.tab->field("API_VERSION").num == 6 && g.tab->field("CHAR_BIG").num == 7 &&
              g.tab->field("InitPoll").type == Type::Function && g.tab->field("AudioPoll").type == Type::Function &&
              g.tab->field("CAPACITY_NEAR_POLYGONS").num == 5 &&
              g.tab->field("SCALE").num == 4.0 && g.tab->field("VERSION").type == Type::String &&
              g.tab->field("PAD_ACT_CAM_RESET").num == 8 && g.tab->field("PAD_A").num == 0x1000 &&
              g.tab->field("PAD_LT").num == 0x10000,
          "%d functions, API_VERSION %g, constants present", fns, g.tab->field("API_VERSION").num);
    test_features_open(L, g);
    Val pad_out = Val::table();
    test_pad(L, pad_out);

    auto r = L.call("Status", {});
    CHECK(r.size() == 1 && r[0].type == Type::Table && !r[0].tab->field("ready").b, "Status() before Init: not ready");
    r = L.call("Create", {Val::number(0), Val::vector(0, 0, 0), Val::number(0)});
    CHECK(is_nil_msg(r), "Create before Init: nil, \"%s\"", str_of(r, 1).c_str());

    // Init without a config file
    gsa1::make_dirs(fake_appdata);
    std::string cfgdir = gsa1::config_dir();
    std::remove(gsa1::join_path(cfgdir, "config.txt").c_str());
    r = L.call("Init", {});
    CHECK(is_nil_msg(r) && str_of(r, 1).find(fake_appdata) == std::string::npos,
          "Init without a config file: false, \"%s\" (code %s)", str_of(r, 1).c_str(), str_of(r, 2).c_str());
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the rest needs the disc\n");
        gmod13_close(&state);
        CHECK(g_fake_pad && g_fake_pad->vib_low[1] == 0, "gmod13_close: the controller's motors are off");
        test_features_closed(false);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    gsa1::Config cfg;
    cfg.disc = gdi;
    std::string err;
    CHECK(gsa1::save_config(cfg, err), "config written to the scratch APPDATA (%s)", err.c_str());
    r = L.call("InitPoll", {});
    CHECK(r.size() == 4 && str_of(r, 0) == "idle", "InitPoll() before Init: \"%s\"", str_of(r, 0).c_str());
    double ti = gsa1::now_ms();
    r = L.call("Init", {});
    double init_ms = gsa1::now_ms() - ti;
    CHECK(r.size() == 2 && r[0].type == Type::Bool && r[0].b && str_of(r, 1) == "loading",
          "Init(): true, \"%s\" at once (%.2f ms): the disc loads on a worker thread", str_of(r, 1).c_str(), init_ms);
    r = L.call("Init", {Val::string("C:\\Windows\\win.ini")});
    CHECK(r.size() == 2 && r[0].b, "Init ignores arguments (no path from Lua): \"%s\"", str_of(r, 1).c_str());
    {
        int polls = 0, changed = 0;
        double poll_max = 0;
        std::string st = "loading", msg;
        while (st == "loading" && polls < 20000) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            double t0 = gsa1::now_ms();
            r = L.call("InitPoll", {});
            poll_max = std::max(poll_max, gsa1::now_ms() - t0);
            polls++;
            st = str_of(r, 0);
            msg = str_of(r, 1);
            changed += r.size() == 4 && r[3].b;
        }
        Val s = L.call("Status", {})[0];
        CHECK(st == "ready" && changed == 1 && s.tab->field("ready").b && s.tab->field("disc_state").str == "ready",
              "InitPoll() while it loads: %d polls (the longest %.2f ms), then \"%s\": \"%s\"", polls, poll_max,
              st.c_str(), msg.c_str());
        r = L.call("Init", {});
        CHECK(r.size() == 2 && r[0].b && str_of(r, 1) == "already initialised", "Init() again: \"%s\"",
              str_of(r, 1).c_str());
    }

    // world
    r = L.call("WorldLoad", {Val::string("../../secret")});
    CHECK(is_nil_msg(r) && str_of(r, 2) == "bad_name", "WorldLoad(\"../../secret\"): false, bad_name");
    r = L.call("WorldLoad", {Val::string("gm_construct")});
    CHECK(is_nil_msg(r) && str_of(r, 2) == "not_found",
          "WorldLoad outside garrysmod/lua/bin: false, not_found (\"%s\")", str_of(r, 1).c_str());
    std::string map;
    gsa1::read_small_file(bsp, 512u << 20, map, err);
    r = L.call("WorldLoadData", {Val::string("VBSPgarbage"), Val::string("x")});
    CHECK(is_nil_msg(r), "WorldLoadData(garbage): false, \"%s\"", str_of(r, 1).c_str());
    r = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(r.size() == 2 && r[0].b && r[1].type == Type::Table && r[1].tab->field("triangles").num > 1000,
          "WorldLoadData(gm_construct bytes): true, %g triangles, %g displacements, parsed in %.0f ms",
          r.size() == 2 && r[1].type == Type::Table ? r[1].tab->field("triangles").num : 0.0,
          r.size() == 2 && r[1].type == Type::Table ? r[1].tab->field("displacements").num : 0.0,
          r.size() == 2 && r[1].type == Type::Table ? r[1].tab->field("parse_ms").num : 0.0);

    // the map's collision in the background, fed the way the addon reads a workshop map (only the ranges asked for)
    {
        r = L.call("MapStart", {Val::string("gm_construct")});
        CHECK(is_nil_msg(r) && str_of(r, 2) == "not_found", "MapStart outside garrysmod/lua/bin: false, not_found");
        r = L.call("MapStartData", {Val::string("gm_construct"), Val::string(map.substr(0, 100)), Val::number((double)map.size())});
        CHECK(is_nil_msg(r) && str_of(r, 2) == "bad_map", "MapStartData with a short header: false, bad_map");
        r = L.call("MapFeed", {Val::number(0), Val::string("x")});
        CHECK(is_nil_msg(r), "MapFeed without a map loading: false, \"%s\"", str_of(r, 1).c_str());
        Val opts = Val::table();
        opts.tab->set(Val::string("cache"), Val::boolean(false));
        r = L.call("MapStartData", {Val::string("gm_construct"), Val::string(map.substr(0, 1036)),
                                    Val::number((double)map.size()), opts});
        CHECK(r.size() == 2 && r[0].type == Type::Bool && r[0].b && str_of(r, 1) == "fed",
              "MapStartData(gm_construct, header, size): true, \"%s\"", str_of(r, 1).c_str());
        Val poll = Val::table();
        uint64_t fed = 0;
        int polls = 0, files = 0, preparing = 0;
        std::string state;
        bool feed_ok = true;
        double t0 = gsa1::now_ms();
        while (polls < 1000000) {
            polls++;
            r = L.call("MapPoll", {poll});
            if (r.size() != 1 || r[0].type != Type::Table) break;
            state = r[0].tab->field("state").str;
            preparing += state == "preparing";
            if (state == "ready" || state == "failed") break;
            Val needs = r[0].tab->field("needs"), fl = r[0].tab->field("files");
            for (double i = 1; needs.type == Type::Table && needs.tab->at(i).type == Type::Table; i++) {
                double ofs = needs.tab->at(i).tab->field("ofs").num, len = needs.tab->at(i).tab->field("len").num;
                auto f = L.call("MapFeed", {Val::number(ofs), Val::string(map.substr((size_t)ofs, (size_t)len))});
                feed_ok = feed_ok && f.size() == 1 && f[0].b;
                fed += (uint64_t)len;
            }
            for (double i = 1; fl.type == Type::Table && fl.tab->at(i).type == Type::Table; i++) {
                L.call("MapFeedFile", {fl.tab->at(i).tab->field("path"), Val()});   // no model files here: missing
                files++;
            }
        }
        CHECK(state == "ready" && feed_ok && fed > 0 && fed < map.size() / 8 && files >= 1 && preparing > 0,
              "MapPoll / MapFeed / MapFeedFile: %s after %d polls (%.0f ms, %d of them \"preparing\"); %.1f MB of %.1f MB "
              "fed, %d model files asked for", state.c_str(), polls, gsa1::now_ms() - t0, preparing, fed / 1048576.0,
              map.size() / 1048576.0, files);
        double ta = gsa1::now_ms();
        r = L.call("MapApply", {});
        double apply_ms = gsa1::now_ms() - ta;
        Val info = r.size() == 2 ? r[1] : Val();
        CHECK(r.size() == 2 && info.type == Type::Table && info.tab->field("prepared").b &&
                  info.tab->field("grid_triangles").num > info.tab->field("triangles").num * 0.5 &&
                  info.tab->field("grid_objects").num > 0 && info.tab->field("thin_wall_max").num == 16 && apply_ms < 8.0,
              "MapApply() in %.2f ms: prepared on the worker in %.0f ms (%g GRID triangles in %g objects, %g undersides "
              "left out)", apply_ms, info.type == Type::Table ? info.tab->field("prepare_ms").num : 0.0,
              info.type == Type::Table ? info.tab->field("grid_triangles").num : 0.0,
              info.type == Type::Table ? info.tab->field("grid_objects").num : 0.0,
              info.type == Type::Table ? info.tab->field("grid_undersides").num : 0.0);
        CHECK(r.size() == 2 && r[0].b && info.type == Type::Table && info.tab->field("full").b &&
                  info.tab->field("triangles").num > 30000 && info.tab->field("brush_models").num >= 6 &&
                  info.tab->field("props_missing").num == info.tab->field("props_solid").num &&
                  info.tab->field("one_way_solids").num > 0,
              "MapApply(): true, %g triangles, %g brush models, %g one-way platforms, %g static props without their "
              "model files", info.type == Type::Table ? info.tab->field("triangles").num : 0.0,
              info.type == Type::Table ? info.tab->field("brush_models").num : 0.0,
              info.type == Type::Table ? info.tab->field("one_way_solids").num : 0.0,
              info.type == Type::Table ? info.tab->field("props_missing").num : 0.0);
        {
            // 0.9.2a (the 0.9.2 verifier's leftover): the collision guard, thin stacks and the preparation's fallback
            const char *nums[] = {"thin_wall_kept", "thin_stacks", "tris_outside", "frags_outside", "displacements_nohull",
                                  "props_outside", "prepare_left_out"};
            int missing = 0;
            std::string vals;
            for (const char *k : nums) {
                bool ok = info.type == Type::Table && info.tab->field(k).type == Type::Number;
                missing += !ok;
                vals += gsa1::format("%s%s %g", vals.empty() ? "" : ", ", k, ok ? info.tab->field(k).num : -1.0);
            }
            CHECK(missing == 0 && info.tab->field("prepare_retried").type == Type::Bool &&
                      info.tab->field("too_big").type == Type::Bool && !info.tab->field("too_big").b,
                  "MapApply's info has 0.9.2's guard counters: %s; prepare_retried %s, too_big %s", vals.c_str(),
                  info.type == Type::Table && info.tab->field("prepare_retried").b ? "true" : "false",
                  info.type == Type::Table && info.tab->field("too_big").b ? "true" : "false");
        }
        r = L.call("MapPoll", {});
        Val st = L.call("Status", {})[0];
        CHECK(r.size() == 1 && r[0].type == Type::Nil && st.tab->field("map_state").str == "idle" &&
                  st.tab->field("world_full").b,
              "after MapApply: no job (MapPoll -> nil, Status().map_state \"%s\"), the world is the full one",
              st.tab->field("map_state").str.c_str());
        r = L.call("ShapeKnown", {Val::string("b3")});
        CHECK(r.size() == 1 && r[0].b, "ShapeKnown(\"b3\"): gm_construct's func_brush *3 is a moving object's shape");
        int mbad = 0;
        mbad += is_nil_msg(L.call("ShapePhy", {Val::string("bad key"), Val::string("x")}));
        mbad += is_nil_msg(L.call("ShapePhy", {Val::string("m:models/x.mdl"), Val::string("not a phy file")}));
        mbad += is_nil_msg(L.call("ShapeBox", {Val::string("x:b"), Val::vector(0, 0, 0), Val::vector(0, 0, 0)}));
        mbad += is_nil_msg(L.call("ShapeBox", {Val::string("m:b"), Val::vector(-8, -8, 0), Val::vector(8, 8, 16)}));
        r = L.call("MoverUpdate", {Val::number(5), Val::string("x:crate"), Val::vector(0, 0, 0), Val::vector(0, 0, 0)});
        mbad += r.size() == 1 && r[0].type == Type::Bool && !r[0].b;   // a Vector where the Angle goes
        mbad += is_nil_msg(L.call("MapFeedFile", {Val::string("models/x.phy"), Val()}));
        CHECK(mbad == 6, "%d of 6 bad shape / mover calls answered with false (+ message)", mbad);
        r = L.call("ShapeBox", {Val::string("x:crate"), Val::vector(-16, -16, 0), Val::vector(16, 16, 32)});
        CHECK(r.size() == 2 && r[0].b && r[1].num == 12, "ShapeBox(\"x:crate\", 32-unit box): true, %g triangles",
              r.size() == 2 ? r[1].num : 0.0);
    }

    r = L.call("CharacterInfo", {Val::number(0)});
    CHECK(r.size() == 1 && r[0].type == Type::Table && r[0].tab->field("radius").num == 16.0 &&
              r[0].tab->field("height").num == 40.0,
          "CharacterInfo(sonic): radius %g, height %g, centre %g Hammer units",
          r.empty() || r[0].type != Type::Table ? 0.0 : r[0].tab->field("radius").num,
          r.empty() || r[0].type != Type::Table ? 0.0 : r[0].tab->field("height").num,
          r.empty() || r[0].type != Type::Table ? 0.0 : r[0].tab->field("center").num);

    // bad arguments
    int bad = 0;
    bad += is_nil_msg(L.call("Create", {Val::string("sonic"), Val::vector(0, 0, 0), Val::number(0)}));
    bad += is_nil_msg(L.call("Create", {Val::number(0), Val::number(1), Val::number(0)}));
    bad += is_nil_msg(L.call("Create", {Val::number(0.5), Val::vector(0, 0, 0), Val::number(0)}));
    bad += is_nil_msg(L.call("Create", {Val::number(1), Val::vector(0, 0, 0), Val::number(0)}));   // Eggman
    bad += is_nil_msg(L.call("Create", {Val::number(0), Val::vector(NAN, 0, 0), Val::number(0)}));
    bad += is_nil_msg(L.call("Tick", {Val::number(12345), Val::number(0), Val::number(0), Val::number(0), Val::number(0), Val::number(0.01)}));
    bad += is_nil_msg(L.call("Texture", {Val::number(0), Val::number(9999)}));
    bad += is_nil_msg(L.call("Pose", {Val::number(1)}));
    r = L.call("GetState", {Val::number(777)});
    bad += r.size() == 1 && r[0].type == Type::Nil;
    r = L.call("Destroy", {Val::string("x")});
    bad += r.size() == 1 && r[0].type == Type::Bool && !r[0].b;
    CHECK(bad == 10, "%d of 10 bad calls answered with nil / false (+ message), none raised a Lua error", bad);

    // a character, with sound
    install_mesh_library(L);
    double tao = gsa1::now_ms();
    r = L.call("AudioOpen", {});
    double ao_ms = gsa1::now_ms() - tao;
    CHECK(r.size() == 2 && r[0].type == Type::Bool && r[0].b && ao_ms < 8.0,
          "AudioOpen(): true, \"%s\" (%.2f ms: the banks open on a worker thread)", str_of(r, 1).c_str(), ao_ms);
    {
        Val as = L.call("AudioStatus", {})[0];
        bool opening = as.tab->field("opening").b && !as.tab->field("open").b;
        int polls = 0;
        std::vector<Val> ap;
        while (polls < 20000) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            polls++;
            ap = L.call("AudioPoll", {});
            if (!(ap.size() == 1 && ap[0].type == Type::Nil)) break;
        }
        as = L.call("AudioStatus", {})[0];
        auto again = L.call("AudioPoll", {});
        CHECK(opening && ap.size() == 2 && ap[0].b && as.tab->field("open").b && !as.tab->field("opening").b &&
                  again.size() == 1 && again[0].type == Type::Nil,
              "AudioStatus().opening, then AudioPoll() after %d polls: true, \"%s\" (once)", polls,
              str_of(ap, 1).c_str());
    }
    r = L.call("AudioSettings", {Val::number(1), Val::number(1), Val::number(1), Val::number(1), Val::boolean(true),
                                 Val::boolean(true), Val::boolean(false), Val::boolean(true)});
    CHECK(r.size() == 1 && r[0].type == Type::Bool && r[0].b, "AudioSettings(1, 1, 1, 1, true, true, false, true) -> true");
    r = L.call("Create", {Val::number(0), Val::vector(704, 132, -139), Val::number(180)});
    CHECK(r.size() == 1 && r[0].type == Type::Number && r[0].num > 0, "Create(sonic, Vector(704, 132, -139), 180) -> id %g",
          r.empty() ? 0.0 : r[0].num);
    double id = r.empty() ? 0 : r[0].num;
    {
        auto u = L.call("MoverUpdate", {Val::number(5), Val::string("x:crate"), Val::vector(800, 132, -144),
                                        Val::angle(0, 45, 0), Val::boolean(true)});
        auto c = L.call("MoverCommit", {});
        Val ms = L.call("MoverStatus", {})[0];
        CHECK(u.size() == 1 && u[0].b && c.size() == 2 && c[0].num == 1 && ms.tab->field("active").num == 1 &&
                  ms.tab->field("active_tris").num == 12,
              "MoverUpdate(5, \"x:crate\", Vector, Angle, true) + MoverCommit() next to the character: %g in libsa1 "
              "(%g triangles)", c.size() == 2 ? c[0].num : -1.0, ms.tab->field("active_tris").num);
        L.call("MoverUpdate", {Val::number(5), Val::string("x:crate"), Val::vector(800, 132, -144),
                               Val::angle(0, 45, 0), Val::boolean(false)});
        c = L.call("MoverCommit", {});
        CHECK(c.size() == 2 && c[0].num == 0 && c[1].num == 1, "not solid any more: parked (%g active, %g parked)",
              c.size() == 2 ? c[0].num : -1.0, c.size() == 2 ? c[1].num : -1.0);
        L.call("MoverForget", {Val::number(5)});
        L.call("MoverCommit", {});
    }
    Val state_t = Val::table();
    double gen = -1;
    int gens = 0, total_pairs = 0, interpolated = 0, render_ok = 0, audio_ok = 0;
    bool tick_ok = true;
    for (int f = 0; f < 180; f++) {
        bool fwd = f >= 60;
        r = L.call("Tick", {Val::number(id), Val::number(0), Val::number(fwd ? 1 : 0), Val::number(180),
                            Val::number(f >= 120 && f < 130 ? 1 : 0), Val::number(1.0 / 60.0)});
        if (r.size() != 1 || r[0].type != Type::Number) {
            tick_ok = false;
            std::printf("        Tick: %s\n", str_of(r, 1).c_str());
            break;
        }
        total_pairs += (int)r[0].num;
        L.call("GetState", {Val::number(id), state_t});
        auto m = L.call("Render", {Val::number(id), Val::number(-1)});
        if (m.size() == 10 && m[0].type == Type::Number && m[6].type == Type::Bool && m[9].type == Type::Bool) {
            render_ok++;
            if (m[0].num != gen) {
                gen = m[0].num;
                gens++;
            }
            interpolated += m[6].b ? 1 : 0;
        }
        auto a = L.call("AudioUpdate", {Val::vector(704, 300, -100), Val::vector(0, -1, 0), Val::vector(0, 0, 1),
                                        Val::number(1), Val::boolean(false), Val::number(1.0 / 60.0)});
        audio_ok += a.size() == 1 && a[0].type == Type::Number;
    }
    Table &s = *state_t.tab;
    CHECK(tick_ok && total_pairs == 90, "180 frames of 1/60 s: Tick ran %d pairs", total_pairs);
    CHECK(s.field("x").type == Type::Number && s.field("ground").type == Type::Bool && s.field("alpha").num >= 0 &&
              s.field("alpha").num < 1 && s.field("x").num < 600,
          "GetState fills the caller's table: pos (%.1f %.1f %.1f), yaw %.1f, action %g, %s, alpha %.2f",
          s.field("x").num, s.field("y").num, s.field("z").num, s.field("yaw").num, s.field("action").num,
          s.field("ground").b ? "ground" : "air", s.field("alpha").num);
    CHECK(render_ok == 180 && gens >= 80 && interpolated >= 150,
          "Render(id, -1) every frame: 10 results, %d new pairs drawn, interpolated in %d of 180 frames", gens,
          interpolated);
    CHECK(audio_ok == 180, "AudioUpdate(eye, forward, up, volume, paused, dt) -> playing sounds, every frame");
    {
        auto r0 = L.call("Render", {Val::number(id), Val::number(0)});
        auto r1 = L.call("Render", {Val::number(id), Val::number(1)});
        auto rh = L.call("Render", {Val::number(id), Val::number(0.5)});
        bool ok = r0.size() == 10 && r1.size() == 10 && rh.size() == 10;
        double moved = 0, mid_err = 0;
        for (int k = 2; ok && k < 5; k++) {
            moved += (r1[k].num - r0[k].num) * (r1[k].num - r0[k].num);
            mid_err = std::max(mid_err, std::fabs(rh[k].num - 0.5 * (r0[k].num + r1[k].num)));
        }
        CHECK(ok && std::sqrt(moved) > 1.0 && mid_err < 0.05 && rh[7].num == 0.5,
              "Render(alpha 0 / 0.5 / 1) while running: the root moves %.1f HU between the pairs, alpha 0.5 is the "
              "midpoint (error %.3f HU)", std::sqrt(moved), mid_err);
    }
    {
        Val bt = Val::table();
        L.call("Render", {Val::number(id), Val::number(-1)});
        r = L.call("Batches", {Val::number(id), bt});
        double count = r.size() == 1 && r[0].type == Type::Number ? r[0].num : 0;
        bool shapes = count > 0 && bt.tab->field("count").num == count;
        double tris = 0;
        int opaque = 0, palette = 0;
        for (int b = 1; b <= (int)count; b++) {
            Val e = bt.tab->at(b);
            if (e.type != Type::Table) { shapes = false; break; }
            Table &E = *e.tab;
            shapes = shapes && E.field("key").type == Type::String && E.field("tris").num > 0 &&
                     E.field("pass").type == Type::Number && E.field("archive").type == Type::Number &&
                     E.field("tex").type == Type::Number && E.field("src").type == Type::Number &&
                     E.field("dst").type == Type::Number && E.field("wrap").type == Type::Number;
            tris += E.field("tris").num;
            opaque += E.field("pass").num == 0;
            palette += ((uint32_t)E.field("flags").num & 0x20u) != 0;
        }
        CHECK(shapes && tris == bt.tab->field("triangles").num && opaque > 0 && palette > 0,
              "Batches(id, t): %g batches (%d opaque, %d palette-lit), %g triangles", count, opaque, palette, tris);
        r = L.call("PrepareView", {Val::number(id), Val::vector(704, 300, -100), Val::vector(1, 0, 0), Val::vector(0, 0, 1)});
        CHECK(r.size() == 1 && r[0].type == Type::Bool && r[0].b, "PrepareView(id, eye, right, up) -> true");
        g_mesh = MeshRec();
        uint64_t pc0 = L.pcalls, vp0 = L.vectors_pushed;
        bool counts = true;
        // round 4c E1: mesh.Normal only for lit batches (not SA1_DRAW_UNLIT; PrepareView's lit defaults to true),
        // mesh.TexCoord only for textured or sphere-mapped ones
        uint64_t want_nrm = 0, want_tc = 0;
        for (int b = 1; b <= (int)count; b++) {
            uint64_t before = g_mesh.adv;
            auto e = L.call("EmitBatch", {Val::number(id), Val::number(b)});
            Table &E = *bt.tab->at(b).tab;
            double want = 3 * E.field("tris").num;
            uint32_t fl = (uint32_t)E.field("flags").num;
            want_nrm += (fl & SA1_DRAW_UNLIT) ? 0 : (uint64_t)want;
            want_tc += (E.field("archive").num >= 0 || (fl & SA1_DRAW_ENV_MAP)) ? (uint64_t)want : 0;
            counts = counts && e.size() == 1 && e[0].type == Type::Number && e[0].num == want &&
                     (double)(g_mesh.adv - before) == want;
        }
        // (before the extra EmitBatch below)
        const uint64_t e_adv = g_mesh.adv, e_nrm = g_mesh.nrm, e_tc = g_mesh.tc, e_pos = g_mesh.pos, e_col = g_mesh.col,
                       e_calls = L.pcalls - pc0;
        bool finite = g_mesh.adv > 0 && g_mesh.bad == 0;
        float lo[3] = {1e30f, 1e30f, 1e30f}, hi[3] = {-1e30f, -1e30f, -1e30f};
        for (size_t i = 0; i < g_mesh.vp.size(); i++) {
            finite = finite && std::isfinite(g_mesh.vp[i]) && std::isfinite(g_mesh.vn[i]);
            lo[i % 3] = std::min(lo[i % 3], g_mesh.vp[i]);
            hi[i % 3] = std::max(hi[i % 3], g_mesh.vp[i]);
        }
        for (double c : g_mesh.vc) {
            finite = finite && c >= 0 && c <= 255 && c == std::floor(c);
        }
        Val st = L.call("Status", {})[0];
        // the scratch Vectors were made at gmod13_open; EmitBatch pushes none
        uint64_t vp1 = L.vectors_pushed;
        L.call("EmitBatch", {Val::number(id), Val::number(1)});
        uint64_t again = L.vectors_pushed - vp1;
        CHECK(counts && finite && e_pos == e_adv && e_nrm == want_nrm && e_tc == want_tc && e_col == e_adv &&
                  e_calls == 3 * e_adv + want_nrm + want_tc,
              "EmitBatch(id, b) for every batch: %llu vertices through mesh.Position / Color / AdvanceVertex, %llu "
              "mesh.Normal (lit batches: %llu), %llu mesh.TexCoord (textured ones: %llu) (%llu protected calls), extent "
              "%.0f x %.0f x %.0f HU", (unsigned long long)e_adv, (unsigned long long)e_nrm, (unsigned long long)want_nrm,
              (unsigned long long)e_tc, (unsigned long long)want_tc, (unsigned long long)e_calls, hi[0] - lo[0],
              hi[1] - lo[1], hi[2] - lo[2]);
        CHECK(st.type == Type::Table && st.tab->field("vector_mode").num == 1 && vp1 - vp0 == 0 && again == 0,
              "the Vectors for mesh.Position / mesh.Normal are two scratch Vectors written in place (mode %g; %llu "
              "Vectors made by the first frame's batches, %llu by a later batch: both made at gmod13_open)", st.type == Type::Table ? st.tab->field("vector_mode").num : -1.0,
              (unsigned long long)(vp1 - vp0), (unsigned long long)again);
        r = L.call("EmitBatch", {Val::number(id), Val::number(count + 1)});
        CHECK(is_nil_msg(r), "EmitBatch(id, count + 1): nil, \"%s\"", str_of(r, 1).c_str());
        // gsa1_lighting 0 (PrepareView's 8th argument false): no batch gets mesh.Normal
        r = L.call("PrepareView", {Val::number(id), Val::vector(704, 300, -100), Val::vector(1, 0, 0), Val::vector(0, 0, 1),
                                   Val::boolean(false), Val::boolean(true), Val::number(2), Val::boolean(false)});
        g_mesh = MeshRec();
        for (int b = 1; b <= (int)count; b++) {
            L.call("EmitBatch", {Val::number(id), Val::number(b)});
        }
        CHECK(r.size() == 1 && r[0].b && g_mesh.adv > 0 && g_mesh.nrm == 0 && g_mesh.tc == want_tc,
              "PrepareView(..., lit = false) (gsa1_lighting 0): %llu vertices, no mesh.Normal, %llu mesh.TexCoord",
              (unsigned long long)g_mesh.adv, (unsigned long long)g_mesh.tc);
        // round 4c E5: with the screen (fov 90, 3440 x 1440) GetState reports the blended batches' screen coverage
        r = L.call("PrepareView", {Val::number(id), Val::vector(704, 300, -100), Val::vector(1, 0, 0), Val::vector(0, 0, 1),
                                   Val::boolean(false), Val::boolean(true), Val::number(2), Val::boolean(true),
                                   Val::number(92.5), Val::number(3440), Val::number(1440)});
        Val gs = Val::table();
        L.call("GetState", {Val::number(id), gs});
        Table &G = *gs.tab;
        CHECK(r.size() == 1 && r[0].b && G.field("blend_layers").type == Type::Number && G.field("blend_layers").num >= 0 &&
                  G.field("sprite_layers").type == Type::Number && G.field("draws").num > 0 &&
                  G.field("vertices").num == 3 * bt.tab->field("triangles").num && G.field("blended").type == Type::Number &&
                  G.field("sprite_batches").type == Type::Number && G.field("sprites").type == Type::Number &&
                  G.field("lines").type == Type::Number && G.field("mesh_calls").num > 0 &&
                  G.field("sprite_max").type == Type::Number && G.field("render_flags").type == Type::Number &&
                  G.field("drawn_root").type == Type::Bool,
              "GetState: draws %g, sprites %g, lines %g, blended batches %g, sprite batches %g, vertices %g, mesh calls "
              "%g, widest sprite %g HU, blended coverage %.4f screens, render flags %g (drawn root: %s)",
              G.field("draws").num, G.field("sprites").num, G.field("lines").num, G.field("blended").num,
              G.field("sprite_batches").num, G.field("vertices").num, G.field("mesh_calls").num, G.field("sprite_max").num,
              G.field("blend_layers").num, G.field("render_flags").num, G.field("drawn_root").b ? "yes" : "no");
        Val stt = L.call("Status", {})[0];
        CHECK(stt.tab->field("build").type == Type::String && !stt.tab->field("build").str.empty() &&
                  stt.tab->field("mesh_saved").type == Type::Number,
              "Status(): build \"%s\", %g mesh calls saved", stt.tab->field("build").str.c_str(),
              stt.tab->field("mesh_saved").num);
    }
    {
        r = L.call("TextureArchives", {Val::number(0)});
        size_t na = r.size() == 1 && r[0].type == Type::Table ? r[0].tab->n.size() : 0;
        std::string a1 = na >= 2 ? r[0].tab->at(2).tab->field("name").str : "";
        CHECK(na >= 2, "TextureArchives(sonic): %u archives (archive 1: %s)", (unsigned)na, a1.c_str());
        // the run string, decoded as the addon paints it, is the decoded texture exactly
        int checked = 0, wrong = 0;
        for (int archive = 0; archive < 2; archive++) {
            auto t = L.call("Texture", {Val::number(0), Val::number(0), Val::number(archive)});
            if (t.size() != 1 || t[0].type != Type::Table) { wrong++; continue; }
            Table &T = *t[0].tab;
            int w = (int)T.field("w").num, h = (int)T.field("h").num;
            std::vector<uint8_t> img((size_t)w * h * 4, 0);
            const std::string &runs = T.field("runs").str;
            for (size_t o = 0; o + 10 <= runs.size(); o += 10) {
                const uint8_t *q = (const uint8_t *)runs.data() + o;
                int x = q[0] | (q[1] << 8), y = q[2] | (q[3] << 8), len = q[4] | (q[5] << 8);
                for (int k = 0; k < len && x + k < w && y < h; k++) {
                    std::memcpy(&img[((size_t)y * w + x + k) * 4], q + 6, 4);
                }
            }
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    auto px = L.call("TexturePixel", {Val::number(0), Val::number(archive), Val::number(0), Val::number(x), Val::number(y)});
                    checked++;
                    bool same = px.size() == 4;
                    for (int k = 0; same && k < 4; k++) {
                        same = px[(size_t)k].num == img[((size_t)y * w + x) * 4 + (size_t)k];
                    }
                    wrong += !same;
                }
            }
        }
        CHECK(checked > 0 && wrong == 0, "Texture(sonic, 0, archive 0 / 1): the runs paint exactly the decoded texels "
              "(TexturePixel, %d texels, %d different)", checked, wrong);
        r = L.call("TexturePixel", {Val::number(0), Val::number(0), Val::number(0), Val::number(5000), Val::number(0)});
        CHECK(r.size() == 1 && r[0].type == Type::Nil, "TexturePixel outside the texture -> nil");
    }
    {
        r = L.call("AudioStatus", {});
        Table *A = r.size() == 1 && r[0].type == Type::Table ? r[0].tab.get() : nullptr;
        CHECK(A && A->field("open").b && A->field("events").num > 0 && !A->field("output").b,
              "AudioStatus(): open, %g sound events reached the mixer; output %s (\"%s\": no Garry's Mod BASS in this "
              "process)", A ? A->field("events").num : 0.0, A && A->field("output").b ? "running" : "not running",
              A ? A->field("error").str.c_str() : "");
    }
    r = L.call("PollEvents", {});
    CHECK(r.size() == 1 && r[0].type == Type::Table, "PollEvents() -> %u events", r.empty() || r[0].type != Type::Table ? 0u : (unsigned)r[0].tab->n.size());
    {
        // 0.6.0: PollEvents(out) fills the caller's table and reuses its event tables (no garbage per frame)
        Val ev = Val::table();
        int seen = 0, reused = 0, ends = 0, frames = 0;
        std::shared_ptr<Table> first;
        for (int f = 0; f < 90; f++) {
            L.call("Tick", {Val::number(id), Val::number(0), Val::number(1), Val::number(180), Val::number(f % 30 == 0 ? 1 : 0),
                            Val::number(1.0 / 60.0)});
            auto pr = L.call("PollEvents", {ev});
            if (pr.size() != 1 || pr[0].tab != ev.tab) break;
            frames++;
            int n = (int)ev.tab->field("count").num;
            ends += ev.tab->at(n + 1).type == Type::Nil;
            if (n > 0) {
                seen += n;
                if (first && ev.tab->at(1).tab == first) reused++;
                first = ev.tab->at(1).tab;
            }
        }
        CHECK(frames == 90 && ends == 90 && seen > 0 && reused > 0,
              "PollEvents(out) for 90 frames: the caller's table every time, %d events, out[count + 1] nil each time, "
              "event tables reused %d times", seen, reused);
    }
    r = L.call("PollLog", {});
    bool clean = r.size() == 1 && r[0].type == Type::Table;
    for (auto &kv : clean ? r[0].tab->n : std::map<double, Val>()) {
        clean = clean && kv.second.str.find(gsa1::parent_dir(gdi)) == std::string::npos;
    }
    CHECK(clean, "PollLog() lines never contain the disc directory");
    r = L.call("Destroy", {Val::number(id)});
    CHECK(r.size() == 1 && r[0].b, "Destroy(id) -> true");
    {
        // the game's own rumble (Knuckles' punch: power 3, 15 frames) reaches the controller through PollEvents
        Table &O = *pad_out.tab;
        auto padpoll = [&]() { L.call("PadPoll", {Val::number(1.0 / 60.0), Val::boolean(false), pad_out}); };
        g_fake_pad->set(1, gsa1::PAD_B);        // the controller is in use
        padpoll();
        r = L.call("Create", {Val::number(3), Val::vector(704, 132, -139), Val::number(180)});
        double kid = r.size() == 1 && r[0].type == Type::Number ? r[0].num : 0;
        int rumbles = 0;
        unsigned max_lo = 0;
        for (int f = 0; f < 300 && kid > 0; f++) {
            int b = (f >= 60 && (f % 30) < 4) ? 2 : 0;
            L.call("Tick", {Val::number(kid), Val::number(0), Val::number(0), Val::number(180), Val::number(b),
                            Val::number(1.0 / 60.0)});
            auto ev = L.call("PollEvents", {});
            for (auto &kv : ev.size() == 1 && ev[0].type == Type::Table ? ev[0].tab->n : std::map<double, Val>()) {
                if (kv.second.type == Type::Table && kv.second.tab->field("type").num == SA1_EVENT_RUMBLE) {
                    rumbles++;
                }
            }
            max_lo = std::max(max_lo, (unsigned)g_fake_pad->vib_low[1]);
            padpoll();
        }
        CHECK(kid > 0 && rumbles > 0 && max_lo > 0 && O.field("connected").b,
              "Knuckles punching: %d rumble events from the game drove controller 2's low motor (up to %u)", rumbles,
              max_lo);
        if (kid > 0) {
            L.call("Destroy", {Val::number(kid)});
        }
    }
    {
        // upgrades: the table, Create with the names, the equipment the game derived from them, refusals
        r = L.call("Upgrades", {});
        size_t all = r.size() == 1 && r[0].type == Type::Table ? r[0].tab->n.size() : 0;
        r = L.call("Upgrades", {Val::number(3)});
        bool knux = r.size() == 1 && r[0].type == Type::Table && r[0].tab->n.size() == 2 &&
                    r[0].tab->at(1).type == Type::Table && r[0].tab->at(1).tab->field("name").str == "shovel_claw" &&
                    r[0].tab->at(1).tab->field("bit").num == 0x40 && r[0].tab->at(2).tab->field("flag").num == 0x11A;
        CHECK(all == 17 && knux, "Upgrades(): %u upgrades; Upgrades(knuckles): shovel_claw (bit 0x40), "
              "fighting_gloves (flag 0x11A)", (unsigned)all);
        Val names = Val::table();
        names.tab->set(Val::number(1), Val::string("shovel_claw"));
        names.tab->set(Val::number(2), Val::string("fighting_gloves"));
        r = L.call("Create", {Val::number(3), Val::vector(704, 132, -139), Val::number(180), names});
        double uid = r.size() == 1 && r[0].type == Type::Number ? r[0].num : 0;
        Val us = Val::table();
        for (int f = 0; f < 20 && uid > 0; f++) {
            L.call("Tick", {Val::number(uid), Val::number(0), Val::number(0), Val::number(180), Val::number(0),
                            Val::number(1.0 / 60.0)});
        }
        L.call("GetState", {Val::number(uid), us});
        CHECK(uid > 0 && us.tab->field("equipment").num == 0x60 && us.tab->field("upgrades").num == 2 &&
                  us.tab->field("upgrades_ok").b,
              "Create(knuckles, pos, 180, {\"shovel_claw\", \"fighting_gloves\"}): equipment 0x%X after the first "
              "steps (wants 0x60)", (unsigned)us.tab->field("equipment").num);
        if (uid > 0) {
            L.call("Destroy", {Val::number(uid)});
        }
        int refused = 0;
        Val other = Val::table();
        other.tab->set(Val::number(1), Val::string("light_speed_shoes"));
        r = L.call("Create", {Val::number(3), Val::vector(704, 132, -139), Val::number(180), other});
        refused += is_nil_msg(r) && str_of(r, 2) == "bad_upgrade";
        Val number = Val::table();
        number.tab->set(Val::number(1), Val::number(0x119));
        r = L.call("Create", {Val::number(3), Val::vector(704, 132, -139), Val::number(180), number});
        refused += is_nil_msg(r);
        r = L.call("Create", {Val::number(3), Val::vector(704, 132, -139), Val::number(180), Val::string("shovel_claw")});
        refused += is_nil_msg(r);
        Val many = Val::table();
        for (int k = 1; k <= 40; k++) many.tab->set(Val::number(k), Val::string("shovel_claw"));
        r = L.call("Create", {Val::number(3), Val::vector(704, 132, -139), Val::number(180), many});
        refused += is_nil_msg(r);
        CHECK(refused == 4, "%d of 4 bad upgrade lists refused (another character's, a number, a string, 40 names)",
              refused);
    }
    {
        // round 4c E1 on the Light Speed aura: Sonic with the Light Speed Shoes and the Crystal Ring holds action until
        // the charge completes; the aura is untextured and unlit (additive), so its vertices get neither mesh.Normal
        // nor mesh.TexCoord
        Val names = Val::table();
        names.tab->set(Val::number(1), Val::string("light_speed_shoes"));
        names.tab->set(Val::number(2), Val::string("crystal_ring"));
        r = L.call("Create", {Val::number(0), Val::vector(704, 132, -139), Val::number(180), names});
        double sid = r.size() == 1 && r[0].type == Type::Number ? r[0].num : 0;
        for (int f = 0; f < 260 && sid > 0; f++) {   // lands first; the charge starts with the press on the ground
            L.call("Tick", {Val::number(sid), Val::number(0), Val::number(0), Val::number(180),
                            Val::number(f >= 60 ? 2 : 0), Val::number(1.0 / 60.0)});
        }
        Val bt = Val::table();
        L.call("Render", {Val::number(sid), Val::number(-1)});
        auto bc = L.call("Batches", {Val::number(sid), bt});
        L.call("PrepareView", {Val::number(sid), Val::vector(704, 300, -100), Val::vector(1, 0, 0), Val::vector(0, 0, 1)});
        int count = bc.size() == 1 && bc[0].type == Type::Number ? (int)bc[0].num : 0;
        uint64_t aura_v = 0, aura_n = 0, aura_t = 0, all_v = 0, all_calls = 0, old_calls = 0;
        uint64_t pc0 = L.pcalls;
        for (int b = 1; b <= count; b++) {
            Table &E = *bt.tab->at(b).tab;
            g_mesh = MeshRec();
            L.call("EmitBatch", {Val::number(sid), Val::number(b)});
            all_v += g_mesh.adv;
            uint32_t fl = (uint32_t)E.field("flags").num;
            if (E.field("archive").num < 0 && (fl & SA1_DRAW_UNLIT) && (fl & SA1_DRAW_ADDITIVE)) {
                aura_v += g_mesh.adv;
                aura_n += g_mesh.nrm;
                aura_t += g_mesh.tc;
            }
        }
        all_calls = L.pcalls - pc0;
        old_calls = 5 * all_v;
        CHECK(sid > 0 && aura_v >= 2000 && aura_n == 0 && aura_t == 0,
              "the charged Light Speed aura (untextured, unlit, additive): %llu vertices with 0 mesh.Normal and 0 "
              "mesh.TexCoord; the whole charged frame %llu mesh calls instead of %llu (%.1f %% fewer)",
              (unsigned long long)aura_v, (unsigned long long)all_calls, (unsigned long long)old_calls,
              old_calls ? 100.0 * (double)(old_calls - all_calls) / (double)old_calls : 0.0);
        if (sid > 0) {
            L.call("Destroy", {Val::number(sid)});
        }
    }
    test_092(L, g);
    r = L.call("Shutdown", {});
    CHECK(r.empty(), "Shutdown()");
    // the game's thread: the addon's frames, every call timed (0.5.1)
    game_thread_timing(L, map, gsa1::base_name(bsp).c_str());
    if (!timing_bsp.empty()) {
        std::string big;
        if (gsa1::read_small_file(timing_bsp, 1024u << 20, big, err) && big.size() > 1036) {
            game_thread_timing(L, big, gsa1::base_name(timing_bsp).c_str());
        } else {
            CHECK(false, "--timing-bsp %s: %s", timing_bsp.c_str(), err.c_str());
        }
    }
    L.call("PadRumble", {Val::number(1), Val::number(1), Val::number(2)});
    bool shaking = g_fake_pad->vib_low[1] > 0;
    gmod13_close(&state);
    CHECK(L.globals.tab->field("gsa1").type == Type::Nil && L.st.empty(), "gmod13_close removes the gsa1 table");
    CHECK(shaking && g_fake_pad->vib_low[1] == 0, "gmod13_close stops the controller's motors");
    test_features_closed(true);
    std::remove(gsa1::join_path(cfgdir, "config.txt").c_str());
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
