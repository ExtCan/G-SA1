-- feat_charselect_bar_test.lua - Character Select's bar and Choose Your Upgrade's band against the owner's mockups (1.0.0-beta1a, lane b1a-bar; notes sadc build/research/b1a/b1a-bar): feat/cl_charselect_bar.lua
-- and feat/cl_upgrades.lua through the addon's autorun, tests/lua_mock.lua, in Garry's Mod's own LuaJIT.
-- THE REAL SCREEN: tests/feat_charselect_bar_binding_test.cpp opens the game's Character Select from the disc through the module, runs it to idle and writes build/<target>/charselect_screen.lua (the draws,
-- the vertices and each draw's texture name as gsa1.FrontendScreen hands them to the addon: numbers and names only, made at test time, never kept). This test paints that screen through the addon's own
-- paint (S.PaintR: paint_2d, the draw filter, emit_draw, S.Overlay) and reads what reaches mesh.Position / mesh.Color and surface.*: beta 1's stand-in had one draw per sphere, the game has one draw of nine.
-- The numbers it compares with are the owner's mockups MEASURED (9.png, 10.png, 11.png, 13.png, 14.png at 1280 x 960: game px x 2); the mockups themselves are never read or kept here.
--   lua_host tests/feat_charselect_bar_test.lua <tests dir> <addon/lua dir> [charselect_screen.lua] [--record]
-- --record also prints every draw call ("REC ..." lines) at 1280 x 960 and 3440 x 1440 for the notes' pictures (sadc build/research/b1a/b1a-bar; notes only, never shipped).
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local screen_path, record = nil, false
for i = 3, #arg do
    if arg[i] == "--record" then record = true elseif arg[i] ~= "" then screen_path = arg[i] end
end
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_charselect_bar_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

local cookies = {}
cookie = { GetNumber = function(k, d) return tonumber(cookies[k]) or d end, Set = function(k, v) cookies[k] = v end, GetString = function(k, d) return cookies[k] or d end }
local G = M.module({ speed = 300, features = { super = 5, jukebox = 1, emote = 3, follower = 2, frontend = 1, charopt = 1 } })
G.CHAROPT = G.CHAROPT or {}
G.CHAROPT.UPGRADE_MODELS, G.CHAROPT.UPGRADE_MODELS_ON, G.CHAROPT.UPGRADE_MODELS_ALL = 5, 0x80000000, 0xF1FFF
function G.SetGameOption() return true end
function G.FrontendUpgradeModels() return true end
G.FRONTEND = { KIND = 32, PRI_3D = -20, LEFT = 1, RIGHT = 2, UP = 4, DOWN = 8, A = 16, B = 32, START = 64, SLOTS = 7 }
local PANEL = {}
PANEL.__index = PANEL
for _, k in ipairs({ "SetPos", "SetSize", "MakePopup", "SetKeyboardInputEnabled", "SetMouseInputEnabled", "SetConVar", "SetTall", "SetImage" }) do PANEL[k] = function() end end
function PANEL:GetWide() return 1920 end
function PANEL:GetTall() return 1440 end
function PANEL:CursorPos() return 0, 0 end
function PANEL:IsVisible() return not self.removed end
function PANEL:IsValid() return not self.removed end
function PANEL:Remove() self.removed = true end
vgui.Create = function(cls) return setmetatable({ cls = cls }, PANEL) end
gui.IsConsoleVisible = gui.IsConsoleVisible or function() return false end
input = input or {}
input.IsButtonDown = input.IsButtonDown or function() return false end
input.LookupBinding = input.LookupBinding or function() return nil end
input.LookupKeyBinding = input.LookupKeyBinding or function() return nil end

