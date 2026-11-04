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
--
-- 0.9.5 (sadc docs/research/gsa1_095_plan.md 4.10, 5.5 with its review R.10; board095_perf.md P1, P2):
--   * The board (libsa1's SA1_DRAW_BOARD 0x4000: Sonic's and Tails' sand / snow board, its own batches by the module's
--     batch key) is part of the character: drawn in every view the character is drawn in - colour, the depth views, the
--     Faces page's close-up, the sun silhouette - whatever gsa1_effects says (its draws carry SA1_DRAW_EFFECT too: the
--     test comes first), and IN FIRST PERSON TOO (C.boardBatches counted beside C.objectBatches; the Objects page's
--     gsa1_set_draw never hides it). A board batch that is also SA1_DRAW_SHADOW follows gsa1_shadow. No new option.
--   * GSA1.DrawCharacterView(C, v): the character ALONE in a view of its own - the Faces page's close-up (perspective,
--     feat/cl_mouthtest.lua) and the sun silhouette (orthographic, feat/cl_liveshadow.lua) - instead of render.RenderView
--     of the whole world: both passes of THIS frame's batches through the colour pass's own draw_batches, only in a frame
--     whose main view prepared the character (C.viewFrame), camera-relative like the main view, counted as its own view
--     kind ("closeup" / "sunshadow", never "main"), timed as the hitch section "Closeup" (or the caller's).
--   * The garbage meter (cl_gcmeter.lua): ENT:Draw / DrawTranslucent are its slot "Draw / the character".
--
-- 0.9.8 (sadc docs/research/gsa1_098_plan.md 2.4 D4, D9, A13; gsa1_096_plan.md 4.10): a follower (C.follower, its own render
-- entity, feat/cl_follower.lua) is drawn by the same paths, with C.lod:
--   * every level: never its OBJECT batches (your world draws the game's objects);
--   * first person is about YOUR character (GSA1.FirstPersonFor, both sites: GSA1.DrawCharacter and draw_depth_late);
--   * level 1 (full): as your character, but in another addon's render target (kind main, a target that is not the screen:
--     the owner's prism_fx draws 7 "main" views into _rt_prism_dynscratch_1024x1024) only with gsa1_follower_other_views 1;
--   * level 2 (far): only when render.GetRenderTarget() is nil (the screen), not when the view kind says main; no EFFECT and no
--     SHADOW batches (a board batch, which is EFFECT too, stays; its shadow does not); the static-mesh path of the pair the
--     module rendered (C.interp false); the lighting cube every 4th frame; no depth, water or shadow-depth views;
--   * level 3: not drawn (the entity is SetNoDraw too);
--   * never counted as your character's view (GSA1.ViewInfo, GSA1.ViewsLine, cl_log.lua's views); its time is the hitch
--     section "FollowerDraw"; one EyePos / EyeAngles per frame for all followers on the screen, not one per follower (D10).
--
-- fardraw stage 1 (sadc docs/research/fardraw.md 4.1 with its review): the faster drawing (feat/cl_nativemesh.lua, GSA1.NativeMesh looked up at each call: this file loads before
-- gsa1/feat/*) also for far followers and the depth pass. With gsa1_native_mesh 0, or "Far followers too" (gsa1_native_far) off for what concerns far followers, or no such file at all,
-- everything draws as it did:
--   * draw_batches: a far follower with room in the budget (N.FarRoom) streams its batches through gsa1.DrawBatchNative every frame; its static meshes are freed once. One refused stays on
--     its static meshes for 2 s;
--   * draw_depth: its streamed batches through gsa1.DrawBatchNative (the static branch of gsa1_interpolate 0 stays);
--   * prepare_frame: no gsa1.PrepareView for a far follower with no new picture, no new origin and no changed option: a dynamic mesh reads the arrays every frame, but the arrays only change
--     with a picture (READ Session::tick_followers: r.pos is c.r_pos; render_copy clears view_ready, which DrawBatchNative also obeys);
--   * GSA1.DrawCharacter: no blended pass for a far follower with nothing to blend (C.farPass1) and, droppable, no draw at all for one outside the view by its real size (far_in_view);
--   * GSA1.DrawCounts: plain integers for the session log's drawpath line, in every state (cl_log.lua).
GSA1 = GSA1 or {}

local band = bit.band
local DRAW_EFFECT, DRAW_SHADOW, DRAW_AFTERIMAGE, WRAP_MASK = 0x40, 0x800, 0x100, 8
local DRAW_OBJECT = 0x1000
local DRAW_BOARD = 0x4000        -- 0.9.5: the character's board (libsa1 SA1_DRAW_BOARD)
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

-- the session log's counts (cl_log.lua's drawpath line reads and clears them every 10 s): draws by route (static, stream by Lua, native; depth by Lua, depth native) and by whom, far followers
-- drawn, far pictures, meshes built, far followers over the budget (feat/cl_nativemesh.lua) and left out by their size. Plain numbers, no garbage
local DC = { static = 0, lua = 0, native = 0, depthStatic = 0, depthLua = 0, depthNative = 0, farStatic = 0, farLua = 0, farNative = 0, nearColour = 0, nearDepth = 0, you = 0,
             farDrawn = 0, farPictures = 0, rebuilt = 0, farOver = 0, farLeftOut = 0 }
GSA1.DrawCounts = DC

local ENT = {}
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "G-SA1 character"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

-- 0.9.8 (seam L1, gsa1_098_plan.md 5.6): the character entity's render bounds; feat/cl_gamecam.lua widens one entity's while
-- the fishing camera shows, from these
GSA1.RENDER_BOUNDS_MIN, GSA1.RENDER_BOUNDS_MAX = Vector(-640, -640, -320), Vector(640, 640, 640)

function ENT:Initialize()
    self:SetRenderBounds(GSA1.RENDER_BOUNDS_MIN, GSA1.RENDER_BOUNDS_MAX)
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
    -- (0.9.8: a far follower's cube every 4th frame)
    if C.lod == 2 and C.light and C.lightFrame and FrameNumber() - C.lightFrame < 4 then return end
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

-- 0.9.8 (D10): the followers ask for the eye once per frame together, not once per follower: EyePos and EyeAngles make a new
-- Vector and Angle in the game
local foEye = { frame = -1 }
local function follower_main_eye()
    local v = GSA1.view
    local fn = FrameNumber()
    if v and v.frame == fn and v.origin and v.angles then return v.origin, v.angles end
    if foEye.frame ~= fn then foEye.frame, foEye.o, foEye.a = fn, EyePos(), EyeAngles() end
    return foEye.o, foEye.a
end
-- the screen's own eye (asked inside the screen's view, so never a mirror's)
local foScreen = { frame = -1 }
local function follower_screen_eye()
    local fn = FrameNumber()
    if foScreen.frame ~= fn then foScreen.frame, foScreen.o, foScreen.a = fn, EyePos(), EyeAngles() end
    return foScreen.o, foScreen.a
end

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

-- the colour pass draws a batch (its pass, triangles and C.hidden aside): the board always, in first person too (0.9.5:
-- before the first-person return and the effects test - it is EFFECT too; a board's shadow batch by gsa1_shadow), a game
-- object by the Objects page's switch (0.9.4: before the shadow and effects tests - it is EFFECT too; its blob shadow also
-- by gsa1_shadow), the shadow by its own switch (before the effects test: it is EFFECT too), effects by gsa1_effects; in
-- first person only the board and the objects. The depth views use the same test (review RC2)
local function batch_on(f, effects, shadows, objects, first_person)
    if band(f, DRAW_BOARD) ~= 0 then
        return shadows or band(f, DRAW_SHADOW) == 0
    end
    if band(f, DRAW_OBJECT) ~= 0 then
        return objects and (shadows or band(f, DRAW_SHADOW) == 0)
    end
    if first_person then return false end
    if band(f, DRAW_SHADOW) ~= 0 then return shadows end
    return effects or band(f, DRAW_EFFECT) == 0
end
GSA1.BatchOn = batch_on

-- 0.9.8 (gsa1_096_plan.md 4.10): which of a follower's batches batch_on may draw at all: never its OBJECT batches; at level 2
-- no shadow and no effects, but its board (the board's draws are EFFECT too)
local function follower_batch(C, f)
    if band(f, DRAW_OBJECT) ~= 0 then return false end
    if (C.lod or 1) >= 2 then
        if band(f, DRAW_SHADOW) ~= 0 then return false end
        if band(f, DRAW_EFFECT) ~= 0 and band(f, DRAW_BOARD) == 0 then return false end
    end
    return true
end
GSA1.FollowerBatch = follower_batch
local FAR_LEVEL = { lod = 2 }       -- (fardraw 4.1 step 4: C.farPass1 is counted as level 2 whatever C.lod is at that moment: it does not go stale at a level change)

-- the Objects page's switch (feat/cl_objects.lua; on without that feature)
local function objects_on()
    local c = GSA1.cv and GSA1.cv.set_draw
    return not c or c:GetBool()
end

-- this draw's view (GSA1.ViewInfo) and the views per frame (the debug line)
local VI = { frame = -1 }
local VT = { frame = -1, cur = { main = 0, ssao = 0, shadowdepth = 0, water = 0, late = 0, closeup = 0, sunshadow = 0 },
             last = { main = 0, ssao = 0, shadowdepth = 0, water = 0, late = 0, closeup = 0, sunshadow = 0 } }
local function tally(kind)
    local fn = FrameNumber()
    if VT.frame ~= fn then
        VT.frame = fn
        VT.cur, VT.last = VT.last, VT.cur
        local c = VT.cur
        c.main, c.ssao, c.shadowdepth, c.water, c.late, c.closeup, c.sunshadow = 0, 0, 0, 0, 0, 0, 0
    end
    VT.cur[kind] = (VT.cur[kind] or 0) + 1
end
local depthRan, lateDone = -1, -1       -- the frame of the last depth pass that drew the character, of the last R1b

-- the batches of one pass (inside the relative view when there is one); main: the main view (the pre-warm steps there);
-- 0.9.5 (GSA1.DrawCharacterView): filter(b) -> bool also has to pass; override: one material for every batch drawn (the
-- sun silhouette's flat white: unlit, a static mesh of this pair and origin is drawn again under it, never rebuilt)
-- 0.9.8 (sadc docs/research/gsa1_098_plan.md 6.13): one dynamic batch: through the module's own mesh path when it is on and checked
-- (feat/cl_nativemesh.lua), else, or when it fails right now, through Lua. Returns whether the path stays in use for this draw
local function stream_batch(C, i, tris, native)
    if native and GSA1.NativeMesh.Draw(C, i) then return true end
    mesh.Begin(MATERIAL_TRIANGLES, tris)
    emit(C, i)
    mesh.End()
    return false
end

local function draw_batches(C, pass, first_person, te, main, filter, override)
    local B = C.batches
    local cv = GSA1.cv
    if C.matsDirty then GSA1.ResolveMaterials(C) end
    local lit = cv.lighting:GetBool() and not override
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
    -- (fardraw 4.1 step 1: a far follower with room in the budget streams through the module; the file loads after this one, so N is looked up here)
    local NM = GSA1.NativeMesh
    local native = NM ~= nil and NM.Ready()
    local far = C.follower and C.lod == 2
    local static = not C.interp and not (native and far and NM.FarRoom(C, pass))
    if far and not static and next(C.static) ~= nil then free_static(C) end
    local tex = GSA1.Tex
    -- the material pre-warm: a few of the character's materials drawn once in this pass (invisible), in the main view
    if GSA1.Warm and main and not C.follower then
        local tw = SysTime()
        GSA1.Warm.Step(C, pass)
        te = te + (SysTime() - tw)      -- (timed as "Warm", not as "EmitBatch")
    end
    local O = C.relOrigin
    local ox, oy, oz = 0, 0, 0
    if O then ox, oy, oz = O.x, O.y, O.z end
    local hidden = C.hidden or NONE
    local nStatic, nLua, nNative, nBuilt = 0, 0, 0, 0
    -- (0.9.4, review R.1: in first person only the game's objects; 0.9.3a drew nothing there; 0.9.5: and the board)
    for i = 1, ((first_person and (C.objectBatches or 0) == 0 and (C.boardBatches or 0) == 0) and 0 or B.count) do
        local b = B[i]
        if b and b.pass == pass and b.tris > 0 and not hidden[i] then
            if batch_on(b.flags, effects, shadows, objects, first_person) and (not filter or filter(b)) and
               (not C.follower or follower_batch(C, b.flags)) then
                local mat = override or C.mats[i]
                render.SetMaterial(mat)
                if not VI.mat and not C.follower then VI.mat = mat end
                local tone = nil
                if pass == 1 then
                    local s, d = tex.BlendOf(b)
                    render.OverrideBlend(true, s, d, BLENDFUNC_ADD)
                    if band(b.wrap or 0, WRAP_MASK) ~= 0 and render.GetToneMappingScaleLinear then
                        tone = render.GetToneMappingScaleLinear()
                        if tone then render.SetToneMappingScaleLinear(TONE_ONE) end
                    end
                end
                if static and override then
                    -- (an extra view's own material: the pair's static mesh drawn again, else streamed - never cached)
                    local sm = C.static[i]
                    if sm and sm.imesh and sm.gen == C.renderGen and sm.tris == b.tris and sm.ox == ox and sm.oy == oy and
                       sm.oz == oz then
                        sm.imesh:Draw()
                        nStatic = nStatic + 1
                    else
                        native = stream_batch(C, i, b.tris, native)
                        if native then nNative = nNative + 1 else nLua = nLua + 1 end
                    end
                elseif static then
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
                        nBuilt = nBuilt + 1
                    end
                    sm.imesh:Draw()
                    nStatic = nStatic + 1
                else
                    native = stream_batch(C, i, b.tris, native)
                    if native then nNative = nNative + 1 else nLua = nLua + 1 end
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
    DC.static, DC.lua, DC.native, DC.rebuilt = DC.static + nStatic, DC.lua + nLua, DC.native + nNative, DC.rebuilt + nBuilt
    if far then
        DC.farStatic, DC.farLua, DC.farNative = DC.farStatic + nStatic, DC.farLua + nLua, DC.farNative + nNative
        -- (the budget's step, feat/cl_nativemesh.lua: a far follower's own colour lock has now happened in this session; a sun silhouette's material is not one)
        if nNative > 0 and not override and not NM.farLockFrame then NM.farLockFrame = FrameNumber() end
    elseif C.follower then
        DC.nearColour = DC.nearColour + nStatic + nLua + nNative
    else
        DC.you = DC.you + nStatic + nLua + nNative
    end
    return te
end

-- R1 (review RC2): the opaque batches into a depth view - exactly the ones the colour pass draws (pass 0, triangles, not
-- hidden, gsa1_effects / gsa1_shadow, in first person only the game's objects: 0.9.4) - with DepthWrite materials (color:
-- $color_depth 1, the depth pass); a static mesh (gsa1_interpolate 0) of this pair and origin is drawn again under the
-- depth material, else the batch is streamed (the depth pass comes before the screen, which rebuilds the static meshes of
-- a new pair)
local function draw_depth(C, color, first_person, te)
    if first_person and (C.objectBatches or 0) == 0 and (C.boardBatches or 0) == 0 then return te end
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
    -- (fardraw 4.1 step 2: the streaming branch through the module; new for the game there: DepthWrite materials, so N.DepthArm)
    local NM = GSA1.NativeMesh
    local native = NM ~= nil and NM.Ready()
    local nStatic, nLua, nNative = 0, 0, 0
    for i = 1, B.count do
        local b = B[i]
        if b and b.pass == 0 and b.tris > 0 and not hidden[i] and batch_on(b.flags, effects, shadows, objects, first_person) and
           (not C.follower or follower_batch(C, b.flags)) then
            local mat = depthMaterial(C.kind, b, color)
            render.SetMaterial(mat)
            if not VI.mat and not C.follower then VI.mat = mat end
            local sm = static and C.static and C.static[i]
            if sm and sm.imesh and sm.gen == C.renderGen and sm.tris == b.tris and sm.ox == ox and sm.oy == oy and
               sm.oz == oz then
                sm.imesh:Draw()
                nStatic = nStatic + 1
            else
                if native then NM.DepthArm() end
                native = stream_batch(C, i, b.tris, native)
                if native then nNative = nNative + 1 else nLua = nLua + 1 end
            end
        end
    end
    DC.depthStatic, DC.depthLua, DC.depthNative = DC.depthStatic + nStatic, DC.depthLua + nLua, DC.depthNative + nNative
    if C.follower then
        DC.nearDepth = DC.nearDepth + nStatic + nLua + nNative
    else
        DC.you = DC.you + nStatic + nLua + nNative
    end
    return te
end

local prepare_frame
-- the frame's origin of camera-relative drawing: the drawn root (constant within a game pair with gsa1_interpolate 0, so
-- the static meshes stay valid); decided with the main view's eye (R2b)
local rwFrame, rwWanted = -1, false       -- (0.9.8: the followers' answer, once per frame together)
local function rel_origin(C, fn)
    if C.relFrame ~= fn then
        C.relFrame = fn
        C.relOrigin = nil
        local wanted
        if C.follower then
            if rwFrame ~= fn then rwFrame, rwWanted = fn, relative_wanted() end
            wanted = rwWanted
        else
            wanted = relative_wanted()
        end
        if wanted then
            C.relO = C.relO or Vector()
            C.relO:Set(C.drawPos)
            C.relOrigin = C.relO
        end
    end
end

-- what a follower's PrepareView takes that its vertices depend on: a generation that goes up when one of them changes, read once per frame for all followers (fardraw 4.1 step 3)
local foOpt = { frame = -1, gen = 0 }
local function follower_opt_gen(cv, fn)
    local o = foOpt
    if o.frame ~= fn then
        o.frame = fn
        local flip, vcolor, width, lighting = cv.flip:GetBool(), cv.vcolor:GetBool(), cv.line_width:GetFloat(), cv.lighting:GetBool()
        if flip ~= o.flip or vcolor ~= o.vcolor or width ~= o.width or lighting ~= o.lighting then
            o.flip, o.vcolor, o.width, o.lighting = flip, vcolor, width, lighting
            o.gen = o.gen + 1
        end
    end
    return o.gen
end

-- the frame's view of the character, once per frame: PrepareView with the main view's eye (the sprites face it, the
-- coverage figure), the draw time's frame (C.viewFrame: GSA1.DrawCharacterView draws only in such a frame)
-- (fardraw 4.1 step 3: a far follower's arrays change only with a picture, so with the faster drawing on for far followers no PrepareView without one; the same frame, the same C.viewFrame.
-- A new origin, the eye under water, a changed option: again in that very frame. Sphere maps and lines stay frozen between pictures, as they do on a static mesh)
function prepare_frame(C, fn)
    rel_origin(C, fn)
    local cv = GSA1.cv
    C.viewFrame = fn
    C.drawMs, C.drawMsFrame = C.drawMsNext or 0, nil
    C.drawMsNext = 0
    local follower = C.follower
    local px, py, pz, pg
    if follower then
        local PO = C.relOrigin
        if PO then px, py, pz = PO.x, PO.y, PO.z end
        pg = follower_opt_gen(cv, fn)
        if C.lod == 2 then
            DC.farDrawn = DC.farDrawn + 1
            local fresh = C.prepGen == C.renderGen
            if not fresh then DC.farPictures = DC.farPictures + 1 end
            local NM = GSA1.NativeMesh
            if fresh and NM and NM.FarWanted() and C.prepX == px and C.prepY == py and C.prepZ == pz and C.prepOptGen == pg then return end
        end
    end
    -- R2b: the main view's eye, whichever view comes first (the water reflection's is mirrored under the water)
    local eye, ang
    if C.follower then eye, ang = follower_main_eye() else eye, ang = main_eye() end
    local tv = SysTime()
    -- the screen for the coverage figure: CalcView's field of view (cl_character.lua) of this frame, else the player's
    -- setting
    local v = GSA1.view
    local fov = (v and v.frame and fn - v.frame <= 2 and v.fov) or (cv_fov and cv_fov:GetFloat()) or 75
    -- (0.9.4d: the axes into the character's own Vectors, not two new ones a frame)
    C.viewR, C.viewU = C.viewR or Vector(), C.viewU or Vector()
    GSA1.AngleAxes(ang, nil, C.viewR, C.viewU)
    gsa1.PrepareView(C.id, eye, C.viewR, C.viewU, cv.flip:GetBool(), cv.vcolor:GetBool(),
        cv.line_width:GetFloat(), cv.lighting:GetBool(), fov, ScrW(), ScrH(), C.relOrigin)
    if follower then C.prepGen, C.prepX, C.prepY, C.prepZ, C.prepOptGen = C.renderGen, px, py, pz, pg end
    if GSA1.HitchAdd then GSA1.HitchAdd("PrepareView", SysTime() - tv) end
end

-- fardraw 4.1 step 6, droppable (review RF.19): is a far follower in the view by its real size? The engine's own cull uses the render bounds above, 640 units for every character; a far follower
-- draws no effects, so it is far smaller than that. GSA1.FAR_RADIUS is measured, not guessed: the largest distance of a vertex a far follower draws from its centre over the walk of
-- tests/feat_nativemesh_binding_test.cpp (every form, without and with its upgrades, running, jumping, each button, standing long), plus 20 %; that test fails when the walk exceeds it. One number for
-- all kinds: Knuckles' own worst is 41, so 99 Knuckles keep a little more than they need at the screen's edge, and no unmeasured pose of a kind with a short worst can pop. The 4 side planes once per
-- frame, from CalcView's view of this frame by Source's Hor+ (as Session::prepare_view computes tan_h, tan_v). No fresh view of ours, or the screen's eye is not that view (another addon's camera):
-- everyone is in view.
GSA1.FAR_RADIUS = 140       -- MEASURED: 116.3 (Big, 27 ticks after B on the run: a plain opaque part), x 1.2, rounded up
local farPlanes = { frame = -1, ok = false }
local function far_planes(fn)
    local P = farPlanes
    P.frame, P.ok = fn, false
    local v = GSA1.view
    if not (v and v.frame == fn and v.origin and v.angles and v.fov and v.fov > 1 and v.fov < 179) then return end
    local se, sa = follower_screen_eye()
    local e = v.origin
    if math.abs(se.x - e.x) > 1 or math.abs(se.y - e.y) > 1 or math.abs(se.z - e.z) > 1 or math.abs(math.NormalizeAngle(sa.p - v.angles.p)) > 1 or
       math.abs(math.NormalizeAngle(sa.y - v.angles.y)) > 1 then
        return
    end
    P.f, P.r, P.u = P.f or Vector(), P.r or Vector(), P.u or Vector()
    GSA1.AngleAxes(v.angles, P.f, P.r, P.u)
    local t43 = math.tan(math.rad(v.fov) / 2)
    local th, tv = t43 * (ScrW() / ScrH()) / (4 / 3), t43 * 0.75
    local nh, nv = 1 / math.sqrt(1 + th * th), 1 / math.sqrt(1 + tv * tv)
    local f, r, u = P.f, P.r, P.u
    P.ex, P.ey, P.ez = e.x, e.y, e.z
    -- the inward normals: tan x forward -+ side, of length 1
    P.fhx, P.fhy, P.fhz = f.x * th * nh, f.y * th * nh, f.z * th * nh
    P.rx, P.ry, P.rz = r.x * nh, r.y * nh, r.z * nh
    P.fvx, P.fvy, P.fvz = f.x * tv * nv, f.y * tv * nv, f.z * tv * nv
    P.ux, P.uy, P.uz = u.x * nv, u.y * nv, u.z * nv
    P.ok = true
end
local function far_in_view(C, fn)
    local P = farPlanes
    if P.frame ~= fn then far_planes(fn) end
    if not P.ok then return true end
    local p = C.drawPos
    local x, y, z = p.x - P.ex, p.y - P.ey, p.z + (C.info and C.info.center or 20) - P.ez
    local R = GSA1.FAR_RADIUS
    local front, side = x * P.fhx + y * P.fhy + z * P.fhz, x * P.rx + y * P.ry + z * P.rz
    if front - side < -R or front + side < -R then return false end
    front, side = x * P.fvx + y * P.fvy + z * P.fvz, x * P.ux + y * P.uy + z * P.uz
    return not (front - side < -R or front + side < -R)
end

-- pass 0: opaque batches, 1: blended batches (in the game's order); flags: the STUDIO flags of ENT:Draw /
-- ENT:DrawTranslucent (0.9.2: they say which of Source's views is drawing)
function GSA1.DrawCharacter(C, pass, flags)
    local B = C and C.batches
    if not B or (B.count or 0) == 0 or not C.drawPos then return end
    if C.follower and (C.lod or 1) >= 3 then return end
    local first_person = GSA1.FirstPersonFor and GSA1.FirstPersonFor(C)
    -- first person: the game's objects only (0.9.4, review R.1) and the board (0.9.5, review R.10: whatever the Objects
    -- page says), or the pre-warm while it runs (the OBJECT and BOARD batches counted once per batch structure;
    -- ResolveMaterials counts them too)
    if first_person and C.objectGen ~= C.batchGen then
        local n, nb = 0, 0
        for i = 1, B.count do
            local b = B[i]
            if b and band(b.flags or 0, DRAW_OBJECT) ~= 0 then n = n + 1 end
            if b and band(b.flags or 0, DRAW_BOARD) ~= 0 then nb = nb + 1 end
        end
        C.objectBatches, C.boardBatches, C.objectGen = n, nb, C.batchGen
    end
    local fp_objects = first_person and (((C.objectBatches or 0) > 0 and objects_on()) or (C.boardBatches or 0) > 0)
    local fn = FrameNumber()
    if first_person and not fp_objects and not (GSA1.Warm and GSA1.Warm.total and not GSA1.Warm.total.done) then
        -- 0.9.5: nothing of the character in this view, but an extra view wants this frame's batches (the sun shadow in
        -- first person, gsa1_sunshadow_fp): the frame's origin and PrepareView only, nothing drawn, no view counted
        if C.viewWanted and C.viewFrame ~= fn then prepare_frame(C, fn) end
        return
    end
    local cv = GSA1.cv
    local t0 = SysTime()
    -- the view: depth views (gsa1_depthfix 1 / 2) get the DepthWrite draw; with gsa1_depthfix 0 they are drawn as 0.9.1
    -- drew them (as the main view)
    local kind, rtname, viewid = view_kind(flags)
    local depthKind = DEPTH_KINDS[kind] or false
    local depth = depthKind and (not cv.depthfix or cv.depthfix:GetInt() >= 1)
    if C.follower then
        -- 0.9.8 (D4): level 2 only on the screen itself; level 1 not in another addon's render target unless the option says
        -- so; none of this counts as your character's view (VI, tally)
        local screen = kind == "main" and rtname == nil
        if (C.lod or 1) == 2 then
            if not screen then return end
            -- (fardraw 4.1 steps 4, 6: looked up at the call; off, or "Far followers too" off: nothing of this)
            local NM = GSA1.NativeMesh
            if NM and NM.FarWanted() then
                if pass == 1 then
                    if C.matsDirty then GSA1.ResolveMaterials(C) end
                    if (C.farPass1 or 0) == 0 then return end
                end
                if not far_in_view(C, fn) then
                    if pass == 0 then
                        DC.farLeftOut = DC.farLeftOut + 1
                        C.drawMs, C.drawMsNext = 0, 0     -- (the followers line's draw figure sums C.drawMs)
                    end
                    return
                end
            end
        elseif kind == "main" and not screen then
            local ov = cv.follower_other_views
            if not (ov and ov:GetBool()) then return end
        end
    else
        VI.frame, VI.pass, VI.flags, VI.kind, VI.rt, VI.viewid, VI.depth, VI.mat = fn, pass, flags, kind, rtname, viewid,
            depth, nil
        if pass == 0 then tally(kind) end
    end
    if depth and kind == "ssao" then depthRan = fn end
    if depth and pass ~= 0 then return end
    rel_origin(C, fn)
    if C.viewFrame ~= fn and (not first_person or fp_objects) then prepare_frame(C, fn) end
    local te = SysTime()
    -- the main view (and 0.9.1's way for depth views with gsa1_depthfix 0): camera-relative under cam.Start3D; every
    -- other view (depth, water): world positions through a model matrix (R2), so Source's view stays as it is
    local push = nil
    local O = C.relOrigin
    if O then
        if kind == "main" or not depth and depthKind or not (cam.PushModelMatrix and Matrix) then
            C.relEye = C.relEye or Vector()
            if C.follower and kind == "main" and rtname == nil then
                local fe, fa = follower_screen_eye()
                C.relEye:Set(fe)
                C.relEye:Sub(O)
                cam.Start3D(C.relEye, fa)
            else
                C.relEye:Set(EyePos())
                C.relEye:Sub(O)
                cam.Start3D(C.relEye, EyeAngles())
            end
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
    if GSA1.HitchAdd then GSA1.HitchAdd(C.follower and "FollowerDraw" or "EmitBatch", SysTime() - te) end
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
    local first_person = GSA1.FirstPersonFor and GSA1.FirstPersonFor(C) or false
    if first_person and (C.objectBatches or 0) == 0 and (C.boardBatches or 0) == 0 then return end
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

-- 0.9.5 (sadc docs/research/board095_perf.md P1; gsa1_095_plan.md 4.17, 5.5): the character ALONE in a view of its own.
--   v = { eye = Vector, ang = Angle, fov = number (perspective) | ortho = { left, right, top, bottom } (orthographic),
--         x, y, w, h, znear, zfar, filter = function(b) -> bool | nil, material = IMaterial | nil (one for every batch:
--         unlit), opaque = true (pass 0 only), kind = "closeup" (default) | "sunshadow", hitch = section name (default
--         "Closeup"; false: the caller times it) }
-- Both passes of THIS frame's batches through the colour pass's own draw_batches (batch_on: gsa1_effects, gsa1_shadow,
-- the Objects page's switch, the board always; the hidden batches; no pre-warm step; never the first-person rule: the
-- caller decides) under cam.Start3D(eye - origin, ang, fov, x, y, w, h, znear, zfar) - or cam.Start with the ortho box -
-- into the current render target, camera-relative like the main view (the eye minus this frame's C.relOrigin). Only in a
-- frame whose main view prepared the character (C.viewFrame == FrameNumber(): its PrepareView and origin; nothing is
-- prepared or rendered again), else false, why (nothing drawn: the caller keeps its last picture). Counted as its own view
-- kind (GSA1.ViewsLine), never as "main"; the time goes into the character's draw time.
local CV_DATA = { type = "3D" }
function GSA1.DrawCharacterView(C, v)
    local B = C and C.batches
    if not B or (B.count or 0) == 0 or not C.drawPos then return false, "no batches" end
    local fn = FrameNumber()
    if C.viewFrame ~= fn then return false, "not drawn this frame" end
    if type(v) ~= "table" or not (v.eye and v.ang) then return false, "no view" end
    local t0 = SysTime()
    local O = C.relFrame == fn and C.relOrigin or nil
    C.cvEye = C.cvEye or Vector()
    C.cvEye:Set(v.eye)
    if O then C.cvEye:Sub(O) end
    -- (0.9.9a: a follower's sun silhouette is never counted as your character's view: D4 above)
    if not C.follower then tally(v.kind or "closeup") end
    local ortho = v.ortho
    if ortho and cam.Start then
        local d = CV_DATA
        d.origin, d.angles, d.x, d.y, d.w, d.h, d.ortho, d.znear, d.zfar = C.cvEye, v.ang, v.x or 0, v.y or 0, v.w,
            v.h, ortho, v.znear, v.zfar
        cam.Start(d)
    else
        cam.Start3D(C.cvEye, v.ang, v.fov, v.x or 0, v.y or 0, v.w, v.h, v.znear, v.zfar)
    end
    local ok, err = pcall(draw_batches, C, 0, false, 0, false, v.filter, v.material)
    if ok and not v.opaque then ok, err = pcall(draw_batches, C, 1, false, 0, false, v.filter, v.material) end
    cam.End3D()
    local dt = SysTime() - t0
    if v.hitch ~= false and GSA1.HitchAdd then GSA1.HitchAdd(v.hitch or "Closeup", dt) end
    C.drawMsNext = (C.drawMsNext or 0) + dt * 1000
    if not ok then error(err, 0) end
    return true
end

-- GSA1.SkyView(isDrawSkybox, isDraw3DSkybox): is this the 3D skybox's own view, for a hook that draws only in the map's
-- view? The rule of 0.9.5a's sun shadow (feat/cl_liveshadow.lua, the top of the file): isDrawSkybox alone excludes nothing,
-- since on a map with a 2D sky it can be true in every call, the main view's too (Garry's Mod wiki). A map known to have no
-- sky_camera (the sun shadow's reader of the entity lump; not known while that is off or still reading) has no such view;
-- else isDraw3DSkybox says yes, and isDrawSkybox alone asks Source's view id: VIEW_3DSKY or no answer is yes. The arguments
-- themselves are UNVERIFIED in game, those of PostDrawTranslucentRenderables most of all (assumed the same).
local VIEW_3DSKY = 1
function GSA1.SkyView(isDrawSkybox, isDraw3DSkybox)
    if not (isDrawSkybox or isDraw3DSkybox) then return false end
    local S = GSA1.SunShadow
    if S and S.light and S.light.sky3d == false then return false end
    if isDraw3DSkybox then return true end
    local vs = render.GetViewSetup and render.GetViewSetup(true)        -- (a new table: callers ask last)
    local id = type(vs) == "table" and vs.viewid or nil
    return id == nil or id == VIEW_3DSKY
end

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
    if isDrawingDepth then return end
    local cv = GSA1.cv and GSA1.cv.depthfix
    if not cv or cv:GetInt() < 2 or GSA1.SkyView(isDrawSkybox, isDraw3DSkybox) then return end
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
    local cu, ss = t.closeup or 0, t.sunshadow or 0
    return string.format("main %d, depth pass %d, shadow depth %d, water %d, depth after the opaque pass %d%s%s", t.main or 0,
        t.ssao or 0, t.shadowdepth or 0, t.water or 0, t.late or 0,
        cu > 0 and string.format(", the Faces page's close-up %d", cu) or "",
        ss > 0 and string.format(", sun shadow %d", ss) or "")
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
    local shadow, after, nhidden, objects, boards, far1 = 0, 0, 0, 0, 0, 0
    for i = 1, n do
        local b = C.batches[i]
        mats[i] = GSA1.Tex.Material(C.kind, b)
        if band(b.flags, DRAW_SHADOW) ~= 0 then shadow = shadow + 1 end
        if band(b.flags, DRAW_OBJECT) ~= 0 then objects = objects + 1 end
        if band(b.flags, DRAW_BOARD) ~= 0 then boards = boards + 1 end
        if band(b.all or b.flags, DRAW_AFTERIMAGE) ~= 0 then after = after + 1 end
        if invisible(b) then
            hidden[i] = true
            nhidden = nhidden + 1
        else
            hidden[i] = nil
        end
        if b.pass == 1 and (b.tris or 0) > 0 and not hidden[i] and follower_batch(FAR_LEVEL, b.flags) then far1 = far1 + 1 end
    end
    C.farPass1 = far1                                    -- (fardraw 4.1 step 4: what a far follower's blended pass would draw, whatever C.lod is now)
    for i = #mats, n + 1, -1 do mats[i] = nil end
    for i in pairs(hidden) do
        if i > n then hidden[i] = nil end
    end
    C.mats, C.hidden = mats, hidden
    C.matsDirty = false
    C.shadowBatches, C.afterimageBatches, C.hiddenBatches = shadow, after, nhidden
    C.objectBatches, C.objectGen = objects, C.batchGen   -- 0.9.4: the game's objects (SA1_DRAW_OBJECT), drawn in
                                                         -- first person too
    C.boardBatches = boards                              -- 0.9.5: the board (SA1_DRAW_BOARD), the same
end

-- (GSA1.DrawCharacter through the global: cl_log.lua's draw counter wraps it and passes every argument on)
local draw_opaque = GSA1.Guard and GSA1.Guard("Draw", function(C, flags) GSA1.DrawCharacter(C, 0, flags) end) or
    function(C, flags) GSA1.DrawCharacter(C, 0, flags) end
local draw_blended = GSA1.Guard and GSA1.Guard("DrawTranslucent", function(C, flags) GSA1.DrawCharacter(C, 1, flags) end)
    or function(C, flags) GSA1.DrawCharacter(C, 1, flags) end

-- flags: the STUDIO flags of this render operation (0.9.2: STUDIO_SSAODEPTHTEXTURE in the depth pass,
-- STUDIO_SHADOWDEPTHTEXTURE in a lamp's shadow depth)
-- 0.9.5 (board095_perf.md P2): the garbage meter's slot of the character's draws (entity draws are not hooks)
local GM = GSA1.GcMeter
local gm_slot = GM and GM.Slot and GM.Slot("Draw", "the character")
function ENT:Draw(flags)
    if gm_slot and GM.on then
        local k0, outer = GM.Enter()
        draw_opaque(self.char, flags)
        GM.Add(gm_slot, k0, outer)
        return
    end
    draw_opaque(self.char, flags)
end

function ENT:DrawTranslucent(flags)
    if gm_slot and GM.on then
        local k0, outer = GM.Enter()
        draw_blended(self.char, flags)
        GM.Add(gm_slot, k0, outer)
        return
    end
    draw_blended(self.char, flags)
end

scripted_ents.Register(ENT, "gsa1_render")

-- ---- the draw list (gsa1_logdraws) -----------------------------------------------------------------------------------
local FLAG_NAMES = {
    { 0x1, "BLEND" }, { 0x2, "ATEST" }, { 0x4, "2SIDED" }, { 0x8, "ENV" }, { 0x10, "UNLIT" }, { 0x20, "PAL" },
    { 0x40, "EFFECT" }, { 0x80, "NOTEX" }, { 0x100, "AFTERIMAGE" }, { 0x200, "ADD" }, { 0x400, "USE_ALPHA" },
    { 0x800, "SHADOW" }, { 0x1000, "OBJECT" }, { 0x4000, "BOARD" },
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
