-- feat_text_test.lua - text in a chosen font (round 0.9.9g; feat/sh_text.lua, feat/cl_text.lua, the two elements in feat/cl_photo.lua and feat/cl_charselect.lua). 1.0.0 (sadc docs/research/gsa1_100_select.md
-- 4.7 with RX.11, 4.8, 7.2 T7): the doubled skin line's cause (two texts in one bucket), T.VERSION 2, the new elements and their Windows families, outlines. The whole addon through its autorun, tests/lua_mock.lua, in
-- Garry's Mod's own LuaJIT. NO REAL FONT: a font "exists" here because a line in the mock's file table says so and its text measures differently; the pictures are the fake bytes this test's render.Capture gives.
--   lua_host tests/feat_text_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
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
do
    local ok, err = pcall(M.load, "autorun/gsa1_autorun.lua")
    local errs = GSA1 and GSA1.FeatureFileErrors or {}
    check(ok and #errs == 0, "the addon's client files load (%s)", tostring(err or errs[1] or "no error"))
end
local T = GSA1 and GSA1.Text
check(T ~= nil and T.Draw ~= nil, "the module loaded")
if not T then return done() end
local log0 = GSA1.Log
function GSA1.Log(kind, fmt, ...)
    logs[#logs + 1] = { kind = kind, text = string.format(fmt, ...) }
    if log0 then return log0(kind, fmt, ...) end
end
local function logged(pat)
    for _, l in ipairs(logs) do
        if string.find(l.text, pat, 1, true) then return true end
    end
    return false
end

-- the engine, as far as this feature asks. A font the "engine took" measures by its own width
local sw, sh = 1920, 1080
ScrW, ScrH = function() return sw end, function() return sh end
local fonts, cur = {}, nil
local taken = {}        -- [family] = a width per letter; absent: Windows' default face
local counts = { captures = 0, created = 0, drew = 0, simple = {}, rects = 0, pushes = 0 }
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
surface.SetTextColor = function() end
surface.SetTextPos = function() end
surface.DrawText = function() counts.drew = counts.drew + 1 end
surface.DrawTexturedRect = function(x, y, w, h)
    counts.rects = counts.rects + 1
    counts.last_rect = { x, y, w, h }
end
draw.SimpleText = function(text, font) counts.simple[#counts.simple + 1] = { text = text, font = font } end
render.PushRenderTarget = function() counts.pushes = counts.pushes + 1 end
render.PopRenderTarget = function() end
render.OverrideAlphaWriteEnable = function() end
render.Clear = function() end
render.OverrideBlend = function() end
local capture_gives = "\137PNG fake picture"
render.Capture = function(t)
    counts.captures = counts.captures + 1
    counts.last_capture = t
    return capture_gives
end
local mats = 0
Material = function(path, flags)
    mats = mats + 1
    return { path = path, flags = flags, IsError = function(self) return M.files[string.gsub(self.path, "^%.%./data/", "")] == nil end }
end
-- the mock's file table holds DATA and GAME paths alike; the DATA folder's listing, its sizes and times
local times, clock = {}, 0
local write0 = file.Write
file.Write = function(p, s)
    clock = clock + 1
    times[p] = clock
    return write0(p, s)
end
file.Time = function(p) return times[p] or 0 end
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
local function count_files()
    local n = 0
    for p in pairs(M.files) do
        if string.match(p, "^gsa1/textcache/") then n = n + 1 end
    end
    return n
end
local function reset_session()
    T.probe, T.mem, T.nmem, T.queue, T.said = {}, {}, 0, {}, {}
    logs = {}
end
local WHITE = { r = 255, g = 255, b = 255, a = 255 }

-- the hash ------------------------------------------------------------------------------------------------------------
local base = T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 1920, 1080)
check(string.match(base, "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%.png$") ~= nil, "T1 the name is 16 hex digits and .png (%s)", base)
check(T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 1920, 1080) == base, "T1 the same inputs, the same name")
check(T.FileName("Up: Sonic", "bauhaus", 20, WHITE, 1920, 1080) ~= base, "T1 another text, another name")
check(T.FileName("Up: Metal Sonic", "rodin", 20, WHITE, 1920, 1080) ~= base, "T1 another font, another name")
check(T.FileName("Up: Metal Sonic", "bauhaus", 21, WHITE, 1920, 1080) ~= base, "T1 another size, another name")
check(T.FileName("Up: Metal Sonic", "bauhaus", 20, { r = 255, g = 255, b = 254, a = 255 }, 1920, 1080) ~= base, "T1 another colour, another name")
check(T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 2560, 1080) ~= base and T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 1920, 1440) ~= base, "T1 another resolution, another name")
do
    local seen, same = {}, 0
    for i = 1, 4000 do
        local h = T.Hash("line " .. i)
        if seen[h] then same = same + 1 end
        seen[h] = true
    end
    check(same == 0, "T1 4000 short texts: %d of the same hash", same)
