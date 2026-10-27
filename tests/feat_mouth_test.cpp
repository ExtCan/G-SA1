// feat_mouth_test: the mouth table v2 and the player's own mouths in G-SA1's core (round 0.9.4e, feature "faces" 3: sadc
// docs/research/lipsync2_plan.md 4.6 / 4.7 / 5.4 and 6.2 with its review R.2 / R.8; lipsync2_show.md 5.2, 7, 8, 9.1).
// build.py links it like core_test (the core and libsa1) and runs it with --gdi when there is one.
//
//   feat_mouth_test [--gdi GAME.gdi] [--verbose]
//
// Without the disc:
//   V8  table v2 against a SECOND transcription of lipsync2_plan.md 4.6 (with its review R.2 rows) typed below as text (not
//       copied from mouth.cpp): pick() for every face kind x class x s {0.2, 0.6, 1} x size {0, 0.5, 1} x variant {0, 1, 2} x
//       big {0, 1}; no key at or above the kind's count; L entries a = -1 with w = min(s, fv_level); the kinds without a
//       face closed; kTableVersion 2.
//   M1  the parser accepts "AA=7>16@0.45", "AA=7>16@0.45:fixed,AA.loud=16", "OO=6:scales" (= 0>6@1 scaling), "FV=ladder@0.25",
//       "EE=ladder", "" and prints the normal form.
//   M2  it refuses (each with its message): SIL=4, MBP=0, XX=4, AA.soft=4, AA=21 for Sonic (AA=20 accepted), AA=8 for Big
//       (AA=7 accepted), @1.5, @-0.1, @nan, "AA=4>", "AA=4>16", "AA=4,AA=5", 25 items, 513 characters, a kind without a face;
//       (review R.8) "AA=-1", "AA=+4", "AA=007", "AA=4294967300", "@.5", "@1e-1", "@0.12345", " AA=4", "AA=4,", ",AA=4",
//       "AA=4,,EE=4", "AA.normal=4", ":scale"; for Big "AA=4>8@0.5" and "AA=ladder@2".
//   M3  all or nothing.   M4 the variant rule.   M5 "" restores G-SA1's table for every kind.   M6 kinds apart.
//   M7  200 seeded valid specs: re-applying spec_of(spec) gives identical picks (and the same normal form again).
// With the disc, through gsa1::Session on a flat floor (as feat_faces_test.cpp):
//   M8  every key of the Faces page's lists (lipsync2_show.md 6.4 with the review R.2 changes, typed again here as text) and
//       of table v2 is accepted by sa1_character_face_mouth in a world of that kind and shown after the pair; key = count is
//       refused with nothing latched; Big's 8 refused without a fault.
//   M9  the mouth point per face kind: two characters of the kind ticked in lock step, one with the mouth closed (0>K@0),
//       one with the kind's widest mouth-only key K at weight 1 (Sonic 7, Tails 16, Knuckles 7, Amy 16, Big 4); the
//       centroid of the render's vertices that moved more than 0.02 SA1 units (0.08 HU: sa1_render positions are host space,
//       4 HU per unit) between the two, from the drawn position (sa1_render.position) in the character's own frame
//       (forward along sa1_render.yaw, up = host +Z) = mouth::mouth_anchor's constants within 0.5 HU. A control pair with
//       the same mouth on both must move nothing (the worlds are in lock step). A kind where nothing moved fails.
//
// API NOTES (094e-gsa1-mouths; lipsync2_plan.md 5.4 - 5.6 as built; the binding is src/module/bind_faces.cpp, feature
// "faces" 3, its tests tests/feat_faces_binding_test.cpp B1-B8; the Lua data addon/lua/gsa1/feat/sh_mouths.lua, its test
// tests/feat_mouths_test.lua):
//   core (src/core/mouth.hpp, Lua thread only): kTableVersion 2; set_override(kind, spec, err) all or nothing ("" = none);
//     spec_of(kind) the normal form; has_override; row_custom(kind, cls); default_table(kind); table(kind) = the override
//     table while one is set; mouth_anchor(kind, Anchor{forward, up}); has_face; kind_name; parse_mouth; mouth_text; pick's
//     LADDER w = min(s, the entry's w) (G-SA1's f v entries carry fv_level).
//   grammar: spec = "" | item {"," item} (<= 24 items, <= 512 characters, no spaces, one item per SOUND.variant); item =
//     SOUND["."quiet|loud]"="MOUTH; SOUND AA EH EE OH OO SS FV; MOUTH = KEY[":scales"|":fixed"] (= 0>KEY@1) |
//     KEY">"KEY"@"W[":scales"|":fixed"] | "ladder"["@"W]; KEY "0" or [1-9][0-9]? below the kind's count; W = one digit
//     ["." 1-4 digits], 0..1. Normal form: class order, normal / quiet / loud, "%.4g", "k" for 0>k@1, ":scales" only when
//     scaling, "ladder" for ladder@1. A NORMAL item replaces the row's quiet / loud / plain (unless also given); only quiet /
//     loud items keep G-SA1's normal; the player's entries are never swapped by "Bigger mouths".
//   Lua: gsa1.VisemeOverride(kind, spec) -> true | nil, "<item>: <why>", "bad_argument" | nil, "<name> has no face in the
//     game", "unsupported" (kinds 1 / 4 / 6 / 8); the module's close hook clears every override (the addon sets every face
//     kind's line or "" when the module opens: review R.8). gsa1.VisemeTable(kind) + table_version, custom_spec, mouth_at
//     {forward, up} (HU from C.drawPos along C.drawYaw, up +Z, scale 1), rows' custom and (when custom) default.
//     MicDevices' loopback; MicOpen(device [, force]) (a loopback -> "unsupported"); MicLevel -> level, peak, state, blocks;
//     MicVisemeWarmup(step) "ah" "ee" "oo" "oh" "gap" "done" "cancel"; MicVisemeWarmupState -> phase, n_ah, n_ee, n_oo,
//     n_oh, result; MicVisemeVoice -> g, frames, f1, f2, warmed; MicVisemeFeatures -> rel_loc, per, nbr, eep, cat, raw, seq,
//     lowr, zcr; MicVisemeTune("engine", 1 | 2); gsa1.FEATURES.faces = 3.
//   mouth points (M9, measured 2026-10-27): Sonic 3.8 / 29.9, Tails 3.4 / 22.3, Knuckles 6.1 / 25.8, Amy 4.3 / 25.0, Big
//     3.2 / 63.4 HU (forward / up).
//   table v2 against the viseme chart (SADC/build/research/r094e/mouths/proto/built_check.py, parsing mouth.cpp): 34 / 40
//     rule checks (0.9.4c 26); the review's sizing sweep: 0 order breaks with "Bigger mouths" on (18 with it off, all
//     Sonic's eh = ah = key 7 lower than his ee smile: a README limit).
//   contract files next to the binding test: build/<target>/faces2_api.txt (P13) and faces_tables.txt (L8b).
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include "../src/core/mouth.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"
#include "../src/core/viseme.hpp"

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

