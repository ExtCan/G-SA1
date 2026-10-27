// feat_emote_binding_test: the emote feature through the module's Lua functions (round 0.9.4a: sadc
// docs/research/faces_wheel_plan.md 5.6 / 6.5) - the feature "emote" (src/module/bind_emote.cpp: EmoteList, Emote,
// EmoteStop, EmoteState, gsa1.EMOTE; the core part src/core/emote.cpp). Linked like binding_test (the module's objects,
// libsa1, the mock Lua stack of tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi.
//
//   feat_emote_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
// Without the disc: gsa1.FEATURES.emote = 1, the functions registered, gsa1.EMOTE = libsa1's macros (LOOP is G-SA1's own),
// EmoteList before the disc -> nil, "not_ready"; Emote with an unknown key -> nil, "unknown ...", "bad_argument" (the key is
// checked before the character); with no character -> nil, message, "not_found"; EmoteState of no character -> nil; bad
// flags / how -> "bad_argument"; no Lua error and an empty stack after every call.
// With the disc: EmoteList(kind, form) for each of the 8 character entries (Sonic, Tails, Knuckles, Amy, E-102, Big, Super
// Sonic kind 8, the General form) without a world - libsa1 094a-lib-emote's list sizes (107 / 140 / 122 / 105 / 89 / 96 /
// 92 / 119), non-empty names, every key parses back to its (source, index), dup points at an earlier entry; Knuckles'
// k_panch0 is two entries (rows 39 and 54); Eggman's list is empty. With gm_construct (read only from the Garry's Mod
// install; skipped when it is not there): a standing Sonic plays "a3" (Emote -> true, EmoteState PLAYING with key a3 after
// two pairs), EmoteStop(STOP_NOW) ends it; an entry not offered ("a130" for a normal Sonic) -> nil, "... is not available
// for Sonic", "bad_argument".
// Round 0.9.4b (objects2_plan.md 11.2; libsa1's SA1_API_EMOTE_HOLD, 094b-lib-emote): gsa1.FEATURES.emote = 2,
// gsa1.EMOTE.HOLD / STATE_HOLDING = libsa1's macros; with gm_construct: Emote(id, "a75", HOLD) (s_kimepose0, the wheel's
// "Hold the last pose") -> EmoteState HOLDING, key a75, frame 64 (its last frame) and still so 60 pairs later; the stick
// ends it (NONE); the pose held again, Emote(a3) replaces it; held again, EmoteStop(STOP_BLEND) blends back to standing
// (PLAYING / ENDING, then NONE); without HOLD a75 ends by itself (never HOLDING).
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

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
#include "../src/core/emote.hpp"
#include "../src/core/util.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

namespace {

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1e9;
}

