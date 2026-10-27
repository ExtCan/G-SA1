-- G-SA1 client: an Xbox-style controller, read by the module itself through Windows XInput (gsa1.PadPoll), so
-- Garry's Mod's own joystick setup is not needed (keep it off: joystick 0).
--
-- Every frame cl_character.lua's Think calls GSA1.PadUpdate before the character's tick: the module applies the
-- dead zones, the button / trigger map and the camera speed (src/core/pad.cpp) and the result is GSA1.pad =
-- { connected, active, sx, sy (the SA1 stick), buttons (SA1), yaw, pitch (view deltas), reset, ... }. While the
-- controller is active (it had input within the last second) its stick replaces the keyboard's and its buttons
-- add to the keyboard's; otherwise the keyboard and mouse play as before. GSA1.PadView (CreateMove) turns the view
-- by the right stick and the camera triggers, and Back turns the camera behind the character. Rumble: the module
-- drives the motors from the game's own vibration events (Knuckles' punches, ...).
GSA1 = GSA1 or {}

GSA1.pad = nil
local pad_out = {}
local dirty = true
local pend_yaw, pend_pitch = 0, 0
local reset_to = nil
local RESET_PITCH = 10      -- degrees below the horizon after a camera reset

-- every pad ConVar (sh_config.lua)
local function pad_convar_names()
    local names = { "gsa1_pad", "gsa1_pad_index", "gsa1_pad_deadzone", "gsa1_pad_deadzone_right", "gsa1_pad_outer",
                    "gsa1_pad_trigger", "gsa1_pad_cam_speed", "gsa1_pad_cam_curve", "gsa1_pad_invert_y",
                    "gsa1_pad_dpad", "gsa1_pad_rumble", "gsa1_pad_rumble_strength" }
    for _, inp in ipairs(GSA1.PAD_INPUTS) do names[#names + 1] = "gsa1_pad_" .. inp.name end
    return names
end

function GSA1.PadSettingsTable()
    local c = GSA1.cv
    local map = {}
    for _, inp in ipairs(GSA1.PAD_INPUTS) do map[inp.name] = c["pad_" .. inp.name]:GetInt() end
    return {
        enabled = c.pad:GetBool(), index = math.Clamp(c.pad_index:GetInt(), 0, 4),
        dead_left = c.pad_dead:GetFloat(), dead_right = c.pad_dead_r:GetFloat(), outer = c.pad_outer:GetFloat(),
        trigger = c.pad_trigger:GetFloat(), cam_speed = c.pad_cam:GetFloat(), cam_curve = c.pad_curve:GetFloat(),
        invert_y = c.pad_invert_y:GetBool(), dpad = c.pad_dpad:GetBool(), rumble = c.pad_rumble:GetBool(),
        rumble_strength = c.pad_rumble_k:GetFloat(), map = map,
    }
end

-- the ConVars -> the module (on the next frame after any change)
function GSA1.ApplyPadSettings()
    dirty = true
    if not GSA1.mod or not gsa1.PadSettings then return end
    gsa1.PadSettings(GSA1.PadSettingsTable())
    dirty = false
end

for _, name in ipairs(pad_convar_names()) do
    cvars.AddChangeCallback(name, function() dirty = true end, "gsa1_pad")
end

local function start_reset()
    local C = GSA1.Char
    if not C or not C.drawYaw then return end
    reset_to = { yaw = C.drawYaw, pitch = RESET_PITCH, deadline = SysTime() + 0.6 }
end

-- once per frame, before the character's tick; paused: the escape menu in single player (no turning, motors off)
function GSA1.PadUpdate(paused)
    if not GSA1.mod or not gsa1.PadPoll then
        GSA1.pad = nil
        return
    end
    if dirty then GSA1.ApplyPadSettings() end
    if not GSA1.cv.pad:GetBool() then
        GSA1.pad = nil
        pend_yaw, pend_pitch, reset_to = 0, 0, nil
        return
    end
    local p = gsa1.PadPoll(paused and 0 or RealFrameTime(), paused and true or false, pad_out)
    GSA1.pad = p
    -- no character, or a menu has the cursor (spawn / context menu): the view stays, as it does for the mouse
    if not GSA1.Char or not p or not p.connected or vgui.CursorVisible() then
        pend_yaw, pend_pitch, reset_to = 0, 0, nil
        return
    end
    pend_yaw = pend_yaw + p.yaw
    pend_pitch = pend_pitch + p.pitch
    if p.reset then start_reset() end
end

-- the controller's input for this tick, or nil while the keyboard has priority
function GSA1.PadInput()
    local p = GSA1.pad
    if p and p.connected and p.active then return p.sx, p.sy, p.buttons end
    return nil
end

-- CreateMove: the view turns by the right stick / camera triggers; a camera reset swings it behind the character
-- (the mouse or the right stick take over at once)
function GSA1.PadView(cmd)
    if pend_yaw == 0 and pend_pitch == 0 and not reset_to then return end
    local yaw, pitch = pend_yaw, pend_pitch
    pend_yaw, pend_pitch = 0, 0
    local ang = cmd:GetViewAngles()
    if reset_to then
        if yaw ~= 0 or pitch ~= 0 or cmd:GetMouseX() ~= 0 or cmd:GetMouseY() ~= 0 or SysTime() > reset_to.deadline then
            reset_to = nil
        else
            local dy = math.NormalizeAngle(reset_to.yaw - ang.y)
            local dp = reset_to.pitch - ang.p
            if math.abs(dy) < 0.5 and math.abs(dp) < 0.5 then
                ang.y, ang.p = reset_to.yaw, reset_to.pitch
                reset_to = nil
            else
                local k = 1 - math.exp(-math.max(RealFrameTime(), 0.001) * 14)
                ang.y = ang.y + dy * k
                ang.p = ang.p + dp * k
            end
        end
    end
    ang.y = math.NormalizeAngle(ang.y + yaw)
    ang.p = math.Clamp(ang.p + pitch, -89, 89)
    ang.r = 0
    cmd:SetViewAngles(ang)
end

-- status ---------------------------------------------------------------------------------------------------------
local PAD_BITS = {
    { 0x1000, "A" }, { 0x2000, "B" }, { 0x4000, "X" }, { 0x8000, "Y" }, { 0x0100, "LB" }, { 0x0200, "RB" },
    { 0x10000, "LT" }, { 0x20000, "RT" }, { 0x0010, "Start" }, { 0x0020, "Back" }, { 0x0040, "LS" }, { 0x0080, "RS" },
    { 0x0001, "up" }, { 0x0002, "down" }, { 0x0004, "left" }, { 0x0008, "right" },
}
local SA1_BITS = { { 1, "A" }, { 2, "B" }, { 4, "Y" }, { 8, "L" }, { 16, "R" } }

local function bit_names(v, list)
    local out = {}
    for _, b in ipairs(list) do
        if bit.band(v or 0, b[1]) ~= 0 then out[#out + 1] = b[2] end
    end
    return #out > 0 and table.concat(out, " ") or "-"
end

-- one line (gsa1_status, the status pages)
function GSA1.PadStatusLine()
    if not GSA1.mod or not gsa1.PadStatus then return "controller: the module is not loaded" end
    if not GSA1.cv.pad:GetBool() then return "controller: off (gsa1_pad 0)" end
    local s = gsa1.PadStatus()
    if not s.available then return "controller: " .. tostring(s.backend) end
    if not s.connected then return string.format("controller: none connected (XInput: %s)", s.backend) end
    local others = {}
    for k = 1, 4 do
        if k ~= s.index and bit.band(s.slots, bit.lshift(1, k - 1)) ~= 0 then others[#others + 1] = tostring(k) end
    end
    return string.format("controller: %d in use (XInput: %s)%s; %s", s.index, s.backend,
        #others > 0 and ("; also connected: " .. table.concat(others, ", ")) or "",
        s.active and "it has priority" or "idle: keyboard and mouse have priority")
end

-- the live read-out of the Controller page
function GSA1.PadStatusLines()
    local out = { GSA1.PadStatusLine() }
    local p = GSA1.pad
    if p and p.connected then
        out[#out + 1] = string.format("left stick %+.2f %+.2f  ->  SA1 stick %+.2f %+.2f (stroke %.0f%%)", p.lx, p.ly,
            p.sx, p.sy, math.min(1, math.sqrt(p.sx * p.sx + p.sy * p.sy)) * 100)
        out[#out + 1] = string.format("right stick %+.2f %+.2f  ->  camera %+.2f %+.2f", p.rx, p.ry, p.cx, p.cy)
        out[#out + 1] = string.format("triggers %.2f / %.2f; held: %s  ->  SA1 buttons: %s", p.lt, p.rt,
            bit_names(p.raw, PAD_BITS), bit_names(p.buttons, SA1_BITS))
        out[#out + 1] = string.format("rumble %.0f%%", (p.rumble or 0) * 100)
    end
    local js = GetConVar("joystick")
    if js and js:GetBool() then
        out[#out + 1] = "note: Garry's Mod's own joystick input is on (joystick 1): it turns the view too; set joystick 0"
    end
    return out
end

-- commands ---------------------------------------------------------------------------------------------------------
concommand.Add("gsa1_pad_defaults", function()
    for _, inp in ipairs(GSA1.PAD_INPUTS) do RunConsoleCommand("gsa1_pad_" .. inp.name, tostring(inp.default)) end
end, nil, "G-SA1: the controller's default buttons (A jump, B / X action, Y, LB / RB = L / R, LT / RT camera, Back reset)")

concommand.Add("gsa1_pad_test_rumble", function()
    local ok, err = GSA1.LoadModule()
    if not ok then GSA1.Chat("%s", tostring(err)) return end
    GSA1.PadUpdate(false)
    local res, msg = gsa1.PadRumble(1, 0.5, 0.6)
    if not res then GSA1.Chat("rumble: %s", tostring(msg)) end
end, nil, "G-SA1: shake the controller for 0.6 s")

concommand.Add("gsa1_pad_status", function()
    if not GSA1.LoadModule() then GSA1.Msg("controller: %s", tostring(GSA1.moduleError)) return end
    for _, l in ipairs(GSA1.PadStatusLines()) do GSA1.Msg("%s", l) end
end, nil, "G-SA1: print the controller's state")