// ---- V8: the second transcription (lipsync2_plan.md 4.6, review R.2 rows included; typed from the plan) ------------------
static const char *k_plan_v2 =
    "kind 0 keys 21 floor 0.8 cap 0.5 fv 0.25\n"
    "0 AA 7>16@.45 F X | quiet 7>16@.30 F X | loud 7>16@.75 F X | plain 0>7@1 F\n"
    "0 EH 7>16@.20 F X | plain 0>7@1 F\n"
    "0 EE 0>4@1 S\n"
    "0 OH 6>16@.40 F X | quiet 6>7@.30 F | plain 6>7@.30 F\n"
    "0 OO 6>7@.20 F\n"
    "0 SS 5>4@.60 F\n"
    "0 FV L\n"
    "kind 2 keys 20 floor 0 cap 0.667 fv 0.1667\n"
    "2 AA 16>8@.50 F X | quiet 0>16@1 S | loud 0>8@1 F X | plain 0>16@1 S\n"
    "2 EH 0>4@1 S\n"
    "2 EE 0>6@1 S\n"
    "2 OH 0>7@1 S\n"
    "2 OO 0>5@.70 S\n"
    "2 SS 0>6@.60 S\n"
    "2 FV L\n"
    "kind 3 keys 20 floor 0.8 cap 0.667 fv 0.1667\n"
    "3 AA 7>16@.30 F X | quiet 0>7@1 F | loud 7>16@.60 F X | plain 0>7@1 F\n"
    "3 EH 4>7@.50 F\n"
    "3 EE 0>5@1 S\n"
    "3 OH 7>14@.30 F X | quiet 0>7@1 F | plain 0>7@1 F\n"
    "3 OO 0>7@1 F\n"
    "3 SS 0>4@1 S\n"
    "3 FV L\n"
    "kind 5 keys 20 floor 0 cap 1 fv 0.125\n"
    "5 AA 0>8@1 S | loud 8>16@.50 F\n"
    "5 EH 0>8@.80 S\n"
    "5 EE 0>10@1 S | quiet 0>5@1 S\n"
    "5 OH 4>6@.30 F | quiet 0>4@1 S\n"
    "5 OO 0>6@.60 S\n"
    "5 SS 0>10@.50 S\n"
    "5 FV L\n"
    "kind 7 keys 8 floor 0 cap 1 fv 0.125\n"
    "7 AA 0>4@1 S | loud 0>5@1 S\n"
    "7 EH 0>4@.55 S\n"
    "7 EE 0>4@.35 S\n"
    "7 OH 0>4@.70 S\n"
    "7 OO 0>4@.30 S\n"
    "7 SS 0>4@.25 S\n"
    "7 FV L\n";

struct TE {                 // a transcribed entry
    bool present = false;
    int a = 0, b = 0;
    float w = 0.0f;
    char how = 'C';         // C closed, S, F, L
    bool x = false;
};
struct TK {                 // a transcribed kind
    int keys = 0;
    float floor = 0, cap = 0, fv = 0;
    TE e[9][4];             // class x (normal, quiet, loud, plain)
    bool ok = false;
};
static std::map<int, TK> g_plan;

static bool parse_te(const std::string &s, TE &e)
{
    std::istringstream in(s);
    std::string mouth, how, x;
    in >> mouth >> how >> x;
    if (mouth == "L") {
        e.present = true;
        e.how = 'L';
        e.a = e.b = -1;
        return true;
    }
    int a = 0, b = 0;
    char w[32] = {0};
    if (std::sscanf(mouth.c_str(), "%d>%d@%31s", &a, &b, w) != 3 || (how != "S" && how != "F")) {
        return false;
    }
    e.present = true;
    e.a = a;
    e.b = b;
    e.w = std::strtof(w, nullptr);
    e.how = how[0];
    e.x = x == "X";
    return true;
}

