-- feat_water_host_test.lua - "Water follows Garry's Mod's water": the host flags each tick passes into libsa1
-- (sadc docs/research/gsa1_090_water.md WTR-A, the G-SA1 half, with its review R3.5 / R4; gsa1_090_plan.md 6.10 task 4;
-- owner default B1 (a): on), and the host camera seam's default (task 8).
-- The addon's client through its autorun on tests/lua_mock.lua, in Garry's Mod's own LuaJIT, with a mocked
-- util.PointContents (a water box and a slime box):
--   lua_host tests/feat_water_host_test.lua <tests dir> <addon/lua dir>
-- Checks: KNOWN | IN_WATER inside the water (and slime), KNOWN outside; the point tested is the PREVIOUS tick's libsa1 state
-- position + 4 units (the game's probe point), never the drawn position or the player entity; the option off and a module
-- without host flags pass 0 (the game's own rule); the host camera goes to the module only when it takes it.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_water_host_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

local G = M.module({})
GSA1 = nil
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
check(ok_load, "the addon loads (%s)", tostring(err_load or "ok"))
if not ok_load then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
local function frames(n) for _ = 1, n do M.frame(1 / 60) end end

-- Garry's Mod's water: a pool (x 600..800, y 0..300, z -200..-100) and a slime pit (x 2000..2200, y 0..300, z -200..-100)
local probes = {}
M.contents = function(p)
    probes[#probes + 1] = Vector(p)
    if p.x >= 600 and p.x <= 800 and p.y >= 0 and p.y <= 300 and p.z >= -200 and p.z <= -100 then return CONTENTS_WATER end
    if p.x >= 2000 and p.x <= 2200 and p.y >= 0 and p.y <= 300 and p.z >= -200 and p.z <= -100 then return CONTENTS_SLIME end
    return 0
end
local function last_flags() return M.ticks.last and M.ticks.last.hflags end

GSA1.Spawn("sonic")              -- at the player (704, 132, -143) + 4: in the pool
local C = GSA1.Char
check(C ~= nil, "Sonic spawned")
if not C then return done() end
local id = C.id
frames(5)
check(last_flags() == 3, "in Garry's Mod water: host flags KNOWN | IN_WATER (%s)", tostring(last_flags()))
local p = probes[#probes]
check(p and math.abs(p.x - C.state.x) < 1e-3 and math.abs(p.y - C.state.y) < 1e-3 and math.abs(p.z - (C.state.z + 4)) < 1e-3,
    "the point tested is the state position + 4 units (%.1f %.1f %.1f; state z %.1f)", p and p.x or 0, p and p.y or 0,
    p and p.z or 0, C.state.z or 0)

-- the game moves the character out of the water: the tick after the move still has the old state (one tick late: the
-- previous tick's position, review R3.5), the one after it says dry
M.mchars[id].pos = Vector(1200, 100, -139)
M.frame(1 / 60)                  -- this frame's tick ran with the state of the tick before (in the pool), then GetState
local f1 = last_flags()
M.frame(1 / 60)
local f2 = last_flags()
check(f1 == 3 and f2 == 1, "moved out of the water: the next tick still passes the previous state's water (%s), the one "
    .. "after it KNOWN only (%s)", tostring(f1), tostring(f2))

-- the drawn position and the player entity do not count
M.mchars[id].pos = Vector(1200, 100, -139)
C.drawPos = Vector(700, 100, -139)                -- in the pool
M.player.pos = Vector(700, 100, -150)             -- in the pool
local ren = G.Render
G.Render = function(i, a)                         -- keep the drawn position in the pool
    local r = { ren(i, a) }
    r[3], r[4], r[5] = 700, 100, -139
    return unpack(r)
end
frames(3)
G.Render = ren
check(last_flags() == 1, "the drawn position and the player entity in the water, the state dry: KNOWN only (%s)",
    tostring(last_flags()))

-- slime counts as water
M.mchars[id].pos = Vector(2100, 100, -139)
frames(3)
check(last_flags() == 3, "in Garry's Mod slime: KNOWN | IN_WATER (%s)", tostring(last_flags()))

-- the option off: 0, the game's own rule; a module without host flags: 0
if M.convars.gsa1_hostwater then M.convars.gsa1_hostwater:SetString("0") end
frames(2)
local off = last_flags()
if M.convars.gsa1_hostwater then M.convars.gsa1_hostwater:SetString("1") end
G.TICK_HOST_FLAGS = nil
frames(2)
local old = last_flags()
G.TICK_HOST_FLAGS = true
frames(2)
check(off == 0 and old == 0 and last_flags() == 3, "\"Water follows Garry's Mod's water\" off: 0 (%s); a module without "
    .. "host flags: 0 (%s); on again: %s", tostring(off), tostring(old), tostring(last_flags()))
check(C.hostFlags == 3, "the character remembers the flags of its last tick (C.hostFlags %s, for the water log)",
    tostring(C.hostFlags))

-- the host camera: asked for and passed only when the module and libsa1 take it (gsa1.TICK_HOST_CAMERA)
frames(2)
local no_cam = M.ticks.last.co == nil and M.ticks.last.ct == nil
G.TICK_HOST_CAMERA = true
frames(2)
local t = M.ticks.last
local v = GSA1.view
local ok_cam = t.co ~= nil and t.ct ~= nil and v and v.origin and math.abs(t.co.x - v.origin.x) < 1e-3 and
    math.abs(t.co.z - v.origin.z) < 1e-3 and math.abs((t.ct - t.co):Length() - 100) < 1e-2
G.TICK_HOST_CAMERA = false
check(no_cam and ok_cam, "the host camera: none while the module does not take it; then this frame's view (%.0f %.0f %.0f) and "
    .. "a point 100 units ahead", t.co and t.co.x or 0, t.co and t.co.y or 0, t.co and t.co.z or 0)
check(#M.reported == 0, "no Lua error (%s)", M.reported[1] or "none")
return done()
