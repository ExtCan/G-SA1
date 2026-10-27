// G-SA1 map tests (offline, no Garry's Mod needed): the map's collision the way 0.5 loads it (src/core/mapjob.*:
// G64's sources - world brushes, displacements, static props' physics models, brush entities - cleaned), the
// physics model parser, the background job in file mode and in fed mode (the addon's way: only the byte ranges it
// asks for), the per-map cache (written, read, refused when damaged or built with other settings), cancelling, and
// moving collision objects in libsa1 (a lift that carries Sonic up and sideways, a door that stops him until it is
// switched off, the object budget, a brush entity of gm_construct he lands on), and thin walls (4, 8 and 16 units:
// runs and spin dashes into them with and without bsp.hpp's thin_wall_max). 0.5.1: the world prepared on the job's
// worker (libsa1's GRID synthesis): installed in O(1), characters on it move bit for bit as on set_static's world,
// prepare = false, a job dropped while it prepares. 0.8: surface types (sadc docs/research/gsa1_060_dig.md F1, F3-F5):
// the material names, every triangle tagged, grass diggable and concrete not on gm_construct and gm_bigcity (Garry's
// Mod's own copy of the workshop file, garrysmod/cache/workshop/105982362.gma, read-only), gm_flatgrass 99% diggable,
// the cache keeping tags and slots (a changed table is a cache hit; a type resolved through its cached base chain),
// the classes without the preparation, and with the disc Knuckles digging on the grass and refused on the concrete.
//
//   map_test [--gdi GAME.gdi] [--gm GARRYSMOD_DIR] [--maps DIR] [--verbose]
//
//   --gm    default Garry's Mod's garrysmod folder, found by tests/gmod_paths.hpp (read-only: maps/gm_construct.bsp, the VPKs and
//           addons for the model files)
//   --maps  a directory with more maps (gm_bigcity_improved_rp, gm_driversheaven_tdm: the static prop checks)
//   --gdi   default $SA1_TEST_GDI; without a disc the libsa1 checks (moving objects) are skipped
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "../src/core/mapjob.hpp"
#include "../src/core/movers.hpp"
#include "../src/core/phy.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"
#include "gamefs.hpp"
#include "mapdrive.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

using namespace gsa1;

static int g_fail = 0, g_checks = 0;
static bool g_verbose = false;

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

static uint32_t g_rng = 12345u;
static uint32_t rnd()
{
    g_rng = g_rng * 1664525u + 1013904223u;
    return g_rng >> 8;
}

// ---- 1. the ranges a reader hands over -----------------------------------------------------------------------------
static void test_ranges()
{
    std::printf("RangeByteSource\n");
    RangeByteSource rs(100);
    std::string a(10, 'a'), b(10, 'b'), c(30, 'c');
    bool ok = rs.add(10, a.data(), 10) && rs.add(30, b.data(), 10);
    std::vector<std::pair<uint64_t, uint64_t>> m;
    rs.missing(0, 100, m);
    CHECK(ok && m.size() == 3 && m[0] == std::make_pair((uint64_t)0, (uint64_t)10) &&
              m[1] == std::make_pair((uint64_t)20, (uint64_t)10) && m[2] == std::make_pair((uint64_t)40, (uint64_t)60),
          "two ranges added, three gaps");
    ok = rs.add(15, c.data(), 30);   // over the end of the first and all of the second
    char buf[8] = {0};
    bool got = rs.read(12, buf, 5);
    m.clear();
    rs.missing(0, 100, m);
    CHECK(ok && got && std::memcmp(buf, "aaacc", 5) == 0 && rs.has(10, 35) && !rs.has(9, 2) && m.size() == 2 &&
              m[1] == std::make_pair((uint64_t)45, (uint64_t)55) && rs.bytes() == 35,
          "an overlapping range replaces the bytes it covers (read across chunks, %llu bytes held)",
          (unsigned long long)rs.bytes());
    CHECK(!rs.add(95, a.data(), 10) && !rs.read(90, buf, 8) && !rs.read(200, buf, 1),
          "ranges beyond the file are refused; reading a gap fails");
}

