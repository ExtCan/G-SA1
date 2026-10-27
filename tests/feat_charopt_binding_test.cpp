// feat_charopt_binding_test: round 0.9.1's character features through the module's Lua functions - "charopt"
// (src/module/bind_charopt.cpp: lives, Amy's bird, Tails' tail blend, holding the air timer) and "musicstate"
// (src/module/bind_musicstate.cpp: the game's music state in the mixer, libsa1 audio header 4). Linked like binding_test
// (the module's objects, libsa1, the mock Lua stack of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi.
//
//   feat_charopt_binding_test [--gdi GAME.gdi]
//
// Without the disc: gsa1.FEATURES.charopt = 1 and .musicstate = 1, the functions registered, gsa1.CHAROPT and
// gsa1.MUSIC_STATE hold libsa1's numbers; bad arguments come back as nil + message (no Lua error); AudioMusicState
// without the sound banks says "not_open".
// With the disc, through the module's session (a solid floor with a closed water box 150 SA1 units (600 HU) deep over
// part of it, the sound banks open):
//   * drowning (sadc docs/research/gsa1_070_drown.md J1's end-to-end case): Sonic standing on the floor under water -
//     AudioMusicState().jingle 96 (kind COUNTDOWN, name TIMER.ADX) from the countdown's JINGLE event (step 1082), then
//     at the drown (step 1862) jingle -1, stopped true, last_end STOP, with SA1_EVENT_DEATH cause DROWN (3) in that step
//     and SA1_EVENT_RESTART (id 2) 240 steps later; after it the game's music back (stopped false);
//   * AudioMusicEnd ends a playing countdown jingle (last_end HOST) and the music stop;
//   * "Characters can drown" off: HoldAir before every pair keeps the air timer under 3 and no countdown comes in
//     1300 pairs (the game's own countdown would start at 1080 steps);
//   * lives: SetLives 2 -> GetLives 2 before and after ticks, 500 -> 127; a puppet-free unknown id -> nil + message;
//   * Amy's bird (gsa1_070_bird.md F4): SetCompanion(Amy, BIRD, true) -> the bird's task in her world (Companion
//     true) and its draws in her batches (archive 0, textures 44-52); false -> gone after a pair; Sonic -> refused;
//   * Tails' tail blend: SetGameOption(Tails, TAILS_SNAP_TAILS, 1 / 0) accepted.
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

// a quad as two triangles whose normal (right-hand winding) points along n
void quad(std::vector<sa1_collision_tri> &out, const float p[4][3], const float n[3], uint32_t surface)
{
    float e1[3], e2[3], c[3];
    for (int k = 0; k < 3; k++) {
        e1[k] = p[1][k] - p[0][k];
        e2[k] = p[2][k] - p[0][k];
    }
    c[0] = e1[1] * e2[2] - e1[2] * e2[1];
    c[1] = e1[2] * e2[0] - e1[0] * e2[2];
    c[2] = e1[0] * e2[1] - e1[1] * e2[0];
    bool same = c[0] * n[0] + c[1] * n[1] + c[2] * n[2] >= 0.0f;
    sa1_collision_tri a, b;
    std::memset(&a, 0, sizeof a);
    std::memset(&b, 0, sizeof b);
    const int ia[3] = {0, same ? 1 : 2, same ? 2 : 1}, ib[3] = {0, same ? 2 : 3, same ? 3 : 2};
    for (int v = 0; v < 3; v++) {
        std::memcpy(a.v[v], p[ia[v]], 12);
        std::memcpy(b.v[v], p[ib[v]], 12);
    }
    a.surface = b.surface = surface;
    out.push_back(a);
    out.push_back(b);
}

// a closed box (host space, z up) with outward faces
void box(std::vector<sa1_collision_tri> &out, float x0, float x1, float y0, float y1, float z0, float z1, uint32_t s)
{
    const float top[4][3] = {{x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1}};
    const float bot[4][3] = {{x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0}};
    const float wx0[4][3] = {{x0, y0, z0}, {x0, y1, z0}, {x0, y1, z1}, {x0, y0, z1}};
    const float wx1[4][3] = {{x1, y0, z0}, {x1, y1, z0}, {x1, y1, z1}, {x1, y0, z1}};
    const float wy0[4][3] = {{x0, y0, z0}, {x1, y0, z0}, {x1, y0, z1}, {x0, y0, z1}};
    const float wy1[4][3] = {{x0, y1, z0}, {x1, y1, z0}, {x1, y1, z1}, {x0, y1, z1}};
    const float up[3] = {0, 0, 1}, down[3] = {0, 0, -1}, mx[3] = {-1, 0, 0}, px[3] = {1, 0, 0}, my[3] = {0, -1, 0},
                py[3] = {0, 1, 0};
    quad(out, top, up, s);
    quad(out, bot, down, s);
    quad(out, wx0, mx, s);
    quad(out, wx1, px, s);
    quad(out, wy0, my, s);
    quad(out, wy1, py, s);
}

