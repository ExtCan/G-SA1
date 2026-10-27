-- G-SA1 feature "objects", client: the PICTURES of the real objects (round 0.9.4b; sadc docs/research/objects2_plan.md 6.3
-- task 3 with its Review R.5 / R.6 / R.8 / R.10 / R.17 / R.18, owner answers 11.0; objects2_view.md 5.3 / 5.6).
--
-- The owner's notes on 0.9.4: "only bounding boxes can be seen when not in Sonic Adventure mode" and "big pop-in with the
-- spawnables". The game's own rings and item boxes run only inside a character's world; libsa1 now also runs one live copy
-- of each DESCRIPTION (a ring; an item box per contents, intact or broken; an air box per contents) in a private world of a
-- character kind with no player in it (the module's feature "preview": src/core/preview.*, bind_preview.cpp), and returns
-- its draws in object space. This file draws those copies at the objects' places:
--   * WHAT (per record of an entity, the records gsa1.SetAdd gives libsa1 - 0.9.4.1's lines of 8, circles split and turned
--     per record - never re-derived in Lua, review R.5): a Ring, and every ring of a Ring line / circle, is the ONE ring
--     description of the kind drawn at its place (gsa1.PreviewRingPlaces: the module splits the entity's description into
--     its records and runs the game's own layout; a ring of the game's group is a RING with angle 0, so its picture is
--     that ring; a placed Ring's yaw is only its spin's start and is ignored), skipping the rings taken in their record;
--     an Item Box its contents (broken: the broken description), upright; an Item Box (Air) its contents under the
--     record's rotation (the entity's angles turned a quarter about up, objects.cpp record_matrix); a taken Ring or air box
--     nothing. Copies are shared per description and removed 3 s after the last use.
--   * WHEN: the module has the features "objects" and "preview" and the disc is loaded; the server's state, unless this
--     client's own world took the object a moment ago (its GONE / BROKEN / USERBITS hides or updates the picture at once;
--     the server's refusal brings it back); within gsa1_set_view_dist of the eye; and
--       (a) no character: gsa1_set_view 1;
--       (b) a character (review R.6 / R.10 / R.17): gsa1_set and gsa1_set_draw 1; the record is not in the character
--           world's running set (gsa1.SetLive once a pair - never rebuilt from the events), except that an INTACT box keeps
--           its picture for its type's settle steps after it appears there (ground 47, air 23: libsa1's measurement) while
--           the live box grows in inside it; gsa1_set_view_far 1, or the Physics Gun / Tool Gun held with
--           gsa1_set_view_edit 1; and while playing (not editing) a record inside the game's range (O.RANGE) for more than
--           V.RANGE_GRACE is never a picture: a full budget left it out, a picture there could not be taken. (The plan's
--           "O.RANGE + the margin" would leave a band of the margin's 400 HU between the game's range and the pictures
--           with nothing drawn: the window reaches range + margin, the spawner only the range - deliberate deviation.)
--   * HOW (review R.8): once per game pair (gsa1_set_view_smooth 0, owner answer O6: the game's 30 steps a second) each
--     description in use is rendered (gsa1.PreviewRender alpha 1, gsa1.PreviewPrepareView with the eye in object space)
--     and each of its batches built into one static IMesh shared by every instance (cl_render.lua's static-mesh pattern,
--     GSA1.StaticMesh); with gsa1_set_view_smooth 1 every frame from libsa1's accumulator. The drawing is each object
--     entity's own ENT:Draw (opaque batches) / DrawTranslucent (blended batches, the game's blend factors) - Source's PVS,
--     frustum, translucent sorting and views apply and the 3D skybox never draws them; depth views draw the opaque batches
--     with cl_textures.lua's DepthWrite material. Per instance cam.PushModelMatrix(translation [, the air box's rotation]);
--     the lighting of the ENTITY (its ambient cube sampled when it is placed or moved, refreshed for 8 entities a frame,
--     round robin). A description with sphere-mapped, sprite or line batches drawn under a rotation (a turned air box) is
--     prepared and streamed per instance. Materials: cl_textures.lua's of the pictures' kind; made when the description's
--     first batches come, not at its first draw.
--   * KIND: the local character's kind; without one the Character page's choice (gsa1_character); kinds without a showcase
--     (both Super Sonics, Tikal, Eggman) use Sonic's; a change re-makes the copies.
--   * THE DREAMCAST LOGO (owner answer O4): without a character the Extra Life box's panel shows the Dreamcast logo instead
--     of a face. There is no such texture on the disc (094b-lib-preview searched all 849 archives), so it is DRAWN here at
--     run time - an orange (#D9441A) clockwise spiral on transparent, into a render target - never a shipped image. The
--     panel batch is found by its texture: the kind's Extra Life panel (V.PANEL, libsa1's measurement, checked by
--     feat_preview_binding_test). A character's own world, and his far pictures, keep his face (the game's).
--   * A NOT_FOUND (a disc reload) re-adds; a fault: one log line, the outlines until gsa1.PreviewClear and a re-add work (at
--     most once a minute). Without the module's features or the disc: the outlines only (feat/cl_objects.lua).
-- UNVERIFIED in game: the pictures' look under this Garry's Mod's lighting, their frame cost with hundreds of entities
-- (owner checklist), the logo's place on the panel (the panel's UVs are assumed to span its texture).
GSA1 = GSA1 or {}
local O = GSA1.Objects
if not O then return end
local V = GSA1.ObjView or {}
GSA1.ObjView = V

