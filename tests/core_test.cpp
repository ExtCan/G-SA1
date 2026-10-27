// G-SA1 offline tests (no Garry's Mod needed): the module's core library against a real map and the user's disc.
//
//   core_test [--bsp MAP.bsp] [--gdi GAME.gdi] [--seconds S] [--fuzz N] [--no-chars] [--verbose]
//             [--jitter | --pairs | --climb | --upgrades | --host-input]
//
//   --bsp  default maps\gm_construct.bsp of Garry's Mod's garrysmod folder, found by tests/gmod_paths.hpp (opened read-only)
//   --gdi  default $SA1_TEST_GDI; without a disc the libsa1 parts are skipped
//
// Parts: config grammar, path rules, BSP -> triangles (counts, flags, bounds, displacement seams under both corner
// conventions), parser fuzzing (mutated and truncated copies, in memory), then through gsa1::Session (the code the
// module runs): disc load, GRID collision from the map, Sonic created above info_player_start and driven by a
// scripted input for some seconds (lands, runs, jumps; positions in Hammer units), the render batches (materials,
// winding, effects of every character, interpolation), the texture transfer (every texel of every archive), sound
// (events -> libsa1's mixer -> PCM), the other characters' smoke runs, the upgrades of every character, timings;
// then on synthetic worlds: the module's frame loop at 60 / 144 / 240 fps and uneven frame times (Sonic running and
// spin dashing: the drawn body must not move against the camera, the owner's 0.2 report) and Knuckles climbing a
// wall (the climbing dust's blend state and texture alpha); the frame loop with multi-pair ticks (38-145 ms frames)
// against one-pair ticking, the whole render bit for bit (T3, sadc docs/research/gsa1_060_pops.md 5.6 / R.5.2).
//   --jitter / --pairs / --climb / --upgrades   run only that part (quick checks; --jitter runs T3 too)
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "../src/core/bsp.hpp"
#include "../src/core/config.hpp"
#include "../src/core/paths.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

using namespace gsa1;

static int g_fail = 0, g_checks = 0;
static bool g_verbose = false;
static int g_fuzz_save = -1;           // --fuzz-save N PATH: write mutated copy N to PATH and stop (debugging)
static std::string g_fuzz_save_path;

#define CHECK(cond, ...)                                     \
    do {                                                     \
        g_checks++;                                          \
        if (cond) {                                          \
            std::printf("  ok    ");                         \
        } else {                                             \
            std::printf("  FAIL  ");                         \
            g_fail++;                                        \
        }                                                    \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

#define INFO(...)                                            \
    do {                                                     \
        std::printf("  info  ");                             \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

// ---- 1. config ----------------------------------------------------------------------------------------------
static void test_config()
{
    std::printf("config:\n");
    Config c;
    std::string e;
#ifdef _WIN32
    const std::string good = "D:\\games\\sa1\\Sonic Adventure (US).gdi";
#else
    const std::string good = "/home/me/sa1/Sonic Adventure (US).gdi";
#endif
    CHECK(parse_config("disc = " + good + "\n", c, e) && c.disc == good, "plain 'disc = path' (%s)", e.c_str());
    CHECK(parse_config("\xEF\xBB\xBF# comment\r\n  disc=\"" + good + "\"  \r\n\r\n", c, e) && c.disc == good,
          "BOM, CRLF, comment, quotes, spaces (%s)", e.c_str());
    struct Bad {
        std::string text;
        const char *why;
    };
    std::vector<Bad> bad = {
        {"", "empty file"},
        {"# only a comment\n", "no disc line"},
        {"disc = " + good + "\ndisc = " + good + "\n", "disc twice"},
        {"disk = " + good + "\n", "unknown key"},
        {"Disc = " + good + "\n", "upper-case key"},
        {"disc " + good + "\n", "no '='"},
        {"disc = \"" + good + "\n", "unterminated quote"},
        {"disc = relative\\game.gdi\n", "relative path"},
        {"disc = \\\\server\\share\\game.gdi\n", "UNC path"},
        {"disc = //server/share/game.gdi\n", "UNC path (slashes)"},
        {"disc = \\\\?\\C:\\game.gdi\n", "device path"},
#ifdef _WIN32
        {"disc = C:\\games\\game.gdi:stream\n", "alternate data stream"},
        {"disc = C:\\games\\CON\\game.gdi\n", "DOS device component"},
        {"disc = C:\\games\\..\\game.gdi\n", "'..' component"},
        {"disc = C:\\games\\game.iso\n", "not a .gdi"},
#else
        {"disc = /games/../game.gdi\n", "'..' component"},
        {"disc = /games/game.iso\n", "not a .gdi"},
#endif
        {std::string("disc = ") + good + "\x01\n", "control character"},
        {std::string("disc = ") + good + "\n\xC3\x28\n", "invalid UTF-8"},
        {std::string("disc = ") + good + std::string(1, '\0') + "\n", "NUL byte"},
        {std::string(5000, '#'), "larger than 4096 bytes"},
    };
    int rejected = 0;
    for (const Bad &b : bad) {
        Config cc;
        std::string ee;
        bool ok = parse_config(b.text, cc, ee);
        if (!ok) {
            rejected++;
        } else {
            std::printf("        accepted but should not: %s\n", b.why);
        }
        if (g_verbose) {
            std::printf("        %-28s -> %s\n", b.why, ok ? "ACCEPTED" : ee.c_str());
        }
    }
    CHECK(rejected == (int)bad.size(), "%d of %d malformed or unsafe config files rejected", rejected, (int)bad.size());
    std::string lines;
    for (int i = 0; i < 70; i++) {
        lines += "# x\n";
    }
    CHECK(!parse_config(lines + "disc = " + good + "\n", c, e), "more than 64 lines rejected");
    Config s;
    s.disc = good;
    CHECK(parse_config(serialize_config(s), c, e) && c.disc == good, "serialize_config round trip");
    INFO("config file: %s  (resolved here: %s)", config_file_display(), config_file().empty() ? "?" : "yes");
}

// ---- 2. paths -----------------------------------------------------------------------------------------------
static void test_paths(const std::string &bsp_path)
{
    std::printf("paths:\n");
    int good = 0, bad = 0;
    for (const char *n : {"gm_construct", "gm_flatgrass", "rp_downtown_v4c_v2", "ttt_67thway_v14", "de_dust2", "gm_a+b"}) {
        good += valid_map_name(n) ? 1 : 0;
    }
    for (const char *n : {"", "..", "../maps/gm_construct", "maps\\x", "con", "CON", "aux.x", "a b", "a:b", ".hidden",
                          "gm_construct/..", "x\xC3\xA9"}) {
        bad += valid_map_name(n) ? 0 : 1;
    }
    CHECK(good == 6 && bad == 12, "map names: %d of 6 valid accepted, %d of 12 invalid rejected", good, bad);
    std::string gm;
#ifdef _WIN32
    bool a = garrysmod_dir_from_module("C:\\Steam\\GarrysMod\\garrysmod\\lua\\bin\\gmcl_gsa1_win64.dll", gm) &&
             gm == "C:\\Steam\\GarrysMod\\garrysmod";
    bool b = !garrysmod_dir_from_module("C:\\Steam\\GarrysMod\\bin\\gmcl_gsa1_win64.dll", gm);
#else
    bool a = garrysmod_dir_from_module("/srv/gmod/garrysmod/lua/bin/gmcl_gsa1_linux64.dll", gm) &&
             gm == "/srv/gmod/garrysmod";
    bool b = !garrysmod_dir_from_module("/srv/gmod/bin/gmcl_gsa1_linux64.dll", gm);
#endif
    CHECK(a && b, "garrysmod directory from the module path (lua/bin required)");
    INFO("this binary: %s", self_module_path().c_str());
    std::string gmdir = parent_dir(parent_dir(bsp_path));
    std::string found, searched;
    std::string name = base_name(bsp_path);
    if (ends_with_ci(name, ".bsp")) {
        name = name.substr(0, name.size() - 4);
    }
    bool f = find_map_file(gmdir, name, found, searched);
    CHECK(f && iequals(found, bsp_path), "find_map_file(%s) in %s: %s", name.c_str(), searched.c_str(),
          f ? "found" : "not found");
    CHECK(!find_map_file(gmdir, "../maps/" + name, found, searched), "find_map_file refuses a path as the name");
}

// ---- 3. BSP ----------------------------------------------------------------------------------------------------
struct Spawn {
    float pos[3];
    float yaw;
};

static int edge_point(const BspDispGrid &g, int edge, uint32_t k)
{
    uint32_t n = g.n;
    switch (edge) {
    case 0: return (int)(k * n + 0);              // corner 0 -> 1: column 0
    case 1: return (int)((n - 1) * n + k);        // corner 1 -> 2: last row
    case 2: return (int)(k * n + (n - 1));        // corner 3 -> 2: last column
    default: return (int)(0 * n + k);             // corner 0 -> 3: row 0
    }
}

static void edge_corners(int edge, int &a, int &b)
{
    static const int ca[4] = {0, 1, 3, 0}, cb[4] = {1, 2, 2, 3};
    a = ca[edge];
    b = cb[edge];
}

static float dist3(const float *a, const float *b)
{
    float dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
    return std::sqrt(dx * dx + dy * dy + dz * dz);
}

// shared displacement edges: displaced border points must coincide (sewn) under the right corner convention
static void disp_seams(Bsp &bsp, bool transpose, uint32_t &edges, uint32_t &good, float &worst)
{
    BspWorldOptions o;
    o.disp_transpose = transpose;
    std::vector<BspDispGrid> gs;
    std::string e;
    edges = good = 0;
    worst = 0.0f;
    if (!bsp.displacement_grids(o, gs, e)) {
        return;
    }
    for (size_t i = 0; i < gs.size(); i++) {
        for (size_t j = i + 1; j < gs.size(); j++) {
            if (!gs[i].n || gs[i].n != gs[j].n) {
                continue;
            }
            for (int ei = 0; ei < 4; ei++) {
                int ia, ib;
                edge_corners(ei, ia, ib);
                for (int ej = 0; ej < 4; ej++) {
                    int ja, jb;
                    edge_corners(ej, ja, jb);
                    bool same = dist3(gs[i].corners[ia], gs[j].corners[ja]) < 0.5f &&
                                dist3(gs[i].corners[ib], gs[j].corners[jb]) < 0.5f;
                    bool rev = dist3(gs[i].corners[ia], gs[j].corners[jb]) < 0.5f &&
                               dist3(gs[i].corners[ib], gs[j].corners[ja]) < 0.5f;
                    if (!same && !rev) {
                        continue;
                    }
                    float m = 0.0f;
                    uint32_t n = gs[i].n;
                    for (uint32_t k = 0; k < n; k++) {
                        int pi = edge_point(gs[i], ei, k);
                        int pj = edge_point(gs[j], ej, same ? k : n - 1 - k);
                        m = std::max(m, dist3(&gs[i].pos[(size_t)pi * 3], &gs[j].pos[(size_t)pj * 3]));
                    }
                    edges++;
                    if (m < 1.0f) {
                        good++;
                    }
                    worst = std::max(worst, m);
                }
            }
        }
    }
}

static bool test_bsp(const std::string &bsp_path, std::vector<sa1_collision_tri> &tris, BspWorldStats &st,
                     std::vector<Spawn> &spawns)
{
    std::printf("bsp: %s\n", bsp_path.c_str());
    FileByteSource src;
    std::string e;
    if (!src.open(bsp_path, e)) {
        CHECK(false, "open the map: %s", e.c_str());
        return false;
    }
    Bsp bsp;
    CHECK(bsp.open(src, e), "VBSP header, version %d, map revision %d (%s)", (int)bsp.version(), (int)bsp.revision(),
          e.c_str());
    BspWorldOptions opt;
    bool ok = bsp.build_world(opt, tris, st, e);
    CHECK(ok, "build_world: %u triangles in %.1f ms (%s)", (unsigned)st.tris, st.ms, ok ? "" : e.c_str());
    if (!ok) {
        return false;
    }
    INFO("brushes %u (world model %u: solid %u, water %u, other %u); displacement brushes dropped %u",
         st.brushes, st.world_brushes, st.solid_brushes, st.water_brushes, st.other_brushes, st.displacement_brushes);
    INFO("brush faces %u (degenerate %u, bevel sides %u, sides with a dispinfo field set %u)", st.brush_faces,
         st.degenerate_faces, st.bevel_sides, st.sides_with_dispinfo);
    INFO("displacements %u (%u skipped) -> %u triangles", st.displacements, st.displacements_skipped,
         st.displacement_tris);
    INFO("triangles: solid %u, water %u, no-climb %u (sky %u, clip %u), nodraw %u, kill %u", st.tris_solid,
         st.tris_water, st.tris_noclimb, st.tris_sky, st.tris_clip, st.tris_nodraw, st.tris_kill);
    INFO("world bounds (%.0f %.0f %.0f) .. (%.0f %.0f %.0f) Hammer units", st.mins[0], st.mins[1], st.mins[2],
         st.maxs[0], st.maxs[1], st.maxs[2]);
    CHECK(st.tris > 1000 && st.world_brushes > 100 && st.tris_kill == 2, "plausible counts (map geometry and a kill plane)");
    uint32_t bad = 0, up = 0, down = 0, wall = 0;
    for (const sa1_collision_tri &t : tris) {
        for (int k = 0; k < 3; k++) {
            for (int a = 0; a < 3; a++) {
                if (!std::isfinite(t.v[k][a]) || std::fabs(t.v[k][a]) > 65536.0f) {
                    bad++;
                }
            }
        }
        float e1[3], e2[3];
        for (int a = 0; a < 3; a++) {
            e1[a] = t.v[1][a] - t.v[0][a];
            e2[a] = t.v[2][a] - t.v[0][a];
        }
        float nz = e1[0] * e2[1] - e1[1] * e2[0];
        float nl = std::sqrt((e1[1] * e2[2] - e1[2] * e2[1]) * (e1[1] * e2[2] - e1[2] * e2[1]) +
                             (e1[2] * e2[0] - e1[0] * e2[2]) * (e1[2] * e2[0] - e1[0] * e2[2]) + nz * nz);
        float c = nl > 0 ? nz / nl : 0;
        if (c > 0.7f) {
            up++;
        } else if (c < -0.7f) {
            down++;
        } else {
            wall++;
        }
    }
    CHECK(bad == 0, "every vertex finite and inside +-65536 (%u bad coordinates)", bad);
    INFO("orientation (counter-clockwise normals): %u facing up, %u down, %u walls", up, down, wall);
    uint32_t edges, good;
    float worst;
    disp_seams(bsp, false, edges, good, worst);
    uint32_t tedges, tgood;
    float tworst;
    disp_seams(bsp, true, tedges, tgood, tworst);
    if (edges) {
        CHECK(good * 10 >= edges * 9 && good >= tgood,
              "displacement seams (Valve corner order): %u of %u shared edges sewn (< 1 unit), worst %.2f; transposed "
              "order: %u of %u, worst %.2f", good, edges, worst, tgood, tedges, tworst);
    } else {
        INFO("no shared displacement edges to check");
    }
    std::vector<BspEntity> ents;
    bool eok = bsp.entities(ents, e);
    for (const BspEntity &en : ents) {
        const std::string *cls = en.get("classname");
        if (cls && (*cls == "info_player_start" || *cls == "info_player_deathmatch")) {
            Spawn s;
            float ang[3] = {0, 0, 0};
            if (en.get_vec3("origin", s.pos)) {
                en.get_vec3("angles", ang);
                s.yaw = ang[1] * 3.14159265f / 180.0f;
                spawns.push_back(s);
            }
        }
    }
    CHECK(eok && !ents.empty(), "entity lump: %u entities, %u player starts (%s)", (unsigned)ents.size(),
          (unsigned)spawns.size(), eok ? "" : e.c_str());
    if (!spawns.empty()) {
        INFO("first player start (%.1f %.1f %.1f) yaw %.1f deg", spawns[0].pos[0], spawns[0].pos[1], spawns[0].pos[2],
             spawns[0].yaw * 180.0f / 3.14159265f);
    }
    return true;
}

// ---- 4. fuzz ------------------------------------------------------------------------------------------------------
static uint32_t g_seed = 0x6A5A1u;
static uint32_t rnd()
{
    g_seed = g_seed * 1664525u + 1013904223u;
    return g_seed >> 8;
}

static void test_fuzz(const std::string &bsp_path, int iterations)
{
    std::printf("fuzz: %d mutated copies of the map (in memory)\n", iterations);
    std::string data, e;
    if (!read_small_file(bsp_path, 256u << 20, data, e)) {
        CHECK(false, "read the map: %s", e.c_str());
        return;
    }
    std::vector<uint8_t> buf(data.begin(), data.end());
    // the lumps the parser reads
    const int lumps[] = {0, 1, 3, 5, 6, 7, 10, 12, 13, 14, 17, 18, 19, 26, 33};
    int ok = 0, rejected = 0;
    double t0 = now_ms(), worst_ms = 0.0;
    for (int it = 0; it < iterations; it++) {
        std::vector<std::pair<size_t, uint8_t>> undo;
        auto poke = [&](size_t off, uint8_t v) {
            if (off < buf.size()) {
                undo.push_back({off, buf[off]});
                buf[off] = v;
            }
        };
        int mode = it % 4;
        if (mode == 0) {
            // the lump directory (offsets, lengths, compression field)
            for (int k = 0; k < 4; k++) {
                int l = lumps[rnd() % (sizeof lumps / sizeof lumps[0])];
                poke(8 + 16 * (size_t)l + rnd() % 16, (uint8_t)rnd());
            }
        } else {
            int l = lumps[rnd() % (sizeof lumps / sizeof lumps[0])];
            int32_t ofs, len;
            std::memcpy(&ofs, &buf[8 + 16 * (size_t)l], 4);
            std::memcpy(&len, &buf[8 + 16 * (size_t)l + 4], 4);
            if (len > 0) {
                int n = mode == 1 ? 8 : mode == 2 ? 64 : 512;
                for (int k = 0; k < n; k++) {
                    uint32_t r = rnd();
                    uint8_t v = (r & 3) == 0 ? 0xFF : (r & 3) == 1 ? 0x00 : (r & 3) == 2 ? 0x7F : (uint8_t)(r >> 8);
                    poke((size_t)ofs + rnd() % (uint32_t)len, v);
                }
            }
        }
        size_t len = (it % 7 == 6) ? (size_t)(rnd() % buf.size()) : buf.size();
        if (it == g_fuzz_save) {
            std::string w((const char *)buf.data(), len), werr;
            bool saved = write_file_replace(g_fuzz_save_path, w, werr);
            std::printf("        iteration %d saved to %s: %s\n", it, g_fuzz_save_path.c_str(), saved ? "ok" : werr.c_str());
            return;
        }
        MemoryByteSource ms(buf.data(), len);
        Bsp b;
        std::vector<sa1_collision_tri> t;
        BspWorldStats st;
        std::vector<BspEntity> en;
        double ti = now_ms();
        bool r = b.open(ms, e) && b.build_world(BspWorldOptions(), t, st, e);
        if (b.version()) {
            b.entities(en, e);
        }
        ti = now_ms() - ti;
        worst_ms = std::max(worst_ms, ti);
        if (g_verbose || ti > 5000.0) {
            std::printf("        iteration %d (mode %d%s): %s, %u triangles, %.0f ms\n", it, mode,
                        len < buf.size() ? ", truncated" : "", r ? "parsed" : e.c_str(), (unsigned)t.size(), ti);
            std::fflush(stdout);
        }
        bool sane = true;
        for (const auto &tri : t) {
            for (int k = 0; k < 3; k++) {
                for (int a = 0; a < 3; a++) {
                    if (!std::isfinite(tri.v[k][a]) || std::fabs(tri.v[k][a]) > 65536.0f) {
                        sane = false;
                    }
                }
            }
        }
        if (!sane) {
            std::printf("        iteration %d produced a non-finite or far triangle\n", it);
            g_fail++;
        }
        (r ? ok : rejected)++;
        for (auto it2 = undo.rbegin(); it2 != undo.rend(); ++it2) {
            buf[it2->first] = it2->second;
        }
    }
    CHECK(true, "no crash in %d iterations (%d parsed, %d rejected with a message) in %.1f s", iterations, ok, rejected,
          (now_ms() - t0) / 1000.0);
    // a damaged map must not keep the map job's worker busy for long (the real map takes about 40 ms)
    CHECK(worst_ms < 5000.0, "every mutated copy parsed or rejected within 5 s (slowest %.0f ms)", worst_ms);
    // a few hand-made headers
    const char *names[] = {"empty", "short header", "wrong magic", "version 21", "lump outside the file", "LZMA lump"};
    int handled = 0;
    for (int k = 0; k < 6; k++) {
        std::vector<uint8_t> h(buf.begin(), buf.begin() + 1036);
        size_t n = h.size();
        if (k == 0) {
            n = 0;
        } else if (k == 1) {
            n = 100;
        } else if (k == 2) {
            h[0] = 'X';
        } else if (k == 3) {
            h[4] = 21;
        } else if (k == 4) {
            int32_t big = 0x7FFFFFF0;
            std::memcpy(&h[8 + 16 * 1], &big, 4);
        } else {
            int32_t one = 1;
            std::memcpy(&h[8 + 16 * 1 + 12], &one, 4);
            h.resize(buf.size());
            std::memcpy(h.data() + 1036, buf.data() + 1036, buf.size() - 1036);
            n = h.size();
        }
        MemoryByteSource ms(h.data(), n);
        Bsp b;
        std::vector<sa1_collision_tri> t;
        BspWorldStats st;
        bool r = b.open(ms, e) && b.build_world(BspWorldOptions(), t, st, e);
        if (!r) {
            handled++;
        }
        if (g_verbose || r) {
            std::printf("        %-22s -> %s\n", names[k], r ? "ACCEPTED" : e.c_str());
        }
    }
    CHECK(handled == 6, "%d of 6 hand-made bad headers rejected", handled);
}

// ---- 5. libsa1 through gsa1::Session ----------------------------------------------------------------------------
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__)
#include <xmmintrin.h>
// the control bits (rounding, flush-to-zero, denormals-are-zero, exception masks); the sticky exception flags
// (bits 0-5) are set by any inexact host arithmetic and say nothing about libsa1's save / restore
static unsigned mxcsr() { return _mm_getcsr() & 0xFFC0u; }
#else
static unsigned mxcsr() { return 0; }
#endif

static const char *kind_name(int32_t k)
{
    const char *n = sa1_character_name(k);
    return n ? n : "?";
}

struct RunLog {
    bool landed = false;
    float land_t = -1, land_z = 0;
    float run_dist = 0, jump_rise = 0;
    bool relanded = false;
    uint32_t max_tris = 0, max_groups = 0;
    double tick_sum = 0, tick_max = 0;
    uint32_t ticks = 0;
    uint64_t pairs = 0;
    bool fault = false;
    bool mxcsr_kept = true;
    std::map<uint32_t, uint32_t> events;
};

// one character driven by the script; frame time 1/60 s
static void drive(Session &s, int32_t id, float seconds, float cam_yaw, RunLog &L, bool print)
{
    Character *c = s.get(id);
    const float dt = 1.0f / 60.0f;
    float run_start[3] = {0, 0, 0}, jump_z0 = 0;
    bool run_started = false, jumped = false;
    std::vector<sa1_event> ev;
    int frames = (int)(seconds * 60.0f + 0.5f);
    for (int f = 0; f <= frames; f++) {
        float t = f * dt;
        float sy = 0.0f;
        uint32_t b = 0;
        if (t >= 1.5f && t < 5.5f) {
            sy = 1.0f;
        }
        if (t >= 4.0f && t < 4.25f) {
            b |= SA1_BUTTON_JUMP;
        }
        unsigned m0 = mxcsr();
        sa1_status st = s.tick(id, 0.0f, sy, cam_yaw, b, dt);
        if (st == SA1_OK) {
            st = s.render(id, -1.0f);      // as the module: a render every frame
        }
        if (mxcsr() != m0) {
            L.mxcsr_kept = false;
        }
        c = s.get(id);
        if (st != SA1_OK || !c) {
            std::printf("        tick failed at t=%.2f: %s\n", t, s.last_error().c_str());
            L.fault = true;
            return;
        }
        L.ticks++;
        L.tick_sum += c->tick_ms_last;
        L.tick_max = std::max(L.tick_max, c->tick_ms_last);
        L.pairs += c->pairs_last;
        L.max_tris = std::max(L.max_tris, c->out_triangles);
        L.max_groups = std::max(L.max_groups, c->batch_count);
        s.poll_events(ev);
        for (const sa1_event &e : ev) {
            L.events[e.type]++;
        }
        const float *p = c->st.position;
        bool ground = (c->st.flags & SA1_STATE_ON_GROUND) != 0;
        if (!L.landed && ground) {
            L.landed = true;
            L.land_t = t;
            L.land_z = p[2];
        }
        if (t >= 1.5f && !run_started) {
            std::memcpy(run_start, p, sizeof run_start);
            run_started = true;
        }
        if (t >= 4.0f && !jumped) {
            jumped = true;
            jump_z0 = p[2];
            float dx = p[0] - run_start[0], dy = p[1] - run_start[1];
            L.run_dist = std::sqrt(dx * dx + dy * dy);
        }
        if (jumped && t < 5.5f) {
            L.jump_rise = std::max(L.jump_rise, p[2] - jump_z0);
            if (t > 4.5f && ground) {
                L.relanded = true;
            }
        }
        if (print && (f % 15 == 0)) {
            std::printf("        t %5.2f  pos (%8.1f %8.1f %8.1f) HU  vel (%7.1f %7.1f %7.1f) HU/s  %s  mode %2d  "
                        "action %3d  draws %4u tris / %2u batches%s\n",
                        t, p[0], p[1], p[2], c->st.velocity[0], c->st.velocity[1], c->st.velocity[2],
                        ground ? "ground" : "air   ", (int)c->st.mode, (int)c->st.action, c->out_triangles,
                        c->batch_count, (b & SA1_BUTTON_JUMP) ? "  [jump]" : (sy > 0 ? "  [fwd]" : ""));
        }
    }
}

// ---- rendering, textures, sound ---------------------------------------------------------------------------------
struct Step {
    int frames;          // 1/60 s frames
    float sy;            // stick forward
    uint32_t buttons;
};

// ticks and renders every frame, as the module does; feeds `pcm` (stereo frames, 44.1 kHz) when given
static bool run_script(Session &s, int32_t id, const std::vector<Step> &script, float yaw,
                       std::vector<int16_t> *pcm = nullptr)
{
    std::vector<sa1_event> ev;
    for (const Step &st : script) {
        for (int f = 0; f < st.frames; f++) {
            if (s.tick(id, 0.0f, st.sy, yaw, st.buttons, 1.0f / 60.0f) != SA1_OK) {
                std::printf("        tick: %s\n", s.last_error().c_str());
                return false;
            }
            s.render(id, -1.0f);
            s.poll_events(ev);
            if (pcm) {
                size_t at = pcm->size();
                pcm->resize(at + 735u * 2u);
                s.audio().render(pcm->data() + at, 735u);
            }
        }
    }
    return true;
}

struct Census {
    uint32_t batches = 0, opaque = 0, blended = 0, tris = 0, palette = 0, effect = 0, additive = 0, afterimage = 0,
             alpha_test = 0, use_alpha = 0, env = 0, effect_archive = 0, sprites = 0, lines = 0,
             shadow = 0;   // 0.8: the blob shadow's batches (SA1_DRAW_SHADOW; they carry EFFECT too, not counted there)
    bool order = true;   // blended batches in increasing game order
};

static Census census(const Character &c)
{
    Census k;
    uint32_t last = 0;
    for (uint32_t b = 0; b < c.batch_count; b++) {
        const RenderBatch &rb = c.batches[b];
        k.batches++;
        k.tris += rb.triangles;
        (rb.pass ? k.blended : k.opaque)++;
        k.palette += (rb.flags & SA1_DRAW_PALETTE_LIT) != 0;
        k.effect += (rb.flags & SA1_DRAW_EFFECT) != 0 && !(rb.flags & SA1_DRAW_SHADOW);
        k.shadow += (rb.flags & SA1_DRAW_SHADOW) != 0;
        k.additive += (rb.flags & SA1_DRAW_ADDITIVE) != 0;
        k.afterimage += (rb.all_flags & SA1_DRAW_AFTERIMAGE) != 0;
        k.alpha_test += (rb.flags & SA1_DRAW_ALPHA_TEST) != 0;
        k.use_alpha += (rb.all_flags & SA1_DRAW_USE_ALPHA) != 0;
        k.env += (rb.flags & SA1_DRAW_ENV_MAP) != 0;
        k.effect_archive += rb.archive >= 1 && !(rb.flags & SA1_DRAW_SHADOW);
        k.sprites += (rb.prims & (1u << SA1_PRIM_SPRITES)) != 0;
        k.lines += (rb.prims & (1u << SA1_PRIM_LINES)) != 0;
        if (rb.pass) {
            if (rb.order < last) {
                k.order = false;
            }
            last = rb.order;
        }
    }
    return k;
}

static std::string census_text(const Census &k)
{
    return format("%u batches (%u opaque, %u blended), %u triangles; palette-lit %u, alpha-test %u, USE_ALPHA drawn "
                  "opaque %u, effect %u (effect archives %u, additive %u, sprites %u, lines %u), afterimage %u, env %u, "
                  "shadow %u",
                  k.batches, k.opaque, k.blended, k.tris, k.palette, k.alpha_test, k.use_alpha, k.effect,
                  k.effect_archive, k.additive, k.sprites, k.lines, k.afterimage, k.env, k.shadow);
}

// the prepared vertices for a camera 150 HU in front of the character
static void check_view(Session &s, Character &c, const char *who)
{
    float yaw = c.r_yaw, f[3] = {-std::cos(yaw), -std::sin(yaw), 0.0f};
    float eye[3] = {c.r_pos[0] - 150.0f * f[0], c.r_pos[1] - 150.0f * f[1], c.r_pos[2] + 40.0f};
    float up[3] = {0, 0, 1}, right[3] = {f[1], -f[0], 0.0f};
    s.prepare_view(c, eye, right, up, ViewOptions());
    bool sizes = true, finite = true, white = true;
    uint32_t cw = 0, ccw = 0, facing = 0, sprite_tris = 0;
    float rmax = 0;
    for (uint32_t b = 0; b < c.batch_count; b++) {
        const RenderBatch &rb = c.batches[b];
        size_t nv = (size_t)rb.triangles * 3u;
        sizes = sizes && rb.pos.size() == nv * 3u && rb.nrm.size() == nv * 3u && rb.uv.size() == nv * 2u &&
                rb.col.size() == nv * 4u;
        for (float v : rb.pos) finite = finite && std::isfinite(v);
        for (float v : rb.uv) finite = finite && std::isfinite(v);
        bool lines = (rb.prims & (1u << SA1_PRIM_LINES)) != 0;   // E-102's targeting reaches far
        for (size_t v = 0; v < nv && !lines; v++) {
            float dx = rb.pos[v * 3] - c.r_pos[0], dy = rb.pos[v * 3 + 1] - c.r_pos[1], dz = rb.pos[v * 3 + 2] - c.r_pos[2];
            rmax = std::max(rmax, std::sqrt(dx * dx + dy * dy + dz * dz));
            if (rb.flags & SA1_DRAW_PALETTE_LIT) {
                white = white && rb.col[v * 4] == 255 && rb.col[v * 4 + 1] == 255 && rb.col[v * 4 + 2] == 255;
            }
        }
        bool sprite = (rb.prims & (1u << SA1_PRIM_SPRITES)) != 0 && rb.prims == (1u << SA1_PRIM_SPRITES);
        for (size_t t = 0; t < (size_t)rb.triangles; t++) {
            const float *p = &rb.pos[t * 9], *n = &rb.nrm[t * 9];
            float e1[3] = {p[3] - p[0], p[4] - p[1], p[5] - p[2]}, e2[3] = {p[6] - p[0], p[7] - p[1], p[8] - p[2]};
            float g[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
            float vn[3] = {n[0] + n[3] + n[6], n[1] + n[4] + n[7], n[2] + n[5] + n[8]};
            float d = g[0] * vn[0] + g[1] * vn[1] + g[2] * vn[2];
            if (!rb.pass && (rb.flags & SA1_DRAW_PALETTE_LIT) && !(rb.flags & SA1_DRAW_DOUBLE_SIDED)) {
                (d < 0 ? cw : ccw)++;
            }
            if (sprite) {
                sprite_tris++;
                // in the camera plane: the face normal is parallel to the view direction (either side: sprites
                // are double-sided and may be mirrored)
                float gl = std::sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2]);
                facing += gl > 0 && std::fabs(g[0] * f[0] + g[1] * f[1] + g[2] * f[2]) > 0.99f * gl;
            }
        }
    }
    CHECK(sizes && finite && white && cw > 9 * ccw && rmax < 400.0f && facing == sprite_tris,
          "%s: prepare_view: every batch 3 vertices per triangle, finite; palette-lit vertex RGB white; %u of %u "
          "opaque body triangles wound clockwise seen from outside (Source's front); %u sprite triangles, %u in the "
          "camera plane; farthest vertex (lines aside) %.0f HU from the root", who, cw, cw + ccw, sprite_tris, facing, rmax);
}

