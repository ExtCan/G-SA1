// G-SA1 core: game controllers through XInput (see pad.hpp).
#include "pad.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

#include "libsa1_internal_api.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

namespace gsa1 {

const char *const kPadInputNames[PAD_IN_COUNT] = {"a", "b", "x", "y", "lb", "rb", "lt", "rt", "start", "back",
                                                  "ls", "rs"};

uint32_t pad_input_bit(int32_t input)
{
    static const uint32_t bits[PAD_IN_COUNT] = {PAD_A,  PAD_B,  PAD_X,     PAD_Y,    PAD_LB, PAD_RB,
                                                PAD_LT, PAD_RT, PAD_START, PAD_BACK, PAD_LS, PAD_RS};
    return input >= 0 && input < PAD_IN_COUNT ? bits[input] : 0u;
}

uint32_t pad_action_buttons(int32_t action)
{
    switch (action) {
    case PAD_ACT_JUMP:
        return SA1_BUTTON_JUMP;
    case PAD_ACT_ACTION:
        return SA1_BUTTON_ACTION;
    case PAD_ACT_ACTION2:
        return SA1_BUTTON_ACTION2;
    case PAD_ACT_L:
        return SA1_BUTTON_L;
    case PAD_ACT_R:
        return SA1_BUTTON_R;
    default:
        return 0u;
    }
}

// ---- providers ---------------------------------------------------------------------------------------------------
void FakePad::set(uint32_t slot, uint16_t buttons, int16_t lx, int16_t ly, int16_t rx, int16_t ry, uint8_t lt,
                  uint8_t rt)
{
    if (slot > 3) {
        return;
    }
    connected[slot] = true;
    PadRaw &r = state[slot];
    r.packet++;
    r.buttons = buttons;
    r.lx = lx;
    r.ly = ly;
    r.rx = rx;
    r.ry = ry;
    r.lt = lt;
    r.rt = rt;
}

int FakePadProvider::get_state(uint32_t slot, PadRaw &out)
{
    if (!pad_->available || slot > 3) {
        return -1;
    }
    pad_->get_calls[slot]++;
    if (!pad_->connected[slot]) {
        return 0;
    }
    out = pad_->state[slot];
    return 1;
}

bool FakePadProvider::set_vibration(uint32_t slot, uint16_t low, uint16_t high)
{
    if (!pad_->available || slot > 3) {
        return false;
    }
    pad_->set_calls[slot]++;
    pad_->vib_low[slot] = low;
    pad_->vib_high[slot] = high;
    return pad_->connected[slot];
}

namespace {

PadProviderFactory g_factory = nullptr;

#ifdef _WIN32
// XInput's structures (xinput.h), declared here so that nothing about XInput reaches the link
struct XGamepad {
    WORD wButtons;
    BYTE bLeftTrigger;
    BYTE bRightTrigger;
    SHORT sThumbLX;
    SHORT sThumbLY;
    SHORT sThumbRX;
    SHORT sThumbRY;
};
struct XState {
    DWORD dwPacketNumber;
    XGamepad Gamepad;
};
struct XVibration {
    WORD wLeftMotorSpeed;    // low-frequency (heavy) motor
    WORD wRightMotorSpeed;   // high-frequency (light) motor
};
static_assert(sizeof(XGamepad) == 12 && sizeof(XState) == 16 && sizeof(XVibration) == 4, "XInput layout");
typedef DWORD(WINAPI *XInputGetStateFn)(DWORD, XState *);
typedef DWORD(WINAPI *XInputSetStateFn)(DWORD, XVibration *);
const DWORD kErrNotConnected = 1167;   // ERROR_DEVICE_NOT_CONNECTED

// XInput, loaded on first use by its full path in the Windows system directory (no DLL search path: a DLL of the
// same name in the game's directory is never picked up); freed with the provider.
class XInputProvider : public PadProvider {
public:
    ~XInputProvider() override
    {
        if (dll_) {
            FreeLibrary(dll_);
        }
    }
    bool available() override
    {
        load();
        return get_ != nullptr;
    }
    std::string name() const override
    {
        if (get_) {
            return name_;
        }
        return tried_ ? "not available: " + why_ : std::string("XInput (not loaded yet)");
    }
    int get_state(uint32_t slot, PadRaw &out) override
    {
        if (slot > 3 || !available()) {
            return -1;
        }
        XState s;
        std::memset(&s, 0, sizeof s);
        DWORD r = get_((DWORD)slot, &s);
        if (r == kErrNotConnected) {
            return 0;
        }
        if (r != 0) {
            return -1;
        }
        out.packet = s.dwPacketNumber;
        out.buttons = s.Gamepad.wButtons;
        out.lt = s.Gamepad.bLeftTrigger;
        out.rt = s.Gamepad.bRightTrigger;
        out.lx = s.Gamepad.sThumbLX;
        out.ly = s.Gamepad.sThumbLY;
        out.rx = s.Gamepad.sThumbRX;
        out.ry = s.Gamepad.sThumbRY;
        return 1;
    }
    bool set_vibration(uint32_t slot, uint16_t low, uint16_t high) override
    {
        if (slot > 3 || !set_) {
            return false;
        }
        XVibration v;
        v.wLeftMotorSpeed = low;
        v.wRightMotorSpeed = high;
        return set_((DWORD)slot, &v) == 0;
    }

private:
    void load()
    {
        if (tried_) {
            return;
        }
        tried_ = true;
        wchar_t sys[MAX_PATH + 1];
        UINT n = GetSystemDirectoryW(sys, MAX_PATH);
        if (n == 0 || n >= MAX_PATH) {
            why_ = "the Windows system directory is unknown";
            return;
        }
        static const wchar_t *const dlls[3] = {L"xinput1_4.dll", L"xinput9_1_0.dll", L"xinput1_3.dll"};
        static const char *const names[3] = {"xinput1_4.dll", "xinput9_1_0.dll", "xinput1_3.dll"};
        for (int i = 0; i < 3; i++) {
            std::wstring path = std::wstring(sys, n) + L"\\" + dlls[i];
            HMODULE h = LoadLibraryW(path.c_str());
            if (!h) {
                continue;
            }
            FARPROC g = GetProcAddress(h, "XInputGetState");
            FARPROC s = GetProcAddress(h, "XInputSetState");
            if (!g) {
                FreeLibrary(h);
                continue;
            }
            std::memcpy(&get_, &g, sizeof get_);
            if (s) {
                std::memcpy(&set_, &s, sizeof set_);
            }
            dll_ = h;
            name_ = names[i];
            return;
        }
        why_ = "no XInput library (xinput1_4.dll, xinput9_1_0.dll, xinput1_3.dll) in the Windows system directory";
    }

