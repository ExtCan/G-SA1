// feat_super_binding_test: Super Sonic through the module's Lua functions (round 6a in round 0.9.3) - the feature "super"
// (src/module/bind_super.cpp: SuperOrder, SuperState, SuperInfo, gsa1.SUPER) and gsa1.Create's extras table
// (gsa1_module.cpp). Linked like binding_test (the module's objects, libsa1, the mock Lua stack of tests/mock_lua.hpp) by
// build.py, run with --gdi GAME.gdi.
//
//   feat_super_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
// Without the disc: gsa1.FEATURES.super = 1, the functions registered, gsa1.SUPER and gsa1.CHAR_SUPER_SONIC hold
// libsa1's numbers, gsa1.Characters() lists Super Sonic as playable, SuperInfo says the disc is not loaded; bad arguments
// come back as nil + message (no Lua error).
// With the disc (and gm_construct from the Garry's Mod install, read only; skipped when it is not there):
//   * SuperInfo: ready, Sonic's Super forms loaded;
//   * Create's extras: a bad table (not a table, a fraction, a string) -> nil, message, "bad_extra"; a create flag G-SA1
//     does not pass, the sea plane, SUPER_CAPABLE Tails -> nil + message;
//   * Super Sonic created with {create_flags = WATER_FLOOR, super_flags = NO_DRAIN, start_rings = 30}: SuperState has
//     them, Super after 2 pairs with 30 rings; without start_rings libsa1's 50;
//   * a SUPER_CAPABLE Sonic running: SuperOrder(SUPER) -> Super in the next pair with his speed, SuperOrder(NORMAL) back;
//     a plain Sonic -> nil, message, "unsupported"; an order that is not 46 / 47 -> "bad_argument".
// 0.9.3a (feature "super" 2: sadc docs/research/super_general_design.md 6.9 / 8.3): SuperOption, SuperGameOption,
// SuperVoicePreview and the new gsa1.SUPER constants without the disc; with it the General entry (GENERAL | START: Super
// after its first pair, SuperState.general / start), the options (a General world takes all four, kind 8 only the voice;
// bad values and other game options refused), kind 8 created with Sonic's upgrade names (Sonic's rows: 0x8007 while
// Super), START_NORMAL, the Preview without open sound banks.
// 0.9.4a (feature "super" 4: sadc docs/research/super2_plan.md 6.4 with its review): SuperWhoosh, SuperInfo.whoosh /
// whoosh_on / whoosh_bank, gsa1.SUPER's SUPOPT_SUPER_ANIMS, SUPOPT_LSD_GOLD, SUPER_EFFECTS_CLONES / _DUST, DRAW_SUPER_GOLD,
// TEXTURE_VARIANT_SUPER_GOLD, WHOOSH_STAGE and gsa1.WRAP_GOLD equal libsa1's / session.hpp's; with the disc SuperOption takes
// SUPER_ANIMS and LSD_GOLD 0 / 1 and SUPER_EFFECTS 3 for a General character, refuses 2 / 4 and kind 8; gsa1.Texture's
// variant (lcharge04's golden variant: other RGB, the same alpha; none for s_ball_a); SuperInfo.stage_tones follows the
// whoosh.
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
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

namespace {

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1e9;
}

Val extras(double create_flags, double super_flags, double start_rings)
{
    Val t = Val::table();
    if (create_flags >= 0) t.tab->set(Val::string("create_flags"), Val::number(create_flags));
    if (super_flags >= 0) t.tab->set(Val::string("super_flags"), Val::number(super_flags));
    if (start_rings > -100) t.tab->set(Val::string("start_rings"), Val::number(start_rings));
    return t;
}

// Tick(id, stick 0 / forward, ...) n pairs
void pairs_of(MockLua &L, double id, int n, double sy)
{
    for (int i = 0; i < n; i++) {
        L.call("Tick", {Val::number(id), Val::number(0), Val::number(sy), Val::number(0), Val::number(0),
                        Val::number(1.0 / 30.0)});
    }
}