// interpolation: render(0), render(1), render(0.5) of a running character
static void test_lerp(Session &s, int32_t id)
{
    Character *c = s.get(id);
    run_script(s, id, {{40, 1.0f, 0}}, c->st.yaw);
    s.render(id, 0.0f);
    std::vector<float> a = c->r_tpos;
    float ra[3] = {c->r_pos[0], c->r_pos[1], c->r_pos[2]};
    s.render(id, 1.0f);
    std::vector<float> b = c->r_tpos;
    float rb[3] = {c->r_pos[0], c->r_pos[1], c->r_pos[2]};
    s.render(id, 0.5f);
    bool interp = c->r_interpolated != 0;
    std::vector<float> m = c->r_tpos;
    float mid = 0, moved = 0, root = 0;
    uint32_t off_arc = 0;
    if (a.size() == b.size() && b.size() == m.size()) {
        // libsa1 interpolates each drawn model's transform (parts turn on arcs, not chords: the spin ball keeps its
        // size): a vertex at alpha 0.5 lies within half its motion of the chord's midpoint
        for (size_t i = 0; i + 2 < m.size(); i += 3) {
            float e2 = 0, c2 = 0;
            for (size_t k = 0; k < 3; k++) {
                float e = m[i + k] - 0.5f * (a[i + k] + b[i + k]), d = b[i + k] - a[i + k];
                e2 += e * e;
                c2 += d * d;
                moved = std::max(moved, std::fabs(d));
            }
            mid = std::max(mid, std::sqrt(e2));
            off_arc += std::sqrt(e2) > 0.5f * std::sqrt(c2) + 0.05f;
        }
    }
    for (int k = 0; k < 3; k++) {
        root = std::max(root, std::fabs(c->r_pos[k] - 0.5f * (ra[k] + rb[k])));
    }
    CHECK(interp && a.size() == m.size() && moved > 0.5f && off_arc == 0 && root < 0.05f,
          "interpolation: render(alpha 0.5) of a running Sonic lies between the last two pairs (%u vertices; they "
          "move up to %.1f HU between the pairs; every vertex within half its motion of the midpoint, the farthest "
          "%.3f HU: the parts turn on arcs; root error %.3f HU)",
          (unsigned)(m.size() / 3u), moved, mid, root);
    // with ticks of 1/120 s libsa1's accumulator gives alternating fractions
    float alphas[4];
    for (int i = 0; i < 4; i++) {
        s.tick(id, 0.0f, 1.0f, c->r_yaw, 0, 1.0f / 120.0f);
        s.render(id, -1.0f);
        alphas[i] = c->r_alpha;
    }
    bool varied = std::fabs(alphas[0] - alphas[1]) > 0.1f || std::fabs(alphas[1] - alphas[2]) > 0.1f;
    CHECK(varied, "render(-1) after ticks of 1/120 s: alpha %.2f %.2f %.2f %.2f (libsa1's accumulator)", alphas[0],
          alphas[1], alphas[2], alphas[3]);
}

