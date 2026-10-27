-- feat_giverings_test.lua - one rule for changing a character's rings by hand (0.9.2a; the 0.9.2 verifier's leftover:
-- "the 'Give rings' button and gsa1_rings use one rule (single player, sv_cheats 1, admin or listen host), checked on the
-- server too"), run by tests/lua_host.c in Garry's Mod's own LuaJIT:
--   lua_host tests/feat_giverings_test.lua <tests dir> <addon/lua dir>
-- The client is the addon's client files over tests/lua_mock.lua; the server is feat/sh_giverings.lua + sv_giverings.lua
-- in their own environment; the two talk through a loopback. Checks (0.9.2: the button refused sv_cheats, gsa1_rings
-- refused the listen host, the server was never asked):
--   * the rule: single player, sv_cheats 1, the listen server's host, an admin - yes; else no, with a plain sentence;
--   * the button (gsa1_give_rings) and the console (gsa1_rings, gsa1_rings_add) give the same answers;
--   * multiplayer: the client asks the server and changes the rings only after its yes; a client that thinks it is an
--     admin while the server says it is not is refused ("the server says no"); single player: no question, at once.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_giverings_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

-- loopback: client -> server at once, server -> client at once
local SRECV, CRECV, STRINGS = {}, {}, {}
local cbuf, sbuf = nil, nil
local asked, answered = 0, 0
local spos, cpos, sin, cin = 0, 0, {}, {}
local function crd() cpos = cpos + 1 return cin[cpos] end
local SPLY                                   -- the server's view of the local player
net.Start = function(name) cbuf = { name = name, vals = {} } end
local function cpush(v) cbuf.vals[#cbuf.vals + 1] = v end
net.WriteUInt, net.WriteInt, net.WriteBool, net.WriteString, net.WriteFloat = cpush, cpush, cpush, cpush, cpush
net.SendToServer = function()
    local m = cbuf
    cbuf = nil
    if m.name == "gsa1_rings_ask" then asked = asked + 1 end
    local fn = SRECV[m.name]
    if fn then
        sin, spos = m.vals, 0
        fn(#m.vals * 8, SPLY)
    end
end
net.Receive = function(name, fn) CRECV[name] = fn end
net.ReadUInt, net.ReadInt, net.ReadBool, net.ReadString = crd, crd, crd, crd
util.NetworkStringToID = function(n) return STRINGS[n] and 1 or 0 end

local S = setmetatable({}, { __index = _G })
S.SERVER, S.CLIENT = true, false
local function srd() spos = spos + 1 return sin[spos] end
S.util = { AddNetworkString = function(n) STRINGS[n] = true end }
S.net = {
    Receive = function(name, fn) SRECV[name] = fn end,
    ReadUInt = srd, ReadInt = srd, ReadBool = srd, ReadString = srd,
    Start = function(name) sbuf = { name = name, vals = {} } end,
    WriteUInt = function(v) sbuf.vals[#sbuf.vals + 1] = v end,
    Send = function()
        local m = sbuf
        sbuf = nil
        answered = answered + 1
        local fn = CRECV[m.name]
        if fn then
            cin, cpos = m.vals, 0
            fn(#m.vals * 8)
        end
    end,
}
S.net.WriteBool, S.net.WriteString = S.net.WriteUInt, S.net.WriteUInt
S.print = function() end
local SCV = {}
S.GetConVar = function(n) return SCV[n] end
local function sinclude(rel)
    local fn, err = host_load(host_read(root .. "/" .. rel), "sv:" .. rel)
    if not fn then error(err) end
    setfenv(fn, S)
    fn()
end
rawset(S, "GSA1", {})
sinclude("gsa1/feat/sh_giverings.lua")
sinclude("gsa1/feat/sv_giverings.lua")
local SG = rawget(S, "GSA1")

-- the client: the addon, a character, the module's ring call
local G = M.module({})
GSA1 = nil
M.load("autorun/gsa1_autorun.lua")
local rings, adds = 0, 0
G.AddRings = function(id, n) rings = rings + n adds = adds + 1 return true end
G.StateEx = function(id, out) out = out or {} out.rings = rings return out end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -16000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -16000 }
GSA1.Spawn("sonic")
M.frame(1 / 60)
check(GSA1.Char ~= nil and GSA1.RingsRule ~= nil and GSA1.RingsRequest ~= nil, "a character; the shared rule is loaded")

-- the rule, in both realms (the client's view: M.player; the server's: SPLY)
local function player(admin, host)
    return { IsValid = function() return true end, IsAdmin = function() return admin end,
             IsListenServerHost = function() return host end, Nick = function() return "owner" end }
end
SPLY = player(false, false)
local sp0 = game.SinglePlayer
local cases = {
    { "single player", true, false, false, false, true },
    { "multiplayer, nobody special", false, false, false, false, false },
    { "multiplayer, sv_cheats 1", false, true, false, false, true },
    { "multiplayer, the listen server's host", false, false, true, false, true },
    { "multiplayer, an admin", false, false, false, true, true },
}
local wrong = {}
for _, c in ipairs(cases) do
    game.SinglePlayer = function() return c[2] end
    M.cv("sv_cheats", "0"):SetString(c[3] and "1" or "0")
    SCV.sv_cheats = M.convars.sv_cheats
    local p = player(c[5], c[4])
    local okc, why = GSA1.RingsRule(p)
    local oks = SG.RingsRule(p)
    if okc ~= c[6] or oks ~= c[6] or (not okc and type(why) ~= "string") then wrong[#wrong + 1] = c[1] end
end
check(#wrong == 0, "the rule (client and server alike): single player, sv_cheats 1, the listen server's host and an admin "
    .. "may; nobody else%s", #wrong > 0 and ("; wrong: " .. table.concat(wrong, ", ")) or "")

-- the button and the console in multiplayer: asked of the server, applied after its yes
game.SinglePlayer = function() return false end
M.cv("sv_cheats", "0"):SetString("0")
M.player.IsAdmin = function() return true end
M.player.IsListenServerHost = function() return false end
SPLY = player(true, false)
local a0, q0 = adds, asked
RunConsoleCommand("gsa1_give_rings", "50")
local give_ok = adds == a0 + 1 and asked == q0 + 1 and rings == 50
M.T = M.T + 1
RunConsoleCommand("gsa1_rings", "20")
local set_ok = rings == 20 and asked == q0 + 2
M.T = M.T + 1
RunConsoleCommand("gsa1_rings_add", "5")
check(give_ok and set_ok and rings == 25 and asked == q0 + 3 and answered == 3,
    "an admin in multiplayer: Give 50 rings, gsa1_rings 20, gsa1_rings_add 5 - each asked of the server first (%d "
    .. "questions, %d answers), rings now %d", asked - q0, answered, rings)
-- the client believes it is an admin, the server does not: refused, told why, no ring changed
SPLY = player(false, false)
local a1, c0 = adds, #M.console
M.T = M.T + 1
RunConsoleCommand("gsa1_give_rings", "10")
local said = table.concat(M.console, "\n", c0 + 1)
check(adds == a1 and string.find(said, "the server says no", 1, true) ~= nil,
    "the server's view decides: a client that thinks it is an admin is refused (no AddRings; \"%s\")",
    string.match(said, "[^\n]*server says no[^\n]*") or said)
-- nobody special: refused on the client already (the same sentence for the button and the console)
chat.AddText = function(...)
    local t = {}
    for _, v in ipairs({ ... }) do if type(v) == "string" then t[#t + 1] = v end end
    M.console[#M.console + 1] = table.concat(t)
end
M.player.IsAdmin = function() return false end
local c1 = #M.console
RunConsoleCommand("gsa1_give_rings", "10")
RunConsoleCommand("gsa1_rings", "10")
local said2 = table.concat(M.console, "\n", c1 + 1)
check(adds == a1 and string.find(said2, "only an admin or the server's host", 1, true) ~= nil and
    string.find(said2, "sv_cheats 1, an admin or the server's host", 1, true) ~= nil,
    "not allowed: the button and the console both refuse and say who may (%s)", said2)
-- single player: no question, at once
game.SinglePlayer = sp0
local q1 = asked
RunConsoleCommand("gsa1_give_rings", "10")
check(asked == q1 and adds == a1 + 1, "single player: given at once, the server is not asked")
check(#M.reported == 0, "no Lua error (%s)", M.reported[1] or "none")
print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
