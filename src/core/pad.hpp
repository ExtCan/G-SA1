// G-SA1 core: an Xbox-style game controller read through Windows XInput, turned into SA1 input (no GMod
// dependency, so tests/pad_test.cpp drives exactly the code the module runs).
//
// Provider: XInput is loaded at run time, the first time an enabled controller is polled: xinput1_4.dll, else
// xinput9_1_0.dll, else xinput1_3.dll, each by its full path in the Windows system directory (never from the
// game directory or the DLL search path); nothing is linked. Other platforms: a provider that reports "not
// available". Tests install a FakePadProvider through set_pad_provider_factory() and inject states.
//
// Controller::poll() runs once per frame and gives (PadFrame):
//   * the SA1 stick: the left stick through a radial dead zone (the stroke starts at 0 just outside it and
//     reaches 1 at the outer edge, the direction is kept), full analog resolution: a partial deflection walks;
//   * camera orbit: the right stick through its own dead zone and a response curve, times the speed (degrees
//     per second) and dt, invert Y optional; as view-angle deltas in Source's convention (yaw counter-clockwise =
//     turning left, pitch positive = looking down); trigger / button actions add camera turns;
//   * SA1 buttons and camera reset from a per-input action map (A jump, B / X action, Y = SA1 Y, LB / RB = SA1
//     L / R, LT / RT = camera left / right, Back = camera reset, Start nothing: the defaults);
//   * priority: active while it has input and for `hold` seconds after, so the addon prefers it to the keyboard;
//   * rumble: requests (and the game's SA1_EVENT_RUMBLE) drive the two motors for their duration.
#pragma once

#include <cstdint>
#include <memory>
#include <string>

