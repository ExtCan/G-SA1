-- G-SA1 client: moving collision - brush entities (doors, lifts, trains, func_brush, breakables) and physics props
-- and vehicles - as libsa1 moving objects (module: src/core/movers.*), G64's dynamic sources with matrices instead of
-- Euler angles.
--
-- A few times a second the entities around the character are looked at (ents.FindInSphere); every frame the ones
-- found are handed to the module with their position, angles and whether they are solid now (gsa1.MoverUpdate), and
-- gsa1.MoverCommit puts the nearest into libsa1 (at most 40 objects / 2048 triangles near the character; the rest are
-- parked far below the map without being freed, so a door switched off and on again or a prop that comes back into
-- range costs one move). Shapes: a brush entity's model ("*N") was built with the map (cl_module.lua: only the solid
-- brush entity classes); a prop's comes from its physics model (the .phy next to the .mdl, read through Garry's
-- Mod's file system and cleaned like brushes by the module), or its collision box for SOLID_BBOX entities.
GSA1 = GSA1 or {}
GSA1.Movers = GSA1.Movers or { list = {}, missing = {}, nextScan = 0 }
local M = GSA1.Movers

local SCAN_INTERVAL = 0.2       -- seconds between looks around
local SCAN_RANGE = 2600         -- Hammer units (the module's own range is 2400 from a chunk's sphere)
local NEW_SHAPES_PER_FRAME = 2
local SOLID_BBOX, SOLID_OBB, SOLID_OBB_YAW, SOLID_VPHYSICS = 2, 3, 4, 6
local FSOLID_TRIGGER = 0x8
local band = bit.band

-- collision groups that do not collide with players (G64 switches the same ones off)
local NO_PLAYER = {}
for _, g in ipairs({ COLLISION_GROUP_DEBRIS, COLLISION_GROUP_DEBRIS_TRIGGER, COLLISION_GROUP_IN_VEHICLE,
                     COLLISION_GROUP_WEAPON, COLLISION_GROUP_PASSABLE_DOOR, COLLISION_GROUP_WORLD }) do
    if g then NO_PLAYER[g] = true end
end

local function prof(name, t0)
    if GSA1.HitchAdd then GSA1.HitchAdd(name, SysTime() - t0) end
end

-- the shape key of an entity ("b<N>", "m:<model>", "x:<box>"), or nil; may read a .phy (budget: new)
local function shape_key(e, budget)
    local model = e:GetModel()
    if not model or model == "" then return nil end
    if string.sub(model, 1, 1) == "*" then
        if not GSA1.cv.brush_ents:GetBool() then return nil end
        local key = "b" .. string.sub(model, 2)
        return gsa1.ShapeKnown(key) and key or nil
    end
    if not GSA1.cv.phys_props:GetBool() then return nil end
    local solid = e:GetSolid()
    if solid == SOLID_VPHYSICS then
        model = string.lower(model)
        local key = "m:" .. model
        if M.missing[key] then return nil end
        if gsa1.ShapeKnown(key) then return key end
        if budget.n <= 0 then return nil end
        budget.n = budget.n - 1
        local t0 = SysTime()
        local path = string.gsub(model, "%.mdl$", ".phy")
        local data = nil
        local f = file.Open(path, "rb", "GAME")
        if f then
            data = f:Read(f:Size())
            f:Close()
        end
        local ok, err = false, "no physics model"
        if data then ok, err = gsa1.ShapePhy(key, data) end
        prof("Shapes", t0)
        if not ok then
            M.missing[key] = true
            if GSA1.cv.debug:GetBool() then GSA1.Msg("%s: no moving collision (%s)", model, tostring(err)) end
            return nil
        end
        return key
    elseif solid == SOLID_BBOX or solid == SOLID_OBB or solid == SOLID_OBB_YAW then
        local mn, mx = e:OBBMins(), e:OBBMaxs()
        local key = string.format("x:%.0f %.0f %.0f %.0f %.0f %.0f", mn.x, mn.y, mn.z, mx.x, mx.y, mx.z)
        if M.missing[key] then return nil end
        if gsa1.ShapeKnown(key) then return key end
        if not gsa1.ShapeBox(key, mn, mx) then
            M.missing[key] = true
            return nil
        end
        return key
    end
    return nil
end

