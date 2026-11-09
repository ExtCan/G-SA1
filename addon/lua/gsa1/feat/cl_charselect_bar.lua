-- G-SA1 Character Select's bottom bar, skins on Up / Down, and the seams of the Upgrades panel (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 4.4, 4.5, 4.6, 4.9 with RX.1; the owner's mockup,
-- rounds plan 14.1bj). feat/cl_charselect.lua calls these through its four seams (S.DrawFilter in paint_2d, S.Overlay at the end of both paints, S.PadFilter / S.KeyFilter / S.MouseFilter first in each design's
-- input, S.WheelFilter in S.OnWheel); every one is optional there, so without this file the screen is 0.9.9g's. The game's screen, its code and its events never change: the bar is drawn over the game's own
-- bar or in place of one of its draws (the support ball: the game's left sphere with other vertex colours; a skin's name and nameplate: the skin's pictures on the game's own vertices, UVs and colours, so
-- they pulse, fade and grey exactly as the game's).
-- THE PICK PATH STAYS 0.9.9g's (RX.1): no filter here ever takes Start, Escape, Enter, keypad Enter, Space or a key S.IsOwnKey names; with the Upgrades panel up the pad gives the game Start alone
-- (cl_charselect.lua step_r), Design S's A, B, Back, Y, the D-pad and the shoulders are taken out of the edges (so Start alone reaches its pick line), and nothing goes into events_r: the panel closes the
-- frame this file sees st.picked.
-- 1.0.0-beta1a (lane b1a-bar; notes sadc build/research/b1a/b1a-bar): MEASURED on the disc through the module (tests/feat_charselect_bar_binding_test.cpp), libsa1 merges the screen's draws of one state, so
-- the two bar spheres' bases are quads 8 and 9 of ONE draw of nine (with the ring's seven): beta 1's filter wanted a draw of one quad and never tinted the ball (the owner's red ball on Sonic). The ball is
-- now found quad by quad and its six vertices get the colour (the game's alpha kept). The game's bar ends are quads reaching x -68 and 700; S.PlaceX sends a vertex outside 0..640 to the screen's edge,
-- which stretched them into the side bars (and squeezed them on a 4:3 screen): each end quad is now cut at the picture's edge with its UV and colours cut with it, so the bar ends where the Dreamcast
-- shows it (x 28 and 604, the owner's mockup). The pink tabs are shapes (surface.DrawPoly, the emote wheel's proven path), not boxes.
-- Fix run (fix-bar): a quad wholly outside 0 .. 640 is never cut (no division by zero); the ends' self-check line names every draw it cut and how far each reached; the ball's line is said once per
-- shown skin (a step to Metal Sonic reaches the log too); a font's text (the path until the text pictures pass their read-back) keeps to its width as a picture does.
-- THE NAMES FIX after beta 1a (sadc/build/research/b1a2; the owner: "The pulsating names appear for a second and then turn into black squares"): a skin's name and plate are no longer a material swapped onto
-- the game's vertices (beta 1a's canvases through mesh). Each is an atlas picture of feat/cl_skinhud.lua, drawn by S.DrawFilter at the game's own quad with surface.DrawTexturedRectUV (T.DrawPic), the
-- call that draws the bar's labels from the same pages in this same paint, in the game's colour and alpha, at the game's own slot in the back pass; the filter then answers false (the game's draw skipped).
-- Not ready, read changed, or not one plain quad: nil, and the game's own name and plate are drawn.
GSA1 = GSA1 or {}
local S = GSA1.CharSelect
if not (S and S.Close) then error("gsa1/feat/cl_charselect.lua did not load: the bar needs it") end
local band, bor, bnot = bit.band, bit.bor, bit.bnot

local cvb = {
    bar = GSA1.ConVar("gsa1_charselect_bar", 1, "Character Select: show the skins and upgrades bar (the support ball, the skin counter, the two pink tabs; off: the game's bottom bar)", 0, 1),
    upgrades = GSA1.ConVar("gsa1_charselect_upgrades", 1, "Character Select: Y (U on the keyboard) opens Choose Your Upgrade (off: Y does nothing)", 0, 1),
    names = GSA1.ConVar("gsa1_charselect_skin_names", 1, "Character Select: skins show their own name and nameplate (off: the game's name stays under a skin)", 0, 1),
}
S.barcv = cvb

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("charselect", fmt, ...) end
end

