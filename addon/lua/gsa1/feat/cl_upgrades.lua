-- G-SA1 upgrade models, the client part (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 3.2, 4.6 with RX.1, 6; the pure part is feat/sh_upgrades.lua, which says what the two switches are).
--   * The ConVars gsa1_upgrade_model_<name> (0 with the upgrade, 1 always shown, 2 never shown) and gsa1_upgrade_models_reset, each with its control (Q menu > Options > G-SA1 > Character, "Upgrade models").
--   * "Visible" reaches the game at once: libsa1's game option 5 (gsa1.CHAROPT.UPGRADE_MODELS) on your character and every follower of that kind, and on the 3D character of Character Select's circle
--     (gsa1.FrontendUpgradeModels); never a re-creation. "Active" is today's gsa1_upgrade_<name> and re-creates the character as today (cl_character.lua waits while Character Select is open).
--   * "CHOOSE YOUR UPGRADE", the panel of the owner's mockup on Character Select (opened by feat/cl_charselect_bar.lua): a green-to-yellow band slides in from the left, the rows fade in one after the other,
--     the selected one pulses with the game's own name curve. Every A, R and L writes the ConVars at once, so neither Start nor Escape has anything to save and neither path learns the panel exists.
GSA1 = GSA1 or {}
local U = GSA1.UpgradeModels
if not U then error("gsa1/feat/sh_upgrades.lua did not load: the upgrade models need it") end
local band = bit.band

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("upgrades", fmt, ...) end
end

-- the model ConVars, one per upgrade with a model (16: Ancient Light has none, so no ConVar and no combo for it; the owner's answer 16, "Default", select 4.0 D-2) --------------------------------------
U.cvm = U.cvm or {}
for _, u in ipairs(GSA1.UPGRADES or {}) do
    if not U.cvm[u.name] and not U.NO_MODEL[u.name] then
        U.cvm[u.name] = GSA1.ConVar("gsa1_upgrade_model_" .. u.name, 0, u.title .. "'s model: 0 = with the upgrade (the game), 1 = always shown (even without the ability), 2 = never shown (the ability stays). "
            .. "At once, no re-creation", 0, 2)
    end
end

local function set_cv(cv, name, v)
    if cv and cv.SetInt then
        cv:SetInt(v)
    else
        RunConsoleCommand(name, tostring(v))
    end
end

-- an upgrade's two switches now: active (boolean), model (0..2)
function U.Get(name)
    local a = GSA1.cv and GSA1.cv["up_" .. name]
    local m = U.cvm[name]
    return a ~= nil and a:GetBool() or false, m and m:GetInt() or 0
end

function U.StateNow(name)
    local a, m = U.Get(name)
    return U.StateOf(a, m, name)
end

-- writes a state into the two ConVars
function U.SetState(name, state)
    local a, m = U.ConVarsOf(state)
    set_cv(GSA1.cv and GSA1.cv["up_" .. name], "gsa1_upgrade_" .. name, a)
    if not U.NO_MODEL[name] then set_cv(U.cvm[name], "gsa1_upgrade_model_" .. name, m) end
end

-- the game option's value for a kind now
function U.Value(kind)
    return U.OptionValue(kind, U.Get)
end

-- applying "visible" ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
U.said = U.said or {}
local function can()
    return gsa1 and gsa1.SetGameOption and gsa1.CHAROPT and gsa1.CHAROPT.UPGRADE_MODELS
end

-- a character of yours or a follower: the value of its kind, once per change (C.upgdValue). false: nothing to do or the module cannot
function U.ApplyTo(C, force)
    if not (C and C.id and can()) then return false end
    if C.def and C.def.noUpgrades then return false end
    local v = U.Value(C.kind)
    if C.upgdValue == v and not force then return true end
    local ok, err, code = gsa1.SetGameOption(C.id, gsa1.CHAROPT.UPGRADE_MODELS, v)
    if ok then
        C.upgdValue = v
        return true
    end
    C.upgdValue = v                      -- (refused: not asked again until the value changes)
    if not U.said[tostring(code)] then
        U.said[tostring(code)] = true
        log("the models of the upgrades: refused: %s (%s)", tostring(err), tostring(code))
    end
    return false
end

-- the 3D characters on Character Select's circle (its own world: the menu's characters run their own Main, select 4.3.3). They hold no upgrade there, so they get the VISIBLE bits
-- themselves (U.FrontendValue), never the character's "0 = the game"
U.FRONTEND_KINDS = { 0, 2, 3, 5, 7, 6 }
function U.ApplyFrontend()
    if not (gsa1 and gsa1.FrontendUpgradeModels) then return false end
    local S = GSA1.CharSelect
    if not (S and S.st and S.st.design == "R") then return false end
    for _, k in ipairs(U.FRONTEND_KINDS) do
        local ok, err, code = gsa1.FrontendUpgradeModels(k, U.FrontendValue(k, U.Get))
        if not ok and not U.said["fe" .. tostring(code)] then
            U.said["fe" .. tostring(code)] = true
            log("the models of the upgrades on Character Select: refused: %s (%s)", tostring(err), tostring(code))
        end
    end
    return true