Val super_state(MockLua &L, double id)
{
    Val out = Val::table();
    std::vector<Val> r = L.call("SuperState", {Val::number(id), out});
    return r.size() == 1 && r[0].type == Type::Table ? r[0] : Val();
}

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
    std::printf("G-SA1 feat_super_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_super_appdata");
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
    Val K = g.tab->field("SUPER");
    bool fns = true;
    for (const char *f : {"SuperOrder", "SuperState", "SuperInfo", "SuperOption", "SuperGameOption", "SuperVoicePreview",
                          "SuperVoiceClip", "SuperWhoosh"}) {
        fns = fns && g.tab->field(f).type == Type::Function;
    }
    CHECK(fns && feats.type == Type::Table && feats.tab->field("super").num == 4 && L.st.empty(),
          "gsa1.FEATURES.super = %g; SuperOrder, SuperState, SuperInfo, SuperOption, SuperGameOption, SuperVoicePreview, "
          "SuperVoiceClip, SuperWhoosh registered",
          feats.type == Type::Table ? feats.tab->field("super").num : -1.0);
#if defined(SA1_API_SUPER)
    CHECK(K.type == Type::Table && K.tab->field("KIND").num == SA1_CHAR_SUPER_SONIC &&
              K.tab->field("ORDER_SUPER").num == SA1_ORDER_SUPER && K.tab->field("ORDER_NORMAL").num == SA1_ORDER_NORMAL &&
              K.tab->field("NO_DRAIN").num == SA1_SUPER_NO_DRAIN && K.tab->field("KEEP_AT_ZERO").num == SA1_SUPER_KEEP_AT_ZERO &&
              K.tab->field("FAITHFUL_REVERT").num == SA1_SUPER_FAITHFUL_REVERT &&
              K.tab->field("SEA_PLANE").num == SA1_SUPER_SEA_PLANE &&
              K.tab->field("CREATE_SUPER_CAPABLE").num == SA1_CREATE_SUPER_CAPABLE &&
              K.tab->field("CREATE_WATER_FLOOR").num == SA1_CREATE_WATER_FLOOR &&
              K.tab->field("STATE_SUPER").num == SA1_STATE_SUPER && K.tab->field("MUSIC_THEME").num == 86 &&
              g.tab->field("CHAR_SUPER_SONIC").num == SA1_CHAR_SUPER_SONIC,
          "gsa1.SUPER: libsa1's numbers (orders 46 / 47, super flags 1 2 4 8, create flags 0x800 / 0x1000, the theme "
          "86); gsa1.CHAR_SUPER_SONIC 8");
#endif
#if defined(SA1_API_SUPER_GENERAL)
    CHECK(K.type == Type::Table && K.tab->field("GENERAL").num == SA1_SUPER_GENERAL &&
              K.tab->field("START").num == SA1_SUPER_START && K.tab->field("WATER_WHILE_SUPER").num == SA1_SUPER_WATER_WHILE_SUPER &&
              K.tab->field("START_NORMAL").num == SA1_SUPER_START_NORMAL && K.tab->field("SUPOPT_SPEED").num == SA1_SUPOPT_SPEED &&
              K.tab->field("SUPOPT_NO_AURA").num == SA1_SUPOPT_NO_AURA && K.tab->field("SUPOPT_VOICE").num == SA1_SUPOPT_VOICE &&
              K.tab->field("SUPOPT_SUPER_EFFECTS").num == SA1_SUPOPT_SUPER_EFFECTS &&
              K.tab->field("SPEED_GAME").num == SA1_SUPER_SPEED_GAME && K.tab->field("SPEED_RUN").num == SA1_SUPER_SPEED_RUN &&
              K.tab->field("SPEED_HALF").num == SA1_SUPER_SPEED_HALF && K.tab->field("SPEED_SONIC").num == SA1_SUPER_SPEED_SONIC &&
              K.tab->field("GOPT_IDLE_BY_FORM").num == SA1_GOPT_SUPER_IDLE_BY_FORM &&
              K.tab->field("GOPT_AURA_ANIM").num == SA1_GOPT_SUPER_AURA_ANIM &&
              K.tab->field("AURA_DREAMCAST").num == SA1_AURA_ANIM_DREAMCAST && K.tab->field("AURA_CALM").num == SA1_AURA_ANIM_CALM &&
              K.tab->field("AURA_SLOW").num == SA1_AURA_ANIM_SLOW && K.tab->field("VOICE_DEFAULT").num == 1116,
          "gsa1.SUPER (0.9.3a): GENERAL 0x10, START 0x20, WATER_WHILE_SUPER 0x40, START_NORMAL 0x80, SUPOPT_* 1-4, SPEED_* "
          "0-3, GOPT_IDLE_BY_FORM %g, GOPT_AURA_ANIM %g, AURA_* 0-2, VOICE_DEFAULT 1116",
          K.type == Type::Table ? K.tab->field("GOPT_IDLE_BY_FORM").num : -1.0,
          K.type == Type::Table ? K.tab->field("GOPT_AURA_ANIM").num : -1.0);