local band, bor, lshift = bit.band, bit.bor, bit.lshift
local cv = O.cv

V.RETIRE = 3                 -- s: a description no picture used is removed this long after its last use
V.TICK_AFTER = 3             -- s: gsa1.PreviewTick runs this long after the last copy went (libsa1 frees an empty
                             -- showcase 60 pairs later: review R.18)
V.LIGHT_PER_FRAME = 8        -- entities whose ambient cube is sampled per frame (round robin; review R.8)
V.RETRY_FAULT = 60           -- s between attempts after a showcase fault
V.PENDING_MAX = 3            -- s: a local take hides the picture until the server's state says so, at most this long
V.RANGE_GRACE = 0.1          -- s: a record inside the game's range that its world does not run for this long gets no picture
V.KIND_TITLE = { [0] = "Sonic", [2] = "Tails", [3] = "Knuckles", [5] = "Amy", [6] = "E-102", [7] = "Big" }
-- the Extra Life panel's texture (archive, texture) per kind (libsa1's measurement: Sonic 2:31, Tails 1:4, Knuckles 2:0,
-- Amy 2:1, E-102 5:3, Big 3:2); the kinds with a showcase are exactly these
V.PANEL = { [0] = { 2, 31 }, [2] = { 1, 4 }, [3] = { 2, 0 }, [5] = { 2, 1 }, [6] = { 5, 3 }, [7] = { 3, 2 } }
V.EXTRA_LIFE = 6             -- the contents "Extra Life (1UP)"
V.SETTLE = { [3] = 47, [4] = 23 }   -- libsa1's settle steps (gsa1.PreviewTypes wins)
V.LOGO_COLOR = { 217, 68, 26 }      -- #D9441A (the owner's reference: the look only; nothing of it is shipped)
V.LOGO_SIZE = 128

local DRAW_ENV = 0x8
local PRIMS_FACING = 2 + 4   -- bit (1 << SA1_PRIM_SPRITES) | (1 << SA1_PRIM_LINES): they face the camera
local B_ONE, B_ZERO, B_ONE_MINUS_SRC_ALPHA = BLEND_ONE or 1, BLEND_ZERO or 0, BLEND_ONE_MINUS_SRC_ALPHA or 5
local F_ADD = BLENDFUNC_ADD or 0
local QUARTER = Angle(0, 90, 0)       -- the record's rotation: the entity's angles x a quarter turn about up
local NONE = {}                       -- (an empty table that is never written)

V.descs = V.descs or {}      -- [key] = description entry D (the copy, its batches, materials and static meshes)
V.ents = V.ents or {}        -- [entity index] = E (the entity's layout and this frame's pictures)
V.pending = V.pending or {}  -- [entity index] = this client's own take of it, waiting for the server's state
V.places = V.places or {}    -- [layout key] = the ring places of a ring group (gsa1.PreviewRingPlaces)
V.stats = V.stats or { adds = 0, removes = 0, refreshed = 0, built = 0, failures = 0, faults = 0, drawn = 0, ents = 0 }
V.frame = V.frame or { n = -1, instances = 0, ents = 0 }

local function now_s() return SysTime() end

local function log(fmt, ...)
    if O.Log then O.Log(fmt, ...) end
end

-- the module can draw previews (and has the disc)
function V.Have()
    return GSA1.mod ~= nil and gsa1 ~= nil and gsa1.PreviewAdd ~= nil and gsa1.PreviewRender ~= nil and
        (not GSA1.HasFeature or GSA1.HasFeature("preview", 1))
end

function V.Ready()
    return V.Have() and O.Have ~= nil and O.Have() and (not gsa1.IsReady or gsa1.IsReady()) and V.working ~= false
end

-- a player without a character sees the pictures (feat/cl_objects.lua O.MarkersOn: the outlines only while editing)
function V.PlainActive()
    return GSA1.Char == nil and cv.view ~= nil and cv.view:GetBool() and V.Ready()
end

-- the kind of the pictures: the character's, else the Character page's; a kind without a showcase -> Sonic
function V.ShowcaseKind(kind)
    kind = tonumber(kind)
    if kind and V.PANEL[kind] then return kind end
    return 0
end

function V.KindNow()
    local C = GSA1.Char
    if C and C.kind ~= nil then return V.ShowcaseKind(C.kind) end
    local c = GSA1.cv and GSA1.cv.character
    local name = c and c.GetString and c:GetString() or "sonic"
    local k = GSA1.KindByName and GSA1.KindByName(name)
    return V.ShowcaseKind(k)
end

-- the settle steps of a type (gsa1.PreviewTypes, once)
function V.Settle(t)
    if not V.types and gsa1.PreviewTypes then
        local ok, ty = pcall(gsa1.PreviewTypes)
        V.types = ok and type(ty) == "table" and ty or false
    end
    local e = V.types and V.types[t]
    return e and tonumber(e.settle) or V.SETTLE[t] or 0
end

-- descriptions ----------------------------------------------------------------------------------------------------------
-- t: SA1_OBJTYPE_*; p1: the contents of a box (0 for a ring); state: 1 present, 3 present and broken
function V.Need(t, p1, state)
    p1, state = p1 or 0, state or 1
    local key = t .. ":" .. p1 .. ":" .. state
    local D = V.descs[key]
    if not D then
        D = { key = key, type = t, p1 = p1, state = state, gen = -1, batches = { count = 0 }, mats = {}, logoMats = {},
              meshes = {}, used = now_s(), born = now_s() }
        V.descs[key] = D
    end
    D.used = V.now or now_s()
    return D
