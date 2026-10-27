// feat_faces_binding_test: the event faces through the module's Lua functions (round 0.9.4a: the feature "faces",
// src/module/bind_faces.cpp, and the microphone src/core/mic.cpp; sadc docs/research/faces_wheel_plan.md 6.4 task 2 and
// its binding test with Review R.19). Linked like binding_test (the module's objects, libsa1, the mock Lua stack of
// tests/mock_lua.hpp) by build.py, run with --gdi GAME.gdi.
//
//   feat_faces_binding_test [--gdi GAME.gdi] [--bsp gm_construct.bsp]
//
// Without the disc: gsa1.FEATURES.faces = 1 with its 12 functions; gsa1.FACE holds libsa1's numbers; FaceSequence refuses
// "b:10", "f:0:0", "b:200:0" and 33 entries with nil, message, "bad_argument"; FaceLevel without a character returns
// nothing and raises nothing; the microphone with a fake BASS recording table: a 1 kHz sine with an RMS of -20 dBFS (peak
// 0.1414) gives the level 0.80 +- 0.02, silence 0; BASS_ERROR_ALREADY takes the RecordSetDevice path and close frees
// nothing; an init failure gives "failed: ..."; MicListen(false) counts no more blocks; MicDevices lists the fake's devices.
// With the disc: FaceInfo for every kind without a world (Sonic 21 keys, Big 8 keys and the mask 0x01FC0C1F, E-102 and
// Super Sonic none; the face animations' lengths), and - with gm_construct (read only; skipped when it is not there) - the
// calls on characters: Sonic's FaceMode / FaceSequence / FaceState, Big's refused 'b', E-102 refused.
//
// Round 0.9.4c (feature "faces" 2, phoneme lip sync; sadc docs/research/phoneme_plan.md 6.2 V9 with its Review R.2 / R.4 /
// R.11): gsa1.FEATURES.faces = 2 with MicViseme, MicVisemeOn, MicVisemeTune, MicVisemeVoice, VisemeMouth, VisemeTable and
// FaceMouth; gsa1.VISEME and gsa1.FACE.MOUTH / SAME_PAIR equal the C++ and libsa1 values (SAME_PAIR present exactly when
// libsa1.h defines SA1_FACE_SAME_PAIR); MicViseme without a device -> cls -1 and numbers; the per-frame functions with bad
// arguments return nothing or 0, 0, 0 and raise nothing; VisemeTable(0) has 9 rows and ladder_cap 0.5; with the fake
// microphone a block makes a frame; with the disc FaceInfo's ladders are the per-character ones (0,4,16 / 0,4,7,8 /
// 0,4,7,16 / 0,7,4,8,16 / 0,4,5) and every VisemeTable key is below FaceInfo(kind).keys. It writes faces2_api.txt next to
// itself (build/<target>/): every new function as built (its arguments and the values it returned here) and every new
// constant with its value - the Lua lane's feat_phonemes_test.lua (P13) checks its mock against it (review R.11).
//
// Round 0.9.4e (feature "faces" 3; sadc docs/research/lipsync2_plan.md 5.5 / 5.6 and 6.2 B1-B8 with its review R.3 / R.4c /
// R.5 / R.7 / R.8): B1 VisemeOverride's argument checks ("bad_argument"; a kind without a face "unsupported"); B2 VisemeTable's
// table_version 2, custom_spec, the rows' custom / default after an override and none after a reset, mouth_at of the five
// face kinds; B3 gsa1.FEATURES.faces = 3; B4 VisemeMouth with an override and after VisemeOverride(kind, ""); B5 MicDevices
// through the fake BASS with a loopback device at 6 (invented device names only: review R.7) - its loopback true, the others
// false; B6 MicOpen(6) -> nil, the text, "unsupported" with nothing opened, MicOpen(input, true) re-opens (RecordStart again),
// MicLevel's four values (blocks); B7 MicVisemeWarmup's seven step words accepted when allowed (engine 2, "Learn my voice",
// the microphone open), refused with "unsupported" (engine 1, adapt 0, nothing open) and "bad_argument" (another word),
// MicVisemeWarmupState's six numbers (result 0..4), MicVisemeVoice's five, MicVisemeFeatures' nine; B8 the per-frame
// functions (MicViseme, MicVisemeFeatures, MicVisemeWarmupState, MicVisemeVoice, MicLevel, VisemeMouth) 10,000 calls each:
// the stack balanced, no table created (a counting mock), nothing thrown. It writes faces2_api.txt (every 0.9.4e function,
// return and constant added) and faces_tables.txt (VisemeTable of every face kind, the normal form of 40 seeded specs, 30
// invalid specs with the module's message) for the Lua lanes (feat_phonemes_test.lua P13, feat_mouths_test.lua L8b).
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
#include "../src/core/mic.hpp"
#include "../src/core/mouth.hpp"
#include "../src/core/util.hpp"
#include "../src/core/viseme.hpp"
#include "../src/module/gsa1_module_internal.hpp"
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

namespace {

// ---- a fake of BASS's recording API ----------------------------------------------------------------------------------
struct Fake {
    int ndev = 2;                    // the recording devices f_info reports (0.9.4e B5: 7, a loopback at 6)
    int init_result = 1;             // RecordInit's BOOL
    int init_error = 0;              // ErrorGetCode after a failed init
    int inits = 0, frees = 0, set_devices = 0, starts = 0, plays = 0, pauses = 0, stops = 0;
    int last_set_device = -1;
    int cur_device = 0;              // what RecordGetDevice reports: RecordInit's / RecordSetDevice's (0.9.4e B6)
    gsa1::mic::RecordProc *proc = nullptr;
    void *user = nullptr;
    uint32_t start_flags = 0, start_rate = 0, start_chans = 0;
    bool paused = true;
    int error = 0;
};
Fake g_fake;

int GSA1_MICCALL f_init(int device)
{
    g_fake.inits++;
    if (!g_fake.init_result) {
        g_fake.error = g_fake.init_error;
        return 0;
    }
    g_fake.cur_device = device >= 0 ? device : 0;    // -1: Windows' default, the fake's device 0
    return 1;
}
int GSA1_MICCALL f_free(void)
{
    g_fake.frees++;
    return 1;
}
int GSA1_MICCALL f_info(uint32_t device, gsa1::mic::DeviceInfo *info)
{
    // invented device names only (review R.7: never the owner's devices)
    static const char *names[] = {"Headset Microphone", "Line In", "Microphone (Example USB Mic)",
                                  "Stereo Mix (Example Audio)", "Microphone (Example Voice Changer)",
                                  "Headset Microphone (Example Pad)", "Speakers (Example Audio)"};
    if ((int)device >= g_fake.ndev || device > 6) {
        return 0;
    }
    info->name = names[device];
    info->driver = "fake";
    info->flags = device == 0 ? (gsa1::mic::kDeviceEnabled | gsa1::mic::kDeviceDefault)
                  : device == 1 ? 0u
                  : device == 6 ? (gsa1::mic::kDeviceEnabled | gsa1::mic::kDeviceLoopback)
                                : gsa1::mic::kDeviceEnabled;
    return 1;
}
int GSA1_MICCALL f_set(uint32_t device)
{
    g_fake.set_devices++;
    g_fake.last_set_device = (int)device;
    g_fake.cur_device = (int)device;
    return 1;
}
uint32_t GSA1_MICCALL f_get(void)
{
    return (uint32_t)g_fake.cur_device;
}
uint32_t GSA1_MICCALL f_start(uint32_t freq, uint32_t chans, uint32_t flags, gsa1::mic::RecordProc *proc, void *user)
{
    g_fake.starts++;
    g_fake.proc = proc;
    g_fake.user = user;
    g_fake.start_rate = freq;
    g_fake.start_chans = chans;
    g_fake.start_flags = flags;
    g_fake.paused = (flags & gsa1::mic::kRecordPause) != 0;
    return 0x42;
}
int GSA1_MICCALL f_play(uint32_t h, int restart)
{
    (void)h;
    (void)restart;
    g_fake.plays++;
    g_fake.paused = false;
    return 1;
}
int GSA1_MICCALL f_pause(uint32_t h)
{
    (void)h;
    g_fake.pauses++;
    g_fake.paused = true;
    return 1;
}
int GSA1_MICCALL f_stop(uint32_t h)
{
    (void)h;
    g_fake.stops++;
    g_fake.proc = nullptr;
    return 1;
}
int GSA1_MICCALL f_error(void)
{
    return g_fake.error;
}
const gsa1::mic::Api k_fake = {f_init, f_free, f_info, f_set, f_get, f_start, f_play, f_pause, f_stop, f_error};

// one 10 ms block (160 samples at 16 kHz) through the proc BASS was given: a sine of `rms` (amplitude rms * sqrt 2)
// at 1 kHz, or silence; delivered even while "paused" (a block in flight), like a real device might
void block(double rms)
{
    float b[160];
    for (int i = 0; i < 160; i++) {
        b[i] = (float)(rms * std::sqrt(2.0) * std::sin(2.0 * 3.14159265358979 * 1000.0 * i / 16000.0));
    }
    if (g_fake.proc) {
        g_fake.proc(0x42, b, sizeof b, g_fake.user);
    }
}

// 0.9.4e B8: the mock with a counter of the tables the module creates
struct CountingLua : MockLua {
    uint64_t tables = 0;
    void CreateTable() override
    {
        tables++;
        MockLua::CreateTable();
    }
};

double num_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::Number ? r[i].num : -1e9;
}