#endif
#if defined(SA1_API_SUPER_POLISH)
    CHECK(K.type == Type::Table && K.tab->field("SUPOPT_SUPER_ANIMS").num == SA1_SUPOPT_SUPER_ANIMS &&
              K.tab->field("SUPOPT_LSD_GOLD").num == SA1_SUPOPT_LSD_GOLD &&
              K.tab->field("SUPER_EFFECTS_CLONES").num == SA1_SUPER_EFFECTS_CLONES &&
              K.tab->field("SUPER_EFFECTS_DUST").num == SA1_SUPER_EFFECTS_DUST &&
              K.tab->field("DRAW_SUPER_GOLD").num == SA1_DRAW_SUPER_GOLD &&
              K.tab->field("TEXTURE_VARIANT_SUPER_GOLD").num == SA1_TEXTURE_VARIANT_SUPER_GOLD &&
              K.tab->field("WHOOSH_STAGE").num == 19 && g.tab->field("WRAP_GOLD").num == gsa1::WRAP_GOLD &&
              gsa1::WRAP_GOLD == 0x10u,
          "gsa1.SUPER (0.9.4a): SUPOPT_SUPER_ANIMS %g, SUPOPT_LSD_GOLD %g, SUPER_EFFECTS_CLONES 1 / _DUST 2, DRAW_SUPER_GOLD "
          "0x2000, TEXTURE_VARIANT_SUPER_GOLD 1, WHOOSH_STAGE 19; gsa1.WRAP_GOLD %g",
          K.type == Type::Table ? K.tab->field("SUPOPT_SUPER_ANIMS").num : -1.0,
          K.type == Type::Table ? K.tab->field("SUPOPT_LSD_GOLD").num : -1.0, g.tab->field("WRAP_GOLD").num);
#else
    CHECK(false, "libsa1.h has no Super Sonic polish (round 0.9.4a, SA1_API_SUPER_POLISH)");
#endif
    // the whoosh without the disc: the setting is the session's (no banks: "closed")
    std::vector<Val> wb = L.call("SuperWhoosh", {Val::string("x")});
    std::vector<Val> w0 = L.call("SuperWhoosh", {Val::boolean(false)});
    Val wi0 = Val::table();
    L.call("SuperInfo", {wi0});
    std::vector<Val> w1 = L.call("SuperWhoosh", {Val::boolean(true)});
    Val wi1 = Val::table();
    L.call("SuperInfo", {wi1});
#if defined(SA1_AUDIO_HAS_STAGE_RULES)
    CHECK(is_nil_msg(wb) && str_of(wb, 2) == "bad_argument" && w0.size() == 1 && w0[0].b && w1.size() == 1 && w1[0].b &&
              wi0.tab->field("whoosh").b && !wi0.tab->field("whoosh_on").b && wi0.tab->field("stage_tones").b &&
              wi1.tab->field("whoosh_on").b && !wi1.tab->field("stage_tones").b &&
              wi1.tab->field("whoosh_bank").str == "closed" && L.st.empty(),
          "SuperWhoosh(false / true) -> true; a string -> bad_argument; SuperInfo.whoosh (stage rules) true, whoosh_on "
          "follows, stage_tones true only while the whoosh is off, whoosh_bank \"%s\" without the sound banks",
          wi1.tab->field("whoosh_bank").str.c_str());
#else
    CHECK(is_nil_msg(w1) && str_of(w1, 2) == "unsupported" && !wi1.tab->field("whoosh").b,
          "a libsa1 without stage rules: SuperWhoosh -> unsupported, SuperInfo.whoosh false");
