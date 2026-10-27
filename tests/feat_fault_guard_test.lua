-- feat_fault_guard_test.lua - a game code fault restarts the character instead of removing it, and the rings survive
-- re-creations (sadc docs/research/gsa1_090_faults.md F3 with its review R.2.5 / R.2.7; gsa1_090_player.md review R.4 G2 /
-- R.5 item 8 (L9); gsa1_090_rings.md F7 with its review R4.11; gsa1_090_plan.md 6.10 tasks 1-3). Promoted from the research
-- prototype sadc/build/research/faults/fault_guard_test.lua (0.9.0: 2 of 6 failed - "Sonic stopped: game code fault ...",
-- the character removed: the owner's "the script dies").
-- The addon's client through its autorun on tests/lua_mock.lua, in Garry's Mod's own LuaJIT:
--   lua_host tests/feat_fault_guard_test.lua <tests dir> <addon/lua dir>
-- The mock module gets the game's ring and life counters (AddRings gives a 1-up for every hundred it passes, as the game's
-- 8C08A198 does; GetLives / SetLives; StateEx) and a Tick that can report the log's fault once.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_fault_guard_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

local G = M.module({})
-- the game's counters per character (B_8C752BE4 rings, B_8C752BE0 lives) and what was called
local R = { adds = {}, setlives = {} }
local function cs(id)
    local c = M.mchars[id]
    if c and c.rings == nil then c.rings, c.lives = c.startRings or 0, 4 end
    return c
