-- feat_climbcam_test.lua - the climbing camera (0.9.9c, addon/lua/gsa1/feat/cl_climbcam.lua and the seam GSA1.ClimbEye in cl_character.lua's CalcView).
-- The owner's note, in game, gm_construct_remaster_csm: "When Knuckles climbs a wall, the camera will sometimes break", and what breaking looked
-- like: "It would go into the wall". The real CalcView in Garry's Mod's own LuaJIT (tests/lua_mock.lua) against walls of this test's own: convex brushes
-- and the classic box-against-brush clip (a start inside a brush is reported, and that brush does not stop the sweep; 0.9.9b's two traces trusted such a start). That
-- rule is from memory of the engine: what Garry's Mod really does there can only be seen in the game, the owner's checklist.
--   lua_host tests/feat_climbcam_test.lua <tests dir> <addon/lua dir>
--   lua_host tests/feat_climbcam_test.lua <tests dir> <addon/lua dir of the frozen 0.9.9b> record   > tests/feat_climbcam_recording.txt
-- 1 the option and its row. 2 the eye stays out of the wall at every view and tilt, walls facing every way, also with the collision behind the visible
-- face. 3 the same along whole climbs, up, down, across, and every way off the wall, chase and first person. 4 a trace that starts inside something is
-- noticed. 5 no jump: entering and leaving, measured against a plain gate on mode 24 (the negative control). 6 the game's own climb
-- (build/x86_64-windows/climb_trajectory.txt, tests/feat_climbcam_binding_test.cpp writes it when there is a disc). 7 everything else moves exactly as
-- 0.9.9b, frame for frame, against the recording tests/feat_climbcam_recording.txt made from the frozen release. 8 the Lua garbage stays flat. 9 the whole
-- client frame. 10 every way a climb ends: up left on the wall for seconds, a body stuck in or gone through a wall or out of reach, a hit, a switch of character, a re-creation,
-- the option; and one line in the session log for each.
local tests, root, run_mode = arg[1] or "tests", arg[2] or "addon/lua", arg[3]
local RECORD = run_mode == "record"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
local groot = string.match(tests, "^(.*)[/\\]tests[/\\]?$") or "."
if not RECORD then print("G-SA1 feat_climbcam_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")") end
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end
local abs, sqrt, max, min, floor, rad, cos, sin = math.abs, math.sqrt, math.max, math.min, math.floor, math.rad, math.cos, math.sin

local CENTER, EYES = 22.8, 36.0       -- MEASURED: gsa1.CharacterInfo(3), feat_climbcam_binding_test

-- the world: convex brushes, each a list of { nx, ny, nz, d } (inside: n . p <= d) -----------------------------------------------------------------
local brushes = {}
local function clear_world() brushes = {} end
local function plane_brush(planes) brushes[#brushes + 1] = planes end
-- an axis-aligned box in world coordinates
local function add_box(x0, y0, z0, x1, y1, z1)
    plane_brush({ { 1, 0, 0, x1 }, { -1, 0, 0, -x0 }, { 0, 1, 0, y1 }, { 0, -1, 0, -y0 }, { 0, 0, 1, z1 }, { 0, 0, -1, -z0 } })
end
-- a wall's frame: a along the normal n (out of the wall), b along the horizontal tangent t, c along w = n x t (straight up on a vertical wall)
local function wall_frame(nx, ny, nz)
    local l = sqrt(nx * nx + ny * ny)
    local tx, ty = -ny / l, nx / l
    local w = { ny * 0 - nz * ty, nz * tx - nx * 0, nx * ty - ny * tx }
    return { n = { nx, ny, nz }, t = { tx, ty, 0 }, w = w }
end
local function dot3(p, x, y, z) return p[1] * x + p[2] * y + p[3] * z end
local function to_world(F, a, b, c)
    return F.n[1] * a + F.t[1] * b + F.w[1] * c, F.n[2] * a + F.t[2] * b + F.w[2] * c, F.n[3] * a + F.t[3] * b + F.w[3] * c
end
-- a box in the wall's frame
local function add_wall_box(F, a0, a1, b0, b1, c0, c1)
    local n, t, w = F.n, F.t, F.w
    plane_brush({ { n[1], n[2], n[3], a1 }, { -n[1], -n[2], -n[3], -a0 }, { t[1], t[2], t[3], b1 }, { -t[1], -t[2], -t[3], -b0 },
                  { w[1], w[2], w[3], c1 }, { -w[1], -w[2], -w[3], -c0 } })
end

-- the classic box clip: start inside and end inside = all solid, fraction 0; start inside and end outside = start solid, that brush does not stop the sweep
local function clip(sx, sy, sz, ex, ey, ez, h)
    local frac, startsolid, allsolid, left = 1, false, false, 0
    for b = 1, #brushes do
        local P = brushes[b]
        local enter, leave, startout, getout, skip = -1, 1, false, false, false
        for i = 1, #P do
            local p = P[i]
            local px, py, pz = p[1], p[2], p[3]
            local dist = p[4] + h * (abs(px) + abs(py) + abs(pz))
            local d1 = px * sx + py * sy + pz * sz - dist
            local d2 = px * ex + py * ey + pz * ez - dist
            if d2 > 0 then getout = true end
            if d1 > 0 then startout = true end
            if d1 > 0 and d2 >= 0 then
                skip = true
                break
            end
            if d1 > 0 or d2 > 0 then
                if d1 > d2 then
                    local f = (d1 - 0.03125) / (d1 - d2)
                    if f > enter then enter = f end
                else
                    local f = (d1 + 0.03125) / (d1 - d2)
                    if f < leave then leave = f end
                end
            end
        end
        if not skip then
            if not startout then
                startsolid = true
                if not getout then
                    allsolid, frac, left = true, 0, 1
                elseif leave ~= 1 and leave > left then
                    left = leave
                end
            elseif enter < leave and enter > -1 and enter < frac then
                frac = max(0, enter)
            end
        end
    end
    return frac, startsolid, allsolid, left
end
M.ntrace = 0
util.TraceHull = function(t)
    M.ntrace = M.ntrace + 1
    if M.other_mask and t.mask ~= MASK_SOLID_BRUSHONLY then M.other_mask = M.other_mask + 1 end
    local s, e = t.start, t.endpos
    local f, ss, as, left = clip(s.x, s.y, s.z, e.x, e.y, e.z, t.maxs and t.maxs.x or 0)
    if M.forceSolid and M.forceSolid(t) then ss, as, f = true, true, 0 end
    local out = t.output or {}
    out.Fraction, out.StartSolid, out.AllSolid, out.FractionLeftSolid, out.Hit = f, ss, as, left, f < 1
    out.HitPos = Vector(s.x + f * (e.x - s.x), s.y + f * (e.y - s.y), s.z + f * (e.z - s.z))
    return out
end
-- the box +-h at a point overlaps a brush (h 0: the point is inside one)
local function overlaps(x, y, z, h)
    for b = 1, #brushes do
        local P = brushes[b]
        local inside = true
        for i = 1, #P do
            local p = P[i]
            if p[1] * x + p[2] * y + p[3] * z - p[4] - h * (abs(p[1]) + abs(p[2]) + abs(p[3])) > 0 then
                inside = false
                break
            end
        end
        if inside then return true end
    end
    return false
end

-- 0.9.9b's eye, by its two traces
local function old_eye(f, pitch, yaw, dist, height, center)
    local cz = f.z + (center or CENTER)
    local tf = clip(f.x, f.y, cz, f.x, f.y, cz + height, 5)
    local hz = cz + tf * height
    local cp, sp, cy, sy = cos(rad(pitch)), sin(rad(pitch)), cos(rad(yaw)), sin(rad(yaw))
    local ex, ey, ez = f.x - cp * cy * dist, f.y - cp * sy * dist, hz + sp * dist
    local bf = clip(f.x, f.y, hz, ex, ey, ez, 5)
    return f.x + bf * (ex - f.x), f.y + bf * (ey - f.y), hz + bf * (ez - hz)
end

-- the addon -------------------------------------------------------------------------------------------------------------------------------------
local G = M.module({})
GSA1 = nil
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
if not RECORD then check(ok_load, "the addon loads (%s)", tostring(err_load or "ok")) end
if not ok_load then
    if RECORD then error(err_load) end
    return done()
end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -100000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -100000 }
local calc = M.hooks.CalcView and M.hooks.CalcView.gsa1_view
local C

local function spawn(name)
    if GSA1.Char then GSA1.Remove(false) end
    M.player.view_entity = nil
    GSA1.Spawn(name or "knuckles")
    C = GSA1.Char
    if C and (name == nil or name == "knuckles") then C.info.center, C.info.eyes = CENTER, EYES end
    return C
end
local function set_cv(name, v) RunConsoleCommand(name, tostring(v)) end
-- one frame's state, as Think leaves it: gsa1.GetState's table, gsa1.Render's root and alpha
local nstep = 0
local function feed(mode, x, y, z, ux, uy, uz, step, alpha)
    local st = C.state
    st.mode, st.upx, st.upy, st.upz = mode, ux, uy, uz
    if step then
        st.step = step
    else
        nstep = nstep + 2
        st.step = nstep
    end
    C.drawPos:SetUnpacked(x, y, z)
    C.alpha = alpha or 0
end
local EYE0 = Vector(0, 0, 64)
local function next_frame(dt)
    M.frameNo = M.frameNo + 1
    M.dt = dt or 1 / 60
end
local function view_of(pitch, yaw)
    return calc(M.player, EYE0, Angle(pitch, yaw, 0), 92.5, 3, 30000)
end
local function fresh()     -- a new climb, no earlier frame
    if C then C.climbCam = nil end
    if GSA1.view then GSA1.view.frame = nil end
end

-- a climb, pair by pair in the wall's frame (what the game does, MEASURED by feat_climbcam_binding_test's scenes): the glide comes in, the grab puts the
-- position on the polygon and the up vector on the wall's normal in one pair, the rest, the move, a way off the wall. Frames: 60 a second, the root
-- between two pairs by alpha, as gsa1.Render returns it
local function pair_path(opts)
    local P = {}
    local function add(mode, a, b, c, ua, uc) P[#P + 1] = { mode = mode, a = a, b = b, c = c, ua = ua, uc = uc } end
    local a, b, c = 150, opts.b or 0, (opts.c or 90) - 14
    while a > 13.5 do
        add(11, a, b, c, 0, 1)
        a = a - 13.5
    end
    a, c = 0, c + 14
    for _ = 1, opts.rest or 30 do add(24, a, b, c, 1, 0) end
    for _ = 1, opts.up or 0 do
        c = c + 6.35
        add(24, a, b, c, 1, 0)
    end
    for _ = 1, opts.down or 0 do
        c = c - 6.35
        add(24, a, b, c, 1, 0)
    end
    for _ = 1, opts.across or 0 do
        b = b + 6.35
        add(24, a, b, c, 1, 0)
    end
    local leave = opts.leave
    if leave == "over" then
        for _ = 1, 18 do
            a, c = a - 0.91, c + 2.55
            add(25, a, b, c, 1, 0)
        end
        add(1, a, b, c, 1, 0)
        for i = 1, 4 do
            local th = rad(22.5 * i)
            c = c + 2
            add(9, a, b, c, cos(th), sin(th))
        end
        for _ = 1, 40 do add(1, a, b, c, 0, 1) end
    elseif leave == "jump" then
        a, c = a + 23.44, c - 16.8
        add(6, a, b, c, 0, 1)
        for _ = 1, 40 do
            a, c = a + 6, c + 5
            add(6, a, b, c, 0, 1)
        end
    elseif leave == "down" then
        c = c - 3.2
        add(1, a, b, c, 1, 0)
        a = a + 13.68
        for i = 1, 4 do
            local th = rad(22.5 * i)
            c = c - 1
            add(9, a, b, c, cos(th), sin(th))
        end
        for _ = 1, 40 do add(9, a, b, c, 0, 1) end
    elseif leave == "fall" then     -- the wall ended: the game counts 6 pairs, then falls with the position still on the plane for a moment
        for _ = 1, 6 do add(24, a, b, c, 1, 0) end
        for i = 1, 40 do
            a, c = a + (i > 3 and 3 or 0), c - i * 0.8
            add(9, a, b, c, 0, 1)
        end
    end
    return P
end
-- pairs -> frames, world coordinates
local function frames_of(P, F, hz)
    hz = hz or 60
    local per = hz / 30
    local out = {}
    for k = 1, #P do
        local p, q = P[k], P[max(k - 1, 1)]
        for i = 0, per - 1 do
            local al = i / per
            local x, y, z = to_world(F, q.a + (p.a - q.a) * al, q.b + (p.b - q.b) * al, q.c + (p.c - q.c) * al)
            local ux, uy, uz = to_world(F, p.ua, 0, p.uc)
            out[#out + 1] = { mode = p.mode, x = x, y = y, z = z, ux = ux, uy = uy, uz = uz, step = k * 2, alpha = al, a = q.a + (p.a - q.a) * al,
                              c = q.c + (p.c - q.c) * al }
        end
    end
    return out
end
local function play_frame(f, dt)
    next_frame(dt)
    feed(f.mode, f.x, f.y, f.z, f.ux, f.uy, f.uz, f.step, f.alpha)
end

-- 7 first in the file: the recording. Each scenario's frames go through fn(i, record) ------------------------------------------------------------------
-- FNV-1a (shifts: LuaJIT's numbers would lose the low bits of the product)
local band, bxor, lshift, tobit, tohex = bit.band, bit.bxor, bit.lshift, bit.tobit, bit.tohex
local function hash_of(s)
    local h = tobit(0x811C9DC5)
    for i = 1, #s do
        h = bxor(h, string.byte(s, i))
        h = tobit(h + lshift(h, 1) + lshift(h, 4) + lshift(h, 7) + lshift(h, 8) + lshift(h, 24))
    end
    return tohex(h)
end
local function frame_line(v, traces)
    if not v then return "nil " .. traces end
    local o, a = v.origin, v.angles
    return string.format("%.17g %.17g %.17g %.17g %.17g %.17g %.17g %s %d", o.x, o.y, o.z, a.p, a.y, a.r, v.fov or -1, tostring(v.drawviewer), traces)
end
local F_REC = wall_frame(0, 1, 0)
local function world_rec()
    clear_world()
    add_box(-4096, -4096, -64, 4096, 4096, 0)
    add_wall_box(F_REC, -64, 8, -2048, 2048, -16, 320)
    add_wall_box(F_REC, -64, 0, -2048, 2048, 320, 480)
end
local function rec_view(i)
    local n0 = M.ntrace
    local v = view_of(-30 + (i * 3) % 70, (i * 7) % 360)
    return v, M.ntrace - n0
end
local SCENARIOS = {}
local function scenario(name, fn) SCENARIOS[#SCENARIOS + 1] = { name = name, fn = fn } end
-- Knuckles walks up to and into the wall (0.9.9b's trust of a start inside stays as it is, everywhere but on the climb), away again
scenario("knuckles_walk", function(rec)
    spawn("knuckles")
    for i = 1, 200 do
        next_frame()
        local y = 120 - i
        feed(i % 2 == 0 and 2 or 1, i * 0.5, y, 0, 0, 0, 1)
        local v, t = rec_view(i)
        rec(v, t)
    end
end)
-- every other mode of Knuckles, also with a tilted up vector
scenario("knuckles_modes", function(rec)
    spawn("knuckles")
    local i = 0
    for _, mode in ipairs({ 1, 2, 3, 6, 9, 11, 12, 13, 18, 19, 20, 21, 23, 25, 26, 27, 42, 43, 44, 45, 48, 53 }) do
        for k = 1, 14 do
            i = i + 1
            next_frame()
            local th = rad(k * 6)
            feed(mode, k * 3, 40 + k, 60 + k, 0, sin(th), cos(th))
            local v, t = rec_view(i)
            rec(v, t)
        end
    end
end)
-- another character's mode 24 is not a climb
for _, name in ipairs({ "sonic", "tails", "amy", "gamma", "big", "eggman", "tikal", "supersonic" }) do
    scenario(name .. "_mode24", function(rec)
        spawn(name)
        C.info.center, C.info.eyes = 20, 28
        for i = 1, 60 do
            next_frame()
            feed(24, i, 2, 40 + i, 0, 1, 0)
            local v, t = rec_view(i)
            rec(v, t)
        end
        M.othersState = M.othersState or C.climbCam
    end)
end
-- the whole climb with the option off, chase and first person
scenario("climb_off", function(rec)
    spawn("knuckles")
    set_cv("gsa1_cam_climb", 0)
    local fr = frames_of(pair_path({ up = 20, leave = "over", rest = 20 }), F_REC)
    for i, f in ipairs(fr) do
        play_frame(f)
        local v, t = rec_view(i)
        rec(v, t)
    end
    set_cv("gsa1_cam_distance", 0)
    for i, f in ipairs(fr) do
        play_frame(f)
        local v, t = rec_view(i)
        rec(v, t)
    end
    set_cv("gsa1_cam_distance", 150)
    set_cv("gsa1_cam_climb", 1)
end)
scenario("first_person", function(rec)
    spawn("knuckles")
    set_cv("gsa1_cam_distance", 0)
    for i = 1, 60 do
        next_frame()
        feed(2, i * 2, 60, 5 + i, 0, 0, 1)
        local v, t = rec_view(i)
        rec(v, t)
    end
    set_cv("gsa1_cam_distance", 150)
end)
scenario("camera_settings", function(rec)
    spawn("knuckles")
    local i = 0
    for _, s in ipairs({ { 60, -10 }, { 1000, 128 }, { 1, 0 }, { 300, -64 } }) do
        set_cv("gsa1_cam_distance", s[1])
        set_cv("gsa1_cam_height", s[2])
        for _ = 1, 40 do
            i = i + 1
            next_frame()
            feed(1, i * 2, 200 - i, 30, 0, 0, 1)
            local v, t = rec_view(i)
            rec(v, t)
        end
    end
    set_cv("gsa1_cam_distance", 150)
    set_cv("gsa1_cam_height", 20)
end)
scenario("view_entity", function(rec)
    spawn("knuckles")
    M.player.view_entity = { removed = false }
    for i = 1, 20 do
        next_frame()
        feed(24, 0, 0, 100, 0, 1, 0)
        local v, t = rec_view(i)
        rec(v, t)
    end
    M.player.view_entity = nil
end)
-- switching and re-creating with no climb going on, also right after a climb has handed back: nothing of the climbing camera comes along
scenario("switch_no_climb", function(rec)
    spawn("knuckles")
    local i = 0
    local function walk(mode, n)
        for _ = 1, n do
            i = i + 1
            next_frame()
            feed(mode, i * 0.5, 120 - i * 0.2, 0, 0, 0, 1)
            local v, t = rec_view(i)
            rec(v, t)
        end
    end
    walk(2, 30)
    GSA1.Spawn("sonic")
    C = GSA1.Char
    C.info.center, C.info.eyes = 20, 28
    walk(2, 30)
    GSA1.Spawn("knuckles")
    C = GSA1.Char
    C.info.center, C.info.eyes = CENTER, EYES
    walk(1, 30)
    GSA1.Recreate("a test")
    C = GSA1.Char
    C.info.center, C.info.eyes = CENTER, EYES
    walk(2, 30)
end)
-- the climb with the option ON: compared only before the first frame of mode 24 and after the camera has handed back (7 below)
local CLIMB_ON_PATH = { up = 20, leave = "over", rest = 20 }
scenario("climb_on", function(rec)
    spawn("knuckles")
    -- this one's wall ends at the top the path goes over: the body comes out on top of it and walks on, in the open
    clear_world()
    add_box(-4096, -4096, -64, 4096, 4096, 0)
    add_wall_box(F_REC, -2048, 0, -2048, 2048, -16, 90 + CLIMB_ON_PATH.up * 6.35)
    local fr = frames_of(pair_path(CLIMB_ON_PATH), F_REC)
    for i, f in ipairs(fr) do
        play_frame(f)
        local v, t = rec_view(i)
        rec(v, t)
    end
    -- standing on, then walking away: well after the climb
    for i = 1, 120 do
        next_frame()
        local l = fr[#fr]
        feed(i < 60 and 1 or 2, l.x, l.y - i, l.z, 0, 0, 1)
        local v, t = rec_view(i)
        rec(v, t)
    end
end)
local function run_scenario(sc)
    world_rec()
    local lines = {}
    sc.fn(function(v, traces) lines[#lines + 1] = frame_line(v, traces) end)
    return lines
end

if RECORD then
    for _, sc in ipairs(SCENARIOS) do
        local lines = run_scenario(sc)
        local h = {}
        for i, l in ipairs(lines) do h[i] = hash_of(l) end
        host_write(sc.name .. " " .. #lines .. " " .. table.concat(h, " ") .. "\n")
    end
    return true
end

local K = GSA1.ClimbCam
local function S() return C and C.climbCam end

-- 1. the option and its row ---------------------------------------------------------------------------------------------------------------------------------
do
    local e = GSA1.CONVARS and GSA1.CONVARS.gsa1_cam_climb
    check(e and e.default == "1" and e.min == 0 and e.max == 1 and not e.server, "gsa1_cam_climb: a client ConVar, default 1, 0 or 1")
    check(M.convars.gsa1_cam_climb and M.convars.gsa1_cam_climb:GetString() == "1", "it is 1 on a fresh install")
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    local page
    for _, m in ipairs(M.menu) do if m.class == "gsa1_camera" then page = m end end
    local calls = {}
    local any = setmetatable({}, { __index = function(t) return function() return t end end })
    local P = setmetatable({}, { __index = function(_, k)
        return function(_, ...)
            calls[#calls + 1] = { k, ... }
            return any
        end
    end })
    local built = page and pcall(page.cpanel, P)
    local box, help
    for i, c in ipairs(calls) do
        if c[1] == "CheckBox" and c[3] == "gsa1_cam_climb" then
            box = c
            help = calls[i + 1]
        end
    end
    check(built and box and help and help[1] == "ControlHelp" and string.find(tostring(help[2]), "wall", 1, true) ~= nil,
        "Options > G-SA1 > Camera has its check box: \"%s\" with a help line", box and tostring(box[2]) or "-")
end
if not calc then
    check(false, "the CalcView hook gsa1_view exists")
    return done()
end

-- 2. the eye at every view and tilt ------------------------------------------------------------------------------------------------------------------------------
-- the walls, in the wall's frame with the collision polygon at a = 0, where Knuckles' position sits. `face`: how far the visible face stands in front of it
local WALLS = {
    { name = "plain wall, the polygon on the visible face", face = 0, build = function(F, top)
        add_wall_box(F, -64, 0, -2048, 2048, -64, top or 512)
    end },
    { name = "16 thick and backed: the polygon 8 behind the visible face (the owner's wall, the thin-wall rule at its default 16)", face = 8, build = function(F, top)
        add_wall_box(F, -8, 8, -2048, 2048, -64, top or 512)
        add_wall_box(F, -300, -8, -2048, 2048, -64, top or 512)
    end },
    { name = "64 thick: the polygon 32 behind the visible face (the thin-wall slider at its most, 64)", face = 32, build = function(F, top)
        add_wall_box(F, -32, 32, -2048, 2048, -64, top or 512)
    end },
}
local FACINGS = {
    { "+y", 0, 1, 0 }, { "-y", 0, -1, 0 }, { "+x", 1, 0, 0 }, { "-x", -1, 0, 0 }, { "diagonal", 0.70710678, 0.70710678, 0 }, { "diagonal 2", -0.8, 0.6, 0 },
    { "a wall leaning back by 30 degrees", 0, 0.8660254, 0.5 },
    { "a wall leaning over by 20 degrees", 0, 0.9396926, -0.3420201 },
}
local YAWS, PITCHES = {}, { -89, -60, -30, -10, 0, 20, 40, 60, 89 }
for y = 0, 345, 15 do YAWS[#YAWS + 1] = y end
-- the view's direction in the wall's frame: `rel` degrees from the wall's normal: 0 = looking out of the wall (away), 180 = looking at it, 90 = along it
local function yaw_of(F, rel)
    return math.deg(math.atan2(F.n[2], F.n[1])) + rel
end
-- one spot: every view for `settle` frames (the view's distance eases out over 18), counting what is wrong
local function sweep(F, wall, spot_c, dist, height, out)
    set_cv("gsa1_cam_distance", dist)
    set_cv("gsa1_cam_height", height)
    local x, y, z = to_world(F, 0, 0, spot_c)
    local base = yaw_of(F, 0)
    fresh()
    for _, pitch in ipairs(PITCHES) do
        for _, rel in ipairs(YAWS) do
            local yaw = base + rel
            for k = 1, 20 do
                next_frame()
                feed(24, x, y, z, F.n[1], F.n[2], F.n[3], k * 2, 0)
                local v = view_of(pitch, yaw)
                out.views = out.views + 1
                local o = v and v.origin
                if not o or overlaps(o.x, o.y, o.z, 0) then
                    out.inside = out.inside + 1
                elseif overlaps(o.x, o.y, o.z, 4.9) then
                    out.close = out.close + 1
                end
                if o then
                    local a = dot3(F.n, o.x, o.y, o.z)
                    if a < wall.face + 4.9 then out.past = out.past + 1 end
                end
            end
            local v = view_of(pitch, yaw)
            local o = v and v.origin
            if o and K then
                -- settled: looking at the wall or along it, the eye is the whole way out; out of the wall's way nothing else stands here
                local S0 = S()
                if S0 and S0.ax then
                    local hz = S0.az + clip(S0.ax, S0.ay, S0.az, S0.ax, S0.ay, S0.az + height, 5) * height
                    local d = sqrt((o.x - S0.ax) ^ 2 + (o.y - S0.ay) ^ 2 + (o.z - hz) ^ 2)
                    local cp, sp = cos(rad(pitch)), sin(rad(pitch))
                    local fwd_a = cp * cos(rad(rel)) * sqrt(F.n[1] ^ 2 + F.n[2] ^ 2) - sp * F.n[3]
                    if out.open and fwd_a < -0.01 and d < dist - 0.5 then out.short = out.short + 1 end
                end
            end
        end
    end
end
spawn("knuckles")
for wi, wall in ipairs(WALLS) do
    local totals = { views = 0, inside = 0, close = 0, past = 0, short = 0, open = true }
    local facings = FACINGS
    for fi, fc in ipairs(facings) do
        local F = wall_frame(fc[2], fc[3], fc[4])
        clear_world()
        wall.build(F)
        sweep(F, wall, 100, 150, 20, totals)
    end
    check(totals.views > 0 and totals.inside == 0, "the eye is never inside the wall: %s, %d facings, %d views x %d tilts (%d frames, %d inside)", wall.name,
        #facings, #YAWS, #PITCHES, totals.views, totals.inside)
    check(totals.close == 0 and totals.past == 0, "  and its +-5 box stays out of the wall, on the open side of the visible face (%d close, %d past it)", totals.close, totals.past)
    check(totals.short == 0, "  looking at the wall or along it, the eye is the whole way out (%d short)", totals.short)
end
-- the owner's settings, 120 / 6, at the owner's two spots: this test's copy of that wall (the map's brushes 442, 612, 444, 2400; a window sill above z 112)
do
    local F = wall_frame(0, 1, 0)
    clear_world()
    add_wall_box(F, -8, 8, -272, 496, -16, 112)         -- 442, y -1040..-1024, seen from the polygon at y -1032
    add_wall_box(F, -360, -8, -448, 496, 48, 112)       -- 612
    add_wall_box(F, -120, 0, -80, 48, 112, 240)         -- 444: the window's back
    add_wall_box(F, 0, 8, -80, 48, 112, 136)            -- 2400: the sill
    add_box(-4096, -4096, -80, 4096, 4096, -16)
    local t = { views = 0, inside = 0, close = 0, past = 0, short = 0 }
    -- sweep() places the position at b = 0, c: the wall's x 1296 here; the notes were at 1283 and 1329, both on this wall
    sweep(F, { face = -1000 }, 86, 120, 6, t)
    sweep(F, { face = -1000 }, 107, 120, 6, t)
    check(t.views > 0 and t.inside == 0 and t.close == 0, "the owner's wall at camera 120 / 6, the notes' heights 86 and 107: %d frames, %d inside, %d with the box in it", t.views, t.inside, t.close)
end
set_cv("gsa1_cam_distance", 150)
set_cv("gsa1_cam_height", 20)

-- 3. whole climbs, every way off the wall, chase and first person ------------------------------------------------------------------------------------------------
local PATHS = {
    { "up the wall and over the top", { up = 20, rest = 20, leave = "over" } },
    { "up, then jumping off", { up = 12, rest = 20, leave = "jump" } },
    { "down the wall, off at the bottom", { down = 8, rest = 20, c = 140, leave = "down" } },
    { "across", { across = 40, rest = 20, leave = "fall" } },
}
local VIEWS = { { 0, 0 }, { 0, 45 }, { 0, 90 }, { 0, 135 }, { 0, 180 }, { 0, 225 }, { 0, 270 }, { 0, 315 }, { 30, 0 }, { 30, 90 }, { 30, 180 }, { -30, 0 }, { -30, 90 }, { -30, 180 }, { 70, 0 }, { -70, 180 } }
local function top_of(opts)    -- over the top: the wall ends where the path leaves it
    return opts.leave == "over" and (opts.c or 90) + (opts.up or 0) * 6.35 or nil
end
local function climb_world(F, wall, opts)
    clear_world()
    wall.build(F, top_of(opts))
    -- a floor of the wall's world, far below these paths
    plane_brush({ { 0, 0, 1, -40 }, { 0, 0, -1, 200 }, { 1, 0, 0, 4096 }, { -1, 0, 0, 4096 }, { 0, 1, 0, 4096 }, { 0, -1, 0, 4096 } })
end
for _, fp in ipairs({ false, true }) do
    set_cv("gsa1_cam_distance", fp and 0 or 150)
    local frames, inside, close = 0, 0, 0
    for _, wall in ipairs(WALLS) do
        for _, fc in ipairs(FACINGS) do
            local F = wall_frame(fc[2], fc[3], fc[4])
            for _, path in ipairs(PATHS) do
                climb_world(F, wall, path[2])
                local fr = frames_of(pair_path(path[2]), F)
                local first24, last24
                for i, f in ipairs(fr) do
                    if f.mode == 24 then
                        first24 = first24 or i
                        last24 = i
                    end
                end
                for _, vw in ipairs(VIEWS) do
                    fresh()
                    local base = yaw_of(F, 0)
                    for i, f in ipairs(fr) do
                        play_frame(f)
                        local v = view_of(vw[1], base + vw[2])
                        -- judged from the grab until 0.67 s after the wall: before and well after that it moves as 0.9.9b
                        if i >= first24 and i <= last24 + 40 then
                            frames = frames + 1
                            local o = v and v.origin
                            if not o or overlaps(o.x, o.y, o.z, 0) then
                                inside = inside + 1
                            elseif overlaps(o.x, o.y, o.z, 4.9) then
                                close = close + 1
                            end
                        end
                    end
                end
            end
        end
    end
    check(frames > 0 and inside == 0 and close == 0, "%s: whole climbs, %d paths x %d walls x %d facings x %d views: %d frames judged, %d inside the wall, %d with the box in it",
        fp and "first person" or "the chase camera", #PATHS, #WALLS, #FACINGS, #VIEWS, frames, inside, close)
end
set_cv("gsa1_cam_distance", 150)
-- the first-person eye on the wall: the body's middle, then as far above it as the eye stands when standing (36 - 22.8)
do
    local F = wall_frame(1, 0, 0)
    clear_world()
    WALLS[2].build(F)
    set_cv("gsa1_cam_distance", 0)
    fresh()
    local fr = frames_of(pair_path({ rest = 60 }), F)
    local v
    for _, f in ipairs(fr) do
        play_frame(f)
        v = view_of(0, 180)
    end
    local o = v and v.origin
    local l = fr[#fr]
    check(o and abs(o.x - (l.x + CENTER)) < 0.01 and abs(o.y - l.y) < 0.01 and abs(o.z - (l.z + EYES - CENTER)) < 0.01,
        "first person on a wall: the eye is %.1f out of the polygon, %.1f above the position (wanted %.1f, %.1f)", o and o.x - l.x or -1, o and o.z - l.z or -1, CENTER, EYES - CENTER)
    set_cv("gsa1_cam_distance", 150)
end
-- the view itself is never changed: the same angles and field of view
do
    local F = wall_frame(0, 1, 0)
    clear_world()
    WALLS[1].build(F)
    fresh()
    next_frame()
    feed(24, 0, 0, 100, 0, 1, 0, 2, 0)
    local v = view_of(12, 34)
    check(v and v.angles.p == 12 and v.angles.y == 34 and v.fov == 92.5 and v.drawviewer == false, "while climbing the view keeps your angles and field of view")
end

-- 4. a trace that starts inside something ------------------------------------------------------------------------------------------------------------------------
do
    set_cv("gsa1_cam_height", 20)
    local F = wall_frame(0, 1, 0)
    local function at(mode_, x, y, z)
        next_frame()
        feed(mode_, x, y, z, 0, 1, 0, nil, 0)
    end
    -- (a) the anchor in the wall, on the very first frame: found along the wall's normal, the nearest open place
    clear_world()
    WALLS[3].build(F)
    fresh()
    C.climbCam = nil
    at(24, 0, 0, 100)
    local v = view_of(0, -90)
    local S0 = S()
    check(v and S0 and S0.solid and S0.solid >= 1 and not overlaps(v.origin.x, v.origin.y, v.origin.z, 4.9), "the first frame in the wall (the anchor starts 32 units deep): noticed (%s), the eye is out",
        S0 and tostring(S0.solid) or "-")
    check(S0 and S0.ay and abs(S0.ay - (32 + 5)) < 0.1, "  the anchor is the nearest open place along the wall's normal: %.2f out of the polygon (the box touches the face at 37)", S0 and S0.ay or -1)
    -- (b) a narrow alley: the way out along the normal is shut by the wall opposite, the way back is open
    clear_world()
    WALLS[1].build(F)
    add_wall_box(F, 24, 40, -2048, 2048, -64, 512)
    fresh()
    for _ = 1, 30 do
        at(24, 0, 0, 100)
        v = view_of(0, 90)
    end
    S0 = S()
    check(v and S0 and S0.ay and S0.ay > 18 and S0.ay < 19 and not overlaps(v.origin.x, v.origin.y, v.origin.z, 4.9),
        "a wall 24 units opposite: the anchor stays between the two (%.2f), never behind the opposite wall", S0 and S0.ay or -1)
    -- (c) a floor that overlaps the anchor all along the normal: the last open point of an earlier frame, this climb's
    clear_world()
    WALLS[1].build(F)
    plane_brush({ { 0, 0, 1, 40 }, { 0, 0, -1, 100 }, { 1, 0, 0, 4096 }, { -1, 0, 0, 4096 }, { 0, 1, 0, 4096 }, { 0, -1, 0, 4096 } })
    fresh()
    at(24, 0, 0, 100)
    view_of(0, 90)
    local down_frames, bad = 0, 0
    for i = 1, 60 do
        GSA1.view.frame = nil   -- (this climb's last open anchor, not the eye of the frame before)
        at(24, 0, 0, 100 - i)   -- the box goes into the floor at z 45
        v = view_of(0, 90)
        down_frames = down_frames + 1
        if not v or overlaps(v.origin.x, v.origin.y, v.origin.z, 4.9) then bad = bad + 1 end
    end
    S0 = S()
    check(bad == 0 and S0 and S0.earlier and S0.earlier > 0, "a floor across the anchor: the last open point takes over (%s frames), the eye stays out (%d of %d bad)", S0 and tostring(S0.earlier) or "-", bad, down_frames)
    -- (d) the first frame with no earlier point of this climb: the eye of the frame before the climb
    clear_world()
    plane_brush({ { 0, 0, 1, 500 }, { 0, 0, -1, -80 }, { 1, 0, 0, 4096 }, { -1, 0, 0, 4096 }, { 0, 1, 0, 4096 }, { 0, -1, 0, 4096 } })   -- all of z 80..500
    fresh()
    GSA1.view.origin, GSA1.view.frame = Vector(0, 300, 60), M.frameNo    -- an open place below it
    at(24, 0, 0, 100)
    v = view_of(0, 90)
    S0 = S()
    check(v and S0 and S0.earlier == 1 and not overlaps(v.origin.x, v.origin.y, v.origin.z, 4.9), "nothing open along the normal on the first frame: from the eye of the frame before (an open place), and it stays out")
    -- (e) nothing known at all: the old view, counted; no error
    fresh()
    GSA1.view.origin, GSA1.view.frame = Vector(0, 0, 200), M.frameNo    -- inside too
    at(24, 0, 0, 100)
    v = view_of(0, 90)
    S0 = S()
    do
        local x, y, z = old_eye({ x = 0, y = 0, z = 100 }, 0, 90, 150, 20)
        check(v and v.origin and S0 and S0.nowhere == 1 and S0.earlier == 0 and v.origin.x == x and v.origin.y == y and v.origin.z == z,
            "nothing open anywhere and no earlier frame: 0.9.9b's own eye for that frame, counted (nowhere %s)", S0 and tostring(S0.nowhere) or "-")
    end
    -- the same in the middle of a climb: something fills the place, the anchor's last open point too. The old traces' eye, not an eye made from the wall's up
    clear_world()
    fresh()
    for _ = 1, 20 do
        at(24, 0, 0, 100)
        view_of(0, 90)
    end
    plane_brush({ { 0, 0, 1, 130 }, { 0, 0, -1, -60 }, { 1, 0, 0, 4096 }, { -1, 0, 0, 4096 }, { 0, 1, 0, 4096 }, { 0, -1, 0, 4096 } })
    GSA1.view.frame = nil
    at(24, 0, 0, 100)
    v = view_of(0, 90)
    S0 = S()
    do
        local x, y, z = old_eye({ x = 0, y = 0, z = 100 }, 0, 90, 150, 20)
        check(v and S0 and S0.nowhere == 1 and v.origin.x == x and v.origin.y == y and v.origin.z == z, "nowhere open in the middle of a climb: 0.9.9b's own eye for that frame (%.1f %.1f %.1f)", v and v.origin.x or -1, v and v.origin.y or -1, v and v.origin.z or -1)
    end
    GSA1.view.frame = nil
    -- (f) the back trace starts inside although its start was found open (rounding; a brush that moved between the traces): the earlier distance
    clear_world()
    WALLS[1].build(F)
    fresh()
    for _ = 1, 30 do
        at(24, 0, 0, 100)
        v = view_of(0, -90)     -- looking at the wall: the whole way out
    end
    local earlier = v and v.origin.y or -1
    M.forceSolid = function(t) return t.endpos.y > 100 and t.start.y < 100 end          -- the back trace of this view only
    at(24, 0, 0, 100)
    v = view_of(0, -90)
    M.forceSolid = nil
    S0 = S()
    check(v and S0 and S0.backSolid == 1 and abs(v.origin.y - earlier) < 0.01, "the back trace starts inside: noticed, the earlier distance holds (%.1f, was %.1f)", v and v.origin.y or -1, earlier)
    -- (g) the same on the first frame: no earlier distance, so the eye at the open anchor
    fresh()
    M.forceSolid = function(t) return t.endpos.y > 100 and t.start.y < 100 end
    at(24, 0, 0, 100)
    v = view_of(0, -90)
    M.forceSolid = nil
    S0 = S()
    check(v and S0 and S0.backSolid == 1 and S0.d == 0 and abs(v.origin.y - S0.ay) < 0.01 and not overlaps(v.origin.x, v.origin.y, v.origin.z, 4.9),
        "on the first frame there is no earlier distance: the eye at the open anchor (%.1f out of the polygon), never in the wall", v and v.origin.y or -1)
    -- (h) the earlier distance would put the eye in something now: the anchor again
    clear_world()
    WALLS[1].build(F)
    fresh()
    for _ = 1, 30 do
        at(24, 0, 0, 100)
        v = view_of(0, -90)
    end
    add_wall_box(F, 60, 400, -2048, 2048, -64, 512)      -- a door came down in front
    M.forceSolid = function(t) return t.endpos.y > 100 and t.start.y < 100 end
    at(24, 0, 0, 100)
    v = view_of(0, -90)
    M.forceSolid = nil
    check(v and not overlaps(v.origin.x, v.origin.y, v.origin.z, 4.9) and abs(v.origin.y - CENTER) < 0.01, "the earlier distance is checked before it is used: blocked now, the eye at the open anchor (%.1f)", v and v.origin.y or -1)
    -- (i) a Lua error in the climbing camera: 0.9.9b's view for the frame, logged, no error in CalcView
    clear_world()
    WALLS[1].build(F)
    fresh()
    C.climbCam = setmetatable({}, { __index = function() error("a test's error") end })
    local logged, log0 = {}, GSA1.Log
    GSA1.Log = function(kind, fmt, ...)
        logged[#logged + 1] = kind
        return log0(kind, fmt, ...)
    end
    at(24, 0, 0, 100)
    local okv, ve = pcall(view_of, 0, 90)
    local nerr = 0
    for _, k in ipairs(logged) do if k == "error" then nerr = nerr + 1 end end
    local errs1 = nerr
    C.climbCam = setmetatable({}, { __index = function() error("a test's error") end })
    at(24, 0, 0, 100)
    view_of(0, 90)
    C.climbCam = setmetatable({}, { __index = function() error("a test's error") end })
    at(24, 0, 0, 100)
    view_of(0, 90)
    nerr = 0
    for _, k in ipairs(logged) do if k == "error" then nerr = nerr + 1 end end
    GSA1.Log = log0
    check(okv and ve and ve.origin and errs1 == 1 and nerr == 1 and K ~= nil, "a Lua error in the climbing camera: the frame keeps 0.9.9b's view, one line in the session log (%d), and this character goes on without it", nerr)
    C.climbOff = nil
    fresh()
    -- no alpha yet (a character's first frames): the new up at once
    C.alpha = nil
    next_frame()
    C.state.mode, C.state.upx, C.state.upy, C.state.upz, C.state.step = 24, 0, 1, 0, 2
    C.drawPos:SetUnpacked(0, 0, 100)
    v = view_of(0, 90)
    check(v and S() and S().active and S().oy > 0 and #M.reported == 0, "no alpha on the character: no error")
    fresh()
end

-- 5. no jump ---------------------------------------------------------------------------------------------------------------------------------------------------------
-- the anchor, frame by frame, against 0.9.9b's and against a plain gate on mode 24 (position + up x center while in mode 24, else straight up)
local function measure_jumps(fr, F, opts)
    opts = opts or {}
    fresh()
    local dt = opts.dt or 1 / 60
    local prev, prev_old, prev_gate, prev_root
    local worst, worst_old, worst_gate, worst_over, n_active = 0, 0, 0, 0, 0
    local first24, last24
    for i, f in ipairs(fr) do if f.mode == 24 then first24 = first24 or i last24 = i end end
    for i, f in ipairs(fr) do
        play_frame(f, dt)
        local v = view_of(0, yaw_of(F, 180))
        local S0 = S()
        local on = S0 and S0.active and S0.ax
        local A = on and { S0.ax, S0.ay, S0.az } or { f.x, f.y, f.z + CENTER }
        local old = { f.x, f.y, f.z + CENTER }
        local gate = f.mode == 24 and { f.x + f.ux * CENTER, f.y + f.uy * CENTER, f.z + f.uz * CENTER } or old
        local root = { f.x, f.y, f.z }
        if prev then
            local function dist(a, b) return sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2) end
            local d, dold, dgate, droot = dist(A, prev), dist(old, prev_old), dist(gate, prev_gate), dist(root, prev_root)
            if i >= first24 - 2 and i <= last24 + 90 then
                worst, worst_old, worst_gate = max(worst, d), max(worst_old, dold), max(worst_gate, dgate)
                worst_over = max(worst_over, d - droot)
            end
        end
        prev, prev_old, prev_gate, prev_root = A, old, gate, root
    end
    return worst, worst_old, worst_gate, worst_over
end
do
    local F = wall_frame(0, 1, 0)
    for _, path in ipairs(PATHS) do
        clear_world()
        WALLS[1].build(F, top_of(path[2]))
        local fr = frames_of(pair_path(path[2]), F)
        local w, wo, wg, over = measure_jumps(fr, F)
        check(w < wg and w <= wo + 0.01 and over <= 1000 / 60 + 0.05, "%s: the anchor's largest move in a frame %.1f (0.9.9b's %.1f, a plain gate %.1f); beyond the character's own move at most %.2f (the limit 16.67)", path[1], w, wo, wg, over)
    end
    -- other frame rates: the limit goes by time
    clear_world()
    WALLS[1].build(F, top_of(PATHS[1][2]))
    local fr30 = frames_of(pair_path(PATHS[1][2]), F, 30)
    local _, _, _, over30 = measure_jumps(fr30, F, { dt = 1 / 30 })
    check(over30 <= 1000 / 30 + 0.05, "at 30 frames a second: at most %.2f beyond the character's own move (the limit 33.33)", over30)
    local fr120 = frames_of(pair_path(PATHS[1][2]), F, 120)
    local _, _, _, over120 = measure_jumps(fr120, F, { dt = 1 / 120 })
    check(over120 <= 1000 / 120 + 0.05, "at 120 frames a second: at most %.2f beyond it (the limit 8.33)", over120)
end
-- it follows the body: on the wall the anchor is the drawn body's middle (position + up x center), at once settled after the grab
do
    local F = wall_frame(0, 1, 0)
    clear_world()
    WALLS[1].build(F)
    fresh()
    local fr = frames_of(pair_path({ rest = 40 }), F)
    local v, settle
    for i, f in ipairs(fr) do
        play_frame(f)
        v = view_of(0, 180)
        local S0 = S()
        if f.mode == 24 and S0 and S0.ax and not settle and abs(S0.ay - (f.y + CENTER)) < 0.02 and abs(S0.az - f.z) < 0.02 then settle = i end
    end
    local first24
    for i, f in ipairs(fr) do if f.mode == 24 then first24 = i break end end
    check(settle and settle - first24 <= 2, "the grab: the anchor is on the body's middle %s frames after the first frame of mode 24", tostring(settle and settle - first24))
    -- the camera hands back: exactly 0.9.9b's traces and eye on the last frame of the climb camera and after it
    fresh()
    local fr2 = frames_of(pair_path({ rest = 20, up = 10, leave = "jump" }), F)
    local handed, last_active_ok, after_bad, active_frames_after = nil, false, 0, 0
    local was_active = false
    for i, f in ipairs(fr2) do
        play_frame(f)
        local vv = view_of(10, 50)
        local S0 = S()
        local act = S0 and S0.active
        if was_active and not act then
            handed = i
            local x, y, z = old_eye(f, 10, 50, 150, 20)
            last_active_ok = abs(vv.origin.x - x) < 1e-6 and abs(vv.origin.y - y) < 1e-6 and abs(vv.origin.z - z) < 1e-6
        elseif handed then
            local x, y, z = old_eye(f, 10, 50, 150, 20)
            if abs(vv.origin.x - x) > 1e-6 or abs(vv.origin.y - y) > 1e-6 or abs(vv.origin.z - z) > 1e-6 then after_bad = after_bad + 1 end
        end
        was_active = act
    end
    check(handed and last_active_ok and after_bad == 0, "the hand back: frame %s gives 0.9.9b's eye and so does every frame after it (%d differ)", tostring(handed), after_bad)
    -- a climb that ends on a slope: up stays tilted, the camera still hands back, in the time it says
    fresh()
    local fr3 = frames_of(pair_path({ rest = 20 }), F)
    for _, f in ipairs(fr3) do
        play_frame(f)
        view_of(0, 90)
    end
    local t_back
    local l = fr3[#fr3]
    for i = 1, 300 do
        next_frame()
        feed(1, l.x, l.y + 40, l.z, 0, 0.5, 0.8660254, i * 2, 0)
        view_of(0, 90)
        local S0 = S()
        if not (S0 and S0.active) then
            t_back = i / 60
            break
        end
    end
    check(t_back and t_back > 0.9 and t_back < 1.6, "standing on a slope after the climb (up tilted): the camera hands back after %.2f s", t_back or -1)
    -- over the top, then a slope: the hold counts from the last frame of mode 24, mode 25 is off the wall
    do
        clear_world()
        WALLS[1].build(F)
        fresh()
        for _, f in ipairs(fr3) do
            play_frame(f)
            view_of(0, 90)
        end
        local t_slope
        for i = 1, 200 do
            next_frame()
            if i <= 36 then
                feed(25, l.x, l.y + 40, l.z, 0, 1, 0, 2000 + i * 2, 0)
            else
                feed(1, l.x, l.y + 40, l.z, 0, 0.5, 0.8660254, 2000 + i * 2, 0)
            end
            view_of(0, 90)
            if not S().active then
                t_slope = i / 60
                break
            end
        end
        check(t_slope and t_slope > 0.95 and t_slope < 1.25, "over the top (mode 25 for 0.6 s), then a slope: the camera hands back %.2f s after the last frame of mode 24", t_slope or -1)
    end
    -- up comes back slowly: no step at the very end of the way
    clear_world()
    WALLS[1].build(F)
    fresh()
    for _, f in ipairs(fr3) do
        play_frame(f)
        view_of(0, 90)
    end
    local moved, lastO = 0, nil
    for i = 0, 56 do
        next_frame()
        local th = rad(10 - i * 0.2)
        if th < 0 then th = 0 end
        feed(9, l.x, l.y + 40, l.z, 0, sin(th), cos(th), 5000 + i * 2, 0)
        view_of(0, 90)
        local S1 = S()
        if lastO and i > 3 then moved = max(moved, sqrt((S1.ox - lastO[1]) ^ 2 + (S1.oy - lastO[2]) ^ 2 + (S1.oz - lastO[3]) ^ 2)) end
        lastO = { S1.ox, S1.oy, S1.oz }
    end
    check(moved > 0 and moved < 0.2, "up coming back slowly: the offset moves at most %.3f a frame, also at the end of the way", moved)
    -- up comes back to nearly straight up, as numbers do: the camera does not wait for the hold
    fresh()
    for _, f in ipairs(fr3) do
        play_frame(f)
        view_of(0, 90)
    end
    t_back = nil
    for i = 1, 120 do
        next_frame()
        feed(1, l.x, l.y + 40, l.z, 1e-9, -1e-9, 1, i * 2, 0)
        view_of(0, 90)
        local S1 = S()
        if not S1.active then
            t_back = i / 60
            break
        end
    end
    check(t_back and t_back < 0.25, "up nearly straight up: the camera hands back at once (%.2f s), not after the hold", t_back or -1)
    -- the clock starts again at a new grab: a second climb gets its whole hold
    fresh()
    for _, f in ipairs(fr3) do
        play_frame(f)
        view_of(0, 90)
    end
    for i = 1, 45 do
        next_frame()
        feed(1, l.x, l.y + 40, l.z, 0, 0.5, 0.8660254, i * 2, 0)
        view_of(0, 90)
    end
    for i = 1, 60 do
        next_frame()
        feed(24, l.x, l.y, l.z, 0, 1, 0, 1000 + i * 2, 0)
        view_of(0, 90)
    end
    t_back = nil
    for i = 1, 300 do
        next_frame()
        feed(1, l.x, l.y + 40, l.z, 0, 0.5, 0.8660254, 2000 + i * 2, 0)
        view_of(0, 90)
        if not S().active then
            t_back = i / 60
            break
        end
    end
    check(t_back and t_back > 0.9, "a second climb after a short way back: its whole hold again (%.2f s)", t_back or -1)
    -- mode 24 with up straight up (a floor taken for a wall, say): it stays the climbing camera, no line in the log every frame
    do
        fresh()
        local n, log0 = 0, GSA1.Log
        GSA1.Log = function(kind, fmt, ...) if kind == "camera" then n = n + 1 end return log0(kind, fmt, ...) end
        local stayed = true
        for i = 1, 60 do
            next_frame()
            feed(24, 0, 300, 100, 0, 0, 1, i * 2, 0)
            view_of(0, 90)
            stayed = stayed and S().active
        end
        GSA1.Log = log0
        check(stayed and n == 0, "mode 24 with up straight up: active on all 60 frames, %d lines in the log", n)
    end
    -- up turning right round in one pair (the back of a thin wall): the limit holds
    do
        fresh()
        local most, lastO2 = 0, nil
        for i = 1, 40 do
            next_frame()
            local uy = i <= 20 and 1 or -1
            feed(24, 0, 300, 100, 0, uy, 0, 2 + floor(i / 2) * 2, i % 2 == 0 and 0 or 0.5)
            view_of(0, 90)
            local S1 = S()
            if lastO2 and i > 10 then most = max(most, sqrt((S1.ox - lastO2[1]) ^ 2 + (S1.oy - lastO2[2]) ^ 2 + (S1.oz - lastO2[3]) ^ 2)) end
            lastO2 = { S1.ox, S1.oy, S1.oz }
        end
        check(most > 15 and most <= 1000 / 60 + 0.01, "up turning right round in one pair: the offset moves at most %.2f a frame (the limit 16.67)", most)
    end
    -- the distance is still easing when the offset is straight up: the camera waits for it
    do
        clear_world()
        WALLS[1].build(F)
        fresh()
        for k = 1, 30 do
            next_frame()
            feed(24, 0, 0, 100, 0, 1, 0, k * 2, 0)
            view_of(0, 90)      -- looking away from the wall: the eye close
        end
        local most, handed_at, prev_e = 0, nil, nil
        local far_y = 600
        for i = 1, 80 do
            next_frame()
            feed(9, 0, far_y, 100, 0, 0, 1, 100 + i * 2, 0)
            local vv = view_of(0, 90)
            local a = S()
            local dist_now = far_y - vv.origin.y
            if prev_e and i > 3 then most = max(most, dist_now - prev_e) end
            prev_e = dist_now
            if not a.active and not handed_at then handed_at = i end
        end
        check(handed_at and handed_at >= 10 and handed_at <= 25 and most <= 150 / 0.3 / 60 + 0.01, "off the wall with the eye still close: it eases out, %.2f a frame at the most, then hands back on frame %s", most, tostring(handed_at))
    end
    -- two views in one frame ease once
    do
        clear_world()
        add_wall_box(F, -64, 0, -2048, 2048, -64, 200)
        fresh()
        for i = 1, 40 do
            next_frame()
            feed(24, 0, 0, 170, 0, 1, 0, i * 2, 0)
            view_of(0, 90)
        end
        next_frame()
        feed(24, 0, 0, 300, 0, 1, 0, 400, 0)
        view_of(0, 90)
        local d1 = S().d
        view_of(0, 90)
        check(S().d == d1, "two views in one frame ease out once (%.2f, %.2f)", d1, S().d)
    end
    -- the frame's eye is a Vector of its own: the climbing camera reuses its own
    do
        clear_world()
        WALLS[1].build(F)
        fresh()
        next_frame()
        feed(24, 0, 0, 100, 0, 1, 0, 2, 0)
        local v1 = view_of(0, 180)
        local y1 = v1.origin.y
        next_frame()
        feed(24, 40, 0, 120, 0, 1, 0, 4, 0)
        local v2 = view_of(0, 180)
        check(v1.origin ~= v2.origin and v1.origin.y == y1, "each frame's view has its own origin (hooks and features may keep it)")
    end
    -- a new climb during the way back goes on from where the anchor is
    clear_world()
    WALLS[1].build(F)
    fresh()
    for _, f in ipairs(fr3) do
        play_frame(f)
        view_of(0, 90)
    end
    next_frame()
    feed(9, l.x, l.y + 2, l.z, 0, 0, 1, 2000, 0)
    view_of(0, 90)
    next_frame()
    feed(9, l.x, l.y + 2, l.z, 0, 0, 1, 2002, 0.5)
    view_of(0, 90)
    local S1 = S()
    local before = S1 and S1.oy or -1
    next_frame()
    feed(24, l.x, l.y, l.z, 0, 1, 0, 2004, 0)
    view_of(0, 90)
    S1 = S()
    check(S1 and abs(S1.oy - before) <= 1000 / 60 + 0.01, "a new grab during the way back: no restart (the offset %.2f to %.2f)", before, S1 and S1.oy or -1)
    -- the view's distance eases out and snaps in: looking away from the wall, past its top
    clear_world()
    add_wall_box(F, -64, 0, -2048, 2048, -64, 200)
    fresh()
    local max_out, max_in, prev_d = 0, 0, nil
    for i = 1, 120 do
        next_frame()
        feed(24, 0, 0, 170 + i * 0.5, 0, 1, 0, i * 2, 0)
        local vv = view_of(0, -90 + 180)
        local S0 = S()
        if S0 and S0.d and prev_d then
            max_out = max(max_out, S0.d - prev_d)
            max_in = max(max_in, prev_d - S0.d)
        end
        prev_d = S0 and S0.d
    end
    check(max_out > 0 and max_out <= 150 / 0.3 / 60 + 0.01, "looking away from the wall as the anchor comes up past its top: the view's distance grows at most %.2f a frame (0.9.9b: at once)", max_out)
    -- paused: nothing moves
    clear_world()
    WALLS[1].build(F)
    fresh()
    next_frame()
    feed(24, 0, 30, 100, 0, 1, 0, 2, 0)
    view_of(0, 90)
    local S2 = S()
    local oy0 = S2 and S2.oy
    M.paused = true
    next_frame()
    feed(24, 0, 0, 100, 0, 1, 0, 4, 0.5)
    view_of(0, 90)
    M.paused = false
    S2 = S()
    check(S2 and S2.oy == oy0, "paused (no frame time): the blend holds")
    -- two views in one frame: one step of the blend
    fresh()
    next_frame()
    feed(24, 0, 30, 100, 0, 1, 0, 2, 0)
    view_of(0, 90)
    next_frame()
    feed(24, 0, 15, 100, 0, 1, 0, 4, 0.5)
    view_of(0, 90)
    S2 = S()
    local oy1 = S2 and S2.oy
    view_of(0, 90)
    S2 = S()
    check(S2 and S2.oy == oy1, "two CalcView calls in one frame: one step of the blend")
    -- the option off in the middle of a climb: at once as 0.9.9b, and on again from straight up
    fresh()
    for _ = 1, 30 do
        next_frame()
        feed(24, 0, 0, 100, 0, 1, 0, nil, 0)
        view_of(0, 90)
    end
    set_cv("gsa1_cam_climb", 0)
    next_frame()
    feed(24, 0, 0, 100, 0, 1, 0, nil, 0)
    local n0 = M.ntrace
    local voff = view_of(0, 90)
    local x, y, z = old_eye({ x = 0, y = 0, z = 100 }, 0, 90, 150, 20)
    check(voff and abs(voff.origin.x - x) < 1e-6 and abs(voff.origin.y - y) < 1e-6 and abs(voff.origin.z - z) < 1e-6 and M.ntrace - n0 == 2,
        "unticked in the middle of a climb: that very frame is 0.9.9b's")
    set_cv("gsa1_cam_climb", 1)
    next_frame()
    feed(24, 0, 0, 100, 0, 1, 0, nil, 0)
    view_of(0, 90)
    S2 = S()
    check(S2 and S2.active and abs(S2.oz - CENTER) <= 1000 / 60 + 0.01, "ticked again: from straight up, by the blend (the offset's height %.2f)", S2 and S2.oz or -1)
    -- a gentle curve: up turns with the wall, the anchor follows without a jump
    fresh()
    local worst = 0
    local last
    local rr = 400
    clear_world()
    for i = 0, 180 do
        local th = rad(i * 0.5)
        local nx, ny = cos(th), sin(th)
        next_frame()
        feed(24, rr * nx, rr * ny, 100, nx, ny, 0, i * 2 + 2, 0)
        view_of(0, 0)
        local S0 = S()
        if last and S0 and i >= 8 then worst = max(worst, sqrt((S0.ax - last[1]) ^ 2 + (S0.ay - last[2]) ^ 2 + (S0.az - last[3]) ^ 2)) end
        last = S0 and { S0.ax, S0.ay, S0.az }
    end
    check(worst > 0 and worst < 7, "round a curved wall: the anchor moves at most %.2f a frame (the character %.2f)", worst, 400 * rad(0.5))
    -- a bad up vector from a module: not a climb
    fresh()
    next_frame()
    feed(24, 0, 0, 100, 0, 0, 0)
    view_of(0, 90)
    check(not (S() and S().active), "up of length 0: not a climb, 0.9.9b's view")
    fresh()
    next_frame()
    feed(24, 0, 0, 100, nil, nil, nil)
    view_of(0, 90)
    check(not (S() and S().active), "a module without upx, upy, upz: not a climb, 0.9.9b's view")
end

-- 6. the game's own climb -------------------------------------------------------------------------------------------------------------------------------------------
do
    local text = host_read(groot .. "/build/x86_64-windows/climb_trajectory.txt")
    if not text then
        info("no build/x86_64-windows/climb_trajectory.txt (no disc when feat_climbcam_binding_test ran): the game's own climb is not replayed")
    else
        local scenes, hit_scenes, switch_scenes, cur = {}, {}, {}, nil
        for line in string.gmatch(text, "[^\n]+") do
            if string.sub(line, 1, 1) == "S" then
                local name, nx, ny, nz, top, hw = string.match(line, "^S (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
                cur = { name = name, n = { tonumber(nx), tonumber(ny), tonumber(nz) }, top = tonumber(top), hw = tonumber(hw), frames = {} }
                if string.find(name, "_hit$") or string.find(name, "_die$") then
                    hit_scenes[#hit_scenes + 1] = cur
                elseif string.find(name, "_switch$") or string.find(name, "_recreate$") then
                    switch_scenes[#switch_scenes + 1] = cur
                else
                    scenes[#scenes + 1] = cur
                end
            elseif string.sub(line, 1, 1) == "X" then
                cur.frames[#cur.frames + 1] = { switch = tonumber(string.sub(line, 3)) }
            else
                local mode, action, x, y, z, ux, uy, uz, step, alpha = string.match(line, "^F (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
                cur.frames[#cur.frames + 1] = { mode = tonumber(mode), x = tonumber(x), y = tonumber(y), z = tonumber(z), ux = tonumber(ux), uy = tonumber(uy), uz = tonumber(uz),
                                                step = tonumber(step), alpha = tonumber(alpha) }
            end
        end
        check(#scenes >= 15, "the game's climb: %d scenes from climb_trajectory.txt", #scenes)
        local pd_game
        local function scene_world(sc, face)
            clear_world()
            local F = wall_frame(sc.n[1], sc.n[2], sc.n[3])
            add_box(-8192, -8192, -64, 8192, 8192, 0)
            add_wall_box(F, -512, face, -sc.hw, sc.hw, -64, sc.top)
            return F
        end
        for _, face in ipairs({ 0, 8 }) do
            local frames, inside, close = 0, 0, 0
            for _, sc in ipairs(scenes) do
                local F = scene_world(sc, face)
                local first24, last24
                for i, f in ipairs(sc.frames) do if f.mode == 24 then first24 = first24 or i last24 = i end end
                for _, cam in ipairs({ { 150, 20 }, { 120, 6 } }) do
                    set_cv("gsa1_cam_distance", cam[1])
                    set_cv("gsa1_cam_height", cam[2])
                    for _, vw in ipairs(VIEWS) do
                        fresh()
                        local base = yaw_of(F, 0)
                        for i, f in ipairs(sc.frames) do
                            play_frame(f)
                            local v = view_of(vw[1], base + vw[2])
                            if first24 and i >= first24 and i <= last24 + 40 then
                                frames = frames + 1
                                local o = v and v.origin
                                if not o or overlaps(o.x, o.y, o.z, 0) then
                                    inside = inside + 1
                                elseif overlaps(o.x, o.y, o.z, 4.9) then
                                    close = close + 1
                                end
                            end
                        end
                    end
                end
            end
            check(frames > 10000 and inside == 0 and close == 0, "the game's climb, %d scenes x 2 cameras x %d views, the polygon %d behind the visible face: %d frames from the grab until 0.67 s after the wall, %d inside, %d with the box in it",
                #scenes, #VIEWS, face, frames, inside, close)
        end
        set_cv("gsa1_cam_distance", 150)
        set_cv("gsa1_cam_height", 20)
        -- the jumps, on the frames the game really gives (the grab, over the top, jumping off, climbing down)
        local all_worst, all_old, all_gate, all_over = 0, 0, 0, 0
        for _, sc in ipairs(scenes) do
            local F = scene_world(sc, 0)
            local w, wo, wg, over = measure_jumps(sc.frames, F)
            all_worst, all_old, all_gate, all_over = max(all_worst, w), max(all_old, wo), max(all_gate, wg), max(all_over, over)
        end
        check(all_worst <= 10 and all_worst < all_old and all_over <= 1000 / 60 + 0.05, "the game's climb: the anchor's largest move in a frame %.1f (0.9.9b's %.1f); beyond the character's own move at most %.2f (the limit 16.67)", all_worst, all_old, all_over)
        check(all_gate > 24 and all_gate > all_worst, "the negative control: a plain gate on mode 24 jumps %.1f in a frame here", all_gate)
        -- the eye itself, at fixed views. It must snap in where something comes between it and the anchor (it cannot pass the wall): those are told apart and
        -- counted, every other move is the anchor's plus the easing out. 0.9.9b's for comparison: its eye goes into the wall and comes out again, the owner's note
        do
            local worst, where, snap, snap_where, snaps, worst_old, at_wall = 0, "", 0, "", 0, 0, 0
            for _, sc in ipairs(scenes) do
                local F = scene_world(sc, 8)
                local first24, last24
                for i, f in ipairs(sc.frames) do
                    if f.mode == 24 then
                        first24 = first24 or i
                        last24 = i
                    end
                end
                local base = yaw_of(F, 0)
                for _, vw in ipairs(VIEWS) do
                    fresh()
                    local px, py, pz, ox, oy, oz, pd
                    for i, f in ipairs(sc.frames) do
                        play_frame(f)
                        local yaw = base + vw[2]
                        local v = view_of(vw[1], yaw)
                        local o = v.origin
                        local S0 = S()
                        local qx, qy, qz = old_eye(f, vw[1], yaw, 150, 20)
                        if px and first24 and i >= first24 and i <= last24 + 40 then
                            local d = sqrt((o.x - px) ^ 2 + (o.y - py) ^ 2 + (o.z - pz) ^ 2)
                            local where_now = string.format("%s, view %d %d, frame %d, mode %d", sc.name, vw[1], vw[2], i, f.mode)
                            if S0 and S0.active and S0.d and pd and pd - S0.d > 12 then
                                snaps = snaps + 1
                                if d > snap then snap, snap_where = d, where_now end
                            elseif S0 and S0.active then
                                if d > worst then worst, where = d, where_now end
                                if vw[1] == 0 and vw[2] == 180 then at_wall = max(at_wall, d) end
                            end
                            worst_old = max(worst_old, sqrt((qx - ox) ^ 2 + (qy - oy) ^ 2 + (qz - oz) ^ 2))
                        end
                        px, py, pz, ox, oy, oz, pd = o.x, o.y, o.z, qx, qy, qz, S0 and S0.d
                    end
                end
            end
            check(worst <= 16.7 + 8.34 + 0.1 and at_wall <= 16.7, "the eye on the game's climb at fixed views: its largest move in a frame %.1f (%s), looking at the wall %.1f; 0.9.9b's %.1f", worst, where, at_wall, worst_old)
            info("  it snapped in %d times of all those frames, the largest %.1f (%s): something came between the eye and the anchor", snaps, snap, snap_where)
        end
        -- each way off the wall, as measured: mode 25 still has up on the wall, and the camera follows
        local per = {}
        for _, sc in ipairs(scenes) do
            local F = scene_world(sc, 0)
            fresh()
            local back
            for i, f in ipairs(sc.frames) do
                play_frame(f)
                view_of(0, yaw_of(F, 180))
                local S0 = S()
                if S0 and not S0.active and not back and i > 100 then back = i end
            end
            per[#per + 1] = string.format("%s %s", sc.name, tostring(back))
        end
        info("the frame the camera handed back, per scene: %s", table.concat(per, ", "))
        -- being hit and being killed on the wall, as the game does it
        check(#hit_scenes >= 3 and #switch_scenes >= 3, "the game's own hits and deaths on the wall: %d scenes, switches and re-creations: %d", #hit_scenes, #switch_scenes)
        do
            local frames, bad, most, n14, nback, where = 0, 0, 0, 0, 0, ""
            for _, sc in ipairs(hit_scenes) do
                for _, face in ipairs({ 0, 8 }) do
                    local F = scene_world(sc, face)
                    local base = yaw_of(F, 0)
                    local first24
                    for i, f in ipairs(sc.frames) do
                        if f.mode == 24 then first24 = first24 or i end
                        if f.mode == 14 and face == 0 then n14 = n14 + 1 end
                    end
                    for _, vw in ipairs(VIEWS) do
                        fresh()
                        local p, was
                        for i, f in ipairs(sc.frames) do
                            play_frame(f)
                            local v = view_of(vw[1], base + vw[2])
                            local o = v.origin
                            local S0 = S()
                            if S0 and S0.active and i >= first24 then
                                frames = frames + 1
                                if overlaps(o.x, o.y, o.z, 4.9) then bad = bad + 1 end
                                if p and i > first24 + 4 and not (S0.d and pd_game and pd_game - S0.d > 12) then
                                    local g = sc.frames[i - 1]
                                    local own = sqrt((f.x - g.x) ^ 2 + (f.y - g.y) ^ 2 + (f.z - g.z) ^ 2)
                                    local d = sqrt((o.x - p.x) ^ 2 + (o.y - p.y) ^ 2 + (o.z - p.z) ^ 2) - own
                                    if d > most then most, where = d, string.format("%s, view %d %d, frame %d, mode %d", sc.name, vw[1], vw[2], i, f.mode) end
                                end
                                was = true
                            elseif was then
                                nback = nback + 1
                                was = false
                            end
                            p = o
                            pd_game = S0 and S0.d
                        end
                    end
                end
            end
            check(n14 > 0, "  the game went to mode 14 on %d frames", n14)
            check(frames > 1000 and bad == 0, "  hit or killed on the wall: %d frames of the climbing camera, %d with the eye or its box in the wall", frames, bad)
            check(nback > 0 and most < 40, "  it hands back (%d times); the eye's largest move beyond the body's own %.1f (%s), snaps in not counted", nback, most, where)
        end
        -- a switch and a re-creation on the wall, as the game goes on from them: through the real GSA1.Spawn and GSA1.Recreate
        do
            local frames, bad, most, nback, nswitch, where = 0, 0, 0, 0, 0, ""
            for _, sc in ipairs(switch_scenes) do
                for _, face in ipairs({ 0, 8 }) do
                    local F = scene_world(sc, face)
                    local base = yaw_of(F, 0)
                    for _, vw in ipairs(VIEWS) do
                        spawn("knuckles")
                        fresh()
                        local p, was, switched
                        for i, f in ipairs(sc.frames) do
                            if f.switch then
                                if f.switch == 3 then GSA1.Recreate("a test") else GSA1.Spawn("sonic") end
                                C = GSA1.Char
                                if C.kind == 3 then C.info.center, C.info.eyes = CENTER, EYES end
                                switched = true
                                nswitch = nswitch + 1
                            else
                                play_frame(f)
                                local v = view_of(vw[1], base + vw[2])
                                local o = v.origin
                                local S0 = S()
                                if switched and S0 and S0.active then
                                    frames = frames + 1
                                    if overlaps(o.x, o.y, o.z, 4.9) then bad = bad + 1 end
                                    if p then
                                        local g = sc.frames[i - 1]
                                        local own = g and g.x and sqrt((f.x - g.x) ^ 2 + (f.y - g.y) ^ 2 + (f.z - g.z) ^ 2) or 0
                                        local d = sqrt((o.x - p.x) ^ 2 + (o.y - p.y) ^ 2 + (o.z - p.z) ^ 2) - own
                                        if d > most then most, where = d, string.format("%s, view %d %d, frame %d, mode %d", sc.name, vw[1], vw[2], i, f.mode) end
                                    end
                                    was = true
                                elseif was then
                                    nback = nback + 1
                                    was = false
                                end
                                p = o
                            end
                        end
                    end
                end
            end
            check(nswitch > 0 and frames > 100 and bad == 0, "  switched or re-created on the wall (%d times): %d frames of the climbing camera, %d with the eye or its box in the wall", nswitch, frames, bad)
            check(nback > 0 and most < 12, "  it hands back (%d times); the eye's largest move beyond the body's own %.1f (%s)", nback, most, where)
            spawn("knuckles")
        end
    end
end

-- 7. everything else moves as 0.9.9b, frame for frame --------------------------------------------------------------------------------------------------------------
do
    local rec = host_read(tests .. "/feat_climbcam_recording.txt")
    check(rec ~= nil, "the recording is there: tests/feat_climbcam_recording.txt")
    local want = {}
    for line in string.gmatch(rec or "", "[^\n]+") do
        local name, n, rest = string.match(line, "^(%S+) (%d+) (.*)$")
        if name then
            local h = {}
            for w in string.gmatch(rest, "%S+") do h[#h + 1] = w end
            want[name] = h
        end
    end
    local total = 0
    for _, sc in ipairs(SCENARIOS) do
        local lines = run_scenario(sc)
        local h = want[sc.name]
        local from, to = 1, #lines
        local differ, first = 0, nil
        if sc.name == "climb_on" then
            -- with the option on only the climb's own frames may differ: from the first frame of mode 24 until the camera hands back
            local fr = frames_of(pair_path(CLIMB_ON_PATH), F_REC)
            local first24
            for i, f in ipairs(fr) do if f.mode == 24 then first24 = i break end end
            local last_climb_frame = #fr     -- the climb's path ends well after up is back
            for i = 1, #lines do
                local mine = hash_of(lines[i])
                if (i < first24 or i > last_climb_frame) and (not h or mine ~= h[i]) then
                    differ = differ + 1
                    first = first or i
                end
            end
            local changed = 0
            for i = first24, last_climb_frame do if not h or hash_of(lines[i]) ~= h[i] then changed = changed + 1 end end
            check(changed > 50, "climb_on: the climb's own frames do change (%d of them, the control)", changed)
        else
            for i = 1, #lines do
                if not h or hash_of(lines[i]) ~= h[i] then
                    differ = differ + 1
                    first = first or i
                end
            end
        end
        total = total + #lines
        check(h and #h == #lines and differ == 0, "%s: %d frames, bit for bit as the frozen 0.9.9b%s", sc.name, #lines, first and string.format(" (first difference at frame %d, %d differ)", first, differ) or "")
    end
    info("the recording compares origin, angles, field of view, drawviewer and the number of traces on %d frames", total)
    check(M.othersState == nil, "another character's mode 24 makes no climbing camera's state")
end

-- the session log: the setting at a new character, one line per climb with what it noticed
do
    local logged, log0 = {}, GSA1.Log
    GSA1.Log = function(kind, fmt, ...)
        logged[#logged + 1] = kind .. " " .. string.format(fmt, ...)
        return log0(kind, fmt, ...)
    end
    if K then K.settingsLine = nil end
    spawn("knuckles")
    local F = wall_frame(0, 1, 0)
    clear_world()
    WALLS[3].build(F)
    local n_settings, n_climb, line = 0, 0, ""
    for _, f in ipairs(frames_of(pair_path({ rest = 10, leave = "jump" }), F)) do
        play_frame(f)
        view_of(0, 90)
    end
    for _ = 1, 150 do
        next_frame()
        feed(1, 0, 400, 0, 0, 0, 1)
        view_of(0, 90)
    end
    for _, l in ipairs(logged) do
        if string.find(l, "gsa1_cam_climb", 1, true) then n_settings = n_settings + 1 end
        if string.find(l, "climbing camera:", 1, true) then
            n_climb = n_climb + 1
            line = l
        end
    end
    GSA1.Log = log0
    check(n_settings == 1, "the session log has the setting once at a new character (%d)", n_settings)
    local solid = string.match(line, "inside something on (%d+) frames")
    check(n_climb == 1 and tonumber(solid) and tonumber(solid) > 0, "and one line for the climb: %s", line)
end

-- 10. every way a climb ends (0.9.9c's verifier): up left on the wall, a body stuck in or gone through a wall, a hit, a switch, a re-creation, the option --------------
local function log_catcher()
    local lines, log0 = {}, GSA1.Log
    GSA1.Log = function(kind, fmt, ...)
        if kind == "camera" then lines[#lines + 1] = string.format(fmt, ...) end
        return log0(kind, fmt, ...)
    end
    return lines, function() GSA1.Log = log0 end
end
local function is_inside(v, h)
    local o = v and v.origin
    return not o or overlaps(o.x, o.y, o.z, h or 0)
end
local function same_as_old(v, f, pitch, yaw, dist, height, center)
    local x, y, z = old_eye(f, pitch, yaw, dist or 150, height or 20, center)
    return v and abs(v.origin.x - x) < 1e-6 and abs(v.origin.y - y) < 1e-6 and abs(v.origin.z - z) < 1e-6
end
local function moved(v, p)
    if not p then return 0 end
    local o = v.origin
    return sqrt((o.x - p.x) ^ 2 + (o.y - p.y) ^ 2 + (o.z - p.z) ^ 2)
end
-- the climb before each of these: 20 pairs on the wall, at `c`
local function on_the_wall(F, c, pitch, yaw)
    local x, y, z = to_world(F, 0, 0, c)
    local v
    for k = 1, 40 do
        next_frame()
        feed(24, x, y, z, F.n[1], F.n[2], F.n[3], 3000 + floor(k / 2) * 2, (k % 2) * 0.5)
        v = view_of(pitch, yaw)
    end
    return v
end

-- (a) MEASURED on the owner's wall, at its end near (1023 -1030), at 72 frames a second: over the top the game goes to mode 9 with up still on the wall and the position 2 out of
-- the polygon, inside the visible wall, for 8.7 s (real/modes): the body is drawn out of the wall (position + up x center), and the camera stays on it until up comes back
do
    local F = wall_frame(0, 1, 0)
    set_cv("gsa1_cam_distance", 120)
    set_cv("gsa1_cam_height", 6)
    spawn("knuckles")
    local dt = 1 / 72
    local total, inside, most, ended, last_ok, after_bad = 0, 0, 0, 0, true, 0
    local checked_views = 0
    for _, vw in ipairs(VIEWS) do
        clear_world()
        WALLS[2].build(F)
        fresh()
        local yaw = yaw_of(F, 0) + vw[2]
        local p = on_the_wall(F, 120, vw[1], yaw)
        p = p and Vector(p.origin)
        local c = 120
        local handed, was
        for i = 1, floor(9.5 / dt) do
            M.frameNo, M.dt = M.frameNo + 1, dt
            local a, ux, uz = 2, 1, 0
            if i <= floor(8.7 / dt) then
                c = c + (i < 300 and 0.3 or -0.1)   -- rising, then falling, with up on the wall
            else
                -- up comes back, the body walks away from the wall
                a, ux, uz = 2 + (i - floor(8.7 / dt)) * 2, 0, 1
            end
            local x, y, z = to_world(F, a, 0, c)
            feed(9, x, y, z, F.n[1] * ux, F.n[2] * ux, F.n[3] * ux + uz, 5000 + floor(i / 2.4) * 2, 0)
            local v = view_of(vw[1], yaw)
            total = total + 1
            local S0 = S()
            if S0 and S0.active then
                if is_inside(v, 4.9) then inside = inside + 1 end
                if i > 1 then most = max(most, moved(v, p)) end
                if i <= floor(8.7 / dt) then was = true end
            elseif was and not handed then
                handed = i
                -- the frame of the hand back: nothing else than the old traces give
                last_ok = last_ok and same_as_old(v, { x = x, y = y, z = z }, vw[1], yaw, 120, 6)
            elseif handed and not same_as_old(v, { x = x, y = y, z = z }, vw[1], yaw, 120, 6) then
                after_bad = after_bad + 1
            end
            p = Vector(v.origin)
        end
        if handed and handed > floor(8.7 / dt) then ended = ended + 1 end
        checked_views = checked_views + 1
    end
    check(inside == 0, "off the wall with up still on it for 8.7 s (the owner's wall, at 72 frames a second): the eye and its box stay out of the wall on all %d frames of %d views (%d in it)", total, checked_views, inside)
    check(ended == checked_views, "  no hand back until up has come back and the body is out (%d of %d views)", ended, checked_views)
    check(most < 16, "  no jump at any time, also not at 2 s: the eye's largest move in a frame %.1f", most)
    check(last_ok and after_bad == 0, "  the hand back gives exactly 0.9.9b's eye, and so does every frame after it (%d differ)", after_bad)
end

-- how upright up must be to count as back: 0.4 stays followed, 0.6 goes to straight up after the hold
do
    local F = wall_frame(0, 1, 0)
    set_cv("gsa1_cam_distance", 150)
    set_cv("gsa1_cam_height", 20)
    clear_world()
    WALLS[1].build(F)
    for _, t in ipairs({ { 0.4, true }, { 0.6, false } }) do
        spawn("knuckles")
        fresh()
        on_the_wall(F, 300, 0, 90)
        local uz, uy = t[1], sqrt(1 - t[1] * t[1])
        for i = 1, floor(1.6 * 60) do
            next_frame()
            feed(1, 0, 60, 300, 0, uy, uz, 7000 + i * 2, 0)
            view_of(0, 90)
        end
        local S0 = S()
        if t[2] then
            check(S0 and S0.active and abs(S0.oz - uz * CENTER) < 0.01, "up %.1f upright (still a wall) 1.6 s off the wall: the anchor stays on the drawn body (the offset's height %.2f)", uz, S0 and S0.oz or -1)
        else
            check(S0 and not S0.active, "up %.1f upright (a slope) 1.6 s off the wall: handed back", uz)
        end
    end
end

-- (b) stuck in a wall after the climb, the way out along the normal in reach: never back in the wall, whatever the time; out again: the hand back
do
    local F = wall_frame(0, 1, 0)
    clear_world()
    WALLS[3].build(F)
    spawn("knuckles")
    fresh()
    set_cv("gsa1_cam_distance", 150)
    set_cv("gsa1_cam_height", 20)
    on_the_wall(F, 100, 0, 90)
    local bad, x, y, z = 0, to_world(F, 0, 0, 100)
    local p, most, off_at = nil, 0, nil
    for i = 1, 6 * 60 do
        next_frame()
        feed(1, x, y, z, 0, 0, 1, 7000 + i * 2, 0)
        local v = view_of(0, 90)
        if is_inside(v, 4.9) then bad = bad + 1 end
        if i > 1 then most = max(most, moved(v, p)) end
        p = Vector(v.origin)
        if not (S() and S().active) then off_at = off_at or i end
    end
    check(bad == 0 and not off_at and most < 16.7, "stuck inside the wall for 6 s after the climb, the way out in reach: the eye stays out on every frame (%d in it), no hand back (%s), its largest move %.1f", bad, tostring(off_at), most)
    local handed
    for i = 1, 120 do
        next_frame()
        local a = min(i * 3, 90)
        local fx, fy, fz = to_world(F, a, 0, 100)
        feed(1, fx, fy, fz, 0, 0, 1, 9000 + i * 2, 0)
        local v = view_of(0, 90)
        if not (S() and S().active) and not handed then
            handed = i
            check(same_as_old(v, { x = fx, y = fy, z = fz }, 0, 90), "  out again: handed back on frame %d with exactly 0.9.9b's eye", i)
        end
    end
    check(handed, "  and it does hand back")
end

-- (c) through the wall: MEASURED, the owner's wall at 72 frames a second, the body goes through the wall in 0.2 s. The eye can not follow through it. It waits on its side while the
-- body is inside, and the first frame the body has an open place on the far side the eye is there: a cut, and it is not in a wall. Nothing else is honest
do
    local F = wall_frame(0, 1, 0)
    clear_world()
    WALLS[3].build(F)    -- 64 thick: a -32..32
    spawn("knuckles")
    fresh()
    on_the_wall(F, 100, 0, 90)
    local bad, wait, far_after, handed = 0, 0, 0, nil
    local first_open
    for i = 1, 200 do
        next_frame()
        local a = 0 - i * 3
        local fx, fy, fz = to_world(F, a, 0, 100)
        feed(9, fx, fy, fz, 0, 0, 1, 7000 + i * 2, 0)
        local v = view_of(0, 90)
        if is_inside(v, 4.9) then bad = bad + 1 end
        local open = a < -37.2
        if open then
            first_open = first_open or i
            if v.origin.y > -32 then far_after = far_after + 1 end
        else
            wait = wait + 1
        end
        if not (S() and S().active) then handed = handed or i end
    end
    check(bad == 0 and far_after == 0, "through the wall: the eye is never in it (%d), and on the far side from the first frame the body has an open place there (%d frames behind)", bad, far_after)
    check(first_open and handed and handed - first_open <= 0.3 * 60 + 2, "  and it hands back at most the ease later (frame %s, the body clear on frame %s)", tostring(handed), tostring(first_open))
end

-- (d) out of reach: the body sinks deep into something the ladder can not leave. The eye waits for it for LOST seconds, then lets go: 0.9.9b's eye, a line in the log
do
    local F = wall_frame(0, 1, 0)
    local function deep_world()
        clear_world()
        WALLS[1].build(F)
        plane_brush({ { 0, 0, 1, 0 }, { 0, 0, -1, 3000 }, { 1, 0, 0, 4096 }, { -1, 0, 0, 4096 }, { 0, 1, 0, 4096 }, { 0, -1, 0, 4096 } })
    end
    deep_world()
    spawn("knuckles")
    fresh()
    local lines, restore = log_catcher()
    on_the_wall(F, 120, 0, 90)
    local let_go, bad_before, sink_start, after_bad = nil, 0, nil, 0
    local dz = 0
    for i = 1, 8 * 60 do
        next_frame()
        dz = dz + 1.2
        local fx, fy, fz = to_world(F, 0, 0, 120 - dz)
        feed(9, fx, fy, fz, 0, 1, 0, 7000 + i * 2, 0)
        -- deep enough: the found place is further from the anchor than the ladder reaches
        if not sink_start and fz < 5 - 129 then sink_start = i end
        local v = view_of(0, 90)
        if S() and S().active then
            if is_inside(v, 4.9) then bad_before = bad_before + 1 end
        elseif not let_go then
            let_go = i
            if not same_as_old(v, { x = fx, y = fy, z = fz }, 0, 90) then after_bad = after_bad + 1 end
        elseif not same_as_old(v, { x = fx, y = fy, z = fz }, 0, 90) then
            after_bad = after_bad + 1
        end
    end
    restore()
    local t = let_go and sink_start and (let_go - sink_start) / 60
    check(bad_before == 0 and t and t > 2.9 and t < 3.2, "sunk out of reach: the eye waits, out of everything (%d frames in it), and lets go %.2f s after the body went out of reach", bad_before, t or -1)
    check(after_bad == 0, "  0.9.9b's eye from that frame on (%d differ)", after_bad)
    local said
    for _, l in ipairs(lines) do if string.find(l, "let go", 1, true) then said = l end end
    check(#lines == 1 and said ~= nil, "  one line in the log says so: %s", tostring(said or lines[1]))
    -- nothing open at all: the frame gives 0.9.9b's eye, and the wait is the same
    do
        clear_world()
        WALLS[1].build(F)
        spawn("knuckles")
        fresh()
        on_the_wall(F, 120, 0, 90)
        clear_world()
        plane_brush({ { 0, 0, 1, 4000 }, { 0, 0, -1, 4000 }, { 1, 0, 0, 4096 }, { -1, 0, 0, 4096 }, { 0, 1, 0, 4096 }, { 0, -1, 0, 4096 } })
        GSA1.view.frame = nil
        local t_go
        for i = 1, 5 * 60 do
            next_frame()
            feed(9, 0, 60, 120, 0, 1, 0, 7000 + i * 2, 0)
            view_of(0, 90)
            if not S().active then
                t_go = i / 60
                break
            end
        end
        check(t_go and t_go > 2.9 and t_go < 3.1, "  nothing open anywhere off the wall: the same wait, then it lets go (%.2f s)", t_go or -1)
    end
    -- each CalcView of a frame does not count
    do
        clear_world()
        WALLS[1].build(F)
        spawn("knuckles")
        fresh()
        on_the_wall(F, 120, 0, 90)
        clear_world()
        plane_brush({ { 0, 0, 1, 4000 }, { 0, 0, -1, 4000 }, { 1, 0, 0, 4096 }, { -1, 0, 0, 4096 }, { 0, 1, 0, 4096 }, { 0, -1, 0, 4096 } })
        GSA1.view.frame = nil
        for i = 1, 100 do
            next_frame()
            feed(9, 0, 60, 120, 0, 1, 0, 7000 + i * 2, 0)
            view_of(0, 90)
            view_of(0, 90)
            view_of(0, 90)
        end
        check(S().active and S().lost and abs(S().lost - 100 / 60) < 0.02, "  three views in a frame wait one frame's time (%.2f s after 100 frames)", S().lost or -1)
    end
    -- it comes back in reach before that: the wait starts again
    deep_world()
    spawn("knuckles")
    fresh()
    on_the_wall(F, 120, 0, 90)
    local still = true
    for round = 1, 4 do
        for i = 1, 2 * 60 do
            next_frame()
            local down = i <= 60 and 340 or 0        -- 2 s: 1 s out of reach, 1 s back in reach, in the open
            local fx, fy, fz = to_world(F, 60, 0, 120 - down)
            feed(9, fx, fy, fz, 0, 1, 0, 7000 + round * 1000 + i * 2, 0)
            view_of(0, 90)
            still = still and S() and S().active
        end
    end
    check(still, "  in reach again before the wait is over: the wait starts again (still the climbing camera after 8 s, 4 of them out of reach)")
    -- on the wall itself there is no letting go: mode 24 out of reach for 6 s
    deep_world()
    spawn("knuckles")
    fresh()
    on_the_wall(F, 120, 0, 90)
    still = true
    for i = 1, 6 * 60 do
        next_frame()
        local fx, fy, fz = to_world(F, 60, 0, 120 - 340)
        feed(24, fx, fy, fz, 0, 1, 0, 7000 + i * 2, 0)
        view_of(0, 90)
        still = still and S() and S().active
    end
    check(still, "  in mode 24 it never lets go")
    -- paused: no wait goes by
    deep_world()
    spawn("knuckles")
    fresh()
    on_the_wall(F, 120, 0, 90)
    M.paused = true
    for i = 1, 300 do
        next_frame()
        local fx, fy, fz = to_world(F, 60, 0, 120 - 340)
        feed(9, fx, fy, fz, 0, 0, 1, 7000 + i * 2, 0)
        view_of(0, 90)
    end
    M.paused = false
    check(S() and S().active, "  paused: no wait goes by")
end

-- (e) being hit on the wall: the game goes to mode 14, up turns off the wall in a few pairs, the body is thrown out and falls (MEASURED: real/, the binding test's own scenes below)
do
    local F = wall_frame(0, 1, 0)
    local function hit_path(c)
        local P = {}
        local a = 0
        for _ = 1, 30 do P[#P + 1] = { mode = 24, a = 0, b = 0, c = c, ua = 1, uc = 0 } end
        for i = 1, 8 do
            local th = rad(i * 11.25)
            a, c = a + 0.5, c - 0.4 * i
            P[#P + 1] = { mode = 14, a = a, b = 0, c = c, ua = cos(th), uc = sin(th) }
        end
        for i = 1, 20 do
            a, c = a + 2, c - 3.2 - i * 0.4
            P[#P + 1] = { mode = 14, a = a, b = 0, c = c, ua = 0, uc = 1 }
        end
        for _ = 1, 60 do P[#P + 1] = { mode = 1, a = a, b = 0, c = c, ua = 0, uc = 1 } end
        return P
    end
    for _, wall in ipairs(WALLS) do
        local frames, bad, most, handed_ok, modes14 = 0, 0, 0, true, 0
        for _, vw in ipairs(VIEWS) do
            clear_world()
            wall.build(F)
            spawn("knuckles")
            fresh()
            local fr = frames_of(hit_path(300), F)
            local yaw = yaw_of(F, 0) + vw[2]
            local p, was, handed, pd
            local first14
            for i, f in ipairs(fr) do
                play_frame(f)
                local v = view_of(vw[1], yaw)
                if f.mode == 14 then
                    first14 = first14 or i
                    modes14 = modes14 + 1
                end
                local S0 = S()
                local act = S0 and S0.active
                if act then
                    frames = frames + 1
                    if is_inside(v, 4.9) then bad = bad + 1 end
                    -- past the first settling frames: the eye moves about what the body does
                    if first14 and p and i > first14 then
                        local g = fr[i - 1]
                        local own = sqrt((f.x - g.x) ^ 2 + (f.y - g.y) ^ 2 + (f.z - g.z) ^ 2)
                        if not (S0.d and pd and pd - S0.d > 12) then most = max(most, moved(v, p) - own) end
                    end
                    was = true
                elseif was and not handed then
                    handed = i
                    handed_ok = handed_ok and same_as_old(v, f, vw[1], yaw)
                end
                p = Vector(v.origin)
                pd = S0 and S0.d
            end
            handed_ok = handed_ok and handed ~= nil
        end
        check(frames > 0 and modes14 > 0 and bad == 0, "being hit on the wall (%s): mode 14, %d views: %d frames, %d with the eye or its box in the wall", wall.name, #VIEWS, frames, bad)
        check(handed_ok and most < 40, "  it hands back with exactly 0.9.9b's eye on every view; beyond the body's own move at most %.1f in a frame (a snap in does not count)", most)
    end
end

-- (f) a switch of character, a re-creation: a new character stands where the old one climbed. That is a way off the wall: the camera goes on with it until it can hand back
do
    local F = wall_frame(0, 1, 0)
    local function new_char()
        C = GSA1.Char
        if C and C.kind == 3 then C.info.center, C.info.eyes = CENTER, EYES end
        return C
    end
    local RUNS = {
        { "switched to Sonic", function() GSA1.Spawn("sonic") end },
        { "re-created", function() GSA1.Recreate("a test") end },
    }
    for _, run in ipairs(RUNS) do
        for _, fp in ipairs({ false, true }) do
            for _, wall in ipairs(WALLS) do
                local frames, bad, most, handed_ok, carried_ok = 0, 0, 0, true, true
                set_cv("gsa1_cam_distance", fp and 0 or 150)
                set_cv("gsa1_cam_height", 20)
                for _, vw in ipairs(VIEWS) do
                    clear_world()
                    wall.build(F)
                    spawn("knuckles")
                    fresh()
                    local yaw = yaw_of(F, 0) + vw[2]
                    local v0 = on_the_wall(F, 300, vw[1], yaw)
                    local p = Vector(v0.origin)
                    run[2]()
                    new_char()
                    carried_ok = carried_ok and C.climbCam ~= nil and C.climbCam.active
                    local handed
                    for i = 1, 240 do
                        next_frame()
                        -- it falls off the wall's polygon, away from the wall after a second
                        local a = i <= 60 and 0 or (i - 60) * 2
                        local fx, fy, fz = to_world(F, a, 0, 300 - i * 0.5)
                        feed(9, fx, fy, fz, 0, 0, 1, 100 + i * 2, 0)
                        local v = view_of(vw[1], yaw)
                        local S0 = S()
                        if S0 and S0.active then
                            frames = frames + 1
                            if is_inside(v, 4.9) then bad = bad + 1 end
                            most = max(most, moved(v, p))
                        elseif not handed then
                            handed = i
                            if not fp then handed_ok = handed_ok and same_as_old(v, { x = fx, y = fy, z = fz }, vw[1], yaw, 150, 20, C.info.center) end
                        end
                        p = Vector(v.origin)
                    end
                    handed_ok = handed_ok and handed ~= nil
                end
                check(carried_ok and frames > 0 and bad == 0, "%s on the wall, %s, %s: the camera goes on with the new character: %d frames, %d with the eye or its box in the wall", run[1], fp and "first person" or "chase", wall.name, frames, bad)
                check(handed_ok and most < 12, "  no jump: the eye's largest move in a frame %.1f, and it hands back%s", most, fp and "" or " with exactly 0.9.9b's eye")
            end
        end
    end
    set_cv("gsa1_cam_distance", 150)
    set_cv("gsa1_cam_height", 20)
    -- the offset's way down takes BLEND_TIME, from on the wall to straight up
    do
        clear_world()
        WALLS[1].build(F)
        spawn("knuckles")
        fresh()
        on_the_wall(F, 300, 0, 180)
        GSA1.Spawn("sonic")
        new_char()
        local fx, fy, fz = to_world(F, 100, 0, 300)
        local t_back
        for i = 1, 120 do
            next_frame()
            feed(1, fx, fy, fz, 0, 0, 1, 100 + i * 2, 0)
            view_of(0, 180)
            if not (S() and S().active) then
                t_back = i / 60
                break
            end
        end
        check(t_back and t_back > 0.27 and t_back < 0.34, "  in the open the camera hands back after the blend: %.2f s (BLEND_TIME 0.3)", t_back or -1)
    end
    -- re-created on the wall, a new grab before the camera has handed back: the whole climb again, up followed when it leaves
    do
        clear_world()
        WALLS[1].build(F)
        spawn("knuckles")
        fresh()
        on_the_wall(F, 300, 0, 180)
        GSA1.Recreate("a test")
        new_char()
        local fx, fy, fz = to_world(F, 0, 0, 300)
        for i = 1, 4 do
            next_frame()
            feed(9, fx, fy, fz, 0, 0, 1, 100 + i * 2, 0)
            view_of(0, 180)
        end
        for i = 1, 20 do
            next_frame()
            feed(24, fx, fy, fz, 0, 1, 0, 200 + i * 2, 0)
            view_of(0, 180)
        end
        for i = 1, 20 do
            next_frame()
            feed(25, fx, fy, fz, 0, 1, 0, 300 + i * 2, 0)
            view_of(0, 180)
        end
        check(S() and S().active and abs(S().oy - CENTER) < 0.01, "  re-created, then a new grab: leaving it, up is followed as on any climb (the offset %.2f)", S() and S().oy or -1)
    end
    -- another character's own mode 24 is no climb, also while the camera goes on with it
    do
        clear_world()
        WALLS[1].build(F)
        spawn("knuckles")
        fresh()
        on_the_wall(F, 300, 0, 180)
        GSA1.Spawn("sonic")
        new_char()
        local fx, fy, fz = to_world(F, 100, 0, 300)
        local t_back
        for i = 1, 120 do
            next_frame()
            feed(24, fx, fy, fz, 0, 1, 0, 100 + i * 2, 0)
            view_of(0, 180)
            if not (S() and S().active) then
                t_back = i / 60
                break
            end
        end
        check(t_back and t_back < 0.5, "  Sonic's own mode 24 keeps no climbing camera: handed back after %.2f s", t_back or -1)
    end
    -- not carried: no climbing camera at the time, the option off, a teleport, a respawn
    do
        clear_world()
        WALLS[1].build(F)
        spawn("knuckles")
        fresh()
        next_frame()
        feed(1, 0, 300, 300, 0, 0, 1, 2, 0)
        view_of(0, 180)
        GSA1.Spawn("sonic")
        new_char()
        check(C.climbCam == nil, "a switch with no climb going on: no climbing camera on the new character")
        spawn("knuckles")
        fresh()
        on_the_wall(F, 300, 0, 180)
        set_cv("gsa1_cam_climb", 0)
        GSA1.Spawn("sonic")
        new_char()
        set_cv("gsa1_cam_climb", 1)
        check(C.climbCam == nil, "the option off at a switch: 0.9.9b's camera at once")
        spawn("knuckles")
        fresh()
        on_the_wall(F, 300, 0, 180)
        GSA1.Recreate("a teleport", Vector(4000, 4000, 300))
        new_char()
        check(C.climbCam == nil, "a re-creation somewhere else (a teleport): no climbing camera on the new character")
        spawn("knuckles")
        fresh()
        on_the_wall(F, 300, 0, 180)
        C.spawnPos = Vector(C.drawPos)      -- even right where it died
        GSA1.Respawn("a test")
        new_char()
        check(C.climbCam == nil, "a respawn starts afresh: no climbing camera on the new character")
    end
end

-- (g) the polygon deep behind whatever stands in front (MEASURED with the thin-wall slider at 64, the owner's map's walls near (2019 -1124) and (1888 -944)): the ladder reaches 128
do
    local F = wall_frame(0, 1, 0)
    clear_world()
    add_wall_box(F, -300, 120, -2048, 2048, -64, 600)
    spawn("knuckles")
    fresh()
    GSA1.view.frame = nil
    local x, y, z = to_world(F, 0, 0, 100)
    local bad, v = 0, nil
    for i = 1, 30 do
        next_frame()
        feed(24, x, y, z, 0, 1, 0, i * 2, 0)
        v = view_of(0, -90)
        if is_inside(v, 4.9) then bad = bad + 1 end
    end
    local S0 = S()
    check(bad == 0 and S0 and S0.nowhere == 0 and S0.earlier == 0 and S0.along > 0 and abs(S0.ay - 125) < 0.1, "the polygon 120 behind the visible face: found along the normal (%d frames, the anchor %.2f out, nowhere %d), the eye is out", S0 and S0.along or -1, S0 and S0.ay or -1, S0 and S0.nowhere or -1)
end

-- at a corner the sweep from the earlier point goes before the far end of the ladder (a jump of 100 otherwise, MEASURED on the owner's map's corners), and something deep along the
-- normal: the far end when the sweep ended far
do
    local F = wall_frame(0, 1, 0)
    set_cv("gsa1_cam_distance", 150)
    set_cv("gsa1_cam_height", 20)
    clear_world()
    add_wall_box(F, -300, 0, -2048, 2048, -64, 600)
    add_wall_box(F, -300, 100, 0, 2048, -64, 600)     -- a block on the wall, from b = 0 on
    spawn("knuckles")
    fresh()
    GSA1.view.frame = nil
    local most, last = 0, nil
    for i = 1, 60 do
        next_frame()
        local b = -40 + i
        local x, y, z = to_world(F, 0, b, 100)
        feed(24, x, y, z, 0, 1, 0, i * 2, 0)
        view_of(0, -90)
        local S0 = S()
        if last and i > 4 then most = max(most, sqrt((S0.ax - last[1]) ^ 2 + (S0.ay - last[2]) ^ 2 + (S0.az - last[3]) ^ 2)) end
        last = { S0.ax, S0.ay, S0.az }
    end
    local S0 = S()
    check(S0.earlier > 0 and most < 2, "a block on the wall, climbing into its side: the sweep from the earlier point holds the anchor against it (%d frames), its largest move %.2f, no jump along the normal", S0.earlier, most)
    -- going on: the sweep ends further than SWEEP_NEAR from the anchor, and then the far end of the ladder takes over
    for i = 61, 140 do
        next_frame()
        local x, y, z = to_world(F, 0, -40 + i, 100)
        feed(24, x, y, z, 0, 1, 0, i * 2, 0)
        view_of(0, -90)
    end
    S0 = S()
    check(S0.along > 0 and abs(S0.ay - 105) < 0.1, "  well inside the block: the far end of the ladder, the anchor on its face (%.2f, wanted 105), %d frames", S0.ay, S0.along)
    -- the far end shut too: the sweep's far end
    clear_world()
    add_wall_box(F, -300, 0, -2048, 2048, -64, 600)
    add_wall_box(F, -300, 400, 0, 2048, -64, 600)
    fresh()
    GSA1.view.frame = nil
    for i = 1, 200 do
        next_frame()
        local x, y, z = to_world(F, 0, -40 + i, 100)
        feed(24, x, y, z, 0, 1, 0, i * 2, 0)
        view_of(0, -90)
    end
    S0 = S()
    check(S0.nowhere == 0 and S0.earlier > 100, "  deep inside something bigger: the sweep's far end is still taken (%d frames, nowhere %d)", S0.earlier, S0.nowhere)
end

-- (h) what the other cases leave open --------------------------------------------------------------------------------------------------------------------------------------
do
    local F = wall_frame(0, 1, 0)
    set_cv("gsa1_cam_distance", 150)
    set_cv("gsa1_cam_height", 20)
    local function at(mode_, x, y, z)
        next_frame()
        feed(mode_, x, y, z, 0, 1, 0, nil, 0)
    end
    local function floor_all(top)        -- something across the whole ladder: a floor brush
        plane_brush({ { 0, 0, 1, top }, { 0, 0, -1, 1000 }, { 1, 0, 0, 4096 }, { -1, 0, 0, 4096 }, { 0, 1, 0, 4096 }, { 0, -1, 0, 4096 } })
    end
    -- every trace of the climbing camera sees only the brushes
    spawn("knuckles")
    clear_world()
    WALLS[3].build(F)
    fresh()
    M.other_mask = 0
    for _ = 1, 60 do
        at(24, 0, 0, 100)
        view_of(0, 90)
    end
    floor_all(200)
    for _ = 1, 10 do
        GSA1.view.frame = nil
        at(24, 0, 0, 100)
        view_of(0, 90)
    end
    check(M.other_mask == 0, "every trace on the climb, those of the search too, is MASK_SOLID_BRUSHONLY, as 0.9.9b's (%d others)", M.other_mask)
    M.other_mask = nil
    -- a new climb knows nothing of the climb before: not its last open anchor
    clear_world()
    WALLS[1].build(F)
    spawn("knuckles")
    fresh()
    for _ = 1, 30 do
        at(24, 0, 0, 300)
        view_of(0, 90)
    end
    for k = 1, 120 do
        next_frame()
        feed(1, 0, 200, 300, 0, 0, 1, 500 + k * 2, 0)
        view_of(0, 90)
    end
    check(not S().active, "(the first climb has handed back)")
    clear_world()
    floor_all(130)      -- (that climb's last open anchor, up at z 322, is still open)
    GSA1.view.frame = nil
    at(24, 0, 0, 100)
    view_of(0, 90)
    check(S().nowhere == 1 and S().earlier == 0, "a new climb, nothing open: not the climb before's anchor (nowhere %d, an earlier point %d)", S().nowhere, S().earlier)
    -- nor its distance
    clear_world()
    WALLS[1].build(F)
    spawn("knuckles")
    fresh()
    for _ = 1, 30 do
        at(24, 0, 0, 100)
        view_of(0, 90)       -- looking away from the wall: the eye close
    end
    local close_d
    for k = 1, 120 do
        next_frame()
        feed(1, 0, 30, 100, 0, 0, 1, 500 + k * 2, 0)
        view_of(0, 90)
        if S().active then close_d = S().d end
    end
    check(not S().active, "(the first climb has handed back, its distance %.1f)", close_d or -1)
    at(24, 0, 0, 100)
    view_of(0, -90)   -- looking at the wall: the eye the whole way out on the very first frame of the climb
    check(close_d < 40 and S().d and S().d > 149, "a new climb: not the climb before's distance either (%.1f, it was %.1f)", S().d or -1, close_d or -1)
    -- the sweep from the earlier point ends at the place it stopped, not where it started
    clear_world()
    WALLS[1].build(F)
    spawn("knuckles")
    fresh()
    for _ = 1, 10 do
        at(24, 0, 0, 200)
        view_of(0, 90)
    end
    floor_all(140)
    GSA1.view.frame = nil
    at(24, 0, 0, 120)
    view_of(0, 90)
    local S0 = S()
    check(S0.earlier == 1 and abs(S0.az - 145) < 0.1 and abs(S0.ay - CENTER) < 0.1, "a floor across the anchor: the anchor is where the sweep from the earlier point stopped, on that floor (%.2f, the box on it 145)", S0.az)
    -- the eye of the frame before: of the frame before, not of long ago
    clear_world()
    floor_all(500)
    fresh()
    GSA1.view.origin, GSA1.view.frame = Vector(0, 0, 900), M.frameNo - 2       -- (next_frame adds 1: 3 old)
    at(24, 0, 0, 100)
    view_of(0, 90)
    check(S().nowhere == 1 and S().earlier == 0, "the eye of the frame before only when it is about that recent (3 frames old: nowhere %d, earlier %d)", S().nowhere, S().earlier)
    GSA1.view.frame = nil
    -- an anchor that only just touches: the sweep along the normal goes on past it, so it stops at the wall, not short of it
    clear_world()
    fresh()
    for _ = 1, 10 do
        at(24, 0, 0, 100)
        view_of(0, 90)
    end
    add_wall_box(F, -300, CENTER - 4.9, -2048, 2048, -64, 600)
    at(24, 0, 0, 100)
    view_of(0, 90)
    S0 = S()
    check(S0 and S0.along == 1 and abs(S0.ay - (CENTER - 4.9 + 5 + 0.03125)) < 0.02, "the anchor's box 0.1 inside: the nearest open place is right at the wall (%.3f, wanted %.3f)", S0 and S0.ay or -1, CENTER - 4.9 + 5 + 0.03125)
    -- the same for the sweep from the earlier point: touching at its very end
    clear_world()
    fresh()
    for _ = 1, 10 do
        at(24, 0, 0, 200)
        view_of(0, 90)
    end
    floor_all(100 - 5)
    GSA1.view.frame = nil
    at(24, 0, 0, 100)
    view_of(0, 90)
    S0 = S()
    check(S0 and S0.nowhere == 0 and S0.earlier == 1, "the box only just touching a floor at the end of the sweep from the earlier point: it is stopped (earlier %d, nowhere %d)", S0 and S0.earlier or -1, S0 and S0.nowhere or -1)
end

-- (i) the session log: one line for each climb, however it ended
do
    local F = wall_frame(0, 1, 0)
    clear_world()
    WALLS[1].build(F)
    local function count(setup)
        spawn("knuckles")
        fresh()
        local lines, restore = log_catcher()
        on_the_wall(F, 300, 0, 180)
        setup()
        restore()
        return #lines, lines[1]
    end
    local function away(n)
        C = GSA1.Char
        local fx, fy, fz = to_world(F, 100, 0, 300)
        for i = 1, n or 120 do
            next_frame()
            feed(1, fx, fy, fz, 0, 0, 1, 100 + i * 2, 0)
            view_of(0, 180)
        end
    end
    local n, l = count(away)
    check(n == 1 and string.find(tostring(l), "handed back", 1, true), "the log: a climb that hands back, one line: %s", tostring(l))
    n, l = count(function()
        set_cv("gsa1_cam_climb", 0)
        next_frame()
        feed(24, 0, 0, 300, 0, 1, 0, 9000, 0)
        view_of(0, 180)
        set_cv("gsa1_cam_climb", 1)
    end)
    check(n == 1 and string.find(tostring(l), "untick", 1, true), "the log: unticked on the wall, one line: %s", tostring(l))
    n, l = count(function()
        GSA1.Spawn("sonic")
        away()
    end)
    check(n == 1, "the log: switched on the wall, one line when the camera hands back: %s", tostring(l))
    n, l = count(function()
        GSA1.Recreate("a test")
        away()
    end)
    check(n == 1, "the log: re-created on the wall, one line: %s", tostring(l))
    n, l = count(function()
        GSA1.Recreate("a teleport", Vector(4000, 4000, 300))
    end)
    check(n == 1 and string.find(tostring(l), "went", 1, true), "the log: teleported off the wall, one line: %s", tostring(l))
    n, l = count(function()
        GSA1.Respawn("a test")
    end)
    check(n == 1 and string.find(tostring(l), "went", 1, true), "the log: respawned on the wall, one line: %s", tostring(l))
    n, l = count(function()
        GSA1.Remove(true)
    end)
    check(n == 1 and string.find(tostring(l), "went", 1, true), "the log: removed on the wall, one line: %s", tostring(l))
    n, l = count(function()
        GSA1.Spawn("sonic")
        GSA1.Remove(true)
    end)
    check(n == 1, "the log: switched, then removed before the hand back, still one line: %s", tostring(l))
    spawn("knuckles")
end

-- 8. garbage: a frame on the wall makes what a frame on the ground makes --------------------------------------------------------------------------------------------
do
    spawn("knuckles")
    local F = wall_frame(0, 1, 0)
    clear_world()
    WALLS[2].build(F)
    local function per_frame(fn, n)
        for i = 1, 3000 do fn(i) end     -- warm: the JIT (its traces are in the count) and the state tables
        local best = math.huge
        for _ = 1, 4 do
            collectgarbage("collect")
            collectgarbage("stop")
            local k0 = collectgarbage("count")
            for i = 1, n do fn(i) end
            local k1 = collectgarbage("count")
            collectgarbage("restart")
            best = min(best, (k1 - k0) * 1024 / n)
        end
        return best
    end
    local ground = per_frame(function(i)
        next_frame()
        feed(1, 0, 200, 0, 0, 0, 1)
        view_of(0, 90)
    end, 300)
    local wall = per_frame(function(i)
        next_frame()
        feed(24, 0, 0, 100, 0, 1, 0)
        view_of(0, 90)
    end, 300)
    check(wall <= ground + 32, "the Lua garbage of a frame on the wall %.0f bytes, on the ground %.0f bytes (the traces' results and the view table, in this mock)", wall, ground)
    -- on the ground and for others no trace is added: the recording's counts say the same
    next_frame()
    feed(1, 0, 200, 0, 0, 0, 1)
    fresh()
    local n0 = M.ntrace
    view_of(0, 90)
    check(M.ntrace - n0 == 2 and C.climbCam == nil, "a frame that is no climb: 2 traces as 0.9.9b, and no state made for it (%s)", tostring(C.climbCam))
    for _ = 1, 10 do
        next_frame()
        feed(24, 0, 0, 100, 0, 1, 0)
        view_of(0, 90)
    end
    next_frame()
    feed(24, 0, 0, 100, 0, 1, 0)
    n0 = M.ntrace
    view_of(0, 90)
    check(M.ntrace - n0 == 2, "a frame on the wall, the anchor open: 2 traces, the same 2 as 0.9.9b's (%d)", M.ntrace - n0)
end

-- 9. the whole client frame: the module's state through GetState and Render ------------------------------------------------------------------------------------------
do
    spawn("knuckles")
    local F = wall_frame(0, 1, 0)
    clear_world()
    WALLS[2].build(F)
    set_cv("gsa1_cam_height", 20)
    local gs, rn = G.GetState, G.Render
    local cur
    G.GetState = function(id, out)
        local r = gs(id, out)
        if r and cur then
            r.mode, r.upx, r.upy, r.upz = cur.mode, cur.ux, cur.uy, cur.uz
            r.x, r.y, r.z, r.step = cur.x, cur.y, cur.z, cur.step
        end
        return r
    end
    G.Render = function(id, alpha)
        local a, b, x, y, z, yaw, interp, al, tris, shifted = rn(id, alpha)
        if a and cur then x, y, z, al = cur.x, cur.y, cur.z, cur.alpha end
        return a, b, x, y, z, yaw, interp, al, tris, shifted
    end
    M.reported = {}
    local bad = 0
    local fr = frames_of(pair_path({ rest = 20, up = 10, leave = "jump" }), F)
    local seen_active = false
    for _, f in ipairs(fr) do
        cur = f
        M.pitch, M.yaw = 0, 90    -- looking away from the wall
        M.frame(1 / 60)
        local o = GSA1.view and GSA1.view.origin
        if (f.mode == 24) and (not o or overlaps(o.x, o.y, o.z, 4.9)) then bad = bad + 1 end
        if S() and S().active then seen_active = true end
    end
    cur = nil
    G.GetState, G.Render = gs, rn
    check(seen_active and bad == 0 and #M.reported == 0, "Think, CalcView, the draws, PostRender on a climb: the frame's view (GSA1.view, what the sound and the game's camera read) is out of the wall on every frame (%d bad), no Lua error (%d)", bad, #M.reported)
end

return done()