end

-- no file: today's font ------------------------------------------------------------------------------------------------
check(T.cv ~= nil and T.cv:GetBool(), "T2 gsa1_text_fonts defaults to 1")
reset_session()
check(T.FontFor("photo_hint", 32) == "DermaLarge", "T2 no font file: the reminder keeps today's DermaLarge")
check(T.FontFor("charselect_skin", 20) == "GSA1CharSelectHint", "T2 no font file: the skin line keeps today's font")
check(logged("Photo mode's reminder: today's DermaLarge") and logged("FOT-Rodin Pro UB.otf is not in garrysmod/resource/fonts"), "T2 the log says which was used, and why")
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == false and #T.queue == 0 and count_files() == 0, "T2 no font: no picture, nothing queued, nothing saved")
check(string.find(T.ElementLine("charselect_skin"), "today's GSA1CharSelectHint", 1, true) ~= nil, "T2 the page says so")

-- the file is there, the engine did not take it: as the .otf may turn out ---------------------------------------------------
reset_session()
M.files["resource/fonts/FOT-Rodin Pro UB.otf"] = "not a font"
check(T.FontFor("photo_hint", 32) == "DermaLarge", "T3 the file is there, the engine fell back: today's font")
check(logged("the engine did not take it") and logged("the same as with a font that does not exist"), "T3 the log tells the two apart")
check(string.find(T.ElementLine("photo_hint"), "the engine did not take it", 1, true) ~= nil, "T3 the page says so")

-- found: made once, saved, loaded later ---------------------------------------------------------------------------------------
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
M.run_hook("PostRender")
check(counts.captures == 1 and count_files() == 1 and M.files["gsa1/textcache/" .. T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 1920, 1080)] == capture_gives, "T4 the next frame: made and saved under its hash (%d captures, %d files)", counts.captures, count_files())
check(counts.last_capture and counts.last_capture.format == "png" and counts.last_capture.alpha == true and counts.last_capture.w == 13 * 15 + 4 and counts.last_capture.h == 24, "T4 a PNG with alpha, at the text's own size in pixels and 2 px round it (%s x %s)", tostring(counts.last_capture and counts.last_capture.w), tostring(counts.last_capture and counts.last_capture.h))
counts.rects = 0
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == true and counts.rects == 1, "T4 from then on it draws from the picture")
check(counts.last_rect[3] == 13 * 15 + 4 and counts.last_rect[1] == math.floor(960 - (13 * 15 + 4) / 2), "T4 at the size it was made, centred where asked, 1 to 1")
local pushes = counts.pushes
-- the next session
reset_session()
T.FontFor("charselect_skin", 20)
counts.rects = 0
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == true and counts.rects == 1 and #T.queue == 0, "T5 the next session loads the saved picture on the first frame")
M.run_hook("PostRender")
check(counts.captures == 1 and counts.pushes == pushes, "T5 and makes nothing again (%d captures)", counts.captures)
-- a resolution change
sw, sh = 2560, 1440
M.run_hook("OnScreenSizeChanged")
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == false and #T.queue == 1, "T6 a new resolution: a new picture is asked for")
M.run_hook("PostRender")
check(counts.captures == 2 and count_files() == 2, "T6 and made beside the old one (%d files)", count_files())
sw, sh = 1920, 1080
M.run_hook("OnScreenSizeChanged")

