// feat_board_test: the board feature's core (round 0.9.5: sadc docs/research/gsa1_095_plan.md 4.10-4.12, 5.3 / 5.4 and 6.3
// task 7 with its Review R.12; board095_gsa1.md 4.4, 10) - src/core/board.{hpp,cpp} and the session's board parts
// (session.cpp board_rules / board_after_tick / set_board_sounds / admit_sound, session.hpp kBatchBoardFlag) - offline,
// linked like core_test (the core and libsa1) by build.py and run with --gdi when there is one.
//
//   feat_board_test [--gdi GAME.gdi]
//
// Without the disc (fails before 0.9.5: nothing of it exists):
//   * the rider test: Sonic in modes 62-68, Tails in 48-54 (or SA1_STATE_ON_BOARD) ride, every other mode and kind not;
//   * the board's tones (208-238 Ice Cap, 690-698 Sand Hill) and its two stage rules {8, 208-238} / {38, 690-698};
//   * board_rules against an Audio without a mixer (the "fake mixer": its registry): both rules recorded for the rider
//     (kRuleNotApplied until a mixer installs them), cleared when the ride ends, another character untouched;
//   * the sound guard: with the board sounds off a rider's board tones stay out, his other tones, another character's board
//     tones and every SOUND_STOP pass; with them on everything passes;
//   * SA1_EVENT_BOARD into the Track: ON / OFF / PUSH counted, REFUSED true once with "carrying something" (holding) or
//     "can't get on a board now", FREED counted with its why and cleared by the read;
//   * the pose: a host-axes rotation -> a Source Angle (Source's MatrixAngles) and back (AngleMatrix), six rotations within
//     0.01 degree;
//   * the plain reasons' texts (gsa1_095_plan.md 5.4);
//   * the batch key (with libsa1's SA1_DRAW_BOARD): a draw with 0x4000 never shares a batch with an equal body draw, and its
//     batch's flags show 0x4000;
//   * with libsa1's board API: G-SA1's contract numbers are libsa1's (board.cpp's static_asserts compiled; checked again
//     here at run time).
// With the disc (--gdi): the rules re-applied to a new mixer - Audio::open installs both recorded rules (SA1_OK) and a
// second open (the Japanese-voices re-open) again.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "../src/core/audio.hpp"
#include "../src/core/board.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"

using namespace gsa1;

static int g_fail = 0, g_checks = 0;

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

static bool rule_is(const Audio &a, int32_t id, uint32_t slot, int32_t stage, uint32_t first, uint32_t last)
{
    StageRule r;
    return a.stage_rule(id, slot, r) && r.stage == stage && r.first == first && r.last == last;
}

static bool no_rule(const Audio &a, int32_t id, uint32_t slot)
{
    StageRule r;
    return !a.stage_rule(id, slot, r) || r.stage < 0;
}

static void test_rider()
{
    std::printf("the rider test and the board's tones\n");
    bool sonic = true, tails = true, others = true;
    for (int32_t m = 0; m < 128; m++) {
        sonic = sonic && board::rider(0, m, 0) == (m >= 62 && m <= 68);
        tails = tails && board::rider(2, m, 0) == (m >= 48 && m <= 54);
        for (int32_t k : {1, 3, 4, 5, 6, 7, 8}) {
            others = others && !board::rider(k, m, 0) && !board::rider(k, m, board::kStateOnBoard);
        }
    }
    bool flag = board::rider(0, 2, board::kStateOnBoard) && board::rider(2, 2, board::kStateOnBoard) &&
                !board::rider(0, 2, 0x08u);
    CHECK(sonic && tails && others && flag,
          "Sonic rides in modes 62-68, Tails in 48-54, or with SA1_STATE_ON_BOARD (0x10, not Super's 0x08); Eggman, Knuckles, "
          "Tikal, Amy, E-102, Big and Super Sonic (kind 8) never");
    bool tones = true;
    for (uint32_t t = 0; t < 2048; t++) {
        tones = tones && board::board_tone(t) == ((t >= 208 && t <= 238) || (t >= 690 && t <= 698));
    }
    StageRule snow, sand, s0, s1;
    board::stage_rules(true, snow, sand);
    board::stage_rules(false, s0, s1);
    CHECK(tones && snow.stage == 8 && snow.first == 208 && snow.last == 238 && sand.stage == 38 && sand.first == 690 &&
              sand.last == 698 && s0.stage < 0 && s1.stage < 0 && kRuleBoardSnow == 1u && kRuleBoardSand == 2u,
          "the board's tones are 208-238 and 690-698; a rider's rules {8, 208-238} (Ice Cap) in slot %u and {38, 690-698} "
          "(Sand Hill) in slot %u; off: both cleared", (unsigned)kRuleBoardSnow, (unsigned)kRuleBoardSand);
}

