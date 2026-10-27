// G-SA1 controller test (no Garry's Mod, no disc): the XInput mapping of src/core/pad.cpp, driven through a fake
// XInput provider whose states the test injects, plus a smoke test of the real XInput provider.
//
//   pad_test
//
// Checks: axis / trigger normalisation; the radial dead zone (zero inside, continuous at its edge, rescaled to 0..1
// up to the outer edge, the direction kept exactly at every angle, the response curve); the settings' clamps; then
// gsa1::Controller with the fake provider: no controller (empty slots probed one per poll, at most once a second),
// a controller found by probing, the left stick -> the SA1 stick (a partial deflection walks: checked through
// exact_stick and the game's own pad dead zone), the default buttons (A jump, B / X action, Y, LB / RB = SA1 L / R,
// LT / RT turn the camera by their depth, Start nothing, Back = camera reset on the press only), remapping, the
// right stick -> camera deltas (speed, curve, invert Y), the D-pad option, priority over the keyboard (input within
// `hold` seconds), automatic selection and a fixed index, disconnection, rumble (the game's events, strength,
// expiry, overlap, pause, off, an unused controller stays still, a controller no longer in use stops), an
// unavailable provider, and the real XInput provider (loaded from the system directory; nothing assumed connected).
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <memory>
#include <string>

#include "../src/core/pad.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

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

static const double kPi = 3.14159265358979323846;

static bool close_to(double a, double b, double eps) { return std::fabs(a - b) <= eps; }
static int16_t ax(double v) { return (int16_t)std::lround(std::max(-1.0, std::min(1.0, v)) * 32767.0); }

