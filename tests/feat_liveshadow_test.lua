-- feat_liveshadow_test.lua - the characters' sun shadow (round 0.9.5: sadc docs/research/gsa1_095_plan.md 4.17 and 6.5 task 6
-- with its review R.7; the owner's 14.1ad 5 and "The G-SA1 drawn sun shadow should be toggleable"): feat/sh_liveshadow.lua
-- and feat/cl_liveshadow.lua with cl_render.lua's GSA1.DrawCharacterView, in Garry's Mod's own LuaJIT against
-- tests/lua_mock.lua (its file.Open on an in-memory file, util.TraceLine, cam.Start with ortho).
--   lua_host tests/feat_liveshadow_test.lua <tests dir> <addon/lua dir>
-- Checks (each fails without the feature):
--   1  the light, through the mock's file.Open on synthetic BSP files (a header and an entity lump of the owner's maps'
--      real keyvalues, numbers only: SADC/build/research/board095/review/sunents.txt): gm_construct's shadow_control
--      "90 0 0" -> straight down, colour 187, distance 1000; gm_genesis (only light_environment, pitch -56, yaw 306) ->
--      down and towards yaw 306 (hand-computed: 0.3287, -0.4524, -0.8290); gm_highway14800 (shadow_control "0 0 0" not
--      used, three light_environment pitch -60 yaw 298) -> (0.2347, -0.4415, -0.8660), the count logged; rp_downtown_v4c
--      (two shadow_control): the first "80 30 0"; rp_sister_location_night "75 50" (two numbers: roll 0); keys left out:
--      base.fgd's defaults (128, 75); neither entity -> straight down; an LZMA lump, an oversized lump, a file that is not
--      a map, no file -> straight down with the reason; disableallshadows 1 (awm_bigcity) -> nothing drawn; slices of at
--      most 256 KB per frame; one log line per map.
--   2  the silhouette: one orthographic GSA1.DrawCharacterView per refresh (cam.Start with the ortho box, the flat white
--      material, only the body and board batches of a mock that also has an effect, a game object and a blob shadow),
--      the render target pushed / popped balanced, cleared, blurred once.
--   3  the receivers: 81 traces per refresh while moving (MASK_SOLID, the player filtered), none beyond the light's
--      distance past the feet; the quads drawn after the opaque renderables with ZERO / ONE_MINUS_SRC_COLOR, the
--      tone-mapping scale 1 and restored, the vertex colours (1 - colour / 255) x fade; gsa1_sunshadow_dark instead; the
--      quads stay on the ground between two grids while the picture follows the drawn root every frame (the texture
--      coordinates shift by the root's move / the box); a ledge cell left out.
--   4  skips: nothing with gsa1_sunshadow 0 (no hook at all, no file read), in first person with gsa1_sunshadow_fp 0, with
--      disableallshadows 1, before the main view drew the character; first person with gsa1_sunshadow_fp 1 draws (the body
--      in the silhouette); at most 30 refreshes a second at 144 fps; a standing character traces at most 4 grids a second.
--   5  no Lua garbage of its own per frame; the cost in the mock (info); the Rendering page's rows and defaults; the
--      session log's perf line carries "sun shadow N ms per frame"; no Lua error.
--
-- API NOTES (095-gsa1-render, round 0.9.5; the lane's full notes - its report carries a short form):
--   cl_render.lua
--     * DRAW_BOARD = 0x4000 (SA1_DRAW_BOARD). GSA1.BatchOn(flags, effects, shadows, objects, first_person): a board batch
--       answers first - true, or gsa1_shadow for BOARD | SHADOW - whatever gsa1_effects / gsa1_set_draw say and in first
--       person (review R.10). C.boardBatches counted beside C.objectBatches (ResolveMaterials, and DrawCharacter's own
--       count in first person); first person draws when (objectBatches > 0 and gsa1_set_draw) or boardBatches > 0, the
--       depth views and R1b the same. GSA1.DrawFlagText names 0x4000 "BOARD".
--     * GSA1.DrawCharacterView(C, v) -> true | false, why ("no batches", "not drawn this frame", "no view"): v = { eye,
--       ang, fov | ortho = { left, right, top, bottom }, x, y, w, h, znear, zfar, filter = fn(b) -> bool, material (one
--       IMaterial for every batch: unlit; a static mesh of the pair is drawn again under it, never rebuilt), opaque = true
--       (pass 0 only), kind = "closeup" | "sunshadow" (the views line), hitch = section name ("Closeup" by default; false:
--       the caller times it) }. Both passes of THIS frame's batches through draw_batches (batch_on, C.hidden, no pre-warm,
--       first_person false: the caller decides), camera-relative (v.eye - this frame's C.relOrigin), cam.Start3D(eye, ang,
--       fov, x, y, w, h, znear, zfar) or cam.Start{ type = "3D", origin, angles, x, y, w, h, ortho, znear, zfar }, only when
--       C.viewFrame == FrameNumber(); its time into C.drawMsNext. Errors propagate (callers pcall it).
--     * C.viewWanted = true (set each PreRender by a feature): in first person with nothing of the character drawn,
--       DrawCharacter still prepares the frame (C.relOrigin, PrepareView, C.viewFrame) and draws nothing, so an extra view
--       can draw the frame's batches (the sun shadow with gsa1_sunshadow_fp).
--     * GSA1.ViewsLine(): "..., the Faces page's close-up N" / ", sun shadow N" when N > 0.
--     * ENT:Draw / DrawTranslucent: the garbage meter's slot "Draw / the character" while GSA1.GcMeter.on.
--   cl_gcmeter.lua (new, after cl_hitch.lua in the autorun): see tests/feat_gcmeter_test.lua's API NOTES. gsa1_log_garbage
--     (client, archived, 1): Disc and status > Diagnostics, under "Slow frame threshold for the log (ms)".
--     entities/gsa1_base.lua: its Draw / DrawTranslucent are the slot "Draw / objects" (looked up at the draw).
--   cl_hitch.lua: ORDER += "Closeup", "SunShadow"; GSA1.GcMeter.Frame(now, gc, counted) right after GSA1.LogFrame.
--   cl_log.lua: a header line "settings 0.9.5: the game uses this camera (gsa1_cam_real) ..., sun shadow ..., garbage
--     meter ..., Faces close-up ..."; the perf line gets "; sun shadow N ms per frame" (the "SunShadow" section, when > 0)
--     and the meter's field (GSA1.GcMeter.TakeField); the summary the meter's line; GSA1.LogCamera(passed): one "camera"
--     line per change - "the game's camera: yours (the view G-SA1 shows)" / "...: its own, behind the character (\"The game
--     uses this camera\" is off)" / "...: its own (G-SA1's view not in use: a camera entity or another addon's view)".
--   cl_character.lua: GSA1.DefaultTickCamera returns nil while gsa1_cam_real is 0 (first line); the tick calls
--     GSA1.LogCamera(co ~= nil) while gsa1.TICK_HOST_CAMERA; update_audio with no fresh view reads the player's eyes at
--     most every 0.25 s into a reused Vector / Angle (board095_perf.md G1).
--   sh_config.lua: GSA1.cv.cam_real = gsa1_cam_real (client, archived, 1, 0..1); cl_menu.lua camera_panel: "The game uses
--     this camera" + its help.
--   feat/cl_mouthtest.lua + cl_faces.lua: gsa1_mouth_closeup 0..2 (1 = the character alone, the default; 2 = with the world
--     behind it) as a combo box (role "closeup"), gsa1_mouth_closeup_fps 5..60 (30) as a slider (role "closeupfps");
--     F.closeup = CU { at, paintedAt, hovered, made, ms, rt, mat, cv (the DrawCharacterView table), view (RenderView's) },
--     F.CloseupRefresh(now) -> bool (PostRender hook gsa1_mouthtest_closeup, only within F.CLOSEUP_SEEN 0.25 s of a Paint),
--     F.CLOSEUP_NEAR / FAR / FAR_WORLD = 4 / 400 / 1500, F.CLOSEUP_IDLE_FPS 5, F.CLOSEUP_BG; F.CloseupPaint draws the
--     render target gsa1_closeup_<format> (256 x 192, UnlitGeneric gsa1_closeup_<format>).
--   feat/sh_liveshadow.lua + feat/cl_liveshadow.lua (the feature "liveshadow"): GSA1.SunShadow = S: S.cv.on / fp / dark =
--     gsa1_sunshadow 1, gsa1_sunshadow_fp 0, gsa1_sunshadow_dark 0 (0..100); Rendering page rows "Sun shadow (like Garry's
--     Mod's props on this map)", "Sun shadow in first person too", "Sun shadow darkness (0 = the map's own colour)" and a
--     status line GSA1.SunShadowLine(). S.light = { source = "shadow_control" | "light_environment" | "down", dx, dy, dz
--     (unit, where the light travels), color = { r, g, b }, distance, disabled, text } for S.lightMap; S.ParseHeader(s),
--     S.ParseEntities(text, step), S.LightOf(found, why), S.Forward(p, y), S.KeyValues, S.Numbers, S.LE32 (pure);
--     S.StepLight() (the Think step); S.Apply() (the hooks gsa1_sunshadow on Think / PreRender / PostDrawOpaqueRenderables
--     exist only while gsa1_sunshadow is 1); S.grid { hit, wx, wy, wz, fade, depth, u, v, cells, ncells, box } (the hit
--     points in the world, their texture coordinates of this frame), S.basis { fwd, right, up }, S.stats { refreshes,
--     refreshMs, traces, frames, frameMs }; the render target gsa1_sunshadow_<format>
--     (256 x 256, its own depth), the materials gsa1_sunshadow_white (UnlitGeneric vgui/white, $nocull, $ignorez) and
--     gsa1_sunshadow_<format> (UnlitGeneric of the target: $vertexcolor, $translucent, $nofog, $decal, $nocull); constants
--     S.RT_SIZE 256, S.GRID 9, S.BLUR 2, S.SLICE 256 KB, S.LUMP_MAX 8 MB, S.REFRESH 1/30 s, S.RETRACE_MOVE 0.5 HU,
--     S.RETRACE_EVERY 0.25 s, S.MIN_DOWN sin 10 degrees, S.STEP_DEPTH 24 HU, S.LIFT 0.5 HU, S.BOX_MIN 48 HU, S.DEFAULT
--     (bin/base.fgd's shadow_control: 80 30 0, 128 128 128, 75, 0). UNVERIFIED in game: GMod's ortho convention (top =
--     -box is the picture's top, as top-down minimap addons use it), render.BlurRenderTarget inside the main view, the
--     decal blend on DXVK, the engine's own defaults for keys a map leaves out.
--   tests/lua_mock.lua (only editor this round): cam.Start (M.camStarts when a table), render.BlurRenderTarget,
--     render.OverrideDepthEnable, surface.SetMaterial / DrawTexturedRectUV (counted), util.TraceLine (M.traceLine(t);
--     M.traces), file.Open on M.gamefiles[path] (Read / Seek / Tell / Size / EndOfFile / Close; M.fileReads).
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_liveshadow_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- the character's batches: { archive, tex, flags, src, dst, wrap, pass, tris, prims }
local LIST = {
    { 0, 0, 0x20, 1, 0, 3, 0, 100, 1 },         -- 1 the body
    { -1, -1, 0x40C0, 1, 0, 0, 0, 44, 1 },      -- 2 the board (BOARD | EFFECT | NO_TEXTURE)
    { 0, 3, 0x40, 1, 0, 3, 0, 20, 1 },          -- 3 an opaque effect
    { 0, 1, 0x1040, 1, 0, 3, 0, 10, 1 },        -- 4 a game object
    { 2, 58, 0x841, 4, 5, 11, 1, 2, 1 },        -- 5 the blob shadow (mask)
    { 1, 2, 0x255, 4, 1, 3, 1, 2, 2 },          -- 6 an additive sprite
}
local G = M.module({ archives = { [0] = { 28, 29, 96, 138 } }, batches = function() return LIST end, speed = 0 })
function G.TextureArchives()
    return { { name = "SONIC", count = 28 }, { name = "SON_EFF", count = 29 }, { name = "OBJ_REGULAR", count = 96 },
             { name = "EFF_REGULAR", count = 138 } }
end
local emitted, inView = {}, false
local emit0 = G.EmitBatch
function G.EmitBatch(id, i)
    if inView then emitted[#emitted + 1] = i end
    return emit0(id, i)
end
-- the render state the receivers touch
local events = {}
local recording = false
-- (the engine's own objects are its own: these stand-ins make none, so the addon's garbage can be measured)
local tone, toneOut = Vector(2, 2, 2), Vector()
render.GetToneMappingScaleLinear = function()
    toneOut:Set(tone)
    return toneOut
end
render.SetToneMappingScaleLinear = function(v)
    tone:Set(v)
    if recording then events[#events + 1] = string.format("tone %g", v.x) end
end
local ob = render.OverrideBlend
render.OverrideBlend = function(on, s, d, f)
    if recording then events[#events + 1] = on and string.format("blend %d %d %d", s, d, f or -1) or "blend off" end
    return ob(on, s, d, f)
end
local colors = {}
mesh.Color = function(r, g, b, a) if recording then colors[#colors + 1] = r end end
local positions = {}
mesh.Position = function(v) if recording then positions[#positions + 1] = v.z end end
local blurs = 0
render.BlurRenderTarget = function() blurs = blurs + 1 end

-- the ground: z = GROUND_Z; a crate top at CRATE (x range) if set
local GROUND_Z = -143
local CRATE = nil
local function plane(s, e, z)
    if s.z >= z and e.z <= z and s.z ~= e.z then
        local f = (s.z - z) / (s.z - e.z)
        return f, s.x + (e.x - s.x) * f, s.y + (e.y - s.y) * f
    end
end
local function trace_line(t)
    local out = t.output or {}
    local s, e = t.start, t.endpos
    out.Hit, out.StartSolid, out.Fraction = false, false, 1
    out.HitPos = out.HitPos or Vector()
    local f, x, y = plane(s, e, GROUND_Z)
    if CRATE then
        local f2, x2, y2 = plane(s, e, CRATE.z)
        if f2 and x2 >= CRATE.x0 and x2 <= CRATE.x1 and (not f or f2 < f) then f, x, y = f2, x2, y2 end
    end
    if f then
        out.Hit, out.Fraction = true, f
        out.HitPos:SetUnpacked(x, y, s.z + (e.z - s.z) * f)
    end
    return out
end
M.traceLine = trace_line

-- the BSP files (little-endian int32; the header, then lump 0 at 1036)
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
local MAPS = {
    gm_construct = WORLD .. ent({ { "classname", "shadow_control" }, { "angles", "90 0 0" }, { "color", "187 187 187" },
        { "distance", "1000" }, { "disableallshadows", "0" } }) .. ent({ { "classname", "light_environment" },
        { "angles", "0 306 0" }, { "pitch", "-56" } }),
    gm_genesis = WORLD .. ent({ { "classname", "light_environment" }, { "angles", "0 306 0" }, { "pitch", "-56" } }),
    gm_highway14800 = WORLD .. ent({ { "classname", "shadow_control" }, { "angles", "0 0 0" }, { "color", "128 128 128" },
        { "distance", "1000" }, { "disableallshadows", "0" } }) .. string.rep(ent({ { "classname", "light_environment" },
        { "angles", "0 298 0" }, { "pitch", "-60" } }), 3),
    rp_downtown_v4c = WORLD .. ent({ { "classname", "shadow_control" }, { "angles", "80 30 0" }, { "color", "128 128 128" },
        { "distance", "75" } }) .. ent({ { "classname", "light_environment" }, { "angles", "0 135 0" }, { "pitch", "-120" } })
        .. ent({ { "classname", "shadow_control" }, { "angles", "0 135 0" }, { "color", "128 128 128" }, { "distance", "75" } }),
    rp_sister_location_night = WORLD .. ent({ { "classname", "shadow_control" }, { "angles", "75 50" },
        { "color", "81 80 87" }, { "distance", "75" }, { "disableallshadows", "0" } }),
    keys_left_out = WORLD .. ent({ { "classname", "shadow_control" } }),
    awm_bigcity = WORLD .. ent({ { "classname", "shadow_control" }, { "angles", "80 30 0" }, { "color", "0 0 0" },
        { "distance", "75" }, { "disableallshadows", "1" } }) .. ent({ { "classname", "light_environment" },
        { "angles", "0 247 0" }, { "pitch", "-60" } }),
    gm_goldencity_v2 = WORLD .. ent({ { "classname", "light_environment" }, { "angles", "0 0 0" }, { "pitch", "0" } }),
    neither = WORLD .. ent({ { "classname", "info_player_start" }, { "origin", "0 0 0" } }),
}
local MAPFILE = "maps/" .. game.GetMap() .. ".bsp"

-- the addon through its autorun ------------------------------------------------------------------------------------------
GSA1 = nil
M.included = {}
M.gamefiles = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local S = GSA1 and GSA1.SunShadow
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
check(ok_load and #ferr == 0 and S ~= nil and S.StepLight ~= nil and GSA1.DrawCharacterView ~= nil, "the autorun loads "
    .. "sh_liveshadow.lua and cl_liveshadow.lua (%s)", ok_load and table.concat(GSA1.FeatureFiles or {}, " ") or
    tostring(err_load or ferr[1]))
if not (ok_load and S and S.StepLight) then return done() end
local logs = {}
local realLog = GSA1.Log
GSA1.Log = function(kind, fmt, ...)
    local okf, text = pcall(string.format, fmt, ...)
    logs[#logs + 1] = { kind = kind, text = okf and text or tostring(fmt) }
    return realLog(kind, fmt, ...)
end
local function logs_with(plain)
    local out = {}
    for _, l in ipairs(logs) do if string.find(l.text, plain, 1, true) then out[#out + 1] = l.text end end
    return out
end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
GSA1.cv.prewarm:SetString("0")

-- a frame as Garry's Mod runs it, with the views' hooks
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
    M.run_hook("PostDrawOpaqueRenderables", false, false, false)
    M.run_hook("PreDrawTranslucentRenderables", false, false)
    for _, e in ipairs(M.entities) do if not e.removed and e.DrawTranslucent then e:DrawTranslucent(1) end end
    M.run_hook("PostDrawTranslucentRenderables", false, false)
    M.run_hook("PostRender")
end
local function frames(n, dt) for _ = 1, n do frame(dt) end end

-- 1. the light -------------------------------------------------------------------------------------------------------------
-- reads a map file through the feature's own job; returns the light and the frames it took
local function read_map(bytes)
    M.gamefiles[MAPFILE] = bytes
    S.light, S.lightMap, S.job = nil, nil, nil
    M.fileReads = {}
    local n = 0
    while not S.lightMap and n < 400 do
        frame()
        n = n + 1
    end
    return S.light, n
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end
local function dir_ok(L, x, y, z) return L and near(L.dx, x) and near(L.dy, y) and near(L.dz, z) end
do
    local L = read_map(bsp(MAPS.gm_construct))
    check(L and L.source == "shadow_control" and dir_ok(L, 0, 0, -1) and L.color[1] == 187 and L.distance == 1000 and
        not L.disabled, "gm_construct: shadow_control \"90 0 0\" -> straight down, colour 187, distance 1000 (%s)",
        L and L.text or "no light")
    check(#logs_with("sun shadow: shadow_control angles (90, 0, 0), colour (187, 187, 187), distance 1000") == 1,
        "one log line for the map's sun")
    L = read_map(bsp(MAPS.gm_genesis))
    check(L and L.source == "light_environment" and dir_ok(L, 0.3287, -0.4524, -0.8290) and L.color[1] == 128 and
        L.distance == 75, "gm_genesis: only light_environment, pitch -56 (negative = down), yaw 306 -> down and towards "
        .. "yaw 306 (%.4f, %.4f, %.4f; review R.7: read as a Source pitch it would point up)", L and L.dx or 0,
        L and L.dy or 0, L and L.dz or 0)
    L = read_map(bsp(MAPS.gm_highway14800))
    check(L and L.source == "light_environment" and dir_ok(L, 0.2347, -0.4415, -0.8660) and L.distance == 1000 and
        string.find(L.text, "shadow_control angles (0, 0, 0) point within 10 degrees", 1, true) and
        string.find(L.text, "the first of 3 light_environment", 1, true), "gm_highway14800: shadow_control \"0 0 0\" not "
        .. "used, the first of three light_environment (%s)", L and L.text or "-")
    L = read_map(bsp(MAPS.rp_downtown_v4c))
    local fx, fy, fz = S.Forward(80, 30)
    check(L and L.source == "shadow_control" and dir_ok(L, fx, fy, fz) and string.find(L.text, "the first of 2 "
        .. "shadow_control", 1, true), "rp_downtown_v4c: the first of two shadow_control, \"80 30 0\" (%s)",
        L and L.text or "-")
    L = read_map(bsp(MAPS.rp_sister_location_night))
    fx, fy, fz = S.Forward(75, 50)
    check(L and dir_ok(L, fx, fy, fz) and L.color[3] == 87, "rp_sister_location_night: angles \"75 50\" (roll 0)")
    L = read_map(bsp(MAPS.keys_left_out))
    fx, fy, fz = S.Forward(80, 30)
    check(L and L.source == "shadow_control" and dir_ok(L, fx, fy, fz) and L.color[1] == 128 and L.distance == 75 and
        not L.disabled, "keys left out: base.fgd's defaults (angles 80 30 0, colour 128, distance 75, shadows on)")
    L = read_map(bsp(MAPS.gm_goldencity_v2))
    check(L and L.source == "down" and dir_ok(L, 0, 0, -1) and string.find(L.text, "pitch 0 points within 10 degrees", 1,
        true), "gm_goldencity_v2: light_environment pitch 0 is horizontal -> straight down (%s)", L and L.text or "-")
    L = read_map(bsp(MAPS.neither))
    check(L and L.source == "down" and string.find(L.text, "neither", 1, true), "neither entity: straight down (%s)",
        L and L.text or "-")
    L = read_map(bsp(MAPS.gm_construct, { fourcc = 4096 }))
    local lzma = L and L.source == "down" and string.find(L.text, "LZMA", 1, true)
    L = read_map(bsp("", { data = "LZMA" .. string.rep("x", 60) }))
    check(lzma and L and L.source == "down" and string.find(L.text, "LZMA", 1, true), "an LZMA-compressed lump (fourCC, "
        .. "or the LZMA magic) is refused: straight down (%s)", L and L.text or "-")
    local reads0 = 0
    L = read_map(bsp("", { len = 9 * 1048576 }))
    for _, r in ipairs(M.fileReads) do reads0 = math.max(reads0, r) end
    check(L and L.source == "down" and string.find(L.text, "more than 8 MB", 1, true) and reads0 <= S.HEADER_BYTES,
        "an oversized lump (9 MB) is refused before it is read (%s; largest read %d bytes)", L and L.text or "-", reads0)
    L = read_map("PK\3\4" .. string.rep("x", 100))
    local notmap = L and L.source == "down" and string.find(L.text, "VBSP", 1, true)
    M.gamefiles[MAPFILE] = nil
    S.light, S.lightMap, S.job = nil, nil, nil
    frame()
    L = S.light
    check(notmap and L and L.source == "down" and string.find(L.text, "could not be read", 1, true), "not a map / no "
        .. "file: straight down with the reason (%s)", L and L.text or "-")
    -- slices: a 700 KB lump with the sun at its end
    local filler = string.rep(ent({ { "classname", "prop_static" }, { "origin", "1 2 3" }, { "model", "models/x.mdl" } }),
        11000)
    local n
    L, n = read_map(bsp(filler .. ent({ { "classname", "shadow_control" }, { "angles", "90 0 0" }, { "color", "100 100 100" },
        { "distance", "500" } })))
    local maxRead, big = 0, 0
    for _, r in ipairs(M.fileReads) do
        if r > maxRead then maxRead = r end
        if r > 1036 then big = big + 1 end
    end
    check(L and L.color[1] == 100 and maxRead <= 256 * 1024 and big >= 3 and n >= big, "a %d KB lump: read in %d slices "
        .. "of at most 256 KB (largest %d bytes), one per frame (%d frames, the parse included)", math.floor(#filler / 1024),
        big, maxRead, n)
end

-- 2-3. the silhouette and the receivers --------------------------------------------------------------------------------
read_map(bsp(MAPS.gm_construct))           -- straight down, colour 187, distance 1000
GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil, "Sonic spawned")
if not C then return done() end
local realDV = GSA1.DrawCharacterView
local dvCalls, dvKinds = 0, {}
GSA1.DrawCharacterView = function(c, v)
    dvCalls = dvCalls + 1
    dvKinds[#dvKinds + 1] = v
    inView = true
    local a, b = realDV(c, v)
    inView = false
    return a, b
end
frames(10)
-- (a moving character: the mock moves it 10 units a game pair)
local speed0 = 0
local function set_speed(v)
    speed0 = v
    for _, c in pairs(M.mchars) do c.pos.x = c.pos.x end
end
set_speed(0)
do
    -- moving: the mock module's speed
    local mc = M.mchars[C.id]
    local moveTick = G.Tick
    function G.Tick(id, ...)
        local r, e, c2 = moveTick(id, ...)
        if mc and r then mc.pos.x = mc.pos.x + 10 * r end
        return r, e, c2
    end
    emitted, dvCalls, dvKinds = {}, 0, {}
    local push0, pop0, clear0, starts0 = M.calls.PushRenderTarget or 0, M.calls.PopRenderTarget or 0,
        M.calls.Clear or 0, #M.camStarts
    local blur0 = blurs
    local refr0, tr0 = S.stats.refreshes, M.calls.TraceLine or 0
    M.traces = {}
    frames(60)
    local refreshes = S.stats.refreshes - refr0
    local traces = (M.calls.TraceLine or 0) - tr0
    local sorted, seen = {}, {}
    for _, i in ipairs(emitted) do if not seen[i] then seen[i] = true; sorted[#sorted + 1] = i end end
    table.sort(sorted)
    local v = dvKinds[1] or {}
    local cs = M.camStarts[#M.camStarts]
    check(refreshes >= 28 and refreshes <= 31 and dvCalls == refreshes and v.kind == "sunshadow" and v.ortho ~= nil and
        v.opaque == true and v.material ~= nil and v.material.shader == "UnlitGeneric" and cs and cs.ortho ~= nil and
        cs.type == "3D", "one orthographic DrawCharacterView per refresh: %d refreshes in 1 s at 60 fps, %d views "
        .. "(kind %s, the ortho box, opaque only, the flat white UnlitGeneric)", refreshes, dvCalls, tostring(v.kind))
    check(table.concat(sorted, " ") == "1 2", "the silhouette draws only the body and the board (batches \"%s\"; the mock "
        .. "also has an effect, a game object, the blob and a sprite)", table.concat(sorted, " "))
    local pushes, pops = (M.calls.PushRenderTarget or 0) - push0, (M.calls.PopRenderTarget or 0) - pop0
    check(pushes == refreshes and pops == pushes and (M.calls.Clear or 0) - clear0 >= refreshes and blurs - blur0 ==
        refreshes, "the render target: %d pushes, %d pops, cleared, blurred once per refresh (%d)", pushes, pops,
        blurs - blur0)
    check(traces == 81 * refreshes, "81 traces per refresh while moving (%d traces for %d refreshes)", traces, refreshes)
    local beyond, masks, filt = 0, true, true
    local root = C.drawPos
    for _, t in ipairs(M.traces) do
        -- the light points straight down: the depth past the feet is the root's height minus the end's
        if t.endpos.z < root.z - 1000 - 10 - 1e-6 then beyond = beyond + 1 end
        if t.mask ~= (MASK_SOLID or 33570827) then masks = false end
    end
    check(#M.traces > 0 and beyond == 0 and masks, "no trace beyond the light's distance past the feet (%d of %d), "
        .. "MASK_SOLID", beyond, #M.traces)
    M.traces = nil
    -- the receivers: recorded inside the hook
    local hk = M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow
    events, colors, positions = {}, {}, {}
    M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow = function(...)
        recording = true
        local r = hk(...)
        recording = false
        return r
    end
    frame()
    local seq = table.concat(events, ", ")
    check(seq == "tone 1, blend 0 10 0, blend off, tone 2", "the receivers: the tone-mapping scale 1, ZERO / "
        .. "ONE_MINUS_SRC_COLOR, then restored (\"%s\")", seq)
    local cmax = 0
    for _, c in ipairs(colors) do if c > cmax then cmax = c end end
    -- colour 187: 255 - 187 = 68 at the feet, less further down (the ground is 0 units below the feet: fade 1)
    check(#colors == 6 * 64 and math.abs(cmax - 68) < 0.5, "64 cells, 384 vertices, the vertex colour (1 - 187 / 255) x "
        .. "fade = %.1f (68 at the feet)", cmax)
    local zmin, zmax = math.huge, -math.huge
    for _, z in ipairs(positions) do zmin, zmax = math.min(zmin, z), math.max(zmax, z) end
    check(near(zmin, GROUND_Z + 0.5, 1e-3) and near(zmax, GROUND_Z + 0.5, 1e-3), "the quads lie on the ground, lifted %.1f "
        .. "towards the light", zmin - GROUND_Z)
    local c187 = colors[1] or -1
    RunConsoleCommand("gsa1_sunshadow_dark", "50")
    colors = {}
    frame()
    local c50 = colors[1] or -1
    RunConsoleCommand("gsa1_sunshadow_dark", "0")
    check(near(c50 / c187, 127.5 / 68, 1e-3), "gsa1_sunshadow_dark 50: the darkness instead of the map's colour (%.1f "
        .. "against %.1f: 127.5 / 68 at the same fade)", c50, c187)
    -- the quads follow the drawn root every frame, between refreshes too (the drawn root moves every frame here, as an
    -- interpolated one does)
    local render0 = G.Render
    function G.Render(id, alpha)
        local a, b, x, y, z, e, f, g, h, i = render0(id, alpha)
        return a, b, x and x + 3 * M.frameNo, y, z, e, f, g, h, i
    end
    local xs, vs = {}, {}
    local mpos, mtex = mesh.Position, mesh.TexCoord
    mesh.Position = function(p) if recording then xs[#xs + 1] = p.x end end
    mesh.TexCoord = function(_, u, v) if recording then vs[#vs + 1] = v end end
    local followed, tried, info1 = false, 0, "-"
    while not followed and tried < 8 do
        tried = tried + 1
        xs, vs = {}, {}
        frame()
        local x1, v1, r1 = xs[1], vs[1], C.drawPos.x
        local g1 = S.grid.at
        xs, vs = {}, {}
        frame()
        local x2, v2, r2 = xs[1], vs[1], C.drawPos.x
        -- (no new grid in the second frame: the same ground points, the picture moved with the root; the light straight
        -- down: the view's up is +x, so v grows by the root's x move / (2 x the box))
        if S.grid.at == g1 and x1 and x2 and math.abs(r2 - r1) > 1 then
            local up = S.basis.up
            local want = (r2 - r1) * up.x / (2 * S.grid.box)
            followed = near(x2, x1, 1e-9) and near(v2 - v1, want, 1e-9)
            info1 = string.format("a vertex at x %.2f -> %.2f, v %.4f -> %.4f (want %+.4f) for a root move of %.2f", x1, x2,
                v1, v2, want, r2 - r1)
        end
    end
    mesh.Position, mesh.TexCoord = mpos, mtex
    G.Render = render0
    frames(2)
    check(followed, "between two grids the quads stay on the ground and the picture follows the drawn root every frame "
        .. "(%s)", info1)
    -- a ledge: a crate top 40 units up under part of the grid: the cells across its edge are left out
    CRATE = { z = GROUND_Z + 40, x0 = C.drawPos.x - 1000, x1 = C.drawPos.x }
    S.refreshAt = nil
    colors = {}
    frames(3)
    local cells = S.grid.ncells
    CRATE = nil
    S.refreshAt = nil
    frames(3)
    check(cells < 64 and cells >= 40, "a ledge under the shadow: the cells across it are left out (%d of 64)", cells)
    M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow = hk
    G.Tick = moveTick
    frames(2)
end

-- 4. skips ------------------------------------------------------------------------------------------------------------------
do
    -- a standing character: the grid at most 4 times a second, the silhouette at the pair rate
    local tr0, rf0 = M.calls.TraceLine or 0, S.stats.refreshes
    frames(60)
    local grids = ((M.calls.TraceLine or 0) - tr0) / 81
    check(grids <= 5 and S.stats.refreshes - rf0 >= 28, "standing: %d grids of traces in 1 s (at most every 0.25 s), %d "
        .. "silhouettes", grids, S.stats.refreshes - rf0)
    -- 144 fps: at most 30 refreshes a second
    rf0 = S.stats.refreshes
    frames(144, 1 / 144)
    local r144 = S.stats.refreshes - rf0
    check(r144 <= 30 and r144 >= 24, "at most 30 refreshes a second at 144 fps (%d)", r144)
    -- first person without gsa1_sunshadow_fp: nothing; with it: the silhouette, with the body
    local dist = GSA1.cv.cam_dist:GetString()
    GSA1.cv.cam_dist:SetString("0")
    rf0, dvCalls = S.stats.refreshes, 0
    local tr1 = M.calls.TraceLine or 0
    frames(30)
    local fpNone = S.stats.refreshes - rf0 == 0 and (M.calls.TraceLine or 0) == tr1
    RunConsoleCommand("gsa1_sunshadow_fp", "1")
    emitted, rf0 = {}, S.stats.refreshes
    frames(30)
    local fpOn = S.stats.refreshes - rf0
    local body = false
    for _, i in ipairs(emitted) do if i == 1 then body = true end end
    RunConsoleCommand("gsa1_sunshadow_fp", "0")
    GSA1.cv.cam_dist:SetString(dist)
    frames(5)
    check(fpNone and fpOn >= 14 and body, "first person: nothing with gsa1_sunshadow_fp 0; with 1 %d silhouettes in 0.5 s, "
        .. "the body in them (the frame's batches prepared, not drawn)", fpOn)
    -- the main view has not drawn the character: no silhouette, no receivers
    rf0 = S.stats.refreshes
    local n0 = S.stats.frames
    M.frameNo = M.frameNo + 1
    M.run_hook("PostDrawOpaqueRenderables", false, false, false)
    check(S.stats.refreshes == rf0 and S.stats.frames == n0, "before the main view drew the character this frame: nothing")
    -- depth and skybox views, other render targets: nothing
    M.run_hook("PostDrawOpaqueRenderables", true, false, false)
    M.run_hook("PostDrawOpaqueRenderables", false, true, false)
    M.render_target = { GetName = function() return "_rt_WaterReflection" end }
    M.run_hook("PostDrawOpaqueRenderables", false, false, false)
    M.render_target = nil
    check(S.stats.frames == n0, "depth, skybox and water views: nothing")
    -- disableallshadows 1
    read_map(bsp(MAPS.awm_bigcity))
    rf0 = S.stats.refreshes
    local tr2 = M.calls.TraceLine or 0
    frames(30)
    check(S.light.disabled and S.stats.refreshes == rf0 and (M.calls.TraceLine or 0) == tr2,
        "disableallshadows 1 (awm_bigcity): nothing drawn (%s)", S.light.text)
    read_map(bsp(MAPS.gm_construct))
    -- off: no hook at all, nothing read, drawn or computed
    RunConsoleCommand("gsa1_sunshadow", "0")
    local hooked = M.hooks.Think.gsa1_sunshadow ~= nil or M.hooks.PreRender.gsa1_sunshadow ~= nil or
        M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow ~= nil
    S.light, S.lightMap, S.job = nil, nil, nil
    M.fileReads = {}
    rf0 = S.stats.refreshes
    local push0, tr3 = M.calls.PushRenderTarget or 0, M.calls.TraceLine or 0
    frames(60)
    check(not hooked and #M.fileReads == 0 and S.stats.refreshes == rf0 and (M.calls.PushRenderTarget or 0) == push0 and
        (M.calls.TraceLine or 0) == tr3 and not C.viewWanted, "gsa1_sunshadow 0: no hook, no file read, no render target, "
        .. "no trace")
    check(string.find(GSA1.SunShadowLine(), "off", 1, true) ~= nil, "the page's line: \"%s\"", GSA1.SunShadowLine())
    RunConsoleCommand("gsa1_sunshadow", "1")
    frames(10)
    check(S.light ~= nil and M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow ~= nil and S.stats.refreshes > rf0,
        "on again: the hooks, the light read again, drawn (%s)", GSA1.SunShadowLine())
end

-- 5. garbage, cost, the page, the log ----------------------------------------------------------------------------------
do
    GSA1.DrawCharacterView = realDV
    local hk = { M.hooks.Think.gsa1_sunshadow, M.hooks.PreRender.gsa1_sunshadow,
                 M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow }
    local mockkb = 0
    local wrapped = {}
    for nm, fn in pairs(gsa1) do
        if type(fn) == "function" then
            wrapped[nm] = fn
            gsa1[nm] = function(...)
                local q0 = collectgarbage("count")
                local a, b, c, d, e, f, g, h = fn(...)
                mockkb = mockkb + collectgarbage("count") - q0
                return a, b, c, d, e, f, g, h
            end
        end
    end
    local kb, n = 0, 0
    local mc = M.mchars[C.id]
    for _ = 1, 60 do frame() end
    if jit and jit.off then jit.off() jit.flush() end
    local camStarts = M.camStarts
    M.camStarts = nil              -- (the mock's own record of the views, not the addon's garbage)
    collectgarbage("collect")
    collectgarbage("stop")
    for _ = 1, 300 do
        M.T = M.T + 1 / 60
        M.frameNo = M.frameNo + 1
        if mc then mc.pos.x = mc.pos.x + 5 end
        M.run_hook("Think")
        for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(1) end end
        local m0 = mockkb
        local k0 = collectgarbage("count")
        hk[1]()
        hk[2]()
        hk[3](false, false, false)
        kb = kb + (collectgarbage("count") - k0) - (mockkb - m0)
        n = n + 1
    end
    collectgarbage("restart")
    if jit and jit.on then jit.on() end
    M.camStarts = camStarts
    for nm, fn in pairs(wrapped) do gsa1[nm] = fn end
    local per = kb * 1024 / n
    check(per < 16, "no Lua garbage of its own per frame: %.1f bytes (its three hooks, 300 frames moving, the mock "
        .. "module's own left out)", per)
    -- the cost in the mock (host_clock: real time; the JIT on), per refresh and per frame
    local tR, nR, tF, nF = 0, 0, 0, 0
    for _ = 1, 600 do
        M.T = M.T + 1 / 60
        M.frameNo = M.frameNo + 1
        if mc then mc.pos.x = mc.pos.x + 5 end
        M.run_hook("Think")
        for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(1) end end
        local r1 = S.stats.refreshes
        local t0 = host_clock()
        hk[3](false, false, false)
        local dt = host_clock() - t0
        if S.stats.refreshes > r1 then tR, nR = tR + dt, nR + 1 else tF, nF = tF + dt, nF + 1 end
    end
    S.mockCost = { refresh = tR * 1000 / math.max(nR, 1), frame = tF * 1000 / math.max(nF, 1),
                   mean = (tR + tF) * 1000 / math.max(nR + nF, 1) }
    info("the sun shadow in the mock (its PostDrawOpaqueRenderables hook, host_clock): %.3f ms in a frame with a "
        .. "refresh (silhouette + 81 traces), %.3f ms in a frame without (the receivers only), %.3f ms per frame on "
        .. "average at 60 fps", S.mockCost.refresh, S.mockCost.frame, S.mockCost.mean)
    -- the Rendering page: the three rows, bound to their ConVars, the defaults
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
    local rows = {}
    for _, c in ipairs(calls) do
        if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then rows[c[3]] = c end
    end
    local d = GSA1.CONVARS
    local okDefaults = d.gsa1_sunshadow and d.gsa1_sunshadow.default == "1" and d.gsa1_sunshadow_fp.default == "0" and
        d.gsa1_sunshadow_dark.default == "0" and d.gsa1_sunshadow_dark.min == 0 and d.gsa1_sunshadow_dark.max == 100 and
        M.convars.gsa1_sunshadow.client and M.convars.gsa1_sunshadow.save
    check(built and rows.gsa1_sunshadow and rows.gsa1_sunshadow[1] == "CheckBox" and rows.gsa1_sunshadow_fp and
        rows.gsa1_sunshadow_dark and rows.gsa1_sunshadow_dark[1] == "NumSlider" and okDefaults, "Options > G-SA1 > "
        .. "Rendering: \"%s\" (gsa1_sunshadow, on), \"%s\" (off), \"%s\" (0 .. 100, 0)", rows.gsa1_sunshadow and
        rows.gsa1_sunshadow[2] or "-", rows.gsa1_sunshadow_fp and rows.gsa1_sunshadow_fp[2] or "-",
        rows.gsa1_sunshadow_dark and rows.gsa1_sunshadow_dark[2] or "-")
    -- the session log's perf line (every 10 s with a character; the mock's clock advances inside a draw)
    M.draw_cost = 1e-5
    for _ = 1, 660 do frame() end
    M.draw_cost = 0
    GSA1.LogFlush()
    local log = M.files["gsa1/log.txt"] or ""
    local pl = string.match(log, "perf [^\n]*sun shadow [%d.]+ ms per frame[^\n]*")
    check(pl ~= nil, "the perf line carries the sun shadow's time (%s)", pl and string.match(pl, "sun shadow [%d.]+ ms per "
        .. "frame") or "none")
end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
