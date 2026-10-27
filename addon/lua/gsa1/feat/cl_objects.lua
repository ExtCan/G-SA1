-- G-SA1 feature "objects", client part (round 0.9.4: spawnable Rings and Item Boxes; sadc docs/research/
-- gsa1_094_plan.md 6.5 tasks 4, 6, 8 with its Review R.1 / R.15; the rules: feat/sh_objects.lua, the server:
-- feat/sv_objects.lua, the module: src/module/bind_objects.cpp).
--
-- Every G-SA1 object entity on the map becomes a place in this client's character worlds (gsa1.SetAdd: the module hands
-- libsa1 the SET records, the game's own spawner makes the ring or box near the character): an entity that appears is
-- added (NetworkEntityCreated / OnEntityCreated, its Initialize, a scan every 2 s), one that goes is removed, a change of
-- its description (Count, Spacing, Radius, Contents) is applied at once, a move once the entity has been still for
-- 0.25 s or the server says a Physics Gun drop ended it (never every frame: every update re-makes the game's object, and a
-- ground box grows in again for 46 steps), and the shared state the server keeps (State, Broken, TakenBits) goes into
-- every world (gsa1.SetState: silent - no sound, no rings, no item). A new disc load forgets the module's objects
-- (gsa1.SetGeneration changes): they are all added again.
--
-- What this client's own character does - a ring taken, a box broken, a line's rings taken (libsa1's GONE / BROKEN /
-- USERBITS events of the local character's world) - goes to the server with the touch (where the character was, the cause,
-- the attacker, how long ago: gsa1_obj_ev); a ground box's GONE (not expected) is sent as BROKEN; events of other worlds
-- (followers, 0.9.6) are not sent. When the server refuses a report it sends the object's state back (gsa1_obj_st) and the
-- world gets the object again.
--
-- Also here: the item icon guard for every new character (gsa1.SetGameOption(GOPT_ITEM_ICON_LIMIT), the way
-- feat/cl_charopt.lua applies its options; review R.15), the window (gsa1.SetConfig from the two sliders), the character's
-- render bounds covering the objects it draws (the rings review 6.1 item 5: GMod would cull them with the character), the
-- outlines while editing (gsa1_base.lua's Draw), the debug line and range, a rate-limited session-log line per take, break
-- and refusal, the spawn-menu content type of the entities (ScriptedEntityType "gsa1_object": the Entities tab's own icon),
-- and the Objects page (Q menu > Options > G-SA1 > Objects: every setting, the server's for admins and the listen host).
--
-- 0.9.4b (sadc docs/research/objects2_plan.md 6.3 tasks 1, 5 with its review R.9 / R.17, section 7, 11.0 / 11.1):
--   * the window gets the range (gsa1_set_range, HU: the game's own per-type range of the object list; the module divides
--     by its 4 HU per unit, 1,600 = the game's 400) and the screen width (gsa1_set_view_wide: view_tan = tan of the half
--     width G-SA1 renders with, Source's hor+ rule tan(fov / 2) x (ScrW / ScrH) / (4 / 3) with CalcView's 4:3 fov, checked
--     once a second and sent again when it changes by more than 1 %) - with a module of feature "objects" 3;
--   * a saved 64 / 32 (0.9.4's window defaults) moves to 128 / 48 ONCE (a cookie, as cl_super.lua's voice move);
--   * the pictures of the real objects are feat/cl_objview.lua's: an entity draws them (gsa1_base.lua: ENT:Draw /
--     DrawTranslucent -> O.DrawEntity), the outlines stay the editing aid (O.MarkersOn: without a character only while
--     editing when pictures are shown, owner answer O7), and the local world's events and the server's refusals reach the
--     pictures (O.PollEvents, gsa1_obj_st) so a taken ring's picture goes at once;
--   * the context menu's hover outline (11.1): Garry's Mod's halo draws ent:DrawModel(), the hidden 12-HU cube at the
--     origin, not the line / circle / box; now the hovered object draws its whole outline itself (O.DrawHover, in a
--     colour that pulses like the sandbox's halo) and, inside halo.Render (halo.RenderedEntity() == the entity: when
--     DrawModel reaches the entity's Draw), a solid silhouette of the whole object (O.DrawHalo). UNVERIFIED in game;
--   * the spawn-menu icons of the content type gsa1_object are handed to feat/cl_objicons.lua (the rendered pictures);
--   * the Objects page: the Distance, Pictures and Spawn menu blocks of objects2_plan.md section 7.
GSA1 = GSA1 or {}
local O = GSA1.Objects
if not O then return end

local band, bor, bnot, lshift = bit.band, bit.bor, bit.bnot, bit.lshift
local cv = O.cv
GSA1.cv = GSA1.cv or {}
GSA1.cv.set_draw = cv.draw            -- cl_render.lua: OBJECT batches drawn by this switch (review R.1)

O.tracked = O.tracked or {}           -- [entity index] = rec
O.order = O.order or {}               -- the entity indices, for the round-robin check
O.unavailable = O.unavailable or {}   -- [type] = why (the module's ObjectInfo / SetAdd)
O.stats = O.stats or { adds = 0, updates = 0, states = 0, removes = 0, sent = 0, refused = 0, failed = 0, events = 0 }
O.CHECKS_PER_FRAME = 16              -- the round-robin look at an entity's place (a move without a Physics Gun drop)
O.STILL = 0.25                        -- s without motion before a moved entity's record follows it
O.SCAN_INTERVAL = 2.0

local function now_s() return SysTime() end

-- the module has the feature (and the disc is loaded: SetAdd says otherwise)
local function have()
    return GSA1.mod ~= nil and gsa1 ~= nil and gsa1.SetAdd ~= nil and
        (not GSA1.HasFeature or GSA1.HasFeature("objects", O.NEEDS.version))
end
O.Have = have

local function num(k, d)
    local t = gsa1 and gsa1.OBJECTS
    return type(t) == "table" and tonumber(t[k]) or d
end
O.Num = num

-- 0.9.4b: the module takes the range and the screen width (feature "objects" 3)
local function ranged()
    return have() and (not GSA1.HasFeature or GSA1.HasFeature("objects", O.RANGE_VERSION or 3))
end
O.Ranged = ranged

-- the range in use (HU): gsa1_set_range within the module's limits; the game's 1,600 when the module cannot set it
function O.RangeHU()
    if not ranged() or not cv.range then return O.RANGE_GAME end
    local hi = math.min(O.RANGE_MAX, num("RANGE_MAX_HU", O.RANGE_MAX))
    return math.Clamp(math.floor(cv.range:GetFloat() + 0.5), O.RANGE_GAME, math.max(O.RANGE_GAME, hi))
end

-- the horizontal half view G-SA1 renders with as tan(half angle), Source's hor+ rule from CalcView's 4:3 fov; 0 = the
-- game's 4:3 (gsa1_set_view_wide 0, or a screen not wider than 4:3)
function O.ViewTanNow()
    if not (cv.view_wide and cv.view_wide:GetBool()) then return 0 end
    local v = GSA1.view
    local fov = v and v.fov and v.frame and FrameNumber() - v.frame <= 2 and tonumber(v.fov) or nil
    if not fov then
        local f = GetConVar("fov_desired")
        fov = f and f:GetFloat() or 75
    end
    local w, h = ScrW(), ScrH()
    if not (w and h and w > 0 and h > 0 and fov > 1 and fov < 179) then return 0 end
    local t = math.tan(math.rad(fov / 2)) * (w / h) / (4 / 3)
    if t <= 0.7005 then return 0 end
    return math.Clamp(t, 0.700, num("VIEW_TAN_MAX", 4.0))
end

-- the value sent: looked at once a second (and at once when the switch changes), kept while it moves by 1 % or less
local vt_sent, vt_time, vt_wide = 0, nil, nil
function O.ViewTan(now)
    local wide = cv.view_wide and cv.view_wide:GetBool() or false
    if vt_time == nil or now - vt_time >= 1 or wide ~= vt_wide then
        vt_time, vt_wide = now, wide
        local t = O.ViewTanNow()
        if (t == 0) ~= (vt_sent == 0) or math.abs(t - vt_sent) > 0.01 * vt_sent then vt_sent = t end
    end
    return vt_sent
end

-- 0.9.4b: a saved 64 / 32 (0.9.4's window defaults) becomes 128 / 48 once (review R.9: the ConVars hold up to 200 / 100)
function O.MigrateWindows()
    if not (cookie and cookie.GetNumber and cookie.Set) or cookie.GetNumber("gsa1_set_windows_094b", 0) ~= 0 then
        return false
    end
    cookie.Set("gsa1_set_windows_094b", "1")
    local moved = false
    if cv.ring_window and cv.ring_window:GetInt() == 64 then
        RunConsoleCommand("gsa1_set_ring_window", tostring(O.RING_WINDOW_DEFAULT))
        moved = true
    end
    if cv.box_window and cv.box_window:GetInt() == 32 then
        RunConsoleCommand("gsa1_set_box_window", tostring(O.BOX_WINDOW_DEFAULT))
        moved = true
    end
    return moved
end

-- the session log, at most 6 lines a second (the rest counted and summed up)
local logwin = { t = 0, n = 0, skipped = 0 }
function O.Log(fmt, ...)
    if not GSA1.Log then return end
    local t = now_s()
    if t - logwin.t >= 1 then
        if logwin.skipped > 0 then GSA1.Log("objects", "(%d more object lines in the last second)", logwin.skipped) end
        logwin.t, logwin.n, logwin.skipped = t, 0, 0
    end
    logwin.n = logwin.n + 1
    if logwin.n > 6 then
        logwin.skipped = logwin.skipped + 1
        return
    end
    GSA1.Log("objects", fmt, ...)
end

-- an entity's place in the module: type, p1, p2, p3 (sh_objects.lua O.Describe; HU)
local function params(ent)
    local d = O.Describe(ent)
    if d.type == O.TYPE.O_GRING then return d, d.type, d.count, d.size, d.shape end
    if d.type == O.TYPE.ITEMBOX or d.type == O.TYPE.ITEMBOX_AIR then return d, d.type, d.contents, 0, 0 end
    return d, d.type, 0, 0, 0
end

-- the shared state word (SA1_SET_STATE_*) and the user bits per record
local function state_of(ent, d)
    local present = d.type == O.TYPE.O_GRING or d.type == O.TYPE.ITEMBOX or (tonumber(ent:GetState()) or 1) ~= 0
    local broken = d.type == O.TYPE.ITEMBOX and ent.GetBroken and ent:GetBroken() == true
    return (present and O.STATE_PRESENT or 0) + (broken and O.STATE_BROKEN or 0)
end

-- record k's bits (the entity's TakenBits, two hex digits per record: sh_objects.lua O.BitsGet)
local function bits_of(ent, k)
    return O.BitsOf(ent, k)
end

local function same_vec(a, b, tol)
    return a and b and math.abs(a.x - b.x) <= tol and math.abs(a.y - b.y) <= tol and math.abs(a.z - b.z) <= tol
end

local function same_ang(a, b, tol)
    return a and b and math.abs(math.NormalizeAngle(a.p - b.p)) <= tol and
        math.abs(math.NormalizeAngle(a.y - b.y)) <= tol and math.abs(math.NormalizeAngle(a.r - b.r)) <= tol
end

-- tracking -----------------------------------------------------------------------------------------------------------------
function O.Track(ent)
    if not O.IsObject(ent) or not IsValid(ent) then return end
    local idx = ent:EntIndex()
    if not idx or idx <= 0 then return end
    local rec = O.tracked[idx]
    if rec and rec.ent == ent then
        rec.dirty = true
        return rec
    end
    if rec then O.Untrack(idx) end
    rec = { ent = ent, idx = idx, dirty = true, bits = {} }
    O.tracked[idx] = rec
    O.order[#O.order + 1] = idx
    return rec
end

-- an entity (or its index) went: its records out of this client's worlds
function O.Untrack(e)
    local idx = type(e) == "number" and e or (e and e.EntIndex and e:EntIndex())
    local rec = idx and O.tracked[idx]
    if not rec then return end
    if type(e) ~= "number" and rec.ent ~= e then return end
    O.tracked[idx] = nil
    if rec.id and have() and gsa1.SetRemove then
        gsa1.SetRemove(rec.id)
        O.stats.removes = O.stats.removes + 1
    end
    for i = #O.order, 1, -1 do
        if O.order[i] == idx then table.remove(O.order, i) break end
    end
end

-- a NetworkVar of an object changed (gsa1_base.lua's NetworkVarNotify; called before the value is set: marked, applied in
-- the next frame)
function O.OnVarChanged(ent, name, old, new)
    local rec = ent and ent.EntIndex and O.tracked[ent:EntIndex()]
    if rec then rec.dirty = true elseif O.IsObject(ent) then O.Track(ent) end
end

-- the entity's own render bounds (its outline): the hull of its layout, a little wider; and the hull as its pick shape
-- here too (sh_objects.lua O.ApplyPickShape: the server's arrives with the next update)
function O.EntityBounds(ent, d)
    local mins, maxs = O.Hull(d or O.Describe(ent))
    O.ApplyPickShape(ent, mins, maxs)
    if not ent.SetRenderBounds then return end
    local r = Vector(16, 16, 16)
    ent:SetRenderBounds(mins - r, maxs + r)
end

function O.ClientInit(ent)
    O.EntityBounds(ent)
    O.Track(ent)
end

-- every object out of the module (gsa1_set 0); the records come back with gsa1_set 1
function O.ClearAll()
    if have() and gsa1.SetClear then gsa1.SetClear() end
    for _, rec in pairs(O.tracked) do
        rec.id, rec.gen, rec.dirty = nil, nil, true
    end
end

-- the entity's records added (true), or not yet (false: try later)
local function add(rec, now)
    local ent = rec.ent
    local d, t, p1, p2, p3 = params(ent)
    if not t then return false end
    if O.unavailable[t] then
        rec.unavailable = O.unavailable[t]
        ent.GSA1Unavailable = rec.unavailable
        return false
    end
    local st = state_of(ent, d)
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local id, err, code = gsa1.SetAdd(t, pos, ang, p1, p2, p3, rec.idx, st)
    if not id then
        rec.retry = now + (code == "not_ready" and 0.5 or 2.0)
        if code == "unsupported" then
            O.unavailable[t] = tostring(err)
            rec.unavailable, ent.GSA1Unavailable = tostring(err), tostring(err)
            O.SayUnavailable(t, err)
        elseif code ~= "not_ready" and rec.lastError ~= err then
            rec.lastError = err
            O.stats.failed = O.stats.failed + 1
            O.Log("%s %d could not be placed in the game: %s", ent.PrintName or "object", rec.idx, tostring(err))
        end
        return false
    end
    rec.id, rec.gen, rec.unavailable = id, O.gen, nil
    O.EntityBounds(ent, d)
    rec.pos, rec.ang, rec.t, rec.p1, rec.p2, rec.p3 = Vector(pos), Angle(ang), t, p1, p2, p3
    rec.nrec = O.RecordCount(d)
    rec.state, rec.moving, rec.moved = st, nil, ent.GetMoved and ent:GetMoved() or 0
    rec.bits = {}
    for k = 0, O.RecordCount(d) - 1 do
        local b = bits_of(ent, k)
        rec.bits[k] = b
        if b ~= 0 then gsa1.SetState(id, st, b, k) end
    end
    O.stats.adds = O.stats.adds + 1
    return true
end

-- the shared state differs from what the module has (numbers only: no garbage; also when a NetworkVar notification
-- did not come)
local function state_changed(rec, e)
    local t = rec.t
    local present = t == O.TYPE.O_GRING or t == O.TYPE.ITEMBOX or (tonumber(e:GetState()) or 1) ~= 0
    local broken = t == O.TYPE.ITEMBOX and e.GetBroken ~= nil and e:GetBroken() == true
    if (present and O.STATE_PRESENT or 0) + (broken and O.STATE_BROKEN or 0) ~= rec.state then return true end
    for k = 0, (rec.nrec or 1) - 1 do
        if bits_of(e, k) ~= (rec.bits[k] or 0) then return true end
    end
    return false
end

-- the entity's description, place and state against what the module has
local function check(rec, now)
    local ent = rec.ent
    if not IsValid(ent) then
        O.Untrack(rec.idx)
        return
    end
    if not rec.id or rec.gen ~= O.gen then
        if (rec.retry or 0) <= now then add(rec, now) end
        return
    end
    local d, t, p1, p2, p3 = params(ent)
    local described = t ~= rec.t or p1 ~= rec.p1 or p2 ~= rec.p2 or p3 ~= rec.p3
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local moved = ent.GetMoved and ent:GetMoved() or 0
    local update = described
    if not update and not (same_vec(pos, rec.pos, 0.05) and same_ang(ang, rec.ang, 0.05)) then
        -- it moves: follow it once it is still (or at once when the server says a Physics Gun drop ended the move)
        if moved ~= rec.moved then
            update = true
        elseif not rec.moving or not (same_vec(pos, rec.lastPos, 0.05) and same_ang(ang, rec.lastAng, 0.05)) then
            rec.moving, rec.lastPos, rec.lastAng = now, Vector(pos), Angle(ang)
        elseif now - rec.moving >= O.STILL then
            update = true
        end
    else
        rec.moving = nil
    end
    rec.moved = moved
    if update then
        local ok, err = gsa1.SetUpdate(rec.id, pos, ang, p1, p2, p3)
        if ok then
            if described then O.EntityBounds(ent, d) end
            rec.pos, rec.ang, rec.moving = Vector(pos), Angle(ang), nil
            rec.t, rec.p1, rec.p2, rec.p3 = t, p1, p2, p3
            rec.nrec = O.RecordCount(d)
            O.stats.updates = O.stats.updates + 1
        else
            rec.id = nil      -- added again (the module forgot it, or the description is new)
            rec.retry = now
            O.Log("%s %d: the update failed (%s); placed again", ent.PrintName or "object", rec.idx, tostring(err))
            return
        end
    end
    local st = state_of(ent, d)
    if st ~= rec.state then
        gsa1.SetState(rec.id, st)
        rec.state = st
        O.stats.states = O.stats.states + 1
    end
    for k = 0, O.RecordCount(d) - 1 do
        local b = bits_of(ent, k)
        if b ~= (rec.bits[k] or 0) then
            gsa1.SetState(rec.id, st, b, k)
            rec.bits[k] = b
            O.stats.states = O.stats.states + 1
        end
    end
    if rec.moving then O.movingSet[rec.idx] = true end
end
O.Check = check
O.movingSet = O.movingSet or {}

local rr = 1
local next_scan, cfg_rings, cfg_boxes, cfg_gen, cfg_range, cfg_vt = 0, nil, nil, nil, nil, nil
local cfg = {}
-- once per frame: the module's generation, the entities to add / update, the window, the events
function O.Sync(now)
    now = now or now_s()
    if not have() then return end
    if not cv.on:GetBool() then
        if O.cleared ~= true then
            O.ClearAll()
            O.cleared = true
        end
        return
    end
    O.cleared = false
    if gsa1.IsReady and not gsa1.IsReady() then return end      -- (no disc yet: nothing to add, no message strings)
    local gen = gsa1.SetGeneration and gsa1.SetGeneration() or 1
    if gen ~= O.gen then
        O.gen = gen
        for _, rec in pairs(O.tracked) do
            rec.id, rec.dirty = nil, true
        end
        cfg_gen = nil
        O.Availability()
    end
    -- the window (the two sliders), 0.9.4b the range and the screen width
    local rw, bw = cv.ring_window:GetInt(), cv.box_window:GetInt()
    O.RANGE = O.RangeHU()
    local range, vt = O.RANGE, 0
    if ranged() then vt = O.ViewTan(now) end
    if gsa1.SetConfig and (rw ~= cfg_rings or bw ~= cfg_boxes or cfg_gen ~= O.gen or range ~= cfg_range or vt ~= cfg_vt) then
        cfg.ring_window = math.Clamp(rw, 1, num("RING_WINDOW_MAX", O.RING_WINDOW_MAX))
        cfg.box_window = math.Clamp(bw, 1, num("BOX_WINDOW_MAX", O.BOX_WINDOW_MAX))
        if ranged() then
            cfg.range = range > O.RANGE_GAME and range or 0         -- (0: the game's 400 units, 0.9.4's list exactly)
            cfg.view_tan = vt
        else
            cfg.range, cfg.view_tan = nil, nil
        end
        local ok, err = gsa1.SetConfig(cfg)
        if ok then
            cfg_rings, cfg_boxes, cfg_gen, cfg_range, cfg_vt = rw, bw, O.gen, range, vt
        elseif O.cfgError ~= tostring(err) then
            O.cfgError = tostring(err)
            O.Log("the window could not be set: %s", tostring(err))
        end
    end
    -- entities the hooks missed
    if now >= next_scan then
        next_scan = now + O.SCAN_INTERVAL
        if ents and ents.FindByClass then
            for _, e in ipairs(ents.FindByClass("gsa1_obj_*")) do
                if O.IsObject(e) and not O.tracked[e:EntIndex()] then O.Track(e) end
            end
        end
    end
    -- the changed and the moving ones every frame (a NetworkVar notification, not added yet, still moving) ...
    for idx, rec in pairs(O.tracked) do
        if rec.dirty or not rec.id or O.movingSet[idx] then
            rec.dirty = false
            O.movingSet[idx] = nil
            check(rec, now)
        end
    end
    local n = #O.order
    -- ... and the others' places a few per frame (a SetPos without a Physics Gun drop: a tool, another addon); their
    -- descriptions and states come with the NetworkVar notifications above
    for _ = 1, math.min(O.CHECKS_PER_FRAME, n) do
        if rr > #O.order then rr = 1 end
        local idx = O.order[rr]
        rr = rr + 1
        local rec = idx and O.tracked[idx]
        local e = rec and rec.ent
        if rec and rec.id and IsValid(e) then
            if state_changed(rec, e) or not (same_vec(e:GetPos(), rec.pos, 0.05) and same_ang(e:GetAngles(), rec.ang, 0.05))
            then
                check(rec, now)
            end
        elseif rec then
            check(rec, now)
        end
    end
end

-- which types this module runs (ObjectInfo.available); the others are not offered in the spawn menu
function O.Availability()
    if not (have() and gsa1.ObjectInfo) then return end
    local info = gsa1.ObjectInfo()
    if type(info) ~= "table" then return end
    for t = 1, tonumber(info.count) or 0 do
        local e = info[t]
        if type(e) == "table" and e.available == false then
            O.unavailable[t] = O.unavailable[t] or "its game code is not in this G-SA1 module"
        end
    end
    if list and list.GetForEdit then
        local sp = list.GetForEdit("SpawnableEntities")
        for _, c in ipairs(O.CLASSES) do
            if O.unavailable[c.type] and type(sp) == "table" then sp[c.class] = nil end
        end
    end
end

local said = {}
function O.SayUnavailable(t, why)
    if said[t] then return end
    said[t] = true
    local title = "this object"
    for _, c in ipairs(O.CLASSES) do
        if c.type == t then title = c.title break end
    end
    if GSA1.Chat then GSA1.Chat("%s cannot run with this G-SA1 module: %s", title, tostring(why)) end
    O.Log("%s cannot run with this module: %s", title, tostring(why))
end

-- the events of this client's worlds ---------------------------------------------------------------------------------------
local evbuf = {}
local KIND_NAME = { [3] = "taken", [4] = "rings taken", [7] = "broken" }

local function server_ok()
    return util.NetworkStringToID and util.NetworkStringToID(O.NET.EV) ~= 0
end

-- one libsa1 event of the local character's world -> the server (true when sent)
function O.SendEvent(C, e)
    if not C or e.character ~= C.id then return false end    -- another world (a follower's, 0.9.6)
    local kind, EV = e.kind, O.EV
    if kind == EV.GONE and e.type == O.TYPE.ITEMBOX then kind = EV.BROKEN end   -- (a ground box ends as its base)
    if kind ~= EV.GONE and kind ~= EV.BROKEN and kind ~= EV.USERBITS then return false end
    local idx = tonumber(e.user) or 0
    local rec = O.tracked[idx]
    if not rec or rec.id ~= e.id or not IsValid(rec.ent) then return false end
    if not cv.on:GetBool() then return false end
    local step = (C.state and tonumber(C.state.step)) or tonumber(e.step) or 0
    local from = (tonumber(e.touch_step) or 0) > 0 and e.touch_step or e.step
    local age = math.Clamp((step - (tonumber(from) or step)) / 60, 0, O.MAX_AGE)
    local cause = math.Clamp(math.floor(tonumber(e.cause) or 0), 0, 3)
    O.Log("%s: %s %d %s (record %d, bits %02X, cause %s, %.2f s ago, condition %04X)", C.title or "?",
        rec.ent.PrintName or "object", idx, KIND_NAME[kind] or tostring(kind), tonumber(e.index) or 0,
        tonumber(e.bits) or 0, O.CAUSE_NAME[cause] or "?", age, tonumber(e.condition) or 0)
    if not server_ok() then return false end
    net.Start(O.NET.EV)
    net.WriteUInt(idx, 16)
    net.WriteUInt(math.Clamp(tonumber(e.index) or 0, 0, 255), 8)      -- (0.9.4.1: up to 127 records)
    net.WriteUInt(kind, 3)
    net.WriteUInt(band(tonumber(e.bits) or 0, 0xFF), 8)
    net.WriteFloat(age)
    net.WriteVector(Vector(e.x or 0, e.y or 0, e.z or 0))
    net.WriteUInt(cause, 2)
    net.WriteVector(Vector(e.ax or 0, e.ay or 0, e.az or 0))
    net.SendToServer()
    O.stats.sent = O.stats.sent + 1
    return true
end

-- every event since the last call (the local character's go to the server)
function O.PollEvents(C)
    if not (have() and gsa1.SetEvents) then return 0 end
    local t = gsa1.SetEvents(evbuf)
    local n = type(t) == "table" and (tonumber(t.count) or 0) or 0
    local V = GSA1.ObjView
    for i = 1, n do
        local e = t[i]
        if type(e) == "table" then
            O.stats.events = O.stats.events + 1
            if V and V.OnEvent and C and e.character == C.id then V.OnEvent(e) end   -- (the picture goes at once)
            O.SendEvent(C, e)
        end
    end
    return n
end

-- the server refused a report (or restores an object): its state into this client's worlds again
net.Receive(O.NET.ST, function()
    local idx = net.ReadUInt(16)
    local state = net.ReadUInt(2)
    local broken = net.ReadBool()
    local nrec = net.ReadUInt(8)
    local taken = net.ReadString()
    local bits = {}
    for k = 0, nrec - 1 do bits[k] = O.BitsGet(taken, k) end
    local why = net.ReadString()
    local rec = O.tracked[idx]
    O.stats.refused = O.stats.refused + 1
    if GSA1.ObjView and GSA1.ObjView.OnRefused then GSA1.ObjView.OnRefused(idx) end
    O.Log("the server refused %s %d: %s", rec and IsValid(rec.ent) and rec.ent.PrintName or "object", idx,
        why ~= "" and why or "no reason given")
    if not (rec and rec.id and have()) then return end
    local st = (state ~= 0 and O.STATE_PRESENT or 0) + (broken and O.STATE_BROKEN or 0)
    gsa1.SetState(rec.id, st)
    rec.state = st
    for k = 0, nrec - 1 do
        gsa1.SetState(rec.id, st, bits[k], k)
        rec.bits[k] = bits[k]
    end
end)

-- every new character: the item icon guard (review R.15) ------------------------------------------------------------------
function O.ApplyIconGuard(C, on)
    if not C or not C.id or not have() or not gsa1.SetGameOption then return false end
    if on == nil then on = cv.icon_guard:GetBool() end
    local ok, err = gsa1.SetGameOption(C.id, num("GOPT_ITEM_ICON_LIMIT", O.GOPT_ITEM_ICON_LIMIT), on and 1 or 0)
    if not ok then
        O.Log("%s: the item icon guard could not be set: %s", C.title or "?", tostring(err))
        return false
    end
    C.iconGuard = on and true or false
    return true
end

hook.Add("GSA1CharacterCreated", "gsa1_objects", function(C, how, old)
    if not C then return end
    O.ApplyIconGuard(C)
end)

cvars.AddChangeCallback("gsa1_set_icon_guard", function(_, _, new)
    if GSA1.Char then O.ApplyIconGuard(GSA1.Char, tonumber(new) ~= 0) end
    O.Log("the item icon guard %s", tonumber(new) ~= 0 and "on" or "off (the game's own list)")
end, "gsa1_objects")
cvars.AddChangeCallback("gsa1_set", function(_, _, new)
    O.Log("rings and item boxes in your game: %s", tonumber(new) ~= 0 and "on" or "off")
end, "gsa1_objects")

-- the character's render bounds cover the objects it draws (GMod culls the render entity by them) -----------------------
local DEF_MIN, DEF_MAX = Vector(-640, -640, -320), Vector(640, 640, 640)    -- cl_render.lua's
function O.UpdateBounds(C)
    if not (C and IsValid(C.ent) and C.ent.SetRenderBounds and have() and gsa1.ObjectBounds) then return end
    local x0, y0, z0, x1, y1, z1 = gsa1.ObjectBounds(C.id)
    if not x0 then
        if C.objBounds then
            C.ent:SetRenderBounds(DEF_MIN, DEF_MAX)
            C.objBounds = nil
        end
        return
    end
    local p = C.drawPos or C.ent:GetPos()
    local mn = Vector(math.min(DEF_MIN.x, x0 - p.x - 16), math.min(DEF_MIN.y, y0 - p.y - 16), math.min(DEF_MIN.z, z0 - p.z - 16))
    local mx = Vector(math.max(DEF_MAX.x, x1 - p.x + 16), math.max(DEF_MAX.y, y1 - p.y + 16), math.max(DEF_MAX.z, z1 - p.z + 16))
    C.ent:SetRenderBounds(mn, mx)
    C.objBounds = { mn, mx }
end

-- after each tick: the events at once (their age counts in game steps), the bounds
hook.Add("GSA1PostTick", "gsa1_objects", function(C, st, dt)
    if not have() then return end
    O.PollEvents(C)
    O.UpdateBounds(C)
end)

-- once per frame: the entities into the module (also without a character: the records are ready when one comes)
hook.Add("Think", "gsa1_objects", function()
    if not have() then return end
    local ok, err = pcall(O.Sync, now_s())
    if not ok and not O.syncError then
        O.syncError = true
        O.Log("error: %s", tostring(err))
        ErrorNoHalt("[G-SA1] objects: " .. tostring(err) .. "\n")
    end
    if not GSA1.Char then O.PollEvents(nil) end      -- nothing to send; the queue drained
end)

hook.Add("NetworkEntityCreated", "gsa1_objects", function(ent)
    if O.IsObject(ent) then O.Track(ent) end
end)
hook.Add("OnEntityCreated", "gsa1_objects", function(ent)
    if O.IsObject(ent) then O.Track(ent) end
end)
hook.Add("EntityRemoved", "gsa1_objects", function(ent)
    if O.IsObject(ent) then O.Untrack(ent) end
end)

-- the outlines while editing --------------------------------------------------------------------------------------------
local EDIT_WEAPONS = { weapon_physgun = true, gmod_tool = true }
local mframe, mon = -1, false
function O.MarkersOn()
    local fn = FrameNumber()
    if fn == mframe then return mon end
    mframe = fn
    mon = false
    if cv.markers and not cv.markers:GetBool() then return false end
    -- 0.9.4b: without a character the outlines show while the real objects' pictures are not shown (no module feature,
    -- no disc, gsa1_set_view 0), else - as with a character - only while editing (owner answer O7: on top of the pictures)
    local V = GSA1.ObjView
    if not GSA1.Char and not (V and V.PlainActive and V.PlainActive()) then
        mon = true
        return true
    end
    mon = O.Editing()
    return mon
end

-- the local player holds the Physics Gun or the Tool Gun
function O.Editing()
    local ply = LocalPlayer()
    local w = IsValid(ply) and ply.GetActiveWeapon and ply:GetActiveWeapon()
    return IsValid(w) and EDIT_WEAPONS[w:GetClass()] == true or false
end

local COL_RING, COL_BOX, COL_OFF, COL_BAD = Color(255, 210, 40), Color(80, 170, 255), Color(140, 140, 140), Color(255, 60, 60)
local COL_HOVER = Color(255, 255, 255)
-- force: drawn whatever O.MarkersOn says (the hover outline), in colour col
function O.DrawMarker(ent, force, col)
    if not force and not O.MarkersOn() then return end
    local d = O.Describe(ent)
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local bad = ent.GSA1Unavailable ~= nil
    if d.type == O.TYPE.RING or d.type == O.TYPE.O_GRING then
        local taken = d.type == O.TYPE.RING and (tonumber(ent:GetState()) or 1) == 0
        for _, r in ipairs(O.RingPositions(d, pos, ang)) do
            local off = taken or band(bits_of(ent, r.record), r.bit) ~= 0
            render.DrawWireframeSphere(r.pos, 12, 8, 6, col or (bad and COL_BAD or (off and COL_OFF or COL_RING)), true)
        end
    else
        local mins, maxs = O.Hull(d)
        local off = (d.type == O.TYPE.ITEMBOX and ent:GetBroken()) or (d.type == O.TYPE.ITEMBOX_AIR and
            (tonumber(ent:GetState()) or 1) == 0)
        render.DrawWireframeBox(pos, d.type == O.TYPE.ITEMBOX and Angle(0, ang.y, 0) or ang, mins, maxs,
            col or (bad and COL_BAD or (off and COL_OFF or COL_BOX)), true)
    end
end

-- 0.9.4b, the context menu's hover (11.1): the object under the context menu's cursor (properties.GetHovered, the way
-- the sandbox's PropertiesHover finds it), looked up in PreDrawHalos - the frame's entity draws come first, so the
-- outline follows one frame later
O.hover = O.hover or { ent = nil, frame = -1 }
function O.FindHover()
    O.hover.ent = nil
    if not (vgui and vgui.GetHoveredPanel and properties and properties.GetHovered) then return nil end
    local p = vgui.GetHoveredPanel()
    if not (IsValid(p) and p.IsWorldClicker and p:IsWorldClicker()) then return nil end
    local ply = LocalPlayer()
    if not (IsValid(ply) and ply.GetAimVector) then return nil end
    local eye = (MainEyePos and MainEyePos()) or EyePos()
    local ok, ent = pcall(properties.GetHovered, eye, ply:GetAimVector())
    if ok and O.IsObject(ent) then
        O.hover.ent, O.hover.frame = ent, FrameNumber()
    end
    return O.hover.ent
end
if hook and hook.Add then
    hook.Add("PreDrawHalos", "gsa1_objects_hover", function() O.FindHover() end)
end

-- the hovered object's whole outline, its colour pulsing like the sandbox's halo
function O.DrawHover(ent)
    if O.hover.ent ~= ent or FrameNumber() - (O.hover.frame or -9) > 2 then return false end
    local p = 200 + math.sin(RealTime() * 50) * 55
    COL_HOVER.r, COL_HOVER.g, COL_HOVER.b = p, p, 255
    O.DrawMarker(ent, true, COL_HOVER)
    return true
end

-- inside halo.Render (halo.RenderedEntity() == ent): a solid silhouette of the whole object, so the halo's stencil holds
-- the line / circle / box and not the hidden cube (only if Garry's Mod's DrawModel reaches the entity's Draw: UNVERIFIED)
local COL_SOLID = Color(255, 255, 255, 255)
function O.DrawHalo(ent)
    if not (render.SetColorMaterial and render.DrawSphere and render.DrawBox) then return false end
    local d = O.Describe(ent)
    local pos, ang = ent:GetPos(), ent:GetAngles()
    render.SetColorMaterial()
    if d.type == O.TYPE.RING or d.type == O.TYPE.O_GRING then
        for _, r in ipairs(O.RingPositions(d, pos, ang)) do
            render.DrawSphere(r.pos, 13, 8, 6, COL_SOLID)
        end
    else
        local mins, maxs = O.Hull(d)
        render.DrawBox(pos, d.type == O.TYPE.ITEMBOX and Angle(0, ang.y, 0) or ang, mins, maxs, COL_SOLID)
    end
    return true
end

-- an object entity's drawing (gsa1_base.lua ENT:Draw pass 0, ENT:DrawTranslucent pass 1; flags: the STUDIO flags): the
-- halo's silhouette, else the real object's picture (feat/cl_objview.lua) and the outlines in the translucent pass (also
-- while the picture is not ready yet)
function O.DrawEntity(ent, pass, flags)
    if halo and halo.RenderedEntity and halo.RenderedEntity() == ent then
        if O.haloDrawn ~= ent or O.haloFrame ~= FrameNumber() then
            O.haloDrawn, O.haloFrame = ent, FrameNumber()
            O.DrawHalo(ent)
        end
        return
    end
    local V = GSA1.ObjView
    local drew = V and V.DrawEntity and V.DrawEntity(ent, pass, flags)
    if pass == 1 then
        -- a picture not ready yet (a new copy's first pair): its outline meanwhile
        O.DrawMarker(ent, drew == "pending")
        O.DrawHover(ent)
    end
end

-- the debug line and range (gsa1_set_debug) --------------------------------------------------------------------------------
function O.StatusLine()
    local n, placed, missing = 0, 0, 0
    for _, rec in pairs(O.tracked) do
        n = n + 1
        if rec.id then placed = placed + 1 elseif rec.unavailable then missing = missing + 1 end
    end
    local gen, objs, recs = 0, 0, 0
    if have() and gsa1.SetGeneration then gen, objs, recs = gsa1.SetGeneration() end
    local s = O.stats
    return string.format("objects: %d on the map, %d in your game (%s module objects, %s records), %d cannot run; events "
        .. "%d, reports sent %d, refused %d; window: %d rings, %d boxes; added %d, updated %d, states %d, removed %d",
        n, placed, tostring(objs), tostring(recs), missing, s.events, s.sent, s.refused, cv.ring_window:GetInt(),
        cv.box_window:GetInt(), s.adds, s.updates, s.states, s.removes)
end

-- 0.9.4b: the range, the windows and the screen width ("range 4,800 HU (1,200 game units), windows 128 / 48, screen width
-- +-61.9 degrees")
local function thousands(n)
    local s = tostring(math.floor(n + 0.5))
    while true do
        local t, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        s = t
        if k == 0 then return s end
    end
end
function O.RangeLine()
    local range = O.RangeHU()
    local vt = ranged() and O.ViewTanNow() or 0
    local width = vt > 0 and string.format("+-%.1f degrees (your screen)", math.deg(math.atan(vt))) or
        "+-35.0 degrees (the game's 4:3)"
    return string.format("range %s HU (%s game units)%s, windows %d / %d, screen width %s", thousands(range),
        thousands(range / 4), ranged() and "" or " - this module cannot change it", math.min(cv.ring_window:GetInt(),
        num("RING_WINDOW_MAX", O.RING_WINDOW_MAX)), math.min(cv.box_window:GetInt(), num("BOX_WINDOW_MAX", O.BOX_WINDOW_MAX)),
        width)
end

hook.Add("HUDPaint", "gsa1_objects_debug", function()
    if not cv.debug:GetBool() or not GSA1.Char then return end
    draw.SimpleText(O.StatusLine(), "DermaDefault", 16, ScrH() - 60, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end)
hook.Add("PostDrawTranslucentRenderables", "gsa1_objects_debug", function(depth, sky)
    if depth or sky or not cv.debug:GetBool() then return end
    local C = GSA1.Char
    if not C or not C.drawPos then return end
    render.DrawWireframeSphere(C.drawPos, O.RANGE, 24, 16, Color(80, 255, 120), true)
end)

-- the Entities tab's content type (ScriptedEntityType "gsa1_object", v1_arch review R.1): the entity icon of the sandbox,
-- looked up when the icon is made (the gamemode registers "entity" after the addons' autorun)
local function add_content_type()
    if not (spawnmenu and spawnmenu.AddContentType) then return end
    spawnmenu.AddContentType("gsa1_object", function(container, obj)
        local f = spawnmenu.GetContentType and spawnmenu.GetContentType("entity")
        if not f then return end
        local icon = f(container, obj)
        -- 0.9.4b: the rendered picture of the real object (feat/cl_objicons.lua), now or when it is made
        local I = GSA1.ObjIcons
        if icon and I and I.Decorate then I.Decorate(icon, obj and obj.spawnname) end
        return icon
    end)
end
add_content_type()
hook.Add("OnGamemodeLoaded", "gsa1_objects", add_content_type)

-- the Objects page ---------------------------------------------------------------------------------------------------------
local function contents_combo(panel)
    local combo = panel:ComboBox("Contents of a new item box")
    for _, c in ipairs(O.CONTENTS) do combo:AddChoice(c.title, tostring(c.value)) end
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand("gsa1_set_box_content", tostring(data))
    end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local c = GetConVar("gsa1_set_box_content")
        local v = c and c:GetString() or ""
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        for _, ch in ipairs(O.CONTENTS) do
            if tonumber(v) == ch.value then
                self:SetText(ch.title)
                return
            end
        end
        self:SetText(v)
    end
    return combo
end

function O.Page(panel)
    panel:Help("Rings and item boxes you place from Q menu > Entities > G-SA1: a Ring, a Ring line, a Ring circle, an Item "
        .. "Box and an Item Box (Air). Your character's own Sonic Adventure code collects and breaks them, so the sounds, "
        .. "the sparkle, the ring counter, the items and their pictures are the game's. In multiplayer they are shared: a "
        .. "ring one player takes, or a box one breaks, is gone (or broken) for everyone.")
    panel:CheckBox("Rings and item boxes in your game", "gsa1_set")
    panel:ControlHelp("Off: the G-SA1 objects on the map are left out of your character's game (nothing is taken or "
        .. "broken by you).")
    panel:CheckBox("Draw rings and item boxes (also in first person, whatever 'Effects' says)", "gsa1_set_draw")
    panel:ControlHelp("Off: they still work, but you do not see them.")
    -- 0.9.4b: Distance (objects2_plan.md section 7; owner answer O1: up to the game's far plane)
    local rmax = math.min(O.RANGE_MAX, num("RANGE_MAX_HU", O.RANGE_MAX))
    local ringmax = math.min(O.RING_WINDOW_MAX, num("RING_WINDOW_MAX", O.RING_WINDOW_MAX))
    local boxmax = math.min(O.BOX_WINDOW_MAX, num("BOX_WINDOW_MAX", O.BOX_WINDOW_MAX))
    panel:Help("Distance")
    panel:NumSlider("How far away your character's game runs rings and item boxes (HU)", "gsa1_set_range", O.RANGE_GAME,
        math.max(O.RANGE_GAME, rmax), 0)
    panel:ControlHelp("The Dreamcast makes rings and boxes only within 1,600 of these units (400 of its own). Farther "
        .. "means more of them running in your game and more to draw: with many rings on screen this costs frame rate, "
        .. "and the very large values (up to 12,000, the game's own far plane) cost the most. For reference, the game "
        .. "itself uses 6,000 for Ice Cap's floating boxes and 8,000 in Twinkle Circuit. Collecting still needs your "
        .. "character there.")
    panel:CheckBox("Rings and boxes use your whole screen width", "gsa1_set_view_wide")
    panel:ControlHelp("The game decides what it draws for a 4:3 screen, so on a wide screen rings appear only in the "
        .. "middle and pop in at the sides as you turn. On: rings and boxes use your screen's width. Only their drawing "
        .. "changes.")
    panel:NumSlider("Rings the game handles at once", "gsa1_set_ring_window", 16, ringmax, 0)
    panel:ControlHelp("The rings around you (each ring of a line or circle counts): the nearest first, then those in "
        .. "front of you. Raise it if far rings still appear late. Above " .. ringmax .. " the game's own collision list "
        .. "would start dropping rings you run through.")
    panel:NumSlider("Item boxes the game handles at once", "gsa1_set_box_window", 4, boxmax, 0)
    panel:ControlHelp("The same for item boxes; above " .. boxmax .. " the game's collision list would start dropping "
        .. "boxes.")
    -- Pictures (the real objects from your disc: feat/cl_objview.lua)
    panel:Help("Pictures")
    panel:CheckBox("Show the real rings and item boxes when you have no character", "gsa1_set_view")
    panel:ControlHelp("Pictures made by the game's own code from your disc: rings spin, boxes show their item, a broken "
        .. "box its base. Nothing can be collected without a character. Off: outlines. (An Extra Life box shows the "
        .. "Dreamcast logo when you have no character.)")
    panel:CheckBox("... and while you build with the Physics Gun or Tool Gun, the ones your character's game is not "
        .. "running", "gsa1_set_view_edit")
    panel:ControlHelp("With a character, objects your game is not running yet (far away) are shown while you hold the "
        .. "Physics Gun or the Tool Gun.")
    panel:CheckBox("While playing, show far rings and item boxes as pictures", "gsa1_set_view_far")
    panel:ControlHelp("Beyond the distance above, rings and boxes are shown as pictures; they become the real ones as you "
        .. "get close (a ring's spin may jump a little then).")
    panel:NumSlider("How far away the pictures are drawn (HU)", "gsa1_set_view_dist", O.VIEW_DIST_MIN, O.VIEW_DIST_MAX, 0)
    panel:ControlHelp("Pictures cost little in the game, but each one is drawn by Garry's Mod: lower it if many objects "
        .. "cost frame rate.")
    panel:CheckBox("Smooth the pictures", "gsa1_set_view_smooth")
    panel:ControlHelp("Off: the pictures turn at the game's own 30 steps a second, like the Dreamcast (the real rings "
        .. "near you are always smooth). On: smoothed to your frame rate (costs a little more).")
    -- Spawn menu (feat/cl_objicons.lua)
    panel:Help("Spawn menu")
    panel:CheckBox("Spawn-menu pictures of the real objects", "gsa1_set_icons")
    panel:ControlHelp("Drawn from your disc when G-SA1 starts. Off: G-SA1's own drawings.")
    panel:CheckBox("Keep the pictures in garrysmod/data/gsa1/icons", "gsa1_set_icons_save")
    panel:ControlHelp("So they show at once next time. They stay on your computer; G-SA1 never uploads or shares them. "
        .. "Off: made every session.")
    panel:Button("Redraw the spawn-menu pictures", "gsa1_icons_rebuild")
    panel:Help("Item boxes")
    contents_combo(panel)
    panel:ControlHelp("What a new box holds when you place it (change a placed box with right-click > Contents).")
    panel:CheckBox("Keep the game's item icon list safe", "gsa1_set_icon_guard")
    panel:ControlHelp("The game keeps at most 20 item pictures on screen and breaks its own memory with more: breaking "
        .. "more than 20 boxes within about 2 seconds could crash the game. On: the 21st picture is skipped - you still "
        .. "get every item.")
    panel:Help("Editing")
    panel:CheckBox("Show outlines while you hold the Physics Gun or Tool Gun", "gsa1_set_markers")
    panel:ControlHelp("An outline of each object (a line's or circle's every ring, a box's size) while you hold the Physics "
        .. "Gun or the Tool Gun, on top of the real objects; without a character also whenever their pictures are not "
        .. "shown.")
    panel:CheckBox("Show the objects' range and records", "gsa1_set_debug")
    panel:Help("Server (the server's host or an admin)")
    panel:CheckBox("G-SA1 objects on this server", "gsa1_sv_set")
    panel:NumSlider("Respawn new objects after (s, 0 = never)", "gsa1_sv_set_respawn", 0, 600, 0)
    panel:ControlHelp("Not the game's own rule (it never brings them back): a taken ring or broken box comes back after "
        .. "this long. Each object has its own \"Respawn after\" (Edit Properties); this is what new ones get.")
    panel:NumSlider("Allowed distance slack (HU)", "gsa1_sv_set_reach_slack", 0, 1024, 0)
    panel:ControlHelp("How far a report may be from where the server saw the character then (network lag).")
    panel:NumSlider("Most G-SA1 objects per player", "sbox_maxgsa1_objects", 0, 5000, 0)
    panel:Button("Reset G-SA1 objects", "gsa1_sv_set_reset")
    panel:ControlHelp("Every taken ring and broken box back at once (admins and the server's host).")
    panel:Help("Known limits: rings and boxes appear within the distance above (the game's own way) and, if you like, "
        .. "as pictures beyond it. They can still disappear high above or behind the game's camera, and in first person "
        .. "(fixed with the host camera in 0.9.5).")
    panel:Help("Status")
    local function status(lbl, fn)
        local baseThink = lbl.Think
        lbl.Think = function(self)
            if baseThink then baseThink(self) end
            if RealTime() < (self.gsa1Next or 0) then return end
            self.gsa1Next = RealTime() + 0.5
            local ok, text = pcall(fn)
            text = ok and tostring(text) or "?"
            if text ~= self.gsa1Text then
                self.gsa1Text = text
                self:SetText(text)
            end
        end
    end
    status(panel:Help("..."), function()
        return have() and O.StatusLine() or "objects: the G-SA1 module is not loaded"
    end)
    status(panel:Help("..."), function() return O.RangeLine() end)
    status(panel:Help("..."), function()
        local V = GSA1.ObjView
        return V and V.StatusLine and V.StatusLine() or "pictures: not loaded"
    end)
    status(panel:Help("..."), function()
        local I = GSA1.ObjIcons
        return I and I.StatusLine and I.StatusLine() or "spawn-menu pictures: not loaded"
    end)
end

if GSA1.AddMenuPage then
    GSA1.AddMenuPage(250, "objects", "Objects", O.Page, O.NEEDS)
end

-- 0.9.4b: the window defaults' one-time move (64 / 32 -> 128 / 48)
O.MigrateWindows()