static bool load_plan()
{
    std::istringstream in(k_plan_v2);
    std::string line;
    int bad = 0;
    while (std::getline(in, line)) {
        if (line.compare(0, 5, "kind ") == 0) {
            TK t;
            int kind = 0;
            if (std::sscanf(line.c_str(), "kind %d keys %d floor %f cap %f fv %f", &kind, &t.keys, &t.floor, &t.cap, &t.fv) != 5) {
                bad++;
                continue;
            }
            t.ok = true;
            for (int c = 0; c < 2; c++) {
                t.e[c][0].present = true;    // SIL, MBP closed
            }
            g_plan[kind] = t;
            continue;
        }
        int kind = -1;
        char cls_s[8] = {0};
        if (std::sscanf(line.c_str(), "%d %7s", &kind, cls_s) != 2 || !g_plan.count(kind)) {
            bad++;
            continue;
        }
        int cls = -1;
        for (int c = 0; c < 9; c++) {
            if (std::string(cls_s) == viseme::name(c)) cls = c;
        }
        if (cls < 2) {
            bad++;
            continue;
        }
        std::string rest = line.substr(line.find(cls_s) + std::strlen(cls_s));
        std::vector<std::string> parts;
        size_t p = 0;
        while (true) {
            size_t bar = rest.find('|', p);
            parts.push_back(rest.substr(p, bar == std::string::npos ? std::string::npos : bar - p));
            if (bar == std::string::npos) break;
            p = bar + 1;
        }
        for (size_t i = 0; i < parts.size(); i++) {
            std::istringstream pi(parts[i]);
            std::string first;
            pi >> first;
            int v = 0;
            std::string body = parts[i];
            if (i > 0) {
                v = first == "quiet" ? 1 : first == "loud" ? 2 : first == "plain" ? 3 : -1;
                if (v < 0) {
                    bad++;
                    continue;
                }
                body = parts[i].substr(parts[i].find(first) + first.size());
            }
            if (!parse_te(body, g_plan[kind].e[cls][v])) bad++;
        }
    }
    return bad == 0 && g_plan.size() == 5;
}

// the rule of phoneme_plan.md 4.3 on the transcription (written again here, not mouth.cpp's code)
static void plan_pick(int kind, int cls, float s, float size, int variant, bool big, int &a, int &b, float &w)
{
    a = b = 0;
    w = 0.0f;
    auto it = g_plan.find(kind);
    if (it == g_plan.end() || cls < 0 || cls > 8) return;
    const TK &t = it->second;
    const TE *r = t.e[cls];
    const TE *e = &r[0];
    if (variant == 1 && r[1].present) e = &r[1];
    else if (variant == 2 && r[2].present) e = &r[2];
    if (e->x && !big) {
        if (r[3].present) e = &r[3];
        else if (r[1].present) e = &r[1];
        else if (!r[0].x) e = &r[0];
    }
    float sc = s < 0 ? 0 : (s > 1 ? 1 : s), sz = size < 0 ? 0 : (size > 1 ? 1 : size);
    if (e->how == 'S') {
        float f = 1.0f - sz;
        if (f < t.floor) f = t.floor;
        a = e->a;
        b = e->b;
        w = e->w * (f + (1.0f - f) * sc);
        w = w > 1 ? 1 : (w < 0 ? 0 : w);
    } else if (e->how == 'F') {
        a = e->a;
        b = e->b;
        w = e->w > 1 ? 1 : e->w;
    } else if (e->how == 'L') {
        a = b = -1;
        w = sc < t.fv ? sc : t.fv;
    }
}

// pick() equals the transcription for every case; returns the count of cases that differ (and the first in `first`)
static int compare_all(int &cases, std::string &first, int keyed_out[2])
{
    int diff = 0;
    cases = 0;
    keyed_out[0] = keyed_out[1] = 0;
    for (int kind = 0; kind < 9; kind++) {
        for (int cls = 0; cls < 9; cls++) {
            for (float s : {0.2f, 0.6f, 1.0f}) {
                for (float size : {0.0f, 0.5f, 1.0f}) {
                    for (int variant = 0; variant < 3; variant++) {
                        for (int big = 0; big < 2; big++) {
                            int a, b, pa, pb;
                            float w, pw;
                            mouth::pick(kind, cls, s, size, variant, big != 0, a, b, w);
                            plan_pick(kind, cls, s, size, variant, big != 0, pa, pb, pw);
                            cases++;
                            const mouth::Table *t = mouth::table(kind);
                            if (t && a >= 0) {
                                keyed_out[0]++;
                                keyed_out[1] += a < t->keys && b < t->keys;
                            }
                            if (a != pa || b != pb || std::fabs(w - pw) > 1e-6f) {
                                if (!diff) {
                                    first = format("kind %d %s s %.1f size %.1f variant %d big %d: %d>%d@%.4f (plan %d>%d@%.4f)",
                                                   kind, viseme::name(cls), s, size, variant, big, a, b, w, pa, pb, pw);
                                }
                                diff++;
                            }
                        }
                    }
                }
            }
        }
    }
    return diff;
}