#endif
    std::vector<Val> ch = L.call("Characters", {});
    bool listed = false;
    if (ch.size() == 1 && ch[0].type == Type::Table) {
        for (int i = 1; i <= 16; i++) {
            Val e = ch[0].tab->at(i);
            if (e.type == Type::Table && e.tab->field("kind").num == 8 && e.tab->field("playable").b) listed = true;
        }
    }
    Val inf0 = Val::table();
    L.call("SuperInfo", {inf0});
    CHECK(listed && inf0.tab->field("api").b && inf0.tab->field("playable").b && !inf0.tab->field("ready").b &&
              !inf0.tab->field("forms").b,
          "Characters(): kind 8 playable; SuperInfo before the disc: api, playable, not ready, no forms yet");
    int bad = 0;
    bad += is_nil_msg(L.call("SuperOrder", {}));
    bad += is_nil_msg(L.call("SuperOrder", {Val::string("1"), Val::number(46)}));
    bad += is_nil_msg(L.call("SuperOrder", {Val::number(77), Val::number(46)}));
    bad += is_nil_msg(L.call("SuperOrder", {Val::number(77), Val::number(0.5)}));
    std::vector<Val> s77 = L.call("SuperState", {Val::number(77)});
    CHECK(bad == 4 && s77.size() == 1 && s77[0].type == Type::Nil && L.st.empty(),
          "bad arguments (none, a string, an unknown id, a fraction): %d of 4 answered with nil + message; SuperState of "
          "an unknown id: nil", bad);
    int bad2 = 0;
    bad2 += is_nil_msg(L.call("SuperOption", {})) && str_of(L.call("SuperOption", {}), 2) == "bad_argument";
    bad2 += is_nil_msg(L.call("SuperOption", {Val::number(77), Val::number(1), Val::number(1)}));
    bad2 += is_nil_msg(L.call("SuperGameOption", {Val::number(77), Val::number(2), Val::number(1)}));
    bad2 += is_nil_msg(L.call("SuperVoicePreview", {Val::number(0)}));
    bad2 += is_nil_msg(L.call("SuperVoicePreview", {Val::number(1116)}));      // no disc, no sound banks: not ready
    bad2 += is_nil_msg(L.call("SuperVoicePreview", {Val::number(1116), Val::number(77)}));
    bad2 += is_nil_msg(L.call("SuperVoiceClip", {Val::number(4096)}));
    bad2 += is_nil_msg(L.call("SuperVoiceClip", {Val::number(396)}));         // no disc, no sound banks: not ready
    bad2 += is_nil_msg(L.call("SuperVoiceClip", {Val::number(396), Val::number(77)}));
    CHECK(bad2 == 9 && L.st.empty(), "SuperOption / SuperGameOption of no character, SuperVoicePreview(0), a Preview "
          "without the sound banks and for an unknown character, SuperVoiceClip(4096), a clip without the sound banks and "
          "for an unknown character: %d of 9 nil + message", bad2);

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
    Val inf = Val::table();
    L.call("SuperInfo", {inf});
    CHECK(st == "ready" && inf.tab->field("ready").b && inf.tab->field("forms").b &&
              inf.tab->field("stage_tones").b == !inf.tab->field("whoosh").b,
          "the disc (%s): SuperInfo ready, Sonic's Super forms loaded; the Perfect Chaos stage tones kept out of the mixer "
          "unless the whoosh is routed (0.9.4a: stage_tones %d, whoosh %d)", st.c_str(), (int)inf.tab->field("stage_tones").b,
          (int)inf.tab->field("whoosh").b);
    // 0.9.4a (review R.6): gsa1.Texture(kind, index, archive, variant) - lcharge04's golden variant, none for s_ball_a
    {
        int eff = -1;
        std::vector<Val> ta = L.call("TextureArchives", {Val::number(0)});
        for (int i = 1; ta.size() == 1 && ta[0].type == Type::Table && i <= 16; i++) {
            Val e = ta[0].tab->at(i);
            if (e.type == Type::Table && e.tab->field("name").str == "SON_EFF") eff = i - 1;
        }
        int lc4 = -1, sba = -1;
        for (int i = 0; eff >= 0 && i < 64; i++) {
            std::vector<Val> t = L.call("Texture", {Val::number(0), Val::number(i), Val::number(eff)});
            if (t.size() != 1 || t[0].type != Type::Table) break;
            std::string nm = t[0].tab->field("name").str;
            if (nm == "lcharge04") lc4 = i;
            if (nm == "s_ball_a") sba = i;
        }
        auto runs_of = [&](const Val &t, gsa1::TextureRuns &tr) {
            tr.width = (uint32_t)t.tab->field("w").num;
            tr.height = (uint32_t)t.tab->field("h").num;
            tr.runs = t.tab->field("runs").str;
            tr.run_count = (uint32_t)t.tab->field("nruns").num;
        };
        bool same_alpha = false, other_rgb = false;
        std::vector<Val> base, gold, ball, v0;
        if (lc4 >= 0) {
            base = L.call("Texture", {Val::number(0), Val::number(lc4), Val::number(eff)});
            gold = L.call("Texture", {Val::number(0), Val::number(lc4), Val::number(eff), Val::number(1)});
            v0 = L.call("Texture", {Val::number(0), Val::number(lc4), Val::number(eff), Val::number(0)});
        }
        if (base.size() == 1 && base[0].type == Type::Table && gold.size() == 1 && gold[0].type == Type::Table) {
            gsa1::TextureRuns tb, tg;
            runs_of(base[0], tb);
            runs_of(gold[0], tg);
            std::vector<uint8_t> pb, pg;
            if (gsa1::paint_runs(tb, pb) && gsa1::paint_runs(tg, pg) && pb.size() == pg.size() && !pb.empty()) {
                same_alpha = true;
                for (size_t p = 0; p < pb.size(); p += 4) {
                    same_alpha = same_alpha && pb[p + 3] == pg[p + 3];
                    other_rgb = other_rgb || std::memcmp(&pb[p], &pg[p], 3) != 0;
                }
            }
        }
        if (sba >= 0) ball = L.call("Texture", {Val::number(0), Val::number(sba), Val::number(eff), Val::number(1)});
        std::vector<Val> badv = L.call("Texture", {Val::number(0), Val::number(0), Val::number(0), Val::number(0.5)});
        CHECK(eff >= 0 && lc4 >= 0 && sba >= 0 && same_alpha && other_rgb && is_nil_msg(ball) && is_nil_msg(badv) &&
                  v0.size() == 1 && v0[0].type == Type::Table && v0[0].tab->field("runs").str == base[0].tab->field("runs").str &&
                  L.st.empty(),
              "gsa1.Texture(0, lcharge04 (%d), SON_EFF (%d), 1): the golden variant - every alpha kept, other RGB; variant 0 "
              "= the texture; s_ball_a's variant 1 -> nil + \"%s\"; a fractional variant refused", lc4, eff,
              str_of(ball, 1).c_str());
    }
    std::string map;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
        std::printf("  info  no gm_construct (%s): the Create checks are skipped\n", bsp.c_str());
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct)");
    const Val pos = Val::vector(704, 132, -139);
