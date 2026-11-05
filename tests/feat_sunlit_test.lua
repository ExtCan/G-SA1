-- feat_sunlit_test.lua - 0.9.9c: the sun shadow only where the sun reaches (gsa1_sunshadow_sunlit; the owner's note 2026-11-04 11:20:55: "Sun Shadows
-- appear in Shadowed areas when they should only be in bright spots"). feat/cl_liveshadow.lua and sh_liveshadow.lua with the real render path, in Garry's Mod's LuaJIT against
-- tests/lua_mock.lua, in a small world of its own: a ground plane, boxes with contents, a sky plane; util.TraceLine answers as Source's trace does (Hit, HitSky, HitNoDraw,
-- StartSolid, HitNormal, the mask against the contents). What the game alone can show is not here: that Source's trace answers so, how it looks.
--   lua_host tests/feat_sunlit_test.lua <tests dir> <addon/lua dir>
-- Run against the frozen 0.9.9b (<addon/lua dir> = build/release_0.9.9b/addon/lua): the option is not there and these checks fail, except section 1, which
-- says that with the option off the drawing is 0.9.9b's, by a hash of every vertex of a scripted walk.
-- Checks:
--   1 off: every vertex of a walk over a ledge and past a wall hashes as 0.9.9b's; no trace but the grid's
--   2 the option, its row on the Rendering page, the sun of a map whose shadow_control points elsewhere (gm_construct_remaster_csm's real numbers), the
--     cases with no sun to ask; the first of several; a "target"; "angle"
--   3 the shade comes from the sun's direction, not the shadow's: a wall's slanted shade with nothing straight above; open sun; half in the sun; a roof; a
--     window and water do not stop the sun, nodraw does; no sky at all; a ray that hits nothing; a corner inside a wall on the sunny side does not count;
--     ground turned away from the sun; two levels on one x, y; first person; the reason in the log and on the page
--   4 no pop: walking and running across a shade line a fixed point of the ground changes little from frame to frame, a grid point by at most the fade's
--     step; a roof that arrives fades, it does not snap; the first frame of a shadow in the shade is not lit
--   5 followers: in the shade, in the sun, one lattice for all
--   5b the sunny top of a ledge keeps its shadow, standing near an edge that falls away from the sun: whatever the height, along either axis, on a walkway, for a
--     follower, when the shadow's own light hits the ledge's side; the trace's own normal decides, a trace with none counts as flat ground
--   5c no flash when the corners a frame are spent: followers appearing at once, everyone teleported, a tall character, into the shade: nothing lit; into the sun: there within a
--     few frames; a shadow on the move keeps what it knows
--   5d no notches in full sun (099c's second verifier): curbs and stairs under a shadow slanted another way than the sun: a riser the grid's light hits makes no fade around it, a corner on the foot of a step does not
--     fade a whole cell; ground truly turned from the sun still reads none: a wall, a band, a crease; a sliver and stairs on the grid's rows; what a tall wall shades stays shade
--   5e what the earlier mutation runs did not see: where a ray starts, the plane through the normal, S.SUN_SAME, the followers' budget, the normals' flag, GSA1.SunShadowTraces, the shadow switched off, nil from the engine
--   5g 0.9.9d's verifier: 5f's fade on lines at any angle and under a slanted light (wider than 5f says of an axis), a crease at every phase of the rows
--   5f 0.9.9d, the fade at a shade line (the owner: "The sun shadow disappears in a gradient style."): its width across a straight line and a slanted one, your shadow and a follower's, at every phase of the lattice and
--     the grid; no pop while walking over a slanted line; no more rays than 0.9.9c's on the same walk
--   6 cost: the grid's own traces a frame stay 0.9.9b's, what the check adds at speed, at 1 + 3 and 1 + 8 shadows; standing; the budget; no Lua garbage of its own per frame,
--     sunlit on and off, walking, at speed and through bars of shade
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_sunlit_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- the character's batches, as feat_liveshadow_test.lua's: the body and the board reach the silhouette
local LIST = { { 0, 0, 0x20, 1, 0, 3, 0, 100, 1 }, { -1, -1, 0x40C0, 1, 0, 0, 0, 44, 1 } }
local G = M.module({ archives = { [0] = { 28, 29, 96, 138 } }, batches = function() return LIST end, speed = 0, features = { render = 1 } })
function G.TextureArchives()
    return { { name = "SONIC", count = 28 }, { name = "SON_EFF", count = 29 }, { name = "OBJ_REGULAR", count = 96 }, { name = "EFF_REGULAR", count = 138 } }
end
-- (the engine's own objects are its own: these stand-ins make none, so the addon's garbage can be measured; toneCalls counts what the engine would make)
local toneCalls = 0
local tone, toneOut = Vector(2, 2, 2), Vector()
render.GetToneMappingScaleLinear = function()
    toneCalls = toneCalls + 1
    toneOut:Set(tone)
    return toneOut
end
render.SetToneMappingScaleLinear = function(v) tone:Set(v) end
render.BlurRenderTarget = function() end

-- ---- the world ------------------------------------------------------------------------------------------------------------
local GZ = -143
-- (section 5f: what it measures, in HU; its walk's rays on 0.9.9c, MEASURED)
local WIDE_STRAIGHT, MEAN_STRAIGHT, WIDE_SLANT, MEAN_SLANT, WIDE_FOLLOWER, MEAN_FOLLOWER, RAYS_099C = 19, 13, 13, 10, 13, 13, 225
local CONTENTS_SOLID, CONTENTS_WINDOW, CONTENTS_GRATE, CONTENTS_WATER = 1, 2, 8, 32
local W = { plane = { 0, 0, 1, GZ }, sky = 4000, boxes = {} }
local band = bit.band
local traceN, traceByMask = 0, {}
local function count_masks() traceN, traceByMask = 0, {} end
local function trace_line(t)
    traceN = traceN + 1
    local mask = t.mask or 33570827
    traceByMask[mask] = (traceByMask[mask] or 0) + 1
    local out = t.output or {}
    local s, e = t.start, t.endpos
    local sx, sy, sz, ex, ey, ez = s.x, s.y, s.z, e.x, e.y, e.z
    -- (0.9.9d: W.shade(x, y): a shade line of any slant, for the rays to the sun alone: boxes here can only make straight lines along an axis)
    if W.shade and mask == (MASK_OPAQUE or 16513) and W.shade(sx, sy) then
        out.Fraction, out.StartSolid, out.AllSolid, out.Hit, out.HitSky, out.HitNoDraw = 0.01, false, false, true, false, false
        out.HitPos = out.HitPos or Vector()
        out.HitNormal = out.HitNormal or Vector()
        out.HitPos:SetUnpacked(sx, sy, sz + 400)
        out.HitNormal:SetUnpacked(0, 0, -1)
        return out
    end
    local dx, dy, dz = ex - sx, ey - sy, ez - sz
    local best, nx, ny, nz, sky, nodraw, startSolid, allSolid = 1, 0, 0, 0, false, false, false, false
    local p = W.plane
    if W.height then
        -- a height field of planes (a ridge, a saw): straight-down rays meet it; another ray only says whether it starts under it
        local hz, hx, hy = W.height(sx, sy)
        if sz < hz then
            startSolid = true
        elseif math.abs(dx) < 1e-6 and math.abs(dy) < 1e-6 and ez < hz then
            local l = math.sqrt(hx * hx + hy * hy + 1)
            best, nx, ny, nz = (sz - hz) / (sz - ez), -hx / l, -hy / l, 1 / l
        end
    elseif p then
        local d1 = p[1] * sx + p[2] * sy + p[3] * sz - p[4]
        local d2 = p[1] * ex + p[2] * ey + p[3] * ez - p[4]
        if d1 < 0 then
            startSolid = true
            if d2 < 0 then allSolid = true end
        elseif d2 < 0 then
            best, nx, ny, nz = d1 / (d1 - d2), p[1], p[2], p[3]
        end
    end
    if W.sky and ez > W.sky and sz <= W.sky then
        local f = (W.sky - sz) / dz
        if f < best then best, nx, ny, nz, sky, nodraw = f, 0, 0, -1, true, false end
    end
    for i = 1, #W.boxes do
        local b = W.boxes[i]
        if band(b.contents or CONTENTS_SOLID, mask) ~= 0 then
            local t0, t1, ax, sg = 0, 1, 0, 0
            local miss = false
            -- x
            if dx == 0 then
                if sx < b[1] or sx > b[2] then miss = true end
            else
                local a, c = (b[1] - sx) / dx, (b[2] - sx) / dx
                local f = -1
                if a > c then a, c, f = c, a, 1 end
                if a > t0 then t0, ax, sg = a, 1, f end
                if c < t1 then t1 = c end
            end
            if dy == 0 then
                if sy < b[3] or sy > b[4] then miss = true end
            elseif not miss then
                local a, c = (b[3] - sy) / dy, (b[4] - sy) / dy
                local f = -1
                if a > c then a, c, f = c, a, 1 end
                if a > t0 then t0, ax, sg = a, 2, f end
                if c < t1 then t1 = c end
            end
            if dz == 0 then
                if sz < b[5] or sz > b[6] then miss = true end
            elseif not miss then
                local a, c = (b[5] - sz) / dz, (b[6] - sz) / dz
                local f = -1
                if a > c then a, c, f = c, a, 1 end
                if a > t0 then t0, ax, sg = a, 3, f end
                if c < t1 then t1 = c end
            end
            if not miss and t0 <= t1 then
                if t0 == 0 and ax == 0 then
                    startSolid = true
                    if t1 >= 1 then allSolid = true end
                elseif t0 < best then
                    best, sky, nodraw = t0, false, b.nodraw or false
                    nx, ny, nz = ax == 1 and sg or 0, ax == 2 and sg or 0, ax == 3 and sg or 0
                end
            end
        end
    end
    out.Fraction, out.StartSolid, out.AllSolid = allSolid and 0 or best, startSolid, allSolid
    out.Hit, out.HitSky, out.HitNoDraw = allSolid or best < 1, sky, nodraw
    out.HitPos = out.HitPos or Vector()
    out.HitNormal = out.HitNormal or Vector()
    out.HitPos:SetUnpacked(sx + dx * best, sy + dy * best, sz + dz * best)
    out.HitNormal:SetUnpacked(nx, ny, nz)
    -- (section 6's model of what the engine makes: four userdata a result, as its HitPos, HitNormal, StartPos, Normal: UNVERIFIED which, and how large; the owner's logs say about 170-250 bytes a trace)
    if W.engine then W.e1, W.e2, W.e3, W.e4 = newproxy(), newproxy(), newproxy(), newproxy() end
    return out
end
M.traceLine = trace_line

-- ---- the map files -------------------------------------------------------------------------------------------------------
local function le(v)
    if v < 0 then v = v + 4294967296 end
    return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function bsp(ents, opts)
    opts = opts or {}
    local data = opts.data or ents
    local hdr = { "VBSP", le(20), le(1036), le(opts.len or #data), le(0), le(opts.fourcc or 0) }
    for _ = 2, 64 do hdr[#hdr + 1] = string.rep("\0", 16) end
    hdr[#hdr + 1] = le(1)
    return table.concat(hdr) .. data
end
local function ent(kv)
    local t = { "{\n" }
    for _, p in ipairs(kv) do t[#t + 1] = string.format('"%s" "%s"\n', p[1], p[2]) end
    t[#t + 1] = "}\n"
    return table.concat(t)
end
local WORLD = ent({ { "classname", "worldspawn" }, { "skyname", "sky_day01_01" } })
local SKYCAM = ent({ { "classname", "sky_camera" }, { "origin", "0 0 11244" }, { "scale", "16" } })
-- gm_construct_remaster_csm's real keyvalues (SADC/build/research/r099c/sunlit/sunmap_out.txt): the shadow straight down, the sun from pitch -50, yaw 34
local REMASTER = WORLD .. SKYCAM .. ent({ { "classname", "shadow_control" }, { "angles", "90 0 0" }, { "color", "187 187 187" }, { "distance", "1000" },
    { "disableallshadows", "0" } }) .. ent({ { "classname", "light_environment" }, { "origin", "891 149 -112" }, { "targetname", "sunsunsun" }, { "style", "34" },
    { "pitch", "-50" }, { "angles", "0 34 0" }, { "_light", "255 240 204 550" }, { "_ambient", "116 154 192 400" } }) ..
    ent({ { "classname", "env_sun" }, { "pitch", "-53" }, { "angles", "0 72 0" }, { "use_angles", "1" } })
local SC = ent({ { "classname", "shadow_control" }, { "angles", "90 0 0" }, { "color", "187 187 187" }, { "distance", "1000" } })
local MAPFILE = "maps/" .. game.GetMap() .. ".bsp"

-- ---- the addon -----------------------------------------------------------------------------------------------------------
GSA1 = nil
M.included = {}
M.gamefiles = { [MAPFILE] = bsp(REMASTER) }
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local S = GSA1 and GSA1.SunShadow
check(ok_load and S ~= nil and S.StepLight ~= nil, "the addon loads with the sun shadow (%s)", tostring(err_load))
if not (ok_load and S and S.StepLight) then return done() end
local logs = {}
local realLog = GSA1.Log
GSA1.Log = function(kind, fmt, ...)
    local okf, text = pcall(string.format, fmt, ...)
    logs[#logs + 1] = { kind = kind, text = okf and text or tostring(fmt) }
    return realLog(kind, fmt, ...)
end
local function logs_with(plain)
    local n, last = 0, nil
    for _, l in ipairs(logs) do
        if string.find(l.text, plain, 1, true) then n, last = n + 1, l.text end
    end
    return n, last
end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
GSA1.cv.prewarm:SetString("0")
local HAS = GSA1.CONVARS.gsa1_sunshadow_sunlit ~= nil
local function opt(name, v) if GSA1.CONVARS[name] then RunConsoleCommand(name, v) end end
local function sunlit(v) opt("gsa1_sunshadow_sunlit", v and "1" or "0") end

-- a frame as Garry's Mod runs it (feat_liveshadow_test.lua's frame(), the main view only); the receivers' vertices of the frame recorded
local verts, nverts, recording = {}, 0, false
for i = 1, 6 * 64 * 12 do verts[i] = { x = 0, y = 0, z = 0, c = 0 } end
do
    local mpos, mcol, madv = mesh.Position, mesh.Color, mesh.AdvanceVertex
    mesh.Position = function(v)
        if recording then
            nverts = nverts + 1
            local q = verts[nverts]
            if not q then q = {}; verts[nverts] = q end
            q.x, q.y, q.z = v.x, v.y, v.z
        end
        return mpos(v)
    end
    mesh.Color = function(r, g, b, a)
        if recording then
            local q = verts[nverts]
            if q then q.c = r end
        end
        return mcol(r, g, b, a)
    end
    mesh.AdvanceVertex = madv
end
local CMD = setmetatable({}, { __index = function() return function() return 0 end end })
local function frame(dt)
    dt = dt or 1 / 60
    M.dt = dt
    M.T = M.T + dt
    M.frameNo = M.frameNo + 1
    M.run_hook("Think")
    M.run_hook("CreateMove", CMD)
    local view = M.run_hook("CalcView", M.player, M.player:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
    M.view_origin = view and view.origin or M.player:EyePos()
    M.run_hook("PreRender")
    M.run_hook("PreDrawOpaqueRenderables", false, false, false)
    for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(1) end end
    nverts, recording = 0, true
    M.run_hook("PostDrawOpaqueRenderables", false, false, false)
    recording = false
    M.run_hook("PreDrawTranslucentRenderables", false, false)
    for _, e in ipairs(M.entities) do if not e.removed and e.DrawTranslucent then e:DrawTranslucent(1) end end
    M.run_hook("PostDrawTranslucentRenderables", false, false)
    M.run_hook("PostRender")
end
local function frames(n, dt) for _ = 1, n do frame(dt) end end
local function read_map(bytes)
    M.gamefiles[MAPFILE] = bytes
    S.light, S.lightMap, S.job = nil, nil, nil
    local n = 0
    while not S.lightMap and n < 400 do
        frame()
        n = n + 1
    end
    return S.light
end
read_map(bsp(REMASTER))
GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil, "Sonic spawned")
if not C then return done() end
local mc = M.mchars[C.id]
local function place(x, y, z)
    mc.pos.x, mc.pos.y, mc.pos.z = x, y, z or GZ
end
local function nearly(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end
-- the vertex colour of the frame's quads at a point of the ground (the triangles' own interpolation), nil where there is no quad
local function colour_at(x, y)
    for i = 1, nverts - 2, 3 do
        local a, b, c = verts[i], verts[i + 1], verts[i + 2]
        local d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        if d ~= 0 then
            local l1 = ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / d
            local l2 = ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / d
            local l3 = 1 - l1 - l2
            if l1 >= -1e-6 and l2 >= -1e-6 and l3 >= -1e-6 then return l1 * a.c + l2 * b.c + l3 * c.c end
        end
    end
    return nil
end
local function cmax()
    local m = 0
    for i = 1, nverts do if verts[i].c > m then m = verts[i].c end end
    return m
end
local FULL = 255 - 187       -- the map's colour 187 at the feet (the ground is under the feet: fade 1)
-- a long wall, x -300 .. -200, 400 HU tall: its slanted shade reaches x 78 (rise 1.4385 per HU towards the sun); straight down nothing is above that ground
local function wall() return { -300, -200, -3000, 3000, GZ, GZ + 400 } end
local function settle(n) frames(n or 30) end

-- 1. off ------------------------------------------------------------------------------------------------------------------
do
    sunlit(false)         -- (this one option alone gives 0.9.9b's drawing: the verifier's fail 4)
    W.boxes = { wall(), { 200, 260, -30, 30, GZ, GZ + 12 } }
    place(300, 0)
    settle(10)
    local h1, h2, count = 0, 0, 0
    local function walk(dx, n)
        for _ = 1, n do
            mc.pos.x = mc.pos.x + dx
            frame()
            for i = 1, nverts do
                local q = verts[i]
                local s = string.format("%.2f %.2f %.2f %.2f", q.x, q.y, q.z, q.c)
                for j = 1, #s do
                    h1 = (h1 * 31 + string.byte(s, j)) % 2147483647
                    h2 = (h2 * 131 + string.byte(s, j)) % 2147483629
                end
                count = count + 1
            end
        end
    end
    count_masks()
    walk(-3, 40)
    walk(-9, 40)
    walk(5, 30)
    local hash = string.format("%d %d %d", h1, h2, count)
    info("the walk's vertices with the option off: hash %s", hash)
    check(hash == "1042993107 1039523655 41472", "off: the same vertices as 0.9.9b in a walk over a low step and past a wall (hash %s, from build/release_0.9.9b)", hash)
    local others = 0
    for m, n in pairs(traceByMask) do if m ~= (MASK_SOLID or 33570827) then others = others + n end end
    check(others == 0 and traceN > 0, "off: only the grid's traces (%d), none of any other kind (%d)", traceN, others)
    -- (nor does it read what only the check needs)
    do
        local tl, read, last = M.traceLine, 0, nil
        M.traceLine = function(t)
            last = t.output
            if last then setmetatable(last, nil) end
            local r = tl(t)
            local n = r.HitNormal
            r.HitNormal = nil
            return setmetatable(r, { __index = function(q, k)
                if k == "HitNormal" then
                    read = read + 1
                    return n
                end
                return rawget(q, k)
            end })
        end
        walk(3, 30)
        M.traceLine = tl
        if last then setmetatable(last, nil) end
        check(read == 0, "off: the grid's traces read only what 0.9.9b read (the normal %d times)", read)
    end
    W.boxes = {}
end

-- 2. the option, the sun -----------------------------------------------------------------------------------------------------
do
    local d = GSA1.CONVARS.gsa1_sunshadow_sunlit
    check(d ~= nil and d.default == "1" and d.min == 0 and d.max == 1, "gsa1_sunshadow_sunlit: default 1, 0 .. 1 (%s)", d and d.default or "no such setting")
    check(GSA1.CONVARS.gsa1_sunshadow_flat == nil, "no second option: the grid's traces are 0.9.9b's")
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
    local at, atOn, atFp, atFollow, atFlat = nil, nil, nil, nil, false
    for i, c in ipairs(calls) do
        if c[3] == "gsa1_sunshadow_sunlit" then at = i end
        if c[3] == "gsa1_sunshadow_flat" then atFlat = true end
        if c[3] == "gsa1_sunshadow" then atOn = i end
        if c[3] == "gsa1_sunshadow_fp" then atFp = i end
        if c[3] == "gsa1_sunshadow_followers" then atFollow = i end
    end
    check(built and at and calls[at][1] == "CheckBox" and calls[at][2] == "Sun shadow only where the sun reaches" and atOn and atFollow and at > atOn and at < atFollow,
        "Options > G-SA1 > Rendering: the check box \"%s\" beside the other sun shadow controls (row %s, between %s and %s)", at and calls[at][2] or "no row",
        tostring(at), tostring(atOn), tostring(atFollow))
    check(built and not atFlat, "the page has no row for a second option")
    local L = read_map(bsp(REMASTER))
    local sun = L and L.sun
    check(L and L.source == "shadow_control" and nearly(L.dz, -1) and sun and sun.known and nearly(sun.dx, 0.5325, 1e-3) and nearly(sun.dy, 0.3592, 1e-3) and nearly(sun.dz, -0.7660, 1e-3),
        "gm_construct_remaster_csm: the shadow falls straight down (shadow_control 90 0 0), the sun's light travels along (%.3f, %.3f, %.3f): the map's own numbers, (0.533, 0.359, -0.766) in its light lumps",
        sun and sun.dx or 0, sun and sun.dy or 0, sun and sun.dz or 0)
    local nlog = logs_with("asked towards the map's baked sun, light_environment pitch -50, yaw 34")
    check(nlog >= 1, "the log's line for the map says towards where it asks")
    L = read_map(bsp(WORLD .. SC .. ent({ { "classname", "light_environment" }, { "pitch", "-60" }, { "angles", "0 0 0" } }) .. ent({ { "classname", "light_environment" },
        { "pitch", "-30" }, { "angles", "0 90 0" } })))
    check(L and L.sun and L.sun.known and nearly(L.sun.dz, -0.8660, 1e-3) and nearly(L.sun.dx, 0.5, 1e-3), "several light_environment: the first, as VRAD (%.3f, %.3f, %.3f)",
        L and L.sun and L.sun.dx or 0, L and L.sun and L.sun.dy or 0, L and L.sun and L.sun.dz or 0)
    L = read_map(bsp(WORLD .. SC .. ent({ { "classname", "light_environment" }, { "origin", "0 0 100" }, { "target", "aim" }, { "pitch", "-60" } }) ..
        ent({ { "classname", "info_target" }, { "targetname", "aim" }, { "origin", "100 0 0" } })))
    check(L and L.sun and L.sun.known and nearly(L.sun.dx, 0.7071, 1e-3) and nearly(L.sun.dz, -0.7071, 1e-3), "a \"target\": aimed at it, as VRAD (%.3f, %.3f, %.3f)", L and L.sun and L.sun.dx or 0,
        L and L.sun and L.sun.dy or 0, L and L.sun and L.sun.dz or 0)
    L = read_map(bsp(WORLD .. SC .. ent({ { "classname", "light_environment" }, { "pitch", "-45" }, { "angle", "90" }, { "angles", "0 0 0" } })))
    check(L and L.sun and L.sun.known and nearly(L.sun.dy, 0.7071, 1e-3) and nearly(L.sun.dx, 0, 1e-3), "an \"angle\" key is the yaw, as VRAD")
    L = read_map(bsp(WORLD .. SC .. ent({ { "classname", "light_environment" }, { "angle", "-2" } })))
    check(L and L.sun and L.sun.known and nearly(L.sun.dz, -1, 1e-3), "\"angle\" -2 is straight down, as VRAD")
    local cases = {
        { "no light_environment", WORLD .. SC, "no light_environment" },
        { "a sun with no light", WORLD .. SC .. ent({ { "classname", "light_environment" }, { "pitch", "-50" }, { "_light", "255 255 255 0" } }), "gives no light" },
        { "a horizontal sun", WORLD .. SC .. ent({ { "classname", "light_environment" }, { "pitch", "0" }, { "angles", "0 0 0" } }), "10 degrees" },
    }
    for _, c in ipairs(cases) do
        L = read_map(bsp(c[2]))
        check(L and L.sun and not L.sun.known and string.find(L.sun.text or "", c[3], 1, true) and string.find(L.sun.text or "", "drawn everywhere", 1, true),
            "%s: not asked, drawn everywhere (%s)", c[1], L and L.sun and L.sun.text or "no answer")
    end
    L = read_map(bsp(REMASTER, { fourcc = 4096 }))
    check(L and L.sun and not L.sun.known and string.find(L.sun.text or "", "LZMA", 1, true), "entities it cannot read: not asked, with the reason (%s)", L and L.sun and L.sun.text or "no answer")
end

-- 3. what it draws ------------------------------------------------------------------------------------------------------------
if not HAS then
    print("  (the options are not there: 0.9.9b; what follows needs them)")
    M.fails = M.fails + 1
    return done()
end
sunlit(true)
read_map(bsp(REMASTER))
do
    -- open sun: as without the option (the world changed under answers kept for S.SUN_KEEP s: a test's teleport of the walls)
    W.boxes = { wall() }
    S.ResetSun()
    place(400, 0)
    settle()
    local on = {}
    for i = 1, nverts do on[i] = verts[i].c end
    sunlit(false)
    settle(2)
    local same, n = true, nverts
    for i = 1, nverts do if not nearly(verts[i].c, on[i], 0.01) then same = false end end
    sunlit(true)
    settle()
    check(n == 384 and same and #on == 384 and nearly(cmax(), FULL, 0.01), "open sun: the same colours as with the option off (%d vertices, %.2f, full %d)", n, cmax(), FULL)
    -- the wall's slanted shade, nothing straight above: the mutation that asks along the shadow's own light sees sky here
    place(-100, 0)
    settle()
    check(nverts == 0 or cmax() == 0, "in the wall's slanted shade, with open sky straight above it: nothing drawn (%d vertices, %.2f; the sun's direction decides, not the shadow's)", nverts, cmax())
    frames(60 * 5 + 10)
    local n1, line = logs_with("the ground under the character is in the shade")
    check(n1 == 1, "the log says why, once (%s)", line or "no line")
    local ln = GSA1.SunShadowLine()
    check(string.find(ln, "in the shade", 1, true) ~= nil and string.find(ln, "pitch -50", 1, true) ~= nil, "the page says so too, and towards where it asks (%s)", ln)
    -- half in the sun: the line at x 78; the lattice's corners at x 64 (shade) and 96 (sun); the sunny part at full strength
    place(80, 0)
    settle()
    local bad, lowest, highest = 0, math.huge, -math.huge
    for i = 1, nverts do
        local q = verts[i]
        local want = FULL * math.max(math.min(0.5 + ((q.x - 64) / 32 - 0.5) * (S.SUN_STEEP or 1), 1), 0)     -- (0.9.9d: S.SUN_STEEP; 0.9.9c's whole cell with 1)
        if not nearly(q.c, want, 0.05) then bad = bad + 1 end
        lowest, highest = math.min(lowest, q.c), math.max(highest, q.c)
    end
    check(nverts == 384 and bad == 0 and nearly(lowest, 0, 0.01) and nearly(highest, FULL, 0.01), "half in the sun: full strength on the sunny side, none in the shade, a fade around the middle of the cell (x 64 to 96) between them "
        .. "(%d of %d vertices off, %.2f .. %.2f)", bad, nverts, lowest, highest)
    -- a roof over all of it
    W.boxes = { { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220 } }
    S.ResetSun()
    place(400, 0)
    settle()
    check(nverts == 0 or cmax() == 0, "under a roof: nothing drawn (%.2f)", cmax())
    -- a window and water let the sun through, as VRAD; a grate too; nodraw does not (VRAD's blockers: brushes of MASK_OPAQUE, READ)
    for _, c in ipairs({ { "a window", CONTENTS_WINDOW }, { "water", CONTENTS_WATER }, { "a grate", CONTENTS_GRATE } }) do
        W.boxes = { { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220, contents = c[2] } }
        S.ResetSun()
        settle()
        check(nearly(cmax(), FULL, 0.01), "under %s: drawn, the sun comes through (%.2f)", c[1], cmax())
    end
    W.boxes = { { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220, nodraw = true } }
    S.ResetSun()
    settle()
    check(nverts == 0 or cmax() == 0, "under nodraw: nothing drawn, VRAD's rays stop on it too (%.2f)", cmax())
    -- no sky over the ground: a closed box of a map (no sky plane, a ceiling that is no sky): the sun reaches none of it
    W.boxes = { { -5000, 5000, -5000, 5000, 3000, 3100 } }
    local sky0 = W.sky
    W.sky = nil
    S.ResetSun()
    settle()
    check(nverts == 0 or cmax() == 0, "a ceiling and no sky: nothing drawn (%.2f)", cmax())
    -- a ray that hits nothing at all counts as seen, as VRAD's
    W.boxes = {}
    S.ResetSun()
    settle()
    check(nearly(cmax(), FULL, 0.01), "a ray that hits nothing: drawn (%.2f)", cmax())
    W.sky = sky0
    -- on the wall's sunny side, close to it: the corners inside the wall have no answer and do not count, the ground stays lit up to the wall
    W.boxes = { wall() }
    S.ResetSun()
    place(-340, 0)
    settle()
    local dim = 0
    for i = 1, nverts do
        if verts[i].x < -300 and verts[i].c < FULL - 0.01 then dim = dim + 1 end
    end
    check(nverts > 0 and dim == 0 and nearly(cmax(), FULL, 0.01), "the wall's sunny side, right up to the wall: full strength, a corner inside the wall does not count (%d dimmed of %d)", dim, nverts)
    -- ground turned away from the sun: a slope of 53 degrees falling away from it (the sun stands at 50), the ledge rule still lets its cells be; straight down it sees the sky
    W.boxes = {}
    W.plane = { 0.662, 0.446, 0.6018, 0.6018 * GZ }
    S.ResetSun()
    place(0, 0)
    sunlit(false)
    settle(3)
    local slopeOff = cmax()
    sunlit(true)
    settle()
    local slopeOn = nverts == 0 and 0 or cmax()
    W.plane = { 0, 0, 1, GZ }
    check(slopeOff > 10 and slopeOn == 0, "ground turned away from the sun: nothing drawn (%.2f; with the option off %.2f), as VRAD gives it no sun", slopeOn, slopeOff)
    -- a trench too narrow for any corner of the lattice: each corner lies inside the walls, so the points ask with their own rays
    W.boxes = { { -300, 2, -300, 300, GZ, GZ + 100 }, { 30, 300, -300, 300, GZ, GZ + 100 }, { 2, 30, -300, 2, GZ, GZ + 100 }, { 2, 30, 30, 300, GZ, GZ + 100 } }
    read_map(bsp(WORLD .. SKYCAM .. SC .. ent({ { "classname", "light_environment" }, { "pitch", "-87" }, { "angles", "0 34 0" } })))     -- (a high sun, to see out of it)
    S.ResetSun()
    place(16, 16)
    settle()
    local openTrench = nverts > 0 and cmax() or 0
    W.boxes[5] = { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220 }
    S.ResetSun()
    settle()
    local roofedTrench = nverts == 0 and 0 or cmax()
    check(nearly(openTrench, FULL, 0.01) and roofedTrench == 0, "a trench with every corner of the lattice inside its walls: the points' own rays, open %.2f, roofed %.2f", openTrench, roofedTrench)
    W.boxes = {}
    read_map(bsp(REMASTER))
    place(0, 0)
    -- a new map's light empties what was asked for the old one, at once: this ground in the wall's shade, then a sun from the other side
    W.boxes = { wall() }
    S.ResetSun()
    place(-100, 0)
    settle()
    local shadeOld = nverts == 0 and 0 or cmax()
    read_map(bsp(WORLD .. SKYCAM .. SC .. ent({ { "classname", "light_environment" }, { "pitch", "-50" }, { "angles", "0 214 0" } })))
    frames(2)
    local sunNew = cmax()
    read_map(bsp(REMASTER))
    check(shadeOld == 0 and nearly(sunNew, FULL, 0.01), "a new sun on a new map: the answers kept for the old one are gone (%.2f, now %.2f)", shadeOld, sunNew)
    W.boxes = {}
    S.ResetSun()
    -- two levels at the same x, y: a roof terrace in the sun above shaded ground under it; each asks about its own surface
    local terrace = { -2000, 2000, -2000, 2000, GZ + 150, GZ + 170 }
    W.boxes = { terrace }
    S.ResetSun()
    place(0, 0, GZ + 170)
    settle()
    local top = cmax()
    place(0, 0, GZ)
    settle()
    local under = nverts == 0 and 0 or cmax()
    check(nearly(top, FULL, 0.01) and under == 0, "the same x, y on two levels: on the terrace in the sun %.2f, on the ground under it %.2f", top, under)
    -- each level keeps its own corners: the second level asks a lattice's worth of rays, not one for every point of the grid
    place(0, 0, GZ + 170)
    S.ResetSun()
    settle(5)
    count_masks()
    place(0, 0, GZ)
    settle(5)
    local secondLevel = traceByMask[MASK_OPAQUE or 16513] or 0
    check(secondLevel > 0 and secondLevel <= 36, "the second level on one x, y: its own corners, at most 36 rays (%d)", secondLevel)
    W.boxes = {}
    S.ResetSun()
    place(0, 0)
    -- a map with no sun to ask: as off, no sun trace
    read_map(bsp(WORLD .. SC))
    W.boxes = { { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220 } }
    settle(4)
    count_masks()
    settle()
    check(nearly(cmax(), FULL, 0.01) and not traceByMask[MASK_OPAQUE or 16513], "no light_environment: drawn under a roof as 0.9.9b, no trace of the check (%.2f)", cmax())
    local ln2 = GSA1.SunShadowLine()
    check(string.find(ln2, "no light_environment", 1, true) ~= nil, "the page says why it does not ask (%s)", ln2)
    read_map(bsp(REMASTER))
    S.ResetSun()
    settle()
    check(nverts == 0 or cmax() == 0, "the same roof on a map with a sun: nothing drawn (%.2f)", cmax())
    -- the masks
    count_masks()
    S.ResetSun()
    settle(20)
    check((traceByMask[MASK_OPAQUE or 16513] or 0) > 0, "the ray to the sun is MASK_OPAQUE, VRAD's mask (%d traces)", traceByMask[MASK_OPAQUE or 16513] or 0)
    -- the log's samples for a later round: the ray's answer beside the engine's lighting, a handful per map; a failure there stops nothing
    do
        local probes = function() return (logs_with("sun check sample:")) end
        local n0 = probes()
        W.boxes = {}
        S.ResetSun()
        S.sunfield.probe[0], S.sunfield.probe[1], S.sunfield.probe.next = 0, 0, 0
        local gsc = render.GetSurfaceColor
        render.GetSurfaceColor = function() return Vector(0.25, 0.5, 0.75) end
        local tick = 0
        for _ = 1, 60 * 60 do
            tick = tick + 1
            if tick % 40 == 0 then
                mc.pos.x = mc.pos.x + 300      -- (new corners, a ray each)
                W.boxes = tick % 80 == 0 and { { -90000, 90000, -90000, 90000, GZ + 200, GZ + 220 } } or {}
            end
            frame()
        end
        local n1, line = logs_with("sun check sample:")
        check(n1 - n0 >= 2 and n1 - n0 <= 2 * S.PROBE_EACH and string.find(line or "", "render.ComputeLighting towards the sun", 1, true) ~= nil and string.find(line or "", "(0.250 0.500 0.750)", 1, true) ~= nil,
            "the log gets the engine's lighting beside the ray's answer, at most %d lines a map (%d; %s)", 2 * S.PROBE_EACH, n1 - n0, line or "none")
        render.GetSurfaceColor = function() error("a test's surface colour error") end
        S.sunfield.probe[0], S.sunfield.probe[1], S.sunfield.probe.next = 0, 0, 0
        W.boxes = {}
        S.ResetSun()
        place(0, 0)
        settle(20)
        render.GetSurfaceColor = gsc
        check(not S.broken and nearly(cmax(), FULL, 0.01) and S.sunfield.probe[1] == S.PROBE_EACH, "an error in the samples stops only the samples (%s)", tostring(S.broken))
        W.boxes = { { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220 } }
        S.ResetSun()
        settle()
    end
    -- off again: the roof no longer matters, at once
    sunlit(false)
    settle(2)
    check(nearly(cmax(), FULL, 0.01), "the option off: drawn under the roof at once, as 0.9.9b (%.2f)", cmax())
    sunlit(true)
    settle()
    check(nverts == 0 or cmax() == 0, "on again: nothing, with no flash in between (%.2f)", cmax())
    -- first person: without gsa1_sunshadow_fp no shadow of yours at all; with it the same rule, in the shade and in the sun
    local fpOld = GSA1.FirstPerson
    GSA1.FirstPerson = function() return true end
    RunConsoleCommand("gsa1_sunshadow_fp", "0")
    W.boxes = {}
    S.ResetSun()
    settle(5)
    local fp0 = nverts
    RunConsoleCommand("gsa1_sunshadow_fp", "1")
    settle()
    local fpSun = nverts > 0 and cmax() or 0
    W.boxes = { { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220 } }
    S.ResetSun()
    settle()
    local fpShade = nverts == 0 and 0 or cmax()
    RunConsoleCommand("gsa1_sunshadow_fp", "0")
    GSA1.FirstPerson = fpOld
    check(fp0 == 0 and nearly(fpSun, FULL, 0.01) and fpShade == 0 and not S.broken, "first person: nothing without the option (%d vertices); with it in the sun %.2f, under a roof %.2f", fp0, fpSun, fpShade)
    W.boxes = {}
    S.ResetSun()
    settle(5)
end

-- 4. no pop --------------------------------------------------------------------------------------------------------------------
do
    W.boxes = { wall() }
    S.ResetSun()
    -- the sampled points of the ground, fixed in the world
    local function sweep(speed, name, limit)
        place(-40, 0)
        S.ResetSun()
        settle(20)
        local dx = speed / 60
        local last = {}
        local worst, wx = 0, 0
        for _ = 1, math.floor(300 / dx) do
            mc.pos.x = mc.pos.x + dx
            frame()
            for x = 40, 150, 11 do
                for y = -20, 20, 20 do
                    local key = x * 1000 + y
                    local c = colour_at(x + 0.5, y + 0.5)
                    if c and last[key] then
                        local d = math.abs(c - last[key]) / FULL
                        if d > worst then worst, wx = d, x end
                    end
                    last[key] = c
                end
            end
        end
        info("%s (%d HU/s) across the shade line: a fixed point of the ground changed by at most %.3f of the full darkness in a frame (at x %d)", name, speed, worst, wx)
        check(worst <= limit, "%s across the shade line: no pop, a fixed point of the ground changes by at most %.3f of the shadow's darkness in a frame (%.3f)", name, limit, worst)
    end
    sweep(120, "walking", 0.10)
    sweep(400, "running", 0.10)
    sweep(1500, "at speed", 0.10)
    -- a crease in the ground whose far side turns from the sun: the one place where the moving grid shows, the line sits at the nearest grid points: said here, by number, and bounded by being one cell wide
    do
        W.boxes = {}
        W.height = function(x)
            if x < 300 then return GZ, 0, 0 end
            return GZ - 1.6 * (x - 300), -1.6, 0
        end
        place(150, 0)
        S.ResetSun()
        settle(20)
        local last, worst, wx, far = {}, 0, 0, 0
        for _ = 1, 100 do
            mc.pos.x = mc.pos.x + 2
            frame()
            for x = 240, 340, 7 do
                local c = colour_at(x + 0.5, 0.5)
                if c and last[x] then
                    local d = math.abs(c - last[x]) / FULL
                    if d > worst then worst, wx = d, x end
                    -- (further than a cell of the grid from the crease nothing jumps)
                    if math.abs(x - 300) > 14 and d > far then far = d end
                end
                last[x] = c
            end
        end
        W.height = nil
        info("walking over a crease whose far side turns from the sun: a fixed point changes by at most %.3f of the shadow in a frame (at x %d, the crease at 300), %.3f further than a cell from it", worst, wx, far)
        check(far <= 0.10, "a crease whose far side turns from the sun: further than a grid cell from it no jump (%.3f; beside it %.3f)", far, worst)
    end
    -- something that moves into the sun's way: not at once, and it does arrive (S.SUN_KEEP)
    W.boxes = {}
    S.ResetSun()
    place(400, 0)
    settle()
    W.boxes = { { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220 } }
    local steps, before, biggest, seen0 = 0, cmax(), 0, false
    for _ = 1, 60 * math.floor(S.SUN_KEEP + 2) do
        frame()
        local c = nverts == 0 and 0 or cmax()
        biggest = math.max(biggest, math.abs(c - before))
        before = c
        if c == 0 then seen0 = true end
    end
    check(seen0 and biggest <= FULL * ((1 / 60) / 0.2), "a roof that arrives: the shadow fades out, at most %.1f a frame (%.1f), within the time an answer is kept", FULL * ((1 / 60) / 0.2), biggest)
    -- the first frame of a shadow in the shade: not lit for a moment. A new character's first grid takes the answer at once
    W.boxes = { wall() }
    S.ResetSun()
    place(-100, 0)
    S.grid.sunWas = false
    frame()
    check(nverts == 0 or cmax() == 0, "a shadow's first frame in the shade is already dark (%.2f)", cmax())
    -- the same after a teleport: a place not asked before has its answer at once
    S.ResetSun()
    place(500, 0)
    settle(20)
    local bright = cmax()
    place(-100, 40)
    frame()
    check(bright > 60 and (nverts == 0 or cmax() == 0), "a teleport from the sun into the shade: dark at once, no flash of the old value (%.2f, before it %.2f)", cmax(), bright)
    W.boxes = {}
    S.ResetSun()
end

-- 5. followers -----------------------------------------------------------------------------------------------------------------
local Fo = GSA1.Followers
local FS = S.followers
hook.Add("Think", "feat_sunlit_levels", function() Fo.UpdateLevels(SysTime()) end)
local uid = 0
local function follower(x, y, lod)
    uid = uid + 1
    local pos = Vector(x, y, GZ)
    local id = G.Create(0, pos, 0, 0, 0)
    local ent2 = ents.CreateClientside("gsa1_render")
    local F = { id = id, kind = 0, name = "sonic", title = "Sonic", uid = uid, info = G.CharacterInfo(0), state = {}, batches = { count = 0 }, batchGen = 0, mats = {}, static = {},
                matsDirty = true, ent = ent2, drawPos = pos, drawYaw = 0, lod = lod or 1, interp = (lod or 1) == 1, renderGen = 1, follower = true }
    G.Batches(id, F.batches)
    ent2.char = F
    Fo.list[#Fo.list + 1] = F
    Fo.byId[id] = F
    return F
end
local function drop(F)
    F.removed = true
    for i = #Fo.list, 1, -1 do if Fo.list[i] == F then table.remove(Fo.list, i) end end
    Fo.byId[F.id] = nil
    F.ent:Remove()
end
-- the colours of the frame by the nearest of the given places
local function by_home(homes)
    local out = {}
    for i = 1, nverts do
        local q = verts[i]
        local best, bd = nil, math.huge
        for j, h in ipairs(homes) do
            local d = (q.x - h[1]) ^ 2 + (q.y - h[2]) ^ 2
            if d < bd then best, bd = j, d end
        end
        out[best] = math.max(out[best] or 0, q.c)
    end
    return out
end
do
    W.boxes = { wall() }
    S.ResetSun()
    place(400, 0)
    local inShade = follower(-100, 400)
    local inSun = follower(500, 400)
    settle(30)
    local c = by_home({ { 400, 0 }, { -100, 400 }, { 500, 400 } })
    check(nearly(c[1] or 0, FULL, 0.01) and (c[2] or 0) == 0 and nearly(c[3] or 0, FULL, 0.01), "followers too: yours in the sun %.2f, one in the wall's shade %.2f, one in the sun %.2f", c[1] or 0, c[2] or 0, c[3] or 0)
    -- half in the sun, on its coarser grid
    drop(inShade)
    drop(inSun)
    frames(12)
    local half = follower(80, 400)
    settle(30)
    local lo, hi, bad = math.huge, -math.huge, 0
    for i = 1, nverts do
        local q = verts[i]
        if q.y > 250 then
            local want = FULL * math.max(math.min(0.5 + ((q.x - 64) / 32 - 0.5) * (S.SUN_STEEP or 1), 1), 0)     -- (0.9.9d: S.SUN_STEEP; 0.9.9c's whole cell with 1)
            if not nearly(q.c, want, 0.05) then bad = bad + 1 end
            lo, hi = math.min(lo, q.c), math.max(hi, q.c)
        end
    end
    check(bad == 0 and nearly(lo, 0, 0.01) and nearly(hi, FULL, 0.01), "a follower half in the sun: the same field on its own grid (%d off, %.2f .. %.2f)", bad, lo, hi)
    drop(half)
    frames(12)
    W.boxes = {}
    S.ResetSun()
end

-- 5b. the sunny top of a ledge keeps its shadow ------------------------------------------------------------------------------------
-- (the verifier's fail 1: a corner of the lattice took its ground's normal from the grid's neighbours, which can lie on another level; it looked turned from the sun and read 0 with no ray; the renewal
-- comes round in the grid's order, so it stayed)
do
    RunConsoleCommand("gsa1_sunshadow_followers", "0")
    local function top(h)
        local n, lo, sum = 0, math.huge, 0
        for i = 1, nverts do
            local q = verts[i]
            if q.z > GZ + h - 2 then n, lo, sum = n + 1, math.min(lo, q.c), sum + q.c end
        end
        return n, n > 0 and lo / FULL or -1, n > 0 and sum / n / FULL or -1
    end
    -- stands for twice the time an answer is kept: all corners have been asked again from where it stands
    local function stays(name, h)
        local nmin, lomin, meanmin = math.huge, 1, 1
        for _ = 1, 5 do
            frames(120)
            local n, lo, mean = top(h)
            nmin, lomin, meanmin = math.min(nmin, n), math.min(lomin, lo), math.min(meanmin, mean)
        end
        check(nmin >= 24 and lomin >= 0.999, "%s: full strength for 10 s (mean %.2f, lowest %.2f, %d vertices on top at least)", name, meanmin, lomin, nmin)
    end
    for _, h in ipairs({ 24, 40, 48, 64, 96, 200 }) do
        W.boxes, W.plane = { { -2000, 0, -2000, 2000, GZ, GZ + h } }, { 0, 0, 1, GZ }
        place(-400, 0, GZ + h)
        S.ResetSun()
        frames(30)
        while mc.pos.x < -30 do
            mc.pos.x = mc.pos.x + 4
            frame()
        end
        local _, lo0 = top(h)
        check(lo0 >= 0.999, "a ledge %d HU high, walking up to the edge that falls away from the sun: full strength on arrival (lowest %.2f)", h, lo0)
        stays(string.format("a ledge %d HU high, standing 30 HU from the edge that falls away from the sun, open sky over all of it", h), h)
    end
    -- the same edge along the other axis
    W.boxes = { { -2000, 2000, -2000, 0, GZ, GZ + 96 } }
    place(0, -400, GZ + 96)
    S.ResetSun()
    frames(30)
    while mc.pos.y < -30 do
        mc.pos.y = mc.pos.y + 4
        frame()
    end
    stays("a ledge 96 HU high, the edge along the other axis", 96)
    -- arriving there with empty answers: the worst order of asking
    W.boxes = { { -2000, 0, -2000, 2000, GZ, GZ + 96 } }
    place(-20, 0, GZ + 96)
    frames(30)
    S.ResetSun()
    stays("a ledge 96 HU high, 20 HU from the edge, all answers asked from where it stands", 96)
    -- a walkway, both edges
    W.boxes = { { -2000, 2000, -40, 40, GZ + 180, GZ + 200 } }
    place(0, 0, GZ + 200)
    S.ResetSun()
    frames(60)
    stays("a walkway 80 HU wide, 200 HU up", 200)
    -- the edge towards the sun, and the low ground beside a ledge between it and the sun: the shade under it stays shade
    W.boxes = { { 0, 2000, -2000, 2000, GZ, GZ + 96 } }
    place(30, 0, GZ + 96)
    S.ResetSun()
    frames(30)
    stays("a ledge 96 HU high, the edge towards the sun", 96)
    W.boxes = { { -2000, 0, -2000, 2000, GZ, GZ + 96 } }
    place(30, 0, GZ)
    S.ResetSun()
    local worst = 0
    for _ = 1, 600 do
        frame()
        for i = 1, nverts do
            local q = verts[i]
            -- (the ledge's slanted shade reaches 61 HU from its foot for a ray from 8 HU up; the lattice's corners at x 32 lie in it, those at x 64 do not, so the fade runs from x 32 to x 64)
            if q.z < GZ + 2 and q.x > 1 and q.x < 31 and q.c > worst then worst = q.c end
        end
    end
    check(worst == 0, "the low ground in the slanted shade of that ledge stays dark for 10 s (%.2f)", worst)
    -- a follower at such an edge
    W.boxes = { { -2000, 0, -2000, 2000, GZ, GZ + 96 } }
    place(-500, 0, GZ + 96)
    RunConsoleCommand("gsa1_sunshadow_followers", "1")
    S.ResetSun()
    local Fe = follower(-30, 0)
    Fe.drawPos.z = GZ + 96
    frames(20)
    stays("a follower 30 HU from that edge", 96)
    drop(Fe)
    frames(12)
    RunConsoleCommand("gsa1_sunshadow_followers", "0")
    -- ground turned from the sun beside a sunny surface: that answer stays with the surface. The shadow's own light slants into the side of a step that the sun cannot see; the step's top, in the same height
    -- band of the lattice, stays lit
    read_map(bsp(WORLD .. SKYCAM .. ent({ { "classname", "shadow_control" }, { "angles", "60 0 0" }, { "color", "187 187 187" }, { "distance", "1000" } }) ..
        ent({ { "classname", "light_environment" }, { "pitch", "-50" }, { "angles", "0 180 0" } })))
    W.boxes = { { 0, 2000, -2000, 2000, GZ, -100 } }
    place(12, 0, -100)
    S.ResetSun()
    frames(30)
    local gg = S.grid
    local onSide = 0
    for k = 1, gg.n * gg.n do
        if gg.hit[k] and gg.wz[k] < -102 and gg.wz[k] >= -128 and math.abs(gg.wx[k]) < 1 then onSide = onSide + 1 end
    end
    check(onSide > 0, "(the scene: the grid's rays hit the step's side in the top's height band: %d points)", onSide)
    local n2, lomin = 0, 1
    for _ = 1, 5 do
        frames(120)
        for i = 1, nverts do
            local q = verts[i]
            if q.z > -102 then
                n2 = n2 + 1
                lomin = math.min(lomin, q.c / FULL)
            end
        end
    end
    -- (under 1: the shadow's own fade with the depth along a slanted light, 24 HU of 1000 at the box's edge)
    check(n2 > 0 and lomin >= 0.95, "the side of a step turned from the sun does not answer for the step's sunny top (lowest %.2f of %d)", lomin, n2)
    read_map(bsp(REMASTER))
    -- a true slope turned from the sun is dark at once, standing or walking, and its corners ask no ray for it
    W.boxes, W.plane = {}, { 0.662, 0.446, 0.6018, 0.6018 * GZ }
    place(0, 0)
    S.ResetSun()
    settle(3)
    count_masks()
    settle(200)
    local raysSlope = traceByMask[MASK_OPAQUE or 16513] or 0
    W.plane = { 0, 0, 1, GZ }
    check(raysSlope == 0, "a slope turned from the sun asks no ray for it (%d)", raysSlope)
    -- a slope that just faces the sun: as baked, little sun, so a weak shadow, going smoothly to none
    do
        local function slope_value(tilt)
            -- a plane falling away from the sun by tilt degrees from where its normal faces the sun head on
            local nx, ny = 0.8295, 0.5597      -- (the sun's way on the ground, unit)
            local a = math.rad(tilt)
            local p = { nx * math.sin(a), ny * math.sin(a), math.cos(a), math.cos(a) * GZ }
            W.plane = p
            S.ResetSun()
            settle(20)
            return nverts > 0 and cmax() / FULL or 0, -(p[1] * 0.5325 + p[2] * 0.3592 + p[3] * -0.7660)
        end
        local v1, f1 = slope_value(46)
        local v2, f2 = slope_value(48)
        local v3, f3 = slope_value(30)
        W.plane = { 0, 0, 1, GZ }
        info("a slope that nearly turns from the sun: facing %.3f: %.2f; facing %.3f: %.2f; facing %.3f: %.2f", f1, v1, f2, v2, f3, v3)
        check(nearly(v3, 1, 0.01) and nearly(v1, f1 / 0.1, 0.02) and nearly(v2, f2 / 0.1, 0.02) and v2 > 0, "a slope nearly turned from the sun: a weaker shadow the less it faces, not a step from full to none (%.2f at facing %.3f, %.2f at %.3f, %.2f at %.3f)", v3, f3, v1, f1, v2, f2)
    end
    -- the option goes on over ground turned from the sun: dark at once, the grid's normals are asked for at that moment, not 0.25 s later
    W.plane = { 0.662, 0.446, 0.6018, 0.6018 * GZ }
    place(0, 0)
    sunlit(false)
    settle(40)
    local offMax = cmax()
    sunlit(true)
    frame()
    local onFirst = nverts == 0 and 0 or cmax()
    W.plane = { 0, 0, 1, GZ }
    S.ResetSun()
    settle(20)
    check(offMax > 10 and onFirst == 0, "the option going on over ground turned from the sun: dark in the first frame (%.2f; off %.2f)", onFirst, offMax)
    -- a trace that gives no normal: flat ground, no error
    local tl = M.traceLine
    for _, mode in ipairs({ "none", "zero" }) do
        local rayStart
        M.traceLine = function(t)
            if (t.mask or 0) == (MASK_OPAQUE or 16513) then rayStart = t.start.z end
            local r = tl(t)
            if mode == "none" then r.HitNormal = nil else r.HitNormal = Vector(0, 0, 0) end
            return r
        end
        W.boxes = {}
        place(0, 0)
        S.ResetSun()
        settle(20)
        check(not S.broken and nearly(cmax(), FULL, 0.01) and rayStart and nearly(rayStart, GZ + S.LIFT + S.SUN_LIFT, 0.01), "a trace with no normal (%s): counts as flat ground, no error (%.2f, a ray from %.2f over the ground, %s)", mode, cmax(), rayStart and rayStart - GZ or -1, tostring(S.broken))
    end
    M.traceLine = tl
    W.boxes = {}
    place(0, 0)
    S.ResetSun()
    settle(10)
end

-- 5c. no flash when the corners a frame are spent ---------------------------------------------------------------------------------
-- (the verifier's fail 2: a point with no answer kept g.sun[k], which started at 1 or held an old place's value)
do
    local ROOF = { -3000, 3000, -3000, 3000, GZ + 200, GZ + 220 }
    local function lit_in_shade(n, xmax)
        local bad, worst, framesBad = 0, 0, 0
        for _ = 1, n do
            frame()
            local here = 0
            for i = 1, nverts do
                local q = verts[i]
                if q.c > 0.5 and (not xmax or q.x < xmax) then
                    here = here + 1
                    worst = math.max(worst, q.c)
                end
            end
            if here > 0 then framesBad, bad = framesBad + 1, bad + here end
        end
        return framesBad, bad, worst
    end
    -- when all shadows are whole and at full strength: the frames it took
    local function whole(wanted, limit)
        for f = 1, limit do
            frame()
            local full = 0
            for i = 1, nverts do if verts[i].c >= FULL - 0.01 then full = full + 1 end end
            if nverts == wanted and full == nverts then return f end
        end
        return math.huge
    end
    local function others(fs)
        for i = #fs, 1, -1 do
            drop(fs[i])
            fs[i] = nil
        end
        frames(12)
    end
    local function want(n) return 384 + n * 36 * 6 end
    for _, n in ipairs({ 3, 8 }) do
        -- followers appearing at once on ground no one has asked about, you in the sun far away
        W.boxes = {}
        place(5000, 5000)
        S.ResetSun()
        RunConsoleCommand("gsa1_sunshadow_followers", tostring(n))
        frames(5)
        W.boxes = { ROOF }
        S.ResetSun()
        local fs = {}
        for i = 1, n do fs[i] = follower(120 * math.cos(i), 120 * math.sin(i)) end
        local fb, vb, worst = lit_in_shade(60, 3000)
        check(fb == 0, "%d followers appearing at once under a roof: no frame with a shadow in the shade (%d frames, %d vertices, darkest %.1f of %d)", n, fb, vb, worst, FULL)
        others(fs)
        -- the same in the sun: they do come
        W.boxes = {}
        S.ResetSun()
        for i = 1, n do fs[i] = follower(5000 + 300 * math.cos(i), 5000 + 300 * math.sin(i)) end
        local f1 = whole(want(n), 40)
        info("%d followers appearing in the sun: all shadows whole and full after %s frames", n, tostring(f1))
        check(f1 <= 20, "%d followers appearing in the sun: all there, full, within 20 frames (%s)", n, tostring(f1))
        -- everyone teleported from the sun under a roof nobody has asked about: nothing lit there, not for a frame
        W.boxes = { { 20000, 26000, -3000, 3000, GZ + 200, GZ + 220 } }
        place(0, 0)
        for i = 1, n do
            fs[i].drawPos.x = 400 * math.cos(i)
            fs[i].drawPos.y = 400 * math.sin(i)
        end
        S.ResetSun()
        frames(40)
        local before = cmax()
        place(23000, 0)
        for i = 1, n do fs[i].drawPos.x = fs[i].drawPos.x + 23000 end
        fb, vb, worst = lit_in_shade(30)
        check(before >= FULL - 0.01 and fb == 0, "you and %d followers teleported from the sun under a roof: no frame with a shadow in the shade (%d frames, %d vertices, darkest %.1f; before it %.1f)", n, fb, vb, worst, before)
        -- teleported from the sun into the sun elsewhere: there again within a few frames, you at once
        W.boxes = {}
        place(0, 0)
        for i = 1, n do
            fs[i].drawPos.x = 400 * math.cos(i)
            fs[i].drawPos.y = 400 * math.sin(i)
        end
        S.ResetSun()
        frames(40)
        place(40000, 0)
        for i = 1, n do fs[i].drawPos.x = fs[i].drawPos.x + 40000 end
        local f2 = whole(want(n), 40)
        info("you and %d followers teleported in the sun: all whole and full after %s frames", n, tostring(f2))
        check(f2 <= 8, "you and %d followers teleported in the sun: all back at full within 8 frames (%s)", n, tostring(f2))
        others(fs)
        RunConsoleCommand("gsa1_sunshadow_followers", "0")
    end
    -- a tall character: its box has more corners than a frame's budget
    local save = C.info
    for _, h in ipairs({ 80, 110 }) do
        C.info = setmetatable({ height = h }, { __index = save })
        W.boxes = { { 20000, 26000, -3000, 3000, GZ + 200, GZ + 220 } }
        place(0, 0)
        S.ResetSun()
        frames(40)
        local before = cmax()
        place(23000, 0)
        local fb, vb, worst = lit_in_shade(20)
        check(before >= FULL - 0.01 and fb == 0, "a character of height %d teleported from the sun under a roof: nothing lit (%d frames, %d vertices, darkest %.1f; before it %.1f)", h, fb, vb, worst, before)
        W.boxes = {}
        place(50000, 0)
        S.ResetSun()
        frames(5)
        check(nearly(cmax(), FULL, 0.01), "a character of height %d in the sun: full after a few frames (%.2f)", h, cmax())
        place(0, 0)
    end
    C.info = save
    -- a small budget, you alone, in the shade
    W.boxes = { ROOF }
    place(5000, 0)
    S.ResetSun()
    frames(5)
    local you = S.SUN_YOU
    S.SUN_YOU = 4
    place(0, 0)
    local fb = lit_in_shade(40)
    S.SUN_YOU = you
    check(fb == 0, "a budget of 4 corners a frame, teleported into the shade: no frame lit (%d)", fb)
    -- a follower's place taken again, near where the last one stood in the sun, a roof since then, a small budget: what the place knew of the last one does not count
    do
        W.boxes = {}
        place(5000, 5000)
        RunConsoleCommand("gsa1_sunshadow_followers", "1")
        S.ResetSun()
        local F1 = follower(0, 0)
        frames(20)
        local was = cmax()
        drop(F1)
        frames(12)
        W.boxes = { ROOF }
        S.ResetSun()
        local them = S.SUN_THEM
        S.SUN_THEM = 2
        local F2 = follower(10, 10)
        local fb2, vb2 = lit_in_shade(40, 3000)
        S.SUN_THEM = them
        check(was >= FULL - 0.01 and fb2 == 0, "a follower's place taken again near the last one's sun, a roof since then: no frame lit (%d frames, %d vertices)", fb2, vb2)
        drop(F2)
        frames(12)
        RunConsoleCommand("gsa1_sunshadow_followers", "0")
    end
    -- off, a roof comes, on again with a small budget: what the shadow knew from before does not count
    W.boxes = {}
    place(0, 0)
    S.ResetSun()
    frames(20)
    sunlit(false)
    frames(3)
    W.boxes = { ROOF }
    S.ResetSun()
    S.SUN_YOU = 2
    sunlit(true)
    fb = lit_in_shade(30)
    S.SUN_YOU = you
    check(fb == 0, "off, a roof, on again with a budget of 2: no frame lit (%d)", fb)
    -- on the move, the budget spent, in open sun: the points whose four corners are not asked yet keep what they knew, no holes in the shadow
    W.boxes = {}
    place(0, 0)
    S.ResetSun()
    frames(20)
    S.SUN_YOU = 2
    local lo = math.huge
    for _ = 1, 40 do
        mc.pos.x = mc.pos.x + 25
        frame()
        for i = 1, nverts do lo = math.min(lo, verts[i].c) end
    end
    S.SUN_YOU = you
    check(lo >= FULL - 0.01, "at speed in open sun with the budget spent: no vertex drops (lowest %.2f of %d)", lo, FULL)
    W.boxes = {}
    place(0, 0)
    S.ResetSun()
    settle(5)
end

-- 5d. no notches in full sun --------------------------------------------------------------------------------------------------------
-- (099c's second verifier: on maps whose shadow is slanted another way than the sun a grid trace can hit a step's riser. Turned from the sun it read 0 while its neighbours read 1, every triangle around it faded, each
-- retrace moved it: a fixed place changed by 0.943 of the shadow in a frame on stairs, 0.720 on a curb, in full sun. The same scenes with the box off: 0.014, 0.027)
local function sunmap(angles, pitch, yaw)
    return read_map(bsp(WORLD .. SKYCAM .. ent({ { "classname", "shadow_control" }, { "angles", angles }, { "color", "187 187 187" }, { "distance", "1000" } }) ..
        ent({ { "classname", "light_environment" }, { "pitch", tostring(pitch) }, { "angles", "0 " .. tostring(yaw) .. " 0" } })))
end
local function stairs_x(sign, rise, deep)
    local t = {}
    for i = 0, 40 do
        local a = i * deep + 5.3
        if sign > 0 then t[#t + 1] = { a, 4000, -4000, 4000, GZ, GZ + (i + 1) * rise }
        else t[#t + 1] = { -4000, -a, -4000, 4000, GZ, GZ + (i + 1) * rise } end
    end
    return t
end
local function stairs_y(sign, rise, deep)
    local t = {}
    for i = 0, 40 do
        local a = i * deep + 5.3
        if sign > 0 then t[#t + 1] = { -4000, 4000, a, 4000, GZ, GZ + (i + 1) * rise }
        else t[#t + 1] = { -4000, 4000, -4000, -a, GZ, GZ + (i + 1) * rise } end
    end
    return t
end
do
    RunConsoleCommand("gsa1_sunshadow_followers", "0")
    local function ground_z(x, y)
        local z = GZ
        for i = 1, #W.boxes do
            local b = W.boxes[i]
            if x >= b[1] and x <= b[2] and y >= b[3] and y <= b[4] and b[6] > z then z = b[6] end
        end
        return z
    end
    -- a walk: the worst change at a fixed place in a frame, of the shadow's darkness; the lowest vertex; the points hitting ground turned from the sun; those with nothing around them that faces the sun
    local function walk(boxes, x0, y0, vx, vy, n, fixed)
        W.boxes, W.plane = boxes, { 0, 0, 1, GZ }
        place(x0 + 0.37, y0 + 0.61, ground_z(x0 + 0.37, y0 + 0.61))
        S.ResetSun()
        frames(20)
        local prev, worst, lowest, nturned, nalone = {}, 0, 1, 0, 0
        local g, sun = S.grid, S.light.sun
        local function turned(k) return g.hit[k] and -(g.nx[k] * sun.dx + g.ny[k] * sun.dy + g.nz[k] * sun.dz) <= 0 end
        for _ = 1, n do
            mc.pos.x, mc.pos.y = mc.pos.x + vx, mc.pos.y + vy
            mc.pos.z = ground_z(mc.pos.x, mc.pos.y)
            frame()
            for i = 1, nverts do if verts[i].c / FULL < lowest then lowest = verts[i].c / FULL end end
            for k = 1, 81 do
                if turned(k) then
                    nturned = nturned + 1
                    local i0, j0 = (k - 1) % 9, math.floor((k - 1) / 9)
                    local alone = true
                    for dj = -1, 1 do
                        for di = -1, 1 do
                            local a, b = i0 + di, j0 + dj
                            if a >= 0 and a < 9 and b >= 0 and b < 9 and g.hit[b * 9 + a + 1] and not turned(b * 9 + a + 1) then alone = false end
                        end
                    end
                    if alone then nalone = nalone + 1 end
                end
            end
            for j = 1, #fixed do
                local c = colour_at(fixed[j][1], fixed[j][2])
                if c and prev[j] then worst = math.max(worst, math.abs(c - prev[j]) / FULL) end
                prev[j] = c
            end
        end
        W.boxes = {}
        return worst, lowest, nturned, nalone
    end
    local R = 5.3
    local function fixed_x() local t = {} for _, x in ipairs({ -40, -24, -11, -7, -4, 4, 7, 11, 24, 40 }) do for _, y in ipairs({ -13, 0, 11 }) do t[#t + 1] = { x + R, y } end end return t end
    local function fixed_y() local t = {} for _, y in ipairs({ -40, -24, -11, -7, -4, 4, 7, 11, 24, 40 }) do for _, x in ipairs({ -13, 0, 11 }) do t[#t + 1] = { x, y + R } end end return t end
    local function fixed_along(sx, sy, deep)
        local t = {}
        for i = 0, 12 do
            local a = (i + 2) * deep + deep / 2 + R
            t[#t + 1] = { sx * a, sy * a }
        end
        return t
    end
    local B = 4000
    local function scenes(label)
        local bad, worstAll, lowAll, turnedAll, nr = 0, 0, 1, 0, 0
        local function one(name, boxes, x0, y0, vx, vy, n, fixed)
            local w, lo, nt = walk(boxes, x0, y0, vx, vy, n, fixed)
            nr = nr + 1
            worstAll, lowAll, turnedAll = math.max(worstAll, w), math.min(lowAll, lo), turnedAll + nt
            if w > 0.05 or lo < 0.9 then
                bad = bad + 1
                print(string.format("  (%s, %s: worst %.3f, lowest %.2f, %d turned points)", label, name, w, lo, nt))
            end
        end
        one("curb 16, riser facing -x", { { R, B, -B, B, GZ, GZ + 16 } }, -200, 0, 4, 0, 100, fixed_x())
        one("curb 16, riser facing +x", { { -B, R, -B, B, GZ, GZ + 16 } }, 200, 0, -4, 0, 100, fixed_x())
        one("curb 16, riser facing -y", { { -B, B, R, B, GZ, GZ + 16 } }, 0, -200, 0, 4, 100, fixed_y())
        one("curb 16, riser facing +y", { { -B, B, -B, R, GZ, GZ + 16 } }, 0, 200, 0, -4, 100, fixed_y())
        one("curb 24, riser facing -y", { { -B, B, R, B, GZ, GZ + 24 } }, 0, -200, 0, 3, 130, fixed_y())
        one("curb 8, riser facing -x", { { R, B, -B, B, GZ, GZ + 8 } }, -200, 0, 12, 0, 33, fixed_x())
        one("a fence 16 high, 4 thick, across x", { { R, R + 4, -B, B, GZ, GZ + 16 } }, -200, 0, 4, 0, 100, fixed_x())
        one("a fence 16 high, 4 thick, across y", { { -B, B, R, R + 4, GZ, GZ + 16 } }, 0, -200, 0, 4, 100, fixed_y())
        one("stairs 8/16 up +x", stairs_x(1, 8, 16), -120, 0, 7, 0, 45, fixed_along(1, 0, 16))
        one("stairs 8/16 up -x", stairs_x(-1, 8, 16), 120, 0, -7, 0, 45, fixed_along(-1, 0, 16))
        one("stairs 8/12 up +x", stairs_x(1, 8, 12), -120, 0, 7, 0, 45, fixed_along(1, 0, 12))
        one("stairs 8/12 up -x", stairs_x(-1, 8, 12), 120, 0, -7, 0, 45, fixed_along(-1, 0, 12))
        one("stairs 8/12 up +y", stairs_y(1, 8, 12), 0, -120, 0, 7, 45, fixed_along(0, 1, 12))
        one("stairs 8/12 up -y", stairs_y(-1, 8, 12), 0, 120, 0, -7, 45, fixed_along(0, -1, 12))
        info("%s: %d walks over curbs and stairs in open sun, the shadow slanted another way than the sun: a fixed place changes by at most %.3f in a frame, lowest vertex %.2f (%d points on ground turned from the sun)", label, nr, worstAll, lowAll, turnedAll)
        check(bad == 0 and turnedAll > 0, "%s: curbs and stairs in full sun: no notch: a fixed place changes by hundredths, every vertex at full strength (%d of %d walks over; worst %.3f, lowest %.2f, %d turned points seen)", label, bad, nr, worstAll, lowAll, turnedAll)
    end
    sunmap("80 30 0", -60, 247)
    scenes("awm_bigcity's numbers")
    sunmap("80 30 0", -70, 0)
    scenes("gm_sonic_zone_one's numbers")
    sunmap("80 30 0", -120, 135)
    scenes("rp_downtown_v4c's numbers")
    -- a new shadow's first look: a riser's points read the points beside them that face the sun, not those still to be read
    do
        sunmap("80 30 0", -60, 247)
        W.boxes, W.plane = { { R, B, -B, B, GZ, GZ + 16 } }, { 0, 0, 1, GZ }
        local you0 = S.SUN_YOU
        S.SUN_YOU = 1000
        local g, sun = S.grid, S.light.sun
        local seen, lo = 0, 1
        for x = -60, 40, 3 do
            place(x + 0.37, 0.61, ground_z(x + 0.37, 0.61))
            S.ResetSun()
            g.sunWas = false
            frame()
            for k = 1, 81 do
                if g.hit[k] and -(g.nx[k] * sun.dx + g.ny[k] * sun.dy + g.nz[k] * sun.dz) <= 0 then
                    seen = seen + 1
                    lo = math.min(lo, g.sun[k])
                end
            end
        end
        S.SUN_YOU = you0
        W.boxes = {}
        check(seen > 0 and lo >= 0.99, "a new shadow's first look: a riser's points read full at once (%d points, lowest %.2f)", seen, lo)
    end
    -- at speed: the second rays are few and the budget holds
    sunmap("80 30 0", -60, 247)
    W.boxes = stairs_x(1, 8, 16)
    place(-120.37, 0.61, GZ)
    S.ResetSun()
    frames(10)
    count_masks()
    local nf = 0
    for _ = 1, 40 do
        mc.pos.x = mc.pos.x + 25
        mc.pos.z = ground_z(mc.pos.x, mc.pos.y)
        frame()
        nf = nf + 1
    end
    local raysStairs = (traceByMask[MASK_OPAQUE or 16513] or 0) / nf
    info("1500 HU/s up stairs 8/16: %.1f rays of the check a frame, your shadow alone", raysStairs)
    check(raysStairs <= S.SUN_YOU + 1, "1500 HU/s up stairs: the rays stay within the budget (%.1f a frame)", raysStairs)
    W.boxes = {}

    -- a sun nearly overhead: the same riser faces it a little: a sliver keeps what its corners say
    sunmap("80 0 0", -87, 0)
    local wg, lg, ng = walk({ { R, B, -B, B, GZ, GZ + 16 } }, -200, 0, 4, 0, 100, fixed_x())
    check(wg <= 0.05 and lg >= 0.9 and ng == 0, "a sun nearly overhead, a riser that hardly faces it: no notch (worst %.3f, lowest %.2f)", wg, lg)
    -- stairs whose steps fall exactly on the grid's rows, every row on a riser at once: nothing around such a point faces the sun, and nothing is lost
    sunmap("80 0 0", -60, 180)
    -- (0.9.9d: the grid's rows lie on fixed places, so it is the stairs that are put at every phase: at one of them all the rows fall on risers)
    local wa, la, na, alone = 0, 1, 0, 0
    for phase = 0, 10, 1 do
        local boxes, fixed = stairs_x(1, 8, 10.77), fixed_along(1, 0, 10.77)
        for _, b in ipairs(boxes) do b[1] = b[1] + phase end
        for _, p in ipairs(fixed) do p[1] = p[1] + phase end
        local w1, l1, n1, a1 = walk(boxes, -120, 0, 7, 0, 45, fixed)
        wa, la, na, alone = math.max(wa, w1), math.min(la, l1), na + n1, alone + a1
    end
    info("stairs on the grid's rows: worst %.3f, lowest %.2f, %d points turned, %d of them with nothing around them facing the sun", wa, la, na, alone)
    check(wa <= 0.05 and la >= 0.9 and alone > 0, "stairs that fall exactly on the grid's rows: no notch, these points keep what they read (worst %.3f, lowest %.2f, %d such points)", wa, la, alone)

    -- ground truly turned from the sun: still none. A wall a shadow falls on, turned from the sun, under a slanted light: its cells are drawn, it reads none; the sunny ground beyond its shade reads full
    sunmap("45 0 0", -50, 180)
    W.boxes = { { 0, 2000, -2000, 2000, GZ, GZ + 60 } }
    place(-70, 0, GZ)
    S.ResetSun()
    frames(30)
    do
        local g = S.grid
        local onWall, wallMax, farN, farMin = 0, 0, 0, 1
        for k = 1, 81 do
            if g.hit[k] then
                if math.abs(g.wx[k]) < 1 and g.wz[k] > GZ + 1 then
                    onWall = onWall + 1
                    wallMax = math.max(wallMax, g.sun[k])
                elseif g.wx[k] < -100 and g.wz[k] < GZ + 1 then
                    farN = farN + 1
                    farMin = math.min(farMin, g.sun[k])
                end
            end
        end
        check(onWall >= 9 and wallMax == 0 and farN > 0 and farMin >= 0.99, "a wall turned from the sun, a shadow falling on it under a slanted light: none on the wall (%d points, at most %.2f), full on the ground beyond its shade (%d points, at least %.2f)", onWall, wallMax, farN, farMin)
    end
    W.boxes = {}
    -- bands of ground falling away from the sun: one a cell wide or wider reads none, one narrower than half a cell makes no notch: the width of the surface decides, not how many rows of the grid are on it now
    read_map(bsp(REMASTER))
    -- (at: where the band starts, read at: at + read; 0.9.9d's rows lie on multiples of 12 HU here)
    local function band(wd, drop, alongY, at, read)
        at, read = at or 0, read or wd / 2 + 0.13
        W.boxes, W.plane = {}, { 0, 0, 1, GZ }
        local function hf(u)
            u = u - at
            if u < 0 then return GZ, 0 end
            if u < wd then return GZ - 1.6 * u, -1.6 end
            return GZ - 1.6 * wd - (drop or 0), 0
        end
        W.height = function(x, y)
            local z, sl = hf(alongY and y or x)
            if alongY then return z, 0, sl end
            return z, sl, 0
        end
        if alongY then place(0.61, -120.37, GZ) else place(-120.37, 0.61, GZ) end
        S.ResetSun()
        frames(20)
        local last, worst, sum, n, lo, near = nil, 0, 0, 0, 1, 0
        for _ = 1, 120 do
            if alongY then mc.pos.y = mc.pos.y + 2 else mc.pos.x = mc.pos.x + 2 end
            mc.pos.z = hf(alongY and mc.pos.y or mc.pos.x)
            frame()
            local c
            if alongY then c = colour_at(0.5, at + read) else c = colour_at(at + read, 0.5) end
            if c then
                sum, n, lo = sum + c / FULL, n + 1, math.min(lo, c / FULL)
                if last then
                    local d = math.abs(c - last) / FULL
                    worst = math.max(worst, d)
                    -- (within 30 HU of the feet: the outer rows of the grid hold no picture of a character this size)
                    if math.abs((alongY and mc.pos.y or mc.pos.x) - wd / 2) <= 30 then near = math.max(near, d) end
                end
            end
            last = c
        end
        W.height = nil
        return n > 0 and sum / n or -1, lo, worst, near
    end
    local m4, l4, w4 = band(4)
    check(m4 >= 0.98 and l4 >= 0.95 and w4 <= 0.02, "a band 4 HU wide turned from the sun, a sliver: no notch when a row of the grid falls on it (mean %.2f, lowest %.2f, worst change %.3f)", m4, l4, w4)
    local m60, l60 = band(60)
    check(m60 <= 0.02 and l60 == 0, "a band 60 HU wide turned from the sun: its middle reads none (mean %.2f, lowest %.2f)", m60, l60)
    local m16, l16, w16, n16 = band(16)
    info("a band 16 HU wide turned from the sun, walked across: its middle reads mean %.2f, lowest %.2f, worst change %.3f, within 30 HU of the feet %.3f", m16, l16, w16, n16)
    check(m16 <= 0.45 and n16 <= 0.3, "a band 16 HU wide, a row or two of the grid on it by turns: its width decides, not the rows: much the same either way, no blink between the two under the character (mean %.2f, worst change %.3f)", m16, n16)
    local m12, l12, w12 = band(12)
    info("a band 12 HU wide, a cell: its middle reads mean %.2f, lowest %.2f, worst change %.3f", m12, l12, w12)
    check(m12 >= 0.98 and w12 <= 0.02, "a band 12 HU wide, no wider than a cell: no notch (mean %.2f, lowest %.2f, worst change %.3f)", m12, l12, w12)
    -- (a row on the band: the cell past the drop is left out by the ledge rule, the one before it holds the place read)
    local md, ld, wdp = band(4, 22, false, 10, 1.13)
    check(md >= 0.98 and ld >= 0.95 and wdp <= 0.02, "a sliver at the top of a drop: its plane does not reach the ground below: no notch (mean %.2f, lowest %.2f, worst change %.3f)", md, ld, wdp)
    -- the same along the grid's other axis
    read_map(bsp(WORLD .. SKYCAM .. SC .. ent({ { "classname", "light_environment" }, { "pitch", "-50" }, { "angles", "0 90 0" } })))
    local my4, ly4, wy4 = band(4, 0, true)
    check(my4 >= 0.98 and ly4 >= 0.95 and wy4 <= 0.02, "a band 4 HU wide along the other axis: no notch (mean %.2f, lowest %.2f, worst change %.3f)", my4, ly4, wy4)
    local my60, ly60 = band(60, 0, true)
    check(my60 <= 0.02 and ly60 == 0, "a band 60 HU wide along the other axis: its middle reads none (mean %.2f, lowest %.2f)", my60, ly60)
    local my16, _, _, wy16 = band(16, 0, true)
    check(my16 <= 0.45 and wy16 <= 0.3, "a band 16 HU wide along the other axis: much the same either way (mean %.2f, worst change %.3f)", my16, wy16)
    read_map(bsp(REMASTER))

    -- the width goes with the grid's cell: a follower's coarser grid, a tall character's larger one: the same rule
    do
        sunmap("80 30 0", -60, 247)
        place(5000, 5000, GZ)
        RunConsoleCommand("gsa1_sunshadow_followers", "1")
        local Fw = follower(-200.37, 0.61)
        S.ResetSun()
        frames(20)
        W.boxes, W.plane = { { R, B, -B, B, GZ, GZ + 16 } }, { 0, 0, 1, GZ }
        local fixed, prev, worst, lowest = fixed_x(), {}, 0, 1
        for _ = 1, 100 do
            Fw.drawPos.x = Fw.drawPos.x + 4
            Fw.drawPos.z = ground_z(Fw.drawPos.x, Fw.drawPos.y)
            frame()
            for i = 1, nverts do
                if verts[i].x < 1000 and verts[i].c / FULL < lowest then lowest = verts[i].c / FULL end
            end
            for j = 1, #fixed do
                local c = colour_at(fixed[j][1], fixed[j][2])
                if c and prev[j] then worst = math.max(worst, math.abs(c - prev[j]) / FULL) end
                prev[j] = c
            end
        end
        check(worst <= 0.05 and lowest >= 0.9, "a follower over a curb under a slanted light: no notch (worst %.3f, lowest %.2f)", worst, lowest)
        read_map(bsp(REMASTER))
        W.boxes, W.plane = {}, { 0, 0, 1, GZ }
        Fw.drawPos.x, Fw.drawPos.y, Fw.drawPos.z = 0, 0, GZ
        S.ResetSun()
        frames(30)
        W.plane = { 0.662, 0.446, 0.6018, 0.6018 * GZ }       -- (the ground under them turns from the sun as they stand: what they read before does not stay)
        frames(30)
        local fhi = 0
        for i = 1, nverts do if verts[i].x < 1000 and verts[i].c > fhi then fhi = verts[i].c end end
        W.plane = { 0, 0, 1, GZ }
        check(fhi == 0, "a follower on a slope turned from the sun: none (%.2f)", fhi)
        drop(Fw)
        frames(12)
        RunConsoleCommand("gsa1_sunshadow_followers", "0")
        -- a tall character
        local save = C.info
        C.info = setmetatable({ height = 110 }, { __index = save })
        sunmap("80 30 0", -60, 247)
        local wt, lt = walk({ { R, B, -B, B, GZ, GZ + 16 } }, -200, 0, 4, 0, 100, fixed_x())
        check(wt <= 0.05 and lt >= 0.9, "a character of height 110 over a curb under a slanted light: no notch (worst %.3f, lowest %.2f)", wt, lt)
        -- (a low sun, a gentle slope turned from it: the larger cells stay under the ledge rule)
        read_map(bsp(WORLD .. SKYCAM .. SC .. ent({ { "classname", "light_environment" }, { "pitch", "-30" }, { "angles", "0 0 0" } })))
        W.boxes, W.plane = {}, { 0, 0, 1, GZ }
        place(0, 0, GZ)
        S.ResetSun()
        frames(30)
        local tb = cmax()
        W.plane = { 0.573, 0, 0.8196, 0.8196 * GZ }
        frames(30)
        local thi, tn = nverts == 0 and 0 or cmax(), S.grid.ncells
        W.plane = { 0, 0, 1, GZ }
        C.info = save
        read_map(bsp(REMASTER))
        check(tb >= FULL - 0.01 and tn > 0 and thi == 0, "a character of height 110, the ground under it turning from the sun: none (%.2f on %d cells; %.2f before)", thi, tn, tb)
    end
    -- the grid's rim knows one side of a point: a neighbour on its plane says it goes on, anything less counts once, along either axis. A row 9 HU past a crease on the rim reads what is around it; the rim's row with the next row on the
    -- plane too reads none
    do
        W.boxes, W.plane = {}, { 0, 0, 1, GZ }
        -- (0.9.9d: the rows lie on multiples of 12 HU: the crease at 303 has the rows 300 and 312 beside it)
        W.height = function(x)
            if x < 303 then return GZ, 0, 0 end
            return GZ - 1.6 * (x - 303), -1.6, 0
        end
        place(312 - 48, 0.61, GZ)
        S.ResetSun()
        frames(30)
        local g = S.grid
        local rimAlone = 1
        for k = 1, 81 do if g.hit[k] and g.wx[k] > 303 then rimAlone = math.min(rimAlone, g.sun[k]) end end
        place(324 - 48, 0.61, GZ)
        S.ResetSun()
        frames(30)
        local onRim, rimHi = 0, 0
        for k = 1, 81 do
            if g.hit[k] and g.wx[k] > 303 then
                onRim = onRim + 1
                rimHi = math.max(rimHi, g.sun[k])
            end
        end
        W.height = nil
        read_map(bsp(WORLD .. SKYCAM .. SC .. ent({ { "classname", "light_environment" }, { "pitch", "-50" }, { "angles", "0 90 0" } })))
        W.height = function(_, y)
            if y < 303 then return GZ, 0, 0 end
            return GZ - 1.6 * (y - 303), 0, -1.6
        end
        place(0.61, 324 - 48, GZ)
        S.ResetSun()
        frames(30)
        local onRim2, rimHi2 = 0, 0
        for k = 1, 81 do
            if g.hit[k] and g.wy[k] > 303 then
                onRim2 = onRim2 + 1
                rimHi2 = math.max(rimHi2, g.sun[k])
            end
        end
        W.height = nil
        read_map(bsp(REMASTER))
        check(rimAlone >= 0.99 and onRim == 18 and rimHi <= 0.01 and onRim2 == 18 and rimHi2 <= 0.01, "the rim: one row past a crease reads what is around it (%.2f), two rows none, along either axis (%d points, at most %.2f; %d points, at most %.2f)", rimAlone, onRim, rimHi, onRim2, rimHi2)
    end
    -- a trace that reports a surface edge-on to its own ray: no division by nothing, no NaN in a vertex's colour
    do
        W.boxes, W.plane = {}, { 0, 0, 1, GZ }
        place(0, 0, GZ)
        S.ResetSun()
        frames(30)
        local tl = M.traceLine
        M.traceLine = function(t)
            local r = tl(t)
            if (t.mask or 0) ~= (MASK_OPAQUE or 16513) then r.HitNormal = Vector(1, 0, 0) end
            return r
        end
        frames(30)
        local v = nverts == 0 and 0 or cmax()
        M.traceLine = tl
        local g = S.grid
        local nans = 0
        for k = 1, 81 do if g.sun[k] ~= g.sun[k] then nans = nans + 1 end end
        check(nans == 0 and not S.broken and nearly(v, FULL, 0.01), "a surface reported edge-on to the ray: no NaN, the points keep what they read (%d; %.2f)", nans, v)
        S.ResetSun()
        frames(30)
    end
    -- what a tall wall shades stays shade: the second ray is for low steps. A wall 64 HU high, the ground right behind it
    read_map(bsp(REMASTER))
    W.boxes, W.plane = { { -2000, -10, -2000, 2000, GZ, GZ + 64 } }, { 0, 0, 1, GZ }
    place(10, 0, GZ)
    S.ResetSun()
    frames(30)
    do
        local g = S.grid
        local n3, hi = 0, 0
        for k = 1, 81 do
            if g.hit[k] and g.wz[k] < GZ + 1 and g.wx[k] > -9 and g.wx[k] < 1 then
                n3 = n3 + 1
                hi = math.max(hi, g.sun[k])
            end
        end
        check(n3 > 0 and hi <= 0.05, "the ground right behind a wall 64 HU high stays in its shade (%d points, at most %.2f)", n3, hi)
    end
    -- a low one: the ray stops, the second one, a step's height higher, gets there; the corner counts as sun. Two rays, one for each corner beside the step
    W.boxes = { { -2000, -10, -2000, 2000, GZ, GZ + 16 } }
    S.ResetSun()
    count_masks()
    frames(30)
    do
        local g = S.grid
        local n3, lo = 0, 1
        for k = 1, 81 do
            if g.hit[k] and g.wz[k] < GZ + 1 and g.wx[k] > -9 then
                n3 = n3 + 1
                lo = math.min(lo, g.sun[k])
            end
        end
        check(n3 > 0 and lo >= 0.99, "the ground right behind a curb 16 HU high: its narrow shade fades no cell (%d points, at least %.2f)", n3, lo)
    end
    W.boxes = {}
    -- a second ray that starts in solid: no way up: shade
    do
        local tl = M.traceLine
        M.traceLine = function(t)
            if (t.mask or 0) ~= (MASK_OPAQUE or 16513) then return tl(t) end
            local out = t.output or {}
            local up = t.start.z > GZ + 20
            out.StartSolid, out.AllSolid, out.Hit, out.HitSky, out.Fraction = up, up, true, false, up and 0 or 1e-4
            out.HitPos = out.HitPos or Vector()
            out.HitNormal = out.HitNormal or Vector()
            return out
        end
        place(0, 0, GZ)
        S.ResetSun()
        frames(30)
        M.traceLine = tl
        local v = nverts == 0 and 0 or cmax()
        check(v == 0 and not S.broken, "a ray stopped at once whose second ray starts in solid: shade (%.2f)", v)
    end
    -- the second ray counts in the budget, and starts a step's height above the first
    do
        local tl, starts = M.traceLine, {}
        M.traceLine = function(t)
            if (t.mask or 0) ~= (MASK_OPAQUE or 16513) then return tl(t) end
            local out = t.output or {}
            starts[#starts + 1] = t.start.z
            out.StartSolid, out.AllSolid, out.Hit = false, false, true
            out.HitSky = t.start.z > GZ + 20
            out.Fraction = out.HitSky and 0.5 or 1e-4
            out.HitPos = out.HitPos or Vector()
            out.HitNormal = out.HitNormal or Vector()
            return out
        end
        local you = S.SUN_YOU
        S.SUN_YOU = 4
        place(9000, 0, GZ)
        S.ResetSun()
        frame()
        S.SUN_YOU = you
        M.traceLine = tl
        local firsts, seconds = 0, 0
        for _, z in ipairs(starts) do
            if nearly(z, GZ + S.LIFT + S.SUN_LIFT, 0.01) then firsts = firsts + 1
            elseif nearly(z, GZ + S.LIFT + S.SUN_LIFT + S.SUN_STEP, 0.01) then seconds = seconds + 1 end
        end
        check(#starts <= 5 and #starts >= 4 and firsts + seconds == #starts and seconds >= 2, "a budget of 4, each ray stopped right after its start: 4 rays and at most one over, the second a step's height higher (%d rays, %d first, %d second)", #starts, firsts, seconds)
        settle(5)
    end
    place(0, 0, GZ)
    S.ResetSun()
    settle(5)
end

-- 5e. what the earlier mutation runs did not see --------------------------------------------------------------------------------------
do
    local MO = MASK_OPAQUE or 16513
    W.boxes, W.plane = {}, { 0, 0, 1, GZ }
    RunConsoleCommand("gsa1_sunshadow_followers", "0")
    place(0, 0)
    S.ResetSun()
    settle(20)
    -- standing: the grid's normals are not asked for again every frame: 4 grids a second, as 0.9.9b
    count_masks()
    settle(60)
    do
        local gridN = traceN - (traceByMask[MO] or 0)
        check(gridN <= 81 * 5, "standing with the check on: at most 5 grids of 81 traces in 60 frames (%d traces)", gridN)
    end
    -- where a ray starts: at the corner of the lattice, on the plane of the point asking, S.SUN_LIFT along that plane's normal
    do
        local nx, nz = 0.2, math.sqrt(1 - 0.04)
        W.plane = { -nx, 0, nz, nz * GZ }     -- (rises towards +x, towards the sun's far side: it faces the sun)
        local tl, ok2, nr, why = M.traceLine, true, 0, ""
        M.traceLine = function(t)
            if (t.mask or 0) == MO then
                nr = nr + 1
                local sx0, sz0 = t.start.x + nx * S.SUN_LIFT, t.start.z - nz * S.SUN_LIFT     -- (the plane's normal here is (-nx, 0, nz))
                local cellx = sx0 / S.SUN_CELL
                -- the point on the plane under the corner, as the mock's plane gives it, lifted as the grid's points are (S.LIFT along the light, straight down here)
                local onPlane = GZ + (nx / nz) * sx0 + S.LIFT
                if math.abs(cellx - math.floor(cellx + 0.5)) > 1e-3 or math.abs(sz0 - onPlane) > 0.01 then
                    ok2 = false
                    why = string.format("start (%.2f %.2f %.2f), on the plane at %.2f", t.start.x, t.start.y, t.start.z, onPlane)
                end
            end
            return tl(t)
        end
        S.ResetSun()
        settle(10)
        M.traceLine = tl
        W.plane = { 0, 0, 1, GZ }
        check(nr > 0 and ok2, "a ray starts at its corner on the asking point's plane, S.SUN_LIFT along the normal (%d rays; %s)", nr, why)
    end
    -- the lift matters: a point's plane can lie under the ground at the next corner: in a gentle valley a corner's ray still starts in the air
    do
        W.boxes, W.plane = {}, { 0, 0, 1, GZ }
        W.height = function(x)
            if x < 16 then return GZ - 0.1 * (x - 16), -0.1, 0 end
            return GZ + 0.1 * (x - 16), 0.1, 0
        end
        place(16, 0, GZ)
        S.ResetSun()
        settle(30)
        W.height = nil
        local SF2, n3, solid = S.sunfield, 0, 0
        for h = 1, S.SUN_SLOTS do
            if SF2.st[h] == 1 then n3 = n3 + 1 elseif SF2.st[h] == 2 then solid = solid + 1 end
        end
        check(n3 > 0 and solid == 0, "a gentle valley: no corner's ray starts under the ground (%d answered, %d not)", n3, solid)
        S.ResetSun()
        settle(5)
    end
    -- on the top of a floor of its own, under a roof
    W.boxes = { { -2000, 2000, -2000, 2000, GZ - 20, GZ }, { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220 } }
    S.ResetSun()
    settle(30)
    do
        local v = nverts == 0 and 0 or cmax()
        W.boxes = {}
        check(v == 0, "a floor of its own under a roof: dark, the ray starts off the surface (%.2f)", v)
    end
    -- a wall that faces the sun, with nothing under its plane to divide by: the corner's height is the point's
    sunmap("60 0 0", -50, 0)
    W.boxes = { { 0, 2000, -2000, 2000, GZ, GZ + 400 } }
    place(-60, 0, GZ)
    S.ResetSun()
    frames(30)
    do
        local g, SF2 = S.grid, S.sunfield
        local onWall, worst = 0, 0
        for k = 1, 81 do if g.hit[k] and math.abs(g.wx[k]) < 1 then onWall = onWall + 1 end end
        for h = 1, S.SUN_SLOTS do if SF2.st[h] ~= 0 and SF2.st[h] ~= 3 then worst = math.max(worst, math.abs(SF2.zg[h] - GZ)) end end
        check(onWall > 0 and worst < 300, "a wall facing the sun: the corners its points ask keep heights near theirs (%d points on it, furthest %.0f HU from the ground)", onWall, worst)
    end
    W.boxes = {}
    read_map(bsp(REMASTER))
    place(0, 0)
    S.ResetSun()
    settle(5)
    -- a corner kept for ground further than S.SUN_SAME from a point does not count for it
    do
        local SF2 = S.sunfield
        local n3 = 0
        for h = 1, S.SUN_SLOTS do
            if SF2.st[h] == 1 then
                SF2.zg[h], SF2.lit[h], SF2.from[h], SF2.t0[h] = SF2.zg[h] + 60, 0, 0, 0
                n3 = n3 + 1
            end
        end
        settle(20)
        local v = nverts == 0 and 0 or cmax()
        check(n3 > 0 and nearly(v, FULL, 0.01), "corners kept 60 HU from this ground, reading shade: they do not count, the points' own rays answer (%d corners, %.2f)", n3, v)
        S.ResetSun()
        settle(5)
    end
    -- a ray that starts in solid everywhere: no answer, drawn, the side of 0.9.9b
    do
        local tl = M.traceLine
        M.traceLine = function(t)
            local r = tl(t)
            if (t.mask or 0) == MO then r.StartSolid, r.AllSolid, r.Hit = true, true, true end
            return r
        end
        S.ResetSun()
        settle(10)
        M.traceLine = tl
        check(not S.broken and nearly(cmax(), FULL, 0.01), "every ray starting in solid: no answer, drawn (%.2f)", cmax())
        S.ResetSun()
        settle(5)
    end
    -- the engine's util.TraceLine with an output table may return nothing: the answer is in the table
    do
        local tl = M.traceLine
        M.traceLine = function(t)
            local r = tl(t)
            if (t.mask or 0) == MO then return nil end
            return r
        end
        W.boxes = { { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220 } }
        S.ResetSun()
        settle(10)
        local under = nverts == 0 and 0 or cmax()
        W.boxes = {}
        S.ResetSun()
        settle(10)
        M.traceLine = tl
        check(not S.broken and under == 0 and nearly(cmax(), FULL, 0.01), "a ray whose trace returns nothing: the answer read from its output: under a roof %.2f, in the sun %.2f (%s)", under, cmax(), tostring(S.broken))
        settle(5)
    end
    -- an answer that changes again while it is still fading: on from where it is, no jump
    do
        local keep = S.SUN_KEEP
        S.SUN_KEEP = 0.1
        S.ResetSun()
        settle(30)
        W.boxes = { { -2000, 2000, -2000, 2000, GZ + 200, GZ + 220 } }
        local biggest, before = 0, cmax()
        for _ = 1, math.floor(60 * (S.SUN_KEEP + S.SUN_FADE / 2)) do        -- (0.9.9c: 13 frames, 0.9.9d's longer fade 36)
            frame()
            local c = nverts == 0 and 0 or cmax()
            biggest = math.max(biggest, math.abs(c - before))
            before = c
        end
        local mid = before
        W.boxes = {}
        for _ = 1, 90 do
            frame()
            local c = nverts == 0 and 0 or cmax()
            biggest = math.max(biggest, math.abs(c - before))
            before = c
        end
        S.SUN_KEEP = keep
        check(mid > 0.05 * FULL and mid < 0.95 * FULL and biggest <= FULL * ((1 / 60) / 0.2) and nearly(before, FULL, 0.1), "a roof that comes and goes within a fade: no jump, at most %.1f a frame (%.1f; %.1f when it went, %.1f at the end)", FULL * ((1 / 60) / 0.2), biggest, mid, before)
        S.ResetSun()
        settle(5)
    end
    -- the followers' budget: a frame's rays for them at most S.SUN_THEM, every frame again
    do
        place(5000, 5000)
        RunConsoleCommand("gsa1_sunshadow_followers", "3")
        local fs = { follower(0, 0), follower(300, 0), follower(600, 0) }
        S.ResetSun()
        frames(30)
        for _, Fq in ipairs(fs) do Fq.drawPos.x = Fq.drawPos.x + 3000 end
        local them = S.SUN_THEM
        S.SUN_THEM = 6
        S.ResetSun()
        -- (your shadow's corners first: fresh for 4 s, so what follows is the followers')
        for _, Fq in ipairs(fs) do Fq.drawPos.x = Fq.drawPos.x - 3000 end
        frames(1)
        for _, Fq in ipairs(fs) do Fq.drawPos.x = Fq.drawPos.x + 3000 end
        local most, total = 0, 0
        for _ = 1, 12 do
            count_masks()
            frame()
            local r = traceByMask[MO] or 0
            most, total = math.max(most, r), total + r
        end
        S.SUN_THEM = them
        for i = #fs, 1, -1 do drop(fs[i]) end
        frames(12)
        RunConsoleCommand("gsa1_sunshadow_followers", "0")
        check(most <= 6 + 1 and total > 12, "the followers' budget: at most S.SUN_THEM rays a frame, one over when a second ray falls on the last (%d at most, %d in 12 frames)", most, total)
    end
    -- the number the perf line prints: every trace of the feature, yours, the followers', the sun's
    do
        place(0, 0)
        RunConsoleCommand("gsa1_sunshadow_followers", "2")
        local fs = { follower(0, 300), follower(0, -300) }
        S.ResetSun()
        frames(20)
        local t0 = GSA1.SunShadowTraces()
        count_masks()
        local g0, fo0, rays0 = S.stats.traces, S.followers.stats.traces, S.sunfield.traces
        for _ = 1, 60 do
            mc.pos.x = mc.pos.x + 25
            for _, Fq in ipairs(fs) do Fq.drawPos.x = Fq.drawPos.x + 25 end
            frame()
        end
        local t1 = GSA1.SunShadowTraces()
        local rays = traceByMask[MO] or 0
        local all = traceN
        check(t1 - t0 == all and rays > 0 and S.followers.stats.traces > fo0 and S.stats.traces > g0 and S.sunfield.traces - rays0 == rays,
            "GSA1.SunShadowTraces: every trace of it, yours, the followers', the sun's (%d, counted %d, of them %d rays)", t1 - t0, all, rays)
        for i = #fs, 1, -1 do drop(fs[i]) end
        frames(12)
        RunConsoleCommand("gsa1_sunshadow_followers", "0")
    end
    -- the shadow switched off and on: what it knew does not count, also with the budget spent
    do
        W.boxes = {}
        place(0, 0)
        S.ResetSun()
        settle(20)
        RunConsoleCommand("gsa1_sunshadow", "0")
        frames(3)
        W.boxes = { { -3000, 3000, -3000, 3000, GZ + 200, GZ + 220 } }
        S.ResetSun()
        local you = S.SUN_YOU
        S.SUN_YOU = 2
        RunConsoleCommand("gsa1_sunshadow", "1")
        local fb = 0
        for _ = 1, 30 do
            frame()
            local here = 0
            for i = 1, nverts do if verts[i].c > 0.5 then here = here + 1 end end
            if here > 0 then fb = fb + 1 end
        end
        S.SUN_YOU = you
        W.boxes = {}
        check(fb == 0, "the shadow switched off, a roof, on again with a budget of 2: no frame lit (%d)", fb)
        S.ResetSun()
        settle(10)
    end
end

-- 5f. the fade at a shade line (0.9.9d) ------------------------------------------------------------------------------------------------
-- The owner, on 0.9.9c: "The transition between non-shadow and shadowed area looks odd. The sun shadow disappears in a gradient style." Measured here as a person sees it: the vertex colour the receivers really have at fixed places, in steps of
-- 1 HU across the line, from where it passes 10 % of the shadow's darkness to where it passes 90 %. On 0.9.9c: 28 HU at most, 27.3 on the mean across a straight line, 32 and 29.9 across a slanted one, 34 and 29.7 for a follower (the lattice's 32 HU cell, READ sun_at; MEASURED by this section on build/release_0.9.9c).
do
    W.boxes = {}
    S.ResetSun()
    -- from the place (x0, y0) along the unit vector (nx, ny), which points from the shade to the sun: the distance between the first point over 10 % and the last under 90 %; nil where the quads do not reach
    local function width(x0, y0, nx, ny)
        local first, last
        for t = -30, 30 do
            local c = colour_at(x0 + nx * t + 0.25, y0 + ny * t + 0.25)
            if c then
                local v = c / FULL
                if v > 0.1 and not first then first = t end
                if v < 0.9 then last = t end
            end
        end
        if not first or not last or last < first then return nil end
        return last - first
    end
    -- every line, every phase of the character against it: the widest and the mean
    local function sweep_lines(shade_of, nx, ny, lines, offs, cross)
        local worst, sum, n = 0, 0, 0
        for _, L in ipairs(lines) do
            W.shade = shade_of(L)
            for _, o in ipairs(offs) do
                local px, py = cross(L, o)
                place(px, py)
                S.ResetSun()
                S.grid.sunWas = false
                settle(4)
                local w = width(px - nx * o, py - ny * o, nx, ny)
                if w then
                    worst, sum, n = math.max(worst, w), sum + w, n + 1
                end
            end
        end
        W.shade = nil
        return worst, n > 0 and sum / n or 0, n
    end
    local offs = {}
    for o = -9, 9, 3 do offs[#offs + 1] = o end
    local lines = {}
    for L = 69, 165, 8 do lines[#lines + 1] = L end        -- (three cells of the lattice: against the rows of 12 HU the lattice comes round every 96 HU)
    local w1, m1, n1 = sweep_lines(function(L) return function(x) return x < L end end, 1, 0, lines, offs, function(L, o) return L + o, 0 end)
    info("the fade across a straight shade line, your shadow: widest %.0f HU, mean %.1f (%d places; 10 %% to 90 %% of the shadow's darkness)", w1, m1, n1)
    check(n1 >= 40 and w1 <= WIDE_STRAIGHT and m1 <= MEAN_STRAIGHT, "a straight shade line: the fade ends close to the line, at most %d HU, %d on the mean (%.0f, %.1f; 0.9.9c: 28, 27.3)", WIDE_STRAIGHT, MEAN_STRAIGHT, w1, m1)
    -- WHAT IT COSTS, said by number: the lattice's corners decide where the line lies, so the place the shadow is half faded can be up to half a cell from the true line of shade; a soft fade hid that, a narrow one shows it
    do
        local off = 0
        for L = 65, 95, 2 do
            W.shade = function(x) return x < L end
            place(L, 0)
            S.ResetSun()
            S.grid.sunWas = false
            settle(4)
            for x = 48, 112 do
                local a, b = colour_at(x + 0.25, 0.25), colour_at(x + 1.25, 0.25)
                if a and b and a < FULL / 2 and b >= FULL / 2 then off = math.max(off, math.abs(x + 0.75 - L)) end
            end
        end
        W.shade = nil
        info("where the shadow is half faded against the true line of shade, a straight line: up to %.1f HU apart", off)
        check(off >= 12 and off <= 18, "the line's place comes from corners 32 HU apart: up to half a cell from the true line (%.1f HU; the owner's checklist says so)", off)
    end
    local slanted = {}
    for L = 0, 60, 10 do slanted[#slanted + 1] = L end
    local r2 = math.sqrt(0.5)
    local w2, m2, n2 = sweep_lines(function(L) return function(x, y) return (x + y) * r2 < L end end, r2, r2, slanted, offs, function(L, o) return (L + o) * r2, (L + o) * r2 end)
    info("the fade across a slanted shade line, your shadow: widest %.0f HU, mean %.1f (%d places)", w2, m2, n2)
    check(n2 >= 40 and w2 <= WIDE_SLANT and m2 <= MEAN_SLANT, "a slanted shade line: at most %d HU, %d on the mean (%.0f, %.1f; 0.9.9c: 32, 29.9)", WIDE_SLANT, MEAN_SLANT, w2, m2)
    -- no pop while walking over a slanted line, and across a straight one at an angle: the same bound as section 4's
    local function walk_over(shade, x0, y0, vx, vy, label)
        W.shade = shade
        place(x0, y0)
        S.ResetSun()
        settle(20)
        local last, worst = {}, 0
        for _ = 1, 240 do
            mc.pos.x, mc.pos.y = mc.pos.x + vx / 60, mc.pos.y + vy / 60
            frame()
            for x = -30, 90, 7 do
                for y = -30, 90, 7 do
                    local c = colour_at(x + 0.5, y + 0.5)
                    local key = x * 1000 + y
                    if c and last[key] then
                        local d = math.abs(c - last[key]) / FULL
                        if d > worst then worst = d end
                    end
                    last[key] = c
                end
            end
        end
        W.shade = nil
        info("%s over the shade line: a fixed place changed by at most %.3f of the shadow in a frame", label, worst)
        check(worst <= 0.10, "%s over the shade line: a fixed place changes by at most 0.10 of the shadow in a frame (%.3f)", label, worst)
    end
    walk_over(function(x, y) return (x + y) * r2 < 30 end, -40, -40, 85, 85, "walking at 120 HU/s on the slant")
    walk_over(function(x, y) return (x + y) * r2 < 30 end, 80, 80, -280, -280, "running at 400 HU/s back on the slant")
    walk_over(function(x, y) return (x + y) * r2 < 30 end, -40, 80, 113, 0, "walking along a row over the slant")
    walk_over(function(x) return x < 30.5 end, 0, 7, 120, 37, "walking at an angle over a straight line")
    -- a character standing: nothing moves at all
    W.shade = function(x, y) return (x + y) * r2 < 30 end
    place(21, 21)
    S.ResetSun()
    settle(20)
    local v0, moved = {}, 0
    for i = 1, nverts do v0[i] = verts[i].c end
    for _ = 1, 120 do
        frame()
        for i = 1, math.min(nverts, #v0) do moved = math.max(moved, math.abs(verts[i].c - v0[i])) end
    end
    W.shade = nil
    check(moved <= 0.01, "standing on a slanted line, the grid traced again four times a second: not a change (%.3f)", moved)
    -- a follower's coarser grid (16 HU)
    do
        local Fo2 = GSA1.Followers
        place(5000, 5000)
        local pos = Vector(80, 300, GZ)
        local id = G.Create(0, pos, 0, 0, 0)
        local e2 = ents.CreateClientside("gsa1_render")
        local F = { id = id, kind = 0, name = "sonic", title = "Sonic", uid = 100000, info = G.CharacterInfo(0), state = {}, batches = { count = 0 }, batchGen = 1, mats = {}, static = {},
                    matsDirty = true, ent = e2, drawPos = pos, drawYaw = 0, lod = 1, interp = true, renderGen = 1, follower = true }
        G.Batches(id, F.batches)
        e2.char = F
        Fo2.list[#Fo2.list + 1] = F
        Fo2.byId[id] = F
        RunConsoleCommand("gsa1_sunshadow_followers", "1")
        local worst, sum, n = 0, 0, 0
        for _, L in ipairs(lines) do
            W.shade = function(x) return x < L end
            for _, o in ipairs(offs) do
                pos:SetUnpacked(L + o, 300, GZ)
                M.mchars[id].pos.x, M.mchars[id].pos.y, M.mchars[id].pos.z = L + o, 300, GZ
                S.ResetSun()
                settle(6)
                local w = width(L, 300, 1, 0)
                if w then worst, sum, n = math.max(worst, w), sum + w, n + 1 end
            end
        end
        W.shade = nil
        info("the fade across a straight shade line, a follower's shadow: widest %.0f HU, mean %.1f (%d places)", worst, n > 0 and sum / n or 0, n)
        check(n >= 20 and worst <= WIDE_FOLLOWER and sum / n <= MEAN_FOLLOWER, "a follower's shadow: at most %d HU across a straight line, %d on the mean, its grid being 16 HU (%.0f, %.1f; 0.9.9c: 34, 29.7)", WIDE_FOLLOWER, MEAN_FOLLOWER, worst, n > 0 and sum / n or 0)
        F.removed = true
        for i = #Fo2.list, 1, -1 do if Fo2.list[i] == F then table.remove(Fo2.list, i) end end
        Fo2.byId[id] = nil
        e2:Remove()
        RunConsoleCommand("gsa1_sunshadow_followers", "3")
        frames(4)
    end
    -- the rows now lie up to half a cell off the character's centre, and may lag S.RETRACE_MOVE behind it as before: how much of the box the quads still reach around the centre, walking any way
    do
        W.shade = nil
        place(0, 0)
        S.ResetSun()
        settle(5)
        local least = math.huge
        for _ = 1, 300 do
            mc.pos.x, mc.pos.y = mc.pos.x + 0.9, mc.pos.y + 0.37
            frame()
            local lox, hix, loy, hiy = math.huge, -math.huge, math.huge, -math.huge
            for i = 1, nverts do
                local q = verts[i]
                lox, hix, loy, hiy = math.min(lox, q.x), math.max(hix, q.x), math.min(loy, q.y), math.max(hiy, q.y)
            end
            if nverts > 0 then least = math.min(least, mc.pos.x - lox, hix - mc.pos.x, mc.pos.y - loy, hiy - mc.pos.y) end
        end
        info("walking: the quads reach at least %.1f HU from the character's centre on every side (the box is 48; 0.9.9c: 42.6 on this walk)", least)
        check(least >= 48 - 6 - S.RETRACE_MOVE - 0.5, "the quads still reach %.1f HU around the character: the box less half a cell less the retrace's lag; 0.9.9c: 42.6", least)
    end
    -- no extra question to the engine: the same walk asks no more rays than 0.9.9c did (MEASURED on build/release_0.9.9c by this test: its info line)
    do
        W.shade = function(x, y) return (x + y) * r2 < 30 end
        place(-200, -200)
        S.ResetSun()
        settle(10)
        count_masks()
        for _ = 1, 400 do
            mc.pos.x, mc.pos.y = mc.pos.x + 2, mc.pos.y + 2
            frame()
        end
        local rays = traceByMask[MASK_OPAQUE or 16513] or 0
        W.shade = nil
        info("a walk of 400 frames over a slanted shade line: %d rays to the sun", rays)
        check(rays <= RAYS_099C * 1.05, "no extra questions to the engine: %d rays on a walk where 0.9.9c asked %d", rays, RAYS_099C)
    end
    place(0, 0)
    S.ResetSun()
    settle(5)
end

-- 5g. what 5f and the crease of section 4 do not show (0.9.9d's verifier, SADC/build/research/r099d/verify/: fade_new.txt, anyangle_new.txt, crease_new.txt): the same fade on lines at any angle and under a slanted light; a crease at every phase of the rows ---
do
    -- the width as a person sees it: 10 % to 90 % of what the walk's plateau reaches (under a slanted light the shadow is less dark)
    local function width(x0, y0, nx, ny)
        local vals, top = {}, 0
        for t = -36, 36 do
            local c = colour_at(x0 + nx * t + 0.25, y0 + ny * t + 0.25)
            vals[t] = c and c / FULL or false
            if c and c / FULL > top then top = c / FULL end
        end
        if top <= 0.05 then return nil end
        local first, last
        for t = -36, 36 do
            local v = vals[t]
            if v then
                if v > 0.1 * top and not first then first = t end
                if v < 0.9 * top then last = t end
            end
        end
        if not first or not last or last < first then return nil end
        return last - first
    end
    local function light(pitch, yaw)
        local MAP = WORLD .. SKYCAM .. ent({ { "classname", "shadow_control" }, { "angles", pitch .. " " .. yaw .. " 0" }, { "color", "187 187 187" }, { "distance", "1000" }, { "disableallshadows", "0" } }) ..
            ent({ { "classname", "light_environment" }, { "origin", "891 149 -112" }, { "targetname", "sunsunsun" }, { "style", "34" }, { "pitch", "-50" }, { "angles", "0 34 0" }, { "_light", "255 240 204 550" }, { "_ambient", "116 154 192 400" } }) ..
            ent({ { "classname", "env_sun" }, { "pitch", "-53" }, { "angles", "0 72 0" }, { "use_angles", "1" } })
        place(0, 0)
        read_map(bsp(MAP))
        W.boxes, W.height, W.shade = {}, nil, nil
        S.ResetSun()
        S.grid.sunWas = false
        settle(4)
    end
    -- bounds: what 0.9.9d measures, widest and mean; beside them 0.9.9c's. Fewer places than the verifier's run, and other ones: the widest stays within its numbers, the mean can differ by a little
    for _, r in ipairs({ { 90, 0, 29, 15.5, "49 / 31.8" }, { 60, 298, 24, 16.5, "47 / 32.0" } }) do
        light(r[1], r[2])
        local worst, sum, n = 0, 0, 0
        for ang = 0, 165, 15 do
            local nx, ny = math.cos(math.rad(ang)), math.sin(math.rad(ang))
            for L = 69, 165, 32 do
                W.shade = function(x, y) return x * nx + y * ny < L end
                for _, o in ipairs({ -9, 3 }) do
                    place(nx * (L + o), ny * (L + o))
                    S.ResetSun()
                    S.grid.sunWas = false
                    settle(4)
                    local w = width(nx * L, ny * L, nx, ny)
                    if w then worst, sum, n = math.max(worst, w), sum + w, n + 1 end
                end
            end
        end
        W.shade = nil
        info("5g lines at every 15 degrees, shadow_control %d %d: widest %d, mean %.1f (%d places); the verifier's fuller run, 0.9.9d %d, 0.9.9c %s", r[1], r[2], worst, n > 0 and sum / n or 0, n, r[3], r[5])
        check(n >= 60 and worst <= r[3] and sum / n <= r[4], "5g lines at any angle, shadow_control %d %d: at most %d HU, %.1f on the mean; NOT the 18 of an axis under a straight-down light (%d, %.1f)", r[1], r[2], r[3], r[4], worst, n > 0 and sum / n or 0)
    end
    local lines, offs = {}, { -9, -3, 3, 9 }
    for L = 69, 165, 16 do lines[#lines + 1] = L end
    for _, r in ipairs({ { 60, 30, 24, 22, "34 / 29.4" }, { 45, 30, 30, 21, "35 / 31.2" }, { 30, 0, 37, 26.5, "38 / 34.8" } }) do
        light(r[1], r[2])
        local worst, sum, n = 0, 0, 0
        for _, L in ipairs(lines) do
            W.shade = function(x) return x < L end
            for _, o in ipairs(offs) do
                place(L + o, 0)
                S.ResetSun()
                S.grid.sunWas = false
                settle(4)
                local w = width(L, 0, 1, 0)
                if w then worst, sum, n = math.max(worst, w), sum + w, n + 1 end
            end
        end
        W.shade = nil
        info("5g across a low light's azimuth, shadow_control %d %d: widest %d, mean %.1f (%d places); the verifier's fuller run, 0.9.9d %d, 0.9.9c %s", r[1], r[2], worst, n > 0 and sum / n or 0, n, r[3], r[5])
        check(n >= 24 and worst <= r[3] and sum / n <= r[4], "5g across a low light, shadow_control %d %d: at most %d HU, %.1f on the mean: the lower the light the less is gained (%d, %.1f)", r[1], r[2], r[3], r[4], worst, n > 0 and sum / n or 0)
    end
    read_map(bsp(REMASTER))
    W.boxes, W.height, W.shade = {}, nil, nil
    place(0, 0)
    S.ResetSun()
    settle(5)
    -- a crease at every phase of the rows of 12 HU. On a row, x = 300, section 4's walk reads 0.000; that is the best phase, not the rule. Under the feet it is gone; further out it is not, and no worse than 0.9.9c's 0.488 and 0.985
    do
        local n20, n30, n40 = 0, 0, 0
        for c0 = 300, 311 do
            W.boxes, W.plane = {}, { 0, 0, 1, GZ }
            local function hz(x) if x < c0 then return GZ, 0, 0 end return GZ - 1.6 * (x - c0), -1.6, 0 end
            W.height = function(x) return hz(x) end
            place(c0 - 60.37, 0.61, GZ)
            S.ResetSun()
            frames(20)
            local prev = {}
            for _ = 1, 60 do
                mc.pos.x = mc.pos.x + 2
                mc.pos.z = (hz(mc.pos.x))
                frame()
                for dx = -60, 60, 3 do
                    local px = c0 + dx + 0.5
                    local c = colour_at(px, 0.5)
                    if c and prev[dx] then
                        local d = math.abs(c - prev[dx]) / FULL
                        local far = math.abs(px - mc.pos.x)
                        if far <= 20 then n20 = math.max(n20, d) end
                        if far <= 30 then n30 = math.max(n30, d) end
                        if far <= 40 then n40 = math.max(n40, d) end
                    end
                    prev[dx] = c
                end
            end
            W.height = nil
        end
        info("5g a crease at 12 phases, walked over: within 20 HU of the feet %.3f, 30 HU %.3f, 40 HU %.3f of the shadow in a frame (0.9.9c: 0.488, 0.488, 0.985)", n20, n30, n40)
        check(n20 <= 0.002, "5g a crease at any phase: nothing moves within 20 HU of the feet (%.3f; 0.9.9c 0.488)", n20)
        check(n30 <= 0.54 and n40 <= 0.95, "5g a crease at any phase: further out it still jumps, the bound says how much (%.3f, %.3f; 0.9.9c 0.488, 0.985)", n30, n40)
        place(0, 0, GZ)
        S.ResetSun()
        settle(5)
    end
end

-- 6. cost --------------------------------------------------------------------------------------------------------------------
do
    local function moving(n, fols, dx, dy)
        for _ = 1, n do
            mc.pos.x, mc.pos.y = mc.pos.x + dx, mc.pos.y + dy
            for _, F in ipairs(fols) do F.drawPos.x, F.drawPos.y = F.drawPos.x + dx, F.drawPos.y + dy end
            frame()
        end
    end
    -- the grid's traces and the sun's rays a frame
    local function rate(fols, dx, dy)
        moving(30, fols, dx, dy)
        count_masks()
        moving(120, fols, dx, dy)
        local rays = traceByMask[MASK_OPAQUE or 16513] or 0
        return (traceN - rays) / 120, rays / 120
    end
    local F = {}
    place(0, 0)
    settle(5)
    local function setup(n)
        for i = #F, 1, -1 do drop(F[i]); F[i] = nil end
        for i = 1, n do F[i] = follower(mc.pos.x, mc.pos.y + 300 * i) end
        RunConsoleCommand("gsa1_sunshadow_followers", tostring(n))
        S.ResetSun()
        frames(15)
    end
    local sp = 25          -- HU a frame: 1500 HU/s at 60 fps
    local results = {}
    for _, n in ipairs({ 0, 3, 8 }) do
        setup(n)
        sunlit(false)
        local old, oldRays = rate(F, sp, 0)
        sunlit(true)
        S.ResetSun()
        local on1, rays1 = rate(F, sp, 0)
        local on2, rays2 = rate(F, sp * 0.7071, sp * 0.7071)
        results[n] = { old = old, oldRays = oldRays, on = on1, rays = rays1, diag = on2, raysDiag = rays2 }
        info("%d followers' shadows at 1500 HU/s on flat ground: the grids' traces a frame: as 0.9.9b %.1f, with the check %.1f; the check's rays a frame %.1f along an axis, %.1f diagonally", n, old, on1, rays1, rays2)
    end
    check(nearly(results[0].old, 81, 1) and nearly(results[3].old, 228, 2) and nearly(results[8].old, 473, 3), "(0.9.9b's counts at speed: 81, 228, 473 traces a frame: %.0f, %.0f, %.0f)", results[0].old, results[3].old, results[8].old)
    check(results[0].oldRays == 0 and results[8].oldRays == 0, "the option off: no ray of the check at speed")
    check(nearly(results[0].on, results[0].old, 0.01) and nearly(results[3].on, results[3].old, 0.01) and nearly(results[8].on, results[8].old, 0.01), "the check takes nothing from the grids and adds nothing to them (%.1f, %.1f, %.1f)", results[0].on, results[3].on, results[8].on)
    -- what the check adds: each ray's result is engine objects the harness cannot weigh (MEASURED here: how many rays; UNVERIFIED: how many bytes)
    check(results[0].rays <= 6 and results[3].rays <= 24 and results[8].rays <= 48 and results[0].raysDiag <= 10 and results[3].raysDiag <= 40 and results[8].raysDiag <= 56,
        "the check's rays at speed: at most 6 a shadow along an axis, 10 diagonally, and the budgets hold (%.1f, %.1f, %.1f; %.1f, %.1f, %.1f)", results[0].rays, results[3].rays, results[8].rays, results[0].raysDiag, results[3].raysDiag, results[8].raysDiag)
    -- standing: after the first answers almost nothing
    setup(3)
    settle(120)
    count_masks()
    settle(240)
    local sunT = traceByMask[MASK_OPAQUE or 16513] or 0
    info("standing, 4 shadows: %.2f traces of the check a frame, %.2f of the grids a frame", sunT / 240, (traceN - sunT) / 240)
    check(sunT / 240 <= 2, "standing: at most 2 traces of the check a frame for 4 shadows (%.2f)", sunT / 240)
    -- no second trace for the same corner when two shadows stand on it
    setup(0)
    count_masks()
    S.ResetSun()
    settle(20)
    local solo = traceByMask[MASK_OPAQUE or 16513] or 0
    local twin = follower(mc.pos.x, mc.pos.y)
    RunConsoleCommand("gsa1_sunshadow_followers", "1")
    frames(15)
    count_masks()
    S.ResetSun()
    settle(20)
    local both = traceByMask[MASK_OPAQUE or 16513] or 0
    check(solo > 0 and both <= solo + 6, "one lattice for all: two shadows on one spot ask no more than one does (%d, %d alone)", both, solo)
    drop(twin)
    frames(12)
    -- the budget: a jump into a new place asks at most so many corners a frame, the rest the next frames
    S.ResetSun()
    frame()
    count_masks()
    place(5000, 5000)
    frame()
    local first = (traceByMask[MASK_OPAQUE or 16513] or 0)
    check(first <= S.SUN_YOU, "a teleport: at most %d rays to the sun for your shadow in a frame (%d)", S.SUN_YOU, first)
    place(0, 0)
    settle(10)
    -- the budget spent: the rest the next frames, no answer lost
    do
        local you = S.SUN_YOU
        W.boxes = { { -5000, 5000, -5000, 5000, GZ + 200, GZ + 220 } }
        S.SUN_YOU = 4
        S.ResetSun()
        place(3000, 0)
        count_masks()
        frame()
        local one = traceByMask[MASK_OPAQUE or 16513] or 0
        local pending = S.grid.sunPending
        settle(12)
        check(one <= 4 and pending and (nverts == 0 or cmax() == 0), "a budget of 4 corners a frame: %d rays in the first, the rest in the next frames, all dark by then (%.2f)", one, cmax())
        S.SUN_YOU = you
        W.boxes = {}
        S.ResetSun()
        place(0, 0)
        settle(5)
    end
    -- no Lua garbage of its own (the mock module's own left out; these world stand-ins make none)
    local mockkb = 0
    local wrapped = {}
    for nm, fn in pairs(gsa1) do
        if type(fn) == "function" then
            wrapped[nm] = fn
            gsa1[nm] = function(...)
                local q0 = collectgarbage("count")
                local a, b, c, d, e, f, g2, h = fn(...)
                mockkb = mockkb + collectgarbage("count") - q0
                return a, b, c, d, e, f, g2, h
            end
        end
    end
    local hk = M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow
    local hp = M.hooks.PostRender.gsa1_sunshadow
    local function measure(n, fols, dx, label)
        local co = coroutine.create(function()
            for _ = 1, n do
                M.T = M.T + 1 / 60
                M.frameNo = M.frameNo + 1
                mc.pos.x = mc.pos.x + dx
                for _, Fx in ipairs(fols) do Fx.drawPos.x = Fx.drawPos.x + dx end
                M.run_hook("Think")
                M.run_hook("PreRender")
                for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(1) end end
                coroutine.yield()
            end
        end)
        frames(30)
        if jit and jit.off then jit.off() jit.flush() end
        local camStarts = M.camStarts
        M.camStarts = nil
        collectgarbage("collect")
        collectgarbage("stop")
        local kb, cnt = 0, 0
        for _ = 1, n do
            coroutine.resume(co)
            local m0 = mockkb
            local k0 = collectgarbage("count")
            hk(false, false, false)
            hp()
            kb = kb + (collectgarbage("count") - k0) - (mockkb - m0)
            cnt = cnt + 1
        end
        collectgarbage("restart")
        if jit and jit.on then jit.on() end
        M.camStarts = camStarts
        local per = kb * 1024 / cnt
        info("%s: %.1f bytes of Lua garbage of its own a frame (%d frames, the JIT off)", label, per, n)
        check(per < 16, "%s: no Lua garbage of its own per frame (%.1f bytes)", label, per)
    end
    measure(300, {}, 0, "standing, the sun check on")
    measure(300, {}, 25, "at speed, the sun check on")
    sunlit(false)
    measure(300, {}, 0, "standing, the check off (0.9.9b's path)")
    measure(300, {}, 25, "at speed, the check off (0.9.9b's path)")
    sunlit(true)
    for i = 1, 8 do F[i] = follower(mc.pos.x, mc.pos.y + 300 * i) end
    RunConsoleCommand("gsa1_sunshadow_followers", "8")
    frames(15)
    measure(300, F, 25, "at speed with 8 followers' shadows, the check on")
    sunlit(false)
    measure(300, F, 25, "at speed with 8 followers' shadows, as 0.9.9b")
    sunlit(true)
    -- through bars of shade, so that the fades run too, and teleports, so that the values are emptied
    do
        local bars = {}
        for k = 0, 60 do bars[#bars + 1] = { mc.pos.x + 400 + k * 300, mc.pos.x + 500 + k * 300, -3000, 3000, GZ, GZ + 200 } end
        W.boxes = bars
        measure(300, F, 25, "at speed with 8 followers' shadows through bars of shade")
        W.boxes = {}
    end
    -- over curbs under a slanted light: the risers' points read their neighbours, the second rays run
    do
        sunmap("80 30 0", -60, 247)
        local curbs = {}
        for k = 0, 140 do curbs[#curbs + 1] = { mc.pos.x + 200 + k * 64, mc.pos.x + 248 + k * 64, -3000, 3000, GZ, GZ + 16 } end
        W.boxes = curbs
        frames(5)
        local P = S.sunfield.probe
        P[0], P[1] = S.PROBE_EACH, S.PROBE_EACH       -- (no "sun check sample" line in these frames: that one line is the 7 bytes above)
        measure(300, {}, 25, "at speed over curbs under a slanted light")
        W.boxes = {}
        read_map(bsp(REMASTER))
        S.ResetSun()
        frames(15)
    end
    for nm, fn in pairs(wrapped) do gsa1[nm] = fn end
    -- the time of the Lua in the mock, the JIT on: what the check and the lattice add
    local function ms(fols, dx)
        local t, n = 0, 240
        for _ = 1, n do
            M.T = M.T + 1 / 60
            M.frameNo = M.frameNo + 1
            mc.pos.x = mc.pos.x + dx
            for _, Fx in ipairs(fols) do Fx.drawPos.x = Fx.drawPos.x + dx end
            M.run_hook("Think")
            M.run_hook("PreRender")
            for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(1) end end
            local t0 = host_clock()
            hk(false, false, false)
            t = t + host_clock() - t0
        end
        return t * 1000 / n
    end
    sunlit(false)
    frames(10)
    ms(F, 25)
    local a = ms(F, 25)
    sunlit(true)
    frames(10)
    ms(F, 25)
    local b = ms(F, 25)
    info("the main view's hook in the mock at speed, 1 + 8 shadows, the mock's traces cheap: %.3f ms a frame as 0.9.9b, %.3f ms now", a, b)
    for i = #F, 1, -1 do drop(F[i]); F[i] = nil end
    RunConsoleCommand("gsa1_sunshadow_followers", "3")
    frames(12)
    W.boxes = {}
    place(0, 0)
    settle(5)
end
hook.Remove("Think", "feat_sunlit_levels")
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
