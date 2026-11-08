// feat_skins_binding_test: Metal Sonic through the module's Lua functions (round 0.9.9f; sadc docs/research/metal099e.md 7, T2, T6, T9; RM.4).
//
//   feat_skins_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
//   * THE API PART runs whenever libsa1.h has SA1_API_SKIN: gsa1.SUPER's CREATE_SKIN, ARCHIVE_SKIN, COPT_SKIN_ANIM, SKIN_ANIM_* are libsa1's numbers; voice_class by its table (T2).
//   * THE BEHAVIOUR PART, with the disc: gsa1.Create(0, ..., {create_flags = CREATE_SKIN, skin = the flat entry}): his batches keep their textures of archive 61, 1,015 triangles, gsa1.SetVoiceless; on Character
//     Select gsa1.FrontendSkin: with the skin on a draw of archive 61 in the screen's holder keeps its texture, with it off none is there (T9, RM.4: white on this screen only).
//   * 1.0.0 beta 1 (libsa1 SA1_API_SKIN 3; sadc docs/research/gsa1_100_select.md 7.2 T9): a skin draws from SA1_ARCHIVE_SKIN_FIRST + its slot (64 .. 79; 61 before); the holder and the follower
//     path keep those textures; gsa1.SkinArchive; gsa1.SUPER's SKIN_ANIM_TRAIL, DRAW_SKIN_TRAIL, ARCHIVE_SKIN_FIRST / _LAST, TEXTURE_VARIANT_SKIN_FIRST; gsa1.CHAROPT.UPGRADE_MODELS; gsa1.FrontendUpgradeModels
//     and gsa1.FrontendState's ring; a draw marked SA1_DRAW_SKIN_TRAIL batches with WRAP_SKIN_TRAIL and its skin's slot (the variant 16 + slot the addon draws).
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

