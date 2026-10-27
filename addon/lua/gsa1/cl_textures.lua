-- G-SA1 client: the characters' textures (decoded by the module from the player's disc) in render targets, and
-- the materials of the render batches.
--
-- GLua cannot create a texture from bytes, so each texture becomes a render target of its exact size, painted
-- with one surface.DrawRect per run of equal pixels (the module run-length encodes the RGBA8 image), a few
-- thousand runs per frame. Every texture archive of a character is used: archive 0 is the model's textures,
-- 1.. its effect archives (SON_EFF, KNU_EFF, E102BEAM, ...) and the common ones (OBJ_REGULAR: the blob shadow's;
-- EFF_REGULAR). A render target's sampler state is fixed when it is created, so a texture drawn both clamped and
-- repeated gets one render target per address mode. Nothing is written to disk. Render targets lose their contents on a
-- device reset (alt-tab in exclusive fullscreen, a resolution change): after such a signal - the game window regaining
-- the focus, OnScreenSizeChanged - a canary pixel is read back and everything is repainted when it changed. 0.4 read it
-- back every 2 seconds, a GPU-to-CPU sync each time (sadc docs/research/gsa1_ramp_freeze.md fix 9: a periodic hitch);
-- gsa1_texrepaint repaints by hand.
--
-- The render targets must keep the alpha channel: sprites, cut-outs and soft effect edges come from the textures'
-- alpha. 0.4 - 0.7 lost it (the owner's 0.6.0 log: "BGRA8888 read back 96 where 96 was painted, 255 where 0"; Knuckles'
-- climbing / digging clods with dark frames and his punch dust as black squares - "inverted alphas"; sadc
-- docs/research/gsa1_060_alpha.md with its review). The chain, measured in the installed Garry's Mod and in Direct3D 9
-- (native and GMod's DXVK, D3D9 and D3D9Ex):
--   1. Source creates every render target and clears it to OPAQUE black (CTexture::Download: ClearColor4ub(0,0,0,255));
--   2. the texture render targets have no depth buffer (MATERIAL_RT_DEPTH_NONE: Source binds none), and 0.4 - 0.7 cleared
--      them with render.Clear(0, 0, 0, 0, true, true): Direct3D 9 rejects a Clear with D3DCLEAR_ZBUFFER / STENCIL and no
--      depth buffer (D3DERR_INVALIDCALL) and clears NOTHING, colour included;
--   3. surface.DrawRect never draws when the draw colour's alpha is 0 (vgui's DrawFilledRect returns early), so the
--      alpha-0 texels kept step 1's opaque black, on every machine measured.
-- 0.8: colour-only clears (render.Clear(0, 0, 0, 0)); an alpha-0 texel that carries RGB (soft edges under bilinear
-- filtering) is painted with its colour and alpha 255 under a blend that writes the colour as it is and alpha ZERO
-- (render.OverrideBlend's separate alpha factors: exact; the review's "fix 2c"), or - where the probe sees that the
-- separate alpha blend is not honoured - with alpha 1 (at most 1/255 off: "fix 2a"); the surface alpha multiplier other
-- addons may leave set is 1 while painting; and a probe that runs the painter itself on a synthetic texture (texel A
-- (200, 100, 50, 96), texel B (255, 255, 255, 0), texel C unpainted) reads back 96 / 0 (<= 1) / 0, then draws that
-- render target the way batches draw - render.SetMaterial with a translucent unlit material of T.Material's kind and a
-- mesh quad, magnified 4x into a white target - and reads what the material samples: 236 214 209 / 255 / 255 where the
-- framebuffer blends in linear light (sRGB-correct: every owner log reads 237 214 208), 234 197 178 where it blends in
-- gamma space (0.9.2a: gsa1_091a_perf.md 3.2; the alpha read-back checks do not depend on it). If even a
-- colour-only clear fails on a host (the unpainted texel is not 0), the textures are cleared by drawing a quad of (0, 0,
-- 0, 0). GSA1.Tex.FormatLine (gsa1_status, gsa1_texcheck, the session log) gives the result. The format stays
-- IMAGE_FORMAT_BGRA8888 (D3DFMT_A8R8G8B8 keeps alpha: 96 painted, 96 read back); RGBA8888 is tried when it does not.
--
-- 0.6.0 (round 4c, the Light Speed charge freeze): a material is named by what it is - its texture's render target (or
-- vgui/white), blend mode, lighting, culling, half-Lambert - so batches that differ only in what the material does not
-- see (blend factors, which render.OverrideBlend sets, effect and texture-loading flags) share one; the materials of
-- known batch keys are found without building a string; a material made at its first use, a render target made at its
-- first use and the texture painting are timed and written into the session log (cl_log.lua). cl_warm.lua makes the
-- materials a character can use while it appears.
--
-- 0.8, the blob shadow (sadc docs/research/gsa1_060_shadow.md G3 with its review R.3.2 / R.3.3): libsa1 draws the game's
-- shadow (SA1_DRAW_SHADOW, OBJ_REGULAR's texture 58 "shadow": black in every texel, the shape in its alpha, SRC_ALPHA /
-- INV_SRC_ALPHA with the diffuse alpha 204). The module marks such a batch with the address-mode bit WRAP_MASK (8): its
-- render target is painted with RGB = the texel's alpha (a "mask"), its material is unlit, translucent, without fog, and
-- cl_render.lua draws it with ZERO / ONE_MINUS_SRC_COLOR - dst x (1 - 204/255 x tex.a), the game's result for a black
-- texture, needing no alpha in the render target. OBJ_REGULAR's other 95 textures are never listed for painting
-- (T.Prepare): the shadow's render target is made at its first use.
--
-- 0.9.1, the game's see-through copies (the owner's 0.7.0 report "afterimages in general aren't transparent"; sadc
-- docs/research/gsa1_070_translucency.md T1 / T3 with its review): Tails' blur tails and ball copies (alpha 170 / 85,
-- 67 / 33 %), Amy's hammer ghosts (76 / 51) and E-102's etx_right3 parts (216) are palette-lit blended draws whose
-- translucency is their vertex alpha. With gsa1_lighting 1 their materials are VertexLitGeneric, and VertexLitGeneric
-- ignores $vertexalpha and $vertexcolor (Source SDK 2013 vertexlitgeneric_dx9_helper.cpp; in the owner's
-- stdshader_dx9.dll at 0x180063CDD): 0.4 - 0.9.0 drew every copy solid. The module now keys a lit translucent batch by its
-- draws' vertex alpha (".a<alpha>" at the end of the batch key; T.BatchAlpha) and its material carries that alpha as
-- $alpha, which VertexLitGeneric multiplies in (the material is named with "_a<alpha>"). Unlit materials keep
-- $vertexalpha only ($alpha too would apply the alpha twice), and their batches are not keyed by alpha (their alphas
-- change from pair to pair). A startup check (T3, with the probe) draws a lit $alpha 0.5 quad and a lit $alpha 1 quad
-- over black: if Source ignores $alpha here too ("LOST"), lit see-through batches get unlit materials instead
-- (see-through, but fullbright); T.LitLine (in T.FormatLine: gsa1_status, the session log) gives the result.
-- 0.9.2a (sadc docs/research/gsa1_091a_perf.md T3b with its review RC15): the check predicts both ways a framebuffer can
-- blend - in gamma space (128 of 255) and in linear light (sRGB-correct, 188 of 255: what the owner's Garry's Mod does,
-- 0.74 of the control) - and says "ok" for either, naming the blend space when the two predictions are far enough apart
-- to tell (T.LitVerdict); 0.9.1a called the owner's 188 "not measured". Only "lost" changes the materials, as before.
--
-- 0.9.2 (sadc docs/research/gsa1_090_render.md R1): T.DepthMaterial, the DepthWrite materials cl_render.lua draws the
-- opaque batches with in Source's depth views (the depth pass post-processing reads, lamp and flashlight shadow depth).
GSA1 = GSA1 or {}
GSA1.Tex = GSA1.Tex or { entries = {}, infos = {}, archives = {}, queue = {}, mats = {}, translucent = {}, later = {} }
local T = GSA1.Tex
T.later = T.later or {}
T.byKey = T.byKey or {}         -- [kind][batch key] = material under the current settings (cleared when they change)
T.paint = T.paint or nil        -- the painting under way: {t0, frames, runs, textures, ms, maxms}
T.created = T.created or 0      -- render targets made
T.clearMode = T.clearMode or "clear"   -- "clear": render.Clear(0, 0, 0, 0); "draw": a quad of (0, 0, 0, 0) (the probe)
T.a0mode = T.a0mode or "exact"         -- alpha-0 texels with RGB: "exact" (separate alpha ZERO) or "alpha1" (the probe)
local LATER_BUDGET = 0.003      -- seconds per frame for the texture infos of a new character (gsa1.Texture)