// ---- 2. physics models -------------------------------------------------------------------------------------------
static void test_phy(gamefs::GameFs &fs)
{
    std::printf("physics models (.phy) from the game's VPKs (%zu VPKs)\n", fs.vpks());
    struct Want {
        const char *path;
        uint32_t hulls, tris;
    };
    const Want want[] = {{"models/props_c17/furniturecouch001a.phy", 4, 48},
                         {"models/props_c17/furnituretable003a.phy", 9, 116},
                         {"models/props_industrial/warehouse_shelf001.phy", 11, 156},
                         {"models/props_vehicles/car002a_physics.phy", 4, 118}};
    std::string couch;
    for (const Want &w : want) {
        std::string data, err;
        if (!fs.read(w.path, data)) {
            INFO("%s is not in this installation", w.path);
            continue;
        }
        if (couch.empty()) {
            couch = data;
        }
        PhyModel m;
        bool ok = parse_phy(data.data(), data.size(), m, err);
        uint32_t outward = 0, total = 0;
        for (const std::vector<float> &h : m.hulls) {
            double c[3] = {0, 0, 0};
            for (size_t i = 0; i < h.size(); i += 3) {
                for (int k = 0; k < 3; k++) {
                    c[k] += h[i + k] / (double)(h.size() / 3);
                }
            }
            for (size_t t = 0; t + 8 < h.size(); t += 9) {
                const float *a = &h[t], *b = a + 3, *cc = a + 6;
                double e1[3] = {b[0] - a[0], b[1] - a[1], b[2] - a[2]}, e2[3] = {cc[0] - a[0], cc[1] - a[1], cc[2] - a[2]};
                double n[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
                double mm[3] = {(a[0] + b[0] + cc[0]) / 3 - c[0], (a[1] + b[1] + cc[1]) / 3 - c[1], (a[2] + b[2] + cc[2]) / 3 - c[2]};
                outward += n[0] * mm[0] + n[1] * mm[1] + n[2] * mm[2] > 0.0;
                total++;
            }
        }
        CHECK(ok && m.hulls.size() == w.hulls && m.triangles == w.tris && outward == total,
              "%s: %zu convex pieces, %u triangles (want %u / %u), %u of %u wound outward; bounds (%.0f %.0f %.0f) .. "
              "(%.0f %.0f %.0f)%s%s", w.path, m.hulls.size(), m.triangles, w.hulls, w.tris, outward, total, m.mins[0],
              m.mins[1], m.mins[2], m.maxs[0], m.maxs[1], m.maxs[2], ok ? "" : ": ", ok ? "" : err.c_str());
        Shape sh;
        double ts = now_ms();
        bool sok = ok && shape_from_phy(m, sh, err);
        double shape_ms = now_ms() - ts;   // gsa1.ShapePhy does this on the game's thread when a prop first comes near
        float longest = 0.0f;
        for (const ShapeChunk &ch : sh.chunks) {
            for (const sa1_collision_tri &t : ch.tris) {
                for (int e = 0; e < 3; e++) {
                    float d = 0;
                    for (int k = 0; k < 3; k++) {
                        float x = t.v[(e + 1) % 3][k] - t.v[e][k];
                        d += x * x;
                    }
                    longest = std::max(longest, std::sqrt(d));
                }
            }
        }
        CHECK(sok && sh.tris > 0 && sh.chunks.size() == 1 && longest <= kMoverTess + 1.0f,
              "  as a moving object's shape: %u triangles in %zu chunk(s), longest edge %.0f HU (cleaned in %.2f ms)",
              sh.tris, sh.chunks.size(), longest, shape_ms);
    }
    std::string mdl, err;
    float mn[3], mx[3];
    if (fs.read("models/props_c17/furniturecouch001a.mdl", mdl, 136)) {
        bool ok = parse_mdl_hull(mdl.data(), mdl.size(), mn, mx, err);
        CHECK(ok && mdl.size() == 136 && mx[0] > mn[0] && mx[2] > mn[2],
              "the couch's .mdl header (136 bytes): hull (%.0f %.0f %.0f) .. (%.0f %.0f %.0f)", mn[0], mn[1], mn[2], mx[0],
              mx[1], mx[2]);
    }
    if (!couch.empty()) {
        // damaged copies: never a crash, bounded output
        uint32_t parsed = 0, refused = 0;
        for (int i = 0; i < 3000; i++) {
            std::string d = couch;
            int kind = i % 3;
            if (kind == 0) {
                d.resize(rnd() % d.size());
            } else {
                int flips = 1 + (int)(rnd() % 8);
                for (int f = 0; f < flips; f++) {
                    d[rnd() % d.size()] = (char)rnd();
                }
            }
            PhyModel m;
            std::string e;
            if (parse_phy(d.data(), d.size(), m, e)) {
                parsed++;
                Shape sh;
                shape_from_phy(m, sh, e);
            } else {
                refused++;
            }
        }
        CHECK(parsed + refused == 3000, "3000 damaged copies of the couch: %u parsed, %u refused, no crash", parsed, refused);
    }
}

// ---- 3. the map job ---------------------------------------------------------------------------------------------------
static bool same_result(const MapResult &a, const MapResult &b, std::string &why)
{
    if (a.world.size() != b.world.size()) {
        why = format("world %zu vs %zu triangles", a.world.size(), b.world.size());
        return false;
    }
    for (size_t i = 0; i < a.world.size(); i++) {
        if (std::memcmp(&a.world[i], &b.world[i], sizeof a.world[i]) != 0) {
            why = format("world triangle %zu differs", i);
            return false;
        }
    }
    if (a.models.size() != b.models.size()) {
        why = "brush models differ";
        return false;
    }
    for (const auto &kv : a.models) {
        auto it = b.models.find(kv.first);
        if (it == b.models.end() || it->second.tris != kv.second.tris || it->second.chunks.size() != kv.second.chunks.size()) {
            why = format("brush model %d differs", kv.first);
            return false;
        }
        for (size_t c = 0; c < kv.second.chunks.size(); c++) {
            const ShapeChunk &x = kv.second.chunks[c], &y = it->second.chunks[c];
            if (x.tris.size() != y.tris.size() ||
                std::memcmp(x.tris.data(), y.tris.data(), x.tris.size() * sizeof(sa1_collision_tri)) != 0 ||
                std::memcmp(x.center, y.center, sizeof x.center) != 0) {
                why = format("brush model %d chunk %zu differs", kv.first, c);
                return false;
            }
        }
    }
    return true;
}

static bool run_job(const std::string &map, const std::string &bsp, const MapJobOptions &o, gamefs::GameFs &fs,
                    bool fed, MapResult &out, std::string &err, MapDrive *d = nullptr)
{
    MapJob job;
    if (fed) {
        std::string head;
        File f;
        if (!f.open(bsp, err) || !gamefs::read_range(bsp, 0, 1036, head) ||
            !job.start_fed(map, head.data(), head.size(), f.size(), o, err)) {
            return false;
        }
    } else if (!job.start_file(map, bsp, o, err)) {
        return false;
    }
    return run_map_job(job, &fs, fed ? &bsp : nullptr, err, d) && job.take(out);
}

static std::string temp_dir()
{
    const char *t = std::getenv("TEMP");
    if (!t) {
        t = std::getenv("TMPDIR");
    }
    return join_path(t ? t : ".", "gsa1_map_test");
}

static void test_job(const std::string &bsp, gamefs::GameFs &fs, MapResult &keep)
{
    std::printf("map job: %s\n", bsp.c_str());
    fs.set_map(bsp);
    MapJobOptions o;
    MapResult a, b, np;
    std::string err, why;
    MapDrive da, db;
    double t0 = now_ms();
    bool ok = run_job("gm_construct", bsp, o, fs, false, a, err, &da);
    double ta = now_ms() - t0;
    const MapStats &s = a.st;
    CHECK(ok && s.props == 182 && s.props_solid == 4 && s.props_placed + s.props_missing + s.props_small == s.props_solid &&
              s.props_placed >= 1 && s.world.tris_extra > 0,
          "file mode: %zu world triangles in %.0f ms (%d polls); static props %u, solid %u, placed %u (%u convex pieces, "
          "%u triangles), missing %u, small %u; model files %u (%u found)%s%s", a.world.size(), ta, da.polls, s.props,
          s.props_solid, s.props_placed, s.props_hulls, s.world.tris_extra, s.props_missing, s.props_small, da.files,
          da.files_found, ok ? "" : ": ", ok ? "" : err.c_str());
    CHECK(ok && s.brush_entities >= 7 && s.brush_models >= 6 && a.models.count(3) == 1,
          "brush entities %u (solid classes), %u brush models as shapes (%u triangles, %u chunks), *3 (a func_brush) among "
          "them", s.brush_entities, s.brush_models, s.brush_model_tris, s.brush_model_chunks);
    CHECK(ok && s.world.one_way_solids > 0 && s.world.thickened_floors == 0 && s.world.displacements == 110 &&
              s.world.disp_tag_checked == 110 && s.world.disp_tag_reversed == 0,
          "cleaned: %u one-way solids (%u undersides + %u pieces left out), %u thickened; 110 displacements, %u decided "
          "by their tags, %u reversed", s.world.one_way_solids, s.world.one_way_faces, s.world.one_way_cross,
          s.world.thickened_floors, s.world.disp_tag_checked, s.world.disp_tag_reversed);
    t0 = now_ms();
    ok = run_job("gm_construct", bsp, o, fs, true, b, err, &db);
    double tb = now_ms() - t0;
    File f;
    std::string ferr;
    uint64_t size = f.open(bsp, ferr) ? f.size() : 1;
    CHECK(ok && same_result(a, b, why) && db.fed < size / 8,
          "fed mode (the addon's reader): the same result from %.1f MB of the %.1f MB file in %d polls (%.0f ms)%s%s",
          db.fed / 1048576.0, size / 1048576.0, db.polls, tb, ok ? "" : ": ", ok ? why.c_str() : err.c_str());
    MapJobOptions nop = o;
    nop.static_props = false;
    ok = run_job("gm_construct", bsp, nop, fs, false, np, err);
    CHECK(ok && np.st.props_placed == 0 && np.st.world.tris_extra == 0 && np.world.size() < a.world.size(),
          "static props off: %zu world triangles (with them %zu)", np.world.size(), a.world.size());
    // the cache
    std::string dir = temp_dir();
    make_dirs(dir);
    std::string file = join_path(dir, "gm_construct.dat");
    std::string data;
    if (file_exists(file)) {
        write_file_replace(file, "x", err);
    }
    MapJobOptions co = o;
    co.cache_dir = dir;
    MapResult c1, c2, c3, c4;
    ok = run_job("gm_construct", bsp, co, fs, false, c1, err);
    CHECK(ok && c1.cache_written && !c1.from_cache && same_result(a, c1, why),
          "cache: written after a build (%.0f ms; before: %s)", c1.cache_ms, c1.cache_note.c_str());
    t0 = now_ms();
    MapDrive dc;
    ok = run_job("gm_construct", bsp, co, fs, true, c2, err, &dc);
    double tc = now_ms() - t0;
    CHECK(ok && c2.from_cache && same_result(a, c2, why) && dc.fed == 0 && dc.files == 0 && c2.st.props_placed == s.props_placed,
          "cache: the second visit (fed mode) reads the cache file in %.0f ms (total %.0f ms, %llu map bytes fed, %u model "
          "files): the same result%s%s", c2.cache_ms, tc, (unsigned long long)dc.fed, dc.files, ok ? "" : ": ",
          ok ? why.c_str() : err.c_str());
    std::string raw;
    read_small_file(file, 512u << 20, raw, err);
    if (raw.size() > 1000) {
        raw[raw.size() / 2] ^= 0x5A;
        write_file_replace(file, raw, err);
    }
    ok = run_job("gm_construct", bsp, co, fs, false, c3, err);
    CHECK(ok && !c3.from_cache && c3.cache_written && same_result(a, c3, why),
          "cache: a damaged file is refused (\"%s\") and rebuilt", c3.cache_note.c_str());
    MapJobOptions co2 = co;
    co2.prop_min_size = 9.0f;
    ok = run_job("gm_construct", bsp, co2, fs, false, c4, err);
    CHECK(ok && !c4.from_cache && c4.cache_written && c4.cache_note.find("other settings") != std::string::npos,
          "cache: a file built with other settings is not used (\"%s\"); rebuilt and written", c4.cache_note.c_str());
    // cancelling while a worker runs
    MapJob j5;
    t0 = now_ms();
    ok = j5.start_file("gm_construct", bsp, o, err);
    j5.cancel();
    CHECK(ok && j5.state() == MapState::Failed && now_ms() - t0 < 5000.0, "cancel: the job stops (%.0f ms) with \"%s\"",
          now_ms() - t0, j5.error().c_str());
    // bad input: not a BSP, a short header
    MapJob j6, j7;
    std::string junk(2000, 'x');
    CHECK(!j6.start_fed("x", junk.data(), junk.size(), 5000, o, err) && !j7.start_fed("x", junk.data(), 100, 5000, o, err),
          "a file that is not a BSP is refused at the start");
    keep = std::move(a);
}

// the static props of a bigger map land in the world where the props stand
static void test_props(const std::string &bsp, gamefs::GameFs &fs)
{
    std::string map = base_name(bsp);
    map = map.substr(0, map.size() - 4);
    std::printf("static props: %s\n", map.c_str());
    fs.set_map(bsp);
    MapJobOptions o;
    MapResult r;
    std::string err;
    MapDrive d;
    double t0 = now_ms();
    bool ok = run_job(map, bsp, o, fs, false, r, err, &d);
    const MapStats &s = r.st;
    CHECK(ok && s.props_placed > 0 && s.props_placed + s.props_small + s.props_missing == s.props_solid &&
              s.props_placed * 10 >= s.props_solid * 8,
          "%u static props, %u solid: %u placed (%u convex pieces -> %u triangles after cleaning), %u missing, %u small; "
          "%u model files (%u found, %u bad); %zu world triangles; %.0f ms (world build %.0f ms)%s%s", s.props,
          s.props_solid, s.props_placed, s.props_hulls, s.world.tris_extra, s.props_missing, s.props_small, s.prop_models,
          d.files_found, s.prop_models_bad, r.world.size(), now_ms() - t0, s.world.ms, ok ? "" : ": ", ok ? "" : err.c_str());
    if (!ok) {
        return;
    }
    // every placed prop's box has prop triangles in it
    FileByteSource src;
    Bsp b;
    std::vector<BspStaticProp> props;
    BspPropInfo info;
    if (!src.open(bsp, err) || !b.open(src, err) || !b.static_props(props, info, err)) {
        CHECK(false, "static props: %s", err.c_str());
        return;
    }
    uint32_t tested = 0, found = 0;
    std::string first_bad;
    for (const BspStaticProp &p : props) {
        if (p.solid != 6 || tested >= 60) {
            continue;
        }
        std::string phy = p.model.substr(0, p.model.size() - 4) + ".phy", data;
        PhyModel m;
        if (!fs.read(phy, data) || !parse_phy(data.data(), data.size(), m, err)) {
            continue;
        }
        double dx = m.maxs[0] - m.mins[0], dy = m.maxs[1] - m.mins[1], dz = m.maxs[2] - m.mins[2];
        if (std::sqrt(dx * dx + dy * dy + dz * dz) < o.prop_min_size) {
            continue;
        }
        tested++;
        float rot[9];
        angle_matrix(p.angles, rot);
        float lo[3] = {1e9f, 1e9f, 1e9f}, hi[3] = {-1e9f, -1e9f, -1e9f};
        for (const std::vector<float> &h : m.hulls) {
            for (size_t i = 0; i + 2 < h.size(); i += 3) {
                for (int k = 0; k < 3; k++) {
                    float w = p.origin[k] + rot[3 * k] * h[i] + rot[3 * k + 1] * h[i + 1] + rot[3 * k + 2] * h[i + 2];
                    lo[k] = std::min(lo[k], w);
                    hi[k] = std::max(hi[k], w);
                }
            }
        }
        bool any = false;
        for (const sa1_collision_tri &t : r.world) {
            float c[3];
            for (int k = 0; k < 3; k++) {
                c[k] = (t.v[0][k] + t.v[1][k] + t.v[2][k]) / 3.0f;
            }
            if (c[0] >= lo[0] - 0.5f && c[0] <= hi[0] + 0.5f && c[1] >= lo[1] - 0.5f && c[1] <= hi[1] + 0.5f &&
                c[2] >= lo[2] - 0.5f && c[2] <= hi[2] + 0.5f) {
                any = true;
                break;
            }
        }
        found += any;
        if (!any && first_bad.empty()) {
            first_bad = format("%s at (%.0f %.0f %.0f)", p.model.c_str(), p.origin[0], p.origin[1], p.origin[2]);
        }
    }
    CHECK(tested > 0 && found == tested, "%u of %u solid props have collision inside their placed physics box%s%s", found,
          tested, first_bad.empty() ? "" : "; first without: ", first_bad.c_str());
}

// ---- 4. moving objects in libsa1 ---------------------------------------------------------------------------------------
struct Run {
    Session &s;
    int32_t id = 0;
    double now = 1000.0;
    explicit Run(Session &ss) : s(ss) {}
    const float *pos() { return s.get(id)->st.position; }
    bool ground() { return (s.get(id)->st.flags & SA1_STATE_ON_GROUND) != 0; }
};

static void floor_world(std::vector<sa1_collision_tri> &w)
{
    w.clear();
    sa1_collision_tri a, b;
    const float S = 6000.0f;
    float q[4][3] = {{-S, -S, 0}, {S, -S, 0}, {S, S, 0}, {-S, S, 0}};
    std::memcpy(a.v[0], q[0], 12);
    std::memcpy(a.v[1], q[1], 12);
    std::memcpy(a.v[2], q[2], 12);
    std::memcpy(b.v[0], q[0], 12);
    std::memcpy(b.v[1], q[2], 12);
    std::memcpy(b.v[2], q[3], 12);
    a.surface = b.surface = SA1_SURFACE_SOLID;
    w.push_back(a);
    w.push_back(b);
}

static void test_movers(const std::string &gdi, const MapResult *construct)
{
    std::printf("moving objects (libsa1)\n");
    Session s;
    std::string err;
    std::vector<sa1_collision_tri> w;
    floor_world(w);
    if (!s.init(gdi, err) || !s.set_world(w, err)) {
        CHECK(false, "init and a flat floor: %s", err.c_str());
        return;
    }
    Movers &mv = s.movers();
    Shape lift, wall, crate;
    float lmin[3] = {-128, -128, -16}, lmax[3] = {128, 128, 0};
    float wmin[3] = {-512, -8, 0}, wmax[3] = {512, 8, 256};
    float cmin[3] = {-16, -16, 0}, cmax[3] = {16, 16, 32};
    bool ok = shape_box(lmin, lmax, lift, err) && shape_box(wmin, wmax, wall, err) && shape_box(cmin, cmax, crate, err);
    CHECK(ok && lift.chunks.size() == 1 && wall.chunks.size() == 1, "box shapes: lift %u, wall %u, crate %u triangles",
          lift.tris, wall.tris, crate.tris);
    mv.set_shape("x:lift", lift);
    mv.set_shape("x:wall", wall);
    mv.set_shape("x:crate", crate);
    const float zero[3] = {0, 0, 0};
    Run R(s);
    float lp[3] = {0, 0, 96};
    float start[3] = {0, 0, 130};
    auto frame = [&](float sx, float sy, float yaw) {
        R.now += 1.0 / 60.0;
        s.commit_movers(R.now);
        s.tick(R.id, sx, sy, yaw, 0, 1.0f / 60.0f);
    };
    // a lift: Sonic lands on it, rides it up and sideways, falls when it is switched off
    mv.update(1, "x:lift", lp, zero, true, R.now);
    s.commit_movers(R.now);
    R.id = s.create(SA1_CHAR_SONIC, start, 0.0f, err);
    if (R.id <= 0) {
        CHECK(false, "create Sonic: %s", err.c_str());
        return;
    }
    for (int f = 0; f < 60; f++) {
        mv.update(1, "x:lift", lp, zero, true, R.now);
        frame(0, 0, 0);
    }
    float z0 = R.pos()[2];
    CHECK(std::fabs(z0 - 96.0f) < 2.0f && R.ground(), "Sonic stands on the lift: z %.1f (its top at 96)", z0);
    for (int f = 0; f < 120; f++) {
        lp[2] += 1.5f;
        mv.update(1, "x:lift", lp, zero, true, R.now);
        frame(0, 0, 0);
    }
    float z1 = R.pos()[2];
    CHECK(std::fabs(z1 - lp[2]) < 6.0f, "the lift rose 180 units in 2 s: Sonic rode it up to z %.1f (its top at %.0f)", z1,
          lp[2]);
    float x0 = R.pos()[0];
    for (int f = 0; f < 60; f++) {
        lp[0] += 2.0f;
        mv.update(1, "x:lift", lp, zero, true, R.now);
        frame(0, 0, 0);
    }
    float x1 = R.pos()[0];
    CHECK(x1 - x0 > 90.0f && std::fabs(R.pos()[2] - lp[2]) < 6.0f,
          "the lift moved 120 units sideways in 1 s: Sonic was carried %.1f units (z %.1f)", x1 - x0, R.pos()[2]);
    float ang[3] = {0, 90, 0};
    for (int f = 0; f < 60; f++) {
        ang[1] += 1.5f;
        mv.update(1, "x:lift", lp, ang, true, R.now);
        frame(0, 0, 0);
    }
    CHECK(std::fabs(R.pos()[2] - lp[2]) < 6.0f && R.ground(), "the lift turned 90 degrees (a matrix, not Euler): Sonic "
          "stayed on it (z %.1f)", R.pos()[2]);
    for (int f = 0; f < 150; f++) {
        mv.update(1, "x:lift", lp, ang, false, R.now);
        frame(0, 0, 0);
    }
    const MoverStats &st = mv.stats();
    CHECK(R.pos()[2] < 2.0f && st.parked >= 1 && st.active == 0,
          "switched off (not solid): parked (%u parked, %llu parks), Sonic fell to the floor (z %.1f)", st.parked,
          (unsigned long long)st.parks, R.pos()[2]);
    s.destroy(R.id);
    mv.forget(1);
    // a wall in the way: stops a run until it is switched off; re-enabling unparks the same object
    float wp[3] = {0, 0, 0}, sp[3] = {0, -500, 8};
    const float kPi = 3.14159265f;
    R.id = s.create(SA1_CHAR_SONIC, sp, kPi / 2, err);
    for (int f = 0; f < 240; f++) {
        mv.update(2, "x:wall", wp, zero, true, R.now);
        frame(0, 1, kPi / 2);
    }
    float y_stop = R.pos()[1];
    uint64_t adds = mv.stats().adds;
    CHECK(y_stop < -8.0f && y_stop > -60.0f, "a wall across the run stops Sonic at y %.1f (its face at -8)", y_stop);
    for (int f = 0; f < 120; f++) {
        mv.update(2, "x:wall", wp, zero, false, R.now);
        frame(0, 1, kPi / 2);
    }
    CHECK(R.pos()[1] > 100.0f, "the wall switched off: Sonic runs through (y %.1f)", R.pos()[1]);
    s.destroy(R.id);
    R.id = s.create(SA1_CHAR_SONIC, sp, kPi / 2, err);
    for (int f = 0; f < 240; f++) {
        mv.update(2, "x:wall", wp, zero, true, R.now);
        frame(0, 1, kPi / 2);
    }
    CHECK(R.pos()[1] < -8.0f && mv.stats().adds == adds && mv.stats().unparks >= 1,
          "switched on again: the parked object comes back (no new object: %llu adds, %llu unparks), Sonic stops at y %.1f",
          (unsigned long long)mv.stats().adds, (unsigned long long)mv.stats().unparks, R.pos()[1]);
    s.destroy(R.id);
    mv.forget(2);
    // the budget: 300 crates around; only the nearest go into libsa1
    R.id = s.create(SA1_CHAR_SONIC, sp, 0.0f, err);
    for (int f = 0; f < 30; f++) {
        for (int i = 0; i < 300; i++) {
            float p[3] = {(float)((i * 7919) % 8000 - 4000), (float)((i * 104729) % 8000 - 4000), 0.0f};
            mv.update(100 + i, "x:crate", p, zero, true, R.now);
        }
        frame(0, 0, 0);
    }
    uint32_t objects = 0, otris = 0;
    sa1_collision_stats(s.ctx(), nullptr, &objects, &otris);
    const MoverStats &bs = mv.stats();
    CHECK(bs.active <= mv.opt.max_active && bs.active_tris <= mv.opt.max_tris && objects <= mv.opt.max_active + mv.opt.max_parked &&
              objects < 64 && bs.candidates > bs.active,
          "300 crates: %u within range, %u in libsa1 (%u triangles), %u parked; libsa1 holds %u objects (< 64 per world)",
          bs.candidates, bs.active, bs.active_tris, bs.parked, objects);
    for (int i = 0; i < 300; i++) {
        mv.forget(100 + i);
    }
    frame(0, 0, 0);
    sa1_collision_stats(s.ctx(), nullptr, &objects, &otris);
    CHECK(objects == 0, "forgotten entities leave no libsa1 object (%u)", objects);
    s.destroy(R.id);
    // a brush entity of gm_construct: the func_brush *3 (a slab 8 units thick, top at 160) as a moving object
    if (construct && construct->models.count(3)) {
        mv.set_shape("b3", construct->models.at(3));
        float org[3] = {-2048, -3600, 156}, above[3] = {-2048, -3600, 220};
        mv.update(3, "b3", org, zero, true, R.now);
        s.commit_movers(R.now);
        R.id = s.create(SA1_CHAR_SONIC, above, 0.0f, err);
        for (int f = 0; f < 90; f++) {
            mv.update(3, "b3", org, zero, true, R.now);
            frame(0, 0, 0);
        }
        CHECK(std::fabs(R.pos()[2] - 160.0f) < 1.5f && R.ground(),
              "gm_construct's func_brush *3 (%u triangles, %zu chunk(s)): Sonic lands on its top at z %.1f (160)",
              construct->models.at(3).tris, construct->models.at(3).chunks.size(), R.pos()[2]);
        s.destroy(R.id);
    }
}

// ---- thin walls (bsp.hpp thin_wall_max) ------------------------------------------------------------------------------
// A floor slab and a wall `thick` units thick across the run (y 0), both cleaned as convex solids the way the map's
// brushes are; characters run (and Sonic spin dashes) into it from y -300. A run "goes through" when the character gets
// past the wall's far face. Without the thin-wall rule (thin_wall_max 0) SA1's land collision touches the far side's
// polygon from behind once the character steps deeper into the wall than it is thick, and the two pushbacks cancel
// (gm_freespace_13's random play: 11 of 400 runs went through 8-unit fences and panes).
static bool wall_world(float thick, float thin_wall_max, std::vector<sa1_collision_tri> &w, BspWorldStats &st,
                       std::string &err)
{
    std::vector<ConvexSolid> solids(2);
    const float fmin[3] = {-3000, -3000, -64}, fmax[3] = {3000, 3000, 0};
    const float wmin[3] = {-1024, -0.5f * thick, 0}, wmax[3] = {1024, 0.5f * thick, 160};
    box_solid(fmin, fmax, nullptr, nullptr, solids[0]);
    box_solid(wmin, wmax, nullptr, nullptr, solids[1]);
    BspWorldOptions o;
    o.thin_wall_max = thin_wall_max;
    return clean_solids(solids, o, w, st, err);
}

static void test_thin_walls(const std::string &gdi)
{
    std::printf("thin walls (one double-sided face halfway through walls at most %.0f units thick)\n",
                BspWorldOptions().thin_wall_max);
    Session s;
    std::string err;
    if (!s.init(gdi, err)) {
        CHECK(false, "init: %s", err.c_str());
        return;
    }
    const float kPi = 3.14159265f;
    const int kinds[] = {SA1_CHAR_SONIC, SA1_CHAR_KNUCKLES, SA1_CHAR_GAMMA, SA1_CHAR_BIG};
    for (float thick : {4.0f, 8.0f, 16.0f}) {
        int through[2] = {0, 0}, runs[2] = {0, 0};
        float closest[2] = {-1e9f, -1e9f};
        uint32_t made = 0;
        for (int rule = 1; rule >= 0; rule--) {
            std::vector<sa1_collision_tri> w;
            BspWorldStats st;
            if (!wall_world(thick, rule ? BspWorldOptions().thin_wall_max : 0.0f, w, st, err) || !s.set_world(w, err)) {
                CHECK(false, "a %.0f-unit wall: %s", thick, err.c_str());
                return;
            }
            if (rule) {
                made = st.thin_walls;
            }
            for (int kind : kinds) {
                for (int spin = 0; spin < (kind == SA1_CHAR_SONIC ? 2 : 1); spin++) {
                    for (float x : {-200.0f, 0.0f, 300.0f}) {
                        float start[3] = {x, -300.0f, 8.0f};
                        int32_t id = s.create(kind, start, kPi / 2, err);
                        if (id <= 0) {
                            CHECK(false, "create: %s", err.c_str());
                            return;
                        }
                        bool gone = false;
                        float ymax = -1e9f;
                        for (int f = 0; f < 300; f++) {
                            float sy = 1.0f;
                            uint32_t btn = 0;
                            if (spin && f < 70) {
                                sy = 0.0f;
                                btn = f < 60 ? SA1_BUTTON_ACTION : 0;
                            }
                            s.tick(id, 0.0f, sy, kPi / 2, btn, 1.0f / 60.0f);
                            const float *p = s.get(id)->st.position;
                            ymax = std::max(ymax, p[1]);
                            if (p[1] > 0.5f * thick + 1.0f) {
                                gone = true;
                            }
                        }
                        runs[rule]++;
                        through[rule] += gone;
                        closest[rule] = std::max(closest[rule], ymax);
                        s.destroy(id);
                    }
                }
            }
        }
        CHECK(through[1] == 0 && made == 1,
              "a %.0f-unit wall (made one double-sided face): %d of %d runs and spin dashes went through (the deepest "
              "feet at y %.1f, its faces at +-%.0f)", thick, through[1], runs[1], closest[1], 0.5f * thick);
        INFO("  without the rule: %d of %d went through (the deepest feet at y %.1f)", through[0], runs[0], closest[0]);
    }
}

// ---- 0.9.2: thin stacks, the guard, displacements without hull collision, coplanar down faces, GRID-FALLBACK ----------
// (sadc docs/research/gsa1_090_collision.md C2 / F3, F6 and gsa1_090_water.md GRID-GUARD, GRID-FALLBACK, WTR-DISP, with
// their reviews). Synthetic solids through clean_solids, and a small Source BSP built in memory (world brushes, quad
// faces carrying flat displacements, one leaf, model 0; no nodes, no materials) through Bsp::build_world.

// the steep triangles (|n.z| < 0.5) whose normal is within `cosmax` of +-axis `ax`: their distinct planes (coordinate
// along the axis, 0.05 apart) and how many are double-sided
struct SteepPlanes {
    std::set<long> planes;
    uint32_t tris = 0, ds = 0;
    double area = 0.0;
};
static SteepPlanes steep_planes(const std::vector<sa1_collision_tri> &w, int ax, const float lo[3], const float hi[3])
{
    SteepPlanes r;
    for (const sa1_collision_tri &t : w) {
        bool in = true;
        for (int v = 0; v < 3 && in; v++) {
            for (int k = 0; k < 3; k++) {
                in = in && t.v[v][k] >= lo[k] - 0.01f && t.v[v][k] <= hi[k] + 0.01f;
            }
        }
        if (!in || (t.surface & SA1_SURFACE_KILL)) {
            continue;
        }
        double e1[3], e2[3];
        for (int k = 0; k < 3; k++) {
            e1[k] = (double)t.v[1][k] - t.v[0][k];
            e2[k] = (double)t.v[2][k] - t.v[0][k];
        }
        double c[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
        double l = std::sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2]);
        if (!(l > 0.0) || std::fabs(c[ax] / l) < 0.9 || std::fabs(c[2] / l) >= 0.5) {
            continue;
        }
        r.tris++;
        r.ds += (t.surface & SA1_SURFACE_DOUBLE_SIDED) != 0;
        r.area += 0.5 * l;
        double m = ((double)t.v[0][ax] + t.v[1][ax] + t.v[2][ax]) / 3.0;
        r.planes.insert((long)std::floor(m / 0.05 + 0.5));
    }
    return r;
}