// a skin's parts' archive: 61 (libsa1 0.5), or SA1_ARCHIVE_SKIN_FIRST .. _LAST (1.0.0 beta 1: one per loaded skin)
bool skin_arch(double a)
{
#if SA1_API_SKIN >= 3
    if (a >= (double)SA1_ARCHIVE_SKIN_FIRST && a <= (double)SA1_ARCHIVE_SKIN_LAST) return true;
#endif
    return a == (double)SA1_ARCHIVE_SKIN;
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
#if SA1_API_SKIN >= 3
    {
        // T9: 1.0.0 beta 1's constants and calls
        CHECK(K.tab->field("SKIN_ANIM_TRAIL").num == 8.0 && K.tab->field("DRAW_SKIN_TRAIL").num == (double)SA1_DRAW_SKIN_TRAIL && K.tab->field("ARCHIVE_SKIN_FIRST").num == 64.0 &&
                  K.tab->field("ARCHIVE_SKIN_LAST").num == 79.0 && K.tab->field("TEXTURE_VARIANT_SKIN_FIRST").num == 16.0 && K.tab->field("WRAP_SKIN_TRAIL").num == (double)gsa1::WRAP_SKIN_TRAIL &&
                  K.tab->field("WRAP_SKIN_SLOT_SHIFT").num == 9.0,
              "T9 gsa1.SUPER.SKIN_ANIM_TRAIL 8, DRAW_SKIN_TRAIL, ARCHIVE_SKIN_FIRST 64 / _LAST 79, TEXTURE_VARIANT_SKIN_FIRST 16, WRAP_SKIN_TRAIL and its slot's shift");
        Val C = g.tab->field("CHAROPT");
        CHECK(C.type == Type::Table && C.tab->field("UPGRADE_MODELS").num == 5.0 && C.tab->field("UPGRADE_MODELS_ON").num == 2147483648.0 && C.tab->field("UPGRADE_MODELS_ALL").num == (double)0xF1FFFu,
              "T9 gsa1.CHAROPT.UPGRADE_MODELS 5, UPGRADE_MODELS_ON 0x80000000, UPGRADE_MODELS_ALL 0xF1FFF");
        CHECK(g.tab->field("SkinArchive").type == Type::Function && g.tab->field("FrontendUpgradeModels").type == Type::Function, "T9 gsa1.SkinArchive and gsa1.FrontendUpgradeModels exist");
        std::vector<Val> bad = L.call("FrontendUpgradeModels", {Val::number(0), Val::number(-1)});
        std::vector<Val> bad2 = L.call("SetGameOption", {Val::number(1), Val::number(5), Val::number(4294967296.0)});
        CHECK(num_of(bad, 0) < 0.0 && str_of(bad, 2) == "bad_argument" && str_of(bad2, 2) == "bad_argument", "T9 a value outside 0 .. 4294967295: bad_argument (%s, %s)", str_of(bad, 2).c_str(), str_of(bad2, 2).c_str());
        // the trail: a draw libsa1 marked SA1_DRAW_SKIN_TRAIL batches with WRAP_SKIN_TRAIL + its skin's slot, never merged with the game-coloured one; the skin's archives keep their textures
        gsa1::Session probe;
        gsa1::Character c;
        c.kind = 0;
        c.num_archives = 8;
        c.create_extra = SA1_CREATE_SKIN;
        c.skin_slot = 1;
        c.r_triangles = 3;
        sa1_draw d;
        std::memset(&d, 0, sizeof d);
        d.prim = SA1_PRIM_TRIANGLES;
        d.count = 1;
        d.archive = 3;
        d.texture = 2;
        d.flags = SA1_DRAW_SKIN_TRAIL;
        c.r_draws.push_back(d);
        d.first = 1;
        d.flags = 0;
        c.r_draws.push_back(d);
        d.first = 2;
        d.archive = 65;
        d.texture = 4;
        c.r_draws.push_back(d);
        probe.rebatch(c);
        uint32_t trail = 0, plain = 0, skinb = 0;
        for (uint32_t i = 0; i < c.batch_count && i < c.batches.size(); i++) {
            const gsa1::RenderBatch &rb = c.batches[i];
            if (rb.archive == 3 && (rb.wrap & gsa1::WRAP_SKIN_TRAIL)) trail = rb.wrap;
            if (rb.archive == 3 && !(rb.wrap & gsa1::WRAP_SKIN_TRAIL)) plain++;
            if (rb.archive == 65 && rb.texture == 4) skinb++;
        }
        CHECK(trail != 0 && ((trail >> gsa1::WRAP_SKIN_SLOT_SHIFT) & 15u) == 1u && plain == 1 && skinb == 1,
              "T9 the trail's draw: WRAP_SKIN_TRAIL with slot 1 (wrap 0x%X), the plain one beside it a batch of its own; archive 65 keeps its texture (%u)", (unsigned)trail, skinb);
        c.skin_slot = -1;
        probe.rebatch(c);
        trail = 0;
        for (uint32_t i = 0; i < c.batch_count && i < c.batches.size(); i++) {
            if (c.batches[i].wrap & gsa1::WRAP_SKIN_TRAIL) trail = c.batches[i].wrap;
        }
        CHECK(trail == 0, "T9 a character whose skin slot is not known: no trail variant (the game's texture)");
    }
#endif
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
        if (skin_arch(e.tab->field("archive").num)) {
            tris += (int)e.tab->field("tris").num;
        } else if (e.tab->field("archive").num < 0) {
            untex++;
        } else {
            others++;
        }
    }
    CHECK(tris == 1015 && untex == 0, "his batches keep their textures (session.cpp): %d triangles on archive 61 (1015), %d untextured, %d of other archives (the blob)", tris, untex, others);
#if SA1_API_SKIN >= 3
    {
        std::vector<Val> sa = L.call("SkinArchive", {Val::number(id)});
        CHECK(num_of(sa, 0) >= 64.0 && num_of(sa, 0) <= 79.0, "T9 gsa1.SkinArchive(id): %.0f (64 + the skin's slot)", num_of(sa, 0));
        gsa1::Character *cc = se->get((int32_t)id);
        CHECK(cc && cc->skin_slot >= 0 && cc->skin_slot == (int32_t)num_of(sa, 0) - 64, "T9 the character knows its skin's slot (%d): its trails' variant 16 + slot", cc ? cc->skin_slot : -9);
    }
