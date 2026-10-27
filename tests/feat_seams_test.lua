-- feat_seams_test.lua - the seams 0.9.2 adds to cl_character.lua for the next rounds' feature files (sadc
-- docs/research/gsa1_090_plan.md 6.10 task 8 and decision 7: the fishing camera, the Character Select chooser and the
-- player follow hook in here instead of editing cl_character.lua; gsa1_090_bigfish.md review R3.7, gsa1_090_charselect.md
-- RC8), and the L6 client half (task 6: CreateMove lets jump and attack through while the player is dead).
-- The addon's client through its autorun on tests/lua_mock.lua, in Garry's Mod's own LuaJIT:
--   lua_host tests/feat_seams_test.lua <tests dir> <addon/lua dir>
-- Part 1: with no feature using them nothing changes (0.9.1's behaviour: the view's yaw, the chase view, the keys, the
-- 20 Hz state send). Part 2: every seam is called and does what it says.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_seams_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

local G = M.module({ speed = 300 })
-- the server has G-SA1 (its network strings): the built-in state send runs; what is sent is recorded
local sent = {}
util.NetworkStringToID = function() return 1 end
net.Start = function(name) sent[#sent + 1] = { name = name, t = M.T } end
GSA1 = nil
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
check(ok_load, "the addon loads (%s)", tostring(err_load or "ok"))
if not ok_load then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
local function frames(n) for _ = 1, n do M.frame(1 / 60) end end
local function count_sent(name, t0)
    local n = 0
    for _, s in ipairs(sent) do if s.name == name and s.t > t0 then n = n + 1 end end
    return n
end
local post = {}
hook.Add("GSA1PostTick", "seams_test", function(C, st, dt) post[#post + 1] = { C = C, st = st, dt = dt } end)

GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil, "Sonic spawned")
if not C then return done() end

-- 1. the defaults change nothing --------------------------------------------------------------------------------------------
check(type(GSA1.ViewOverride) == "function" and type(GSA1.TickYaw) == "function" and type(GSA1.InputBlocked) == "function"
    and type(GSA1.TickCamera) == "function" and GSA1.NetSendOverride == nil,
    "the seams exist: GSA1.ViewOverride, GSA1.TickYaw, GSA1.InputBlocked, GSA1.TickCamera (functions), "
    .. "GSA1.NetSendOverride (unset)")
M.yaw, M.forward, M.keys = 37, 10000, IN_JUMP
local t0 = M.T
frames(60)
local tk = M.ticks.last
local view = M.run_hook("CalcView", M.player, M.player:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
local drawn = C.drawPos
check(tk.yaw == 37 and tk.sy == 1 and tk.buttons == 1 and tk.co == nil,
    "the tick: the view's yaw (%s), the keys' stick (%s) and buttons (%s), no host camera (the module does not take it)",
    tostring(tk.yaw), tostring(tk.sy), tostring(tk.buttons))
check(view and view.origin and math.abs(view.origin.x - (drawn.x - 150 * math.cos(math.rad(M.pitch)) * math.cos(math.rad(37)))) < 0.5,
    "the chase view as before: %.1f units behind the character (the camera distance 150)", view and
    (view.origin - Vector(drawn.x, drawn.y, view.origin.z)):Length() or -1)
local n20 = count_sent(GSA1.NET_STATE, t0)
check(n20 >= 18 and n20 <= 21, "the built-in state send: %d packets in 1 s (20 Hz)", n20)
check(#post >= 25 and post[#post].C == C and post[#post].st == C.state and post[#post].dt > 0,
    "the hook GSA1PostTick(C, state, dt) runs after every tick (%d times in 60 frames)", #post)

-- 2. every seam is called and does what it says ------------------------------------------------------------------------
-- GSA1.TickYaw: the stick's frame
local yaw_calls = 0
local yaw0 = GSA1.TickYaw
GSA1.TickYaw = function(c)
    yaw_calls = yaw_calls + 1
    return c == C and 123 or nil
end
frames(3)
check(yaw_calls >= 3 and M.ticks.last.yaw == 123, "GSA1.TickYaw: called every tick (%d), its yaw goes into the tick (%s)",
    yaw_calls, tostring(M.ticks.last.yaw))
GSA1.TickYaw = yaw0

-- GSA1.ViewOverride: the frame's view
local ov_calls, ov_seen = 0, nil
local ov0 = GSA1.ViewOverride
GSA1.ViewOverride = function(v, c, ply)
    ov_calls = ov_calls + 1
    ov_seen = v
    return { origin = Vector(1, 2, 3), angles = Angle(10, 20, 0), fov = 60, drawviewer = false }
end
frames(2)
local vo = M.run_hook("CalcView", M.player, M.player:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
check(ov_calls >= 2 and ov_seen and ov_seen.origin and vo and vo.origin.x == 1 and vo.origin.z == 3 and
    GSA1.view.origin.x == 1 and GSA1.view.fov == 60, "GSA1.ViewOverride: called with G-SA1's own view, its view is "
    .. "the frame's (and GSA1.view's)")
-- a feature that has nothing to say returns nil: G-SA1's view stays
GSA1.ViewOverride = function() return nil end
vo = M.run_hook("CalcView", M.player, M.player:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
check(vo and vo.origin.x ~= 1, "a ViewOverride returning nil leaves G-SA1's view")
-- looking through a camera entity wins before the seam
local seen_cam = 0
GSA1.ViewOverride = function() seen_cam = seen_cam + 1 return nil end
M.player.view_entity = { removed = false }
vo = M.run_hook("CalcView", M.player, M.player:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
M.player.view_entity = nil
check(vo == nil and seen_cam == 0, "a view entity (the Camera tool) wins: no G-SA1 view, the seam is not asked")
GSA1.ViewOverride = ov0

-- GSA1.InputBlocked: a neutral pad, the controller's view turning held
local blocked_calls = 0
local pv_calls = 0
local pv0 = GSA1.PadView
GSA1.PadView = function() pv_calls = pv_calls + 1 end
local ib0 = GSA1.InputBlocked
GSA1.InputBlocked = function() blocked_calls = blocked_calls + 1 return true end
M.forward, M.keys = 10000, IN_JUMP + IN_ATTACK
frames(3)
tk = M.ticks.last
check(blocked_calls >= 6 and tk.sx == 0 and tk.sy == 0 and tk.buttons == 0 and pv_calls == 0,
    "GSA1.InputBlocked true: asked by CreateMove and the tick (%d), the character gets a neutral pad (stick %s %s, "
    .. "buttons %s), the controller does not turn the view", blocked_calls, tostring(tk.sx), tostring(tk.sy),
    tostring(tk.buttons))
GSA1.InputBlocked = ib0
frames(2)
check(M.ticks.last.sy == 1 and M.ticks.last.buttons == 3 and pv_calls > 0, "unblocked: the keys again (buttons %s)",
    tostring(M.ticks.last.buttons))
GSA1.PadView = pv0

-- GSA1.NetSendOverride: replaces the built-in send
local ns_calls, ns_args = 0, nil
GSA1.NetSendOverride = function(c, st, now)
    ns_calls = ns_calls + 1
    ns_args = { c, st, now }
end
t0 = M.T
frames(30)
check(ns_calls >= 15 and ns_args[1] == C and ns_args[2] == C.state and type(ns_args[3]) == "number" and
    count_sent(GSA1.NET_STATE, t0) == 0, "GSA1.NetSendOverride: called every tick (%d) with (C, state, now); the built-in "
    .. "20 Hz send is skipped", ns_calls)
GSA1.NetSendOverride = function() error("a broken send") end
frames(2)
check(GSA1.Char == C, "an error in the override is logged; the character carries on")
GSA1.NetSendOverride = nil

-- GSA1.TickCamera: asked only when the module takes the host camera
local cam_calls = 0
local tc0 = GSA1.TickCamera
GSA1.TickCamera = function(c) cam_calls = cam_calls + 1 return Vector(5, 6, 7), Vector(5, 6, 8) end
frames(2)
local asked_without = cam_calls
G.TICK_HOST_CAMERA = true
frames(2)
G.TICK_HOST_CAMERA = false
check(asked_without == 0 and cam_calls >= 2 and M.ticks.last.co and M.ticks.last.co.z == 7 and M.ticks.last.ct.z == 8,
    "GSA1.TickCamera: not asked while the module does not take a camera; then its origin and target go into the tick")
GSA1.TickCamera = tc0

-- 3. L6, the client half: CreateMove lets jump and attack through while the player is dead --------------------------------
M.keys = IN_JUMP + IN_ATTACK + IN_ATTACK2 + IN_DUCK
frames(1)
local alive_out = M.cmdOut
M.player.alive = false
frames(1)
local dead_out = M.cmdOut
M.player.alive = true
frames(1)
check(alive_out == 0 and dead_out == IN_JUMP + IN_ATTACK + IN_ATTACK2 and M.cmdOut == 0,
    "CreateMove: alive, every button cleared (%s); dead, jump and attack go through to the gamemode's respawn (%s; duck "
    .. "cleared)", tostring(alive_out), tostring(dead_out))
M.keys = 0

check(#M.reported == 0, "no Lua error (%s)", M.reported[1] or "none")
return done()
