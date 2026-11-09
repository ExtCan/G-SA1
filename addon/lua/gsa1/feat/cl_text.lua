-- G-SA1 text in a chosen font, the client part (round 0.9.9g; the pure part is feat/sh_text.lua, which says what may and may not be here). Takes (text, font, size, colour), makes it once into a picture at the game's current
-- resolution and draws it from then on. Until the picture is ready, and when anything refuses, the element draws as it does without this file: its caller keeps its own draw.SimpleText.
-- 1.0.0-beta1a (the owner's beta 1 test: "the upgrade name textures have no alpha"; sadc/build/research/b1a/b1a-text/NOTES.md): beta 1 drew each text into a render target and saved it with render.Capture as a
-- PNG. MEASURED on the owner's PC: every one of those PNGs is RGB (colour type 2) on opaque black, and the "white specks" are the picture before's letters (1790 of LIGHT SPEED SHOES' 1790 white pixels sit
-- where CHOOSE YOUR UPGRADE, made just before it into the same 1024 x 128 bucket, had its letters). The render targets were never cleared: render.Clear(r, g, b, 0, true, true) asks for a depth clear of a
-- target without a depth buffer, which Direct3D 9 drops whole (cl_textures.lua 0.8, measured), and the "replace draw" was surface.DrawRect at alpha 0, which vgui never draws (the same notes). So every
-- picture sat on Source's opaque black creation colour, and the PNG had nothing to keep (the spawn icons, captured the same way from targets that ARE cleared, came out RGBA in the same session).
-- NOW: no PNG is written or read. A picture is a part of one page of a render-target atlas (sh_text.lua T.PAGES pages of T.PAGE_W x T.PAGE_H; full: the least recently shown page is emptied and its
-- pictures are made again when next shown), made and drawn exactly like cl_textures.lua's textures, which the owner's game shows right: a BGRA8888 target without depth, cleared colour-only and by
-- the ONE / ZERO draw with a separate alpha factor of ZERO (the alpha probe of every owner log reads it back as 0), and an UnlitGeneric material with $vertexcolor, $vertexalpha and $translucent ($nocull
-- and $ignorez as cl_hud.lua's). Lost with a device reset (a canary texel is read after the window gets the focus back) or a new resolution: made again on demand. feat/cl_skinhud.lua paints the skins'
-- names and plates into the same pages (T.Place, T.PaintPic, T.ReadPic). UNVERIFIED in game until the owner's next session: the log's "text pictures:" lines say what the game read back.
-- 1.0.0-beta1a, the verifier's MEDIUM: THE READ-BACK DECIDES. After each start or reset the first picture made is read back (T.AlphaCheck). No picture is handed out before it reads right; if it
-- reads wrong (a box round the letters, or letters without alpha) none is handed out at all: the texts stay drawn with the font, as without this file, and the log says why.
-- THE NAMES FIX after beta 1a (sadc/build/research/b1a2; the owner: "The pulsating names appear for a second and then turn into black squares"): the skins' names and plates were the only pictures in a
-- render target of their own (T.Canvas, 1024 x 256 / 2048 x 256), drawn smaller than their texels through mesh, never read again after the make. Retired: feat/cl_skinhud.lua makes them as parts of
-- these atlas pages (T.Place, T.PaintPic, T.ReadPic), the path that kept the bar's labels right in the owner's game, and T.CheckLost now reads the canary of every page that holds pictures.
-- THE SMALL READ (b1a2-fix2, the names fix's verifier): a check read a few texels with one render.CapturePixels of a whole 2048 x 1024 page (8 MiB; with mat_queue_mode -1 a capture waits for the render
-- thread). T.ReadTexels now draws each texel it is asked for through its page's OWN material (render.SetMaterial and a mesh quad, ONE / ZERO for colour and alpha: cl_textures.lua probe_sample's path,
-- which reads right in the owner's game) into a 2 x 2 cell of one 16 x 4 target made like cl_textures.lua's probes, and reads that target (256 bytes). What it reads is what the material samples, so
-- a page whose material samples something else reads wrong too. THE CANARY is compared with what this same read gave right after the page's make (p.canary0), not with the painted constant
-- (the constant is only a line in the log when the two differ); a page whose canary reads otherwise than painted is said once and still works.
GSA1 = GSA1 or {}
local T = GSA1.Text
if not T then error("gsa1/feat/sh_text.lua did not load: the text needs it") end

T.cv = T.cv or GSA1.ConVar("gsa1_text_fonts", 1, "Use the fonts in garrysmod/resource/fonts on G-SA1's own reminder and skin line (off: today's fonts). At once", 0, 1)
local cv = T.cv

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("text", fmt, ...) end
end

T.probe = T.probe or {}     -- [font] = { there =, taken =, why = }
T.mem = T.mem or {}         -- [key] = a picture { mat, w, h, u0, v0, u1, v1, page, gen } | { waiting = true } | { failed = true }
T.nmem = T.nmem or 0
T.queue = T.queue or {}
T.stats = T.stats or { made = 0, failed = 0, emptied = 0, lost = 0, old = 0 }
T.said = T.said or {}
T.pages = T.pages or {}     -- the atlas (sh_text.lua T.NewPage + rt, mat)
T.check = T.check or { tries = 0 }   -- the read-back of the first pictures (T.AlphaCheck): state nil (not yet), "ok", "unreadable" (drawn unchecked) or "bad" (none handed out); why

local created = {}
local function make_font(id, family, size, weight)
    if not created[id] then
        surface.CreateFont(id, { font = family, size = size, weight = weight, antialias = true, extended = true })
        created[id] = true
    end
    return id
end

-- (these two run every frame an element shows: once a text is known they make no garbage)
local ids = {}
local function font_id(key, size)
    local by = ids[key]
    if not by then
        by = {}
        ids[key] = by
    end
    local id = by[size]
    if not id then
        local f = T.FONTS[key]
        id = make_font("GSA1Text_" .. key .. "_" .. tostring(size), f.family, size, f.weight or 400)
        by[size] = id
    end
    return id
end
T.FontId = font_id

local names, nnames = {}, 0
local function name_of(text, font, size, color, sw, sh, outline)
    local n = names[text]
    outline = outline or 0
    if n and n.font == font and n.size == size and n.r == color.r and n.g == color.g and n.b == color.b and n.a == (color.a or 255) and n.sw == sw and n.sh == sh and n.ol == outline then
        return n.name
    end
    if not n then
        nnames = nnames + 1
        if nnames > T.MAX_MEM then
            names, nnames = {}, 1
        end
        n = {}
        names[text] = n
    end
    n.font, n.size, n.r, n.g, n.b, n.a, n.sw, n.sh, n.ol = font, size, color.r, color.g, color.b, color.a or 255, sw, sh, outline
    n.name = T.FileName(text, font, size, color, sw, sh, outline)
    return n.name
end

-- Is the font there, and did the engine take it? A family the engine does not know comes out in Windows' default face, so the test line measures exactly as it does with a family that cannot exist. That is how the log tells
-- "the .otf did not load" from "it did" (the engine says nothing itself)
T.PROBE_LINE = "Sonic Adventure 0123456789"
T.NO_SUCH_FAMILY = "GSA1 no such font"
function T.Probe(key)
    local p = T.probe[key]
    if p then return p end
    local f = T.FONTS[key]
    p = { there = false, taken = false }
    T.probe[key] = p
    if not f then
        p.why = "no such font in the table"
        return p
    end
    -- (1.0.0: a family Windows has, f.system, has no file to look for: the engine is only asked)
    p.there = f.system == true or file.Exists(T.FONT_DIR .. "/" .. tostring(f.file), "GAME") == true
    if not p.there then
        p.why = f.file .. " is not in garrysmod/resource/fonts"
    elseif not (surface.CreateFont and surface.SetFont and surface.GetTextSize) then
        p.why = "this game has no surface.CreateFont"
    else
        local weight = f.weight or 400
        local none = make_font("GSA1TextProbeNone_" .. tostring(weight), T.NO_SUCH_FAMILY, 64, weight)
        local its = make_font("GSA1TextProbe_" .. key, f.family, 64, weight)
        surface.SetFont(none)
        local w0, h0 = surface.GetTextSize(T.PROBE_LINE)
        surface.SetFont(its)
        local w1, h1 = surface.GetTextSize(T.PROBE_LINE)
        p.widths = { w0, w1 }
        if w0 == w1 and h0 == h1 then
            p.why = (f.system and (f.family .. " is not on this PC") or (f.file .. " is there, but the engine did not take it")) .. ": the test line measures " .. tostring(w1) .. " px, the same as with a font that does not exist"
        else
            p.taken = true
        end
    end
    if p.taken then
        log("font %s: %s is there and the engine took it (the test line: %s px, %s px with no font)", f.title, f.system and "Windows' own" or f.file, tostring(p.widths[2]), tostring(p.widths[1]))
    else
        log("font %s: not used: %s", f.title, p.why)
    end
    return p
end

-- the font key an element draws with now (nil: today's engine font): its own if it was found and the option is on; 1.0.0: else the Windows family it names (e.system), if the engine has it
function T.Pick(name)
    local e = T.ELEMENTS[name]
    if not e then return nil end
    if cv:GetBool() and e.font and T.Probe(e.font).taken then return e.font end
    if e.system and T.Probe(e.system).taken then return e.system end
    return nil
end

-- the font an element draws with now: T.Pick's, else today's. The log says which, once
function T.FontFor(name, size)
    local e = T.ELEMENTS[name]
    local key = T.Pick(name)
    if not T.said[name] then
        T.said[name] = true
        if key and key == e.font then
            log("%s: %s", e.title, T.FONTS[key].title)
        elseif key then
            log("%s: %s (%s)", e.title, T.FONTS[key].title, cv:GetBool() and (T.Probe(e.font).why or "?") or "the option is off")
        elseif cv:GetBool() or e.system then
            log("%s: today's %s (%s)", e.title, e.fallback, (e.font and T.Probe(e.font).why) or "?")
        end
    end
    if key then return font_id(key, size) end
    return e.fallback
end

-- the known texts' table keeps to its bound: past it, only the pictures still on their pages stay
local function remember(name, m)
    if T.mem[name] == nil then T.nmem = T.nmem + 1 end
    T.mem[name] = m
    if T.nmem > T.MAX_MEM then
        local keep, n = {}, 0
        for k, v in pairs(T.mem) do
            if v.page and v.gen == v.page.gen then
                keep[k] = v
                n = n + 1
            end
        end
        T.mem, T.nmem = keep, n
    end
end

-- an outline: a width in px (black), or { width, r, g, b }; -> width, colour, the key that names it
local BLACK = { r = 0, g = 0, b = 0 }
local okeys = {}
local function outline_of(o)
    if type(o) == "table" then
        local w = tonumber(o[1]) or 0
        local k = tostring(w) .. ":" .. tostring(o[2]) .. "," .. tostring(o[3]) .. "," .. tostring(o[4])
        local c = okeys[k]
        if not c then
            c = { r = tonumber(o[2]) or 0, g = tonumber(o[3]) or 0, b = tonumber(o[4]) or 0 }
            okeys[k] = c
        end
        return w, c, k
    end
    local w = tonumber(o) or 0
    return w, BLACK, w
end
T.OutlineOf = outline_of

-- THE PROVEN PATH: render targets, clears and materials as cl_textures.lua's textures -------------------------------------------------------------------------------------------------------------------------
local bor = bit.bor
local B_ZERO, B_ONE, B_SRC_ALPHA, B_ONE_MINUS_SRC_ALPHA, F_ADD = 0, 1, 4, 5, 0
T.RT_FLAGS = bor(0x100, 0x200, 0x4, 0x8)      -- NOMIP, NOLOD, CLAMPS, CLAMPT (cl_textures.lua T.Get)
T.CANARY_RGB = { 37, 201, 93 }                  -- a texel in the last rows of each target, at alpha 0: read after the window gets the focus back

-- the format cl_textures.lua's probe chose (BGRA8888 keeps alpha on the owner's setups), its alpha-0 way and its clear way
local function rt_format()
    local X = GSA1.Tex
    return X and X.format or { name = "BGRA8888", fmt = IMAGE_FORMAT_BGRA8888 or 12 }
end
local function exact_a0()
    local X = GSA1.Tex
    return not (X and X.a0mode == "alpha1")
end
local function colour_clear()
    local X = GSA1.Tex
    return not (X and X.clearMode == "draw")
end

-- the material of a target: cl_hud.lua's translucent one (the game's own 2D draws on Character Select use exactly these)
function T.MaterialParams(tex)
    return { ["$basetexture"] = tex, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$translucent"] = 1, ["$nocull"] = 1, ["$ignorez"] = 1 }
end

local function new_target(name, w, h)
    local f = rt_format()
    local rt = GetRenderTargetEx(name .. "_" .. f.name, w, h, RT_SIZE_LITERAL or 1, MATERIAL_RT_DEPTH_NONE or 2, T.RT_FLAGS, 0, f.fmt)
    local mat = CreateMaterial(name .. "_" .. f.name, "UnlitGeneric", T.MaterialParams(rt:GetName()))
    return rt, mat, f.name
end

-- (inside T.Paint) a rectangle set to (r, g, b) at alpha 0, whatever was there: colour ONE / ZERO, alpha ZERO / ZERO (cl_textures.lua's alpha-0 texels: "exact"), or alpha 1 where the probe saw the
-- separate alpha factors ignored ("alpha1": at most 1/255 off). vgui never draws alpha 0 itself: the colour goes at 255 and the blend writes the 0
function T.ClearRect(x, y, w, h, r, g, b)
    draw.NoTexture()
    if exact_a0() then
        render.OverrideBlend(true, B_ONE, B_ZERO, F_ADD, B_ZERO, B_ZERO, F_ADD)
        surface.SetDrawColor(r, g, b, 255)
    else
        render.OverrideBlend(true, B_ONE, B_ZERO, F_ADD, B_ONE, B_ZERO, F_ADD)
        surface.SetDrawColor(r, g, b, 1)
    end
    surface.DrawRect(x, y, w, h)
end

-- (inside T.Paint) a rectangle replaced by (r, g, b, a), colour and alpha written as they are (cl_textures.lua's painter)
function T.FillRect(x, y, w, h, r, g, b, a)
    draw.NoTexture()
    render.OverrideBlend(true, B_ONE, B_ZERO, F_ADD, B_ONE, B_ZERO, F_ADD)
    surface.SetDrawColor(r, g, b, a or 255)
    surface.DrawRect(x, y, w, h)
end

-- (inside T.Paint) letters over what is there: colour SRC_ALPHA / ONE_MINUS_SRC_ALPHA, alpha ONE / ONE_MINUS_SRC_ALPHA (the "over" of the letter's coverage)
function T.TextBlend()
    render.OverrideBlend(true, B_SRC_ALPHA, B_ONE_MINUS_SRC_ALPHA, F_ADD, B_ONE, B_ONE_MINUS_SRC_ALPHA, F_ADD)
end

-- paints into a target t = { rt, w, h, fresh [, rw, rh] }: fn() draws (in cam.Start2D, the surface alpha multiplier at 1). A fresh target is cleared whole first (colour only, then by drawing: rw x rh, the
-- render target's size, where its pictures keep to w x h); its canary is set after fn, at the bottom left of w x h (x 0..1: inside any screen's width). b1a2-fix2: after the first paint of a page's
-- generation (made, emptied, lost) its canary is read once through the small read (T.NoteCanary): what later reads are compared with
function T.Paint(t, fn)
    local am = surface.GetAlphaMultiplier and surface.GetAlphaMultiplier()
    if am and am ~= 1 then surface.SetAlphaMultiplier(1) end
    render.PushRenderTarget(t.rt)
    render.OverrideAlphaWriteEnable(true, true)
    if t.fresh and colour_clear() then render.Clear(0, 0, 0, 0) end         -- (colour only: the target has no depth buffer, and a clear that asks for one is dropped whole)
    cam.Start2D()
    local ok, err = pcall(function()
        if t.fresh then
            T.ClearRect(0, 0, t.rw or t.w, t.rh or t.h, 0, 0, 0)
            t.fresh = false
        end
        fn()
        local c = T.CANARY_RGB
        T.ClearRect(0, t.h - 2, 2, 2, c[1], c[2], c[3])
    end)
    render.OverrideBlend(false)
    cam.End2D()
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if am and am ~= 1 then surface.SetAlphaMultiplier(am) end
    if ok and t.index and t.canaryGen ~= t.gen and T.NoteCanary then
        t.canaryGen = t.gen
        T.NoteCanary(t)
    end
    return ok, err
end

-- reads a target back (render.CapturePixels, as cl_textures.lua's probe): fn(read) with read(x, y) -> r, g, b, a (nil: not readable); its result, or nil and the error. A WHOLE target: the make's
-- reads only (T.AlphaCheck, T.ReadPic); the checks read through T.ReadTexels
function T.ReadBack(t, fn)
    render.PushRenderTarget(t.rt)
    local ok, res = pcall(function()
        render.CapturePixels()
        return fn(render.ReadPixel)
    end)
    render.PopRenderTarget()
    if not ok then return nil, res end
    return res
end

-- THE SMALL READ (b1a2-fix2) -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- a target of T.READ_W x T.READ_H made like cl_textures.lua's probes (gsa1_probe_* 4 x 4, gsa1_probes_* 16 x 16, gsa1_probel_* 8 x 4: no depth, no mips, point sampled, its probed format); each
-- texel asked for fills a T.READ_CELL x T.READ_CELL cell, read at the cell's (1, 1): inside the cell whatever half-pixel rule the rasteriser keeps. Before each copy the target is filled with
-- T.READ_FILL (alpha 77): a copy that drew nothing reads that, never an old read's texels
T.READ_W, T.READ_H, T.READ_CELL = 16, 4, 2
T.READ_FILL = { 255, 0, 255, 77 }
T.READ_FLAGS = bor(0x100, 0x200, 0x1)              -- NOMIP, NOLOD, POINTSAMPLE (cl_textures.lua's probes)
T.CANARY_TOL = 8                                   -- a canary channel may differ this much from its make's read (sh_skinhud.lua H.CHECK_TOL)
local readers = {}
function T.Reader()
    local f = rt_format()
    local r = readers[f.name]
    if not r then
        local rt = GetRenderTargetEx("gsa1_textread_" .. f.name, T.READ_W, T.READ_H, RT_SIZE_LITERAL or 1, MATERIAL_RT_DEPTH_NONE or 2, T.READ_FLAGS, 0, f.fmt)
        if not rt then return nil end
        r = { rt = rt, w = T.READ_W, h = T.READ_H, fmt = f.name, name = rt.GetName and rt:GetName() or ("gsa1_textread_" .. f.name) }
        readers[f.name] = r
    end
    return r
end

-- one cell: a quad whose four corners all sample the texel's centre (u, v), so every pixel it covers is exactly that texel whether the material filters bilinearly or by points (the page's
-- target is not point sampled) and wherever the rasteriser puts a pixel's centre; the vertex colour white at 255 ($vertexcolor, $vertexalpha: the texel as it is)
local QV = nil
local function cell_quad(x0, y0, x1, y1, u, v)
    if not QV then QV = { Vector(0, 0, 0), Vector(0, 0, 0), Vector(0, 0, 0), Vector(0, 0, 0) } end
    QV[1]:SetUnpacked(x0, y0, 0)
    QV[2]:SetUnpacked(x1, y0, 0)
    QV[3]:SetUnpacked(x1, y1, 0)
    QV[4]:SetUnpacked(x0, y1, 0)
    mesh.Begin(MATERIAL_QUADS or 7, 1)
    for k = 1, 4 do
        mesh.Position(QV[k])
        mesh.TexCoord(0, u, v)
        mesh.Color(255, 255, 255, 255)
        mesh.AdvanceVertex()
    end
    mesh.End()
end

-- list[i0..i1] (at most a target's cells) copied and read into out[i] = { r, g, b, a }; -> true, or false and why. The render target stack, the 2D context and the overrides are restored whatever happens
local function copy_read(rd, list, i0, i1, out)
    local cell = T.READ_CELL
    local per_row = math.floor(rd.w / cell)
    local am = surface.GetAlphaMultiplier and surface.GetAlphaMultiplier()
    if am and am ~= 1 then surface.SetAlphaMultiplier(1) end
    local in2d = false
    render.PushRenderTarget(rd.rt)
    local ok, err = pcall(function()
        render.OverrideAlphaWriteEnable(true, true)
        cam.Start2D()
        in2d = true
        local s = T.READ_FILL
        T.FillRect(0, 0, rd.w, rd.h, s[1], s[2], s[3], s[4])
        render.OverrideBlend(true, B_ONE, B_ZERO, F_ADD, B_ONE, B_ZERO, F_ADD)
        local last = nil
        for i = i0, i1 do
            local q = list[i]
            local p = q.page
            if p.mat ~= last then
                render.SetMaterial(p.mat)
                last = p.mat
            end
            local k = i - i0
            local cx, cy = (k % per_row) * cell, math.floor(k / per_row) * cell
            cell_quad(cx, cy, cx + cell, cy + cell, (q.x + 0.5) / (p.rw or p.w), (q.y + 0.5) / (p.rh or p.h))
        end
        render.OverrideBlend(false)
        cam.End2D()
        in2d = false
        render.OverrideAlphaWriteEnable(false)
        render.CapturePixels()
        for i = i0, i1 do
            local k = i - i0
            local r, g, b, a = render.ReadPixel((k % per_row) * cell + 1, math.floor(k / per_row) * cell + 1)
            if r == nil or a == nil then error("render.ReadPixel gave nothing", 0) end
            out[i] = { r, g, b, a }
        end
    end)
    if in2d then cam.End2D() end
    render.OverrideBlend(false)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if am and am ~= 1 then surface.SetAlphaMultiplier(am) end
    return ok, err
end

-- the texels list[i] = { page =, x =, y = } (page px) as each page's material draws them: -> { { r, g, b, a }, ... }, nil, ms; or nil, why, ms. One copy and one capture of the small target per
-- T.READ_W / T.READ_CELL x T.READ_H / T.READ_CELL texels (16: a check needs 5)
function T.ReadTexels(list)
    local t0 = SysTime()
    local rd = T.Reader()
    if not rd then return nil, "no render target to read through", 0 end
    local per = math.floor(rd.w / T.READ_CELL) * math.floor(rd.h / T.READ_CELL)
    local out, i0 = {}, 1
    while i0 <= #list do
        local i1 = math.min(#list, i0 + per - 1)
        local ok, err = copy_read(rd, list, i0, i1, out)
        if not ok then return nil, tostring(err), (SysTime() - t0) * 1000 end
        i0 = i1 + 1
    end
    local ms = (SysTime() - t0) * 1000
    T.stats.smallReads = (T.stats.smallReads or 0) + 1
    T.lastRead = { n = #list, ms = ms }
    return out, nil, ms
end

-- the colour the canary was painted in (cl_textures.lua's alpha-0 way: 0, or 1 where the separate alpha factors are ignored)
function T.CanaryPainted()
    local c = T.CANARY_RGB
    return { c[1], c[2], c[3], exact_a0() and 0 or 1 }
end

-- a canary read c against a reference (its make's read): true when a channel differs by more than T.CANARY_TOL
function T.CanaryOff(c, ref)
    for i = 1, 4 do
        if math.abs((c[i] or 0) - (ref[i] or 0)) > T.CANARY_TOL then return true end
    end
    return false
end

local function rgba(c) return string.format("%d %d %d %d", c[1] or -1, c[2] or -1, c[3] or -1, c[4] or -1) end
T.RGBA = rgba

-- (T.Paint, after the first paint of a page's generation; feat/cl_skinhud.lua's make when that read gave nothing) its canary through the small read, or c as such a read gave it: p.canary0, what
-- every later read of it is compared with. Its colour not what was painted (a colour space, a rounding): kept, said once a page. Its ALPHA not the painted one (no colour space touches alpha: the
-- material does not sample what was painted): not kept, said once a page, the painted colour stays the reference
function T.NoteCanary(p, c)
    if not c then
        local got = T.ReadTexels({ { page = p, x = 1, y = p.h - 1 } })
        c = got and got[1]
    end
    p.canary0 = nil
    if not c then return nil end
    local painted = T.CanaryPainted()
    local idx = tostring(p.index)
    if math.abs((c[4] or 255) - painted[4]) > T.CANARY_TOL then
        if not T.said["canary_a_" .. idx] then
            T.said["canary_a_" .. idx] = true
            log("text pictures: page %d's canary reads %s at its make through its material, its alpha not the painted %s: the material does not sample what was painted; it is compared with the painted colour",
                p.index or 0, rgba(c), rgba(painted))
        end
        return nil
    end
    p.canary0 = c
    if T.CanaryOff(c, painted) and not T.said["canary_c_" .. idx] then
        T.said["canary_c_" .. idx] = true
        log("text pictures: page %d's canary reads %s at its make through its material (painted %s): later reads of it are compared with what it read at the make, not with the painted colour; the pages work as before",
            p.index or 0, rgba(c), rgba(painted))
    end
    return c
end

-- the characters of a text (UTF-8)
local function chars(text)
    local out = {}
    for ch in string.gmatch(text, "[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

-- an outline's offsets: a disc of radius r px (a grid of step r / 5, at least 1) and its rim at 16 points
local discs = {}
local function disc(r)
    local d = discs[r]
    if d then return d end
    d = {}
    local s = math.max(1, math.floor(r / 5))
    local n = math.floor(r / s)
    for iy = -n, n do
        for ix = -n, n do
            local dx, dy = ix * s, iy * s
            if (dx ~= 0 or dy ~= 0) and dx * dx + dy * dy <= r * r + r then d[#d + 1] = { dx, dy } end
        end
    end
    if s > 1 then
        for a = 0, 15 do d[#d + 1] = { math.cos(a * math.pi / 8) * r, math.sin(a * math.pi / 8) * r } end
    end
    discs[r] = d
    return d
end
T.Disc = disc

-- the advance of each letter in the font's px with a space's advance times `space` and `track` target px after each letter (sx: the target px per font px sideways); -> { { ch, x }, ... }, width
function T.Layout(text, font, track, space, sx)
    surface.SetFont(font)
    local per, x = {}, 0
    local list = chars(text)
    for i, ch in ipairs(list) do
        local w = tonumber((surface.GetTextSize(ch))) or 0
        per[i] = { ch, x }
        x = x + (ch == " " and w * (space or 1) or w)
        if i < #list then x = x + (track or 0) / (sx or 1) end
    end
    return per, x
end

-- (inside T.Paint) a line of letters. s = { text, font, x, y (the line box's top left, target px), color, outline (target px), ocolor, track (target px between letters), space (a space's advance x this),
-- sx, sy (target px per font px: drawn through cam.PushModelMatrix when not 1), bold (target px: the fill drawn this far either side too) }. Outline first, all round, then the fill on top
function T.DrawLetters(s)
    local sx, sy = s.sx or 1, s.sy or 1
    local scaled = sx ~= 1 or sy ~= 1
    local per = nil
    if (s.track or 0) ~= 0 or (s.space or 1) ~= 1 then per = T.Layout(s.text, s.font, s.track, s.space, sx) end
    local ox, oy = s.x, s.y
    if scaled then
        local m = Matrix()
        m:Translate(Vector(s.x, s.y, 0))
        m:Scale(Vector(sx, sy, 1))
        cam.PushModelMatrix(m, true)
        ox, oy = 0, 0
    end
    local ok, err = pcall(function()
        surface.SetFont(s.font)
        local function line(dx, dy)
            if per then
                for i = 1, #per do
                    surface.SetTextPos(ox + per[i][2] + dx, oy + dy)
                    surface.DrawText(per[i][1])
                end
            else
                surface.SetTextPos(ox + dx, oy + dy)
                surface.DrawText(s.text)
            end
        end
        T.TextBlend()
        local c = s.color
        local ol = s.outline or 0
        if ol > 0 then
            local oc = s.ocolor or BLACK
            surface.SetTextColor(oc.r, oc.g, oc.b, c.a or 255)
            for _, d in ipairs(disc(ol)) do line(d[1] / sx, d[2] / sy) end
        end
        surface.SetTextColor(c.r, c.g, c.b, c.a or 255)
        local b = math.floor(s.bold or 0)
        if b > 0 then
            for dx = -b, b do line(dx / sx, 0) end
        else
            line(0, 0)
        end
    end)
    if scaled then cam.PopModelMatrix() end
    if not ok then error(err, 0) end
end

-- THE ATLAS ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- the part of a page its pictures go in: the whole page, or as much of it as the screen covers where the screen is smaller (UNVERIFIED whether Garry's Mod draws into, or reads back, a render target
-- past the screen's size: this keeps every picture and the canary inside it either way). A screen of at least T.PAGE_W x T.PAGE_H, as the owner's 3440 x 1440, has the whole page
local function page_bound()
    local sw, sh = tonumber(ScrW and ScrW()), tonumber(ScrH and ScrH())
    if not (sw and sh) or sw <= 0 or sh <= 0 then return T.PAGE_W, T.PAGE_H end     -- (no screen size yet: the whole page)
    return math.max(64, math.min(T.PAGE_W, math.floor(sw))), math.max(64, math.min(T.PAGE_H, math.floor(sh)))
end
T.PageBound = page_bound
-- the tallest picture a fresh page takes: sh_text.lua's T.PackInto rounds a shelf up to T.SHELF_STEP and keeps the last T.CANARY rows (the verifier: 1017..1020 px passed the old check, then no shelf took it)
local function max_pic_h(bh)
    return math.floor((bh - T.CANARY) / T.SHELF_STEP) * T.SHELF_STEP
end
T.MaxPicH = max_pic_h

local function page_new(i)
    local bw, bh = page_bound()
    local p = T.NewPage(bw, bh)
    p.rw, p.rh = T.PAGE_W, T.PAGE_H
    p.rt, p.mat, p.fmt = new_target("gsa1_textpage_" .. i .. "_" .. p.rw .. "x" .. p.rh, p.rw, p.rh)
    p.fresh, p.index = true, i
    T.pages[i] = p
    if not T.said.atlas then
        T.said.atlas = true
        log("text pictures: a render-target atlas of at most %d pages of %d x %d (%s, kept in the game's memory): no PNG is written or read%s", T.PAGES, p.rw, p.rh, p.fmt,
            (bw < p.rw or bh < p.rh) and string.format("; pictures keep to %d x %d of each, the screen's size", bw, bh) or "")
    end
    return p
end

-- a place for a w x h picture: page, x, y (nil: it cannot have one). A full atlas empties its least recently shown page
local function alloc(w, h)
    for _, p in ipairs(T.pages) do
        local x, y = T.PackInto(p, w, h)
        if x then return p, x, y end
    end
    if #T.pages < T.PAGES then
        local p = page_new(#T.pages + 1)
        local x, y = T.PackInto(p, w, h)
        if x then return p, x, y end
        return nil
    end
    local vi = T.Victim(T.pages)
    local p = T.pages[vi]
    local n, recent = p.n, (p.used or 0) >= FrameNumber() - 1
    T.EmptyPage(p)
    T.stats.emptied = T.stats.emptied + 1
    log("text pictures: page %d emptied for room (the least recently shown): its %d pictures are made again when next shown%s", vi, n,
        recent and "; more text is on the screen at once than the atlas holds" or "")
    local x, y = T.PackInto(p, w, h)
    if x then return p, x, y end
    return nil
end

-- A PICTURE PAINTED BY ITS CALLER (feat/cl_skinhud.lua: a skin's name and plate): a box of the atlas, the same pages, painter, read-back and draw as the texts. w x h px is the picture (what T.DrawPic
-- draws: its UVs), with `margin` px of clear round it in its box (a letter painted a little off stays inside the box, never on a neighbour). -> { page, gen, mat, x, y, w, h (the picture on the page),
-- ax, ay, aw, ah (its whole box), u0, v0, u1, v1 } or nil and why. Good while T.PicValid (its page not emptied since)
function T.Place(w, h, margin)
    margin = math.max(0, math.floor(tonumber(margin) or 0))
    w, h = math.ceil(tonumber(w) or 0), math.ceil(tonumber(h) or 0)
    local aw, ah = w + 2 * margin, h + 2 * margin
    local bw, bh = page_bound()
    if w <= 0 or h <= 0 or aw > bw or ah > max_pic_h(bh) then return nil, string.format("%d x %d px, a page takes %d x %d at most", aw, ah, bw, max_pic_h(bh)) end
    local page, ax, ay = alloc(aw, ah)
    if not page then return nil, "no room on a page" end
    local pw, ph = page.rw or page.w, page.rh or page.h
    local x, y = ax + margin, ay + margin
    page.used = FrameNumber()
    return { mat = page.mat, page = page, gen = page.gen, x = x, y = y, w = w, h = h, ax = ax, ay = ay, aw = aw, ah = ah,
             u0 = x / pw, v0 = y / ph, u1 = (x + w) / pw, v1 = (y + h) / ph }
end

-- is a placed picture still on its page (not emptied for room, lost or made again since)?
function T.PicValid(pic)
    return pic ~= nil and pic.page ~= nil and pic.gen == pic.page.gen
end

-- paints into a placed picture's page (T.Paint: the page cleared first when fresh, the canary set after): fn(x, y) with (x, y) the picture's top left on the page. -> ok, error
function T.PaintPic(pic, fn)
    if not T.PicValid(pic) then return false, "its page was emptied" end
    local x, y = pic.x, pic.y
    return T.Paint(pic.page, function() fn(x, y) end)
end

-- reads a placed picture back (T.ReadBack: one render.CapturePixels of its page): fn(read) with read(x, y) in the picture's own px, anywhere in its box (nil outside it, or not readable); its
-- result, or nil and the error
function T.ReadPic(pic, fn)
    if not T.PicValid(pic) then return nil, "its page was emptied" end
    local px, py = pic.x, pic.y
    local x0, y0, x1, y1 = pic.ax - px, pic.ay - py, pic.ax + pic.aw - 1 - px, pic.ay + pic.ah - 1 - py
    return T.ReadBack(pic.page, function(read)
        return fn(function(x, y)
            if x < x0 or y < y0 or x > x1 or y > y1 then return nil end
            return read(px + x, py + y)
        end)
    end)
end

-- the first pictures after a start or a reset: their alpha read back (one GPU read each): 0 expected at the picture's four corners (3 of them at least: a letter may overhang one), 200 or more somewhere in
-- the letters (a grid over the whole picture). The verdict is T.check.state, which T.Get obeys: "ok" hands pictures out; "bad" never (the texts stay drawn with the font); not yet: none, until one reads
-- right. A picture whose letters the grid misses (a few dots) is not a verdict: the next one is read, T.CHECK_TRIES at most. Not readable here: drawn unchecked (the path is cl_textures.lua's, whose own
-- read-back is the log's "render targets:" line)
T.CHECK_TRIES = 3
function T.AlphaCheck(m)
    local p = m.page
    local C = T.check
    local res, err = T.ReadBack(p, function(read)
        local corners, clear = {}, 0
        local x1, y1 = m.x + m.w - 1, m.y + m.h - 1
        for _, q in ipairs({ { m.x, m.y }, { x1, m.y }, { m.x, y1 }, { x1, y1 } }) do
            local _, _, _, a = read(q[1], q[2])
            if a == nil then return nil end
            corners[#corners + 1] = a
            if a <= 1 then clear = clear + 1 end
        end
        local amax = 0
        local sy, sx = math.max(1, math.floor(m.h / 24)), math.max(1, math.floor(m.w / 256))
        for y = m.y, y1, sy do
            for x = m.x, x1, sx do
                local _, _, _, a = read(x, y)
                if a and a > amax then amax = a end
            end
        end
        return { corners = corners, clear = clear, amax = amax }
    end)
    C.tries = (C.tries or 0) + 1
    T.alphaCheck = res or { err = err }
    if not res then
        C.state = "unreadable"
        log("text pictures: alpha check on page %d: not readable here (%s): the pictures are drawn unchecked", p.index or 0, tostring(err or "render.ReadPixel gives no alpha"))
        return nil
    end
    local cs = table.concat(res.corners, " ")
    res.clearOk, res.inkOk = res.clear >= 3, res.amax >= 200
    res.ok = res.clearOk and res.inkOk
    if res.ok then
        C.state, C.why = "ok", nil
        log("text pictures: alpha check on page %d: corners %s round the letters, %d at most in them: ok (transparent round the letters): the pictures are drawn", p.index or 0, cs, res.amax)
    elseif not res.clearOk then
        C.state, C.why = "bad", string.format("its corners read alpha %s, not 0: each text would sit in a box", cs)
    elseif C.tries >= T.CHECK_TRIES then
        C.state, C.why = "bad", string.format("the letters read alpha %d at most in %d pictures, not 255: they would not show", res.amax, C.tries)
    else
        log("text pictures: alpha check on page %d: corners %s round the letters, but no letter read (%d at most): the next picture is read too; until then the texts are drawn with the font",
            p.index or 0, cs, res.amax)
    end
    if C.state == "bad" then
        T.queue = {}
        log("text pictures: alpha check on page %d: NOT OK, please report this line (%s): the texts are drawn with the font from now on, as without pictures (the button \"Make the text pictures again\" reads once more)",
            p.index or 0, C.why)
    end
    return res
end

-- may pictures be handed out now (T.AlphaCheck's verdict)?
local function handing()
    local s = T.check.state
    return s == "ok" or s == "unreadable"
end
T.Handing = handing

-- one picture into the atlas
function T.Make(job)
    local function failed(why)
        T.stats.failed = T.stats.failed + 1
        remember(job.name, { failed = true })
        if not T.said.make_failed then
            T.said.make_failed = true
            log("a picture could not be made (%s): the text stays drawn with the font each time", why)
        end
        return nil
    end
    local font = font_id(job.font, job.size)
    local ol = tonumber(job.outline) or 0
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(job.text)
    local w = math.ceil((tonumber(tw) or 0) + 2 * T.PAD + 2 * ol)
    local h = math.ceil((tonumber(th) or 0) + 2 * T.PAD + 2 * ol)
    local bw, bh = page_bound()
    if w <= 2 * T.PAD or h <= 2 * T.PAD or w > bw or h > max_pic_h(bh) then
        return failed(string.format("%d x %d px, a page takes %d x %d at most", w, h, bw, max_pic_h(bh)))
    end
    local page, x, y = alloc(w, h)
    if not page then return failed("no room on a page") end
    local c = job.color
    -- the ground: the letters' colour at alpha 0 (their soft edges keep it), the outline's under an outline
    local g = ol > 0 and (job.ocolor or BLACK) or c
    local ok, err = T.Paint(page, function()
        T.ClearRect(x, y, w, h, g.r, g.g, g.b)
        T.DrawLetters({ text = job.text, font = font, x = x + T.PAD + ol, y = y + T.PAD + ol, color = c, outline = ol, ocolor = job.ocolor })
    end)
    if not ok then return failed(tostring(err)) end
    local pw, ph = page.rw or page.w, page.rh or page.h
    local m = { mat = page.mat, w = w, h = h, u0 = x / pw, v0 = y / ph, u1 = (x + w) / pw, v1 = (y + h) / ph, page = page, gen = page.gen, x = x, y = y }
    remember(job.name, m)
    page.used = FrameNumber()
    T.stats.made = T.stats.made + 1
    if T.check.state == nil then T.AlphaCheck(m) end
    return m
end

-- 1.0.0: the picture of a text, or nil: the caller draws it its own way (with T.FontFor's font): no font was picked, or the picture is not ready yet. outline: a black outline of that many px round the
-- letters, or { px, r, g, b } in that colour (0 / nil: none). An element without a Windows family (e.system) keeps 0.9.9g's rule: nothing with the option off.
-- 1.0.0-beta1a: the picture is a part of an atlas page: { mat (the page), w, h (its px), u0, v0, u1, v1 }; draw it with surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1) or T.DrawPic. Good for this
-- frame: ask again each frame (no garbage once a text is known). Nil, too, until the first picture made has read back right (T.AlphaCheck), and always once it read back wrong
function T.Get(text, name, size, color, outline)
    if not text or text == "" then return nil end
    if T.check.state == "bad" then return nil end
    local e = T.ELEMENTS[name]
    if not e or (not e.system and not cv:GetBool()) then return nil end
    local key = T.Pick(name)
    if not key then return nil end
    local ow, oc, okey = outline_of(outline)
    local fname = name_of(text, key, size, color, ScrW(), ScrH(), okey)
    local m = T.mem[fname]
    if m then
        if m.page then
            if m.gen == m.page.gen then
                if not handing() then return nil end    -- (made, not yet read back right: the caller's own way meanwhile)
                m.page.used = FrameNumber()
                return m
            end
            m = nil                                 -- (its page was emptied or lost: made again)
        else
            return nil                              -- (waiting, or failed: the caller's own way)
        end
    end
    remember(fname, { waiting = true })
    T.queue[#T.queue + 1] = { name = fname, text = text, font = key, size = size, color = { r = color.r, g = color.g, b = color.b, a = color.a or 255 }, outline = ow or 0,
        ocolor = ow > 0 and { r = oc.r, g = oc.g, b = oc.b } or nil }
    return nil
end

-- draws a picture of T.Get (or T.Place) at (x, y), w x h px, in (r, g, b, a) (0..255; nil: 255). fu0, fv0, fu1, fv1: only that part of it (0..1 of the picture; nil: all of it)
function T.DrawPic(m, x, y, w, h, r, g, b, a, fu0, fv0, fu1, fv1)
    surface.SetDrawColor(r or 255, g or 255, b or 255, a or 255)
    surface.SetMaterial(m.mat)
    local u0, v0, u1, v1 = m.u0, m.v0, m.u1, m.v1
    if fu0 then
        local du, dv = u1 - u0, v1 - v0
        u0, v0, u1, v1 = u0 + fu0 * du, v0 + fv0 * dv, u0 + fu1 * du, v0 + fv1 * dv
    end
    surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)
end

-- true: drawn from its picture. false: the caller draws it its own way (with T.FontFor's font): the option is off, the font was not found, or the picture is not ready yet
function T.Draw(text, name, size, color, x, y, ax, ay, outline)
    local m = T.Get(text, name, size, color, outline)
    if not m then return false end
    local px, py = x, y
    if ax == 1 then px = x - m.w / 2 elseif ax == 2 then px = x - m.w end
    if ay == 1 then py = y - m.h / 2 elseif ay == 2 or ay == 4 then py = y - m.h end
    T.DrawPic(m, math.floor(px), math.floor(py), m.w, m.h)
    return true
end

-- every picture lost (a device reset, a new resolution, the button): made again when next shown, and the first one read back again (T.AlphaCheck). The pages' parts for pictures follow the
-- screen's size (page_bound). (The names fix: no canvas any more; the skins' pictures are on these pages and made again as theirs are)
function T.LoseAll(why)
    local bw, bh = page_bound()
    for _, p in ipairs(T.pages) do
        T.EmptyPage(p)
        p.w, p.h = bw, bh
        p.canary0 = nil                 -- (read again after its next paint, T.Paint)
    end
    T.check = { tries = 0 }
    T.mem, T.nmem, T.queue = {}, 0, {}
    T.said.make_failed = nil
    T.stats.lost = T.stats.lost + 1
    log("text pictures: %s: every picture is made again when next shown", tostring(why))
end

-- (the names fix: beta 1a read only the first page that held pictures, so a lost page behind it, or a canvas, was never found) the canary of EVERY page that holds pictures; one lost: all made again.
-- b1a2-fix2: all of them in one small read (T.ReadTexels), each against what it read at its make (p.canary0; the painted colour only for a page whose make's read gave nothing). Not readable here:
-- nothing to tell by, nothing made again. Returns how many pages were read
function T.CheckLost()
    local pages, list = {}, {}
    for _, p in ipairs(T.pages) do
        if p.n > 0 and not p.fresh then
            pages[#pages + 1] = p
            list[#list + 1] = { page = p, x = 1, y = p.h - 1 }
        end
    end
    if #pages == 0 then return 0 end
    local got = T.ReadTexels(list)
    if not got then return #pages end
    for i, p in ipairs(pages) do
        local ref = p.canary0 or T.CanaryPainted()
        if T.CanaryOff(got[i], ref) then
            T.LoseAll(string.format("the render targets were lost (device reset): page %d's canary reads %s, at its make %s", p.index or i, rgba(got[i]), p.canary0 and rgba(p.canary0) or "not read"))
            return #pages
        end
    end
    return #pages
end

-- beta 1's saved pictures (garrysmod/data/gsa1/textcache/*.png, RGB on black): nothing reads them any more; deleted once
function T.List()
    local found = file.Find(T.DIR .. "/*.png", "DATA") or {}
    local list = {}
    for _, n in ipairs(found) do
        local p = T.DIR .. "/" .. n
        list[#list + 1] = { name = n, size = file.Size(p, "DATA") or 0, time = file.Time and file.Time(p, "DATA") or 0 }
    end
    return list
end

function T.DeleteOld()
    local n = 0
    for _, e in ipairs(T.List()) do
        file.Delete(T.DIR .. "/" .. e.name)
        n = n + 1
    end
    T.stats.old = T.stats.old + n
    if n > 0 then log("text pictures: %d saved pictures of beta 1 deleted from garrysmod/data/gsa1/textcache (they had no alpha); nothing is saved there any more", n) end
    return n
end

-- (0.9.9g's folder bound: no folder to bound now)
function T.Bound()
    return 0
end

-- the atlas, in a line (the Text page, the log)
function T.AtlasLine()
    local n, used, area = 0, 0, 0
    for _, p in ipairs(T.pages) do
        if p.n > 0 then used = used + 1 end
        n = n + p.n
        area = area + p.area
    end
    local bw, bh = page_bound()
    local total = T.PAGES * bw * bh
    local off = T.check.state == "bad" and ("OFF, the texts are drawn with the font: " .. tostring(T.check.why) .. "; ") or ""
    return string.format("%s%d of at most %d pages of %d x %d in use, %d pictures (%d %% of the atlas); %d emptied for room, %d times made again (device reset, resolution, button)",
        off, used, T.PAGES, T.PAGE_W, T.PAGE_H, n, math.floor(100 * area / total + 0.5), T.stats.emptied, T.stats.lost)
end
T.FolderLine = T.AtlasLine

-- the making: up to 16 pictures or 2 ms a frame, after the frame (PostRender, where cl_textures.lua paints); one summary line when a batch is done
local had_focus, check_at = true, nil
local batch = { n = 0, ms = 0, at = -100 }
hook.Add("PostRender", "gsa1_text", function()
    if not T.said.old then
        T.said.old = true
        T.DeleteOld()
    end
    local focus = system and system.HasFocus and system.HasFocus()
    if focus ~= nil then
        if focus and not had_focus then check_at = RealTime() + 0.5 end
        had_focus = focus
    end
    if check_at and RealTime() >= check_at then
        check_at = nil
        T.CheckLost()
    end
    if #T.queue == 0 then
        if batch.n > 0 and RealTime() - batch.at >= 5 then
            log("text pictures: %d made in %.1f ms; %s", batch.n, batch.ms, T.AtlasLine())
            batch.n, batch.ms, batch.at = 0, 0, RealTime()
        end
        return
    end
    local t0 = SysTime()
    local n = 0
    while #T.queue > 0 and n < 16 and (n == 0 or SysTime() - t0 < 0.002) do
        local job = table.remove(T.queue, 1)
        T.Make(job)
        n = n + 1
    end
    batch.n, batch.ms = batch.n + n, batch.ms + (SysTime() - t0) * 1000
    if GSA1.HitchAdd then GSA1.HitchAdd("Text pictures", SysTime() - t0) end
end)

-- a new resolution: new pictures (their key holds it)
hook.Add("OnScreenSizeChanged", "gsa1_text", function()
    T.LoseAll("the screen size changed")
end)

-- "Make the text pictures again": the atlas emptied (and beta 1's leftovers deleted)
function T.Clear()
    local n = 0
    for _, p in ipairs(T.pages) do n = n + p.n end
    T.DeleteOld()
    T.LoseAll("gsa1_text_clear")
    return n
end
if concommand and concommand.Add then
    concommand.Add("gsa1_text_clear", function() T.Clear() end, nil, "G-SA1: make the text pictures again (they live in the game's memory; nothing is saved)")
end

-- what the page says
function T.ElementLine(name)
    local e = T.ELEMENTS[name]
    local f = T.FONTS[e.font]
    local key = T.Pick(name)
    if not cv:GetBool() then
        if key then return e.title .. ": " .. T.FONTS[key].title .. " (the option is off)." end
        return e.title .. ": today's " .. e.fallback .. " (the option is off)."
    end
    local p = T.Probe(e.font)
    if p.taken then return e.title .. ": " .. f.title .. ", found." end
    if key then return e.title .. ": " .. T.FONTS[key].title .. ". " .. f.title .. " was not used: " .. (p.why or "?") .. "." end
    return e.title .. ": today's " .. e.fallback .. ". " .. f.title .. " was not used: " .. (p.why or "?") .. "."
end

function T.Page(panel)
    panel:Help("G-SA1's own text in a font you have. Fonts are looked for in garrysmod/resource/fonts when Garry's Mod starts; none comes with the addon. Each text is made once into a picture at your resolution and kept in the game's memory while you play; nothing is saved to disk.")
    panel:CheckBox("Use these fonts", "gsa1_text_fonts")
    panel:ControlHelp("Off: today's fonts. At once.")
    for _, name in ipairs(T.ELEMENT_ORDER) do
        panel:Help(T.ElementLine(name))
    end
    panel:Help("The pictures: " .. T.AtlasLine() .. ".")
    panel:Button("Make the text pictures again", "gsa1_text_clear")
    panel:ControlHelp("They are made again when they are next shown.")
    -- 1.0.0 (sadc docs/research/gsa1_100_select.md 4.7, 6): the skins' name and nameplate pictures (feat/cl_skinhud.lua)
    panel:Button("Make the skins' name pictures again", "gsa1_skins_hud_remake")
    panel:ControlHelp("Makes the names and nameplates G-SA1 draws for skins again, with the fonts above. A name.png or nameplate.png you put in garrysmod/data/gsa1/skins/<character>/<skin>/hud yourself is used as it is.")
end
if GSA1.AddMenuPage then GSA1.AddMenuPage(297, "text", "Text", T.Page) end