#if defined(SA1_API_SUPER)
    // the extras' refusals
    int be = 0, bm = 0;
    auto create8 = [&](const Val &ex) {
        return L.call("Create", {Val::number(8), pos, Val::number(180), Val(), Val(), ex});
    };
    std::vector<Val> r = create8(Val::string("x"));
    be += is_nil_msg(r) && str_of(r, 2) == "bad_extra";
    r = create8(extras(0.5, -1, -100));
    be += is_nil_msg(r) && str_of(r, 2) == "bad_extra";
    Val sf = Val::table();
    sf.tab->set(Val::string("super_flags"), Val::string("a"));
    r = create8(sf);
    be += is_nil_msg(r) && str_of(r, 2) == "bad_extra";
    r = create8(extras(0x20, -1, -100));
    bm += is_nil_msg(r);
    std::string why_stage = str_of(r, 1);
    r = create8(extras(-1, SA1_SUPER_SEA_PLANE, -100));
    bm += is_nil_msg(r) && str_of(r, 1).find("sea plane") != std::string::npos;
    r = L.call("Create", {Val::number(SA1_CHAR_TAILS), pos, Val::number(180), Val(), Val(),
                          extras(SA1_CREATE_SUPER_CAPABLE, -1, -100)});
    bm += is_nil_msg(r);
    CHECK(be == 3 && bm == 3 && L.st.empty(), "extras refused: %d of 3 bad tables (\"bad_extra\"), %d of 3 worlds G-SA1 "
          "does not make (a create flag of its own: \"%s\"; the sea plane; SUPER_CAPABLE Tails)", be, bm,
          why_stage.c_str());
    // Super Sonic with extras
    r = create8(extras(SA1_CREATE_WATER_FLOOR, SA1_SUPER_NO_DRAIN, 30));
    double id8 = num_of(r, 0);
    Val s0 = super_state(L, id8);
    pairs_of(L, id8, 3, 0.0);
    Val s1 = super_state(L, id8);
    CHECK(id8 > 0 && s0.type == Type::Table && s0.tab->field("capable").b && s0.tab->field("kind").num == 8 &&
              s0.tab->field("create_flags").num == SA1_CREATE_WATER_FLOOR &&
              s0.tab->field("super_flags").num == SA1_SUPER_NO_DRAIN && s0.tab->field("water_floor").b &&
              s0.tab->field("start_rings").num == 30 && s1.type == Type::Table && s1.tab->field("super").b &&
              s1.tab->field("rings").num == 30 && s1.tab->field("changes").num == 1,
          "Create(8, ..., {WATER_FLOOR, NO_DRAIN, 30 rings}): SuperState capable, the flags kept; Super after 3 pairs "
          "with %g rings (%g form change)", s1.type == Type::Table ? s1.tab->field("rings").num : -1.0,
          s1.type == Type::Table ? s1.tab->field("changes").num : -1.0);
    L.call("Destroy", {Val::number(id8)});
    r = create8(Val::table());
    id8 = num_of(r, 0);
    pairs_of(L, id8, 3, 0.0);
    Val s2 = super_state(L, id8);
    CHECK(id8 > 0 && s2.type == Type::Table && s2.tab->field("super").b && s2.tab->field("rings").num == 50 &&
              s2.tab->field("super_given").b == false,
          "Create(8, ..., {}): libsa1's defaults, Super with 50 rings");
    L.call("Destroy", {Val::number(id8)});
    // the transformation
    r = L.call("Create", {Val::number(0), pos, Val::number(180), Val(), Val::number(50),
                          extras(SA1_CREATE_SUPER_CAPABLE, 0, -100)});
    double id0 = num_of(r, 0);
    pairs_of(L, id0, 50, 1.0);
    Val a = super_state(L, id0);
    double v0 = a.type == Type::Table ? a.tab->field("speed").num : -1;
    std::vector<Val> o1 = L.call("SuperOrder", {Val::number(id0), Val::number(SA1_ORDER_SUPER)});
    pairs_of(L, id0, 1, 1.0);
    Val b = super_state(L, id0);
    double v1 = b.type == Type::Table ? b.tab->field("speed").num : -1;
    CHECK(id0 > 0 && a.tab->field("capable").b && !a.tab->field("super").b && o1.size() == 1 && o1[0].b &&
              b.tab->field("super").b && v0 > 300 && v1 > 0.9 * v0 && b.tab->field("rings").num == 50,
          "a SUPER_CAPABLE Sonic running at %.0f HU/s: SuperOrder(46) -> true; Super in the next pair at %.0f HU/s, 50 "
          "rings", v0, v1);
    std::vector<Val> o2 = L.call("SuperOrder", {Val::number(id0), Val::number(SA1_ORDER_NORMAL)});
    pairs_of(L, id0, 1, 1.0);
    Val c = super_state(L, id0);
    std::vector<Val> o3 = L.call("SuperOrder", {Val::number(id0), Val::number(3)});
    CHECK(o2.size() == 1 && o2[0].b && !c.tab->field("super").b && c.tab->field("changes").num == 2 && is_nil_msg(o3) &&
              str_of(o3, 2) == "bad_argument",
          "SuperOrder(47): back to normal Sonic in the next pair; SuperOrder(3): nil, \"%s\", %s", str_of(o3, 1).c_str(),
          str_of(o3, 2).c_str());
    L.call("Destroy", {Val::number(id0)});
