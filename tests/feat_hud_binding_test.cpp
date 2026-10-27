// feat_hud_binding_test: the HUD feature's binding test (round 0.9.1; src/module/bind_hud.cpp, sadc
// docs/research/gsa1_070_hud.md F8). Linked like binding_test (the module's objects, libsa1, the mock Lua stack of
// tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi when one is given.
//
//   feat_hud_binding_test [--gdi GAME.gdi]
//
// Without the disc: gsa1.FEATURES.hud = 1, its 4 functions, gsa1.HUD (the parts against libsa1.h, the strides), no
// FEATURE_ERRORS; bad arguments come back as nil + message (no Lua error).
// With the disc (through the module's session, on a floor; the characters' worlds tick through gsa1.Tick):
//   * Sonic with every part and the clock: HudScreen gives the game's 15 sprites (the TIME label / ring icon and 3 ring
//     digits, the life icon and 2 lives digits, 8 timer digits) at the game's places (gsa1_070_hud.md 2 C), every one
//     blended SRC_ALPHA / INV_SRC_ALPHA with a CON_REGULAR texture whose name gsa1.Texture knows; the time runs
//     (HudCounters); unchanged without a tick (changed false), again with force;
//   * the parts: rings + lives 7 (the label cropped to the ring icon), lives + time 11, rings + time 12, time 8, none 0;
//   * HudSetTime 1:23:45 shows in HudCounters after a pair;
//   * E-102: the time held at 3:00:00 with e102_no_limit 1 (clock_running false), counting down with 0; 00:00:00 set on
//     him gives 3:00:00 (no time-up loop);
//   * Big: his own HUD (the task 8C0EB160) as CHARACTER draws, with FISHING and CON_REGULAR textures; Tails, Knuckles and
//     Amy: the common HUD with their own life icons.
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
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"

