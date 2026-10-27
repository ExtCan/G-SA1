-- G-SA1 client: quick test tools (2026-10-25, the owner's requests "add a command to add a player message for easy in-game
-- notes" and "add a command that will set the ring amount"). Q -> Options -> G-SA1 -> Debug (0.9.3a: the owner's
-- "rename the Notes and Tools tab to 'Debug'"; the page id stays "tools", so no setting changes).
--   * Notes for the session log (garrysmod/data/gsa1/log.txt, which Claude reads after a test): a "note" line with the text
--     and what was happening at that moment (the same context as gsa1_log_mark):
--       gsa1_note <text>              in the console (bind a key: bind f8 "gsa1_note stuck in a fence")
--       !note <text> or /note <text>  in chat (the chat line itself is not shown)
--       gsa1_note_popup               a small box to type the note in; the moment is taken when the box opens.
--                                     The page's key (gsa1_note_key) opens it too.
--   * Rings: gsa1_rings <n> sets the character's ring count (0..999), gsa1_rings_add <n> adds (a negative n takes rings).
--     Both go through the game's own ring counter (gsa1.AddRings, round 5), so passing 100 gives the game's 1-up as in the
--     game. Allowed in single player, with sv_cheats 1, for an admin or the listen server's host (0.9.2a: one rule with
--     "Give rings", feat/sh_giverings.lua; in multiplayer the server checks it too).
GSA1 = GSA1 or {}

local T = GSA1.Tools or {}
GSA1.Tools = T
T.RINGS_MAX = 999

local cv_key = GSA1.ConVar("gsa1_note_key", 0, "A key that opens the box for a note in the session log (0 = none; set "
    .. "it on the Debug page)", 0, 1024)

local function say(...)
    if chat and chat.AddText then
        chat.AddText(Color(80, 160, 255), "[G-SA1] ", color_white, ...)
    else
        MsgC(Color(80, 160, 255), "[G-SA1] ", color_white, table.concat({ ... }), "\n")
    end
end

local function log_on()
    local cv = GetConVar("gsa1_log")
    return GSA1.Log ~= nil and (cv == nil or cv:GetBool())
end

-- writes the note; ctx = the moment's context (taken when a note box opened), else now
function T.Note(text, ctx)
    text = string.Trim(tostring(text or ""))
    if text == "" then
        say("write something after the command, e.g. gsa1_note the camera went through the wall here")
        return false
    end
    if not log_on() then
        say("the session log is off: tick 'Keep a session log' (Options > G-SA1 > Disc and status)")
        return false
    end
    ctx = ctx or (GSA1.LogContext and GSA1.LogContext()) or ""
    GSA1.Log("note", "%s%s", text, ctx ~= "" and ("; " .. ctx) or "")
    if GSA1.LogFlush then GSA1.LogFlush() end
    say("note saved in the session log")
    return true
end

concommand.Add("gsa1_note", function(ply, cmd, args, argstr) T.Note(argstr) end, nil,
    "G-SA1: write a note into the session log (garrysmod/data/gsa1/log.txt) with what is happening right now")

-- chat: "!note <text>" or "/note <text>" (only your own lines; the line is not shown in chat)
hook.Add("OnPlayerChat", "gsa1_note", function(ply, text)
    if ply ~= LocalPlayer() or type(text) ~= "string" then return end
    local body = string.match(text, "^[!/][Nn][Oo][Tt][Ee]%s+(.+)$")
    if body == nil and string.match(text, "^[!/][Nn][Oo][Tt][Ee]%s*$") then body = "" end
    if body == nil then return end
    T.Note(body)
    return true
end)

-- the note box: the moment is taken when it opens, so typing takes as long as it needs
function T.Popup()
    if IsValid(T.frame) then
        T.frame:MakePopup()
        return
    end
    local ctx = GSA1.LogContext and GSA1.LogContext() or ""
    local f = vgui.Create("DFrame")
    f:SetTitle("G-SA1: a note for the session log")
    f:SetSize(520, 96)
    f:Center()
    f:MakePopup()
    local e = vgui.Create("DTextEntry", f)
    e:Dock(TOP)
    e:SetTall(26)
    if e.SetPlaceholderText then e:SetPlaceholderText("What happened? (Enter saves, Esc or the X closes)") end
    local function save()
        if T.Note(e:GetValue(), ctx) then f:Close() end
    end
    e.OnEnter = save
    local b = vgui.Create("DButton", f)
    b:Dock(BOTTOM)
    b:SetText("Save the note")
    b.DoClick = save
    e:RequestFocus()
    T.frame = f
end
concommand.Add("gsa1_note_popup", function() T.Popup() end, nil, "G-SA1: open a box to type a note for the session log")

-- the note key (gsa1_note_key): opens the box when pressed outside menus and chat
hook.Add("Think", "gsa1_note_key", function()
    local k = cv_key:GetInt()
    if k <= 0 then
        T.keyDown = false
        return
    end
    local ply = LocalPlayer()
    local busy = vgui.CursorVisible() or gui.IsGameUIVisible() or (IsValid(ply) and ply.IsTyping ~= nil and ply:IsTyping())
    local down = (not busy) and input.IsButtonDown(k) or false
    if down and not T.keyDown then T.Popup() end
    T.keyDown = down
end)

-- rings -------------------------------------------------------------------------------------------------------------------
local function rings_allowed()
    if GSA1.RingsAllowed then return GSA1.RingsAllowed() end
    if game.SinglePlayer() then return true end
    local sc = GetConVar("sv_cheats")
    if sc and sc:GetBool() then return true end
    local ply = LocalPlayer()
    return IsValid(ply) and ply:IsAdmin()
