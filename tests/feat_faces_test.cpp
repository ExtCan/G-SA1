// feat_faces_test: the event faces in G-SA1's core (round 0.9.4a: sadc docs/research/faces_wheel_plan.md 6.4 with its
// Review; libsa1.h "faces", SA1_API_FACE; the measured timelines of LIB tests/face_test.c F3 / F7 / F15), offline. build.py
// links it like core_test (the core and libsa1) and runs it with --gdi when there is one.
//
//   feat_faces_test [--gdi GAME.gdi] [--verbose]
//
// With the disc, through gsa1::Session (the module's code path: tick, render, batches) on a flat floor:
//   * event faces on: within 2 pairs Sonic's batches draw the event head's own textures (archive 0, textures 25-27 with
//     SA1_DRAW_* 0x30 - the states the census's face segment added); off: gone within 2 pairs; before any call: none;
//   * Big's event head (archive 0 texture 2, which only the event head draws);
//   * a face animation "Z:6:30" in the regular-face mode: the state's face_to is key 8 within 4 pairs, the event head is
//     drawn while it plays, and after about 18 pairs the regular head is back (face_shown 0, the textures gone);
//   * lip sync: a level ramp 0 -> 1 walks the mouth ladder (face_from / face_to neighbours on the character's own ladder from
//     sa1_face_info_get - 0.9.4c: per character, Sonic 0 4 16 - activity LIPSYNC), -1 closes the mouth and the regular head
//     comes back;
//   * 0.9.4c (phoneme_plan.md 6.2 V10): sa1_character_face_mouth, a pair at a time on Sonic: after the pair it is applied
//     face_from / face_to are its keys (activity LIPSYNC); -1 closes; Big's key 8 refused (SA1_ERR_INVALID_ARGUMENT)
//     without a fault, his 0 > 4 shown; E-102's mouth refused (SA1_ERR_UNSUPPORTED);
//   * E-102: every face call refused (SA1_ERR_UNSUPPORTED), no event head;
//   * the census (core_test's material_census.txt next to this test, and the addon's cl_warm_census.lua generated from it)
//     holds the event heads' states, so the pre-warm (tests/warm_test.lua) makes them before the first face.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "../src/core/session.hpp"
#include "../src/core/util.hpp"

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

#if defined(SA1_API_FACE)

// ---- a flat floor ---------------------------------------------------------------------------------------------------------
static void floor_tiles(std::vector<sa1_collision_tri> &out, float x0, float x1, float y0, float y1, float z, float tile)
{
    for (float x = x0; x < x1 - 0.5f; x += tile) {
        for (float y = y0; y < y1 - 0.5f; y += tile) {
            const float p[4][3] = {{x, y, z}, {x + tile, y, z}, {x + tile, y + tile, z}, {x, y + tile, z}};
            sa1_collision_tri a, b;
            std::memset(&a, 0, sizeof a);
            std::memset(&b, 0, sizeof b);
            const int ia[3] = {0, 1, 2}, ib[3] = {0, 2, 3};
            for (int v = 0; v < 3; v++) {
                std::memcpy(a.v[v], p[ia[v]], 12);
                std::memcpy(b.v[v], p[ib[v]], 12);
            }
            a.surface = b.surface = SA1_SURFACE_SOLID;
            out.push_back(a);
            out.push_back(b);
        }
    }
}

// one game pair standing, then the render of it
static bool pair(Session &s, int32_t id)
{
    std::vector<sa1_event> ev;
    sa1_status st = s.tick(id, 0.0f, 0.0f, 0.0f, 0u, 1.0f / 30.0f);
    s.poll_events(ev);
    sa1_status rs = s.render(id, 1.0f);
    if (st != SA1_OK || rs != SA1_OK) {
        std::printf("        tick / render: %s\n", s.last_error().c_str());
    }
    return st == SA1_OK && rs == SA1_OK;
}

