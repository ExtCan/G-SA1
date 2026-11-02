-- feat_gamecam_test.lua - Big's fishing camera, the Lua half (feature "gamecam"; round 0.9.8: sadc docs/research/gsa1_098_plan.md
-- 5.5, 5.6, 5.9, 6.9 with its review R98.12, R98.14, R98.21; fish098.md 4, 6.3 G3-G10). The addon's client through its autorun on
-- tests/lua_mock.lua, in Garry's Mod's own LuaJIT, with a local mock of the feature's module part (gsa1.Camera follows libsa1's
-- rule: a known request is RUNNING only after a tick with the bit):
--   lua_host tests/feat_gamecam_test.lua <tests dir> <addon/lua dir>
-- The mock is checked against build/<target>/gamecam_api.txt (feat_gamecam_binding_test.cpp writes it) as soon as the snapshot
-- header build/deps/include/libsa1.h defines SA1_API_CAMERA (5.5); before that the check is skipped with a message.
--
-- API NOTES (098-gsa1-gamecam, the full text; the report carries a summary):
--   * Module (src/module/bind_gamecam.cpp, #if defined(SA1_API_CAMERA)): gsa1.Camera(id, alpha, out) -> true | false, message, code.
--     Fills the caller's table with flags, kind, level, adjust, fn, px, py, pz, fx, fy, fz, tx, ty, tz, fov (Hammer units; fov in
--     radians, libsa1's); no table is made per call; alpha < 0 is libsa1's accumulator. false for an unknown id ("not_found"), bad
--     arguments ("bad_argument"), a puppet, and libsa1's refusals ("unsupported" while its gate is closed, "not loaded" without a
--     world). Constants gsa1.INPUT_GAME_CAMERA, gsa1.CAMSTATE_{ACTIVE, KNOWN, RUNNING, CUT}, gsa1.CAMKIND_{NONE, AIM, LURE, CATCH,
--     OTHER}. gsa1.FEATURES.gamecam = 1.
--   * Lua (feat/cl_gamecam.lua): GSA1.GameCam = G; G.st (gsa1.Camera's table), G.mix (0 your camera .. 1 the game's), G.chase (the
--     view everybody else sees, the chain's result), G.Allowed(C), G.Running(C), G.Locked(), G.Toggle(), G.Reset(), G.Panel(panel).
--   * Chained, each keeping the previous value, at file scope: GSA1.HostWaterFlags (only C == GSA1.Char and Big; followers' flags stay
--     water bits), GSA1.TickYaw, GSA1.ViewOverride, GSA1.FirstPerson, GSA1.PadView, GSA1.FollowerTickCamera (G.chase while G.mix > 0;
--     decision A9). Once, at the first GSA1CharacterCreated (2.4 C4): GSA1.ExtraButtons.
--   * Hooks with the id gsa1_gamecam: InputMouseApply, CreateMove, GSA1PreTick (the toggle's key), GSA1CharacterCreated, Removed, Died.
--   * cl_menu.lua's seams: GSA1.CameraPanelExtra(panel), GSA1.RenderingPanelExtra(panel) (the second is 098-gsa1-nativemesh's). Each is
--     an if and a call at the end of its page.
--   * Reads GSA1.RENDER_BOUNDS_MIN / MAX (cl_render.lua, L1), C.ent, C.drawPos, C.kind, C.id, C.death; session log lines "gamecam" (one
--     per request change) and one "settings" line per change at a new character.
-- UNVERIFIED by this test (the game only): SetRenderBounds against Source's PVS, the view under water, the blends' feel.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_gamecam_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end
local function vnear(a, b, eps) return a and b and near(a.x, b.x, eps) and near(a.y, b.y, eps) and near(a.z, b.z, eps) end
local function fv(v) return v and string.format("%.2f %.2f %.2f", v.x, v.y, v.z) or "nil" end

local MG = M.module({})          -- the feature is absent first
GSA1 = nil
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferrs = GSA1 and GSA1.FeatureFileErrors or {}
check(ok_load and #ferrs == 0, "the addon loads through its autorun with cl_gamecam.lua in its place (%s)",
    tostring(err_load or ferrs[1] or "ok"))
if not ok_load then return done() end
local G = GSA1.GameCam
check(type(G) == "table" and type(G.Allowed) == "function", "GSA1.GameCam exists")
if type(G) ~= "table" then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
local function frames(n, dt) for _ = 1, n do M.frame(dt or 1 / 60) end end
local function hflags() return M.ticks.last and M.ticks.last.hflags or 0 end
local band = bit.band

-- a stand-in for the DForm (as feat_interact_test.lua), for the pages
local made = {}
local METHODS
local function standin(kind)
    local P = { kind = kind, calls = {} }
    made[#made + 1] = P
    return setmetatable(P, { __index = function(t, k)
        if METHODS[k] then return METHODS[k] end
        if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
        return function(self, ...)
            t.calls[#t.calls + 1] = { k, ... }
            return standin(k)
        end
    end })
end
METHODS = { SetText = function(self, s) self.text = s end, SetValue = function(self, s) self.value = s end,
            SetConVar = function(self, c) self.convar = c end }
vgui.Create = function(cls) return standin(cls) end
local function camera_page()
    made = {}
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    local entry
    for _, e in ipairs(M.menu) do if e.class == "gsa1_camera" then entry = e end end
    local panel = standin("DForm")
    entry.cpanel(panel)
    local page = { help = {}, checks = {}, sliders = {}, combos = {}, binders = {} }
    for _, P in ipairs(made) do
        for _, c in ipairs(P.calls) do
            if c[1] == "Help" or c[1] == "ControlHelp" then page.help[#page.help + 1] = tostring(c[2]) end
            if c[1] == "CheckBox" then page.checks[c[3]] = c[2] end
            if c[1] == "NumSlider" then page.sliders[c[3]] = { c[2], c[4], c[5] } end
            if c[1] == "ComboBox" then page.combos[#page.combos + 1] = c[2] end
        end
        if P.kind == "DBinder" then page.binders[#page.binders + 1] = P.convar end
    end
    page.text = table.concat(page.help, "\n")
    page.all = made
    return page
end

-- 0. the seams of cl_menu.lua -----------------------------------------------------------------------------------------------------
do
    local saved_c, saved_r = GSA1.CameraPanelExtra, GSA1.RenderingPanelExtra
    GSA1.CameraPanelExtra = nil
    local a = camera_page()
    GSA1.CameraPanelExtra = saved_c
    check(a.checks.gsa1_cam_real ~= nil and a.sliders.gsa1_cam_distance ~= nil and #a.combos == 0,
        "the Camera page without the seam's function: its own rows only")
    check(string.find(a.text, "follow that camera instead", 1, true) ~= nil and string.find(a.text, "follow the camera you see.", 1, true) ~= nil,
        "gsa1_cam_real's help text says what happens while the fishing camera shows (review R98.21)")
    local got
    GSA1.RenderingPanelExtra = function(p) got = p end
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    local entry
    for _, e in ipairs(M.menu) do if e.class == "gsa1_rendering" then entry = e end end
    local rp = standin("DForm")
    entry.cpanel(rp)
    local last = rp.calls[#rp.calls]
    check(got == rp and last and last[1] == "CheckBox" and last[3] == "gsa1_debug",
        "GSA1.RenderingPanelExtra(panel) is called at the end of the Rendering page")
    GSA1.RenderingPanelExtra = saved_r
end

-- 1. the feature absent: the page says what it needs, nothing else changes -------------------------------------------------------
do
    local p = camera_page()
    check(string.find(p.text, "gamecam", 1, true) ~= nil and string.find(p.text, "0.9.8", 1, true) ~= nil and #p.combos == 0,
        "the feature absent: the page says what it needs, no fishing rows")
    GSA1.Spawn("big")
    local C = GSA1.Char
    check(C ~= nil and C.kind == 7, "Big spawned")
    frames(3)
    check(band(hflags(), 8) == 0 and GSA1.ViewOverride({ origin = Vector(), angles = Angle() }, C, M.player) == nil
        and GSA1.TickYaw(C) == nil and G.mix == 0, "the feature absent: no bit, no view, no stick's frame")
    GSA1.Remove(true)
end

-- the feature: a local mock of 5.5 ------------------------------------------------------------------------------------------------
local CAMAPI = { INPUT_GAME_CAMERA = 8, CAMSTATE_ACTIVE = 1, CAMSTATE_KNOWN = 2, CAMSTATE_RUNNING = 4, CAMSTATE_CUT = 8,
                 CAMKIND_NONE = 0, CAMKIND_AIM = 1, CAMKIND_LURE = 2, CAMKIND_CATCH = 3, CAMKIND_OTHER = 4 }
for k, v in pairs(CAMAPI) do MG[k] = v end
MG.FEATURES.gamecam = 1
local cam = { level = 0, kind = 0, adjust = 0, fn = 0, px = 0, py = 0, pz = 0, fx = 1, fy = 0, fz = 0, tx = 0, ty = 0, tz = 0,
              fov = math.rad(70), cut = false }
local camera_calls = 0
function MG.Camera(id, alpha, out)
    camera_calls = camera_calls + 1
    local c = M.mchars[id]
    if not c or type(out) ~= "table" then return false, "no such character", "not_found" end
    local fl = 0
    if cam.level > 0 then fl = 1 end
    if cam.kind >= 1 and cam.kind <= 3 then fl = bit.bor(fl, 2) end
    if band(fl, 3) == 3 and band(c.hflags or 0, 8) ~= 0 then fl = bit.bor(fl, 4) end    -- a request runs only in a tick with the bit
    if cam.cut then fl = bit.bor(fl, 8) end
    out.flags, out.kind, out.level, out.adjust, out.fn = fl, cam.kind, cam.level, cam.adjust, cam.fn
    out.px, out.py, out.pz, out.fx, out.fy, out.fz = cam.px, cam.py, cam.pz, cam.fx, cam.fy, cam.fz
    out.tx, out.ty, out.tz, out.fov = cam.tx, cam.ty, cam.tz, cam.fov
    return true
end
local function no_request()
    cam.level, cam.kind, cam.adjust, cam.fn, cam.cut = 0, 0, 0, 0, false
end
-- AIM: the eye 200 HU south and 100 HU above Big, looking north (yaw 90, pitch 0); the target elsewhere on purpose: a look-at differs
local function aim(C, adjust)
    local p = C.drawPos
    cam.level, cam.kind, cam.adjust, cam.fn = 2, 1, adjust or 3, 0x8C0239C2
    cam.px, cam.py, cam.pz = p.x, p.y - 200, p.z + 100
    cam.fx, cam.fy, cam.fz = 0, 1, 0
    cam.tx, cam.ty, cam.tz = p.x + 300, p.y + 40, p.z - 20
end
-- LURE: the eye about 650 HU out, the lure 60 HU in front of it
local function lure(C, dist)
    local p = C.drawPos
    dist = dist or 700
    cam.level, cam.kind, cam.adjust, cam.fn = 4, 2, 0, 0x8C0EAF28
    cam.px, cam.py, cam.pz = p.x + dist - 60, p.y, p.z + 40
    cam.fx, cam.fy, cam.fz = 1, 0, 0
    cam.tx, cam.ty, cam.tz = p.x + dist, p.y, p.z
end

-- traces: recorded; a test may make them hit
local traces, trace_hit, trace_startsolid = {}, nil, false
local trace0 = util.TraceHull
util.TraceHull = function(t)
    traces[#traces + 1] = { start = Vector(t.start), endpos = Vector(t.endpos), mask = t.mask, mins = Vector(t.mins), maxs = Vector(t.maxs) }
    local r = trace0(t)
    r.StartSolid = trace_startsolid
    if trace_hit then
        r.HitPos, r.Hit = Vector(trace_hit), true
    end
    return r
end

-- the addon's session log, recorded
local logged = {}
local log0 = GSA1.Log
GSA1.Log = function(kind, fmt, ...)
    logged[#logged + 1] = { kind = kind, text = string.format(fmt, ...) }
    if log0 then return log0(kind, fmt, ...) end
end
local function logs(kind)
    local n = 0
    for _, l in ipairs(logged) do if l.kind == kind then n = n + 1 end end
    return n
end

-- 2. G3: the view ----------------------------------------------------------------------------------------------------------------
GSA1.Spawn("big")
local C = GSA1.Char
check(C ~= nil and G.extraDone == true, "Big spawned again with the feature; GSA1.ExtraButtons wrapped at the first character")
do
    local found
    for _, l in ipairs(logged) do
        if l.kind == "settings" and string.find(l.text, "gsa1_cam_fish", 1, true) then found = l.text end
    end
    check(found ~= nil and string.find(found, "blend 0.3", 1, true) ~= nil and string.find(found, "module's feature yes", 1, true) ~= nil,
        "one settings line with the seven settings (%s)", tostring(found))
end
frames(2)
no_request()
frames(2)
check(G.mix == 0 and band(hflags(), 8) == 8, "Big, no request: the bit goes (it changes nothing in libsa1 without a request); no mix")
check(GSA1.view.origin ~= nil and GSA1.ViewOverride({ origin = Vector(1, 2, 3), angles = Angle(4, 5, 0), fov = 90 }, C, M.player) == nil,
    "no request: the chain's result, nothing of this camera")
local yaw0 = M.yaw
aim(C)
local DT = 0.05
M.frame(DT)                                                                  -- the first tick has the bit; CalcView sees RUNNING
local mix1 = G.mix
check(near(mix1, DT / 0.3), "AIM: the blend starts: mix %.4f after one frame of %.0f ms (%.4f)", mix1, DT * 1000, DT / 0.3)
local last = traces[#traces]
local eye80 = Vector(C.drawPos.x, C.drawPos.y, C.drawPos.z + 80)
check(last and vnear(last.start, eye80) and vnear(last.endpos, Vector(cam.px, cam.py, cam.pz)) and last.mask == MASK_SOLID_BRUSHONLY
    and last.mins.x == -5 and last.maxs.z == 5, "AIM: the 5-HU hull trace goes from Big + 80 HU to the game's eye (%s -> %s)",
    fv(last and last.start), fv(last and last.endpos))
M.frame(DT)
M.frame(DT)
check(near(G.mix, 0.5), "mix 0.5 at 0.15 s (%.4f)", G.mix)
local ch = G.chase
local want = Vector(ch.origin.x + (cam.px - ch.origin.x) * 0.5, ch.origin.y + (cam.py - ch.origin.y) * 0.5,
    ch.origin.z + (cam.pz - ch.origin.z) * 0.5)
check(vnear(GSA1.view.origin, want), "at 0.15 s the view's origin is half way between your camera and the game's (%s; %s)",
    fv(GSA1.view.origin), fv(want))
check(near(GSA1.view.angles.y, ch.angles.y + math.NormalizeAngle(90 - ch.angles.y) * 0.5) and near(GSA1.view.angles.p, ch.angles.p * 0.5),
    "at 0.15 s the view's angles are half way, the short way round (yaw %.2f, pitch %.2f)", GSA1.view.angles.y, GSA1.view.angles.p)
M.frame(DT)
M.frame(DT)
M.frame(DT)
check(near(G.mix, 1), "mix 1 at 0.3 s (%.4f)", G.mix)
check(vnear(GSA1.view.origin, Vector(cam.px, cam.py, cam.pz)) and near(GSA1.view.angles.y, 90) and near(GSA1.view.angles.p, 0),
    "at 0.3 s the view is the game's: origin %s, angles from forward (pitch %.2f, yaw %.2f), not at the target", fv(GSA1.view.origin),
    GSA1.view.angles.p, GSA1.view.angles.y)
check(GSA1.view.fov == M.fov, "the field of view stays yours by default (%.1f)", GSA1.view.fov)
do
    trace_hit = Vector(cam.px, cam.py + 30, cam.pz)
    M.frame(1 / 60)
    check(vnear(GSA1.view.origin, trace_hit), "a wall between Big and the eye: the shown view stops at the trace's hit (%s)", fv(GSA1.view.origin))
    check(G.st.py == cam.py, "the game's numbers stay (only the shown view moved)")
    trace_startsolid = true
    M.frame(1 / 60)
    check(vnear(GSA1.view.origin, Vector(cam.px, cam.py, cam.pz)), "a trace that starts in a brush moves nothing (%s)", fv(GSA1.view.origin))
    trace_hit, trace_startsolid = nil, false
end
-- LURE: the trace starts at the target
lure(C)
M.frame(1 / 60)
last = traces[#traces]
check(last and vnear(last.start, Vector(cam.tx, cam.ty, cam.tz)) and vnear(last.endpos, Vector(cam.px, cam.py, cam.pz)),
    "LURE: the trace goes from the target to the eye (%s -> %s)", fv(last and last.start), fv(last and last.endpos))
-- CUT: inside the camera, no blend; the field of view with the option
cam.cut = true
M.frame(1 / 60)
check(G.mix == 1, "a CUT with the mix at 1 stays a cut")
cam.cut = false
M.convars.gsa1_cam_fish_fov:SetString("1")
M.frame(1 / 60)
check(near(GSA1.view.fov, 70), "gsa1_cam_fish_fov 1: the game's 70 degrees (%.2f)", GSA1.view.fov)
M.convars.gsa1_cam_fish_fov:SetString("0")
-- the end: toward the moving chase view
no_request()
local gameO = Vector(G.gameO)
M.yaw = yaw0
M.frame(DT)
check(near(G.mix, 1 - DT / 0.3), "the end: the mix falls (%.4f)", G.mix)
for i = 1, 2 do
    M.yaw = M.yaw + 20
    M.frame(DT)
    local m, c2 = G.mix, G.chase
    local w = Vector(c2.origin.x + (gameO.x - c2.origin.x) * m, c2.origin.y + (gameO.y - c2.origin.y) * m, c2.origin.z + (gameO.z - c2.origin.z) * m)
    check(vnear(GSA1.view.origin, w) and near(m, 1 - (i + 1) * DT / 0.3), "the way back, frame %d: toward the live chase view "
        .. "(mix %.3f, origin %s, chase yaw %.0f)", i, m, fv(GSA1.view.origin), c2.angles.y)
end
frames(4, DT)
check(G.mix == 0 and vnear(GSA1.view.origin, G.chase.origin), "mix 0: your camera again (%s)", fv(GSA1.view.origin))
M.yaw = yaw0
-- a cut in the blend in: at once; at mix 0 the blend still runs
aim(C)
M.frame(DT)
check(near(G.mix, DT / 0.3), "a new request starts the blend from 0")
cam.cut = true
M.frame(DT)
check(G.mix == 1, "a CUT during the blend: the camera jumps, as the game's does")
cam.cut = false
no_request()
frames(8, DT)
cam.cut = true
aim(C)
M.frame(DT)
check(near(G.mix, DT / 0.3), "a CUT at mix 0 is the blend's business (mix %.3f)", G.mix)
cam.cut = false
no_request()
frames(8, DT)
-- blend 0: at once both ways
M.convars.gsa1_cam_fish_blend:SetString("0")
aim(C)
frames(2, DT)
local at_once = G.mix
no_request()
frames(1, DT)
check(at_once == 1 and G.mix == 0, "blend 0: at once, both ways")
M.convars.gsa1_cam_fish_blend:SetString("0.3")

-- 3. G4: when the bit goes -----------------------------------------------------------------------------------------------------
do
    aim(C)
    frames(2, DT)
    check(band(hflags(), 8) == 8, "As the game: the bit goes while aiming")
    M.convars.gsa1_cam_fish:SetString("0")
    local c0 = camera_calls
    frames(3, DT)
    check(band(hflags(), 8) == 0 and camera_calls == c0 and G.st.flags == 0, "Off: no bit, gsa1.Camera is not even asked")
    frames(8, DT)
    check(G.mix == 0 and GSA1.ViewOverride({ origin = Vector(), angles = Angle() }, C, M.player) == nil, "Off: ViewOverride gives nothing")
    M.convars.gsa1_cam_distance:SetString("0")
    check(GSA1.FirstPerson() == true, "Off: FirstPerson is the character's as ever")
    M.convars.gsa1_cam_distance:SetString("150")
    -- Lure only
    M.convars.gsa1_cam_fish:SetString("1")
    aim(C)
    frames(3, DT)
    check(band(hflags(), 8) == 0 and G.mix == 0, "Lure only: no bit while aiming; your camera")
    lure(C)
    M.frame(DT)                                                              -- this frame's CalcView reads kind LURE
    local f1 = band(hflags(), 8)
    M.frame(DT)
    check(f1 == 0 and band(hflags(), 8) == 8, "Lure only: the bit from the frame after kind LURE was read (%d, then %d)", f1, band(hflags(), 8))
    frames(2, DT)
    check(G.mix > 0, "Lure only: the view goes to the lure")
    no_request()
    frames(8, DT)
    M.convars.gsa1_cam_fish:SetString("2")
    -- a Camera-tool view
    aim(C)
    frames(8, DT)
    check(G.mix == 1, "As the game: showing")
    M.player.view_entity = {}
    M.frame(DT)
    M.frame(DT)
    check(band(hflags(), 8) == 0 and not G.Allowed(C) and GSA1.TickYaw(C) == nil and not G.Locked(), "a Camera-tool view: no bit, no frame, not locked")
    M.player.view_entity = NULL
    check(G.Allowed(C), "no view entity at all (NULL): no Camera tool, as CalcView's own test")
    M.player.view_entity = nil
    frames(1, DT)
    check(G.Allowed(C), "back from the Camera tool: allowed again")
    no_request()
    frames(8, DT)
    -- a follower's flags stay water bits, and no view for anybody else
    aim(C)
    frames(2, DT)
    local bigf = { kind = 7, id = C.id, state = C.state, follower = true }
    check(band(GSA1.HostWaterFlags(bigf), 8) == 0 and GSA1.TickYaw(bigf) == nil, "a Big follower: water bits only, no yaw of this camera")
    no_request()
    frames(8, DT)
end

-- 4. death ------------------------------------------------------------------------------------------------------------------------
lure(C)
frames(8, DT)
check(G.mix == 1 and band(hflags(), 8) == 8, "the lure in the water: showing")
hook.Run("GSA1CharacterDied", C, 1, {})
M.frame(DT)
M.frame(DT)
check(band(hflags(), 8) == 0 and G.mix < 1, "GSA1CharacterDied: the bit stops, the view starts back (mix %.3f)", G.mix)
frames(8, DT)
check(G.mix == 0 and not G.Locked(), "... and is back; the game's request is still on (level %d), as the game's own rule", G.st.level)
no_request()
GSA1.Spawn("big")
C = GSA1.Char
frames(2, DT)
check(not G.dead and band(hflags(), 8) == 8 and G.mix == 0, "the respawn: a new world, the bit is allowed again")

-- 5. G5: the stick's frame, the mouse, the right stick, the eye angles ---------------------------------------------------------------
do
    local rec = {}
    local cmd = { SetMouseX = function(_, v) rec.mx = v end, SetMouseY = function(_, v) rec.my = v end,
                  GetViewAngles = function() return Angle(M.pitch, M.yaw, 0) end, SetViewAngles = function(_, a) rec.a = Angle(a) rec.n = (rec.n or 0) + 1 end,
                  GetMouseX = function() return 0 end, GetMouseY = function() return 0 end, KeyDown = function() return false end }
    local create = M.hooks.CreateMove.gsa1_gamecam
    local mouse = M.hooks.InputMouseApply.gsa1_gamecam
    check(mouse(cmd, 10, 10, Angle()) == nil and rec.mx == nil, "no request: the mouse is yours")
    check(GSA1.TickYaw(C) == nil, "no request: the stick's frame is the view's")
    aim(C)
    cam.fx, cam.fy, cam.fz = -0.5, -math.sqrt(3) / 2, 0
    local yaw_want = math.deg(math.atan2(cam.fy, cam.fx))
    M.frame(DT)
    check(near(GSA1.TickYaw(C), yaw_want), "RUNNING: GSA1.TickYaw is forward's yaw (%.3f; %.3f)", tonumber(GSA1.TickYaw(C)) or 0, yaw_want)
    M.frame(DT)
    check(near(M.ticks.last.yaw, yaw_want), "the tick gets it")
    create(cmd)
    check(G.mix < 1 and rec.n == nil, "during the blend in the eye angles stay: the chase view it starts from does not move (mix %.3f)", G.mix)
    check(mouse(cmd, 10, -7, Angle()) == true and rec.mx == 0 and rec.my == 0, "locked: InputMouseApply swallows the mouse")
    GSA1.Wheel.open = true
    check(mouse(cmd, 10, -7, Angle()) == nil, "the open wheel wins (its own hook swallows too)")
    GSA1.Wheel.open = false
    frames(5, DT)
    create(cmd)
    check(G.mix == 1 and rec.n == 1 and near(rec.a.y, yaw_want) and near(rec.a.p, 0), "shown: SetViewAngles with the game's angles (%.2f %.2f)", rec.a.p, rec.a.y)
    cam.fx, cam.fy, cam.fz = 0, 0, -1
    M.frame(DT)
    create(cmd)
    check(near(rec.a.p, 89), "pitch clamped at +-89 (forward straight down: %.2f)", rec.a.p)
    cam.fx, cam.fy, cam.fz = 0, 0, 1
    M.frame(DT)
    create(cmd)
    check(near(rec.a.p, -89), "pitch clamped at +-89 (forward straight up: %.2f)", rec.a.p)
    cam.fx, cam.fy, cam.fz = 0, 1, 0
    M.frame(DT)
    -- the right stick: a stand-in command while locked
    local got = {}
    local prev = G.prevPadView
    G.prevPadView = function(c)
        got.mx = c:GetMouseX()
        got.ang = c:GetViewAngles()
        c:SetViewAngles(Angle(1, 2, 3))
        got.same = c == cmd
    end
    local n0 = rec.n
    GSA1.PadView(cmd)
    check(got.mx == 1 and got.ang ~= nil and rec.n == n0 and got.same == false, "locked: the pad's turn goes to a stand-in (no SetViewAngles reaches the command; "
        .. "a reset is dropped by its mouse move)")
    no_request()
    frames(8, DT)
    got = {}
    GSA1.PadView(cmd)
    check(got.same == true and rec.n == n0 + 1, "not locked: the pad's turn reaches the command")
    G.prevPadView = prev
    -- not locked at the way back: the mouse is yours, the eye angles too
    aim(C)
    frames(8, DT)
    no_request()
    M.frame(DT)
    check(G.mix > 0 and G.mix < 1 and mouse(cmd, 3, 3, Angle()) == nil, "the way back: the mouse is yours again (mix %.3f)", G.mix)
    frames(8, DT)

    -- the orbit (view only)
    M.convars.gsa1_cam_fish_mouse:SetString("1")
    lure(C)
    frames(8, DT)
    local base = Vector(GSA1.view.origin)
    check(vnear(base, Vector(cam.px, cam.py, cam.pz)), "orbit on, no mouse yet: the game's view")
    mouse(cmd, -5000, 5000, Angle())
    check(G.orbitY == 60 and G.orbitP == 30, "the offsets are clamped at +-60, +-30 (%.1f, %.1f)", G.orbitY, G.orbitP)
    mouse(cmd, 50000, -5000, Angle())
    check(G.orbitY == -60 and G.orbitP == -30, "... both ways (%.1f, %.1f)", G.orbitY, G.orbitP)
    G.orbitY, G.orbitP = 90, 0                                               -- a quarter turn, to check the geometry
    M.frame(DT)
    local d = GSA1.view.origin - Vector(cam.tx, cam.ty, cam.tz)
    local d0 = Vector(cam.px - cam.tx, cam.py - cam.ty, cam.pz - cam.tz)
    check(near(d:Length(), d0:Length(), 1e-2) and near(d.x, -d0.y, 1e-2) and near(d.y, d0.x, 1e-2), "the eye turned around the target (%s from it)", fv(d))
    check(near(GSA1.view.angles.y, 90) and near(G.st.px, cam.px), "the view's yaw turned with it; the game's numbers stay")
    create(cmd)
    check(near(rec.a.y, 0), "the eye angles stay the game's while the view orbits (%.2f)", rec.a.y)
    last = traces[#traces]
    check(vnear(last.start, Vector(cam.tx, cam.ty, cam.tz)), "orbit: the trace starts at the target")
    aim(C)
    M.frame(DT)
    last = traces[#traces]
    check(vnear(last.start, Vector(cam.tx, cam.ty, cam.tz)), "orbit: also for AIM")
    no_request()
    frames(2, DT)
    check(G.orbitY == 0 and G.orbitP == 0, "the offsets are cleared when the request ends")
    frames(8, DT)
    M.convars.gsa1_cam_fish_mouse:SetString("0")
end

-- 6. G6: the render bounds ----------------------------------------------------------------------------------------------------------
do
    local sets = {}
    C.ent.SetRenderBounds = function(self, lo, hi) sets[#sets + 1] = { lo = Vector(lo), hi = Vector(hi) } end
    aim(C)
    cam.tx, cam.ty, cam.tz = C.drawPos.x + 100, C.drawPos.y, C.drawPos.z
    frames(8, DT)
    check(#sets == 0, "AIM near Big: the character's own box is enough, no call (%d)", #sets)
    lure(C, 700)
    M.frame(DT)
    local s = sets[#sets]
    check(#sets == 1 and s, "LURE at 700 HU: one SetRenderBounds")
    if s then
        local p = C.drawPos
        local tx, ex = cam.tx - p.x, cam.px - p.x
        check(s.hi.x >= tx + 256 - 1e-3 and s.hi.x >= ex + 64 - 1e-3 and near(s.hi.x, tx + 256), "it covers the target + 256 and the eye + 64 HU (hi.x %.1f; target %.1f, eye %.1f)",
            s.hi.x, tx, ex)
        check(near(s.lo.x, GSA1.RENDER_BOUNDS_MIN.x) and near(s.lo.z, GSA1.RENDER_BOUNDS_MIN.z) and near(s.hi.z, GSA1.RENDER_BOUNDS_MAX.z) and near(s.hi.y, GSA1.RENDER_BOUNDS_MAX.y),
            "the union with the character's own box (%s .. %s)", fv(s.lo), fv(s.hi))
    end
    local n = #sets
    lure(C, 730)
    frames(3, DT)
    check(#sets == n, "a change of 30 HU: no call")
    lure(C, 800)
    frames(2, DT)
    check(#sets == n + 1 and near(sets[#sets].hi.x, 800 + 256), "a change of 100 HU: one call (hi.x %.1f)", sets[#sets].hi.x)
    n = #sets
    no_request()
    M.frame(DT)
    check(#sets == n and G.mix > 0, "the way back: the box stays while the view is still out there")
    frames(8, DT)
    s = sets[#sets]
    check(#sets == n + 1 and G.mix == 0 and vnear(s.lo, GSA1.RENDER_BOUNDS_MIN) and vnear(s.hi, GSA1.RENDER_BOUNDS_MAX), "restored at the end, to the named box of cl_render.lua (%s .. %s)", fv(s.lo), fv(s.hi))
    frames(3, DT)
    check(#sets == n + 1, "nothing more after that")
    C.ent.SetRenderBounds = function() end
end

-- 7. G7: first person ---------------------------------------------------------------------------------------------------------------
do
    M.convars.gsa1_cam_distance:SetString("0")
    frames(2, DT)
    check(GSA1.FirstPerson() == true, "first person, no request: FirstPerson")
    aim(C)
    M.frame(DT)
    check(G.mix > 0 and GSA1.FirstPerson() == false, "gsa1_cam_fish_first 1: from the first frame of the blend Big is drawn (FirstPerson false)")
    frames(8, DT)
    check(GSA1.FirstPerson() == false and vnear(GSA1.view.origin, Vector(cam.px, cam.py, cam.pz)), "... and the view is the game's")
    no_request()
    M.frame(DT)
    check(G.mix > 0 and GSA1.FirstPerson() == false, "the way back: still from outside")
    frames(8, DT)
    check(G.mix == 0 and GSA1.FirstPerson() == true, "back in the eyes")
    M.convars.gsa1_cam_fish_first:SetString("0")
    aim(C)
    frames(3, DT)
    check(GSA1.FirstPerson() == true and band(hflags(), 8) == 0 and G.mix == 0, "gsa1_cam_fish_first 0: first person stays first person, no bit")
    M.convars.gsa1_cam_distance:SetString("150")
    frames(2, DT)
    check(band(hflags(), 8) == 8, "... in third person the bit goes as ever")
    no_request()
    frames(8, DT)
    M.convars.gsa1_cam_fish_first:SetString("1")
end

-- 8. G8: the R key; the file order (2.4 C4) ---------------------------------------------------------------------------------------------
do
    local names = table.concat(GSA1.FeatureFiles, " ")
    local gi, ii, wi = string.find(names, "cl_gamecam", 1, true), string.find(names, "cl_interact", 1, true), string.find(names, "cl_wheel.lua", 1, true)
    check(gi and ii and wi and gi < ii and ii < wi, "cl_gamecam loads before cl_interact's plain GSA1.ExtraButtons and cl_wheel's wrap")
    M.keys = IN_RELOAD
    lure(C)
    frames(3, DT)
    check(GSA1.ExtraButtons(C) == 24, "all feature files loaded, the lure in the water, R down: L + R (%s)", tostring(GSA1.ExtraButtons(C)))
    frames(1, DT)
    check(band(M.ticks.last.buttons, 24) == 24, "the tick gets L + R (buttons %d)", M.ticks.last.buttons)
    aim(C)
    frames(2, DT)
    check(GSA1.ExtraButtons(C) == 0 and band(M.ticks.last.buttons, 24) == 0, "kind AIM: R does nothing (buttons %d)", M.ticks.last.buttons)
    M.keys = 0
    lure(C)
    frames(2, DT)
    check(GSA1.ExtraButtons(C) == 0, "R up: nothing")
    M.keys = IN_RELOAD
    M.convars.gsa1_cam_fish_rkey:SetString("0")
    frames(2, DT)
    check(GSA1.ExtraButtons(C) == 0, "the option off: nothing")
    M.convars.gsa1_cam_fish_rkey:SetString("1")
    frames(2, DT)
    GSA1.Interact.PressAction()
    check(GSA1.ExtraButtons(C) == 26, "chained: the interact key's action press and L + R (%s)", tostring(GSA1.ExtraButtons(C)))
    GSA1.Interact.actionUntil = nil
    check(GSA1.ExtraButtons(C) == 24, "... and L + R alone again")
    GSA1.Wheel.open = true
    local w = GSA1.ExtraButtons(C)
    local rcmd = { KeyDown = function() return true end, GetViewAngles = function() return Angle() end, SetViewAngles = function() end,
                   GetMouseX = function() return 0 end, GetMouseY = function() return 0 end }
    GSA1.PadView(rcmd)
    local w2 = G.rDown
    GSA1.Wheel.open = false
    check(w == 0 and w2 == false, "the open wheel: nothing, R does not even reach this file (%s, %s)", tostring(w), tostring(w2))
    frames(1, DT)
    local ib = GSA1.InputBlocked
    GSA1.InputBlocked = function() return true end
    check(G.RKey(C) == 0, "GSA1.InputBlocked: nothing")
    GSA1.InputBlocked = ib
    M.convars.gsa1_cam_fish:SetString("0")
    frames(1, DT)
    frames(1, DT)
    check(GSA1.ExtraButtons(C) == 0, "Off: R is 0.9.5's Y only")
    M.convars.gsa1_cam_fish:SetString("2")
    M.keys = 0
    no_request()
    frames(8, DT)
    local x0 = GSA1.ExtraButtons
    GSA1.Spawn("sonic")
    check(GSA1.ExtraButtons == x0, "wrapped once: a second character wraps nothing")
    GSA1.Spawn("big")
    C = GSA1.Char
    frames(2, DT)
end

-- 9. the toggle (2.4 C7) ---------------------------------------------------------------------------------------------------------------
do
    check(type(M.cmds.gsa1_cam_fish_toggle) == "function", "the command gsa1_cam_fish_toggle exists")
    M.cmds.gsa1_cam_fish_toggle()
    check(G.toggleOff == false, "no request: the toggle does nothing")
    lure(C)
    frames(8, DT)
    check(G.mix == 1, "the lure camera shows")
    M.cmds.gsa1_cam_fish_toggle()
    frames(1, DT)
    frames(1, DT)
    check(G.toggleOff and band(hflags(), 8) == 0 and G.mix < 1, "the toggle: no bit, back to your camera (mix %.3f)", G.mix)
    frames(8, DT)
    M.cmds.gsa1_cam_fish_toggle()
    frames(2, DT)
    check(not G.toggleOff and band(hflags(), 8) == 8 and G.mix > 0, "pressed again: the same request again")
    M.cmds.gsa1_cam_fish_toggle()
    frames(2, DT)
    check(G.toggleOff == true, "off once more")
    no_request()
    frames(2, DT)
    check(G.toggleOff == false and band(hflags(), 8) == 8, "the cast ended: the toggle is over")
    -- the key: a ConVar polled before each tick, on its edge, not while typing
    local down = {}
    input = input or {}
    input.IsButtonDown = function(code) return down[code] == true end
    M.convars.gsa1_cam_fish_toggle_key:SetString("37")
    lure(C)
    frames(2, DT)
    down[37] = true
    frames(1, DT)
    local t1 = G.toggleOff
    frames(3, DT)
    down[37] = false
    frames(1, DT)
    check(t1 == true and G.toggleOff == true, "the key toggles on its edge, once")
    down[37] = true
    frames(1, DT)
    check(G.toggleOff == false, "pressed again: back")
    down[37] = false
    frames(1, DT)
    M.convars.gsa1_cam_fish_toggle_key:SetString("0")
    no_request()
    frames(8, DT)
end

-- 10. G9: followers keep the chase eye (decision A9) ----------------------------------------------------------------------------------
do
    check(type(GSA1.FollowerTickCamera) == "function", "GSA1.FollowerTickCamera exists")
    frames(2, DT)
    local o0, t0 = GSA1.FollowerTickCamera(C)
    local v = GSA1.view
    check(G.mix == 0 and o0 and t0 and vnear(o0, v.origin), "no fishing: the view of GSA1.TickCamera (%s)", fv(o0))
    lure(C)
    frames(8, DT)
    local o1, t1 = GSA1.FollowerTickCamera(C)
    local ch1 = G.chase
    local f = ch1.angles:Forward()
    check(G.mix == 1 and o1 and vnear(o1, ch1.origin) and vnear(t1, Vector(ch1.origin.x + f.x * 100, ch1.origin.y + f.y * 100, ch1.origin.z + f.z * 100), 1e-2)
        and not vnear(o1, GSA1.view.origin), "the lure camera shows: followers get the chase eye (%s), not the view (%s)", fv(o1), fv(GSA1.view.origin))
    GSA1.cv.cam_real:SetString("0")
    check(GSA1.FollowerTickCamera(C) == nil, "\"The game uses this camera\" off: nothing, as always")
    GSA1.cv.cam_real:SetString("1")
    no_request()
    frames(8, DT)
end

-- 11. the log: one line per request change, by comparing G.st (review R98.12) ------------------------------------------------------------
do
    local n0 = logs("gamecam")
    aim(C, 3)
    frames(3, DT)
    check(logs("gamecam") == n0 + 1, "a request: one line (%d)", logs("gamecam") - n0)
    aim(C, 0)
    frames(3, DT)
    check(logs("gamecam") == n0 + 2, "the adjust changed: one more line")
    lure(C)
    frames(3, DT)
    check(logs("gamecam") == n0 + 3, "the lure: one more line")
    local line
    for _, l in ipairs(logged) do if l.kind == "gamecam" then line = l.text end end
    check(string.find(line, "lure", 1, true) and string.find(line, "8C0EAF28", 1, true) and string.find(line, "level 4", 1, true), "it says which: %s", line)
    no_request()
    frames(8, DT)
    check(logs("gamecam") == n0 + 4, "the end: one more line")
end

-- 12. G10: the Camera page: every row of 5.9 with its default; a board running: nothing of this acts ----------------------------------------
do
    local p = camera_page()
    check(#p.combos == 1 and p.combos[1] == "Big's fishing camera", "the combo \"Big's fishing camera\"")
    local combo
    for _, P in ipairs(p.all) do
        if P.kind == "ComboBox" then combo = P end
    end
    local choices = {}
    for _, c in ipairs(combo and combo.calls or {}) do if c[1] == "AddChoice" then choices[#choices + 1] = c[2] .. "=" .. c[3] end end
    check(table.concat(choices, ",") == "Off=0,Lure only=1,As the game=2", "its choices: %s", table.concat(choices, ","))
    if combo and combo.OnSelect then combo:OnSelect(1, "Off", "0") end
    check(M.convars.gsa1_cam_fish:GetString() == "0", "picking Off sets gsa1_cam_fish 0")
    M.convars.gsa1_cam_fish:SetString("2")
    combo:Think()
    check(combo.text == "As the game", "it follows the ConVar (%s)", tostring(combo.text))
    local s = p.sliders.gsa1_cam_fish_blend
    check(s and s[1] == "Blend from and to your camera (s)" and s[2] == 0 and s[3] == 1.5, "the slider 0-1.5 s")
    check(p.checks.gsa1_cam_fish_mouse == "The mouse turns around the lure while fishing", "the mouse row")
    check(p.checks.gsa1_cam_fish_fov == "The game's field of view (70) while fishing", "the field of view row")
    check(p.checks.gsa1_cam_fish_first == "Also when you play in first person", "the first person row")
    check(p.checks.gsa1_cam_fish_rkey == "R reels in at once (the game's L + R)", "the R row")
    check(#p.binders == 1 and p.binders[1] == "gsa1_cam_fish_toggle_key" and string.find(p.text, "Look elsewhere for this cast", 1, true), "the binder \"Look elsewhere for this cast\"")
    check(string.find(p.text, "There are no fish in Garry's Mod yet: cast, watch and reel in.", 1, true) ~= nil, "the help line about the fish")
    local defaults = { gsa1_cam_fish = "2", gsa1_cam_fish_blend = "0.3", gsa1_cam_fish_mouse = "0", gsa1_cam_fish_fov = "0",
                       gsa1_cam_fish_first = "1", gsa1_cam_fish_rkey = "1", gsa1_cam_fish_toggle_key = "0" }
    local wrong, n = {}, 0
    for name, want in pairs(defaults) do
        n = n + 1
        local d = GSA1.CONVARS[name]
        if not d or d.default ~= want then wrong[#wrong + 1] = name end
    end
    for name in pairs(GSA1.CONVARS) do
        if string.find(name, "^gsa1_cam_fish") and defaults[name] == nil then wrong[#wrong + 1] = "unknown " .. name end
    end
    check(n == 7 and #wrong == 0, "the seven ConVars with their defaults (%s)", table.concat(wrong, " "))
    -- a panel error stays on the page
    local real = G.Panel
    G.Panel = function() error("boom") end
    local ep = camera_page()
    G.Panel = real
    check(string.find(ep.text, "could not be shown", 1, true) ~= nil, "an error in these rows is shown on the page, the page's own rows stay")
    -- a board running
    GSA1.Spawn("sonic")
    local S = GSA1.Char
    S.board = { on = true }
    aim(S)
    local c0 = camera_calls
    frames(5, DT)
    check(camera_calls == c0 and band(hflags(), 8) == 0 and G.mix == 0 and GSA1.TickYaw(S) == nil, "Sonic on a board: nothing of this acts (the request is OTHER, not asked)")
    no_request()
end

-- 13. A22: 32 B of garbage per frame with no Big, for what this feature adds --------------------------------------------------------------
do
    local S = GSA1.Char
    local CMDT = setmetatable({}, { __index = function() return function() return 0 end end })   -- reading it makes garbage, as frame_test's
    local view = { origin = Vector(1, 2, 3), angles = Angle(1, 2, 0), fov = 90 }
    local create, mouse, pre = M.hooks.CreateMove.gsa1_gamecam, M.hooks.InputMouseApply.gsa1_gamecam, M.hooks.GSA1PreTick.gsa1_gamecam
    local cg = collectgarbage
    local function frame_calls()
        GSA1.TickYaw(S)
        GSA1.HostWaterFlags(S)
        GSA1.FollowerTickCamera(S)
        GSA1.ViewOverride(view, S, M.player)
        GSA1.FirstPerson()
        GSA1.PadView(CMDT)
        create(CMDT)
        mouse(CMDT, 0, 0, view.angles)
        pre(S)
        GSA1.ExtraButtons(S)
    end
    local function prev_calls()
        if G.prevTickYaw then G.prevTickYaw(S) end
        G.prevHostWaterFlags(S)
        if G.prevFollowerTickCamera then G.prevFollowerTickCamera(S) elseif GSA1.TickCamera then GSA1.TickCamera(S) end
        if G.prevViewOverride then G.prevViewOverride(view, S, M.player) end
        G.prevFirstPerson()
        G.prevPadView(CMDT)
        if G.prevExtra then G.prevExtra(S) end
    end
    local function measure(fn)
        for _ = 1, 3000 do fn() end
        cg("collect")
        cg("stop")
        local k0 = cg("count")
        for _ = 1, 2000 do fn() end
        local kb = cg("count") - k0
        cg("restart")
        return kb * 1024 / 2000
    end
    local a = measure(frame_calls)
    local b = measure(prev_calls)
    check(a - b < 32, "with no Big this feature adds %.1f bytes of Lua garbage per frame (budget 32 B; wrapped %.1f, the functions they wrap %.1f)", a - b, a, b)
    info("A22 gamecam: %.1f bytes per frame with no Big", a - b)
end

-- 14. the mock against the module's gamecam_api.txt (5.5, review R98.14): the binding test writes it whenever the snapshot header has
-- SA1_API_CAMERA; then it must exist and match (a missing or stale file is a failure); before that the check is skipped
do
    local groot = string.gsub(tests, "[/" .. string.char(92) .. "]tests$", "")
    local hdr = host_read(groot .. "/build/deps/include/libsa1.h") or ""
    if not string.find(hdr, "#define SA1_API_CAMERA", 1, true) then
        info("gamecam_api.txt: the snapshot's libsa1.h has no SA1_API_CAMERA yet - the check is skipped (5.5's rule)")
    else
        local api = host_read(groot .. "/build/x86_64-windows/gamecam_api.txt")
        local wrong, n = {}, { feature = 0, ["function"] = 0, const = 0, field = 0 }
        if not api then
            wrong[1] = "no build/x86_64-windows/gamecam_api.txt"
        else
            local st = {}
            GSA1.Spawn("big")
            MG.Camera(GSA1.Char.id, -1, st)
            for line in string.gmatch(api, "[^\r\n]+") do
                if string.sub(line, 1, 1) ~= "#" then
                    local f = {}
                    for part in string.gmatch(line .. "\t", "([^\t]*)\t") do f[#f + 1] = part end
                    local kind = f[1]
                    if n[kind] then n[kind] = n[kind] + 1 end
                    if kind == "feature" then
                        if tonumber(MG.FEATURES[f[2]]) ~= tonumber(f[3]) then wrong[#wrong + 1] = "feature " .. tostring(f[2]) end
                    elseif kind == "function" then
                        if type(MG[f[2]]) ~= "function" then wrong[#wrong + 1] = "function " .. tostring(f[2]) end
                    elseif kind == "const" then
                        if tonumber(MG[f[2]]) ~= tonumber(f[3]) then wrong[#wrong + 1] = "const " .. tostring(f[2]) end
                    elseif kind == "field" then
                        if type(st[f[3]]) ~= f[4] then wrong[#wrong + 1] = "field " .. tostring(f[3]) end
                    end
                end
            end
            for name, v in pairs(CAMAPI) do
                if not string.find(api, "const\t" .. name .. "\t" .. tostring(v), 1, true) then wrong[#wrong + 1] = "not in the file: " .. name end
            end
            if n.feature < 1 or n["function"] < 1 or n.const < 10 or n.field < 15 then wrong[#wrong + 1] = "the file has too few records" end
        end
        check(#wrong == 0, "this test's mock module matches build/x86_64-windows/gamecam_api.txt (%d functions, %d constants, %d fields)%s",
            n["function"], n.const, n.field, #wrong > 0 and (": " .. table.concat(wrong, ", ")) or "")
    end
end

check(#M.reported == 0, "no Lua error (%s)", M.reported[1] or "none")
return done()