static void test_v8()
{
    std::printf("V8 table v2 (lipsync2_plan.md 4.6 with the review R.2 rows):\n");
    bool loaded = load_plan();
    CHECK(loaded, "the transcription parses: 5 kinds, every row");
    int heads = 0;
    for (auto &kv : g_plan) {
        const mouth::Table *t = mouth::default_table(kv.first);
        heads += t && t->keys == kv.second.keys && std::fabs(t->floor - kv.second.floor) < 1e-6f &&
                 std::fabs(t->ladder_cap - kv.second.cap) < 1e-6f && std::fabs(t->fv_level - kv.second.fv) < 1e-6f &&
                 t->kind == kv.first;
    }
    CHECK(heads == 5 && mouth::kTableVersion == 2,
          "every kind's keys / floor / ladder cap / fv_level equal the plan's (%d of 5); kTableVersion %d", heads,
          mouth::kTableVersion);
    int cases = 0, keyed[2];
    std::string first;
    int diff = compare_all(cases, first, keyed);
    CHECK(diff == 0 && cases == 9 * 9 * 3 * 3 * 3 * 2, "pick() equals the plan's table in every case: %d of %d differ%s%s",
          diff, cases, diff ? ": " : "", first.c_str());
    CHECK(keyed[0] > 0 && keyed[1] == keyed[0], "no key at or above the kind's count (%d of %d keyed picks below it)", keyed[1],
          keyed[0]);
    int lad = 0, lad_ok = 0, faceless = 0;
    for (int kind : {0, 2, 3, 5, 7}) {
        const mouth::Table *t = mouth::default_table(kind);
        for (float s : {0.05f, 0.2f, 0.6f, 1.0f}) {
            int a, b;
            float w;
            mouth::pick(kind, viseme::FV, s, 0.5f, 0, true, a, b, w);
            lad++;
            lad_ok += a == -1 && b == -1 && std::fabs(w - std::min(s, t->fv_level)) < 1e-6f;
        }
    }
    for (int kind : {1, 4, 6, 8, 9, -1}) {
        for (int cls = 0; cls < 9; cls++) {
            int a = 9, b = 9;
            float w = 9;
            mouth::pick(kind, cls, 1.0f, 1.0f, 0, true, a, b, w);
            faceless += a == 0 && b == 0 && w == 0.0f;
        }
    }
    CHECK(lad_ok == lad && faceless == 54,
          "f v th: a = b = -1 and w = min(s, fv_level) (%d of %d); Eggman, Tikal, E-102, Super Sonic and bad kinds closed "
          "(%d of 54)", lad_ok, lad, faceless);
    // the 14 rows that changed against 0.9.4c, by sight (Sonic's ah is his open mouth, not the grin)
    int a, b;
    float w;
    mouth::pick(0, viseme::AA, 1.0f, 0.5f, 0, true, a, b, w);
    std::string sa = format("%d>%d@%.2f", a, b, w);
    mouth::pick(0, viseme::AA, 0.3f, 0.5f, 1, true, a, b, w);
    std::string sq = format("%d>%d@%.2f", a, b, w);
    mouth::pick(5, viseme::EH, 0.95f, 0.5f, 0, true, a, b, w);
    std::string ae = format("%d>%d@%.2f", a, b, w);
    CHECK(sa == "7>16@0.45" && sq == "7>16@0.30" && ae == "0>8@0.78",
          "Sonic's ah %s (his open mouth with fangs, not the grin 4>16), quiet ah %s (review R.2); Amy's eh at s 0.95 %s "
          "(0>8@.80 scaling: review R.2)", sa.c_str(), sq.c_str(), ae.c_str());
}

// ---- M1 - M7: the player's mouths -------------------------------------------------------------------------------------------
struct Pick {
    int a, b;
    float w;
    bool operator==(const Pick &o) const { return a == o.a && b == o.b && w == o.w; }
};
static std::vector<Pick> picks_of(int kind)
{
    std::vector<Pick> out;
    for (int cls = 0; cls < 9; cls++)
        for (float s : {0.2f, 0.6f, 1.0f})
            for (float size : {0.0f, 0.5f, 1.0f})
                for (int variant = 0; variant < 3; variant++)
                    for (int big = 0; big < 2; big++) {
                        Pick p;
                        mouth::pick(kind, cls, s, size, variant, big != 0, p.a, p.b, p.w);
                        out.push_back(p);
                    }
    return out;
}

static std::string pick_s(int kind, int cls, int variant, bool big, float s = 1.0f)
{
    int a, b;
    float w;
    mouth::pick(kind, cls, s, 0.5f, variant, big, a, b, w);
    return format("%d>%d@%.4g", a, b, w);
}

static uint32_t g_rng = 12345u;
static uint32_t rnd(uint32_t n)
{
    g_rng = g_rng * 1664525u + 1013904223u;
    return (g_rng >> 8) % n;
}

// a random valid spec for a face kind (any grammar form; the items in a random order)
static std::string random_spec(int kind)
{
    static const char *snd[7] = {"AA", "EH", "EE", "OH", "OO", "SS", "FV"};
    static const char *var[3] = {"", ".quiet", ".loud"};
    int keys = mouth::default_table(kind)->keys;
    std::vector<std::string> items;
    for (int c = 0; c < 7; c++) {
        for (int v = 0; v < 3; v++) {
            if (rnd(4) != 0) continue;
            std::string m;
            switch (rnd(6)) {
            case 0: m = std::to_string(rnd(keys)); break;
            case 1: m = format("0>%u@1", rnd(keys)); break;
            case 2: {
                uint32_t dec = rnd(5);
                std::string wt = rnd(9) == 0 ? "1" : (dec == 0 ? "0" : "0.");
                for (uint32_t d = 0; d < dec && wt != "1"; d++) wt += (char)('0' + rnd(10));
                m = format("%u>%u@%s", rnd(keys), rnd(keys), wt.c_str());
                break;
            }
            case 3: m = rnd(2) ? "ladder" : format("ladder@0.%u", 1 + rnd(9999)); break;
            case 4: m = format("%u>%u@0.%02u:scales", rnd(keys), rnd(keys), rnd(100)); break;
            default: m = format("%u:%s", rnd(keys), rnd(2) ? "fixed" : "scales"); break;
            }
            items.push_back(std::string(snd[c]) + var[v] + "=" + m);
        }
    }
    for (size_t i = items.size(); i > 1; i--) std::swap(items[i - 1], items[rnd((uint32_t)i)]);
    std::string s;
    for (size_t i = 0; i < items.size(); i++) s += (i ? "," : "") + items[i];
    return s;
}