-- keys (GMod's KEY_*; the numbers when a global is missing)
local K_UP, K_DOWN, K_LEFT, K_RIGHT = KEY_UP or 88, KEY_DOWN or 90, KEY_LEFT or 89, KEY_RIGHT or 91
local K_W, K_S, K_D, K_E, K_U, K_R, K_L = KEY_W or 33, KEY_S or 29, KEY_D or 14, KEY_E or 15, KEY_U or 31, KEY_R or 28, KEY_L or 22
local K_BACK = KEY_BACKSPACE or 66
local K_PICK = { [KEY_ENTER or 64] = true, [KEY_PAD_ENTER or 51] = true, [KEY_SPACE or 65] = true }   -- the keyboard's pick: never taken here (RX.1)
S.PICK_KEYS = K_PICK
local M_LEFT, M_RIGHT = MOUSE_LEFT or 107, MOUSE_RIGHT or 108
-- the XInput bits of the panel (src/core/pad.hpp): Y, the shoulders and the triggers are never forwarded to the game (cl_charselect.lua step_r)
S.PAD_Y, S.PAD_LB, S.PAD_RB, S.PAD_LT, S.PAD_RT, S.PAD_X = 0x8000, 0x0100, 0x0200, 0x10000, 0x20000, 0x4000
-- Design S: what the panel takes out of the edges while it is up (RX.1: never Start)
S.PANEL_PAD = bor(S.PAD_A, S.PAD_B, S.PAD_BACK, S.PAD_Y, S.PAD_UP, S.PAD_DOWN, S.PAD_LEFT, S.PAD_RIGHT, S.PAD_LB, S.PAD_RB, S.PAD_LT, S.PAD_RT)

-- the bar's places on the game's 640 x 480 screen. The owner's mockup 9 (1280 x 960: game px x 2), MEASURED in beta 1a: each tab's box and the two radii of its big curve (the owner's tab art 13.png: top
-- left, the Y tab; 14.png: top right, the D-pad tab: rx, ry and the superellipse's exponent, fitted to the mockup's pink rows), the small corners; each text's centre (of its capitals) and its size (a font's size; capitals are about 0.7 of it) and the widest it may be. The spheres
-- MEASURED on the disc (LANDING.md C; tests/feat_charselect_bar_binding_test.cpp): 50 x 50 at (128, 418) and (504, 418). ends_y: the band of y the bar's end quads are in (386 .. 450)
S.BAR = {
    ball_l = { 128, 418 }, ball_r = { 504, 418 }, ball_size = 50, ball_tol = 3,
    tab_y = { 36, 392.5, 98.5, 419 }, tab_d = { 516, 361, 593, 390 },
    curve_y = { 38, 18, 1.4 }, curve_d = { 25, 17, 2 }, corner = 2.6,
    text_y = { 69.5, 408, 14, 50 }, text_d = { 557, 377, 11, 64 },
    lbl_up = { 66, 430, 14, 60 }, lbl_skins = { 565.5, 402.5, 20.5, 52 },
    counter = { 504.5, 415, 22, 44 },
    ends_y = { 380, 460 },
}
-- the tabs' colours (the owner's 13.png / 14.png, MEASURED): the pink, the lighter top, the dark rim on the right and below; white letters on them. The bar's words: the mockup's pale blue-white
-- (MEASURED 192..200, 220..224, 255 in 9.png) with a dark blue rim on "Upgrades" (the bar's light lower edge) and none on "Skins" (its dark top); the counter white with a black rim
S.TAB_PINK, S.TAB_LIGHT, S.TAB_RIM = { 255, 12, 255 }, { 255, 120, 255 }, { 61, 0, 56 }
S.TAB_TEXT = { 255, 255, 255 }
S.LABEL = { 196, 222, 255 }
S.LABEL_OUTLINE = { 8, 75, 129 }
-- the support ball by upgrade_model_compatibility: the owner's 11.png, MEASURED on its three balls (green 4DFF00, yellow FFCC00; the red is the game's own FFFF0000)
S.BALL = { full = { 77, 255, 0, tint = true }, partial = { 255, 204, 0, tint = true }, none = { 255, 0, 0, tint = true } }

local function idle(st)
    if st.picked then return false end
    if st.design == "R" then return tonumber(st.state and st.state.phase) == 0 end
    return true
end

-- the slot's shown skin: index (1 = the character itself), and the list's length
function S.SkinOf(st, slot)
    slot = slot or st.slot
    local n = #S.SlotNames(slot)
    local i = st.skins and st.skins[slot] or 1
    if i < 1 or i > n then i = 1 end
    return i, math.max(1, n)
end

