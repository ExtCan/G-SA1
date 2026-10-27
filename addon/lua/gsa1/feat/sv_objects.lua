-- G-SA1 feature "objects", server part (round 0.9.4; sadc docs/research/gsa1_094_plan.md 6.5 tasks 1 and 5 with its Review
-- R.3, gsa1_090_rings.md review R.4.7, gsa1_094_items.md 5). Pure Lua: dedicated servers work (no module, no disc).
--
-- The server owns the shared state of every G-SA1 object (the entities' NetworkVars State, Broken, TakenBits (0.9.4.1:
-- a ring group's rings taken, two hex digits per record; 0.9.4: UserBits0..7), RespawnAt) and checks every report a
-- client's character makes (gsa1_obj_ev: a ring taken, a box broken, a line's rings taken), accepting it only
--   * from a player who is a G-SA1 character, while "G-SA1 objects on this server" (gsa1_sv_set) is on, within a rate limit;
--   * for a legal change: a Ring or air box there -> taken, a ground box whole -> broken, a ring group's bits only added and
--     only bits of rings the group has (a group's touch near any ring of that record, each added ring on the character's
--     path in the half second before: 0.9.4.1, sh_objects.lua O.CheckEvent);
--   * when the TOUCH fits (sh_objects.lua O.CheckEvent; never ply:GetPos() at the time the report arrives): the touch within
--     the cause's reach of the object - the body 64 HU of a ring, 80 HU of a box; a projectile (E-102's shot) within 80 HU
--     of the box with the shooter within 1,040 HU; a ring the Magnetic Barrier pulled within 264 HU of its place with the
--     ring 64 HU from the character (review R.3); no touch seen: 80 HU, 1,040 HU for E-102 and Big - and the touch on the
--     character's own path at the report's age (a ~1.5 s history of each character player's positions, sampled every tick
--     from ply.GSA1State, sv_gsa1.lua) within the slack (gsa1_sv_set_reach_slack) plus speed x the time beyond the path;
--   * unless hook.Run("GSA1ObjectEvent", ply, ent, kind, data) returns false.
-- A refused report gets the object's state sent back to its client (gsa1_obj_st), so that world has it again.
-- Respawn: an object's "Respawn after" (s; new ones take gsa1_sv_set_respawn, 0 = never: the game's rule) brings it back
-- that long after its last change; "Reset G-SA1 objects" (gsa1_sv_set_reset: admins, the listen server's host, single
-- player, the server console) brings everything back. Placing: the class's SpawnFunction (gsa1_base.lua) asks this file:
-- gsa1_sv_set, the limit sbox_maxgsa1_objects, the placer's contents (gsa1_set_box_content), the default respawn time;
-- undo reads "Undone G-SA1 <name>", Utilities > Cleanup has "G-SA1 objects". The pick hull (0.9.4.1, sh_objects.lua "THE
-- PICK HULL"): the whole object as SOLID_OBB collision bounds with custom collisions and a physics box, frozen; the
-- Physics Gun carries it (OnPhysgunPickup lets it move) and a drop freezes it again and tells the clients to move the
-- game's object at once; a new Count / Spacing / Radius rebuilds the hull (after the drop if it is being carried).
GSA1 = GSA1 or {}
local O = GSA1.Objects
if not O then return end

util.AddNetworkString(O.NET.EV)
util.AddNetworkString(O.NET.ST)

local cv = O.cv
O.HIST_SECONDS = 1.5
O.RATE, O.BURST = 60, 120          -- reports per second per player (a Light Speed Dash through a line: ~30 a second)
O.all = O.all or {}                -- [entity] = true: every object of the map
O.layoutDirty = O.layoutDirty or {}

local function now() return CurTime() end

local function is_char(ply)
    if not IsValid(ply) then return false end
    if ply.GSA1Active then return true end
    return GSA1.IsCharacter ~= nil and GSA1.IsCharacter(ply) == true
end
O.IsCharacterPlayer = is_char

-- the objects of the map ------------------------------------------------------------------------------------------------
function O.Register(ent)
    if O.IsObject(ent) then O.all[ent] = true end
end

hook.Add("OnEntityCreated", "gsa1_objects", function(ent)
    if O.IsObject(ent) then O.all[ent] = true end
end)
hook.Add("EntityRemoved", "gsa1_objects", function(ent)
    O.all[ent] = nil
    O.layoutDirty[ent] = nil
end)

-- the state a new (or pasted) object starts with: there, whole, no rings taken, no respawn due
function O.FreshState(dt)
    if type(dt) ~= "table" then return end
    dt.State, dt.Broken, dt.RespawnAt, dt.Moved = 1, false, 0, 0
    if dt.TakenBits ~= nil then dt.TakenBits = "" end
    for k = 0, 7 do
        dt["UserBits" .. k] = nil        -- (a 0.9.4 copy's per-record Ints: no such NetworkVars any more)
    end
end

-- a ring group's rings all back (every record's bits 0)
function O.ClearBits(ent)
    if ent.SetTakenBits then ent:SetTakenBits("") end
end

-- the pick hull (sh_objects.lua "THE PICK HULL"): a frozen physics box without gravity (the Physics Gun moves physics
-- objects; at most O.PHYS_MAX from the centre), then the whole object as SOLID_OBB collision bounds with custom
-- collisions (TestCollision: the editing rays only), in COLLISION_GROUP_WORLD (props and NPCs pass it)
function O.ApplyHull(ent)
    local d = O.Describe(ent)
    local mins, maxs = O.Hull(d)
    local pmin, pmax = O.PhysBox(mins, maxs)
    if ent.PhysicsInitBox then ent:PhysicsInitBox(pmin, pmax) end      -- (sets SOLID_BBOX and the bounds: both redone below)
    if ent.SetMoveType then ent:SetMoveType(MOVETYPE_VPHYSICS) end
    O.ApplyPickShape(ent, mins, maxs)
    if ent.SetCollisionGroup then ent:SetCollisionGroup(COLLISION_GROUP_WORLD) end
    local phys = ent.GetPhysicsObject and ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        if phys.EnableGravity then phys:EnableGravity(false) end
    end
    ent.GSA1Hull = { mins, maxs }
end

function O.ServerInit(ent)
    O.all[ent] = true
    local c = O.BY_CLASS[ent:GetClass()] or {}
    -- the class's defaults where a value was never set (a new entity's NetworkVars are 0)
    if c.count and ent.GetCount and (tonumber(ent:GetCount()) or 0) < 1 then ent:SetCount(c.count[3]) end
    if c.size then
        local get = c.shape == 1 and ent.GetRadius or ent.GetSpacing
        local set = c.shape == 1 and ent.SetRadius or ent.SetSpacing
        if get and set and (tonumber(get(ent)) or 0) <= 0 then set(ent, c.size[3]) end
    end
    ent:SetState(1)
    ent:SetBroken(false)
    ent:SetRespawnAt(0)
    O.ClearBits(ent)
    O.ApplyHull(ent)
