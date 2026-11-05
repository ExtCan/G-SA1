// feat_skins_binding_test: Metal Sonic through the module's Lua functions (round 0.9.9f; sadc docs/research/metal099e.md 7, T2, T6, T9; RM.4).
//
//   feat_skins_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
//   * THE API PART runs whenever libsa1.h has SA1_API_SKIN: gsa1.SUPER's CREATE_SKIN, ARCHIVE_SKIN, COPT_SKIN_ANIM, SKIN_ANIM_* are libsa1's numbers; voice_class by its table (T2).
//   * THE BEHAVIOUR PART, with the disc: gsa1.Create(0, ..., {create_flags = CREATE_SKIN, skin = the flat entry}): his batches keep their textures of archive 61, 1,015 triangles, gsa1.SetVoiceless; on Character
//     Select gsa1.FrontendSkin: with the skin on a draw of archive 61 in the screen's holder keeps its texture, with it off none is there (T9, RM.4: white on this screen only).
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
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace {

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1.0;
}

#if defined(SA1_API_SKIN)
extern "C" {
struct sa1k_char;
struct sa1k_char *sa1k_char_of(const sa1_context *ctx, sa1_character_id id);
uint32_t sa1k_test_glow_bytes(const struct sa1k_char *sc);
}
sa1_event ev(int32_t type, uint32_t id)
{
    sa1_event e;
    std::memset(&e, 0, sizeof e);
    e.type = type;
    e.id = id;
    return e;
}

Val array(const std::vector<double> &v)
{
    Val t = Val::table();
    for (size_t i = 0; i < v.size(); i++) {
        t.tab->set(Val::number((double)(i + 1)), Val::number(v[i]));
    }
    return t;
}

// the entry as feat/sh_skins.lua's GSA1.Skins.DescOf gives it
Val skin_desc()
{
    Val t = Val::table();
    t.tab->set(Val::string("model_file"), Val::string("ADV02.PRS"));
    t.tab->set(Val::string("model_sha1"), Val::string("ab5f600e707681f538794520c296c4fefe84659c"));
    t.tab->set(Val::string("model_load"), Val::number(0x0C900000));
    t.tab->set(Val::string("model_first"), Val::number(0x0CA8B9CC));
    t.tab->set(Val::string("model_end"), Val::number(0x0CA92EB8));
    t.tab->set(Val::string("model_root"), Val::number(0x0CA92E84));
    t.tab->set(Val::string("tex_file"), Val::string("ADV_MR03.PRS"));
    t.tab->set(Val::string("tex_sha1"), Val::string("cca1620491391e3d6e44d83be478d0687d5fa14f"));
    t.tab->set(Val::string("keep"), array({76, 77, 97, 98, 99, 100, 101, 102, 103}));
    t.tab->set(Val::string("scale"), Val::number(0.7));
    t.tab->set(Val::string("lift"), Val::number(1.0));
    t.tab->set(Val::string("turn"), Val::number(1));
    t.tab->set(Val::string("ball_texture"), Val::number(101));
    t.tab->set(Val::string("parts"), array({1, 10, -1, -1, 12, 22, -1, -1, 12, 22, -1, -1, 25, 34, -1, -1, 25, 34, 5, 27, 27, 29, 6, 30, 30, 30, -1, -1, 30, 30, -1, -1, 30, 30, -1, -1,
                                            36, 45, -1, -1, 36, 45, 11, 38, 38, 40, 12, 41, 41, 41, -1, -1, 41, 41, -1, -1, 41, 41, -1, -1, 47, 55, 16, 49, 49, 51, 18, 52, 49, 51, -1, -1,
                                            52, 52, -1, -1, 52, 52, -1, -1, 57, 65, 21, 59, 59, 61, 23, 62, 59, 61, -1, -1, 62, 62, -1, -1, 62, 62, -1, -1}));
    t.tab->set(Val::string("anim"), array({10, 132, 11, 133, 12, 134, 13, 134}));
    t.tab->set(Val::string("anim_walk"), array({9, 131}));
    t.tab->set(Val::string("anim_fast"), array({9, 132}));
    t.tab->set(Val::string("fast_on"), Val::number(0.25));
    t.tab->set(Val::string("fast_off"), Val::number(0.215));
    t.tab->set(Val::string("glow_r"), Val::number(0.55));
    t.tab->set(Val::string("glow_g"), Val::number(0.10));
    t.tab->set(Val::string("glow_b"), Val::number(1.00));
    t.tab->set(Val::string("glow_inflate"), Val::number(0.30));
    return t;
}

