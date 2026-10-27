-- feat_objicons_test.lua - the spawn-menu pictures of the real objects and the G-SA1 tab's icon (round 0.9.4b; sadc
-- docs/research/objects2_plan.md 6.3 task 4 with its Review R.7 / R.19, 11.0 (O4 / O5), 11.2): feat/cl_objicons.lua with
-- feat/cl_objview.lua (the copies, the drawing, the Dreamcast logo), cl_objects.lua (the content type gsa1_object) and
-- cl_spawntab.lua (T.SetIcon) - in Garry's Mod's own LuaJIT against tests/lua_mock.lua, a mock of the module's features
-- "objects" 3 and "preview" 1, a model of a render target's alpha (cleared transparent, drawn opaque), of render.Capture's
-- PNG and of Material("../data/...") / IMaterial:GetColor on it, and of the spawn menu's icons and tab.
--   lua_host tests/feat_objicons_test.lua <tests dir> <addon/lua dir>
-- Checks: the tab's icon is a 16 x 16 silkicon until Sonic's 1-up icon is drawn into a 16 x 16 picture; no disc ->
-- nothing rendered or written; one picture per class per key, each through the read-back check, the PNG written only under
-- data/gsa1/icons with the key in its name and listed in index.json only after its own check; the content type's icons get
-- the picture in place (made before or after the icon); the Extra Life box's picture wears the Dreamcast logo; a failing
-- PNG check deletes the file and keeps the render target only when its read-back passed; a failing read-back and PNG keep
-- G-SA1's drawing; next session a matching index.json gives the PNGs at once, before the disc (review R.19), a PNG whose
-- Material is an error keeps the drawing; a changed key (contents, module version; 0.9.4f: not the character) draws again
-- and deletes the
-- old files - only names of the pattern under data/gsa1/icons (review R.7); a device reset switches to the PNG or draws
-- again; gsa1_set_icons 0 -> G-SA1's drawings, gsa1_set_icons_save 0 -> nothing written; every file.Write under
-- gsa1/icons.
-- 0.9.4d (the owner's 0.9.4b note: the ring pale, the circle tiny, the line not saved): the render targets hold a picture's
-- alpha per pixel by its shape (a disc, a thin ring that misses 0.9.4b's 7 x 7 grid, empty, all opaque, the pale alpha-100
-- disc), the PNG keeps that shape; the framing maths (I.Fit: a cube's distance and the narrowed view, an off-centre box
-- centred) and every class's camera as drawn (85 % filled, centred, the nearest corner beyond Source's depth-in-alpha
-- range; the line of 5, the circle of 7 at 48 HU seen 35-45 degrees from above); the rings taken at a three-quarter moment
-- of their turn (the mock's ring turns 4 degrees a pair in its bounds); the render state of the drawing (no depth in the
-- alpha, the studio cube without local lights, modulation / blend / tone 1, all restored; the ring's material the world
-- draw's); the coverage check (a thin ring kept, an empty, a full and a pale picture refused); the key's I.PICTURES and
-- the old key's files deleted at a session's first key; no key work and no garbage in an idle I.Step.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_objicons_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

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
-- the spawn menu: content types (the sandbox's "entity" icon), the creation tabs, a built menu's tab image
local function new_icon(class)
    local img = { mat = nil, size = nil }
    function img:SetMaterial(m) self.mat = m end
    function img:SetImage(n) self.mat = n end
    function img:SetSize(w, h) self.size = { w, h } end
    local icon = { class = class, Image = img }
    function icon:SetMaterial(n) self.m_MaterialName = n self.Image.mat = n end
    return icon
end
local contentTypes = { entity = function(container, obj)
    local icon = new_icon(obj.spawnname)
    icon:SetMaterial(obj.material)
    return icon
end }
spawnmenu.AddContentType = function(name, fn) contentTypes[name] = fn end
spawnmenu.GetContentType = function(name) return contentTypes[name] end
local creationTabs = {}
spawnmenu.AddCreationTab = function(name, fn, icon, order, tip) creationTabs[name] = { Function = fn, Icon = icon, Order = order } end
spawnmenu.GetCreationTabs = function() return creationTabs end
local function make_icon(class)
    return contentTypes.gsa1_object(nil, { spawnname = class, nicename = class, material = "entities/" .. class .. ".png" })
end

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
-- a ring turns 4 degrees a pair about z (libsa1's measurement, objects2_view.md M1): its bounds follow its turn (diameter
-- RING_D, tube RING_T); MOD.ringTurn: the turn of the ring copies' bounds at their last pair, in degrees
local RING_D, RING_T = 24.6, 4.2
function G.PreviewInfo(id)
    local c = MOD.copies[id]
    if not c then return nil, "no such preview", "not_found" end
    local settle = ({ [3] = 47, [4] = 23 })[c.desc.type] or 0
    if c.desc.type == 1 then
        local b = math.rad((c.pairs * 4 + (MOD.ringPhase or 0)) % 360)
        local ex = RING_D * math.abs(math.cos(b)) + RING_T * math.abs(math.sin(b))
        local ey = RING_D * math.abs(math.sin(b)) + RING_T * math.abs(math.cos(b))
        return c.pairs * 2, true, -ex / 2, -ey / 2, -RING_D / 2, ex / 2, ey / 2, RING_D / 2, 1, 96
    end
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

local I = GSA1.ObjIcons
local T = GSA1.SpawnTab
check(I ~= nil and T ~= nil and string.find(loaded, "cl_objicons.lua", 1, true) ~= nil, "feat/cl_objicons.lua loaded")
if not (I and T) then return done() end

-- a model of render targets' alpha, render.Capture's PNG and Material() / GetColor on it ---------------------------------------
local RT = { cur = nil, stack = {}, state = {}, pushes = {} }
-- 0.9.4d: the render state the pictures are drawn under
local RS = { depthAlpha = true, lightsCleared = false, suppressed = false, cube = {}, mod = { 0.4, 0.5, 0.6 }, blend = 0.3,
       tone = Vector(0.5, 0.5, 0.5), drawsSeen = {}, sets = 0 }
function RS.snapshot()
    local cube = {}
    for i = 0, 5 do cube[i] = RS.cube[i] end
    return { depthAlpha = RS.depthAlpha, lightsCleared = RS.lightsCleared, suppressed = RS.suppressed, cube = cube,
             mod = { RS.mod[1], RS.mod[2], RS.mod[3] }, blend = RS.blend, tone = RS.tone and RS.tone.x }
end
render.SetWriteDepthToDestAlpha = function(b) RS.depthAlpha = b and true or false RS.sets = RS.sets + 1 end
render.SuppressEngineLighting = function(b) RS.suppressed = b and true or false if b then RS.lightsCleared = false end end
render.SetLocalModelLights = function(t) RS.lightsCleared = (t == nil or #t == 0) end
render.ResetModelLighting = function(r, g, b) for i = 0, 5 do RS.cube[i] = r end end
render.SetModelLighting = function(i, r, g, b) RS.cube[i] = r end
render.GetColorModulation = function() return RS.mod[1], RS.mod[2], RS.mod[3] end
render.SetColorModulation = function(r, g, b) RS.mod = { r, g, b } end
render.GetBlend = function() return RS.blend end
render.SetBlend = function(b) RS.blend = b end
render.GetToneMappingScaleLinear = function() return RS.tone end
render.SetToneMappingScaleLinear = function(v) RS.tone = v end
render.PushRenderTarget = function(rt)
    RT.stack[#RT.stack + 1] = RT.cur or false
    RT.cur = rt
    RT.pushes[#RT.pushes + 1] = rt and rt.name or "?"
end
render.PopRenderTarget = function()
    local c = RT.stack[#RT.stack]
    RT.stack[#RT.stack] = nil
    RT.cur = c or nil
end
render.Clear = function() if RT.cur then RT.state[RT.cur.name] = { drawn = false } end end
local usedMats = {}
local keepSetMat = render.SetMaterial
render.SetMaterial = function(m)
    if RT.cur then usedMats[RT.cur.name] = usedMats[RT.cur.name] or {} table.insert(usedMats[RT.cur.name], m) end
    keepSetMat(m)
end
local drawShape = "disc"         -- the shape the next drawing leaves in a render target (below)
local function mark()
    if RT.cur then
        local st = RT.state[RT.cur.name] or {}
        st.drawn = true
        st.shape = drawShape
        RT.state[RT.cur.name] = st
        -- the render state of a picture's drawing (0.9.4d): the depth not in the alpha, the studio light, no local lights
        if string.find(RT.cur.name, "gsa1_icon_", 1, true) then RS.drawsSeen[#RS.drawsSeen + 1] = RS.snapshot() end
    end
end
Mesh = function(mat) return { mat = mat, Draw = function() mark() end, Destroy = function() end } end
local keepEnd = mesh.End
mesh.End = function() mark() keepEnd() end
surface.DrawTexturedRect = function() mark() end
surface.DrawPoly = function() mark() end
local alphaMode, pngMode = "rgba", "ok"
-- 0.9.4d: a picture's alpha per pixel by its SHAPE (what the drawing left in the render target): "disc" (the default: a
-- disc of radius 0.3 x the size around the centre, opaque - an object), "thin" (an annulus 76-80 px around the centre of a
-- 256 x 256 picture: about 3 % of it, between every point of 0.9.4b's 7 x 7 sample grid - the thin rings of a line or
-- circle), "empty" (nothing drawn), "full" (every pixel opaque: a clear that did not work), "half" (the disc at alpha 100:
-- the 0.9.4b pale ring, the view depth in the alpha). drawShape (above) is the shape the next drawing leaves.
local function shape_alpha(shape, x, y, size)
    if shape == "full" then return 255 end
    if shape == "empty" or not shape then return 0 end
    local c = size / 2
    local d = math.sqrt((x - c) ^ 2 + (y - c) ^ 2)
    if shape == "thin" then return (d >= 76 and d <= 80) and 255 or 0 end
    if shape == "half" then return d <= size * 0.3 and 100 or 0 end
    return d <= size * 0.3 and 255 or 0
end
local function rt_shape(st) return (st and st.drawn) and (st.shape or "disc") or "empty" end
local readCalls = 0
render.ReadPixel = function(x, y)
    readCalls = readCalls + 1
    if alphaMode ~= "rgba" then return 0, 0, 0 end
    local st = RT.cur and RT.state[RT.cur.name]
    return 255, 255, 255, shape_alpha(rt_shape(st), x, y, RT.cur and RT.cur.w or 256)
end
local captures = 0
pngReads = 0                     -- IMaterial:GetColor calls on a saved PNG (0.9.4f: 0.9.4d's 16,384 a picture were the lag)
render.Capture = function(t)
    captures = captures + 1
    local st = RT.cur and RT.state[RT.cur.name]
    return "PNG:" .. rt_shape(st) .. ":" .. tostring(t.w or 256) .. ":" .. (RT.cur and RT.cur.name or "screen")
end
function Material(p)
    local rel = string.match(p, "^%.%./data/(.*)$")
    local data = rel and M.files[rel]
    if not data or pngMode == "error" then return { name = p, IsError = function() return true end } end
    local shape, size = string.match(data, "^PNG:(%a+):(%d+):")
    size = tonumber(size) or 256
    return { name = p, IsError = function() return false end, GetColor = function(self, x, y)
        pngReads = pngReads + 1
        -- "opaquebg": a capture that ignored alpha = true (0.9.4f's corner check)
        return Color(255, 255, 255, pngMode == "opaquebg" and 255 or shape_alpha(shape, x, y, size))
    end }
end
-- JSON (a store keyed by the string written: enough for index.json's round trip; a crafted string is a crafted table)
local store = {}
util.TableToJSON = function(t)
    local id = #store + 1
    store[id] = t
    return "json:" .. id
end
util.JSONToTable = function(s)
    local id = tonumber(string.match(s or "", "^json:(%d+)$"))
    return id and store[id] or nil
end
-- every file write and delete
local writes, deletes = {}, {}
local keepWrite, keepDelete = file.Write, file.Delete
file.Write = function(p, s) writes[#writes + 1] = p keepWrite(p, s) end
file.Delete = function(p) deletes[#deletes + 1] = p keepDelete(p) end
MOD.ready = false
function G.IsReady() return MOD.ready end
local function frame(n)
    for _ = 1, n or 1 do M.frame(1 / 60) end
end
local function icon_files()
    local out = {}
    for p in pairs(M.files) do
        if string.match(p, "^gsa1/icons/") and string.match(p, "%.png$") then out[#out + 1] = p end
    end
    table.sort(out)
    return out
end
local function count_pushes(prefix, exact)
    local n = 0
    for _, name in ipairs(RT.pushes) do
        if (exact and name == prefix) or (not exact and string.sub(name, 1, #prefix) == prefix) then n = n + 1 end
    end
    return n
end
-- the pictures' own render targets (cl_textures.lua paints the textures into theirs)
local function icon_pushes() return count_pushes("gsa1_icon_") + count_pushes("gsa1_tabicon_") end
local function writes_ok()
    for _, p in ipairs(writes) do
        if not string.match(p, "^gsa1/icons/[^/]+$") then return false, p end
    end
    return true
end
local CLASSES = { "gsa1_obj_ring", "gsa1_obj_ring_line", "gsa1_obj_ring_circle", "gsa1_obj_itembox", "gsa1_obj_itembox_air" }

-- 1. the tab's icon before anything: 16 x 16; no disc -> nothing drawn or written ----------------------------------------
do
    local tab = creationTabs["G-SA1"]
    frame(30)
    check(tab and tab.Icon == "icon16/coins.png" and T.ICON_SIZE == 16 and icon_pushes() == 0 and #writes == 0 and
        captures == 0,
        "before the disc: the tab's icon is the 16 x 16 silkicon %s (0.9.4a: the 128-pixel ring), nothing rendered (%d) or "
        .. "written (%d)", tab and tostring(tab.Icon) or "-", icon_pushes(), #writes)
end

-- 2. the disc: the tab's icon (Sonic's 1-up icon), then one picture per class once the spawn menu made an icon ----------
MOD.ready = true
frame(40)
local tabPic = I.pics.tab
local tabIcon = creationTabs["G-SA1"].Icon
local tab16 = M.rts["gsa1_tabicon_BGRA8888"] or M.rts["gsa1_tabicon_RGBA8888"]
local tabTex = false
for _, c in ipairs(MOD.calls) do end
for name in pairs(M.rts) do if string.find(name, "_2_31_", 1, true) and string.find(name, "gsa1_", 1, true) then tabTex = true end end
check(tabPic and tab16 and tab16.w == 16 and tab16.h == 16 and type(tabIcon) == "string" and
    string.match(tabIcon, "^%.%./data/gsa1/icons/gsa1_obj_tab_%d+%.png$") ~= nil and tabTex and count_pushes("gsa1_icon_") == 0,
    "the disc: the tab's icon is Sonic's 1-up icon (texture 31 of archive 2 painted: %s) drawn into a 16 x 16 render target "
    .. "(%s x %s) and kept as %s; no class picture before the spawn menu made a G-SA1 icon (%d)", tostring(tabTex),
    tab16 and tostring(tab16.w) or "-", tab16 and tostring(tab16.h) or "-", tostring(tabIcon), count_pushes("gsa1_icon_"))
local ringIcon = make_icon("gsa1_obj_ring")
local boxIcon = make_icon("gsa1_obj_itembox")
frame(240)
local made = 0
for _, c in ipairs(CLASSES) do if I.pics[c] then made = made + 1 end end
local files = icon_files()
local idx = I.ReadIndex()
local key = I.key
local named = true
for _, c in ipairs(CLASSES) do
    local p = I.pics[c]
    named = named and p and p.file and string.find(p.file, "_" .. key, 1, true) ~= nil and string.match(p.file, I.PATTERN)
end
local wok, wbad = writes_ok()
check(made == 5 and I.pics.gsa1_obj_ring.from == "rt" and ringIcon.Image.mat == I.pics.gsa1_obj_ring.mat and
    boxIcon.Image.mat == I.pics.gsa1_obj_itembox.mat and #files == 6 and idx and idx.key == key and named and wok and
    count_pushes("gsa1_icon_gsa1_obj_ring_" .. GSA1.Tex.format.name, true) == 1,
    "the spawn menu's first G-SA1 icon: the five pictures made (one render each), the icons' images replaced in place by the "
    .. "render targets' materials (their read-back passed), %d PNGs under data/gsa1/icons named with the key %s and listed "
    .. "in index.json (key %s); every file.Write under gsa1/icons (%s)", #files, tostring(key), idx and tostring(idx.key) or
    "-", wok and "yes" or tostring(wbad))
local later = make_icon("gsa1_obj_ring_circle")
check(later.Image.mat == I.pics.gsa1_obj_ring_circle.mat,
    "an icon made later (the other tab, a refresh) gets its picture at once")

-- 3. the Extra Life box: the Dreamcast logo; a new key draws again and deletes the old files -------------------------------
do
    local old = icon_files()
    deletes = {}
    RunConsoleCommand("gsa1_set_box_content", "6")
    frame(300)
    local key2 = I.key
    local delOld = 0
    for _, p in ipairs(deletes) do
        for _, o in ipairs(old) do if p == o and string.find(o, "itembox", 1, true) then delOld = delOld + 1 end end
    end
    local logoUsed = false
    for name, list in pairs(usedMats) do
        if string.find(name, "gsa1_icon_gsa1_obj_itembox_", 1, true) then
            for _, m in ipairs(list) do
                if type(m) == "table" and string.find(m.name or "", "gsa1_dclogo", 1, true) then logoUsed = true end
            end
        end
    end
    local boxFile = I.pics.gsa1_obj_itembox and I.pics.gsa1_obj_itembox.file or ""
    check(key2 ~= key and delOld == 2 and #deletes >= 6 and logoUsed and string.find(boxFile, "_c6_", 1, true) ~= nil and
        boxIcon.Image.mat == I.pics.gsa1_obj_itembox.mat,
        "contents 6 (Extra Life): a new key (%s -> %s) - every picture drawn again, the old files deleted (%d, both boxes' "
        .. "among them), the item boxes' pictures wear the Dreamcast logo (owner answer O4: %s) in %s", tostring(key),
        tostring(key2), #deletes, tostring(logoUsed), boxFile)
end

-- 4. a failing PNG check deletes the file and keeps a passing render target; a failing read-back and PNG keep the drawing ----
do
    pngMode = "error"
    deletes, writes = {}, {}
    I.Rebuild()
    frame(300)
    local keptRt = I.pics.gsa1_obj_ring and I.pics.gsa1_obj_ring.from == "rt" and I.pics.gsa1_obj_ring.file == nil
    local deleted = #deletes
    check(keptRt and deleted >= 5 and #writes >= 5,
        "a PNG whose Material is an error: deleted after its check (%d of %d written), the render target - its read-back "
        .. "passed - stays the picture", deleted, #writes)
    alphaMode = "rgb"
    I.pics = {}
    for _, ic in ipairs({ ringIcon, boxIcon }) do ic:SetMaterial("entities/" .. ic.class .. ".png") end
    I.Rebuild()
    frame(300)
    check(I.pics.gsa1_obj_ring == nil and ringIcon.Image.mat == "entities/gsa1_obj_ring.png",
        "render.ReadPixel without alpha and a failing PNG: no picture, the icon keeps G-SA1's drawing (%s)",
        tostring(ringIcon.Image.mat))
    -- 0.9.4f: without alpha from render.ReadPixel the PNG is still written and its own coverage scan passes it (or not)
    pngMode = "ok"
    I.pics = {}
    for _, ic in ipairs({ ringIcon, boxIcon }) do ic:SetMaterial("entities/" .. ic.class .. ".png") end
    I.Rebuild()
    frame(300)
    local fromPng = I.pics.gsa1_obj_ring and I.pics.gsa1_obj_ring.from == "png" and I.pics.gsa1_obj_ring.file ~= nil
    drawShape = "empty"
    I.pics = {}
    for _, ic in ipairs({ ringIcon, boxIcon }) do ic:SetMaterial("entities/" .. ic.class .. ".png") end
    deletes = {}
    I.Rebuild()
    frame(300)
    local emptyRefused = I.pics.gsa1_obj_ring == nil and #deletes >= 5
    drawShape = "disc"
    check(fromPng and emptyRefused, "render.ReadPixel without alpha, the PNG passing its own scan: the picture from the PNG "
        .. "(%s); an empty PNG refused and deleted (%d deletes) - 0.9.4f keeps this fallback", tostring(fromPng), #deletes)
    alphaMode, pngMode = "rgba", "ok"
    I.Rebuild()
    frame(300)
    check(I.pics.gsa1_obj_ring and I.pics.gsa1_obj_ring.file ~= nil, "drawn again with both checks passing")
end

-- 5. a device reset: a render-target picture switches to its PNG -----------------------------------------------------------
do
    M.run_hook("OnScreenSizeChanged")
    check(I.pics.gsa1_obj_ring.from == "png" and ringIcon.Image.mat == I.pics.gsa1_obj_ring.mat,
        "a device reset (a screen size change): the render-target pictures switch to their PNGs (%s)",
        tostring(I.pics.gsa1_obj_ring.from))
    -- one without a PNG is drawn again
    I.pics.gsa1_obj_ring = { mat = I.pics.gsa1_obj_ring.mat, from = "rt" }
    local q0 = #I.queue
    I.DeviceReset("a test")
    check(#I.queue == q0 + 1, "a render-target picture without a PNG is queued to be drawn again")
    frame(60)
end

-- 6. the next session: a matching index.json gives the PNGs at once, before the disc (review R.19) ---------------------------
do
    local keyNow = I.key
    MOD.ready = false
    I.pics, I.key, I.indexTried, I.queue, I.job = {}, nil, nil, {}, nil
    local fresh = make_icon("gsa1_obj_ring")
    local pushes0 = icon_pushes()
    frame(10)
    local fromPng = I.pics.gsa1_obj_ring and I.pics.gsa1_obj_ring.from == "png"
    check(fromPng and fresh.Image.mat == I.pics.gsa1_obj_ring.mat and icon_pushes() == pushes0 and
        string.match(creationTabs["G-SA1"].Icon or "", "gsa1_obj_tab") ~= nil,
        "the next session, before the disc: index.json's key matches - the icons get their PNGs at once (%s), the tab its "
        .. "1-up PNG, nothing rendered", tostring(fromPng))
    -- a deleted file (or an error material) keeps the drawing
    local f = I.pics.gsa1_obj_ring_line and I.pics.gsa1_obj_ring_line.file
    I.pics, I.key, I.indexTried = {}, nil, nil
    if f then M.files["gsa1/icons/" .. f] = nil end
    local lineIcon = make_icon("gsa1_obj_ring_line")
    frame(5)
    check(f ~= nil and I.pics.gsa1_obj_ring_line == nil and lineIcon.Image.mat == "entities/gsa1_obj_ring_line.png" and
        I.pics.gsa1_obj_ring ~= nil,
        "a PNG the owner deleted: that icon keeps G-SA1's drawing (no checkerboard), the others their PNGs")
    MOD.ready = true
    frame(240)
    check(I.key == keyNow and I.pics.gsa1_obj_ring_line ~= nil,
        "with the disc the missing picture is made again (the others stay their PNGs)")
end

-- 7. index.json is a file anyone can edit: only names of the pattern under data/gsa1/icons are deleted ----------------------
do
    M.files["gsa1/icons/gsa1_obj_ok_1.png"] = "PNG:1:x"
    M.files["gsa1/icons/notgsa1.png"] = "PNG:1:x"
    M.files["gsa1/icons/gsa1_obj_x.png.txt"] = "x"
    M.files["gsa1/notes.txt"] = "x"
    M.files[I.INDEX] = util.TableToJSON({ format = 1, key = "crafted", files = { a = "../notes.txt", b = "notgsa1.png",
        c = "gsa1_obj_ok_1.png", d = "gsa1_obj_x.png.txt", e = "gsa1_obj_../../x.png" } })
    deletes = {}
    I.key = "crafted"
    frame(2)
    local only = #deletes == 1 and deletes[1] == "gsa1/icons/gsa1_obj_ok_1.png"
    check(only and M.files["gsa1/icons/notgsa1.png"] ~= nil and M.files["gsa1/notes.txt"] ~= nil and
        M.files["gsa1/icons/gsa1_obj_x.png.txt"] ~= nil,
        "a crafted index.json: of '../notes.txt', 'notgsa1.png', 'gsa1_obj_ok_1.png', 'gsa1_obj_x.png.txt', "
        .. "'gsa1_obj_../../x.png' only gsa1_obj_ok_1.png is deleted (%d deletes: %s)", #deletes, table.concat(deletes, ", "))
    frame(300)
end

-- 8. the module's version is part of the key ---------------------------------------------------------------------------
do
    local k0 = I.key
    G.VERSION = "0.9.4b-test"
    frame(300)
    check(I.key ~= k0 and I.pics.gsa1_obj_ring and string.find(I.pics.gsa1_obj_ring.file or "", I.key, 1, true) ~= nil,
        "a new module version: a new key (%s -> %s), drawn again", tostring(k0), tostring(I.key))
end

-- 9. the switches ------------------------------------------------------------------------------------------------------------
do
    RunConsoleCommand("gsa1_set_icons", "0")
    local p0 = icon_pushes()
    I.Rebuild()
    frame(60)
    check(ringIcon.Image.mat == "entities/gsa1_obj_ring.png" and creationTabs["G-SA1"].Icon == "icon16/coins.png" and
        icon_pushes() == p0,
        "gsa1_set_icons 0: G-SA1's drawings again (%s), the tab's silkicon, nothing rendered", tostring(ringIcon.Image.mat))
    RunConsoleCommand("gsa1_set_icons", "1")
    RunConsoleCommand("gsa1_set_icons_save", "0")
    writes = {}
    I.Rebuild()
    frame(300)
    check(#writes == 0 and I.pics.gsa1_obj_ring and I.pics.gsa1_obj_ring.from == "rt" and
        ringIcon.Image.mat == I.pics.gsa1_obj_ring.mat,
        "gsa1_set_icons_save 0: drawn again into render targets, nothing written (%d writes)", #writes)
    RunConsoleCommand("gsa1_set_icons_save", "1")
end

-- 10. a built spawn menu: the tab's image takes the 16 x 16 picture --------------------------------------------------------
do
    local img = { SetMaterial = function(s, m) s.mat = m end, SetImage = function(s, n) s.mat = n end,
                  SetSize = function(s, w, h) s.w, s.h = w, h end }
    g_SpawnMenu = { CreateMenu = { GetCreationTab = function(self, name)
        if name == "G-SA1" then return { Tab = { Image = img, InvalidateLayout = function() end } } end
    end } }
    local ok = I.ApplyTab(I.pics.tab)
    check(ok and img.mat ~= nil and img.w == 16 and img.h == 16,
        "a built spawn menu: the G-SA1 tab's image gets the 1-up picture at 16 x 16 (%s x %s)", tostring(img.w), tostring(img.h))
    g_SpawnMenu = nil
end

-- 11. 0.9.4d: the colour, the framing, the check, the key ---------------------------------------------------------------------
-- the camera of each picture (cam.Start3D inside a picture's render target) and the ring's turn at that moment
local starts, crcCalls = {}, 0
cam.Start3D = function(eye, ang, fov, x, y, w, h, near, far)
    if RT.cur and string.find(RT.cur.name, "gsa1_icon_", 1, true) then
        local D = V.descs["1:0:1"]
        local aspect = nil
        if D and D.id then
            local _, _, x0, y0, z0, x1, y1, z1 = G.PreviewInfo(D.id)
            aspect = (y1 - y0) / (z1 - z0)
        end
        starts[RT.cur.name] = { eye = Vector(eye), ang = Angle(ang), fov = fov, near = near, far = far, aspect = aspect }
    end
end
local keepCRC = util.CRC
util.CRC = function(s) crcCalls = crcCalls + 1 return keepCRC(s) end
local function rt_of(class) return "gsa1_icon_" .. class .. "_" .. GSA1.Tex.format.name end
-- the bounds of a class's picture as the test sees them: each ring's place +- I.RING_R, a box's PreviewInfo bounds
local function class_bounds(class)
    local inst = I.Instances(class)
    if not inst then return nil end
    local mn, mx = Vector(1e9, 1e9, 1e9), Vector(-1e9, -1e9, -1e9)
    for _, it in ipairs(inst) do
        local r = it.r or 12
        mn = Vector(math.min(mn.x, it.pos.x - r), math.min(mn.y, it.pos.y - r), math.min(mn.z, it.pos.z - (it.r or 12)))
        mx = Vector(math.max(mx.x, it.pos.x + r), math.max(mx.y, it.pos.y + r), math.max(mx.z, it.pos.z + r))
    end
    return mn, mx, #inst, inst
end
-- the share of the picture's half size the farthest corner reaches, and the nearest corner's depth, for a camera
local function framing(mn, mx, cam)
    local f, r, u = cam.ang:Forward(), cam.ang:Right(), cam.ang:Up()
    local t = math.tan(math.rad(cam.fov / 2))
    local most, nearest = 0, math.huge
    local cx, cy = 0, 0
    local xs, ys = {}, {}
    for i = 0, 7 do
        local p = Vector(i % 2 == 0 and mn.x or mx.x, math.floor(i / 2) % 2 == 0 and mn.y or mx.y, i < 4 and mn.z or mx.z)
        local v = Vector(p.x - cam.eye.x, p.y - cam.eye.y, p.z - cam.eye.z)
        local z = v:Dot(f)
        local sx, sy = v:Dot(r) / z / t, v:Dot(u) / z / t
        xs[#xs + 1], ys[#ys + 1] = sx, sy
        most = math.max(most, math.abs(sx), math.abs(sy))
        nearest = math.min(nearest, z)
    end
    local function mid(a) return (math.min(unpack(a)) + math.max(unpack(a))) / 2 end
    return most, nearest, mid(xs), mid(ys)
end

-- (a) the framing maths: a cube of half size 10 seen along +x with a 60-degree view fills 85 % at 30.38 HU; with the
-- nearest corner at least 50 HU away the eye goes back to 60 HU and the view narrows to 26.5 degrees
if not (I.Fit and I.Coverage and I.CoverageOK) then
    check(false, "0.9.4d's I.Fit, I.Coverage and I.CoverageOK exist")
    I.Fit = function() return Vector(), 0, 0, 0, 0 end
    I.Coverage = function() return nil end
    I.CoverageOK = function() return false end
end
do
    local eye, d, fov = I.Fit(Vector(-10, -10, -10), Vector(10, 10, 10), Angle(0, 0, 0), 60, 0.85, 0)
    local k = 0.85 * math.tan(math.rad(30))
    local want = 10 / k + 10
    local eye2, d2, fov2, near2 = I.Fit(Vector(-10, -10, -10), Vector(10, 10, 10), Angle(0, 0, 0), 60, 0.85, 50)
    local want2 = 2 * math.deg(math.atan((10 / 50) / 0.85))
    check(math.abs(d - want) < 0.01 and math.abs(eye.x + want) < 0.01 and math.abs(eye.y) < 1e-6 and math.abs(fov - 60) < 1e-9
        and math.abs(d2 - 60) < 0.01 and math.abs(fov2 - want2) < 0.01 and near2 > 0 and near2 <= I.NEAR,
        "I.Fit: a cube of half size 10 along +x at 60 degrees: the eye %.2f HU back (expected %.2f), 85 %% filled; with the "
        .. "nearest corner 50 HU away: %.2f HU and %.2f degrees (expected 60 and %.2f), near plane %.2f", d, want, d2, fov2,
        want2, near2 or -1)
    -- an off-centre box (a tall one seen from above) is centred: the projection's middle on the picture's centre
    local eye3, d3, fov3 = I.Fit(Vector(-5, -30, 0), Vector(25, 10, 80), Angle(30, 45, 0), 30, 0.85, 0)
    local most, nearest, mxp, myp = framing(Vector(-5, -30, 0), Vector(25, 10, 80), { eye = eye3, ang = Angle(30, 45, 0),
        fov = fov3 })
    check(math.abs(most - 0.85) < 0.01 and math.abs(mxp) < 0.01 and math.abs(myp) < 0.01,
        "I.Fit: an off-centre box seen from above at 45 degrees fills %.1f %% of the picture's half size, centred (%.3f, %.3f)",
        most * 100, mxp, myp)
end

-- (b) every class's picture as drawn: the bounds fill about 85 %, centred, the nearest corner beyond Source's depth-in-alpha
-- range; the line has 5 rings, the circle 7 at radius 48, the rings' camera along x, the circle seen 35-45 degrees from above
do
    I.Rebuild()
    frame(300)
    local lines, ok = {}, true
    for _, class in ipairs(CLASSES) do
        local cam = starts[rt_of(class)]
        local mn, mx, n = class_bounds(class)
        if not (cam and mn) then
            ok = false
            lines[#lines + 1] = class .. ": no camera"
        else
            local most, nearest, mxp, myp = framing(mn, mx, cam)
            local good = most > 0.83 and most < 0.851 and math.abs(mxp) < 0.02 and math.abs(myp) < 0.02 and
                nearest >= I.NEAR_MIN - 0.01 and cam.near <= I.NEAR and cam.far > nearest
            ok = ok and good
            lines[#lines + 1] = string.format("%s: %d, %.0f degrees at %.0f HU, %.1f %% filled, nearest corner %.0f HU%s",
                class, n, cam.fov, (cam.eye - (mn + mx) * 0.5):Length(), most * 100, nearest, good and "" or " (BAD)")
        end
    end
    local _, _, nLine = class_bounds("gsa1_obj_ring_line")
    local _, _, nCircle, ci = class_bounds("gsa1_obj_ring_circle")
    local r = ci and ci[1] and math.sqrt(ci[1].pos.x ^ 2 + ci[1].pos.y ^ 2) or 0
    local ringCam, circleCam = starts[rt_of("gsa1_obj_ring")], starts[rt_of("gsa1_obj_ring_circle")]
    check(ok and nLine == 5 and nCircle == 7 and math.abs(r - 48) < 0.01 and ringCam and ringCam.ang.y == 0 and
        ringCam.fov < 10 and circleCam and circleCam.ang.p >= 35 and circleCam.ang.p <= 45,
        "the pictures' cameras (bounds -> distance per class): %s; the line 5 rings, the circle %d at radius %.1f",
        table.concat(lines, "; "), nCircle or 0, r)
    -- (c) the ring classes waited for the three-quarter moment of the rings' turn
    local asp = {}
    local face = I.FACE or { 0.72, 0.90 }
    local good = I.FACE ~= nil
    for _, class in ipairs({ "gsa1_obj_ring", "gsa1_obj_ring_line", "gsa1_obj_ring_circle" }) do
        local a = starts[rt_of(class)] and starts[rt_of(class)].aspect
        good = good and a ~= nil and a >= face[1] and a <= face[2]
        asp[#asp + 1] = string.format("%s %.2f", class, a or -1)
    end
    check(good, "the rings are pictured at a three-quarter moment of their turn (width / height %.2f-%.2f): %s", face[1],
        face[2], table.concat(asp, ", "))
end

-- (d) the colour: drawn with the depth kept out of the alpha, the studio light (the ambient cube, no local lights),
-- colour modulation, blend and tone-mapping scale 1 - each restored after; the ring's material is the world draw's
do
    local seen, bad = 0, nil
    for _, s in ipairs(RS.drawsSeen) do
        seen = seen + 1
        local cube = s.cube
        local lightOk = s.suppressed and s.lightsCleared and cube[4] == 1 and cube[0] == 0.9 and cube[1] == 0.9 and
            cube[2] == 0.9 and cube[3] == 0.9 and cube[5] == 0.6
        if not (s.depthAlpha == false and lightOk and s.mod[1] == 1 and s.mod[2] == 1 and s.mod[3] == 1 and s.blend == 1 and
                s.tone == 1) and not bad then
            bad = string.format("depth in alpha %s, light %s, modulation %s %s %s, blend %s, tone %s", tostring(s.depthAlpha),
                tostring(lightOk), tostring(s.mod[1]), tostring(s.mod[2]), tostring(s.mod[3]), tostring(s.blend),
                tostring(s.tone))
        end
    end
    local restored = RS.depthAlpha == true and RS.mod[1] == 0.4 and RS.mod[2] == 0.5 and RS.mod[3] == 0.6 and RS.blend == 0.3
        and RS.tone and RS.tone.x == 0.5 and not RS.suppressed
    -- the ring's batch as a character's world draws it (the mock's: archive 2, texture 50, the ring's flags 0x106C)
    local ringBatch = { archive = 2, tex = 50, flags = 0x106C, pass = 0, tris = 96, src = 4, dst = 5, wrap = 3, prims = 1,
                        key = string.format("%d.%d.%X.%d", 2, 50, 0x106C, 0) }
    local worldMat = GSA1.Tex.Material(0, ringBatch)
    local used = false
    for _, m in ipairs(usedMats[rt_of("gsa1_obj_ring")] or {}) do if m == worldMat then used = true end end
    check(seen > 0 and bad == nil and restored and used,
        "the pictures are drawn (%d draws) with render.SetWriteDepthToDestAlpha(false), the studio cube (top 1, sides 0.9, "
        .. "below 0.6) and no local lights, modulation / blend / tone 1%s; afterwards restored (%s); the ring with the world "
        .. "draw's material (%s)", seen, bad and (" - NOT: " .. bad) or "", tostring(restored), tostring(used))
end

-- (e) the check: coverage over the whole picture - a thin ring passes (0.9.4b's 7 x 7 grid saw nothing of it), an empty
-- picture, a full one (the clear failed) and the pale one (alpha 100) fail
do
    local function cov(shape) return I.Coverage(function(x, y) return shape_alpha(shape, x, y, 256) end, 256) end
    local tOp, tCl = cov("thin")
    local eOp, eCl = cov("empty")
    local fOp, fCl = cov("full")
    local hOp, hCl = cov("half")
    local gridHits = 0
    for sy = 1, 7 do
        for sx = 1, 7 do
            if shape_alpha("thin", math.floor(sx * 256 / 8), math.floor(sy * 256 / 8), 256) > 0 then gridHits = gridHits + 1 end
        end
    end
    check(I.CoverageOK(tOp, tCl) and not I.CoverageOK(eOp, eCl) and not I.CoverageOK(fOp, fCl) and
        not I.CoverageOK(hOp, hCl) and gridHits == 0,
        "I.Coverage: a thin ring %.1f %% opaque - passes (0.9.4b's 7 x 7 grid: %d of 49 points on it); empty %.1f %%, a "
        .. "failed clear %.1f %% clear, the pale picture (alpha 100) %.1f %% opaque - each refused", (tOp or 0) * 100, gridHits,
        (eOp or 0) * 100, (fCl or 0) * 100, (hOp or 0) * 100)
    -- in the job: thin rings are kept (render target and PNG), an empty and a pale picture keep G-SA1's drawing
    drawShape = "thin"
    I.Rebuild()
    frame(300)
    local thinOk = I.pics.gsa1_obj_ring_line and I.pics.gsa1_obj_ring_line.from == "rt" and I.pics.gsa1_obj_ring_line.file and
        I.pics.gsa1_obj_ring_circle and I.pics.gsa1_obj_ring_circle.file
    for _, shape in ipairs({ "empty", "half" }) do
        drawShape = shape
        I.pics = {}
        ringIcon:SetMaterial("entities/gsa1_obj_ring.png")
        deletes = {}
        local w0 = #writes
        I.Rebuild()
        frame(300)
        local pngs = 0
        for i = w0 + 1, #writes do
            -- an object's picture (the tab's own icon, Sonic's 1-up, is not one: it is written with every rebuild)
            if string.find(writes[i], "%.png$") and not string.find(writes[i], "gsa1_obj_tab_", 1, true) then pngs = pngs + 1 end
        end
        -- 0.9.4f hot fix: a picture whose render-target check fails (its alpha read back) is never written as a PNG
        thinOk = thinOk and I.pics.gsa1_obj_ring == nil and ringIcon.Image.mat == "entities/gsa1_obj_ring.png" and pngs == 0
    end
    drawShape = "disc"
    I.Rebuild()
    frame(300)
    check(thinOk and I.pics.gsa1_obj_ring ~= nil,
        "in the job: thin rings kept as render target and PNG; an empty and a pale picture refused - no PNG written for them "
        .. "(0.9.4f), G-SA1's drawing stays; drawn again afterwards")
-- 0.9.4f hot fix: changing character does not change the pictures' key (no remaking of every picture: owner, 1 fps)
do
    local V = GSA1.ObjView
    local keep = V and V.KindNow
    local k1, k2
    if V then
        V.KindNow = function() return 0 end
        k1 = I.Key()
        V.KindNow = function() return 3 end
        k2 = I.Key()
        V.KindNow = keep
    end
    check(V == nil or (k1 ~= nil and k1 == k2), "the pictures' key does not follow the character (%s / %s)", tostring(k1),
        tostring(k2))
    check(I.COVER_STEP >= 8, "the render-target check reads at most 1,024 pixels (step %d)", I.COVER_STEP)
    -- end to end: a character change (the showcase kind: cl_objview's V.Think clears its copies) neither changes the key
    -- nor draws a picture again
    local keyBefore, capBefore, errBefore = I.key, captures, #M.reported
    local kindNow = 0
    local kindKeep = V and V.KindNow
    if V then V.KindNow = function() return kindNow end end
    for _, kind in ipairs({ 3, 5, 0 }) do
        kindNow = kind
        frame(60)
    end
    check(V ~= nil and keyBefore ~= nil and I.key == keyBefore and captures == capBefore and I.job == nil and
        #I.queue == 0 and #M.reported == errBefore,
        "end to end: Knuckles, Big, Sonic in turn - the key stays (%s / %s), no picture made again (%d captures), no error",
        tostring(keyBefore), tostring(I.key), captures - capBefore)
    -- a character change while a picture waits starts its wait again; a kind that never settles still ends it
    local keepReady = I.InstancesReady
    I.InstancesReady = function() return false end
    local waited0 = I.stats.waited
    kindNow = 0
    I.Rebuild()
    frame(2)
    local job = I.job
    local part = math.floor(I.WAIT_MAX * 0.8 * 60)
    frame(part)
    kindNow = 3
    frame(part)
    local kept = job ~= nil and I.job == job and I.stats.waited == waited0
    for i = 1, math.floor(I.WAIT_MAX * 2.5 * 60) do
        kindNow = (i % 2 == 0) and 3 or 5
        frame(1)
        if I.stats.waited > waited0 then break end
    end
    local ended = I.stats.waited > waited0
    I.InstancesReady = keepReady
    kindNow = 0
    if V then V.KindNow = kindKeep end
    check(kept and ended, "a character change while a picture waits: its wait starts again (still waiting after 1.6 x "
        .. "I.WAIT_MAX: %s); a kind that never settles: the wait still ends (%s)", tostring(kept), tostring(ended))
    -- the PNG's corner check: a capture that ignored alpha (an opaque background) is deleted, the render target kept
    pngMode = "opaquebg"
    I.pics = {}
    deletes = {}
    I.Rebuild()
    frame(300)
    local cornerOk = I.pics.gsa1_obj_ring and I.pics.gsa1_obj_ring.from == "rt" and I.pics.gsa1_obj_ring.file == nil and
        #deletes >= 5
    pngMode = "ok"
    check(cornerOk, "a PNG with an opaque background (a capture that ignored alpha): deleted after its corner check (%d "
        .. "deletes), the render target stays the picture", #deletes)
    -- the reads of a whole rebuild: 1,024 render.ReadPixel a picture, a PNG's corners only (no scan with alpha)
    readCalls, pngReads = 0, 0
    local cap0 = captures
    I.Rebuild()
    frame(300)
    local n = #I.Classes()
    check(captures - cap0 >= n and readCalls >= n * 1024 and readCalls <= n * 1024 + 64 and pngReads >= n * 4 and
        pngReads <= n * 4 + 64,
        "a whole rebuild of %d pictures (%d captures): %d render.ReadPixel (at most %d), %d PNG reads (0.9.4e: about "
        .. "16,384 a picture)", n, captures - cap0, readCalls, n * 1024 + 64, pngReads)
end
end

-- (f) the key: I.PICTURES is part of it; a session whose first key differs from index.json's deletes the files that index
-- lists (the owner's 0.9.4b / 0.9.4c pale pictures) and draws them again
do
    local k2 = I.Key()
    local keepP = I.PICTURES
    I.PICTURES = 1
    local k1 = I.Key()
    I.PICTURES = keepP
    local old = { "gsa1_obj_ring_4207846940.png", "gsa1_obj_ring_circle_4207846940.png", "gsa1_obj_tab_4207846940.png" }
    for _, f in ipairs(old) do M.files["gsa1/icons/" .. f] = "PNG:half:256:old" end
    M.files[I.INDEX] = util.TableToJSON({ format = 1, gen = 0, key = "4207846940", files = { gsa1_obj_ring = old[1],
        gsa1_obj_ring_circle = old[2], tab = old[3] } })
    MOD.ready = false
    I.pics, I.key, I.indexTried, I.queue, I.job = {}, nil, nil, {}, nil
    frame(5)
    local kept = M.files["gsa1/icons/" .. old[1]] ~= nil
    deletes = {}
    MOD.ready = true
    frame(300)
    local gone = 0
    for _, f in ipairs(old) do if M.files["gsa1/icons/" .. f] == nil then gone = gone + 1 end end
    local idx = I.ReadIndex()
    check(k1 ~= k2 and kept and gone == 3 and idx and idx.key == I.key and I.pics.gsa1_obj_ring and
        string.find(I.pics.gsa1_obj_ring.file or "", I.key, 1, true) ~= nil,
        "the key carries I.PICTURES (%s -> %s); a session starting with an index.json of another key: its PNGs kept before "
        .. "the disc (%s), deleted with the disc (%d of 3), every picture drawn again under the key %s", tostring(k1),
        tostring(k2), tostring(kept), gone, tostring(I.key))
end

-- (g) idle: once the pictures are made, a frame makes no key (no string, no CRC) and no Lua garbage in I.Step (under
-- a byte a frame on average)
do
    frame(10)
    local c0 = crcCalls
    for _ = 1, 300 do I.Step() end             -- (LuaJIT compiles its traces first: a trace is a GC object too)
    collectgarbage("collect")
    collectgarbage("stop")
    local k0 = collectgarbage("count")
    for _ = 1, 1000 do I.Step() end
    local bytes = (collectgarbage("count") - k0) * 1024
    collectgarbage("restart")
    check(#I.queue == 0 and not I.job and crcCalls == c0 and bytes < 1000,
        "idle: 1,300 frames of I.Step with every picture made - %d key computations, %.2f bytes of Lua garbage a frame "
        .. "(0.9.4b: a string and a CRC every frame, about 110 bytes)", crcCalls - c0, bytes / 1000)
end
-- 0.9.4d verifier: pictures of older keys that no index lists are deleted; this key's and other names are kept
do
    local keepFind = file.Find
    local listing = { "gsa1_obj_ring_4207846940.png", "gsa1_obj_ring_circle_4207846940.png", "gsa1_obj_ring_777.png",
        "gsa1_obj_tab_777.png", "gsa1_obj_itembox_c3_777.png", "notes.png" }
    file.Find = function(pat, path)
        if path == "DATA" and pat == I.DIR .. "/*.png" then return listing, {} end
        return keepFind(pat, path)
    end
    local d0 = #deletes
    local n = I.DeleteOrphans("777")
    file.Find = keepFind
    local got = {}
    for i = d0 + 1, #deletes do got[#got + 1] = deletes[i] end
    table.sort(got)
    check(n == 2 and #got == 2 and got[1] == "gsa1/icons/gsa1_obj_ring_4207846940.png" and
        got[2] == "gsa1/icons/gsa1_obj_ring_circle_4207846940.png",
        "older keys' pictures no index lists: the 2 of key 4207846940 deleted, this key's 3 and a foreign name kept (%s)",
        table.concat(got, " "))
end
local wok2, wbad2 = writes_ok()
check(wok2, "every file.Write of the run under garrysmod/data/gsa1/icons (%s)", wok2 and "yes" or tostring(wbad2))
return done()