-- the entry a slot shows now in this state (a skin's registry entry, or nil for the character itself), and its name
function S.SkinEntry(st, slot)
    slot = slot or st.slot
    local i = S.SkinOf(st, slot)
    local name = S.SlotNames(slot)[i] or S.EntryOf(slot)
    local K = GSA1.Skins
    return K and K.SKINS and K.SKINS[name] or nil, name
end

-- shows skin `index` of `slot` (1 = the slot's own character). Design R: on the game's screen at once through gsa1.FrontendSkin (the screen's slot 0 wears it); a refusal (a module without skins, a disc
-- without the files) leaves the index where it was and logs why, so a pick never names a skin the screen did not show (select 4.5)
function S.SetSkin(st, slot, index)
    local names = S.SlotNames(slot)
    if index < 1 or index > #names then return false end
    local name = names[index]
    local K = GSA1.Skins
    local skin = index > 1 and K and K.SKINS[name] or nil
    local ok, msg, code = true, nil, nil
    if index > 1 and not (skin and gsa1 and gsa1.SUPER and gsa1.SUPER.CREATE_SKIN and gsa1.FrontendSkin) then
        ok, msg = false, "this module has no skins"
    elseif st.design == "R" and gsa1.FrontendSkin then
        if skin then
            ok, msg, code = gsa1.FrontendSkin(K.DescOf(skin), K.Voiceless(skin))
        else
            ok, msg, code = gsa1.FrontendSkin(nil)
        end
    end
    if not ok then
        log("the skin %s: refused: %s (%s)", tostring(name), tostring(msg), tostring(code))
        return false
    end
    st.skins = st.skins or {}
    st.skins[slot] = index
    -- (the index in the line, so the log's repeat filter never folds a step into the one before it)
    log("slot %d: skin %d/%d, %s", slot, index, #names, tostring(name))
    if S.SkinShown then S.SkinShown(st, slot) end
    return true
end

-- one step through the slot's skins: +1 Up, -1 Down, wrapping (Sonic > Metal Sonic > Mecha Sonic > Sonic)
function S.StepSkin(st, dir)
    local i, n = S.SkinOf(st, st.slot)
    if n < 2 then return false end
    return S.SetSkin(st, st.slot, (i - 1 + dir) % n + 1)
end

-- the game's screen opened: the slot it opens on keeps the skin you are (start_r); the characters in the circle wear the upgrade models you chose (select 4.3.3)
function S.ApplySkins(st)
    for slot, i in pairs(st.skins or {}) do
        if i > 1 and not S.SetSkin(st, slot, i) then st.skins[slot] = 1 end
    end
    local U = GSA1.UpgradeModels
    if U and U.ApplyFrontend then U.ApplyFrontend() end
end

-- Design S's line under the buttons (cl_charselect.lua's fixed text path); nil: none
function S.SkinLineS(st)
    if not GSA1.CharSelect.cv.skins:GetBool() then return nil end
    local i, n = S.SkinOf(st, st.slot)
    local up = cvb.upgrades:GetBool() and #S.UpgradeList(st) > 0
    if n < 2 and not up then return nil end
    local _, shown = S.SkinEntry(st, st.slot)
    local c = GSA1.CharacterByName and GSA1.CharacterByName(shown)
    local parts = {}
    if n >= 2 then parts[#parts + 1] = string.format("Skin %d/%d: %s   Up / Down: skins", i, n, c and c.title or "?") end
    if up then parts[#parts + 1] = "Y or U: upgrades" end
    return table.concat(parts, "   ")
end

-- the upgrades the Upgrades panel lists for the selected slot (question 15's default: the character's own; slot 6, Super Sonic, Sonic's)
function S.UpgradeList(st)
    local U = GSA1.UpgradeModels
    local c = GSA1.CharacterByName and GSA1.CharacterByName(S.EntryOf(st.slot))
    if not (U and c) or c.noUpgrades then return {} end
    return U.ListFor(c.kind)
end

-- the support ball's colour for the shown entry (nil: the game's red: a character without upgrades), and its name (full / partial / none)
function S.BallTint(st)
    if #S.UpgradeList(st) == 0 then return nil, "no upgrades" end
    local e = S.SkinEntry(st, st.slot)
    local how = e and e.upgrade_model_compatibility or "full"
    return S.BALL[how] or S.BALL.none, S.BALL[how] and how or "none"
end

-- the screen's vertices (gsa1.FrontendScreen's flat array: x, y, u, v, r, g, b, a a vertex, from 0) -----------------------------------------------------------------------------------------------------------
local VS = 8

-- the game's 640 x 480 box of six vertices from `q`, and the first one's colour
local function quad_box(V, q)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for v = q, q + 5 do
        local o = v * VS
        local x, y = V[o + 1], V[o + 2]
        if not (x and y) then return nil end
        if x < x0 then x0 = x end
        if x > x1 then x1 = x end
        if y < y0 then y0 = y end
        if y > y1 then y1 = y end
    end
    local o = q * VS
    return x0, y0, x1, y1, V[o + 5], V[o + 6], V[o + 7]
end

-- is the quad from vertex q the tinted base of a bar sphere centred on `at`? (each bar sphere is a 50 x 50 tinted base, then a white shine; the ring's spheres are 48 x 48: LANDING.md C)
local function bar_sphere(V, q, at)
    local x0, y0, x1, y1, r, g, b = quad_box(V, q)
    if not x0 then return false end
    local B = S.BAR
    if math.abs(x1 - x0 - B.ball_size) > 1.5 or math.abs(y1 - y0 - B.ball_size) > 1.5 then return false end
    if math.abs((x0 + x1) / 2 - at[1]) > B.ball_tol or math.abs((y0 + y1) / 2 - at[2]) > B.ball_tol then return false end
    return not ((r or 0) >= 250 and (g or 0) >= 250 and (b or 0) >= 250)      -- (the shine is white)
end

-- the quads of draw k (its first vertex, its vertex count; nil: not whole quads)
local function quads_of(st, D, k)
    local V = st.scr and st.scr.v
    local first, count = D[k + 2], D[k + 3]
    if not (V and first and count) or count < 6 or count % 6 ~= 0 then return nil end
    return V, first, count
end

-- does draw k hold the tinted base of the bar's sphere at (cx, cy)? (any quad of it: libsa1 merges the screen's draws of one state, MEASURED b1a-bar)
function S.IsBarSphere(st, D, k, at)
    local V, first, count = quads_of(st, D, k)
    if not V then return false end
    for q = first, first + count - 6, 6 do
        if bar_sphere(V, q, at) then return true end
    end
    return false
end

-- THE SUPPORT BALL: the left sphere's six vertices of draw k get `tint` (nil: the game's own colours back), the game's alpha kept. The colours the module wrote this screen generation are kept the first
-- time, so a tint taken away (the option off, a character without upgrades) gives the game's red back before the module's next generation. Returns how many quads it found (0 or 1) and which
function S.TintBall(st, D, k, tint)
    local V, first, count = quads_of(st, D, k)
    if not V then return 0 end
    local gen = st.scr.gen
    if st.ballGen ~= gen or not st.ballSaved then st.ballGen, st.ballSaved = gen, {} end
    local found, at = 0, nil
    for q = first, first + count - 6, 6 do
        if bar_sphere(V, q, S.BAR.ball_l) then
            found, at = found + 1, q
            for v = q, q + 5 do
                local o = v * VS
                local was = st.ballSaved[v]
                if not was then
                    was = { V[o + 5], V[o + 6], V[o + 7] }
                    st.ballSaved[v] = was
                end
                local c = tint or was
                V[o + 5], V[o + 6], V[o + 7] = c[1], c[2], c[3]
            end
        end
    end
    return found, at and (at - first) / 6 + 1, count / 6
end

-- THE BAR'S ENDS: a quad of the bar's band of y with a vertex outside the game's 0 .. 640 is cut at the picture's edge (x 0.001 / 639.999, so S.PlaceX keeps it in the 4:3 box instead of sending it to the
-- screen's edge); the cut vertex takes the u, v and colour of its edge at that x (the partner on the quad's other side, same y). Its cut-off part is the texture's clear end (MEASURED through the module,
-- gsa1.FrontendTexturePixel: cs_ce_bd_2's columns 0 .. 95 of 256 are clear, so the bar's picture starts at x 28 and ends at 604), so the Dreamcast's picture is unchanged and stays where it is. Once cut, a
-- quad is inside and is never cut again. A quad wholly outside 0 .. 640 is left as it is (S.PlaceX puts all of it on the screen's edge, zero wide, where the Dreamcast clips it away; fix-bar: cutting it
-- divided by zero). Returns the vertices it moved, and the least and the greatest x the cut vertices had (nil: none on that side)
local EDGE = 0.001
function S.KeepEnds(st, D, k)
    local V, first, count = quads_of(st, D, k)
    if not V then return 0 end
    local B, moved, lo, hi = S.BAR, 0, nil, nil
    for q = first, first + count - 6, 6 do
        local x0, y0, x1, y1 = quad_box(V, q)
        if x0 and y0 >= B.ends_y[1] and y1 <= B.ends_y[2] and (x0 < 0 or x1 > 640) and x1 > EDGE and x0 < 640 - EDGE and x1 - x0 > 1 then
            for v = q, q + 5 do
                local o = v * VS
                local x = V[o + 1]
                local edge = (x < 0 and EDGE) or (x > 640 and 640 - EDGE) or nil
                if edge then
                    local far = x < 0 and x1 or x0
                    local p
                    for w = q, q + 5 do
                        local ow = w * VS
                        if math.abs(V[ow + 2] - V[o + 2]) < 0.01 and math.abs(V[ow + 1] - far) < 0.01 then
                            p = ow
                            break
                        end
                    end
                    local den = p and V[p + 1] - x or 0
                    if math.abs(den) > 1e-6 then
                        local t = (edge - x) / den
                        for c = 3, 8 do V[o + c] = V[o + c] + (V[p + c] - V[o + c]) * t end
                        V[o + 1] = edge
                        moved = moved + 1
                        if x < 0 and (not lo or x < lo) then lo = x end
                        if x > 640 and (not hi or x > hi) then hi = x end
                    end
                end
            end
        end
    end
    return moved, lo, hi
end

-- what the filters saw this paint, for the self-check line (S.Overlay counts the paints: st.barPaint). One table kept, emptied for each paint (nothing made a frame)
local function seen(st)
    local f = st.barFrame
    local p = st.barPaint or 0
    if not f then
        f = {}
        st.barFrame = f
    end
    if f.paint ~= p then
        f.paint, f.ball, f.ballQuad, f.ballOf, f.ballDraw, f.ballDrawName, f.ballTint, f.ballHow, f.cuts = p, nil, nil, nil, nil, nil, nil, nil, nil
    end
    return f
end

-- A SKIN'S NAME OR PLATE (the names fix): the game's draw k as one axis-aligned rectangle of one colour (MEASURED, the trace lane: m_sonic and B_SONIC_e are one quad of 6 vertices, UVs 0..1, one
-- colour, every frame) -> its box in game px, the UVs at its top left and bottom right, its colour; nil: not that shape (the game's own is drawn)
local function same(p, q) return p == nil or math.abs(p - q) < 1e-4 end
local function skin_quad(st, D, k)
    local V, first, count = quads_of(st, D, k)
    if not V or count ~= 6 then return nil end
    local x0, y0, x1, y1 = quad_box(V, first)
    if not x0 or x1 - x0 < 0.5 or y1 - y0 < 0.5 then return nil end
    local o1 = first * VS
    local r, g, b, a = V[o1 + 5], V[o1 + 6], V[o1 + 7], V[o1 + 8]
    if not (r and g and b and a) then return nil end
    local ua, va, ub, vb = nil, nil, nil, nil
    for v = first, first + 5 do
        local o = v * VS
        local x, y, u, w = V[o + 1], V[o + 2], V[o + 3], V[o + 4]
        local left, top = math.abs(x - x0) < 0.01, math.abs(y - y0) < 0.01
        if not ((left or math.abs(x - x1) < 0.01) and (top or math.abs(y - y1) < 0.01)) then return nil end
        if math.abs(V[o + 5] - r) > 0.5 or math.abs(V[o + 6] - g) > 0.5 or math.abs(V[o + 7] - b) > 0.5 or math.abs(V[o + 8] - a) > 0.5 then return nil end
        if not (u and w) then return nil end
        if left then
            if not same(ua, u) then return nil end
            ua = u
        else
            if not same(ub, u) then return nil end
            ub = u
        end
        if top then
            if not same(va, w) then return nil end
            va = w
        else
            if not same(vb, w) then return nil end
            vb = w
        end
    end
    if not (ua and ub and va and vb) then return nil end
    return x0, y0, x1, y1, ua, va, ub, vb, r, g, b, a
end

-- draws picture `pic` (an atlas part of feat/cl_skinhud.lua) where the game's draw k would draw, placed by this paint's own layout (st.m: S.Layout in paint_r) as paint_2d places the game's vertices,
-- with surface.DrawTexturedRectUV in the draw's colour and alpha (T.DrawPic, the bar's labels' call). true: drawn; false: not this shape or no layout (the game's own is drawn)
function S.DrawSkinPicture(st, D, k, pic)
    local Tx = GSA1.Text
    local m = st.m
    if not (Tx and Tx.DrawPic and m and m.W and pic and pic.mat and pic.u1) then return false end
    local x0, y0, x1, y1, ua, va, ub, vb, r, g, b, a = skin_quad(st, D, k)
    if not x0 then return false end
    local X0, Y0, X1, Y1 = S.PlaceX(m, x0), S.PlaceY(m, y0), S.PlaceX(m, x1), S.PlaceY(m, y1)
    local px, py = math.floor(X0 + 0.5), math.floor(Y0 + 0.5)
    local pw, ph = math.floor(X1 + 0.5) - px, math.floor(Y1 + 0.5) - py
    if pw <= 0 or ph <= 0 then return false end
    if ua == 0 and va == 0 and ub == 1 and vb == 1 then
        Tx.DrawPic(pic, px, py, pw, ph, r, g, b, a)
    else
        Tx.DrawPic(pic, px, py, pw, ph, r, g, b, a, ua, va, ub, vb)
    end
    return true
end

-- THE DRAW FILTER (paint_2d): nil = as today; false = skip; a material = this one on the game's vertices; { r, g, b, tint = true } = these vertex colours on the whole draw (the game's alpha kept).
-- The bar's ends and the support ball change the screen's own vertices instead (their draws hold other quads), and return nil. A skin's name and plate are drawn here (S.DrawSkinPicture) and return false
function S.DrawFilter(st, name, D, k)
    if not name then return nil end
    local bar = cvb.bar:GetBool()
    if bar and S.HiddenTexture(name) then return false end            -- File and Clear stay hidden while the bar is on: the counter sits where the Clear digits were
    local f = seen(st)
    local moved, lo, hi = S.KeepEnds(st, D, k)                          -- (always: the game's own bar, bar or not, ends where the Dreamcast shows it)
    if moved > 0 and not (st.barSaid and st.barSaid.ends) then          -- (each draw it cut, for the self-check line: only until that line is said)
        f.cuts = f.cuts or {}
        f.cuts[#f.cuts + 1] = { name = name, n = moved, lo = lo, hi = hi }
    end
    local ln = string.lower(name)
    if cvb.names:GetBool() and st.skins then
        local H = GSA1.SkinHud
        for slot, i in pairs(st.skins) do
            if i > 1 then
                local base = S.SLOT_ENTRY[slot]
                if base and (ln == "m_" .. base or ln == "b_" .. base .. "_e" or ln == "b_" .. base) then
                    local id = S.SlotNames(slot)[i]
                    local which = ln == "m_" .. base and "name" or "plate"
                    local get = H and (H.Picture or H.Material)
                    local pic = get and get(id, which)
                    if pic and S.DrawSkinPicture(st, D, k, pic) then
                        if H.Shown then H.Shown(id, which, name, D[k + 4], D[k + 5], st.F and st.F.KIND) end
                        return false            -- (drawn: the game's own draw skipped)
                    end
                    return nil                  -- (not made yet, not read right, or read changed: the game's own, never a blank or black frame)
                end
            end
        end
    end
    local tint, how = nil, "the bar is off"
    if bar then tint, how = S.BallTint(st) end
    local found, quad, of = S.TintBall(st, D, k, tint)
    if found > 0 then f.ball, f.ballQuad, f.ballOf, f.ballDraw, f.ballDrawName, f.ballTint, f.ballHow = found, quad, of, k / 11, name, tint, how end
    return nil
end

-- 2D helpers (screen px from game px through the panel's own placing, so they follow the 4:3 box and gsa1_charselect_wide) ------------------------------------------------------------------------------
local function px(m, x) return S.PlaceX(m, x) end
local function py(m, y) return S.PlaceY(m, y) end

-- a text's picture through feat/cl_text.lua, or nil. 1.0.0-beta1a (b1a-text's API, sadc build/research/b1a/b1a-text/API.md): { mat = an atlas page, w, h, u0, v0, u1, v1 }, good for this frame
local function picture(text, element, size, col, outline)
    local Tx = GSA1.Text
    if not (Tx and Tx.Get) then return nil end
    local ok, m = pcall(Tx.Get, text, element, size, col, outline)
    if ok and type(m) == "table" and m.mat and (m.w or 0) > 0 and (m.h or 0) > 0 and m.u1 then return m end
    return nil
end

-- a picture into a box of screen px: its part of the page (T.DrawPic: the page's UVs), in white at full alpha (its colour is in the picture)
local function draw_pic(m, x, y, w, h)
    local Tx = GSA1.Text
    if Tx and Tx.DrawPic then return Tx.DrawPic(m, x, y, w, h, 255, 255, 255, 255) end
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(m.mat)
    surface.DrawTexturedRectUV(x, y, w, h, m.u0, m.v0, m.u1, m.v1)
end

-- the font a text keeps to `maxw` px with (fix-bar): measured by the engine itself (surface.GetTextSize, as cl_text.lua's probe and cl_upgrades.lua do), outline included; wider, the same font in the
-- size that fits (T.FontFor makes each size once). Today's engine font (a fallback of one size) stays as it is. Kept per font, text and width: nothing measured a frame
local fits = {}
local function width_of(font, text, ow)
    surface.SetFont(font)
    return (tonumber((surface.GetTextSize(text))) or 0) + 2 * ow
end
local function fitted_font(text, element, size, font, maxw, ow)
    local Tx = GSA1.Text
    if not (maxw and maxw > 0 and Tx and Tx.FontFor and surface.SetFont and surface.GetTextSize) then return font end
    local by = fits[font]
    if not by then
        by = {}
        fits[font] = by
    end
    local c = by[text]
    if c and c.maxw == maxw then return c.font end
    local best, w = font, width_of(font, text, ow)
    local s = size
    for _ = 1, 4 do                                     -- (a font's width is not quite in proportion to its size: up to four steps down)
        if w <= maxw or w <= 0 or s <= 8 then break end
        s = math.max(8, math.min(s - 1, math.floor(s * maxw / w)))
        local f2 = Tx.FontFor(element, s)
        if f2 == best then break end                    -- (a fallback of one size)
        best, w = f2, width_of(f2, text, ow)
    end
    if not c then
        c = {}
        by[text] = c
    end
    c.maxw, c.font = maxw, best
    return best
end
S.FittedFont = fitted_font

-- a text centred on (x, y) in screen px, at most `maxw` px wide (a picture wider is drawn smaller; a font's text in a smaller size of its font: fitted_font). Its picture, or its font until the picture is
-- ready. Returns how it was drawn: "picture" or the font's name
function S.BarText(text, element, size, col, x, y, outline, maxw)
    size = math.max(8, math.floor(size + 0.5))
    local m = picture(text, element, size, col, outline)
    if m then
        local k = (maxw and m.w > maxw) and maxw / m.w or 1
        local w, h = m.w * k, m.h * k
        draw_pic(m, math.floor(x - w / 2 + 0.5), math.floor(y - h / 2 + 0.5), w, h)
        return "picture"
    end
    local Tx = GSA1.Text
    local font = Tx and Tx.FontFor and Tx.FontFor(element, size) or "DermaDefaultBold"
    local c = col.r and col or Color(col[1], col[2], col[3], 255)
    local ow = type(outline) == "table" and outline[1] or tonumber(outline) or 0
    font = fitted_font(text, element, size, font, maxw, ow)
    if ow > 0 and draw.SimpleTextOutlined then
        local oc = type(outline) == "table" and Color(outline[2], outline[3], outline[4], 255) or Color(0, 0, 0, 255)
        draw.SimpleTextOutlined(text, font, x, y, c, 1, 1, ow, oc)
    else
        draw.SimpleText(text, font, x, y, c, 1, 1)
    end
    return tostring(font)
end

-- A PINK TAB (the owner's 13.png / 14.png): one convex shape, clockwise on screen as surface.DrawPoly draws it (the emote wheel's path, feat/cl_wheel.lua): a big curve on one top corner (left =
-- the Y tab, 13.png), small round corners on the other three. The big curve is a superellipse |x/rx|^e + |y/ry|^e = 1 (e 2: an ellipse; the mockup's Y tab MEASURED e 1.4, a long soft slope; its
-- D-pad tab e 2), convex for any e >= 1. All in screen px. Returns the outline's points from the top-left corner on
local function spow(v, p)
    if v < 0 then return -((-v) ^ p) end
    return v ^ p
end
local function arc(out, cx, cy, rx, ry, a0, a1, n, e)
    local p = 2 / (e or 2)
    for i = 0, n do
        local a = a0 + (a1 - a0) * i / n
        out[#out + 1] = { x = cx + spow(math.cos(a), p) * rx, y = cy + spow(math.sin(a), p) * ry }
    end
end
function S.TabShape(x0, y0, x1, y1, rx, ry, rc, big_left, e, n)
    n = n or 16
    local out = {}
    local hp = math.pi / 2
    if big_left then
        arc(out, x0 + rx, y0 + ry, rx, ry, math.pi, 3 * hp, n, e)
        arc(out, x1 - rc, y0 + rc, rc, rc, 3 * hp, 2 * math.pi, 3)
    else
        arc(out, x0 + rc, y0 + rc, rc, rc, math.pi, 3 * hp, 3)
        arc(out, x1 - rx, y0 + ry, rx, ry, 3 * hp, 2 * math.pi, n, e)
    end
    arc(out, x1 - rc, y1 - rc, rc, rc, 0, hp, 3)
    arc(out, x0 + rc, y1 - rc, rc, rc, hp, math.pi, 3)
    return out
end

-- the part of a convex shape above y = yc (still convex and clockwise; Sutherland-Hodgman against one line)
function S.ClipAbove(poly, yc)
    local out = {}
    local n = #poly
    for i = 1, n do
        local p, q = poly[i], poly[i % n + 1]
        local pin, qin = p.y <= yc, q.y <= yc
        if pin then out[#out + 1] = { x = p.x, y = p.y } end
        if pin ~= qin then
            local t = (yc - p.y) / (q.y - p.y)
            out[#out + 1] = { x = p.x + (q.x - p.x) * t, y = yc }
        end
    end
    return out
end

local function moved_poly(poly, dx, dy)
    local out = {}
    for i, p in ipairs(poly) do out[i] = { x = p.x + dx, y = p.y + dy } end
    return out
end

-- the gloss: a thin white line just inside the tab's top edge (along its big curve too), as short convex quads, brightest at the light's side (top left in both arts) and fading along
local function gloss_quads(x0, y0, x1, y1, rx, ry, rc, big_left, e, inset, th)
    local path = {}
    local hp = math.pi / 2
    local i0, i1 = inset, inset + th
    -- the line's two edges: the outline shrunk by `inset` and by `inset + th`
    local function edge(d)
        local pts = {}
        if big_left then
            arc(pts, x0 + rx, y0 + ry, rx - d, ry - d, math.pi + 0.35, 3 * hp, 10, e)
            arc(pts, x1 - rc - d, y0 + rc, math.max(0.5, rc - d), math.max(0.5, rc - d), 3 * hp, 3 * hp + 0.6, 2)
        else
            arc(pts, x0 + rc + d, y0 + rc + d, math.max(0.5, rc), math.max(0.5, rc), math.pi + 0.4, 3 * hp, 3)
            arc(pts, x1 - rx, y0 + ry, rx - d, ry - d, 3 * hp, 3 * hp + 0.9, 10, e)
        end
        return pts
    end
    local a, b = edge(i0), edge(i1)
    for i = 1, math.min(#a, #b) - 1 do
        local t = (i - 1) / math.max(1, #a - 2)
        path[#path + 1] = { poly = { a[i], a[i + 1], b[i + 1], b[i] }, alpha = math.floor(235 - 175 * t) }
    end
    return path
end

-- a tab's polygons for a box in screen px (kept per screen size: nothing made a frame)
local function tab_parts(x0, y0, x1, y1, rx, ry, rc, big_left, e, s)
    local h = y1 - y0
    local body = S.TabShape(x0, y0, x1, y1, rx, ry, rc, big_left, e)
    local sh = math.max(1, 0.9 * s)
    return {
        shadow = moved_poly(body, sh, sh),
        body = body,
        light1 = S.ClipAbove(body, y0 + 0.30 * h),
        light2 = S.ClipAbove(body, y0 + 0.16 * h),
        gloss = gloss_quads(x0, y0, x1, y1, rx, ry, rc, big_left, e, math.max(1, 0.9 * s), math.max(1, 1.1 * s)),
    }
end

local function poly(p, r, g, b, a)
    if #p < 3 or not surface.DrawPoly then return end            -- (GMod always has it; a stand-in without it draws no tab)
    surface.SetDrawColor(r, g, b, a)
    surface.DrawPoly(p)
end

local function paint_tab(T)
    if draw and draw.NoTexture then draw.NoTexture() end
    local P, L, R = S.TAB_PINK, S.TAB_LIGHT, S.TAB_RIM
    poly(T.shadow, R[1], R[2], R[3], 235)
    poly(T.body, P[1], P[2], P[3], 255)
    poly(T.light1, L[1], L[2], L[3], 90)
    poly(T.light2, L[1], L[2], L[3], 90)
    for _, q in ipairs(T.gloss) do poly(q.poly, 255, 255, 255, q.alpha) end
end

-- the tabs' shapes on this layout (made again only when the screen's size or placing changes)
local function tabs_for(st, m)
    local key = string.format("%.3f %.3f %.4f %.4f", m.ox, m.oy, m.sx, m.sy)
    local c = st.barTabs
    if c and c.key == key then return c end
    local B = S.BAR
    local function one(r, curve, big_left)
        local x0, y0, x1, y1 = px(m, r[1]), py(m, r[2]), px(m, r[3]), py(m, r[4])
        return tab_parts(x0, y0, x1, y1, curve[1] * m.sx, curve[2] * m.sy, B.corner * m.sy, big_left, curve[3], m.sy)
    end
    c = { key = key, y = one(B.tab_y, B.curve_y, true), d = one(B.tab_d, B.curve_d, false) }
    st.barTabs = c
    return c
end
S.TabsFor = tabs_for

-- the bar's own parts over the game's bar (Design R). Returns how each text was drawn (for the self-check line)
local COLS = {}
local function colour(c)
    local k = c[1] * 65536 + c[2] * 256 + c[3]
    local o = COLS[k]
    if not o then
        o = Color(c[1], c[2], c[3], 255)
        COLS[k] = o
    end
    return o
end
function S.PaintBar(st, m)
    local B = S.BAR
    local how = {}
    local tabs = tabs_for(st, m)
    local tc, lc = colour(S.TAB_TEXT), colour(S.LABEL)
    local orim = { math.max(1, math.floor(0.75 * m.sy + 0.5)), S.LABEL_OUTLINE[1], S.LABEL_OUTLINE[2], S.LABEL_OUTLINE[3] }
    local function text(t, spec, col, outline)
        how[#how + 1] = t .. " " .. S.BarText(t, "bar_label", spec[3] * m.sy, col, px(m, spec[1]), py(m, spec[2]), outline, spec[4] * m.sy)
    end
    if cvb.upgrades:GetBool() then
        paint_tab(tabs.y)
        text("Y Button", B.text_y, tc, 0)
        text("Upgrades", B.lbl_up, lc, orim)
    end
    if GSA1.CharSelect.cv.skins:GetBool() then
        paint_tab(tabs.d)
        text("D-Pad Up/Down", B.text_d, tc, 0)
        text("Skins", B.lbl_skins, lc, 0)
    end
    local i, n = S.SkinOf(st, st.slot)
    text(i .. "/" .. n, B.counter, tc, math.max(2, math.floor(1.25 * m.sy + 0.5)))
    return how
end

-- how far a cut draw reached (S.KeepEnds' least and greatest x)
local function reached(lo, hi)
    if lo and hi then return string.format("x %g and %g", lo, hi) end
    return string.format("x %g", lo or hi or 0)
end

-- the self-check lines of the bar, once per open (the owner's next log says whether the game's screen gave the filters what they need): the ball found and its colour (once for each skin shown: a step to
-- Metal Sonic or Mecha Sonic is said too), the ends cut (each draw cut, and how far it reached), the tabs and texts
local function self_check(st, m, how)
    st.barSaid = st.barSaid or { frames = 0, balls = {} }
    local said = st.barSaid
    said.frames, said.balls = said.frames + 1, said.balls or {}
    local f = st.barFrame
    if f and f.paint ~= (st.barPaint or 0) then f = nil end         -- (nothing of this paint's: the filters saw no draw)
    if f and f.ball then
        local e, shown = S.SkinEntry(st, st.slot)
        shown = tostring(shown)
        local by = said.balls[shown]
        if not by then
            by = {}
            said.balls[shown] = by
        end
        local hw = tostring(f.ballHow)
        if not by[hw] then
            by[hw], said.ball = true, true
            local t = f.ballTint
            log("bar: the support ball is quad %d of %d of the game's draw %d (%s): %s for %s (%s)", f.ballQuad or 0, f.ballOf or 0, f.ballDraw or -1, tostring(f.ballDrawName),
                t and string.format("%d %d %d", t[1], t[2], t[3]) or "the game's red", shown, hw)
        end
    elseif not said.ball and said.frames == 30 then
        said.ball = true
        log("bar: the support ball was NOT found on the game's screen (no 50 x 50 sphere at 128, 418 in 30 frames): it keeps the game's red")
    end
    if not said.ends and f and f.cuts then
        said.ends = true
        local parts = {}
        for _, c in ipairs(f.cuts) do parts[#parts + 1] = string.format("%d vertices of %s (they reached %s)", c.n, tostring(c.name), reached(c.lo, c.hi)) end
        log("bar: the bar's ends kept to the game's picture, cut at x 0 and 640: %s", table.concat(parts, "; "))
    elseif not said.ends and said.frames == 30 then
        said.ends = true
        log("bar: no bar end reached outside x 0 .. 640 in 30 frames (nothing cut)")
    end
    if how and not said.texts then
        local pics, all = 0, #how
        for _, h in ipairs(how) do if string.find(h, " picture$") then pics = pics + 1 end end
        if pics == all or said.frames == 120 then
            said.texts = true
            log("bar: drawn at %d x %d (the game's px x%.2f): %d tab shapes; %s", m.W or 0, m.H or 0, m.sy or 0, (cvb.upgrades:GetBool() and 1 or 0) + (GSA1.CharSelect.cv.skins:GetBool() and 1 or 0),
                table.concat(how, ", "))
        end
    end
end

-- THE OVERLAY: the end of both paints. m: the game screen's layout (nil: Design S)
function S.Overlay(st, m, W, H)
    local U = GSA1.UpgradeModels
    if st.picked and st.panel_up and U and U.PanelClose then U.PanelClose(st, "the pick") end
    if st.design == "R" and m then
        local how = cvb.bar:GetBool() and S.PaintBar(st, m) or nil
        self_check(st, m, how)
        st.barPaint = (st.barPaint or 0) + 1
    end
    if U and U.PanelPaint and (st.panel_up or st.panelFade) then
        if not m then
            st.mS = S.Layout(W, H, false, st.mS or {})          -- (Design S: the 4:3 box of the screen, kept: nothing a frame)
            m = st.mS
        end
        U.PanelPaint(st, m, W, H)
    end
end

-- the Upgrades panel may open now: the option, idle, a character with upgrades
function S.PanelAllowed(st)
    return cvb.upgrades:GetBool() and idle(st) and #S.UpgradeList(st) > 0 and GSA1.UpgradeModels ~= nil and GSA1.UpgradeModels.PanelOpen ~= nil
end

-- THE PAD FILTER, first in both designs' pad step. Design R: pressed = the edges of the pad, held = the pad; returns pressed (unchanged: step_r's own lines use it). Design S: returns the edges with the panel's
-- buttons taken out while it is up, and the stick's x (0 while it is up)
function S.PadFilter(st, pressed, held, sx, sy)
    local U = GSA1.UpgradeModels
    -- a panel closed last frame: gone now (it stayed up for the frame it closed in, so step_r's masking line kept that frame's buttons from the game; U.PanelClose put what was held into st.mask)
    if st.panelEnding then st.panelEnding, st.panel_up = nil, false end
    if st.picked then
        if st.panel_up and U and U.PanelClose then U.PanelClose(st, "the pick") end
        return pressed, sx
    end
    if st.panel_up and U then
        U.PanelPad(st, pressed, sy)
        if st.design == "S" then return band(pressed, bnot(S.PANEL_PAD)), 0 end
        return pressed, sx
    end
    if band(pressed, S.PAD_Y) ~= 0 and S.PanelAllowed(st) then
        U.PanelOpen(st, "Y")
        if st.design == "S" then return band(pressed, bnot(S.PANEL_PAD)), 0 end
        return pressed, sx
    end
    -- Up and Down step the skins only while the screen is idle; on Design R they are still forwarded (step_r's own lines: RM.5, F2 MEASURED)
    if GSA1.CharSelect.cv.skins:GetBool() and idle(st) then
        if band(pressed, S.PAD_UP) ~= 0 then S.StepSkin(st, 1) elseif band(pressed, S.PAD_DOWN) ~= 0 then S.StepSkin(st, -1) end
    end
    return pressed, sx
end

-- THE KEY FILTER, first in both designs' key handlers: true = taken here. Never the keyboard's pick (Enter, keypad Enter, Space) nor a key S.IsOwnKey names (RX.1); Escape never comes here (S.OnKey)
function S.KeyFilter(st, code)
    if K_PICK[code] or S.IsOwnKey(code) then return false end
    local U = GSA1.UpgradeModels
    if st.picked then return false end
    if st.panel_up and U then
        if code == K_UP or code == K_W then U.PanelMove(st, -1)
        elseif code == K_DOWN or code == K_S then U.PanelMove(st, 1)
        elseif code == K_E or code == K_RIGHT or code == K_D then U.PanelCycle(st)
        elseif code == K_R then U.PanelAll(st, true)
        elseif code == K_L then U.PanelAll(st, false)
        elseif code == K_BACK or code == K_U then U.PanelClose(st, "the key")
        end
        return true                     -- (every other key waits while the panel is up: the ring behind it does not move)
    end
    if code == K_U and S.PanelAllowed(st) then
        U.PanelOpen(st, "U")
        return true
    end
    if (code == K_UP or code == K_W or code == K_DOWN or code == K_S) and GSA1.CharSelect.cv.skins:GetBool() and idle(st) then
        S.StepSkin(st, (code == K_UP or code == K_W) and 1 or -1)
        return true
    end
    return false
end

-- the game px of a screen point (Design R's layout)
local function game_xy(st, mx, my, W, H)
    local m = S.Layout(W, H, GSA1.CharSelect.cv.wide:GetBool(), st.mB or {})
    st.mB = m
    return (mx - m.ox) / m.sx, (my - m.oy) / m.sy, m
end
local function inside(x, y, r, pad)
    pad = pad or 0
    return x >= r[1] - pad and x <= r[3] + pad and y >= r[2] - pad and y <= r[4] + pad
end

-- THE MOUSE FILTER, first in both designs' mouse handlers: true = taken here
function S.MouseFilter(st, code, mx, my, W, H)
    local U = GSA1.UpgradeModels
    if st.picked then return false end
    if st.panel_up and U then
        if code == M_RIGHT then
            U.PanelClose(st, "a right click")
        elseif code == M_LEFT then
            U.PanelClick(st, mx, my, W, H)
        end
        return true
    end
    if st.design ~= "R" or not cvb.bar:GetBool() then return false end
    local gx, gy, m = game_xy(st, mx, my, W, H)
    if S.SphereAt and S.SphereAt(st, mx, my, m) ~= nil then return false end      -- (a ring sphere there: the game's own click, as today)
    local B, half = S.BAR, S.BAR.ball_size / 2
    local ball_l = { B.ball_l[1] - half, B.ball_l[2] - half, B.ball_l[1] + half, B.ball_l[2] + half }
    local ball_r = { B.ball_r[1] - half, B.ball_r[2] - half, B.ball_r[1] + half, B.ball_r[2] + half }
    if code == M_LEFT and (inside(gx, gy, ball_l) or inside(gx, gy, B.tab_y)) and S.PanelAllowed(st) then
        U.PanelOpen(st, "a click")
        return true
    end
    if inside(gx, gy, ball_r) and GSA1.CharSelect.cv.skins:GetBool() and idle(st) then
        S.StepSkin(st, code == M_RIGHT and -1 or 1)
        return true
    end
    return false
end

-- the mouse wheel moves the panel's selection while it is up
function S.WheelFilter(st, delta)
    local U = GSA1.UpgradeModels
    if not (st.panel_up and U) then return false end
    U.PanelMove(st, (tonumber(delta) or 0) > 0 and -1 or 1)
    return true
end

-- a skin shown: its pictures are asked for (one a frame, PostRender: feat/cl_skinhud.lua)
function S.SkinShown(st, slot)
    local H, e = GSA1.SkinHud, S.SkinEntry(st, slot)
    if H and H.Want and e then H.Want(e) end
end
