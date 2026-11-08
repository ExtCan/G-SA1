-- feat_upgrades_test.lua - the upgrade models and CHOOSE YOUR UPGRADE (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 3.2, 4.6 with RX.1, 6, 7.2 T2, T3): feat/sh_upgrades.lua and
-- feat/cl_upgrades.lua through the addon's autorun, tests/lua_mock.lua, in Garry's Mod's own LuaJIT, a mock of the module's game option and front end. No game byte: numbers and names.
--   lua_host tests/feat_upgrades_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_upgrades_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

local cookies = {}
cookie = { GetNumber = function(k, d) return tonumber(cookies[k]) or d end, Set = function(k, v) cookies[k] = v end, GetString = function(k, d) return cookies[k] or d end }

local G = M.module({ speed = 300, features = { super = 5, jukebox = 1, emote = 3, follower = 2, frontend = 1, charopt = 1 } })
G.CHAROPT = G.CHAROPT or {}
G.CHAROPT.UPGRADE_MODELS, G.CHAROPT.UPGRADE_MODELS_ON, G.CHAROPT.UPGRADE_MODELS_ALL = 5, 0x80000000, 0xF1FFF
local gopts = {}
function G.SetGameOption(id, opt, v)
    gopts[#gopts + 1] = { id = id, opt = opt, v = v }
    return true
end
local fe_up = {}
function G.FrontendUpgradeModels(kind, v)
    fe_up[#fe_up + 1] = { kind = kind, v = v }
    return true
end

-- the panels Character Select makes (enough of vgui for S.Open), the keyboard
local PANEL = {}
PANEL.__index = PANEL
for _, k in ipairs({ "SetPos", "SetSize", "MakePopup", "SetKeyboardInputEnabled", "SetMouseInputEnabled", "SetConVar", "SetTall", "SetImage" }) do PANEL[k] = function() end end
function PANEL:GetWide() return 1920 end
function PANEL:GetTall() return 1440 end
function PANEL:CursorPos() return 0, 0 end
function PANEL:IsVisible() return not self.removed end
function PANEL:IsValid() return not self.removed end
function PANEL:Remove()
    if self.removed then return end
    self.removed = true
    if self.OnRemove then self:OnRemove() end
end
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
local U, S = GSA1 and GSA1.UpgradeModels, GSA1 and GSA1.CharSelect
check(U ~= nil and U.PanelOpen ~= nil and S ~= nil and S.PadFilter ~= nil, "feat/sh_upgrades.lua, cl_upgrades.lua and cl_charselect_bar.lua are there")
if not (U and S) then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }

local function cvset(name, v) M.convars[name]:SetString(tostring(v)) end
local function reset_all()
    for _, u in ipairs(GSA1.UPGRADES) do
        cvset("gsa1_upgrade_" .. u.name, 0)
        if not U.NO_MODEL[u.name] then cvset("gsa1_upgrade_model_" .. u.name, 0) end
    end
end

-- ---- T2: the four states, the A cycle, R and L, the two ConVars -------------------------------------------------------------------------------------------------------------------------------
check(U.Next("on") == "hidden" and U.Next("hidden") == "shown" and U.Next("shown") == "off" and U.Next("off") == "on",
    "T2 the A cycle in the owner's order: active and visible > active and invisible > inactive but visible > disabled entirely > ...")
check(U.Next("on", "ancient_light") == "off" and U.Next("off", "ancient_light") == "on" and U.StateOf(true, 1, "ancient_light") == "on",
    "T2 question 16's default: Ancient Light (no model) only Active / Inactive")
do
    local want = { on = { 1, 0 }, hidden = { 1, 2 }, shown = { 0, 1 }, off = { 0, 0 } }
    local bad = {}
    for s, w in pairs(want) do
        local a, m = U.ConVarsOf(s)
        if a ~= w[1] or m ~= w[2] or U.StateOf(a == 1, m) ~= s then bad[#bad + 1] = s end
    end
    check(#bad == 0, "T2 the two ConVars of each state, and back (%s)", table.concat(bad, ", "))
    check(U.StateOf(true, 0) == "on" and U.StateOf(false, 0) == "off", "T2 model 0 (\"with the upgrade\", the default): the look follows the ability, as today")
end
-- every model ConVar has a control, defaults 0; Ancient Light has none (question 16's default, select 4.0 D-2: the name is built with "..", so the check is in the mock at run time)
do
    local bad, n = {}, 0
    for _, u in ipairs(GSA1.UPGRADES) do
        local cv = M.convars["gsa1_upgrade_model_" .. u.name]
        if U.NO_MODEL[u.name] then
            if cv ~= nil then bad[#bad + 1] = u.name .. " (made)" end
        elseif not (cv and cv:GetInt() == 0 and cv.lo == 0 and cv.hi == 2) then
            bad[#bad + 1] = u.name
        else
            n = n + 1
        end
    end
    check(#GSA1.UPGRADES == 17 and n == 16 and #bad == 0 and M.convars.gsa1_upgrade_model_ancient_light == nil,
        "T2 sixteen gsa1_upgrade_model_<name>, 0..2, default 0, and no gsa1_upgrade_model_ancient_light is ever made (%d; %s)", n, table.concat(bad, ", "))
    reset_all()
    U.SetState("ancient_light", "on")
    U.SetState("ancient_light", "off")
    RunConsoleCommand("gsa1_upgrade_models_reset")
    check(M.convars.gsa1_upgrade_model_ancient_light == nil and U.StateNow("ancient_light") == "off", "T2 Ancient Light's A, R / L and the reset write its ability only")
end

-- the game option for every combination of Sonic's three (0 while every model shows as the ability says)
do
    reset_all()
    local names = { "light_speed_shoes", "crystal_ring", "ancient_light" }
    local bad, n = 0, 0
    for _, s1 in ipairs(U.STATES) do
        for _, s2 in ipairs(U.STATES) do
            for _, s3 in ipairs({ "on", "off" }) do
                U.SetState(names[1], s1)
                U.SetState(names[2], s2)
                U.SetState(names[3], s3)
                local differs = (s1 == "hidden" or s1 == "shown" or s2 == "hidden" or s2 == "shown")
                local bits = 0
                if U.STATE[s1].visible then bits = bits + 0x2 end
                if U.STATE[s2].visible then bits = bits + 0x1 end
                local want = differs and (0x80000000 + bits) or 0
                n = n + 1
                if U.Value(0) ~= want or U.Value(8) ~= want then bad = bad + 1 end
            end
        end
    end
    check(n == 32 and bad == 0, "T2 the game option of every combination of Sonic's (%d, %d wrong): 0 = the game unless a model shows differently from its ability; Super Sonic (kind 8) the same", n, bad)
    reset_all()
    U.SetState("lure_1", "shown")
    check(U.Value(7) == 0x80000000 + 0x10000, "T2 Big: a lure shown without the upgrade: ON + 0x10000 (%X)", U.Value(7))
    reset_all()
end

-- Character Select's circle (r1-verify-s): its characters hold no upgrade (select 4.3.3), so they get ON + the bits marked VISIBLE, 0 only when none is; the sixteen pairs of Sonic's two
-- with a model, through U.ApplyFrontend with Design R's front end as the mock's module answers it
do
    reset_all()
    local saved = S.st
    S.st = { slot = 0, design = "R", skins = {}, state = { phase = 0 } }
    local bad, n, wrongs = 0, 0, {}
    for _, s1 in ipairs(U.STATES) do
        for _, s2 in ipairs(U.STATES) do
            U.SetState("light_speed_shoes", s1)
            U.SetState("crystal_ring", s2)
            local bits = (U.STATE[s1].visible and 0x2 or 0) + (U.STATE[s2].visible and 0x1 or 0)
            local want = bits ~= 0 and (0x80000000 + bits) or 0
            fe_up = {}
            U.ApplyFrontend()
            local got
            for _, f in ipairs(fe_up) do if f.kind == 0 then got = f.v end end
            n = n + 1
            if got ~= want or U.FrontendValue(0, U.Get) ~= want then
                bad = bad + 1
                wrongs[#wrongs + 1] = string.format("%s/%s: %s", s1, s2, tostring(got))
            end
        end
    end
    check(n == 16 and bad == 0, "T2 the circle's Sonic gets ON + the bits marked VISIBLE in all sixteen pairs of the shoes and the ring, 0 only when neither is (%d wrong: %s)", bad, table.concat(wrongs, "; "))
    -- the default of upgrades you have (active and visible, also what R sets): the character keeps the game (0), the circle wears them
    U.SetState("light_speed_shoes", "on")
    U.SetState("crystal_ring", "on")
    fe_up = {}
    U.ApplyFrontend()
    local fe0, fe2
    for _, f in ipairs(fe_up) do
        if f.kind == 0 then fe0 = f.v end
        if f.kind == 2 then fe2 = f.v end
    end
    check(U.Value(0) == 0 and fe0 == 0x80000003 and fe2 == 0, "T2 both on: Sonic's character gets 0 (the game), the circle's Sonic ON + 0x3, Tails' circle 0 (none of his is visible) (%s, %s)", tostring(fe0), tostring(fe2))
    -- active and invisible (the owner's checklist line): plain shoes in the circle at once
    U.SetState("light_speed_shoes", "hidden")
    fe_up = {}
    U.ApplyFrontend()
    fe0 = nil
    for _, f in ipairs(fe_up) do if f.kind == 0 then fe0 = f.v end end
    check(fe0 == 0x80000001, "T2 the shoes active and invisible: the circle's Sonic keeps the ring only (%s)", tostring(fe0))
    -- every kind the circle shows: its own list's visible bits (Big: a lure shown)
    reset_all()
    U.SetState("lure_2", "shown")
    U.SetState("life_belt", "on")
    check(U.FrontendValue(7, U.Get) == 0x80000000 + 0x20000 + 0x1000 and U.FrontendValue(5, U.Get) == 0 and U.FrontendValue(0, U.Get) == 0,
        "T2 Big's circle: ON + the lure and the belt; Amy and Sonic 0 (%X)", U.FrontendValue(7, U.Get))
    S.st = saved
    reset_all()
end

-- "visible" reaches the game at once on your character and its followers of that kind, never by a re-creation
do
    local recreates = 0
    local rec0 = GSA1.Recreate
    GSA1.Recreate = function(...) recreates = recreates + 1 return rec0(...) end
    GSA1.Spawn("sonic")
    M.frame(1 / 60)
    local C = GSA1.Char
    check(C and C.kind == 0, "a Sonic of yours")
    GSA1.Followers = GSA1.Followers or {}
    local saved = GSA1.Followers.list
    local F0, F2 = { id = 9001, kind = 0 }, { id = 9002, kind = 2 }
    GSA1.Followers.list = { F0, F2 }
    gopts = {}
    cvset("gsa1_upgrade_model_light_speed_shoes", 1)
    local mine, fol, other = nil, nil, nil
    for _, g in ipairs(gopts) do
        if g.id == C.id then mine = g end
        if g.id == 9001 then fol = g end
        if g.id == 9002 then other = g end
    end
    check(mine and mine.opt == 5 and mine.v == 0x80000002 and fol and fol.v == 0x80000002 and recreates == 0,
        "T2 the shoes \"always shown\" without the ability: gsa1.SetGameOption(id, 5, ON + 0x2) at once on Sonic and his Sonic follower, no re-creation (%s)", tostring(mine and mine.v))
    check(other and other.v == 0, "T2 Tails' follower: his own kind's value, the game (0)")
    gopts = {}
    cvset("gsa1_upgrade_model_light_speed_shoes", 0)
    check(gopts[1] and gopts[1].v == 0, "T2 back to \"with the upgrade\": 0, the game")
    GSA1.Followers.list = saved          -- (the two stand-ins are no real followers: the frames below would walk them)
    -- a new character takes it before its first tick
    cvset("gsa1_upgrade_model_crystal_ring", 1)
    GSA1.Remove(true)
    gopts = {}
    GSA1.Spawn("sonic")
    M.frame(1 / 60)
    local seen
    for _, g in ipairs(gopts) do if GSA1.Char and g.id == GSA1.Char.id then seen = g.v end end
    if seen == nil then info("calls after the spawn: %d; the character %s", #gopts, tostring(GSA1.Char and GSA1.Char.id)) for _, g in ipairs(gopts) do info("  %s %s %s", tostring(g.id), tostring(g.opt), tostring(g.v)) end end
    check(seen == 0x80000001, "T2 a character made later gets it at its creation (%s)", tostring(seen))
    cvset("gsa1_upgrade_model_crystal_ring", 0)
    -- "active" while Character Select is open: the re-creation waits, and runs after the close
    recreates = 0
    S.Open("test")
    check(S.IsOpen(), "Character Select open")
    cvset("gsa1_upgrade_light_speed_shoes", 1)
    for _ = 1, 40 do M.frame(1 / 60) end
    check(recreates == 0, "T2 \"active\" changed while Character Select is open: no re-creation behind it (%d)", recreates)
    S.Close("test")
    for _ = 1, 40 do M.frame(1 / 60) end
    check(recreates == 1, "T2 after the close: the waiting re-creation runs once (%d)", recreates)
    cvset("gsa1_upgrade_light_speed_shoes", 0)
    for _ = 1, 40 do M.frame(1 / 60) end
    GSA1.Recreate = rec0
end

-- R, L and A through the panel (Design S's pad), and the pick path untouched (RX.1)
do
    reset_all()
    local st = { slot = 0, design = "S", padWas = 0, stickWas = 0, skins = {} }
    check(U.PanelOpen(st, "test") == true and st.panel_up and #st.upList == 3, "T2 the panel opens on Sonic with his three")
    local p = S.PadFilter(st, S.PAD_RB, S.PAD_RB, 0, 0)
    local all = true
    for _, u in ipairs(st.upList) do all = all and U.StateNow(u.name) == "on" end
    check(all and p == 0, "T2 R (RB): every row active and visible; Design S's edges come back without the panel's buttons")
    S.PadFilter(st, S.PAD_LT, S.PAD_LT, 0, 0)
    all = true
    for _, u in ipairs(st.upList) do all = all and U.StateNow(u.name) == "off" end
    check(all, "T2 L (LT): every row disabled entirely")
    S.PadFilter(st, S.PAD_A, S.PAD_A, 0, 0)
    check(U.StateNow("light_speed_shoes") == "on", "T2 A: the selected row one step (off > on)")
    S.PadFilter(st, S.PAD_DOWN, S.PAD_DOWN, 0, 0)
    S.PadFilter(st, S.PAD_A, S.PAD_A, 0, 0)
    check(st.upSel == 2 and U.StateNow("crystal_ring") == "on", "T2 Down moves the selection, A steps that row")
    local q = S.PadFilter(st, S.PAD_START + S.PAD_A, S.PAD_START + S.PAD_A, 0, 0)
    check(q == S.PAD_START, "RX.1 Design S, the panel up: Start alone comes back (A taken out), so step_s's pick line picks")
    S.PadFilter(st, S.PAD_B, S.PAD_B, 0, 0)
    check(st.panelEnding == true, "T2 B closes the panel (the rest of this frame it stays up)")
    S.PadFilter(st, 0, 0, 0, 0)
    check(not st.panel_up, "T2 and the next frame it is gone; the screen stays")
    reset_all()
end

-- ---- T3: the layout, the pulse, the colours, whose upgrades ----------------------------------------------------------------------------------------------------------------------------------
do
    local function near(a, b) return math.abs(a - b) < 1e-6 end
    local p1, s1 = U.Layout(1)
    local p3, s3 = U.Layout(3)
    local p6, s6 = U.Layout(6)
    local p17, s17 = U.Layout(17)
    local p2, s2 = U.Layout(2)
    check(near(p1, 77.25) and near(s1, 1) and near(p2, 77.25) and near(p3, 77.25) and near(s3, 1), "T3 one to three rows: the mockup's own pitch 77.25 and size, never larger")
    check(near(p6, 236 / 6) and math.abs(s6 - 0.509) < 0.001 and near(p17, 236 / 17) and math.abs(s17 - 0.180) < 0.001,
        "T3 Big's six at %.3f (a name about %.1f game px tall), seventeen at %.3f", s6, 24.5 * s6, s17)
    local bad = 0
    for _, r in ipairs({ 0, 0x4000, 0x8000, 0xC000, 12345, 0x5B0 * 7 }) do
        if not near(U.Pulse(r), 0.1845 * (math.sin(r * math.pi * 2 / 65536) + 1) + 0.615) then bad = bad + 1 end
    end
    check(bad == 0 and math.abs(U.PulseScale(0x4000) - 0.984 / 0.7995) < 1e-6 and math.abs(U.PulseScale(0xC000) - 0.615 / 0.7995) < 1e-6,
        "T3 the pulse is the game's own name curve 0.1845 * (sin(ring) + 1) + 0.615, scaled about its mean: 0.77 .. 1.23")
    check(U.RING_STEP == 0x5B0 and math.floor(65536 / U.RING_STEP + 0.5) == 45, "T3 one pulse in 45 frames (0x5B0 a frame), 0.75 s")
    -- [14.1bl] [14.1bn] the owner's answers 18, 22 and 29 (rounds plan 14.1bl, 14.1bn): select 4.6.1's table, key by key, false only for Ancient Light (no model)
    local WANT = { light_speed_shoes = "F4FF00", crystal_ring = "0CC1A6", ancient_light = false, jet_anklet = "C0C0C0", rhythm_badge = "5C4CB6", shovel_claw = "C0C0C0",
        fighting_gloves = "ECBC10", warrior_feather = "5D87B6", long_hammer = "0ADF05", jet_booster = "C00202", laser_blaster = "C0C0C0", life_belt = "018601", power_rod = "ACD700",
        lure_1 = "D92D99", lure_2 = "4E5EF2", lure_3 = "4F6080", lure_4 = "CE8511" }
    local bad, n, extra = {}, 0, 0
    for _, u in ipairs(GSA1.UPGRADES) do
        n = n + 1
        if U.COLORS[u.name] ~= WANT[u.name] then bad[#bad + 1] = u.name .. "=" .. tostring(U.COLORS[u.name]) end
    end
    for k in pairs(U.COLORS) do
        if WANT[k] == nil then extra = extra + 1 end
    end
    check(n == 17 and #bad == 0 and extra == 0, "T3 [14.1bn] every name colour is select 4.6.1's as the owner's answers 22 and 29 changed it, all 17 by R1's keys (%s; %d other keys)", table.concat(bad, ", "), extra)
    -- false resolves at draw time to the slot's colour or the shown skin's char_color, never white; a colour of its own stays on a skin
    local K = GSA1.Skins
    local cases = {
        { "ancient_light", 0, nil, "0053FA" }, { "ancient_light", 6, nil, "F1F100" }, { "ancient_light", 0, K.SKINS.metalsonic, "3900B5" }, { "ancient_light", 0, K.SKINS.mechasonic, "FF8A1C" },
        { "ancient_light", nil, nil, "0053FA" }, { "long_hammer", 3, nil, "0ADF05" }, { "warrior_feather", 3, nil, "5D87B6" }, { "shovel_claw", 2, nil, "C0C0C0" },
        { "laser_blaster", 5, nil, "C0C0C0" }, { "jet_anklet", 1, nil, "C0C0C0" }, { "light_speed_shoes", 0, K.SKINS.mechasonic, "F4FF00" },
    }
    local wrong = {}
    for _, c in ipairs(cases) do
        local h = U.NameHex(c[1], c[2], c[3])
        local col = U.NameColor({ name = c[1] }, c[2], c[3])
        local r, g, b = U.RGB(c[4])
        if h ~= c[4] or not (col and col.r == r and col.g == g and col.b == b) then wrong[#wrong + 1] = c[1] .. "@" .. tostring(c[2]) .. "=" .. tostring(h) end
    end
    check(#wrong == 0, "T3 [14.1bn] U.NameHex and U.NameColor: Ancient Light in Sonic's blue, on Super Sonic's slot yellow, on Metal violet, on Mecha orange; the Long Hammer green, the Warrior Feather blue, the Claw, the Blaster and the Anklet silver; a skin keeps a colour of the upgrade's own (%s)",
        table.concat(wrong, ", "))
    local SLOT = { [0] = "0053FA", [1] = "F6C400", [2] = "F41000", [3] = "F985B7", [4] = "7331C7", [5] = "868686", [6] = "F1F100" }
    local sb = {}
    for slot = 0, 6 do
        local h = U.NameHex("ancient_light", slot, nil)
        if h ~= SLOT[slot] or h == "FFFFFF" then sb[#sb + 1] = slot .. "=" .. tostring(h) end
    end
    check(#sb == 0, "T3 false is the slot's character's colour on all seven slots (Sonic, Tails, Knuckles, Amy, Big, E-102, Super Sonic), never white (%s)", table.concat(sb, ", "))
    local st6 = { slot = 6 }
    local l6 = S.UpgradeList(st6)
    check(#l6 == 3 and l6[1].name == "light_speed_shoes", "T3 slot 6 (Super Sonic) lists Sonic's three")
    check(#S.UpgradeList({ slot = 4 }) == 6 and #S.UpgradeList({ slot = 1 }) == 2, "T3 Big six, Tails two (question 15's default: only the character's own)")
    cookies[GSA1.QUESTION_COOKIE] = 1
    GSA1.questionUnlocked = nil
    local saved = S.SLOT_ENTRY[6]
    S.SLOT_ENTRY[6] = "question"
    check(#S.UpgradeList({ slot = 6 }) == 0 and S.PanelAllowed({ slot = 6, design = "S" }) == false, "T3 the \"?\" has none: Y does nothing there")
    S.SLOT_ENTRY[6] = saved
end

-- the panel paints (no error) at both sizes; the rows fade in after the title; closing slides it out
do
    surface.SetFont = surface.SetFont or function() end
    surface.GetTextSize = surface.GetTextSize or function(s) return 10 * #tostring(s), 20 end
    draw.SimpleTextOutlined = draw.SimpleTextOutlined or function() end
    local st = { slot = 4, design = "S", padWas = 0, stickWas = 0, skins = {} }
    U.PanelOpen(st, "test")
    local m = S.Layout(1920, 1440, false, {})
    local ok, err = pcall(U.PanelPaint, st, m, 1920, 1440)
    check(ok, "T3 the panel paints with Big's six (%s)", tostring(err))
    U.PanelClose(st, "test")
    S.PadFilter(st, 0, 0, 0, 0)
    ok, err = pcall(U.PanelPaint, st, m, 1920, 1440)
    check(ok and st.panelFade ~= nil, "T3 closing: it slides out (%s)", tostring(err))
end

-- the options' page: the block with every model combo and the button
do
    local seen, buttons = {}, {}
    local panel = setmetatable({}, { __index = function(t, k)
        return function(self, a, b)
            if k == "ComboBox" then
                seen[b] = a
                return { AddChoice = function() end }
            end
            if k == "Button" then buttons[b] = a end
            return setmetatable({}, { __index = function() return function() end end })
        end
    end })
    U.BuildOptions(panel)
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    check(n == 16 and seen.gsa1_upgrade_model_ancient_light == nil and buttons.gsa1_upgrade_models_reset ~= nil, "T10 the Upgrade models block: 16 combos (Ancient Light has no model), the reset button (%d)", n)
    cvset("gsa1_upgrade_model_power_rod", 2)
    RunConsoleCommand("gsa1_upgrade_models_reset")
    check(M.convars.gsa1_upgrade_model_power_rod:GetInt() == 0, "T10 \"Every model with its upgrade\" sets them back to 0")
end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