// batches of archive 0 drawing texture t with all of `flags`
static int drawn(const Character *c, int t, uint32_t flags)
{
    int n = 0;
    for (uint32_t i = 0; i < c->batch_count; i++) {
        const RenderBatch &b = c->batches[i];
        n += b.archive == 0 && b.texture == t && (b.flags & flags) == flags;
    }
    return n;
}

static bool sonic_ev(const Character *c)
{
    return drawn(c, 25, 0x30) && drawn(c, 26, 0x30) && drawn(c, 27, 0x30);
}

static bool any_sonic_ev(const Character *c)
{
    return drawn(c, 25, 0x30) || drawn(c, 26, 0x30) || drawn(c, 27, 0x30);
}

static std::string why(Session &s, sa1_status st)
{
    const char *e = sa1_last_error(s.ctx());
    return format("%s: %s", sa1_status_string(st), e ? e : "");
}

static void test_event(Session &s)
{
    std::printf("event faces (the switch):\n");
    std::string err;
    const float at[3] = {-2000.0f, 0.0f, 8.0f};
    int32_t id = s.create(SA1_CHAR_SONIC, at, 0.0f, err);
    const Character *c = id > 0 ? s.get(id) : nullptr;
    CHECK(c != nullptr, "Sonic created (%s)", err.c_str());
    if (!c) return;
    bool clean = true;
    for (int p = 0; p < 10; p++) {
        pair(s, id);
        clean = clean && !any_sonic_ev(c);
    }
    CHECK(clean && c->st.face_mode == 0 && c->st.face_letter == -1 && c->st.face_from == -1,
          "before any face call: no event head textures in 10 pairs; the state's face fields are \"none\" (mode 0, "
          "letter -1, from -1)");
    sa1_status st = sa1_character_face_mode(s.ctx(), id, SA1_FACE_MODE_EVENT);
    int on_at = -1;
    for (int p = 1; p <= 6; p++) {
        pair(s, id);
        if (on_at < 0 && sonic_ev(c)) on_at = p;
    }
    CHECK(st == SA1_OK && on_at > 0 && on_at <= 2 && c->st.face_mode == SA1_FACE_MODE_EVENT && c->st.face_shown,
          "event faces on: Sonic's batches draw archive 0 textures 25, 26 and 27 with flags 0x30 from pair %d (at most "
          "2); face_mode %u, shown %u", on_at, (unsigned)c->st.face_mode, (unsigned)c->st.face_shown);
    st = sa1_character_face_mode(s.ctx(), id, SA1_FACE_MODE_GAME);
    int off_at = -1;
    for (int p = 1; p <= 6; p++) {
        pair(s, id);
        if (off_at < 0 && !any_sonic_ev(c)) off_at = p;
    }
    CHECK(st == SA1_OK && off_at > 0 && off_at <= 2 && !any_sonic_ev(c) && c->st.face_mode == SA1_FACE_MODE_GAME,
          "event faces off: the event head's textures are gone from pair %d (at most 2)", off_at);

    // a face animation in the regular-face mode: Z (surprised) entered over 6 frames, held 30 (F15)
    sa1_face_entry e;
    std::memset(&e, 0, sizeof e);
    e.anim = 25;
    e.enter = 6;
    e.hold = 30;
    st = sa1_character_face_sequence(s.ctx(), id, &e, 1u, 0u);
    int to8 = -1, back_at = -1, ev_pairs = 0;
    for (int p = 1; p <= 30; p++) {
        pair(s, id);
        if (to8 < 0 && c->st.face_to == 8) to8 = p;
        ev_pairs += any_sonic_ev(c) ? 1 : 0;
        if (to8 > 0 && back_at < 0 && !c->st.face_shown && c->st.face_activity == SA1_FACE_ACT_NONE) back_at = p;
    }
    bool gone = !any_sonic_ev(c);
    CHECK(st == SA1_OK && to8 > 0 && to8 <= 4 && back_at >= 16 && back_at <= 21 && ev_pairs >= 14 && gone,
          "face animation \"Z:6:30\": face_to 8 from pair %d (at most 4), the event head drawn in %d pairs, the regular "
          "head back at pair %d (about 18: LIB F15) and its textures gone", to8, ev_pairs, back_at);

    // lip sync: a ramp 0 -> 1, then -1 (the ladder is the character's own: sa1_face_info_get, 0.9.4c's per-character ones)
    sa1_face_info fi;
    std::memset(&fi, 0, sizeof fi);
    fi.struct_size = sizeof fi;
    sa1_status fst = sa1_face_info_get(s.ctx(), SA1_CHAR_SONIC, &fi);
    const int lad_n = fi.ladder_len > 8u ? 8 : (int)fi.ladder_len;
    std::string lad;
    for (int i = 0; i < lad_n; i++) lad += format("%s%d", i ? "-" : "", fi.ladder[i]);
    int steps_ok = 0, n = 0, lip = 0;
    std::string walk;
    for (int p = 0; p <= 16; p++) {
        float lv = (float)p / 16.0f;
        sa1_character_face_level(s.ctx(), id, lv, SA1_FACE_LEVEL_LADDER);
        pair(s, id);
        n++;
        int a = -1, b = -1;
        for (int i = 0; i < lad_n; i++) {
            if (fi.ladder[i] == c->st.face_from) a = i;
            if (fi.ladder[i] == c->st.face_to) b = i;
        }
        steps_ok += a >= 0 && (b == a + 1 || (b == a && a == lad_n - 1));
        lip += c->st.face_activity == SA1_FACE_ACT_LIPSYNC;
        if (p % 4 == 0) walk += format("%s%d>%d", walk.empty() ? "" : " ", c->st.face_from, c->st.face_to);
    }
    sa1_character_face_level(s.ctx(), id, -1.0f, SA1_FACE_LEVEL_LADDER);
    int closed_at = -1;
    for (int p = 1; p <= 20; p++) {
        pair(s, id);
        if (closed_at < 0 && !c->st.face_shown && !any_sonic_ev(c)) closed_at = p;
    }
    CHECK(fst == SA1_OK && lad_n >= 2 && steps_ok == n && lip == n && closed_at > 0 && closed_at <= 8,
          "lip sync: a level ramp 0 -> 1 walks Sonic's mouth ladder %s from sa1_face_info_get (%d of %d pairs on neighbouring "
          "keys, %d with activity LIPSYNC; %s); -1: the mouth closes and the regular head is back at pair %d", lad.c_str(),
          steps_ok, n, lip, walk.c_str(), closed_at);

    // 0.9.4c: the host's own mouth (sa1_character_face_mouth), one call per pair
    static const struct {
        uint32_t a, b;
        float w;
    } mouths[] = {{0, 4, 0.5f}, {6, 16, 0.4f}, {4, 16, 0.3f}, {0, 7, 0.75f}, {7, 16, 0.6f}, {0, 6, 0.9f}};
    int shown = 0, mlip = 0;
    sa1_status mst = SA1_OK;
    std::string seen;
    for (const auto &m : mouths) {
        sa1_status r = sa1_character_face_mouth(s.ctx(), id, m.a, m.b, m.w, 0u);
        if (r != SA1_OK) mst = r;
        pair(s, id);
        shown += c->st.face_from == (int32_t)m.a && c->st.face_to == (int32_t)m.b;
        mlip += c->st.face_activity == SA1_FACE_ACT_LIPSYNC;
        seen += format("%s%d>%d@%.2f", seen.empty() ? "" : " ", c->st.face_from, c->st.face_to, c->st.face_rate);
    }
    sa1_character_face_mouth(s.ctx(), id, 0u, 0u, -1.0f, 0u);
    int mclosed = -1;
    for (int p = 1; p <= 20; p++) {
        pair(s, id);
        if (mclosed < 0 && !c->st.face_shown && !any_sonic_ev(c)) mclosed = p;
    }
    CHECK(mst == SA1_OK && shown == 6 && mlip == 6 && mclosed > 0 && mclosed <= 8,
          "FaceMouth (sa1_character_face_mouth) on Sonic: after each pair face_from / face_to are the keys of its call (%d "
          "of 6: %s; activity LIPSYNC in %d); weight -1 closes the mouth (the regular head back at pair %d)", shown,
          seen.c_str(), mlip, mclosed);
    s.destroy(id);
}