static void test_rules()
{
    std::printf("the stage rules against Audio's registry (no mixer)\n");
    Audio a;
    if (!a.has_stage_rules()) {
        CHECK(false, "this libsa1 has no stage rules (libsa1_audio.h version 5)");
        return;
    }
    bool on = board::apply_rules(a, 7, true);
    bool both = rule_is(a, 7, kRuleBoardSnow, 8, 208, 238) && rule_is(a, 7, kRuleBoardSand, 38, 690, 698) &&
                a.rule_status(7, kRuleBoardSnow) == kRuleNotApplied && a.rule_status(7, kRuleBoardSand) == kRuleNotApplied;
    bool other = no_rule(a, 8, kRuleBoardSnow) && no_rule(a, 8, kRuleBoardSand) && no_rule(a, 7, kRuleWhoosh);
    bool off = board::apply_rules(a, 7, false);
    bool cleared = no_rule(a, 7, kRuleBoardSnow) && no_rule(a, 7, kRuleBoardSand);
    bool bad = !board::apply_rules(a, 0, true);
    CHECK(on && both && other && off && cleared && bad,
          "a rider gets both rules (recorded, not applied: no mixer yet), another character none, the whoosh slot untouched; "
          "the ride's end clears both; id 0 is refused");
}

static void test_admit()
{
    std::printf("the board sounds' guard\n");
    const uint32_t S = SA1_EVENT_SOUND, X = SA1_EVENT_SOUND_STOP;
    bool off_rider = !board::admit(false, true, S, 690) && !board::admit(false, true, S, 237) &&
                     !board::admit(false, true, S, 208) && !board::admit(false, true, S, 698);
    bool off_pass = board::admit(false, true, S, 33) && board::admit(false, true, S, 17) && board::admit(false, true, S, 239) &&
                    board::admit(false, true, S, 689) && board::admit(false, false, S, 690) &&
                    board::admit(false, true, X, 690) && board::admit(false, true, SA1_EVENT_VOICE, 690);
    bool on_pass = board::admit(true, true, S, 690) && board::admit(true, true, S, 237);
    CHECK(off_rider && off_pass && on_pass,
          "board sounds off: a rider's 690 / 237 / 208 / 698 stay out; his 33 / 17 / 239 / 689, another character's 690, a "
          "SOUND_STOP of 690 and a voice pass (review R.12: the playing loop's stop is never kept out); on: all pass");
}

static void test_events()
{
    std::printf("SA1_EVENT_BOARD into the character's board\n");
    board::Track t;
    board::on_event(t, board::kEvOn, 65, false);
    board::on_event(t, board::kEvPush, 0, false);
    board::on_event(t, board::kEvOff, 0, false);
    std::string why;
    bool none = !board::take_refusal(t, why);
    board::on_event(t, board::kEvRefused, 23, true);
    bool r1 = board::take_refusal(t, why);
    std::string w1 = why;
    bool r1b = board::take_refusal(t, why);
    board::on_event(t, board::kEvRefused, 2, false);
    bool r2 = board::take_refusal(t, why);
    std::string w2 = why;
    board::on_event(t, board::kEvFreed, 2, false);
    board::on_event(t, board::kEvFreed, 1, false);
    int32_t fw = -9;
    uint32_t nf = board::take_freed(t, fw);
    int32_t fw2 = -9;
    uint32_t nf2 = board::take_freed(t, fw2);
    board::on_event(t, 99, 0, false);
    CHECK(t.ev_on == 1 && t.last_on_mode == 65 && t.ev_push == 1 && t.ev_off == 1 && none && r1 &&
              w1 == "carrying something" && !r1b && r2 && w2 == "can't get on a board now" && nf == 2 && fw == 1 &&
              nf2 == 0 && fw2 == -1 && t.ev_refused == 2 && t.ev_freed == 2,
          "ON (mode %u), PUSH, OFF counted; REFUSED true once - \"%s\" while holding, \"%s\" otherwise; two FREED: %u since the "
          "last read, the last one's why %d, then 0 / -1; an unknown id ignored", (unsigned)t.last_on_mode, w1.c_str(),
          w2.c_str(), (unsigned)nf, (int)fw);
}

