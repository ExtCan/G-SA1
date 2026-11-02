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
--      the render target pushed / popped balanced, cleared, blurred once, all of it in PostRender.
--   3  the receivers: a grid of 81 traces whenever the root moved 8 HU (MASK_SOLID, the player filtered), only in the main
--      view, none beyond the light's distance past the feet; the quads drawn after the opaque renderables with ZERO /
--      ONE_MINUS_SRC_COLOR, the tone-mapping scale 1 and restored, the vertex colours (1 - colour / 255) x fade;
--      gsa1_sunshadow_dark instead; the quads stay on the ground between two grids while the picture follows the drawn root
--      every frame (the texture coordinates shift by the root's move / the box); a ledge cell left out.
--   4  skips: nothing with gsa1_sunshadow 0 (no hook at all, no file read), in first person with gsa1_sunshadow_fp 0, with
--      disableallshadows 1, before the main view drew the character, in depth, 3D skybox and water views of a frame whose
--      character IS prepared (0.9.5's check of these was empty: its frame had no prepared character); first person with
--      gsa1_sunshadow_fp 1 draws (the body in the silhouette); at most 30 refreshes a second at 144 fps; a standing
--      character traces 4 grids a second.
--   5  no Lua garbage of its own per frame, drawn and not drawn; the cost in the mock (info); the Rendering page's rows and
--      defaults; the session log's perf line carries "sun shadow N ms per frame"; no Lua error.
--   6  0.9.5a, the owner's two sessions on 0.9.5 (SADC/build/research/fix095a/diagnosis.md). THE FRAME'S ORDER, modelled by
--      this file's frame(): the views as his logs show them (the depth pass first, the character prepared there; the 3D
--      skybox on a map with a sky_camera; the main view), PostRender after them. No PushRenderTarget, render.Clear,
--      BlurRenderTarget or cam.Start from the first view's PreDrawOpaqueRenderables to the end of the last view; the blended
--      pass's cam.Start3D(eye, angles) - what it leaves out comes from the last render operation (the wiki's page; the model
--      counts one that follows a cam.Start of the same frame's views) - inherits nothing; the picture's own order in
--      PostRender, the tone-mapping scale 1 over it and restored; the quads appear the frame after the first refresh; no
--      picture of a character whose batches are stale at the frame's end. gm_snowrider_day_v3 (session 1; its real numbers,
--      no sky_camera): the main view with isDrawSkybox true draws. gm_highway14800 (session 2; it has a sky_camera): the
--      quads in the main view and not in the 3D skybox's. A map with a sky_camera, isDrawSkybox true, isDraw3DSkybox false:
--      the view id decides. AT SPEED (his log: 1339 HU/s on the board, other pairs 1500-2300): at his two frame rates, on
--      flat ground in three directions, up to 2300 HU/s, in EVERY frame a disc of 16 HU round the picture's centre lies on
--      drawn cells (on a grid traced at the end of an earlier frame it left them at 20 to 30 Hz), at most one grid a frame,
--      none outside the main view; walking, a grid only every few frames and the darkness at the picture's centre steady.
--      Another character: nothing with the old one's picture, drawn from the frame after its own; removed: nothing. Why not
--      drawn: one log line per reason per map after 5 s, the reason on the page, none when drawn.
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
--     S.RT_SIZE 256, S.GRID 9, S.BLUR 2, S.SLICE 256 KB, S.LUMP_MAX 8 MB, S.REFRESH 1/30 s, S.RETRACE_MOVE 8 HU,
--     S.RETRACE_EVERY 0.25 s, S.MIN_DOWN sin 10 degrees, S.STEP_DEPTH 24 HU, S.LIFT 0.5 HU, S.BOX_MIN 48 HU, S.DEFAULT
--     (bin/base.fgd's shadow_control: 80 30 0, 128 128 128, 75, 0). UNVERIFIED in game: GMod's ortho convention (top =
--     -box is the picture's top, as top-down minimap addons use it), the decal blend on DXVK, the engine's own defaults for
--     keys a map leaves out.
--     0.9.5a: S.Apply also hooks PostRender (the silhouette, the reason); the grid is traced in the main view's hook, before
--     the quads; S.light.sky3d (false: no sky_camera); S.WHY (the reasons' strings), S.why, S.whySince, S.WHY_AFTER 5 s,
--     S.WHY_SHOW 1 s; S.quadsFrame (the frame of the last quads), S.drawnFrame (the frame the main view took the character),
--     S.hookFrame, S.mainFrame, S.skipWhy, S.pictureC (the character of the picture).
--     UNVERIFIED in game, only the owner can see them: that the flashing is gone, cam.Start with the ortho box and
--     render.BlurRenderTarget in PostRender at 30 Hz, GMod's isDraw3DSkybox in the 3D skybox's view (the view id on a sky_camera
--     map is the fallback), the quads on displacements.
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
-- (features: as the owner's module: "render 1" - camera-relative drawing, so the frame's cam.Start3D calls exist in the mock)
local G = M.module({ archives = { [0] = { 28, 29, 96, 138 } }, batches = function() return LIST end, speed = 0,
                     features = { render = 1 } })
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
local phase, curView = nil, nil         -- frame() below: "view" while a view runs, the name of that view
local quadsIn = {}          -- [the view frame() is in] = the receivers' vertices drawn there
mesh.Color = function(r, g, b, a)
    if recording then
        colors[#colors + 1] = r
        local v = curView or "none"
        quadsIn[v] = (quadsIn[v] or 0) + 1
    end
end
local positions = {}
mesh.Position = function(v) if recording then positions[#positions + 1] = v.z end end
local blurs = 0
render.BlurRenderTarget = function() blurs = blurs + 1 end
-- 0.9.5a, the frame's order: what is called while a frame's views run. phase = "view" from the first view's
-- PreDrawOpaqueRenderables to the end of the last view (frame() below); viewCalls: the render target work seen there;
-- picture: while recordPicture, the calls from a push of the sun shadow's own target to its blur
local viewCalls, picture, pictureOn, recordPicture = {}, {}, false, false
local toneAtBox, toneAtBlur = nil, nil      -- the tone-mapping scale when the picture's box was opened and at its blur
local function spy(lib, name, label)
    local f = lib[name]
    lib[name] = function(a, ...)
        if phase == "view" then viewCalls[#viewCalls + 1] = label end
        if label == "PushRenderTarget" then
            pictureOn = recordPicture and GSA1 and GSA1.SunShadow and a == GSA1.SunShadow.rt and a ~= nil
        end
        if pictureOn then picture[#picture + 1] = label end
        if label == "BlurRenderTarget" then
            if pictureOn then toneAtBlur = tone.x end
            pictureOn = false
        end
        return f(a, ...)
    end
end
spy(render, "PushRenderTarget", "PushRenderTarget")
spy(render, "PopRenderTarget", "PopRenderTarget")
spy(render, "Clear", "Clear")
spy(render, "BlurRenderTarget", "BlurRenderTarget")
-- (the wiki's cam.Start3D page: what it leaves out falls back to the current or last render operation. The model: inside a
-- view, a cam.Start3D with no viewport after a cam.Start of the same frame's views takes the box's: "inherited")
local camInView, start3d, inherited = false, 0, 0
do
    local camStart, camStart3D = cam.Start, cam.Start3D
    cam.Start = function(t)
        if phase == "view" then
            viewCalls[#viewCalls + 1] = "cam.Start"
            camInView = true
        end
        if pictureOn then
            picture[#picture + 1] = "cam.Start"
            toneAtBox = tone.x
        end
        return camStart(t)
    end
    cam.Start3D = function(eye, ang, fov, x, y, w, h, ...)
        if phase == "view" and not w then
            start3d = start3d + 1
            if camInView then inherited = inherited + 1 end
        end
        return camStart3D(eye, ang, fov, x, y, w, h, ...)
    end
end

-- the ground: z = GROUND_Z; a crate top at CRATE (x range) if set
local GROUND_Z = -143
local CRATE = nil
local function plane(s, e, z)
    if s.z >= z and e.z <= z and s.z ~= e.z then
        local f = (s.z - z) / (s.z - e.z)
        return f, s.x + (e.x - s.x) * f, s.y + (e.y - s.y) * f
    end
end
local tracesIn = {}          -- [the view frame() is in, or "none"] = the traces made there
local function trace_line(t)
    local v = curView or "none"
    tracesIn[v] = (tracesIn[v] or 0) + 1
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
    gm_construct = WORLD .. ent({ { "classname", "sky_camera" }, { "origin", "0 0 0" }, { "scale", "16" } }) ..
        ent({ { "classname", "shadow_control" }, { "angles", "90 0 0" }, { "color", "187 187 187" },
        { "distance", "1000" }, { "disableallshadows", "0" } }) .. ent({ { "classname", "light_environment" },
        { "angles", "0 306 0" }, { "pitch", "-56" } }),
    gm_genesis = WORLD .. ent({ { "classname", "light_environment" }, { "angles", "0 306 0" }, { "pitch", "-56" } }),
    gm_highway14800 = WORLD .. ent({ { "classname", "sky_camera" }, { "origin", "572 -28 14692" }, { "scale", "16" } }) ..
        ent({ { "classname", "shadow_control" }, { "angles", "0 0 0" }, { "color", "128 128 128" },
        { "distance", "1000" }, { "disableallshadows", "0" } }) .. string.rep(ent({ { "classname", "light_environment" },
        { "angles", "0 298 0" }, { "pitch", "-60" } }), 3),
    -- the owner's session 1 (read from the map's entity lump): only one light_environment, no sky_camera: a 2D sky
    gm_snowrider_day_v3 = WORLD .. ent({ { "classname", "light_environment" }, { "angles", "0 0 0" }, { "pitch", "-50" } }),
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

-- a frame as Garry's Mod runs it, with the views' hooks. 0.9.5a: the views as the owner's logs show them, each optional -
-- VIEWS.depth: the depth pass first (GShader; "main 1, depth pass 1" on both maps of his session), into
-- _rt_ResolvedFullFrameDepth: the character's Draw prepares the frame there, so C.viewFrame is this frame's already in every
-- later view; VIEWS.sky3d: the 3D skybox's view on a map with a sky_camera, the screen bound, (false, true, true), nothing of
-- ours drawn in it; the main view: VIEWS.sky2d: isDrawSkybox true, a 2D sky (the wiki's hook page; false under a 3D skybox);
-- VIEWS.target: a render target bound in it; VIEWS.skyArgs: the main view's three arguments, whatever the rest says;
-- VIEWS.culled: the engine does not draw the character's entity this frame
local VIEWS = { depth = false, sky3d = false, sky2d = false, target = nil, skyArgs = nil, culled = false }
local DEPTH_RT = { GetName = function() return "_rt_ResolvedFullFrameDepth" end }
local SSAO = STUDIO_SSAODEPTHTEXTURE or 134217728
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
    phase, camInView = "view", false
    if VIEWS.depth then
        curView = "depth"
        M.render_target = DEPTH_RT
        M.run_hook("PreDrawOpaqueRenderables", true, false, false)
        for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(SSAO) end end
        M.run_hook("PostDrawOpaqueRenderables", true, false, false)
        M.render_target = nil
    end
    if VIEWS.sky3d then
        curView = "sky3d"
        M.run_hook("PreDrawOpaqueRenderables", false, true, true)
        M.run_hook("PostDrawOpaqueRenderables", false, true, true)
    end
    curView = "main"
    M.render_target = VIEWS.target
    local a1, a2, a3 = false, VIEWS.sky2d and true or false, false
    if VIEWS.skyArgs then a1, a2, a3 = VIEWS.skyArgs[1], VIEWS.skyArgs[2], VIEWS.skyArgs[3] end
    M.run_hook("PreDrawOpaqueRenderables", a1, a2, a3)
    if not VIEWS.culled then
        for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(1) end end
    end
    M.run_hook("PostDrawOpaqueRenderables", a1, a2, a3)
    M.run_hook("PreDrawTranslucentRenderables", a1, a2)
    if not VIEWS.culled then
        for _, e in ipairs(M.entities) do if not e.removed and e.DrawTranslucent then e:DrawTranslucent(1) end end
    end
    M.run_hook("PostDrawTranslucentRenderables", a1, a2)
    M.render_target = nil
    phase, curView = nil, nil
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
    tracesIn = {}
    frames(60)
    local refreshes = S.stats.refreshes - refr0
    local traces = (M.calls.TraceLine or 0) - tr0
    local sorted, seen = {}, {}
    for _, i in ipairs(emitted) do if not seen[i] then seen[i] = true; sorted[#sorted + 1] = i end end
    table.sort(sorted)
    local v = dvKinds[1] or {}
    local cs = M.camStarts[#M.camStarts]
    check(refreshes >= 59 and refreshes <= 61 and dvCalls == refreshes and v.kind == "sunshadow" and v.ortho ~= nil and
        v.opaque == true and v.material ~= nil and v.material.shader == "UnlitGeneric" and cs and cs.ortho ~= nil and
        cs.type == "3D", "one orthographic DrawCharacterView per refresh: %d refreshes in 1 s at 60 fps, %d views "
        .. "(kind %s, the ortho box, opaque only, the flat white UnlitGeneric)", refreshes, dvCalls, tostring(v.kind))
    check(table.concat(sorted, " ") == "1 2", "the silhouette draws only the body and the board (batches \"%s\"; the mock "
        .. "also has an effect, a game object, the blob and a sprite)", table.concat(sorted, " "))
    local pushes, pops = (M.calls.PushRenderTarget or 0) - push0, (M.calls.PopRenderTarget or 0) - pop0
    check(pushes == refreshes and pops == pushes and (M.calls.Clear or 0) - clear0 >= refreshes and blurs - blur0 ==
        refreshes and #viewCalls == 0, "the render target: %d pushes, %d pops, cleared, blurred once per refresh (%d), "
        .. "none of it inside a view (%d calls there)", pushes, pops, blurs - blur0, #viewCalls)
    check(traces % 81 == 0 and traces / 81 >= 28 and traces / 81 <= 31 and tracesIn.main == traces, "a grid of 81 traces "
        .. "whenever the root moved 8 HU: %d traces in 1 s at 10 HU per game pair (%d grids), all in the main view (%d there)",
        traces, traces / 81, tracesIn.main or 0)
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
    -- the quads follow the drawn root every frame, between two grids too (the drawn root moves 3 HU every frame here, as an
    -- interpolated one does, and nothing else moves it: a grid every third frame)
    G.Tick = moveTick
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
        -- (no new grid in the second frame - a grid is made right before the quads - so its quads use the grid the first
        -- one's did: the same ground points, the picture moved with the root; the light straight down: the view's up is +x,
        -- so v grows by the root's x move / (2 x the box))
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
    S.grid.at = nil
    colors = {}
    frames(3)
    local cells = S.grid.ncells
    CRATE = nil
    S.grid.at = nil
    frames(3)
    check(cells < 64 and cells >= 40, "a ledge under the shadow: the cells across it are left out (%d of 64)", cells)
    M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow = hk
    frames(2)
end

-- 4. skips ------------------------------------------------------------------------------------------------------------------
do
    -- a standing character: the grid at most 4 times a second, the silhouette at the pair rate
    local tr0, rf0 = M.calls.TraceLine or 0, S.stats.refreshes
    frames(60)
    local grids = ((M.calls.TraceLine or 0) - tr0) / 81
    check(grids >= 3 and grids <= 5 and S.stats.refreshes - rf0 >= 28, "standing: %d grids of traces in 1 s (every 0.25 s, so a "
        .. "prop that moves under the shadow is seen), %d silhouettes", grids, S.stats.refreshes - rf0)
    -- gsa1_sunshadow_rate: 0, the default, a picture in every frame at any frame rate (the owner on 0.9.5a: "it runs at a lower
    -- frame rate to the rest of the game"); above 0 at most that many a second
    rf0 = S.stats.refreshes
    frames(144, 1 / 144)
    local r144all = S.stats.refreshes - rf0
    RunConsoleCommand("gsa1_sunshadow_rate", "30")
    rf0 = S.stats.refreshes
    frames(60)
    local r60at30 = S.stats.refreshes - rf0
    rf0 = S.stats.refreshes
    frames(144, 1 / 144)
    local r144 = S.stats.refreshes - rf0
    RunConsoleCommand("gsa1_sunshadow_rate", "0")
    rf0 = S.stats.refreshes
    frames(30)
    local rBack = S.stats.refreshes - rf0
    check(r144all >= 143 and r144all <= 145 and rBack >= 29 and r60at30 >= 28 and r60at30 <= 31 and r144 <= 30 and r144 >= 24,
        "the picture: every frame by default (%d in 144 frames at 144 fps, %d in 30 frames after the slider's way back); "
        .. "gsa1_sunshadow_rate 30: %d a second at 60 fps, %d at 144 fps", r144all, rBack, r60at30, r144)
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
    -- depth and 3D skybox views, other render targets, in a frame whose character is prepared (the depth pass's Draw): nothing
    M.render_target = DEPTH_RT
    for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(SSAO) end end
    local prepared = C.viewFrame == FrameNumber()
    M.run_hook("PostDrawOpaqueRenderables", true, false, false)
    M.render_target = nil
    M.run_hook("PostDrawOpaqueRenderables", false, true, true)
    M.render_target = { GetName = function() return "_rt_WaterReflection" end }
    M.run_hook("PostDrawOpaqueRenderables", false, false, false)
    M.render_target = nil
    check(prepared and S.stats.frames == n0, "depth, 3D skybox and water views of a frame with the character prepared: "
        .. "nothing (%s)", prepared and "prepared" or "NOT prepared: the check says nothing")
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
        M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow ~= nil or (M.hooks.PostRender or {}).gsa1_sunshadow ~= nil
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

-- 6. 0.9.5a: the owner's two sessions -------------------------------------------------------------------------------------
do
    GSA1.DrawCharacterView = realDV
    -- the receivers' colours, recorded inside the hook as in section 3 (a new hook after an off / on)
    local function record_quads()
        local hk = M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow
        M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow = function(...)
            recording = true
            local r = hk(...)
            recording = false
            return r
        end
        return function() M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow = hk end
    end
    -- the frame's order: the views as his logs show them, every view (the depth pass with the character's Draw in it)
    VIEWS.depth = true
    RunConsoleCommand("gsa1_sunshadow", "0")
    RunConsoleCommand("gsa1_sunshadow", "1")
    S.refreshAt = nil
    S.grid.at = nil         -- (0.9.5's off left the last grid's time: this check shall see its order, not that)
    viewCalls, picture, pictureOn, recordPicture = {}, {}, false, true
    toneAtBox, toneAtBlur = nil, nil
    local unrecord = record_quads()
    local r0 = S.stats.refreshes
    colors = {}
    frame()
    local q1, r1 = #colors, S.stats.refreshes - r0
    colors = {}
    frame()
    local q2 = #colors
    check(q1 == 0 and r1 == 1 and q2 == 384, "the picture appears the frame after the first refresh: %d receiver vertices in "
        .. "the frame of the first silhouette (%d made, at its end), %d in the next", q1, r1, q2)
    recordPicture = false
    local got = table.concat(picture, " ", 1, math.min(#picture, 5))
    check(got == "PushRenderTarget Clear cam.Start PopRenderTarget BlurRenderTarget", "one picture's order at the frame's "
        .. "end: \"%s\"", got)
    check(toneAtBox == 1 and toneAtBlur == 1 and tone.x == 2, "the tone-mapping scale 1 from the picture's box to its blur "
        .. "(%s, %s) and restored after it (%s): an HDR map's scale at the frame's end does not grey the picture",
        tostring(toneAtBox), tostring(toneAtBlur), tostring(tone.x))
    do
        -- the character's batches go stale between the main view and the frame's end: no picture, no render target
        hook.Add("PostDrawTranslucentRenderables", "feat_liveshadow_test", function() GSA1.Char.viewFrame = -1 end)
        S.refreshAt = nil
        local p0, n0 = M.calls.PushRenderTarget or 0, S.stats.refreshes
        frame()
        hook.Remove("PostDrawTranslucentRenderables", "feat_liveshadow_test")
        check((M.calls.PushRenderTarget or 0) == p0 and S.stats.refreshes == n0, "batches stale at the frame's end: no picture "
            .. "and no render target (%d pushes)", (M.calls.PushRenderTarget or 0) - p0)
        frames(2)
    end
    viewCalls, start3d, inherited = {}, 0, 0
    r0 = S.stats.refreshes
    frames(120)
    local seen = {}
    for _, name in ipairs(viewCalls) do seen[name] = (seen[name] or 0) + 1 end
    local names = {}
    for name, c in pairs(seen) do names[#names + 1] = name .. " x" .. c end
    table.sort(names)
    check(S.stats.refreshes - r0 >= 56 and #viewCalls == 0, "%d silhouettes in 120 frames, and between the first view's "
        .. "PreDrawOpaqueRenderables and the end of the last view no PushRenderTarget, render.Clear, BlurRenderTarget or "
        .. "cam.Start (%s)", S.stats.refreshes - r0, #names > 0 and table.concat(names, ", ") or "none")
    check(start3d >= 120 and inherited == 0, "the character's camera-relative cam.Start3D(eye, angles) in the views (%d, the "
        .. "blended pass among them) never follows a cam.Start of the same frame: %d took its box", start3d, inherited)
    unrecord()

    -- session 1: gm_snowrider_day_v3, no sky_camera: the main view comes with isDrawSkybox true
    local L = read_map(bsp(MAPS.gm_snowrider_day_v3))
    VIEWS.sky2d = true
    unrecord = record_quads()
    frames(4)
    r0 = S.stats.refreshes
    colors, quadsIn = {}, {}
    frames(30)
    local cmax = 0
    for _, c in ipairs(colors) do if c > cmax then cmax = c end end
    check(L and L.sky3d == false and dir_ok(L, 0.6428, 0, -0.7660) and string.find(L.text, "no sky_camera", 1, true) and
        S.stats.refreshes - r0 >= 14 and (quadsIn.main or 0) > 0 and near(cmax, 127, 0.5), "gm_snowrider_day_v3 (session "
        .. "1): a 2D sky, the main view (false, true, false): drawn: %d silhouettes in 30 frames, %d receiver vertices, "
        .. "colour %.1f (255 - 128 at the feet); the light: %s", S.stats.refreshes - r0, quadsIn.main or 0, cmax,
        L and L.text or "-")
    VIEWS.sky2d = false
    unrecord()

    -- session 2: gm_highway14800, a sky_camera: the 3D skybox's view (false, true, true) before the main view (false, false, false)
    L = read_map(bsp(MAPS.gm_highway14800))
    VIEWS.sky3d = true
    unrecord = record_quads()
    frames(4)
    colors, quadsIn = {}, {}
    frames(30)
    check(L and L.sky3d == true and (quadsIn.main or 0) > 0 and quadsIn.sky3d == nil, "gm_highway14800 (session 2): a "
        .. "sky_camera: the quads in the main view (%d vertices) and none in the 3D skybox's (%d)", quadsIn.main or 0,
        quadsIn.sky3d or 0)
    -- a map with a sky_camera and a view that says 2D sky, not 3D (r_3dsky 0, or the sky_camera's area out of sight): the view id
    VIEWS.sky3d = false
    VIEWS.skyArgs = { false, true, false }
    M.view_setup = { viewid = 0 }
    colors, quadsIn = {}, {}
    frames(10)
    local as_main = quadsIn.main or 0
    M.view_setup = { viewid = 1 }
    colors, quadsIn = {}, {}
    frames(10)
    local as_sky = quadsIn.main or 0
    M.view_setup = nil
    colors, quadsIn = {}, {}
    frames(10)
    local as_unknown = quadsIn.main or 0
    VIEWS.skyArgs = nil
    check(as_main > 0 and as_sky == 0 and as_unknown == 0, "a sky_camera map, (false, true, false): view id 0 draws (%d "
        .. "vertices), view id 1 or no answer does not (%d, %d)", as_main, as_sky, as_unknown)
    -- a map with no sky_camera has no 3D skybox's view, so (false, true, true) there is its main view too: no log can show the
    -- third argument under a 2D sky, 0.9.5 tested all three together
    read_map(bsp(MAPS.gm_snowrider_day_v3))
    frames(4)
    VIEWS.skyArgs = { false, true, true }
    colors, quadsIn = {}, {}
    frames(10)
    local third_arg = quadsIn.main or 0
    VIEWS.skyArgs = nil
    check(third_arg > 0, "gm_snowrider_day_v3, (false, true, true): the main view still draws (%d vertices)", third_arg)
    read_map(bsp(MAPS.gm_highway14800))
    frames(4)
    unrecord()

    -- AT SPEED: the owner's log has 1339 HU/s on the board (mode 62, 23:43:55-56), other pairs 1500-2300 HU/s. The picture is
    -- made every 2 or 3 frames at his frame rates (1/59.9: 2; 1/60.19: 3); the quads must lie under it in every frame all the
    -- same, or the shadow strobes at that rate (the first 0.9.5a draft's grid, traced at a frame's end, did: 88 / 8 / 100 % at
    -- 1340 HU/s, 0 / 100 / 8 at 2000)
    do
        L = read_map(bsp(MAPS.gm_highway14800))
        VIEWS.sky3d = true
        unrecord = record_quads()
        local uv = {}
        local mtex = mesh.TexCoord
        mesh.TexCoord = function(_, u, v)
            if recording then
                uv[#uv + 1] = u
                uv[#uv + 1] = v
            end
        end
        local render1 = G.Render
        local speed, along, across = 0, 1, 0
        function G.Render(id, alpha)
            local a, b, x, y, z, e, f, g, h, i = render1(id, alpha)
            return a, b, x and speed * M.T * along, y and speed * M.T * across, z, e, f, g, h, i
        end
        -- the triangle drawn this frame that holds a point of the picture (the texture coordinates of its 3 corners from uv[t])
        -- and the point's weights
        local function tri_at(x, y)
            for t = 1, #uv - 5, 6 do
                local ax, ay, bx, by, cx, cy = uv[t], uv[t + 1], uv[t + 2], uv[t + 3], uv[t + 4], uv[t + 5]
                local den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
                if den ~= 0 then
                    local w1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / den
                    local w2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / den
                    local w3 = 1 - w1 - w2
                    if w1 >= -1e-9 and w2 >= -1e-9 and w3 >= -1e-9 then return t, w1, w2, w3 end
                end
            end
        end
        -- the share of a disc of 16 HU round the picture's centre that lies on the triangles drawn this frame
        local function on_cells()
            local r = 16 / (2 * S.grid.box)
            local inside, total = 0, 0
            for a = 0, 11 do
                for ring = 1, 4 do
                    local rr = r * ring / 4
                    total = total + 1
                    if tri_at(0.5 + rr * math.cos(a * math.pi / 6), 0.5 + rr * math.sin(a * math.pi / 6)) then
                        inside = inside + 1
                    end
                end
            end
            return inside / total
        end
        local worst, where, most = 1, "-", 0
        tracesIn = {}
        -- (gm_highway14800's sun: towards yaw 298)
        local dirs = { { "along x", 1, 0 }, { "across the sun", 0.8829, 0.4695 }, { "along the sun", 0.4695, -0.8829 } }
        for _, dt in ipairs({ 1 / 60.19, 1 / 59.9 }) do
            for _, d in ipairs(dirs) do
                along, across = d[2], d[3]
                for _, v in ipairs({ 0, 500, 1000, 1340, 1600, 2000, 2300 }) do
                    speed = v
                    frames(10, dt)
                    for _ = 1, 60 do
                        uv = {}
                        local t0 = M.calls.TraceLine or 0
                        frame(dt)
                        most = math.max(most, (M.calls.TraceLine or 0) - t0)
                        local share = on_cells()
                        if share < worst then
                            worst, where = share, string.format("%d HU/s %s at 1/%.2f s", v, d[1], 1 / dt)
                        end
                    end
                end
            end
        end
        check(worst >= 1 - 1e-9 and most <= 81, "at speed: in every frame up to 2300 HU/s, 1/60.19 and 1/59.9 s a frame, three "
            .. "directions, a disc of 16 HU round the picture's centre lies on drawn cells (the worst frame %.0f %%, %s), at "
            .. "most one grid a frame (%d traces)", worst * 100, where, most)
        check((tracesIn.main or 0) > 0 and tracesIn.depth == nil and tracesIn.sky3d == nil and tracesIn.none == nil, "the grid "
            .. "only in the main view (traces: %d there, %d in the depth pass, %d in the 3D skybox's, %d outside the views)",
            tracesIn.main or 0, tracesIn.depth or 0, tracesIn.sky3d or 0, tracesIn.none or 0)
        -- walking: a grid only every few frames, and the darkness steady between two grids (session 1's map: the light's
        -- distance is only 75, so a fade kept from the grid's time would saw by 8 x 0.64 / 75 = 7 % of the shadow's darkness)
        VIEWS.sky3d = false
        L = read_map(bsp(MAPS.gm_snowrider_day_v3))
        VIEWS.sky2d = true
        speed, along, across = 150, 1, 0
        frames(10)
        local t0 = M.calls.TraceLine or 0
        local lo, hi, seen = math.huge, -math.huge, 0
        for _ = 1, 60 do
            uv, colors = {}, {}
            frame()
            local t, w1, w2, w3 = tri_at(0.5, 0.5)
            if t then
                local j = (t + 1) / 2
                local c = colors[j] * w1 + colors[j + 1] * w2 + colors[j + 2] * w3
                lo, hi, seen = math.min(lo, c), math.max(hi, c), seen + 1
            end
        end
        local grids = ((M.calls.TraceLine or 0) - t0) / 81
        check(grids >= 12 and grids <= 16, "walking, 150 HU/s (2.5 HU a frame): %d grids in 60 frames, not one every frame", grids)
        check(seen == 60 and hi - lo < 0.1, "walking on flat ground: the darkness at the picture's centre stays the same from "
            .. "frame to frame, between two grids too (%.2f .. %.2f of 255, %d frames)", lo, hi, seen)
        VIEWS.sky2d = false
        mesh.TexCoord = mtex
        G.Render = render1
        unrecord()
    end

    -- another character: nothing with the old one's picture, drawn from the frame after its own; removed: nothing
    read_map(bsp(MAPS.gm_construct))
    unrecord = record_quads()
    frames(4)
    colors = {}
    frame()
    local before = #colors
    local c0 = GSA1.Char
    GSA1.Spawn("tails")
    colors = {}
    frame()
    local first = #colors
    colors = {}
    frame()
    local second = #colors
    check(GSA1.Char ~= c0 and before == 384 and first == 0 and second == 384, "another character: %d receiver vertices before, "
        .. "%d in its first frame (the picture there is the old one's), %d from the frame after its own picture", before, first,
        second)
    GSA1.Remove(true, false)
    colors = {}
    frames(3)
    local gone = #colors
    GSA1.Spawn("sonic")
    C = GSA1.Char
    colors = {}
    frame()
    first = #colors
    colors = {}
    frame()
    second = #colors
    check(gone == 0 and first == 0 and second == 384, "the character removed: %d receiver vertices in 3 frames; spawned again: "
        .. "%d, then %d", gone, first, second)
    unrecord()
    VIEWS.depth = false

    -- why not drawn: one line per reason per map after 5 s, the reason on the page
    read_map(bsp(MAPS.gm_construct))
    frames(4)
    local function lines(text) return #logs_with("not drawn for 5 s: " .. text) end
    check(S.why == nil and #logs_with("not drawn for 5 s") == 0 and not string.find(GSA1.SunShadowLine(), "not drawn", 1,
        true), "drawn: no reason, no line, nothing on the page (\"%s\")", GSA1.SunShadowLine())
    local function stretch(n) frames(n or 310) end
    -- the reasons, each from a real state
    local dist = GSA1.cv.cam_dist:GetString()
    GSA1.cv.cam_dist:SetString("0")
    frames(250)
    local early = lines("first person")
    stretch(70)
    local page = GSA1.SunShadowLine()
    GSA1.cv.cam_dist:SetString(dist)
    frames(4)
    local back = S.why == nil and not string.find(GSA1.SunShadowLine(), "not drawn", 1, true)
    GSA1.cv.cam_dist:SetString("0")
    stretch()
    GSA1.cv.cam_dist:SetString(dist)
    frames(4)
    check(early == 0 and lines("first person") == 1 and string.find(page, "not drawn now: first person", 1, true) ~= nil and
        back, "first person without gsa1_sunshadow_fp: no line before 5 s, one after, not a second one for a second stretch "
        .. "(%d); the page: \"...%s\"; gone again when drawn", lines("first person"), string.sub(page, -60))
    read_map(bsp(MAPS.awm_bigcity))
    stretch()
    check(lines("this map turns shadows off") == 1, "disableallshadows 1: the reason (%d line)",
        lines("this map turns shadows off"))
    read_map(bsp(MAPS.gm_construct))
    frames(4)
    VIEWS.target = { GetName = function() return "_rt_some_addon" end }
    stretch()
    VIEWS.target = nil
    frames(4)
    check(lines("only views into a render target") == 1, "the hook sees only views into a render target: the reason (%d line)",
        lines("only views into a render target"))
    VIEWS.skyArgs = { false, true, true }
    stretch()
    VIEWS.skyArgs = { true, false, false }
    stretch()
    VIEWS.skyArgs = nil
    frames(4)
    check(lines("only the 3D skybox") == 1 and lines("only depth views") == 1, "the hook sees only the 3D skybox's view / "
        .. "only depth views: the reasons (%d, %d lines)", lines("only the 3D skybox"), lines("only depth views"))
    local hk = M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow
    M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow = nil
    stretch()
    M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow = hk
    frames(4)
    check(lines("Garry's Mod did not call") == 1, "another addon's hook answered first, the hook never runs: the reason (%d "
        .. "line)", lines("Garry's Mod did not call"))
    -- the same at the frame's end, where the reasons are worked out: the main view's hook has to say it
    local hk_post = M.hooks.PostRender.gsa1_sunshadow
    M.hooks.PostRender.gsa1_sunshadow = nil
    stretch(650)
    local post_page = GSA1.SunShadowLine()
    M.hooks.PostRender.gsa1_sunshadow = hk_post
    frames(4)
    check(lines("G-SA1's hook at the frame's end was not called") == 1 and string.find(post_page, "not drawn now", 1, true) ~= nil,
        "another addon's PostRender answered first: the reason (%d line), on the page (\"%s\")",
        lines("G-SA1's hook at the frame's end was not called"), post_page)
    local ground = GROUND_Z
    GROUND_Z = -1e6
    S.refreshAt = nil
    S.grid.at = nil
    stretch()
    GROUND_Z = ground
    S.refreshAt = nil
    S.grid.at = nil
    frames(4)
    check(lines("no ground") == 1 and S.why == nil, "no ground within the light's distance: the reason (%d line), drawn again "
        .. "over the ground", lines("no ground"))
    VIEWS.culled = true
    stretch()
    VIEWS.culled = false
    frames(4)
    check(lines("the character was not drawn") == 1, "the engine does not draw the character: the reason (%d line)",
        lines("the character was not drawn"))
    local Ckeep = GSA1.Char
    GSA1.Char = nil
    stretch()
    local nochar = GSA1.SunShadowLine()
    GSA1.Char = Ckeep
    frames(4)
    check(lines("no character") == 0 and string.find(nochar, "not drawn now: no character", 1, true) ~= nil,
        "no character: on the page, not in the log (nothing is wrong)")
    -- another map: the reasons again (a map change restarts the client's Lua in the game; the state is per map anyway)
    local gm0 = game.GetMap
    game.GetMap = function() return "gm_other" end
    M.gamefiles["maps/gm_other.bsp"] = bsp(MAPS.gm_construct)
    frames(4)
    GSA1.cv.cam_dist:SetString("0")
    stretch()
    GSA1.cv.cam_dist:SetString(dist)
    game.GetMap = gm0
    M.gamefiles["maps/gm_other.bsp"] = nil
    read_map(bsp(MAPS.gm_construct))
    frames(4)
    check(lines("first person") == 2, "at most once per reason per map: another map logs it again (%d lines in all)",
        lines("first person"))
    -- off again: no reason left, nothing logged in a long stretch
    local n1 = #logs_with("not drawn for 5 s")
    RunConsoleCommand("gsa1_sunshadow", "0")
    GSA1.cv.cam_dist:SetString("0")
    stretch()
    GSA1.cv.cam_dist:SetString(dist)
    local off = #logs_with("not drawn for 5 s") == n1 and S.why == nil
    RunConsoleCommand("gsa1_sunshadow", "1")
    frames(10)
    check(off and S.why == nil, "gsa1_sunshadow 0: no reason, no line (the PostRender hook is gone too); on again: drawn")
    check(#viewCalls == 0, "over all of this test's frames since the check above: no render target work inside a view (%d)",
        #viewCalls)
end

-- 5. garbage, cost, the page, the log ----------------------------------------------------------------------------------
do
    GSA1.DrawCharacterView = realDV
    local hk = { M.hooks.Think.gsa1_sunshadow, M.hooks.PreRender.gsa1_sunshadow,
                 M.hooks.PostDrawOpaqueRenderables.gsa1_sunshadow,
                 (M.hooks.PostRender or {}).gsa1_sunshadow or function() end }
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
        hk[4]()
        kb = kb + (collectgarbage("count") - k0) - (mockkb - m0)
        n = n + 1
    end
    -- the same in first person without gsa1_sunshadow_fp: not drawn, a reason every frame (a constant string)
    local dist = GSA1.cv.cam_dist:GetString()
    GSA1.cv.cam_dist:SetString("0")
    local kb2, n2 = 0, 0
    for _ = 1, 300 do
        M.T = M.T + 1 / 60
        M.frameNo = M.frameNo + 1
        M.run_hook("Think")
        for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(1) end end
        local m0 = mockkb
        local k0 = collectgarbage("count")
        hk[2]()
        hk[3](false, false, false)
        hk[4]()
        kb2 = kb2 + (collectgarbage("count") - k0) - (mockkb - m0)
        n2 = n2 + 1
    end
    GSA1.cv.cam_dist:SetString(dist)
    collectgarbage("restart")
    if jit and jit.on then jit.on() end
    M.camStarts = camStarts
    for nm, fn in pairs(wrapped) do gsa1[nm] = fn end
    local per = kb * 1024 / n
    check(per < 16, "no Lua garbage of its own per frame: %.1f bytes (its four hooks, 300 frames moving, the mock "
        .. "module's own left out)", per)
    local per2 = kb2 * 1024 / n2
    check(per2 < 16, "none either when not drawn, a reason every frame: %.1f bytes (first person, 300 frames: one log line "
        .. "in them at most)", per2)
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
        hk[4]()
        local dt = host_clock() - t0
        if S.stats.refreshes > r1 then tR, nR = tR + dt, nR + 1 else tF, nF = tF + dt, nF + 1 end
    end
    S.mockCost = { refresh = tR * 1000 / math.max(nR, 1), frame = tF * 1000 / math.max(nF, 1),
                   mean = (tR + tF) * 1000 / math.max(nR + nF, 1) }
    info("the sun shadow in the mock (its PostDrawOpaqueRenderables and PostRender hooks, host_clock), 5 HU a frame (81 traces "
        .. "in about every other frame): %.3f ms in a frame with a silhouette, %.3f ms in a frame without, %.3f ms per frame on "
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
        d.gsa1_sunshadow_rate and d.gsa1_sunshadow_rate.default == "0" and d.gsa1_sunshadow_rate.max == 60 and
        M.convars.gsa1_sunshadow.client and M.convars.gsa1_sunshadow.save
    check(rows.gsa1_sunshadow_rate and rows.gsa1_sunshadow_rate[1] == "NumSlider", "Options > G-SA1 > Rendering: \"%s\" "
        .. "(0 .. 60, 0)", rows.gsa1_sunshadow_rate and rows.gsa1_sunshadow_rate[2] or "-")
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
