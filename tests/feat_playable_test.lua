-- feat_playable_test.lua - Dr. Eggman and Tikal, the addon's side (round 0.9.9; sadc docs/research/gsa1_099_plan.md 5.6, 5.9, 5.10, 6.5 with its review
-- R99.6, R99.7; playable099.md 4, 6, 7.4): sh_config.lua's entries, feat/cl_playable.lua's debug button, cl_character.lua's airEndsNothing.
-- THE REAL PATH (review R99.7): the whole addon through its autorun on tests/lua_mock.lua in Garry's Mod's own LuaJIT, so the real chain of
-- GSA1.FilterButtons (Wheel, Super, Playable, Board) and cl_character.lua's real Think: the key's input.IsButtonDown or the controller's
-- GSA1.pad.raw down must reach the module's Tick (M.ticks.last.buttons). The module's own mask is proved by behaviour in
-- tests/feat_playable_binding_test.cpp (mode 11 / 17 through the real module). The plan's addendum A3: the key is H, nothing touches voice chat.
--   lua_host tests/feat_playable_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_playable_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- the mock module: the whole addon runs on it; the events and the pad are the test's
GSA1 = nil
local G = M.module({ speed = 300 })
local R = { queue = {}, pad = nil }
local pool = {}
function G.PollEvents(out)
    out = out or {}
    local n = 0
    for _, q in ipairs(R.queue) do
        n = n + 1
        local e = pool[n] or {}
        pool[n] = e
        e.type, e.id, e.bank, e.x, e.y, e.z, e.arg, e.step, e.character = q.type, q.id or 0, 0, 0, 0, 0, q.arg or 0, 0, (GSA1.Char and GSA1.Char.id) or 1
        out[n] = e
    end
    out[n + 1] = nil
    out.count = n
    R.queue = {}
    return out
end
function G.PadPoll(dt, paused, out)
    out = out or {}
    out.connected, out.active, out.raw, out.buttons, out.sx, out.sy = R.pad ~= nil, false, R.pad or 0, 0, 0, 0
    out.yaw, out.pitch, out.reset, out.lx, out.ly, out.rx, out.ry, out.cx, out.cy, out.lt, out.rt = 0, 0, false, 0, 0, 0, 0, 0, 0, 0, 0
    return out
end
-- the GMod parts lua_mock.lua does not have
local keys = {}
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    GetKeyName = function(code) return code == 18 and "h" or ("key" .. tostring(code)) end,
}
M.player.IsTyping = function() return M.typing == true end
local cursor = false
vgui.CursorVisible = function() return cursor end
util.NetworkStringToID = function() return 1 end

