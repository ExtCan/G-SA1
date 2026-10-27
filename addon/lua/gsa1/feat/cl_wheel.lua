-- G-SA1 emote wheel, client (round 0.9.4a: sadc docs/research/faces_wheel_plan.md 4.6, 5.5, 5.6, 6.5, 7.1, 8.1, 8.3 with
-- its Review R.9 / R.16 / R.18 and the owner's answers 10.1; faces_wheel_ui.md 2, 3, 9; super2_plan.md 10.2, the CORRECTED
-- reading). The owner: "a holdable button that will open a radial menu (like GTA V's weapon wheel without the slow-mo) that
-- when a hold is let go, it will play the selected animation"; the animations "swappable with a menu in the G-SA1 options tab
-- that lists all the animations with their internal names"; "unique per character"; and (10.2) each slot with a face
-- animation, played together with the body animation by the Left Trigger (or a rebindable key / button) in the open wheel,
-- only the centre's face animation when nothing is highlighted.
--
--   * Hold the wheel key (gsa1_wheel_key, TAB) or button (gsa1_wheel_pad, D-pad down): the wheel opens in the middle of the
--     screen; the game keeps running (no slow motion). The mouse moves a cursor (the view does not turn), the right stick
--     points (the camera does not turn); keys 1-8 light a slot; the mouse wheel / LB / RB turn the pages (empty pages are
--     skipped). Release: the highlighted slot's body animation (gsa1.Emote; "(stop)": gsa1.EmoteStop; the one playing
--     again: back to standing with a blend). The face trigger (gsa1_wheel_face_key, the left mouse button; gsa1_wheel_face_pad,
--     LT) in the open wheel: the slot's face animation (GSA1.Faces.Play, feat/cl_faces.lua) together with its body animation,
--     or at the centre only the centre's face animation; the wheel closes and the release plays nothing more. Right click / B
--     cancel. The wheel closes without playing when the character goes, dies or changes, a menu or the chat opens.
--   * Nothing leaks into the game while it is open (review R.18): the mouse (InputMouseApply), the right stick and the camera
--     reset (a wrap of GSA1.PadView that calls the original with a stand-in command: the pending turn is used up, a reset is
--     dropped, the view stays), presses that start while it is open (the chained GSA1.FilterButtons: held back until released;
--     SA1 L / R held back while it is open), the interact key's synthetic action press (the chained GSA1.ExtraButtons), the
--     wheel key's own Garry's Mod bind (TAB = the scoreboard: blocked while a character exists), the mouse wheel (the seam
--     GSA1.BindOverride: pages, not the camera distance), the stick (the seam GSA1.FilterStick: "stop while choosing", and
--     the D-pad while a D-pad wheel button is held with gsa1_pad_dpad 1).
--   * Q menu > Options > G-SA1 > Emote wheel (order 280): every setting, and the wheels - pick a character (all eight entries,
--     editable without spawning), a page, a slot (or the centre) on the little wheel, double-click an animation in the list
--     (every animation of that character by its internal name, number, frames and how it plays; the game's variants of one
--     motion folded; the ones that cannot play yet greyed out with the reason: feat/cl_wheel_rows.lua), its face animation.
--     The wheels are kept in garrysmod/data/gsa1/emote_wheel.txt (feat/sh_wheel.lua's format), mirrored read-only into
--     gsa1_wheel_summary for the session log.
--   * Session log lines "emote": the wheel opened, what played (name, number, page, slot), refusals in libsa1's words,
--     cancels, faces played from the wheel; a count at the end of a character.
--   * Console: +gsa1_wheel / -gsa1_wheel (the wheel held by a bind), gsa1_emote <name, key or number>, gsa1_emote_stop.
--   * Round 0.9.4b (objects2_plan.md 11.2, the owner's 0.9.4a notes): "Hold the last pose" per slot (default on): an
--     animation that ends in a pose (it plays once) stays on its last frame until he moves, jumps, presses the action
--     button or plays another animation (libsa1's end mode HOLD: gsa1.EMOTE.HOLD, feature "emote" 2; looping ones loop
--     until he moves); choosing the held slot again blends back to standing. The wheel's look: a dark glass ring with
--     clear separators, the highlighted slot lit in the character's colour (Sonic blue; gold for Super Sonic) and a little
--     larger, the animation's name large in the centre, a gold marker on slots with a face animation, a short open / close
--     and highlight fade; its fonts (Garry's Mod's Roboto by default, gsa1_wheel_font) are made per wheel size and screen
--     with surface.CreateFont - once per size, never per frame - so the labels grow and shrink with the wheel.
--   * Round 0.9.4e (gsa1_rounds_plan.md 14.1aa; the owner: "An option for hiding the wheel for recording purposes would be
--     great, also being able to change the animation's play rate"): "Hide the wheel" (gsa1_wheel_hidden, a check box and
--     a toggle key gsa1_wheel_hide_key): the wheel works exactly as usual but its HUD draws nothing (W.HUDPaint; the rule
--     for the toggle's note is at W.ToggleHidden); the play rate: per slot (W.SPEEDS, saved in the file's speed column)
--     times gsa1_wheel_speed, sent as gsa1.Emote's 4th argument (libsa1's sa1_emote_item.speed; feature "emote" 3). A
--     slot's face animation keeps its own timing.
GSA1 = GSA1 or {}
local W = GSA1.Wheel
if not W then error("gsa1/feat/sh_wheel.lua did not load: the emote wheel needs it") end

local band, bor, bnot = bit.band, bit.bor, bit.bnot
local BTN_L, BTN_R = 8, 16

-- settings (every one has a control on the Emote wheel page) ----------------------------------------------------------------
local cv = {
    on = GSA1.ConVar("gsa1_wheel", 1, "The emote wheel: hold the wheel key, point at an animation with the mouse or the "
        .. "right stick, release to play it (1 = on)", 0, 1),
    key = GSA1.ConVar("gsa1_wheel_key", 67, "The emote wheel's key, held (a key code; 67 = TAB; 0 = none: bind +gsa1_wheel "
        .. "instead). While you are a character this key does not open the scoreboard", 0, 511),
    pad = GSA1.ConVar("gsa1_wheel_pad", 2, "The emote wheel's controller button, held (XInput bits: 2 = D-pad down; 0 = "
        .. "none)", 0, 0x30000),
    face_key = GSA1.ConVar("gsa1_wheel_face_key", 107, "The face trigger in the open wheel (a key or mouse button code; 107 "
        .. "= the left mouse button; 0 = none): the highlighted slot's face animation with its animation, or only the "
        .. "centre's face animation", 0, 511),
    face_pad = GSA1.ConVar("gsa1_wheel_face_pad", 0x10000, "The face trigger's controller button (XInput bits: 65536 = LT; "
        .. "0 = none)", 0, 0x30000),
    mouse = GSA1.ConVar("gsa1_wheel_mouse", 1, "Mouse sensitivity in the emote wheel", 0.25, 4),
    deadzone = GSA1.ConVar("gsa1_wheel_deadzone", 0.5, "The right stick points at a slot from this deflection on", 0.2, 0.9),
    keep = GSA1.ConVar("gsa1_wheel_stick_keep", 0.5, "Seconds a slot stays lit after the right stick went back to rest, "
        .. "then the centre (0 = it stays lit)", 0, 2),
    size = GSA1.ConVar("gsa1_wheel_size", 1, "The emote wheel's size", 0.5, 2),
    opacity = GSA1.ConVar("gsa1_wheel_opacity", 0.75, "The emote wheel's background", 0.2, 1),
    font = GSA1.ConVar("gsa1_wheel_font", 0, "The emote wheel's font: 0 = Roboto (Garry's Mod's own), 1 = Segoe UI "
        .. "(Windows), 2 = Bahnschrift (Windows 10 / 11), 3 = Coolvetica (Garry's Mod's classic)", 0, 3),
    move = GSA1.ConVar("gsa1_wheel_move", 1, "The character can keep moving while the emote wheel is open (0 = he stops)",
        0, 1),
    air = GSA1.ConVar("gsa1_wheel_air", 0, "Animations from the emote wheel may start in the air (he keeps falling and lands "
        .. "while posing)", 0, 1),
    tap = GSA1.ConVar("gsa1_wheel_tap", 0, "A quick tap of the wheel key plays the last animation again", 0, 1),
    toast = GSA1.ConVar("gsa1_wheel_toast", 1, "Show the name of what plays (and why an animation could not play)", 0, 1),
    -- round 0.9.4e (gsa1_rounds_plan.md 14.1aa)
    hidden = GSA1.ConVar("gsa1_wheel_hidden", 0, "Hide the emote wheel (for recording): it works exactly as usual - hold, "
        .. "point, release, the face trigger - but draws nothing on screen (1 = hidden)", 0, 1),
    hide_key = GSA1.ConVar("gsa1_wheel_hide_key", 0, "A key that switches \"Hide the wheel\" on and off (a key code; 0 = "
        .. "none; the console command gsa1_wheel_hide_toggle does the same)", 0, 511),
    speed = GSA1.ConVar("gsa1_wheel_speed", 1, "The play rate of every animation from the emote wheel: it multiplies each "
        .. "slot's own play rate (1 = the game's rate, 2 = twice as fast)", 0.25, 4),
    summary = GSA1.ConVar("gsa1_wheel_summary", "", "Read-only: a copy of your emote wheels' state for the session log (the "
        .. "wheels themselves are in garrysmod/data/gsa1/emote_wheel.txt)"),
}
W.cv = cv

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("emote", fmt, ...) end
end

-- the module ------------------------------------------------------------------------------------------------------------------
local have_cache, have_at, speed_cache = false, -1e9, false
local function have()
    local now = SysTime()
    if now - have_at > 2 then
        have_at = now
        have_cache = (GSA1.HasFeature and GSA1.HasFeature(W.NEEDS.feature, W.NEEDS.version)) and true or false
        -- 0.9.4e: does the module take the play rate (feature "emote" 3)
        speed_cache = (GSA1.HasFeature and GSA1.HasFeature(W.SPEED_NEEDS.feature, W.SPEED_NEEDS.version)) and true or false
    end
    return have_cache
end
W.Have = have
function W.ResetHave() have_at = -1e9 end
-- round 0.9.4e: the module plays an animation at a rate (gsa1.Emote's 4th argument); older ones at the game's rate
function W.SpeedSupported()
    have()
    return speed_cache
end
-- round 0.9.4e: the wheel draws nothing (gsa1_wheel_hidden)
function W.Hidden()
    return cv.hidden:GetBool()
end
local function emote_const(name, default)
    local E = gsa1 and gsa1.EMOTE
    return E and tonumber(E[name]) or default
end

-- an entry's catalogue (gsa1.EmoteList, no world needed), kept for the session once the disc is loaded
W.lists = W.lists or {}
function W.ListOf(entry)
    local l = W.lists[entry]
    if l then return l end
    if not (GSA1.mod and gsa1 and gsa1.EmoteList and have()) then return nil end
    local kind, form = W.KindForm(entry)
    if not kind then return nil end
    local ok, list = pcall(gsa1.EmoteList, kind, form)
    if not ok or type(list) ~= "table" then return nil end
    W.Index(list)
    W.lists[entry] = list
    return list
end

-- the file ------------------------------------------------------------------------------------------------------------------------
function W.SetMirror()
    local m = W.MirrorString(W.data)
    if cv.summary and cv.summary:GetString() ~= m then cv.summary:SetString(m) end
end
function W.Load()
    local text = file.Read(W.FILE, "DATA")
    W.data, W.badLines, W.badNotes = W.Parse(text)
    W.SetMirror()
    return W.data
end
function W.Save()
    if file.CreateDir then file.CreateDir("gsa1") end
    file.Write(W.FILE, W.Serialize(W.data))
    W.SetMirror()
end
W.data = W.data or W.Load()

-- the wheel of an entry: the file's, else its defaults
function W.WheelOf(entry)
    return W.data[entry] or W.DefaultWheel(entry)
end
-- the wheel of an entry for an edit: from the defaults at the first edit (the extras' keys filled from the catalogue)
function W.Edit(entry)
    local w = W.data[entry]
    if w then return w end
    w = W.DefaultWheel(entry)
    local list = W.ListOf(entry)
    if list then
        for p = 1, W.PAGES do
            for s = 1, W.SLOTS do
                local o = w.pages[p][s]
                if o.body == "x" then
                    local e = W.Resolve(list, o.body, o.name)
                    if e then o.body = e.key end
                end
            end
        end
    end
    W.data[entry] = w
    return w
end
function W.ResetEntry(entry)
    W.data[entry] = nil
    W.Save()
end

-- input --------------------------------------------------------------------------------------------------------------------------
local function key_down(code)
    code = tonumber(code) or 0
    return code > 0 and input ~= nil and input.IsButtonDown ~= nil and input.IsButtonDown(code) == true
end
local function pad_raw()
    local p = GSA1.pad
    if p and p.connected then return tonumber(p.raw) or 0 end
    return 0
end
-- a panel, a menu, the chat: the reason, else nil
function W.Busy()
    if GSA1.InputBlocked and GSA1.InputBlocked() then return "a panel has the input" end
    if vgui.CursorVisible() then return "a menu opened" end
    if gui.IsGameUIVisible() then return "the game menu opened" end
    local ply = LocalPlayer()
    if IsValid(ply) and ply.IsTyping ~= nil and ply:IsTyping() == true then return "typing" end
    return nil
end
-- the wheel key / button / command held, and by which
function W.WheelDown()
    if W.cmdDown then return true, "the command +gsa1_wheel" end
    if key_down(cv.key:GetInt()) then return true, W.KeyName(cv.key:GetInt()) end
    local b = cv.pad:GetInt()
    if b > 0 and band(pad_raw(), b) ~= 0 then return true, W.PadTitle(b) end
    return false
end
function W.FaceDown()
    if key_down(cv.face_key:GetInt()) then return true end
    local b = cv.face_pad:GetInt()
    return b > 0 and band(pad_raw(), b) ~= 0
end
local function cancel_down()
    return key_down(W.MOUSE_RIGHT) or band(pad_raw(), W.PAD_B) ~= 0
end
local KEY_ONE = KEY_1 or 2
local function slot_keys()
    local down = 0
    for i = 1, W.SLOTS do
        local code = KEY_ONE + i - 1
        local d = (input and input.IsKeyDown and input.IsKeyDown(code)) or key_down(code)
        if d then down = bor(down, bit.lshift(1, i - 1)) end
    end
    return down
end

-- a key's name for the page and the hint ("TAB", "left click")
function W.KeyName(code)
    code = tonumber(code) or 0
    if code <= 0 then return "none" end
    if code == W.MOUSE_LEFT then return "left click" end
    if code == W.MOUSE_RIGHT then return "right click" end
    local name = input and input.GetKeyName and input.GetKeyName(code)
    return string.upper(tostring(name or code))
end

-- the SA1 buttons a controller button presses through the Controller page's map (gsa1_pad_<name>; cl_pad.lua)
local PAD_NAMES = { [0x1000] = "a", [0x2000] = "b", [0x4000] = "x", [0x8000] = "y", [0x0100] = "lb", [0x0200] = "rb",
                    [0x10000] = "lt", [0x20000] = "rt", [0x0010] = "start", [0x0020] = "back", [0x0040] = "ls",
                    [0x0080] = "rs" }
local ACTION_BITS = { [1] = 1, [2] = 2, [3] = 4, [4] = BTN_L, [5] = BTN_R }
local ACTION_WORDS = { [1] = "jump", [2] = "the action button", [3] = "SA1 Y", [4] = "SA1 L", [5] = "SA1 R",
                       [6] = "the camera (left)", [7] = "the camera (right)", [8] = "the camera reset" }
function W.PadMapped(b)
    local name = PAD_NAMES[tonumber(b) or 0]
    local c = name and GSA1.cv and GSA1.cv["pad_" .. name]
    local act = c and c:GetInt() or 0
    return ACTION_BITS[act] or 0, ACTION_WORDS[act]
end

-- the wheel ------------------------------------------------------------------------------------------------------------------------
W.open = false
W.stats = W.stats or { opened = 0, played = 0, refused = 0, cancelled = 0, faces = 0 }
W.masked = W.masked or 0

local function toast(fmt, ...)
    -- 0.9.4e: hidden, nothing of the wheel may show (not even later: the toast is not kept)
    if not cv.toast:GetBool() or cv.hidden:GetBool() then return end
    local ok, text = pcall(string.format, fmt, ...)
    W.toastText = ok and text or tostring(fmt)
    W.toastUntil = SysTime() + 1.5
end
W.Toast = toast

function W.Open(C, how)
    W.open, W.char, W.entry = true, C, C.name or (GSA1.CharacterByKind and GSA1.CharacterByKind(C.kind) or {}).name or "sonic"
    W.page, W.sel, W.cx, W.cy = 1, 0, 0, 0
    W.openAt, W.how, W.lastInput, W.stickAt = SysTime(), how, nil, nil
    W.wheel = W.WheelOf(W.entry)
    W.list = W.ListOf(W.entry)
    W.glow, W.pointDeg, W.fadeFrom = {}, nil, nil
    -- the edges start from what is held now: a face key or button held while opening is no press
    W.faceWas, W.cancelWas, W.padWas, W.keysWas = W.FaceDown(), cancel_down(), pad_raw(), slot_keys()
    W.stats.opened = W.stats.opened + 1
    log("wheel opened (%s): %s's wheel, page 1 of %d", tostring(how), W.Title(W.entry), #W.Pages(W.wheel))
end

-- why: nil for a play, a reason for a cancel; guard: a press closed it (the press is held back from the game)
function W.Close(why, guard)
    if not W.open then return end
    W.open = false
    -- the HUD fades the wheel out (W.CLOSE_TIME); hidden (0.9.4e): no fade, not even after showing it again
    W.fadeFrom = (not cv.hidden:GetBool()) and SysTime() or nil
    if guard then
        W.closedAt, W.guardTicks = SysTime(), W.CLOSE_GUARD_TICKS
    end
    if why then
        W.stats.cancelled = W.stats.cancelled + 1
        log("wheel cancelled (%s)", why)
    end
end

-- the open wheel's slot (nil at the centre)
function W.Selected()
    if not W.open or W.sel == 0 then return nil end
    return W.wheel.pages[W.page][W.sel]
end

function W.TurnPage(dir, how)
    if not W.open then return end
    local p = W.NextPage(W.wheel, W.page, dir)
    if p ~= W.page then
        W.page, W.sel = p, 0
        W.lastInput = nil
    end
end

-- what a slot's body plays now (its catalogue entry), or nil, the reason
local function slot_entry(slot, list)
    if not slot or not slot.body then return nil, "empty" end
    if slot.body == "stop" then return nil, "stop" end
    local e, how = W.Resolve(list, slot.body, slot.name)
    if not e then return nil, how == "no list" and "the catalogue is not loaded" or ("missing: " .. tostring(slot.name or slot.body)) end
    return e
end
W.SlotEntry = slot_entry

-- a slot's body animation on character C (entry: whose wheel; default the open wheel's): true when libsa1 took it
function W.PlayBody(C, slot, page, s, how, face, entry)
    if not slot or not slot.body then return false end
    entry = entry or W.entry or C.name
    local title = C.title or W.Title(entry)
    if slot.body == "stop" then
        local ok, why = gsa1.EmoteStop(C.id, emote_const("STOP_NOW", 0))
        log("stop (page %d slot %d)%s", page or 0, s or 0, ok and "" or (": " .. tostring(why)))
        toast("> stop%s", face and (" + " .. face) or "")
        return ok and true or false
    end
    local e, why = slot_entry(slot, W.ListOf(entry))
    if not e then
        toast("%s", why)
        log("refused page %d slot %d: %s", page or 0, s or 0, why)
        W.stats.refused = W.stats.refused + 1
        return false
    end
    -- the one G-SA1 started last, still playing or holding its pose: back to standing (review R.18: EmoteState's row
    -- follows the chain; 0.9.4b: a held pose blends into the stand)
    local pl = W.playing
    if pl and pl.id == C.id and pl.key == e.key then
        local st = gsa1.EmoteState(C.id)
        if st == emote_const("STATE_PLAYING", 1) or st == emote_const("STATE_ENDING", 2) or
            st == emote_const("STATE_HOLDING", 3) then
            gsa1.EmoteStop(C.id, emote_const("STOP_BLEND", 1))
            W.playing = nil
            log("%s back to standing (chosen again: page %d slot %d)", e.name, page or 0, s or 0)
            toast("> %s: back to standing", e.name)
            return true
        end
    end
    local flags = 0
    if slot.loop then flags = bor(flags, emote_const("LOOP", 0x100)) end
    if cv.air:GetBool() then flags = bor(flags, emote_const("IN_AIR", 4)) end
    -- 0.9.4b: "Hold the last pose" (an animation that plays once stays on its last frame; a module without HOLD: 0)
    local hold = W.HoldApplies(slot, e) and emote_const("HOLD", 0) or 0
    if hold ~= 0 then flags = bor(flags, hold) end
    -- 0.9.4e: the play rate - the slot's x gsa1_wheel_speed (libsa1's sa1_emote_item.speed); a module without it: the
    -- game's rate (the 4th argument is not sent)
    local rate = W.PlayRate(slot, cv.speed:GetFloat())
    local rated = W.SpeedSupported()
    local ok, reason, code
    if rated then
        ok, reason, code = gsa1.Emote(C.id, e.key, flags, rate)
    else
        ok, reason, code = gsa1.Emote(C.id, e.key, flags)
    end
    if ok then
        W.playing = { id = C.id, key = e.key, name = e.name, hold = hold ~= 0, rate = rated and rate or 1 }
        W.last = { page = page, slot = s }
        W.stats.played = W.stats.played + 1
        local at = ""
        if rate ~= 1 then
            at = rated and (", at " .. W.SpeedText(rate)) or string.format(", at the game's rate (%s needs G-SA1 module %s)",
                W.SpeedText(rate), W.SPEED_NEEDS.module)
        end
        log("played %s (#%s) from page %d slot %d of %s's wheel (%s)%s%s", e.name ~= "" and e.name or e.key,
            e.source == 1 and ("extra " .. tostring(e.index)) or tostring(e.index), page or 0, s or 0, W.Title(entry), how,
            slot.loop and ", looped" or (hold ~= 0 and ", holds its last pose" or ""), at)
        toast("> %s%s%s%s", e.name ~= "" and e.name or e.key, (rated and rate ~= 1) and (" at " .. W.SpeedText(rate)) or "",
            face and (" + " .. face) or "",
            (slot.loop or e.play == "loop") and " (move to stop)" or (hold ~= 0 and " (holds the pose: move to stop)" or ""))
        return true
    end
    W.stats.refused = W.stats.refused + 1
    reason = tostring(reason or "refused")
    log("%s refused (%s): %s", e.name ~= "" and e.name or e.key, tostring(code), reason)
    -- review R.16: on the ground but not standing - with the wheel open the stick usually still moves him
    toast("%s can't do that now: %s%s", title, reason, reason == "moving" and " - let go of the stick to pose" or "")
    return false
end

-- a face animation from the wheel (feat/cl_faces.lua's GSA1.Faces; guarded: faces_wheel_plan.md 5.5)
function W.PlayFace(C, entry, name)
    local F = GSA1.Faces
    if not name or not (F and F.Play) then return false end
    if F.HasFaces and not F.HasFaces(entry) then return false end
    if F.CanShow then
        local can, why = F.CanShow(name, entry)
        if can == false then
            toast("%s", tostring(why or ("cannot show " .. name)))
            log("face %s not shown: %s", name, tostring(why))
            return false
        end
    end
    local ok, why = F.Play(C, name, "wheel")
    if ok then
        W.stats.faces = W.stats.faces + 1
        log("face %s (wheel)", name)
    else
        toast("%s", tostring(why or "the face animation did not play"))
        log("face %s refused: %s", name, tostring(why))
    end
    return ok and true or false
end

-- release: the highlighted slot's body animation (nothing at the centre; a tap may repeat the last one)
function W.Release(C)
    local sel, page = W.sel, W.page
    local tapped = SysTime() - (W.openAt or 0) < W.TAP
    local wheel = W.wheel
    W.Close(nil)
    if sel == 0 then
        if tapped and cv.tap:GetBool() and W.last then
            local slot = wheel.pages[W.last.page] and wheel.pages[W.last.page][W.last.slot]
            if slot and slot.body then W.PlayBody(C, slot, W.last.page, W.last.slot, "a tap") end
        else
            log("wheel released at the centre: nothing")
        end
        return
    end
    local slot = wheel.pages[page][sel]
    if not W.SlotUsed(slot) or not slot.body then
        log("wheel released on page %d slot %d: no animation there", page, sel)
        return
    end
    W.PlayBody(C, slot, page, sel, "release")
end

-- the face trigger: the slot's face animation together with its body animation, or the centre's face animation alone;
-- the wheel closes (the later release plays nothing)
function W.FaceTrigger(C, how)
    local sel, page, entry, wheel = W.sel, W.page, W.entry, W.wheel
    W.Close(nil, true)
    local F = GSA1.Faces
    local faces = F ~= nil and F.Play ~= nil and (not F.HasFaces or F.HasFaces(entry))
    if sel == 0 then
        local face = wheel.centre and wheel.centre.face
        if face and faces then
            W.PlayFace(C, entry, face)
            toast("face: %s", face)
        else
            log("face trigger at the centre (%s): no face animation there", how)
        end
        return
    end
    local slot = wheel.pages[page][sel]
    local face = slot and faces and slot.face or nil
    W.PlayBody(C, slot, page, sel, "the face trigger", face)
    if face then W.PlayFace(C, entry, face) end
end

-- why the open wheel closes now (nil: it stays)
function W.CloseReason(C)
    if not C then return "the character is gone" end
    if C ~= W.char then return "the character changed" end
    if C.death then return "the character died" end
    if not cv.on:GetBool() then return "the wheel was switched off" end
    return W.Busy()
end

-- every frame, before the character's tick (GSA1PreTick: cl_pad.lua's PadUpdate has read the controller of this frame)
function W.Think()
    local C = GSA1.Char
    local now = SysTime()
    local raw, how = W.WheelDown()
    if W.open then
        local why = W.CloseReason(C)
        if why then
            W.Close(why, false)
        else
            W.OpenThink(C, now, raw)
        end
    elseif raw and not W.wasRaw and C and not C.death and cv.on:GetBool() and not W.Busy() and have() then
        W.Open(C, how)
    end
    W.wasRaw = raw
    W.padHeld = cv.pad:GetInt() > 0 and band(pad_raw(), cv.pad:GetInt()) ~= 0
end

-- the open wheel's inputs of this frame: the face trigger and a cancel first (a press in the frame of the release still
-- counts), then the release, the pages, keys 1-8, the right stick
function W.OpenThink(C, now, raw)
    local fd = W.FaceDown()
    if fd and not W.faceWas then
        W.faceWas = fd
        W.FaceTrigger(C, "the face trigger")
        return
    end
    W.faceWas = fd
    local cd = cancel_down()
    if cd and not W.cancelWas then
        W.cancelWas = cd
        W.Close(key_down(W.MOUSE_RIGHT) and "right click" or "B", true)
        return
    end
    W.cancelWas = cd
    if not raw then
        W.Release(C)
        return
    end
    local praw = pad_raw()
    local new = band(praw, bnot(W.padWas or 0))
    W.padWas = praw
    if band(new, W.PAD_LB) ~= 0 then W.TurnPage(-1, "LB") end
    if band(new, W.PAD_RB) ~= 0 then W.TurnPage(1, "RB") end
    local keys = slot_keys()
    local knew = band(keys, bnot(W.keysWas or 0))
    W.keysWas = keys
    for i = 1, W.SLOTS do
        if band(knew, bit.lshift(1, i - 1)) ~= 0 then
            W.sel, W.lastInput, W.pointDeg = i, "keys", nil
        end
    end
    local p = GSA1.pad
    if p and p.connected then
        local rx, ry = tonumber(p.rx) or 0, tonumber(p.ry) or 0
        if math.sqrt(rx * rx + ry * ry) >= cv.deadzone:GetFloat() then
            -- XInput's thumb y grows upwards (src/core/pad.cpp pad_axis): up = slot 1
            W.pointDeg = W.Angle(rx, ry)
            W.sel = W.Pick(W.sel ~= 0 and W.sel or nil, W.pointDeg)
            W.lastInput, W.stickAt = "stick", now
        elseif W.lastInput == "stick" and W.sel ~= 0 then
            local keep = cv.keep:GetFloat()
            if keep > 0 and now - (W.stickAt or now) >= keep then W.sel = 0 end
            W.pointDeg = nil
        end
    end
end

-- the mouse moves the wheel's cursor while it is open; the view does not turn
function W.MouseApply(cmd, x, y)
    if not W.open then return nil end
    if (x and x ~= 0) or (y and y ~= 0) then
        W.cx, W.cy = W.MoveCursor(W.cx, W.cy, x, y, cv.mouse:GetFloat())
        W.sel = W.CursorSlot(W.sel, W.cx, W.cy)
        W.lastInput = "mouse"
        W.pointDeg = W.sel ~= 0 and W.Angle(W.cx, W.cy) or nil
    end
    if cmd then
        if cmd.SetMouseX then cmd:SetMouseX(0) end
        if cmd.SetMouseY then cmd:SetMouseY(0) end
    end
    return true
end

-- the seams (kept across a reload of this file: W survives it) ------------------------------------------------------------------
-- GSA1.PadView (cl_pad.lua, called from CreateMove): while the wheel is open the original runs with a stand-in command - it
-- uses up the pending controller turn and drops a camera reset (the stand-in reports a mouse move) - and the view stays
W.prevPadView = W.prevPadView or GSA1.PadView
local proxy = { cmd = nil }
function proxy:GetViewAngles() return self.cmd:GetViewAngles() end
function proxy:SetViewAngles() end
function proxy:GetMouseX() return 1 end
function proxy:GetMouseY() return 1 end
GSA1.PadView = function(cmd)
    local orig = W.prevPadView
    if not orig then return end
    if not W.open then return orig(cmd) end
    proxy.cmd = cmd
    local ok, err = pcall(orig, proxy)
    proxy.cmd = nil
    if not ok then log("error in GSA1.PadView: %s", tostring(err)) end
end

-- GSA1.FilterButtons (cl_character.lua: the player's own buttons before each tick): a press that starts while the wheel
-- is open (or in the ticks right after a press closed it: the face trigger, right click / B - the click reaches the
-- buttons through CreateMove up to a frame later) is held back until it is released; SA1 L / R and the wheel button's own
-- mapped buttons are held back while it is open / held. A jump held before opening stays held.
W.CLOSE_GUARD_TICKS = 3
function W.Filter(C, buttons)
    buttons = tonumber(buttons) or 0
    local guard = false
    if W.guardTicks and W.guardTicks > 0 then
        W.guardTicks = W.guardTicks - 1
        guard = true
    end
    local new = band(buttons, bnot(W.lastButtons or 0))
    W.lastButtons = buttons
    if W.open or guard then W.masked = bor(W.masked or 0, new) end
    W.masked = band(W.masked or 0, buttons)
    local out = band(buttons, bnot(W.masked))
    if W.open then out = band(out, bnot(bor(BTN_L, BTN_R))) end
    if W.padHeld and (W.open or guard) then out = band(out, bnot(W.PadMapped(cv.pad:GetInt()))) end
    return out
end
W.prevFilter = W.prevFilter or GSA1.FilterButtons
GSA1.FilterButtons = function(C, buttons)
    local b = W.Filter(C, buttons)
    if W.prevFilter then b = W.prevFilter(C, b) end
    return b
end

-- GSA1.ExtraButtons (feat/cl_interact.lua: the interact / lift keys press the game's action button): 0 while open
W.prevExtra = W.prevExtra or GSA1.ExtraButtons
GSA1.ExtraButtons = function(C)
    if W.open then return 0 end
    if W.prevExtra then return W.prevExtra(C) end
    return 0
end

-- GSA1.FilterStick (cl_character.lua seam, 0.9.4a): "stop while choosing" (gsa1_wheel_move 0) and the D-pad of a D-pad
-- wheel button with "D-pad moves the character" while the left stick rests
function W.Stick(C, sx, sy)
    if W.open and not cv.move:GetBool() then return 0, 0 end
    local b = cv.pad:GetInt()
    if W.padHeld and band(b, W.PAD_DPAD) ~= 0 and GSA1.cv and GSA1.cv.pad_dpad and GSA1.cv.pad_dpad:GetBool() then
        local p = GSA1.pad
        local dead = GSA1.cv.pad_dead and GSA1.cv.pad_dead:GetFloat() or 0.2
        local lx, ly = p and tonumber(p.lx) or 0, p and tonumber(p.ly) or 0
        if math.sqrt(lx * lx + ly * ly) <= dead then return 0, 0 end
    end
    return sx, sy
end
W.prevStick = W.prevStick or GSA1.FilterStick
GSA1.FilterStick = function(C, sx, sy)
    sx, sy = W.Stick(C, sx, sy)
    if W.prevStick then sx, sy = W.prevStick(C, sx, sy) end
    return sx, sy
end

-- GSA1.BindOverride (cl_character.lua seam, 0.9.4a): the mouse wheel turns the pages while the wheel is open
W.prevBind = W.prevBind or GSA1.BindOverride
GSA1.BindOverride = function(ply, bind, pressed, code)
    if W.open and (bind == "invprev" or bind == "invnext") then
        if pressed ~= false then W.TurnPage(bind == "invnext" and 1 or -1, "the mouse wheel") end
        return true
    end
    if W.prevBind then return W.prevBind(ply, bind, pressed, code) end
    return nil
end

-- hooks ---------------------------------------------------------------------------------------------------------------------------
local function guard(name, fn)
    return GSA1.Guard and GSA1.Guard(name, fn) or fn
end
-- the wheel's input: before every tick of the character (GSA1PreTick runs in cl_character.lua's Think right after the
-- controller was read); without a character the wheel is closed by GSA1CharacterRemoved
hook.Add("GSA1PreTick", "gsa1_wheel", guard("wheel", function(C) W.Think() end))
hook.Add("InputMouseApply", "gsa1_wheel", guard("wheel mouse", function(cmd, x, y, ang)
    return W.MouseApply(cmd, x, y)
end))
-- the wheel key's own Garry's Mod bind (TAB = +showscores) does nothing while you are a character
hook.Add("PlayerBindPress", "gsa1_wheel", function(ply, bind, pressed, code)
    if not GSA1.Char or not cv.on:GetBool() then return end
    local k = cv.key:GetInt()
    if k <= 0 then return end
    if code ~= nil then
        if code == k then return true end
        return
    end
    local name = input and input.LookupKeyBinding and input.LookupKeyBinding(k)
    if name and bind and string.lower(name) == string.lower(bind) then return true end
end)
hook.Add("GSA1CharacterCreated", "gsa1_wheel", function(C, how)
    W.playing = nil
    local entry = C and C.name
    if entry and W.EntryOf(entry) and have() then
        local w = W.WheelOf(entry)
        log("%s's wheel: %d of 33 slots (%s)", W.Title(entry), W.UsedCount(w), W.data[entry] and "your file" or "the defaults")
    end
end)
local function stats_line(who)
    local s = W.stats
    if s.opened + s.played + s.refused + s.cancelled == 0 then return end
    log("%s: wheel opened %d times; %d animations played, %d refused, %d cancelled; %d face animations from the wheel",
        who, s.opened, s.played, s.refused, s.cancelled, s.faces)
    W.stats = { opened = 0, played = 0, refused = 0, cancelled = 0, faces = 0 }
end
hook.Add("GSA1CharacterLeaving", "gsa1_wheel", function(C, how)
    if W.open then W.Close("the character is " .. tostring(how or "leaving"), false) end
end)
hook.Add("GSA1CharacterRemoved", "gsa1_wheel", function(C)
    if W.open then W.Close("the character is gone", false) end
    W.playing = nil
    stats_line(C and C.title or "the character")
end)
hook.Add("ShutDown", "gsa1_wheel", function() stats_line("the session") end)

-- the face library changed (feat/cl_faces.lua): renamed faces renamed in every slot and the centre, deleted ones cleared
function W.FaceLibraryChanged(change)
    if type(change) ~= "table" then return end
    local ren, del = change.renamed or {}, change.deleted or {}
    local function fix(o)
        if not o or not o.face then return false end
        if ren[o.face] then
            o.face = ren[o.face]
            return true
        end
        if del[o.face] then
            o.face = nil
            return true
        end
        return false
    end
    local changed = false
    for _, c in ipairs(W.Entries()) do
        local uses = false
        local w = W.data[c.name] or W.DefaultWheel(c.name)
        for p = 1, W.PAGES do
            for s = 1, W.SLOTS do
                local o = w.pages[p][s]
                if o and o.face and (ren[o.face] or del[o.face]) then uses = true end
            end
        end
        if w.centre.face and (ren[w.centre.face] or del[w.centre.face]) then uses = true end
        if uses then
            w = W.Edit(c.name)
            for p = 1, W.PAGES do
                for s = 1, W.SLOTS do fix(w.pages[p][s]) end
            end
            fix(w.centre)
            changed = true
        end
    end
    if changed then
        W.Save()
        log("face animations renamed / deleted: the wheels follow")
    end
    if W.editor and W.editor.Refresh then W.editor.Refresh() end
end
hook.Add("GSA1FaceLibraryChanged", "gsa1_wheel", function(change) W.FaceLibraryChanged(change) end)

-- the keys: one the character uses is refused for the wheel key (the old key stays), the face trigger may not be the wheel key
function W.KeyRefused(code)
    local lookup = input and input.LookupBinding
    local keycode = input and input.GetKeyCode
    local sk = GetConVar("gsa1_super_key")
    return W.KeyRefusal(code, lookup and function(b) return lookup(b) end or nil,
        keycode and function(n) return keycode(n) end or nil, sk and sk:GetInt() or nil)
end
cvars.AddChangeCallback("gsa1_wheel_key", function(name, old, new)
    local why = W.KeyRefused(tonumber(new))
    local hk = cv.hide_key:GetInt()
    if not why and hk > 0 and tonumber(new) == hk then why = "the hide key" end     -- 0.9.4e
    if why then
        W.keyNote = string.format("%s is %s: the wheel key stays %s", W.KeyName(tonumber(new)), why, W.KeyName(tonumber(old)))
        log("%s", W.keyNote)
        if GSA1.Chat then GSA1.Chat("%s", W.keyNote) end
        RunConsoleCommand("gsa1_wheel_key", tostring(old))
    elseif tonumber(new) ~= tonumber(old) then
        W.keyNote = nil
    end
end, "gsa1_wheel")
cvars.AddChangeCallback("gsa1_wheel_face_key", function(name, old, new)
    local k = tonumber(new) or 0
    local hk = cv.hide_key:GetInt()
    if k > 0 and (k == cv.key:GetInt() or k == hk) then
        W.keyNote = string.format("%s is the %s: the face trigger stays %s", W.KeyName(k), k == hk and "hide key" or
            "wheel key", W.KeyName(tonumber(old)))
        log("%s", W.keyNote)
        RunConsoleCommand("gsa1_wheel_face_key", tostring(old))
    end
end, "gsa1_wheel")

-- hiding the wheel (round 0.9.4e) -----------------------------------------------------------------------------------------------
-- gsa1_wheel_hidden 1: the wheel works exactly as usual - the wheel key / button / +gsa1_wheel, pointing with the mouse, the
-- right stick or keys 1-8, the pages, the release, the face trigger, the centre, cancelling, everything it holds back from
-- the game - but W.HUDPaint draws nothing: no ring, no labels, no centre text, no pointer, no open / close fade, no toast.
-- Nothing else of G-SA1's HUD changes. The session log still says what played (a file, not the screen).
-- THE NOTE RULE (the owner records with it): turning hiding ON (the key or gsa1_wheel_hide_toggle) shows nothing at all -
-- anything on screen then would be in the recording; turning it OFF shows ONE small note ("the emote wheel is shown
-- again"; notification.AddLegacy, else a chat line) - so a note is never shown while the wheel is hidden. The check box on
-- the page changes it silently (the page is open: you see it). Both ways: a session log line.
function W.ToggleHidden(how)
    local on = not cv.hidden:GetBool()
    cv.hidden:SetBool(on)
    if not on then
        local text = "G-SA1: the emote wheel is shown again"
        if notification and notification.AddLegacy then
            notification.AddLegacy(text, NOTIFY_GENERIC or 0, 3)
        elseif GSA1.Chat then
            GSA1.Chat("the emote wheel is shown again")
        end
    end
    log("wheel %s by %s", on and "hidden" or "shown", tostring(how))
    return on
end
-- the toggle key: every frame (a Think hook: it works with or without a character); a press while a menu, the chat or a
-- panel has the input does nothing. Nothing allocated per frame
W.hideWas = false
function W.HideKeyThink()
    local k = cv.hide_key:GetInt()
    if k <= 0 then
        W.hideWas = false
        return
    end
    local d = key_down(k)
    if d and not W.hideWas and not W.Busy() then W.ToggleHidden("the hide key " .. W.KeyName(k)) end
    W.hideWas = d
end
cvars.AddChangeCallback("gsa1_wheel_hidden", function(name, old, new)
    if (tonumber(new) or 0) ~= 0 then
        -- nothing of the wheel stays on screen: the toast and the fade end now
        W.toastUntil, W.fadeFrom = 0, nil
    end
end, "gsa1_wheel")
-- the hide key may not be the wheel key, the face trigger or a key the character uses (the old key stays)
cvars.AddChangeCallback("gsa1_wheel_hide_key", function(name, old, new)
    local k = tonumber(new) or 0
    if k <= 0 then return end
    local why
    if k == cv.key:GetInt() then
        why = "the wheel key"
    elseif k == cv.face_key:GetInt() then
        why = "the face trigger"
    else
        why = W.KeyRefused(k)
    end
    if why then
        W.keyNote = string.format("%s is %s: the hide key stays %s", W.KeyName(k), why, W.KeyName(tonumber(old)))
        log("%s", W.keyNote)
        RunConsoleCommand("gsa1_wheel_hide_key", tostring(old))
    end
end, "gsa1_wheel")
hook.Add("Think", "gsa1_wheel_hide", guard("wheel hide key", function() W.HideKeyThink() end))
concommand.Add("gsa1_wheel_hide_toggle", function() W.ToggleHidden("the command gsa1_wheel_hide_toggle") end, nil,
    "G-SA1: hide or show the emote wheel (it keeps working while hidden; Q menu > Options > G-SA1 > Emote wheel)")

-- the HUD ---------------------------------------------------------------------------------------------------------------------------
-- Round 0.9.4b (objects2_plan.md 11.2; the owner: "The animation wheel's font doesn't resize with the wheel. The animation
-- wheel is bland looking and the font sucks."). The fonts: one per role (label, small, big, toast), made with
-- surface.CreateFont once per (role, font choice, pixel size) and kept (W.fontMade); W.Fonts() compares the screen height,
-- gsa1_wheel_size and gsa1_wheel_font with the last ones (three numbers a frame) and only when one changed picks - and, the
-- first time, makes - the fonts of the new size. Never a font per frame. The geometry (sectors, rims, the lit sector, the
-- centre, the face markers, the label places) is made once per screen and wheel size (W.Geometry).
W.fontMade = W.fontMade or {}
W.font = W.font or {}
W.fontBuilds = W.fontBuilds or 0
W.fit = W.fit or {}
function W.Fonts()
    local sh, size = ScrH(), cv.size:GetFloat()
    local choice = math.Clamp(cv.font:GetInt(), 0, #W.FONT_CHOICES - 1)
    if W.fontH == sh and W.fontS == size and W.fontC == choice and W.font.label then return W.font end
    W.fontH, W.fontS, W.fontC = sh, size, choice
    local px = W.FontSizes(sh, size)
    for _, role in ipairs(W.FONT_ROLES) do
        local name = W.FontName(role, choice, px[role])
        if not W.fontMade[name] and surface and surface.CreateFont then
            surface.CreateFont(name, W.FontData(role, choice, px[role]))
            W.fontMade[name] = true
        end
        W.font[role] = name
    end
    W.fontPx = px
    W.fit = {}
    W.fontBuilds = W.fontBuilds + 1
    return W.font
end
-- a new screen size: the fonts are made again (Garry's Mod's own advice after a resolution change) and the geometry
hook.Add("OnScreenSizeChanged", "gsa1_wheel", function()
    W.fontMade, W.fontH, W.geo = {}, nil, nil
end)

-- a text shortened with "..." to a pixel width in a role's font (cached per place and text until the fonts or the
-- geometry change; place: one cache per width, default the role)
local function fit(role, text, maxw, place)
    text = tostring(text or "")
    place = place or role
    local c = W.fit[place]
    if not c then
        c = {}
        W.fit[place] = c
    end
    local v = c[text]
    if v then return v end
    v = text
    if surface and surface.SetFont and surface.GetTextSize and W.font[role] then
        surface.SetFont(W.font[role])
        if (surface.GetTextSize(v) or 0) > maxw then
            for n = #text - 1, 3, -1 do
                v = string.sub(text, 1, n) .. "..."
                if (surface.GetTextSize(v) or 0) <= maxw then break end
            end
        end
    end
    c[text] = v
    return v
end
W.Fit = fit

-- the wheel's shapes for the screen and the size (made again only when one changes)
function W.Geometry()
    local sw, sh, size = ScrW(), ScrH(), cv.size:GetFloat()
    local g = W.geo
    if g and g.sw == sw and g.sh == sh and g.size == size then return g end
    local rout, rin = W.Radii(sh, size)
    local cx, cy = sw / 2, sh / 2
    g = { sw = sw, sh = sh, size = size, cx = cx, cy = cy, rin = rin, rout = rout }
    local gap = 1.6                                    -- degrees between the sectors: the separators
    local rim = math.max(2, rout * 0.012)
    g.rlit = rout * 1.045                              -- the lit sector stands out a little
    g.sectors = W.SectorQuads(cx, cy, rin, rout, gap, 6)
    g.rims = W.SectorQuads(cx, cy, rout - rim, rout, gap, 6)
    g.lit = W.SectorQuads(cx, cy, rin * 0.985, g.rlit, gap, 6)
    g.litRims = W.SectorQuads(cx, cy, g.rlit - rim * 1.5, g.rlit, gap, 6)
    g.seps = W.SeparatorQuads(cx, cy, rin + rim, rout - rim, math.max(1, rout * 0.0035))
    g.rd = rin * 0.93                                  -- the centre's glass
    g.disc = W.Disc(cx, cy, g.rd, 48)
    g.ring = W.RingQuads(cx, cy, g.rd, g.rd + math.max(2, rout * 0.007), 48)
    g.lab, g.num, g.marks = {}, {}, {}
    local mr = math.max(3, rout * 0.02)
    for s = 1, W.SLOTS do
        local a = W.AngleOfSlot(s)
        local x, y = W.Polar(cx, cy, rin + (rout - rin) * 0.52, a)
        g.lab[s] = { x = x, y = y }
        x, y = W.Polar(cx, cy, rin + (rout - rin) * 0.15, a)
        g.num[s] = { x = x, y = y }
        x, y = W.Polar(cx, cy, rout - (rout - rin) * 0.13, a)
        g.marks[s] = W.Disc(x, y, mr, 12)
    end
    -- the widths a label may take: the sector's chord at the label's radius, at most the ring's depth
    g.labW = math.min(2 * (rin + (rout - rin) * 0.52) * math.sin(math.rad(22.5)) * 0.86, (rout - rin) * 0.92)
    g.bigW, g.smallW = g.rd * 1.8, g.rd * 1.85
    W.geo = g
    W.fit = {}
    return g
end

-- the colours the HUD changes every frame (alpha of the fade): reused tables, no garbage per frame
local T_WHITE, T_DIM, T_GOLD, T_SHADOW, T_DARK = Color(255, 255, 255), Color(196, 202, 214), Color(255, 206, 72),
    Color(0, 0, 0), Color(20, 22, 30)
local function tint(t, r, g, b, a)
    t.r, t.g, t.b, t.a = r, g, b, math.floor(math.Clamp(a, 0, 255))
    return t
end
-- centred text with a soft shadow
local function stext(text, font, x, y, col, off)
    draw.SimpleText(text, font, x + off, y + off, T_SHADOW, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(text, font, x, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- what a slot shows: its internal name, "(stop)", "-" or "missing: <name>"
function W.SlotText(slot, list, n)
    if not slot or not slot.body then return "-" end
    if slot.body == "stop" then return "(stop)" end
    local e, why = slot_entry(slot, list)
    if not e then return W.Shorten(why == "the catalogue is not loaded" and (slot.name or slot.body) or why, n or 14) end
    return W.Shorten(e.name ~= "" and e.name or e.key, n or 14)
end
-- does the loaded module hold poses (feature "emote" 2: gsa1.EMOTE.HOLD)
function W.HoldSupported()
    return emote_const("HOLD", 0) ~= 0
end
-- how a slot's animation plays, in words ("loops", "holds its last pose", "plays once")
function W.PlaysText(slot, e)
    if not e then return "" end
    if (slot and slot.loop) or e.play == "loop" then return "loops" end
    if W.HoldApplies(slot, e) and W.HoldSupported() then return "holds its last pose" end
    return "plays once"
end
-- the centre's lines for the highlighted slot (or the centre)
function W.CentreLines()
    local out = {}
    if W.sel == 0 then
        local f = W.wheel.centre and W.wheel.centre.face
        out[1] = f and ("face: " .. f) or W.Title(W.entry)
        out[2] = f and "LT / click: this face" or "release here: nothing"
        return out
    end
    local slot = W.wheel.pages[W.page][W.sel]
    if not slot or not slot.body then
        out[1] = slot and slot.face and "-" or "(empty)"
    elseif slot.body == "stop" then
        out[1] = "(stop)"
        out[2] = "back to the game's pose"
    else
        local e, why = slot_entry(slot, W.list)
        if e then
            out[1] = e.name ~= "" and e.name or e.key
            out[2] = string.format("%s - %d frames", e.source == 1 and ("extra " .. e.index) or ("#" .. e.index),
                tonumber(e.frames) or 0)
            out[3] = W.PlaysText(slot, e)
            -- 0.9.4e: the play rate when it is not the game's
            local rate = W.PlayRate(slot, cv.speed:GetFloat())
            if rate ~= 1 and W.SpeedSupported() then out[3] = out[3] .. ", at " .. W.SpeedText(rate) end
        else
            out[1] = why
        end
    end
    if slot and slot.face then out[#out + 1] = "face: " .. slot.face end
    return out
end
function W.HintLine()
    local F = GSA1.Faces
    local faces = F ~= nil and F.Play ~= nil and (not F.HasFaces or F.HasFaces(W.entry))
    local pages = W.wheel and #W.Pages(W.wheel) > 1
    return string.format("release: play%s - right click / B: cancel%s", faces and string.format(" - %s / %s: with its face",
        W.PadTitleShort(cv.face_pad:GetInt()), W.KeyName(cv.face_key:GetInt())) or "",
        pages and " - mouse wheel / LB / RB: pages" or "")
end
function W.PadTitleShort(b)
    local t = W.PadTitle(b)
    return string.match(t, "%((%u+)%)") or t
end

-- the accent colour of the open wheel: the character's, gold while he is Super (both Super Sonics, and Sonic turned Super)
function W.AccentNow()
    local C = W.char
    return W.Accent(W.entry, C ~= nil and C.superForm == true)
end

-- the pointer: a small accent triangle on the centre's ring toward the mouse / the stick (reused table)
local needle = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local function set_needle(g, deg)
    local w = 7
    needle[1].x, needle[1].y = W.Polar(g.cx, g.cy, g.rd + 1, deg - w)
    needle[2].x, needle[2].y = W.Polar(g.cx, g.cy, g.rin * 0.985, deg)
    needle[3].x, needle[3].y = W.Polar(g.cx, g.cy, g.rd + 1, deg + w)
    return needle
end
W.NeedlePoly = set_needle

-- the wheel at k (0..1: the open / close animation's strength), every frame while it is open or fading out
function W.PaintWheel(g, f, k, dt)
    local acc = W.AccentNow()
    local bgA = 255 * math.Clamp(cv.opacity:GetFloat(), 0, 1) * k
    if draw and draw.NoTexture then draw.NoTexture() end
    local page = W.wheel.pages[W.page] or {}
    W.glow = W.glow or {}
    for s = 1, W.SLOTS do
        local gl = W.GlowStep(W.glow[s] or 0, (W.open and s == W.sel) and 1 or 0, dt)
        W.glow[s] = gl
        local used = W.SlotUsed(page[s])
        -- dark glass (an empty slot fainter), then the accent edge; the gaps between the sectors are the separators
        surface.SetDrawColor(14, 16, 22, bgA * (used and 1 or 0.72))
        for _, q in ipairs(g.sectors[s]) do surface.DrawPoly(q) end
        surface.SetDrawColor(acc[1], acc[2], acc[3], (used and 90 or 45) * k)
        for _, q in ipairs(g.rims[s]) do surface.DrawPoly(q) end
        -- the highlight: the slot lit in the accent colour, a little larger, with a bright edge; it fades in and out
        if gl > 0.02 then
            surface.SetDrawColor(acc[1], acc[2], acc[3], 200 * gl * k)
            for _, q in ipairs(g.lit[s]) do surface.DrawPoly(q) end
            surface.SetDrawColor(255, 255, 255, 190 * gl * k)
            for _, q in ipairs(g.litRims[s]) do surface.DrawPoly(q) end
        end
        -- a face animation goes with this slot: a gold marker near the rim
        if page[s] and page[s].face then
            surface.SetDrawColor(255, 206, 72, 235 * k)
            surface.DrawPoly(g.marks[s])
        end
    end
    -- the separators: a thin light line in each gap (seen on dark and bright backgrounds alike)
    surface.SetDrawColor(255, 255, 255, 46 * k)
    for _, q in ipairs(g.seps) do surface.DrawPoly(q) end
    -- the centre: darker glass, an accent ring (bright when the centre is chosen), the pointer
    surface.SetDrawColor(8, 9, 13, math.min(255, bgA * 1.15))
    surface.DrawPoly(g.disc)
    surface.SetDrawColor(acc[1], acc[2], acc[3], ((W.open and W.sel == 0) and 230 or 110) * k)
    for _, q in ipairs(g.ring) do surface.DrawPoly(q) end
    if W.open and W.pointDeg then
        surface.SetDrawColor(acc[1], acc[2], acc[3], 230 * k)
        surface.DrawPoly(set_needle(g, W.pointDeg))
    end
    -- page markers above the wheel
    local px = W.fontPx or W.FontSizes(g.sh, g.size)
    local pages = W.Pages(W.wheel)
    if #pages > 1 and surface.DrawRect then
        local pw, ph, pg = math.floor(px.small * 1.4), math.max(3, math.floor(px.small * 0.22)), math.floor(px.small * 0.5)
        local x0 = math.floor(g.cx - (#pages * pw + (#pages - 1) * pg) / 2)
        local y0 = math.floor(g.cy - g.rlit - px.small * 0.9)
        for i, p in ipairs(pages) do
            if p == W.page then
                surface.SetDrawColor(acc[1], acc[2], acc[3], 255 * k)
            else
                surface.SetDrawColor(190, 196, 210, 120 * k)
            end
            surface.DrawRect(x0 + (i - 1) * (pw + pg), y0, pw, ph)
        end
    end
    if not (draw and draw.SimpleText) then return end
    tint(T_SHADOW, 0, 0, 0, 170 * k)
    local white, dim, gold = tint(T_WHITE, 255, 255, 255, 255 * k), tint(T_DIM, 196, 202, 214, 225 * k),
        tint(T_GOLD, 255, 206, 72, 255 * k)
    local dark = tint(T_DARK, 16, 18, 26, 255 * k)
    local off = math.max(1, math.floor(px.label / 16))
    for s = 1, W.SLOTS do
        local slot, lp, np = page[s], g.lab[s], g.num[s]
        local lit = (W.glow[s] or 0) > 0.5
        stext(tostring(s), f.small, np.x, np.y, lit and white or dim, off)
        local text = fit("label", W.SlotText(slot, W.list, 40), g.labW)
        stext(text, f.label, lp.x, lp.y, (W.SlotUsed(slot) or lit) and white or dim, off)
        if slot and slot.face then
            stext(fit("small", slot.face, g.labW, "face"), f.small, lp.x, lp.y + px.label * 0.95, lit and dark or gold, off)
        end
    end
    -- the centre: the name large, then what it is, then its face animation
    local lines = W.CentreLines()
    local y = g.cy - (#lines > 1 and px.big * 0.45 or 0)
    stext(fit("big", lines[1] or "", g.bigW), f.big, g.cx, y, white, off + 1)
    y = y + px.big * 0.5 + px.small * 0.75
    for i = 2, #lines do
        local face = string.sub(lines[i], 1, 6) == "face: "
        stext(fit("small", lines[i], g.smallW, "centre"), f.small, g.cx, y, face and gold or dim, off)
        y = y + px.small * 1.2
    end
    -- the hint below
    stext(W.HintLine(), f.small, g.cx, g.cy + g.rlit + px.small * 1.3, dim, off)
end

-- k: 0..1 the animation; closing: the fade after the wheel closed (the last state, a little larger)
function W.DrawWheel(k, closing)
    k = math.Clamp(tonumber(k) or 1, 0, 1)
    local g = W.Geometry()
    local f = W.Fonts()
    local dt = RealFrameTime and RealFrameTime() or (1 / 60)
    local scale = closing and (1 + 0.04 * (1 - k)) or (0.9 + 0.1 * k)
    local pushed = false
    if scale ~= 1 and cam and cam.PushModelMatrix and Matrix and Vector then
        local m = Matrix()
        m:Translate(Vector(g.cx, g.cy, 0))
        m:Scale(Vector(scale, scale, 1))
        m:Translate(Vector(-g.cx, -g.cy, 0))
        cam.PushModelMatrix(m)
        pushed = true
    end
    local ok, err = pcall(W.PaintWheel, g, f, k, dt)
    if pushed then cam.PopModelMatrix() end
    if not ok then error(err, 0) end
end

function W.DrawToast()
    local sw, sh = ScrW(), ScrH()
    local f = W.Fonts()
    local left = (W.toastUntil or 0) - SysTime()
    local a = math.Clamp(left / 0.3, 0, 1)
    if draw and draw.SimpleTextOutlined then
        draw.SimpleTextOutlined(W.toastText, f.toast, sw / 2, sh * 0.66, tint(T_WHITE, 255, 255, 255, 255 * a),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, tint(T_SHADOW, 0, 0, 0, 200 * a))
    end
end

-- while open: the opening animation (W.OPEN_TIME); after a close: the fade out (W.CLOSE_TIME); otherwise nothing
function W.HUDPaint()
    -- 0.9.4e: hidden - nothing at all (the wheel, its fade, the toast); the wheel works on (W.Think and the seams do not
    -- read this setting)
    if cv.hidden:GetBool() then
        W.fadeFrom = nil
        return
    end
    local now = SysTime()
    if W.open then
        W.DrawWheel(W.Ease((now - (W.openAt or now)) / W.OPEN_TIME), false)
    elseif W.fadeFrom and W.wheel then
        local t = (now - W.fadeFrom) / W.CLOSE_TIME
        if t < 1 then
            W.DrawWheel(1 - W.Ease(t), true)
        else
            W.fadeFrom = nil
        end
    end
    if W.toastText and now < (W.toastUntil or 0) then W.DrawToast() end
end
hook.Add("HUDPaint", "gsa1_wheel", guard("wheel HUD", function() W.HUDPaint() end))

-- console ---------------------------------------------------------------------------------------------------------------------------
concommand.Add("+gsa1_wheel", function() W.cmdDown = true end, nil, "G-SA1: hold the emote wheel open (bind a key to it)")
concommand.Add("-gsa1_wheel", function() W.cmdDown = false end)

-- an animation of the current character by key ("a75", "x3"), number ("75") or internal name; nil, why
function W.Find(C, what)
    local list = W.ListOf(C.name)
    if not list then return nil, "the animation list is not loaded (the disc, or a module without the emote feature)" end
    what = string.Trim(tostring(what or ""))
    if what == "" then return nil, "which animation? (a name like s_wait3, a number or a key like a3)" end
    if string.match(what, "^%d+$") then what = "a" .. what end
    local e = W.Index(list).byKey[what]
    if e then return e end
    e = W.Resolve(list, "-none-", what)
    if e then return e end
    return nil, string.format("%s has no animation %s", W.Title(C.name), what)
end
concommand.Add("gsa1_emote", function(_, _, args, argstr)
    local C = GSA1.Char
    if not C then GSA1.Chat("emote: no character") return end
    if not have() then GSA1.Chat("emote: %s", GSA1.MissingFeatureText and GSA1.MissingFeatureText(W.NEEDS) or "needs a newer module") return end
    local e, why = W.Find(C, argstr or (args and args[1]))
    if not e then GSA1.Chat("emote: %s", why) return end
    W.PlayBody(C, { body = e.key, name = e.name }, 0, 0, "the command gsa1_emote", nil, C.name)
end, nil, "G-SA1: play one of your character's animations (internal name, number or key; the Emote wheel page lists them; "
    .. "at the play rate of every animation, gsa1_wheel_speed)")
concommand.Add("gsa1_emote_stop", function()
    local C = GSA1.Char
    if not C or not have() then return end
    gsa1.EmoteStop(C.id, emote_const("STOP_NOW", 0))
    log("stopped (the command gsa1_emote_stop)")
end, nil, "G-SA1: stop the animation your character plays")

-- the page: Q menu > Options > G-SA1 > Emote wheel ----------------------------------------------------------------------------
-- the groups of the list's filter: All, the classes (gsa1.EMOTE.CLASS_*'s words), then the rows that cannot play yet
W.GROUPS = { "All", "stand", "idle", "pose", "move", "air", "brake", "ball", "attack", "carry", "setpiece", "hurt", "fish",
             "swim", "board", "super", "not usable yet" }
W.NOT_USABLE = "not usable yet"

-- the rows the page lists for an entry: every catalogue entry, the game's variants of one motion folded into the first
-- (by dup: the same drawn object and motion - never by name, review R.9), and the rows that cannot play (cl_wheel_rows.lua,
-- owner answer FQ19: greyed, with the reason). r = { e (the catalogue entry; nil when greyed), key, num, extra, name,
-- frames, plays, group, greyed (the reason), variants = { entries } }
function W.PageRows(entry, list)
    local rows = {}
    local offered = {}
    list = W.Index(list)
    if list then
        local reps = {}
        for i = 1, tonumber(list.n) or #list do
            local e = list[i]
            local d = tonumber(e.dup) or 0
            if e.source == 0 then offered[e.index] = true end
            if d > 0 and reps[d] then
                local v = reps[d].variants
                v[#v + 1] = e
            else
                local r = { e = e, key = e.key, num = e.index, extra = e.source == 1, name = e.name ~= "" and e.name or
                    ("(no name) " .. e.key), frames = tonumber(e.frames) or 0, plays = tostring(e.play or ""),
                    group = tostring(e.group or "?"), variants = {} }
                reps[i] = r
                rows[#rows + 1] = r
            end
        end
    end
    for _, u in ipairs(W.UNPLAYABLE and W.UNPLAYABLE[entry] or {}) do
        if not offered[u[1]] then
            rows[#rows + 1] = { key = "a" .. u[1], num = u[1], name = u[2] ~= "" and u[2] or ("(empty) a" .. u[1]),
                                frames = "", plays = "", group = W.NOT_USABLE, greyed = u[3], variants = {} }
        end
    end
    table.sort(rows, function(a, b)
        local ka, kb = (a.extra and 100000 or 0) + a.num, (b.extra and 100000 or 0) + b.num
        return ka < kb
    end)
    return rows
end

-- a row's tooltip: the SA Tools label and the folded variants; a greyed row's reason
function W.RowTip(r)
    if r.greyed then return r.name .. ": " .. r.greyed end
    local t = r.e and r.e.label ~= "" and r.e.label or r.name
    if #r.variants > 0 then
        local v = {}
        for _, e in ipairs(r.variants) do v[#v + 1] = e.source == 1 and ("x" .. e.index) or ("#" .. e.index) end
        t = string.format("%s (+%d variant%s: %s - the game's own copies of this motion)", t, #r.variants,
            #r.variants == 1 and "" or "s", table.concat(v, ", "))
    end
    return t
end

-- where an entry's wheel has each animation: { [the folded row's key] = "p1 s3, p2 s1" }
function W.OnWheel(entry, list)
    local out = {}
    list = W.Index(list)
    if not list then return out end
    local w = W.WheelOf(entry)
    for p = 1, W.PAGES do
        for s = 1, W.SLOTS do
            local e = W.Resolve(list, w.pages[p][s].body, w.pages[p][s].name)
            if e then
                local d = tonumber(e.dup) or 0
                local rep = d > 0 and list[d] or e
                out[rep.key] = (out[rep.key] and (out[rep.key] .. ", ") or "") .. string.format("p%d s%d", p, s)
            end
        end
    end
    return out
end

-- does a row match the find box (a part of its name, its number or key) and the group filter
function W.RowMatches(r, find, group)
    if group and group ~= "" and group ~= "All" and r.group ~= group then return false end
    find = string.lower(string.Trim(tostring(find or "")))
    if find == "" then return true end
    if string.find(string.lower(r.name), find, 1, true) then return true end
    if find == tostring(r.num) or find == r.key or find == "#" .. tostring(r.num) then return true end
    return false
end

local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[2], tostring(c[1])) end
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand(cvname, tostring(data))
    end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local c = GetConVar(cvname)
        local v = c and c:GetString() or ""
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        local n = tonumber(v)
        for _, ch in ipairs(choices) do
            if n ~= nil and tonumber(ch[1]) == n then
                self:SetText(ch[2])
                return
            end
        end
        self:SetText(v)
    end
    return combo
end

local function live_label(panel, lines_fn)
    local lbl = panel:Help("...")
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + 0.5
        local text = table.concat(lines_fn(), "\n")
        if text ~= self.gsa1Text then
            self.gsa1Text = text
            self:SetText(text)
            if self.InvalidateLayout then self:InvalidateLayout(true) end
            local parent = self.GetParent and self:GetParent()
            if IsValid(parent) and parent.InvalidateLayout then parent:InvalidateLayout() end
        end
    end
    return lbl
end

local function binder(panel, cvname)
    local b = vgui.Create("DBinder", panel)
    if b.SetConVar then b:SetConVar(cvname) end
    if b.SetTall then b:SetTall(28) end
    panel:AddItem(b)
    return b
end

-- the entry the page starts with: the current character's, else the character setting's
local function current_entry()
    local C = GSA1.Char
    if C and C.name and W.EntryOf(C.name) then return C.name end
    local c = GSA1.CharacterByName and GSA1.CharacterByName(GSA1.cv and GSA1.cv.character and
        GSA1.cv.character:GetString() or "sonic")
    return c and c.name or "sonic"
end
W.CurrentEntry = current_entry

-- the page's lines (status)
function W.StatusLines(E)
    local out = {}
    if not have() then
        out[1] = GSA1.MissingFeatureText and GSA1.MissingFeatureText(W.NEEDS) or "needs G-SA1 module 0.9.4a"
        return out
    end
    local entry = E and E.entry or current_entry()
    local list = W.ListOf(entry)
    local rows = list and W.PageRows(entry, list) or {}
    local grey = 0
    for _, r in ipairs(rows) do if r.greyed then grey = grey + 1 end end
    local w = W.WheelOf(entry)
    out[#out + 1] = string.format("%s: %s animations%s; the wheel uses %d of 33 slots (%s)", W.Title(entry),
        list and tostring(tonumber(list.n) or #list) or "?", grey > 0 and string.format(" (%d more can't play yet)", grey)
        or "", W.UsedCount(w), W.data[entry] and "your changes" or "the defaults")
    out[#out + 1] = string.format("wheel: %s%s; key %s, controller %s; face trigger %s / %s; hide key %s", cv.on:GetBool() and
        "on" or "off", cv.hidden:GetBool() and " (hidden: it works but draws nothing)" or "", W.KeyName(cv.key:GetInt()),
        W.PadTitle(cv.pad:GetInt()), W.KeyName(cv.face_key:GetInt()), W.PadTitle(cv.face_pad:GetInt()),
        W.KeyName(cv.hide_key:GetInt()))
    -- 0.9.4e: the play rate
    local g = cv.speed:GetFloat()
    if not W.SpeedSupported() then
        out[#out + 1] = string.format("play rates: need G-SA1 module %s (feature \"emote\" %d); this one plays every "
            .. "animation at the game's rate", W.SPEED_NEEDS.module, W.SPEED_NEEDS.version)
    elseif g ~= 1 then
        out[#out + 1] = string.format("play rate of every animation: %s (times each slot's own)", W.SpeedText(g))
    end
    if (W.badLines or 0) > 0 then
        out[#out + 1] = string.format("%d line%s of emote_wheel.txt %s not understood (%s)", W.badLines,
            W.badLines == 1 and "" or "s", W.badLines == 1 and "was" or "were", table.concat(W.badNotes or {}, "; "))
    end
    if W.keyNote then out[#out + 1] = W.keyNote end
    if E and E.note then out[#out + 1] = E.note end
    if W.playing then out[#out + 1] = "last played: " .. tostring(W.playing.name ~= "" and W.playing.name or W.playing.key) end
    local m = cv.summary:GetString()
    out[#out + 1] = "your changed wheels: " .. (m ~= "" and m or "none")
    return out
end

-- the little wheel of the page (its own coordinates; the selected slot filled)
local function paint_mini(self, w, h, E)
    local size = math.min(w, h)
    local cx, cy = w / 2, h / 2
    local rout, rin = size * 0.48, size * 0.48 * 0.4
    local qk = string.format("%d %d", w, h)
    if self.gsa1Key ~= qk then
        self.gsa1Quads = W.SectorQuads(cx, cy, rin, rout, 2, 4)
        local disc = {}
        for i = 0, 23 do
            local a = math.rad(i * 15)
            disc[#disc + 1] = { x = cx + math.sin(a) * rin * 0.9, y = cy - math.cos(a) * rin * 0.9 }
        end
        self.gsa1Disc, self.gsa1Key = disc, qk
    end
    local col = W.Accent(E.entry, false)
    if draw and draw.NoTexture then draw.NoTexture() end
    local wheel = W.WheelOf(E.entry)
    local list = W.ListOf(E.entry)
    for s = 1, W.SLOTS do
        if E.sel == s then
            surface.SetDrawColor(col[1], col[2], col[3], 255)
        else
            surface.SetDrawColor(18, 20, 28, W.SlotUsed(wheel.pages[E.page][s]) and 235 or 170)
        end
        for _, q in ipairs(self.gsa1Quads[s]) do surface.DrawPoly(q) end
    end
    if E.sel == 0 then surface.SetDrawColor(col[1], col[2], col[3], 255) else surface.SetDrawColor(10, 11, 16, 240) end
    surface.DrawPoly(self.gsa1Disc)
    if not (draw and draw.SimpleText) then return end
    for s = 1, W.SLOTS do
        local x, y = W.LabelPos(cx, cy, rin, rout, s)
        local slot = wheel.pages[E.page][s]
        draw.SimpleText(tostring(s), "DermaDefault", x, y - 8, Color(200, 200, 200, 255), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
        draw.SimpleText(W.SlotText(slot, list, 11), "DermaDefault", x, y + 4, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
        -- the face marker and (0.9.4e) the slot's play rate when it is not 1x
        local sp = W.SlotSpeed(slot)
        if slot.face or sp ~= 1 then
            draw.SimpleText((slot.face and ":)" or "") .. (sp ~= 1 and ((slot.face and " " or "") .. W.SpeedText(sp)) or ""),
                "DermaDefault", x, y + 16, Color(255, 210, 60, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    local cf = wheel.centre.face
    draw.SimpleText(cf and (":) " .. W.Shorten(cf, 10)) or "centre", "DermaDefault", cx, cy, Color(255, 255, 255, 255),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- the page's editor: the wheel being edited (any entry, no character needed), its page and slot (0 = the centre), the
-- actions of the page's controls. Its controls (E.list, E.selLine, E.loopBox, E.faceCombo, ...) are set by W.BuildPage;
-- without them (a test) the actions still edit the wheels.
function W.NewEditor(entry)
    local E = { entry = entry or current_entry(), page = 1, sel = 1 }
    local function valid() return W.editor == E and (E.list == nil or IsValid(E.list)) end
    function E.Wheel() return W.WheelOf(E.entry) end
    function E.Slot()
        if E.sel == 0 then return nil end
        return E.Wheel().pages[E.page][E.sel]
    end
    -- the list, filtered by the find box and the group
    function E.Fill()
        if not valid() or not E.list then return end
        local l = E.list
        if l.Clear then l:Clear() end
        local glist = W.ListOf(E.entry)
        local rows = W.PageRows(E.entry, glist)
        local on = W.OnWheel(E.entry, glist)
        local find = E.find and E.find.GetValue and E.find:GetValue() or ""
        if type(find) ~= "string" then find = "" end
        E.shown = {}
        for _, r in ipairs(rows) do
            if W.RowMatches(r, find, E.groupValue) then
                local line = l:AddLine(r.extra and ("x" .. r.num) or tostring(r.num), r.name, tostring(r.frames), r.plays,
                    r.group, on[r.key] or "")
                if line then
                    line.gsa1Row = r
                    if line.SetTooltip then line:SetTooltip(W.RowTip(r)) end
                    if r.greyed then
                        if line.SetSelectable then line:SetSelectable(false) end
                        if type(line.Columns) == "table" then
                            for _, lab in pairs(line.Columns) do
                                if type(lab) == "table" and lab.SetTextColor then lab:SetTextColor(Color(150, 150, 150, 255)) end
                            end
                        end
                    end
                end
                E.shown[#E.shown + 1] = { row = r, line = line }
            end
        end
    end
    -- the controls follow the wheel (after every change)
    function E.Refresh()
        if not valid() then return end
        E.syncing = true
        for p, b in ipairs(E.pageButtons or {}) do
            if b.SetText then b:SetText((p == E.page and "> " or "") .. "Page " .. p) end
        end
        local w = E.Wheel()
        local glist = W.ListOf(E.entry)
        local F = GSA1.Faces
        local faces = F ~= nil and F.Library ~= nil and (not F.HasFaces or F.HasFaces(E.entry))
        local slot = E.Slot()
        if E.selLine and E.selLine.SetText then
            if E.sel == 0 then
                E.selLine:SetText("The centre: no animation, only its face animation (the face trigger with nothing "
                    .. "highlighted)")
            else
                local text
                if not slot or not slot.body then
                    text = "-"
                elseif slot.body == "stop" then
                    text = "(stop)"
                else
                    local e, why = W.SlotEntry(slot, glist)
                    text = e and string.format("%s  #%s  %d frames, %s%s", e.name, e.source == 1 and ("x" .. e.index) or
                        tostring(e.index), tonumber(e.frames) or 0, W.PlaysText(slot, e), W.SlotSpeed(slot) ~= 1 and
                        (", " .. W.SpeedText(W.SlotSpeed(slot))) or "") or why
                end
                E.selLine:SetText(string.format("Page %d, slot %d: %s", E.page, E.sel, text))
            end
        end
        if E.loopBox then
            if E.loopBox.SetChecked then E.loopBox:SetChecked(slot ~= nil and slot.loop == true) end
            if E.loopBox.SetEnabled then E.loopBox:SetEnabled(E.sel ~= 0) end
        end
        -- 0.9.4b: "Hold the last pose" - on unless switched off; it matters for an animation that plays once and is not
        -- looped (greyed otherwise, and without a module that holds)
        if E.holdBox then
            local e = slot and slot.body and slot.body ~= "stop" and W.SlotEntry(slot, glist) or nil
            local can = E.sel ~= 0 and slot ~= nil and slot.body ~= nil and slot.body ~= "stop" and not slot.loop and
                (e == nil or e.play ~= "loop") and W.HoldSupported()
            if E.holdBox.SetChecked then E.holdBox:SetChecked(E.sel ~= 0 and slot ~= nil and not slot.nohold) end
            if E.holdBox.SetEnabled then E.holdBox:SetEnabled(can and true or false) end
        end
        if E.holdNote and E.holdNote.SetText then
            E.holdNote:SetText(E.HoldNote())
        end
        -- 0.9.4e: the slot's play rate (a slot with an animation; the module must take it)
        local sc = E.speedCombo
        if sc then
            if sc.Clear then sc:Clear() end
            local cur = W.SlotSpeed(slot)
            for _, v in ipairs(W.SPEEDS) do
                sc:AddChoice(W.SpeedText(v) .. (v == 1 and " (the game's rate)" or ""), tostring(v), v == cur)
            end
            local can = E.sel ~= 0 and slot ~= nil and slot.body ~= nil and slot.body ~= "stop" and W.SpeedSupported()
            if sc.SetEnabled then sc:SetEnabled(can and true or false) end
            if sc.SetValue then sc:SetValue(W.SpeedText(cur) .. (cur == 1 and " (the game's rate)" or "")) end
        end
        if E.speedNote and E.speedNote.SetText then
            E.speedNote:SetText(E.SpeedNote())
        end
        local fc = E.faceCombo
        if fc then
            if fc.Clear then fc:Clear() end
            local cur = E.sel == 0 and w.centre.face or (slot and slot.face)
            fc:AddChoice("none", "-", cur == nil)
            if faces then
                for _, a in ipairs(F.Library() or {}) do
                    local can = true
                    if F.CanShow then can = F.CanShow(a.name, E.entry) end
                    fc:AddChoice(can == false and (a.name .. " (can't show)") or a.name, a.name, cur == a.name)
                end
            end
            if fc.SetEnabled then fc:SetEnabled(faces and true or false) end
            if fc.SetValue then fc:SetValue(cur or "none") end
        end
        if E.faceNote and E.faceNote.SetText then
            if F == nil or F.Library == nil then
                E.faceNote:SetText("Face animations come with the Faces page (G-SA1's feature \"faces\").")
            elseif not faces then
                local c = W.EntryOf(E.entry)
                E.faceNote:SetText(string.format("%s has no face in the game: no face animations.", c and c.kind == 6 and
                    "E-102" or "Super Sonic"))
            else
                E.faceNote:SetText("Face animations are made on the Faces page; the face trigger plays this one with the "
                    .. "slot's animation.")
            end
        end
        E.syncing = false
        E.Fill()
    end
    function E.SetEntry(name)
        if not W.EntryOf(name) then return false end
        E.entry, E.page, E.sel, E.note = name, 1, 1, nil
        E.Refresh()
        return true
    end
    function E.SetPage(p)
        E.page = math.Clamp(math.floor(tonumber(p) or 1), 1, W.PAGES)
        E.Refresh()
    end
    function E.Select(s)
        E.sel = math.Clamp(math.floor(tonumber(s) or 0), 0, W.SLOTS)
        E.note = nil
        E.Refresh()
    end
    -- a row into slot s of the shown page (default: the selected slot, and then the next slot is selected)
    function E.Assign(r, s)
        if r.greyed then
            E.note = r.name .. " cannot go on the wheel: " .. r.greyed
            E.Refresh()
            return false
        end
        local target = s or E.sel
        if target == 0 then
            E.note = "the centre has only a face animation: pick a slot (1-8) for an animation"
            E.Refresh()
            return false
        end
        local w = W.Edit(E.entry)
        local slot = w.pages[E.page][target]
        slot.body, slot.name = r.e.key, r.e.name ~= "" and r.e.name or nil
        W.Save()
        log("%s's wheel: page %d slot %d = %s (%s)", W.Title(E.entry), E.page, target, tostring(r.e.name), r.e.key)
        if not s then E.sel = target % W.SLOTS + 1 end
        E.note = nil
        E.Refresh()
        return true
    end
    function E.Clear()
        local w = W.Edit(E.entry)
        if E.sel == 0 then
            w.centre.face = nil
        else
            w.pages[E.page][E.sel] = {}
        end
        W.Save()
        E.Refresh()
    end
    function E.ClearPage()
        local w = W.Edit(E.entry)
        for s = 1, W.SLOTS do w.pages[E.page][s] = {} end
        W.Save()
        E.Refresh()
    end
    function E.Reset()
        W.ResetEntry(E.entry)
        E.note = W.Title(E.entry) .. "'s wheel: the defaults again"
        E.Refresh()
    end
    function E.SetLoop(on)
        if E.sel == 0 then return end
        local w = W.Edit(E.entry)
        w.pages[E.page][E.sel].loop = on and true or nil
        W.Save()
        E.Refresh()
    end
    -- 0.9.4b: the slot's "Hold the last pose" (on by default: only "off" is kept, as the file's option nohold)
    function E.SetHold(on)
        if E.sel == 0 then return end
        local w = W.Edit(E.entry)
        w.pages[E.page][E.sel].nohold = (not on) or nil
        W.Save()
        log("%s's wheel: page %d slot %d holds its last pose: %s", W.Title(E.entry), E.page, E.sel, on and "on" or "off")
        E.Refresh()
    end
    -- 0.9.4e: the slot's play rate (W.SPEEDS; 1 = the game's rate: not written to the file)
    function E.SetSpeed(v)
        v = tonumber(v)
        if E.sel == 0 then return false end
        if not v or v ~= v or v < W.SPEED_MIN or v > W.SPEED_MAX then
            E.note = string.format("a slot's play rate is %s to %s", W.SpeedText(W.SPEED_MIN), W.SpeedText(W.SPEED_MAX))
            E.Refresh()
            return false
        end
        local w = W.Edit(E.entry)
        w.pages[E.page][E.sel].speed = v ~= 1 and v or nil
        W.Save()
        log("%s's wheel: page %d slot %d plays at %s", W.Title(E.entry), E.page, E.sel, W.SpeedText(v))
        E.note = nil
        E.Refresh()
        return true
    end
    -- the line under the rate box: what the slot plays at, and that its face animation keeps its own timing
    function E.SpeedNote()
        if not W.SpeedSupported() then
            return string.format("Play rates need G-SA1 module %s (feature \"emote\" %d); this one plays every animation "
                .. "at the game's rate.", W.SPEED_NEEDS.module, W.SPEED_NEEDS.version)
        end
        local slot = E.Slot()
        local g = cv.speed:GetFloat()
        if E.sel == 0 or not slot or not slot.body or slot.body == "stop" then
            return "How fast the slot's animation plays (1x = the game's own rate). Its face animation keeps its own "
                .. "timing."
        end
        local own = W.SlotSpeed(slot)
        return string.format("This animation plays at %s%s. The slot's face animation keeps its own timing (the Faces "
            .. "page sets it).", W.SpeedText(own), g ~= 1 and string.format(" x %s (every animation) = %s", W.SpeedText(g),
            W.SpeedText(W.PlayRate(slot, g))) or " the game's rate")
    end
    -- the line under the hold box: what it does for the selected slot
    function E.HoldNote()
        if not W.HoldSupported() then
            return "Holding the last pose needs G-SA1 module 0.9.4b (feature \"emote\" 2); this one plays the animation "
                .. "and goes back to standing."
        end
        local slot = E.Slot()
        if E.sel == 0 or not slot or not slot.body or slot.body == "stop" then
            return "An animation that ends in a pose (it plays once) stays on its last frame until you move, jump, press "
                .. "the action button or pick another animation; choosing it again on the wheel goes back to standing."
        end
        local e = W.SlotEntry(slot, W.ListOf(E.entry))
        if slot.loop or (e and e.play == "loop") then
            return "This one loops until you move: there is no last pose to hold."
        end
        if slot.nohold then return "Off: after its last frame he goes back to standing." end
        return "On: he stays in the pose until you move (choosing it again on the wheel goes back to standing)."
    end
    -- the slot's (or the centre's) face animation; a name the entry cannot show is refused with the reason
    function E.SetFace(name)
        if name == nil or name == "-" or name == "" or name == "none" then
            name = nil
        else
            local F = GSA1.Faces
            if not (F and F.Play) then
                E.note = "face animations need the Faces page (G-SA1's feature \"faces\")"
                E.Refresh()
                return false
            end
            if F.HasFaces and not F.HasFaces(E.entry) then
                E.note = W.Title(E.entry) .. " has no face in the game"
                E.Refresh()
                return false
            end
            if F.CanShow then
                local can, why = F.CanShow(name, E.entry)
                if can == false then
                    E.note = tostring(why or (W.Title(E.entry) .. " can't show " .. name))
                    E.Refresh()
                    return false
                end
            end
        end
        local w = W.Edit(E.entry)
        if E.sel == 0 then w.centre.face = name else w.pages[E.page][E.sel].face = name end
        W.Save()
        E.note = nil
        E.Refresh()
        return true
    end
    -- the selected slot on the current character as the face trigger plays it (its animation and its face animation)
    function E.Play()
        local C = GSA1.Char
        if not C then
            E.note = "spawn a character to try it"
            E.Refresh()
            return false
        end
        if C.name ~= E.entry then
            E.note = string.format("this is %s's wheel: spawn %s to try it", W.Title(E.entry), W.Title(E.entry))
            E.Refresh()
            return false
        end
        local w = E.Wheel()
        local slot = E.Slot()
        local F = GSA1.Faces
        local faces = F ~= nil and F.Play ~= nil and (not F.HasFaces or F.HasFaces(E.entry))
        if E.sel == 0 then
            if w.centre.face and faces then return W.PlayFace(C, E.entry, w.centre.face) end
            return false
        end
        local face = slot and faces and slot.face or nil
        local ok = W.PlayBody(C, slot, E.page, E.sel, "the page's Play", face, E.entry)
        if face then W.PlayFace(C, E.entry, face) end
        return ok
    end
    function E.PlayRow(r)
        local C = GSA1.Char
        if r.greyed or not C or C.name ~= E.entry then
            E.note = r.greyed and (r.name .. " cannot play in G-SA1 yet: " .. r.greyed) or
                string.format("spawn %s to try it", W.Title(E.entry))
            E.Refresh()
            return false
        end
        return W.PlayBody(C, { body = r.e.key, name = r.e.name }, 0, 0, "the page's list", nil, E.entry)
    end
    function E.Menu(r)
        if not DermaMenu then return end
        local m = DermaMenu()
        if not r.greyed then
            for s = 1, W.SLOTS do
                m:AddOption(string.format("Put in slot %d", s), function() E.Assign(r, s) end)
            end
            m:AddOption("Play now", function() E.PlayRow(r) end)
        end
        m:AddOption("Copy name", function() if SetClipboardText then SetClipboardText(r.name) end end)
        m:Open()
    end
    return E
end

function W.BuildPage(panel)
    local E = W.NewEditor()
    W.editor = E
    panel:Help("Hold the wheel key, point at an animation with the mouse or the right stick and let go: your character plays "
        .. "it. The game keeps running underneath (no slow motion); moving, jumping or the action button ends the animation. "
        .. "Each character has his own wheel of up to 4 pages of 8 slots and a centre; a slot can also have a face animation "
        .. "(the Faces page makes them), played together with the slot's animation by the face trigger.")
    panel:CheckBox("Emote wheel", "gsa1_wheel")
    panel:ControlHelp("Hold the wheel key, point at an animation with the mouse or the right stick, release to play it. The "
        .. "game keeps running; the camera does not turn while you choose.")
    -- the keys
    panel:Help("Wheel key (hold)")
    binder(panel, "gsa1_wheel_key")
    panel:Button("No key (bind +gsa1_wheel yourself)", "gsa1_wheel_key", "0")
    panel:ControlHelp("TAB like GTA V's weapon wheel; while you are a character TAB does not open the scoreboard. Keys your "
        .. "character uses are refused.")
    choice_combo(panel, "Controller button (hold)", "gsa1_wheel_pad", W.PAD_BUTTONS)
    local _, also = W.PadMapped(cv.pad:GetInt())
    panel:ControlHelp("LB is GTA's, but it is the game's L (Big's fishing camera uses L + R)." .. (also and (" Your "
        .. W.PadTitle(cv.pad:GetInt()) .. " also does " .. also .. " (Controller page): held back while the wheel is open.")
        or ""))
    panel:Help("Face trigger in the open wheel")
    binder(panel, "gsa1_wheel_face_key")
    panel:Button("No face key", "gsa1_wheel_face_key", "0")
    panel:ControlHelp("Plays the highlighted slot's face animation together with its animation, or only the centre's face "
        .. "animation; the wheel closes. Mouse buttons are fine: they do nothing else while the wheel is open.")
    choice_combo(panel, "Face trigger (controller)", "gsa1_wheel_face_pad", W.PAD_BUTTONS)
    panel:ControlHelp("LT does not turn the camera while the wheel is open.")
    -- pointing and the look
    panel:NumSlider("Mouse sensitivity in the wheel", "gsa1_wheel_mouse", 0.25, 4, 2)
    panel:ControlHelp("How far the mouse moves to reach a slot.")
    panel:NumSlider("Right stick: point at least", "gsa1_wheel_deadzone", 0.2, 0.9, 2)
    panel:NumSlider("Right stick: keep the slot lit for (s)", "gsa1_wheel_stick_keep", 0, 2, 2)
    panel:ControlHelp("After the stick goes back to rest; then the centre is chosen. 0 = it stays lit (GTA style; the centre "
        .. "only if you never pointed).")
    panel:NumSlider("Wheel size", "gsa1_wheel_size", 0.5, 2, 2)
    panel:ControlHelp("The names on the wheel grow and shrink with it.")
    panel:NumSlider("Wheel background", "gsa1_wheel_opacity", 0.2, 1, 2)
    panel:ControlHelp("How dark the wheel's glass is (the highlighted slot is always lit).")
    local fonts = {}
    for i, c in ipairs(W.FONT_CHOICES) do fonts[i] = { i - 1, c.title } end
    choice_combo(panel, "Wheel font", "gsa1_wheel_font", fonts)
    panel:ControlHelp("Fonts that come with Garry's Mod or Windows (on Linux the Windows ones fall back to a standard "
        .. "font).")
    panel:CheckBox("The character can keep moving while the wheel is open", "gsa1_wheel_move")
    panel:ControlHelp("Off: he stops (no stick) while you choose.")
    panel:CheckBox("Allow animations in the air", "gsa1_wheel_air")
    panel:ControlHelp("On: an animation can start while jumping or falling; he keeps falling and lands while posing.")
    panel:CheckBox("A quick tap plays the last one again", "gsa1_wheel_tap")
    panel:CheckBox("Show the name of what plays", "gsa1_wheel_toast")
    panel:ControlHelp("Also says why an animation could not play.")
    -- 0.9.4e: hiding the wheel (for recording) and the play rate of every animation
    panel:CheckBox("Hide the wheel (for recording)", "gsa1_wheel_hidden")
    panel:ControlHelp("The wheel works exactly as usual - hold the key, point with the mouse or the right stick, let go, "
        .. "the face trigger, the centre - but nothing of it is drawn: no ring, no names, no centre text, no fade, no name "
        .. "of what plays. The rest of G-SA1's HUD stays as it is.")
    panel:Help("Hide / show the wheel (a key that switches it)")
    binder(panel, "gsa1_wheel_hide_key")
    panel:Button("No hide key", "gsa1_wheel_hide_key", "0")
    panel:ControlHelp("Hiding says nothing on screen (it would be in your recording); showing it again shows one small "
        .. "note. Keys your character uses, the wheel key and the face trigger are refused. Console: "
        .. "gsa1_wheel_hide_toggle.")
    panel:NumSlider("Play rate of every animation (x)", "gsa1_wheel_speed", 0.25, 4, 2)
    panel:ControlHelp("Multiplies each slot's own play rate (below): 2 = twice as fast, 0.5 = half as fast. Only the body "
        .. "animations: the face animations keep their own timing.")

    -- the wheels
    panel:Help("The wheels")
    local cc = panel:ComboBox("Character")
    for _, c in ipairs(W.Entries()) do cc:AddChoice(c.title, c.name, c.name == E.entry) end
    cc.OnSelect = function(_, _, _, data) E.SetEntry(data) end
    E.charCombo = cc
    local pagesRow = vgui.Create("DPanel", panel)
    if pagesRow.SetTall then pagesRow:SetTall(24) end
    if pagesRow.SetPaintBackground then pagesRow:SetPaintBackground(false) end
    E.pageButtons = {}
    for p = 1, W.PAGES do
        local b = vgui.Create("DButton", pagesRow)
        b:SetText("Page " .. p)
        if b.Dock then b:Dock(LEFT) end
        if b.SetWide then b:SetWide(56) end
        b.DoClick = function() E.SetPage(p) end
        E.pageButtons[p] = b
    end
    local clearPage = vgui.Create("DButton", pagesRow)
    clearPage:SetText("Clear page")
    if clearPage.Dock then clearPage:Dock(FILL) end
    clearPage.DoClick = function() E.ClearPage() end
    E.clearPage = clearPage
    panel:AddItem(pagesRow)
    local mini = vgui.Create("DPanel", panel)
    if mini.SetTall then mini:SetTall(260) end
    mini.Paint = function(self, w, h)
        paint_mini(self, w, h, E)
        return true
    end
    mini.OnMousePressed = function(self, code)
        local w, h = self:GetWide(), self:GetTall()
        local x, y = self:CursorPos()
        local size = math.min(w, h)
        local s = W.SlotAt(x - w / 2, y - h / 2, size * 0.48 * 0.4, size * 0.48)
        if s ~= nil then E.Select(s) end
    end
    panel:AddItem(mini)
    E.mini = mini
    panel:ControlHelp("Click a slot (or the centre) on the little wheel; slot 1 is at the top, then clockwise.")
    E.selLine = panel:Help("Slot 1")
    local playB = panel:Button("Play it on your character")
    if playB then playB.DoClick = function() E.Play() end end
    E.playButton = playB
    local clearB = panel:Button("Clear this slot")
    if clearB then clearB.DoClick = function() E.Clear() end end
    E.clearButton = clearB
    E.loopBox = panel:CheckBox("Loop it (until you move)")
    if E.loopBox then
        E.loopBox.OnChange = function(self, on)
            if E.syncing then return end
            E.SetLoop(on)
        end
    end
    E.holdBox = panel:CheckBox("Hold the last pose (until you move)")
    if E.holdBox then
        E.holdBox.OnChange = function(self, on)
            if E.syncing then return end
            E.SetHold(on)
        end
    end
    E.holdNote = panel:ControlHelp("")
    -- 0.9.4e: the slot's play rate
    E.speedCombo = panel:ComboBox("Play rate:")
    if E.speedCombo then
        E.speedCombo.OnSelect = function(_, _, _, data)
            if E.syncing then return end
            E.SetSpeed(tonumber(data))
        end
    end
    E.speedNote = panel:ControlHelp("")
    E.faceCombo = panel:ComboBox("Face with it:")
    if E.faceCombo then
        E.faceCombo.OnSelect = function(_, _, _, data)
            if E.syncing then return end
            E.SetFace(data)
        end
    end
    E.faceNote = panel:ControlHelp("")
    -- the list
    panel:Help("Every animation of the character: double-click puts it into the selected slot (then the next slot is "
        .. "selected); right-click for more. Greyed out: cannot play in G-SA1 yet (the tooltip says why).")
    E.find = panel:TextEntry("Find (name or number)")
    if E.find then
        E.find.OnChange = function() E.Fill() end
        if E.find.SetUpdateOnType then E.find:SetUpdateOnType(true) end
    end
    E.group = panel:ComboBox("Group")
    E.groupValue = "All"
    if E.group then
        for _, g in ipairs(W.GROUPS) do E.group:AddChoice(g, g, g == "All") end
        E.group.OnSelect = function(_, _, _, data)
            E.groupValue = data
            E.Fill()
        end
    end
    local list = vgui.Create("DListView", panel)
    if list.SetMultiSelect then list:SetMultiSelect(false) end
    list:AddColumn("#")
    list:AddColumn("Internal name")
    list:AddColumn("Frames")
    list:AddColumn("Plays")
    list:AddColumn("Group")
    list:AddColumn("On wheel")
    if list.SetTall then list:SetTall(380) end
    panel:AddItem(list)
    E.list = list
    list.DoDoubleClick = function(_, _, line)
        if line and line.gsa1Row then E.Assign(line.gsa1Row) end
    end
    list.OnRowSelected = function(_, _, line)
        local r = line and line.gsa1Row
        if r and r.greyed then E.note = r.name .. " cannot play in G-SA1 yet: " .. r.greyed end
    end
    list.OnRowRightClick = function(_, _, line)
        if line and line.gsa1Row then E.Menu(line.gsa1Row) end
    end
    local resetB = panel:Button("Reset this character's wheel to the defaults")
    if resetB then resetB.DoClick = function() E.Reset() end end
    E.resetButton = resetB
    panel:ControlHelp("Your wheels are kept in garrysmod/data/gsa1/emote_wheel.txt. The list shows the internal names the "
        .. "game's developers gave the animations (custom names come later); animations made for props (carrying, set "
        .. "pieces, Big's fishing, the board) play without the prop; an animation pauses while your character is off "
        .. "screen.")
    panel:Help("Status")
    live_label(panel, function() return W.StatusLines(E) end)
    E.Refresh()
end

GSA1.AddMenuPage(280, "wheel", "Emote wheel", W.BuildPage, W.NEEDS)