static void test_overrides()
{
    std::printf("M1 - M7 the player's mouths (set_override):\n");
    std::string err;
    // M1
    struct Ok {
        int kind;
        const char *spec, *normal;
    } oks[] = {{0, "AA=7>16@0.45", "AA=7>16@0.45"},
               {0, "AA=7>16@0.45:fixed,AA.loud=16", "AA=7>16@0.45,AA.loud=16"},
               {0, "OO=6:scales", "OO=6:scales"},
               {0, "FV=ladder@0.25", "FV=ladder@0.25"},
               {0, "EE=ladder", "EE=ladder"},
               {0, "", ""},
               {0, "EE=0>17@0.8:scales,AA.loud=7>16@0.7", "AA.loud=7>16@0.7,EE=0>17@0.8:scales"},
               {0, "AA=20", "AA=20"},
               {7, "AA=7", "AA=7"},
               {2, "OO=0>5@1.0,SS.quiet=ladder@1", "OO=5,SS.quiet=ladder"}};
    int m1 = 0;
    std::string m1s;
    for (const Ok &o : oks) {
        bool r = mouth::set_override(o.kind, o.spec, err);
        std::string n = mouth::spec_of(o.kind);
        m1 += r && n == o.normal && mouth::has_override(o.kind) == (o.spec[0] != 0);
        if (!(r && n == o.normal)) m1s += format(" [%s -> %s %s]", o.spec, r ? n.c_str() : "refused:", err.c_str());
    }
    int a, b;
    float w;
    mouth::set_override(0, "OO=6:scales", err);
    mouth::pick(0, viseme::OO, 0.5f, 0.5f, 0, true, a, b, w);
    bool oo_scales = a == 0 && b == 6 && std::fabs(w - 1.0f * (0.8f + 0.2f * 0.5f)) < 1e-6f;   // Sonic's floor 0.8
    mouth::set_override(0, "FV=ladder@0.25,EE=ladder", err);
    mouth::pick(0, viseme::FV, 0.9f, 0.5f, 0, true, a, b, w);
    bool fv_cap = a == -1 && b == -1 && std::fabs(w - 0.25f) < 1e-6f;
    mouth::pick(0, viseme::EE, 0.9f, 0.5f, 0, true, a, b, w);
    bool ee_lad = a == -1 && std::fabs(w - 0.9f) < 1e-6f;
    CHECK(m1 == (int)(sizeof oks / sizeof oks[0]) && oo_scales && fv_cap && ee_lad,
          "M1 accepted with the normal form printed back (%d of %d)%s; \"OO=6:scales\" = 0>6@1 scaling (s 0.5 -> 0.90); "
          "FV=ladder@0.25 caps at 0.25, EE=ladder at the loudness", m1, (int)(sizeof oks / sizeof oks[0]), m1s.c_str());

    // M2
    std::string i25, s513 = "AA=7>16@0.45";
    static const char *const snd7[7] = {"AA", "EH", "EE", "OH", "OO", "SS", "FV"};
    static const char *const var4[4] = {"", ".quiet", ".loud", ".quiet"};
    for (int i = 0; i < 25; i++) i25 += format("%s%s%s=4", i ? "," : "", snd7[i % 7], var4[i / 7]);
    while (s513.size() < 513) s513 += ",";
    struct Bad {
        int kind;
        std::string spec;
    };
    std::vector<Bad> bads = {{0, "SIL=4"}, {0, "MBP=0"}, {0, "XX=4"}, {0, "AA.soft=4"}, {0, "AA=21"}, {7, "AA=8"},
                             {0, "AA=4>16@1.5"}, {0, "AA=4>16@-0.1"}, {0, "AA=4>16@nan"}, {0, "AA=4>"}, {0, "AA=4>16"},
                             {0, "AA=4,AA=5"}, {0, i25}, {0, s513}, {6, "AA=4"},
                             // review R.8
                             {0, "AA=-1"}, {0, "AA=+4"}, {0, "AA=007"}, {0, "AA=4294967300"}, {0, "AA=7>16@.5"},
                             {0, "AA=7>16@1e-1"}, {0, "AA=7>16@0.12345"}, {0, " AA=4"}, {0, "AA=4,"}, {0, ",AA=4"},
                             {0, "AA=4,,EE=4"}, {0, "AA.normal=4"}, {0, "AA=7>16@0.5:scale"}, {7, "AA=4>8@0.5"},
                             {7, "AA=ladder@2"}};
    int refused = 0;
    std::string msgs;
    for (const Bad &x : bads) {
        mouth::set_override(x.kind, "", err);
        bool r = mouth::set_override(x.kind, x.spec.c_str(), err);
        refused += !r && !err.empty() && !mouth::has_override(x.kind);
        if (g_verbose || r) {
            msgs += format("\n        %s%-24.24s -> %s", r ? "ACCEPTED " : "", x.spec.c_str(), err.c_str());
        }
    }
    bool s20 = mouth::set_override(0, "AA=20", err), b7 = mouth::set_override(7, "AA=7", err);
    mouth::set_override(0, "AA=21", err);
    std::string e21 = err;
    mouth::set_override(7, "AA=8", err);
    std::string e8 = err;
    mouth::set_override(0, "AA=4294967300", err);
    std::string ebig = err;
    mouth::set_override(0, "", err);
    mouth::set_override(7, "", err);
    CHECK(refused == (int)bads.size() && s20 && b7 && e21 == "AA=21: key 21 is not one of Sonic's 21 face keys (0-20)" &&
              e8 == "AA=8: key 8 is not one of Big's 8 face keys (0-7)",
          "M2 refused, each with its message (%d of %zu): \"%s\"; \"%s\"; \"%s\"; AA=20 for Sonic and AA=7 for Big accepted%s",
          refused, bads.size(), e21.c_str(), e8.c_str(), ebig.c_str(), msgs.c_str());

    // M3 all or nothing
    mouth::set_override(0, "AA=7", err);
    bool m3r = mouth::set_override(0, "AA=4,EH=99", err);
    std::string m3e = err;
    CHECK(!m3r && pick_s(0, viseme::AA, 0, true) == "0>7@1" && mouth::spec_of(0) == "AA=7",
          "M3 \"AA=7\" then \"AA=4,EH=99\" refused (%s): ah still 0>7@1 (%s), the override still \"AA=7\"", m3e.c_str(),
          pick_s(0, viseme::AA, 0, true).c_str());

    // M4 the variant rule
    mouth::set_override(0, "AA=9>10@0.5", err);
    std::string v0 = pick_s(0, viseme::AA, 0, true), v1 = pick_s(0, viseme::AA, 1, true), v2 = pick_s(0, viseme::AA, 2, true),
                v0off = pick_s(0, viseme::AA, 0, false), v1off = pick_s(0, viseme::AA, 1, false);
    bool c1 = mouth::row_custom(0, viseme::AA) && !mouth::row_custom(0, viseme::EH);
    mouth::set_override(0, "AA.loud=16", err);
    std::string l0 = pick_s(0, viseme::AA, 0, true), l2 = pick_s(0, viseme::AA, 2, true), l2off = pick_s(0, viseme::AA, 2, false),
                l0off = pick_s(0, viseme::AA, 0, false), l1 = pick_s(0, viseme::AA, 1, true);
    const mouth::Table *t0 = mouth::table(0);
    bool exprs = t0 && t0->rows[viseme::AA].loud.expression == 0 && t0->rows[viseme::AA].loud.present;
    CHECK(v0 == "9>10@0.5" && v1 == v0 && v2 == v0 && v0off == v0 && v1off == v0 && c1 && l0 == "7>16@0.45" && l2 == "0>16@1" &&
              l2off == "0>16@1" && l0off == "0>7@1" && l1 == "7>16@0.3" && exprs,
          "M4 a normal override replaces the row (variants 1 / 2 and big off give yours: %s %s %s %s %s; the expression keys "
          "9 / 10 stay yours); only AA.loud=16 keeps G-SA1's normal %s (big off: its plain %s) and quiet %s, gives %s for "
          "loud (big off too: %s)", v0.c_str(), v1.c_str(), v2.c_str(), v0off.c_str(), v1off.c_str(), l0.c_str(), l0off.c_str(),
          l1.c_str(), l2.c_str(), l2off.c_str());

    // M5 reset, M6 kinds apart (M1 left Tails' "OO=5,..." set: G-SA1's table first)
    for (int k : {0, 2, 3, 5, 7}) mouth::set_override(k, "", err);
    std::vector<Pick> tails0 = picks_of(2);
    for (int k : {0, 2, 3, 5, 7}) mouth::set_override(k, "AA=4,EH=5:scales,OO.quiet=ladder@0.5", err);
    mouth::set_override(0, "AA=1,EE=3", err);
    bool m6 = picks_of(2) != tails0;   // Tails has his own override now
    mouth::set_override(2, "", err);
    std::vector<Pick> tails_def = picks_of(2);
    mouth::set_override(0, "SS=2>3@0.25:scales", err);
    bool m6b = picks_of(2) == tails_def && tails_def == tails0;
    for (int k : {0, 2, 3, 5, 7}) mouth::set_override(k, "", err);
    int cases = 0, keyed[2];
    std::string first;
    int diff = compare_all(cases, first, keyed);
    int none = 0;
    for (int k : {0, 2, 3, 5, 7}) none += !mouth::has_override(k) && mouth::spec_of(k).empty() && mouth::table(k) == mouth::default_table(k);
    CHECK(diff == 0 && none == 5, "M5 set_override(k, \"\") for every kind: every pick equals V8's table again (%d of %d differ), "
          "no override left (%d of 5)", diff, cases, none);
    CHECK(m6 && m6b, "M6 Sonic's override leaves Tails' picks alone (Tails' own override changed them; after his reset and "
          "another Sonic override they equal G-SA1's)");

    // M7 round trip
    int same = 0, norm_same = 0, applied = 0;
    std::string why7;
    for (int i = 0; i < 200; i++) {
        static const int face_kinds[5] = {0, 2, 3, 5, 7};
        int kind = face_kinds[i % 5];
        std::string spec = random_spec(kind);
        if (!mouth::set_override(kind, spec.c_str(), err)) {
            if (why7.empty()) why7 = spec + ": " + err;
            continue;
        }
        applied++;
        std::vector<Pick> p1 = picks_of(kind);
        std::string n1 = mouth::spec_of(kind);
        mouth::set_override(kind, "", err);
        bool r2 = mouth::set_override(kind, n1.c_str(), err);
        std::vector<Pick> p2 = picks_of(kind);
        same += r2 && p1 == p2;
        norm_same += r2 && mouth::spec_of(kind) == n1;
        mouth::set_override(kind, "", err);
    }
    CHECK(applied == 200 && same == 200 && norm_same == 200,
          "M7 200 seeded valid specs (every grammar form): accepted %d, re-applying spec_of gives identical picks %d and the "
          "same normal form %d%s%s", applied, same, norm_same, why7.empty() ? "" : "; first refused: ", why7.c_str());
}

