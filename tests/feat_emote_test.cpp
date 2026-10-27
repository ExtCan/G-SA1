// feat_emote_test: the emote feature in G-SA1's core (round 0.9.4a: sadc docs/research/faces_wheel_plan.md 6.5 with its
// Review R.16 / R.18; libsa1.h "emotes", SA1_API_EMOTE; src/core/emote.{hpp,cpp}, what bind_emote.cpp's Lua functions
// call), offline. build.py links it like core_test (the core and libsa1) and runs it with --gdi when there is one.
//
//   feat_emote_test [--gdi GAME.gdi] [--verbose]
//
// Without the disc: the keys parse and print; the API is there.
// With the disc, through gsa1::Session (the module's code path) on a flat floor:
//   * a standing Sonic plays "a75" (s_kimepose0, the level clear pose) through gsa1::emote_play: the state says PLAYING
//     with row 75 within 2 pairs and the drawn body (root-relative) differs from a second, standing Sonic's; a stick input
//     ends it, and the pair after it equals the standing Sonic's pair with the same input (position, speed, mode, action,
//     the rand state): the game ran untouched underneath;
//   * refusals in libsa1's plain words: in the air -> "in the air", running -> "moving" (review R.16);
//   * the catalogues of the 8 character entries (Sonic, Tails, Knuckles, Amy, E-102, Big, Super Sonic (Vs. Perfect Chaos),
//     the General form while Super): every entry played for a pair on a standing character of its entry without a fault,
//     and stopped; written to emote_lists.txt next to this test (entry, kind, form, position, key, internal name, dup,
//     played) for tests/feat_wheel_test.lua, which checks the wheels' defaults (W.DEFAULTS) and the greyed rows against it
//     (review R.18: the C++ test does not read Lua);
//   * round 0.9.4b (objects2_plan.md 11.2, libsa1's SA1_API_EMOTE_HOLD): emote_play(a75, SA1_EMOTE_HOLD) - the wheel's
//     "Hold the last pose" - reaches HOLDING on row 75's last frame (64) and stays there: 90 pairs later the drawn body is
//     the same; a stick input ends it at once; the same with a loop flag (G-SA1's "loop it") loops and is never HOLDING.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "../src/core/emote.hpp"
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