GSA1 = nil
M.included = {}
do
    local ok, err = pcall(M.load, "autorun/gsa1_autorun.lua")
    local errs = GSA1 and GSA1.FeatureFileErrors or {}
    check(ok and #errs == 0, "the addon's client files load (%s)", tostring(err or errs[1] or "no error"))
end
local S, U = GSA1 and GSA1.CharSelect, GSA1 and GSA1.UpgradeModels
check(S ~= nil and S.DrawFilter ~= nil and S.PaintR ~= nil and U ~= nil and U.PaintBand ~= nil, "feat/cl_charselect.lua, cl_charselect_bar.lua and cl_upgrades.lua are there")
if not (S and S.PaintR and U and U.PaintBand) then return done() end

-- the log's lines (the self-check lines the owner's next log shows)
local logs = {}
do
    local orig = GSA1.Log
    GSA1.Log = function(cat, fmt, ...)
        local ok, s = pcall(string.format, fmt, ...)
        logs[#logs + 1] = tostring(cat) .. " " .. (ok and s or tostring(fmt))
        if orig then return orig(cat, fmt, ...) end
    end
end
local function logged(pat)
    for _, l in ipairs(logs) do if string.find(l, pat) then return l end end
    return nil
end

-- THE RECORDER: what the addon's paint hands GMod (surface.*, draw.*, render.SetMaterial, mesh.*) -------------------------------------------------------------------------------------------------------------
local R = { list = {} }
local col, smat, rmat, vtx, cur = { 255, 255, 255, 255 }, nil, nil, nil, nil
local function rec(t) R.list[#R.list + 1] = t end
surface.SetDrawColor = function(r, g, b, a)
    if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
    col = { r, g, b, a or 255 }
end
surface.DrawRect = function(x, y, w, h) rec({ "R", x = x, y = y, w = w, h = h, c = col }) end
surface.DrawPoly = function(p)
    local q = {}
    for i, v in ipairs(p) do q[i] = { x = v.x, y = v.y } end
    rec({ "P", p = q, c = col })
end
surface.SetMaterial = function(m) smat = m end
surface.DrawTexturedRect = function(x, y, w, h) rec({ "T", x = x, y = y, w = w, h = h, mat = smat, c = col, whole = true }) end
surface.DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1) rec({ "T", x = x, y = y, w = w, h = h, mat = smat, c = col, uv = { u0, v0, u1, v1 } }) end
draw.NoTexture = function() smat = nil end
draw.SimpleText = function(text, font, x, y, c, ax, ay) rec({ "S", text = text, font = font, x = x, y = y, c = c, ax = ax, ay = ay, ow = 0 }) end
draw.SimpleTextOutlined = function(text, font, x, y, c, ax, ay, ow, oc) rec({ "S", text = text, font = font, x = x, y = y, c = c, ax = ax, ay = ay, ow = ow, oc = oc }) end
render.SetMaterial = function(m) rmat = m end
mesh.Begin = function() vtx = {} end
mesh.Position = function(v) cur = { x = v.x, y = v.y } end
mesh.TexCoord = function(_, u, v) cur.u, cur.v = u, v end
mesh.Color = function(r, g, b, a) cur.r, cur.g, cur.b, cur.a = r, g, b, a end
mesh.AdvanceVertex = function()
    vtx[#vtx + 1] = cur
    cur = {}
end
mesh.End = function() rec({ "M", mat = rmat, v = vtx }) end
-- the engine's own measure of a font's text (GMod has it always): a stand-in width of 0.62 x the font's size a letter, the size read from the stand-in font's name (font:<element>:<size>)
local cur_font = nil
surface.SetFont = function(f) cur_font = f end
surface.GetTextSize = function(t)
    local s = tonumber(string.match(tostring(cur_font), ":(%d+)$")) or 16
    return math.floor(s * 0.62 * #tostring(t) + 0.5), s
end

-- the text pictures: b1a-text's (feat/cl_text.lua T.Get); here a stand-in of a picture's box (the letters' colour kept), or none (the font's path)
local Tx = GSA1.Text
local real_get, real_font = Tx and Tx.Get, Tx and Tx.FontFor
local function pictures(on)
    if not Tx then return end
    Tx.FontFor = function(e, size) return "font:" .. tostring(e) .. ":" .. tostring(size) end
    if on then
        Tx.Get = function(text, element, size, c, outline)
            local ow = type(outline) == "table" and outline[1] or tonumber(outline) or 0
            return { mat = { text = text, element = element, size = size, c = { c.r, c.g, c.b }, ow = ow, oc = type(outline) == "table" and { outline[2], outline[3], outline[4] } or { 0, 0, 0 } },
                w = math.floor(size * 0.52 * #text + 2 * ow + 4), h = math.floor(size * 1.2 + 2 * ow + 4), u0 = 0.125, v0 = 0.25, u1 = 0.375, v1 = 0.5 }
        end
    else
        Tx.Get = function() return nil end
    end
end

-- THE SCREEN ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local dump_path = screen_path or (root .. "/../../build/x86_64-windows/charselect_screen.lua")
local src = host_read(dump_path)
local SCR = nil
if src then
    local f = host_load(src, "charselect_screen.lua")
    SCR = f and f() or nil
end
check(src == nil or (SCR and SCR.nd and SCR.v and SCR.d), "the real screen loads (%s)", dump_path)
if not SCR then
    info("no real screen at %s (tests/feat_charselect_bar_binding_test.cpp writes it with --gdi): the ball and the bar's ends are checked on the measured layout only", dump_path)
end

-- the module's side of the paint: gsa1.FrontendScreen fills st.scr from the dump once per generation (the module writes only when the generation changed), GSA1.Tex names the textures, GSA1.Hud a material
local names_at, mats = {}, {}
if SCR then
    for i = 0, SCR.nd - 1 do
        local k = i * 11
        local a, t = SCR.d[k + 4], SCR.d[k + 5]
        if a >= 0 and t >= 0 then names_at[a * 4096 + t] = SCR.names[i] end
    end
end
local gen_now = 1
local function fill(out)
    out.gen, out.nd, out.ns, out.nv, out.w, out.h = gen_now, SCR.nd, 0, SCR.nv, 640, 480
    out.d, out.v = {}, {}
    for i = 1, #SCR.d do out.d[i] = SCR.d[i] end
    for i = 1, #SCR.v do out.v[i] = SCR.v[i] end
end
function G.FrontendScreen(out, force)
    if not force and out.gen == gen_now then return gen_now, false end
    fill(out)
    return gen_now, true
end
function G.FrontendRender() return 0 end
GSA1.Tex.Info = function(kind, archive, tex) local n = names_at[archive * 4096 + tex] return n and { name = n } or nil end
GSA1.Tex.Archives = function() return { n = 9, [0] = { name = "AVA_BACK" } } end
GSA1.Hud.Material = function(kind, archive, tex)
    local key = archive * 4096 + tex
    mats[key] = mats[key] or { name = names_at[key] or ("tex " .. key) }
    return mats[key], 2
end
local faults = {}
local real_fault = S.FaultR
S.FaultR = function(st, why) faults[#faults + 1] = tostring(why) end

local function new_st(skin)
    return { design = "R", F = G.FRONTEND, scr = {}, batches = {}, events = {}, state = { phase = 0, slot = 0, slots = 7, ring = 0 }, m = {}, slot = 0, slots = 7, names = {},
        skins = { [0] = skin or 1 }, frame = 200, keys = {}, pulse = 0, mask = 0, padWas = 0 }
end
local function paint(st, W, H)
    R.list = {}
    S.PaintR(st, W, H)
    return R.list
end

-- the vertices of the mesh draws of a texture, in screen px
local function verts_of(list, name)
    local out = {}
    for _, r in ipairs(list) do
        if r[1] == "M" and r.mat and r.mat.name == name then
            for _, v in ipairs(r.v) do out[#out + 1] = v end
        end
    end
    return out
end
local function in_box(v, x0, y0, x1, y1) return v.x >= x0 - 1 and v.x <= x1 + 1 and v.y >= y0 - 1 and v.y <= y1 + 1 end
local function layout(W, H) return S.Layout(W, H, false, {}) end
local function sx(m, x) return m.ox + x * m.sx end
local function sy(m, y) return m.oy + y * m.sy end
local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 1e-6) end

S.barcv.bar:SetString("1")
S.barcv.upgrades:SetString("1")
S.cv.skins:SetString("1")
pictures(false)

-- ---- B1: THE SUPPORT BALL on the real screen ---------------------------------------------------------------------------------------------------------------------------------------------------------------
if SCR then
    -- the real screen's facts this test builds on (MEASURED through the module; the binding test prints them too)
    local sphe, n_bases = nil, 0
    for i = 0, SCR.nd - 1 do
        if SCR.names[i] == "sphe_7" then sphe = i end
    end
    check(sphe ~= nil and SCR.d[sphe * 11 + 3] == 54, "B1 the real screen: the spheres' tinted bases are ONE draw of 54 vertices, nine quads (draw %s) - beta 1's stand-in had a draw per sphere", tostring(sphe))
    for _, W in ipairs({ { 1280, 960 }, { 3440, 1440 } }) do
        local m = layout(W[1], W[2])
        local lx0, ly0, lx1, ly1 = sx(m, 103), sy(m, 393), sx(m, 153), sy(m, 443)
        local rx0, ry0, rx1, ry1 = sx(m, 479), sy(m, 393), sx(m, 529), sy(m, 443)
        local function ball(list)
            local l, r, ring = {}, {}, {}
            for _, v in ipairs(verts_of(list, "sphe_7")) do
                if in_box(v, lx0, ly0, lx1, ly1) then l[#l + 1] = v elseif in_box(v, rx0, ry0, rx1, ry1) then r[#r + 1] = v else ring[#ring + 1] = v end
            end
            return l, r, ring
        end
        local function all(vs, c)
            if #vs == 0 then return false end
            for _, v in ipairs(vs) do
                if not (v.r == c[1] and v.g == c[2] and v.b == c[3] and v.a == 255) then return false end
            end
            return true
        end
        local st = new_st(1)
        local list = paint(st, W[1], W[2])
        local l, r, ring = ball(list)
        local blue, red = 0, 0
        for _, v in ipairs(ring) do
            if v.r == 0 and v.g == 0 and v.b == 255 then blue = blue + 1 elseif v.r == 255 and v.g == 0 and v.b == 0 then red = red + 1 end
        end
        check(#faults == 0 and #l == 6 and all(l, { 77, 255, 0 }), "B1 %dx%d Sonic: the left ball's six vertices reach mesh.Color green 77 255 0 255 (the owner's 11.png, full; beta 1: the game's red) (%d vertices; %s)",
            W[1], W[2], #l, faults[1] or "no fault")
        check(#r == 6 and all(r, { 255, 0, 0 }) and blue == 36 and red == 6, "B1 %dx%d the right ball keeps the game's red, the ring's six blue and the selected red (%d, %d blue, %d red)", W[1], W[2], #r, blue, red)
        local shine = verts_of(list, "sphe_6")
        local white = 0
        for _, v in ipairs(shine) do if v.r == 255 and v.g == 255 and v.b == 255 then white = white + 1 end end
        check(#shine == 54 and white == 54, "B1 %dx%d the shines stay white (%d of %d)", W[1], W[2], white, #shine)
        -- the same generation, painted again: the same colours (the filter changes the screen's own vertices; a second paint must not drift)
        list = paint(st, W[1], W[2])
        l = ball(list)
        check(all(l, { 77, 255, 0 }), "B1 %dx%d painted again in the same generation: still green", W[1], W[2])
        -- Metal Sonic and Mecha Sonic: none (red); a partial skin: yellow; the bar off: the game's red at once, in the same generation
        st.skins[0] = 2
        l = ball(paint(st, W[1], W[2]))
        check(all(l, { 255, 0, 0 }), "B1 %dx%d Metal Sonic (upgrade_model_compatibility none): red", W[1], W[2])
        st.skins[0] = 3
        l = ball(paint(st, W[1], W[2]))
        check(all(l, { 255, 0, 0 }), "B1 %dx%d Mecha Sonic: red", W[1], W[2])
        local K = GSA1.Skins
        local metal = K and K.SKINS and K.SKINS.metalsonic
        if metal then
            local was = metal.upgrade_model_compatibility
            metal.upgrade_model_compatibility = "partial"
            st.skins[0] = 2
            l = ball(paint(st, W[1], W[2]))
            check(all(l, { 255, 204, 0 }), "B1 %dx%d a skin with partial support: yellow 255 204 0 (11.png)", W[1], W[2])
            metal.upgrade_model_compatibility = was
        end
        st.skins[0] = 1
        l = ball(paint(st, W[1], W[2]))
        S.barcv.bar:SetString("0")
        local l2 = ball(paint(st, W[1], W[2]))
        S.barcv.bar:SetString("1")
        check(all(l, { 77, 255, 0 }) and all(l2, { 255, 0, 0 }), "B1 %dx%d gsa1_charselect_bar 0: the game's own red back in the same generation", W[1], W[2])
        -- a new generation from the module (red again in its vertices): green again
        gen_now = gen_now + 1
        l = ball(paint(st, W[1], W[2]))
        check(all(l, { 77, 255, 0 }), "B1 %dx%d a new generation of the module's screen: green again", W[1], W[2])
        -- a character without upgrades: the game's red (S.UpgradeList empty)
        local real_list = S.UpgradeList
        S.UpgradeList = function() return {} end
        l = ball(paint(st, W[1], W[2]))
        S.UpgradeList = real_list
        check(all(l, { 255, 0, 0 }), "B1 %dx%d a character without upgrades: the game's red", W[1], W[2])
    end
    local line = logged("^charselect bar: the support ball is quad 9 of 9 of the game's draw")
    check(line ~= nil and string.find(line, "77 255 0 for sonic (full)", 1, true) ~= nil, "B1 the self-check line for the owner's log: %s", tostring(line))
    -- (fix-bar) a step to another skin in the same open is said too, once for each skin shown
    local metal_line = logged("^charselect bar: the support ball is .*255 0 0 for metalsonic %(none%)")
    local mecha_line = logged("^charselect bar: the support ball is .*255 0 0 for mechasonic %(none%)")
    local n_sonic = 0
    for _, l in ipairs(logs) do if string.find(l, "77 255 0 for sonic (full)", 1, true) and string.find(l, "^charselect bar: the support ball") then n_sonic = n_sonic + 1 end end
    check(metal_line ~= nil and mecha_line ~= nil and n_sonic == 2, "B1 a step to Metal Sonic and to Mecha Sonic in the same open reaches the log too, and Sonic's line is said once an open (two opens, four paints of Sonic each: %s | %s | %d)",
        tostring(metal_line), tostring(mecha_line), n_sonic)

    -- ---- B2: THE BAR'S ENDS: inside the game's picture, where the Dreamcast and the owner's mockup 9 have them ---------------------------------------------------------------------------------------------
    for _, W in ipairs({ { 1280, 960 }, { 3440, 1440 } }) do
        local m = layout(W[1], W[2])
        gen_now = gen_now + 1
        local list = paint(new_st(1), W[1], W[2])
        local v = verts_of(list, "cs_ce_bd_2")
        local minx, maxx = math.huge, -math.huge
        for _, p in ipairs(v) do
            if p.x < minx then minx = p.x end
            if p.x > maxx then maxx = p.x end
        end
        check(#v == 12 and near(minx, sx(m, 0.001), 0.01) and near(maxx, sx(m, 639.999), 0.01), "B2 %dx%d the bar's end quads stop at the picture's edges, x %.1f .. %.1f px (beta 1: 0 .. %d, into the side bars)",
            W[1], W[2], minx, maxx, W[1])
        -- where the bar's picture starts and ends now: its texture's u 0.375 (MEASURED through the module, gsa1.FrontendTexturePixel: cs_ce_bd_2's columns 0 .. 95 of 256 are clear), interpolated along the
        -- emitted quads
        local function x_at_u(lo_side, u)
            local a, b
            for _, p in ipairs(v) do
                if near(p.y, sy(m, 386), 0.01) then
                    if lo_side and p.x < sx(m, 200) then if near(p.x, minx, 0.01) then a = p else b = p end end
                    if not lo_side and p.x > sx(m, 440) then if near(p.x, maxx, 0.01) then a = p else b = p end end
                end
            end
            if not (a and b) then return nil end
            return a.x + (b.x - a.x) * (u - a.u) / (b.u - a.u), a.u
        end
        local xl, ul = x_at_u(true, 0.375)
        local xr, ur = x_at_u(false, 0.375)
        local gl, gr = xl and (xl - m.ox) / m.sx, xr and (xr - m.ox) / m.sx
        -- beta 1's: S.PlaceX sent x -68 to the screen's edge 0 and x 700 to its width, so the same u landed here (in game px)
        local b1l = (0.375 * (m.ox + 188 * m.sx) - m.ox) / m.sx
        local b1r = ((m.ox + 444 * m.sx) + (1 - 0.375) * (W[1] - (m.ox + 444 * m.sx)) - m.ox) / m.sx
        check(near(ul, 68.001 / 256, 1e-6) and near(ur, 1 - 195.999 / 256, 1e-6), "B2 %dx%d the cut vertices carry the texture's u of the picture's edge (%.6f, %.6f: 68.001 of 256 and 1 - 195.999 of 256)", W[1], W[2], ul or -1, ur or -1)
        check(gl and gr and near(gl, 28, 0.01) and near(gr, 604, 0.01), "B2 %dx%d the bar's picture ends at game x %.2f and %.2f (u 0.375: -68 + 96 and 700 - 96): the owner's mockup 9, MEASURED 28 and 604.5 (beta 1: %.0f and %.0f)",
            W[1], W[2], gl or -1, gr or -1, b1l, b1r)
    end
    local line2 = logged("^charselect bar: the bar's ends kept to the game's picture")
    check(line2 ~= nil and string.find(line2, "6 vertices of cs_ce_bd_2 (they reached x -68 and 700)", 1, true) ~= nil, "B2 the self-check line names each draw cut and how far it reached: %s", tostring(line2))
end

-- ---- B2b: a quad wholly outside 0 .. 640 in the bar's band is left alone (fix-bar: the cut divided by zero there and wrote NaN); a quad reaching out on one side is cut on that side only -----------
do
    local V = {}
    local function quad(base, x0, x1, y0, y1)
        local pts = { { x0, y0, 0, 0 }, { x0, y1, 0, 1 }, { x1, y0, 1, 0 }, { x0, y1, 0, 1 }, { x1, y1, 1, 1 }, { x1, y0, 1, 0 } }
        for i, p in ipairs(pts) do
            local o = (base + i - 1) * 8
            V[o + 1], V[o + 2], V[o + 3], V[o + 4], V[o + 5], V[o + 6], V[o + 7], V[o + 8] = p[1], p[2], p[3], p[4], 0, 46 + 157 * p[4], 255, 255
        end
    end
    quad(0, -100, -20, 400, 440)        -- wholly left of the picture
    quad(6, 650, 720, 400, 440)         -- wholly right of it
    quad(12, 164, 676, 390, 454)        -- the Japanese nameplate b_sonic's shape: out on the right only
    local before = {}
    for i = 1, 96 do before[i] = V[i] end
    local st = { scr = { gen = 1, v = V } }
    local moved, lo, hi = S.KeepEnds(st, { 0, 0, 18 }, 0)
    local finite, same = true, true
    for i = 1, 18 * 8 do
        local x = V[i]
        if x ~= x or x == math.huge or x == -math.huge then finite = false end
    end
    for i = 1, 96 do if V[i] ~= before[i] then same = false end end
    local right_x, right_u = {}, {}
    for v = 12, 17 do
        local o = v * 8
        if V[o + 3] > 0.5 then right_x[#right_x + 1], right_u[#right_u + 1] = V[o + 1], V[o + 3] end
    end
    check(finite and same and moved == 3 and lo == nil and hi == 676 and #right_x == 3 and near(right_x[1], 639.999, 1e-9) and near(right_u[1], 475.999 / 512, 1e-6),
        "B2b quads wholly outside 0 .. 640 untouched, no NaN or infinity (%s, %s); a quad out on the right only: its 3 right vertices cut at 639.999 with u %.6f (%d moved, reached %s .. %s)",
        tostring(finite), tostring(same), right_u[1] or -1, moved, tostring(lo), tostring(hi))
end

-- ---- B3: THE PINK TABS (13.png / 14.png and their places in 9.png) -------------------------------------------------------------------------------------------------------------------------------------------
local function area2(p)
    local a = 0
    for i = 1, #p do
        local q, r = p[i], p[i % #p + 1]
        a = a + q.x * r.y - r.x * q.y
    end
    return a
end
local function convex(p)
    local sgn = 0
    for i = 1, #p do
        local a, b, c = p[i], p[i % #p + 1], p[(i + 1) % #p + 1]
        local z = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
        if math.abs(z) > 1e-6 then
            local s = z > 0 and 1 or -1
            if sgn == 0 then sgn = s elseif s ~= sgn then return false end
        end
    end
    return true
end
local function bbox(p)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, v in ipairs(p) do
        x0, y0, x1, y1 = math.min(x0, v.x), math.min(y0, v.y), math.max(x1, v.x), math.max(y1, v.y)
    end
    return x0, y0, x1, y1
end
-- the left / right edge of a convex polygon at height y
local function span(p, y)
    local lo, hi = math.huge, -math.huge
    for i = 1, #p do
        local a, b = p[i], p[i % #p + 1]
        if (a.y - y) * (b.y - y) <= 0 and a.y ~= b.y then
            local x = a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
            lo, hi = math.min(lo, x), math.max(hi, x)
        end
    end
    return lo, hi
end
do
    gen_now = gen_now + 1
    local st = new_st(1)
    if not SCR then
        st.scr = { gen = 1, nd = 0, nv = 0, d = {}, v = {} }
        G.FrontendScreen = function(out) return 1, false end
    end
    local list = paint(st, 1280, 960)
    local pinks = {}
    for _, r in ipairs(R.list) do
        if r[1] == "P" and r.c[1] == 255 and r.c[2] == 12 and r.c[3] == 255 and r.c[4] == 255 then pinks[#pinks + 1] = r.p end
    end
    check(#pinks == 2, "B3 two pink tab shapes (surface.DrawPoly, %d)", #pinks)
    local yt, dt = pinks[1], pinks[2]
    if yt and dt then
        local x0, y0, x1, y1 = bbox(yt)
        local a0, b0, a1, b1 = bbox(dt)
        -- the mockup's pink (13.png's body included) MEASURED at 1280 x 960: Y tab x 72 .. 196, y 785 .. 837; D tab x 1032 .. 1185, y 722 .. 779
        check(near(x0, 72, 1.5) and near(y0, 785, 1.5) and near(x1, 197, 1.5) and near(y1, 838, 1.5), "B3 1280x960 the Y tab's box %.0f,%.0f .. %.0f,%.0f px (the mockup 72,785 .. 197,838)", x0, y0, x1, y1)
        check(near(a0, 1032, 1.5) and near(b0, 722, 1.5) and near(a1, 1186, 1.5) and near(b1, 780, 1.5), "B3 1280x960 the D-pad tab's box %.0f,%.0f .. %.0f,%.0f px (the mockup 1032,722 .. 1186,780)", a0, b0, a1, b1)
        check(area2(yt) > 0 and area2(dt) > 0 and convex(yt) and convex(dt), "B3 both are convex and clockwise on screen, as surface.DrawPoly draws (the emote wheel's own rule, sh_wheel.lua W.PolyArea2)")
        -- the big curve: the mockup's pink rows (MEASURED, 1280 x 960): Y tab's left edge at y 789: 126, 797: 104, 805: 91, 813: 76, 821: 72; D tab's right edge at y 724: 1152, 730: 1164, 738: 1175,
        -- 746: 1181, 756: 1185 (the small corners: within 6 px of the box)
        local bad = {}
        for _, row in ipairs({ { 789, 126 }, { 797, 104 }, { 805, 91 }, { 813, 76 }, { 821, 72 } }) do
            local lo = span(yt, row[1])
            if math.abs(lo - row[2]) > 6 then bad[#bad + 1] = string.format("Y %d: %.0f (%d)", row[1], lo, row[2]) end
        end
        for _, row in ipairs({ { 724, 1152 }, { 730, 1164 }, { 738, 1175 }, { 746, 1181 }, { 756, 1185 } }) do
            local _, hi = span(dt, row[1])
            if math.abs(hi - row[2]) > 6 then bad[#bad + 1] = string.format("D %d: %.0f (%d)", row[1], hi, row[2]) end
        end
        local _, yr = span(yt, y0 + 2)
        local dl = span(dt, b0 + 2)
        check(#bad == 0 and yr > x1 - 4 and dl < a0 + 4, "B3 the big curve on the Y tab's top left and the D-pad tab's top right follow the mockup's rows within 6 px; the other top corners small (%s)", table.concat(bad, "; "))
    end
    -- the gloss: white along the top of each tab; the rim below and right; nothing black anywhere in the bar
    local gloss, rim, black = 0, 0, 0
    for _, r in ipairs(R.list) do
        if r[1] == "P" and r.c[1] == 255 and r.c[2] == 255 and r.c[3] == 255 and r.c[4] >= 150 then gloss = gloss + 1 end
        if r[1] == "P" and r.c[1] == 61 and r.c[2] == 0 and r.c[3] == 56 then rim = rim + 1 end
        -- (paint_r clears the whole screen black first: not a box of the bar)
        if (r[1] == "P" or r[1] == "R") and r.c[1] == 0 and r.c[2] == 0 and r.c[3] == 0 and r.c[4] > 0 and not (r[1] == "R" and r.x == 0 and r.y == 0 and r.w == 1280) then black = black + 1 end
    end
    check(gloss >= 6 and rim == 2 and black == 0, "B3 a white gloss line along each top (%d bright pieces), the dark rim (%d), no black box drawn (%d)", gloss, rim, black)
    -- the letters, font path (a picture not ready yet) and picture path, at both sizes: white on the tabs, the mockup's pale blue on the bar, centred where the mockup has them
    local want = {
        { "Y Button", 69.5, 408, { 255, 255, 255 } }, { "D-Pad Up/Down", 557, 377, { 255, 255, 255 } },
        { "Upgrades", 66, 430, { 196, 222, 255 } }, { "Skins", 565.5, 402.5, { 196, 222, 255 } }, { "1/3", 504.5, 415, { 255, 255, 255 } },
    }
    for _, mode in ipairs({ false, true }) do
        pictures(mode)
        for _, W in ipairs({ { 1280, 960 }, { 3440, 1440 } }) do
            local m = layout(W[1], W[2])
            paint(st, W[1], W[2])
            local bad = {}
            for _, w in ipairs(want) do
                local found
                for _, r in ipairs(R.list) do
                    if mode and r[1] == "T" and r.mat and r.mat.text == w[1] then
                        -- (b1a-text's atlas: the picture's own part of the page, by its UVs; a plain DrawTexturedRect would draw the whole page)
                        local uv = r.uv or {}
                        found = { x = r.x + r.w / 2, y = r.y + r.h / 2, x0 = r.x, x1 = r.x + r.w, c = r.mat.c, ok = not r.whole and uv[1] == 0.125 and uv[2] == 0.25 and uv[3] == 0.375 and uv[4] == 0.5 and r.c[4] == 255 }
                    elseif not mode and r[1] == "S" and r.text == w[1] then
                        found = { x = r.x, y = r.y, c = { r.c.r, r.c.g, r.c.b }, ok = r.ax == 1 and r.ay == 1 }
                    end
                end
                -- (a picture wider than the room is drawn smaller: the tab texts stay on their tabs, the Y tab's text right of its big curve: game x 36 + 0.4 * 30 on)
                local room = ({ ["Y Button"] = { 44, 98.5 }, ["D-Pad Up/Down"] = { 516, 593 } })[w[1]]
                if found and mode and room and not (found.x0 >= sx(m, room[1]) - 1 and found.x1 <= sx(m, room[2]) + 1) then found.ok = false end
                if not found then
                    bad[#bad + 1] = w[1] .. " not drawn"
                elseif not (near(found.x, sx(m, w[2]), 1) and near(found.y, sy(m, w[3]), 1) and found.c[1] == w[4][1] and found.c[2] == w[4][2] and found.c[3] == w[4][3]) or found.ok == false then
                    bad[#bad + 1] = string.format("%s at %.0f,%.0f in %d %d %d", w[1], found.x, found.y, found.c[1], found.c[2], found.c[3])
                end
            end
            check(#bad == 0, "B3 %dx%d %s: Y Button and D-Pad Up/Down white on the tabs, Upgrades and Skins in the mockup's 196 222 255, the counter white, each centred where 9.png has it, a picture by its own UVs of the atlas page (%s)", W[1], W[2],
                mode and "pictures" or "fonts", table.concat(bad, "; "))
        end
    end
    pictures(false)
    -- (fix-bar) the font path (until the text pictures pass their read-back) keeps each text to its width as the picture path does: measured with surface.GetTextSize (here the stand-in above), a smaller
    -- size of the same font when it would be wider
    local B = S.BAR
    local specs = { ["Y Button"] = B.text_y, ["D-Pad Up/Down"] = B.text_d, ["Upgrades"] = B.lbl_up, ["Skins"] = B.lbl_skins, ["1/3"] = B.counter }
    for _, W in ipairs({ { 1280, 960 }, { 3440, 1440 } }) do
        local m = layout(W[1], W[2])
        paint(st, W[1], W[2])
        local bad, dpad = {}, nil
        for _, r in ipairs(R.list) do
            local spec = r[1] == "S" and specs[r.text]
            if spec then
                local size = tonumber(string.match(tostring(r.font), ":(%d+)$")) or 0
                local w = math.floor(size * 0.62 * #r.text + 0.5) + 2 * (r.ow or 0)
                local asked = math.max(8, math.floor(spec[3] * m.sy + 0.5))
                if w > spec[4] * m.sy + 0.5 or size > asked or size < 8 then bad[#bad + 1] = string.format("%s %d px in size %d (asked %d, at most %.0f px)", r.text, w, size, asked, spec[4] * m.sy) end
                if r.text == "D-Pad Up/Down" then dpad = { size, asked, w } end
            end
        end
        check(#bad == 0 and dpad and dpad[1] < dpad[2], "B3 %dx%d fonts: every bar text within its width; D-Pad Up/Down (%s px wide in the size asked) drawn in size %s of %s, %s px (%s)", W[1], W[2],
            dpad and tostring(math.floor(dpad[2] * 0.62 * 13 + 0.5)) or "?", dpad and tostring(dpad[1]) or "?", dpad and tostring(dpad[2]) or "?", dpad and tostring(dpad[3]) or "?", table.concat(bad, "; "))
    end
    local line = logged("^charselect bar: drawn at ")
    check(line ~= nil and string.find(line, "2 tab shapes", 1, true) ~= nil, "B3 the self-check line: %s", tostring(line))
end

-- ---- B4: THE BAND of Choose Your Upgrade (10.png / 12.png) ---------------------------------------------------------------------------------------------------------------------------------------------------
do
    -- the mockup's alpha MEASURED against the same sky in 9.png (fix-bar: rows y 8 .. 55 of 10.png, all three channels; game x: alpha). b1a-bar's first fade was half of it from x 320 on (the verifier)
    local MOCK = { { 210, 0.970 }, { 220, 0.905 }, { 230, 0.788 }, { 240, 0.699 }, { 250, 0.583 }, { 260, 0.488 }, { 270, 0.417 }, { 280, 0.345 }, { 290, 0.288 }, { 300, 0.234 }, { 310, 0.191 },
        { 320, 0.153 }, { 330, 0.127 }, { 340, 0.094 }, { 350, 0.083 }, { 360, 0.060 }, { 370, 0.053 }, { 380, 0.041 }, { 390, 0.031 }, { 400, 0.019 }, { 410, 0.011 }, { 420, 0.008 } }
    local bad, worst = {}, 0
    for _, p in ipairs(MOCK) do
        local e = math.abs(U.BandAlpha(p[1]) - p[2])
        worst = math.max(worst, e)
        if e > 0.035 then bad[#bad + 1] = string.format("%d: %.3f (%.3f)", p[1], U.BandAlpha(p[1]), p[2]) end
    end
    check(#bad == 0 and U.BandAlpha(214) == 1 and U.BandAlpha(500) == 0, "B4 the band's fade follows the mockup's from x 210 to 420 within 0.035 (worst %.3f; 1 to x 214, none from 500: %s)", worst, table.concat(bad, ", "))
    for _, W in ipairs({ { 1280, 960 }, { 3440, 1440 } }) do
        local m = layout(W[1], W[2])
        R.list = {}
        local xe = U.PaintBand(m, 0, 1)
        local strips = {}
        for _, r in ipairs(R.list) do if r[1] == "R" then strips[#strips + 1] = r end end
        local gaps, last = 0, nil
        for _, r in ipairs(strips) do
            if last and r.x ~= last.x + last.w then gaps = gaps + 1 end
            last = r
        end
        local first = strips[1]
        local at200, at240
        for _, r in ipairs(strips) do
            local cx = r.x + r.w / 2
            if not at200 and cx >= sx(m, 199) then at200 = r end
            if not at240 and cx >= sx(m, 240) then at240 = r end
        end
        check(first and first.x == 0 and math.abs(first.c[1] - 32) <= 3 and math.abs(first.c[2] - 122) <= 3 and first.c[4] == 255, "B4 %dx%d the band starts at the SCREEN's left edge in the mockup's dark green 207A01 (%s)",
            W[1], W[2], first and string.format("x %d: %d %d %d %d", first.x, first.c[1], first.c[2], first.c[3], first.c[4]) or "none")
        check(at200 and math.abs(at200.c[1] - 189) <= 4 and math.abs(at200.c[2] - 246) <= 3 and at200.c[4] == 255, "B4 %dx%d yellow-green BDF604 at game x 200 (%s)", W[1], W[2],
            at200 and string.format("%d %d %d", at200.c[1], at200.c[2], at200.c[3]) or "none")
        check(at240 and near(at240.c[4] / 255, U.BandAlpha(241), 0.03) and near(at240.c[4] / 255, 0.699, 0.04), "B4 %dx%d at game x 240 the alpha the mockup has (%.2f; MEASURED 0.70)", W[1], W[2], at240 and at240.c[4] / 255 or -1)
        -- (the last strip of alpha 1 / 255 ends at game x 440, U.BAND.seen_to: the faint tail the mockup still has at 380 .. 420)
        check(gaps == 0 and last and last.x + last.w >= sx(m, 436) and last.x + last.w <= sx(m, 440) + 1 and last.c[4] >= 1 and near(xe, sx(m, 440), 0.01) and near(first.y, sy(m, 0), 0.5) and near(first.y + first.h, sy(m, 324), 1),
            "B4 %dx%d the strips tile without a gap from x 0 to game x 436 .. 440 (%.0f px, alpha %d there), from the top to game y 324 (%d gaps)", W[1], W[2], last and last.x + last.w or -1, last and last.c[4] or -1, gaps)
    end
    -- the panel painted on Sonic with the band slid in: its self-check line
    local st = new_st(1)
    st.slot = 0
    if U.PanelOpen(st, "test") then
        st.upT0 = SysTime() - 5
        pictures(true)
        R.list = {}
        local ok, err = pcall(U.PanelPaint, st, layout(3440, 1440), 3440, 1440)
        pictures(false)
        check(ok, "B4 the panel paints (%s)", tostring(err))
        local texts, whole = 0, 0
        for _, r in ipairs(R.list) do
            if r[1] == "T" and r.mat and r.mat.text then
                texts = texts + 1
                if r.whole or not (r.uv and r.uv[1] == 0.125 and r.uv[4] == 0.5) then whole = whole + 1 end
            end
        end
        check(texts >= 10 and whole == 0, "B4 the panel's %d texts are drawn by their own UVs of the atlas page (b1a-text's API; %d as a whole page)", texts, whole)
        local line = logged("^upgrades Choose Your Upgrade: the band from the screen's left edge to x 2080 px of 3440 %(game x 440")
        check(line ~= nil, "B4 the self-check line: %s", tostring(line or logged("^upgrades Choose Your Upgrade: the band")))
    end
end

-- ---- B5 (the names fix after beta 1a, sadc/build/research/b1a2): A SKIN'S NAME AND PLATE ON THE REAL SCREEN are atlas pictures drawn by S.DrawFilter at the game's own quads with surface.DrawTexturedRectUV,
-- in the quads' colour, at the game's slot in the back pass (before the ring's neighbour names), the game's m_sonic / B_SONIC_e draws skipped. Not ready, or read changed: the game's own (beta 1a: a
-- canvas material on the game's vertices through mesh, which turned into black squares in the owner's game) -------------------------------------------------------------------------------------------------------
if SCR then
    local H = GSA1.SkinHud
    local kn, kp = nil, nil
    for i = 0, SCR.nd - 1 do
        if SCR.names[i] == "m_sonic" then kn = i * 11 end
        if SCR.names[i] == "B_SONIC_e" then kp = i * 11 end
    end
    local function box_of(k)
        local first, count = SCR.d[k + 2], SCR.d[k + 3]
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
        for v = first, first + count - 1 do
            local o = v * 8
            x0, y0, x1, y1 = math.min(x0, SCR.v[o + 1]), math.min(y0, SCR.v[o + 2]), math.max(x1, SCR.v[o + 1]), math.max(y1, SCR.v[o + 2])
        end
        local o = first * 8
        return x0, y0, x1, y1, { SCR.v[o + 5], SCR.v[o + 6], SCR.v[o + 7], SCR.v[o + 8] }, count
    end
    check(kn and kp, "B5 the real screen has m_sonic and B_SONIC_e")
    if kn and kp then
        local page = { name = "gsa1_textpage_1_2048x1024_BGRA8888" }
        local pA = { mat = page, u0 = 16 / 2048, v0 = 16 / 1024, u1 = 528 / 2048, v1 = 144 / 1024, w = 512, h = 128 }
        local pB = { mat = page, u0 = 594 / 2048, v0 = 16 / 1024, u1 = 1618 / 2048, v1 = 144 / 1024, w = 1024, h = 128 }
        local saved = H.mats.metalsonic
        local shown = {}
        local real_shown = H.Shown
        H.Shown = function(id, which, gname, archive, tex, kind) shown[#shown + 1] = { id = id, which = which, gname = gname, archive = archive, tex = tex, kind = kind } end
        for _, W in ipairs({ { 1280, 960 }, { 3440, 1440 } }) do
            local m = layout(W[1], W[2])
            gen_now = gen_now + 1
            H.mats.metalsonic = { name = pA, plate = pB }
            shown = {}
            local list = paint(new_st(2), W[1], W[2])
            local ti, tp, ni, tails, sonic_mesh = nil, nil, nil, nil, 0
            for i, r in ipairs(list) do
                if r[1] == "T" and r.mat == page and r.uv and r.uv[1] == pA.u0 then ti = ti or i end
                if r[1] == "T" and r.mat == page and r.uv and r.uv[1] == pB.u0 then tp = tp or i end
                if r[1] == "M" and r.mat and (r.mat.name == "m_tails" or r.mat.name == "m_supersonic") then tails = tails or i end
                if r[1] == "M" and r.mat and (r.mat.name == "m_sonic" or r.mat.name == "B_SONIC_e") then sonic_mesh = sonic_mesh + 1 end
            end
            local x0, y0, x1, y1, c, count = box_of(kn)
            local t = ti and list[ti]
            local px, py = math.floor(sx(m, x0) + 0.5), math.floor(sy(m, y0) + 0.5)
            local okbox = t and t.x == px and t.y == py and t.w == math.floor(sx(m, x1) + 0.5) - px and t.h == math.floor(sy(m, y1) + 0.5) - py
            check(count == 6 and okbox and t.c[1] == c[1] and t.c[2] == c[2] and t.c[3] == c[3] and t.c[4] == c[4] and t.uv[3] == pA.u1 and t.uv[4] == pA.v1 and tp ~= nil and sonic_mesh == 0,
                "B5 %dx%d Metal Sonic: his name drawn with surface.DrawTexturedRectUV at the game's m_sonic quad (%s), in its colour %s, his plate too; the game's m_sonic and B_SONIC_e not drawn (%d)",
                W[1], W[2], t and string.format("%d,%d %dx%d", t.x, t.y, t.w, t.h) or "none", table.concat(c, " "), sonic_mesh)
            check(tails == nil or (ti and ti < tails), "B5 %dx%d at the game's own slot: before the ring's neighbour names m_tails / m_supersonic (record %s, %s)", W[1], W[2], tostring(ti), tostring(tails))
            local by = {}
            for _, x in ipairs(shown) do by[x.which] = x end
            check(#shown == 2 and by.name and by.name.gname == "m_sonic" and by.name.id == "metalsonic" and by.name.kind == G.FRONTEND.KIND and by.name.archive == SCR.d[kn + 4] and by.plate and by.plate.gname == "B_SONIC_e",
                "B5 %dx%d each picture's show is told to feat/cl_skinhud.lua (its self-check's clock), with the game's draw it stands in for (%d)", W[1], W[2], #shown)
            -- not ready (or read changed: the fallback): the game's own name and plate, through the mesh as always
            H.mats.metalsonic = { name = false, plate = false }
            gen_now = gen_now + 1
            list = paint(new_st(2), W[1], W[2])
            local pics, game = 0, 0
            for _, r in ipairs(list) do
                if r[1] == "T" and r.mat == page then pics = pics + 1 end
                if r[1] == "M" and r.mat and (r.mat.name == "m_sonic" or r.mat.name == "B_SONIC_e") then game = game + 1 end
            end
            check(pics == 0 and game == 2, "B5 %dx%d not ready or read changed: the game's own m_sonic and B_SONIC_e drawn (%d), no picture (%d): never a blank or black frame", W[1], W[2], game, pics)
        end
        H.Shown = real_shown
        H.mats.metalsonic = saved
    end
end

-- ---- --record: every draw call at both sizes, for the notes' pictures ------------------------------------------------------------------------------------------------------------------------------------------
if record then
    local function q(v) return string.format("%.2f", v) end
    local function emit(tag, W, H)
        print(string.format("REC BEGIN %s %d %d", tag, W, H))
        for _, r in ipairs(R.list) do
            local c = r.c or { 255, 255, 255, 255 }
            if r[1] == "R" then
                print(string.format("REC R %s %s %s %s %d %d %d %d", q(r.x), q(r.y), q(r.w), q(r.h), c[1], c[2], c[3], c[4]))
            elseif r[1] == "P" then
                local pts = {}
                for _, v in ipairs(r.p) do pts[#pts + 1] = q(v.x) .. " " .. q(v.y) end
                print(string.format("REC P %d %d %d %d %s", c[1], c[2], c[3], c[4], table.concat(pts, " ")))
            elseif r[1] == "T" then
                local mt = r.mat or {}
                local mc = mt.c or { 255, 255, 255 }
                local oc = mt.oc or { 0, 0, 0 }
                print(string.format("REC T %s %s %s %s %d %d %d %d %d %d %d %s|%s", q(r.x), q(r.y), q(r.w), q(r.h), mc[1], mc[2], mc[3], mt.ow or 0, oc[1], oc[2], oc[3], tostring(mt.element), tostring(mt.text)))
            elseif r[1] == "S" then
                print(string.format("REC S %s %s %d %d %d %s|%s", q(r.x), q(r.y), r.c.r, r.c.g, r.c.b, tostring(r.font), tostring(r.text)))
            elseif r[1] == "M" then
                local pts = {}
                for _, v in ipairs(r.v) do pts[#pts + 1] = string.format("%s %s %s %s %d %d %d %d", q(v.x), q(v.y), q(v.u or 0), q(v.v or 0), v.r or 0, v.g or 0, v.b or 0, v.a or 0) end
                print(string.format("REC M %s %d %s", tostring(r.mat and r.mat.name), #r.v, table.concat(pts, " ")))
            end
        end
        print("REC END")
    end
    pictures(true)
    for _, W in ipairs({ { 1280, 960 }, { 3440, 1440 } }) do
        for _, skin in ipairs({ 1, 2 }) do
            gen_now = gen_now + 1
            local st = new_st(skin)
            if not SCR then st.scr = { gen = 1, nd = 0, nv = 0, d = {}, v = {} } end
            paint(st, W[1], W[2])
            emit(string.format("bar_skin%d", skin), W[1], W[2])
            -- Choose Your Upgrade on top (slid in)
            if U.PanelOpen(st, "record") then
                st.upT0 = SysTime() - 5
                paint(st, W[1], W[2])
                emit(string.format("upgrades_skin%d", skin), W[1], W[2])
            end
        end
    end
    pictures(false)
end

S.FaultR = real_fault
if Tx then Tx.Get, Tx.FontFor = real_get, real_font end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