void pairs_of(MockLua &L, double id, int n, double sy)
{
    for (int i = 0; i < n; i++) {
        L.call("Tick", {Val::number(id), Val::number(0), Val::number(sy), Val::number(0), Val::number(0),
                        Val::number(1.0 / 30.0)});
    }
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
    std::printf("G-SA1 feat_emote_binding_test\n");
#if !defined(SA1_API_EMOTE)
    CHECK(false, "libsa1.h has no emotes (round 0.9.4a, SA1_API_EMOTE)");
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return 1;
#else
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_emote_appdata");
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
    bool fns = true;
    for (const char *f : {"EmoteList", "Emote", "EmoteStop", "EmoteState"}) {
        fns = fns && g.tab->field(f).type == Type::Function;
    }
#if defined(SA1_API_EMOTE_HOLD)
    const double want_version = 2.0;
#else
    const double want_version = 1.0;
#endif
    CHECK(fns && feats.type == Type::Table && feats.tab->field("emote").num == want_version && L.st.empty(),
          "gsa1.FEATURES.emote = %g; EmoteList, Emote, EmoteStop, EmoteState registered",
          feats.type == Type::Table ? feats.tab->field("emote").num : -1.0);
    Val K = g.tab->field("EMOTE");
    bool k = K.type == Type::Table;
    struct { const char *name; double v; } consts[] = {
        {"LOOP", (double)gsa1::kEmoteLoop}, {"IN_AIR", SA1_EMOTE_IN_AIR}, {"KEEP_INPUT", SA1_EMOTE_KEEP_INPUT},
        {"NO_PROPS", SA1_EMOTE_NO_PROPS}, {"NO_TRAIL", SA1_EMOTE_NO_TRAIL}, {"CHAIN", SA1_EMOTE_CHAIN},
        {"STOP_NOW", SA1_EMOTE_STOP_NOW}, {"STOP_BLEND", SA1_EMOTE_STOP_BLEND}, {"STATE_NONE", SA1_EMOTE_STATE_NONE},
        {"STATE_PLAYING", SA1_EMOTE_STATE_PLAYING}, {"STATE_ENDING", SA1_EMOTE_STATE_ENDING}, {"ROW", SA1_EMOTE_ROW},
        {"EXTRA", SA1_EMOTE_EXTRA}, {"PLAY_DEFAULT", SA1_EMOTE_PLAY_DEFAULT}, {"PLAY_ONCE", SA1_EMOTE_PLAY_ONCE},
        {"PLAY_LOOP", SA1_EMOTE_PLAY_LOOP}, {"MAX_ITEMS", SA1_EMOTE_MAX_ITEMS}, {"FORM_NORMAL", SA1_EMOTE_FORM_NORMAL},
        {"FORM_SUPER", SA1_EMOTE_FORM_SUPER}, {"CLASS_STAND", SA1_EMOTE_CLASS_STAND}, {"CLASS_IDLE", SA1_EMOTE_CLASS_IDLE},
        {"CLASS_POSE", SA1_EMOTE_CLASS_POSE}, {"CLASS_MOVE", SA1_EMOTE_CLASS_MOVE}, {"CLASS_AIR", SA1_EMOTE_CLASS_AIR},
        {"CLASS_BRAKE", SA1_EMOTE_CLASS_BRAKE}, {"CLASS_BALL", SA1_EMOTE_CLASS_BALL},
        {"CLASS_ATTACK", SA1_EMOTE_CLASS_ATTACK}, {"CLASS_CARRY", SA1_EMOTE_CLASS_CARRY},
        {"CLASS_SETPIECE", SA1_EMOTE_CLASS_SETPIECE}, {"CLASS_HURT", SA1_EMOTE_CLASS_HURT},
        {"CLASS_FISH", SA1_EMOTE_CLASS_FISH}, {"CLASS_SWIM", SA1_EMOTE_CLASS_SWIM}, {"CLASS_BOARD", SA1_EMOTE_CLASS_BOARD},
        {"CLASS_SUPER", SA1_EMOTE_CLASS_SUPER}, {"F_NEEDS_PROP", SA1_EMOTE_F_NEEDS_PROP}, {"F_HOLD", SA1_EMOTE_F_HOLD},
        {"F_SUPER_ONLY", SA1_EMOTE_F_SUPER_ONLY}, {"F_BOARD", SA1_EMOTE_F_BOARD},
        {"F_OTHER_OBJECT", SA1_EMOTE_F_OTHER_OBJECT}, {"F_EXTRA", SA1_EMOTE_F_EXTRA},
#if defined(SA1_API_EMOTE_HOLD)
        {"HOLD", SA1_EMOTE_HOLD}, {"STATE_HOLDING", SA1_EMOTE_STATE_HOLDING},
#endif
    };
    std::string wrong;
    for (const auto &c : consts) {
        if (!k || K.tab->field(c.name).type != Type::Number || K.tab->field(c.name).num != c.v) {
            wrong += std::string(" ") + c.name;
        }
    }
#if defined(SA1_API_EMOTE_HOLD)
    CHECK((gsa1::emote_pass_flags() & SA1_EMOTE_HOLD) != 0 && (gsa1::kEmoteLoop & SA1_EMOTE_HOLD) == 0,
          "round 0.9.4b: Emote passes gsa1.EMOTE.HOLD (0x%X) through to libsa1", (unsigned)SA1_EMOTE_HOLD);
#endif
    CHECK(k && wrong.empty() && ((uint32_t)gsa1::kEmoteLoop & (SA1_EMOTE_CHAIN | gsa1::emote_pass_flags())) == 0,
          "gsa1.EMOTE: libsa1's numbers (%zu constants; LOOP 0x%X is G-SA1's own and no libsa1 flag)%s",
          sizeof consts / sizeof consts[0], (unsigned)gsa1::kEmoteLoop, wrong.empty() ? "" : (": wrong" + wrong).c_str());

    // the keys (src/core/emote.cpp)
    uint32_t src = 9, idx = 9;
    bool keys = gsa1::emote_parse_key("a75", src, idx) && src == SA1_EMOTE_ROW && idx == 75 &&
                gsa1::emote_parse_key("x3", src, idx) && src == SA1_EMOTE_EXTRA && idx == 3 &&
                gsa1::emote_parse_key("a0", src, idx) && idx == 0 && gsa1::emote_parse_key("a999", src, idx) &&
                !gsa1::emote_parse_key("a1000", src, idx) && !gsa1::emote_parse_key("a075", src, idx) &&
                !gsa1::emote_parse_key("b3", src, idx) && !gsa1::emote_parse_key("a", src, idx) &&
                !gsa1::emote_parse_key("a-1", src, idx) && !gsa1::emote_parse_key("a 3", src, idx) &&
                gsa1::emote_key(SA1_EMOTE_ROW, 75) == "a75" && gsa1::emote_key(SA1_EMOTE_EXTRA, 3) == "x3";
    CHECK(keys, "the keys: a<row> / x<extra> parse and print (a0, a75, a999, x3; not a1000, a075, b3, a, a-1, \"a 3\")");

    // without the disc / a character
    std::vector<Val> l0 = L.call("EmoteList", {Val::number(0)});
    std::vector<Val> lb = L.call("EmoteList", {Val::number(9)});
    std::vector<Val> lf = L.call("EmoteList", {Val::number(0), Val::number(2)});
    std::vector<Val> u1 = L.call("Emote", {Val::number(77), Val::string("zz")});
    std::vector<Val> u2 = L.call("Emote", {Val::number(77), Val::number(3)});
    std::vector<Val> u3 = L.call("Emote", {Val::number(77), Val::string("a3")});
    std::vector<Val> u4 = L.call("Emote", {Val::number(77), Val::string("a3"), Val::number(0x8000)});
    std::vector<Val> s1 = L.call("EmoteStop", {Val::number(77)});
    std::vector<Val> s2 = L.call("EmoteStop", {Val::number(77), Val::number(5)});
    std::vector<Val> st = L.call("EmoteState", {Val::number(77)});
    CHECK(is_nil_msg(l0) && str_of(l0, 2) == "not_ready" && is_nil_msg(lb) && str_of(lb, 2) == "bad_argument" &&
              is_nil_msg(lf) && str_of(lf, 2) == "bad_argument" && is_nil_msg(u1) &&
              str_of(u1, 1).rfind("unknown", 0) == 0 && str_of(u1, 2) == "bad_argument" && is_nil_msg(u2) &&
              str_of(u2, 2) == "bad_argument" && is_nil_msg(u3) && str_of(u3, 2) == "not_found" && is_nil_msg(u4) &&
              str_of(u4, 2) == "bad_argument" && is_nil_msg(s1) && str_of(s1, 2) == "not_found" && is_nil_msg(s2) &&
              str_of(s2, 2) == "bad_argument" && st.size() == 1 && st[0].type == Type::Nil && L.st.empty(),
          "without the disc: EmoteList -> nil, \"%s\", not_ready; kind 9 / form 2 -> bad_argument; Emote(77, \"zz\") -> "
          "nil, \"%s\", bad_argument (the key first); Emote of no character -> not_found; a flag 0x8000 -> bad_argument; "
          "EmoteStop of no character -> not_found, how 5 -> bad_argument; EmoteState of no character -> nil",
          str_of(l0, 1).c_str(), str_of(u1, 1).c_str());

    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the catalogue checks need the disc\n");
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
    std::string ist = "loading";
    for (int polls = 0; ist == "loading" && polls < 30000; polls++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        ist = str_of(L.call("InitPoll", {}), 0);
    }
    CHECK(ist == "ready", "the disc: %s", ist.c_str());

    // the catalogues of the 8 entries, no world
    struct Entry { const char *name; int kind; int form; size_t want; } entries[] = {
        {"sonic", 0, 0, 107}, {"tails", 2, 0, 140}, {"knuckles", 3, 0, 122}, {"amy", 5, 0, 105}, {"gamma", 6, 0, 89},
        {"big", 7, 0, 96}, {"supersonic", 8, 0, 92}, {"supersonic_general", 0, 1, 119},
    };
    std::string sizes, problems;
    for (const Entry &e : entries) {
        std::vector<Val> r = L.call("EmoteList", {Val::number(e.kind), Val::number(e.form)});
        if (r.size() != 1 || r[0].type != Type::Table) {
            problems += gsa1::format(" %s: no list (%s)", e.name, str_of(r, 1).c_str());
            continue;
        }
        Val t = r[0];
        size_t n = (size_t)t.tab->field("n").num;
        sizes += gsa1::format("%s%s %zu", sizes.empty() ? "" : ", ", e.name, n);
        if (n != e.want) problems += gsa1::format(" %s: %zu entries (libsa1 reported %zu)", e.name, n, e.want);
        for (size_t i = 1; i <= n; i++) {
            Val row = t.tab->at((double)i);
            if (row.type != Type::Table) {
                problems += gsa1::format(" %s %zu: no table", e.name, i);
                break;
            }
            std::string key = row.tab->field("key").str, name = row.tab->field("name").str;
            uint32_t s = 0, x = 0;
            bool parses = gsa1::emote_parse_key(key, s, x) && s == (uint32_t)row.tab->field("source").num &&
                          x == (uint32_t)row.tab->field("index").num;
            std::string play = row.tab->field("play").str;
            double dup = row.tab->field("dup").num;
            if (name.empty() || !parses || (play != "loop" && play != "once" && play != "hold") ||
                dup < 0 || dup >= (double)i || row.tab->field("group").str.empty()) {
                problems += gsa1::format(" %s %s (%s, %s, dup %g)", e.name, key.c_str(), name.c_str(), play.c_str(), dup);
                break;
            }
        }
    }
    CHECK(problems.empty() && L.st.empty(), "EmoteList without a world for the 8 entries (%s): names, keys that parse back to "
          "(source, index), play loop / once / hold, dup an earlier entry or 0%s", sizes.c_str(), problems.c_str());
    std::vector<Val> kn = L.call("EmoteList", {Val::number(3)});
    int panch = 0;
    std::string pk;
    if (kn.size() == 1 && kn[0].type == Type::Table) {
        for (int i = 1; i <= (int)kn[0].tab->field("n").num; i++) {
            Val row = kn[0].tab->at(i);
            if (row.tab->field("name").str == "k_panch0") {
                panch++;
                pk += " " + row.tab->field("key").str + (row.tab->field("dup").num > 0 ? "(dup)" : "");
            }
        }
    }
    std::vector<Val> eg = L.call("EmoteList", {Val::number(1)});
    CHECK(panch == 2 && pk == " a39 a54" && eg.size() == 1 && eg[0].type == Type::Table && eg[0].tab->field("n").num == 0,
          "Knuckles' k_panch0 is two entries, neither a duplicate (%s): names are not unique (review R.9); Eggman: an empty "
          "list", pk.c_str());

    std::string map;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
        std::printf("  info  no gm_construct (%s): the play checks are skipped\n", bsp.c_str());
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct)");
    const Val pos = Val::vector(704, 132, -139);
    std::vector<Val> r = L.call("Create", {Val::number(0), pos, Val::number(180)});
    double id = num_of(r, 0);
    pairs_of(L, id, 20, 0.0);                  // he lands and stands
    std::vector<Val> p1 = L.call("Emote", {Val::number(id), Val::string("a3")});
    pairs_of(L, id, 2, 0.0);
    std::vector<Val> st1 = L.call("EmoteState", {Val::number(id)});
    std::vector<Val> p2 = L.call("Emote", {Val::number(id), Val::string("a130")});
    std::vector<Val> sp = L.call("EmoteStop", {Val::number(id), Val::number(SA1_EMOTE_STOP_NOW)});
    pairs_of(L, id, 2, 0.0);
    std::vector<Val> st2 = L.call("EmoteState", {Val::number(id)});
    CHECK(id > 0 && p1.size() == 1 && p1[0].b && st1.size() == 4 && num_of(st1, 0) == SA1_EMOTE_STATE_PLAYING &&
              str_of(st1, 1) == "a3" && num_of(st1, 2) >= 0 && is_nil_msg(p2) && str_of(p2, 2) == "bad_argument" &&
              str_of(p2, 1).find("not available for Sonic") != std::string::npos && sp.size() == 1 && sp[0].b &&
              st2.size() == 4 && num_of(st2, 0) == SA1_EMOTE_STATE_NONE && st2[1].type == Type::Nil,
          "a standing Sonic: Emote(a3) -> true, EmoteState %g \"%s\" item %g frame %g after two pairs; Emote(a130) -> nil, "
          "\"%s\", %s; EmoteStop(STOP_NOW) -> the state none after two pairs", num_of(st1, 0), str_of(st1, 1).c_str(),
          num_of(st1, 2), num_of(st1, 3), str_of(p2, 1).c_str(), str_of(p2, 2).c_str());