static void test_thin_stacks()
{
    std::printf("thin stacks (0.9.2: steep faces of any source within thin_wall_max become one double-sided face)\n");
    std::string err;
    auto run = [&](const std::vector<ConvexSolid> &solids, bool rule, std::vector<sa1_collision_tri> &w, BspWorldStats &st) {
        BspWorldOptions o;
        o.thin_stacks = rule;
        return clean_solids(solids, o, w, st, err);
    };
    // a fence of two 1-unit panels `gap` apart (each one made a double-sided middle face by the per-solid rule)
    for (float gap : {2.0f, 4.0f, 8.0f}) {
        std::vector<ConvexSolid> s(2);
        const float a0[3] = {-64, -0.5f * gap - 1.0f, 0}, a1[3] = {64, -0.5f * gap, 128};
        const float b0[3] = {-64, 0.5f * gap, 0}, b1[3] = {64, 0.5f * gap + 1.0f, 128};
        box_solid(a0, a1, nullptr, nullptr, s[0]);
        box_solid(b0, b1, nullptr, nullptr, s[1]);
        const float lo[3] = {-65, -20, -1}, hi[3] = {65, 20, 129};
        SteepPlanes r[2];
        BspWorldStats st[2];
        for (int rule = 0; rule < 2; rule++) {
            std::vector<sa1_collision_tri> w;
            run(s, rule != 0, w, st[rule]);
            r[rule] = steep_planes(w, 1, lo, hi);
        }
        CHECK(r[1].planes.size() == 1 && r[1].ds == r[1].tris && r[1].tris > 0 && st[1].thin_stacks > 0,
              "two 1-unit panels %.0f units apart: %zu plane(s) facing +-y, %u of %u triangles double-sided (without the "
              "rule: %zu planes, the character was held between them)", gap, r[1].planes.size(), r[1].ds, r[1].tris,
              r[0].planes.size());
    }
    // a 2-unit panel whose back is tilted 3 degrees (a tapered prop hull: not antiparallel enough for the per-solid rule)
    {
        const float k = 128.0f * std::tan(3.0f * 3.14159265f / 180.0f);
        std::vector<std::array<float, 3>> v = {{-64, 0, 0}, {64, 0, 0}, {64, 0, 128}, {-64, 0, 128},
                                               {-64, 2, 0}, {64, 2, 0}, {64, 2 + k, 128}, {-64, 2 + k, 128}};
        const int f[6][4] = {{0, 3, 2, 1}, {4, 5, 6, 7}, {0, 1, 5, 4}, {3, 7, 6, 2}, {0, 4, 7, 3}, {1, 2, 6, 5}};
        ConvexSolid cs;
        for (const auto &q : f) {
            for (int t : {0, 1}) {
                for (int idx : {q[0], q[1 + t], q[2 + t]}) {
                    cs.tris.insert(cs.tris.end(), v[(size_t)idx].begin(), v[(size_t)idx].end());
                }
            }
        }
        const float lo[3] = {-65, -20, -1}, hi[3] = {65, 20, 129};
        SteepPlanes r[2];
        BspWorldStats st[2];
        for (int rule = 0; rule < 2; rule++) {
            std::vector<sa1_collision_tri> w;
            run({cs}, rule != 0, w, st[rule]);
            r[rule] = steep_planes(w, 1, lo, hi);
        }
        CHECK(st[1].thin_walls == 0 && r[1].tris > 0 && r[1].ds == r[1].tris && st[1].thin_stack_faces > 0 &&
                  r[0].ds == 0,
              "a 2-unit panel, its back tilted 3 degrees: the per-solid rule leaves it (%u thin walls), the stack rule "
              "keeps one double-sided side (%u of %u triangles facing +-y double-sided; without it %u of %u)",
              st[1].thin_walls, r[1].ds, r[1].tris, r[0].ds, r[0].tris);
    }
    // a partial stack: a small 2-unit panel 1 unit in front of a large 32-unit wall: the wall's face is never left out
    {
        std::vector<ConvexSolid> s(2);
        const float w0[3] = {-256, 0, 0}, w1[3] = {256, 32, 256};
        const float p0[3] = {-16, -3, 64}, p1[3] = {16, -1, 96};
        box_solid(w0, w1, nullptr, nullptr, s[0]);
        box_solid(p0, p1, nullptr, nullptr, s[1]);
        std::vector<sa1_collision_tri> w;
        BspWorldStats st;
        run(s, true, w, st);
        const float lo[3] = {-256, -0.01f, 0}, hi[3] = {256, 0.01f, 256};
        const float plo[3] = {-17, -3.5f, 63}, phi[3] = {17, -0.5f, 97};
        SteepPlanes face = steep_planes(w, 1, lo, hi), panel = steep_planes(w, 1, plo, phi);
        CHECK(std::fabs(face.area - 512.0 * 256.0) < 1.0 && face.ds == face.tris && panel.tris == 0,
              "a 2-unit panel 1 unit in front of a large wall: the wall's front face keeps its whole area (%.0f of %.0f "
              "square units) and is double-sided (%u of %u), the panel's face is left out (%u left; %u faces of stacks "
              "left out)", face.area, 512.0 * 256.0, face.ds, face.tris, panel.tris, st.thin_stack_faces);
    }
}

// ---- 0.9.3: front-only ceilings and curved surfaces ---------------------------------------------------------------------
// (sadc docs/research/gsa1_091b_ceiling.md FIX-C3 with its Review R.5.1, gsa1_091a_loop.md LOOP-G1 with its Review R.4;
// the owner's notes "jumped through ceiling" (0.9.1a), "every single ceiling can be jumped through" (0.9.2) and "going
// through loop forces me up onto the top of it" (0.9.1a)). Synthetic solids through clean_solids, as the map's brushes.

// a convex solid from its corners and faces (any winding)
static ConvexSolid poly_solid(const std::vector<std::array<double, 3>> &v, const std::vector<std::vector<int>> &faces)
{
    ConvexSolid cs;
    for (const std::vector<int> &f : faces) {
        for (size_t k = 1; k + 1 < f.size(); k++) {
            for (int idx : {f[0], f[k], f[k + 1]}) {
                for (int c = 0; c < 3; c++) {
                    cs.tris.push_back((float)v[(size_t)idx][(size_t)c]);
                }
            }
        }
    }
    return cs;
}

// the fraction of n x n points over x0..x1 / y0..y1 that have a land triangle facing `facing` (+1 up, -1 down) at height
// z (+-0.5) over or under them whose surface has all bits of `need` and none of `none`
static double coverage_bits(const std::vector<sa1_collision_tri> &w, float x0, float x1, float y0, float y1, float z,
                            int facing, uint32_t need, uint32_t none, int n = 16)
{
    int hit = 0;
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            double x = x0 + (x1 - x0) * (i + 0.5) / n, y = y0 + (y1 - y0) * (j + 0.5) / n;
            bool any = false;
            for (const sa1_collision_tri &t : w) {
                if ((t.surface & SA1_SURFACE_KILL) || (t.surface & need) != need || (t.surface & none)) {
                    continue;
                }
                double ax = t.v[0][0], ay = t.v[0][1], bx = t.v[1][0], by = t.v[1][1], cx = t.v[2][0], cy = t.v[2][1];
                double d = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
                if (std::fabs(d) < 1e-9 || (d > 0) != (facing > 0)) {
                    continue;
                }
                double l1 = ((bx - x) * (cy - y) - (by - y) * (cx - x)) / d;
                double l2 = ((cx - x) * (ay - y) - (cy - y) * (ax - x)) / d;
                double l3 = 1.0 - l1 - l2;
                if (l1 < -1e-6 || l2 < -1e-6 || l3 < -1e-6) {
                    continue;
                }
                double zz = l1 * t.v[0][2] + l2 * t.v[1][2] + l3 * t.v[2][2];
                if (std::fabs(zz - z) <= 0.5) {
                    any = true;
                    break;
                }
            }
            hit += any;
        }
    }
    return (double)hit / (double)(n * n);
}

// the gm_bigcity house of gsa1_091b_ceiling.md section 2, moved to the origin (x 0..288 = 176..464, y 0..384 =
// -320..64, the floor's top z 0 = -11136): a floor slab, four 8-unit walls - the north one with a window (x 88..216,
// z 42..84) - and a gabled roof brush whose flat underside is the ceiling (z 128) and whose ridge is 32 units above it
// at x 144 (0 at the eaves). In the real map the window's brushes cut the ceiling at x 88 and 216 (the hidden-face
// removal's cut depends on the brushes' side order); here two 4-unit partitions under those lines cut it the same way
// for certain: strips under the roof's thin ends (5-20 units: one-way) and a middle 20-32 units under the ridge
static void house_solids(std::vector<ConvexSolid> &s)
{
    auto box = [&](float x0, float y0, float z0, float x1, float y1, float z1) {
        const float a[3] = {x0, y0, z0}, b[3] = {x1, y1, z1};
        s.emplace_back();
        box_solid(a, b, nullptr, nullptr, s.back());
    };
    box(-64, -64, -16, 352, 448, 0);       // the floor
    box(16, 0, 0, 24, 384, 128);           // west wall
    box(264, 0, 0, 272, 384, 128);         // east wall
    box(16, 0, 0, 272, 8, 128);            // south wall
    box(16, 376, 0, 88, 384, 128);         // north wall, west of the window
    box(88, 376, 0, 216, 384, 42);         // ... under the window
    box(88, 376, 84, 216, 384, 128);       // ... over the window
    box(216, 376, 0, 272, 384, 128);       // ... east of the window
    box(84, 8, 0, 88, 376, 128);           // the partitions
    box(216, 8, 0, 220, 376, 128);
    s.push_back(poly_solid({{0, 0, 128}, {288, 0, 128}, {144, 0, 160}, {0, 384, 128}, {288, 384, 128}, {144, 384, 160}},
                           {{0, 1, 4, 3}, {0, 2, 1}, {3, 4, 5}, {0, 3, 5, 2}, {1, 2, 5, 4}}));
}

// a loop of `segs` convex segments (inner radius R, thickness T, width W along y, axis along y through (0, 0, R)), its
// inner bottom on a floor at z 0, travel from the bottom up the -x side, over the top and down the +x side; the exit
// segments whose lowest point is below 60 units are left out (a real loop's exit is beside its entry: gm_genesis's ribbon
// drifts 336 units in y). sadc build/research/loop/loop_diag.cpp synth_loop.
static void loop_solids(double R, double T, int segs, double W, std::vector<ConvexSolid> &s)
{
    const double PI = 3.14159265358979;
    for (int k = 0; k < segs; k++) {
        double a0 = -PI / 2 - 2 * PI * k / segs, a1 = -PI / 2 - 2 * PI * (k + 1) / segs;
        double zmin = 1e300;
        for (double a : {a0, a1}) {
            for (double r : {R, R + T}) {
                zmin = std::min(zmin, R + r * std::sin(a));
            }
        }
        if (k >= segs / 2 && zmin < 60.0) {
            continue;
        }
        std::vector<std::array<double, 3>> pt;
        for (double a : {a0, a1}) {
            for (double r : {R, R + T}) {
                for (double y : {-W / 2, W / 2}) {
                    pt.push_back({r * std::cos(a), y, R + r * std::sin(a)});
                }
            }
        }
        s.push_back(poly_solid(pt, {{0, 1, 5, 4}, {2, 6, 7, 3}, {0, 4, 6, 2}, {1, 3, 7, 5}, {0, 2, 3, 1}, {4, 5, 7, 6}}));
    }
    const float a[3] = {-4000, -1200, -64}, b[3] = {4000, 1200, 0};
    s.emplace_back();
    box_solid(a, b, nullptr, nullptr, s.back());
}

