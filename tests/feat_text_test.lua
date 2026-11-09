-- feat_text_test.lua - text in a chosen font (round 0.9.9g; feat/sh_text.lua, feat/cl_text.lua, the two elements in feat/cl_photo.lua and feat/cl_charselect.lua). 1.0.0 (sadc docs/research/gsa1_100_select.md
-- 4.7 with RX.11, 4.8, 7.2 T7): the new elements and their Windows families, outlines. 1.0.0-beta1a (lane b1a-text, sadc/build/research/b1a/b1a-text/NOTES.md): THE PICTURES LIVE IN A RENDER-TARGET ATLAS,
-- no PNG. This test runs them against tests/lua_mock_rt.lua, the pixel model of Garry's Mod's render targets as this project MEASURED them (a new target is opaque black; a clear that asks for depth
-- on a target without one is dropped whole; vgui never draws an alpha-0 rectangle; the separate alpha blend), with a model of letters (each a box of the text's colour). The whole addon through its
-- autorun, tests/lua_mock.lua, in Garry's Mod's own LuaJIT. NO REAL FONT: a font "exists" here because a line in the mock's file table says so and its text measures differently.
-- WHAT ONLY THE GAME CAN SHOW: the letters' real shapes, whether vgui's text honours render.OverrideBlend's separate alpha (the log's "text pictures: alpha check" line reads it back in the owner's game).
--   lua_host tests/feat_text_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local R = host_load(host_read(tests .. "/lua_mock_rt.lua"), "lua_mock_rt.lua")()(M)
local check, info = M.check, M.info
print("G-SA1 feat_text_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

local cookies = {}
cookie = { GetNumber = function(k, d) return tonumber(cookies[k]) or d end, Set = function(k, v) cookies[k] = v end, GetString = function(k, d) return cookies[k] or d end }

local G = M.module({ speed = 300, features = { super = 5, jukebox = 1, emote = 3, follower = 2, frontend = 1 } })
GSA1 = nil
local logs = {}
M.included = {}

-- the engine, as far as this feature asks. A font the "engine took" measures by its own width a letter; letters are boxes (the model below)
local sw, sh = 1920, 1080
ScrW, ScrH = function() return sw end, function() return sh end
local fonts, cur = {}, nil
local taken = {}        -- [family] = a width per letter; absent: Windows' default face
local counts = { created = 0, drew = 0, simple = {}, uv = 0, captures = 0 }
surface.CreateFont = function(name, def)
    fonts[name] = def
    counts.created = counts.created + 1
end
surface.SetFont = function(name) cur = name end
surface.GetTextSize = function(s)
    local def = fonts[cur]
    local per = def and taken[def.font] or 10
    return per * #s, (def and def.size or 32)
end
-- THE LETTERS' MODEL: a letter of a font of size s is a box (0.15 .. 0.85 of its advance) x (0.2 .. 0.8 of s) below the text position, in the text colour and alpha, blended as the pixel model blends
-- (under render.OverrideBlend, or SRC_ALPHA / ONE_MINUS_SRC_ALPHA); cam.PushModelMatrix moves and scales it
local TXT = { x = 0, y = 0, c = { 255, 255, 255, 255 } }
local mstack = {}
Matrix = function()
    local t = { tx = 0, ty = 0, sx = 1, sy = 1 }
    function t:Translate(v) self.tx, self.ty = self.tx + v.x * self.sx, self.ty + v.y * self.sy end
    function t:Scale(v) self.sx, self.sy = self.sx * v.x, self.sy * v.y end
    return t
end
cam.PushModelMatrix = function(m) mstack[#mstack + 1] = m end
cam.PopModelMatrix = function() mstack[#mstack] = nil end
surface.SetTextPos = function(x, y) TXT.x, TXT.y = x, y end
surface.SetTextColor = function(r, g, b, a)
    if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
    TXT.c = { r, g, b, math.floor((a or 255) * R.mult) }
end
surface.DrawText = function(s)
    counts.drew = counts.drew + 1
    local t = R.cur
    local def = fonts[cur]
    local per, size = def and taken[def.font] or 10, def and def.size or 32
    local m = mstack[#mstack] or { tx = 0, ty = 0, sx = 1, sy = 1 }
    local aw = R.alphaWrite
    if TXT.noalpha then R.alphaWrite = false end      -- (T17: a host whose text writes no alpha)
    if t and R.in2d then
        for i = 0, #s - 1 do
            if string.sub(s, i + 1, i + 1) ~= " " then
                local x0, x1 = m.tx + m.sx * (TXT.x + (i + 0.15) * per), m.tx + m.sx * (TXT.x + (i + 0.85) * per)
                local y0, y1 = m.ty + m.sy * (TXT.y + 0.2 * size), m.ty + m.sy * (TXT.y + 0.8 * size)
                for py = math.max(0, math.floor(y0)), math.min(t.h, math.ceil(y1)) - 1 do
                    for px = math.max(0, math.floor(x0)), math.min(t.w, math.ceil(x1)) - 1 do
                        if px + 0.5 >= x0 and px + 0.5 < x1 and py + 0.5 >= y0 and py + 0.5 < y1 then R.write(t, py * t.w + px + 1, TXT.c) end
                    end
                end
            end
        end
    end
    R.alphaWrite = aw
    TXT.x = TXT.x + per * #s
end
local uvs = {}
surface.DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1)
    counts.uv = counts.uv + 1
    uvs[#uvs + 1] = { x = x, y = y, w = w, h = h, u0 = u0, v0 = v0, u1 = u1, v1 = v1, mat = counts.mat }
end
surface.DrawTexturedRect = function(x, y, w, h)
    counts.plain = (counts.plain or 0) + 1
end
local set_mat0 = surface.SetMaterial
surface.SetMaterial = function(m)
    counts.mat = m
    if set_mat0 then set_mat0(m) end
end
draw.SimpleText = function(text, font) counts.simple[#counts.simple + 1] = { text = text, font = font } end
render.Capture = function(t)
    counts.captures = counts.captures + 1
    return "\137PNG"
end
Material = function(path, flags)
    return { path = path, flags = flags, IsError = function(self) return M.files[string.gsub(self.path, "^%.%./data/", "")] == nil end }
end
-- the mock's file table holds DATA and GAME paths alike; the DATA folder's listing of the old pictures (the LUA path stays the mock's: the autorun lists the feature files with it)
local find0 = file.Find
file.Find = function(pattern, path)
    if path == "DATA" then
        local out = {}
        for p in pairs(M.files) do
            local n = string.match(p, "^gsa1/textcache/([^/]+%.png)$")
            if n then out[#out + 1] = n end
        end
        table.sort(out)
        return out, {}
    end
    return find0(pattern, path)
end
file.Time = function() return 0 end
-- beta 1's leftovers on the owner's PC: deleted once, nothing else
M.files["gsa1/textcache/0aefb352301fba2e.png"] = "\137PNG beta 1"
M.files["gsa1/textcache/9d68466248657178.png"] = "\137PNG beta 1"
M.files["gsa1/other.txt"] = "a file of someone else"

do
    local ok, err = pcall(M.load, "autorun/gsa1_autorun.lua")
    local errs = GSA1 and GSA1.FeatureFileErrors or {}
    check(ok and #errs == 0, "the addon's client files load (%s)", tostring(err or errs[1] or "no error"))
end
local T = GSA1 and GSA1.Text
check(T ~= nil and T.Draw ~= nil and T.Get ~= nil and T.DrawPic ~= nil, "the module loaded (T.Draw, T.Get, T.DrawPic)")
if not T then return done() end
local log0 = GSA1.Log
function GSA1.Log(kind, fmt, ...)
    logs[#logs + 1] = { kind = kind, text = string.format(fmt, ...) }
    if log0 then return log0(kind, fmt, ...) end
end
local function logged(pat)
    for _, l in ipairs(logs) do
        if string.find(l.text, pat, 1, true) then return l.text end
    end
    return nil
end
local function reset_session()
    T.probe, T.mem, T.nmem, T.queue = {}, {}, 0, {}
    for k in pairs(T.said) do
        if k ~= "atlas" and k ~= "alpha" and k ~= "old" then T.said[k] = nil end
    end
    logs = {}
end
local WHITE = { r = 255, g = 255, b = 255, a = 255 }
local YELLOW = { r = 244, g = 255, b = 0, a = 255 }
-- (small pages here: the pixel model keeps every texel in Lua)
T.PAGE_W, T.PAGE_H, T.PAGES = 512, 128, 2

-- the hash: the picture's key -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local base = T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 1920, 1080)
check(string.match(base, "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%.png$") ~= nil, "T1 the key is 16 hex digits (%s)", base)
check(T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 1920, 1080) == base, "T1 the same inputs, the same key")
check(T.FileName("Up: Sonic", "bauhaus", 20, WHITE, 1920, 1080) ~= base, "T1 another text, another key")
check(T.FileName("Up: Metal Sonic", "rodin", 20, WHITE, 1920, 1080) ~= base, "T1 another font, another key")
check(T.FileName("Up: Metal Sonic", "bauhaus", 21, WHITE, 1920, 1080) ~= base, "T1 another size, another key")
check(T.FileName("Up: Metal Sonic", "bauhaus", 20, { r = 255, g = 255, b = 254, a = 255 }, 1920, 1080) ~= base, "T1 another colour, another key")
check(T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 2560, 1080) ~= base and T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 1920, 1440) ~= base, "T1 another resolution, another key")
do
    local seen, same = {}, 0
    for i = 1, 4000 do
        local h = T.Hash("line " .. i)
        if seen[h] then same = same + 1 end
        seen[h] = true
    end
    check(same == 0, "T1 4000 short texts: %d of the same hash", same)
end

-- no file: today's font ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
check(T.cv ~= nil and T.cv:GetBool(), "T2 gsa1_text_fonts defaults to 1")
reset_session()
check(T.FontFor("photo_hint", 32) == "DermaLarge", "T2 no font file: the reminder keeps today's DermaLarge")
check(T.FontFor("charselect_skin", 20) == "GSA1CharSelectHint", "T2 no font file: the skin line keeps today's font")
check(logged("Photo mode's reminder: today's DermaLarge") and logged("FOT-Rodin Pro UB.otf is not in garrysmod/resource/fonts"), "T2 the log says which was used, and why")
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == false and #T.queue == 0, "T2 no font: no picture, nothing queued")
check(string.find(T.ElementLine("charselect_skin"), "today's GSA1CharSelectHint", 1, true) ~= nil, "T2 the page says so")

-- the file is there, the engine did not take it: as the .otf may turn out -----------------------------------------------------------------------------------------------------------------------------------------------
reset_session()
M.files["resource/fonts/FOT-Rodin Pro UB.otf"] = "not a font"
check(T.FontFor("photo_hint", 32) == "DermaLarge", "T3 the file is there, the engine fell back: today's font")
check(logged("the engine did not take it") and logged("the same as with a font that does not exist"), "T3 the log tells the two apart")
check(string.find(T.ElementLine("photo_hint"), "the engine did not take it", 1, true) ~= nil, "T3 the page says so")

-- T4 found: made once into the atlas, from the PROVEN path; no PNG -----------------------------------------------------------------------------------------------------------------------------------------------------
reset_session()
M.files["resource/fonts/BauhausStd-Bold.ttf"] = "not a font"
taken["Bauhaus Std Medium"] = 13
local id = T.FontFor("charselect_skin", 20)
check(id == "GSA1Text_bauhaus_20" and fonts[id] and fonts[id].font == "Bauhaus Std Medium" and fonts[id].size == 20, "T4 surface.CreateFont by name from the table (%s)", tostring(id))
check(logged("Character Select's skin line: Bauhaus Std Bold"), "T4 the log says which was used")
check(string.find(T.ElementLine("charselect_skin"), "Bauhaus Std Bold, found", 1, true) ~= nil, "T4 the page says which")
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == false and #T.queue == 1, "T4 the first frame: the caller draws it, a job waits")
T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1)
check(#T.queue == 1, "T4 one job for one text")
local nfiles0 = 0
for _ in pairs(M.files) do nfiles0 = nfiles0 + 1 end
M.run_hook("PostRender")
local pic = T.Get("Up: Metal Sonic", "charselect_skin", 20, WHITE)
check(pic ~= nil and pic.page ~= nil and pic.mat == pic.page.mat and pic.w == 13 * 15 + 4 and pic.h == 24, "T4 the next frame: made into an atlas page, at the text's size and 2 px round it (%s x %s)", tostring(pic and pic.w), tostring(pic and pic.h))
check(M.files["gsa1/textcache/0aefb352301fba2e.png"] == nil and M.files["gsa1/textcache/9d68466248657178.png"] == nil and M.files["gsa1/other.txt"] ~= nil and logged("2 saved pictures of beta 1 deleted"),
    "T4 beta 1's saved pictures (no alpha) deleted once, nothing else")
do
    local n = 0
    for p in pairs(M.files) do if string.find(p, "textcache", 1, true) then n = n + 1 end end
    check(counts.captures == 0 and n == 0, "T4 no render.Capture, no PNG written (%d captures, %d files)", counts.captures, n)
end
if pic then
    local p = pic.page
    local rt = p.rt
    local mp = pic.mat.params or {}
    check(rt.depth == MATERIAL_RT_DEPTH_NONE and rt.fmt == GSA1.Tex.format.fmt and rt.w == 512 and rt.h == 128 and bit.band(rt.flags or 0, 0x30C) == 0x30C,
        "T4 the page is a render target as cl_textures.lua's textures: no depth, its probed format, no mips, clamped (%s)", tostring(rt.name))
    check(pic.mat.shader == "UnlitGeneric" and mp["$basetexture"] == rt.name and mp["$vertexcolor"] == 1 and mp["$vertexalpha"] == 1 and mp["$translucent"] == 1 and mp["$nocull"] == 1 and mp["$ignorez"] == 1,
        "T4 its material is cl_hud.lua's translucent one on the render target")
    check(math.abs(pic.u0 * 512 - pic.x) < 1e-6 and math.abs(pic.u1 * 512 - (pic.x + pic.w)) < 1e-6 and math.abs(pic.v1 * 128 - (pic.y + pic.h)) < 1e-6, "T4 its UVs are its own part of the page")
    check(R.dropped == 0, "T4 no clear ever asked for a depth buffer the target does not have (%d dropped)", R.dropped)
    -- THE PIXELS (the model's): round the letters alpha 0 in the text's own colour, in the letters the colour at 255
    local r0, g0, b0, a0 = rt:Get(pic.x, pic.y)
    local _, _, _, a1 = rt:Get(pic.x + pic.w - 1, pic.y + pic.h - 1)
    local lr, lg, lb, la = rt:Get(pic.x + 2 + 6, pic.y + 2 + 10)
    check(a0 == 0 and a1 == 0 and r0 == 255 and g0 == 255 and b0 == 255, "T4 round the letters: alpha 0 (the ground in the letters' colour: %d %d %d %d)", r0, g0, b0, a0)
    check(la == 255 and lr == 255 and lg == 255 and lb == 255, "T4 in a letter: the colour at alpha 255 (%d %d %d %d)", lr, lg, lb, la)
    local outside = 0
    for y = 0, 127, 7 do
        for x = 0, 511, 7 do
            if not (x >= pic.x and x < pic.x + pic.w and y >= pic.y and y < pic.y + pic.h) and not (x >= 510 and y >= 126) then
                local _, _, _, a = rt:Get(x, y)
                if a ~= 0 then outside = outside + 1 end
            end
        end
    end
    check(outside == 0, "T4 the rest of the page: alpha 0 (Source's opaque black creation colour cleared: %d texels not)", outside)
    check(logged("text pictures: a render-target atlas of at most 2 pages of 512 x 128") and logged("no PNG is written or read"), "T4 the log: the atlas, its pages, its format, no PNG")
    local ac = logged("text pictures: alpha check on page 1")
    check(ac and string.find(ac, "0 round the letters, 255 at most in them: ok", 1, true), "T4 the log: the first picture's alpha read back: %s", tostring(ac))
end
counts.uv = 0
uvs = {}
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == true and counts.uv == 1 and (counts.plain or 0) == 0, "T4 from then on it draws from its part of the page (DrawTexturedRectUV)")
check(pic and uvs[1] and uvs[1].w == pic.w and uvs[1].x == math.floor(960 - pic.w / 2) and uvs[1].u0 == pic.u0 and uvs[1].v1 == pic.v1 and uvs[1].mat == pic.mat, "T4 at the size it was made, centred where asked, 1 to 1, its UVs")
-- the next session: made again (nothing on disk)
reset_session()
T.FontFor("charselect_skin", 20)
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == false and #T.queue == 1, "T5 a new session (the table empty) makes it again: nothing is read from a file")
M.run_hook("PostRender")
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == true, "T5 and draws it the frame after")

-- T6 THE SPECKS, MEASURED ON THE OWNER'S FILES: each picture had the one before's letters (beta 1's render target was never cleared). Two texts in a row of one page: the second's part holds only its own
do
    reset_session()
    T.Clear()
    local a = "CHOOSE YOUR UPGRADE"
    local b = "LIGHT SPEED"
    T.Get(a, "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    local pa = T.Get(a, "charselect_skin", 20, WHITE)
    -- (the page emptied by T.Clear: the second picture goes where the first one was, as beta 1's bucket did)
    T.Clear()
    T.Get(b, "charselect_skin", 20, YELLOW)
    M.run_hook("PostRender")
    local pb = T.Get(b, "charselect_skin", 20, YELLOW)
    local white, yellow = 0, 0
    if pa and pb then
        local rt = pb.page.rt
        for y = pa.y, pa.y + pa.h - 1 do
            for x = pa.x, pa.x + pa.w - 1 do
                local r, g, bb, al = rt:Get(x, y)
                if al > 0 and r == 255 and g == 255 and bb == 255 then white = white + 1 end
                if al > 0 and r == 244 and g == 255 and bb == 0 then yellow = yellow + 1 end
            end
        end
    end
    check(pa and pb and pa.x == pb.x and pa.y == pb.y and white == 0 and yellow > 0, "T6 the second picture where the first was: none of the first's letters left (%d white texels, %d of its own)", white, yellow)
    -- beta 1's way in the same model: the clear with depth is dropped, the alpha-0 rectangle is never drawn: the old letters stay, on opaque black (what the owner's PNGs show)
    local rt = GetRenderTargetEx("beta1_bucket", 64, 16, 1, MATERIAL_RT_DEPTH_NONE, 0, 0, 12)
    local function beta1(s, c)
        render.PushRenderTarget(rt)
        render.OverrideAlphaWriteEnable(true, true)
        render.Clear(c.r, c.g, c.b, 0, true, true)
        cam.Start2D()
        render.OverrideBlend(true, 1, 0, 0, 1, 0, 0)
        surface.SetDrawColor(c.r, c.g, c.b, 0)
        surface.DrawRect(0, 0, 64, 16)
        render.OverrideBlend(true, 4, 5, 0, 1, 5, 0)
        surface.SetFont("GSA1Text_bauhaus_20")
        surface.SetTextColor(c.r, c.g, c.b, 255)
        surface.SetTextPos(2, 0)
        surface.DrawText(s)
        render.OverrideBlend(false)
        cam.End2D()
        render.OverrideAlphaWriteEnable(false)
        render.PopRenderTarget()
    end
    beta1("WWWW", WHITE)
    beta1("Y", YELLOW)
    local w2, op = 0, 0
    for y = 0, 15 do
        for x = 0, 63 do
            local r, g, bb, al = rt:Get(x, y)
            if r == 255 and g == 255 and bb == 255 then w2 = w2 + 1 end
            if al == 255 then op = op + 1 end
        end
    end
    check(w2 > 0 and op == 64 * 16, "T6 beta 1's way, in the model: the last picture's white letters stay (%d texels) and every texel is opaque (%d of %d): the owner's black boxes and specks", w2, op, 64 * 16)
end

-- T7 an outline: black round the letters, alpha 0 beyond it
do
    reset_session()
    T.Get("ACTIVE", "charselect_skin", 20, YELLOW, 2)
    M.run_hook("PostRender")
    local p = T.Get("ACTIVE", "charselect_skin", 20, YELLOW, 2)
    if p then
        local rt = p.page.rt
        -- the first letter's box: x from 2 + 2 + 0.15 x 13, y from 2 + 2 + 4; the outline's texel just left of it, and the ground beyond
        local lx, ly = p.x + 4 + 2, p.y + 4 + 8
        local r1, g1, b1, a1 = rt:Get(lx - 2, ly)
        local _, _, _, a2 = rt:Get(p.x, p.y)
        local r3, g3, b3, a3 = rt:Get(lx + 2, ly)
        check(r1 == 0 and g1 == 0 and b1 == 0 and a1 == 255 and a2 == 0 and r3 == 244 and g3 == 255 and b3 == 0 and a3 == 255,
            "T7 a 2 px outline: black at 255 round the letter (%d %d %d %d), the letter yellow (%d %d %d %d), alpha 0 beyond (%d)", r1, g1, b1, a1, r3, g3, b3, a3, a2)
        check(p.w == 13 * 6 + 4 + 4 and p.h == 20 + 4 + 4, "T7 the picture grows by the outline all round (%d x %d)", p.w, p.h)
    else
        check(false, "T7 the outlined picture was made")
    end
end

-- T8 THE BOUND: 2 pages; a full atlas empties its least recently shown page, and what was on it is made again on demand
do
    reset_session()
    T.Clear()
    local rts0, pages0 = M.nrts, #T.pages
    local shown = {}
    for i = 1, 60 do
        local s = "a line of text number " .. i
        T.Get(s, "charselect_skin", 20, WHITE)
        M.run_hook("PostRender")
        M.frameNo = (M.frameNo or 0) + 1
        shown[#shown + 1] = s
    end
    check(#T.pages == 2 and M.nrts - rts0 == 2 - pages0, "T8 60 texts of 290 px: 2 pages at most, no render target beyond them (%d pages, %d new targets)", #T.pages, M.nrts - rts0)
    check(T.stats.emptied > 0 and logged("emptied for room (the least recently shown)"), "T8 a page emptied for room, said in the log (%d)", T.stats.emptied)
    local first = T.Get(shown[1], "charselect_skin", 20, WHITE)
    check(first == nil and #T.queue == 1, "T8 the first text's page was emptied: asked again, it is made again")
    M.run_hook("PostRender")
    check(T.Get(shown[1], "charselect_skin", 20, WHITE) ~= nil, "T8 and drawn the frame after")
    local line = T.AtlasLine()
    check(string.find(line, "of at most 2 pages of 512 x 128 in use", 1, true) ~= nil, "T8 the page says how full the atlas is (%s)", line)
    -- a text too wide for a page: the caller's own way, no retry each frame
    T.Get(string.rep("W", 60), "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    check(T.Get(string.rep("W", 60), "charselect_skin", 20, WHITE) == nil and #T.queue == 0, "T8 a text wider than a page: never made, never asked again")
    -- the verifier's LOW: a picture a little taller than a shelf can be (here 121 of 128 - 4 canary rows) passed the old check, then no page took it, and a full atlas emptied a page for nothing
    local e0, pages1 = T.stats.emptied, #T.pages
    T.said.make_failed = nil
    T.Get("AB", "charselect_skin", 117, WHITE)
    M.run_hook("PostRender")
    check(T.MaxPicH(128) == 120 and T.PackInto(T.NewPage(512, 128), 30, 120) ~= nil and T.PackInto(T.NewPage(512, 128), 30, 121) == nil, "T8 the tallest picture a page takes is the packer's own: 120 of 128 here")
    check(pages1 == 2 and T.stats.emptied == e0 and T.Get("AB", "charselect_skin", 117, WHITE) == nil and #T.queue == 0 and logged("a page takes 512 x 120 at most"),
        "T8 a 121 px picture with the atlas full: refused before any page is emptied (%d emptied, was %d)", T.stats.emptied, e0)
end

-- T9 a new resolution, a device reset, the button: made again on demand
do
    reset_session()
    T.Get("Up: Metal Sonic", "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    sw, sh = 2560, 1440
    M.run_hook("OnScreenSizeChanged")
    check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == false and #T.queue == 1, "T9 a new resolution: a new picture is asked for")
    M.run_hook("PostRender")
    check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == true, "T9 and drawn")
    sw, sh = 1920, 1080
    M.run_hook("OnScreenSizeChanged")
    T.Get("Up: Metal Sonic", "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    -- a device reset: every texel lost (opaque black again); the window loses and gets back the focus; half a second later the canary is read
    local p = T.Get("Up: Metal Sonic", "charselect_skin", 20, WHITE)
    M.focus = false
    M.run_hook("PostRender")
    if p then p.page.rt:Fill(0, 0, 0, 255) end
    M.focus = true
    M.run_hook("PostRender")
    check(T.Get("Up: Metal Sonic", "charselect_skin", 20, WHITE) ~= nil, "T9 the focus back: nothing read yet (half a second)")
    M.T = M.T + 1
    M.run_hook("PostRender")
    check(T.Get("Up: Metal Sonic", "charselect_skin", 20, WHITE) == nil and logged("the render targets were lost (device reset)"), "T9 then the canary is read: lost, every picture made again")
    M.run_hook("PostRender")
    check(T.Get("Up: Metal Sonic", "charselect_skin", 20, WHITE) ~= nil, "T9 and drawn again")
    -- the focus back without a loss: nothing made again
    local made0 = T.stats.made
    M.focus = false
    M.run_hook("PostRender")
    M.focus = true
    M.run_hook("PostRender")
    M.T = M.T + 1
    M.run_hook("PostRender")
    check(T.Get("Up: Metal Sonic", "charselect_skin", 20, WHITE) ~= nil and T.stats.made == made0, "T9 the focus back with the targets kept: nothing made again")
    -- the button
    check(M.cmds.gsa1_text_clear ~= nil, "T9 the command gsa1_text_clear")
    M.cmds.gsa1_text_clear()
    check(T.Get("Up: Metal Sonic", "charselect_skin", 20, WHITE) == nil and #T.queue == 1, "T9 Make the text pictures again: made again when next shown")
    M.run_hook("PostRender")
end

-- T17 THE READ-BACK DECIDES (the verifier's MEDIUM: a failed check used to change nothing but a log line). In the pixel model: a host that ignores the separate alpha factors (the clear's alpha 0
-- comes out 255: the owner's black boxes), a host whose text writes no alpha (invisible letters), a host that cannot read back; then the button reads again
do
    local function fresh()
        reset_session()
        T.Clear()
        logs = {}
    end
    -- boxes
    fresh()
    R.separate_alpha = false
    T.Get("BOXED", "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    local made = T.mem[next(T.mem)]
    check(made and made.page ~= nil, "T17 the picture was made (into the page)")
    check(T.check.state == "bad" and T.Get("BOXED", "charselect_skin", 20, WHITE) == nil and T.Draw("BOXED", "charselect_skin", 20, WHITE, 0, 0) == false,
        "T17 its corners read opaque: it is NOT handed out, the caller draws the text with the font (%s)", tostring(T.check.state))
    check(logged("NOT OK, please report this line") and logged("would sit in a box") and logged("drawn with the font from now on"), "T17 the log says it, and why: %s", tostring(logged("NOT OK")))
    T.Get("ANOTHER", "charselect_skin", 20, WHITE)
    check(#T.queue == 0 and string.find(T.AtlasLine(), "OFF, the texts are drawn with the font", 1, true) == 1, "T17 nothing more is made; the Text page says the pictures are off (%s)", T.AtlasLine())
    R.separate_alpha = true
    -- the button reads again
    M.cmds.gsa1_text_clear()
    T.Get("BOXED", "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    check(T.check.state == "ok" and T.Get("BOXED", "charselect_skin", 20, WHITE) ~= nil and logged("ok (transparent round the letters)"), "T17 Make the text pictures again: read again, ok, drawn")
    -- letters without alpha: not a verdict on one picture (its letters may be a few dots), on T.CHECK_TRIES
    fresh()
    TXT.noalpha = true
    for i = 1, T.CHECK_TRIES do T.Get("NO ALPHA " .. i, "charselect_skin", 20, WHITE) end
    M.run_hook("PostRender")
    local handed = 0
    for i = 1, T.CHECK_TRIES do if T.Get("NO ALPHA " .. i, "charselect_skin", 20, WHITE) then handed = handed + 1 end end
    check(T.check.state == "bad" and handed == 0 and logged("but no letter read") and logged("the letters read alpha 0 at most in 3 pictures"),
        "T17 letters that read alpha 0 in %d pictures: none handed out (%d), the log says it", T.CHECK_TRIES, handed)
    TXT.noalpha = nil
    -- the first picture without a letter read, the second with: handed out from the second on, never before
    fresh()
    TXT.noalpha = true
    T.Get("DOTS", "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    check(T.check.state == nil and T.Get("DOTS", "charselect_skin", 20, WHITE) == nil, "T17 one picture with no letter read: not yet a verdict, nothing handed out yet")
    TXT.noalpha = nil
    T.Get("LETTERS", "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    check(T.check.state == "ok" and T.Get("LETTERS", "charselect_skin", 20, WHITE) ~= nil, "T17 the next one reads right: pictures are handed out")
    -- not readable here: drawn unchecked (the path is cl_textures.lua's), said once
    fresh()
    local rp = render.ReadPixel
    render.ReadPixel = function() return nil end
    T.Get("UNREAD", "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    render.ReadPixel = rp
    check(T.check.state == "unreadable" and T.Get("UNREAD", "charselect_skin", 20, WHITE) ~= nil and logged("not readable here"), "T17 a host that cannot read back: drawn unchecked, said in the log")
    fresh()
end

-- T18 A SCREEN SMALLER THAN A PAGE (the verifier's LOW, UNVERIFIED whether Garry's Mod draws into a render target past the screen): pictures and the canary keep inside the screen's part of the page
do
    reset_session()
    sw, sh = 400, 100
    M.run_hook("OnScreenSizeChanged")
    local pics = {}
    for i = 1, 5 do
        T.Get("a line of text number " .. i, "charselect_skin", 20, WHITE)
        M.run_hook("PostRender")
    end
    local inside, n = 0, 0
    for i = 1, 5 do
        local p = T.Get("a line of text number " .. i, "charselect_skin", 20, WHITE)
        if p then
            n = n + 1
            pics[#pics + 1] = p
            if p.x + p.w <= 400 and p.y + p.h <= 100 - T.CANARY and math.abs(p.u1 * 512 - (p.x + p.w)) < 1e-6 and math.abs(p.v1 * 128 - (p.y + p.h)) < 1e-6 then inside = inside + 1 end
        end
    end
    check(n == 5 and inside == 5, "T18 a 400 x 100 screen: 5 pictures, all inside its 400 x 100 of the 512 x 128 page, their UVs the page's (%d of %d)", inside, n)
    local pg = pics[1] and pics[1].page
    local cr, cg, cb, ca = nil, nil, nil, nil
    if pg then cr, cg, cb, ca = pg.rt:Get(0, 98) end
    check(cr == 37 and cg == 201 and cb == 93 and ca == 0, "T18 the canary at the bottom left of the screen's part (x 0..1, rows 98..99), at alpha 0 (%s %s %s %s)", tostring(cr), tostring(cg), tostring(cb), tostring(ca))
    -- a device reset there is still seen
    if pg then pg.rt:Fill(0, 0, 0, 255) end
    M.focus = false
    M.run_hook("PostRender")
    M.focus = true
    M.run_hook("PostRender")
    M.T = M.T + 1
    logs = {}
    M.run_hook("PostRender")
    check(logged("the render targets were lost (device reset)") ~= nil, "T18 and a device reset is seen there")
    sw, sh = 1920, 1080
    M.run_hook("OnScreenSizeChanged")
    T.Get("a line of text number 1", "charselect_skin", 20, WHITE)
    M.run_hook("PostRender")
    local back = T.Get("a line of text number 1", "charselect_skin", 20, WHITE)
    check(back ~= nil and T.pages[1].w == 512 and T.pages[1].h == 128, "T18 the screen back to 1920 x 1080: the whole page again (%s x %s)", tostring(T.pages[1] and T.pages[1].w), tostring(T.pages[1] and T.pages[1].h))
end

-- odd text: the key stays 16 hex digits, whatever it holds; bytes that look like a path or a format stay text
do
    local odd = { "../../../autoexec.cfg", "a/b\\c:d", "100% %s %n", "\0zero\0", "Sonic \227\131\134\227\130\185\227\131\136", string.rep("x", 3000) }
    local bad, seen, same = 0, {}, 0
    for _, s in ipairs(odd) do
        local n = T.FileName(s, "bauhaus", 20, WHITE, 1920, 1080)
        if not string.match(n, "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%.png$") then bad = bad + 1 end
        if seen[n] then same = same + 1 end
        seen[n] = true
    end
    check(bad == 0 and same == 0, "T15 odd text: every key is 16 hex digits, none the same (%d, %d)", bad, same)
    local k = T.FileName("a", "bauhaus", 20, WHITE, 1920, 1080)
    check(T.FileName("a\0bauhaus", "bauhaus", 20, WHITE, 1920, 1080) ~= k, "T15 a text cannot run into the next field")
    T.Draw("100% %s %n", "charselect_skin", 20, WHITE, 0, 0)
    local ok = pcall(M.run_hook, "PostRender")
    check(ok and T.Draw("100% %s %n", "charselect_skin", 20, WHITE, 0, 0) == true, "T15 a text with format characters is made and drawn")
end

-- no garbage a frame: an element that shows its text for seconds makes none
do
    T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1)
    M.run_hook("PostRender")
    -- (this test's own fakes keep what they were given: not the module's garbage)
    local rect0, mat0, col0 = surface.DrawTexturedRectUV, surface.SetMaterial, surface.SetDrawColor
    surface.DrawTexturedRectUV, surface.SetMaterial, surface.SetDrawColor = function() end, function() end, function() end
    -- (a first round, so that what LuaJIT's compiler keeps for its traces is not counted as garbage)
    for _ = 1, 10000 do
        T.FontFor("charselect_skin", 20)
        T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1)
    end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 10000 do
        T.FontFor("charselect_skin", 20)
        T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1)
    end
    local grew = collectgarbage("count") - before
    collectgarbage("restart")
    surface.DrawTexturedRectUV, surface.SetMaterial, surface.SetDrawColor = rect0, mat0, col0
    -- (the smallest thing Lua can allocate is over 16 bytes: one a frame would be over 156 KB here)
    check(grew < 64, "T16 10000 frames of an element in its picture: %.2f KB of Lua garbage: nothing a frame", grew)
    info("%.2f KB of Lua garbage over 10000 frames (the engine's own calls are mocks here)", grew)
end

-- the elements: photo mode's reminder through its own hook -------------------------------------------------------------------------------------------------------------------------------------------------------------
local P = GSA1.Photo
check(P ~= nil, "the photo feature is there")
local photo_src = host_read(root .. "/gsa1/feat/cl_photo.lua")
local select_src = host_read(root .. "/gsa1/feat/cl_charselect.lua")
check(string.find(photo_src, "Tx.FontFor(\"photo_hint\"", 1, true) ~= nil and string.find(photo_src, "Tx.Draw(s, \"photo_hint\"", 1, true) ~= nil, "T10 photo mode's reminder asks the module")
check(select(2, string.gsub(select_src, "skin_line%(hint, W, H, 0%.", "")) == 1 and string.find(select_src, "local hint = S.SkinLineS and S.SkinLineS(st)", 1, true) ~= nil,
    "T10 1.0.0: only the simple chooser draws a skin line, through the module (the game's screen: the counter, the name and the nameplate say it)")
if P then
    local function run_reminder()
        counts.simple = {}
        P.state, P.moved, P.t0, P.hintLines = "on", false, SysTime(), nil
        GSA1.Char = GSA1.Char or {}
        M.run_hook("DrawOverlay")
    end
    -- the option off: exactly today's
    reset_session()
    M.files["resource/fonts/FOT-Rodin Pro UB.otf"] = "not a font"
    taken["FOT-Rodin Pro UB"] = 14
    T.cv:SetInt(0)
    local uv0 = counts.uv
    run_reminder()
    check(#counts.simple > 0 and counts.simple[1].font == "DermaLarge" and counts.uv == uv0, "T11 gsa1_text_fonts 0: today's DermaLarge by draw.SimpleText, no picture (%d lines)", #counts.simple)
    check(T.Draw("x", "photo_hint", 32, WHITE, 0, 0) == false, "T11 and T.Draw says no")
    T.cv:SetInt(1)
    run_reminder()
    check(#counts.simple > 0 and counts.simple[1].font == "GSA1Text_rodin_32", "T12 on, found, not ready: the caller draws it in the chosen font (%s)", tostring(counts.simple[1] and counts.simple[1].font))
    local njobs = #T.queue
    check(njobs >= 1, "T12 its lines are queued (%d)", njobs)
    for _ = 1, njobs do M.run_hook("PostRender") end
    counts.uv = 0
    run_reminder()
    -- (a line wider than this test's 512 px page stays drawn with the font: never made, never asked again)
    local wide = 0
    for _, l in ipairs(counts.simple) do
        surface.SetFont(l.font)
        if surface.GetTextSize(l.text) + 4 > T.PAGE_W then wide = wide + 1 end
    end
    check(wide == #counts.simple and counts.uv >= 1, "T12 then it draws from its pictures (%d), only a line wider than a page with the font (%d of %d)", counts.uv, wide, #counts.simple)
    P.state = "off"
end

-- the page -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local seen, helps = {}, {}
    local panel = setmetatable({}, { __index = function(t, k)
        return function(self, a, b)
            if k == "CheckBox" then seen[b] = a end
            if k == "Button" then seen[b] = a end
            if k == "Help" or k == "ControlHelp" then helps[#helps + 1] = a end
        end
    end })
    T.Page(panel)
    check(seen.gsa1_text_fonts ~= nil, "T13 gsa1_text_fonts has a check box on its page")
    check(seen.gsa1_text_clear ~= nil and seen.gsa1_skins_hud_remake ~= nil, "T13 and both make-again buttons")
    local text = table.concat(helps, "\n")
    check(string.find(text, "Photo mode's reminder", 1, true) ~= nil and string.find(text, "Character Select's skin line", 1, true) ~= nil, "T13 the page says which font each element found")
    check(string.find(text, "nothing is saved to disk", 1, true) ~= nil and string.find(text, "pages of", 1, true) ~= nil, "T13 and that the pictures live in the game's memory, how full")
    local m = GSA1.MenuPages
    local found = false
    for _, p in ipairs(m or {}) do found = found or p.id == "text" end
    check(found or not m, "T13 the page is on the menu")
end

-- nothing of a font's in the addon: the walk is repos/sync_repos_fonts_test.py's; here, that the code names no path into the addon, and writes no picture
local text_src = host_read(root .. "/gsa1/feat/cl_text.lua") .. host_read(root .. "/gsa1/feat/sh_text.lua")
check(string.find(text_src, "addons/", 1, true) == nil and string.find(text_src, "materials/", 1, true) == nil, "T14 pictures and fonts are looked for only in resource/fonts")
do
    local code = string.gsub(host_read(root .. "/gsa1/feat/cl_text.lua"), "%-%-[^\n]*", "")
    check(string.find(code, "render.Capture(", 1, true) == nil and string.find(code, "file.Write", 1, true) == nil, "T14 cl_text.lua's code neither captures nor writes a file")
end
check(T.VERSION == 3, "T14 T.VERSION 3 (the atlas)")
do
    check(T.FileName("x", "rodin", 20, WHITE, 1920, 1080, 2) ~= T.FileName("x", "rodin", 20, WHITE, 1920, 1080) and
        T.FileName("x", "rodin", 20, WHITE, 1920, 1080, "2:0,40,150") ~= T.FileName("x", "rodin", 20, WHITE, 1920, 1080, 2), "T7 an outline, and its colour, are in the key")
end
-- the pure packer
do
    local p = T.NewPage(100, 40)
    local x1, y1 = T.PackInto(p, 30, 10)
    local x2, y2 = T.PackInto(p, 30, 12)
    local x3, y3 = T.PackInto(p, 60, 10)
    local x4 = T.PackInto(p, 101, 5)
    check(x1 == 0 and y1 == 0 and x2 == 32 and y2 == 0 and x3 == 0 and y3 == 18 and x4 == nil, "T8 the packer: one shelf of a height class, a gutter of 2, the next shelf below, nothing wider than a page")
    local x5 = T.PackInto(p, 10, 30)
    check(x5 == nil, "T8 the packer: the last rows are the canary's")
    local a, b = { used = 5 }, { used = 3 }
    check(T.Victim({ a, b }) == 2, "T8 the least recently shown page is the one emptied")
end
-- RX.11: the new elements name one of the owner's three first, then a family Windows has, then today's engine font. 1.0.0-beta1a: the skins' name in Bauhaus, the plate in Gill Sans (the game's faces)
do
    local need = { skin_name = "arial_black", skin_plate = "arial_black", upgrades_title = "arial_black", upgrades_status = "impact", upgrades_name = "impact", bar_label = "arial_black" }
    local bad = {}
    for name, sys in pairs(need) do
        local e = T.ELEMENTS[name]
        if not (e and T.FONTS[e.font] and T.FONTS[e.font].file and e.system == sys and T.FONTS[sys].system and e.fallback) then bad[#bad + 1] = name end
    end
    check(#bad == 0, "RX.11 the six new elements: one of the owner's fonts first, then Arial Black or Impact, then today's (%s)", table.concat(bad, ", "))
    check(T.ELEMENTS.skin_name.font == "bauhaus" and T.ELEMENTS.skin_plate.font == "gill", "b1a the skin's name in Bauhaus (the game's names), its plate in Gill Sans Bold (the game's plates)")
    -- (Gill Sans is not in this test's resource/fonts: the bar's labels show the second and third choices)
    reset_session()
    taken["Arial Black"] = 9
    check(T.FontFor("bar_label", 24) == "GSA1Text_arial_black_24", "RX.11 the owner's font missing: the Windows family the engine took (%s)", tostring(T.FontFor("bar_label", 24)))
    taken["Arial Black"] = nil
    reset_session()
    check(T.FontFor("bar_label", 24) == "DermaDefaultBold", "RX.11 neither: today's engine font")
    for _, f in pairs(T.FONTS) do
        check(f.system or (f.file and not string.find(f.file, "/", 1, true)), "RX.11 %s: a file name only, looked for in garrysmod/resource/fonts (never shipped)", f.title)
    end
end
-- T19 THE NAMES FIX (sadc/build/research/b1a2): a picture its caller paints (feat/cl_skinhud.lua's names and plates) is a box of these same pages: placed with a clear margin, painted by T.Paint at its
-- place, read back by T.ReadBack in its own px, drawn with T.DrawPic (a part of it too), gone with its page. Beta 1a gave each its own render target (T.Canvas, retired)
do
    reset_session()
    T.LoseAll("T19")
    check(T.Canvas == nil and T.CanvasValid == nil and T.canvases == nil, "T19 no canvas any more (beta 1a's T.Canvas retired): no gsa1_canvas_* render target can be made")
    local pic = T.Place(100, 20, 4)
    check(pic ~= nil and pic.page ~= nil and pic.mat == pic.page.mat and pic.x == pic.ax + 4 and pic.y == pic.ay + 4 and pic.aw == 108 and pic.ah == 28 and pic.w == 100 and pic.h == 20
        and math.abs(pic.u0 * 512 - pic.x) < 1e-6 and math.abs(pic.u1 * 512 - (pic.x + 100)) < 1e-6 and math.abs(pic.v1 * 128 - (pic.y + 20)) < 1e-6,
        "T19 T.Place: a box of a page with its margin; its UVs are the picture inside it (%s)", pic and string.format("%d,%d %dx%d in %d,%d %dx%d", pic.x, pic.y, pic.w, pic.h, pic.ax, pic.ay, pic.aw, pic.ah) or "none")
    local ok = pic and T.PaintPic(pic, function(x, y)
        T.ClearRect(pic.ax, pic.ay, pic.aw, pic.ah, 0, 0, 0)
        T.FillRect(x + 10, y + 5, 30, 10, 200, 100, 50, 255)
    end)
    local got = pic and T.ReadPic(pic, function(read)
        local r, g, b, a = read(15, 8)
        local _, _, _, a0 = read(-4, -4)
        return { r, g, b, a, a0, read(-5, 0) == nil and read(104, 0) == nil and read(0, 24) == nil }
    end)
    check(ok and got and got[1] == 200 and got[2] == 100 and got[3] == 50 and got[4] == 255 and got[5] == 0 and got[6] == true,
        "T19 T.PaintPic paints at the picture's place, T.ReadPic reads it in its own px: the fill, its margin clear, nothing outside its box")
    local cr, cg, cb, ca = pic.page.rt:Get(1, pic.page.h - 1)
    check(cr == 37 and cg == 201 and cb == 93 and ca == 0, "T19 the page's canary set by the paint, as every picture's (%s %s %s %s)", tostring(cr), tostring(cg), tostring(cb), tostring(ca))
    local pic2 = T.Place(50, 20, 4)
    T.PaintPic(pic2, function(x, y)
        T.ClearRect(pic2.ax, pic2.ay, pic2.aw, pic2.ah, 0, 0, 0)
        T.FillRect(x, y, 50, 20, 9, 9, 9, 255)
    end)
    local again = T.ReadPic(pic, function(read) return { read(15, 8) } end)
    check(pic2 and pic2.page == pic.page and pic2.ax >= pic.ax + pic.aw and again and again[1] == 200, "T19 a neighbour placed and painted beside it: the first picture unchanged")
    local u0 = #uvs
    T.DrawPic(pic, 10, 20, 100, 20, 255, 255, 255, 128, 0, 0, 0.5, 1)
    T.DrawPic(pic, 10, 20, 100, 20)
    local a, b = uvs[u0 + 1], uvs[u0 + 2]
    check(a and b and math.abs(a.u0 - pic.u0) < 1e-9 and math.abs(a.u1 - (pic.u0 + 0.5 * (pic.u1 - pic.u0))) < 1e-9 and a.v1 == pic.v1 and b.u0 == pic.u0 and b.u1 == pic.u1 and b.v1 == pic.v1,
        "T19 T.DrawPic: the whole picture by its UVs, or a part of it inside them")
    check(T.PicValid(pic), "T19 valid while its page holds it")
    T.LoseAll("T19")
    check(not T.PicValid(pic) and T.ReadPic(pic, function() return 1 end) == nil and select(1, T.PaintPic(pic, function() end)) == false, "T19 its page emptied: no longer valid, neither painted nor read")
    check(T.Place(600, 20, 0) == nil and T.Place(100, 120, 4) == nil, "T19 a box wider than a page, or taller than a page takes: no place")
end

-- T20 (the names fix: beta 1a's T.CheckLost read only the first page that held pictures, and a canvas never) the canary of EVERY page that holds pictures is read after the focus comes back
do
    reset_session()
    T.LoseAll("T20")
    local lost0 = T.stats.lost
    local a = T.Place(500, 100, 0)
    local b = T.Place(500, 100, 0)
    check(a and b and a.page ~= b.page, "T20 two pages hold pictures")
    if a and b then
        T.PaintPic(a, function() end)
        T.PaintPic(b, function() end)
        check(T.CheckLost() == 2 and T.stats.lost == lost0, "T20 both pages' canaries read, both kept: nothing made again")
        b.page.rt:Fill(0, 0, 0, 255)
        logs = {}
        local n = T.CheckLost()
        check(n == 2 and T.stats.lost == lost0 + 1 and logged("the render targets were lost (device reset)") and not T.PicValid(a) and not T.PicValid(b),
            "T20 the SECOND page lost (beta 1a never read it): found, every picture made again (%d pages read)", n)
    end
end
-- T21 (b1a2-fix2) THE SMALL READ: T.ReadTexels draws each asked texel of a page through the page's own material (render.SetMaterial, a mesh quad, ONE / ZERO) into a cell of a 16 x 4 target made
-- like cl_textures.lua's probes, and reads that; T.CheckLost reads every page's canary that way in one capture, against what the same read gave at the page's make
do
    reset_session()
    T.LoseAll("T21")
    local capname, xform = nil, nil
    local cap0, rp0 = render.CapturePixels, render.ReadPixel
    local caps = {}
    render.CapturePixels = function()
        capname = R.cur and R.cur.name
        caps[#caps + 1] = capname
        return cap0()
    end
    render.ReadPixel = function(x, y)
        local r, g, b, a = rp0(x, y)
        if xform and r and string.find(capname or "", "gsa1_textread_", 1, true) then r, g, b = xform(r), xform(g), xform(b) end
        return r, g, b, a
    end
    local a = T.Place(100, 20, 4)
    T.PaintPic(a, function(x, y)
        T.ClearRect(a.ax, a.ay, a.aw, a.ah, 0, 0, 0)
        T.FillRect(x, y, 30, 10, 200, 100, 50, 255)
        T.FillRect(x + 30, y, 30, 10, 255, 255, 255, 0)
        T.FillRect(x + 60, y, 30, 10, 9, 8, 7, 128)
    end)
    local p = a.page
    caps = {}
    local got, err, ms = T.ReadTexels({ { page = p, x = a.x + 5, y = a.y + 5 }, { page = p, x = a.x + 35, y = a.y + 5 }, { page = p, x = a.x + 65, y = a.y + 5 }, { page = p, x = a.x + 95, y = a.y + 15 }, { page = p, x = 1, y = p.h - 1 } })
    local rd = T.Reader()
    check(got and got[1][1] == 200 and got[1][2] == 100 and got[1][3] == 50 and got[1][4] == 255 and got[2][4] == 0 and got[3][1] == 9 and got[3][4] == 128 and got[4][4] == 0
        and got[5][1] == 37 and got[5][4] == 0 and #caps == 1 and caps[1] == rd.name,
        "T21 the texels as the page holds them (200 100 50 255, alpha 0, 9 8 7 128, clear, the canary), in one capture of the small target %s, not of the page (%s)", tostring(rd and rd.name), table.concat(caps, ", "))
    check(rd.rt.w == 16 and rd.rt.h == 4 and rd.rt.depth == MATERIAL_RT_DEPTH_NONE and bit.band(rd.rt.flags or 0, 0x301) == 0x301 and rd.rt.fmt == GSA1.Tex.format.fmt,
        "T21 the small target is made like cl_textures.lua's probes: 16 x 4, no depth, no mips, point sampled, the probed format")
    -- what the page's material samples is what is read: its texture pointed at another target (Source's opaque black creation colour)
    local other = GetRenderTargetEx("gsa1_t21_other", 8, 8, 1, MATERIAL_RT_DEPTH_NONE, 0, 0, 12)
    local was = p.mat.params["$basetexture"]
    p.mat.params["$basetexture"] = other:GetName()
    local elsewhere = T.ReadTexels({ { page = p, x = a.x + 5, y = a.y + 5 } })
    p.mat.params["$basetexture"] = was
    check(elsewhere and elsewhere[1][1] == 0 and elsewhere[1][4] == 255, "T21 what the page's material samples is what is read (its texture another target: %s, not the page's 200 100 50 255)",
        elsewhere and T.RGBA(elsewhere[1]) or "nil")
    -- a copy that draws nothing reads the fill (alpha 77), never an old read's texels
    local mend = mesh.End
    mesh.End = function() end
    local nothing = T.ReadTexels({ { page = p, x = a.x + 5, y = a.y + 5 } })
    mesh.End = mend
    check(nothing and nothing[1][1] == 255 and nothing[1][2] == 0 and nothing[1][3] == 255 and nothing[1][4] == 77, "T21 a copy that draws nothing reads the fill %s, not the last read's texel", nothing and T.RGBA(nothing[1]) or "nil")
    local twenty = {}
    for i = 1, 20 do twenty[i] = { page = p, x = a.x + (i % 3) * 30 + 5, y = a.y + 5 } end
    local caps0 = #caps
    local many = T.ReadTexels(twenty)
    check(many and #many == 20 and many[20][1] == 9 and many[3][1] == 200 and #caps - caps0 == 2, "T21 more texels than a target holds (20 of 16): two copies, in order (%d captures)", #caps - caps0)
    check(p.canary0 and p.canary0[1] == 37 and p.canary0[2] == 201 and p.canary0[3] == 93 and p.canary0[4] == 0, "T21 the page's canary read at its make that way (%s)", p.canary0 and T.RGBA(p.canary0) or "nil")
    -- the canary read otherwise than painted (a host whose copy gives colours at 3/4): said once, compared with its make's read; no device reset, no remake
    xform = function(v) return math.floor(v * 0.75) end
    T.LoseAll("T21 the colours at 3/4")
    logs = {}
    local lost0 = T.stats.lost
    local b = T.Place(100, 20, 4)
    T.PaintPic(b, function() end)
    local c0 = b.page.canary0
    for _ = 1, 3 do
        M.focus = false
        M.run_hook("PostRender")
        M.focus = true
        M.run_hook("PostRender")
        M.T = M.T + 1
        M.run_hook("PostRender")
    end
    check(c0 and c0[1] == 27 and c0[2] == 150 and c0[3] == 69 and c0[4] == 0 and T.CanaryOff(c0, T.CanaryPainted()) and T.stats.lost == lost0 and T.PicValid(b)
        and logged("text pictures: page 1's canary reads 27 150 69 0 at its make through its material (painted 37 201 93 0)") and not logged("were lost (device reset)"),
        "T21 a canary read at its make otherwise than painted (%s): said once, three focus returns read it against that, nothing made again (the old rule, against the painted colour, made it all again each time)",
        c0 and T.RGBA(c0) or "nil")
    b.page.rt:Fill(0, 0, 0, 255)
    local n = T.CheckLost()
    check(n == 1 and T.stats.lost == lost0 + 1 and logged("the render targets were lost (device reset): page 1's canary reads 0 0 0 255, at its make 27 150 69 0"), "T21 by the same rule a real loss is still found: %s", tostring(logged("were lost (device reset)")))
    -- its alpha not the painted (the material samples something else at the make): not kept, said once; the painted colour is the reference
    xform = nil
    T.LoseAll("T21 the material elsewhere")
    logs = {}
    local c = T.Place(100, 20, 4)
    local cw = c.page.mat.params["$basetexture"]
    c.page.mat.params["$basetexture"] = other:GetName()
    T.PaintPic(c, function() end)
    c.page.mat.params["$basetexture"] = cw
    check(c.page.canary0 == nil and logged("its alpha not the painted 37 201 93 0: the material does not sample what was painted") and T.CheckLost() == 1 and T.PicValid(c),
        "T21 a make-time canary whose alpha is not the painted one: not taken as the reference (%s); the painted colour is, and reads right", tostring(logged("its alpha not")))
    render.CapturePixels, render.ReadPixel = cap0, rp0
    T.LoseAll("T21 done")
end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))

info("no real font file was used; how a real one looks, and the alpha vgui's letters really write, only the game can show (the log's \"text pictures: alpha check\" line)")
return done()