#if defined(SA1_API_SUPER_GENERAL)
    // 0.9.3a: the General entry (GENERAL | START) and its options
    r = L.call("Create", {Val::number(0), pos, Val::number(180), Val(), Val(),
                          extras(SA1_CREATE_SUPER_CAPABLE, SA1_SUPER_GENERAL | SA1_SUPER_START | SA1_SUPER_NO_DRAIN, 50)});
    double idg = num_of(r, 0);
    Val g0 = super_state(L, idg);
    int opts = 0;
    opts += L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_SPEED), Val::number(SA1_SUPER_SPEED_RUN)})[0].b;
    opts += L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_NO_AURA), Val::number(0)})[0].b;
    opts += L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_VOICE), Val::number(1116)})[0].b;
    opts += L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_SUPER_EFFECTS), Val::number(1)})[0].b;
    opts += L.call("SuperGameOption", {Val::number(idg), Val::number(SA1_GOPT_SUPER_IDLE_BY_FORM), Val::number(1)})[0].b;
    opts += L.call("SuperGameOption", {Val::number(idg), Val::number(SA1_GOPT_SUPER_AURA_ANIM), Val::number(1)})[0].b;
    std::vector<Val> ob1 = L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_SPEED), Val::number(9)});
    std::vector<Val> ob2 = L.call("SuperOption", {Val::number(idg), Val::number(9), Val::number(0)});
    std::vector<Val> ob3 = L.call("SuperGameOption", {Val::number(idg), Val::number(SA1_GOPT_TAILS_SNAP_TAILS), Val::number(1)});
    std::vector<Val> ob4 = L.call("SuperGameOption", {Val::number(idg), Val::number(SA1_GOPT_SUPER_AURA_ANIM), Val::number(3)});