// the loop's radial faces (|n.y| < 0.5) by their plane's distance from the axis: on the inner surface, the outer one, or
// in the middle (a thin wall's / ribbon's middle face); with their flags
struct LoopFaces {
    uint32_t inner = 0, inner_up = 0, inner_ceiling = 0, outer = 0, middle = 0;
    uint32_t inner_steep_ds = 0, inner_not_curved = 0, inner_fo = 0, middle_ds = 0, middle_curved = 0, curved = 0;
};
static LoopFaces loop_faces(const std::vector<sa1_collision_tri> &w, double R, double T, int segs)
{
    LoopFaces f;
    const double ci = R * std::cos(3.14159265358979 / segs), co = (R + T) * std::cos(3.14159265358979 / segs);
    for (const sa1_collision_tri &t : w) {
        double e1[3], e2[3], c[3];
        for (int k = 0; k < 3; k++) {
            e1[k] = (double)t.v[1][k] - t.v[0][k];
            e2[k] = (double)t.v[2][k] - t.v[0][k];
            c[k] = ((double)t.v[0][k] + t.v[1][k] + t.v[2][k]) / 3.0;
        }
        double n[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
        double l = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        if (!(l > 0.0) || std::fabs(n[1] / l) >= 0.5 || c[2] < 1.0) {
            continue;   // the loop's sides, the floor
        }
        for (double &q : n) {
            q /= l;
        }
        double d = std::fabs(n[0] * c[0] + n[2] * (c[2] - R));
        f.curved += (t.surface & SA1_SURFACE_CURVED) != 0;
        bool ds = (t.surface & SA1_SURFACE_DOUBLE_SIDED) != 0;
        if (std::fabs(d - ci) < 2.0) {
            f.inner++;
            f.inner_up += n[2] >= 0.5;
            f.inner_ceiling += n[2] <= -0.9;
            if (n[2] < 0.5) {
                f.inner_steep_ds += ds;
                f.inner_not_curved += !(t.surface & SA1_SURFACE_CURVED);
                f.inner_fo += (t.surface & SA1_SURFACE_FRONT_ONLY) != 0;
            }
        } else if (std::fabs(d - co) < 2.0) {
            f.outer++;
        } else if (d > ci + 1.0 && d < co - 1.0) {
            f.middle++;
            f.middle_ds += ds;
            f.middle_curved += (t.surface & SA1_SURFACE_CURVED) != 0;
        }
    }
    return f;
}

static void test_ceilings_and_loops()
{
    std::printf("front-only ceilings and curved surfaces (0.9.3)\n");
    std::string err;
    // --- FIX-C3: the house ---
    {
        std::vector<ConvexSolid> s;
        house_solids(s);
        std::vector<sa1_collision_tri> w[2];
        BspWorldStats st[2];
        for (int fix = 0; fix < 2; fix++) {
            BspWorldOptions o;
            o.one_way_front_only = fix != 0;
            clean_solids(s, o, w[fix], st[fix], err);
        }
        const uint32_t FO = SA1_SURFACE_FRONT_ONLY;
        double all = coverage_bits(w[1], 24, 264, 8, 376, 128, -1, 0, 0);
        double west = coverage_bits(w[1], 24, 84, 8, 376, 128, -1, FO, 0), east = coverage_bits(w[1], 220, 264, 8, 376, 128, -1, FO, 0);
        double mid = coverage_bits(w[1], 88, 216, 8, 376, 128, -1, 0, FO), mid_fo = coverage_bits(w[1], 88, 216, 8, 376, 128, -1, FO, 0);
        double old_all = coverage_bits(w[0], 24, 264, 8, 376, 128, -1, 0, 0);
        double old_strips = coverage_bits(w[0], 24, 84, 8, 376, 128, -1, 0, 0) + coverage_bits(w[0], 220, 264, 8, 376, 128, -1, 0, 0);
        CHECK(all > 0.95 && west > 0.99 && east > 0.99 && mid > 0.99 && mid_fo < 0.01 && st[1].one_way_front_only > 0 &&
                  st[1].thickened_floors == 0,
              "the gm_bigcity house: its whole interior ceiling (z 128) is there (%.0f%% covered, the partitions' tops "
              "aside); the strips under the roof's thin ends are FRONT-ONLY (west %.0f%%, east %.0f%%), the middle (20-32 "
              "units under the ridge) an "
              "ordinary ceiling (%.0f%%; libsa1's GRID makes it front-only); %u pieces front-only, %u floors thickened",
              100 * all, 100 * west, 100 * east, 100 * mid, st[1].one_way_front_only, st[1].thickened_floors);
        CHECK(old_all < 0.6 && old_strips < 0.02,
              "... without front-only ceilings (0.9.2's one-way rule): %.0f%% of it (the strips left out: jumped through)",
              100 * old_all);
    }
    // --- the low-ceiling test first, steep undersides left out, thin one-way slabs not thickened (Review R.5.1 a, b) ---
    {
        std::vector<ConvexSolid> s;
        auto box = [&](float x0, float y0, float z0, float x1, float y1, float z1) {
            const float a[3] = {x0, y0, z0}, b[3] = {x1, y1, z1};
            s.emplace_back();
            box_solid(a, b, nullptr, nullptr, s.back());
        };
        box(-200, -200, -16, 1600, 400, 0);   // the floor (top z 0)
        box(100, 0, 24, 200, 100, 28);        // a shelf board 24 units over the floor
        box(400, 0, 200, 600, 200, 204);      // a 4-unit platform 200 units up
        // a 45-degree plank, 8 units thick, its foot on the floor
        const double k = 8.0 * std::sqrt(0.5);
        s.push_back(poly_solid({{1000, 0, 0}, {1200, 0, 200}, {1000 - k, 0, k}, {1200 - k, 0, 200 + k},
                                {1000, 100, 0}, {1200, 100, 200}, {1000 - k, 100, k}, {1200 - k, 100, 200 + k}},
                               {{0, 1, 5, 4}, {2, 6, 7, 3}, {0, 4, 6, 2}, {1, 3, 7, 5}, {0, 2, 3, 1}, {4, 5, 7, 6}}));
        std::vector<sa1_collision_tri> w;
        BspWorldStats st;
        clean_solids(s, BspWorldOptions(), w, st, err);
        double shelf = coverage_bits(w, 100, 200, 0, 100, 24, -1, 0, 0);
        double plat = coverage_bits(w, 400, 600, 0, 200, 200, -1, SA1_SURFACE_FRONT_ONLY, 0);
        uint32_t steep_down = 0;
        for (const sa1_collision_tri &t : w) {
            double e1[3], e2[3];
            for (int c = 0; c < 3; c++) {
                e1[c] = (double)t.v[1][c] - t.v[0][c];
                e2[c] = (double)t.v[2][c] - t.v[0][c];
            }
            double n[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
            double l = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
            steep_down += l > 0 && n[2] / l < -0.6 && n[2] / l > -0.8 && t.v[0][0] > 900.0f;
        }
        CHECK(shelf < 0.01 && plat > 0.99 && steep_down == 0 && st.thickened_floors == 0,
              "a shelf board 24 units over a floor: no underside (a low ceiling, tested first: %.0f%%); a 4-unit platform 200 "
              "units up: its underside FRONT-ONLY (%.0f%%), not thickened (%u floors thickened); a 45-degree plank's "
              "underside left out (%u steep down triangles)", 100 * shelf, 100 * plat, st.thickened_floors, steep_down);
    }
    // --- LOOP-G1: synthetic loops ---
    const double R = 512, W = 320;
    const int N = 16;
    for (float tw : {32.0f, 16.0f}) {
        std::vector<ConvexSolid> s;
        loop_solids(R, 32, N, W, s);
        std::vector<sa1_collision_tri> w[2];
        BspWorldStats st[2];
        for (int fix = 0; fix < 2; fix++) {
            BspWorldOptions o;
            o.thin_wall_max = tw;
            o.curved = fix != 0;
            clean_solids(s, o, w[fix], st[fix], err);
        }
        LoopFaces f = loop_faces(w[1], R, 32, N), g = loop_faces(w[0], R, 32, N);
        CHECK(f.middle == 0 && f.inner_steep_ds == 0 && f.inner_not_curved == 0 && f.inner_fo == 0 && f.inner_ceiling >= 2 &&
                  st[1].curved_surfaces >= 1,
              "a loop (radius 512, 32 thick, %d segments) with thin walls %.0f: every inner face of its walls and ceiling is "
              "single-sided on the inner radius and CURVED (%u inner faces, %u of the ceiling, %u not curved, %u front-only, "
              "%u middle faces); %u curved surface(s), %u faces", N, tw, f.inner - f.inner_up, f.inner_ceiling,
              f.inner_not_curved, f.inner_fo, f.middle, st[1].curved_surfaces, st[1].curved_faces);
        if (tw > 16.0f) {
            CHECK(g.middle > 0, "... without the curved-surface rule: %u middle faces at thin walls %.0f (the running surface "
                  "stepped out 16 units: the owner's loop)", g.middle, tw);
        }
    }
    {
        // a 16-unit ribbon: one double-sided surface over all its curved faces
        std::vector<ConvexSolid> s;
        loop_solids(R, 16, N, W, s);
        std::vector<sa1_collision_tri> w;
        BspWorldStats st;
        BspWorldOptions o;
        o.thin_wall_max = 32.0f;
        clean_solids(s, o, w, st, err);
        LoopFaces f = loop_faces(w, R, 16, N);
        CHECK(f.middle > 0 && f.middle_ds == f.middle && f.middle_curved == f.middle && f.inner == f.inner_up && st.curved_ribbons > 0,
              "a 16-unit loop ribbon: its walls and ceiling one double-sided CURVED middle surface (%u middle faces, %u "
              "double-sided, %u curved; %u inner faces left, all of the floor segments; %u ribbon pairs)", f.middle,
              f.middle_ds, f.middle_curved, f.inner, st.curved_ribbons);
    }
    {
        // a 20-unit loop: the one-way rule would take its top (20.4 units vertically <= one_way_max) - it stays an
        // ordinary curved ceiling (never front-only: the review's R.4.8)
        std::vector<ConvexSolid> s;
        loop_solids(R, 20, N, W, s);
        std::vector<sa1_collision_tri> w[2];
        BspWorldStats st[2];
        for (int fix = 0; fix < 2; fix++) {
            BspWorldOptions o;
            o.curved = fix != 0;
            clean_solids(s, o, w[fix], st[fix], err);
        }
        LoopFaces f = loop_faces(w[1], R, 20, N), g = loop_faces(w[0], R, 20, N);
        CHECK(f.inner_ceiling >= 2 && f.inner_fo == 0 && f.inner_not_curved == 0 && g.inner_fo > 0,
              "a 20-unit loop (thin walls 16): its ceiling is there, CURVED and not front-only (%u ceiling faces, %u front-only; "
              "without the rule %u of its faces became front-only one-way pieces, 0.9.2 left them out)", f.inner_ceiling,
              f.inner_fo, g.inner_fo);
    }
    // --- scenes without curves: nothing curved, the same triangles with the rule on and off ---
    {
        std::vector<ConvexSolid> s;
        auto box = [&](float x0, float y0, float z0, float x1, float y1, float z1) {
            const float a[3] = {x0, y0, z0}, b[3] = {x1, y1, z1};
            s.emplace_back();
            box_solid(a, b, nullptr, nullptr, s.back());
        };
        box(-500, -500, -16, 3000, 500, 0);                      // floor
        box(0, 0, 100, 200, 100, 108);                           // two stacked slabs
        box(0, 0, 164, 200, 100, 172);
        box(400, -64, 0, 528, -63, 128);                         // a fence of two 1-unit panels 2 apart
        box(400, -61, 0, 528, -60, 128);
        box(700, 0, 0, 732, 300, 160);                           // a 32-unit wall
        // a chamfered bench: an octagonal prism (45-degree chamfers 8 units)
        s.push_back(poly_solid({{1000, 0, 40}, {1008, 0, 32}, {1056, 0, 32}, {1064, 0, 40}, {1064, 0, 48}, {1056, 0, 56},
                                {1008, 0, 56}, {1000, 0, 48}, {1000, 200, 40}, {1008, 200, 32}, {1056, 200, 32}, {1064, 200, 40},
                                {1064, 200, 48}, {1056, 200, 56}, {1008, 200, 56}, {1000, 200, 48}},
                               {{0, 1, 2, 3, 4, 5, 6, 7}, {8, 9, 10, 11, 12, 13, 14, 15}, {0, 1, 9, 8}, {1, 2, 10, 9},
                                {2, 3, 11, 10}, {3, 4, 12, 11}, {4, 5, 13, 12}, {5, 6, 14, 13}, {6, 7, 15, 14}, {7, 0, 8, 15}}));
        std::vector<sa1_collision_tri> w[2];
        BspWorldStats st[2];
        for (int fix = 0; fix < 2; fix++) {
            BspWorldOptions o;
            o.thin_wall_max = 32.0f;
            o.curved = fix != 0;
            clean_solids(s, o, w[fix], st[fix], err);
        }
        bool same = w[0].size() == w[1].size();
        for (size_t i = 0; same && i < w[0].size(); i++) {
            same = std::memcmp(&w[0][i], &w[1][i], sizeof(sa1_collision_tri)) == 0;
        }
        const float lo[3] = {699, -1, 0}, hi[3] = {733, 301, 160};
        SteepPlanes wall = steep_planes(w[1], 0, lo, hi);
        CHECK(same && st[1].curved_faces == 0 && wall.planes.size() == 1 && wall.ds == wall.tris && wall.tris > 0,
              "stacked slabs, a fence, a 32-unit wall at thin walls 32 and a chamfered bench: nothing curved (%u faces), "
              "the same %zu triangles with the rule on and off; the 32-unit wall is still one double-sided middle face (%zu "
              "plane(s), %u of %u triangles double-sided)", st[1].curved_faces, w[1].size(), wall.planes.size(), wall.ds,
              wall.tris);
    }
}

// a minimal Source BSP (version 20) in memory
#pragma pack(push, 1)
struct WPlane {
    float n[3];
    float d;
    int32_t type;
};
struct WFace {
    uint16_t planenum;
    uint8_t side, on_node;
    int32_t firstedge;
    int16_t numedges, texinfo, dispinfo, fog;
    uint8_t styles[4];
    int32_t lightofs;
    float area;
    int32_t lm_mins[2], lm_size[2];
    int32_t orig_face;
    uint16_t num_prims, first_prim;
    uint32_t smoothing;
};
struct WTexinfo {
    float tv[2][4], lv[2][4];
    int32_t flags, texdata;
};
struct WLeaf {
    int32_t contents;
    int16_t cluster, areaflags;
    int16_t mins[3], maxs[3];
    uint16_t firstleafface, numleaffaces, firstleafbrush, numleafbrushes;
    int16_t water;
    uint16_t pad;
};
struct WModel {
    float mins[3], maxs[3], origin[3];
    int32_t headnode, firstface, numfaces;
};
struct WBrush {
    int32_t firstside, numsides, contents;
};
struct WSide {
    uint16_t planenum;
    int16_t texinfo, dispinfo;
    uint8_t bevel, thin;
};
struct WDispInfo {
    float start[3];
    int32_t vert_start, tri_start, power, min_tess;
    float smoothing;
    int32_t contents;
    uint16_t map_face, pad;
    int32_t lm_alpha_start, lm_sample_start;
    uint8_t neighbors[88];
    uint32_t allowed[10];
};
struct WDispVert {
    float vec[3];
    float dist, alpha;
};
#pragma pack(pop)
static_assert(sizeof(WPlane) == 20 && sizeof(WFace) == 56 && sizeof(WTexinfo) == 72 && sizeof(WLeaf) == 32 &&
                  sizeof(WModel) == 48 && sizeof(WBrush) == 12 && sizeof(WSide) == 8 && sizeof(WDispInfo) == 176 &&
                  sizeof(WDispVert) == 20,
              "BSP lump records");

struct BspBuilder {
    std::vector<WPlane> planes;
    std::vector<float> verts;
    std::vector<uint16_t> edges = {0, 0};   // edge 0 is never used
    std::vector<int32_t> surfedges;
    std::vector<WFace> faces;
    std::vector<WBrush> brushes;
    std::vector<WSide> sides;
    std::vector<WDispInfo> disps;
    std::vector<WDispVert> dverts;
    // a plane pair as vbsp writes them: 2k (n, d) and 2k + 1 (-n, -d)
    uint16_t plane(float nx, float ny, float nz, float d)
    {
        planes.push_back(WPlane{{nx, ny, nz}, d, 0});
        planes.push_back(WPlane{{-nx, -ny, -nz}, -d, 0});
        return (uint16_t)(planes.size() - 2);
    }
    // a convex solid brush from its outward planes {nx, ny, nz, d}; the plane numbers in `pn` (optional)
    void brush(const std::vector<std::array<float, 4>> &pl, std::vector<uint16_t> *pn = nullptr)
    {
        WBrush b{(int32_t)sides.size(), (int32_t)pl.size(), 1};
        for (const auto &p : pl) {
            uint16_t k = plane(p[0], p[1], p[2], p[3]);
            sides.push_back(WSide{k, 0, -1, 0, 0});
            if (pn) {
                pn->push_back(k);
            }
        }
        brushes.push_back(b);
    }
    void box(const float lo[3], const float hi[3], std::vector<uint16_t> *pn = nullptr)
    {
        brush({{1, 0, 0, hi[0]}, {-1, 0, 0, -lo[0]}, {0, 1, 0, hi[1]}, {0, -1, 0, -lo[1]}, {0, 0, 1, hi[2]},
               {0, 0, -1, -lo[2]}}, pn);
    }
    // a flat displacement (power 2) on a quad face of plane pn, corners c (corner 0 = its start), minTess flags mt;
    // dist (optional, 25 values, row r * 5 + column k: row r from corner 0 towards corner 1): each point raised along +z
    void disp(uint16_t pn, const float c[4][3], int32_t mt = 0, const float *dist = nullptr)
    {
        WFace f;
        std::memset(&f, 0, sizeof f);
        f.planenum = pn;
        f.firstedge = (int32_t)surfedges.size();
        f.numedges = 4;
        f.dispinfo = (int16_t)disps.size();
        f.lightofs = -1;
        uint16_t v0 = (uint16_t)(verts.size() / 3);
        for (int k = 0; k < 4; k++) {
            verts.insert(verts.end(), c[k], c[k] + 3);
        }
        for (int k = 0; k < 4; k++) {
            surfedges.push_back((int32_t)(edges.size() / 2));
            edges.push_back((uint16_t)(v0 + k));
            edges.push_back((uint16_t)(v0 + (k + 1) % 4));
        }
        WDispInfo d;
        std::memset(&d, 0, sizeof d);
        std::memcpy(d.start, c[0], sizeof d.start);
        d.vert_start = (int32_t)dverts.size();
        d.tri_start = -1;
        d.power = 2;
        d.min_tess = mt;
        d.map_face = (uint16_t)faces.size();
        for (int k = 0; k < 25; k++) {
            dverts.push_back(WDispVert{{0, 0, 1}, dist ? dist[k] : 0.0f, 0.0f});
        }
        faces.push_back(f);
        disps.push_back(d);
    }
    std::string bytes(const float mins[3], const float maxs[3]) const
    {
        std::string out(1036, '\0');
        std::memcpy(&out[0], "VBSP", 4);
        int32_t ver = 20;
        std::memcpy(&out[4], &ver, 4);
        auto lump = [&](int index, const void *p, size_t n, int32_t version = 0) {
            while (out.size() % 4) {
                out.push_back('\0');
            }
            int32_t l[4] = {(int32_t)out.size(), (int32_t)n, version, 0};
            std::memcpy(&out[8 + 16 * index], l, 16);
            out.append((const char *)p, n);
        };
        WTexinfo ti;
        std::memset(&ti, 0, sizeof ti);
        WLeaf leaf;
        std::memset(&leaf, 0, sizeof leaf);
        leaf.numleafbrushes = (uint16_t)brushes.size();
        std::vector<uint16_t> lb(brushes.size());
        for (size_t i = 0; i < lb.size(); i++) {
            lb[i] = (uint16_t)i;
        }
        WModel m;
        std::memset(&m, 0, sizeof m);
        std::memcpy(m.mins, mins, sizeof m.mins);
        std::memcpy(m.maxs, maxs, sizeof m.maxs);
        m.headnode = -1;   // leaf 0
        lump(1, planes.data(), planes.size() * sizeof(WPlane));
        lump(3, verts.data(), verts.size() * sizeof(float));
        lump(6, &ti, sizeof ti);
        lump(7, faces.data(), faces.size() * sizeof(WFace));
        lump(10, &leaf, sizeof leaf, 1);
        lump(12, edges.data(), edges.size() * sizeof(uint16_t));
        lump(13, surfedges.data(), surfedges.size() * sizeof(int32_t));
        lump(14, &m, sizeof m);
        lump(17, lb.data(), lb.size() * sizeof(uint16_t));
        lump(18, brushes.data(), brushes.size() * sizeof(WBrush));
        lump(19, sides.data(), sides.size() * sizeof(WSide));
        lump(26, disps.data(), disps.size() * sizeof(WDispInfo));
        lump(33, dverts.data(), dverts.size() * sizeof(WDispVert));
        return out;
    }
};

// the land triangles inside lo..hi (every corner) and their area, by facing (+1 up, -1 down, 0 steep)
static double area_in(const std::vector<sa1_collision_tri> &w, const float lo[3], const float hi[3], int facing,
                      uint32_t *count = nullptr)
{
    double a = 0.0;
    uint32_t n = 0;
    for (const sa1_collision_tri &t : w) {
        bool in = !(t.surface & SA1_SURFACE_KILL);
        for (int v = 0; v < 3 && in; v++) {
            for (int k = 0; k < 3; k++) {
                in = in && t.v[v][k] >= lo[k] - 0.01f && t.v[v][k] <= hi[k] + 0.01f;
            }
        }
        if (!in) {
            continue;
        }
        double e1[3], e2[3];
        for (int k = 0; k < 3; k++) {
            e1[k] = (double)t.v[1][k] - t.v[0][k];
            e2[k] = (double)t.v[2][k] - t.v[0][k];
        }
        double c[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
        double l = std::sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2]);
        if (!(l > 0.0)) {
            continue;
        }
        int f = c[2] / l >= 0.5 ? 1 : (c[2] / l <= -0.5 ? -1 : 0);
        if (f == facing) {
            a += 0.5 * l;
            n++;
        }
    }
    if (count) {
        *count = n;
    }
    return a;
}

// the fraction of n x n points over x0..x1 / y0..y1 (cell centres) that have a land triangle facing `facing` (+1 up,
// -1 down) at height z (+-0.5) over or under them
static double coverage(const std::vector<sa1_collision_tri> &w, float x0, float x1, float y0, float y1, float z, int facing,
                       int n = 20)
{
    int hit = 0;
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            double x = x0 + (x1 - x0) * (i + 0.5) / n, y = y0 + (y1 - y0) * (j + 0.5) / n;
            bool any = false;
            for (const sa1_collision_tri &t : w) {
                if (t.surface & SA1_SURFACE_KILL) {
                    continue;
                }
                double ax = t.v[0][0], ay = t.v[0][1], bx = t.v[1][0], by = t.v[1][1], cx = t.v[2][0], cy = t.v[2][1];
                double d = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
                if (std::fabs(d) < 1e-9 || (d > 0) != (facing > 0)) {
                    continue;   // vertical, or facing the other way (counter-clockwise seen from above = up)
                }
                double l1 = ((bx - x) * (cy - y) - (by - y) * (cx - x)) / d;
                double l2 = ((cx - x) * (ay - y) - (cy - y) * (ax - x)) / d;
                double l3 = 1.0 - l1 - l2;
                if (l1 < -1e-6 || l2 < -1e-6 || l3 < -1e-6) {
                    continue;
                }
                double zz = l1 * t.v[0][2] + l2 * t.v[1][2] + l3 * t.v[2][2];
                if (std::fabs(zz - z) <= 0.5) {
                    any = true;
                    break;
                }
            }
            hit += any;
        }
    }
    return (double)hit / (double)(n * n);
}