#define INFO(...)                                            \
    do {                                                     \
        std::printf("  info  ");                             \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

#if defined(SA1_API_EMOTE)

// ---- the scene: a flat floor (host space, z up) -------------------------------------------------------------------------------
static void quad(std::vector<sa1_collision_tri> &out, float x0, float y0, float x1, float y1, float z)
{
    sa1_collision_tri a, b;
    std::memset(&a, 0, sizeof a);
    std::memset(&b, 0, sizeof b);
    const float p[4][3] = {{x0, y0, z}, {x1, y0, z}, {x1, y1, z}, {x0, y1, z}};
    const int ia[3] = {0, 1, 2}, ib[3] = {0, 2, 3};
    for (int v = 0; v < 3; v++) {
        std::memcpy(a.v[v], p[ia[v]], 12);
        std::memcpy(b.v[v], p[ib[v]], 12);
    }
    a.surface = b.surface = SA1_SURFACE_SOLID;
    out.push_back(a);
    out.push_back(b);
}

static bool flat_floor(Session &s)
{
    std::vector<sa1_collision_tri> floor;
    for (float x = -8192.0f; x < 8191.0f; x += 1024.0f) {
        for (float y = -2048.0f; y < 2047.0f; y += 1024.0f) {
            quad(floor, x, y, x + 1024.0f, y + 1024.0f, 0.0f);
        }
    }
    std::string err;
    bool ok = s.set_world(floor, err);
    if (!ok) CHECK(false, "set_world: %s", err.c_str());
    return ok;
}

static std::vector<sa1_event> g_ev;

static sa1_status pair(Session &s, int32_t id, float sx, float sy, uint32_t b = 0)
{
    sa1_status st = s.tick(id, sx, sy, 0.0f, b, 1.0f / 30.0f);
    s.poll_events(g_ev);
    if (st != SA1_OK && g_verbose) std::printf("        tick: %s\n", s.last_error().c_str());
    return st;
}

static bool run(Session &s, int32_t id, int pairs, float sy = 0.0f, uint32_t b = 0)
{
    for (int i = 0; i < pairs; i++) {
        if (SA1_FAILED(pair(s, id, 0.0f, sy, b))) return false;
    }
    return true;
}

static int32_t make(Session &s, int32_t kind, const float pos[3], std::string &err, bool general = false)
{
    if (general) {
        CreateExtra ex;
        ex.flags = SA1_CREATE_SUPER_CAPABLE;
        ex.super_given = true;
        ex.super_flags = SA1_SUPER_GENERAL | SA1_SUPER_START | SA1_SUPER_NO_DRAIN;
        return s.create(kind, pos, 0.0f, err, nullptr, nullptr, 50, &ex);
    }
    return s.create(kind, pos, 0.0f, err);
}

// the drawn vertices relative to the drawn root (alpha 1: the last pair)
static std::vector<float> body(Session &s, int32_t id)
{
    std::vector<float> out;
    if (s.render(id, 1.0f) != SA1_OK) return out;
    const Character *c = s.get(id);
    if (!c) return out;
    out.reserve(c->r_tpos.size());
    for (size_t i = 0; i + 2 < c->r_tpos.size(); i += 3) {
        out.push_back(c->r_tpos[i] - c->r_pos[0]);
        out.push_back(c->r_tpos[i + 1] - c->r_pos[1]);
        out.push_back(c->r_tpos[i + 2] - c->r_pos[2]);
    }
    return out;
}

static float max_diff(const std::vector<float> &a, const std::vector<float> &b)
{
    if (a.size() != b.size() || a.empty()) return 1e9f;
    float m = 0.0f;
    for (size_t i = 0; i < a.size(); i++) m = std::max(m, std::fabs(a[i] - b[i]));
    return m;
}

// ---- 1. play, cancel by the stick, the game untouched ------------------------------------------------------------------------
static void test_play(Session &s)
{
    std::printf("a standing Sonic plays s_kimepose0 (a75); the stick ends it; the game underneath is untouched\n");
    std::string err;
    const float at[3] = {-4000.0f, 0.0f, 8.0f};
    int32_t a = make(s, SA1_CHAR_SONIC, at, err), b = make(s, SA1_CHAR_SONIC, at, err);
    CHECK(a > 0 && b > 0, "two Sonics at one place (%s)", err.c_str());
    if (a <= 0 || b <= 0) return;
    run(s, a, 20);
    run(s, b, 20);
    uint32_t src = 0, idx = 0;
    emote_parse_key("a75", src, idx);
    sa1_status st = emote_play(s.ctx(), a, src, idx, 0);
    std::string why = SA1_FAILED(st) ? emote_error(s.ctx(), st) : "";
    int playing_at = -1;
    for (int p = 1; p <= 2; p++) {
        pair(s, a, 0, 0);
        pair(s, b, 0, 0);
        const Character *ca = s.get(a);
        if (playing_at < 0 && ca && ca->st.emote_state == SA1_EMOTE_STATE_PLAYING && ca->st.emote_row == 75) playing_at = p;
    }
    run(s, a, 10);
    run(s, b, 10);
    float d = max_diff(body(s, a), body(s, b));
    const Character *ca = s.get(a), *cb = s.get(b);
    CHECK(st == SA1_OK && playing_at > 0 && ca && ca->st.emote_state == SA1_EMOTE_STATE_PLAYING && d > 1.0f && d < 1e8f,
          "emote_play(a75) -> %s%s; PLAYING with row 75 after %d pair(s); 12 pairs in, the drawn body differs from the "
          "standing Sonic's by up to %.1f HU", sa1_status_string(st), why.c_str(), playing_at, d);
    // the stick: the emote ends before the pair that reads it
    pair(s, a, 0.0f, 1.0f);
    pair(s, b, 0.0f, 1.0f);
    ca = s.get(a);
    cb = s.get(b);
    bool same = ca && cb && ca->st.emote_state == SA1_EMOTE_STATE_NONE && ca->st.mode == cb->st.mode &&
                ca->st.action == cb->st.action && ca->st.rand_state == cb->st.rand_state &&
                std::memcmp(ca->st.position, cb->st.position, sizeof ca->st.position) == 0 &&
                std::memcmp(ca->st.player_speed, cb->st.player_speed, sizeof ca->st.player_speed) == 0;
    CHECK(same, "a stick input ends it: the pair after it equals the standing Sonic's pair with the same input (mode %d / "
          "%d, action %d / %d, x %.3f / %.3f, rand %08X / %08X)", ca ? ca->st.mode : -1, cb ? cb->st.mode : -1,
          ca ? ca->st.action : -1, cb ? cb->st.action : -1, ca ? ca->st.position[0] : 0.0, cb ? cb->st.position[0] : 0.0,
          ca ? ca->st.rand_state : 0u, cb ? cb->st.rand_state : 0u);
    s.destroy(a);
    s.destroy(b);
}

// ---- 1b. HOLD (round 0.9.4b): the pose stays on its last frame until the player moves ------------------------------------
#if defined(SA1_API_EMOTE_HOLD)
static int until_state(Session &s, int32_t id, uint32_t want, int max_pairs)
{
    for (int p = 1; p <= max_pairs; p++) {
        if (SA1_FAILED(pair(s, id, 0, 0))) return -1;
        const Character *c = s.get(id);
        if (c && c->st.emote_state == want) return p;
    }
    return -1;
}

static void test_hold(Session &s)
{
    std::printf("HOLD: a standing Sonic's s_kimepose0 (a75) stays on its last frame until he moves (round 0.9.4b)\n");
    std::string err;
    const float at[3] = {-1000.0f, -1000.0f, 8.0f};
    int32_t id = make(s, SA1_CHAR_SONIC, at, err);
    CHECK(id > 0, "a Sonic (%s)", err.c_str());
    if (id <= 0) return;
    run(s, id, 20);
    sa1_status st = emote_play(s.ctx(), id, SA1_EMOTE_ROW, 75, SA1_EMOTE_HOLD);
    int held = until_state(s, id, SA1_EMOTE_STATE_HOLDING, 150);
    const Character *c = s.get(id);
    int row = c ? c->st.emote_row : -1;
    float frame = c ? c->st.emote_frame : -1.0f;
    run(s, id, 1);
    std::vector<float> b0 = body(s, id);
    run(s, id, 90);
    std::vector<float> b1 = body(s, id);
    c = s.get(id);
    bool still = c && c->st.emote_state == SA1_EMOTE_STATE_HOLDING && c->st.emote_row == 75;
    float d = max_diff(b0, b1);
    CHECK(st == SA1_OK && held > 0 && row == 75 && std::fabs(frame - 64.0f) < 0.01f && still && d < 0.01f,
          "emote_play(a75, HOLD) -> %s; HOLDING after %d pairs on row %d frame %.2f; 90 pairs (3 s) later still holding, "
          "the drawn body moved %.4f HU", sa1_status_string(st), held, row, frame, d);
    pair(s, id, 0.0f, 1.0f);
    c = s.get(id);
    CHECK(c && c->st.emote_state == SA1_EMOTE_STATE_NONE, "a stick input ends the held pose at once (state %u)",
          c ? (unsigned)c->st.emote_state : 99u);
    run(s, id, 60);
    st = emote_play(s.ctx(), id, SA1_EMOTE_ROW, 75, SA1_EMOTE_HOLD | kEmoteLoop);
    bool holding = false, playing = false;
    for (int p = 0; p < 150; p++) {
        pair(s, id, 0, 0);
        c = s.get(id);
        holding = holding || (c && c->st.emote_state == SA1_EMOTE_STATE_HOLDING);
        playing = c && c->st.emote_state == SA1_EMOTE_STATE_PLAYING;
    }
    CHECK(st == SA1_OK && !holding && playing, "with \"loop it\" (G-SA1's LOOP) the same row loops: 150 pairs later still "
          "playing, never HOLDING (HOLD is for animations that end in a pose)");
    s.destroy(id);
}
#endif

// ---- 2. refusals in plain words --------------------------------------------------------------------------------------------------
static void test_refusals(Session &s)
{
    std::printf("refusals in libsa1's plain words (review R.16)\n");
    std::string err;
    const float high[3] = {-2000.0f, 0.0f, 600.0f};
    int32_t id = make(s, SA1_CHAR_SONIC, high, err);
    run(s, id, 3);
    const Character *c = s.get(id);
    bool air = c && !(c->st.game_flags & 3u);
    sa1_status st = emote_play(s.ctx(), id, SA1_EMOTE_ROW, 3, 0);
    std::string why = emote_error(s.ctx(), st);
    CHECK(air && st == SA1_ERR_UNSUPPORTED && why == "in the air" && std::string(emote_code(st)) == "unsupported",
          "falling (mode %d): refused with \"%s\" (%s)", c ? c->st.mode : -1, why.c_str(), emote_code(st));
    s.destroy(id);
    const float at[3] = {-2000.0f, 0.0f, 8.0f};
    id = make(s, SA1_CHAR_SONIC, at, err);
    run(s, id, 15);
    run(s, id, 30, 1.0f);
    c = s.get(id);
    st = emote_play(s.ctx(), id, SA1_EMOTE_ROW, 3, 0);
    why = emote_error(s.ctx(), st);
    CHECK(st == SA1_ERR_UNSUPPORTED && why == "moving", "running (mode %d, %.1f units per step): refused with \"%s\"",
          c ? c->st.mode : -1, c ? c->st.player_speed[0] : 0.0f, why.c_str());
    st = emote_play(s.ctx(), id, SA1_EMOTE_ROW, 130, 0);
    why = emote_error(s.ctx(), st);
    CHECK(st == SA1_ERR_INVALID_ARGUMENT && why.find("not available for Sonic") != std::string::npos &&
              std::string(emote_code(st)) == "bad_argument",
          "an entry not offered (130 for a normal Sonic): \"%s\" (%s)", why.c_str(), emote_code(st));
    s.destroy(id);
}

// ---- 3. every entry of the 8 lists plays; emote_lists.txt ------------------------------------------------------------------------
struct EntryDef {
    const char *name;
    int32_t kind;
    uint32_t form;
    bool general;
    size_t want;
};

static void test_lists(Session &s, const std::string &out_path)
{
    std::printf("the catalogues of the 8 entries: every entry plays for a pair; %s\n", out_path.c_str());
    const EntryDef defs[] = {
        {"sonic", 0, 0, false, 107}, {"tails", 2, 0, false, 140}, {"knuckles", 3, 0, false, 122}, {"amy", 5, 0, false, 105},
        {"gamma", 6, 0, false, 89}, {"big", 7, 0, false, 96}, {"supersonic", 8, 0, false, 92},
        {"supersonic_general", 0, 1, true, 119},
    };
    std::string text = "# G-SA1 emote lists (tests/feat_emote_test.cpp, libsa1 " + std::string(sa1_version_string()) +
                       "): every catalogue entry of the 8 character entries, played for a pair on the disc\n"
                       "# entry\tkind\tform\tpos\tkey\tname\tdup\tplayed (ok / refused: <why> / fault / not started)\n";
    int total = 0, played = 0;
    std::string problems, sizes;
    for (const EntryDef &d : defs) {
        std::vector<EmoteEntry> list;
        std::string err;
        if (!emote_list(s.ctx(), d.kind, d.form, list, err)) {
            problems += format(" %s: %s", d.name, err.c_str());
            continue;
        }
        sizes += format("%s%s %zu", sizes.empty() ? "" : ", ", d.name, list.size());
        if (list.size() != d.want) problems += format(" %s: %zu entries (libsa1's report: %zu)", d.name, list.size(), d.want);
        const float at[3] = {(float)(-6000 + 1500 * (int)(&d - defs)), 1000.0f, 8.0f};
        int32_t id = make(s, d.kind, at, err, d.general);
        run(s, id, 30);
        for (size_t i = 0; i < list.size(); i++) {
            const EmoteEntry &e = list[i];
            std::string res;
            const Character *c = s.get(id);
            if (!c || c->faulted) {
                s.destroy(id);
                id = make(s, d.kind, at, err, d.general);
                run(s, id, 30);
            }
            sa1_status st = emote_play(s.ctx(), id, e.source, e.index, 0);
            if (SA1_FAILED(st)) {
                res = "refused: " + emote_error(s.ctx(), st);
            } else {
                sa1_status t = pair(s, id, 0, 0);
                c = s.get(id);
                if (SA1_FAILED(t) || (c && c->faulted)) {
                    res = "fault";
                } else if (c && c->st.emote_state != SA1_EMOTE_STATE_NONE) {
                    res = "ok";
                } else {
                    res = "not started";
                }
                emote_stop(s.ctx(), id, SA1_EMOTE_STOP_NOW);
                run(s, id, 2);
            }
            total++;
            played += res == "ok";
            if (res != "ok") problems += format(" %s %s %s (%s)", d.name, e.key.c_str(), e.name.c_str(), res.c_str());
            text += format("%s\t%d\t%u\t%zu\t%s\t%s\t%d\t%s\n", d.name, (int)d.kind, (unsigned)d.form, i + 1, e.key.c_str(),
                           e.name.c_str(), e.dup_of >= 0 && (size_t)e.dup_of != i ? e.dup_of + 1 : 0, res.c_str());
        }
        s.destroy(id);
    }
    std::string werr;
    bool wrote = write_file_replace(out_path, text, werr);
    CHECK(problems.empty() && played == total && total > 800 && wrote,
          "%d of %d entries played for a pair and stopped (%s); emote_lists.txt written%s%s", played, total, sizes.c_str(),
          wrote ? "" : (": " + werr).c_str(), problems.substr(0, 600).c_str());
}

#endif  // SA1_API_EMOTE

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
            std::printf("usage: feat_emote_test [--gdi GAME.gdi] [--verbose]\n");
            return 2;
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_emote_test (libsa1 %s)\n", sa1_version_string());
#if !defined(SA1_API_EMOTE)
    CHECK(false, "libsa1.h has no emotes (round 0.9.4a, SA1_API_EMOTE)");
#else
    uint32_t src = 0, idx = 0;
    CHECK(kEmoteApi && emote_parse_key("a75", src, idx) && src == SA1_EMOTE_ROW && idx == 75 &&
              emote_parse_key("x3", src, idx) && src == SA1_EMOTE_EXTRA && idx == 3 && !emote_parse_key("q1", src, idx) &&
              std::string(emote_play_name(SA1_EMOTE_PLAY_LOOP, 0)) == "loop" &&
              std::string(emote_play_name(SA1_EMOTE_PLAY_ONCE, SA1_EMOTE_F_HOLD)) == "hold" &&
              std::string(emote_class_name(SA1_EMOTE_CLASS_POSE)) == "pose" &&
              std::string(emote_class_name(SA1_EMOTE_CLASS_SUPER)) == "super",
          "the emote API is there; keys, play and class names");
    if (gdi.empty()) {
        INFO("no --gdi / SA1_TEST_GDI: the world checks need the disc");
    } else {
        Session s;
        std::string err;
        bool ok = s.init(gdi, err) && flat_floor(s);
        CHECK(ok, "the disc and a flat floor (%s)", err.c_str());
        if (ok) {
            test_play(s);
#if defined(SA1_API_EMOTE_HOLD)
            test_hold(s);
#endif
            test_refusals(s);
            std::string out = join_path(parent_dir(argv[0]).empty() ? std::string(".") : parent_dir(argv[0]),
                                        "emote_lists.txt");
            test_lists(s, out);
        }
        for (const std::string &l : s.take_log()) {
            if (g_verbose || l.find("error") != std::string::npos) std::printf("        %s\n", l.c_str());
        }
        s.shutdown();
    }
#endif
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
