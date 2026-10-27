-- G-SA1 interaction (round 5), client: Garry's Mod's world as the game's objects, the hits and pushes going to the
-- server, the interact key and the Q-menu page Options > G-SA1 > Interaction. The rules are sh_interact.lua's; the
-- server's side is sv_interact.lua; the module's side is src/module/bind_interact.cpp (libsa1's host objects).
--
-- Every 0.1 s the entities within 2400 units of the character are looked at (ents.FindInSphere): NPCs and NextBots
-- (hostile / neutral / friendly by the server's relation messages, else by class), other players (PvP), vehicles,
-- props with health and props the server tagged as liftable, balloons and hazards. Each becomes a libsa1 host object
-- (gsa1.ObjAdd, keyed by its entity index) shaped from its collision bounds; every game pair (30 Hz) it is moved to where
-- the entity is (gsa1.ObjMove). In the character's world they are real game objects: Sonic's jump, roll and homing
-- attack, Knuckles' punches, Amy's hammer, E-102's lock-on and laser, Big's lure, the bounce, touch damage with the
-- game's own knock-back and ring loss, the lift and throw, a balloon's launch - all the game's own code.
--   * HIT events go to the server (gsa1_hit) when that kind of target's "attack" switch is on: Garry's Mod damage there.
--   * LIFTED / RELEASED: the server freezes the prop while it is carried and follows the pose this client sends; this
--     client draws it at the character's hands every frame (no network delay for the player); a throw gets the game's
--     own speed.
--   * Damage the player takes on the server comes back (gsa1_hurt) and hits the character in its game (rings).
--   * Pushing (the owner's addition A): the game's contacts with moving objects (gsa1.Contacts) - a physics prop the
--     character runs, rolls or spin-dashes into - go to the server (gsa1_push), which pushes the prop by mass; standing on
--     a prop never pushes it. The game stops a fast ball short of a wall without touching it, so a ball whose speed drops
--     to under 40% within a frame with a prop just ahead (Garry's Mod's own trace) counts as an impact as well.
--   * The interact key (the owner's addition B; default: the key of +use, E): a liftable prop in front -> the game's
--     action button for a moment (the game lifts it; carrying: puts it down or throws it); otherwise the server uses the
--     door, button or other usable thing in front of the character (sv_interact.lua), or a vehicle: the character steps
--     out and you drive, and become the character again when you leave it.
-- 0.9.2 (sadc docs/research/gsa1_090_player.md L6-L8, H1-H3 and gsa1_090_faults.md with their reviews; owner answer,
-- rounds plan 14.1j: a NextBot's or a script's kill of the player kills the character too and both come back together):
--   * the player died (gsa1_player_died: Player:Kill, a deadly hit in the health modes) -> the character is killed the
--     game's way (DAMAGE_KILL; "The character can die" off: a plain hit and the player comes back at once); when the
--     character respawns (GSA1CharacterRespawned) a dead player asks the server to come back with it (gsa1_respawn);
--   * no hit reaches a dead character or one that has not run its first game pair (the gm_goldencity_v2 fault: a hit on a
--     respawned Sonic before PInitialize, gsa1_090_faults.md 1.3): dropped and counted; a kill there waits for that pair;
--   * hurt lines name the attacker's class (the server sends it);
--   * a carried prop is drawn and sent with its lowest corner above the floor under it (the higher of the character's feet
--     and a trace of its footprint), or over the head; its put-down position is raised the same way.
GSA1 = GSA1 or {}
local I = GSA1.Interact
if not I then return end
local K, cv = I.K, I.cv

local SCAN_INTERVAL, SCAN_RANGE, LEAVE_RANGE, MAX_OBJECTS = 0.1, 2400, 2800, 512
local MOVE_INTERVAL = 1 / 30
local HIT_INTERVAL, POSE_INTERVAL = 1 / 30, 1 / 30
local CLEAR_AFTER = 2.0          -- seconds without a character: every object out of libsa1
local BTN_ACTION = 2             -- SA1_BUTTON_ACTION
local ACTION_TIME = 0.05         -- seconds the interact key holds the action button (at least one game pair)
local guard = GSA1.Guard or function(_, fn) return fn end
local MAX_HIT_LINES = 200        -- hits written into the session log; the rest are only counted
-- the session log (cl_log.lua; a line repeated within a few seconds is counted, not written again)
local function log(kind, ...)
    if GSA1.Log then GSA1.Log(kind, ...) end
end

I.objects = I.objects or {}      -- [entity index] = { ent, cat, kind, sig, character }
I.rel = I.rel or {}              -- [entity index] = relation (the server's)
I.killed = I.killed or {}        -- [entity index] = time until which a killed NPC is not registered again
I.stats = I.stats or { hits = 0, hits_sent = 0, pushes = 0, pushes_sent = 0, presses = 0, uses = 0, lifts = 0,
                       releases = 0, hurts = 0, denied = 0, add_errors = 0, hurts_dropped = 0, player_deaths = 0,
                       respawn_asks = 0 }
I.evbuf, I.cbuf, I.st = I.evbuf or {}, I.cbuf or {}, I.st or {}
I.nextScan, I.nextMove, I.nextHit = 0, 0, 0

function I.HasModule()
    return GSA1.HasFeature ~= nil and GSA1.HasFeature(I.NEEDS.feature, I.NEEDS.version) or false
end

-- the server has the interaction feature (it pooled the network strings)
local server_seen, server_until = false, 0
function I.ServerOk()
    local now = SysTime()
    if now >= server_until then
        server_until = now + 1
        server_seen = util.NetworkStringToID(I.NET.HIT) ~= 0
    end
    return server_seen
end

-- the module's constants against this addon's (once)
local consts_checked = false
local function check_constants()
    if consts_checked then return end
    consts_checked = true
    local m = gsa1 and gsa1.INTERACT
    if type(m) ~= "table" then return end
    local bad = {}
    for k, v in pairs(I.K) do
        if m[k] ~= nil and m[k] ~= v then bad[#bad + 1] = k end
    end
    if #bad > 0 then
        table.sort(bad)
        GSA1.Msg("interaction: the module's numbers differ from the addon's (%s): install the module and the addon of "
            .. "the same version", table.concat(bad, ", "))
    end
end

-- what the client knows about an entity (one table, reused)
local info = {}
function I.EntityInfo(e)
    local idx = e:EntIndex()
    info.class = e:GetClass()
    info.npc = e:IsNPC()
    info.nextbot = e.IsNextBot ~= nil and e:IsNextBot() or false
    info.player = e:IsPlayer()
    info.vehicle = e:IsVehicle()
    info.character = info.player and GSA1.IsCharacter ~= nil and GSA1.IsCharacter(e) or false
    info.holdable = e:GetNW2Bool("gsa1_hold", false)
    info.hp = e:GetNW2Int("gsa1_hp", 0)
    info.rel = I.rel[idx]
    info.movers = GSA1.cv ~= nil and GSA1.cv.phys_props ~= nil and GSA1.cv.phys_props:GetBool() or false
    local holder = e:GetNW2Entity("gsa1_holder")
    info.held_elsewhere = IsValid(holder) and holder ~= LocalPlayer()
    return info
end

-- the position an object is registered at: the OBB's centre (a G-SA1 player: its character's middle)
local function anchor(o, e)
    if o.character then
        local p = e:GetPos()
        p.z = p.z + 20
        return p
    end
    return e:WorldSpaceCenter()
end

local function round(v) return math.floor(v * 4 + 0.5) / 4 end

function I.Register(e, idx, cat, kind, flags, touch, armor, inf, s, now)
    local form, sx, sy, sz = I.ShapeFromOBB(cat, inf.class, e:OBBMins(), e:OBBMaxs(), inf.character)
    local launch = kind == K.BALLOON and s.balloon_speed or 0
    local sig = string.format("%d:%d:%d:%d:%d:%g:%g:%g:%g", kind, flags, touch, armor, form, round(sx), round(sy),
        round(sz), launch)
    local o = I.objects[idx]
    if o and o.sig == sig and o.ent == e then return o end
    local temp = { character = inf.character }
    local p = anchor(temp, e)
    local id, err = gsa1.ObjAdd(idx, kind, flags, p.x, p.y, p.z, e:GetAngles().y, armor, touch, 0, 1,
        form, 0, 0, 0, sx, sy, sz, 0, 0, launch, 0)
    if not id then
        I.stats.add_errors = I.stats.add_errors + 1
        if I.stats.add_errors <= 3 then GSA1.Msg("interaction: %s (%s): %s", inf.class, cat, tostring(err)) end
        return nil
    end
    o = { ent = e, cat = cat, kind = kind, sig = sig, character = inf.character, id = id }
    I.objects[idx] = o
    return o
end

function I.Unregister(idx, killed)
    if I.objects[idx] and gsa1 and gsa1.ObjRemove then gsa1.ObjRemove(idx, killed and true or false) end
    I.objects[idx] = nil
end

function I.ClearAll()
    if gsa1 and gsa1.ObjClear and next(I.objects) then gsa1.ObjClear() end
    I.objects = {}
end

-- the look around (every 0.1 s)
function I.Scan(C, now)
    local s = I.Settings()
    I.settings = s
    local ply = LocalPlayer()
    local pos = C.drawPos
    local found, seen, n = {}, {}, 0
    if s.interact then
        for _, e in ipairs(ents.FindInSphere(pos, SCAN_RANGE)) do
            -- (0.9.4: a G-SA1 game object is the game's own object in the world, never a host object: feat/sh_objects.lua)
            if IsValid(e) and e ~= ply and not e:IsWorld() and not e:IsWeapon() and not e.GSA1Object then
                local idx = e:EntIndex()
                if idx > 0 and (I.CandidateClass(e:GetClass()) or e:IsNPC() or e:IsPlayer() or e:IsVehicle() or
                                e:IsNextBot()) then
                    found[idx] = true
                    if n < MAX_OBJECTS and not ((I.killed[idx] or 0) > now) then
                        local inf = I.EntityInfo(e)
                        local cat = I.Category(inf)
                        if cat then
                            local kind, flags, touch, armor = I.Describe(cat, s, inf)
                            if kind and I.Register(e, idx, cat, kind, flags, touch, armor, inf, s, now) then
                                seen[idx] = true
                                n = n + 1
                            end
                        end
                    end
                end
            end
        end
    end
    local leave2 = LEAVE_RANGE * LEAVE_RANGE
    for idx, o in pairs(I.objects) do
        if not seen[idx] then
            local e = o.ent
            local gone = not IsValid(e) or found[idx] or not s.interact or e:GetPos():DistToSqr(pos) > leave2
            if gone and not (I.held and I.held.idx == idx) then I.Unregister(idx, false) end
        end
    end
end

-- where the entities are now (once per game pair: libsa1 moves them smoothly over it)
function I.MoveAll()
    for idx, o in pairs(I.objects) do
        local e = o.ent
        if IsValid(e) and not (I.held and I.held.idx == idx) then
            local p = anchor(o, e)
            local ok = gsa1.ObjMove(idx, p.x, p.y, p.z, e:GetAngles().y)
            if not ok then I.objects[idx] = nil end          -- the module forgot it (a new disc load): registered again
        end
    end
end

-- events -----------------------------------------------------------------------------------------------------------------
local function send_hit(e, o)
    if not I.ServerOk() then return end
    -- one hit per target per HIT_INTERVAL; different targets hit in the same frame are all sent
    local now = SysTime()
    I.nextHitFor = I.nextHitFor or {}
    if now < (I.nextHitFor[e.ent] or 0) then return end
    I.nextHitFor[e.ent] = now + HIT_INTERVAL
    net.Start(I.NET.HIT)
    net.WriteUInt(e.ent, 16)
    net.WriteUInt(math.Clamp(e.attack, 0, 31), 5)
    net.WriteUInt(math.Clamp(e.level, 0, 3), 2)
    net.WriteUInt(math.Clamp(e.damage, 0, 3), 2)
    net.WriteVector(Vector(e.x, e.y, e.z))
    net.WriteNormal(Vector(e.dx, e.dy, e.dz))
    net.WriteFloat(e.speed)
    net.WriteUInt(math.Clamp(e.flags, 0, 15), 4)
    net.SendToServer()
    I.stats.hits_sent = I.stats.hits_sent + 1
end

function I.OnHit(C, e)
    local o = I.objects[e.ent]
    I.stats.hits = I.stats.hits + 1
    I.lastHit = { ent = e.ent, attack = e.attack, cat = o and o.cat or "?", t = SysTime() }
    if not o then return end
    local sends = I.SendsHits(o.cat, I.settings or I.Settings())
    if sends then send_hit(e, o) end
    if I.stats.hits <= MAX_HIT_LINES then
        log("hit", "%s %s (%d) by %s, level %d, flags 0x%X%s", o.cat, IsValid(o.ent) and o.ent:GetClass() or "?", e.ent,
            (I.ATTACKS[e.attack] or I.ATTACKS[0]).title, e.level, e.flags, sends and "" or " (its attack switch is off)")
    end
    if GSA1.cv.debug:GetBool() then
        GSA1.Msg("interaction: hit %s %d (%s) with %s, level %d, flags 0x%X", o.cat, e.ent,
            IsValid(o.ent) and o.ent:GetClass() or "?", (I.ATTACKS[e.attack] or I.ATTACKS[0]).title, e.level, e.flags)
    end
end

local function send_hold(idx, on, pos, vel, reason)
    if not I.ServerOk() then return end
    net.Start(I.NET.HOLD)
    net.WriteUInt(idx, 16)
    net.WriteBool(on)
    if not on then
        net.WriteVector(pos)
        net.WriteVector(vel)
        net.WriteUInt(math.Clamp(reason or 0, 0, 7), 3)
    end
    net.SendToServer()
end

local function clear_render(ent)
    if IsValid(ent) then
        ent:SetRenderOrigin()
        ent:SetRenderAngles()
    end
end

function I.OnLifted(C, e)
    local o = I.objects[e.ent]
    if not o or not IsValid(o.ent) then
        gsa1.ObjRelease(e.ent)
        return
    end
    local ang = o.ent:GetAngles()
    I.held = { idx = e.ent, ent = o.ent, ang = Angle(ang.p, ang.y, ang.r),
               yaw_off = math.NormalizeAngle(ang.y - (C.state.yaw or 0)), nextPose = 0, since = SysTime() }
    o.ent.GSA1NoCollide = true
    I.stats.lifts = I.stats.lifts + 1
    send_hold(e.ent, true)
    log("hold", "lifted %s (%d)", o.ent:GetModel() or o.ent:GetClass(), e.ent)
end

-- H1 / H3 (gsa1_090_player.md P2): a held prop's centre (cx, cy, cz) in the held angles `ang`, moved so that its lowest
-- corner is CLEAR units above the floor under it - the higher of the character's feet and a downward trace of the prop's
-- footprint from the hold point - or, with "over the head", above the character's head; unchanged when it is clear
-- already (props up to about 25 units tall at Sonic's hands) or with "Keep carried props above the ground" off. The
-- game's held object stays at the hands (it has no collision while held), so only the drawing and the server's prop move.
local CLEAR = 1
local clear_res = {}
local clear_filter = {}
local clear_trace = { start = Vector(), endpos = Vector(), mins = Vector(), maxs = Vector(), output = clear_res,
                      filter = clear_filter }
function I.ClearPose(C, ent, ang, cx, cy, cz, carried)
    if not (cv.hold_clear and cv.hold_clear:GetBool()) or not IsValid(ent) then return cx, cy, cz end
    local low, hx, hy = I.TurnedBox(ent:OBBMins(), ent:OBBMaxs(), ang)
    local feet = C.drawPos.z
    local floor = feet
    clear_trace.start:SetUnpacked(cx, cy, cz)
    clear_trace.endpos:SetUnpacked(cx, cy, cz + low - 2 * CLEAR)
    clear_trace.mins:SetUnpacked(-hx, -hy, 0)
    clear_trace.maxs:SetUnpacked(hx, hy, 1)
    clear_filter[1], clear_filter[2], clear_filter[3] = LocalPlayer(), ent, IsValid(C.ent) and C.ent or nil
    clear_trace.mask = MASK_SOLID or 33570827
    local tr = util.TraceHull(clear_trace)
    if tr and tr.Hit and not tr.StartSolid and tr.HitPos and tr.HitPos.z > floor then floor = tr.HitPos.z end
    local up = I.LiftFor(cz, low, floor, CLEAR)
    if up <= 0 then return cx, cy, cz end
    if carried and cv.hold_overhead and cv.hold_overhead:GetBool() then
        -- over the head: above the character, its bottom just over the head (GSA1.CHAR_SIZE)
        local top = feet + I.CharSize(C.kind).height + CLEAR
        return C.drawPos.x, C.drawPos.y, math.max(cz + up, top - low)
    end
    return cx, cy, cz + up
end

local RELEASE_WORDS = { [K.RELEASE_THROW] = "thrown", [K.RELEASE_THROW_AIMED] = "thrown at a target",
                        [K.RELEASE_PUT_DOWN] = "put down", [K.RELEASE_DROP] = "dropped (hit, or lost)",
                        [K.RELEASE_FORCED] = "let go (the server or the module)" }
function I.OnReleased(C, e)
    local h = I.held
    local ent = h and h.idx == e.ent and h.ent or Entity(e.ent)
    -- H2: the game's release point is the prop's centre at the hands: raised out of the floor like the carried pose
    local rx, ry, rz = e.x, e.y, e.z
    if h and h.idx == e.ent and IsValid(ent) then
        local yaw = h.yaw or ((C.state.yaw or 0) + h.yaw_off)
        local cz0 = rz
        rx, ry, rz = I.ClearPose(C, ent, Angle(h.ang.p, yaw, h.ang.r), rx, ry, rz, false)
        if rz > cz0 + 0.01 then I.stats.releases_lifted = (I.stats.releases_lifted or 0) + 1 end
    end
    send_hold(e.ent, false, Vector(rx, ry, rz), Vector(e.dx * e.speed, e.dy * e.speed, e.dz * e.speed), e.reason)
    clear_render(ent)
    if IsValid(ent) then ent.GSA1NoCollide = SysTime() + 0.6 end   -- out of the character's way while it leaves the hands
    if h and h.idx == e.ent then I.held = nil end
    I.stats.releases = I.stats.releases + 1
    log("hold", "released %d: %s at %.0f units/s", e.ent, RELEASE_WORDS[e.reason] or tostring(e.reason), e.speed)
end

function I.PollEvents(C)
    local ev = gsa1.ObjEvents(I.evbuf)
    for i = 1, ev.count or 0 do
        local e = ev[i]
        if e.character == C.id then
            if e.type == K.EVENT_HIT then
                I.OnHit(C, e)
            elseif e.type == K.EVENT_LIFTED then
                I.OnLifted(C, e)
            elseif e.type == K.EVENT_RELEASED then
                I.OnReleased(C, e)
            elseif GSA1.cv.debug:GetBool() then
                GSA1.Msg("interaction: event %d on %d", e.type, e.ent)
            end
        end
    end
end

-- pushing props (owner addition A) ---------------------------------------------------------------------------------------
function I.Pushable(e)
    if not IsValid(e) or e:IsPlayer() or e:IsNPC() or e:IsWorld() then return false end
    if e:GetMoveType() ~= MOVETYPE_VPHYSICS then return false end
    if I.held and I.held.ent == e then return false end
    return true
end

local reports = {}
local function add_report(idx, dx, dy, dz, px, py, pz, vin, rolling, typ, first)
    if #reports >= 8 then return end
    reports[#reports + 1] = { idx = idx, dx = dx, dy = dy, dz = dz, px = px, py = py, pz = pz, vin = vin,
                              rolling = rolling, typ = typ, first = first }
end

-- a fast ball that stops short of a prop (the game's sweep stops it without a touch): the impact
function I.RollImpact(C, rolling)
    local s0 = C.state
    if not s0.step or s0.step == I.lastStep then return end
    I.lastStep = s0.step
    local vx, vy = s0.vx or 0, s0.vy or 0
    local speed = math.sqrt(vx * vx + vy * vy)
    local prev = I.prevRoll
    I.prevRoll = { rolling = rolling, speed = speed, vx = vx, vy = vy }
    if not (prev and prev.rolling and prev.speed > 300 and speed < 0.4 * prev.speed) then return end
    local fx, fy = prev.vx / prev.speed, prev.vy / prev.speed
    local dist = prev.speed * 2 / 60 + 48
    local start = Vector(C.drawPos)
    start.z = start.z + ((C.info and C.info.center) or 20)
    local tr = util.TraceHull({ start = start, endpos = start + Vector(fx, fy, 0) * dist, mins = Vector(-8, -8, -8),
                                maxs = Vector(8, 8, 8), filter = { LocalPlayer(), C.ent }, mask = MASK_SOLID })
    if tr and tr.Hit and IsValid(tr.Entity) and I.Pushable(tr.Entity) then
        local p = tr.HitPos
        add_report(tr.Entity:EntIndex(), fx, fy, 0, p.x, p.y, p.z, prev.speed, true, K.CONTACT_SIDE, true)
    end
end

function I.ContactsThink(C)
    local list = gsa1.Contacts(C.id, I.cbuf)
    local s = I.settings or I.Settings()
    if not (s.interact and s.prop.push) or cv.push_strength:GetFloat() <= 0 then
        I.prevRoll = nil
        return
    end
    local st = I.st
    local rolling = st.ball == true or (C.kind == 0 and (st.mode == 4 or st.mode == 5 or st.mode == 6))
    for i = 1, list.count or 0 do
        local k = list[i]
        if k.side > 0 or k.head > 0 then
            local e = Entity(k.ent)
            if I.Pushable(e) then
                local dx, dy, dz = I.PushDirection(k.type, k.nx, k.ny, k.nz)
                if dx then
                    add_report(k.ent, dx, dy, dz, k.px, k.py, k.pz, k.vin, rolling, k.type, k.first > 0)
                end
            end
        end
    end
    I.RollImpact(C, rolling)
    if #reports == 0 then return end
    I.stats.pushes = I.stats.pushes + #reports
    if I.ServerOk() then
        net.Start(I.NET.PUSH, true)
        net.WriteUInt(#reports, 4)
        for _, r in ipairs(reports) do
            net.WriteUInt(r.idx, 16)
            net.WriteNormal(Vector(r.dx, r.dy, r.dz))
            net.WriteVector(Vector(r.px, r.py, r.pz))
            net.WriteFloat(r.vin)
            net.WriteBool(r.rolling)
            net.WriteUInt(r.typ, 2)
            net.WriteBool(r.first)
        end
        net.WriteFloat(cv.push_strength:GetFloat())
        net.WriteFloat(cv.push_roll:GetFloat())
        net.SendToServer()
        I.stats.pushes_sent = I.stats.pushes_sent + #reports
    end
    reports = {}
end

-- the interact key (owner addition B) ------------------------------------------------------------------------------------
local binding_code, binding_until = nil, 0
function I.KeyCode()
    local k = cv.key and cv.key:GetInt() or 0
    if k > 0 then return k end
    local now = SysTime()
    if now >= binding_until then
        binding_until = now + 1
        binding_code = nil
        local name = input and input.LookupBinding and input.LookupBinding("+use", true)
        if name and input.GetKeyCode then
            local c = input.GetKeyCode(name)
            if c and c > 0 then binding_code = c end
        end
    end
    return binding_code
end

function I.KeyName()
    local code = I.KeyCode()
    if not code then return "no key (bind +use, or choose one on the Interaction page)" end
    local name = input and input.GetKeyName and input.GetKeyName(code)
    return string.upper(tostring(name or code))
end

-- the game's action button for a moment (cl_character.lua asks GSA1.ExtraButtons before each tick)
function I.PressAction()
    I.actionUntil = SysTime() + ACTION_TIME
end

function GSA1.ExtraButtons(C)
    if I.actionUntil and SysTime() < I.actionUntil then return BTN_ACTION end
    return 0
end

local function facing(C)
    local y = math.rad(C.state.yaw or C.drawYaw or 0)
    return math.cos(y), math.sin(y)
end

-- a liftable prop the game can take now (registered as HOLDABLE, in reach and in front)
function I.HoldableAhead(C)
    local fx, fy = facing(C)
    for idx, o in pairs(I.objects) do
        if o.kind == K.HOLDABLE and IsValid(o.ent) then
            local mn, mx = o.ent:OBBMins(), o.ent:OBBMaxs()
            local r = math.max(mx.x - mn.x, mx.y - mn.y) / 2
            if I.HoldableInFront(C.drawPos, fx, fy, o.ent:WorldSpaceCenter(), r) then return idx end
        end
    end
    return nil
end

function I.Press(C)
    I.stats.presses = I.stats.presses + 1
    local s = I.settings or I.Settings()
    if cv.key_lift:GetBool() and s.hold and s.interact then
        if (I.st.held_object or 0) ~= 0 then
            I.PressAction()
            I.lastPress = "the action button (put down or throw)"
            return
        end
        if I.HoldableAhead(C) then
            I.PressAction()
            I.lastPress = "the action button (lift)"
            return
        end
    end
    if not I.ServerOk() then
        I.lastPress = "nothing (the server has no G-SA1 interaction)"
        return
    end
    net.Start(I.NET.USE)
    net.WriteBool(true)
    net.WriteVector(Vector(C.drawPos))
    net.WriteFloat(C.state.yaw or 0)
    net.WriteFloat((C.info and C.info.center) or 20)
    net.WriteBool(cv.key_vehicles:GetBool())
    net.SendToServer()
    I.useHeld = true
    I.lastPress = "use"
end

function I.Release(C)
    if I.useHeld and I.ServerOk() then
        net.Start(I.NET.USE)
        net.WriteBool(false)
        net.SendToServer()
    end
    I.useHeld = false
end

concommand.Add("+gsa1_interact", function() I.cmdDown = true end, nil,
    "G-SA1: the interact key (bind any key to it: use doors, buttons and vehicles; lift props)")
concommand.Add("-gsa1_interact", function() I.cmdDown = false end)

function I.KeyThink(C)
    -- with "Interaction with the world" off, E is the engine's +use again (PlayerBindPress lets it through): the
    -- character must not use the same thing a second time
    if not cv.interact:GetBool() then
        I.keyDown, I.liftDown = false, false
        return
    end
    local ply = LocalPlayer()
    local busy = vgui.CursorVisible() or gui.IsGameUIVisible() or (ply.IsTyping ~= nil and ply:IsTyping())
    local code = I.KeyCode()
    local down = I.cmdDown == true or (code ~= nil and not busy and input.IsButtonDown(code)) or false
    if down and not I.keyDown then
        I.Press(C)
    elseif not down and I.keyDown then
        I.Release(C)
    end
    I.keyDown = down
    -- the optional lift key: the game's action button for a moment
    local lift = cv.lift_key and cv.lift_key:GetInt() or 0
    local ldown = lift > 0 and not busy and input.IsButtonDown(lift) or false
    if ldown and not I.liftDown then
        I.PressAction()
        I.lastPress = "the lift key (the action button)"
    end
    I.liftDown = ldown
end

-- E as a character: the engine's +use is not wanted (the character uses things, not the invisible player)
hook.Add("PlayerBindPress", "gsa1_interact", function(ply, bind, pressed)
    if not GSA1.Char or not cv.interact:GetBool() then return end
    if (cv.key:GetInt() or 0) == 0 and string.find(string.lower(bind or ""), "+use", 1, true) then return true end
end)

-- the character's options and settings ---------------------------------------------------------------------------------
function I.ApplyOptions(C)
    if not C or not I.HasModule() then return end
    gsa1.SetCharOption(C.id, K.COPT_NO_DEATH, cv.can_die:GetBool() and 0 or 1)
    gsa1.SetCharOption(C.id, K.COPT_KEEP_RINGS, cv.lose_rings:GetBool() and 0 or 1)
    gsa1.ObjConfig(math.Clamp(cv.window:GetInt(), 16, 64))
end

for _, name in ipairs({ "gsa1_can_die", "gsa1_lose_rings", "gsa1_obj_window" }) do
    cvars.AddChangeCallback(name, function() I.ApplyOptions(GSA1.Char) end, "gsa1_interact")
end
local rescan = { "gsa1_interact", "gsa1_prop_push", "gsa1_hold", "gsa1_balloon", "gsa1_balloon_launch",
                 "gsa1_balloon_speed", "gsa1_balloon_touch", "gsa1_solid_npcs" }
for _, c in ipairs(I.CATEGORIES) do
    for _, part in ipairs({ "_attack", "_target", "_touch" }) do rescan[#rescan + 1] = "gsa1_" .. c.id .. part end
end
for _, name in ipairs(rescan) do
    cvars.AddChangeCallback(name, function() I.nextScan = 0 end, "gsa1_interact")
end

-- the frame ---------------------------------------------------------------------------------------------------------------
function I.Think()
    local C = GSA1.Char
    local now = SysTime()
    if not C or not GSA1.mod then
        if I.held then
            clear_render(I.held.ent)
            send_hold(I.held.idx, false, IsValid(I.held.ent) and I.held.ent:WorldSpaceCenter() or Vector(), Vector(), 0)
            I.held = nil
        end
        I.charId = nil
        I.keyDown = false
        if next(I.objects) and now >= (I.noCharSince or now) + CLEAR_AFTER then I.ClearAll() end
        I.noCharSince = I.noCharSince or now
        return
    end
    I.noCharSince = nil
    if not I.HasModule() then return end
    check_constants()
    if C.id ~= I.charId then
        if I.held then
            clear_render(I.held.ent)
            send_hold(I.held.idx, false, IsValid(I.held.ent) and I.held.ent:WorldSpaceCenter() or Vector(), Vector(), 0)
            I.held = nil
        end
        I.charId = C.id
        I.wasDead = false
        I.prevRoll = nil
        I.ApplyOptions(C)
        I.nextScan = 0
    end
    gsa1.StateEx(C.id, I.st)
    if now >= I.nextScan then
        I.nextScan = now + SCAN_INTERVAL
        I.Scan(C, now)
    end
    if now >= I.nextMove then
        I.nextMove = now + MOVE_INTERVAL
        I.MoveAll()
    end
    I.PollEvents(C)
    I.ContactsThink(C)
    -- the held prop lost (a forced release the event queue did not deliver)
    if I.held and (I.st.held_object or 0) == 0 and now > (I.held.since or 0) + 1 then
        clear_render(I.held.ent)
        send_hold(I.held.idx, false, IsValid(I.held.ent) and I.held.ent:WorldSpaceCenter() or Vector(), Vector(), 0)
        I.held = nil
    end
    -- the character's death (gsa1_sv_kill_on_death: the player dies with it, and comes back when the character respawns)
    local dead = I.st.dead == true
    if dead and not I.wasDead and I.svcv.kill_on_death:GetBool() and I.ServerOk() then
        net.Start(I.NET.DEAD)
        net.SendToServer()
        I.playerDied = now
    end
    I.wasDead = dead
    -- a kill of the player that came during the character's first game pair: applied once that pair has run
    -- (a re-creation in between: the new character takes it)
    local pk = I.pendingKill
    if pk then
        local blocked = I.HitBlocked(C)
        if blocked ~= "new" or now >= pk.untilT then
            I.pendingKill = nil
            if blocked ~= "dead" then I.KillCharacter(C, pk.d) end
        end
    end
    -- the player is dead but the character lives on (a re-creation in between, a kill the game did not take): once,
    -- 1.5 s after the death, the player is asked back (the server waits for the gamemode's own delay)
    local lp = LocalPlayer()
    if I.playerDied and not I.pendingKill and now - I.playerDied > 1.5 and IsValid(lp) and lp.Alive ~= nil and
        not lp:Alive() and I.HitBlocked(C) == nil then
        I.AskRespawn(C, "the player is dead and the character lives")
    end
    if I.playerDied and now - I.playerDied > 30 then I.playerDied = nil end
    I.KeyThink(C)
    -- the session log: what the interaction did, every 30 s when something happened
    if now >= (I.nextLog or 0) then
        I.nextLog = now + 30
        local s = I.stats
        local key = string.format("%d %d %d %d %d %d", s.hits, s.pushes_sent, s.lifts, s.presses, s.hurts, s.denied)
        if key ~= I.lastLogKey then
            I.lastLogKey = key
            local lines = I.StatusLines()
            log("interact", "%s; %s", lines[1] or "", lines[2] or "")
        end
    end
end
hook.Add("Think", "gsa1_interact", guard("interact", I.Think))

-- the shortest-arc blend of two yaws (degrees)
function I.LerpYaw(a, b, t)
    local d = math.NormalizeAngle(b - a)
    return a + d * t
end

-- the held prop drawn at the character's hands, every frame (interpolated like the character).
-- 0.9.3a (sadc docs/research/super_general_design.md 6.7 / D13, the owner's 0.9.2 note "Moving while carrying objects
-- causes the object to jitter"): the body is drawn between the DRAWN steps of the last two pairs (sa1_character_render),
-- but 0.9.3 interpolated the prop between the last pair's two steps (position_prev -> position): a 7-15 HU sawtooth at
-- 30 Hz while running (res-game measured it). With a module that returns the drawn steps (ObjHeld's values 13-20, the
-- interact feature 2) the prop is interpolated drawn_prev -> drawn and its yaw along the shortest arc, with the body's
-- alpha; otherwise as 0.9.3.
function I.DrawHeld()
    local h, C = I.held, GSA1.Char
    if not h or not C or not IsValid(h.ent) or not GSA1.mod or not gsa1.ObjHeld then return end
    local ent, phase, x, y, z, px, py, pz, yaw, hx, hy, hz, dx, dy, dz, dpx, dpy, dpz, dyaw, dpyaw = gsa1.ObjHeld(C.id)
    if not ent or ent ~= h.idx then return end
    local a = (C.interp == false) and 1 or math.Clamp(C.alpha or 1, 0, 1)
    local cx, cy, cz
    if dx ~= nil and dpx ~= nil and dyaw ~= nil and dpyaw ~= nil then
        cx, cy, cz = dpx + (dx - dpx) * a, dpy + (dy - dpy) * a, dpz + (dz - dpz) * a
        yaw = I.LerpYaw(dpyaw, dyaw, a)
        I.heldDrawn = true
    else
        cx, cy, cz = px + (x - px) * a, py + (y - py) * a, pz + (z - pz) * a
        I.heldDrawn = false
    end
    local ang = Angle(h.ang.p, yaw + h.yaw_off, h.ang.r)
    h.yaw = yaw + h.yaw_off
    cx, cy, cz = I.ClearPose(C, h.ent, ang, cx, cy, cz, true)
    local off = h.ent:OBBCenter()
    off:Rotate(ang)
    h.ent:SetRenderOrigin(Vector(cx - off.x, cy - off.y, cz - off.z))
    h.ent:SetRenderAngles(ang)
    local now = SysTime()
    if now >= h.nextPose and I.ServerOk() then
        h.nextPose = now + POSE_INTERVAL
        net.Start(I.NET.HOLD_POSE, true)
        net.WriteUInt(h.idx, 16)
        net.WriteVector(Vector(cx, cy, cz))
        net.WriteFloat(yaw + h.yaw_off)
        net.SendToServer()
    end
end
hook.Add("PreRender", "gsa1_interact_held", guard("interact held", I.DrawHeld))

-- the server's messages ---------------------------------------------------------------------------------------------------
-- G7 (gsa1_090_player.md review R.4 G7, gsa1_090_faults.md 1.3): why a host hit cannot go to the character now - "dead"
-- (its death plays: the game's own, or one this file asked for), "new" (it has not run its first game pair: the
-- player's work does not exist before PInitialize, and a hit there faulted the respawned Sonic on gm_goldencity_v2) -
-- or nil
local st_probe = {}
function I.HitBlocked(C)
    if not C then return "gone" end
    if C.death or (C.killAsked and SysTime() - C.killAsked < I.KILL_TAKES) then return "dead" end
    if GSA1.mod and gsa1.StateEx then
        local s = gsa1.StateEx(C.id, st_probe)
        if s and s.dead then return "dead" end
    end
    if ((C.state and C.state.step) or 0) <= 0 then return "new" end
    return nil
end
local BLOCK_WORDS = { dead = "the character is dead", new = "the character has not started yet (its first game step)",
                      gone = "no character" }

net.Receive(I.NET.HURT, function()
    local amount = net.ReadFloat()
    local typ = net.ReadUInt(32)
    local src = net.ReadVector()
    local attacker = net.ReadUInt(16)
    local kill = net.ReadBool()
    local pvp = net.ReadBool()
    local cls = net.ReadString() or ""
    local C = GSA1.Char
    if not C or not I.HasModule() then return end
    local from = cls ~= "" and (" from " .. cls) or ""
    local blocked = I.HitBlocked(C)
    if blocked then
        I.stats.hurts_dropped = (I.stats.hurts_dropped or 0) + 1
        log("hurt", "the player took %.0f damage (type %d)%s%s: dropped, %s", amount, typ, from,
            kill and " (deadly)" or "", BLOCK_WORDS[blocked] or blocked)
        return
    end
    local flags = kill and K.DAMAGE_KILL or 0
    if cv.knockback:GetBool() or (pvp and I.svcv.pvp_knockback:GetBool()) then flags = flags + K.DAMAGE_FACE_SOURCE end
    gsa1.Damage(C.id, flags, src.x, src.y, src.z, attacker)
    I.stats.hurts = I.stats.hurts + 1
    log("hurt", "the player took %.0f damage (type %d)%s%s%s: the character is hit", amount, typ, from,
        pvp and " (another character)" or "", kill and " (deadly)" or "")
    I.lastHurt = { amount = amount, type = typ, pvp = pvp, class = cls, t = SysTime() }
end)

-- L6: the player died (a NextBot's Player:Kill, a script, a deadly hit in the health modes): the character dies too, the
-- game's way, and the player comes back with it when it respawns. The hook GSA1PlayerDied(C, class, how) (how: 0 a
-- deadly hit, 1 killed outright, 2 a silent kill; class: the attacker's, for a kill outright the NPC or NextBot next to
-- the player - the server's guess) is for the session log (cl_log.lua).
local HOW_WORDS = { [0] = "a deadly hit", [1] = "killed outright (Garry's Mod's Kill)", [2] = "a silent kill" }
I.KILL_WAIT = 1.0                -- s a kill waits for a new character's first game pair (then it is applied anyway)
I.KILL_TAKES = 3.0               -- s after a kill request without the game's death: it lives, the player is asked back

-- the request for the dead player to come back with the character (at the character, with the camera's view)
function I.AskRespawn(C, why)
    if not I.ServerOk() or not C then return end
    local ang = LocalPlayer():EyeAngles()
    net.Start(I.NET.RESPAWN)
    net.WriteVector(Vector(C.drawPos))
    net.WriteFloat(ang.y)
    net.WriteFloat(ang.p)
    net.WriteUInt(math.Clamp(C.kind or 0, 0, 15), 4)
    net.SendToServer()
    I.stats.respawn_asks = (I.stats.respawn_asks or 0) + 1
    I.playerDied = nil
    log("hurt", "the player is asked back with %s (%s)", C.title or "the character", why or "it respawned")
end

-- the kill itself (or, with "The character can die" off, a plain hit: the player comes back at once)
function I.KillCharacter(C, d)
    if not cv.can_die:GetBool() then
        gsa1.Damage(C.id, 0, C.drawPos.x, C.drawPos.y, C.drawPos.z, d.attacker or 0)
        log("hurt", "the player died (%s, %s): the character cannot die (Interaction page), so it is hit and the player "
            .. "comes back at once", d.class, HOW_WORDS[d.how] or tostring(d.how))
        I.AskRespawn(C, "the character cannot die")
        return
    end
    C.killAsked = SysTime()
    gsa1.Damage(C.id, K.DAMAGE_KILL, C.drawPos.x, C.drawPos.y, C.drawPos.z, d.attacker or 0)
    log("hurt", "the player died (%s, %s): the character is killed too", d.class, HOW_WORDS[d.how] or tostring(d.how))
end

function I.OnPlayerDied(d)
    I.stats.player_deaths = (I.stats.player_deaths or 0) + 1
    I.lastPlayerDeath = { class = d.class, how = d.how, t = SysTime() }
    local C = GSA1.Char
    if GSA1.RunHook then GSA1.RunHook("GSA1PlayerDied", C, d.class, d.how) end
    if not C then return end
    I.playerDied = SysTime()
    if not I.HasModule() then
        I.AskRespawn(C, "no interaction in the module")
        return
    end
    local blocked = I.HitBlocked(C)
    if blocked == "dead" then
        -- already dying (gsa1_sv_kill_on_death killed the player for it, or it died the same moment): it respawns by itself
        log("hurt", "the player died (%s, %s): the character is dead already", d.class, HOW_WORDS[d.how] or tostring(d.how))
        return
    end
    if blocked == "new" then
        I.pendingKill = { d = d, id = C.id, untilT = SysTime() + I.KILL_WAIT }
        return
    end
    I.KillCharacter(C, d)
end

net.Receive(I.NET.PLAYER_DIED, function()
    local cls = net.ReadString() or ""
    local how = net.ReadUInt(2)
    local attacker = net.ReadUInt(16)
    I.OnPlayerDied({ class = cls ~= "" and cls or "?", how = how, attacker = attacker })
end)

-- the character respawned (0.9.1's death handling, after the game's own restart request): a dead player comes back with it
hook.Add("GSA1CharacterRespawned", "gsa1_interact", guard("interact respawn", function(NC, reason, old)
    local ply = LocalPlayer()
    local dead = IsValid(ply) and ply.Alive ~= nil and not ply:Alive()
    if dead or (I.playerDied and SysTime() - I.playerDied < 30) then I.AskRespawn(NC, "the character respawned") end
    I.pendingKill = nil
end))

net.Receive(I.NET.KILL, function()
    local idx = net.ReadUInt(16)
    I.killed[idx] = SysTime() + 3
    if I.objects[idx] and I.HasModule() then I.Unregister(idx, true) end
end)

net.Receive(I.NET.REL, function()
    local n = net.ReadUInt(10)
    for _ = 1, n do
        local idx = net.ReadUInt(16)
        I.rel[idx] = net.ReadUInt(2)
    end
    I.nextScan = 0
end)

local function drop(idx)
    if I.held and I.held.idx == idx then
        clear_render(I.held.ent)
        I.held = nil
    end
    if I.HasModule() and I.objects[idx] then gsa1.ObjRelease(idx) end
end
net.Receive(I.NET.HOLD_DROP, function() drop(net.ReadUInt(16)) end)
net.Receive(I.NET.HOLD_DENY, function()
    I.stats.denied = I.stats.denied + 1
    drop(net.ReadUInt(16))
end)

local USE_WORDS = { [I.USE_NOTHING] = "nothing to use in front of the character", [I.USE_USED] = "used",
                    [I.USE_DENIED] = "not allowed", [I.USE_VEHICLE] = "a vehicle", [I.USE_OFF] = "off on this server" }
net.Receive(I.NET.USE_RESULT, function()
    local r = net.ReadUInt(3)
    local idx = net.ReadUInt(16)
    local e = idx > 0 and Entity(idx) or nil
    I.lastUse = { result = r, idx = idx, class = IsValid(e) and e:GetClass() or "", t = SysTime() }
    if r == I.USE_USED then I.stats.uses = I.stats.uses + 1 end
    log("interact", "the interact key: %s%s", USE_WORDS[r] or tostring(r),
        I.lastUse.class ~= "" and (" (" .. I.lastUse.class .. ")") or "")
    if GSA1.cv.debug:GetBool() then
        GSA1.Msg("interact: %s%s", USE_WORDS[r] or tostring(r), I.lastUse.class ~= "" and (" (" .. I.lastUse.class .. ")") or "")
    end
end)

-- a vehicle in front: the character steps out, the player gets in (and back into the character when leaving it)
net.Receive(I.NET.USE_VEHICLE, function()
    local idx = net.ReadUInt(16)
    local C = GSA1.Char
    if not C or not cv.key_vehicles:GetBool() then return end
    local kind = C.kind
    -- 0.9.3a (RC4): the list entry comes back, not only the kind (Super Sonic (General Gameplay) is kind 0); the server
    -- keeps the 4-bit kind
    I.vehicleName, I.vehicleKind = C.name, kind
    if GSA1.Remove then GSA1.Remove(true) end
    net.Start(I.NET.ENTER_VEHICLE)
    net.WriteUInt(idx, 16)
    net.WriteUInt(cv.vehicle_return:GetBool() and math.Clamp(kind, 0, 14) or 15, 4)
    net.SendToServer()
end)

net.Receive(I.NET.VEHICLE_LEFT, function()
    local kind = net.ReadUInt(4)
    if GSA1.Char or not GSA1.Spawn then return end
    local name = I.vehicleKind == kind and I.vehicleName or nil
    I.vehicleName, I.vehicleKind = nil, nil
    local def = name and GSA1.CharacterByName and GSA1.CharacterByName(name) or GSA1.CharacterByKind(kind)
    if def then GSA1.Spawn(def.name) end
end)

hook.Add("EntityRemoved", "gsa1_interact", function(e)
    local idx = e:EntIndex()
    if idx and idx > 0 and I.objects[idx] then
        if I.held and I.held.idx == idx then I.held = nil end
        I.Unregister(idx, false)
    end
end)

-- the shapes the game sees (gsa1_obj_debug) ---------------------------------------------------------------------------------
local CAT_COLOR = { hostile = Color(255, 60, 60), neutral = Color(255, 200, 60), friendly = Color(60, 255, 60),
                    vehicle = Color(60, 160, 255), player = Color(255, 60, 255), breakable = Color(200, 140, 80),
                    holdable = Color(255, 255, 255), balloon = Color(255, 128, 200), hazard = Color(255, 120, 0) }
hook.Add("PostDrawTranslucentRenderables", "gsa1_interact_debug", function(depth, sky)
    if sky or not GSA1.Char or not cv.debug:GetBool() then return end
    for _, o in pairs(I.objects) do
        local e = o.ent
        if IsValid(e) then
            local col = CAT_COLOR[o.cat] or color_white
            if o.kind == K.BALLOON or o.kind == K.HAZARD then
                local mn, mx = e:OBBMins(), e:OBBMaxs()
                render.DrawWireframeSphere(e:WorldSpaceCenter(), math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) / 2, 8,
                    8, col, true)
            else
                render.DrawWireframeBox(e:GetPos(), e:GetAngles(), e:OBBMins(), e:OBBMaxs(), col, true)
            end
        end
    end
end)

-- status ------------------------------------------------------------------------------------------------------------------
function I.StatusLines()
    local out = {}
    if not I.HasModule() then
        out[1] = "interaction: needs G-SA1 module " .. I.NEEDS.module
        return out
    end
    local counts, total = {}, 0
    for _, o in pairs(I.objects) do
        counts[o.cat] = (counts[o.cat] or 0) + 1
        total = total + 1
    end
    local parts = {}
    for _, c in ipairs({ "hostile", "neutral", "friendly", "player", "vehicle", "breakable", "holdable", "balloon",
                         "hazard" }) do
        if counts[c] then parts[#parts + 1] = counts[c] .. " " .. c end
    end
    local C = GSA1.Char
    local inf = gsa1.ObjInfo(C and C.id or nil) or {}
    out[#out + 1] = string.format("objects: %d registered%s; %d near the character in the game%s", total,
        #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "", inf.proxies or 0,
        (inf.refused or 0) > 0 and string.format(", %d refused (the game's memory)", inf.refused) or "")
    local st = I.st
    out[#out + 1] = string.format("rings %d, score %d; hits %d (%d sent), pushes %d, lifts %d, interact presses %d "
        .. "(%d uses), hits taken %d%s%s%s", st.rings or 0, st.score or 0, I.stats.hits, I.stats.hits_sent,
        I.stats.pushes_sent, I.stats.lifts, I.stats.presses, I.stats.uses, I.stats.hurts,
        (I.stats.hurts_dropped or 0) > 0 and string.format(" (%d dropped: a dead or not yet started character)",
            I.stats.hurts_dropped) or "",
        (I.stats.player_deaths or 0) > 0 and string.format(", player deaths %d", I.stats.player_deaths) or "",
        I.ServerOk() and "" or "; the server has no G-SA1 interaction")
    out[#out + 1] = string.format("interact key: %s; last: %s", I.KeyName(),
        I.lastUse and ((USE_WORDS[I.lastUse.result] or "?") .. (I.lastUse.class ~= "" and (" " .. I.lastUse.class) or ""))
        or (I.lastPress or "-"))
    return out
end

concommand.Add("gsa1_interact_status", function()
    for _, l in ipairs(I.StatusLines()) do GSA1.Msg("%s", l) end
end, nil, "G-SA1: the interaction's state (objects, hits, pushes, the interact key)")

concommand.Add("gsa1_interact_damage_defaults", function()
    for a = 0, I.MAX_ATTACK do
        RunConsoleCommand("gsa1_sv_dmg_" .. I.ATTACKS[a].name, tostring(I.ATTACKS[a].dmg))
    end
    RunConsoleCommand("gsa1_sv_dmg_scale", "1")
end, nil, "G-SA1 (server): every attack's damage back to the defaults")

-- the page: Options > G-SA1 > Interaction ------------------------------------------------------------------------------------
local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[1], c[2]) end
    combo.OnSelect = function(_, _, _, data) RunConsoleCommand(cvname, tostring(data)) end
    local cvar = GetConVar(cvname)
    local v = cvar and cvar:GetString() or ""
    for _, c in ipairs(choices) do
        if tonumber(c[2]) == tonumber(v) then combo:SetValue(c[1]) end
    end
    return combo
end

function I.BuildPage(panel)
    panel:Help("Garry's Mod's world as Sonic Adventure's: NPCs, other players, vehicles, props, balloons and hazards "
        .. "near the character become the game's own enemies and objects, so the jump, the homing attack, punches, the "
        .. "hammer, E-102's lock-on and Big's lure hit them, touching enemies costs rings, and props can be pushed, "
        .. "lifted, carried and thrown.")
    panel:CheckBox("Interaction with the world", "gsa1_interact")
    panel:Help("Keys")
    panel:ControlHelp("Jump: jump (Space). Action - spin dash, punch, attack, and the game's lift / put down / throw: "
        .. "crouch, attack or attack2 (Ctrl / mouse buttons), B or X on a controller. Interact - doors, buttons, "
        .. "vehicles and other things a player uses with E: the key below. Mouse wheel: camera distance.")
    local keyline = panel:Help("Interact key: " .. I.KeyName())
    local binder = vgui.Create("DBinder", panel)
    if binder.SetConVar then binder:SetConVar("gsa1_interact_key") end
    binder:SetTall(28)
    panel:AddItem(binder)
    panel:Button("Interact with the +use key (E)", "gsa1_interact_key", "0")
    panel:ControlHelp("Or bind any key to +gsa1_interact. In front of the character: a door or button is used as a "
        .. "player's E uses it (the map's own rules: a door that only opens by a button stays shut); a vehicle: the "
        .. "character steps out and you drive.")
    panel:CheckBox("The interact key also lifts, puts down and throws props", "gsa1_interact_lift")
    panel:ControlHelp("As Garry's Mod's E picks props up: it presses the game's action button for the character, which "
        .. "lifts a prop in front of it and puts down or throws one it carries.")
    panel:Help("Lift / put down / throw key (optional; none = the action button and the interact key):")
    local lifter = vgui.Create("DBinder", panel)
    if lifter.SetConVar then lifter:SetConVar("gsa1_lift_key") end
    lifter:SetTall(28)
    panel:AddItem(lifter)
    panel:Button("No extra lift key", "gsa1_lift_key", "0")
    panel:ControlHelp("Jump and the action button follow your Garry's Mod keys (Options > Keyboard: jump, duck, attack, "
        .. "attack2) and, on a controller, the Controller page.")
    panel:CheckBox("The interact key enters vehicles (the character steps out)", "gsa1_interact_vehicles")
    panel:CheckBox("Leaving that vehicle makes me the character again", "gsa1_vehicle_return")
    keyline.Think = function(self)
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + 0.5
        self:SetText("Interact key: " .. I.KeyName())
    end
    panel:Help("Getting hit")
    panel:CheckBox("The character can die (a hit with no rings)", "gsa1_can_die")
    panel:CheckBox("Hits scatter rings", "gsa1_lose_rings")
    panel:CheckBox("Knocked back away from the attacker", "gsa1_knockback_from_source")
    panel:ControlHelp("Off: backwards along the character's facing, as in the game.")
    panel:Help("What the character does to each kind of target")
    panel:ControlHelp("Attack: its hits do Garry's Mod damage (the amounts are in the server section). Targeting: E-102's "
        .. "lock-on, and the homing attack with every other aimed move. Touch: touching it hurts the character.")
    for _, c in ipairs(I.CATEGORIES) do
        panel:Help(c.title)
        if c.attack then panel:CheckBox("Attack " .. string.lower(c.title), "gsa1_" .. c.id .. "_attack") end
        if c.target then choice_combo(panel, "Targeting", "gsa1_" .. c.id .. "_target", I.TARGET_CHOICES) end
        if c.touch then panel:CheckBox("Touching them hurts", "gsa1_" .. c.id .. "_touch") end
        if c.push then
            panel:CheckBox("Running, rolling and spin-dashing into them pushes them", "gsa1_prop_push")
            panel:NumSlider("Push strength", "gsa1_push_strength", 0, 4, 2)
            panel:NumSlider("Rolling pushes this many times harder", "gsa1_push_roll", 1, 4, 2)
            panel:ControlHelp("Heavier props move less; standing on a prop never shoves it.")
        end
    end
    panel:Help("Carrying")
    panel:CheckBox("Pick up props (the game's lift, carry, put down and throw)", "gsa1_hold")
    panel:ControlHelp("The props a player could pick up with E (the server's limits below): stand at one and press the "
        .. "action button (or the interact key); press it again to put it down, running to throw it. Big lifts the same "
        .. "props as the others.")
    panel:CheckBox("Keep carried props above the ground", "gsa1_hold_clear")
    panel:ControlHelp("The game holds a prop by its middle at the hands, so a prop taller than the hands (an oil drum, a "
        .. "crate) would reach into the floor: it is lifted clear of the floor instead, and put down on it. Off: as the "
        .. "game.")
    panel:CheckBox("Carry props taller than the hands over the head", "gsa1_hold_overhead")
    panel:ControlHelp("Off: lifted clear of the ground at the hands.")
    panel:Help("Balloons")
    panel:CheckBox("Balloons are targets: hitting one pops it and launches the character up", "gsa1_balloon")
    choice_combo(panel, "Launch", "gsa1_balloon_launch", { { "Like a spring (the game's pose)", "0" },
                                                           { "Like an enemy bounce (homing chains on)", "1" } })
    panel:NumSlider("Launch speed (0 = the game's spring)", "gsa1_balloon_speed", 0, 5000, 0)
    panel:CheckBox("Touching a balloon pops it too", "gsa1_balloon_touch")
    panel:Help("More")
    panel:CheckBox("NPCs are solid", "gsa1_solid_npcs")
    -- (0.9.4, sadc docs/research/gsa1_094_plan.md decision 11: not to be read like the Objects page's ring and box sliders)
    panel:NumSlider("NPCs and props the game sees at once", "gsa1_obj_window", 16, 64, 0)
    panel:CheckBox("Draw the shapes the game sees", "gsa1_obj_debug")
    if GSA1.Hud and GSA1.Hud.MenuControls then
        panel:Help("HUD")
        GSA1.Hud.MenuControls(panel)
    end
    panel:Help("Server (admins; in single player that is you)")
    panel:CheckBox("Characters damage NPCs, props and players", "gsa1_sv_damage")
    choice_combo(panel, "Damage a character's player takes", "gsa1_sv_damage_mode",
        { { "Rings (the game's rules; health untouched)", "0" }, { "Health (Garry's Mod's)", "1" }, { "Both", "2" } })
    panel:CheckBox("Characters can hit other players (PvP)", "gsa1_sv_pvp")
    panel:CheckBox("PvP hits knock the other character back", "gsa1_sv_pvp_knockback")
    panel:CheckBox("Characters can pick up props", "gsa1_sv_hold")
    panel:NumSlider("Heaviest prop to pick up (kg)", "gsa1_sv_hold_mass", 1, 250, 0)
    panel:NumSlider("Largest prop to pick up (units)", "gsa1_sv_hold_size", 16, 256, 0)
    panel:CheckBox("Characters can push props", "gsa1_sv_push")
    panel:NumSlider("Strongest push a player may ask for", "gsa1_sv_push_max", 0, 10, 1)
    panel:CheckBox("Attacks pop balloons", "gsa1_sv_balloon_pop")
    panel:CheckBox("Characters can use doors, buttons and the like", "gsa1_sv_interact")
    panel:CheckBox("Characters can enter vehicles", "gsa1_sv_interact_vehicles")
    panel:NumSlider("Interact reach (units)", "gsa1_sv_interact_reach", 32, 256, 0)
    panel:NumSlider("Smallest damage that hits a character", "gsa1_sv_min_damage", 0, 100, 0)
    panel:NumSlider("Damage that kills a character at once", "gsa1_sv_kill_damage", 1, 5000, 0)
    panel:CheckBox("The character's death kills the player", "gsa1_sv_kill_on_death")
    panel:CheckBox("A player killed while a character (a NextBot, a script) comes back with the character",
        "gsa1_sv_respawn_with_character")
    panel:ControlHelp("Such a kill also kills the character; when it respawns at its spawn point, the player comes back "
        .. "as the character. Off: the gamemode's own respawn.")
    panel:CheckBox("Bullets hit a character only where its body is", "gsa1_sv_hit_shape")
    panel:ControlHelp("The invisible player is a 72-unit person; off: a shot over the character's head still hits it.")
    panel:Help("Damage per attack (Garry's Mod damage of one hit)")
    panel:NumSlider("Scale (every attack)", "gsa1_sv_dmg_scale", 0, 10, 2)
    for a = 0, I.MAX_ATTACK do
        panel:NumSlider(I.ATTACKS[a].title, "gsa1_sv_dmg_" .. I.ATTACKS[a].name, 0, 500, 0)
    end
    panel:Button("Reset the damage to the defaults", "gsa1_interact_damage_defaults")
    panel:Help("Status")
    local status = panel:Help("...")
    local baseThink = status.Think
    status.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + 0.5
        self:SetText(table.concat(I.StatusLines(), "\n"))
    end
end

GSA1.AddMenuPage(250, "interact", "Interaction", I.BuildPage, I.NEEDS)