// ---- 1. math -------------------------------------------------------------------------------------------------------
static void test_math()
{
    std::printf("axis, trigger and dead-zone math:\n");
    CHECK(pad_axis(32767) == 1.0f && pad_axis(-32768) == -1.0f && pad_axis(-32767) == -1.0f && pad_axis(0) == 0.0f &&
              close_to(pad_axis(16384), 0.5, 1e-4),
          "pad_axis: 32767 -> 1, -32768 / -32767 -> -1, 0 -> 0, 16384 -> %.5f", pad_axis(16384));
    CHECK(pad_trigger(0, 0.12f) == 0.0f && pad_trigger(30, 0.12f) == 0.0f && pad_trigger(255, 0.12f) == 1.0f &&
              close_to(pad_trigger(128, 0.12f), (128.0 / 255.0 - 0.12) / 0.88, 1e-5) && pad_trigger(200, 0.0f) == 200.0f / 255.0f,
          "pad_trigger (threshold 0.12): 0 and 30 -> 0, 128 -> %.4f, 255 -> 1; threshold 0: linear",
          pad_trigger(128, 0.12f));
    float x, y;
    const float in = 0.20f, out = 0.95f;
    pad_radial(0.19f, 0.0f, in, out, 1.0f, x, y);
    bool inside = x == 0.0f && y == 0.0f;
    pad_radial(0.1f, 0.13f, in, out, 1.0f, x, y);
    inside = inside && x == 0.0f && y == 0.0f;
    pad_radial(0.0f, -0.2f, in, out, 1.0f, x, y);
    inside = inside && x == 0.0f && y == 0.0f;
    CHECK(inside, "radial dead zone 0.20: magnitudes 0.19, 0.164 (diagonal) and 0.20 give (0, 0)");
    pad_radial(0.2005f, 0.0f, in, out, 1.0f, x, y);
    float edge = x;
    pad_radial(0.0f, 0.575f, in, out, 1.0f, x, y);
    float mid = y, midx = x;
    CHECK(edge > 0.0f && edge < 0.001f && close_to(mid, 0.5, 1e-5) && midx == 0.0f,
          "just outside it the stroke starts at %.5f (continuous); 0.575 -> %.5f (rescaled 0.20..0.95 -> 0..1)", edge, mid);
    pad_radial(0.96f, 0.0f, in, out, 1.0f, x, y);
    float sat = x;
    pad_radial(1.0f, 1.0f, in, out, 1.0f, x, y);
    CHECK(sat == 1.0f && close_to(std::sqrt(x * x + y * y), 1.0, 1e-6) && close_to(x, y, 1e-7),
          "beyond the outer edge 1; a square gate's corner (1, 1) -> (%.4f, %.4f): length 1 at exactly 45 degrees", x, y);
    double worst_dir = 0.0;
    bool monotonic = true;
    for (int deg = 0; deg < 360; deg += 7) {
        double a = deg * kPi / 180.0;
        float prev = -1.0f;
        for (int k = 0; k <= 20; k++) {
            double m = 0.25 + 0.75 * k / 20.0;
            pad_radial((float)(m * std::cos(a)), (float)(m * std::sin(a)), in, out, 1.0f, x, y);
            double d = std::atan2((double)y, (double)x) - std::atan2(std::sin(a), std::cos(a));
            while (d > kPi) d -= 2 * kPi;
            while (d < -kPi) d += 2 * kPi;
            worst_dir = std::max(worst_dir, std::fabs(d));
            float len = std::sqrt(x * x + y * y);
            monotonic = monotonic && len >= prev;
            prev = len;
        }
    }
    CHECK(worst_dir < 1e-5 && monotonic,
          "52 directions x 21 magnitudes: direction kept (worst error %.2e rad), stroke grows with the deflection",
          worst_dir);
    pad_radial(0.575f, 0.0f, in, out, 1.5f, x, y);
    float curved = x;
    pad_radial(NAN, 0.5f, in, out, 1.0f, x, y);
    CHECK(close_to(curved, std::pow(0.5, 1.5), 1e-5) && x == 0.0f && y == 0.0f,
          "response curve 1.5: half stroke -> %.5f (0.5^1.5); a non-finite axis -> (0, 0)", curved);

    PadSettings s;
    s.dead_left = NAN;
    s.dead_right = 0.9f;
    s.outer = 0.3f;
    s.cam_speed = 1e9f;
    s.cam_curve = -2.0f;
    s.slot = 7;
    s.map[PAD_IN_A] = 99;
    s.map[PAD_IN_B] = -1;
    s.rumble_strength = 3.0f;
    s.sanitize();
    PadSettings d;
    CHECK(s.dead_left == d.dead_left && s.dead_right == 0.9f && close_to(s.outer, 0.95, 1e-6) && s.cam_speed == 1080.0f &&
              s.cam_curve == 0.25f && s.slot == -1 && s.map[PAD_IN_A] == PAD_ACT_NONE && s.map[PAD_IN_B] == PAD_ACT_NONE &&
              s.rumble_strength == 1.0f,
          "settings clamped: NaN dead zone -> default, outer edge beyond the dead zones (%.2f), speed 1080, curve "
          "0.25, slot 7 -> automatic, unknown actions -> nothing, rumble strength 1", s.outer);
    PadSettings def;
    CHECK(def.map[PAD_IN_A] == PAD_ACT_JUMP && def.map[PAD_IN_B] == PAD_ACT_ACTION && def.map[PAD_IN_X] == PAD_ACT_ACTION &&
              def.map[PAD_IN_Y] == PAD_ACT_ACTION2 && def.map[PAD_IN_LB] == PAD_ACT_L && def.map[PAD_IN_RB] == PAD_ACT_R &&
              def.map[PAD_IN_LT] == PAD_ACT_CAM_LEFT && def.map[PAD_IN_RT] == PAD_ACT_CAM_RIGHT &&
              def.map[PAD_IN_START] == PAD_ACT_NONE && def.map[PAD_IN_BACK] == PAD_ACT_CAM_RESET &&
              std::strcmp(kPadInputNames[PAD_IN_START], "start") == 0 && pad_input_bit(PAD_IN_LT) == PAD_LT,
          "default map: A jump, B / X action, Y = SA1 Y, LB / RB = SA1 L / R, LT / RT camera left / right, Start "
          "nothing, Back camera reset");
}

// ---- 2. the controller with a fake XInput -------------------------------------------------------------------------
struct Rig {
    std::shared_ptr<FakePad> fp = std::make_shared<FakePad>();
    Controller c{std::unique_ptr<PadProvider>(new FakePadProvider(fp))};
    double now = 100.0;
    const double dt = 1.0 / 60.0;
    const PadFrame &step(int n = 1, bool paused = false)
    {
        for (int i = 0; i < n; i++) {
            now += dt;
            c.poll(now, paused ? 0.0 : dt, paused);
        }
        return c.frame();
    }
    uint32_t gets() const { return fp->get_calls[0] + fp->get_calls[1] + fp->get_calls[2] + fp->get_calls[3]; }
};