static void test_synthetic_bsp()
{
    std::printf("a synthetic map (0.9.2: thin stacks of displacements, displacements without hull collision, coplanar "
                "down faces, rockford's wedge brush, the guard)\n");
    BspBuilder B;
    // A: a 2-unit brush x -900..-700 with flat displacements on both sides (the brush is dropped, as the engine does:
    // two single-sided surfaces 2 units apart, gm_highway14800's barrier walls)
    std::vector<uint16_t> pa;
    const float alo[3] = {-900, -1, 0}, ahi[3] = {-700, 1, 128};
    B.box(alo, ahi, &pa);
    {
        const float cp[4][3] = {{-900, 1, 0}, {-900, 1, 128}, {-700, 1, 128}, {-700, 1, 0}};
        const float cm[4][3] = {{-700, -1, 0}, {-700, -1, 128}, {-900, -1, 128}, {-900, -1, 0}};
        B.disp(pa[2], cp);   // +y side
        B.disp(pa[3], cm);   // -y side
    }
    // B: two displacements on one plane facing opposite ways (y 200, x -400..-200: two faces back to back, 0 apart)
    {
        uint16_t p = B.plane(0, 1, 0, 200);
        const float cp[4][3] = {{-400, 200, 0}, {-400, 200, 128}, {-200, 200, 128}, {-200, 200, 0}};
        const float cm[4][3] = {{-200, 200, 0}, {-200, 200, 128}, {-400, 200, 128}, {-400, 200, 0}};
        B.disp(p, cp);
        B.disp((uint16_t)(p + 1), cm);
    }
    // C: flat displacement floors at z 100: x 0..200 with minTess 0x80000006 (no physics, no hull collision: rp_nycity's
    // river surface), x 300..500 with 0x80000002 (no physics collision only: the player's hull still collides)
    {
        uint16_t p = B.plane(0, 0, 1, 100);
        const float c1[4][3] = {{0, -100, 100}, {200, -100, 100}, {200, 100, 100}, {0, 100, 100}};
        const float c2[4][3] = {{300, -100, 100}, {500, -100, 100}, {500, 100, 100}, {300, 100, 100}};
        B.disp(p, c1, (int32_t)0x80000006u);
        B.disp(p, c2, (int32_t)0x80000002u);
    }
    // D: a displacement floor at z 0 (x 600..760) and a box brush x 700..800 standing on z 0: its bottom lies on the
    // floor for x 700..760 (0 units apart: the coplanar down face of rp_nycity, collision doc F6)
    {
        uint16_t p = B.plane(0, 0, 1, 0);
        const float c[4][3] = {{600, -100, 0}, {760, -100, 0}, {760, 100, 0}, {600, 100, 0}};
        B.disp(p, c);
        const float lo[3] = {700, -50, 0}, hi[3] = {800, 50, 64};
        B.box(lo, hi);
    }
    // E: rp_rockford_v2b's wedge brush (3304 -288 528)..(3312 1664 544), end plane (-0.9993 0.0370 0) d -3248.14
    {
        float l = std::sqrt(0.9993f * 0.9993f + 0.037f * 0.037f);
        B.brush({{1, 0, 0, 3312}, {-1, 0, 0, -3304}, {0, -1, 0, 288}, {0, 0, 1, 544}, {0, 0, -1, -528},
                 {-0.9993f / l, 0.037f / l, 0, -3248.14f / l}});
    }
    const float mins[3] = {-4096, -4096, -512}, maxs[3] = {4096, 4096, 1024};
    std::string bytes = B.bytes(mins, maxs);
    MemoryByteSource src(bytes.data(), bytes.size());
    Bsp bsp;
    std::string err;
    if (!bsp.open(src, err)) {
        CHECK(false, "the synthetic map: %s", err.c_str());
        return;
    }
    // the props: a box far outside the world (x 20000), one reaching out of it (x 4000..4300: the world ends at 4096)
    std::vector<ConvexSolid> extra(2);
    const float f0[3] = {20000, 0, 0}, f1[3] = {20064, 64, 64}, h0[3] = {4000, 0, 0}, h1[3] = {4300, 64, 64};
    box_solid(f0, f1, nullptr, nullptr, extra[0]);
    box_solid(h0, h1, nullptr, nullptr, extra[1]);
    auto build = [&](const BspWorldOptions &o, std::vector<sa1_collision_tri> &w, BspWorldStats &st) {
        bool ok = bsp.build_world(o, &extra, w, st, err);
        if (!ok) {
            CHECK(false, "build_world: %s", err.c_str());
        }
        return ok;
    };
    BspWorldOptions on, off;
    off.thin_stacks = false;
    off.guard = false;
    off.disp_nohull = false;
    off.coplanar_down = false;
    std::vector<sa1_collision_tri> w1, w0;
    BspWorldStats s1, s0;
    if (!build(on, w1, s1) || !build(off, w0, s0)) {
        return;
    }
    // A
    {
        const float lo[3] = {-901, -20, -1}, hi[3] = {-699, 20, 129};
        SteepPlanes a = steep_planes(w1, 1, lo, hi), b = steep_planes(w0, 1, lo, hi);
        CHECK(s1.displacement_brushes == 1 && a.planes.size() == 1 && a.tris > 0 && a.ds == a.tris &&
                  b.planes.size() == 2 && b.ds == 0,
              "a brush with displacements on both sides: one double-sided surface (%zu plane, %u of %u triangles "
              "double-sided); without the rule two single-sided ones %zu planes apart (%u double-sided)",
              a.planes.size(), a.ds, a.tris, b.planes.size(), b.ds);
    }
    // B
    {
        const float lo[3] = {-401, 190, -1}, hi[3] = {-199, 210, 129};
        SteepPlanes a = steep_planes(w1, 1, lo, hi), b = steep_planes(w0, 1, lo, hi);
        CHECK(a.tris > 0 && a.ds == a.tris && std::fabs(a.area - 200.0 * 128.0) < 1.0 &&
                  std::fabs(b.area - 2.0 * 200.0 * 128.0) < 1.0,
              "two coincident displacements facing opposite ways: one double-sided (%.0f square units, %u of %u "
              "double-sided); without the rule both (%.0f)", a.area, a.ds, a.tris, b.area);
    }
    // C
    {
        const float lo1[3] = {-1, -101, 99}, hi1[3] = {201, 101, 101}, lo2[3] = {299, -101, 99}, hi2[3] = {501, 101, 101};
        double a1 = area_in(w1, lo1, hi1, 1), a2 = area_in(w1, lo2, hi2, 1), b1 = area_in(w0, lo1, hi1, 1);
        CHECK(s1.displacements_nohull == 1 && a1 == 0.0 && std::fabs(a2 - 200.0 * 200.0) < 1.0 &&
                  std::fabs(b1 - 200.0 * 200.0) < 1.0,
              "a displacement with minTess 0x80000006 (no hull collision) gives no triangles (%.0f square units; "
              "without the rule %.0f), one with 0x80000002 stays (%.0f); %u left out", a1, b1, a2,
              s1.displacements_nohull);
    }
    // D
    {
        double a = coverage(w1, 700, 760, -50, 50, 0.0f, -1), r = coverage(w1, 760, 800, -50, 50, 0.0f, -1),
               b = coverage(w0, 700, 760, -50, 50, 0.0f, -1), fl = coverage(w1, 600, 760, -100, 100, 0.0f, 1);
        CHECK(a == 0.0 && r == 1.0 && b == 1.0 && fl == 1.0 && s1.coplanar_cut > 0,
              "a box's bottom on a displacement floor (0 units apart, half over it): no down face over the floor (%.0f %% "
              "of it; without the rule %.0f %%), the rest of the bottom stays (%.0f %%), the floor too (%.0f %%)",
              100.0 * a, 100.0 * b, 100.0 * r, 100.0 * fl);
    }
    // E
    {
        const float lo[3] = {3303, -289, 527}, hi[3] = {3313, 1665, 545};
        uint32_t inside = 0, outside = 0;
        for (const sa1_collision_tri &t : w1) {
            bool near = false, in = true;
            for (int v = 0; v < 3; v++) {
                near |= t.v[v][0] > 3000 && t.v[v][0] < 3600 && t.v[v][2] > 400 && t.v[v][2] < 700;
                for (int k = 0; k < 3; k++) {
                    in = in && t.v[v][k] >= lo[k] && t.v[v][k] <= hi[k];
                }
            }
            if (near) {
                (in ? inside : outside)++;
            }
        }
        CHECK(inside > 0 && outside == 0 && s1.tris_out_of_range == 0 && s1.thin_walls >= 1,
              "rockford's wedge brush: %u triangles inside its box, %u around it outside (0.9.1: the middle face ran to y "
              "262144), %u beyond any map", inside, outside, s1.tris_out_of_range);
    }
    // the guard
    {
        const float flo[3] = {19990, -10, -10}, fhi[3] = {20074, 74, 74}, hlo[3] = {3999, -1, -1},
                    hhi[3] = {4161, 65, 65};
        uint32_t nf1 = 0, nf0 = 0, nh1 = 0;
        area_in(w1, flo, fhi, 0, &nf1);
        area_in(w0, flo, fhi, 0, &nf0);
        area_in(w1, hlo, hhi, 1, &nh1);
        bool beyond = false;
        for (const sa1_collision_tri &t : w1) {
            for (int v = 0; v < 3; v++) {
                beyond |= !(t.surface & SA1_SURFACE_KILL) && t.v[v][0] > 4096 + 64;
            }
        }
        CHECK(nf1 == 0 && nf0 > 0 && s1.tris_outside > 0 && !beyond && s0.tris_outside == 0,
              "a prop far outside the world: none of its triangles (%u; without the guard %u); %u triangles with a "
              "corner beyond the world's bounds + 64 left out and counted, none left (the kill plane stays: %u "
              "triangles)", nf1, nf0, s1.tris_outside, s1.tris_kill);
        INFO("  the prop reaching out of the world keeps %u upward triangles inside the bounds + 64", nh1);
    }
}

// 0.9.3, the 0.9.2 owner notes on gm_highway14800 ("I still fall through the ground with tunnels", "some sinking into the
// ground") and gm_construct_in_flatgrass_v3's spot (-1834 -36), the coll-tunnel diagnosis (sadc build/research/colltunnel):
// disp_brush_exact (a brush beside a displacement on its plane stays: the tunnel floors) and disp_cover (up faces under
// displacement ground are left out, rooms under it stay)
static void test_disp_floors()
{
    std::printf("tunnel floors beside displacements, up faces buried under displacement ground (0.9.3)\n");
    BspBuilder B;
    std::vector<uint16_t> p1, p2;
    auto box = [&](float x0, float y0, float z0, float x1, float y1, float z1, std::vector<uint16_t> *pn = nullptr) {
        const float lo[3] = {x0, y0, z0}, hi[3] = {x1, y1, z1};
        B.box(lo, hi, pn);
    };
    // 1: a tunnel floor (x 0..128, y 0..2048, top z 0) with a short flat displacement on its plane over y 0..256 (vbsp writes
    // the displacement's own brush nowhere: gm_highway14800's brushes 53-59 beside the displacements 682-688)
    box(0, 0, -32, 128, 2048, 0, &p1);
    {
        const float c[4][3] = {{0, 0, 0}, {128, 0, 0}, {128, 256, 0}, {0, 256, 0}};
        B.disp(p1[4], c);
    }
    // 2: a displacement that IS its brush's top side (the brush is the displacement's own: dropped, as the engine does)
    box(300, 0, -32, 428, 256, 0, &p2);
    {
        const float c[4][3] = {{300, 0, 0}, {428, 0, 0}, {428, 256, 0}, {300, 256, 0}};
        B.disp(p2[4], c);
    }
    const uint16_t pz = B.plane(0, 0, 1, 0);   // z = 0, facing up
    auto ground = [&](float x0, float x1, float y0, float y1, const float *dist = nullptr) {
        const float c[4][3] = {{x0, y0, 0}, {x1, y0, 0}, {x1, y1, 0}, {x0, y1, 0}};
        B.disp(pz, c, 0, dist);
    };
    // 3: a brush top 8 units under flat ground (the sinking into covered roads)
    box(600, 0, -32, 728, 256, -8);
    ground(600, 728, 0, 256);
    // 4: a brush top 8 units under ground that covers half of it
    box(900, 0, -32, 1412, 256, -8);
    ground(900, 1156, 0, 256);
    // 5: a room under the ground: a floor at -120 under a slab (bottom -64, top -56), the ground at 0
    box(1600, 0, -136, 1728, 256, -120);
    box(1600, 0, -64, 1728, 256, -56);
    ground(1600, 1728, 0, 256);
    // 6: a floor 200 units under the ground (beyond disp_cover_max)
    box(1900, 0, -216, 2028, 256, -200);
    ground(1900, 2028, 0, 256);
    // 7: ground crossing a floor: rising from -16 (x 2200) to +16 (x 2456) over a brush top at 0
    box(2200, 0, -32, 2456, 256, 0);
    {
        float dist[25];
        for (int r = 0; r < 5; r++) {
            for (int k = 0; k < 5; k++) {
                dist[r * 5 + k] = -16.0f + 8.0f * (float)r;
            }
        }
        ground(2200, 2456, 0, 256, dist);
    }
    // 8: a cave of displacements: a floor at -60, a down-facing displacement at -20 (its ceiling), the ground at 0
    box(2600, 0, -76, 2728, 256, -60);
    {
        const uint16_t pd = B.plane(0, 0, -1, 20);   // z = -20, facing down
        const float c[4][3] = {{2600, 0, -20}, {2600, 256, -20}, {2728, 256, -20}, {2728, 0, -20}};
        B.disp(pd, c);
        ground(2600, 2728, 0, 256);
    }
    // 9: a static prop's hull whose top is 6 units under the ground
    ground(2980, 3100, 0, 128);
    std::vector<ConvexSolid> extra(1);
    {
        const float lo[3] = {3000, 16, -40}, hi[3] = {3064, 80, -6};
        box_solid(lo, hi, nullptr, nullptr, extra[0]);
    }
    const float mins[3] = {-512, -512, -512}, maxs[3] = {4096, 2560, 512};
    std::string bytes = B.bytes(mins, maxs);
    MemoryByteSource src(bytes.data(), bytes.size());
    Bsp bsp;
    std::string err;
    if (!bsp.open(src, err)) {
        CHECK(false, "the synthetic map: %s", err.c_str());
        return;
    }
    BspWorldOptions on, t1only, off;
    t1only.disp_cover_max = 0.0f;
    off.disp_brush_exact = false;
    off.disp_cover_max = 0.0f;
    std::vector<sa1_collision_tri> w1, wt, w0;
    BspWorldStats s1, st1, s0;
    if (!bsp.build_world(on, &extra, w1, s1, err) || !bsp.build_world(t1only, &extra, wt, st1, err) ||
        !bsp.build_world(off, &extra, w0, s0, err)) {
        CHECK(false, "build_world: %s", err.c_str());
        return;
    }
    auto up_area = [](const std::vector<sa1_collision_tri> &w, float x0, float x1, float y0, float y1, float z) {
        const float lo[3] = {x0 - 0.5f, y0 - 0.5f, z - 0.5f}, hi[3] = {x1 + 0.5f, y1 + 0.5f, z + 0.5f};
        return area_in(w, lo, hi, 1);
    };
    // 1, 2
    {
        // the floor's top (128 x 2048, one face) plus the displacement on it (128 x 256)
        double a1 = up_area(w1, 0, 128, 0, 2048, 0), a0 = up_area(w0, 0, 128, 0, 2048, 0);
        double a2 = up_area(w1, 300, 428, 0, 256, 0);
        CHECK(std::fabs(a1 - 128.0 * 2304.0) < 1.0 && std::fabs(a0 - 128.0 * 256.0) < 1.0 && s1.disp_brushes_kept == 1 &&
                  s1.displacement_brushes == 1 && s0.displacement_brushes == 2 && std::fabs(a2 - 128.0 * 256.0) < 1.0,
              "a tunnel floor beside a short displacement on its plane stays (%.0f square units of up faces there: the "
              "floor's 262144 and the displacement's 32768; 0.9.2's rule dropped the whole brush: %.0f); a displacement "
              "that is its brush's top still drops that brush (%.0f square units there: the displacement alone); brushes "
              "dropped %u (0.9.2: %u), kept %u", a1, a0, a2, s1.displacement_brushes, s0.displacement_brushes,
              s1.disp_brushes_kept);
    }
    // 3, 4, 9
    {
        double b3 = up_area(w1, 600, 728, 0, 256, -8), b3o = up_area(wt, 600, 728, 0, 256, -8);
        double g3 = up_area(w1, 600, 728, 0, 256, 0);
        double h4 = up_area(w1, 900, 1156, 0, 256, -8), k4 = up_area(w1, 1156, 1412, 0, 256, -8);
        double p9 = up_area(w1, 3000, 3064, 16, 80, -6), p9o = up_area(wt, 3000, 3064, 16, 80, -6);
        CHECK(b3 < 1.0 && std::fabs(b3o - 128.0 * 256.0) < 1.0 && std::fabs(g3 - 128.0 * 256.0) < 1.0 && h4 < 1.0 &&
                  std::fabs(k4 - 256.0 * 256.0) < 1.0 && p9 < 1.0 && p9o > 4000.0 && s1.disp_cover_faces >= 3,
              "a brush top 8 units under flat ground is left out (%.0f square units; without the rule %.0f), the ground "
              "stays (%.0f); under ground over half of it, that half (%.0f) - the other half stays (%.0f of %.0f); a "
              "prop's top 6 units under the ground (%.0f; without %.0f); %u faces cut, %u pieces, %.0f square units",
              b3, b3o, g3, h4, k4, 256.0 * 256.0, p9, p9o, s1.disp_cover_faces, s1.disp_cover_pieces, s1.disp_cover_area);
    }
    // 5, 6, 8
    {
        double f5 = up_area(w1, 1600, 1728, 0, 256, -120), t5 = up_area(w1, 1600, 1728, 0, 256, -56);
        double f6 = up_area(w1, 1900, 2028, 0, 256, -200), f8 = up_area(w1, 2600, 2728, 0, 256, -60);
        CHECK(std::fabs(f5 - 128.0 * 256.0) < 1.0 && t5 < 1.0 && std::fabs(f6 - 128.0 * 256.0) < 1.0 &&
                  std::fabs(f8 - 128.0 * 256.0) < 1.0,
              "a room under the ground keeps its floor (%.0f of %.0f square units; the slab's top above it, 56 units "
              "under the ground, is left out: %.0f); a floor 200 units under the ground stays (%.0f); a cave of "
              "displacements (a down-facing one over the floor) keeps its floor (%.0f)", f5, 128.0 * 256.0, t5, f6, f8);
    }
    // 7
    {
        double lowpart = coverage_bits(w1, 2204, 2316, 4, 252, 0.0f, 1, 0, SA1_SURFACE_DOUBLE_SIDED, 8);
        double highpart = coverage_bits(w1, 2348, 2452, 4, 252, 0.0f, 1, 0, SA1_SURFACE_DOUBLE_SIDED, 8);
        double before = coverage_bits(wt, 2348, 2452, 4, 252, 0.0f, 1, 0, SA1_SURFACE_DOUBLE_SIDED, 8);
        CHECK(lowpart > 0.99 && highpart < 0.01 && before > 0.99,
              "ground crossing a floor (from 16 under it to 16 over it): the floor stays where the ground is lower (%.0f%%), "
              "and is left out where the ground is over it (%.0f%%; without the rule %.0f%%)", 100 * lowpart, 100 * highpart,
              100 * before);
    }
}

// GRID-FALLBACK: a world over libsa1's limit is prepared once more without the triangles outside the map, and a world
// that is too big anyway says so in plain words
static void grid_soup(std::vector<sa1_collision_tri> &t, int n, float step, float x0, float y0, float z0)
{
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            float a = x0 + i * step, b = y0 + j * step, z = z0 + (float)((i * 7 + j * 13) % 5);
            t.push_back(sa1_collision_tri{{{a, b, z}, {a + step, b, z}, {a + step, b + step, z}}, SA1_SURFACE_SOLID});
            t.push_back(sa1_collision_tri{{{a, b, z}, {a + step, b + step, z}, {a, b + step, z}}, SA1_SURFACE_SOLID});
        }
    }
}

