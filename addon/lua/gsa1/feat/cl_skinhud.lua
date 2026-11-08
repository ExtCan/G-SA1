-- G-SA1 a skin's name and nameplate pictures, the client part (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 4.7 with RX.11; the pure part is feat/sh_skinhud.lua, which says what may be here).
-- Made at most one a frame, in PostRender, the first time a skin's slot is shown on Character Select (S.SkinShown); until it exists the game's own name and plate stay (no blank frame). Used by
-- feat/cl_charselect_bar.lua's draw filter on the game's own vertices. Saved in garrysmod/data/gsa1/skins/<base>/<id>/HUD on this PC only, never under the addon (repos/sync_repos.py refuses made text
-- pictures and fonts). UNVERIFIED in game: the look of the squeezed letters, render.Capture's PNG alpha at 2048 x 256 (cl_text.lua and cl_objicons.lua make theirs the same way).
GSA1 = GSA1 or {}
local H = GSA1.SkinHud
if not H then error("gsa1/feat/sh_skinhud.lua did not load: the skins' pictures need it") end
local K = GSA1.Skins

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("skinhud", fmt, ...) end
end

H.mats = H.mats or {}           -- [id] = { name = material | false, plate = material | false }
H.queue = H.queue or {}
H.stats = H.stats or { made = 0, loaded = 0, failed = 0, deleted = 0 }
H.nmat = H.nmat or 0