// the run-length strings handed to Lua paint exactly libsa1's decoded RGBA, for every archive of every character
static void test_textures(Session &s)
{
    static const int32_t kinds[] = {SA1_CHAR_SONIC, SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA,
                                    SA1_CHAR_BIG};
    uint32_t textures = 0, archives = 0, bad = 0, failed = 0;
    uint64_t pixels = 0, runs = 0;
    std::string per;
    for (int32_t k : kinds) {
        uint32_t na = s.texture_archives(k), kt = 0;
        archives += na;
        for (uint32_t a = 0; a < na; a++) {
            uint32_t n = 0;
            std::string e, name;
            if (!s.texture_count(k, a, n, e, &name)) {
                failed++;
                continue;
            }
            for (uint32_t i = 0; i < n; i++) {
                TextureRuns tr;
                std::vector<uint8_t> img;
                sa1_texture_info ti;
                std::memset(&ti, 0, sizeof ti);
                ti.struct_size = sizeof ti;
                if (!s.texture_runs(k, a, i, tr, e) || sa1_texture_get(s.ctx(), k, a, i, &ti) != SA1_OK || !ti.rgba) {
                    failed++;
                    continue;
                }
                textures++;
                kt++;
                pixels += (uint64_t)tr.width * tr.height;
                runs += tr.run_count;
                if (!paint_runs(tr, img) || std::memcmp(img.data(), ti.rgba, img.size()) != 0) {
                    bad++;
                    if (g_verbose || bad <= 3) {
                        std::printf("        %s archive %u (%s) texture %u %s: painted image differs\n", kind_name(k), a,
                                    name.c_str(), i, tr.name.c_str());
                    }
                }
            }
        }
        per += format("%s%s %u/%u", per.empty() ? "" : ", ", kind_name(k), kt, na);
    }
    CHECK(textures > 300 && bad == 0 && failed == 0,
          "texture transfer: %u textures in %u archives (%s textures/archives), %llu texels in %llu runs: the runs "
          "paint every texel exactly as decoded (%u differ, %u failed)", textures, archives, per.c_str(),
          (unsigned long long)pixels, (unsigned long long)runs, bad, failed);
}

// materials and effects of every character in the situations that showed the owner's first in-game problems
static void test_effects(Session &s, const float pos[3], float yaw)
{
    const uint32_t A = SA1_BUTTON_ACTION;
    struct Case {
        int32_t kind;
        const char *what;
        std::vector<Step> script;
    };
    const Case cases[] = {
        {SA1_CHAR_SONIC, "Sonic standing", {{40, 0, 0}}},
        {SA1_CHAR_SONIC, "Sonic charging a spin dash", {{40, 0, 0}, {28, 0, A}}},
        {SA1_CHAR_TAILS, "Tails standing", {{40, 0, 0}}},
        {SA1_CHAR_KNUCKLES, "Knuckles punching", {{40, 0, 0}, {2, 0, A}, {10, 0, 0}}},
        {SA1_CHAR_GAMMA, "E-102 locking on", {{40, 0, 0}, {40, 0, A}}},
        {SA1_CHAR_AMY, "Amy swinging", {{40, 0, 0}, {2, 0, A}, {8, 0, 0}}},
        {SA1_CHAR_BIG, "Big after the action button", {{40, 0, 0}, {20, 0, A}, {40, 0, 0}}},
    };
    for (const Case &cs : cases) {
        std::string e;
        int32_t id = s.create(cs.kind, pos, yaw, e);
        if (id <= 0 || !run_script(s, id, cs.script, yaw)) {
            CHECK(false, "%s: %s", cs.what, e.c_str());
            if (id > 0) s.destroy(id);
            continue;
        }
        Character *c = s.get(id);
        s.render(id, 1.0f);
        Census k = census(*c);
        bool ok = k.batches > 0 && k.order && k.opaque > 0;
        const char *need = "";
        if (std::string(cs.what) == "Sonic standing") {
            // the eyes: USE_ALPHA materials are drawn opaque (the irises sit in front of the eye whites)
            ok = ok && k.use_alpha > 0 && k.palette > 0 && k.effect == 0 && k.shadow == 1;
            need = "palette-lit body, USE_ALPHA drawn opaque, no effects, the game's blob shadow in a batch of its own";
        } else if (std::string(cs.what) == "Sonic charging a spin dash") {
            ok = ok && k.effect_archive > 0 && k.additive > 0;
            need = "SON_EFF (archive 1) additive effect batches";
        } else if (cs.kind == SA1_CHAR_TAILS) {
            ok = ok && k.afterimage > 0 && k.blended > 0;
            need = "the tails' fading copies: blended, after the opaque batches, in the game's order";
        } else if (cs.kind == SA1_CHAR_KNUCKLES) {
            ok = ok && k.sprites > 0 && k.effect_archive > 0;
            need = "the punch sprite with KNU_EFF";
        } else if (cs.kind == SA1_CHAR_GAMMA) {
            ok = ok && k.lines > 0;
            need = "the targeting lines";
        } else {
            need = "information";
        }
        CHECK(ok, "%s: %s (%s)", cs.what, census_text(k).c_str(), need);
        if (g_verbose) {
            for (uint32_t b = 0; b < c->batch_count; b++) {
                const RenderBatch &rb = c->batches[b];
                std::printf("        batch %2u pass %u %-22s %5u tris  all %04X  order %u\n", b, rb.pass, rb.key.c_str(),
                            rb.triangles, rb.all_flags, rb.order);
            }
        }
        check_view(s, *c, cs.what);
        s.destroy(id);
    }
}

// sound: the events of a scripted run go through libsa1's mixer into PCM
static void test_audio(Session &s, const float pos[3], float yaw)
{
    std::string e;
    double t0 = now_ms();
    bool ok = s.audio_open(false, e);
    CHECK(ok, "sound banks and voices opened in %.0f ms (%s)", now_ms() - t0, ok ? (e.empty() ? "complete" : e.c_str()) : e.c_str());
    if (!ok) {
        return;
    }
    int32_t id = s.create(SA1_CHAR_SONIC, pos, yaw, e);
    std::vector<int16_t> pcm;
    float ear_f[3] = {1, 0, 0}, ear_u[3] = {0, 0, 1};
    s.audio().listener(pos, ear_f, ear_u);
    const uint32_t J = SA1_BUTTON_JUMP, A = SA1_BUTTON_ACTION;
    bool ran = id > 0 && run_script(s, id, {{40, 0, 0}, {10, 0, J}, {50, 0, 0}, {30, 0, A}, {40, 0, 0}, {60, 1, 0}}, yaw, &pcm);
    double sum = 0;
    uint32_t loud = 0;
    for (int16_t v : pcm) {
        sum += (double)v * v;
        loud += std::abs((int)v) > 1000;
    }
    double rms = pcm.empty() ? 0.0 : std::sqrt(sum / (double)pcm.size());
    CHECK(ran && s.audio().sound_events() > 0 && rms > 30.0 && loud > 100,
          "sound: Sonic idles, jumps, spin-dashes and runs: %llu sound events -> %.1f s of 44.1 kHz stereo, rms %.0f, "
          "%u samples above 1000", (unsigned long long)s.audio().sound_events(), pcm.size() / 2.0 / 44100.0, rms, loud);
    AudioOptions o = s.audio().options();
    o.master = 0.0f;
    s.audio().apply(o);
    std::vector<int16_t> quiet;
    run_script(s, id, {{10, 0, J}, {30, 0, 0}}, yaw, &quiet);
    bool silent = true;
    for (int16_t v : quiet) silent = silent && v == 0;
    CHECK(silent, "master volume 0 (the options menu): silence");
    o.master = 1.0f;
    s.audio().apply(o);
    s.destroy(id);
    s.audio_close();
    CHECK(!s.audio().is_open(), "sound closed");
}

// ---- E2 (0.9.2a, sadc docs/research/gsa1_091b_itembox.md section 6 with its review R.4.1): a destroyed character's
// queued events never reach the next character. Sonic runs and jumps (Session::tick moves his sound events into the
// session's queue), is destroyed in that frame without poll_events - as the addon removes or restarts a character whose
// tick failed - then Tails is created, ticked and polled: no event carries Sonic's id (0.9.1: his events came out with
// Tails' first poll, the owner's "Tails's game code faulted (address 8C05D930)").
static void test_stale_events(Session &s, const float pos[3], float yaw)
{
    std::printf("      a destroyed character's events (E2):\n");
    std::string e;
    std::vector<sa1_event> ev;
    s.poll_events(ev);
    int32_t sonic = s.create(SA1_CHAR_SONIC, pos, yaw, e);
    uint32_t queued = 0;
    for (int f = 0; f < 150 && sonic > 0; f++) {
        uint32_t b = (f >= 90 && f < 100) || (f >= 120 && f < 125) ? SA1_BUTTON_JUMP : 0;
        s.tick(sonic, 0.0f, f >= 60 ? 1.0f : 0.0f, yaw, b, 1.0f / 60.0f);
    }
    uint64_t d0 = s.stale_events_dropped();
    s.destroy(sonic);
    queued = (uint32_t)(s.stale_events_dropped() - d0);
    int32_t tails = s.create(SA1_CHAR_TAILS, pos, yaw, e);
    uint32_t stale = 0, own = 0, polls = 0;
    for (int f = 0; f < 60 && tails > 0; f++) {
        s.tick(tails, 0.0f, 0.0f, yaw, f >= 30 && f < 35 ? SA1_BUTTON_JUMP : 0, 1.0f / 60.0f);
        s.poll_events(ev);
        polls++;
        for (const sa1_event &x : ev) {
            if (x.character == sonic) stale++;
            else if (x.character == tails) own++;
        }
    }
    CHECK(sonic > 0 && tails > 0 && queued > 0 && stale == 0,
          "Sonic's %u queued events were dropped with him (Session::destroy); Tails' %u polls: %u of Sonic's events, %u of "
          "his own", queued, polls, stale, own);
    s.destroy(tails);
}

// ---- the frame loop at several frame rates (the owner's 0.2 report: "at high speed the character goes forward
// and backward every frame") --------------------------------------------------------------------------------------
// The module's frame loop is simulated on a flat floor: per frame Session::tick(dt) + Session::render(-1), as
// cl_character.lua's Think does, the camera at the drawn root (CalcView: C.drawPos + a fixed offset on flat
// ground). Recorded per frame: the drawn root, the centroid of the drawn body (the character renderer's draws of
// archive 0), whether libsa1 interpolated the geometry. Wanted: the root and the body move forward monotonically,
// and the body keeps its place relative to the root (= relative to the camera) from frame to frame.
struct JitterFrame {
    float t = 0;
    float root[3] = {0, 0, 0}, body[3] = {0, 0, 0}, dir[2] = {1, 0};
    bool have_body = false, interp = false, shifted = false;
    float alpha = 0, speed = 0;
    uint32_t pairs = 0;
};

static bool body_centroid(const Character &c, float out[3])
{
    double s[3] = {0, 0, 0};
    size_t n = 0;
    for (const sa1_draw &d : c.r_draws) {
        if (d.prim != SA1_PRIM_TRIANGLES || d.source != SA1_SOURCE_CHARACTER || d.archive != 0) {
            continue;
        }
        uint32_t end = std::min(d.first + d.count, c.r_triangles);
        for (uint32_t t = d.first; t < end; t++) {
            for (int k = 0; k < 9; k++) {
                s[k % 3] += c.r_tpos[(size_t)t * 9u + (size_t)k];
            }
            n += 3;
        }
    }
    if (!n) {
        return false;
    }
    for (int k = 0; k < 3; k++) {
        out[k] = (float)(s[k] / (double)n);
    }
    return true;
}

static std::vector<sa1_collision_tri> flat_floor(float half, float tile, float z)
{
    std::vector<sa1_collision_tri> out;
    for (float x0 = -half; x0 < half - 0.5f; x0 += tile) {
        for (float y0 = -half; y0 < half - 0.5f; y0 += tile) {
            float x1 = x0 + tile, y1 = y0 + tile;
            sa1_collision_tri a = {{{x0, y0, z}, {x1, y0, z}, {x1, y1, z}}, SA1_SURFACE_SOLID};
            sa1_collision_tri b = {{{x0, y0, z}, {x1, y1, z}, {x0, y1, z}}, SA1_SURFACE_SOLID};
            out.push_back(a);
            out.push_back(b);
        }
    }
    return out;
}

struct JitterResult {
    uint32_t fast = 0;          // frames faster than the threshold
    uint32_t root_back = 0;     // the drawn root moved backwards along the run
    uint32_t body_back = 0;     // the drawn body moved backwards along the run
    uint32_t raw = 0;           // frames libsa1 did not interpolate the geometry
    uint32_t shifted = 0;       // ... which libsa1 moved along with the root (Character::r_shifted)
    float rel_in = 0;           // largest change of (body - root) along the run between frames of one pair, HU
    float rel_edge = 0;         // the same where a new pair was drawn (the model's own change from pair to pair)
    float step = 0;             // largest frame-to-frame advance of the root, HU
    float top = 0;              // top speed, HU/s
    float lead = 0;             // the root ahead of the body's centroid (one 60 Hz step: libsa1 request), HU
    float lead_speed = 0;       // ... at this speed (the fastest measured frame), HU/s
};

// dts: the frame times, cycled; script(t, stick forward, buttons)
template <typename Script>
static JitterResult jitter_run(Session &s, const float pos[3], const std::vector<float> &dts, float seconds,
                               float measure_from, Script script, const char *label, bool print)
{
    JitterResult R;
    std::string e;
    int32_t id = s.create(SA1_CHAR_SONIC, pos, 0.0f, e);
    if (id <= 0) {
        std::printf("        create: %s\n", e.c_str());
        return R;
    }
    std::vector<JitterFrame> fr;
    std::vector<sa1_event> ev;
    float t = 0;
    size_t k = 0;
    while (t < seconds) {
        float dt = dts[k++ % dts.size()];
        t += dt;
        float sy = 0;
        uint32_t b = 0;
        script(t, sy, b);
        if (s.tick(id, 0.0f, sy, 0.0f, b, dt) != SA1_OK || s.render(id, -1.0f) != SA1_OK) {
            std::printf("        tick / render at t=%.3f: %s\n", t, s.last_error().c_str());
            break;
        }
        s.poll_events(ev);
        Character *c = s.get(id);
        JitterFrame f;
        f.t = t;
        std::memcpy(f.root, c->r_pos, sizeof f.root);
        f.have_body = body_centroid(*c, f.body);
        f.interp = c->r_interpolated != 0;
        f.shifted = c->r_shifted;
        f.alpha = c->r_alpha;
        f.pairs = c->pairs_last;
        float vx = c->st.velocity[0], vy = c->st.velocity[1];
        f.speed = std::sqrt(vx * vx + vy * vy);
        if (f.speed > 1e-3f) {
            f.dir[0] = vx / f.speed;
            f.dir[1] = vy / f.speed;
        }
        fr.push_back(f);
    }
    s.destroy(id);
    int printed = 0;
    float lead_speed = 0;
    for (size_t i = 1; i < fr.size(); i++) {
        const JitterFrame &a = fr[i - 1], &f = fr[i];
        R.top = std::max(R.top, f.speed);
        if (f.t < measure_from || f.speed < 600.0f || !a.have_body || !f.have_body) {
            continue;
        }
        R.fast++;
        const float *d = f.dir;
        float dr = (f.root[0] - a.root[0]) * d[0] + (f.root[1] - a.root[1]) * d[1];
        float db = (f.body[0] - a.body[0]) * d[0] + (f.body[1] - a.body[1]) * d[1];
        float rel = db - dr;
        R.root_back += dr < -0.01f;
        R.body_back += db < -0.01f;
        R.raw += !f.interp;
        R.shifted += f.shifted;
        float &rm = f.pairs ? R.rel_edge : R.rel_in;
        rm = std::max(rm, std::fabs(rel));
        R.step = std::max(R.step, dr);
        if (f.speed > lead_speed) {
            lead_speed = f.speed;
            R.lead = -((f.body[0] - f.root[0]) * d[0] + (f.body[1] - f.root[1]) * d[1]);
            R.lead_speed = f.speed;
        }
        if (print && printed < 40) {
            printed++;
            float off = (f.body[0] - f.root[0]) * d[0] + (f.body[1] - f.root[1]) * d[1];
            std::printf("        %s t %.4f  pairs %u alpha %.3f %s  speed %6.0f  root %+7.2f  body %+8.2f  "
                        "body-root %+7.2f  (body ahead of the root by %+.2f)\n", label, f.t, f.pairs, f.alpha,
                        f.interp ? "lerp" : "RAW ", f.speed, dr, db, rel, off);
        }
    }
    return R;
}

// ---- upgrades (the owner's 0.2 report: "the upgrades should be toggleable") --------------------------------------
// Every character created with all of its upgrades and with none: the event flags are in its world before the first
// step, PInitialize turns them into playerwk.equipment (sa1_state_ex.equipment), and the upgrades the game draws
// (Tails' anklets, Knuckles' claws / gloves, Amy's hammer, E-102's parts, Big's rod) change the drawn model.
static void test_upgrades(Session &s, const float pos[3], float yaw)
{
    size_t n = 0;
    const UpgradeDef *tab = upgrade_table(n);
    static const int32_t kinds[] = {SA1_CHAR_SONIC, SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA,
                                    SA1_CHAR_BIG};
    uint32_t total = 0;
    for (int32_t k : kinds) {
        std::vector<const UpgradeDef *> all;
        uint32_t want = 0;
        std::string names;
        for (size_t i = 0; i < n; i++) {
            if (tab[i].kind == k) {
                all.push_back(&tab[i]);
                want |= tab[i].equipment;
                names += format("%s%s", names.empty() ? "" : ", ", tab[i].title);
            }
        }
        total += (uint32_t)all.size();
        uint32_t equip[2] = {0, 0}, tris[2] = {0, 0}, flags_set = 0;
        bool ok[2] = {false, false}, checked[2] = {false, false};
        for (int with = 0; with < 2; with++) {
            std::string e;
            int32_t id = s.create(k, pos, yaw, e, nullptr, with ? &all : nullptr);
            if (id <= 0) {
                std::printf("        %s: %s\n", kind_name(k), e.c_str());
                continue;
            }
            if (with) {
                // the flags are in the world before the first step
                struct sa1g_world *w = sa1_character_world(s.ctx(), id);
                for (const UpgradeDef *u : all) {
                    uint32_t a = kEventFlagsAddr + u->flag, v = 0;
                    if (w && sa1g_world_rd32(w, a & ~3u, &v) == 0 && ((v >> (8u * (a & 3u))) & 0xFFu) != 0) {
                        flags_set++;
                    }
                }
            }
            ok[with] = run_script(s, id, {{30, 0, 0}}, yaw);
            Character *c = s.get(id);
            s.render(id, 1.0f);
            equip[with] = c->st.equipment & 0x7FFFu;
            checked[with] = c->upgrades_checked && c->upgrades_ok;
            for (const sa1_draw &d : c->r_draws) {
                if (d.prim == SA1_PRIM_TRIANGLES && d.archive == 0) {
                    tris[with] += d.count;
                }
            }
            s.destroy(id);
        }
        bool drawn_differs = tris[0] != tris[1];
        bool need_draw = k == SA1_CHAR_TAILS || k == SA1_CHAR_KNUCKLES || k == SA1_CHAR_AMY;
        CHECK(ok[0] && ok[1] && flags_set == all.size() && (equip[1] & want) == want && (equip[0] & want) == 0 &&
                  checked[0] && checked[1] && (!need_draw || drawn_differs),
              "%s with %s: %u of %u event flags in the world before the first step; equipment 0x%04X (wants 0x%04X), "
              "without upgrades 0x%04X; the model draws %u triangles with, %u without", kind_name(k), names.c_str(),
              flags_set, (unsigned)all.size(), equip[1], want, equip[0], tris[1], tris[0]);
    }
    std::vector<const UpgradeDef *> wrong = {find_upgrade(SA1_CHAR_SONIC, "light_speed_shoes")};
    std::string e;
    int32_t id = s.create(SA1_CHAR_KNUCKLES, pos, yaw, e, nullptr, &wrong);
    if (id > 0) {
        s.destroy(id);
    }
    CHECK(total == 17 && id <= 0 && find_upgrade(SA1_CHAR_KNUCKLES, "shovel_claw") &&
              !find_upgrade(SA1_CHAR_SONIC, "shovel_claw"),
          "%u upgrades in the table; another character's upgrade is refused (\"%s\")", total, e.c_str());
}

