-- G-SA1 feature "teleport", server part (0.9.2a; sadc docs/research/gsa1_091a_teleport.md T0 with its review R.4; the
-- rule and the messages: feat/sh_teleport.lua). sv_gsa1.lua places a character player only through GSA1.PlacePlayer
-- and asks GSA1.TeleportGate before applying a state packet; activate / deactivate / PlayerSpawn clear the record
-- (GSA1.ClearPlacement).
local P = GSA1.Teleport
util.AddNetworkString(P.NET)
util.AddNetworkString(P.NET_ACK)

-- what happened (gsa1_teleport_status; the feature test reads it)
P.Stats = P.Stats or { detected = 0, sent = 0, dropped = 0, acked = 0, timeouts = 0, loops = 0, suppressed = 0,
                       kept_out = 0, stale_acks = 0, stayed = 0 }
P.STAY_TIME, P.STAY_NEAR = 8.0, 64   -- a "confirmed only" teleport: packets from within 64 units of where it began are
                                     -- dropped for up to 8 s (a death playing out in a teleporter; review R-b)
local TS = P.Stats
local EF_NOINTERP_BIT = EF_NOINTERP or 8
local OBS_NONE = OBS_MODE_NONE or 0

-- the map's teleporters (trigger_teleport boxes), for "Map teleporters move my character" off and for the cause
P.boxes = P.boxes or nil
function P.RefreshBoxes()
    local out = {}
    for _, e in ipairs(ents.FindByClass and ents.FindByClass("trigger_teleport") or {}) do
        if IsValid(e) and e.WorldSpaceAABB then
            local mins, maxs = e:WorldSpaceAABB()
            if mins and maxs then out[#out + 1] = { ent = e, mins = mins, maxs = maxs } end
        end
    end
    P.boxes = out
    return out
end
hook.Add("InitPostEntity", "gsa1_teleport", function() P.RefreshBoxes() end)
hook.Add("PostCleanupMap", "gsa1_teleport", function() P.RefreshBoxes() end)

local function box_at(pos)
    for _, b in ipairs(P.boxes or P.RefreshBoxes()) do
        if P.HullInBox(pos, b.mins, b.maxs) then return b end
    end
    return nil
end

-- the name a teleporter sends to (its target keyvalue), for the session log
local function target_of(e)
    if not IsValid(e) then return "?" end
    local t
    if e.GetInternalVariable then
        local ok, v = pcall(e.GetInternalVariable, e, "target")
        if ok and type(v) == "string" and v ~= "" then t = v end
        if not t then
            ok, v = pcall(e.GetInternalVariable, e, "m_target")
            if ok and type(v) == "string" and v ~= "" then t = v end
        end
    end
    if not t and e.GetKeyValues then
        local ok, kv = pcall(e.GetKeyValues, e)
        if ok and type(kv) == "table" and type(kv.target) == "string" then t = kv.target end
    end
    return t or "?"
end

-- the cause of a move away from `from` (where G-SA1 had put the player)
local function cause_of(from)
    P.RefreshBoxes()
    local b = box_at(from)
    if b then return "trigger_teleport -> " .. target_of(b.ent) end
    return "moved by the map or another addon"
end

-- Every G-SA1 placement of a character player (the state receiver, the respawn as a character): sets the origin and
-- records it. With "Map teleporters move my character" off a spot whose hull overlaps a trigger_teleport is not taken
-- (the player stays at its last spot outside: the teleporter never fires) unless `force` (the respawn). Returns true when
-- the player was placed.
function GSA1.PlacePlayer(ply, pos, ang, force)
    if not force and not P.cv_server:GetBool() and box_at(pos) then
        TS.kept_out = TS.kept_out + 1
        return false
    end
    ply:SetPos(pos)
    if ang then ply:SetEyeAngles(ang) end
    ply.GSA1Placed = Vector(pos)
    ply.GSA1PlacedYaw = ply:EyeAngles().y
    return true
end

-- activate, deactivate, PlayerSpawn: the next placement starts a new record
function GSA1.ClearPlacement(ply)
    ply.GSA1Placed, ply.GSA1PlacedYaw, ply.GSA1TeleWait, ply.GSA1TeleStay = nil, nil, nil, nil
end

local function eligible(ply)
    if not (IsValid(ply) and ply.GSA1Active and ply.GSA1Placed and P.cv_server:GetBool()) then return false end
    if ply.Alive and not ply:Alive() then return false end
    if ply.InVehicle and ply:InVehicle() then return false end
    if ply.GetObserverMode and ply:GetObserverMode() ~= OBS_NONE then return false end
    local follow = GetConVar("gsa1_sv_follow")
    if follow and not follow:GetBool() then return false end
    return true
end

-- A move G-SA1 did not make is a teleport (where: "tick" after a user command, "packet" before a state packet is
-- applied). Holds the player there, tells the owning client and returns true; a second teleport while the first is not
-- confirmed yet (a destination inside another teleporter) is one more (review R.3.4).
function GSA1.CheckMoved(ply, where)
    if not eligible(ply) then return false end
    local wait = ply.GSA1TeleWait
    local ref = wait and wait.pos or ply.GSA1Placed
    local o = ply:GetPos()
    local d = o:Distance(ref)
    local noint = ply.IsEffectActive and ply:IsEffectActive(EF_NOINTERP_BIT) or false
    if not P.IsTeleport(d, noint) then return false end
    local now = SysTime()
    TS.detected = TS.detected + 1
    ply.GSA1TeleTimes = ply.GSA1TeleTimes or {}
    local n, past = P.LoopCount(ply.GSA1TeleTimes, now)
    local eye = ply:EyeAngles()
    local before = ply.GSA1CmdYaw or ply.GSA1PlacedYaw
    local turned = P.Turned(before, eye.y)
    ply.GSA1Placed = Vector(o)
    if past and ply.GSA1TeleLoopSent then
        -- the loop guard: still held there, the client is told again when the window has room
        TS.suppressed = TS.suppressed + 1
        if wait then
            wait.pos = Vector(o)
        else
            ply.GSA1TeleWait = { gen = ply.GSA1TeleGen or 0, at = now, pos = Vector(o) }
        end
        return true
    end
    local cause = cause_of(ref)
    local loop = past
    if loop then
        TS.loops = TS.loops + 1
        ply.GSA1TeleLoopSent = true
    else
        ply.GSA1TeleLoopSent = nil
    end
    ply.GSA1TeleGen = P.NextGen(ply.GSA1TeleGen)
    ply.GSA1TeleWait = { gen = ply.GSA1TeleGen, at = now, pos = Vector(o), from = Vector(ref) }
    ply.GSA1TeleStay = nil
    net.Start(P.NET)
    net.WriteUInt(ply.GSA1TeleGen, P.GEN_BITS)
    net.WriteVector(o)
    net.WriteAngle(eye)
    net.WriteBool(turned)
    net.WriteVector(ply:GetVelocity())
    net.WriteBool(loop)
    net.WriteString(string.sub(cause, 1, 120))
    net.WriteFloat(d)
    net.WriteString(where or "?")
    net.Send(ply)
    TS.sent = TS.sent + 1
    return true
end

-- The state receiver asks before it applies a packet (pos: the packet's position): true = drop it (a teleport waits for
-- the client's confirmation: the packet is from before the client moved the character; a teleport was found just now;
-- or the client confirmed without moving the character and the packet still comes from where the teleport began). 1 s
-- without a confirmation resumes the old follow.
function GSA1.TeleportGate(ply, pos)
    local w = ply.GSA1TeleWait
    if w then
        if SysTime() - w.at < P.ACK_TIMEOUT then
            TS.dropped = TS.dropped + 1
            return true
        end
        ply.GSA1TeleWait = nil
        ply.GSA1Placed = ply:GetPos()
        TS.timeouts = TS.timeouts + 1
    end
    local st = ply.GSA1TeleStay
    if st then
        if SysTime() < st.untilT and pos and pos:Distance(st.from) < P.STAY_NEAR then
            TS.stayed = TS.stayed + 1
            return true
        end
        ply.GSA1TeleStay = nil
    end
    return GSA1.CheckMoved(ply, "packet")
end

net.Receive(P.NET_ACK, function(len, ply)
    if not IsValid(ply) then return end
    local gen = net.ReadUInt(P.GEN_BITS)
    local moved = net.ReadBool()
    local w = ply.GSA1TeleWait
    if w and w.gen == gen then
        ply.GSA1TeleWait = nil
        ply.GSA1Placed = ply:GetPos()
        TS.acked = TS.acked + 1
        if not moved and w.from then ply.GSA1TeleStay = { from = w.from, untilT = SysTime() + P.STAY_TIME } end
    else
        TS.stale_acks = TS.stale_acks + 1
    end
end)

-- the view angles of the user command (before a trigger's Teleport snaps them): "the view turned"
hook.Add("StartCommand", "gsa1_teleport", function(ply, cmd)
    if ply.GSA1Active and cmd and cmd.GetViewAngles then ply.GSA1CmdYaw = cmd:GetViewAngles().y end
end)

-- after the user command's ProcessImpacts (CTriggerTeleport::Touch) and before the next command's movement
hook.Add("PlayerPostThink", "gsa1_teleport", function(ply)
    GSA1.CheckMoved(ply, "tick")
end)

concommand.Add("gsa1_teleport_status", function(ply)
    if IsValid(ply) and not (ply.IsAdmin and ply:IsAdmin()) and not game.SinglePlayer() then return end
    local line = string.format("G-SA1 teleports: %d detected, %d sent, %d stale packets dropped, %d confirmed, %d without a "
        .. "confirmation, %d loops (%d not sent), %d spots in a teleporter not taken (gsa1_sv_teleports 0)", TS.detected,
        TS.sent, TS.dropped, TS.acked, TS.timeouts, TS.loops, TS.suppressed, TS.kept_out)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end, nil, "G-SA1: the server's teleport counts")