// the game's analog conversion (8C05117E): 12 pad units of dead zone per axis; returns the stroke 0..1 it decodes
static double game_stroke(float sx, float sy, double &dir_deg)
{
    double px = std::lround(sx * 127.0), py = std::lround(-sy * 127.0);
    double gx = px >= 0 ? std::max(0.0, px - 12.0) : std::min(0.0, px + 12.0);
    double gy = py >= 0 ? std::max(0.0, py - 12.0) : std::min(0.0, py + 12.0);
    dir_deg = std::atan2(-gy, gx) * 180.0 / kPi;
    return std::min(1.0, std::sqrt(gx * gx + gy * gy) / 115.0);
}

static void test_controller()
{
    std::printf("controller (fake XInput):\n");
    Rig R;
    PadFrame f = R.step(120);
    uint32_t probes = R.gets();
    CHECK(f.available && f.enabled && !f.connected && f.slot == -1 && !f.active && probes <= 12 &&
              R.fp->get_calls[0] >= 1 && R.fp->get_calls[3] >= 1,
          "no controller, 120 polls (2 s): not connected; %u probes of empty slots (each slot at most once a second, "
          "one per poll)", probes);
    R.fp->set(2, 0);
    int found = 0;
    for (int i = 0; i < 70 && !R.c.frame().connected; i++) {
        R.step();
        found = i + 1;
    }
    f = R.c.frame();
    CHECK(f.connected && f.slot == 2 && !f.active && !f.input && found <= 66,
          "a controller in slot 3 (index 2) is found by probing after %d polls; resting: not active", found);
    uint32_t g0 = R.fp->get_calls[2];
    R.step(10);
    CHECK(R.fp->get_calls[2] - g0 == 10, "a connected controller is read every poll (%u reads in 10 polls)",
          R.fp->get_calls[2] - g0);

    // left stick -> SA1 stick
    R.fp->set(2, 0, ax(0.15), ax(0.1));
    f = R.step();
    CHECK(f.stick_x == 0.0f && f.stick_y == 0.0f && !f.input && !f.active, "left stick at (0.15, 0.10): inside the "
          "dead zone, no input");
    R.fp->set(2, 0, 0, ax(0.575));
    f = R.step();
    double dir = 0, stroke = 0;
    float gx, gy;
    exact_stick(f.stick_x, f.stick_y, gx, gy);
    stroke = game_stroke(gx, gy, dir);
    CHECK(f.input && f.active && f.stick_x == 0.0f && close_to(f.stick_y, 0.5, 2e-4) && close_to(stroke, 0.5, 0.01) &&
              close_to(dir, 90.0, 1e-9),
          "left stick half up: SA1 stick (0, %.4f), active; the game decodes stroke %.3f at %.1f degrees (walk)",
          f.stick_y, stroke, dir);
    R.fp->set(2, 0, ax(0.26 * 0.6), ax(0.26 * 0.8));
    f = R.step();
    exact_stick(f.stick_x, f.stick_y, gx, gy);
    stroke = game_stroke(gx, gy, dir);
    CHECK(f.input && stroke > 0.0 && stroke < 0.15,
          "a deflection just outside the dead zone (0.26) still moves: SA1 stick %.3f, game stroke %.3f (creep)",
          std::sqrt(f.stick_x * f.stick_x + f.stick_y * f.stick_y), stroke);
    R.fp->set(2, 0, 32767, 32767);
    f = R.step();
    exact_stick(f.stick_x, f.stick_y, gx, gy);
    stroke = game_stroke(gx, gy, dir);
    CHECK(close_to(std::sqrt(f.stick_x * f.stick_x + f.stick_y * f.stick_y), 1.0, 1e-6) && close_to(f.stick_x, f.stick_y, 1e-7) &&
              stroke > 0.99 && close_to(dir, 45.0, 0.5),
          "full diagonal: SA1 stick length 1 at 45 degrees; game stroke %.3f at %.2f degrees (run)", stroke, dir);
    R.fp->set(2, 0, -32768, 0);
    f = R.step();
    CHECK(f.stick_x == -1.0f && f.stick_y == 0.0f && f.lx == -1.0f, "full left: (-1, 0)");

    // priority: active for `hold` (1 s) after the last input
    R.fp->set(2, 0);
    f = R.step();
    bool released = f.stick_x == 0.0f && f.stick_y == 0.0f && !f.input && f.active;
    f = R.step(50);
    bool still = f.active;
    f = R.step(12);
    CHECK(released && still && !f.active,
          "released: no input, still active 0.85 s later (priority over the keyboard), inactive after 1 s");

    // default buttons
    struct B {
        uint16_t bit;
        uint32_t sa1;
        const char *name;
    } bs[] = {{PAD_A, SA1_BUTTON_JUMP, "A"},    {PAD_B, SA1_BUTTON_ACTION, "B"},  {PAD_X, SA1_BUTTON_ACTION, "X"},
              {PAD_Y, SA1_BUTTON_ACTION2, "Y"}, {PAD_LB, SA1_BUTTON_L, "LB"},     {PAD_RB, SA1_BUTTON_R, "RB"},
              {PAD_START, 0, "Start"},          {PAD_LS, 0, "left stick click"}, {PAD_RS, 0, "right stick click"}};
    bool all = true;
    std::string bad;
    for (const B &b : bs) {
        R.fp->set(2, 0);
        R.step();
        R.fp->set(2, b.bit);
        f = R.step();
        bool ok = f.sa1_buttons == b.sa1 && (f.pressed & b.bit) && f.input && f.active && !f.cam_reset &&
                  f.look_yaw == 0.0f;
        f = R.step();
        ok = ok && f.sa1_buttons == b.sa1 && !(f.pressed & b.bit);
        if (!ok) {
            all = false;
            bad += std::string(" ") + b.name;
        }
    }
    CHECK(all, "A -> SA1 A (jump), B and X -> SA1 B (action), Y -> SA1 Y, LB / RB -> SA1 L / R, Start and the stick "
          "clicks -> nothing; held: no new press%s", bad.c_str());
    R.fp->set(2, 0);
    R.step();
    R.fp->set(2, PAD_BACK);
    f = R.step();
    bool reset1 = f.cam_reset && f.sa1_buttons == 0;
    f = R.step();
    bool reset2 = !f.cam_reset;
    R.fp->set(2, 0);
    R.step();
    R.fp->set(2, PAD_BACK);
    f = R.step();
    CHECK(reset1 && reset2 && f.cam_reset, "Back: camera reset on the press only (not while held), again on the "
          "next press; no SA1 button");

    // triggers: camera turn by their depth (Source yaw: + = left)
    const double dt = R.dt;
    R.fp->set(2, 0, 0, 0, 0, 0, 20, 0);
    f = R.step();
    bool below = f.look_yaw == 0.0f && !(f.raw_buttons & PAD_LT) && !f.input && close_to(f.lt, 20.0 / 255.0, 1e-6);
    R.fp->set(2, 0, 0, 0, 0, 0, 255, 0);
    f = R.step();
    float lt_full = f.look_yaw;
    R.fp->set(2, 0, 0, 0, 0, 0, 128, 0);
    f = R.step();
    float lt_half = f.look_yaw;
    R.fp->set(2, 0, 0, 0, 0, 0, 0, 255);
    f = R.step();
    CHECK(below && close_to(lt_full, 180.0 * dt, 1e-4) && close_to(lt_half, 180.0 * dt * pad_trigger(128, 0.12f), 1e-4) &&
              close_to(f.look_yaw, -180.0 * dt, 1e-4) && (f.raw_buttons & PAD_RT) && f.sa1_buttons == 0,
          "LT below its threshold: nothing; LT full: camera left %.3f deg/frame (180 deg/s), half: %.3f; RT full: "
          "right %.3f", lt_full, lt_half, f.look_yaw);

    // right stick: camera orbit
    R.fp->set(2, 0, 0, 0, 32767, 0);
    f = R.step();
    bool right = close_to(f.cam_x, 1.0, 1e-6) && close_to(f.look_yaw, -180.0 * dt, 1e-4) && f.look_pitch == 0.0f;
    R.fp->set(2, 0, 0, 0, 0, 32767);
    f = R.step();
    bool up = close_to(f.look_pitch, -180.0 * dt, 1e-4) && f.look_yaw == 0.0f;
    R.fp->set(2, 0, 0, 0, ax(0.575), 0);
    f = R.step();
    bool half = close_to(f.look_yaw, -180.0 * dt * std::pow(0.5, 1.5), 1e-4);
    R.fp->set(2, 0, 0, 0, ax(0.1), ax(-0.15));
    f = R.step();
    bool rest = f.look_yaw == 0.0f && f.look_pitch == 0.0f && !f.input;
    CHECK(right && up && half && rest,
          "right stick: right = turn right (yaw -3 deg/frame), up = look up (pitch -3), half right = %.4f (curve "
          "1.5), inside its dead zone nothing", -180.0 * dt * std::pow(0.5, 1.5));
    PadSettings s;
    s.invert_y = true;
    s.cam_speed = 90.0f;
    R.c.configure(s);
    R.fp->set(2, 0, 0, 0, 0, 32767);
    f = R.step();
    float inv = f.look_pitch;
    f = R.step(1, true);
    CHECK(close_to(inv, 90.0 * dt, 1e-4) && f.look_pitch == 0.0f,
          "invert Y and speed 90: up = look down (pitch +%.3f); paused (dt 0): no turning", inv);

    // remapping
    s = PadSettings();
    s.map[PAD_IN_START] = PAD_ACT_JUMP;
    s.map[PAD_IN_LT] = PAD_ACT_L;
    s.map[PAD_IN_A] = PAD_ACT_NONE;
    s.map[PAD_IN_RS] = PAD_ACT_CAM_RESET;
    R.c.configure(s);
    R.fp->set(2, PAD_START);
    f = R.step();
    bool start = f.sa1_buttons == SA1_BUTTON_JUMP;
    R.fp->set(2, 0, 0, 0, 0, 0, 255, 0);
    f = R.step();
    bool ltl = f.sa1_buttons == SA1_BUTTON_L && f.look_yaw == 0.0f;
    R.fp->set(2, PAD_A);
    f = R.step();
    bool anone = f.sa1_buttons == 0 && f.input;
    R.fp->set(2, PAD_RS);
    f = R.step();
    CHECK(start && ltl && anone && f.cam_reset, "remapped: Start -> jump, LT -> SA1 L (no camera turn), A -> nothing "
          "(still counts as input), right stick click -> camera reset");

    // D-pad
    s = PadSettings();
    R.c.configure(s);
    R.fp->set(2, PAD_DPAD_UP);
    f = R.step();
    bool off = f.stick_x == 0.0f && f.stick_y == 0.0f && f.input;
    s.dpad_moves = true;
    R.c.configure(s);
    R.fp->set(2, PAD_DPAD_UP | PAD_DPAD_RIGHT);
    f = R.step();
    bool diag = close_to(f.stick_x, std::sqrt(0.5), 1e-6) && close_to(f.stick_y, std::sqrt(0.5), 1e-6);
    R.fp->set(2, PAD_DPAD_UP, ax(-1.0), 0);
    f = R.step();
    CHECK(off && diag && f.stick_x == -1.0f && f.stick_y == 0.0f,
          "D-pad: off by default; on: up + right = full stroke at 45 degrees; a deflected left stick wins");
    R.c.configure(PadSettings());
}

