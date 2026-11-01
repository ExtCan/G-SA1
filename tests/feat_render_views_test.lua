-- feat_render_views_test.lua - 0.9.2 (sadc docs/research/gsa1_090_render.md R1, R1b, R2, R2b, D1 with its review RC1-RC4):
-- what cl_render.lua draws in each of Source's views, in Garry's Mod's own LuaJIT against tests/lua_mock.lua.
--   lua_host tests/feat_render_views_test.lua <tests dir> <addon/lua dir>
-- One frame plays through Source's views in their order - VIEW enum: 0 main, 3 water reflection, 4 water refraction,
-- 7 shadow depth (a lamp / flashlight), 8 SSAO depth (the depth pass: render.GetResolvedFullFrameDepth, what GShader, sun
-- shafts, depth of field and bokeh read) - each with its render target and ENT:Draw / DrawTranslucent flags (the research's
-- views_test.lua, render090). The review's variants (views_variants_test.lua, render090review) change what Garry's Mod is
-- assumed to report, since that is UNVERIFIED:
--   as_doc  : render.GetViewSetup(true).viewid is the view being drawn; ENT:Draw gets the STUDIO depth flags
--   player  : the view setup is the player's in every view (viewid 0)
--   noflags : as player, and ENT:Draw gets STUDIO_RENDER only
--   stale   : viewid is the previous view's
--   fxoff   : an opaque effect batch with gsa1_effects 0 (the depth must leave it out like the screen: review RC2)
--   bracket : as noflags, and the depth views' render targets have unknown names: only PreDrawOpaqueRenderables'
--             isDrawingDepth says that they are depth views
-- Then (as_doc): the DepthWrite materials' parameters, static meshes (gsa1_interpolate 0) reused in a depth view only for
-- their pair and origin, gsa1_depthfix 0 / 1 / 2 (R1b: one push of the depth texture per frame after the main view's opaque
-- renderables; none with 1, none in depth views), GSA1.ViewInfo (D1), the Rendering page's control, the debug line.
-- On 0.9.1's files the R1 / R2 / R2b checks fail (5 per variant); with 0.9.2's all pass.
-- 0.9.5 (sadc docs/research/gsa1_095_plan.md 4.10, 5.5 with its review R.10; board095_perf.md P1): section 3 - the board's
-- batches (SA1_DRAW_BOARD 0x4000) drawn with gsa1_effects 0 and in first person (gsa1_set_draw never hides them), a
-- BOARD | SHADOW batch by gsa1_shadow; GSA1.DrawCharacterView draws exactly the batches one colour view draws (both passes,
-- the effects / shadow / objects switches, the hidden batches), never in a frame the main view did not draw, counted as its
-- own kind and never as "main". The sun shadow (its own test, feat_liveshadow_test.lua) is off in these worlds.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
-- (GMod's own print goes to the engine console, which lua_host does not have: the mock's print writes through host_write;
-- before the first mock is loaded host_write is used directly)
host_write("G-SA1 feat_render_views_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")\n")

local TOTAL, FAILED = 0, 0
local WATER_Z = -120
local F_RENDER, F_SSAO, F_SHADOW = 1, 134217728, 1073741824
local V_MAIN, V_REFLECTION, V_REFRACTION, V_SHADOW, V_SSAO = 0, 3, 4, 7, 8