// ---- Knuckles climbing (the owner's 0.2 report: "Knuckles' climbing particles have no alpha") --------------------
// A floor and a wall; Knuckles jumps, glides into the wall (jump held in the air), grabs it and climbs (stick
// forward). Every effect draw of the climb is collected: its primitive, texture archive / index, the texture's
// alpha class, the SA1_DRAW_* flags, the blend factors, the vertex / sprite alpha and the batch it went into.
static std::vector<sa1_collision_tri> floor_and_wall(float wall_x)
{
    std::vector<sa1_collision_tri> out = flat_floor(4096.0f, 1024.0f, 0.0f);
    const float L = 2048.0f, H = 4096.0f, x = wall_x;
    // the wall's front faces -X (towards the character); counter-clockwise from the front
    sa1_collision_tri a = {{{x, -L, 0}, {x, L, H}, {x, L, 0}}, SA1_SURFACE_SOLID};
    sa1_collision_tri b = {{{x, -L, 0}, {x, -L, H}, {x, L, H}}, SA1_SURFACE_SOLID};
    out.push_back(a);
    out.push_back(b);
    return out;
}

struct ClimbDraw {
    uint32_t prim, flags, material;
    int32_t archive, texture;
    uint8_t src, dst, source;
    uint32_t tex_alpha;
    uint32_t min_a, max_a;      // vertex / sprite alpha seen
    uint32_t pass;              // the batch's pass (0 opaque, 1 blended)
    uint32_t frames;
};

static void test_climb(Session &s, bool print)
{
    std::string e;
    const float start[3] = {-400.0f, 0.0f, 20.0f};
    int32_t id = s.create(SA1_CHAR_KNUCKLES, start, 0.0f, e);
    if (id <= 0) {
        CHECK(false, "Knuckles: create: %s", e.c_str());
        return;
    }
    std::map<std::string, ClimbDraw> seen;
    std::vector<sa1_event> ev;
    bool climbed = false;
    int32_t climb_action = -1;
    float top_z = 0, wall_z0 = 0;
    const float dt = 1.0f / 60.0f;
    for (int f = 0; f < 60 * 8; f++) {
        float t = f * dt;
        float sy = 0.0f;
        uint32_t b = 0;
        if (t >= 1.0f && t < 1.1f) {
            b = SA1_BUTTON_JUMP;                    // jump
        } else if (t >= 1.3f && t < 2.6f) {
            b = SA1_BUTTON_JUMP;                    // glide
            sy = 1.0f;
        } else if (t >= 2.6f) {
            sy = 1.0f;                              // climb
        }
        if (s.tick(id, 0.0f, sy, 0.0f, b, dt) != SA1_OK || s.render(id, -1.0f) != SA1_OK) {
            std::printf("        tick at %.2f: %s\n", t, s.last_error().c_str());
            break;
        }
        s.poll_events(ev);
        Character *c = s.get(id);
        if (print && f % 10 == 0) {
            std::printf("        t %.2f pos (%.0f %.0f %.0f) action %d mode %d draws %u sprites %u\n", t,
                        c->st.position[0], c->st.position[1], c->st.position[2], (int)c->st.action, (int)c->st.mode,
                        (unsigned)c->r_draws.size(), (unsigned)c->r_sprites.size());
        }
        bool at_wall = c->st.position[0] > -60.0f && c->st.position[2] > 30.0f;
        if (at_wall && t > 2.6f) {
            if (!climbed) {
                wall_z0 = c->st.position[2];
                climb_action = c->st.action;
            }
            climbed = true;
            top_z = std::max(top_z, c->st.position[2]);
        }
        if (t < 2.6f) {
            continue;
        }
        for (uint32_t bi = 0; bi < c->batch_count; bi++) {
            const RenderBatch &rb = c->batches[bi];
            for (uint32_t di : rb.draws) {
                const sa1_draw &d = c->r_draws[di];
                if (!(d.flags & SA1_DRAW_EFFECT)) {
                    continue;
                }
                std::string key = format("%u %d.%d %04X %u/%u m%08X", d.prim, d.archive, d.texture, d.flags,
                                         d.blend_src, d.blend_dst, d.material);
                ClimbDraw &cd = seen[key];
                if (cd.frames == 0) {
                    cd.prim = d.prim;
                    cd.flags = d.flags;
                    cd.material = d.material;
                    cd.archive = d.archive;
                    cd.texture = d.texture;
                    cd.src = d.blend_src;
                    cd.dst = d.blend_dst;
                    cd.source = d.source;
                    cd.pass = rb.pass;
                    cd.min_a = 255;
                    cd.max_a = 0;
                    sa1_texture_info ti;
                    std::memset(&ti, 0, sizeof ti);
                    ti.struct_size = sizeof ti;
                    cd.tex_alpha = (d.archive >= 0 && d.texture >= 0 &&
                                    sa1_texture_get(s.ctx(), SA1_CHAR_KNUCKLES, (uint32_t)d.archive,
                                                    (uint32_t)d.texture, &ti) == SA1_OK) ? ti.alpha : 99u;
                }
                cd.frames++;
                if (d.prim == SA1_PRIM_SPRITES) {
                    for (uint32_t k = d.first; k < d.first + d.count && k < c->r_sprites.size(); k++) {
                        cd.min_a = std::min<uint32_t>(cd.min_a, c->r_sprites[k].color[3]);
                        cd.max_a = std::max<uint32_t>(cd.max_a, c->r_sprites[k].color[3]);
                    }
                } else if (d.prim == SA1_PRIM_TRIANGLES) {
                    for (uint32_t k = d.first; k < d.first + d.count && k < c->r_triangles; k++) {
                        for (int j = 0; j < 3; j++) {
                            uint32_t a = c->r_tcol[(size_t)k * 12u + (size_t)j * 4u + 3u];
                            cd.min_a = std::min(cd.min_a, a);
                            cd.max_a = std::max(cd.max_a, a);
                        }
                    }
                }
            }
        }
    }
    s.destroy(id);
    if (print) {
        INFO("Knuckles: grabbed the wall at z %.0f in action %d, climbed to z %.0f", wall_z0, (int)climb_action, top_z);
    }
    // the climbing dust: sprites of a texture with graded alpha, blended with the source alpha
    uint32_t dust = 0, dust_frames = 0;
    int32_t dust_arc = -1, dust_tex = -1;
    for (const auto &kv : seen) {
        const ClimbDraw &cd = kv.second;
        if (cd.prim == SA1_PRIM_SPRITES && (cd.flags & SA1_DRAW_BLEND) && !(cd.flags & SA1_DRAW_ADDITIVE) &&
            cd.src == SA1_BLEND_SRC_ALPHA && cd.dst == SA1_BLEND_INV_SRC_ALPHA && cd.pass == 1 &&
            cd.tex_alpha == SA1_TEXTURE_ALPHA_BLEND) {
            dust++;
            dust_frames += cd.frames;
            dust_arc = cd.archive;
            dust_tex = cd.texture;
        }
    }
    // what the addon paints into the texture's render target: the graded alpha of every texel
    uint32_t graded = 0, clear = 0, opaque = 0;
    bool painted_ok = false;
    if (dust_arc >= 0) {
        TextureRuns tr;
        std::vector<uint8_t> img;
        sa1_texture_info ti;
        std::memset(&ti, 0, sizeof ti);
        ti.struct_size = sizeof ti;
        if (s.texture_runs(SA1_CHAR_KNUCKLES, (uint32_t)dust_arc, (uint32_t)dust_tex, tr, e) && paint_runs(tr, img) &&
            sa1_texture_get(s.ctx(), SA1_CHAR_KNUCKLES, (uint32_t)dust_arc, (uint32_t)dust_tex, &ti) == SA1_OK &&
            ti.rgba && img.size() == (size_t)ti.width * ti.height * 4u) {
            painted_ok = std::memcmp(img.data(), ti.rgba, img.size()) == 0;
            for (size_t i = 3; i < img.size(); i += 4) {
                (img[i] == 0 ? clear : img[i] == 255 ? opaque : graded)++;
            }
        }
    }
    CHECK(climbed && dust > 0 && painted_ok && clear > 0 && graded > 0,
          "Knuckles climbs a wall (%.0f HU up): the climbing dust is %u sprite draw(s) of texture %d.%d (%u frames) "
          "with graded alpha, blended SRC_ALPHA / INV_SRC_ALPHA in the blended pass; the texture's runs carry its "
          "alpha exactly (%u clear, %u graded, %u opaque texels): the render target must keep it (cl_textures.lua)",
          top_z - wall_z0, dust, dust_arc, dust_tex, dust_frames, clear, graded, opaque);
    for (const auto &kv : seen) {
        if (!print) {
            break;
        }
        const ClimbDraw &cd = kv.second;
        if (print && cd.archive >= 0 && cd.texture >= 0) {
            sa1_texture_info ti;
            std::memset(&ti, 0, sizeof ti);
            ti.struct_size = sizeof ti;
            if (sa1_texture_get(s.ctx(), SA1_CHAR_KNUCKLES, (uint32_t)cd.archive, (uint32_t)cd.texture, &ti) == SA1_OK &&
                ti.rgba) {
                uint32_t hist[5] = {0, 0, 0, 0, 0};
                for (uint32_t i = 0; i < ti.width * ti.height; i++) {
                    uint32_t a = ti.rgba[i * 4u + 3u];
                    hist[a == 0 ? 0 : a < 64 ? 1 : a < 192 ? 2 : a < 255 ? 3 : 4]++;
                }
                std::printf("        texture %d.%d %s %ux%u pixel format %u data format %u alpha class %u: alpha 0: %u, "
                            "1-63: %u, 64-191: %u, 192-254: %u, 255: %u\n", cd.archive, cd.texture,
                            ti.name ? ti.name : "", ti.width, ti.height, ti.pixel_format, ti.data_format, ti.alpha,
                            hist[0], hist[1], hist[2], hist[3], hist[4]);
            }
        }
        INFO("climb effect draw: prim %u (source %u) texture %d.%d (alpha class %u) flags %04X blend %u/%u material "
             "%08X: alpha %u..%u, %s batch, %u frames", cd.prim, cd.source, cd.archive, cd.texture, cd.tex_alpha,
             cd.flags, cd.src, cd.dst, cd.material, cd.min_a, cd.max_a, cd.pass ? "blended" : "OPAQUE", cd.frames);
    }
}

static void test_climb_world(const std::string &gdi)
{
    std::printf("Knuckles on a wall (a floor and a wall):\n");
    Session cs;
    std::string ce;
    if (!cs.init(gdi, ce)) {
        CHECK(false, "init: %s", ce.c_str());
        return;
    }
    std::vector<sa1_collision_tri> w = floor_and_wall(0.0f);
    if (!cs.set_world(w, ce)) {
        CHECK(false, "set_world: %s", ce.c_str());
        return;
    }
    test_climb(cs, g_verbose);
}

// ---- 0.9.2: what the session passes into libsa1 (sadc docs/research/gsa1_090_plan.md 6.10 tasks 3, 4 and 8) ----------
// The start rings reach sa1_character_create_ex (SA1_CREATE_START_RINGS: the world's ring count before its first step,
// clamped to 99); the tick's host flags reach sa1_input.host_flags (gsa1_090_water.md WTR-A): in the water doc's tunnel
// scene - a dry room (floor 0, a ceiling slab 256..320 HU) under water up to 832 HU - the game's own rule puts Sonic in
// water (the lowest water surface above him), with SA1_INPUT_HOST_WATER_KNOWN (dry) he stays dry; in a 512-HU pool KNOWN |
// IN_WATER keeps him in water. The host camera is recorded (libsa1 takes it from round 0.9.4 on).
static void ct_quad(std::vector<sa1_collision_tri> &o, const float a[3], const float b[3], const float c[3], const float d[3]);
static const float kTestPair = 1.0f / 30.0f;      // one game pair

static void ct_box(std::vector<sa1_collision_tri> &o, float x0, float x1, float y0, float y1, float z0, float z1,
                   uint32_t surface)
{
    size_t n0 = o.size();
    float p[8][3] = {{x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0},
                     {x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1}};
    ct_quad(o, p[4], p[5], p[6], p[7]);
    ct_quad(o, p[0], p[3], p[2], p[1]);
    ct_quad(o, p[0], p[1], p[5], p[4]);
    ct_quad(o, p[2], p[3], p[7], p[6]);
    ct_quad(o, p[1], p[2], p[6], p[5]);
    ct_quad(o, p[3], p[0], p[4], p[7]);
    for (size_t i = n0; i < o.size(); i++) {
        o[i].surface = surface;
    }
}

// Sonic standing at `pos` for `pairs` pairs with the host flags `flags` (-1: no TickExtra at all): ticks in the game's
// water, the largest step reached; false when it could not run
static bool host_water_run(Session &s, const float pos[3], int flags, int pairs, int &wet, std::string &why,
                           uint32_t *passed = nullptr)
{
    std::string e;
    int32_t id = s.create(SA1_CHAR_SONIC, pos, 0.0f, e);
    if (id <= 0) {
        why = e;
        return false;
    }
    wet = 0;
    TickExtra x;
    x.host_flags = flags < 0 ? 0u : (uint32_t)flags;
    for (int i = 0; i < pairs; i++) {
        sa1_status st = s.tick(id, 0.0f, 0.0f, 0.0f, 0u, kTestPair, false, flags < 0 ? nullptr : &x);
        if (st != SA1_OK) {
            why = s.last_error();
            s.destroy(id);
            return false;
        }
        Character *c = s.get(id);
        if (c && (c->st.water_attr & 0x400002u) != 0) {
            wet++;
        }
        if (c && passed) {
            *passed = c->host_flags_last;
        }
    }
    s.destroy(id);
    return true;
}