namespace gsa1 {

// XInput's wButtons bits, plus two synthetic bits for the triggers beyond their threshold
enum : uint32_t {
    PAD_DPAD_UP = 0x0001u,
    PAD_DPAD_DOWN = 0x0002u,
    PAD_DPAD_LEFT = 0x0004u,
    PAD_DPAD_RIGHT = 0x0008u,
    PAD_START = 0x0010u,
    PAD_BACK = 0x0020u,
    PAD_LS = 0x0040u,              // left stick click
    PAD_RS = 0x0080u,              // right stick click
    PAD_LB = 0x0100u,
    PAD_RB = 0x0200u,
    PAD_A = 0x1000u,
    PAD_B = 0x2000u,
    PAD_X = 0x4000u,
    PAD_Y = 0x8000u,
    PAD_LT = 0x10000u,             // left trigger beyond PadSettings::trigger
    PAD_RT = 0x20000u,
};

// What a button or trigger does (PadSettings::map; the Lua side's gsa1_pad_<input> values)
enum PadAction : int32_t {
    PAD_ACT_NONE = 0,
    PAD_ACT_JUMP = 1,              // SA1 A
    PAD_ACT_ACTION = 2,            // SA1 B: spin dash, punch, attack
    PAD_ACT_ACTION2 = 3,           // SA1 Y
    PAD_ACT_L = 4,                 // SA1 L
    PAD_ACT_R = 5,                 // SA1 R
    PAD_ACT_CAM_LEFT = 6,          // turn the camera left (look around); a trigger turns by its depth
    PAD_ACT_CAM_RIGHT = 7,
    PAD_ACT_CAM_RESET = 8,         // camera behind the character (PadFrame::cam_reset on the press)
    PAD_ACT_COUNT = 9,
};

// The mappable inputs (index into PadSettings::map)
enum PadInput : int32_t {
    PAD_IN_A = 0, PAD_IN_B, PAD_IN_X, PAD_IN_Y, PAD_IN_LB, PAD_IN_RB, PAD_IN_LT, PAD_IN_RT, PAD_IN_START,
    PAD_IN_BACK, PAD_IN_LS, PAD_IN_RS, PAD_IN_COUNT
};
extern const char *const kPadInputNames[PAD_IN_COUNT];    // "a", "b", "x", "y", "lb", "rb", "lt", "rt", ...
uint32_t pad_input_bit(int32_t input);                     // PAD_* bit of an input
uint32_t pad_action_buttons(int32_t action);               // SA1_BUTTON_* of an action (0 for camera actions)

// One controller state as XInput reports it
struct PadRaw {
    uint32_t packet = 0;
    uint16_t buttons = 0;          // PAD_* (XInput bits)
    uint8_t lt = 0, rt = 0;        // 0..255
    int16_t lx = 0, ly = 0;        // -32768..32767, +y up
    int16_t rx = 0, ry = 0;
};

class PadProvider {
public:
    virtual ~PadProvider() = default;
    // loads the API on first use; false: not available (reason in name())
    virtual bool available() = 0;
    virtual std::string name() const = 0;
    // 1: connected (out filled), 0: no controller in that slot (0..3), -1: error / not available
    virtual int get_state(uint32_t slot, PadRaw &out) = 0;
    virtual bool set_vibration(uint32_t slot, uint16_t low, uint16_t high) = 0;
};

// The shared state behind a FakePadProvider (tests keep a reference after handing the provider over)
struct FakePad {
    bool available = true;
    bool connected[4] = {false, false, false, false};
    PadRaw state[4];
    uint16_t vib_low[4] = {0, 0, 0, 0}, vib_high[4] = {0, 0, 0, 0};
    uint32_t get_calls[4] = {0, 0, 0, 0}, set_calls[4] = {0, 0, 0, 0};
    // replaces slot's state (connects it) and advances its packet number
    void set(uint32_t slot, uint16_t buttons, int16_t lx = 0, int16_t ly = 0, int16_t rx = 0, int16_t ry = 0,
             uint8_t lt = 0, uint8_t rt = 0);
};

class FakePadProvider : public PadProvider {
public:
    explicit FakePadProvider(std::shared_ptr<FakePad> pad) : pad_(std::move(pad)) {}
    bool available() override { return pad_->available; }
    std::string name() const override { return pad_->available ? "fake" : "not available: fake"; }
    int get_state(uint32_t slot, PadRaw &out) override;
    bool set_vibration(uint32_t slot, uint16_t low, uint16_t high) override;

private:
    std::shared_ptr<FakePad> pad_;
};

// XInput on Windows (loaded lazily from the system directory), "not available" elsewhere; a factory set by
// set_pad_provider_factory() takes precedence (tests).
std::unique_ptr<PadProvider> make_pad_provider();
typedef std::unique_ptr<PadProvider> (*PadProviderFactory)();
void set_pad_provider_factory(PadProviderFactory factory);

// -1..1 (-32768 -> -1)
float pad_axis(int16_t v);
// 0 up to the threshold (fraction of 255), then 0..1
float pad_trigger(uint8_t v, float threshold);
// Radial dead zone: magnitude <= inner -> (0, 0); inner..outer -> 0..1 raised to `curve`; beyond outer -> 1;
// the direction is kept exactly.
void pad_radial(float x, float y, float inner, float outer, float curve, float &ox, float &oy);

struct PadSettings {
    bool enabled = true;
    int32_t slot = -1;             // -1: automatic (the controller used last), 0..3: that XInput slot
    float dead_left = 0.20f;       // radial dead zones, fraction of full deflection
    float dead_right = 0.20f;
    float outer = 0.95f;           // deflection that counts as full (both sticks)
    float trigger = 0.12f;         // trigger threshold (fraction)
    float cam_speed = 180.0f;      // degrees per second at full right-stick deflection (yaw and pitch)
    float cam_curve = 1.5f;        // right-stick response exponent (1 = linear)
    bool invert_y = false;         // right stick up = look down
    bool dpad_moves = false;       // the D-pad moves the character (full stroke) while the left stick rests
    bool rumble = true;
    float rumble_strength = 1.0f;  // 0..1
    float hold = 1.0f;             // seconds the controller keeps priority after its last input
    int32_t map[PAD_IN_COUNT] = {
        PAD_ACT_JUMP,              // A
        PAD_ACT_ACTION,            // B
        PAD_ACT_ACTION,            // X
        PAD_ACT_ACTION2,           // Y
        PAD_ACT_L,                 // LB
        PAD_ACT_R,                 // RB
        PAD_ACT_CAM_LEFT,          // LT
        PAD_ACT_CAM_RIGHT,         // RT
        PAD_ACT_NONE,              // Start
        PAD_ACT_CAM_RESET,         // Back
        PAD_ACT_NONE,              // left stick click
        PAD_ACT_NONE,              // right stick click
    };
    void sanitize();               // clamps every field into its range (non-finite values -> defaults)
};

struct PadFrame {
    bool available = false;        // the provider works (XInput loaded)
    bool enabled = false;
    bool connected = false;        // a controller is in use (slot >= 0)
    int32_t slot = -1;             // 0..3
    bool input = false;            // anything beyond the dead zones / thresholds in this poll
    bool active = false;           // priority over the keyboard (input within `hold` seconds)
    uint32_t packet = 0;
    float lx = 0, ly = 0, rx = 0, ry = 0;   // sticks, -1..1, +y up
    float lt = 0, rt = 0;                   // triggers, 0..1
    uint32_t raw_buttons = 0;      // PAD_* held (PAD_LT / PAD_RT beyond the threshold)
    uint32_t pressed = 0;          // PAD_* pressed since the last poll
    float stick_x = 0, stick_y = 0;          // SA1 stick: -1..1, +y forward
    float cam_x = 0, cam_y = 0;              // right stick after its dead zone and curve
    uint32_t sa1_buttons = 0;      // SA1_BUTTON_* held
    float look_yaw = 0;            // degrees to add to the view yaw this poll (positive: turn left)
    float look_pitch = 0;          // degrees to add to the view pitch (positive: look down)
    bool cam_reset = false;        // the camera-reset action was pressed in this poll
    float rumble_low = 0, rumble_high = 0;   // motor levels now, 0..1
};

class Controller {
public:
    Controller();                                     // provider: make_pad_provider()
    explicit Controller(std::unique_ptr<PadProvider> provider);
    ~Controller();                                    // motors off
    Controller(const Controller &) = delete;
    Controller &operator=(const Controller &) = delete;

