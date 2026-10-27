-- feat_wheel_test.lua - the emote wheel's addon side (round 0.9.4a: addon/lua/gsa1/feat/sh_wheel.lua, cl_wheel.lua,
-- cl_wheel_rows.lua and cl_character.lua's seams GSA1.FilterStick / GSA1.BindOverride; sadc docs/research/
-- faces_wheel_plan.md 6.5 with its Review R.9 / R.16 / R.18, the owner's answers 10.1 and super2_plan.md 10.2's CORRECTED
-- reading) in Garry's Mod's own LuaJIT with a mocked GMod (tests/lua_mock.lua) and a mock of the module's feature "emote"
-- (bind_emote.cpp: every call recorded, the arguments checked) and of feat/cl_faces.lua's GSA1.Faces (the Lua contract of
-- faces_wheel_plan.md 5.5, recorded). Checks (the numbers of 6.5's test list):
--   (1) every gsa1_wheel* setting with its default, each with a control on the "Emote wheel" page;
--   (2) holding the key opens the wheel within a frame; the HUD draws only while it is open; a release at the centre
--       plays nothing;
--   (3) the mouse: InputMouseApply moves the wheel's cursor and returns true, the mouse is zeroed, the 8 directions light
--       slots 1-8, the centre none, the view does not turn; closed: nil;
--   (4) the right stick (XInput's thumb y grows upwards: src/core/pad.cpp) lights a slot, the slot stays lit for
--       gsa1_wheel_stick_keep s after the stick rests, then the centre (0: it stays); a release plays slot 1 once; B cancels;
--   (5) no view turn and no stored turn through GSA1.PadView while open, a camera reset dropped;
--   (6) presses that start while open are held back from GSA1.FilterButtons until released (the chained filter after it
--       never sees them); a jump held before opening stays held; GSA1.ExtraButtons is 0 while open (review R.18);
--   (7) the mouse wheel pages through GSA1.BindOverride while open and leaves gsa1_cam_distance alone; closed it changes
--       the camera distance as before;
--   (8) the wheel key's own bind (TAB = +showscores) is blocked only while a character exists;
--   (9) closing on: the character removed, the vgui cursor, the game UI, typing, GSA1.InputBlocked - nothing plays;
--   (10) pages: empty ones skipped, LB / RB and keys 1-8, "Clear page" survives a reload;
--   (11) storage: the format of faces_wheel_plan.md 8.1 round trip, the face column and the centre line, a missing name
--        kept and shown, a renumbered row found by name, bad lines counted, the mirror; a39 / a54 (both k_panch0) and
--        a75 / a139 (both s_kimepose0) keep their own keys after a reload (review R.9);
--   (12) the page lists the module's rows by internal name and number, the game's variants folded by dup (two motions with
--        one name are two rows), the find box and the group filter, double-click fills the selected slot, another entry's
--        wheel is editable without a character; the rows that cannot play are greyed with the reason as the tooltip and
--        cannot be assigned (owner answer FQ19);
--   (13) a refusal shows libsa1's reason in the toast and an "emote ... refused" log line ("moving": the stick hint);
--   (14) gsa1_wheel_move 0: GSA1.FilterStick gives 0, 0 only while open;
--   (15) the face trigger (left click, LT): the slot's face animation and its body animation once each, the wheel closes,
--        the release plays nothing; at the centre only the centre's face animation; E-102: the body only; a face the
--        entry cannot show: the body plays and the toast says why; rebinding the trigger moves it;
--   (16) GSA1FaceLibraryChanged: a renamed face is renamed in every slot and the centre, a deleted one cleared, the file
--        saved;
--   (17) the playing animation chosen again -> EmoteStop(STOP_BLEND); "(stop)" -> EmoteStop(STOP_NOW);
--   (18) "loop it" sends EMOTE.LOOP, gsa1_wheel_air 1 sends EMOTE.IN_AIR (0: neither);
--   round 0.9.4b (objects2_plan.md 11.2, the owner's 0.9.4a notes):
--   (19) "Hold the last pose": the per-slot option (default on) reaches the module - an animation that plays once gets
--        gsa1.EMOTE.HOLD, one switched off, looped ("loop it") or looping does not; a module without HOLD gets 0.9.4a's
--        flags; the held pose chosen again (EmoteState HOLDING) -> EmoteStop(STOP_BLEND); the file keeps "nohold"; the
--        page's check box sets it and is greyed for a looping animation;
--   (20) the fonts: made with surface.CreateFont per wheel size and screen (the label, small, big and toast fonts follow
--        gsa1_wheel_size and ScrH), Garry's Mod's own Roboto by default, gsa1_wheel_font picks another; nothing is made
--        while the size and the screen stay (100 frames of the open wheel: no font made), a size seen before reuses its
--        fonts;
--   (21) the design: the highlighted slot lit in the accent colour (Sonic blue; gold for Super Sonic) and fading in, a
--        gold marker on slots with a face animation, the highlighted animation's name in the big font in the centre, the
--        page markers, the open animation and the fade after closing (nothing drawn after it).
--   round 0.9.4e (gsa1_rounds_plan.md 14.1aa; the owner: "An option for hiding the wheel for recording purposes would be
--   great, also being able to change the animation's play rate"):
--   (22) "Hide the wheel" (gsa1_wheel_hidden 1): the HUD draws nothing - no polygon, text, rectangle, colour or font, no
--        fade after the close, no toast - while the mouse, the right stick, keys 1-8, the release, the face trigger and the
--        centre work exactly as usual (the same calls as shown); shown again, the same sequence draws (negative control);
--   (23) the toggle key (gsa1_wheel_hide_key) flips it once per press (held: once; a menu open: not), turning it on shows
--        nothing, turning it off one small note (notification.AddLegacy), both logged; gsa1_wheel_hide_toggle the same; the
--        wheel key, the face trigger and the character's keys are refused as the hide key;
--   (24) the play rate: the slot's (W.SPEEDS) x gsa1_wheel_speed reaches gsa1.Emote's 4th argument (2 x 1 = 2, 2 x 1.5 = 3,
--        1 x 0.5 = 0.5, 0.25 x 0.25 = 1/16, 4 x 4 = 16), the face animation is played as before (no rate), the page's rate
--        box sets it (the file's 9th column; 1x writes none; 8 refused), the centre and the toast say it; a module without
--        feature "emote" 3 gets 0.9.4d's three arguments and the page says why;
--   (25) an old (0.9.4d) wheel file without speeds loads as 1x everywhere (Emote gets 1) and prints back unchanged; bad
--        speeds are bad lines; 0.9.4d's own reader (build/release_0.9.4d's sh_wheel.lua, when present) reads a new file with
--        rates (it ignores the 9th column).
--   API NOTES (round 0.9.4e, lane 094e-gsa1-wheel; files: feat/sh_wheel.lua, feat/cl_wheel.lua, src/module/bind_emote.cpp,
--   this test, tests/feat_emote_binding_test.cpp):
--     module  gsa1.FEATURES.emote = 3 (with libsa1's SA1_API_EMOTE_HOLD; without it 1, as before). gsa1.Emote(id, key
--             [, flags [, speed]]): speed = sa1_emote_item.speed, a multiplier of the game's rate for every entry of the
--             item's chain; nil or 0 = 1 (versions 1 / 2 behaviour); gsa1.EMOTE.SPEED_MIN = 1/64, SPEED_MAX = 16; outside,
--             or not a number: nil, message, "bad_argument" (checked before the character). bind_emote.cpp builds the
--             sa1_emote itself (emote_play_speed: the core's gsa1::emote_play plus the speed; src/core/emote.* unchanged).
--     Lua     W.SPEEDS {0.25 .. 4}, W.SPEED_MIN / MAX 0.25 / 4, W.LIB_SPEED_MIN / MAX 1/64 / 16, W.SPEED_NEEDS {emote 3,
--             0.9.4e}; W.SlotSpeed(slot), W.PlayRate(slot, global) (slot x global, clamped to libsa1's range),
--             W.SpeedText(v) ("2x"), W.ParseSpeed(text) (the file's 9th column), W.SpeedSupported(); slot.speed (nil =
--             1x). W.PlayBody sends the rate only when the module has emote 3. W.ToggleHidden(how) (the note rule: none
--             when hiding, one notification.AddLegacy line when showing again), W.HideKeyThink() (Think hook
--             "gsa1_wheel_hide"), W.Hidden(); console gsa1_wheel_hide_toggle; the editor's E.SetSpeed(v), E.SpeedNote(),
--             E.speedCombo, E.speedNote.
--     ConVars gsa1_wheel_hidden 0 (check box), gsa1_wheel_hide_key 0 (binder + "No hide key"), gsa1_wheel_speed 1
--             (slider 0.25-4) - all on Q menu > Options > G-SA1 > Emote wheel; the per-slot rate is a combo box there.
--     file    data/gsa1/emote_wheel.txt: an optional 9th column "speed" (written only for an animation slot not at 1x;
--             0.25-4; anything else a bad line); files without it load as 1x; 0.9.4d's reader ignores it.
--   and task 3 / review R.18: every W.DEFAULTS slot of the 8 entries resolves by name to an offered entry that played in
--   feat_emote_test.cpp (its build/<target>/emote_lists.txt; skipped with a note when the file is missing), and the
--   generated greyed rows (cl_wheel_rows.lua) are exactly the table rows the disc's catalogue leaves out.
--   lua_host tests/feat_wheel_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_wheel_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files (the faces' contract is stubbed below: faces_wheel_plan.md 5.5)
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_wheel[%w_]*%.lua$") then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end

-- the mock module's feature "emote" ------------------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ features = { emote = 3 } })       -- 0.9.4e: the play rate
local R = { calls = {}, bad = {}, refuse = nil, state = {}, pad = { connected = false, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0,
            yaw = 0, pitch = 0, reset = false } }
local function rec(name, ...) R.calls[#R.calls + 1] = { name, ... } end
local function calls_of(name)
    local out = {}
    for _, c in ipairs(R.calls) do
        if c[1] == name then out[#out + 1] = c end
    end
    return out
end
local function reset_calls()
    R.calls = {}
    R.state = {}
end
G.EMOTE = { LOOP = 0x100, IN_AIR = 4, KEEP_INPUT = 8, NO_PROPS = 0x10, NO_TRAIL = 2, CHAIN = 1, STOP_NOW = 0,
            STOP_BLEND = 1, STATE_NONE = 0, STATE_PLAYING = 1, STATE_ENDING = 2, ROW = 0, EXTRA = 1, FORM_NORMAL = 0,
            FORM_SUPER = 1, F_NEEDS_PROP = 1, F_HOLD = 2, F_SUPER_ONLY = 4, F_BOARD = 8, F_OTHER_OBJECT = 0x10,
            F_EXTRA = 0x20, HOLD = 0x20, STATE_HOLDING = 3,       -- version 2 (0.9.4b): HOLD, STATE_HOLDING
            SPEED_MIN = 1 / 64, SPEED_MAX = 16 }                  -- version 3 (0.9.4e): Emote's play rate
-- the catalogues: { key, name, frames, play, group, dup (1-based position of the first, 0 none) } per (kind, form)
local function L(rows)
    local out = { n = #rows }
    for i, r in ipairs(rows) do
        local src = string.sub(r[1], 1, 1) == "x" and 1 or 0
        out[i] = { key = r[1], source = src, index = tonumber(string.sub(r[1], 2)), name = r[2], label = "LABEL_" .. r[2],
                   frames = r[3], play = r[4], group = r[5], class = 0, flags = 0, dup = r[6] or 0,
                   dup_key = "" }
    end
    return out
end
local SONIC = {
    { "a0", "s_wait0", 32, "loop", "stand" }, { "a3", "s_wait3", 66, "once", "idle" }, { "a5", "s_wait_a1", 39, "once", "idle" },
    { "a14", "s_spin0", 8, "loop", "ball" }, { "a15", "s_spin0", 8, "loop", "ball", 4 },
    { "a26", "s_rollfly", 33, "loop", "air" }, { "a47", "s_tukamari0", 20, "once", "setpiece" },
    { "a70", "s_zitabata", 30, "loop", "air" }, { "a75", "s_kimepose0", 65, "once", "pose" },
    { "a76", "s_kimepose1", 50, "loop", "pose" }, { "a81", "s_furatsuki0", 60, "loop", "idle" },
    { "a84", "s_awa0", 40, "once", "swim" },
}
local SUPER = {
    { "a3", "s_wait3", 66, "once", "idle" }, { "a5", "s_wait_a1", 39, "once", "idle" }, { "a75", "s_kimepose0", 65, "once", "pose" },
    { "a81", "s_furatsuki0", 60, "loop", "idle" }, { "a130", "ss_wait0", 32, "loop", "super" },
    { "a131", "ss_move0", 8, "loop", "super" }, { "a132", "ss_move1", 8, "loop", "super" },
    { "a133", "ss_move2", 8, "loop", "super" }, { "a134", "ss_move2", 8, "loop", "super", 8 },
    { "a139", "s_kimepose0", 65, "once", "pose", 3 },
}
local LISTS = {
    ["0:0"] = L(SONIC), ["0:1"] = L(SUPER), ["8:0"] = L(SUPER), ["8:1"] = L(SUPER),
    ["2:0"] = L({ { "a5", "m_wait_a1", 39, "once", "idle" }, { "a33", "m_rollfly0", 33, "loop", "air" },
                  { "a37", "m_flyup", 20, "loop", "air" }, { "a43", "m_atack_1", 20, "once", "attack" },
                  { "a54", "m_kimepose0", 65, "once", "pose" }, { "a56", "m_losepose0", 65, "once", "pose" },
                  { "a94", "m_zitabata", 30, "loop", "air" }, { "x0", "m_taiki0", 90, "once", "idle" } }),
    ["3:0"] = L({ { "a5", "k_wait_a1", 39, "once", "idle" }, { "a30", "k_rollfly0", 33, "loop", "air" },
                  { "a39", "k_panch0", 75, "hold", "attack" }, { "a40", "k_kimepose1", 65, "once", "pose" },
                  { "a54", "k_panch0", 32, "once", "attack" }, { "a56", "k_panch2", 32, "once", "attack" },
                  { "x0", "k_taiki0", 40, "once", "idle" }, { "x1", "k_taiki1", 40, "once", "idle" },
                  { "x2", "k_wait_b1", 40, "loop", "idle" }, { "x3", "k_item_fg1", 60, "once", "idle" } }),
    ["5:0"] = L({ { "a5", "a_wait_a1", 39, "once", "idle" }, { "a42", "a_kimepose0", 65, "once", "pose" },
                  { "a81", "a_attack1", 20, "once", "attack" }, { "a85", "a_rollat0", 20, "loop", "attack" },
                  { "a87", "a_rollat2", 20, "loop", "attack" }, { "x0", "a_taiki0", 40, "once", "idle" },
                  { "x1", "a_kakure0", 40, "once", "idle" }, { "x2", "a_mogura1", 40, "once", "idle" } }),
    ["6:0"] = L({ { "a43", "e_wait2", 39, "loop", "stand" }, { "a46", "e_wwait0", 39, "loop", "stand" },
                  { "a49", "e_hover1", 20, "loop", "air" }, { "a62", "e_shoot0", 20, "once", "attack" },
                  { "a67", "e_taiki0", 90, "once", "pose" }, { "a77", "e_item_f1", 40, "once", "idle" },
                  { "a80", "e_item_g1", 40, "once", "idle" }, { "x0", "e_kimepose0", 90, "once", "pose" } }),
    ["7:0"] = L({ { "a2", "b_wait_a1", 39, "once", "idle" }, { "a47", "b_zitabata0", 30, "loop", "air" },
                  { "a48", "b_kimepose0", 65, "once", "pose" }, { "a60", "b_joysmall", 40, "once", "pose" },
                  { "a61", "b_joymiddle", 40, "once", "pose" }, { "a62", "b_joybig0", 40, "once", "pose" },
                  { "a92", "b_wwait0", 40, "loop", "swim" }, { "x0", "b_item_u0", 40, "once", "idle" },
                  { "x1", "b_item_u1", 40, "once", "idle" } }),
}
local function int_in(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end
function G.EmoteList(kind, form)
    rec("EmoteList", kind, form)
    if not int_in(kind, 0, 8) or not (form == nil or int_in(form, 0, 1)) then
        R.bad[#R.bad + 1] = "EmoteList"
        return nil, "EmoteList(kind, form)", "bad_argument"
    end
    local l = LISTS[kind .. ":" .. (form or 0)]
    if not l then return { n = 0 } end
    -- a fresh copy each call (the module makes new tables)
    local out = { n = l.n }
    for i = 1, l.n do
        local e = {}
        for k, v in pairs(l[i]) do e[k] = v end
        out[i] = e
    end
    return out
end
function G.Emote(id, key, flags, speed, ...)
    rec("Emote", id, key, flags, speed)
    local known = 0x100 + 4 + 8 + 0x10 + 2 + (G.EMOTE.HOLD and 0x20 or 0)
    -- 0.9.4e (bind_emote.cpp): speed nil, 0 (= 1) or 1/64..16; only with feature "emote" 3
    local speed_ok = speed == nil or (type(speed) == "number" and (speed == 0 or (speed >= 1 / 64 and speed <= 16)) and
        (tonumber(G.FEATURES.emote) or 0) >= 3)
    if not (int_in(id, 1, 1e9) and type(key) == "string" and string.match(key, "^[ax]%d+$") and
        (flags == nil or (int_in(flags, 0, 0xFFFF) and bit.band(flags, bit.bnot(known)) == 0)) and speed_ok and
        select("#", ...) == 0) then
        R.bad[#R.bad + 1] = "Emote"
        return nil, "unknown animation key", "bad_argument"
    end
    if R.refuse then return nil, R.refuse, "unsupported" end
    R.state[id] = { 1, key }
    return true
end
function G.EmoteStop(id, how)
    rec("EmoteStop", id, how)
    if not (int_in(id, 1, 1e9) and (how == nil or how == 0 or how == 1)) then
        R.bad[#R.bad + 1] = "EmoteStop"
        return nil, "EmoteStop(id, how)", "bad_argument"
    end
    R.state[id] = nil
    return true
end
function G.EmoteState(id)
    local s = R.state[id]
    if not s then return 0, nil, -1, 0 end
    return s[1], s[2], 0, 3
end
function G.PadPoll(dt, paused, out)
    out = out or {}
    for k, v in pairs(R.pad) do out[k] = v end
    out.active, out.buttons, out.sx, out.sy = R.pad.active or false, R.pad.buttons or 0, 0, 0
    return out
end

-- the faces' contract (feat/cl_faces.lua, faces_wheel_plan.md 5.5), recorded
local FACES = { { name = "Happy" }, { name = "Blink" }, { name = "Surprised" }, { name = "Talk" }, { name = "Shock" },
                { name = "Eyes closed" }, { name = "Sad" }, { name = "Sleepy" }, { name = "Angry talk" } }
local NO_FACE = { gamma = true, supersonic = true, supersonic_general = true }
local function faces_stub()
    return {
        Library = function() return FACES end,
        Find = function(name)
            for _, f in ipairs(FACES) do if f.name == name then return f end end
        end,
        HasFaces = function(entry) return not NO_FACE[entry] end,
        CanShow = function(name, entry)
            if entry == "big" and (name == "Happy" or name == "Surprised") then return false, "Big can't show b" end
            return true
        end,
        Play = function(C, name, why)
            rec("FacePlay", C and C.id, name, why)
            return true
        end,
        Stop = function(C) rec("FaceStop", C and C.id) end,
    }
end

-- the GMod parts the feature uses that lua_mock.lua does not have
local keys, binds, codes = {}, {}, {}
local KEYNAMES = { [67] = "TAB", [107] = "MOUSE1", [108] = "MOUSE2", [17] = "G", [16] = "F", [65] = "SPACE", [33] = "W" }
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    IsKeyDown = function(code) return keys[code] == true end,
    IsMouseDown = function(code) return keys[code] == true end,
    LookupBinding = function(b) return binds[b] end,
    GetKeyCode = function(name) return codes[name] end,
    GetKeyName = function(code) return KEYNAMES[code] or ("key" .. tostring(code)) end,
    LookupKeyBinding = function(code) if code == 67 then return "+showscores" end end,
}
binds["+jump"], codes["SPACE"] = "SPACE", 65
binds["+forward"], codes["W"] = "W", 33
binds["+attack"], codes["MOUSE1"] = "MOUSE1", 107
M.player.IsTyping = function() return M.typing == true end
local cursor, blocked = false, false
vgui.CursorVisible = function() return cursor end
local polys = 0
surface.DrawPoly = function() polys = polys + 1 end
surface.SetFont = function() end
surface.GetTextSize = function(s) return #tostring(s) * 8, 16 end
-- 0.9.4b: the fonts made (surface.CreateFont: name, data) and what the HUD draws (colours, texts, rectangles)
local fonts_made = {}
surface.CreateFont = function(name, data) fonts_made[#fonts_made + 1] = { name = name, data = data } end
local drawcol, drawn = { 0, 0, 0, 0 }, { colours = {}, texts = {}, rects = 0 }
surface.SetDrawColor = function(r, g, b, a)
    drawcol = { r, g, b, a }
    drawn.colours[#drawn.colours + 1] = drawcol
end
surface.DrawRect = function() drawn.rects = drawn.rects + 1 end
draw.SimpleText = function(text, font, x, y, col)
    drawn.texts[#drawn.texts + 1] = { text = text, font = font, x = x, y = y, a = col and col.a }
end
local function reset_drawn() drawn = { colours = {}, texts = {}, rects = 0 } end
local KEY_TAB, MOUSE_LEFT, MOUSE_RIGHT = 67, 107, 108

-- 1. loading and the settings ---------------------------------------------------------------------------------------------------
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local W = GSA1 and GSA1.Wheel
check(ok_load and #ferr == 0 and W ~= nil and W.BuildPage ~= nil and W.UNPLAYABLE ~= nil,
    "the autorun loads feat/sh_wheel.lua, cl_wheel.lua and cl_wheel_rows.lua (%s)", ok_load and
    table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_load or ferr[1]))
if not (ok_load and W) then return done() end
GSA1.Faces = faces_stub()
local prevBlocked = GSA1.InputBlocked
GSA1.InputBlocked = function() return blocked end
local WANT = {
    gsa1_wheel = { "1", 0, 1 }, gsa1_wheel_key = { "67", 0, 511 }, gsa1_wheel_pad = { "2", 0, 0x30000 },
    gsa1_wheel_face_key = { "107", 0, 511 }, gsa1_wheel_face_pad = { "65536", 0, 0x30000 },
    gsa1_wheel_mouse = { "1", 0.25, 4 }, gsa1_wheel_deadzone = { "0.5", 0.2, 0.9 }, gsa1_wheel_stick_keep = { "0.5", 0, 2 },
    gsa1_wheel_size = { "1", 0.5, 2 }, gsa1_wheel_opacity = { "0.75", 0.2, 1 }, gsa1_wheel_move = { "1", 0, 1 },
    gsa1_wheel_air = { "0", 0, 1 }, gsa1_wheel_tap = { "0", 0, 1 }, gsa1_wheel_toast = { "1", 0, 1 },
    gsa1_wheel_summary = { "", nil, nil },
    gsa1_wheel_font = { "0", 0, 3 },                -- 0.9.4b
    gsa1_wheel_hidden = { "0", 0, 1 }, gsa1_wheel_hide_key = { "0", 0, 511 }, gsa1_wheel_speed = { "1", 0.25, 4 },  -- 0.9.4e
}
local bad = {}
for name, w in pairs(WANT) do
    local c = M.convars[name]
    if not (c and c.client and c.save and c.v == w[1] and c.lo == w[2] and c.hi == w[3] and GSA1.CONVARS[name]) then
        bad[#bad + 1] = name
    end
end
local mine = 0
for name in pairs(GSA1.CONVARS) do if string.find(name, "^gsa1_wheel") then mine = mine + 1 end end
table.sort(bad)
check(#bad == 0 and mine == 19, "(1) 19 client settings with faces_wheel_plan.md 7.1's defaults (TAB, D-pad down, the left "
    .. "mouse button and LT, sensitivity 1, dead zone 0.5, keep 0.5 s, size 1, background 0.75, moving on, in the air off, "
    .. "tap off, the toast on, the read-only mirror; 0.9.4b: the font 0 = Roboto; 0.9.4e: hidden 0, no hide key, play rate "
    .. "1)%s (%d)", #bad > 0 and (": wrong " .. table.concat(bad, " ")) or "", mine)

-- the page: every setting has a control (vgui stand-ins record the calls)
local made = {}
local METHODS
local function standin(kind)
    local P = { kind = kind, calls = {}, lines = {} }
    made[#made + 1] = P
    return setmetatable(P, { __index = function(t, k)
        if METHODS[k] then return METHODS[k] end
        if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
        return function(self, ...)
            t.calls[#t.calls + 1] = { k, ... }
            return standin(k)
        end
    end })
end
METHODS = {
    SetText = function(self, s) self.text = s end,
    SetConVar = function(self, c) self.convar = c end,
    SetTooltip = function(self, s) self.tooltip = s end,
    GetValue = function(self) return self.value or "" end,
    Clear = function(self) self.lines = {} self.choices = {} end,
    AddLine = function(self, ...)
        local l = standin("Line")
        l.cols = { ... }
        self.lines[#self.lines + 1] = l
        return l
    end,
    AddChoice = function(self, text, data, sel)
        self.choices = self.choices or {}
        self.choices[#self.choices + 1] = { text, data, sel }
    end,
}
vgui.Create = function(cls) return standin(cls) end
M.menu = {}
M.run_hook("PopulateToolMenu")
local entry
for _, e in ipairs(M.menu) do
    if e.class == "gsa1_feat_wheel" then entry = e end
end
check(entry and entry.name == "Emote wheel" and entry.category == "G-SA1", "the page Options -> G-SA1 -> Emote wheel")
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
local E, panel
local function build_page()
    made = {}
    panel = standin("DForm")
    entry.cpanel(panel)
    E = W.editor
end
if entry then
    build_page()
    local bound, combos = {}, {}
    for _, P in ipairs(made) do
        for _, c in ipairs(P.calls) do
            if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then bound[c[3]] = true end
            if c[1] == "Button" and c[3] == "gsa1_wheel_key" then bound.key_none = true end
            if c[1] == "Button" and c[3] == "gsa1_wheel_face_key" then bound.face_none = true end
            if c[1] == "Button" and c[3] == "gsa1_wheel_hide_key" then bound.hide_none = true end      -- 0.9.4e
        end
        if P.convar then bound[P.convar] = true end
        if P.kind == "ComboBox" and P.OnSelect then combos[#combos + 1] = P end
    end
    -- the combo boxes that set a ConVar (OnSelect -> RunConsoleCommand)
    for _, P in ipairs(combos) do
        local before = { pad = M.convars.gsa1_wheel_pad.v, fpad = M.convars.gsa1_wheel_face_pad.v,
                         font = M.convars.gsa1_wheel_font.v }
        pcall(P.OnSelect, P, 1, "x", "8")
        if M.convars.gsa1_wheel_pad.v == "8" then bound.gsa1_wheel_pad = true end
        if M.convars.gsa1_wheel_face_pad.v == "8" then bound.gsa1_wheel_face_pad = true end
        if M.convars.gsa1_wheel_font.v == "8" then bound.gsa1_wheel_font = true end
        M.convars.gsa1_wheel_pad.v, M.convars.gsa1_wheel_face_pad.v = before.pad, before.fpad
        M.convars.gsa1_wheel_font.v = before.font
    end
    -- the page's own combos (character, face, group) took "8" too: back to a clean state
    M.files[W.FILE] = nil
    W.data = nil
    W.Load()
    E.groupValue = "All"
    local missing = {}
    for name in pairs(WANT) do
        if not bound[name] and name ~= "gsa1_wheel_summary" then missing[#missing + 1] = name end
    end
    table.sort(missing)
    local status = table.concat(W.StatusLines(E), "\n")
    check(#missing == 0 and bound.key_none and bound.face_none and bound.hide_none and
        string.find(status, "your changed wheels", 1, true) ~= nil,
        "(1) every setting has a control on the page (check boxes, sliders, three key binders with \"No key\" - 0.9.4e: the "
        .. "hide key -, the two controller combos) and the status shows the read-only mirror%s", #missing > 0 and
        (": missing " .. table.concat(missing, " ")) or "")
end

-- a character ------------------------------------------------------------------------------------------------------------------
local function frames(n, dt)
    for _ = 1, n or 1 do M.frame(dt or 1 / 60) end
end
local function log_has(pat)
    GSA1.LogFlush()
    return string.find(M.files["gsa1/log.txt"] or "", pat) ~= nil
end
local function spawn(name)
    GSA1.Spawn(name)
    frames(2)
    return GSA1.Char
end
local C = spawn("sonic")
check(C ~= nil and C.name == "sonic", "Sonic spawned (the wheel's entry: sonic)")
if not C then return done() end
local function open()
    keys[KEY_TAB] = true
    frames(1)
end
local function release()
    keys[KEY_TAB] = nil
    frames(1)
end
local function emotes() return calls_of("Emote") end

local CMD = {}
CMD.__index = CMD
function CMD:SetMouseX(v) self.mx = v end
function CMD:SetMouseY(v) self.my = v end
function CMD:GetViewAngles() return Angle(10, 20, 0) end
function CMD:SetViewAngles(a) self.set = (self.set or 0) + 1 end
function CMD:GetMouseX() return 0 end
function CMD:GetMouseY() return 0 end
local function newcmd() return setmetatable({}, CMD) end

-- 2. opening, the HUD, a release at the centre --------------------------------------------------------------------------------
do
reset_calls()
polys = 0
M.run_hook("HUDPaint")
local closed_polys = polys
open()
local opened = W.open
polys = 0
M.run_hook("HUDPaint")
local open_polys = polys
release()
-- 0.9.4b: after the close the wheel fades out for W.CLOSE_TIME, then nothing is drawn
polys = 0
M.run_hook("HUDPaint")
local fade_polys = polys
frames(math.ceil(W.CLOSE_TIME * 60) + 2)
polys = 0
M.run_hook("HUDPaint")
local after_polys = polys
check(closed_polys == 0 and opened and open_polys >= 49 and not W.open and #emotes() == 0 and fade_polys > 0 and
    after_polys == 0,
    "(2) holding TAB opens the wheel in the same frame; the HUD draws only while it is open (%d polygons: 8 sectors x 6 and "
    .. "the centre; %d closed) and fades out after the close (%d polygons, then %d); a release with nothing highlighted "
    .. "plays nothing (%d calls)", open_polys, closed_polys, fade_polys, after_polys, #emotes())

end
-- 3. the mouse ----------------------------------------------------------------------------------------------------------------------
do
local cmd = newcmd()
local closed_r = M.run_hook("InputMouseApply", cmd, 0, -400, Angle())
open()
local r = M.run_hook("InputMouseApply", cmd, 0, -400, Angle())
local lit1 = W.sel
local dirs = { { 0, -400 }, { 300, -300 }, { 400, 0 }, { 300, 300 }, { 0, 400 }, { -300, 300 }, { -400, 0 }, { -300, -300 } }
local got = {}
for i, d in ipairs(dirs) do
    W.cx, W.cy, W.sel = 0, 0, 0
    M.run_hook("InputMouseApply", cmd, d[1], d[2], Angle())
    got[i] = W.sel
end
W.cx, W.cy, W.sel = 0, 0, 0
M.run_hook("InputMouseApply", cmd, 60, 0, Angle())
local centre = W.sel
release()
check(closed_r == nil and r == true and cmd.mx == 0 and cmd.my == 0 and lit1 == 1 and table.concat(got, " ") ==
    "1 2 3 4 5 6 7 8" and centre == 0 and cmd.set == nil,
    "(3) InputMouseApply(cmd, 0, -400) returns true, zeroes the mouse and lights slot 1; the 8 directions light slots %s; "
    .. "a small move stays in the centre (%d); the view is never set; closed: nil", table.concat(got, " "), centre)

end
-- 4. the right stick ---------------------------------------------------------------------------------------------------------------
do
reset_calls()
R.pad = { connected = true, raw = 0, rx = 0, ry = 1, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }
open()
frames(1)
local s_up = W.sel
R.pad.rx, R.pad.ry = 0, 0
frames(10)                -- 10 / 60 s < gsa1_wheel_stick_keep 0.5
local s_kept = W.sel
frames(30)                -- past 0.5 s
local s_after = W.sel
R.pad.ry = 1
frames(1)
R.pad.ry = 0
RunConsoleCommand("gsa1_wheel_stick_keep", "0")
frames(40)
local s_zero = W.sel
RunConsoleCommand("gsa1_wheel_stick_keep", "0.5")
release()
local e1 = emotes()
check(s_up == 1 and s_kept == 1 and s_after == 0 and s_zero == 1 and #e1 == 1 and e1[1][2] == C.id and e1[1][3] == "a75" and
    e1[1][4] == G.EMOTE.HOLD, "(4) the right stick up (XInput's ry +1) lights slot 1; at rest it stays lit for 0.5 s (%d), then the "
    .. "centre (%d); with keep 0 it stays (%d); the release plays slot 1 once: Emote(%s, %s, %s)", s_kept, s_after, s_zero,
    tostring(e1[1] and e1[1][2]), tostring(e1[1] and e1[1][3]), tostring(e1[1] and e1[1][4]))
reset_calls()
open()
R.pad.ry = 1
frames(1)
R.pad.ry, R.pad.raw = 0, W.PAD_B
frames(1)
local b_closed = not W.open
R.pad.raw = 0
release()
check(b_closed and #emotes() == 0, "(4) B cancels: the wheel closes and the release plays nothing")

end
-- 5. the controller's view turn and camera reset while open ------------------------------------------------------------------
do
R.pad = { connected = true, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 25, pitch = 5, reset = true }
open()
GSA1.PadUpdate(false)           -- a turn and a reset pending (cl_pad.lua)
local c5 = newcmd()
GSA1.PadView(c5)
local while_open = c5.set
R.pad.yaw, R.pad.pitch, R.pad.reset = 0, 0, false
release()
GSA1.PadUpdate(false)
local c6 = newcmd()
GSA1.PadView(c6)
check(while_open == nil and c6.set == nil, "(5) a pad turn and a camera reset while open: the view is not set then, and "
    .. "nothing pending turns it after the close (the original PadView used them up through the stand-in)")
R.pad = { connected = false, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }

end
-- 6. buttons while open: GSA1.FilterButtons (through the real input path: CreateMove -> the tick), GSA1.ExtraButtons -----------
do
local seen = {}
local realPrev = W.prevFilter
W.prevFilter = function(Cc, b)
    seen[#seen + 1] = { b, W.open }
    return realPrev and realPrev(Cc, b) or b
end
local JUMP, ACTION, SA1L = 1, 2, 8
local function tick_buttons() return M.ticks.last and M.ticks.last.buttons or -1 end
M.keys = IN_JUMP
frames(3)                                         -- jump held before opening
local f0 = tick_buttons()
open()
M.keys = IN_JUMP + IN_DUCK                        -- the action press starts while open
frames(3)
local f1 = tick_buttons()
R.pad = { connected = true, active = true, buttons = SA1L, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0,
          reset = false }
frames(3)                                         -- SA1 L (LB on the controller) while open
local f2 = tick_buttons()
R.pad = { connected = false, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }
release()
frames(3)
local f3 = tick_buttons()                         -- the action still held after the close: held back
M.keys = IN_JUMP
frames(3)
local f4 = tick_buttons()
M.keys = IN_JUMP + IN_DUCK                        -- a new press after the close goes through
frames(3)
local f5 = tick_buttons()
M.keys = 0
frames(3)
W.prevFilter = realPrev
local sees_action = false
for _, x in ipairs(seen) do
    if x[2] and bit.band(x[1], ACTION) ~= 0 then sees_action = true end
end
local extra_prev = W.prevExtra
W.prevExtra = function() return ACTION end
open()
local ex_open = GSA1.ExtraButtons(C)
release()
local ex_closed = GSA1.ExtraButtons(C)
W.prevExtra = extra_prev
check(f0 == JUMP and f1 == JUMP and f2 == JUMP and f3 == JUMP and f4 == JUMP and f5 == JUMP + ACTION and not sees_action
    and ex_open == 0 and ex_closed == ACTION, "(6) a press that starts while open is held back until released (the game "
    .. "gets %d, %d, %d, then %d after the release and %d for a new press) and the filter chained after the wheel's never "
    .. "sees it; SA1 L is held back; a jump held before opening stays held (%d); the interact key's synthetic press "
    .. "(GSA1.ExtraButtons) is 0 while open, %d after", f1, f2, f3, f4, f5, f0, ex_closed)

end
-- 7. the mouse wheel ----------------------------------------------------------------------------------------------------------------
do
local w7 = W.Edit("sonic")
w7.pages[2][1] = { body = "a3", name = "s_wait3" }
W.Save()
local cam0 = GSA1.cv.cam_dist:GetFloat()
open()
local p0 = W.page
M.run_hook("PlayerBindPress", M.player, "invnext", true, 113)
local p1 = W.page
local cam1 = GSA1.cv.cam_dist:GetFloat()
release()
M.run_hook("PlayerBindPress", M.player, "invnext", true, 113)
local cam2 = GSA1.cv.cam_dist:GetFloat()
GSA1.cv.cam_dist:SetFloat(cam0)
check(p0 == 1 and p1 == 2 and cam1 == cam0 and cam2 == cam0 + 20, "(7) the mouse wheel through GSA1.BindOverride turns "
    .. "the page while open (%d -> %d) and leaves gsa1_cam_distance alone (%g); closed it changes the camera distance as "
    .. "before (%g -> %g)", p0, p1, cam1, cam0, cam2)

end
-- 8. TAB's own bind ---------------------------------------------------------------------------------------------------------------
do
local b_with = M.run_hook("PlayerBindPress", M.player, "+showscores", true, KEY_TAB)
local b_other = M.run_hook("PlayerBindPress", M.player, "+showscores", true, 22)
GSA1.Remove(true)
local b_without = M.run_hook("PlayerBindPress", M.player, "+showscores", true, KEY_TAB)
C = spawn("sonic")
check(b_with == true and b_other == nil and b_without == nil, "(8) TAB's bind (the scoreboard) is blocked while a character "
    .. "exists and only then; another key's bind is not")

end
-- 9. closing without playing --------------------------------------------------------------------------------------------------
do
local function try_close(setup, undo, what)
    reset_calls()
    open()
    W.sel = 1
    setup()
    frames(1)
    local closed = not W.open
    undo()
    release()
    return closed and #emotes() == 0, what
end
local res9 = {}
res9[#res9 + 1] = { try_close(function() cursor = true end, function() cursor = false end, "the vgui cursor") }
res9[#res9 + 1] = { try_close(function() M.ui = true end, function() M.ui = false end, "the game UI") }
res9[#res9 + 1] = { try_close(function() M.typing = true end, function() M.typing = false end, "typing") }
res9[#res9 + 1] = { try_close(function() blocked = true end, function() blocked = false end, "GSA1.InputBlocked") }
reset_calls()
open()
W.sel = 1
GSA1.Remove(true)
frames(1)
local removed_ok = not W.open
release()
res9[#res9 + 1] = { removed_ok and #emotes() == 0, "the character removed" }
C = spawn("sonic")
local fails9 = {}
for _, x in ipairs(res9) do if not x[1] then fails9[#fails9 + 1] = x[2] end end
check(#fails9 == 0, "(9) the wheel closes and nothing plays on: the vgui cursor, the game UI, typing, GSA1.InputBlocked, "
    .. "the character removed%s", #fails9 > 0 and (": failed " .. table.concat(fails9, ", ")) or "")

end
-- 10. pages -----------------------------------------------------------------------------------------------------------------------
do
local w10 = W.Edit("sonic")
w10.pages[2] = {}
for s = 1, 8 do w10.pages[2][s] = {} end
w10.pages[3][2] = { body = "a5", name = "s_wait_a1" }
W.Save()
R.pad = { connected = true, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }
open()
R.pad.raw = W.PAD_RB
frames(1)
local pr = W.page
R.pad.raw = 0
frames(1)
R.pad.raw = W.PAD_RB
frames(1)
local pr2 = W.page
R.pad.raw = W.PAD_LB
frames(1)
local pl = W.page
R.pad.raw = 0
keys[(KEY_1 or 2) + 3] = true
frames(1)
local k4 = W.sel
keys[(KEY_1 or 2) + 3] = nil
W.sel = 0
release()
R.pad = { connected = false, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }
-- "Clear page" survives a reload
E.SetEntry("sonic")
E.SetPage(1)
E.ClearPage()
W.data = nil
W.Load()
local survived = not W.PageUsed(W.WheelOf("sonic"), 1)
check(pr == 3 and pr2 == 1 and pl == 3 and k4 == 4 and survived, "(10) pages: RB skips the empty page 2 (1 -> %d), turns "
    .. "round (%d), LB back (%d); key 4 lights slot %d; \"Clear page\" survives a reload (page 1 empty, no defaults)", pr,
    pr2, pl, k4)
W.ResetEntry("sonic")

end
-- 11. storage --------------------------------------------------------------------------------------------------------------------
do
local text11 = table.concat({
    "# comment", "version\t1",
    "sonic\t1\t1\ta75\ts_kimepose0\tHappy\tloop\t",
    "sonic\t1\t2\ta3\ts_kimepose0\t-\t-\t",           -- renumbered: a3 is s_wait3 now, the name finds a75
    "sonic\t1\t3\ta200\ts_nothing\t-\t-\t",            -- a name found nowhere: kept, shown missing
    "sonic\t1\t4\tstop\t-\t-\t-\t",
    "sonic\t0\t0\t-\t-\tBlink\t-\t",
    "knuckles\t1\t1\ta39\tk_panch0\t-\t-\t",
    "knuckles\t1\t2\ta54\tk_panch0\t-\t-\t",
    "supersonic\t1\t1\ta75\ts_kimepose0\t-\t-\t",
    "supersonic\t1\t2\ta139\ts_kimepose0\t-\t-\t",
    "tails\t9\t1\ta3\tx\t-\t-\t",                       -- bad: page 9
    "nobody\t1\t1\ta3\tx\t-\t-\t",                      -- bad: no such entry
    "sonic\t1\t5\ta3",                                  -- bad: too few columns
}, "\n") .. "\n"
M.files[W.FILE] = text11
W.data = nil
W.Load()
local ws = W.WheelOf("sonic")
local ls = W.ListOf("sonic")
local s1, s2, s3 = ws.pages[1][1], ws.pages[1][2], ws.pages[1][3]
local e2 = W.Resolve(ls, s2.body, s2.name)
local miss = W.SlotText(s3, ls, 30)
local rt = W.Serialize(W.data)
local again = W.Parse(rt)
local rt2 = W.Serialize(again)
local lk = W.ListOf("knuckles")
local wk = W.WheelOf("knuckles")
local k39 = W.Resolve(lk, wk.pages[1][1].body, wk.pages[1][1].name)
local k54 = W.Resolve(lk, wk.pages[1][2].body, wk.pages[1][2].name)
local lsu = W.ListOf("supersonic")
local wsu = W.WheelOf("supersonic")
local u75 = W.Resolve(lsu, wsu.pages[1][1].body, wsu.pages[1][1].name)
local u139 = W.Resolve(lsu, wsu.pages[1][2].body, wsu.pages[1][2].name)
W.Save()
W.data = nil
W.Load()
local k39b = W.Resolve(lk, W.WheelOf("knuckles").pages[1][1].body, W.WheelOf("knuckles").pages[1][1].name)
local k54b = W.Resolve(lk, W.WheelOf("knuckles").pages[1][2].body, W.WheelOf("knuckles").pages[1][2].name)
local u139b = W.Resolve(lsu, W.WheelOf("supersonic").pages[1][2].body, W.WheelOf("supersonic").pages[1][2].name)
local kept = string.find(M.files[W.FILE], "sonic\t1\t3\ta200\ts_nothing\t", 1, true) ~= nil
check(s1.body == "a75" and s1.face == "Happy" and s1.loop == true and ws.centre.face == "Blink" and e2 and e2.key == "a75"
    and miss == "missing: s_nothing" and kept and s3.body == "a200" and ws.pages[1][4].body == "stop" and rt == rt2 and
    W.badLines == 0 and k39b and k39b.key == "a39" and k54b and k54b.key == "a54" and u139b and u139b.key == "a139",
    "(11) the file: the face and loop columns and the centre line (%s, %s, %s); a renumbered row found by its name "
    .. "(a3 s_kimepose0 -> %s); a name found nowhere kept and shown (\"%s\"); a round trip is identical; k_panch0 a39 / a54 and "
    .. "s_kimepose0 a75 / a139 keep their own keys after a reload (%s %s %s %s)", tostring(s1.body), tostring(s1.face),
    tostring(ws.centre.face), e2 and e2.key or "nil", miss, k39 and k39.key or "nil", k54 and k54.key or "nil",
    u75 and u75.key or "nil", u139 and u139.key or "nil")
local _, bad11 = W.Parse(text11)
local mirror = M.convars.gsa1_wheel_summary.v
check(bad11 == 3 and string.find(mirror, "sonic %d+/33") ~= nil and string.find(mirror, "knuckles 2/33", 1, true) ~= nil and
    string.find(mirror, "supersonic 2/33", 1, true) ~= nil, "(11) bad lines counted (%d of 3: a page 9, an unknown entry, "
    .. "too few columns); the read-only mirror gsa1_wheel_summary = \"%s\"", bad11, mirror)
M.files[W.FILE] = nil
W.data = nil
W.Load()

end
-- 12. the page's list ---------------------------------------------------------------------------------------------------------
do
GSA1.Remove(true)
build_page()
E.SetEntry("knuckles")
local function line_of(name, num)
    for _, l in ipairs(E.list.lines) do
        if l.cols[2] == name and (num == nil or l.cols[1] == num) then return l end
    end
end
local kp39, kp54 = line_of("k_panch0", "39"), line_of("k_panch0", "54")
E.SetEntry("sonic")
local nlines = #E.list.lines
local spin = 0
for _, l in ipairs(E.list.lines) do if l.cols[2] == "s_spin0" then spin = spin + 1 end end
local spinLine = line_of("s_spin0")
local grey40 = line_of("(no label) STG02_0C9E2060", "40")
local grey130 = line_of("ss_wait0", "130")
E.find.value = "kimepose0"
E.Fill()
local found = #E.list.lines
E.find.value = "81"
E.Fill()
local found81 = #E.list.lines == 1 and E.list.lines[1].cols[2] == "s_furatsuki0"
E.find.value = ""
E.groupValue = "air"
E.Fill()
local air = #E.list.lines
E.groupValue = "not usable yet"
E.Fill()
local notusable = #E.list.lines
E.groupValue = "All"
E.Fill()
-- double-click into the selected slot (page 1 slot 3), then the next slot is selected
E.Select(3)
local l3 = line_of("s_awa0")
E.list.DoDoubleClick(E.list, 1, l3)
local w12 = W.WheelOf("sonic")
local put = w12.pages[1][3]
local nextSel = E.sel
-- a greyed row cannot go on the wheel
local before40 = W.WheelOf("sonic").pages[1][4].body
if grey40 then E.list.DoDoubleClick(E.list, 1, grey40) end
local after40 = W.WheelOf("sonic").pages[1][4].body
check(kp39 ~= nil and kp54 ~= nil and spin == 1 and spinLine and string.find(spinLine.tooltip or "", "+1 variant", 1, true)
    and found == 2 and found81 and air == 2 and put.body == "a84" and put.name == "s_awa0" and nextSel == 4 and
    GSA1.Char == nil, "(12) the page lists the rows by internal name and number (%d for Sonic); Knuckles' k_panch0 rows 39 "
    .. "and 54 are two rows, Sonic's s_spin0 variants one (\"%s\"); the find box (\"kimepose0\": %d (a75 and the greyed 139), \"81\": %s) and the group "
    .. "filter (air: %d) work; a double-click fills the selected slot (p1 s3 = %s) and selects the next (%d); edited "
    .. "without a character", nlines, spinLine and spinLine.tooltip or "?", found, tostring(found81), air,
    tostring(put.body), nextSel)
check(grey40 ~= nil and grey40.gsa1Row and grey40.gsa1Row.greyed ~= nil and string.find(grey40.tooltip or "",
    "Windy Valley", 1, true) and grey130 and string.find(grey130.tooltip or "", "Super Sonic", 1, true) and
    after40 == before40 and notusable == 35, "(12) owner answer FQ19: the rows that cannot play are listed greyed with "
    .. "the reason as the tooltip (\"%s\"), %d for Sonic, and a double-click does not put one on the wheel",
    grey40 and grey40.tooltip or "missing", notusable)
W.ResetEntry("sonic")
C = spawn("sonic")

end
-- 13. a refusal -------------------------------------------------------------------------------------------------------------------
do
reset_calls()
R.refuse = "moving"
open()
W.sel = 1
release()
local toast13 = W.toastText or ""
R.refuse = nil
check(#emotes() == 1 and string.find(toast13, "moving", 1, true) and string.find(toast13, "let go of the stick", 1, true) and
    log_has("emote%s+s_kimepose0 refused %(unsupported%): moving"), "(13) a refusal: the toast gives libsa1's reason "
    .. "(\"%s\") and an \"emote ... refused\" log line", toast13)

end
-- 14. "stop while choosing" -------------------------------------------------------------------------------------------------------
do
RunConsoleCommand("gsa1_wheel_move", "0")
local cx1, cy1 = GSA1.FilterStick(C, 0.5, 0.25)
open()
local ox, oy = GSA1.FilterStick(C, 0.5, 0.25)
release()
RunConsoleCommand("gsa1_wheel_move", "1")
open()
local mx, my = GSA1.FilterStick(C, 0.5, 0.25)
release()
check(cx1 == 0.5 and cy1 == 0.25 and ox == 0 and oy == 0 and mx == 0.5 and my == 0.25, "(14) gsa1_wheel_move 0: "
    .. "GSA1.FilterStick gives 0, 0 only while the wheel is open (closed: the stick; with 1: the stick while open)")

end
-- 15. the face trigger ---------------------------------------------------------------------------------------------------------
do
local function face_calls() return calls_of("FacePlay") end
local function trigger_click()
    keys[MOUSE_LEFT] = true
    frames(1)
    keys[MOUSE_LEFT] = nil
end
reset_calls()
open()
W.sel = 1
trigger_click()
local closed15 = not W.open
release()
local e15, f15 = emotes(), face_calls()
check(closed15 and #e15 == 1 and e15[1][3] == "a75" and #f15 == 1 and f15[1][2] == C.id and f15[1][3] == "Happy" and
    f15[1][4] == "wheel", "(15) the left click in the open wheel on slot 1 (s_kimepose0 with Happy): Emote(a75) and "
    .. "GSA1.Faces.Play(C, Happy, wheel) once each, the wheel closes and the release plays nothing more (%d / %d calls)",
    #e15, #f15)
reset_calls()
R.pad = { connected = true, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }
open()
W.sel = 1
R.pad.raw = 0x10000
frames(1)
R.pad.raw = 0
release()
local eLT, fLT = emotes(), face_calls()
reset_calls()
open()
W.sel = 0
trigger_click()
release()
local eC, fC = emotes(), face_calls()
check(#eLT == 1 and #fLT == 1 and #eC == 0 and #fC == 1 and fC[1][3] == "Happy", "(15) LT (pad bit 0x10000) the same; "
    .. "at the centre only the centre's face animation (%s), no body animation", fC[1] and fC[1][3] or "none")
GSA1.Remove(true)
C = spawn("gamma")
reset_calls()
open()
W.sel = 1
trigger_click()
release()
local eG, fG = emotes(), face_calls()
GSA1.Remove(true)
C = spawn("big")
local wb = W.Edit("big")
wb.pages[1][1].face = "Happy"           -- a face Big cannot show
reset_calls()
open()
W.sel = 1
trigger_click()
release()
local eB, fB = emotes(), face_calls()
local toastB = W.toastText or ""
W.ResetEntry("big")
GSA1.Remove(true)
C = spawn("sonic")
RunConsoleCommand("gsa1_wheel_face_key", "16")
RunConsoleCommand("gsa1_wheel_face_pad", "131072")
reset_calls()
open()
W.sel = 1
trigger_click()                         -- the left click is no trigger now
local still = W.open
keys[16] = true
frames(1)
keys[16] = nil
release()
local eR, fR = emotes(), face_calls()
RunConsoleCommand("gsa1_wheel_face_key", "107")
RunConsoleCommand("gsa1_wheel_face_pad", "65536")
check(#eG == 1 and #fG == 0 and #eB == 1 and #fB == 0 and string.find(toastB, "Big can't show b", 1, true) and still and
    #eR == 1 and #fR == 1, "(15) E-102: the body only; Big with a face he cannot show: the body plays and the toast says "
    .. "why (\"%s\"); rebound to F / RT: the left click does nothing, F triggers", toastB)
R.pad = { connected = false, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }

end
-- 16. the face library changed ----------------------------------------------------------------------------------------------------
do
local w16 = W.Edit("sonic")
w16.pages[2][1] = { body = "a3", name = "s_wait3", face = "Happy" }
W.Save()
hook.Run("GSA1FaceLibraryChanged", { renamed = { Happy = "Grin" }, deleted = { Blink = true } })
local s16 = W.WheelOf("sonic")
local t16 = W.WheelOf("tails")
local file16 = M.files[W.FILE] or ""
check(s16.pages[1][1].face == "Grin" and s16.pages[2][1].face == "Grin" and s16.centre.face == "Grin" and
    s16.pages[1][3].face == nil and t16.pages[1][1].face == "Grin" and t16.pages[1][4].face == nil and
    string.find(file16, "\tGrin\t", 1, true) and not string.find(file16, "\tHappy\t", 1, true),
    "(16) GSA1FaceLibraryChanged: Happy renamed to Grin in every slot and the centre (also in a wheel still on its "
    .. "defaults), Blink deleted -> cleared, the file saved")
M.files[W.FILE] = nil
W.data = nil
W.Load()

end
-- 17. the playing one again, "(stop)" ------------------------------------------------------------------------------------------------
do
reset_calls()
open()
W.sel = 1
release()                         -- plays a75
R.calls = {}
open()
W.sel = 1
release()                         -- the playing one again
local stops = calls_of("EmoteStop")
local e17 = #emotes()
local w17 = W.Edit("sonic")
w17.pages[1][2] = { body = "stop" }
W.Save()
reset_calls()
open()
W.sel = 2
release()
local stops2 = calls_of("EmoteStop")
check(e17 == 0 and #emotes() == 0 and #stops == 1 and stops[1][3] == 1 and #stops2 == 1 and stops2[1][3] == 0,
    "(17) the playing animation chosen again -> EmoteStop(id, STOP_BLEND); \"(stop)\" -> EmoteStop(id, STOP_NOW)")
W.ResetEntry("sonic")

end
-- 18. "loop it", "in the air" ----------------------------------------------------------------------------------------------------
do
local w18 = W.Edit("sonic")
w18.pages[1][3].loop = true
W.Save()
reset_calls()
open()
W.sel = 3
release()
local fl1 = emotes()[1]
RunConsoleCommand("gsa1_wheel_air", "1")
R.state = {}
reset_calls()
open()
W.sel = 5
release()
local fl2 = emotes()[1]
RunConsoleCommand("gsa1_wheel_air", "0")
R.state = {}
reset_calls()
open()
W.sel = 5
release()
local fl3 = emotes()[1]
W.ResetEntry("sonic")
check(fl1 and fl1[3] == "a5" and fl1[4] == 0x100 and fl2 and fl2[3] == "a70" and fl2[4] == 4 and fl3 and fl3[4] == 0,
    "(18) \"loop it\" sends EMOTE.LOOP (%s), gsa1_wheel_air 1 sends EMOTE.IN_AIR (%s), 0 neither (%s)",
    tostring(fl1 and fl1[4]), tostring(fl2 and fl2[4]), tostring(fl3 and fl3[4]))

end
-- 19. "Hold the last pose" (round 0.9.4b, objects2_plan.md 11.2) ----------------------------------------------------------------
do
local HOLD, LOOP = G.EMOTE.HOLD, G.EMOTE.LOOP
local pure = W.HoldApplies({}, { play = "once" }) and W.HoldApplies({}, { play = "hold" }) and
    not W.HoldApplies({}, { play = "loop" }) and not W.HoldApplies({ loop = true }, { play = "once" }) and
    not W.HoldApplies({ nohold = true }, { play = "once" }) and not W.HoldApplies({}, nil)
W.ResetEntry("sonic")
reset_calls()
open()
W.sel = 1                                   -- a75 s_kimepose0, plays once: holds by default
release()
local f1 = emotes()[1]
local toast19 = W.toastText or ""
local logged = log_has("played s_kimepose0 %(#75%) from page 1 slot 1 of Sonic's wheel %(release%), holds its last pose")
-- the held pose chosen again: back to standing with a blend
R.state[C.id] = { 3, "a75" }                -- EmoteState: HOLDING
R.calls = {}
open()
W.sel = 1
release()
local again = calls_of("EmoteStop")
local again_e = #emotes()
R.state = {}
-- the page's check box: switched off for slot 1 -> the file keeps "nohold", the release sends no HOLD
build_page()
E.SetEntry("sonic")
E.Select(1)
local function last_of(P, name)
    local v
    for _, c in ipairs(P and P.calls or {}) do if c[1] == name then v = c[2] end end
    return v
end
local checked1 = last_of(E.holdBox, "SetChecked")
local enabled1 = last_of(E.holdBox, "SetEnabled")
if E.holdBox and E.holdBox.OnChange then E.holdBox.OnChange(E.holdBox, false) end
local file19 = M.files[W.FILE] or ""
local off_note = E.HoldNote()
reset_calls()
open()
W.sel = 1
release()
local f2 = emotes()[1]
R.state = {}
W.data = nil
W.Load()
local kept = W.WheelOf("sonic").pages[1][1].nohold == true
-- a looping animation (slot 4: a26 s_rollfly loops) gets no HOLD, and its box is greyed
E.Select(4)
local enabled4 = last_of(E.holdBox, "SetEnabled")
reset_calls()
open()
W.sel = 4
release()
local f4 = emotes()[1]
R.state = {}
-- an animation from the console (gsa1_emote) holds too
reset_calls()
M.cmds.gsa1_emote(nil, "gsa1_emote", { "s_kimepose0" }, "s_kimepose0")
local fc = emotes()[1]
R.state = {}
-- a module without HOLD (0.9.4a's feature "emote" 1): 0.9.4a's flags
G.EMOTE.HOLD = nil
reset_calls()
open()
W.sel = 2                                   -- a3 s_wait3, once
release()
local f0 = emotes()[1]
local old_note = E.HoldNote()
G.EMOTE.HOLD = HOLD
R.state = {}
-- the file's options column: "loop,nohold" both ways
local parsed, badp = W.Parse("sonic\t1\t2\ta3\ts_wait3\t-\tloop,nohold\t\n")
local ps = parsed.sonic and parsed.sonic.pages[1][2]
local back = W.Serialize(parsed)
check(pure and f1 and f1[3] == "a75" and f1[4] == HOLD and string.find(toast19, "holds the pose", 1, true) and logged and
    again_e == 0 and #again == 1 and again[1][3] == G.EMOTE.STOP_BLEND,
    "(19) \"Hold the last pose\" is on by default: an animation that plays once is sent with gsa1.EMOTE.HOLD (a75: %s; "
    .. "the toast \"%s\", the log says so); the held pose chosen again (HOLDING) -> EmoteStop(STOP_BLEND)",
    tostring(f1 and f1[4]), toast19)
check(checked1 == true and enabled1 == true and string.find(file19, "sonic\t1\t1\ta75\ts_kimepose0\tHappy\tnohold\t", 1, true)
    and f2 and f2[4] == 0 and kept and string.find(off_note, "back to standing", 1, true) and enabled4 == false and
    f4 and f4[3] == "a26" and f4[4] == 0 and fc and fc[3] == "a75" and fc[4] == HOLD,
    "(19) the page's check box (on and enabled for a75) switched off: the file keeps \"nohold\" and the release sends %s "
    .. "(kept after a reload: %s); greyed for a looping animation (a26 sends %s); gsa1_emote s_kimepose0 holds (%s)",
    tostring(f2 and f2[4]), tostring(kept), tostring(f4 and f4[4]), tostring(fc and fc[4]))
check(f0 and f0[3] == "a3" and f0[4] == 0 and string.find(old_note, "0.9.4b", 1, true) and badp == 0 and ps and
    ps.loop == true and ps.nohold == true and string.find(back, "\tloop,nohold\t", 1, true),
    "(19) a module without HOLD gets 0.9.4a's flags (%s) and the page says why; the file's options \"loop,nohold\" parse "
    .. "and print back", tostring(f0 and f0[4]))
W.ResetEntry("sonic")

end
-- 20. the fonts follow the wheel's size and the screen; none is made per frame (round 0.9.4b) ------------------------------
do
local function made_since(n0)
    local out = {}
    for i = n0 + 1, #fonts_made do out[#out + 1] = fonts_made[i] end
    return out
end
local function size_of(name)
    for _, f in ipairs(fonts_made) do if f.name == name then return f.data.size end end
end
local function paint(n)
    for _ = 1, n or 1 do M.run_hook("HUDPaint") end
end
W.fontMade, W.fontH, W.geo = {}, nil, nil
fonts_made = {}
RunConsoleCommand("gsa1_wheel_size", "1")
open()
W.sel = 1
paint(3)
local first = made_since(0)
local faces = {}
for _, f in ipairs(first) do faces[f.data.font] = true end
local label1, big1 = W.font.label, W.font.big
local px1 = { label = size_of(label1), big = size_of(big1), small = size_of(W.font.small) }
local n0 = #fonts_made
for _ = 1, 100 do
    M.frame()
    paint(1)
end
local per_frame = #fonts_made - n0
RunConsoleCommand("gsa1_wheel_size", "2")
paint(2)
local made2 = #made_since(n0)
local px2 = { label = size_of(W.font.label), big = size_of(W.font.big), small = size_of(W.font.small) }
local label_texts = 0
reset_drawn()
paint(1)
for _, t in ipairs(drawn.texts) do if t.font == W.font.label then label_texts = label_texts + 1 end end
local n2 = #fonts_made
RunConsoleCommand("gsa1_wheel_size", "1")
paint(2)
local reused = #fonts_made == n2 and W.font.label == label1
RunConsoleCommand("gsa1_wheel_size", "0.5")
paint(1)
local px05 = size_of(W.font.label)
RunConsoleCommand("gsa1_wheel_size", "1")
RunConsoleCommand("gsa1_wheel_font", "1")
local n3 = #fonts_made
paint(1)
local segoe = made_since(n3)
local segoe_ok = #segoe == 4
for _, f in ipairs(segoe) do segoe_ok = segoe_ok and f.data.font == "Segoe UI" end
RunConsoleCommand("gsa1_wheel_font", "0")
-- a new screen: the fonts are made again at the new height
M.scrh = 720
M.run_hook("OnScreenSizeChanged", 3440, 1440)
local n4 = #fonts_made
paint(1)
local px720 = size_of(W.font.label)
local made720 = #made_since(n4)
M.scrh = 1440
M.run_hook("OnScreenSizeChanged", 3440, 720)
paint(1)
release()
R.state = {}
local ratio = px2.label / px1.label
check(#first == 4 and faces["Roboto Cn"] and faces["Roboto"] and faces["Roboto Bk"] and W.FontData("big", 0, 40).font ==
    "Roboto Cn" and per_frame == 0 and made2 == 3 and
    ratio > 1.85 and ratio < 2.15 and px2.big > px1.big * 1.85 and px2.small > px1.small * 1.8 and reused and px05 and
    px05 < px1.label * 0.6 and label_texts == 16,
    "(20) the fonts: %d made at the first draw (Garry's Mod's own Roboto: Roboto Cn / Roboto / Roboto Bk); %d made in 100 "
    .. "more frames; size 2: %d new (the toast's follows the screen only), label %d -> %d px (x%.2f), big %d -> %d, small %d -> %d, the 8 labels drawn with it "
    .. "(%d texts with their shadows); size 1 again reuses the first fonts (%s); size 0.5: label %s px", #first, per_frame,
    made2, px1.label or -1, px2.label or -1, ratio, px1.big or -1, px2.big or -1, px1.small or -1, px2.small or -1,
    label_texts, tostring(reused), tostring(px05))
check(segoe_ok and made720 == 4 and px720 and math.abs(px720 - px1.label / 2) <= 2,
    "(20) gsa1_wheel_font 1 makes the Segoe UI fonts; a screen of 720 lines makes them again at half the size (label %s px)",
    tostring(px720))

end
-- 21. the design: lit slot, accent colours, face markers, the centre, page markers, the animations (round 0.9.4b) --------------
do
local function paint(n)
    for _ = 1, n or 1 do M.run_hook("HUDPaint") end
end
local function has_colour(rgb, amin, amax)
    for _, c in ipairs(drawn.colours) do
        if c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3] and (c[4] or 0) >= amin and (c[4] or 0) <= (amax or 255) then
            return true
        end
    end
    return false
end
local function count_colour(rgb)
    local n = 0
    for _, c in ipairs(drawn.colours) do
        if c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3] then n = n + 1 end
    end
    return n
end
W.ResetEntry("sonic")
reset_drawn()
open()
paint(1)
local bg0 = drawn.colours[1] and drawn.colours[1][4] or -1    -- the first sector's glass at the start of the opening
W.sel = 1
for _ = 1, 12 do
    M.frame()
    paint(1)
end
reset_drawn()
paint(1)
local bg1 = drawn.colours[1] and drawn.colours[1][4] or -1
local blue = W.COLOURS.sonic
local lit_blue = has_colour(blue, 190)
local glow1 = W.glow[1] or 0
local marks = count_colour({ 255, 206, 72 })
local big
for _, t in ipairs(drawn.texts) do if t.font == W.font.big and t.text == "s_kimepose0" then big = t end end
local rects1 = drawn.rects
-- another slot: the highlight fades over, it does not jump
W.sel = 2
paint(1)
local g1, g2 = W.glow[1] or 0, W.glow[2] or 0
paint(12)
local g1b, g2b = W.glow[1] or 0, W.glow[2] or 0
-- the mouse: a pointer toward it
M.run_hook("InputMouseApply", newcmd(), 400, 0, Angle())
reset_drawn()
paint(1)
local pointer = has_colour(blue, 230, 230) and W.pointDeg ~= nil
-- Sonic turned Super: gold
C.superForm = true
reset_drawn()
paint(1)
local gold_lit = has_colour(W.GOLD, 190) and not has_colour(blue, 190)
C.superForm = nil
-- a second page: page markers above the wheel
local w21 = W.Edit("sonic")
w21.pages[2][1] = { body = "a3", name = "s_wait3" }
W.wheel = W.WheelOf("sonic")
reset_drawn()
paint(1)
local rects2 = drawn.rects
-- every shape runs clockwise on screen (surface.DrawPoly draws nothing otherwise)
local geo = W.Geometry()
local wrong_way, shapes = 0, 0
local function clockwise(list)
    for _, q in ipairs(list) do
        shapes = shapes + 1
        if W.PolyArea2(q) <= 0 then wrong_way = wrong_way + 1 end
    end
end
for sl = 1, 8 do
    clockwise(geo.sectors[sl])
    clockwise(geo.rims[sl])
    clockwise(geo.lit[sl])
    clockwise(geo.litRims[sl])
    clockwise({ geo.marks[sl] })
    clockwise({ W.NeedlePoly(geo, sl * 45 - 30) })
end
clockwise(geo.ring)
clockwise(geo.seps)
clockwise({ geo.disc })
W.Close("test", false)
release()
W.fadeFrom = nil
W.ResetEntry("sonic")
R.state = {}
check(bg0 == 0 and bg1 > 180 and lit_blue and glow1 > 0.95 and marks == 5 and big ~= nil and rects1 == 0 and rects2 == 2 and
    W.Accent("supersonic")[1] == W.GOLD[1] and W.Accent("supersonic_general")[3] == W.GOLD[3],
    "(21) the wheel opens from transparent (glass alpha %s, then %s); the highlighted slot is lit in Sonic blue (glow %.2f); "
    .. "the 5 slots with a face animation carry a gold marker (%d); the centre shows \"s_kimepose0\" in the big font; page "
    .. "markers only with more than one page (%d, then %d); both Super Sonic entries are gold", tostring(bg0),
    tostring(bg1), glow1, marks, rects1, rects2)
check(g1 > 0.5 and g1 < 0.99 and g2 > 0.05 and g2 < 0.5 and g1b < 0.02 and g2b > 0.95 and pointer and gold_lit and
    wrong_way == 0 and shapes > 250,
    "(21) the highlight fades from slot 1 to slot 2 (first frame %.2f / %.2f, then %.2f / %.2f); the mouse shows a pointer; "
    .. "Sonic turned Super lights the wheel in gold; all %d shapes run clockwise on screen (%d do not)", g1, g2, g1b, g2b,
    shapes, wrong_way)

end
-- 22. "Hide the wheel" (round 0.9.4e): it works as usual and draws nothing --------------------------------------------------
local function trigger_click22()
    keys[MOUSE_LEFT] = true
    frames(1)
    keys[MOUSE_LEFT] = nil
end
-- one run of the wheel with every input (the same for hidden and shown): what played and what was drawn
local function wheel_run()
    W.ResetEntry("sonic")
    reset_calls()
    R.state = {}
    polys = 0
    reset_drawn()
    local fonts0 = #fonts_made
    W.fontMade, W.fontH, W.geo = {}, nil, nil
    W.toastText, W.toastUntil = nil, 0
    local out = {}
    -- the mouse lights slot 1, the release plays it
    open()
    M.run_hook("HUDPaint")
    local cmd = newcmd()
    out.mouse = M.run_hook("InputMouseApply", cmd, 0, -400, Angle())
    out.mouseZero = cmd.mx == 0 and cmd.my == 0
    out.sel1 = W.sel
    for _ = 1, 10 do
        M.frame()
        M.run_hook("HUDPaint")
    end
    release()
    out.fadeAfterRelease = W.fadeFrom ~= nil
    for _ = 1, 3 do
        M.frame()
        M.run_hook("HUDPaint")
    end
    -- the right stick lights slot 3 (right), the release plays it
    R.state = {}
    R.pad = { connected = true, raw = 0, rx = 1, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }
    open()
    frames(1)
    out.stick = W.sel
    M.run_hook("HUDPaint")
    release()
    R.pad = { connected = false, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }
    -- key 5 lights slot 5, the face trigger plays its animation with its face (slot 5: a70 with Shock)
    R.state = {}
    open()
    keys[(KEY_1 or 2) + 4] = true
    frames(1)
    keys[(KEY_1 or 2) + 4] = nil
    out.key5 = W.sel
    M.run_hook("HUDPaint")
    trigger_click22()
    out.closedByFace = not W.open
    release()
    -- the centre: the face trigger plays only the centre's face animation (Happy)
    open()
    W.sel = 0
    M.run_hook("HUDPaint")
    trigger_click22()
    release()
    for _ = 1, 3 do
        M.frame()
        M.run_hook("HUDPaint")
    end
    local e, f = {}, {}
    for _, c in ipairs(calls_of("Emote")) do e[#e + 1] = c[3] end
    for _, c in ipairs(calls_of("FacePlay")) do f[#f + 1] = c[3] end
    out.emotes, out.faces = table.concat(e, " "), table.concat(f, " ")
    out.polys, out.texts, out.rects, out.colours = polys, #drawn.texts, drawn.rects, #drawn.colours
    out.fonts = #fonts_made - fonts0
    out.toastShown = (W.toastUntil or 0) > SysTime()
    R.state = {}
    return out
end
do
RunConsoleCommand("gsa1_wheel_hidden", "1")
local h = wheel_run()
local hlog = log_has("emote%s+played s_kimepose0")
RunConsoleCommand("gsa1_wheel_hidden", "0")
local v = wheel_run()
check(h.mouse == true and h.mouseZero and h.sel1 == 1 and h.stick == 3 and h.key5 == 5 and h.closedByFace and
    h.emotes == "a75 a5 a70" and h.faces == "Shock Happy" and h.emotes == v.emotes and h.faces == v.faces and hlog,
    "(22) hidden, the wheel works exactly as usual: the mouse lights slot %s (the mouse zeroed), the right stick slot %s, "
    .. "key 5 slot %s, the releases and the face trigger play %s with the faces %s, the centre's face alone (shown: %s / "
    .. "%s - the same calls); the session log still says what played", tostring(h.sel1), tostring(h.stick),
    tostring(h.key5), h.emotes, h.faces, v.emotes, v.faces)
check(h.polys == 0 and h.texts == 0 and h.rects == 0 and h.colours == 0 and h.fonts == 0 and not h.fadeAfterRelease and
    not h.toastShown and v.polys > 100 and v.texts > 20 and v.fadeAfterRelease and v.toastShown,
    "(22) hidden, the HUD draws nothing: %d polygons, %d texts, %d rectangles, %d colours, %d fonts made, no fade after the "
    .. "release, no toast (shown, the same run draws %d polygons and %d texts, fades out and shows the toast)", h.polys,
    h.texts, h.rects, h.colours, h.fonts, v.polys, v.texts)
-- hidden while the toast and the fade are on screen: both end at once
W.ResetEntry("sonic")
reset_calls()
open()
W.sel = 1
release()
local before = (W.toastUntil or 0) > SysTime() and W.fadeFrom ~= nil
RunConsoleCommand("gsa1_wheel_hidden", "1")
polys = 0
reset_drawn()
M.run_hook("HUDPaint")
RunConsoleCommand("gsa1_wheel_hidden", "0")
M.run_hook("HUDPaint")
local after = polys == 0 and #drawn.texts == 0 and W.fadeFrom == nil and (W.toastUntil or 0) <= SysTime()
R.state = {}
check(before and after, "(22) hiding while the fade and the toast are on screen ends both at once (nothing drawn then, "
    .. "nothing left over when it is shown again)")

end
-- 23. the hide key (round 0.9.4e) -------------------------------------------------------------------------------------------------
do
local notes = {}
local prevNotification = notification
notification = { AddLegacy = function(text, kind, len) notes[#notes + 1] = { text = text, len = len } end }
local KEY_H = 18
RunConsoleCommand("gsa1_wheel_hide_key", tostring(KEY_H))
local set = M.convars.gsa1_wheel_hide_key.v
local function press(n)
    keys[KEY_H] = true
    frames(n or 1)
    keys[KEY_H] = nil
    frames(1)
end
press(1)
local h1, n1 = M.convars.gsa1_wheel_hidden.v, #notes
local logOn = log_has("emote%s+wheel hidden by the hide key")
press(5)                                        -- held 5 frames: one toggle
local h2, n2 = M.convars.gsa1_wheel_hidden.v, #notes
local noteText = notes[1] and notes[1].text or ""
local logOff = log_has("emote%s+wheel shown by the hide key")
cursor = true                                   -- a menu has the input: the key does nothing
press(1)
local h3 = M.convars.gsa1_wheel_hidden.v
cursor = false
-- the console command: the same toggle and the same rule
M.cmds.gsa1_wheel_hide_toggle(nil, "gsa1_wheel_hide_toggle", {}, "")
local h4, n4 = M.convars.gsa1_wheel_hidden.v, #notes
M.cmds.gsa1_wheel_hide_toggle(nil, "gsa1_wheel_hide_toggle", {}, "")
local h5, n5 = M.convars.gsa1_wheel_hidden.v, #notes
-- refused as the hide key: the wheel key, the face trigger, the jump key (the old key stays); the wheel key and the face
-- trigger refuse the hide key
RunConsoleCommand("gsa1_wheel_hide_key", "67")
local r1 = M.convars.gsa1_wheel_hide_key.v
RunConsoleCommand("gsa1_wheel_hide_key", "107")
local r2 = M.convars.gsa1_wheel_hide_key.v
RunConsoleCommand("gsa1_wheel_hide_key", "65")
local r3 = M.convars.gsa1_wheel_hide_key.v
RunConsoleCommand("gsa1_wheel_key", tostring(KEY_H))
local r4 = M.convars.gsa1_wheel_key.v
RunConsoleCommand("gsa1_wheel_face_key", tostring(KEY_H))
local r5 = M.convars.gsa1_wheel_face_key.v
-- the wheel works while the hide key is held (no interference) and "No hide key" (0) stops the key
RunConsoleCommand("gsa1_wheel_hide_key", "0")
press(1)
local h6 = M.convars.gsa1_wheel_hidden.v
notification = prevNotification
check(set == "18" and h1 == "1" and n1 == 0 and logOn and h2 == "0" and n2 == 1 and
    string.find(noteText, "shown again", 1, true) and logOff and h3 == "0" and h4 == "1" and n4 == 1 and h5 == "0" and
    n5 == 2 and h6 == "0",
    "(23) the hide key: a press hides (%s) and shows NOTHING (%d notes), held it toggles once (%s), turning it off shows one "
    .. "small note (\"%s\"), both logged; with a menu open it does nothing (%s); gsa1_wheel_hide_toggle the same (%s, %d "
    .. "notes; %s, %d); key 0 does nothing (%s)", h1, n1, h2, noteText, h3, h4, n4, h5, n5, h6)
check(r1 == "18" and r2 == "18" and r3 == "18" and r4 == "67" and r5 == "107",
    "(23) refused as the hide key: the wheel key, the face trigger, the jump key (it stays %s, %s, %s); the wheel key and "
    .. "the face trigger refuse the hide key (%s, %s)", r1, r2, r3, r4, r5)

end
-- 24. the play rate (round 0.9.4e): the slot's x gsa1_wheel_speed reaches gsa1.Emote's 4th argument ---------------------------
do
W.ResetEntry("sonic")
local w24 = W.Edit("sonic")
w24.pages[1][1].speed = 2              -- a75 s_kimepose0 (Happy)
w24.pages[1][2].speed = 0.25           -- a3 s_wait3
w24.pages[1][4].speed = 4              -- a26 s_rollfly
W.Save()
local function play_slot(sel)
    R.state = {}
    reset_calls()
    open()
    W.sel = sel
    release()
    local e = emotes()[1]
    R.state = {}
    return e
end
local function rate_of(e) return e and e[5] end
local a1 = play_slot(1)
local toast24 = W.toastText or ""
local log24 = log_has("played s_kimepose0 %(#75%) from page 1 slot 1 of Sonic's wheel %(release%), holds its last pose, at 2x")
RunConsoleCommand("gsa1_wheel_speed", "1.5")
local a2 = play_slot(1)
RunConsoleCommand("gsa1_wheel_speed", "0.5")
local a3 = play_slot(3)                -- a26 s_rollfly: own 1x
RunConsoleCommand("gsa1_wheel_speed", "0.25")
local a4 = play_slot(2)                -- 0.25 x 0.25
RunConsoleCommand("gsa1_wheel_speed", "4")
local a5 = play_slot(4)                -- 4 x 4 = 16 (libsa1's top)
RunConsoleCommand("gsa1_wheel_speed", "1")
-- the face trigger: the body at its rate, the face animation as before (no rate: it keeps its own timing)
reset_calls()
open()
W.sel = 1
keys[MOUSE_LEFT] = true
frames(1)
keys[MOUSE_LEFT] = nil
release()
local fe, ff = emotes()[1], calls_of("FacePlay")[1]
R.state = {}
-- the centre line of the open wheel says the rate
open()
W.sel = 1
local lines = W.CentreLines()
W.Close("test", false)
release()
check(rate_of(a1) == 2 and a1[4] == G.EMOTE.HOLD and string.find(toast24, "at 2x", 1, true) and log24 and
    rate_of(a2) == 3 and rate_of(a3) == 0.5 and math.abs((rate_of(a4) or 0) - 1 / 16) < 1e-9 and rate_of(a5) == 16 and
    fe and rate_of(fe) == 2 and ff and ff[3] == "Happy" and #ff == 4 and string.find(lines[3] or "", "at 2x", 1, true),
    "(24) the slot's rate x gsa1_wheel_speed reaches gsa1.Emote's 4th argument: 2 x 1 = %s (with HOLD; the toast \"%s\" "
    .. "and the log say it), 2 x 1.5 = %s, 1 x 0.5 = %s, 0.25 x 0.25 = %s, 4 x 4 = %s; the face trigger: the body at %s, "
    .. "the face animation Faces.Play(C, %s, wheel) as before; the centre: \"%s\"", tostring(rate_of(a1)), toast24,
    tostring(rate_of(a2)), tostring(rate_of(a3)), tostring(rate_of(a4)), tostring(rate_of(a5)),
    tostring(fe and rate_of(fe)), tostring(ff and ff[3]), tostring(lines[3]))
-- the page: the rate box of the selected slot, the file's 9th column
build_page()
E.SetEntry("sonic")
E.Select(3)                            -- a5 s_wait_a1 (Blink)
local box = E.speedCombo
local nchoices = box and box.choices and #box.choices or 0
local boxOk = box ~= nil and box.OnSelect ~= nil and nchoices == 8
if box and box.OnSelect then box.OnSelect(box, 6, "2x", "2") end
local file24 = M.files[W.FILE] or ""
local col9 = string.find(file24, "sonic\t1\t3\ta5\ts_wait_a1\tBlink\t-\t\t2\n", 1, true) ~= nil
local note24 = E.SpeedNote()
local refused = E.SetSpeed(8) == false and W.WheelOf("sonic").pages[1][3].speed == 2
E.SetSpeed(1)
local file24b = M.files[W.FILE] or ""
local back1 = string.find(file24b, "sonic\t1\t3\ta5\ts_wait_a1\tBlink\t-\t\n", 1, true) ~= nil
W.data = nil
W.Load()
local kept = W.WheelOf("sonic").pages[1][1].speed == 2 and W.WheelOf("sonic").pages[1][3].speed == nil
check(boxOk and col9 and refused and back1 and kept and string.find(note24, "keeps its own timing", 1, true),
    "(24) the page's \"Play rate\" box (%d choices 0.25x-4x) sets the selected slot: the file's 9th column \"2\"; 1x writes "
    .. "none; 8 is refused; kept after a reload; the note: \"%s\"", nchoices, note24)
-- a module without the play rate (feature "emote" 2, 0.9.4d): three arguments, as before; the page says why
G.FEATURES.emote = 2
W.ResetHave()
local o1 = play_slot(1)
local oldNote = E.SpeedNote()
local oldStatus = table.concat(W.StatusLines(E), "\n")
G.FEATURES.emote = 3
W.ResetHave()
check(o1 and o1[3] == "a75" and o1[4] == G.EMOTE.HOLD and o1[5] == nil and string.find(oldNote, "0.9.4e", 1, true) and
    string.find(oldStatus, "0.9.4e", 1, true),
    "(24) a module with feature \"emote\" 2 gets Emote(id, a75, HOLD) without a rate (%s) and the page says play rates "
    .. "need 0.9.4e", tostring(o1 and o1[5]))
W.ResetEntry("sonic")

end
-- 25. an old wheel file (0.9.4d: no speeds) loads as 1x; the 9th column; 0.9.4d's reader --------------------------------------
do
local old = table.concat({
    "# G-SA1 emote wheel (0.9.4d)", "version\t1",
    "sonic\t1\t1\ta75\ts_kimepose0\tHappy\t-\t",
    "sonic\t1\t2\ta3\ts_wait3\t-\tloop\t",
    "sonic\t1\t3\ta26\ts_rollfly\tSurprised\tnohold\t",
    "sonic\t0\t0\t-\t-\tBlink\t-\t",
}, "\n") .. "\n"
M.files[W.FILE] = old
W.data = nil
W.Load()
local ws = W.WheelOf("sonic")
local all1 = true
for p = 1, W.PAGES do
    for sl = 1, W.SLOTS do
        local o = ws.pages[p][sl]
        if o.speed ~= nil or W.SlotSpeed(o) ~= 1 then all1 = false end
    end
end
R.state = {}
reset_calls()
open()
W.sel = 2
release()
local e25 = emotes()[1]
R.state = {}
local out = W.Serialize(W.data)
local same = true
for line in string.gmatch(old, "[^\n]+") do
    if string.sub(line, 1, 6) == "sonic\t" and not string.find(out, line .. "\n", 1, true) then same = false end
end
-- the speed column: good and bad values
local p1, b1 = W.Parse("sonic\t1\t1\ta75\ts_kimepose0\t-\t-\t\t0.5\nsonic\t1\t2\ta3\ts_wait3\t-\t-\t\t1\n")
local p2, b2 = W.Parse("sonic\t1\t1\ta75\ts_kimepose0\t-\t-\t\t8\nsonic\t1\t2\ta3\ts_wait3\t-\t-\t\tfast\n" ..
    "sonic\t1\t3\ta3\ts_wait3\t-\t-\t\t-1\nsonic\t1\t4\ta3\ts_wait3\t-\t-\t\t1e1\n")
local good = b1 == 0 and p1.sonic and p1.sonic.pages[1][1].speed == 0.5 and p1.sonic.pages[1][2].speed == nil
check(all1 and e25 and e25[3] == "a3" and e25[4] == 0x100 and e25[5] == 1 and same and good and b2 == 4,
    "(25) a 0.9.4d wheel file without speeds loads as 1x everywhere (slot 2 plays Emote(a3, LOOP, %s)) and its slot lines "
    .. "print back unchanged; the 9th column \"0.5\" reads 0.5, \"1\" nothing; 8, \"fast\", -1 and 1e1 are bad lines (%d of 4)",
    tostring(e25 and e25[5]), b2)
-- 0.9.4d's own reader takes a file with rates (it reads columns 1-8): loaded in a sandbox from the frozen release
local oldsrc = host_read(tests .. "/../build/release_0.9.4d/addon/lua/gsa1/feat/sh_wheel.lua")
if not oldsrc then
    info("build/release_0.9.4d/addon/lua/gsa1/feat/sh_wheel.lua is not here: 0.9.4d's reader is not checked")
else
    local mine = GSA1
    local W2
    local okOld, errOld = pcall(function()
        GSA1 = { CHARACTERS = mine.CHARACTERS }
        host_load(oldsrc, "sh_wheel_094d.lua")()
        W2 = GSA1.Wheel
    end)
    GSA1 = mine
    local wr = W.EmptyWheel()
    wr.pages[1][1] = { body = "a75", name = "s_kimepose0", face = "Happy", speed = 2 }
    wr.pages[1][2] = { body = "a3", name = "s_wait3", loop = true, speed = 0.5 }
    local newText = W.Serialize({ sonic = wr })
    local o, ob = nil, -1
    if okOld and W2 and W2.Parse then o, ob = W2.Parse(newText) end
    check(okOld and o and ob == 0 and o.sonic and o.sonic.pages[1][1].body == "a75" and o.sonic.pages[1][1].face == "Happy" and
        o.sonic.pages[1][2].loop == true and string.find(newText, "\t2\n", 1, true) ~= nil,
        "(25) 0.9.4d's reader (the frozen release's sh_wheel.lua) takes a file with rates: %s bad lines, the slots kept "
        .. "(it ignores the 9th column)%s", tostring(ob), okOld and "" or (": " .. tostring(errOld)))
end
M.files[W.FILE] = nil
W.data = nil
W.Load()

end
-- the key refusal ----------------------------------------------------------------------------------------------------------------
do
RunConsoleCommand("gsa1_wheel_key", "65")         -- SPACE: the jump key
local k1 = M.convars.gsa1_wheel_key.v
RunConsoleCommand("gsa1_wheel_key", "17")         -- G: the Super key (gsa1_super_key, when that feature is there)
M.cv("gsa1_super_key", "17")
RunConsoleCommand("gsa1_wheel_key", "67")
RunConsoleCommand("gsa1_wheel_key", "17")
local k2 = M.convars.gsa1_wheel_key.v
RunConsoleCommand("gsa1_wheel_key", "67")
RunConsoleCommand("gsa1_wheel_face_key", "67")
local k3 = M.convars.gsa1_wheel_face_key.v
RunConsoleCommand("gsa1_wheel_face_key", "107")
check(k1 == "67" and k2 == "67" and k3 == "107", "the wheel key refuses the jump key and the Super key (the old key stays: "
    .. "%s, %s); the face trigger may not be the wheel key (%s)", k1, k2, k3)
check(#R.bad == 0, "every module call had valid arguments%s", #R.bad > 0 and (": " .. table.concat(R.bad, ", ")) or "")

end
-- task 3 / review R.18: the defaults against the disc's catalogues (feat_emote_test.cpp's emote_lists.txt) ------------------------
do
local lists_text = host_read(tests .. "/../build/x86_64-windows/emote_lists.txt")
if not lists_text then
    info("build/x86_64-windows/emote_lists.txt is missing (feat_emote_test runs with the disc first): the defaults are not "
        .. "checked against the disc")
else
    local disc = {}
    for line in string.gmatch(lists_text, "[^\n]+") do
        if string.sub(line, 1, 1) ~= "#" then
            local f = {}
            for x in string.gmatch(line .. "\t", "([^\t]*)\t") do f[#f + 1] = x end
            local en = f[1]
            disc[en] = disc[en] or { n = 0 }
            local l = disc[en]
            l.n = l.n + 1
            l[l.n] = { key = f[5], name = f[6], dup = tonumber(f[7]) or 0, played = f[8] }
        end
    end
    local unresolved, notplayed, total = {}, {}, 0
    for _, c in ipairs(GSA1.CHARACTERS) do
        local l = disc[c.name]
        local d = W.DEFAULTS[c.name]
        for s = 1, 8 do
            local o = d and d[s]
            if o then
                total = total + 1
                local e = l and W.Resolve(l, o.body, o.name)
                if not e or e.name ~= o.name then
                    unresolved[#unresolved + 1] = c.name .. " " .. tostring(o.name)
                elseif e.played ~= "ok" then
                    notplayed[#notplayed + 1] = c.name .. " " .. o.name .. " (" .. tostring(e.played) .. ")"
                end
            end
        end
    end
    check(#unresolved == 0 and #notplayed == 0 and total == 64, "every default slot of the 8 wheels (%d) resolves by name to "
        .. "an offered entry of its (kind, form) list on the disc that played without a fault%s%s", total,
        #unresolved > 0 and (": unresolved " .. table.concat(unresolved, ", ")) or "",
        #notplayed > 0 and ("; did not play: " .. table.concat(notplayed, ", ")) or "")
    -- the greyed rows are exactly the table rows the disc's catalogue leaves out
    local wrong = {}
    for _, c in ipairs(GSA1.CHARACTERS) do
        local l = disc[c.name]
        local rows = {}
        for i = 1, l and l.n or 0 do
            local num = tonumber(string.match(l[i].key or "", "^a(%d+)$"))
            if num then rows[num] = true end
        end
        local grey = {}
        for _, u in ipairs(W.UNPLAYABLE[c.name] or {}) do
            grey[u[1]] = true
            if rows[u[1]] then wrong[#wrong + 1] = c.name .. " a" .. u[1] .. " is offered" end
        end
        for n = 0, (W.TABLE_ROWS[c.name] or 0) - 1 do
            if not rows[n] and not grey[n] then wrong[#wrong + 1] = c.name .. " a" .. n .. " is in neither" end
        end
    end
    check(#wrong == 0, "the generated greyed rows (cl_wheel_rows.lua) are exactly the action-table rows the disc's "
        .. "catalogue does not offer%s", #wrong > 0 and (": " .. table.concat(wrong, ", ", 1, math.min(#wrong, 8))) or "")
end

end
GSA1.LogFlush()
local errs = {}
for _, e in ipairs(M.reported) do errs[#errs + 1] = e end
check(#errs == 0 and not string.find(M.files["gsa1/log.txt"] or "", "Lua error in wheel", 1, true),
    "no Lua error in the wheel's hooks%s", #errs > 0 and (": " .. errs[1]) or "")
GSA1.InputBlocked = prevBlocked
return done()