local band, bor = bit.band, bit.bor
local TF_POINTSAMPLE, TF_CLAMPS, TF_CLAMPT, TF_NOMIP, TF_NOLOD = 0x1, 0x4, 0x8, 0x100, 0x200
-- GMod's BLEND_* values (render.OverrideBlend)
local B_ZERO, B_ONE, B_SRC_ALPHA, B_ONE_MINUS_SRC_ALPHA, B_ONE_MINUS_SRC_COLOR = 0, 1, 4, 5, 10
local FUNC_ADD = 0
local QUADS = MATERIAL_QUADS or 7

-- render target formats, preferred first (IMAGE_FORMAT_* values of Source's ImageFormat)
local RT_FORMATS = {
    { name = "BGRA8888", fmt = IMAGE_FORMAT_BGRA8888 or 12 },
    { name = "RGBA8888", fmt = IMAGE_FORMAT_RGBA8888 or 0 },
}
T.format = T.format or RT_FORMATS[1]
T.probe = T.probe or nil         -- { [name] = probe result } after the probe (probe_format)
local WRAP_CLAMP_U, WRAP_CLAMP_V, WRAP_POINT, WRAP_MASK = 1, 2, 4, 8
T.WRAP_MASK = WRAP_MASK
-- 0.9.4a (sadc docs/research/super2_plan.md 6.4 task 3 with its review R.6): a batch libsa1 marked gold (the golden Light
-- Speed charge) draws the texture's golden variant (gsa1.Texture(kind, index, archive, 1)) from a render target of its own
-- (the wrap is part of its name); the alpha handling stays the base texture's (the variant keeps every alpha)
local WRAP_GOLD = 0x10
T.WRAP_GOLD = WRAP_GOLD
local DRAW_BLEND, DRAW_ALPHA_TEST, DRAW_DOUBLE_SIDED = 0x1, 0x2, 0x4
local DRAW_UNLIT, DRAW_PALETTE_LIT, DRAW_ADDITIVE = 0x10, 0x20, 0x200
-- archives whose textures are not listed for painting at a spawn (T.Prepare): OBJ_REGULAR (96 textures per character
-- kind, of which only the blob shadow's is drawn: made at its first use; review R.3.2 of gsa1_060_shadow.md)
T.NO_PREPARE = { OBJ_REGULAR = true }

-- the archives of a character: { [0] = {name, count}, ... }
function T.Archives(kind)
    local a = T.archives[kind]
    if a then return a end
    a = { n = 0 }
    local list = gsa1.TextureArchives(kind)
    if type(list) == "table" then
        for i, e in ipairs(list) do
            a[i - 1] = { name = e.name, count = e.count }
            a.n = i
        end
    end
    T.archives[kind] = a
    return a
end

local function prof(name, t0)
    if GSA1.HitchAdd then GSA1.HitchAdd(name, SysTime() - t0) end
end

-- variant (0.9.4a): 0 / nil = the texture, > 0 = libsa1's variant of it (a refusal is the caller's to report: quiet)
local function info_of(kind, archive, index, variant)
    variant = tonumber(variant) or 0
    local k = kind .. "_" .. archive .. "_" .. index .. (variant > 0 and ("_v" .. variant) or "")
    local i = T.infos[k]
    if i == nil then
        local info, err
        if variant > 0 then
            info, err = gsa1.Texture(kind, index, archive, variant)
        else
            info, err = gsa1.Texture(kind, index, archive)
        end
        if not info and variant == 0 then
            GSA1.Msg("texture %d of archive %d of character %d: %s", index, archive, kind, tostring(err))
        end
        i = info or false
        T.infos[k] = i
        if not info and variant > 0 then T.infoErrors[k] = tostring(err) end
    end
    return i or nil
end
T.infoErrors = T.infoErrors or {}

local function enqueue(e, urgent)
    if e.queued then
        if not urgent then return end
        for qi, q in ipairs(T.queue) do
            if q == e then table.remove(T.queue, qi) break end
        end
    end
    e.queued = true
    if urgent then table.insert(T.queue, 1, e) else T.queue[#T.queue + 1] = e end
end

-- the render target of a texture in an address mode (WRAP_* bits; WRAP_MASK: the mask of the texture's alpha; 0.9.4a
-- WRAP_GOLD: the texture's golden variant, or the texture itself when the module refuses the variant); painted
-- soon (urgent: next). `why`: "first use" (a batch needs it now: timed and logged), nil (the spawn's list, the pre-warm)
function T.Get(kind, archive, index, wrap, urgent, why)
    local key = kind .. "_" .. archive .. "_" .. index .. "_" .. wrap
    local e = T.entries[key]
    if e ~= nil then
        if e and urgent and not e.done then enqueue(e, true) end
        return e or nil
    end
    local t0 = SysTime()
    local gold = band(wrap, WRAP_GOLD) ~= 0
    local info
    if gold then
        info = info_of(kind, archive, index, 1)
    else
        info = info_of(kind, archive, index)
    end
    if gold and not info then
        -- review R.6: a refused variant (an older module or libsa1, another texture) draws the game's own texture in this
        -- render target, never vgui/white (an additive white square per sparkle); one log line
        info = info_of(kind, archive, index)
        if GSA1.Log then
            GSA1.Log("texture", "texture %d of archive %d of character %d has no golden variant (%s): its gold draws use the "
                .. "game's texture", index, archive, kind, tostring(T.infoErrors[kind .. "_" .. archive .. "_" .. index
                .. "_v1"] or "?"))
        end
        gold = false
    end
    if not info then
        T.entries[key] = false
        return nil
    end
    local flags = bor(TF_NOMIP, TF_NOLOD)
    if band(wrap, WRAP_CLAMP_U) ~= 0 then flags = bor(flags, TF_CLAMPS) end
    if band(wrap, WRAP_CLAMP_V) ~= 0 then flags = bor(flags, TF_CLAMPT) end
    if band(wrap, WRAP_POINT) ~= 0 then flags = bor(flags, TF_POINTSAMPLE) end
    local rt = GetRenderTargetEx("gsa1_" .. T.format.name .. "_" .. key, info.w, info.h, RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE, flags, 0, T.format.fmt)
    e = { key = key, rt = rt, info = info, pos = 1, done = false, kind = kind, archive = archive, index = index,
          mask = band(wrap, WRAP_MASK) ~= 0, gold = gold }
    T.entries[key] = e
    T.created = T.created + 1
    enqueue(e, urgent)
    if why then
        prof("Texture target", t0)
        if GSA1.WarmRunning and GSA1.WarmRunning() then
            -- a new character's first frames while its pre-warm runs: counted with the pre-warm
            if GSA1.WarmTarget then GSA1.WarmTarget(SysTime() - t0) end
        elseif GSA1.Log then
            GSA1.Log("texture", "render target %s (%s, %dx%d, address mode %d) made at its %s in %.2f ms; %d runs to "
                .. "paint", rt:GetName(), tostring(info.name), info.w, info.h, wrap, why, (SysTime() - t0) * 1000,
                info.nruns or 0)
        end
    end
    return e
end

-- every texture of every archive of `kind` in the usual address mode (clamped), archive 0 first, except the archives of
-- T.NO_PREPARE (OBJ_REGULAR). 0.5.1: only listed here; their infos (gsa1.Texture: the module run-length encodes the
-- texels) and render targets are made a few per frame (LATER_BUDGET, the PostRender hook below), so a character's first
-- spawn is not one long frame; the textures its batches draw come first anyway (T.Get(..., urgent) from cl_render.lua)
function T.Prepare(kind)
    local a = T.Archives(kind)
    for ai = 0, a.n - 1 do
        if not T.NO_PREPARE[a[ai].name or ""] then
            for i = 0, (a[ai].count or 0) - 1 do
                T.later[#T.later + 1] = { kind, ai, i }
            end
        end
    end
end

function T.Pending()
    return #T.queue + #T.later
end

hook.Add("PostRender", "gsa1_texture_later", function()
    if #T.later == 0 then return end
    local t0 = SysTime()
    local n = 0
    while #T.later > 0 and (n == 0 or SysTime() - t0 < LATER_BUDGET) do
        local it = table.remove(T.later, 1)
        T.Get(it[1], it[2], it[3], bor(WRAP_CLAMP_U, WRAP_CLAMP_V), false)
        n = n + 1
    end
    if GSA1.HitchAdd then GSA1.HitchAdd("Texture info", SysTime() - t0) end
end)

-- a material that draws its vertex colour as it is (vgui/white): the "clear by drawing" fallback
local clear_mat = nil
local QV = { Vector(0, 0, 0), Vector(0, 0, 0), Vector(0, 0, 0), Vector(0, 0, 0) }

-- a 2D quad from (x0, y0) to (x1, y1) with UVs 0..1 and one colour (in cam.Start2D, with the material set); n: a
-- normal for lit materials (VertexLitGeneric's ambient cube gives black for none: the T3 check)
local function quad2d(x0, y0, x1, y1, r, g, b, a, n)
    QV[1]:SetUnpacked(x0, y0, 0)
    QV[2]:SetUnpacked(x1, y0, 0)
    QV[3]:SetUnpacked(x1, y1, 0)
    QV[4]:SetUnpacked(x0, y1, 0)
    mesh.Begin(QUADS, 1)
    for k = 1, 4 do
        mesh.Position(QV[k])
        if n then mesh.Normal(n) end
        mesh.TexCoord(0, (k == 2 or k == 3) and 1 or 0, k >= 3 and 1 or 0)
        mesh.Color(r, g, b, a)
        mesh.AdvanceVertex()
    end
    mesh.End()
end

-- (in cam.Start2D, blend ONE / ZERO for colour and alpha) every texel of a w x h target set to (r, g, b, a) by drawing
local function draw_fill(w, h, r, g, b, a)
    if not clear_mat then
        clear_mat = CreateMaterial("gsa1_clear", "UnlitGeneric", { ["$basetexture"] = "vgui/white", ["$vertexcolor"] = 1,
            ["$vertexalpha"] = 1, ["$translucent"] = 1, ["$ignorez"] = 1 })
    end
    render.SetMaterial(clear_mat)
    quad2d(0, 0, w, h, r, g, b, a)
end

local a0buf = {}   -- the alpha-0 runs of a slice (painted in a second pass: fix 2c), reused

-- paints up to `budget` runs of entry e; returns the number painted. The first slice clears the target (colour only, or
-- by drawing: T.clearMode). Runs with alpha > 0: their colour; runs with alpha 0 (the module leaves out (0,0,0,0), so
-- these carry RGB): the colour with alpha 0 (T.a0mode "exact") or alpha 1 ("alpha1"); a mask entry (WRAP_MASK): RGB =
-- the texel's alpha, alpha 255
local function paint_some(e, budget)
    local info = e.info
    local runs, nruns = info.runs, info.nruns
    local first = e.pos
    local last = math.min(nruns, first + budget - 1)
    local byte, setcolor, rect = string.byte, surface.SetDrawColor, surface.DrawRect
    local mask, exact = e.mask, T.a0mode ~= "alpha1"
    local drawclear = T.clearMode == "draw"
    render.PushRenderTarget(e.rt)
    render.OverrideAlphaWriteEnable(true, true)
    if first == 1 and not drawclear then
        -- colour only: the render target has no depth buffer, and a clear that asks for depth or stencil is dropped whole
        render.Clear(0, 0, 0, 0)
    end
    cam.Start2D()
    -- write the colour and the alpha as they are (no blending with the target)
    render.OverrideBlend(true, B_ONE, B_ZERO, FUNC_ADD, B_ONE, B_ZERO, FUNC_ADD)
    if first == 1 and drawclear then draw_fill(info.w, info.h, 0, 0, 0, 0) end
    draw.NoTexture()
    local na0 = 0
    for r = first, last do
        local o = (r - 1) * 10 + 1
        local x0, x1, y0, y1, l0, l1, cr, cg, cb, ca = byte(runs, o, o + 9)
        if mask then
            if ca > 0 then
                setcolor(ca, ca, ca, 255)
                rect(x0 + x1 * 256, y0 + y1 * 256, l0 + l1 * 256, 1)
            end
        elseif ca > 0 then
            setcolor(cr, cg, cb, ca)
            rect(x0 + x1 * 256, y0 + y1 * 256, l0 + l1 * 256, 1)
        elseif exact then
            na0 = na0 + 1
            a0buf[na0] = o
        else
            setcolor(cr, cg, cb, 1)
            rect(x0 + x1 * 256, y0 + y1 * 256, l0 + l1 * 256, 1)
        end
    end
    if na0 > 0 then
        -- alpha-0 texels with RGB, exactly: drawn with alpha 255 (vgui skips alpha 0), the colour written as it is and
        -- the alpha by the separate alpha blend ZERO / ZERO
        render.OverrideBlend(true, B_ONE, B_ZERO, FUNC_ADD, B_ZERO, B_ZERO, FUNC_ADD)
        for k = 1, na0 do
            local o = a0buf[k]
            local x0, x1, y0, y1, l0, l1, cr, cg, cb = byte(runs, o, o + 8)
            setcolor(cr, cg, cb, 255)
            rect(x0 + x1 * 256, y0 + y1 * 256, l0 + l1 * 256, 1)
        end
    end
    render.OverrideBlend(false)
    cam.End2D()
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    e.pos = last + 1
    if e.pos > nruns then e.done = true end
    return last - first + 1
end

-- an all-transparent texture: only the clear
local function clear_only(e)
    render.PushRenderTarget(e.rt)
    render.OverrideAlphaWriteEnable(true, true)
    if T.clearMode == "draw" then
        cam.Start2D()
        render.OverrideBlend(true, B_ONE, B_ZERO, FUNC_ADD, B_ONE, B_ZERO, FUNC_ADD)
        draw_fill(e.info.w, e.info.h, 0, 0, 0, 0)
        render.OverrideBlend(false)
        cam.End2D()
    else
        render.Clear(0, 0, 0, 0)
    end
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
end

-- what a batch material's parameters are (T.Material and the probe's sampling check): mode 0 opaque, 1 alpha test,
-- 2 translucent, 3 additive, 4 the shadow's mask (translucent, no fog; drawn with ZERO / ONE_MINUS_SRC_COLOR). alpha
-- (0.9.1, T.MaterialState: below 255 only for lit translucent and additive batches): $alpha, the material's alpha -
-- VertexLitGeneric ignores $vertexalpha, so a lit see-through copy's alpha must be the material's
local function material_params(mode, nocull, hl, tex, alpha)
    local params = {
        ["$model"] = 1,
        ["$vertexcolor"] = 1,           -- the module writes white RGB where the game ignores the vertex colour
        ["$nocull"] = nocull and 1 or 0,
        ["$basetexture"] = tex,
    }
    if mode == 4 then
        params["$translucent"] = 1        -- no depth writes; the blend is render.OverrideBlend's
        params["$nofog"] = 1              -- fog would pull the mask towards the fog colour
    elseif mode >= 2 then
        params["$vertexalpha"] = 1
        if mode == 3 then
            params["$additive"] = 1
        else
            params["$translucent"] = 1
        end
    elseif mode == 1 then
        params["$alphatest"] = 1          -- 1-bit texture alpha: cut-out
        params["$alphatestreference"] = 0.5
    end
    if hl then
        params["$halflambert"] = 1        -- the game's light palette wraps around the model softly
    end
    if alpha and alpha < 255 and mode >= 2 and mode <= 3 then
        params["$alpha"] = alpha / 255    -- (VertexLitGeneric: texture alpha x $alpha; the vertex alpha is ignored)
    end
    return params
end

-- The probe's texture (4 x 4; each row: texel A (200, 100, 50, 96) at x 0-1, texel B (255, 255, 255, 0) at x 2 - an
-- alpha-0 texel with RGB -, x 3 unpainted) as the module's runs
local PROBE_RUNS = nil
local function probe_runs()
    if not PROBE_RUNS then
        local t = {}
        for y = 0, 3 do
            t[#t + 1] = string.char(0, 0, y, 0, 2, 0, 200, 100, 50, 96)
            t[#t + 1] = string.char(2, 0, y, 0, 1, 0, 255, 255, 255, 0)
        end
        PROBE_RUNS = table.concat(t)
    end
    return PROBE_RUNS, 8
end

-- the painter's own path on the probe texture; returns the render target and the read-back alphas of A, B, C (nil when
-- render.ReadPixel gives no alpha) and A's RGB
local function probe_paint(f)
    local rt = GetRenderTargetEx("gsa1_probe_" .. f.name, 4, 4, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE,
        bor(TF_NOMIP, TF_NOLOD, TF_POINTSAMPLE), 0, f.fmt)
    if not rt then return nil end
    -- the target opaque first (drawn), so that the painter's clear is what makes the unpainted texel 0 - also when the
    -- probe runs again in a session (a render target keeps its contents)
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    cam.Start2D()
    render.OverrideBlend(true, B_ONE, B_ZERO, FUNC_ADD, B_ONE, B_ZERO, FUNC_ADD)
    draw_fill(4, 4, 9, 9, 9, 255)
    render.OverrideBlend(false)
    cam.End2D()
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    local runs, n = probe_runs()
    paint_some({ rt = rt, info = { w = 4, h = 4, runs = runs, nruns = n }, pos = 1 }, 1000)
    render.PushRenderTarget(rt)
    render.CapturePixels()
    local ar, ag, ab, aa = render.ReadPixel(0, 1)
    local _, _, _, ba = render.ReadPixel(2, 1)
    local _, _, _, ca = render.ReadPixel(3, 1)
    render.PopRenderTarget()
    return rt, aa, ba, ca, ar, ag, ab
end

-- what a translucent unlit batch material samples from the probe's render target: drawn the batches' way (a material
-- of T.Material's kind, render.SetMaterial and a mesh quad, SRC_ALPHA / ONE_MINUS_SRC_ALPHA) over white, 4 x 4 pixels
-- per texel into a 16 x 16 target; the centres of the A, B and C blocks of row 1
local function probe_sample(f, probe_rt)
    local st = GetRenderTargetEx("gsa1_probes_" .. f.name, 16, 16, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE,
        bor(TF_NOMIP, TF_NOLOD, TF_POINTSAMPLE), 0, f.fmt)
    if not st then return nil end
    local name = "gsa1m_probe_" .. f.name .. "_t010"
    local mat = T.mats[name]
    if not mat then
        mat = CreateMaterial(name, "UnlitGeneric", material_params(2, true, false, probe_rt:GetName()))
        T.mats[name] = mat
    end
    local in2d = false
    render.PushRenderTarget(st)
    local ok, res = pcall(function()
        render.OverrideAlphaWriteEnable(true, true)
        if T.clearMode ~= "draw" then render.Clear(255, 255, 255, 255) end
        cam.Start2D()
        in2d = true
        if T.clearMode == "draw" then
            render.OverrideBlend(true, B_ONE, B_ZERO, FUNC_ADD, B_ONE, B_ZERO, FUNC_ADD)
            draw_fill(16, 16, 255, 255, 255, 255)
        end
        render.SetMaterial(mat)
        render.OverrideBlend(true, B_SRC_ALPHA, B_ONE_MINUS_SRC_ALPHA, FUNC_ADD)
        quad2d(0, 0, 16, 16, 255, 255, 255, 255)
        render.OverrideBlend(false)
        cam.End2D()
        in2d = false
        render.OverrideAlphaWriteEnable(false)
        render.CapturePixels()
        local ar, ag, ab = render.ReadPixel(2, 6)
        local br, bg, bb = render.ReadPixel(10, 6)
        local cr, cg, cb = render.ReadPixel(14, 6)
        if not (ar and br and cr) then return nil end
        return { ar = ar, ag = ag, ab = ab, b = math.min(br, bg, bb), c = math.min(cr, cg, cb) }
    end)
    if in2d then cam.End2D() end
    render.OverrideBlend(false)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if not ok then return { err = tostring(res) } end
    return res
end

-- T3 (0.9.1; sadc docs/research/gsa1_070_translucency.md T3 as its review R2.4 corrected it): does VertexLitGeneric
-- honour $alpha on mesh draws in this Garry's Mod? Two lit quads (a normal, the engine lighting suppressed, a white
-- ambient cube, no fog) drawn the batches' way (SRC_ALPHA / ONE_MINUS_SRC_ALPHA) over BLACK into an 8 x 4 target: a
-- control with $alpha 1 and one with $alpha 128/255. Honoured: the second reads half the first where the framebuffer
-- blends in gamma space (128 of 255), 0.74 of it where it blends in linear light (188 of 255; T3b, 0.9.2a); ignored: the
-- same as the first ("lost"). A control darker than 32 (the lit quad not drawn as expected) decides nothing.
-- Returns { control, test, verdict = "ok" | "lost" | nil, space = "linear" | "gamma" | nil, why, err }.

-- T3b (0.9.2a; gsa1_091a_perf.md 3.4 with its review RC15): the verdict of a control / test pair (r.control, r.test: the
-- brightest channel read, 0..255); sets r.verdict, r.space (only when the two predictions are more than two tolerances
-- apart: a dark control cannot tell them apart), r.linear / r.gamma (the predictions) or r.why. Returns r.
local function srgb_dec(v) return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
local function srgb_enc(v) return v <= 0.0031308 and v * 12.92 or 1.055 * v ^ (1 / 2.4) - 0.055 end
function T.LitVerdict(r)
    if not (r and r.control and r.test) then return r end
    local a = 128 / 255
    local eg = r.control * a                                      -- gamma-space blending
    local el = 255 * srgb_enc(a * srgb_dec(r.control / 255))      -- linear-light blending
    local tol = math.max(6, r.control * 0.04)
    r.gamma, r.linear = eg, el
    local apart = math.abs(el - eg) > 2 * tol
    if r.control < 32 then
        r.why = "the lit control quad read " .. r.control
    elseif math.abs(r.test - el) <= tol then
        r.verdict, r.space = "ok", apart and "linear" or nil
    elseif math.abs(r.test - eg) <= tol then
        r.verdict, r.space = "ok", apart and "gamma" or nil
    elseif r.test >= r.control * 0.95 then
        r.verdict = "lost"
    else
        r.why = string.format("the $alpha 0.5 quad read %d of %d (linear light %.0f, gamma %.0f expected)", r.test,
            r.control, el, eg)
    end
    return r
end
local LIT_N = Vector(0, 0, 1)
local function lit_probe_material(name, alpha)
    local m = T.mats[name]
    if not m then
        local params = material_params(2, true, false, "vgui/white", alpha)
        params["$nofog"] = 1
        m = CreateMaterial(name, "VertexLitGeneric", params)
        T.mats[name] = m
    end
    return m
end
local function probe_lit(f)
    local st = GetRenderTargetEx("gsa1_probel_" .. f.name, 8, 4, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE,
        bor(TF_NOMIP, TF_NOLOD, TF_POINTSAMPLE), 0, f.fmt)
    if not st then return { why = "no render target" } end
    local ctl = lit_probe_material("gsa1m_probe_lit_a255", 255)
    local half = lit_probe_material("gsa1m_probe_lit_a128", 128)
    local in2d, suppressed = false, false
    render.PushRenderTarget(st)
    local ok, res = pcall(function()
        render.OverrideAlphaWriteEnable(true, true)
        if T.clearMode ~= "draw" then render.Clear(0, 0, 0, 255) end
        cam.Start2D()
        in2d = true
        if T.clearMode == "draw" then
            render.OverrideBlend(true, B_ONE, B_ZERO, FUNC_ADD, B_ONE, B_ZERO, FUNC_ADD)
            draw_fill(8, 4, 0, 0, 0, 255)
        end
        render.SuppressEngineLighting(true)
        suppressed = true
        render.ResetModelLighting(1, 1, 1)
        for i = 0, 5 do render.SetModelLighting(i, 1, 1, 1) end
        render.SetLocalModelLights()
        render.OverrideBlend(true, B_SRC_ALPHA, B_ONE_MINUS_SRC_ALPHA, FUNC_ADD)
        render.SetMaterial(ctl)
        quad2d(0, 0, 4, 4, 255, 255, 255, 255, LIT_N)
        render.SetMaterial(half)
        quad2d(4, 0, 8, 4, 255, 255, 255, 255, LIT_N)
        render.OverrideBlend(false)
        render.SuppressEngineLighting(false)
        suppressed = false
        cam.End2D()
        in2d = false
        render.OverrideAlphaWriteEnable(false)
        render.CapturePixels()
        local cr, cg, cb = render.ReadPixel(1, 1)
        local hr, hg, hb = render.ReadPixel(5, 1)
        if not (cr and hr) then return { why = "not readable" } end
        return { control = math.max(cr, cg, cb), test = math.max(hr, hg, hb) }
    end)
    if suppressed then render.SuppressEngineLighting(false) end
    if in2d then cam.End2D() end
    render.OverrideBlend(false)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if not ok then return { err = tostring(res) } end
    return T.LitVerdict(res)
end

-- "lit see-through materials: ok ($alpha 0.5 read 188 of 255; this Garry's Mod blends in linear light)" (T.FormatLine:
-- gsa1_status, the session log)
local SPACE_TEXT = { linear = "; this Garry's Mod blends in linear light", gamma = "; this Garry's Mod blends in gamma space" }
function T.LitLine()
    local l = T.lit
    if not l then return "lit see-through materials: not checked" end
    if l.verdict == "ok" then
        return string.format("lit see-through materials: ok ($alpha 0.5 read %d of %d%s)", l.test, l.control,
            SPACE_TEXT[l.space or ""] or "")
    elseif l.verdict == "lost" then
        return string.format("lit see-through materials: $alpha IGNORED (read %d of %d): the game's see-through copies "
            .. "are drawn with unlit materials instead (see-through, fullbright)", l.test, l.control)
    end
    return "lit see-through materials: not measured (" .. tostring(l.err or l.why or "?") .. ")"
end

-- The alpha probe of one format (in PostRender, once): the painter's own clear and runs on the probe texture, read back;
-- the fallbacks the read-back asks for (the unpainted texel is not 0: clear by drawing; the alpha-0 texel's alpha is
-- above 1: alpha 1), then what a translucent material samples. Returns { readable, painted, a0, clear, ok, why,
-- clearMode, a0mode, sample = { ar, ag, ab, b, c } }. The render target stack, the 2D context and the overrides are
-- restored whatever happens inside (paint_some / probe_sample).
local function probe_format(f)
    T.clearMode, T.a0mode = "clear", "exact"
    local res = { readable = false }
    local ok, err = pcall(function()
        local rt, a, b, c, ar = probe_paint(f)
        if not rt then return end
        res.r = ar
        if a == nil or b == nil or c == nil then return end
        res.readable = true
        if c > 2 then
            T.clearMode = "draw"
            res.clearFallback = c
            rt, a, b, c = probe_paint(f)
        end
        if b > 1 then
            T.a0mode = "alpha1"
            res.a0Fallback = b
            rt, a, b, c = probe_paint(f)
        end
        res.painted, res.a0, res.clear = a, b, c
        local why = {}
        if math.abs(a - 96) > 2 then why[#why + 1] = "the painted alpha" end
        if b > 1 then why[#why + 1] = "the alpha-0 texel" end
        if c > 2 then why[#why + 1] = "the clear" end
        res.ok = #why == 0
        res.why = table.concat(why, ", ")
        res.sample = probe_sample(f, rt)
    end)
    if not ok then res = { readable = false, err = tostring(err) } end
    res.clearMode, res.a0mode = T.clearMode, T.a0mode
    return res
end

function T.RunProbe()
    T.probe = {}
    for _, f in ipairs(RT_FORMATS) do T.probe[f.name] = probe_format(f) end
    local chosen = T.format
    if T.probe[chosen.name].readable and not T.probe[chosen.name].ok then
        for _, f in ipairs(RT_FORMATS) do
            if T.probe[f.name].ok then
                chosen = f
                break
            end
        end
    end
    if chosen ~= T.format then
        T.format = chosen
        GSA1.Msg("render targets: %s did not keep the alpha channel, using %s for new textures", RT_FORMATS[1].name,
            chosen.name)
    end
    local p = T.probe[T.format.name]
    T.clearMode, T.a0mode = p.clearMode or "clear", p.a0mode or "exact"
    -- T3: lit see-through materials (only where pixels can be read back at all)
    local was = T.litAlpha
    T.lit, T.litAlpha = nil, nil
    if p.readable then
        local okl, l = pcall(probe_lit, T.format)
        T.lit = okl and l or { err = tostring(l) }
        T.litAlpha = T.lit.verdict
    end
    if T.litAlpha == "lost" then
        GSA1.Msg("%s: please report this line", T.LitLine())
    end
    if (was == "lost") ~= (T.litAlpha == "lost") then
        -- the lit see-through materials change: the batches' materials are made again
        T.ForgetKeys()
        local C = GSA1.Char
        if C then
            C.matsDirty = true
            if GSA1.FreeStaticMeshes then GSA1.FreeStaticMeshes(C) end
        end
    end
    if p.readable and not p.ok then
        GSA1.Msg("%s: translucent effects may show as squares: please report this line", T.FormatLine())
    end
end

-- "render targets: BGRA8888, alpha kept (painted 96 -> 96, alpha 0 -> 0, unpainted -> 0; seen through a translucent
-- material: 237 214 208 / 255 / 255)" (236 214 209 expected in linear light, 234 197 178 in gamma space)
function T.FormatLine()
    local p = T.probe and T.probe[T.format.name]
    if not p then return "render targets: " .. T.format.name .. " (alpha probe not run yet)" end
    if not p.readable then
        return "render targets: " .. T.format.name .. " (alpha not readable here" .. (p.err and (": " .. p.err) or "")
            .. ")"
    end
    local s = p.sample
    local seen = (s and s.ar) and string.format("; seen through a translucent material: %d %d %d / %d / %d", s.ar, s.ag,
        s.ab, s.b, s.c) or "; what a material samples: not readable"
    local how = ""
    if p.a0mode == "alpha1" then how = how .. "; alpha-0 texels painted with alpha 1 (separate alpha blend not honoured)" end
    if p.clearMode == "draw" then how = how .. "; cleared by drawing (a colour clear did not clear)" end
    return string.format("render targets: %s, alpha %s (painted 96 -> %d, alpha 0 -> %d, unpainted -> %d%s)%s%s; %s",
        T.format.name, p.ok and "kept" or "LOST", p.painted, p.a0, p.clear, seen, how,
        p.ok and "" or (": " .. tostring(p.why) .. " failed"), T.LitLine())
end

function T.RepaintAll(why)
    T.paintWhy = why or "repainted"
    T.queue = {}
    for _, e in pairs(T.entries) do
        if e then
            e.pos, e.done, e.queued = 1, false, false
            enqueue(e, false)
        end
    end
end

-- painting under way: one "paint" line in the session log when the queue runs empty
local function paint_done()
    local P = T.paint
    T.paint = nil
    if P and GSA1.Log then
        GSA1.Log("paint", "%d textures (%d runs) painted in %.1f ms over %d frames (at most %.1f ms in one frame)%s",
            P.textures, P.runs, P.ms, P.frames, P.maxms, P.why and (": " .. P.why) or "")
    end
end

hook.Add("PostRender", "gsa1_texture_paint", GSA1.Guard and GSA1.Guard("Texture paint", function() T.PaintFrame() end)
    or function() T.PaintFrame() end)

local function paint_frame()
    local t0 = SysTime()
    if not T.probe then
        local ok, err = pcall(T.RunProbe)
        if not ok then
            T.probe = { [T.format.name] = { readable = false, err = tostring(err) } }
            GSA1.Msg("render target alpha probe failed: %s", tostring(err))
        end
    end
    if #T.queue == 0 then
        if T.paint then paint_done() end
        return
    end
    local P = T.paint
    if not P then
        P = { t0 = t0, frames = 0, runs = 0, textures = 0, ms = 0, maxms = 0, why = T.paintWhy }
        T.paint = P
        T.paintWhy = nil
    end
    local budget0 = GSA1.cv.paint_budget:GetInt()
    local budget = budget0
    while budget > 0 and #T.queue > 0 do
        local e = T.queue[1]
        if e.info.nruns == 0 then
            clear_only(e)
            e.done = true
        else
            budget = budget - paint_some(e, budget)
        end
        if e.done then
            e.queued = false
            table.remove(T.queue, 1)
            P.textures = P.textures + 1
        end
    end
    local ms = (SysTime() - t0) * 1000
    P.frames, P.runs, P.ms = P.frames + 1, P.runs + (budget0 - math.max(budget, 0)), P.ms + ms
    if ms > P.maxms then P.maxms = ms end
    if #T.queue == 0 then paint_done() end
    if GSA1.HitchAdd then GSA1.HitchAdd("Texture paint", SysTime() - t0) end
end

-- the probe and the painting, with the surface alpha multiplier at 1 (surface.SetDrawColor multiplies the alpha by it;
-- another addon may leave it set) and put back afterwards
function T.PaintFrame()
    local am = surface.GetAlphaMultiplier and surface.GetAlphaMultiplier()
    if am and am ~= 1 then surface.SetAlphaMultiplier(1) end
    local ok, err = pcall(paint_frame)
    if am and am ~= 1 then surface.SetAlphaMultiplier(am) end
    if not ok then error(err, 0) end
end

-- device-reset check (one painted texture's canary pixel), only after a device-reset signal: the window got the
-- focus back (alt-tab out of exclusive fullscreen loses the render targets), a resolution change; and gsa1_texcheck
-- (painted pixels against the module's; the shadow's masks are left out: they hold the alpha as colour)
local canary_at = nil           -- RealTime() when the canary is to be read (nil: no signal pending)
local had_focus = true
local check_request = nil
function T.CanarySignal(delay)
    canary_at = RealTime() + (delay or 0.5)
end
hook.Add("PostRender", "gsa1_texture_check", function()
    local focus = system.HasFocus()
    if focus and not had_focus then T.CanarySignal(0.5) end
    had_focus = focus
    if check_request and #T.queue == 0 then
        local req = check_request
        check_request = nil
        local textures, samples, bad, worst = 0, 0, 0, 0
        local asamples, abad, aworst, transparent = 0, 0, 0, 0
        for _, e in pairs(T.entries) do
            -- (0.9.4a: a golden variant's render target is left out: gsa1.TexturePixel reads the game's texture)
            if e and e.done and not e.mask and not e.gold then
                textures = textures + 1
                local w, h = e.info.w, e.info.h
                render.PushRenderTarget(e.rt)
                render.CapturePixels()
                for sy = 0, 7 do
                    for sx = 0, 7 do
                        local x, y = math.floor((sx + 0.5) * w / 8), math.floor((sy + 0.5) * h / 8)
                        local r, g, b, a = render.ReadPixel(x, y)
                        local er, eg, eb, ea = gsa1.TexturePixel(e.kind, e.archive, e.index, x, y)
                        if r and er then
                            samples = samples + 1
                            if a then
                                asamples = asamples + 1
                                local da = math.abs(a - ea)
                                if da > 2 then abad = abad + 1 end
                                aworst = math.max(aworst, da)
                                if ea < 255 then transparent = transparent + 1 end
                            end
                            -- RGB of fully transparent texels is never seen
                            local d = ea == 0 and 0 or math.max(math.abs(r - er), math.abs(g - eg), math.abs(b - eb),
                                a and math.abs(a - ea) or 0)
                            if d > 2 then
                                bad = bad + 1
                                if bad <= req.show then
                                    GSA1.Msg("texture %s (%s) at %d,%d: painted %d %d %d %s, decoded %d %d %d %d", e.key,
                                        e.info.name, x, y, r, g, b, tostring(a), er, eg, eb, ea)
                                end
                            end
                            worst = math.max(worst, d)
                        end
                    end
                end
                render.PopRenderTarget()
            end
        end
        GSA1.Msg("texture check: %d render targets, %d samples, %d differ by more than 2 (worst %d)", textures, samples,
            bad, worst)
        if asamples > 0 then
            GSA1.Msg("texture check, alpha: %d samples (%d not opaque), %d differ by more than 2 (worst %d)", asamples,
                transparent, abad, aworst)
        else
            GSA1.Msg("texture check, alpha: render.ReadPixel gives no alpha here, not checked")
        end
        GSA1.Msg("%s", T.FormatLine())
        return
    end
    if not canary_at or #T.queue > 0 or RealTime() < canary_at then return end
    canary_at = nil
    local t0 = SysTime()
    for _, e in pairs(T.entries) do
        local i = e and e.info
        if i and e.done and i.canary and not e.mask then
            render.PushRenderTarget(e.rt)
            render.CapturePixels()
            local r, g, b = render.ReadPixel(i.cx, i.cy)
            render.PopRenderTarget()
            if r and (math.abs(r - i.cr) > 8 or math.abs(g - i.cg) > 8 or math.abs(b - i.cb) > 8) then
                GSA1.Msg("textures were lost (device reset): repainting")
                T.RepaintAll("after a device reset")
            end
            break
        end
    end
    if GSA1.HitchAdd then GSA1.HitchAdd("Texture check", SysTime() - t0) end
end)

hook.Add("OnScreenSizeChanged", "gsa1_texture_repaint", function()
    T.RepaintAll("the screen size changed")
end)

concommand.Add("gsa1_texcheck", function(ply, cmd, args)
    if not GSA1.mod then GSA1.Msg("the module is not loaded") return end
    check_request = { show = tonumber(args[1] or "") or 10 }
    GSA1.Msg("checking the painted textures against the decoded ones (after painting finishes) ...")
end, nil, "G-SA1: compare the painted render targets with the module's decoded textures")

concommand.Add("gsa1_texrepaint", function()
    T.RepaintAll("gsa1_texrepaint")
end, nil, "G-SA1: paint every texture again")

-- PowerVR / Ninja blend factors (sa1_draw.blend_src / blend_dst) -> GMod BLEND_* (render.OverrideBlend)
T.BLEND_SRC = { [0] = 0, 1, 2, 3, 4, 5, 6, 7 }      -- OTHER_COLOR as source = the destination colour
T.BLEND_DST = { [0] = 0, 1, 9, 10, 4, 5, 6, 7 }     -- OTHER_COLOR as destination = the source colour

-- the render.OverrideBlend factors of a blended batch: the game's, or for the shadow's mask (WRAP_MASK) ZERO /
-- ONE_MINUS_SRC_COLOR (dst x (1 - mask x vertex colour) = dst x (1 - a x tex.a))
function T.BlendOf(b)
    if band(b.wrap or 0, WRAP_MASK) ~= 0 and band(b.flags or 0, DRAW_BLEND) ~= 0 then
        return B_ZERO, B_ONE_MINUS_SRC_COLOR
    end
    return T.BLEND_SRC[b.src] or 4, T.BLEND_DST[b.dst] or 5
end

-- 0.9.1 (T1): a batch's alpha - a lit translucent batch's vertex alpha, which the module puts at the end of its key
-- (".a170"; a module or a pre-warm state that gives the field: b.alpha); 255 for every other batch
local alphaOfKey = {}           -- [batch key] = its alpha (keys are few: a character's render states)
function T.BatchAlpha(b)
    local a = b.alpha
    if a then return a end
    local k = b.key
    if not k then return 255 end
    a = alphaOfKey[k]
    if not a then
        a = tonumber(string.match(k, "%.a(%d+)$")) or 255
        alphaOfKey[k] = a
    end
    return a
end

-- what a batch's material is under the current settings: mode (0 opaque, 1 alpha test, 2 translucent, 3 additive, 4 the
-- shadow's mask), lit (VertexLitGeneric, else UnlitGeneric), nocull, half-Lambert (palette-lit draws when lit) and
-- (0.9.1, T1) alpha: the material's $alpha - a lit translucent or additive batch's vertex alpha (T.BatchAlpha), 255 for
-- every other material (unlit ones honour the vertex alpha). Where the startup check saw VertexLitGeneric ignore $alpha
-- too (T.litAlpha "lost"), such a batch is unlit instead (see-through, but fullbright)
local MODE_LETTER = { [0] = "o", [1] = "a", [2] = "t", [3] = "x", [4] = "m" }
function T.MaterialState(b)
    local f = b.flags
    local nocull = GSA1.cv.nocull:GetBool() or band(f, DRAW_DOUBLE_SIDED) ~= 0
    if band(f, DRAW_BLEND) ~= 0 and band(b.wrap or 0, WRAP_MASK) ~= 0 then
        return 4, false, nocull, false, 255
    end
    local lit = GSA1.cv.lighting:GetBool() and band(f, DRAW_UNLIT) == 0
    local mode = 0
    if band(f, DRAW_BLEND) ~= 0 then
        mode = band(f, DRAW_ADDITIVE) ~= 0 and 3 or 2
    elseif band(f, DRAW_ALPHA_TEST) ~= 0 then
        mode = 1
    end
    local alpha = 255
    if lit and mode >= 2 then
        alpha = T.BatchAlpha(b)
        if alpha < 255 and T.litAlpha == "lost" then
            lit, alpha = false, 255
        end
    end
    return mode, lit, nocull, lit and band(f, DRAW_PALETTE_LIT) ~= 0, alpha
end

-- the material of a render batch (gsa1.Batches entry; cl_warm.lua's states too) under the current settings. warm:
-- made by the pre-warm (its time goes to the warm-up's figures; the texture is not pushed ahead of the painting)
function T.Material(kind, b, warm)
    local cache = T.byKey[kind]
    if not cache then
        cache = {}
        T.byKey[kind] = cache
    end
    local m = cache[b.key]
    if m then return m end
    local mode, lit, nocull, hl, alpha = T.MaterialState(b)
    local tex, texname = "vgui/white", "white"
    if b.archive >= 0 and b.tex >= 0 then
        local e = T.Get(kind, b.archive, b.tex, b.wrap, not warm, not warm and "first use" or nil)
        if e then
            tex = e.rt:GetName()
            texname = tex
        end
    end
    local name = string.format("gsa1m_%s_%s%d%d%d%s", texname, MODE_LETTER[mode], lit and 1 or 0, nocull and 1 or 0,
        hl and 1 or 0, alpha < 255 and ("_a" .. alpha) or "")
    m = T.mats[name]
    if not m then
        local params = material_params(mode, nocull, hl, tex, alpha)
        local shader = lit and "VertexLitGeneric" or "UnlitGeneric"
        local t0 = SysTime()
        m = CreateMaterial(name, shader, params)
        local dt = SysTime() - t0
        T.mats[name] = m
        T.nmats = (T.nmats or 0) + 1
        if warm or (GSA1.WarmRunning and GSA1.WarmRunning()) then
            -- the pre-warm's own, or the character's first frames' while the pre-warm runs: counted with it
            if GSA1.WarmCreated then GSA1.WarmCreated(name, dt, not warm) end
        else
            prof("Materials", t0)
            if GSA1.LogMaterial then
                GSA1.LogMaterial(name, shader, string.format("%s%s%s%s, batch %s", ({ [0] = "opaque", "alpha test",
                    "translucent", "additive", "shadow mask" })[mode], nocull and ", both sides" or "",
                    hl and ", half-Lambert" or "", alpha < 255 and (", $alpha " .. alpha .. "/255") or "",
                    tostring(b.key)), dt * 1000)
            end
        end
    end
    cache[b.key] = m
    return m
end

-- 0.9.2 (sadc docs/research/gsa1_090_render.md R1 with its review RC1 / RC2): the material an opaque batch is drawn with in
-- one of Source's DEPTH views - the SSAO / depth-pass view (VIEW_SSAO, render.GetResolvedFullFrameDepth: what GShader,
-- sun shafts, depth of field and bokeh read) and a lamp's or flashlight's shadow-depth view - where every model is drawn
-- with Source's DepthWrite shader. color: $color_depth 1 (the SSAO view reads the colour: the view depth / far in red),
-- else 0 (a shadow depth map is the depth buffer itself). $nocull as the colour material (the batch's both-sides flag or
-- gsa1_nocull); $model 1; an alpha-tested batch (T.MaterialState mode 1, a textured one) keeps its cut-out: $alphatest
-- with its texture's render target. One material per state (render target, alpha test, both sides, colour), named
-- "gsa1d_<render target or x>_<alpha test><both sides><colour>"; cached per batch key like T.Material and forgotten with
-- it (T.ForgetKeys). warm: made by the pre-warm (cl_warm.lua; counted with it, the texture not pushed ahead).
T.depthByKey = T.depthByKey or { [0] = {}, [1] = {} }
function T.DepthMaterial(kind, b, color, warm)
    local ck = color and 1 or 0
    local byKind = T.depthByKey[ck]
    local cache = byKind[kind]
    if not cache then
        cache = {}
        byKind[kind] = cache
    end
    local m = b.key and cache[b.key]
    if m then return m end
    local mode, _, nocull = T.MaterialState(b)
    local atest = mode == 1 and b.archive >= 0 and b.tex >= 0
    local tex = nil
    if atest then
        local e = T.Get(kind, b.archive, b.tex, b.wrap, not warm, not warm and "first use" or nil)
        if e then tex = e.rt:GetName() else atest = false end
    end
    local name = string.format("gsa1d_%s_%d%d%d", atest and tex or "x", atest and 1 or 0, nocull and 1 or 0, ck)
    m = T.mats[name]
    if not m then
        local params = { ["$color_depth"] = ck, ["$nocull"] = nocull and 1 or 0, ["$model"] = 1 }
        if atest then
            params["$alphatest"], params["$alphatestreference"], params["$basetexture"] = 1, 0.5, tex
        end
        local t0 = SysTime()
        m = CreateMaterial(name, "DepthWrite", params)
        local dt = SysTime() - t0
        T.mats[name] = m
        T.nmats = (T.nmats or 0) + 1
        if warm or (GSA1.WarmRunning and GSA1.WarmRunning()) then
            if GSA1.WarmCreated then GSA1.WarmCreated(name, dt, not warm) end
        else
            prof("Materials", t0)
            if GSA1.LogMaterial then
                GSA1.LogMaterial(name, "DepthWrite", string.format("depth (%s)%s%s, batch %s", color and
                    "$color_depth 1: the depth pass" or "shadow depth", atest and ", alpha test" or "",
                    nocull and ", both sides" or "", tostring(b.key)), dt * 1000)
            end
        end
    end
    if b.key then cache[b.key] = m end
    return m
end

-- the materials of the batch keys depend on the settings (lighting, both sides): forget them when those change
function T.ForgetKeys()
    T.byKey = {}
    T.depthByKey = { [0] = {}, [1] = {} }
end