// ---- M8 / M9 with the disc ----------------------------------------------------------------------------------------------------
#if defined(SA1_API_FACE)

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

static bool pair(Session &s, int32_t id)
{
    std::vector<sa1_event> ev;
    sa1_status st = s.tick(id, 0.0f, 0.0f, 0.0f, 0u, 1.0f / 30.0f);
    s.poll_events(ev);
    sa1_status rs = s.render(id, 1.0f);
    return st == SA1_OK && rs == SA1_OK;
}

// the Faces page's lists (lipsync2_show.md 6.4 with lipsync2_plan.md's review R.2 changes), typed again as text: the keys
// of every "a>b@w" / "k" entry (voice / slit are the ladder: no key)
static const char *k_lists[5][2] = {
    {"0", "0 5 4 7 6 7>16 7>16 7>16 7>16 4>16 6>16 6>7 6>7 5>4 5>4 0>4 16 17 11 14 8 9 10"},
    {"2", "0 4 5 6 7 16 18 16>8 8 0>5 0>6 0>4 17 12 9"},
    {"3", "0 6 4 5 7 4>7 7>16 7>16 7>14 18 19 0>4 8 16 17 14 9 10 12"},
    {"5", "0 7 5 4 6 8 10 16 19 7>8 0>8 8>16 4>6 0>6 0>10 0>7 9 14 17"},
    {"7", "0 0>4 4 5"},
};