end

local function free_meshes(D)
    for i, im in pairs(D.meshes) do
        if im and im.Destroy then im:Destroy() end
        D.meshes[i] = nil
    end
end

local function drop(D, call)
    free_meshes(D)
    if call and D.id and gsa1.PreviewRemove then gsa1.PreviewRemove(D.id) end
    if D.id then
        V.stats.removes = V.stats.removes + 1
        V.lastGone = now_s()
    end
    D.id, D.ready, D.built = nil, false, false
    D.batches.count = 0
end

-- every copy out (a kind change, a fault, the pictures off); call: tell the module
function V.ClearCopies(why, call)
    local n = 0
    for k, D in pairs(V.descs) do
        if D.id then n = n + 1 end
        drop(D, false)
        V.descs[k] = nil
    end
    if call ~= false and gsa1 and gsa1.PreviewClear and n > 0 then gsa1.PreviewClear() end
    V.places = {}
    if n > 0 and why then log("pictures: %d kinds of object cleared (%s)", n, why) end
end

local addDesc = { kind = 0, type = 1, params = { 0, 0, 0 }, state = 1, user_bits = 0 }
local function add_copy(D, now)
    if (D.retry or 0) > now then return false end
    addDesc.kind, addDesc.type, addDesc.state = V.kind or 0, D.type, D.state
    addDesc.params[1] = D.p1
    local id, err, code = gsa1.PreviewAdd(addDesc)
    if id then
        D.id, D.gen, D.ready, D.built, D.err = id, -1, false, false, nil
        D.batches.count = 0
        V.stats.adds = V.stats.adds + 1
        return true
    end
    D.err, D.code = tostring(err), code
    if code == "fault" then
        V.Fault(err)
    elseif code == "not_ready" then
        D.retry = now + 0.5
    else
        D.retry = now + 10
        V.stats.failures = V.stats.failures + 1
        log("pictures: %s could not be made (%s)", D.key, tostring(err))
    end
    return false
end

-- a showcase fault: one line, the outlines until a clear and a re-add work (at most once a minute)
function V.Fault(err)
    V.stats.faults = V.stats.faults + 1
    if V.working ~= false then
        log("pictures: the hidden copy of the game faulted (%s); outlines until it is made again", tostring(err))
    end
    V.working = false
    V.faultAt = now_s()
    V.ClearCopies(nil, false)
end

-- the materials of a description's batches: cl_textures.lua's of the pictures' kind; logoMats: the same with the Extra
-- Life panel's texture replaced by the Dreamcast logo
local function resolve_mats(D)
    local T = GSA1.Tex
    local panel = V.PANEL[V.kind or 0]
    local extra = (D.type == O.TYPE.ITEMBOX or D.type == O.TYPE.ITEMBOX_AIR) and D.p1 == V.EXTRA_LIFE
    D.hasLogo = false
    for i = 1, D.batches.count do
        local b = D.batches[i]
        local m = T and T.Material(V.kind or 0, b) or nil
        D.mats[i] = m
        D.logoMats[i] = m
        if extra and panel and b.archive == panel[1] and b.tex == panel[2] then
            D.logoMats[i] = V.LogoMaterial(b) or m
            D.hasLogo = true
        end
    end
    for i = #D.mats, D.batches.count + 1, -1 do
        D.mats[i], D.logoMats[i] = nil, nil
    end
    D.logoReady = V.logo and V.logo.done or false
    D.facing = false
    for i = 1, D.batches.count do
        local b = D.batches[i]
        if band(b.flags or 0, DRAW_ENV) ~= 0 or band(b.prims or 0, PRIMS_FACING) ~= 0 then D.facing = true end
    end
end

-- the eye and the view's axes (the main view's: cl_render.lua GSA1.MainEye)
local function main_view()
    if GSA1.MainEye then return GSA1.MainEye() end
    return EyePos(), EyeAngles()
end