    bool tried_ = false;
    HMODULE dll_ = nullptr;
    XInputGetStateFn get_ = nullptr;
    XInputSetStateFn set_ = nullptr;
    std::string name_, why_;
};
#else
class NoPadProvider : public PadProvider {
public:
    bool available() override { return false; }
    std::string name() const override
    {
        return "not available: controllers are read through XInput on Windows only (no Linux support yet)";
    }
    int get_state(uint32_t, PadRaw &) override { return -1; }
    bool set_vibration(uint32_t, uint16_t, uint16_t) override { return false; }
};
#endif

float clampf(float v, float lo, float hi, float def)
{
    return std::isfinite(v) ? std::max(lo, std::min(hi, v)) : def;
}

}  // namespace

std::unique_ptr<PadProvider> make_pad_provider()
{
    if (g_factory) {
        return g_factory();
    }
#ifdef _WIN32
    return std::unique_ptr<PadProvider>(new XInputProvider());
#else
    return std::unique_ptr<PadProvider>(new NoPadProvider());
#endif
}

void set_pad_provider_factory(PadProviderFactory factory)
{
    g_factory = factory;
}

// ---- math --------------------------------------------------------------------------------------------------------
float pad_axis(int16_t v)
{
    return std::max(-1.0f, (float)v / 32767.0f);
}

float pad_trigger(uint8_t v, float threshold)
{
    float thr = std::isfinite(threshold) ? std::max(0.0f, threshold) : 0.0f;
    if (thr >= 0.999f) {
        return 0.0f;
    }
    float t = (float)v / 255.0f;
    if (t <= thr) {
        return 0.0f;
    }
    return std::min(1.0f, (t - thr) / (1.0f - thr));
}

void pad_radial(float x, float y, float inner, float outer, float curve, float &ox, float &oy)
{
    ox = oy = 0.0f;
    if (!std::isfinite(x) || !std::isfinite(y)) {
        return;
    }
    float in = std::isfinite(inner) ? std::max(0.0f, inner) : 0.0f;
    float m = std::sqrt(x * x + y * y);
    if (!(m > in) || !(m > 0.0f)) {
        return;
    }
    float span = (std::isfinite(outer) ? outer : 1.0f) - in;
    float t = span > 1e-6f ? (m - in) / span : 1.0f;
    t = std::max(0.0f, std::min(1.0f, t));
    if (std::isfinite(curve) && curve > 0.0f && curve != 1.0f) {
        t = std::pow(t, curve);
    }
    ox = x / m * t;
    oy = y / m * t;
}

void PadSettings::sanitize()
{
    const PadSettings d;
    if (slot < -1 || slot > 3) {
        slot = -1;
    }
    dead_left = clampf(dead_left, 0.0f, 0.9f, d.dead_left);
    dead_right = clampf(dead_right, 0.0f, 0.9f, d.dead_right);
    outer = clampf(outer, 0.5f, 1.0f, d.outer);
    // the outer edge lies beyond both dead zones (an empty range would turn the sticks digital)
    outer = std::max(outer, std::min(1.0f, std::max(dead_left, dead_right) + 0.05f));
    trigger = clampf(trigger, 0.0f, 0.9f, d.trigger);
    cam_speed = clampf(cam_speed, 0.0f, 1080.0f, d.cam_speed);
    cam_curve = clampf(cam_curve, 0.25f, 4.0f, d.cam_curve);
    rumble_strength = clampf(rumble_strength, 0.0f, 1.0f, d.rumble_strength);
    hold = clampf(hold, 0.0f, 10.0f, d.hold);
    for (int32_t i = 0; i < PAD_IN_COUNT; i++) {
        if (map[i] < 0 || map[i] >= PAD_ACT_COUNT) {
            map[i] = PAD_ACT_NONE;
        }
    }
}

// ---- Controller --------------------------------------------------------------------------------------------------
Controller::Controller() : p_(make_pad_provider()) {}

Controller::Controller(std::unique_ptr<PadProvider> provider) : p_(std::move(provider)) {}

Controller::~Controller()
{
    stop();
}

void Controller::configure(const PadSettings &in)
{
    PadSettings s = in;
    s.sanitize();
    bool slot_changed = s.slot != s_.slot;
    s_ = s;
    if (!s_.enabled || slot_changed) {
        cur_ = -1;
        prev_bits_ = 0;
        f_ = PadFrame();
        f_.enabled = s_.enabled;
    }
    if (!s_.enabled || !s_.rumble || slot_changed) {
        stop();
    } else {
        apply_motors();      // the strength may have changed
    }
}

std::string Controller::backend() const
{
    return p_ ? p_->name() : std::string("none");
}

uint32_t Controller::connected_mask() const
{
    uint32_t m = 0;
    for (int k = 0; k < 4; k++) {
        m |= conn_[k] ? (1u << k) : 0u;
    }
    return m;
}

bool Controller::has_input(const PadRaw &r) const
{
    float x, y, cx, cy;
    pad_radial(pad_axis(r.lx), pad_axis(r.ly), s_.dead_left, s_.outer, 1.0f, x, y);
    pad_radial(pad_axis(r.rx), pad_axis(r.ry), s_.dead_right, s_.outer, 1.0f, cx, cy);
    return r.buttons != 0 || x != 0.0f || y != 0.0f || cx != 0.0f || cy != 0.0f ||
           pad_trigger(r.lt, s_.trigger) > 0.0f || pad_trigger(r.rt, s_.trigger) > 0.0f;
}

void Controller::apply_motors()
{
    int32_t slot = cur_;
    uint16_t lo = 0, hi = 0;
    if (slot >= 0 && s_.enabled && s_.rumble) {
        float k = s_.rumble_strength;
        lo = (uint16_t)std::lround(std::max(0.0f, std::min(1.0f, rumble_lo_ * k)) * 65535.0f);
        hi = (uint16_t)std::lround(std::max(0.0f, std::min(1.0f, rumble_hi_ * k)) * 65535.0f);
    }
    f_.rumble_low = (float)lo / 65535.0f;
    f_.rumble_high = (float)hi / 65535.0f;
    if (!p_) {
        return;
    }
    if (sent_slot_ >= 0 && sent_slot_ != slot) {
        if (sent_lo_ || sent_hi_) {
            p_->set_vibration((uint32_t)sent_slot_, 0, 0);   // a controller no longer in use stops
        }
        sent_slot_ = -1;
        sent_lo_ = sent_hi_ = 0;
    }
    if (slot < 0 || (slot == sent_slot_ && lo == sent_lo_ && hi == sent_hi_)) {
        return;
    }
    p_->set_vibration((uint32_t)slot, lo, hi);
    sent_slot_ = slot;
    sent_lo_ = lo;
    sent_hi_ = hi;
}

void Controller::stop()
{
    rumble_end_ = 0.0;
    rumble_lo_ = rumble_hi_ = 0.0f;
    apply_motors();
}

bool Controller::rumble(float low, float high, double seconds, double now)
{
    if (!s_.enabled || !s_.rumble || cur_ < 0 || !std::isfinite(low) || !std::isfinite(high) ||
        !std::isfinite(seconds) || !std::isfinite(now) || seconds <= 0.0) {
        return false;
    }
    low = std::max(0.0f, std::min(1.0f, low));
    high = std::max(0.0f, std::min(1.0f, high));
    seconds = std::min(seconds, 5.0);
    if (now >= rumble_end_) {
        rumble_lo_ = low;
        rumble_hi_ = high;
    } else {
        rumble_lo_ = std::max(rumble_lo_, low);
        rumble_hi_ = std::max(rumble_hi_, high);
    }
    rumble_end_ = std::max(rumble_end_, now + seconds);
    apply_motors();
    return true;
}

bool Controller::rumble_event(uint32_t power, uint32_t frames, double now)
{
    if (!(now - last_input_ <= kRumbleWindow)) {
        return false;
    }
    uint32_t p = std::max(1u, std::min(7u, power));
    float strength = 0.25f + 0.75f * (float)(p - 1u) / 6.0f;     // the game's power 1..7
    double seconds = std::max(0.08, std::min(2.0, (double)frames / 60.0));
    return rumble(strength, strength * 0.5f, seconds, now);
}

const PadFrame &Controller::poll(double now, double dt, bool paused)
{
    polls_++;
    if (!std::isfinite(dt) || dt < 0.0) {
        dt = 0.0;
    }
    dt = std::min(dt, 0.25);
    PadFrame f;
    f.enabled = s_.enabled;
    f.available = s_.enabled && p_ && p_->available();     // the first enabled poll loads XInput
    if (!f.available) {
        cur_ = -1;
        prev_bits_ = 0;
        for (int k = 0; k < 4; k++) {
            conn_[k] = false;
        }
        f_ = f;
        stop();
        return f_;
    }
    // connected slots every poll; at most one empty slot per poll, each at most once per kProbeInterval (a query
    // of an empty XInput slot is slow)
    for (int32_t k = 0; k < 4; k++) {
        if (s_.slot >= 0 && k != s_.slot) {
            conn_[k] = false;
            continue;
        }
        if (!conn_[k]) {
            continue;
        }
        PadRaw r;
        if (p_->get_state((uint32_t)k, r) == 1) {
            raw_[k] = r;
        } else {
            conn_[k] = false;
            next_probe_[k] = now + kProbeInterval;
        }
    }
    for (int32_t i = 0; i < 4; i++) {
        int32_t k = (int32_t)((probe_rr_ + (uint32_t)i) & 3u);
        if ((s_.slot >= 0 && k != s_.slot) || conn_[k] || now < next_probe_[k]) {
            continue;
        }
        probe_rr_ = (uint32_t)(k + 1) & 3u;
        PadRaw r;
        if (p_->get_state((uint32_t)k, r) == 1) {
            conn_[k] = true;
            raw_[k] = r;
        } else {
            next_probe_[k] = now + kProbeInterval;
        }
        break;
    }
    // the controller in use
    int32_t cur = cur_ >= 0 && conn_[cur_] ? cur_ : -1;
    if (s_.slot >= 0) {
        cur = conn_[s_.slot] ? s_.slot : -1;
    } else if (!(cur >= 0 && has_input(raw_[cur]))) {
        // automatic: the one in use stays until it rests and another one has input
        int32_t pick = -1;
        for (int32_t k = 0; k < 4 && pick < 0; k++) {
            if (conn_[k] && k != cur && has_input(raw_[k])) {
                pick = k;
            }
        }
        for (int32_t k = 0; k < 4 && pick < 0 && cur < 0; k++) {
            if (conn_[k]) {
                pick = k;
            }
        }
        if (pick >= 0) {
            cur = pick;
        }
    }
    if (cur != cur_) {
        prev_bits_ = 0;
        cur_ = cur;
    }
    if (paused || now >= rumble_end_) {
        rumble_end_ = paused ? 0.0 : rumble_end_;
        rumble_lo_ = rumble_hi_ = 0.0f;
    }
    if (cur_ < 0) {
        f_ = f;
        apply_motors();
        return f_;
    }
    const PadRaw &r = raw_[cur_];
    f.connected = true;
    f.slot = cur_;
    f.packet = r.packet;
    f.lx = pad_axis(r.lx);
    f.ly = pad_axis(r.ly);
    f.rx = pad_axis(r.rx);
    f.ry = pad_axis(r.ry);
    f.lt = (float)r.lt / 255.0f;
    f.rt = (float)r.rt / 255.0f;
    float lt = pad_trigger(r.lt, s_.trigger), rt = pad_trigger(r.rt, s_.trigger);
    uint32_t bits = (uint32_t)r.buttons | (lt > 0.0f ? PAD_LT : 0u) | (rt > 0.0f ? PAD_RT : 0u);
    f.raw_buttons = bits;
    f.pressed = bits & ~prev_bits_;
    prev_bits_ = bits;
    // the SA1 stick: full analog resolution outside the dead zone (exact_stick maps it onto the game's own pad
    // range in Session::tick, so a small deflection still walks)
    pad_radial(f.lx, f.ly, s_.dead_left, s_.outer, 1.0f, f.stick_x, f.stick_y);
    if (s_.dpad_moves && f.stick_x == 0.0f && f.stick_y == 0.0f) {
        float dx = ((bits & PAD_DPAD_RIGHT) ? 1.0f : 0.0f) - ((bits & PAD_DPAD_LEFT) ? 1.0f : 0.0f);
        float dy = ((bits & PAD_DPAD_UP) ? 1.0f : 0.0f) - ((bits & PAD_DPAD_DOWN) ? 1.0f : 0.0f);
        float m = std::sqrt(dx * dx + dy * dy);
        if (m > 0.0f) {
            f.stick_x = dx / m;
            f.stick_y = dy / m;
        }
    }
    pad_radial(f.rx, f.ry, s_.dead_right, s_.outer, s_.cam_curve, f.cam_x, f.cam_y);
    float turn = 0.0f;
    for (int32_t i = 0; i < PAD_IN_COUNT; i++) {
        uint32_t bit = pad_input_bit(i);
        float amount = i == PAD_IN_LT ? lt : i == PAD_IN_RT ? rt : ((bits & bit) ? 1.0f : 0.0f);
        if (amount <= 0.0f) {
            continue;
        }
        int32_t a = s_.map[i];
        f.sa1_buttons |= pad_action_buttons(a);
        if (a == PAD_ACT_CAM_LEFT) {
            turn += amount;
        } else if (a == PAD_ACT_CAM_RIGHT) {
            turn -= amount;
        } else if (a == PAD_ACT_CAM_RESET && (f.pressed & bit)) {
            f.cam_reset = true;
        }
    }
    // right stick right = turn right (yaw decreases in Source); stick up = look up (pitch decreases)
    float yaw_rate = std::max(-1.0f, std::min(1.0f, turn - f.cam_x));
    float pitch_rate = s_.invert_y ? f.cam_y : -f.cam_y;
    f.look_yaw = (float)((double)yaw_rate * s_.cam_speed * dt);
    f.look_pitch = (float)((double)pitch_rate * s_.cam_speed * dt);
    f.input = has_input(r);
    if (f.input) {
        last_input_ = now;
    }
    f.active = now - last_input_ <= (double)s_.hold;
    f_ = f;
    apply_motors();
    return f_;
}

}  // namespace gsa1
