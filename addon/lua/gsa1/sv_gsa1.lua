-- G-SA1 server side (pure Lua; the server needs neither the module nor a disc).
--
-- A player who spawns a character tells the server (gsa1_active); while active the server keeps the player
-- entity at the character's reported position (gsa1_state) so that PVS, sounds, triggers that test the player's
-- origin and other addons see the player where the character is. Validation: only the sender's own player, rate
-- limited, finite numbers inside the map. The player is invisible and noclipped while active and is put back on
-- its feet (at the character, when that spot is free) afterwards.
--
-- 0.8.0, the weapon (sadc docs/research/gsa1_060_weapon.md with its review; the 0.6.0 owner test: "Entering character
-- mode with a weapon keeps the weapons effects visible (Physics Gun light)"): while a character the player's weapon is
-- put away - a switch to the empty gsa1_hands (sh_net.lua), so the old weapon's own Holster runs; a Gravity Gun lets
-- go of what it holds first - retried every 0.2 s while a weapon refuses, and forced after 1 s (SetActiveWeapon, the
-- G64 / SkateGM way, as a last resort). The weapon held before is given back when the character ends (else the default
-- weapon). Meanwhile: no other weapon becomes active (the gate in sh_net.lua; pickups go into the inventory), the
-- weapon's world model is hidden for every player (DrawWorldModel) and its view model too, the flashlight is off and
-- cannot be switched on, and the NW2 flag GSA1.NW_CHAR (GSA1.IsCharacter) tells every client that the player is a
-- character. The hands are removed by the Think hook a tick after the character ends: Entity:Remove takes effect at
-- the start of the next tick, so removing them at once and putting the weapon away again in the same tick (remove and
-- spawn in one console line) would select the dying hands (review R.3.2). No option: putting the weapon away is part
-- of being the character (owner default, rounds plan 14.1d).
--
-- 0.9.2a, teleports (sadc docs/research/gsa1_091a_teleport.md T0; feat/sh_teleport.lua, feat/sv_teleport.lua): G-SA1 is
-- the only thing that moves a character player's entity, so every placement goes through GSA1.PlacePlayer (it records
-- it), the state receiver first asks GSA1.TeleportGate (a teleport found or waiting for the client: the packet is
-- dropped), and activate / deactivate / PlayerSpawn clear the record (GSA1.ClearPlacement).
util.AddNetworkString(GSA1.NET_ACTIVE)
util.AddNetworkString(GSA1.NET_STATE)

local follow = CreateConVar("gsa1_sv_follow", "1", FCVAR_ARCHIVE, "Move a player's entity along with their G-SA1 character")
local MAX_RATE = 40          -- state packets per second accepted per player
local HANDS = GSA1.HANDS
local HOLSTER_RETRY = 0.2    -- s between attempts to put a refusing weapon away
local HOLSTER_FORCE = 1.0    -- s after which the hands are made active without the old weapon's Holster

local function hull_free(ply, pos)
    local mins, maxs = ply:GetHull()
    local tr = util.TraceHull({ start = pos, endpos = pos, mins = mins, maxs = maxs,
                                mask = MASK_PLAYERSOLID, filter = ply })
    return not tr.StartSolid
end

-- a weapon whose removal is pending (Entity:Remove takes effect at the start of the next tick)
local function dying(w)
    return w.IsMarkedForDeletion ~= nil and w:IsMarkedForDeletion() == true
end

-- put away: the empty hands, or no weapon at all, are active
local function holstered(ply)
    local w = ply:GetActiveWeapon()
    return not IsValid(w) or (w:GetClass() == HANDS and not dying(w))
end