-- the description's draws for this pair (or this frame, smoothed): render, batches, materials, its view with the eye in
-- object space of anchor (an instance's place), one static IMesh per batch. Returns true when it can be drawn
function V.Refresh(D, eye, ang, anchor, force)
    if not D.id then return false end
    local fn = FrameNumber()
    if D.frame == fn and not force then return D.ready end
    D.frame = fn
    local alpha = (cv.view_smooth and cv.view_smooth:GetBool()) and -1 or 1
    local n, gen, bgen, changed = gsa1.PreviewRender(D.id, alpha)
    if not n then
        local code = bgen
        if code == "not_found" or code == "not_ready" then
            drop(D, false)              -- a disc reload freed it: added again
        elseif code == "fault" then
            V.Fault(gen)
        end
        return false
    end
    if not changed and D.built and not force then return D.ready end
    gsa1.PreviewBatches(D.id, D.batches)
    D.gen = gen
    resolve_mats(D)
    local cvr = GSA1.cv or {}
    local rel = (anchor and eye) and (eye - anchor) or Vector(0, 0, 0)
    gsa1.PreviewPrepareView(D.id, rel, ang:Right(), ang:Up(), cvr.flip and cvr.flip:GetBool() or false,
        not cvr.vcolor or cvr.vcolor:GetBool(), cvr.line_width and cvr.line_width:GetFloat() or 2,
        not cvr.lighting or cvr.lighting:GetBool())
    free_meshes(D)
    local id = D.id
    for i = 1, D.batches.count do
        local b = D.batches[i]
        if b.tris > 0 and D.mats[i] then
            local ok, im = pcall(GSA1.StaticMesh, D.mats[i], b.tris, function() gsa1.PreviewEmitBatch(id, i) end)
            if ok then D.meshes[i] = im end
        end
    end
    D.built = true
    D.ready = D.batches.count > 0
    V.stats.refreshed = V.stats.refreshed + 1
    return D.ready
end

-- the ring places of a ring group (gsa1.PreviewRingPlaces: the module's records, the game's layout), cached
local placeBuf = {}
function V.Places(d, ang)
    local key = string.format("%d:%d:%.3f:%d:%.2f:%.2f:%.2f", V.kind or 0, d.count or 0, d.size or 0, d.shape or 0,
        ang.p, ang.y, ang.r)
    local p = V.places[key]
    if p ~= nil and not (p.failed and now_s() - p.failed > 2) then return not p.failed and p or nil end
    local n, out = gsa1.PreviewRingPlaces(V.kind or 0, O.TYPE.O_GRING, ang, d.count, d.size, d.shape, placeBuf)
    if not n then
        V.places[key] = { failed = now_s() }          -- (tried again 2 s later; the outline meanwhile)
        return nil
    end
    p = {}
    for i = 1, n do
        local k = 5 * (i - 1)
        p[i] = { off = Vector(out[k + 1], out[k + 2], out[k + 3]), record = out[k + 4], bit = out[k + 5] }
    end
    V.places[key] = p
    return p
end

-- an entity's layout: its pictures' kinds and places relative to the entity (made again when its description, place or
-- angles change)
local function layout(E, ent, d, pos, ang)
    local items = {}
    local T = O.TYPE
    if d.type == T.RING then
        items[1] = { t = T.RING, record = 0, bit = 0, off = Vector(0, 0, 0) }
    elseif d.type == T.O_GRING then
        local p = V.Places(d, ang)
        if not p then return nil end
        for i, r in ipairs(p) do
            items[i] = { t = T.RING, record = r.record, bit = r.bit, off = r.off }
        end
    elseif d.type == T.ITEMBOX then
        items[1] = { t = T.ITEMBOX, record = 0, bit = 0, off = Vector(0, 0, 0) }
    elseif d.type == T.ITEMBOX_AIR then
        items[1] = { t = T.ITEMBOX_AIR, record = 0, bit = 0, off = Vector(0, 0, 0), rot = true }
    end
    return items
end

-- the layout is made again when the description, the place or the angles change (numbers compared: no string a frame)
local function moved(E, d, pos, ang, kind)
    local s = E.s
    if not s then return true end
    return s[1] ~= kind or s[2] ~= d.type or s[3] ~= d.count or s[4] ~= d.size or s[5] ~= d.shape or s[6] ~= d.contents or
        math.abs(s[7] - pos.x) > 0.01 or math.abs(s[8] - pos.y) > 0.01 or math.abs(s[9] - pos.z) > 0.01 or
        math.abs(s[10] - ang.p) > 0.01 or math.abs(s[11] - ang.y) > 0.01 or math.abs(s[12] - ang.r) > 0.01
end

-- this client's own takes ---------------------------------------------------------------------------------------------
-- a GONE / BROKEN / USERBITS event of the local character's world (cl_objects.lua O.PollEvents): the picture goes (or
-- breaks, or loses those rings) at once, before the server's state arrives
function V.OnEvent(e)
    local idx = tonumber(e.user)
    if not idx then return end
    local EV = O.EV
    local kind = e.kind
    if kind ~= EV.GONE and kind ~= EV.BROKEN and kind ~= EV.USERBITS then return end
    local p = V.pending[idx] or { bits = {} }
    p.t = now_s()
    if kind == EV.GONE then
        if e.type == O.TYPE.ITEMBOX then p.broken = true else p.gone = true end
    elseif kind == EV.BROKEN then
        p.broken = true
    else
        local k = tonumber(e.index) or 0
        p.bits[k] = bor(p.bits[k] or 0, band(tonumber(e.bits) or 0, 0xFF))
    end
    V.pending[idx] = p
end

-- the server refused this client's report: the picture as the server's state says
function V.OnRefused(idx)
    V.pending[idx] = nil
end

-- the live set (review R.6) -------------------------------------------------------------------------------------------
V.live, V.liveSince, V.liveBuf = V.live or {}, V.liveSince or {}, V.liveBuf or {}
function V.UpdateLive(C)
    if V.liveChar ~= C.id then
        V.liveChar, V.live, V.liveSince, V.liveStep, V.liveOk = C.id, {}, {}, nil, nil
    end
    local step = C.state and tonumber(C.state.step) or nil
    if step ~= nil and step == V.liveStep then return end
    V.liveStep = step
    if not gsa1.SetLive then
        V.liveOk = false
        return
    end
    local n, out = gsa1.SetLive(C.id, V.liveBuf)
    if not n then
        V.liveOk = false
        return
    end
    V.liveOk = true
    local live, since = {}, V.liveSince
    for i = 1, n do
        local obj, rec = out[2 * i - 1], out[2 * i]
        local l = live[obj]
        if not l then
            l = {}
            live[obj] = l
        end
        l[rec] = true
        local k = obj * 256 + rec
        if not since[k] then since[k] = step or 0 end
    end
    for k in pairs(since) do
        local obj, rec = math.floor(k / 256), k % 256
        if not (live[obj] and live[obj][rec]) then since[k] = nil end
    end
    V.live = live