local function wanted(e, ply)
    if not IsValid(e) or e == ply or e:IsPlayer() or e:IsNPC() or e:IsWeapon() or e:IsWorld() then return false end
    -- 0.9.4: a G-SA1 game object (feat/sh_objects.lua) is the game's own object in the world, with its own collision; its
    -- editing box would be a moving object the character stands on instead of reaching the box's lid
    if e.GSA1Object then return false end
    local cls = e:GetClass()
    if cls == "gsa1_render" or cls == "prop_ragdoll" or cls == "class C_ClientRagdoll" then return false end
    return true
end

local function is_solid(e, ply)
    if not e:IsSolid() or band(e:GetSolidFlags(), FSOLID_TRIGGER) ~= 0 then return false end
    -- a prop the character carries, or one that just left its hands (round 5, feat/cl_interact.lua): true or a time
    local nc = e.GSA1NoCollide
    if nc == true or (type(nc) == "number" and SysTime() < nc) then return false end
    if NO_PLAYER[e:GetCollisionGroup()] then return false end
    if IsValid(ply) and ply.GetVehicle and ply:GetVehicle() == e then return false end
    return true
end

-- the entities near pos -> M.list ({ent, idx, key})
local function scan(pos, ply)
    local budget = { n = NEW_SHAPES_PER_FRAME }
    local list, seen = {}, {}
    for _, e in ipairs(ents.FindInSphere(pos, SCAN_RANGE)) do
        if wanted(e, ply) then
            local key = shape_key(e, budget)
            if key then
                local idx = e:EntIndex()
                list[#list + 1] = { ent = e, idx = idx, key = key }
                seen[idx] = true
            end
        end
    end
    for _, it in ipairs(M.list) do
        if not seen[it.idx] then gsa1.MoverForget(it.idx) end
    end
    M.list = list
end

-- once per frame before gsa1.Tick: the entities' transforms into the module, the nearest into libsa1
function GSA1.MoversThink(C, now)
    if not GSA1.mod or not gsa1.MoverUpdate then return end
    local t0 = SysTime()
    local ply = LocalPlayer()
    if now >= M.nextScan then
        M.nextScan = now + SCAN_INTERVAL
        scan(C.drawPos, ply)
    end
    for _, it in ipairs(M.list) do
        local e = it.ent
        if IsValid(e) then
            gsa1.MoverUpdate(it.idx, it.key, e:GetPos(), e:GetAngles(), is_solid(e, ply))
        end
    end
    gsa1.MoverCommit()
    prof("Movers", t0)
end

-- no character: every object out of libsa1's way (parked), the list forgotten
function GSA1.MoversClear()
    if not GSA1.mod or not gsa1.MoverForget then return end
    for _, it in ipairs(M.list) do gsa1.MoverForget(it.idx) end
    M.list = {}
    gsa1.MoverCommit()
end

hook.Add("EntityRemoved", "gsa1_movers", function(e)
    if not GSA1.mod or not gsa1.MoverForget then return end
    local idx = e:EntIndex()
    for i, it in ipairs(M.list) do
        if it.idx == idx then
            gsa1.MoverForget(idx)
            table.remove(M.list, i)
            return
        end
    end
end)

for _, name in ipairs({ "gsa1_brush_entities", "gsa1_physics_props" }) do
    cvars.AddChangeCallback(name, function()
        M.missing = {}
        M.nextScan = 0
    end, "gsa1_movers")
end

-- "moving objects: 12 near (3 in libsa1, 340 triangles, 2 parked), 5 shapes"
function GSA1.MoverLine()
    if not GSA1.mod or not gsa1.MoverStatus then return "moving objects: -" end
    local s = gsa1.MoverStatus()
    local on = {}
    if GSA1.cv.brush_ents:GetBool() then on[#on + 1] = "brush entities" end
    if GSA1.cv.phys_props:GetBool() then on[#on + 1] = "physics props" end
    return string.format("moving objects (%s): %d near, %d in the game (%d triangles), %d parked, %d shapes%s",
        #on > 0 and table.concat(on, ", ") or "off", s.entities or 0, s.active or 0, s.active_tris or 0,
        s.parked or 0, s.shapes or 0, (s.failures or 0) > 0 and string.format("; %d failed: %s", s.failures, s.error) or "")
end