int bird_batches(MockLua &L, double id)
{
    Val batches = Val::table();
    L.call("Batches", {Val::number(id), batches});
    int nb = (int)batches.tab->field("count").num, n = 0;
    for (int b = 1; b <= nb; b++) {
        Val e = batches.tab->at(b);
        if (e.type == Type::Table && e.tab->field("archive").num == 0 && e.tab->field("tex").num >= 44 &&
            e.tab->field("tex").num <= 52) {
            n++;
        }
    }
    return n;
}

}  // namespace

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::printf("G-SA1 feat_charopt_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_charopt_appdata");
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
    Val co = g.type == Type::Table ? g.tab->field("CHAROPT") : Val();
    Val ms = g.type == Type::Table ? g.tab->field("MUSIC_STATE") : Val();
    bool fns = g.type == Type::Table;
    for (const char *f : {"SetLives", "GetLives", "SetCompanion", "Companion", "SetGameOption", "HoldAir",
                          "AudioMusicState", "AudioMusicEnd"}) {
        fns = fns && g.tab->field(f).type == Type::Function;
    }
    CHECK(fns && feats.type == Type::Table && feats.tab->field("charopt").num == 1 &&
              feats.tab->field("musicstate").num == 1 && L.st.empty(),
          "gsa1.FEATURES.charopt = %g, .musicstate = %g; SetLives, GetLives, SetCompanion, Companion, SetGameOption, "
          "HoldAir, AudioMusicState, AudioMusicEnd registered",
          feats.type == Type::Table ? feats.tab->field("charopt").num : -1.0,
          feats.type == Type::Table ? feats.tab->field("musicstate").num : -1.0);
    if (g.type != Type::Table) return 1;
    CHECK(co.type == Type::Table && co.tab->field("COMPANION_BIRD").num == SA1_COMPANION_BIRD &&
              co.tab->field("TAILS_SNAP_TAILS").num == SA1_GOPT_TAILS_SNAP_TAILS &&
              co.tab->field("DEATH_DROWN").num == SA1_DEATH_DROWN && co.tab->field("DEATH_ZONE").num == SA1_DEATH_ZONE &&
              co.tab->field("EVENT_TIME_UP").num == SA1_EVENT_TIME_UP && co.tab->field("LIVES_START").num == 4 &&
              co.tab->field("LIVES_MAX").num == 127 && co.tab->field("BREATH_COUNTDOWN").num == 1080,
          "gsa1.CHAROPT: libsa1's numbers (bird %g, tail snap %g, deaths drown %g / zone %g, TIME_UP %g)",
          co.type == Type::Table ? co.tab->field("COMPANION_BIRD").num : -1.0,
          co.type == Type::Table ? co.tab->field("TAILS_SNAP_TAILS").num : -1.0,
          co.type == Type::Table ? co.tab->field("DEATH_DROWN").num : -1.0,
          co.type == Type::Table ? co.tab->field("DEATH_ZONE").num : -1.0,
          co.type == Type::Table ? co.tab->field("EVENT_TIME_UP").num : -1.0);
    CHECK(ms.type == Type::Table && ms.tab->field("JINGLE_COUNTDOWN").num == SA1_AUDIO_JINGLE_COUNTDOWN &&
              ms.tab->field("END_STOP").num == SA1_AUDIO_JINGLE_END_STOP &&
              ms.tab->field("END_HOST").num == SA1_AUDIO_JINGLE_END_HOST &&
              ms.tab->field("HEADER_VERSION").num == SA1_AUDIO_HEADER_VERSION && SA1_AUDIO_HEADER_VERSION >= 4,
          "gsa1.MUSIC_STATE: libsa1_audio.h's numbers (header version %g)",
          ms.type == Type::Table ? ms.tab->field("HEADER_VERSION").num : -1.0);
    int bad = 0;
    bad += is_nil_msg(L.call("SetLives", {}));
    bad += is_nil_msg(L.call("SetLives", {Val::number(1)}));
    bad += is_nil_msg(L.call("SetLives", {Val::string("1"), Val::number(3)}));
    bad += is_nil_msg(L.call("SetCompanion", {Val::number(1), Val::number(1)}));
    bad += is_nil_msg(L.call("SetCompanion", {Val::number(77), Val::number(1), Val::boolean(true)}));
    bad += is_nil_msg(L.call("Companion", {Val::number(77)}));
    bad += is_nil_msg(L.call("SetGameOption", {Val::number(77), Val::number(1), Val::number(0.5)}));
    bad += is_nil_msg(L.call("HoldAir", {Val::number(-3)}));
    std::vector<Val> gl = L.call("GetLives", {Val::number(77)});
    std::vector<Val> mst = L.call("AudioMusicState", {});
    CHECK(bad == 8 && gl.size() == 1 && gl[0].type == Type::Nil && is_nil_msg(mst) && str_of(mst, 2) == "not_open" &&
              L.st.empty(),
          "bad arguments (missing, strings, unknown ids, a fraction): %d of 8 answered with nil + message; GetLives of an "
          "unknown id: nil; AudioMusicState without the sound banks: nil, \"%s\", \"%s\"", bad, str_of(mst, 1).c_str(),
          str_of(mst, 2).c_str());

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
    // a floor (z 0) over x -4000..8000, and a water box (z 0..600 = 150 SA1 units deep) over x 2000..6000
    std::vector<sa1_collision_tri> tris;
    const float fl[4][3] = {{-4000, -3000, 0}, {8000, -3000, 0}, {8000, 3000, 0}, {-4000, 3000, 0}};
    const float up[3] = {0, 0, 1};
    quad(tris, fl, up, SA1_SURFACE_SOLID);
    box(tris, 2000, 6000, -2000, 2000, 0, 600, SA1_SURFACE_WATER);
    bool world = st == "ready" && se && se->set_world(tris, err);
    bool audio = world && se->audio_open(false, err);
    CHECK(world && audio, "the disc (%s), a floor with a water box 600 HU deep, the sound banks open%s%s", st.c_str(),
          err.empty() ? "" : ": ", err.c_str());
    if (!world || !audio) {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    install_mesh_library(L);
    auto pair = [&](double id) { se->tick((int32_t)id, 0.0f, 0.0f, 0.0f, 0u, 1.0f / 30.0f); };
    std::vector<sa1_event> ev;

    // ---- drowning: the game's music state through the jingle, the drown and the restart --------------------------
    const float wpos[3] = {4000.0f, 0.0f, 8.0f};
    double sid = se->create(SA1_CHAR_SONIC, wpos, 0.0f, err);
    int32_t jingle_step = -1, stop_step = -1, death_step = -1, death_cause = -1, restart_step = -1, back_step = -1;
    bool kind_ok = false, name_ok = false, stop_ok = false;
    Val out = Val::table();
    for (int p = 0; p < 1150 && sid > 0; p++) {
        pair(sid);
        se->poll_events(ev);
        uint32_t step = se->get((int32_t)sid)->st.step;
        for (const sa1_event &e : ev) {
            if (e.character != (sa1_character_id)sid) continue;
            if (e.type == SA1_EVENT_DEATH && death_step < 0) {
                death_step = (int32_t)e.step;
                death_cause = (int32_t)e.arg;
            }
            if (e.type == SA1_EVENT_RESTART && e.id == 2 && restart_step < 0) restart_step = (int32_t)e.step;
        }
        std::vector<Val> r = L.call("AudioMusicState", {out});
        if (r.size() != 1 || r[0].type != Type::Table) continue;
        double j = out.tab->field("jingle").num;
        bool stopped = out.tab->field("stopped").b;
        if (j == 96 && jingle_step < 0) {
            jingle_step = (int32_t)step;
            kind_ok = out.tab->field("kind").num == SA1_AUDIO_JINGLE_COUNTDOWN;
            name_ok = out.tab->field("name").str == "TIMER.ADX";
        }
        if (stopped && stop_step < 0) {
            stop_step = (int32_t)step;
            stop_ok = j == -1 && out.tab->field("last_end").num == SA1_AUDIO_JINGLE_END_STOP &&
                      out.tab->field("last_jingle").num == 96;
        }
        if (stop_step >= 0 && !stopped && back_step < 0) back_step = (int32_t)step;
    }
    CHECK(jingle_step >= 1080 && jingle_step <= 1086 && kind_ok && name_ok,
          "Sonic 150 units under water: AudioMusicState().jingle 96 (kind COUNTDOWN, \"TIMER.ADX\") from step %d (the "
          "countdown's JINGLE at 1082)", jingle_step);
    CHECK(death_step >= 1860 && death_step <= 1866 && stop_step >= death_step && stop_step <= death_step + 2 && stop_ok &&
              death_cause == SA1_DEATH_DROWN && death_step - jingle_step >= 778 && death_step - jingle_step <= 782,
          "the drown: stopped from step %d (jingle -1, last_end STOP, last_jingle 96); SA1_EVENT_DEATH cause %d (DROWN) "
          "at step %d", stop_step, death_cause, death_step);
    CHECK(restart_step == death_step + 240 && back_step > restart_step && back_step <= restart_step + 3,
          "RESTART id 2 at step %d (240 after the drown); the game's music back (stopped false) at step %d", restart_step,
          back_step);
    se->destroy((int32_t)sid);

    // ---- AudioMusicEnd: a countdown ended by the host ------------------------------------------------------------
    sid = se->create(SA1_CHAR_SONIC, wpos, 0.0f, err);
    for (int p = 0; p < 560 && sid > 0; p++) {
        pair(sid);
        se->poll_events(ev);
    }
    L.call("AudioMusicState", {out});
    double j_before = out.tab->field("jingle").num;
    std::vector<Val> re = L.call("AudioMusicEnd", {});
    L.call("AudioMusicState", {out});
    CHECK(j_before == 96 && re.size() == 1 && re[0].b && out.tab->field("jingle").num == -1 &&
              out.tab->field("last_end").num == SA1_AUDIO_JINGLE_END_HOST && !out.tab->field("stopped").b,
          "AudioMusicEnd during the countdown (jingle %g): jingle -1, last_end HOST (%g)", j_before,
          out.tab->field("last_end").num);
    se->destroy((int32_t)sid);

    // ---- "Characters can drown" off: the air timer held --------------------------------------------------------------
    sid = se->create(SA1_CHAR_SONIC, wpos, 0.0f, err);
    int max_found = -1, max_breath = -1, jingles = 0;
    bool hold_ok = true;
    for (int p = 0; p < 1300 && sid > 0; p++) {
        std::vector<Val> h = L.call("HoldAir", {Val::number(sid)});
        if (h.size() != 1 || h[0].type != Type::Number) {
            hold_ok = false;
            break;
        }
        max_found = std::max(max_found, (int)h[0].num);
        pair(sid);
        max_breath = std::max(max_breath, (int)se->get((int32_t)sid)->st.breath_timer);
        se->poll_events(ev);
        for (const sa1_event &e : ev) {
            jingles += e.character == (sa1_character_id)sid && e.type == SA1_EVENT_JINGLE && e.id == 96;
        }
    }
    const sa1_state_ex &hs = se->get((int32_t)sid)->st;
    CHECK(hold_ok && max_found <= 2 && max_breath <= 2 && jingles == 0 && hs.mode != 81,
          "HoldAir before every pair for 1300 pairs under water: the timer it found at most %d, after a pair at most %d "
          "(the game's countdown starts at 1080), %d countdown jingles, mode %d (not the drown)", max_found, max_breath,
          jingles, (int)hs.mode);
    // ... and with drowning on again the game's own timer counts from 0
    for (int p = 0; p < 100; p++) pair(sid);
    CHECK(se->get((int32_t)sid)->st.breath_timer >= 190, "without HoldAir the game's air timer counts again (%d after "
          "100 pairs)", (int)se->get((int32_t)sid)->st.breath_timer);
    se->destroy((int32_t)sid);
    se->poll_events(ev);

    // ---- lives --------------------------------------------------------------------------------------------------------
    const float dpos[3] = {-2000.0f, 0.0f, 8.0f};
    sid = se->create(SA1_CHAR_SONIC, dpos, 0.0f, err);
    std::vector<Val> l0 = L.call("GetLives", {Val::number(sid)});
    std::vector<Val> s1 = L.call("SetLives", {Val::number(sid), Val::number(2)});
    std::vector<Val> l1 = L.call("GetLives", {Val::number(sid)});
    for (int p = 0; p < 30; p++) pair(sid);
    std::vector<Val> l2 = L.call("GetLives", {Val::number(sid)});
    std::vector<Val> s2 = L.call("SetLives", {Val::number(sid), Val::number(500)});
    std::vector<Val> l3 = L.call("GetLives", {Val::number(sid)});
    CHECK(l0.size() == 1 && l0[0].num == 4 && s1.size() == 1 && s1[0].num == 2 && l1[0].num == 2 && l2[0].num == 2 &&
              s2[0].num == 127 && l3[0].num == 127 && se->get((int32_t)sid)->st.lives == 2,
          "lives: the game's 4, SetLives 2 -> GetLives %g (and %g after 30 pairs), 500 -> %g", l1[0].num, l2[0].num,
          l3[0].num);
    std::vector<Val> sc = L.call("SetCompanion", {Val::number(sid), Val::number(SA1_COMPANION_BIRD), Val::boolean(true)});
    CHECK(is_nil_msg(sc), "SetCompanion on Sonic: nil, \"%s\" (%s)", str_of(sc, 1).c_str(), str_of(sc, 2).c_str());
    se->destroy((int32_t)sid);

    // ---- Amy's bird ---------------------------------------------------------------------------------------------------
    double aid = se->create(SA1_CHAR_AMY, dpos, 0.0f, err);
    for (int p = 0; p < 10; p++) pair(aid);
    std::vector<Val> c0 = L.call("Companion", {Val::number(aid), Val::number(SA1_COMPANION_BIRD)});
    int b0 = bird_batches(L, aid);
    std::vector<Val> on = L.call("SetCompanion", {Val::number(aid), Val::number(SA1_COMPANION_BIRD), Val::boolean(true)});
    for (int p = 0; p < 30; p++) pair(aid);
    L.call("Render", {Val::number(aid), Val::number(1)});
    std::vector<Val> c1 = L.call("Companion", {Val::number(aid), Val::number(SA1_COMPANION_BIRD)});
    int b1 = bird_batches(L, aid);
    std::vector<Val> again = L.call("SetCompanion", {Val::number(aid), Val::number(1), Val::number(1)});
    std::vector<Val> off = L.call("SetCompanion", {Val::number(aid), Val::number(SA1_COMPANION_BIRD), Val::boolean(false)});
    for (int p = 0; p < 2; p++) pair(aid);
    L.call("Render", {Val::number(aid), Val::number(1)});
    std::vector<Val> c2 = L.call("Companion", {Val::number(aid), Val::number(SA1_COMPANION_BIRD)});
    int b2 = bird_batches(L, aid);
    CHECK(c0.size() == 1 && !c0[0].b && b0 == 0 && on.size() == 1 && on[0].b && c1.size() == 1 && c1[0].b && b1 > 0 &&
              again.size() == 1 && again[0].b && off.size() == 1 && off[0].b && c2.size() == 1 && !c2[0].b && b2 == 0,
          "Amy's bird: none at first (%d bird batches); SetCompanion(BIRD, true) -> in her world, %d batches of archive 0 "
          "textures 44-52; again (1): accepted; false -> gone after a pair (%d)", b0, b1, b2);
    se->destroy((int32_t)aid);

    // ---- Tails' tail blend --------------------------------------------------------------------------------------------
    double tid = se->create(SA1_CHAR_TAILS, dpos, 0.0f, err);
    std::vector<Val> g1 = L.call("SetGameOption", {Val::number(tid), Val::number(SA1_GOPT_TAILS_SNAP_TAILS),
                                                    Val::number(1)});
    for (int p = 0; p < 5; p++) pair(tid);
    std::vector<Val> g0 = L.call("SetGameOption", {Val::number(tid), Val::number(SA1_GOPT_TAILS_SNAP_TAILS),
                                                    Val::number(0)});
    CHECK(g1.size() == 1 && g1[0].b && g0.size() == 1 && g0[0].b && L.st.empty(),
          "SetGameOption(Tails, TAILS_SNAP_TAILS, 1) before his first tick and 0 between ticks: accepted");
    se->destroy((int32_t)tid);

    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