-- batches { archive, tex, flags, src, dst, wrap, pass, tris, prims }: the body (palette-lit, opaque), a cut-out part
-- (alpha test), an additive effect sprite, the blob shadow (mask)
local function batch_list(variant)
    local L = {
        { 0, 0, 0x20, 1, 0, 3, 0, 100, 1 },
        { 0, 1, 0x22, 1, 0, 3, 0, 10, 1 },
        { 1, 2, 0x255, 4, 1, 3, 1, 2, 2 },
        { 2, 58, 0x841, 4, 5, 11, 1, 2, 1 },
    }
    if variant == "fxoff" then L[#L + 1] = { 0, 3, 0x40, 1, 0, 3, 0, 20, 1 } end
    if variant == "board" then
        L = {
            { 0, 0, 0x20, 1, 0, 3, 0, 100, 1 },         -- 1 the body
            { -1, -1, 0x40C0, 1, 0, 0, 0, 44, 1 },      -- 2 the board (BOARD | EFFECT | NO_TEXTURE: board095_lib.md 2.3 G)
            { 1, 2, 0x255, 4, 1, 3, 1, 2, 2 },          -- 3 an additive effect sprite
            { 2, 58, 0x841, 4, 5, 11, 1, 2, 1 },        -- 4 the blob shadow (mask)
            { 2, 58, 0x4841, 4, 5, 11, 1, 2, 1 },       -- 5 a board batch that is a shadow too (BOARD | SHADOW)
            { 0, 1, 0x1040, 1, 0, 3, 0, 10, 1 },        -- 6 a game object (OBJECT | EFFECT)
            { 0, 3, 0x40, 1, 0, 3, 0, 20, 1 },          -- 7 an opaque effect
        }
    end
    return L
end

local function rt(name) return { GetName = function() return name end } end

-- a fresh mock and addon for one variant; E.frame(views, hooks) plays one frame
local function world(variant)
    local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
    M.root = root
    local E = { M = M, variant = variant, late = nil }
    local LIST = batch_list(variant)
    local G = M.module({ archives = { [0] = { 28, 29, 96, 138 } }, batches = function() return LIST end,
                         features = { render = 1 } })
    function G.TextureArchives()
        return { { name = "SONIC", count = 28 }, { name = "SON_EFF", count = 29 }, { name = "OBJ_REGULAR", count = 96 },
                 { name = "EFF_REGULAR", count = 138 } }
    end
    CONTENTS_WATER = 32
    util.PointContents = function(p) return (p.z < WATER_Z) and CONTENTS_WATER or 0 end
    STUDIO_RENDER, STUDIO_SSAODEPTHTEXTURE, STUDIO_SHADOWDEPTHTEXTURE = F_RENDER, F_SSAO, F_SHADOW
    VIEW_MAIN, VIEW_REFLECTION, VIEW_REFRACTION, VIEW_SHADOW_DEPTH_TEXTURE, VIEW_SSAO = V_MAIN, V_REFLECTION,
        V_REFRACTION, V_SHADOW, V_SSAO
    -- recorders: what each view gets (materials, cam.Start3D, model matrices, batches, IMesh draws); R1b's pushes
    local V = nil
    local function sink() return E.late or V end
    local old_set = render.SetMaterial
    function render.SetMaterial(m)
        old_set(m)
        local s = sink()
        if s and m then s.mats[#s.mats + 1] = m end
    end
    cam.Start3D = function(pos)
        local s = sink()
        if s then s.start3d = s.start3d + 1; s.relEye = pos and Vector(pos) end
    end
    cam.End3D = function() local s = sink() if s then s.end3d = s.end3d + 1 end end
    cam.PushModelMatrix = function(m)
        local s = sink()
        if s then s.model = s.model + 1; s.modelT = m and m.t and Vector(m.t) end
    end
    cam.PopModelMatrix = function() local s = sink() if s then s.modelPop = s.modelPop + 1 end end
    local MXT = {}
    MXT.__index = MXT
    function MXT:Identity() self.t = Vector() end
    function MXT:SetTranslation(v) self.t = Vector(v) end
    Matrix = function() return setmetatable({ t = Vector() }, MXT) end
    local old_emit = G.EmitBatch
    function G.EmitBatch(id, i)
        local s = sink()
        if s then s.batches[#s.batches + 1] = i end
        return old_emit(id, i)
    end
    Mesh = function(mat)
        return { mat = mat, Destroy = function() end, Draw = function()
            local s = sink()
            if s then s.imesh = s.imesh + 1 end
        end }
    end
    local old_prep = G.PrepareView
    function G.PrepareView(id, eye, ...)
        E.prepEye = Vector(eye)
        return old_prep(id, eye, ...)
    end
    E.depthTex = rt("_rt_ResolvedFullFrameDepth")
    render.GetResolvedFullFrameDepth = function() return E.depthTex end
    E.pushes, E.ranges = {}, {}
    render.PushRenderTarget = function(t)
        E.pushes[#E.pushes + 1] = { name = t and t.GetName and t:GetName() or tostring(t), view = V and V.name or "-",
                                    frame = M.frameNo }
        E.late = E.newView("late")
        E.lates = E.lates or {}
        E.lates[#E.lates + 1] = E.late
    end
    render.PopRenderTarget = function() E.late = nil end
    render.DepthRange = function(a, b) E.ranges[#E.ranges + 1] = string.format("%g..%g", a, b) end

    function E.newView(name)
        return { mats = {}, start3d = 0, end3d = 0, model = 0, modelPop = 0, batches = {}, imesh = 0, name = name }
    end
    GSA1 = nil
    M.included = {}
    local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
    E.loadError = not ok_load and tostring(err_load) or nil
    if not ok_load then return E end
    GSA1.LoadModule()
    GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
    GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
    GSA1.cv.prewarm:SetString("0")
    -- (0.9.5: the sun shadow pushes a render target of its own after the opaque renderables: tested in its own file)
    if GetConVar("gsa1_sunshadow") then RunConsoleCommand("gsa1_sunshadow", "0") end
    if variant == "fxoff" then GSA1.cv.effects:SetString("0") end
    GSA1.Spawn("sonic")
    E.C = GSA1.Char
    if not E.C then return E end
    for _ = 1, 10 do M.frame(1 / 60) end
    for _, e in ipairs(M.entities) do if e.cls == "gsa1_render" and not e.removed then E.ent = e end end

    -- one frame with the given views (in Source's order), each drawn with Draw(flags) then, except depth views,
    -- DrawTranslucent(flags); hooks: the PreDrawOpaqueRenderables / PostDrawOpaqueRenderables brackets around Draw
    function E.frame(views, hooks)
        M.dt = 1 / 60
        M.T = M.T + M.dt
        M.frameNo = M.frameNo + 1
        M.run_hook("Think")
        M.run_hook("CreateMove", setmetatable({}, { __index = function() return function() return 0 end end }))
        local view = M.run_hook("CalcView", M.player, M.player:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
        local eye = view and view.origin or M.player:EyePos()
        M.run_hook("PreRender")
        local out = {}
        local prev_id = 0
        for _, vw in ipairs(views) do
            V = E.newView(vw.name)
            local e = Vector(eye)
            if vw.viewid == V_REFLECTION then e.z = 2 * WATER_Z - e.z end         -- Source mirrors the eye in z
            if vw.eye then e = Vector(vw.eye[1], vw.eye[2], vw.eye[3]) end
            M.view_origin = e
            local vid = vw.viewid
            if variant == "player" or variant == "noflags" or variant == "bracket" then
                vid = V_MAIN
            elseif variant == "stale" then
                vid = prev_id
            end
            prev_id = vw.viewid
            M.view_setup = { viewid = vid, origin = (variant == "as_doc" or variant == "stale" or variant == "fxoff") and e
                             or eye, angles = Angle(M.pitch, M.yaw, 0) }
            local target = vw.rt
            if variant == "bracket" and vw.depth then target = "_rt_unknown_" .. vw.name end
            M.render_target = target and rt(target) or nil
            local fl = vw.flags or F_RENDER
            if variant == "noflags" or variant == "bracket" then fl = F_RENDER end
            if hooks then M.run_hook("PreDrawOpaqueRenderables", vw.depth or false, false, false) end
            if vw.before then vw.before(V) end
            E.ent:Draw(fl)
            if vw.probe then vw.probe(V, fl) end
            if hooks then M.run_hook("PostDrawOpaqueRenderables", vw.depth or false, false, false) end
            if not vw.depth then E.ent:DrawTranslucent(fl) end
            out[vw.name] = V
            V = nil
        end
        M.view_origin, M.view_setup, M.render_target = eye, nil, nil
        M.run_hook("PostRender")
        return out, eye
    end
    return E
end

local function shaders(v)
    local seen, t = {}, {}
    for _, m in ipairs(v.mats) do
        local sh = m.shader or "?"
        if not seen[sh] then seen[sh] = true; t[#t + 1] = sh end
    end
    return table.concat(t, ",")
end
local function sorted_batches(v)
    local t = {}
    for i, b in ipairs(v.batches) do t[i] = b end
    table.sort(t)
    return table.concat(t, " ")
end
local function describe(v)
    return string.format("%-11s batches {%s}, shaders {%s}, cam.Start3D %d (relative eye %s), model matrices %d", v.name,
        sorted_batches(v), shaders(v), v.start3d,
        v.relEye and string.format("%.0f %.0f %.0f", v.relEye.x, v.relEye.y, v.relEye.z) or "-", v.model)
end

local VIEWS_A = {   -- expensive water whose reflection does not draw entities: the refraction first
    { name = "refraction", viewid = V_REFRACTION, rt = "_rt_WaterRefraction" },
    { name = "ssao", viewid = V_SSAO, rt = "_rt_ResolvedFullFrameDepth", flags = F_RENDER + F_SSAO, depth = true },
    { name = "main", viewid = V_MAIN },
    { name = "lampdepth", viewid = V_SHADOW, rt = "_rt_ShadowDummy", flags = F_RENDER + F_SHADOW, depth = true,
      eye = { 704, 132, 200 } },      -- the lamp (a Vector once the mock is loaded: E.frame)
}
local VIEWS_B = {   -- expensive water that reflects entities: the reflection is the frame's first view
    { name = "reflection", viewid = V_REFLECTION, rt = "_rt_WaterReflection" },
    { name = "refraction", viewid = V_REFRACTION, rt = "_rt_WaterRefraction" },
    { name = "ssao", viewid = V_SSAO, rt = "_rt_ResolvedFullFrameDepth", flags = F_RENDER + F_SSAO, depth = true },
    { name = "main", viewid = V_MAIN },
}

local function finish(M)
    M.check(#M.reported == 0, "no Lua error%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
    TOTAL, FAILED = TOTAL + M.checks, FAILED + M.fails
end

-- 1. the views, under each variant ------------------------------------------------------------------------------------
for _, variant in ipairs({ "as_doc", "player", "noflags", "stale", "fxoff", "bracket" }) do
    host_write("\n-- variant " .. variant .. "\n")
    local E = world(variant)
    local M = E.M
    local check, info = M.check, M.info
    check(E.loadError == nil and E.C ~= nil and E.ent ~= nil, "the addon loads, Sonic spawns, the entity exists%s",
        E.loadError and (": " .. E.loadError) or "")
    if E.C and E.ent then
        local C = E.C
        local hooks = variant == "bracket"
        print(string.format("water at z %d; Sonic's drawn root z %.1f; the eye above the water", WATER_Z, C.drawPos.z))
        local A, eyeA = E.frame(VIEWS_A, hooks)
        info("scenario A (refraction first): main eye z %.1f, PrepareView's eye z %.1f", eyeA.z, E.prepEye and E.prepEye.z
            or -1)
        for _, vw in ipairs(VIEWS_A) do info("%s", describe(A[vw.name])) end
        local B, eyeB = E.frame(VIEWS_B, hooks)
        info("scenario B (reflection first): main eye z %.1f, PrepareView's eye z %.1f (the mirrored eye: %.1f)", eyeB.z,
            E.prepEye and E.prepEye.z or -1, 2 * WATER_Z - eyeB.z)
        for _, vw in ipairs(VIEWS_B) do info("%s", describe(B[vw.name])) end
        -- R1: depth views (SSAO, shadow depth) draw the opaque batches only, with DepthWrite materials, no cam.Start3D,
        -- at world positions
        for _, n in ipairs({ "ssao", "lampdepth" }) do
            local v = A[n]
            local t = v.modelT
            check(shaders(v) == "DepthWrite" and sorted_batches(v) == "1 2" and v.start3d == 0 and v.model == 1 and
                v.modelPop == 1 and t ~= nil and math.abs(t.z - C.drawPos.z) < 1e-3,
                "R1 %s view: the opaque batches (1 2), DepthWrite, no cam.Start3D, one model matrix at the drawn root "
                .. "(got batches {%s}, shaders {%s}, %d cam.Start3D, %d model matrices)", n, sorted_batches(v),
                shaders(v), v.start3d, v.model)
        end
        -- R2: water views at world positions (Source clips and fogs them by world heights)
        for _, sc in ipairs({ { "A", A }, { "B", B } }) do
            for _, n in ipairs({ "reflection", "refraction" }) do
                local v = sc[2][n]
                if v then
                    local t = v.modelT
                    local world_pos = v.start3d == 0 and (C.relOrigin == nil or (t and math.abs(t.x - C.drawPos.x) < 1e-3
                        and math.abs(t.y - C.drawPos.y) < 1e-3 and math.abs(t.z - C.drawPos.z) < 1e-3))
                    check(world_pos and v.model == v.modelPop, "R2 scenario %s, %s view: world positions (0 cam.Start3D, "
                        .. "got %d; relative vertices under a model matrix translated by the drawn root: %s)", sc[1], n,
                        v.start3d, t and string.format("%.1f %.1f %.1f", t.x, t.y, t.z) or "none")
                end
            end
        end
        -- the main view keeps 0.8's camera-relative drawing (the eye above the water), with its colour materials
        check(A.main.start3d == 2 and B.main.start3d == 2 and A.main.end3d == 2 and B.main.end3d == 2 and
            A.main.model == 0 and B.main.model == 0, "main view: camera-relative in both scenarios (cam.Start3D: A %d, "
            .. "B %d; 0.9.0 decided once per frame in the frame's first view)", A.main.start3d, B.main.start3d)
        local want = variant == "fxoff" and 3 or 4      -- fxoff: batches 1 2 4 (the effects 3 and 5 are off)
        for _, sc in ipairs({ { "A", A }, { "B", B } }) do
            local s = shaders(sc[2].main)
            check(not string.find(s, "DepthWrite", 1, true) and #sc[2].main.batches == want, "scenario %s: the main view "
                .. "draws its %d batches with colour materials (got {%s}, %d batches)", sc[1], want, s,
                #sc[2].main.batches)
        end
        -- R2b: the sprites face the main view's eye (PrepareView, once per frame, with the main view's eye)
        check(E.prepEye and math.abs(E.prepEye.z - eyeB.z) < 1e-3, "R2b scenario B: PrepareView's eye is the main "
            .. "view's (z %.1f; got %.1f)", eyeB.z, E.prepEye and E.prepEye.z or -1)
    end
    finish(M)
end

-- 2. the depth materials, static meshes, gsa1_depthfix, R1b, ViewInfo, the menu (as_doc) ------------------------------
host_write("\n-- depth materials, static meshes, gsa1_depthfix, R1b, ViewInfo, the Rendering page\n")
local E = world("as_doc")
local M = E.M
local check, info = M.check, M.info
if not (E.C and E.ent) then
    check(false, "the addon loads and Sonic spawns%s", E.loadError and (": " .. E.loadError) or "")
else
    local C = E.C
    -- (a) the DepthWrite materials: $color_depth 1 in the depth pass, 0 in shadow depth; $model 1; the cut-out (batch 2,
    -- alpha test) keeps its texture; both sides from gsa1_nocull
    local A = E.frame(VIEWS_A)
    local function params_line(v)
        local t = {}
        for _, m in ipairs(v.mats) do
            local p = m.params or {}
            t[#t + 1] = string.format("%s{cd %s, nocull %s, model %s, atest %s, ref %s, tex %s}", tostring(m.name),
                tostring(p["$color_depth"]), tostring(p["$nocull"]), tostring(p["$model"]), tostring(p["$alphatest"]),
                tostring(p["$alphatestreference"]), tostring(p["$basetexture"]))
        end
        return table.concat(t, " ")
    end
    local function depth_ok(v, cd)
        local m1, m2 = v.mats[1], v.mats[2]
        if not (m1 and m2 and m1.shader == "DepthWrite" and m2.shader == "DepthWrite") then return false end
        local p1, p2 = m1.params, m2.params
        return p1["$color_depth"] == cd and p1["$model"] == 1 and p1["$nocull"] == 0 and p1["$alphatest"] == nil and
            p2["$color_depth"] == cd and p2["$alphatest"] == 1 and p2["$alphatestreference"] == 0.5 and
            type(p2["$basetexture"]) == "string" and string.find(p2["$basetexture"], "_0_0_1_3$") ~= nil
    end
    check(depth_ok(A.ssao, 1), "the depth pass's materials: %s", params_line(A.ssao))
    check(depth_ok(A.lampdepth, 0), "shadow depth's materials: %s", params_line(A.lampdepth))
    check(A.ssao.mats[1] ~= A.lampdepth.mats[1], "one material per colour mode (%s / %s)", tostring(A.ssao.mats[1].name),
        tostring(A.lampdepth.mats[1].name))
    local nm = M.nmaterials
    E.frame(VIEWS_A)
    check(M.nmaterials == nm, "made once per state: no new material in the next frame (%d -> %d)", nm, M.nmaterials)
    GSA1.cv.nocull:SetString("1")
    local Anc = E.frame(VIEWS_A)
    local p = Anc.ssao.mats[1] and Anc.ssao.mats[1].params or {}
    check(p["$nocull"] == 1 and Anc.ssao.mats[1].name == "gsa1d_x_011", "gsa1_nocull 1: the depth material draws both "
        .. "sides (%s, $nocull %s)", tostring(Anc.ssao.mats[1] and Anc.ssao.mats[1].name), tostring(p["$nocull"]))
    GSA1.cv.nocull:SetString("0")
    E.frame(VIEWS_A)

    -- (b) static meshes (gsa1_interpolate 0): the depth view after the screen reuses the pair's meshes; a mesh of another
    -- origin is streamed instead (review RC2)
    GSA1.cv.interp:SetString("0")
    local MAIN_SSAO = { { name = "main", viewid = V_MAIN },
                        { name = "ssao", viewid = V_SSAO, rt = "_rt_ResolvedFullFrameDepth", flags = F_RENDER + F_SSAO,
                          depth = true } }
    E.frame(MAIN_SSAO)
    local S1 = E.frame(MAIN_SSAO)
    local reuse = S1.ssao
    local moved = { { name = "main", viewid = V_MAIN },
                    { name = "ssao", viewid = V_SSAO, rt = "_rt_ResolvedFullFrameDepth", flags = F_RENDER + F_SSAO,
                      depth = true, before = function()
                          for _, sm in pairs(C.static or {}) do sm.ox = sm.ox + 1 end
                      end } }
    local S2 = E.frame(moved)
    check(reuse.imesh == 2 and #reuse.batches == 0 and S2.ssao.imesh == 0 and sorted_batches(S2.ssao) == "1 2",
        "gsa1_interpolate 0: the depth view draws the pair's 2 static meshes (%d, %d streamed); with another origin it "
        .. "streams them (%d meshes, batches {%s})", reuse.imesh, #reuse.batches, S2.ssao.imesh, sorted_batches(S2.ssao))
    GSA1.cv.interp:SetString("1")
    E.frame(VIEWS_A)

    -- (c) gsa1_depthfix 0: the depth views drawn as 0.9.1 drew them (colour, camera-relative); 1: DepthWrite
    check(GSA1.cv.depthfix ~= nil and GSA1.cv.depthfix:GetString() == "1" and GSA1.cv.depthfix.lo == 0 and
        GSA1.cv.depthfix.hi == 2, "gsa1_depthfix: default 1, 0 .. 2")
    if not GSA1.cv.depthfix then GSA1.cv.depthfix = M.cv("gsa1_depthfix_missing", "1") end
    GSA1.cv.depthfix:SetString("0")
    local Z = E.frame(VIEWS_A)
    check(not string.find(shaders(Z.ssao), "DepthWrite", 1, true) and Z.ssao.start3d == 1 and
        not string.find(shaders(Z.lampdepth), "DepthWrite", 1, true), "gsa1_depthfix 0: the depth views as 0.9.1 "
        .. "(%s; %s)", describe(Z.ssao), describe(Z.lampdepth))
    GSA1.cv.depthfix:SetString("1")

    -- (d) R1b: gsa1_depthfix 2 pushes the depth texture once per frame after the main view's opaque renderables and draws
    -- the opaque batches there with the $color_depth 1 DepthWrite at world positions, the depth range pulled in and put
    -- back; none with 1, none in depth views, none without a depth pass in the frame
    E.pushes, E.ranges, E.lates = {}, {}, {}
    E.frame(VIEWS_A, true)
    E.frame(VIEWS_B, true)
    check(#E.pushes == 0, "gsa1_depthfix 1: no late depth draw (%d pushes)", #E.pushes)
    GSA1.cv.depthfix:SetString("2")
    E.pushes, E.ranges, E.lates = {}, {}, {}
    local f0 = M.frameNo
    E.frame(VIEWS_A, true)
    E.frame(VIEWS_B, true)
    local per, where = {}, {}
    for _, p2 in ipairs(E.pushes) do
        per[p2.frame] = (per[p2.frame] or 0) + 1
        where[#where + 1] = p2.view .. ":" .. p2.name
    end
    local L1 = E.lates[1]
    local late_ok = L1 ~= nil and shaders(L1) == "DepthWrite" and sorted_batches(L1) == "1 2" and L1.start3d == 0 and
        L1.model == 1 and L1.modelPop == 1 and L1.modelT and math.abs(L1.modelT.z - C.drawPos.z) < 1e-3 and
        L1.mats[1].params["$color_depth"] == 1
    check(#E.pushes == 2 and per[f0 + 1] == 1 and per[f0 + 2] == 1 and where[1] == "main:_rt_ResolvedFullFrameDepth"
        and where[2] == "main:_rt_ResolvedFullFrameDepth" and late_ok and table.concat(E.ranges, " ") ==
        "0..0.99999 0..1 0..0.99999 0..1", "gsa1_depthfix 2: one late depth draw per frame, in the main view (%s), "
        .. "%s, depth range %s", table.concat(where, ", "), L1 and describe(L1) or "none", table.concat(E.ranges, " "))
    E.pushes = {}
    E.frame({ { name = "main", viewid = V_MAIN } }, true)
    check(#E.pushes == 0, "gsa1_depthfix 2 without a depth pass in the frame: no late draw (%d)", #E.pushes)
    E.pushes = {}
    E.frame(VIEWS_A, false)
    check(#E.pushes == 0, "no PostDrawOpaqueRenderables: no late draw (%d)", #E.pushes)
    E.pushes = {}
    M.run_hook("PostDrawOpaqueRenderables", true, false, false)
    M.render_target = rt("_rt_ResolvedFullFrameDepth")
    M.run_hook("PostDrawOpaqueRenderables", false, false, false)
    M.render_target = nil
    check(#E.pushes == 0, "inside a depth view or another render target: no late draw (%d)", #E.pushes)
    GSA1.cv.depthfix:SetString("1")

    -- (e) D1: GSA1.ViewInfo - the last draw's view, and the view being drawn now
    local seen = {}
    local VIEWS_I = {
        { name = "ssao", viewid = V_SSAO, rt = "_rt_ResolvedFullFrameDepth", flags = F_RENDER + F_SSAO, depth = true,
          probe = function(_, fl)
              seen.ssao = GSA1.ViewInfo and GSA1.ViewInfo()
              seen.live = GSA1.ViewInfo and GSA1.ViewInfo(true, fl)
          end },
        { name = "main", viewid = V_MAIN, probe = function() seen.main = GSA1.ViewInfo and GSA1.ViewInfo() end },
    }
    E.frame(VIEWS_I)
    local s, l, mn = seen.ssao or {}, seen.live or {}, seen.main or {}
    check(s.kind == "ssao" and s.shader == "DepthWrite" and s.flags == F_RENDER + F_SSAO and
        s.rt == "_rt_ResolvedFullFrameDepth" and s.pass == 0 and s.frame == M.frameNo and l.kind == "ssao" and
        l.viewid == V_SSAO and l.shader == "DepthWrite" and l.live == true and mn.kind == "main" and
        mn.rt == "the screen" and mn.shader == "VertexLitGeneric", "GSA1.ViewInfo: depth pass {kind %s, shader %s, flags "
        .. "%s, rt %s}, now {kind %s, viewid %s, shader %s}, main {kind %s, rt %s, shader %s}", tostring(s.kind),
        tostring(s.shader), tostring(s.flags), tostring(s.rt), tostring(l.kind), tostring(l.viewid), tostring(l.shader),
        tostring(mn.kind), tostring(mn.rt), tostring(mn.shader))

    -- (f) the Rendering page: a control for gsa1_depthfix; the debug line counts the views
    M.run_hook("PopulateToolMenu")
    local page = nil
    for _, e in ipairs(M.menu) do if e.class == "gsa1_rendering" then page = e end end
    local calls = {}
    local any = setmetatable({}, { __index = function(t) return function() return t end end })
    local P = setmetatable({}, { __index = function(_, k)
        return function(_, ...)
            calls[#calls + 1] = { k, ... }
            return any
        end
    end })
    local built, err = pcall(function() page.cpanel(P) end)
    local combo, choices = false, 0
    for i, c in ipairs(calls) do
        if c[1] == "ComboBox" and c[2] == "Depth for post-processing effects" then combo = i end
    end
    -- choice_combo adds its choices to the combo returned by ComboBox (the recording stand-in): count the help line
    for _, c in ipairs(calls) do
        if c[1] == "ControlHelp" and string.find(tostring(c[2]), "depth image", 1, true) then choices = choices + 1 end
    end
    check(page ~= nil and built and combo and choices == 1, "Options > G-SA1 > Rendering: \"Depth for post-processing "
        .. "effects\" (gsa1_depthfix)%s", built and "" or (": " .. tostring(err)))
    E.frame(VIEWS_A)
    local line = GSA1.RenderLine(C)
    check(string.find(line, "views: main 1, depth pass 1, shadow depth 1, water 1, depth after the opaque pass 0", 1, true)
        ~= nil, "the debug line: %s", line)
end
finish(M)

-- 3. 0.9.5: the board's batches; GSA1.DrawCharacterView --------------------------------------------------------------------
host_write("\n-- 0.9.5: the board's batches, GSA1.DrawCharacterView\n")
do
    local E3 = world("board")
    local M3 = E3.M
    local check3 = M3.check
    if not (E3.C and E3.ent) then
        check3(false, "the addon loads and Sonic spawns%s", E3.loadError and (": " .. E3.loadError) or "")
    else
        local C = E3.C
        local MAIN = { { name = "main", viewid = V_MAIN } }
        local function main_batches()
            local out = E3.frame(MAIN)
            return sorted_batches(out.main)
        end
        -- one extra view right after this frame's main view, recorded like a view (the recorders' sink)
        local function view_batches(v)
            E3.late = E3.newView("extra")
            local ok, why = GSA1.DrawCharacterView(C, v)
            local rec = E3.late
            E3.late = nil
            return sorted_batches(rec), ok, why, rec
        end
        local VIEW = { eye = Vector(C.drawPos.x + 46, C.drawPos.y, C.drawPos.z + 31), ang = Angle(0, 180, 0), fov = 30,
                       x = 0, y = 0, w = 256, h = 192, znear = 4, zfar = 400 }
        local cv = GSA1.cv
        E3.frame(MAIN)
        -- (a) third person: everything; Effects off: the board stays (it is EFFECT too); Shadows off: the board's shadow
        -- batch goes with the blob; gsa1_set_draw 0: the board stays, the object goes
        local tp = main_batches()
        local tpView, okv, why = view_batches(VIEW)
        cv.effects:SetString("0")
        local fx0 = main_batches()
        local fx0View = view_batches(VIEW)
        cv.effects:SetString("1")
        cv.shadow:SetString("0")
        local sh0 = main_batches()
        local sh0View = view_batches(VIEW)
        cv.shadow:SetString("1")
        RunConsoleCommand("gsa1_set_draw", "0")
        local obj0 = main_batches()
        local obj0View = view_batches(VIEW)
        RunConsoleCommand("gsa1_set_draw", "1")
        check3(tp == "1 2 3 4 5 6 7" and fx0 == "1 2 4 5 6" and sh0 == "1 2 3 6 7" and obj0 == "1 2 3 4 5 7",
            "third person: all \"%s\"; Effects off \"%s\" (the board stays); Shadows off \"%s\" (the board's shadow "
            .. "batch goes with the blob); gsa1_set_draw 0 \"%s\" (the board stays)", tp, fx0, sh0, obj0)
        check3(okv == true and tpView == tp and fx0View == fx0 and sh0View == sh0 and obj0View == obj0,
            "GSA1.DrawCharacterView draws exactly the batches of one colour view, both passes, under every switch "
            .. "(\"%s\", \"%s\", \"%s\", \"%s\"; %s)", tpView, fx0View, sh0View, obj0View, tostring(why or "drawn"))
        -- (b) the hidden batches stay hidden in the extra view too
        E3.frame(MAIN)
        C.hidden = C.hidden or {}
        C.hidden[3] = true
        local hid = view_batches(VIEW)
        C.hidden[3] = nil
        check3(hid == "1 2 4 5 6 7", "a hidden batch is not drawn in the extra view either (\"%s\")", hid)
        -- (c) never in a frame the main view did not draw
        M3.frameNo = M3.frameNo + 1
        local nd, okn, whyn = view_batches(VIEW)
        check3(okn == false and whyn == "not drawn this frame" and nd == "", "a frame the main view did not draw: "
            .. "nothing (%s, \"%s\")", tostring(okn), tostring(whyn))
        -- (d) its own kind in the views line, never "main"; the camera-relative eye; the filter and one material
        E3.frame(MAIN)
        local _, _, _, rec = view_batches(VIEW)
        local line = GSA1.ViewsLine()
        local O = C.relOrigin
        local relOk = rec.relEye ~= nil and (O == nil or (math.abs(rec.relEye.x - (VIEW.eye.x - O.x)) < 1e-6 and
            math.abs(rec.relEye.z - (VIEW.eye.z - O.z)) < 1e-6))
        check3(string.find(line, "main 1,", 1, true) ~= nil and string.find(line, "the Faces page's close-up 1", 1, true)
            ~= nil and relOk, "counted as its own view (\"%s\"), not as main; its eye camera-relative (%s)", line,
            O and "relative" or "absolute")
        E3.frame(MAIN)
        local flat = CreateMaterial("test_flat", "UnlitGeneric", {})
        local fv = { eye = VIEW.eye, ang = VIEW.ang, ortho = { left = -48, right = 48, top = -48, bottom = 48 }, x = 0,
                     y = 0, w = 256, h = 256, znear = 1, zfar = 400, opaque = true, material = flat, kind = "sunshadow",
                     hitch = false, filter = function(b) return b.pass == 0 and bit.band(b.flags, 0x1000) == 0 end }
        local starts0 = #M3.camStarts
        local fb, okf, _, recf = view_batches(fv)
        local onlyFlat = #recf.mats > 0
        for _, m in ipairs(recf.mats) do if m ~= flat then onlyFlat = false end end
        local cs = M3.camStarts[#M3.camStarts]
        check3(okf and fb == "1 2 7" and onlyFlat and #M3.camStarts == starts0 + 1 and cs and cs.ortho == fv.ortho and
            string.find(GSA1.ViewsLine(), "sun shadow 1", 1, true) ~= nil, "an orthographic extra view (cam.Start with "
            .. "the ortho box) with a filter and one material for every batch: \"%s\", %d materials all the given one: %s",
            fb, #recf.mats, tostring(onlyFlat))
        -- (e) first person: the board (and the object), never the body; Effects off: the board stays; Shadows off: its
        -- shadow batch goes; gsa1_set_draw 0: the board stays (review R.10)
        local dist = cv.cam_dist:GetString()
        cv.cam_dist:SetString("0")
        local fp = main_batches()
        cv.effects:SetString("0")
        local fpfx0 = main_batches()
        cv.effects:SetString("1")
        cv.shadow:SetString("0")
        local fpsh0 = main_batches()
        cv.shadow:SetString("1")
        RunConsoleCommand("gsa1_set_draw", "0")
        local fpobj0 = main_batches()
        RunConsoleCommand("gsa1_set_draw", "1")
        cv.cam_dist:SetString(dist)
        check3(fp == "2 5 6" and fpfx0 == "2 5 6" and fpsh0 == "2 6" and fpobj0 == "2 5", "first person: the board and "
            .. "the object only \"%s\"; Effects off \"%s\"; Shadows off \"%s\"; gsa1_set_draw 0 \"%s\" (the board stays: "
            .. "review R.10)", fp, fpfx0, fpsh0, fpobj0)
        check3((C.boardBatches or 0) == 2, "C.boardBatches counts the board's batches (%s)", tostring(C.boardBatches))
        -- (f) the depth pass in first person with only the board: drawn there too (the board is part of the character)
        cv.cam_dist:SetString("0")
        RunConsoleCommand("gsa1_set_draw", "0")
        local VD = { { name = "ssao", viewid = V_SSAO, rt = "_rt_ResolvedFullFrameDepth", flags = F_RENDER + F_SSAO,
                       depth = true }, { name = "main", viewid = V_MAIN } }
        local D = E3.frame(VD)
        RunConsoleCommand("gsa1_set_draw", "1")
        cv.cam_dist:SetString(dist)
        check3(sorted_batches(D.ssao) == "2", "first person, gsa1_set_draw 0: the depth pass draws the board (\"%s\")",
            sorted_batches(D.ssao))
        -- (g) the draw list names the bit
        check3(GSA1.DrawFlagText(0x40C0) == "EFFECT|NOTEX|BOARD", "the draw list's flag names: %s",
            GSA1.DrawFlagText(0x40C0))
    end
    finish(M3)
end

print(string.format("\n%d checks, %d failed", TOTAL, FAILED))
return FAILED == 0