static void test_host_input(const std::string &gdi)
{
    std::printf("0.9.2: start rings, host flags and the host camera through the session:\n");
    Session s;
    std::string e;
    if (!s.init(gdi, e)) {
        CHECK(false, "init: %s", e.c_str());
        return;
    }
    // the start rings (rings F7): given, clamped, the game's 0
    std::vector<sa1_collision_tri> floor = flat_floor(4096.0f, 1024.0f, 0.0f);
    CHECK(s.set_world(floor, e), "a flat floor (%s)", e.c_str());
    float pos[3] = {8.0f, 8.0f, 4.0f};
    int32_t a = s.create(SA1_CHAR_SONIC, pos, 0.0f, e, nullptr, nullptr, 37);
    int32_t b = s.create(SA1_CHAR_SONIC, pos, 0.0f, e, nullptr, nullptr, 150);
    int32_t g = s.create(SA1_CHAR_SONIC, pos, 0.0f, e);
    Character *ca = s.get(a), *cb = s.get(b), *cg = s.get(g);
    int32_t ra = ca ? ca->st.rings : -1, rb = cb ? cb->st.rings : -1, rg = cg ? cg->st.rings : -1;
    for (int i = 0; ca && i < 4; i++) {
        s.tick(a, 0.0f, 0.0f, 0.0f, 0u, kTestPair);
    }
    int32_t ra2 = ca ? ca->st.rings : -1;
    CHECK(ca && cb && cg && ra == 37 && ra2 == 37 && rb == kStartRingsMax && rg == 0 && ca->start_rings == 37 &&
              cb->start_rings == kStartRingsMax && cg->start_rings == -1,
          "start rings reach sa1_character_create_ex: 37 -> %d before the first step (%d after 4 pairs), 150 -> %d (clamped: "
          "a start never gives a 1-up), none -> %d (the game's 0)", ra, ra2, rb, rg);
    s.destroy(a);
    s.destroy(b);
    s.destroy(g);

    // the host flags (WTR-A): the tunnel
    std::vector<sa1_collision_tri> tunnel;
    ct_box(tunnel, -4096, 4096, -4096, 4096, -256, 0, SA1_SURFACE_SOLID);
    ct_box(tunnel, -4096, 4096, -4096, 4096, 256, 320, SA1_SURFACE_SOLID);
    ct_box(tunnel, -4096, 4096, -4096, 4096, 320, 832, SA1_SURFACE_WATER);
    CHECK(s.set_world(tunnel, e), "the tunnel: a dry room (ceiling slab 256..320 HU) under water up to 832 HU (%s)",
          e.c_str());
    int wet_none = -1, wet_zero = -1, wet_dry = -1, wet_pool = -1, wet_pool_none = -1;
    uint32_t passed_dry = 0, passed_pool = 0;
    std::string why;
    bool r1 = host_water_run(s, pos, -1, 60, wet_none, why);
    bool r2 = r1 && host_water_run(s, pos, 0, 60, wet_zero, why);
    bool r3 = r2 && host_water_run(s, pos, (int)SA1_INPUT_HOST_WATER_KNOWN, 60, wet_dry, why, &passed_dry);
    CHECK(r3 && wet_none > 0 && wet_zero == wet_none && wet_dry == 0 && passed_dry == SA1_INPUT_HOST_WATER_KNOWN,
          "host flags in the tunnel, 60 pairs at (8 8 4): no flags -> in the game's water %d pairs (its own rule: the "
          "water above), flags 0 -> %d (the same), KNOWN (GMod: dry) -> %d (passed 0x%X)%s%s", wet_none, wet_zero, wet_dry,
          (unsigned)passed_dry, r3 ? "" : ": ", r3 ? "" : why.c_str());
    // the pool: KNOWN | IN_WATER keeps real water
    std::vector<sa1_collision_tri> pool;
    ct_box(pool, -4096, 4096, -4096, 4096, -256, 0, SA1_SURFACE_SOLID);
    ct_box(pool, -4096, 4096, -4096, 4096, 0, 512, SA1_SURFACE_WATER);
    CHECK(s.set_world(pool, e), "a pool 512 HU deep (%s)", e.c_str());
    bool r4 = host_water_run(s, pos, -1, 60, wet_pool_none, why);
    bool r5 = r4 && host_water_run(s, pos, (int)(SA1_INPUT_HOST_WATER_KNOWN | SA1_INPUT_HOST_IN_WATER), 60, wet_pool, why,
                                   &passed_pool);
    CHECK(r5 && wet_pool_none > 0 && wet_pool > 0 && passed_pool == (SA1_INPUT_HOST_WATER_KNOWN | SA1_INPUT_HOST_IN_WATER),
          "host flags in the pool: no flags -> in water %d of 60 pairs, KNOWN | IN_WATER -> %d (passed 0x%X)%s%s",
          wet_pool_none, wet_pool, (unsigned)passed_pool, r5 ? "" : ": ", r5 ? "" : why.c_str());
    // bits libsa1 does not define are not passed; the host camera is recorded (and passed only with kHostCameraInput)
    int32_t id = s.create(SA1_CHAR_SONIC, pos, 0.0f, e);
    TickExtra x;
    x.host_flags = 0xF0u | SA1_INPUT_HOST_WATER_KNOWN;
    x.camera = true;
    x.cam_pos[0] = 100.0f;
    x.cam_pos[1] = 200.0f;
    x.cam_pos[2] = 300.0f;
    x.cam_target[2] = 1.0f;
    sa1_status st = id > 0 ? s.tick(id, 0.0f, 0.0f, 0.0f, 0u, kTestPair, false, &x) : SA1_ERR_NOT_FOUND;
    Character *c = s.get(id);
    CHECK(st == SA1_OK && c && c->host_flags_last == SA1_INPUT_HOST_WATER_KNOWN && c->host_camera_last &&
              c->host_cam_last[2] == 300.0f && c->host_cam_last[5] == 1.0f,
          "unknown host flag bits are dropped (0x%X passed); the host camera is recorded (%s by this libsa1)",
          c ? (unsigned)c->host_flags_last : 0u, kHostCameraInput ? "and passed" : "not taken yet");
    x.camera = false;
    if (id > 0) {
        s.tick(id, 0.0f, 0.0f, 0.0f, 0u, kTestPair, false, &x);
        s.tick(id, 0.0f, 0.0f, 0.0f, 0u, kTestPair);
    }
    CHECK(c && !c->host_camera_last && c->host_flags_last == 0u && c->host_flag_ticks == 2u,
          "a tick without a camera clears it, a tick without TickExtra passes no flags (%llu ticks with flags)",
          c ? (unsigned long long)c->host_flag_ticks : 0ull);
    if (id > 0) {
        s.destroy(id);
    }
}

// ---- the frame loop against the camera: vertical movement (round 4c, the owner's 0.5.0 report "the horizontal speed
// position flickering thing from earlier happens with vertical movement too"; sadc docs/research/gsa1_vertical_flicker.md
// with its review) -----------------------------------------------------------------------------------------------------
// The same frame loop as test_jitter (Session::tick(dt) + Session::render(-1) per frame, the camera at the drawn root
// r_pos), on synthetic worlds: a flat floor, a 3000-unit tower with a floor below, raw stairs. Per frame: the drawn
// root, the centroid of the drawn body (archive-0 model draws), whether libsa1 interpolated, and the largest difference
// between what the Session draws (r_tpos, sprites, lines) and libsa1's own sa1_character_render at the same alpha.
typedef std::vector<sa1_collision_tri> Tris;

static void ct_quad(Tris &o, const float a[3], const float b[3], const float c[3], const float d[3])
{
    sa1_collision_tri t1 = {{{a[0], a[1], a[2]}, {b[0], b[1], b[2]}, {c[0], c[1], c[2]}}, SA1_SURFACE_SOLID};
    sa1_collision_tri t2 = {{{a[0], a[1], a[2]}, {c[0], c[1], c[2]}, {d[0], d[1], d[2]}}, SA1_SURFACE_SOLID};
    o.push_back(t1);
    o.push_back(t2);
}

static void ct_floor(Tris &o, float x0, float y0, float x1, float y1, float z, float tile = 1024.0f)
{
    for (float x = x0; x < x1 - 0.01f; x += tile) {
        for (float y = y0; y < y1 - 0.01f; y += tile) {
            float xe = std::min(x + tile, x1), ye = std::min(y + tile, y1);
            float a[3] = {x, y, z}, b[3] = {xe, y, z}, c[3] = {xe, ye, z}, d[3] = {x, ye, z};
            ct_quad(o, a, b, c, d);
        }
    }
}

// a tower 3000 units high (its top 1200 x 1024 around x = -15000) on a floor
static Tris w_tower()
{
    Tris o;
    ct_floor(o, -16384, -16384, 16384, 16384, 0.0f);
    const float x0 = -15600, y0 = -512, z0 = 0, x1 = -14400, y1 = 512, z1 = 3000;
    float p[8][3] = {{x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0},
                     {x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1}};
    ct_quad(o, p[4], p[5], p[6], p[7]);
    ct_quad(o, p[0], p[3], p[2], p[1]);
    ct_quad(o, p[0], p[1], p[5], p[4]);
    ct_quad(o, p[2], p[3], p[7], p[6]);
    ct_quad(o, p[1], p[2], p[6], p[5]);
    ct_quad(o, p[3], p[0], p[4], p[7]);
    return o;
}

// raw stairs: 24 steps of 16 x 24 units along +x from x -14000 (no ramp flag), a landing
static Tris w_stairs()
{
    Tris o;
    ct_floor(o, -16384, -16384, 16384, 16384, 0.0f);
    const float x0 = -14000, h = 16.0f, d = 24.0f, w = 512.0f;
    for (int i = 0; i < 24; i++) {
        float x = x0 + i * d, z = (i + 1) * h;
        float r0[3] = {x, -w, z - h}, r1[3] = {x, w, z - h}, r2[3] = {x, w, z}, r3[3] = {x, -w, z};
        ct_quad(o, r0, r1, r2, r3);
        float t0[3] = {x, -w, z}, t1[3] = {x + d, -w, z}, t2[3] = {x + d, w, z}, t3[3] = {x, w, z};
        ct_quad(o, t0, t1, t2, t3);
    }
    ct_floor(o, x0 + 24 * d, -512, x0 + 24 * d + 512, 512, 24 * h, 512.0f);
    return o;
}

struct FlickFrame {
    double t = 0;
    float root[3] = {0, 0, 0}, body[3] = {0, 0, 0}, vel[3] = {0, 0, 0};
    bool have_body = false, interp = false, shifted = false;
    // libsa1 moved draws of the last pair with the root (SA1_RENDER_MOVED_WITH_ROOT). 0.8: the game's blob shadow is a
    // draw every pair matches, so Knuckles' ball / curled-body pairs are interpolated (the shadow) with the body moved
    // with the root - no longer "not interpolated"
    bool moved = false;
    float alpha = 0;
    uint32_t pairs = 0;
    float ident = 0;            // the Session's drawn vertices / sprites / lines against libsa1's render at this alpha (HU)
};

// the body: the model draws of archive 0 that are not effects (the character renderer, the ball shells' models, ...)
static bool flick_body(const Character &c, float out[3])
{
    double s[3] = {0, 0, 0};
    size_t n = 0;
    for (const sa1_draw &d : c.r_draws) {
        if (d.prim != SA1_PRIM_TRIANGLES || d.archive != 0 || (d.flags & SA1_DRAW_EFFECT) ||
            !(d.source == SA1_SOURCE_CHARACTER || d.source == SA1_SOURCE_MODEL || d.source == SA1_SOURCE_POSE)) {
            continue;
        }
        uint32_t end = std::min(d.first + d.count, c.r_triangles);
        for (uint32_t t = d.first; t < end; t++) {
            for (int k = 0; k < 9; k++) {
                s[k % 3] += c.r_tpos[(size_t)t * 9u + (size_t)k];
            }
            n += 3;
        }
    }
    if (!n) {
        return false;
    }
    for (int k = 0; k < 3; k++) {
        out[k] = (float)(s[k] / (double)n);
    }
    return true;
}

// the review's vertex-level check (gsa1_vertical_flicker.md R.1 item 2 / R.4): what the Session draws equals libsa1's
// own sa1_character_render at the same alpha; 0.5.1's follow_root moved non-interpolated frames a second time
static float flick_identity(Session &s, const Character &c)
{
    const sa1_render *r = nullptr;
    if (sa1_character_render(s.ctx(), c.id, c.r_alpha, &r) != SA1_OK || !r) {
        return 1e9f;
    }
    uint32_t nt = (r->positions && r->normals && r->uvs && r->colors) ? r->num_triangles : 0u;
    uint32_t ns = r->sprites ? r->num_sprites : 0u, nl = r->line_vertices ? (r->num_line_vertices & ~1u) : 0u;
    if (nt != c.r_triangles || ns != c.r_sprites.size() || nl != c.r_lines.size()) {
        return 1e9f;
    }
    float worst = 0.0f;
    for (size_t i = 0; i < (size_t)nt * 9u; i++) {
        worst = std::max(worst, std::fabs(r->positions[i] - c.r_tpos[i]));
    }
    for (uint32_t i = 0; i < ns; i++) {
        for (int k = 0; k < 3; k++) {
            worst = std::max(worst, std::fabs(r->sprites[i].position[k] - c.r_sprites[i].position[k]));
        }
    }
    for (uint32_t i = 0; i < nl; i++) {
        for (int k = 0; k < 3; k++) {
            worst = std::max(worst, std::fabs(r->line_vertices[i].position[k] - c.r_lines[i].position[k]));
        }
    }
    return std::isfinite(worst) ? worst : 1e9f;
}

typedef void (*FlickScript)(double t, const Character &c, float &sx, float &sy, uint32_t &b, double &state);

static std::vector<FlickFrame> flick_run(Session &s, int32_t kind, const float pos[3],
                                         const std::vector<const UpgradeDef *> &ups, const std::vector<float> &dts,
                                         double seconds, FlickScript script, bool &ok)
{
    std::vector<FlickFrame> fr;
    std::string e;
    int32_t id = s.create(kind, pos, 0.0f, e, nullptr, ups.empty() ? nullptr : &ups);
    ok = id > 0;
    if (!ok) {
        std::printf("        create %s: %s\n", kind_name(kind), e.c_str());
        return fr;
    }
    std::vector<sa1_event> ev;
    double t = 0, state = -1;
    size_t k = 0;
    while (t < seconds) {
        float dt = dts[k++ % dts.size()];
        t += dt;
        float sx = 0, sy = 0;
        uint32_t b = 0;
        script(t, *s.get(id), sx, sy, b, state);
        if (s.tick(id, sx, sy, 0.0f, b, dt) != SA1_OK || s.render(id, -1.0f) != SA1_OK) {
            std::printf("        tick / render at t=%.3f: %s\n", t, s.last_error().c_str());
            ok = false;
            break;
        }
        s.poll_events(ev);
        Character *c = s.get(id);
        FlickFrame f;
        f.t = t;
        std::memcpy(f.root, c->r_pos, sizeof f.root);
        std::memcpy(f.vel, c->st.velocity, sizeof f.vel);
        f.have_body = flick_body(*c, f.body);
        f.interp = c->r_interpolated != 0;
        f.shifted = c->r_shifted;
        f.moved = (c->r_flags & SA1_RENDER_MOVED_WITH_ROOT) != 0;
        f.alpha = c->r_alpha;
        f.pairs = c->pairs_last;
        f.ident = flick_identity(s, *c);
        fr.push_back(f);
    }
    s.destroy(id);
    return fr;
}

struct FlickStats {
    uint32_t frames = 0, raw = 0, raw_pairs = 0, shifted = 0, ident_raw = 0;
    float ident = 0, ident_raw_max = 0;   // largest Session-vs-libsa1 difference: every frame / non-interpolated frames
    float drift = 0;                      // inside non-interpolated pairs: the change of body - root since the pair began
    uint32_t rev = 0;                     // pairs whose body - root drift (> 1 HU) the next pair's jump undid (> 120 deg)
    float rev_max = 0;
    float rel_z_in = 0;                   // largest change of (body - root).z between two frames of one pair
    float lead = 0, lead_speed = 0;       // the root ahead of the body along the velocity at the fastest frame
    float path_win = 0;                   // largest change of (body - root) along the path per frame inside the window
    float max_speed = 0, max_vz = 0;
};

static float fdot3(const float a[3], const float b[3]) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

static FlickStats flick_analyse(const std::vector<FlickFrame> &fr, double from, double w0 = 1e9, double w1 = -1e9)
{
    FlickStats R;
    for (size_t i = 1; i < fr.size(); i++) {
        const FlickFrame &a = fr[i - 1], &f = fr[i];
        if (f.t < from || !a.have_body || !f.have_body) {
            continue;
        }
        R.frames++;
        R.ident = std::max(R.ident, f.ident);
        if ((!f.interp || f.moved) && f.alpha < 1.0f) {
            R.ident_raw++;
            R.ident_raw_max = std::max(R.ident_raw_max, f.ident);
        }
        float sp = std::sqrt(fdot3(f.vel, f.vel));
        R.max_speed = std::max(R.max_speed, sp);
        R.max_vz = std::max(R.max_vz, std::fabs(f.vel[2]));
        float rel0[3], rel1[3], drel[3];
        for (int k = 0; k < 3; k++) {
            rel0[k] = a.body[k] - a.root[k];
            rel1[k] = f.body[k] - f.root[k];
            drel[k] = rel1[k] - rel0[k];
        }
        R.raw += !f.interp;
        R.shifted += f.shifted;
        if (f.pairs) {
            R.raw_pairs += !f.interp || f.moved;
        } else {
            R.rel_z_in = std::max(R.rel_z_in, std::fabs(drel[2]));
            if (!f.interp) {
                size_t j = i;
                while (j > 0 && !fr[j].pairs) {
                    j--;
                }
                float dd[3];
                for (int q = 0; q < 3; q++) {
                    dd[q] = rel1[q] - (fr[j].body[q] - fr[j].root[q]);
                }
                R.drift = std::max(R.drift, std::sqrt(fdot3(dd, dd)));
            }
        }
        if (f.t >= w0 && f.t <= w1) {
            float d[3] = {f.vel[0], f.vel[1], f.vel[2]};
            float dl = std::sqrt(fdot3(d, d));
            if (dl < 1.0f) {
                for (int k = 0; k < 3; k++) {
                    d[k] = f.root[k] - a.root[k];
                }
                dl = std::sqrt(fdot3(d, d));
            }
            if (dl > 1e-4f) {
                R.path_win = std::max(R.path_win, std::fabs(fdot3(drel, d)) / dl);
            }
        }
    }
    // per pair: D = (body - root) at its last frame minus at its first; E = at the next pair's first frame minus at
    // this pair's last. A back-and-forth: E points against D (vf_test.cpp's "reversals")
    std::vector<size_t> starts;
    for (size_t i = 0; i < fr.size(); i++) {
        if (fr[i].pairs && fr[i].t >= from && fr[i].have_body) {
            starts.push_back(i);
        }
    }
    for (size_t k = 0; k + 1 < starts.size(); k++) {
        size_t a = starts[k], b = starts[k + 1] - 1, n = starts[k + 1];
        if (b <= a || !fr[b].have_body || !fr[n].have_body) {
            continue;
        }
        float D[3], E[3];
        for (int q = 0; q < 3; q++) {
            float ra = fr[a].body[q] - fr[a].root[q], rb = fr[b].body[q] - fr[b].root[q], rn = fr[n].body[q] - fr[n].root[q];
            D[q] = rb - ra;
            E[q] = rn - rb;
        }
        float dl = std::sqrt(fdot3(D, D)), el = std::sqrt(fdot3(E, E));
        if (dl > 1.0f && el > 1.0f && fdot3(D, E) < -0.5f * dl * el) {
            R.rev++;
            R.rev_max = std::max(R.rev_max, std::min(dl, el));
        }
    }
    float best = 0;
    for (const FlickFrame &f : fr) {
        if (f.t < from || !f.have_body) {
            continue;
        }
        float sp = std::sqrt(fdot3(f.vel, f.vel));
        if (sp > best && sp > 1.0f) {
            best = sp;
            float d[3] = {f.vel[0] / sp, f.vel[1] / sp, f.vel[2] / sp};
            float rel[3] = {f.body[0] - f.root[0], f.body[1] - f.root[1], f.body[2] - f.root[2]};
            R.lead = -fdot3(rel, d);
            R.lead_speed = sp;
        }
    }
    return R;
}

static bool flick_hold(double t, double a, double b) { return t >= a && t < b; }