static void test_selection()
{
    std::printf("controller selection:\n");
    Rig R;
    R.fp->set(2, 0);
    R.fp->set(0, 0);
    R.step(70);
    PadFrame f = R.c.frame();
    CHECK(f.connected && f.slot == 0 && R.c.connected_mask() == 5u,
          "two controllers (slots 1 and 3), both resting: automatic takes the first (index %d); mask %u", f.slot + 1,
          R.c.connected_mask());
    R.fp->set(2, PAD_A);
    f = R.step();
    bool to2 = f.slot == 2 && f.sa1_buttons == SA1_BUTTON_JUMP && (f.pressed & PAD_A);
    R.fp->set(0, PAD_B);
    f = R.step();
    bool stay = f.slot == 2 && f.sa1_buttons == SA1_BUTTON_JUMP;
    R.fp->set(2, 0);
    f = R.step();
    CHECK(to2 && stay && f.slot == 0 && f.sa1_buttons == SA1_BUTTON_ACTION,
          "automatic: the one pressing A takes over; the other's input is ignored while it is in use; once it rests, "
          "the other one with input takes over");
    PadSettings s;
    s.slot = 2;
    R.c.configure(s);
    R.fp->set(0, PAD_X);
    R.fp->set(2, 0, 0, 0);
    f = R.step();
    bool fixed = f.slot == 2 && f.sa1_buttons == 0;
    s.slot = 1;
    R.c.configure(s);
    f = R.step(70);
    CHECK(fixed && !f.connected && f.slot == -1 && R.c.connected_mask() == 0u,
          "fixed index 3: only slot 3 is read (slot 1's X ignored); fixed index 2 (empty): not connected");
    R.c.configure(PadSettings());
    R.fp->set(0, 0, 0, ax(1.0));
    R.step(70);
    f = R.c.frame();
    bool back = f.connected && f.slot == 0 && f.active;
    R.fp->connected[0] = false;
    R.fp->connected[2] = false;
    f = R.step();
    CHECK(back && !f.connected && !f.active && f.stick_y == 0.0f && f.sa1_buttons == 0,
          "both unplugged while running: not connected, not active, stick released");
    uint32_t g0 = R.gets();
    s = PadSettings();
    s.enabled = false;
    R.c.configure(s);
    f = R.step(120);
    CHECK(!f.enabled && !f.available && !f.connected && R.gets() == g0,
          "disabled: nothing is read (no XInput calls in 120 polls)");

    Rig U;
    U.fp->available = false;
    f = U.step(10);
    CHECK(!f.available && !f.connected && U.gets() == 0 && !U.c.rumble(1, 1, 1, U.now) &&
              U.c.backend().find("not available") == 0,
          "provider not available: \"%s\", nothing connected, no rumble", U.c.backend().c_str());
}

