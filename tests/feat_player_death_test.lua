-- feat_player_death_test.lua - the Garry's Mod player's death while a G-SA1 character (sadc docs/research/gsa1_090_player.md
-- L6 with its review G3 / G7, R.5 item 7; owner answer, rounds plan 14.1j: "a NextBot / script kill of the player: both
-- die and respawn together"). The research model's check 3 (sadc/build/research/player/player_model_test.lua: after
-- Player:Kill the dead player never respawned, the character ran on) inverted, in Garry's Mod's own LuaJIT: the addon's
-- client through its autorun against tests/lua_mock.lua (cl_character.lua's real death and respawn handling over a mocked
-- module whose world dies on DAMAGE_KILL and asks for its restart 2 s later, as the game does after a hit), the server's
-- files (sv_gsa1.lua, the interaction feature) through the autorun's server branch in their own environment, a model of
-- Garry's Mod's player (Kill, Spawn with the gamemode's loadout after the PlayerSpawn hooks, the weapon switch gate) and a
-- loopback network (a message is read at the other side's next frame).
--   lua_host tests/feat_player_death_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_player_death_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only the interaction feature's files (the others have their own tests)
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_interact%.lua$") then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end

-- Garry's Mod constants and helpers the mock lacks
MOVETYPE_VPHYSICS, MOVETYPE_NOCLIP, MOVETYPE_WALK, MOVETYPE_OBSERVER = 6, 8, 2, 10
MASK_SOLID, MASK_PLAYERSOLID, CONTENTS_DEBRIS, IN_USE = 33570827, 33636363, 0x4000000, 32
USE_ON, USE_TOGGLE, COLLISION_GROUP_DEBRIS = 1, 3, 1
local VMT = getmetatable(Vector())
function VMT:Dot(v) return self.x * v.x + self.y * v.y + self.z * v.z end
function VMT:IsZero() return self.x == 0 and self.y == 0 and self.z == 0 end

-- the loopback network: what one side sends is read at the other side's next frame
local strings, recv_s, recv_c = {}, {}, {}
local to_server, to_client = {}, {}
local out_c, out_s
local function writer_to(get)
    return function(v)
        local m = get()
        if m then m.vals[#m.vals + 1] = (type(v) == "table" and v.x ~= nil) and Vector(v) or v end
    end
end
net.Start = function(name) out_c = { name = name, vals = {} } end
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteFloat", "WriteVector", "WriteNormal", "WriteString" }) do
    net[w] = writer_to(function() return out_c end)
end
net.SendToServer = function()
    if out_c then to_server[#to_server + 1] = out_c end
    out_c = nil
end
net.Receive = function(name, fn) recv_c[name] = fn end
local cread
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadFloat", "ReadVector", "ReadNormal", "ReadString" }) do
    net[r] = function() return cread() end
end
util.NetworkStringToID = function(n) return strings[n] and 1 or 0 end
local function reader(vals)
    local i = 0
    return function() i = i + 1 return vals[i] end
end
local sent_s = {}                       -- every message the server sent: name
local sent_c = {}                       -- every message the client sent: name

-- the player: one entity for both realms (single player), with Garry's Mod's player parts modelled -------------------------
local ply = M.player
local MAP_SPAWN = Vector(-500, 300, 8)
ply.pos = Vector(MAP_SPAWN)
ply.alive, ply.movetype, ply.nodraw, ply.inv, ply.kills, ply.spawns = true, MOVETYPE_WALK, false, {}, 0, 0
ply.drawWorld, ply.drawView, ply.shadow = true, true, true
function ply:EntIndex() return 1 end
function ply:IsNPC() return false end
function ply:IsNextBot() return false end
function ply:IsVehicle() return false end
function ply:IsWeapon() return false end
function ply:IsWorld() return false end
function ply:IsTyping() return false end
function ply:Ping() return 0 end
function ply:Alive() return self.alive end
function ply:InVehicle() return false end
function ply:SetNoDraw(b) self.nodraw = b end
function ply:GetNoDraw() return self.nodraw end
function ply:DrawShadow(b) self.shadow = b end
function ply:DrawWorldModel(b) self.drawWorld = b end
function ply:DrawViewModel(b) self.drawView = b end
function ply:SetMoveType(m) self.movetype = m end
function ply:GetMoveType() return self.movetype end
function ply:FlashlightIsOn() return false end
function ply:Flashlight() end
function ply:GetHull() return Vector(-16, -16, 0), Vector(16, 16, 72) end
function ply:SetVelocity() end
function ply:GetVelocity() return Vector() end
function ply:SetEyeAngles(a) M.yaw, M.pitch = a.y, a.p end
function ply:DropObject() end
function ply:OBBMins() return Vector(-16, -16, 0) end
function ply:OBBMaxs() return Vector(16, 16, 72) end
-- weapons: Give switches to a new weapon when none is active, through PlayerSwitchWeapon (true = prevented: sh_net.lua's
-- gate while a character); the dead lose their weapons
local S, SH, GM_S
local function S_call(ev, ...)
    for _, fn in pairs(SH[ev] or {}) do
        local a, b = fn(...)
        if a ~= nil then return a, b end
    end
    local g = GM_S[ev]
    if g then return g(GM_S, ...) end
end
local WMT = {}
WMT.__index = WMT
function WMT:GetClass() return self.cls end
function WMT:IsMarkedForDeletion() return false end
function WMT:Remove()
    self.removed = true
    if ply.inv[self.cls] == self then ply.inv[self.cls] = nil end
    if ply.active == self then ply.active = nil end
end
local function switch(w)
    if ply.active == w then return true end
    if S_call("PlayerSwitchWeapon", ply, ply.active or NULL, w) == true then return false end
    ply.active = w
    return true
end
function ply:Give(c)
    if self.inv[c] then return NULL end
    local w = setmetatable({ cls = c }, WMT)
    self.inv[c] = w
    if not IsValid(self.active) then switch(w) end
    return w
end
function ply:GetActiveWeapon() return self.active or NULL end
function ply:GetWeapon(c) return self.inv[c] or NULL end
function ply:HasWeapon(c) return self.inv[c] ~= nil end
function ply:SelectWeapon(c) if self.inv[c] then switch(self.inv[c]) end end
function ply:SetActiveWeapon(w) self.active = IsValid(w) and w or nil end
function ply:SwitchToDefaultWeapon() self:SelectWeapon("weapon_physgun") end
function ply:StripWeapons()
    for _, w in pairs(self.inv) do w.removed = true end
    self.inv, self.active = {}, nil
end
-- Player:Kill (DrGBase's jumpscare ends with entity:Kill): no damage; GM:PlayerDeath with the player as its own attacker
function ply:Kill()
    if not self.alive then return end
    self.alive, self.movetype, self.kills = false, MOVETYPE_OBSERVER, self.kills + 1
    self:StripWeapons()
    S_call("PlayerDeath", self, self, self)
end
-- Player:Spawn: the engine's part (alive, walking, drawn, at the map's spawn point), then GM:PlayerSpawn - the hooks
-- first, then the gamemode's own (sandbox's loadout)
function ply:Spawn()
    self.alive, self.movetype, self.nodraw, self.spawns = true, MOVETYPE_WALK, false, self.spawns + 1
    self.pos = Vector(MAP_SPAWN)
    M.yaw, M.pitch = 90, 0
    S_call("PlayerSpawn", self)
end

-- the server realm ---------------------------------------------------------------------------------------------------------
S = setmetatable({}, { __index = _G })
SH = {}
S.SERVER, S.CLIENT = true, false
GM_S = {
    PlayerUse = function() return true end, AllowPlayerPickup = function() return true end,
    PlayerSwitchWeapon = function() return false end,
    -- base player.lua: no respawn for 2 s; then a jump / attack press respawns (GM:PlayerDeathThink; p.keySpawn: the
    -- player presses them, which 092-gsa1-char's CreateMove lets through while dead)
    PlayerDeath = function(gm, p) p.NextSpawnTime = M.T + 2 end,
    PlayerDeathThink = function(gm, p)
        if p.NextSpawnTime and M.T < p.NextSpawnTime then return end
        if p.keySpawn then p:Spawn() end
    end,
    -- sandbox's loadout (player_sandbox.lua PLAYER:Loadout)
    PlayerSpawn = function(gm, p)
        p:Give("weapon_crowbar")
        p:Give("weapon_physgun")
        p:SwitchToDefaultWeapon()
    end,
}
S.hook = { Add = function(ev, name, fn) SH[ev] = SH[ev] or {} SH[ev][name] = fn end,
           Remove = function(ev, name) if SH[ev] then SH[ev][name] = nil end end,
           Run = function(ev, ...) return S_call(ev, ...) end }
local SCV = {}
S.CreateConVar = function(name, default)
    local c = setmetatable({ name = name, v = tostring(default) }, getmetatable(M.cv("fps_max")))
    SCV[name] = c
    return c
end
S.GetConVar = function(n) return SCV[n] end
S.player = { GetAll = function() return { ply } end }
S.weapons = { Register = function() end, GetStored = function() end }
S.scripted_ents = { Get = function() end }
S.AddCSLuaFile = function() end
S.CurTime = function() return M.T end
S.FindMetaTable = function() return nil end
S.near = {}
S.ents = { FindInSphere = function() return S.near end }
S.util = {
    AddNetworkString = function(n) strings[n] = true end,
    NetworkStringToID = function(n) return strings[n] and 1 or 0 end,
    IsInWorld = function() return true end,
    TraceHull = function(t) return { StartSolid = false, Hit = false, HitPos = Vector(t.endpos) } end,
    TraceLine = function(t) return { Hit = false, Fraction = 1, HitPos = Vector(t.endpos) } end,
}
S.include = function(rel)
    local src = host_read(M.root .. "/" .. rel)
    if not src then error("server include: no file " .. rel) end
    local fn, err = host_load(src, "sv:" .. rel)
    if not fn then error(err) end
    setfenv(fn, S)
    fn()
end
local sread
S.net = {
    Receive = function(name, fn) recv_s[name] = fn end,
    Start = function(name) out_s = { name = name, vals = {} } end,
    Send = function()
        if out_s then
            to_client[#to_client + 1] = out_s
            sent_s[#sent_s + 1] = out_s.name
        end
        out_s = nil
    end,
}
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteFloat", "WriteVector", "WriteNormal", "WriteString" }) do
    S.net[w] = writer_to(function() return out_s end)
end
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadFloat", "ReadVector", "ReadNormal", "ReadString" }) do
    S.net[r] = function() return sread() end
end

-- deliveries: the client's messages at the server's tick, the server's at the client's frame
local function deliver_to_server()
    local list = to_server
    to_server = {}
    for _, m in ipairs(list) do
        sent_c[#sent_c + 1] = m.name
        local fn = recv_s[m.name]
        if fn then
            sread = reader(m.vals)
            fn(#m.vals * 8, ply)
        end
    end
end
local function deliver_to_client()
    local list = to_client
    to_client = {}
    for _, m in ipairs(list) do
        local fn = recv_c[m.name]
        if fn then
            cread = reader(m.vals)
            fn(#m.vals * 8)
        end
    end
end

-- the addon: the server's files (the autorun's server branch), then the client's ----------------------------------------------
rawset(S, "GSA1", {})
local ok_s, err_s = pcall(S.include, "autorun/gsa1_autorun.lua")
local SG = rawget(S, "GSA1")
local SI = SG and SG.Interact

-- the client's module: the interaction feature, and a world that dies the game's way
GSA1 = nil
local G = M.module({ features = { interact = 1 } })
local R = { calls = {}, queue = {}, dead = {}, restart = {}, pending = {}, deaths = 0 }
local function rec(name, ...) R.calls[#R.calls + 1] = { name, M.T, ... } end
local function calls_of(name, flags)
    local n = 0
    for _, c in ipairs(R.calls) do
        if c[1] == name and (flags == nil or c[4] == flags) then n = n + 1 end
    end
    return n
end
G.INTERACT = { ENEMY = 1, HOLDABLE = 5, BALLOON = 6, SOLID = 1, HITF_LAUNCHED = 8 }
function G.ObjAdd(ent) return ent + 1000, true end
G.ObjUpdate = G.ObjAdd
function G.ObjMove() return true end
function G.ObjRemove() return true end
function G.ObjClear() return 0 end
function G.ObjEvents(out) out = out or {} out.count = 0 return out end
function G.ObjConfig() return true end
function G.ObjHeld() return nil end
function G.ObjRelease() return true end
function G.ObjInfo() return { proxies = 0, refused = 0 } end
function G.SetCharOption() return true end
function G.AddRings() return true end
function G.Contacts(id, out) out = out or {} out.count = 0 return out end
-- sa1_character_damage: DAMAGE_KILL is the game's death request (8C07BBC2): the world dies in its next step
local KILL = 2
function G.Damage(id, flags, sx, sy, sz, ent)
    rec("Damage", id, flags, ent)
    if flags % 4 >= KILL and not R.ignoreKill then R.pending[id] = true end
    return true
end
function G.StateEx(id, out)
    out = out or {}
    out.rings, out.lives, out.score, out.held_object, out.held, out.mode = 0, 4, 0, 0, 0, 2
    out.dead = R.dead[id] == true
    return out
end
-- a death: SA1_EVENT_DEATH in the step it starts, SA1_EVENT_RESTART 2.0 s later (the game's own after a hit)
local function die(id, cause)
    if R.dead[id] then return end
    R.dead[id] = true
    R.deaths = R.deaths + 1
    R.queue[#R.queue + 1] = { type = 6, arg = cause, id = 0 }
    R.restart[id] = M.T + 2.0
end
local tick0 = G.Tick
function G.Tick(id, sx, sy, yaw, buttons, dt)
    local n, err, code = tick0(id, sx, sy, yaw, buttons, dt)
    if n and n > 0 then
        if R.pending[id] then
            R.pending[id] = nil
            die(id, 2)                              -- SA1_DEATH_HOST
        end
        if R.restart[id] and M.T >= R.restart[id] then
            R.restart[id] = nil
            R.queue[#R.queue + 1] = { type = 7, arg = 0, id = 2 }
        end
    end
    return n, err, code
end
local destroy0 = G.Destroy
function G.Destroy(id)
    R.restart[id], R.pending[id] = nil, nil
    return destroy0(id)
end
local pool = {}
function G.PollEvents(out)
    out = out or {}
    local n = 0
    for _, q in ipairs(R.queue) do
        n = n + 1
        local e = pool[n] or {}
        pool[n] = e
        -- the living character's id, as the module reports it (gsa1_091b_itembox.md review R.4.1)
        e.type, e.id, e.bank, e.x, e.y, e.z, e.arg, e.step, e.character = q.type, q.id, 0, 0, 0, 0, q.arg, 0,
            (GSA1.Char and GSA1.Char.id) or 1
        out[n] = e
    end
    out[n + 1] = nil
    out.count = n
    R.queue = {}
    return out
end

M.included = {}
local ok_c, err_c = pcall(M.load, "autorun/gsa1_autorun.lua")
local I = GSA1 and GSA1.Interact
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
check(ok_s and SI ~= nil and ok_c and #ferr == 0 and I ~= nil,
    "both realms load: sv_gsa1.lua and the interaction feature on the server (%s), the client through the autorun (%s)",
    tostring(err_s or "ok"), ok_c and table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_c or ferr[1]))
if not (I and SI) then return done() end
check(strings.gsa1_player_died and strings.gsa1_respawn and SCV.gsa1_sv_respawn_with_character and
    SCV.gsa1_sv_respawn_with_character.v == "1",
    "the server registers gsa1_player_died and gsa1_respawn; \"comes back with the character\" is on by default")
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }

-- what the test sees of the client's hooks
local seen = { died = 0, respawned = 0, player_died = {} }
hook.Add("GSA1CharacterDied", "death_test", function() seen.died = seen.died + 1 end)
hook.Add("GSA1CharacterRespawned", "death_test", function() seen.respawned = seen.respawned + 1 end)
hook.Add("GSA1PlayerDied", "death_test", function(C, cls, how) seen.player_died[#seen.player_died + 1] = { cls, how } end)

-- one host frame (single player): the server's tick (the client's messages first), then the client's frame
local watch = nil                      -- { visible = n, armed = n, frames = n }: counted while set
local function frame()
    deliver_to_server()
    S_call("Think")
    if not ply.alive then S_call("PlayerDeathThink", ply) end
    deliver_to_client()
    M.frame(1 / 60)
    if watch then
        watch.frames = watch.frames + 1
        if ply.alive and not ply.nodraw then watch.visible = watch.visible + 1 end
        if ply.alive and IsValid(ply.active) and ply.active.cls ~= "gsa1_hands" then watch.armed = watch.armed + 1 end
        if ply.alive and ply:GetNW2Bool("gsa1_char", false) ~= true then watch.flag = watch.flag + 1 end
    end
end
local function frames(n) for _ = 1, n do frame() end end
-- a server setting: on the server and in the client's replicated copy (FCVAR_REPLICATED)
local function set_sv(name, v)
    if SCV[name] then SCV[name].v = v end
    if M.convars[name] then M.convars[name].v = v end
end
-- frames until the player is alive again (or `max` seconds): the time it took
local function until_alive(max)
    local t0 = M.T
    for _ = 1, math.floor(max * 60) do
        frame()
        if ply.alive then return M.T - t0 end
    end
    return nil
end

-- 1. a character: the server makes the player it ---------------------------------------------------------------------------
ply:Spawn()                                                    -- the map's first spawn: the sandbox loadout
frames(2)
check(IsValid(ply.active) and ply.active.cls == "weapon_physgun" and not ply.nodraw, "baseline: a sandbox player with "
    .. "the Physics Gun out")
ply.pos = Vector(0, 0, 0)
GSA1.Spawn("sonic")
frames(20)
local C = GSA1.Char
check(C ~= nil and ply.GSA1Active == true and ply.nodraw and ply.movetype == MOVETYPE_NOCLIP and
    ply:GetNW2Bool("gsa1_char", false) and (not IsValid(ply.active) or ply.active.cls == "gsa1_hands"),
    "Sonic spawned: the server made the player the character (invisible, noclip, the character flag, the weapon put away)")
if not C then return done() end
ply.GSA1Prev = ply.GSA1Prev or {}
local held_before = ply.GSA1Prev.weapon

-- 2. a NextBot's Player:Kill (DrGBase FNaF's jumpscare) -------------------------------------------------------------------------
local bonnie = { cls = "npc_drg_fnaf1_bonnie", pos = Vector(40, 0, 0) }
function bonnie:GetClass() return self.cls end
function bonnie:GetPos() return Vector(self.pos) end
function bonnie:IsNPC() return false end
function bonnie:IsNextBot() return true end
function bonnie:GetEnemy() return ply end
function bonnie:EntIndex() return 77 end
function bonnie:GetMoveType() return 3 end
S.near = { bonnie }
local damage0, kills0, spawns0, deaths0 = calls_of("Damage", KILL), ply.kills, ply.spawns, R.deaths
local died0, resp0 = seen.died, seen.respawned
ply.keySpawn = true                         -- (the player keeps pressing jump: the gamemode's own respawn must wait)
ply:Kill()
local took = until_alive(6)
ply.keySpawn = false
local NC = GSA1.Char
check(took ~= nil and took >= 2.9 and took <= 3.2 and ply.spawns == spawns0 + 1,
    "after Player:Kill the player respawns %.2f s later, with the character (the game's death until its restart request, "
    .. "2.0 s, then G-SA1's 1.0 s, plus the game pairs and a frame each way; 0.9.0: never), though it pressed jump all "
    .. "along (the gamemode's own respawn at 2 s waits for the character)", took or -1)
check(calls_of("Damage", KILL) == damage0 + 1 and R.deaths == deaths0 + 1 and seen.died == died0 + 1 and
    seen.respawned == resp0 + 1 and NC ~= C,
    "between the death and the respawn the character dies exactly once (one DAMAGE_KILL, one SA1_EVENT_DEATH, one "
    .. "GSA1CharacterDied) and respawns once")
local pd = seen.player_died[#seen.player_died]
check(pd and pd[1] == "npc_drg_fnaf1_bonnie" and pd[2] == 1,
    "the death message names the NextBot next to the player (Player:Kill has no attacker: the one that has the player as "
    .. "its enemy) and says it was a kill outright: GSA1PlayerDied(C, \"%s\", %s)", pd and pd[1] or "?",
    tostring(pd and pd[2]))
check(ply.alive and ply.GSA1Active and ply.nodraw and ply.movetype == MOVETYPE_NOCLIP and
    ply:GetNW2Bool("gsa1_char", false) and NC and (ply.pos - NC.drawPos):Length() < 1 and
    (ply.pos - MAP_SPAWN):Length() > 100,
    "the player came back as the character in the same tick, at the respawned character (%.0f %.0f %.0f), not at the map's "
    .. "spawn point", ply.pos.x, ply.pos.y, ply.pos.z)
watch = { visible = 0, armed = 0, flag = 0, frames = 0 }
frames(180)
check(ply.spawns == spawns0 + 1 and ply.alive and watch.visible == 0 and watch.armed == 0 and watch.flag == 0,
    "for 3 s after the respawn no frame shows a visible or armed player (%d visible, %d armed, %d without the character "
    .. "flag in %d frames; 0.9.0: visible and armed at the map's spawn point for up to 2 s)", watch.visible, watch.armed,
    watch.flag, watch.frames)
watch = nil
check(ply.kills == kills0 + 1 and ply.spawns == spawns0 + 1, "one kill, one spawn (%d, %d)", ply.kills - kills0,
    ply.spawns - spawns0)
GSA1.LogFlush()
local lt = M.files["gsa1/log.txt"] or ""
check(string.find(lt, "the player died (npc_drg_fnaf1_bonnie, killed outright (Garry's Mod's Kill)): the character is "
    .. "killed too", 1, true) ~= nil and string.find(lt, "the player is asked back with Sonic", 1, true) ~= nil,
    "the session log: the player's death with the NextBot's class, the request to come back")
-- the weapon held before the character comes back when the character ends (not the respawn's loadout)
GSA1.Remove(false)
frames(3)
check(held_before == "weapon_physgun" and IsValid(ply.active) and ply.active.cls == "weapon_physgun" and not ply.nodraw,
    "removing the character after that: the player gets the Physics Gun it held before the character (%s)",
    IsValid(ply.active) and ply.active.cls or "none")

-- 3. gsa1_sv_kill_on_death 1: the character's own death kills the player once, and both come back once (no loop) ---------
ply.pos = Vector(0, 0, 0)
GSA1.Spawn("sonic")
frames(20)
C = GSA1.Char
set_sv("gsa1_sv_kill_on_death", "1")
damage0, kills0, spawns0, deaths0, resp0 = calls_of("Damage", KILL), ply.kills, ply.spawns, R.deaths, seen.respawned
local sent_dead0 = #sent_c
die(C.id, 1)                                                    -- the game's own: a hit with no rings
frames(8 * 60)
local deads = 0
for i = sent_dead0 + 1, #sent_c do deads = deads + (sent_c[i] == "gsa1_dead" and 1 or 0) end
check(ply.kills == kills0 + 1 and ply.spawns == spawns0 + 1 and calls_of("Damage", KILL) == damage0 and
    R.deaths == deaths0 + 1 and seen.respawned == resp0 + 1 and deads == 1 and ply.alive and ply.GSA1Active,
    "kill on death: one character death -> exactly one Kill (%d), one respawn of the player (%d) and of the character "
    .. "(%d); the player's death is not passed back to the character (%d kills asked)", ply.kills - kills0,
    ply.spawns - spawns0, seen.respawned - resp0, calls_of("Damage", KILL) - damage0)
set_sv("gsa1_sv_kill_on_death", "0")

-- 4. a kill during a new character's first game pair waits for that pair (G7) ------------------------------------------------
frames(10)
GSA1.Respawn("test")
C = GSA1.Char
damage0, deaths0 = calls_of("Damage", KILL), R.deaths
local step_at_kill = C.state.step
ply:Kill()
deliver_to_client()                                             -- the message arrives before the character's first pair
local early = calls_of("Damage", KILL) - damage0
local took2 = until_alive(6)
check(step_at_kill == 0 and early == 0 and calls_of("Damage", KILL) == damage0 + 1 and R.deaths == deaths0 + 1 and
    took2 ~= nil, "a kill before the new character's first game pair (step %d) waits for it (no damage then), then kills "
    .. "it once; the player comes back with it (%.2f s)", step_at_kill or -1, took2 or -1)

-- 5. "The character can die" off: the kill is a plain hit, and the player comes back as soon as the gamemode allows ------------
frames(60)
M.convars.gsa1_can_die:SetString("0")
C = GSA1.Char
damage0 = calls_of("Damage", KILL)
local hits0 = calls_of("Damage", 0)
ply:Kill()
local took3 = until_alive(3)
check(took3 ~= nil and took3 >= 1.98 and took3 < 2.1 and calls_of("Damage", KILL) == damage0 and
    calls_of("Damage", 0) == hits0 + 1 and GSA1.Char == C and ply.GSA1Active and ply.nodraw,
    "\"The character can die\" off: Player:Kill is a plain hit on the character (no death), and the player comes back as "
    .. "the character as soon as the gamemode allows (its 2-s NextSpawnTime: %.2f s)", took3 or -1)
M.convars.gsa1_can_die:SetString("1")

-- 6. "Comes back with the character" off: the gamemode's own respawn ------------------------------------------------------------
frames(60)
set_sv("gsa1_sv_respawn_with_character", "0")
spawns0, resp0 = ply.spawns, seen.respawned
local alive6 = ply.alive
ply:Kill()
local still_dead = until_alive(1.5) == nil
ply.keySpawn = true
local took6 = until_alive(1)
ply.keySpawn = false
local plain = ply.alive and not ply.GSA1Active
frames(150)
check(alive6 and still_dead and took6 ~= nil and plain and ply.spawns == spawns0 + 1 and seen.respawned == resp0 + 1 and
    ply.GSA1Active and ply.nodraw,
    "with \"comes back with the character\" off the character still dies and respawns, the player stays dead until the "
    .. "gamemode's own respawn (a jump press after its 2 s), as a plain player first, the character's again after the "
    .. "client's 2-s gsa1_active repeat (as 0.9.1)")
set_sv("gsa1_sv_respawn_with_character", "1")

-- 7. a kill the game does not take (the character lives on): the player is asked back once, a few seconds later ----------
R.ignoreKill = true
C = GSA1.Char
spawns0, deaths0 = ply.spawns, R.deaths
ply:Kill()
local took7 = until_alive(8)
R.ignoreKill = false
check(took7 ~= nil and took7 >= 2.95 and took7 < 3.2 and R.deaths == deaths0 and GSA1.Char == C and
    ply.spawns == spawns0 + 1 and ply.GSA1Active and ply.nodraw, "a kill the game does not take: 3 s without its death, "
    .. "then the player is asked back once and comes back as the living character (%.2f s)", took7 or -1)

check(#M.reported == 0, "no Lua error%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
info("client messages %d, server messages %d; kills %d, spawns %d, character deaths %d", #sent_c, #sent_s, ply.kills,
    ply.spawns, R.deaths)
return done()