static void test_angles()
{
    std::printf("the pose: rotation -> Source Angle\n");
    const float cases[6][3] = {{0, 0, 0}, {0, 90, 0}, {15, -30, 0}, {-20, 200, 10}, {5, 45, -170}, {89, 10, 30}};
    double worst = 0.0;
    std::string seen;
    for (const auto &c : cases) {
        float rot[9], back[9], ang[3];
        board::angles_rotation(c, rot);
        board::rotation_angles(rot, ang);
        board::angles_rotation(ang, back);
        double d = 0.0;
        for (int k = 0; k < 9; k++) {
            d = std::max(d, (double)std::fabs(rot[k] - back[k]));
        }
        // compare as directions: the matrix again (angles have several spellings: yaw 200 = -160)
        worst = std::max(worst, std::asin(std::min(1.0, d)) * 57.29577951308232);
        seen += format(" (%g %g %g)->(%.2f %.2f %.2f)", c[0], c[1], c[2], ang[0], ang[1], ang[2]);
    }
    const float ident[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};
    float a0[3];
    board::rotation_angles(ident, a0);
    // a quarter turn about host z: forward +y, left -x, up +z = yaw 90
    const float yaw90[9] = {0, -1, 0, 1, 0, 0, 0, 0, 1};
    float a90[3];
    board::rotation_angles(yaw90, a90);
    // a 15-degree slope going down along +x: forward (cos 15, 0, -sin 15) = pitch 15
    const float c15 = std::cos(15.0f * 0.017453292f), s15 = std::sin(15.0f * 0.017453292f);
    const float pitch15[9] = {c15, 0, s15, 0, 1, 0, -s15, 0, c15};
    float a15[3];
    board::rotation_angles(pitch15, a15);
    CHECK(worst < 0.01 && std::fabs(a0[0]) + std::fabs(a0[1]) + std::fabs(a0[2]) < 1e-4 && std::fabs(a90[1] - 90.0f) < 0.01f &&
              std::fabs(a90[0]) < 0.01f && std::fabs(a15[0] - 15.0f) < 0.01f && std::fabs(a15[1]) < 0.01f,
          "six rotations round-trip within %.4f degree (<0.01):%s; identity -> (0 0 0), a quarter turn about z -> yaw %.2f, "
          "a board down a 15-degree slope along +x -> pitch %.2f", worst, seen.c_str(), a90[1], a15[0]);
}

static void test_reasons()
{
    std::printf("the plain reasons\n");
    CHECK(std::string(board::kReasonKind) == "only Sonic and Tails ride a board" &&
              std::string(board::kReasonSuper) == "Super Sonic doesn't ride a board" &&
              std::string(board::kReasonNotRiding) == "not riding" &&
              std::string(board::kReasonNoKept) == "no board left behind" &&
              std::string(board::kReasonCarrying) == "carrying something" &&
              std::string(board::kReasonRefused) == "can't get on a board now" &&
              std::string(board::code_of(SA1_ERR_UNSUPPORTED)) == "unsupported" &&
              std::string(board::code_of(SA1_ERR_NOT_LOADED)) == "not_ready" &&
              std::string(board::code_of(SA1_ERR_GAME_FAULT)) == "fault" &&
              std::string(board::code_of(SA1_ERR_NOT_IMPLEMENTED)) == "fault" &&
              std::string(board::code_of(SA1_ERR_INVALID_ARGUMENT)) == "bad_argument" &&
              std::string(board::code_of(SA1_ERR_NOT_FOUND)) == "not_found",
          "the reasons: \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%s\"; the codes unsupported, not_ready, fault, bad_argument, "
          "not_found", board::kReasonKind, board::kReasonSuper, board::kReasonNotRiding, board::kReasonNoKept,
          board::kReasonCarrying, board::kReasonRefused);
}

static void test_batches()
{
    std::printf("the batch key\n");
#if defined(SA1_DRAW_BOARD)
    // two equal opaque untextured triangles, one of them the board's
    Character c;
    c.kind = 0;
    c.num_archives = 1;
    c.r_triangles = 2;
    c.r_tpos.assign(18, 0.0f);
    c.r_tnrm.assign(18, 0.0f);
    c.r_tuv.assign(12, 0.0f);
    c.r_tcol.assign(24, 255);
    sa1_draw d;
    std::memset(&d, 0, sizeof d);
    d.prim = SA1_PRIM_TRIANGLES;
    d.archive = -1;
    d.texture = -1;
    d.count = 1;
    d.first = 0;
    d.flags = SA1_DRAW_EFFECT | SA1_DRAW_NO_TEXTURE;
    d.blend_src = SA1_BLEND_ONE;
    d.blend_dst = SA1_BLEND_ZERO;
    c.r_draws.push_back(d);
    d.first = 1;
    d.flags |= SA1_DRAW_BOARD;
    c.r_draws.push_back(d);
    Session s;
    s.rebatch(c);
    bool sep = c.batch_count == 2 && ((c.batches[0].flags ^ c.batches[1].flags) == SA1_DRAW_BOARD) &&
               (c.batches[1].flags & SA1_DRAW_BOARD) && (kBatchKeyFlags & SA1_DRAW_BOARD) && kBatchBoardFlag == 0x4000u;
    // two board draws merge (one state)
    c.r_draws[0].flags |= SA1_DRAW_BOARD;
    s.rebatch(c);
    bool merged = c.batch_count == 1 && (c.batches[0].flags & SA1_DRAW_BOARD) && c.batches[0].triangles == 2;
    CHECK(sep && merged,
          "a board draw (SA1_DRAW_BOARD 0x4000) and an equal body draw: two batches, the board's flags 0x%X; two board draws: "
          "one batch", c.batch_count ? (unsigned)c.batches[0].flags : 0u);
#else
    INFO("this libsa1.h has no SA1_DRAW_BOARD (the round-start snapshot): the batch key keeps 0.9.4f's bits (0x%X)",
         (unsigned)kBatchKeyFlags);
    CHECK(kBatchBoardFlag == 0u, "kBatchBoardFlag is 0 without SA1_DRAW_BOARD");
#endif
}

