// feat_question_binding_test: the "?" through the module's Lua functions (round 0.9.9; sadc docs/research/gsa1_099_plan.md 5.5, 5.10, 6.5 tasks 1, 9;
// playable099.md 5.3, 7.4). Linked like binding_test (the module's objects, libsa1, the mock Lua stack of tests/mock_lua.hpp) by build.py, run
// with --gdi GAME.gdi; gm_construct from the Garry's Mod install gives gsa1.Create its world, a flat floor of its own is what it stands on.
//
//   feat_question_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
//   * THE API PART runs whenever libsa1.h has SA1_API_QUESTION: gsa1.FEATURES.super = 5, gsa1.SUPER's CREATE_QUESTION, ARCHIVE_QUESTION,
//     COPT_QUESTION_SPIN are libsa1's numbers; it writes build/<target>/question_api.txt (tests/feat_question_test.lua checks its mock against it).
//   * THE BEHAVIOUR PART prints exactly one line "SKIP behaviour: question is not built yet" and passes while libsa1 answers that text (5.3).
//     Otherwise: a "?" batch is textured (session.cpp's textured test: WITHOUT IT THE "?" COMES OUT UNTEXTURED WITH NO ERROR): archive 62, texture 7,
//     sphere-mapped, 692 triangles, no other body draw; gsa1.Texture(8, 7, 62) is CS_CE_TX, (8, 10, 62) sstx_body (any case), (8, 11, 62) none;
//     gsa1.SetCharOption(id, COPT_QUESTION_SPIN, 0 / 1); the flag on another kind refused; a plain Super Sonic next to it draws no batch of
//     archive 62 and still has his own; TextureArchives(8) stays without archive 62.
//   * A1 (the plan's addendum; the owner: "the matcap texture has been scaled down and it's repeating while being a reflection"; no lane had seen the
//     module's real output): for the character AND for the menu's "?" (gsa1.FrontendRender), through the real render path: PrepareView / EmitBatch
//     with several views and frames: every emitted UV in 0..1 and equal to the sphere map's rule of the emitted, unit-length normal: nothing scales
//     it; the batch's address mode is the clamped one, both bits; the runs of the textures that draw (CS_CE_TX 256 x 32, sstx_body) paint each texel
//     at most once, inside its size, with the decoded colour, and sum up to the texture: no tiling fill. tests/feat_question_test.lua has the Lua half.
//
// question_api.txt's records, one per line, tab-separated:
//   feature super <version>       const <NAME> <number>       behaviour <RAN | SKIP> <what>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#include <algorithm>
#include <cctype>
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
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

namespace {

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1.0;
}

bool refused(const std::vector<Val> &r)
{
    return r.size() >= 2 && (r[0].type == Type::Nil || (r[0].type == Type::Bool && !r[0].b)) && r[1].type == Type::String && !r[1].str.empty();
}

// what a sphere-mapped batch's emitted vertices are: UVs and normals, by the rule of session.cpp's prepare_view
struct Sphere {
    size_t verts = 0;
    double umin = 9, umax = -9, vmin = 9, vmax = -9, off_rule = 0, off_unit = 0;
    int bad = 0;
};
void sphere_add(Sphere &s, const float R[3], const float U[3])
{
    size_t n = g_mesh.vuv.size() / 2;
    s.bad += g_mesh.bad;
    for (size_t i = 0; i < n; i++) {
        double u = g_mesh.vuv[i * 2], v = g_mesh.vuv[i * 2 + 1];
        double nx = g_mesh.vn[i * 3], ny = g_mesh.vn[i * 3 + 1], nz = g_mesh.vn[i * 3 + 2];
        s.umin = std::min(s.umin, u);
        s.umax = std::max(s.umax, u);
        s.vmin = std::min(s.vmin, v);
        s.vmax = std::max(s.vmax, v);
        s.off_rule = std::max(s.off_rule, std::fabs(u - (0.5 + 0.5 * (nx * R[0] + ny * R[1] + nz * R[2]))));
        s.off_rule = std::max(s.off_rule, std::fabs(v - (0.5 - 0.5 * (nx * U[0] + ny * U[1] + nz * U[2]))));
        s.off_unit = std::max(s.off_unit, std::fabs(std::sqrt(nx * nx + ny * ny + nz * nz) - 1.0));
    }
    s.verts += n;
}
bool sphere_ok(const Sphere &s)
{
    return s.verts > 0 && s.bad == 0 && s.umin >= -0.002 && s.umax <= 1.002 && s.vmin >= -0.002 && s.vmax <= 1.002 && s.off_rule < 0.002 && s.off_unit < 0.002;
}