// gsa1_vertical_flicker.md 6 / R.4: Knuckles' standing jump (jump held 1.0-1.3 s, measured from 0.9 s) ...
static void fs_jump_stand(double t, const Character &, float &, float &, uint32_t &b, double &)
{
    b = (flick_hold(t, 1.0, 1.3) || flick_hold(t, 2.5, 2.6)) ? SA1_BUTTON_JUMP : 0u;
}
// ... the running jump (forward from 0.5 s, jumps at 3.0-3.3 s and 4.6-4.7 s, measured from 2.9 s) ...
static void fs_jump_run(double t, const Character &, float &, float &sy, uint32_t &b, double &)
{
    sy = t >= 0.5 ? 1.0f : 0.0f;
    b = (flick_hold(t, 3.0, 3.3) || flick_hold(t, 4.6, 4.7)) ? SA1_BUTTON_JUMP : 0u;
}
// ... a jump at the edge of the 3000-unit tower (R.1 item 7: the ball and the body alternate through the whole fall) ...
static void fs_edge_jump(double t, const Character &c, float &, float &sy, uint32_t &b, double &state)
{
    sy = t >= 0.5 ? 1.0f : 0.0f;
    if (state < 0 && c.st.position[0] > -14520.0f) {
        state = t;
    }
    b = (state >= 0 && t >= state && t < state + 0.4) ? SA1_BUTTON_JUMP : 0u;
}
// ... running off the tower (fix B: the fall) ...
static void fs_fall(double t, const Character &, float &, float &sy, uint32_t &, double &)
{
    sy = flick_hold(t, 0.5, 4.0) ? 1.0f : 0.0f;
}
// ... up the raw stairs ...
static void fs_stairs(double t, const Character &, float &, float &sy, uint32_t &, double &)
{
    sy = t >= 0.5 ? 1.0f : 0.0f;
}
// ... and the Light Speed charge (action held 1.0-5.0 s, released: the dash runs at 3779 HU/s for 10 steps)
static void fs_lsd(double t, const Character &, float &, float &, uint32_t &b, double &)
{
    b = flick_hold(t, 1.0, 5.0) ? SA1_BUTTON_ACTION : 0u;
}

static void test_flicker(const std::string &gdi)
{
    std::printf("frame loop against the camera, vertical movement (round 4c; gsa1_vertical_flicker.md):\n");
    Session s;
    std::string e;
    if (!s.init(gdi, e)) {
        CHECK(false, "init: %s", e.c_str());
        return;
    }
    std::vector<float> uneven;
    uint32_t seed = 12345u;
    for (int i = 0; i < 997; i++) {
        seed = seed * 1103515245u + 12345u;
        float r = (float)((seed >> 8) & 0xFFFF) / 65535.0f;
        uneven.push_back((1.0f / 144.0f) * (0.6f + 0.8f * r));
    }
    struct Rate {
        const char *name;
        std::vector<float> dts;
    };
    const Rate rates[] = {{"60", {1.0f / 60.0f}}, {"144", {1.0f / 144.0f}}, {"240", {1.0f / 240.0f}},
                          {"100/200", {1.0f / 100.0f, 1.0f / 200.0f}}, {"144+-40%", uneven}};
    const std::vector<const UpgradeDef *> none;
    // fix A: Knuckles' standing and running jumps, Sonic's running jump, at every frame-time pattern
    std::vector<sa1_collision_tri> floor = flat_floor(16384.0f, 1024.0f, 0.0f);
    CHECK(s.set_world(floor, e), "a flat floor (%s)", e.c_str());
    const float start[3] = {-15000.0f, 0.0f, 40.0f};
    struct JumpCase {
        const char *what;
        int32_t kind;
        FlickScript script;
        double seconds, from;
    };
    const JumpCase jumps[] = {{"Knuckles' standing jump", SA1_CHAR_KNUCKLES, fs_jump_stand, 4.0, 0.9},
                              {"Knuckles' running jump", SA1_CHAR_KNUCKLES, fs_jump_run, 6.0, 2.9},
                              {"Sonic's running jump", SA1_CHAR_SONIC, fs_jump_run, 6.0, 2.9}};
    for (const JumpCase &jc : jumps) {
        for (const Rate &r : rates) {
            bool ok = false;
            std::vector<FlickFrame> fr = flick_run(s, jc.kind, start, none, r.dts, jc.seconds, jc.script, ok);
            FlickStats R = flick_analyse(fr, jc.from);
            bool knux = jc.kind == SA1_CHAR_KNUCKLES;
            // the review (R.2.3, R.4): a few pair-edge steps of 2 HU stay - the game's own 30 Hz change between the
            // ball and the curled body, and the model change at take-off and landing - so the back-and-forth CHECK
            // is "none over 3 HU" (0.5.1: 16-29 per jump, up to 25 HU)
            CHECK(ok && R.ident_raw_max < 1e-4f && R.ident < 1e-4f && R.drift <= 0.5f && (!knux || R.raw_pairs >= 10) &&
                      (!knux || R.rev_max < 3.0f),
                  "%s fps, %s: %u frames, %u pairs libsa1 drew (in part) moved with the root; the drawn "
                  "vertices are libsa1's to %.6f HU in the %u frames of such pairs (%.6f in all); the body against "
                  "the camera drifts %.2f HU inside such a pair; %u back-and-forth pairs, the largest %.2f HU "
                  "[0.5.1: drift up to 25 HU, up to 29 back-and-forth pairs of up to 25 HU]",
                  r.name, jc.what, R.frames, R.raw_pairs, R.ident_raw_max, R.ident_raw, R.ident, R.drift, R.rev, R.rev_max);
        }
    }
    // fix A: Knuckles jumping at the tower's edge (the ball and the body alternate through the 3000-unit fall: a 55 HU
    // sawtooth in 0.5.1); fix B: Sonic running off the tower (the body hung one step's fall above the camera's root)
    std::vector<sa1_collision_tri> tower = w_tower();
    CHECK(s.set_world(tower, e), "a 3000-unit tower on a floor (%s)", e.c_str());
    const float top[3] = {-15400.0f, 0.0f, 3040.0f};
    for (int ri = 0; ri < 2; ri++) {
        const Rate &r = rates[ri];
        bool ok = false;
        std::vector<FlickFrame> fr = flick_run(s, SA1_CHAR_KNUCKLES, top, none, r.dts, 7.0, fs_edge_jump, ok);
        FlickStats R = flick_analyse(fr, 1.0);
        CHECK(ok && R.max_vz > 1000.0f && R.raw_pairs >= 10 && R.ident_raw_max < 1e-4f && R.drift <= 0.5f,
              "%s fps, Knuckles jumps at the tower's edge and falls (|vz| up to %.0f HU/s): %u pairs (in part) moved "
              "with the root; "
              "drawn vertices = libsa1's to %.6f HU; drift inside a pair %.2f HU [0.5.1: a second shift of up to 56 HU]",
              r.name, R.max_vz, R.raw_pairs, R.ident_raw_max, R.drift);
        fr = flick_run(s, SA1_CHAR_SONIC, top, none, r.dts, 7.0, fs_fall, ok);
        R = flick_analyse(fr, 1.0);
        float lim = ri == 0 ? 2.0f : 1.5f;
        CHECK(ok && R.max_vz > 1500.0f && R.rel_z_in < lim && R.ident < 1e-4f,
              "%s fps, Sonic runs off the tower and falls (|vz| up to %.0f HU/s): the body against the camera moves "
              "%.2f HU per frame within a pair, under %.1f [0.5.1: 13.29 at 60 fps, 5.54 at 144: the root was one "
              "60 Hz step ahead of the drawn body]", r.name, R.max_vz, R.rel_z_in, lim);
    }
    // fix B: Amy on raw stairs (16 x 24 units, no ramp flag)
    std::vector<sa1_collision_tri> st = w_stairs();
    CHECK(s.set_world(st, e), "raw stairs, 24 steps of 16 x 24 units (%s)", e.c_str());
    const float foot[3] = {-14600.0f, 0.0f, 40.0f};
    for (int ri = 0; ri < 2; ri++) {
        const Rate &r = rates[ri];
        bool ok = false;
        std::vector<FlickFrame> fr = flick_run(s, SA1_CHAR_AMY, foot, none, r.dts, 6.0, fs_stairs, ok);
        FlickStats R = flick_analyse(fr, 0.8);
        float lim = ri == 0 ? 2.0f : 1.5f;
        CHECK(ok && R.rel_z_in < lim && R.ident < 1e-4f,
              "%s fps, Amy runs up the stairs: the body against the camera moves %.2f HU per frame within a pair, "
              "under %.1f [0.5.1: 15.36 at 60 fps, 6.40 at 144]", r.name, R.rel_z_in, lim);
    }
    // fix B, lsd_lag review C4: the Light Speed Dash released without a target (3779 HU/s for 10 steps); the camera
    // follows the drawn root, so the body must keep its place against it in the frames of the release and the stop
    CHECK(s.set_world(floor, e), "the flat floor again (%s)", e.c_str());
    std::vector<const UpgradeDef *> lsd;
    for (const char *u : {"light_speed_shoes", "crystal_ring", "ancient_light"}) {
        lsd.push_back(find_upgrade(SA1_CHAR_SONIC, u));
    }
    const Rate lsd_rates[] = {{"60", {1.0f / 60.0f}},
                              {"60 on an 84 Hz display", {2.0f / 84.0f, 1.0f / 84.0f, 2.0f / 84.0f, 1.0f / 84.0f, 1.0f / 84.0f}}};
    for (const Rate &r : lsd_rates) {
        bool ok = false;
        std::vector<FlickFrame> fr = flick_run(s, SA1_CHAR_SONIC, start, lsd, r.dts, 6.0, fs_lsd, ok);
        FlickStats R = flick_analyse(fr, 0.9, 4.9, 5.4);
        CHECK(ok && R.max_speed > 3000.0f && R.path_win <= 4.0f && R.ident < 1e-4f,
              "%s fps, Light Speed Dash (all of Sonic's upgrades, action held 1.0-5.0 s, released: up to %.0f HU/s): "
              "the body against the camera moves at most %.2f HU along the path per frame in 4.9-5.4 s "
              "[0.5.0: 31.5 / 44.9 HU, a lurch of a body length]", r.name, R.max_speed, R.path_win);
    }
    s.shutdown();
}

// ---- round 4c F6, E1 and E5 on a hand-made character (no disc): the vertex colour of untextured draws, the mesh calls a
// batch's material reads, the screen coverage of the blended batches -----------------------------------------------
static void test_view_rules()
{
    std::printf("prepare_view rules (round 4c F6 / E1 / E5, no disc needed):\n");
    Session s;
    Character c;
    c.r_triangles = 4;
    // a triangle per draw: 0 untextured blended additive unlit (the Light Speed aura's kind), 1 textured opaque lit,
    // 2 textured sphere map, 3 untextured blended, half of a 400 x 300 screen seen from the origin (fov 90, Hor+)
    const float tri[4][9] = {{100, 10, 0, 100, -10, 0, 100, 0, 10},
                             {100, 10, 0, 100, -10, 0, 100, 0, 10},
                             {100, 10, 0, 100, -10, 0, 100, 0, 10},
                             {100, 100, 75, 100, -100, 75, 100, -100, -75}};
    for (int t = 0; t < 4; t++) {
        for (int k = 0; k < 9; k++) {
            c.r_tpos.push_back(tri[t][k]);
            c.r_tnrm.push_back(k % 3 == 0 ? -1.0f : 0.0f);
        }
        for (int k = 0; k < 6; k++) {
            c.r_tuv.push_back(0.25f);
        }
        for (int k = 0; k < 3; k++) {
            c.r_tcol.insert(c.r_tcol.end(), {10, 200, 30, 128});
        }
    }
    const uint32_t A = SA1_DRAW_BLEND | SA1_DRAW_UNLIT | SA1_DRAW_ADDITIVE;
    struct B {
        int32_t archive;
        uint32_t flags, pass;
    };
    const B bs[4] = {{-1, A, 1}, {0, 0, 0}, {0, SA1_DRAW_ENV_MAP, 0}, {-1, SA1_DRAW_BLEND, 1}};
    c.batch_count = 4;
    c.batches.resize(4);
    for (uint32_t i = 0; i < 4; i++) {
        sa1_draw d;
        std::memset(&d, 0, sizeof d);
        d.prim = SA1_PRIM_TRIANGLES;
        d.first = i;
        d.count = 1;
        d.archive = bs[i].archive;
        d.texture = bs[i].archive >= 0 ? 0 : -1;
        d.flags = bs[i].flags;
        c.r_draws.push_back(d);
        RenderBatch &rb = c.batches[i];
        rb.pass = bs[i].pass;
        rb.archive = d.archive;
        rb.texture = d.texture;
        rb.flags = d.flags;
        rb.prims = 1u << SA1_PRIM_TRIANGLES;
        rb.triangles = 1;
        rb.draws.assign(1, i);
    }
    const float eye[3] = {0, 0, 0}, right[3] = {0, -1, 0}, up[3] = {0, 0, 1};
    ViewOptions o;
    o.vertex_color = false;
    s.prepare_view(c, eye, right, up, o);
    auto rgb = [&](uint32_t b) { return format("%u %u %u", c.batches[b].col[0], c.batches[b].col[1], c.batches[b].col[2]); };
    bool f6 = rgb(0) == "10 200 30" && rgb(3) == "10 200 30" && rgb(1) == "255 255 255" && c.batches[0].col[3] == 128;
    o.vertex_color = true;
    s.prepare_view(c, eye, right, up, o);
    f6 = f6 && rgb(1) == "10 200 30" && rgb(0) == "10 200 30";
    CHECK(f6, "F6: with gsa1_vertexcolor 0 an untextured blended batch keeps its vertex colour (%s), a textured one "
          "turns white; with 1 both keep it", rgb(0).c_str());
    bool e1 = !c.batches[0].need_normal && !c.batches[0].need_uv && c.batches[1].need_normal && c.batches[1].need_uv &&
              c.batches[2].need_uv && c.batches[3].need_normal && !c.batches[3].need_uv;
    o.lit = false;
    s.prepare_view(c, eye, right, up, o);
    e1 = e1 && !c.batches[1].need_normal && c.batches[1].need_uv && !c.batches[2].need_normal;
    CHECK(e1, "E1: mesh.Normal only for lit materials (not SA1_DRAW_UNLIT, not with gsa1_lighting 0), mesh.TexCoord only "
          "for textured or sphere-mapped batches");
    o.lit = true;
    o.fov = 90.0f;
    o.width = 400.0f;
    o.height = 300.0f;
    s.prepare_view(c, eye, right, up, o);
    float half = c.view_cover;
    // a huge triangle across the whole view, and one behind the eye
    float big[9] = {50, 4000, -4000, 50, 4000, 4000, 50, -8000, 0}, back[9] = {-50, 10, 0, -50, -10, 0, -50, 0, 10};
    std::memcpy(&c.r_tpos[0], big, sizeof big);
    std::memcpy(&c.r_tpos[27], back, sizeof back);
    s.prepare_view(c, eye, right, up, o);
    float full = c.view_cover;
    CHECK(half > 0.5f && half < 0.52f && full > 0.99f && full < 1.01f,
          "E5: the blended batches cover %.4f of a 400 x 300 screen (a triangle over half of it plus a small one), then "
          "%.4f (one covering everything, one behind the eye)", half, full);
    std::memcpy(&c.r_tpos[0], tri[0], sizeof tri[0]);
    std::memcpy(&c.r_tpos[27], tri[3], sizeof tri[3]);
    s.prepare_view(c, eye, right, up, o);
    const float fwd[3] = {1, 0, 0};
    double small = triangle_pixels(eye, right, up, fwd, 1.0, 0.75, 400, 300, tri[0], tri[0] + 3, tri[0] + 6) / 120000.0;
    double halfx = triangle_pixels(eye, right, up, fwd, 1.0, 0.75, 400, 300, tri[3], tri[3] + 3, tri[3] + 6) / 120000.0;
    CHECK(std::fabs(halfx - 0.5) < 1e-6 && std::fabs(c.view_cover - (float)(halfx + small)) < 1e-5f,
          "E5: triangle_pixels: half the screen exactly (%.6f), the small one %.6f, their sum is the coverage (%.6f)",
          halfx, small, c.view_cover);
}

static void test_jitter(const std::string &gdi)
{
    std::printf("frame loop at 60 / 144 / 240 fps and uneven frame times (Sonic at top speed and after a spin dash):\n");
    Session s;
    std::string e;
    if (!s.init(gdi, e)) {
        CHECK(false, "init: %s", e.c_str());
        return;
    }
    std::vector<sa1_collision_tri> floor = flat_floor(16384.0f, 1024.0f, 0.0f);
    CHECK(s.set_world(floor, e), "a flat floor of %u triangles (%s)", (unsigned)floor.size(), e.c_str());
    const float start[3] = {-15000.0f, 0.0f, 40.0f};
    struct Rate {
        const char *name;
        std::vector<float> dts;
    };
    // uneven: what a real frame loop gives (frame pacing, vsync misses)
    std::vector<float> uneven;
    uint32_t seed = 12345u;
    for (int i = 0; i < 997; i++) {
        seed = seed * 1103515245u + 12345u;
        float r = (float)((seed >> 8) & 0xFFFF) / 65535.0f;
        uneven.push_back((1.0f / 144.0f) * (0.6f + 0.8f * r));
    }
    const Rate rates[] = {{"60", {1.0f / 60.0f}}, {"144", {1.0f / 144.0f}}, {"240", {1.0f / 240.0f}},
                          {"100/200", {1.0f / 100.0f, 1.0f / 200.0f}}, {"144+-40%", uneven}};
    for (const Rate &r : rates) {
        auto run = [](float t, float &sy, uint32_t &b) {
            sy = t >= 1.0f ? 1.0f : 0.0f;
            b = 0;
        };
        // the spin dash is released at 1.8 s; measured from its second pair (the first one starts the body's lag
        // of one 60 Hz step behind the root, see JitterResult::lead)
        auto dash = [](float t, float &sy, uint32_t &b) {
            sy = 0.0f;
            b = (t >= 1.0f && t < 1.8f) ? SA1_BUTTON_ACTION : 0u;
        };
        std::string l1 = std::string("run ") + r.name, l2 = std::string("dash ") + r.name;
        JitterResult a = jitter_run(s, start, r.dts, 6.0f, 2.0f, run, l1.c_str(), g_verbose);
        JitterResult d = jitter_run(s, start, r.dts, 3.5f, 1.9f, dash, l2.c_str(), g_verbose);
        for (const JitterResult *x : {&a, &d}) {
            const char *what = x == &a ? "running" : "spin dash";
            float pair = x->top / 30.0f;
            CHECK(x->fast > 20 && x->root_back == 0 && x->body_back == 0 && x->rel_in < 0.5f + 0.05f * x->step &&
                  x->rel_edge < 0.15f * pair + 0.5f,
                  "%s fps, %s (top %.0f HU/s, %.0f HU per pair): %u fast frames (%u not interpolated by libsa1, %u "
                  "moved with the root); the drawn root went back in %u, the body in %u; the body against the root (= "
                  "the camera) moved by at most %.2f HU within a pair and %.2f HU at a new pair (the root advances up "
                  "to %.2f HU per frame)", r.name, what, x->top, pair, x->fast, x->raw, x->shifted, x->root_back,
                  x->body_back, x->rel_in, x->rel_edge, x->step);
        }
        // round 4c (libsa1's fix B): the root is the drawn step's, so the body no longer trails the camera's root by
        // one 60 Hz step (0.5.1: 15.8 HU at 1031 HU/s, 39.6 HU at 2379 HU/s)
        CHECK(std::fabs(a.lead) < 2.0f && std::fabs(d.lead) < 2.0f,
              "%s fps: the drawn body's centre against the camera's root along the run: %.2f HU at %.0f HU/s, %.2f HU "
              "at %.0f HU/s after the spin dash (under 2) [0.5.1: 15.8 and 39.6]", r.name, a.lead, a.lead_speed, d.lead,
              d.lead_speed);
    }
    s.shutdown();
}