static void test_rumble()
{
    std::printf("rumble:\n");
    Rig R;
    R.fp->set(1, PAD_A);
    R.step(70);
    PadFrame f = R.c.frame();
    bool conn = f.connected && f.slot == 1 && R.fp->vib_low[1] == 0;
    bool ok = R.c.rumble_event(7, 30, R.now);
    f = R.c.frame();
    CHECK(conn && ok && R.fp->vib_low[1] == 65535 && R.fp->vib_high[1] == 32768 && close_to(f.rumble_low, 1.0, 1e-6),
          "the game's rumble event (power 7, 30 frames): motors %u / %u at once", R.fp->vib_low[1], R.fp->vib_high[1]);
    R.step(27);
    bool on = R.fp->vib_low[1] == 65535;
    R.step(4);
    CHECK(on && R.fp->vib_low[1] == 0 && R.fp->vib_high[1] == 0 && R.c.frame().rumble_low == 0.0f,
          "still on after 0.45 s, off after 0.52 s (30 frames of 1/60 s)");
    R.c.rumble_event(1, 15, R.now);
    uint16_t p1 = R.fp->vib_low[1];
    R.step(20);
    PadSettings s;
    s.rumble_strength = 0.5f;
    R.c.configure(s);
    R.c.rumble_event(7, 15, R.now);
    uint16_t half = R.fp->vib_low[1];
    CHECK(p1 == 16384 && half == 32768, "power 1 -> %u (a quarter); strength 0.5, power 7 -> %u", p1, half);
    R.c.configure(PadSettings());
    R.step(20);
    R.c.rumble_event(2, 60, R.now);
    R.step(3);
    R.c.rumble_event(7, 6, R.now);
    R.step(30);
    bool overlap = R.fp->vib_low[1] == 65535;
    R.step(30);
    CHECK(overlap && R.fp->vib_low[1] == 0, "overlapping requests keep the stronger level and the later end");
    R.c.rumble_event(7, 120, R.now);
    f = R.step(1, true);
    CHECK(R.fp->vib_low[1] == 0 && f.rumble_low == 0.0f, "pausing stops the motors at once");
    s = PadSettings();
    s.rumble = false;
    R.c.configure(s);
    CHECK(!R.c.rumble_event(7, 60, R.now) && !R.c.rumble(1, 1, 1, R.now) && R.fp->vib_low[1] == 0,
          "rumble off: requests and events are ignored");
    R.c.configure(PadSettings());
    R.c.rumble_event(5, 120, R.now);
    bool started = R.fp->vib_low[1] > 0;
    s = PadSettings();
    s.enabled = false;
    R.c.configure(s);
    CHECK(started && R.fp->vib_low[1] == 0, "disabling the controller stops the motors");
    R.c.configure(PadSettings());
    R.fp->set(1, 0);
    R.step(70);
    R.now += 31.0;
    R.step();
    CHECK(R.c.frame().connected && !R.c.rumble_event(7, 60, R.now) && R.fp->vib_low[1] == 0,
          "a controller without input for 31 s is not shaken by the game's events (it is not being used)");
    R.fp->set(1, PAD_A);
    R.step();
    R.c.rumble_event(7, 120, R.now);
    bool rumbling = R.fp->vib_low[1] == 65535;
    R.fp->set(3, 0);
    R.step(70);
    R.fp->set(1, 0);
    R.fp->set(3, PAD_B);
    PadFrame g = R.step();
    CHECK(rumbling && g.slot == 3 && R.fp->vib_low[1] == 0 && R.fp->vib_low[3] == 65535,
          "switching to another controller moves the rumble there and stops the first one");
    uint32_t sets = R.fp->set_calls[3];
    R.step(5);
    CHECK(R.fp->set_calls[3] == sets, "unchanged motor levels are not sent again");
    {
        auto fp = std::make_shared<FakePad>();
        std::unique_ptr<Controller> c(new Controller(std::unique_ptr<PadProvider>(new FakePadProvider(fp))));
        fp->set(0, PAD_A);
        double now = 5.0;
        for (int i = 0; i < 3; i++) {
            now += 1.0 / 60.0;
            c->poll(now, 1.0 / 60.0, false);
        }
        c->rumble(1, 1, 3, now);
        bool on0 = fp->vib_low[0] == 65535;
        c.reset();
        CHECK(on0 && fp->vib_low[0] == 0 && fp->vib_high[0] == 0,
              "destroying the controller (module unload) stops the motors");
    }
}

