-- G-SA1 photo mode (0.9.9d, the client's part; the owner: "the photomode idea is awesome and I love it"; sadc docs/research/photo099d.md with its review RP.1-16; the owner's later answers win over it: world freeze optional, completely untouchable;
-- feat/sv_photo.lua is the server's part, tests/feat_photo_test.lua the test, tests/feat_photo_binding_test.cpp the pin against the real game code).
-- One key (K) or the command gsa1_photo: you and your followers stop mid-pose; WASD, Space, Ctrl fly a free camera, the mouse looks, the wheel zooms, right mouse held tilts and zooms, R resets; the key again, Escape, the page's button or the command
-- go on from the same moment.
-- A FREEZE IS NOT A TICK OF NO TIME: WHILE FROZEN NOTHING CALLS THE WORLDS. tick_character (cl_character.lua) and GSA1.FollowersThink (wrapped here) return at their first line, so no gsa1.Tick, no gsa1.FollowersTick, no gsa1.Render, no GSA1PreTick and the
-- like: nothing can be written, and the pose, the face, the effects stay what the module's arrays hold. gsa1.PrepareView, which works from those arrays, makes them for the new eye every frame.
-- THE STATES (only GSA1.PhotoThink moves them, once a frame before the tick; the command, Escape and the page only leave a request [RP.5]): "off"; "on" (the free camera, the blocked input); "thaw" (one more frame without a tick: the input is free, the free
-- camera has let go, so CalcView builds the real view and the first tick does not hand the game the photo camera; until a real view has been handed out, or 3 frames when none comes: a view entity, another addon's CalcView). GSA1.PhotoFrozen() is true in on
-- and thaw. Ended at once, no extra frame, GSA1.view made old [RP.6], when the world goes anyway: a re-creation or respawn, the player dying, a character made while followers alone were frozen, the last follower gone, ShutDown.
-- Keys that flew the camera are no press for the game [RP.3]: what is down at the thaw and was not at the freeze stays out of the user command, and out of GSA1.PadInput, until released. A key held through stays on: a long jump goes on.
-- Untouchable (the owner's answer 13): hits arriving from the server are dropped here (I.HitBlocked), feat/sv_photo.lua stops them there, for a character in multiplayer, for anyone in single player (who may: the head of that file); nothing in the world can reach a character that runs no pair. A server teleport waits for the end. An error in this
-- file's own code ends photo mode for the session and leaves the ticks running [RP.11].
-- Not frozen: one comparison in each of about 15 seams and wraps, no module call, no garbage, no ConVar. No state is kept in a ConVar, so a crash or a map change cannot leave anything frozen on this side.
-- UNVERIFIED, only the game can show: photo099d.md section 14 and the owner's checklist.
GSA1 = GSA1 or {}
local P = GSA1.Photo
if not P then error("gsa1/feat/sh_photo.lua did not load: photo mode needs it") end
local cv = P.cv
local band, bor, bnot = bit.band, bit.bor, bit.bnot
local IN_SPEED_, IN_WALK_, IN_JUMP_, IN_DUCK_, IN_ATTACK2_, IN_RELOAD_ = IN_SPEED or 131072, IN_WALK or 262144, IN_JUMP or 2, IN_DUCK or 4, IN_ATTACK2 or 2048, IN_RELOAD or 8192
local PAD_START, PAD_A, PAD_B = 0x0010, 0x1000, 0x2000
local Fo, B, I, H, S, G, O, CS = GSA1.Followers, GSA1.Board, GSA1.Interact, GSA1.Hud, GSA1.SunShadow, GSA1.GameCam, GSA1.Objects, GSA1.CharSelect

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("photo", fmt, ...) end
end

P.state = P.state or "off"
P.cam = P.cam or { pos = Vector(), ang = Angle(), viewAng = Angle(), viewPos = Vector(), fov = 75, fov0 = 75, vx = 0, vy = 0, vz = 0 }
P.keys, P.moveF, P.moveS = 0, 0, 0
P.lastButtons, P.heldMask, P.frozenButtons = 0, 0, 0
P.lastPad, P.padMask, P.frozenPad = 0, 0, 0
P.keyWas, P.padWas, P.reloadWas = false, false, false
P.boxes = P.boxes or {}
P.avgDt = P.avgDt or (1 / 60)
local cam = P.cam
local c_fwd, c_right, c_up = Vector(), Vector(), Vector()

function GSA1.PhotoFrozen() return P.state ~= "off" end
function P.FreeCam() return P.state == "on" and GSA1.Char ~= nil end
function GSA1.PhotoNoShadow() return P.state ~= "off" and cv.shadows ~= nil and cv.shadows:GetBool() end
function GSA1.PhotoHoldsMusic() return P.state ~= "off" and cv.jukebox ~= nil and not cv.jukebox:GetBool() end
local frozen = GSA1.PhotoFrozen

-- the wall clocks moved on by the freeze's length (3.5) --------------------------------------------------------------------------------------------------------
local function shift(t, k, s)
    if t and t[k] then t[k] = t[k] + s end
end
local function shift_board(b, s)
    if not b then return end
    shift(b.walk, "deadline", s)
    shift(b.fwalk, "deadline", s)
    shift(b.leaving, "at", s)
    shift(b.entering, "at", s)
    shift(b.pendingFree, "at", s)
end
function P.ShiftClocks(s)
    local C = GSA1.Char
    if C then
        shift(C, "respawnAt", s)
        shift(C, "fallbackAt", s)
        shift(C, "killAsked", s)
        shift_board(C.board, s)
    end
    if I then
        shift(I.pendingKill, "untilT", s)
        shift(I, "actionUntil", s)
    end
    if Fo then
        for _, F in ipairs(Fo.list) do
            shift(F, "guardUntil", s)
            shift_board(F.board, s)
        end
        shift(Fo.emote, "waitUntil", s)
        shift(Fo.emote, "nextTry", s)
    end
    if B and B.leftQueue then
        for _, e in ipairs(B.leftQueue) do shift(e, "at", s) end
    end
end

-- the server's part ---------------------------------------------------------------------------------------------------------------------------------------------
local function server_has()
    return util.NetworkStringToID(P.NET) ~= 0
end
local eye_sent = Vector()
local function send(flags, eye)
    if not server_has() then return end
    net.Start(P.NET)
    net.WriteUInt(flags, 2)
    net.WriteBool(eye ~= nil)
    if eye then net.WriteVector(eye) end
    net.SendToServer()
end
function P.WantFlags()
    if P.state ~= "on" then return 0 end
    local f = 1
    if cv.world:GetBool() and game.SinglePlayer() then f = 3 end
    return f
end
-- the flags at once when they change; while on every 2 s, and the eye at most 4 times a second after 128 units of movement (4.2)
local function server_think(now)
    local want = P.WantFlags()
    local eye = nil
    if want ~= 0 and P.FreeCam() and cam.started then
        local p = cam.pos
        local dx, dy, dz = p.x - eye_sent.x, p.y - eye_sent.y, p.z - eye_sent.z
        if not P.eyeAt or (now - P.eyeAt >= 0.25 and dx * dx + dy * dy + dz * dz >= 128 * 128) or now - (P.sentAt or 0) >= 2 then eye = p end
    end
    if want ~= P.sentFlags or eye or (want ~= 0 and now - (P.sentAt or 0) >= 2) then
        P.sentFlags, P.sentAt = want, now
        if eye then
            P.eyeAt = now
            eye_sent:Set(eye)
        end
        send(want, eye)
        if want == 0 then P.worldMask = nil end
    end
end
net.Receive(P.NET, function()
    P.worldMask = net.ReadUInt(3)
    if P.worldMask ~= P.WORLD_ALL then
        local no = {}
        for _, e in ipairs(P.WORLD) do
            if band(P.worldMask, e.bit) == 0 then no[#no + 1] = e.name end
        end
        log("the world could not be frozen entirely: %s did not take", table.concat(no, ", "))
    end
end)

-- what is hidden ------------------------------------------------------------------------------------------------------------------------------------------------
local function shadows_think()
    if not S then return end
    local want = GSA1.PhotoNoShadow() and true or false
    if want ~= (S.hiddenForPhoto or false) then
        S.hiddenForPhoto = want
        if S.Apply then S.Apply() end
    end
end

-- the states ----------------------------------------------------------------------------------------------------------------------------------------------------
local function refuse_why()
    if not GSA1.mod then return "the module is not loaded" end
    if not GSA1.Char and not (Fo and Fo.list[1]) then return "nothing to freeze" end
    local W = GSA1.Wheel
    if W and W.open then return "the emote wheel is open" end
    if P.prevInputBlocked and P.prevInputBlocked() then return "a panel has the input" end
    local ply = LocalPlayer()
    if IsValid(ply) and ply.Alive and not ply:Alive() then return "the player is dead" end
    if I and I.pendingKill then return "a kill is on its way" end
    return nil
end

local function start(now)
    local why = refuse_why()
    if why then
        log("not started: %s", why)
        return
    end
    P.state, P.t0, P.frames, P.moved, P.pinned, P.hintLines = "on", now, 0, false, false, nil
    cam.started, cam.vx, cam.vy, cam.vz = false, 0, 0, 0
    P.frozenButtons, P.frozenPad = P.lastButtons, P.lastPad
    P.keys, P.moveF, P.moveS = P.lastButtons, 0, 0
    P.viewFrame = FrameNumber()
    P.fpsBefore = 1 / math.max(P.avgDt, 1e-3)
    local C = GSA1.Char
    log("frozen at (%.0f %.0f %.0f), action %s, %d followers", C and C.drawPos.x or 0, C and C.drawPos.y or 0, C and C.drawPos.z or 0, tostring(C and C.state and C.state.action or "-"), Fo and #Fo.list or 0)
end

local function ended_log(now, why)
    local t = now - (P.t0 or now)
    log("frozen %.1f s, %d followers, %.1f fps; %.1f fps before; ended by %s", t, Fo and #Fo.list or 0, (P.frames or 0) / math.max(t, 1e-3), P.fpsBefore or 0, tostring(why))
end

-- the one way to off: what waited for the end goes on
local function to_off()
    P.state = "off"
    shadows_think()
    if B and P.boxes[1] and P.prevOnBox then
        local q = P.boxes
        P.boxes = {}
        for _, a in ipairs(q) do P.prevOnBox(unpack(a, 1, 9)) end
    end
    local m = P.teleport
    if m and P.prevHandle then
        P.teleport = nil
        local ok, err = pcall(P.prevHandle, m)
        if not ok then log("the teleport that waited: %s", tostring(err)) end
    end
end

local function thaw(now, why)
    P.state, P.thawFrames, P.realView = "thaw", 0, false
    P.ShiftClocks(now - (P.t0 or now))
    ended_log(now, why)
    -- [RP.3] what is down now and was not at the freeze: no press for the game
    P.heldMask = band(P.lastButtons, bnot(P.frozenButtons))
    P.padMask = band(P.lastPad, bnot(P.frozenPad))
    shadows_think()
end

-- [RP.6] the world goes anyway: no extra frame, and the photo camera is no view any more
function P.EndNow(why)
    if P.state == "off" then return end
    local now = SysTime()
    local was = P.state
    if was == "on" then
        P.ShiftClocks(now - (P.t0 or now))
        ended_log(now, why)
    end
    local v = GSA1.view
    if v then v.frame = -1e9 end
    P.state = "off"
    P.heldMask, P.padMask = band(P.lastButtons, bnot(P.frozenButtons)), band(P.lastPad, bnot(P.frozenPad))
    server_think(now)
    to_off()
end

-- [RP.11] a failure of this file's own code ends photo mode, for the session; the ticks and the sound go on
function P.Fail(where, err)
    P.broken = true
    P.state = "off"
    local v = GSA1.view
    if v then v.frame = -1e9 end
    if S and S.hiddenForPhoto then
        S.hiddenForPhoto = false
        if S.Apply then pcall(S.Apply) end
    end
    if server_has() then pcall(send, 0) end
    P.sentFlags = 0
    log("error in %s: %s; photo mode is off until the next map", where, tostring(err))
    ErrorNoHalt("[G-SA1] photo mode: " .. tostring(err) .. "\n")
end

-- the key: its own busy test asks the chain BELOW this file's wrap, or the key could never end what it started
local function busy()
    if vgui.CursorVisible() or gui.IsGameUIVisible() then return true end
    if gui.IsConsoleVisible and gui.IsConsoleVisible() then return true end
    if system.HasFocus and not system.HasFocus() then return true end
    local ply = LocalPlayer()
    if IsValid(ply) and ply.IsTyping ~= nil and ply:IsTyping() == true then return true end
    if P.prevInputBlocked and P.prevInputBlocked() then return true end
    return false
end

-- the free camera's step: eased, so no jerk at any frame rate; stepped with the real frame time, so it holds still when single player is paused
local hull_min, hull_max = Vector(-5, -5, -5), Vector(5, 5, 5)
local c_to, c_res = Vector(), {}
local c_trace = { start = cam.pos, endpos = c_to, mins = hull_min, maxs = hull_max, mask = MASK_SOLID_BRUSHONLY or 16395, output = c_res }
local function cam_step(dt)
    if not cam.started or dt <= 0 then return end
    if FrameNumber() - (P.viewFrame or 0) > 1 then return end       -- a view entity's view wins: the free camera waits where it was
    local keys = P.keys
    local f, s, u = P.moveF, P.moveS, 0
    if band(keys, IN_JUMP_) ~= 0 then u = u + 1 end
    if band(keys, IN_DUCK_) ~= 0 then u = u - 1 end
    local p = GSA1.pad
    if p and p.connected then
        if (p.sx or 0) ~= 0 or (p.sy or 0) ~= 0 then f, s = p.sy or 0, p.sx or 0 end
        local raw = p.raw or 0
        if band(raw, PAD_A) ~= 0 then u = u + 1 end
        if band(raw, PAD_B) ~= 0 then u = u - 1 end
    end
    local speed = cv.speed:GetFloat()
    if band(keys, IN_SPEED_) ~= 0 then speed = speed * 4 end
    if band(keys, IN_WALK_) ~= 0 then speed = speed * 0.25 end
    if GSA1.AngleAxes then GSA1.AngleAxes(cam.ang, c_fwd, c_right, c_up) else c_fwd:Set(cam.ang:Forward()) c_right:Set(cam.ang:Right()) end
    local wx, wy, wz = c_fwd.x * f + c_right.x * s, c_fwd.y * f + c_right.y * s, c_fwd.z * f + c_right.z * s + u
    local l = math.sqrt(wx * wx + wy * wy + wz * wz)
    if l > 1 then wx, wy, wz = wx / l, wy / l, wz / l end
    if l > 0 then P.moved = true end
    local k = 1 - math.exp(-12 * dt)
    cam.vx, cam.vy, cam.vz = cam.vx + (wx * speed - cam.vx) * k, cam.vy + (wy * speed - cam.vy) * k, cam.vz + (wz * speed - cam.vz) * k
    if l == 0 and cam.vx * cam.vx + cam.vy * cam.vy + cam.vz * cam.vz < 0.25 then
        cam.vx, cam.vy, cam.vz = 0, 0, 0
        return
    end
    c_to:SetUnpacked(cam.pos.x + cam.vx * dt, cam.pos.y + cam.vy * dt, cam.pos.z + cam.vz * dt)
    -- stops at the map's brushes, keeps out of the void; props and characters are passed through; a start inside a brush moves freely until it is out
    local r = util.TraceHull(c_trace) or c_res
    if r.StartSolid or r.AllSolid or not r.HitPos then
        cam.pos:Set(c_to)
    else
        cam.pos:Set(r.HitPos)
    end
end

local function pad_raw()
    local p = GSA1.pad
    return p and p.connected and (p.raw or 0) or 0
end

local function think_body(now)
    -- [RP.2] what loads after this file and replaces a function: wrapped once, here
    if not P.lateDone then P.LateWraps() end
    -- a teleport that waited through a re-creation: now GSA1.Char is the new character (GSA1CharacterLeaving below)
    local tm = P.teleportNext
    if tm then
        P.teleportNext = nil
        local ok, err = pcall(P.prevHandle, tm)
        if not ok then log("the teleport that waited: %s", tostring(err)) end
    end
    local dt = RealFrameTime()
    if P.state == "off" then
        if dt > 0 then P.avgDt = P.avgDt + (dt - P.avgDt) * math.min(dt / 10, 1) end
    else
        P.frames = (P.frames or 0) + 1
    end
    local p = GSA1.pad
    P.lastPad = p and p.connected and (p.buttons or 0) or 0
    -- the key, the button: the edge, not while something else has the input
    local want = P.request
    P.request = nil
    local code = cv.key:GetInt()
    local down = code > 0 and input ~= nil and input.IsButtonDown(code) or false
    if down and not P.keyWas and not busy() then want = want or "the key" end
    P.keyWas = down
    local pb = cv.pad:GetInt()
    local pdown = pb > 0 and band(pad_raw(), pb) == pb
    if pdown and not P.padWas and not busy() then want = want or "the button" end
    P.padWas = pdown
    local st = P.state
    if st == "off" then
        if want then start(now) end
    elseif st == "on" then
        -- the ways out that are not asked for
        local ply = LocalPlayer()
        if IsValid(ply) and ply.Alive and not ply:Alive() then
            P.EndNow("the player's death")
        elseif not GSA1.Char and not (Fo and Fo.list[1]) then
            P.EndNow("nothing left to freeze")
        elseif CS and CS.IsOpen and CS.IsOpen() then
            thaw(now, "Character Select")
        elseif want then
            thaw(now, want)
        else
            cam_step(dt)
        end
    elseif st == "thaw" then
        P.thawFrames = P.thawFrames + 1
        if P.realView or P.thawFrames >= 3 then to_off() end
    end
    if P.state == "on" then
        shadows_think()
        server_think(now)
    elseif P.sentFlags and P.sentFlags ~= 0 then
        server_think(now)
    end
end

function GSA1.PhotoThink(now)
    if P.broken then return end
    local ok, err = pcall(think_body, now)
    if not ok then P.Fail("GSA1.PhotoThink", err) end
    -- (what it costs while frozen: the hitch section "Photo", photo099d.md section 8; nothing while off)
    if P.state ~= "off" and GSA1.HitchAdd then GSA1.HitchAdd("Photo", SysTime() - now) end
end

-- the user command, before the hook reads it ---------------------------------------------------------------------------------------------------------------------
local pad_proxy = {}
function pad_proxy:GetViewAngles() return Angle(cam.ang.p, cam.ang.y, 0) end
function pad_proxy:SetViewAngles(a)
    if not cam.started then return end
    cam.ang.p, cam.ang.y = math.Clamp(a.p, -89, 89), a.y
end
function pad_proxy:GetMouseX() return 1 end
function pad_proxy:GetMouseY() return 1 end
local cv_fwd, cv_side
local function cmd_body(cmd)
    local btn = cmd.GetButtons and cmd:GetButtons() or 0
    P.lastButtons = btn
    if P.state == "on" then
        P.keys = btn
        cv_fwd, cv_side = cv_fwd or GetConVar("cl_forwardspeed"), cv_side or GetConVar("cl_sidespeed")
        P.moveF, P.moveS = cmd:GetForwardMove() / math.max(cv_fwd and cv_fwd:GetFloat() or 10000, 1), cmd:GetSideMove() / math.max(cv_side and cv_side:GetFloat() or 10000, 1)
        -- R: the field of view back, no tilt, as the Camera's Reload
        local r = band(btn, IN_RELOAD_) ~= 0
        if r and not P.reloadWas and cam.started then
            cam.fov, cam.ang.r = cam.fov0, 0
        end
        P.reloadWas = r
        -- the real view angles are pinned, not restored: +left and the like move them past the mouse hook, and they are the next tick's stick frame
        if not P.pinned then
            P.pin, P.pinned = cmd:GetViewAngles(), true
        end
        cmd:SetViewAngles(P.pin)
        -- the pending turn of the right stick looks with the camera, and is used up: CreateMove does not call GSA1.PadView while blocked, and it would swing the view at thaw
        if GSA1.PadView then GSA1.PadView(pad_proxy) end
    elseif P.heldMask ~= 0 then
        if cmd.SetButtons then cmd:SetButtons(band(btn, bnot(P.heldMask))) end
        P.heldMask = band(P.heldMask, btn)
    end
end
function GSA1.PhotoCmd(cmd)
    if P.broken then return end
    local ok, err = pcall(cmd_body, cmd)
    if not ok then P.Fail("GSA1.PhotoCmd", err) end
end

-- the mouse: as the Camera, READ gamemodes/sandbox/entities/weapons/gmod_camera.lua: slower when zoomed in; right mouse held: up and down zooms, left and right tilts ---------
local cv_yaw, cv_pitch
local function mouse_body(cmd, x, y)
    if not (P.FreeCam() and cam.started) then return nil end
    x, y = tonumber(x) or 0, tonumber(y) or 0
    if band(P.keys, IN_ATTACK2_) ~= 0 then
        local dt = RealFrameTime()
        cam.fov = math.Clamp(cam.fov + y * dt * 6.6, 5, 150)
        cam.ang.r = cam.ang.r + x * dt * 1.65
    else
        cv_yaw, cv_pitch = cv_yaw or GetConVar("m_yaw"), cv_pitch or GetConVar("m_pitch")
        local sens = cam.fov / math.max(cam.fov0, 1)
        cam.ang.y = cam.ang.y - x * (cv_yaw and cv_yaw:GetFloat() or 0.022) * sens
        cam.ang.p = math.Clamp(cam.ang.p + y * (cv_pitch and cv_pitch:GetFloat() or 0.022) * sens, -89, 89)
    end
    if x ~= 0 or y ~= 0 then P.moved = true end
    if cmd then
        if cmd.SetMouseX then cmd:SetMouseX(0) end
        if cmd.SetMouseY then cmd:SetMouseY(0) end
    end
    return true
end
hook.Add("InputMouseApply", "gsa1_photo", function(cmd, x, y)
    if P.state ~= "on" or P.broken then return end
    local ok, r = pcall(mouse_body, cmd, x, y)
    if not ok then
        P.Fail("the mouse", r)
        return
    end
    return r
end)

-- the wraps: each keeps the one it replaced, so a Lua refresh does not stack them; each answers as if it were not there unless photo mode is on ----------------------------
P.prevFollowersThink = P.prevFollowersThink or GSA1.FollowersThink
GSA1.FollowersThink = function(now)
    if P.state ~= "off" then
        if Fo then Fo.last = now end
        return
    end
    return P.prevFollowersThink(now)
end

P.prevInputBlocked = P.prevInputBlocked or GSA1.InputBlocked
GSA1.InputBlocked = function()
    if P.state == "on" then return true end
    -- [RP.4] Start also reaches Source as Escape (MEASURED r099a/misc/diagnosis.md L1); left by Escape, Start's edge must open nothing, whichever came first
    local until_t = P.startGuard
    if until_t then
        if SysTime() >= until_t then
            P.startGuard = nil
        elseif band(pad_raw(), PAD_START) ~= 0 then
            return true
        end
    end
    return P.prevInputBlocked()
end

P.prevFirstPerson = P.prevFirstPerson or GSA1.FirstPerson
GSA1.FirstPerson = function()
    if P.FreeCam() then return false end
    return P.prevFirstPerson()
end

P.prevViewOverride = P.prevViewOverride or GSA1.ViewOverride
GSA1.ViewOverride = function(view, C, ply)
    local ov = P.prevViewOverride(view, C, ply)
    if P.state == "on" then
        -- the chain ran, so the fishing camera's blend and bounds stay right; its answer is dropped
        local base = ov or view
        if not cam.started then
            cam.started = true
            cam.pos:Set(base.origin)
            local a = base.angles
            cam.ang.p, cam.ang.y, cam.ang.r = a.p, a.y, a.r or 0
            cam.fov = base.fov or cam.fov
            cam.fov0 = cam.fov
        end
        P.viewFrame = FrameNumber()
        cam.viewPos:Set(cam.pos)
        cam.viewAng.p, cam.viewAng.y, cam.viewAng.r = cam.ang.p, cam.ang.y, cam.ang.r
        return { origin = cam.viewPos, angles = cam.viewAng, fov = cam.fov, drawviewer = false }
    elseif P.state == "thaw" then
        P.realView = true
    end
    return ov
end

P.prevBindOverride = P.prevBindOverride or GSA1.BindOverride
GSA1.BindOverride = function(ply, bind, pressed, code)
    if P.FreeCam() and (bind == "invprev" or bind == "invnext") then
        if pressed and cam.started then
            local f = bind == "invprev" and 0.92 or 1 / 0.92
            cam.fov = math.Clamp(cam.fov * f, 5, 150)
        end
        return true
    end
    -- a key that has a Garry's Mod bind is swallowed while there is something to freeze, as the wheel's TAB
    local k = cv.key:GetInt()
    if k > 0 and (GSA1.Char or (Fo and Fo.list[1])) then
        if code ~= nil then
            if code == k then return true end
        else
            local name = input and input.LookupKeyBinding and input.LookupKeyBinding(k)
            if name and bind and string.lower(name) == bind then return true end
        end
    end
    return P.prevBindOverride(ply, bind, pressed, code)
end

-- [RP.3] the controller's buttons at the thaw
if GSA1.PadInput then
    P.prevPadInput = P.prevPadInput or GSA1.PadInput
    GSA1.PadInput = function()
        local sx, sy, b = P.prevPadInput()
        if b and P.padMask ~= 0 then
            local d = b
            b = band(b, bnot(P.padMask))
            P.padMask = band(P.padMask, d)
        end
        return sx, sy, b
    end
end

if G and G.Locked then
    -- the fishing camera's mouse and pad wrap stand aside while the free camera is on; G.View still runs in the chain
    P.prevLocked = P.prevLocked or G.Locked
    G.Locked = function()
        if P.FreeCam() then return false end
        return P.prevLocked()
    end
end

if H and H.Visible then
    P.prevHudVisible = P.prevHudVisible or H.Visible
    H.Visible = function()
        if P.state ~= "off" and cv.hud:GetBool() then return false end
        return P.prevHudVisible()
    end
end

if I then
    if I.HitBlocked then
        -- the owner's answer 13: nothing lands, nothing wakes you, single player or not, in any damage mode
        P.prevHitBlocked = P.prevHitBlocked or I.HitBlocked
        I.HitBlocked = function(C)
            if P.state ~= "off" then return "frozen for a photo: untouchable" end
            return P.prevHitBlocked(C)
        end
    end
    if I.OnPlayerDied then
        P.prevOnPlayerDied = P.prevOnPlayerDied or I.OnPlayerDied
        I.OnPlayerDied = function(d)
            P.EndNow("the player's death")
            return P.prevOnPlayerDied(d)
        end
    end
    if I.KeyThink then
        P.prevKeyThink = P.prevKeyThink or I.KeyThink
        I.KeyThink = function(C)
            if P.state ~= "off" then return end
            return P.prevKeyThink(C)
        end
    end
end

if B then
    if B.LeftPump then
        P.prevLeftPump = P.prevLeftPump or B.LeftPump
        B.LeftPump = function()
            if P.state ~= "off" then return end
            return P.prevLeftPump()
        end
    end
    if B.OnBox then
        -- the server's word about a Board box can call gsa1.Board: kept for the end
        P.prevOnBox = P.prevOnBox or B.OnBox
        B.OnBox = function(...)
            if P.state ~= "off" then
                if #P.boxes < 16 then P.boxes[#P.boxes + 1] = { ... } end
                return
            end
            return P.prevOnBox(...)
        end
    end
    if B.CameraMove then
        -- [RP.7] it eases the view yaw behind the board: nothing while frozen, its clock kept moving, or the first call after would swing the yaw by its clamp's 0.1 s
        P.prevCameraMove = P.prevCameraMove or B.CameraMove
        B.CameraMove = function(cmd)
            if P.state ~= "off" then
                if B.cam then B.cam.last = SysTime() end
                return false
            end
            return P.prevCameraMove(cmd)
        end
    end
end

if O and O.ViewTan then
    -- [the plan's 3.6] holds its last answer: the photo's field of view is no game's view
    P.prevViewTan = P.prevViewTan or O.ViewTan
    O.ViewTan = function(now)
        if P.state ~= "off" then return P.lastTan or P.prevViewTan(now) end
        P.lastTan = P.prevViewTan(now)
        return P.lastTan
    end
end

-- [RP.2] cl_teleport.lua loads after this file, and its "function P.Handle" would replace a wrap made here. Answer 13: a teleport does not wake you either: it waits for the end, the last one wins; the server has been told "not moved"
function P.LateWraps()
    P.lateDone = true
    local T = GSA1.Teleport
    if T and T.Handle then
        P.prevHandle = P.prevHandle or T.Handle
        T.Handle = function(m)
            if P.teleportNext and not m.loop then P.teleportNext = nil end      -- (one that waited for the new character: this one came after it, and the last one wins)
            if P.state ~= "off" and not m.loop then
                P.teleport = m
                log("a teleport to (%.0f %.0f %.0f) waits for the end of the freeze", m.pos.x, m.pos.y, m.pos.z)
                return "frozen for a photo"
            end
            return P.prevHandle(m)
        end
    end
end

-- the ways out and the hooks -----------------------------------------------------------------------------------------------------------------------------------------
-- (only requests: they can come at any moment of a frame, and only GSA1.PhotoThink moves the state [RP.5])
function P.Request(why)
    P.request = why or "the command"
end
concommand.Add("gsa1_photo", function() P.Request("the command") end, nil, "G-SA1: photo mode on or off: you and your followers freeze mid-pose (Q menu > Options > G-SA1 > Photo mode)")

-- Escape leaves and does not open the game's menu; the second Escape opens it. If the engine shows the menu anyway photo mode just stays
hook.Add("OnPauseMenuShow", "gsa1_photo", function()
    if P.state ~= "on" then return end
    P.Request("Escape")
    P.startGuard = SysTime() + 0.25
    return false
end)

local guard = GSA1.Guard or function(_, fn) return fn end
hook.Add("GSA1CharacterLeaving", "gsa1_photo", guard("photo", function(C, how)
    -- a teleport that waited would go to the world about to be destroyed, and GSA1.Recreate has taken the old place already (r099d/verify/photo_attack.txt A4): it goes to the next character, in the next GSA1.PhotoThink, when GSA1.Char is that one.
    -- A respawn goes to its spawn point, as it does when the teleport came just before it without photo mode: the teleport is dropped here, never run. 0.9.9e: P.EndNow would have run it inside destroy_character; the real
    -- module has no gsa1.Warp, so that was GSA1.Recreate inside the destroy, and GSA1.Respawn then left that new world with no owner (r099d/verify2/nowarp.txt)
    if how == "respawned" then
        if P.teleport or P.teleportNext then log("the teleport that waited is dropped: the character respawns at its spawn point") end
        P.teleport, P.teleportNext = nil, nil
    elseif P.teleport then
        P.teleportNext, P.teleport = P.teleport, nil
    end
    P.EndNow("the character is " .. tostring(how))
end))
hook.Add("GSA1CharacterCreated", "gsa1_photo", guard("photo", function() P.EndNow("a character was made") end))
hook.Add("ShutDown", "gsa1_photo", function() pcall(P.EndNow, "the map's end") end)

-- a follower made while frozen stands at its first pose: its world has rendered one, and only a tick would read it (READ session.cpp create, Fo.AfterTick)
hook.Add("GSA1FollowerCreated", "gsa1_photo", guard("photo", function(F)
    if P.state == "off" or not (F and F.id and F.batches) then return end
    gsa1.Batches(F.id, F.batches)
    F.batchGen, F.matsDirty = (F.batchGen or -1) + 1, true
end))

-- everything hidden, chat kept while typing [RP.12]: a hidden chat line takes every key with nothing on screen
hook.Add("HUDShouldDraw", "gsa1_photo", function(name)
    if P.state == "off" or not cv.hud:GetBool() then return end
    if name == "CHudChat" then
        local ply = LocalPlayer()
        if IsValid(ply) and ply.IsTyping ~= nil and ply:IsTyping() == true then return end
    end
    return false
end)

-- the reminder: four seconds, or until the camera first moves; in DrawOverlay, so a hidden HUD does not hide it
function P.HintText()
    local k = cv.key:GetInt()
    local W = GSA1.Wheel
    local name = k > 0 and W and W.KeyName and W.KeyName(k) or nil
    return "Photo mode: fly with WASD, Space, Ctrl; Shift fast, Alt slow; wheel zooms; hold right mouse to tilt; R resets. " .. (name and (name .. " or Escape") or "Escape") .. " to leave."
end
-- as many lines as it takes to fit maxw (at about 15 px a letter, UNVERIFIED by eye, the text is about 2000 px: one line on the owner's 3440, clipped at both ends on a 1920 one)
function P.HintLines(maxw, width_of)
    local lines, cur = {}, nil
    for word in string.gmatch(P.HintText(), "%S+") do
        local try = cur and (cur .. " " .. word) or word
        if cur and width_of(try) > maxw then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    lines[#lines + 1] = cur
    return lines
end
local function hint_width(s) return (surface.GetTextSize(s)) end
P.HINT_SIZE = 32    -- DermaLarge's size: the text module's element keeps it (feat/cl_text.lua: gsa1_text_fonts; off, or the font not found: exactly DermaLarge)
hook.Add("DrawOverlay", "gsa1_photo", function()
    if P.state ~= "on" or P.moved or not GSA1.Char or not cv.hint:GetBool() or SysTime() - (P.t0 or 0) > 4 then return end
    local Tx = GSA1.Text
    local font = Tx and Tx.FontFor and Tx.FontFor("photo_hint", P.HINT_SIZE) or "DermaLarge"
    surface.SetFont(font)
    local sw, sh = ScrW(), ScrH()
    if not P.hintLines or P.hintW ~= sw or P.hintFont ~= font then P.hintLines, P.hintW, P.hintFont = P.HintLines(sw * 0.9, hint_width), sw, font end
    local _, lh = surface.GetTextSize("A")
    for i, s in ipairs(P.hintLines) do
        local y = sh * 0.8 + (i - 1) * lh
        if not (Tx and Tx.Draw and Tx.Draw(s, "photo_hint", P.HINT_SIZE, color_white, sw / 2, y, 1, 1)) then
            draw.SimpleText(s, font, sw / 2, y, color_white, TEXT_ALIGN_CENTER or 1, TEXT_ALIGN_CENTER or 1)
        end
    end
end)

-- the keys refused [RP.1]: B.KeyRefused does not hold them all, and this feature adds the ones its camera and its page need ------------------------------------------
local OTHER_KEYS = { { "gsa1_board_key", "the board key" }, { "gsa1_debug_key", "the debug button's key" }, { "gsa1_charselect_key", "Character Select's key" }, { "gsa1_note_key", "the note key" },
                     { "gsa1_look_camera_key", "the head look's key" }, { "gsa1_lipsync_key", "the lip sync key" }, { "gsa1_face_event_key", "the face key" }, { "gsa1_cam_fish_toggle_key", "the fishing camera's key" } }
for i = 1, 10 do OTHER_KEYS[#OTHER_KEYS + 1] = { "gsa1_face_hotkey_" .. i, "a face's hotkey" } end
local KEEP_BINDS = { { "+menu", "the Q menu's key" }, { "+menu_context", "the C menu's key" }, { "toggleconsole", "the console's key" }, { "+speed", "the camera's fast key" }, { "+walk", "the camera's slow key" } }
function P.KeyRefused(code)
    code = tonumber(code) or 0
    if code <= 0 then return nil end
    for _, e in ipairs(OTHER_KEYS) do
        local c = GetConVar(e[1])
        if c and c:GetInt() == code then return e[2] end
    end
    if input and input.LookupBinding and input.GetKeyCode then
        for _, e in ipairs(KEEP_BINDS) do
            local name = input.LookupBinding(e[1])
            if name and input.GetKeyCode(name) == code then return e[2] end
        end
    end
    if B and B.KeyRefused then return B.KeyRefused(code, "gsa1_photo_key") end
    return nil
end
local function key_name(code)
    local W = GSA1.Wheel
    return W and W.KeyName and W.KeyName(code) or tostring(code)
end
cvars.AddChangeCallback("gsa1_photo_key", function(name, old, new)
    if P.keyBack ~= nil and tonumber(new) == P.keyBack then
        P.keyBack = nil
        return
    end
    local why = P.KeyRefused(new)
    if why then
        P.keyBack = tonumber(old)
        P.keyNote = string.format("%s is %s: the photo mode key stays %s", key_name(tonumber(new)), why, key_name(tonumber(old)))
        log("%s", P.keyNote)
        if GSA1.Chat then GSA1.Chat("%s", P.keyNote) end
        RunConsoleCommand("gsa1_photo_key", tostring(old))
    elseif tonumber(new) ~= tonumber(old) then
        P.keyNote = nil
    end
end, "gsa1_photo")
cvars.AddChangeCallback("gsa1_photo_pad", function(name, old, new)
    if P.padBack ~= nil and tonumber(new) == P.padBack then
        P.padBack = nil
        return
    end
    local bits = tonumber(new) or 0
    local why = nil
    if bits > 0 then
        why = B and B.PadRefused and B.PadRefused(bits) or nil
        for _, n in ipairs({ "gsa1_debug_pad", "gsa1_board_pad" }) do
            local c = GetConVar(n)
            if c and c:GetInt() == bits then why = why or ("the button of " .. n) end
        end
    end
    if why then
        P.padBack = tonumber(old)
        P.keyNote = string.format("that button is %s: the photo mode button stays", why)
        log("%s", P.keyNote)
        RunConsoleCommand("gsa1_photo_pad", tostring(old))
    end
end, "gsa1_photo")
-- cl_playable.lua has no refusal of its own: the debug key set to the photo key goes back
cvars.AddChangeCallback("gsa1_debug_key", function(name, old, new)
    if tonumber(new) == cv.key:GetInt() and tonumber(new) ~= 0 then
        P.keyNote = string.format("%s is the photo mode key: the debug button's key stays %s", key_name(tonumber(new)), key_name(tonumber(old)))
        log("%s", P.keyNote)
        RunConsoleCommand("gsa1_debug_key", tostring(old))
    end
end, "gsa1_photo")

-- the page -------------------------------------------------------------------------------------------------------------------------------------------------------------------
function P.StatusLine()
    if P.broken then return "Photo mode stopped after an error: see the session log. It is back on the next map." end
    if P.state == "off" then return "Not frozen." end
    local now = SysTime()
    local t = now - (P.t0 or now)
    local n = Fo and #Fo.list or 0
    local who = GSA1.Char and (n > 0 and string.format("you and %d follower%s", n, n == 1 and "" or "s") or "you") or string.format("%d follower%s", n, n == 1 and "" or "s")
    local line = string.format("Frozen for %d s: %s. %.0f fps (%.0f before).", t, who, (P.frames or 0) / math.max(t, 1e-3), P.fpsBefore or 0)
    if not GSA1.Char and not game.SinglePlayer() then line = line .. " You can still be hurt: in multiplayer only a character is untouchable." end
    if cv.world:GetBool() then
        if not game.SinglePlayer() then
            line = line .. " The world goes on: single player only."
        elseif P.worldMask and P.worldMask ~= P.WORLD_ALL then
            local no = {}
            for _, e in ipairs(P.WORLD) do
                if band(P.worldMask, e.bit) == 0 then no[#no + 1] = e.what end
            end
            line = line .. " The world is frozen, except " .. table.concat(no, ", ") .. ": their setting did not take."
        else
            line = line .. " The world is frozen too."
        end
    end
    return line
end

local function live_label(panel, fn)
    local lbl = panel:Help("...")
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + 0.5
        local text = fn()
        if text ~= self.gsa1Text then
            self.gsa1Text = text
            self:SetText(text)
            if self.InvalidateLayout then self:InvalidateLayout(true) end
        end
    end
    return lbl
end

function P.Page(panel)
    panel:Help("WASD, Space and Ctrl fly the camera. The mouse wheel zooms, right mouse held tilts and zooms, R resets. While frozen nothing can hurt, move or wake you (in multiplayer only as a character: with followers alone you stay an ordinary player). Without the box below the world around you keeps going.")
    live_label(panel, P.StatusLine)
    local btn = panel:Button("Freeze now", "gsa1_photo")
    if btn and btn.SetText then
        local baseThink = btn.Think
        btn.Think = function(self)
            if baseThink then baseThink(self) end
            local text = P.state == "off" and "Freeze now" or "Leave photo mode"
            if text ~= self.gsa1Text then
                self.gsa1Text = text
                self:SetText(text)
            end
        end
    end
    panel:ControlHelp("The way out if you lose the key.")
    panel:Help("Photo mode key")
    local b = vgui.Create("DBinder", panel)
    if b.SetConVar then b:SetConVar("gsa1_photo_key") end
    if b.SetTall then b:SetTall(28) end
    panel:AddItem(b)
    panel:Button("No key (bind gsa1_photo yourself)", "gsa1_photo_key", "0")
    panel:ControlHelp("Freezes you and your followers mid-pose. Press it again, or Escape, to go on from the same moment. Keys the character, the wheel or the board use are refused.")
    live_label(panel, function() return P.keyNote or "" end)
    local W = GSA1.Wheel
    local choices = W and W.PAD_BUTTONS or { { 0, "None" } }
    local combo = panel:ComboBox("Controller button")
    if combo and combo.AddChoice then
        for _, c in ipairs(choices) do combo:AddChoice(c[2], tostring(c[1])) end
        combo.OnSelect = function(_, _, _, data) RunConsoleCommand("gsa1_photo_pad", tostring(data)) end
        local baseThink = combo.Think
        combo.Think = function(self)
            if baseThink then baseThink(self) end
            local v = cv.pad:GetInt()
            if v == self.gsa1Value then return end
            self.gsa1Value = v
            for _, c in ipairs(choices) do
                if tonumber(c[1]) == v then self:SetText(c[2]) break end
            end
        end
    end
    panel:ControlHelp("Left stick flies, right stick looks, A up, B down.")
    panel:CheckBox("Freeze the world too (single player)", "gsa1_photo_world")
    panel:ControlHelp("Props, NPCs and NextBots stop as well, and go on when you do. Doors, lifts, animated props, particles and other addons' own timers do not stop. In multiplayer it does nothing: a server is for other people too.")
    panel:CheckBox("Hide the HUD while frozen", "gsa1_photo_hud")
    panel:ControlHelp("All of it: rings, time, the game's own and other addons'.")
    panel:CheckBox("Hide shadows while frozen", "gsa1_photo_shadows")
    panel:ControlHelp("The sun shadows and the game's round shadow.")
    panel:CheckBox("The jukebox keeps playing while frozen", "gsa1_photo_jukebox")
    panel:ControlHelp("Your music and Super Sonic's. Sound effects, voices and the game's own music always hold.")
    panel:NumSlider("Camera speed", "gsa1_photo_speed", 20, 2000, 0)
    panel:ControlHelp("Units a second. Shift: 4 times. Alt: a quarter.")
    panel:CheckBox("Show the reminder", "gsa1_photo_hint")
    panel:ControlHelp("Four seconds of what the keys do when it starts.")
end
if GSA1.AddMenuPage then GSA1.AddMenuPage(295, "photo", "Photo mode", P.Page) end
