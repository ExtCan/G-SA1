-- G-SA1 Character Select's bottom bar, skins on Up / Down, and the seams of the Upgrades panel (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 4.4, 4.5, 4.6, 4.9 with RX.1; the owner's mockup,
-- rounds plan 14.1bj). feat/cl_charselect.lua calls these through its four seams (S.DrawFilter in paint_2d, S.Overlay at the end of both paints, S.PadFilter / S.KeyFilter / S.MouseFilter first in each design's
-- input, S.WheelFilter in S.OnWheel); every one is optional there, so without this file the screen is 0.9.9g's. The game's screen, its code and its events never change: the bar is drawn over the game's own
-- bar or in place of one of its draws (the support ball: the game's left sphere with other vertex colours; a skin's name and nameplate: the skin's pictures on the game's own vertices, UVs and colours, so
-- they pulse, fade and grey exactly as the game's).
-- THE PICK PATH STAYS 0.9.9g's (RX.1): no filter here ever takes Start, Escape, Enter, keypad Enter, Space or a key S.IsOwnKey names; with the Upgrades panel up the pad gives the game Start alone
-- (cl_charselect.lua step_r), Design S's A, B, Back, Y, the D-pad and the shoulders are taken out of the edges (so Start alone reaches its pick line), and nothing goes into events_r: the panel closes the
-- frame this file sees st.picked.
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

-- the bar's places on the game's 640 x 480 screen (the owner's 9.webp, MEASURED: select 4.4; the spheres MEASURED on the harness, LANDING.md C)
S.BAR = {
    ball_l = { 128, 418 }, ball_r = { 504, 418 }, ball_size = 50, ball_tol = 3,
    tab_y = { 37, 393, 97, 418 }, tab_d = { 516, 361, 592, 389 },
    lbl_up = { 35, 422, 98, 440 }, lbl_skins = { 540, 392, 590, 412 },
    counter_h = 20,
}
S.TAB_PINK, S.TAB_LIGHT, S.TAB_RIM = { 255, 12, 255 }, { 255, 101, 255 }, { 61, 0, 56 }     -- the owner's 13.png / 14.png
S.LABEL_OUTLINE = { 0, 40, 150 }
-- the support ball by upgrade_model_compatibility (the game's own red for none)
S.BALL = { full = { 0, 224, 0, tint = true }, partial = { 255, 208, 0, tint = true }, none = { 255, 0, 0, tint = true } }

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

-- the support ball's colour for the shown entry (nil: the game's red: a character without upgrades)
function S.BallTint(st)
    if #S.UpgradeList(st) == 0 then return nil end
    local e = S.SkinEntry(st, st.slot)
    return S.BALL[e and e.upgrade_model_compatibility or "full"] or S.BALL.none
end

-- the game's 640 x 480 box of a draw's vertices (nil: none)
local function game_box(st, D, k)
    local V = st.scr and st.scr.v
    if not V then return nil end
    local first, count = D[k + 2], D[k + 3]
    if not (first and count) or count < 3 or count > 6 then return nil end
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for v = first, first + count - 1 do
        local o = v * 8
        local x, y = V[o + 1], V[o + 2]
        if x < x0 then x0 = x end
        if x > x1 then x1 = x end
        if y < y0 then y0 = y end
        if y > y1 then y1 = y end
    end
    return x0, y0, x1, y1, V[first * 8 + 5], V[first * 8 + 6], V[first * 8 + 7]
end

-- is this draw the tinted base of the bar's sphere at (cx, cy)? (MEASURED, LANDING.md C: each bar sphere is a tinted base then a white shine, 50 x 50; the slot rings' spheres are 48 x 48)
function S.IsBarSphere(st, D, k, at)
    local x0, y0, x1, y1, r, g, b = game_box(st, D, k)
    if not x0 then return false end
    local B = S.BAR
    local w, h = x1 - x0, y1 - y0
    if math.abs(w - B.ball_size) > 1.5 or math.abs(h - B.ball_size) > 1.5 then return false end
    if math.abs((x0 + x1) / 2 - at[1]) > B.ball_tol or math.abs((y0 + y1) / 2 - at[2]) > B.ball_tol then return false end
    return not ((r or 0) >= 250 and (g or 0) >= 250 and (b or 0) >= 250)      -- (the shine is white)
end

-- THE DRAW FILTER (paint_2d): nil = as today; false = skip; a material = this one on the game's vertices; { r, g, b, tint = true } = these vertex colours (the game's alpha kept)
function S.DrawFilter(st, name, D, k)
    if not name then return nil end
    local bar = cvb.bar:GetBool()
    if bar and S.HiddenTexture(name) then return false end            -- File and Clear stay hidden while the bar is on: the counter sits where the Clear digits were
    local ln = string.lower(name)
    if cvb.names:GetBool() and st.skins then
        local H = GSA1.SkinHud
        for slot, i in pairs(st.skins) do
            if i > 1 then
                local base = S.SLOT_ENTRY[slot]
                if base and (ln == "m_" .. base or ln == "b_" .. base .. "_e" or ln == "b_" .. base) then
                    local id = S.SlotNames(slot)[i]
                    local mat = H and H.Material and H.Material(id, ln == "m_" .. base and "name" or "plate")
                    if mat then return mat end
                    return nil                  -- (not made yet: the game's own, no blank frame)
                end
            end
        end
    end
    if bar and S.IsBarSphere(st, D, k, S.BAR.ball_l) then return S.BallTint(st) end
    return nil
end

-- 2D helpers (screen px from game px through the panel's own placing, so they follow the 4:3 box and gsa1_charselect_wide) ------------------------------------------------------------------------------
local WHITE = Color(255, 255, 255, 255)
local function place_rect(m, r)
    local x0, y0 = S.PlaceX(m, r[1]), S.PlaceY(m, r[2])
    local x1, y1 = S.PlaceX(m, r[3]), S.PlaceY(m, r[4])
    return x0, y0, x1 - x0, y1 - y0
end

-- a text through feat/cl_text.lua (its picture, or its font until the picture is ready), centred on (x, y) in screen px
function S.BarText(text, element, size, col, x, y, outline)
    local Tx = GSA1.Text
    size = math.max(8, math.floor(size + 0.5))
    if Tx and Tx.Draw and Tx.Draw(text, element, size, col, x, y, 1, 1, outline) then return true end
    local font = Tx and Tx.FontFor and Tx.FontFor(element, size) or "DermaDefaultBold"
    local oc = type(outline) == "table" and Color(outline[2], outline[3], outline[4], 255) or Color(0, 0, 0, 255)
    local ow = type(outline) == "table" and outline[1] or outline
    if draw.SimpleTextOutlined then
        draw.SimpleTextOutlined(text, font, x, y, col, 1, 1, math.max(1, tonumber(ow) or 1), oc)
    else
        draw.SimpleText(text, font, x, y, col, 1, 1)
    end
    return false
end

-- a box with some top corners rounded (draw.RoundedBoxEx; a plain box where a game has none)
local function rbox(rad, x, y, w, h, c, tl, tr)
    if draw.RoundedBoxEx then return draw.RoundedBoxEx(rad, x, y, w, h, c, tl, tr, false, false) end
    surface.SetDrawColor(c.r, c.g, c.b, c.a)
    surface.DrawRect(x, y, w, h)
end

-- a pink tab: a box with one top corner rounded at about half its height, a lighter top band, a dark rim on the rounded side (the owner's 13.png / 14.png)
local function tab(m, r, right_round, text)
    local x, y, w, h = place_rect(m, r)
    local rad = math.floor(h / 2)
    local P, L, R = S.TAB_PINK, S.TAB_LIGHT, S.TAB_RIM
    rbox(rad, x, y, w, h, Color(P[1], P[2], P[3], 255), not right_round, right_round)
    rbox(rad, x, y, w, math.floor(h * 0.35), Color(L[1], L[2], L[3], 255), not right_round, right_round)
    local rim = math.max(1, math.floor(1.5 * m.sx + 0.5))
    surface.SetDrawColor(R[1], R[2], R[3], 255)
    surface.DrawRect(right_round and (x + w - rim) or x, y + rad, rim, h - rad)
    S.BarText(text, "bar_label", h * 0.62, WHITE, x + w / 2, y + h / 2 + h * 0.04, 0)
end

-- the bar's own parts over the game's bar (Design R)
function S.PaintBar(st, m)
    local B = S.BAR
    if cvb.upgrades:GetBool() then
        tab(m, B.tab_y, true, "Y Button")
        local x, y, w, h = place_rect(m, B.lbl_up)
        S.BarText("Upgrades", "bar_label", h * 1.15, WHITE, x + w / 2, y + h / 2, { math.max(1, math.floor(m.sy + 0.5)), S.LABEL_OUTLINE[1], S.LABEL_OUTLINE[2], S.LABEL_OUTLINE[3] })
    end
    if GSA1.CharSelect.cv.skins:GetBool() then
        tab(m, B.tab_d, false, "D-Pad Up/Down")
        local x, y, w, h = place_rect(m, B.lbl_skins)
        S.BarText("Skins", "bar_label", h * 1.25, WHITE, x + w / 2, y + h / 2, { math.max(1, math.floor(m.sy + 0.5)), S.LABEL_OUTLINE[1], S.LABEL_OUTLINE[2], S.LABEL_OUTLINE[3] })
    end
    local i, n = S.SkinOf(st, st.slot)
    S.BarText(i .. "/" .. n, "bar_label", B.counter_h * m.sy * 1.35, WHITE, S.PlaceX(m, B.ball_r[1]), S.PlaceY(m, B.ball_r[2]), math.max(2, math.floor(2 * m.sy + 0.5)))
end

-- THE OVERLAY: the end of both paints. m: the game screen's layout (nil: Design S)
function S.Overlay(st, m, W, H)
    local U = GSA1.UpgradeModels
    if st.picked and st.panel_up and U and U.PanelClose then U.PanelClose(st, "the pick") end
    if st.design == "R" and m and cvb.bar:GetBool() then S.PaintBar(st, m) end
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
