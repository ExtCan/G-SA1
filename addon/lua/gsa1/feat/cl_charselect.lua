-- G-SA1 Character Select (round 0.9.8; sadc docs/research/gsa1_098_plan.md 6.10 with its review R98.11, R98.13, R98.20, R98.22;
-- charsel098.md 6, gsa1_090_charselect.md 4 with its review RC2, RC8; owner: rounds plan 14.1i, 14.1j). The C menu's icon, the
-- menubar's G-SA1 menu, the command gsa1_charselect, a key you set and Start on the controller open one full-screen panel.
--   Design R (the module's feature "frontend": bind_frontend.cpp, libsa1's SA1_API_FRONTEND): the Dreamcast's own screen, run by
--   the game's own code from your disc in a private world; this file only places its draws, gives it the pad, plays its sounds
--   and turns its pick into a GSA1.Spawn.
--   Design S (this file, always there): seven buttons in the sphere colours and "Choose Your Buddy!". It is what the panel
--   shows whenever the module has no feature "frontend" or the game's screen fails (one log line says why).
-- Nothing pauses (the plan's A12): while the panel is open GSA1.InputBlocked gives your character a neutral pad, so it stands
-- (on a board it rides on until it stops) and can be hurt; your followers keep following it. A pick is a plain GSA1.Spawn.
-- Every way out ends in S.Close. A popup panel eats a key's bind, so the panel closes itself on the key, the bound command
-- and Escape (RC8). UNVERIFIED by any test: 3D in a vgui Paint, Escape and popup focus in Garry's Mod itself.
GSA1 = GSA1 or {}
local S = GSA1.CharSelect
if not S then error("gsa1/feat/sh_charselect.lua did not load: Character Select needs it") end

local band, bor, bnot = bit.band, bit.bor, bit.bnot

local KEY_MOVE_LEFT, KEY_MOVE_RIGHT = KEY_LEFT or 89, KEY_RIGHT or 91
local KEY_LETTER_A, KEY_LETTER_D = KEY_A or 11, KEY_D or 14
local KEY_MOVE_UP, KEY_LETTER_W = KEY_UP or 88, KEY_W or 33      -- 0.9.9f: a skin's Up, without a pad (the owner named the D-pad)
local KEY_PICK, KEY_PICK_PAD, KEY_PICK_SPACE = KEY_ENTER or 64, KEY_PAD_ENTER or 51, KEY_SPACE or 65
local KEY_GO_BACK, KEY_CLOSE = KEY_BACKSPACE or 66, KEY_ESCAPE or 70
local M_LEFT, M_RIGHT = MOUSE_LEFT or 107, MOUSE_RIGHT or 108

-- settings (every one has a control on the Character page, below) --------------------------------------------------------------
local cv = {
    key    = GSA1.ConVar("gsa1_charselect_key", 0, "Character Select: the key that opens and closes it (a key code; 0 = none; "
        .. "bind <key> gsa1_charselect works too)", 0, 255),
    pad    = GSA1.ConVar("gsa1_charselect_pad", 1, "Character Select: Start on the controller opens it (only while Start does "
        .. "nothing else, gsa1_pad_start 0)", 0, 1),
    dialog = GSA1.ConVar("gsa1_charselect_dialog", 0, "Character Select: show the game's Game / Instruction / Cancel dialog "
        .. "after a pick (0 = the pick plays the pose at once)", 0, 1),
    close  = GSA1.ConVar("gsa1_charselect_close", 0, "Character Select, after a pick: 0 = the game's 5-second pose (A skips it "
        .. "after the voice), 1 = switch when the voice starts", 0, 1),
    music  = GSA1.ConVar("gsa1_charselect_music", 1, "Character Select: play Choose Your Buddy! (your jukebox pauses and goes "
        .. "on afterwards)", 0, 1),
    file   = GSA1.ConVar("gsa1_charselect_file", 0, "Character Select: show File and Clear in the bottom bar (they mean nothing "
        .. "in Garry's Mod)", 0, 1),
    wide   = GSA1.ConVar("gsa1_charselect_wide", 0, "Character Select on wide screens: 0 = 4:3 with the sky continued, 1 = "
        .. "stretched", 0, 1),
    -- 0.9.9 (sadc docs/research/gsa1_099_plan.md 5.9, small099.md 3.2)
    qmark  = GSA1.ConVar("gsa1_charselect_qmark", 1, "The question mark's texture: 1 = the gold "
        .. "in the menu's own archive (sstx_body), 0 = as the Dreamcast draws it (the words Player Select mirrored over it)", 0, 1),
    -- 0.9.9f (the owner, rounds plan 14.1bd; sadc docs/research/metal099e.md 5.2)
    skins  = GSA1.ConVar("gsa1_charselect_skins", 1, "Character Select: Up on Sonic switches to Metal Sonic (off: Up does what it did)", 0, 1),
}
S.cv = cv

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("charselect", fmt, ...) end
end

S.st = nil                      -- the open panel's state (nil: closed)
S.keyWas, S.startWas = false, false
S.keyClosedAt = -1
S.stats = { opened = 0, picked = 0, cancelled = 0, faults = 0 }

function S.IsOpen()
    return S.st ~= nil
end

-- a panel of G-SA1's has the input: your character gets a neutral pad (cl_character.lua), the wheel and the faces wait
local prev_blocked = GSA1.InputBlocked
function GSA1.InputBlocked()
    if S.st ~= nil then return true end
    if prev_blocked then return prev_blocked() end
    return false
end

-- input helpers --------------------------------------------------------------------------------------------------------------
local function key_down(code)
    code = tonumber(code) or 0
    return code > 0 and input ~= nil and input.IsButtonDown ~= nil and input.IsButtonDown(code) == true
end

-- the controller's raw buttons and left stick while one is connected (GSA1.pad is live with a panel open: cl_character.lua's
-- Think polls it whatever GSA1.InputBlocked says)
local function pad_read()
    local p = GSA1.pad
    if p and p.connected then return tonumber(p.raw) or 0, tonumber(p.sx) or 0, tonumber(p.sy) or 0 end
    return 0, 0, 0
end

-- why the key or Start cannot open it now (typing, the console, the game menu, another panel), else nil
function S.Busy()
    if GSA1.InputBlocked and GSA1.InputBlocked() then return "a panel has the input" end
    if vgui.CursorVisible() then return "a menu opened" end
    if gui.IsGameUIVisible() then return "the game menu opened" end
    if gui.IsConsoleVisible and gui.IsConsoleVisible() then return "the console" end
    local ply = LocalPlayer()
    if IsValid(ply) and ply.IsTyping ~= nil and ply:IsTyping() == true then return "typing" end
    return nil
end