static void test_grid_fallback()
{
    std::printf("GRID-FALLBACK (0.9.2: a map over the game's collision memory)\n");
    // a 4800-unit square floor of 16-unit cells (180,000 triangles) inside the bounds, and 3 million triangles far
    // outside them (a phantom face through the map, cut into pieces: what rp_rockford_v2b's sliver hulls made)
    const float mins[3] = {-2500, -2500, -100}, maxs[3] = {2500, 2500, 100};
    std::vector<sa1_collision_tri> t;
    t.reserve(3200000);
    grid_soup(t, 300, 16.0f, -2400, -2400, 0);
    size_t inside = t.size();
    grid_soup(t, 1225, 16.0f, 8000, 8000, 50);
    PrepareResult r;
    PrepareOptions o;
    double t0 = now_ms();
    bool ok = prepare_world_guarded(t, mins, maxs, o, r);
    CHECK(ok && r.ok && r.retried && r.left_out == t.size() - inside && r.grid_triangles >= inside && !r.too_big,
          "%zu triangles (%zu of them outside the map): libsa1's limit, then prepared without the outside ones (%u "
          "left out, %u GRID triangles) in %.1f s%s%s", t.size(), t.size() - inside, r.left_out, r.grid_triangles,
          (now_ms() - t0) / 1000.0, r.ok ? "" : ": ", r.error.c_str());
    // 3 million triangles inside the map: too big, said plainly
    t.clear();
    grid_soup(t, 1225, 16.0f, -9800, -9800, 0);
    const float m2[3] = {-10000, -10000, -100}, x2[3] = {10000, 10000, 100};
    t0 = now_ms();
    ok = prepare_world_guarded(t, m2, x2, o, r);
    CHECK(!ok && r.too_big && !r.retried && r.status == SA1_ERR_LIMIT &&
              r.error.find("too big for the game") != std::string::npos &&
              r.error.find("no character can be created") != std::string::npos,
          "%zu triangles inside the map: too big (%.1f s): \"%s\"", t.size(), (now_ms() - t0) / 1000.0, r.error.c_str());
    // a failure that is not a size limit is left as it was (no retry): an empty soup is fine, so check the plain path
    std::vector<sa1_collision_tri> small;
    grid_soup(small, 10, 16.0f, 0, 0, 0);
    ok = prepare_world_guarded(small, nullptr, nullptr, o, r);
    CHECK(ok && r.ok && !r.retried && r.left_out == 0, "a small world prepares at once (%u GRID triangles)",
          r.grid_triangles);
}

static void sleep_ms(int ms)
{
    std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}

// 0.5.1: the world prepared by the job's worker (prepare.hpp, libsa1's sa1_collision_prepare_tris): installed in O(1),
// shared by every world created afterwards, and the characters on it move exactly as on the same triangles handed to
// sa1_collision_set_static (whose first world synthesizes them on the creating thread)
static void test_prepared(const std::string &gdi, const std::string &bsp, gamefs::GameFs &fs, const MapResult &c)
{
    std::printf("prepared world (libsa1's GRID synthesis on the map job's worker)\n");
    const PrepareResult &p = c.prep;
    CHECK(p.ok && p.prepared && p.triangles == c.world.size() && p.grid_triangles > c.world.size() / 2 &&
              p.grid_objects > 0,
          "the job prepared gm_construct on its worker in %.0f ms: %u triangles -> %u GRID triangles in %u objects, %u "
          "undersides within reach left out, %u KB%s%s", p.ms, p.triangles, p.grid_triangles, p.grid_objects,
          p.grid_undersides, p.bytes / 1024u, p.error.empty() ? "" : ": ", p.error.c_str());
    if (!p.ok) {
        return;
    }
    Session a, b;
    std::string err;
    if (!a.init(gdi, err) || !b.init(gdi, err)) {
        CHECK(false, "init: %s", err.c_str());
        return;
    }
    double t0 = now_ms();
    bool ok = a.set_world_prepared(p.prepared, err);
    double set_ms = now_ms() - t0;
    sa1_collision_info ia;
    a.world_info(ia);
    CHECK(ok && ia.prepared == 1 && ia.grid_triangles == p.grid_triangles && set_ms < 2.0,
          "set_world_prepared in %.3f ms (sa1_collision_set_prepared, O(1)): the context's geometry, %u GRID triangles%s%s",
          set_ms, ia.grid_triangles, ok ? "" : ": ", err.c_str());
    ok = b.set_world(c.world, err);
    CHECK(ok, "the same triangles through set_world (sa1_collision_set_static)%s%s", ok ? "" : ": ", err.c_str());
    // the same scripted input on both sessions: run forward, turn, jump, spin dash / punch, from the player start
    const float start[3] = {704, 132, -139};
    const int kinds[] = {SA1_CHAR_SONIC, SA1_CHAR_KNUCKLES, SA1_CHAR_TAILS, SA1_CHAR_BIG};
    int differ = 0, frames = 0;
    double ca_max = 0, cb_first = 0;
    uint32_t refs_with = 0;
    for (int kind : kinds) {
        double ma = 0, mb = 0;
        int32_t ida = a.create(kind, start, 3.14159265f, err, &ma);
        int32_t idb = b.create(kind, start, 3.14159265f, err, &mb);
        if (ida <= 0 || idb <= 0) {
            CHECK(false, "create kind %d: %s", kind, err.c_str());
            return;
        }
        ca_max = std::max(ca_max, ma);
        if (kind == SA1_CHAR_SONIC) {
            cb_first = mb;
            sa1_collision_prepared_info pi;
            p.prepared.info(pi);
            refs_with = pi.refs;
        }
        for (int f = 0; f < 360; f++) {
            float sy = f < 300 ? 1.0f : 0.0f, sx = (f / 60) % 2 ? 0.4f : -0.3f;
            uint32_t btn = (f % 90) == 45 ? SA1_BUTTON_JUMP : ((f % 90) > 70 ? SA1_BUTTON_ACTION : 0u);
            a.tick(ida, sx, sy, 0.0f, btn, 1.0f / 60.0f);
            b.tick(idb, sx, sy, 0.0f, btn, 1.0f / 60.0f);
            const Character *A = a.get(ida), *B = b.get(idb);
            frames++;
            differ += !A || !B || std::memcmp(A->st.position, B->st.position, sizeof A->st.position) != 0 ||
                      A->st.action != B->st.action;
        }
        a.destroy(ida);
        b.destroy(idb);
    }
    CHECK(differ == 0, "Sonic, Knuckles, Tails and Big (360 frames each of running, turning, jumping, actions): the "
          "prepared world and set_static agree in every frame (%d of %d differ)", differ, frames);
    CHECK(ca_max < 8.0 && refs_with >= 3,
          "creation on the prepared world: at most %.1f ms (on set_static's world the first one took %.0f ms: the GRID "
          "synthesis); %u references while Sonic lived (the job's result, the context, the world)", ca_max, cb_first,
          refs_with);
    // prepare = false: no preparation (MapApply then hands libsa1 the triangles)
    MapJobOptions np;
    np.prepare = false;
    MapResult r;
    MapJob j;
    ok = j.start_file("gm_construct", bsp, np, err) && run_map_job(j, &fs, nullptr, err) && j.take(r);
    CHECK(ok && !r.prep.ok && !r.prep.prepared && r.world.size() == c.world.size(),
          "prepare = false: the same world, nothing prepared");
    // a job dropped while it prepares: no waiting (the module retires it; idle() says when it can be deleted)
    MapJob *k = new MapJob();
    MapJobOptions kp;
    kp.static_props = false;   // no model files to feed: straight from building to preparing
    kp.surface_types = false;  // no material files either
    ok = k->start_file("gm_construct", bsp, kp, err);
    double tw = now_ms();
    while (ok && k->state() != MapState::Preparing && k->state() != MapState::Ready && k->state() != MapState::Failed &&
           now_ms() - tw < 20000.0) {
        k->poll();
        sleep_ms(1);
    }
    MapState k_state = k->state();
    bool saw = k_state == MapState::Preparing;
    double t1 = now_ms();
    k->request_cancel();
    double cancel_ms = now_ms() - t1;
    bool idle_at_once = k->idle();
    while (!k->idle() && now_ms() - t1 < 20000.0) {
        sleep_ms(1);
    }
    double idle_ms = now_ms() - t1;
    double t2 = now_ms();
    delete k;
    double del_ms = now_ms() - t2;
    CHECK(ok && saw && cancel_ms < 1.0 && del_ms < 5.0,
          "dropping a job while it prepares: request_cancel %.3f ms, idle %s after %.0f ms (the preparation runs to its "
          "end on the worker), delete %.2f ms%s%s", cancel_ms, idle_at_once ? "at once" : "", idle_ms, del_ms,
          saw ? "" : "; the job never prepared: ", saw ? "" : (ok ? map_state_name(k_state) : err.c_str()));
}