void pairs_of(MockLua &L, double id, int n)
{
    for (int i = 0; i < n; i++) {
        L.call("Tick", {Val::number(id), Val::number(0), Val::number(0), Val::number(0), Val::number(0),
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
    std::printf("G-SA1 feat_faces_binding_test\n");
    CountingLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    std::string self = gsa1::parent_dir(argv[0]);
    std::string fake_appdata = gsa1::join_path(self.empty() ? "." : self, "feat_faces_appdata");
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
#if !defined(SA1_API_FACE)
    CHECK(false, "libsa1.h has no faces section (round 0.9.4a, SA1_API_FACE)");
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return 1;
#else
    Val feats = g.tab->field("FEATURES");
    bool fns = true;
    int nfns = 0;
    for (const char *f : {"FaceInfo", "FaceMode", "FaceSequence", "FaceScript", "FaceStop", "FaceLevel", "FaceState",
                          "MicDevices", "MicOpen", "MicListen", "MicClose", "MicLevel",
                          // 0.9.4c (version 2)
                          "MicViseme", "MicVisemeOn", "MicVisemeTune", "MicVisemeVoice", "VisemeMouth", "VisemeTable",
                          "FaceMouth"}) {
        fns = fns && g.tab->field(f).type == Type::Function;
        nfns++;
    }
    for (const char *f : {"VisemeOverride"}) {    // 0.9.4e (version 3)
        fns = fns && g.tab->field(f).type == Type::Function;
        nfns++;
    }
    CHECK(fns && feats.type == Type::Table && feats.tab->field("faces").num == 3 && L.st.empty(),
          "B3 gsa1.FEATURES.faces = %g (0.9.4e: 3); its %d functions registered (FaceMouth: libsa1's "
          "sa1_character_face_mouth; VisemeOverride: the player's mouths)",
          feats.type == Type::Table ? feats.tab->field("faces").num : -1.0, nfns);
    Val K = g.tab->field("FACE");
    CHECK(K.type == Type::Table && K.tab->field("MODE_GAME").num == SA1_FACE_MODE_GAME &&
              K.tab->field("MODE_EVENT").num == SA1_FACE_MODE_EVENT &&
              K.tab->field("PACE_CUTSCENE").num == SA1_FACE_PACE_CUTSCENE && K.tab->field("NOW").num == SA1_FACE_NOW &&
              K.tab->field("LOOP").num == SA1_FACE_LOOP && K.tab->field("HOLD_LAST").num == SA1_FACE_HOLD_LAST &&
              K.tab->field("LEVEL_LADDER").num == SA1_FACE_LEVEL_LADDER &&
              K.tab->field("LEVEL_TALK").num == SA1_FACE_LEVEL_TALK && K.tab->field("ACT_NONE").num == SA1_FACE_ACT_NONE &&
              K.tab->field("ACT_SEQUENCE").num == SA1_FACE_ACT_SEQUENCE &&
              K.tab->field("ACT_SCRIPT").num == SA1_FACE_ACT_SCRIPT && K.tab->field("ACT_HELD").num == SA1_FACE_ACT_HELD &&
              K.tab->field("ACT_LIPSYNC").num == SA1_FACE_ACT_LIPSYNC &&
              K.tab->field("ACT_GAMEPLAY").num == SA1_FACE_ACT_GAMEPLAY && K.tab->field("SEQ_MAX").num == SA1_FACE_SEQ_MAX &&
              K.tab->field("HOLD_MAX").num == SA1_FACE_HOLD_MAX && K.tab->field("ENTER_MAX").num == 127,
          "gsa1.FACE: libsa1's numbers (MODE_EVENT %u, PACE_CUTSCENE 0x%X, NOW %u, LOOP %u, HOLD_LAST %u, ACT_* 0-5, "
          "SEQ_MAX %u, HOLD_MAX %u)", (unsigned)SA1_FACE_MODE_EVENT, (unsigned)SA1_FACE_PACE_CUTSCENE,
          (unsigned)SA1_FACE_NOW, (unsigned)SA1_FACE_LOOP, (unsigned)SA1_FACE_HOLD_LAST, (unsigned)SA1_FACE_SEQ_MAX,
          (unsigned)SA1_FACE_HOLD_MAX);
#if defined(SA1_FACE_SAME_PAIR)
    const bool same_pair_ok = K.tab->field("SAME_PAIR").type == Type::Number && K.tab->field("SAME_PAIR").num == SA1_FACE_SAME_PAIR;
    const char *same_pair_what = "present = SA1_FACE_SAME_PAIR (libsa1 built the faster mouth)";
#else
    const bool same_pair_ok = K.tab->field("SAME_PAIR").type == Type::Nil;
    const char *same_pair_what = "absent (libsa1.h has no SA1_FACE_SAME_PAIR: the faster mouth was not built)";
#endif
    CHECK(K.tab->field("MOUTH").num == 1 && same_pair_ok,
          "gsa1.FACE.MOUTH = 1 (gsa1.FaceMouth exists: review R.4); gsa1.FACE.SAME_PAIR %s (review R.2)", same_pair_what);
    // gsa1.VISEME
    Val VI = g.tab->field("VISEME");
    int vis_ok = 0;
    if (VI.type == Type::Table) {
        for (int k = 0; k < gsa1::viseme::COUNT; k++) {
            vis_ok += VI.tab->field(gsa1::viseme::name(k)).num == k &&
                      VI.tab->field("NAMES").type == Type::Table && VI.tab->field("NAMES").tab->at(k).str == gsa1::viseme::name(k) &&
                      VI.tab->field("WORDS").type == Type::Table && VI.tab->field("WORDS").tab->at(k).str == gsa1::viseme::word(k);
        }
    }
    CHECK(vis_ok == 9 && VI.tab->field("COUNT").num == 9 && VI.tab->field("SIL").num == 0 && VI.tab->field("FV").num == 8 &&
              VI.tab->field("WORDS").tab->at(8).str == "f v th" && VI.tab->field("NAMES").tab->at(9).type == Type::Nil,
          "gsa1.VISEME: SIL 0 .. FV 8, COUNT 9, NAMES[0..8] and WORDS[0..8] (\"silence\" .. \"f v th\") equal the C++ "
          "classes (%d of 9)", vis_ok);

    // the spec, checked in C before anything else
    std::string e33;
    for (int i = 0; i < 33; i++) e33 += i ? ",B:0:0" : "B:0:0";
    int bad = 0;
    std::string why;
    for (const char *spec : {"b:10", "f:0:0", "b:200:0", "", "b:10:3601", "bb:1:1", "b:1:1,"}) {
        std::vector<Val> r = L.call("FaceSequence", {Val::number(77), Val::string(spec), Val::number(0)});
        bad += is_nil_msg(r) && str_of(r, 2) == "bad_argument";
        if (std::string(spec) == "f:0:0") why = str_of(r, 1);
    }
    std::vector<Val> r33 = L.call("FaceSequence", {Val::number(77), Val::string(e33), Val::number(0)});
    bad += is_nil_msg(r33) && str_of(r33, 2) == "bad_argument";
    std::vector<Val> rfl = L.call("FaceSequence", {Val::number(77), Val::string("b:10:90"), Val::number(2)});
    bad += is_nil_msg(rfl) && str_of(rfl, 2) == "bad_argument";
    std::vector<Val> rok = L.call("FaceSequence", {Val::number(77), Val::string("b:10:90, A:8:0"), Val::number(4)});
    CHECK(bad == 9 && is_nil_msg(rok) && str_of(rok, 2) == "not_found" && L.st.empty(),
          "FaceSequence: \"b:10\", \"f:0:0\" (%s), \"b:200:0\", \"\", hold 3601, \"bb:1:1\", a trailing comma, 33 entries "
          "and the flag LOOP -> nil, message, \"bad_argument\" (%d of 9); a good spec of no character -> \"not_found\"",
          why.c_str(), bad);
    // FaceLevel: numbers only, nothing back, never an error
    size_t r0 = L.call("FaceLevel", {Val::number(77), Val::number(0.5), Val::number(0)}).size();
    size_t r1 = L.call("FaceLevel", {}).size();
    size_t r2 = L.call("FaceLevel", {Val::string("x"), Val::table(), Val::number(9)}).size();
    std::vector<Val> fs = L.call("FaceState", {Val::number(77)});
    int bad2 = 0;
    bad2 += is_nil_msg(L.call("FaceMode", {Val::number(77), Val::boolean(true), Val::boolean(false)}));
    bad2 += is_nil_msg(L.call("FaceMode", {Val::number(77), Val::string("yes")}));
    bad2 += is_nil_msg(L.call("FaceScript", {Val::number(77), Val::string("CDE"), Val::number(8)}));
    bad2 += is_nil_msg(L.call("FaceStop", {}));
    bad2 += is_nil_msg(L.call("FaceInfo", {Val::number(9)}));
    bad2 += is_nil_msg(L.call("FaceInfo", {Val::number(0)}));      // the disc is not loaded yet: not_ready
    CHECK(r0 == 0 && r1 == 0 && r2 == 0 && fs.size() == 1 && fs[0].type == Type::Nil && bad2 == 6 && L.st.empty(),
          "FaceLevel without a character (or with junk) returns nothing and raises nothing; FaceState of no character "
          "nil; FaceMode / FaceScript / FaceStop / FaceInfo refusals as nil + message (%d of 6)", bad2);

    // ---- 0.9.4c: phoneme lip sync (V9) ---------------------------------------------------------------------------------
    {
        const double nan = std::nan("");
        size_t m0 = L.call("FaceMouth", {Val::number(77), Val::number(0), Val::number(4), Val::number(0.5)}).size();
        size_t m1 = L.call("FaceMouth", {Val::number(77), Val::number(0), Val::number(4), Val::number(nan)}).size();
        size_t m2 = L.call("FaceMouth", {Val::number(77), Val::number(99), Val::number(4), Val::number(0.5), Val::number(512)}).size();
        size_t m3 = L.call("FaceMouth", {}).size();
        size_t m4 = L.call("FaceMouth", {Val::string("x"), Val::table(), Val::boolean(true), Val::number(1e300)}).size();
        size_t l0 = L.call("FaceLevel", {Val::number(77), Val::number(0.5), Val::number(0), Val::number(512)}).size();
        size_t l1 = L.call("FaceLevel", {Val::number(77), Val::number(nan), Val::number(1), Val::number(512)}).size();
        CHECK(m0 + m1 + m2 + m3 + m4 + l0 + l1 == 0 && L.st.empty(),
              "FaceMouth / FaceLevel (with flags) without a character, with NaN, with key 99 or with junk return nothing and "
              "raise nothing");
        std::vector<Val> mv = L.call("MicViseme", {});
        std::vector<Val> vv = L.call("MicVisemeVoice", {});
        bool nums = mv.size() == 6 && vv.size() == 5;     // 0.9.4e: g, frames, f1, f2, warmed
        for (const Val &v : mv) nums = nums && v.type == Type::Number;
        for (const Val &v : vv) nums = nums && v.type == Type::Number;
        CHECK(nums && num_of(mv, 0) == -1 && num_of(vv, 1) == 0 && std::fabs(num_of(vv, 0) - gsa1::viseme::prior_g()) < 1e-5,
              "MicViseme without a device -> 6 numbers, cls %g (-1); MicVisemeVoice -> the prior %.3f, %g frames",
              num_of(mv, 0), num_of(vv, 0), num_of(vv, 1));
        int tune_ok = 0, tune_bad = 0;
        for (const char *n : {"gate_min_db", "adapt", "smooth"}) {
            std::vector<Val> r = L.call("MicVisemeTune", {Val::string(n), Val::number(std::string(n) == "gate_min_db" ? 6 :
                                                                                          (std::string(n) == "adapt" ? 1 : 3))});
            tune_ok += r.size() == 1 && r[0].type == Type::Bool && r[0].b;
        }
        std::vector<Val> rv = L.call("MicVisemeTune", {Val::string("reset_voice")});
        tune_ok += rv.size() == 1 && rv[0].b;
        std::vector<Val> ra = L.call("MicVisemeTune", {Val::string("adapt"), Val::boolean(true)});
        tune_ok += ra.size() == 1 && ra[0].b;
        for (const std::vector<Val> &args : std::vector<std::vector<Val>>{
                 {Val::string("gate_min_db"), Val::number(2)}, {Val::string("gate_min_db"), Val::number(13)},
                 {Val::string("adapt"), Val::number(0.5)}, {Val::string("smooth"), Val::number(4)},
                 {Val::string("smooth"), Val::string("quick")}, {Val::string("loudness"), Val::number(1)}, {}}) {
            std::vector<Val> r = L.call("MicVisemeTune", args);
            tune_bad += is_nil_msg(r) && str_of(r, 2) == "bad_argument";
        }
        std::vector<Val> on1 = L.call("MicVisemeOn", {Val::boolean(true)});
        std::vector<Val> on0 = L.call("MicVisemeOn", {Val::boolean(false)});
        std::vector<Val> onx = L.call("MicVisemeOn", {Val::string("yes")});
        CHECK(tune_ok == 5 && tune_bad == 7 && on1.size() == 1 && on1[0].b && on0.size() == 1 && on0[0].b && is_nil_msg(onx) &&
                  str_of(onx, 2) == "bad_argument" && L.st.empty(),
              "MicVisemeTune: gate_min_db / adapt / smooth / reset_voice / adapt=true taken (%d of 5), out of range, unknown "
              "or missing -> nil, message, \"bad_argument\" (%d of 7); MicVisemeOn(true / false) -> true, (\"yes\") refused",
              tune_ok, tune_bad);
        // VisemeMouth: the table's rule, numbers only
        int same = 0, cases = 0;
        for (int kind : {0, 2, 3, 5, 7, 6}) {
            for (int cls = 0; cls < gsa1::viseme::COUNT; cls++) {
                for (int variant = 0; variant < 3; variant++) {
                    for (int big = 0; big < 2; big++) {
                        int a, b;
                        float w;
                        gsa1::mouth::pick(kind, cls, 0.7f, 0.5f, variant, big != 0, a, b, w);
                        std::vector<Val> r = L.call("VisemeMouth", {Val::number(kind), Val::number(cls), Val::number(0.7),
                                                                    Val::number(0.5), Val::number(variant), Val::boolean(big != 0)});
                        cases++;
                        same += r.size() == 3 && num_of(r, 0) == a && num_of(r, 1) == b && std::fabs(num_of(r, 2) - w) < 1e-6;
                    }
                }
            }
        }
        int zero = 0, junk = 0;
        for (const std::vector<Val> &args : std::vector<std::vector<Val>>{
                 {}, {Val::number(0)}, {Val::number(0), Val::number(9), Val::number(1), Val::number(0.5), Val::number(0)},
                 {Val::number(0), Val::number(2), Val::number(nan), Val::number(0.5), Val::number(0)},
                 {Val::number(0), Val::number(2), Val::number(1), Val::number(0.5), Val::number(3)},
                 {Val::string("x"), Val::table(), Val::number(1), Val::number(1), Val::number(0)},
                 {Val::number(99), Val::number(2), Val::number(1), Val::number(0.5), Val::number(0)}}) {
            std::vector<Val> r = L.call("VisemeMouth", args);
            junk++;
            zero += r.size() == 3 && num_of(r, 0) == 0 && num_of(r, 1) == 0 && num_of(r, 2) == 0;
        }
        std::vector<Val> fv = L.call("VisemeMouth", {Val::number(0), Val::number(8), Val::number(0.9), Val::number(0.5),
                                                     Val::number(0), Val::boolean(true)});
        CHECK(same == cases && zero == junk && num_of(fv, 0) == -1 && std::fabs(num_of(fv, 2) - 0.25) < 1e-6 && L.st.empty(),
              "VisemeMouth equals the C++ table's rule in %d of %d cases; bad arguments -> 0, 0, 0 (%d of %d) without a "
              "Lua error; Sonic's f v th -> -1, -1, %.2f (the ladder kept to his fv_level 0.25: review R.1)", same, cases,
              zero, junk, num_of(fv, 2));
        std::vector<Val> t0 = L.call("VisemeTable", {Val::number(0)});
        std::vector<Val> t6 = L.call("VisemeTable", {Val::number(6)});
        std::vector<Val> tx = L.call("VisemeTable", {Val::string("x")});
        int rows = 0;
        std::string aa;
        if (t0.size() == 1 && t0[0].type == Type::Table) {
            const Table &t = *t0[0].tab;
            for (int k = 0; k < 9; k++) rows += t.at(k).type == Type::Table && t.at(k).tab->field("how").type == Type::String;
            const Val &r2 = t.at(2);
            if (r2.type == Type::Table) {
                aa = gsa1::format("%g>%g@%.2f %s%s; quiet %g>%g; loud %g>%g; plain %g>%g", r2.tab->field("a").num,
                                  r2.tab->field("b").num, r2.tab->field("w").num, r2.tab->field("how").str.c_str(),
                                  r2.tab->field("expression").b ? " X" : "", r2.tab->field("quiet").tab ? r2.tab->field("quiet").tab->field("a").num : -9,
                                  r2.tab->field("quiet").tab ? r2.tab->field("quiet").tab->field("b").num : -9,
                                  r2.tab->field("loud").tab ? r2.tab->field("loud").tab->field("a").num : -9,
                                  r2.tab->field("loud").tab ? r2.tab->field("loud").tab->field("b").num : -9,
                                  r2.tab->field("plain").tab ? r2.tab->field("plain").tab->field("a").num : -9,
                                  r2.tab->field("plain").tab ? r2.tab->field("plain").tab->field("b").num : -9);
            }
        }
        CHECK(rows == 9 && t0[0].tab->field("ladder_cap").num == 0.5 && std::fabs(t0[0].tab->field("fv_level").num - 0.25) < 1e-6 &&
                  t0[0].tab->field("keys").num == 21 && t0[0].tab->field("kind").num == 0 && is_nil_msg(t6) &&
                  str_of(t6, 2) == "unsupported" && is_nil_msg(tx) && str_of(tx, 2) == "bad_argument" &&
                  aa == "7>16@0.45 fixed X; quiet 7>16; loud 7>16; plain 0>7",
              "VisemeTable(0): 9 rows [0..8], ladder_cap 0.5, fv_level 0.25, keys 21; Sonic's \"ah\" %s (0.9.4e table v2: his "
              "open mouth with fangs); VisemeTable(6) (E-102) -> nil, \"unsupported\"; (\"x\") -> \"bad_argument\"", aa.c_str());
    }

    // ---- 0.9.4e: the player's mouths (B1 - B4) and faces_tables.txt (lipsync2_plan.md 5.5 / 5.6, review R.4c / R.8) -------
    {
        // B1 VisemeOverride's arguments
        std::string s513(513, 'A');
        int b1 = 0;
        std::string why1;
        for (const std::vector<Val> &args : std::vector<std::vector<Val>>{
                 {Val::string("x"), Val::string("AA=4")}, {Val::number(9), Val::string("AA=4")},
                 {Val::number(-1), Val::string("AA=4")}, {Val::number(2.5), Val::string("AA=4")}, {},
                 {Val::number(0), Val::table()}, {Val::number(0), Val::number(4)}, {Val::number(0), Val::boolean(true)},
                 {Val::number(0), Val::string(s513)}, {Val::number(0), Val::string(std::string("AA=4\0EE=4", 9))},
                 {Val::number(0), Val::string("AA=21")}}) {
            std::vector<Val> r = L.call("VisemeOverride", args);
            b1 += is_nil_msg(r) && str_of(r, 2) == "bad_argument";
            if (args.size() == 2 && args[1].type == Type::String && args[1].str == "AA=21") why1 = str_of(r, 1);
        }
        int unsup = 0;
        std::string why6;
        for (int k : {1, 4, 6, 8}) {
            std::vector<Val> r = L.call("VisemeOverride", {Val::number(k), Val::string("AA=4")});
            unsup += is_nil_msg(r) && str_of(r, 2) == "unsupported";
            if (k == 6) why6 = str_of(r, 1);
        }
        std::vector<Val> rnil = L.call("VisemeOverride", {Val::number(0)});
        CHECK(b1 == 11 && unsup == 4 && why6 == "E-102 has no face in the game" &&
                  why1 == "AA=21: key 21 is not one of Sonic's 21 face keys (0-20)" && rnil.size() == 1 && rnil[0].b &&
                  L.st.empty(),
              "B1 VisemeOverride: a kind not a number / out of range / not whole, no arguments, a spec that is a table / number "
              "/ boolean, 513 characters, a zero byte, Sonic's key 21 (\"%s\") -> nil, message, \"bad_argument\" (%d of 11); "
              "Eggman / Tikal / E-102 / Super Sonic -> \"unsupported\" (%d of 4: \"%s\"); a nil spec = G-SA1's table (true)",
              why1.c_str(), b1, unsup, why6.c_str());

        // B2 / B4 VisemeTable's new fields and VisemeMouth with an override
        int b2 = 0;
        std::string at;
        for (int k : {0, 2, 3, 5, 7}) {
            std::vector<Val> t = L.call("VisemeTable", {Val::number(k)});
            if (t.size() != 1 || t[0].type != Type::Table) continue;
            const Table &tt = *t[0].tab;
            Val ma = tt.field("mouth_at");
            bool rows_plain = true;
            for (int c = 0; c < 9; c++) {
                rows_plain = rows_plain && tt.at(c).type == Type::Table && tt.at(c).tab->field("custom").type == Type::Bool &&
                             !tt.at(c).tab->field("custom").b && tt.at(c).tab->field("default").type == Type::Nil;
            }
            b2 += tt.field("table_version").num == 2 && tt.field("custom_spec").type == Type::String &&
                  tt.field("custom_spec").str.empty() && ma.type == Type::Table && ma.tab->field("forward").type == Type::Number &&
                  ma.tab->field("up").num > 0 && rows_plain;
            if (ma.type == Type::Table) {
                at += gsa1::format("%s%d: %.1f / %.1f", at.empty() ? "" : ", ", k, ma.tab->field("forward").num,
                                   ma.tab->field("up").num);
            }
        }
        std::vector<Val> before = L.call("VisemeMouth", {Val::number(0), Val::number(2), Val::number(1), Val::number(0.5),
                                                         Val::number(0), Val::boolean(true)});
        std::vector<Val> ok = L.call("VisemeOverride", {Val::number(0), Val::string("AA=9>10@0.5,EE.loud=ladder@0.4")});
        std::vector<Val> t0 = L.call("VisemeTable", {Val::number(0)});
        std::vector<Val> mine = L.call("VisemeMouth", {Val::number(0), Val::number(2), Val::number(1), Val::number(0.5),
                                                       Val::number(0), Val::boolean(false)});
        std::vector<Val> other = L.call("VisemeMouth", {Val::number(2), Val::number(2), Val::number(1), Val::number(0.5),
                                                        Val::number(0), Val::boolean(true)});
        bool custom_ok = false;
        std::string cs;
        if (t0.size() == 1 && t0[0].type == Type::Table) {
            const Table &tt = *t0[0].tab;
            cs = tt.field("custom_spec").str;
            const Val &aa = tt.at(2), &eh = tt.at(3), &ee = tt.at(4);
            custom_ok = aa.tab->field("custom").b && aa.tab->field("a").num == 9 && aa.tab->field("b").num == 10 &&
                        aa.tab->field("default").type == Type::Table && aa.tab->field("default").tab->field("a").num == 7 &&
                        aa.tab->field("default").tab->field("b").num == 16 &&
                        aa.tab->field("default").tab->field("quiet").type == Type::Table &&
                        aa.tab->field("quiet").type == Type::Nil && !eh.tab->field("custom").b &&
                        eh.tab->field("default").type == Type::Nil && ee.tab->field("custom").b &&
                        ee.tab->field("loud").type == Type::Table && ee.tab->field("loud").tab->field("how").str == "ladder" &&
                        ee.tab->field("a").num == 0 && ee.tab->field("b").num == 4;
        }
        std::vector<Val> back = L.call("VisemeOverride", {Val::number(0), Val::string("")});
        std::vector<Val> t1 = L.call("VisemeTable", {Val::number(0)});
        std::vector<Val> after = L.call("VisemeMouth", {Val::number(0), Val::number(2), Val::number(1), Val::number(0.5),
                                                        Val::number(0), Val::boolean(true)});
        bool reset_ok = t1.size() == 1 && t1[0].type == Type::Table && t1[0].tab->field("custom_spec").str.empty() &&
                        !t1[0].tab->at(2).tab->field("custom").b && t1[0].tab->at(2).tab->field("default").type == Type::Nil;
        CHECK(b2 == 5 && ok.size() == 1 && ok[0].b && custom_ok && cs == "AA=9>10@0.5,EE.loud=ladder@0.4" && reset_ok && L.st.empty(),
              "B2 VisemeTable of the 5 face kinds: table_version 2, custom_spec \"\", every row custom false without default, "
              "mouth_at (%s) (%d of 5); after VisemeOverride(0, \"AA=9>10@0.5,EE.loud=ladder@0.4\"): custom_spec \"%s\", ah "
              "custom with G-SA1's row as default (7>16 and its quiet), its quiet / loud gone, ee custom with its loud a "
              "ladder, eh untouched; after VisemeOverride(0, \"\") none again", at.c_str(), b2, cs.c_str());
        CHECK(num_of(before, 0) == 7 && num_of(before, 1) == 16 && num_of(mine, 0) == 9 && num_of(mine, 1) == 10 &&
                  std::fabs(num_of(mine, 2) - 0.5) < 1e-6 && num_of(other, 0) == 16 && num_of(other, 1) == 8 && back.size() == 1 &&
                  back[0].b && num_of(after, 0) == 7 && num_of(after, 1) == 16 && std::fabs(num_of(after, 2) - 0.45) < 1e-6,
              "B4 VisemeMouth(Sonic, ah): G-SA1's %g>%g before, the override's %g>%g@%.2f after VisemeOverride (with \"Bigger "
              "mouths\" off: yours are never swapped), Tails' untouched (%g>%g), G-SA1's %g>%g@%.2f after VisemeOverride(0, \"\")",
              num_of(before, 0), num_of(before, 1), num_of(mine, 0), num_of(mine, 1), num_of(mine, 2), num_of(other, 0),
              num_of(other, 1), num_of(after, 0), num_of(after, 1), num_of(after, 2));

        // faces_tables.txt (lipsync2_plan.md 5.6): VisemeTable of every face kind, the module's normal form of 40 seeded
        // valid specs, and (review R.8) 30 invalid specs with the module's message - feat_mouths_test.lua's L8b reads it
        std::string txt = "# faces_tables.txt: feature \"faces\" 3 as built (g-sa1 tests/feat_faces_binding_test.cpp, sadc "
                          "docs/research/lipsync2_plan.md 5.6 with its review R.4c / R.8). Tab-separated fields:\n"
                          "#   feature faces <version>\n"
                          "#   table <kind> <keys> <floor> <ladder_cap> <fv_level> <table_version>\n"
                          "#   row <kind> <SOUND> <normal|quiet|loud|plain> <mouth, the grammar's normal form> <how> <expression 0|1>\n"
                          "#   anchor <kind> <forward> <up>\n"
                          "#   spec <kind> <the spec as given> <the module's normal form (VisemeTable(kind).custom_spec)>\n"
                          "#   bad <kind> <the spec as given> <code> <the module's message>\n";
        txt += gsa1::format("feature\tfaces\t%g\n", feats.tab->field("faces").num);
        static const char *const vname[4] = {"normal", "quiet", "loud", "plain"};
        int rows_written = 0;
        for (int k : {0, 2, 3, 5, 7}) {
            std::vector<Val> t = L.call("VisemeTable", {Val::number(k)});
            if (t.size() != 1 || t[0].type != Type::Table) continue;
            const Table &tt = *t[0].tab;
            txt += gsa1::format("table\t%d\t%g\t%.4g\t%.4g\t%.4g\t%g\n", k, tt.field("keys").num, tt.field("floor").num,
                                tt.field("ladder_cap").num, tt.field("fv_level").num, tt.field("table_version").num);
            for (int c = 2; c < 9; c++) {
                const Val &row = tt.at(c);
                for (int v = 0; v < 4; v++) {
                    const Val e = v == 0 ? row : row.tab->field(vname[v]);
                    if (e.type != Type::Table) continue;
                    gsa1::mouth::Entry me;
                    me.a = (int)e.tab->field("a").num;
                    me.b = (int)e.tab->field("b").num;
                    me.w = (float)e.tab->field("w").num;
                    const std::string how = e.tab->field("how").str;
                    me.how = how == "scales" ? gsa1::mouth::SCALES : how == "fixed" ? gsa1::mouth::FIXED
                             : how == "ladder" ? gsa1::mouth::LADDER : gsa1::mouth::CLOSED;
                    txt += gsa1::format("row\t%d\t%s\t%s\t%s\t%s\t%d\n", k, gsa1::viseme::name(c), vname[v],
                                        gsa1::mouth::mouth_text(me).c_str(), how.c_str(), e.tab->field("expression").b ? 1 : 0);
                    rows_written++;
                }
            }
            Val ma = tt.field("mouth_at");
            if (ma.type == Type::Table) {
                txt += gsa1::format("anchor\t%d\t%.4g\t%.4g\n", k, ma.tab->field("forward").num, ma.tab->field("up").num);
            }
        }
        // 40 seeded valid specs (every grammar form; the M1 cases first)
        std::vector<std::pair<int, std::string>> specs = {
            {0, "AA=7>16@0.45"}, {0, "AA=7>16@0.45:fixed,AA.loud=16"}, {0, "OO=6:scales"}, {0, "FV=ladder@0.25"},
            {0, "EE=ladder"}, {0, ""}, {0, "AA=20"}, {7, "AA=7"}, {0, "EE=0>17@0.8:scales,AA.loud=7>16@0.7"},
            {2, "OO=0>5@1.0,SS.quiet=ladder@1"}};
        uint32_t rng = 20261027u;
        auto rnd = [&rng](uint32_t n) {
            rng = rng * 1664525u + 1013904223u;
            return (rng >> 8) % n;
        };
        static const char *const snd[7] = {"AA", "EH", "EE", "OH", "OO", "SS", "FV"};
        static const char *const var[3] = {"", ".quiet", ".loud"};
        static const int face_kinds[5] = {0, 2, 3, 5, 7};
        while (specs.size() < 40) {
            int k = face_kinds[rnd(5)];
            int keys = gsa1::mouth::default_table(k)->keys;
            std::vector<std::string> items;
            for (int c = 0; c < 7; c++) {
                for (int v = 0; v < 3; v++) {
                    if (rnd(5) != 0) continue;
                    std::string m;
                    switch (rnd(6)) {
                    case 0: m = std::to_string(rnd(keys)); break;
                    case 1: m = gsa1::format("0>%u@1", rnd(keys)); break;
                    case 2: m = gsa1::format("%u>%u@0.%u", rnd(keys), rnd(keys), rnd(10000)); break;
                    case 3: m = rnd(2) ? "ladder" : gsa1::format("ladder@0.%u", rnd(1000)); break;
                    case 4: m = gsa1::format("%u>%u@1.0000:scales", rnd(keys), rnd(keys)); break;
                    default: m = gsa1::format("%u:%s", rnd(keys), rnd(2) ? "fixed" : "scales"); break;
                    }
                    items.push_back(std::string(snd[c]) + var[v] + "=" + m);
                }
            }
            for (size_t i = items.size(); i > 1; i--) std::swap(items[i - 1], items[rnd((uint32_t)i)]);
            std::string sp;
            for (size_t i = 0; i < items.size(); i++) sp += (i ? "," : "") + items[i];
            specs.push_back({k, sp});
        }
        int spec_ok = 0;
        for (const auto &sp : specs) {
            std::vector<Val> r = L.call("VisemeOverride", {Val::number(sp.first), Val::string(sp.second)});
            std::vector<Val> t = L.call("VisemeTable", {Val::number(sp.first)});
            std::string nf = t.size() == 1 && t[0].type == Type::Table ? t[0].tab->field("custom_spec").str : "?";
            spec_ok += r.size() == 1 && r[0].b;
            txt += gsa1::format("spec\t%d\t%s\t%s\n", sp.first, sp.second.c_str(), nf.c_str());
            L.call("VisemeOverride", {Val::number(sp.first), Val::string("")});
        }
        // 30 invalid specs: M2's list (the faceless kind included) and review R.8's numeric edge cases
        std::string i25, s513b = "AA=7>16@0.45";
        static const char *const var4[4] = {"", ".quiet", ".loud", ".quiet"};
        for (int i = 0; i < 25; i++) i25 += gsa1::format("%s%s%s=4", i ? "," : "", snd[i % 7], var4[i / 7]);
        while (s513b.size() < 513) s513b += ",";
        std::vector<std::pair<int, std::string>> bads = {
            {0, "SIL=4"}, {0, "MBP=0"}, {0, "XX=4"}, {0, "AA.soft=4"}, {0, "AA=21"}, {7, "AA=8"}, {0, "AA=4>16@1.5"},
            {0, "AA=4>16@-0.1"}, {0, "AA=4>16@nan"}, {0, "AA=4>"}, {0, "AA=4>16"}, {0, "AA=4,AA=5"}, {0, i25}, {0, s513b},
            {6, "AA=4"}, {0, "AA=-1"}, {0, "AA=+4"}, {0, "AA=007"}, {0, "AA=4294967300"}, {0, "AA=7>16@.5"},
            {0, "AA=7>16@1e-1"}, {0, "AA=7>16@0.12345"}, {0, " AA=4"}, {0, "AA=4,"}, {0, ",AA=4"}, {0, "AA=4,,EE=4"},
            {0, "AA.normal=4"}, {0, "AA=7>16@0.5:scale"}, {7, "AA=4>8@0.5"}, {7, "AA=ladder@2"}};
        int bad_ok = 0;
        for (const auto &b : bads) {
            std::vector<Val> r = L.call("VisemeOverride", {Val::number(b.first), Val::string(b.second)});
            std::vector<Val> t = L.call("VisemeTable", {Val::number(b.first)});
            bool unchanged = b.first == 6 || (t.size() == 1 && t[0].type == Type::Table && t[0].tab->field("custom_spec").str.empty());
            bad_ok += is_nil_msg(r) && unchanged;
            txt += gsa1::format("bad\t%d\t%s\t%s\t%s\n", b.first, b.second.c_str(), str_of(r, 2).c_str(), str_of(r, 1).c_str());
        }
        std::string where = gsa1::join_path(self.empty() ? std::string(".") : self, "faces_tables.txt"), werr;
        bool wrote = gsa1::write_file_replace(where, txt, werr);
        CHECK(wrote && spec_ok == 40 && bad_ok == 30 && bads.size() == 30 && rows_written > 40 && L.st.empty(),
              "faces_tables.txt written next to the test (%s): the 5 face kinds' rows (%d entries), 40 seeded valid specs with "
              "the module's normal form (%d accepted), 30 invalid ones with its message (%d refused, nothing changed) - for "
              "feat_mouths_test.lua's L8b%s%s", where.c_str(), rows_written, spec_ok, bad_ok, werr.empty() ? "" : ": ",
              werr.c_str());
    }

    // ---- the microphone with a fake BASS -------------------------------------------------------------------------------
    gsa1::mic::set_test_api(&k_fake);
    std::vector<Val> md = L.call("MicDevices", {});
    bool devs = md.size() == 1 && md[0].type == Type::Table && md[0].tab->at(1).type == Type::Table &&
                md[0].tab->at(1).tab->field("name").str == "Headset Microphone" &&
                md[0].tab->at(1).tab->field("default").b && md[0].tab->at(1).tab->field("enabled").b &&
                md[0].tab->at(2).type == Type::Table && !md[0].tab->at(2).tab->field("enabled").b &&
                md[0].tab->at(3).type == Type::Nil;
    std::vector<Val> lv0 = L.call("MicLevel", {});
    std::vector<Val> mo = L.call("MicOpen", {Val::number(-1)});
    std::vector<Val> lv1 = L.call("MicLevel", {});
    CHECK(devs && str_of(lv0, 2) == "off" && mo.size() == 1 && mo[0].b && str_of(lv1, 2) == "paused" &&
              g_fake.inits == 1 && g_fake.starts == 1 && g_fake.start_rate == 16000 && g_fake.start_chans == 1 &&
              (g_fake.start_flags & 0xFFFFu) == (gsa1::mic::kSampleFloat | gsa1::mic::kRecordPause) &&
              (g_fake.start_flags >> 16) == 10,
          "MicDevices lists the fake's two devices; MicOpen(-1): RecordInit, RecordStart(16000 Hz, mono, float, paused, "
          "a 10 ms period); MicLevel \"off\" before, \"paused\" after");
    L.call("MicListen", {Val::boolean(true)});
    block(0.1);       // RMS 0.1 = -20 dBFS
    std::vector<Val> lv2 = L.call("MicLevel", {});
    double lvl = num_of(lv2, 0), pk = num_of(lv2, 1);
    block(0.0);
    std::vector<Val> lv3 = L.call("MicLevel", {});
    CHECK(g_fake.plays == 1 && std::fabs(lvl - 0.80) <= 0.02 && std::fabs(pk - 0.1414) <= 0.005 && str_of(lv2, 2) == "on" &&
              num_of(lv3, 0) == 0.0 && gsa1::mic::blocks() == 2,
          "MicListen(true): a 1 kHz sine with an RMS of -20 dBFS -> level %.3f (0.80 +- 0.02), peak %.4f; silence -> %.3f",
          lvl, pk, num_of(lv3, 0));
    L.call("MicListen", {Val::boolean(false)});
    uint64_t nb = gsa1::mic::blocks();
    block(0.1);
    block(0.1);
    std::vector<Val> lv4 = L.call("MicLevel", {});
    CHECK(g_fake.pauses == 1 && gsa1::mic::blocks() == nb && str_of(lv4, 2) == "paused" && num_of(lv4, 0) == 0.0,
          "MicListen(false): ChannelPause; blocks delivered afterwards are not counted (%llu)",
          (unsigned long long)gsa1::mic::blocks());
    std::vector<Val> mc = L.call("MicClose", {});
    CHECK(mc.size() == 1 && mc[0].b && g_fake.stops == 1 && g_fake.frees == 1 && str_of(L.call("MicLevel", {}), 2) == "off",
          "MicClose: ChannelStop and RecordFree (it initialised the device)");
    // BASS_ERROR_ALREADY: Garry's Mod has the device: RecordSetDevice, never freed
    g_fake = Fake();
    g_fake.init_result = 0;
    g_fake.init_error = gsa1::mic::kErrorAlready;
    mo = L.call("MicOpen", {Val::number(-1)});
    bool here = gsa1::mic::initialised_here();
    L.call("MicClose", {});
    CHECK(mo.size() == 1 && mo[0].b && g_fake.set_devices == 1 && g_fake.last_set_device == 0 && !here &&
              g_fake.starts == 1 && g_fake.stops == 1 && g_fake.frees == 0,
          "BASS_ERROR_ALREADY: RecordSetDevice(the default device 0), started; MicClose stops it and frees nothing");
    // an init failure
    g_fake = Fake();
    g_fake.init_result = 0;
    g_fake.init_error = gsa1::mic::kErrorBusy;
    mo = L.call("MicOpen", {Val::number(0)});
    std::vector<Val> lv5 = L.call("MicLevel", {});
    std::vector<Val> ml = L.call("MicListen", {Val::boolean(true)});
    CHECK(is_nil_msg(mo) && str_of(lv5, 2).compare(0, 8, "failed: ") == 0 &&
              str_of(lv5, 2).find("Privacy") != std::string::npos && is_nil_msg(ml) && g_fake.starts == 0,
          "an init failure (busy): MicOpen -> nil, message; MicLevel \"%s\"; MicListen -> nil, message", str_of(lv5, 2).c_str());
    L.call("MicClose", {});
    // 0.9.4c: the classifier through the binding: off -> -1; on, a press, one block -> a frame (seq +1)
    g_fake = Fake();
    mo = L.call("MicOpen", {Val::number(-1)});
    L.call("MicListen", {Val::boolean(true)});
    L.call("MicVisemeOn", {Val::boolean(false)});
    block(0.1);
    std::vector<Val> v0 = L.call("MicViseme", {});
    L.call("MicVisemeOn", {Val::boolean(true)});
    std::vector<Val> v1 = L.call("MicViseme", {});
    block(0.1);
    std::vector<Val> v2 = L.call("MicViseme", {});
    block(0.1);
    std::vector<Val> v3 = L.call("MicViseme", {});
    L.call("MicListen", {Val::boolean(false)});
    std::vector<Val> v4 = L.call("MicViseme", {});
    L.call("MicClose", {});
    std::vector<Val> vc = L.call("MicVisemeVoice", {});
    CHECK(mo.size() == 1 && mo[0].b && num_of(v0, 0) == -1 && num_of(v1, 0) == -1 && num_of(v2, 0) >= 0 &&
              num_of(v2, 0) <= 8 && num_of(v3, 5) == std::fmod(num_of(v2, 5) + 1, 65536) && num_of(v4, 0) == -1 &&
              num_of(v2, 1) >= 0 && num_of(v2, 1) <= 1 && num_of(vc, 1) == 0,
          "MicViseme with the fake microphone: -1 with the analysis off and before the press' first frame, then a frame "
          "(cls %g, level %.2f, seq %g -> %g), -1 paused; MicClose (the session's end) forgets the speaker number (%g frames)",
          num_of(v2, 0), num_of(v2, 1), num_of(v2, 5), num_of(v3, 5), num_of(vc, 1));

    // ---- 0.9.4e: the microphone's loopback devices, the forced re-open, the warm-up and the features (B5 - B8) ---------
    std::string txt_loopback, txt_engine1, txt_adapt0, txt_closed;
    {
        // B5 MicDevices with a loopback device at 6 (invented names)
        g_fake = Fake();
        g_fake.ndev = 7;
        std::vector<Val> d7 = L.call("MicDevices", {});
        int lb_ok = 0, lb_n = 0;
        std::string lb_name;
        if (d7.size() == 1 && d7[0].type == Type::Table) {
            for (int i = 1; i <= 8; i++) {
                const Val e = d7[0].tab->at(i);
                if (e.type != Type::Table) continue;
                lb_n++;
                bool want = e.tab->field("index").num == 6;
                lb_ok += e.tab->field("loopback").type == Type::Bool && e.tab->field("loopback").b == want;
                if (want) lb_name = e.tab->field("name").str;
            }
        }
        CHECK(lb_n == 7 && lb_ok == 7 && lb_name == "Speakers (Example Audio)" && L.st.empty(),
              "B5 MicDevices through the fake BASS (7 invented devices; \"%s\" at 6 with BASS's flag 8): its loopback is true, "
              "the 6 others false (%d of %d)", lb_name.c_str(), lb_ok, lb_n);

        // B6 MicOpen(6) refused with nothing opened; an input opened, again (nothing new), forced (RecordStart again);
        // MicLevel's four values
        int inits0 = g_fake.inits, starts0 = g_fake.starts;
        std::vector<Val> o6 = L.call("MicOpen", {Val::number(6)});
        bool nothing = g_fake.inits == inits0 && g_fake.starts == starts0;
        std::vector<Val> lvx = L.call("MicLevel", {});
        std::vector<Val> o2 = L.call("MicOpen", {Val::number(2)});
        int starts1 = g_fake.starts;
        std::vector<Val> o2a = L.call("MicOpen", {Val::number(2)});
        int starts2 = g_fake.starts;
        std::vector<Val> o2f = L.call("MicOpen", {Val::number(2), Val::boolean(true)});
        int starts3 = g_fake.starts;
        std::vector<Val> obad = L.call("MicOpen", {Val::number(2), Val::string("yes")});
        L.call("MicListen", {Val::boolean(true)});
        block(0.1);
        block(0.1);
        block(0.1);
        std::vector<Val> lv4 = L.call("MicLevel", {});
        txt_loopback = str_of(o6, 1);
        CHECK(is_nil_msg(o6) && str_of(o6, 2) == "unsupported" &&
                  txt_loopback == "that device records what your PC plays (a speaker output), not a microphone" && nothing &&
                  lvx.size() == 4 && str_of(lvx, 2) == "off" && o2.size() == 1 && o2[0].b && starts1 == starts0 + 1 &&
                  o2a.size() == 1 && o2a[0].b && starts2 == starts1 && o2f.size() == 1 && o2f[0].b && starts3 == starts2 + 1 &&
                  is_nil_msg(obad) && str_of(obad, 2) == "bad_argument" && lv4.size() == 4 && lv4[3].type == Type::Number &&
                  num_of(lv4, 3) >= 3 && L.st.empty(),
              "B6 MicOpen(6) -> nil, \"%s\", \"unsupported\" with nothing opened (MicLevel still \"off\"); MicOpen(2) opens, "
              "again changes nothing, MicOpen(2, true) re-opens (RecordStart %d -> %d -> %d); a non-boolean force -> "
              "\"bad_argument\"; MicLevel returns level, peak, state, blocks (%g after 3 blocks)", txt_loopback.c_str(),
              starts1, starts2, starts3, num_of(lv4, 3));

        // B7 the warm-up: allowed with engine 2, "Learn my voice" and the microphone open; its refusals
        L.call("MicVisemeTune", {Val::string("engine"), Val::number(2)});
        L.call("MicVisemeTune", {Val::string("adapt"), Val::number(1)});
        L.call("MicVisemeOn", {Val::boolean(true)});
        block(0.1);
        int acc = 0, steps = 0;
        std::string acc_why;
        for (const char *w : {"ah", "gap", "ee", "gap", "oo", "gap", "oh", "done", "cancel"}) {
            std::vector<Val> r = L.call("MicVisemeWarmup", {Val::string(w)});
            steps++;
            bool ok = r.size() == 1 && r[0].type == Type::Bool && r[0].b;
            acc += ok;
            if (!ok && acc_why.empty()) acc_why = std::string(w) + ": " + str_of(r, 1);
            block(0.1);
        }
        std::vector<Val> ws = L.call("MicVisemeWarmupState", {});
        bool ws_nums = ws.size() == 6;
        for (const Val &v : ws) ws_nums = ws_nums && v.type == Type::Number;
        L.call("MicVisemeTune", {Val::string("engine"), Val::number(1)});
        block(0.1);
        std::vector<Val> r1 = L.call("MicVisemeWarmup", {Val::string("ah")});
        L.call("MicVisemeTune", {Val::string("engine"), Val::number(2)});
        L.call("MicVisemeTune", {Val::string("adapt"), Val::number(0)});
        block(0.1);
        std::vector<Val> r2 = L.call("MicVisemeWarmup", {Val::string("ah")});
        L.call("MicVisemeTune", {Val::string("adapt"), Val::number(1)});
        block(0.1);
        std::vector<Val> rb = L.call("MicVisemeWarmup", {Val::string("eh")});
        std::vector<Val> rn = L.call("MicVisemeWarmup", {Val::number(1)});
        std::vector<Val> re3 = L.call("MicVisemeTune", {Val::string("engine"), Val::number(3)});
        std::vector<Val> vv5 = L.call("MicVisemeVoice", {});
        std::vector<Val> vf9 = L.call("MicVisemeFeatures", {});
        L.call("MicClose", {});
        std::vector<Val> r3 = L.call("MicVisemeWarmup", {Val::string("ah")});
        txt_engine1 = str_of(r1, 1);
        txt_adapt0 = str_of(r2, 1);
        txt_closed = str_of(r3, 1);
        bool nums5 = vv5.size() == 5, nums9 = vf9.size() == 9;
        for (const Val &v : vv5) nums5 = nums5 && v.type == Type::Number;
        for (const Val &v : vf9) nums9 = nums9 && v.type == Type::Number;
        bool refusals = is_nil_msg(r1) && str_of(r1, 2) == "unsupported" && txt_engine1 == "needs 'Sound detection' 0.9.4e" &&
                        is_nil_msg(r2) && str_of(r2, 2) == "unsupported" && txt_adapt0 == "needs 'Learn my voice'" &&
                        is_nil_msg(r3) && str_of(r3, 2) == "unsupported" && txt_closed == "the microphone is not open" &&
                        is_nil_msg(rb) && str_of(rb, 2) == "bad_argument" && is_nil_msg(rn) && str_of(rn, 2) == "bad_argument" &&
                        is_nil_msg(re3) && str_of(re3, 2) == "bad_argument";
        CHECK(ws_nums && is_nil_msg(rb) && str_of(rb, 2) == "bad_argument" && is_nil_msg(rn) && str_of(rn, 2) == "bad_argument" &&
                  is_nil_msg(re3) && str_of(re3, 2) == "bad_argument" && nums5 && nums9 && L.st.empty(),
              "B7 MicVisemeWarmup(\"eh\"), (1) and MicVisemeTune(\"engine\", 3) -> \"bad_argument\"; MicVisemeWarmupState six "
              "numbers, MicVisemeVoice five, MicVisemeFeatures nine");
        CHECK(acc == steps && num_of(ws, 0) == -1 && num_of(ws, 5) == 3 && refusals && num_of(vv5, 4) == 0,
              "B7 MicVisemeWarmup: ah gap ee gap oo gap oh done cancel accepted with engine 2, \"Learn my voice\" and the "
              "microphone open (%d of %d%s%s); MicVisemeWarmupState after cancel: phase %g, result %g (3 stopped); refused "
              "\"unsupported\": engine 1 (\"%s\"), adapt 0 (\"%s\"), closed (\"%s\"); warmed %g", acc, steps,
              acc_why.empty() ? "" : "; first refusal ", acc_why.c_str(), num_of(ws, 0), num_of(ws, 5), txt_engine1.c_str(),
              txt_adapt0.c_str(), txt_closed.c_str(), num_of(vv5, 4));

        // B8 the per-frame functions: 10,000 calls each - the frame balanced (the arguments + the declared returns), no
        // table created, numbers (MicLevel's state: a string), nothing thrown (a Lua error ends the test)
        g_fake = Fake();
        L.call("MicOpen", {Val::number(-1)});
        L.call("MicListen", {Val::boolean(true)});
        L.call("MicVisemeOn", {Val::boolean(true)});
        block(0.1);
        struct PF {
            const char *name;
            size_t n;
            std::vector<Val> args;
        };
        const PF pfs[] = {{"MicViseme", 6, {}},
                          {"MicVisemeFeatures", 9, {}},
                          {"MicVisemeWarmupState", 6, {}},
                          {"MicVisemeVoice", 5, {}},
                          {"MicLevel", 4, {}},
                          {"VisemeMouth", 3, {Val::number(0), Val::number(2), Val::number(0.7), Val::number(0.5), Val::number(0),
                                              Val::boolean(true)}}};
        uint64_t tables0 = L.tables;
        size_t unbalanced = 0, wrong = 0, calls = 0;
        Val gt = L.globals.tab->field("gsa1");
        for (const PF &pf : pfs) {
            Val fn = gt.tab->field(pf.name);
            for (int i = 0; i < 10000; i++) {
                if (i % 1000 == 0) block(0.05);
                std::vector<Val> saved;
                saved.swap(L.st);
                L.st = pf.args;
                int n = fn.fn ? fn.fn(L.state) : -1;
                unbalanced += n < 0 || (size_t)n != pf.n || L.st.size() != pf.args.size() + pf.n;
                for (size_t k = pf.args.size(); k < L.st.size(); k++) {
                    const Val &v = L.st[k];
                    wrong += !(v.type == Type::Number || (std::string(pf.name) == "MicLevel" && k == pf.args.size() + 2 &&
                                                          v.type == Type::String));
                }
                L.st.swap(saved);
                calls++;
            }
        }
        L.call("MicClose", {});
        CHECK(unbalanced == 0 && wrong == 0 && L.tables == tables0 && calls == 60000 && L.st.empty(),
              "B8 MicViseme, MicVisemeFeatures, MicVisemeWarmupState, MicVisemeVoice, MicLevel, VisemeMouth: %zu calls, the "
              "frame balanced in all but %zu, %zu non-number results, %llu tables created", calls, unbalanced, wrong,
              (unsigned long long)(L.tables - tables0));
    }
    gsa1::mic::set_test_api(nullptr);
    CHECK(std::fabs(gsa1::mic::level_of_rms(1.0f) - 1.0f) < 1e-6 && gsa1::mic::level_of_rms(0.001f) < 1e-4f &&
              std::fabs(gsa1::mic::level_of_rms(0.0316228f) - 0.6f) < 1e-3 && gsa1::mic::level_of_rms(0.0f) == 0.0f,
          "the mapping: 0 dBFS -> 1, -60 dBFS -> 0, -30 dBFS -> 0.60, silence 0");

    {
        // faces2_api.txt (review R.11): the new functions as built - each line only for a function that is registered and
        // whose returns were seen above - and the new constants as the module set them
        struct Fn {
            const char *name, *args, *rets;
        };
        const Fn api[] = {{"MicViseme", "", "cls, level, f1, f2, conf, seq"},
                          {"MicVisemeOn", "on", "true | nil, message, code"},
                          {"MicVisemeTune", "name, value", "true | nil, message, code"},
                          {"MicVisemeVoice", "", "g, frames, f1, f2, warmed"},
                          {"VisemeMouth", "kind, cls, s, size, variant, big", "a, b, w"},
                          {"VisemeTable", "kind", "table | nil, message, code"},
                          {"FaceMouth", "id, key_a, key_b, weight, [flags]", "nothing"},
                          {"FaceLevel", "id, level, style, [flags]", "nothing"},
                          // 0.9.4e (feature "faces" 3)
                          {"MicDevices", "", "table | nil, message, code"},
                          {"MicOpen", "device, [force]", "true | nil, message, code"},
                          {"MicLevel", "", "level, peak, state, blocks"},
                          {"MicVisemeWarmup", "step", "true | nil, message, code"},
                          {"MicVisemeWarmupState", "", "phase, n_ah, n_ee, n_oo, n_oh, result"},
                          {"MicVisemeFeatures", "", "rel_loc, per, nbr, eep, cat, raw, seq, lowr, zcr"},
                          {"VisemeOverride", "kind, spec", "true | nil, message, code"}};
        std::string txt = "# faces2_api.txt: feature \"faces\" as built (g-sa1 tests/feat_faces_binding_test.cpp V9 / B1-B8, "
                          "sadc docs/research/phoneme_plan.md review R.11, lipsync2_plan.md 5.5 / 5.6)\n"
                          "# fn <Name>(<args in order>, [<optional>]) -> <returns>; const <TABLE>.<KEY> <value>; tune <name> "
                          "<range>; field <table> <fields>; step <Name> <words>; text <Name>.<case> <message>; result <Name> "
                          "<value> <meaning>\n";
        txt += gsa1::format("feature faces %g\n", feats.tab->field("faces").num);
        txt += gsa1::format("const FEATURES.faces %g\n", feats.tab->field("faces").num);
        for (const Fn &f : api) {
            if (g.tab->field(f.name).type == Type::Function) {
                txt += gsa1::format("fn %s(%s) -> %s\n", f.name, f.args, f.rets);
            }
        }
        Val VI2 = g.tab->field("VISEME");
        for (int k = 0; k < gsa1::viseme::COUNT; k++) {
            txt += gsa1::format("const VISEME.%s %g\n", gsa1::viseme::name(k), VI2.tab->field(gsa1::viseme::name(k)).num);
        }
        txt += gsa1::format("const VISEME.COUNT %g\n", VI2.tab->field("COUNT").num);
        for (int k = 0; k < gsa1::viseme::COUNT; k++) {
            txt += gsa1::format("const VISEME.NAMES[%d] %s\n", k, VI2.tab->field("NAMES").tab->at(k).str.c_str());
        }
        for (int k = 0; k < gsa1::viseme::COUNT; k++) {
            txt += gsa1::format("const VISEME.WORDS[%d] %s\n", k, VI2.tab->field("WORDS").tab->at(k).str.c_str());
        }
        Val K2 = g.tab->field("FACE");
        for (const char *c : {"LEVEL_LADDER", "LEVEL_TALK", "MOUTH", "SAME_PAIR"}) {
            if (K2.tab->field(c).type == Type::Number) {
                txt += gsa1::format("const FACE.%s %g\n", c, K2.tab->field(c).num);
            }
        }
        txt += "tune gate_min_db 3..12\ntune adapt 0..1\ntune smooth 0..3\ntune engine 1..2\ntune reset_voice\n";
        txt += "field VisemeTable kind keys floor ladder_cap fv_level table_version custom_spec mouth_at\n";
        txt += "field VisemeTable.row a b w how expression quiet loud plain custom default\n";
        // 0.9.4e: the rest of feature "faces" 3 as the calls above returned it
        txt += "field VisemeTable.row.default a b w how expression quiet loud plain\n";
        txt += "field VisemeTable.mouth_at forward up\n";
        txt += "field MicDevices.entry index name default enabled loopback\n";
        txt += "const TABLE_VERSION 2\n";
        txt += "step MicVisemeWarmup ah ee oo oh gap done cancel\n";
        txt += "result MicVisemeWarmupState.phase -1 none, 0 ah, 1 ee, 2 oo, 3 oh, 4 gap\n";
        txt += "result MicVisemeWarmupState.result 0 none, 1 learned, 2 too short, 3 stopped, 4 unclear\n";
        txt += "text MicOpen.loopback " + txt_loopback + "\n";
        txt += "text MicVisemeWarmup.engine1 " + txt_engine1 + "\n";
        txt += "text MicVisemeWarmup.adapt0 " + txt_adapt0 + "\n";
        txt += "text MicVisemeWarmup.closed " + txt_closed + "\n";
        txt += "code MicOpen.loopback unsupported\ncode MicVisemeWarmup.refused unsupported\ncode MicVisemeWarmup.word "
               "bad_argument\ncode VisemeOverride.spec bad_argument\ncode VisemeOverride.faceless unsupported\n";
        std::string where = gsa1::join_path(self.empty() ? std::string(".") : self, "faces2_api.txt"), werr;
        bool wrote = gsa1::write_file_replace(where, txt, werr);
        CHECK(wrote, "faces2_api.txt written next to the test (%s; %d lines) for the Lua lane's P13%s%s", where.c_str(),
              (int)std::count(txt.begin(), txt.end(), '\n'), werr.empty() ? "" : ": ", werr.c_str());
    }
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the disc checks are skipped\n");
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
    CHECK(st == "ready", "the disc (%s)", st.c_str());
    // FaceInfo for every kind, without a world
    struct Want {
        int kind;
        double keys, letters;
        const char *ladder;
    };
    // 0.9.4c: the per-character ladders by the measured mouth opening (phoneme_plan.md 4.6; Tikal unchanged)
    const Want want[] = {{0, 21, 0x7FFFFFFF, "0,4,16"}, {1, 0, 0, ""}, {2, 20, 0x7FFFFFFF, "0,4,7,8"},
                         {3, 20, 0x7FFFFFFF, "0,4,7,16"}, {4, 20, 0x7FFFFFFF, "0,5,4,6,7"},
                         {5, 20, 0x7FFFFFFF, "0,7,4,8,16"}, {6, 0, 0, ""}, {7, 8, 0x01FC0C1F, "0,4,5"}, {8, 0, 0, ""}};
    int good = 0;
    std::string got;
    for (const Want &w : want) {
        auto t0 = std::chrono::steady_clock::now();
        std::vector<Val> r = L.call("FaceInfo", {Val::number(w.kind)});
        double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        if (r.size() == 1 && r[0].type == Type::Table) {
            const Table &t = *r[0].tab;
            bool ok = t.field("keys").num == w.keys && t.field("letters").num == w.letters &&
                      t.field("has_face").b == (w.keys > 0) && (w.keys == 0 || t.field("ladder").str == w.ladder) &&
                      t.field("steps").type == Type::Table && t.field("steps").tab->at(2).num == 48 &&
                      t.field("first").tab->at(2).num == 5 && t.field("last").tab->at(25).num == 8 &&
                      t.field("steps").tab->at(30).num == 182 && t.field("first").tab->at(27).num == 10;
            good += ok;
            got += gsa1::format("%s%d: %g keys 0x%08X %s (%.0f ms)", got.empty() ? "" : "; ", w.kind, t.field("keys").num,
                                (unsigned)t.field("letters").num, t.field("ladder").str.c_str(), ms);
        } else {
            got += gsa1::format("%s%d: %s", got.empty() ? "" : "; ", w.kind, str_of(r, 1).c_str());
        }
    }
    CHECK(good == 9, "FaceInfo without a world for every kind (Sonic 21 keys, Big 8 keys 0x01FC0C1F, E-102 / Eggman / Super "
          "Sonic none; the ladders Sonic 0,4,16, Tails 0,4,7,8, Knuckles 0,4,7,16, Amy 0,7,4,8,16, Big 0,4,5; C 48 steps, "
          "first 5; Z ends on key 8; e 182 steps): %s", got.c_str());
    // 0.9.4c: every key of the mouth table below the character's own key count
    {
        int keyed = 0, below = 0;
        for (int kind : {0, 2, 3, 5, 7}) {
            std::vector<Val> fi = L.call("FaceInfo", {Val::number(kind)});
            std::vector<Val> tb = L.call("VisemeTable", {Val::number(kind)});
            if (fi.size() != 1 || fi[0].type != Type::Table || tb.size() != 1 || tb[0].type != Type::Table) continue;
            double keys = fi[0].tab->field("keys").num;
            for (int c = 0; c < 9; c++) {
                const Val &row = tb[0].tab->at(c);
                for (const char *sub : {"", "quiet", "loud", "plain"}) {
                    const Val e = *sub ? row.tab->field(sub) : row;
                    if (e.type != Type::Table || e.tab->field("how").str == "ladder") continue;
                    keyed++;
                    below += e.tab->field("a").num >= 0 && e.tab->field("a").num < keys && e.tab->field("b").num >= 0 &&
                             e.tab->field("b").num < keys;
                }
            }
        }
        CHECK(keyed > 0 && below == keyed, "every VisemeTable key is below FaceInfo(kind).keys (%d of %d entries)", below, keyed);
    }
    std::string map;
    if (!gsa1::read_small_file(bsp, 512u << 20, map, err) || map.empty()) {
        std::printf("  info  no gm_construct (%s): the character checks are skipped\n", bsp.c_str());
        gmod13_close(&state);
        std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
        return g_fail ? 1 : 0;
    }
    std::vector<Val> wl = L.call("WorldLoadData", {Val::string(map), Val::string("gm_construct")});
    CHECK(wl.size() == 2 && wl[0].b, "WorldLoadData(gm_construct)");
    const Val pos = Val::vector(704, 132, -139);
    std::vector<Val> c0 = L.call("Create", {Val::number(0), pos, Val::number(180)});
    double id0 = num_of(c0, 0);
    pairs_of(L, id0, 4);
    std::vector<Val> s0 = L.call("FaceState", {Val::number(id0)});
    std::vector<Val> m1 = L.call("FaceMode", {Val::number(id0), Val::boolean(true), Val::boolean(false)});
    pairs_of(L, id0, 3);
    std::vector<Val> s1 = L.call("FaceState", {Val::number(id0)});
    std::vector<Val> q1 = L.call("FaceSequence", {Val::number(id0), Val::string("Z:6:30"), Val::number(0)});
    pairs_of(L, id0, 4);
    std::vector<Val> s2 = L.call("FaceState", {Val::number(id0)});
    L.call("FaceLevel", {Val::number(id0), Val::number(1.0), Val::number(0)});
    CHECK(id0 > 0 && s0.size() == 7 && num_of(s0, 0) == 0 && num_of(s0, 5) == -1 && m1.size() == 1 && m1[0].b &&
              num_of(s1, 0) == SA1_FACE_MODE_EVENT && s1[1].b && q1.size() == 1 && q1[0].b && num_of(s2, 3) == 8 &&
              num_of(s2, 6) == SA1_FACE_ACT_SEQUENCE && L.st.empty(),
          "Sonic: FaceState before any call (mode 0, letter -1), FaceMode(event) -> mode %g, the EV head shown; "
          "FaceSequence(\"Z:6:30\") -> to %g (key 8), activity %g", num_of(s1, 0), num_of(s2, 3), num_of(s2, 6));
    L.call("Destroy", {Val::number(id0)});
    std::vector<Val> c7 = L.call("Create", {Val::number(7), pos, Val::number(180)});
    double id7 = num_of(c7, 0);
    pairs_of(L, id7, 2);
    std::vector<Val> b1 = L.call("FaceSequence", {Val::number(id7), Val::string("b:10:90"), Val::number(0)});
    std::vector<Val> b2 = L.call("FaceSequence", {Val::number(id7), Val::string("C:0:0,A:8:0"), Val::number(0)});
    L.call("Destroy", {Val::number(id7)});
    std::vector<Val> c6 = L.call("Create", {Val::number(6), pos, Val::number(180)});
    double id6 = num_of(c6, 0);
    pairs_of(L, id6, 2);
    std::vector<Val> g1 = L.call("FaceMode", {Val::number(id6), Val::boolean(true), Val::boolean(false)});
    L.call("Destroy", {Val::number(id6)});
    CHECK(id7 > 0 && is_nil_msg(b1) && str_of(b1, 2) == "unsupported" && str_of(b1, 1).find("b") != std::string::npos &&
              b2.size() == 1 && b2[0].b && id6 > 0 && is_nil_msg(g1) && str_of(g1, 2) == "unsupported",
          "Big: 'b' refused (\"%s\"), 'C' then 'A' taken; E-102: FaceMode refused (\"%s\")", str_of(b1, 1).c_str(),
          str_of(g1, 1).c_str());
    gmod13_close(&state);
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
#endif
}