static void test_keys_disc(Session &s)
{
    std::printf("M8 every listed key and every table key accepted by a world of the kind (the disc):\n");
    int total = 0, accepted = 0, shown = 0, refused = 0, faults = 0, kinds = 0;
    std::string failed;
    for (const auto &kl : k_lists) {
        int kind = std::atoi(kl[0]);
        std::string err;
        const float at[3] = {0.0f, 0.0f, 8.0f};
        int32_t id = s.create(kind, at, 0.0f, err);
        const Character *c = id > 0 ? s.get(id) : nullptr;
        if (!c) {
            failed += format(" kind %d not created (%s)", kind, err.c_str());
            continue;
        }
        kinds++;
        for (int p = 0; p < 4; p++) pair(s, id);
        std::vector<std::pair<int, int>> keys;
        std::istringstream in(kl[1]);
        std::string tok;
        while (in >> tok) {
            int a = 0, b = 0;
            if (tok.find('>') != std::string::npos) std::sscanf(tok.c_str(), "%d>%d", &a, &b);
            else b = std::atoi(tok.c_str());
            keys.push_back({a, b});
        }
        // every key of table v2 (all rows and variants)
        const mouth::Table *t = mouth::default_table(kind);
        for (int cls = 0; cls < 9 && t; cls++) {
            for (const mouth::Entry *e : {&t->rows[cls].normal, &t->rows[cls].quiet, &t->rows[cls].loud, &t->rows[cls].plain}) {
                if (e->present && e->how != mouth::LADDER && e->how != mouth::CLOSED) keys.push_back({e->a, e->b});
            }
        }
        for (const auto &k : keys) {
            total++;
            sa1_status st = sa1_character_face_mouth(s.ctx(), id, (uint32_t)k.first, (uint32_t)k.second, 0.5f, 0u);
            accepted += st == SA1_OK;
            pair(s, id);
            bool ok = c->st.face_from == k.first && c->st.face_to == k.second;
            shown += ok;
            if (st != SA1_OK || !ok) failed += format(" %d:%d>%d", kind, k.first, k.second);
        }
        // key = count: refused, nothing latched (a good mouth sent first stays the one shown)
        sa1_character_face_mouth(s.ctx(), id, 0u, 4u, 0.6f, 0u);
        sa1_status bad = sa1_character_face_mouth(s.ctx(), id, 0u, (uint32_t)t->keys, 0.5f, 0u);
        bool pr = pair(s, id);
        refused += bad == SA1_ERR_INVALID_ARGUMENT && pr && c->st.face_from == 0 && c->st.face_to == 4 && !c->faulted;
        faults += c->faulted;
        sa1_character_face_mouth(s.ctx(), id, 0u, 0u, -1.0f, 0u);
        pair(s, id);
        s.destroy(id);
    }
    CHECK(kinds == 5 && accepted == total && shown == total && refused == 5 && faults == 0,
          "M8 %d keys of the lists and of table v2 over the 5 face kinds: accepted %d, shown after the pair %d; key = the "
          "kind's count refused with the previous mouth still shown (nothing latched) in %d of 5 kinds (Big's 8 without a "
          "fault)%s", total, accepted, shown, refused, failed.c_str());
}

