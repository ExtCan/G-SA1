-- G-SA1 feature "follower", client (round 0.9.8; sadc docs/research/gsa1_098_plan.md 2.4, 5.6, 5.9, 6.7; gsa1_096_plan.md 4.10,
-- 4.12-4.19, 4.21, 5.5-5.7, 6.5 with its reviews R.4-R.6, R.12, R.14, R.15, R.19; follow096_gsa1.md 3, 4.4-4.6, 7, 8).
--
-- The owner: followers run the game's own "1.5P" follower AI, each in its own libsa1 world (the module's feature "follower":
-- gsa1.FollowerCreate ... FollowersTick). This file keeps the list, chooses whom each follows, ticks them after your character,
-- chooses how each is drawn, and reacts to your character's life and to their worlds' events.
--   * GSA1.Followers = Fo: Fo.list (F tables in spawn order), Fo.byId[id], Fo.Count(eggOnly), Fo.RootOf(F) -> C | nil.
--     F = { id, kind, title, uid, egg, slot (1..15 for kinds 0 / 2, else nil), leaderId (nil: host-fed), target = { type = "me" |
--     "player" | "aim" | "follower" | "stay", ent, uid, pos, yaw }, state, ent, drawPos, drawYaw, lod (1 | 2 | 3), follower = true,
--     board (0.9.5's B.State table) }. Other features read these; only this file writes them.
--   * GSA1.SpawnFollower(kind, opts) -> true | false, reason: never raises; kind a name or a number; opts = { ignore_cap, target,
--     silent, objects, upgrades, why }.
--   * Hooks: GSA1FollowerCreated(F, why) before its first tick (why "page", "spawntab", "console", "egg", "re-created");
--     GSA1FollowerPostTick(F, state, dt) after its tick and render; GSA1FollowerRemoved(F, why) with its world still there
--     (why "removed", "cap", "fault", "map", "undo", "target"). None runs for your character; your GSA1Character* hooks never run
--     for a follower.
--   * The seam GSA1.FollowerTickCamera(C) -> origin, target | nil (decision A9): the camera FollowersTick gets.
--   * Per frame (D10): no engine call that returns a Vector or an Angle per follower. Exceptions, one per TARGET, not per
--     follower: a host-fed target's own entity (position, velocity, facing), read once a frame per entity.
--   * Round 0.9.9 (sadc docs/research/gsa1_099_plan.md 4.1 B3-B5, follow099.md 5, 6.3), three options on the page: Fo.ApplySpeed(F) (the catch-up,
--     gsa1_follower_speed), Fo.ApplySpots() (each follower's own spot around the one it follows, gsa1_follower_spacing), Fo.EmoteStart / Fo.EmoteThink /
--     Fo.EmoteEnd (Fo.emote: they play the same page and slot of their own wheels while you play yours, gsa1_follower_emotes, through W.ON_PLAYED).
GSA1 = GSA1 or {}

-- Seam L2 (decision A9): the camera the followers' tick gets. feat/cl_gamecam.lua wraps it while the fishing camera shows
-- (the chase eye: else a follower's respawn drops it 50 units above the lake). By default GSA1.TickCamera(C), asked through
-- the table, so a later wrap of either reaches the followers.
function GSA1.FollowerTickCamera(C)
    if GSA1.TickCamera then return GSA1.TickCamera(C) end
    return nil
end

local Fo = GSA1.Followers
if not Fo then return end
local cv = Fo.cv
local W = GSA1.Wheel                     -- feat/sh_wheel.lua (the sh_ files load before every cl_ file)
GSA1.cv.follower_other_views = cv.other_views   -- (cl_render.lua reads it)
-- round 0.9.9a (N7, sadc build/research/r099a/stop/diagnosis.md): the game's own AI keeps a stopped follower in its walk at speed 0, on one frame (the real game's Tails too); on: the game's own stand and idle
cv.fix_stand = GSA1.ConVar("gsa1_follower_fix_stand", 1, "Followers that stop go to their stand and idle (0 = the game's own: they stay in a still pose, as the real game's Tails does)", 0, 1)

Fo.list = Fo.list or {}
Fo.byId = Fo.byId or {}
Fo.byToken = Fo.byToken or {}
Fo.goneIds = Fo.goneIds or {}            -- the ids of followers that went: a late event of theirs is dropped
Fo.nextUid = Fo.nextUid or 1
Fo.tickOut = Fo.tickOut or {}            -- FollowersTick's table (reused)
Fo.TARGET_NAMES = { [0] = "me", [1] = "player", [2] = "follower", [3] = "aim", [4] = "stay" }
Fo.TARGET_VALUES = { me = 0, player = 1, follower = 2, aim = 3, stay = 4 }
local EV_FOLLOW = 16                     -- SA1_EVENT_FOLLOW; id: 1 a respawn (arg why), 2 the leader lost, 3 an item it broke

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("follower", fmt, ...) end
end
local function run_hook(name, ...)
    if GSA1.RunHook then return GSA1.RunHook(name, ...) end
end

-- the module ------------------------------------------------------------------------------------------------------------------
local have_cache, have_at = false, -1e9
function Fo.Have()
    local t = SysTime()
    if t - have_at > 2 then
        have_at = t
        have_cache = (GSA1.HasFeature ~= nil and GSA1.HasFeature(Fo.NEEDS.feature, Fo.NEEDS.version) and gsa1 ~= nil and
            gsa1.FollowerCreate ~= nil) and true or false
        if have_cache and not Fo.threadsSent then Fo.ApplyThreads() end
    end
    return have_cache
end
function Fo.ResetHave() have_at = -1e9 end

-- "CPU threads for followers" (module-wide)
function Fo.ApplyThreads()
    if not (GSA1.mod and gsa1 and gsa1.FollowerThreads) then return false end
    gsa1.FollowerThreads(cv.threads:GetInt())
    Fo.threadsSent = true
    return true
end
cvars.AddChangeCallback("gsa1_follower_threads", function() Fo.ApplyThreads() end, "gsa1_follower")

-- which kinds can follow: [kind] = true | the plain reason (libsa1's; "followers are not built yet" in an unfinished library)
Fo.kindsOut = Fo.kindsOut or {}
function Fo.KindsNow()
    if not (Fo.Have() and gsa1.FollowerKinds) then return {} end
    return gsa1.FollowerKinds(Fo.kindsOut) or {}
end
-- why a kind cannot be spawned now (nil: it can)
function Fo.WhyNot(kind)
    if not cv.on:GetBool() then return "Followers are off (Followers page)" end
    if not Fo.Have() then return "this G-SA1 module has no followers" end
    local k = Fo.KindsNow()[kind]
    if k ~= true then return type(k) == "string" and k or (Fo.KindTitle(kind) .. " cannot follow") end
    return nil
end

-- counts --------------------------------------------------------------------------------------------------------------------
-- eggOnly true: the ones made with ignore_cap (the secret's); else the normal ones
function Fo.Count(eggOnly)
    local n = 0
    local want = eggOnly == true
    for _, F in ipairs(Fo.list) do
        if (F.egg == true) == want then n = n + 1 end
    end
    return n
end
function Fo.Cap()
    return math.min(math.max(cv.max:GetInt(), 0), Fo.NORMAL_MAX)
end
function Fo.FreeSlot()
    local used = {}
    for _, F in ipairs(Fo.list) do
        if F.slot then used[F.slot] = true end
    end
    for s = 1, Fo.BOARD_SLOTS do
        if not used[s] then return s end
    end
    return nil
end

-- whom it follows ---------------------------------------------------------------------------------------------------------------
function Fo.ByUid(uid)
    for _, F in ipairs(Fo.list) do
        if F.uid == uid then return F end
    end
    return nil
end

-- the nearest other player to a point (nil: nobody else is here)
local function other_players()
    local out, ply = {}, LocalPlayer()
    if player and player.GetAll then
        for _, p in ipairs(player.GetAll()) do
            if IsValid(p) and p ~= ply then out[#out + 1] = p end
        end
    end
    return out
end
local function nearest_player(pos)
    local best, bd = nil, nil
    for _, p in ipairs(other_players()) do
        local pp = p:GetPos()
        local dx, dy, dz = pp.x - pos.x, pp.y - pos.y, pp.z - pos.z
        local d = dx * dx + dy * dy + dz * dz
        if not bd or d < bd then best, bd = p, d end
    end
    return best
end

-- what "want" means now: a target table, or nil and why. want: 0 .. 4, a word, or a target table
function Fo.MakeTarget(want)
    if type(want) == "table" then return want end
    local name = type(want) == "string" and want or Fo.TARGET_NAMES[tonumber(want) or 0]
    name = string.lower(tostring(name or "me"))
    if tonumber(name) then name = Fo.TARGET_NAMES[tonumber(name)] or "me" end
    local ply = LocalPlayer()
    if name == "me" then return { type = "me" } end
    if name == "player" then return { type = "player" } end
    if name == "follower" or name == "last" then
        local G = Fo.list[#Fo.list]
        if not G then return { type = "me" } end
        return { type = "follower", uid = G.uid }
    end
    if name == "aim" then
        local tr = IsValid(ply) and ply.GetEyeTrace and ply:GetEyeTrace()
        local e = tr and tr.Entity
        if IsValid(e) and e ~= ply and ((e.IsNPC and e:IsNPC()) or (e.IsPlayer and e:IsPlayer())) then
            return { type = "aim", ent = e }
        end
        return nil, "aim at an NPC or a player first"
    end
    if name == "stay" then
        local C = GSA1.Char
        return { type = "stay", pos = Vector(C and C.drawPos or ply:GetPos()),
                 yaw = C and (C.drawYaw or C.spawnYaw) or ply:EyeAngles().y }
    end
    return nil, "unknown target " .. name
end

-- the libsa1 leader this target has now: the character / follower entry, or nil (host-fed)
function Fo.TargetLeader(t, C)
    C = C or GSA1.Char
    if t.type == "me" or (t.type == "player" and not IsValid(t.ent)) then return C end
    if t.type == "follower" then return Fo.ByUid(t.uid) end
    return nil
end

-- the entity a host-fed target stands for (nil: a frozen point, or a walk's)
function Fo.TargetEntity(t, C)
    if t.type == "player" or t.type == "aim" then
        if IsValid(t.ent) then return t.ent end
    end
    if t.type == "me" or t.type == "player" then
        if not (C or GSA1.Char) then return LocalPlayer() end
    end
    return nil
end

-- where a new follower appears: Fo.BEHIND HU behind what it follows, along that one's facing; and that facing
function Fo.BehindLeader(t, C)
    local base, yaw
    local L = Fo.TargetLeader(t, C)
    if L then
        base, yaw = L.drawPos, L.drawYaw or L.spawnYaw or 0
    elseif t.type == "stay" then
        base, yaw = t.pos, t.yaw or 0
    else
        local e = Fo.TargetEntity(t, C) or LocalPlayer()
        base = e:GetPos()
        yaw = (e == LocalPlayer() or not e.GetAngles) and e:EyeAngles().y or e:GetAngles().y
    end
    local r = math.rad(yaw)
    return Vector(base.x - math.cos(r) * Fo.BEHIND, base.y - math.sin(r) * Fo.BEHIND, base.z + 1), yaw
end

-- the chain above F: does G already follow F (directly or through others)?
local function follows(G, F)
    local guard = 0
    while G and guard < 256 do
        if G == F then return true end
        local t = G.target
        G = t and t.type == "follower" and Fo.ByUid(t.uid) or nil
        guard = guard + 1
    end
    return false
end
Fo.Follows = follows

-- your character when F's chain ends at it, else nil
function Fo.RootOf(F)
    local C = GSA1.Char
    local guard = 0
    while F and guard < 256 do
        local t = F.target
        if not t then return nil end
        if t.type == "follower" then
            F = Fo.ByUid(t.uid)
        elseif t.type == "me" or (t.type == "player" and not IsValid(t.ent)) then
            return C
        else
            return nil
        end
        guard = guard + 1
    end
    return nil
end
-- F's chain ends at you (your character, or your player entity without one)
local function is_mine(F)
    local guard = 0
    while F and guard < 256 do
        local t = F.target
        if not t then return false end
        if t.type == "follower" then
            F = Fo.ByUid(t.uid)
        else
            return t.type == "me" or (t.type == "player" and not IsValid(t.ent))
        end
        guard = guard + 1
    end
    return false
end

-- the entry of F's libsa1 leader (your character or a follower; nil: host-fed)
function Fo.LeaderEntry(F)
    local id = F.leaderId
    if not id then return nil end
    local C = GSA1.Char
    if C and C.id == id then return C end
    return Fo.byId[id]
end

-- F's target into the module: its leader link, or host-fed. C: your character when GSA1.Char is not it yet (a Created hook)
function Fo.ApplyTarget(F, C)
    local t = F.target
    local L = Fo.TargetLeader(t, C)
    if F.walkFeed then return true end          -- (a walk to a box's board: its link comes back when it ends)
    local lid = L and L.id or nil
    local ok, err, code = gsa1.FollowerLeader(F.id, lid)
    if not ok then return false, tostring(err), code end
    F.leaderId = lid
    F.hostFed = lid == nil
    F.fedStay = nil
    return true
end

-- F follows something else. want: as Fo.MakeTarget. -> true | false, reason
function Fo.SetTarget(F, want)
    local t, why = Fo.MakeTarget(want)
    if not t then return false, why end
    if t.type == "follower" then
        local G = Fo.ByUid(t.uid)
        if G == F then
            -- "my last follower" for the newest one itself: the one before it
            local idx
            for i, H in ipairs(Fo.list) do
                if H == F then idx = i end
            end
            G = idx and Fo.list[idx - 1] or nil
            if not G then return false, F.title .. " has no other follower to follow" end
            t = { type = "follower", uid = G.uid }
        end
        if follows(G, F) then
            return false, string.format("%s already follows %s", G.title or "?", F.title or "?")
        end
    end
    local was = F.target
    F.target = t
    local ok, err = Fo.ApplyTarget(F)
    if not ok then
        F.target = was
        return false, tostring(err)
    end
    log("%s (follower %d) now follows %s", F.title or "?", F.uid, Fo.TargetText(F))
    return true
end

-- a lost target: its leader's leader, at the end you (one log line)
function Fo.LoseTarget(F, why, inherited)
    F.target = inherited or { type = "me" }
    log("%s (follower %d): %s; it now follows %s", F.title or "?", F.uid, tostring(why), Fo.TargetText(F))
    Fo.ApplyTarget(F)
end

-- the walk to a box's board (feat/cl_board.lua): host-fed at that place, standing; the AI walks there with the game's steering
function Fo.WalkTo(F, pos, yaw)
    gsa1.FollowerLeader(F.id, nil)
    F.leaderId, F.hostFed = nil, true
    F.walkFeed = { pos = pos, yaw = yaw }
    Fo.ApplySpots()     -- (0.9.9: its spot is 0 during the walk, or the AI stops off the board)
end
function Fo.WalkEnd(F)
    F.walkFeed = nil
    if F.removed then return end
    Fo.ApplyTarget(F)
    Fo.ApplySpots()
end

-- whom it follows, in words (the page's rows)
function Fo.TargetText(F)
    local t = F.target or {}
    if t.type == "me" then return "you" end
    if t.type == "player" then
        if IsValid(t.ent) then return (t.ent.Nick and t.ent:Nick()) or "a player" end
        return "you (nobody else is here)"
    end
    if t.type == "follower" then
        local G = Fo.ByUid(t.uid)
        return G and string.format("%s (%d)", G.title or "?", G.uid) or "you"
    end
    if t.type == "aim" then
        return IsValid(t.ent) and (t.ent.GetClass and t.ent:GetClass() or "what you aimed at") or "you"
    end
    if t.type == "stay" then return "nobody (it stays)" end
    return "?"
end

-- the feeds (host-fed): one reading per entity per frame, into reused objects (D10) -----------------------------------------------
Fo.snaps = Fo.snaps or setmetatable({}, { __mode = "k" })
local ZERO = Vector(0, 0, 0)
local function snap_of(e, fn)
    local s = Fo.snaps[e]
    if not s then
        s = { frame = -1, pos = Vector(), vel = Vector(), yaw = 0, ground = true }
        Fo.snaps[e] = s
    end
    if s.frame ~= fn then
        s.frame = fn
        s.pos:Set(e:GetPos())
        if e.GetVelocity then s.vel:Set(e:GetVelocity()) end
        if e == LocalPlayer() then
            s.yaw = e:EyeAngles().y
        elseif e.GetAngles then
            s.yaw = e:GetAngles().y
        end
        if e.OnGround then s.ground = e:OnGround() and true or false end
    end
    return s
end
function Fo.Feed(F, fn)
    local wf = F.walkFeed
    if wf then
        gsa1.FollowerFeed(F.id, wf.pos, ZERO, wf.yaw, true)
        return
    end
    local t = F.target
    if t.type == "stay" then
        -- a frozen point: once (and again after a relink)
        if not F.fedStay then
            F.fedStay = true
            gsa1.FollowerFeed(F.id, t.pos, ZERO, t.yaw or 0, true)
        end
        return
    end
    local e = Fo.TargetEntity(t)
    if not IsValid(e) then return end
    local s = snap_of(e, fn)
    gsa1.FollowerFeed(F.id, s.pos, s.vel, s.yaw, s.ground)
end

-- once a second: the nearest player chosen again; every frame a lost entity falls back
function Fo.RefreshTargets(now)
    local list = Fo.list
    if now >= (Fo.nextTargets or 0) then
        Fo.nextTargets = now + 1
        for _, F in ipairs(list) do
            local t = F.target
            if t.type == "player" then
                local p = nearest_player(F.drawPos)
                if p ~= t.ent then
                    t.ent = p
                    Fo.ApplyTarget(F)
                end
            end
        end
    end
    for i = 1, #list do
        local F = list[i]
        local t = F.target
        if t.type == "aim" and not IsValid(t.ent) then
            Fo.LoseTarget(F, "what it followed went away")
        elseif t.type == "player" and t.ent ~= nil and not IsValid(t.ent) then
            t.ent = nil
            log("%s (follower %d): the player it followed left; it now follows you", F.title or "?", F.uid)
            Fo.ApplyTarget(F)
        end
    end
end

-- keeping up and standing apart (round 0.9.9; every value is the host's option: follow099.md 3.5, 4.2) ---------------------------------
Fo.refusedNotes = Fo.refusedNotes or {}
local function note_refused(F, what, err)
    if Fo.refusedNotes[what] then return end
    Fo.refusedNotes[what] = true
    log("%s (follower %d): %s: %s", F.title or "?", F.uid or 0, what, tostring(err))
end
-- at 1 libsa1 never writes a number of the world: a follower near its spot runs at the game's own speed at any value
function Fo.ApplySpeed(F)
    if not (gsa1 and gsa1.FollowerSpeed) then return false end
    local ok, err = gsa1.FollowerSpeed(F.id, math.Clamp(cv.speed:GetFloat(), 1, Fo.SPEED_MAX))
    if not ok then note_refused(F, "the catch-up speed", err) end
    return ok and true or false
end
-- the stand (not in the game; the option's words: the ConVar above). Off: libsa1 is the game's own, bit for bit
function Fo.ApplyStand(F)
    if not (gsa1 and gsa1.FollowerStand) then return false end
    local ok, err = gsa1.FollowerStand(F.id, cv.fix_stand:GetBool())
    if not ok then note_refused(F, "its stand", err) end
    return ok and true or false
end
-- every follower's spot, by its place in the list. One follower alone stands where the game puts it; so does one walking to a box's board.
-- 0 turns them off for all; while the secret's followers are here all use Fo.SPACING_EGG. A call only for a spot that changed
function Fo.ApplySpots()
    if not (gsa1 and gsa1.FollowerSpot) then return end
    local list = Fo.list
    local n = #list
    local s = cv.spacing:GetFloat()
    if s > 0 and Fo.Count(true) > 0 then s = Fo.SPACING_EGG end
    for i = 1, n do
        local F = list[i]
        local x, y = 0, 0
        if not F.walkFeed then x, y = Fo.SpotOf(i, n, s) end
        if x ~= (F.spotX or 0) or y ~= (F.spotY or 0) then
            local ok, err = gsa1.FollowerSpot(F.id, x, y)
            if ok then
                F.spotX, F.spotY = x, y
            else
                note_refused(F, "its spot", err)
            end
        end
    end
end

-- the entry ---------------------------------------------------------------------------------------------------------------------
-- the world: -> id | nil, message, code
local function create_world(kind, target, opts, C)
    local pos, yaw = Fo.BehindLeader(target, C)
    local L = Fo.TargetLeader(target, C)
    local o = {
        objects = tonumber(opts.objects) or cv.objects:GetInt(),
        sounds = (not opts.silent) and cv.sounds:GetBool(),
        fix_view = cv.fix_view:GetBool(),
        fix_respawn = cv.fix_respawn:GetBool(),
    }
    if opts.upgrades ~= false and cv.upgrades:GetBool() then
        o.upgrades = (type(opts.upgrades) == "table") and opts.upgrades or GSA1.UpgradeNames(kind)
    end
    local id, err, code = gsa1.FollowerCreate(kind, pos, yaw, L and L.id or nil, o)
    return id, err, code, pos, yaw, o
end

-- the kinds of host objects a follower's world mirrors (096 4.19): enemies and hazards knock it back; it holds nothing. The mask
-- is libsa1's SA1_HOSTOBJ_KIND_BIT(kind) bits. 0 means EVERY kind there (sa1_world_hostobj.c ho_kind_on), not none, and no value
-- means none: the secret's followers (review R.19: mirror no enemy at all, 99 worlds) get the bit of the rarest kind only.
local function kind_bit(name, default)
    local t = gsa1 and gsa1.INTERACT
    return bit.lshift(1, tonumber(t and t[name]) or default)
end
function Fo.HostObjMask(egg)
    if egg then return kind_bit("BALLOON", 6) end
    return bit.bor(kind_bit("ENEMY", 1), kind_bit("HAZARD", 4))
end

function Fo.MakeEntry(id, kind, opts, target, pos, yaw, C)
    local def = GSA1.CharacterByKind(kind)
    if GSA1.Tex and GSA1.Tex.Prepare and not (Fo.prepared and Fo.prepared[kind]) then
        Fo.prepared = Fo.prepared or {}
        Fo.prepared[kind] = true
        GSA1.Tex.Prepare(kind)
    end
    local ent = ents.CreateClientside("gsa1_render")
    ent:Spawn()
    local uid = Fo.nextUid
    Fo.nextUid = uid + 1
    local L = Fo.TargetLeader(target, C)
    local F = {
        id = id, kind = kind, name = def and def.name or tostring(kind), title = def and def.title or tostring(kind), def = def,
        uid = uid, egg = opts.ignore_cap == true, target = target, leaderId = L and L.id or nil, hostFed = L == nil,
        info = gsa1.CharacterInfo and gsa1.CharacterInfo(kind) or {}, state = {}, batches = { count = 0 }, batchGen = -1, mats = {},
        static = {}, matsDirty = true, ent = ent, drawPos = Vector(pos), drawYaw = yaw, spawnYaw = yaw, lod = 1, interp = true,
        renderGen = 0, follower = true, finfo = {}, faults = {}, drops = {}, opts = opts, respawns = 0,
        nextInfo = SysTime() + (uid % 16) / 64,        -- (the 4 Hz reading, spread over the frames)
    }
    if kind == 0 or kind == 2 then F.slot = Fo.FreeSlot() end
    ent.char = F
    gsa1.GetState(id, F.state)
    if F.state.x then F.drawPos:SetUnpacked(F.state.x, F.state.y, F.state.z) end
    ent:SetPos(F.drawPos)
    Fo.list[#Fo.list + 1] = F
    Fo.byId[id] = F
    -- 0.9.9: before its first tick
    Fo.ApplyStand(F)
    Fo.ApplySpeed(F)
    Fo.ApplySpots()
    -- host objects, Tails' tail blend, the item icon guard (its own game's rings and boxes)
    if gsa1.ObjWorldMask then gsa1.ObjWorldMask(id, Fo.HostObjMask(F.egg)) end
    if GSA1.CharOpt and GSA1.CharOpt.ApplyTailBlend then GSA1.CharOpt.ApplyTailBlend(F) end
    if (tonumber(opts.objects) or cv.objects:GetInt()) ~= 0 and GSA1.Objects and GSA1.Objects.ApplyIconGuard then
        GSA1.Objects.ApplyIconGuard(F)
    end
    return F
end

local function spawn_follower(kind, opts)
    local k, def = tonumber(kind), nil
    if not k and type(kind) == "string" then k, def = GSA1.KindByName(kind) end
    if not k then return false, "unknown character " .. tostring(kind) end
    if (def and def.form) or not Fo.KINDS[k] then
        return false, (def and def.title or tostring(kind)) .. " is not a character that can follow"
    end
    local why = Fo.WhyNot(k)
    if why then return false, why end
    local ok, err = GSA1.EnsureReady()
    if not ok then
        if err == "loading" then return false, "loading: " .. tostring(GSA1.LoadingText and GSA1.LoadingText() or "the disc") end
        return false, tostring(err)
    end
    if opts.ignore_cap then
        if Fo.Count(true) >= Fo.EGG_MAX then return false, "99 followers made by the secret: the most" end
    else
        local n = Fo.Count(false)
        if n >= Fo.Cap() then
            return false, string.format("you have %d followers (the most at once: Followers page)", n)
        end
    end
    local target, terr = Fo.MakeTarget(opts.target == nil and cv.target:GetInt() or opts.target)
    if not target then return false, terr end
    local t0 = SysTime()
    local id, cerr, code, pos, yaw = create_world(k, target, opts)
    if not id then
        if GSA1.Log then GSA1.Log("follower", "no %s follower: %s", Fo.KindTitle(k), tostring(cerr)) end
        return false, tostring(cerr)
    end
    if GSA1.DrainLog then GSA1.DrainLog() end
    Fo.worldSeen = GSA1.worldInfo
    if not Fo.settingsLogged and GSA1.Log then
        Fo.settingsLogged = true
        GSA1.Log("settings", "followers: at most %d, new ones follow %s, upgrades %s, rings and boxes %s, sounds %s, board %s, boxes %s, "
            .. "come along %s, loop guard %s, fixes view %s respawn %s, full detail %d, far rate %d, draw distance %d, other views %s, "
            .. "threads %d, catch-up speed %s, room between them %s, emote with you %s, stand and idle %s", cv.max:GetInt(), tostring(Fo.TARGET_NAMES[cv.target:GetInt()]),
            cv.upgrades:GetString(), cv.objects:GetString(), cv.sounds:GetString(), cv.board:GetString(), cv.board_boxes:GetString(),
            cv.come_along:GetString(), cv.loop_guard:GetString(), cv.fix_view:GetString(), cv.fix_respawn:GetString(), cv.full_detail:GetInt(),
            cv.far_rate:GetInt(), cv.draw_dist:GetInt(), cv.other_views:GetString(), cv.threads:GetInt(), cv.speed:GetString(),
            cv.spacing:GetString(), cv.emotes:GetString(), cv.fix_stand:GetString())
    end
    local F = Fo.MakeEntry(id, k, opts, target, pos, yaw)
    run_hook("GSA1FollowerCreated", F, opts.why or "spawned")
    log("%s follower %d made in %.1f ms (%s; follows %s; slot %s; %d followers)", F.title, F.uid, (SysTime() - t0) * 1000,
        tostring(opts.why or "spawned"), Fo.TargetText(F), tostring(F.slot or "-"), #Fo.list)
    return true, F
end

function GSA1.SpawnFollower(kind, opts)
    local ok, a, b = pcall(spawn_follower, kind, type(opts) == "table" and opts or {})
    if not ok then
        if GSA1.Log then GSA1.Log("error", "GSA1.SpawnFollower: %s", tostring(a)) end
        return false, tostring(a)
    end
    return a, b
end

-- the world and the entity go; its followers take its target first
function Fo.Remove(F, why)
    if F.removed then return end
    F.removed = true
    why = why or "removed"
    run_hook("GSA1FollowerRemoved", F, why)
    Fo.byId[F.id] = nil
    for i, H in ipairs(Fo.list) do
        if H == F then
            table.remove(Fo.list, i)
            break
        end
    end
    for _, G in ipairs(Fo.list) do
        local t = G.target
        if t.type == "follower" and t.uid == F.uid then
            local inherited = F.target
            if inherited.type == "aim" or inherited.type == "player" or inherited.type == "stay" then
                inherited = { type = inherited.type, ent = inherited.ent, pos = inherited.pos, yaw = inherited.yaw }
            elseif inherited.type == "follower" then
                inherited = { type = "follower", uid = inherited.uid }
            else
                inherited = { type = "me" }
            end
            Fo.LoseTarget(G, F.title .. " went away", inherited)
        end
    end
    Fo.goneIds[F.id] = true
    if F.token then Fo.byToken[F.token] = nil end
    if GSA1.mod and gsa1 and gsa1.Destroy then gsa1.Destroy(F.id) end
    if GSA1.FreeStaticMeshes then GSA1.FreeStaticMeshes(F) end
    if IsValid(F.ent) then F.ent:Remove() end
    Fo.EmoteForget(F)
    Fo.ApplySpots()
    log("%s (follower %d) removed (%s); %d followers left", F.title or "?", F.uid, tostring(why), #Fo.list)
end

function Fo.RemoveAll(why)
    for i = #Fo.list, 1, -1 do Fo.Remove(Fo.list[i], why) end
end

-- the newest normal one goes first (the cap slider, "Remove the last")
function Fo.Newest(normal)
    for i = #Fo.list, 1, -1 do
        local F = Fo.list[i]
        if not normal or not F.egg then return F end
    end
    return nil
end

-- the same follower made again behind its leader (a fault, a death of its world, its upgrades, the map's collision): its uid,
-- slot, target and token stay; GSA1FollowerRemoved / GSA1FollowerCreated run. -> the new entry | nil
function Fo.Recreate(F, why, removedWhy)
    if F.removed then return nil end
    local keep = F
    local kind, target, opts = F.kind, F.target, F.opts
    local uid, slot, token, faults, drops, egg = F.uid, F.slot, F.token, F.faults, F.drops, F.egg
    F.removed = true
    run_hook("GSA1FollowerRemoved", F, removedWhy or "removed")
    Fo.byId[F.id] = nil
    Fo.goneIds[F.id] = true
    local at
    for i, H in ipairs(Fo.list) do
        if H == F then
            at = i
            break
        end
    end
    if at then table.remove(Fo.list, at) end
    gsa1.Destroy(F.id)
    GSA1.FreeStaticMeshes(F)
    if IsValid(F.ent) then F.ent:Remove() end
    Fo.EmoteForget(F)
    local id, err, _, pos, yaw = create_world(kind, target, opts)
    if not id then
        log("%s (follower %d) could not be made again: %s", keep.title or "?", uid, tostring(err))
        if token then Fo.byToken[token] = nil end
        for _, G in ipairs(Fo.list) do
            if G.target.type == "follower" and G.target.uid == uid then Fo.LoseTarget(G, keep.title .. " went away") end
        end
        Fo.ApplySpots()
        return nil
    end
    local NF = Fo.MakeEntry(id, kind, opts, target, pos, yaw)
    -- (MakeEntry put it last and took a new uid and slot: it is the same follower)
    table.remove(Fo.list)
    table.insert(Fo.list, at or (#Fo.list + 1), NF)
    NF.uid, NF.slot, NF.token, NF.faults, NF.drops, NF.egg = uid, slot, token, faults, drops, egg
    if token then Fo.byToken[token] = NF end
    Fo.nextUid = Fo.nextUid - 1
    if keep.heldBack then NF.heldBack = true end
    for _, G in ipairs(Fo.list) do
        if G.target.type == "follower" and G.target.uid == uid then Fo.ApplyTarget(G) end
    end
    Fo.ApplySpots()     -- (it is back at its place in the list)
    run_hook("GSA1FollowerCreated", NF, "re-created")
    log("%s (follower %d) made again behind its leader (%s)", NF.title or "?", uid, tostring(why))
    return NF
end

-- a fault of its world: made again, FAULT_MAX within FAULT_WINDOW s: removed with one chat line; your character never stops
function Fo.Fault(F, msg, code)
    local now = SysTime()
    local fl = F.faults
    for i = #fl, 1, -1 do
        if now - fl[i] > Fo.FAULT_WINDOW then table.remove(fl, i) end
    end
    fl[#fl + 1] = now
    if GSA1.Log then
        GSA1.Log("fault", "%s (follower %d): game code fault %d within %d s: %s", F.title or "?", F.uid, #fl, Fo.FAULT_WINDOW,
            tostring(msg))
    end
    if #fl >= Fo.FAULT_MAX then
        GSA1.Chat("%s (follower) stopped: its game code faulted %d times within %d s (see the session log)", F.title or "?",
            Fo.FAULT_MAX, Fo.FAULT_WINDOW)
        Fo.Remove(F, "fault")
        return
    end
    Fo.Recreate(F, "a game code fault", "fault")
end

-- an event of a follower's world (cl_character.lua GSA1.DispatchEvent): true when it was a follower's; a removed one's late
-- event is dropped
function GSA1.FollowerEvent(e, now)
    local id = e.character
    if not id or id == 0 then return false end
    local F = Fo.byId[id]
    if not F then return Fo.goneIds[id] == true end
    local EV = GSA1.EV
    local ty = e.type
    if ty == EV.FAULT then
        Fo.Fault(F, string.format("address %08X", tonumber(e.id) or 0), "fault")
    elseif ty == EV.DEATH or ty == EV.RESTART then
        log("%s (follower %d): its game ended (event %d, cause %s): made again behind its leader, no life lost", F.title or "?",
            F.uid, ty, tostring(e.arg))
        Fo.Recreate(F, "the game ended it")
    elseif ty == EV.CAPACITY then
        F.capacityAt = F.capacityAt or {}
        local t = SysTime()
        if t >= (F.capacityAt[e.id] or 0) then
            F.capacityAt[e.id] = t + 5
            if GSA1.Log then
                GSA1.Log("capacity", "(follower) %s at (%.0f %.0f %.0f): %s (%s)", F.title or "?", e.x or 0, e.y or 0, e.z or 0,
                    (GSA1.CAPACITY_TEXT and GSA1.CAPACITY_TEXT[e.id]) or ("limit " .. tostring(e.id)), tostring(e.arg))
            end
        end
    elseif ty == EV_FOLLOW then
        if e.id == 2 then
            log("%s (follower %d): the leader was lost (%s)", F.title or "?", F.uid, tostring(e.arg))
        elseif e.id == 3 then
            log("%s (follower %d): an item box gave it an item (%s); nothing changes for you", F.title or "?", F.uid, tostring(e.arg))
        end
    end
    return true
end

-- your character's life ----------------------------------------------------------------------------------------------------------
-- a riding follower gets off first: Tails' board handler swallows the hold's order 12 (096 review R.5)
function Fo.Hold(F, on)
    local B = GSA1.Board
    if on and B and F.board and F.board.on and B.Off then
        F.board.stayOff = true
        B.Off(F, "leader left", nil, nil)
    end
    if on and B and F.board and F.board.fwalk and B.FollowerWalkEnd then B.FollowerWalkEnd(F, "it is held") end
    if not on and F.board then F.board.stayOff = nil end
    local ok, err = gsa1.FollowerHold(F.id, on and true or false)
    if not ok then log("%s (follower %d): hold %s: %s", F.title or "?", F.uid, tostring(on), tostring(err)) end
    return ok
end

-- every follower whose chain ends at character C
local function chain_of(C, fn)
    for _, F in ipairs(Fo.list) do
        local G, guard = F, 0
        while G and guard < 256 do
            if G.leaderId == C.id then
                fn(F)
                break
            end
            local t = G.target
            G = t and t.type == "follower" and Fo.ByUid(t.uid) or nil
            guard = guard + 1
        end
    end
end

hook.Add("GSA1CharacterLeaving", "gsa1_follower", function(C, how)
    Fo.EmoteEnd(Fo.EmoteConst("STOP_NOW", 0), "your character is leaving")
    if not C or not Fo.list[1] or not cv.come_along:GetBool() then return end
    chain_of(C, function(F)
        if Fo.Hold(F, true) then
            F.heldBack = true
            F.held = true
        end
    end)
    Fo.heldAt = SysTime()
end)

-- relink: a target "me" gets the new character (C) or your player entity (nil)
function Fo.Relink(C)
    local walks = false
    for _, F in ipairs(Fo.list) do
        local t = F.target
        if t.type == "me" or (t.type == "player" and not IsValid(t.ent)) then
            if F.walkFeed then
                F.walkFeed = nil
                walks = true
                if F.board then F.board.fwalk = nil end
            end
            Fo.ApplyTarget(F, C)
        end
    end
    if walks then Fo.ApplySpots() end       -- (0.9.9: a walk that ended here gets its spot back)
end
-- the ones parked for your character's change come back: the game's mode 0 places them behind the leader
function Fo.ReleaseHeld()
    for _, F in ipairs(Fo.list) do
        if F.heldBack then
            F.heldBack = nil
            F.held = false
            Fo.Hold(F, false)
        end
    end
    Fo.heldAt = nil
end

hook.Add("GSA1CharacterCreated", "gsa1_follower", function(C, how, old)
    if not C or not Fo.list[1] then return end
    Fo.Relink(C)
    Fo.ReleaseHeld()
end)

hook.Add("GSA1CharacterRemoved", "gsa1_follower", function(C, switching)
    if switching or not Fo.list[1] then return end
    -- the ones that mirrored it get off (B's handler runs the same edge, whichever comes first)
    if C and C.board and C.board.on and GSA1.Board and GSA1.Board.Mirror then GSA1.Board.Mirror(C, false, "removed") end
    Fo.Relink(nil)
    Fo.ReleaseHeld()
end)

-- "come back to me": the game's own respawn (in from 50 units above the camera) -> how many
function Fo.CallOne(F)
    if F.removed or F.held then return false end
    local ok = gsa1.FollowerRespawn(F.id)
    if ok then F.calledAt = SysTime() end
    return ok and true or false
end
function Fo.CallBack(how)
    local n = 0
    for _, F in ipairs(Fo.list) do
        if is_mine(F) and Fo.CallOne(F) then n = n + 1 end
    end
    log("%d followers called back (%s)", n, tostring(how or "the page"))
    return n
end

-- they emote with you (round 0.9.9: sadc docs/research/gsa1_099_plan.md 2.4 C3, 4.1 B5, 5.6; follow099.md 5.1, 5.3, 5.4; review R99.16) ------------
-- You play a slot of the wheel: each of your followers plays the same page and slot of its own wheel, with that slot's own loop, hold and rate and its
-- kind's own catalogue. Fo.emote = { id, page, slot, pending = { [F] = true }, started = { [F] = true }, was (the record before: whom a skip must stop) }.
-- An empty slot, a face alone, "(stop)", a gate's refusal: a plain skip, no toast. A refusal of the moment ("moving", "on the way"): asked again at 5 Hz,
-- so one on its way joins when it arrives. One that took it and lost it is not asked again. Faces are not sent. Never SA1_EMOTE_IN_AIR: it would stop a
-- running follower where it is. W.playing stays the player's: followers never go through W.PlayBody. Your emote ending ends theirs.
Fo.EMOTE_RETRY = 0.2        -- s between two rounds of asking (5 Hz)
Fo.EMOTE_WAIT = 1.25        -- s your own emote may take to show: it is latched until your next pair and may wait 30 pairs to settle (its state is NONE until then)
Fo.EMOTE_MOVING = 4         -- HU/s: above this you are off running, and your emote's end stops theirs at once; below it they blend into the stand

function Fo.EmoteConst(name, default)
    local E = gsa1 and gsa1.EMOTE
    return E and tonumber(E[name]) or default
end
local emote_const = Fo.EmoteConst

-- one word once per record in the log, whoever says it (the secret's 99 would write 99 lines)
local function emote_note(rec, F, word)
    if rec.words[word] then return end
    rec.words[word] = true
    log("%s (follower %d): page %d slot %d of its wheel: %s", F.title or "?", F.uid or 0, rec.page, rec.slot, tostring(word))
end

local function emote_stop(F, how)
    if not F.removed and gsa1 and gsa1.EmoteStop then gsa1.EmoteStop(F.id, how) end
end

-- W.ON_PLAYED: your body emote started from the page's slot s. Page 0 is a catalogue row or gsa1_emote, not a slot: nothing maps (2.4 C3)
function Fo.EmoteStart(C, page, s)
    page, s = tonumber(page) or 0, tonumber(s) or 0
    if page < 1 or s < 1 or not cv.emotes:GetBool() or not C then return end
    if not (W and W.WheelOf and W.SlotEntry and W.ListOf and gsa1 and gsa1.Emote) then return end
    local pending = {}
    for _, F in ipairs(Fo.list) do
        if is_mine(F) and not F.held then pending[F] = true end
    end
    local old = Fo.emote
    if old then
        -- you went on to another slot: who does not take part any more stops now, who has an empty slot there stops at its skip
        for F in pairs(old.started) do
            if not pending[F] then emote_stop(F, emote_const("STOP_BLEND", 1)) end
        end
    end
    if next(pending) == nil then
        Fo.emote = nil
        return
    end
    Fo.emote = { id = C.id, page = page, slot = s, pending = pending, started = {}, was = old and old.started or nil, words = {}, kinds = {}, seen = false,
                 waitUntil = SysTime() + Fo.EMOTE_WAIT, nextTry = 0 }
end
if W then
    W.ON_PLAYED = W.ON_PLAYED or {}
    for i = #W.ON_PLAYED, 1, -1 do
        if W.ON_PLAYED[i] == Fo.emoteHook then table.remove(W.ON_PLAYED, i) end
    end
    Fo.emoteHook = function(C, page, s) return Fo.EmoteStart(C, page, s) end
    W.ON_PLAYED[#W.ON_PLAYED + 1] = Fo.emoteHook
end

-- the record ends: how (gsa1.EMOTE.STOP_*) for those that play, by default STOP_NOW if you are moving (your own cancel is the same clear), else STOP_BLEND
function Fo.EmoteEnd(how, why)
    local rec = Fo.emote
    if not rec then return end
    Fo.emote = nil
    if not how then
        local C = GSA1.Char
        local st = C and C.state
        local vx, vy = st and st.vx or 0, st and st.vy or 0
        how = vx * vx + vy * vy > Fo.EMOTE_MOVING * Fo.EMOTE_MOVING and emote_const("STOP_NOW", 0) or emote_const("STOP_BLEND", 1)
    end
    local n = 0
    for F in pairs(rec.started) do
        emote_stop(F, how)
        n = n + 1
    end
    if n > 0 then log("%d followers stop their emote (%s)", n, tostring(why or "your emote ended")) end
end

-- a follower goes (Fo.Remove, Fo.Recreate: a new world plays nothing)
function Fo.EmoteForget(F)
    local rec = Fo.emote
    if not rec then return end
    rec.pending[F], rec.started[F] = nil, nil
    if rec.was then rec.was[F] = nil end
    if next(rec.pending) == nil and next(rec.started) == nil then Fo.emote = nil end
end

local function emote_skip(rec, F, word)
    rec.pending[F] = nil
    if rec.was and rec.was[F] then emote_stop(F, emote_const("STOP_BLEND", 1)) end
    emote_note(rec, F, word)
end

-- what the slot means on an entry's wheel, once per record (W.DefaultWheel makes a table each time; the secret's 99 are asked at 5 Hz)
local function emote_slot(rec, name)
    local k = rec.kinds[name]
    if k then return k end
    local wheel = W.WheelOf(name)
    local slot = wheel and wheel.pages and wheel.pages[rec.page] and wheel.pages[rec.page][rec.slot]
    local e, why = W.SlotEntry(slot, W.ListOf(name))
    k = { e = e, why = why or "empty", flags = 0 }
    if e then
        if slot.loop then k.flags = bit.bor(k.flags, emote_const("LOOP", 0x100)) end
        if W.HoldApplies(slot, e) then k.flags = bit.bor(k.flags, emote_const("HOLD", 0)) end
        if W.SpeedSupported() then k.rate = W.PlayRate(slot, W.cv.speed:GetFloat()) end
    end
    rec.kinds[name] = k
    return k
end

local function emote_try(rec, F)
    if F.removed or F.held then
        rec.pending[F] = nil
        return
    end
    local k = emote_slot(rec, F.name)
    local e = k.e
    if not e then return emote_skip(rec, F, k.why) end
    for _, g in ipairs(W.PLAY_GATES or {}) do
        local gok, gwhy = pcall(g.gate, F, e)
        if gok and gwhy then return emote_skip(rec, F, gwhy) end
    end
    local ok, reason, code
    if k.rate then
        ok, reason, code = gsa1.Emote(F.id, e.key, k.flags, k.rate)
    else
        ok, reason, code = gsa1.Emote(F.id, e.key, k.flags)
    end
    if ok then
        rec.pending[F], rec.started[F] = nil, true
    elseif code == "unsupported" or code == "limit" then
        emote_note(rec, F, reason or code)          -- (of the moment: asked again)
    else
        emote_skip(rec, F, reason or code or "refused")
    end
end

-- every frame while the record exists: one module call; at 5 Hz the pending ones
function Fo.EmoteThink(now)
    local rec = Fo.emote
    if not rec then return end
    local C = GSA1.Char
    if not C or C.id ~= rec.id or not gsa1.EmoteState then return Fo.EmoteEnd(nil, "your character went") end
    local st = gsa1.EmoteState(C.id)
    if st == nil or st == emote_const("STATE_NONE", 0) then
        if rec.seen or now >= rec.waitUntil then return Fo.EmoteEnd() end
        return
    end
    rec.seen = true
    if st == emote_const("STATE_ENDING", 2) or now < rec.nextTry then return end
    rec.nextTry = now + Fo.EMOTE_RETRY
    for F in pairs(rec.pending) do
        emote_try(rec, F)
    end
    if next(rec.pending) == nil and next(rec.started) == nil then Fo.emote = nil end
end

-- the frame -----------------------------------------------------------------------------------------------------------------------
-- the draw level of F, at once (no hysteresis): the module's call, the entity, the path cl_render.lua takes
function Fo.level_changed(F, level)
    if not gsa1.FollowerDraw then return end
    if level == 2 then
        gsa1.FollowerDraw(F.id, 2, cv.far_rate:GetInt())
    else
        gsa1.FollowerDraw(F.id, level)
    end
    if F.lod ~= level and GSA1.FreeStaticMeshes then GSA1.FreeStaticMeshes(F) end
    F.lod = level
    F.interp = level == 1
    F.lodWant, F.lodSince = nil, nil
    if IsValid(F.ent) and F.ent.SetNoDraw then F.ent:SetNoDraw(level == 3) end
end

-- the levels (096 4.10), ten times a second: the nearest gsa1_follower_full_detail within the draw distance are 1, the others
-- within it 2, beyond it 3; a held one 3 at once; every other change waits Fo.LEVEL_DELAY s (0.5 s hysteresis)
Fo.order = Fo.order or {}
local function by_dist(a, b)
    if a.dist2 ~= b.dist2 then return a.dist2 < b.dist2 end
    return a.uid < b.uid
end
local eye_probe = Vector()
function Fo.UpdateLevels(now)
    if now < (Fo.nextLevels or 0) then return end
    Fo.nextLevels = now + 0.1
    local v = GSA1.view
    local ex, ey, ez
    if v and v.origin and v.frame and FrameNumber() - v.frame <= 2 then
        ex, ey, ez = v.origin.x, v.origin.y, v.origin.z
    else
        -- no fresh view (no character): the player's eye, at most every 0.25 s (update_audio's rule)
        if now >= (Fo.eyeAt or 0) then
            Fo.eyeAt = now + 0.25
            local ply = LocalPlayer()
            if IsValid(ply) then eye_probe:Set(ply:EyePos()) end
        end
        ex, ey, ez = eye_probe.x, eye_probe.y, eye_probe.z
    end
    local order = Fo.order
    local n, list = 0, Fo.list
    local maxd = cv.draw_dist:GetFloat()
    maxd = maxd * maxd
    for i = 1, #list do
        local F = list[i]
        if not F.held then
            local p = F.drawPos
            local dx, dy, dz = p.x - ex, p.y - ey, p.z - ez
            F.dist2 = dx * dx + dy * dy + dz * dz
            n = n + 1
            order[n] = F
        end
    end
    for i = #order, n + 1, -1 do order[i] = nil end
    table.sort(order, by_dist)
    local full = cv.full_detail:GetInt()
    for i = 1, n do
        local F = order[i]
        local want = F.dist2 > maxd and 3 or (i <= full and 1 or 2)
        if want == F.lod then
            F.lodWant, F.lodSince = nil, nil
        elseif F.lodWant ~= want then
            F.lodWant, F.lodSince = want, now
        elseif now - F.lodSince >= Fo.LEVEL_DELAY then
            Fo.level_changed(F, want)
        end
    end
end

-- the entity of a held follower stays at its leader; it is not drawn and stands 1,000,000 units above it (096 review R.15)
function Fo.UpdateHeld(F, s)
    local held = F.heldBack == true or F.guardUntil ~= nil or (s.z or 0) > Fo.HOLD_ABOVE
    if held then
        if not F.inHold then
            F.inHold = true
            F.boxTrack = nil                -- (a jump in its positions: it starts its box samples again)
            F.lodBefore = F.lod
        end
        F.held = true
        if F.lod ~= 3 then Fo.level_changed(F, 3) end
        local L = Fo.LeaderEntry(F)
        if L and L.drawPos and IsValid(F.ent) then F.ent:SetPos(L.drawPos) end
    elseif F.inHold then
        -- placed behind its leader again: drawn at once, as it was
        F.inHold = nil
        F.held = false
        Fo.level_changed(F, F.lodBefore or 1)
    end
    return held
end

-- what the module gave for this frame (D8: out[i] has the drawn root; no engine call that returns a Vector): the position, the
-- batches
function Fo.AfterTick(F, r)
    local s = F.state
    gsa1.GetState(F.id, s)
    local held = Fo.UpdateHeld(F, s)
    if held then return end
    if F.lod == 3 then
        -- not rendered: the last pair's position (the levels need it)
        if s.x then F.drawPos:SetUnpacked(s.x, s.y, s.z) end
        if s.yaw then F.drawYaw = s.yaw end
    elseif r.x then
        F.drawPos:SetUnpacked(r.x, r.y, r.z)
        F.drawYaw, F.alpha, F.interpolated, F.triangles = r.yaw, r.alpha, r.interpolated, r.tris
    end
    if r.rendered then F.renderGen = F.renderGen + 1 end
    if r.restructured or (F.batchGen < 0 and r.rendered) then
        F.batchGen = F.batchGen + 1
        gsa1.Batches(F.id, F.batches)
        F.matsDirty = true
    end
    if IsValid(F.ent) then F.ent:SetPos(F.drawPos) end
end

-- the guards: below the map, the respawn-loop guard (096 4.16, review R.14: a host rule behind gsa1_follower_loop_guard), the 4 Hz
-- reading of its info
function Fo.Guards(F, now)
    if F.removed then return end
    local gu = F.guardUntil
    if gu then
        if now >= gu then
            F.guardUntil = nil
            F.held = false
            Fo.Hold(F, false)
            log("%s (follower %d): back behind its leader after the loop guard's wait", F.title or "?", F.uid)
        end
        return
    end
    if now >= F.nextInfo then
        F.nextInfo = now + 0.25
        if gsa1.FollowerInfo then
            local inf = gsa1.FollowerInfo(F.id, F.finfo)
            if type(inf) == "table" and inf.respawns then
                local d = (tonumber(inf.respawns) or 0) - F.respawns
                if d > 0 then
                    F.respawns = tonumber(inf.respawns) or 0
                    -- (a call back is yours, not a loop)
                    if not (F.calledAt and now - F.calledAt < 1) then
                        local dr = F.drops
                        for _ = 1, d do dr[#dr + 1] = now end
                    end
                end
            end
        end
    end
    if F.held or not cv.loop_guard:GetBool() then return end
    local dr = F.drops
    while dr[1] and now - dr[1] > Fo.LOOP_WINDOW do table.remove(dr, 1) end
    if #dr >= Fo.LOOP_MAX then
        for i = #dr, 1, -1 do dr[i] = nil end
        if Fo.Hold(F, true) then
            F.guardUntil = now + Fo.LOOP_HOLD
            F.held = true
            log("%s (follower %d) dropped in %d times within %d s: it waits %d s and comes back behind its leader", F.title or "?",
                F.uid, Fo.LOOP_MAX, Fo.LOOP_WINDOW, Fo.LOOP_HOLD)
        end
        return
    end
    -- below the map: drops in again at once, at most once a second
    local wi = GSA1.worldInfo
    local s = F.state
    if wi and wi.min_z and s.z and s.z < wi.min_z - 1024 and now >= (F.fellAt or 0) then
        F.fellAt = now + 1
        gsa1.FollowerRespawn(F.id)
        log("%s (follower %d) fell below the map: it drops in again", F.title or "?", F.uid)
    end
end

-- Lua errors of one follower's part: logged; 3 within 10 s remove that follower; your tick goes on
local function follower_error(F, err)
    if GSA1.Log then GSA1.Log("error", "%s (follower %d): %s", F.title or "?", F.uid, tostring(err)) end
    local now = SysTime()
    local el = F.luaErrors or {}
    F.luaErrors = el
    for i = #el, 1, -1 do
        if now - el[i] > 10 then table.remove(el, i) end
    end
    el[#el + 1] = now
    if #el >= 3 then Fo.Remove(F, "fault") end
end

local function after_one(F, r, dt, now)
    Fo.AfterTick(F, r)
    run_hook("GSA1FollowerPostTick", F, F.state, dt)
    Fo.Guards(F, now)
end

local cv_timescale = GetConVar("host_timescale")
local yaw_ang
-- the frame's dt: tick_character's rule (cl_character.lua: the same clock, 0 while paused, host_timescale)
function Fo.FrameDt(now)
    local last = Fo.last or now
    Fo.last = now
    local dt = math.Clamp(now - last, 0, 0.25)
    if (GSA1.GamePaused and GSA1.GamePaused()) or (GSA1.Hitch and GSA1.Hitch.tickPaused) then dt = 0 end
    return dt * (cv_timescale and cv_timescale:GetFloat() or 1)
end

-- the view's yaw without a new Angle (a follower's stick is the AI's; the world still keeps a camera yaw)
function Fo.ViewYaw(now)
    local v = GSA1.view
    if v and v.angles and v.frame and FrameNumber() - v.frame <= 2 then return v.angles.y end
    if now >= (Fo.yawAt or 0) or yaw_ang == nil then
        Fo.yawAt = now + 0.25
        local ply = LocalPlayer()
        yaw_ang = IsValid(ply) and ply:EyeAngles().y or 0
    end
    return yaw_ang
end

-- the map's collision was loaded again: characters keep the world they were created with, so these are made again too
local function world_watch()
    local wi = GSA1.worldInfo
    if wi == Fo.worldSeen then return false end
    Fo.worldSeen = wi
    for i = #Fo.list, 1, -1 do Fo.Recreate(Fo.list[i], "the map's collision was loaded") end
    return true
end

-- once per frame, right after your character's tick (cl_character.lua's Think hook "gsa1_tick")
function GSA1.FollowersThink(now)
    local list = Fo.list
    if not list[1] then
        Fo.last = nil
        return
    end
    if not GSA1.mod or not Fo.Have() or not gsa1.FollowersTick then return end
    local t0 = SysTime()
    now = now or t0
    world_watch()
    local C = GSA1.Char
    -- your character's change failed (no new one came): they do not wait for ever
    if Fo.heldAt and not C and now - Fo.heldAt > 1 then
        Fo.Relink(nil)
        Fo.ReleaseHeld()
    end
    local dt = Fo.FrameDt(now)
    Fo.RefreshTargets(now)
    Fo.EmoteThink(now)
    local fn = FrameNumber()
    local hostFlags = GSA1.HostWaterFlags
    for i = 1, #list do
        local F = list[i]
        if F.hostFed then Fo.Feed(F, fn) end
        -- the water at its last pair's position: once per pair (the module keeps the flags for its ticks)
        local st = F.state.step
        if st ~= F.flagStep then
            F.flagStep = st
            if gsa1.FollowerHostFlags then gsa1.FollowerHostFlags(F.id, hostFlags(F)) end
        end
    end
    -- with a character its tick ran GSA1.MoversThink; without one the followers' foci keep the moving objects going
    if not C and GSA1.MoversThink then GSA1.MoversThink(nil, now) end
    local co, ct
    if gsa1.TICK_HOST_CAMERA and C and GSA1.FollowerTickCamera then co, ct = GSA1.FollowerTickCamera(C) end
    local tt = SysTime()
    -- (the last argument: level 1's alpha rule, your character's gsa1_interpolate)
    local res = gsa1.FollowersTick(dt, Fo.ViewYaw(now), co, ct, Fo.tickOut, GSA1.cv.interp:GetBool())
    local tick_ms = (SysTime() - tt) * 1000
    local n = res and res.count or 0
    for i = 1, n do
        local r = res[i]
        local F = Fo.byId[r.id]
        if F then
            if not r.ok then
                if r.code == "fault" then
                    Fo.Fault(F, r.msg, r.code)
                else
                    log("%s (follower %d) stopped: %s", F.title or "?", F.uid, tostring(r.msg))
                    Fo.Remove(F, "fault")
                end
            else
                local ok, err = pcall(after_one, F, r, dt, now)
                if not ok then follower_error(F, err) end
            end
        end
    end
    Fo.UpdateLevels(now)
    if not C then GSA1.PollAllEvents(now) end
    -- the log's own line (cl_log.lua: every 10 s)
    if GSA1.LogFollowers then
        local draw, lv1, lv2, lv3, egg = 0, 0, 0, 0, 0
        for i = 1, #list do
            local F = list[i]
            draw = draw + (F.drawMs or 0)
            local l = F.lod
            if l == 1 then lv1 = lv1 + 1 elseif l == 2 then lv2 = lv2 + 1 else lv3 = lv3 + 1 end
            if F.egg then egg = egg + 1 end
        end
        GSA1.LogFollowers(now, #list, egg, res and res.ms or tick_ms, res and res.ms_join or 0, res and res.workers or 0, draw, lv1,
            lv2, lv3)
    end
    if GSA1.HitchAdd then GSA1.HitchAdd("Followers", SysTime() - t0) end
end

-- at most maxN followers more than apart HU from C and from every focus already chosen (cl_collision.lua), in a reused list; never
-- a held one (it stands 1,000,000 units above its leader)
Fo.fociOut = Fo.fociOut or {}
function Fo.FarFoci(C, apart, maxN)
    local out = Fo.fociOut
    local n = 0
    local a2 = apart * apart
    local list = Fo.list
    local cp = C and C.drawPos
    for i = 1, #list do
        if n >= maxN then break end
        local F = list[i]
        if not F.held then
            local p = F.drawPos
            local far = true
            if cp then
                local dx, dy, dz = p.x - cp.x, p.y - cp.y, p.z - cp.z
                far = dx * dx + dy * dy + dz * dz > a2
            end
            if far then
                for j = 1, n do
                    local q = out[j]
                    local dx, dy, dz = p.x - q.x, p.y - q.y, p.z - q.z
                    if dx * dx + dy * dy + dz * dz <= a2 then
                        far = false
                        break
                    end
                end
            end
            if far then
                n = n + 1
                out[n] = p
            end
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end

-- the map goes (the module destroys every world with its shutdown)
hook.Add("ShutDown", "gsa1_follower", function()
    Fo.list, Fo.byId, Fo.byToken = {}, {}, {}
    Fo.emote = nil
end)

-- settings ------------------------------------------------------------------------------------------------------------------------
cvars.AddChangeCallback("gsa1_follower", function(_, _, new)
    if tonumber(new) == 0 then Fo.RemoveAll("removed") end
end, "gsa1_follower")
cvars.AddChangeCallback("gsa1_follower_max", function(_, _, new)
    local cap = math.min(math.max(tonumber(new) or 0, 0), Fo.NORMAL_MAX)
    while Fo.Count(false) > cap do
        local F = Fo.Newest(true)
        if not F then break end
        Fo.Remove(F, "cap")
    end
end, "gsa1_follower")
-- 0.9.9: all three act at once on the followers there are; one settings line a second after the last change, not one per tick of a drag
local function log_setting(what, c)
    timer.Create("gsa1_follower_log_" .. what, 1, 1, function()
        if GSA1.Log then GSA1.Log("settings", "followers: %s %s", what, c:GetString()) end
    end)
end
cvars.AddChangeCallback("gsa1_follower_speed", function()
    for _, F in ipairs(Fo.list) do Fo.ApplySpeed(F) end
    log_setting("catch-up speed", cv.speed)
end, "gsa1_follower")
cvars.AddChangeCallback("gsa1_follower_fix_stand", function()
    for _, F in ipairs(Fo.list) do Fo.ApplyStand(F) end
    log_setting("stand and idle", cv.fix_stand)
end, "gsa1_follower")
cvars.AddChangeCallback("gsa1_follower_spacing", function()
    Fo.ApplySpots()
    log_setting("room between them", cv.spacing)
end, "gsa1_follower")
cvars.AddChangeCallback("gsa1_follower_emotes", function(_, _, new)
    if tonumber(new) == 0 then Fo.EmoteEnd(nil, "the option went off") end
    log_setting("emote with you", cv.emotes)
end, "gsa1_follower")
cvars.AddChangeCallback("gsa1_follower_far_rate", function()
    for _, F in ipairs(Fo.list) do
        if F.lod == 2 then gsa1.FollowerDraw(F.id, 2, cv.far_rate:GetInt()) end
    end
end, "gsa1_follower")
-- "Followers' own sounds" off silences those there are too (the module takes it at creation)
Fo.pending = Fo.pending or {}
local function recreate_later(fn)
    Fo.pendingAt = SysTime() + 0.25
    Fo.pendingFn = fn
end
cvars.AddChangeCallback("gsa1_follower_sounds", function()
    recreate_later(function(F) return not F.opts.silent end)
end, "gsa1_follower")
-- an upgrade of a follower's kind ticked: those of that kind are made again (a moment later: one round for "all on")
if GSA1.UPGRADES then
    for _, u in ipairs(GSA1.UPGRADES) do
        cvars.AddChangeCallback("gsa1_upgrade_" .. u.name, function()
            if not cv.upgrades:GetBool() then return end
            Fo.pending[u.kind] = true
            recreate_later(function(F) return Fo.pending[GSA1.UpgradeKind and GSA1.UpgradeKind(F.kind) or F.kind] == true end)
        end, "gsa1_follower")
    end
end
cvars.AddChangeCallback("gsa1_follower_upgrades", function()
    recreate_later(function() return true end)
end, "gsa1_follower")
hook.Add("Think", "gsa1_follower", function()
    local at = Fo.pendingAt
    if not at or SysTime() < at then return end
    local fn = Fo.pendingFn
    Fo.pendingAt, Fo.pendingFn = nil, nil
    for i = #Fo.list, 1, -1 do
        local F = Fo.list[i]
        if fn(F) then Fo.Recreate(F, "a setting changed") end
    end
    for k in pairs(Fo.pending) do Fo.pending[k] = nil end
end)
-- the settings that also act on followers: Tails' tail blend, the item icon guard, the materials' settings
cvars.AddChangeCallback("gsa1_tails_tail_blend", function()
    if not (GSA1.CharOpt and GSA1.CharOpt.ApplyTailBlend) then return end
    for _, F in ipairs(Fo.list) do GSA1.CharOpt.ApplyTailBlend(F) end
end, "gsa1_follower")
cvars.AddChangeCallback("gsa1_set_icon_guard", function()
    if not (GSA1.Objects and GSA1.Objects.ApplyIconGuard) then return end
    for _, F in ipairs(Fo.list) do GSA1.Objects.ApplyIconGuard(F) end
end, "gsa1_follower")
for _, name in ipairs({ "gsa1_lighting", "gsa1_vertexcolor", "gsa1_flip_winding", "gsa1_nocull", "gsa1_line_width" }) do
    cvars.AddChangeCallback(name, function()
        for _, F in ipairs(Fo.list) do
            F.matsDirty = true
            GSA1.FreeStaticMeshes(F)
        end
    end, "gsa1_follower")
end

-- the keys: the open wheel's action (W.OPEN_ACTIONS: no patch of cl_wheel.lua, D12), refused keys and buttons as the board's --------
local function key_down(code)
    code = tonumber(code) or 0
    return code > 0 and input ~= nil and input.IsButtonDown ~= nil and input.IsButtonDown(code) == true
end
local function pad_raw()
    local p = GSA1.pad
    if p and p.connected then return tonumber(p.raw) or 0 end
    return 0
end
function Fo.CallDown()
    if key_down(cv.call_key:GetInt()) then return true end
    local b = cv.call_pad:GetInt()
    return b > 0 and bit.band(pad_raw(), b) ~= 0
end
function Fo.CallHint()
    if not Fo.list[1] then return nil end
    local k, p = cv.call_key:GetInt(), cv.call_pad:GetInt()
    local parts = {}
    if k > 0 then parts[#parts + 1] = W and W.KeyName and W.KeyName(k) or tostring(k) end
    if p > 0 and W and W.PadTitle then
        local t = W.PadTitle(p)
        parts[#parts + 1] = string.match(t, "%((%u+)%)") or t
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " / ") .. ": call your followers"
end
function Fo.CallAct()
    if not Fo.list[1] then return false end
    if W and W.Close then W.Close(nil, true) end
    Fo.wheelClosedAt = SysTime()
    Fo.CallBack("the wheel")
    return true
end
if W then
    W.OPEN_ACTIONS = W.OPEN_ACTIONS or {}
    for i = #W.OPEN_ACTIONS, 1, -1 do
        if W.OPEN_ACTIONS[i].name == "followers" then table.remove(W.OPEN_ACTIONS, i) end
    end
    W.OPEN_ACTIONS[#W.OPEN_ACTIONS + 1] = { name = "followers", down = function(C) return Fo.CallDown() end,
                                             act = function(C) return Fo.CallAct() end,
                                             hint = function(C) return Fo.CallHint() end }
end
-- a Garry's Mod bind of that key (F is the flashlight) does nothing while the wheel is open or right after it closed
hook.Add("PlayerBindPress", "gsa1_follower", function(ply, bind, pressed, code)
    if not W or not Fo.list[1] then return end
    local recent = Fo.wheelClosedAt and SysTime() - Fo.wheelClosedAt < 0.1
    if not (W.open or recent) then return end
    local k = cv.call_key:GetInt()
    if k <= 0 then return end
    if code ~= nil then
        if code == k then return true end
        return
    end
    local name = input and input.LookupKeyBinding and input.LookupKeyBinding(k)
    if name and bind and string.lower(name) == string.lower(bind) then return true end
end)
function Fo.KeyRefused(code)
    code = tonumber(code) or 0
    if code <= 0 then return nil end
    local B = GSA1.Board
    if not B then return nil end
    if B.cv and B.cv.key and B.cv.key:GetInt() == code then return "the board key" end
    return B.KeyRefused and B.KeyRefused(code, "gsa1_follower_call_key") or nil
end
function Fo.PadRefused(bits)
    bits = tonumber(bits) or 0
    if bits <= 0 then return nil end
    local B = GSA1.Board
    if not B then return nil end
    if B.cv and B.cv.pad and B.cv.pad:GetInt() == bits then return "the board button" end
    return B.PadRefused and B.PadRefused(bits, "gsa1_follower_call_pad") or nil
end
-- (the value put back comes through here too, a frame later in the game: the note stays)
cvars.AddChangeCallback("gsa1_follower_call_key", function(name, old, new)
    if Fo.keyBack ~= nil and tonumber(new) == Fo.keyBack then
        Fo.keyBack = nil
        return
    end
    local why = Fo.KeyRefused(new)
    if why then
        Fo.keyBack = tonumber(old)
        local kn = W and W.KeyName or tostring
        Fo.keyNote = string.format("%s is %s: the key that calls your followers stays %s", kn(tonumber(new)), why,
            kn(tonumber(old)))
        log("%s", Fo.keyNote)
        if GSA1.Chat then GSA1.Chat("%s", Fo.keyNote) end
        RunConsoleCommand("gsa1_follower_call_key", tostring(old))
    elseif tonumber(new) ~= tonumber(old) then
        Fo.keyNote = nil
    end
end, "gsa1_follower")
cvars.AddChangeCallback("gsa1_follower_call_pad", function(name, old, new)
    if Fo.padBack ~= nil and tonumber(new) == Fo.padBack then
        Fo.padBack = nil
        return
    end
    local why = Fo.PadRefused(new)
    if why then
        Fo.padBack = tonumber(old)
        local pt = W and W.PadTitle or tostring
        Fo.keyNote = string.format("%s is %s: the button that calls your followers stays %s", pt(tonumber(new)), why,
            pt(tonumber(old)))
        log("%s", Fo.keyNote)
        if GSA1.Chat then GSA1.Chat("%s", Fo.keyNote) end
        RunConsoleCommand("gsa1_follower_call_pad", tostring(old))
    elseif tonumber(new) ~= tonumber(old) then
        Fo.keyNote = nil
    end
end, "gsa1_follower")

-- the spawn icons (feat/sv_follower.lua) ---------------------------------------------------------------------------------------------
local function send_made(token, made)
    if util.NetworkStringToID(Fo.NET.MADE) == 0 then return end
    net.Start(Fo.NET.MADE)
    net.WriteUInt(token, 16)
    net.WriteBool(made and true or false)
    net.SendToServer()
end
net.Receive(Fo.NET.REQ, function()
    local token, kind = net.ReadUInt(16), net.ReadUInt(4)
    local ok, res = GSA1.SpawnFollower(kind, { why = "spawntab" })
    if ok then
        res.token = token
        Fo.byToken[token] = res
    elseif GSA1.Chat then
        GSA1.Chat("no follower: %s", tostring(res))
    end
    send_made(token, ok)
end)
net.Receive(Fo.NET.UNDO, function()
    local token = net.ReadUInt(16)
    local F = Fo.byToken[token]
    if F and not F.removed then Fo.Remove(F, "undo") end
end)

-- the G-SA1 tab's Followers group: the kinds that can follow (a FUNCTION, any load order: cl_spawntab.lua T.LATER)
GSA1.SpawnTab = GSA1.SpawnTab or {}
do
    local T = GSA1.SpawnTab
    T.LATER = T.LATER or {}
    for i = #T.LATER, 1, -1 do
        if T.LATER[i].name == "Followers" then table.remove(T.LATER, i) end
    end
    T.LATER[#T.LATER + 1] = { name = "Followers", icon = "icon16/group.png", classes = function() return Fo.SpawnerClasses() end }
end
function Fo.SpawnerClasses()
    local out = {}
    local allowed = Fo.KindsNow()
    for _, k in ipairs(Fo.KIND_ORDER) do
        if allowed[k] == true then out[#out + 1] = Fo.SpawnerClass(k) end
    end
    return out
end

-- the console's extras (each has its control on the page) ----------------------------------------------------------------------------
local function say(fmt, ...)
    if GSA1.Msg then GSA1.Msg(fmt, ...) end
end
concommand.Add("gsa1_follower_spawn", function(ply, cmd, args)
    local ok, res = GSA1.SpawnFollower(args[1] and args[1] ~= "" and args[1] or cv.kind:GetInt(),
        { target = args[2], why = "console" })
    if not ok then GSA1.Chat("no follower: %s", tostring(res)) end
end, nil, "G-SA1: gsa1_follower_spawn [character] [me | player | follower | aim | stay]: a follower (Q menu > Options > G-SA1 > "
    .. "Followers)")
concommand.Add("gsa1_follower_remove", function(ply, cmd, args)
    if args[1] == "all" then
        Fo.RemoveAll("removed")
        return
    end
    local n = tonumber(args[1])
    local F = n and Fo.list[n] or Fo.Newest(false)
    if F then Fo.Remove(F, "removed") else say("no such follower") end
end, nil, "G-SA1: gsa1_follower_remove [all | n]: removes the newest follower, all of them, or the n-th")
-- (gsa1_follower_settarget, not gsa1_follower_target as 096 5.9 says: that name is the ConVar of 5.9's row, and one name cannot
-- be both: the class of gsa1_098_plan.md 2.4 C7)
concommand.Add("gsa1_follower_settarget", function(ply, cmd, args)
    local who = args[1]
    if not who or who == "" then
        say("gsa1_follower_settarget <me | player | follower | aim | stay> [n]")
        return
    end
    local n = tonumber(args[2])
    for i, F in ipairs(Fo.list) do
        if not n or n == i then
            local ok, why = Fo.SetTarget(F, who)
            if not ok then GSA1.Chat("%s", tostring(why)) end
        end
    end
end, nil, "G-SA1: gsa1_follower_settarget <me | player | follower | aim | stay> [n]: whom your followers (or the n-th) follow")
concommand.Add("gsa1_follower_call", function() Fo.CallBack("the command") end, nil,
    "G-SA1: your followers come back to you (the game's own respawn)")

-- the page (Q menu > Options > G-SA1 > Followers) -------------------------------------------------------------------------------------
local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[2], tostring(c[1])) end
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand(cvname, tostring(data))
    end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local c = GetConVar(cvname)
        local v = c and c:GetString() or ""
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        local n = tonumber(v)
        for _, ch in ipairs(choices) do
            if n ~= nil and tonumber(ch[1]) == n then
                self:SetText(ch[2])
                return
            end
        end
        self:SetText(v)
    end
    combo.gsa1ConVar = cvname
    return combo
end

local function live_label(panel, lines_fn)
    local lbl = panel:Help("...")
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + 0.5
        local text = table.concat(lines_fn(), "\n")
        if text ~= self.gsa1Text then
            self.gsa1Text = text
            self:SetText(text)
            if self.InvalidateLayout then self:InvalidateLayout(true) end
        end
    end
    return lbl
end

local function admin_part()
    local ply = LocalPlayer()
    if game.SinglePlayer() then return true end
    if IsValid(ply) and ply.IsListenServerHost and ply:IsListenServerHost() then return true end
    return IsValid(ply) and ply.IsAdmin ~= nil and ply:IsAdmin() == true
end

Fo.TARGET_CHOICES = { { 0, "Me" }, { 1, "The nearest player" }, { 2, "My last follower" }, { 3, "What I aim at" },
                      { 4, "Stay here" } }

-- the kinds for the combo: those that cannot follow say why ("greyed": a plain reason; picking one does nothing but say it)
function Fo.KindChoices()
    local allowed = Fo.KindsNow()
    local out = {}
    for _, k in ipairs(Fo.KIND_ORDER) do
        local a = allowed[k]
        local title = Fo.KindTitle(k)
        if a == true then
            out[#out + 1] = { k, title }
        else
            out[#out + 1] = { k, title .. " (can't follow: " .. tostring(a or "unknown") .. ")" }
        end
    end
    return out
end

-- one row's words: who, whom it follows, what it does, how far, how often it dropped in
local MODE_WORDS = { [0] = "being placed", [2] = "dropping in", [4] = "following", [5] = "taken over", [6] = "waiting" }
local SMODE_WORDS = { [0] = "waiting", [1] = "on foot", [2] = "jumping", [3] = "flying or gliding" }
function Fo.RowText(F, i)
    local info = F.finfo or {}
    local mode = tonumber(info.mode)
    local what = MODE_WORDS[mode or -1] or "starting"
    if mode == 4 then what = SMODE_WORDS[tonumber(info.smode) or -1] or what end
    if F.board and F.board.on then what = "on a board" end
    if F.board and F.board.fwalk then what = "walking to a board" end
    local r = tonumber(info.respawns) or F.respawns or 0
    return string.format("%d  %s  follows %s; %s, %.0f units away%s%s", i, F.title or "?", Fo.TargetText(F), what,
        tonumber(info.distance) or 0, r > 0 and string.format(", dropped in %d times", r) or "",
        F.egg and " (the secret's)" or "")
end

-- the list, refreshed at 2 Hz from gsa1.FollowerInfo's table (read by the guards at 4 Hz); rows made again when the followers change
function Fo.StatusLines()
    local out = {}
    local why = Fo.WhyNot(cv.kind:GetInt())
    if why then
        out[#out + 1] = "Spawn a follower: " .. why
    else
        out[#out + 1] = string.format("Your followers: %d of %d%s", Fo.Count(false), Fo.Cap(),
            Fo.Count(true) > 0 and string.format(" (and %d of the secret's)", Fo.Count(true)) or "")
    end
    if Fo.keyNote then out[#out + 1] = Fo.keyNote end
    return out
end
function Fo.ThreadsLine()
    if not (Fo.Have() and gsa1.FollowersStats) then return "CPU threads: -" end
    Fo.statsOut = Fo.statsOut or {}
    local s = gsa1.FollowersStats(Fo.statsOut) or {}
    local par = gsa1.FOLLOWER and gsa1.FOLLOWER.LIB_PARALLEL
    return string.format("%d workers%s; tick %.2f ms, render %.2f ms, the wait %.2f ms per frame", tonumber(s.workers) or 0,
        par ~= nil and ("; game code in parallel: " .. (par and "yes" or "no")) or "", tonumber(s.ms_tick) or 0,
        tonumber(s.ms_render) or 0, tonumber(s.ms_join) or 0)
end

local function build_row(host, F, i)
    local row = vgui.Create("DPanel", host)
    row.gsa1Uid = F.uid
    if row.SetPaintBackground then row:SetPaintBackground(false) end
    if row.Dock then row:Dock(TOP) end
    if row.SetTall then row:SetTall(44) end
    local lbl = vgui.Create("DLabel", row)
    if lbl.SetText then lbl:SetText(Fo.RowText(F, i)) end
    if lbl.Dock then lbl:Dock(TOP) end
    if lbl.SetDark then lbl:SetDark(true) end
    row.gsa1Label = lbl
    local combo = vgui.Create("DComboBox", row)
    for _, c in ipairs(Fo.TARGET_CHOICES) do combo:AddChoice(c[2], c[1]) end
    if combo.SetValue then combo:SetValue("Follows ...") end
    combo.OnSelect = function(_, _, _, data)
        local ok, why = Fo.SetTarget(F, data)
        if not ok then GSA1.Chat("%s", tostring(why)) end
    end
    if combo.Dock then combo:Dock(LEFT) end
    if combo.SetWide then combo:SetWide(150) end
    row.gsa1Target = combo
    local call = vgui.Create("DButton", row)
    if call.SetText then call:SetText("Call") end
    call.DoClick = function() Fo.CallOne(F) end
    if call.Dock then call:Dock(LEFT) end
    row.gsa1Call = call
    local rm = vgui.Create("DButton", row)
    if rm.SetText then rm:SetText("Remove") end
    rm.DoClick = function() Fo.Remove(F, "removed") end
    if rm.Dock then rm:Dock(LEFT) end
    row.gsa1Remove = rm
    return row
end

-- the page's list panel: Think refreshes it at 2 Hz (no per-frame panel work)
function Fo.ListThink(host)
    if RealTime() < (host.gsa1Next or 0) then return end
    host.gsa1Next = RealTime() + 0.5
    local sig = {}
    for i, F in ipairs(Fo.list) do sig[i] = tostring(F.id) end
    sig = table.concat(sig, ",")
    host.gsa1Rows = host.gsa1Rows or {}
    if sig ~= host.gsa1Sig then
        host.gsa1Sig = sig
        for _, r in ipairs(host.gsa1Rows) do
            if r.Remove then r:Remove() end
        end
        host.gsa1Rows = {}
        -- (the page is for your followers; the secret's 99 would make it a mile long: the first 16)
        for i, F in ipairs(Fo.list) do
            if i > 16 then break end
            host.gsa1Rows[i] = build_row(host, F, i)
        end
        if host.SetTall then host:SetTall(#host.gsa1Rows * 44) end
    else
        for i, r in ipairs(host.gsa1Rows) do
            local F = Fo.list[i]
            if F and r.gsa1Label and r.gsa1Label.SetText then r.gsa1Label:SetText(Fo.RowText(F, i)) end
        end
    end
end

function Fo.BuildPage(panel)
    panel:Help("Followers run the game's own \"Tails follows Sonic\" code, each in a game of its own: they run after you, jump, fly "
        .. "(Tails) or glide (Knuckles), and when they fall too far behind or stay off the screen they drop in from above the "
        .. "camera.")
    panel:CheckBox("Followers", "gsa1_follower")
    choice_combo(panel, "Character to spawn", "gsa1_follower_kind", Fo.KindChoices())
    panel:ControlHelp(Fo.PLAYABLE_NOTE)
    live_label(panel, Fo.StatusLines)
    panel:Button("Spawn a follower", "gsa1_follower_spawn")
    panel:Button("Remove the last", "gsa1_follower_remove")
    panel:Button("Remove all", "gsa1_follower_remove", "all")
    panel:Button("Call them back to me", "gsa1_follower_call")
    choice_combo(panel, "New followers follow", "gsa1_follower_target", Fo.TARGET_CHOICES)
    panel:NumSlider("Most followers at once (each is a whole game, about 21 MB)", "gsa1_follower_max", 1, Fo.NORMAL_MAX, 0)
    panel:NumSlider("Speed when catching up (1 = the game's own, 2 = up to twice its speed)", "gsa1_follower_speed", 1, Fo.SPEED_MAX, 2)
    panel:ControlHelp("Near you they run at the game's own speed. Behind you they may run up to this many times faster until they have caught up. To stay with Sonic at "
        .. "full speed: Sonic 1.2, Knuckles 1.3, Tails 1.5, E-102 2.5, Big 3.5, Amy 4. At 1 they fall behind and drop in from above, as in the game.")
    panel:NumSlider("Room between followers (0 = the game's own: they can stand inside each other)", "gsa1_follower_spacing", 0, Fo.SPACING_MAX, 0)
    panel:ControlHelp("With two or more, each has its own spot around the one it follows; one follower alone stands where the game puts it. While running they can still "
        .. "pass through each other for a moment: they do not collide with each other.")
    panel:CheckBox("Followers play the same slot of their own wheel when you play one from the emote wheel", "gsa1_follower_emotes")
    panel:ControlHelp("An empty slot on a follower's wheel does nothing. A follower on its way joins when it arrives; your emote ending ends theirs. Faces do not go with it.")
    if not (gsa1 and gsa1.FollowerSpeed) then
        panel:ControlHelp("This G-SA1 module has no catch-up speed and no spots: they need module 0.9.9.")
    end
    panel:CheckBox("Followers get your ticked upgrades of their character", "gsa1_follower_upgrades")
    choice_combo(panel, "Rings and item boxes", "gsa1_follower_objects", { { 0, "They pass through them" },
        { 1, "They touch them in their own game (nothing changes for you)" } })
    panel:ControlHelp("For new followers. In their own game a box a follower breaks gives it the item and plays no jingle.")
    panel:CheckBox("Followers' own sounds (the game's: a following Tails' own sound effects are silent)", "gsa1_follower_sounds")
    panel:CheckBox("Followers come along when you switch character, respawn or teleport", "gsa1_follower_come_along")
    panel:CheckBox("A follower that keeps dropping in (4 times within 10 s) waits 3 s and comes back behind you; one that falls below "
        .. "the map drops in again at once", "gsa1_follower_loop_guard")
    -- the list
    panel:Help("Your followers")
    local host = vgui.Create("DPanel", panel)
    if host.SetPaintBackground then host:SetPaintBackground(false) end
    if host.SetTall then host:SetTall(0) end
    local baseThink = host.Think
    host.Think = function(self)
        if baseThink then baseThink(self) end
        Fo.ListThink(self)
    end
    panel:AddItem(host)
    Fo.pageList = host
    -- the board
    panel:Help("Board")
    panel:CheckBox("Sonic and Tails followers get on a board when the one they follow does (and off again)", "gsa1_follower_board")
    choice_combo(panel, "In Board On / Off boxes", "gsa1_follower_board_boxes", { { 0, "Not at all" },
        { 1, "Walk to the box's board like you" }, { 2, "Get on at once with a board of their own" } })
    panel:ControlHelp("Their boards follow the game's own pick in their own game. The board a follower leaves counts towards your "
        .. "left boards (Board page). The box's own board stays there for you.")
    -- the keys
    panel:Help("Call your followers back (in the open emote wheel). As a character with no wheel, such as Dr. Eggman or Tikal: use the button Call them back to me, or gsa1_follower_call")
    local b = vgui.Create("DBinder", panel)
    if b.SetConVar then b:SetConVar("gsa1_follower_call_key") end
    if b.SetTall then b:SetTall(28) end
    panel:AddItem(b)
    panel:Button("No key", "gsa1_follower_call_key", "0")
    choice_combo(panel, "Controller button in the open wheel", "gsa1_follower_call_pad", W and W.PAD_BUTTONS or
        { { 0, "None" }, { 0x0040, "Left stick click (LS)" }, { 0x0080, "Right stick click (RS)" } })
    panel:ControlHelp("Open the wheel and press the key or the button: the wheel closes and they come back, dropping in from above. "
        .. "Keys and buttons the character, the wheel or the board use are refused.")
    -- fixes
    panel:Help("Fixes (not in the game)")
    panel:CheckBox("Followers that stop go to their stand and idle", "gsa1_follower_fix_stand")
    panel:ControlHelp("Works at once. Off: the game's own: a stopped follower stays in a still pose, as the game's Tails does. E-102's hover stays in a still pose either way: the game has no way out of it but a jump, for you too.")
    panel:Help("For new followers:")
    panel:CheckBox("Followers' own animations run where the game's camera cannot see them", "gsa1_follower_fix_view")
    panel:ControlHelp("Off: a follower's emote also pauses while the game's camera cannot see it.")
    panel:CheckBox("After dropping in, followers other than Tails forget where they were (stops Knuckles bouncing back)",
        "gsa1_follower_fix_respawn")
    -- drawing
    panel:Help("Drawing")
    panel:NumSlider("Followers drawn in full detail (the nearest)", "gsa1_follower_full_detail", 0, 99, 0)
    panel:NumSlider("Far followers: pictures per second", "gsa1_follower_far_rate", 5, 30, 0)
    panel:NumSlider("Followers drawn up to (units)", "gsa1_follower_draw_dist", 500, 12000, 0)
    panel:CheckBox("Followers in other addons' views (reflections, cube maps)", "gsa1_follower_other_views")
    panel:ControlHelp("Every follower runs every game step whatever is drawn: only the drawing is cheaper.")
    panel:NumSlider("CPU threads for followers (0 = automatic)", "gsa1_follower_threads", 0, 16, 0)
    live_label(panel, function() return { Fo.ThreadsLine() } end)
    -- the server part
    if admin_part() then
        panel:Help("Server (admins and the listen server's host)")
        panel:CheckBox("Follower icons in the spawn menu work on this server", "gsa1_sv_follower_icons")
    end
    panel:Help("Known limits: other players do not see your followers yet (multiplayer characters are not drawn yet); followers do "
        .. "not attack and your attacks do not hit them; saves and the duplicator do not keep them; a map change removes them; "
        .. "Amy's bird stays with Amy only when you play her.")
end

GSA1.AddMenuPage(290, "followers", "Followers", Fo.BuildPage, Fo.NEEDS)