// ---- T3: multi-pair ticks against one-pair ticking, the whole render (sadc docs/research/gsa1_060_pops.md 5.6 with its
// review R.5.2; fix round 0.6 leftover 1) ------------------------------------------------------------------------------
// The module's frame loop (Session::tick(dt) + Session::render(-1)) with 60 fps frames and long frames of 38 / 62 / 92 /
// 145 ms (the jump lines of the owner's 0.6.0 log): a frame of 33 ms or more runs 2-5 pairs in one tick. A reference
// character in the same Session ticks the same per-pair inputs one pair per tick, in step, and renders at the test frame's
// own alpha. libsa1 captures every pair of a multi-pair tick (F1 with the review's refresh, R.3.1), so the WHOLE drawn
// render must be bit-identical to the reference in every frame: vertices, normals, UVs, colours, draws, sprites, lines,
// root, yaw, flags, and the state. 0.6.0's libsa1 drew a multi-pair tick between pairs k apart (the root up to 61 HU off
// the path, the body 26 HU); F1 without the refresh got the root right and the body wrong (review R.3.2: 66 frames off by
// up to 33.7 HU, inside the spin-dash charge), which a root-only check misses.
struct PairsIn {
    float sx = 0, sy = 0;
    uint32_t b = 0;
};
typedef PairsIn (*PairsScript)(double g);   // g: game seconds (pairs / 30) when the tick starts; one input per tick

// Sonic (review R.3.2's scenario on the flat floor): runs, jumps every 5 s, a spin dash charged standing at 11.4-12.6 s
static PairsIn pairs_sonic(double g)
{
    PairsIn in;
    double c = std::fmod(g, 15.0), j = std::fmod(g, 5.0);
    in.sy = (g >= 0.5 && (c < 11.0 || c >= 12.6)) ? 1.0f : 0.0f;
    if (j >= 3.0 && j < 3.2) {
        in.b |= SA1_BUTTON_JUMP;
    }
    if (c >= 11.4 && c < 12.6) {
        in.b |= SA1_BUTTON_ACTION;
    }
    return in;
}
// Tails: runs, jumps at 3 s of every 8 and flies (jump taps) until 5.5 s: the ball and the flight with their afterimages
static PairsIn pairs_tails(double g)
{
    PairsIn in;
    double c = std::fmod(g, 8.0);
    in.sy = g >= 0.5 ? 1.0f : 0.0f;
    if ((c >= 3.0 && c < 3.15) || (c >= 3.4 && c < 5.5 && std::fmod(c, 0.4) < 0.15)) {
        in.b |= SA1_BUTTON_JUMP;
    }
    return in;
}

struct PairsStats {
    uint32_t frames = 0, identical = 0, topo = 0, state_diff = 0;
    uint32_t multi = 0, multi_charge = 0, max_k = 0;   // ticks of 2+ pairs, of them in Sonic's spin-dash charge (mode 4)
    float root_max = 0, vert_max = 0, excess_max = 0;  // largest differences against the reference (HU)
    double worst_t = -1;
    bool ok = true;
};

template <typename T>
static bool pairs_same(const std::vector<T> &a, const std::vector<T> &b)
{
    return a.size() == b.size() && (a.empty() || std::memcmp(a.data(), b.data(), a.size() * sizeof(T)) == 0);
}

static bool pairs_same_state(const sa1_state_ex &a, const sa1_state_ex &b)
{
    return std::memcmp(a.position, b.position, sizeof a.position) == 0 &&
           std::memcmp(a.velocity, b.velocity, sizeof a.velocity) == 0 && std::memcmp(&a.yaw, &b.yaw, sizeof a.yaw) == 0 &&
           a.action == b.action && std::memcmp(&a.frame, &b.frame, sizeof a.frame) == 0 && a.step == b.step &&
           a.mode == b.mode && a.smode == b.smode && a.game_flags == b.game_flags && a.player_flags == b.player_flags &&
           std::memcmp(a.angle, b.angle, sizeof a.angle) == 0 &&
           std::memcmp(a.sa1_position, b.sa1_position, sizeof a.sa1_position) == 0 &&
           std::memcmp(a.speed, b.speed, sizeof a.speed) == 0;
}

static PairsStats pairs_run(Session &s, int32_t kind, const float pos[3], const std::vector<float> &dts, double seconds,
                            PairsScript script)
{
    PairsStats M;
    std::string e;
    int32_t id = s.create(kind, pos, 0.0f, e), rid = id > 0 ? s.create(kind, pos, 0.0f, e) : 0;
    if (id <= 0 || rid <= 0) {
        std::printf("        create %s: %s\n", kind_name(kind), e.c_str());
        M.ok = false;
        if (id > 0) {
            s.destroy(id);
        }
        return M;
    }
    const float kPair = (float)(1.0 / 30.0);   // one pair per reference tick (float(1/30) > 1/30: exactly one)
    std::vector<PairsIn> pair_in;               // the input of every pair the test character ran (index = pair - 1)
    std::vector<sa1_event> ev;
    float prev_root[3] = {0, 0, 0}, prev_ref[3] = {0, 0, 0};
    bool have_prev = false;
    double t = 0;
    size_t k = 0;
    while (t < seconds && M.ok) {
        float dt = dts[k++ % dts.size()];
        t += dt;
        Character *c = s.get(id);
        uint64_t before = c->pairs_total;
        PairsIn in = script((double)before / 30.0);
        if (s.tick(id, in.sx, in.sy, 0.0f, in.b, dt) != SA1_OK || s.render(id, -1.0f) != SA1_OK) {
            std::printf("        tick / render at t=%.3f: %s\n", t, s.last_error().c_str());
            M.ok = false;
            break;
        }
        s.poll_events(ev);
        c = s.get(id);
        uint32_t ran = (uint32_t)(c->pairs_total - before);
        pair_in.insert(pair_in.end(), ran, in);
        if (ran >= 2) {
            M.multi++;
            M.multi_charge += kind == SA1_CHAR_SONIC && c->st.mode == 4;
            M.max_k = std::max(M.max_k, ran);
        }
        // the reference: the same inputs, one pair per tick, rendered at this frame's alpha
        Character *rc = s.get(rid);
        while (M.ok && rc->pairs_total < c->pairs_total) {
            uint64_t rb = rc->pairs_total;
            const PairsIn &q = pair_in[(size_t)rb];
            if (s.tick(rid, q.sx, q.sy, 0.0f, q.b, kPair) != SA1_OK) {
                std::printf("        reference tick at t=%.3f: %s\n", t, s.last_error().c_str());
                M.ok = false;
            }
            s.poll_events(ev);
            rc = s.get(rid);
            if (rc->pairs_total != rb + 1) {
                std::printf("        the reference ran %u pairs in one tick\n", (unsigned)(rc->pairs_total - rb));
                M.ok = false;
            }
        }
        if (!M.ok || s.render(rid, c->r_alpha) != SA1_OK) {
            M.ok = false;
            break;
        }
        rc = s.get(rid);
        M.frames++;
        M.state_diff += !pairs_same_state(c->st, rc->st);
        bool same_n = c->r_triangles == rc->r_triangles && c->r_draws.size() == rc->r_draws.size() &&
                      c->r_sprites.size() == rc->r_sprites.size() && c->r_lines.size() == rc->r_lines.size();
        M.topo += !same_n;
        bool same = same_n && pairs_same(c->r_tpos, rc->r_tpos) && pairs_same(c->r_tnrm, rc->r_tnrm) &&
                    pairs_same(c->r_tuv, rc->r_tuv) && pairs_same(c->r_tcol, rc->r_tcol) &&
                    pairs_same(c->r_draws, rc->r_draws) && pairs_same(c->r_sprites, rc->r_sprites) &&
                    pairs_same(c->r_lines, rc->r_lines) && std::memcmp(c->r_pos, rc->r_pos, sizeof c->r_pos) == 0 &&
                    std::memcmp(&c->r_yaw, &rc->r_yaw, sizeof c->r_yaw) == 0 && c->r_flags == rc->r_flags &&
                    c->r_interpolated == rc->r_interpolated && c->batch_sig == rc->batch_sig;
        M.identical += same;
        float droot = dist3(c->r_pos, rc->r_pos), dv = 0;
        if (same_n) {
            for (size_t q = 0; q < c->r_tpos.size(); q++) {
                dv = std::max(dv, std::fabs(c->r_tpos[q] - rc->r_tpos[q]));
            }
        }
        if (!same && M.worst_t < 0) {
            M.worst_t = t;
        }
        M.root_max = std::max(M.root_max, droot);
        M.vert_max = std::max(M.vert_max, same_n ? dv : 1e9f);
        if (have_prev) {   // the drawn root's move against the reference's (the lurch of 0.6.0: up to 33 HU too far)
            M.excess_max = std::max(M.excess_max, dist3(c->r_pos, prev_root) - dist3(rc->r_pos, prev_ref));
        }
        std::memcpy(prev_root, c->r_pos, sizeof prev_root);
        std::memcpy(prev_ref, rc->r_pos, sizeof prev_ref);
        have_prev = true;
        if (g_verbose && (ran >= 2 || !same)) {
            std::printf("        t %7.3f dt %5.1f ms  pairs %u alpha %.3f  mode %d action %d  %s  root off %.4f  "
                        "vertices off %.4f\n", t, dt * 1000.0f, ran, c->r_alpha, (int)c->st.mode, (int)c->st.action,
                        same ? "identical" : "DIFFERS", droot, same_n ? dv : -1.0f);
        }
    }
    s.destroy(rid);
    s.destroy(id);
    return M;
}

static void test_pairs(const std::string &gdi)
{
    std::printf("frame loop with multi-pair ticks (38 / 62 / 92 / 145 ms frames) against one-pair ticking, the whole "
                "render (T3; gsa1_060_pops.md 5.6, R.5.2):\n");
    Session s;
    std::string e;
    if (!s.init(gdi, e)) {
        CHECK(false, "init: %s", e.c_str());
        return;
    }
    std::vector<sa1_collision_tri> floor = flat_floor(16384.0f, 1024.0f, 0.0f);
    CHECK(s.set_world(floor, e), "a flat floor of %u triangles (%s)", (unsigned)floor.size(), e.c_str());
    const float start[3] = {-15000.0f, 0.0f, 40.0f};
    // 60 fps with a long frame every 0.5 s (38, 62, 92, 145 ms in turn; every 0.25 s in 11.45-12.55 s, Sonic's
    // spin-dash charge). After 60 fps frames a 62 / 92 / 145 ms frame runs 2 / 2-3 / 4-5 pairs; a 38 ms one runs 1 or 2
    // (2 only when the alpha before it is at least 0.86)
    const float longs[4] = {0.038f, 0.062f, 0.092f, 0.145f};
    std::vector<float> dts;
    double wall = 0.0, next = 0.5;
    for (int n = 0; wall < 20.0;) {
        float dt = 1.0f / 60.0f;
        if (wall >= next) {
            dt = longs[n++ % 4];
            next += (wall >= 11.45 && wall < 12.55) ? 0.25 : 0.5;
        }
        dts.push_back(dt);
        wall += dt;
    }
    struct Case {
        const char *what;
        int32_t kind;
        PairsScript script;
        double seconds;
    };
    const Case cases[] = {{"Sonic runs, jumps, charges and releases a spin dash", SA1_CHAR_SONIC, pairs_sonic, 16.0},
                          {"Tails runs, jumps and flies", SA1_CHAR_TAILS, pairs_tails, 8.0}};
    for (const Case &cs : cases) {
        PairsStats M = pairs_run(s, cs.kind, start, dts, cs.seconds, cs.script);
        bool sonic = cs.kind == SA1_CHAR_SONIC;
        CHECK(M.ok && M.frames > 100 && M.identical == M.frames && M.state_diff == 0 && M.multi >= 10 && M.max_k >= 4 &&
                  (!sonic || M.multi_charge >= 2),
              "%s (%.0f s, 60 fps + 38 / 62 / 92 / 145 ms frames): %u ticks of 2+ pairs (largest %u; %u in the spin-dash "
              "charge); the whole drawn render is the one-pair reference's, bit for bit, in %u of %u frames (first "
              "difference at t %.3f; largest root difference %.4f HU, vertices %.4f HU, %u frames with other draw counts); "
              "the drawn root moved at most %.4f HU further than the reference's in a frame; the state differs in %u "
              "frames [0.6.0's libsa1: root up to 61 HU off the path, the body 26 HU; F1 without the refresh: the body "
              "up to 33.7 HU in the charge]",
              cs.what, cs.seconds, M.multi, M.max_k, M.multi_charge, M.identical, M.frames, M.worst_t, M.root_max,
              M.vert_max, M.topo, M.excess_max, M.state_diff);
    }
    s.shutdown();
}

static void test_material_census(const std::string &gdi, const std::string &out_path);

static void test_session(const std::string &gdi, const std::vector<sa1_collision_tri> &tris,
                         const std::vector<Spawn> &spawns, float seconds, bool chars)
{
    std::printf("libsa1 session (the module's code path):\n");
    Session s;
    std::string e;
    bool ok = s.init(gdi, e);
    CHECK(ok, "init + disc load in %.0f ms (%s)", s.disc_load_ms(), ok ? "" : e.c_str());
    for (const std::string &l : s.take_log()) {
        if (g_verbose || l.find("warn") != std::string::npos || l.find("error") != std::string::npos) {
            std::printf("        %s\n", l.c_str());
        }
    }
    if (!ok) {
        return;
    }
    {
        std::string scrubbed = s.scrub("cannot open " + parent_dir(gdi) + "/track03.bin");
        CHECK(scrubbed.find(parent_dir(gdi)) == std::string::npos && scrubbed.find("<disc>") != std::string::npos,
              "messages for Lua hide the disc directory (\"%s\")", scrubbed.c_str());
    }
    ok = s.set_world(tris, e);
    sa1_collision_info ci;
    s.world_info(ci);
    CHECK(ok && ci.mode == SA1_COLLISION_MODE_GRID && ci.triangles == tris.size(),
          "sa1_collision_set_static: %u triangles (%u collidable) in %.1f ms (%s)", (unsigned)ci.triangles,
          (unsigned)ci.collidable_triangles, s.world_set_ms(), ok ? "" : e.c_str());
    Spawn sp = spawns.empty() ? Spawn{{0, 0, 0}, 0} : spawns[0];
    float pos[3] = {sp.pos[0], sp.pos[1], sp.pos[2] + 32.0f};
    double cms = 0;
    int32_t id = s.create(SA1_CHAR_SONIC, pos, sp.yaw, e, &cms);
    s.world_info(ci);
    CHECK(id > 0, "Sonic created at (%.1f %.1f %.1f) in %.0f ms: GRID %u objects, %u triangles (%u split), %u kill "
          "objects (%s)", pos[0], pos[1], pos[2], cms, (unsigned)ci.grid_objects, (unsigned)ci.grid_triangles,
          (unsigned)ci.grid_split, (unsigned)ci.grid_kill_objects, id > 0 ? "" : e.c_str());
    if (id <= 0) {
        return;
    }
    Character *c = s.get(id);
    CHECK(c && c->out_triangles > 0 && c->batch_count > 0 && c->rendered,
          "drawn right after creation (the start pose): %u triangles in %u batches", c ? c->out_triangles : 0,
          c ? c->batch_count : 0);
    RunLog L;
    std::printf("      Sonic, %.1f s at 60 fps: idle 1.5 s, stick forward along the spawn yaw, jump at 4.0 s\n", seconds);
    drive(s, id, seconds, sp.yaw, L, true);
    CHECK(!L.fault, "no world fault (%u ticks, %llu pairs = %.1f s of game time)", L.ticks, (unsigned long long)L.pairs,
          L.pairs / 30.0);
    CHECK(L.landed, "lands on gm_construct: on the ground at t = %.2f s, z %.1f HU (spawn floor %.1f)", L.land_t,
          L.land_z, sp.pos[2]);
    CHECK(L.run_dist > 200.0f, "runs: %.0f HU in 2.5 s with the stick forward", L.run_dist);
    CHECK(L.jump_rise > 20.0f, "jumps: rises %.1f HU above the take-off", L.jump_rise);
    CHECK(L.relanded, "lands again after the jump");
    CHECK(L.mxcsr_kept, "the host's MXCSR is unchanged by every tick");
    INFO("tick: %.3f ms average, %.3f ms worst per call (frame dt 1/60 s); draws up to %u triangles in %u batches",
         L.tick_sum / std::max(1u, L.ticks), L.tick_max, L.max_tris, L.max_groups);
    {
        std::string ev;
        for (const auto &kv : L.events) {
            ev += format("%stype %u x%u", ev.empty() ? "" : ", ", kv.first, kv.second);
        }
        INFO("events: %s", ev.empty() ? "none" : ev.c_str());
    }
    c = s.get(id);
    if (c) {
        check_view(s, *c, "Sonic after the run");
        test_lerp(s, id);
    }
    test_textures(s);
    s.destroy(id);

    // stick direction against the camera yaw: the game's analog conversion turns the run direction a few degrees
    // (libsa1 keeps it); the addon's gsa1_stick_trim ConVar can compensate
    for (int mapping = 0; mapping < 2; mapping++) {
        bool raw = mapping == 0;
        std::string offs;
        float worst = 0.0f;
        for (int a = -135; a <= 180; a += 45) {
            int32_t sid = s.create(SA1_CHAR_SONIC, pos, sp.yaw, e);
            if (sid <= 0) {
                break;
            }
            float phi = a * 3.14159265f / 180.0f;
            float cam = sp.yaw;
            for (int f = 0; f < 60 + 36; f++) {
                bool stick = f >= 60;
                s.tick(sid, stick ? std::sin(phi) : 0.0f, stick ? std::cos(phi) : 0.0f, cam, 0, 1.0f / 60.0f, raw);
            }
            Character *sc = s.get(sid);
            double want = sp.yaw - phi;
            double got = std::atan2(sc->st.velocity[1], sc->st.velocity[0]);
            double d = std::remainder(got - want, 2.0 * 3.14159265358979) * 180.0 / 3.14159265358979;
            offs += format("%s%+d:%+.1f", offs.empty() ? "" : " ", a, d);
            worst = std::max(worst, (float)std::fabs(d));
            s.destroy(sid);
        }
        if (raw) {
            INFO("raw stick (the DC pad's dead zone): stick angle -> run direction error (deg) %s", offs.c_str());
        } else {
            CHECK(worst < 1.0f, "exact stick mapping: stick angle -> run direction error (deg) %s (worst %.2f)",
                  offs.c_str(), worst);
        }
    }

    if (chars) {
        const int32_t others[] = {SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA, SA1_CHAR_BIG};
        for (int32_t k : others) {
            double ms = 0;
            int32_t cid = s.create(k, pos, sp.yaw, e, &ms);
            if (cid <= 0) {
                CHECK(false, "%s: create: %s", kind_name(k), e.c_str());
                continue;
            }
            RunLog R;
            drive(s, cid, 6.0f, sp.yaw, R, g_verbose);
            Character *cc = s.get(cid);
            CHECK(!R.fault && R.landed && R.run_dist > 50.0f && R.max_tris > 0,
                  "%-8s created in %4.0f ms; lands at t=%.2f, runs %.0f HU, jump +%.0f HU, draws <= %u tris / %u batches, "
                  "tick avg %.3f ms", kind_name(k), ms, R.land_t, R.run_dist, R.jump_rise, R.max_tris, R.max_groups,
                  R.tick_sum / std::max(1u, R.ticks));
            if (R.fault && cc) {
                std::printf("        %s\n", s.last_error().c_str());
            }
            s.destroy(cid);
        }
    }
    test_effects(s, pos, sp.yaw);
    test_upgrades(s, pos, sp.yaw);
    test_stale_events(s, pos, sp.yaw);
    test_audio(s, pos, sp.yaw);
    for (const std::string &l : s.take_log()) {
        if (g_verbose || l.find("error") != std::string::npos) {
            std::printf("        %s\n", l.c_str());
        }
    }
    s.shutdown();
}


