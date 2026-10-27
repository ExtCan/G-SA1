-- G-SA1 client: drawing a character.
--
-- One clientside entity (gsa1_render) per character. Every frame the module renders what the game drew
-- (libsa1's sa1_character_render: the draws of the last 30 Hz pair interpolated towards the next, so animation
-- and movement are smooth at any frame rate) and sorts the draws into batches by render state. Opaque batches
-- are drawn in ENT:Draw with depth writes; blended ones (Tails' fading tail copies, additive effects) in
-- ENT:DrawTranslucent after them, in the game's order, with the game's blend factors (render.OverrideBlend).
-- The module streams each batch's vertices straight into GMod's mesh builder (gsa1.EmitBatch): a dynamic mesh
-- per batch per frame while interpolating, one static IMesh per batch per game pair with gsa1_interpolate 0.
-- Lighting: an ambient cube sampled from the map's lighting.
-- 0.6.0 (round 4c): PrepareView gets the lighting setting (the module then leaves out mesh.Normal for unlit materials
-- and mesh.TexCoord for untextured ones: E1) and the screen (the module measures how much of it the blended batches
-- cover: E5, for the session log); the material pre-warm (cl_warm.lua) draws in both passes, also in first person;
-- Lua errors in the draws go into the session log (GSA1.Guard).
--
-- 0.8 (the owner's test of 0.6.0; sadc docs/research/gsa1_060_shadow.md G1-G6 and gsa1_060_render.md with their reviews):
--   * Shadows. libsa1 draws the game's own blob shadow (SA1_DRAW_SHADOW: where the game's shadow code put it - on the
--     ground it found under the character, tilted to that ground, shrunk with height, gone high above the ground). Its
--     batches are drawn when gsa1_shadow is 1 (Q menu > Options > G-SA1 > Rendering), whatever gsa1_effects says (they
--     carry SA1_DRAW_EFFECT too: the test comes before the effects test), not in first person (like the body). A mask
--     batch (address mode WRAP_MASK: the black "shadow" texture) is drawn with ZERO / ONE_MINUS_SRC_COLOR (cl_textures.lua
--     T.BlendOf) under a tone-mapping scale of 1 (an HDR map's exposure would scale the darkening; restored afterwards).
--   * Camera-relative drawing (gsa1_relative, module feature "render"). 0.7 handed Garry's Mod absolute positions; far
--     from the map's centre (the owner's gm_bigcity run at x ~ 5400, y ~ 3900-11750) the GPU's float32 vertex transform
--     rounds them by about 0.001 units - more than the 0.016-0.04 units between Big's (and Tails', Sonic's) eye layers -
--     so the eyes z-fought even with Big standing still. Now the module writes every position minus the character's
--     drawn root (subtracted in double) and the batches are drawn under cam.Start3D(EyePos() - root, EyeAngles()): the
--     same picture, computed on small numbers. Off (or a module without the feature, or the eye under water, where
--     Source's water fog uses absolute heights): absolute positions as in 0.7. UNVERIFIED in game: that cam.Start3D
--     inside ENT:Draw keeps the view's projection, viewport and depth buffer (gsa1_relative 0 is the way back).
--   * gsa1_logdraws: one frame's draw list (gsa1.DrawList) into the session log, for reports such as "Tails'
--     motion-blur tails don't disappear when spinning" (gsa1_060_render.md 4.5); with gsa1_debug a summary line on screen.
--
-- 0.9.1 (sadc docs/research/gsa1_070_translucency.md T1 with its review R3.3): the game's see-through copies are drawn
-- see-through with the lighting on (their alpha is the material's: cl_textures.lua). A lit see-through batch of alpha 0
-- drawn SRC_ALPHA with ONE_MINUS_SRC_ALPHA or ONE changes nothing on screen - Knuckles' top-speed copies: the game scales
-- their fade wrongly (-85.3 for -1/3), so their see-through parts get alpha 0 and vanish, as on the Dreamcast - and is not
-- drawn (draw calls saved). With other blend factors an alpha-0 draw still writes, so those are drawn.
--
-- 0.9.2 (the owner's 0.9.0 report: a sun-shaft effect washed over Sonic's top half; the characters could not be seen through
-- the top of water; sadc docs/research/gsa1_090_render.md R1, R2, R2b, D1 with its review RC1-RC4):
--   * Source draws the character in several VIEWS per frame, not only on the screen: the depth pass (VIEW_SSAO into
--     _rt_ResolvedFullFrameDepth, made every frame once an addon asks for it - GShader - and read by sun shafts, depth of
--     field, bokeh, SSAO-like effects), a lamp's or flashlight's shadow depth (VIEW_SHADOW_DEPTH_TEXTURE), and above
--     expensive water the water's refraction and reflection. view_kind tells them apart in this order (review RC1): the
--     STUDIO flags of ENT:Draw / DrawTranslucent; the render target - none (the screen) is always the main view, so a
--     stale or player view id can never turn the on-screen draw into a depth draw -; the render target's name; inside a
--     depth pass (PreDrawOpaqueRenderables' isDrawingDepth) a depth view; only then render.GetViewSetup(true).viewid.
--   * Depth views (R1): the blended pass draws nothing; the opaque pass draws exactly the batches the colour pass would
--     draw (gsa1_effects, gsa1_shadow, the batches not drawn, first person; RC2) with DepthWrite materials (cl_textures.lua
--     T.DepthMaterial: $color_depth 1 in the depth pass, 0 in shadow depth). 0.9.0 / 0.9.1 drew the colour materials there
--     under a nested cam.Start3D and the character was MISSING from the depth image (depth effects took him for the sky
--     behind him: the one-row cut of the owner's screenshot).
--   * Every view but the main one draws at WORLD positions (R2): the camera-relative vertices go through a model matrix
--     translated by the frame's origin (cam.PushModelMatrix), never cam.Start3D, so Source's own view stays untouched - the
--     water's clip plane and fog work on world heights (0.9.0 clipped the submerged body away above low water and fogged
--     it too much above high water), the depth and shadow targets stay bound. Only the main view (and monitors, mirrors:
--     any other render target) keeps 0.8's camera-relative cam.Start3D.
--   * The frame's camera-relative decision and PrepareView (the sprites face the camera, the coverage figure) use the MAIN
--     view's eye - CalcView's (GSA1.view) - whichever view draws the character first (R2b; 0.9.0 took the water
--     reflection's mirrored eye when the reflection came first).
--   * gsa1_depthfix (Options > G-SA1 > Rendering, "Depth for post-processing effects"): 0 off (the depth views drawn as
--     0.9.1 drew them), 1 the depth views as above (default), 2 also, in the main view's PostDrawOpaqueRenderables after a
--     depth pass ran this frame, the opaque batches drawn once more into render.GetResolvedFullFrameDepth() with the
--     $color_depth 1 DepthWrite at world positions (R1b, review RC4: the fallback in case the depth view's own draw does
--     not land), with the depth range pulled in by LATE_DEPTH_RANGE so it passes the depth test against the character's
--     own camera-relative colour pass (the two transforms round differently). Both UNVERIFIED in game.
--   * GSA1.ViewInfo() (D1): the last character draw's view {viewid, flags, kind, rt, shader, pass, frame} for the
--     session log's "views" line; GSA1.ViewInfo(true, flags) describes the view being drawn now (call it inside a draw).
--
-- 0.9.4 (sadc docs/research/gsa1_094_plan.md 6.5 task 6 with its review R.1): the game's objects - rings, a ring's sparkle
-- and blob shadow, item boxes (libsa1's SA1_DRAW_OBJECT, its own batches since the module's batch key has the bit) - are
-- drawn by the Objects page's switch (gsa1_set_draw), whatever gsa1_effects says (tested before the effects test, like
-- the shadow; an object's blob shadow also follows gsa1_shadow), and IN FIRST PERSON TOO: there DrawCharacter draws only
-- the OBJECT batches (the character's own stay hidden), in the colour pass and the depth views alike.
GSA1 = GSA1 or {}

local band = bit.band
local DRAW_EFFECT, DRAW_SHADOW, DRAW_AFTERIMAGE, WRAP_MASK = 0x40, 0x800, 0x100, 8
local DRAW_OBJECT = 0x1000
local NONE = {}
local CONTENTS_WATER_ = CONTENTS_WATER or 0x20

-- 0.9.2: Source's views (see the top). GMod's globals, with the numeric values as fallbacks
local SSAO_FLAG = STUDIO_SSAODEPTHTEXTURE or 134217728
local SHADOWDEPTH_FLAG = STUDIO_SHADOWDEPTHTEXTURE or 1073741824
-- VIEW_REFLECTION 3, VIEW_REFRACTION 4, VIEW_SHADOW_DEPTH_TEXTURE 7, VIEW_SSAO 8
local VIEW_KINDS = { [3] = "water", [4] = "water", [7] = "shadowdepth", [8] = "ssao" }
-- render target names (lower case); _rt_shadowdummy: SDK 2013's shadow-depth colour target (UNVERIFIED in GMod)
local RT_KINDS = { _rt_waterrefraction = "water", _rt_waterreflection = "water", _rt_resolvedfullframedepth = "ssao",
                   _rt_shadowdummy = "shadowdepth" }
local DEPTH_KINDS = { ssao = true, shadowdepth = true }
local LATE_DEPTH_RANGE = 0.99999    -- R1b: z x 0.99999 (about 0.03 units nearer at 150 units, 1.4 at 1,000)

local ENT = {}
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "G-SA1 character"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:Initialize()
    self:SetRenderBounds(Vector(-640, -640, -320), Vector(640, 640, 640))
    self:DrawShadow(false)          -- Source's own shadow: the game's blob is drawn instead (gsa1_shadow)
end

local function free_static(C)
    for _, sm in pairs(C.static or {}) do
        if sm.imesh then sm.imesh:Destroy() end
    end
    C.static = {}
end
GSA1.FreeStaticMeshes = free_static

function ENT:OnRemove()
    if self.char then free_static(self.char) end
end

-- the ambient cube (BOX_FRONT +X, BOX_BACK -X, BOX_RIGHT -Y, BOX_LEFT +Y, BOX_TOP +Z, BOX_BOTTOM -Z)
local BOX_DIRS = {
    [0] = Vector(1, 0, 0), [1] = Vector(-1, 0, 0), [2] = Vector(0, -1, 0),
    [3] = Vector(0, 1, 0), [4] = Vector(0, 0, 1), [5] = Vector(0, 0, -1),
}

-- sampled once per rendered frame
local function update_lighting(C)
    if C.lightFrame == FrameNumber() then return end
    C.lightFrame = FrameNumber()
    C.lightOrigin = C.lightOrigin or Vector()
    C.lightOrigin:Set(C.drawPos)
    C.lightOrigin.z = C.lightOrigin.z + (C.info.center or 20)
    C.light = C.light or {}
    for i = 0, 5 do
        C.light[i] = render.ComputeLighting(C.lightOrigin, BOX_DIRS[i])
    end
end

-- 0.9.4b (sadc docs/research/objects2_plan.md 6.3 task 3, review R.8): the character's lighting and static-mesh pattern
-- as helpers for the pictures of the real objects (feat/cl_objview.lua), which sample the ambient cube per ENTITY (when it
-- is placed or moved, a few a frame) instead of per frame; nothing above or below changes
-- the ambient cube of a point: out[0..5] (BOX_FRONT .. BOX_BOTTOM), 6 render.ComputeLighting samples
function GSA1.LightCube(origin, out)
    out = out or {}
    for i = 0, 5 do
        out[i] = render.ComputeLighting(origin, BOX_DIRS[i])
    end
    return out
end

-- the model lighting of such a cube for the draws that follow (VertexLitGeneric); GSA1.EndLightCube() after them
function GSA1.ApplyLightCube(origin, light)
    render.SuppressEngineLighting(true)
    render.SetLightingOrigin(origin)
    render.ResetModelLighting(0, 0, 0)
    for i = 0, 5 do
        local l = light[i]
        if l then render.SetModelLighting(i, l.x, l.y, l.z) end
    end
    render.SetLocalModelLights()
end

function GSA1.EndLightCube()
    render.SuppressEngineLighting(false)
end

-- one static IMesh of tris triangles in material mat, its vertices streamed by emit() (gsa1.EmitBatch /
-- gsa1.PreviewEmitBatch): what draw_batches builds once per game pair with gsa1_interpolate 0
function GSA1.StaticMesh(mat, tris, emit)
    local im = Mesh(mat)
    mesh.Begin(im, MATERIAL_TRIANGLES, tris)
    local ok, err = pcall(emit)
    mesh.End()
    if not ok then
        im:Destroy()
        error(err, 0)
    end
    return im
end

local cv_fov = GetConVar("fov_desired")
local TONE_ONE = Vector(1, 1, 1)

local function emit(C, i)
    local n, err = gsa1.EmitBatch(C.id, i)
    if not n and not C.emitError then
        C.emitError = true
        GSA1.Msg("drawing batch %d of %s: %s", i, C.title, tostring(err))
    end
end

-- 0.9.2 (R1 / R2, review RC1): which of Source's views is drawing now: "main", "ssao" (the depth pass), "shadowdepth"
-- (a lamp's or flashlight's shadow depth), "water" (refraction, reflection); also the render target's name (nil: the
-- screen) and the view id when it was looked up. Order: the STUDIO flags, the render target (none = the screen = main),
-- its name, a depth pass bracket (PreDrawOpaqueRenderables' isDrawingDepth), the current view setup's viewid.
local kindOfName = {}           -- [render target name] = kind or false (memoised: no new string per draw)
local depthStack, depthTop = {}, 0      -- PreDrawOpaqueRenderables ... PostDrawOpaqueRenderables: isDrawingDepth
local lastLook = { frame = -1, name = nil, kind = nil, id = nil }      -- the view id lookup, once per target and frame
local function view_kind(flags)
    local rt = render.GetRenderTarget and render.GetRenderTarget()
    local name = rt and rt:GetName() or nil
    if flags then
        if band(flags, SSAO_FLAG) ~= 0 then return "ssao", name end
        if band(flags, SHADOWDEPTH_FLAG) ~= 0 then return "shadowdepth", name end
    end
    if not rt then return "main" end
    name = name or ""
    local k = kindOfName[name]
    if k == nil then
        k = RT_KINDS[string.lower(name)] or false
        kindOfName[name] = k
    end
    if k then return k, name end
    local fn = FrameNumber()
    local depthPass = depthTop > 0 and depthStack[depthTop] or false
    if lastLook.frame == fn and lastLook.name == name and lastLook.depth == depthPass then
        return lastLook.kind, name, lastLook.id
    end
    local vs = render.GetViewSetup and render.GetViewSetup(true)
    local id = type(vs) == "table" and vs.viewid or nil
    if depthPass then
        k = id == 7 and "shadowdepth" or "ssao"         -- a depth pass into a target of another name
    else
        k = (id and VIEW_KINDS[id]) or "main"
    end
    lastLook.frame, lastLook.name, lastLook.depth, lastLook.kind, lastLook.id = fn, name, depthPass, k, id
    return k, name, id
end
GSA1.ViewKind = view_kind

-- R2b: the main view's eye this frame (CalcView's, cl_character.lua), whichever view draws first
local function main_eye()
    local v = GSA1.view
    if v and v.frame == FrameNumber() and v.origin and v.angles then return v.origin, v.angles end
    return EyePos(), EyeAngles()
end
GSA1.MainEye = main_eye

-- 0.9.4d: an angle's axes written into the Vectors given (Source's AngleVectors: what Angle:Forward / Right / Up return,
-- without a new Vector each - Lua garbage every frame, tests/frame_test.lua); fwd, right or up may be nil
function GSA1.AngleAxes(ang, fwd, right, up)
    local p, y, r = math.rad(ang.p), math.rad(ang.y), math.rad(ang.r)
    local sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    if fwd then fwd:SetUnpacked(cp * cy, cp * sy, -sp) end
    if right then right:SetUnpacked(-sr * sp * cy + cr * sy, -sr * sp * sy - cr * cy, -sr * cp) end
    if up then up:SetUnpacked(cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp) end
end

-- camera-relative drawing this frame: the setting, a module that writes relative positions, the main view's eye not
-- under water
local function relative_wanted()
    local cv = GSA1.cv.relative
    if not (cv and cv:GetBool() and GSA1.HasFeature and GSA1.HasFeature("render", 1)) then return false end
    if util.PointContents and band(util.PointContents((main_eye())), CONTENTS_WATER_) ~= 0 then return false end
    return true
end

-- the colour pass draws a batch (its pass, triangles and C.hidden aside): a game object by the Objects page's switch
-- (0.9.4: before the shadow and effects tests - it is EFFECT too; its blob shadow also by gsa1_shadow), the shadow by its
-- own switch (before the effects test: it is EFFECT too), effects by gsa1_effects; in first person only the objects. The
-- depth views use the same test (review RC2)
local function batch_on(f, effects, shadows, objects, first_person)
    if band(f, DRAW_OBJECT) ~= 0 then
        return objects and (shadows or band(f, DRAW_SHADOW) == 0)
    end
    if first_person then return false end
    if band(f, DRAW_SHADOW) ~= 0 then return shadows end
    return effects or band(f, DRAW_EFFECT) == 0
end
GSA1.BatchOn = batch_on

-- the Objects page's switch (feat/cl_objects.lua; on without that feature)
local function objects_on()
    local c = GSA1.cv and GSA1.cv.set_draw
    return not c or c:GetBool()
end

-- this draw's view (GSA1.ViewInfo) and the views per frame (the debug line)
local VI = { frame = -1 }
local VT = { frame = -1, cur = { main = 0, ssao = 0, shadowdepth = 0, water = 0, late = 0 },
             last = { main = 0, ssao = 0, shadowdepth = 0, water = 0, late = 0 } }
local function tally(kind)
    local fn = FrameNumber()
    if VT.frame ~= fn then
        VT.frame = fn
        VT.cur, VT.last = VT.last, VT.cur
        local c = VT.cur
        c.main, c.ssao, c.shadowdepth, c.water, c.late = 0, 0, 0, 0, 0
    end
    VT.cur[kind] = (VT.cur[kind] or 0) + 1
end
local depthRan, lateDone = -1, -1       -- the frame of the last depth pass that drew the character, of the last R1b

-- the batches of one pass (inside the relative view when there is one); main: the main view (the pre-warm steps there)
local function draw_batches(C, pass, first_person, te, main)
    local B = C.batches
    local cv = GSA1.cv
    if C.matsDirty then GSA1.ResolveMaterials(C) end
    local lit = cv.lighting:GetBool()
    if lit then
        update_lighting(C)
        render.SuppressEngineLighting(true)
        render.SetLightingOrigin(C.lightOrigin)
        render.ResetModelLighting(0, 0, 0)
        for i = 0, 5 do
            local l = C.light[i]
            render.SetModelLighting(i, l.x, l.y, l.z)
        end
        render.SetLocalModelLights()
    end
    local effects = cv.effects:GetBool()
    local shadows = not cv.shadow or cv.shadow:GetBool()
    local objects = objects_on()
    local static = not C.interp
    local tex = GSA1.Tex
    -- the material pre-warm: a few of the character's materials drawn once in this pass (invisible), in the main view
    if GSA1.Warm and main then
        local tw = SysTime()
        GSA1.Warm.Step(C, pass)
        te = te + (SysTime() - tw)      -- (timed as "Warm", not as "EmitBatch")
    end
    local O = C.relOrigin
    local ox, oy, oz = 0, 0, 0
    if O then ox, oy, oz = O.x, O.y, O.z end
    local hidden = C.hidden or NONE
    -- (0.9.4, review R.1: in first person only the game's objects; 0.9.3a drew nothing there)
    for i = 1, ((first_person and (C.objectBatches or 0) == 0) and 0 or B.count) do
        local b = B[i]
        if b and b.pass == pass and b.tris > 0 and not hidden[i] then
            if batch_on(b.flags, effects, shadows, objects, first_person) then
                local mat = C.mats[i]
                render.SetMaterial(mat)
                if not VI.mat then VI.mat = mat end
                local tone = nil
                if pass == 1 then
                    local s, d = tex.BlendOf(b)
                    render.OverrideBlend(true, s, d, BLENDFUNC_ADD)
                    if band(b.wrap or 0, WRAP_MASK) ~= 0 and render.GetToneMappingScaleLinear then
                        tone = render.GetToneMappingScaleLinear()
                        if tone then render.SetToneMappingScaleLinear(TONE_ONE) end
                    end
                end
                if static then
                    local sm = C.static[i]
                    if not sm or sm.gen ~= C.renderGen or sm.mat ~= mat or sm.tris ~= b.tris or sm.ox ~= ox or
                       sm.oy ~= oy or sm.oz ~= oz then
                        if sm and sm.imesh then sm.imesh:Destroy() end
                        local im = Mesh(mat)
                        mesh.Begin(im, MATERIAL_TRIANGLES, b.tris)
                        emit(C, i)
                        mesh.End()
                        sm = { imesh = im, gen = C.renderGen, mat = mat, tris = b.tris, ox = ox, oy = oy, oz = oz }
                        C.static[i] = sm
                    end
                    sm.imesh:Draw()
                else
                    mesh.Begin(MATERIAL_TRIANGLES, b.tris)
                    emit(C, i)
                    mesh.End()
                end
                if tone then render.SetToneMappingScaleLinear(tone) end
                if pass == 1 then
                    render.OverrideBlend(false)
                end
            end
        end
    end
    if lit then
        render.SuppressEngineLighting(false)
    end
    return te
end

-- R1 (review RC2): the opaque batches into a depth view - exactly the ones the colour pass draws (pass 0, triangles, not
-- hidden, gsa1_effects / gsa1_shadow, in first person only the game's objects: 0.9.4) - with DepthWrite materials (color:
-- $color_depth 1, the depth pass); a static mesh (gsa1_interpolate 0) of this pair and origin is drawn again under the
-- depth material, else the batch is streamed (the depth pass comes before the screen, which rebuilds the static meshes of
-- a new pair)
local function draw_depth(C, color, first_person, te)
    if first_person and (C.objectBatches or 0) == 0 then return te end
    local B = C.batches
    if C.matsDirty then GSA1.ResolveMaterials(C) end
    local cv = GSA1.cv
    local effects = cv.effects:GetBool()
    local shadows = not cv.shadow or cv.shadow:GetBool()
    local objects = objects_on()
    local static = not C.interp
    local depthMaterial = GSA1.Tex.DepthMaterial
    local O = C.relOrigin
    local ox, oy, oz = 0, 0, 0
    if O then ox, oy, oz = O.x, O.y, O.z end
    local hidden = C.hidden or NONE
    for i = 1, B.count do
        local b = B[i]
        if b and b.pass == 0 and b.tris > 0 and not hidden[i] and batch_on(b.flags, effects, shadows, objects, first_person) then
            local mat = depthMaterial(C.kind, b, color)
            render.SetMaterial(mat)
            if not VI.mat then VI.mat = mat end
            local sm = static and C.static and C.static[i]
            if sm and sm.imesh and sm.gen == C.renderGen and sm.tris == b.tris and sm.ox == ox and sm.oy == oy and
               sm.oz == oz then
                sm.imesh:Draw()
            else
                mesh.Begin(MATERIAL_TRIANGLES, b.tris)
                emit(C, i)
                mesh.End()
            end
        end
    end
    return te
end

-- pass 0: opaque batches, 1: blended batches (in the game's order); flags: the STUDIO flags of ENT:Draw /
-- ENT:DrawTranslucent (0.9.2: they say which of Source's views is drawing)
function GSA1.DrawCharacter(C, pass, flags)
    local B = C and C.batches
    if not B or (B.count or 0) == 0 or not C.drawPos then return end
    local first_person = GSA1.FirstPerson and GSA1.FirstPerson()
    -- first person: the game's objects only (0.9.4, review R.1), or the pre-warm while it runs (the OBJECT batches
    -- counted once per batch structure; ResolveMaterials counts them too)
    if first_person and C.objectGen ~= C.batchGen then
        local n = 0
        for i = 1, B.count do
            local b = B[i]
            if b and band(b.flags or 0, DRAW_OBJECT) ~= 0 then n = n + 1 end
        end
        C.objectBatches, C.objectGen = n, C.batchGen
    end
    local fp_objects = first_person and (C.objectBatches or 0) > 0 and objects_on()
    if first_person and not fp_objects and not (GSA1.Warm and GSA1.Warm.total and not GSA1.Warm.total.done) then return end
    local cv = GSA1.cv
    local t0 = SysTime()
    local fn = FrameNumber()
    -- the view: depth views (gsa1_depthfix 1 / 2) get the DepthWrite draw; with gsa1_depthfix 0 they are drawn as 0.9.1
    -- drew them (as the main view)
    local kind, rtname, viewid = view_kind(flags)
    local depthKind = DEPTH_KINDS[kind] or false
    local depth = depthKind and (not cv.depthfix or cv.depthfix:GetInt() >= 1)
    VI.frame, VI.pass, VI.flags, VI.kind, VI.rt, VI.viewid, VI.depth, VI.mat = fn, pass, flags, kind, rtname, viewid,
        depth, nil
    if pass == 0 then tally(kind) end
    if depth and kind == "ssao" then depthRan = fn end
    if depth and pass ~= 0 then return end
    -- the frame's origin of camera-relative drawing: the drawn root (constant within a game pair with
    -- gsa1_interpolate 0, so the static meshes stay valid); decided with the main view's eye (R2b)
    if C.relFrame ~= fn then
        C.relFrame = fn
        C.relOrigin = nil
        if relative_wanted() then
            C.relO = C.relO or Vector()
            C.relO:Set(C.drawPos)
            C.relOrigin = C.relO
        end
    end
    if C.viewFrame ~= fn and (not first_person or fp_objects) then
        C.viewFrame = fn
        C.drawMs, C.drawMsFrame = C.drawMsNext or 0, nil
        C.drawMsNext = 0
        -- R2b: the main view's eye, whichever view comes first (the water reflection's is mirrored under the water)
        local eye, ang = main_eye()
        local tv = SysTime()
        -- the screen for the coverage figure: CalcView's field of view (cl_character.lua) of this frame, else the
        -- player's setting
        local v = GSA1.view
        local fov = (v and v.frame and fn - v.frame <= 2 and v.fov) or (cv_fov and cv_fov:GetFloat()) or 75
        -- (0.9.4d: the axes into the character's own Vectors, not two new ones a frame)
        C.viewR, C.viewU = C.viewR or Vector(), C.viewU or Vector()
        GSA1.AngleAxes(ang, nil, C.viewR, C.viewU)
        gsa1.PrepareView(C.id, eye, C.viewR, C.viewU, cv.flip:GetBool(), cv.vcolor:GetBool(),
            cv.line_width:GetFloat(), cv.lighting:GetBool(), fov, ScrW(), ScrH(), C.relOrigin)
        if GSA1.HitchAdd then GSA1.HitchAdd("PrepareView", SysTime() - tv) end
    end
    local te = SysTime()
    -- the main view (and 0.9.1's way for depth views with gsa1_depthfix 0): camera-relative under cam.Start3D; every
    -- other view (depth, water): world positions through a model matrix (R2), so Source's view stays as it is
    local push = nil
    local O = C.relOrigin
    if O then
        if kind == "main" or not depth and depthKind or not (cam.PushModelMatrix and Matrix) then
            C.relEye = C.relEye or Vector()
            C.relEye:Set(EyePos())
            C.relEye:Sub(O)
            cam.Start3D(C.relEye, EyeAngles())
            push = "3d"
        else
            C.relM = C.relM or Matrix()
            C.relM:Identity()
            C.relM:SetTranslation(O)
            cam.PushModelMatrix(C.relM)
            push = "model"
        end
    end
    local ok, res
    if depth then
        ok, res = pcall(draw_depth, C, kind == "ssao", first_person, te)
    else
        ok, res = pcall(draw_batches, C, pass, first_person, te, kind == "main")
    end
    if push == "3d" then cam.End3D() elseif push == "model" then cam.PopModelMatrix() end
    if not ok then error(res, 0) end
    te = res
    if GSA1.HitchAdd then GSA1.HitchAdd("EmitBatch", SysTime() - te) end
    C.drawMsNext = (C.drawMsNext or 0) + (SysTime() - t0) * 1000
end

-- R1b (gsa1_depthfix 2, review RC4): after the main view's opaque renderables, when a depth pass drew the character this
-- frame, its opaque batches once more into the depth pass's texture (render.GetResolvedFullFrameDepth) with the
-- $color_depth 1 DepthWrite at world positions - before GShader's reconstruction (PreDrawTranslucentRenderables) and the
-- screen-space effects read it. The main view's own depth buffer stays bound (UNVERIFIED): the depth range pulled in by
-- LATE_DEPTH_RANGE keeps the draw from failing the depth test against the character's own colour pass, which was drawn
-- camera-relative and rounds differently.
local function draw_depth_late(C)
    local tex = render.GetResolvedFullFrameDepth and render.GetResolvedFullFrameDepth()
    if not tex then return end
    local first_person = GSA1.FirstPerson and GSA1.FirstPerson() or false
    if first_person and (C.objectBatches or 0) == 0 then return end
    local t0 = SysTime()
    render.PushRenderTarget(tex)
    local O = C.relOrigin
    local model = false
    if O and cam.PushModelMatrix and Matrix then
        C.relM = C.relM or Matrix()
        C.relM:Identity()
        C.relM:SetTranslation(O)
        cam.PushModelMatrix(C.relM)
        model = true
    end
    local ranged = render.DepthRange ~= nil
    if ranged then render.DepthRange(0, LATE_DEPTH_RANGE) end
    tally("late")
    local ok, err = pcall(draw_depth, C, true, first_person, 0)
    if ranged then render.DepthRange(0, 1) end
    if model then cam.PopModelMatrix() end
    render.PopRenderTarget()
    if not ok then error(err, 0) end
    C.drawMsNext = (C.drawMsNext or 0) + (SysTime() - t0) * 1000
end
GSA1.DrawCharacterDepthLate = draw_depth_late

-- the depth pass bracket (view_kind): GMod calls PreDrawOpaqueRenderables(isDrawingDepth, isDrawSkybox, isDraw3DSkybox)
-- before a view's opaque renderables and PostDrawOpaqueRenderables after them; nested views keep their own entry, and
-- the stack starts empty every frame (PreRender) in case another addon's hook stopped one of ours
hook.Add("PreRender", "gsa1_views", function()
    for i = depthTop, 1, -1 do depthStack[i] = nil end
    depthTop = 0
end)
hook.Add("PreDrawOpaqueRenderables", "gsa1_views", function(isDrawingDepth, isDrawSkybox, isDraw3DSkybox)
    if depthTop < 16 then
        depthTop = depthTop + 1
        depthStack[depthTop] = isDrawingDepth and true or false
    end
    -- the depth pass of this frame (R1b) also when the character's own draw there is not seen
    if isDrawingDepth and render.GetRenderTarget then
        local rt = render.GetRenderTarget()
        local name = rt and rt:GetName()
        if name and RT_KINDS[string.lower(name)] == "ssao" then depthRan = FrameNumber() end
    end
end)
local late = GSA1.Guard and GSA1.Guard("DepthLate", draw_depth_late) or draw_depth_late
hook.Add("PostDrawOpaqueRenderables", "gsa1_views", function(isDrawingDepth, isDrawSkybox, isDraw3DSkybox)
    if depthTop > 0 then
        depthStack[depthTop] = nil
        depthTop = depthTop - 1
    end
    if isDrawingDepth or isDrawSkybox or isDraw3DSkybox then return end
    local cv = GSA1.cv and GSA1.cv.depthfix
    if not cv or cv:GetInt() < 2 then return end
    local C = GSA1.Char
    local fn = FrameNumber()
    if not C or not C.batches or depthRan ~= fn or lateDone == fn or C.relFrame ~= fn then return end
    if render.GetRenderTarget and render.GetRenderTarget() then return end        -- the screen's main view only
    lateDone = fn
    late(C)
end)

-- D1: a material's shader ("DepthWrite", "VertexLitGeneric", "UnlitGeneric")
local function shader_of(m)
    if not m then return nil end
    local ok, s = pcall(function() return (m.GetShader and m:GetShader()) or m.shader end)
    return ok and s or nil
end

-- D1 (for the session log's "views" line, cl_log.lua): the view of the last character draw - viewid (when view_kind
-- looked it up: a render target that is neither the screen nor a known one), the STUDIO flags, the kind ("main",
-- "ssao", "shadowdepth", "water"), the render target's name ("the screen"), the shader drawn with, the pass, the frame;
-- nil before the first draw. GSA1.ViewInfo(true, flags): the view being drawn NOW (call it inside a draw), with the view
-- id from render.GetViewSetup(true) and the shader G-SA1 uses in that view.
function GSA1.ViewInfo(live, flags)
    if live then
        local kind, rt, id = view_kind(flags)
        if id == nil and render.GetViewSetup then
            local ok, vs = pcall(render.GetViewSetup, true)
            if ok and type(vs) == "table" then id = vs.viewid end
        end
        local cv = GSA1.cv and GSA1.cv.depthfix
        local shader
        if DEPTH_KINDS[kind] and (not cv or cv:GetInt() >= 1) then
            shader = "DepthWrite"
        else
            local C = GSA1.Char
            shader = C and C.mats and shader_of(C.mats[1])
        end
        return { viewid = id, flags = flags, kind = kind, rt = rt or "the screen", shader = shader or "?", live = true }
    end
    if VI.frame < 0 then return nil end
    return { viewid = VI.viewid, flags = VI.flags, kind = VI.kind, rt = VI.rt or "the screen",
             shader = shader_of(VI.mat) or (VI.depth and "DepthWrite") or "?", pass = VI.pass, frame = VI.frame,
             depth = VI.depth }
end

-- the views that drew the character in the last frame ("main 1, depth pass 1, ..."; the debug line)
function GSA1.ViewsLine()
    local t = VT.frame == FrameNumber() and VT.cur or VT.last
    return string.format("main %d, depth pass %d, shadow depth %d, water %d, depth after the opaque pass %d", t.main or 0,
        t.ssao or 0, t.shadowdepth or 0, t.water or 0, t.late or 0)
end

-- 0.9.1 (T1, review R3.3): a blended batch that leaves the picture as it is - a lit see-through batch of alpha 0
-- (cl_textures.lua T.BatchAlpha) drawn SRC_ALPHA (4) with ONE_MINUS_SRC_ALPHA (5) or ONE (1); not the shadow's mask
local function invisible(b)
    local BA = GSA1.Tex.BatchAlpha
    return BA ~= nil and b.pass == 1 and band(b.wrap or 0, WRAP_MASK) == 0 and b.src == 4 and (b.dst == 5 or b.dst == 1)
        and BA(b) == 0
end

-- materials of the current batches (after a batch change or a settings change; the table is reused), the batches not
-- drawn (C.hidden: alpha 0); the batches' figures for the debug line (shadow, afterimage and hidden batches)
function GSA1.ResolveMaterials(C)
    local mats = C.mats or {}
    local hidden = C.hidden or {}
    local n = C.batches.count or 0
    local shadow, after, nhidden, objects = 0, 0, 0, 0
    for i = 1, n do
        local b = C.batches[i]
        mats[i] = GSA1.Tex.Material(C.kind, b)
        if band(b.flags, DRAW_SHADOW) ~= 0 then shadow = shadow + 1 end
        if band(b.flags, DRAW_OBJECT) ~= 0 then objects = objects + 1 end
        if band(b.all or b.flags, DRAW_AFTERIMAGE) ~= 0 then after = after + 1 end
        if invisible(b) then
            hidden[i] = true
            nhidden = nhidden + 1
        else
            hidden[i] = nil
        end
    end
    for i = #mats, n + 1, -1 do mats[i] = nil end
    for i in pairs(hidden) do
        if i > n then hidden[i] = nil end
    end
    C.mats, C.hidden = mats, hidden
    C.matsDirty = false
    C.shadowBatches, C.afterimageBatches, C.hiddenBatches = shadow, after, nhidden
    C.objectBatches, C.objectGen = objects, C.batchGen   -- 0.9.4: the game's objects (SA1_DRAW_OBJECT), drawn in
                                                         -- first person too
end

-- (GSA1.DrawCharacter through the global: cl_log.lua's draw counter wraps it and passes every argument on)
local draw_opaque = GSA1.Guard and GSA1.Guard("Draw", function(C, flags) GSA1.DrawCharacter(C, 0, flags) end) or
    function(C, flags) GSA1.DrawCharacter(C, 0, flags) end
local draw_blended = GSA1.Guard and GSA1.Guard("DrawTranslucent", function(C, flags) GSA1.DrawCharacter(C, 1, flags) end)
    or function(C, flags) GSA1.DrawCharacter(C, 1, flags) end

-- flags: the STUDIO flags of this render operation (0.9.2: STUDIO_SSAODEPTHTEXTURE in the depth pass,
-- STUDIO_SHADOWDEPTHTEXTURE in a lamp's shadow depth)
function ENT:Draw(flags)
    draw_opaque(self.char, flags)
end

function ENT:DrawTranslucent(flags)
    draw_blended(self.char, flags)
end

scripted_ents.Register(ENT, "gsa1_render")

-- ---- the draw list (gsa1_logdraws) -----------------------------------------------------------------------------------
local FLAG_NAMES = {
    { 0x1, "BLEND" }, { 0x2, "ATEST" }, { 0x4, "2SIDED" }, { 0x8, "ENV" }, { 0x10, "UNLIT" }, { 0x20, "PAL" },
    { 0x40, "EFFECT" }, { 0x80, "NOTEX" }, { 0x100, "AFTERIMAGE" }, { 0x200, "ADD" }, { 0x400, "USE_ALPHA" },
    { 0x800, "SHADOW" }, { 0x1000, "OBJECT" },
}
local PRIM_NAMES = { [0] = "triangles", [1] = "sprites", [2] = "lines" }
local SOURCE_NAMES = { [0] = "character", [1] = "model", [2] = "sprite", [3] = "line", [4] = "polygon", [5] = "pose" }

function GSA1.DrawFlagText(f)
    local t = {}
    for _, fl in ipairs(FLAG_NAMES) do
        if band(f, fl[1]) ~= 0 then t[#t + 1] = fl[2] end
    end
    return #t > 0 and table.concat(t, "|") or "-"
end

-- writes character C's draw list (the last gsa1.Render) into the session log: a "draws" header line and one line per
-- draw; returns the number of draws (nil, message when it cannot)
function GSA1.LogDraws(C)
    if not C then return nil, "no character" end
    if not (GSA1.HasFeature and GSA1.HasFeature("render", 1)) or not gsa1.DrawList then
        return nil, "this needs the module of G-SA1 0.8 (feature \"render\")"
    end
    C.drawList = C.drawList or {}
    local t = C.drawList
    local n, err = gsa1.DrawList(C.id, t)
    if not n then return nil, tostring(err) end
    if not GSA1.Log then return nil, "the session log is not loaded" end
    local s = C.state or {}
    local cv = GSA1.cv
    GSA1.Log("draws", "%s: %d draws (render %d, alpha %.2f%s), mode %d action %d %s, %d batches; effects %s, shadows %s, "
        .. "interpolate %s, %s positions", C.title or "?", n, t.gen or 0, t.alpha or 0, C.interpolated and ", interpolated"
        or "", s.mode or -1, s.action or -1, s.ground and "ground" or "air", C.batches and C.batches.count or 0,
        cv.effects:GetBool() and "on" or "off", (not cv.shadow or cv.shadow:GetBool()) and "on" or "off",
        cv.interp:GetBool() and "on" or "off", C.relOrigin and "camera-relative" or "absolute")
    for i = 1, n do
        local d = t[i]
        GSA1.Log("draws", "#%d order %d %s (%s) x%d: %s archive %d (%s) texture %d \"%s\", material %08X, blend %d/%d, "
            .. "alpha %d..%d, diffuse %08X -> batch %d pass %d", i, d.order or 0, PRIM_NAMES[d.prim] or "?",
            SOURCE_NAMES[d.source] or "?", d.n or 0, GSA1.DrawFlagText(d.flags or 0), d.archive or -1,
            (d.aname ~= nil and d.aname ~= "") and d.aname or "-", d.tex or -1, d.texname or "", d.mat or 0, d.src or 0,
            d.dst or 0, d.amin or 0, d.amax or 0, d.diffuse or 0, d.batch or 0, d.pass or -1)
    end
    return n
end

concommand.Add("gsa1_logdraws", function()
    local n, err = GSA1.LogDraws(GSA1.Char)
    if not n then
        GSA1.Msg("gsa1_logdraws: %s", tostring(err))
    else
        if GSA1.LogFlush then GSA1.LogFlush() end
        GSA1.Msg("%d draws written into the session log (garrysmod/data/gsa1/log.txt)%s", n,
            (GSA1.cv.log and not GSA1.cv.log:GetBool()) and " - but the session log is off (gsa1_log 0)" or "")
    end
end, nil, "G-SA1: write the character's draw list of this frame (what the game drew, with textures, flags, alpha and "
    .. "the batch each went into) into the session log")

-- the render line of the debug overlay (gsa1_debug): batches, shadow and afterimage batches, the drawing mode
function GSA1.RenderLine(C)
    C = C or GSA1.Char
    if not C or not C.batches then return "render: no character" end
    local s = C.state or {}
    return string.format("render: %d batches (%d blended), shadow batches %d (shadow draws %s), afterimage batches %d "
        .. "(%d with alpha 0, not drawn); %s positions; views: %s (gsa1_depthfix %s); gsa1_logdraws writes the draw list",
        C.batches.count or 0, C.blendedBatches or 0, C.shadowBatches or 0, s.shadow_draws ~= nil and
        tostring(s.shadow_draws) or "?", C.afterimageBatches or 0, C.hiddenBatches or 0, C.relOrigin and "camera-relative"
        or "absolute", GSA1.ViewsLine(), GSA1.cv.depthfix and GSA1.cv.depthfix:GetString() or "-")
end

hook.Add("HUDPaint", "gsa1_debug_render", function()
    local C = GSA1.Char
    if not C or not GSA1.cv.debug:GetBool() then return end
    draw.SimpleText(GSA1.RenderLine(C), "DermaDefault", 16, ScrH() - 40, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end)