#endif
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

#if defined(SA1_API_SKIN) && SA1_API_SKIN >= 2
    // ---- 0.9.9h: a Metal Sonic follower (the owner: "can you add a Metal Sonic follower?"): gsa1.FollowerCreate(0, ..., {skin = the flat entry, voiceless = true}) ----------------------------
    {
        Val F = g.tab->field("FOLLOWER");
        CHECK(F.type == Type::Table && F.tab->field("SKIN").type == Type::Bool && F.tab->field("SKIN").b, "gsa1.FOLLOWER.SKIN: this module dresses followers");
        std::vector<Val> lr = L.call("Create", {Val::number(0), Val::vector(0, 0, 8), Val::number(0)});
        double lead = num_of(lr, 0);
        CHECK(lead > 0.0, "a plain Sonic to follow (%s)", str_of(lr, 1).c_str());
        auto fopts = [&](bool voiceless) {
            Val o = Val::table();
            o.tab->set(Val::string("skin"), skin_desc());
            o.tab->set(Val::string("voiceless"), Val::boolean(voiceless));
            return o;
        };
        std::vector<Val> bad = L.call("FollowerCreate", {Val::number(2), Val::vector(0, -40, 8), Val::number(0), Val::number(lead), fopts(true)});
        CHECK(num_of(bad, 0) <= 0.0 && str_of(bad, 2) == "bad_argument" && str_of(bad, 1).find("kind 0") != std::string::npos, "a skin on a Tails follower: refused by name (%s)", str_of(bad, 1).c_str());
        Val junk = Val::table();
        junk.tab->set(Val::string("skin"), Val::number(3));
        std::vector<Val> bad2 = L.call("FollowerCreate", {Val::number(0), Val::vector(0, -40, 8), Val::number(0), Val::number(lead), junk});
        CHECK(num_of(bad2, 0) <= 0.0 && str_of(bad2, 2) == "bad_argument", "opts.skin that is no table: bad_argument (%s)", str_of(bad2, 1).c_str());
        std::vector<Val> fr = L.call("FollowerCreate", {Val::number(0), Val::vector(0, -40, 8), Val::number(0), Val::number(lead), fopts(true)});
        double fid = num_of(fr, 0);
        CHECK(fid > 0.0, "gsa1.FollowerCreate(0, ..., {skin = ..., voiceless = true}) = id %.0f (%s)", fid, str_of(fr, 1).c_str());
        std::vector<Val> pr = L.call("FollowerCreate", {Val::number(0), Val::vector(0, 40, 8), Val::number(0), Val::number(lead)});
        double pid = num_of(pr, 0);
        CHECK(pid > 0.0, "and a plain Sonic follower beside it = id %.0f (%s)", pid, str_of(pr, 1).c_str());
        if (fid > 0.0 && pid > 0.0) {
            gsa1::Character *fc = se->get((int32_t)fid);
            gsa1::Character *pc = se->get((int32_t)pid);
            CHECK(fc && fc->follower && fc->voiceless && (fc->create_extra & SA1_CREATE_SKIN) && pc && !pc->voiceless && !(pc->create_extra & SA1_CREATE_SKIN),
                  "the follower's Character: voiceless, its batches may draw archive 61 (create_extra); the plain one neither");
            const gsa1::FollowerOpts *ko = se->followers().opts_of((int32_t)fid);
            CHECK(ko && ko->skin == nullptr && ko->skin_worn, "the set keeps no pointer to the create's table (skin_worn only)");
            std::vector<Val> so2 = L.call("SetCharOption", {Val::number(fid), Val::number((double)SA1_COPT_SKIN_ANIM), Val::number(5)});
            CHECK(so2.size() == 1 && so2[0].b, "gsa1.SetCharOption(follower, COPT_SKIN_ANIM, 5): true (%s)", str_of(so2, 1).c_str());
            Val out = Val::table();
            for (int i = 0; i < 60; i++) {
                L.call("Tick", {Val::number(lead), Val::number(0), Val::number(0), Val::number(0), Val::number(0), Val::number(1.0 / 30.0)});
                L.call("FollowersTick", {Val::number(1.0 / 30.0), Val::number(0), Val(), Val(), out});
            }
            auto count = [&](double who, int &skin_tris, int &skin_tex, int &untex, int &body) {
                skin_tris = skin_tex = untex = body = 0;
                Val b2 = Val::table();
                L.call("Batches", {Val::number(who), b2});
                int nb = (int)b2.tab->field("count").num;
                for (int i = 1; i <= nb; i++) {
                    Val e = b2.tab->at(i);
                    if (e.type != Type::Table) continue;
                    if (skin_arch(e.tab->field("archive").num)) {
                        skin_tris += (int)e.tab->field("tris").num;
                        skin_tex += e.tab->field("tex").num >= 0;
                    } else if (e.tab->field("archive").num < 0) {
                        untex++;
                    } else if (e.tab->field("archive").num == 0) {
                        body += (int)e.tab->field("tris").num;
                    }
                }
            };
            int st, tx, un, bd, st2, tx2, un2, bd2;
            count(fid, st, tx, un, bd);
            count(pid, st2, tx2, un2, bd2);
            CHECK(st == 1015 && tx > 0 && un == 0, "the follower's batches: %d triangles on archive 61 (1015) in %d textured batches, %d untextured, %d on archive 0 (the blob)", st, tx, un, bd);
            CHECK(st2 == 0 && bd2 > 900, "the plain follower beside it: Sonic's body, %d triangles on archive 0, none on archive 61", bd2);
            sa1_damage dm;
            std::memset(&dm, 0, sizeof dm);
            dm.struct_size = sizeof dm;
            uint64_t m0 = fc ? fc->voices_muted : 0;
            sa1_character_add_rings(se->ctx(), (sa1_character_id)fid, 5);
            sa1_character_damage(se->ctx(), (sa1_character_id)fid, &dm);
            for (int i = 0; i < 60; i++) {
                L.call("Tick", {Val::number(lead), Val::number(0), Val::number(0), Val::number(0), Val::number(0), Val::number(1.0 / 30.0)});
                L.call("FollowersTick", {Val::number(1.0 / 30.0), Val::number(0), Val(), Val(), out});
            }
            CHECK(fc && fc->voices_muted > m0, "a hit on the follower, voiceless: %llu of its voices stayed out of the mixer", (unsigned long long)(fc ? fc->voices_muted - m0 : 0));
        }
        if (fid > 0.0) L.call("Destroy", {Val::number(fid)});
        if (pid > 0.0) L.call("Destroy", {Val::number(pid)});
        if (lead > 0.0) L.call("Destroy", {Val::number(lead)});
    }