// M9: the mouth point
static void test_anchor(Session &s)
{
    std::printf("M9 the mouth point per face kind (the close-up's camera target):\n");
    struct K {
        int kind, key;
    } ks[] = {{0, 7}, {2, 16}, {3, 7}, {5, 16}, {7, 4}};
    std::string got;
    int good = 0, control_still = 0;
    for (const K &k : ks) {
        std::string err;
        const float at[3] = {0.0f, 0.0f, 8.0f};
        int32_t ia = s.create(k.kind, at, 0.0f, err);
        int32_t ib = s.create(k.kind, at, 0.0f, err);
        const Character *ca = ia > 0 ? s.get(ia) : nullptr, *cb = ib > 0 ? s.get(ib) : nullptr;
        if (!ca || !cb) {
            got += format(" kind %d: not created (%s)", k.kind, err.c_str());
            if (ia > 0) s.destroy(ia);
            if (ib > 0) s.destroy(ib);
            continue;
        }
        // stand still, both with the event head shown and the mouth closed, then the control: the same mouth on both
        size_t moved_control = 0;
        for (int p = 0; p < 12; p++) {
            sa1_character_face_mouth(s.ctx(), ia, 0u, (uint32_t)k.key, 0.0f, 0u);
            sa1_character_face_mouth(s.ctx(), ib, 0u, (uint32_t)k.key, 0.0f, 0u);
            pair(s, ia);
            pair(s, ib);
        }
        bool same_n = ca->r_tpos.size() == cb->r_tpos.size() && !ca->r_tpos.empty();
        for (size_t i = 0; same_n && i + 2 < ca->r_tpos.size(); i += 3) {
            float d = std::sqrt((ca->r_tpos[i] - cb->r_tpos[i]) * (ca->r_tpos[i] - cb->r_tpos[i]) +
                                (ca->r_tpos[i + 1] - cb->r_tpos[i + 1]) * (ca->r_tpos[i + 1] - cb->r_tpos[i + 1]) +
                                (ca->r_tpos[i + 2] - cb->r_tpos[i + 2]) * (ca->r_tpos[i + 2] - cb->r_tpos[i + 2]));
            moved_control += d > 0.08f;
        }
        control_still += same_n && moved_control == 0;
        // two pairs: A closed, B the widest mouth-only key at weight 1
        for (int p = 0; p < 2; p++) {
            sa1_character_face_mouth(s.ctx(), ia, 0u, (uint32_t)k.key, 0.0f, 0u);
            sa1_character_face_mouth(s.ctx(), ib, 0u, (uint32_t)k.key, 1.0f, 0u);
            pair(s, ia);
            pair(s, ib);
        }
        double cx = 0, cy = 0, cz = 0;
        size_t n = 0;
        // diagnostics (--verbose): the largest move, the move-weighted centroid and the centroid of the corners that moved
        // at least 30 % of the largest move
        double dmax = 0, wsum = 0, wx = 0, wy = 0, wz = 0, hx = 0, hy = 0, hz = 0;
        size_t nh = 0;
        if (ca->r_tpos.size() == cb->r_tpos.size()) {
            for (size_t i = 0; i + 2 < ca->r_tpos.size(); i += 3) {
                double dx = cb->r_tpos[i] - ca->r_tpos[i], dy = cb->r_tpos[i + 1] - ca->r_tpos[i + 1],
                       dz = cb->r_tpos[i + 2] - ca->r_tpos[i + 2];
                dmax = std::max(dmax, std::sqrt(dx * dx + dy * dy + dz * dz));
            }
            for (size_t i = 0; i + 2 < ca->r_tpos.size(); i += 3) {
                double dx = cb->r_tpos[i] - ca->r_tpos[i], dy = cb->r_tpos[i + 1] - ca->r_tpos[i + 1],
                       dz = cb->r_tpos[i + 2] - ca->r_tpos[i + 2];
                double d = std::sqrt(dx * dx + dy * dy + dz * dz);
                double mx = 0.5 * (ca->r_tpos[i] + cb->r_tpos[i]), my = 0.5 * (ca->r_tpos[i + 1] + cb->r_tpos[i + 1]),
                       mz = 0.5 * (ca->r_tpos[i + 2] + cb->r_tpos[i + 2]);
                if (d > 0.08) {
                    cx += mx;
                    cy += my;
                    cz += mz;
                    n++;
                    wx += d * mx;
                    wy += d * my;
                    wz += d * mz;
                    wsum += d;
                }
                if (d >= 0.3 * dmax && dmax > 0) {
                    hx += mx;
                    hy += my;
                    hz += mz;
                    nh++;
                }
            }
        }
        if (g_verbose && n > 0) {
            double yaw = ca->r_yaw, c = std::cos(yaw), sn = std::sin(yaw);
            auto frame = [&](double x, double y, double z, const char *what) {
                double rx = x - ca->r_pos[0], ry = y - ca->r_pos[1], rz = z - ca->r_pos[2];
                std::printf("        %s %s: forward %.2f up %.2f side %.2f\n", mouth::kind_name(k.kind), what,
                            rx * c + ry * sn, rz, -rx * sn + ry * c);
            };
            std::printf("        %s: the largest move %.2f HU; %zu corners over 0.08 HU, %zu over 30 %% of the largest\n",
                        mouth::kind_name(k.kind), dmax, n, nh);
            frame(wx / wsum, wy / wsum, wz / wsum, "move-weighted centroid");
            if (nh) frame(hx / (double)nh, hy / (double)nh, hz / (double)nh, "centroid of the corners over 30 %");
        }
        mouth::Anchor want;
        bool has = mouth::mouth_anchor(k.kind, want);
        if (n > 0) {
            cx /= (double)n;
            cy /= (double)n;
            cz /= (double)n;
            double rx = cx - ca->r_pos[0], ry = cy - ca->r_pos[1], rz = cz - ca->r_pos[2];
            double yaw = ca->r_yaw;
            double fwd = rx * std::cos(yaw) + ry * std::sin(yaw), side = -rx * std::sin(yaw) + ry * std::cos(yaw);
            bool ok = has && std::fabs(fwd - want.forward) <= 0.5 && std::fabs(rz - want.up) <= 0.5;
            good += ok;
            got += format("%s %s: forward %.2f up %.2f (side %.2f; %zu of %zu corners moved; mouth.cpp %.1f / %.1f)%s",
                          got.empty() ? "" : ";", mouth::kind_name(k.kind), fwd, rz, side, n, ca->r_tpos.size() / 3,
                          want.forward, want.up, ok ? "" : " DIFFERS");
        } else {
            got += format("%s %s: nothing moved (%zu / %zu corners)", got.empty() ? "" : ";", mouth::kind_name(k.kind),
                          ca->r_tpos.size() / 3, cb->r_tpos.size() / 3);
        }
        sa1_character_face_mouth(s.ctx(), ia, 0u, 0u, -1.0f, 0u);
        sa1_character_face_mouth(s.ctx(), ib, 0u, 0u, -1.0f, 0u);
        s.destroy(ia);
        s.destroy(ib);
    }
    mouth::Anchor none;
    bool faceless = !mouth::mouth_anchor(6, none) && !mouth::mouth_anchor(8, none) && !mouth::mouth_anchor(4, none);
    CHECK(control_still == 5, "M9 control: two worlds of the kind in lock step with the same closed mouth move no vertex "
          "(%d of 5 kinds)", control_still);
    CHECK(good == 5 && faceless, "M9 the mouth point (HU from sa1_render.position, the character's own frame) within 0.5 HU of "
          "mouth.cpp's constants (%d of 5):%s; E-102, Super Sonic and Tikal have none", good, got.c_str());
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
            std::printf("usage: feat_mouth_test [--gdi GAME.gdi] [--verbose]\n");
            return 2;
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_mouth_test (the mouth table v2 and the player's mouths)\n");
    test_v8();
    test_overrides();
#if defined(SA1_API_FACE)
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: M8 / M9 need the disc\n");
    } else {
        Session s;
        std::string err;
        bool ok = s.init(gdi, err);
        std::vector<sa1_collision_tri> floor;
        floor_tiles(floor, -4096.0f, 4096.0f, -2048.0f, 2048.0f, 0.0f, 1024.0f);
        ok = ok && s.set_world(floor, err);
        CHECK(ok, "the disc and a flat floor (%s)", err.c_str());
        if (ok) {
            test_keys_disc(s);
            test_anchor(s);
        }
        s.shutdown();
    }
#else
    std::printf("  info  libsa1.h has no faces section: M8 / M9 skipped\n");
#endif
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