namespace {

const int DS = 11, SS = 15, VS = 8;

struct Spr {
    double x, y, w, h;      // top-left (pivot + rect x0 / y0) and size on the 640 x 480 screen
    int draw;               // its draw (0-based)
};

struct Screen {
    double gen = -1;
    bool changed = false;
    int nd = 0, ns = 0, nv = 0;
    Val out = Val::table();
    std::vector<Spr> spr;
};

double num(const Val &t, double i)
{
    Val v = t.tab->at(i);
    return v.type == Type::Number ? v.num : -1e30;
}

// HudScreen(id, out [, force]) into s (the out table kept across calls)
bool screen(MockLua &L, double id, Screen &s, bool force = false)
{
    std::vector<Val> args = {Val::number(id), s.out};
    if (force) args.push_back(Val::boolean(true));
    std::vector<Val> r = L.call("HudScreen", args);
    if (r.size() != 2 || r[0].type != Type::Number || r[1].type != Type::Bool) {
        return false;
    }
    s.gen = r[0].num;
    s.changed = r[1].b;
    s.nd = (int)s.out.tab->field("nd").num;
    s.ns = (int)s.out.tab->field("ns").num;
    s.nv = (int)s.out.tab->field("nv").num;
    s.spr.clear();
    Val d = s.out.tab->field("d"), sp = s.out.tab->field("s");
    if (d.type != Type::Table || sp.type != Type::Table) {
        return s.nd == 0;
    }
    for (int i = 0; i < s.nd; i++) {
        int prim = (int)num(d, i * DS + 1), first = (int)num(d, i * DS + 2), count = (int)num(d, i * DS + 3);
        if (prim != 1) continue;
        for (int j = first; j < first + count; j++) {
            double x0 = num(sp, j * SS + 1), y0 = num(sp, j * SS + 2), x1 = num(sp, j * SS + 3), y1 = num(sp, j * SS + 4);
            double px = num(sp, j * SS + 5), py = num(sp, j * SS + 6);
            s.spr.push_back({px + x0, py + y0, x1 - x0, y1 - y0, i});
        }
    }
    return true;
}

bool has_sprite(const Screen &s, double x, double y, double w = -1)
{
    for (const Spr &p : s.spr) {
        if (std::fabs(p.x - x) < 0.6 && std::fabs(p.y - y) < 0.6 && (w < 0 || std::fabs(p.w - w) < 0.6)) return true;
    }
    return false;
}

void tick(MockLua &L, double id, int frames)
{
    for (int f = 0; f < frames; f++) {
        L.call("Tick", {Val::number(id), Val::number(0), Val::number(0), Val::number(0), Val::number(0),
                        Val::number(1.0 / 60.0)});
    }
}

// HudCounters -> total frames (minutes * 3600 + seconds * 60 + frames), running; -1 when it failed
double counters(MockLua &L, double id, bool *running = nullptr, double *mm = nullptr)
{
    std::vector<Val> r = L.call("HudCounters", {Val::number(id)});
    if (r.size() != 7 || r[0].type != Type::Number) return -1;
    if (running) *running = r[3].type == Type::Bool && r[3].b;
    if (mm) *mm = r[0].num;
    return r[0].num * 3600 + r[1].num * 60 + r[2].num;
}

bool settings(MockLua &L, double id, int parts, int clock, int free)
{
    std::vector<Val> r = L.call("HudSettings", {Val::number(id), Val::number(parts), Val::number(clock),
                                                Val::number(free)});
    return r.size() == 1 && r[0].type == Type::Bool && r[0].b;
}

// the name of archive a of a kind (gsa1.TextureArchives)
std::string archive_name(MockLua &L, int kind, int a)
{
    std::vector<Val> r = L.call("TextureArchives", {Val::number(kind)});
    if (r.empty() || r[0].type != Type::Table) return "";
    Val e = r[0].tab->at(a + 1);
    return e.type == Type::Table ? e.tab->field("name").str : "";
}

std::string texture_name(MockLua &L, int kind, int a, int t)
{
    std::vector<Val> r = L.call("Texture", {Val::number(kind), Val::number(t), Val::number(a)});
    return !r.empty() && r[0].type == Type::Table ? r[0].tab->field("name").str : "";
}

}  // namespace

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::printf("G-SA1 feat_hud_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_hud_appdata");
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
    Val errs = g.type == Type::Table ? g.tab->field("FEATURE_ERRORS") : Val();
    Val hud = g.type == Type::Table ? g.tab->field("HUD") : Val();
    int fns = 0;
    for (const char *n : {"HudSettings", "HudSetTime", "HudCounters", "HudScreen"}) {
        fns += g.type == Type::Table && g.tab->field(n).type == Type::Function;
    }
    bool consts = hud.type == Type::Table && hud.tab->field("RINGS").num == SA1_HUD_RINGS &&
                  hud.tab->field("LIVES").num == SA1_HUD_LIVES && hud.tab->field("TIME").num == SA1_HUD_TIME &&
                  hud.tab->field("CHARACTER").num == SA1_HUD_CHARACTER && hud.tab->field("ALL").num == SA1_HUD_ALL &&
                  hud.tab->field("D").num == DS && hud.tab->field("S").num == SS && hud.tab->field("V").num == VS;
    CHECK(g.type == Type::Table && feats.type == Type::Table && feats.tab->field("hud").num == 1 && fns == 4 && consts &&
              errs.type == Type::Table && errs.tab->n.empty() && L.st.empty(),
          "gsa1.FEATURES.hud = %g, %d of its 4 functions, gsa1.HUD = {RINGS 1, LIVES 2, TIME 4, CHARACTER 8, ALL 15, D 11, "
          "S 15, V 8} %s, no FEATURE_ERRORS",
          feats.type == Type::Table ? feats.tab->field("hud").num : -1.0, fns, consts ? "as libsa1.h" : "WRONG");
    if (g.type != Type::Table) return 1;
    int bad = 0;
    bad += is_nil_msg(L.call("HudSettings", {}));
    bad += is_nil_msg(L.call("HudSettings", {Val::number(77), Val::number(15), Val::number(1), Val::number(1)}));
    bad += is_nil_msg(L.call("HudSetTime", {Val::string("1"), Val::number(0), Val::number(0), Val::number(0)}));
    bad += is_nil_msg(L.call("HudScreen", {Val::number(1)}));
    bad += is_nil_msg(L.call("HudScreen", {Val::number(77), Val::table()}));
    std::vector<Val> rc = L.call("HudCounters", {Val::number(77)});
    bool counters_nil = rc.size() == 1 && rc[0].type == Type::Nil;
    CHECK(bad == 5 && counters_nil && L.st.empty(), "bad arguments (no arguments, no such character, a string id, no out "
          "table): %d of 5 answered with nil + message; HudCounters of no character: nil; no Lua error", bad);

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the screen checks need the disc\n");
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
    const float X = 0.0f, Y = 0.0f, Z = 0.0f;
    std::vector<sa1_collision_tri> floor;
    for (int i = -2; i < 2; i++) {
        for (int j = -2; j < 2; j++) {
            float x0 = X + 512.0f * i, y0 = Y + 512.0f * j, x1 = x0 + 512.0f, y1 = y0 + 512.0f;
            sa1_collision_tri a = {{{x0, y0, Z}, {x1, y0, Z}, {x1, y1, Z}}, SA1_SURFACE_SOLID};
            sa1_collision_tri b = {{{x0, y0, Z}, {x1, y1, Z}, {x0, y1, Z}}, SA1_SURFACE_SOLID};
            floor.push_back(a);
            floor.push_back(b);
        }
    }
    bool world = st == "ready" && se && se->set_world(floor, err);
    CHECK(world, "the disc (%s) and a floor through the module's session%s%s", st.c_str(), err.empty() ? "" : ": ",
          err.c_str());
    if (!world) {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    const float spawn[3] = {X + 13.7f, Y + 7.3f, Z + 8.0f};

    // ---- Sonic: every part, the clock running ----
    double id = se->create(SA1_CHAR_SONIC, spawn, 0.0f, err);
    bool set_ok = id > 0 && settings(L, id, SA1_HUD_ALL, 1, 1);
    tick(L, id, 48);
    Screen s;
    bool got = screen(L, id, s);
    int con = -1, blended = 0, named = 0;
    std::string cname, label_name;
    Val d = s.out.tab->field("d");
    for (int i = 0; got && i < s.nd; i++) {
        int a = (int)num(d, i * DS + 4), t = (int)num(d, i * DS + 5), fl = (int)num(d, i * DS + 6);
        if (con < 0) {
            con = a;
            cname = archive_name(L, SA1_CHAR_SONIC, a);
        }
        if (a != con) con = -2;
        blended += (fl & SA1_DRAW_BLEND) && num(d, i * DS + 7) == SA1_BLEND_SRC_ALPHA &&
                   num(d, i * DS + 8) == SA1_BLEND_INV_SRC_ALPHA;
        std::string tn = texture_name(L, SA1_CHAR_SONIC, a, t);
        named += !tn.empty();
        if (t == 11) label_name = tn;
    }
    bool places = has_sprite(s, 16, 32, 64) && has_sprite(s, 46, 52) && has_sprite(s, 62, 52) && has_sprite(s, 78, 52) &&
                  has_sprite(s, 16, 400, 32) && has_sprite(s, 49, 416) && has_sprite(s, 65, 416);
    for (int k = 0; k < 8; k++) places = places && has_sprite(s, 64 + 16 * k, 33);
    CHECK(set_ok && got && s.changed && s.ns == 15 && s.nv == 0 && places,
          "Sonic, every part: HudScreen gen %g (changed), %d draws, %d sprites at the game's places (TIME / ring icon "
          "(16, 32) 64 wide, ring digits (46/62/78, 52), life icon (16, 400) 32 wide, lives (49/65, 416), timer digits "
          "(64 + 16k, 33)): %s", s.gen, s.nd, s.ns, places ? "yes" : "NO");
    CHECK(cname == "CON_REGULAR" && blended == s.nd && named == s.nd && s.nd > 0,
          "every draw: archive %d \"%s\", blended SRC_ALPHA / INV_SRC_ALPHA (%d of %d), a texture gsa1.Texture knows (%d; "
          "cell 11 \"%s\")", con, cname.c_str(), blended, s.nd, named, label_name.c_str());
    bool run1 = false;
    double t1 = counters(L, id, &run1);
    double gen1 = s.gen;
    screen(L, id, s);
    bool same = !s.changed && s.gen == gen1;
    screen(L, id, s, true);
    bool forced = s.changed && s.ns == 15;
    tick(L, id, 30);
    double t2 = counters(L, id);
    CHECK(run1 && t1 > 0 && t2 >= t1 + 25 && same && forced,
          "the time runs (HudCounters: %g then %g frames after 30 more), clock_running; no tick: unchanged (gen %g); force: "
          "copied again", t1, t2, gen1);
    struct MaskCase {
        int parts, sprites;
        const char *what;
    } masks[] = {{SA1_HUD_RINGS | SA1_HUD_LIVES, 7, "rings + lives (the label cropped to the ring icon)"},
                 {SA1_HUD_LIVES | SA1_HUD_TIME, 11, "lives + time"},
                 {SA1_HUD_RINGS | SA1_HUD_TIME, 12, "rings + time"},
                 {SA1_HUD_TIME, 8, "time"},
                 {0, 0, "none"}};
    std::string mask_line;
    int mask_ok = 0;
    for (const MaskCase &mc : masks) {
        settings(L, id, mc.parts, 1, 1);
        tick(L, id, 2);
        screen(L, id, s);
        mask_ok += s.ns == mc.sprites;
        mask_line += gsa1::format("%s%s %d", mask_line.empty() ? "" : ", ", mc.what, s.ns);
        if (mc.parts == (SA1_HUD_RINGS | SA1_HUD_LIVES)) {
            mask_line += has_sprite(s, 16, 49, 64) ? " (ring icon at (16, 49))" : " (NO ring icon at (16, 49))";
        }
    }
    CHECK(mask_ok == 5, "the parts: %s", mask_line.c_str());
    settings(L, id, SA1_HUD_ALL, 1, 1);
    std::vector<Val> rt = L.call("HudSetTime", {Val::number(id), Val::number(1), Val::number(23), Val::number(45)});
    tick(L, id, 2);
    double mm = -1;
    double t3 = counters(L, id, nullptr, &mm);
    CHECK(rt.size() == 1 && rt[0].b && mm == 1 && t3 >= 1 * 3600 + 23 * 60 + 45 && t3 < 1 * 3600 + 23 * 60 + 52,
          "HudSetTime 1:23:45: HudCounters %02d:%02d:%02d after a pair", (int)(t3 / 3600), (int)std::fmod(t3 / 60, 60),
          (int)std::fmod(t3, 60));
    se->destroy((int32_t)id);

    // ---- E-102: the time limit held, and the game's rule ----
    double e = se->create(SA1_CHAR_GAMMA, spawn, 0.0f, err);
    settings(L, e, SA1_HUD_ALL, 1, 1);
    tick(L, e, 60);
    bool erun = true;
    double et1 = counters(L, e, &erun);
    screen(L, e, s);
    int e_sprites = s.ns;
    settings(L, e, SA1_HUD_ALL, 1, 0);
    tick(L, e, 60);
    bool erun2 = false;
    double et2 = counters(L, e, &erun2);
    L.call("HudSetTime", {Val::number(e), Val::number(0), Val::number(0), Val::number(0)});
    tick(L, e, 2);
    double et3 = counters(L, e);
    CHECK(e > 0 && et1 == 3 * 3600 && !erun && e_sprites == 15 && et2 < 3 * 3600 && et2 > 3 * 3600 - 70 && erun2 &&
              et3 > 3 * 3600 - 10 && et3 <= 3 * 3600,
          "E-102: no limit: the time held at %g frames (3:00:00; clock_running %s), %d sprites; the game's rule: counting "
          "down (%g after 60 frames); 00:00:00 set: %g (3:00:00, the game's restart time)", et1, erun ? "true" : "false",
          e_sprites, et2, et3);
    se->destroy((int32_t)e);

    // ---- Big: his own HUD task; the others: the common HUD with their icons ----
    double b = se->create(SA1_CHAR_BIG, spawn, 0.0f, err);
    settings(L, b, SA1_HUD_ALL, 1, 1);
    tick(L, b, 48);
    screen(L, b, s);
    int big_char = 0, fishing = 0, big_con = 0, common = 0;
    d = s.out.tab->field("d");
    for (int i = 0; i < s.nd; i++) {
        int part = (int)num(d, i * DS + 10);
        double src = num(d, i * DS + 11);
        std::string an = archive_name(L, SA1_CHAR_BIG, (int)num(d, i * DS + 4));
        if (part == SA1_HUD_CHARACTER && src == (double)0x8C0EB160u) {
            big_char += (int)num(d, i * DS + 3);
            fishing += an == "FISHING";
            big_con += an == "CON_REGULAR";
        } else if (part != SA1_HUD_CHARACTER) {
            common++;
        }
    }
    CHECK(b > 0 && big_char > 0 && fishing > 0 && big_con > 0 && common == 0,
          "Big: %d sprites of his HUD task 8C0EB160 (CHARACTER; draws with FISHING %d, CON_REGULAR %d), %d common-HUD draws "
          "(the game's 8C08A4BA / 8C08A724 skip him)", big_char, fishing, big_con, common);
    se->destroy((int32_t)b);
    struct KindCase {
        int kind;
        const char *name;
        int icon;
    } kinds[] = {{SA1_CHAR_TAILS, "Tails", 14}, {SA1_CHAR_KNUCKLES, "Knuckles", 15}, {SA1_CHAR_AMY, "Amy", 17}};
    for (const KindCase &kc : kinds) {
        double c = se->create(kc.kind, spawn, 0.0f, err);
        settings(L, c, SA1_HUD_ALL, 1, 1);
        tick(L, c, 24);
        screen(L, c, s);
        int icon = -1;
        d = s.out.tab->field("d");
        Val sp = s.out.tab->field("s");
        for (int i = 0; i < s.nd; i++) {
            int first = (int)num(d, i * DS + 2), count = (int)num(d, i * DS + 3);
            for (int j = first; j < first + count; j++) {
                if (std::fabs(num(sp, j * SS + 5) - 16) < 0.6 && std::fabs(num(sp, j * SS + 6) - 400) < 0.6) {
                    icon = (int)num(d, i * DS + 5);
                }
            }
        }
        CHECK(c > 0 && s.ns >= 15 && icon == kc.icon, "%s: %d sprites, the life icon is CON_REGULAR cell %d (the game's %d)",
              kc.name, s.ns, icon, kc.icon);
        se->destroy((int32_t)c);
    }
    CHECK(L.st.empty(), "the Lua stack is balanced (%d left)", (int)L.st.size());
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