-- the capture refuses: today's way stays, one line in the log --------------------------------------------------------------------
logs = {}
capture_gives = nil
T.Draw("Another line", "charselect_skin", 20, WHITE, 0, 0)
M.run_hook("PostRender")
check(T.Draw("Another line", "charselect_skin", 20, WHITE, 0, 0) == false and #T.queue == 0 and logged("could not be made"), "T7 render.Capture gives nothing: the caller goes on drawing it, no retry each frame, one line in the log")
capture_gives = "\137PNG fake picture"

-- odd text: the name stays 16 hex digits, whatever it holds; bytes that look like a path or a format stay text
do
    local odd = { "../../../autoexec.cfg", "a/b\\c:d", "100% %s %n", "\0zero\0", "Sonic \227\131\134\227\130\185\227\131\136", string.rep("x", 3000) }
    local bad, seen, same = 0, {}, 0
    for _, s in ipairs(odd) do
        local n = T.FileName(s, "bauhaus", 20, WHITE, 1920, 1080)
        if not string.match(n, "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%.png$") then bad = bad + 1 end
        if seen[n] then same = same + 1 end
        seen[n] = true
    end
    check(bad == 0 and same == 0, "T15 odd text: every name is 16 hex digits, none the same (%d, %d)", bad, same)
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
    local rect0, mat0 = surface.DrawTexturedRect, surface.SetMaterial
    surface.DrawTexturedRect, surface.SetMaterial = function() end, function() end
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
    surface.DrawTexturedRect, surface.SetMaterial = rect0, mat0
    -- (the smallest thing Lua can allocate is over 16 bytes: one a frame would be over 156 KB here)
    check(grew < 64, "T16 10000 frames of an element in its picture: %.2f KB of Lua garbage: nothing a frame", grew)
    info("%.2f KB of Lua garbage over 10000 frames (the engine's own calls are mocks here)", grew)
end

-- the bounds -----------------------------------------------------------------------------------------------------------------------
local list = {}
for i = 1, 300 do list[i] = { name = string.format("%04d.png", i), size = 1000, time = i } end
local del = T.Trim(list, 256, 1024 * 1024)
check(#del == 44 and del[1] == "0001.png" and del[44] == "0044.png", "T8 by count: the 44 oldest of 300 (%d)", #del)
list = {}
for i = 1, 10 do list[i] = { name = string.format("%04d.png", i), size = 3 * 1024 * 1024, time = i } end
del = T.Trim(list, 256, 16 * 1024 * 1024)
check(#del == 5 and del[1] == "0001.png", "T8 by size: 30 MB comes down under 16 MB (%d deleted)", #del)
del = T.Trim({ { name = "a.png", size = 99 * 1024 * 1024, time = 1 } }, 256, 16 * 1024 * 1024, "a.png")
check(#del == 0, "T8 the picture just made is never the one deleted")
for i = 1, T.MAX_FILES + 20 do
    local line = "text number " .. i
    T.Draw(line, "charselect_skin", 20, WHITE, 0, 0)
    M.run_hook("PostRender")
end
check(count_files() <= T.MAX_FILES and count_files() >= T.MAX_FILES - 5, "T8 %d texts asked for: the folder holds %d, at most %d", T.MAX_FILES + 20, count_files(), T.MAX_FILES)
check(string.find(T.FolderLine(), "of at most 256 pictures", 1, true) ~= nil, "T8 the page says how full it is")

-- clear --------------------------------------------------------------------------------------------------------------------------------
M.files["gsa1/other.txt"] = "a file of someone else"
local cleared = T.Clear()
check(cleared > 0 and count_files() == 0 and M.files["gsa1/other.txt"] ~= nil and M.files["resource/fonts/BauhausStd-Bold.ttf"] ~= nil, "T9 clear: %d pictures gone, nothing else", cleared)
check(T.Draw("Up: Metal Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1) == false and #T.queue == 1, "T9 after a clear it is made again")
M.run_hook("PostRender")

-- the elements: photo mode's reminder through its own hook ---------------------------------------------------------------------------
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
    local made0, rects0 = counts.created, counts.rects
    run_reminder()
    check(#counts.simple > 0 and counts.simple[1].font == "DermaLarge" and counts.rects == rects0, "T11 gsa1_text_fonts 0: today's DermaLarge by draw.SimpleText, no picture (%d lines)", #counts.simple)
    check(T.Draw("x", "photo_hint", 32, WHITE, 0, 0) == false, "T11 and T.Draw says no")
    T.cv:SetInt(1)
    run_reminder()
    check(#counts.simple > 0 and counts.simple[1].font == "GSA1Text_rodin_32", "T12 on, found, not ready: the caller draws it in the chosen font (%s)", tostring(counts.simple[1] and counts.simple[1].font))
    local njobs = #T.queue
    check(njobs >= 1, "T12 its lines are queued (%d)", njobs)
    for _ = 1, njobs do M.run_hook("PostRender") end
    counts.rects = 0
    run_reminder()
    check(#counts.simple == 0 and counts.rects >= 1, "T12 then it draws only from its pictures (%d)", counts.rects)
    P.state = "off"
end

-- the page -----------------------------------------------------------------------------------------------------------------------------
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
    check(seen.gsa1_text_clear ~= nil, "T13 and clear has a button")
    local text = table.concat(helps, "\n")
    check(string.find(text, "Photo mode's reminder", 1, true) ~= nil and string.find(text, "Character Select's skin line", 1, true) ~= nil, "T13 the page says which font each element found")
    local m = GSA1.MenuPages
    local found = false
    for _, p in ipairs(m or {}) do found = found or p.id == "text" end
    check(found or not m, "T13 the page is on the menu")
end

-- nothing of a font's in the addon: the walk is repos/sync_repos_fonts_test.py's; here, that the code names no path into the addon
local text_src = host_read(root .. "/gsa1/feat/cl_text.lua") .. host_read(root .. "/gsa1/feat/sh_text.lua")
check(string.find(text_src, "addons/", 1, true) == nil and string.find(text_src, "materials/", 1, true) == nil, "T14 pictures and fonts are looked for only in resource/fonts and data/gsa1/textcache")

-- ---- T7 (1.0.0, select 4.8): the doubled skin line. A model of a render target as the owner's game showed it: render.Clear leaves the last picture's letters; only a draw that REPLACES colour and
-- alpha over the whole bucket empties it. Two texts of one bucket in a row: the second picture holds its own text only -----------------------------------------------------------------------------
do
    reset_session()
    local rts, cur_rt, blend = {}, nil, nil
    local made = {}
    GetRenderTargetEx = function(name, w, h) rts[name] = rts[name] or { name = name, w = w, h = h, texts = {} } return rts[name] end
    render.PushRenderTarget = function(rt) cur_rt = rt end
    render.PopRenderTarget = function() cur_rt = nil end
    render.Clear = function() end                                   -- (the owner's game: nothing emptied, sadc docs/research/gsa1_100_select.md 2.3)
    render.OverrideBlend = function(on, src, dst, op, sa, da) blend = on and { src, dst, sa, da } or nil end
    local full = {}
    surface.SetDrawColor = function() end
    surface.DrawRect = function(x, y, w, h)
        if cur_rt and blend and blend[1] == (BLEND_ONE or 1) and blend[2] == (BLEND_ZERO or 0) and blend[3] == (BLEND_ONE or 1) and blend[4] == (BLEND_ZERO or 0) and x <= 0 and y <= 0 and w >= cur_rt.w and h >= cur_rt.h then
            cur_rt.texts = {}
            full[#full + 1] = cur_rt.name
        end
    end
    surface.DrawText = function(s) if cur_rt then cur_rt.texts[#cur_rt.texts + 1] = s end end
    render.Capture = function() made[#made + 1] = cur_rt and table.concat(cur_rt.texts, "|") or "" return "\137PNG " .. made[#made] end
    -- (two new texts of 15 and 16 letters: 199 and 212 px, both in the 256 x 64 bucket, as the owner's 151 and 249 px were)
    T.Draw("Up: Mecha Sonic", "charselect_skin", 20, WHITE, 960, 800, 1, 1)
    M.run_hook("PostRender")
    T.Draw("MECHA SONIC (Up)", "charselect_skin", 20, WHITE, 960, 800, 1, 1)
    M.run_hook("PostRender")
    check(#full == 2 and full[1] == full[2] and full[1] == "gsa1_text_256x64", "T7 both jobs of one bucket start with the full-bucket replace draw (%d; %s)", #full, tostring(full[1]))
    check(made[2] == "MECHA SONIC (Up)" and not string.find(made[2] or "", "Up: Mecha Sonic", 1, true), "T7 the second picture holds only its own text (%s)", tostring(made[2]))
    -- an outline: the text drawn round itself, then itself on top
    T.Draw("ACTIVE", "charselect_skin", 20, WHITE, 0, 0, 0, 1, 2)
    M.run_hook("PostRender")
    local parts = 0
    for _ in string.gmatch(made[#made] or "", "ACTIVE") do parts = parts + 1 end
    check(parts > 8, "T7 an outline of 2 px: the text drawn round itself before the text (%d draws of it)", parts)
end
check(T.VERSION == 2, "T7 T.VERSION 2")
do
    local saved = T.VERSION
    local a = T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 1920, 1080)
    T.VERSION = 1
    local b = T.FileName("Up: Metal Sonic", "bauhaus", 20, WHITE, 1920, 1080)
    T.VERSION = saved
    check(a ~= b, "T7 version 2 changes every name: a picture 0.9.9g made over another's leftovers is never loaded again")
    check(T.FileName("x", "rodin", 20, WHITE, 1920, 1080, 2) ~= T.FileName("x", "rodin", 20, WHITE, 1920, 1080) and
        T.FileName("x", "rodin", 20, WHITE, 1920, 1080, "2:0,40,150") ~= T.FileName("x", "rodin", 20, WHITE, 1920, 1080, 2), "T7 an outline, and its colour, are in the name")
end
-- RX.11: the new elements name one of the owner's three first, then a family Windows has, then today's engine font
do
    local need = { skin_name = "arial_black", skin_plate = "arial_black", upgrades_title = "arial_black", upgrades_status = "impact", upgrades_name = "impact", bar_label = "arial_black" }
    local bad = {}
    for name, sys in pairs(need) do
        local e = T.ELEMENTS[name]
        if not (e and T.FONTS[e.font] and T.FONTS[e.font].file and e.system == sys and T.FONTS[sys].system and e.fallback) then bad[#bad + 1] = name end
    end
    check(#bad == 0, "RX.11 the six new elements: one of the owner's fonts first, then Arial Black or Impact, then today's (%s)", table.concat(bad, ", "))
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

info("no real font file was used; how a real one looks only the game can show")
return done()