static void test_big_gamma(Session &s)
{
    std::printf("Big and E-102:\n");
    std::string err;
    const float at[3] = {-1000.0f, 0.0f, 8.0f};
    int32_t id = s.create(SA1_CHAR_BIG, at, 0.0f, err);
    const Character *c = id > 0 ? s.get(id) : nullptr;
    CHECK(c != nullptr, "Big created (%s)", err.c_str());
    if (!c) return;
    bool before = false;
    for (int p = 0; p < 6; p++) {
        pair(s, id);
        before = before || drawn(c, 2, 0x20);
    }
    sa1_status st = sa1_character_face_mode(s.ctx(), id, SA1_FACE_MODE_EVENT);
    int on_at = -1;
    for (int p = 1; p <= 6; p++) {
        pair(s, id);
        if (on_at < 0 && drawn(c, 2, 0x20)) on_at = p;
    }
    sa1_face_entry e;
    std::memset(&e, 0, sizeof e);
    e.anim = 27;                                   // 'b': Big cannot show it
    sa1_status sb = sa1_character_face_sequence(s.ctx(), id, &e, 1u, 0u);
    std::string wb = why(s, sb);
    CHECK(st == SA1_OK && !before && on_at > 0 && on_at <= 2 && sb == SA1_ERR_UNSUPPORTED,
          "Big: his event head (archive 0 texture 2, flags 0x20) only with event faces, from pair %d; 'b' refused (%s)",
          on_at, wb.c_str());
    // 0.9.4c: Big's eight keys - key 8 refused (a key >= 8 reads wrong data, >= 16 faults the world), 0 > 4 shown
    sa1_status k8 = sa1_character_face_mouth(s.ctx(), id, 0u, 8u, 0.5f, 0u);
    std::string w8 = why(s, k8);
    bool k8_pair = pair(s, id);
    sa1_status k4 = sa1_character_face_mouth(s.ctx(), id, 0u, 4u, 0.5f, 0u);
    bool k4_pair = pair(s, id);
    CHECK(k8 == SA1_ERR_INVALID_ARGUMENT && k8_pair && !c->faulted && k4 == SA1_OK && k4_pair && c->st.face_from == 0 &&
              c->st.face_to == 4,
          "Big: FaceMouth key 8 refused without a fault (%s); 0 > 4 shown after the next pair (%d > %d)", w8.c_str(),
          c->st.face_from, c->st.face_to);
    s.destroy(id);
    id = s.create(SA1_CHAR_GAMMA, at, 0.0f, err);
    c = id > 0 ? s.get(id) : nullptr;
    CHECK(c != nullptr, "E-102 created (%s)", err.c_str());
    if (!c) return;
    pair(s, id);
    sa1_status g1 = sa1_character_face_mode(s.ctx(), id, SA1_FACE_MODE_EVENT);
    std::string w1 = why(s, g1);
    sa1_status g2 = sa1_character_face_sequence(s.ctx(), id, &e, 1u, 0u);
    sa1_status g3 = sa1_character_face_level(s.ctx(), id, 0.5f, SA1_FACE_LEVEL_LADDER);
    sa1_status g4 = sa1_character_face_mouth(s.ctx(), id, 0u, 4u, 0.5f, 0u);
    pair(s, id);
    CHECK(g1 == SA1_ERR_UNSUPPORTED && g2 == SA1_ERR_UNSUPPORTED && g3 == SA1_ERR_UNSUPPORTED && g4 == SA1_ERR_UNSUPPORTED &&
              c->st.face_mode == 0 && !c->st.face_shown,
          "E-102: every face call refused, the mouth too (%s); no face state", w1.c_str());
    s.destroy(id);
}

