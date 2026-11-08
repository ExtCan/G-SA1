-- G-SA1 text in a chosen font, the client part (round 0.9.9g; the pure part is feat/sh_text.lua, which says what may and may not be here). Takes (text, font, size, colour), makes it once into a picture at the game's current
-- resolution, saves it as garrysmod/data/gsa1/textcache/<hash>.png and later loads the saved picture instead of drawing it again. Until the picture is ready, and when anything refuses, the element draws as it does without this
-- file: its caller keeps its own draw.SimpleText. UNVERIFIED in game: render.Capture's PNG alpha here (feat/cl_objicons.lua makes its pictures the same way), the look of the text, whether a .otf loads at all: the log and the page say.
GSA1 = GSA1 or {}
local T = GSA1.Text
if not T then error("gsa1/feat/sh_text.lua did not load: the text needs it") end

T.cv = T.cv or GSA1.ConVar("gsa1_text_fonts", 1, "Use the fonts in garrysmod/resource/fonts on G-SA1's own reminder and skin line (off: today's fonts). At once", 0, 1)
local cv = T.cv

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("text", fmt, ...) end
end

T.probe = T.probe or {}     -- [font] = { there =, taken =, why = }
T.mem = T.mem or {}         -- [file name] = { mat =, w =, h = } | { waiting = true } | { failed = true }
T.nmem = T.nmem or 0
T.queue = T.queue or {}
T.stats = T.stats or { made = 0, loaded = 0, failed = 0, cleared = 0 }
T.said = T.said or {}

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

local names, nnames = {}, 0
local function name_of(text, font, size, color, sw, sh, outline)
    local n = names[text]
    outline = outline or 0
    if n and n.font == font and n.size == size and n.r == color.r and n.g == color.g and n.b == color.b and n.a == (color.a or 255) and n.sw == sw and n.sh == sh and n.ol == outline then
        return n.name
    end
    if not n then
        nnames = nnames + 1
        if nnames > 2 * T.MAX_FILES then
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

local function remember(name, m)
    if T.mem[name] == nil then T.nmem = T.nmem + 1 end
    T.mem[name] = m
    if T.nmem > 2 * T.MAX_FILES then       -- the memory's own bound: they load again from the folder
        T.mem, T.nmem = {}, 0
    end
end

local function measure(font, text)
    surface.SetFont(font)
    local w, h = surface.GetTextSize(text)
    return (tonumber(w) or 0) + 2 * T.PAD, (tonumber(h) or 0) + 2 * T.PAD
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

-- the saved picture, or a job for the next frame
local function open(name, text, key, size, color, outline, ocolor)
    local path = T.DIR .. "/" .. name
    if file.Exists(path, "DATA") then
        local mat = Material("../data/" .. path, "smooth")
        if mat and not (mat.IsError and mat:IsError()) then
            local w, h = measure(font_id(key, size), text)
            w, h = w + 2 * (outline or 0), h + 2 * (outline or 0)
            local m = { mat = mat, w = w, h = h }
            remember(name, m)
            T.stats.loaded = T.stats.loaded + 1
            return m
        end
    end
    local m = { waiting = true }
    remember(name, m)
    T.queue[#T.queue + 1] = { name = name, text = text, font = key, size = size, color = { r = color.r, g = color.g, b = color.b, a = color.a or 255 }, outline = outline or 0,
        ocolor = ocolor and { r = ocolor.r, g = ocolor.g, b = ocolor.b } or nil }
    return m
end

