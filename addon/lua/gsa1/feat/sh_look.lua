-- G-SA1 feature "look", the pure part (round 0.9.8: sadc docs/research/gsa1_098_plan.md 5.9, 6.8; gsa1_096_plan.md 4.20,
-- 5.5, 5.6, 6.6 with its review R.12 / R.13; look096.md 7.2): which thing a character's head turns to. No Garry's Mod call
-- and nothing of the module here: feat/cl_look.lua fills the pool and sends the look; the game's own head code does the turn
-- (libsa1's sa1_character_look, src/module/bind_look.cpp). What a character looks at in Garry's Mod is the host's choice, not
-- the game's (the game's characters look at people who talk to them, upgrade items and freed animals): every rule below sits
-- behind the options of the Head look page.
--   THE RULES (look096.md 7.2.2, measured in 5.10):
--     * in range: people, characters and hostile NPCs gsa1_look_range, items and what was defeated 40 HU more; a follower's
--       leader L.LEADER_RANGE (a follower that stopped near its leader stands further off than people are looked at);
--     * within +-100 degrees of the looker's facing (the heading alone: the game's head has its own limits);
--     * the category switched on;
--     * priority defeated > people / characters / hostile NPCs > items > (followers only) the leader; of the best priority
--       the nearest;
--     * hysteresis: a target is held at least 1 s while it stays eligible; a new one must be the best for 0.5 s;
--     * a looker never picks itself; a follower never picks another follower of this client (a group of followers would
--       only look at each other, never at you: gsa1_098_plan.md 7's "a follower looks at you when you stop"), and its leader
--       only as the last choice.
--   A CANDIDATE (one shared pool, reused tables): { key, cat, x, y, z, px, py, pz, t, follower, ent, name, word }: key > 0 an
--   entity index, key < 0 the character -key; x, y, z its newest point, px, py, pz the sample before, t the time of the newest.
--   A LOOKER: { key, follower, x, y, z (its eyes), fx, fy (its facing, a unit vector), leaderKey, leaderEntry, cur, curSince,
--   cand, candSince, blocked = nil | { [key] = until } }.
GSA1 = GSA1 or {}
local L = GSA1.Look or {}
GSA1.Look = L

L.NEEDS = { feature = "look", version = 1, module = "0.9.8" }
L.PAGE_ORDER = 287
L.CAT_DEFEATED, L.CAT_PEOPLE, L.CAT_HOSTILE, L.CAT_ITEM = 1, 2, 3, 4
L.ROUND = 0.1               -- seconds between two choices (the interaction scan's rate)
L.HOLD, L.SWITCH = 1.0, 0.5 -- at least 1 s on a target; a new one must be the best for 0.5 s
L.CONE_DEGREES = 100
L.ITEM_EXTRA = 40           -- items and the defeated: the range + 40 HU (the game's upgrade items 160 against 120 for people)
L.LEADER_RANGE = 2400       -- a follower's leader (the pool's largest radius)
L.SCAN_MAX = 2400           -- the pool's radius at most (cl_interact.lua's SCAN_RANGE)
L.POOL_MAX = 64             -- candidates a looker chooses from
L.TRACE_EVERY = 0.25        -- line of sight per looker: at most every 0.25 s
L.TRACES_PER_SECOND = 60    -- and in all
L.TRACES_PER_FRAME = 8      -- after a long frame
L.BLOCKED_FOR = 1           -- a blocked target is dropped for 1 s
L.DEFEATED_FOR = 5          -- the freed animal's 300 steps
L.KILLED_MARK = 3           -- cl_interact.lua: I.killed[idx] = the kill's time + 3 s

local CAT_DEFEATED, CAT_PEOPLE, CAT_HOSTILE, CAT_ITEM = L.CAT_DEFEATED, L.CAT_PEOPLE, L.CAT_HOSTILE, L.CAT_ITEM
local HOLD, SWITCH = L.HOLD, L.SWITCH
local COS2 = math.cos(math.rad(L.CONE_DEGREES)) ^ 2     -- (the cone's cosine is negative: only the far side needs it)

-- the options as the chooser reads them (o: reused)
function L.SetOptions(o, range, people, hostile, items, defeated)
    range = tonumber(range) or 120
    o.range = range
    o.r2 = range * range
    o.r2far = (range + L.ITEM_EXTRA) * (range + L.ITEM_EXTRA)
    o.r2leader = L.LEADER_RANGE * L.LEADER_RANGE
    o.people, o.hostile, o.items, o.defeated = people and true or false, hostile and true or false, items and true or false,
        defeated and true or false
    return o
end

-- the pool's radius around the character (farthest: its farthest follower, HU; look096.md 7.2.2)
function L.Radius(range, farthest)
    return math.min((tonumber(range) or 120) + L.ITEM_EXTRA + (tonumber(farthest) or 0), L.SCAN_MAX)
end

-- I.Category's word -> the look's category (nil: not a person)
function L.CategoryOf(word)
    if word == "friendly" or word == "neutral" or word == "player" then return CAT_PEOPLE end
    if word == "hostile" then return CAT_HOSTILE end
    return nil
end

-- G-SA1's own entities are never targets: the game looks neither at rings nor at item boxes (look096.md 3.3)
function L.IsOurClass(cls)
    return string.sub(cls, 1, 4) == "gsa1"
end
function L.IsItemClass(cls)
    return string.sub(cls, 1, 5) == "item_"
end

function L.NewLooker(id, follower)
    return { id = id, key = -id, follower = follower and true or false, x = 0, y = 0, z = 0, fx = 1, fy = 0, curSince = 0,
             candSince = 0, nextTrace = 0 }
end

function L.SetFacing(l, yawDegrees)
    local y = math.rad(tonumber(yawDegrees) or 0)
    l.fx, l.fy = math.cos(y), math.sin(y)
end

-- a blocked key still counts (an expired entry goes)
local function is_blocked(bl, key, now)
    local t = bl[key]
    if not t then return false end
    if t > now then return true end
    bl[key] = nil
    return false
end

-- the choice for one looker: the candidate it looks at now (nil: none), with the hysteresis; pool[1..n]. No allocation.
function L.Choose(l, pool, n, o, now)
    local lx, ly, lz, fx, fy = l.x, l.y, l.z, l.fx, l.fy
    local me, leader, isf, bl = l.key, l.leaderKey, l.follower, l.blocked
    local cur = l.cur
    local curE, best, bestP, bestD = nil, nil, 9, 1e30
    local r2, r2far, people, hostile, items, defeated = o.r2, o.r2far, o.people, o.hostile, o.items, o.defeated
    for i = 1, n do
        local c = pool[i]
        local key = c.key
        if key ~= me and key ~= leader and not (isf and c.follower) then
            local cat = c.cat
            local reach, on, prio
            if cat == CAT_PEOPLE then reach, on, prio = r2, people, 2
            elseif cat == CAT_HOSTILE then reach, on, prio = r2, hostile, 2
            elseif cat == CAT_ITEM then reach, on, prio = r2far, items, 3
            else reach, on, prio = r2far, defeated, 1 end
            if on then
                local dx, dy, dz = c.x - lx, c.y - ly, c.z - lz
                local h2 = dx * dx + dy * dy
                local d2 = h2 + dz * dz
                if d2 <= reach then
                    local dot = dx * fx + dy * fy
                    if (dot >= 0 or dot * dot <= COS2 * h2) and not (bl and is_blocked(bl, key, now)) then
                        if key == cur then curE = c end
                        if prio < bestP or (prio == bestP and d2 < bestD) then best, bestP, bestD = c, prio, d2 end
                    end
                end
            end
        end
    end
    -- the leader, last (it is left out above); a held leader must stay eligible like any other target
    local le = isf and l.leaderEntry or nil
    if le then
        local key = le.key
        local dx, dy, dz = le.x - lx, le.y - ly, le.z - lz
        local h2 = dx * dx + dy * dy
        if h2 + dz * dz <= o.r2leader then
            local dot = dx * fx + dy * fy
            if (dot >= 0 or dot * dot <= COS2 * h2) and not (bl and is_blocked(bl, key, now)) then
                if key == cur then curE = le end
                if not best then best = le end
            end
        end
    end
    -- the hysteresis
    if cur and not curE then
        cur, l.cur = nil, nil       -- gone or not eligible: dropped at once
    end
    local bk = best and best.key or nil
    if bk == cur then
        l.cand = nil
        return curE
    end
    if bk ~= l.cand then l.cand, l.candSince = bk, now end
    if now - l.candSince >= SWITCH - 1e-9 and (cur == nil or now - l.curSince >= HOLD - 1e-9) then
        l.cur, l.curSince, l.cand = bk, now, nil
        return best
    end
    return curE
end

-- a line of sight failed: the target is dropped for L.BLOCKED_FOR s (the next round chooses without it)
function L.Block(l, key, now)
    local bl = l.blocked
    if not bl then
        bl = {}
        l.blocked = bl
    end
    bl[key] = now + L.BLOCKED_FOR
    if l.cur == key then l.cur = nil end
    l.cand = nil
end

-- the point to send between two samples: the sample before -> the newest over one round (the head follows a walking NPC
-- in every frame; no engine call per looker per frame: gsa1_098_plan.md 2.4 D10). A defeated target has px = x.
function L.PointAt(c, now)
    local a = (now - c.t) / L.ROUND
    if a >= 1 then return c.x, c.y, c.z end
    if a < 0 then a = 0 end
    local px, py, pz = c.px, c.py, c.pz
    return px + (c.x - px) * a, py + (c.y - py) * a, pz + (c.z - pz) * a
end
