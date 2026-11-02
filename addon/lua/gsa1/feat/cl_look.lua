-- G-SA1 feature "look", client (round 0.9.8: sadc docs/research/gsa1_098_plan.md 5.9, 6.8 with 2.4 D10; gsa1_096_plan.md
-- 4.20, 5.5, 5.6, 6.6 with its review R.12 / R.13; look096.md 7.2; the module: src/module/bind_look.cpp; the choice:
-- feat/sh_look.lua). The heads of your character and of its followers turn to what is near, through the game's own head code.
--   * THE POOL, every 0.1 s (L.ROUND) in the hook GSA1PreTick "gsa1_look": one ents.FindInSphere around your character's drawn
--     position, radius range + 40 + the farthest follower's distance, at most 2,400 HU, at most 64 candidates: NPCs and
--     NextBots (I.EntityInfo + I.Category: friendly / neutral / hostile by the server's relations; point EyePos), other players
--     (EyePos; a G-SA1 player: the root + the eyes' height), free weapons and item_* pickups (WorldSpaceCenter; never G-SA1's
--     rings and boxes), what was just defeated (when I.killed[idx] appears for an entity the pool held: its last point, 5 s),
--     then your character and your followers (drawPos + the kind's eyes: a table read, no engine Vector).
--   * THE CHOICE, once per looker per round: L.Choose (feat/sh_look.lua).
--   * LINE OF SIGHT for the chosen target: util.TraceLine from the looker's eyes (MASK_VISIBLE, its own entity, the target and
--     the player filtered), at most every 0.25 s per looker and 60 a second in all, round robin (100 lookers: each about every
--     1.7 s). No look until the first trace passes (no head turned through a wall); a blocked target is dropped for 1 s.
--   * SENDING, in every frame before the tick: gsa1.Look(id, POINT, x, y, z) when the point changed (a look stays latched in
--     libsa1 until the next call; the point moves between two rounds' samples: L.PointAt), one LOOK_OFF when there is nothing,
--     LOOK_CAMERA while the camera key is held. A false from gsa1.Look (E-102 has no look task: the game never turns his head)
--     is remembered per character: no more calls.
--   * WITH NO CHARACTER OF YOURS GSA1PreTick does not run, and a look stays latched (review R.13): GSA1CharacterRemoved sends
--     one LOOK_OFF to every follower, and nothing more is sent until you have a character.
--   * GARBAGE (2.4 D10, decision A22: at most 300 B a frame, tests/feat_look_test.lua): nothing per frame; per round the engine's
--     table of ents.FindInSphere and one Vector per candidate (EyePos, WorldSpaceCenter, GetPos have no form without one); per
--     trace what util.TraceLine puts into its reused output table. The session log's "look" line (every 10 s) has the top
--     gsa1_look* hooks' garbage from the meter (cl_gcmeter.lua).
-- Seams, none of them edited: GSA1PreTick, GSA1CharacterCreated, GSA1CharacterLeaving, GSA1CharacterRemoved, GSA1CharacterDied,
-- GSA1FollowerCreated, GSA1FollowerRemoved, GSA1.Followers (list, byId; F.drawPos, drawYaw, kind, leaderId, ent, held: a held
-- follower is out of the lists, 096 review R.15; never written),
-- GSA1.Interact (EntityInfo, Category, killed), GSA1.AddMenuPage, GSA1.ConVar, GSA1.FirstPerson.
GSA1 = GSA1 or {}
local L = GSA1.Look
if not L then return end

local CAT_DEFEATED, CAT_PEOPLE, CAT_HOSTILE, CAT_ITEM = L.CAT_DEFEATED, L.CAT_PEOPLE, L.CAT_HOSTILE, L.CAT_ITEM

local cv = {
    look       = GSA1.ConVar("gsa1_look", 1, "Heads turn to look at: 0 = only what the game looks at, 1 = also Garry's Mod "
        .. "things (people, items, what you defeated)", 0, 1),
    people     = GSA1.ConVar("gsa1_look_people", 1, "Heads turn to friendly and neutral NPCs and other players", 0, 1),
    hostile    = GSA1.ConVar("gsa1_look_hostile", 0, "Heads turn to hostile NPCs too (the game never looks at enemies)", 0, 1),
    items      = GSA1.ConVar("gsa1_look_items", 1, "Heads turn to items lying near", 0, 1),
    defeated   = GSA1.ConVar("gsa1_look_defeated", 1, "Heads turn to what you just defeated, for 5 seconds", 0, 1),
    range      = GSA1.ConVar("gsa1_look_range", 120, "How near a thing must be for a head to turn to it (Hammer units; items "
        .. "and what you defeated 40 more)", 40, 400),
    emotes     = GSA1.ConVar("gsa1_look_emotes", 1, "Heads also turn while an emote plays (0: your character's look ends during "
        .. "emotes)", 0, 1),
    followers  = GSA1.ConVar("gsa1_look_followers", 1, "Followers look at: 0 = only what the game makes them, 1 = the same "
        .. "things as you, and at you when there is nothing else", 0, 1),
    camera_key = GSA1.ConVar("gsa1_look_camera_key", 0, "Hold this key to look at the camera (the game's Z button; a key code, "
        .. "0 = none)", 0),
    camera_all = GSA1.ConVar("gsa1_look_camera_all", 1, "The camera key turns your followers' heads too", 0, 1),
    super      = GSA1.ConVar("gsa1_look_super", 0, "Super Sonic turns his head too (the game turns only normal Sonic's head)",
        0, 1),
}
L.cv = cv

local function have()
    return GSA1.mod ~= nil and gsa1 ~= nil and gsa1.Look ~= nil
end
L.Have = have

local function log(kind, ...)
    if GSA1.Log then GSA1.Log(kind, ...) end
end

-- state ---------------------------------------------------------------------------------------------------------------------
L.lookers, L.nlookers, L.byId = {}, 0, {}   -- your character and your followers (a dense list; by character id)
L.pool, L.spare, L.npool, L.nall = {}, {}, 0, 0 -- pool[1..nall]: every sampled candidate; 1..npool (at most 64) are chosen from
L.byKey, L.free = {}, {}
L.round, L.poolTime, L.nextRound = 0, 0, 0
L.cursor, L.traceTokens, L.traceUsed, L.traceWindow, L.lastFrame = 0, 0, 0, 0, nil
L.o = L.SetOptions({}, 120, true, false, true, true)
L.stats = { frames = 0, rounds = 0, traces = 0, sent = 0, choose_s = 0, radius = 0 }
L.nextLine = 0
L.eyes = {}

-- the kind's eyes above the root (gsa1.CharacterInfo: sa1_physics.eyes_height x 4 HU; asked once per kind)
local function eyes_of(kind)
    local e = L.eyes[kind]
    if e then return e end
    local info = gsa1.CharacterInfo and gsa1.CharacterInfo(kind)
    e = type(info) == "table" and tonumber(info.eyes) or 28
    L.eyes[kind] = e
    return e
end

local function add_looker(id, follower, kind, src)
    local l = L.NewLooker(id, follower)
    l.kind, l.src, l.eyes = kind, src, eyes_of(kind)
    L.nlookers = L.nlookers + 1
    L.lookers[L.nlookers] = l
    L.byId[id] = l
    return l
end

local function remove_looker(id)
    local l = L.byId[id]
    if not l then return end
    L.byId[id] = nil
    local n, list = L.nlookers, L.lookers
    for i = 1, n do
        if list[i] == l then
            list[i] = list[n]
            list[n] = nil
            L.nlookers = n - 1
            return
        end
    end
end

-- the pool ------------------------------------------------------------------------------------------------------------------
local function take(key)
    local c = L.byKey[key]
    if c then return c end
    local free = L.free
    local n = #free
    c = free[n]
    if c then
        free[n] = nil
    else
        c = {}
    end
    c.key, c.t, c.till, c.npc, c.follower = key, nil, nil, false, false
    L.byKey[key] = c
    return c
end

local function xyz(v) return v.x, v.y, v.z end

local function sample(c, x, y, z, now)
    if c.t then
        c.px, c.py, c.pz = c.x, c.y, c.z
    else
        c.px, c.py, c.pz = x, y, z
    end
    c.x, c.y, c.z, c.t = x, y, z, now
end

local function put(c, n)
    c.round = L.round
    L.spare[n] = c
    return n
end

-- a thing in the sphere -> its candidate (nothing when it is not one)
local function scan_entity(e, ply, I, killed, now, n)
    local idx = e:EntIndex()
    if idx <= 0 or e == ply or (e.IsDormant and e:IsDormant()) then return n end
    local cls = e:GetClass()
    if e.GSA1Object or L.IsOurClass(cls) then return n end
    local cat, word, npc, x, y, z
    if e:IsNPC() or (e.IsNextBot ~= nil and e:IsNextBot()) then
        if killed and (killed[idx] or 0) > now then return n end   -- (as I.Scan: it is on its way out)
        word = I and I.Category(I.EntityInfo(e)) or "hostile"
        cat, npc = L.CategoryOf(word), true
        if not cat then return n end
        x, y, z = xyz(e:EyePos())
    elseif e:IsPlayer() then
        if e.Alive ~= nil and not e:Alive() then return n end
        cat, word = CAT_PEOPLE, "player"
        if GSA1.IsCharacter and GSA1.IsCharacter(e) then
            x, y, z = xyz(e:GetPos())
            z = z + eyes_of(0)
        else
            x, y, z = xyz(e:EyePos())
        end
    elseif (e:IsWeapon() and not IsValid(e:GetOwner())) or L.IsItemClass(cls) then
        cat, word = CAT_ITEM, "item"
        x, y, z = xyz(e:WorldSpaceCenter())
    else
        return n
    end
    local c = take(idx)
    c.cat, c.word, c.name, c.ent, c.npc = cat, word, cls, e, npc or false
    sample(c, x, y, z, now)
    return put(c, n + 1)
end

-- what was defeated since the last scan: the entity the pool held stays a candidate at its last point (the same key: a head
-- that looked at it goes on looking)
local function note_defeated(I, now)
    local killed = I and I.killed
    if not killed then return end
    local since = L.poolTime
    for i = 1, L.nall do
        local c = L.pool[i]
        if c.npc and c.cat ~= CAT_DEFEATED then
            local k = killed[c.key]
            if k and k - L.KILLED_MARK >= since then
                local t0 = k - L.KILLED_MARK
                c.cat, c.word, c.till = CAT_DEFEATED, "defeated", t0 + L.DEFEATED_FOR
                c.px, c.py, c.pz = c.x, c.y, c.z
            end
        end
    end
end

-- the candidates of this round: L.pool[1..L.nall], the first L.npool are chosen from (the rest: leaders only)
function L.Scan(C, radius, now)
    local I = GSA1.Interact
    local ply = LocalPlayer()
    L.round = L.round + 1
    note_defeated(I, now)
    local n, max = 0, L.POOL_MAX
    for i = 1, L.nall do
        local c = L.pool[i]
        if c.cat == CAT_DEFEATED and c.till > now then n = put(c, n + 1) end
    end
    local found = ents.FindInSphere(C.drawPos, radius)
    local killed = I and I.killed
    for i = 1, #found do
        if n >= max then break end
        local e = found[i]
        local c = L.byKey[e:EntIndex()]
        if not (c and c.round == L.round) then n = scan_entity(e, ply, I, killed, now, n) end
    end
    -- the characters: table reads (followers last: they never crowd out the world's things)
    local Fo = GSA1.Followers
    local list = Fo and Fo.list
    if list and list[1] then
        local pos = C.drawPos
        local c = take(-C.id)
        c.cat, c.word, c.name, c.ent, c.follower = CAT_PEOPLE, "character", C.title or "your character", C.ent, false
        sample(c, pos.x, pos.y, pos.z + eyes_of(C.kind), now)
        n = put(c, n + 1)
        for i = 1, #list do
            local F = list[i]
            pos = F.drawPos
            if pos and not F.held then
                c = take(-F.id)
                c.cat, c.word, c.name, c.ent, c.follower = CAT_PEOPLE, "character", F.title or "a follower", F.ent, true
                sample(c, pos.x, pos.y, pos.z + eyes_of(F.kind), now)
                n = put(c, n + 1)
            end
        end
    end
    -- the old list's leftovers go back; the two lists swap (no table per scan)
    local round, byKey, free = L.round, L.byKey, L.free
    for i = 1, L.nall do
        local c = L.pool[i]
        if c.round ~= round then
            byKey[c.key] = nil
            c.ent = nil
            free[#free + 1] = c
        end
    end
    L.pool, L.spare = L.spare, L.pool
    L.nall, L.npool = n, math.min(n, max)
    L.poolTime = now
end

local function clear_pool()
    local byKey, free = L.byKey, L.free
    for i = 1, L.nall do
        local c = L.pool[i]
        byKey[c.key] = nil
        c.ent = nil
        free[#free + 1] = c
    end
    L.nall, L.npool = 0, 0
end

-- one round --------------------------------------------------------------------------------------------------------------------
local function read_options(o)
    L.SetOptions(o, cv.range:GetFloat(), cv.people:GetBool(), cv.hostile:GetBool(), cv.items:GetBool(), cv.defeated:GetBool())
    o.on, o.followers, o.emotes = cv.look:GetBool(), cv.followers:GetBool(), cv.emotes:GetBool()
    o.camera_key, o.camera_all = cv.camera_key:GetInt(), cv.camera_all:GetBool()
end

local function place(l, pos, yaw)
    l.x, l.y, l.z = pos.x, pos.y, pos.z + l.eyes
    L.SetFacing(l, yaw)
end

local function drop_target(l)
    l.target, l.losKey, l.cur, l.cand = nil, nil, nil, nil
end

function L.Round(C, now)
    local o = L.o
    read_options(o)
    local me = L.byId[C.id]
    local s = C.state
    place(me, C.drawPos, s and s.yaw or 0)
    -- the followers' lookers (made here when a follower came before this file saw it) and how far they are
    local Fo = GSA1.Followers
    local list = Fo and Fo.list
    local farthest, sx, sy = 0, C.drawPos.x, C.drawPos.y
    if list then
        for i = 1, #list do
            local F = list[i]
            local pos = F.drawPos
            local l = L.byId[F.id]
            if F.held then
                -- (096 review R.15: it stands far above its leader, out of the look's lists; its latched look ends once)
                if l then
                    l.held = true
                    drop_target(l)
                end
            elseif pos then
                l = l or add_looker(F.id, true, F.kind, F)
                l.held = false
                place(l, pos, F.drawYaw or 0)
                l.ent, l.leaderKey = F.ent, F.leaderId and -F.leaderId or nil
                local dx, dy = pos.x - sx, pos.y - sy
                local d2 = dx * dx + dy * dy
                if d2 > farthest then farthest = d2 end
            end
        end
    end
    me.ent = C.ent
    -- nobody chooses: no scan at all
    local choosing = false
    if o.on then
        for i = 1, L.nlookers do
            local l = L.lookers[i]
            if not l.refused and not l.dead and not l.held and (not l.follower or o.followers) then
                choosing = true
                break
            end
        end
    end
    if not choosing then
        if L.nall > 0 then clear_pool() end
        for i = 1, L.nlookers do drop_target(L.lookers[i]) end
        return
    end
    local radius = L.Radius(o.range, math.sqrt(farthest))
    L.stats.radius = radius
    L.Scan(C, radius, now)
    -- the choice, per looker
    local t0 = SysTime()
    local pool, npool, byKey = L.pool, L.npool, L.byKey
    local followers = o.followers
    for i = 1, L.nlookers do
        local l = L.lookers[i]
        if l.refused or l.dead or l.held or (l.follower and not followers) then
            if l.target or l.cur then drop_target(l) end
        else
            local lk = l.leaderKey
            l.leaderEntry = lk and byKey[lk] or nil
            local t = L.Choose(l, pool, npool, o, now)
            if t ~= l.target then
                l.target = t
                if not t or l.losKey ~= t.key then l.losKey, l.nextTrace = nil, 0 end
            end
        end
    end
    local st = L.stats
    st.rounds, st.choose_s = st.rounds + 1, st.choose_s + (SysTime() - t0)
end

-- line of sight --------------------------------------------------------------------------------------------------------------
local tr_filter, tr_out = {}, {}
local tr = { start = Vector(), endpos = Vector(), filter = tr_filter, output = tr_out, mask = MASK_VISIBLE or 24705 }

function L.Traces(now)
    local last = L.lastFrame
    L.lastFrame = now
    local dt = last and now - last or 0
    if now >= L.traceWindow then L.traceWindow, L.traceUsed = now + 1, 0 end
    L.traceTokens = math.min(L.traceTokens + dt * L.TRACES_PER_SECOND, L.TRACES_PER_FRAME)
    local n = L.nlookers
    if n == 0 then return end
    local ply = LocalPlayer()
    local cursor = L.cursor
    for _ = 1, n do
        if L.traceTokens < 1 or L.traceUsed >= L.TRACES_PER_SECOND then break end
        cursor = cursor % n + 1
        local l = L.lookers[cursor]
        local t = l.target
        if t and now >= l.nextTrace then
            l.nextTrace = now + L.TRACE_EVERY
            L.traceTokens, L.traceUsed = L.traceTokens - 1, L.traceUsed + 1
            tr.start:SetUnpacked(l.x, l.y, l.z)
            tr.endpos:SetUnpacked(t.x, t.y, t.z)
            local me, it = l.ent, t.ent
            tr_filter[1], tr_filter[2], tr_filter[3] = IsValid(me) and me or ply, IsValid(it) and it or ply, ply
            local res = util.TraceLine(tr)
            L.stats.traces = L.stats.traces + 1
            if res and res.Hit then
                L.Block(l, t.key, now)
                l.target, l.losKey = nil, nil
            else
                l.losKey = t.key
            end
        end
    end
    L.cursor = cursor
end

-- sending ---------------------------------------------------------------------------------------------------------------------
local function camera_held(code)
    if code <= 0 or input == nil or input.IsButtonDown == nil then return false end
    if GSA1.FirstPerson and GSA1.FirstPerson() then return false end    -- the eye is inside the head
    if vgui.CursorVisible() or gui.IsGameUIVisible() or (GSA1.InputBlocked and GSA1.InputBlocked()) then return false end
    local ply = LocalPlayer()
    if ply.IsTyping ~= nil and ply:IsTyping() then return false end
    return input.IsButtonDown(code) == true
end

local function refused(l, msg)
    l.refused = tostring(msg or "refused")
    drop_target(l)
    log("look", "%s: no head look: %s", l.src and l.src.title or tostring(l.id), l.refused)
end

local function send_off(l, off)
    local ok, msg = gsa1.Look(l.id, off)
    L.stats.sent = L.stats.sent + 1
    if ok then
        l.sk = off
    else
        refused(l, msg)
    end
end

function L.Send(C, now)
    local o = L.o
    local off, point, camera = gsa1.LOOK_OFF, gsa1.LOOK_POINT, gsa1.LOOK_CAMERA
    local held = camera_held(o.camera_key or 0)
    local emote = false
    if not o.emotes and gsa1.EmoteState then
        local st = gsa1.EmoteState(C.id)
        emote = st ~= nil and st ~= 0
    end
    local camera_all = o.camera_all
    for i = 1, L.nlookers do
        local l = L.lookers[i]
        if not l.refused then
            local isf = l.follower
            if l.dead or (emote and not isf) then
                if l.sk ~= off then send_off(l, off) end
            elseif held and (not isf or camera_all) then
                if l.sk ~= camera then
                    local ok, msg = gsa1.Look(l.id, camera)
                    L.stats.sent = L.stats.sent + 1
                    if ok then
                        l.sk = camera
                    else
                        refused(l, msg)
                    end
                end
            else
                local t = l.target
                if t and l.losKey == t.key then
                    local x, y, z = L.PointAt(t, now)
                    if l.sk ~= point or x ~= l.sx or y ~= l.sy or z ~= l.sz then
                        local ok, msg = gsa1.Look(l.id, point, x, y, z)
                        L.stats.sent = L.stats.sent + 1
                        if ok then
                            l.sk, l.sx, l.sy, l.sz = point, x, y, z
                        else
                            refused(l, msg)
                        end
                    end
                elseif l.sk ~= off then
                    send_off(l, off)
                end
            end
        end
    end
end

-- the session log (2.4 D10: its own line; cl_log.lua's perf line is cut at about 900 characters)
L.slotLast = {}
function L.HooksField(frames)
    local GM = GSA1.GcMeter
    if not (GM and GM.on and GM.list) then return "the garbage meter is off" end
    local top = {}
    for _, s in ipairs(GM.list) do
        if string.find(s.key, "/ gsa1_look", 1, true) then
            top[#top + 1] = { s.key, s.kb - (L.slotLast[s.key] or 0) }
            L.slotLast[s.key] = s.kb
        end
    end
    if #top == 0 then return "no gsa1_look hook measured yet" end
    table.sort(top, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for i = 1, math.min(3, #top) do
        local b = top[i][2] * 1024 / math.max(frames, 1)
        if b >= 0.5 then parts[#parts + 1] = string.format("%s %.0f B", top[i][1], b) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "under 1 B"
end

function L.LogLine(now)
    local st = L.stats
    local secs = 10
    log("look", "head look: lookers %d, candidates %d (radius %.0f HU); choosing %.4f ms a round, %.1f traces and %.1f looks "
        .. "sent a second; garbage per frame: %s", L.nlookers, L.npool, st.radius, st.rounds > 0 and st.choose_s * 1000 / st.rounds
        or 0, st.traces / secs, st.sent / secs, L.HooksField(st.frames))
    st.frames, st.rounds, st.traces, st.sent, st.choose_s = 0, 0, 0, 0, 0
end

function L.LogSettings()
    local function v(c) return c and c:GetString() or "?" end
    log("settings", "head look: heads turn %s, people %s, hostile %s, items %s, defeated %s, range %s, emotes %s, followers %s, "
        .. "camera key %s (followers too %s), Super Sonic %s", v(cv.look), v(cv.people), v(cv.hostile), v(cv.items),
        v(cv.defeated), v(cv.range), v(cv.emotes), v(cv.followers), v(cv.camera_key), v(cv.camera_all), v(cv.super))
end

-- the hooks -------------------------------------------------------------------------------------------------------------------
function L.Frame(C, now)
    if not L.byId[C.id] then add_looker(C.id, false, C.kind, C) end
    L.stats.frames = L.stats.frames + 1
    if now >= L.nextRound then
        L.nextRound = now + L.ROUND
        L.Round(C, now)
        if now >= L.nextLine then
            if L.nextLine > 0 then L.LogLine(now) end
            L.nextLine = now + 10
        end
    end
    L.Traces(now)
    L.Send(C, now)
end

hook.Add("GSA1PreTick", "gsa1_look", function(C)
    if not C or not have() then return end
    L.Frame(C, SysTime())
end)

-- Super Sonic's head: libsa1 knows which worlds can take it (kind 8 and a Sonic created super-capable; a plain Sonic's world
-- answers "unsupported": nothing to say about that)
function L.ApplySuper(C, on)
    if not C or (C.kind ~= 8 and C.kind ~= 0) or not have() or not gsa1.SetCharOption or not gsa1.COPT_SUPER_LOOK then
        return false
    end
    local ok, err, code = gsa1.SetCharOption(C.id, gsa1.COPT_SUPER_LOOK, on and 1 or 0)
    if not ok then
        if C.kind == 8 or code ~= "unsupported" then
            log("look", "%s: Super Sonic's head: %s", C.title or "?", tostring(err))
        end
        return false
    end
    return true
end

hook.Add("GSA1CharacterCreated", "gsa1_look", function(C)
    if not C or not have() then return end
    if not L.settingsLogged then
        L.settingsLogged = true
        L.LogSettings()
    end
    if cv.super:GetBool() then L.ApplySuper(C, true) end
end)

-- its world goes: its looker goes with it (a new character gets a new one at its first tick)
hook.Add("GSA1CharacterLeaving", "gsa1_look", function(C)
    if C and C.id then remove_looker(C.id) end
end)

-- no character of yours any more: GSA1PreTick stops, and a look stays latched (review R.13)
hook.Add("GSA1CharacterRemoved", "gsa1_look", function(C, switching)
    if switching or not have() then return end
    local off = gsa1.LOOK_OFF
    for i = 1, L.nlookers do
        local l = L.lookers[i]
        if l.follower then
            drop_target(l)
            if not l.refused then send_off(l, off) end
        end
    end
    if L.nall > 0 then clear_pool() end
end)

-- a dying character does not look round: one OFF, and a new character has a new looker
hook.Add("GSA1CharacterDied", "gsa1_look", function(C)
    local l = C and L.byId[C.id]
    if l then
        l.dead = true
        drop_target(l)
    end
end)

hook.Add("GSA1FollowerCreated", "gsa1_look", function(F)
    if F and F.id and have() and not L.byId[F.id] then add_looker(F.id, true, F.kind, F) end
end)
hook.Add("GSA1FollowerRemoved", "gsa1_look", function(F)
    if F and F.id then remove_looker(F.id) end
end)

-- the settings ------------------------------------------------------------------------------------------------------------------
for _, name in ipairs({ "gsa1_look", "gsa1_look_people", "gsa1_look_hostile", "gsa1_look_items", "gsa1_look_defeated",
                        "gsa1_look_range", "gsa1_look_emotes", "gsa1_look_followers", "gsa1_look_camera_key",
                        "gsa1_look_camera_all", "gsa1_look_super" }) do
    cvars.AddChangeCallback(name, function() L.LogSettings() end, "gsa1_look")
end
cvars.AddChangeCallback("gsa1_look_super", function(_, _, new)
    if GSA1.Char then L.ApplySuper(GSA1.Char, tonumber(new) ~= 0) end
end, "gsa1_look_apply")

-- the page -------------------------------------------------------------------------------------------------------------------
local stateOut = {}
function L.StatusLines()
    local lines = {}
    if not have() then
        lines[1] = "The head look needs the G-SA1 module " .. L.NEEDS.module .. "."
        return lines
    end
    local C = GSA1.Char
    local l = C and L.byId[C.id]
    if not l then
        lines[1] = "No character yet."
        return lines
    end
    local title = C.title or "Your character"
    if l.refused then
        lines[1] = C.kind == 6 and "E-102 never turns his head (as the game)." or (title .. ": " .. l.refused)
        return lines
    end
    local st = gsa1.LookState and gsa1.LookState(C.id, stateOut) or nil
    local head = st and string.format(" - head %+.0f / %+.0f", st.head_y or 0, st.head_z or 0) or ""
    local t = l.target
    if st and st.owner == 2 then
        lines[1] = title .. ": the game's own look" .. head
    elseif l.sk == gsa1.LOOK_CAMERA then
        lines[1] = title .. " looks at the camera" .. head
    elseif t and l.losKey == t.key then
        local dx, dy, dz = t.x - l.x, t.y - l.y, t.z - l.z
        lines[1] = string.format("%s looks at %s (%s, %.0f HU)%s", title, tostring(t.name), tostring(t.word),
            math.sqrt(dx * dx + dy * dy + dz * dz), head)
    else
        lines[1] = title .. " looks at nothing in particular" .. head
    end
    local nf, looking = 0, 0
    for i = 1, L.nlookers do
        local f = L.lookers[i]
        if f.follower then
            nf = nf + 1
            if f.target or f.sk == gsa1.LOOK_CAMERA then looking = looking + 1 end
        end
    end
    if nf > 0 then lines[2] = string.format("Followers: %d of %d look at something.", looking, nf) end
    return lines
end

local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[1], c[2]) end
    combo.OnSelect = function(_, _, _, data) RunConsoleCommand(cvname, tostring(data)) end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local c = GetConVar(cvname)
        local v = c and c:GetString() or ""
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        local n = tonumber(v)
        for _, ch in ipairs(choices) do
            if n ~= nil and tonumber(ch[2]) == n then
                self:SetText(ch[1])
                return
            end
        end
    end
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

function L.BuildPage(panel)
    panel:Help("Your character and your followers turn their heads with the game's own head code. E-102 never turns his head; "
        .. "Big moves only his eyes; Sonic standing moves only his eyes; Tails' and Big's eyes stay centred while they talk - "
        .. "all as in the game.")
    live_label(panel, L.StatusLines)
    choice_combo(panel, "Heads turn to look at", "gsa1_look", { { "only what the game looks at", 0 },
        { "also Garry's Mod things", 1 } })
    panel:ControlHelp("Garry's Mod things are people, items and what you defeated: the game's characters look at people who "
        .. "talk to them, upgrade items and freed animals. The camera key below works either way.")
    panel:CheckBox("Friendly and neutral NPCs and other players", "gsa1_look_people")
    panel:CheckBox("Hostile NPCs too (the game never looks at enemies)", "gsa1_look_hostile")
    panel:CheckBox("Items lying near", "gsa1_look_items")
    panel:ControlHelp("Weapons and pickups. Never G-SA1's rings and item boxes: the game does not look at them either.")
    panel:CheckBox("What you just defeated, for 5 seconds", "gsa1_look_defeated")
    panel:NumSlider("How near (Hammer units)", "gsa1_look_range", 40, 400, 0)
    panel:ControlHelp("The game: 120 for people. Items and what you defeated: 40 more. Only within 100 degrees to either side "
        .. "of where the character faces, and only what it can see.")
    panel:CheckBox("Also while an emote plays", "gsa1_look_emotes")
    choice_combo(panel, "Followers look at", "gsa1_look_followers", { { "only what the game makes them", 0 },
        { "the same things as you, and at you", 1 } })
    panel:ControlHelp("The game's follower never looks at anything; the second choice is G-SA1's. They look at you when there "
        .. "is nothing else.")
    panel:Help("Hold to look at the camera (the game's Z button)")
    local b = vgui.Create("DBinder", panel)
    if b.SetConVar then b:SetConVar("gsa1_look_camera_key") end
    if b.SetTall then b:SetTall(28) end
    panel:AddItem(b)
    panel:Button("No camera key", "gsa1_look_camera_key", "0")
    panel:ControlHelp("Does nothing in first person (the eye is inside the head).")
    panel:CheckBox("The camera key turns your followers' heads too", "gsa1_look_camera_all")
    panel:CheckBox("Super Sonic turns his head too", "gsa1_look_super")
    panel:ControlHelp("The game turns only normal Sonic's head, which is hidden while he is Super. Not the game's own "
        .. "behaviour.")
end

GSA1.AddMenuPage(L.PAGE_ORDER, "look", "Head look", L.BuildPage, L.NEEDS)