end

-- per frame -----------------------------------------------------------------------------------------------------------
local lightRR = 1
local function update_entity(idx, rec, C, now, eye, dist2, mode, editing, stamp)
    local ent = rec.ent
    local E = V.ents[idx]
    if not IsValid(ent) then
        V.ents[idx] = nil
        return
    end
    if not E or E.ent ~= ent then
        E = { ent = ent, pics = {}, npics = 0, inRange = {} }
        V.ents[idx] = E
    end
    E.seen = stamp
    E.npics, E.wait = 0, false
    if mode == 0 then return end
    local d = O.Describe(ent)
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local kind = V.kind or 0
    if moved(E, d, pos, ang, kind) or not E.items then
        E.items = layout(E, ent, d, pos, ang)
        E.s = E.items and { kind, d.type, d.count, d.size, d.shape, d.contents, pos.x, pos.y, pos.z, ang.p, ang.y, ang.r } or
            nil
        E.pos, E.ang = Vector(pos), Angle(ang)
        E.light = nil                   -- placed or moved: sampled again
    end
    local items = E.items
    if not items then
        E.wait = true                   -- (its ring places are not there: the outline until they are)
        return
    end
    local T = O.TYPE
    -- the state: the server's, and this client's own take until the server's state says so
    local p = V.pending[idx]
    if p and now - p.t > V.PENDING_MAX then
        V.pending[idx] = nil
        p = nil
    end
    local state = tonumber(ent.GetState and ent:GetState()) or 1
    local broken = d.type == T.ITEMBOX and ent.GetBroken ~= nil and ent:GetBroken() == true
    if p then
        if p.gone then
            if state == 0 then V.pending[idx] = nil end
            state = 0
        end
        if p.broken then
            if broken then V.pending[idx] = nil end
            broken = true
        end
    end
    if (d.type == T.RING or d.type == T.ITEMBOX_AIR) and state == 0 then return end
    local oid = rec.id
    local live = C and oid and V.live[oid] or nil
    local ex, ey, ez = eye.x, eye.y, eye.z
    local cpos = C and (C.drawPos or (IsValid(C.ent) and C.ent:GetPos())) or nil
    local range2 = O.RANGE * O.RANGE
    local Dring = nil                   -- (one description lookup per entity, not per ring)
    for _, it in ipairs(items) do
        local x, y, z = E.pos.x + it.off.x, E.pos.y + it.off.y, E.pos.z + it.off.z
        local show = true
        if it.t == T.RING and d.type == T.O_GRING then
            local have = O.BitsOf(ent, it.record)
            if p and p.bits[it.record] then
                if band(have, p.bits[it.record]) == p.bits[it.record] then p.bits[it.record] = nil end
                have = bor(have, p.bits[it.record] or 0)
            end
            show = band(have, it.bit) == 0
        end
        if show then
            local dx, dy, dz = x - ex, y - ey, z - ez
            show = dx * dx + dy * dy + dz * dz <= dist2
        end
        if show and mode == 2 then
            -- (b) with a character: not what its world runs (an intact box keeps its picture while it grows in)
            local running = live and live[it.record]
            if running then
                local hold = false
                if (it.t == T.ITEMBOX and not broken) or it.t == T.ITEMBOX_AIR then
                    local since = V.liveSince[oid * 256 + it.record]
                    local step = C.state and tonumber(C.state.step) or 0
                    hold = since ~= nil and step - since < V.Settle(it.t)
                end
                show = hold
            elseif not editing and cpos then
                -- inside the game's range but not running: a full budget left it out (no picture: it could not be taken)
                local dx, dy, dz = x - cpos.x, y - cpos.y, z - cpos.z
                local key = it.record * 65536 + (it.bit or 0)
                if dx * dx + dy * dy + dz * dz < range2 then
                    local t0 = E.inRange[key]
                    if not t0 then
                        E.inRange[key] = now
                    elseif now - t0 > V.RANGE_GRACE then
                        show = false
                    end
                else
                    E.inRange[key] = nil
                end
            end
        end
        if show then
            local D
            if it.t == T.RING then
                Dring = Dring or V.Need(T.RING, 0, 1)
                D = Dring
            elseif it.t == T.ITEMBOX then
                D = V.Need(T.ITEMBOX, d.contents, broken and 3 or 1)
            else
                D = V.Need(T.ITEMBOX_AIR, d.contents, 1)
            end
            E.npics = E.npics + 1
            local pic = E.pics[E.npics]
            if not pic then
                pic = { pos = Vector() }
                E.pics[E.npics] = pic
            end
            pic.D = D
            if not D.ready then E.wait = true end
            pic.pos:SetUnpacked(x, y, z)
            pic.ang = it.rot and E.ang or nil
            if not D.anchorFrame or D.anchorFrame ~= V.frameNo then
                D.anchorFrame = V.frameNo
                D.anchor = D.anchor or Vector()
                D.anchor:SetUnpacked(x, y, z)
            end
        end
    end
    -- the entity's lighting: sampled when it was placed or moved (a few a frame), then round robin
    if E.npics > 0 and not E.light and V.lightBudget > 0 then
        V.lightBudget = V.lightBudget - 1
        V.SampleLight(E)
    end
end