// the census next to this test (core_test wrote it) and the addon's data generated from it
static void test_census(const std::string &dir)
{
    std::printf("the material census (the pre-warm):\n");
    std::string text, err;
    std::string path = join_path(dir.empty() ? std::string(".") : dir, "material_census.txt");
    if (!read_small_file(path, 16u << 20, text, err)) {
        std::printf("  info  no material census at %s (core_test writes it with the disc): skipped\n", path.c_str());
        return;
    }
    static const int ev[][2] = {{0, 25}, {0, 26}, {0, 27}, {2, 19}, {2, 20}, {3, 2}, {3, 3}, {3, 4}, {5, 9}, {5, 10}};
    std::string missing;
    for (const auto &e : ev) {
        if (text.find(format("\n%d 0 %d 30 ", e[0], e[1])) == std::string::npos) missing += format(" %d/%d", e[0], e[1]);
    }
    std::string lua;
    std::string lpath = join_path(join_path(join_path(join_path(join_path(dir, ".."), ".."), "addon"), "lua"),
                                  "gsa1/cl_warm_census.lua");
    bool have_lua = read_small_file(lpath, 16u << 20, lua, err);
    std::string lmiss;
    if (have_lua) {
        for (const auto &e : ev) {
            size_t at = lua.find(format("    [%d] = {", e[0]));
            size_t end = lua.find("\n    },", at == std::string::npos ? 0 : at);
            std::string item = format("{ 0, %d, 0x30,", e[1]);
            size_t f = at == std::string::npos ? std::string::npos : lua.find(item, at);
            if (f == std::string::npos || f > end) lmiss += format(" %d/%d", e[0], e[1]);
        }
    }
    CHECK(missing.empty() && (!have_lua || lmiss.empty()),
          "the census holds the event heads' states (Sonic 25-27, Tails 19-20, Knuckles 2-4, Amy 9-10; flags 0x30)%s%s; "
          "the addon's cl_warm_census.lua too%s%s", missing.empty() ? "" : ": missing", missing.c_str(),
          have_lua ? (lmiss.empty() ? "" : ": missing") : " (not found: skipped)", lmiss.c_str());
}