-- put the active weapon away: an ordinary switch to the hands (the old weapon's Holster runs); true when it held
local function holster(ply, force)
    if holstered(ply) then return true end
    -- the Gravity Gun refuses to holster while it holds something (HL2's CWeaponPhysCannon::Holster): let go first
    -- (Player:DropObject / Entity:ForcePlayerDrop release Gravity Gun, Physics Gun and +use holds)
    if IsValid(ply.GSA1GravHeld) then ply.GSA1GravHeld:ForcePlayerDrop() end
    ply:DropObject()
    local hands = ply:GetWeapon(HANDS)
    if IsValid(hands) and dying(hands) then
        hands = nil                          -- being removed: given again by a later attempt, once it is gone
    elseif not IsValid(hands) then
        ply:Give(HANDS)                      -- (a gamemode that refuses pickups refuses it: the forced fallback below)
        hands = ply:GetWeapon(HANDS)
    end
    if holstered(ply) then return true end
    if IsValid(hands) then ply:SelectWeapon(HANDS) end
    if holstered(ply) then return true end
    if force then
        -- the old weapon still refuses (its Holster returns false), or there are no hands: make the hands (or no
        -- weapon) active without the old weapon's Holster
        ply:SetActiveWeapon(IsValid(hands) and hands or NULL)
    end
    return holstered(ply)
end

-- give the weapon held before back (cls nil: there was none); the hands go a tick later (the Think hook)
local function unholster(ply, cls)
    if ply:Alive() and cls then
        if ply:HasWeapon(cls) then ply:SelectWeapon(cls) end
        local w = ply:GetActiveWeapon()
        if not IsValid(w) or w:GetClass() == HANDS then ply:SwitchToDefaultWeapon() end  -- gone or refused: the default
    end
    ply.GSA1DropHands = true
end

-- 0.9.2a: a placement of a character player (recorded by the teleport feature; a plain SetPos without it)
local function place(ply, pos, ang, force)
    if GSA1.PlacePlayer then return GSA1.PlacePlayer(ply, pos, ang, force) end
    ply:SetPos(pos)
    if ang then ply:SetEyeAngles(ang) end
    return true
end
local function clear_placement(ply)
    if GSA1.ClearPlacement then GSA1.ClearPlacement(ply) end
end

local function activate(ply, kind)
    ply.GSA1Active = true
    ply.GSA1Kind = kind
    ply.GSA1DropHands = nil
    clear_placement(ply)
    local w = ply:GetActiveWeapon()
    ply.GSA1Prev = { movetype = ply:GetMoveType(), nodraw = ply:GetNoDraw(),
                     weapon = IsValid(w) and w:GetClass() ~= HANDS and w:GetClass() or nil }
    ply:SetNW2Bool(GSA1.NW_CHAR, true)
    if follow:GetBool() then
        ply:SetMoveType(MOVETYPE_NOCLIP)
    end
    ply:SetNoDraw(true)
    ply:DrawShadow(false)
    ply:DrawWorldModel(false)
    ply:DrawViewModel(false)
    if ply:FlashlightIsOn() then ply:Flashlight(false) end
    ply.GSA1HolsterSince = CurTime()
    ply.GSA1HolsterNext = CurTime() + HOLSTER_RETRY
    holster(ply, false)
end

local function deactivate(ply, pos)
    if not ply.GSA1Active then return end
    ply.GSA1Active = false
    clear_placement(ply)
    ply:SetNW2Bool(GSA1.NW_CHAR, false)          -- first: the switch gate lets the weapon held before back
    local prev = ply.GSA1Prev or {}
    ply:SetMoveType(prev.movetype or MOVETYPE_WALK)
    ply:SetNoDraw(prev.nodraw or false)
    ply:DrawShadow(true)
    ply:DrawWorldModel(true)
    ply:DrawViewModel(true)                      -- before the switch: a restored weapon's Deploy may still hide it
    unholster(ply, prev.weapon)
    ply:DrawWorldModel(true)                     -- again after it (whether the setting survives a switch is undocumented)
    if pos and util.IsInWorld(pos) then
        for _, up in ipairs({ 2, 16, 40, 72 }) do
            local p = pos + Vector(0, 0, up)
            if hull_free(ply, p) then
                ply:SetPos(p)
                break
            end
        end
    end
    ply:SetVelocity(-ply:GetVelocity())
    ply.GSA1State = nil
end

net.Receive(GSA1.NET_ACTIVE, function(len, ply)
    if not IsValid(ply) then return end
    local on = net.ReadBool()
    if on then
        local kind = net.ReadUInt(4)
        -- a character switch (cl_character.lua sends only "on" with the new kind) or the client's 2-second repeat
        if ply.GSA1Active then ply.GSA1Kind = kind return end
        activate(ply, kind)
    else
        local pos = net.ReadVector()
        deactivate(ply, pos)
    end
end)

net.Receive(GSA1.NET_STATE, function(len, ply)
    if not IsValid(ply) or not ply.GSA1Active then return end
    local now = SysTime()
    if now - (ply.GSA1LastState or 0) < 1 / MAX_RATE then return end
    ply.GSA1LastState = now
    local s = GSA1.Net.ReadState()
    local pos = Vector(s.x, s.y, s.z)
    if s.x ~= s.x or s.y ~= s.y or s.z ~= s.z or not util.IsInWorld(pos) then return end
    local following = follow:GetBool() and ply:GetMoveType() == MOVETYPE_NOCLIP
    -- 0.9.2a: a teleport of the hidden player found now, or one the client has not confirmed yet: this packet is from
    -- before the client moved the character there (feat/sv_teleport.lua)
    if following and GSA1.TeleportGate and GSA1.TeleportGate(ply, pos) then return end
    s.time = CurTime()
    ply.GSA1State = s              -- the relay hook for remote puppets (sh_net.lua)
    if following then
        place(ply, pos)
    end
end)

-- the weapon stays put away (a weapon that refused to holster, the loadout after a respawn, a weapon an addon made
-- active with SetActiveWeapon: retried, forced 1 s after it was last put away); the hands of a player who stopped
-- being a character go
hook.Add("Think", "gsa1_holster", function()
    local now = CurTime()
    for _, ply in ipairs(player.GetAll()) do
        if ply.GSA1Active then
            if not ply:Alive() then
                ply.GSA1HolsterSince = now
            elseif holstered(ply) then
                ply.GSA1HolsterSince = now
            elseif now >= (ply.GSA1HolsterNext or 0) then
                ply.GSA1HolsterNext = now + HOLSTER_RETRY
                holster(ply, now - (ply.GSA1HolsterSince or now) >= HOLSTER_FORCE)
            end
        elseif ply.GSA1DropHands then
            ply.GSA1DropHands = nil
            local hands = ply:GetWeapon(HANDS)
            if IsValid(hands) then hands:Remove() end
        end
    end
end)

-- what the player's Gravity Gun holds (dropped before it is put away)
hook.Add("GravGunOnPickedUp", "gsa1", function(ply, ent) ply.GSA1GravHeld = ent end)
hook.Add("GravGunOnDropped", "gsa1", function(ply, ent)
    if ply.GSA1GravHeld == ent then ply.GSA1GravHeld = nil end
end)

-- a character is the player's body: no fall damage, no noclip toggling, no flashlight while active
hook.Add("GetFallDamage", "gsa1", function(ply)
    if ply.GSA1Active then return 0 end
end)

hook.Add("PlayerNoClip", "gsa1", function(ply, desired)
    if ply.GSA1Active then return false end
end)

hook.Add("PlayerSwitchFlashlight", "gsa1", function(ply, on)
    if ply.GSA1Active and on then return false end
end)

-- a respawn while a character (killed): the player is back in the game with the gamemode's loadout; the client keeps
-- its character and repeats gsa1_active within 2 s, which makes the player a character again and puts the new weapon
-- away.
-- 0.9.2 (sadc docs/research/gsa1_090_player.md L6, owner answer: the player and the character die and come back
-- together): the respawn the character asked for (it respawned after the player's death: feat/sv_interact.lua sets
-- GSA1SpawnAsChar around Player:Spawn) keeps the player the character in this same tick - before the gamemode's loadout,
-- so no weapon comes out (the switch gate of sh_net.lua) and no visible player stands at the spawn point - at the
-- character's position and view; GSA1Prev keeps what the player held before the character
hook.Add("PlayerSpawn", "gsa1", function(ply)
    local again = ply.GSA1SpawnAsChar
    ply.GSA1SpawnAsChar = nil
    if again and ply.GSA1Active then
        local prev = ply.GSA1Prev
        ply.GSA1Active = false
        activate(ply, again.kind or ply.GSA1Kind or 0)
        ply.GSA1Prev = prev or ply.GSA1Prev
        if again.yaw then ply:SetEyeAngles(Angle(again.pitch or 0, again.yaw, 0)) end
        if again.pos then place(ply, again.pos, nil, true) end   -- a G-SA1 placement (0.9.2a: recorded, no teleport)
        return
    end
    clear_placement(ply)
    if ply.GSA1Active then
        ply.GSA1Active = false
        ply:SetNW2Bool(GSA1.NW_CHAR, false)
        ply:SetNoDraw(false)
        ply:DrawShadow(true)
        ply:DrawWorldModel(true)
        ply:DrawViewModel(true)
        ply.GSA1DropHands = true
    end
end)

hook.Add("PlayerDisconnected", "gsa1", function(ply)
    ply.GSA1Active = false
end)