-- Start may open it: only while Start does nothing else (the Controller page) and the game has the focus (RC8)
function S.StartAllowed()
    local c = GSA1.cv and GSA1.cv.pad_start
    if not cv.pad:GetBool() or (c and c:GetInt() ~= 0) then return false end
    return system.HasFocus() == true
end

-- this key is the one that opens the panel: the option's, or a bind of the command (a popup eats the bind)
function S.IsOwnKey(code)
    local k = cv.key:GetInt()
    if k > 0 and code == k then return true end
    if not input then return false end
    if input.LookupKeyBinding and input.LookupKeyBinding(code) == "gsa1_charselect" then return true end
    local name = input.LookupBinding and input.LookupBinding("gsa1_charselect")
    if name and input.GetKeyCode and input.GetKeyCode(name) == code then return true end
    return false
end

-- the title of a slot's button
function S.SlotTitle(slot)
    if slot == S.SUPER_SLOT then return "Super Sonic" end
    local sk = S.st and S.st.skin and S.SLOT_SKINS[slot]
    if sk then
        local e = GSA1.CharacterByName and GSA1.CharacterByName(sk[1])
        return e and e.title or sk[1]
    end
    local c = GSA1.CharacterByName and GSA1.CharacterByName(S.SLOT_ENTRY[slot])
    return c and c.title or tostring(S.SLOT_ENTRY[slot])
end

-- the current character's slot, else the character setting's
function S.FirstSlot()
    local C = GSA1.Char
    if C and C.name then return S.SlotOf(C.name) end
    return S.SlotOf(GSA1.cv and GSA1.cv.character and GSA1.cv.character:GetString() or "sonic")
end

-- the entry a slot plays
function S.EntryName(slot)
    local sk = S.st and S.st.skin and S.SLOT_SKINS[slot]
    if sk then return sk[1] end
    return S.EntryOf(slot)
end

-- 0.9.9f: Up on a slot with skins: the skin on the spot, again the slot's own character. The game does not know (Up is still forwarded on Design R, where it does nothing while idle, MEASURED, and moves the
-- optional dialog's cursor: metal099e.md RM.5). A module without skins or a disc without the files: st.skin stays false and the log says why, so the pick cannot name a skin the screen did not show
function S.ToggleSkin(st)
    local sk = S.SLOT_SKINS[st.slot]
    if not sk then return false end
    local name, on = sk[1], not st.skin
    local K = GSA1.Skins
    local skin = K and K.SKINS[name]
    local ok, msg, code = true, nil, nil
    if not (skin and gsa1 and gsa1.SUPER and gsa1.SUPER.CREATE_SKIN and gsa1.FrontendSkin) then
        ok, msg = false, "this module has no skins"
    elseif st.design == "R" then
        if on then
            ok, msg, code = gsa1.FrontendSkin(K.DescOf(skin), K.Voiceless(skin))
        else
            ok, msg, code = gsa1.FrontendSkin(nil)
        end
    end
    if not ok then
        st.skin = false
        log("the skin %s: refused: %s (%s)", name, tostring(msg), tostring(code))
        return false
    end
    st.skin = on
    log("slot %d: %s", st.slot, on and name or tostring(S.EntryOf(st.slot)))
    return true
end

-- the line on a slot with skins; nil: none
function S.SkinHint(st)
    if not cv.skins:GetBool() then return nil end
    local sk = S.SLOT_SKINS[st.slot]
    if not sk then return nil end
    local e = GSA1.CharacterByName and GSA1.CharacterByName(sk[1])
    local o = GSA1.CharacterByName and GSA1.CharacterByName(S.EntryOf(st.slot))
    local title, own = e and e.title or sk[1], o and o.title or tostring(S.EntryOf(st.slot))
    if st.skin then return string.upper(title) .. "   (Up: " .. own .. ")" end
    return "Up: " .. title
end

-- music ----------------------------------------------------------------------------------------------------------------------
-- one source of the track whatever gsa1_sound_bgm says (RC2): the jukebox engine's channel 1, the game's music silenced, your
-- own jukebox paused where it is (cl_jukebox.lua P.SelectPlay / P.SelectStop). Without the jukebox: silent, the screen works.
function S.MusicStart(st, music)
    if st.music == music or not cv.music:GetBool() then return end
    local P = GSA1.JukeboxPlayer
    if not (P and P.SelectPlay) then return end
    local ok, why = P.SelectPlay(music)
    if ok then
        st.music = music
    elseif not st.musicSaid then
        st.musicSaid = true
        log("no music: %s", tostring(why))
    end
end

function S.MusicStop(st, fade)
    local P = GSA1.JukeboxPlayer
    if st.music and P and P.SelectStop then P.SelectStop(fade) end
    st.music = nil
end

-- Design S ---------------------------------------------------------------------------------------------------------------------
local COL_BACK = Color(6, 6, 24, 245)
local COL_SPHERE = Color(S.SPHERE[1], S.SPHERE[2], S.SPHERE[3], 255)
local COL_SELECTED = Color(S.SPHERE_SELECTED[1], S.SPHERE_SELECTED[2], S.SPHERE_SELECTED[3], 255)
local COL_TEXT = Color(255, 255, 255, 255)
local COL_HINT = Color(190, 190, 210, 255)
local font_h = nil
local function fonts(H)
    if font_h == H then return end
    font_h = H
    if not surface.CreateFont then return end
    surface.CreateFont("GSA1CharSelectTitle", { font = "Arial Black", size = math.max(18, math.floor(H / 16)), weight = 900,
        italic = true, antialias = true })
    surface.CreateFont("GSA1CharSelectButton", { font = "Arial", size = math.max(14, math.floor(H / 36)), weight = 700,
        antialias = true })
    surface.CreateFont("GSA1CharSelectHint", { font = "Arial", size = math.max(12, math.floor(H / 54)), weight = 500,
        antialias = true })
end