Val extras_skin(bool with_skin)
{
    Val t = Val::table();
    t.tab->set(Val::string("create_flags"), Val::number((double)SA1_CREATE_SKIN));
    if (with_skin) {
        t.tab->set(Val::string("skin"), skin_desc());
    }
    return t;
}

std::vector<sa1_collision_tri> flat_floor(float half)
{
    std::vector<sa1_collision_tri> out;
    const float tile = 256.0f;
    for (float x = -half; x < half - 0.5f; x += tile) {
        for (float y = -half; y < half - 0.5f; y += tile) {
            const float p[4][3] = {{x, y, 0.0f}, {x + tile, y, 0.0f}, {x + tile, y + tile, 0.0f}, {x, y + tile, 0.0f}};
            sa1_collision_tri a, b;
            std::memset(&a, 0, sizeof a);
            std::memset(&b, 0, sizeof b);
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
    }
    return out;
}
#endif

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
    std::printf("G-SA1 feat_skins_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_skins_appdata");
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
    auto finish = [&]() {
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    };
#if !defined(SA1_API_SKIN)
    Val K0 = g.type == Type::Table ? g.tab->field("SUPER") : Val();
    CHECK(K0.type != Type::Table || K0.tab->field("CREATE_SKIN").type == Type::Nil, "libsa1.h has no SA1_API_SKIN: no gsa1.SUPER.CREATE_SKIN");
    return finish();
#else
    if (g.type != Type::Table) {
        CHECK(false, "the gsa1 table");
        return 1;
    }
    // ---- T2 --------------------------------------------------------------------------------------------------------
    using gsa1::voice_class;
    CHECK(!voice_class(ev(SA1_EVENT_SOUND, 1111)) && voice_class(ev(SA1_EVENT_SOUND, 1112)) && voice_class(ev(SA1_EVENT_SOUND, 1263)) && !voice_class(ev(SA1_EVENT_SOUND, 1264)) &&
              voice_class(ev(SA1_EVENT_SOUND, 1275)) && !voice_class(ev(SA1_EVENT_SOUND, 1274)) && !voice_class(ev(SA1_EVENT_SOUND, 736)) && !voice_class(ev(SA1_EVENT_SOUND, 723)),
          "T2 voice_class, tones: 1111 no, 1112 yes, 1263 yes, 1264 no, 1274 no, 1275 yes, 736 and 723 (Sonic's player sounds) no");
    CHECK(voice_class(ev(SA1_EVENT_VOICE, 396)) && !voice_class(ev(SA1_EVENT_SOUND_STOP, 1116)) && !voice_class(ev(SA1_EVENT_JINGLE, 1116)), "T2 SA1_EVENT_VOICE yes, a stop never, a jingle never");
    Val K = g.tab->field("SUPER");
    CHECK(K.type == Type::Table && K.tab->field("CREATE_SKIN").num == (double)SA1_CREATE_SKIN && K.tab->field("ARCHIVE_SKIN").num == (double)SA1_ARCHIVE_SKIN &&
              K.tab->field("COPT_SKIN_ANIM").num == (double)SA1_COPT_SKIN_ANIM && K.tab->field("SKIN_ANIM_FLY").num == (double)SA1_SKIN_ANIM_FLY &&
              K.tab->field("SKIN_ANIM_WALK").num == (double)SA1_SKIN_ANIM_WALK && K.tab->field("SKIN_ANIM_GLOW").num == (double)SA1_SKIN_ANIM_GLOW && SA1_CREATE_SKIN == 0x4000u && SA1_ARCHIVE_SKIN == 61u,
          "gsa1.SUPER.CREATE_SKIN 0x4000, ARCHIVE_SKIN 61, COPT_SKIN_ANIM, SKIN_ANIM_*: libsa1's numbers");
    if (gdi.empty()) {
        std::printf("  info  no disc: the behaviour part is skipped\n");
        return finish();
    }
    gsa1::make_dirs(fake_appdata);
    gsa1::Config cfg;
    cfg.disc = gdi;
    std::string err;
    CHECK(gsa1::save_config(cfg, err), "config written to the scratch APPDATA (%s)", err.c_str());
    L.call("Init", {});
    std::string ist = "loading";
    for (int polls = 0; ist == "loading" && polls < 60000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        ist = str_of(L.call("InitPoll", {}), 0);
    }
    CHECK(ist == "ready", "the disc: %s", ist.c_str());
    gsa1::Session *se = gsa1::mod::session();
    if (ist != "ready" || !se) {
        return finish();
    }
    std::string map;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
        std::printf("  info  no gm_construct (%s): the behaviour part is skipped\n", bsp.c_str());
        return finish();
    }
    std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct) (Create needs a world)");
    CHECK(se->set_world(flat_floor(4096.0f), err), "a flat SOLID floor (%s)", err.c_str());

    // T6: the flag with no entry refuses by name
    std::vector<Val> r0 = L.call("Create", {Val::number(0), Val::vector(0, 0, 8), Val::number(0), Val(), Val(), extras_skin(false)});
    CHECK(num_of(r0, 0) <= 0.0 && str_of(r0, 1).find("skin") != std::string::npos, "T6 the flag without the entry: refused by name: %s", str_of(r0, 1).c_str());
    // a plain Sonic has no archive 61 listed
    std::vector<Val> ta = L.call("TextureArchives", {Val::number(0)});
    int listed = 0;
    for (int i = 1; ta.size() == 1 && ta[0].type == Type::Table && i <= 64; i++) {
        listed += ta[0].tab->at(i).type == Type::Table;
    }
    CHECK(listed > 0 && listed < 61, "TextureArchives(0): %d archives: archive 61 is not among them", listed);
    std::vector<Val> r = L.call("Create", {Val::number(0), Val::vector(0, 0, 8), Val::number(0), Val(), Val(), extras_skin(true)});
    double id = num_of(r, 0);
    CHECK(id > 0.0 && L.st.empty(), "gsa1.Create(0, ..., {create_flags = CREATE_SKIN, skin = ...}) = id %.0f (%s)", id, str_of(r, 1).c_str());
    if (id <= 0.0) {
        return finish();
    }
    // 0.9.9g: the entry's colour reached libsa1: the shells were built (the internal test hook; what they look like: skin_test S11)
    CHECK(sa1k_test_glow_bytes(sa1k_char_of(se->ctx(), (sa1_character_id)id)) > 0u, "T6 extras.skin's glow reached libsa1: %u bytes of shells", (unsigned)sa1k_test_glow_bytes(sa1k_char_of(se->ctx(), (sa1_character_id)id)));
    auto tick = [&](double buttons = 0.0) {
        return L.call("Tick", {Val::number(id), Val::number(0), Val::number(0), Val::number(0), Val::number(buttons), Val::number(1.0 / 30.0)});
    };
    for (int i = 0; i < 40; i++) tick();
    L.call("Render", {Val::number(id), Val::number(-1)});
    Val b = Val::table();
    L.call("Batches", {Val::number(id), b});
    int n = (int)b.tab->field("count").num, tris = 0, untex = 0, others = 0;
    for (int i = 1; i <= n; i++) {
        Val e = b.tab->at(i);
        if (e.type != Type::Table) continue;
        if (e.tab->field("archive").num == SA1_ARCHIVE_SKIN) {
            tris += (int)e.tab->field("tris").num;
        } else if (e.tab->field("archive").num < 0) {
            untex++;
        } else {
            others++;
        }
    }
    CHECK(tris == 1015 && untex == 0, "his batches keep their textures (session.cpp): %d triangles on archive 61 (1015), %d untextured, %d of other archives (the blob)", tris, untex, others);
    std::vector<Val> t0 = L.call("Texture", {Val::number(0), Val::number(6), Val::number(61)});
    std::string n6 = t0.size() >= 1 && t0[0].type == Type::Table ? t0[0].tab->field("name").str : "";
    CHECK(n6.find("msblue") != std::string::npos, "gsa1.Texture(0, 6, 61), position 6 of keep, id 101: %s (msblue)", n6.c_str());
    // the voice
    std::vector<Val> sv = L.call("SetVoiceless", {Val::number(id), Val::boolean(true)});
    CHECK(sv.size() == 1 && sv[0].b, "gsa1.SetVoiceless(id, true)");
    std::vector<Val> so = L.call("SetCharOption", {Val::number(id), Val::number((double)SA1_COPT_SKIN_ANIM), Val::number(3)});
    CHECK(so.size() == 1 && so[0].b, "gsa1.SetCharOption(id, COPT_SKIN_ANIM, 3): true (%s)", str_of(so, 1).c_str());
    // the seam itself: a hit's voice stays out of the mixer, counted (Session::admit_sound)
    {
        gsa1::Character *c = se->get((int32_t)id);
        uint64_t before = c ? c->voices_muted : 0;
        sa1_character_add_rings(se->ctx(), (sa1_character_id)id, 5);
        sa1_damage dm;
        std::memset(&dm, 0, sizeof dm);
        dm.struct_size = sizeof dm;
        sa1_character_damage(se->ctx(), (sa1_character_id)id, &dm);
        for (int i = 0; i < 60; i++) tick();
        uint64_t muted = c ? c->voices_muted : 0;
        CHECK(c != nullptr && muted > before, "T2 a hit, voiceless: %llu of his voices stayed out of the mixer (Session::admit_sound)", (unsigned long long)(muted - before));
        L.call("SetVoiceless", {Val::number(id), Val::boolean(false)});
        uint64_t held = c ? c->voices_muted : 0;
        sa1_character_damage(se->ctx(), (sa1_character_id)id, &dm);
        for (int i = 0; i < 60; i++) tick();
        CHECK(c != nullptr && c->voices_muted == held, "T2 with his voice on, none is held back");
    }
    L.call("Destroy", {Val::number(id)});

    // ---- T9: the screen's holder (RM.4) ----------------------------------------------------------------------------------------
    std::vector<Val> op = L.call("FrontendOpen", {});
    CHECK(op.size() >= 1 && op[0].type == Type::Bool && op[0].b, "FrontendOpen (%s)", str_of(op, 1).c_str());
    auto fe_tick = [&](int frames) {
        for (int i = 0; i < frames; i++) {
            L.call("FrontendTick", {Val::number(1.0 / 60.0), Val::number(0), Val::number(0), Val::number(0)});
        }
    };
    auto fe_count = [&](int &skin_tris, int &skin_tex, int &untex2) {
        skin_tris = skin_tex = untex2 = 0;
        L.call("FrontendRender", {});
        Val o = Val::table();
        L.call("FrontendBatches", {o});
        int c = (int)o.tab->field("count").num;
        for (int i = 1; i <= c; i++) {
            Val e = o.tab->at(i);
            if (e.type != Type::Table) continue;
            if (e.tab->field("archive").num == SA1_ARCHIVE_SKIN) {
                skin_tris += (int)e.tab->field("tris").num;
                skin_tex += e.tab->field("tex").num >= 0;
            } else if (e.tab->field("archive").num < 0) {
                untex2++;
            }
        }
    };
    int st0, tx0, un0;
    fe_tick(30);
    fe_count(st0, tx0, un0);
    std::vector<Val> on = L.call("FrontendSkin", {skin_desc(), Val::boolean(true)});
    CHECK(on.size() >= 1 && on[0].type == Type::Bool && on[0].b, "gsa1.FrontendSkin(entry, true) (%s)", str_of(on, 1).c_str());
    int st1, tx1, un1;
    fe_tick(2);
    fe_count(st1, tx1, un1);
    std::vector<Val> off = L.call("FrontendSkin", {});
    int st2, tx2, un2;
    fe_tick(2);
    fe_count(st2, tx2, un2);
    CHECK(st0 == 0 && st1 == 1015 && tx1 > 0 && un1 == 0 && st2 == 0,
          "T9 RM.4: Character Select: without it no draw of archive 61 (%d triangles), with it %d triangles in %d batches, every one with its texture (%d untextured); off again %d",
          st0, st1, tx1, un1, st2);
    L.call("FrontendClose", {});
    return finish();
#endif
}
