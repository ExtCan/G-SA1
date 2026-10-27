-- G-SA1 interaction (round 5), server (pure Lua: no module, no disc): what the characters' hits, pushes, lifts and the
-- interact key do in Garry's Mod, and the damage a character's player takes going back to the character. The rules are
-- sh_interact.lua's; the client's side is cl_interact.lua. Design: sadc docs/libsa1_interaction.md 3.2 / 3.3 and the
-- addendum 6.1.3 / 6.2.3 / 6.3; plan gsa1_rounds_plan.md 9.3 with the owner's additions (pushing props, the interact
-- button).
--
--   * Hits (gsa1_hit): checked (the sender is a character - GSA1.IsCharacter -, the target is near enough for that
--     attack, at most one hit per target per 0.15 s, the GSA1CanDamage hook, gsa1_sv_damage) and applied as a DamageInfo
--     with the player as the attacker: each attack's own damage (gsa1_sv_dmg_<attack> x gsa1_sv_dmg_scale) and type.
--     Another player (PvP, gsa1_sv_pvp): a character victim is hit in its own game (gsa1_hurt: knocked back away from
--     the attacker, rings lost), its health only in the health / both damage modes. A balloon: popped (gsa1_sv_balloon_pop).
--   * Damage a character's player takes (EntityTakeDamage) goes to the character (gsa1_hurt) and, in the default rings
--     mode, is blocked; NPC kills by a character go back to it (gsa1_kill: E-102's time bonus); NPC relations every 0.5 s.
--   * 0.9.2 (sadc docs/research/gsa1_090_player.md L5-L8, H2 with its review): bullets count only where the character
--     is (ScalePlayerDamage, gsa1_sv_hit_shape); a character's player that dies (a NextBot's Player:Kill...) kills the
--     character too (gsa1_player_died) and comes back with it (gsa1_respawn, gsa1_sv_respawn_with_character; the
--     PlayerSpawn of sv_gsa1.lua makes it the character again in the same tick); hurt and death messages name the
--     attacker's class; the interact key never uses the player's own entities (its hands) or a base class's empty Use;
--     a released prop is lifted out of the floor before it moves again.
--   * Props: the ones a player could carry with E (prop_physics*, motion enabled, at most gsa1_sv_hold_mass kg and
--     gsa1_sv_hold_size units, AllowPlayerPickup) are tagged for the clients (NW2Bool gsa1_hold), and so is a prop's health
--     (NW2Int gsa1_hp). A lift is checked (the hooks AllowPlayerPickup and GSA1CanHold) and the prop is frozen and
--     follows the pose the holder sends; a release gives it the game's throw speed. A physics gun taking it, its removal
--     or the holder leaving drops it.
--   * Pushes (gsa1_push, owner addition A): a physics prop the character ran, rolled or spin-dashed into gets an impulse
--     by the character's and the prop's mass (sh_interact.lua I.PushDeltaV), the player's strength capped by
--     gsa1_sv_push_max; the GSA1CanPush hook can refuse.
--   * The interact key (gsa1_use, owner addition B): the usable entity in front of the character (traces along its
--     facing and tilted up, then a search around; Source's own rules for doors and buttons, any scripted entity with a
--     Use function) is used as a player's E uses it: the PlayerUse hook first, then Entity:Use with the player as
--     activator; a momentary button every tick while the key is held; while held, Player:KeyDown(IN_USE) is true for
--     that player (Sandbox's gmod_button keeps a non-toggle button on while its user holds E). A vehicle: the client is
--     told, removes the character and asks to enter (the CanPlayerEnterVehicle hook); leaving it makes the player the
--     character again (gsa1_vehicle_return).
GSA1 = GSA1 or {}
local I = GSA1.Interact
if not I then return end
local K, NET, SV = I.K, I.NET, I.svcv

for _, name in pairs(NET) do util.AddNetworkString(name) end

local function is_char(ply)
    if GSA1.IsCharacter then return GSA1.IsCharacter(ply) end
    return IsValid(ply) and ply.GSA1Active == true
end

-- the latency allowance (a fast character moves while the message travels)
local function ping_allow(ply)
    return math.min(ply:Ping(), 500) * 2
end

local function rate_ok(ply, key, interval)
    local now = CurTime()
    ply.GSA1Rate = ply.GSA1Rate or {}
    if now < (ply.GSA1Rate[key] or 0) then return false end
    ply.GSA1Rate[key] = now + interval
    return true
end

local function dist_to(ent, pos)
    local p = ent.NearestPoint and ent:NearestPoint(pos) or ent:GetPos()
    return p:Distance(pos)
end

-- hits ---------------------------------------------------------------------------------------------------------------------
local function dmg_value(attack)
    local cvar = SV.dmg[attack] or SV.dmg[0]
    return I.DamageFor(attack, SV.dmg_scale:GetFloat(), cvar and cvar:GetFloat() or nil)
end

-- the class of what hurt or killed a player, for the session log (0.9.2, L7: "world" for the map itself)
function I.ClassOf(ent)
    if not IsValid(ent) then return "world" end
    return ent:GetClass()
end

-- a character hit by another (PvP), or by the world: the victim's client hits its character (0.9.2: with the attacker's
-- class for the session log's hurt lines, L7)
function I.SendHurt(victim, amount, dtype, source, attacker, kill, pvp)
    net.Start(NET.HURT)
    net.WriteFloat(amount)
    net.WriteUInt(dtype or 0, 32)
    net.WriteVector(source)
    net.WriteUInt(IsValid(attacker) and math.Clamp(attacker:EntIndex(), 0, 65535) or 0, 16)
    net.WriteBool(kill and true or false)
    net.WriteBool(pvp and true or false)
    net.WriteString(string.sub(I.ClassOf(attacker), 1, 64))
    net.Send(victim)
end

net.Receive(NET.HIT, function(len, ply)
    if not IsValid(ply) or not is_char(ply) or not SV.damage:GetBool() then return end
    local idx = net.ReadUInt(16)
    local attack = net.ReadUInt(5)
    net.ReadUInt(2)                      -- level (informational)
    net.ReadUInt(2)                      -- damage units (informational)
    local pos = net.ReadVector()
    local dir = net.ReadNormal()
    net.ReadFloat()                      -- speed (informational)
    net.ReadUInt(4)                      -- flags
    -- several targets can be hit in one frame (a spin dash through a group, Maximum Heat, the laser): a burst of up to
    -- 16 hits per player per 0.25 s; each target's own limit (0.15 s, below) stops repeats on the same one
    local now = CurTime()
    local bucket = ply.GSA1HitBucket
    if not bucket or now - bucket.t > 0.25 then
        bucket = { t = now, n = 0 }
        ply.GSA1HitBucket = bucket
    end
    bucket.n = bucket.n + 1
    if bucket.n > 16 then return end
    local ent = Entity(idx)
    if not IsValid(ent) or ent == ply or ent:IsWorld() then return end
    if attack > I.MAX_ATTACK then attack = 0 end
    -- near enough: the attack's reach from the character, and the reported point at the target
    local reach = I.Reach(attack) + 64 + ping_allow(ply)
    if dist_to(ent, ply:GetPos()) > reach or dist_to(ent, pos) > 200 then return end
    if not rate_ok(ent, "hit_by_" .. ply:EntIndex(), 0.15) then return end
    if hook.Run("GSA1CanDamage", ply, ent, attack) == false then return end
    -- a balloon pops (its own OnTakeDamage: the pop effect, an explosive balloon explodes; an indestructible one stays)
    if ent:GetClass() == "gmod_balloon" then
        if SV.balloon_pop:GetBool() then
            local d = DamageInfo()
            d:SetDamage(1)
            d:SetAttacker(ply)
            d:SetInflictor(ply)
            d:SetDamagePosition(pos)
            ent:TakeDamageInfo(d)
        end
        return
    end
    local def = I.ATTACKS[attack]
    local amount = dmg_value(attack)
    if ent:IsPlayer() then
        if not SV.pvp:GetBool() then return end
        local mode = SV.damage_mode:GetInt()
        if is_char(ent) then
            I.SendHurt(ent, amount, def.type, ply:GetPos(), ply, false, true)
            if mode == 0 then return end
        end
        ent.GSA1NoForward = true          -- this damage was sent to the character already
    end
    local d = DamageInfo()
    d:SetAttacker(ply)
    d:SetInflictor(ply)
    d:SetDamage(amount)
    d:SetDamageType(def.type)
    d:SetDamagePosition(pos)
    d:SetDamageForce(dir * amount * 300)
    d:SetReportedPosition(ply:GetPos())
    ent:TakeDamageInfo(d)
    ent.GSA1NoForward = nil
    if ent:IsVehicle() then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then phys:ApplyForceOffset(dir * phys:GetMass() * 200, pos) end
    end
end)

-- an NPC a character damaged died: its client removes it as killed (E-102's time bonus, the marker's release)
hook.Add("OnNPCKilled", "gsa1_interact", function(npc, attacker)
    if not IsValid(npc) or not IsValid(attacker) or not attacker:IsPlayer() or not is_char(attacker) then return end
    net.Start(NET.KILL)
    net.WriteUInt(math.Clamp(npc:EntIndex(), 0, 65535), 16)
    net.Send(attacker)
end)

-- damage a character's player takes ------------------------------------------------------------------------------------------
local DMG_FALL_, DMG_DROWN_, DMG_DROWNRECOVER_ = DMG_FALL or 32, DMG_DROWN or 16384, DMG_DROWNRECOVER or 524288
hook.Add("EntityTakeDamage", "gsa1_interact", function(target, dmg)
    if not IsValid(target) or not target:IsPlayer() or not is_char(target) then return end
    if target.GSA1NoForward then return end
    local mode = SV.damage_mode:GetInt()
    local t = dmg:GetDamageType()
    -- falling does nothing to a character; drowning is the game's own (its countdown)
    if bit.band(t, DMG_FALL_) ~= 0 or bit.band(t, DMG_DROWN_) ~= 0 or bit.band(t, DMG_DROWNRECOVER_) ~= 0 then
        if mode == 0 then return true end
        return
    end
    local amount = dmg:GetDamage()
    -- a bullet refused by the hit shape (ScalePlayerDamage below set it to 0): no hit at all
    if amount <= 0 and bit.band(t, I.TRACE_DAMAGE) ~= 0 then
        if mode == 0 then return true end
        return
    end
    if amount < SV.min_damage:GetFloat() then
        if mode == 0 then return true end
        return
    end
    if mode ~= 1 and rate_ok(target, "hurt", 0.1) then
        local src = dmg:GetDamagePosition()
        local att = dmg:GetAttacker()
        if (not src or src:IsZero()) and IsValid(att) then src = att:WorldSpaceCenter() end
        I.SendHurt(target, amount, t, src or target:GetPos(), att, amount >= SV.kill_damage:GetFloat(), false)
    end
    if mode == 0 then return true end
end)

-- 0.9.2, L5 (sadc docs/research/gsa1_090_player.md review R.3.6): a trace attack (a bullet) is traced against the
-- invisible player's 72-unit model, not against the character; it hits only within I.HIT_MARGIN units of the character's
-- own cylinder (its feet: the server's last state, its size: GSA1.CHAR_SIZE). Only here and only for bullets: melee
-- (a DrGBase NextBot puts the damage position at its own centre), blasts and fire keep hitting through EntityTakeDamage.
-- Returning true stops the damage (GM:ScalePlayerDamage); the 0 damage also keeps EntityTakeDamage from a ring hit.
function I.FeetOf(ply)
    local s = ply.GSA1State
    if s and s.time and CurTime() - s.time < 1 and s.x == s.x and s.y == s.y and s.z == s.z then
        return s.x, s.y, s.z
    end
    local p = ply:GetPos()
    return p.x, p.y, p.z
end

hook.Add("ScalePlayerDamage", "gsa1_interact", function(ply, hitgroup, dmg)
    if not IsValid(ply) or not is_char(ply) or not SV.hit_shape:GetBool() then return end
    if bit.band(dmg:GetDamageType(), I.TRACE_DAMAGE) == 0 then return end
    local p = dmg:GetDamagePosition()
    if not p or (p.x == 0 and p.y == 0 and p.z == 0) then return end
    local size = I.CharSize(ply.GSA1Kind)
    local fx, fy, fz = I.FeetOf(ply)
    if I.CylinderOutside(fx, fy, fz, size.radius, size.height, p.x, p.y, p.z) <= I.HIT_MARGIN then return end
    dmg:SetDamage(0)
    ply.GSA1Missed = (ply.GSA1Missed or 0) + 1
    return true
end)

-- 0.9.2, L6 (gsa1_090_player.md 1.3 (c), (d) and the review G3 / G7; owner answer, rounds plan 14.1j: "both die and
-- respawn together"): a character's player that dies - a NextBot's Player:Kill (DrGBase's jumpscare), a script, a
-- deadly hit in the health damage modes - tells its client, which kills the character the game's way (round 5's damage
-- path with DAMAGE_KILL); when the character respawns, the client asks for the player back (gsa1_respawn below) and the
-- player comes back as the character, at it (sv_gsa1.lua PlayerSpawn). Not for the death gsa1_sv_kill_on_death caused (the
-- character died first) - and the client skips a character that is dead already.
local KILL_DAMAGE, KILL_OUTRIGHT, KILL_SILENT = 0, 1, 2

-- who killed a player outright: Player:Kill has no attacker (the player is its own), so the NPC or NextBot next to the
-- player that has it as its enemy, else the nearest within 200 units (DrGBase's jumpscare moves the player in front of
-- the animatronic first) - a guess for the session log only
function I.KillerNear(ply)
    local pos = ply:GetPos()
    local best, best_d, enemy
    for _, e in ipairs(ents.FindInSphere(pos, 200)) do
        if IsValid(e) and e ~= ply and (e:IsNPC() or (e.IsNextBot and e:IsNextBot())) then
            local d = e:GetPos():Distance(pos)
            if e.GetEnemy and e:GetEnemy() == ply and (not enemy or d < enemy[2]) then enemy = { e, d } end
            if not best_d or d < best_d then best, best_d = e, d end
        end
    end
    return enemy and enemy[1] or best
end

local function player_died(ply, attacker, how)
    if not IsValid(ply) or not ply:IsPlayer() or not (ply.GSA1Active or is_char(ply)) then return end
    ply.GSA1DiedAsChar = CurTime()                       -- (PlayerDeathThink below: the character brings it back)
    local from_char = ply.GSA1KillFromChar
    ply.GSA1KillFromChar = nil
    if from_char and CurTime() - from_char < 1 then return end      -- gsa1_sv_kill_on_death: the character died first
    local killer = attacker
    if not IsValid(killer) or killer == ply then
        if how == KILL_DAMAGE then how = KILL_OUTRIGHT end
        killer = I.KillerNear(ply)
    end
    net.Start(NET.PLAYER_DIED)
    net.WriteString(IsValid(killer) and string.sub(killer:GetClass(), 1, 64) or (attacker == ply and "itself" or "world"))
    net.WriteUInt(how, 2)
    net.WriteUInt(IsValid(killer) and math.Clamp(killer:EntIndex(), 0, 65535) or 0, 16)
    net.Send(ply)
end

hook.Add("PlayerDeath", "gsa1_interact", function(ply, inflictor, attacker)
    player_died(ply, attacker, KILL_DAMAGE)
end)
hook.Add("PlayerSilentDeath", "gsa1_interact", function(ply)
    player_died(ply, nil, KILL_SILENT)
end)

net.Receive(NET.DEAD, function(len, ply)
    if IsValid(ply) and is_char(ply) and SV.kill_on_death:GetBool() and ply:Alive() and rate_ok(ply, "dead", 2) then
        ply.GSA1KillFromChar = CurTime()                 -- (PlayerDeath: not a death to pass back to the character)
        ply:Kill()
    end
end)

-- the character respawned and its player is dead: bring the player back as the character, at the character's spawn
-- point (gsa1_sv_respawn_with_character; the gamemode's NextSpawnTime is waited for; the hook GSA1CanRespawn(ply) can
-- refuse). Done at once, or from Think once the gamemode's delay is over.
function I.RespawnThink(ply)
    local w = ply.GSA1RespawnWant
    if not w then return end
    if not IsValid(ply) or ply:Alive() or CurTime() - w.t > 30 or not SV.respawn:GetBool() then
        ply.GSA1RespawnWant = nil
        return
    end
    if ply.NextSpawnTime and CurTime() < ply.NextSpawnTime then return end
    ply.GSA1RespawnWant = nil
    if hook.Run("GSA1CanRespawn", ply) == false then return end
    ply.GSA1SpawnAsChar = { pos = w.pos, yaw = w.yaw, pitch = w.pitch, kind = w.kind }
    ply:Spawn()
    ply.GSA1SpawnAsChar = nil
end

-- while the character is to bring its dead player back, the gamemode's own respawn (base GM:PlayerDeathThink: a jump or
-- attack press once NextSpawnTime is over) waits - it would put a visible, armed player at the map's spawn point until
-- the client's 2-s gsa1_active repeat - for at most I.RESPAWN_HOLD s after the death (a client that never asks)
I.RESPAWN_HOLD = 10
hook.Add("PlayerDeathThink", "gsa1_interact", function(ply)
    if not IsValid(ply) or not SV.respawn:GetBool() or not ply.GSA1DiedAsChar or
        CurTime() - ply.GSA1DiedAsChar > I.RESPAWN_HOLD or not (ply.GSA1Active or is_char(ply)) then
        return
    end
    if ply.GSA1RespawnWant then I.RespawnThink(ply) end
    return false
end)

net.Receive(NET.RESPAWN, function(len, ply)
    if not IsValid(ply) then return end
    local pos = net.ReadVector()
    local yaw = net.ReadFloat()
    local pitch = net.ReadFloat()
    local kind = net.ReadUInt(4)
    -- (only a dead character's player is spawned, so the rate gate is only against floods: a second death soon after a
    -- respawn must not lose its request)
    if not SV.respawn:GetBool() or ply:Alive() or not (ply.GSA1Active or is_char(ply)) or
        not rate_ok(ply, "respawn", 0.1) then
        return
    end
    if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z or not util.IsInWorld(pos) then pos = nil end
    if yaw ~= yaw or pitch ~= pitch then yaw, pitch = nil, nil end
    ply.GSA1RespawnWant = { pos = pos, yaw = yaw, pitch = pitch and math.Clamp(pitch, -89, 89), kind = kind, t = CurTime() }
    I.RespawnThink(ply)
end)

-- NPC relations and the prop tags, every 0.5 s around each character --------------------------------------------------------
local D_LI_, D_NU_ = D_LI or 3, D_NU or 4
local function relation_of(npc, ply)
    if not npc.Disposition then return I.REL_HOSTILE end
    local d = npc:Disposition(ply)
    if d == D_LI_ then return I.REL_FRIENDLY end
    if d == D_NU_ then return I.REL_NEUTRAL end
    return I.REL_HOSTILE
end

-- a prop a player could carry with E (Source's +use pickup: physics props with motion, the mass and size limits)
function I.Liftable(ent)
    if not IsValid(ent) or not string.find(ent:GetClass(), "^prop_physics") then return false end
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) or not phys:IsMoveable() then return false end
    if phys:GetMass() > SV.hold_mass:GetFloat() then return false end
    local mn, mx = ent:OBBMins(), ent:OBBMaxs()
    if math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) > SV.hold_size:GetFloat() then return false end
    return true
