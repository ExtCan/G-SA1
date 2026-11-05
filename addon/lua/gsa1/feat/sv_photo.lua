-- G-SA1 photo mode, the server's part (0.9.9d; feat/cl_photo.lua is the client's, sadc docs/research/photo099d.md 4.2 with RP.15; the owner's answers 12 and 13).
--
-- UNTOUCHABLE (answer 13, "completely invincible and untouchable", which replaced the plan's "a hit wakes you in multiplayer"): while a player who may (WHO MAY, below) says it is in photo mode, in any damage mode, nothing lands: god mode (Player:GodEnable) and no target
-- (Player:SetNoTarget, so NPCs and the NextBots that ask leave it alone), EntityTakeDamage and PlayerShouldTakeDamage refuse everything, I.SendHurt (feat/sv_interact.lua) sends no hit to the client, CanPlayerSuicide refuses the console's kill, and
-- Player:Kill / KillSilent called from Lua do nothing for such a player (a NextBot's kill does not go through damage: READ tests/feat_player_death_test.lua's model). What the player had before stays after: both are put back as they were. Nothing is
-- kept for later: a hit in photo mode never lands, also not when it ends. A way past all this (a map's own kill, an addon holding the real Kill from before this file): the player dies, the server's part ends with it (PostPlayerDeath) and the client's by its poll.
-- WHO MAY (0.9.9d's verifier, SADC/build/research/r099d/verify/photo_attack.txt: a crafted message, or followers alone, gave a plain Garry's Mod player god mode on someone else's server): in single player anyone; in multiplayer only a character (P.Allowed).
-- A character has no weapon and is hidden (READ sv_gsa1.lua activate), and it stops being untouchable when it stops being a character (Think). With followers alone in multiplayer they freeze and the player stays an ordinary player, the page says so. While untouchable in multiplayer it hurts nobody either: a real frozen client
-- attacks nobody, so that only stops a modified one (its character can still walk: the server cannot tell it from a frozen one, UNVERIFIED how much that is worth to anyone).
-- A KNOWN CONSEQUENCE, the owner's to weigh: in multiplayer this lets any character step out of a fight with one key. Other players see nothing new (the player is hidden while a character, feat/cl_photo.lua).
-- It ends when the client says so, when the client has said nothing for 5 s (P.SILENT: the client repeats itself every 2 s), at death, at the disconnect, at ShutDown.
--
-- THE WORLD (answer 12, "Freezing the world should be optional"; gsa1_photo_world, default off; SINGLE PLAYER ONLY: asked in multiplayer the server refuses, whoever asks: a server is for other people too):
--   the way          stops                              what it leaves behind                                                                   verdict
--   phys_timescale 0 all physics: props, ragdolls, what was thrown; velocities kept (the simulation gets no time, UNVERIFIED)  a ConVar that survives a map change   USED (READ: Sandbox's Utilities slider goes down to 0)
--   ai_disabled 1    NPCs                                a ConVar that survives a map change                                                     USED (READ: Sandbox's menu bar)
--   nb_stop 1        NextBots (UNVERIFIED that Lua's run under it; flags UNVERIFIED, so it may need sv_cheats: what does not take is told to the page)  the same     USED
--   game.SetTimeScale everything, doors too              not rejected for what it stops: at its smallest the server's frames come seconds apart (my memory of the wiki's 0.001, UNVERIFIED), and a client's "leave" waits for one; CurTime crawls   REJECTED
--   host_timescale   the same                            a cheat; G-SA1 reads it for its own ticks                                                REJECTED
--   the engine's pause everything                        Think stops (READ cl_hitch.lua's note): no key and no camera of ours; no sv_pausable in server.dll (MEASURED)  REJECTED
--   EnableMotion per object  physics, one by one         a list to undo, velocities lost, new objects to catch, a player's frozen props to tell from ours              REJECTED
--   NOT STOPPED by the ways used: doors, trains and lifts (they do not run on physics), animated props, particles, timers and other addons' own Lua, other sounds. Said on the page.
--   Each value is put back only if it is still what photo mode set (so a Sandbox box you moved meanwhile stays yours), and to what it was (so your own Disable AI stays on).
--   ON EVERY WAY OUT: the key, Escape, the command and the Leave button all end in the client's message; the box unticked while frozen too; dying and a silent client: here; changing map: ShutDown here, and because a ConVar lives on while the Lua state does
--   not, a mark in the DATA folder (P.MARK, written before the first ConVar) is read when this file loads next: on the next map, or after a crash and restart. It holds the values from before. Nothing else is left behind.
--   ONE CHANGE AT A TIME: Source runs a server's RunConsoleCommand later, not at once (my memory of the wiki's note, UNVERIFIED; the test's section V5 runs them so), so what was just asked may not show in the ConVars yet, and reading them then would take photo mode's own values for the person's, or see nothing to put back
--   (r099d/verify/photo_attack.txt A3). So a message only says what is wanted (P.worldAsk); P.WorldStep makes a change when the last one shows, or has had P.WORLD_SETTLE s (a command that does not take), here or in Think. The mark goes only when the values are seen back.
GSA1 = GSA1 or {}
local P = GSA1.Photo
if not P then error("gsa1/feat/sh_photo.lua did not load: photo mode needs it") end

P.SILENT = 5                -- s without a message from a client in photo mode: over
P.EYE_EVERY = 0.2           -- s: an eye taken at most this often per player
P.MARK = "gsa1_photo_world.txt"
P.active = P.active or {}   -- the players in photo mode
P.world = P.world or nil    -- { prev = { [name] = string }, ply, checkAt } while the world is frozen
P.worldAsk = P.worldAsk or nil      -- the player who wants it frozen; nil: nobody
P.worldPend = P.worldPend or nil    -- { was = { [name] = the value before the command }, untilT, dropMark } while the last change may not have run
P.WORLD_SETTLE = 0.25       -- s: at most this long for a change to show

local function say(fmt, ...)
    if GSA1.Log then pcall(GSA1.Log, "photo", fmt, ...) end
end

local function same(a, b)
    local x, y = tonumber(a), tonumber(b)
    if x and y then return x == y end
    return a == b
end

-- the world -----------------------------------------------------------------------------------------------------------------------
-- has what the last change asked run? A ConVar still showing the value from before says no; one that shows anything else, the asked value or the person's own, says yes
local function settled()
    local p = P.worldPend
    if not p then return true end
    if CurTime() < p.untilT then
        for name, v in pairs(p.was) do
            local c = GetConVar(name)
            if c and same(c:GetString(), v) then return false end
        end
    end
    P.worldPend = nil
    if p.dropMark then file.Delete(P.MARK) end
    return true
end

function P.WorldOn(ply)
    if P.world then return true end
    local w = { prev = {}, ply = ply, checkAt = CurTime() + 0.25 }
    local lines, was = {}, {}
    for _, e in ipairs(P.WORLD) do
        local c = GetConVar(e.name)
        if c then
            local v = c:GetString()
            w.prev[e.name] = v
            lines[#lines + 1] = e.name .. " " .. v
            if not same(v, e.on) then was[e.name] = v end
        end
    end
    file.Write(P.MARK, table.concat(lines, "\n"))
    for _, e in ipairs(P.WORLD) do
        if w.prev[e.name] then RunConsoleCommand(e.name, e.on) end
    end
    P.world = w
    P.worldPend = { was = was, untilT = CurTime() + P.WORLD_SETTLE }
    say("the world is frozen too (single player)")
    return true
end

-- keepMark: at ShutDown, in case the commands do not run any more: the next load finds it
function P.WorldOff(why, keepMark)
    local w = P.world
    if not w then return end
    P.world = nil
    local from = {}
    for _, e in ipairs(P.WORLD) do
        local c = GetConVar(e.name)
        local was = w.prev[e.name]
        if c and was and same(c:GetString(), e.on) and not same(was, e.on) then
            RunConsoleCommand(e.name, was)
            from[e.name] = e.on
        end
    end
    P.worldPend = { was = from, untilT = CurTime() + P.WORLD_SETTLE, dropMark = not keepMark }
    settled()
    say("the world goes on (%s)", tostring(why))
end

-- what is wanted and what is, one change at a time. Called by every message and by Think
function P.WorldStep()
    if not settled() then return end
    local ask = P.worldAsk
    if ask and not P.world then
        P.WorldOn(ask)
    elseif P.world and not ask then
        P.WorldOff(P.worldWhy)
    end
end

-- a mark from a state that ended without putting things back: a map change, a crash. Only what still has photo mode's value goes back
function P.WorldRecover()
    if not file.Exists(P.MARK, "DATA") then return end
    local text = file.Read(P.MARK, "DATA") or ""
    file.Delete(P.MARK)
    local from = {}
    for name, was in string.gmatch(text, "(%S+) (%S+)") do
        for _, e in ipairs(P.WORLD) do
            local c = e.name == name and GetConVar(name)
            if c and same(c:GetString(), e.on) and not same(was, e.on) then
                RunConsoleCommand(name, was)
                from[name] = e.on
            end
        end
    end
    P.worldPend = { was = from, untilT = CurTime() + P.WORLD_SETTLE }
    say("the world's settings put back after a map change or a crash")
end
P.WorldRecover()

local function world_mask()
    local m = 0
    for _, e in ipairs(P.WORLD) do
        local c = GetConVar(e.name)
        if c and same(c:GetString(), e.on) then m = bit.bor(m, e.bit) end
    end
    return m
end

-- a player --------------------------------------------------------------------------------------------------------------------------
-- who may be untouchable: WHO MAY at the top of this file
function P.Allowed(ply)
    return game.SinglePlayer() or ply.GSA1Active == true
end

function P.Begin(ply)
    if ply.GSA1Photo then return end
    if not P.Allowed(ply) then return end
    if ply.Alive and not ply:Alive() then return end
    ply.GSA1Photo = true
    ply.GSA1PhotoPrev = { god = ply.HasGodMode and ply:HasGodMode() or false, notarget = ply.IsFlagSet and ply:IsFlagSet(FL_NOTARGET or 65536) or false }
    if ply.GodEnable then ply:GodEnable() end
    if ply.SetNoTarget then ply:SetNoTarget(true) end
    P.active[ply] = true
end

function P.End(ply, why)
    P.active[ply] = nil
    if P.worldAsk == ply then
        P.worldAsk, P.worldWhy = nil, why
        P.WorldStep()
    end
    if not ply.GSA1Photo then return end
    local prev = ply.GSA1PhotoPrev or {}
    ply.GSA1Photo, ply.GSA1PhotoPrev, ply.GSA1PhotoEye, ply.GSA1PhotoSeen = nil, nil, nil, nil
    if IsValid(ply) then
        if not prev.god and ply.GodDisable then ply:GodDisable() end
        if not prev.notarget and ply.SetNoTarget then ply:SetNoTarget(false) end
    end
end

net.Receive(P.NET, function(len, ply)
    if not IsValid(ply) then return end
    local flags = net.ReadUInt(2)
    local eye = net.ReadBool() and net.ReadVector() or nil
    if bit.band(flags, 1) == 0 then
        P.End(ply, "photo mode ended")
        return
    end
    P.Begin(ply)
    if not ply.GSA1Photo then return end
    ply.GSA1PhotoSeen = CurTime()
    if bit.band(flags, 2) ~= 0 then
        if game.SinglePlayer() then P.worldAsk = ply end      -- (never for a server with other people on it, whoever asks: the one place a wish comes in)
    elseif P.worldAsk == ply then
        P.worldAsk, P.worldWhy = nil, "the box was unticked"
    end
    P.WorldStep()
    -- the free camera's place (RP.15): only a character's, its own rate, finite, in the world, and for those who may (single player, sv_cheats, an admin, the host), so nobody looks through walls at what is not sent to them
    if eye then
        local now = CurTime()
        if ply.GSA1Active and now - (ply.GSA1PhotoEyeAt or -1e9) >= P.EYE_EVERY and eye.x == eye.x and eye.y == eye.y and eye.z == eye.z and util.IsInWorld(eye) and GSA1.RingsRule and GSA1.RingsRule(ply) then
            ply.GSA1PhotoEye, ply.GSA1PhotoEyeAt = eye, now
        end
    end
end)

hook.Add("SetupPlayerVisibility", "gsa1_photo", function(ply)
    local e = ply.GSA1PhotoEye
    if e then AddOriginToPVS(e) end
end)

hook.Add("Think", "gsa1_photo", function()
    local now = CurTime()
    if next(P.active) then
        for ply in pairs(P.active) do
            if not IsValid(ply) then
                P.End(ply, "the player is gone")
            elseif now - (ply.GSA1PhotoSeen or now) > P.SILENT then
                P.End(ply, "the client said nothing for " .. P.SILENT .. " s")
            elseif not P.Allowed(ply) then
                P.End(ply, "the player is no character any more")
            end
        end
    end
    if P.worldAsk or P.world or P.worldPend then P.WorldStep() end
    local w = P.world
    if w and w.checkAt and now >= w.checkAt then
        -- what did not take (a cheat flag: UNVERIFIED in the game) is told to the page
        w.checkAt = nil
        if IsValid(w.ply) then
            net.Start(P.NET)
            net.WriteUInt(world_mask(), 3)
            net.Send(w.ply)
        end
    end
end)

-- nothing lands ----------------------------------------------------------------------------------------------------------------------
hook.Add("EntityTakeDamage", "gsa1_photo", function(target, dmg)
    if target.GSA1Photo then return true end
    if next(P.active) and not game.SinglePlayer() then
        local a = dmg:GetAttacker()
        if IsValid(a) and a.GSA1Photo then return true end
    end
end)
hook.Add("PlayerShouldTakeDamage", "gsa1_photo", function(ply) if ply.GSA1Photo then return false end end)
hook.Add("CanPlayerSuicide", "gsa1_photo", function(ply) if ply.GSA1Photo then return false end end)
hook.Add("GetFallDamage", "gsa1_photo", function(ply) if ply.GSA1Photo then return 0 end end)
do
    local PL = FindMetaTable and FindMetaTable("Player")
    if PL and PL.Kill then
        P.prevKill = P.prevKill or PL.Kill
        function PL.Kill(self, ...)
            if self.GSA1Photo then return end
            return P.prevKill(self, ...)
        end
    end
    if PL and PL.KillSilent then
        P.prevKillSilent = P.prevKillSilent or PL.KillSilent
        function PL.KillSilent(self, ...)
            if self.GSA1Photo then return end
            return P.prevKillSilent(self, ...)
        end
    end
end

-- the ways out that are not the client's ---------------------------------------------------------------------------------------------
hook.Add("PostPlayerDeath", "gsa1_photo", function(ply) P.End(ply, "the player died") end)
hook.Add("PlayerDisconnected", "gsa1_photo", function(ply) P.End(ply, "the player left") end)
hook.Add("ShutDown", "gsa1_photo", function()
    P.WorldOff("the map ends", true)
    for ply in pairs(P.active) do P.End(ply, "the map ends") end
end)