#endif

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
            if (skin_arch(e.tab->field("archive").num)) {
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
#if SA1_API_SKIN >= 3
    {
        Val fs = Val::table();
        std::vector<Val> fsr = L.call("FrontendState", {fs});
        CHECK(fsr.size() >= 1 && fsr[0].type == Type::Table && fs.tab->field("ring").type == Type::Number, "T9 gsa1.FrontendState gives ring (%.0f)", fs.tab->field("ring").num);
        std::vector<Val> um = L.call("FrontendUpgradeModels", {Val::number(0), Val::number(2147483648.0 + 3.0)});
        std::vector<Val> um0 = L.call("FrontendUpgradeModels", {Val::number(0), Val::number(0)});
        CHECK(um.size() >= 1 && um[0].type == Type::Bool && um[0].b && um0.size() >= 1 && um0[0].type == Type::Bool && um0[0].b,
              "T9 gsa1.FrontendUpgradeModels(0, ON + shoes + ring), then 0: true (%s)", str_of(um, 1).c_str());
    }
#endif
    CHECK(st0 == 0 && st1 == 1015 && tx1 > 0 && un1 == 0 && st2 == 0,
          "T9 RM.4: Character Select: without it no draw of archive 61 (%d triangles), with it %d triangles in %d batches, every one with its texture (%d untextured); off again %d",
          st0, st1, tx1, un1, st2);
    L.call("FrontendClose", {});
    return finish();
#endif
}