// the module's runs of one texture against its decoded pixels (10 bytes a run: x, y, length as little-endian 16-bit, then RGBA). pixel(x, y, out)
template <typename F>
bool runs_paint_the_texture(const Val &t, F pixel, std::string &why)
{
    int w = (int)t.tab->field("w").num, h = (int)t.tab->field("h").num, nr = (int)t.tab->field("nruns").num;
    const std::string &runs = t.tab->field("runs").str;
    if (w <= 0 || h <= 0 || runs.size() != (size_t)nr * 10u) {
        why = gsa1::format("%d x %d, %d runs in %zu bytes", w, h, nr, runs.size());
        return false;
    }
    std::vector<uint8_t> seen((size_t)w * (size_t)h, 0);
    int painted = 0, wrong = 0, twice = 0, outside = 0, empty_left = 0;
    for (int r = 0; r < nr; r++) {
        const uint8_t *b = (const uint8_t *)runs.data() + (size_t)r * 10u;
        int x = b[0] + b[1] * 256, y = b[2] + b[3] * 256, l = b[4] + b[5] * 256;
        if (y >= h || x + l > w) {
            outside++;
            continue;
        }
        for (int i = 0; i < l; i++) {
            size_t k = (size_t)y * (size_t)w + (size_t)(x + i);
            twice += seen[k] ? 1 : 0;
            seen[k] = 1;
            painted++;
            uint8_t px[4];
            if (!pixel(x + i, y, px) || px[0] != b[6] || px[1] != b[7] || px[2] != b[8] || px[3] != b[9]) wrong++;
        }
    }
    // what no run paints is (0, 0, 0, 0) on the disc (the module leaves those out; the target is cleared to them)
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint8_t px[4];
            if (!seen[(size_t)y * (size_t)w + (size_t)x] && (!pixel(x, y, px) || px[0] || px[1] || px[2] || px[3])) empty_left++;
        }
    }
    why = gsa1::format("%d x %d, %d runs, %d texels painted, %d twice, %d runs outside, %d wrong colours, %d left out that are not empty", w, h, nr, painted, twice, outside, wrong, empty_left);
    return twice == 0 && outside == 0 && wrong == 0 && empty_left == 0 && painted > 0;
}

std::string lower(std::string s)
{
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); });
    return s;
}

#if defined(SA1_API_QUESTION)
Val extras(double create_flags, double super_flags, double start_rings)
{
    Val t = Val::table();
    t.tab->set(Val::string("create_flags"), Val::number(create_flags));
    t.tab->set(Val::string("super_flags"), Val::number(super_flags));
    t.tab->set(Val::string("start_rings"), Val::number(start_rings));
    return t;
}

// a flat SOLID floor (host space, z up) at z = 0, of 256-HU tiles
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
    std::printf("G-SA1 feat_question_binding_test\n");
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_question_appdata");
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
#if !defined(SA1_API_QUESTION)
    Val K0 = g.type == Type::Table ? g.tab->field("SUPER") : Val();
    CHECK(K0.type != Type::Table || K0.tab->field("CREATE_QUESTION").type == Type::Nil,
          "libsa1.h has no SA1_API_QUESTION: no gsa1.SUPER.CREATE_QUESTION");
    return finish();
