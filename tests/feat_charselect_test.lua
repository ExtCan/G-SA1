-- feat_charselect_test.lua - Character Select, the addon's side (round 0.9.8: sadc docs/research/gsa1_098_plan.md 6.10 with its
-- review R98.11, R98.13, R98.20, R98.22; charsel098.md 6, 7 "G-SA1" item 1; gsa1_090_charselect.md review RC2, RC8):
-- feat/sh_charselect.lua, feat/cl_charselect.lua and the hold in feat/cl_jukebox.lua, in Garry's Mod's own LuaJIT with
-- tests/lua_mock.lua. The stubs lua_mock.lua lacks live here (list, the panel, gui, input, the menus); lua_mock.lua is not changed.
--   lua_host tests/feat_charselect_test.lua <tests dir> <addon/lua dir>
-- API NOTES (098-gsa1-charsel): the full text is at the top of tests/feat_charselect_binding_test.cpp. Design S runs with the feature
-- absent; Design R runs on a small model of the module's feature here, checked against build/<target>/frontend_api.txt as soon as the
-- snapshot's libsa1.h defines SA1_API_FRONTEND (5.5, review R98.14). What only the game can show stays UNVERIFIED: 3D in a vgui Paint,
-- Escape, popup focus, the C menu's release.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_charselect_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files, the jukebox's and the HUD's (H.Material). 1.0.0: the feature's bar and its panel (cl_charselect_bar.lua, sh_upgrades / cl_upgrades), the skins' registry and pictures and the
-- text they are drawn with
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_charselect%.lua$") or string.find(n, "_jukebox%.lua$") or n == "cl_hud.lua" or n == "cl_charselect_bar.lua" or string.find(n, "_upgrades%.lua$") or
                string.find(n, "_skins%.lua$") or string.find(n, "_skinhud%.lua$") or string.find(n, "_text%.lua$") then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end

-- the stubs ----------------------------------------------------------------------------------------------------------------------
local lists = {}
list = {
    Set = function(name, k, v) lists[name] = lists[name] or {} lists[name][k] = v end,
    Get = function(name) return lists[name] or {} end,
    GetForEdit = function(name) lists[name] = lists[name] or {} return lists[name] end,
}
-- the keyboard and the mouse
local keys, binds, keybinds, codes = {}, {}, {}, {}
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    IsKeyDown = function(code) return keys[code] == true end,
    IsMouseDown = function(code) return keys[code] == true end,
    LookupBinding = function(b) return binds[b] end,
    LookupKeyBinding = function(code) return keybinds[code] end,
    GetKeyCode = function(name) return codes[name] end,
    GetKeyName = function(code) return "key" .. tostring(code) end,
}
-- the panels
local panels = {}
local PANEL = {}
PANEL.__index = PANEL
function PANEL:SetPos(x, y) self.x, self.y = x, y end
function PANEL:SetSize(w, h) self.w, self.h = w, h end
function PANEL:GetWide() return self.w or 0 end
function PANEL:GetTall() return self.h or 0 end
function PANEL:MakePopup() self.popup = true end
function PANEL:SetKeyboardInputEnabled(b) self.keyboard = b end
function PANEL:SetMouseInputEnabled(b) self.mouse = b end
function PANEL:CursorPos() return self.cx or 0, self.cy or 0 end
function PANEL:SetConVar(c) self.convar = c end
function PANEL:SetTall() end
function PANEL:SetImage(p) self.image = p end
function PANEL:GetChildren() return self.children or {} end
function PANEL:IsVisible() return not self.removed and self.visible ~= false end
function PANEL:Remove()
    if self.removed then return end
    self.removed = true
    if self.OnRemove then self:OnRemove() end
