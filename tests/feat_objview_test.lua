-- feat_objview_test.lua - the pictures of the real objects (round 0.9.4b; sadc docs/research/objects2_plan.md 6.3 task 3
-- with its Review R.6 / R.8 / R.9 / R.10 / R.17 / R.18, owner answers 11.0, 11.1): feat/cl_objview.lua with
-- feat/sh_objects.lua, cl_objects.lua (the window's migration, the outlines, the hover outline), cl_objicons.lua,
-- cl_spawntab.lua and the entities - in Garry's Mod's own LuaJIT against tests/lua_mock.lua, a mock of the module's
-- features "objects" 3 and "preview" 1 (every call recorded) and a small model of the client's scripted entities.
--   lua_host tests/feat_objview_test.lua <tests dir> <addon/lua dir>
-- Checks: without a character every entity draws its picture - 30 Rings, a line and a circle share ONE PreviewAdd of the
-- RING description; a taken Ring and a taken air box draw nothing, a broken ground box the broken description, a line
-- without its taken rings; a local GONE hides a picture before the server's state, a refusal brings it back; with a
-- character only the records SetLive does not list, only with gsa1_set_view_far 1 or the Physics Gun / Tool Gun with
-- gsa1_set_view_edit 1; the hold of an intact box (ground 47 steps, air 23; none for a broken box or a ring); none with
-- gsa1_set 0 or gsa1_set_draw 0, nor inside the game's range while playing; a lost event cannot leave a picture on a live
-- record; PreviewTick runs 3 s past the last copy; gsa1_set_view 0 -> the outlines; gsa1_set_view_dist culls; the kind
-- follows the character, then the Character page, Super Sonic -> Sonic; NOT_FOUND re-adds; one static IMesh per
-- (description, batch) per pair shared by every instance, rebuilt only at a new pair (every frame with
-- gsa1_set_view_smooth 1); drawn from ENT:Draw / DrawTranslucent - the opaque batches in the depth pass with the depth
-- material, nothing blended there; the Dreamcast logo drawn by code (no file read) on the Extra Life panel without a
-- character, the face with one; the window migration 64 / 32 -> 128 / 48 once (the ConVar holds up to 200, review R.9);
-- the context menu's hover outline and the halo's silhouette (11.1); a fault: outlines, then cleared and made again.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_objview_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files and the spawn-menu tab
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_objects%.lua$") or n == "cl_objview.lua" or n == "cl_objicons.lua" or n == "cl_spawntab.lua" then
                keep[#keep + 1] = n
            end
        end
        return keep
    end
    return out
end

-- GMod functions the mock lacks ---------------------------------------------------------------------------------------------
SOLID_OBB, RENDERGROUP_TRANSLUCENT, COLLISION_GROUP_NONE, TRANSMIT_ALWAYS = 3, 1, 0, 0
MATERIAL_RT_DEPTH_SEPARATE, TEXTUREFLAGS_CLAMPS, TEXTUREFLAGS_CLAMPT, MATERIAL_FOG_NONE = 1, 4, 8, 0
local VMT = getmetatable(Vector())
function VMT:Dot(v) return self.x * v.x + self.y * v.y + self.z * v.z end
VMT.__div = function(a, k) return Vector(a.x / k, a.y / k, a.z / k) end
local XMT = {}
XMT.__index = XMT
function Matrix()
    return setmetatable({ t = Vector(), a = Angle(0, 0, 0), rot = {} }, XMT)
end
function XMT:Identity() self.t = Vector() self.a = Angle(0, 0, 0) self.rot = {} end
function XMT:SetTranslation(v) self.t = Vector(v) end
function XMT:SetAngles(a) self.a = Angle(a) end
function XMT:Rotate(a) self.rot[#self.rot + 1] = Angle(a) end
function XMT:GetForward() return self.a:Forward() end
function XMT:GetRight() return self.a:Right() end
function XMT:GetUp() return self.a:Up() end
local pushes = {}
cam.PushModelMatrix = function(m) pushes[#pushes + 1] = { t = Vector(m.t), a = Angle(m.a), rot = #m.rot } end
cam.PopModelMatrix = function() end
local wire = { spheres = 0, boxes = 0, solid_spheres = 0, solid_boxes = 0, colors = {} }
render.DrawWireframeSphere = function(p, r, a, b, col) wire.spheres = wire.spheres + 1 wire.colors[#wire.colors + 1] = col end
render.DrawWireframeBox = function() wire.boxes = wire.boxes + 1 end
render.SetColorMaterial = function() end
render.DrawSphere = function() wire.solid_spheres = wire.solid_spheres + 1 end
render.DrawBox = function() wire.solid_boxes = wire.solid_boxes + 1 end
render.GetToneMappingScaleLinear = function() return Vector(1, 1, 1) end
render.SetToneMappingScaleLinear = function() end
render.GetFogMode = function() return 0 end
render.FogMode = function() end
render.Capture = function() return nil end
local polys = 0
surface.DrawPoly = function() polys = polys + 1 end
surface.SetMaterial = function() end
surface.DrawTexturedRect = function() end
surface.CreateFont = function() end
local files_read = {}
local realRead = file.Read
file.Read = function(p, path) files_read[#files_read + 1] = p return realRead(p, path) end
function Material(p) return { name = p, IsError = function() return true end } end
util.CRC = function(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 4294967291 end
    return tostring(h)
end
local cookies = {}
cookie = { GetNumber = function(k, d) return tonumber(cookies[k]) or d end, Set = function(k, v) cookies[k] = v end }
input = { IsButtonDown = function() return false end }
local spawn_list = {}
list = { GetForEdit = function(name) spawn_list[name] = spawn_list[name] or {} return spawn_list[name] end,
         Get = function(name) return spawn_list[name] or {} end }

-- the client's scripted entities --------------------------------------------------------------------------------------------
local EMT = {}
local function new_entity(classes, cls, idx)
    local e = setmetatable({ cls = cls, idx = idx, pos = Vector(), ang = Angle(0, 0, 0), dt = {}, dtn = {} }, {
        __index = function(t, k)
            local c = classes[cls]
            local guard = 0
            while c and guard < 8 do
                local v = rawget(c, k)
                if v ~= nil then return v end
                c = classes[rawget(c, "Base") or ""]
                guard = guard + 1
            end
            return EMT[k]
        end })
    if e.SetupDataTables then e:SetupDataTables() end
    return e
end
function EMT:NetworkVar(typ, slot, name)
    local default = typ == "Bool" and false or (typ == "String" and "" or 0)
    self.dt[name] = default
    self.dtn[name] = self.dtn[name] or {}
    self["Get" .. name] = function(s) return s.dt[name] end
    self["Set" .. name] = function(s, v)
        for _, f in ipairs(s.dtn[name]) do f(s, name, s.dt[name], v) end
        s.dt[name] = v
    end
end
function EMT:NetworkVarNotify(name, fn) table.insert(self.dtn[name], fn) end
function EMT:GetNetworkVars() local t = {} for k, v in pairs(self.dt) do t[k] = v end return t end
function EMT:EntIndex() return self.idx end
function EMT:GetClass() return self.cls end
function EMT:GetPos() return Vector(self.pos) end
function EMT:GetAngles() return Angle(self.ang) end
function EMT:SetModel() end
function EMT:DrawShadow() end
function EMT:SetSolid() end
function EMT:SetCollisionBounds(a, b) self.cbounds = { a, b } end
function EMT:EnableCustomCollisions() end
function EMT:SetRenderBounds() end
function EMT:OBBMins() return Vector(-8, -8, -8) end
function EMT:OBBMaxs() return Vector(8, 8, 8) end

local CCLASSES = {}
local function load_entity(name)
    local src = host_read(M.root .. "/entities/" .. name .. ".lua")
    local fn, err = host_load(src, "cl:" .. name)
    if not fn then error(err) end
    local ENTT = {}
    ENT = ENTT
    fn()
    ENT = nil
    CCLASSES[name] = ENTT
    scripted_ents.Register(ENTT, name)
end
local CENTS, next_idx = {}, 100
local function spawn(cls, pos, ang, vars)
    next_idx = next_idx + 1
    local e = new_entity(CCLASSES, cls, next_idx)
    e.pos, e.ang = Vector(pos), Angle(ang or Angle(0, 0, 0))
    e:SetState(1)
    for k, v in pairs(vars or {}) do e.dt[k] = v end
    CENTS[e.idx] = e
    M.entities[#M.entities + 1] = e
    if e.Initialize then e:Initialize() end
    M.run_hook("NetworkEntityCreated", e)
    return e
end
local function remove(e)
    e.removed = true
    M.run_hook("EntityRemoved", e)
    if e.OnRemove then e:OnRemove() end
end

-- the mock module: the features "objects" 3 and "preview" 1 -----------------------------------------------------------------
local G = M.module({ features = { objects = 3, preview = 1, render = 1 }, archives = { [0] = { 28, 29, 96, 138 } } })
local MOD = { calls = {}, adds = {}, gen = 1, nextId = 1, events = {}, live = {}, copies = {}, nextCopy = 1, emits = 0,
              acc = 0, renders = 0, prepares = 0, faultNext = false, places = 0 }
local function rec(name, ...) MOD.calls[#MOD.calls + 1] = { name, ... } end
local function n_of(name)
    local n = 0
    for _, c in ipairs(MOD.calls) do n = n + (c[1] == name and 1 or 0) end
    return n
end
G.OBJECTS = { RING = 1, O_GRING = 2, ITEMBOX = 3, ITEMBOX_AIR = 4, STATE_PRESENT = 1, STATE_BROKEN = 2, EVENT_GONE = 3,
              EVENT_USERBITS = 4, EVENT_BROKEN = 7, GOPT_ITEM_ICON_LIMIT = 4, DRAW_OBJECT = 0x1000, RING_WINDOW_MAX = 200,
              BOX_WINDOW_MAX = 100, RANGE_MIN_HU = 1600, RANGE_MAX_HU = 12000, VIEW_TAN_MIN = 0.7, VIEW_TAN_MAX = 4,
              HU_PER_UNIT = 4 }
G.PREVIEW = { ROT_NONE = 0, ROT_OUTER = 1, ROT_INNER = 2, MAX = 256, IDLE_PAIRS = 60 }
function G.SetAdd(t, pos, ang, p1, p2, p3, user, st)
    local id = MOD.nextId
    MOD.nextId = MOD.nextId + 1
    MOD.adds[id] = { t = t, user = user }
    rec("SetAdd", id, t, p1, p2, p3, user)
    return id
end
function G.SetUpdate(id) return MOD.adds[id] ~= nil or nil end
function G.SetRemove(id) MOD.adds[id] = nil return true end
function G.SetClear() MOD.adds = {} return 0 end
function G.SetState(id, st, bits, index) rec("SetState", id, st, bits, index) return true end
function G.SetConfig(t) rec("SetConfig", t.ring_window, t.box_window, t.range, t.view_tan) return true end
function G.SetEvents(out)
    out = out or {}
    for i, e in ipairs(MOD.events) do out[i] = e end
    out.count = #MOD.events
    MOD.events = {}
    return out
end
function G.SetGeneration() return MOD.gen, 0, 0 end
function G.ObjectInfo()
    local out = { count = 4 }
    for t = 1, 4 do out[t] = { type = t, available = true, range = 4800 } end
    return out
end
function G.ObjectBounds() return nil end
function G.SetGameOption() return true end
function G.SetLive(id, out)
    out = out or {}
    if MOD.liveFail then return nil, "no such character", "not_found" end
    local n = 0
    for _, l in ipairs(MOD.live) do
        out[2 * n + 1], out[2 * n + 2] = l[1], l[2]
        n = n + 1
    end
    out[2 * n + 1] = nil
    rec("SetLive", id)
    return n, out
end
-- the previews: per type its batches (archive, tex, flags, pass, tris); the Extra Life box's panel is its kind's texture
local PANEL = { [0] = { 2, 31 }, [2] = { 1, 4 }, [3] = { 2, 0 }, [5] = { 2, 1 }, [6] = { 5, 3 }, [7] = { 3, 2 } }
local function batches_of(c)
    local d = c.desc
    if d.type == 1 then return { { 2, 50, 0x106C, 0, 96 } } end
    if d.type == 3 and d.state == 3 then return { { 2, 40, 0x1060, 0, 50 }, { 2, 41, 0x1061, 1, 4 } } end
    local panel = d.params[1] == 6 and PANEL[d.kind] or { 2, 20 + d.params[1] }
    if d.type == 3 then
        return { { 2, 40, 0x1060, 0, 66 }, { 2, 42, 0x1070, 0, 12 }, { panel[1], panel[2], 0x1079, 1, 36 }, { 2, 43, 0x1071, 1, 2 } }
    end
    return { { 2, 44, 0x106C, 0, 60 }, { panel[1], panel[2], 0x1079, 1, 36 }, { 2, 45, 0x1071, 1, 2 } }
end
function G.PreviewTypes()
    return { { type = 1, available = true, rotation = 1, settle = 0 }, { type = 2, available = true, rotation = 2, settle = 0 },
             { type = 3, available = true, rotation = 0, settle = 47 }, { type = 4, available = true, rotation = 1, settle = 23 } }
end
function G.PreviewAdd(d)
    rec("PreviewAdd", d.kind, d.type, d.params[1], d.state)
    if MOD.faultNext then return nil, "the showcase faulted", "fault" end
    if d.kind == 1 or d.kind == 4 or d.kind == 8 then return nil, "no showcase", "unsupported" end
    local id = MOD.nextCopy
    MOD.nextCopy = MOD.nextCopy + 1
    MOD.copies[id] = { desc = { kind = d.kind, type = d.type, params = { d.params[1], d.params[2], d.params[3] },
                                state = d.state }, pairs = 0, rendered = -1 }
    return id
end
function G.PreviewRemove(id) rec("PreviewRemove", id) MOD.copies[id] = nil return true end
function G.PreviewClear()
    local n = 0
    for _ in pairs(MOD.copies) do n = n + 1 end
    MOD.copies = {}
    rec("PreviewClear", n)
    return n
end
function G.PreviewTick(dt)
    rec("PreviewTick", dt)
    if MOD.tickFault then return nil, "faulted", "fault" end
    MOD.acc = MOD.acc + dt
    while MOD.acc >= 1 / 30 do
        MOD.acc = MOD.acc - 1 / 30
        for _, c in pairs(MOD.copies) do c.pairs = c.pairs + 1 end
    end
    return true
end
function G.PreviewRender(id, alpha)
    local c = MOD.copies[id]
    if not c then return nil, "no such preview", "not_found" end
    MOD.renders = MOD.renders + 1
    local changed = (alpha or 1) < 1 or c.rendered ~= c.pairs
    c.rendered = c.pairs
    local n = c.pairs > 0 and #batches_of(c) or 0
    return n, c.pairs, 1, changed
end
function G.PreviewBatches(id, out)
    local c = MOD.copies[id]
    if not c then return nil end
    local list = c.pairs > 0 and batches_of(c) or {}
    for i, b in ipairs(list) do
        local e = out[i] or {}
        out[i] = e
        e.archive, e.tex, e.flags, e.pass, e.tris = b[1], b[2], b[3], b[4], b[5]
        e.src, e.dst, e.wrap, e.prims, e.mat, e.all = 4, 5, 3, 1, 0, b[3]
        e.key = string.format("%d.%d.%X.%d", b[1], b[2], b[3], b[4])
    end
    out.count = #list
    return #list, out
end
function G.PreviewPrepareView(id) MOD.prepares = MOD.prepares + 1 return true end
function G.PreviewEmitBatch(id, i)
    local c = MOD.copies[id]
    local b = c and batches_of(c)[i]
    if not b then return nil, "PreviewEmitBatch(id, batch)" end
    MOD.emits = MOD.emits + 1
    return b[5] * 3
end
function G.PreviewInfo(id)
    local c = MOD.copies[id]
    if not c then return nil, "no such preview", "not_found" end
    local settle = ({ [3] = 47, [4] = 23 })[c.desc.type] or 0
    return c.pairs * 2, c.pairs * 2 >= settle, -12, -12, -12, 12, 12, 12, 1, 96
end
function G.PreviewRingPlaces(kind, t, ang, p1, p2, p3, out)
    MOD.places = MOD.places + 1
    out = out or {}
    local O = GSA1.Objects
    local d = { type = t, count = p1, size = p2, shape = p3 }
    local n = 0
    for _, r in ipairs(O.RingPositions(d, Vector(0, 0, 0), ang)) do
        out[5 * n + 1], out[5 * n + 2], out[5 * n + 3], out[5 * n + 4], out[5 * n + 5] = r.pos.x, r.pos.y, r.pos.z,
            r.record, r.bit
        n = n + 1
    end
    out.count = n
    return n, out
end
function G.PreviewStats() return { copies = 0, tick_ms = 0.2 } end

-- the client through the autorun ---------------------------------------------------------------------------------------------
M.included = {}
local ok_c, err_c = pcall(M.load, "autorun/gsa1_autorun.lua")
local ok_e, err_e = pcall(function()
    load_entity("gsa1_base")
    for _, n in ipairs({ "gsa1_obj_ring", "gsa1_obj_ring_line", "gsa1_obj_ring_circle", "gsa1_obj_itembox",
                         "gsa1_obj_itembox_air" }) do load_entity(n) end
end)
local O = GSA1 and GSA1.Objects
local V = GSA1 and GSA1.ObjView
local loaded = GSA1 and table.concat(GSA1.FeatureFiles or {}, " ") or ""
check(ok_c and ok_e and O ~= nil and V ~= nil and #(GSA1.FeatureFileErrors or {}) == 0 and
    string.find(loaded, "cl_objview.lua", 1, true) ~= nil and CCLASSES.gsa1_base.RenderGroup == RENDERGROUP_BOTH,
    "the files load (%s; %s): feat/cl_objview.lua, the entities' RenderGroup is RENDERGROUP_BOTH (review R.8)",
    ok_c and loaded or tostring(err_c), tostring(err_e or "ok"))
if not (O and V) then return done() end
GSA1.LoadModule()

-- the window migration (review R.9) ---------------------------------------------------------------------------------------
do
    local rw, bw = GetConVar("gsa1_set_ring_window"), GetConVar("gsa1_set_box_window")
    rw:SetString("64")
    bw:SetString("32")
    cookies = {}
    local m1 = O.MigrateWindows()
    local v1, b1 = rw:GetInt(), bw:GetInt()
    rw:SetString("64")
    local m2 = O.MigrateWindows()
    local v2 = rw:GetInt()
    rw:SetString("128")
    check(m1 == true and v1 == 128 and b1 == 48 and m2 == false and v2 == 64 and rw.hi == 200 and bw.hi == 100 and
        rw.v == "128" and GSA1.CONVARS.gsa1_set_ring_window.default == "128",
        "the window's one-time move: a saved 64 / 32 -> %d / %d, the second time a 64 stays (%d); the ConVars hold up to "
        .. "%s / %s (review R.9: not 0.9.4's 70 / 32), default 128", v1, b1, v2, tostring(rw.hi), tostring(bw.hi))
end

-- helpers ---------------------------------------------------------------------------------------------------------------------
local function frame(n)
    for _ = 1, n or 1 do M.frame(1 / 60) end
end
local function adds_of(t)
    local n = 0
    for _, c in ipairs(MOD.calls) do
        if c[1] == "PreviewAdd" and (t == nil or c[3] == t) then n = n + 1 end
    end
    return n
end
local function pics(e)
    local E = V.ents[e.idx]
    return E and E.npics or 0
end
local function draw_count(e, pass, flags)
    pushes = {}
    if pass == 0 then e:Draw(flags) else e:DrawTranslucent(flags) end
    return #pushes
end

-- 1. no character: every entity its picture, one RING description for rings, lines and circles ---------------------------
M.player.pos = Vector(0, 0, 0)
M.view_origin = Vector(0, 0, 64)
local rings = {}
for i = 1, 30 do rings[i] = spawn("gsa1_obj_ring", Vector(100 + 40 * i, 200, 32)) end
local line = spawn("gsa1_obj_ring_line", Vector(0, 600, 32), Angle(0, 0, 0), { Count = 20, Spacing = 40 })
local circ = spawn("gsa1_obj_ring_circle", Vector(0, -600, 32), Angle(0, 0, 0), { Count = 7, Radius = 80 })
local box = spawn("gsa1_obj_itembox", Vector(400, 0, 0.5), Angle(0, 0, 0), { Contents = 3 })
local air = spawn("gsa1_obj_itembox_air", Vector(500, 0, 40), Angle(0, 30, 0), { Contents = 1 })
frame(6)
check(GSA1.Char == nil and V.PlainActive() and adds_of(1) == 1 and adds_of(3) == 1 and adds_of(4) == 1 and
    pics(rings[1]) == 1 and pics(line) == 20 and pics(circ) == 7 and pics(box) == 1 and pics(air) == 1 and MOD.places >= 2,
    "no character: one PreviewAdd of the RING description for 30 Rings, a line of 20 and a circle of 7 (%d), one per box "
    .. "(%d / %d); pictures: a ring 1, the line %d, the circle %d (places from gsa1.PreviewRingPlaces: %d calls), the boxes "
    .. "%d / %d", adds_of(1), adds_of(3), adds_of(4), pics(line), pics(circ), MOD.places, pics(box), pics(air))
-- the drawing: ENT:Draw opaque, DrawTranslucent blended, one model matrix per instance; the static meshes
local np0, np1 = draw_count(line, 0), draw_count(line, 1)
local ap = draw_count(air, 0)
local airRot = pushes[1] and pushes[1].rot or 0
local D = V.descs["1:0:1"]
local meshes = 0
for _, im in pairs(D and D.meshes or {}) do meshes = meshes + 1 end
local e0 = MOD.emits
frame(1)
local e1 = MOD.emits
frame(1)
local e2 = MOD.emits
-- (per frame: at a new pair one emit per batch of each description - ring 1, box 4, air box 3 - and the turned air box,
-- whose batches are sphere-mapped, streamed per instance: 3; never one per ring of the 57 drawn)
check(np0 == 20 and np1 == 20 and ap == 1 and airRot == 1 and D and D.ready and meshes == 1 and e1 - e0 <= 11 and
    e2 - e1 <= 11 and math.min(e1 - e0, e2 - e1) == 3,
    "the line draws its 20 rings in ENT:Draw and DrawTranslucent (one model matrix each: %d / %d), the air box under its "
    .. "rotation and a quarter turn (%d); the RING description has %d static IMesh, rebuilt only at a new pair (emits per "
    .. "frame %d, %d: each description's batches once a pair, the turned air box streamed - never per ring)", np0, np1,
    airRot, meshes, e1 - e0, e2 - e1)

-- a new description draws nothing in its first pair (libsa1): the entity shows its outline meanwhile
do
    local nb = spawn("gsa1_obj_itembox", Vector(-400, 0, 0.5), Angle(0, 0, 0), { Contents = 5 })
    M.T = M.T + 1 / 60
    M.frameNo = M.frameNo + 1
    M.run_hook("Think")
    wire.boxes = 0
    pushes = {}
    nb:DrawTranslucent()
    local outline, drawn = wire.boxes, #pushes
    frame(6)
    wire.boxes = 0
    pushes = {}
    M.frameNo = M.frameNo + 1
    nb:DrawTranslucent()
    check(outline == 1 and drawn == 0 and wire.boxes == 0 and #pushes == 1,
        "a new description's first pair (no draws yet): the box's outline meanwhile (%d), then its picture without the "
        .. "outline (%d picture, %d outline)", outline, #pushes, wire.boxes)
    remove(nb)
end

-- 2. the states: a taken Ring and air box nothing, a broken ground box its base, a line without its taken rings -------------
rings[1]:SetState(0)
air:SetState(0)
box:SetBroken(true)
line:SetTakenBits("05")
frame(4)
check(pics(rings[1]) == 0 and pics(air) == 0 and pics(box) == 1 and V.ents[box.idx].pics[1].D.key == "3:3:3" and
    adds_of(3) == 3 and pics(line) == 18,
    "a taken Ring and a taken air box draw nothing; the broken ground box the broken description (%s); the line without "
    .. "its 2 taken rings (%d pictures)", V.ents[box.idx].pics[1] and V.ents[box.idx].pics[1].D.key or "-", pics(line))
rings[1]:SetState(1)
air:SetState(1)
box:SetBroken(false)
line:SetTakenBits("")

-- 3. a local take hides the picture at once; a refusal brings it back --------------------------------------------------------
do
    local C = { id = 7, kind = 0, title = "Sonic", state = { step = 10 }, drawPos = Vector(0, 0, 0) }
    V.OnEvent({ kind = 3, user = rings[2].idx, type = 1, index = 0, bits = 0 })
    frame(1)
    local hidden = pics(rings[2])
    V.OnEvent({ kind = 4, user = line.idx, type = 2, index = 0, bits = 0x01 })
    frame(1)
    local after = pics(line)
    V.OnRefused(rings[2].idx)
    V.OnRefused(line.idx)
    frame(1)
    check(hidden == 0 and after == 19 and pics(rings[2]) == 1 and pics(line) == 20,
        "this client's own GONE hides the ring's picture before the server's state (%d), a USERBITS a line's ring (%d of "
        .. "20); the server's refusal brings both back (%d, %d)", hidden, after, pics(rings[2]), pics(line))
end

-- 4. gsa1_set_view 0: the outlines only; gsa1_set_view_dist culls -----------------------------------------------------------
RunConsoleCommand("gsa1_set_view", "0")
frame(1)
wire.spheres = 0
M.frameNo = M.frameNo + 1
local off_pics = pics(rings[3])
rings[3]:DrawTranslucent()
local spheres_off = wire.spheres
RunConsoleCommand("gsa1_set_view", "1")
frame(1)
wire.spheres = 0
M.frameNo = M.frameNo + 1
rings[3]:DrawTranslucent()
local spheres_on = wire.spheres
RunConsoleCommand("gsa1_set_view_dist", "1000")
local far = spawn("gsa1_obj_ring", Vector(5000, 0, 32))
frame(2)
local far_pics, near_pics = pics(far), pics(rings[3])
RunConsoleCommand("gsa1_set_view_dist", "8000")
frame(2)
check(off_pics == 0 and spheres_off == 1 and spheres_on == 0 and far_pics == 0 and near_pics == 1 and pics(far) == 1,
    "gsa1_set_view 0: no picture, the outline (%d sphere); 1: the picture without the outline (outlines only while "
    .. "editing, owner answer O7: %d); gsa1_set_view_dist 1000 culls a ring 5,000 HU away (%d), 8000 draws it",
    spheres_off, spheres_on, far_pics)

-- 5. the kind: the Character page's, Super Sonic -> Sonic ----------------------------------------------------------------
do
    RunConsoleCommand("gsa1_character", "knuckles")
    frame(3)
    local k1 = V.kind
    local addK = 0
    for _, c in ipairs(MOD.calls) do if c[1] == "PreviewAdd" and c[2] == 3 then addK = addK + 1 end end
    RunConsoleCommand("gsa1_character", "supersonic")
    frame(3)
    local k2 = V.kind
    RunConsoleCommand("gsa1_character", "sonic")
    frame(3)
    check(k1 == 3 and addK >= 3 and k2 == 0 and n_of("PreviewClear") >= 2,
        "the pictures' kind: the Character page's Knuckles (%s, %d copies of his), Super Sonic (Vs. Perfect Chaos) -> "
        .. "Sonic's (%s); a change clears the copies (%d PreviewClear)", tostring(k1), addK, tostring(k2), n_of("PreviewClear"))
end

-- 6. the Dreamcast logo (owner answer O4): drawn by code, on the Extra Life panel without a character ----------------------
do
    box:SetContents(6)
    files_read = {}
    for _ = 1, 8 do frame(1) end
    local Dx = V.descs["3:6:1"]
    local logoMat = Dx and Dx.logoMats and Dx.logoMats[3]
    local faceMat = Dx and Dx.mats and Dx.mats[3]
    local readIcons = 0
    for _, p in ipairs(files_read) do if string.find(p, "logo", 1, true) or string.find(p, "%.png") then readIcons = readIcons + 1 end end
    -- the panel batch drawn without a character: the logo's material
    local used = {}
    local keepSet = render.SetMaterial
    render.SetMaterial = function(m) used[#used + 1] = m keepSet(m) end
    box:DrawTranslucent()
    render.SetMaterial = keepSet
    local sawLogo = false
    for _, m in ipairs(used) do if m == logoMat then sawLogo = true end end
    check(Dx and Dx.hasLogo and V.logo and V.logo.done and polys > 0 and logoMat and logoMat ~= faceMat and
        string.find(logoMat.name or "", "gsa1_dclogo", 1, true) ~= nil and logoMat.params["$basetexture"] ==
        V.logo.rt:GetName() and sawLogo and readIcons == 0,
        "an Extra Life box without a character: its panel (Sonic's 2:31) drawn with the Dreamcast logo's material %s - a "
        .. "render target painted by code (%d polygons of the orange spiral), no file read (%d)", logoMat and logoMat.name or
        "-", polys, readIcons)
    box:SetContents(3)
end

-- 7. a character: only what its world does not run, the far / edit switches, the hold, the range ------------------------
local C = { id = 7, kind = 0, title = "Sonic", state = { step = 100 }, drawPos = Vector(0, 0, 0) }
GSA1.Char = C
local function step(n)
    for _ = 1, n or 1 do
        C.state.step = C.state.step + 2
        frame(2)
    end
end
local function live_set(list)
    MOD.live = list
end
local rid = function(e) return O.tracked[e.idx] and O.tracked[e.idx].id end
RunConsoleCommand("gsa1_set_range", "1600")
O.RANGE = 1600
-- a far ring (beyond the range) and the box (inside it)
local farRing = spawn("gsa1_obj_ring", Vector(3000, 0, 32))
local nearBox = spawn("gsa1_obj_itembox", Vector(300, 300, 0.5), Angle(0, 0, 0), { Contents = 3 })
live_set({})
step(4)
local far_shown, near_shown = pics(farRing), pics(nearBox)
-- the near box comes into the world: SetLive lists it - the hold while it grows in (47 steps), then no picture
live_set({ { rid(nearBox), 0 } })
step(1)
local hold1 = pics(nearBox)
step(20)                    -- 42 steps
local hold2 = pics(nearBox)
step(4)                     -- 50 steps
local hold3 = pics(nearBox)
-- the far ring: live -> no picture at once (a ring has no hold)
live_set({ { rid(farRing), 0 }, { rid(nearBox), 0 } })
step(1)
local ring_live = pics(farRing)
check(far_shown == 1 and near_shown == 0 and hold1 == 1 and hold2 == 1 and hold3 == 0 and ring_live == 0,
    "with a character (far pictures on): a ring 3,000 HU away that its world does not run has its picture (%d), a box "
    .. "inside the game's range that it does not run none (%d: a full budget, no picture that could not be taken); once "
    .. "SetLive lists the box its picture holds while it grows in (%d after 2 steps, %d after 42, %d after 50: 47 steps), a "
    .. "ring none at once (%d)", far_shown, near_shown, hold1, hold2, hold3, ring_live)
-- a broken box: no hold
nearBox:SetBroken(true)
live_set({})
step(1)
live_set({ { rid(nearBox), 0 } })
step(1)
local broken_hold = pics(nearBox)
nearBox:SetBroken(false)
-- the air box's hold: 23 steps
live_set({})
local farAir = spawn("gsa1_obj_itembox_air", Vector(3500, 0, 40), Angle(0, 0, 0), { Contents = 2 })
step(2)
live_set({ { rid(farAir), 0 } })
step(10)
local air_hold = pics(farAir)
step(3)
local air_after = pics(farAir)
check(broken_hold == 0 and air_hold == 1 and air_after == 0,
    "no hold for a broken box (%d); the air box holds its picture 23 steps (%d after 20, %d after 26: review R.10)",
    broken_hold, air_hold, air_after)
-- the switches
live_set({})
step(1)
RunConsoleCommand("gsa1_set_view_far", "0")
step(1)
local far_off = pics(farRing)
M.player.active = { GetClass = function() return "weapon_physgun" end }
step(1)
local edit_on = pics(farRing)
RunConsoleCommand("gsa1_set_view_edit", "0")
step(1)
local edit_off = pics(farRing)
M.player.active = nil
RunConsoleCommand("gsa1_set_view_edit", "1")
RunConsoleCommand("gsa1_set_view_far", "1")
step(1)
local back = pics(farRing)
RunConsoleCommand("gsa1_set", "0")
step(1)
local set_off = pics(farRing)
RunConsoleCommand("gsa1_set", "1")
RunConsoleCommand("gsa1_set_draw", "0")
step(1)
local draw_off = pics(farRing)
RunConsoleCommand("gsa1_set_draw", "1")
step(1)
check(far_off == 0 and edit_on == 1 and edit_off == 0 and back == 1 and set_off == 0 and draw_off == 0 and
    pics(farRing) == 1,
    "the switches: far pictures off -> none (%d); the Physics Gun with gsa1_set_view_edit 1 -> the picture (%d), with 0 "
    .. "none (%d); on again %d; gsa1_set 0 -> none (%d), gsa1_set_draw 0 -> none (%d) (review R.17)", far_off, edit_on,
    edit_off, back, set_off, draw_off)
-- a lost event cannot leave a picture on a live record: SetLive is the source (review R.6)
do
    live_set({ { rid(farRing), 0 } })
    step(1)
    local live_now = pics(farRing)
    MOD.events = {}          -- (no SPAWNED / DESPAWNED event at all)
    live_set({})
    step(1)
    local gone_now = pics(farRing)
    check(live_now == 0 and gone_now == 1 and n_of("SetLive") > 10,
        "the running set is gsa1.SetLive's once a pair (%d calls): a live record has no picture (%d) and gets it back when "
        .. "SetLive no longer lists it (%d) - no event needed (review R.6)", n_of("SetLive"), live_now, gone_now)
end
-- the kind follows the character
C.kind = 3
step(2)
local kc = V.kind
C.kind = 8
step(2)
local k8 = V.kind
C.kind = 0
step(2)
check(kc == 3 and k8 == 0, "the pictures' kind follows the character: Knuckles %s, Super Sonic (kind 8) -> Sonic's %s",
    tostring(kc), tostring(k8))
GSA1.Char = nil
frame(2)

-- 8. NOT_FOUND re-adds; the smooth option; the depth views ---------------------------------------------------------------
do
    local Dr = V.descs["1:0:1"]
    local old = Dr and Dr.id
    MOD.copies = {}             -- (a disc reload freed every copy)
    frame(4)
    local Dn = V.descs["1:0:1"]
    check(Dn and Dn.id and Dn.id ~= old and pics(rings[3]) == 1,
        "a NOT_FOUND (a disc reload) re-adds the description (copy %s -> %s)", tostring(old), tostring(Dn and Dn.id))
    RunConsoleCommand("gsa1_set_view_smooth", "1")
    local e0 = MOD.emits
    frame(3)
    local smooth_emits = MOD.emits - e0
    RunConsoleCommand("gsa1_set_view_smooth", "0")
    frame(2)
    local e1 = MOD.emits
    frame(1)
    check(smooth_emits >= 3, "gsa1_set_view_smooth 1 (owner answer O6): the meshes every frame (%d emits in 3 frames); "
        .. "0: only at a new pair", smooth_emits)
    -- the depth pass: the opaque batches with the depth material, nothing blended
    local used = {}
    local keepSet = render.SetMaterial
    render.SetMaterial = function(m) used[#used + 1] = m keepSet(m) end
    local SSAO = STUDIO_SSAODEPTHTEXTURE or 134217728
    pushes = {}
    box:Draw(SSAO)
    local opaqueDepth = #pushes
    local depthMat = used[1]
    pushes = {}
    box:DrawTranslucent(SSAO)
    local blendDepth = #pushes
    render.SetMaterial = keepSet
    check(opaqueDepth == 1 and depthMat and depthMat.shader == "DepthWrite" and blendDepth == 0,
        "the depth pass (STUDIO_SSAODEPTHTEXTURE): the opaque batches with the DepthWrite material (%s), nothing in the "
        .. "blended pass (%d)", depthMat and tostring(depthMat.shader) or "-", blendDepth)
end

-- 9. PreviewTick runs 3 s past the last copy (review R.18) ----------------------------------------------------------------
do
    for _, e in ipairs(M.entities) do if O.IsObject(e) and not e.removed then remove(e) end end
    frame(2)
    local t0 = n_of("PreviewTick")
    for _ = 1, 60 * 4 do frame(1) end           -- 4 s: the copies retire after 3 s ...
    local t1 = n_of("PreviewTick")
    local removed = n_of("PreviewRemove")
    for _ = 1, 60 * 4 do frame(1) end           -- ... and the ticks stop 3 s later
    local t2 = n_of("PreviewTick")
    for _ = 1, 30 do frame(1) end
    local t3 = n_of("PreviewTick")
    check(t1 > t0 and removed >= 3 and t2 > t1 and t3 == t2,
        "after the last object went: the copies removed after 3 s (%d PreviewRemove), PreviewTick still running (%d), "
        .. "stopping 3 s after the last copy (%d -> %d)", removed, t1 - t0, t2, t3)
end

-- 10. the hover outline and the halo's silhouette (11.1) -------------------------------------------------------------------
do
    local hl = spawn("gsa1_obj_ring_line", Vector(0, 900, 32), Angle(0, 0, 0), { Count = 10, Spacing = 40 })
    frame(4)
    vgui.GetHoveredPanel = function() return { IsWorldClicker = function() return true end } end
    properties = { GetHovered = function() return hl end }
    M.player.GetAimVector = function() return Vector(1, 0, 0) end
    M.run_hook("PreDrawHalos")
    RunConsoleCommand("gsa1_set_markers", "0")
    wire.spheres = 0
    hl:DrawTranslucent()
    local hover_spheres = wire.spheres
    local colour = wire.colors[#wire.colors]
    halo = { RenderedEntity = function() return hl end }
    wire.solid_spheres = 0
    pushes = {}
    hl:Draw()
    local solid, picture_in_halo = wire.solid_spheres, #pushes
    halo = nil
    properties = nil
    vgui.GetHoveredPanel = nil
    RunConsoleCommand("gsa1_set_markers", "1")
    check(O.hover.ent == hl and hover_spheres == 10 and colour and colour.b == 255 and solid == 10 and picture_in_halo == 0,
        "the context menu's hover (11.1, UNVERIFIED in game): the hovered line draws its whole outline - its 10 rings (%d), "
        .. "in the pulsing hover colour - even with the outlines off; inside halo.Render its silhouette: %d solid spheres, "
        .. "no picture (%d)", hover_spheres, solid, picture_in_halo)
    remove(hl)
end

-- 11. a fault: the outlines, then cleared and made again -------------------------------------------------------------------
do
    local fr = spawn("gsa1_obj_ring", Vector(50, 50, 32))
    frame(4)
    local before = pics(fr)
    MOD.tickFault = true
    frame(2)
    MOD.tickFault = false
    local working = V.working
    M.frameNo = M.frameNo + 1
    local markers = O.MarkersOn()
    local c0 = n_of("PreviewClear")
    M.T = M.T + 61
    frame(4)
    check(before == 1 and working == false and markers == true and n_of("PreviewClear") > c0 and V.working ~= false and
        pics(fr) == 1,
        "a showcase fault: the pictures stop and the outlines show (markers %s); a minute later PreviewClear and a new "
        .. "copy (pictures %d)", tostring(markers), pics(fr))
end

return done()