function V.SampleLight(E)
    if not (GSA1.LightCube and E.pos) then return end
    E.lightOrigin = E.lightOrigin or Vector()
    E.lightOrigin:Set(E.pos)
    E.lightOrigin.z = E.lightOrigin.z + 16
    E.light = GSA1.LightCube(E.lightOrigin, E.light or {})
end

-- the mode of the pictures this frame: 0 none, 1 a player without a character (a), 2 with one (b)
function V.Mode(C)
    if not V.Ready() then return 0 end
    if not C then return (cv.view and cv.view:GetBool()) and 1 or 0 end
    if not (cv.on:GetBool() and cv.draw:GetBool()) then return 0 end
    if V.liveOk == false then return 0 end      -- (a module without SetLive cannot tell what the world runs)
    if (cv.view_far and cv.view_far:GetBool()) or (O.Editing and O.Editing() and cv.view_edit and cv.view_edit:GetBool())
    then
        return 2
    end
    return 0
end

function V.Think()
    local now = now_s()
    V.now = now
    V.frameNo = FrameNumber()
    if not V.Have() then return end
    -- a fault: at most one attempt a minute
    if V.working == false then
        if now - (V.faultAt or 0) < V.RETRY_FAULT then return end
        V.working = nil
        if gsa1.PreviewClear then gsa1.PreviewClear() end
        log("pictures: making the hidden copy of the game again")
    end
    local ready = V.Ready()
    local C = GSA1.Char
    local kind = V.KindNow()
    if kind ~= V.kind then
        if V.kind ~= nil then V.ClearCopies("the pictures' character changed") end
        V.kind = kind
        V.types = nil
    end
    if ready and C then V.UpdateLive(C) else V.liveChar, V.liveOk = nil, nil end
    local mode = ready and V.Mode(C) or 0
    V.mode = mode
    local eye, ang = main_view()
    local vd = cv.view_dist and cv.view_dist:GetFloat() or O.VIEW_DIST_DEFAULT
    local editing = O.Editing and O.Editing() or false
    V.lightBudget = V.LIGHT_PER_FRAME
    -- (0.9.4d: the entities seen this frame by a stamp, not a new table a frame)
    local stamp = (V.stamp or 0) + 1
    V.stamp = stamp
    for idx, rec in pairs(O.tracked or NONE) do
        update_entity(idx, rec, C, now, eye, vd * vd, mode, editing, stamp)
    end
    for idx, E in pairs(V.ents) do
        if E.seen ~= stamp then V.ents[idx] = nil end
    end
    -- the round-robin light refresh
    local n = 0
    for idx, E in pairs(V.ents) do
        n = n + 1
    end
    if n > 0 and V.lightBudget > 0 then
        local i = 0
        for _, E in pairs(V.ents) do
            i = i + 1
            if i >= lightRR and E.npics > 0 then
                V.SampleLight(E)
                V.lightBudget = V.lightBudget - 1
                if V.lightBudget <= 0 then break end
            end
        end
        lightRR = (lightRR + V.LIGHT_PER_FRAME - 1) % n + 1
    end
    if not ready then return end
    -- the copies: made, refreshed (their materials made as soon as their batches come), retired
    local any = false
    for key, D in pairs(V.descs) do
        if now - D.used > V.RETIRE then
            drop(D, true)
            V.descs[key] = nil
        else
            any = true
            if not D.id then add_copy(D, now) end
            if D.id and D.anchor then V.Refresh(D, eye, ang, D.anchor) end
        end
    end
    if any then V.lastGone = now end
    if (any or (V.lastGone and now - V.lastGone < V.TICK_AFTER)) and gsa1.PreviewTick then
        local ok, err, code = gsa1.PreviewTick(FrameTime())
        if not ok and code == "fault" then V.Fault(err) end
    end
end