-- the skin line, through the text module when it has this font (feat/cl_text.lua: gsa1_text_fonts; off, or the font not found: exactly today's)
local function skin_line(hint, W, H, frac)
    local mid = TEXT_ALIGN_CENTER or 1
    local Tx = GSA1.Text
    local size = math.max(12, math.floor(H / 54))
    local font = Tx and Tx.FontFor and Tx.FontFor("charselect_skin", size) or "GSA1CharSelectHint"
    if not (Tx and Tx.Draw and Tx.Draw(hint, "charselect_skin", size, COL_TEXT, W / 2, H * frac, mid, mid)) then
        draw.SimpleText(hint, font, W / 2, H * frac, COL_TEXT, mid, mid)
    end
end

-- the buttons of Design S, in the panel's Paint
function S.PaintS(st, W, H)
    fonts(H)
    surface.SetDrawColor(COL_BACK.r, COL_BACK.g, COL_BACK.b, COL_BACK.a)
    surface.DrawRect(0, 0, W, H)
    local mid = TEXT_ALIGN_CENTER or 1
    draw.SimpleText("Character Select", "GSA1CharSelectTitle", W / 2, H * 0.14, COL_TEXT, mid, mid)
    for slot = 0, S.SLOTS - 1 do
        local x, y, w, h = S.ButtonRect(slot, W, H)
        draw.RoundedBox(math.floor(w / 8), x, y, w, h, slot == st.slot and COL_SELECTED or COL_SPHERE)
        draw.SimpleText(S.SlotTitle(slot), "GSA1CharSelectButton", x + w / 2, y + h / 2, COL_TEXT, mid, mid)
    end
    draw.SimpleText("Left / Right: move.   Enter, Space, a click, A or Start: pick.   Backspace, right click, B or Back: back.   "
        .. "Escape closes.", "GSA1CharSelectHint", W / 2, H * 0.84, COL_HINT, mid, mid)
    if st.fallback then
        draw.SimpleText(st.fallback, "GSA1CharSelectHint", W / 2, H * 0.89, COL_HINT, mid, mid)
    end
    local hint = S.SkinHint(st)
    if hint then skin_line(hint, W, H, 0.79) end
end

function S.Move(dir)
    local st = S.st
    if not st then return end
    st.slot = (st.slot + dir) % S.SLOTS
end

-- a pick: GSA1.Spawn (everything of a switch is its own: the place, the view's yaw, gsa1_character, the server), then close
function S.Finish(slot)
    local st = S.st
    if not st then return end
    local name = S.EntryName(slot)
    S.stats.picked = S.stats.picked + 1
    log("pick: slot %d, %s", slot, tostring(name))
    local ok, err = pcall(GSA1.Spawn, name)
    if not ok then log("the pick of %s failed: %s", tostring(name), tostring(err)) end
    S.Close("the pick")
end

-- Design S's controller: a press is an edge against the frame before, and padWas starts at what is held when the panel opens,
-- so the Start that opened it counts only after it was released
local function step_s(st)
    local raw, sx = pad_read()
    local pressed = band(raw, bnot(st.padWas))
    st.padWas = raw
    local dir = (sx <= -S.STICK and -1) or (sx >= S.STICK and 1) or 0
    if dir ~= 0 and dir ~= st.stickWas then S.Move(dir) end
    st.stickWas = dir
    if band(pressed, S.PAD_LEFT) ~= 0 then S.Move(-1) end
    if band(pressed, S.PAD_RIGHT) ~= 0 then S.Move(1) end
    if band(pressed, S.PAD_UP) ~= 0 and cv.skins:GetBool() then S.ToggleSkin(st) end
    if band(pressed, S.PAD_A + S.PAD_START) ~= 0 then return S.Finish(st.slot) end
    if band(pressed, S.PAD_B + S.PAD_BACK) ~= 0 then return S.Close("back") end
end

local function key_s(st, code)
    if code == KEY_MOVE_LEFT or code == KEY_LETTER_A then return S.Move(-1) end
    if code == KEY_MOVE_RIGHT or code == KEY_LETTER_D then return S.Move(1) end
    if (code == KEY_MOVE_UP or code == KEY_LETTER_W) and cv.skins:GetBool() then return S.ToggleSkin(st) end
    if code == KEY_PICK or code == KEY_PICK_PAD or code == KEY_PICK_SPACE then return S.Finish(st.slot) end
    if code == KEY_GO_BACK then return S.Close("back") end
end

local function mouse_s(st, code, mx, my, W, H)
    if code == M_RIGHT then return S.Close("back") end
    if code == M_LEFT then
        local slot = S.ButtonAt(mx, my, W, H)
        if slot then
            st.slot = slot
            return S.Finish(slot)
        end
    end
end

-- Design R ---------------------------------------------------------------------------------------------------------------------
local DS, VS = 11, 8            -- the flat arrays of gsa1.FrontendScreen (gsa1.HudScreen's layout)
local D_NO_TEXTURE = 0x80
local R_KINDS = { 0, 2, 3, 5, 7, 6 }   -- the ring's six characters (sh_config.lua kinds)
-- the game's circle on its 640 x 480 screen: a click inside it picks (charsel098 3.3)
local CIRCLE_X, CIRCLE_Y, CIRCLE_R = 316, 244, 150

-- the game's screen can run: the module's feature, and what draws it. true, or false and why
function S.HaveR()
    local ok = GSA1.HasFeature("frontend", 1)
    if not ok then return false, "the module has no feature \"frontend\"" end
    if type(gsa1.FRONTEND) ~= "table" or type(gsa1.FrontendOpen) ~= "function" then
        return false, "the module's feature \"frontend\" is incomplete"
    end
    if not (GSA1.Tex and GSA1.Tex.PaintNow and GSA1.Hud and GSA1.Hud.Material) then
        return false, "the addon's texture or HUD file did not load"
    end
    return true
end

-- the first open's menu textures, all at once (a screen never shows piecemeal); once, in PostRender as the painting of cl_textures
local function first_paint()
    hook.Remove("PostRender", "gsa1_charselect_paint")
    local st = S.st
    if not (st and st.design == "R") then return end
    local ok, n, ms = pcall(GSA1.Tex.PaintNow, st.F.KIND)
    if ok then
        if (n or 0) > 0 then log("the menu's %d textures painted in %.1f ms", n, ms or 0) end
    else
        S.FaultR(st, "painting its textures: " .. tostring(n))
    end
end

-- asks the module for the game's screen: true, or false and why
local function start_r(st)
    local have, why = S.HaveR()
    if not have then return false, why end
    local japanese = GSA1.cv and GSA1.cv.snd_japanese and GSA1.cv.snd_japanese:GetBool()
    local ok, msg, code = gsa1.FrontendOpen({ slot = st.slot, language = japanese and 0 or 1, dialog = cv.dialog:GetBool() })
    if not ok then
        -- ("unsupported": a library without the front end's code; nothing has gone wrong, no text on the chooser)
        return false, tostring(msg or "the module refused it") .. (code and (" (" .. tostring(code) .. ")") or ""),
            code ~= "unsupported"
    end
    st.design, st.F = "R", gsa1.FRONTEND
    st.scr, st.batches, st.events, st.state, st.m = {}, {}, {}, {}, {}
    if st.skin then
        -- opened while you are him: it opens on him
        st.skin = false
        S.ToggleSkin(st)
    end
    st.keys, st.pulse, st.mask, st.frame, st.slots = {}, 0, st.padWas, 0, S.SLOTS
    st.names = {}
    -- the characters' textures come in the budgeted way, the selected kind's first (T.Material's urgent T.Get)
    if not S.prepared then
        S.prepared = true
        for _, k in ipairs(R_KINDS) do GSA1.Tex.Prepare(k) end
    end
    hook.Add("PostRender", "gsa1_charselect_paint", first_paint)
    return true
end

-- the game's screen failed: one log line, and the simple chooser takes over with the same buttons
function S.FaultR(st, why)
    if st ~= S.st or st.design ~= "R" then return end
    S.stats.faults = S.stats.faults + 1
    log("the game's screen failed (%s): the simple chooser takes over", tostring(why))
    pcall(gsa1.FrontendClose)
    st.design = "S"
    st.fallback = "The game's own screen failed: " .. tostring(why)
    st.padWas, st.stickWas = (pad_read()), 0
    st.slot = st.slot % S.SLOTS
    S.MusicStart(st, S.MUSIC)
end

-- a press for one frame of the game (at most 8 frames run per call; a frame rate above 60 runs none in some calls: it waits)
local function pulse(st, b, code)
    st.pulse = bor(st.pulse, b)
    if code then st.keys[code] = b end
end

-- a run of presses, RUN_FRAMES apart (the ring's slide): the mouse wheel and a click on a sphere
local function run_to(st, dir, n)
    if dir == 0 or n <= 0 then return end
    st.run = { bit = dir > 0 and st.F.RIGHT or st.F.LEFT, left = n, at = st.frame }
end

-- the game's pick input: A, or after the pose's voice the skip of its 5 seconds (the plan's 6.3; host, gsa1_charselect_close)
local function pick_input(st, code)
    if st.picked then
        if st.frame > st.pickFrame then return S.Finish(st.picked) end
        return
    end
    pulse(st, st.F.A, code)
end

local function key_r(st, code)
    local F = st.F
    if code == KEY_PICK or code == KEY_PICK_PAD or code == KEY_PICK_SPACE then return pick_input(st, code) end
    if st.picked then return end
    if code == KEY_MOVE_LEFT or code == KEY_LETTER_A then return pulse(st, F.LEFT, code) end
    if code == KEY_MOVE_RIGHT or code == KEY_LETTER_D then return pulse(st, F.RIGHT, code) end
    if code == KEY_GO_BACK then return pulse(st, F.B, code) end
    if (code == KEY_MOVE_UP or code == KEY_LETTER_W) and cv.skins:GetBool() and tonumber(st.state.phase) == 0 then return S.ToggleSkin(st) end
end

-- the screen's bounding box of these vertices, on W x H; nil: none
local function vertex_box(scr, m, first, count)
    local V = scr.v
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for v = first, first + count - 1 do
        local o = v * VS
        local x, y = S.PlaceX(m, V[o + 1]), S.PlaceY(m, V[o + 2])
        if x < x0 then x0 = x end
        if x > x1 then x1 = x end
        if y < y0 then y0 = y end
        if y > y1 then y1 = y end
    end
    if x0 > x1 then return nil end
    return x0, y0, x1, y1
end

-- a texture's name of the menu's archives (no layout code: the draws say where things are)
local function name_of(st, archive, tex)
    if archive < 0 or tex < 0 then return nil end
    local key = archive * 4096 + tex
    local n = st.names[key]
    if n == nil then
        local info = GSA1.Tex.Info(st.F.KIND, archive, tex)
        n = info and info.name or false
        st.names[key] = n
    end
    return n or nil
end

-- which sphere is at a point: the k-th quad of the texture sphe_7 is slot (slot + k) mod n (8C9038E0 draws them from the selected
-- one; the bottom bar's two buttons use the same texture after the ring's n; libsa1 merges neighbours of one state into one draw,
-- so a draw may hold several quads, 6 vertices each), nil: none
function S.SphereAt(st, mx, my, m)
    local scr = st.scr
    local D = scr.d
    if not D then return nil end
    local k = 0
    for d = 0, (scr.nd or 0) - 1 do
        local o = d * DS
        if name_of(st, D[o + 4], D[o + 5]) == "sphe_7" then
            local first, count = D[o + 2], D[o + 3]
            for q = 0, math.floor(count / 6) - 1 do
                local x0, y0, x1, y1 = vertex_box(scr, m, first + q * 6, 6)
                if x0 and mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
                    return S.SphereSlot(st.slot, k, st.slots)
                end
                k = k + 1
                if k >= st.slots then return nil end
            end
        end
    end
    return nil
end

local function mouse_r(st, code, mx, my, W, H)
    if code == M_RIGHT then
        if not st.picked then pulse(st, st.F.B) end
        return
    end
    if code ~= M_LEFT then return end
    if st.picked then return pick_input(st) end
    local m = S.Layout(W, H, cv.wide:GetBool(), st.m)
    local slot = S.SphereAt(st, mx, my, m)
    if slot and slot ~= st.slot then
        local dir, n = S.ShortestRun(st.slot, slot, st.slots)
        return run_to(st, dir, n)
    end
    if slot then return pick_input(st) end
    local cx, cy = S.PlaceX(m, CIRCLE_X), S.PlaceY(m, CIRCLE_Y)
    local r = CIRCLE_R * m.sy
    if (mx - cx) * (mx - cx) + (my - cy) * (my - cy) <= r * r then return pick_input(st) end
end

local function events_r(st)
    local n = tonumber((gsa1.FrontendEvents(st.events))) or 0
    for i = 1, n do
        local e = st.events[i]
        local kind, id = e.kind, tonumber(e.id) or -1
        if kind == "select" then
            if id >= 0 then st.slot = id end
        elseif kind == "pick" then
            st.picked, st.pickFrame, st.run = id >= 0 and id or st.slot, st.frame, nil
            st.slot = st.picked
            log("the pose: slot %d", st.picked)
        elseif kind == "done" then
            S.Finish(st.picked or (id >= 0 and id) or st.slot)
            return
        elseif kind == "cancel" then
            S.Close("back")
            return
        elseif kind == "music" then
            if id >= 0 then S.MusicStart(st, id) else S.MusicStop(st, 0.3) end
        end
    end
end

-- one frame of the panel: the pad and the keys -> gsa1.FrontendTick -> the events
local function step_r(st)
    local F = st.F
    local raw, sx, sy = pad_read()
    -- what was held at the open counts only after it was released ("Start that opened the panel must be released before it
    -- counts as a pick"; A and the D-pad likewise)
    st.mask = band(st.mask, raw)
    local pad = band(raw, bnot(st.mask))
    local pressed = band(pad, bnot(st.padWas))
    st.padWas = raw
    local b = 0
    if st.picked then
        if band(pressed, S.PAD_A + S.PAD_START) ~= 0 then
            pick_input(st)
            if S.st ~= st then return end
        end
        sx, sy = 0, 0
    else
        -- 0.9.9f: on a slot with skins, only while the screen is idle (phase 0); Up is still forwarded, always (RM.5)
        if band(pressed, S.PAD_UP) ~= 0 and S.SLOT_SKINS[st.slot] and cv.skins:GetBool() and tonumber(st.state.phase) == 0 then S.ToggleSkin(st) end
        if band(pad, S.PAD_LEFT) ~= 0 then b = bor(b, F.LEFT) end
        if band(pad, S.PAD_RIGHT) ~= 0 then b = bor(b, F.RIGHT) end
        if band(pad, S.PAD_UP) ~= 0 then b = bor(b, F.UP) end
        if band(pad, S.PAD_DOWN) ~= 0 then b = bor(b, F.DOWN) end
        if band(pad, S.PAD_A) ~= 0 then b = bor(b, F.A) end
        if band(pad, S.PAD_START) ~= 0 then b = bor(b, F.START) end
        if band(pad, S.PAD_B + S.PAD_BACK) ~= 0 then b = bor(b, F.B) end
        for code, kb in pairs(st.keys) do
            if key_down(code) then b = bor(b, kb) else st.keys[code] = nil end
        end
        local run = st.run
        if run and st.frame >= run.at then
            st.pulse = bor(st.pulse, run.bit)
            run.left = run.left - 1
            if run.left <= 0 then st.run = nil else run.at = st.frame + S.RUN_FRAMES end
        end
        b = bor(b, st.pulse)
    end
    local frames, msg = gsa1.FrontendTick(RealFrameTime(), sx, sy, b)
    if not frames then return S.FaultR(st, msg) end
    if frames > 0 then
        st.pulse = 0
        st.frame = st.frame + frames
    end
    gsa1.FrontendState(st.state)
    st.slots = tonumber(st.state.slots) or st.slots
    st.slot = tonumber(st.state.slot) or st.slot
    events_r(st)
    if S.st == st and st.picked and cv.close:GetInt() == 1 and st.frame > st.pickFrame then
        S.Finish(st.picked)                     -- gsa1_charselect_close 1: the switch when the voice starts
    end
end

-- the 2D part of the paint: the draws behind the 3D or in front of it, in the list's order; the sky is repeated to the edges (the
-- wide screen rule; gsa1_charselect_wide stretches instead), every other vertex at x <= 0 or >= 640 goes to the screen's edge
local function emit_draw(V, first, count, m, dx, dy, whole)
    local pos = S.vpos
    mesh.Begin(MATERIAL_TRIANGLES, math.floor(count / 3))
    for v = first, first + count - 1 do
        local o = v * VS
        local x, y
        if whole then
            x, y = m.ox + dx + V[o + 1] * m.sx, m.oy + dy + V[o + 2] * m.sy
        else
            x, y = S.PlaceX(m, V[o + 1]), S.PlaceY(m, V[o + 2])
        end
        pos:SetUnpacked(x, y, 0)
        mesh.Position(pos)
        mesh.TexCoord(0, V[o + 3], V[o + 4])
        mesh.Color(V[o + 5], V[o + 6], V[o + 7], V[o + 8])
        mesh.AdvanceVertex()
    end
    mesh.End()
end

local function paint_2d(st, m, front, show_file, H_mat, T)
    local scr, F = st.scr, st.F
    local D, V = scr.d, scr.v
    local BS, BD = T.BLEND_SRC or {}, T.BLEND_DST or {}
    local add = BLENDFUNC_ADD or 0
    local n = 0
    for d = 0, (scr.nd or 0) - 1 do
        local k = d * DS
        local prim, first, count, archive, tex, flags = D[k + 1], D[k + 2], D[k + 3], D[k + 4], D[k + 5], D[k + 6]
        if count >= 3 and prim == 0 and (D[k + 9] > F.PRI_3D) == front then
            local name = name_of(st, archive, tex)
            if band(flags, D_NO_TEXTURE) == 0 and (show_file or not S.HiddenTexture(name)) then
                local mat, mode = H_mat(F.KIND, archive, tex, flags, false)
                if mat then
                    render.SetMaterial(mat)
                    if mode >= 2 then render.OverrideBlend(true, BS[D[k + 7]] or 4, BD[D[k + 8]] or 5, add) end
                    if st.skyArchive == archive and (m.ox > 0 or m.oy > 0) then
                        -- (a box wider than its copies: as many as reach the edges)
                        local sw, sh = 640 * m.sx, 480 * m.sy
                        local nx, ny = math.ceil(m.ox / sw), math.ceil(m.oy / sh)
                        for ky = -ny, ny do
                            for kx = -nx, nx do emit_draw(V, first, count, m, kx * sw, ky * sh, true) end
                        end
                    else
                        emit_draw(V, first, count, m, 0, 0, false)
                    end
                    if mode >= 2 then render.OverrideBlend(false) end
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- the studio of the picture: the neutral light of the spawn-menu pictures (feat/cl_objicons.lua I.STUDIO), no fog, tone mapping 1;
-- G-SA1's own light, not the game's palette (charsel098 2)
local WHITE_CUBE = { [0] = Vector(0.9, 0.9, 0.9), Vector(0.9, 0.9, 0.9), Vector(0.9, 0.9, 0.9), Vector(0.9, 0.9, 0.9),
                     Vector(0.9, 0.9, 0.9), Vector(0.9, 0.9, 0.9) }
local function paint_3d(st, m, T)
    local n, _, kind = gsa1.FrontendRender()
    if not n or n <= 0 then return 0 end
    local eye, ang, fov = gsa1.FrontendView()
    if not eye then return 0 end
    gsa1.FrontendBatches(st.batches)
    local count = tonumber(st.batches.count) or n
    render.ClearDepth()
    st.in3d = true
    local x, y = math.floor(m.ox + 0.5), math.floor(m.oy + 0.5)
    cam.Start3D(eye, ang, fov or 70, x, y, math.floor(640 * m.sx + 0.5), math.floor(480 * m.sy + 0.5), 4, 8000)
    local tone = render.GetToneMappingScaleLinear and render.GetToneMappingScaleLinear()
    if render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(Vector(1, 1, 1)) end
    if render.FogMode then render.FogMode(MATERIAL_FOG_NONE or 0) end
    if render.SetColorModulation then render.SetColorModulation(1, 1, 1) end
    if render.SetBlend then render.SetBlend(1) end
    local I = GSA1.ObjIcons
    GSA1.ApplyLightCube(eye + ang:Forward() * 100, I and I.STUDIO or WHITE_CUBE)
    local c = GSA1.cv
    gsa1.FrontendPrepareView(eye, ang:Right(), ang:Up(), c.flip:GetBool(), c.vcolor:GetBool(), c.line_width:GetFloat(),
        c.lighting:GetBool())
    local add = BLENDFUNC_ADD or 0
    local drawn = 0
    for pass = 0, 1 do
        for i = 1, count do
            local b = st.batches[i]
            if b and b.pass == pass and b.tris > 0 then
                local mat = T.Material(kind, b)
                if mat then
                    render.SetMaterial(mat)
                    if pass == 1 then
                        local src, dst = T.BlendOf(b)
                        render.OverrideBlend(true, src, dst, add)
                    end
                    mesh.Begin(MATERIAL_TRIANGLES, b.tris)
                    gsa1.FrontendEmitBatch(i)
                    mesh.End()
                    if pass == 1 then render.OverrideBlend(false) end
                    drawn = drawn + 1
                end
            end
        end
    end
    GSA1.EndLightCube()
    if tone and render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(tone) end
    cam.End3D()
    st.in3d = false
    return drawn
end

-- the panel's Paint with the game's screen; a Lua error here is the screen's fault too
local function paint_r(st, W, H)
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, W, H)
    local gen, msg = gsa1.FrontendScreen(st.scr)
    if not gen then
        S.FaultR(st, msg)
        return
    end
    if st.skyArchive == nil then
        st.skyArchive = false
        local a = GSA1.Tex.Archives(st.F.KIND)
        for ai = 0, a.n - 1 do
            if a[ai] and a[ai].name == "AVA_BACK" then st.skyArchive = ai end
        end
    end
    local m = S.Layout(W, H, cv.wide:GetBool(), st.m)
    local T, H_mat = GSA1.Tex, GSA1.Hud.Material
    local show = cv.file:GetBool()
    S.vpos = S.vpos or Vector(0, 0, 0)
    st.drawn2d = paint_2d(st, m, false, show, H_mat, T)
    st.drawn3d = paint_3d(st, m, T)
    st.drawn2d = st.drawn2d + paint_2d(st, m, true, show, H_mat, T)
    local hint = S.SkinHint(st)
    if hint then
        fonts(H)
        skin_line(hint, W, H, 0.80)
    end
end

function S.PaintR(st, W, H)
    local ok, err = pcall(paint_r, st, W, H)
    if not ok then
        if st.in3d then
            st.in3d = false
            pcall(GSA1.EndLightCube)
            pcall(cam.End3D)
        end
        S.FaultR(st, err)
    end
end

-- the panel --------------------------------------------------------------------------------------------------------------------
-- the panel's own input: the key and Escape first (a popup eats their binds), then the design's
function S.OnKey(code)
    local st = S.st
    if not st then return end
    if S.IsOwnKey(code) then
        S.keyClosedAt = SysTime()
        return S.Close("the key")
    end
    if code == KEY_CLOSE then return S.Close("Escape") end
    if st.design == "R" then return key_r(st, code) end
    return key_s(st, code)
end

function S.OnMouse(code, mx, my, W, H)
    local st = S.st
    if not st then return end
    if S.IsOwnKey(code) then
        S.keyClosedAt = SysTime()
        return S.Close("the key")
    end
    if st.design == "R" then return mouse_r(st, code, mx, my, W, H) end
    return mouse_s(st, code, mx, my, W, H)
end

function S.OnWheel(delta)
    local st = S.st
    if not st then return end
    local dir = (tonumber(delta) or 0) > 0 and -1 or 1
    if st.design == "R" then
        if st.picked then return end
        local run = st.run
        local b = dir > 0 and st.F.RIGHT or st.F.LEFT
        -- another notch in the same direction goes on the run
        if run and run.bit == b then run.left = run.left + 1 else run_to(st, dir, 1) end
        return
    end
    S.Move(dir)
end

-- every frame while open (the panel's Think: vgui runs it whatever the game does)
function S.Step()
    local st = S.st
    if not st then return end
    -- Escape opened the game menu: it closes this panel instead. Only the edge counts: the command typed in the console opens
    -- the panel under an open game menu
    local ui = gui.IsGameUIVisible()
    if ui and not st.uiWas then
        if gui.HideGameUI then gui.HideGameUI() end
        S.Close("Escape")
        return
    end
    st.uiWas = ui
    if st.design == "R" then return step_r(st) end
    return step_s(st)
end

local function make_panel(st)
    local p = vgui.Create("EditablePanel")
    p:SetPos(0, 0)
    p:SetSize(ScrW(), ScrH())
    p:MakePopup()
    p:SetKeyboardInputEnabled(true)
    p:SetMouseInputEnabled(true)
    p.Paint = function(self, w, h)
        if st.design == "R" then S.PaintR(st, w, h) end
        if st.design == "S" then S.PaintS(st, w, h) end       -- (also in the frame the game's screen failed)
    end
    p.Think = function() S.Step() end
    p.OnKeyCodePressed = function(self, code) S.OnKey(code) end
    p.OnMousePressed = function(self, code)
        local mx, my = 0, 0
        if self.CursorPos then mx, my = self:CursorPos() end
        S.OnMouse(code, mx, my, self:GetWide(), self:GetTall())
    end
    p.OnMouseWheeled = function(self, delta) S.OnWheel(delta) end
    p.OnRemove = function(self)
        -- removed from outside (a map change, another addon): the same way out
        if S.st == st then
            st.panel = nil
            S.Close("the panel was removed")
        end
    end
    return p
end

-- the menus under the panel go away (the C menu stays open while its key is held otherwise: review R.4)
local function close_menu(m)
    if not IsValid(m) or not (m.IsVisible and m:IsVisible()) or not m.Close then return end
    m:Close()
    if m:IsVisible() then m:Close() end              -- (a menu hanging open takes two)
end

-- opens it; how: "cmenu", "menubar", "command", "key", "start", "page"
function S.Open(how)
    if S.st then return true end
    local t0 = SysTime()
    close_menu(g_ContextMenu)
    close_menu(g_SpawnMenu)
    local raw = pad_read()
    local st = { how = how or "?", slot = S.FirstSlot(), padWas = raw, stickWas = 0, design = "S",
                 uiWas = gui.IsGameUIVisible(), t0 = t0 }
    do
        -- 0.9.9f: opening while you are a skin of this slot shows him (S.ToggleSkin, in start_r for the game's screen)
        local me = GSA1.Char and GSA1.Char.name or (GSA1.cv and GSA1.cv.character and GSA1.cv.character:GetString())
        for _, n in ipairs(S.SLOT_SKINS[st.slot] or {}) do
            if n == me then st.skin = true end
        end
    end
    S.st = st
    st.panel = make_panel(st)
    local ok, why, refused = start_r(st)
    if not ok then
        -- the failure path: the simple chooser with the same buttons (the plan's A16); a refusal the module gave is shown
        if refused then
            S.stats.faults = S.stats.faults + 1
            st.fallback = "The game's own screen could not open: " .. tostring(why)
        end
        S.MusicStart(st, S.MUSIC)
    end
    S.stats.opened = S.stats.opened + 1
    log("open (%s, %s): %.1f ms, %s", st.how, S.EntryName(st.slot), (SysTime() - t0) * 1000, ok and "the game's own screen" or
        ("the simple chooser: " .. tostring(why)))
    return true
end

-- every way out ends here
function S.Close(why)
    local st = S.st
    if not st then return false end
    S.st = nil
    if st.design == "R" then
        hook.Remove("PostRender", "gsa1_charselect_paint")
        pcall(gsa1.FrontendClose)
    end
    S.MusicStop(st, 0.3)
    if IsValid(st.panel) then st.panel:Remove() end
    -- what is held now does not open it again (the key or Start that closed it, whichever hook runs next)
    S.keyWas = key_down(cv.key:GetInt())
    S.startWas = band(pad_read(), S.PAD_START) ~= 0
    if why ~= "the pick" then S.stats.cancelled = S.stats.cancelled + 1 end
    log("close: %s, after %.1f s", tostring(why), SysTime() - st.t0)
    return true
end

function S.Toggle(how)
    if S.st then
        S.Close(how)
        return false
    end
    -- the panel closed itself on this key a moment ago and the bind came through as well
    if how == "the command" and SysTime() - S.keyClosedAt < 0.2 then return false end
    return S.Open(how)
end

-- the key and Start, polled (the panel closes itself on the key: a popup eats it). Nothing to allocate here: this runs every
-- frame with the panel closed (the plan's A22: at most 16 B)
local function think()
    local st = S.st
    if st and not IsValid(st.panel) then
        st.panel = nil
        S.Close("the panel is gone")
        st = nil
    end
    local down = key_down(cv.key:GetInt())
    if down and not S.keyWas and not st and not S.Busy() then S.Open("key") end
    S.keyWas = down
    local start = band(pad_read(), S.PAD_START) ~= 0
    if start and not S.startWas and not S.st and S.StartAllowed() and not S.Busy() then S.Open("start") end
    S.startWas = start
end
hook.Add("Think", "gsa1_charselect", GSA1.Guard and GSA1.Guard("CharSelect", think) or think)

-- Escape, where the engine asks first (older versions: S.Step's edge)
hook.Add("OnPauseMenuShow", "gsa1_charselect", function()
    if not S.st then return end
    S.Close("Escape")
    return false
end)

concommand.Add("gsa1_charselect", function() S.Toggle("the command") end, nil,
    "G-SA1: open or close Character Select (bind <key> gsa1_charselect works)")

-- 0.9.9: the question mark's texture (sadc docs/research/small099.md 3.2, gsa1_099_plan.md 2.3 row 1, 2.4 C1, C2). The model's
-- material asks for texture 7 of the menu's archive (cs_ce_tx, the words "Player Select"), sphere-mapped; its UVs stay in 0..1 and its
-- address mode clamps: nothing repeats, the normals sweep the words over every bevel. With gsa1_charselect_qmark 1 a sphere-mapped batch
-- of THAT texture takes sstx_body of the same archive, which no draw of the screen uses. By name, never by number: a texture or an
-- archive without those names stays as it is. Render only: the 2D "Player Select" (cl_hud.lua's H.Material) never comes here.
S.QUESTION_TEXTURES = 11    -- AVA_CHSEL(_E) on the disc; archive 62 is not in T.Archives(8)
local qmark_cache = {}
function S.QuestionTexture(kind, b)
    if band(b.flags or 0, 0x8) == 0 or not cv.qmark:GetBool() then return b.tex end     -- SA1_DRAW_ENV_MAP
    local T = GSA1.Tex
    local here = T.Info(kind, b.archive, b.tex)
    if not (here and string.lower(tostring(here.name)) == "cs_ce_tx") then return b.tex end
    local key = kind * 4096 + b.archive
    local q = qmark_cache[key]
    if q == nil then
        q = false
        local sup = gsa1.SUPER
        local count = (kind == 8 and sup and b.archive == sup.ARCHIVE_QUESTION) and S.QUESTION_TEXTURES
            or (T.Archives(kind)[b.archive] or {}).count or 0
        for i = 0, count - 1 do
            local info = T.Info(kind, b.archive, i)
            if info and string.lower(tostring(info.name)) == "sstx_body" then q = i break end
        end
        if not q then log("archive %d of character %d has no sstx_body: the question mark stays as the disc draws it", b.archive, kind) end
        qmark_cache[key] = q
    end
    return q or b.tex
end
if GSA1.Tex then GSA1.Tex.Remap = S.QuestionTexture end
-- T.ForgetKeys reaches the menu's per-frame call; a "?" that exists keeps its materials in C.mats (small099.md 3.2's hand-over)
cvars.AddChangeCallback("gsa1_charselect_qmark", function(_, _, new)
    if GSA1.Tex then GSA1.Tex.ForgetKeys() end
    local C = GSA1.Char
    if C and C.question then C.matsDirty = true end
    log("gsa1_charselect_qmark = %s", tostring(new))
end, "gsa1_charselect")

-- the entry points ---------------------------------------------------------------------------------------------------------------
-- the C menu's icon: at file scope, the sandbox gamemode reads the list when it makes the menu (after the autorun). A plain icon
-- until the disc gave Sonic's 1-up (S.IconStep)
S.ICON_FILE = "gsa1/charselect64.png"
S.ICON_PATH = "../data/" .. S.ICON_FILE
S.ICON_PLAIN = "icon64/playermodel.png"
local function start_icon()
    if file and file.Exists and file.Exists(S.ICON_FILE, "DATA") then return S.ICON_PATH end
    return S.ICON_PLAIN
end
S.DESKTOP = { title = "Character Select", icon = start_icon(), width = 640, height = 480, onewindow = true,
    init = function(icon, window)
        if IsValid(window) then window:Remove() end
        S.Open("cmenu")
    end }
if list and list.Set then list.Set("DesktopWindows", "GSA1CharSelect", S.DESKTOP) end

-- the menubar of the C and Q menus
hook.Add("PopulateMenuBar", "gsa1_charselect", function(bar)
    if not (bar and bar.AddOrGetMenu) then return end
    local m = bar:AddOrGetMenu("G-SA1")
    m:AddOption("Character Select...", function() S.Open("menubar") end)
    m:AddSpacer()
    for _, c in ipairs(GSA1.ListedCharacters()) do
        m:AddOption(c.title, function() GSA1.Spawn(c.name) end)
    end
    m:AddSpacer()
    m:AddOption("Remove character", function() RunConsoleCommand("gsa1_remove") end)
    S.menubarMenu = m
end)
-- 0.9.9e: the menubar was filled before the unlocking: the "?" goes at its end
hook.Add("GSA1QuestionUnlocked", "gsa1_charselect", function()
    local m = S.menubarMenu
    if not (m and m.AddOption and (not m.IsValid or m:IsValid())) then return end
    m:AddOption("?", function() GSA1.Spawn("question") end)
end)

-- the icon from your disc (never shipped; written at run time) -----------------------------------------------------------------
-- in place on the open C menu's widget, and for the next time the menu is made
function S.ApplyIcon(path)
    S.DESKTOP.icon = path
    if list and list.Set then list.Set("DesktopWindows", "GSA1CharSelect", S.DESKTOP) end
    local bar = IsValid(g_ContextMenu) and g_ContextMenu.DesktopWidgets
    if not (bar and IsValid(bar) and bar.GetChildren) then return false end
    for _, w in ipairs(bar:GetChildren()) do
        if w.WidgetClass == "GSA1CharSelect" and w.GetChildren then
            for _, c in ipairs(w:GetChildren()) do
                if c.SetImage then
                    c:SetImage(path)
                    return true
                end
            end
        end
    end
    return false
end

-- Sonic's 1-up from the disc into 64 x 64, as cl_objicons.lua's I.RenderTab does; true when done (made, or given up)
function S.RenderIcon()
    local Tx = GSA1.Tex
    if not (Tx and GSA1.mod and gsa1.IsReady and gsa1.IsReady()) then return false end
    local I = GSA1.ObjIcons or {}
    local e = Tx.Get(I.TAB_KIND or 0, I.TAB_ARCHIVE or 2, I.TAB_TEX or 31, 3, true)
    if not e then
        log("Sonic's 1-up icon is not on this disc: the C menu keeps the plain icon")
        return true
    end
    if not e.done then return false end
    local keep = GetConVar("gsa1_set_icons_save")
    if keep and not keep:GetBool() then return true end        -- "Keep the pictures": no file, the plain icon stays
    local fmt = Tx.format
    local size = 64
    local rt = GetRenderTargetEx("gsa1_charselect_icon_" .. fmt.name, size, size, RT_SIZE_LITERAL or 1, MATERIAL_RT_DEPTH_NONE or 2,
        (TEXTUREFLAGS_CLAMPS or 4) + (TEXTUREFLAGS_CLAMPT or 8), 0, fmt.fmt)
    local src = CreateMaterial("gsa1_charselect_icon_src_" .. fmt.name, "UnlitGeneric", { ["$basetexture"] = e.rt:GetName(),
        ["$translucent"] = 1, ["$vertexalpha"] = 1, ["$vertexcolor"] = 1 })
    local one, zero, add = BLEND_ONE or 1, BLEND_ZERO or 0, BLENDFUNC_ADD or 0
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
    render.OverrideBlend(true, one, zero, add, one, zero, add)
    surface.SetMaterial(src)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRect(0, 0, size, size)
    render.OverrideBlend(false)
    cam.End2D()
    local data = render.Capture and render.Capture({ format = "png", x = 0, y = 0, w = size, h = size, alpha = true })
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if not (data and #data > 0 and file and file.Write) then
        log("the C menu's icon could not be read back: the plain icon stays")
        return true
    end
    if file.CreateDir then file.CreateDir("gsa1") end
    file.Write(S.ICON_FILE, data)
    S.ApplyIcon(S.ICON_PATH)
    log("the C menu's icon: Sonic's 1-up from your disc, %d x %d", size, size)
    return true
end

-- PostRender while the icon is wanted: from the first time the C menu opens (its picture costs nothing before anyone sees it)
function S.IconStep()
    local ok, done = pcall(S.RenderIcon)
    if not ok then
        log("the C menu's icon: %s", tostring(done))
        done = true
    end
    if done then hook.Remove("PostRender", "gsa1_charselect_icon") end
    return done
end
hook.Add("ContextMenuOpened", "gsa1_charselect", function()
    if S.iconAsked or S.DESKTOP.icon == S.ICON_PATH then return end
    S.iconAsked = true
    hook.Add("PostRender", "gsa1_charselect_icon", S.IconStep)
end)

-- the Character page (the owner's rule: every option on the Q menu) --------------------------------------------------------------
local function combo(panel, label, name, choices)
    local c = panel:ComboBox(label)
    local now = GetConVar(name)
    now = now and now:GetString() or ""
    for _, e in ipairs(choices) do c:AddChoice(e[1], e[2], tostring(e[2]) == now) end
    c.OnSelect = function(_, _, _, data) RunConsoleCommand(name, tostring(data)) end
    return c
end

function S.BuildOptions(panel)
    panel:Help("Character Select")
    panel:ControlHelp("The game's own character select screen. Also in the C menu, in the menubar's G-SA1 menu and as the "
        .. "command gsa1_charselect. Nothing pauses: your character gets no input and can be hurt while it is open (on a board "
        .. "it rides on until it stops).")
    panel:Button("Open Character Select", "gsa1_charselect")
    panel:Help("Character Select key")
    local b = vgui.Create("DBinder", panel)
    if b.SetConVar then b:SetConVar("gsa1_charselect_key") end
    if b.SetTall then b:SetTall(28) end
    panel:AddItem(b)
    panel:CheckBox("Controller Start opens it", "gsa1_charselect_pad")
    panel:ControlHelp("Only while Start does nothing else on the Controller page. Once it is open Start picks and B or Back "
        .. "goes back, as in the game.")
    panel:CheckBox("Show the game's Game / Instruction / Cancel dialog", "gsa1_charselect_dialog")
    combo(panel, "After a pick", "gsa1_charselect_close", {
        { "the game's 5-second pose (A skips it after the voice)", "0" }, { "switch when the voice starts", "1" } })
    panel:CheckBox("Up on Sonic switches to Metal Sonic", "gsa1_charselect_skins")
    panel:ControlHelp("Up on the D-pad (or the Up key, or W) while Sonic is selected. Off: Up does what it did.")
    panel:CheckBox("Play Choose Your Buddy!", "gsa1_charselect_music")
    panel:ControlHelp("Your jukebox pauses where it is and goes on afterwards. Off: no music, the jukebox goes on.")
    panel:CheckBox("Show File and Clear in the bottom bar", "gsa1_charselect_file")
    combo(panel, "Wide screens", "gsa1_charselect_wide", { { "4:3 with the sky continued", "0" }, { "stretched", "1" } })
    combo(panel, "The question mark's texture", "gsa1_charselect_qmark", {
        { "gold (the menu's sstx_body; not what the game's code picks)", "1" },
        { "as the Dreamcast draws it (the words Player Select mirrored over it)", "0" } })
    panel:ControlHelp((GSA1.QuestionUnlocked() and "Both the question mark on this screen and the character \"?\". " or "The question mark on this screen. ") .. "The texture was never tiling: the game's model "
        .. "asks for the texture with the words Player Select and spreads them over every curved face. Your disc also has this unused gold.")
end
if GSA1.AddCharacterOption then GSA1.AddCharacterOption(180, "charselect", S.BuildOptions) end
