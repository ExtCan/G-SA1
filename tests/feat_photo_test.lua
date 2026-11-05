-- feat_photo_test.lua - 0.9.9d: basic photo mode (sadc docs/research/photo099d.md with its review, and the owner's later answers: "12. Freezing the world should be optional"; "13. No, while you're in Photomode you are completely
-- invincible and untouchable"). feat/sh_photo.lua, cl_photo.lua, sv_photo.lua and their seams, in Garry's Mod's own LuaJIT: the client through the autorun against tests/lua_mock.lua, the module a spy on every gsa1.* call, the server's
-- file in its own environment with messages delivered at once. What the game alone can show is not here (photo099d.md section 14 and the owner's checklist).
--   lua_host tests/feat_photo_test.lua <tests dir> <addon/lua dir>
-- FAILS on the frozen 0.9.9c (<addon/lua dir> = build/release_0.9.9c/addon/lua): GSA1.Photo does not exist; only P1 runs, and it pins what 0.9.9c's frames call.
-- The numbers P1 .. P26 are photo099d.md section 11's; W: the world's freeze (answer 12); U: untouchable (answer 13); V: what 0.9.9d's verifier found.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_photo_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end
IN_SPEED, IN_FORWARD = IN_SPEED or 131072, IN_FORWARD or 8
local band, bor = bit.band, bit.bor

-- ---- input, as feat_wheel_test.lua's ----------------------------------------------------------------------------------------------------
local KEYS, BINDS, typing, cursor, consoleOpen = {}, {}, false, false, false
input = {
    IsButtonDown = function(c) return KEYS[c] == true end, IsKeyDown = function(c) return KEYS[c] == true end, IsMouseDown = function(c) return KEYS[c] == true end,
    LookupBinding = function(b) return BINDS[b] end, GetKeyCode = function(n) return tonumber(n) end, GetKeyName = function(c) return "key" .. tostring(c) end,
    LookupKeyBinding = function(c) for b, k in pairs(BINDS) do if tonumber(k) == c then return b end end end,
}
vgui.CursorVisible = function() return cursor end
gui.IsConsoleVisible = function() return consoleOpen end
M.player.IsTyping = function() return typing end

-- ---- the module, with followers (feat_follower_test.lua's model, smaller) --------------------------------------------------------------------
local BATCHES = { { 0, 0, 0x20, 1, 0, 3, 0, 500, 1 }, { 0, 1, 0x20, 1, 0, 3, 0, 300, 1 }, { 0, 2, 0x860, 1, 0, 3, 0, 4, 1 } }     -- (the third: the game's round shadow)
local G = M.module({ features = { follower = 2, board = 1, emote = 3, preview = 2, render = 1, interact = 1 }, host_camera = true, batches = function() return BATCHES end })
local FM = { chars = {}, order = {}, ticks = 0 }
function G.TextureArchives() return { { name = "SONIC", count = 28 } } end
function G.FollowerKinds(out) out = out or {} out[0], out[2], out[3] = true, true, true return out end
local create0, destroy0 = G.Create, G.Destroy
function G.FollowerCreate(kind, pos, yaw, leader, opts)
    local id = create0(kind, pos, yaw, nil, nil)
    FM.chars[id] = { id = id, kind = kind, leader = leader, first = true, rx = pos.x, ry = pos.y, rz = pos.z, ryaw = yaw, level = 1 }
    FM.order[#FM.order + 1] = id
    return id
end
function G.Destroy(id)
    if FM.chars[id] then
        FM.chars[id] = nil
        for i, v in ipairs(FM.order) do if v == id then table.remove(FM.order, i) break end end
    end
    return destroy0(id)
end
function G.FollowerLeader() return true end
function G.FollowerFeed() return true end
function G.FollowerHostFlags() return true end
function G.FollowerHold() return true end
function G.FollowerRespawn() return true end
function G.FollowerDraw(id, level) if FM.chars[id] then FM.chars[id].level = level end return true end
function G.FollowerInfo(id, out) out = out or {} out.leader, out.mode, out.held = nil, 0, false return out end
function G.FollowerStand() return true end
function G.FollowerSpeed() return true end
function G.FollowerThreads(n) return n == 0 and 3 or n end
function G.FollowersStats(out) out = out or {} out.followers, out.workers, out.ms_tick, out.ms_render, out.ms_join, out.frames = #FM.order, 3, 1, 1, 0.1, 60 return out end
G.FOLLOWER = { MAX = 112, MAX_CHARACTERS = 128, OBJECTS_NONE = 0, OBJECTS_OWN = 1, DRAW_FULL = 1, DRAW_FAR = 2, DRAW_NONE = 3, RATE_MIN = 5, RATE_MAX = 30, RATE_DEFAULT = 15, POOL_MAX = 16, LIB_PARALLEL = false, SPEED_MAX = 8,
               MODE = { PLACE = 0, RESPAWN = 2, NORMAL = 4, TAKEOVER = 5, PARKED = 6 } }
function G.StateEx(id, out) out = out or {} out.rings, out.lives, out.mode, out.hurt_steps, out.held, out.held_object = 0, 4, 2, -1, 0, 0 return out end
function G.Damage(id) FM.damage = (FM.damage or 0) + 1 return true end
-- (0.9.9e: no G.Warp: the real module has none, MEASURED by 099d-verify2: a teleport re-creates the character. Tests count the re-creations: FM.recreates, by the hook below)
function G.AddRings() return true end
function G.PreviewTick(dt) FM.previewDt = dt return true end
function G.PreviewAdd() return nil, "no", "unsupported" end
function G.PreviewRender() return nil, "no", "not_found" end
function G.FollowersTick(dt, yaw, co, ct, out, interpolate)
    FM.ticks = FM.ticks + 1
    FM.last = { dt = dt, yaw = yaw, co = co and Vector(co), ct = ct and Vector(ct) }
    local n = 0
    for _, id in ipairs(FM.order) do
        local f, c = FM.chars[id], M.mchars[id]
        n = n + 1
        local r = out[n]
        if not r then r = {} out[n] = r end
        c.acc = c.acc + dt
        local np = 0
        while c.acc >= 1 / 30 do c.acc, np, c.pair, c.gen = c.acc - 1 / 30, np + 1, c.pair + 1, c.gen + 1 end
        r.id, r.pairs, r.ok, r.rendered, r.restructured = id, np, true, true, f.first
        f.first = false
        r.x, r.y, r.z, r.yaw, r.interpolated, r.alpha, r.tris = c.pos.x, c.pos.y, c.pos.z, f.ryaw, true, 0.5, 800
    end
    out.count, out.workers, out.ms, out.ms_join = n, 3, 1.5, 0.25
    return out
end

surface.SetFont = surface.SetFont or function() end
surface.GetTextSize = surface.GetTextSize or function(s) return 15 * #s, 32 end     -- (about what DermaLarge is, the verifier's estimate; UNVERIFIED by eye)
-- ---- the two realms: messages delivered at once ------------------------------------------------------------------------------------------------
local to_server, to_client, recv_s, recv_c = {}, {}, {}, {}
local strings, out_m = {}, nil
local net_real = net or {}
local function writer(v_is)
    return function(v) if out_m then out_m.vals[#out_m.vals + 1] = v_is and Vector(v) or v end end
end
local keep_receive = net_real.Receive
net = setmetatable({
    Start = function(name) out_m = { name = name, vals = {} } end,
    WriteBool = writer(), WriteUInt = writer(), WriteFloat = writer(), WriteString = writer(), WriteVector = writer(true), WriteNormal = writer(true), WriteAngle = writer(),
    SendToServer = function() if out_m then to_server[#to_server + 1] = out_m end out_m = nil end,
    Send = function() if out_m then to_client[#to_client + 1] = out_m end out_m = nil end,
    Broadcast = function() if out_m then to_client[#to_client + 1] = out_m end out_m = nil end,
    Receive = function(name, fn) recv_c[name] = fn end,
}, { __index = net_real })
local reading
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadFloat", "ReadString", "ReadVector", "ReadNormal", "ReadAngle" }) do
    net[r] = function()
        reading.i = reading.i + 1
        return reading.vals[reading.i]
    end
end
local PLY = M.player
local function pump()
    local q = to_server
    to_server = {}
    for _, m in ipairs(q) do
        local fn = recv_s[m.name]
        if fn then
            reading = { vals = m.vals, i = 0 }
            fn(0, PLY)
        end
    end
    local q2 = to_client
    to_client = {}
    for _, m in ipairs(q2) do
        local fn = recv_c[m.name]
        if fn then
            reading = { vals = m.vals, i = 0 }
            fn(0)
        end
    end
end
util.NetworkStringToID = function(n) return strings[n] and 1 or 0 end

-- ---- the client -----------------------------------------------------------------------------------------------------------------------------------
GSA1 = nil
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
check(ok_load and GSA1 ~= nil, "the addon loads (%s)", tostring(err_load))
if not (ok_load and GSA1) then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
GSA1.cv.prewarm:SetString("0")
strings[GSA1.NET_ACTIVE or "?"], strings[GSA1.NET_STATE or "?"] = true, true
local SPY, SPY_ON = {}, false
for k, v in pairs(gsa1) do
    if type(v) == "function" then
        gsa1[k] = function(...)
            if SPY_ON then SPY[k] = (SPY[k] or 0) + 1 end
            return v(...)
        end
    end
end
local function spy_reset() SPY = {} SPY_ON = true end
local function spy_off() SPY_ON = false end

local cmdv = { buttons = 0, side = 0, forward = 0, sets = 0, mx = 0, my = 0 }
local CMD = {}
CMD.__index = CMD
function CMD:GetSideMove() return cmdv.side end
function CMD:GetForwardMove() return cmdv.forward end
function CMD:KeyDown(k) return band(cmdv.buttons, k) ~= 0 end
function CMD:ClearMovement() cmdv.side, cmdv.forward = 0, 0 end
function CMD:ClearButtons() cmdv.buttons = 0 end
function CMD:GetButtons() return cmdv.buttons end
function CMD:SetButtons(b) cmdv.buttons = b end
function CMD:GetViewAngles() return Angle(M.pitch, M.yaw, 0) end
function CMD:SetViewAngles(a) M.pitch, M.yaw = a.p, a.y cmdv.sets = cmdv.sets + 1 end     -- (RP.13: the pin is fed back, unlike the mock's no-op)
function CMD:GetMouseX() return cmdv.mx end
function CMD:GetMouseY() return cmdv.my end
function CMD:SetMouseX(v) cmdv.mx = v end
function CMD:SetMouseY(v) cmdv.my = v end
local cmdo = setmetatable({}, CMD)
local held = { buttons = 0, side = 0, forward = 0 }     -- what the person holds, every frame
local function hook_frame(order, dt)
    dt = dt or 1 / 60
    M.dt = dt
    M.T = M.T + dt
    M.frameNo = M.frameNo + 1
    cmdv.buttons, cmdv.side, cmdv.forward = held.buttons, held.side, held.forward
    local function cm() M.run_hook("CreateMove", cmdo) end
    if order == "cmdfirst" then cm() end
    M.run_hook("Think")
    if order ~= "cmdfirst" then cm() end
    local view = M.run_hook("CalcView", PLY, PLY:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
    M.view_origin = view and view.origin or PLY:EyePos()
    M.lastView = view
    for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(1) end end
    for _, e in ipairs(M.entities) do if not e.removed and e.DrawTranslucent then e:DrawTranslucent(1) end end
    M.run_hook("PostRender")
    pump()
end
local function frames(n, dt, order) for _ = 1, n do hook_frame(order, dt) end end
GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil, "Sonic spawned")
if not C then return done() end
local Fo = GSA1.Followers
local function add_follower()
    local n0 = #Fo.list
    RunConsoleCommand("gsa1_follower_spawn", "tails")
    return #Fo.list > n0 and Fo.list[#Fo.list] or nil
end
local F1 = add_follower()
local F2 = add_follower()
check(F1 ~= nil and F2 ~= nil and F1 ~= F2, "two followers (%s)", tostring(#Fo.list))
frames(30)

-- P1. never pressed: exactly 0.9.9c's calls, pinned by a hash of every module call of every frame and every Tick's arguments ------------------------------------
do
    local h1, h2, h3 = 0, 0, 0
    local function mix(s)
        for i = 1, #s do
            local b = string.byte(s, i)
            h1 = (h1 * 31 + b) % 2147483647
            h2 = (h2 * 131 + b) % 2147483629
        end
        h3 = h3 + #s
    end
    local names = {}
    for k in pairs(gsa1) do names[#names + 1] = k end
    table.sort(names)
    held.forward, held.buttons = 5000, IN_JUMP
    for f = 1, 600 do
        if f == 200 then held.buttons = 0 end
        if f == 300 then held.side = -3000 end
        spy_reset()
        hook_frame()
        spy_off()
        for _, k in ipairs(names) do if SPY[k] then mix(k .. "=" .. SPY[k] .. ";") end end
        local t = M.ticks.last
        mix(string.format("%.6f %.6f %.6f %d %.6f;", t.sx, t.sy, t.yaw, t.buttons, t.dt))
        local fl = FM.last
        mix(string.format("%.6f %.6f;", fl.dt, fl.yaw))
    end
    held.forward, held.side, held.buttons = 0, 0, 0
    local hash = string.format("%d %d %d", h1, h2, h3)
    info("P1: 600 frames of calls and Tick's arguments: hash %s", hash)
    check(hash == "191699848 2130983722 119249", "P1 never pressed: every frame's module calls and Tick's arguments are 0.9.9c's (hash %s, from build/release_0.9.9c)", hash)
end
local P = GSA1.Photo
check(P ~= nil and GSA1.PhotoFrozen ~= nil and GSA1.PhotoThink ~= nil, "GSA1.Photo, GSA1.PhotoFrozen, GSA1.PhotoThink exist")
if not (P and GSA1.PhotoFrozen and GSA1.PhotoThink) then return done() end
local frozen = GSA1.PhotoFrozen
local function press(code)
    code = code or 21
    KEYS[code] = true
    hook_frame()
    KEYS[code] = nil
end
local function leave()
    if frozen() then
        RunConsoleCommand("gsa1_photo")
        frames(5)
    end
end

-- the server, in its own environment --------------------------------------------------------------------------------------------------------------------
local SV = {}
do
    local S = setmetatable({}, { __index = _G })
    S.SERVER, S.CLIENT = true, false
    local hooks = {}
    S.hook = { Add = function(ev, name, fn) hooks[ev] = hooks[ev] or {} hooks[ev][name] = fn end, Remove = function(ev, name) if hooks[ev] then hooks[ev][name] = nil end end, Run = function() end }
    SV.hooks = hooks
    function SV.run(ev, ...)
        for _, fn in pairs(hooks[ev] or {}) do
            local r = fn(...)
            if r ~= nil then return r end
        end
    end
    -- the server's ConVars, Source's: RunConsoleCommand takes effect at once here; SV.refuse[name]: it does not take (a cheat flag: UNVERIFIED in the game)
    SV.cvars = { phys_timescale = "1.00", ai_disabled = "0", nb_stop = "0" }
    SV.refuse = {}
    SV.cmds = {}
    S.GetConVar = function(name)
        if SV.cvars[name] == nil then return nil end
        return { GetString = function() return SV.cvars[name] end, GetFloat = function() return tonumber(SV.cvars[name]) or 0 end }
    end
    S.RunConsoleCommand = function(name, v)
        SV.cmds[#SV.cmds + 1] = name .. " " .. tostring(v)
        if not SV.refuse[name] then SV.cvars[name] = tostring(v) end
    end
    SV.single = true
    S.game = { SinglePlayer = function() return SV.single end, GetMap = game.GetMap }
    S.util = setmetatable({ AddNetworkString = function(n) strings[n] = true end, IsInWorld = function(p) return SV.inworld ~= false end }, { __index = util })
    S.net = setmetatable({ Receive = function(name, fn) recv_s[name] = fn end, Start = net.Start, Send = net.Send, WriteUInt = net.WriteUInt, WriteBool = net.WriteBool, ReadUInt = net.ReadUInt, ReadBool = net.ReadBool, ReadVector = net.ReadVector }, { __index = net })
    SV.files = {}
    S.file = { Exists = function(p) return SV.files[p] ~= nil end, Read = function(p) return SV.files[p] end, Write = function(p, s) SV.files[p] = s end, Delete = function(p) SV.files[p] = nil end }
    S.CurTime = function() return M.T end
    S.player = { GetAll = function() return { PLY } end }
    -- the player's server half
    local PL = {}
    function PL.Kill(self) SV.killed = (SV.killed or 0) + 1 end
    function PL.KillSilent(self) SV.killed = (SV.killed or 0) + 1 end
    S.FindMetaTable = function(n) if n == "Player" then return PL end end
    PLY.Kill, PLY.KillSilent = function(self) return PL.Kill(self) end, function(self) return PL.KillSilent(self) end
    PLY.god, PLY.notarget = false, false
    function PLY:GodEnable() self.god = true end
    function PLY:GodDisable() self.god = false end
    function PLY:HasGodMode() return self.god end
    function PLY:SetNoTarget(b) self.notarget = b end
    function PLY:IsFlagSet(f) if f == (FL_NOTARGET or 65536) then return self.notarget end return false end
    PLY.IsAdmin = PLY.IsAdmin or function() return false end
    S.AddOriginToPVS = function(p) SV.pvs = (SV.pvs or 0) + 1 SV.pvsAt = p end
    S.FL_NOTARGET = FL_NOTARGET or 65536
    S.GSA1 = setmetatable({}, { __index = GSA1 })
    S.GSA1.Photo = setmetatable({}, { __index = GSA1.Photo })
    S.GSA1.Log = nil
    SV.env = S
    local src = host_read(root .. "/gsa1/feat/sv_photo.lua")
    if src then
        local fn, err = host_load(src, "sv_photo.lua")
        check(fn ~= nil, "feat/sv_photo.lua compiles (%s)", tostring(err))
        if fn then
            setfenv(fn, S)
            local ok, e2 = pcall(fn)
            check(ok, "feat/sv_photo.lua loads (%s)", tostring(e2))
        end
    else
        check(false, "feat/sv_photo.lua exists")
    end
end
local PS = SV.env.GSA1.Photo
strings[P.NET or "gsa1_photo"] = true

-- P2. the key -----------------------------------------------------------------------------------------------------------------------------------------------
do
    local d = GSA1.CONVARS.gsa1_photo_key
    check(d ~= nil and d.default == "21", "P2 the key: gsa1_photo_key, K (21) by default [RP.1] (%s)", d and d.default or "none")
    press()
    check(frozen() and P.state == "on", "P2 its press freezes (%s)", tostring(P.state))
    KEYS[21] = true
    frames(10)
    check(P.state == "on", "P2 holding it does not toggle (%s)", tostring(P.state))
    KEYS[21] = nil
    hook_frame()
    press()
    check(P.state == "thaw", "P2 a second press: the thaw step (%s)", tostring(P.state))
    frames(2)
    check(not frozen(), "P2 then off (%s)", tostring(P.state))
    for _, what in ipairs({ "cursor", "typing", "console", "ui", "focus" }) do
        if what == "cursor" then cursor = true elseif what == "typing" then typing = true elseif what == "console" then consoleOpen = true elseif what == "ui" then M.ui = true else M.focus = false end
        press()
        local f = frozen()
        cursor, typing, consoleOpen, M.ui, M.focus = false, false, false, false, true
        hook_frame()
        check(not f, "P2 not while %s", what)
        if f then leave() end
    end
    RunConsoleCommand("gsa1_photo_key", "0")
    KEYS[21] = true
    frames(2)
    KEYS[21] = nil
    check(not frozen(), "P2 key 0: no key")
    RunConsoleCommand("gsa1_photo")
    frames(1)
    check(P.state == "on", "P2 the command gsa1_photo works without a key (%s)", tostring(P.state))
    RunConsoleCommand("gsa1_photo")
    frames(4)
    check(not frozen(), "P2 and leaves")
    RunConsoleCommand("gsa1_photo_key", "21")
    hook_frame()
    -- the controller's button, none by default; Start and A are refused, the old one stays
    check(GetConVar("gsa1_photo_pad"):GetInt() == 0, "P2 no controller button by default")
    RunConsoleCommand("gsa1_photo_pad", "16")
    check(GetConVar("gsa1_photo_pad"):GetInt() == 0, "P2 Start refused as the button (%d)", GetConVar("gsa1_photo_pad"):GetInt())
    RunConsoleCommand("gsa1_photo_pad", "8")
    local pu = GSA1.PadUpdate
    local raw = 0
    GSA1.PadUpdate = function() GSA1.pad = { connected = true, active = false, sx = 0, sy = 0, buttons = 0, raw = raw, yaw = 0, pitch = 0, reset = false, rx = 0, ry = 0, cx = 0, cy = 0 } end
    frames(1)
    raw = 8
    frames(3)
    check(P.state == "on", "P2 the chosen button freezes, once (%s)", tostring(P.state))
    raw = 0
    frames(1)
    raw = 8
    frames(2)
    check(P.state ~= "on", "P2 and thaws (%s)", tostring(P.state))
    raw = 0
    frames(3)
    GSA1.PadUpdate = pu
    GSA1.pad = nil
    RunConsoleCommand("gsa1_photo_pad", "0")
    hook_frame()
end

-- P3, P4. nothing of the game runs; the allowlist of 3.4 -----------------------------------------------------------------------------------------------------------
do
    local ALLOWED = {}
    for name in string.gmatch("PrepareView EmitBatch DrawBatchNative ObjHeld StateEx HudCounters HudScreen Camera Contacts ObjEvents PollLog IsReady SetGeneration SetLive AudioUpdate AudioMusicState AudioDuck AudioStatus JukeboxUpdate JukeboxState JukeboxVolume PadPoll PadStatus PadSettings ObjAdd ObjMove ObjRemove ObjRelease SetAdd SetUpdate SetRemove SetState SetConfig PreviewTick FollowerInfo FollowersStats LookState FaceState EmoteState SuperState SuperInfo GetLives Status MoverStatus NativeMeshStatus InitPoll WorldInfo GetState CharacterInfo TextureArchives TexturePixels TextureInfo CamState ShapeKnown", "%S+") do ALLOWED[name] = true end
    -- (GetState: a read; photo099d.md's list has it as the far pictures' read-outs. Tick, FollowersTick, Render, Batches, PollEvents, and everything else: not allowed)
    local before = { FM.ticks, M.mchars[C.id].pair }
    press()
    local KEYS_ALL = { 11, 12, 16, 17, 18, 15, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36 }
    spy_reset()
    local pre, post, fpost = M.hook_runs.GSA1PreTick or 0, M.hook_runs.GSA1PostTick or 0, M.hook_runs.GSA1FollowerPostTick or 0
    local tick0 = FM.ticks
    held.buttons = bor(IN_JUMP, IN_DUCK, IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_USE or 32)
    for i = 1, 300 do
        for _, k in ipairs(KEYS_ALL) do KEYS[k] = i % 40 < 20 and k ~= 21 or nil end
        hook_frame()
    end
    for _, k in ipairs(KEYS_ALL) do KEYS[k] = nil end
    held.buttons = 0
    spy_off()
    local banned = {}
    for _, n in ipairs({ "Tick", "FollowersTick", "Render", "Batches", "PollEvents", "MoverUpdate", "MoverCommit", "FollowerFeed", "FollowerHostFlags", "FollowerDraw", "Damage", "Warp", "Board", "BoardFree" }) do
        if SPY[n] then banned[#banned + 1] = n .. "=" .. SPY[n] end
    end
    check(#banned == 0 and FM.ticks == tick0, "P3 300 frozen frames: no Tick, FollowersTick, Render, Batches, PollEvents, MoverUpdate, FollowerFeed, FollowerHostFlags, FollowerDraw (%s)", table.concat(banned, " "))
    check((M.hook_runs.GSA1PreTick or 0) == pre and (M.hook_runs.GSA1PostTick or 0) == post and (M.hook_runs.GSA1FollowerPostTick or 0) == fpost, "P3 GSA1PreTick, GSA1PostTick, GSA1FollowerPostTick not run")
    local other = {}
    for k, n in pairs(SPY) do if not ALLOWED[k] then other[#other + 1] = k .. "=" .. n end end
    table.sort(other)
    check(#other == 0, "P4 with every key of the addon pressed: only the allowlist reaches the module (others: %s)", table.concat(other, " "))
    local seen = {}
    for k in pairs(SPY) do seen[#seen + 1] = k end
    table.sort(seen)
    info("P4 the calls of the frozen frames: %s", table.concat(seen, " "))
    leave()
end

-- P5, P6. the thaw ------------------------------------------------------------------------------------------------------------------------------------------------
do
    held.buttons = 0
    frames(4)
    local yaw0, co0 = M.ticks.last.yaw, M.ticks.last.co and Vector(M.ticks.last.co)
    local ct0 = M.ticks.last.ct and Vector(M.ticks.last.ct)
    press()
    M.T = M.T + 5       -- a long freeze
    frames(120)
    press()
    check(P.state == "thaw", "P6 the frame after the press: the thaw step (%s)", tostring(P.state))
    local t0 = M.ticks.last
    local ticksAt = t0
    local fticks = FM.ticks
    hook_frame()
    -- that frame ticked: one frame's time, not the freeze, not 0.25
    local t = M.ticks.last
    check(t ~= ticksAt and math.abs(t.dt - 1 / 60) < 1e-6, "P5 the first tick after: one frame's time (%.4f)", t.dt)
    check(t.yaw == yaw0, "P5 the yaw exactly as before (%s against %s)", tostring(t.yaw), tostring(yaw0))
    check(co0 and t.co and t.co.x == co0.x and t.co.y == co0.y and t.co.z == co0.z, "P5 the host camera exactly as before")
    check(FM.ticks == fticks + 1 and math.abs(FM.last.dt - 1 / 60) < 1e-6, "P5 the followers' first tick: one frame's time (%.4f)", FM.last.dt)
    -- RP.3: pressed during the freeze and still held: out of the tick's buttons until released
    press()
    frames(3)
    held.buttons = bor(IN_JUMP, IN_ATTACK2, IN_RELOAD)
    frames(3)
    press()
    frames(3)
    check(not frozen() and band(M.ticks.last.buttons, 1 + 2 + 4) == 0, "P5 [RP.3] Space, right mouse, R pressed while frozen and still held: not in the tick's buttons (%d)", M.ticks.last.buttons)
    held.buttons = 0
    frames(2)
    held.buttons = IN_JUMP
    frames(2)
    check(band(M.ticks.last.buttons, 1) ~= 0, "P5 [RP.3] released and pressed again: a jump (%d)", M.ticks.last.buttons)
    -- held from before the freeze until after it stays on: no new press in the world
    press()
    frames(3)
    press()
    frames(3)
    check(band(M.ticks.last.buttons, 1) ~= 0, "P5 [RP.3] held from before the freeze until after it: stays on (%d)", M.ticks.last.buttons)
    held.buttons = 0
    frames(2)
    -- RP.3 for the controller's buttons
    local pad = { connected = true, active = true, sx = 0, sy = 0, buttons = 0, raw = 0, yaw = 0, pitch = 0, reset = false, rx = 0, ry = 0, cx = 0, cy = 0 }
    local pu = GSA1.PadUpdate
    GSA1.PadUpdate = function() GSA1.pad = pad end
    frames(2)
    press()
    frames(2)
    pad.buttons = 1
    frames(2)
    press()
    frames(3)
    check(band(M.ticks.last.buttons, 1) == 0, "P5 [RP.3] the pad's button pressed while frozen and held: out (%d)", M.ticks.last.buttons)
    pad.buttons = 0
    frames(2)
    pad.buttons = 1
    frames(2)
    check(band(M.ticks.last.buttons, 1) ~= 0, "P5 [RP.3] the pad's button again: a press (%d)", M.ticks.last.buttons)
    pad.buttons = 0
    GSA1.PadUpdate = pu
    GSA1.pad = nil
    frames(2)
    -- RP.5: a way out arriving before Think, and after CalcView, in both frame orders
    for _, order in ipairs({ "thinkfirst", "cmdfirst" }) do
        for _, way in ipairs({ "command", "escape" }) do
            frames(3, nil, order)
            press()
            frames(3, nil, order)
            local photoCam = Vector(100000, 0, 0)
            P.cam.pos:Set(photoCam)
            frames(1, nil, order)
            if way == "command" then RunConsoleCommand("gsa1_photo") else M.run_hook("OnPauseMenuShow") end
            check(P.state == "on", "P6 [RP.5] %s, %s: only a request (%s)", way, order, tostring(P.state))
            local before = M.ticks.last
            hook_frame(order)
            check(P.state == "thaw" or (order == "cmdfirst" and P.state == "thaw"), "P6 [RP.5] %s, %s: the next frame is the thaw (%s)", way, order, tostring(P.state))
            check(M.ticks.last == before, "P6 [RP.5] %s, %s: no tick in it", way, order)
            hook_frame(order)
            local co = M.ticks.last.co
            check(M.ticks.last ~= before and not (co and co.x > 50000), "P6 [RP.5] %s, %s: the first tick gets no photo camera (%s)", way, order, co and tostring(co.x) or "nil")
            frames(20, nil, order)     -- (the Start guard's time)
        end
    end
    -- a view entity at the thaw: off after 3 frames
    press()
    frames(2)
    PLY.view_entity = { removed = false }
    frames(2)
    press()
    check(P.state == "thaw", "P6 with a view entity on: thaw (%s)", tostring(P.state))
    frames(2)
    local st = P.state
    frames(2)
    check(st == "thaw" and not frozen(), "P6 with a view entity on: off after 3 frames (%s, then %s)", tostring(st), tostring(P.state))
    PLY.view_entity = nil
    frames(2)
    -- RP.6: ending at once: no photo camera in the next ticks
    press()
    frames(2)
    P.cam.pos:SetUnpacked(100000, 0, 0)
    frames(1)
    GSA1.Recreate("a test")
    check(not frozen(), "P6 a re-creation ends it at once (%s)", tostring(P.state))
    check((GSA1.view.frame or 0) < 0, "P6 [RP.6] and GSA1.view is no view any more (frame %s)", tostring(GSA1.view.frame))
    C = GSA1.Char
    local ft0 = FM.last
    M.run_hook("Think")
    local c2, c3 = M.ticks.last.co, FM.last.co
    check(not (c2 and c2.x > 50000) and not (c3 and c3.x > 50000), "P6 [RP.6] the next tick and the followers' get no photo camera")
    frames(3)
end

-- P7. the clocks --------------------------------------------------------------------------------------------------------------------------------------------------
do
    frames(3)
    press()
    frames(2)
    local I, B = GSA1.Interact, GSA1.Board
    C = GSA1.Char
    local T0 = SysTime()
    C.respawnAt, C.fallbackAt, C.killAsked = T0 + 1, T0 + 2, T0 - 1
    I.pendingKill = { untilT = T0 + 3 }
    I.actionUntil = T0 + 4
    F1.guardUntil = T0 + 5
    Fo.emote = Fo.emote or {}
    local em0, em1 = Fo.emote.waitUntil, Fo.emote.nextTry
    Fo.emote.waitUntil, Fo.emote.nextTry = T0 + 6, T0 + 7
    local boardC, boardF = C.board, F1.board
    C.board = { walk = { deadline = T0 + 8 }, fwalk = { deadline = T0 + 9 }, leaving = { at = T0 + 10 }, entering = { at = T0 + 11 }, pendingFree = { at = T0 + 12 } }
    F1.board = { walk = { deadline = T0 + 13 }, pendingFree = { at = T0 + 14 } }
    local lq = B.leftQueue
    local entry = { at = T0 + 15, C = F1 }
    B.leftQueue = { entry }
    local boards = C.board
    local boardsF = F1.board
    M.T = M.T + 60
    local S0 = SysTime()
    press()
    local s = SysTime() - T0
    local function near(v, w) return v ~= nil and math.abs(v - w - s) < 0.1 end
    check(near(C.respawnAt, T0 + 1) and near(C.fallbackAt, T0 + 2), "P7 a death's respawn at the same remaining time")
    check(near(C.killAsked, T0 - 1) and near(I.pendingKill.untilT, T0 + 3) and near(I.actionUntil, T0 + 4), "P7 the kill's clocks and the interact key's")
    check(near(F1.guardUntil, T0 + 5) and near(Fo.emote.waitUntil, T0 + 6) and near(Fo.emote.nextTry, T0 + 7), "P7 a follower's guard, the emote's wait")
    check(near(boards.walk.deadline, T0 + 8) and near(boards.fwalk.deadline, T0 + 9) and near(boards.leaving.at, T0 + 10) and near(boards.entering.at, T0 + 11) and near(boards.pendingFree.at, T0 + 12), "P7 your board's walk and its leaving")
    check(near(boardsF.walk.deadline, T0 + 13) and near(boardsF.pendingFree.at, T0 + 14), "P7 a follower's board [RP.8]")
    check(near(entry.at, T0 + 15), "P7 B.leftQueue [RP.8]")
    C.respawnAt, C.fallbackAt, C.killAsked = nil, nil, nil
    I.pendingKill, I.actionUntil = nil, nil
    F1.guardUntil, Fo.emote.waitUntil, Fo.emote.nextTry = nil, em0, em1
    C.board, F1.board = boardC, boardF
    B.leftQueue = lq
    frames(3)
end

-- P8. sound ------------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local paused, jb
    local au, ju = gsa1.AudioUpdate, gsa1.JukeboxUpdate
    gsa1.AudioUpdate = function(o, f, u, v, p, dt) paused = p return au(o, f, u, v, p, dt) end
    gsa1.JukeboxUpdate = gsa1.JukeboxUpdate and function(o, f, u, v, m, p) jb = p return ju and ju(o, f, u, v, m, p) or 0 end or nil
    frames(1)
    check(paused == false, "P8 not frozen: the mixer runs")
    press()
    frames(1)
    check(paused == true, "P8 frozen: the mixer holds")
    press()
    hook_frame()
    frames(2)
    check(paused == false, "P8 after: it runs again")
    gsa1.AudioUpdate, gsa1.JukeboxUpdate = au, ju
    -- the jukebox and Super's music, by the box: the hold both files ask for
    check(GSA1.PhotoHoldsMusic() == false, "P8 not frozen: the music is not held")
    press()
    frames(1)
    check(GSA1.PhotoHoldsMusic() == false, "P8 frozen, the box on (the default): the jukebox keeps playing")
    RunConsoleCommand("gsa1_photo_jukebox", "0")
    check(GSA1.PhotoHoldsMusic() == true, "P8 the box off: held")
    RunConsoleCommand("gsa1_photo_jukebox", "1")
    leave()
    for _, f in ipairs({ "gsa1/feat/cl_jukebox.lua", "gsa1/feat/cl_super.lua" }) do
        local src = host_read(root .. "/" .. f) or ""
        local i = string.find(src, "PhotoHoldsMusic", 1, true)
        local bg = string.find(src, "background:GetBool()", 1, true)
        check(i ~= nil and bg ~= nil and i > bg, "P8 [RP.16] %s asks after the gsa1_jukebox_background test, so an unticked box holds it either way", f)
    end
end

-- P9-P12. the camera ----------------------------------------------------------------------------------------------------------------------------------------------------
do
    frames(3)
    local v0 = M.lastView
    local o0, a0, f0 = Vector(v0.origin), Angle(v0.angles), v0.fov
    press()
    hook_frame()
    local v1 = M.lastView
    check(v1.origin.x == o0.x and v1.origin.y == o0.y and v1.origin.z == o0.z and v1.angles.y == a0.y and v1.angles.p == a0.p and v1.fov == f0, "P9 the first frozen frame's view is the last frame's")
    -- speed: independent of the frame rate, the box's speed, Shift, Alt
    local function flown(setup, fps, secs)
        P.cam.pos:SetUnpacked(0, 0, 0)
        P.cam.ang.p, P.cam.ang.y, P.cam.ang.r = 0, 0, 0
        P.cam.vx, P.cam.vy, P.cam.vz = 0, 0, 0
        setup()
        frames(math.floor(fps * secs), 1 / fps)
        local d = P.cam.pos.x * P.cam.pos.x + P.cam.pos.y * P.cam.pos.y + P.cam.pos.z * P.cam.pos.z
        held.buttons, held.forward, held.side = 0, 0, 0
        frames(60)
        return math.sqrt(d), P.cam.pos
    end
    local d60 = flown(function() held.forward = 10000 end, 60, 2)
    local d30 = flown(function() held.forward = 10000 end, 30, 2)
    check(math.abs(d60 - 400) < 30 and math.abs(d60 - d30) < 8, "P9 W flies at gsa1_photo_speed, whatever the frame rate (%.1f at 60 fps, %.1f at 30, 2 s at 200)", d60, d30)
    local dfast = flown(function() held.forward, held.buttons = 10000, IN_SPEED end, 60, 1)
    local dslow = flown(function() held.forward, held.buttons = 10000, IN_WALK end, 60, 1)
    check(math.abs(dfast / dslow - 16) < 1.5, "P9 Shift 4 times, Alt a quarter (%.1f, %.1f)", dfast, dslow)
    local _, pu = flown(function() held.buttons = IN_JUMP end, 60, 1)
    local zu = pu.z
    local _, pd = flown(function() held.buttons = IN_DUCK end, 60, 1)
    check(zu > 100 and pd.z < -100, "P9 Space up, Ctrl down (%.1f, %.1f)", zu, pd.z)
    P.cam.pos:SetUnpacked(10, 20, 30)
    P.cam.vx, P.cam.vy, P.cam.vz = 0, 0, 0
    frames(30)
    check(P.cam.pos.x == 10 and P.cam.pos.y == 20 and P.cam.pos.z == 30, "P9 no motion with no key")
    -- a brush stops it
    local th = util.TraceHull
    util.TraceHull = function(t)
        local out = t.output or {}
        out.Hit, out.StartSolid = false, false
        out.HitPos = Vector(t.endpos)
        if t.endpos.x > 50 then
            out.Hit = true
            out.HitPos = Vector(50, t.endpos.y, t.endpos.z)
        end
        return out
    end
    P.cam.pos:SetUnpacked(0, 0, 0)
    P.cam.ang.y = 0
    held.forward = 10000
    frames(120)
    held.forward = 0
    check(P.cam.pos.x <= 50.001 and P.cam.pos.x > 40, "P9 stops at a brush (%.1f)", P.cam.pos.x)
    -- a start in solid gets out
    util.TraceHull = function(t)
        local out = t.output or {}
        out.Hit, out.StartSolid, out.AllSolid = true, true, true
        out.Fraction = 0
        out.HitPos = Vector(t.start)
        return out
    end
    P.cam.pos:SetUnpacked(0, 0, 0)
    held.forward = 10000
    frames(30)
    held.forward = 0
    check(P.cam.pos.x > 20, "P9 a start in solid moves freely until it is out (%.1f)", P.cam.pos.x)
    util.TraceHull = th
    frames(60)
    -- P10 the real angles
    local p0, y0 = M.pitch, M.yaw
    cmdv.sets = 0
    local ret
    for _ = 1, 600 do
        M.yaw = M.yaw + 0.25        -- +left and the like, past the mouse hook
        ret = M.run_hook("InputMouseApply", cmdo, 7, 3, Angle(M.pitch, M.yaw, 0))
        hook_frame()
    end
    check(ret == true, "P10 InputMouseApply returns true")
    check(cmdv.sets >= 600 and M.yaw == y0 and M.pitch == p0, "P10 the real view angles pinned to the last bit over 600 frames (%s, %s; %d pins)", tostring(M.yaw), tostring(M.pitch), cmdv.sets)
    local ang = P.cam.ang
    check(ang.p <= 89 and ang.p >= -89, "P10 the camera's pitch held to 89 (%.1f)", ang.p)
    -- the pad's pending turn is used up: no swing at thaw
    local pad = { connected = true, active = true, sx = 0, sy = 0, buttons = 0, raw = 0, yaw = 5, pitch = 0, reset = false, rx = 0, ry = 0, cx = 0, cy = 0 }
    local realPoll = gsa1.PadPoll
    gsa1.PadPoll = function(dt, paused, out) for k, v in pairs(pad) do out[k] = v end return out end
    GSA1.pad = nil
    local camYaw = P.cam.ang.y
    frames(30)
    check(P.cam.ang.y ~= camYaw and M.yaw == y0, "P10 the right stick turns the camera and not the eye angles (%.1f, %s)", P.cam.ang.y, tostring(M.yaw))
    gsa1.PadPoll = realPoll
    frames(2)
    press()
    frames(3)
    check(M.yaw == y0 and M.pitch == p0, "P10 no swing at thaw: the pending turn was used up (%s)", tostring(M.yaw))
    frames(2)
    -- P11 wheel, right mouse, R
    press()
    frames(2)
    local dist0 = GSA1.cv.cam_dist:GetFloat()
    local fov0 = P.cam.fov
    local r1 = M.run_hook("PlayerBindPress", PLY, "invprev", true, 112)
    check(r1 == true and P.cam.fov < fov0 and GSA1.cv.cam_dist:GetFloat() == dist0, "P11 the wheel zooms (%.1f from %.1f), gsa1_cam_distance not touched", P.cam.fov, fov0)
    local fov1 = P.cam.fov
    M.run_hook("PlayerBindPress", PLY, "invnext", true, 113)
    check(P.cam.fov > fov1, "P11 the other way")
    held.buttons = IN_ATTACK2
    hook_frame()
    local fov2, roll2 = P.cam.fov, P.cam.ang.r
    M.run_hook("InputMouseApply", cmdo, 100, 100, Angle())
    check(P.cam.fov ~= fov2 and P.cam.ang.r ~= roll2, "P11 right mouse held: zooms and tilts (%.2f, %.2f)", P.cam.fov, P.cam.ang.r)
    held.buttons = IN_RELOAD
    hook_frame()
    held.buttons = 0
    hook_frame()
    check(P.cam.fov == P.cam.fov0 and P.cam.ang.r == 0, "P11 R: the field of view back, no tilt (%.2f, %.2f)", P.cam.fov, P.cam.ang.r)
    -- P12 a view entity
    P.cam.pos:SetUnpacked(5, 6, 7)
    PLY.view_entity = { removed = false }
    held.forward = 10000
    frames(5)
    local vv = M.lastView
    check(vv == nil and P.state == "on", "P12 a view entity: its view wins, the freeze stays")
    held.forward = 0
    PLY.view_entity = nil
    hook_frame()
    check(M.lastView and math.abs(M.lastView.origin.x - 5) < 0.001 and M.lastView.origin.y == 6, "P12 the free camera where it was when the entity goes (%.2f)", M.lastView and M.lastView.origin.x or -1)
    -- first person
    local d0 = GSA1.cv.cam_dist:GetFloat()
    leave()
    RunConsoleCommand("gsa1_cam_distance", "0")
    frames(2)
    check(GSA1.FirstPerson() == true, "first person before")
    press()
    frames(2)
    check(GSA1.FirstPerson() == false, "P9 from first person: the body shows while the free camera is on")
    press()
    frames(3)
    check(GSA1.FirstPerson() == true, "P9 first person again after")
    RunConsoleCommand("gsa1_cam_distance", tostring(d0))
    frames(2)
end

-- P13, P14, P26. HUD, hint, shadows ---------------------------------------------------------------------------------------------------------------------------------
do
    local names = { "CHudHealth", "CHudGMod", "CHudChat", "CHudCrosshair", "NetGraph" }
    press()
    hook_frame()
    local allFalse = true
    for _, n in ipairs(names) do if M.run_hook("HUDShouldDraw", n) ~= false then allFalse = false end end
    check(allFalse, "P13 HUDShouldDraw false for every name with the box on")
    typing = true
    check(M.run_hook("HUDShouldDraw", "CHudChat") == nil, "P26 [RP.12] the chat while typing: not hidden")
    typing = false
    local hv = P.prevHudVisible
    P.prevHudVisible = function() return true end
    check(GSA1.Hud.Visible() == false, "P13 G-SA1's own HUD draws nothing")
    RunConsoleCommand("gsa1_photo_hud", "0")
    check(GSA1.Hud.Visible() == true, "P13 with the box off it draws")
    RunConsoleCommand("gsa1_photo_hud", "1")
    P.prevHudVisible = hv
    RunConsoleCommand("gsa1_photo_hud", "0")
    check(M.run_hook("HUDShouldDraw", "CHudHealth") == nil, "P13 box off: nil")
    RunConsoleCommand("gsa1_photo_hud", "1")
    -- the hint in DrawOverlay
    local texts = {}
    local st = draw.SimpleText
    draw.SimpleText = function(t) texts[#texts + 1] = t return st(t) end
    M.run_hook("DrawOverlay")
    local whole = table.concat(texts, " ")
    check(string.find(whole, "KEY21", 1, true) ~= nil and string.find(whole, "Escape", 1, true) ~= nil, "P13 the reminder, with the key in use (%s)", whole)
    texts = {}
    M.T = M.T + 5
    M.run_hook("DrawOverlay")
    check(#texts == 0, "P13 gone after 4 s")
    leave()
    RunConsoleCommand("gsa1_photo_hint", "0")
    press()
    hook_frame()
    texts = {}
    M.run_hook("DrawOverlay")
    check(#texts == 0, "P13 none with its box off")
    leave()
    RunConsoleCommand("gsa1_photo_hint", "1")
    press()
    hook_frame()
    held.forward = 10000
    frames(2)
    held.forward = 0
    texts = {}
    M.run_hook("DrawOverlay")
    check(#texts == 0, "P13 gone when the camera first moves")
    draw.SimpleText = st
    leave()
    -- shadows
    local S = GSA1.SunShadow
    RunConsoleCommand("gsa1_photo_shadows", "1")
    press()
    frames(2)
    check(S.hooked == false and GSA1.PhotoNoShadow() == true and GetConVar("gsa1_sunshadow"):GetBool() and GSA1.cv.shadow:GetBool(), "P14 the box hides the sun shadow and the blob, no ConVar written")
    local eb, blob = gsa1.EmitBatch, 0
    gsa1.EmitBatch = function(id, i)
        if i == 3 then blob = blob + 1 end
        return eb(id, i)
    end
    frames(2)
    local hidden = blob
    RunConsoleCommand("gsa1_photo_shadows", "0")
    frames(2)
    check(hidden == 0 and blob > 0, "P14 the blob's batch is not drawn while hidden, at once back when unticked (%d, %d)", hidden, blob)
    gsa1.EmitBatch = eb
    RunConsoleCommand("gsa1_photo_shadows", "1")
    frames(1)
    leave()
    check(S.hooked == true and not GSA1.PhotoNoShadow(), "P14 back at the end")
    RunConsoleCommand("gsa1_photo_shadows", "0")
    press()
    frames(2)
    check(S.hooked == true and not GSA1.PhotoNoShadow(), "P14 the box off: they stay")
    leave()
end

-- the small wraps, one by one [3.5, RP.7, RP.8] ---------------------------------------------------------------------------------------------------------------------------
do
    local I, B, GC, V, W = GSA1.Interact, GSA1.Board, GSA1.GameCam, GSA1.ObjView, GSA1.Wheel
    frames(3)
    check(GSA1.InputBlocked() ~= true, "the input is free before")
    check(M.run_hook("PlayerBindPress", PLY, "something", true, 21) == true, "P2 a key with a Garry's Mod bind is swallowed while there is something to freeze")
    check(M.run_hook("PlayerBindPress", PLY, "something", true, 22) ~= true, "P2 no other key")
    local keepP = P.prevViewOverride
    local chain = 0
    P.prevViewOverride = function()
        chain = chain + 1
        return { origin = Vector(9, 9, 9), angles = Angle(1, 2, 0), fov = 50 }
    end
    press()
    frames(2)
    local v = M.lastView
    check(chain > 0 and v.origin.x == 9 and v.angles.y == 2 and v.fov == 50, "P9 the free camera starts from the fishing camera's view, and its chain keeps running")
    P.prevViewOverride = keepP
    check(GSA1.InputBlocked() == true and W.Busy() ~= nil, "3.2 GSA1.InputBlocked while on: the wheel, the faces, the Super key, Start wait (%s)", tostring(W.Busy()))
    -- the fishing camera's lock stands aside
    local lk = P.prevLocked
    P.prevLocked = function() return true end
    check(GC.Locked() == false, "4.2 the fishing camera's lock stands aside for the free camera")
    P.prevLocked = lk
    -- E
    local ip, pressed = I.Press, 0
    I.Press = function() pressed = pressed + 1 end
    I.cmdDown, I.keyDown = true, false
    I.KeyThink(GSA1.Char)
    check(pressed == 0, "3.5 the interact key acts on nothing while frozen (%d)", pressed)
    P.prevKeyThink(GSA1.Char)
    check(pressed == 1, "3.5 (the same call with no wrap does: %d)", pressed)
    I.cmdDown, I.keyDown = nil, false
    I.Press = ip
    -- a board box's word waits; the pump waits
    local realBox, boxed = P.prevOnBox, 0
    P.prevOnBox = function() boxed = boxed + 1 end
    B.OnBox(1, 1, 0, 0, Vector(), 0, 0, 0, 0)
    check(boxed == 0 and #P.boxes == 1, "3.5 the server's word about a Board box waits (%d, %d)", boxed, #P.boxes)
    for i = 1, 40 do B.OnBox(1, 1, 0, 0, Vector(), 0, 0, 0, 0) end
    check(#P.boxes <= 16, "3.5 at most 16 of them (%d)", #P.boxes)
    local lq = B.leftQueue
    local old = { at = SysTime() - 100, C = F1 }
    B.leftQueue = { old }
    B.LeftPump()
    check(B.leftQueue[1] == old, "3.5 B.LeftPump does nothing while frozen")
    B.leftQueue = lq
    -- a far picture's private world: no time
    local vready = V.Ready
    V.Ready = function() return true end
    FM.previewDt = nil
    V.lastGone = SysTime()
    frames(1)
    local dtFrozen = FM.previewDt
    leave()
    check(boxed == math.min(boxed, 16) and boxed >= 1, "3.5 the words of the boxes come at the end (%d)", boxed)
    P.prevOnBox = realBox
    V.lastGone = SysTime()
    FM.previewDt = nil
    frames(1)
    V.Ready = vready
    check(dtFrozen == 0 and FM.previewDt and FM.previewDt > 0, "3.3 far ring and box pictures stop turning: gsa1.PreviewTick gets no time while frozen (%s, then %s)", tostring(dtFrozen), tostring(FM.previewDt))
    -- [RP.7] riding: the board camera's clock keeps moving, the first step after is one frame's
    local Cn = GSA1.Char
    local b = B.State(Cn)
    M.yaw = 90
    frames(2)
    press()
    frames(2)
    local wasOn = b.on
    b.on = true
    M.T = M.T + 10
    frames(30)
    check(math.abs(B.cam.last - SysTime()) <= 1 / 30, "P5 [RP.7] B.cam.last keeps moving (%.3f behind)", SysTime() - B.cam.last)
    check(M.yaw == 90, "P5 [RP.7] the board's camera does not ease the yaw while frozen (%.2f)", M.yaw)
    Cn.drawYaw = 0
    B.cam.pauseUntil = 0
    local cm = B.CameraMove(cmdo)
    check(cm == false and M.yaw == 90, "P5 B.CameraMove does nothing while frozen, whatever the board wants (%s, %.2f)", tostring(cm), M.yaw)
    press()
    hook_frame()
    local d = math.abs(M.yaw - 90)
    check(d <= 90 * 0.06, "P5 [RP.7] the first frames after: a frame's easing, not the clamp's 22 %% (%.2f degrees of 90)", d)
    b.on = wasOn
    M.yaw = 0
    frames(3)
end

-- P15. the ways out ----------------------------------------------------------------------------------------------------------------------------------------------------
do
    frames(3)
    press()
    frames(2)
    check(M.run_hook("OnPauseMenuShow") == false, "P15 Escape: the menu does not open")
    frames(2)
    check(not frozen(), "P15 Escape ends it")
    frames(30)
    check(M.run_hook("OnPauseMenuShow") == nil, "P15 the second Escape opens it")
    -- the dead player with no PLAYER_DIED [RP.9]
    press()
    frames(2)
    PLY.alive = false
    hook_frame()
    check(not frozen(), "P15 [RP.9] a dead player, no message: ends (%s)", tostring(P.state))
    PLY.alive = true
    frames(2)
    press()
    frames(2)
    GSA1.Interact.OnPlayerDied({ class = "x", how = 1, attacker = 0 })
    check(not frozen(), "P15 the player's death by message: ends first")
    frames(3)
    GSA1.Interact.playerDied = nil
    -- Character Select by the command
    local CS = GSA1.CharSelect
    press()
    frames(2)
    local io0 = CS.IsOpen
    CS.IsOpen = function() return true end
    hook_frame()
    CS.IsOpen = io0
    check(P.state ~= "on", "P15 Character Select opened by the command: photo mode leaves (%s)", tostring(P.state))
    frames(3)
    -- the last follower gone with no character
    local keepC = GSA1.Char
    GSA1.Char = nil
    press()
    frames(2)
    check(P.state == "on", "P15 followers only: frozen (%s)", tostring(P.state))
    local list = Fo.list
    Fo.list = {}
    hook_frame()
    Fo.list = list
    check(not frozen(), "P15 the last follower gone with no character: ends")
    GSA1.Char = keepC
    frames(2)
    -- RP.10: a character made while frozen with followers only
    GSA1.Char = nil
    press()
    frames(2)
    GSA1.Char = keepC
    M.run_hook("GSA1CharacterCreated", keepC, "spawned", nil)
    check(not frozen(), "P15 [RP.10] a character made while frozen with followers only: ends")
    frames(2)
    -- your character removed, followers left: no GSA1CharacterCreated comes
    press()
    frames(2)
    GSA1.Remove(true)
    check(not frozen(), "P15 your character removed while frozen: ends at once, the hook GSA1CharacterLeaving")
    GSA1.Spawn("sonic")
    C = GSA1.Char
    frames(2)
    -- ShutDown
    press()
    frames(1)
    M.run_hook("ShutDown")
    check(not frozen(), "P15 ShutDown ends it")
    frames(2)
    -- RP.2, answer 13: a teleport does not wake you; it waits for the end, with the real load order
    local T = GSA1.Teleport
    press()
    frames(2)
    FM.warps = 0
    local warpsSeen = {}
    hook.Add("GSA1CharacterCreated", "test_photo_warps", function(NC, how)
        if how == "re-created" then
            FM.warps = FM.warps + 1
            warpsSeen[#warpsSeen + 1] = { photo = GSA1.PhotoFrozen and GSA1.PhotoFrozen(), x = NC.drawPos.x }
        end
    end)
    local m = { gen = 1, pos = Vector(300, 300, 300), ang = Angle(), turned = false, vel = Vector(), loop = false, cause = "t", dist = 1, where = "tick" }
    T.Handle(m)
    frames(2)
    check(P.state == "on" and FM.warps == 0, "P15 [RP.2, answer 13] a server teleport wakes nothing, with cl_teleport loaded after cl_photo (%s, %d re-creations)", tostring(P.state), FM.warps)
    leave()
    check(FM.warps == 1 and warpsSeen[1] and warpsSeen[1].photo == false, "P15 [RP.2] one re-creation at the place, only after photo mode has ended (%d)", FM.warps or 0)
    hook.Remove("GSA1CharacterCreated", "test_photo_warps")
    frames(2)
    -- refused to start [P18's first half]
    PLY.alive = false
    press()
    check(not frozen(), "P18 refused with a dead player")
    PLY.alive = true
    frames(2)
    local W = GSA1.Wheel
    W.open = true
    press()
    W.open = false
    check(not frozen(), "P18 refused with the wheel open")
    frames(1)
    GSA1.Interact.pendingKill = { untilT = SysTime() + 1 }
    press()
    GSA1.Interact.pendingKill = nil
    check(not frozen(), "P18 refused with a kill waiting")
    frames(1)
    local list2, keep2 = Fo.list, GSA1.Char
    Fo.list, GSA1.Char = {}, nil
    press()
    Fo.list, GSA1.Char = list2, keep2
    check(not frozen(), "P18 refused with nothing to freeze")
    frames(2)
end

-- P16, U. untouchable: answer 13 ----------------------------------------------------------------------------------------------------------------------------------------------
do
    local I = GSA1.Interact
    C = GSA1.Char
    local NET_HURT = I.NET.HURT
    local function hurt(kill)
        reading = { vals = { 50, 8, Vector(), 0, kill or false, false, "npc_x" }, i = 0 }
        recv_c[NET_HURT](0)
    end
    C.killAsked, C.death = nil, nil        -- (P15's kill)
    hook_frame()
    FM.damage = 0
    hurt()
    check(FM.damage == 1, "U before photo mode a hit lands (%d; blocked: %s; module %s)", FM.damage, tostring(I.HitBlocked(GSA1.Char)), tostring(I.HasModule()))
    press()
    frames(2)
    FM.damage = 0
    hurt()
    hurt(true)
    check(FM.damage == 0 and P.state == "on", "P16, U a hit, a deadly one too, frozen: dropped, not woken (%d; %s)", FM.damage, tostring(P.state))
    -- in multiplayer the same: the owner's answer replaced the plan's
    local sp = game.SinglePlayer
    game.SinglePlayer = function() return false end
    hurt()
    game.SinglePlayer = sp
    check(FM.damage == 0 and P.state == "on", "U in multiplayer the same: nothing lands, nothing wakes (%d; %s)", FM.damage, tostring(P.state))
    pump()
    check(PLY.GSA1Photo == true and PLY.god == true and PLY.notarget == true, "U the server: god mode and no target while frozen (%s %s %s)", tostring(PLY.GSA1Photo), tostring(PLY.god), tostring(PLY.notarget))
    -- every damage, by the server's hook; any damage mode: the hook asks no mode
    local blocked = 0
    for _, t in ipairs({ 2, 8, 64, 16384, 32, 4096, 268435456 }) do
        local dmg = { GetDamageType = function() return t end, GetDamage = function() return 100 end }
        if SV.run("EntityTakeDamage", PLY, dmg) == true then blocked = blocked + 1 end
    end
    check(blocked == 7, "U bullet, slash, blast, drown, fall, the world's: all stopped by the server (%d of 7)", blocked)
    check(SV.run("PlayerShouldTakeDamage", PLY) == false, "U PlayerShouldTakeDamage false")
    check(SV.run("CanPlayerSuicide", PLY) == false, "U the console's kill refused")
    SV.killed = 0
    PLY:Kill()
    PLY:KillSilent()
    check(SV.killed == 0, "U another addon's Player:Kill, a NextBot's: refused (%d)", SV.killed)
    check(SV.run("GetFallDamage", PLY) == 0, "U no fall damage")
    leave()
    pump()
    check(PLY.GSA1Photo == nil and PLY.god == false and PLY.notarget == false, "U it ends with photo mode: god mode and no target as they were (%s %s)", tostring(PLY.god), tostring(PLY.notarget))
    local dmg2 = { GetDamageType = function() return 2 end, GetDamage = function() return 100 end }
    check(SV.run("EntityTakeDamage", PLY, dmg2) ~= true, "U after it the server's damage goes on as ever")
    PLY:Kill()
    check(SV.killed == 1, "U after it Player:Kill kills")
    FM.damage = 0
    frames(2)
    hurt()
    check(FM.damage == 1, "U after it a hit lands, nothing was kept from the freeze (%d)", FM.damage)
    -- god mode the player had before stays
    PLY.god, PLY.notarget = true, true
    press()
    frames(2)
    leave()
    pump()
    check(PLY.god == true and PLY.notarget == true, "U a god mode from before stays after")
    PLY.god, PLY.notarget = false, false
    frames(2)
    -- a client that goes silent is not god for ever
    press()
    frames(2)
    pump()
    local keepFlags = net.SendToServer
    net.SendToServer = function() out_m = nil end
    M.T = M.T + 6
    SV.run("Think")
    check(PLY.GSA1Photo == nil and PLY.god == false, "U no message for 5 s: the server ends it for that player")
    net.SendToServer = keepFlags
    leave()
    frames(2)
    -- the player dying some way that gets through
    press()
    frames(2)
    pump()
    SV.run("PostPlayerDeath", PLY)
    check(PLY.GSA1Photo == nil and PLY.god == false, "U dying some way that gets through: the server's part ends")
    leave()
    frames(2)
end

-- W. answer 12: the world -----------------------------------------------------------------------------------------------------------------------------------------------------
do
    local cv = SV.cvars
    local function world_on() return cv.phys_timescale == "0" and cv.ai_disabled == "1" and cv.nb_stop == "1" end
    local function world_off() return cv.phys_timescale == "1.00" and cv.ai_disabled == "0" and cv.nb_stop == "0" end
    local d = GSA1.CONVARS.gsa1_photo_world
    check(d ~= nil and d.default == "0", "W gsa1_photo_world: default off (%s)", d and d.default or "none")
    press()
    frames(2)
    check(world_off(), "W the box off: the world goes on")
    leave()
    RunConsoleCommand("gsa1_photo_world", "1")
    local function start()
        press()
        frames(2)
        pump()
    end
    -- each way out restores all three
    start()
    check(world_on(), "W the box on: physics, NPCs, NextBots stop (%s %s %s)", cv.phys_timescale, cv.ai_disabled, cv.nb_stop)
    check(SV.files["gsa1_photo_world.txt"] ~= nil, "W a mark on disk for a crash")
    press()
    frames(3)
    pump()
    check(world_off() and SV.files["gsa1_photo_world.txt"] == nil, "W the key: all back, the mark gone")
    start()
    M.run_hook("OnPauseMenuShow")
    frames(3)
    pump()
    check(world_off(), "W Escape: all back")
    frames(30)
    start()
    RunConsoleCommand("gsa1_photo")
    frames(3)
    pump()
    check(world_off(), "W the command, which is the Leave button's: all back")
    start()
    RunConsoleCommand("gsa1_photo_world", "0")
    frames(2)
    pump()
    check(world_off() and P.state == "on", "W the box unticked while frozen: all back, still frozen")
    RunConsoleCommand("gsa1_photo_world", "1")
    frames(2)
    pump()
    check(world_on(), "W ticked again: stops again")
    PLY.alive = false
    hook_frame()
    pump()
    PLY.alive = true
    check(world_off() and not frozen(), "W the player's death, the client's part: all back")
    frames(2)
    start()
    SV.run("PostPlayerDeath", PLY)
    check(world_off(), "W the player's death, the server's part: all back")
    leave()
    frames(2)
    -- the client goes silent
    start()
    local keepSend = net.SendToServer
    net.SendToServer = function() out_m = nil end
    M.T = M.T + 6
    SV.run("Think")
    net.SendToServer = keepSend
    check(world_off(), "W no message for 5 s: all back")
    leave()
    frames(2)
    -- changing map: ShutDown on the server; the mark stays until the next map's load finds nothing to do
    start()
    SV.run("ShutDown")
    check(world_off() and SV.files["gsa1_photo_world.txt"] ~= nil, "W changing map: the server's ShutDown puts them back, the mark stays in case the commands do not run any more")
    PS.WorldRecover()
    check(world_off() and SV.files["gsa1_photo_world.txt"] == nil, "W the next map's load finds nothing to do and takes the mark")
    leave()
    frames(2)
    -- a crash and restart: a new server state finds the mark. A value still frozen goes back; values the restart reset stay
    SV.files["gsa1_photo_world.txt"] = "phys_timescale 1.00\nai_disabled 0\nnb_stop 0"
    cv.phys_timescale, cv.ai_disabled, cv.nb_stop = "0", "0", "1"
    PS.WorldRecover()
    check(world_off() and SV.files["gsa1_photo_world.txt"] == nil, "W a crash and restart: what is still frozen goes back, the mark gone (%s %s %s)", cv.phys_timescale, cv.ai_disabled, cv.nb_stop)
    -- what the person had set stays: they ticked Disable AI themselves
    cv.ai_disabled = "1"
    start()
    leave()
    pump()
    check(cv.ai_disabled == "1" and cv.phys_timescale == "1.00", "W the person's own ai_disabled 1 stays after (%s)", cv.ai_disabled)
    cv.ai_disabled = "0"
    -- changed by hand while frozen: not overwritten
    start()
    cv.phys_timescale = "0.5"
    leave()
    pump()
    check(cv.phys_timescale == "0.5", "W a value changed by hand while frozen is left (%s)", cv.phys_timescale)
    cv.phys_timescale = "1.00"
    frames(2)
    -- what did not take is said
    SV.refuse.nb_stop = true
    start()
    M.T = M.T + 0.5
    SV.run("Think")
    pump()
    check(P.worldMask == 3, "W a ConVar that does not take: the page knows (mask %s)", tostring(P.worldMask))
    SV.refuse.nb_stop = nil
    leave()
    frames(2)
    -- multiplayer: never, even if a client asks
    SV.single = false
    local sp = game.SinglePlayer
    game.SinglePlayer = function() return false end
    press()
    frames(2)
    pump()
    check(world_off(), "W multiplayer: the box does nothing to a server for other people")
    check(P.WantFlags() == 1, "W multiplayer: the client does not even ask (%d)", P.WantFlags())
    PLY.GSA1Active = true       -- (a character may be untouchable in multiplayer; it may not stop the world)
    reading = { vals = { 3, false }, i = 0 }
    recv_s[P.NET](0, PLY)
    check(PLY.GSA1Photo == true and world_off(), "W multiplayer: a character's client asking anyway is refused by the server (%s)", tostring(PLY.GSA1Photo))
    PLY.GSA1Active = nil
    leave()
    game.SinglePlayer = sp
    SV.single = true
    frames(2)
    RunConsoleCommand("gsa1_photo_world", "0")
    frames(2)
end

-- P17. followers made and removed while frozen --------------------------------------------------------------------------------------------------------------------------------
do
    press()
    frames(2)
    local F3 = add_follower()
    check(F3 ~= nil and (F3.batches.count or 0) > 0, "P17 a follower made while frozen has its first pose (%d batches)", F3 and F3.batches.count or -1)
    local t0 = FM.ticks
    frames(5)
    check(FM.ticks == t0, "P17 with 0 FollowersTick")
    Fo.Remove(F3, "test")
    check(Fo.byId[F3.id] == nil and P.state == "on", "P17 one removed is gone at once, frozen still")
    leave()
    frames(2)
end

-- P18. refused keys --------------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local function refused(code)
        RunConsoleCommand("gsa1_photo_key", tostring(code))
        frames(1)
        return GetConVar("gsa1_photo_key"):GetInt() ~= code
    end
    local list = { "gsa1_board_key", "gsa1_wheel_key", "gsa1_wheel_face_key", "gsa1_interact_key", "gsa1_lift_key", "gsa1_follower_call_key", "gsa1_debug_key", "gsa1_charselect_key", "gsa1_note_key", "gsa1_look_camera_key", "gsa1_lipsync_key", "gsa1_face_event_key", "gsa1_face_hotkey_1", "gsa1_face_hotkey_10", "gsa1_cam_fish_toggle_key" }
    local c = 140
    for _, name in ipairs(list) do
        local cvar = GetConVar(name)
        if cvar then
            c = c + 1
            local old = cvar:GetString()
            cvar:SetString(tostring(c))
            check(refused(c) and GetConVar("gsa1_photo_key"):GetInt() == 21, "P18 [RP.1] the key of %s is refused, the old key stays", name)
            cvar:SetString(old)
        else
            info("P18 no ConVar %s in this tree", name)
        end
    end
    BINDS["+menu"], BINDS["+speed"], BINDS["+walk"], BINDS["toggleconsole"] = "170", "171", "172", "173"
    for _, code in ipairs({ 170, 171, 172, 173 }) do check(refused(code), "P18 the key bound to a way to the page or the camera (%d)", code) end
    BINDS = {}
    check(not refused(174), "P18 a key nobody uses is taken")
    RunConsoleCommand("gsa1_photo_key", "21")
    frames(1)
    BINDS = {}
    -- the other keys refuse K
    local note = GSA1.Board.KeyRefused(21)
    check(note ~= nil, "P18 the other keys refuse K (%s)", tostring(note))
    RunConsoleCommand("gsa1_debug_key", "21")
    frames(1)
    check(GetConVar("gsa1_debug_key"):GetInt() == 18, "P18 [RP.1] the debug key is put back when set to the photo key (%d)", GetConVar("gsa1_debug_key"):GetInt())
    -- the default clashes with no key of the addon's: a later key cannot clash unseen
    local clash = {}
    for name, cvar in pairs(M.convars) do
        if string.find(name, "^gsa1_") and (string.find(name, "_key$") or string.find(name, "_hotkey_%d+$")) and name ~= "gsa1_photo_key" and cvar:GetInt() == 21 then clash[#clash + 1] = name end
    end
    check(#clash == 0, "P18 K is no other key of the addon's (%s)", table.concat(clash, " "))
end

-- the hitch section ---------------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local ha, n = GSA1.HitchAdd, 0
    GSA1.HitchAdd = function(name, t)
        if name == "Photo" then n = n + 1 end
        if ha then return ha(name, t) end
    end
    frames(5)
    check(n == 0, "8 the hitch section \"Photo\": nothing while off (%d)", n)
    press()
    frames(5)
    check(n >= 5, "8 and a line of its own while frozen (%d)", n)
    leave()
    GSA1.HitchAdd = ha
end

-- P19. garbage -----------------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local function think_bytes(n)
        if jit and jit.off then jit.off() jit.flush() end
        collectgarbage("collect")
        collectgarbage("stop")
        local k0 = collectgarbage("count")
        for _ = 1, n do
            M.T = M.T + 1 / 60
            M.frameNo = M.frameNo + 1
            GSA1.PhotoThink(M.T)
            GSA1.PhotoCmd(cmdo)
            GSA1.ViewOverride({ origin = Vector(), angles = Angle(), fov = 90 }, GSA1.Char, PLY)
        end
        local d = (collectgarbage("count") - k0) * 1024 / n
        collectgarbage("restart")
        if jit and jit.on then jit.on() end
        return d
    end
    local function own_bytes(n)
        if jit and jit.off then jit.off() jit.flush() end
        collectgarbage("collect")
        collectgarbage("stop")
        local k0 = collectgarbage("count")
        for _ = 1, n do
            M.T = M.T + 1 / 60
            M.frameNo = M.frameNo + 1
            local t = { origin = Vector(), angles = Angle(), fov = 90 }
        end
        local d = (collectgarbage("count") - k0) * 1024 / n
        collectgarbage("restart")
        if jit and jit.on then jit.on() end
        return d
    end
    local own = own_bytes(300)
    local off = think_bytes(300) - own
    press()
    frames(2)
    local on = think_bytes(300) - own
    leave()
    info("P19 the seams' own Lua garbage, the test's objects taken off: not frozen %.1f bytes a frame, frozen %.1f", off, on)
    check(on <= 240, "P19 frozen: no more than the view table a frame (%.1f bytes)", on)
    check(off <= 16, "P19 not frozen: nothing of its own (%.1f bytes)", off)
end

-- P20. the view's tangent --------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local O = GSA1.Objects
    frames(3)
    local t0 = O.ViewTan(SysTime())
    press()
    frames(3)
    P.cam.fov = 30
    frames(3)
    M.T = M.T + 2
    frames(1)
    local t1 = O.ViewTan(SysTime())
    check(t1 == t0, "P20 O.ViewTan does not move with the photo's field of view (%.4f, %.4f)", t0, t1)
    press()
    local t2 = O.ViewTan(SysTime())
    check(t2 == t0, "P20 nor in the thaw step (%.4f)", t2)
    frames(3)
end

-- P21. the eye to the server --------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local sent = 0
    local keep = net.SendToServer
    net.SendToServer = function()
        if out_m and out_m.name == P.NET then sent = sent + 1 end
        return keep()
    end
    frames(2)
    press()
    hook_frame()
    sent = 0
    frames(240)         -- 4 s standing still
    check(sent >= 1 and sent <= 3, "P21 still: about every 2 s (%d in 4 s)", sent)
    sent = 0
    held.forward = 10000
    RunConsoleCommand("gsa1_photo_speed", "2000")
    frames(120)
    held.forward = 0
    RunConsoleCommand("gsa1_photo_speed", "200")
    check(sent <= 9, "P21 flying: at most 4 a second (%d in 2 s)", sent)
    frames(30)
    pump()
    SV.pvs = 0
    local rule = SV.env.GSA1.RingsRule
    SV.env.GSA1.RingsRule = function() return true end
    PLY.GSA1Active = true
    M.T = M.T + 3
    frames(2)
    pump()
    SV.run("SetupPlayerVisibility", PLY)
    check(SV.pvs >= 1, "P21 the server adds the eye's place (%d)", SV.pvs)
    SV.env.GSA1.RingsRule = function() return false end
    PLY.GSA1PhotoEye = nil
    M.T = M.T + 3
    frames(2)
    pump()
    SV.pvs = 0
    SV.run("SetupPlayerVisibility", PLY)
    check(SV.pvs == 0, "P21 refused to a non-admin in multiplayer: nobody looks through walls at what is not sent")
    SV.env.GSA1.RingsRule = function() return true end
    M.T = M.T + 3
    frames(2)
    pump()
    SV.inworld = false
    PLY.GSA1PhotoEye = nil
    M.T = M.T + 3
    frames(2)
    pump()
    SV.inworld = nil
    SV.pvs = 0
    SV.run("SetupPlayerVisibility", PLY)
    check(SV.pvs == 0, "P21 [RP.15] an eye outside the world refused")
    SV.env.GSA1.RingsRule = rule
    PLY.GSA1Active = nil
    net.SendToServer = keep
    leave()
    frames(2)
end

-- V. what 0.9.9d's verifier found (SADC/build/research/r099d/verify/photo_attack.txt, mymut.txt): who may in multiplayer; the server's commands that run later; a teleport and a re-creation; the reminder on a smaller screen; what no test pinned ----
do
    local I, T = GSA1.Interact, GSA1.Teleport
    local function msg(flags, eye)
        reading = { vals = { flags, eye ~= nil, eye }, i = 0 }
        recv_s[P.NET](0, PLY)
    end
    local function nobody() return PLY.GSA1Photo == nil and PLY.god == false and PLY.notarget == false end
    local function says() return string.format("%s, god %s, no target %s", tostring(PLY.GSA1Photo), tostring(PLY.god), tostring(PLY.notarget)) end
    local function near(a, b, e) return a ~= nil and math.abs(a - b) < (e or 0.1) end
    local cv = SV.cvars
    local bullet = { GetDamageType = function() return 2 end, GetDamage = function() return 100 end, GetAttacker = function() return nil end }
    local other = {}
    local byPly = { GetDamageType = function() return 2 end, GetDamage = function() return 100 end, GetAttacker = function() return PLY end }
    local byOther = { GetDamageType = function() return 2 end, GetDamage = function() return 100 end, GetAttacker = function() return other end }
    local FV = add_follower()      -- (the sections before took the first two away)
    check(FV ~= nil, "V a follower")
    frames(2)
    msg(0)
    PLY.GSA1Active = nil

    -- V1 (fail 1) in multiplayer only a character: a plain player's message, or freezing your followers and walking on armed, gets no god mode
    SV.single = false
    local spc = game.SinglePlayer
    game.SinglePlayer = function() return false end
    msg(1)
    check(nobody(), "V1 multiplayer: a plain player's own message gets nothing (%s)", says())
    check(SV.run("EntityTakeDamage", PLY, bullet) ~= true, "V1 multiplayer: and a bullet lands on it")
    msg(3)
    check(nobody() and cv.phys_timescale == "1.00", "V1 multiplayer: asked with the world too: nothing (%s)", says())
    local keepC = GSA1.Char
    GSA1.Char = nil
    press()
    frames(2)
    pump()
    check(P.state == "on" and P.FreeCam() == false and nobody(), "V1 multiplayer, followers only, the key: they freeze, the player stays an ordinary player (%s, free camera %s, %s)", tostring(P.state), tostring(P.FreeCam()), says())
    check(string.find(P.StatusLine(), "only a character", 1, true) ~= nil, "V1 the page says so (%s)", P.StatusLine())
    -- (no free camera with followers alone: the walk, the attack and the mouse stay the player's)
    held.forward, held.buttons = 5000, 1
    hook_frame()
    check(cmdv.forward == 5000 and cmdv.buttons == 1, "V1 followers only: the walk and the attack stay the player's (%s, %s)", tostring(cmdv.forward), tostring(cmdv.buttons))
    held.forward, held.buttons = 0, 0
    check(M.run_hook("InputMouseApply", cmdo, 3, 3, Angle(M.pitch, M.yaw, 0)) == nil, "V1 followers only: the mouse too")
    RunConsoleCommand("gsa1_photo")
    frames(5)
    GSA1.Char = keepC
    frames(2)
    PLY.GSA1Active = true
    msg(1)
    check(PLY.GSA1Photo == true and PLY.god == true and PLY.notarget == true, "V1 multiplayer, a character: untouchable, answer 13 (%s)", says())
    check(SV.run("EntityTakeDamage", PLY, bullet) == true, "V1 multiplayer, a character: a bullet stopped")
    check(SV.run("EntityTakeDamage", other, byPly) == true, "V1 multiplayer: while untouchable it hurts nobody either")
    check(SV.run("EntityTakeDamage", other, byOther) ~= true, "V1 multiplayer: others' damage goes on")
    M.T = M.T + 1
    PLY.GSA1Active = false
    SV.run("Think")
    check(nobody(), "V1 multiplayer: a character no more: over, in the next tick (%s)", says())
    msg(1)
    check(nobody(), "V1 multiplayer: and asking again gets nothing (%s)", says())
    SV.single = true
    game.SinglePlayer = spc
    PLY.GSA1Active = nil
    msg(1)
    check(PLY.GSA1Photo == true and PLY.god == true, "V1 single player: followers only too, nobody else is on the server (%s)", says())
    check(SV.run("EntityTakeDamage", other, byPly) ~= true, "V1 single player: what you shoot is still hurt")
    msg(0)
    check(nobody(), "V1 single player: over")

    -- V2 (fail 4) the eye's rules, RP.15: a character only, its own rate, gone at the end
    local rule = SV.env.GSA1.RingsRule
    SV.env.GSA1.RingsRule = function() return true end
    M.T = M.T + 1
    msg(1, Vector(1, 2, 3))
    check(PLY.GSA1Photo == true and PLY.GSA1PhotoEye == nil, "V2 the eye: not from a player who is no character")
    PLY.GSA1Active = true
    msg(1, Vector(1, 2, 3))
    check(PLY.GSA1PhotoEye ~= nil and PLY.GSA1PhotoEye.x == 1, "V2 the eye: a character's is taken")
    msg(1, Vector(4, 5, 6))
    check(PLY.GSA1PhotoEye.x == 1, "V2 the eye: its own rate, not again within %.1f s", PS.EYE_EVERY)
    M.T = M.T + PS.EYE_EVERY + 0.01
    msg(1, Vector(4, 5, 6))
    check(PLY.GSA1PhotoEye.x == 4, "V2 the eye: and after it")
    SV.pvs = 0
    SV.run("SetupPlayerVisibility", PLY)
    check(SV.pvs == 1 and SV.pvsAt.x == 4, "V2 the server adds that place")
    msg(0)
    SV.pvs = 0
    SV.run("SetupPlayerVisibility", PLY)
    check(PLY.GSA1PhotoEye == nil and SV.pvs == 0, "V2 the eye is gone with photo mode (P21)")
    SV.env.GSA1.RingsRule = rule
    PLY.GSA1Active = nil

    -- V3 (fail 4) a dead player
    PLY.alive = false
    msg(1)
    PLY.alive = true
    check(nobody(), "V3 a dead player's message: nothing (%s)", says())

    -- V4 (fail 4) a crash and restart: only what still holds photo mode's value goes back
    SV.files[PS.MARK] = "phys_timescale 1.00\nai_disabled 0\nnb_stop 0"
    cv.phys_timescale, cv.ai_disabled, cv.nb_stop = "0.5", "0", "1"
    PS.WorldRecover()
    check(cv.phys_timescale == "0.5" and cv.nb_stop == "0" and SV.files[PS.MARK] == nil, "V4 a crash and restart: a value changed since stays, the frozen one goes back (%s, %s)", cv.phys_timescale, cv.nb_stop)
    cv.phys_timescale = "1.00"
    M.T = M.T + 1
    SV.run("Think")

    -- V5 (fail 6) the server's commands run later, as Source's do (my memory of the wiki's note: UNVERIFIED; the mock's at-once hides it): two opposite messages in one server tick
    do
        local S = SV.env
        local real = S.RunConsoleCommand
        local queue = {}
        S.RunConsoleCommand = function(n, v) queue[#queue + 1] = { n, v } end
        local function tick(n)     -- the next server ticks: the queue runs, then Think
            for _ = 1, n or 1 do
                local q = queue
                queue = {}
                for _, c in ipairs(q) do real(c[1], c[2]) end
                M.T = M.T + 1 / 60
                SV.run("Think")
            end
        end
        local function line() return string.format("%s %s %s, mark %s", cv.phys_timescale, cv.ai_disabled, cv.nb_stop, tostring(SV.files[PS.MARK] ~= nil)) end
        local function is_on() return cv.phys_timescale == "0" and cv.ai_disabled == "1" and cv.nb_stop == "1" and SV.files[PS.MARK] ~= nil end
        local function is_off() return cv.phys_timescale == "1.00" and cv.ai_disabled == "0" and cv.nb_stop == "0" and SV.files[PS.MARK] == nil end
        msg(3)
        tick(3)
        check(is_on(), "V5 the commands run later: frozen a tick after (%s)", line())
        msg(1) msg(3)
        tick(4)
        check(is_on(), "V5 unticked and ticked in one tick: frozen (%s)", line())
        msg(0)
        tick(3)
        check(is_off(), "V5 then left: all back, the mark gone (%s)", line())
        msg(3) msg(1)
        tick(4)
        check(is_off(), "V5 ticked and unticked in one tick: all back, the mark gone (%s)", line())
        msg(0)
        tick(2)
        msg(3) msg(0)
        tick(4)
        check(is_off(), "V5 asked and left in one tick: all back (%s)", line())
        msg(3)
        tick(3)
        msg(0) msg(3) msg(0)
        tick(4)
        check(is_off(), "V5 left, again, left in one tick: all back (%s)", line())
        for _ = 1, 5 do
            msg(3) msg(1) msg(3)
            tick(1)
            msg(1) msg(3) msg(0)
            tick(1)
        end
        tick(8)
        check(is_off(), "V5 five rounds of that, a tick apart: all back (%s)", line())
        -- the person's own Disable AI through all of it
        cv.ai_disabled = "1"
        msg(3)
        tick(3)
        msg(1) msg(3)
        tick(4)
        msg(0)
        tick(4)
        check(cv.ai_disabled == "1" and cv.phys_timescale == "1.00", "V5 the person's own Disable AI stays (%s)", line())
        cv.ai_disabled = "0"
        -- left, and the map ends before the commands ran: the mark is still there for the next load
        msg(3)
        tick(3)
        msg(0)
        SV.run("ShutDown")
        queue = {}
        check(SV.files[PS.MARK] ~= nil, "V5 left and the map ends before the commands ran: the mark stays (%s)", line())
        S.RunConsoleCommand = real
        PS.WorldRecover()
        M.T = M.T + 1
        SV.run("Think")
        check(is_off(), "V5 and the next load puts them back (%s)", line())
    end

    -- V6 (fail 4) the way out with no thaw: the clocks move too, the server hears at once (ShutDown runs no frame after it)
    frames(2)
    press()
    frames(2)
    pump()
    do
        local T0 = SysTime()
        local F0 = FV
        I.actionUntil, F0.guardUntil = T0 + 4, T0 + 5
        M.T = M.T + 60
        local s = SysTime() - T0
        P.EndNow("a test")
        check(near(I.actionUntil, T0 + 4 + s) and near(F0.guardUntil, T0 + 5 + s), "V6 EndNow moves the clocks on by the freeze's length (%s, %s, by %.1f)", tostring(I.actionUntil and I.actionUntil - T0), tostring(F0.guardUntil and F0.guardUntil - T0), s)
        I.actionUntil, F0.guardUntil = nil, nil
        pump()
        check(PLY.GSA1Photo == nil and PLY.god == false, "V6 EndNow tells the server at once (%s)", says())
    end
    frames(3)

    -- V7 (fail 4) the mouse: the pitch held, slower when zoomed in
    press()
    frames(2)
    do
        local a = P.cam.ang
        M.run_hook("InputMouseApply", cmdo, 0, 1000000, Angle(M.pitch, M.yaw, 0))
        check(a.p == 89, "V7 the pitch held to 89 going down (%.1f)", a.p)
        M.run_hook("InputMouseApply", cmdo, 0, -1000000, Angle(M.pitch, M.yaw, 0))
        check(a.p == -89, "V7 the pitch held to -89 going up (%.1f)", a.p)
        local fov, fov0 = P.cam.fov, P.cam.fov0
        P.cam.fov, P.cam.fov0 = 80, 80
        local y0 = a.y
        M.run_hook("InputMouseApply", cmdo, 100, 0, Angle(M.pitch, M.yaw, 0))
        local d1 = a.y - y0
        P.cam.fov = 40
        y0 = a.y
        M.run_hook("InputMouseApply", cmdo, 100, 0, Angle(M.pitch, M.yaw, 0))
        local d2 = a.y - y0
        P.cam.fov, P.cam.fov0 = fov, fov0
        check(d1 ~= 0 and math.abs(d2 - d1 / 2) < 1e-6, "V7 zoomed in twice, the mouse half as fast (%.3f, %.3f)", d1, d2)
    end
    leave()

    -- V8 (fail 4) the controller: A lifts, B lowers
    do
        local pad = { connected = true, active = true, sx = 0, sy = 0, buttons = 0, raw = 0x1000, yaw = 0, pitch = 0, reset = false, rx = 0, ry = 0, cx = 0, cy = 0 }
        local realPoll = gsa1.PadPoll
        gsa1.PadPoll = function(dt, paused, out) for k, v in pairs(pad) do out[k] = v end return out end
        GSA1.pad = nil
        frames(2)
        press()
        frames(2)
        local z0 = P.cam.pos.z
        frames(30)
        local z1 = P.cam.pos.z
        pad.raw = 0x2000
        frames(90)
        check(z1 > z0 + 20 and P.cam.pos.z < z1 - 20, "V8 the pad's A lifts, B lowers (%.0f, %.0f, %.0f)", z0, z1, P.cam.pos.z)
        pad.raw = 0
        gsa1.PadPoll = realPoll
        leave()
        GSA1.pad = nil
        frames(2)
    end

    -- V9 (fail 4) the server's loop message is only a message: it does not wait
    press()
    frames(2)
    local function tele(loop) return { gen = 1, pos = Vector(1000, 2000, 300), ang = Angle(0, 90, 0), turned = false, vel = Vector(), loop = loop or false, cause = "a test", dist = 100, where = "tick" } end
    do
        local r = T.Handle(tele(true))
        check(r == "loop" and P.teleport == nil and P.state == "on", "V9 a loop message passes through, nothing waits (%s)", tostring(r))
    end

    -- V10 (fail 4) a follower's first pose only while frozen
    do
        spy_reset()
        M.run_hook("GSA1FollowerCreated", FV, "a test")
        local on = SPY.Batches or 0
        leave()
        frames(2)
        spy_reset()
        M.run_hook("GSA1FollowerCreated", FV, "a test")
        local off = SPY.Batches or 0
        spy_off()
        check(on == 1 and off == 0, "V10 gsa1.Batches for a new follower while frozen, not otherwise (%d, %d)", on, off)
    end

    -- V11 (fail 4) the key's own bind is swallowed only while there is something to freeze
    do
        local keepList = Fo.list
        local kc = GSA1.Char
        check(GSA1.BindOverride(PLY, "anything", true, 21) == true, "V11 the key: swallowed with something to freeze")
        GSA1.Char, Fo.list = nil, {}
        local r = GSA1.BindOverride(PLY, "anything", true, 21)
        GSA1.Char, Fo.list = kc, keepList
        check(r ~= true, "V11 the key: left alone with nothing to freeze (%s)", tostring(r))
    end

    -- V12 (fail 5) a teleport waits, then the character is re-created: it goes to the new one. 0.9.9e: with no gsa1.Warp, as in the real module, a teleport re-creates; every way out, and no world
    -- left with no owner (r099d/verify2/nowarp.txt: Respawn's destroy ran the teleport's GSA1.Recreate inside it, and that new world stayed)
    do
        local live, ev = {}, {}
        local c0, d0 = gsa1.Create, gsa1.Destroy
        gsa1.Create = function(...)
            local id, err = c0(...)
            if id then live[id] = true end
            ev[#ev + 1] = "create"
            return id, err
        end
        gsa1.Destroy = function(id, ...)
            ev[#ev + 1] = live[id] and "destroy" or "destroy of one already gone"
            live[id] = nil
            return d0(id, ...)
        end
        live[GSA1.Char.id] = true
        for _, F in ipairs(Fo.list) do live[F.id] = true end
        local function orphans()
            local keep, n = { [GSA1.Char and GSA1.Char.id or -1] = true }, 0
            for _, F in ipairs(Fo.list) do keep[F.id] = true end
            for id in pairs(live) do if not keep[id] then n = n + 1 end end
            return n
        end
        local function evs() return table.concat(ev, ", ") end
        local function round(how, act, x)
            frames(3)
            press()
            frames(2)
            local m = tele()
            m.pos = Vector(x, 2000, 300)
            local r = T.Handle(m)
            for k in pairs(ev) do ev[k] = nil end
            local ok, err = pcall(act)
            check(ok, "V12 %s: no error (%s)", how, tostring(err))
            check(r == "frozen for a photo" and not frozen(), "V12 %s: it waited, and the freeze is over at once (%s, %s)", how, tostring(r), tostring(P.state))
            local before = evs()
            hook_frame()
            frames(2)
            check(orphans() == 0 and not string.find(evs(), "already gone", 1, true), "V12 %s: no world left with no owner, none destroyed twice (%d; %s)", how, orphans(), evs())
            return before
        end
        round("re-created", function() GSA1.Recreate("a test") end, 1000)
        check(GSA1.Char.drawPos.x == 1000 and P.teleport == nil and P.teleportNext == nil, "V12 re-created: the character goes to the place, nothing still waits (%.0f)", GSA1.Char.drawPos.x)
        -- another one comes after it and before the next frame: the last one wins
        frames(2)
        press()
        frames(2)
        T.Handle(tele())
        GSA1.Recreate("a test")
        local second = tele()
        second.pos = Vector(3000, 0, 0)
        T.Handle(second)
        hook_frame()
        frames(2)
        check(GSA1.Char.drawPos.x == 3000, "V12 a newer one before the next frame: the last one wins (%.0f)", GSA1.Char.drawPos.x)
        round("switched", function() GSA1.Spawn("tails") end, 1500)
        check(GSA1.Char.name == "tails" and GSA1.Char.drawPos.x == 1500, "V12 switched: the new character at the place (%.0f)", GSA1.Char.drawPos.x)
        GSA1.Spawn("sonic")
        live[GSA1.Char.id] = true
        -- a respawn goes to its spawn point, as it does without photo mode: one destroy, one create, nothing runs inside it, nothing waits
        for _, cmd in ipairs({ { "GSA1.Respawn", function() GSA1.Respawn("a test") end }, { "gsa1_respawn", function() RunConsoleCommand("gsa1_respawn") end } }) do
            local sp = Vector(GSA1.Char.spawnPos)
            local before = round("respawned by " .. cmd[1], cmd[2], 7000)
            check(before == "destroy, create", "V12 respawned by %s: one destroy, one create, in that order (%s)", cmd[1], before)
            check(GSA1.Char.drawPos.x == sp.x and GSA1.Char.drawPos.x ~= 7000 and P.teleport == nil and P.teleportNext == nil, "V12 respawned by %s: at its spawn point, the teleport dropped (%.0f, spawn %.0f)", cmd[1], GSA1.Char.drawPos.x, sp.x)
        end
        -- the same respawn with a re-creation before it in one frame: nothing goes after the respawn either
        frames(2)
        press()
        frames(2)
        T.Handle(tele())
        GSA1.Recreate("a test")
        GSA1.Respawn("a test")
        hook_frame()
        frames(2)
        check(P.teleportNext == nil and GSA1.Char.drawPos.x == GSA1.Char.spawnPos.x and GSA1.Char.drawPos.x ~= 1000, "V12 a re-creation and a respawn in one frame: the respawn wins (%.0f)", GSA1.Char.drawPos.x)
        check(orphans() == 0, "V12 ... no world left with no owner")
        -- removed for good: nothing to move, no error, nothing left
        round("removed", function() GSA1.Remove(true) end, 9000)
        check(GSA1.Char == nil and P.teleport == nil and P.teleportNext == nil, "V12 removed: nothing moves, nothing waits (%s)", evs())
        gsa1.Create, gsa1.Destroy = c0, d0
        GSA1.Spawn("sonic")
        C = GSA1.Char
        frames(3)
    end

    -- V13 (fail 7) the reminder fits the screen: lines, not one line clipped at both ends
    do
        local sw, simple = ScrW, draw.SimpleText
        for _, row in ipairs({ { 3440, 1, 1 }, { 1920, 2, 2 }, { 1280, 2, 3 }, { 1024, 2, 4 } }) do
            ScrW = function() return row[1] end
            P.hintLines = { "from the last freeze: another key, another screen" }
            press()
            hook_frame()
            local got = {}
            draw.SimpleText = function(t, _, x, y) got[#got + 1] = { t = t, x = x, y = y } end
            M.run_hook("DrawOverlay")
            draw.SimpleText = simple
            local parts, wide, rising = {}, 0, true
            for i, g in ipairs(got) do
                parts[i] = g.t
                wide = math.max(wide, 15 * #g.t)
                if i > 1 and g.y <= got[i - 1].y then rising = false end
                if g.x ~= row[1] / 2 then rising = false end
            end
            check(#got >= row[2] and #got <= row[3] and wide <= row[1] * 0.9 and rising and table.concat(parts, " ") == P.HintText(), "V13 a screen %d wide: %d lines, the widest %d px, all of the text, line under line", row[1], #got, wide)
            leave()
            frames(2)
        end
        -- the window changes size while it shows
        ScrW = function() return 3440 end
        press()
        hook_frame()
        local one, two = {}, {}
        draw.SimpleText = function(t) one[#one + 1] = t end
        M.run_hook("DrawOverlay")
        ScrW = function() return 1024 end
        draw.SimpleText = function(t) two[#two + 1] = t end
        M.run_hook("DrawOverlay")
        draw.SimpleText = simple
        check(#one == 1 and #two >= 2, "V13 the window made smaller while it shows: it fits again (%d, then %d lines)", #one, #two)
        leave()
        frames(2)
        ScrW = sw
    end
    Fo.Remove(FV, "a test")
    frames(2)
end

-- P22. the page ------------------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local page
    for _, p in ipairs(GSA1.MenuPages) do if p.id == "photo" then page = p end end
    check(page ~= nil and page.order == 295 and page.title == "Photo mode", "P22 the page: Q menu > Options > G-SA1 > Photo mode, after Followers")
    local calls = {}
    local any = setmetatable({}, { __index = function(t) return function() return t end end, __call = function(t) return t end })
    local PN = setmetatable({}, { __index = function(_, k)
        return function(_, ...)
            calls[#calls + 1] = { k, ... }
            return any
        end
    end })
    local vc = vgui.Create
    local binder
    vgui.Create = function(cls) if cls == "DBinder" then binder = true end return any end
    local ok_page, err_page = pcall(page and page.builder or function() error("no page") end, PN)
    vgui.Create = vc
    check(ok_page, "P22 it builds (%s)", tostring(err_page))
    local has = {}
    for _, c in ipairs(calls) do
        for i = 2, #c do if type(c[i]) == "string" then has[c[i]] = c[1] end end
    end
    check(binder == true, "P22 a DBinder on the key")
    for _, row in ipairs({ { "gsa1_photo", "Button" }, { "gsa1_photo_key", "Button" }, { "gsa1_photo_hud", "CheckBox" }, { "gsa1_photo_shadows", "CheckBox" }, { "gsa1_photo_jukebox", "CheckBox" }, { "gsa1_photo_speed", "NumSlider" }, { "gsa1_photo_hint", "CheckBox" }, { "gsa1_photo_world", "CheckBox" } }) do
        check(has[row[1]] == row[2], "P22 %s: a %s (%s)", row[1], row[2], tostring(has[row[1]]))
    end
    check(has["Controller button"] == "ComboBox", "P22 the controller button's combo box (%s)", tostring(has["Controller button"]))
    -- every ConVar of the feature has a row
    for name in pairs(GSA1.CONVARS) do
        if string.find(name, "^gsa1_photo_") and name ~= "gsa1_photo_pad" then check(has[name] ~= nil, "P22 %s has a control", name) end
    end
    local line = P.StatusLine()
    check(type(line) == "string" and string.find(line, "Not frozen", 1, true) ~= nil, "P22 the status line (%s)", tostring(line))
    press()
    frames(2)
    local line2 = P.StatusLine()
    check(string.find(line2, "Frozen for", 1, true) ~= nil, "P22 the status line frozen (%s)", line2)
    leave()
end

-- P23. no ConVar written; P24. an error ends it; P25. Start -----------------------------------------------------------------------------------------------------------------------
do
    local writes = {}
    local seen = {}
    for name, c in pairs(M.convars) do seen[name] = c:GetString() end
    press()
    M.T = M.T + 5
    held.forward = 10000
    frames(30)
    held.forward = 0
    M.run_hook("PlayerBindPress", PLY, "invprev", true, 112)
    leave()
    for name, c in pairs(M.convars) do if seen[name] ~= c:GetString() then writes[#writes + 1] = name end end
    check(#writes == 0, "P23 no ConVar written by a whole freeze (%s)", table.concat(writes, " "))
end
do
    -- P25 [RP.4] Start with Escape, in both orders: Character Select does not open
    local CS = GSA1.CharSelect
    local RAW = 0
    local pu = GSA1.PadUpdate
    GSA1.PadUpdate = function() GSA1.pad = { connected = true, active = false, sx = 0, sy = 0, buttons = 0, raw = RAW, yaw = 0, pitch = 0, reset = false, rx = 0, ry = 0, cx = 0, cy = 0 } end
    local realOpen, opened = CS.Open, 0
    CS.Open = function() opened = opened + 1 end
    local sa = CS.StartAllowed
    CS.StartAllowed = function() return true end
    for _, way in ipairs({ "escape first", "start first" }) do
        frames(2)
        press()
        frames(2)
        opened = 0
        if way == "escape first" then
            M.run_hook("OnPauseMenuShow")
            hook_frame()
            RAW = 0x0010
            frames(3)
        else
            RAW = 0x0010
            hook_frame()
            M.run_hook("OnPauseMenuShow")
            frames(3)
        end
        check(not frozen() and opened == 0, "P25 [RP.4] %s: photo mode ends, Character Select does not open (%d)", way, opened)
        RAW = 0
        frames(30)
        RAW = 0x0010
        frames(2)
        check(opened == 1, "P25 a later press of Start does open it (%d)", opened)
        RAW = 0
        frames(2)
    end
    CS.Open, CS.StartAllowed = realOpen, sa
    GSA1.PadUpdate = pu
    GSA1.pad = nil
    frames(2)
end
do
    -- P24 [RP.11]: last, because it stops the feature for the rest of the session
    local realKey = input.IsButtonDown
    press()
    frames(2)
    pump()
    check(PLY.GSA1Photo == true, "P24 frozen, the server knows")
    local t0 = M.ticks.last
    local errors0 = #M.reported
    input.IsButtonDown = function(c)
        if c == 21 then error("a test's failure") end
        return realKey(c)
    end
    hook_frame()
    input.IsButtonDown = realKey
    check(P.state == "off" and not frozen(), "P24 [RP.11] an error in PhotoThink's body: photo mode off (%s)", tostring(P.state))
    check(PLY.GSA1Photo == nil and PLY.god == false, "P24 the server is told by the failure itself: no 5 s of god mode (%s, %s)", tostring(PLY.GSA1Photo), tostring(PLY.god))
    check(M.ticks.last ~= t0, "P24 the same frame's tick and sound run")
    local reported = #M.reported
    frames(5)
    check(#M.reported == reported, "P24 no error in the following frames (%d)", #M.reported - reported)
    M.reported = {}
end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