end

function U.ApplyAll()
    U.ApplyTo(GSA1.Char)
    for _, F in ipairs(GSA1.Followers and GSA1.Followers.list or {}) do
        if not F.removed then U.ApplyTo(F) end
    end
    U.ApplyFrontend()
end

hook.Add("GSA1CharacterCreated", "gsa1_upgrades", function(C)
    if C then
        C.upgdValue = nil
        U.ApplyTo(C)
    end
end)
-- a follower made since (no hook of its own): looked at twice a second, nothing a frame
U.nextLook = 0
hook.Add("Think", "gsa1_upgrades", function()
    local now = SysTime()
    if now < U.nextLook then return end
    U.nextLook = now + 0.5
    for _, F in ipairs(GSA1.Followers and GSA1.Followers.list or {}) do
        if not F.removed and F.upgdValue == nil then U.ApplyTo(F) end
    end
end)
if cvars and cvars.AddChangeCallback then
    for _, u in ipairs(GSA1.UPGRADES or {}) do
        if U.cvm[u.name] then cvars.AddChangeCallback("gsa1_upgrade_model_" .. u.name, function() U.ApplyAll() end, "gsa1_upgrades") end
        cvars.AddChangeCallback("gsa1_upgrade_" .. u.name, function() U.ApplyAll() end, "gsa1_upgrades_models")
    end
end