#else
    if (g.type != Type::Table) {
        CHECK(false, "the gsa1 table");
        return 1;
    }
    // ---- the API part --------------------------------------------------------------------------------------------------------
    std::vector<std::string> api;
    auto write_api = [&](const char *behaviour) {
        std::string path = gsa1::join_path(self.empty() ? "." : self, "question_api.txt");
        std::string text = "# G-SA1 question_api.txt: the module contract of round 0.9.9 (sadc docs/research/gsa1_099_plan.md 5.5), written by\n"
                           "# tests/feat_question_binding_test.cpp from the module as built against this target's build/deps/include/libsa1.h (" +
                           std::string(sa1_version_string()) + ")\n";
        for (const std::string &r : api) text += r + "\n";
        text += std::string("behaviour\t") + behaviour + "\n";
        std::FILE *f = std::fopen(path.c_str(), "wb");
        bool ok = f && std::fwrite(text.data(), 1, text.size(), f) == text.size();
        if (f) std::fclose(f);
        CHECK(ok, "question_api.txt written: %s (%zu records)", path.c_str(), api.size() + 1);
    };
    Val feats = g.tab->field("FEATURES"), K = g.tab->field("SUPER");
    double fsuper = feats.type == Type::Table ? feats.tab->field("super").num : -1.0;
    CHECK(fsuper == 5.0, "gsa1.FEATURES.super = %g", fsuper);
    api.push_back(gsa1::format("feature\tsuper\t%.0f", fsuper));
    struct { const char *name; double want; } consts[] = {
        {"CREATE_QUESTION", (double)SA1_CREATE_QUESTION}, {"ARCHIVE_QUESTION", (double)SA1_ARCHIVE_QUESTION},
        {"COPT_QUESTION_SPIN", (double)SA1_COPT_QUESTION_SPIN},
    };
    bool const_ok = K.type == Type::Table;
    for (const auto &c : consts) {
        Val v = K.type == Type::Table ? K.tab->field(c.name) : Val();
        const_ok = const_ok && v.type == Type::Number && v.num == c.want;
        api.push_back(gsa1::format("const\t%s\t%.0f", c.name, c.want));
    }
    CHECK(const_ok && SA1_CREATE_QUESTION == 0x2000u && SA1_ARCHIVE_QUESTION == 62u && SA1_COPT_QUESTION_SPIN == 8u,
          "gsa1.SUPER.CREATE_QUESTION 0x2000, ARCHIVE_QUESTION 62, COPT_QUESTION_SPIN 8: libsa1's numbers");
    if (gdi.empty()) {
        std::printf("  info  no disc: the behaviour part needs --gdi\n");
        write_api("SKIP\tno disc");
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
    if (ist != "ready") {
        write_api("SKIP\tno disc");
        return finish();
    }
    std::string map;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
        std::printf("  info  no gm_construct (%s): the behaviour part is skipped\n", bsp.c_str());
        write_api("SKIP\tno gm_construct");
        return finish();
    }
    std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct) (Create needs a world)");
    gsa1::Session *se = gsa1::mod::session();
    CHECK(se && se->set_world(flat_floor(4096.0f), err), "a flat SOLID floor (%s)", err.c_str());

    // ---- the behaviour part --------------------------------------------------------------------------------------------------------
    const double kFlag = (double)SA1_CREATE_QUESTION;
    const double kKeep = (double)SA1_SUPER_KEEP_AT_ZERO, kNoDrain = (double)SA1_SUPER_NO_DRAIN;
    auto make_q = [&]() {
        return L.call("Create", {Val::number(8), Val::vector(0, 0, 8), Val::number(0), Val(), Val(), extras(kFlag, kKeep + kNoDrain, 50)});
    };
    // the archive before the first "?": not loaded, and archive 62 is never counted
    std::vector<Val> ta = L.call("TextureArchives", {Val::number(8)});
    int listed = 0, named = 0;
    for (int i = 1; ta.size() == 1 && ta[0].type == Type::Table && i <= 64; i++) {
        Val e = ta[0].tab->at(i);
        if (e.type == Type::Table) {
            listed++;
            if (lower(e.tab->field("name").str).find("chsel") != std::string::npos) named++;
        }
    }
    CHECK(listed > 0 && listed < 62 && named == 0, "TextureArchives(8): %d archives, none of them the menu's: a plain Super Sonic's list is untouched", listed);
    std::vector<Val> r = make_q();
    double q = num_of(r, 0);
    if (q <= 0.0 && str_of(r, 1).find("not built yet") != std::string::npos) {
        std::printf("SKIP behaviour: question is not built yet\n");
        write_api("SKIP\tquestion is not built yet");
        return finish();
    }
    CHECK(q > 0.0 && L.st.empty(), "gsa1.Create(8, ..., {create_flags = CREATE_QUESTION, ...}) = id %.0f (%s)", q, str_of(r, 1).c_str());
    if (q <= 0.0) {
        write_api("SKIP\tthe create failed");
        return finish();
    }
    auto tick = [&](double id, double buttons = 0.0) {
        return L.call("Tick", {Val::number(id), Val::number(0), Val::number(0), Val::number(0), Val::number(buttons), Val::number(1.0 / 30.0)});
    };
    for (int i = 0; i < 40; i++) tick(q);
    struct Draws { int n = 0, q_batches = 0, q_tris = 0, q_tex = -1, q_flags = 0, untextured = 0, other = 0; double q_wrap = -1; };
    auto draws = [&](double id) {
        Draws d;
        L.call("Render", {Val::number(id), Val::number(-1)});
        Val b = Val::table();
        L.call("Batches", {Val::number(id), b});
        d.n = (int)b.tab->field("count").num;
        for (int i = 1; i <= d.n; i++) {
            Val e = b.tab->at(i);
            if (e.type != Type::Table) continue;
            if (e.tab->field("archive").num == SA1_ARCHIVE_QUESTION) {
                d.q_batches++;
                d.q_tris += (int)e.tab->field("tris").num;
                d.q_tex = (int)e.tab->field("tex").num;
                d.q_flags = (int)e.tab->field("flags").num;
                d.q_wrap = e.tab->field("wrap").num;
            } else if (e.tab->field("archive").num < 0) {
                d.untextured++;
            } else {
                d.other++;
            }
        }
        return d;
    };
    Draws dq = draws(q);
    CHECK(dq.q_batches == 1 && dq.q_tris == 692 && dq.q_tex == 7 && (dq.q_flags & SA1_DRAW_ENV_MAP) != 0 && dq.untextured == 0,
          "a \"?\" batch is textured (session.cpp): archive 62, texture %d, %d triangles, flags 0x%X, address mode %g; %d untextured draws, %d of other "
          "archives (the blob)", dq.q_tex, dq.q_tris, dq.q_flags, dq.q_wrap, dq.untextured, dq.other);
    // the names of the disc's archive
    std::vector<Val> t7 = L.call("Texture", {Val::number(8), Val::number(7), Val::number(62)});
    std::vector<Val> t10 = L.call("Texture", {Val::number(8), Val::number(10), Val::number(62)});
    std::vector<Val> t11 = L.call("Texture", {Val::number(8), Val::number(11), Val::number(62)});
    std::string n7 = t7.size() >= 1 && t7[0].type == Type::Table ? t7[0].tab->field("name").str : "";
    std::string n10 = t10.size() >= 1 && t10[0].type == Type::Table ? t10[0].tab->field("name").str : "";
    CHECK(lower(n7) == "cs_ce_tx" && lower(n10) == "sstx_body" && refused(t11),
          "gsa1.Texture(8, 7, 62) is %s, (8, 10, 62) is %s, (8, 11, 62) refused (S.QUESTION_TEXTURES = 11)", n7.c_str(), n10.c_str());
    // the spin, at once
    double spin = K.tab->field("COPT_QUESTION_SPIN").num;
    std::vector<Val> s0 = L.call("SetCharOption", {Val::number(q), Val::number(spin), Val::number(0)});
    tick(q);
    Draws d0 = draws(q);
    std::vector<Val> s1 = L.call("SetCharOption", {Val::number(q), Val::number(spin), Val::number(1)});
    tick(q);
    Draws d1 = draws(q);
    CHECK(s0.size() >= 1 && s0[0].type == Type::Bool && s0[0].b && s1.size() >= 1 && s1[0].b && d0.q_tris == 692 && d1.q_tris == 692,
          "gsa1.SetCharOption(id, COPT_QUESTION_SPIN, 0 / 1): true (%s), the \"?\" still draws", str_of(s0, 1).c_str());
    // a plain Super Sonic next to it
    std::vector<Val> r8 = L.call("Create", {Val::number(8), Val::vector(64, 0, 8), Val::number(0), Val(), Val(), extras(0, kNoDrain, 50)});
    double plain = num_of(r8, 0);
    CHECK(plain > 0.0, "a plain Super Sonic next to it (id %.0f)", plain);
    if (plain > 0.0) {
        for (int i = 0; i < 40; i++) tick(plain);
        Draws dp = draws(plain);
        CHECK(dp.q_batches == 0 && dp.other > 0, "the plain Super Sonic: no batch of archive 62, %d of his own", dp.other);
        L.call("Destroy", {Val::number(plain)});
    }
    // the flag on another kind (libsa1's rule; the module passes the flag: kCreateExtraFlags)
    Val flag_only = Val::table();
    flag_only.tab->set(Val::string("create_flags"), Val::number(kFlag));
    std::vector<Val> rs = L.call("Create", {Val::number(0), Val::vector(0, 64, 8), Val::number(0), Val(), Val(), flag_only});
    CHECK(refused(rs) && str_of(rs, 1).find("only kind 8") != std::string::npos, "the flag on a Sonic: refused (%s)", str_of(rs, 1).c_str());
    // A1: the character, through the real render path, spinning, from several views
    {
        install_mesh_library(L);
        static const float views[4][6] = {{0, -1, 0, 0, 0, 1}, {1, 0, 0, 0, 0, 1}, {0.7071068f, -0.7071068f, 0, 0, 0, 1}, {0, -1, 0, 0.7071068f, 0, 0.7071068f}};
        Sphere sp;
        int wrap_ok = 0, frames_seen = 0;
        for (int f = 0; f < 45; f++) {
            tick(q);
            L.call("Render", {Val::number(q), Val::number(-1)});
            Val b = Val::table();
            L.call("Batches", {Val::number(q), b});
            int nb = (int)b.tab->field("count").num;
            for (int i = 1; i <= nb; i++) {
                Val e = b.tab->at(i);
                if (e.type != Type::Table || e.tab->field("archive").num != SA1_ARCHIVE_QUESTION) continue;
                frames_seen++;
                wrap_ok += ((int)e.tab->field("wrap").num & 3) == 3 ? 1 : 0;
                for (const auto &vw : views) {
                    L.call("PrepareView", {Val::number(q), Val::vector(100, 100, 100), Val::vector(vw[0], vw[1], vw[2]), Val::vector(vw[3], vw[4], vw[5]),
                                           Val::boolean(false), Val::boolean(true), Val::number(2), Val::boolean(true)});
                    g_mesh = MeshRec();
                    L.call("EmitBatch", {Val::number(q), Val::number(i)});
                    sphere_add(sp, &vw[0], &vw[3]);
                }
            }
        }
        CHECK(frames_seen == 45 && wrap_ok == 45, "A1, the character: the \"?\" batch's address mode has both clamp bits in %d of %d frames", wrap_ok, frames_seen);
        CHECK(sphere_ok(sp), "A1, the character, 45 frames x 4 views, %zu vertices: u %.4f .. %.4f, v %.4f .. %.4f (nothing leaves 0..1), each UV the sphere map's rule of its "
              "normal within %.4f, normals unit length within %.4f: no scale, no repeat in the module's output (%d bad calls)", sp.verts, sp.umin, sp.umax, sp.vmin, sp.vmax, sp.off_rule, sp.off_unit, sp.bad);
        for (int ti : {7, 10}) {
            std::vector<Val> t = L.call("Texture", {Val::number(8), Val::number(ti), Val::number(62)});
            std::string why;
            bool ok = t.size() >= 1 && t[0].type == Type::Table && runs_paint_the_texture(t[0], [&](int x, int y, uint8_t *px) {
                std::vector<Val> p = L.call("TexturePixel", {Val::number(8), Val::number(62), Val::number(ti), Val::number(x), Val::number(y)});
                if (p.size() != 4) return false;
                for (int k = 0; k < 4; k++) px[k] = (uint8_t)p[k].num;
                return true;
            }, why);
            CHECK(ok, "A1, texture %d of archive 62 (%s): the runs paint it exactly, no tiling fill: %s", ti, t.empty() || t[0].type != Type::Table ? "?" : t[0].tab->field("name").str.c_str(), why.c_str());
        }
    }
    // moves: it runs and jumps as Super Sonic, with no fault
    for (int i = 0; i < 30; i++) tick(q, SA1_BUTTON_JUMP);
    std::vector<Val> after = tick(q);
    CHECK(after.size() >= 1 && after[0].type == Type::Number && draws(q).q_tris == 692, "a jump: no fault, the \"?\" still draws");
    L.call("Destroy", {Val::number(q)});
    // A1: the menu's "?", the screen's own world: gsa1.FrontendRender on slot 6