// ---- the material census (round 4c, the Light Speed charge freeze): every render state each character draws -------
// Every character with all of its upgrades plays a script that uses its moves (run, jumps, the actions in the air,
// action and Y, a held action: Sonic's Light Speed charge until the aura, Knuckles' Maximum Heat, E-102's lock-on, Big's
// cast) on a flat floor. Every batch state that appears - archive, texture, SA1_DRAW_* flags, blend factors, address
// mode, pass, primitives, the lit translucent batches' alpha (0.9.1) - is written to material_census.txt next to the
// test, one line per state:
//   kind archive texture flags(hex) src dst wrap pass prims(hex) alpha
// The addon's material pre-warm (cl_warm.lua) must cover every one of them; tests/warm_test.lua checks that against
// this file in Garry's Mod's own LuaJIT (build.py --test).
static void census_script(double t, float &sy, uint32_t &b)
{
    const uint32_t J = SA1_BUTTON_JUMP, A = SA1_BUTTON_ACTION, Y = SA1_BUTTON_ACTION2;
    sy = 0.0f;
    b = 0;
    if (t >= 1.0 && t < 2.5) sy = 1.0f;
    if (t >= 2.5 && t < 2.8) b = J;                       // a running jump
    if (t >= 2.9 && t < 3.6) b = J;                       // jump again in the air and hold (homing, flight, glide, hover)
    if (t >= 4.0 && t < 4.15) b = A;                      // action
    if (t >= 4.5 && t < 4.6) b = Y;                       // Y
    if (t >= 5.0 && t < 5.6) {                            // action held while running (roll)
        sy = 1.0f;
        b = A;
    }
    if (t >= 6.0 && t < 9.5) b = A;                       // action held standing (charges, lock-on, cast)
    if (t >= 10.5 && t < 10.7) b = J;                     // jump, then action in the air
    if (t >= 10.8 && t < 11.6) b = A;
    if (t >= 12.0 && t < 12.1) b = A;                     // a last action standing
}

#if defined(SA1_API_FACE)
// 0.9.4a (sadc docs/research/faces_wheel_plan.md 6.4 task 1): the event head's render states. The EV head (the cutscene
// face G-SA1 shows with event faces, face animations, lip sync and the wheel's face animations) draws textures no gameplay
// state draws (Sonic 25-27, Tails 19-20, Knuckles 2-4, Amy 9-10 with SA1_DRAW_* 0x30, some also 0x20; Big 2 / 27), so the
// first face would make its materials at first use (round 4c's freeze pattern). After its scripted play each character
// with a face (Sonic, Tails, Knuckles, Amy, Big) turns event faces on, idles a second (the game's blinking idle), then
// plays every face animation it can show (sa1_face_info.letters: Big 14 of 31) at once, kCensusFaceEach frames each;
// Tails flies through the second half (his flight model's head).
static const int kCensusFaceIdle = 60, kCensusFaceEach = 8;

static bool census_face_kind(int32_t k)
{
    return k == SA1_CHAR_SONIC || k == SA1_CHAR_TAILS || k == SA1_CHAR_KNUCKLES || k == SA1_CHAR_AMY || k == SA1_CHAR_BIG;
}

static int census_face_count(uint32_t letters)
{
    int n = 0;
    for (int i = 0; i < 31; i++) {
        n += (int)((letters >> i) & 1u);
    }
    return n;
}

// frame i of the face segment: the face calls and the buttons; false with err when libsa1 refuses a call
static bool census_face_step(Session &s, int32_t id, int32_t k, uint32_t letters, int i, uint32_t &b, std::string &err)
{
    b = 0;
    sa1_status st = SA1_OK;
    if (i == 0) {
        st = sa1_character_face_mode(s.ctx(), id, SA1_FACE_MODE_EVENT);
    }
    int j = i - kCensusFaceIdle, n = census_face_count(letters);
    if (j >= 0 && j % kCensusFaceEach == 0 && j / kCensusFaceEach < n) {
        int slot = j / kCensusFaceEach, seen = 0;
        for (int a = 0; a < 31 && st == SA1_OK; a++) {
            if (((letters >> a) & 1u) && seen++ == slot) {
                const char script[2] = {(char)(a < 26 ? 'A' + a : 'a' + (a - 26)), 0};
                st = sa1_character_face(s.ctx(), id, script, SA1_FACE_NOW);
            }
        }
    }
    if (k == SA1_CHAR_TAILS && j >= 0) {
        int h = (n / 2) * kCensusFaceEach;            // the second half: a jump, then the jump again held (flight)
        if ((j >= h && j < h + 10) || j >= h + 16) {
            b = SA1_BUTTON_JUMP;
        }
    }
    if (st != SA1_OK) {
        const char *e = sa1_last_error(s.ctx());
        err = format("%s (%s)", sa1_status_string(st), e ? e : "");
    }
    return st == SA1_OK;
}
#endif

static void test_material_census(const std::string &gdi, const std::string &out_path)
{
    std::printf("material census (every render state of every character; the material pre-warm's reference):\n");
    Session s;
    std::string e;
    if (!s.init(gdi, e)) {
        CHECK(false, "init: %s", e.c_str());
        return;
    }
    std::vector<sa1_collision_tri> floor = flat_floor(16384.0f, 1024.0f, 0.0f);
    if (!s.set_world(floor, e)) {
        CHECK(false, "set_world: %s", e.c_str());
        return;
    }
    static const int32_t kinds[] = {SA1_CHAR_SONIC, SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA,
                                    SA1_CHAR_BIG};
    std::map<std::string, int> states;
    std::string per;
    bool ok = true;
    for (int32_t k : kinds) {
        size_t n = 0;
        const UpgradeDef *tab = upgrade_table(n);
        std::vector<const UpgradeDef *> ups;
        for (size_t i = 0; i < n; i++) {
            if (tab[i].kind == k) {
                ups.push_back(&tab[i]);
            }
        }
        const float pos[3] = {-15000.0f, 0.0f, 40.0f};
        int32_t id = s.create(k, pos, 0.0f, e, nullptr, &ups);
        if (id <= 0) {
            CHECK(false, "%s: create: %s", kind_name(k), e.c_str());
            ok = false;
            continue;
        }
        // 0.9.1 (gsa1_070_bird.md F4 with its review R.2.4): Amy with her bird, as G-SA1 creates her by default
        // (feat/cl_charopt.lua, gsa1_amy_bird 1): its 11 render states (archive 0, textures 44-52) are in the census
        if (k == SA1_CHAR_AMY) {
            sa1_status bs = sa1_character_set_companion(s.ctx(), id, SA1_COMPANION_BIRD, 1);
            CHECK(bs == SA1_OK, "Amy: her bird for the census (%s)", sa1_status_string(bs));
        }
        std::vector<sa1_event> ev;
        uint32_t mine = 0, blended = 0, textured_fx = 0;
        const int script_frames = 60 * 13;
        int face_frames = 0;
        uint32_t face_letters = 0, face_new = 0;
#if defined(SA1_API_FACE)
        // 0.9.4a: the face segment (census_face_step) of the characters with a face
        if (census_face_kind(k)) {
            sa1_face_info fi;
            std::memset(&fi, 0, sizeof fi);
            fi.struct_size = sizeof fi;
            sa1_status fs = sa1_face_info_get(s.ctx(), k, &fi);
            CHECK(fs == SA1_OK && fi.letters != 0, "%s: sa1_face_info_get for the census's face segment (%s, letters 0x%08X)",
                  kind_name(k), sa1_status_string(fs), (unsigned)fi.letters);
            face_letters = fs == SA1_OK ? fi.letters : 0u;
            face_frames = face_letters ? kCensusFaceIdle + kCensusFaceEach * census_face_count(face_letters) + 30 : 0;
        }
#endif
        for (int f = 0; f < script_frames + face_frames; f++) {
            float sy = 0;
            uint32_t b = 0;
            if (f < script_frames) {
                census_script(f / 60.0, sy, b);
            }
#if defined(SA1_API_FACE)
            else if (!census_face_step(s, id, k, face_letters, f - script_frames, b, e)) {
                CHECK(false, "%s: a face call of the census's face segment at frame %d: %s", kind_name(k), f, e.c_str());
                ok = false;
                break;
            }
#endif
            if (s.tick(id, 0.0f, sy, 0.0f, b, 1.0f / 60.0f) != SA1_OK || s.render(id, -1.0f) != SA1_OK) {
                CHECK(false, "%s: tick / render at frame %d: %s", kind_name(k), f, s.last_error().c_str());
                ok = false;
                break;
            }
            s.poll_events(ev);
            const Character *c = s.get(id);
            for (uint32_t bi = 0; bi < c->batch_count; bi++) {
                const RenderBatch &rb = c->batches[bi];
                // 0.9.1 (translucency T1): the lit translucent batches' alpha (a material of its own: $alpha), last
                std::string key = format("%d %d %d %X %u %u %u %u %X %u", (int)k, rb.archive, rb.texture, rb.flags,
                                         (unsigned)rb.blend_src, (unsigned)rb.blend_dst, rb.wrap, rb.pass, rb.prims,
                                         (unsigned)rb.alpha);
                if (states.emplace(key, 1).second) {
                    mine++;
                    blended += rb.pass;
                    textured_fx += rb.archive >= 1;
                    face_new += f >= script_frames;
                }
            }
        }
        s.destroy(id);
        per += format("%s%s %u (%u blended, %u from effect archives%s)", per.empty() ? "" : ", ", kind_name(k), mine,
                      blended, textured_fx, face_frames ? format(", %u new in the face segment", face_new).c_str() : "");
    }
    std::FILE *f = std::fopen(out_path.c_str(), "wb");
    if (f) {
        std::fprintf(f, "# G-SA1 material census (core_test): kind archive texture flags(hex) src dst wrap pass prims(hex) "
                        "alpha\n");
        for (const auto &kv : states) {
            std::fprintf(f, "%s\n", kv.first.c_str());
        }
        std::fclose(f);
    }
    CHECK(ok && f && states.size() > 60, "%u render states in all (%s), written to %s", (unsigned)states.size(),
          per.c_str(), out_path.c_str());
#if defined(SA1_API_FACE)
    // 0.9.4a: the event heads' own textures (archive 0, flags 0x30; faces_events.md 5.2) are in the census
    {
        static const int ev[][2] = {{SA1_CHAR_SONIC, 25}, {SA1_CHAR_SONIC, 26}, {SA1_CHAR_SONIC, 27}, {SA1_CHAR_TAILS, 19},
                                    {SA1_CHAR_TAILS, 20}, {SA1_CHAR_KNUCKLES, 2}, {SA1_CHAR_KNUCKLES, 3},
                                    {SA1_CHAR_KNUCKLES, 4}, {SA1_CHAR_AMY, 9}, {SA1_CHAR_AMY, 10}};
        std::string missing;
        for (const auto &e2 : ev) {
            std::string pre = format("%d 0 %d 30 ", e2[0], e2[1]);
            bool have = false;
            for (const auto &kv : states) {
                have = have || kv.first.compare(0, pre.size(), pre) == 0;
            }
            if (!have) {
                missing += format(" %s %d", kind_name(e2[0]), e2[1]);
            }
        }
        CHECK(missing.empty(), "the event heads' own textures are in the census (Sonic 25-27, Tails 19-20, Knuckles 2-4, "
              "Amy 9-10; flags 0x30)%s%s", missing.empty() ? "" : ": missing", missing.c_str());
    }
#endif
    s.shutdown();
}

int main(int argc, char **argv)
{
    std::string bsp = gsa1_garrysmod_dir()[0] ? std::string(gsa1_garrysmod_dir()) + "\\maps\\gm_construct.bsp" : std::string();
    std::string gdi;
    const char *env = std::getenv("SA1_TEST_GDI");
    if (env) {
        gdi = env;
    }
    float seconds = 6.0f;
    int fuzz = 60;
    bool chars = true, jitter_only = false, pairs_only = false, climb_only = false, upgrades_only = false, flicker_only = false,
         census_only = false, host_only = false;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--bsp" && i + 1 < argc) {
            bsp = argv[++i];
        } else if (a == "--gdi" && i + 1 < argc) {
            gdi = argv[++i];
        } else if (a == "--seconds" && i + 1 < argc) {
            seconds = (float)std::atof(argv[++i]);
        } else if (a == "--fuzz" && i + 1 < argc) {
            fuzz = std::atoi(argv[++i]);
        } else if (a == "--no-chars") {
            chars = false;
        } else if (a == "--verbose") {
            g_verbose = true;
        } else if (a == "--fuzz-save" && i + 2 < argc) {
            g_fuzz_save = std::atoi(argv[++i]);
            g_fuzz_save_path = argv[++i];
        } else if (a == "--jitter") {
            jitter_only = true;
        } else if (a == "--pairs") {
            pairs_only = true;
        } else if (a == "--climb") {
            climb_only = true;
        } else if (a == "--upgrades") {
            upgrades_only = true;
        } else if (a == "--flicker") {
            flicker_only = true;
        } else if (a == "--census") {
            census_only = true;
        } else if (a == "--host-input") {
            host_only = true;
        } else {
            std::printf("usage: core_test [--bsp MAP.bsp] [--gdi GAME.gdi] [--seconds S] [--fuzz N] [--no-chars] "
                        "[--verbose] [--jitter | --pairs | --climb | --upgrades | --flicker | --census | --host-input]\n");
            return 2;
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);   // a stuck test shows where it stopped, also through a pipe
    std::printf("G-SA1 core_test (libsa1 %s)\n", sa1_version_string());
    // the material census goes next to the test executable (build.py's warm_test reads it)
    std::string census_path = join_path(parent_dir(argv[0]).empty() ? std::string(".") : parent_dir(argv[0]),
                                        "material_census.txt");
    if (flicker_only || census_only) {
        test_view_rules();
        if (!gdi.empty()) {
            if (flicker_only) {
                test_flicker(gdi);
            }
            if (census_only) {
                test_material_census(gdi, census_path);
            }
        }
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    if (host_only) {
        if (!gdi.empty()) {
            test_host_input(gdi);
        }
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    if (climb_only && !gdi.empty()) {
        test_climb_world(gdi);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    if (jitter_only || pairs_only) {
        if (!gdi.empty()) {
            if (jitter_only) {
                test_jitter(gdi);
            }
            test_pairs(gdi);
        }
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    test_config();
    test_paths(bsp);
    test_view_rules();
    std::vector<sa1_collision_tri> tris;
    BspWorldStats st;
    std::vector<Spawn> spawns;
    bool have_map = test_bsp(bsp, tris, st, spawns);
    if (upgrades_only && have_map && !gdi.empty()) {
        Session us;
        std::string ue;
        if (us.init(gdi, ue) && us.set_world(tris, ue)) {
            Spawn sp = spawns.empty() ? Spawn{{0, 0, 0}, 0} : spawns[0];
            float up[3] = {sp.pos[0], sp.pos[1], sp.pos[2] + 32.0f};
            test_upgrades(us, up, sp.yaw);
        }
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    if (fuzz > 0) {
        test_fuzz(bsp, fuzz);
    }
    if (gdi.empty()) {
        std::printf("libsa1 session: skipped (no --gdi and no SA1_TEST_GDI)\n");
    } else {
        if (have_map) {
            test_session(gdi, tris, spawns, std::max(seconds, 6.0f), chars);
        }
        test_jitter(gdi);
        test_pairs(gdi);
        test_flicker(gdi);
        test_climb_world(gdi);
        test_host_input(gdi);
        test_material_census(gdi, census_path);
    }
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