#if defined(SA1_API_EMOTE_HOLD)
    // round 0.9.4b: HOLD (the wheel's "Hold the last pose", default on for once animations)
    auto state_of = [&](std::vector<Val> &out) {
        out = L.call("EmoteState", {Val::number(id)});
        return num_of(out, 0);
    };
    auto until_state = [&](double want, int max_pairs, std::vector<Val> &out) {
        for (int p = 1; p <= max_pairs; p++) {
            pairs_of(L, id, 1, 0.0);
            if (state_of(out) == want) return p;
        }
        return -1;
    };
    pairs_of(L, id, 30, 0.0);
    std::vector<Val> hs, hs2, hs3;
    std::vector<Val> h1 = L.call("Emote", {Val::number(id), Val::string("a75"), Val::number(SA1_EMOTE_HOLD)});
    int held_at = until_state(SA1_EMOTE_STATE_HOLDING, 150, hs);
    pairs_of(L, id, 60, 0.0);
    double held_state = state_of(hs2);
    CHECK(h1.size() == 1 && h1[0].b && held_at > 0 && str_of(hs, 1) == "a75" && std::fabs(num_of(hs, 3) - 64.0) < 0.01 &&
              held_state == SA1_EMOTE_STATE_HOLDING && str_of(hs2, 1) == "a75" && std::fabs(num_of(hs2, 3) - 64.0) < 0.01,
          "Emote(a75, HOLD): EmoteState HOLDING after %d pairs, key \"%s\", frame %g (s_kimepose0's last); 60 pairs later "
          "still %g \"%s\" frame %g", held_at, str_of(hs, 1).c_str(), num_of(hs, 3), held_state, str_of(hs2, 1).c_str(),
          num_of(hs2, 3));
    pairs_of(L, id, 1, 1.0);
    double moved = state_of(hs3);
    pairs_of(L, id, 60, 0.0);
    CHECK(moved == SA1_EMOTE_STATE_NONE, "the stick ends the held pose at once (state %g)", moved);
    // held again: another animation replaces the pose
    std::vector<Val> h2 = L.call("Emote", {Val::number(id), Val::string("a75"), Val::number(SA1_EMOTE_HOLD)});
    int held2 = until_state(SA1_EMOTE_STATE_HOLDING, 150, hs);
    std::vector<Val> r3 = L.call("Emote", {Val::number(id), Val::string("a3")});
    pairs_of(L, id, 2, 0.0);
    double s3 = state_of(hs3);
    std::string k3 = str_of(hs3, 1);
    L.call("EmoteStop", {Val::number(id), Val::number(SA1_EMOTE_STOP_NOW)});
    pairs_of(L, id, 4, 0.0);
    CHECK(h2.size() == 1 && h2[0].b && held2 > 0 && r3.size() == 1 && r3[0].b && s3 == SA1_EMOTE_STATE_PLAYING && k3 == "a3",
          "held again (after %d pairs), Emote(a3) replaces the pose: %g \"%s\"", held2, s3, k3.c_str());
    // held again: STOP_BLEND blends back to standing (the wheel's slot chosen again)
    std::vector<Val> h3 = L.call("Emote", {Val::number(id), Val::string("a75"), Val::number(SA1_EMOTE_HOLD)});
    int held3 = until_state(SA1_EMOTE_STATE_HOLDING, 150, hs);
    std::vector<Val> sb = L.call("EmoteStop", {Val::number(id), Val::number(SA1_EMOTE_STOP_BLEND)});
    bool left = false;
    int ended = -1;
    for (int p = 1; p <= 120 && ended < 0; p++) {
        pairs_of(L, id, 1, 0.0);
        double x = state_of(hs3);
        if (x == SA1_EMOTE_STATE_PLAYING || x == SA1_EMOTE_STATE_ENDING) left = true;
        if (x == SA1_EMOTE_STATE_NONE) ended = p;
    }
    CHECK(h3.size() == 1 && h3[0].b && held3 > 0 && sb.size() == 1 && sb[0].b && ended > 0,
          "held again (after %d pairs), EmoteStop(STOP_BLEND) blends back to standing: %s, none after %d pairs", held3,
          left ? "PLAYING / ENDING first" : "straight to none", ended);
    // without HOLD (0.9.4a): a75 ends by itself and is never HOLDING
    pairs_of(L, id, 10, 0.0);
    std::vector<Val> h4 = L.call("Emote", {Val::number(id), Val::string("a75")});
    bool holding = false;
    int done_at = -1;
    for (int p = 1; p <= 200 && done_at < 0; p++) {
        pairs_of(L, id, 1, 0.0);
        double x = state_of(hs3);
        holding = holding || x == SA1_EMOTE_STATE_HOLDING;
        if (p > 2 && x == SA1_EMOTE_STATE_NONE) done_at = p;
    }
    CHECK(h4.size() == 1 && h4[0].b && !holding && done_at > 0,
          "without HOLD a75 ends by itself after %d pairs, never HOLDING", done_at);
#endif
    L.call("Destroy", {Val::number(id)});
    CHECK(L.st.empty(), "the mock stack is empty after every call");
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
#endif
}