static void test_contract()
{
    std::printf("the contract numbers (gsa1_095_plan.md 5.3)\n");
#if defined(SA1_API_BOARD)
    bool ok = board::kAvailable && SA1_BOARD_ON == board::kOn && SA1_BOARD_FREE == board::kFree &&
              SA1_EVENT_BOARD == board::kEventBoard && SA1_BOARD_EV_FREED == board::kEvFreed &&
              SA1_STATE_ON_BOARD == board::kStateOnBoard && SA1_BSTATE_SETTLED == board::kBsSettled &&
              SA1_BOARD_SETTLE_STEPS == board::kSettleSteps && SA1_DRAW_BOARD == board::kDrawBoard &&
              SA1_PREVIEW_BOARD == board::kPreviewBoard && SA1_SURFACE_BOARD_SNOW == board::kSurfaceBoardSnow &&
              SA1_SURFACE_BOARD_SAND == board::kSurfaceBoardSand && SA1_BOARD_KNOWN_FLAGS == board::kFlagsKnown &&
              SA1_INPUT_HOST_CAMERA == 0x4u && kHostCameraInput && (kHostFlagsKnown & SA1_INPUT_HOST_CAMERA) == 0u;
    CHECK(ok, "libsa1.h's board (SA1_API_BOARD): G-SA1's numbers equal libsa1's; the host camera bit 0x4 is known and never "
          "one of the Lua host flags (kHostFlagsKnown 0x%X)", (unsigned)kHostFlagsKnown);
    std::string err;
    sa1_status st = board::call(nullptr, 1, board::kOn, 0, 0, err);
    CHECK(st == SA1_ERR_NOT_LOADED && !err.empty(), "board::call without a context: %s (\"%s\")", sa1_status_string(st),
          err.c_str());
#else
    std::string err;
    sa1_status st = board::call(nullptr, 1, board::kOn, 0, 0, err);
    board::Track t;
    bool r = board::refresh(nullptr, 1, t);
    CHECK(!board::kAvailable && st == SA1_ERR_UNSUPPORTED && err == board::kReasonNoApi && !r && !t.view.valid,
          "this libsa1.h has no board (the round-start snapshot): board::call answers \"%s\", nothing to read", err.c_str());
#endif
}

static void test_new_mixer(const std::string &gdi)
{
    std::printf("the rules re-applied to a new mixer (the disc)\n");
    Audio a;
    if (!a.has_stage_rules()) {
        CHECK(false, "no stage rules");
        return;
    }
    board::apply_rules(a, 5, true);
    std::string err;
    bool o1 = a.open(gdi, false, err);
    int32_t s1 = a.rule_status(5, kRuleBoardSnow), s2 = a.rule_status(5, kRuleBoardSand);
    std::string err2;
    bool o2 = a.open(gdi, true, err2);
    int32_t s3 = a.rule_status(5, kRuleBoardSnow), s4 = a.rule_status(5, kRuleBoardSand);
    uint64_t applied = a.rules_applied();
    a.shutdown();
    CHECK(o1 && o2 && s1 == SA1_OK && s2 == SA1_OK && s3 == SA1_OK && s4 == SA1_OK && applied >= 4,
          "both rules recorded before the banks opened are installed with the mixer (%d / %d) and again with the re-opened "
          "one (%d / %d; %llu applications)%s%s", (int)s1, (int)s2, (int)s3, (int)s4, (unsigned long long)applied,
          o1 && o2 ? "" : ": ", o1 ? err2.c_str() : err.c_str());
}

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) {
        gdi = e;
    }
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") {
            gdi = argv[++i];
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_board_test (libsa1 %s; board API %s)\n", sa1_version_string(),
                board::kAvailable ? "present" : "absent");
    test_rider();
    test_rules();
    test_admit();
    test_events();
    test_angles();
    test_reasons();
    test_batches();
    test_contract();
    if (!gdi.empty()) {
        test_new_mixer(gdi);
    } else {
        INFO("no --gdi / SA1_TEST_GDI: the new mixer's rules are not checked");
    }
    std::printf("\nfeat_board_test: %d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