end

-- a NetworkVar changed (gsa1_base.lua's notify, before the value is set): a new layout re-makes the hull next tick
function O.OnVarChanged(ent, name, old, new)
    if name == "Count" or name == "Spacing" or name == "Radius" then
        if old ~= new then O.layoutDirty[ent] = true end
    end
end

-- may ply place an object of class cls now? (ok, why)
function O.CanSpawn(ply, cls)
    if not cv.sv_on:GetBool() then return false, "G-SA1 objects are off on this server (gsa1_sv_set 0)" end
    if not O.BY_CLASS[cls] then return false, "not a G-SA1 object" end
    if IsValid(ply) and ply.CheckLimit and not ply:CheckLimit("gsa1_objects") then
        return false, "the G-SA1 objects limit (sbox_maxgsa1_objects)"
    end
    return true
end

-- the class's SpawnFunction (gsa1_base.lua): the place, the placer's contents, the default respawn time, the count, the
-- cleanup (the undo is the sandbox's own, renamed below)
function O.ServerSpawn(ply, tr, cls)
    local ok, why = O.CanSpawn(ply, cls)
    if not ok then
        if IsValid(ply) and ply.ChatPrint and not string.find(why, "limit", 1, true) then ply:ChatPrint("G-SA1: " .. why) end
        return nil
    end
    local yaw = IsValid(ply) and ply.EyeAngles and ply:EyeAngles().y or 0
    local pos, ang = O.SpawnPlace(cls, tr, yaw)
    local ent = ents.Create(cls)
    if not IsValid(ent) then return nil end
    ent:SetPos(pos)
    ent:SetAngles(ang)
    local c = O.BY_CLASS[cls]
    if c.contents and ent.SetContents then
        local v = IsValid(ply) and ply.GetInfoNum and ply:GetInfoNum("gsa1_set_box_content", O.DEFAULT_CONTENTS) or
            O.DEFAULT_CONTENTS
        ent:SetContents(math.Clamp(math.floor(tonumber(v) or O.DEFAULT_CONTENTS), 0, 8))
    end
    if ent.SetRespawnAfter then ent:SetRespawnAfter(math.max(0, cv.sv_respawn:GetFloat())) end
    ent:Spawn()
    if ent.Activate then ent:Activate() end
    if IsValid(ply) then
        if ply.AddCount then ply:AddCount("gsa1_objects", ent) end
        if ply.AddCleanup then ply:AddCleanup("gsa1_objects", ent) end
    end
    return ent
end

-- "Undone G-SA1 <name>" (the sandbox makes the undo after SpawnFunction: renamed when it is created)
hook.Add("CanCreateUndo", "gsa1_objects", function(ply, undo)
    if type(undo) ~= "table" or type(undo.Entities) ~= "table" then return end
    for _, e in pairs(undo.Entities) do
        if O.IsObject(e) and IsValid(e) then
            local name = e.PrintName or "object"
            undo.CustomUndoText = "Undone G-SA1 " .. name
            return
        end
    end
end)

-- the state ---------------------------------------------------------------------------------------------------------------
-- the object as the rules see it (sh_objects.lua O.CheckEvent)
function O.ServerView(ent)
    local d = O.Describe(ent)
    local obj = { type = d.type, d = d, pos = ent:GetPos(), state = tonumber(ent:GetState()) or 1,
                  broken = ent:GetBroken() == true, bits = {} }
    for k = 0, O.RecordCount(d) - 1 do obj.bits[k] = O.BitsOf(ent, k) end
    if d.type == O.TYPE.RING or d.type == O.TYPE.O_GRING then obj.rings = O.RingPositions(d, obj.pos, ent:GetAngles()) end
    return obj
end

-- back as it was placed: there, whole, every ring; reason: for the log (nil: quiet)
function O.Respawn(ent, reason)
    if not IsValid(ent) or not O.IsObject(ent) then return end
    ent:SetState(1)
    ent:SetBroken(false)
    ent:SetRespawnAt(0)
    O.ClearBits(ent)
end

local function respawn_due(ent)
    local after = tonumber(ent:GetRespawnAfter()) or 0
    ent:SetRespawnAt(after > 0 and now() + after or 0)
end

-- the object's state to one player (a refused report: its world gets the object again)
function O.SendState(ent, ply, why)
    if not (IsValid(ent) and IsValid(ply)) then return end
    local d = O.Describe(ent)
    local n = O.RecordCount(d)
    net.Start(O.NET.ST)
    net.WriteUInt(ent:EntIndex(), 16)
    net.WriteUInt(math.Clamp(tonumber(ent:GetState()) or 1, 0, 1), 2)
    net.WriteBool(ent:GetBroken() == true)
    net.WriteUInt(n, 8)                                 -- (0.9.4.1: up to 127 records, their bits as TakenBits)
    net.WriteString(ent.GetTakenBits and tostring(ent:GetTakenBits() or "") or "")
    net.WriteString(tostring(why or ""))
    net.Send(ply)
end

-- the history of each character player's positions (sampled every tick from ply.GSA1State, the last state packet)
function O.Sample(ply, t)
    local s = ply.GSA1State
    if not (is_char(ply) and s and s.x) then
        ply.GSA1Hist = nil
        return
    end
    local h = ply.GSA1Hist or {}
    ply.GSA1Hist = h
    local st = tonumber(s.time) or t
    local last = h[#h]
    if not last or last.t < st then
        h[#h + 1] = { t = st, x = s.x, y = s.y, z = s.z }
    elseif last.t == st then
        last.x, last.y, last.z = s.x, s.y, s.z      -- (two packets in one tick: the newer one)
    end
    while #h > 1 and h[1].t < t - O.HIST_SECONDS do table.remove(h, 1) end
end

-- the rate limit (a token bucket per player)
function O.RateOk(ply, t)
    local b = ply.GSA1ObjRate or { tokens = O.BURST, t = t }
    ply.GSA1ObjRate = b
    b.tokens = math.min(O.BURST, b.tokens + (t - b.t) * O.RATE)
    b.t = t
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

O.counts = O.counts or { taken = 0, broken = 0, rings = 0, refused = 0 }

-- one report e = {kind, index, bits, age, pos, cause, att} from ply about ent: applied (true) or refused (false, why)
function O.ServerEvent(ply, ent, e)
    if not cv.sv_on:GetBool() then return false, "G-SA1 objects are off on this server" end
    if not is_char(ply) then return false, "only a G-SA1 character takes rings and breaks boxes" end
    if not (IsValid(ent) and O.IsObject(ent)) then return false, "no such object" end
    local t = now()
    if not O.RateOk(ply, t) then return false, "too many reports at once" end
    local obj = O.ServerView(ent)
    local hist = ply.GSA1Hist
    if (not hist or #hist == 0) and game.SinglePlayer() then
        -- single player: the only client is the host; no positions (the follow off) is no reason to refuse
        hist = { { t = t - e.age, x = e.pos.x, y = e.pos.y, z = e.pos.z }, synthetic = true }
    end
    local ok, why, add = O.CheckEvent(e, obj, hist or {}, t, cv.sv_slack:GetFloat(), ply.GSA1Kind)
    if not ok then return false, why end
    if hook and hook.Run and hook.Run("GSA1ObjectEvent", ply, ent, e.kind, e) == false then
        return false, "refused by another addon (GSA1ObjectEvent)"
    end
    local EV = O.EV
    if e.kind == EV.GONE then
        ent:SetState(0)
        O.counts.taken = O.counts.taken + 1
    elseif e.kind == EV.BROKEN then
        ent:SetBroken(true)
        O.counts.broken = O.counts.broken + 1
    elseif e.kind == EV.USERBITS then
        local k = e.index
        ent:SetTakenBits(O.BitsSet(ent:GetTakenBits(), k, bit.bor(O.BitsOf(ent, k), add)))
        O.counts.rings = O.counts.rings + 1
    end
    respawn_due(ent)
    return true
end

net.Receive(O.NET.EV, function(len, ply)
    if not IsValid(ply) then return end
    local idx = net.ReadUInt(16)
    local e = { index = net.ReadUInt(8), kind = net.ReadUInt(3), bits = net.ReadUInt(8), age = net.ReadFloat(),
                pos = net.ReadVector(), cause = net.ReadUInt(2), att = net.ReadVector() }
    local ent = Entity(idx)
    local ok, why = O.ServerEvent(ply, ent, e)
    if not ok then
        O.counts.refused = O.counts.refused + 1
        if IsValid(ent) and O.IsObject(ent) then O.SendState(ent, ply, why) end
    end
end)

-- every tick: the history; every 0.1 s: respawns, new layouts, frozen boxes -------------------------------------------------
local next_slow = 0
hook.Add("Think", "gsa1_objects", function()
    local t = now()
    for _, ply in ipairs(player.GetAll()) do O.Sample(ply, t) end
    if t < next_slow then return end
    next_slow = t + 0.1
    for ent in pairs(O.layoutDirty) do
        if not IsValid(ent) then
            O.layoutDirty[ent] = nil
        elseif not ent.GSA1Held then        -- (carried by the Physics Gun: rebuilt after the drop)
            O.layoutDirty[ent] = nil
            -- a new layout: the old rings' bits no longer name the same rings
            O.ClearBits(ent)
            O.ApplyHull(ent)
        end
    end
    for ent in pairs(O.all) do
        if not IsValid(ent) then
            O.all[ent] = nil
        else
            local at = tonumber(ent:GetRespawnAt()) or 0
            if at > 0 and t >= at then O.Respawn(ent, "respawn") end
            if not ent.GSA1Held then
                local phys = ent.GetPhysicsObject and ent:GetPhysicsObject()
                if IsValid(phys) and phys.IsMotionEnabled and phys:IsMotionEnabled() then phys:EnableMotion(false) end
            end
        end
    end
end)

-- the Physics Gun (ENT:PhysgunPickup in gsa1_base.lua allows it): held - its physics box free to move while carried -
-- then frozen again where it was dropped and the clients told to move the game's object at once
hook.Add("OnPhysgunPickup", "gsa1_objects", function(ply, ent)
    if not O.IsObject(ent) then return end
    ent.GSA1Held = true
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        if phys.Wake then phys:Wake() end
    end
end)
hook.Add("PhysgunDrop", "gsa1_objects", function(ply, ent)
    if not O.IsObject(ent) then return end
    ent.GSA1Held = nil
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:SetVelocity(Vector(0, 0, 0))
    end
    ent:SetMoved(((tonumber(ent:GetMoved()) or 0) + 1) % 65536)
end)

-- "Reset G-SA1 objects": admins, the listen server's host, single player, the server console
function O.MayReset(ply)
    if not IsValid(ply) then return true end
    if game.SinglePlayer() then return true end
    if ply.IsListenServerHost and ply:IsListenServerHost() then return true end
    return ply.IsAdmin ~= nil and ply:IsAdmin() == true
end

concommand.Add("gsa1_sv_set_reset", function(ply)
    if not O.MayReset(ply) then
        if IsValid(ply) and ply.ChatPrint then ply:ChatPrint("G-SA1: only an admin or the server's host may reset the objects") end
        return
    end
    local n = 0
    for ent in pairs(O.all) do
        if IsValid(ent) then
            O.Respawn(ent, "reset")
            n = n + 1
        end
    end
    print(string.format("[G-SA1] %d objects reset by %s", n, IsValid(ply) and tostring(ply:Nick()) or "the console"))
end, nil, "G-SA1: every taken ring and broken item box back (admins and the server's host)")

-- objects that existed before this file ran (a Lua refresh)
if ents and ents.FindByClass then
    for _, e in ipairs(ents.FindByClass("gsa1_obj_*")) do O.Register(e) end
end