end

-- sets (add = false) or adds to (add = true) the character's rings through the game's own ring counter
function T.SetRings(n, add)
    local C = GSA1.Char
    if not C or not C.id then
        say("no character: spawn one first")
        return false
    end
    if not (gsa1 and gsa1.AddRings and gsa1.StateEx) then
        say("setting rings needs the G-SA1 module 0.9.0 or newer")
        return false
    end
    if not rings_allowed() then
        say("setting rings needs single player, sv_cheats 1, an admin or the server's host")
        return false
    end
    n = tonumber(n)
    if not n then
        say(add and "how many? e.g. gsa1_rings_add 10" or "how many? e.g. gsa1_rings 50")
        return false
    end
    T.st = T.st or {}
    local st = gsa1.StateEx(C.id, T.st)
    local cur = st and tonumber(st.rings)
    if not cur then
        say("the character's ring count is not available yet")
        return false
    end
    n = math.floor(n)
    local function apply()
        local CC = GSA1.Char
        if not CC or not CC.id then return false end
        local st2 = gsa1.StateEx(CC.id, T.st)
        local now = st2 and tonumber(st2.rings) or cur
        local target = math.Clamp(add and (now + n) or n, 0, T.RINGS_MAX)
        local delta = target - now
        while delta ~= 0 do
            local step = math.Clamp(delta, -1000, 1000)
            local ok, msg = gsa1.AddRings(CC.id, step)
            if not ok then
                say("could not change the rings: ", tostring(msg))
                return false
            end
            delta = delta - step
        end
        if log_on() then GSA1.Log("note", "rings set to %d (were %d) from the console", target, now) end
        say(string.format("rings: %d", target))
        return true
    end
    -- multiplayer: the server checks the same rule first (feat/sh_giverings.lua)
    if GSA1.RingsRequest then return GSA1.RingsRequest(add and "gsa1_rings_add" or "gsa1_rings", n, apply) end
    return apply()
end
concommand.Add("gsa1_rings", function(ply, cmd, args) T.SetRings(args[1], false) end, nil,
    "G-SA1: set your character's rings, e.g. gsa1_rings 50 (0..999; the game's own counter: 100 gives a 1-up)")
concommand.Add("gsa1_rings_add", function(ply, cmd, args) T.SetRings(args[1], true) end, nil,
    "G-SA1: add rings to your character, e.g. gsa1_rings_add 10 (a negative number takes rings)")

-- update notice (2026-10-25, the owner's request "do a Windows notification when you're ready for installing the next
-- update": Windows hides its notifications while a full-screen game runs, so G-SA1 says it in the game too). Claude's release
-- step writes garrysmod/data/gsa1/update_ready.txt (one line, e.g. "G-SA1 0.9.2 is ready: close Garry's Mod to install it")
-- and the installer deletes it. Checked every 20 s; each new text is shown once (a notice and a chat line).
T.UPDATE_FILE = "gsa1/update_ready.txt"
local function check_update()
    if not file.Exists(T.UPDATE_FILE, "DATA") then return end
    local text = string.Trim(file.Read(T.UPDATE_FILE, "DATA") or "")
    if text == "" or text == T.updateShown then return end
    T.updateShown = text
    if notification and notification.AddLegacy then
        notification.AddLegacy(text, NOTIFY_GENERIC or 0, 15)
    end
    if surface and surface.PlaySound then surface.PlaySound("buttons/button15.wav") end
    say(text)
    if log_on() then GSA1.Log("msg", "update notice: %s", text) end
end
timer.Create("gsa1_update_notice", 20, 0, function()
    local ok, err = pcall(check_update)
    if not ok and log_on() then GSA1.Log("error", "update notice: %s", tostring(err)) end
end)

-- the page ----------------------------------------------------------------------------------------------------------------
GSA1.AddMenuPage(900, "tools", "Debug", function(panel)
    panel:Help("Notes go into the session log (garrysmod/data/gsa1/log.txt) together with what was happening at that "
        .. "moment, so they can be read after a test.")
    local entry = panel:TextEntry("Note")
    local write = panel:Button("Write this note")
    write.DoClick = function()
        if IsValid(entry) and T.Note(entry:GetValue()) then entry:SetValue("") end
    end
    panel:ControlHelp("Faster during play: chat !note <text> (or /note <text>), the console gsa1_note <text>, or the key "
        .. "below, which opens a small note box (the moment is taken when the box opens).")
    panel:Help("Note box key:")
    local binder = vgui.Create("DBinder", panel)
    if binder.SetConVar then binder:SetConVar("gsa1_note_key") end
    binder:SetTall(28)
    panel:AddItem(binder)
    panel:Button("No note key", "gsa1_note_key", "0")
    panel:Help("Rings (single player, sv_cheats 1, an admin or the server's host; the game's own counter, so passing 100 "
        .. "gives a 1-up):")
    local slider = panel:NumSlider("Rings", nil, 0, T.RINGS_MAX, 0)
    if IsValid(slider) then slider:SetValue(50) end
    local set = panel:Button("Set my character's rings")
    set.DoClick = function()
        if IsValid(slider) then T.SetRings(math.floor(slider:GetValue() + 0.5), false) end
    end
    panel:ControlHelp("Console: gsa1_rings <n> sets them, gsa1_rings_add <n> adds (a negative n takes rings).")
end)
