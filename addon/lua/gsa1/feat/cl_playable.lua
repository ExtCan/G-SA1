-- G-SA1 Dr. Eggman and Tikal (round 0.9.9; sadc docs/research/gsa1_099_plan.md 4.1 B8, B9, 5.5, 5.6, 5.9; playable099.md 2.4, 3.3, 4.3, 6). They
-- run as the game's code leaves them: nothing here repairs a move, a hurt state, a pose or a drown. This file is their debug button, the
-- Dreamcast's X: libsa1's SA1_BUTTON_X (gsa1.BUTTON_X), sent for kinds 1 and 4 only, never for anyone else. The stick then moves them with
-- no ground and no gravity, held with the stick forward or back they fly up or down, jump leaves it, action goes back to the spawn point
-- (on a Dreamcast that press is an address error; a world's standing stub queues the respawn: plan 4.2 D1). A second press does nothing.
-- The key defaults to H (18; the plan's addendum A3: free in the owner's config.cfg, and the Dreamcast's X is voice chat there), the controller to
-- Y: the pad's X sends action in G-SA1's map (src/core/pad.hpp), and in debug mode action is the respawn.
-- This file loads before feat/cl_super.lua and feat/cl_wheel.lua: both chain over it (Wheel, Super, Playable, Board; each passes the bit on).
GSA1 = GSA1 or {}
local P = GSA1.Playable or {}
GSA1.Playable = P
local band, bor = bit.band, bit.bor

P.DEBUG_KINDS = { [1] = true, [4] = true }

local cv = {
    on  = GSA1.ConVar("gsa1_debug_button", 1, "Eggman and Tikal: the game's debug button (free movement; 0 = the button does nothing)", 0, 1),
    key = GSA1.ConVar("gsa1_debug_key", 18, "Eggman and Tikal: the debug button's key (a key code; 18 = H; 0 = none)", 0, 511),
    pad = GSA1.ConVar("gsa1_debug_pad", 0x8000, "Eggman and Tikal: the debug button on the controller (XInput bits as gsa1_super_pad; "
        .. "32768 = Y; 0 = none)", 0, 0x30000),
}
P.cv = cv

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("settings", fmt, ...) end
end

-- a menu, the chat or a panel has the input (a copy of feat/cl_super.lua S.InputBusy: that file loads later)
function P.InputBusy()
    if GSA1.InputBlocked and GSA1.InputBlocked() then return true end
    if vgui.CursorVisible() or gui.IsGameUIVisible() then return true end
    local ply = LocalPlayer()
    return IsValid(ply) and ply.IsTyping ~= nil and ply:IsTyping() == true
end

-- the key or the controller button is down now
function P.DebugDown()
    if P.InputBusy() then return false end
    local k = cv.key:GetInt()
    if k > 0 and input and input.IsButtonDown and input.IsButtonDown(k) then return true end
    local b = cv.pad:GetInt()
    local p = GSA1.pad
    if b > 0 and p and p.connected and band(tonumber(p.raw) or 0, b) ~= 0 then return true end
    return false
end

-- the player's own buttons for this tick (cl_character.lua's seam): the bit only for kinds 1 and 4, with the option on
P.prevFilter = P.prevFilter or GSA1.FilterButtons
GSA1.FilterButtons = function(C, buttons)
    if P.prevFilter then buttons = P.prevFilter(C, buttons) end
    if C and P.DEBUG_KINDS[C.kind] and gsa1.BUTTON_X and cv.on:GetBool() and P.DebugDown() then
        buttons = bor(buttons, gsa1.BUTTON_X)
    end
    return buttons
end

for _, name in ipairs({ "gsa1_debug_button", "gsa1_debug_key", "gsa1_debug_pad" }) do
    cvars.AddChangeCallback(name, function(_, _, new) log("%s = %s", name, tostring(new)) end, "gsa1_playable")
end

-- the key's name ("X", "none")
function P.KeyName()
    local k = cv.key:GetInt()
    if k <= 0 then return "none" end
    local name = input and input.GetKeyName and input.GetKeyName(k)
    return string.upper(tostring(name or k))
end
-- the controller button's name
function P.PadName()
    local b = cv.pad:GetInt()
    local S = GSA1.Super
    if S and S.PadTitle then return S.PadTitle(b) end
    return b == 0 and "None" or string.format("button 0x%X", b)
end

-- the session log: what the button is for a character that has one
hook.Add("GSA1CharacterCreated", "gsa1_playable", function(C, how)
    if not (C and P.DEBUG_KINDS[C.kind]) then return end
    if GSA1.Log then
        GSA1.Log("playable", "%s %s: the game's own code, nothing repaired; debug button %s (key %s, controller %s)", C.title or "?",
            how or "created", (gsa1.BUTTON_X and cv.on:GetBool()) and "on" or "off", P.KeyName(), P.PadName())
    end
end)

-- the page's lines
P.REASONS = "Dr. Eggman and Tikal have no emotes, faces, head look or boards. They can be followers and a follower can follow them (the Followers page says what they do). With no "
    .. "emote wheel, call your followers back with the button on the Followers page."
function P.StatusLines()
    local out = { P.REASONS }
    if not (gsa1 and gsa1.BUTTON_X) then
        out[#out + 1] = "The debug button: this module or libsa1 has none (G-SA1 module 0.9.9 or newer)"
    elseif not cv.on:GetBool() then
        out[#out + 1] = "The debug button is off"
    else
        out[#out + 1] = string.format("The debug button: the key %s, the controller's %s", P.KeyName(), P.PadName())
    end
    return out
end

-- a combo box for a ConVar whose values have titles ({ value, title }): it follows the ConVar (the pattern of cl_super.lua's choice_combo)
local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    local now = tonumber(GetConVar(cvname) and GetConVar(cvname):GetString() or "")
    for _, c in ipairs(choices) do combo:AddChoice(c[2], tostring(c[1]), now ~= nil and tonumber(c[1]) == now) end
    combo.OnSelect = function(_, _, _, data) RunConsoleCommand(cvname, tostring(data)) end
    return combo
end

-- a label that refreshes itself twice a second while visible (the pattern of cl_super.lua's live_label)
local function live_label(panel, lines_fn)
    local lbl = panel:Help(table.concat(lines_fn(), "\n"))
    if not lbl then return nil end
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + 0.5
        local text = table.concat(lines_fn(), "\n")
        if text ~= self.gsa1Text then
            self.gsa1Text = text
            self:SetText(text)
            self:InvalidateLayout(true)
            local parent = self:GetParent()
            if IsValid(parent) then parent:InvalidateLayout() end
        end
    end
    return lbl
end

-- the Character page's rows (the owner's rule: every option on the Q menu)
function P.BuildOptions(panel)
    panel:Help("Dr. Eggman and Tikal")
    panel:ControlHelp("As broken as the game's code is, nothing repaired: a hit does nothing; when the air runs out they just stand there, "
        .. "with no pose and no voice, until the game asks for its restart about 4 seconds later; Eggman has no jump pose and no action, Tikal "
        .. "uses one run motion for everything, their lives icon is Sonic's.")
    panel:CheckBox("Eggman and Tikal: the game's debug button", "gsa1_debug_button")
    panel:ControlHelp("As on the Dreamcast: free movement. Press it, then the stick moves them (no ground, no gravity), hold it with the "
        .. "stick forward or back to go up or down, jump ends it, action goes back to your spawn point (on a real Dreamcast that button "
        .. "crashes the game).")
    panel:Help("Debug button key (now: " .. P.KeyName() .. ")")
    local binder = vgui.Create("DBinder", panel)
    if binder.SetConVar then binder:SetConVar("gsa1_debug_key") end
    if binder.SetTall then binder:SetTall(28) end
    panel:AddItem(binder)
    panel:Button("No key", "gsa1_debug_key", "0")
    local S = GSA1.Super
    choice_combo(panel, "Debug button on the controller", "gsa1_debug_pad", S and S.PAD_BUTTONS or { { 0, "None" }, { 0x8000, "Y" } })
    panel:ControlHelp("X sends the action button on your controller, so it is not the default")
    live_label(panel, P.StatusLines)
    if GSA1.Question and GSA1.Question.BuildOptions and GSA1.QuestionUnlocked() then GSA1.Question.BuildOptions(panel) end
end
if GSA1.AddCharacterOption then GSA1.AddCharacterOption(175, "playable", P.BuildOptions) end