#if defined(GSA1_HAS_FRONTEND)
    {
        Val oa = Val::table();
        oa.tab->set(Val::string("slot"), Val::number(6));
        oa.tab->set(Val::string("language"), Val::number(1));
        oa.tab->set(Val::string("dialog"), Val::boolean(false));
        std::vector<Val> op = L.call("FrontendOpen", {oa});
        CHECK(!op.empty() && op[0].type == Type::Bool && op[0].b, "A1, the menu: FrontendOpen on slot 6 (%s)", str_of(op, 1).c_str());
        Val evs = Val::table();
        for (int i = 0; i < 140; i++) {
            L.call("FrontendTick", {Val::number(1.0 / 60.0 + 1e-6), Val::number(0), Val::number(0), Val::number(0)});
            L.call("FrontendEvents", {evs});
        }
        static const float views[3][6] = {{0, -1, 0, 0, 0, 1}, {1, 0, 0, 0, 0, 1}, {0.7071068f, -0.7071068f, 0, 0, 0, 1}};
        Sphere sp;
        int seen = 0, wrap_ok = 0, tex = -1, arch = -1, flags = 0;
        double kind = -1;
        for (int f = 0; f < 45; f++) {
            L.call("FrontendTick", {Val::number(1.0 / 60.0 + 1e-6), Val::number(0), Val::number(0), Val::number(0)});
            L.call("FrontendEvents", {evs});
            std::vector<Val> rd = L.call("FrontendRender", {});
            kind = num_of(rd, 2);
            Val b = Val::table();
            L.call("FrontendBatches", {b});
            int nb = (int)b.tab->field("count").num;
            for (int i = 1; i <= nb; i++) {
                Val e = b.tab->at(i);
                if (e.type != Type::Table || !((int)e.tab->field("flags").num & SA1_DRAW_ENV_MAP)) continue;
                seen++;
                arch = (int)e.tab->field("archive").num;
                tex = (int)e.tab->field("tex").num;
                flags = (int)e.tab->field("flags").num;
                wrap_ok += ((int)e.tab->field("wrap").num & 3) == 3 ? 1 : 0;
                for (const auto &vw : views) {
                    L.call("FrontendPrepareView", {Val::vector(100, 100, 100), Val::vector(vw[0], vw[1], vw[2]), Val::vector(vw[3], vw[4], vw[5]), Val::boolean(false), Val::boolean(true),
                                                   Val::number(2), Val::boolean(true)});
                    g_mesh = MeshRec();
                    L.call("FrontendEmitBatch", {Val::number(i)});
                    sphere_add(sp, &vw[0], &vw[3]);
                }
            }
        }
        CHECK(seen == 45 && wrap_ok == 45 && tex == 7, "A1, the menu: 45 frames, kind %g: the \"?\" draw is archive %d, texture %d, flags 0x%X, its address mode has both clamp bits in %d of %d frames",
              kind, arch, tex, flags, wrap_ok, seen);
        CHECK(sphere_ok(sp), "A1, the menu, 45 frames x 3 views, %zu vertices: u %.4f .. %.4f, v %.4f .. %.4f, each UV the sphere map's rule of its normal within %.4f, normals unit length within "
              "%.4f: no scale, no repeat (%d bad calls)", sp.verts, sp.umin, sp.umax, sp.vmin, sp.vmax, sp.off_rule, sp.off_unit, sp.bad);
        for (int ti : {7, 10}) {
            std::vector<Val> t = L.call("FrontendTexture", {Val::number(ti), Val::number(arch)});
            std::string why;
            bool ok = t.size() >= 1 && t[0].type == Type::Table && runs_paint_the_texture(t[0], [&](int x, int y, uint8_t *px) {
                std::vector<Val> p = L.call("FrontendTexturePixel", {Val::number(arch), Val::number(ti), Val::number(x), Val::number(y)});
                if (p.size() != 4) return false;
                for (int k = 0; k < 4; k++) px[k] = (uint8_t)p[k].num;
                return true;
            }, why);
            CHECK(ok, "A1, the menu's texture %d of archive %d (%s): the runs paint it exactly, no tiling fill: %s", ti, arch, t.empty() || t[0].type != Type::Table ? "?" : t[0].tab->field("name").str.c_str(), why.c_str());
        }
        L.call("FrontendClose", {});
    }
#endif
    write_api("RAN\tquestion");
    return finish();
#endif
}
