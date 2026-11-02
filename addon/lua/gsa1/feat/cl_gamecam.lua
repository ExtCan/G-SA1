-- G-SA1 client: Big's fishing camera (feature "gamecam"; round 0.9.8: sadc docs/research/gsa1_098_plan.md 5.5, 5.6, 5.9, 6.9;
-- fish098.md 4; decisions A8, A9). The game's own camera request runs in libsa1 (SA1_INPUT_GAME_CAMERA, sa1_character_camera):
-- the game's FISHING camera while Big aims, the game's lure camera while the lure is in the water, the game's bright line.
-- This file asks for it and shows it:
--   * the bit: GSA1.HostWaterFlags adds gsa1.INPUT_GAME_CAMERA while G.Allowed(C) (a request libsa1 does not know, or none,
--     runs nothing: without a request the bit changes nothing);
--   * the stick's frame: GSA1.TickYaw is the game camera's yaw while it runs;
--   * the view: GSA1.ViewOverride. Position and forward are the game's, the angles come from the forward vector, NEVER from a
--     look-at of the target (during SLOW the game's camera still turns while the target is already there; a look-at snaps on
--     the first frames). A hull trace keeps the shown view out of the map's brushes (it stands in for the game's camera
--     against the land, 8C01E32A / 8C01BD9E, owner question O-G8; the game's numbers stay untouched). G.mix blends from and
--     to your camera; a CUT of the game's camera stays a cut;
--   * the render bounds: the character's entity lies behind the eye while the view is on the lure (fish098 4.4);
--   * the mouse and the right stick do nothing while it runs (locked, as the game), or turn the view around the lure
--     (gsa1_cam_fish_mouse); first person shows the camera too (gsa1_cam_fish_first);
--   * the ways to leave: the game's own, R = the game's L + R while the lure is in the water (keyboard), the death, the toggle.
-- Nothing here touches another character: followers keep the chase eye (GSA1.FollowerTickCamera, decision A9), and a Big
-- follower is never ticked with the bit. With the module's feature absent every wrap passes through and the Camera page says
-- what it needs. There are no fish in a Garry's Mod world: the catch shot's kind is known to libsa1 but never comes.
-- UNVERIFIED in game (mock only; the owner's checklist): SetRenderBounds against Source's PVS (if Big, the lure or the line
-- vanish while the view is on the lure, the fallback is a draw hook while it runs, as cl_render.lua has per view), the view
-- under water, the feel of the blends.
GSA1 = GSA1 or {}
GSA1.GameCam = GSA1.GameCam or {}
local G = GSA1.GameCam                  -- kept across a reload of this file, as the wraps below are
local band, bor = bit.band, bit.bor

G.BIG_KIND = 7
G.NEEDS = { feature = "gamecam", version = 1, module = "0.9.8" }
local BIG_KIND = G.BIG_KIND
local BTN_L, BTN_R = 8, 16              -- as cl_wheel.lua (SA1_BUTTON_L, SA1_BUTTON_R)
local TRACE_ABOVE_BIG = 80              -- Big + (0, 20, 0): 20 game units, the point the game's FISHING camera circles
local BOUNDS_TARGET, BOUNDS_EYE, BOUNDS_STEP = 256, 64, 64
local ORBIT_YAW, ORBIT_PITCH = 60, 30   -- degrees, the most the mouse turns the view around the lure
local PITCH_LIMIT = 89                  -- the eye angles' pitch

-- the settings (5.9; every one has its control on the Camera page, G.Panel) ------------------------------------------------------
local cv = G.cv or {}
G.cv = cv
cv.fish = GSA1.ConVar("gsa1_cam_fish", "2", "Big's fishing camera: 0 = off (your camera, as 0.9.5), 1 = only on the lure, "
    .. "2 = as the game (behind Big while he aims, then on the lure)", 0, 2)
cv.blend = GSA1.ConVar("gsa1_cam_fish_blend", "0.3", "Seconds of the blend from and to your camera (0 = at once)", 0, 1.5)
cv.mouse = GSA1.ConVar("gsa1_cam_fish_mouse", "0", "1 = the mouse turns the view around the lure while fishing; 0 = the mouse "
    .. "does nothing, as the game", 0, 1)
cv.fov = GSA1.ConVar("gsa1_cam_fish_fov", "0", "1 = the game's field of view (70) while fishing; 0 = yours", 0, 1)
cv.first = GSA1.ConVar("gsa1_cam_fish_first", "1", "1 = the fishing camera also when you play in first person; 0 = first person "
    .. "stays first person (the line stays invisible, as 0.9.5)", 0, 1)
cv.rkey = GSA1.ConVar("gsa1_cam_fish_rkey", "1", "1 = R reels in at once while the lure is in the water (the game's L + R)", 0, 1)
cv.toggle_key = GSA1.ConVar("gsa1_cam_fish_toggle_key", "0", "Key that looks elsewhere for this cast (the same as the command "
    .. "gsa1_cam_fish_toggle)", 0, 1024)

-- the state ----------------------------------------------------------------------------------------------------------------------
G.st = G.st or { flags = 0, kind = 0, level = 0, adjust = 0, fn = 0, px = 0, py = 0, pz = 0, fx = 1, fy = 0, fz = 0,
                 tx = 0, ty = 0, tz = 0, fov = 0 }  -- gsa1.Camera's table (reused: no garbage per frame)
G.mix = G.mix or 0                      -- 0 your camera .. 1 the game's
G.orbitY, G.orbitP = G.orbitY or 0, G.orbitP or 0

local function clear_request(st)
    st.flags, st.kind, st.level, st.adjust, st.fn = 0, 0, 0, 0, 0
end

-- back to nothing: a new or removed character has a new world, so no request (fish098 3.2)
function G.Reset()
    clear_request(G.st)
    G.mix, G.orbitY, G.orbitP = 0, 0, 0
    G.dead, G.toggleOff, G.rDown, G.toggleDown = false, false, false, false
    G.chase, G.chaseFrame = nil, nil
    G.gameO, G.gameA, G.gameFov, G.eyeP, G.eyeY = nil, nil, nil, nil, nil
    G.logFn, G.logLevel, G.logAdjust = 0, 0, 0
    G.boundsSet, G.bounds = false, nil
end
if G.logFn == nil then G.Reset() end

-- the module's feature, without loading anything (per frame, only for Big)
function G.Present()
    if not GSA1.mod or not gsa1 or not gsa1.Camera or not gsa1.INPUT_GAME_CAMERA then return false end
    local f = gsa1.FEATURES
    return type(f) == "table" and (tonumber(f.gamecam) or 0) >= 1
end

-- the bit may be on for C now (4.2, 4.6)
function G.Allowed(C)
    if C == nil or C ~= GSA1.Char or C.kind ~= BIG_KIND or not G.Present() then return false end
    local mode = cv.fish:GetInt()
    if mode <= 0 or G.dead or C.death or G.toggleOff then return false end
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end
    local ve = ply:GetViewEntity()
    if IsValid(ve) and ve ~= ply then return false end                          -- a Camera-tool view: as 0.9.5 (CalcView's own test)
    if not cv.first:GetBool() and G.prevFirstPerson() then return false end     -- first person stays first person
    if mode == 1 and G.st.kind ~= gsa1.CAMKIND_LURE then return false end       -- "Lure only": the last frame's kind
    return true
end

-- the game camera ran in the last pair and may show (the frame before's gsa1.Camera)
function G.Running(C)
    local fl = G.st.flags
    return fl ~= 0 and C ~= nil and band(fl, gsa1.CAMSTATE_RUNNING) ~= 0 and G.Allowed(C)
end

function G.Locked()
    if G.st.flags == 0 then return false end
    return G.Running(GSA1.Char)
end

-- the bit, and the stick's frame (both chained, 5.6; only for your character) -----------------------------------------------------
G.prevHostWaterFlags = G.prevHostWaterFlags or GSA1.HostWaterFlags
GSA1.HostWaterFlags = function(C)
    local flags = G.prevHostWaterFlags(C)
    if C ~= nil and C.kind == BIG_KIND and G.Allowed(C) then return bor(flags, gsa1.INPUT_GAME_CAMERA) end
    return flags
end

-- (the same numbers as Vector(fx, fy, fz):Angle(), in -180..180: no Vector made)
local function forward_angles(st)
    local fx, fy, fz = st.fx, st.fy, st.fz
    return math.deg(math.atan2(-fz, math.sqrt(fx * fx + fy * fy))), math.deg(math.atan2(fy, fx))
end

G.prevTickYaw = G.prevTickYaw or GSA1.TickYaw
GSA1.TickYaw = function(C)
    if G.st.flags ~= 0 and G.Running(C) then
        local _, yaw = forward_angles(G.st)
        return yaw
    end
    if G.prevTickYaw then return G.prevTickYaw(C) end
    return nil
end

-- the request ---------------------------------------------------------------------------------------------------------------------
local KIND_WORD = { [0] = "none", [1] = "aim", [2] = "lure", [3] = "catch", [4] = "other" }
local function poll(C)
    local st = G.st
    if cv.fish:GetInt() > 0 and C.kind == BIG_KIND and G.Present() then
        if gsa1.Camera(C.id, -1, st) ~= true then clear_request(st) end
    else
        clear_request(st)
    end
    -- one log line per request change (SA1_EVENT_CAMERA is for hosts that see the events; review R98.12)
    if st.fn ~= G.logFn or st.level ~= G.logLevel or st.adjust ~= G.logAdjust then
        G.logFn, G.logLevel, G.logAdjust = st.fn, st.level, st.adjust
        if GSA1.Log then
            GSA1.Log("gamecam", "%s's camera request: %s, level %d, adjust %d, function %08X, %s", C.title or "Big",
                KIND_WORD[st.kind] or "?", st.level, st.adjust, st.fn,
                band(st.flags, gsa1.CAMSTATE_RUNNING or 4) ~= 0 and "shown" or "not shown")
        end
    end
    -- the toggle lasts until this cast ends
    if G.toggleOff and band(st.flags, gsa1.CAMSTATE_ACTIVE or 1) == 0 then G.toggleOff = false end
end

-- the render bounds (fish098 4.4, a blocker): while it runs the box also holds the target and the eye; a change under 64 HU sets
-- nothing; the character's own box is back when the blend has ended
local bounds_lo, bounds_hi = Vector(), Vector()
local bounds_min, bounds_max = Vector(-640, -640, -320), Vector(640, 640, 640)    -- (as cl_render.lua, should that file not say)
function G.Bounds(C, running)
    local ent = C.ent
    if not IsValid(ent) or not ent.SetRenderBounds then return end
    local bmin, bmax = GSA1.RENDER_BOUNDS_MIN or bounds_min, GSA1.RENDER_BOUNDS_MAX or bounds_max
    if not running then
        if G.boundsSet and G.mix <= 0 then
            G.boundsSet, G.bounds = false, nil
            ent:SetRenderBounds(bmin, bmax)
        end
        return
    end
    local st, pos = G.st, C.drawPos
    local tx, ty, tz, ex, ey, ez = st.tx - pos.x, st.ty - pos.y, st.tz - pos.z, st.px - pos.x, st.py - pos.y, st.pz - pos.z
    local x0 = math.min(bmin.x, tx - BOUNDS_TARGET, ex - BOUNDS_EYE)
    local y0 = math.min(bmin.y, ty - BOUNDS_TARGET, ey - BOUNDS_EYE)
    local z0 = math.min(bmin.z, tz - BOUNDS_TARGET, ez - BOUNDS_EYE)
    local x1 = math.max(bmax.x, tx + BOUNDS_TARGET, ex + BOUNDS_EYE)
    local y1 = math.max(bmax.y, ty + BOUNDS_TARGET, ey + BOUNDS_EYE)
    local z1 = math.max(bmax.z, tz + BOUNDS_TARGET, ez + BOUNDS_EYE)
    local b = G.bounds
    if not b then
        b = { bmin.x, bmin.y, bmin.z, bmax.x, bmax.y, bmax.z }
        G.bounds = b
    end
    local abs = math.abs
    if abs(x0 - b[1]) <= BOUNDS_STEP and abs(y0 - b[2]) <= BOUNDS_STEP and abs(z0 - b[3]) <= BOUNDS_STEP and
        abs(x1 - b[4]) <= BOUNDS_STEP and abs(y1 - b[5]) <= BOUNDS_STEP and abs(z1 - b[6]) <= BOUNDS_STEP then
        return
    end
    b[1], b[2], b[3], b[4], b[5], b[6] = x0, y0, z0, x1, y1, z1
    bounds_lo:SetUnpacked(x0, y0, z0)
    bounds_hi:SetUnpacked(x1, y1, z1)
    G.boundsSet = true
    ent:SetRenderBounds(bounds_lo, bounds_hi)
end

-- the view (4.3) ------------------------------------------------------------------------------------------------------------------
local hull_min, hull_max = Vector(-5, -5, -5), Vector(5, 5, 5)
local trace_from, trace_to, trace_res = Vector(), Vector(), {}
local view_trace = { start = trace_from, endpos = trace_to, mins = hull_min, maxs = hull_max, mask = MASK_SOLID_BRUSHONLY,
                     output = trace_res }

-- the game's eye turned around the target by the orbit's offsets (view only: the game's numbers stay)
local function orbit_eye(st, ox, oy, oz)
    local dx, dy, dz = ox - st.tx, oy - st.ty, oz - st.tz
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist < 0.001 then return ox, oy, oz end
    local az = math.atan2(dy, dx) + math.rad(G.orbitY)
    local el = math.Clamp(math.asin(math.Clamp(dz / dist, -1, 1)) + math.rad(G.orbitP), -1.55, 1.55)
    local ce = math.cos(el)
    return st.tx + dist * ce * math.cos(az), st.ty + dist * ce * math.sin(az), st.tz + dist * math.sin(el)
end

-- what the game's camera shows now, into G.gameO / G.gameA / G.gameFov (they stay for the way back)
local function game_view(C, st)
    local pitch, yaw = forward_angles(st)
    G.eyeP, G.eyeY = pitch, yaw            -- the eye angles' numbers: the game's, an orbit is view only
    local ox, oy, oz = st.px, st.py, st.pz
    local orbit = cv.mouse:GetBool()
    if orbit then
        ox, oy, oz = orbit_eye(st, ox, oy, oz)
        pitch, yaw = pitch + G.orbitP, yaw + G.orbitY
    end
    if orbit or st.kind == gsa1.CAMKIND_LURE then
        trace_from:SetUnpacked(st.tx, st.ty, st.tz)
    else
        local p = C.drawPos
        trace_from:SetUnpacked(p.x, p.y, p.z + TRACE_ABOVE_BIG)
    end
    trace_to:SetUnpacked(ox, oy, oz)
    util.TraceHull(view_trace)
    local hit = trace_res.HitPos
    if hit and not trace_res.StartSolid then ox, oy, oz = hit.x, hit.y, hit.z end
    if not G.gameO then G.gameO = Vector() end
    G.gameO:SetUnpacked(ox, oy, oz)
    G.gameA = Angle(pitch, yaw, 0)
    G.gameFov = math.deg(st.fov or 0)
end

-- chase: the view of everybody else (the chase or first-person view, the chain's result). A new table when it shows
function G.View(chase, C)
    if C.kind ~= BIG_KIND then
        if G.mix > 0 then G.mix = 0 end    -- (no way to get here: a new character resets G)
        return nil
    end
    poll(C)
    local st = G.st
    G.chase, G.chaseFrame = chase, FrameNumber()
    local running = st.flags ~= 0 and band(st.flags, gsa1.CAMSTATE_RUNNING) ~= 0 and G.Allowed(C)
    -- the mix: FrameTime() / the blend; a cut of the game's camera stays a cut
    local blend = cv.blend:GetFloat()
    local mix = G.mix
    if running then
        if blend <= 0 or (mix > 0 and band(st.flags, gsa1.CAMSTATE_CUT) ~= 0) then
            mix = 1
        else
            mix = math.min(mix + FrameTime() / blend, 1)
        end
    elseif blend <= 0 then
        mix = 0
    else
        mix = math.max(mix - FrameTime() / blend, 0)
    end
    G.mix = mix
    if running then
        game_view(C, st)
    else
        G.orbitY, G.orbitP = 0, 0          -- cleared when the request ends
    end
    G.Bounds(C, running)
    if mix <= 0 or not G.gameO then return nil end
    -- your camera, and the way back: toward the live chase view
    local co, ca, go, ga = chase.origin, chase.angles, G.gameO, G.gameA
    local origin, angles
    if mix >= 1 then
        origin, angles = Vector(go), Angle(ga.p, ga.y, 0)
    else
        local na = math.NormalizeAngle
        origin = Vector(co.x + (go.x - co.x) * mix, co.y + (go.y - co.y) * mix, co.z + (go.z - co.z) * mix)
        angles = Angle(ca.p + na(ga.p - ca.p) * mix, ca.y + na(ga.y - ca.y) * mix, ca.r + na(0 - ca.r) * mix)
    end
    local fov = chase.fov
    if fov and cv.fov:GetBool() and G.gameFov and G.gameFov > 0 then
        fov = fov + (G.gameFov - fov) * mix -- CalcView's fov is 4:3-based, so 70 is the Dreamcast's 70
    end
    return { origin = origin, angles = angles, fov = fov, drawviewer = false }
end

G.prevViewOverride = G.prevViewOverride or GSA1.ViewOverride
GSA1.ViewOverride = function(view, C, ply)
    local ov = G.prevViewOverride and G.prevViewOverride(view, C, ply) or nil
    if C.kind ~= BIG_KIND then return ov end
    local chase = (type(ov) == "table" and ov.origin and ov.angles) and ov or view
    return G.View(chase, C) or ov
end

-- first person: from outside while it shows and on the way back (the line, Big and the lure would be invisible otherwise)
G.prevFirstPerson = G.prevFirstPerson or GSA1.FirstPerson
GSA1.FirstPerson = function()
    if G.mix > 0 and cv.first:GetBool() then return false end
    return G.prevFirstPerson()
end

-- followers keep the chase eye while this camera shows: a respawn drops them near Big, not above the lake (decision A9). The
-- default of this seam is GSA1.TickCamera (feat/cl_follower.lua); "The game uses this camera" off gives nothing there, as always
local follower_o, follower_t, follower_f = Vector(), Vector(), Vector()
function G.FollowerEye()
    local ch = G.chase
    if not ch or not ch.origin or not ch.angles then return nil end
    follower_o:Set(ch.origin)
    GSA1.AngleAxes(ch.angles, follower_f)
    follower_t:SetUnpacked(follower_o.x + follower_f.x * 100, follower_o.y + follower_f.y * 100, follower_o.z + follower_f.z * 100)
    return follower_o, follower_t
end
G.prevFollowerTickCamera = G.prevFollowerTickCamera or GSA1.FollowerTickCamera
GSA1.FollowerTickCamera = function(C)
    if G.mix > 0 and GSA1.cv.cam_real and GSA1.cv.cam_real:GetBool() and G.chaseFrame and FrameNumber() - G.chaseFrame <= 2 then
        return G.FollowerEye()
    end
    local prev = G.prevFollowerTickCamera or GSA1.TickCamera
    if prev then return prev(C) end
    return nil
end

-- the mouse, the right stick, the eye angles (4.5) ----------------------------------------------------------------------------------
-- The mouse is swallowed while it runs; the open emote wheel wins (its own hook takes the deltas and swallows too).
function G.MouseApply(cmd, x, y)
    if not G.Locked() then return nil end
    if GSA1.Wheel and GSA1.Wheel.open then return nil end
    if cv.mouse:GetBool() then
        local my, mp = GetConVar("m_yaw"), GetConVar("m_pitch")
        G.orbitY = math.Clamp(G.orbitY - (tonumber(x) or 0) * (my and my:GetFloat() or 0.022), -ORBIT_YAW, ORBIT_YAW)
        G.orbitP = math.Clamp(G.orbitP + (tonumber(y) or 0) * (mp and mp:GetFloat() or 0.022), -ORBIT_PITCH, ORBIT_PITCH)
    end
    if cmd then
        if cmd.SetMouseX then cmd:SetMouseX(0) end
        if cmd.SetMouseY then cmd:SetMouseY(0) end
    end
    return true
end
hook.Add("InputMouseApply", "gsa1_gamecam", GSA1.Guard("gamecam mouse", function(cmd, x, y, ang)
    return G.MouseApply(cmd, x, y)
end))

-- The eye angles ARE the game's at the end, so your camera continues from the direction you were last shown: the yaw hand-back
-- needs nothing else (bigfish review R3.6). Only once the blend in has ended: until then the chase view it blends from must stay
-- where it was.
local eye_ang = Angle()
function G.EyeAngles(cmd)
    if not GSA1.Char then return end
    if G.st.flags == 0 or not G.eyeP or G.mix < 1 or not G.Locked() then return end
    eye_ang.p, eye_ang.y, eye_ang.r = math.Clamp(G.eyeP, -PITCH_LIMIT, PITCH_LIMIT), G.eyeY, 0
    cmd:SetViewAngles(eye_ang)
end
hook.Add("CreateMove", "gsa1_gamecam", GSA1.Guard("gamecam eye", function(cmd)
    return G.EyeAngles(cmd)
end))

-- GSA1.PadView (cl_pad.lua, called from CreateMove before the buttons are cleared; like cl_wheel.lua's wrap): while it runs the
-- original gets a stand-in command, so the pending turn is used up, a camera reset dropped, and the view stays. R is read here:
-- the keyboard's +reload (no controller reaches it), only while the lure is in the water.
G.prevPadView = G.prevPadView or GSA1.PadView
local proxy = { cmd = nil }
function proxy:GetViewAngles() return self.cmd:GetViewAngles() end
function proxy:SetViewAngles() end
function proxy:GetMouseX() return 1 end
function proxy:GetMouseY() return 1 end
GSA1.PadView = function(cmd)
    local st = G.st
    if st.flags ~= 0 and st.kind == gsa1.CAMKIND_LURE then
        G.rDown = type(cmd.KeyDown) == "function" and cmd:KeyDown(IN_RELOAD) and true or false
    elseif G.rDown then
        G.rDown = false
    end
    local orig = G.prevPadView
    if not orig then return end
    if not G.Locked() then return orig(cmd) end
    proxy.cmd = cmd
    local ok, err = pcall(orig, proxy)
    proxy.cmd = nil
    if not ok and GSA1.Log then GSA1.Log("error", "GSA1.PadView (fishing camera): %s", tostring(err)) end
end

-- the ways to leave (4.6) ---------------------------------------------------------------------------------------------------------
-- R = the game's L + R, with the lure in the water and the option on (the game reads them: code_8C0E91E4.c:432)
function G.RKey(C)
    if C ~= GSA1.Char or not G.rDown or G.st.flags == 0 or G.st.kind ~= gsa1.CAMKIND_LURE or not cv.rkey:GetBool() then return 0 end
    if GSA1.Wheel and GSA1.Wheel.open then return 0 end
    if GSA1.InputBlocked and GSA1.InputBlocked() then return 0 end
    return bor(BTN_L, BTN_R)
end
-- cl_interact.lua's plain "function GSA1.ExtraButtons" comes after this file: a wrap at file scope would be lost, so it is made
-- once, at the first character, when every file has loaded (2.4 C4)
function G.InstallExtra()
    if G.extraDone then return end
    G.extraDone = true
    G.prevExtra = GSA1.ExtraButtons
    GSA1.ExtraButtons = function(C)
        local extra = G.prevExtra and G.prevExtra(C) or 0
        local r = G.RKey(C)
        if r ~= 0 then return bor(extra, r) end
        return extra
    end
end

-- "Look elsewhere for this cast": no bit until this cast ends; again: the same request from your eye
function G.Toggle()
    local C = GSA1.Char
    if not C or C.kind ~= BIG_KIND or G.st.flags == 0 or band(G.st.flags, gsa1.CAMSTATE_ACTIVE) == 0 then return false end
    G.toggleOff = not G.toggleOff
    if GSA1.Log then
        GSA1.Log("gamecam", "fishing camera: %s for this cast", G.toggleOff and "looking elsewhere" or "back on the game's camera")
    end
    return true
end
concommand.Add("gsa1_cam_fish_toggle", function() G.Toggle() end)

-- the toggle's key (polled before each tick; only for Big, only with a key)
function G.KeyThink(C)
    if C.kind ~= BIG_KIND then return end
    local code = cv.toggle_key:GetInt()
    if code <= 0 then
        G.toggleDown = false
        return
    end
    local ply = LocalPlayer()
    local busy = vgui.CursorVisible() or gui.IsGameUIVisible() or (ply.IsTyping ~= nil and ply:IsTyping())
    local down = not busy and input.IsButtonDown(code) or false
    if down and not G.toggleDown then G.Toggle() end
    G.toggleDown = down
end
hook.Add("GSA1PreTick", "gsa1_gamecam", function(C)
    if C and C.kind == BIG_KIND then G.KeyThink(C) end
end)

-- the character's life: a new world has no request. At the death the bit stops and the view blends back; the game itself would
-- stay on the request until the restart (fish098 2.5, owner question O-G6)
hook.Add("GSA1CharacterCreated", "gsa1_gamecam", function(C)
    G.InstallExtra()
    G.Reset()
    G.LogSettings()
end)
hook.Add("GSA1CharacterRemoved", "gsa1_gamecam", function(C)
    G.Reset()
end)
hook.Add("GSA1CharacterDied", "gsa1_gamecam", function(C)
    if C and C == GSA1.Char then G.dead = true end
end)

-- the session log: the settings (R.13's form: one line from this file, cl_log.lua stays as it is), once per change at a new character
function G.LogSettings()
    if not GSA1.Log then return end
    local line = string.format("settings 0.9.8: Big's fishing camera (gsa1_cam_fish) %s, blend %s s, mouse %s, the game's field "
        .. "of view %s, first person %s, R key %s, toggle key %s, module's feature %s", cv.fish:GetString(), cv.blend:GetString(),
        cv.mouse:GetString(), cv.fov:GetString(), cv.first:GetString(), cv.rkey:GetString(), cv.toggle_key:GetString(),
        G.Present() and "yes" or "no")
    if line == G.settingsLine then return end
    G.settingsLine = line
    GSA1.Log("settings", "%s", line)
end

-- the Camera page's rows (cl_menu.lua's seam, 5.6) ---------------------------------------------------------------------------------
-- a combo box that shows the ConVar's value, also after a change from the console (as cl_menu.lua's choice_combo)
local FISH_CHOICES = { { "Off", "0" }, { "Lure only", "1" }, { "As the game", "2" } }
local function fish_combo(panel)
    local combo = panel:ComboBox("Big's fishing camera")
    for _, c in ipairs(FISH_CHOICES) do combo:AddChoice(c[1], c[2]) end
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand("gsa1_cam_fish", tostring(data))
    end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local v = cv.fish:GetString()
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        local n = tonumber(v)
        for _, c in ipairs(FISH_CHOICES) do
            if tonumber(c[2]) == n then
                self:SetText(c[1])
                return
            end
        end
        self:SetText(v)
    end
    return combo
end

function G.Panel(panel)
    panel:Help("Big's fishing camera")
    local missing = GSA1.MissingFeatureText(G.NEEDS)
    if missing then
        panel:Help(missing)
        return
    end
    fish_combo(panel)
    panel:ControlHelp("As the game: behind Big while he aims and on the lure when it lands, with the game's own bright line. "
        .. "Lure only: your camera while he aims. Off: your camera, as 0.9.5. There are no fish in Garry's Mod yet: cast, watch "
        .. "and reel in.")
    panel:NumSlider("Blend from and to your camera (s)", "gsa1_cam_fish_blend", 0, 1.5, 2)
    panel:CheckBox("The mouse turns around the lure while fishing", "gsa1_cam_fish_mouse")
    panel:ControlHelp("Off: the mouse does nothing while this camera shows, as in the game; WASD moves the cursor. The view stops "
        .. "at walls by G-SA1's own trace.")
    panel:CheckBox("The game's field of view (70) while fishing", "gsa1_cam_fish_fov")
    panel:CheckBox("Also when you play in first person", "gsa1_cam_fish_first")
    panel:ControlHelp("Off: first person stays first person, and the line stays invisible.")
    panel:CheckBox("R reels in at once (the game's L + R)", "gsa1_cam_fish_rkey")
    panel:ControlHelp("Only while the lure is in the water, on the keyboard. A controller's two bumpers do it anyway; holding jump "
        .. "reels in slowly.")
    panel:Help("Look elsewhere for this cast")
    local b = vgui.Create("DBinder", panel)
    if b.SetConVar then b:SetConVar("gsa1_cam_fish_toggle_key") end
    if b.SetTall then b:SetTall(28) end
    panel:AddItem(b)
    panel:ControlHelp("Back to your camera until this cast ends; press it again for the game's. Also the console command "
        .. "gsa1_cam_fish_toggle.")
end
GSA1.CameraPanelExtra = function(panel)
    local ok, err = xpcall(G.Panel, debug.traceback, panel)
    if not ok then
        panel:Help("These options could not be shown: " .. tostring(err))
        if GSA1.Log then GSA1.Log("error", "fishing camera options: %s", tostring(err)) end
    end
end