local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local P = GSA1 and GSA1.Playable
check(ok_load and #ferr == 0 and P ~= nil, "the addon loads, with feat/cl_playable.lua (%s)", tostring(err_load or ferr[1] or "ok"))
if not (ok_load and P) then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
local X = 0x40
local function frames(n, dt) for _ = 1, n do M.frame(dt or 1 / 60) end end
local function has_x() return M.ticks.last ~= nil and bit.band(M.ticks.last.buttons or 0, X) ~= 0 end
local function log_has(pat)
    GSA1.LogFlush()
    return string.find(M.files["gsa1/log.txt"] or "", pat) ~= nil
end
local function setcv(name, v) GetConVar(name):SetString(tostring(v)) end

RunConsoleCommand("iwonderwhotheseventhcharacteris")   -- (0.9.9e: the "?" is an unlockable: tests/feat_unlock_test.lua; this test wants it)
-- 1. the entries -------------------------------------------------------------------------------------------------------------------
local ke, de = GSA1.KindByName("eggman")
local kt, dt = GSA1.KindByName("tikal")
check(ke == 1 and de.title == "Dr. Eggman" and de.nowheel == true and de.airEndsNothing == true and not de.form and
    kt == 4 and dt.title == "Tikal" and dt.nowheel == true and dt.airEndsNothing == true and not dt.form,
    "the list: \"Dr. Eggman\" (kind 1) and \"Tikal\" (kind 4), no wheel, the air timer's end kept")
local order = {}
for i, c in ipairs(GSA1.CHARACTERS) do order[c.name] = i end
check(#GSA1.CHARACTERS == 13 and order.eggman == order.big + 1 and order.tikal == order.big + 2 and order.supersonic == order.big + 3 and
    order.question == 13, "after Big, before the Super Sonics; \"?\" last (%d entries)", #GSA1.CHARACTERS)
check(GSA1.CharacterByKind(1) == de and GSA1.CharacterByKind(4) == dt and GSA1.CharacterByName("1") == de and GSA1.CharacterByName("4") == dt and
    GSA1.CharacterByKind(0).name == "sonic" and GSA1.CharacterByKind(8).name == "supersonic" and GSA1.CharacterByName("8").name == "supersonic" and
    GSA1.CharacterByName("0").name == "sonic", "by kind and by number: 1 and 4 are theirs; 8 stays Super Sonic and 0 Sonic")
check(GSA1.CHAR_SIZE[1].radius == 34 and GSA1.CHAR_SIZE[1].height == 72 and GSA1.CHAR_SIZE[4].radius == 16 and GSA1.CHAR_SIZE[4].center == 20,
    "GSA1.CHAR_SIZE has their rows (feat_interact_size_binding_test compares them with the disc)")
check(#GSA1.UpgradesOf(1) == 0 and #GSA1.UpgradesOf(4) == 0, "they have no upgrades")
check(GetConVar("gsa1_debug_button"):GetInt() == 1 and GetConVar("gsa1_debug_key"):GetInt() == 18 and GetConVar("gsa1_debug_pad"):GetInt() == 0x8000,
    "the defaults (5.9, the plan's addendum A3): the button on, the key H (18), the controller's Y (0x8000)")

-- 2. the debug button, the whole chain ---------------------------------------------------------------------------------------------
local function play(name)
    GSA1.Spawn(name)
    frames(3)
    return GSA1.Char
end
local function pressed(n)
    keys[18] = true
    frames(n or 3)
    local v = has_x()
    keys[18] = false
    return v
end
local C = play("tikal")
check(C ~= nil and C.kind == 4 and C.def == dt, "Tikal comes up")
frames(2)
check(not has_x(), "Tikal, nothing pressed: no bit")
check(pressed(), "Tikal, the key down: the tick's buttons hold 0x40 through Wheel, Super, Playable, Board (buttons %s)", tostring(M.ticks.last.buttons))
frames(2)
check(not has_x(), "the key up: the bit is gone")
R.pad = 0x8000
frames(3)
check(has_x(), "Tikal, the controller's Y (GSA1.pad.raw 0x8000): the bit")
R.pad = 0x4000
frames(3)
check(not has_x(), "Tikal, the controller's X: no bit (X sends action: the reason Y is the default)")
R.pad = nil
frames(2)
-- what stops it
setcv("gsa1_debug_button", 0)
check(not pressed(), "gsa1_debug_button 0: no bit")
setcv("gsa1_debug_button", 1)
local blocked = GSA1.InputBlocked
GSA1.InputBlocked = function() return true end
check(not pressed(), "an InputBlocked panel: no bit")
GSA1.InputBlocked = blocked
cursor = true
check(not pressed(), "the cursor up: no bit")
cursor = false
M.ui = true
check(not pressed(), "the game's menu: no bit")
M.ui = false
M.typing = true
check(not pressed(), "typing: no bit")
M.typing = false
check(pressed(), "and after all of those the key works again")
-- another key, no key, no controller button
setcv("gsa1_debug_key", 25)
check(not pressed(), "gsa1_debug_key 25: H no longer does it")
keys[25] = true
frames(3)
check(has_x(), "the new key does")
keys[25] = false
setcv("gsa1_debug_key", 0)
keys[0] = true
frames(3)
check(not has_x(), "gsa1_debug_key 0: no key")
keys[0] = nil
setcv("gsa1_debug_key", 18)
setcv("gsa1_debug_pad", 0)
R.pad = 0x8000
frames(3)
check(not has_x(), "gsa1_debug_pad 0: no controller button")
R.pad = nil
setcv("gsa1_debug_pad", 0x8000)
-- Eggman, as Tikal
C = play("eggman")
check(C ~= nil and C.kind == 1 and C.def == de and pressed(), "Dr. Eggman comes up; the key down: the bit")
-- nobody else
for _, name in ipairs({ "sonic", "supersonic", "supersonic_general", "question", "tails", "knuckles", "amy", "gamma", "big" }) do
    C = play(name)
    local k = pressed()
    R.pad = 0x8000
    frames(3)
    local p = has_x()
    R.pad = nil
    frames(2)
    check(C ~= nil and not k and not p, "%s: the key and the controller's Y down: no 0x40", tostring(C and C.title))
end
-- an old module with no BUTTON_X: no error, no bit
C = play("tikal")
local bx = G.BUTTON_X
G.BUTTON_X = nil
check(not pressed(), "a module with no gsa1.BUTTON_X: no bit, no error")
G.BUTTON_X = bx

-- 4. D12: the air timer's end (review R99.6) -----------------------------------------------------------------------------------------
local EV = GSA1.EV
local function event(t, arg, id)
    R.queue[#R.queue + 1] = { type = t, arg = arg, id = id }
    frames(2)
end
C = play("tikal")
local before = #M.creates
event(EV.DEATH, 3)
check(C.death == nil and C.fallbackAt == nil and GSA1.Char == C, "Tikal, SA1_EVENT_DEATH cause 3: no C.death, no fallback")
check(log_has("the air ran out"), "one game log line says so")
frames(7 * 60)
check(GSA1.Char == C and #M.creates == before, "no respawn 7 s later")
-- the game's own restart request, 240 steps after it (MEASURED by libsa1's playable_test P5b): as for anyone
event(EV.RESTART, 0, 2)
check(C.restartAt ~= nil and C.respawnAt ~= nil, "the game's own restart request: answered as for anyone (no mask)")
frames(90)
check(GSA1.Char ~= C and #M.creates == before + 1 and GSA1.Char.def == dt, "it comes back as Tikal 1 s later")
C = GSA1.Char
before = #M.creates
event(EV.DEATH, 2)
check(C.death ~= nil and C.death.cause == 2 and C.fallbackAt ~= nil, "Tikal, cause 2 (killed): as anyone: C.death, a fallback")
frames(7 * 60)
check(GSA1.Char ~= C and #M.creates == before + 1, "... and the respawn")
C = play("eggman")
event(EV.DEATH, 3)
check(C.death == nil and C.fallbackAt == nil, "Dr. Eggman, cause 3: the same")
C = play("sonic")
before = #M.creates
event(EV.DEATH, 3)
check(C.death ~= nil and C.death.cause == 3 and C.fallbackAt ~= nil, "Sonic, cause 3: as today: he drowned")
frames(7 * 60)
check(GSA1.Char ~= C and #M.creates == before + 1, "... and his respawn")

-- 5. what they do not have -----------------------------------------------------------------------------------------------------------
local W, F, B = GSA1.Wheel, GSA1.Faces, GSA1.Board
C = play("tikal")
W.Open(C, "test")
check(not W.open and W.toastText == "Tikal has no emotes", "the wheel refuses: \"%s\"", tostring(W.toastText))
check(W.PlayBody(C, { body = "a1", name = "x" }, 1, 1, "test") == false, "W.PlayBody refuses")
local ents_ = {}
for _, c in ipairs(W.Entries()) do ents_[c.name] = true end
check(not ents_.eggman and not ents_.tikal and not ents_.question and ents_.sonic and ents_.big and ents_.supersonic and ents_.supersonic_general,
    "W.Entries leaves them and \"?\" out")
check(W.CurrentEntry() ~= "tikal", "the Emote wheel page does not open on Tikal: %s", tostring(W.CurrentEntry()))
check(F.NoFaceText("eggman") == "Eggman has no face in the game" and F.NoFaceText("tikal") == "Tikal's cutscene face is not wired up" and
    not F.HasFaces("eggman") and not F.HasFaces("tikal"), "the Faces page's words")
local can, why = B.CanBoard(C, true)
check(can == false and why == "only Sonic and Tails ride a board", "no board: \"%s\"", tostring(why))

-- 6. the Character page: every row of 5.9 that is this lane's -------------------------------------------------------------------------
do
    local made, METHODS = {}, nil
    local function standin(kind)
        local Pn = { kind = kind, calls = {} }
        made[#made + 1] = Pn
        return setmetatable(Pn, { __index = function(t, k)
            if METHODS[k] then return METHODS[k] end
            if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
            return function(self, ...)
                t.calls[#t.calls + 1] = { k, ... }
                local child = standin(k)
                child.args = { ... }
                return child
            end
        end })
    end
    METHODS = { SetText = function(self, s) self.text = s end, SetConVar = function(self, c) self.convar = c end }
    vgui.Create = function(cls) return standin(cls) end
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    local entry
    for _, e in ipairs(M.menu) do
        if e.class == "gsa1_character" then entry = e end
    end
    check(entry ~= nil, "the Character page")
    local cok, cerr = pcall(entry.cpanel, standin("DForm"))
    check(cok, "the page builds (%s)", tostring(cerr or "ok"))
    local boxes, sliders, helps, combos, buttons, binder = {}, {}, {}, {}, {}, nil
    for _, Pn in ipairs(made) do
        if Pn.kind == "DBinder" and Pn.convar == "gsa1_debug_key" then binder = Pn end
        for _, c in ipairs(Pn.calls) do
            if c[1] == "CheckBox" then boxes[c[3]] = c[2] end
            if c[1] == "NumSlider" then sliders[c[3]] = { c[2], c[4], c[5], c[6] } end
            if c[1] == "ControlHelp" or c[1] == "Help" then helps[#helps + 1] = tostring(c[2]) end
            if c[1] == "ComboBox" then combos[c[2]] = true end
            if c[1] == "Button" then buttons[c[2]] = c[3] end
        end
    end
    local all = table.concat(helps, " ")
    check(boxes.gsa1_debug_button == "Eggman and Tikal: the game's debug button", "the check box gsa1_debug_button")
    check(string.find(all, "action goes back to your spawn point (on a real Dreamcast that button crashes the game)", 1, true) ~= nil, "its help")
    check(binder ~= nil and buttons["No key"] == "gsa1_debug_key", "the key: a DBinder and \"No key\"")
    check(string.find(all, "voice chat", 1, true) == nil, "no word about voice chat (the plan's addendum A3)")
    check(combos["Debug button on the controller"] and string.find(all, "X sends the action button on your controller", 1, true) ~= nil, "the controller's combo and its help")
    check(string.find(all, "They can be followers and a follower can follow them", 1, true) ~= nil, "the status line (%s)", tostring(P.StatusLines()[2]))
    check(string.find(all, "the button on the Followers page", 1, true) ~= nil, "no wheel: the call-back's way is said (review R99.18)")
    local quick = 0
    for _, Pn in ipairs(made) do
        for _, c in ipairs(Pn.calls) do
            if c[1] == "Button" and c[3] == "gsa1_spawn" and (c[4] == "eggman" or c[4] == "tikal" or c[4] == "question") then quick = quick + 1 end
        end
    end
    check(quick == 3, "quick spawn has all three (%d)", quick)
    local opts = {}
    M.run_hook("PopulateMenuBar", { AddOrGetMenu = function() return { AddOption = function(_, t) opts[t] = true return {} end, AddSpacer = function() end } end })
    check(opts["Dr. Eggman"] and opts["Tikal"] and opts["?"], "the menubar has all three")
end
-- the settings log: one line per change
setcv("gsa1_debug_pad", 0x4000)
check(log_has("gsa1_debug_pad = 16384"), "the session log: gsa1_debug_pad = 16384")
setcv("gsa1_debug_pad", 0x8000)

-- 7. the mock against the module's playable_api.txt (5.5): the binding test writes it whenever the snapshot's libsa1.h defines SA1_API_PLAYABLE --
do
    local groot = string.gsub(tests, "[/" .. string.char(92) .. "]tests$", "")
    local hdr = host_read(groot .. "/build/deps/include/libsa1.h") or ""
    if not string.find(hdr, "#define SA1_API_PLAYABLE", 1, true) then
        info("playable_api.txt: the snapshot's libsa1.h has no SA1_API_PLAYABLE - the check is skipped (5.5's rule)")
    else
        local api = host_read(groot .. "/build/x86_64-windows/playable_api.txt")
        local wrong, nc, np = {}, 0, 0
        if not api then
            wrong[1] = "no build/x86_64-windows/playable_api.txt"
        else
            for line in string.gmatch(api, "[^\r\n]+") do
                if string.sub(line, 1, 1) ~= "#" then
                    local f = {}
                    for part in string.gmatch(line .. "\t", "([^\t]*)\t") do f[#f + 1] = part end
                    if f[1] == "const" then
                        nc = nc + 1
                        if tonumber(G[f[2]]) ~= tonumber(f[3]) then wrong[#wrong + 1] = "const " .. f[2] end
                    elseif f[1] == "playable" then
                        np = np + 1
                        if not GSA1.CharacterByKind(tonumber(f[2])) then wrong[#wrong + 1] = "playable " .. f[2] end
                    end
                end
            end
            if nc < 1 or np < 2 then wrong[#wrong + 1] = string.format("only %d constants, %d kinds", nc, np) end
        end
        check(#wrong == 0, "the mock and the list agree with playable_api.txt%s", #wrong > 0 and (": " .. table.concat(wrong, ", ")) or "")
    end
end

check(#M.reported == 0, "no Lua error reported (%d%s)", #M.reported, M.reported[1] and (": " .. M.reported[1]) or "")
return done()
