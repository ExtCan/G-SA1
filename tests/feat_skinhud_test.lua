-- feat_skinhud_test.lua - a skin's name and nameplate pictures (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 4.7 with RX.11, 7.2 T6): feat/sh_skinhud.lua and feat/cl_skinhud.lua through the
-- addon's autorun, tests/lua_mock.lua, in Garry's Mod's own LuaJIT, on tests/lua_mock_rt.lua, the pixel model of Garry's Mod's render targets as this project MEASURED them, with a model of letters
-- (each a box whose height is the font's capitals). The layout numbers are the game's, MEASURED on its pictures (numbers only; no game byte, no font here).
-- THE NAMES FIX after 1.0.0-beta1a (sadc/build/research/b1a2; the owner: "The pulsating names appear for a second and then turn into black squares"): the pictures are parts of the text atlas's
-- 2048 x 1024 pages at 2 x the game's on 3440 x 1440 (never a render target of their own), made one paint and one read a frame, drawn by S.DrawFilter with surface.DrawTexturedRectUV at the game's
-- quad, read again at most once a second while shown, and never drawn again once a read is wrong (the game's own instead), made again once. Here: every one of those, and the fallback on black, on
-- a changed letter texel, on the page's canary, on a binding pointing elsewhere and on an unreadable read; the real path is tests/feat_skinhud_binding_test.cpp (feat_skinhud_real.lua).
-- WHAT ONLY THE GAME CAN SHOW: the real letters, what Garry's Mod's engine does to a page in the owner's session (the log's "skin pictures check" lines), and what the owner sees on the screen.
--   lua_host tests/feat_skinhud_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local R = host_load(host_read(tests .. "/lua_mock_rt.lua"), "lua_mock_rt.lua")()(M)
local check, info = M.check, M.info
print("G-SA1 feat_skinhud_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end
local cookies = {}
cookie = { GetNumber = function(k, d) return tonumber(cookies[k]) or d end, Set = function(k, v) cookies[k] = v end, GetString = function(k, d) return cookies[k] or d end }
local G = M.module({ speed = 300, features = { super = 5, frontend = 1 } })
M.scrw, M.scrh = 3440, 1440

-- the engine, as far as the pictures ask ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- (a capture without the copy: the pixel model's copies 4 x 2 M values of a 2048 x 1024 page; nothing writes between a capture and its reads here, so reading the target itself is the same)
-- b1a2-fix2: every capture's target is kept (the self-check's must be the small one, never a page); XFORM, when set, changes the colours a read of the small target gives (a host whose copy reads
-- colours otherwise than the page holds them, as a colour space may: the canary's make-time read then is not the painted colour)
local unreadable = false
local caps = {}             -- [frame] = { target names captured in it }
local XFORM = nil
render.CapturePixels = function()
    R.captured = R.cur
    local l = caps[M.frameNo]
    if not l then
        l = {}
        caps[M.frameNo] = l
    end
    l[#l + 1] = R.cur and R.cur.name or "?"
end
render.ReadPixel = function(x, y)
    local t = R.captured
    if unreadable or not t or x < 0 or y < 0 or x >= t.w or y >= t.h then return nil end
    local r, g, b, a = t:Get(x, y)
    if XFORM and string.find(t.name or "", "gsa1_textread_", 1, true) then r, g, b = XFORM(r), XFORM(g), XFORM(b) end
    return r, g, b, a
end
local fonts, cur = {}, nil
local MODEL = { ["Bauhaus Std Medium"] = { per = 0.5, cap = 0.5873, asc = 0.8103 }, ["Gill Sans"] = { per = 0.6, cap = 0.5702, asc = 0.7995 } }
local DEFAULT = { per = 0.55, cap = 0.6, asc = 0.8 }
surface.CreateFont = function(name, def) fonts[name] = def end
surface.SetFont = function(name) cur = name end
local function fm() local d = fonts[cur] return d and (MODEL[d.font] or DEFAULT) or DEFAULT, d and d.size or 32, d and d.font end
surface.GetTextSize = function(s)
    local m, size, fam = fm()
    if fam == "GSA1 no such font" then return 7 * #s, size end         -- (T.Probe's "no font": another width, so the families above count as taken)
    return m.per * size * #s, size
end
local TXT = { x = 0, y = 0, c = { 255, 255, 255, 255 } }
local mstack = {}
Matrix = function()
    local t = { tx = 0, ty = 0, sx = 1, sy = 1 }
    function t:Translate(v) self.tx, self.ty = self.tx + v.x * self.sx, self.ty + v.y * self.sy end
    function t:Scale(v) self.sx, self.sy = self.sx * v.x, self.sy * v.y end
    return t
end
local scales = {}
cam.PushModelMatrix = function(m) mstack[#mstack + 1] = m scales[#scales + 1] = { sx = m.sx, sy = m.sy } end
cam.PopModelMatrix = function() mstack[#mstack] = nil end
surface.SetTextPos = function(x, y) TXT.x, TXT.y = x, y end
surface.SetTextColor = function(r, g, b, a) TXT.c = { r, g, b, math.floor((a or 255) * R.mult) } end
surface.DrawText = function(s)
    local t = R.cur
    local m, size = fm()
    local per = m.per * size
    local mt = mstack[#mstack] or { tx = 0, ty = 0, sx = 1, sy = 1 }
    local aw = R.alphaWrite
    if TXT.noalpha then R.alphaWrite = false end      -- (a host whose text writes no alpha)
    if t and R.in2d then
        for i = 0, #s - 1 do
            if string.sub(s, i + 1, i + 1) ~= " " then
                local x0, x1 = mt.tx + mt.sx * (TXT.x + (i + 0.1) * per), mt.tx + mt.sx * (TXT.x + (i + 0.9) * per)
                local y0, y1 = mt.ty + mt.sy * (TXT.y + (m.asc - m.cap) * size), mt.ty + mt.sy * (TXT.y + m.asc * size)
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
-- a PNG of the owner's: one colour with alpha 128 everywhere, drawn by surface.DrawTexturedRect through the pixel model
local OWN = { 200, 10, 10, 128 }
local smat = nil
surface.SetMaterial = function(m) smat = m end
surface.DrawTexturedRect = function(x, y, w, h)
    local t = R.cur
    if not (t and R.in2d and smat and smat.png) then return end
    for py = math.max(0, y), math.min(t.h, y + h) - 1 do
        for px = math.max(0, x), math.min(t.w, x + w) - 1 do R.write(t, py * t.w + px + 1, OWN) end
    end
end
-- what the paint draws on the screen: every surface.DrawTexturedRectUV (the skins' pictures', the labels' call)
local drawn = {}
surface.DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1) drawn[#drawn + 1] = { x = x, y = y, w = w, h = h, uv = { u0, v0, u1, v1 }, mat = smat, c = { R.color[1], R.color[2], R.color[3], R.color[4] } } end
Material = function(path)
    return { path = path, png = true, IsError = function(self) return M.files[string.gsub(self.path, "^%.%./data/", "")] == nil end,
             GetColor = function() return { r = OWN[1], g = OWN[2], b = OWN[3], a = OWN[4] } end }
end
local times = {}
local write0 = file.Write
file.Write = function(p, s) times[p] = (times.now or 100) return write0(p, s) end
file.Time = function(p) return times[p] or 0 end
file.CreateDir = function() end
M.files["resource/fonts/BauhausStd-Bold.ttf"] = "not a font"
M.files["resource/fonts/Gill Sans Bold.otf"] = "not a font"
-- beta 1's made pictures of Metal Sonic, listed in generated.txt (the owner's PC: name.png, nameplate.png of 23:06:17)
M.files["gsa1/skins/sonic/metalsonic/hud/name.png"] = "\137PNG beta 1"
M.files["gsa1/skins/sonic/metalsonic/hud/nameplate.png"] = "\137PNG beta 1"
M.files["gsa1/skins/sonic/metalsonic/hud/generated.txt"] = "# made by G-SA1\nname.png\nnameplate.png\n"
times["gsa1/skins/sonic/metalsonic/hud/name.png"], times["gsa1/skins/sonic/metalsonic/hud/nameplate.png"], times["gsa1/skins/sonic/metalsonic/hud/generated.txt"] = 99, 99, 99
M.files["gsa1/skins/sonic/metalsonic/hud/other.txt"] = "someone's note"

GSA1 = nil
M.included = {}
do
    local ok, err = pcall(M.load, "autorun/gsa1_autorun.lua")
    local errs = GSA1 and GSA1.FeatureFileErrors or {}
    check(ok and #errs == 0, "the addon's client files load (%s)", tostring(err or errs[1] or "no error"))
end
local H, K, T, S = GSA1 and GSA1.SkinHud, GSA1 and GSA1.Skins, GSA1 and GSA1.Text, GSA1 and GSA1.CharSelect
check(H ~= nil and H.Picture ~= nil and H.SelfCheck ~= nil and K ~= nil and T ~= nil and T.Place ~= nil and S ~= nil and S.DrawFilter ~= nil, "feat/sh_skinhud.lua, cl_skinhud.lua, cl_text.lua's atlas pictures and the draw filter are there")
if not (H and K and T and S and H.Picture) then return done() end
local logs = {}
local log0 = GSA1.Log
function GSA1.Log(kind, fmt, ...)
    logs[#logs + 1] = { kind = kind, text = string.format(fmt, ...), frame = M.frameNo }
    if log0 then return log0(kind, fmt, ...) end
end
local function logged(pat)
    for _, l in ipairs(logs) do
        if string.find(l.text, pat, 1, true) then return l.text, l.frame end
    end
    return nil
end
local function count_logged(pat)
    local n = 0
    for _, l in ipairs(logs) do if string.find(l.text, pat, 1, true) then n = n + 1 end end
    return n
end
local metal, mecha = K.SKINS.metalsonic, K.SKINS.mechasonic
-- the paints and reads of each frame (T.Paint; T.ReadBack: a whole page, the make's; b1a2-fix2 T.ReadTexels: the small read, the self-check's and the make's reference)
local paints, reads, smalls = {}, {}, {}
local paint0, read0, small0 = T.Paint, T.ReadBack, T.ReadTexels
T.Paint = function(t, fn) paints[M.frameNo] = (paints[M.frameNo] or 0) + 1 return paint0(t, fn) end
T.ReadBack = function(t, fn) reads[M.frameNo] = (reads[M.frameNo] or 0) + 1 return read0(t, fn) end
T.ReadTexels = function(list) smalls[M.frameNo] = (smalls[M.frameNo] or 0) + 1 return small0(list) end
-- the frames a make step ran in (the self-check never reads in one)
local makes = {}
local step0 = H.Step
H.Step = function() makes[M.frameNo] = true return step0() end

-- CHARACTER SELECT'S PAINT, as far as the names go: the game's m_sonic and B_SONIC_e quads (MEASURED on the real screen: one quad of 6 vertices each, UVs 0..1, one colour) through S.DrawFilter
local st = { slot = 0, design = "R", skins = { [0] = 2 }, state = { phase = 0 }, scr = { v = {} }, F = { KIND = 32 }, m = S.Layout(3440, 1440, false, {}) }
local D = {}
local function gquad(d, x0, y0, x1, y1, archive)
    local V = st.scr.v
    local first = #V / 8
    for _, p in ipairs({ { x0, y0, 0, 0 }, { x1, y0, 1, 0 }, { x1, y1, 1, 1 }, { x0, y0, 0, 0 }, { x1, y1, 1, 1 }, { x0, y1, 0, 1 } }) do
        local o = #V
        V[o + 1], V[o + 2], V[o + 3], V[o + 4], V[o + 5], V[o + 6], V[o + 7], V[o + 8] = p[1], p[2], p[3], p[4], 255, 255, 255, 255
    end
    local k = d * 11
    D[k + 1], D[k + 2], D[k + 3], D[k + 4], D[k + 5], D[k + 6] = 0, first, 6, archive, 0, 0x11
    return k
end
local KN = gquad(0, 205.5, 314.4, 426.5, 369.6, 5)
local KP = gquad(1, 164, 390, 563.4, 439.9, 4)
local showing = true
local last = {}             -- this frame's: what the filter answered for the name and the plate, and what it drew
local first_name_frame = nil
local function paint()
    drawn = {}
    local rn = S.DrawFilter(st, "m_sonic", D, KN)
    local nd = #drawn
    local rp = S.DrawFilter(st, "B_SONIC_e", D, KP)
    last = { rn = rn, rp = rp, name = nd > 0 and drawn[1] or nil, plate = #drawn > nd and drawn[#drawn] or nil }
    if last.name and not first_name_frame then first_name_frame = M.frameNo end
    return last
end
-- what a drawn picture shows at its top left corner (a texel the name keeps clear): "black" = an opaque dark texel there (the owner's black square)
local function corner_of(d)
    if not d then return "game" end
    local rt = d.mat and M.rts[d.mat.params and d.mat.params["$basetexture"] or ""]
    if not rt then return "?" end
    local u = d.uv[1] + 0.004 * (d.uv[3] - d.uv[1])
    local v = d.uv[2] + 0.02 * (d.uv[4] - d.uv[2])
    local r, g, b, a = rt:Get(math.floor(u * rt.w), math.floor(v * rt.h))
    if a >= 128 and math.max(r, g, b) <= 12 then return "black" end
    return a <= 1 and "clear" or "other"
end
local function frame()
    M.T = M.T + 1 / 60
    M.frameNo = M.frameNo + 1
    M.run_hook("PostRender")
    if showing then return paint() end
    last = {}
    return last
end
local function frames(n, each)
    for _ = 1, n do
        local l = frame()
        if each then each(l) end
    end
end
local function made_all()
    for _ = 1, 30 do
        if not H.job and #H.queue == 0 then return true end
        frame()
    end
    return not H.job and #H.queue == 0
end

-- THE PURE PART: the places, the game's sizes, the atlas scale ---------------------------------------------------------------------------------------------------------------------------------------------------
do
    local P = H.Paths(metal)
    check(P.dir == "gsa1/skins/sonic/metalsonic/hud" and P.name == "gsa1/skins/sonic/metalsonic/hud/name.png" and P.plate == "gsa1/skins/sonic/metalsonic/hud/nameplate.png" and
        P.list == "gsa1/skins/sonic/metalsonic/hud/generated.txt", "T6 garrysmod/data/gsa1/skins/<base>/<id>/hud (lower case, as Garry's Mod wrote the owner's): name.png, nameplate.png, generated.txt")
    check(H.AtlasScale(3440, 1440, 2048, 1016) == 2 and H.AtlasScale(1920, 1080, 2048, 1016) == 1 and H.AtlasScale(2560, 1440, 2048, 1016) == 2 and H.AtlasScale(3840, 2160, 2048, 1016) == 3
        and H.AtlasScale(640, 480, 640, 472) == 1 and H.AtlasScale(nil, nil) == 3,
        "b1a2 the atlas scale: 2 on the owner's 3440 x 1440 (beta 1a's canvases: 4), 1 on 1920 x 1080, 3 on 3840 x 2160, 3 with no screen size yet (%d %d %d)", H.AtlasScale(3440, 1440, 2048, 1016), H.AtlasScale(1920, 1080, 2048, 1016),
        H.AtlasScale(3840, 2160, 2048, 1016))
    -- never drawn smaller than 0.77 of a texel a pixel: the pulse's smallest is 0.615 of the game's size (MEASURED, the trace lane: 157.4 of 256 game px), at the screen's own game-px scale
    local worst = math.huge
    for _, W in ipairs({ { 3440, 1440 }, { 1920, 1080 }, { 2560, 1440 }, { 3840, 2160 }, { 1280, 720 }, { 1600, 900 }, { 5120, 1440 } }) do
        local sc = math.min(W[1] / 640, W[2] / 480)
        local s = H.AtlasScale(W[1], W[2], math.min(2048, W[1]), T.MaxPicH(math.min(1024, W[2])))
        worst = math.min(worst, 0.615 * sc / s)
    end
    check(worst >= 0.769, "b1a2 on every screen the smallest pulse draws at least 0.77 of a texel a pixel (the atlas's own range; beta 1a's canvases went to 0.45): %.3f", worst)
    local L = H.Layout("name", 2)
    local Lp = H.Layout("plate", 2)
    check(L.w == 512 and L.h == 128 and L.cap == 74 and L.outline == 8 and L.rows[1] == 18 and L.rows[2] == 107 and Lp.w == 1024 and Lp.h == 128 and Lp.rows[1] == 18 and Lp.rows[2] == 59,
        "b1a2 at 2 x: the name 512 x 128 (capitals 74 px, outline 8, the game's rows 18..107), the plate 1024 x 128 (rows 18..59)")
    local cx, cy = H.ClearPoint(L)
    local px, py = H.ClearPoint(Lp)
    check(cx == 2 and cy == 1 and px == 782 and py == 126, "b1a2 the texels that must stay clear: the name's (2, 1), the plate's right of its frame (782, 126)")
    check(H.TextOf(metal, "name") == "METAL SONIC" and H.TextOf(mecha, "plate") == "MECHA SONIC", "T6 the texts in capitals, from char_name and char_nameplate")
    local set = H.ParseGenerated("# a comment\nname.png\n../../evil.png\nnameplate.png\nC:/x.png\n")
    check(set["name.png"] and set["nameplate.png"] and not set["../../evil.png"] and not set["C:/x.png"], "T6 generated.txt: plain .png names only")
    check(H.IsMade(set, "name.png", 99, 99) and not H.IsMade(set, "name.png", 200, 99) and not H.IsMade(set, "own.png", 1, 99), "T6 a listed file not newer than the list is G-SA1's; newer, or unlisted, is the owner's")
    -- the verdicts
    local made = { clear = { 0, 0, 0, 0 }, ink = { 57, 0, 181, 255 }, clear_alpha_only = true }
    check(H.CheckVerdict(made, { clear = { 0, 0, 0, 1 }, ink = { 60, 3, 178, 255 } }) == nil and H.CheckVerdict(made, { clear = { 0, 0, 0, 255 }, ink = { 57, 0, 181, 255 } }) ~= nil
        and H.CheckVerdict(made, { clear = { 0, 0, 0, 0 }, ink = { 0, 0, 0, 255 } }) ~= nil and H.CanaryVerdict({ 37, 201, 93, 0 }, T.CANARY_RGB) == nil and H.CanaryVerdict({ 0, 0, 0, 255 }, T.CANARY_RGB) ~= nil,
        "b1a2 the check's verdicts: within 8 of the make is right; a clear texel opaque, an ink texel changed, a canary changed are not")
    -- b1a2-fix2: the canary against what it read at the make, not the painted constant
    check(H.CanaryVerdict({ 28, 150, 70, 0 }, { 27, 150, 69, 0 }) == nil and H.CanaryVerdict({ 28, 150, 70, 0 }, T.CANARY_RGB) ~= nil and H.CanaryVerdict({ 27, 150, 69, 255 }, { 27, 150, 69, 0 }) ~= nil
        and H.CanaryVerdict({ 37, 201, 93, 1 }, { 37, 201, 93, 0 }) == nil,
        "b1a2-fix2 the canary's verdict: within 8 of its make's read on all four channels is right (a read of 28 150 70 0 is right against a make of 27 150 69 0, though not the painted 37 201 93); its alpha changed is not")
end

-- METAL SONIC SHOWN: made into the atlas, one paint and one read a frame ----------------------------------------------------------------------------------------------------------------------------------------
local rts0 = {}
for name in pairs(M.rts) do rts0[name] = true end
local f0 = M.frameNo
do
    check(H.Picture("metalsonic", "name") == nil, "T6 not made yet: nil (the game's own name stays, no blank frame)")
    check(#H.queue == 2, "T6 both pictures queued once (%d)", #H.queue)
    check(M.files["gsa1/skins/sonic/metalsonic/hud/name.png"] == nil and M.files["gsa1/skins/sonic/metalsonic/hud/nameplate.png"] == nil and M.files["gsa1/skins/sonic/metalsonic/hud/other.txt"] ~= nil
        and logged("beta 1's made name.png and nameplate.png deleted"), "T6 beta 1's made files (listed, not newer than the list) deleted once; other files stay")
    local game_frames, black = 0, 0
    for _ = 1, 8 do
        local l = frame()
        if not l.name then game_frames = game_frames + 1 end
        if corner_of(l.name) == "black" then black = black + 1 end
    end
    local worst_p, worst_r = 0, 0
    for f = f0 + 1, M.frameNo do
        worst_p, worst_r = math.max(worst_p, paints[f] or 0), math.max(worst_r, reads[f] or 0)
    end
    local worst_s, worst_c = 0, 0
    for f = f0 + 1, M.frameNo do
        worst_s = math.max(worst_s, smalls[f] or 0)
        local pagecaps = 0
        for _, n in ipairs(caps[f] or {}) do if string.find(n, "gsa1_textpage_", 1, true) then pagecaps = pagecaps + 1 end end
        worst_c = math.max(worst_c, pagecaps)
    end
    check(#H.queue == 0 and not H.job and worst_p == 1 and worst_r == 1 and worst_c == 1 and worst_s <= 2,
        "b1a2 the make spread: one paint and one capture of the page a frame at most (%d, %d, %d), beta 1a's three of each in one frame; b1a2-fix2: the check's texels read through the small target in the same frame (%d small reads at most: the page's canary after its first paint, the picture's reference)",
        worst_p, worst_r, worst_c, worst_s)
    local newcanvas = 0
    for name in pairs(M.rts) do if not rts0[name] and string.find(name, "gsa1_canvas_", 1, true) then newcanvas = newcanvas + 1 end end
    local pn, pp = H.mats.metalsonic and H.mats.metalsonic.name, H.mats.metalsonic and H.mats.metalsonic.plate
    check(newcanvas == 0 and pn and pp and pn.page and pn.page.rt.name == "gsa1_textpage_1_2048x1024_BGRA8888" and pn.mat == pn.page.mat and pp.page == pn.page and pn.w == 512 and pn.h == 128 and pp.w == 1024,
        "b1a2 no render target of their own (no gsa1_canvas_*): both are parts of text page 1, gsa1_textpage_1_2048x1024_BGRA8888, 512 x 128 and 1024 x 128 (%s)", pn and pn.page and pn.page.rt.name or "none")
    check(M.files["gsa1/skins/sonic/metalsonic/hud/name.png"] == nil, "T6 no PNG written")
    check(game_frames >= 1 and black == 0, "T6 until both read back right the game's own name is drawn (%d frames), never a black one", game_frames)
    if pn and pp then
        local rt = pn.page.rt
        local top, bot, fill, outl, fl, fr = nil, nil, 0, 0, nil, nil
        for y = pn.y, pn.y + pn.h - 1 do
            for x = pn.x, pn.x + pn.w - 1 do
                local r, g, b, a = rt:Get(x, y)
                if a >= 128 then
                    top = top or (y - pn.y)
                    bot = y - pn.y
                    if r == 0x39 and g == 0 and b == 0xB5 then
                        fill = fill + 1
                        fl = (not fl or x - pn.x < fl) and (x - pn.x) or fl
                        fr = (not fr or x - pn.x > fr) and (x - pn.x) or fr
                    elseif r == 0 and g == 0 and b == 0 then outl = outl + 1 end
                end
            end
        end
        local _, _, _, a0 = rt:Get(pn.x + 2, pn.y + 1)
        check(a0 == 0 and fill > 2000 and outl > 2000, "T6 the name: clear round it (%d), Metal's colour in the letters (%d texels), black round them (%d)", a0, fill, outl)
        check(top and math.abs(top - 18) <= 1 and math.abs(bot - 107) <= 1, "b1a2 the name's letters with their outline in rows %s..%s: the game's m_sonic 9..53 x 2 (18..107)", tostring(top), tostring(bot))
        check(fl and math.abs((fr - fl + 1) - 464) <= 2 and math.abs((fl + fr + 1) / 2 - 256) <= 1, "T6 the squeezed name fitted to the game's width: its fill in columns %s..%s (the room 464 px, centred on 256)", tostring(fl), tostring(fr))
        local line = logged("Metal Sonic's name in the text pictures' atlas")
        check(line and string.find(line, "\"METAL SONIC\" in Bauhaus Std Bold", 1, true) and string.find(line, "(the game's own: 18..107)", 1, true) and string.find(line, "a clear corner's alpha 0", 1, true)
            and string.find(line, "page 1, 512 x 128", 1, true) and string.find(line, "2 paints and reads in 2 frames", 1, true) and string.find(line, "fitted once to the game's width", 1, true),
            "b1a2 the log: the atlas page, the size, the face, the rows against the game's, the paints and their frames, the clear corner: %s", tostring(line))
        local sm = H.state.metalsonic.name.made
        check(line and string.find(line, "checked by its texels at 2,1 (0 0 0 0) and ", 1, true) and string.find(line, "read through the page's material as the page holds them", 1, true)
            and sm.clear[4] == 0 and sm.ink[1] == 0x39 and sm.ink[3] == 0xB5 and sm.ink[4] == 255 and sm.pink and sm.pink[1] == 0x39,
            "b1a2-fix2 the make's reference: the two texels the check reads again, read the way it reads them (through the page's material into the small target), as the page holds them here")
        check(pn.page.canary0 and pn.page.canary0[1] == 37 and pn.page.canary0[2] == 201 and pn.page.canary0[3] == 93 and pn.page.canary0[4] == 0,
            "b1a2-fix2 page 1's canary read at its make the same way: %s", tostring(pn.page.canary0 and T.RGBA(pn.page.canary0)))
        -- the plate: the game's frame, field and bar, black capitals in rows 18..59, clear beyond its frame; its margin round it clear (nothing painted on a neighbour)
        local p = pp.page.rt
        local function px(x, y) return { p:Get(pp.x + x, pp.y + y) } end
        local f, w, b, c = px(2, 2), px(10, 10), px(40, 88), px(900, 60)
        check(f[1] == 0 and f[4] == 255 and w[1] == 255 and w[4] == 255 and b[1] == 0 and b[4] == 255 and c[4] == 0, "T6 the plate: black frame, white field, black bar, clear beyond it")
        local ttop, tbot = nil, nil
        for y = 8, 66 do
            for x = 40, 740 do
                if p:Get(pp.x + x, pp.y + y) < 100 then
                    ttop = ttop or y
                    tbot = y
                end
            end
        end
        check(ttop and math.abs(ttop - 18) <= 1 and math.abs(tbot - 59) <= 1, "b1a2 the plate's capitals in rows %s..%s: the game's B_SONIC_e 9..29 x 2", tostring(ttop), tostring(tbot))
        local margin_ink = 0
        for _, q in ipairs({ pn, pp }) do
            for y = q.ay, q.ay + q.ah - 1 do
                for x = q.ax, q.ax + q.aw - 1 do
                    local inside = x >= q.x and x < q.x + q.w and y >= q.y and y < q.y + q.h
                    if not inside and select(4, rt:Get(x, y)) > 1 then margin_ink = margin_ink + 1 end
                end
            end
        end
        check(margin_ink == 0, "b1a2 the margin round each picture in its box is clear (%d texels not): no letter on a neighbour", margin_ink)
        check(logged("text pictures: alpha check on page 1") ~= nil, "b1a2 the atlas's own alpha check ran on the first picture (no text was made before it): %s", tostring(logged("text pictures: alpha check on page 1")))
        local q = pn.mat.params or {}
        check(pn.mat.shader == "UnlitGeneric" and q["$translucent"] == 1 and q["$vertexalpha"] == 1 and q["$vertexcolor"] == 1, "T6 the page's material is the atlas's own (cl_hud.lua's parameters)")
    end
end

-- DRAWN AS THE BAR'S LABELS ARE, AND CHECKED ONCE A SECOND -------------------------------------------------------------------------------------------------------------------------------------------------------------
local first_draw = nil
do
    first_draw = first_name_frame or M.frameNo
    local l = frame()
    local m = st.m
    local d = l.name
    local function at(dd, x0, y0, x1, y1)
        if not dd then return false end
        local ax, ay = math.floor(m.ox + x0 * m.sx + 0.5), math.floor(m.oy + y0 * m.sy + 0.5)
        return dd.x == ax and dd.y == ay and dd.w == math.floor(m.ox + x1 * m.sx + 0.5) - ax and dd.h == math.floor(m.oy + y1 * m.sy + 0.5) - ay
    end
    local pn = H.mats.metalsonic.name
    check(l.rn == false and l.rp == false and d and d.mat == pn.mat and d.uv[1] == pn.u0 and d.uv[4] == pn.v1 and at(d, 205.5, 314.4, 426.5, 369.6) and d.c[1] == 255 and d.c[4] == 255 and at(l.plate, 164, 390, 563.4, 439.9),
        "b1a2 the name and the plate drawn with surface.DrawTexturedRectUV at the game's quads, in its colour, from their part of the page; the game's draws skipped (false)")
    check(d and d.w / pn.w >= 0.77, "b1a2 at the pulse's widest here the name is drawn at %.2f of a texel a pixel (the owner's game: 0.92 .. 1.48)", d and d.w / pn.w or 0)
    check(logged("skin name drawn for Metal Sonic on Character Select (made, a picture of 512 x 128 on text page 1") and logged("skin plate drawn for Metal Sonic on Character Select"),
        "b1a2 the log says when each was first drawn: %s", tostring(logged("skin name drawn for Metal Sonic")))
    local r0 = {}
    for f = M.frameNo + 1, M.frameNo + 400 do r0[f] = true end
    local black = 0
    frames(400, function(ll) if corner_of(ll.name) == "black" then black = black + 1 end end)
    local list, pagecaps, smallcaps = {}, 0, 0
    for f = first_draw + 1, M.frameNo do
        if (smalls[f] or 0) > 0 and not makes[f] then list[#list + 1] = f end
        if not makes[f] then
            for _, n in ipairs(caps[f] or {}) do
                if string.find(n, "gsa1_textpage_", 1, true) then pagecaps = pagecaps + 1 elseif string.find(n, "gsa1_textread_", 1, true) then smallcaps = smallcaps + 1 end
            end
        end
    end
    local gaps_ok = #list >= 5
    for i = 2, #list do if list[i] - list[i - 1] < 59 then gaps_ok = false end end
    check(gaps_ok and (list[1] or 0) - first_draw >= 59 and (list[1] or 0) - first_draw <= 61, "b1a2 the self-check reads at most once a second while shown: %d reads in 400 frames, the first %d frames after the first draw",
        #list, (list[1] or 0) - first_draw)
    local rd = T.Reader()
    check(pagecaps == 0 and smallcaps == #list and rd and rd.rt.w == 16 and rd.rt.h == 4 and rd.rt.depth == MATERIAL_RT_DEPTH_NONE and bit.band(rd.rt.flags or 0, 0x301) == 0x301 and rd.rt.fmt == GSA1.Tex.format.fmt,
        "b1a2-fix2 the self-check never captures a page (%d captures of a page): each read is one capture of the 16 x 4 target %s (%d), made like cl_textures.lua's probes (no depth, no mips, point sampled, the probed format)",
        pagecaps, tostring(rd and rd.name), smallcaps)
    local first = logged("skin pictures check: the first read: 5 texels drawn through its material into the 16 x 4 target gsa1_textread_BGRA8888 and read there (256 bytes, where a capture of the whole page is 8 MiB), readable: the read took ")
    check(first ~= nil and count_logged("skin pictures check: the first read") == 1, "b1a2-fix2 the session's first read says what it read and what it cost, once: %s", tostring(first))
    local kept, kf = logged("skin pictures check: Metal Sonic's name read right 5.0 s after its first draw")
    check(kept ~= nil and kf and kf - first_draw >= 299 and kf - first_draw <= 301 and count_logged("skin pictures check: Metal Sonic's name read right") == 1
        and string.find(kept, "clear alpha 0; ink 57 0 181 255 as made; page 1's canary 37 201 93 0 as at the make, painted 37 201 93 0; its material on page 1's 2048 x 1024 target; 5 texels drawn through its material into the 16 x 4 target, the read took 0.0 ms", 1, true) ~= nil,
        "b1a2 the kept line, exactly once, 5 s after the first draw (frame +%s): %s", tostring(kf and kf - first_draw), tostring(kept))
    check(logged("skin pictures check: Metal Sonic's nameplate read right") ~= nil and count_logged("skin pictures check: Metal Sonic's nameplate read right") == 1 and black == 0 and H.stats.changed == 0,
        "b1a2 the plate's too, once; nothing changed, never black (%s)", tostring(logged("skin pictures check: Metal Sonic's nameplate read right")))
    -- away (Sonic shown) 2.5 s: no read; back: the first read a second later
    showing = false
    local rf = M.frameNo
    frames(150)
    local away = 0
    for f = rf + 1, M.frameNo do away = away + (reads[f] or 0) + (smalls[f] or 0) end
    showing = true
    local back = M.frameNo + 1
    frames(70)
    local firstback = nil
    for f = back, M.frameNo do if (smalls[f] or 0) > 0 then firstback = firstback or f end end
    check(away == 0 and firstback and firstback - back >= 59 and firstback - back <= 61, "b1a2 not shown: no read (%d); shown again: the first read a second later (frame +%s)", away, tostring(firstback and firstback - back))
end

-- THE FALLBACK -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- a frame-by-frame record: what the name's draw showed (the game's own, or the picture's corner)
local function watch(n, stop)
    local rec = {}
    for i = 1, n do
        local l = frame()
        rec[i] = { f = M.frameNo, drawn = l.name ~= nil, corner = corner_of(l.name), plate = l.plate ~= nil, pic = H.mats[st.skins[0] == 2 and "metalsonic" or "mechasonic"] }
        if stop and stop(rec[i]) then break end
    end
    return rec
end
local function fill_box(pic, r, g, b, a)
    local rt = pic.page.rt
    for y = pic.ay, pic.ay + pic.ah - 1 do
        for x = pic.ax, pic.ax + pic.aw - 1 do
            local i = y * rt.w + x + 1
            rt.r[i], rt.g[i], rt.b[i], rt.a[i] = r, g, b, a
        end
    end
end
-- 1. THE NEGATIVE CONTROL (the trace lane's run 3): the name's box filled with opaque black, Source's creation colour, as a lost target reads. Beta 1a drew a black box from then on, silently
do
    logs = {}
    local pn = H.mats.metalsonic.name
    fill_box(pn, 0, 0, 0, 255)
    local f_fill = M.frameNo
    local rec = watch(130)
    local black, changed_f, game_next, back = 0, nil, nil, nil
    local line, lf = logged("skin pictures check: Metal Sonic's name CHANGED")
    for _, r in ipairs(rec) do
        if r.corner == "black" then black = black + 1 end
        if lf and r.f == lf then game_next = not r.drawn end
        if lf and r.f > lf and r.drawn and not back then back = r end
    end
    check(line ~= nil and lf - f_fill <= 60 and black <= 60 and game_next == true, "b1a2 NEGATIVE CONTROL: black read within a second (frame +%s), the game's own name drawn from that frame (%s), black on screen %d frames at most (beta 1a: to the end)",
        tostring(lf and lf - f_fill), tostring(game_next), black)
    local slow = line and (string.find(line, "the last frame of 50 ms or more", 1, true) or string.find(line, "no frame of 50 ms or more before it", 1, true))
    check(line and string.find(line, "clear alpha 255, made 0; ink 0 0 0 255, made 57 0 181 255; page 1's canary 37 201 93 0 as at the make; binding ok;", 1, true) and string.find(line, "made again once. Please report this line", 1, true)
        and slow, "b1a2 the line says what was read against the make, the canary, the binding, the control, the slow frames: %s", tostring(line))
    check(line and string.find(line, "the game's own m_sonic texture", 1, true) ~= nil, "b1a2 the control (the game's own texture's texel) is in the line")
    local s = H.state.metalsonic.name
    check(back and back.corner == "clear" and s.remakes == 1 and H.mats.metalsonic.name and H.mats.metalsonic.name ~= pn, "b1a2 made again once (a new place on the page), checked, and drawn again: right, not black (%s)", tostring(back and back.corner))
end
-- 2. A SECOND CHANGE (a letter texel of the remade name): the game's own for the rest of the session, never made again
do
    logs = {}
    local pn = H.mats.metalsonic.name
    local s = H.state.metalsonic.name
    local rt = pn.page.rt
    local i = (pn.y + s.made.inkAt[2]) * rt.w + pn.x + s.made.inkAt[1] + 1
    rt.r[i], rt.g[i], rt.b[i] = 255, 255, 0
    local rec = watch(200)
    local line = logged("skin pictures check: Metal Sonic's name CHANGED")
    local drawn_after = 0
    local _, lf = logged("skin pictures check: Metal Sonic's name CHANGED")
    for _, r in ipairs(rec) do if lf and r.f >= lf and r.drawn then drawn_after = drawn_after + 1 end end
    check(line and string.find(line, "ink 255 255 0 255, made 57 0 181 255", 1, true) and string.find(line, "for the rest of this session", 1, true) and drawn_after == 0 and #H.queue == 0 and not H.job
        and H.Picture("metalsonic", "name") == nil, "b1a2 a changed letter texel, the second change: the game's own name for the rest of the session, not made again (%s)", tostring(line))
    check(rec[#rec].plate, "b1a2 the plate, unchanged, is still drawn")
end
-- 3. THE PAGE'S CANARY (its target lost): the plate's line, every text picture made again, the plate drawn again
do
    logs = {}
    local pp = H.mats.metalsonic.plate
    local rt = pp.page.rt
    local i = (pp.page.h - 1) * rt.w + 1 + 1
    rt.r[i], rt.g[i], rt.b[i], rt.a[i] = 0, 0, 0, 255
    local rec = watch(130)
    local line = logged("skin pictures check: Metal Sonic's nameplate CHANGED")
    local again = false
    for _, r in ipairs(rec) do if r.plate and r.pic and r.pic.plate and r.pic.plate ~= pp then again = true end end
    check(line and string.find(line, "page 1's canary 0 0 0 255 (at the make 37 201 93 0, painted 37 201 93 0)", 1, true) and logged("text pictures: the render targets were lost (device reset)") and again,
        "b1a2 the page's canary changed: the plate's line, every text picture made again (cl_text.lua's line), the plate made again and drawn (%s)", tostring(line))
end
-- 4. A BINDING POINTING ELSEWHERE (Mecha Sonic): what the page's material samples is no longer its target
do
    st.skins[0] = 3
    logs = {}
    watch(10)
    local pn = H.mats.mechasonic and H.mats.mechasonic.name
    local other = GetRenderTargetEx("gsa1_test_other", 64, 64, 1, MATERIAL_RT_DEPTH_NONE, 0, 0, 12)
    local was = pn and pn.mat.params["$basetexture"]
    if pn then pn.mat.params["$basetexture"] = other:GetName() end
    watch(70)
    if pn then pn.mat.params["$basetexture"] = was end
    local line = logged("skin pictures check: Mecha Sonic's name CHANGED")
    check(pn and line and string.find(line, "its material now samples \"gsa1_test_other 64 x 64\", at the make \"gsa1_textpage_1_2048x1024_bgra8888 2048 x 1024\"", 1, true) and H.state.mechasonic.name.remakes == 1,
        "b1a2 the page's material samples another texture: Mecha Sonic's name falls back, made again once (%s)", tostring(line))
    -- b1a2-fix2: the read goes through the material, so its texels show it too (the other target is Source's opaque black), and the remake made while it still samples elsewhere is not drawn
    check(line and string.find(line, "clear alpha 255, made 0", 1, true) and logged("Mecha Sonic's name picture could not be made (drawn through its page's material it reads 0 0 0 255 at its clear texel")
        and logged("its alpha not the painted 37 201 93 0: the material does not sample what was painted"),
        "b1a2-fix2 drawn through the material, the check reads what it samples: the texels changed too, the remake refused while it samples elsewhere, and the page's canary not taken as its make's (%s)",
        tostring(logged("could not be made")))
end
-- 5. AN UNREADABLE READ: the game's own; the remake cannot be read either, so the game's own for the rest of the session
do
    H.Remake()
    st.skins[0] = 2
    logs = {}
    watch(70)
    local ok_before = H.Picture("metalsonic", "name") ~= nil
    unreadable = true
    watch(70)
    local line = logged("skin pictures check: Metal Sonic's name NOT READABLE")
    watch(10)
    unreadable = false
    check(ok_before and line and string.find(line, "made again once", 1, true) and logged("Metal Sonic's name picture could not be made (not readable here") and logged("the game's own stays for the rest of this session")
        and H.Picture("metalsonic", "name") == nil, "b1a2 a read that gives nothing: the game's own; its remake not readable either: the game's own for the rest of the session (%s)", tostring(line))
end
-- 6. T.CheckLost READS EVERY PAGE (beta 1a: the first only): a second page lost is found, and the skins' pictures are made again (not taken for a change)
do
    T.LoseAll("the test's fresh pages")
    H.Remake()
    logs = {}
    watch(10)
    local c0 = H.stats.changed
    local filler = T.Place(2000, 900, 0)
    T.PaintPic(filler, function() end)
    local p2 = filler and filler.page
    check(p2 and p2 ~= H.mats.metalsonic.name.page, "b1a2 a second page holds a picture")
    if p2 then p2.rt:Fill(0, 0, 0, 255) end
    local n = T.CheckLost()
    watch(10)
    check(n == 2 and logged("text pictures: the render targets were lost (device reset)") ~= nil and H.stats.changed == c0,
        "b1a2 T.CheckLost read both pages' canaries (%d) and found the second lost; not taken for a change of the skin's pictures", n)
    check(H.Picture("metalsonic", "name") ~= nil and logged("Metal Sonic's name in the text pictures' atlas"), "b1a2 the skin's pictures made again with every picture, and drawn")
end

-- THE MAKE'S OWN CHECKS ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- the read-back corrects the face's proportions (a font whose capitals sit lower and taller than sh_skinhud.lua's table says, as Garry's Mod's own font cell may): corrected once, in a frame of its own
do
    MODEL["Bauhaus Std Medium"] = { per = 0.5, cap = 0.66, asc = 0.86 }
    logs = {}
    H.Remake()
    watch(12)
    local pn = H.mats.metalsonic.name
    local top, bot = nil, nil
    if pn then
        for y = pn.y, pn.y + pn.h - 1 do
            for x = pn.x, pn.x + pn.w - 1 do
                local _, _, _, a = pn.page.rt:Get(x, y)
                if a >= 128 then top = top or (y - pn.y) bot = y - pn.y end
            end
        end
    end
    local line = logged("Metal Sonic's name in the text pictures' atlas")
    check(line and string.find(line, "corrected once", 1, true) and string.find(line, "3 paints and reads in 3 frames", 1, true) and top and math.abs(top - 18) <= 1 and math.abs(bot - 107) <= 1,
        "T6 off by the font's own proportions: corrected once to rows %s..%s, one paint and read a frame (%s)", tostring(top), tostring(bot), tostring(line))
    MODEL["Bauhaus Std Medium"] = { per = 0.5, cap = 0.5873, asc = 0.8103 }
end
-- THE READ-BACK DECIDES (the verifier's MEDIUM): a made picture that reads wrong is never drawn; the game's own name and plate stay
do
    R.separate_alpha = false
    logs = {}
    H.Remake()
    watch(12)
    check(H.Picture("metalsonic", "name") == nil and H.Picture("metalsonic", "plate") == nil and #H.queue == 0, "T6 boxes read back: neither picture is drawn (the game's own stays)")
    check(logged("Metal Sonic's name picture could not be made (a texel that must be clear reads alpha 255, not 0: it would draw as a box): the game's own stays") ~= nil,
        "T6 the log says why: %s", tostring(logged("could not be made")))
    R.separate_alpha = true
    T.Clear()
    TXT.noalpha = true
    logs = {}
    H.Remake()
    watch(12)
    TXT.noalpha = nil
    check(H.Picture("metalsonic", "name") == nil and logged("Metal Sonic's name picture could not be made (no letter read back: they would not show)") ~= nil, "T6 letters without alpha: the name is not drawn (%s)", tostring(logged("could not be made")))
    T.Clear()
    H.Remake()
    watch(12)
    check(H.Picture("metalsonic", "name") ~= nil and H.Picture("metalsonic", "plate") ~= nil, "T6 the host right again: both made and drawn")
end
-- Mecha: the owner's own name.png (unlisted) is used as it is, copied into the atlas with its alpha, and checked against what it read at the make; only the plate is made
do
    M.files["gsa1/skins/sonic/mechasonic/hud/name.png"] = "the owner's own picture"
    times["gsa1/skins/sonic/mechasonic/hud/name.png"] = 500
    logs = {}
    H.mats.mechasonic, H.state.mechasonic = nil, nil
    st.skins[0] = 3
    H.Want(mecha)
    check(#H.queue == 2 and H.queue[1].how == "load" and H.queue[2].how == "make", "T6 Mecha: his own name.png is loaded, the plate made")
    watch(8)
    local pn = H.mats.mechasonic and H.mats.mechasonic.name
    local r, g, b, a = nil, nil, nil, nil
    if pn then r, g, b, a = pn.page.rt:Get(pn.x + 10, pn.y + 10) end
    check(pn and H.state.mechasonic.name.how == "load" and r == 200 and g == 10 and b == 10 and a == 128 and M.files["gsa1/skins/sonic/mechasonic/hud/name.png"] == "the owner's own picture",
        "T6 the owner's picture copied into its atlas box with its own alpha (%s %s %s %s), the file untouched", tostring(r), tostring(g), tostring(b), tostring(a))
    check(logged("your own name.png (a corner's alpha 128, 128 in the file)") and logged("skin name drawn for Mecha Sonic on Character Select (your own name.png"), "T6 the log says so, and draws it")
    watch(70)
    check(H.Picture("mechasonic", "name") ~= nil and not logged("Mecha Sonic's name CHANGED"), "b1a2 the owner's own picture (alpha 128 everywhere) reads as it was made: kept, not taken for a change")
    local list = H.ParseGenerated(M.files["gsa1/skins/sonic/mechasonic/hud/generated.txt"] or "")
    check(not list["name.png"], "T6 generated.txt never lists the owner's picture")
    st.skins[0] = 2
end
-- A SLOW READ: b1a2-fix2, the small read itself (not the page's capture any more) took 10 ms or more: read every 5 s from then on, said once. A small read under 10 ms keeps the checks once a second
do
    logs = {}
    watch(70)
    check(H.check.period == 1 and not logged("read every 5 s"), "b1a2-fix2 small reads under 10 ms: the checks stay once a second (%s s)", tostring(H.check.period))
    local rb = T.ReadTexels
    T.ReadTexels = function(list) M.T = M.T + 0.012 return rb(list) end
    watch(70)
    T.ReadTexels = rb
    local f1 = M.frameNo
    watch(400)
    local list = {}
    for f = f1 + 1, M.frameNo do if (smalls[f] or 0) > 0 and not makes[f] then list[#list + 1] = f end end
    local spaced = #list >= 1
    for i = 2, #list do if list[i] - list[i - 1] < 290 then spaced = false end end
    check(logged("(5 texels drawn through its material into the 16 x 4 target) took 12.0 ms: read every 5 s from now on") ~= nil and spaced and H.check.period == 5,
        "b1a2 a small read of 12 ms: every 5 s from then on (%d reads in 400 frames; %s)", #list, tostring(logged("read every 5 s")))
    H.check.period = H.CHECK_PERIOD
end
-- b1a2-fix2 THE CANARY READ OTHERWISE THAN PAINTED: a host whose copy gives the colours at 3/4 (the canary reads 27 150 69 0, not 37 201 93 0). Every picture made again: the page's canary is
-- said once, compared with what it read at its make from then on: no change, no device reset, no remake (the old rule, against the painted colour, made everything again every second here)
do
    XFORM = function(v) return math.floor(v * 0.75) end
    logs = {}
    T.LoseAll("the test's colour-changing copy")
    H.Remake()
    local lost0, changed0, remade0 = T.stats.lost, H.stats.changed, H.stats.remade
    local rec = watch(420)
    local drawn = 0
    for _, r in ipairs(rec) do if r.drawn then drawn = drawn + 1 end end
    local pn = H.mats.metalsonic and H.mats.metalsonic.name
    local c0 = pn and pn.page.canary0
    local said = logged("text pictures: page 1's canary reads 27 150 69 0 at its make through its material (painted 37 201 93 0): later reads of it are compared with what it read at the make")
    check(said and count_logged("canary reads") == 1 and c0 and c0[1] == 27 and c0[4] == 0 and H.CanaryVerdict(c0, T.CANARY_RGB) ~= nil,
        "b1a2-fix2 the page's canary read at its make otherwise than painted: said once (%s), kept as its reference", tostring(said))
    check(T.stats.lost == lost0 and H.stats.changed == changed0 and H.stats.remade == remade0 and not logged("CHANGED") and not logged("were lost (device reset)") and drawn >= 400
        and logged("skin pictures check: Metal Sonic's name read right 5.0 s after its first draw (clear alpha 0; ink 42 0 135 255 as made; page 1's canary 27 150 69 0 as at the make, painted 37 201 93 0"),
        "b1a2-fix2 and it still works: no change, no device reset, no remake in 7 s, the name drawn from its picture (%d of 420 frames), read right against its make's read (%s)", drawn, tostring(logged("read right")))
    local n = T.CheckLost()
    check(n >= 1 and T.stats.lost == lost0, "b1a2-fix2 T.CheckLost (the focus back) by the same rule: %d page(s) read, nothing lost", n)
    local line = logged("Metal Sonic's name in the text pictures' atlas")
    check(line and string.find(line, "checked by its texels at 2,1 (0 0 0 0) and ", 1, true) and string.find(line, "(42 0 135 255), read through the page's material (the page itself holds 0 0 0 0 and 57 0 181 255)", 1, true),
        "b1a2-fix2 the make's line says when the copy reads otherwise than the page holds: %s", tostring(line))
    XFORM = nil
    T.LoseAll("the test's copy as it was")
    H.Remake()
    watch(12)
end
-- NOTHING MADE A FRAME: the pictures' draw, their shows and the PostRender hook (its make and its check idle) make no Lua garbage while a skin's name and plate are shown. (The filter's
-- S.SlotNames, feat/sh_charselect.lua, pinned by T8, makes a small table a call, as in beta 1a: not this fix's, said as info)
do
    watch(70)
    local uv0, dc0 = surface.DrawTexturedRectUV, surface.SetDrawColor
    surface.DrawTexturedRectUV, surface.SetDrawColor = function() end, function() end     -- (the stand-ins' own records are tables)
    local post = M.hooks.PostRender and M.hooks.PostRender.gsa1_skinhud
    H.check.last = RealTime() + 1000          -- (no read due in these frames)
    local function one()
        M.frameNo = M.frameNo + 1
        local pn, pp = H.Picture("metalsonic", "name"), H.Picture("metalsonic", "plate")
        if pn and S.DrawSkinPicture(st, D, KN, pn) then H.Shown("metalsonic", "name", "m_sonic", 5, 0, 32) end
        if pp and S.DrawSkinPicture(st, D, KP, pp) then H.Shown("metalsonic", "plate", "B_SONIC_e", 4, 0, 32) end
        if post then post() end
    end
    local function per_frame(fn, n)
        for _ = 1, 300 do fn() end
        collectgarbage("collect")
        collectgarbage("stop")
        local k0 = collectgarbage("count")
        for _ = 1, n do fn() end
        local b = (collectgarbage("count") - k0) * 1024 / n
        collectgarbage("restart")
        return b
    end
    local per = per_frame(one, 2000)
    local names = per_frame(function() S.SlotNames(0) end, 2000)
    surface.DrawTexturedRectUV, surface.SetDrawColor = uv0, dc0
    H.check.last = nil
    check(post ~= nil and H.Picture("metalsonic", "name") ~= nil and per < 4, "b1a2 no garbage a frame while shown: the pictures' draw, their shows, the PostRender hook (%.1f bytes a frame)", per)
    info("the draw filter's S.SlotNames (feat/sh_charselect.lua, pinned) makes %.0f bytes a call, as in beta 1a: not this fix's", names)
end

-- make again: only the listed files go; the owner's stay
do
    M.files["gsa1/skins/sonic/metalsonic/hud/name.png"] = "\137PNG made"
    M.files["gsa1/skins/sonic/metalsonic/hud/generated.txt"] = "name.png\n"
    times["gsa1/skins/sonic/metalsonic/hud/name.png"], times["gsa1/skins/sonic/metalsonic/hud/generated.txt"] = 300, 300
    local n = H.Remake()
    check(n == 1 and M.files["gsa1/skins/sonic/metalsonic/hud/name.png"] == nil and M.files["gsa1/skins/sonic/mechasonic/hud/name.png"] == "the owner's own picture" and
        M.files["gsa1/skins/sonic/metalsonic/hud/other.txt"] ~= nil, "T6 \"Make again\" deletes the listed made file only (%d), the owner's and other files stay", n)
    watch(12)
    check(H.Picture("metalsonic", "name") ~= nil and H.Picture("metalsonic", "plate") ~= nil and #H.queue == 0, "T6 made again")
    check(M.cmds and M.cmds.gsa1_skins_hud_remake ~= nil, "T6 the command gsa1_skins_hud_remake (the Text page's button)")
end
-- a skin with auto_generate_name = false and no file: nothing is made
do
    local e = { id = "testskin", base = "sonic", char_name = "Test", auto_generate_name = false, auto_generate_nameplate = false,
                name_tex_location = "[skin folder]/HUD/name.png", nameplate_tex_location = "[skin folder]/HUD/nameplate.png" }
    check(H.Wants(e, "name", false) == "none" and H.Wants(e, "name", true) == "load" and H.Wants(metal, "name", false) == "make", "T6 auto_generate_* off and no file: none; a file: load")
end
-- nothing under the addon; no PNG written by the code; no canvas
do
    local src = host_read(root .. "/gsa1/feat/cl_skinhud.lua") .. host_read(root .. "/gsa1/feat/sh_skinhud.lua")
    local code = string.gsub(src, "%-%-[^\n]*", "")
    check(string.find(src, "addons/", 1, true) == nil and string.find(src, "materials/", 1, true) == nil and string.find(src, ".ttf", 1, true) == nil, "T6 the pictures stay in garrysmod/data; no font named")
    check(string.find(code, "render.Capture(", 1, true) == nil and string.find(code, "Canvas", 1, true) == nil and string.find(code, "GetRenderTargetEx", 1, true) == nil and string.find(code, "CreateMaterial", 1, true) == nil,
        "b1a2 no render.Capture, no canvas, no render target or material of its own: the atlas's pages only")
    local any = 0
    for name in pairs(M.rts) do if string.find(name, "gsa1_canvas_", 1, true) then any = any + 1 end end
    check(any == 0, "b1a2 no gsa1_canvas_* render target was ever made (%d)", any)
end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
info("the letters here are boxes; their real shapes, and what Garry's Mod's engine does to a page in the owner's session, only the game can show (the log's \"letters in rows\" and \"skin pictures check\" lines)")
return done()
