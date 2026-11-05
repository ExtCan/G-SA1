-- feat_lightbody_test.lua - 0.9.9d: the character's map light is sampled at the body's middle (gsa1_light_body; the owner: "Knuckles still turns completely black on walls"). cl_render.lua's update_lighting with the real draw
-- path, in Garry's Mod's LuaJIT against tests/lua_mock.lua. The numbers of the world below are the owner's, MEASURED in their game with render.ComputeLighting, normal (0 1 0), on gm_construct_remaster_csm: inside the wall
-- (1283 -1032 109) 0 0 0; at the body (1283 -1009 86) 0.128 0.238 0.379. What the game alone can show is not here: that Source's ComputeLighting and PointContents answer so at every wall.
--   lua_host tests/feat_lightbody_test.lua <tests dir> <addon/lua dir>
-- Run against the frozen 0.9.9c (<addon/lua dir> = build/release_0.9.9c/addon/lua) the wall's checks fail: there the point is always drawPos + (0, 0, center).
-- Checks:
--   1 the option, its row on the Rendering page; default on
--   2 upright: exactly the numbers 0.9.9c asks for, bit for bit, on and off: every origin of a walk
--   3 on a wall: the body's middle, the owner's numbers; off gives 0.9.9c's black; a ceiling too
--   4 the point still solid: the last good light stays, no question asked at the solid point; the first frame; back out
--   5 a follower on a wall takes the same path, a far follower every 4th frame as before
--   6 a module without upx, upy, upz, and a nonsense up: 0.9.9c's point
--   7 cost: one util.PointContents a frame more at most for your character, none with the option off; no Lua garbage of its own
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_lightbody_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end
local G = M.module({ archives = { [0] = { 28 } }, speed = 0, features = { render = 1 } })
function G.TextureArchives() return { { name = "SONIC", count = 28 } } end
local realState = G.GetState
local UP = {}           -- [id] = { x, y, z }; none: a module without the fields
function G.GetState(id, out)
    local r = realState(id, out)
    local u = UP[id]
    if r then r.upx, r.upy, r.upz = u and u[1], u and u[2], u and u[3] end
    return r