    // sanitized; disabling, switching rumble off or changing the slot stops the motors
    void configure(const PadSettings &s);
    const PadSettings &settings() const { return s_; }

    // Once per frame. now: monotonic seconds; dt: seconds of camera turning (0 while paused); paused: motors off.
    const PadFrame &poll(double now, double dt, bool paused);
    const PadFrame &frame() const { return f_; }

    // Both motors (0..1, times rumble_strength) for `seconds`; overlapping requests keep the stronger and the
    // later end. Only with rumble on and a controller in use. Returns whether the motors were set.
    bool rumble(float low, float high, double seconds, double now);
    // SA1_EVENT_RUMBLE: id = power 1..7 (the game's vibration call), arg = duration in 1/60 s frames.
    // Only when the controller had input within kRumbleWindow seconds (a controller lying unused stays still).
    bool rumble_event(uint32_t power, uint32_t frames, double now);
    void stop();                                      // motors off now

    PadProvider *provider() { return p_.get(); }
    std::string backend() const;                      // provider name
    uint32_t connected_mask() const;                  // bit per slot seen connected
    uint64_t polls() const { return polls_; }

    static constexpr double kProbeInterval = 1.0;     // seconds between probes of an empty slot
    static constexpr double kRumbleWindow = 30.0;

private:
    void apply_motors();
    bool has_input(const PadRaw &r) const;

    std::unique_ptr<PadProvider> p_;
    PadSettings s_;
    PadFrame f_;
    bool conn_[4] = {false, false, false, false};
    PadRaw raw_[4];
    double next_probe_[4] = {0, 0, 0, 0};
    uint32_t probe_rr_ = 0;
    int32_t cur_ = -1;
    uint32_t prev_bits_ = 0;
    double last_input_ = -1e30;
    double rumble_end_ = 0.0;
    float rumble_lo_ = 0.0f, rumble_hi_ = 0.0f;
    int32_t sent_slot_ = -1;
    uint16_t sent_lo_ = 0, sent_hi_ = 0;
    uint64_t polls_ = 0;
};

}  // namespace gsa1