end
local function new_panel(cls)
    local p = setmetatable({ cls = cls }, PANEL)
    panels[#panels + 1] = p
    return p
end
local menu_cursor = false
vgui = {
    Create = function(cls) return new_panel(cls) end,
    CursorVisible = function()
        if menu_cursor then return true end
        for _, p in ipairs(panels) do if p.popup and not p.removed then return true end end
        return false
    end,
}
local hides = 0
gui.HideGameUI = function()
    hides = hides + 1
    M.ui = false
end
gui.IsConsoleVisible = function() return false end
local texts = {}
surface.CreateFont = function() end
surface.DrawTexturedRect = function() end
surface.SetDrawColor = function() end
draw.RoundedBox = function(r, x, y, w, h, c) texts.boxes = texts.boxes or {} texts.boxes[#texts.boxes + 1] = { x, y, w, h, c } end
draw.SimpleText = function(t) texts[#texts + 1] = t end

-- the addon, with the module's feature "jukebox" and no "frontend" -----------------------------------------------------------------
local G = M.module({ features = { jukebox = 1 } })
local calls = { play = {}, stop = {}, pause = {}, volume = {}, duck = {} }
local jb = { [0] = "idle", [1] = "idle" }
function G.MusicList() return nil, "loading" end
function G.JukeboxPlay(ch, music, start, plan, loops, fi, fo)
    calls.play[#calls.play + 1] = { ch = ch, music = music, start = start, plan = plan, loops = loops }
    jb[ch] = "playing"
    return true, "loading"
end
function G.JukeboxStop(ch, fade)
    calls.stop[#calls.stop + 1] = { ch = ch, fade = fade }
    jb[ch] = "idle"
    return true
end
function G.JukeboxPause(ch, paused)
    calls.pause[#calls.pause + 1] = { ch = ch, paused = paused }
    return true
end
function G.JukeboxSeek() return true end
function G.JukeboxVolume(ch, v)
    calls.volume[#calls.volume + 1] = { ch = ch, v = v }
    return true
end
local last_update = nil
function G.JukeboxUpdate(eye, fwd, up, gv, mv, paused)
    last_update = { mv = mv, paused = paused }
    return jb[1] == "playing" and 1 or 0
end
function G.JukeboxState(ch, out)
    out = out or {}
    out.music, out.state = -1, jb[ch] or "idle"
    return out
end
function G.JukeboxStatus() return { ready = true } end
function G.AudioOpen() return true, "ok" end
function G.AudioDuck(gain, jingles)
    calls.duck[#calls.duck + 1] = { gain = gain, jingles = jingles }
    return true
end
-- the controller
local pad = { connected = false, raw = 0, sx = 0, sy = 0 }
function G.PadPoll(dt, paused, out)
    out = out or {}
    out.connected, out.active, out.yaw, out.pitch, out.reset = pad.connected, false, 0, 0, false
    out.raw, out.sx, out.sy, out.buttons = pad.raw, pad.sx, pad.sy, 0
    return out
end
local real_create = G.Create
local created_ups = {}
function G.Create(kind, pos, yaw, ups, rings, extras)
    created_ups[#created_ups + 1] = ups
    return real_create(kind, pos, yaw, ups, rings)
end

GSA1 = nil
M.included = {}
-- what Garry's Mod kept from an older version: a saved "last". 0.9.9e: nothing reads it any more, nothing creates the ConVar
local cookies = {}
cookie = { GetNumber = function(k, d) return tonumber(cookies[k]) or d end, Set = function(k, v) cookies[k] = v end }
M.cv("gsa1_charselect_super", "last")
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local feat_errors = GSA1 and GSA1.FeatureFileErrors or {}
check(ok_load and #feat_errors == 0, "the addon's client files load with the feature's two files (%s)",
    tostring(err_load or feat_errors[1] or "no error"))
if not ok_load or #feat_errors > 0 then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
local S = GSA1.CharSelect

local function open_panel()
    return S.st and S.st.panel or nil
end
local function frames(n)
    for _ = 1, n or 1 do
        M.frame(1 / 60)
        local p = open_panel()
        if p and p.Think then p:Think() end
        p = open_panel()
        if p and p.Paint then p:Paint(p.w, p.h) end
    end
end
local function press(code)
    local p = open_panel()
    if p and p.OnKeyCodePressed then p:OnKeyCodePressed(code) end
end
local function count_log(word)
    local n = 0
    for line in string.gmatch(M.files["gsa1/log.txt"] or "", "[^\n]+") do
        if string.find(line, "charselect", 1, true) and string.find(line, word, 1, true) then n = n + 1 end
    end
    return n
end
local function reset_calls()
    calls.play, calls.stop, calls.pause, calls.volume, calls.duck = {}, {}, {}, {}, {}
end

-- 0.9.9e (the owner, 14.1bc): the slot always plays Super Sonic (Vs. Perfect Chaos); the option, its memory and its one-time move are gone -------------------
do
    check(S.cv.super == nil and S.cv.super_last == nil and S.MigrateSlot == nil and S.SuperEntry == nil and S.SUPER_CHOICES == nil, "no option, no memory, no move")
    check(cookies.gsa1_charselect_super_099 == nil, "no marker")
    check(S.SlotTitle(6) == "Super Sonic" and S.EntryName(6) == "supersonic", "the slot gives Super Sonic (Vs. Perfect Chaos), a saved \"last\" or not")
end

-- 1. the C menu's icon (R98.13: at file scope, behind the guard) -----------------------------------------------------------------
local entry = list.Get("DesktopWindows").GSA1CharSelect
check(type(entry) == "table" and entry.title == "Character Select" and entry.onewindow == true and type(entry.init) == "function"
    and entry.icon == S.ICON_PLAIN and entry.width == 640 and entry.height == 480,
    "the C menu's list has the entry GSA1CharSelect, a plain icon first (%s)", tostring(entry and entry.icon))
do
    g_ContextMenu = new_panel("ContextMenu")
    local closes = 0
    function g_ContextMenu:Close() closes = closes + 1 self.visible = false end
    local window = new_panel("DFrame")
    entry.init({}, window)
    check(S.IsOpen() and window.removed == true and closes == 1 and S.st.how == "cmenu",
        "the icon: its window goes, the C menu closes (review R.4), the panel opens (how = %s)", tostring(S.st and S.st.how))
    local p = open_panel()
    check(p and p.popup == true and p.w == ScrW() and p.h == ScrH() and p.keyboard == true and p.mouse == true,
        "a full-screen popup with the keyboard and the mouse")
    S.Close("test")
    g_ContextMenu = nil
    check(not S.IsOpen() and p.removed == true and GSA1.InputBlocked() == false, "closing removes the panel, the input is back")
end

-- 2. the menubar ---------------------------------------------------------------------------------------------------------------------
do
    local opts, spacers, name = {}, 0, nil
    local menu = { AddOption = function(self, text, fn) opts[#opts + 1] = { text, fn } return {} end,
                   AddSpacer = function() spacers = spacers + 1 end }
    local bar = { AddOrGetMenu = function(self, label) name = label return menu end }
    M.run_hook("PopulateMenuBar", bar)
    local titles = {}
    for _, o in ipairs(opts) do titles[o[1]] = o[2] end
    local all = titles["Character Select..."] ~= nil and titles["Remove character"] ~= nil
    for _, c in ipairs(GSA1.ListedCharacters()) do all = all and titles[c.title] ~= nil end
    check(name == "G-SA1" and all, "the menubar: G-SA1 > Character Select..., every character, Remove character")
    titles["Character Select..."]()
    check(S.IsOpen() and S.st.how == "menubar", "Character Select... opens the panel")
    S.Close("test")
end

-- 3. the command --------------------------------------------------------------------------------------------------------------------
M.cmds["gsa1_charselect"]()
check(S.IsOpen() and S.st.how == "the command", "gsa1_charselect opens it")
M.cmds["gsa1_charselect"]()
check(not S.IsOpen(), "gsa1_charselect closes it")

-- 4. the key, polled in Think; the panel closes itself on it (RC8: with the cursor up polling alone would not do) -------------------
frames(2)
check(not S.IsOpen(), "gsa1_charselect_key 0: no key opens it")
S.cv.key:SetString("30")
keys[30] = true
frames(1)
check(S.IsOpen() and S.st.how == "key", "gsa1_charselect_key 30: the press opens it")
keys[30] = false
frames(2)
check(S.IsOpen(), "it stays open when the key is released")
check(vgui.CursorVisible() == true, "the popup has the cursor")
keys[30] = true
press(30)
check(not S.IsOpen(), "a second press closes it while vgui.CursorVisible() is true (the panel's own OnKeyCodePressed)")
frames(3)
check(not S.IsOpen(), "the key still held does not open it again")
keys[30] = false
frames(1)
keys[30] = true
frames(1)
check(S.IsOpen(), "released and pressed again: open again")
keys[30] = false
frames(1)
press(30)
check(not S.IsOpen(), "closed")
-- the bound command: a popup eats the bind, the panel compares the key with it
M.T = M.T + 1
binds["gsa1_charselect"], codes["f7"] = "f7", 98
M.cmds["gsa1_charselect"]()
check(S.IsOpen(), "the command through a bind opens it")
press(98)
check(not S.IsOpen(), "the panel closes itself on the bound key")
M.cmds["gsa1_charselect"]()
check(not S.IsOpen(), "the bind coming through as well within a moment does not open it again")
M.T = M.T + 1
binds["gsa1_charselect"], codes["f7"] = nil, nil
-- not while busy
menu_cursor = true
keys[30] = true
frames(1)
check(not S.IsOpen(), "not while a menu has the cursor")
keys[30] = false
menu_cursor = false
frames(1)
M.ui = true
keys[30] = true
frames(1)
check(not S.IsOpen(), "not with the game menu up")
keys[30] = false
M.ui = false
frames(1)
M.player.IsTyping = function() return true end
keys[30] = true
frames(1)
check(not S.IsOpen(), "not while typing")
keys[30] = false
M.player.IsTyping = nil
frames(1)
S.cv.key:SetString("0")

-- 5. Start on the controller -------------------------------------------------------------------------------------------------------
pad.connected = true
-- (two frames: the hooks of a frame run in no set order, so GSA1.pad may be this frame's only from the next one on)
local function start_edge()
    pad.raw = S.PAD_START
    frames(2)
    return S.IsOpen()
end
local function release()
    pad.raw = 0
    frames(2)
end
check(start_edge() and S.st.how == "start", "Start's edge opens it")
-- 6. the press that opened it does not pick until it was released; then Start picks (the game's Start)
frames(5)
check(S.IsOpen() and GSA1.Char == nil, "the Start that opened it, still held, does not pick")
release()
check(S.IsOpen(), "released: still open")
S.Close("test")
frames(1)
GSA1.cv.pad_start:SetString("1")
check(not start_edge(), "not with gsa1_pad_start 1")
release()
GSA1.cv.pad_start:SetString("0")
M.focus = false
check(not start_edge(), "not while Garry's Mod has no focus")
release()
M.focus = true
S.cv.pad:SetString("0")
check(not start_edge(), "not with gsa1_charselect_pad 0")
release()
S.cv.pad:SetString("1")
pad.raw = 0
pad.connected = false

-- 7. Escape ---------------------------------------------------------------------------------------------------------------------------
S.Open("test")
M.ui = true
frames(1)
check(not S.IsOpen() and hides == 1 and M.ui == false, "Escape: the game menu is hidden again and the panel closes (hides %d)", hides)
S.Open("test")
check(M.run_hook("OnPauseMenuShow") == false and not S.IsOpen(), "Escape where the engine asks first: no game menu, the panel closes")
check(M.run_hook("OnPauseMenuShow") == nil, "with the panel closed the pause menu is left alone")
S.Open("test")
press(KEY_ESCAPE or 70)
check(not S.IsOpen(), "the Escape key itself closes it")
M.ui = true
M.cmds["gsa1_charselect"]()
frames(1)
check(S.IsOpen(), "opened from the console under the game menu: it stays")
M.ui = false
frames(1)
S.Close("test")

-- 8. picks: the entry through GSA1.Spawn, with the ticked upgrades --------------------------------------------------------------------
local function run_of(ev) return M.hook_runs[ev] or 0 end
frames(1)
GSA1.cv["up_shovel_claw"]:SetString("1")
S.Open("test")
check(S.st.slot == 0, "no character: Sonic's slot first (gsa1_character)")
press(KEY_D or 14)
press(KEY_RIGHT or 91)
check(S.st.slot == 2, "D and Right move the selection (slot %d)", S.st.slot)
press(KEY_LEFT or 89)
press(KEY_RIGHT or 91)
local nc = #M.creates
press(KEY_ENTER or 64)
check(not S.IsOpen() and GSA1.Char and GSA1.Char.kind == 3 and #M.creates == nc + 1 and GSA1.cv.character:GetString() == "knuckles",
    "Enter on slot 2: gsa1.Create kind 3, gsa1_character = knuckles, the panel closed")
local ups = created_ups[#created_ups]
local has_up = false
for _, u in ipairs(ups or {}) do if u == "shovel_claw" then has_up = true end end
check(has_up, "with the ticked upgrades (%s)", table.concat(ups or {}, " "))
GSA1.cv["up_shovel_claw"]:SetString("0")
-- the current character is the first selection
S.Open("test")
check(S.st.slot == 2, "the current character is the first selection")
-- a pick is any switch: the life events (followers, board, HUD) hear of it
local leaving0, created0 = run_of("GSA1CharacterLeaving"), run_of("GSA1CharacterCreated")
local old = GSA1.Char
S.st.slot = 0
press(KEY_SPACE or 65)
check(run_of("GSA1CharacterLeaving") == leaving0 + 1 and run_of("GSA1CharacterCreated") == created0 + 1 and GSA1.Char ~= old and
    GSA1.Char.kind == 0, "Space: a switch, GSA1CharacterLeaving and GSA1CharacterCreated fire as for any switch (recheck 4.5 item 4)")
-- a click on a button
S.Open("test")
do
    local p = open_panel()
    local x, y, w, h = S.ButtonRect(5, p.w, p.h)
    p.cx, p.cy = x + w / 2, y + h / 2
    p:OnMousePressed(MOUSE_LEFT or 107)
    check(not S.IsOpen() and GSA1.Char.kind == 6, "a click on E-102's button picks E-102 (kind %d)", GSA1.Char.kind)
end
-- the "?" slot: whatever is saved, Super Sonic (Vs. Perfect Chaos)
local function pick_super(saved, want)
    GetConVar("gsa1_charselect_super"):SetString(saved)
    S.Open("test")
    S.st.slot = 6
    press(KEY_SPACE or 65)
    check(not S.IsOpen() and GSA1.Char.name == want and not GSA1.Char.question, "slot 6 with a saved gsa1_charselect_super %s plays %s (%s)", saved, want, tostring(GSA1.Char.name))
end
pick_super("last", "supersonic")
pick_super("supersonic_general", "supersonic")
pick_super("question", "supersonic")
S.Open("test")
check(S.st.slot == 6, "Super Sonic: the first selection is slot 6")
S.Close("test")
-- Dr. Eggman and Tikal are not on the ring; the General form's slot and the "?"'s slot stay 6 for the first selection
do
    check(S.ENTRY_SLOT.question == 6 and S.SlotOf("question") == 6 and S.ENTRY_SLOT.supersonic_general == 6 and S.EntryOf(6) == "supersonic", "the slot of the other two is 6, and it plays Super Sonic (Vs. Perfect Chaos)")
    check(S.SlotTitle(6) == "Super Sonic", "the slot's title")
    GSA1.Spawn("tikal")
    check(GSA1.Char and GSA1.Char.kind == 4, "Tikal comes up")
    S.Open("test")
    check(S.st.slot == 0, "Dr. Eggman and Tikal are not on the game's ring: as Tikal the screen starts on Sonic (slot %s)", tostring(S.st.slot))
    S.Close("test")
end
GSA1.Spawn("sonic")
-- back and the mouse
S.Open("test")
press(KEY_BACKSPACE or 66)
check(not S.IsOpen() and GSA1.Char.kind == 0, "Backspace goes back: no switch")
S.Open("test")
open_panel():OnMousePressed(MOUSE_RIGHT or 108)
check(not S.IsOpen() and GSA1.Char.kind == 0, "a right click goes back: no switch")
S.Open("test")
open_panel():OnMouseWheeled(-1)
check(S.st.slot == 1, "the wheel moves")
open_panel():OnMouseWheeled(1)
check(S.st.slot == 0, "the wheel moves back")
S.Close("test")
-- the controller
pad.connected = true
start_edge()
check(S.IsOpen(), "Start opens it")
release()
pad.raw = S.PAD_RIGHT
frames(1)
check(S.st.slot == 1, "the D-pad moves")
pad.raw = 0
pad.sx = 0.9
frames(3)
check(S.st.slot == 2, "the stick moves once per push")
pad.sx = 0
frames(1)
pad.raw = S.PAD_A
frames(1)
check(not S.IsOpen() and GSA1.Char.kind == 3, "A picks")
release()
start_edge()
check(S.IsOpen(), "Start opens it again")
release()
S.st.slot = 1
pad.raw = S.PAD_START
frames(4)
check(not S.IsOpen() and GSA1.Char.kind == 2, "released and pressed again, Start picks; held on, it does not open again (kind %d)", GSA1.Char.kind)
release()
start_edge()
release()
pad.raw = S.PAD_B
frames(1)
check(not S.IsOpen() and GSA1.Char.kind == 2, "B goes back")
release()
start_edge()
release()
pad.raw = S.PAD_BACK
frames(1)
check(not S.IsOpen(), "Back goes back")
release()
pad.connected = false
frames(1)

-- 9. nothing pauses; a neutral pad; a board rides on (A12, R98.22) ------------------------------------------------------------------------
GSA1.Spawn("sonic")
do
    M.keys, M.forward = IN_JUMP, 10000
    frames(2)
    check(M.ticks.last.buttons ~= 0 and M.ticks.last.sy ~= 0, "before: the character gets the input")
    local C = GSA1.Char
    local pushes = 0
    G.BoardPush = function() pushes = pushes + 1 return true end
    C.board = { on = true }
    S.Open("test")
    local t0 = #M.creates
    local dt0 = M.ticks.last
    frames(5)
    local l = M.ticks.last
    check(l ~= dt0 and l.buttons == 0 and l.sx == 0 and l.sy == 0, "while it is open the tick goes on with a neutral pad (buttons %d)", l.buttons)
    check(GSA1.Char == C and C.board.on == true and pushes == 0 and #M.creates == t0, "the board rides on: nothing else is touched")
    S.Close("test")
    frames(2)
    check(M.ticks.last.buttons ~= 0, "closed: the input is back")
    M.keys, M.forward = 0, 0
    C.board = nil
    G.BoardPush = nil
end
check(GSA1.InputBlocked() == false, "closed: GSA1.InputBlocked is false")
-- a panel removed from outside
S.Open("test")
do
    local p = open_panel()
    p:Remove()
    check(not S.IsOpen() and GSA1.InputBlocked() == false, "a panel removed from outside: the same way out")
end

-- 10. music (RC2): one source, the jukebox pauses and resumes -----------------------------------------------------------------------------
local P = GSA1.JukeboxPlayer
local function one_source(bgm)
    reset_calls()
    GSA1.cv.snd_bgm:SetString(bgm)
    S.Open("test")
    frames(3)
    local n1 = 0
    for _, c in ipairs(calls.play) do if c.music == 24 then n1 = n1 + 1 end end
    local ch1 = calls.play[1]
    check(n1 == 1 and ch1.ch == 1 and ch1.plan == "forever" and ch1.start == 0,
        "gsa1_sound_bgm %s: track 24 once, on channel 1, looped (%d)", bgm, n1)
    check(#calls.duck >= 1 and calls.duck[1].gain == 0 and calls.duck[1].jingles == false, "the game's music is silenced: AudioDuck(0, false)")
    check(last_update and last_update.paused == false and last_update.mv > 0, "the engine does not hold channel 1 (no global pause, volume %.2f)", last_update.mv)
    S.Close("test")
    frames(2)
    check(#calls.stop == 1 and calls.stop[1].ch == 1 and calls.stop[1].fade > 0 and calls.stop[1].fade < 1, "closed: channel 1 ends with a short fade")
    local back = calls.duck[#calls.duck]
    check(back and back.gain == 1, "the game's music is back: AudioDuck(1, ...)")
end
one_source("0")
one_source("1")
GSA1.cv.snd_bgm:SetString("0")
-- the personal jukebox goes on where it was
do
    reset_calls()
    P.current, P.track, P.plan, P.startedAt, P.startPos, P.paused, P.used = 7, { music = 7, file = "x", seconds = 100 }, "forever", M.T, 12, false, true
    jb[0] = "playing"
    S.Open("test")
    frames(3)
    local paused = false
    for _, c in ipairs(calls.pause) do if c.ch == 0 and c.paused then paused = true end end
    check(paused and P.holdWhy == "charselect", "your jukebox pauses where it is, holdWhy \"charselect\" (%s)", tostring(P.holdWhy))
    local pos = P.Position()
    S.Close("test")
    frames(1)
    local resumed = false
    for _, c in ipairs(calls.pause) do if c.ch == 0 and c.paused == false then resumed = true end end
    check(resumed and not P.paused and P.current == 7 and math.abs(P.Position() - pos) < 0.2 and P.holdWhy ~= "charselect",
        "closed: it resumes at its position (%.2f)", P.Position())
    -- a jukebox the owner paused stays paused
    P.paused = true
    reset_calls()
    S.Open("test")
    S.Close("test")
    check(#calls.pause == 0 and P.paused == true, "a jukebox you paused stays paused")
    P.paused, P.current, P.track = false, nil, nil
    jb[0] = "idle"
    frames(1)
end
-- no music
do
    reset_calls()
    S.cv.music:SetString("0")
    P.current, P.track, P.plan, P.startedAt, P.startPos, P.paused, P.used = 7, { music = 7, file = "x", seconds = 100 }, "forever", M.T, 12, false, true
    S.Open("test")
    frames(2)
    check(#calls.play == 0 and #calls.pause == 0, "gsa1_charselect_music 0: no music, the jukebox goes on")
    S.Close("test")
    S.cv.music:SetString("1")
    P.current, P.track = nil, nil
    frames(1)
end
-- without the jukebox feature: silent, the screen works
do
    reset_calls()
    G.FEATURES.jukebox = nil
    S.Open("test")
    frames(2)
    check(S.IsOpen() and #calls.play == 0, "no jukebox in the module: silent, the panel works")
    S.Close("test")
    G.FEATURES.jukebox = 1
    frames(1)
end

-- 11. the panel's picture: seven buttons in the sphere colours -----------------------------------------------------------------------------
do
    S.Open("test")
    S.st.slot = 3
    texts.boxes = {}
    local p = open_panel()
    for i = #texts, 1, -1 do texts[i] = nil end
    p:Paint(p.w, p.h)
    local reds, blues = 0, 0
    for _, b in ipairs(texts.boxes) do
        if b[5].r == 255 and b[5].b == 0 then reds = reds + 1 end
        if b[5].b == 255 and b[5].r == 0 then blues = blues + 1 end
    end
    local all = table.concat(texts, "|")
    check(#texts.boxes == 7 and reds == 1 and blues == 6 and string.find(all, "Knuckles", 1, true) and string.find(all, "E-102", 1, true)
        and string.find(all, "Super Sonic", 1, true), "seven buttons: FF0000FF, the selected one FFFF0000, with their names")
    local x0 = S.ButtonRect(0, p.w, p.h)
    local x6, y6, w6 = S.ButtonRect(6, p.w, p.h)
    check(x0 >= 0 and x6 + w6 <= p.w and x0 < x6 and S.ButtonAt(x6 + 1, y6 + 1, p.w, p.h) == 6 and S.ButtonAt(0, 0, p.w, p.h) == nil,
        "they fit the screen, and S.ButtonAt finds them")
    S.Close("test")
end

-- 12. the pure parts --------------------------------------------------------------------------------------------------------------------------
do
    local m = S.Layout(3440, 1440, false)
    check(m.s == 3 and m.ox == 760 and m.oy == 0, "3440 x 1440: s = 3, the box at x 760 (s %s, x %s)", tostring(m.s), tostring(m.ox))
    check(S.PlaceX(m, 0) == 0 and S.PlaceX(m, -4) == 0 and S.PlaceX(m, 640) == 3440 and S.PlaceX(m, 700) == 3440 and S.PlaceX(m, 320) == 1720,
        "a vertex at x <= 0 or >= 640 goes to the screen's edge (the title bar reaches 0)")
    local w = S.Layout(3440, 1440, true)
    check(w.sx == 3440 / 640 and w.sy == 3 and w.ox == 0 and S.PlaceX(w, 320) == 1720, "gsa1_charselect_wide 1 stretches")
    local a, b = S.ShortestRun(0, 2, 7)
    local c, d = S.ShortestRun(0, 6, 7)
    local e, f = S.ShortestRun(3, 3, 7)
    local g, h = S.ShortestRun(1, 5, 6)
    check(a == 1 and b == 2 and c == -1 and d == 1 and e == 0 and f == 0 and g == -1 and h == 2, "a click on a sphere: the shortest run of presses")
    check(S.SphereSlot(2, 0, 7) == 2 and S.SphereSlot(2, 6, 7) == 1, "the k-th sphere draw is slot (slot + k) mod n")
    check(S.HiddenTexture("cs_sinkou_e") and S.HiddenTexture("FS_FILE_e") and S.HiddenTexture("fs_file_num3") and S.HiddenTexture("sinkou_0")
        and not S.HiddenTexture("sphe_7") and not S.HiddenTexture(nil), "the draws of File and Clear are found by the texture's name")
    check(S.EntryOf(2) == "knuckles" and S.EntryOf(5) == "gamma" and S.EntryOf(9) == nil, "slots -> entries")
end

-- 13. the Character page: the combo and buttons stay, every row has a control -------------------------------------------------------------------
do
    local P2 = { calls = {}, made = {} }
    local function ctl(kind)
        local o = { kind = kind, choices = {} }
        function o:AddChoice(text, data) self.choices[#self.choices + 1] = { text, data } end
        function o:SetText() end
        function o:SetConVar(c) self.convar = c end
        function o:SetTall() end
        function o:SetValue() end
        function o:SetFont() end
        function o:SetWrap() end
        function o:SetAutoStretchVertical() end
        function o:InvalidateLayout() end
        P2.made[#P2.made + 1] = o
        return o
    end
    local panel = setmetatable({}, { __index = function(t, k)
        return function(self, ...)
            P2.calls[#P2.calls + 1] = { k, ... }
            if k == "ComboBox" or k == "Help" or k == "ControlHelp" or k == "CheckBox" or k == "NumSlider" or k == "Button" or k == "TextEntry" then
                return ctl(k)
            end
        end
    end })
    local entry_opt
    for _, e in ipairs(GSA1.CharacterOptions) do if e.id == "charselect" then entry_opt = e end end
    check(entry_opt and entry_opt.order == 180 and entry_opt.needs == nil, "the rows come through GSA1.AddCharacterOption, order 180, for every module")
    M.run_hook("PopulateToolMenu")
    local charpage
    for _, m in ipairs(M.menu) do if m.name == "Character" then charpage = m end end
    local ok, err = pcall(charpage.cpanel, panel)
    check(ok, "the Character page builds (%s)", tostring(err or "ok"))
    local bound, buttons, combos = {}, {}, {}
    for _, c in ipairs(P2.calls) do
        if c[1] == "CheckBox" and type(c[3]) == "string" then bound[c[3]] = c[2] end
        if c[1] == "AddItem" and type(c[2]) == "table" and c[2].convar then bound[c[2].convar] = "binder" end
        if c[1] == "Button" then buttons[#buttons + 1] = tostring(c[2]) .. "|" .. tostring(c[3]) end
        if c[1] == "ComboBox" then combos[#combos + 1] = tostring(c[2]) end
    end
    local function find_button(cmd)
        for _, b in ipairs(buttons) do if string.find(b, cmd, 1, true) then return true end end
    end
    check(string.find(table.concat(combos, "|"), "Character", 1, true) ~= nil and find_button("gsa1_spawn") and find_button("gsa1_remove") and find_button("gsa1_respawn"),
        "the Character page keeps its combo and buttons")
    check(find_button("Open Character Select|gsa1_charselect"), "the button \"Open Character Select\"")
    for _, o in ipairs(P2.made) do
        if o.kind == "ComboBox" and o.OnSelect then
            for _, ch in ipairs(o.choices) do
                local before = {}
                for n, cvo in pairs(M.convars) do before[n] = cvo.v end
                pcall(o.OnSelect, o, 1, ch[1], ch[2])
                for n, cvo in pairs(M.convars) do
                    if cvo.v ~= before[n] then
                        bound[n] = "combo"
                        cvo.v = before[n]
                    end
                end
            end
        end
    end
    local want = { "gsa1_charselect_key", "gsa1_charselect_pad", "gsa1_charselect_dialog", "gsa1_charselect_close", "gsa1_charselect_music",
                   "gsa1_charselect_file", "gsa1_charselect_wide", "gsa1_charselect_qmark" }
    local missing = {}
    for _, n in ipairs(want) do if not bound[n] then missing[#missing + 1] = n end end
    check(#missing == 0, "every row of 5.9 has its control (%s)", table.concat(missing, " "))
    -- every gsa1_charselect_* ConVar but the memory is a row of 5.9, with the default 5.9 gives it
    local defaults = { gsa1_charselect_key = "0", gsa1_charselect_pad = "1", gsa1_charselect_dialog = "0", gsa1_charselect_close = "0",
                       gsa1_charselect_music = "1", gsa1_charselect_file = "0", gsa1_charselect_wide = "0",
                       gsa1_charselect_qmark = "1", gsa1_charselect_skins = "1",
                       -- 1.0.0 (sadc docs/research/gsa1_100_select.md 6): the bar, the Upgrades panel, the skins' own names
                       gsa1_charselect_bar = "1", gsa1_charselect_upgrades = "1", gsa1_charselect_skin_names = "1" }
    local extra, wrong = {}, {}
    for n, d in pairs(GSA1.CONVARS) do
        if string.find(n, "^gsa1_charselect") then
            if not defaults[n] then extra[#extra + 1] = n end
            if d.default ~= defaults[n] then wrong[#wrong + 1] = n end
        end
    end
    check(#extra == 0 and #wrong == 0, "no other option, each with the default of 5.9 (%s %s)", table.concat(extra, " "), table.concat(wrong, " "))
    check(GSA1.CONVARS.gsa1_charselect_super == nil and GSA1.CONVARS.gsa1_charselect_super_last == nil and not bound.gsa1_charselect_super, "0.9.9e: the slot's option and its memory are gone, and its combo box")
end

-- 14. the icon from the disc, at run time ---------------------------------------------------------------------------------------------------------
do
    check(M.hooks.PostRender == nil or M.hooks.PostRender.gsa1_charselect_icon == nil, "no picture is made before the C menu is first opened")
    local widget_image = new_panel("DImage")
    local widget = new_panel("DButton")
    widget.WidgetClass, widget.children = "GSA1CharSelect", { widget_image }
    local bar = new_panel("DIconLayout")
    bar.children = { new_panel("DButton"), widget }
    g_ContextMenu = new_panel("ContextMenu")
    g_ContextMenu.DesktopWidgets = bar
    function g_ContextMenu:Close() self.visible = false end
    render.Capture = function(t)
        return t.format == "png" and t.w == 64 and t.h == 64 and t.alpha == true and "PNGDATA" or nil
    end
    M.run_hook("ContextMenuOpened")
    check(M.hooks.PostRender.gsa1_charselect_icon ~= nil, "the C menu's first opening asks for the picture")
    local n = 0
    while M.hooks.PostRender.gsa1_charselect_icon and n < 3000 do
        M.frame(1 / 60)
        n = n + 1
    end
    check(M.files["gsa1/charselect64.png"] == "PNGDATA" and widget_image.image == S.ICON_PATH and list.Get("DesktopWindows").GSA1CharSelect.icon == S.ICON_PATH,
        "Sonic's 1-up, written to data/gsa1/charselect64.png at run time, set in place on the open menu and for its next making (%d frames)", n)
    check(S.ICON_PATH == "../data/gsa1/charselect64.png", "the path a material reads")
    g_ContextMenu = nil
    render.Capture = nil
end

-- 15. the frame cost with the panel closed (A22: at most 16 B; frame_test.lua, its figure) ----------------------------------------------------------
do
    local think = M.hooks.Think.gsa1_charselect
    pad.connected = true
    for _ = 1, 2000 do think() end
    collectgarbage("collect")
    collectgarbage("stop")
    local k0 = collectgarbage("count")
    for _ = 1, 2000 do think() end
    local kb = collectgarbage("count") - k0
    collectgarbage("restart")
    pad.connected = false
    check(kb * 1024 / 2000 < 16, "the Think hook with the panel closed: %.2f B a frame (A22: under 16 B)", kb * 1024 / 2000)
end

-- 17. Design R on a mock of the module's feature "frontend" (the plan's 5.5, charsel098 6.6) --------------------------------------------------------
-- A small model of the game's screen: LEFT / RIGHT slide for 20 frames, A or START picks (the voice next frame, 300 frames of pose, done), B leaves
-- after 9 frames; its draws: the sky, the title bar, seven spheres, the bottom bar's text, a draw in front; two 3D batches.
local FE = { open = false, opens = {}, closes = 0, ticks = 0, inputs = {}, events = {} }
local FE_NAMES = { [0] = { [0] = "AVA_BACK00" }, [1] = { [0] = "sphe_7", [1] = "title", [2] = "sinkou_0", [3] = "dlg" } }
G.FEATURES.frontend = 1
G.FRONTEND = { KIND = 32, PRI_3D = -20, LEFT = 1, RIGHT = 2, UP = 4, DOWN = 8, A = 16, B = 32, START = 64, SLOTS = 7 }
local F = G.FRONTEND
local tex_asked = { frontend = 0, wrong = 0 }
local real_texture = G.Texture
function G.Texture(kind, index, archive, variant)
    if kind == F.KIND then tex_asked.wrong = tex_asked.wrong + 1 end
    return real_texture(kind, index, archive, variant)
end
function G.FrontendTextureArchives()
    return { { name = "AVA_BACK", count = 1 }, { name = "ADV_WINDOW", count = 4 } }
end
function G.FrontendTextureCount(a) return a == 1 and 4 or 1 end
function G.FrontendTexture(index, archive)
    tex_asked.frontend = tex_asked.frontend + 1
    local n = FE_NAMES[archive or 0] and FE_NAMES[archive or 0][index]
    if not n then return nil, "no such texture" end
    return { w = 8, h = 8, fmt = 0, dfmt = 0, alpha = 0, name = n, runs = string.rep("\0\0\0\0\8\0\255\255\255\255", 8), nruns = 8, canary = false }
end
function G.FrontendTexturePixel() return 255, 255, 255, 255 end
function G.FrontendStats(out) return out or {} end
local function fe_emit(kind, id)
    FE.events[#FE.events + 1] = { kind = kind, id = id }
end
function G.FrontendOpen(a)
    if FE.refuse then return nil, FE.refuse, "not_ready" end
    if FE.open then return nil, "a front end is open already", "open" end
    FE.open = true
    FE.opens[#FE.opens + 1] = a
    FE.slot, FE.slots, FE.frame, FE.phase, FE.pose, FE.acc, FE.prev = a.slot or 0, 7, 0, 0, 0, 0, 0
    FE.inputs, FE.events = {}, {}
    fe_emit("music", 24)
    return true
end
function G.FrontendClose()
    if FE.open then FE.closes = FE.closes + 1 end
    FE.open = false
    return true
end
function G.FrontendTick(dt, sx, sy, buttons)
    FE.ticks = FE.ticks + 1
    if not FE.open then return nil, "no front end is open", "not_ready" end
    if FE.gone then return nil, "no front end is open", "not_ready" end
    if FE.fault then return nil, "the game faulted at 8C900000", "fault" end
    FE.lastStick = { sx, sy }
    FE.acc = FE.acc + dt
    local n = 0
    while FE.acc >= 1 / 60 - 1e-9 and n < 8 do
        FE.acc = FE.acc - 1 / 60
        n = n + 1
        FE.frame = FE.frame + 1
        local down = n == 1 and buttons or FE.prev
        local edge = bit.band(down, bit.bnot(FE.prev))
        FE.inputs[#FE.inputs + 1] = { frame = FE.frame, buttons = down, edge = edge }
        FE.prev = down
        if FE.phase == 0 then
            if bit.band(edge, F.LEFT + F.RIGHT) ~= 0 then
                FE.phase, FE.slideEnd, FE.dir = 1, FE.frame + 20, bit.band(edge, F.RIGHT) ~= 0 and 1 or -1
            elseif bit.band(edge, F.A + F.START) ~= 0 then
                FE.phase, FE.pose = 3, 0
                fe_emit("pick", FE.slot)
            elseif bit.band(edge, F.B) ~= 0 then
                FE.phase, FE.leave = 4, FE.frame + 9
                fe_emit("music", -1)
            end
        elseif FE.phase == 1 then
            if FE.frame >= FE.slideEnd then
                FE.slot = (FE.slot + FE.dir) % FE.slots
                FE.phase = 0
                fe_emit("select", FE.slot)
            end
        elseif FE.phase == 3 then
            FE.pose = FE.pose + 1
            if FE.pose == 300 then
                fe_emit("music", -1)
                fe_emit("done", FE.slot)
            end
        elseif FE.phase == 4 then
            if FE.frame >= FE.leave then fe_emit("cancel", -1) end
        end
    end
    return n
end
function G.FrontendState(out)
    if not FE.open then return nil, "no front end is open", "not_ready" end
    out = out or {}
    out.slot, out.slots, out.phase, out.frame, out.pose_frames, out.kind, out.faults = FE.slot, FE.slots, FE.phase, FE.frame, FE.pose, 0, 0
    return out
end
function G.FrontendEvents(out)
    if not FE.open then return nil, "no front end is open", "not_ready" end
    out = out or {}
    local n = #FE.events
    for i = 1, n do
        out[i] = out[i] or {}
        out[i].kind, out[i].id = FE.events[i].kind, FE.events[i].id
    end
    FE.events = {}
    out.count = n
    return n, out
end
local function fe_quad(D, V, d, archive, tex, flags, pri, x0, y0, x1, y1)
    local nv = #V / 8
    local k = d * 11
    D[k + 1], D[k + 2], D[k + 3], D[k + 4], D[k + 5], D[k + 6], D[k + 7], D[k + 8], D[k + 9], D[k + 10], D[k + 11] = 0, nv, 6, archive, tex, flags, 1, 0, pri, 0, 0
    local pts = { { x0, y0, 0, 0 }, { x1, y0, 1, 0 }, { x1, y1, 1, 1 }, { x0, y0, 0, 0 }, { x1, y1, 1, 1 }, { x0, y1, 0, 1 } }
    for _, p in ipairs(pts) do
        local o = #V
        V[o + 1], V[o + 2], V[o + 3], V[o + 4], V[o + 5], V[o + 6], V[o + 7], V[o + 8] = p[1], p[2], p[3], p[4], 255, 255, 255, 255
    end
end
function G.FrontendScreen(out, force)
    if FE.screenFail then return nil, "no screen", "fault" end
    if not FE.open then return nil, "no front end is open", "not_ready" end
    if out.gen == FE.frame and not force then return FE.frame, false end
    local D, V = {}, {}
    out.d, out.v, out.s = D, V, {}
    out.gen, out.w, out.h, out.ns = FE.frame, 640, 480, 0
    local d = 0
    fe_quad(D, V, d, 0, 0, 0, -100, 0, 0, 640, 480)
    d = d + 1
    fe_quad(D, V, d, 1, 1, 1, -60, 0, 0, 640, 40)
    d = d + 1
    -- (libsa1 merges neighbours of one state: one draw of the ring's seven quads, plus two more of the bottom bar's)
    local ring0 = #V / 8
    for k = 0, 8 do
        fe_quad(D, V, d, 1, 0, 1, -40, 100 + 60 * k, 420, 132 + 60 * k, 452)
    end
    D[d * 11 + 2], D[d * 11 + 3] = ring0, 9 * 6
    d = d + 1
    fe_quad(D, V, d, 1, 2, 1, -40, 500, 460, 560, 476)
    d = d + 1
    fe_quad(D, V, d, 1, 3, 1, -5, 200, 200, 300, 300)
    d = d + 1
    out.nd, out.nv = d, #V / 8
    return FE.frame, true
end
function G.FrontendRender()
    if not FE.open then return nil, "no front end is open", "not_ready" end
    return 2, FE.frame, FE.slot == 6 and F.KIND or 0
end
local FE_BATCHES = { { key = "fe.o", archive = 0, tex = 0, flags = 0, wrap = 3, src = 1, dst = 0, pass = 0, tris = 10, all = 0, mat = 0, order = 1, source = 0, prims = 1 },
                     { key = "fe.t", archive = 0, tex = 1, flags = 1, wrap = 3, src = 4, dst = 5, pass = 1, tris = 5, all = 1, mat = 0, order = 2, source = 0, prims = 1 } }
function G.FrontendBatches(out)
    if not FE.open then return nil end
    out = out or {}
    for i, b in ipairs(FE_BATCHES) do out[i] = b end
    out.gen, out.count, out.triangles = FE.frame, #FE_BATCHES, 15
    return #FE_BATCHES, out
end
local trace = {}
function G.FrontendPrepareView(eye, right, up, flip, vc, lp, lit)
    trace[#trace + 1] = "prepare"
    FE.preparedLit, FE.preparedEye = lit, eye
    return true
end
function G.FrontendEmitBatch(b)
    trace[#trace + 1] = "emit" .. b
    return FE_BATCHES[b].tris * 3
end
function G.FrontendView() return Vector(0, 0, 0), Angle(0, -90, 0), 70 end

-- what the paint does, in order
render.ClearDepth = function() trace[#trace + 1] = "cleardepth" end
cam.Start3D = function(eye, ang, fov, x, y, w, h, near, far)
    trace[#trace + 1] = "start3d"
    FE.cam = { eye = eye, ang = ang, fov = fov, x = x, y = y, w = w, h = h, near = near, far = far }
end
cam.End3D = function() trace[#trace + 1] = "end3d" end
local draws2d = {}
local real_pos, real_begin, real_end = mesh.Position, mesh.Begin, mesh.End
local cur = nil
mesh.Begin = function(...)
    cur = { xs = {}, ys = {} }
    return real_begin(...)
end
mesh.Position = function(v)
    if cur then
        cur.xs[#cur.xs + 1] = v.x
        cur.ys[#cur.ys + 1] = v.y
    end
    return real_pos(v)
end
mesh.End = function(...)
    if cur and #cur.xs > 0 then
        draws2d[#draws2d + 1] = cur
        trace[#trace + 1] = "2d"
    end
    cur = nil
    return real_end(...)
end
local function fe_frames(n)
    frames(n)
end
local function fe_paint()
    local p = open_panel()
    for i = #trace, 1, -1 do trace[i] = nil end
    for i = #draws2d, 1, -1 do draws2d[i] = nil end
    p:Paint(p.w, p.h)
end
local function fe_presses(mask)
    local out = {}
    for _, i in ipairs(FE.inputs) do
        if bit.band(i.edge, mask) ~= 0 then out[#out + 1] = i.frame end
    end
    return out
end

GSA1.Spawn("sonic")
frames(2)
reset_calls()
-- opening
GSA1.cv.snd_japanese:SetString("1")
S.cv.dialog:SetString("1")
S.Open("test")
check(S.st.design == "R" and #FE.opens == 1 and FE.opens[1].slot == 0 and FE.opens[1].language == 0 and FE.opens[1].dialog == true,
    "the feature is there: FrontendOpen {slot = the current character's, language 0 for Japanese voices, dialog as the option}")
S.Close("test")
check(FE.closes == 1 and not FE.open, "every close ends in FrontendClose")
GSA1.cv.snd_japanese:SetString("0")
S.cv.dialog:SetString("0")
GSA1.Spawn("knuckles")
S.Open("test")
check(FE.opens[2].slot == 2 and FE.opens[2].language == 1 and FE.opens[2].dialog == false, "Knuckles: slot 2, English, no dialog")
-- the first open paints the menu's textures at once, through the Frontend texture functions
do
    local T = GSA1.Tex
    frames(1)
    local all_done = true
    for _, spec in ipairs({ { 0, 0 }, { 1, 0 }, { 1, 1 }, { 1, 2 }, { 1, 3 } }) do
        local e = T.entries[F.KIND .. "_" .. spec[1] .. "_" .. spec[2] .. "_3"]
        all_done = all_done and e and e.done
    end
    check(all_done and M.hooks.PostRender.gsa1_charselect_paint == nil, "the first frame paints every menu texture at once (T.PaintNow in PostRender, one hook call)")
    check(tex_asked.frontend >= 5 and tex_asked.wrong == 0, "they come through gsa1.FrontendTexture; gsa1.Texture is never asked for kind 32 (2.4 C2)")
    local a = T.Archives(F.KIND)
    check(a.n == 2 and a[0].name == "AVA_BACK" and a[1].count == 4, "T.Archives on gsa1.FRONTEND.KIND: gsa1.FrontendTextureArchives")
    local m = T.Material(F.KIND, FE_BATCHES[2])
    check(m ~= nil, "T.Material on gsa1.FRONTEND.KIND works")
end
-- 0.9.9: the question mark's texture (sadc docs/research/small099.md 6.3, the prototype's 5 checks; gsa1_099_plan.md 2.4 C2). By name, render only, on the
-- menu's kind; tests/feat_question_test.lua has the same for the character (kind 8, archive 62: C1)
do
    local T = GSA1.Tex
    local NAMES = { [0] = "cs_ce_bd_1", "cs_ce_bd_2", "cs_ce_bd_3", "CS_CE_BU", "CS_CE_O", "CS_CE_OD", "CS_CE_OU", "CS_CE_TX", "cs_sinkou_e", "CS_TX_e", "sstx_body" }
    local fa, ft = G.FrontendTextureArchives, G.FrontendTexture
    local asked_tex = 0
    function G.FrontendTextureArchives() return { { name = "AVA_CHSEL_E", count = 11 }, { name = "OTHER", count = 8 } } end
    function G.FrontendTexture(i, a)
        asked_tex = asked_tex + 1
        if a == 1 then return { w = 4, h = 4, name = i == 7 and "CS_CE_TX" or "x" .. i, runs = "", nruns = 0 } end
        return { w = 8, h = 8, name = NAMES[i] or "?", runs = "", nruns = 0 }
    end
    local keep_a, keep_i, keep_e, keep_q = T.archives[F.KIND], T.infos, T.entries, T.queue
    T.archives[F.KIND], T.infos, T.queue = nil, {}, {}
    local function asked()
        local e = {}
        for k in pairs(T.entries) do e[#e + 1] = k end
        table.sort(e)
        return table.concat(e, " ")
    end
    local function fresh()
        T.entries = {}
        T.ForgetKeys()
    end
    local Q = { key = "7.7.68.1.0.3.0", archive = 0, tex = 7, flags = 0x68, wrap = 3, src = 1, dst = 0, pass = 0, tris = 692, all = 0x68, mat = 0x9461A400 }
    check(GetConVar("gsa1_charselect_qmark") ~= nil and T.Remap == S.QuestionTexture, "the option exists; T.Remap is S.QuestionTexture")
    fresh()
    T.Material(F.KIND, Q)
    check(string.find(asked(), F.KIND .. "_0_10_3", 1, true) ~= nil and string.find(asked(), F.KIND .. "_0_7_3", 1, true) == nil,
        "gsa1_charselect_qmark 1 (the default): the question mark's batch draws sstx_body (texture 10), clamped: %s", asked())
    S.cv.qmark:SetString("0")
    T.entries = {}
    T.Material(F.KIND, Q)
    check(string.find(asked(), F.KIND .. "_0_7_3", 1, true) ~= nil, "gsa1_charselect_qmark 0: as the Dreamcast, texture 7, after the callback's T.ForgetKeys: %s", asked())
    S.cv.qmark:SetString("1")
    fresh()
    T.Material(F.KIND, { key = "plain", archive = 0, tex = 7, flags = 0x11, wrap = 3, src = 4, dst = 5, pass = 1, tris = 2, all = 0x11, mat = 0 })
    check(string.find(asked(), F.KIND .. "_0_7_3", 1, true) ~= nil and string.find(asked(), F.KIND .. "_0_10_3", 1, true) == nil, "a batch that is not sphere-mapped keeps its texture: %s", asked())
    fresh()
    T.Material(F.KIND, { key = "other", archive = 0, tex = 6, flags = 0x68, wrap = 3, src = 1, dst = 0, pass = 0, tris = 2, all = 0x68, mat = 0 })
    check(string.find(asked(), F.KIND .. "_0_6_3", 1, true) ~= nil, "a sphere-mapped batch of another texture keeps it: %s", asked())
    fresh()
    T.Material(F.KIND, { key = "noBody", archive = 1, tex = 7, flags = 0x68, wrap = 3, src = 1, dst = 0, pass = 0, tris = 2, all = 0x68, mat = 0 })
    check(string.find(asked(), F.KIND .. "_1_7_3", 1, true) ~= nil, "an archive without sstx_body keeps the texture: %s", asked())
    if GSA1.LogFlush then GSA1.LogFlush() end
    check(string.find(M.files["gsa1/log.txt"] or "", "has no sstx_body: the question mark stays as the disc draws it", 1, true) ~= nil, "... with one log line")
    -- C2: the name first; the walk of the archive only for a batch that IS cs_ce_tx
    fresh()
    T.infos = {}
    asked_tex = 0
    T.Material(F.KIND, { key = "other2", archive = 0, tex = 5, flags = 0x68, wrap = 3, src = 1, dst = 0, pass = 0, tris = 2, all = 0x68, mat = 0 })
    check(asked_tex == 1, "C2: a sphere-mapped batch of another name makes one texture call (%d), no walk of its archive", asked_tex)
    G.FrontendTextureArchives, G.FrontendTexture = fa, ft
    T.archives[F.KIND], T.infos, T.entries, T.queue = keep_a, keep_i, keep_e, keep_q
    T.ForgetKeys()
end
-- the music comes from the game's own request
frames(2)
check(#calls.play == 1 and calls.play[1].ch == 1 and calls.play[1].music == 24, "the game's music request: track 24 on channel 1, once")
check(#calls.duck >= 1 and calls.duck[1].gain == 0, "the game's music silenced")
-- the keyboard: a press reaches the game, also one shorter than a frame
do
    keys[KEY_RIGHT or 91] = true
    press(KEY_RIGHT or 91)
    FE.inputs = {}
    fe_frames(3)
    keys[KEY_RIGHT or 91] = false
    check(#fe_presses(F.RIGHT) == 1, "Right: one press in the game's frames")
    fe_frames(25)
    check(S.st.slot == 3, "the slide ends: the select event moves the selection (slot %d)", S.st.slot)
    press(KEY_LEFT or 89)                      -- released before the next frame
    FE.inputs = {}
    fe_frames(2)
    check(#fe_presses(F.LEFT) == 1, "a press shorter than a frame still reaches the game")
    fe_frames(25)
    check(S.st.slot == 2, "back to slot 2 (%d)", S.st.slot)
    -- a frame rate above 60: a press waits for the frame that runs
    M.dt = 1 / 240
    press(KEY_D or 14)
    FE.inputs = {}
    for _ = 1, 8 do
        M.frame(1 / 240)
        open_panel():Think()
    end
    M.dt = 1 / 60
    check(#fe_presses(F.RIGHT) == 1, "at 240 frames a second a press waits for the game's next frame and goes once")
    fe_frames(25)
    press(KEY_A or 11)
    fe_frames(25)
    check(S.st.slot == 2, "A and D move as Left and Right (%d)", S.st.slot)
end
-- a click on a sphere, the mouse wheel
do
    fe_paint()
    local st = S.st
    local p = open_panel()
    local m = S.Layout(p.w, p.h, false)
    -- the k-th sphere is at x 100 + 60 k: slot (2 + k) mod 7
    local function click_sphere(k)
        p.cx, p.cy = m.ox + (116 + 60 * k) * m.sx, m.oy + 436 * m.sy
        p:OnMousePressed(MOUSE_LEFT or 107)
    end
    FE.inputs = {}
    click_sphere(2)                            -- slot 4: two to the right, 21 frames apart
    fe_frames(60)
    local rs = fe_presses(F.RIGHT)
    check(#rs == 2 and rs[2] - rs[1] == S.RUN_FRAMES and st.slot == 4, "a click on a sphere: the shortest run of presses, %d frames apart (slot %d)", S.RUN_FRAMES, st.slot)
    FE.inputs = {}
    click_sphere(6)                            -- (4 + 6) mod 7 = 3: one to the left
    fe_frames(30)
    check(#fe_presses(F.LEFT) == 1 and #fe_presses(F.RIGHT) == 0 and st.slot == 3, "the other way round when it is shorter (slot %d)", st.slot)
    FE.inputs = {}
    p:OnMouseWheeled(-1)
    fe_frames(30)
    check(#fe_presses(F.RIGHT) == 1 and st.slot == 4, "the wheel down: Right (slot %d)", st.slot)
    FE.inputs = {}
    p:OnMouseWheeled(1)
    fe_frames(30)
    check(#fe_presses(F.LEFT) == 1 and st.slot == 3, "the wheel up: Left (slot %d)", st.slot)
    FE.inputs = {}
    p:OnMouseWheeled(-1)
    p:OnMouseWheeled(-1)
    fe_frames(60)
    check(#fe_presses(F.RIGHT) == 2 and st.slot == 5, "two notches: two presses (slot %d)", st.slot)
    FE.inputs = {}
    p:OnMouseWheeled(1)
    fe_frames(30)
    p:OnMouseWheeled(1)
    fe_frames(30)
    p:OnMouseWheeled(1)
    fe_frames(30)
    check(st.slot == 2, "back on slot 2 (%d)", st.slot)
end
-- the picture: its order, the layout at 3440 x 1440
do
    fe_paint()
    local text = table.concat(trace, " ")
    local i_clear, i_start, i_prep, i_e1, i_e2, i_end = string.find(text, "cleardepth", 1, true), string.find(text, "start3d", 1, true), string.find(text, "prepare", 1, true),
        string.find(text, "emit1", 1, true), string.find(text, "emit2", 1, true), string.find(text, "end3d", 1, true)
    check(i_clear and i_start and i_prep and i_e1 and i_e2 and i_end and i_clear < i_start and i_start < i_prep and i_prep < i_e1 and i_e1 < i_e2 and i_e2 < i_end,
        "ClearDepth, cam.Start3D, FrontendPrepareView, the opaque batch, the blended batch, cam.End3D (%s)", text)
    local c = FE.cam
    check(c and c.x == 760 and c.y == 0 and c.w == 1920 and c.h == 1440 and c.fov == 70 and c.near > 0 and c.far > c.near, "the 3D in the 4:3 box: (760, 0), 1920 x 1440, the game's 70 degrees")
    -- the 2D before and after the 3D
    local before, after, inside = 0, 0, false
    local seen3d = false
    for _, t in ipairs(trace) do
        if t == "start3d" then seen3d = true end
        if t == "2d" and not seen3d then before = before + 1 end
        if t == "2d" and seen3d then after = after + 1 end
    end
    -- the sky three times, the title bar, seven spheres; hidden: the bottom bar's text; in front: one draw + the two 3D batches go through mesh too
    check(before == 3 + 1 + 1, "behind the 3D: the sky repeated three times (to the edges), the title bar, the spheres' one draw; File and Clear hidden (%d draws)", before)
    local xs = draws2d[4].xs
    local x0, x1 = math.min(unpack(xs)), math.max(unpack(xs))
    check(x0 == 0 and x1 == 3440, "the title bar reaches the screen's edges (x %d .. %d)", x0, x1)
    local sky0, sky2 = draws2d[1].xs, draws2d[3].xs
    check(math.min(unpack(sky0)) < 0 and math.max(unpack(sky2)) > 3440, "the sky goes past both edges")
    local sp = draws2d[5].xs
    check(math.abs(math.min(unpack(sp)) - (760 + 100 * 3)) < 1e-6, "a sphere stays where the 4:3 box puts it")
    check(string.find(text, "end3d", 1, true) < string.find(text, "2d", string.find(text, "end3d", 1, true), true), "the draw in front comes after the 3D")
    -- the bottom bar's two extra quads of the texture are no slots
    do
        local p = open_panel()
        local m = S.Layout(p.w, p.h, false)
        check(S.SphereAt(S.st, m.ox + (116 + 60 * 7) * m.sx, m.oy + 436 * m.sy, m) == nil, "the quads of sphe_7 after the ring's n are no slots")
    end
    S.cv.file:SetString("1")
    S.barcv.bar:SetString("0")              -- (1.0.0: with the bar on, File and Clear stay hidden whatever this option says: select 4.4, T5 below)
    fe_paint()
    local n = 0
    for _, t in ipairs(trace) do if t == "2d" then n = n + 1 end end
    S.barcv.bar:SetString("1")
    S.cv.file:SetString("0")
    S.cv.wide:SetString("1")
    fe_paint()
    local c2 = FE.cam
    local nw = 0
    for _, t in ipairs(trace) do if t == "2d" then nw = nw + 1 end end
    check(n == 3 + 1 + 1 + 1 + 1 and nw == 1 + 1 + 1 + 1 and c2.x == 0 and c2.w == 3440, "gsa1_charselect_file shows the hidden draw; gsa1_charselect_wide stretches (one sky, the 3D over the whole screen)")
    S.cv.wide:SetString("0")
end
-- back: the game's B, its fade, EV_CANCEL closes; no switch
do
    local C = GSA1.Char
    reset_calls()
    press(KEY_BACKSPACE or 66)
    fe_frames(4)
    check(S.IsOpen(), "Backspace: the game's fade first")
    fe_frames(10)
    check(not S.IsOpen() and GSA1.Char == C and #calls.stop == 1 and calls.stop[1].ch == 1, "EV_CANCEL closes it, no switch; the game's stop request ended the music")
end
-- a pick: the pose, the game's 5 seconds, then the switch
do
    GSA1.Spawn("sonic")
    frames(2)
    S.Open("test")
    FE.inputs = {}
    frames(1)
    press(KEY_RIGHT or 91)
    frames(25)
    local leaving0 = M.hook_runs.GSA1CharacterLeaving or 0
    press(KEY_ENTER or 64)
    frames(2)
    check(S.IsOpen() and S.st.picked == 1 and GSA1.Char.kind == 0, "Enter: the pose starts (slot 1), no switch yet")
    frames(299)
    check(not S.IsOpen() and GSA1.Char.kind == 2 and GSA1.cv.character:GetString() == "tails" and (M.hook_runs.GSA1CharacterLeaving or 0) == leaving0 + 1,
        "after the game's 300 frames: GSA1.Spawn(tails), the panel closed, the life events fired")
    -- the skip: a second A after the voice
    S.Open("test")
    frames(2)
    press(KEY_RIGHT or 91)
    frames(25)
    press(KEY_ENTER or 64)
    press(KEY_ENTER or 64)
    check(S.IsOpen(), "a second pick in the same frame does nothing: not before the voice")
    frames(3)
    press(KEY_ENTER or 64)
    check(not S.IsOpen() and GSA1.Char.kind == 3, "a pick input after the voice skips the pose (Knuckles)")
    -- gsa1_charselect_close 1: the switch when the voice starts
    S.cv.close:SetString("1")
    S.Open("test")
    frames(2)
    press(KEY_RIGHT or 91)
    frames(25)
    press(KEY_SPACE or 65)
    frames(3)
    check(not S.IsOpen() and GSA1.Char.kind == 5, "gsa1_charselect_close 1: the switch when the voice starts (Amy, kind %d)", GSA1.Char.kind)
    S.cv.close:SetString("0")
    -- the "?" slot, and the current Super Sonic starts on slot 6
    S.Open("test")
    frames(1)
    S.st.slot = 6
    FE.slot = 6
    frames(1)
    fe_paint()
    press(KEY_ENTER or 64)
    frames(4)
    press(KEY_ENTER or 64)
    check(not S.IsOpen() and GSA1.Char.name == "supersonic", "slot 6 plays the option's Super Sonic (%s)", tostring(GSA1.Char.name))
    S.Open("test")
    check(FE.opens[#FE.opens].slot == 6, "both Super Sonics: the first slot is 6")
    S.Close("test")
    GSA1.Spawn("sonic")
    frames(2)
end
-- charsel098 7's wording: a "pick" event for slot 2 and "done" make Knuckles with the ticked upgrades
do
    GSA1.cv["up_shovel_claw"]:SetString("1")
    S.Open("test")
    frames(2)
    fe_emit("pick", 2)
    frames(1)
    check(S.IsOpen() and S.st.picked == 2, "a \"pick\" event for slot 2: the pose")
    fe_emit("done", 2)
    frames(1)
    local ups2 = created_ups[#created_ups]
    local has = false
    for _, u in ipairs(ups2 or {}) do if u == "shovel_claw" then has = true end end
    check(not S.IsOpen() and GSA1.Char.kind == 3 and has and GSA1.cv.character:GetString() == "knuckles",
        "\"done\": gsa1.Create kind 3 with the ticked upgrades, gsa1_character = knuckles")
    GSA1.cv["up_shovel_claw"]:SetString("0")
    GSA1.Spawn("sonic")
    frames(2)
end
-- the click that picks: the selected sphere, or in the circle
do
    S.Open("test")
    frames(2)
    fe_paint()
    local p = open_panel()
    local m = S.Layout(p.w, p.h, false)
    p.cx, p.cy = m.ox + 116 * m.sx, m.oy + 436 * m.sy
    FE.inputs = {}
    p:OnMousePressed(MOUSE_LEFT or 107)
    frames(2)
    check(S.st and S.st.picked == 0 and #fe_presses(F.A) == 1, "a click on the selected sphere: A")
    frames(3)
    p:OnMousePressed(MOUSE_LEFT or 107)
    check(not S.IsOpen() and GSA1.Char.kind == 0, "a click after the voice skips the pose")
    S.Open("test")
    frames(2)
    fe_paint()
    p = open_panel()
    p.cx, p.cy = m.ox + 316 * m.sx, m.oy + 200 * m.sy
    FE.inputs = {}
    p:OnMousePressed(MOUSE_LEFT or 107)
    frames(2)
    check(S.st and S.st.picked == 0, "a click in the circle: A")
    S.Close("test")
    S.Open("test")
    frames(2)
    fe_paint()
    p = open_panel()
    p.cx, p.cy = 5, 5
    FE.inputs = {}
    p:OnMousePressed(MOUSE_LEFT or 107)
    frames(2)
    check(S.st and not S.st.picked and #fe_presses(F.A) == 0, "a click anywhere else does nothing")
    p:OnMousePressed(MOUSE_RIGHT or 108)
    frames(12)
    check(not S.IsOpen(), "a right click: back")
end
-- the controller: the Start that opened it has to be released first, Start = the game's Start, Back = B
do
    pad.connected = true
    pad.raw = S.PAD_START
    frames(2)
    check(S.IsOpen() and S.st.how == "start" and S.st.design == "R", "Start opens the game's screen")
    FE.inputs = {}
    frames(5)
    check(#fe_presses(F.START) == 0, "the opening press goes on being held: the game does not see it")
    pad.raw = 0
    frames(2)
    pad.raw = S.PAD_RIGHT
    frames(1)
    pad.raw = 0
    frames(25)
    check(#fe_presses(F.RIGHT) == 1 and S.st.slot == 1, "the D-pad: the game's Right (slot %d)", S.st.slot)
    pad.sx = -0.8
    frames(1)
    check(FE.lastStick[1] == -0.8, "the stick goes to the game as it is")
    pad.sx = 0
    frames(1)
    pad.raw = S.PAD_START
    frames(2)
    check(#fe_presses(F.START) == 1 and S.st.picked == 1, "released and pressed again: the game's Start, a pick")
    pad.raw = 0
    frames(3)
    pad.raw = S.PAD_A
    frames(2)
    check(not S.IsOpen() and GSA1.Char.kind == 2, "A after the voice skips the pose")
    pad.raw = 0
    frames(3)
    -- A held while it opens by another way
    pad.raw = S.PAD_A
    frames(1)
    S.Open("test")
    FE.inputs = {}
    frames(3)
    check(#fe_presses(F.A) == 0, "an A held at the open is not a press")
    pad.raw = 0
    frames(2)
    pad.raw = S.PAD_BACK
    frames(12)
    check(not S.IsOpen(), "Back: the game's B")
    pad.raw = 0
    pad.connected = false
    frames(2)
    GSA1.Spawn("sonic")
    frames(2)
end
-- the key and Escape work the same way with the game's screen
do
    S.Open("test")
    frames(1)
    S.cv.key:SetString("30")
    press(30)
    check(not S.IsOpen() and FE.closes > 0 and not FE.open, "the key closes it at once, with no game input")
    S.cv.key:SetString("0")
    S.Open("test")
    M.ui = true
    frames(1)
    check(not S.IsOpen() and not FE.open and M.ui == false, "Escape closes it at once")
end
-- nothing else while it is open: the world goes on, the player's input is neutral
do
    M.keys = IN_JUMP
    frames(2)
    S.Open("test")
    local dt0 = M.ticks.last
    frames(3)
    check(M.ticks.last ~= dt0 and M.ticks.last.buttons == 0, "the world goes on with a neutral pad")
    S.Close("test")
    M.keys = 0
end
-- the ways it fails: one log line each, then the simple chooser with the same buttons
do
    local function log_has(word)
        if GSA1.LogFlush then GSA1.LogFlush() end
        return string.find(M.files["gsa1/log.txt"] or "", word, 1, true) ~= nil
    end
    -- a fault in a tick
    reset_calls()
    S.Open("test")
    frames(2)
    FE.fault = true
    frames(1)
    FE.fault = false
    check(S.IsOpen() and S.st.design == "S" and S.st.fallback and not FE.open and log_has("the game faulted at 8C900000"), "a fault: FrontendClose, one log line, the simple chooser (%s)", tostring(S.st and S.st.fallback))
    check(#calls.play == 1 and calls.play[1].music == 24, "its music goes on: no second source")
    frames(2)
    S.st.slot = 1
    press(KEY_ENTER or 64)
    check(not S.IsOpen() and GSA1.Char.kind == 2, "the chooser's pick works")
    -- a refusal at the open
    FE.refuse = "the disc is not loaded yet"
    S.Open("test")
    check(S.IsOpen() and S.st.design == "S" and string.find(S.st.fallback or "", "not loaded", 1, true) and log_has("the simple chooser: the disc is not loaded yet"), "a refusal at the open: the chooser, the reason logged")
    frames(1)
    S.Close("test")
    FE.refuse = nil
    -- the screen's fault while painting
    S.Open("test")
    frames(1)
    FE.screenFail = true
    fe_paint()
    FE.screenFail = false
    check(S.IsOpen() and S.st.design == "S" and not FE.open, "FrontendScreen failing in the paint: the chooser")
    S.Close("test")
    -- a Lua error while painting (inside the 3D part: its view is ended)
    S.Open("test")
    frames(1)
    local emit = G.FrontendEmitBatch
    G.FrontendEmitBatch = function() error("boom") end
    local n_end = 0
    local end3d = cam.End3D
    cam.End3D = function() n_end = n_end + 1 end
    fe_paint()
    G.FrontendEmitBatch = emit
    cam.End3D = end3d
    check(S.IsOpen() and S.st.design == "S" and n_end == 1 and log_has("boom"), "a Lua error in the paint: the 3D view is ended, one log line, the chooser")
    S.Close("test")
    -- the disc went (gsa1.Shutdown; the module answers not_ready: R98.20)
    S.Open("test")
    frames(1)
    FE.gone = true
    frames(1)
    FE.gone = false
    check(S.IsOpen() and S.st.design == "S", "the module answering not_ready: the chooser")
    S.Close("test")
    -- the feature gone from the module
    G.FEATURES.frontend = nil
    S.Open("test")
    check(S.st.design == "S" and S.st.fallback == nil and log_has("the module has no feature"), "no feature \"frontend\": the chooser, one log line, no error text on it")
    S.Close("test")
    G.FEATURES.frontend = 1
end
do
    local n0 = FE.ticks
    frames(5)
    check(FE.ticks == n0 and not S.IsOpen(), "closed: nothing of the front end runs")
end

-- ---- 1.0.0 beta 1 (sadc docs/research/gsa1_100_select.md 4.4-4.6, 4.9, 7.2 T4, T5, T8 with RX.1): the bar, skins on Up / Down, CHOOSE YOUR UPGRADE, the pick path pinned -------------------------------
do
    local skin_calls = {}
    G.SUPER = G.SUPER or {}
    G.SUPER.CREATE_SKIN = G.SUPER.CREATE_SKIN or 0x4000
    function G.FrontendSkin(desc, quiet)
        if FE.refuseSkin and desc then return nil, FE.refuseSkin, "not_found" end
        skin_calls[#skin_calls + 1] = desc and desc.id or false
        return true
    end
    local U = GSA1.UpgradeModels
    for _, u in ipairs(GSA1.UPGRADES) do
        M.convars["gsa1_upgrade_" .. u.name]:SetString("0")
        if M.convars["gsa1_upgrade_model_" .. u.name] then M.convars["gsa1_upgrade_model_" .. u.name]:SetString("0") end     -- (none for Ancient Light: no model)
    end
    local function pad_press(bits)
        pad.raw = bits
        frames(1)
        pad.raw = 0
        frames(1)
    end
    local function open_on_sonic()
        if S.IsOpen() then S.Close("test") end
        GSA1.Spawn("sonic")
        frames(2)
        S.Open("test")
        frames(3)
        return S.st
    end
    pad.connected = true
    local st = open_on_sonic()
    check(st and st.design == "R" and st.slot == 0, "T4 the game's screen on Sonic")
    -- T4: Up and Down step the slot's skins, one step a press, only idle, and reach the game always (RM.5, F2)
    FE.inputs = {}
    pad_press(S.PAD_UP)
    local a1 = st.skins[0]
    pad_press(S.PAD_UP)
    local a2 = st.skins[0]
    pad_press(S.PAD_UP)
    local a3 = st.skins[0]
    check(a1 == 2 and a2 == 3 and a3 == 1 and skin_calls[1] == "metalsonic" and skin_calls[2] == "mechasonic" and skin_calls[3] == false,
        "T4 Up: Sonic > Metal Sonic > Mecha Sonic > Sonic, on the game's screen each time (%s %s %s)", tostring(a1), tostring(a2), tostring(a3))
    pad_press(S.PAD_DOWN)
    local b1 = st.skins[0]
    pad_press(S.PAD_DOWN)
    local b2 = st.skins[0]
    pad_press(S.PAD_DOWN)
    check(b1 == 3 and b2 == 2 and st.skins[0] == 1, "T4 Down goes the other way")
    check(#fe_presses(F.UP) == 3 and #fe_presses(F.DOWN) == 3, "T4 Up and Down still reach gsa1.FrontendTick, every press (%d, %d)", #fe_presses(F.UP), #fe_presses(F.DOWN))
    pad.raw = S.PAD_UP
    frames(5)
    pad.raw = 0
    frames(1)
    check(st.skins[0] == 2, "T4 held: one step a press")
    S.SetSkin(st, 0, 1)
    FE.phase = 2
    frames(1)
    FE.inputs = {}
    pad_press(S.PAD_UP)
    check(st.skins[0] == 1 and #fe_presses(F.UP) == 1, "T4 in another phase (the dialog): no step, and Up still reaches the game (its cursor)")
    FE.phase = 0
    frames(1)
    -- the keyboard: Up / W forward, Down / S back
    press(KEY_W or 33)
    check(st.skins[0] == 2, "T4 W: forward")
    press(KEY_S or 29)
    check(st.skins[0] == 1, "T4 S: back")
    -- a refusal leaves the index
    FE.refuseSkin = "the disc has no such file"
    press(KEY_UP or 88)
    check(st.skins[0] == 1 and S.EntryName(0) == "sonic", "T4 a refusal of the module leaves the index: the pick names what the screen showed")
    FE.refuseSkin = nil
    -- the counter's text and the ball, by the shown entry
    press(KEY_UP or 88)
    local i, n = S.SkinOf(st, 0)
    check(i == 2 and n == 3 and S.BallTint(st)[1] == 255 and S.BallTint(st)[2] == 0, "T5 Metal shown: \"2/3\", the red ball (upgrade_model_compatibility none)")
    S.SetSkin(st, 0, 1)
    check(S.BallTint(st)[2] == 255 and S.BallTint(st)[1] == 77, "T5 Sonic: the green ball (full; 1.0.0-beta1a: the owner's 11.png green 4DFF00)")
    st.slot = 1
    i, n = S.SkinOf(st, 1)
    check(i == 1 and n == 1 and S.BallTint(st)[2] == 255 and S.BallTint(st)[1] == 77, "T5 Tails: \"1/1\", green")
    st.slot = 0

    -- T4: Y opens CHOOSE YOUR UPGRADE, only idle; with it up the game gets Start alone from the pad
    pad_press(S.PAD_Y)
    check(st.panel_up == true and #st.upList == 3, "T4 Y opens the panel on Sonic (3 rows)")
    FE.inputs = {}
    local s0 = U.StateNow("light_speed_shoes")
    pad.raw, pad.sx, pad.sy = S.PAD_A + S.PAD_LEFT, 1, 0
    frames(1)
    local last = FE.inputs[#FE.inputs]
    check(last and last.buttons == 0 and FE.lastStick[1] == 0 and FE.lastStick[2] == 0, "T4 the panel up: no A, Left or stick reaches the game (%s)", tostring(last and last.buttons))
    pad.raw, pad.sx = 0, 0
    frames(1)
    check(st.panel_up and S.IsOpen() and st.slot == 0, "T4 the panel took them: the screen stays, the ring did not move")
    check(s0 == "off" and U.StateNow("light_speed_shoes") == "on", "T4 A: the selected row one step (off > on)")
    pad_press(S.PAD_RB)
    local all = true
    for _, u in ipairs(st.upList) do all = all and U.StateNow(u.name) == "on" end
    check(all, "T4 RB: every row active and visible")
    pad_press(S.PAD_LB)
    all = true
    for _, u in ipairs(st.upList) do all = all and U.StateNow(u.name) == "off" end
    check(all, "T4 LB: every row disabled entirely")
    -- RX.1 the keyboard with the panel up: E and Right step, Up / Down move; never the pick keys
    press(KEY_E or 15)
    check(U.StateNow("light_speed_shoes") == "on", "RX.1 E steps the upgrade you are on")
    press(KEY_DOWN or 90)
    press(KEY_RIGHT or 91)
    check(st.upSel == 2 and U.StateNow("crystal_ring") == "on" and st.slot == 0, "RX.1 Down moves, Right steps (the ring does not move: slot %d)", st.slot)
    pad_press(S.PAD_B)
    frames(1)
    check(not st.panel_up and S.IsOpen() and #fe_presses(F.B) == 0, "T4 B closes the panel only: the screen stays, the game never saw B")
    pad_press(S.PAD_B)
    frames(12)
    check(not S.IsOpen(), "T4 then B again goes back as always (the game's fade, EV_CANCEL)")

    -- RX.1 THE PICK PATH WITH THE PANEL UP: Enter, keypad Enter, Space and Start pick; Escape closes the screen
    for _, how in ipairs({ { "Enter", KEY_ENTER or 64 }, { "keypad Enter", KEY_PAD_ENTER or 51 }, { "Space", KEY_SPACE or 65 }, { "Start" }, { "Escape", KEY_ESCAPE or 70 } }) do
        st = open_on_sonic()
        pad_press(S.PAD_Y)
        local up = st.panel_up
        if how[2] then press(how[2]) else pad_press(S.PAD_START) end
        frames(2)
        if how[1] == "Escape" then
            check(up and not S.IsOpen(), "RX.1 the panel up: Escape closes the whole screen (S.OnKey first)")
        else
            check(up and st.picked == 0 and not st.panel_up, "RX.1 the panel up: %s picks, as in 0.9.9g, and the panel closes the frame the bar sees st.picked", how[1])
        end
    end
    if S.IsOpen() then S.Close("test") end
    -- U: the panel, unless U is the person's own Character Select key (then S.OnKey closes the screen)
    st = open_on_sonic()
    press(KEY_U or 31)
    check(st.panel_up, "T4 U opens the panel")
    press(KEY_U or 31)
    frames(1)
    check(not st.panel_up and S.IsOpen(), "T4 U again closes it")
    S.cv.key:SetString(tostring(KEY_U or 31))
    press(KEY_U or 31)
    check(not S.IsOpen(), "RX.1 U as the person's Character Select key: closes the screen, never the panel")
    S.cv.key:SetString("0")
    -- the bar off: no panel, no filter's colour; File and Clear by their own option
    S.barcv.bar:SetString("0")
    st = open_on_sonic()
    check(S.DrawFilter(st, "cs_sinkou_e", {}, 0) == nil, "T5 the bar off: the game's bottom bar as today")
    S.barcv.bar:SetString("1")
    S.cv.file:SetString("1")
    check(S.DrawFilter(st, "cs_sinkou_e", {}, 0) == false and S.DrawFilter(st, "fs_file_num1", {}, 0) == false, "T5 the bar on: File and Clear hidden, whatever gsa1_charselect_file says")
    S.cv.file:SetString("0")
    S.barcv.upgrades:SetString("0")
    pad_press(S.PAD_Y)
    check(not st.panel_up, "T4 gsa1_charselect_upgrades 0: Y does nothing")
    S.barcv.upgrades:SetString("1")
    if S.IsOpen() then S.Close("test") end

    -- Design S: the panel's buttons out of the edges, Start alone picks; A steps, never picks
    FE.refuse = "test: no game screen"
    GSA1.Spawn("sonic")
    frames(2)
    S.Open("test")
    frames(2)
    st = S.st
    check(st.design == "S", "Design S")
    pad_press(S.PAD_Y)
    check(st.panel_up, "T4 Design S: Y opens the panel")
    local before = U.StateNow("light_speed_shoes")
    pad_press(S.PAD_A)
    check(S.IsOpen() and U.StateNow("light_speed_shoes") ~= before, "RX.1 Design S: A steps the row and does not pick")
    pad_press(S.PAD_START)
    check(not S.IsOpen(), "RX.1 Design S: Start picks with the panel up")
    FE.refuse = nil
    pad.connected = false
    for _, u in ipairs(GSA1.UPGRADES) do
        M.convars["gsa1_upgrade_" .. u.name]:SetString("0")
        if M.convars["gsa1_upgrade_model_" .. u.name] then M.convars["gsa1_upgrade_model_" .. u.name]:SetString("0") end     -- (none for Ancient Light: no model)
    end
    frames(30)
end

-- T5: the draw filter: a skin's name and nameplate pictures on the game's own draws; the support ball's colour on the game's left sphere
do
    -- (the names fix after beta 1a, sadc/build/research/b1a2: a skin's name and plate are atlas pictures of feat/cl_skinhud.lua, drawn at the game's own quad with surface.DrawTexturedRectUV in the
    -- quad's colour, the bar's labels' call; the filter then answers false and paint_2d skips the game's draw. Beta 1a swapped a canvas material onto the game's vertices)
    local st = { slot = 0, design = "R", skins = { [0] = 2 }, state = { phase = 0 }, scr = { v = {} }, F = { KIND = 32 }, m = S.Layout(1280, 960, false, {}) }
    local H = GSA1.SkinHud
    local page = { tag = "atlas page" }
    local pA = { mat = page, u0 = 0, v0 = 0, u1 = 0.25, v1 = 0.125, w = 512, h = 128 }
    local pB = { mat = page, u0 = 0.25, v0 = 0, u1 = 0.75, v1 = 0.125, w = 1024, h = 128 }
    H.mats.metalsonic = { name = pA, plate = pB }
    local QD, QV = {}, st.scr.v
    local function gquad(d, x0, y0, x1, y1, a)
        local first = #QV / 8
        for _, p in ipairs({ { x0, y0, 0, 0 }, { x1, y0, 1, 0 }, { x1, y1, 1, 1 }, { x0, y0, 0, 0 }, { x1, y1, 1, 1 }, { x0, y1, 0, 1 } }) do
            local o = #QV
            QV[o + 1], QV[o + 2], QV[o + 3], QV[o + 4], QV[o + 5], QV[o + 6], QV[o + 7], QV[o + 8] = p[1], p[2], p[3], p[4], 255, 255, 255, a
        end
        local k = d * 11
        QD[k + 1], QD[k + 2], QD[k + 3], QD[k + 4], QD[k + 5] = 0, first, 6, 5, 0
        return k
    end
    local kn = gquad(0, 205.5, 314.4, 426.5, 369.6, 255)        -- (m_sonic's and B_SONIC_e's quads MEASURED on the real screen, charselect_screen.lua)
    local kp = gquad(1, 164, 390, 563.4, 439.9, 128)
    local drawn, col, smat = {}, nil, nil
    local sdc, ssm, suv = surface.SetDrawColor, surface.SetMaterial, surface.DrawTexturedRectUV
    surface.SetDrawColor = function(r, g, b, a) col = { r, g, b, a } end
    surface.SetMaterial = function(m) smat = m end
    surface.DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1) drawn[#drawn + 1] = { x = x, y = y, w = w, h = h, uv = { u0, v0, u1, v1 }, mat = smat, c = col } end
    local m = st.m
    local function at(d, x0, y0, x1, y1)
        if not d then return false end
        local px, py = math.floor(m.ox + x0 * m.sx + 0.5), math.floor(m.oy + y0 * m.sy + 0.5)
        return d.x == px and d.y == py and d.w == math.floor(m.ox + x1 * m.sx + 0.5) - px and d.h == math.floor(m.oy + y1 * m.sy + 0.5) - py
    end
    local rn, rp, rj = S.DrawFilter(st, "m_sonic", QD, kn), S.DrawFilter(st, "B_SONIC_e", QD, kp), S.DrawFilter(st, "b_sonic", QD, kp)
    local d1, d2 = drawn[1], drawn[2]
    check(rn == false and rp == false and rj == false and #drawn == 3 and d1.mat == page and d1.uv[1] == 0 and d1.uv[2] == 0 and d1.uv[3] == 0.25 and d1.uv[4] == 0.125 and at(d1, 205.5, 314.4, 426.5, 369.6)
        and d1.c[1] == 255 and d1.c[4] == 255 and d2.uv[1] == 0.25 and d2.uv[3] == 0.75 and at(d2, 164, 390, 563.4, 439.9) and d2.c[4] == 128,
        "T5 Metal shown: m_sonic and B_SONIC_e (Japanese b_sonic too) are his pictures, drawn at the game's quad with surface.DrawTexturedRectUV in its colour and alpha; the game's draw skipped (false)")
    drawn = {}
    check(S.DrawFilter(st, "m_tails", QD, kn) == nil and #drawn == 0, "T5 another slot's name stays the game's")
    S.barcv.names:SetString("0")
    check(S.DrawFilter(st, "m_sonic", QD, kn) == nil and #drawn == 0, "T5 gsa1_charselect_skin_names 0: the game's SONIC under him")
    S.barcv.names:SetString("1")
    H.mats.metalsonic = { name = false, plate = false }
    check(S.DrawFilter(st, "m_sonic", QD, kn) == nil and #drawn == 0, "T5 a picture not made yet, or read changed (the fallback): the game's own (never a blank or black frame)")
    -- not one plain quad (another shape, more colours): the game's own
    H.mats.metalsonic = { name = pA, plate = pB }
    QV[QD[kn + 2] * 8 + 13] = 200
    check(S.DrawFilter(st, "m_sonic", QD, kn) == nil and #drawn == 0, "T5 a quad of more than one colour: the game's own")
    QV[QD[kn + 2] * 8 + 13] = 255
    surface.SetDrawColor, surface.SetMaterial, surface.DrawTexturedRectUV = sdc, ssm, suv
    H.mats.metalsonic = nil
    -- the left sphere: the 50 x 50 tinted base at (128, 418); its white shine and the ring's 48 x 48 spheres are left alone (LANDING.md C)
    local D, V = {}, st.scr.v
    local function quad(d, cx, cy, size, r, g, b)
        local first = #V / 8
        local x0, y0, x1, y1 = cx - size / 2, cy - size / 2, cx + size / 2, cy + size / 2
        for _, p in ipairs({ { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y0 }, { x1, y1 }, { x0, y1 } }) do
            local o = #V
            V[o + 1], V[o + 2], V[o + 3], V[o + 4], V[o + 5], V[o + 6], V[o + 7], V[o + 8] = p[1], p[2], 0, 0, r, g, b, 255
        end
        local k = d * 11
        D[k + 1], D[k + 2], D[k + 3] = 0, first, 6
        return k
    end
    local base = quad(0, 128, 418, 50, 255, 0, 0)
    local shine = quad(1, 128, 418, 50, 255, 255, 255)
    local ring = quad(2, 193.2, 215.9, 48, 0, 0, 255)
    local right = quad(3, 504, 418, 50, 255, 0, 0)
    st.skins[0] = 1
    -- (1.0.0-beta1a: the game merges the spheres into one draw, so the filter colours the ball's own six vertices and returns nil; the real screen: tests/feat_charselect_bar_test.lua B1)
    local function rgb(k) local o = D[k + 2] * 8 return V[o + 5], V[o + 6], V[o + 7] end
    local t = S.DrawFilter(st, "sphe_7", D, base)
    local r, g, b = rgb(base)
    check(t == nil and r == 77 and g == 255 and b == 0, "T5 Sonic: the left sphere's base turns green (full)")
    st.skins[0] = 3
    t = S.DrawFilter(st, "sphe_7", D, base)
    r, g, b = rgb(base)
    check(t == nil and r == 255 and g == 0 and b == 0, "T5 Mecha Sonic: red (none)")
    local same = S.DrawFilter(st, "sphe_7", D, shine) == nil and S.DrawFilter(st, "sphe_7", D, ring) == nil and S.DrawFilter(st, "sphe_7", D, right) == nil
    local s1, s2, s3 = rgb(shine)
    local q1, q2, q3 = rgb(ring)
    local w1, w2, w3 = rgb(right)
    check(same and s1 + s2 + s3 == 765 and q1 == 0 and q2 == 0 and q3 == 255 and w1 == 255 and w2 == 0 and w3 == 0,
        "T5 the shine, a ring sphere (48 x 48, centre left of x 320) and the right sphere keep the game's colours")
    local src = host_read(root .. "/gsa1/feat/cl_charselect.lua")
    check(string.find(src, "alt = S.DrawFilter(st, name, D, k)", 1, true) ~= nil and string.find(src, "if tint then mesh.Color(tint[1], tint[2], tint[3], V[o + 8])", 1, true) ~= nil,
        "T5 paint_2d's seam: the filter's material or vertex colours (the game's alpha kept)")
end

-- T8 (RX.1): the Start and Escape paths and every pick and back line, by content, against the frozen 0.9.9g release ------------------------------------------------------------------------------
do
    -- (r1-verify-s: without build/release_0.9.9g, a fresh clone, a scratch copy or the public repo, the pins shrank to an info line.) Each pinned block is compared with the FNV-1a 32 of
    -- 0.9.9g's own, stored here, always; with the frozen release beside the addon also with its text, and the stored hashes are checked against it
    local PIN_0999G = {
        ["function S.StartAllowed()"] = "6f550bc8", ["local function think()"] = "57049bb0", ["function S.OnKey(code)"] = "259699a9", ["function S.Step()"] = "16217b5b",
        ["hook.Add(\"OnPauseMenuShow\""] = "bbe9afea", ["function S.Close(why)"] = "dca69f33", ["function S.Finish(slot)"] = "6cbafaa4", ["function S.Toggle(how)"] = "578274d4",
        ["local function make_panel(st)"] = "f5b688b2", ["local function pick_input(st, code)"] = "405bd32e", ["local function events_r(st)"] = "fcd5697a",
    }
    local function fnv1a(s)
        local h = bit.tobit(0x811C9DC5)
        for i = 1, #s do
            h = bit.tobit(bit.lshift(bit.bxor(h, string.byte(s, i)), 24) + bit.bxor(h, string.byte(s, i)) * 403)
        end
        return bit.tohex(h)
    end
    local src = string.gsub(host_read(root .. "/gsa1/feat/cl_charselect.lua") or "", "\r", "")
    local rel = host_read(root .. "/../../build/release_0.9.9g/addon/lua/gsa1/feat/cl_charselect.lua")
    if rel then rel = string.gsub(rel, "\r", "") end
    check(fnv1a("") == "811c9dc5" and fnv1a("a") == "e40c292c", "T8 the pins' hash is FNV-1a 32 (its two reference values)")
    if not rel then info("T8 no frozen 0.9.9g release beside the addon (a fresh clone or a scratch copy): the blocks are compared with 0.9.9g's hashes stored in this test, the lines with their text here") end
    do
        local function block(text, head, tail)
            local a = string.find(text, head, 1, true)
            if not a then return "" end
            local b = string.find(text, tail, a, true)
            return b and string.sub(text, a, b + #tail - 1) or ""
        end
        local pins = {
            { "function S.StartAllowed()", "\nend\n" }, { "local function think()", "\nend\n" }, { "function S.OnKey(code)", "\nend\n" },
            { "function S.Step()", "\nend\n" }, { "hook.Add(\"OnPauseMenuShow\"", "\nend)\n" }, { "function S.Close(why)", "\nend\n" },
            { "function S.Finish(slot)", "\nend\n" }, { "function S.Toggle(how)", "\nend\n" }, { "local function make_panel(st)", "\nend\n" },
            { "local function pick_input(st, code)", "\nend\n" },
        }
        local bad, stored = {}, {}
        for _, p in ipairs(pins) do
            local x = block(src, p[1], p[2])
            if x == "" or fnv1a(x) ~= PIN_0999G[p[1]] or (rel and x ~= block(rel, p[1], p[2])) then bad[#bad + 1] = p[1] end
            if rel and fnv1a(block(rel, p[1], p[2])) ~= PIN_0999G[p[1]] then stored[#stored + 1] = p[1] end
        end
        if rel then
            if fnv1a(block(rel, "local function events_r(st)", "\nend\n")) ~= PIN_0999G["local function events_r(st)"] then stored[#stored + 1] = "events_r" end
            check(#stored == 0, "T8 the stored hashes are 0.9.9g's own (checked against the frozen release: %s)", table.concat(stored, "; "))
        end
        check(#bad == 0, "T8 not one line changed against 0.9.9g: S.StartAllowed, think, S.OnKey, S.Step, the OnPauseMenuShow hook, S.Close, S.Finish, S.Toggle, make_panel, pick_input (%s)", table.concat(bad, "; "))
        -- every pick and back line of every input path, by content (their line numbers move with the seams)
        local lines = {
            "    if st.picked then\n        if band(pressed, S.PAD_A + S.PAD_START) ~= 0 then\n            pick_input(st)\n            if S.st ~= st then return end\n        end\n        sx, sy = 0, 0\n",
            "        if band(pad, S.PAD_A) ~= 0 then b = bor(b, F.A) end\n        if band(pad, S.PAD_START) ~= 0 then b = bor(b, F.START) end\n        if band(pad, S.PAD_B + S.PAD_BACK) ~= 0 then b = bor(b, F.B) end\n",
            "    if band(pressed, S.PAD_A + S.PAD_START) ~= 0 then return S.Finish(st.slot) end\n    if band(pressed, S.PAD_B + S.PAD_BACK) ~= 0 then return S.Close(\"back\") end\n",
            "    if code == KEY_PICK or code == KEY_PICK_PAD or code == KEY_PICK_SPACE then return pick_input(st, code) end\n    if st.picked then return end\n",
            "    if code == KEY_GO_BACK then return pulse(st, F.B, code) end\n",
            "    if code == KEY_PICK or code == KEY_PICK_PAD or code == KEY_PICK_SPACE then return S.Finish(st.slot) end\n    if code == KEY_GO_BACK then return S.Close(\"back\") end\n",
            "    if code == M_RIGHT then\n        if not st.picked then pulse(st, st.F.B) end\n        return\n    end\n    if code ~= M_LEFT then return end\n    if st.picked then return pick_input(st) end\n",
            "    if slot then return pick_input(st) end\n",
            "    if (mx - cx) * (mx - cx) + (my - cy) * (my - cy) <= r * r then return pick_input(st) end\n",
            "        elseif kind == \"pick\" then\n            st.picked, st.pickFrame, st.run = id >= 0 and id or st.slot, st.frame, nil\n            st.slot = st.picked\n            log(\"the pose: slot %d\", st.picked)\n        elseif kind == \"done\" then\n            S.Finish(st.picked or (id >= 0 and id) or st.slot)\n            return\n        elseif kind == \"cancel\" then\n            S.Close(\"back\")\n            return\n",
            "    if S.st == st and st.picked and cv.close:GetInt() == 1 and st.frame > st.pickFrame then\n",
        }
        local missing = {}
        for i, l in ipairs(lines) do
            local _, nx = string.gsub(src, l:gsub("%p", "%%%0"), "")
            local _, ny = string.gsub(rel or l, l:gsub("%p", "%%%0"), "")
            if nx ~= 1 or ny ~= 1 then missing[#missing + 1] = tostring(i) .. " (" .. nx .. "/" .. ny .. ")" end
        end
        check(#missing == 0, "T8 RX.1: step_r's picked branch and its A / Start / B lines, step_s's Start and B lines, key_r's and key_s's pick and back lines, mouse_r's pick_input calls, events_r's pick, done "
            .. "and cancel branches, the close option's line: each once, as in 0.9.9g (%s)", table.concat(missing, ", "))
        -- the seams take nothing of it: the key filter says no to the pick keys and the person's own key first
        local bar = host_read(root .. "/gsa1/feat/cl_charselect_bar.lua") or ""
        check(string.find(bar, "if K_PICK[code] or S.IsOwnKey(code) then return false end", 1, true) ~= nil and string.find(src, "if st.panel_up then b, sx, sy = band(b, F.START), 0, 0 end", 1, true) ~= nil,
            "T8 RX.1: the key filter never takes Enter, keypad Enter, Space or the person's own key; with the panel up the pad gives the game Start alone")
        local evb = block(src, "local function events_r(st)", "\nend\n")
        check(evb ~= "" and fnv1a(evb) == PIN_0999G["local function events_r(st)"] and (not rel or evb == block(rel, "local function events_r(st)", "\nend\n")), "T8 RX.1: no line goes into events_r")
    end
end
-- 18. the mock against the module's frontend_api.txt (5.5, review R98.14): the binding test writes it whenever the snapshot's libsa1.h defines
-- SA1_API_FRONTEND; then it must exist and the mock must match it (a missing file is a failure)
do
    local groot = string.gsub(tests, "[/" .. string.char(92) .. "]tests$", "")
    local hdr = host_read(groot .. "/build/deps/include/libsa1.h") or ""
    if not string.find(hdr, "#define SA1_API_FRONTEND", 1, true) then
        info("frontend_api.txt: the snapshot's libsa1.h has no SA1_API_FRONTEND yet - the check is skipped (5.5's rule)")
    else
        local api = host_read(groot .. "/build/x86_64-windows/frontend_api.txt")
        local wrong, nf, nc = {}, 0, 0
        if not api then
            wrong[1] = "no build/x86_64-windows/frontend_api.txt"
        else
            for line in string.gmatch(api, "[^\r\n]+") do
                if string.sub(line, 1, 1) ~= "#" then
                    local f = {}
                    for part in string.gmatch(line .. "\t", "([^\t]*)\t") do f[#f + 1] = part end
                    if f[1] == "feature" and tonumber(G.FEATURES[f[2]]) ~= tonumber(f[3]) then
                        wrong[#wrong + 1] = "feature " .. tostring(f[2])
                    elseif f[1] == "function" then
                        nf = nf + 1
                        if type(G[f[2]]) ~= "function" then wrong[#wrong + 1] = "function " .. f[2] end
                    elseif f[1] == "const" then
                        nc = nc + 1
                        if tonumber(G.FRONTEND[f[2]]) ~= tonumber(f[3]) then wrong[#wrong + 1] = "const " .. f[2] end
                    end
                end
            end
            if nf < 15 or nc < 9 then wrong[#wrong + 1] = string.format("only %d functions, %d constants", nf, nc) end
        end
        check(#wrong == 0, "this test's mock matches build/x86_64-windows/frontend_api.txt (%d functions, %d constants): %s", nf, nc, table.concat(wrong, ", "))
    end
end

-- 16. the session log: one line per open, pick, cancel ---------------------------------------------------------------------------------------------
if GSA1.LogFlush then GSA1.LogFlush() end
do
    local opens, picks, closes = count_log("open ("), count_log("pick:"), count_log("close:")
    check(opens > 0 and picks > 0 and closes > 0, "the session log has charselect lines (%d open, %d pick, %d close)", opens, picks, closes)
end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))

return done()