-- a picture of the DATA folder as a material that takes the game's vertex colours and alpha (the name pulses, fades and greys with the game's own colours)
function H.Load(path, id, which)
    local png = Material("../data/" .. path, "smooth")
    if not png or (png.IsError and png:IsError()) then return false end
    local tex = png.GetTexture and png:GetTexture("$basetexture")
    if tex and tex.Download then pcall(tex.Download, tex) end          -- (made again under the same name: read it from the disk again)
    if not (tex and CreateMaterial) then return png end
    H.nmat = H.nmat + 1
    local ok, mat = pcall(CreateMaterial, "gsa1_skinhud_" .. tostring(id) .. "_" .. tostring(which) .. "_" .. H.nmat, "UnlitGeneric",
        { ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$translucent"] = 1 })
    if not ok or not mat then return png end
    if mat.SetTexture then mat:SetTexture("$basetexture", tex) end
    return mat
end

-- a skin was shown: its two pictures loaded, or queued to be made
function H.Want(e)
    if not (e and e.id) or H.mats[e.id] then return end
    local t = {}
    H.mats[e.id] = t
    local P = H.Paths(e)
    if not P then return end
    for _, which in ipairs({ "name", "plate" }) do
        local path = P[which]
        if path then
            local exists = file.Exists(path, "DATA") == true
            local w = H.Wants(e, which, exists)
            if w == "load" then
                t[which] = H.Load(path, e.id, which)
                if t[which] then H.stats.loaded = H.stats.loaded + 1 end
            elseif w == "make" then
                t[which] = false
                H.queue[#H.queue + 1] = { id = e.id, which = which, path = path }
            else
                t[which] = false
            end
        end
    end
end

-- the material of a skin's picture now (nil: not there yet, the game's own stays)
function H.Material(id, which)
    local e = K and K.SKINS and K.SKINS[id]
    if not e then return nil end
    if not H.mats[id] then H.Want(e) end
    local m = H.mats[id] and H.mats[id][which]
    return m or nil
end

-- folders, one level at a time
local function mkdirs(dir)
    if not file.CreateDir then return end
    local acc = ""
    for part in string.gmatch(dir, "[^/]+") do
        acc = acc == "" and part or (acc .. "/" .. part)
        file.CreateDir(acc)
    end
end

-- a text into the box (x, y, w, h) of the render target: capitals fill `cap` px of letter height, squeezed sideways to max_w, centred; outline px round them (in the picture's px)
local function draw_text(text, element, color, cx, cy, cap, max_w, outline, ocolor)
    local Tx = GSA1.Text
    local size = 128                                         -- (the largest size tried; scaled up to the letters' height below, select 4.7)
    local font = Tx and Tx.FontFor and Tx.FontFor(element, size) or "DermaLarge"
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(text)
    tw, th = tonumber(tw) or 1, tonumber(th) or 1
    local sy = cap / math.max(1, th * 0.66)                  -- (capitals are about two thirds of a line's height)
    local sx = math.min(sy, max_w / math.max(1, tw))
    local m = Matrix()
    m:Translate(Vector(cx - tw * sx / 2, cy - th * sy / 2, 0))
    m:Scale(Vector(sx, sy, 1))
    cam.PushModelMatrix(m, true)
    if outline > 0 then
        local o = outline / sy
        surface.SetTextColor(ocolor[1], ocolor[2], ocolor[3], 255)
        for a = 0, 15 do
            local ang = a * math.pi / 8
            surface.SetTextPos(math.cos(ang) * o, math.sin(ang) * o)
            surface.DrawText(text)
        end
    end
    surface.SetTextColor(color[1], color[2], color[3], 255)
    surface.SetTextPos(0, 0)
    surface.DrawText(text)
    cam.PopModelMatrix()
    return tw * sx, sx < sy
end

-- one picture (PostRender)
function H.Make(job)
    local e = K and K.SKINS and K.SKINS[job.id]
    local t = H.mats[job.id]
    if not (e and t) then return end
    local function failed(why)
        H.stats.failed = H.stats.failed + 1
        log("%s's %s picture could not be made (%s): the game's own stays", tostring(e.title), job.which, tostring(why))
    end
    local L = job.which == "name" and H.NAME or H.PLATE
    local w, h = L.w, L.h
    local rt = GetRenderTargetEx("gsa1_skinhud_" .. w .. "x" .. h, w, h, RT_SIZE_LITERAL or 1, MATERIAL_RT_DEPTH_NONE or 2, 0, 0, IMAGE_FORMAT_BGRA8888 or 12)
    local text = H.TextOf(e, job.which)
    local data
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(0, 0, 0, 0, true, true)
    cam.Start2D()
    local ok, err = pcall(function()
        -- the whole target replaced first, colour and alpha (the doubled line's lesson, select 4.8)
        render.OverrideBlend(true, BLEND_ONE or 1, BLEND_ZERO or 0, BLENDFUNC_ADD or 0, BLEND_ONE or 1, BLEND_ZERO or 0, BLENDFUNC_ADD or 0)
        surface.SetDrawColor(0, 0, 0, 0)
        surface.DrawRect(0, 0, w, h)
        if job.which == "plate" then
            local s, P = L.scale, L
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawRect(0, 0, (P.x1 + 1) * s, (P.bottom + 1) * s)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawRect(P.frame * s, P.frame * s, (P.x1 + 1 - 2 * P.frame) * s, (P.bottom + 1 - 2 * P.frame) * s)
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawRect(P.frame * s + 3 * s, P.bar0 * s, (P.x1 + 1 - 2 * P.frame - 6) * s, (P.bar1 - P.bar0 + 1) * s)
        end
        render.OverrideBlend(true, BLEND_SRC_ALPHA or 4, BLEND_ONE_MINUS_SRC_ALPHA or 5, BLENDFUNC_ADD or 0, BLEND_ONE or 1, BLEND_ONE_MINUS_SRC_ALPHA or 5, BLENDFUNC_ADD or 0)
        if job.which == "name" then
            local r, g, b = K.ColorOf(e)
            local cap = h * L.letters * 0.8                  -- (the capitals of the game's m_sonic fill rows 9..53 with their outline)
            draw_text(text, "skin_name", { r or 255, g or 255, b or 255 }, w / 2, h / 2, cap, L.max_w, cap * L.outline, { 0, 0, 0 })
        else
            local s, P = L.scale, L
            local cx = (P.x1 + 1) * s / 2
            local cy = (P.text0 + P.text1 + 1) * s / 2
            draw_text(text, "skin_plate", { 0, 0, 0 }, cx, cy, (P.text1 - P.text0 + 1) * s * 0.9, (P.x1 + 1 - 2 * P.frame - 2 * P.margin) * s, 0, { 0, 0, 0 })
        end
        render.OverrideBlend(false)
    end)
    cam.End2D()
    if ok then
        ok, data = pcall(render.Capture, { format = "png", x = 0, y = 0, w = w, h = h, alpha = true })
        if not ok then err, data = data, nil end
    end
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if not ok then return failed(err) end
    if type(data) ~= "string" or string.sub(data, 1, 4) ~= "\137PNG" then return failed("render.Capture gave no PNG") end
    local P = H.Paths(e)
    mkdirs(P.dir)
    local dir = string.match(job.path, "^(.*)/[^/]+$")
    if dir then mkdirs(dir) end
    file.Write(job.path, data)
    -- the list of what G-SA1 made (the only files "make again" deletes)
    local set = H.ParseGenerated(file.Read(P.list, "DATA"))
    if dir == P.dir then set[H.Base(job.path)] = true end
    file.Write(P.list, H.FormatGenerated(set))
    t[job.which] = H.Load(job.path, e.id, job.which)
    H.stats.made = H.stats.made + 1
    log("made %s's %s picture: %s, %d x %d, %d bytes", tostring(e.title), job.which, job.path, w, h, #data)
end

hook.Add("PostRender", "gsa1_skinhud", function()
    local job = table.remove(H.queue, 1)
    if not job then return end
    local ok, err = pcall(H.Make, job)
    if not ok then
        H.stats.failed = H.stats.failed + 1
        log("a skin's picture: %s", tostring(err))
    end
end)

-- "Make the skins' name pictures again" (the Text page): only the files each HUD/generated.txt lists; the owner's own pictures stay
function H.Remake()
    local n = 0
    for _, id in ipairs(K and K.ORDER or {}) do
        local e = K.SKINS[id]
        local P = e and H.Paths(e)
        if P then
            local set = H.ParseGenerated(file.Read(P.list, "DATA"))
            for name in pairs(set) do
                local path = P.dir .. "/" .. name
                if file.Exists(path, "DATA") then
                    file.Delete(path)
                    n = n + 1
                end
            end
            if next(set) then file.Write(P.list, H.FormatGenerated({})) end
            H.mats[id] = nil
            H.Want(e)
        end
    end
    H.stats.deleted = H.stats.deleted + n
    log("the skins' pictures: %d made ones deleted, made again one a frame", n)
    return n
end
if concommand and concommand.Add then
    concommand.Add("gsa1_skins_hud_remake", function() H.Remake() end, nil, "G-SA1: make the skins' name and nameplate pictures again (only the ones G-SA1 made; yours stay)")
end