// ---- 3. the real XInput provider -------------------------------------------------------------------------------
static void test_real()
{
    std::printf("real provider:\n");
    std::unique_ptr<PadProvider> p = make_pad_provider();
    std::string before = p->name();
#ifdef _WIN32
    double t0 = now_ms();
    bool ok = p->available();
    double load_ms = now_ms() - t0;
    std::string path;
    HMODULE h = GetModuleHandleA(p->name().c_str());
    wchar_t buf[MAX_PATH + 1] = {0}, sys[MAX_PATH + 1] = {0};
    if (h) {
        GetModuleFileNameW(h, buf, MAX_PATH);
    }
    UINT n = GetSystemDirectoryW(sys, MAX_PATH);
    bool in_sys = h && n > 0 && _wcsnicmp(buf, sys, n) == 0;
    CHECK(ok && in_sys && before.find("not loaded yet") != std::string::npos,
          "XInput loaded on first use (%.2f ms): %s from the Windows system directory (%s)", load_ms, p->name().c_str(),
          in_sys ? "yes" : "no");
    std::string slots;
    t0 = now_ms();
    for (uint32_t k = 0; k < 4; k++) {
        PadRaw r;
        int st = p->get_state(k, r);
        slots += format(" %u:%s", k + 1, st == 1 ? "connected" : st == 0 ? "empty" : "error");
        if (st == 1) {
            INFO("controller %u: buttons %04X, left (%d, %d), right (%d, %d), triggers %u / %u", k + 1, r.buttons, r.lx,
                 r.ly, r.rx, r.ry, r.lt, r.rt);
        }
    }
    INFO("XInput slots:%s (4 reads in %.2f ms)", slots.c_str(), now_ms() - t0);
    Controller c;
    for (int i = 0; i < 8; i++) {
        c.poll(now_ms() / 1000.0, 1.0 / 60.0, false);
    }
    CHECK(c.frame().available, "a Controller on the real provider polls without trouble (%s; %s)",
          c.backend().c_str(), c.frame().connected ? format("controller %d in use", c.frame().slot + 1).c_str()
                                                   : "no controller connected");
#else
    CHECK(!p->available() && p->name().find("not available") == 0, "%s", p->name().c_str());
    Controller c;
    c.poll(1.0, 0.016, false);
    CHECK(!c.frame().available && !c.frame().connected && !c.rumble(1, 1, 1, 1.0), "the stub polls as not available");
#endif
}

int main()
{
    std::printf("G-SA1 pad_test\n");
    test_math();
    test_controller();
    test_selection();
    test_rumble();
    test_real();
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