end

local function tag(ent)
    local cls = ent:GetClass()
    local hold = SV.hold:GetBool() and (ent.GSA1HeldBy ~= nil or I.Liftable(ent))
    if ent:GetNW2Bool("gsa1_hold", false) ~= hold then ent:SetNW2Bool("gsa1_hold", hold) end
    if string.find(cls, "^prop_physics") or I.BREAKABLES[cls] then
        local hp = math.max(0, math.floor(ent:Health()))
        if ent:GetNW2Int("gsa1_hp", 0) ~= hp then ent:SetNW2Int("gsa1_hp", hp) end
    end
end

local next_scan = 0
local function scan_around()
    local now = CurTime()
    if now < next_scan then return end
    next_scan = now + 0.5
    for _, ply in ipairs(player.GetAll()) do
        if is_char(ply) then
            local changes = {}
            ply.GSA1Rel = ply.GSA1Rel or {}
            for _, e in ipairs(ents.FindInSphere(ply:GetPos(), 3000)) do
                if e.GSA1Object then
                    -- 0.9.4: a G-SA1 game object (feat/sh_objects.lua) is never a host object (no tag, no relation)
                elseif e:IsNPC() then
                    local idx = e:EntIndex()
                    local r = relation_of(e, ply)
                    if ply.GSA1Rel[idx] ~= r and #changes < 1000 then
                        ply.GSA1Rel[idx] = r
                        changes[#changes + 1] = { idx, r }
                    end
                elseif e:GetMoveType() == MOVETYPE_VPHYSICS or I.BREAKABLES[e:GetClass()] then
                    tag(e)
                end
            end
            if #changes > 0 then
                net.Start(NET.REL)
                net.WriteUInt(#changes, 10)
                for _, c in ipairs(changes) do
                    net.WriteUInt(math.Clamp(c[1], 0, 65535), 16)
                    net.WriteUInt(c[2], 2)
                end
                net.Send(ply)
            end
        end
    end
end

-- holding props ---------------------------------------------------------------------------------------------------------------
local held = {}                          -- [prop] = holder

-- 0.9.2, H2 (gsa1_090_player.md P2): where a released prop goes - its origin `origin`, lifted in steps (0, 2, 8, 16 units,
-- then its own height) until its box there is free of the world and other solids (the game's release point is its centre
-- at the hands: an oil drum put down by Sonic went 12.3 units into the floor before VPhysics took it); the first free
-- one, else `origin` unchanged
function I.FreeSpot(ent, origin, ply)
    local _, _, _, lo, hi = I.TurnedBox(ent:OBBMins(), ent:OBBMaxs(), ent:GetAngles())
    local mins, maxs = Vector(lo.x, lo.y, lo.z), Vector(hi.x, hi.y, hi.z)
    local filter = { ent }
    if IsValid(ply) then filter[2] = ply end
    local lifts = { unpack(I.RELEASE_LIFTS) }
    lifts[#lifts + 1] = math.max(hi.z - lo.z, 16)
    for _, up in ipairs(lifts) do
        local p = origin + Vector(0, 0, up)
        local tr = util.TraceHull({ start = p, endpos = p, mins = mins, maxs = maxs, filter = filter, mask = MASK_SOLID })
        if not (tr and tr.StartSolid) then return p end
    end
    return origin
end

function I.ReleaseProp(ent, pos, vel, notify)
    local ply = ent.GSA1HeldBy
    held[ent] = nil
    if not IsValid(ent) then return end
    local prev = ent.GSA1HoldPrev or {}
    ent.GSA1HeldBy = nil
    ent.GSA1HoldPrev = nil
    ent:SetNW2Entity("gsa1_holder", NULL)
    if prev.group then ent:SetCollisionGroup(prev.group) end
    if pos and IsValid(ply) and pos:Distance(ply:GetPos()) < 400 then
        local off = ent:OBBCenter()          -- pos is the prop's centre (where the game released it)
        off:Rotate(ent:GetAngles())
        ent:SetPos(I.FreeSpot(ent, pos - off, ply))
    end
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        if prev.motion ~= false then phys:EnableMotion(true) end
        phys:Wake()
        if vel then
            local l = vel:Length()
            if l > 3000 then vel = vel * (3000 / l) end
            phys:SetVelocity(vel)
        end
    end
    if IsValid(ply) then
        ply.GSA1Held = nil
        if ent.SetPhysicsAttacker then ent:SetPhysicsAttacker(ply, 5) end
        if notify then
            net.Start(NET.HOLD_DROP)
            net.WriteUInt(ent:EntIndex(), 16)
            net.Send(ply)
        end
    end
end

local function deny(ply, idx)
    net.Start(NET.HOLD_DENY)
    net.WriteUInt(idx, 16)
    net.Send(ply)
end

net.Receive(NET.HOLD, function(len, ply)
    if not IsValid(ply) then return end
    local idx = net.ReadUInt(16)
    local on = net.ReadBool()
    local ent = Entity(idx)
    if on then
        if not is_char(ply) or not SV.hold:GetBool() or not IsValid(ent) or not ent:GetNW2Bool("gsa1_hold", false) or
            (ent.IsPlayerHolding and ent:IsPlayerHolding()) or (IsValid(ent.GSA1HeldBy) and ent.GSA1HeldBy ~= ply) or
            IsValid(ply.GSA1Held) or dist_to(ent, ply:GetPos()) > 200 + ping_allow(ply) or not I.Liftable(ent) or
            hook.Run("AllowPlayerPickup", ply, ent) == false or hook.Run("GSA1CanHold", ply, ent) == false then
            deny(ply, idx)
            return
        end
        local phys = ent:GetPhysicsObject()
        ent.GSA1HoldPrev = { group = ent:GetCollisionGroup(), motion = phys:IsMotionEnabled() }
        ent.GSA1HeldBy = ply
        ent.GSA1HoldAng = ent:GetAngles()
        ent:SetNW2Entity("gsa1_holder", ply)
        phys:EnableMotion(false)
        ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        ply.GSA1Held = ent
        held[ent] = ply
    else
        local pos = net.ReadVector()
        local vel = net.ReadVector()
        net.ReadUInt(3)
        if IsValid(ent) and ent.GSA1HeldBy == ply then I.ReleaseProp(ent, pos, vel, false) end
    end
end)

net.Receive(NET.HOLD_POSE, function(len, ply)
    if not IsValid(ply) then return end
    local idx = net.ReadUInt(16)
    local pos = net.ReadVector()
    local yaw = net.ReadFloat()
    local ent = Entity(idx)
    if not IsValid(ent) or ent.GSA1HeldBy ~= ply or yaw ~= yaw then return end
    if pos:Distance(ply:GetPos()) > 300 + ping_allow(ply) then return end
    local a = ent.GSA1HoldAng or ent:GetAngles()
    local ang = Angle(a.p, yaw, a.r)
    local off = ent:OBBCenter()
    off:Rotate(ang)
    ent:SetAngles(ang)
    ent:SetPos(pos - off)
end)

-- the ends of a hold that are the server's
hook.Add("OnPhysgunPickup", "gsa1_interact", function(ply, ent)
    if IsValid(ent) and ent.GSA1HeldBy then I.ReleaseProp(ent, nil, nil, true) end
end)
hook.Add("AllowPlayerPickup", "gsa1_interact", function(ply, ent)
    if IsValid(ent) and IsValid(ent.GSA1HeldBy) and ent.GSA1HeldBy ~= ply then return false end
end)
hook.Add("GravGunPickupAllowed", "gsa1_interact", function(ply, ent)
    if IsValid(ent) and IsValid(ent.GSA1HeldBy) and ent.GSA1HeldBy ~= ply then return false end
end)
hook.Add("EntityRemoved", "gsa1_interact", function(ent)
    local ply = held[ent]
    if ply == nil then return end
    held[ent] = nil
    if IsValid(ply) then
        ply.GSA1Held = nil
        net.Start(NET.HOLD_DROP)
        net.WriteUInt(ent:EntIndex(), 16)
        net.Send(ply)
    end
end)

local function holds_think()
    for ent, ply in pairs(held) do
        if not IsValid(ent) then
            held[ent] = nil
        elseif not IsValid(ply) or not is_char(ply) or not ply:Alive() then
            I.ReleaseProp(ent, nil, Vector(0, 0, 0), IsValid(ply))
        end
    end
end

-- pushes (owner addition A) -----------------------------------------------------------------------------------------------------
function I.Pushable(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWorld() then return false end
    if ent:GetMoveType() ~= MOVETYPE_VPHYSICS or IsValid(ent.GSA1HeldBy) then return false end
    if ent.IsPlayerHolding and ent:IsPlayerHolding() then return false end
    local phys = ent:GetPhysicsObject()
    return IsValid(phys) and phys:IsMoveable()
end

net.Receive(NET.PUSH, function(len, ply)
    if not IsValid(ply) then return end
    local n = net.ReadUInt(4)
    local list = {}
    for i = 1, math.min(n, 8) do
        list[i] = { idx = net.ReadUInt(16), dir = net.ReadNormal(), point = net.ReadVector(), vin = net.ReadFloat(),
                    rolling = net.ReadBool(), typ = net.ReadUInt(2), first = net.ReadBool() }
    end
    local strength = net.ReadFloat()
    local roll = net.ReadFloat()
    if not is_char(ply) or not SV.push:GetBool() or not rate_ok(ply, "push", 1 / 45) then return end
    if strength ~= strength or roll ~= roll then return end
    local mc = I.CHAR_MASS[ply.GSA1Kind or 0] or 60
    for _, r in ipairs(list) do
        local ent = Entity(r.idx)
        local vin = r.vin
        if (r.typ == K.CONTACT_SIDE or r.typ == K.CONTACT_HEAD) and vin == vin and I.Pushable(ent) and
            dist_to(ent, ply:GetPos()) <= I.PUSH_REACH + ping_allow(ply) and r.point:Distance(ply:GetPos()) < 200 and
            hook.Run("GSA1CanPush", ply, ent) ~= false then
            local phys = ent:GetPhysicsObject()
            local dir = r.dir
            if r.typ == K.CONTACT_SIDE then
                dir = Vector(dir.x, dir.y, 0)
                if dir:Length() < 0.2 then dir = nil else dir:Normalize() end
            else
                dir = Vector(0, 0, 1)
            end
            if dir then
                local k = I.PushFactor(strength, r.rolling, roll, SV.push_max:GetFloat())
                local m = phys:GetMass()
                local dv = I.PushDeltaV(math.min(vin, 4000), phys:GetVelocity():Dot(dir), mc, m, k)
                if dv > 0 then
                    phys:Wake()
                    phys:ApplyForceOffset(dir * (m * dv), r.point)
                    if ent.SetPhysicsAttacker then ent:SetPhysicsAttacker(ply, 2) end
                end
            end
        end
    end
end)

-- the interact key (owner addition B) ----------------------------------------------------------------------------------------
-- 0.9.2, L8 (gsa1_090_player.md, side finding; 26 "used (gmod_hands)" lines in the owner's logs): a scripted entity is
-- usable when its own class or a class it is built on defines Use - not when the first Use up its Base chain is one of
-- the base classes' empty ones (base_anim's ENT:Use does nothing, and gmod_hands inherits it)
I.EMPTY_USE_BASES = { base_anim = true, base_entity = true, base_gmodentity = true, base_ai = true, base_nextbot = true,
                      base_point = true, base_brush = true, base_filter = true }
local sent_use = {}
local function scripted_use(cls)
    local v = sent_use[cls]
    if v == nil then
        v = false
        if scripted_ents.GetStored then
            local c = cls
            for _ = 1, 16 do
                local st = c and scripted_ents.GetStored(c)
                local t = type(st) == "table" and st.t
                if type(t) ~= "table" then break end
                if type(rawget(t, "Use")) == "function" then
                    v = not I.EMPTY_USE_BASES[c]
                    break
                end
                local base = st.Base or t.Base
                if base == c then break end
                c = base
            end
        else
            local t = scripted_ents.Get and scripted_ents.Get(cls)
            v = type(t) == "table" and type(t.Use) == "function"
        end
        sent_use[cls] = v
    end
    return v
end

-- the player's own entities are never used: itself, its hands, its view model, what it owns in the engine's sense
-- (Entity:GetOwner: the hands, the weapons, their projectiles)
function I.OwnEntity(ply, e)
    if not IsValid(ply) or not IsValid(e) then return false end
    if e == ply then return true end
    if e.GetOwner and e:GetOwner() == ply then return true end
    if ply.GetHands and ply:GetHands() == e then return true end
    if ply.GetViewModel and ply:GetViewModel() == e then return true end
    return false
end

-- what using an entity means (the entity itself, else its parents: the engine's own use search does the same); ply: the
-- user (its own entities are not usable)
function I.UsableKind(ent, ply)
    local e = ent
    for _ = 1, 4 do
        if not IsValid(e) or e:IsWorld() or I.OwnEntity(ply, e) then return nil end
        local inf = { class = e:GetClass(), vehicle = e:IsVehicle(), player = e:IsPlayer(), npc = e:IsNPC(),
                      weapon = e:IsWeapon(), sent_use = e:IsScripted() and scripted_use(e:GetClass()),
                      spawnflags = function(f) return e:HasSpawnFlags(f) end }
        local kind = I.UseKind(inf)
        if kind then return e, kind end
        e = e:GetParent()
    end
    return nil
end

local function use_env(ply)
    local filter = { ply }
    local hands = ply.GetHands and ply:GetHands()
    if IsValid(hands) then filter[#filter + 1] = hands end
    return {
        trace = function(a, b)
            local tr = util.TraceHull({ start = Vector(a.x, a.y, a.z), endpos = Vector(b.x, b.y, b.z),
                                        mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6), filter = filter,
                                        mask = bit.bor(MASK_SOLID, CONTENTS_DEBRIS or 0x4000000) })
            if tr.Hit and IsValid(tr.Entity) then return { ent = tr.Entity, pos = tr.HitPos } end
            return nil
        end,
        usable = function(e) return I.UsableKind(e, ply) end,
        around = function(o, r)
            local out = {}
            local c = Vector(o.x, o.y, o.z)
            for _, e in ipairs(ents.FindInSphere(c, r)) do
                if not e:IsWorld() and not I.OwnEntity(ply, e) then
                    out[#out + 1] = { ent = e, point = e:NearestPoint(c) }
                end
            end
            return out
        end,
        visible = function(o, p, e)
            local tr = util.TraceLine({ start = Vector(o.x, o.y, o.z), endpos = Vector(p.x, p.y, p.z), filter = filter,
                                        mask = MASK_SOLID })
            return not tr.Hit or tr.Fraction > 0.97 or tr.Entity == e
        end,
    }
end

local function use_result(ply, r, ent)
    net.Start(NET.USE_RESULT)
    net.WriteUInt(r, 3)
    net.WriteUInt(IsValid(ent) and math.Clamp(ent:EntIndex(), 0, 65535) or 0, 16)
    net.Send(ply)
end

net.Receive(NET.USE, function(len, ply)
    if not IsValid(ply) then return end
    local press = net.ReadBool()
    if not press then
        ply.GSA1Using = nil
        ply.GSA1UseHeld = nil
        return
    end
    local pos = net.ReadVector()
    local yaw = net.ReadFloat()
    local center = net.ReadFloat()
    local vehicles = net.ReadBool()
    if not is_char(ply) or not rate_ok(ply, "use", 0.1) then return end
    if not SV.interact:GetBool() then
        use_result(ply, I.USE_OFF)
        return
    end
    if yaw ~= yaw or center ~= center or pos:Distance(ply:GetPos()) > 160 + ping_allow(ply) then return end
    local origin = Vector(pos.x, pos.y, pos.z + math.Clamp(center, 0, 64))
    local r = math.rad(yaw)
    local ent, kind = I.FindUseTarget(origin, math.cos(r), math.sin(r), SV.interact_reach:GetFloat(), use_env(ply))
    if not ent then
        use_result(ply, I.USE_NOTHING)
        return
    end
    if kind == "vehicle" then
        if vehicles and SV.interact_vehicles:GetBool() and hook.Run("CanPlayerEnterVehicle", ply, ent, 0) ~= false then
            net.Start(NET.USE_VEHICLE)
            net.WriteUInt(ent:EntIndex(), 16)
            net.Send(ply)
            use_result(ply, I.USE_VEHICLE, ent)
        else
            use_result(ply, I.USE_DENIED, ent)
        end
        return
    end
    if hook.Run("PlayerUse", ply, ent) == false then
        use_result(ply, I.USE_DENIED, ent)
        return
    end
    ply.GSA1UseHeld = true
    ent:Use(ply, ply, USE_ON or 1, 1)
    if kind == "continuous" then ply.GSA1Using = ent end
    use_result(ply, I.USE_USED, ent)
end)

-- a momentary button turns while the key is held (the engine's continuous use: every tick)
local function using_think()
    for _, ply in ipairs(player.GetAll()) do
        local ent = ply.GSA1Using
        if ent ~= nil then
            if not IsValid(ent) or not is_char(ply) or dist_to(ent, ply:GetPos()) > SV.interact_reach:GetFloat() + 96 then
                ply.GSA1Using = nil
            elseif hook.Run("PlayerUse", ply, ent) ~= false then
                ent:Use(ply, ply, USE_TOGGLE or 3, 0)
            end
        end
        if ply.GSA1UseHeld and not is_char(ply) then ply.GSA1UseHeld = nil end
    end
end

-- Player:KeyDown(IN_USE) for a character holding the interact key after a use (Sandbox's gmod_button keeps a non-toggle
-- button on while its user holds E); every other key and player as Garry's Mod has it
local PLY = FindMetaTable and FindMetaTable("Player")
if PLY and PLY.KeyDown and not PLY.GSA1KeyDownWrapped then
    local key_down = PLY.KeyDown
    PLY.GSA1KeyDownWrapped = true
    PLY.KeyDown = function(self, key)
        if key == IN_USE and self.GSA1UseHeld then return true end
        return key_down(self, key)
    end
end

-- vehicles: the client removed its character; enter now (and remember to give it back)
net.Receive(NET.ENTER_VEHICLE, function(len, ply)
    if not IsValid(ply) then return end
    local idx = net.ReadUInt(16)
    local kind = net.ReadUInt(4)
    local veh = Entity(idx)
    if not IsValid(veh) or is_char(ply) or not ply:Alive() or ply:InVehicle() or not SV.interact_vehicles:GetBool() then
        return
    end
    if dist_to(veh, ply:GetPos()) > 250 + ping_allow(ply) then return end
    if hook.Run("CanPlayerEnterVehicle", ply, veh, 0) == false then return end
    if veh:IsVehicle() then
        ply:EnterVehicle(veh)
    else
        veh:Use(ply, ply, USE_ON or 1, 1)            -- a scripted vehicle (LVS, simfphys) seats its driver itself
    end
    ply.GSA1VehicleReturn = kind < 15 and kind or nil
end)

hook.Add("PlayerLeaveVehicle", "gsa1_interact", function(ply, veh)
    local kind = ply.GSA1VehicleReturn
    if kind == nil then return end
    ply.GSA1VehicleReturn = nil
    net.Start(NET.VEHICLE_LEFT)
    net.WriteUInt(kind, 4)
    net.Send(ply)
end)

hook.Add("PlayerDisconnected", "gsa1_interact", function(ply)
    if IsValid(ply.GSA1Held) then I.ReleaseProp(ply.GSA1Held, nil, nil, false) end
end)

hook.Add("Think", "gsa1_interact", function()
    scan_around()
    holds_think()
    using_think()
    for _, ply in ipairs(player.GetAll()) do
        if ply.GSA1RespawnWant then I.RespawnThink(ply) end
    end
end)