#if defined(SA1_API_SUPER_POLISH)
    // 0.9.4a: the Super poses, the golden Light Speed charge (0 / 1), the golden effects as bits (0..3)
    int pol = 0;
    pol += L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_SUPER_ANIMS), Val::number(0)})[0].b;
    pol += L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_SUPER_ANIMS), Val::number(1)})[0].b;
    pol += L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_LSD_GOLD), Val::number(0)})[0].b;
    pol += L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_LSD_GOLD), Val::number(1)})[0].b;
    pol += L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_SUPER_EFFECTS), Val::number(3)})[0].b;
    std::vector<Val> pb1 = L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_SUPER_ANIMS), Val::number(2)});
    std::vector<Val> pb2 = L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_LSD_GOLD), Val::number(2)});
    std::vector<Val> pb3 = L.call("SuperOption", {Val::number(idg), Val::number(SA1_SUPOPT_SUPER_EFFECTS), Val::number(4)});
    CHECK(pol == 5 && str_of(pb1, 2) == "bad_argument" && str_of(pb2, 2) == "bad_argument" &&
              str_of(pb3, 2) == "bad_argument" && L.st.empty(),
          "0.9.4a, the General entry: SuperOption SUPER_ANIMS 0 / 1, LSD_GOLD 0 / 1 and SUPER_EFFECTS 3 taken (%d of 5); "
          "SUPER_ANIMS 2, LSD_GOLD 2, SUPER_EFFECTS 4 refused (bad_argument)", pol);
    Val gw = super_state(L, idg);
    CHECK(gw.type == Type::Table && gw.tab->field("whoosh").b == wi1.tab->field("whoosh").b,
          "SuperState.whoosh: the General entry's whoosh is routed (%d)", gw.type == Type::Table ? (int)gw.tab->field("whoosh").b : -1);