-- 1.0.0: the picture of a text ({ mat =, w =, h = }), or nil: the caller draws it its own way (with T.FontFor's font): no font was picked, or the picture is not ready yet. outline: a black outline of
-- that many px round the letters, or { px, r, g, b } in that colour (0 / nil: none). An element without a Windows family (e.system) keeps 0.9.9g's rule: nothing with the option off
function T.Get(text, name, size, color, outline)
    if not text or text == "" then return nil end
    local e = T.ELEMENTS[name]
    if not e or (not e.system and not cv:GetBool()) then return nil end
    local key = T.Pick(name)
    if not key then return nil end
    local ow, oc, okey = outline_of(outline)
    local fname = name_of(text, key, size, color, ScrW(), ScrH(), okey)
    local m = T.mem[fname] or open(fname, text, key, size, color, ow, oc)
    return m.mat and m or nil
end

-- true: drawn from its picture. false: the caller draws it its own way (with T.FontFor's font): the option is off, the font was not found, or the picture is not ready yet
function T.Draw(text, name, size, color, x, y, ax, ay, outline)
    local m = T.Get(text, name, size, color, outline)
    if not m then return false end
    local px, py = x, y
    if ax == 1 then px = x - m.w / 2 elseif ax == 2 then px = x - m.w end
    if ay == 1 then py = y - m.h / 2 elseif ay == 2 or ay == 4 then py = y - m.h end
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(m.mat)
    surface.DrawTexturedRect(math.floor(px), math.floor(py), m.w, m.h)
    return true
end

-- the folder's bounds, oldest first
function T.List()
    local names = file.Find(T.DIR .. "/*.png", "DATA") or {}
    local list = {}
    for _, n in ipairs(names) do
        local p = T.DIR .. "/" .. n
        list[#list + 1] = { name = n, size = file.Size(p, "DATA") or 0, time = file.Time and file.Time(p, "DATA") or 0 }
    end
    return list
end

function T.Bound(keep)
    local del = T.Trim(T.List(), T.MAX_FILES, T.MAX_BYTES, keep)
    for _, n in ipairs(del) do
        file.Delete(T.DIR .. "/" .. n)
        if T.mem[n] then
            T.mem[n] = nil
            T.nmem = T.nmem - 1
        end
    end
    if #del > 0 then log("the picture folder keeps to its bounds: %d old pictures deleted", #del) end
    return #del
end

-- one picture, into a render target of the text's own colour at alpha 0: the letters' edges keep that colour and only their alpha falls off (on black they would come out with a dark rim)
function T.Make(job)
    local m = T.mem[job.name]
    local function failed(why)
        T.stats.failed = T.stats.failed + 1
        if T.mem[job.name] == nil then T.nmem = T.nmem + 1 end
        T.mem[job.name] = { failed = true }
        if not T.said.make_failed then
            T.said.make_failed = true
            log("a picture could not be made (%s): the text stays drawn with the font each time", why)
        end
    end
    local font = font_id(job.font, job.size)
    local ol = tonumber(job.outline) or 0
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(job.text)
    local w, h = (tonumber(tw) or 0) + 2 * T.PAD + 2 * ol, (tonumber(th) or 0) + 2 * T.PAD + 2 * ol
    if w <= 2 * T.PAD or h <= 2 * T.PAD or w > T.MAX_SIDE or h > T.MAX_SIDE then
        return failed(string.format("%d x %d px", w, h))
    end
    local bw, bh = T.Bucket(w), T.Bucket(h)
    local rt = GetRenderTargetEx("gsa1_text_" .. bw .. "x" .. bh, bw, bh, RT_SIZE_LITERAL or 1, MATERIAL_RT_DEPTH_NONE or 2, 0, 0, IMAGE_FORMAT_BGRA8888 or 12)
    local c = job.color
    -- (with an outline the ground is black at alpha 0, so the outline's soft edge stays black)
    local gr, gg, gb = c.r, c.g, c.b
    if ol > 0 then
        local oc = job.ocolor or BLACK
        gr, gg, gb = oc.r, oc.g, oc.b
    end
    local data
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(gr, gg, gb, 0, true, true)
    cam.Start2D()
    local ok, err = pcall(function()
        -- 1.0.0 (sadc docs/research/gsa1_100_select.md 4.8, the doubled skin line of 14.1bi): render.Clear did not empty a shared bucket in the owner's game, so the whole bucket is also REPLACED by one draw,
        -- colour and alpha (ONE, ZERO), before the text: whatever the last picture left, none of it stays. S.RenderIcon writes its picture the same way
        if render.OverrideBlend then
            render.OverrideBlend(true, BLEND_ONE or 1, BLEND_ZERO or 0, BLENDFUNC_ADD or 0, BLEND_ONE or 1, BLEND_ZERO or 0, BLENDFUNC_ADD or 0)
        end
        surface.SetDrawColor(gr, gg, gb, 0)
        surface.DrawRect(0, 0, bw, bh)
        if render.OverrideBlend then
            render.OverrideBlend(true, BLEND_SRC_ALPHA or 4, BLEND_ONE_MINUS_SRC_ALPHA or 5, BLENDFUNC_ADD or 0, BLEND_ONE or 1, BLEND_ONE_MINUS_SRC_ALPHA or 5, BLENDFUNC_ADD or 0)
        end
        surface.SetFont(font)
        if ol > 0 then
            -- the outline: the text in its colour (black unless asked) at every whole offset within the width, then the text itself
            local oc = job.ocolor or BLACK
            surface.SetTextColor(oc.r, oc.g, oc.b, c.a or 255)
            for dy = -ol, ol do
                for dx = -ol, ol do
                    if (dx ~= 0 or dy ~= 0) and dx * dx + dy * dy <= ol * ol + ol then
                        surface.SetTextPos(T.PAD + ol + dx, T.PAD + ol + dy)
                        surface.DrawText(job.text)
                    end
                end
            end
        end
        surface.SetTextColor(c.r, c.g, c.b, c.a or 255)
        surface.SetTextPos(T.PAD + ol, T.PAD + ol)
        surface.DrawText(job.text)
        if render.OverrideBlend then render.OverrideBlend(false) end
    end)
    cam.End2D()
    if ok then
        ok, data = pcall(render.Capture, { format = "png", x = 0, y = 0, w = w, h = h, alpha = true })
        if not ok then err, data = data, nil end
    end
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if not ok then return failed(tostring(err)) end
    if type(data) ~= "string" or string.sub(data, 1, 4) ~= "\137PNG" then
        return failed("render.Capture gave no PNG")
    end
    if file.CreateDir then
        file.CreateDir("gsa1")
        file.CreateDir(T.DIR)
    end
    local path = T.DIR .. "/" .. job.name
    file.Write(path, data)
    local mat = Material("../data/" .. path, "smooth")
    if not mat or (mat.IsError and mat:IsError()) then return failed("the saved PNG does not load") end
    if m == nil then T.nmem = T.nmem + 1 end
    T.mem[job.name] = { mat = mat, w = w, h = h }
    T.stats.made = T.stats.made + 1
    log("made the picture %s: %d x %d px, %d bytes, \"%s\"", job.name, w, h, #data, string.sub(job.text, 1, 40))
    T.Bound(job.name)
end

-- at most one a frame, after the frame (cl_objicons.lua makes its own the same way)
hook.Add("PostRender", "gsa1_text", function()
    local job = table.remove(T.queue, 1)
    if job then T.Make(job) end
end)

-- a new resolution: new pictures (the name holds it); the old ones go when the folder's bound asks
hook.Add("OnScreenSizeChanged", "gsa1_text", function()
    T.mem, T.nmem, T.queue = {}, 0, {}
    T.said.make_failed = nil
end)

-- every picture in the folder; only there
function T.Clear()
    local n = 0
    for _, e in ipairs(T.List()) do
        file.Delete(T.DIR .. "/" .. e.name)
        n = n + 1
    end
    T.mem, T.nmem, T.queue = {}, 0, {}
    T.stats.cleared = T.stats.cleared + n
    log("the picture folder was cleared: %d pictures", n)
    return n
end
if concommand and concommand.Add then
    concommand.Add("gsa1_text_clear", function() T.Clear() end, nil, "Delete the saved text pictures in garrysmod/data/gsa1/textcache")
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

function T.FolderLine()
    local list = T.List()
    local bytes = 0
    for _, e in ipairs(list) do bytes = bytes + (tonumber(e.size) or 0) end
    return string.format("%d of at most %d pictures, %.1f of at most %d MB, at this resolution and others.", #list, T.MAX_FILES, bytes / (1024 * 1024), T.MAX_BYTES / (1024 * 1024))
end

function T.Page(panel)
    panel:Help("G-SA1's own text in a font you have. Fonts are looked for in garrysmod/resource/fonts when Garry's Mod starts; none comes with the addon. Each text is made once into a picture at your resolution and saved.")
    panel:CheckBox("Use these fonts", "gsa1_text_fonts")
    panel:ControlHelp("Off: today's fonts. At once.")
    for _, name in ipairs(T.ELEMENT_ORDER) do
        panel:Help(T.ElementLine(name))
    end
    panel:Help("Saved pictures, in garrysmod/data/gsa1/textcache: " .. T.FolderLine())
    panel:Button("Clear the saved pictures", "gsa1_text_clear")
    panel:ControlHelp("They are made again when they are next shown.")
    -- 1.0.0 (sadc docs/research/gsa1_100_select.md 4.7, 6): the skins' name and nameplate pictures (feat/cl_skinhud.lua)
    panel:Button("Make the skins' name pictures again", "gsa1_skins_hud_remake")
    panel:ControlHelp("Deletes only the pictures G-SA1 made in garrysmod/data/gsa1/skins/<character>/<skin>/HUD (listed in generated.txt there) and makes them again, with the fonts above. Your own pictures stay.")
end
if GSA1.AddMenuPage then GSA1.AddMenuPage(297, "text", "Text", T.Page) end
