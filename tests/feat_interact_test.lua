-- feat_interact_test.lua - the interaction feature's addon side (addon/lua/gsa1/feat/sh_interact.lua, cl_interact.lua,
-- sv_interact.lua, cl_hud.lua; plan gsa1_rounds_plan.md 9.3 with the owner's additions: pushing props, the interact
-- button, the ring HUD) in Garry's Mod's own LuaJIT: the client through the autorun against tests/lua_mock.lua and a mock
-- of the module's interaction functions (bind_interact.cpp's Lua API, every call recorded); the server's files in their
-- own environment with a small model of Garry's Mod's entities, physics objects, damage and net messages (delivered at
-- once between the realms, single player).
--   lua_host tests/feat_interact_test.lua <tests dir> <addon/lua dir>
-- Checks: the settings (each with a control on the Interaction page) and their defaults (owner decisions 1-7); the pure
-- rules on a synthetic list of NPCs, players, vehicles, props, balloons and hazards (category, kind and flags, shapes);
-- the push model (mass, rolling, the server's cap, standing on a prop); the interact key's target search (a door, a
-- button above a short character, the parent of a part, nothing behind, an occluded one) and Source's use rules; a client
-- frame registering the entities, moving them, sending hits by the category switches, lifts and throws, contacts as
-- pushes, a ball stopped short of a prop as an impact, the interact key (a lift with the action button, a use request);
-- the server applying hits as damage (scaled per attack, reach, rate, the GSA1CanDamage hook, PvP in rings mode, a
-- balloon), pushes as impulses, holding (frozen, the pose, the throw, a refused lift), the interact key (PlayerUse,
-- Entity:Use, a momentary button every tick, KeyDown(IN_USE) while held, a vehicle), damage to the character's player
-- (forwarded and blocked in rings mode), NPC kills; the HUD.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_interact_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files (other features have their own tests)
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_interact%.lua$") or n == "cl_hud.lua" then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end

-- GMod constants and helpers the mock lacks ------------------------------------------------------------------------------
MOVETYPE_VPHYSICS, MOVETYPE_NOCLIP, MOVETYPE_WALK = 6, 8, 2
MASK_SOLID, CONTENTS_DEBRIS, IN_USE = 33570827, 0x4000000, 32
USE_OFF, USE_ON, USE_SET, USE_TOGGLE = 0, 1, 2, 3
COLLISION_GROUP_NONE = 0
D_HT, D_FR, D_LI, D_NU = 1, 2, 3, 4
DMG_FALL, DMG_DROWN, DMG_DROWNRECOVER, DMG_BULLET = 32, 16384, 524288, 2
local VMT = getmetatable(Vector())
function VMT:Dot(v) return self.x * v.x + self.y * v.y + self.z * v.z end
function VMT:DistToSqr(v) local d = self - v return d:Dot(d) end
function VMT:IsZero() return self.x == 0 and self.y == 0 and self.z == 0 end
function VMT:Normalize()
    local l = self:Length()
    if l > 0 then self:Mul(1 / l) end
end
function VMT:GetNormalized() local v = Vector(self) v:Normalize() return v end
function VMT:Rotate(a)
    local f, r, u = a:Forward(), a:Right(), a:Up()
    local x, y, z = self.x, self.y, self.z
    self.x = f.x * x - r.x * y + u.x * z
    self.y = f.y * x - r.y * y + u.y * z
    self.z = f.z * x - r.z * y + u.z * z
end
VMT.__div = function(a, k) return Vector(a.x / k, a.y / k, a.z / k) end
render.DrawWireframeBox, render.DrawWireframeSphere = function() end, function() end
local drawn = {}
draw.SimpleTextOutlined = function(text) drawn[#drawn + 1] = tostring(text) end
surface.CreateFont = function() end
local keys = {}
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    LookupBinding = function(b) return b == "+use" and "e" or nil end,
    GetKeyCode = function(name) return name == "e" and 15 or 0 end,
    GetKeyName = function(code) return code == 15 and "e" or tostring(code) end,
}
local KEY_E = 15

-- entities (one set for both realms: single player) ------------------------------------------------------------------------
local E = {}                    -- [index] = entity
local EMT = {}
EMT.__index = EMT
local function phys_object(mass, moveable)
    return { mass = mass, motion = moveable ~= false, vel = Vector(), impulses = {}, woke = 0,
             GetMass = function(s) return s.mass end, IsMoveable = function(s) return s.motion end,
             IsMotionEnabled = function(s) return s.motion end, EnableMotion = function(s, b) s.motion = b end,
             Wake = function(s) s.woke = s.woke + 1 end, SetVelocity = function(s, v) s.vel = Vector(v) end,
             GetVelocity = function(s) return Vector(s.vel) end,
             ApplyForceOffset = function(s, imp, at) s.impulses[#s.impulses + 1] = { imp = Vector(imp), at = Vector(at) } end }
end
local function new_ent(idx, cls, pos, t)
    t = t or {}
    local e = setmetatable({ idx = idx, cls = cls, pos = Vector(pos), ang = t.ang or Angle(0, 0, 0),
                             mins = t.mins or Vector(-16, -16, 0), maxs = t.maxs or Vector(16, 16, 72), nw2 = {},
                             spawnflags = t.spawnflags or 0, movetype = t.movetype or 0, used = {}, damage = {},
                             health = t.health or 0, group = 0 }, EMT)
    for k, v in pairs(t) do if e[k] == nil then e[k] = v end end
    E[idx] = e
    return e
end
function EMT:EntIndex() return self.idx end
function EMT:GetClass() return self.cls end
function EMT:GetModel() return self.model or "models/props_junk/wood_crate001a.mdl" end
function EMT:IsNPC() return self.npc == true end
function EMT:IsNextBot() return self.nextbot == true end
function EMT:IsPlayer() return false end
function EMT:IsVehicle() return self.vehicle == true end
function EMT:IsWeapon() return false end
function EMT:IsWorld() return false end
function EMT:IsScripted() return self.scripted == true end
function EMT:GetPos() return Vector(self.pos) end
function EMT:SetPos(p) self.pos = Vector(p) end
function EMT:GetAngles() return Angle(self.ang) end
function EMT:SetAngles(a) self.ang = Angle(a) end
function EMT:OBBMins() return Vector(self.mins) end
function EMT:OBBMaxs() return Vector(self.maxs) end
function EMT:OBBCenter() return (self.mins + self.maxs) * 0.5 end
function EMT:WorldSpaceCenter() local c = self:OBBCenter() c:Rotate(self.ang) return self.pos + c end
function EMT:NearestPoint(p)
    local c = self:WorldSpaceCenter()
    local hx, hy, hz = (self.maxs.x - self.mins.x) / 2, (self.maxs.y - self.mins.y) / 2, (self.maxs.z - self.mins.z) / 2
    return Vector(math.Clamp(p.x, c.x - hx, c.x + hx), math.Clamp(p.y, c.y - hy, c.y + hy), math.Clamp(p.z, c.z - hz, c.z + hz))
end
function EMT:GetNW2Bool(k, d) local v = self.nw2[k] if v == nil then return d end return v end
EMT.GetNW2Int, EMT.GetNW2Entity = EMT.GetNW2Bool, function(s, k) return s.nw2[k] or NULL end
function EMT:SetNW2Bool(k, v) self.nw2[k] = v end
EMT.SetNW2Int, EMT.SetNW2Entity = EMT.SetNW2Bool, EMT.SetNW2Bool
function EMT:GetMoveType() return self.movetype end
function EMT:GetPhysicsObject() return self.phys or NULL end
function EMT:HasSpawnFlags(f) return bit.band(self.spawnflags, f) == f end
function EMT:GetParent() return self.parent or NULL end
function EMT:Use(a, c, t, v) self.used[#self.used + 1] = { a = a, t = t, v = v } end
function EMT:TakeDamageInfo(d) self.damage[#self.damage + 1] = d end
function EMT:Health() return self.health end
function EMT:SetCollisionGroup(g) self.group = g end
function EMT:GetCollisionGroup() return self.group end
function EMT:SetRenderOrigin(p) self.renderOrigin = p end
function EMT:SetRenderAngles(a) self.renderAngles = a end
function EMT:IsPlayerHolding() return false end
function EMT:SetPhysicsAttacker(p) self.physAttacker = p end
function EMT:Disposition(ply) return self.disp or D_HT end
function Entity(i) return E[i] or NULL end

-- the local player, in both realms
local ply = M.player
ply.idx = 1
E[1] = ply
function ply:EntIndex() return 1 end
function ply:IsNPC() return false end
function ply:IsNextBot() return false end
function ply:IsVehicle() return false end
function ply:IsWeapon() return false end
function ply:IsWorld() return false end
function ply:Ping() return 0 end
function ply:Alive() return true end
function ply:InVehicle() return self.vehicle_in ~= nil end
function ply:EnterVehicle(v) self.vehicle_in = v end
function ply:Kill() self.killed = true end
function ply:IsTyping() return false end
function ply:OBBMins() return Vector(-16, -16, 0) end
function ply:OBBMaxs() return Vector(16, 16, 72) end
function ply:GetMoveType() return MOVETYPE_NOCLIP end
ply.pos = Vector(0, 0, 0)

local found = {}                -- what ents.FindInSphere returns (both realms)
ents.FindInSphere = function() return found end

-- the server realm: its own globals over the mock's, its hooks, its net -----------------------------------------------------
local S = setmetatable({}, { __index = _G })
S.SERVER, S.CLIENT = true, false
local SH, recv_s, recv_c, strings = {}, {}, {}, {}
local GM_S = { PlayerUse = function() return true end, AllowPlayerPickup = function() return true end,
               CanPlayerEnterVehicle = function() return true end }
local function call(hooks, gm, ev, ...)
    for _, fn in pairs(hooks[ev] or {}) do
        local a, b = fn(...)
        if a ~= nil then return a, b end
    end
    local g = gm[ev]
    if g then return g(gm, ...) end
end
local function S_call(ev, ...) return call(SH, GM_S, ev, ...) end
S.hook = { Add = function(ev, name, fn) SH[ev] = SH[ev] or {} SH[ev][name] = fn end,
           Remove = function(ev, name) if SH[ev] then SH[ev][name] = nil end end,
           Run = function(ev, ...) return S_call(ev, ...) end }
local SCV = {}
S.CreateConVar = function(name, default)
    local c = setmetatable({ name = name, v = tostring(default) }, getmetatable(M.cv("fps_max")))
    SCV[name] = c
    return c
end
S.GetConVar = function(n) return SCV[n] end
S.player = { GetAll = function() return { ply } end }
S.weapons = { Register = function() end, GetStored = function() end }
S.AddCSLuaFile = function() end
S.include = function(rel)
    local src = host_read(M.root .. "/" .. rel)
    if not src then error("server include: no file " .. rel) end
    local fn, err = host_load(src, "sv:" .. rel)
    if not fn then error(err) end
    setfenv(fn, S)
    fn()
end
S.CurTime = function() return M.T end
S.FindMetaTable = function(n) if n == "Player" then return S.PLAYER_META end end
S.PLAYER_META = { KeyDown = function(self, k) return (self.keysDown or 0) % (2 * k) >= k end }
S.scripted_ents = { Get = function(cls) if cls == "gmod_button" or cls == "keypad" then return { Use = function() end } end end }
local DMT = {}
DMT.__index = DMT
for _, n in ipairs({ "Damage", "Attacker", "Inflictor", "DamageType", "DamagePosition", "DamageForce",
                     "ReportedPosition" }) do
    DMT["Set" .. n] = function(s, v) s[n] = v end
    DMT["Get" .. n] = function(s) return s[n] end
end
S.DamageInfo = function() return setmetatable({}, DMT) end
S.util = {
    AddNetworkString = function(n) strings[n] = true end,
    IsInWorld = function() return true end,
    TraceHull = function(t) return S.trace_result and S.trace_result(t) or { Hit = false, HitPos = Vector(t.endpos) } end,
    TraceLine = function(t) return { Hit = false, Fraction = 1, HitPos = Vector(t.endpos) } end,
}
-- net, both directions, delivered at once
local function writer()
    local m = { vals = {} }
    local function push(v) m.vals[#m.vals + 1] = v end
    return m, push
end
local out_c, out_s
local function reader(vals)
    local i = 0
    return function() i = i + 1 return vals[i] end
end
local sent_c, sent_s = {}, {}
net.Start = function(name) out_c = { name = name, vals = {} } end
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteFloat", "WriteVector", "WriteNormal", "WriteEntity", "WriteString" }) do
    net[w] = function(v) if out_c then out_c.vals[#out_c.vals + 1] = type(v) == "table" and Vector(v) or v end end
end
net.Receive = function(name, fn) recv_c[name] = fn end
local cread
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadFloat", "ReadVector", "ReadNormal", "ReadEntity", "ReadString" }) do
    net[r] = function() return cread() end
end
net.SendToServer = function()
    local m = out_c
    out_c = nil
    if not m then return end
    sent_c[#sent_c + 1] = m
    local fn = recv_s[m.name]
    if fn then
        local saved = S.sread
        S.sread = reader(m.vals)
        fn(#m.vals * 8, ply)
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
        sent_s[#sent_s + 1] = m
        local fn = recv_c[m.name]
        if fn then
            local saved = cread
            cread = reader(m.vals)
            fn(#m.vals * 8)
            cread = saved
        end
    end,
}
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteFloat", "WriteVector", "WriteNormal", "WriteString" }) do
    S.net[w] = function(v) if out_s then out_s.vals[#out_s.vals + 1] = type(v) == "table" and Vector(v) or v end end
end
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadFloat", "ReadVector", "ReadNormal", "ReadString" }) do
    S.net[r] = function() return S.sread() end
end
util.NetworkStringToID = function(n) return strings[n] and 1 or 0 end

local function last_c(name)
    for i = #sent_c, 1, -1 do if sent_c[i].name == name then return sent_c[i] end end
end
local function count_c(name)
    local n = 0
    for _, m in ipairs(sent_c) do n = n + (m.name == name and 1 or 0) end
    return n
end
local function count_s(name)
    local n = 0
    for _, m in ipairs(sent_s) do n = n + (m.name == name and 1 or 0) end
    return n
end

-- the server's files: its config, the shared net file, this feature (sv_gsa1.lua is the weapon test's) --------------------
rawset(S, "GSA1", {})
local ok_s, err_s = pcall(function()
    S.include("gsa1/sh_config.lua")
    S.include("gsa1/sh_net.lua")
    S.include("gsa1/feat/sh_interact.lua")
    S.include("gsa1/feat/sv_interact.lua")
end)
local SG = rawget(S, "GSA1")
local SI = SG and SG.Interact

-- the client: the autorun with a mock module that has the interaction feature -------------------------------------------------
GSA1 = nil
local G = M.module({ features = { interact = 1 } })
local MOD = { calls = {}, objects = {}, events = {}, contacts = {}, held = nil, st = { rings = 7, score = 120, lives = 4,
              held_object = 0, held = 0, ball = false, mode = 2, dead = false } }
local function rec(name, ...) MOD.calls[#MOD.calls + 1] = { name, ... } end
local function n_of(name)
    local n = 0
    for _, c in ipairs(MOD.calls) do n = n + (c[1] == name and 1 or 0) end
    return n
end
function G.ObjAdd(ent, kind, flags, x, y, z, yaw, armor, touch, cooldown, nshapes, form, cx, cy, cz, sx, sy, sz, syaw,
                  sflags, launch, reach)
    rec("ObjAdd", ent, kind, flags)
    MOD.objects[ent] = { kind = kind, flags = flags, touch = touch, form = form, sx = sx, sy = sy, sz = sz, launch = launch,
                         x = x, y = y, z = z }
    return ent + 1000, true
end
G.ObjUpdate = G.ObjAdd
function G.ObjMove(ent, x, y, z, yaw)
    rec("ObjMove", ent)
    if not MOD.objects[ent] then return false, "the entity is not registered" end
    return true
end
function G.ObjRemove(ent, killed) rec("ObjRemove", ent, killed) MOD.objects[ent] = nil return true end
function G.ObjClear() rec("ObjClear") MOD.objects = {} return 0 end
function G.ObjEvents(out)
    out = out or {}
    for i, e in ipairs(MOD.events) do out[i] = e end
    out.count = #MOD.events
    MOD.events = {}
    return out
end
function G.ObjConfig(w) rec("ObjConfig", w) return true end
function G.ObjHeld(id)
    local h = MOD.held
    if not h then return nil end
    -- 0.9.3a (interact 2): the drawn steps after the 0.9.3 values when the test gives them
    if h.dx then
        return h.ent, 2, h.x, h.y, h.z, h.px or h.x, h.py or h.y, h.pz or h.z, h.yaw, h.x, h.y, h.z, h.dx, h.dy, h.dz, h.dpx,
            h.dpy, h.dpz, h.dyaw, h.dpyaw
    end
    return h.ent, 2, h.x, h.y, h.z, h.x, h.y, h.z, h.yaw, h.x, h.y, h.z
end
function G.ObjRelease(ent) rec("ObjRelease", ent) return true end
function G.ObjInfo() return { proxies = 3, refused = 0 } end
function G.Damage(id, flags, sx, sy, sz, ent) rec("Damage", id, flags, sx, sy, sz, ent) return true end
function G.SetCharOption(id, o, v) rec("SetCharOption", id, o, v) return true end
function G.AddRings() return true end
function G.StateEx(id, out)
    out = out or {}
    for k, v in pairs(MOD.st) do out[k] = v end
    return out
end
function G.Contacts(id, out)
    out = out or {}
    for i, c in ipairs(MOD.contacts) do out[i] = c end
    out.count = #MOD.contacts
    MOD.contacts = {}
    return out
end
G.INTERACT = { ENEMY = 1, HOLDABLE = 5, BALLOON = 6, SOLID = 1, HITF_LAUNCHED = 8 }

M.included = {}
local ok_c, err_c = pcall(M.load, "autorun/gsa1_autorun.lua")
local I = GSA1 and GSA1.Interact
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
check(ok_s and SI ~= nil and ok_c and #ferr == 0 and I ~= nil and GSA1.Hud ~= nil,
    "both realms load: the server's sh_interact + sv_interact (%s), the client's sh_interact, cl_hud and cl_interact "
    .. "through the autorun (%s)", tostring(err_s or "ok"), ok_c and table.concat(GSA1.FeatureFiles or {}, " ")
    or tostring(err_c or ferr[1]))
if not (I and SI) then return done() end
check(n_of("ObjAdd") == 0 and n_of("SetCharOption") == 0, "nothing calls the module while the files load")
local NET = I.NET
local nets = 0
for _, n in pairs(NET) do nets = nets + (strings[n] and 1 or 0) end
check(nets == 17, "the server registers the feature's 17 network strings (%d; 0.9.2: gsa1_player_died, gsa1_respawn)", nets)

-- 1. settings: defaults (owner decisions) and every one on the page -----------------------------------------------------------
local function cvv(name) local c = M.convars[name] return c and c.v end
local function scv(name) local c = SCV[name] return c and c.v end
check(cvv("gsa1_interact") == "1" and cvv("gsa1_hostile_attack") == "1" and cvv("gsa1_hostile_target") == "2" and
    cvv("gsa1_hostile_touch") == "1" and cvv("gsa1_neutral_touch") == "0" and cvv("gsa1_friendly_attack") == "0" and
    cvv("gsa1_friendly_target") == "0" and cvv("gsa1_vehicle_target") == "2" and cvv("gsa1_player_attack") == "1" and
    cvv("gsa1_prop_push") == "1" and cvv("gsa1_hold") == "1" and cvv("gsa1_balloon") == "1" and cvv("gsa1_interact_key") == "0",
    "client defaults: interaction on; hostile NPCs attacked, targeted, harmful to touch; neutral ones not harmful (decision "
    .. "3); friendly NPCs left alone; vehicles and players targets; props pushed and carried; balloons on; interact = +use")
check(scv("gsa1_sv_damage_mode") == "0" and scv("gsa1_sv_pvp") == "1" and scv("gsa1_sv_dmg_spin") == "50" and
    scv("gsa1_sv_dmg_laser") == "80" and scv("gsa1_sv_hold_mass") == "35" and scv("gsa1_sv_interact") == "1",
    "server defaults: rings mode (decision 1), PvP on (decision 4), scaled damage per attack (decision 2: spin 50, laser "
    .. "80), props up to 35 kg, the interact key allowed")
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
            return standin(k)
        end
    end })
end
METHODS = { SetText = function(self, s) self.text = s end, SetValue = function(self, s) self.value = s end,
            SetConVar = function(self, c) self.convar = c end }
vgui.Create = function(cls) return standin(cls) end
M.menu = {}
M.run_hook("PopulateToolMenu")
local entry
for _, e in ipairs(M.menu) do if e.class == "gsa1_feat_interact" then entry = e end end
check(entry and entry.name == "Interaction" and entry.category == "G-SA1", "the page Options -> G-SA1 -> Interaction")
if not entry then return done() end
local panel = standin("DForm")
entry.cpanel(panel)
local bound = {}
for _, P in ipairs(made) do
    for _, c in ipairs(P.calls) do
        if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then bound[c[3]] = true end
        if c[1] == "ComboBox" then P.isCombo = true end
    end
    if P.convar then bound[P.convar] = true end
end
-- combo boxes set their ConVar through OnSelect: find them by their choices
for _, c in ipairs(I.CATEGORIES) do
    if c.target then bound["gsa1_" .. c.id .. "_target"] = bound["gsa1_" .. c.id .. "_target"] or false end
end
local combos = 0
for _, P in ipairs(made) do if P.kind == "ComboBox" and P.OnSelect then combos = combos + 1 end end
local missing = {}
for name, d in pairs(GSA1.CONVARS) do
    local mine = string.find(name, "^gsa1_interact") or string.find(name, "_attack$") or string.find(name, "_target$") or
        string.find(name, "_touch$") or string.find(name, "^gsa1_push") or
        string.find(name, "^gsa1_sv_") or string.find(name, "^gsa1_balloon") or string.find(name, "^gsa1_hold") or
        name == "gsa1_prop_push" or name == "gsa1_can_die" or name == "gsa1_lose_rings" or
        name == "gsa1_knockback_from_source" or name == "gsa1_solid_npcs" or name == "gsa1_obj_window" or
        name == "gsa1_obj_debug" or name == "gsa1_vehicle_return" or name == "gsa1_lift_key"
    local is_combo = string.find(name, "_target$") or name == "gsa1_balloon_launch" or name == "gsa1_sv_damage_mode"
    if mine and not bound[name] and not is_combo then missing[#missing + 1] = name end
end
table.sort(missing)
check(#missing == 0 and combos >= 7, "every setting of the feature has a control on the page (check boxes, sliders, the "
    .. "key binder; %d combo boxes for targeting, the balloon launch and the damage mode)%s", combos,
    #missing > 0 and (": missing " .. table.concat(missing, " ")) or "")
local page_text = {}
for _, P in ipairs(made) do
    for _, c in ipairs(P.calls) do if c[1] == "Help" or c[1] == "ControlHelp" then page_text[#page_text + 1] = tostring(c[2]) end end
end
local pt = table.concat(page_text, " ")
check(string.find(pt, "Interact - doors, buttons", 1, true) ~= nil and string.find(pt, "Action - spin dash", 1, true) ~= nil
    and string.find(pt, "could not be built", 1, true) == nil,
    "the page documents the key layout (jump, the game's action button lifts / throws, interact = E) and builds cleanly")

-- 2. the pure rules ------------------------------------------------------------------------------------------------------------
local K = I.K
local s = I.Settings()
local function cat(t) return I.Category(t) end
check(cat({ class = "npc_zombie", npc = true }) == "hostile" and cat({ class = "npc_citizen", npc = true }) == "friendly" and
    cat({ class = "npc_citizen", npc = true, rel = I.REL_HOSTILE }) == "hostile" and
    cat({ class = "npc_combine_s", npc = true, rel = I.REL_NEUTRAL }) == "neutral" and
    cat({ class = "my_nextbot", nextbot = true }) == "hostile" and cat({ class = "player", player = true }) == "player" and
    cat({ class = "prop_vehicle_jeep", vehicle = true }) == "vehicle" and cat({ class = "lvs_wheeldrive_car" }) == "vehicle"
    and cat({ class = "gmod_balloon" }) == "balloon" and cat({ class = "env_fire" }) == "hazard" and
    cat({ class = "prop_physics", holdable = true }) == "holdable" and cat({ class = "prop_physics", hp = 50 }) == "breakable"
    and cat({ class = "func_breakable" }) == "breakable" and cat({ class = "prop_physics" }) == nil and
    cat({ class = "func_door" }) == nil,
    "categories of a synthetic entity list: zombie hostile, citizen friendly (hostile once the server says so), a "
    .. "NextBot hostile, players, vehicles (LVS too), balloons, fire, a liftable prop, props with health; a plain prop "
    .. "and a door are no host object")
local function desc(c, inf) return { I.Describe(c, s, inf or {}) } end
local d_h, d_n, d_f, d_v, d_p = desc("hostile"), desc("neutral"), desc("friendly"), desc("vehicle"), desc("player")
local d_b, d_hold, d_bal, d_haz = desc("breakable"), desc("holdable", { hp = 20, movers = true }), desc("balloon"), desc("hazard")
check(d_h[1] == K.ENEMY and d_h[2] == K.SOLID and d_h[3] == 1 and d_n[1] == K.ENEMY and d_n[3] == 0 and d_f[1] == nil and
    d_v[1] == K.TARGET and d_v[2] == K.NO_BONUS + K.NOT_SOLID and d_p[1] == K.ENEMY and d_p[3] == 0 and
    d_b[1] == K.TARGET and d_b[2] == K.NO_HOMING + K.NO_BONUS + K.NOT_SOLID and d_hold[1] == K.HOLDABLE and
    d_hold[2] == K.NOT_SOLID + K.HOLD_HITS and d_bal[1] == K.BALLOON and d_haz[1] == K.HAZARD and d_haz[3] == 2,
    "kinds and flags (addendum 6.3.1): hostile ENEMY solid touch 1; neutral ENEMY touch 0; friendly nothing; vehicles "
    .. "TARGET (no bonus); players ENEMY touch 0; breakable props E-102's targets; a liftable prop with health HOLDABLE "
    .. "with hits (its moving object is its body); balloons; hazards touch 2")
local s2 = I.Settings()
s2.hostile.target, s2.hostile.attack, s2.hostile.touch = 0, false, false
s2.vehicle.target = 1
s2.pvp = false
local off = { I.Describe("hostile", s2, {}) }
s2.hostile.attack = true
local t0 = { I.Describe("hostile", s2, {}) }
local v1 = { I.Describe("vehicle", s2, {}) }
check(off[1] == nil and t0[2] == K.NO_HOMING + K.NO_LOCKON + K.SOLID and v1[2] == K.NO_HOMING + K.NO_BONUS + K.NOT_SOLID and
    I.Describe("player", s2, {}) == nil,
    "the per-category switches (decision 6): everything off -> no object; targeting 0 -> neither homing nor lock-on; 1 -> "
    .. "E-102's lock-on only; PvP off on the server -> players are no objects")
local f1, a1, b1 = I.ShapeFromOBB("hostile", "npc_zombie", Vector(-16, -16, 0), Vector(16, 16, 72))
local f2 = I.ShapeFromOBB("hostile", "npc_manhack", Vector(-8, -8, -4), Vector(8, 8, 4))
local f3, x3, y3, z3 = I.ShapeFromOBB("breakable", "prop_physics", Vector(-20, -10, 0), Vector(20, 10, 30))
local f4, r4 = I.ShapeFromOBB("player", "player", Vector(-16, -16, 0), Vector(16, 16, 72), true)
check(f1 == K.CYLINDER and math.abs(a1 - 12.8) < 1e-6 and b1 == 36 and f2 == K.SPHERE and f3 == K.BOX and x3 == 20 and
    y3 == 10 and z3 == 15 and f4 == K.CYLINDER and r4 == 16,
    "shapes from the OBB: an NPC a cylinder (r %.1f, half height %g), a manhack a sphere, a prop a box of its half "
    .. "extents, another G-SA1 player its character's size", a1, b1)
-- the push model
local dir = { I.PushDirection(K.CONTACT_SIDE, -1, 0, 0) }
local up = { I.PushDirection(K.CONTACT_HEAD, 0, 0, -1) }
local light = I.PushDeltaV(473, 0, 60, 10, 1)
local heavy = I.PushDeltaV(473, 0, 60, 500, 1)
local rolled = I.PushDeltaV(473, 0, 60, 10, I.PushFactor(1, true, 2, 4))
local capped = I.PushFactor(4, true, 4, 4)
check(dir[1] == 1 and dir[2] == 0 and up[3] == 1 and I.PushDirection(K.CONTACT_LANDING, 0, 0, 1) == nil and
    I.PushDirection(K.CONTACT_SIDE, 0, 0, 1) == nil and light > 400 and heavy < light / 6 and math.abs(rolled - 2 * light) < 1e-6
    and capped == 4 and I.PushDeltaV(473, 500, 60, 10, 1) == 0 and I.PushDeltaV(1e6, 0, 250, 1, 4) == I.PUSH_DV_MAX,
    "the push (owner addition A): away from the character; up from below; a landing never pushes; a 10 kg crate gains "
    .. "%.0f HU/s from a run at 473 HU/s, a 500 kg one %.0f; rolling twice that; the server's cap; nothing when the prop "
    .. "is faster; at most %d HU/s", light, heavy, I.PUSH_DV_MAX)
-- Source's use rules
local function has(f) return function(x) return bit.band(f, x) == x end end
check(I.UseKind({ class = "func_door", spawnflags = has(0) }) == nil and
    I.UseKind({ class = "func_door", spawnflags = has(256) }) == "impulse" and
    I.UseKind({ class = "prop_door_rotating", spawnflags = has(0) }) == "impulse" and
    I.UseKind({ class = "prop_door_rotating", spawnflags = has(32768) }) == nil and
    I.UseKind({ class = "func_button", spawnflags = has(0) }) == "impulse" and
    I.UseKind({ class = "func_button", spawnflags = has(256) }) == nil and
    I.UseKind({ class = "func_button", spawnflags = has(256 + 1024) }) == "impulse" and
    I.UseKind({ class = "momentary_rot_button" }) == "continuous" and I.UseKind({ class = "gmod_button", sent_use = true })
    == "impulse" and I.UseKind({ class = "prop_vehicle_jeep", vehicle = true }) == "vehicle" and
    I.UseKind({ class = "npc_citizen", npc = true }) == nil and I.UseKind({ class = "prop_physics" }) == nil,
    "use rules: a func_door only with \"Use Opens\", a prop_door_rotating unless \"Ignore player +USE\", a func_button "
    .. "unless touch-only, momentary buttons held, scripted entities with a Use (gmod_button, keypads), vehicles")
-- the target search
local door = { name = "door", x = 60, y = 0, z = 20 }
local button = { name = "button", x = 50, y = 0, z = 60 }
local behind = { name = "behind", x = -40, y = 0, z = 20 }
local function env_with(things, blocked)
    return {
        trace = function(a, b)
            for _, t in ipairs(things) do
                -- a hit when the segment passes within 12 units of the thing
                local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
                local l2 = dx * dx + dy * dy + dz * dz
                local u = math.Clamp(((t.x - a.x) * dx + (t.y - a.y) * dy + (t.z - a.z) * dz) / l2, 0, 1)
                local px, py, pz = a.x + u * dx - t.x, a.y + u * dy - t.y, a.z + u * dz - t.z
                if px * px + py * py + pz * pz < 144 then return { ent = t } end
            end
        end,
        usable = function(t) if t.usable == false then return nil end return t.parent or t, "impulse" end,
        around = function()
            local out = {}
            for _, t in ipairs(things) do out[#out + 1] = { ent = t, point = { x = t.x, y = t.y, z = t.z } } end
            return out
        end,
        visible = function(o, p, t) return not (blocked and blocked[t]) end,
    }
end
local o = { x = 0, y = 0, z = 20 }
local r1 = I.FindUseTarget(o, 1, 0, 96, env_with({ door }))
local r2 = I.FindUseTarget(o, 1, 0, 96, env_with({ button }))
local r3 = I.FindUseTarget(o, 1, 0, 96, env_with({ behind }))
local side_btn = { name = "side", x = 30, y = 40, z = 20 }
local r4 = I.FindUseTarget(o, 1, 0, 96, env_with({ side_btn }))
local r5 = I.FindUseTarget(o, 1, 0, 96, env_with({ side_btn }, { [side_btn] = true }))
local part = { name = "handle", x = 60, y = 0, z = 20, parent = door }
local r6 = I.FindUseTarget(o, 1, 0, 96, env_with({ part }))
check(r1 == door and r2 == button and r3 == nil and r4 == side_btn and r5 == nil and r6 == door,
    "the interact key's search: a door straight ahead; a button at a player's eye height above a short character (the "
    .. "tilted looks); nothing behind; one off to the side found around; not through a wall; a part uses its parent")
check(I.HoldableInFront(Vector(0, 0, 0), 1, 0, Vector(40, 0, 10), 10) and not I.HoldableInFront(Vector(0, 0, 0), 1, 0,
    Vector(-40, 0, 10), 10) and not I.HoldableInFront(Vector(0, 0, 0), 1, 0, Vector(100, 0, 10), 10) and
    not I.HoldableInFront(Vector(0, 0, 0), 1, 0, Vector(40, 0, 120), 10),
    "a liftable prop is in front within the game's grab reach (not behind, not far, not high above)")

-- 3. a client frame: the world as host objects ---------------------------------------------------------------------------------
local zombie = new_ent(10, "npc_zombie", Vector(200, 0, 0), { npc = true })
local citizen = new_ent(11, "npc_citizen", Vector(300, 50, 0), { npc = true })
local jeep = new_ent(12, "prop_vehicle_jeep", Vector(-300, 0, 0), { vehicle = true, mins = Vector(-60, -100, 0),
                                                                  maxs = Vector(60, 100, 70), movetype = MOVETYPE_VPHYSICS })
local crate = new_ent(13, "prop_physics", Vector(100, 100, 0), { mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 32),
                                                                movetype = MOVETYPE_VPHYSICS })
crate.phys = phys_object(10)
crate.nw2.gsa1_hold = true
local barrel = new_ent(14, "prop_physics", Vector(0, 300, 0), { movetype = MOVETYPE_VPHYSICS, health = 30 })
barrel.phys = phys_object(80)
barrel.nw2.gsa1_hp = 30
local balloon = new_ent(15, "gmod_balloon", Vector(0, -200, 100), { mins = Vector(-12, -12, -12), maxs = Vector(12, 12, 12) })
local plain = new_ent(16, "prop_physics", Vector(50, -50, 0), { movetype = MOVETYPE_VPHYSICS })
plain.phys = phys_object(20)
found = { zombie, citizen, jeep, crate, barrel, balloon, plain, ply }
GSA1.LoadModule()
local C = { id = 1, kind = 0, drawPos = Vector(0, 0, 0), state = { yaw = 0, vx = 0, vy = 0, step = 0 },
            info = { center = 20 }, ent = { removed = false } }
GSA1.Char = C
ply.nw2.gsa1_char, ply.GSA1Kind = true, 0         -- the server's character flag (sv_gsa1.lua sets it)
I.Think()
local kinds = {}
for idx, ob in pairs(MOD.objects) do kinds[idx] = ob.kind end
check(kinds[10] == K.ENEMY and kinds[11] == nil and kinds[12] == K.TARGET and kinds[13] == K.HOLDABLE and
    kinds[14] == K.TARGET and kinds[15] == K.BALLOON and kinds[16] == nil and kinds[1] == nil and
    n_of("SetCharOption") == 2 and n_of("ObjConfig") == 1,
    "a frame with a character: the zombie, the jeep, the liftable crate, the barrel with health and the balloon are "
    .. "registered (the friendly citizen, a plain prop and the player are not); the character's options set (can die, "
    .. "rings) and the window")
local adds = n_of("ObjAdd")
M.T = M.T + 0.2
I.Think()
check(n_of("ObjAdd") == adds and n_of("ObjMove") >= 5, "the next look around sends no unchanged object again; the "
    .. "objects are moved every game pair (%d moves)", n_of("ObjMove"))
M.convars.gsa1_vehicle_target:SetString("0")
M.convars.gsa1_vehicle_attack:SetString("0")
M.T = M.T + 0.2
I.Think()
check(MOD.objects[12] == nil and n_of("ObjRemove") >= 1, "vehicles switched off on the page: the jeep is removed")
M.convars.gsa1_vehicle_target:SetString("2")
M.convars.gsa1_vehicle_attack:SetString("1")

-- hits: the hostile zombie's go to the server, the server damages it
local function ev(t) MOD.events[#MOD.events + 1] = t end
ev({ character = 1, type = K.EVENT_HIT, ent = 10, attack = 1, level = 1, damage = 1, x = 200, y = 0, z = 36, dx = 1, dy = 0,
     dz = 0, speed = 400, flags = 1, step = 10, reason = 0, target = 0 })
zombie.damage = {}
M.T = M.T + 0.2
I.Think()
local dmg = zombie.damage[1]
check(count_c(NET.HIT) == 1 and dmg and dmg.Damage == 50 and dmg.Attacker == ply and dmg.DamageType == 128,
    "a HIT on the zombie (SPIN): sent to the server, which damages it by the jump's 50 (DMG_CLUB) with the player as the "
    .. "attacker (%s)", dmg and tostring(dmg.Damage) or "no damage")
SCV.gsa1_sv_dmg_scale.v = "2"
M.T = M.T + 0.2
ev({ character = 1, type = K.EVENT_HIT, ent = 10, attack = 7, level = 3, damage = 3, x = 200, y = 0, z = 36, dx = 1, dy = 0,
     dz = 0, speed = 0, flags = 0, step = 20, reason = 0, target = 0 })
I.Think()
check(zombie.damage[2] and zombie.damage[2].Damage == 180, "Knuckles' punch with the scale at 2: 180 (90 x 2)")
SCV.gsa1_sv_dmg_scale.v = "1"
-- too far, a vetoing hook, and the rate
zombie.pos = Vector(2000, 0, 0)
M.T = M.T + 0.2
ev({ character = 1, type = K.EVENT_HIT, ent = 10, attack = 1, level = 1, damage = 1, x = 200, y = 0, z = 36, dx = 1, dy = 0,
     dz = 0, speed = 0, flags = 0, step = 30, reason = 0, target = 0 })
I.Think()
zombie.pos = Vector(200, 0, 0)
SH.GSA1CanDamage = { test = function() return false end }
M.T = M.T + 0.2
ev({ character = 1, type = K.EVENT_HIT, ent = 10, attack = 1, level = 1, damage = 1, x = 200, y = 0, z = 36, dx = 1, dy = 0,
     dz = 0, speed = 0, flags = 0, step = 40, reason = 0, target = 0 })
I.Think()
SH.GSA1CanDamage = nil
check(#zombie.damage == 2, "no damage when the target is out of the attack's reach, or the GSA1CanDamage hook says no")
-- a balloon pops (any attack); the citizen (friendly, attack off) is never sent
M.T = M.T + 0.2
ev({ character = 1, type = K.EVENT_HIT, ent = 15, attack = 3, level = 1, damage = 1, x = 0, y = -200, z = 100, dx = 0,
     dy = -1, dz = 0, speed = 300, flags = K.HITF_LAUNCHED, step = 50, reason = 0, target = 0 })
balloon.damage = {}
local sent_before = count_c(NET.HIT)
I.Think()
check(#balloon.damage == 1 and balloon.damage[1].Damage == 1 and count_c(NET.HIT) == sent_before + 1,
    "a homing attack on a balloon: the server pops it (1 damage through its own OnTakeDamage)")
-- two targets in one frame (a spin dash through a group): both hits go out and both are damaged (0.9.0 verifier: the
-- second was dropped by a client-wide timer and the server's per-player limit)
M.T = M.T + 0.2
ev({ character = 1, type = K.EVENT_HIT, ent = 10, attack = 1, level = 1, damage = 1, x = 200, y = 0, z = 36, dx = 1, dy = 0,
     dz = 0, speed = 400, flags = 0, step = 52, reason = 0, target = 0 })
ev({ character = 1, type = K.EVENT_HIT, ent = 15, attack = 1, level = 1, damage = 1, x = 0, y = -200, z = 100, dx = 0,
     dy = -1, dz = 0, speed = 400, flags = 0, step = 52, reason = 0, target = 0 })
zombie.damage, balloon.damage = {}, {}
local sent_two = count_c(NET.HIT)
I.Think()
check(count_c(NET.HIT) == sent_two + 2 and #zombie.damage == 1 and #balloon.damage == 1,
    "two targets hit in the same frame: both hits are sent (%d) and both targets take damage (%d, %d)",
    count_c(NET.HIT) - sent_two, #zombie.damage, #balloon.damage)

-- holding: lifted, drawn at the hands, the pose to the server, thrown
ev({ character = 1, type = K.EVENT_LIFTED, ent = 13, attack = 0, level = 0, damage = 0, x = 0, y = 0, z = 0, dx = 0, dy = 0,
     dz = 0, speed = 0, flags = 0, step = 60, reason = 0, target = 0 })
MOD.st.held_object, MOD.st.held = 1013, 13
M.T = M.T + 0.2
I.Think()
check(I.held and I.held.idx == 13 and crate.GSA1NoCollide == true and crate.GSA1HeldBy == ply and crate.phys.motion == false
    and crate.group == COLLISION_GROUP_DEBRIS and crate.nw2.gsa1_holder == ply,
    "LIFTED: the server takes the crate (frozen, debris, the holder networked); the client keeps it out of the character's "
    .. "collision")
MOD.held = { ent = 13, x = 30, y = 0, z = 40, yaw = 90 }
I.DrawHeld()
check(crate.renderOrigin and math.abs(crate.renderOrigin.z - 24) < 1e-6 and crate.pos.z == 24 and
    math.abs(crate:GetAngles().y - 90) < 1e-6,
    "while carried: drawn at the hands at once (render origin z %.1f: the centre 40 minus half its height), the server "
    .. "places it there for the others", crate.renderOrigin and crate.renderOrigin.z or -1)
-- 0.9.3a (the carried-object jitter, sadc docs/research/super_general_design.md 6.7 / D13): with the drawn steps the prop is
-- interpolated drawn_prev -> drawn with the body's alpha (the last pair's two steps, position_prev -> position, are not
-- used any more), and its yaw along the shortest arc
do
local ref_origin = Vector(crate.renderOrigin)
C.alpha, C.interp = 0.5, true
MOD.held = { ent = 13, x = 300, y = 300, z = 300, px = -300, py = -300, pz = -300, yaw = 0, dx = 40, dy = 0, dz = 40,
             dpx = 20, dpy = 0, dpz = 40, dyaw = 100, dpyaw = 80 }
I.DrawHeld()
local drawn_origin = Vector(crate.renderOrigin)
local drawn_used = I.heldDrawn
MOD.held = { ent = 13, x = 30, y = 0, z = 40, yaw = 90, dx = 30, dy = 0, dz = 40, dpx = 30, dpy = 0, dpz = 40, dyaw = -170,
             dpyaw = 170 }
I.DrawHeld()
local arc_yaw = crate.renderAngles and crate.renderAngles.y or -1
C.alpha, C.interp = nil, nil
check(drawn_used and math.abs(drawn_origin.x - ref_origin.x) < 1e-6 and math.abs(drawn_origin.y - ref_origin.y) < 1e-6 and
    math.abs(drawn_origin.z - ref_origin.z) < 1e-6 and math.abs(math.NormalizeAngle(arc_yaw - 180)) < 1e-6,
    "the drawn steps: at alpha 0.5 between drawn_prev (20, yaw 80) and drawn (40, yaw 100) the prop is where the 0.9.3 "
    .. "values put it at (30, yaw 90), the last pair's own steps ignored; yaw 170 -> -170 passes 180 (%.1f), not 0", arc_yaw)
MOD.held = { ent = 13, x = 30, y = 0, z = 40, yaw = 90 }
I.DrawHeld()
end
ev({ character = 1, type = K.EVENT_RELEASED, ent = 13, attack = 0, level = 0, damage = 0, x = 40, y = 0, z = 40, dx = 1,
     dy = 0, dz = 0.37, speed = 517, flags = 0, step = 70, reason = K.RELEASE_THROW, target = 0 })
MOD.st.held_object, MOD.st.held = 0, 0
MOD.held = nil
M.T = M.T + 0.2
I.Think()
check(I.held == nil and crate.GSA1HeldBy == nil and crate.phys.motion == true and math.abs(crate.phys.vel.x - 517) < 1e-3
    and crate.renderOrigin == nil and type(crate.GSA1NoCollide) == "number" and crate.physAttacker == ply,
    "RELEASED (a throw): the server lets it fly at the game's speed (%.0f HU/s), credited to the player; the client draws "
    .. "it where it is again", crate.phys.vel.x)
-- a lift the server refuses (too heavy): the client drops it again
crate.phys.mass = 100
ev({ character = 1, type = K.EVENT_LIFTED, ent = 13, attack = 0, level = 0, damage = 0, x = 0, y = 0, z = 0, dx = 0, dy = 0,
     dz = 0, speed = 0, flags = 0, step = 80, reason = 0, target = 0 })
local rel_before = n_of("ObjRelease")
M.T = M.T + 0.2
I.Think()
check(n_of("ObjRelease") == rel_before + 1 and crate.GSA1HeldBy == nil and count_s(NET.HOLD_DENY) == 1,
    "a lift the server refuses (heavier than gsa1_sv_hold_mass): the character drops it again (ObjRelease)")
crate.phys.mass = 10

-- 4. pushes ---------------------------------------------------------------------------------------------------------------------
MOD.contacts = { { ent = 16, steps = 2, side = 2, landing = 0, head = 0, riding = 0, wall = 0, first = 1, type = K.CONTACT_SIDE,
                   nx = -1, ny = 0, nz = 0, px = 50, py = -50, pz = 20, vx = 473, vy = 0, vz = 0, vin = 473, vout = 0,
                   depth = 0.5 } }
M.T = M.T + 0.2
I.Think()
local imp = plain.phys.impulses[1]
check(imp and math.abs(imp.imp.x - 20 * I.PushDeltaV(473, 0, 60, 20, 1)) < 1e-3 and imp.imp.y == 0 and imp.imp.z == 0,
    "Sonic runs into a 20 kg prop: the server pushes it away from him by mass (impulse %.0f kg HU/s along +x)",
    imp and imp.imp.x or 0)
MOD.contacts = { { ent = 16, steps = 2, side = 0, landing = 2, head = 0, riding = 2, wall = 0, first = 0,
                   type = K.CONTACT_LANDING, nx = 0, ny = 0, nz = 1, px = 50, py = -50, pz = 32, vx = 0, vy = 0, vz = -5,
                   vin = 0, vout = 0, depth = 0.1 } }
M.T = M.T + 0.2
local pushes = count_c(NET.PUSH)
I.Think()
check(count_c(NET.PUSH) == pushes and #plain.phys.impulses == 1, "standing on it: no push")
plain.phys.motion = false
MOD.contacts = { { ent = 16, steps = 2, side = 2, landing = 0, head = 0, riding = 0, wall = 1, first = 0, type = K.CONTACT_SIDE,
                   nx = -1, ny = 0, nz = 0, px = 50, py = -50, pz = 20, vx = 40, vy = 0, vz = 0, vin = 40, vout = 0,
                   depth = 0.5 } }
M.T = M.T + 0.2
I.Think()
check(#plain.phys.impulses == 1, "a frozen prop is not pushed")
plain.phys.motion = true
-- a ball stopped short of the prop: the impact
C.state = { yaw = 0, vx = 2400, vy = 0, step = 100 }
MOD.st.ball = true
M.T = M.T + 0.2
I.Think()
C.state = { yaw = 0, vx = 10, vy = 0, step = 102 }
local util_hull = util.TraceHull
util.TraceHull = function(t)
    return { Hit = true, Entity = plain, HitPos = Vector(t.start.x + 37, t.start.y, t.start.z), HitNormal = Vector(-1, 0, 0) }
end
M.T = M.T + 0.2
I.Think()
util.TraceHull = util_hull
MOD.st.ball = false
local imp2 = plain.phys.impulses[2]
check(imp2 and imp2.imp.x > 2 * 20 * I.PushDeltaV(473, 0, 60, 20, 1),
    "a spin dash stopped short of it by the game (2400 -> 10 HU/s, no contact): an impact, rolling: pushed harder than "
    .. "the run (%.0f)", imp2 and imp2.imp.x or 0)

-- 5. the interact key -------------------------------------------------------------------------------------------------------------
crate.pos = Vector(40, 0, 0)
C.state = { yaw = 0, vx = 0, vy = 0, step = 110 }
keys[KEY_E] = true
M.T = M.T + 0.2
local uses = count_c(NET.USE)
I.Think()
local b1 = GSA1.ExtraButtons(C)
M.T = M.T + 0.2
local b2 = GSA1.ExtraButtons(C)
keys[KEY_E] = false
I.Think()
M.convars.gsa1_lift_key:SetString("70")
keys[70] = true
M.T = M.T + 0.2
I.Think()
local b3 = GSA1.ExtraButtons(C)
keys[70] = false
M.T = M.T + 0.2
I.Think()
M.convars.gsa1_lift_key:SetString("0")
check(b1 == 2 and b2 == 0 and b3 == 2 and count_c(NET.USE) == uses,
    "E with the liftable crate in front: the game's action button for a moment (lifts it, as the game does), no use "
    .. "request; the optional lift key (gsa1_lift_key) presses it too")
crate.pos = Vector(100, 100, 0)
local btn = new_ent(20, "func_button", Vector(60, 0, 40), { mins = Vector(-4, -8, -8), maxs = Vector(4, 8, 8) })
S.trace_result = function(t)
    if t.endpos.x > 50 and math.abs(t.endpos.z - t.start.z) < 30 then return { Hit = true, Entity = btn, HitPos = Vector(60, 0, 40) } end
    return { Hit = false, HitPos = Vector(t.endpos) }
end
ply.nw2.gsa1_char = true
keys[KEY_E] = true
M.T = M.T + 0.2
I.Think()
check(#btn.used == 1 and btn.used[1].a == ply and btn.used[1].t == USE_ON and ply.GSA1UseHeld == true and
    S.PLAYER_META.KeyDown(ply, IN_USE) == true,
    "E with a func_button in front: the server uses it as a player's E (activator the player, USE_ON); while E is held "
    .. "Player:KeyDown(IN_USE) is true for the character's player (gmod_button holds)")
keys[KEY_E] = false
M.T = M.T + 0.2
I.Think()
check(ply.GSA1UseHeld == nil and S.PLAYER_META.KeyDown(ply, IN_USE) == false, "E released: KeyDown(IN_USE) false again")
SH.PlayerUse = { test = function() return false end }
keys[KEY_E] = true
M.T = M.T + 0.2
I.Think()
keys[KEY_E] = false
M.T = M.T + 0.2
I.Think()
SH.PlayerUse = nil
check(#btn.used == 1 and I.lastUse and I.lastUse.result == I.USE_DENIED,
    "the PlayerUse hook says no (prop protection): not used, the client hears \"not allowed\"")
-- "Interaction with the world" off: E is the engine's own +use again, so the character must not use the button as well
-- (0.9.0 verifier: it sent two uses)
M.convars.gsa1_interact:SetString("0")
local uses_off = count_c(NET.USE)
keys[KEY_E] = true
M.T = M.T + 0.2
I.Think()
keys[KEY_E] = false
M.T = M.T + 0.2
I.Think()
M.convars.gsa1_interact:SetString("1")
check(count_c(NET.USE) == uses_off and #btn.used == 1,
    "interaction off: E sends no use of the character's own (the engine's +use is the only one)")
local mom = new_ent(21, "momentary_rot_button", Vector(60, 0, 40))
S.trace_result = function(t)
    if t.endpos.x > 50 then return { Hit = true, Entity = mom, HitPos = Vector(60, 0, 40) } end
    return { Hit = false, HitPos = Vector(t.endpos) }
end
keys[KEY_E] = true
M.T = M.T + 0.2
I.Think()
for _ = 1, 3 do S_call("Think") end
local turns = #mom.used
keys[KEY_E] = false
M.T = M.T + 0.2
I.Think()
S_call("Think")
check(turns == 4 and #mom.used == 4 and mom.used[2].t == USE_TOGGLE,
    "a momentary button turns every server tick while E is held (%d uses), and stops when E is released", turns)
-- a vehicle: the character steps out (GSA1.Remove), the player enters, and comes back as the character on leaving
S.trace_result = function(t)
    if t.endpos.x > 50 then return { Hit = true, Entity = jeep, HitPos = Vector(60, 0, 40) } end
    return { Hit = false, HitPos = Vector(t.endpos) }
end
jeep.pos = Vector(120, 0, 0)
local removed, spawned
GSA1.Remove = function() removed = true GSA1.Char = nil ply.nw2.gsa1_char = false end
GSA1.Spawn = function(name) spawned = name end
keys[KEY_E] = true
M.T = M.T + 0.2
I.Think()
keys[KEY_E] = false
check(removed and ply.vehicle_in == jeep, "E at a jeep: the character steps out and the player is in the jeep")
S_call("PlayerLeaveVehicle", ply, jeep)
check(spawned == "sonic", "leaving the jeep makes the player Sonic again (gsa1_vehicle_return)")
-- 0.9.3a (RC4): the list entry comes back - Super Sonic (General Gameplay) is kind 0 too
GSA1.Char = C
C.name = "supersonic_general"
ply.nw2.gsa1_char = true
ply.vehicle_in = nil
removed, spawned = nil, nil
M.T = M.T + 0.5
I.Think()
keys[KEY_E] = true
M.T = M.T + 0.2
I.Think()
keys[KEY_E] = false
S_call("PlayerLeaveVehicle", ply, jeep)
check(removed and spawned == "supersonic_general", "Super Sonic (General Gameplay) leaves the jeep as himself (%s), not as "
    .. "plain Sonic", tostring(spawned))
C.name = nil
GSA1.Char = C
ply.nw2.gsa1_char = true
ply.vehicle_in = nil

-- 6. damage the character's player takes -------------------------------------------------------------------------------------------
local dmginfo = S.DamageInfo()
dmginfo:SetDamage(12)
dmginfo:SetDamageType(DMG_BULLET)
dmginfo:SetDamagePosition(Vector(300, 0, 50))
dmginfo:SetAttacker(zombie)
local damages = n_of("Damage")
M.T = M.T + 1
local blocked = S_call("EntityTakeDamage", ply, dmginfo)
local dcall = MOD.calls[#MOD.calls]
check(blocked == true and n_of("Damage") == damages + 1 and dcall[1] == "Damage" and dcall[3] == 0 and dcall[4] == 300 and
    dcall[7] == 10,
    "a zombie's bullet hits the player: blocked (rings mode, decision 1) and sent to the character - gsa1.Damage from "
    .. "(300 0 50), credited to the zombie's object, knocked back the game's way")
local drown = S.DamageInfo()
drown:SetDamage(10)
drown:SetDamageType(DMG_DROWN)
M.T = M.T + 1
local b3 = S_call("EntityTakeDamage", ply, drown)
SCV.gsa1_sv_damage_mode.v = "1"
M.T = M.T + 1
local b4 = S_call("EntityTakeDamage", ply, dmginfo)
SCV.gsa1_sv_damage_mode.v = "0"
check(b3 == true and b4 == nil and n_of("Damage") == damages + 1,
    "drowning is the game's own (blocked, not sent); in health mode Garry's Mod applies the damage and the character "
    .. "is not hit")
-- PvP: another player who is a character is hit in its own game, in rings mode not in health
local other = setmetatable({ idx = 2, nw2 = { gsa1_char = true }, damage = {}, pos = Vector(150, 0, 0) }, { __index = ply })
E[2] = other
function other:EntIndex() return 2 end
function other:IsPlayer() return true end
other.TakeDamageInfo = function(self, d) self.damage[#self.damage + 1] = d end
other.NearestPoint = function(self, p) return Vector(self.pos) end
local hurts = count_s(NET.HURT)
M.T = M.T + 1
S.sread = reader({ 2, 3, 1, 1, Vector(150, 0, 30), Vector(1, 0, 0), 400, 0 })
recv_s[NET.HIT](0, ply)
check(count_s(NET.HURT) == hurts + 1 and #other.damage == 0,
    "PvP (decision 4): a homing attack on another character sends it a hit with knock-back (gsa1_hurt) and, in rings "
    .. "mode, no Garry's Mod damage")
-- an NPC killed by the character: removed as killed in its game
local rm = n_of("ObjRemove")
S_call("OnNPCKilled", zombie, ply)
check(n_of("ObjRemove") == rm + 1 and MOD.calls[#MOD.calls][3] == true,
    "the zombie dies from the character's hits: its object is removed KILLED (E-102's time bonus)")

-- 9. 0.9.2 (sadc docs/research/gsa1_090_player.md L1, L5, L7, L8, H1-H3 and G7 with its review) ------------------------------
-- L1: the characters' sizes, both realms (feat_interact_size_binding_test compares them with the disc)
-- (the released 0.9.1 files lack these: the checks below fail there instead of stopping the test)
local CS, SCS = GSA1.CHAR_SIZE, SG.CHAR_SIZE
local char_size = I.CharSize or function() return nil end
local outside = I.CylinderOutside or function() return -1 end
check(CS and SCS and CS[0].radius == 16 and CS[0].height == 40 and CS[0].eyes == 28 and CS[0].center == 21.6 and
    CS[2].height == 36 and CS[3].height == 45.6 and CS[5].radius == 14 and CS[6].height == 84 and CS[6].eyes == 80 and
    CS[7].radius == 38 and CS[7].height == 68 and SCS[6].height == 84 and char_size(8) == CS[0] and char_size(nil) == CS[0],
    "GSA1.CHAR_SIZE in both realms: Sonic r 16 h 40 eyes 28 centre 21.6, Tails h 36, Knuckles h 45.6, Amy r 14, E-102 h 84 "
    .. "eyes 80, Big r 38 h 68 (gsa1_090_player.md 1.3); a kind without a row has Sonic's")
check(outside(0, 0, 0, 16, 40, 0, 0, 60) == 20 and outside(0, 0, 0, 16, 40, 0, 0, 20) == 0 and
    outside(0, 0, 0, 16, 40, 30, 0, 20) == 14 and math.abs(outside(0, 0, 0, 16, 40, 19, 0, 44) - 5) < 1e-9,
    "the distance outside a character's cylinder: 20 units above Sonic's head, 0 inside, 14 beside him, a corner 5")
-- L5: bullets (trace attacks) count only where the character is; melee, blasts and the rest still hit
local BULLET, SLASH, BLAST = 2, 4, 64
local function take(typ, pos, amount)
    local d = S.DamageInfo()
    d:SetDamage(amount or 8)
    d:SetDamageType(typ)
    d:SetDamagePosition(pos)
    d:SetAttacker(citizen)
    M.T = M.T + 1
    ply.GSA1State = { x = 0, y = 0, z = 0, time = M.T }
    local before = n_of("Damage")
    -- Garry's Mod: a trace attack on a player asks ScalePlayerDamage first (true = no damage), then EntityTakeDamage
    local refused = typ == BULLET and S_call("ScalePlayerDamage", ply, 1, d) == true
    if not refused then S_call("EntityTakeDamage", ply, d) end
    return n_of("Damage") - before, refused
end
ply.pos = Vector(0, 0, 0)
C.state = { yaw = 0, vx = 0, vy = 0, step = 200 }
local over, over_r = take(BULLET, Vector(0, 0, 60))
local body = take(BULLET, Vector(0, 0, 20))
local beside = take(BULLET, Vector(30, 0, 20))
local edge = take(BULLET, Vector(22, 0, 20))
local melee = take(SLASH, Vector(40, 0, 36), 25)              -- DrGBase's ENT:Attack: the position is the bot's own centre
local blast = take(BLAST, Vector(100, 0, 0), 110)              -- a blast's position is its centre
check(over == 0 and over_r and body == 1 and beside == 0 and edge == 1 and melee == 1 and blast == 1,
    "L5: a bullet at Sonic's feet + 60 misses (refused, no ring hit), at + 20 hits, 30 units beside him misses, 22 hits "
    .. "(within 8 of his 16-unit radius); a DrGBase-style melee (position the attacker's centre, 40 away) and a blast "
    .. "(centre 100 away) still hit (0.9.0: every one hit)")
if SCV.gsa1_sv_hit_shape then SCV.gsa1_sv_hit_shape.v = "0" end
local over_off = take(BULLET, Vector(0, 0, 60))
if SCV.gsa1_sv_hit_shape then SCV.gsa1_sv_hit_shape.v = "1" end
check(over_off == 1, "with \"Bullets hit a character only where its body is\" off the shot over his head hits again")
-- L7: the hurt line names the attacker's class
GSA1.LogFlush()
local lt = M.files["gsa1/log.txt"] or ""
check(string.find(lt, "the player took 8 damage (type 2) from npc_citizen: the character is hit", 1, true) ~= nil and
    string.find(lt, "the player took 110 damage (type 64) from npc_citizen", 1, true) ~= nil,
    "L7: the hurt lines name the attacker's class (\"... from npc_citizen\"), sent by the server with the hit")
-- G7: no hit on a dead character or on one before its first game pair (dropped and counted)
local dropped0 = I.stats.hurts_dropped or 0
C.state = { yaw = 0, vx = 0, vy = 0, step = 0 }
local h_new = take(SLASH, Vector(40, 0, 36), 25)
C.state = { yaw = 0, vx = 0, vy = 0, step = 2 }
MOD.st.dead = true
local h_dead = take(SLASH, Vector(40, 0, 36), 25)
MOD.st.dead = false
C.death = { cause = 1, step = 10, at = M.T }
local h_dead2 = take(SLASH, Vector(40, 0, 36), 25)
C.death = nil
local h_ok = take(SLASH, Vector(40, 0, 36), 25)
GSA1.LogFlush()
lt = M.files["gsa1/log.txt"] or ""
check(h_new == 0 and h_dead == 0 and h_dead2 == 0 and h_ok == 1 and (I.stats.hurts_dropped or 0) == dropped0 + 3 and
    string.find(lt, "dropped, the character has not started yet", 1, true) ~= nil and
    string.find(lt, "dropped, the character is dead", 1, true) ~= nil and
    string.find(table.concat(I.StatusLines(), " "), "3 dropped", 1, true) ~= nil,
    "G7: a hit during the character's first game pair (step 0) and on a dead character (the game's dead bit, or its death "
    .. "event) is dropped, counted (status: 3 dropped) and logged; after its first pair it hits again")

-- L8: the interact key never uses the player's own hands (gmod_hands, base_anim's empty Use) - 26 "used (gmod_hands)"
-- lines in the owner's logs
function EMT:GetOwner() return self.owner or NULL end
S.scripted_ents.Get = function(cls)
    -- Garry's Mod's Get copies the base's functions in: gmod_hands has base_anim's (empty) Use
    if cls == "gmod_button" or cls == "keypad" or cls == "gmod_hands" or cls == "sent_plain" then return { Use = function() end } end
end
local stored = {
    gmod_button = { t = { Use = function() end }, Base = "base_gmodentity" },
    gmod_hands = { t = { Type = "anim" }, Base = "base_anim" },
    sent_plain = { t = { Type = "anim" }, Base = "base_gmodentity" },
    base_gmodentity = { t = {}, Base = "base_anim" },
    base_anim = { t = { Use = function() end }, Base = "base_entity" },
    base_entity = { t = {} },
}
S.scripted_ents.GetStored = function(cls) return stored[cls] end
local hands = new_ent(30, "gmod_hands", Vector(0, 0, 64), { scripted = true, owner = ply, mins = Vector(-4, -4, -4),
                                                          maxs = Vector(4, 4, 4) })
function ply:GetHands() return hands end
local plain_sent = new_ent(32, "sent_plain", Vector(40, 0, 20), { scripted = true, mins = Vector(-4, -4, -4),
                                                                 maxs = Vector(4, 4, 4) })
S.trace_result = function(t) return { Hit = true, Entity = hands, HitPos = Vector(0, 0, 64) } end
found = { hands, ply }
local function press_e()
    keys[KEY_E] = false                         -- (the key up first: the jeep's press above ended without a frame)
    M.T = M.T + 0.2
    I.Think()
    I.lastUse = nil
    keys[KEY_E] = true
    M.T = M.T + 0.2
    I.Think()
    keys[KEY_E] = false
    M.T = M.T + 0.2
    I.Think()
    return I.lastUse
end
local u1 = press_e()
local own_kind = SI.UsableKind(hands, ply)
S.trace_result = nil
found = { plain_sent, ply }
local u2 = press_e()
check(u1 and u1.result == I.USE_NOTHING and own_kind == nil and #hands.used == 0 and u2 and u2.result == I.USE_NOTHING and
    #plain_sent.used == 0 and SI.UsableKind(btn, ply) ~= nil,
    "L8: E with the player's own gmod_hands straight above the character (traced and found around) -> \"nothing to use\" "
    .. "(0.9.0: \"used (gmod_hands)\"); a scripted entity whose only Use is base_anim's empty one is not usable either; a "
    .. "func_button still is")
local gb = new_ent(33, "gmod_button", Vector(50, 0, 30), { scripted = true, mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4) })
check(SI.UsableKind(gb, ply) == gb, "a gmod_button (its own Use) stays usable through the Base chain check")
found = {}

-- H1-H3: a carried oil drum stays above the ground (props_c17/oildrum001, 29 x 29 x 45.6, 30 kg: its centre at Sonic's
-- hands 13.0 above his feet put its bottom 9.8 units into the floor)
local drum = new_ent(31, "prop_physics", Vector(30, 0, 0), { mins = Vector(-14.5, -14.5, 0), maxs = Vector(14.5, 14.5, 45.6),
                                                            movetype = MOVETYPE_VPHYSICS, model = "models/props_c17/oildrum001.mdl" })
drum.phys = phys_object(30)
drum.nw2.gsa1_hold = true
found = { drum }
C.drawPos = Vector(0, 0, 0)
C.state = { yaw = 0, vx = 0, vy = 0, step = 300 }
M.T = M.T + 0.2
I.Think()
check(MOD.objects[31] and MOD.objects[31].kind == K.HOLDABLE, "the drum is a holdable object")
ev({ character = 1, type = K.EVENT_LIFTED, ent = 31, attack = 0, level = 0, damage = 0, x = 0, y = 0, z = 0, dx = 0, dy = 0,
     dz = 0, speed = 0, flags = 0, step = 310, reason = 0, target = 0 })
MOD.st.held_object, MOD.st.held = 1031, 31
M.T = M.T + 0.2
I.Think()
MOD.held = { ent = 31, x = 30, y = 0, z = 13.0, yaw = 0 }
I.DrawHeld()
local drawn_bottom = drum.renderOrigin and drum.renderOrigin.z or -99
local sent_bottom = drum.pos.z
check(I.held and I.held.idx == 31 and drawn_bottom >= 0.999 and sent_bottom >= 0.999 and drawn_bottom < 1.5,
    "H1: Sonic holding the drum at the measured hold point (centre 13.0 above his feet): drawn with its bottom at %.1f and "
    .. "sent to the server at %.1f, above the floor (0.9.0: -9.8)", drawn_bottom, sent_bottom)
local cl_hull = util.TraceHull
util.TraceHull = function(t)
    local out = t.output or {}
    out.Hit, out.StartSolid, out.HitPos = true, false, Vector(t.endpos.x, t.endpos.y, 8)
    return out
end
I.DrawHeld()
local step_bottom = drum.renderOrigin.z
util.TraceHull = cl_hull
if M.convars.gsa1_hold_overhead then M.convars.gsa1_hold_overhead:SetString("1") end
I.DrawHeld()
local head_bottom, head_x = drum.renderOrigin.z, drum.renderOrigin.x
if M.convars.gsa1_hold_overhead then M.convars.gsa1_hold_overhead:SetString("0") end
if M.convars.gsa1_hold_clear then M.convars.gsa1_hold_clear:SetString("0") end
I.DrawHeld()
local game_bottom = drum.renderOrigin.z
if M.convars.gsa1_hold_clear then M.convars.gsa1_hold_clear:SetString("1") end
check(step_bottom >= 8.999 and head_bottom >= 40.999 and math.abs(head_x) < 1e-6 and math.abs(game_bottom + 9.8) < 1e-6,
    "H1 / H3: over a step 8 units up (the trace of its footprint) the bottom stays above it (%.1f); \"over the head\": "
    .. "above Sonic's 40-unit head (%.1f), over him; \"Keep carried props above the ground\" off: the game's -9.8",
    step_bottom, head_bottom)
-- H2: put down at the game's release point (centre 10.5): raised by the client, so the server's prop is on the floor
ev({ character = 1, type = K.EVENT_RELEASED, ent = 31, attack = 0, level = 0, damage = 0, x = 40, y = 0, z = 10.5, dx = 1,
     dy = 0, dz = 0, speed = 0, flags = 0, step = 330, reason = K.RELEASE_PUT_DOWN, target = 0 })
MOD.st.held_object, MOD.st.held = 0, 0
MOD.held = nil
M.T = M.T + 0.2
I.Think()
local put_bottom = drum.pos.z
check(I.held == nil and drum.GSA1HeldBy == nil and drum.phys.motion == true and put_bottom >= -1e-6,
    "H2: put down at the game's centre 10.5: the server places its bottom at %.1f, on the floor (0.9.0: -12.3)", put_bottom)
-- H2, the server's own guard: a release the client did not raise (an older client, the option off) is lifted in steps
-- until the prop's box is free of the floor
if M.convars.gsa1_hold_clear then M.convars.gsa1_hold_clear:SetString("0") end
ev({ character = 1, type = K.EVENT_LIFTED, ent = 31, attack = 0, level = 0, damage = 0, x = 0, y = 0, z = 0, dx = 0, dy = 0,
     dz = 0, speed = 0, flags = 0, step = 340, reason = 0, target = 0 })
MOD.st.held_object, MOD.st.held = 1031, 31
M.T = M.T + 0.2
I.Think()
local tried = {}
S.trace_result = function(t)
    tried[#tried + 1] = t.start.z
    return { Hit = false, StartSolid = t.start.z + t.mins.z < -1e-6, HitPos = Vector(t.endpos) }
end
ev({ character = 1, type = K.EVENT_RELEASED, ent = 31, attack = 0, level = 0, damage = 0, x = 40, y = 0, z = 10.5, dx = 1,
     dy = 0, dz = 0, speed = 0, flags = 0, step = 350, reason = K.RELEASE_PUT_DOWN, target = 0 })
MOD.st.held_object, MOD.st.held = 0, 0
M.T = M.T + 0.2
I.Think()
S.trace_result = nil
if M.convars.gsa1_hold_clear then M.convars.gsa1_hold_clear:SetString("1") end
local guard_bottom = drum.pos.z
check(guard_bottom >= -1e-6 and #tried == 4 and math.abs(guard_bottom - (10.5 - 22.8 + 16)) < 1e-6,
    "H2, the server's guard: released 12.3 units into the floor, its box is tried 0, 2, 8 and 16 units up and set at the "
    .. "first free spot (bottom %.1f, %d tries)", guard_bottom, #tried)
found = {}

-- the session log (Claude reads it after the owner's test)
if GSA1.LogFlush then GSA1.LogFlush() end
local logtext = M.files["gsa1/log.txt"] or ""
check(string.find(logtext, "hostile npc_zombie (10) by Spin", 1, true) ~= nil and
    string.find(logtext, "lifted models/props_junk/wood_crate001a.mdl (13)", 1, true) ~= nil and
    string.find(logtext, "released 13: thrown at 517 units/s", 1, true) ~= nil and
    string.find(logtext, "the interact key: used (func_button)", 1, true) ~= nil and
    string.find(logtext, "the interact key: not allowed (func_button)", 1, true) ~= nil and
    string.find(logtext, "the player took 12 damage", 1, true) ~= nil,
    "the session log has the hits, the lifts and throws, the interact key's results and the hits taken")

-- 7. the HUD (0.9.1: the game's own HUD replaced round 5's ring counter: feat/cl_hud.lua, tests/feat_hud_test.lua) --------------
drawn = {}
M.run_hook("HUDPaint")
local hud_entry = nil
for _, e in ipairs(M.menu) do if e.class == "gsa1_feat_hud" then hud_entry = e end end
check(#drawn == 0 and M.run_hook("HUDShouldDraw", "CHudHealth") == nil and M.run_hook("HUDShouldDraw", "CHudChat") == nil
    and GSA1.Hud.MenuControls ~= nil and hud_entry ~= nil, "the HUD is the hud feature's (its own page; this module "
    .. "has no hud part): no Garry's Mod text counter, Garry's Mod's health stays; the Interaction page keeps the HUD "
    .. "switch")

-- 8. without the module's part ------------------------------------------------------------------------------------------------------
G.FEATURES = {}
M.menu = {}
M.run_hook("PopulateToolMenu")
for _, e in ipairs(M.menu) do if e.class == "gsa1_feat_interact" then entry = e end end
local panel2 = standin("DForm")
entry.cpanel(panel2)
local t2 = {}
for _, c in ipairs(panel2.calls) do t2[#t2 + 1] = c[1] .. "(" .. tostring(c[2]) .. ")" end
check(string.find(table.concat(t2, " "), "0.9.0", 1, true) ~= nil, "a module without the interaction: the page says it "
    .. "needs G-SA1 module 0.9.0")
check(#M.reported == 0, "no Lua error%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
info("module calls: ObjAdd %d, ObjMove %d, ObjRemove %d, Damage %d; client messages %d, server messages %d",
    n_of("ObjAdd"), n_of("ObjMove"), n_of("ObjRemove"), n_of("Damage"), #sent_c, #sent_s)
return done()