end
-- the world: a wall at y -1024, solid behind it; the owner's numbers in the open, nothing in the wall
local CONTENTS_SOLID_ = 1
local BODY = Vector(0.128, 0.238, 0.379)
local asks = {}
local recording = false
local function wall_solid(p) return p.y < -1024 and p.y > -1400 and p.x > 1000 and p.x < 1800 end
render.ComputeLighting = function(p, n)
    if recording then asks[#asks + 1] = { x = p.x, y = p.y, z = p.z } end
    if M.solidNow and M.solidNow(p) or wall_solid(p) then return Vector(0, 0, 0) end
    return Vector(BODY)
end
local solidExtra
M.contents = function(p)
    if solidExtra and solidExtra(p) then return CONTENTS_SOLID_ end
    return wall_solid(p) and CONTENTS_SOLID_ or 0
end
M.solidNow = function(p) return solidExtra and solidExtra(p) end
GSA1 = nil
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
check(ok_load and GSA1 ~= nil, "the addon loads (%s)", tostring(err_load))
if not (ok_load and GSA1) then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
GSA1.cv.prewarm:SetString("0")
GSA1.Spawn("knuckles")
local C = GSA1.Char
check(C ~= nil, "Knuckles spawned")
if not C then return done() end
local mc = M.mchars[C.id]
local function opt(v) if GetConVar("gsa1_light_body") then RunConsoleCommand("gsa1_light_body", v and "1" or "0") end end
local function at(x, y, z) mc.pos.x, mc.pos.y, mc.pos.z = x, y, z end
local function frame_rec()
    asks = {}
    recording = true
    M.frame()
    recording = false
    return asks
end
local center = C.info.center or 20

-- 1. the option ----------------------------------------------------------------------------------------------------------------------
do
    local d = GetConVar("gsa1_light_body")
    check(d ~= nil and d:GetString() == "1" and d.lo == 0 and d.hi == 1 and d.save == true, "gsa1_light_body: default 1, 0 .. 1, saved (%s)", d and d:GetString() or "no such setting")
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    local page
    for _, e in ipairs(M.menu) do if e.class == "gsa1_rendering" then page = e end end
    local calls = {}
    local any = setmetatable({}, { __index = function(t) return function() return t end end })
    local P = setmetatable({}, { __index = function(_, k)
        return function(_, ...)
            calls[#calls + 1] = { k, ... }
            return any
        end
    end })
    local built = page and pcall(page.cpanel, P)
    local row, lighting
    for i, c in ipairs(calls) do
        if c[1] == "CheckBox" and c[3] == "gsa1_light_body" then row = i end
        if c[1] == "CheckBox" and c[3] == "gsa1_lighting" then lighting = i end
    end
    check(built and row ~= nil and lighting ~= nil and row > lighting, "Options > G-SA1 > Rendering: the check box \"%s\" after the map lighting's (row %s)", row and calls[row][2] or "no row", tostring(row))
end

-- 2. upright: 0.9.9c's numbers, exactly -------------------------------------------------------------------------------------------------
do
    UP[C.id] = { 0, 0, 1 }
    local bad, n = 0, 0
    local function walk(on)
        opt(on)
        local out = {}
        local x, y, z = 0.1, -300.7, 12.3
        for i = 1, 90 do
            x, y, z = x + 3.3, y + 1.7, z + math.sin(i) * 5
            at(x, y, z)
            local a = frame_rec()
            for _, p in ipairs(a) do out[#out + 1] = p end
            local want = C.drawPos
            for _, p in ipairs(a) do
                n = n + 1
                if p.x ~= want.x or p.y ~= want.y or p.z ~= want.z + center then bad = bad + 1 end
            end
        end
        return out
    end
    local on = walk(true)
    local off = walk(false)
    check(n >= 90 * 2 * 6 and bad == 0, "upright, the option on and off: every sample at exactly drawPos + (0, 0, center) (%d of %d off)", bad, n)
    local same = #on == #off
    for i = 1, math.min(#on, #off) do
        if on[i].x ~= off[i].x or on[i].y ~= off[i].y or on[i].z ~= off[i].z then same = false end
    end
    check(same and #on > 0, "upright: the same numbers with the option on and off, bit for bit (%d samples)", #on)
    opt(true)
end

-- 3. on a wall ----------------------------------------------------------------------------------------------------------------------------
do
    UP[C.id] = { 0, 1, 0 }
    at(1283, -1032, 86)
    opt(true)
    M.frame()       -- (the state with the new up: the tick comes before the draw)
    local a = frame_rec()
    local p = a[1]
    check(p ~= nil and #a == 6 and p.x == C.drawPos.x and p.y == C.drawPos.y + center and p.z == C.drawPos.z, "on a wall: the six samples at the body's middle, drawPos + up * center (%.1f %.1f %.1f, %d samples)", p and p.x or 0, p and p.y or 0, p and p.z or 0, #a)
    local l = C.light and C.light[3]
    check(l and l.x == BODY.x and l.y == BODY.y and l.z == BODY.z, "on a wall: the owner's numbers at the body, not black (%.3f %.3f %.3f)", l and l.x or -1, l and l.y or -1, l and l.z or -1)
    -- the light reaches the draw
    local seen
    local real = render.SetModelLighting
    render.SetModelLighting = function(i, r, g, b)
        if i == 3 then seen = { r, g, b } end
        if real then return real(i, r, g, b) end
    end
    M.frame()
    render.SetModelLighting = real
    check(seen and seen[1] == BODY.x and seen[3] == BODY.z, "the draw gets it: render.SetModelLighting(3, %.3f, %.3f, %.3f)", seen and seen[1] or -1, seen and seen[2] or -1, seen and seen[3] or -1)
    -- the option off: 0.9.9c's light, the point in the wall, black
    opt(false)
    M.frame()
    local a2 = frame_rec()
    local p2, l2 = a2[1], C.light and C.light[3]
    check(p2 and p2.y == C.drawPos.y and p2.z == C.drawPos.z + center and l2 and l2.x == 0 and l2.y == 0 and l2.z == 0, "the option off: 0.9.9c's point in the wall, and its black (%.3f %.3f %.3f)", l2 and l2.x or -1, l2 and l2.y or -1, l2 and l2.z or -1)
    opt(true)
    M.frame()
    local l3 = C.light and C.light[3]
    check(l3 and l3.x == BODY.x, "on again: at once (%.3f)", l3 and l3.x or -1)
    -- a character under a ceiling, a tilted one
    UP[C.id] = { 0, 0, -1 }
    at(0, 0, 500)
    M.frame()
    local a3 = frame_rec()
    check(a3[1] and a3[1].z == C.drawPos.z - center and a3[1].x == C.drawPos.x, "upside down: below the root (%.1f)", a3[1] and a3[1].z or 0)
    local r2 = math.sqrt(0.5)
    UP[C.id] = { r2, 0, r2 }
    at(0, 0, 0)
    M.frame()
    local a4 = frame_rec()
    check(a4[1] and math.abs(a4[1].x - center * r2) < 1e-9 and math.abs(a4[1].z - center * r2) < 1e-9, "tilted on a slope: along its own up (%.2f %.2f)", a4[1] and a4[1].x or 0, a4[1] and a4[1].z or 0)
    UP[C.id] = { 0, 0, 1 }
end

-- 4. still solid: the last good light ---------------------------------------------------------------------------------------------------
do
    UP[C.id] = { 0, 1, 0 }
    at(1283, -1032, 86)
    M.frame()
    M.frame()
    local good = C.light and C.light[3]
    -- a wall thicker than the body: the middle of the body is in solid too
    at(1283, -1100, 86)
    M.frame()
    local a = frame_rec()
    local l = C.light and C.light[3]
    check(#a == 0 and l and l == good, "the body's middle in solid: nothing asked there, the last good light stays (%d samples; %.3f)", #a, l and l.x or -1)
    check(C.lightOrigin and C.lightOrigin.y > -1024, "and the lighting origin stays with it, out of the wall (%.1f)", C.lightOrigin and C.lightOrigin.y or 0)
    -- out again: new numbers at once
    at(1283, -1032, 86)
    M.frame()
    local a2 = frame_rec()
    check(#a2 == 6, "out of solid: asked again in the same frame (%d samples)", #a2)
    -- the first frame of a character whose body's middle is in solid: nothing to keep. 0.9.9c's point is asked, so there are numbers and nothing errors; from the first good point on it is the body's
    UP[C.id] = { 0, 1, 0 }
    C.light, C.lightFrame = nil, nil
    at(1283, -1100, 86)
    local a3 = frame_rec()
    check(#a3 == 6 and a3[1].y == C.drawPos.y and a3[1].z == C.drawPos.z + center and C.light ~= nil, "the first frame in solid, nothing kept: 0.9.9c's point is asked (%d samples at %.1f %.1f)", #a3, a3[1] and a3[1].y or 0, a3[1] and a3[1].z or 0)
    local reported = #M.reported
    M.frame()
    check(#M.reported == reported and C.light ~= nil, "no error; the frames after keep that light until the point is free")
    UP[C.id] = { 0, 0, 1 }
    at(0, 0, 0)
    M.frame()
end

-- 5. followers share the path ---------------------------------------------------------------------------------------------------------------
do
    local Fo = GSA1.Followers
    local pos = Vector(1283, -1032, 86)
    local id = G.Create(2, pos, 0, 0, 0)
    local e2 = ents.CreateClientside("gsa1_render")
    UP[id] = { 0, 1, 0 }
    local F = { id = id, kind = 2, name = "knuckles", title = "Knuckles", uid = 1, info = G.CharacterInfo(2), state = {}, batches = { count = 0 }, batchGen = 1, mats = {}, static = {},
                matsDirty = true, ent = e2, drawPos = pos, drawYaw = 0, lod = 1, interp = true, renderGen = 1, follower = true }
    G.Batches(id, F.batches)
    G.GetState(id, F.state)
    e2.char = F
    Fo.list[#Fo.list + 1] = F
    Fo.byId[id] = F
    local rec = {}
    local cl = render.ComputeLighting
    render.ComputeLighting = function(p, n)
        rec[#rec + 1] = p.y
        return cl(p, n)
    end
    M.frame()
    local hit = false
    for _, y in ipairs(rec) do if y == pos.y + (F.info.center or 20) then hit = true end end
    local lf = F.light and F.light[3]
    check(hit and lf and lf.x == BODY.x, "a follower on a wall: its own up, the body's middle, the owner's numbers (%.3f)", lf and lf.x or -1)
    -- a far follower: still every 4th frame
    F.lod = 2
    M.frame()
    local n, frames = 0, 12
    local before = F.lightFrame
    for _ = 1, frames do
        local was = F.lightFrame
        M.frame()
        if F.lightFrame ~= was then n = n + 1 end
    end
    check(n >= 2 and n <= 4, "a far follower: its cube every 4th frame, as 0.9.8's (%d of %d frames)", n, frames)
    render.ComputeLighting = cl
    for i = #Fo.list, 1, -1 do if Fo.list[i] == F then table.remove(Fo.list, i) end end
    Fo.byId[id] = nil
    e2:Remove()
    M.frame()
end

-- 6. a module without the up, nonsense ---------------------------------------------------------------------------------------------------------
do
    UP[C.id] = nil
    at(1283, -1032, 86)
    M.frame()
    local a = frame_rec()
    check(a[1] and a[1].y == C.drawPos.y and a[1].z == C.drawPos.z + center, "a module without upx, upy, upz: 0.9.9c's point (%.1f %.1f)", a[1] and a[1].y or 0, a[1] and a[1].z or 0)
    local nan = 0 / 0
    for _, u in ipairs({ { nan, nan, nan }, { 0, 0, 0 } }) do
        UP[C.id] = u
        M.frame()
        local b = frame_rec()
        check(b[1] and b[1].z == C.drawPos.z + center and b[1].y == b[1].y, "an up of (%s %s %s): 0.9.9c's point, no NaN in the sample", tostring(u[1]), tostring(u[2]), tostring(u[3]))
    end
    UP[C.id] = { 0, 0, 1 }
    at(0, 0, 0)
    M.frame()
end

-- 7. cost ---------------------------------------------------------------------------------------------------------------------------------------
do
    -- PointContents: the option off asks nothing new
    opt(false)
    M.frame()
    M.calls.PointContents = 0
    local function draw_only(n)
        local hk = M.hooks.PreDrawOpaqueRenderables
        for _ = 1, n do M.frame() end
    end
    draw_only(10)
    local offCalls = M.calls.PointContents or 0
    opt(true)
    M.frame()
    M.calls.PointContents = 0
    draw_only(10)
    local onCalls = M.calls.PointContents or 0
    info("util.PointContents in 10 frames: %d off, %d on", offCalls, onCalls)
    check(onCalls <= offCalls + 10, "one question a frame more at most for your character (%d against %d)", onCalls, offCalls)
    -- Lua garbage of the sample itself, the stand-in making none: a wall's frames on against off
    local keep = Vector(0.1, 0.2, 0.3)
    local cl = render.ComputeLighting
    render.ComputeLighting = function() return keep end
    UP[C.id] = { 0, 1, 0 }
    at(1283, -1032, 86)
    M.frame()
    local function bytes(n)
        if jit and jit.off then jit.off() jit.flush() end
        collectgarbage("collect")
        collectgarbage("stop")
        local k0 = collectgarbage("count")
        for _ = 1, n do
            M.T = M.T + 1 / 60
            M.frameNo = M.frameNo + 1
            C.lightFrame = nil
            for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw() end end
        end
        local d = (collectgarbage("count") - k0) * 1024 / n
        collectgarbage("restart")
        if jit and jit.on then jit.on() end
        return d
    end
    opt(false)
    local b0 = bytes(120)
    opt(true)
    local b1 = bytes(120)
    info("the character's draw on a wall: %.1f bytes of Lua garbage a frame off, %.1f on", b0, b1)
    check(b1 <= b0 + 16, "no Lua garbage of its own (%.1f bytes a frame against %.1f)", b1, b0)
    render.ComputeLighting = cl
    UP[C.id] = { 0, 0, 1 }
end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