#endif  // SA1_API_FACE

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--gdi" && i + 1 < argc) {
            gdi = argv[++i];
        } else if (a == "--verbose") {
            g_verbose = true;
        } else {
            std::printf("usage: feat_faces_test [--gdi GAME.gdi] [--verbose]\n");
            return 2;
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_faces_test (libsa1 %s)\n", sa1_version_string());
#if !defined(SA1_API_FACE)
    CHECK(false, "libsa1.h has no faces section (round 0.9.4a, SA1_API_FACE)");
#else
    CHECK(SA1_FACE_SEQ_MAX == 32u && SA1_FACE_HOLD_MAX == 3600u && SA1_FACE_MODE_EVENT == 1u,
          "libsa1 has the faces (SA1_API_FACE): 32 entries per face animation, holds up to 3600 frames");
    test_census(parent_dir(argv[0]));
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the world checks need the disc\n");
    } else {
        Session s;
        std::string err;
        bool ok = s.init(gdi, err);
        std::vector<sa1_collision_tri> floor;
        floor_tiles(floor, -4096.0f, 4096.0f, -2048.0f, 2048.0f, 0.0f, 1024.0f);
        ok = ok && s.set_world(floor, err);
        CHECK(ok, "the disc and a flat floor (%s)", err.c_str());
        if (ok) {
            test_event(s);
            test_big_gamma(s);
        }
        s.shutdown();
    }
#endif
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