end
function G.AddRings(id, n)
    local c = cs(id)
    if not c then return nil, "no such character" end
    R.adds[#R.adds + 1] = { id = id, n = n }
    local old = c.rings
    c.rings = c.rings + n
    local a, b = math.floor(old / 100), math.floor(c.rings / 100)
    if a < b then c.lives = math.min(c.lives + (b - a), 127) end     -- 8C08A120: the 1-up
    return true
end
function G.GetLives(id)
    local c = cs(id)
    return c and c.lives or nil
end
function G.SetLives(id, n)
    local c = cs(id)
    if not c then return nil, "no such character" end
    R.setlives[#R.setlives + 1] = { id = id, n = n }
    c.lives = n
    return n
end
-- (the character options of feat/cl_charopt.lua need these to carry the lives over: a re-creation keeps them)
function G.SetCompanion() return true end
function G.SetGameOption() return true end
function G.StateEx(id, out)
    local c = cs(id)
    if not c then return nil end
    out = out or {}
    out.rings, out.lives, out.dead = c.rings, c.lives, false
    return out
end
-- the module's Tick can fail: fault_next > 0 makes the next tick that runs a pair fail with `fault_msg` / `fault_code`;
-- a faulted id answers as Session::tick does afterwards
local real_tick = G.Tick
local faulted, fault_next = {}, 0
local fault_msg = "game code fault: character 262145: access violation (read) at guest 00000004 (NULL page, segment 0x00) "
    .. "in func_8C0AFB10 (8C0AFB10); host 0000000000000004, pc 00007FFB91022242"
local fault_code = "fault"
function G.Tick(id, ...)
    if faulted[id] then return nil, "the character's world faulted earlier; recreate the character", "fault" end
    local n, e, c = real_tick(id, ...)
    if fault_next > 0 and n and n > 0 then
        fault_next = fault_next - 1
        faulted[id] = true
        return nil, fault_msg, fault_code
    end
    return n, e, c
end

GSA1 = nil
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
check(ok_load, "the addon loads (%s)", tostring(err_load or "ok"))
if not ok_load then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
local function frames(n) for _ = 1, n do M.frame(1 / 60) end end
local function console_since(c0) return table.concat(M.console, " | ", c0 + 1) end
local function log_text()
    GSA1.LogFlush()
    return M.files["gsa1/log.txt"] or ""
end

-- 1. a fault restarts the character where it stood, with its rings and lives -------------------------------------------
GSA1.Spawn("sonic")
check(GSA1.Char ~= nil, "Sonic spawned")
if not GSA1.Char then return done() end
frames(60)
local C1 = GSA1.Char
cs(C1.id).rings = 400
cs(C1.id).lives = 7
M.mchars[C1.id].pos = Vector(900, 100, -139)           -- where the game moved it
frames(2)
local stood = Vector(C1.drawPos)
local adds0 = #R.adds
local c0 = #M.console
fault_next = 1
frames(30)
local said = console_since(c0)
info("console after the fault: %s", said)
local C2 = GSA1.Char
check(#M.reported == 0, "no Lua error (%s)", M.reported[1] or "none")
check(C2 ~= nil and C2.id ~= C1.id, "the faulted character is restarted: a new character (id %s -> %s; 0.9.0 removed it)",
    tostring(C1.id), tostring(C2 and C2.id))
if not C2 then return done() end
local create = M.creates[#M.creates]
check(create.id == C2.id and math.abs(create.pos.x - stood.x) < 0.01 and math.abs(create.pos.y - stood.y) < 0.01 and
    math.abs(create.pos.z - (stood.z + 1)) < 0.01 and create.rings == nil,
    "... where it stood (%.0f %.0f %.0f), with no start rings of its own", create.pos.x, create.pos.y, create.pos.z)
local adds = {}
for i = adds0 + 1, #R.adds do adds[#adds + 1] = R.adds[i] end
check(#adds == 1 and adds[1].id == C2.id and adds[1].n == 400 and cs(C2.id).rings == 400,
    "L9: its 400 rings carried over with exactly one AddRings(new id, 400) (%d calls; the new world has %d rings)", #adds,
    cs(C2.id).rings)
check(cs(C2.id).lives == 7, "no life lost and none gained: 7 lives (the 1-ups of the carried rings are taken back: %d "
    .. "SetLives call(s))", #R.setlives)
check(string.find(said, "game code faulted; restarted where it stood", 1, true) ~= nil and
    not string.find(said, "stopped", 1, true), "one short chat line says so")
local log = log_text()
check(string.find(log, "fault +Sonic: game code fault 1 within 10 s: [^\n]*func_8C0AFB10") ~= nil,
    "the session log has a fault line with the function and the count")
check(string.find(log, "re-created where it stood (restart after a game code fault)", 1, true) ~= nil and
    string.find(log, "400 rings kept", 1, true) ~= nil, "... and the restart, with the rings kept")

-- 2. the old world's fault event reaches the new character: no second chat line ------------------------------------------
local pe = G.PollEvents
local once = true
G.PollEvents = function(out)
    out = pe(out)
    if once then
        once = false
        local e = out[1]
        e.type, e.id, e.character = 13, 0x8C0AFB10, C1.id         -- SA1_EVENT_FAULT of the faulted character
    end
    return out
end
c0 = #M.console
frames(2)
G.PollEvents = pe
check(not string.find(console_since(c0), "faulted (address", 1, true) and
    string.find(log_text(), "the earlier Sonic's fault event (address 8C0AFB10)", 1, true) ~= nil,
    "the faulted world's own fault event, polled with the new character's first events, is logged, not said again")

-- 3. an older module's answer for a fatal stub ("not implemented", code "error"): restarted as well -----------------------
frames(60)
M.T = M.T + 11                       -- out of the 10-s fault window
local C3 = GSA1.Char
fault_msg = "not implemented: character 3: unimplemented: func_8C051D38 (8C051D38) has no implementation in this build "
    .. "(fatal stub)"
fault_code = "error"
fault_next = 1
frames(10)
check(GSA1.Char ~= nil and GSA1.Char.id ~= C3.id, "a fatal stub reported by a 0.9.1 module (code \"error\", \"not "
    .. "implemented\") restarts the character too")
fault_code = "fault"

-- 4. 3 faults within 10 s stop it, saying why -----------------------------------------------------------------------------
frames(30)
M.T = M.T + 11
c0 = #M.console
fault_next = 5
frames(120)
said = console_since(c0)
local _, restarts4 = string.gsub(said, "restarted where it stood", "")
check(GSA1.Char == nil and restarts4 == 2 and string.find(said, "stopped: its game code faulted 3 times within 10 s", 1,
    true) ~= nil, "3 faults within 10 s: restarted twice, then the character stops (no restart loop) and the chat line "
    .. "says why")
local fc = GSA1.LogState.counts and GSA1.LogState.counts.faults
check(fc ~= nil and fc.n == 5 and fc.by.restarted == 4 and fc.by.stopped == 1,
    "the session summary counts the faults (%s restarted, %s stopped)", fc and tostring(fc.by.restarted) or "?",
    fc and tostring(fc.by.stopped) or "?")
fault_next = 0

-- 5. other tick errors stop it as before -------------------------------------------------------------------------------------
M.T = M.T + 20                       -- out of the fault window
GSA1.Spawn("sonic")
frames(30)
local tick2 = G.Tick
G.Tick = function(id, ...) return nil, "invalid argument: dt", "error" end
frames(2)
G.Tick = tick2
check(GSA1.Char == nil, "a tick error that is not a fault removes the character as before")

-- 6. L9 on its own: a re-creation keeps the rings, a respawn after a death keeps the game's 0 ---------------------------
GSA1.Spawn("sonic")
frames(30)
local C6 = GSA1.Char
cs(C6.id).rings = 400
adds0 = #R.adds
GSA1.Recreate("upgrades changed")
local C7 = GSA1.Char
check(C7 and C7.id ~= C6.id and #R.adds == adds0 + 1 and R.adds[#R.adds].id == C7.id and R.adds[#R.adds].n == 400,
    "GSA1.Recreate with 400 rings: exactly one AddRings(new id, 400) (0.9.0: none, the rings were thrown away)")
frames(30)
adds0 = #R.adds
cs(C7.id).rings = 250
GSA1.Respawn("death")
check(GSA1.Char and GSA1.Char.id ~= C7.id and #R.adds == adds0 and cs(GSA1.Char.id).rings == 0,
    "a respawn keeps the game's 0 (no AddRings)")
cs(GSA1.Char.id).rings = 0
adds0 = #R.adds
GSA1.Recreate("the map's collision was loaded")
check(#R.adds == adds0, "a re-creation with no rings calls nothing")

-- 7. start rings: spawns and respawns start with them, a re-creation carries its own count instead ---------------------
M.convars.gsa1_start_rings:SetString("25")
GSA1.Remove(true)
GSA1.Spawn("sonic")
local sp = M.creates[#M.creates]
frames(5)
GSA1.Respawn("command")
local rp = M.creates[#M.creates]
cs(GSA1.Char.id).rings = 60
GSA1.Recreate("upgrades changed")
local rc = M.creates[#M.creates]
check(sp.rings == 25 and rp.rings == 25 and rc.rings == nil and cs(GSA1.Char.id).rings == 60,
    "Start with 25 rings: the spawn and the respawn ask the module for 25 (%s, %s), the re-creation for none (%s) and "
    .. "carries its 60 over", tostring(sp.rings), tostring(rp.rings), tostring(rc.rings))
M.convars.gsa1_start_rings:SetString("150")
GSA1.Respawn("command")
check(M.creates[#M.creates].rings == 99, "at most 99 (%s): a start never gives a 1-up", tostring(M.creates[#M.creates].rings))
M.convars.gsa1_start_rings:SetString("0")
GSA1.Respawn("command")
check(M.creates[#M.creates].rings == nil, "0 = the game's 0 (no start rings asked for)")

-- 8. Give rings (rings F7): the Character page's buttons, the command, admin-only in multiplayer ---------------------------
local made = {}
local function standin(kind)
    local t = { kind = kind, calls = {} }
    made[#made + 1] = t
    return setmetatable(t, { __index = function(_, k)
        if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
        return function(self, ...)
            t.calls[#t.calls + 1] = { k, ... }
            return standin(k)
        end
    end })
end
vgui.Create = function(cls) return standin(cls) end
M.menu = {}
M.run_hook("PopulateToolMenu")
local entry
for _, e in ipairs(M.menu) do if e.class == "gsa1_character" then entry = e end end
check(entry ~= nil, "the Character page")
local buttons, slider, box = {}, false, false
if entry then
    local panel = standin("DForm")
    entry.cpanel(panel)
    for _, P in ipairs(made) do
        for _, c in ipairs(P.calls) do
            if c[1] == "Button" and c[3] == "gsa1_give_rings" then buttons[#buttons + 1] = c[4] end
            if c[1] == "NumSlider" and c[3] == "gsa1_start_rings" then slider = true end
            if c[1] == "CheckBox" and c[3] == "gsa1_hostwater" then box = true end
        end
    end
end
check(table.concat(buttons, " ") == "10 50 100" and slider and box,
    "the Character page: Give 10 / 50 / 100 rings (%s), Start with N rings, Water follows Garry's Mod's water",
    table.concat(buttons, " "))
local C8 = GSA1.Char
adds0 = #R.adds
cs(C8.id).rings, cs(C8.id).lives = 30, 4
RunConsoleCommand("gsa1_give_rings", "100")
check(#R.adds == adds0 + 1 and R.adds[#R.adds].n == 100 and R.adds[#R.adds].id == C8.id and cs(C8.id).lives == 5,
    "Give 100 rings: AddRings(id, 100) through the game's counter, with its 1-up (lives 4 -> %d)", cs(C8.id).lives)
-- multiplayer, not an admin: refused
local sp0 = game.SinglePlayer
game.SinglePlayer = function() return false end
M.player.IsAdmin = function() return false end
M.player.IsListenServerHost = function() return false end
adds0 = #R.adds
c0 = #M.console
RunConsoleCommand("gsa1_give_rings", "50")
check(#R.adds == adds0 and string.find(console_since(c0), "only an admin or the server's host", 1, true) ~= nil,
    "multiplayer: a player who is not an admin is refused (no AddRings) and told why")
M.player.IsAdmin = function() return true end
RunConsoleCommand("gsa1_give_rings", "50")
local admin_ok = #R.adds == adds0 + 1
M.player.IsAdmin = function() return false end
M.player.IsListenServerHost = function() return true end
RunConsoleCommand("gsa1_give_rings", "10")
check(admin_ok and #R.adds == adds0 + 2, "an admin and the listen server's host may")
game.SinglePlayer = sp0
check(#M.reported == 0, "no Lua error in the whole test (%s)", M.reported[1] or "none")
return done()