-- drawing (gsa1_base.lua ENT:Draw / DrawTranslucent through cl_objects.lua O.DrawEntity) -------------------------------
local M = nil
-- a description's batches of one pass under the current model matrix. depth: the depth views' material (color: the
-- depth pass's $color_depth 1); logo: the Dreamcast logo on an Extra Life panel; alphaBlend: the blended batches keep a
-- separate alpha blend (ONE / ONE_MINUS_SRC_ALPHA: the spawn-menu pictures' transparent render target); inst: an
-- instance under a rotation drawn from a view of its own (D.facing: sphere maps, sprites, lines)
function V.DrawDesc(D, pass, depth, color, logo, alphaBlend, inst)
    local T = GSA1.Tex
    local mats = (logo and D.hasLogo and V.logo and V.logo.done) and D.logoMats or D.mats
    local stream = inst ~= nil
    if stream then
        local ang = inst.ang
        local m = Matrix()
        m:SetAngles(ang)
        m:Rotate(QUARTER)
        local eye, eang = main_view()
        local rel = eye - inst.pos
        -- the eye and the axes in the instance's own frame (its rotation's transpose)
        local f, l, u = m:GetForward(), -m:GetRight(), m:GetUp()
        local function local_of(v) return Vector(v:Dot(f), v:Dot(l), v:Dot(u)) end
        local cvr = GSA1.cv or {}
        gsa1.PreviewPrepareView(D.id, local_of(rel), local_of(eang:Right()), local_of(eang:Up()),
            cvr.flip and cvr.flip:GetBool() or false, not cvr.vcolor or cvr.vcolor:GetBool(),
            cvr.line_width and cvr.line_width:GetFloat() or 2, not cvr.lighting or cvr.lighting:GetBool())
    end
    local drawn = 0
    for i = 1, D.batches.count do
        local b = D.batches[i]
        if b and b.pass == pass and b.tris > 0 then
            local mat
            if depth then
                mat = T.DepthMaterial(V.kind or 0, b, color)
            else
                mat = mats[i]
            end
            if mat then
                render.SetMaterial(mat)
                if pass == 1 and not depth then
                    local s, d = T.BlendOf(b)
                    if alphaBlend then
                        render.OverrideBlend(true, s, d, F_ADD, B_ONE, B_ONE_MINUS_SRC_ALPHA, F_ADD)
                    else
                        render.OverrideBlend(true, s, d, F_ADD)
                    end
                end
                if stream then
                    mesh.Begin(MATERIAL_TRIANGLES, b.tris)
                    gsa1.PreviewEmitBatch(D.id, i)
                    mesh.End()
                else
                    local im = D.meshes[i]
                    if im then im:Draw() end
                end
                if pass == 1 and not depth then render.OverrideBlend(false) end
                drawn = drawn + 1
            end
        end
    end
    return drawn
end

local function draw_pics(E, pass, depth, color, logo)
    M = M or Matrix()
    local n = 0
    for i = 1, E.npics do
        local pic = E.pics[i]
        local D = pic.D
        if D and D.ready and D.id then
            M:Identity()
            M:SetTranslation(pic.pos)
            local inst = nil
            if pic.ang then
                M:SetAngles(pic.ang)
                M:Rotate(QUARTER)
                if D.facing then inst = pic end
            end
            cam.PushModelMatrix(M)
            local ok, err = pcall(V.DrawDesc, D, pass, depth, color, logo, false, inst)
            cam.PopModelMatrix()
            if not ok then error(err, 0) end
            n = n + 1
        end
    end
    return n
end

-- true when the entity drew pictures (the caller still draws the outlines); "pending" when it has pictures to show that are
-- not ready yet (a new copy draws nothing in its first pair; ring places not there): the caller draws its outline instead
function V.DrawEntity(ent, pass, flags)
    local E = V.ents[ent:EntIndex()]
    if not E or E.ent ~= ent then return false end
    if (E.npics or 0) == 0 then return E.wait and "pending" or false end
    local kind = GSA1.ViewKind and GSA1.ViewKind(flags) or "main"
    local df = GSA1.cv and GSA1.cv.depthfix
    local depth = (kind == "ssao" or kind == "shadowdepth") and (not df or df:GetInt() >= 1)
    if depth and pass ~= 0 then return true end
    local lit = GSA1.cv and GSA1.cv.lighting and GSA1.cv.lighting:GetBool()
    local light = lit and not depth and E.light and GSA1.ApplyLightCube
    if light then GSA1.ApplyLightCube(E.lightOrigin, E.light) end
    local ok, res = pcall(draw_pics, E, pass, depth, kind == "ssao", GSA1.Char == nil)
    if light then GSA1.EndLightCube() end
    if not ok then
        if not V.drawError then
            V.drawError = true
            log("pictures: drawing failed: %s", tostring(res))
        end
        return false
    end
    local fn = FrameNumber()
    if V.frame.n ~= fn then
        V.frame.lastInstances, V.frame.lastEnts = V.frame.instances, V.frame.ents
        V.frame.n, V.frame.instances, V.frame.ents = fn, 0, 0
    end
    if pass == 0 then
        V.frame.instances = V.frame.instances + res
        V.frame.ents = V.frame.ents + 1
    end
    if res == 0 and E.wait then return "pending" end
    return res > 0
end

-- the Dreamcast logo, drawn by code (owner answer O4) -----------------------------------------------------------------
-- a clockwise spiral widening outwards, as short convex quads (surface.DrawPoly) on transparent: an Archimedean spiral of
-- 1.75 turns from the centre, its width growing from 2 % to 13 % of the picture
function V.LogoPolys(size)
    local polys = {}
    local c = size / 2
    local turns, segs = 1.75, 140
    local tmax = turns * 2 * math.pi
    local r0, r1 = size * 0.02, size * 0.44
    local w0, w1 = size * 0.02, size * 0.13
    local function at(t, side)
        local f = t / tmax
        local r = r0 + (r1 - r0) * f
        local w = w0 + (w1 - w0) * f
        local rr = r + side * w / 2
        -- screen y points down: a growing angle turns clockwise on screen
        return c + rr * math.cos(t), c + rr * math.sin(t)
    end
    for i = 0, segs - 1 do
        local t0, t1 = tmax * i / segs, tmax * (i + 1) / segs
        local ax, ay = at(t0, 1)
        local bx, by = at(t1, 1)
        local cx, cy = at(t1, -1)
        local dx, dy = at(t0, -1)
        polys[#polys + 1] = { { x = ax, y = ay }, { x = bx, y = by }, { x = cx, y = cy }, { x = dx, y = dy } }
    end
    return polys
end

-- paints the logo into its render target (in a render hook: PostRender)
function V.PaintLogo()
    local T = GSA1.Tex
    local fmt = T and T.format or { name = "BGRA8888", fmt = IMAGE_FORMAT_BGRA8888 or 12 }
    local L = V.logo or {}
    V.logo = L
    local size = V.LOGO_SIZE
    if not L.rt then
        L.rt = GetRenderTargetEx("gsa1_dclogo_" .. fmt.name, size, size, RT_SIZE_LITERAL or 1, MATERIAL_RT_DEPTH_NONE or 2,
            bor(TEXTUREFLAGS_CLAMPS or 4, TEXTUREFLAGS_CLAMPT or 8), 0, fmt.fmt)
    end
    render.PushRenderTarget(L.rt)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(0, 0, 0, 0)            -- (colour only: the target has no depth buffer)
    cam.Start2D()
    render.OverrideBlend(true, B_ONE, B_ZERO, F_ADD, B_ONE, B_ZERO, F_ADD)
    draw.NoTexture()
    local col = V.LOGO_COLOR
    surface.SetDrawColor(col[1], col[2], col[3], 255)
    for _, q in ipairs(V.LogoPolys(size)) do
        surface.DrawPoly(q)
        surface.DrawPoly({ q[4], q[3], q[2], q[1] })      -- (either winding: one of them is culled)
    end
    render.OverrideBlend(false)
    cam.End2D()
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    L.done, L.painted = true, (L.painted or 0) + 1
    V.logoMats = {}
end

-- a batch's material with the logo as its texture (the batch's own state: cl_textures.lua T.MaterialState)
V.logoMats = V.logoMats or {}
function V.LogoMaterial(b)
    if not (V.logo and V.logo.rt) then
        V.logoWanted = true
        return nil
    end
    local T = GSA1.Tex
    local mode, lit, nocull, hl, alpha = T.MaterialState(b)
    local name = string.format("gsa1_dclogo_m%d%d%d%d_%d", mode, lit and 1 or 0, nocull and 1 or 0, hl and 1 or 0, alpha)
    local m = V.logoMats[name]
    if m then return m end
    local p = { ["$model"] = 1, ["$vertexcolor"] = 1, ["$nocull"] = nocull and 1 or 0,
                ["$basetexture"] = V.logo.rt:GetName() }
    if mode >= 2 and mode <= 3 then
        p["$vertexalpha"] = 1
        if mode == 3 then p["$additive"] = 1 else p["$translucent"] = 1 end
        if alpha and alpha < 255 then p["$alpha"] = alpha / 255 end
    else
        -- the logo's transparency cuts the panel out (the face's panel draws opaque or alpha-tested)
        p["$alphatest"] = 1
        p["$alphatestreference"] = 0.5
    end
    if hl then p["$halflambert"] = 1 end
    m = CreateMaterial(name, lit and "VertexLitGeneric" or "UnlitGeneric", p)
    V.logoMats[name] = m
    return m