// ---- 6. surface types (0.8: sadc docs/research/gsa1_060_dig.md F1, F3-F5 with its Review R4: G1, G5, G6, G8, G14) ----
// the land triangle under (x, y) highest at most 8 units above z and at most `reach` below it (-1: none)
static int probe(const MapResult &r, double x, double y, double z, double reach = 24.0)
{
    int best = -1;
    double bz = -1e300;
    for (size_t i = 0; i < r.world.size(); i++) {
        const sa1_collision_tri &t = r.world[i];
        if ((t.surface & (SA1_SURFACE_WATER | SA1_SURFACE_HEAVY_WATER)) ||
            ((t.surface & SA1_SURFACE_KILL) && !(t.surface & SA1_SURFACE_SOLID))) {
            continue;
        }
        const float *a = t.v[0], *b = t.v[1], *c = t.v[2];
        double d1 = (x - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (y - b[1]);
        double d2 = (x - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (y - c[1]);
        double d3 = (x - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (y - a[1]);
        bool neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
        if (neg && pos) {
            continue;
        }
        double ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2], vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
        double nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
        double nl = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (!(nl > 0.0) || nz / nl < 0.5) {
            continue;   // walkable faces only
        }
        double zt = a[2] - (nx * (x - a[0]) + ny * (y - a[1])) / nz;
        if (zt <= z + 8.0 && zt >= z - reach && zt > bz) {
            bz = zt;
            best = (int)i;
        }
    }
    return best;
}

static std::string type_at(const MapResult &r, int i)
{
    if (i < 0 || (size_t)i >= r.world_tag.size()) {
        return "(none)";
    }
    uint32_t s = r.world_tag[(size_t)i] & 0xFFFFu;
    return s < r.types.size() ? r.types[s].name() : std::string("(untagged)");
}

static uint32_t surface_at(const MapResult &r, int i)
{
    return i >= 0 && (size_t)i < r.world.size() ? r.world[(size_t)i].surface : 0u;
}

static void surface_stats(const char *map, const MapResult &r)
{
    const MapStats &s = r.st;
    INFO("%s: %u materials (%u used, %u unusable names), %u .vmt read (%u missing, %u bad, %u patches, %u includes "
         "missing), %u without a $surfaceprop, %u blends, %u scripts, %u surface types; %u of %u triangles tagged; walkable "
         "%.0f%% diggable, %.1f%% slippery; G6: %u faces whose coplanar overlap went to another surface type; G7: %u thin "
         "walls of two types; %u stair ramps tagged; %u displacement triangles of a blend's second material; %u prop pieces "
         "with a .phy surface type; classes applied in %.1f ms",
         map, s.materials, s.materials_used, s.materials_bad, s.vmt_found, s.vmt_missing, s.vmt_bad, s.vmt_patches,
         s.vmt_includes_missing, s.vmt_default, s.vmt_blends, s.surface_scripts, s.surface_types, s.world.tris_tagged,
         s.world.tris, r.surf.walkable > 0 ? 100.0 * r.surf.dig / r.surf.walkable : 0.0,
         r.surf.walkable > 0 ? 100.0 * r.surf.slippery / r.surf.walkable : 0.0, s.world.coplanar_mixed,
         s.world.thin_walls_mixed, s.world.stairs_tagged, s.world.disp_tris_blend, s.props_surfaceprop, r.surf.ms);
}

static void test_surfaces_construct(const std::string &bsp, gamefs::GameFs &fs, MapResult &keep)
{
    std::printf("surface types: gm_construct\n");
    fs.set_map(bsp);
    // F1: the material names
    FileByteSource src;
    Bsp b;
    BspMaterials mats;
    std::string err;
    bool ok = src.open(bsp, err) && b.open(src, err) && b.materials(mats, err);
    auto has = [&](const char *n, bool used) {
        for (size_t i = 0; i < mats.names.size(); i++) {
            if (mats.names[i] == n) {
                return !used || mats.used[i] != 0;
            }
        }
        return false;
    };
    uint32_t used = 0;
    for (uint8_t u : mats.used) {
        used += u;
    }
    CHECK(ok && mats.texdata > 0 && mats.bad == 0 && has("gm_construct/grass_13", true) &&
              has("concrete/concretefloor026a", true),
          "F1: %u TEXDATA entries, %zu material names (%u used by collision faces), gm_construct/grass_13 and "
          "concrete/concretefloor026a among them", mats.texdata, mats.names.size(), used);
    // F3: tags, classes, the cache
    std::string dir = join_path(temp_dir(), "surf");
    make_dirs(dir);
    std::string cf = join_path(dir, "gm_construct.dat");
    if (file_exists(cf)) {
        write_file_replace(cf, "x", err);
    }
    MapJobOptions o;
    o.cache_dir = dir;
    MapResult r;
    MapDrive d;
    double t0 = now_ms();
    ok = run_job("gm_construct", bsp, o, fs, false, r, err, &d);
    double ms = now_ms() - t0;
    const BspWorldStats &w = r.st.world;
    CHECK(ok && r.world_tag.size() == r.world.size() && w.tris_tagged + w.tris_kill == w.tris && r.st.vmt_found > 0 &&
              r.st.surface_scripts == 1 && r.types.size() >= 126,
          "F3: built in %.0f ms (%u files fed, %u found): every triangle but the kill plane tagged (%u of %u), %u .vmt read, "
          "%zu surface types%s%s", ms, d.files, d.files_found, w.tris_tagged, w.tris, r.st.vmt_found, r.types.size(),
          ok ? "" : ": ", ok ? "" : err.c_str());
    surface_stats("gm_construct", r);
    int g = probe(r, -3120, 982, -44), c = probe(r, 298, -1491, -144);
    CHECK(g >= 0 && c >= 0 && (surface_at(r, g) & SA1_SURFACE_DIG) && !(surface_at(r, c) & SA1_SURFACE_DIG) &&
              type_at(r, g) == "grass" && type_at(r, c) == "concrete",
          "F3: the ground at (-3120 982 -44) is %s (%s), at (298 -1491 -144) %s (%s)", type_at(r, g).c_str(),
          (surface_at(r, g) & SA1_SURFACE_DIG) ? "diggable" : "not diggable", type_at(r, c).c_str(),
          (surface_at(r, c) & SA1_SURFACE_DIG) ? "diggable" : "not diggable");
    double share = r.surf.walkable > 0 ? r.surf.dig / r.surf.walkable : 0.0;
    CHECK(share > 0.85 && share < 0.98, "F3: %.1f%% of the walkable ground diggable (the research measured 93.1%%)",
          100.0 * share);
    // the second visit: a cache hit, no files, the same tags and slots
    MapResult r2;
    MapDrive d2;
    ok = run_job("gm_construct", bsp, o, fs, true, r2, err, &d2);
    bool same_tags = ok && r2.world_tag == r.world_tag && r2.types.size() == r.types.size();
    for (size_t i = 0; same_tags && i < r.types.size(); i++) {
        same_tags = r.types[i].chain == r2.types[i].chain && r.types[i].letter == r2.types[i].letter;
    }
    std::string why;
    CHECK(ok && r2.from_cache && d2.files == 0 && same_tags && same_result(r, r2, why),
          "F3: the second load is a cache hit (%u files fed) with the same tags, slots and classed triangles%s%s",
          d2.files, why.empty() ? "" : ": ", why.c_str());
    // a changed table: a cache hit, the bits follow (no rebuild)
    MapJobOptions o3 = o;
    o3.surfaces.table.names["grass"] = kKindSlippery;
    MapResult r3;
    MapDrive d3;
    ok = run_job("gm_construct", bsp, o3, fs, false, r3, err, &d3);
    int g3 = probe(r3, -3120, 982, -44);
    CHECK(ok && r3.from_cache && d3.files == 0 && (surface_at(r3, g3) & SA1_SURFACE_SLIPPERY) &&
              !(surface_at(r3, g3) & SA1_SURFACE_DIG) && r3.surf.hash != r.surf.hash,
          "F3: grass made slippery: a cache hit (%.0f ms to Ready, no files), the grass slippery and not diggable",
          r3.ready_ms);
    // G1: a type resolved only through its base chain, from the cache's slots
    MapJobOptions o4 = o;
    o4.surfaces.table.names.erase("grass");
    o4.surfaces.table.names["dirt"] = kKindSlippery | kKindNoClimb;
    MapResult r4;
    MapDrive d4;
    ok = run_job("gm_construct", bsp, o4, fs, false, r4, err, &d4);
    int g4 = probe(r4, -3120, 982, -44);
    uint32_t gi = g4 >= 0 ? r4.world_tag[(size_t)g4] & 0xFFFFu : 0xFFFFu;
    std::string how = gi < r4.surf.types.size() ? r4.surf.types[gi].how : "?";
    CHECK(ok && r4.from_cache && d4.files == 0 && (surface_at(r4, g4) & SA1_SURFACE_SLIPPERY) &&
              (surface_at(r4, g4) & SA1_SURFACE_NO_CLIMB) && !(surface_at(r4, g4) & SA1_SURFACE_DIG) && how == "base dirt",
          "G1: grass unlisted, dirt slippery and no-climbing: on a cache hit with no script fed, grass takes dirt's kinds "
          "(%s) through the cached chain", how.c_str());
    // G5: without the preparation (MapApply hands libsa1 the triangles) the classes are there too
    MapJobOptions o5 = o;
    o5.prepare = false;
    MapResult r5;
    ok = run_job("gm_construct", bsp, o5, fs, false, r5, err);
    int g5 = probe(r5, -3120, 982, -44);
    CHECK(ok && !r5.prep.ok && (surface_at(r5, g5) & SA1_SURFACE_DIG), "G5: prepare = false: the triangles MapApply hands "
          "libsa1 carry the classes");
    // surface types off: no tags, no material files
    MapJobOptions o6;
    o6.surface_types = false;
    MapResult r6;
    MapDrive d6;
    ok = run_job("gm_construct", bsp, o6, fs, false, r6, err, &d6);
    int g6 = probe(r6, -3120, 982, -44);
    CHECK(ok && r6.world_tag.empty() && r6.types.empty() && !(surface_at(r6, g6) & SA1_SURFACE_DIG) &&
              d6.files == r6.st.prop_models && r6.world.size() == r.world.size(),
          "surface_types = false: no tags, no material files (%u files: the props'), the same triangles (%zu)", d6.files,
          r6.world.size());
    keep = std::move(r);
}

static void test_surfaces_flatgrass(const std::string &bsp, gamefs::GameFs &fs)
{
    std::printf("surface types: gm_flatgrass\n");
    fs.set_map(bsp);
    MapJobOptions o;
    MapResult r;
    std::string err;
    bool ok = run_job("gm_flatgrass", bsp, o, fs, false, r, err);
    surface_stats("gm_flatgrass", r);
    // the research measured drawn faces (the FACES lump); the collision also has brush sides facing the void outside the
    // map (vbsp drops those faces): gm_flatgrass's sign texture under the map ("default": no $surfaceprop). Left out of
    // both sides of the share here, as the research's measure leaves them out.
    double untyped = 0.0;
    for (size_t i = 0; i < r.types.size() && i < r.surf.types.size(); i++) {
        if (r.types[i].name() == "default") {
            untyped += r.surf.types[i].area;
        }
    }
    double share = r.surf.walkable - untyped > 0 ? r.surf.dig / (r.surf.walkable - untyped) : 0.0;
    int spawn = probe(r, 0, 0, -12800);
    CHECK(ok && share >= 0.99 && (surface_at(r, spawn) & SA1_SURFACE_DIG) && type_at(r, spawn) == "grass",
          "F3: gm_flatgrass: %.1f%% of the walkable ground with a surface type diggable (at least 99%%; with the untyped "
          "sign under the map %.1f%%); the ground at the map's centre is %s", 100.0 * share,
          r.surf.walkable > 0 ? 100.0 * r.surf.dig / r.surf.walkable : 0.0, type_at(r, spawn).c_str());
}

// gm_bigcity (workshop 105982362) from Garry's Mod's own copy of the workshop file (garrysmod/cache/workshop, read-only),
// fed the addon's way (only the ranges the job asks for); its materials from the map's pak and the game's VPKs
static bool test_surfaces_bigcity(const std::string &gm, MapResult &out)
{
    std::string gma = join_path(join_path(join_path(gm, "cache"), "workshop"), "105982362.gma");
    gamefs::Gma g;
    uint64_t ofs = 0, len = 0;
    if (!file_exists(gma) || !g.load(gma) || !g.range("maps/gm_bigcity.bsp", ofs, len)) {
        INFO("%s (gm_bigcity) is not there: its surface checks are skipped", gma.c_str());
        return false;
    }
    std::printf("surface types: gm_bigcity (%s)\n", gma.c_str());
    gamefs::GameFs fs(gm);
    fs.set_map(gma, ofs);
    std::string dir = join_path(temp_dir(), "surf");
    make_dirs(dir);
    MapJobOptions o;
    o.cache_dir = dir;   // the second run of this test reads it from the cache
    MapJob job;
    std::string head, err;
    MapDrive d;
    double t0 = now_ms();
    bool ok = gamefs::read_range(gma, ofs, 1036, head) && job.start_fed("gm_bigcity", head.data(), head.size(), len, o, err) &&
              run_map_job(job, &fs, &gma, err, &d, 1u << 20, ofs) && job.take(out);
    CHECK(ok, "gm_bigcity loaded in %.1f s (%s; %.1f MB of %.1f MB fed, %u files)%s%s", (now_ms() - t0) / 1000.0,
          out.from_cache ? "from the cache" : "built", d.fed / 1048576.0, len / 1048576.0, d.files, ok ? "" : ": ",
          err.c_str());
    if (!ok) {
        return false;
    }
    surface_stats("gm_bigcity", out);
    int lawn = probe(out, -441, -3450, -11136), lawn2 = probe(out, -512, -2560, -11136), conc = probe(out, -425, -3645, -11144);
    CHECK(lawn >= 0 && conc >= 0 && lawn2 >= 0 && (surface_at(out, lawn) & SA1_SURFACE_DIG) &&
              (surface_at(out, lawn2) & SA1_SURFACE_DIG) && !(surface_at(out, conc) & SA1_SURFACE_DIG),
          "F3: the lawn where the owner stood (-441 -3450 -11136) is %s (%s), (-512 -2560) %s; the logged spot (-425 -3645 "
          "-11144) %s (%s)", type_at(out, lawn).c_str(), (surface_at(out, lawn) & SA1_SURFACE_DIG) ? "diggable" : "NOT diggable",
          type_at(out, lawn2).c_str(), type_at(out, conc).c_str(),
          (surface_at(out, conc) & SA1_SURFACE_DIG) ? "DIGGABLE" : "not diggable");
    double share = out.surf.walkable > 0 ? out.surf.dig / out.surf.walkable : 0.0;
    uint32_t prop_tris = 0, prop_dig = 0;
    for (size_t i = 0; i < out.world.size() && i < out.world_tag.size(); i++) {
        std::string n = type_at(out, (int)i);
        if (n == "metal" || n == "metalpanel" || n == "wood_crate" || n == "glass") {
            prop_tris++;
            prop_dig += (out.world[i].surface & SA1_SURFACE_DIG) != 0;
        }
    }
    CHECK(share > 0.03 && share < 0.15 && prop_tris > 0 && prop_dig == 0,
          "F3 / F4: %.1f%% of gm_bigcity's walkable ground diggable (the research measured 7.5%%; \"derives from dirt\" "
          "would give 36%%); %u triangles of metal / metalpanel / wood_crate / glass (its static props' types), none "
          "diggable", 100.0 * share, prop_tris);
    return true;
}

// ---- 0.9.3 on the owner's maps (read-only; skipped when a map is not there) ---------------------------------------------
// the owner's gm_bigcity house (gsa1_091b_ceiling.md section 2: the floor z -11136, the ceiling -11008 over x 200..440,
// y -312..56 under a roof 0..32 units thick): the whole interior ceiling is there, the strips under the roof's thin ends
// (x 200..264, 392..440) front-only; and no one-way solid was thickened (Review R.5.1: 1,480 if the marks returned 0)
static void test_bigcity_house(const MapResult &r)
{
    std::printf("0.9.3: gm_bigcity's house (the owner's 0.9.1a \"jumped through ceiling\")\n");
    const uint32_t FO = SA1_SURFACE_FRONT_ONLY;
    double all = coverage_bits(r.world, 204, 436, -308, 52, -11008, -1, 0, 0, 12);
    double west = coverage_bits(r.world, 204, 260, -308, 52, -11008, -1, FO, 0, 12);
    double east = coverage_bits(r.world, 396, 436, -308, 52, -11008, -1, FO, 0, 12);
    CHECK(all > 0.97 && west > 0.97 && east > 0.97 && r.st.world.thickened_floors == 0 && r.st.world.one_way_front_only > 0,
          "the house's interior ceiling at z -11008 is there (%.0f%%), FRONT-ONLY under the roof's thin ends (west %.0f%%, "
          "east %.0f%%; 0.9.2 left these out); %u pieces front-only on the map, %u floors thickened", 100 * all, 100 * west,
          100 * east, r.st.world.one_way_front_only, r.st.world.thickened_floors);
}

// a map inside a workshop GMA through the map job (fed, as the addon does), with options o
static bool load_gma_map(const std::string &gm, const std::string &gma, const char *entry, const char *name,
                         const MapJobOptions &o, MapResult &out)
{
    gamefs::Gma g;
    uint64_t ofs = 0, len = 0;
    if (!file_exists(gma) || !g.load(gma) || !g.range(entry, ofs, len)) {
        INFO("%s (%s) is not there: its checks are skipped", gma.c_str(), name);
        return false;
    }
    gamefs::GameFs fs(gm);
    fs.set_map(gma, ofs);
    MapJob job;
    std::string head, err;
    MapDrive d;
    double t0 = now_ms();
    bool ok = gamefs::read_range(gma, ofs, 1036, head) && job.start_fed(name, head.data(), head.size(), len, o, err) &&
              run_map_job(job, &fs, &gma, err, &d, 1u << 20, ofs) && job.take(out);
    CHECK(ok, "%s loaded in %.1f s (thin walls %.0f%s)%s%s", name, (now_ms() - t0) / 1000.0, o.world.thin_wall_max,
          o.world.one_way_front_only ? "" : ", no front-only ceilings", ok ? "" : ": ", err.c_str());
    return ok;
}

// the radial faces of a loop of a map (axis along y through (cx, *, cz)) inside the box |x - cx|, |z - cz| <= R + T + 48,
// |y - cy| <= ylen: on the inner surface (plane distance from the axis <= R + rin), in the middle (a thin wall's middle
// face: between), outer (>= R + T - 4)
struct MapLoop {
    uint32_t inner = 0, inner_walls = 0, inner_walls_curved = 0, inner_fo = 0, middle_ds = 0, curved = 0;
};
static MapLoop map_loop(const std::vector<sa1_collision_tri> &w, double cx, double cy, double cz, double R, double T,
                        double ylen, double rin)
{
    MapLoop m;
    for (const sa1_collision_tri &t : w) {
        double e1[3], e2[3], c[3];
        for (int k = 0; k < 3; k++) {
            e1[k] = (double)t.v[1][k] - t.v[0][k];
            e2[k] = (double)t.v[2][k] - t.v[0][k];
            c[k] = ((double)t.v[0][k] + t.v[1][k] + t.v[2][k]) / 3.0;
        }
        if (std::fabs(c[0] - cx) > R + T + 48 || std::fabs(c[2] - cz) > R + T + 48 || std::fabs(c[1] - cy) > ylen) {
            continue;
        }
        double n[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
        double l = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        if (!(l > 0.0) || std::fabs(n[1] / l) >= 0.5) {
            continue;
        }
        for (double &q : n) {
            q /= l;
        }
        double d = std::fabs(n[0] * (c[0] - cx) + n[2] * (c[2] - cz));
        double rad = std::sqrt((c[0] - cx) * (c[0] - cx) + (c[2] - cz) * (c[2] - cz));
        if (rad < R - 40.0 || rad > R + T + 40.0) {
            continue;   // not a face of the ribbon
        }
        m.curved += (t.surface & SA1_SURFACE_CURVED) != 0;
        if (d <= R + rin) {
            m.inner++;
            if (n[2] < 0.5 && n[0] * (c[0] - cx) + n[2] * (c[2] - cz) < 0.0) {   // facing the axis: the running surface
                m.inner_walls++;
                m.inner_walls_curved += (t.surface & SA1_SURFACE_CURVED) != 0;
                m.inner_fo += (t.surface & SA1_SURFACE_FRONT_ONLY) != 0;
            }
        } else if (d < R + T - 4.0) {
            m.middle_ds += (t.surface & SA1_SURFACE_DOUBLE_SIDED) != 0;
        }
    }
    return m;
}

// libsa1 internals (static linkage; test diagnostics only): the ground speed as a dash panel sets it (diag_maps.cpp)
extern "C" {
struct sa1g_world;
struct sa1g_world *sa1_character_world(const sa1_context *ctx, sa1_character_id id);
void *sa1g_world_ptr(const struct sa1g_world *w, uint32_t guest);
struct diag_player_ptrs {
    uint32_t tp, twp, mwp, pwp, csts;
};
void sa1g_world_player(const struct sa1g_world *w, struct diag_player_ptrs *out);
}
static void set_ground_speed(Session &s, int32_t id, float v)
{
    Character *c = s.get(id);
    sa1g_world *w = c ? sa1_character_world(s.ctx(), c->id) : nullptr;
    if (!w) {
        return;
    }
    diag_player_ptrs pp;
    std::memset(&pp, 0, sizeof pp);
    sa1g_world_player(w, &pp);
    void *p = pp.pwp ? sa1g_world_ptr(w, pp.pwp + 0x38) : nullptr;
    if (p) {
        std::memcpy(p, &v, 4);
    }
}

// a jump from the floor at (x, y, z) with the stick idle (A held 40 frames): did the feet get above z_ceil?
static bool map_jump_through(Session &s, int kind, float x, float y, float z, float z_ceil)
{
    std::string e;
    const float pos[3] = {x, y, z + 2.0f};
    int32_t id = s.create(kind, pos, 0.0f, e);
    if (id <= 0) {
        return true;
    }
    bool through = false;
    for (int f = 0; f < 200; f++) {
        s.tick(id, 0.0f, 0.0f, 0.0f, f >= 20 && f < 60 ? SA1_BUTTON_JUMP : 0u, 1.0f / 60.0f);
        Character *c = s.get(id);
        if (!c) {
            break;
        }
        const float *p = c->st.position;
        through |= p[2] > z_ceil + 1.0f && std::fabs(p[0] - x) < 96.0f && std::fabs(p[1] - y) < 96.0f;
    }
    s.destroy(id);
    return through;
}

// a run into a map's loop (axis along y through (cx, *, cz), inner radius R, thickness T) from `start` toward -x, the
// ground speed set on the ground until 0.6 R before the centre (sadc build/research/loop/loop_diag.cpp loop_run):
// 'C' completed (>= 330 degrees), 'T' put on top of the loop, 'f' fell off inside, '?' never reached it
static char map_loop_run(Session &s, double cx, double cy, double cz, double R, double T, const float start[3], float speed,
                         double *progress)
{
    std::string e;
    const float yaw = 3.14159265f;
    int32_t id = s.create(SA1_CHAR_SONIC, start, yaw, e);
    if (id <= 0) {
        return '?';
    }
    double phi_un = 0, phi_prev = 0, phi_max = -1e9;
    bool have = false, entered = false, top = false;
    int entered_f = -1;
    for (int f = 0; f < 900; f++) {
        s.tick(id, 0.0f, f < 24 ? 0.0f : 1.0f, yaw, 0, 1.0f / 60.0f);
        Character *c = s.get(id);
        if (!c) {
            break;
        }
        const float *p = c->st.position;
        bool ground = (c->st.flags & SA1_STATE_ON_GROUND) != 0;
        double dx = p[0] - cx, dz = p[2] - cz, r = std::sqrt(dx * dx + dz * dz);
        if (speed > 0.0f && ground && dx > 0.6 * R && !entered) {
            set_ground_speed(s, id, speed);
        }
        if (c->pairs_last == 0) {
            continue;
        }
        double phi = std::atan2(-dx, -dz) * 180.0 / 3.14159265358979;
        if (!have) {
            phi_un = phi;
            have = true;
        } else {
            double d = phi - phi_prev;
            while (d > 180) {
                d -= 360;
            }
            while (d < -180) {
                d += 360;
            }
            phi_un += d;
        }
        phi_prev = phi;
        bool on = ground && std::fabs(r - R) < 24.0 && std::fabs(p[1] - cy) < 600.0;
        if (!entered && on && std::fabs(dx) < 0.25 * R) {
            entered = true;
            entered_f = f;
            phi_un = phi;
        }
        if (entered && on) {
            phi_max = std::max(phi_max, phi_un);
        }
        top |= dz > 0 && r > R + T - 6.0 && std::fabs(dx) < R + T;
        if (entered && f > entered_f + 600) {
            break;
        }
    }
    s.destroy(id);
    *progress = phi_max < -1e8 ? 0.0 : phi_max;
    return !entered ? '?' : phi_max >= 330.0 ? 'C' : top ? 'T' : 'f';
}

static void test_owner_maps_093(const std::string &gm, const std::string &gdi)
{
    std::printf("0.9.3: the owner's maps (ceilings of gm_construct_in_flatgrass_v3, loops of gm_genesis; thin walls 32)\n");
    const std::string steam = join_path(join_path(join_path(gm, ".."), ".."), "..");   // ...\steamapps
    const uint32_t FO = SA1_SURFACE_FRONT_ONLY;
    // gm_construct_in_flatgrass_v3 (0.9.2 note at (-1834 -36 -8505): "I jumped through the ceiling twice"): the
    // underground ceilings above the floors at -8832 and -8680 (24- and 8-unit slabs: one-way until 0.9.2)
    {
        std::string gma = join_path(join_path(join_path(join_path(join_path(steam, "workshop"), "content"), "4000"),
                                              "3767235490"), "gmpublisher.gma");
        MapJobOptions o;
        o.world.thin_wall_max = 32.0f;
        o.prepare = false;
        MapResult r[2];
        bool ok = load_gma_map(gm, gma, "maps/gm_construct_in_flatgrass_v3.bsp", "gm_construct_in_flatgrass_v3", o, r[1]);
        if (ok) {
            o.world.one_way_front_only = false;
            load_gma_map(gm, gma, "maps/gm_construct_in_flatgrass_v3.bsp", "gm_construct_in_flatgrass_v3", o, r[0]);
            double c1 = coverage_bits(r[1].world, -1874, -1794, -76, 4, -8704, -1, FO, 0, 8);
            double c2 = coverage_bits(r[1].world, -1874, -1794, -76, 4, -8608, -1, FO, 0, 8);
            double o1 = coverage_bits(r[0].world, -1874, -1794, -76, 4, -8704, -1, 0, 0, 8);
            double o2 = coverage_bits(r[0].world, -1874, -1794, -76, 4, -8608, -1, 0, 0, 8);
            CHECK(c1 > 0.99 && c2 > 0.99 && o1 < 0.01 && o2 < 0.01,
                  "the two ceilings the owner jumped through at (-1834 -36), z -8704 and -8608: FRONT-ONLY ceilings now "
                  "(%.0f%%, %.0f%%; without front-only ceilings %.0f%%, %.0f%%: 0.9.2 left them out)", 100 * c1, 100 * c2,
                  100 * o1, 100 * o2);
        }
        if (ok && !gdi.empty()) {
            // with the disc: the six kinds jump at (-1834 -36) from the floors at -8832 and -8680 (0.9.2: all but Amy's short
            // jump went through, landing on -8680 / -8600 and, jumping again, on the terrain at -8505 where the owner wrote
            // the note)
            Session ss;
            std::string err;
            PrepareResult pr[2];
            int through[2] = {0, 0}, n = 0;
            if (ss.init(gdi, err) && prepare_world(r[1].world, PrepareOptions(), pr[1]) &&
                prepare_world(r[0].world, PrepareOptions(), pr[0])) {
                for (int on = 1; on >= 0; on--) {
                    ss.set_world_prepared(pr[on].prepared, err);
                    for (int kind : {SA1_CHAR_SONIC, SA1_CHAR_TAILS, SA1_CHAR_KNUCKLES, SA1_CHAR_AMY, SA1_CHAR_GAMMA, SA1_CHAR_BIG}) {
                        through[on] += map_jump_through(ss, kind, -1834, -36, -8832, -8704);
                        n += on;
                        if (kind != SA1_CHAR_GAMMA) {   // E-102 (84 units tall) does not fit under -8608 (72 units of room)
                            through[on] += map_jump_through(ss, kind, -1834, -36, -8680, -8608);
                            n += on;
                        }
                    }
                }
                CHECK(through[1] == 0, "the owner's spot at (-1834 -36): %d of %d jumps of the six kinds went through the "
                      "ceilings at -8704 / -8608 (0.9.2's one-way ceilings: %d)", through[1], n, through[0]);
            } else {
                CHECK(false, "gm_construct_in_flatgrass_v3 with the disc: %s%s", err.c_str(), pr[1].error.c_str());
            }
        }
    }
    // gm_genesis (0.9.1a note at (-3822 -10338 -13975): "going through loop forces me up onto the top of it"), the
    // owner's thin walls 32: the small loop (centre x -3584, z -14464, inner radius 512, 28.6-32 thick) and the big one
    // (x -6272, z -13952, 1024, 64 thick)
    {
        std::string gma = join_path(join_path(join_path(gm, "cache"), "workshop"), "266666023.gma");
        MapJobOptions o;
        o.world.thin_wall_max = 32.0f;
        o.prepare = false;
        MapResult r[2];
        if (load_gma_map(gm, gma, "maps/gm_genesis.bsp", "gm_genesis", o, r[1])) {
            o.world.curved = false;
            load_gma_map(gm, gma, "maps/gm_genesis.bsp", "gm_genesis", o, r[0]);
            MapLoop s1 = map_loop(r[1].world, -3584, -10304, -14464, 512, 32, 700, 11),
                    s0 = map_loop(r[0].world, -3584, -10304, -14464, 512, 32, 700, 11);
            MapLoop b1 = map_loop(r[1].world, -6272, -10624, -13952, 1024, 64, 900, 11);
            CHECK(s1.middle_ds == 0 && s1.inner_walls > 0 && s1.inner_walls_curved == s1.inner_walls && s1.inner_fo == 0 &&
                      s0.middle_ds > 0 && b1.curved > 0 && r[1].st.world.curved_surfaces > 0,
                  "gm_genesis' small loop: its running surface stays single-sided on the inner radius and CURVED (%u of %u "
                  "faces facing the axis curved, %u front-only, %u double-sided middle faces; without the curved-surface "
                  "rule %u middle faces: the owner's loop); the big loop %u curved faces; %u curved surfaces, %u faces on "
                  "the map", s1.inner_walls_curved, s1.inner_walls, s1.inner_fo, s1.middle_ds, s0.middle_ds, b1.curved,
                  r[1].st.world.curved_surfaces, r[1].st.world.curved_faces);
            if (!gdi.empty()) {
                // Sonic at loop speed (a dash panel's 10-16 units per step; gsa1_091a_loop.md 4: the small loop needs about
                // 7.6, the big one 11 - review R.4.6: 13 on 0.9.2's libsa1); running alone falls back off the wall (the game)
                Session ss;
                std::string err;
                PrepareResult pr[2];
                if (ss.init(gdi, err) && prepare_world(r[1].world, PrepareOptions(), pr[1]) &&
                    prepare_world(r[0].world, PrepareOptions(), pr[0])) {
                    std::string runs[2];
                    int done[2] = {0, 0}, top[2] = {0, 0}, btop = 0;
                    for (int fix = 1; fix >= 0; fix--) {
                        ss.set_world_prepared(pr[fix].prepared, err);
                        const float st[3] = {-1500.0f, -10304.0f, -14968.0f};
                        for (float v : {10.0f, 12.0f, 16.0f}) {
                            double prog = 0;
                            char c = map_loop_run(ss, -3584, -10304, -14464, 512, 32, st, v, &prog);
                            done[fix] += c == 'C';
                            top[fix] += c == 'T';
                            runs[fix] += format(" %.0f:%c(%.0f)", v, c, prog);
                        }
                        if (fix) {
                            const float bst[3] = {-4400.0f, -10624.0f, -14968.0f};
                            for (float v : {14.0f, 16.0f}) {
                                double prog = 0;
                                char c = map_loop_run(ss, -6272, -10624, -13952, 1024, 64, bst, v, &prog);
                                btop += c == 'T';
                                runs[fix] += format("; big loop %.0f:%c(%.0f)", v, c, prog);
                            }
                        }
                    }
                    CHECK(top[1] == 0 && done[1] >= 2 && btop == 0,
                          "gm_genesis' loops at the owner's thin walls 32, Sonic at loop speed (C completed, T put on top, f "
                          "fell off inside):%s; without the curved-surface rule:%s", runs[1].c_str(), runs[0].c_str());
                } else {
                    CHECK(false, "gm_genesis with the disc: %s%s", err.c_str(), pr[1].error.c_str());
                }
            }
        }
    }
}

// a run along y from (x, y, z) (dir +1 / -1) for `frames`, then back: the lowest the feet got (the death zone of
// gm_highway14800 is at z -7296; a tunnel floor's fall goes there)
static float map_run_lowest(Session &s, int kind, float x, float y, float z, float dir, int frames)
{
    std::string e;
    const float pos[3] = {x, y, z + 2.0f};
    const float yaw = dir > 0 ? 1.5707963f : -1.5707963f;
    int32_t id = s.create(kind, pos, yaw, e);
    if (id <= 0) {
        return -1e9f;
    }
    float low = 1e9f;
    for (int f = 0; f < 2 * frames; f++) {
        float yw = f < frames ? yaw : -yaw;
        s.tick(id, 0.0f, f < 20 ? 0.0f : 1.0f, yw, 0u, 1.0f / 60.0f);
        Character *c = s.get(id);
        if (!c) {
            break;
        }
        low = std::min(low, c->st.position[2]);
    }
    s.destroy(id);
    return low;
}

// 0.9.3: the owner's 0.9.2 maps (thin walls 32) - gm_highway14800's tunnel floors (z -5304) where he fell into the death
// zone four times (18:48:54 at (8761 -1062), 18:49:45 (-3444 -2936), 18:50:56 (-3489 -1116), 18:52:41 (9314 -439)): 0.9.2's
// displacement-brush rule dropped the floor brushes beside short flat displacements on their plane (the coll-tunnel
// diagnosis: west brushes 53-59, east 120-126); and gm_construct_in_flatgrass_v3's slab top at -8600 in the void under the
// terrain at (-1834 -36), where the owner stood under the ground (disp_cover)
static void test_owner_maps_tunnels(const std::string &gm, const std::string &gdi)
{
    std::printf("0.9.3: the owner's tunnels (gm_highway14800) and buried floors (gm_construct_in_flatgrass_v3)\n");
    const std::string steam = join_path(join_path(join_path(gm, ".."), ".."), "..");   // ...\steamapps
    {
        std::string gma = join_path(join_path(join_path(gm, "cache"), "workshop"), "152413570.gma");
        MapJobOptions o;
        o.world.thin_wall_max = 32.0f;
        o.prepare = false;
        MapResult r[2];
        if (load_gma_map(gm, gma, "maps/gm_highway14800.bsp", "gm_highway14800", o, r[1])) {
            o.world.disp_brush_exact = false;
            o.world.disp_cover_max = 0.0f;
            load_gma_map(gm, gma, "maps/gm_highway14800.bsp", "gm_highway14800", o, r[0]);
            double w1 = coverage_bits(r[1].world, -3480, -3440, -3000, -1100, -5304, 1, 0, 0, 12);
            double w0 = coverage_bits(r[0].world, -3480, -3440, -3000, -1100, -5304, 1, 0, 0, 12);
            double e1 = coverage_bits(r[1].world, 8980, 9020, -2200, -1200, -5304, 1, 0, 0, 12);
            double e0 = coverage_bits(r[0].world, 8980, 9020, -2200, -1200, -5304, 1, 0, 0, 12);
            CHECK(w1 > 0.99 && e1 > 0.99 && w0 < 0.2 && e0 < 0.2 && r[1].st.world.disp_brushes_kept > 0,
                  "the tunnel floors at z -5304 where the owner fell: west (x -3460, y -3000..-1100) %.0f%%, east (x 9000, "
                  "y -2200..-1200) %.0f%% (0.9.2: %.0f%%, %.0f%%); %u brushes beside displacements kept, %u dropped; %u up "
                  "faces under displacement ground cut (%u pieces, %.0f square units)", 100 * w1, 100 * e1, 100 * w0,
                  100 * e0, r[1].st.world.disp_brushes_kept, r[1].st.world.displacement_brushes,
                  r[1].st.world.disp_cover_faces, r[1].st.world.disp_cover_pieces, r[1].st.world.disp_cover_area);
            if (!gdi.empty()) {
                Session ss;
                std::string err;
                PrepareResult pr[2];
                if (ss.init(gdi, err) && prepare_world(r[1].world, PrepareOptions(), pr[1]) &&
                    prepare_world(r[0].world, PrepareOptions(), pr[0])) {
                    int fell[2] = {0, 0}, n = 0;
                    std::string lows[2];
                    for (int fix = 1; fix >= 0; fix--) {
                        ss.set_world_prepared(pr[fix].prepared, err);
                        const float spots[4][4] = {{-3460, -800, -5304, -1}, {-3460, -2900, -5304, 1},
                                                   {9000, -2440, -5304, 1}, {9000, -1300, -5304, -1}};
                        for (const auto &sp : spots) {
                            float low = map_run_lowest(ss, SA1_CHAR_SONIC, sp[0], sp[1], sp[2], sp[3], 240);
                            fell[fix] += low < -5400.0f;
                            n += fix;
                            lows[fix] += format(" %.0f", low);
                        }
                    }
                    CHECK(fell[1] == 0, "Sonic runs through the tunnels at the owner's falls: %d of %d runs fell (the lowest "
                          "the feet got:%s; 0.9.2's world: %d fell:%s)", fell[1], n, lows[1].c_str(), fell[0], lows[0].c_str());
                } else {
                    CHECK(false, "gm_highway14800 with the disc: %s%s", err.c_str(), pr[1].error.c_str());
                }
            }
        }
    }
    {
        std::string gma = join_path(join_path(join_path(join_path(join_path(steam, "workshop"), "content"), "4000"),
                                              "3767235490"), "gmpublisher.gma");
        MapJobOptions o;
        o.world.thin_wall_max = 32.0f;
        o.prepare = false;
        MapResult r[2];
        if (load_gma_map(gm, gma, "maps/gm_construct_in_flatgrass_v3.bsp", "gm_construct_in_flatgrass_v3", o, r[1])) {
            o.world.disp_cover_max = 0.0f;
            load_gma_map(gm, gma, "maps/gm_construct_in_flatgrass_v3.bsp", "gm_construct_in_flatgrass_v3", o, r[0]);
            double s1 = coverage_bits(r[1].world, -1874, -1794, -76, 4, -8600, 1, 0, 0, 8);
            double s0 = coverage_bits(r[0].world, -1874, -1794, -76, 4, -8600, 1, 0, 0, 8);
            double f1 = coverage_bits(r[1].world, -1874, -1794, -76, 4, -8680, 1, 0, 0, 8);
            double f2 = coverage_bits(r[1].world, -1874, -1794, -76, 4, -8832, 1, 0, 0, 8);
            CHECK(s1 < 0.01 && s0 > 0.99 && f1 > 0.99 && f2 > 0.99,
                  "the slab top at -8600 in the void under the terrain at (-1834 -36) is left out (%.0f%%; without the rule "
                  "%.0f%%: the owner stood there under the ground), the floors of the rooms below stay (-8680 %.0f%%, -8832 "
                  "%.0f%%); %u up faces cut under displacement ground (%u pieces, %.0f square units)", 100 * s1, 100 * s0,
                  100 * f1, 100 * f2, r[1].st.world.disp_cover_faces, r[1].st.world.disp_cover_pieces,
                  r[1].st.world.disp_cover_area);
        }
    }
}

// F5: Knuckles with the Shovel Claw presses action and jump together and keeps action held (the game: 8C0C8330 in mode 1)
struct DigRun {
    bool ground = false, dug = false, refused = false, back = false;
    uint32_t press_step = 0, dig_step = 0, back_step = 0;
    float z0 = 0, z1 = 0;
    std::string modes;
};

static DigRun dig_at(Session &s, const float spot[3], bool claw)
{
    DigRun d;
    std::string err;
    std::vector<const UpgradeDef *> ups;
    if (claw) {
        ups.push_back(find_upgrade(SA1_CHAR_KNUCKLES, "shovel_claw"));
    }
    const float start[3] = {spot[0], spot[1], spot[2] + 4.0f};
    int32_t id = s.create(SA1_CHAR_KNUCKLES, start, 0.0f, err, nullptr, &ups);
    if (id <= 0) {
        d.modes = "create: " + err;
        return d;
    }
    for (int f = 0; f < 60; f++) {
        s.tick(id, 0.0f, 0.0f, 0.0f, 0u, 1.0f / 60.0f);
    }
    Character *c = s.get(id);
    d.ground = c && (c->st.flags & SA1_STATE_ON_GROUND);
    d.z0 = c ? c->st.position[2] : 0.0f;
    d.press_step = c ? c->st.step : 0;
    int last = -999;
    for (int f = 0; f < 480 && c; f++) {
        uint32_t btn = f < 2 ? (SA1_BUTTON_ACTION | SA1_BUTTON_JUMP) : f < 10 ? SA1_BUTTON_ACTION : 0u;
        s.tick(id, 0.0f, 0.0f, 0.0f, btn, 1.0f / 60.0f);
        c = s.get(id);
        if (!c) {
            break;
        }
        int m = c->st.mode;
        if (m != last) {
            d.modes += format("%d@%u ", m, c->st.step - d.press_step);
            last = m;
        }
        if (m == 19 && !d.dug) {
            d.dug = true;
            d.dig_step = c->st.step;
        }
        d.refused = d.refused || m == 22;
        if (d.dug && !d.back && m == 1) {
            d.back = true;
            d.back_step = c->st.step;
            d.z1 = c->st.position[2];
        }
    }
    s.destroy(id);
    return d;
}

static void test_dig(const std::string &gdi, const char *map, const MapResult &r, const float dig_spot[3],
                     const float concrete_spot[3])
{
    std::printf("F5: Knuckles digs on %s\n", map);
    Session s;
    std::string err;
    bool ok = s.init(gdi, err) && (r.prep.ok && r.prep.prepared ? s.set_world_prepared(r.prep.prepared, err)
                                                                 : s.set_world(r.world, err));
    if (!ok) {
        CHECK(false, "%s: the session: %s", map, err.c_str());
        return;
    }
    DigRun a = dig_at(s, dig_spot, true), b = dig_at(s, concrete_spot, true), n = dig_at(s, dig_spot, false);
    CHECK(a.ground && a.dug && !a.refused && a.dig_step - a.press_step <= 6,
          "%s (%.0f %.0f %.0f), the Shovel Claw, action + jump: dug (mode 19) %u steps after the press; modes %s", map,
          dig_spot[0], dig_spot[1], dig_spot[2], a.dig_step - a.press_step, a.modes.c_str());
    CHECK(a.back && a.back_step - a.dig_step <= 160 && std::fabs(a.z1 - a.z0) <= 2.0f,
          "G14: out again (mode 1) %u steps after the dig began, at %+.2f units of the start height (at most 160 steps, "
          "0.5 SA1 units)", a.back_step - a.dig_step, a.z1 - a.z0);
    CHECK(b.ground && b.refused && !b.dug, "%s concrete (%.0f %.0f %.0f): the game's \"can't dig here\" (mode 22); modes %s",
          map, concrete_spot[0], concrete_spot[1], concrete_spot[2], b.modes.c_str());
    CHECK(!n.dug, "without the Shovel Claw no dig on the same grass (modes %s)", n.modes.c_str());
}

int main(int argc, char **argv)
{
    std::string gm = gsa1_garrysmod_dir(), maps, gdi;
    const char *env = std::getenv("SA1_TEST_GDI");
    if (env) {
        gdi = env;
    }
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--gm" && i + 1 < argc) {
            gm = argv[++i];
        } else if (a == "--maps" && i + 1 < argc) {
            maps = argv[++i];
        } else if (a == "--gdi" && i + 1 < argc) {
            gdi = argv[++i];
        } else if (a == "--verbose") {
            g_verbose = true;
        } else if (a == "--bsp" && i + 1 < argc) {
            ++i;   // build.py passes --bsp to every test; this one uses --gm
        }
    }
    std::printf("G-SA1 map_test\n");
    test_ranges();
    test_thin_stacks();
    test_ceilings_and_loops();
    test_synthetic_bsp();
    test_disp_floors();
    test_grid_fallback();
    gamefs::GameFs fs(gm);
    test_phy(fs);
    MapResult construct;
    std::string bsp = join_path(join_path(gm, "maps"), "gm_construct.bsp");
    if (file_exists(bsp)) {
        test_job(bsp, fs, construct);
    } else {
        INFO("%s is missing: the map job checks are skipped", bsp.c_str());
    }
    if (!maps.empty()) {
        for (const char *m : {"gm_bigcity_improved_rp.bsp", "gm_driversheaven_tdm.bsp"}) {
            std::string p = join_path(maps, m);
            if (file_exists(p)) {
                test_props(p, fs);
            }
        }
    }
    // surface types (0.8)
    MapResult surf_construct, surf_bigcity;
    if (file_exists(bsp)) {
        test_surfaces_construct(bsp, fs, surf_construct);
    }
    std::string flat = join_path(join_path(gm, "maps"), "gm_flatgrass.bsp");
    if (file_exists(flat)) {
        test_surfaces_flatgrass(flat, fs);
    }
    bool big = test_surfaces_bigcity(gm, surf_bigcity);
    if (big) {
        test_bigcity_house(surf_bigcity);
    }
    test_owner_maps_093(gm, gdi);
    test_owner_maps_tunnels(gm, gdi);
    if (!gdi.empty()) {
        if (!surf_construct.world.empty()) {
            const float g[3] = {-3120, 982, -44}, c[3] = {298, -1491, -144};
            test_dig(gdi, "gm_construct", surf_construct, g, c);
        }
        if (big) {
            const float g[3] = {-441, -3450, -11136}, c[3] = {-425, -3645, -11144};
            test_dig(gdi, "gm_bigcity", surf_bigcity, g, c);
        }
    }
    if (!gdi.empty()) {
        if (!construct.world.empty()) {
            test_prepared(gdi, bsp, fs, construct);
        }
        test_movers(gdi, construct.world.empty() ? nullptr : &construct);
        test_thin_walls(gdi);
    } else {
        INFO("no disc (--gdi or SA1_TEST_GDI): the moving object checks are skipped");
    }
    std::printf("map_test: %d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
