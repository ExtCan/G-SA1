-- feat_objects_test.lua - the objects feature's addon side (round 0.9.4: spawnable Rings and Item Boxes; sadc
-- docs/research/gsa1_094_plan.md 6.5 with its Review R.1 / R.3 / R.15 / R.17): feat/sh_objects.lua, cl_objects.lua,
-- sv_objects.lua, the entities addon/lua/entities/gsa1_base.lua and gsa1_obj_*.lua, the patches in cl_render.lua,
-- cl_collision.lua, feat/cl_interact.lua and feat/sv_interact.lua - in Garry's Mod's own LuaJIT: the client through the
-- autorun against tests/lua_mock.lua and a mock of the module's object functions (every call recorded); the server's
-- files in their own environment with a small model of Garry's Mod's scripted entities (NetworkVars with their
-- notifications, Edit tables, the duplicator's GetNetworkVars / RestoreNetworkVars, physics boxes), each server entity
-- networked to a client copy at once, and net messages delivered at once between the realms.
--   lua_host tests/feat_objects_test.lua <tests dir> <addon/lua dir>
-- Checks: the five classes (Spawnable in "G-SA1", gsa1_object icons, Edit tables, the nine contents 0..8, Count limits
-- line 128 / circle 128) and the base; a copy's NetworkVars (editable values kept, runtime state fresh); the placement (the
-- placer's contents userinfo, the default respawn time, the surface heights, the limit, gsa1_sv_set 0, "Undone G-SA1
-- <name>"); the client: one SetAdd per entity with the right type and parameters (a line of 20 = 3 records of 8 / 8 / 4),
-- Contents -> SetUpdate, State 0 -> SetState(0), a Physics Gun drag -> one SetUpdate once still / at the drop, removal ->
-- SetRemove, gsa1_set 0 -> SetClear, a new module generation -> added again, the window from the sliders; the events: a
-- GONE of the local world -> one report, a ground box's GONE -> sent as BROKEN, another world's -> not sent; the server:
-- the LSD and spin-dash cases (GONE 128-708 HU from the ring when it arrives) accepted, a touch 1,000 HU from the path
-- refused, Big's body break at 62 HU and E-102's projectile break (shot 20 HU from the box, E-102 1,000 HU away) accepted, a
-- body break 300 HU away refused, a Magnetic Barrier ring 193 HU away accepted as MAGNET and refused as BODY (review R.3),
-- illegal / repeated / unknown reports and a non-character sender refused, the rate limit, gsa1_sv_set 0, the
-- GSA1ObjectEvent hook; a refusal sends the state back and the client's world gets the object again; respawn: a Ring after
-- its time, a ground box whole again, a group's bits cleared by "Reset G-SA1 objects" (refused for a non-admin); the
-- render through GSA1.DrawCharacter (review R.1): first person draws the OBJECT batches only (0.9.3a: nothing), with
-- gsa1_effects 0 too, not with gsa1_set_draw 0, third person unchanged for the other batches, the render bounds cover an
-- object 1,500 HU away; the three scanners ignore a G-SA1 object; every setting has a control on the Objects page; an
-- unavailable type is refused with a message and left out of the spawn menu; every new character gets the icon guard.
-- 0.9.4.1 (section 13): THE OWNER'S REFUSED REPORTS replayed (a line's and a circle's USERBITS whose touch is the record's
-- latest ring, 105-226 HU from the rings they add: accepted; a touch at the true ring place accepted; a touch far from
-- every ring of the record, and a claimed ring the path never passed, refused); 128-ring lines and circles (records,
-- masks, the evenly spaced places, golden places shared with feat_objects_test.cpp, the shared state TakenBits through
-- a report, a refusal, a client's SetState of record 100, a respawn and a reset); THE PICK HULL (its extents per class
-- and size, SOLID_OBB with custom collisions in COLLISION_GROUP_WORLD on the server and the client copy, a physics box
-- clamped to 2048, TestCollision: a Physics Gun / Tool Gun ray hits the whole oriented hull, a bullet's ray and a hull
-- trace pass, the context menu's ray hits on the client, PhysgunPickup allowed, OnPhysgunPickup lets it move, the drop
-- freezes it, anything else that unfreezes it is undone within 0.1 s, a layout change while carried is rebuilt after the
-- drop, the context menu's "collision" property refused).
-- 0.9.4b (objects2_plan.md 6.3 task 5, section 7, 11.0 / 11.2; feature "objects" 3): the window's first SetConfig carries
-- the new defaults 128 / 48, the range in HU (gsa1_set_range 4,800) and view_tan from the mocked fov / ScrW / ScrH (3440 x
-- 1440 at 92.5: 1.873 +-0.005), sent again when the range changes, 0 with gsa1_set_view_wide 0; the page's sliders reach
-- gsa1.OBJECTS' maxima (rings 200, boxes 100, range 12,000 HU) and every new setting has its control (the Redraw button
-- too); the debug sphere has gsa1_set_range's radius; the G-SA1 tab's icon is a 16 x 16 silkicon (11.2).
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_objects_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files, the interaction feature's (its scanners are checked) and the spawn-menu tab (0.9.4a)
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_objects%.lua$") or string.find(n, "_interact%.lua$") or n == "cl_spawntab.lua" then
                keep[#keep + 1] = n
            end
        end
        return keep
    end
    return out
end

-- GMod constants and helpers the mock lacks ----------------------------------------------------------------------------------
SOLID_VPHYSICS, MOVETYPE_VPHYSICS, MOVETYPE_NONE, TRANSMIT_ALWAYS = 6, 6, 0, 0
SOLID_BBOX, SOLID_OBB = 2, 3
RENDERGROUP_TRANSLUCENT, COLLISION_GROUP_NONE = 1, 0
MOVETYPE_NOCLIP, MOVETYPE_WALK, MASK_SOLID, IN_USE = 8, 2, 33570827, 32
D_HT, D_FR, D_LI, D_NU = 1, 2, 3, 4
local VMT = getmetatable(Vector())
function VMT:Dot(v) return self.x * v.x + self.y * v.y + self.z * v.z end
function VMT:DistToSqr(v) local d = self - v return d:Dot(d) end
VMT.__div = function(a, k) return Vector(a.x / k, a.y / k, a.z / k) end
local AMT = getmetatable(Angle())
local wire = { spheres = 0, boxes = 0 }
render.DrawWireframeSphere = function() wire.spheres = wire.spheres + 1 end
render.DrawWireframeBox = function() wire.boxes = wire.boxes + 1 end
surface.CreateFont = function() end
input = { IsButtonDown = function() return false end, LookupBinding = function() return "e" end,
          GetKeyCode = function() return 15 end, GetKeyName = function() return "e" end }
local chats = {}
chat.AddText = function(...)
    local t = {}
    for _, v in ipairs({ ... }) do if type(v) == "string" then t[#t + 1] = v end end
    chats[#chats + 1] = table.concat(t)
end
local spawn_list = {}
list = { GetForEdit = function(name) spawn_list[name] = spawn_list[name] or {} return spawn_list[name] end,
         Set = function(name, k, v) spawn_list[name] = spawn_list[name] or {} spawn_list[name][k] = v end }

-- a model of scripted entities (both realms) --------------------------------------------------------------------------------
local EMT = {}
local function phys_object()
    return { motion = true, gravity = true, vel = Vector(),
             EnableMotion = function(s, b) s.motion = b end, IsMotionEnabled = function(s) return s.motion end,
             EnableGravity = function(s, b) s.gravity = b end, SetVelocity = function(s, v) s.vel = Vector(v) end,
             IsMoveable = function(s) return s.motion end, GetMass = function() return 10 end, Wake = function() end }
end
local function install_dt(e)
    e.dt, e.dtn, e.edit, e.keys = {}, {}, {}, {}
end
function EMT:NetworkVar(typ, slot, name, other)
    local default = typ == "Bool" and false or 0
    if typ == "String" then default = "" end                 -- (0.9.4.1: TakenBits)
    self.dt[name] = default
    self.dtn[name] = self.dtn[name] or {}
    self.types = self.types or {}
    self.types[name] = typ
    self["Get" .. name] = function(s) return s.dt[name] end
    self["Set" .. name] = function(s, v)
        for _, f in ipairs(s.dtn[name]) do f(s, name, s.dt[name], v) end
        s.dt[name] = v
        if s.peer and s.peer["Set" .. name] then s.peer["Set" .. name](s.peer, v) end   -- networked to the client copy
    end
    if other and other.KeyName then
        self.keys[other.KeyName] = name
        if other.Edit then self.edit[other.KeyName] = other.Edit end
    end
end
function EMT:NetworkVarNotify(name, fn) table.insert(self.dtn[name], fn) end
function EMT:GetNetworkVars()
    local t = {}
    for k, v in pairs(self.dt) do t[k] = v end
    return t
end
function EMT:RestoreNetworkVars(tab)
    for k, v in pairs(tab or {}) do
        if self.dt[k] ~= nil then self["Set" .. k](self, v) end
    end
end
function EMT:GetEditingData() return self.edit end
function EMT:EntIndex() return self.idx end
function EMT:GetClass() return self.cls end
function EMT:GetPos() return Vector(self.pos) end
function EMT:SetPos(p)
    self.pos = Vector(p)
    if self.peer then self.peer.pos = Vector(p) end
end
function EMT:GetAngles() return Angle(self.ang) end
function EMT:SetAngles(a)
    self.ang = Angle(a)
    if self.peer then self.peer.ang = Angle(a) end
end
function EMT:SetModel(m) self.model = m end
function EMT:DrawShadow() end
function EMT:PhysicsInitBox(mn, mx)
    self.phys = phys_object()
    self.box = { Vector(mn), Vector(mx) }
    self.solid = SOLID_BBOX                                -- (GMod's PhysicsInitBox: SOLID_BBOX and the bounds)
    self.cbounds = { Vector(mn), Vector(mx) }
    self.boxInits = (self.boxInits or 0) + 1
end
function EMT:SetSolid(s) self.solid = s end
function EMT:GetSolid() return self.solid or 0 end
function EMT:EnableCustomCollisions(b) self.customcol = (b ~= false) end
function EMT:SetMoveType(m) self.movetype = m end
function EMT:GetMoveType() return self.movetype or 0 end
function EMT:SetCollisionBounds(a, b) self.cbounds = { Vector(a), Vector(b) } end
function EMT:SetCollisionGroup(g) self.group = g end
function EMT:GetCollisionGroup() return self.group or 0 end
function EMT:GetPhysicsObject() return self.phys or NULL end
function EMT:SetRenderBounds(a, b) self.rbounds = { Vector(a), Vector(b) } end
function EMT:OBBMins() return self.cbounds and Vector(self.cbounds[1]) or Vector(-8, -8, -8) end
function EMT:OBBMaxs() return self.cbounds and Vector(self.cbounds[2]) or Vector(8, 8, 8) end
function EMT:IsPlayer() return false end
function EMT:IsNPC() return self.npc == true end
function EMT:IsNextBot() return false end
function EMT:IsVehicle() return false end
function EMT:IsWeapon() return false end
function EMT:IsWorld() return false end
function EMT:Activate() end
function EMT:GetNW2Bool(k, d) local v = (self.nw2 or {})[k] if v == nil then return d end return v end
EMT.GetNW2Int = EMT.GetNW2Bool
function EMT:SetNW2Bool(k, v) self.nw2 = self.nw2 or {} self.nw2[k] = v self.nw2writes = (self.nw2writes or 0) + 1 end
EMT.SetNW2Int = EMT.SetNW2Bool
function EMT:Health() return 0 end
function EMT:Disposition() return D_HT end

-- a class table chain: the entity's class (ENT), its base, then the engine's functions
local function class_lookup(classes, cls)
    return function(t, k)
        local c = classes[cls]
        local guard = 0
        while c and guard < 8 do
            local v = rawget(c, k)
            if v ~= nil then return v end
            c = classes[rawget(c, "Base") or ""]
            guard = guard + 1
        end
        return EMT[k]
    end
end
local function new_entity(classes, cls, idx)
    local e = setmetatable({ cls = cls, idx = idx, pos = Vector(), ang = Angle(0, 0, 0) },
        { __index = class_lookup(classes, cls) })
    install_dt(e)
    if e.SetupDataTables then e:SetupDataTables() end
    return e
end

-- the server realm: its own globals over the mock's, its hooks, its net -------------------------------------------------------
local S = setmetatable({}, { __index = _G })
S.SERVER, S.CLIENT = true, false
local SH, recv_s, recv_c, strings, scmds = {}, {}, {}, {}, {}
local function run_s(ev, ...)
    for _, fn in pairs(SH[ev] or {}) do
        local a, b = fn(...)
        if a ~= nil then return a, b end
    end
end
S.hook = { Add = function(ev, name, fn) SH[ev] = SH[ev] or {} SH[ev][name] = fn end,
           Remove = function(ev, name) if SH[ev] then SH[ev][name] = nil end end,
           Run = function(ev, ...) return run_s(ev, ...) end }
local SCV = {}
S.CreateConVar = function(name, default, flags, help, lo, hi)
    local c = setmetatable({ name = name, v = tostring(default) }, getmetatable(M.cv("fps_max")))
    SCV[name] = c
    return c
end
S.GetConVar = function(n) return SCV[n] end
S.CreateClientConVar = nil
S.concommand = { Add = function(name, fn) scmds[name] = fn end }
S.AddCSLuaFile = function() end
S.CurTime = function() return M.T end
S.print = function() end
S.timer = { Simple = function() end, Create = function() end, Remove = function() end }
local single = true
S.game = { SinglePlayer = function() return single end, GetMap = function() return "gm_test" end }
S.cleanup = { Register = function(t) S.cleanup_types = (S.cleanup_types or 0) + 1 end }
-- server entities
local SCLASSES, SENTS, next_idx = {}, {}, 100
local CCLASSES, CENTS = {}, {}
local function network_to_client(se)
    local ce = setmetatable({ cls = se.cls, idx = se.idx, pos = Vector(se.pos), ang = Angle(se.ang) },
        { __index = class_lookup(CCLASSES, se.cls) })
    install_dt(ce)
    if ce.SetupDataTables then ce:SetupDataTables() end
    for k, v in pairs(se.dt) do ce.dt[k] = v end
    se.peer = ce
    CENTS[se.idx] = ce
    M.run_hook("OnEntityCreated", ce)
    if ce.Initialize then ce:Initialize() end
    M.run_hook("NetworkEntityCreated", ce)
    return ce
end
S.ents = {
    Create = function(cls)
        next_idx = next_idx + 1
        local e = new_entity(SCLASSES, cls, next_idx)
        e.Spawn = function(s)
            SENTS[s.idx] = s
            if s.Initialize then s:Initialize() end
            run_s("OnEntityCreated", s)
            network_to_client(s)
        end
        e.Remove = function(s)
            s.removed = true
            SENTS[s.idx] = nil
            run_s("EntityRemoved", s)
            if s.peer then
                s.peer.removed = true
                M.run_hook("EntityRemoved", s.peer)
                if s.peer.OnRemove then s.peer:OnRemove() end
                CENTS[s.idx] = nil
            end
        end
        return e
    end,
    FindByClass = function(pat)
        local out = {}
        for _, e in pairs(SENTS) do
            if string.find(e.cls, "^" .. string.gsub(pat, "%*", ".*") .. "$") then out[#out + 1] = e end
        end
        return out
    end,
    FindInSphere = function() return S.found or {} end,
}
S.Entity = function(i) return SENTS[i] or NULL end
S.scripted_ents = { Register = function(t, name) SCLASSES[name] = t end, Get = function() return nil end }
S.util = { AddNetworkString = function(n) strings[n] = true end, IsInWorld = function() return true end,
           TraceLine = function(t) return { Hit = false, HitPos = Vector(t.endpos) } end,
           TraceHull = function(t) return { Hit = false, HitPos = Vector(t.endpos) } end }
-- the players (the server's view)
local function new_player(idx, name)
    local p = setmetatable({ idx = idx, name = name, pos = Vector(), infos = {}, admin = false, host = false, chats = {},
                             limit = true, counts = {}, cleanups = {} }, { __index = EMT })
    function p:IsValid() return true end
    function p:IsPlayer() return true end
    function p:Nick() return self.name end
    function p:GetInfoNum(k, d) local v = self.infos[k] if v == nil then return d end return v end
    function p:CheckLimit(k) return self.limit end
    function p:AddCount(k, e) self.counts[#self.counts + 1] = e end
    function p:AddCleanup(k, e) self.cleanups[#self.cleanups + 1] = { k, e } end
    function p:IsAdmin() return self.admin end
    function p:IsListenServerHost() return self.host end
    function p:ChatPrint(s) self.chats[#self.chats + 1] = s end
    function p:EyeAngles() return Angle(0, self.yaw or 0, 0) end
    function p:GetPos() return Vector(self.pos) end
    function p:Alive() return true end
    function p:Ping() return 0 end
    return p
end
local P1 = new_player(1, "player one")
local P2 = new_player(2, "player two")
S.player = { GetAll = function() return { P1, P2 } end }
-- net, both directions, delivered at once
local out_c, out_s, sent_c, sent_s = nil, nil, {}, {}
local function reader(vals)
    local i = 0
    return function() i = i + 1 return vals[i] end
end
local cread
net.Start = function(name) out_c = { name = name, vals = {} } end
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteInt", "WriteFloat", "WriteVector", "WriteEntity", "WriteString" }) do
    net[w] = function(v) if out_c then out_c.vals[#out_c.vals + 1] = type(v) == "table" and getmetatable(v) == VMT and Vector(v) or v end end
end
net.Receive = function(name, fn) recv_c[name] = fn end
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadInt", "ReadFloat", "ReadVector", "ReadEntity", "ReadString" }) do
    net[r] = function() return cread() end
end
local sender = P1
net.SendToServer = function()
    local m = out_c
    out_c = nil
    if not m then return end
    sent_c[#sent_c + 1] = m
    local fn = recv_s[m.name]
    if fn then
        local saved = S.sread
        S.sread = reader(m.vals)
        fn(#m.vals * 8, sender)
        S.sread = saved
    end
end
S.net = {
    Receive = function(name, fn) recv_s[name] = fn end,
    Start = function(name) out_s = { name = name, vals = {} } end,
    Send = function(to)
        local m = out_s
        out_s = nil
        if not m then return end
        m.to = to
        sent_s[#sent_s + 1] = m
        local fn = recv_c[m.name]
        if fn and to == P1 then
            local saved = cread
            cread = reader(m.vals)
            fn(#m.vals * 8)
            cread = saved
        end
    end,
}
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteInt", "WriteFloat", "WriteVector", "WriteNormal", "WriteString",
                     "WriteEntity" }) do
    S.net[w] = function(v) if out_s then out_s.vals[#out_s.vals + 1] = type(v) == "table" and getmetatable(v) == VMT and Vector(v) or v end end
end
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadInt", "ReadFloat", "ReadVector", "ReadNormal", "ReadString",
                     "ReadEntity" }) do
    S.net[r] = function() return S.sread() end
end
util.NetworkStringToID = function(n) return strings[n] and 1 or 0 end
local function count_c(name)
    local n = 0
    for _, m in ipairs(sent_c) do n = n + (m.name == name and 1 or 0) end
    return n
end
local function last_c(name)
    for i = #sent_c, 1, -1 do if sent_c[i].name == name then return sent_c[i] end end
end
local function count_s(name)
    local n = 0
    for _, m in ipairs(sent_s) do n = n + (m.name == name and 1 or 0) end
    return n
end

local function sinclude(rel)
    local src = host_read(M.root .. "/" .. rel)
    if not src then error("server include: no file " .. rel) end
    local fn, err = host_load(src, "sv:" .. rel)
    if not fn then error(err) end
    setfenv(fn, S)
    fn()
end
-- an entity file into a realm's class table
local function load_entity(realm, name)
    local src = host_read(M.root .. "/entities/" .. name .. ".lua")
    if not src then error("no entity file " .. name) end
    local fn, err = host_load(src, (realm == S and "sv:" or "cl:") .. name)
    if not fn then error(err) end
    local ENTT = {}
    if realm == S then
        rawset(S, "ENT", ENTT)
        setfenv(fn, S)
        fn()
        rawset(S, "ENT", nil)
        SCLASSES[name] = ENTT
    else
        ENT = ENTT
        fn()
        ENT = nil
        CCLASSES[name] = ENTT
        scripted_ents.Register(ENTT, name)
    end
    return ENTT
end
local CLASS_NAMES = { "gsa1_obj_ring", "gsa1_obj_ring_line", "gsa1_obj_ring_circle", "gsa1_obj_itembox",
                      "gsa1_obj_itembox_air" }

-- the server's files: its config, the shared net file, this feature and the interaction feature's server half ------------
rawset(S, "GSA1", {})
local ok_s, err_s = pcall(function()
    sinclude("gsa1/sh_config.lua")
    sinclude("gsa1/sh_net.lua")
    sinclude("gsa1/feat/sh_objects.lua")
    sinclude("gsa1/feat/sv_objects.lua")
    sinclude("gsa1/feat/sh_interact.lua")
    sinclude("gsa1/feat/sv_interact.lua")
    load_entity(S, "gsa1_base")
    for _, n in ipairs(CLASS_NAMES) do load_entity(S, n) end
end)
local SG = rawget(S, "GSA1")
local SO = SG and SG.Objects

-- the client: the autorun with a mock module that has the objects feature -----------------------------------------------------
GSA1 = nil
local G = M.module({ features = { objects = 3, render = 1, interact = 1, charopt = 1 },
                     archives = { [0] = { 28, 29, 96, 138 } },
                     batches = function(pair, kind) return M.batchList end })
function G.TextureArchives(kind)
    return { { name = "SONIC", count = 28 }, { name = "SON_EFF", count = 29 }, { name = "OBJ_REGULAR", count = 96 },
             { name = "EFF_REGULAR", count = 138 } }
end
local MOD = { calls = {}, adds = {}, gen = 1, nextId = 1, events = {}, unsupported = {}, unavailable = {} }
local function rec(name, ...) MOD.calls[#MOD.calls + 1] = { name, ... } end
local function n_of(name)
    local n = 0
    for _, c in ipairs(MOD.calls) do n = n + (c[1] == name and 1 or 0) end
    return n
end
local function last_of(name)
    for i = #MOD.calls, 1, -1 do if MOD.calls[i][1] == name then return MOD.calls[i] end end
end
G.OBJECTS = { RING = 1, O_GRING = 2, ITEMBOX = 3, ITEMBOX_AIR = 4, STATE_PRESENT = 1, STATE_BROKEN = 2, EVENT_GONE = 3,
              EVENT_USERBITS = 4, EVENT_BROKEN = 7, GOPT_ITEM_ICON_LIMIT = 4, DRAW_OBJECT = 0x1000, RING_WINDOW_MAX = 200,
              BOX_WINDOW_MAX = 100, RANGE_MIN_HU = 1600, RANGE_MAX_HU = 12000, VIEW_TAN_MIN = 0.7, VIEW_TAN_MAX = 4 }
function G.SetAdd(t, pos, ang, p1, p2, p3, user, st)
    if MOD.unsupported[t] then
        rec("SetAddRefused", t)
        return nil, "the type's code is not in this build", "unsupported"
    end
    local id = MOD.nextId
    MOD.nextId = MOD.nextId + 1
    rec("SetAdd", id, t, p1, p2, p3, user, st)
    MOD.adds[id] = { t = t, pos = Vector(pos), ang = Angle(ang), p = { p1, p2, p3 }, user = user, st = st }
    return id
end
function G.SetUpdate(id, pos, ang, p1, p2, p3)
    rec("SetUpdate", id, p1, p2, p3)
    if not MOD.adds[id] then return nil, "no such object", "not_found" end
    MOD.adds[id].pos = Vector(pos)
    return true
end
function G.SetRemove(id) rec("SetRemove", id) MOD.adds[id] = nil return true end
function G.SetClear()
    local n = 0
    for _ in pairs(MOD.adds) do n = n + 1 end
    MOD.adds = {}
    rec("SetClear", n)
    return n
end
function G.SetState(id, st, bits, index) rec("SetState", id, st, bits, index) return true end
function G.SetConfig(t) rec("SetConfig", t.ring_window, t.box_window, t.range, t.view_tan) return true end
function G.SetEvents(out)
    out = out or {}
    for i, e in ipairs(MOD.events) do out[i] = e end
    out.count = #MOD.events
    MOD.events = {}
    return out
end
function G.SetGeneration()
    local n = 0
    for _ in pairs(MOD.adds) do n = n + 1 end
    return MOD.gen, n, n
end
function G.ObjectInfo()
    local out = { count = 4 }
    for t = 1, 4 do out[t] = { type = t, available = not MOD.unavailable[t], range = 1600 } end
    return out
end
function G.ObjectBounds(id) if MOD.bounds then return unpack(MOD.bounds) end end
function G.SetGameOption(id, o, v) rec("SetGameOption", id, o, v) return true end
-- the interaction feature's functions (cl_interact.lua's scanner)
function G.ObjAdd(ent, kind) rec("ObjAdd", ent, kind) return ent + 1000, true end
G.ObjUpdate = G.ObjAdd
function G.ObjMove() return true end
function G.ObjRemove(ent) rec("ObjRemove", ent) return true end
function G.ObjClear() return 0 end
function G.ObjEvents(out) out = out or {} out.count = 0 return out end
function G.ObjConfig() return true end
function G.ObjHeld() return nil end
function G.ObjRelease() return true end
function G.ObjInfo() return { proxies = 0, refused = 0 } end
function G.Damage() return true end
function G.SetCharOption() return true end
function G.AddRings() return true end
function G.StateEx(id, out) out = out or {} out.rings, out.lives, out.mode = 0, 4, 2 return out end
function G.Contacts(id, out) out = out or {} out.count = 0 return out end
G.INTERACT = { ENEMY = 1, HOLDABLE = 5, BALLOON = 6, SOLID = 1, HITF_LAUNCHED = 8 }
function G.MoverUpdate(idx) rec("MoverUpdate", idx) return true end

M.included = {}
local ok_c, err_c = pcall(M.load, "autorun/gsa1_autorun.lua")
local ok_e, err_e = pcall(function()
    load_entity(nil, "gsa1_base")
    for _, n in ipairs(CLASS_NAMES) do load_entity(nil, n) end
end)
local O = GSA1 and GSA1.Objects
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local loaded = GSA1 and table.concat(GSA1.FeatureFiles or {}, " ") or ""
check(ok_s and SO ~= nil and ok_c and ok_e and #ferr == 0 and O ~= nil and string.find(loaded, "cl_objects.lua", 1, true)
    ~= nil and O.Sync ~= nil and SO.ServerEvent ~= nil,
    "both realms load: the server's sh_objects + sv_objects (+ the interaction feature's) and the entities (%s); the "
    .. "client's sh_objects and cl_objects through the autorun (%s), the entities (%s)", tostring(err_s or "ok"),
    ok_c and loaded or tostring(err_c or ferr[1]), tostring(err_e or "ok"))
if not (O and SO) then return done() end
check(n_of("SetAdd") == 0 and n_of("SetConfig") == 0, "nothing calls the module while the files load")
check(strings["gsa1_obj_ev"] and strings["gsa1_obj_st"] and S.cleanup_types == 1 and scmds["gsa1_sv_set_reset"] ~= nil,
    "the server registers gsa1_obj_ev / gsa1_obj_st, the cleanup gsa1_objects and the command gsa1_sv_set_reset")

-- 1. the classes ------------------------------------------------------------------------------------------------------------------
do
local cls_ok, cls_bad = 0, {}
for _, n in ipairs(CLASS_NAMES) do
    local c, s = CCLASSES[n], SCLASSES[n]
    local good = c and s and c.Spawnable == true and c.Category == "G-SA1" and c.Base == "gsa1_base" and
        c.ScriptedEntityType == "gsa1_object" and c.GSA1Object == true and c.Editable == true and
        type(c.PrintName) == "string" and s.Spawnable == true and M.classes[n] == c and O.BY_CLASS[n] ~= nil
    if good then cls_ok = cls_ok + 1 else cls_bad[#cls_bad + 1] = n end
end
local base = CCLASSES.gsa1_base
check(cls_ok == 5 and base and base.Spawnable == false and base.GSA1Object == true and base.SpawnFunction ~= nil,
    "the five classes are Spawnable in \"G-SA1\" on gsa1_base, ScriptedEntityType gsa1_object, editable (%s); the base is "
    .. "not spawnable", #cls_bad > 0 and ("bad: " .. table.concat(cls_bad, " ")) or "ok")
local names = {}
for _, n in ipairs(CLASS_NAMES) do names[#names + 1] = CCLASSES[n].PrintName end
check(table.concat(names, ", ") == "Ring, Ring line, Ring circle, Item Box, Item Box (Air)",
    "their names in the Entities tab: %s", table.concat(names, ", "))
local probe = {}
for _, n in ipairs(CLASS_NAMES) do probe[n] = new_entity(CCLASSES, n, 1) end
local line_e, circ_e, box_e = probe.gsa1_obj_ring_line.edit, probe.gsa1_obj_ring_circle.edit, probe.gsa1_obj_itembox.edit
local function combo_ok(edit)
    local c = edit and edit.contents
    if not (c and c.type == "Combo" and type(c.values) == "table") then return false, 0 end
    local n, seen = 0, {}
    for title, v in pairs(c.values) do
        n = n + 1
        seen[v] = title
    end
    if n ~= 9 then return false, n end
    for i, ct in ipairs(O.CONTENTS) do
        if seen[i - 1] ~= ct.title or ct.value ~= i - 1 then return false, n end
    end
    return true, n
end
local cok1, cn1 = combo_ok(box_e)
local cok2 = combo_ok(probe.gsa1_obj_itembox_air.edit)
check(cok1 and cok2 and O.CONTENTS[1].title == "Speed Shoes (HAYAASI)" and O.CONTENTS[9].title ==
    "Magnetic Barrier (ITEM_TH_BARIA)" and O.CONTENTS[8].title == "Bomb (EKUSUPUROSYON)",
    "both boxes' Contents combo: exactly the game's nine (%d), values 0..8 in the game's order (Speed Shoes (HAYAASI) .. "
    .. "Magnetic Barrier (ITEM_TH_BARIA))", cn1)
check(line_e and line_e.count and line_e.count.max == 128 and line_e.count.min == 1 and line_e.spacing and circ_e and
    circ_e.count and circ_e.count.max == 128 and circ_e.radius and probe.gsa1_obj_ring.edit.respawnafter and
    probe.gsa1_obj_ring_line.GetTakenBits ~= nil and probe.gsa1_obj_ring_circle.GetTakenBits ~= nil and
    probe.gsa1_obj_ring_line.types.TakenBits == "String" and probe.gsa1_obj_ring_line.GetUserBits0 == nil and
    probe.gsa1_obj_ring.GetTakenBits == nil and O.LINE_MAX == 128 and O.CIRCLE_MAX == 128,
    "Edit tables: a line's Count 1..128 and Spacing, a circle's Count 1..128 (0.9.4: 7) and Radius, every object's "
    .. "Respawn after; a line and a circle keep their rings taken in the String TakenBits (0.9.4: UserBits0..7)")
-- the line's records: 20 rings -> 8 / 8 / 4 (the module splits the same way: feat_objects_test.cpp)
local d20 = { type = 2, shape = 0, count = 20, size = 40 }
check(O.RecordCount(d20) == 3 and O.RecordMask(d20, 0) == 0xFF and O.RecordMask(d20, 1) == 0xFF and
    O.RecordMask(d20, 2) == 0x0F and O.RecordCount({ type = 2, shape = 1, count = 7, size = 80 }) == 1 and
    O.RecordMask({ type = 2, shape = 1, count = 7, size = 80 }, 0) == 0xFE and
    O.RecordCount({ type = 2, shape = 0, count = 64, size = 40 }) == 8 and
    O.RecordCount({ type = 2, shape = 0, count = 128, size = 40 }) == 16,
    "a line of 20: 3 records of 8 / 8 / 4 rings (bits FF FF 0F); a circle of 7: 1 record (bits 1..7 = FE); 64: 8 records, "
    .. "128: 16")
local rp = O.RingPositions(d20, Vector(0, 0, 0), Angle(0, 90, 0))
local ys = {}
for _, r in ipairs(rp) do ys[#ys + 1] = r.pos.y end
table.sort(ys)
local even = #ys == 20 and math.abs(ys[1] + 380) < 1e-3 and math.abs(ys[20] - 380) < 1e-3
for i = 2, #ys do even = even and math.abs(ys[i] - ys[i - 1] - 40) < 1e-3 end
check(even, "the line's 20 rings 40 HU apart along the entity's forward (yaw 90: +y), centred: %.0f .. %.0f", ys[1] or 0,
    ys[#ys] or 0)

end
-- 2. a copy's NetworkVars (the duplicator, saves): the editable values kept, the runtime state fresh --------------------------
do
local sline = S.ents.Create("gsa1_obj_ring_line")
sline:SetCount(20)
sline:SetSpacing(32)
sline:SetRespawnAfter(30)
sline:SetState(0)
sline:SetTakenBits("0005")
sline:SetRespawnAt(99)
local data = { DT = sline:GetNetworkVars() }
data.DT.UserBits1 = 5                                       -- (what a 0.9.4 copy carries)
sline:OnEntityCopyTableFinish(data)
local copy = S.ents.Create("gsa1_obj_ring_line")
copy:RestoreNetworkVars(data.DT)
check(copy:GetCount() == 20 and copy:GetSpacing() == 32 and copy:GetRespawnAfter() == 30 and copy:GetState() == 1 and
    copy:GetTakenBits() == "" and copy:GetRespawnAt() == 0 and data.DT.Count == 20 and data.DT.UserBits1 == nil,
    "RestoreNetworkVars round trip: Count %s, Spacing %s, Respawn after %s kept; State %s, TakenBits \"%s\", RespawnAt %s "
    .. "fresh (a 0.9.4 copy's UserBits dropped)", tostring(copy:GetCount()), tostring(copy:GetSpacing()),
    tostring(copy:GetRespawnAfter()), tostring(copy:GetState()), tostring(copy:GetTakenBits()),
    tostring(copy:GetRespawnAt()))

end
-- 3. placing (the classes' SpawnFunction -> sv_objects.lua O.ServerSpawn) --------------------------------------------------
local SPAWN = SCLASSES.gsa1_base.SpawnFunction
local function spawn(cls, x, y, z, nz)
    return SPAWN(SCLASSES[cls], P1, { Hit = true, HitPos = Vector(x, y, z), HitNormal = Vector(0, 0, nz or 1) }, cls)
end
P1.infos.gsa1_set_box_content = 6
P1.yaw = 90
local sbox = spawn("gsa1_obj_itembox", 100, 200, 0)
local sair = spawn("gsa1_obj_itembox_air", 300, 200, 0)
local sring = spawn("gsa1_obj_ring", 500, 200, 0)
local phys = sbox and sbox:GetPhysicsObject()
check(sbox and sbox:GetContents() == 6 and sair and sair:GetContents() == 6 and math.abs(sbox.pos.z - 0.5) < 1e-6 and
    math.abs(sair.pos.z - 40) < 1e-6 and sring and math.abs(sring.pos.z - 32) < 1e-6 and sbox.ang.y == 90 and
    sbox:GetState() == 1 and sbox:GetRespawnAfter() == 0,
    "placing: the placer's gsa1_set_box_content (6, Extra Life) reaches the box; the ground box's base at the surface "
    .. "(+%.1f), the air box 40 above it (+%.0f), a ring 32 (+%.0f); facing the placer (yaw %s); there, Respawn after 0",
    sbox and sbox.pos.z or -1, sair and sair.pos.z or -1, sring and sring.pos.z or -1, sbox and tostring(sbox.ang.y) or "-")
check(sbox and sbox.box and sbox.box[1].z == 0 and sbox.box[2].z == 60 and sbox.box[2].x == 20 and
    sbox.group == COLLISION_GROUP_WORLD and sbox.solid == SOLID_OBB and sbox.customcol == true and sbox.cbounds and
    sbox.cbounds[2].z == 60 and sbox.movetype == MOVETYPE_VPHYSICS and
    phys and phys.motion == false and phys.gravity == false and #P1.counts == 3 and P1.cleanups[1][1] == "gsa1_objects" and
    sbox:UpdateTransmitState() == TRANSMIT_ALWAYS,
    "the ground box's hull of the game's size (r 20, 60 tall): a frozen physics box without gravity, SOLID_OBB with "
    .. "custom collisions (0.9.4.1: the pick hull), in COLLISION_GROUP_WORLD, counted for sbox_maxgsa1_objects, in the "
    .. "cleanup gsa1_objects, sent to everyone (TRANSMIT_ALWAYS)")
local undo = { Entities = { sbox }, CustomUndoText = "Undone Item Box" }
run_s("CanCreateUndo", P1, undo)
P1.limit = false
local over = spawn("gsa1_obj_ring", 0, 0, 0)
P1.limit = true
SO.cv.sv_on:SetString("0")
local off = spawn("gsa1_obj_ring", 0, 0, 0)
SO.cv.sv_on:SetString("1")
SO.cv.sv_respawn:SetString("15")
local timed = spawn("gsa1_obj_ring", 700, 200, 0)
SO.cv.sv_respawn:SetString("0")
check(undo.CustomUndoText == "Undone G-SA1 Item Box" and over == nil and off == nil and #P1.chats == 1 and
    string.find(P1.chats[1], "off on this server", 1, true) ~= nil and timed and timed:GetRespawnAfter() == 15,
    "undo reads \"%s\"; the limit refuses (no message of ours: the sandbox's own), gsa1_sv_set 0 refuses with \"%s\"; "
    .. "gsa1_sv_set_respawn 15 -> a new ring's Respawn after %s", undo.CustomUndoText, tostring(P1.chats[1]),
    timed and tostring(timed:GetRespawnAfter()) or "-")

-- 4. the client: the entities into the module --------------------------------------------------------------------------------
GSA1.LoadModule()
local sline = S.ents.Create("gsa1_obj_ring_line")
sline:SetPos(Vector(900, 200, 32))
sline:SetAngles(Angle(0, 90, 0))
sline:SetCount(20)
sline:SetSpacing(40)
sline:Spawn()
local scirc = S.ents.Create("gsa1_obj_ring_circle")
scirc:SetPos(Vector(1100, 200, 32))
scirc:Spawn()
M.frame(1 / 60)
local adds = {}
for _, c in ipairs(MOD.calls) do if c[1] == "SetAdd" then adds[c[7]] = c end end
local la, ba, ra, ca = adds[sline.idx], adds[sbox.idx], adds[sring.idx], adds[scirc.idx]
check(n_of("SetAdd") == 6 and la and la[3] == 2 and la[4] == 20 and la[5] == 40 and la[6] == 0 and la[8] == 1 and ba and
    ba[3] == 3 and ba[4] == 6 and ba[5] == 0 and ra and ra[3] == 1 and ra[4] == 0 and ca and ca[3] == 2 and ca[4] == 7 and
    ca[5] == 80 and ca[6] == 1 and adds[sair.idx] and adds[sair.idx][3] == 4,
    "a frame: one SetAdd per entity (%d): the line (type 2, 20 rings, 40 HU, shape 0, user = its index, PRESENT), the "
    .. "ground box (3, contents 6), the ring (1, 0 0 0), the circle (2, 7, 80, 1: the class defaults), the air box (4)",
    n_of("SetAdd"))
M.frame(1 / 60)
local cfg = last_of("SetConfig")
check(n_of("SetAdd") == 6 and n_of("SetConfig") == 1 and cfg and cfg[2] == 128 and cfg[3] == 48 and cfg[4] == 4800 and
    cfg[5] and math.abs(cfg[5] - 1.873) <= 0.005,
    "the next frame adds nothing again; the window once from the sliders (rings %s, boxes %s: 0.9.4b's defaults), the range "
    .. "%s HU and view_tan %.4f (3440 x 1440 at fov 92.5: 1.873)", cfg and tostring(cfg[2]) or "-",
    cfg and tostring(cfg[3]) or "-", cfg and tostring(cfg[4]) or "-", cfg and tonumber(cfg[5]) or -1)
GSA1.cv.set_draw = O.cv.draw
RunConsoleCommand("gsa1_set_ring_window", "40")
M.frame(1 / 60)
cfg = last_of("SetConfig")
check(n_of("SetConfig") == 2 and cfg[2] == 40, "the ring slider at 40 -> SetConfig(40, 48)")
RunConsoleCommand("gsa1_set_range", "1600")
M.frame(1 / 60)
local cr = last_of("SetConfig")
RunConsoleCommand("gsa1_set_range", "13000")
M.frame(1 / 60)
local cr2 = last_of("SetConfig")
RunConsoleCommand("gsa1_set_view_wide", "0")
M.frame(1 / 60)
local cw = last_of("SetConfig")
RunConsoleCommand("gsa1_set_view_wide", "1")
RunConsoleCommand("gsa1_set_range", "4800")
M.frame(1 / 60)
local cb = last_of("SetConfig")
check(cr[4] == 0 and cr2[4] == 12000 and cw[5] == 0 and cb[4] == 4800 and math.abs(cb[5] - 1.873) <= 0.005 and
    O.RANGE == 4800,
    "gsa1_set_range 1600 -> range 0 (the game's 400 units: 0.9.4's list exactly), 13000 -> clamped to the module's 12,000 "
    .. "HU (%s); gsa1_set_view_wide 0 -> view_tan 0 (the game's 4:3); back at 4800 / 1.873; O.RANGE follows (%s)",
    tostring(cr2[4]), tostring(O.RANGE))
local box_id = ba and ba[2]
local u0 = n_of("SetUpdate")
sbox:SetContents(2)
M.frame(1 / 60)
M.frame(1 / 60)
local up = last_of("SetUpdate")
check(n_of("SetUpdate") == u0 + 1 and up and up[2] == box_id and up[3] == 2 and up[4] == 0 and up[5] == 0,
    "Contents changed to 2 on the server -> one SetUpdate(box, 2, 0, 0) on the client")
local s0 = n_of("SetState")
sring:SetState(0)
M.frame(1 / 60)
local ss = last_of("SetState")
check(n_of("SetState") == s0 + 1 and ss and ss[2] == ra[2] and ss[3] == 0 and ss[4] == nil,
    "the ring's State 0 (another player took it) -> SetState(ring, 0) in this client's worlds")
sline:SetTakenBits("0005")
M.frame(1 / 60)
ss = last_of("SetState")
check(ss and ss[2] == la[2] and ss[3] == 1 and ss[4] == 0x05 and ss[5] == 1,
    "the line's TakenBits \"0005\" (record 1: 0x05) -> SetState(line, PRESENT, 0x05, record 1)")
-- a Physics Gun drag: no update while it moves, one once it is still (0.25 s); a drop updates at once
u0 = n_of("SetUpdate")
for i = 1, 12 do
    sline:SetPos(Vector(900 + 5 * i, 200, 32))
    M.frame(1 / 60)
end
local during = n_of("SetUpdate") - u0
for _ = 1, 24 do M.frame(1 / 60) end
local after = n_of("SetUpdate") - u0
for i = 1, 6 do
    sline:SetPos(Vector(960, 200 + 5 * i, 32))
    M.frame(1 / 60)
end
local before_drop = n_of("SetUpdate") - u0
run_s("OnPhysgunPickup", P1, sline)
run_s("PhysgunDrop", P1, sline)
M.frame(1 / 60)
local at_drop = n_of("SetUpdate") - u0
check(during == 0 and after == 1 and before_drop == 1 and at_drop == 2 and sline:GetMoved() == 1 and
    sline:GetPhysicsObject().motion == false,
    "a drag: %d updates during 12 moving frames, %d once still for 0.25 s; a Physics Gun drop -> Moved %d and the update "
    .. "at once (%d in all), the box frozen again", during, after, sline:GetMoved(), at_drop)

-- 5. a character: the icon guard, the events -----------------------------------------------------------------------------------
M.batchList = {
    { 0, 0, 0x20, 1, 0, 3, 0, 100, 1 },              -- 1 the body
    { 2, 50, 0x106C, 1, 0, 3, 0, 96, 1 },            -- 2 a ring (OBJECT | EFFECT | PALETTE_LIT | ENV_MAP | 2SIDED)
    { 1, 2, 0x255, 4, 1, 3, 1, 2, 2 },               -- 3 an effect sprite of the character
    { 2, 58, 0x1841, 4, 5, 11, 1, 2, 1 },            -- 4 the ring's blob shadow (OBJECT | SHADOW | EFFECT | BLEND)
    { 2, 58, 0x841, 4, 5, 11, 1, 2, 1 },             -- 5 the character's blob shadow
}
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
GSA1.cv.prewarm:SetString("0")
GSA1.Spawn("sonic")
local C = GSA1.Char
local go = last_of("SetGameOption")
check(C ~= nil and go and go[2] == C.id and go[3] == 4 and go[4] == 1,
    "a new character gets SetGameOption(GOPT_ITEM_ICON_LIMIT 4, 1): the icon guard on (review R.15)")
if not C then return done() end
RunConsoleCommand("gsa1_set_icon_guard", "0")
go = last_of("SetGameOption")
RunConsoleCommand("gsa1_set_icon_guard", "1")
check(go and go[2] == C.id and go[3] == 4 and go[4] == 0, "gsa1_set_icon_guard 0 -> SetGameOption(4, 0) on the character now")
for _ = 1, 4 do M.frame(1 / 60) end
-- the server sees P1 as a character standing next to the objects
P1.GSA1Active, P1.GSA1Kind = true, 0
local function stand(x, y, z)
    M.T = M.T + 0.05               -- (a state packet every 50 ms, as the client sends them)
    P1.GSA1State = { x = x, y = y, z = z, time = M.T }
    run_s("Think")
end
local function event(t)
    local e = { kind = t.kind, character = t.character or C.id, id = t.id, user = t.user, index = t.index or 0,
                type = t.type, condition = t.condition or 0, bits = t.bits or 0, step = 100, touch_step = 84,
                x = t.x, y = t.y, z = t.z, cause = t.cause or 1, ax = t.ax or t.x, ay = t.ay or t.y, az = t.az or t.z }
    MOD.events[#MOD.events + 1] = e
end
local ring_id = ra[2]
sring:SetState(1)
M.frame(1 / 60)
for _ = 1, 3 do stand(500, 200, 0) M.frame(1 / 60) end
local ev0 = count_c("gsa1_obj_ev")
event({ kind = 3, id = ring_id, user = sring.idx, type = 1, x = 510, y = 200, z = 10, condition = 0x0010 })
M.frame(1 / 60)
local m = last_c("gsa1_obj_ev")
check(count_c("gsa1_obj_ev") == ev0 + 1 and m and m.vals[1] == sring.idx and m.vals[3] == 3 and sring:GetState() == 0,
    "a GONE of the local world -> one gsa1_obj_ev (entity %s, kind %s, %.2f s old); the server took it: State %s",
    m and tostring(m.vals[1]) or "-", m and tostring(m.vals[3]) or "-", m and m.vals[5] or -1, tostring(sring:GetState()))
for _ = 1, 3 do stand(100, 200, 0) M.frame(1 / 60) end
event({ kind = 3, id = box_id, user = sbox.idx, type = 3, x = 110, y = 200, z = 10, condition = 0x8015 })
M.frame(1 / 60)
m = last_c("gsa1_obj_ev")
check(m and m.vals[1] == sbox.idx and m.vals[3] == 7 and sbox:GetBroken() == true,
    "a ground box's GONE (not expected) is sent as BROKEN (kind %s); the server: Broken %s", m and tostring(m.vals[3]) or
    "-", tostring(sbox:GetBroken()))
local ev1 = count_c("gsa1_obj_ev")
event({ kind = 3, character = C.id + 7, id = ra[2], user = sring.idx, type = 1, x = 510, y = 200, z = 10 })
event({ kind = 1, id = ra[2], user = sring.idx, type = 1, x = 510, y = 200, z = 10 })
event({ kind = 3, id = 999, user = sring.idx, type = 1, x = 510, y = 200, z = 10 })
M.frame(1 / 60)
check(count_c("gsa1_obj_ev") == ev1, "not sent: an event of another world (a follower's), a SPAWNED, an event whose "
    .. "object id is not the entity's record")
-- a refused report: the state back to the client, whose world gets the ring again
sring:SetState(1)
M.frame(1 / 60)
local st0, s0n = count_s("gsa1_obj_st"), n_of("SetState")
for _ = 1, 40 do stand(-3000, 200, 0) M.frame(1 / 60) end     -- (the path near the ring is older than 0.6 s now)
event({ kind = 3, id = ring_id, user = sring.idx, type = 1, x = 510, y = 200, z = 10 })
M.frame(1 / 60)
ss = last_of("SetState")
check(count_s("gsa1_obj_st") == st0 + 1 and sring:GetState() == 1 and n_of("SetState") > s0n and ss and ss[2] == ring_id and
    ss[3] == 1,
    "a report the server refuses (the character far from the touch then) -> gsa1_obj_st back, the ring stays, the client "
    .. "puts it into its world again (SetState(ring, PRESENT))")

-- 6. the server's check (sh_objects.lua O.CheckEvent; rings review R.4.7, items 5.2, review R.3) --------------------------------
do
-- a path: positions every 0.05 s of client time, arriving `lat` s later (the server's sample times)
local function path(now, lat, fn)
    local h = {}
    for tc = now - 1.4, now + 1e-6, 0.05 do
        local x, y, z = fn(tc)
        h[#h + 1] = { t = tc + lat, x = x, y = y, z = z }
    end
    return h
end
local NOW = 1000
local function ring_obj(x, y, z)
    local d = { type = 1, shape = 0, count = 1, size = 0 }
    return { type = 1, d = d, pos = Vector(x, y, z), state = 1, broken = false, bits = { [0] = 0 },
             rings = O.RingPositions(d, Vector(x, y, z), Angle(0, 0, 0)) }
end
local function box_obj(x, y, z, t) return { type = t or 3, d = { type = t or 3 }, pos = Vector(x, y, z), state = 1,
                                            broken = false, bits = {} } end
-- the Light Speed Dash and the spin dash: the touch 30 HU before the ring, GONE 16 steps (0.267 s) later, sent a frame
-- after that and 50 ms on the way; the character 372 / 708 HU past the ring when the report arrives (rings review R.2.6)
local function dash(speed)
    local t_touch = NOW - 0.05 - 0.283
    local h = path(NOW, 0.05, function(tc) return 970 + speed * (tc - t_touch), 0, 0 end)
    local e = { kind = 3, age = 0.283, pos = Vector(970, 0, 0), cause = 1, att = Vector(970, 0, 0) }
    local ok, why = O.CheckEvent(e, ring_obj(1000, 0, 0), h, NOW, 128, 0)
    local x_now = 970 + speed * (NOW - 0.05 - t_touch)
    return ok, why, x_now - 1000
end
local lok, lwhy, ld = dash(1393)
local sok, swhy, sd = dash(2650)
check(lok and sok and ld > 120 and sd > 690,
    "the Light Speed Dash (the character %.0f HU past the ring when the report arrives) and the spin dash (%.0f HU) are "
    .. "accepted: the touch is checked against the path at the report's age, never the position now (%s / %s)", ld, sd,
    tostring(lwhy or "ok"), tostring(swhy or "ok"))
local far = path(NOW, 0.05, function(tc) return 0, 0, 0 end)
local fok, fwhy = O.CheckEvent({ kind = 3, age = 0.3, pos = Vector(1000, 0, 0), cause = 1, att = Vector(1000, 0, 0) },
    ring_obj(1020, 0, 0), far, NOW, 128, 0)
check(not fok, "a touch 1,000 HU from every position the server has: refused (%s)", tostring(fwhy))
local big = path(NOW, 0.05, function(tc) return 62, 0, 0 end)
local bok, bwhy = O.CheckEvent({ kind = 7, age = 0.02, pos = Vector(62, 0, 0), cause = 1, att = Vector(62, 0, 0) },
    box_obj(0, 0, 0), big, NOW, 128, 7)
local gam = path(NOW, 0.05, function(tc) return 1000, 0, 0 end)
local gok, gwhy = O.CheckEvent({ kind = 7, age = 0.05, pos = Vector(1000, 0, 0), cause = 2, att = Vector(20, 0, 0) },
    box_obj(0, 0, 0), gam, NOW, 128, 6)
local b300 = path(NOW, 0.05, function(tc) return 300, 0, 0 end)
local tok, twhy = O.CheckEvent({ kind = 7, age = 0.05, pos = Vector(300, 0, 0), cause = 1, att = Vector(300, 0, 0) },
    box_obj(0, 0, 0), b300, NOW, 128, 0)
check(bok and gok and not tok,
    "Big's body break 62 HU from the ground box: accepted (%s); E-102's PROJECTILE break, the shot 20 HU from the box and "
    .. "E-102 1,000 HU away: accepted (%s); a BODY break 300 HU away: refused (%s)", tostring(bwhy or "ok"),
    tostring(gwhy or "ok"), tostring(twhy))
local mag = path(NOW, 0.05, function(tc) return 193, 0, 0 end)
local mok, mwhy = O.CheckEvent({ kind = 3, age = 0.27, pos = Vector(193, 0, 0), cause = 3, att = Vector(180, 0, 0) },
    ring_obj(0, 0, 0), mag, NOW, 128, 0)
local mbok, mbwhy = O.CheckEvent({ kind = 3, age = 0.27, pos = Vector(193, 0, 0), cause = 1, att = Vector(193, 0, 0) },
    ring_obj(0, 0, 0), mag, NOW, 128, 0)
local mfok = O.CheckEvent({ kind = 3, age = 0.27, pos = Vector(193, 0, 0), cause = 3, att = Vector(60, 0, 0) },
    ring_obj(0, 0, 0), mag, NOW, 128, 0)
check(mok and not mbok and not mfok,
    "a ring the Magnetic Barrier pulled, the touch 193 HU from its place: MAGNET accepted (%s), BODY refused (%s), MAGNET "
    .. "with the pulled ring 133 HU from the character refused (review R.3)", tostring(mwhy or "ok"), tostring(mbwhy))
-- 0.9.4 verifier: libsa1 measured a pulled ring caught 275 HU from its place while the character ran away
local mag275 = path(NOW, 0.05, function(tc) return 275, 0, 0 end)
local m275, m275why = O.CheckEvent({ kind = 3, age = 0.27, pos = Vector(275, 0, 0), cause = 3, att = Vector(262, 0, 0) },
    ring_obj(0, 0, 0), mag275, NOW, 128, 0)
local mag400 = path(NOW, 0.05, function(tc) return 400, 0, 0 end)
local m400 = O.CheckEvent({ kind = 3, age = 0.27, pos = Vector(400, 0, 0), cause = 3, att = Vector(390, 0, 0) },
    ring_obj(0, 0, 0), mag400, NOW, 128, 0)
check(m275 and not m400, "a pulled ring caught 275 HU from its place (the measured case): MAGNET accepted (%s); 400 HU "
    .. "refused", tostring(m275why or "ok"))
local here = path(NOW, 0.05, function(tc) return 0, 0, 0 end)
local function ck(e, obj, kind) return O.CheckEvent(e, obj, here, NOW, 128, kind or 0) end
local touch = { pos = Vector(10, 0, 0), att = Vector(10, 0, 0), cause = 1, age = 0.1 }
local function ev(t) local e = {} for k, v in pairs(touch) do e[k] = v end for k, v in pairs(t) do e[k] = v end return e end
local taken = ring_obj(0, 0, 0)
taken.state = 0
local brk = box_obj(0, 0, 0)
brk.broken = true
local d8 = { type = 2, shape = 0, count = 8, size = 40 }
local grp = { type = 2, d = d8, pos = Vector(0, 0, 0), state = 1, bits = { [0] = 0x03 },
              rings = O.RingPositions(d8, Vector(0, 0, 0), Angle(0, 0, 0)) }
local refusals = {
    { ck(ev({ kind = 5 }), ring_obj(0, 0, 0)) },                               -- unknown kind
    { ck(ev({ kind = 3 }), taken) },                                           -- repeated: taken already
    { ck(ev({ kind = 7 }), brk) },                                             -- repeated: broken already
    { ck(ev({ kind = 7 }), ring_obj(0, 0, 0)) },                               -- a ring cannot break
    { ck(ev({ kind = 3 }), box_obj(0, 0, 0)) },                                -- a ground box is never taken whole
    { ck(ev({ kind = 4, index = 0, bits = 0x03 }), grp) },                     -- bits it has already
    { ck(ev({ kind = 4, index = 1, bits = 0x01 }), grp) },                     -- no record 1 in a line of 8
    { ck(ev({ kind = 4, index = 0, bits = 0x100 }), grp) },                    -- (a 9th bit)
    { ck(ev({ kind = 3, age = 5 }), ring_obj(0, 0, 0)) },                      -- 5 s old
}
local nref, whys = 0, {}
for _, r in ipairs(refusals) do
    if not r[1] then nref = nref + 1 end
    whys[#whys + 1] = tostring(r[2])
end
local gok2, _, add = ck(ev({ kind = 4, index = 0, bits = 0x0F, pos = Vector(-40, 0, 0) }), grp)
check(nref == #refusals and gok2 and add == 0x0C,
    "refused %d of %d: an unknown kind, a ring taken already, a box broken already, a ring that breaks, a ground box taken "
    .. "whole, bits the group has, a record the line lacks, a bit beyond 8, a report 5 s old; a group's 0x0F over 0x03 "
    .. "adds 0x%02X", nref, #refusals, add or -1)
-- the sender, the switch, the rate, the hook (O.ServerEvent)
stand(500, 200, 32)
stand(500, 200, 32)
P2.GSA1Active = false
local e1 = { kind = 3, index = 0, bits = 0, age = 0, pos = sring:GetPos(), cause = 1, att = sring:GetPos() }
local nc_ok, nc_why = SO.ServerEvent(P2, sring, e1)
SO.cv.sv_on:SetString("0")
local off_ok, off_why = SO.ServerEvent(P1, sring, e1)
SO.cv.sv_on:SetString("1")
S.hook.Add("GSA1ObjectEvent", "test", function(ply, ent, kind, data) return false end)
local hk_ok, hk_why = SO.ServerEvent(P1, sring, e1)
S.hook.Remove("GSA1ObjectEvent", "test")
P1.GSA1ObjRate = nil
local rate_refused = 0
for _ = 1, 130 do
    local ok, why = SO.ServerEvent(P1, sring, { kind = 5, index = 0, bits = 0, age = 0, pos = sring:GetPos(), cause = 1 })
    if not ok and string.find(tostring(why), "too many", 1, true) then rate_refused = rate_refused + 1 end
end
P1.GSA1ObjRate = nil
check(not nc_ok and not off_ok and not hk_ok and string.find(tostring(hk_why), "GSA1ObjectEvent", 1, true) and
    rate_refused >= 5 and sring:GetState() == 1,
    "refused: a player who is not a character (%s), with gsa1_sv_set 0 (%s), by a GSA1ObjectEvent hook (%s); %d of 130 "
    .. "reports at once over the rate limit", tostring(nc_why), tostring(off_why), tostring(hk_why), rate_refused)

end
-- 7. respawn and reset --------------------------------------------------------------------------------------------------------
do
timed:SetState(1)
stand(700, 200, 0)
stand(700, 200, 0)
local tk, tkwhy = SO.ServerEvent(P1, timed, { kind = 3, index = 0, bits = 0, age = 0, pos = Vector(705, 200, 20),
                                              cause = 1, att = Vector(705, 200, 20) })
local due = timed:GetRespawnAt()
M.T = M.T + 14
run_s("Think")
local still = timed:GetState()
M.T = M.T + 1.2
run_s("Think")
check(tk and timed:GetState() == 1 and still == 0 and due > 0 and timed:GetRespawnAt() == 0,
    "a ring with Respawn after 15 taken (%s): State 0, back to 1 after 15 s (not after 14: %s), RespawnAt cleared (%s)",
    tostring(tkwhy or tk), tostring(still), tostring(timed:GetRespawnAt()))
sbox:SetRespawnAfter(5)
sbox:SetBroken(false)
stand(100, 200, 0)
stand(100, 200, 0)
local bk = SO.ServerEvent(P1, sbox, { kind = 7, index = 0, bits = 0, age = 0, pos = Vector(110, 200, 10), cause = 1,
                                      att = Vector(110, 200, 10) })
local was = sbox:GetBroken()
M.T = M.T + 5.2
run_s("Think")
check(bk and was == true and sbox:GetBroken() == false, "a ground box with Respawn after 5 broken: Broken, whole again 5 s later")
local rings8 = O.RingPositions(O.Describe(sline), sline:GetPos(), sline:GetAngles())
local r0 = sline:GetPos()
for _, r in ipairs(rings8) do if r.record == 1 and r.bit == 1 then r0 = r.pos end end
stand(r0.x, r0.y, r0.z)
stand(r0.x, r0.y, r0.z)
local u1 = SO.ServerEvent(P1, sline, { kind = 4, index = 1, bits = 0x03, age = 0, pos = Vector(r0), cause = 1,
                                       att = Vector(r0) })
single = false
P2.admin, P1.admin = false, true
scmds["gsa1_sv_set_reset"](P2)
local after_p2 = SO.BitsOf(sline, 1)
scmds["gsa1_sv_set_reset"](P1)
single = true
check(after_p2 ~= 0 and SO.BitsOf(sline, 1) == 0 and sline:GetTakenBits() == "" and #P2.chats >= 1 and string.find(P2.chats[#P2.chats], "admin", 1, true),
    "a line's bits taken (0x%02X; first report %s): \"Reset G-SA1 objects\" by a non-admin in multiplayer refused (%s), by "
    .. "an admin: cleared", after_p2 or -1, tostring(u1), tostring(P2.chats[#P2.chats]))

end
-- 8. the render through GSA1.DrawCharacter (review R.1) -----------------------------------------------------------------------
local drawn = {}
local old_emit = G.EmitBatch
function G.EmitBatch(id, i)
    drawn[#drawn + 1] = i
    return old_emit(id, i)
end
local function frame_drawn()
    drawn = {}
    M.frame(1 / 60)
    table.sort(drawn)
    return table.concat(drawn, " ")
end
do
for _ = 1, 4 do frame_drawn() end
local d_tp = frame_drawn()
GSA1.cv.effects:SetString("0")
local d_tp_fx0 = frame_drawn()
GSA1.cv.effects:SetString("1")
GSA1.cv.cam_dist:SetString("0")
local d_fp = frame_drawn()
GSA1.cv.effects:SetString("0")
local d_fp_fx0 = frame_drawn()
GSA1.cv.effects:SetString("1")
GSA1.cv.shadow:SetString("0")
local d_fp_sh0 = frame_drawn()
GSA1.cv.shadow:SetString("1")
RunConsoleCommand("gsa1_set_draw", "0")
local d_fp_off = frame_drawn()
GSA1.cv.cam_dist:SetString("150")
local d_tp_off = frame_drawn()
RunConsoleCommand("gsa1_set_draw", "1")
check(d_tp == "1 2 3 4 5" and d_tp_fx0 == "1 2 4 5" and d_fp == "2 4" and d_fp_fx0 == "2 4" and d_fp_sh0 == "2" and
    d_fp_off == "" and d_tp_off == "1 3 5",
    "batches drawn (1 body, 2 a ring, 3 an effect, 4 the ring's blob, 5 the character's blob): third person \"%s\", "
    .. "Effects off \"%s\" (the ring stays); first person \"%s\" (0.9.3a: nothing), with Effects off \"%s\", Shadows off "
    .. "\"%s\"; gsa1_set_draw 0: first person \"%s\", third person \"%s\"", d_tp, d_tp_fx0, d_fp, d_fp_fx0, d_fp_sh0,
    d_fp_off, d_tp_off)
-- the render entity's bounds cover an object 1,500 HU away (GMod would cull the rings with the character)
C.ent.SetRenderBounds = function(self, a, b) self.rb = { Vector(a), Vector(b) } end
local p = C.drawPos
MOD.bounds = { p.x + 1490, p.y - 10, p.z, p.x + 1510, p.y + 10, p.z + 20 }
frame_drawn()
local rb1 = C.ent.rb
MOD.bounds = nil
frame_drawn()
local rb2 = C.ent.rb
check(rb1 and rb1[2].x >= 1500 and rb1[1].x <= -640 and rb2 and rb2[2].x == 640,
    "the character's render bounds reach %.0f HU along x for a ring 1,500 HU away, and go back to 640 without objects",
    rb1 and rb1[2].x or -1)

end
-- 9. the three scanners ignore a G-SA1 object -----------------------------------------------------------------------------------
do
local cbox = CENTS[sbox.idx]
local fake_prop = setmetatable({ cls = "prop_physics", idx = 4321, pos = Vector(p), ang = Angle(0, 0, 0), GSA1Object = true },
    { __index = EMT })
local old_find = ents.FindInSphere
ents.FindInSphere = function() return { cbox, fake_prop } end
GSA1.Movers.nextScan = 0
local mv0, oa0 = n_of("MoverUpdate"), n_of("ObjAdd")
for _ = 1, 12 do frame_drawn() end
ents.FindInSphere = old_find
local in_list = false
for _, it in ipairs(GSA1.Movers.list or {}) do
    if it.idx == cbox.idx or it.idx == 4321 then in_list = true end
end
local sfake = setmetatable({ cls = "npc_fake", idx = 4322, pos = Vector(0, 0, 0), ang = Angle(0, 0, 0), GSA1Object = true,
                             npc = true, movetype = MOVETYPE_VPHYSICS }, { __index = EMT })
S.found = { sfake }
local REL = SG.Interact and SG.Interact.NET and SG.Interact.NET.REL
local rel0 = REL and count_s(REL) or 0
P1.GSA1Active = true
P1:SetNW2Bool("gsa1_char", true)            -- (GSA1.IsCharacter: the interaction feature's scan runs for characters)
local sv_ok = pcall(SH.Think.gsa1_interact)
S.found = nil
check(not in_list and n_of("MoverUpdate") == mv0 and n_of("ObjAdd") == oa0 and REL ~= nil and count_s(REL) == rel0 and
    sfake.nw2writes == nil,
    "the scanners: the moving-collision scan (cl_collision.lua) and the host-object scan (cl_interact.lua I.Scan) leave "
    .. "a G-SA1 box and a G-SA1 object of class prop_physics out; the server's scan_around (sv_interact.lua) neither "
    .. "relates nor tags one (server Think ran: %s)", tostring(sv_ok))

end
-- 10. the outlines -----------------------------------------------------------------------------------------------------------
do
local cline, cbox = CENTS[sline.idx], CENTS[sbox.idx]
local function markers(fn)
    M.frameNo = M.frameNo + 1
    wire.spheres, wire.boxes = 0, 0
    fn()
    O.DrawMarker(cline)
    O.DrawMarker(cbox)
    return wire.spheres, wire.boxes
end
local s1, b1 = markers(function() M.player.active = nil end)
local s2, b2 = markers(function() M.player.active = { GetClass = function() return "weapon_physgun" end } end)
local s3, b3 = markers(function() RunConsoleCommand("gsa1_set_markers", "0") end)
RunConsoleCommand("gsa1_set_markers", "1")
M.player.active = nil
check(s1 == 0 and b1 == 0 and s2 == 20 and b2 == 1 and s3 == 0 and b3 == 0,
    "outlines: none for a character without the Physics Gun; with it the line's 20 rings and the box (%d, %d); "
    .. "gsa1_set_markers 0: none", s2, b2)

end
-- 11. the Objects page: every setting has a control ---------------------------------------------------------------------------
do
local made = {}
local METHODS
local function standin(kind)
    local P = { kind = kind, calls = {} }
    made[#made + 1] = P
    return setmetatable(P, { __index = function(t, k)
        if METHODS[k] then return METHODS[k] end
        if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
        return function(self, ...)
            t.calls[#t.calls + 1] = { k, ... }
            local child = standin(k)
            child.args = { ... }
            return child
        end
    end })
end
METHODS = { SetText = function(self, s) self.text = s end, SetValue = function(self, s) self.value = s end }
vgui.Create = function(cls) return standin(cls) end
M.menu = {}
M.run_hook("PopulateToolMenu")
local entry
for _, e in ipairs(M.menu) do if e.class == "gsa1_feat_objects" then entry = e end end
check(entry and entry.name == "Objects" and entry.category == "G-SA1", "the page Options -> G-SA1 -> Objects")
if entry then
    local panel = standin("DForm")
    entry.cpanel(panel)
    local bound, ranges, buttons, combo = {}, {}, {}, nil
    for _, Pn in ipairs(made) do
        for _, c in ipairs(Pn.calls) do
            if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then
                bound[c[3]] = true
                if c[1] == "NumSlider" then ranges[c[3]] = { c[4], c[5] } end
            end
            if c[1] == "Button" then buttons[#buttons + 1] = tostring(c[3]) end
            if c[1] == "ComboBox" and c[2] == "Contents of a new item box" then combo = true end
        end
    end
    local missing = {}
    for name in pairs(GSA1.CONVARS) do
        local mine = string.find(name, "^gsa1_set") or string.find(name, "^gsa1_sv_set") or name == "sbox_maxgsa1_objects"
        if mine and not bound[name] and not (name == "gsa1_set_box_content" and combo) then
            missing[#missing + 1] = name
        end
    end
    table.sort(missing)
    local n = 0
    for name in pairs(bound) do n = n + 1 end
    local news = 0
    for _, nm in ipairs({ "gsa1_set_range", "gsa1_set_view_wide", "gsa1_set_view", "gsa1_set_view_edit",
                          "gsa1_set_view_far", "gsa1_set_view_dist", "gsa1_set_view_smooth", "gsa1_set_icons",
                          "gsa1_set_icons_save" }) do
        if bound[nm] and GSA1.CONVARS[nm] then news = news + 1 end
    end
    check(#missing == 0 and combo and n >= 20 and news == 9 and table.concat(buttons, " ") ==
        "gsa1_icons_rebuild gsa1_sv_set_reset" and
        ranges.gsa1_set_ring_window and ranges.gsa1_set_ring_window[2] == 200 and ranges.gsa1_set_box_window[2] == 100 and
        ranges.gsa1_set_range and ranges.gsa1_set_range[1] == 1600 and ranges.gsa1_set_range[2] == 12000 and
        ranges.gsa1_set_view_dist and ranges.gsa1_set_view_dist[2] == 32768 and
        GSA1.CONVARS.gsa1_set_box_content and GSA1.CONVARS.sbox_maxgsa1_objects and GSA1.CONVARS.sbox_maxgsa1_objects.server,
        "every setting has a control (%d check boxes and sliders - the 9 of 0.9.4b among them: %d - the contents combo, the "
        .. "Redraw and reset buttons; sliders 16-200 rings, 4-100 boxes: gsa1.OBJECTS' maxima, review R.9; the range "
        .. "1,600-12,000 HU: owner answer O1; the pictures' distance to 32,768); gsa1_set_box_content (userinfo) and "
        .. "sbox_maxgsa1_objects listed in GSA1.CONVARS by hand (review R.15)%s", n, news,
        #missing > 0 and (": missing " .. table.concat(missing, " ")) or "")
end

end
-- 12. gsa1_set 0 / 1, a removal, a new module generation, an unavailable type ---------------------------------------------------
do
RunConsoleCommand("gsa1_set", "0")
frame_drawn()
local cleared = n_of("SetClear")
local a0 = n_of("SetAdd")
RunConsoleCommand("gsa1_set", "1")
frame_drawn()
check(cleared == 1 and n_of("SetAdd") == a0 + 6, "gsa1_set 0 -> SetClear; 1 -> the %d objects added again",
    n_of("SetAdd") - a0)
local rm0 = n_of("SetRemove")
local ring_now
for _, rec in pairs(O.tracked) do if rec.idx == sring.idx then ring_now = rec.id end end
sring:Remove()
frame_drawn()
local rm = last_of("SetRemove")
check(n_of("SetRemove") == rm0 + 1 and rm and rm[2] == ring_now, "the ring removed on the server -> SetRemove on the client")
MOD.unsupported[4] = true
MOD.gen = MOD.gen + 1
a0 = n_of("SetAdd")
chats = {}
for _ = 1, 30 do frame_drawn() end
local refused = n_of("SetAddRefused")
local said = false
for _, c in ipairs(chats) do if string.find(c, "Item Box (Air) cannot run", 1, true) then said = true end end
MOD.unavailable[4] = true
spawn_list.SpawnableEntities = { gsa1_obj_itembox_air = {}, gsa1_obj_ring = {} }
O.Availability()
check(n_of("SetAdd") == a0 + 4 and refused == 1 and said and CENTS[sair.idx].GSA1Unavailable ~= nil and
    spawn_list.SpawnableEntities.gsa1_obj_itembox_air == nil and spawn_list.SpawnableEntities.gsa1_obj_ring ~= nil,
    "a new module generation: the 4 others added again; the air box the module refuses (\"unsupported\") once in 30 frames, "
    .. "with a chat line and the entity marked; ObjectInfo available false -> left out of the spawn menu")

-- a state that arrives without a NetworkVar notification (older Garry's Mod clients called no proxies): the round-robin
-- look finds it within a few frames
local ccirc = CENTS[scirc.idx]
local crec = O.tracked[scirc.idx]
ccirc.dt.TakenBits = "06"
local s_before = n_of("SetState")
for _ = 1, 8 do frame_drawn() end
local found_bits = false
for i = #MOD.calls, 1, -1 do
    local c = MOD.calls[i]
    if c[1] == "SetState" and crec and c[2] == crec.id and c[4] == 0x06 and c[5] == 0 then found_bits = true break end
end
check(found_bits and n_of("SetState") > s_before, "a circle's TakenBits \"06\" set without a notification: applied by the "
    .. "round-robin look within 8 frames (SetState(circle, PRESENT, 0x06, 0))")
end
-- the "G-SA1" tab at the top of the spawn menu (owner, 0.9.4a: "Like how G64 does"; feat/cl_spawntab.lua)
do
    local T = GSA1.SpawnTab
    local tabs, icons, panels = {}, {}, {}
    local keep_sm, keep_create = spawnmenu.AddCreationTab, vgui.Create
    spawnmenu.AddCreationTab = function(name, fn, icon, order, tip) tabs[#tabs + 1] = { name = name, fn = fn, icon = icon,
        order = order } end
    spawnmenu.CreateContentIcon = function(kind, parent, o) icons[#icons + 1] = { kind = kind, parent = parent, o = o } end
    vgui.Create = function(cls)
        local p = { cls = cls, SetVisible = function() end, SetTriggerSpawnlistChange = function() end }
        p.CallPopulateHook = function(self, h) p.hooked = h end
        panels[#panels + 1] = p
        return p
    end
    local switched
    local content = { SwitchPanel = function(self, pnl) switched = pnl end }
    local nodes = {}
    local tree = { AddNode = function(self, name, icon) local n = { name = name, icon = icon } nodes[#nodes + 1] = n return n end }
    spawn_list.SpawnableEntities = {}
    for _, c in ipairs(O.CLASSES) do
        spawn_list.SpawnableEntities[c.class] = { PrintName = c.title, ScriptedEntityType = "gsa1_object", Category = "G-SA1" }
    end
    spawn_list.SpawnableEntities.gsa1_obj_itembox_air = nil      -- a type the module cannot run (O.Availability took it out)
    local reg = T and T.Register()
    local made = tabs[1] and tabs[1].fn()
    local pop = T and T.Populate(content, tree)
    spawnmenu.AddCreationTab, spawnmenu.CreateContentIcon, vgui.Create = keep_sm, nil, keep_create
    local names = {}
    for _, ic in ipairs(icons) do names[#names + 1] = ic.o.spawnname end
    check(reg == true and #tabs == 1 and tabs[1].name == "G-SA1" and tabs[1].icon == "icon16/coins.png" and
        T.ICON_SIZE == 16 and made and
        made.cls == "SpawnmenuContentPanel" and made.hooked == "PopulateGSA1" and pop == true and #nodes == 1 and
        nodes[1].name == "Rings and Item Boxes" and #icons == 4 and table.concat(names, " ") ==
        "gsa1_obj_ring gsa1_obj_ring_line gsa1_obj_ring_circle gsa1_obj_itembox" and icons[1].kind == "gsa1_object" and
        icons[1].o.material == "entities/gsa1_obj_ring.png" and icons[1].o.nicename == "Ring" and switched ~= nil and
        switched == nodes[1].PropPanel,
        "the G-SA1 spawn-menu tab: registered (%d) with a 16 x 16 icon (0.9.4b, 11.2: not the 128-pixel ring), its panel "
        .. "calls PopulateGSA1, one category 'Rings and Item Boxes' opened at "
        .. "once with the entity icons of the 4 types the module runs (%s; the unavailable air box left out)", #tabs,
        table.concat(names, " "))
end
-- 0.9.4b: the debug sphere has the range's radius (gsa1_set_range) ------------------------------------------------------------
do
    local keepChar = GSA1.Char
    GSA1.Char = { drawPos = Vector(0, 0, 0) }
    local radius
    local keepSphere = render.DrawWireframeSphere
    render.DrawWireframeSphere = function(p, r) radius = r end
    RunConsoleCommand("gsa1_set_debug", "1")
    local fn = M.hooks.PostDrawTranslucentRenderables and M.hooks.PostDrawTranslucentRenderables.gsa1_objects_debug
    if fn then fn(false, false) end
    RunConsoleCommand("gsa1_set_debug", "0")
    render.DrawWireframeSphere = keepSphere
    GSA1.Char = keepChar
    check(radius == O.RANGE and radius == 4800, "the debug sphere (\"Show the objects' range and records\") has the "
        .. "range's radius: %s HU (gsa1_set_range)", tostring(radius))
end
-- 13. 0.9.4.1 ---------------------------------------------------------------------------------------------------------------
-- 13a. 128 rings: the circle split, records, masks, the evenly spaced places, golden places (the same in feat_objects_test.cpp)
do
local function gd(count, size, shape) return { type = 2, shape = shape, count = count, size = size } end
local splits = {}
for _, n in ipairs({ 1, 7, 8, 12, 64, 100, 127, 128 }) do
    local per, m = O.CircleSplit(n)
    splits[#splits + 1] = string.format("%d=%dx%d", n, m, per)
end
local sp = table.concat(splits, " ")
check(sp == "1=1x1 7=1x7 8=2x4 12=2x6 64=16x4 100=20x5 127=127x1 128=32x4",
    "a circle of N rings = m records of n (the largest of 7..1 dividing N): %s", sp)
local c128, c127, l128 = gd(128, 800, 1), gd(127, 800, 1), gd(128, 40, 0)
check(O.RecordCount(c128) == 32 and O.RecordMask(c128, 0) == 0x1E and O.RecordMask(c128, 31) == 0x1E and
    O.RecordMask(c128, 32) == 0 and O.RecordCount(c127) == 127 and O.RecordMask(c127, 126) == 0x02 and
    O.RecordCount(l128) == 16 and O.RecordMask(l128, 15) == 0xFF and O.RecordMask(l128, 16) == 0 and
    O.RecordMask(gd(7, 80, 1), 0) == 0xFE,
    "records and masks: a circle of 128 = 32 records of bits 1..4 (1E), of 127 = 127 records of bit 1 (02), a line of 128 "
    .. "= 16 records of 8 (FF); a circle of 7 still one record (FE)")
local function circle_ok(d, pos, ang)
    local rp = O.RingPositions(d, pos, ang)
    if #rp ~= d.count then return false, "count " .. #rp end
    local per, m = O.CircleSplit(d.count)
    local seen, worst = {}, 0
    local f, l = ang:Forward(), -ang:Right()
    for _, r in ipairs(rp) do
        if seen[r.place] then return false, "place twice" end
        seen[r.place] = true
        local a = math.rad(r.place * 360 / d.count)
        local want = pos + f * (d.size * math.cos(a)) + l * (d.size * math.sin(a))
        worst = math.max(worst, (r.pos - want):Length())
        local i = math.floor(math.log(r.bit) / math.log(2) + 0.5)
        if i < 1 or i > per or (i * m + r.record) % d.count ~= r.place then return false, "record / bit / place" end
    end
    for pl = 0, d.count - 1 do if not seen[pl] then return false, "place missing" end end
    return worst < 1e-6, string.format("worst %.2g HU", worst)
end
local ok1, w1 = circle_ok(c128, Vector(10, 20, 30), Angle(0, 37, 0))
local ok2, w2 = circle_ok(c127, Vector(0, 0, 0), Angle(20, 200, 0))
local ok3, w3 = circle_ok(gd(12, 200, 1), Vector(0, 0, 0), Angle(0, 90, 0))
local lp = O.RingPositions(l128, Vector(0, 0, 0), Angle(0, 0, 0))
local xs, lpl = {}, {}
for _, r in ipairs(lp) do
    xs[#xs + 1] = r.pos.x
    lpl[r.place] = (lpl[r.place] or 0) + 1
end
table.sort(xs)
local even = #xs == 128 and math.abs(xs[1] + 2540) < 1e-6 and math.abs(xs[128] - 2540) < 1e-6
for i = 2, #xs do even = even and math.abs(xs[i] - xs[i - 1] - 40) < 1e-6 end
check(ok1 and ok2 and ok3 and even,
    "the places: circles of 128 (yaw 37), 127 (pitch 20, yaw 200) and 12 (yaw 90) - record k's ring i on place (i m + k) "
    .. "mod N, every place once, place p at p 360 / N from the forward towards the left (%s, %s, %s); a line of 128: 128 "
    .. "rings 40 HU apart from -2540 to +2540", w1, w2, w3)
-- golden places (feat_objects_test.cpp checks the module's ring_positions against the same numbers)
local function find(d, record, bitv)
    for _, r in ipairs(O.RingPositions(d, Vector(0, 0, 0), Angle(0, 0, 0))) do
        if r.record == record and r.bit == bitv then return r end
    end
end
local g1, g2, g3 = find(gd(12, 100, 1), 1, 4), find(gd(128, 100, 1), 31, 16), find(gd(20, 40, 0), 2, 8)
local function at(r, x, y, z) return r and math.abs(r.pos.x - x) < 1e-3 and math.abs(r.pos.y - y) < 1e-3 and
    math.abs(r.pos.z - z) < 1e-3 end
check(g1 and g1.place == 5 and at(g1, -86.60254, 50, 0) and g2 and g2.place == 31 and at(g2, 4.90677, 99.87955, 0) and
    g3 and g3.place == 19 and at(g3, 380, 0, 0),
    "golden places shared with the module's test: a circle of 12 (r 100) record 1 bit 4 -> place 5 (-86.6, 50); of 128 "
    .. "record 31 bit 16 -> place 31 (4.91, 99.88); a line of 20 (40 HU) record 2 bit 8 -> place 19 (380, 0)")
-- the shared state: two hex digits per record
local s1 = O.BitsSet("", 126, 0x02)
local s2 = O.BitsSet(s1, 126, 0)
local s3 = O.BitsSet(O.BitsSet("", 1, 0x05), 0, 0xFF)
check(#s1 == 254 and O.BitsGet(s1, 126) == 2 and O.BitsGet(s1, 125) == 0 and O.BitsGet(s1, 127) == 0 and s2 == "" and
    s3 == "FF05" and O.BitsGet(s3, 1) == 5 and O.BitsGet(nil, 3) == 0 and O.BitsGet(0, 0) == 0,
    "TakenBits: record 126's bits 02 -> a string of %d hex digits; cleared again -> \"\"; records 0 and 1 -> \"%s\"; "
    .. "missing records read 0", #s1, s3)
end

-- 13b. the owner's refused reports replayed (sh_objects.lua O.CheckEvent; log_094_20261026_prev.txt) ---------------------------
do
local NOW = 2000
-- a path sampled every 0.05 s of the server's time from fn(t)
local function path_at(fn, t_end)
    local h = {}
    for t = t_end - 1.4, t_end + 1e-6, 0.05 do
        local x, y, z = fn(t)
        h[#h + 1] = { t = t, x = x, y = y, z = z }
    end
    return h
end
local function group_obj(d, pos)
    return { type = 2, d = d, pos = Vector(pos), state = 1, bits = {},
             rings = O.RingPositions(d, Vector(pos), Angle(0, 0, 0)) }
end
local function nearest_added(obj, k, add, touch)
    local best = math.huge
    for _, r in ipairs(obj.rings) do
        if r.record == k and bit.band(r.bit, add) ~= 0 then best = math.min(best, (r.pos - touch):Length()) end
    end
    return best
end
-- "Ring line 250": a line of 8 (40 HU), Sonic running +x at 1,200 HU/s; the bits of places 1, 2, 3 (bits 10, 04, 01)
-- arrive with the touch of his latest ring (place 6: x 116), 216 / 176 / 137 HU from them
local d8 = { type = 2, shape = 0, count = 8, size = 40 }
local line = group_obj(d8, Vector(0, 0, 0))
local t_touch = NOW - 0.08
local run = path_at(function(t) return 116 + 1200 * (t - t_touch), 0, 0 end, NOW + 0.1)
local touch = Vector(116, 0, 0)
local replay, dists, whys = {}, {}, {}
for i, ev in ipairs({ { bits = 0x10, age = 0.08, now = NOW }, { bits = 0x14, age = 0.115, now = NOW + 0.035 },
                      { bits = 0x15, age = 0.148, now = NOW + 0.068 } }) do
    local add = bit.band(ev.bits, bit.bnot(line.bits[0] or 0))
    dists[i] = nearest_added(line, 0, add, touch)
    local ok, why, got = O.CheckEvent({ kind = 4, index = 0, bits = ev.bits, age = ev.age, pos = touch, cause = 1,
                                        att = touch }, line, run, ev.now, 128, 0)
    replay[i] = ok and got == add
    whys[i] = tostring(why or "ok")
    if ok then line.bits[0] = bit.bor(line.bits[0] or 0, got) end
end
check(replay[1] and replay[2] and replay[3] and dists[1] > 210 and dists[2] > 170 and dists[3] > 130,
    "the owner's \"Ring line 250\" reports (bits 10, 14, 15 with the touch of his latest ring, %.0f / %.0f / %.0f HU from "
    .. "the rings they add: 0.9.4 refused them, at most 64): accepted (%s / %s / %s)", dists[1], dists[2], dists[3],
    whys[1], whys[2], whys[3])
-- "Ring circle 256": a circle of 7 (r 80), Sonic running round it; places 1, 2, 3 reported with the touch at ring 3's
local d7 = { type = 2, shape = 1, count = 7, size = 80 }
local circ = group_obj(d7, Vector(0, 0, 0))
local r3
for _, r in ipairs(circ.rings) do if r.place == 3 then r3 = r.pos end end
local ct = NOW - 0.1
local w = math.rad(360 / 7) / 0.1                     -- one place every 0.1 s
local round = path_at(function(t)
    local a = math.rad(3 * 360 / 7) + w * (t - ct)
    return 80 * math.cos(a), 80 * math.sin(a), 0
end, NOW + 0.1)
local cok, cwhy, cd = {}, {}, {}
for i, ev in ipairs({ { bits = 0x02, age = 0.10 }, { bits = 0x06, age = 0.10 }, { bits = 0x0E, age = 0.10 } }) do
    local add = bit.band(ev.bits, bit.bnot(circ.bits[0] or 0))
    cd[i] = nearest_added(circ, 0, add, r3)
    local ok, why, got = O.CheckEvent({ kind = 4, index = 0, bits = ev.bits, age = ev.age, pos = Vector(r3), cause = 1,
                                        att = Vector(r3) }, circ, round, NOW, 128, 0)
    cok[i], cwhy[i] = ok and got == add, tostring(why or "ok")
    if ok then circ.bits[0] = bit.bor(circ.bits[0] or 0, got) end
end
check(cok[1] and cok[2] and cok[3] and cd[1] > 64 and cd[2] > 64,
    "the owner's \"Ring circle 256\" reports (bits 02, 06, 0E with the touch at ring 3, %.0f / %.0f / %.0f HU from the "
    .. "rings they add): accepted (%s / %s / %s)", cd[1], cd[2], cd[3], cwhy[1], cwhy[2], cwhy[3])
-- a touch at the true ring place; refusals: a touch far from every ring of the record, a ring the path never passed
local fresh = group_obj(d8, Vector(0, 0, 0))
local p0
for _, r in ipairs(fresh.rings) do if r.place == 0 then p0 = r.pos end end       -- place 0: bit 40, x -140
local still = path_at(function(t) return p0.x, p0.y, p0.z end, NOW)
local at_ok, at_why = O.CheckEvent({ kind = 4, index = 0, bits = 0x40, age = 0.1, pos = Vector(p0), cause = 1,
                                     att = Vector(p0) }, fresh, still, NOW, 128, 0)
local far_ok, far_why = O.CheckEvent({ kind = 4, index = 0, bits = 0x40, age = 0.1, pos = Vector(400, 0, 0), cause = 1,
                                       att = Vector(400, 0, 0) }, fresh, path_at(function() return 400, 0, 0 end, NOW), NOW,
                                     128, 0)
local claim_ok, claim_why = O.CheckEvent({ kind = 4, index = 0, bits = 0xC0, age = 0.1, pos = Vector(p0), cause = 1,
                                           att = Vector(p0) }, fresh, still, NOW, 128, 0)
local synthetic = { { t = NOW - 0.1, x = p0.x, y = p0.y, z = p0.z }, synthetic = true }
local sp_ok = O.CheckEvent({ kind = 4, index = 0, bits = 0xC0, age = 0.1, pos = Vector(p0), cause = 1, att = Vector(p0) },
    fresh, synthetic, NOW, 128, 0)
check(at_ok and not far_ok and not claim_ok and sp_ok,
    "a touch at the true ring place (place 0, bit 40) accepted (%s); a touch 260 HU from every ring of the record refused "
    .. "(%s); a character standing at place 0 claiming place 7 too (280 HU away) refused (%s); single player's stand-in "
    .. "path (no positions) leaves the added rings unchecked", tostring(at_why or "ok"), tostring(far_why),
    tostring(claim_why))
end

-- 13c. 128-ring objects through the server and the client ---------------------------------------------------------------------
do
local c127 = S.ents.Create("gsa1_obj_ring_circle")
c127:SetPos(Vector(-2000, 0, 32))
c127:SetCount(127)
c127:SetRadius(600)
c127:Spawn()
local l128 = S.ents.Create("gsa1_obj_ring_line")
l128:SetPos(Vector(-2000, 3000, 32))
l128:SetCount(128)
l128:SetSpacing(40)
l128:Spawn()
M.frame(1 / 60)
local ca, la2
for _, c in ipairs(MOD.calls) do
    if c[1] == "SetAdd" and c[7] == c127.idx then ca = c end
    if c[1] == "SetAdd" and c[7] == l128.idx then la2 = c end
end
check(ca and ca[3] == 2 and ca[4] == 127 and ca[5] == 600 and ca[6] == 1 and la2 and la2[4] == 128 and la2[6] == 0,
    "a circle of 127 and a line of 128 placed: SetAdd(2, 127, 600, circle) and SetAdd(2, 128, 40, line) on the client")
-- record 100 of the circle (place 100) taken by P1 standing there
local r100
for _, r in ipairs(O.RingPositions(O.Describe(c127), c127:GetPos(), c127:GetAngles())) do
    if r.record == 100 then r100 = r end
end
P1.GSA1Active, P1.GSA1Kind = true, 0
P1.GSA1Hist = nil
stand(r100.pos.x, r100.pos.y, r100.pos.z)
stand(r100.pos.x, r100.pos.y, r100.pos.z)
local okr, whyr = SO.ServerEvent(P1, c127, { kind = 4, index = 100, bits = 0x02, age = 0, pos = Vector(r100.pos), cause = 1,
                                            att = Vector(r100.pos) })
M.frame(1 / 60)
local got100
for i = #MOD.calls, 1, -1 do
    local c = MOD.calls[i]
    if c[1] == "SetState" and c[2] == ca[2] and c[5] == 100 then got100 = c break end
end
check(okr and #c127:GetTakenBits() == 202 and SO.BitsOf(c127, 100) == 2 and got100 and got100[4] == 2 and got100[3] == 1,
    "the circle's record 100 (place 100) taken (%s): TakenBits %d hex digits, record 100 = 02; the client puts it into its "
    .. "worlds: SetState(circle, PRESENT, 0x02, record 100)", tostring(whyr or "ok"), #c127:GetTakenBits())
-- the index travels in 8 bits (0.9.4: 3): a report of record 100 from the client reaches the server as record 100
local ev0 = count_c("gsa1_obj_ev")
local rec127 = O.tracked[c127.idx]
event({ kind = 4, id = rec127 and rec127.id, user = c127.idx, type = 2, index = 120, bits = 0x02, x = 0, y = 0, z = 0 })
M.frame(1 / 60)
local m = last_c("gsa1_obj_ev")
check(count_c("gsa1_obj_ev") == ev0 + 1 and m and m.vals[2] == 120, "a USERBITS of record 120 is sent as record %s",
    m and tostring(m.vals[2]) or "-")
-- a refusal sends the whole state back: every record's bits into the client's worlds
local st0 = count_s("gsa1_obj_st")
local s1 = #MOD.calls
local rok = SO.ServerEvent(P1, c127, { kind = 4, index = 101, bits = 0x02, age = 0, pos = Vector(5000, 0, 0), cause = 1,
                                      att = Vector(5000, 0, 0) })
if not rok then SO.SendState(c127, P1, "test refusal") end
local per_record, rec100 = 0, false
for i = s1 + 1, #MOD.calls do
    local c = MOD.calls[i]
    if c[1] == "SetState" and c[2] == ca[2] and c[5] ~= nil then
        per_record = per_record + 1
        if c[5] == 100 and c[4] == 2 then rec100 = true end
    end
end
check(not rok and count_s("gsa1_obj_st") == st0 + 1 and per_record == 127 and rec100,
    "a refused report of record 101 -> gsa1_obj_st with the 127 records' bits; the client sets all %d (record 100 still "
    .. "02)", per_record)
-- respawn / reset: every record's rings back
SO.Respawn(c127, "test")
M.frame(1 / 60)
local back
for i = #MOD.calls, 1, -1 do
    local c = MOD.calls[i]
    if c[1] == "SetState" and c[2] == ca[2] and c[5] == 100 then back = c break end
end
check(c127:GetTakenBits() == "" and back and back[4] == 0, "a respawn clears TakenBits; the client gives record 100 its "
    .. "ring back (SetState bits 0)")
c127:Remove()
l128:Remove()
M.frame(1 / 60)
end

-- 13d. the pick hull ----------------------------------------------------------------------------------------------------------
do
local function hull(cls, count, size)
    local c = O.BY_CLASS[cls]
    return O.Hull({ class = cls, type = c.type, shape = c.shape or 0, count = count or 1, size = size or 0 })
end
local function box_is(mn, mx, a, b) return (mn - a):Length() < 1e-6 and (mx - b):Length() < 1e-6 end
local h1 = { hull("gsa1_obj_ring") }
local h2 = { hull("gsa1_obj_ring_line", 20, 40) }
local h3 = { hull("gsa1_obj_ring_circle", 7, 80) }
local h4 = { hull("gsa1_obj_ring_line", 128, 400) }
local h5 = { hull("gsa1_obj_itembox") }
local h6 = { hull("gsa1_obj_itembox_air") }
check(box_is(h1[1], h1[2], Vector(-24, -24, -24), Vector(24, 24, 24)) and
    box_is(h2[1], h2[2], Vector(-404, -24, -24), Vector(404, 24, 24)) and
    box_is(h3[1], h3[2], Vector(-104, -104, -24), Vector(104, 104, 24)) and
    box_is(h4[1], h4[2], Vector(-25424, -24, -24), Vector(25424, 24, 24)) and
    box_is(h5[1], h5[2], Vector(-20, -20, 0), Vector(20, 20, 60)) and
    box_is(h6[1], h6[2], Vector(-40, -40, -20), Vector(40, 40, 60)),
    "the pick hull is the whole object: a ring 24 HU around, a line of 20 (40 HU) 808 long, a circle of radius 80 208 "
    .. "wide, a line of 128 (400 HU) 50,848 long, the boxes their size")
-- a line of 20 turned to yaw 90 (along +y), its server entity and client copy
local pl = S.ents.Create("gsa1_obj_ring_line")
pl:SetPos(Vector(3000, 0, 32))
pl:SetAngles(Angle(0, 90, 0))
pl:SetCount(20)
pl:SetSpacing(40)
pl:Spawn()
local big = S.ents.Create("gsa1_obj_ring_line")
big:SetPos(Vector(3000, 6000, 32))
big:SetCount(128)
big:SetSpacing(400)
big:Spawn()
M.frame(1 / 60)
local cpl = CENTS[pl.idx]
check(pl.solid == SOLID_OBB and pl.customcol == true and pl.group == COLLISION_GROUP_WORLD and pl.cbounds and
    pl.cbounds[2].x == 404 and pl.phys and pl.phys.motion == false and pl.phys.gravity == false and
    big.box and big.box[2].x == O.PHYS_MAX and big.cbounds[2].x == 25424 and
    cpl and cpl.solid == SOLID_OBB and cpl.customcol == true and cpl.cbounds and cpl.cbounds[2].x == 404,
    "server: SOLID_OBB with custom collisions, the hull as the collision bounds, COLLISION_GROUP_WORLD, a frozen "
    .. "physics box without gravity (a line of 128 x 400 HU: physics %s, collision bounds %s); the client copy: the same "
    .. "shape at once", big.box and tostring(big.box[2].x) or "-", big.cbounds and tostring(big.cbounds[2].x) or "-")
-- TestCollision on the server: P1 holding the Physics Gun, a ray from his shoot position at the line's far end
local wep
function P1:GetActiveWeapon() return wep or NULL end
function P1:GetShootPos() return Vector(self.shoot or self.pos) end
function P2:GetActiveWeapon() return NULL end
local function weapon(cls) return { GetClass = function() return cls end } end
P1.shoot = Vector(2700, 350, 64)
local start, delta = Vector(2700, 350, 64), Vector(600, 0, -64)
wep = weapon("weapon_physgun")
local tr_pg = pl:TestCollision(start, delta, false, Vector(), MASK_SOLID)
wep = weapon("gmod_tool")
local tr_tg = pl:TestCollision(start, delta, false, Vector(), MASK_SOLID)
local tr_box = pl:TestCollision(start, delta, true, Vector(16, 16, 36), MASK_SOLID)
wep = weapon("weapon_pistol")
local tr_gun = pl:TestCollision(start, delta, false, Vector(), MASK_SOLID)
wep = weapon("weapon_physgun")
P1.shoot = Vector(3350, -300, 64)
local tr_miss = pl:TestCollision(Vector(3350, -300, 64), Vector(0, 600, -64), false, Vector(), MASK_SOLID)
P1.shoot = Vector(3000, 0, 32)
local tr_in = pl:TestCollision(Vector(3000, 0, 32), Vector(0, 0, -100), false, Vector(), MASK_SOLID)
P1.shoot = Vector(0, 0, 0)
local tr_far = pl:TestCollision(start, delta, false, Vector(), MASK_SOLID)
local hit_ok = tr_pg and math.abs(tr_pg.Fraction - 0.46) < 1e-6 and math.abs(tr_pg.HitPos.x - 2976) < 1e-3 and
    math.abs(tr_pg.HitPos.y - 350) < 1e-3 and tr_pg.Normal and math.abs(tr_pg.Normal.x + 1) < 1e-6 and tr_tg ~= nil
check(hit_ok and tr_box == nil and tr_gun == nil and tr_miss == nil and tr_in == nil and tr_far == nil,
    "TestCollision (server): a Physics Gun ray at the turned line's far end (350 HU from its middle) hits its hull at "
    .. "(%.0f %.0f %.1f), fraction %.2f, normal facing the player; the Tool Gun's too; a hull trace (player movement), a "
    .. "pistol's ray, a ray where the unturned hull would be, a ray from inside, a ray not from the holder's eyes: no hit",
    tr_pg and tr_pg.HitPos.x or -1, tr_pg and tr_pg.HitPos.y or -1, tr_pg and tr_pg.HitPos.z or -1,
    tr_pg and tr_pg.Fraction or -1)
wep = nil
-- the client: the context menu's ray (from the camera: anywhere) while C is held; the local player's Physics Gun
local keep_pos, keep_act = M.player.pos, M.player.active
M.player.active = nil
local c_none = cpl:TestCollision(start, delta, false, Vector(), MASK_SOLID)
g_ContextMenu = { IsVisible = function() return true end }
local c_menu = cpl:TestCollision(Vector(2600, 350, 300), Vector(800, 0, -536), false, Vector(), MASK_SOLID)
g_ContextMenu = nil
M.player.pos = Vector(2700, 350, 0)                        -- (EyePos = pos + 64: the ray's start)
M.player.active = { GetClass = function() return "weapon_physgun" end }
local c_pg = cpl:TestCollision(start, delta, false, Vector(), MASK_SOLID)
M.player.pos, M.player.active = keep_pos, keep_act
check(c_none == nil and c_menu ~= nil and c_pg ~= nil and math.abs(c_pg.Fraction - 0.46) < 1e-6,
    "TestCollision (client): nothing without the context menu or an editing weapon; the context menu's ray from a camera "
    .. "position hits; the local player's Physics Gun ray hits at the same place as the server's")
-- the Physics Gun: allowed, carried (motion on), frozen at the drop; anything else that unfreezes it undone
local may = pl:PhysgunPickup(P1)
run_s("OnPhysgunPickup", P1, pl)
local carried = pl.phys.motion == true and pl.GSA1Held == true
M.T = M.T + 0.2
run_s("Think")
local still_carried = pl.phys.motion == true
local moved0 = pl:GetMoved()
run_s("PhysgunDrop", P1, pl)
local dropped = pl.phys.motion == false and pl:GetMoved() == moved0 + 1 and pl.GSA1Held == nil
pl.phys:EnableMotion(true)                                -- (the Physics Gun's reload, a dupe)
M.T = M.T + 0.2
run_s("Think")
local refrozen = pl.phys.motion == false
check(may == true and carried and still_carried and dropped and refrozen,
    "the Physics Gun: PhysgunPickup allows it (%s); picked up -> its physics box moves (motion on) and stays so while "
    .. "carried; dropped -> frozen, Moved +1 (the clients move the game's object at once); unfrozen by something else -> "
    .. "frozen again within 0.1 s", tostring(may))
-- a new Count while it is carried: the hull is rebuilt after the drop
run_s("OnPhysgunPickup", P1, pl)
local inits = pl.boxInits
pl:SetCount(30)
M.T = M.T + 0.2
run_s("Think")
local during = pl.boxInits == inits and pl.cbounds[2].x == 404
run_s("PhysgunDrop", P1, pl)
M.T = M.T + 0.2
run_s("Think")
check(during and pl.boxInits == inits + 1 and pl.cbounds[2].x == 29 * 20 + 24 and pl.phys.motion == false,
    "Count 30 while carried: the hull kept until the drop, then rebuilt (half length %s) and frozen", tostring(pl.cbounds[2].x))
-- the context menu: "Enable Collisions" (and the like) left out for G-SA1 objects only
local deny_s = run_s("CanProperty", P1, "collision", pl)
local keep_s = run_s("CanProperty", P1, "remover", pl)
local deny_c = M.run_hook("CanProperty", M.player, "collision", cpl)
local other = run_s("CanProperty", P1, "collision", setmetatable({ cls = "prop_physics" }, { __index = EMT }))
check(deny_s == false and keep_s == nil and deny_c == false and other == nil,
    "CanProperty: \"collision\" refused for a G-SA1 object (both realms), \"remover\" left to the gamemode, a prop untouched")
pl:Remove()
big:Remove()
M.frame(1 / 60)
end

M.player.active = nil
check(#M.reported == 0, "no Lua error (%s)", M.reported[1] or "none")
return done()