end

hook.Add("PostRender", "gsa1_objview_logo", function()
    if not V.logoWanted and not (V.logo and V.logo.lost) then return end
    V.logoWanted = false
    local ok, err = pcall(V.PaintLogo)
    if ok then
        if V.logo then V.logo.lost = false end
        -- the descriptions that wait for it resolve their logo materials again
        for _, D in pairs(V.descs) do
            if D.hasLogo then D.built = false end
        end
    elseif not V.logoError then
        V.logoError = true
        log("pictures: the Dreamcast logo could not be drawn: %s", tostring(err))
    end
end)

-- render targets lose their contents on a device reset (cl_textures.lua: focus regained, a screen size change)
local hadFocus = true
hook.Add("PostRender", "gsa1_objview_reset", function()
    local focus = true
    if system and system.HasFocus then focus = system.HasFocus() and true or false end
    if focus and not hadFocus and V.logo and V.logo.done then V.logo.lost = true end
    hadFocus = focus
end)
hook.Add("OnScreenSizeChanged", "gsa1_objview_reset", function()
    if V.logo and V.logo.done then V.logo.lost = true end
end)

-- status (the Objects page) -------------------------------------------------------------------------------------------
function V.StatusLine()
    if not V.Have() then return "pictures: this G-SA1 module has no object previews (outlines only)" end
    if V.working == false then return "pictures: the hidden copy of the game faulted - outlines until it is made again" end
    if not V.Ready() then return "pictures: waiting for the disc (outlines until then)" end
    local n = 0
    for _, D in pairs(V.descs) do
        if D.id then n = n + 1 end
    end
    local ms = 0
    if gsa1.PreviewStats then
        local ok, st = pcall(gsa1.PreviewStats)
        if ok and type(st) == "table" then ms = tonumber(st.tick_ms) or 0 end
    end
    local modes = { [0] = "off", [1] = "no character: every object", [2] = "with your character: the ones it does not run" }
    return string.format("pictures: %d kinds of object, %d drawn on %d objects last frame (%s), showcase %s %.2f ms a "
        .. "frame", n, V.frame.lastInstances or V.frame.instances or 0, V.frame.lastEnts or V.frame.ents or 0,
        modes[V.mode or 0] or "?", V.KIND_TITLE[V.kind or 0] or "?", ms)
end

-- once per frame (after the objects feature's own Think: the hooks' order does not matter, both read the entities)
hook.Add("Think", "gsa1_objview", function()
    local ok, err = pcall(V.Think)
    if not ok and not V.thinkError then
        V.thinkError = true
        log("pictures: error: %s", tostring(err))
        ErrorNoHalt("[G-SA1] objects pictures: " .. tostring(err) .. "\n")
    end
end)

-- a new disc or gsa1.Shutdown forgets the module's copies (gsa1.PreviewRender says not_found / not_ready: added again)
hook.Add("GSA1CharacterCreated", "gsa1_objview", function(C)
    V.liveChar = nil
end)
