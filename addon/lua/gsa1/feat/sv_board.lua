-- G-SA1 feature "board", server part (round 0.9.5; sadc docs/research/gsa1_095_plan.md 4.15, 5.6 with its review paragraph
-- (R.3, R.5), 6.4 task 3; board095_gsa1.md 5.4 - 5.9). Pure Lua: dedicated servers work (no module, no disc); single
-- player is a listen server with one player and runs the same code.
--
-- The server owns the boxes' shared state - the Board On box's board (Present, RespawnAt, the place it lies: BoardPos /
-- BoardAng from a trace down), every box's Used - and decides who enters a box: a Think hook runs the swept edge test
-- (feat/sh_board.lua B.Edge) on each NEW state packet of a character player (ply.GSA1State, stamped per accepted packet by
-- sv_gsa1.lua; nothing without "Let the server move your player entity"), and tells that player's client
--   * GO (Board On, he is on foot, Sonic or Tails: the board is CLAIMED for him for the walk's deadline + 2 s; the place
--     and the claim's lifetime go with it), GONE (the board is gone or claimed: when it comes back), RIDING (he rides
--     into a Board On box: the box's ground and push), SPENT (a 1-use box that was used), OFF (Board Off, he rides);
--   * the client answers gsa1_board_took (on the board: Present false, Used + 1, the refill timer) or gsa1_board_cancel
--     (the walk ended: the claim is released), gsa1_board_st (his riding state: the NW2 bool gsa1_board; a Board Off
--     box's use, counted only when the server sent him OFF for that box in the last 5 s), gsa1_board_left (a board he got
--     off came to rest: the server makes the decoration gsa1_board_left there).
-- Review R.3: a player is SERVED in a box once he got GO, OFF or RIDING for it, until he leaves it (outside by EXIT_PAD):
-- a refill or a released claim re-tests only the unserved players inside (those who got GONE; the nearest first), never the
-- one who cancelled, so a jump stops the walk instead of restarting it. Checks: every message from a character player
-- only, a token bucket of 10 a second per player, claims by sender / slot / id and their lifetime, a left board finite and
-- within 2,048 HU of the sender's character (a bucket of 3 refilled at 1 a second: review R.5). Hooks for other addons:
-- GSA1BoardBox(ply, ent, what) (false: nothing happens), GSA1BoardChanged(ply, on). gsa1_sv_board 0: boxes can be placed,
-- nothing happens. "Reset every Board box" (gsa1_sv_board_reset: admins, the listen server's host, single player, the
-- console) and "Reset this box" (the context menu, feat/sh_board.lua).
GSA1 = GSA1 or {}
local B = GSA1.Board
if not B then return end

for _, n in pairs(B.NET) do util.AddNetworkString(n) end

local cv = B.cv
local WHAT, WHY = B.WHAT, B.WHY
B.sv = B.sv or { boxes = {}, list = {}, dirty = true, claimId = 0, left = {}, layoutDirty = {}, nextSlow = 0,
                 nextPose = 0, counts = { go = 0, off = 0, riding = 0, gone = 0, spent = 0, took = 0, cancelled = 0,
                 timeouts = 0, refills = 0, left = 0, refused = 0, packets = 0 } }
local S = B.sv

local function now() return CurTime() end

local function is_char(ply)
    if not IsValid(ply) then return false end
    if ply.GSA1Active then return true end
    return GSA1.IsCharacter ~= nil and GSA1.IsCharacter(ply) == true
end
B.IsCharacterPlayer = is_char

local function num(ent, name, d)
    local g = ent and ent["Get" .. name]
    local v = g and tonumber(g(ent))
    if v == nil then return d end
    return v
end

-- a player's edge-test record: the track (B.Edge), the boxes he was served in, the OFFs sent, the GONE / SPENT times
local function track_of(ply)
    local t = ply.GSA1BoardTrack
    if not t then
        t = B.NewTrack()
        t.served, t.offSent, t.said, t.stamp = {}, {}, {}, nil
        ply.GSA1BoardTrack = t
    end
    return t
end
B.TrackOf = track_of

-- the boxes ---------------------------------------------------------------------------------------------------------------
-- the edge test's data of a box (its pose and size; rebuilt when one changes)
function B.BoxData(ent)
    local L, W, H = B.Size(ent)
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local b = B.MakeBox(ent, pos.x, pos.y, pos.z, ang.p, ang.y, ang.r, L, W, H)
    b.ent, b.kind = ent, B.BoxKind(ent)
    b.sig = { pos.x, pos.y, pos.z, ang.p, ang.y, ang.r, L, W, H }
    return b
end

local function same_sig(b, ent)
    local L, W, H = B.Size(ent)
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local s = b.sig
    return math.abs(s[1] - pos.x) < 0.01 and math.abs(s[2] - pos.y) < 0.01 and math.abs(s[3] - pos.z) < 0.01 and
        math.abs(s[4] - ang.p) < 0.01 and math.abs(s[5] - ang.y) < 0.01 and math.abs(s[6] - ang.r) < 0.01 and
        s[7] == L and s[8] == W and s[9] == H
end

function B.Register(ent)
    if not B.IsBox(ent) then return end
    local b = B.BoxData(ent)
    S.boxes[ent] = b
    S.dirty = true
    -- a new box takes each player's "inside" from his last sample: a box placed on a character does nothing until he
    -- leaves and comes back
    for _, ply in ipairs(player.GetAll()) do
        if ply.GSA1BoardTrack then B.Seed(ply.GSA1BoardTrack, b) end
    end
    return b
end

local function rebuild_list()
    local list = {}
    for ent, b in pairs(S.boxes) do
        if IsValid(ent) then list[#list + 1] = b else S.boxes[ent] = nil end
    end
    S.list = list
    S.dirty = false
end

-- the board's place in a Board On box: traced down from the base centre (the world only), aligned to the ground, turned by
-- the box's yaw; the clients draw the lying board there and GO sends it (review R.3: one value)
function B.BoardPlace(ent)
    if B.BoxKind(ent) ~= "on" or not ent.SetBoardPos then return end
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local _, _, up = B.Axes(ang.p, ang.y, ang.r)
    local start = Vector(pos.x + up[1] * 8, pos.y + up[2] * 8, pos.z + up[3] * 8)
    local tr = util.TraceLine({ start = start, endpos = Vector(start.x, start.y, start.z - B.TRACE_DOWN),
                                mask = MASK_SOLID_BRUSHONLY, filter = ent })
    if tr and tr.Hit and tr.HitPos then
        ent:SetBoardPos(Vector(tr.HitPos))
        local p, y, r = B.GroundAngles(ang.y, tr.HitNormal)
        ent:SetBoardAng(Angle(p, y, r))
    else
        ent:SetBoardPos(Vector(pos))
        ent:SetBoardAng(Angle(0, ang.y, 0))
    end
end

-- the pick hull (feat/sh_objects.lua "THE PICK HULL"): a frozen physics box without gravity, the box as SOLID_OBB collision
-- bounds with custom collisions, in COLLISION_GROUP_WORLD
function B.ApplyHull(ent)
    local mins, maxs = B.Hull(ent)
    local L = B.PHYS_MAX
    local pmin = Vector(math.max(mins.x, -L), math.max(mins.y, -L), math.max(mins.z, -L))
    local pmax = Vector(math.min(maxs.x, L), math.min(maxs.y, L), math.min(maxs.z, L))
    if ent.PhysicsInitBox then ent:PhysicsInitBox(pmin, pmax) end
    if ent.SetMoveType then ent:SetMoveType(MOVETYPE_VPHYSICS) end
    if ent.SetSolid then ent:SetSolid(SOLID_OBB or 3) end
    if ent.SetCollisionBounds then ent:SetCollisionBounds(mins, maxs) end
    if ent.EnableCustomCollisions then ent:EnableCustomCollisions(true) end
    if ent.SetCollisionGroup then ent:SetCollisionGroup(COLLISION_GROUP_WORLD) end
    local phys = ent.GetPhysicsObject and ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        if phys.EnableGravity then phys:EnableGravity(false) end
    end
    ent.GSA1Hull = { mins, maxs }
end

-- the class's defaults (a new box from the spawn menu, or one never configured)
function B.Defaults(ent)
    local D = B.DEFAULT
    if ent.SetWidth then ent:SetWidth(D.Width) end
    if ent.SetLength then ent:SetLength(D.Length) end
    if ent.SetHeight then ent:SetHeight(D.Height) end
    if ent.SetEnabled then ent:SetEnabled(true) end
    if ent.SetUses then ent:SetUses(D.Uses) end
    if ent.SetRefill then ent:SetRefill(true) end
    if ent.SetRefillAfter then ent:SetRefillAfter(D.RefillAfter) end
    if ent.SetPush then ent:SetPush(D.Push) end
    if ent.SetGround then ent:SetGround(D.Ground) end
end

-- Initialize (gsa1_trigger.lua): the defaults when it was never configured (a copy restored its values before), the fresh
-- runtime state, the hull, the board's place
function B.ServerInit(ent)
    if num(ent, "Width", 0) <= 0 and num(ent, "Length", 0) <= 0 and num(ent, "Height", 0) <= 0 then B.Defaults(ent) end
    if ent.SetUsed then ent:SetUsed(0) end
    if ent.SetPresent then ent:SetPresent(true) end
    if ent.SetRespawnAt then ent:SetRespawnAt(0) end
    ent.GSA1Claim = nil
    B.ApplyHull(ent)
    B.BoardPlace(ent)
    B.Register(ent)
end

-- a size changed (gsa1_trigger.lua's notify, before the value is set): the hull and the place next tick
function B.OnVarChanged(ent, name, old, new)
    if old ~= new then S.layoutDirty[ent] = true end
end

function B.MayPick(ply, ent) return B.IsBox(ent) end

-- may ply place a box of class cls now (ok, why); gsa1_sv_board 0 still places it (inert)
function B.CanSpawn(ply, cls)
    if not B.BY_CLASS[cls] then return false, "not a G-SA1 trigger box" end
    if IsValid(ply) and ply.CheckLimit and not ply:CheckLimit("gsa1_triggers") then
        return false, "the G-SA1 trigger boxes limit (sbox_maxgsa1_triggers)"
    end
    return true
end

-- the class's SpawnFunction (gsa1_trigger.lua): on the aimed surface, the placer's yaw, upright; the defaults; the count
-- and the cleanup (the undo is the sandbox's own, renamed below)
function B.ServerSpawn(ply, tr, cls)
    local ok, why = B.CanSpawn(ply, cls)
    if not ok then
        if IsValid(ply) and ply.ChatPrint and not string.find(why, "limit", 1, true) then ply:ChatPrint("G-SA1: " .. why) end
        return nil
    end
    local yaw = IsValid(ply) and ply.EyeAngles and ply:EyeAngles().y or 0
    local pos, ang = B.SpawnPlace(tr, yaw)
    local ent = ents.Create(cls)
    if not IsValid(ent) then return nil end
    ent:SetPos(pos)
    ent:SetAngles(ang)
    B.Defaults(ent)
    if ent.SetPlacer and IsValid(ply) then ent:SetPlacer(ply) end
    ent:Spawn()
    if ent.Activate then ent:Activate() end
    if IsValid(ply) then
        if ply.AddCount then ply:AddCount("gsa1_triggers", ent) end
        if ply.AddCleanup then ply:AddCleanup("gsa1_triggers", ent) end
    end
    return ent
end

-- "Undone G-SA1 Board On box"
hook.Add("CanCreateUndo", "gsa1_board", function(ply, undo)
    if type(undo) ~= "table" or type(undo.Entities) ~= "table" then return end
    for _, e in pairs(undo.Entities) do
        if IsValid(e) and B.IsBox(e) then
            undo.CustomUndoText = "Undone G-SA1 " .. tostring(e.PrintName or "trigger") .. " box"
            return
        end
    end
end)

hook.Add("OnEntityCreated", "gsa1_board", function(ent)
    if B.IsBox(ent) and not S.boxes[ent] and ent.GetWidth then
        -- (Initialize registers it with its hull; this only catches a box made before this file ran)
        if num(ent, "Width", 0) > 0 then B.Register(ent) end
    end
end)
hook.Add("EntityRemoved", "gsa1_board", function(ent)
    if S.boxes[ent] then
        S.boxes[ent] = nil
        S.dirty = true
    end
    S.layoutDirty[ent] = nil
    for _, ply in ipairs(player.GetAll()) do
        local t = ply.GSA1BoardTrack
        if t then
            t.inside[ent], t.served[ent], t.offSent[ent], t.said[ent] = nil, nil, nil, nil
        end
    end
    if B.IsLeft(ent) then
        for p, list in pairs(S.left) do
            for i = #list, 1, -1 do
                if list[i] == ent then table.remove(list, i) end
            end
            if #list == 0 then S.left[p] = nil end
        end
    end
end)

-- the messages to a client ------------------------------------------------------------------------------------------------
local ZERO = Vector(0, 0, 0)
function B.Send(ply, ent, what, slot, claim, seconds)
    local on = B.BoxKind(ent) == "on"
    local place = (on and ent.GetBoardPos) and ent:GetBoardPos() or ent:GetPos()
    local bang = (on and ent.GetBoardAng) and ent:GetBoardAng() or ent:GetAngles()
    net.Start(B.NET.BOX)
    net.WriteUInt(ent:EntIndex(), 16)
    net.WriteUInt(what, 3)
    net.WriteUInt(math.Clamp(math.floor(tonumber(slot) or 0), 0, 15), 4)
    net.WriteUInt(math.Clamp(math.floor(tonumber(claim) or 0), 0, 255), 8)
    net.WriteVector(place or ZERO)
    net.WriteFloat(bang and bang.y or 0)
    net.WriteUInt(on and math.Clamp(num(ent, "Push", 1), 0, 2) or 0, 2)
    net.WriteUInt(on and math.Clamp(num(ent, "Ground", 0), 0, 3) or 0, 2)
    net.WriteFloat(tonumber(seconds) or 0)
    net.Send(ply)
    local key = string.lower(B.WHAT_NAME[what] or "?")
    S.counts[key] = (S.counts[key] or 0) + 1
end

-- GONE / SPENT at most every B.GONE_EVERY s per player and box
local function say_rate(ply, ent, what, seconds)
    local t = track_of(ply)
    local tn = now()
    local last = t.said[ent]
    if last and tn - last < B.GONE_EVERY then return false end
    t.said[ent] = tn
    B.Send(ply, ent, what, 0, 0, seconds)
    return true
end

local function claim_live(ent)
    local c = ent.GSA1Claim
    if not c then return false end
    if not IsValid(c.ply) or now() - c.at > c.life then
        ent.GSA1Claim = nil
        return false
    end
    return true
end

local function run_box_hook(ply, ent, what)
    if hook and hook.Run and hook.Run("GSA1BoardBox", ply, ent, what) == false then return false end
    return true
end

-- the horizontal distance of a player's last reported position to a point
local function hdist(ply, p)
    local s = ply.GSA1State
    if not (s and s.x and p) then return 0 end
    local dx, dy = s.x - p.x, s.y - p.y
    return math.sqrt(dx * dx + dy * dy)
end

-- ply's character (slot) entered box ent (the edge test, or a re-test): what the box does for him
function B.Enter(ply, ent, slot)
    slot = slot or 0
    if not (IsValid(ply) and IsValid(ent) and B.IsBox(ent)) then return nil end
    if not cv.sv_on:GetBool() then return nil end
    if ent.GetEnabled and not ent:GetEnabled() then return nil end
    local t = track_of(ply)
    if B.Spent(ent) then
        say_rate(ply, ent, WHAT.SPENT, 0)
        return WHAT.SPENT
    end
    local riding = ply.GetNW2Bool and ply:GetNW2Bool(B.NW_RIDING, false) == true
    if B.BoxKind(ent) == "off" then
        if not riding then return nil end
        if not run_box_hook(ply, ent, WHAT.OFF) then return nil end
        t.served[ent] = true
        t.offSent[ent] = now()
        B.Send(ply, ent, WHAT.OFF, slot, 0, 0)
        return WHAT.OFF
    end
    if riding then
        if not run_box_hook(ply, ent, WHAT.RIDING) then return nil end
        t.served[ent] = true
        B.Send(ply, ent, WHAT.RIDING, slot, 0, 0)
        return WHAT.RIDING
    end
    local k = tonumber(ply.GSA1Kind)
    if k ~= B.KIND_SONIC and k ~= B.KIND_TAILS then return nil end
    if ent:GetPresent() and not claim_live(ent) then
        if not run_box_hook(ply, ent, WHAT.GO) then return nil end
        local life = B.WalkDeadline(hdist(ply, ent:GetBoardPos())) + B.CLAIM_EXTRA
        S.claimId = S.claimId % 255 + 1
        ent.GSA1Claim = { ply = ply, slot = slot, id = S.claimId, at = now(), life = life }
        t.served[ent] = true
        B.Send(ply, ent, WHAT.GO, slot, S.claimId, life)
        return WHAT.GO
    end
    -- gone (refilling) or claimed by somebody else: he stays unserved, a refill or a released claim re-tests him
    local at = num(ent, "RespawnAt", 0)
    say_rate(ply, ent, WHAT.GONE, at > 0 and math.max(0, at - now()) or -1)
    return WHAT.GONE
end

-- the unserved character players inside box ent, the nearest first, until one gets the board (a refill, a released claim)
function B.Retest(ent)
    if not (IsValid(ent) and B.BoxKind(ent) == "on") then return end
    if not ent:GetPresent() or claim_live(ent) then return end
    local cand = {}
    local place = ent:GetBoardPos()
    for _, ply in ipairs(player.GetAll()) do
        local t = ply.GSA1BoardTrack
        if t and t.inside[ent] and not t.served[ent] and is_char(ply) then
            cand[#cand + 1] = { ply = ply, d = hdist(ply, place) }
        end
    end
    table.sort(cand, function(a, b) return a.d < b.d end)
    for _, c in ipairs(cand) do
        if B.Enter(c.ply, ent, 0) == WHAT.GO then return c.ply end
    end
end

-- the client's answers ------------------------------------------------------------------------------------------------------
-- the token bucket of a player's messages
local function rate_ok(ply)
    local tn = now()
    local b = ply.GSA1BoardRate or { tokens = B.MSG_BURST, t = tn }
    ply.GSA1BoardRate = b
    b.tokens = math.min(B.MSG_BURST, b.tokens + (tn - b.t) * B.MSG_RATE)
    b.t = tn
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end
B.RateOk = rate_ok

local function claim_of(ply, ent, slot, claim)
    local c = IsValid(ent) and ent.GSA1Claim
    if not c then return nil, "no claim on that box" end
    if c.ply ~= ply or c.slot ~= slot or c.id ~= claim then return nil, "not this player's claim" end
    return c
end

-- on the board: the board is gone from the box, a use counted, the refill timer
function B.Took(ply, ent, slot, claim)
    if not (IsValid(ent) and B.BoxKind(ent) == "on") then return false, "no such Board On box" end
    local c, why = claim_of(ply, ent, slot, claim)
    if not c then return false, why end
    if now() - c.at > c.life then
        ent.GSA1Claim = nil
        return false, "the claim timed out"
    end
    ent.GSA1Claim = nil
    ent:SetPresent(false)
    ent:SetUsed(num(ent, "Used", 0) + 1)
    if B.Spent(ent) or not ent:GetRefill() then
        ent:SetRespawnAt(0)
    else
        ent:SetRespawnAt(now() + math.Clamp(num(ent, "RefillAfter", B.DEFAULT.RefillAfter), 0, B.REFILL_MAX))
    end
    S.counts.took = S.counts.took + 1
    return true
end

-- the walk ended without getting on: the claim released (no use counted), the unserved players inside re-tested
function B.Cancel(ply, ent, slot, claim, why)
    local c, err = claim_of(ply, ent, slot, claim)
    if not c then return false, err end
    ent.GSA1Claim = nil
    S.counts.cancelled = S.counts.cancelled + 1
    B.Retest(ent)
    return true
end

-- the riding state of ply's character slot changed
function B.StateMsg(ply, on, why, ent, slot)
    -- (off is taken from anyone: a removed character's client says it after telling the server it stopped being one)
    if on and not is_char(ply) then return false, "not a character" end
    if slot == 0 and ply.SetNW2Bool then ply:SetNW2Bool(B.NW_RIDING, on and true or false) end
    if hook and hook.Run then hook.Run("GSA1BoardChanged", ply, on and true or false) end
    -- review R.3: a Board Off box's use counts only when the server sent this player OFF for it in the last 5 s
    if not on and why == WHY.OFF_BOX and IsValid(ent) and B.BoxKind(ent) == "off" then
        local t = track_of(ply)
        local at = t.offSent[ent]
        if at and now() - at <= B.OFF_USE_WINDOW then
            t.offSent[ent] = nil
            ent:SetUsed(num(ent, "Used", 0) + 1)
            return true, "used"
        end
    end
    return true
end

-- a left board: a bucket of 3 per player refilled at 1 a second (review R.5), finite, within 2,048 HU of his character
local function finite(v) return v == v and v > -1e9 and v < 1e9 end
function B.LeftOk(ply, place, ang, kind, variant)
    if not is_char(ply) then return false, "not a character" end
    if cv.sv_left_max:GetInt() <= 0 then return false, "left boards are off on this server" end
    if kind ~= B.KIND_SONIC and kind ~= B.KIND_TAILS then return false, "not a board kind" end
    if not (place and finite(place.x) and finite(place.y) and finite(place.z) and ang and finite(ang.p) and
        finite(ang.y) and finite(ang.r)) then
        return false, "not a place"
    end
    local s = ply.GSA1State
    if s and s.x then
        local dx, dy, dz = place.x - s.x, place.y - s.y, place.z - s.z
        if dx * dx + dy * dy + dz * dz > B.LEFT_RADIUS * B.LEFT_RADIUS then return false, "too far from the character" end
    elseif not (game.SinglePlayer and game.SinglePlayer()) then
        return false, "the server has no position of this character"
    end
    local tn = now()
    local b = ply.GSA1BoardLeft or { tokens = B.LEFT_BUCKET, t = tn }
    ply.GSA1BoardLeft = b
    b.tokens = math.min(B.LEFT_BUCKET, b.tokens + (tn - b.t) * B.LEFT_REFILL)
    b.t = tn
    if b.tokens < 1 then return false, "too many left boards at once" end
    b.tokens = b.tokens - 1
    return true
end

function B.Left(ply, place, ang, kind, variant, slot)
    local ok, why = B.LeftOk(ply, place, ang, kind, variant)
    if not ok then
        S.counts.refused = S.counts.refused + 1
        return nil, why
    end
    local ent = ents.Create(B.LEFT_CLASS)
    if not IsValid(ent) then return nil, "no left board entity" end
    ent:SetPos(Vector(place))
    ent:SetAngles(Angle(ang.p, ang.y, ang.r))
    if ent.SetKind then ent:SetKind(kind) end
    if ent.SetVariant then ent:SetVariant(math.Clamp(math.floor(tonumber(variant) or 0), 0, 15)) end
    if ent.SetSlot then ent:SetSlot(slot or 0) end
    if ent.SetRider then ent:SetRider(ply) end
    ent:Spawn()
    local life = cv.sv_left_time:GetFloat()
    ent.GSA1Expire = life > 0 and now() + life or nil
    ent.GSA1Owner = ply
    local list = S.left[ply] or {}
    S.left[ply] = list
    list[#list + 1] = ent
    -- at most gsa1_sv_board_left_max per player: the oldest goes
    local maxn = cv.sv_left_max:GetInt()
    while #list > maxn do
        local old = table.remove(list, 1)
        if IsValid(old) then old:Remove() end
    end
    if undo and undo.Create then
        undo.Create("gsa1_board_left")
        undo.AddEntity(ent)
        undo.SetPlayer(ply)
        if undo.SetCustomUndoText then undo.SetCustomUndoText("Undone G-SA1 left board") end
        undo.Finish()
    end
    if ply.AddCleanup then ply:AddCleanup("gsa1_board_left", ent) end
    S.counts.left = S.counts.left + 1
    return ent
end

net.Receive(B.NET.TOOK, function(len, ply)
    if not IsValid(ply) then return end
    local idx, slot, claim = net.ReadUInt(16), net.ReadUInt(4), net.ReadUInt(8)
    if not (is_char(ply) and rate_ok(ply)) then return end
    B.Took(ply, Entity(idx), slot, claim)
end)
net.Receive(B.NET.CANCEL, function(len, ply)
    if not IsValid(ply) then return end
    local idx, slot, claim, why = net.ReadUInt(16), net.ReadUInt(4), net.ReadUInt(8), net.ReadUInt(3)
    if not rate_ok(ply) then return end
    B.Cancel(ply, Entity(idx), slot, claim, why)
end)
net.Receive(B.NET.ST, function(len, ply)
    if not IsValid(ply) then return end
    local on, why, idx, slot = net.ReadBool(), net.ReadUInt(3), net.ReadUInt(16), net.ReadUInt(4)
    if not rate_ok(ply) then return end
    B.StateMsg(ply, on, why, idx > 0 and Entity(idx) or nil, slot)
end)
net.Receive(B.NET.LEFT, function(len, ply)
    if not IsValid(ply) then return end
    local place, ang = net.ReadVector(), net.ReadAngle()
    local kind, variant, slot = net.ReadUInt(4), net.ReadUInt(4), net.ReadUInt(4)
    B.Left(ply, place, ang, kind, variant, slot)
end)

-- the box's state back as placed: the board there, no use counted, no claim, nobody served there; then the players inside
function B.ResetBox(ent, reason)
    if not (IsValid(ent) and B.IsBox(ent)) then return end
    if ent.SetUsed then ent:SetUsed(0) end
    if ent.SetPresent then ent:SetPresent(true) end
    if ent.SetRespawnAt then ent:SetRespawnAt(0) end
    ent.GSA1Claim = nil
    for _, ply in ipairs(player.GetAll()) do
        local t = ply.GSA1BoardTrack
        if t then t.served[ent], t.offSent[ent], t.said[ent] = nil, nil, nil end
    end
    S.layoutDirty[ent] = true
    B.Retest(ent)
end

-- "Reset every Board box": admins, the listen server's host, single player, the server console
function B.MayResetAll(ply)
    if not IsValid(ply) then return true end
    if game.SinglePlayer() then return true end
    if ply.IsListenServerHost and ply:IsListenServerHost() then return true end
    return ply.IsAdmin ~= nil and ply:IsAdmin() == true
end
concommand.Add("gsa1_sv_board_reset", function(ply)
    if not B.MayResetAll(ply) then
        if IsValid(ply) and ply.ChatPrint then ply:ChatPrint("G-SA1: only an admin or the server's host may reset the boxes") end
        return
    end
    local n = 0
    for ent in pairs(S.boxes) do
        if IsValid(ent) then
            B.ResetBox(ent, "reset")
            n = n + 1
        end
    end
    print(string.format("[G-SA1] %d Board boxes reset by %s", n, IsValid(ply) and tostring(ply:Nick()) or "the console"))
end, nil, "G-SA1: every Board On / Off box back as placed - the boards there, no uses counted (admins and the host)")

-- every tick: the edge test on new state packets; every 0.1 s: claims, refills, new layouts, poses, frozen boxes, the left
-- boards' lifetime ------------------------------------------------------------------------------------------------------------
local exits = {}
function B.EdgeThink(t)
    if S.dirty then rebuild_list() end
    for _, ply in ipairs(player.GetAll()) do
        local s = ply.GSA1State
        if is_char(ply) and s and s.x and s.time then
            local tr = track_of(ply)
            if s.time ~= tr.stamp then
                tr.stamp = s.time
                S.counts.packets = S.counts.packets + 1
                for i = #exits, 1, -1 do exits[i] = nil end
                local ev = B.Edge(tr, S.list, s.x, s.y, s.z, s.time, exits)
                -- left a box (outside it by EXIT_PAD): served there no more (an OFF's use may still come in its window)
                for _, b in ipairs(exits) do tr.served[b.key] = nil end
                for i = 1, #ev do
                    local e = ev[i]
                    if cv.sv_on:GetBool() then B.Enter(ply, e.box.ent, 0) end
                end
            end
        elseif ply.GSA1BoardTrack and not is_char(ply) then
            -- not a character any more: a new character is tested from its first packet (a start inside a box boards);
            -- nobody rides
            ply.GSA1BoardTrack = nil
            if ply.GetNW2Bool and ply:GetNW2Bool(B.NW_RIDING, false) then ply:SetNW2Bool(B.NW_RIDING, false) end
        end
    end
end

function B.SlowThink(t)
    -- claims that timed out (the walk's deadline + 2 s), whatever the client says
    for ent in pairs(S.boxes) do
        if IsValid(ent) then
            local c = ent.GSA1Claim
            if c and (not IsValid(c.ply) or t - c.at > c.life) then
                ent.GSA1Claim = nil
                S.counts.timeouts = S.counts.timeouts + 1
                B.Retest(ent)
            end
            -- a refill
            if B.BoxKind(ent) == "on" and not ent:GetPresent() then
                local at = num(ent, "RespawnAt", 0)
                if at > 0 and t >= at and not B.Spent(ent) then
                    ent:SetPresent(true)
                    ent:SetRespawnAt(0)
                    S.counts.refills = S.counts.refills + 1
                    B.Retest(ent)
                end
            end
            if not ent.GSA1Held then
                local phys = ent.GetPhysicsObject and ent:GetPhysicsObject()
                if IsValid(phys) and phys.IsMotionEnabled and phys:IsMotionEnabled() then phys:EnableMotion(false) end
            end
        end
    end
    for ent in pairs(S.layoutDirty) do
        if not IsValid(ent) then
            S.layoutDirty[ent] = nil
        elseif not ent.GSA1Held then
            S.layoutDirty[ent] = nil
            B.ApplyHull(ent)
            B.BoardPlace(ent)
            if S.boxes[ent] then
                S.boxes[ent] = B.BoxData(ent)
                S.dirty = true
            end
        end
    end
    if t >= S.nextPose then
        S.nextPose = t + 0.25
        for ent, b in pairs(S.boxes) do
            if IsValid(ent) and not ent.GSA1Held and not same_sig(b, ent) then
                S.boxes[ent] = B.BoxData(ent)
                S.dirty = true
                B.BoardPlace(ent)
            end
        end
    end
    for p, list in pairs(S.left) do
        for i = #list, 1, -1 do
            local e = list[i]
            if not IsValid(e) then
                table.remove(list, i)
            elseif e.GSA1Expire and t >= e.GSA1Expire then
                table.remove(list, i)
                e:Remove()
            end
        end
        if #list == 0 then S.left[p] = nil end
    end
end

hook.Add("Think", "gsa1_board", function()
    local t = now()
    B.EdgeThink(t)
    if t < S.nextSlow then return end
    S.nextSlow = t + 0.1
    B.SlowThink(t)
end)

-- the Physics Gun: carried, then frozen again where it was dropped (its data and the board's place follow)
hook.Add("OnPhysgunPickup", "gsa1_board", function(ply, ent)
    if not B.IsBox(ent) then return end
    ent.GSA1Held = true
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        if phys.Wake then phys:Wake() end
    end
end)
hook.Add("PhysgunDrop", "gsa1_board", function(ply, ent)
    if not B.IsBox(ent) then return end
    ent.GSA1Held = nil
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:SetVelocity(Vector(0, 0, 0))
    end
    S.layoutDirty[ent] = true
end)

-- a player who leaves: his claims released, his left boards stay until their time
hook.Add("PlayerDisconnected", "gsa1_board", function(ply)
    for ent in pairs(S.boxes) do
        local c = IsValid(ent) and ent.GSA1Claim
        if c and c.ply == ply then
            ent.GSA1Claim = nil
            B.Retest(ent)
        end
    end
end)

-- boxes that existed before this file ran (a Lua refresh)
if ents and ents.FindByClass then
    for _, c in ipairs(B.CLASSES) do
        for _, e in ipairs(ents.FindByClass(c.class)) do
            if not S.boxes[e] then B.Register(e) end
        end
    end
end