-- every model with its upgrade (the page's button)
function U.Reset()
    for _, u in ipairs(GSA1.UPGRADES or {}) do
        if U.cvm[u.name] then set_cv(U.cvm[u.name], "gsa1_upgrade_model_" .. u.name, 0) end
    end
    log("every model with its upgrade again")
end
if concommand and concommand.Add then
    concommand.Add("gsa1_upgrade_models_reset", function() U.Reset() end, nil, "G-SA1: every upgrade's model with its upgrade again (gsa1_upgrade_model_<name> 0)")
end

-- Q menu > Options > G-SA1 > Character, after the upgrades (the owner's rule: every option on the Q menu)
function U.BuildOptions(panel)
    panel:Help("Upgrade models")
    panel:ControlHelp("Which model each upgrade shows, apart from whether the character has it (the boxes above). \"With the upgrade\" is the game. Also on Character Select: Y (or U) opens Choose Your Upgrade.")
    local shown = {}
    for _, c in ipairs(GSA1.ListedCharacters and GSA1.ListedCharacters() or {}) do
        local ups = (c.form or shown[c.kind] or c.noUpgrades) and {} or GSA1.UpgradesOf(c.kind)
        shown[c.kind] = true
        for _, u in ipairs(ups) do
            if not U.NO_MODEL[u.name] then
                local combo = panel:ComboBox(u.title .. " model", "gsa1_upgrade_model_" .. u.name)
                if combo and combo.AddChoice then
                    local now = U.cvm[u.name] and U.cvm[u.name]:GetInt() or 0
                    combo:AddChoice("with the upgrade", 0, now == 0)
                    combo:AddChoice("always shown", 1, now == 1)
                    combo:AddChoice("never shown", 2, now == 2)
                    combo.OnSelect = function(_, _, _, data) RunConsoleCommand("gsa1_upgrade_model_" .. u.name, tostring(data)) end
                end
                if U.NOTES[u.name] then panel:ControlHelp(U.NOTES[u.name]) end
            end
        end
    end
    panel:Button("Every model with its upgrade", "gsa1_upgrade_models_reset")
end
if GSA1.AddCharacterOption then GSA1.AddCharacterOption(10, "upgrade_models", U.BuildOptions) end

-- CHOOSE YOUR UPGRADE ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- st: Character Select's open state (feat/cl_charselect.lua). st.panel_up, st.upSel, st.upList, st.upT0; st.panelFade while it slides out
function U.PanelOpen(st, how)
    local S = GSA1.CharSelect
    local list = S.UpgradeList(st)
    if #list == 0 then return false end
    st.panel_up, st.panelEnding, st.panelFade = true, nil, nil
    st.upList, st.upSel, st.upT0, st.upStickWas = list, st.upSel and math.min(st.upSel, #list) or 1, SysTime(), 0
    log("Choose Your Upgrade open (%s): %d upgrades", tostring(how), #list)
    return true
end

-- closes it (the screen stays). It stays up for the rest of this frame (the pad's masking line in step_r keeps that frame's buttons from the game); what the pad holds now reaches the game only after it is
-- released (st.mask, step_r's own rule for what was held at the open)
function U.PanelClose(st, why)
    if not st.panel_up or st.panelEnding then return false end
    st.panelEnding = true
    st.panelFade, st.upClosed = true, SysTime()
    local S = GSA1.CharSelect
    if st.design == "R" then
        st.mask = bit.bor(st.mask or 0, band(st.padWas or 0, bit.bor(S.PAD_A, S.PAD_B, S.PAD_BACK, S.PAD_Y or 0x8000, S.PAD_UP, S.PAD_DOWN)))
    end
    log("Choose Your Upgrade closed (%s)", tostring(why))
    return true
end

function U.PanelMove(st, dir)
    local n = #(st.upList or {})
    if n == 0 then return end
    st.upSel = ((st.upSel or 1) - 1 + dir) % n + 1
end

function U.PanelCycle(st, k)
    local u = st.upList and st.upList[k or st.upSel or 1]
    if not u then return end
    local s = U.Next(U.StateNow(u.name), u.name)
    U.SetState(u.name, s)
    log("%s: %s", u.title, s)
end

-- R: every row active and visible; L: every row disabled entirely
function U.PanelAll(st, on)
    for _, u in ipairs(st.upList or {}) do U.SetState(u.name, on and "on" or "off") end
    log("every upgrade %s", on and "active and visible" or "disabled entirely")
end

-- the pad while it is up (feat/cl_charselect_bar.lua S.PadFilter): the edges, and the stick's y (past 0.5, one step a push)
function U.PanelPad(st, pressed, sy)
    local S = GSA1.CharSelect
    if band(pressed, S.PAD_B + S.PAD_BACK + S.PAD_Y) ~= 0 then return U.PanelClose(st, "the pad") end
    if band(pressed, S.PAD_UP) ~= 0 then U.PanelMove(st, -1) end
    if band(pressed, S.PAD_DOWN) ~= 0 then U.PanelMove(st, 1) end
    local d = ((tonumber(sy) or 0) >= 0.5 and -1) or ((tonumber(sy) or 0) <= -0.5 and 1) or 0
    if d ~= 0 and d ~= st.upStickWas then U.PanelMove(st, d) end
    st.upStickWas = d
    if band(pressed, S.PAD_A) ~= 0 then U.PanelCycle(st) end
    if band(pressed, S.PAD_RB + S.PAD_RT) ~= 0 then U.PanelAll(st, true) end
    if band(pressed, S.PAD_LB + S.PAD_LT) ~= 0 then U.PanelAll(st, false) end
    return true
end

-- the rows' places, in game px (k from 1)
function U.RowPlace(k, n)
    local L = U.LAYOUT
    local pitch, scale = U.Layout(n)
    local y = L.status_y + pitch * (k - 1)
    return y, L.status_h * scale, y + (L.name_y - L.status_y) * scale, L.name_h * scale, scale
end

-- a click: on a row, that row selected and stepped
function U.PanelClick(st, mx, my, W, H)
    local S = GSA1.CharSelect
    local m = st.F and st.m and st.m.sx and st.m or S.Layout(W, H, st.design == "R" and S.cv.wide:GetBool() or false, {})
    local gx, gy = (mx - m.ox) / m.sx, (my - m.oy) / m.sy
    local n = #(st.upList or {})
    if gx > U.BAND.click_to then return false end
    for k = 1, n do
        local sy, sh, ny, nh = U.RowPlace(k, n)
        if gy >= sy - 2 and gy <= ny + nh + 2 then
            st.upSel = k
            U.PanelCycle(st, k)
            return true
        end
    end
    return false
end

-- drawing ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function ease_out(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) * (1 - t) * (1 - t)
end

local COL = {}
local function col(r, g, b)
    local k = r * 65536 + g * 256 + b
    local c = COL[k]
    if not c then
        c = Color(r, g, b, 255)
        COL[k] = c
    end
    return c
end

-- a text at (x, y centre) in screen px, left aligned, scaled by s about its left edge; returns its width. Through feat/cl_text.lua's pictures, else its font
local function text_at(text, element, size, c, x, y, s, alpha, outline, dim)
    local Tx = GSA1.Text
    size = math.max(8, math.floor(size + 0.5))
    local pic = Tx and Tx.Get and Tx.Get(text, element, size, c, outline)
    local a = math.floor(255 * alpha)
    if pic and pic.mat and pic.u1 then
        -- (1.0.0-beta1a, b1a-text's API: the picture is a part of an atlas page; T.DrawPic draws that part, with its UVs, in this colour: grey 153 dims a disabled row)
        local w, h = pic.w * s, pic.h * s
        local v = dim and 153 or 255
        if Tx.DrawPic then
            Tx.DrawPic(pic, math.floor(x), math.floor(y - h / 2), w, h, v, v, v, a)
        else
            surface.SetDrawColor(v, v, v, a)
            surface.SetMaterial(pic.mat)
            surface.DrawTexturedRectUV(math.floor(x), math.floor(y - h / 2), w, h, pic.u0, pic.v0, pic.u1, pic.v1)
        end
        return w
    end
    local font = Tx and Tx.FontFor and Tx.FontFor(element, size) or "DermaLarge"
    local cc = Color(dim and math.floor(c.r * 0.6) or c.r, dim and math.floor(c.g * 0.6) or c.g, dim and math.floor(c.b * 0.6) or c.b, a)
    if draw.SimpleTextOutlined then
        draw.SimpleTextOutlined(text, font, x, y, cc, 0, 1, math.max(1, tonumber(outline) or 1), Color(0, 0, 0, a))
    else
        draw.SimpleText(text, font, x, y, cc, 0, 1)
    end
    if not (surface.SetFont and surface.GetTextSize) then return size * 0.6 * #text end
    surface.SetFont(font)
    local w = surface.GetTextSize(text)
    return (tonumber(w) or 0)
end

-- the name's colour of an upgrade on the slot that shows it, with the skin it shows (nil: the character itself): its own colour, else the skin's or the slot's character's (the owner's answers 18, 22
-- and 29: sh_upgrades.lua U.COLORS, U.NameHex); never white
function U.NameColor(u, slot, skin)
    local r, g, b = U.RGB(U.NameHex(u and u.name, slot, skin))
    return col(r or 0, g or 0x53, b or 0xFA)
end

-- the pulse's ring: the front end's own (gsa1.FrontendState's ring, so it beats with the name under the character), else G-SA1's clock at the game's 0x5B0 a frame
function U.Ring(st)
    local r = st.state and tonumber(st.state.ring)
    if r then return r end
    return (SysTime() * 60 * U.RING_STEP) % 65536
end

-- THE BAND (1.0.0-beta1a, lane b1a-bar; the owner's 10.png and 12.png at 1280 x 960, MEASURED): dark green 207A01 at the picture's left edge to yellow-green BDF604 at game x 200 (U.LAYOUT.from / to),
-- solid to 214, then fading out as (1 - t)^4 over 214 .. 500. Fix run (fix-bar): the fade fitted to the mockup's alpha MEASURED against the same sky in 9.png (rows y 8 .. 55 of 10.png, all three
-- channels; game x: alpha) 220: 0.91, 240: 0.70, 260: 0.49, 280: 0.35, 300: 0.23, 320: 0.15, 340: 0.09, 360: 0.06, 380: 0.04, 400: 0.02, 420: 0.01, within 0.03 at every point (b1a-bar's first fade,
-- (1 - t)^2 over 210 .. 380, was half the mockup's from x 320 on and none from 380; beta 1's straight fade to 400 left 0.63 at 280). Its last strip of alpha 1 / 255 or more ends at game x 440 (seen_to:
-- the slide's reach and the log's end); a click past game x 380 (click_to, where the mockup's alpha falls under 0.05) is not on a row. From the top to game y 324 (MEASURED 326). On a screen wider than
-- 4:3 the green starts at the SCREEN's left edge and turns yellow-green where the mockup has it (beta 1 filled the side bar with the flat dark green, the owner's 15.jpg; a matter of taste on the owner's
-- checklist). The slide moves it in from beyond the screen's left edge (U.LAYOUT.slide), the rows with it
U.BAND = { ramp_to = 200, solid_to = 214, fade_to = 500, power = 4, step = 2, seen_to = 440, click_to = 380 }
function U.BandAlpha(x)
    local B = U.BAND
    if x <= B.solid_to then return 1 end
    if x >= B.fade_to then return 0 end
    return (1 - (x - B.solid_to) / (B.fade_to - B.solid_to)) ^ B.power
end

-- one strip of the band, screen px [xa, xb) shifted by `shift`, clipped at the screen's left edge
local function strip(xa, xb, shift, y0, h, r, g, b, a)
    local x0, x1 = math.floor(xa + shift + 0.5), math.floor(xb + shift + 0.5)
    if x0 < 0 then x0 = 0 end
    if x1 <= x0 or a <= 0 then return 0 end
    surface.SetDrawColor(r, g, b, a)
    surface.DrawRect(x0, y0, x1 - x0, h)
    return 1
end

-- the band on layout m, moved by `shift` screen px, at `fade` (0..1). Returns its right end on the screen (px, unshifted) and the strips drawn
function U.PaintBand(m, shift, fade)
    local S, L, B = GSA1.CharSelect, U.LAYOUT, U.BAND
    local y0 = math.floor(S.PlaceY(m, 0) + 0.5)
    local h = math.floor(S.PlaceY(m, L.band_h) + 0.5) - y0
    local xr, xs, xe = S.PlaceX(m, B.ramp_to), S.PlaceX(m, B.solid_to), S.PlaceX(m, B.seen_to)
    local n = 0
    -- the ramp from the screen's left edge: a strip every 2 game px of the box's scale
    local steps = math.max(8, math.ceil(xr / (B.step * m.sx)))
    for i = 0, steps - 1 do
        local t = (i + 0.5) / steps
        n = n + strip(xr * i / steps, xr * (i + 1) / steps, shift, y0, h, math.floor(L.from[1] + (L.to[1] - L.from[1]) * t + 0.5),
            math.floor(L.from[2] + (L.to[2] - L.from[2]) * t + 0.5), math.floor(L.from[3] + (L.to[3] - L.from[3]) * t + 0.5), math.floor(255 * fade + 0.5))
    end
    n = n + strip(xr, xs, shift, y0, h, L.to[1], L.to[2], L.to[3], math.floor(255 * fade + 0.5))
    for gx = B.solid_to, B.seen_to - B.step, B.step do          -- (past seen_to every strip rounds to alpha 0)
        local a = U.BandAlpha(gx + B.step / 2)
        n = n + strip(S.PlaceX(m, gx), S.PlaceX(m, gx + B.step), shift, y0, h, L.to[1], L.to[2], L.to[3], math.floor(255 * a * fade + 0.5))
    end
    return xe, n
end

-- the panel (S.Overlay calls it while it is up or sliding out). m: the game screen's layout
function U.PanelPaint(st, m, W, H)
    local S, L = GSA1.CharSelect, U.LAYOUT
    local now = SysTime()
    local reach = S.PlaceX(m, U.BAND.seen_to)            -- (the band's visible right end: a slide from beyond the screen's left edge moves it this far)
    local shift, fade = 0, 1
    if st.panelFade and not st.panel_up then
        local t = (now - (st.upClosed or now)) / L.close
        if t >= 1 then
            st.panelFade = nil
            return
        end
        shift, fade = -reach * ease_out(t), 1 - t
    elseif st.panelFade and st.panelEnding then
        shift = 0
    else
        shift = -reach * (1 - ease_out((now - (st.upT0 or now)) / L.slide))
    end
    local xe, strips = U.PaintBand(m, shift, fade)
    if st.upSaid ~= st.upT0 and shift == 0 then
        st.upSaid = st.upT0
        log("Choose Your Upgrade: the band from the screen's left edge to x %d px of %d (game x %d, the mockup's fade), bottom at y %d px, %d strips; %d rows from x %d px", math.floor(xe + 0.5), W or 0,
            U.BAND.seen_to, math.floor(S.PlaceY(m, L.band_h) + 0.5), strips, #(st.upList or {}), math.floor(S.PlaceX(m, L.x) + 0.5))
    end
    -- the title, then the rows (each fading in after the one above)
    local list = st.upList or {}
    local n = #list
    local white, grey = col(L.white[1], L.white[2], L.white[3]), col(L.grey[1], L.grey[2], L.grey[3])
    local ol = math.max(1, math.floor(2 * m.sy + 0.5))
    local tsize = L.title_h * m.sy * 1.35
    text_at("CHOOSE YOUR UPGRADE", "upgrades_title", tsize, white, S.PlaceX(m, L.title_x) + shift, S.PlaceY(m, L.title_y + L.title_h / 2), 1, fade, ol)
    local t = now - (st.upT0 or now)
    local pulse = U.PulseScale(U.Ring(st))
    local skin = S.SkinEntry and S.SkinEntry(st, st.slot) or nil      -- (the shown skin: its name colour for an upgrade with none of its own)
    for k, u in ipairs(list) do
        local a = math.max(0, math.min(1, (t - L.fade_at - L.fade_each * (k - 1)) / L.fade)) * fade
        if st.panelFade and not st.panel_up then a = fade end
        if a > 0 then
            local sy, sh, ny, nh = U.RowPlace(k, n)
            local s = (k == st.upSel) and pulse or 1
            local active, model = U.Get(u.name)
            local state = U.StateOf(active, model, u.name)
            local vis = U.STATE[state].visible and not U.NO_MODEL[u.name]
            local x = S.PlaceX(m, L.x) + shift                  -- (the rows move with the band)
            local ssize, olr = sh * m.sy * 1.35, math.max(1, math.floor(ol * sh / L.status_h + 0.5))
            local yc = S.PlaceY(m, sy + sh / 2)
            local w1 = text_at("ACTIVE", "upgrades_status", ssize, active and white or grey, x, yc, s, a, olr)
            local w2 = text_at("/", "upgrades_status", ssize, white, x + w1, yc, s, a, olr)
            text_at("VISIBLE", "upgrades_status", ssize, vis and white or grey, x + w1 + w2, yc, s, a, olr)
            text_at(string.upper(u.title), "upgrades_name", nh * m.sy * 1.35, U.NameColor(u, st.slot, skin), x, S.PlaceY(m, ny + nh / 2), s, a, olr, state == "off")
        end
    end
    -- Super Sonic (Vs. Perfect Chaos) uses Sonic's (select 4.6)
    if st.slot == S.SUPER_SLOT and n > 0 then
        text_at("Super Sonic uses Sonic's upgrades", "upgrades_status", 13 * m.sy * 1.35, white, S.PlaceX(m, L.x) + shift, S.PlaceY(m, L.band_h - 14), 1, fade, ol)
    end
end