#endif
    pairs_of(L, idg, 3, 0.0);
    Val g1 = super_state(L, idg);
    CHECK(idg > 0 && g0.type == Type::Table && g0.tab->field("general").b && g0.tab->field("start").b &&
              g0.tab->field("capable").b && g1.type == Type::Table && g1.tab->field("super").b &&
              g1.tab->field("kind").num == 0 && g1.tab->field("rings").num == 50 && opts == 6 &&
              str_of(ob1, 2) == "bad_argument" && str_of(ob2, 2) == "bad_argument" && str_of(ob3, 2) == "bad_argument" &&
              str_of(ob4, 2) == "bad_argument",
          "the General entry: Create(0, ..., {SUPER_CAPABLE, GENERAL | START | NO_DRAIN, 50}): SuperState general and start, "
          "Super after 3 pairs (kind 0, %g rings); the six options taken (%d); speed 9, option 9, the Tails option and aura "
          "animation 3 refused (bad_argument)", g1.type == Type::Table ? g1.tab->field("rings").num : -1.0, opts);
    L.call("Destroy", {Val::number(idg)});
    // kind 8 with Sonic's upgrade names (the module's find_upgrade maps kind 8 to Sonic's rows); START_NORMAL; options
    Val upn = Val::table();
    upn.tab->set(Val::number(1), Val::string("light_speed_shoes"));
    upn.tab->set(Val::number(2), Val::string("crystal_ring"));
    upn.tab->set(Val::number(3), Val::string("ancient_light"));
    r = L.call("Create", {Val::number(8), pos, Val::number(180), upn, Val(), extras(-1, SA1_SUPER_NO_DRAIN, 50)});
    id8 = num_of(r, 0);
    pairs_of(L, id8, 4, 0.0);
    Val k8 = super_state(L, id8);
    std::vector<Val> k8a = L.call("SuperOption", {Val::number(id8), Val::number(SA1_SUPOPT_NO_AURA), Val::number(1)});
    std::vector<Val> k8v = L.call("SuperOption", {Val::number(id8), Val::number(SA1_SUPOPT_VOICE), Val::number(1116)});
#if defined(SA1_API_SUPER_POLISH)
    std::vector<Val> k8p = L.call("SuperOption", {Val::number(id8), Val::number(SA1_SUPOPT_SUPER_ANIMS), Val::number(1)});
    std::vector<Val> k8g = L.call("SuperOption", {Val::number(id8), Val::number(SA1_SUPOPT_LSD_GOLD), Val::number(1)});
    CHECK(is_nil_msg(k8p) && str_of(k8p, 2) == "unsupported" && is_nil_msg(k8g) && str_of(k8g, 2) == "unsupported",
          "0.9.4a: Super Sonic (Vs. Perfect Chaos) refuses SUPER_ANIMS and LSD_GOLD (unsupported: he is the game's own)");
#endif
    CHECK(id8 > 0 && k8.type == Type::Table && k8.tab->field("super").b && k8.tab->field("equipment").num == 0x8007 &&
              !k8.tab->field("general").b && is_nil_msg(k8a) && str_of(k8a, 2) == "unsupported" && k8v.size() == 1 &&
              k8v[0].b,
          "Super Sonic (Vs. Perfect Chaos) with Sonic's three upgrade names: equipment %04X while Super; NO_AURA "
          "\"unsupported\" (his aura stays the game's), the voice taken",
          k8.type == Type::Table ? (unsigned)k8.tab->field("equipment").num : 0u);
    L.call("Destroy", {Val::number(id8)});
    r = L.call("Create", {Val::number(8), pos, Val::number(180), Val(), Val(),
                          extras(-1, SA1_SUPER_START_NORMAL | SA1_SUPER_NO_DRAIN, 50)});
    id8 = num_of(r, 0);
    pairs_of(L, id8, 6, 0.0);
    Val kn = super_state(L, id8);
    std::vector<Val> ko = L.call("SuperOrder", {Val::number(id8), Val::number(SA1_ORDER_SUPER)});
    pairs_of(L, id8, 3, 0.0);
    Val ks = super_state(L, id8);
    CHECK(id8 > 0 && kn.type == Type::Table && !kn.tab->field("super").b && ko.size() == 1 && ko[0].b &&
              ks.type == Type::Table && ks.tab->field("super").b,
          "kind 8 with START_NORMAL (re-created after he had turned back): normal Sonic for 6 pairs, Super again with "
          "SuperOrder(46)");
    L.call("Destroy", {Val::number(id8)});
#endif
    r = L.call("Create", {Val::number(0), pos, Val::number(180)});
    double idp = num_of(r, 0);
    std::vector<Val> o4 = L.call("SuperOrder", {Val::number(idp), Val::number(SA1_ORDER_SUPER)});
    Val p = super_state(L, idp);
    CHECK(idp > 0 && is_nil_msg(o4) && str_of(o4, 2) == "unsupported" && p.type == Type::Table && !p.tab->field("capable").b,
          "a plain Sonic: SuperOrder -> nil, \"%s\", unsupported; SuperState capable false", str_of(o4, 1).c_str());
    L.call("Destroy", {Val::number(idp)});
#endif
    CHECK(L.st.empty(), "the mock stack is empty after every call");
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
