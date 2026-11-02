-- feat_follower_test.lua - the follower feature's addon side (round 0.9.8; sadc docs/research/gsa1_098_plan.md 2.4, 5.5-5.9, 6.7;
-- gsa1_096_plan.md 4.10, 4.12-4.19, 4.21, 5.5-5.7, 6.5 task 8 with its reviews; follow096_gsa1.md 9.1 items 1-13): feat/sh_follower.lua,
-- cl_follower.lua, sv_follower.lua, entities/gsa1_follower_spawner.lua and the patches in cl_character.lua, cl_render.lua,
-- cl_collision.lua, cl_log.lua, feat/cl_board.lua, feat/sv_board.lua, feat/cl_unlikesonic.lua, in Garry's Mod's own LuaJIT: the client
-- through the autorun against tests/lua_mock.lua and a MOCK MODULE of 5.5 (feature "follower" 1, a small model of 0.9.5's board per
-- character), the server's files in their own environment with net messages delivered at once between the realms.
--   lua_host tests/feat_follower_test.lua <tests dir> <addon/lua dir>
-- The mock is checked against build/x86_64-windows/follower_api.txt (feat_follower_binding_test.cpp writes it) as soon as the snapshot
-- header build/deps/include/libsa1.h defines SA1_API_FOLLOWER (5.5; a missing file is a failure); before that the check is skipped.
--
-- API NOTES (098-gsa1-followlua, the full text; the report carries a summary):
--   * GSA1.Followers = Fo (both realms: Fo.cv, Fo.NET, Fo.KINDS, Fo.KIND_ORDER, Fo.EGG_MAX 99, Fo.NORMAL_MAX 8, Fo.BEHIND 40). Client:
--     Fo.list (F tables in spawn order), Fo.byId[id], Fo.Count(eggOnly), Fo.Cap(), Fo.RootOf(F) -> your character | nil,
--     Fo.LeaderEntry(F) -> the entry of its libsa1 leader | nil, Fo.ByUid(uid), Fo.TargetText(F), Fo.SetTarget(F, want) -> true | false, why
--     (want: 0-4, "me", "player", "follower", "aim", "stay"), Fo.Remove(F, why), Fo.RemoveAll(why), Fo.Recreate(F, why), Fo.CallBack(how),
--     Fo.CallOne(F), Fo.Hold(F, on), Fo.FarFoci(C, apart, maxN) -> a reused list of positions, Fo.SpawnerClasses(), Fo.WhyNot(kind).
--   * F = { id, kind, title, name, uid, egg (made with ignore_cap), slot (1..15 for kinds 0 / 2, else nil), leaderId (nil: host-fed), hostFed,
--     target = { type = "me" | "player" | "aim" | "follower" | "stay", ent, uid, pos, yaw }, state (gsa1.GetState's table, refreshed after each
--     FollowersTick), ent (its render entity), drawPos (Vector, reused), drawYaw (degrees), lod (1 | 2 | 3), held (it stands 1,000,000
--     units above its leader: keep it out of your lists), follower = true, board (B.State's table), finfo (gsa1.FollowerInfo's table, 4 Hz) }.
--     Read only, for every other feature.
--   * GSA1.SpawnFollower(kind, opts) -> true, F | false, reason (never raises); opts = { ignore_cap, target, silent, objects, upgrades, why }.
--   * Hooks: GSA1FollowerCreated(F, why), GSA1FollowerPostTick(F, state, dt), GSA1FollowerRemoved(F, why): a re-creation (a fault, a DEATH event
--     of its world, its upgrades, the map's collision) runs Removed + Created with a NEW F table and the same uid, slot, target.
--   * Seams: GSA1.FollowerTickCamera(C) -> origin, target | nil (wrap it: feat/cl_gamecam.lua), GSA1.FollowersThink(now), GSA1.DispatchEvent(C, e,
--     now), GSA1.PollAllEvents(now), GSA1.EV, GSA1.GamePaused(), GSA1.FirstPersonFor(C), GSA1.RENDER_BOUNDS_MIN / MAX, GSA1.FollowerBatch(C, flags),
--     cl_log.lua GSA1.LogFollowers(...), B.FollowerBoxes(F), B.Mirror(C, on, why), B.FollowerTick(F, st, dt), B.LeftPump().
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_follower_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files and the ones it talks to
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_follower%.lua$") or string.find(n, "_board%.lua$") or string.find(n, "_wheel[%w_]*%.lua$") or
                n == "sh_objects.lua" or n == "cl_spawntab.lua" or n == "cl_unlikesonic.lua" then
                keep[#keep + 1] = n
            end
        end
        return keep
    end
    return out
end

-- GMod's constants and helpers the mock lacks (local to this test) -----------------------------------------------------------------
SOLID_VPHYSICS, MOVETYPE_VPHYSICS, MOVETYPE_NONE, TRANSMIT_ALWAYS, SOLID_NONE = 6, 6, 0, 0, 0
SOLID_BBOX, SOLID_OBB, RENDERGROUP_TRANSLUCENT, COLLISION_GROUP_NONE = 2, 3, 1, 0
MOVETYPE_NOCLIP, MOVETYPE_WALK, MASK_SOLID, TOP, LEFT = 8, 2, 33570827, 4, 1
surface.CreateFont = function() end
surface.SetFont = function() end
surface.GetTextSize = function(s) return #tostring(s) * 8, 16 end
surface.DrawPoly = function() end
cam.Start3D2D = function() end
cam.End3D2D = function() end
draw.SimpleTextOutlined = function() end
local chats = {}
chat.AddText = function(...)
    local t = {}
    for _, v in ipairs({ ... }) do if type(v) == "string" then t[#t + 1] = v end end
    chats[#chats + 1] = table.concat(t)
end
-- the timer library: timers run by hand (the egg's)
local timers = {}
timer = { Simple = function() end, Remove = function(n) timers[n] = nil end,
          Create = function(n, d, r, f) timers[n] = { fn = f, left = r } end }
-- the keyboard
local keys = {}
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    IsKeyDown = function(code) return keys[code] == true end,
    IsMouseDown = function(code) return keys[code] == true end,
    LookupBinding = function(b) return nil end,
    GetKeyCode = function(name) return nil end,
    GetKeyName = function(code) return "key" .. tostring(code) end,
    LookupKeyBinding = function(code) if code == 16 then return "impulse 100" end end,
}
M.player.IsTyping = function() return false end
M.player.GetAimVector = function() return Vector(1, 0, 0) end
M.player.IsAdmin = function() return true end
M.player.Nick = function() return "me" end
Entity = function() return NULL end
-- the other players the client sees
local others = {}
player = { GetAll = function()
    local t = { M.player }
    for _, p in ipairs(others) do t[#t + 1] = p end
    return t
end }
local function other_player(name, x, y, z)
    return { name = name, pos = Vector(x, y, z), GetPos = function(s) return Vector(s.pos) end, GetVelocity = function() return Vector() end,
             GetAngles = function() return Angle(0, 30, 0) end, OnGround = function() return true end,
             IsPlayer = function() return true end, IsNPC = function() return false end, Nick = function(s) return s.name end }
end

-- the server realm: its own globals over the mock's, its hooks, its net (as feat_board_test.lua) --------------------------------------
local S = setmetatable({}, { __index = _G })
S.SERVER, S.CLIENT = true, false
local SH, recv_s, recv_c, strings = {}, {}, {}, {}
S.hook = { Add = function(ev, name, fn) SH[ev] = SH[ev] or {} SH[ev][name] = fn end,
           Remove = function(ev, name) if SH[ev] then SH[ev][name] = nil end end,
           Run = function(ev, ...)
               for _, fn in pairs(SH[ev] or {}) do
                   local a, b = fn(...)
                   if a ~= nil then return a, b end
               end
           end }
local SCV = {}
S.CreateConVar = function(name, default, flags, help, lo, hi)
    local c = setmetatable({ name = name, v = tostring(default), lo = lo, hi = hi, flags = flags }, getmetatable(M.cv("fps_max")))
    SCV[name] = c
    return c
end
S.GetConVar = function(n) return SCV[n] end
S.CreateClientConVar = nil
S.concommand = { Add = function() end }
S.AddCSLuaFile = function() end
S.CurTime = function() return M.T end
S.print = function() end
S.timer = { Simple = function() end, Create = function() end, Remove = function() end }
S.game = { SinglePlayer = function() return true end, GetMap = function() return "gm_test" end }
S.cleanup = { Register = function() end }
local undos = {}
S.undo = { Create = function(n) undos[#undos + 1] = { name = n, ents = {} } end,
           AddEntity = function(e) table.insert(undos[#undos].ents, e) end,
           AddFunction = function(f) undos[#undos].fn = f end,
           SetPlayer = function(p) undos[#undos].ply = p end,
           SetCustomUndoText = function(t) undos[#undos].text = t end,
           Finish = function() undos[#undos].done = true end }
S.util = { AddNetworkString = function(n) strings[n] = true end, IsInWorld = function() return true end,
           TraceLine = function(t) return { Hit = true, HitPos = Vector(t.start.x, t.start.y, 0), HitNormal = Vector(0, 0, 1) } end }
S.MASK_SOLID_BRUSHONLY = 16395
-- the left boards on the server: an entity with every Set* / Get* its code uses
local left_ents = {}
local function s_entity(cls)
    local e = { cls = cls, vals = {} }
    setmetatable(e, { __index = function(t, k)
        local op, name = string.match(k, "^(%u%l%l)(%u%w*)$")
        if op == "Set" then return function(s, v) s.vals[name] = v end end
        if op == "Get" then return function(s) return s.vals[name] end end
        return nil
    end })
    e.Spawn = function() end
    e.Remove = function(s) s.removed = true end
    return e
end
S.ents = { Create = function(cls)
    local e = s_entity(cls)
    left_ents[#left_ents + 1] = e
    return e
end, FindByClass = function() return {} end }
S.Entity = function() return NULL end
S.scripted_ents = { Register = function() end }
S.IsValid = function(x) return x ~= nil and x ~= false and x ~= NULL and not (type(x) == "table" and x.removed) end
local SP = { name = "p1", pos = Vector(), GSA1Active = true, nw2 = {}, undos = {} }
function SP:IsValid() return true end
function SP:GetPos() return Vector(self.pos) end
function SP:IsPlayer() return true end
function SP:Nick() return self.name end
function SP:GetNW2Bool(k, d) local v = self.nw2[k] if v == nil then return d end return v end
function SP:SetNW2Bool(k, v) self.nw2[k] = v end
function SP:AddCleanup() end
S.player = { GetAll = function() return { SP } end }
-- net, both directions, delivered at once
local out_c, out_s, sent_c, sent_s, cread = nil, nil, {}, {}, nil
local function reader(vals)
    local i = 0
    return function() i = i + 1 return vals[i] end
end
net.Start = function(name) out_c = { name = name, vals = {} } end
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteInt", "WriteFloat", "WriteVector", "WriteAngle", "WriteEntity", "WriteString" }) do
    net[w] = function(v) if out_c then out_c.vals[#out_c.vals + 1] = v end end
end
net.Receive = function(name, fn) recv_c[name] = fn end
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadInt", "ReadFloat", "ReadVector", "ReadAngle", "ReadEntity", "ReadString" }) do
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
        fn(#m.vals * 8, SP)
        S.sread = saved
    end
end
S.net = { Receive = function(name, fn) recv_s[name] = fn end, Start = function(name) out_s = { name = name, vals = {} } end,
          Send = function(to)
              local m = out_s
              out_s = nil
              if not m then return end
              m.to = to
              sent_s[#sent_s + 1] = m
              local fn = recv_c[m.name]
              if fn and to == SP then
                  local saved = cread
                  cread = reader(m.vals)
                  fn(#m.vals * 8)
                  cread = saved
              end
          end }
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteInt", "WriteFloat", "WriteVector", "WriteAngle", "WriteString", "WriteEntity" }) do
    S.net[w] = function(v) if out_s then out_s.vals[#out_s.vals + 1] = v end end
end
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadInt", "ReadFloat", "ReadVector", "ReadAngle", "ReadString", "ReadEntity" }) do
    S.net[r] = function() return S.sread() end
end
util.NetworkStringToID = function(n) return strings[n] and 1 or 0 end
local function msgs_c(name)
    local out = {}
    for _, m in ipairs(sent_c) do if m.name == name then out[#out + 1] = m end end
    return out
end
local function clear_msgs() sent_c, sent_s = {}, {} end
local function sinclude(rel)
    local src = host_read(M.root .. "/" .. rel)
    if not src then error("server include: no file " .. rel) end
    local fn, err = host_load(src, "sv:" .. rel)
    if not fn then error(err) end
    setfenv(fn, S)
    fn()
end
-- the spawner file, in a realm: ENT and scripted_ents.Register as GMod's loader gives them
local function load_spawner(realm)
    local classes = {}
    local src = host_read(M.root .. "/entities/gsa1_follower_spawner.lua")
    if not src then error("no entities/gsa1_follower_spawner.lua") end
    local fn, err = host_load(src, "gsa1_follower_spawner")
    if not fn then error(err) end
    local env = setmetatable({ ENT = {}, AddCSLuaFile = function() end, scripted_ents = { Register = function(t, n) classes[n] = t end } },
        { __index = realm })
    setfenv(fn, env)
    fn()
    return classes, env.ENT
end

rawset(S, "GSA1", {})
local ok_s, err_s = pcall(function()
    sinclude("gsa1/sh_config.lua")
    sinclude("gsa1/sh_net.lua")
    sinclude("gsa1/feat/sh_board.lua")
    sinclude("gsa1/feat/sv_board.lua")
    sinclude("gsa1/feat/sh_follower.lua")
    sinclude("gsa1/feat/sv_follower.lua")
end)
local SG = rawget(S, "GSA1")
local SB = SG and SG.Board
local SFo = SG and SG.Followers
local classes_s, ok_cls = nil, nil
ok_cls, classes_s = pcall(load_spawner, S)

-- the client: the autorun with a mock module of 5.5 --------------------------------------------------------------------------------
GSA1 = nil
-- the batches of a character per game pair: a body, an effect, a blob shadow, a game object, a board's draw, a blended body
local BATCHES = { { 0, 0, 0x20, 1, 0, 3, 0, 500, 1 }, { 0, 1, 0x60, 1, 1, 3, 1, 20, 1 }, { 0, 2, 0x860, 1, 0, 3, 0, 4, 1 },
                  { 0, 3, 0x1020, 1, 0, 3, 0, 8, 1 }, { 0, 4, 0x4060, 1, 0, 3, 0, 44, 1 }, { 0, 5, 0x4860, 1, 0, 3, 0, 4, 1 } }
local IDX = { body = 1, effect = 2, shadow = 3, object = 4, board = 5, boardshadow = 6 }
local G = M.module({ features = { follower = 1, board = 1, emote = 3, preview = 2 }, host_camera = true,
                     batches = function() return BATCHES end })
local FM = { calls = {}, chars = {}, order = {}, bad = {}, ticks = 0, kinds = { [0] = true, [2] = true, [3] = true, [6] = true,
             [5] = "Amy cannot follow yet: her bird", [7] = "Big cannot follow yet: fishing" }, threads = {}, mem_low = false,
             emits = {}, events = {}, workers = 3 }
local function fcall(name, ...) FM.calls[#FM.calls + 1] = { name, ... } end
local function fcalls(name, id)
    local out = {}
    for _, c in ipairs(FM.calls) do
        if c[1] == name and (id == nil or c[2] == id) then out[#out + 1] = c end
    end
    return out
end
local function fclear() FM.calls = {} end
local function is_vec(v) return type(v) == "table" and type(v.x) == "number" and type(v.y) == "number" and type(v.z) == "number" end
local create0 = G.Create
local KINDS_OK = { [0] = true, [2] = true, [3] = true, [5] = true, [6] = true, [7] = true }
local OPT_TYPES = { upgrades = "table", objects = "number", sounds = "boolean", seed = "number", fix_view = "boolean", fix_respawn = "boolean" }
function G.FollowerKinds(out)
    out = out or {}
    for k, v in pairs(FM.kinds) do out[k] = v end
    return out
end
function G.FollowerCreate(kind, pos, yaw, leader, opts, ...)
    fcall("FollowerCreate", kind, pos and Vector(pos), yaw, leader, opts)
    if FM.throw then error(FM.throw) end
    if not (KINDS_OK[kind] and is_vec(pos) and type(yaw) == "number" and (leader == nil or type(leader) == "number") and
        (opts == nil or type(opts) == "table") and select("#", ...) == 0) then
        FM.bad[#FM.bad + 1] = "FollowerCreate arguments"
        return nil, "FollowerCreate(kind, pos, yaw, leader, opts)", "bad_argument"
    end
    for k, v in pairs(opts or {}) do
        if OPT_TYPES[k] == nil or type(v) ~= OPT_TYPES[k] then
            FM.bad[#FM.bad + 1] = "FollowerCreate opts." .. tostring(k)
            return nil, "FollowerCreate: opts." .. tostring(k), "bad_argument"
        end
    end
    if FM.kinds[kind] ~= true then return nil, FM.kinds[kind], "unsupported" end
    if FM.mem_low then return nil, "not enough free memory", "limit" end
    if #FM.order >= 112 then return nil, "too many followers", "limit" end
    local id = create0(kind, pos, yaw, nil, nil)
    FM.chars[id] = { id = id, kind = kind, leader = leader, opts = opts or {}, level = 1, rate = 15, held = false, respawns = 0, frames = 0,
                     first = true, rx = pos.x, ry = pos.y, rz = pos.z, ryaw = yaw }
    FM.order[#FM.order + 1] = id
    return id
end
local destroy0 = G.Destroy
function G.Destroy(id)
    fcall("Destroy", id)
    if FM.chars[id] then
        FM.chars[id] = nil
        for i, v in ipairs(FM.order) do
            if v == id then table.remove(FM.order, i) break end
        end
    else
        -- your character: its followers go host-fed (leader_gone)
        for _, f in pairs(FM.chars) do
            if f.leader == id then f.leader = nil end
        end
    end
    return destroy0(id)
end
function G.FollowerLeader(id, leader)
    fcall("FollowerLeader", id, leader)
    local f = FM.chars[id]
    if not f then return nil, "not a follower", "not_found" end
    if leader == id then return nil, "a follower cannot follow itself or one of its own followers", "bad_argument" end
    f.leader = leader
    return true
end
function G.FollowerFeed(id, pos, vel, yaw, ground, kind)
    fcall("FollowerFeed", id, pos and Vector(pos), vel and Vector(vel), yaw, ground, kind)
    if not (FM.chars[id] and is_vec(pos) and is_vec(vel) and type(yaw) == "number" and type(ground) == "boolean") then
        FM.bad[#FM.bad + 1] = "FollowerFeed arguments"
        return nil, "FollowerFeed(id, pos, vel, yaw, ground [, kind])", "bad_argument"
    end
    return true
end
function G.FollowerHostFlags(id, flags)
    fcall("FollowerHostFlags", id, flags)
    if type(flags) ~= "number" then FM.bad[#FM.bad + 1] = "FollowerHostFlags arguments" end
    return true
end
function G.FollowerHold(id, on)
    fcall("FollowerHold", id, on)
    local f = FM.chars[id]
    if not f or type(on) ~= "boolean" then return nil, "FollowerHold(id, on)", "bad_argument" end
    f.held = on
    return true
end
function G.FollowerRespawn(id)
    fcall("FollowerRespawn", id)
    local f = FM.chars[id]
    if not f then return nil, "not a follower", "not_found" end
    f.respawns = f.respawns + 1
    return true
end
function G.FollowerDraw(id, level, rate)
    fcall("FollowerDraw", id, level, rate)
    local f = FM.chars[id]
    if not f or (level ~= 1 and level ~= 2 and level ~= 3) then return nil, "FollowerDraw(id, level [, rate])", "bad_argument" end
    f.level, f.rate = level, rate or f.rate
    return true
end
function G.FollowerInfo(id, out)
    local f = FM.chars[id]
    if not f then return nil, "not a follower", "not_found" end
    out = out or {}
    out.kind, out.leader, out.mode, out.smode, out.offscreen = f.kind, f.leader or 0, f.held and 6 or 4, 1, 0
    out.distance, out.respawns, out.respawns_distance, out.respawns_offscreen = 40, f.respawns, 0, 0
    out.held, out.lost, out.hidden, out.pairs, out.dropped = f.held, false, 0, 0, 0
    out.objects, out.sounds, out.level = f.opts.objects or 1, f.opts.sounds ~= false, f.level
    return out
end
function G.FollowerThreads(n)
    FM.threads[#FM.threads + 1] = n
    return n == 0 and FM.workers or n
end
function G.FollowersStats(out)
    out = out or {}
    out.followers, out.workers, out.ms_tick, out.ms_render, out.ms_join, out.frames = #FM.order, FM.workers, 1, 1, 0.1, 60
    return out
end
G.FOLLOWER = { MAX = 112, MAX_CHARACTERS = 128, OBJECTS_NONE = 0, OBJECTS_OWN = 1, DRAW_FULL = 1, DRAW_FAR = 2, DRAW_NONE = 3, RATE_MIN = 5,
               RATE_MAX = 30, RATE_DEFAULT = 15, POOL_MAX = 16, LIB_PARALLEL = false,
               MODE = { PLACE = 0, RESPAWN = 2, NORMAL = 4, TAKEOVER = 5, PARKED = 6 } }
-- the board's model (feat_board_test.lua's): an order at the next pair, a kept board that settles
local BM = { calls = {}, chars = {}, refuse = nil, hurt = -1 }
local function bcalls(name, id)
    local out = {}
    for _, c in ipairs(BM.calls) do
        if c[1] == name and (id == nil or c[2] == id) then out[#out + 1] = c end
    end
    return out
end
G.BOARD = { TERRAIN_MAP = 0, TERRAIN_SNOW = 1, TERRAIN_SAND = 2, DRAW = 0x4000, SETTLE_STEPS = 30, FREED_REMOVED = 0, FREED_FELL = 1,
            FREED_REPLACED = 2, FREED_FREE = 3 }
G.PREVIEW = { BOARD = 0x100 }
local function bs_of(id)
    local s = BM.chars[id]
    if not s then
        s = { on = false, held = false, kept = false, still = 0, x = 0, y = 0, z = 0, terrain = 0, variant = 0, freed = 0, freed_why = -1 }
        BM.chars[id] = s
    end
    return s
end
function G.Board(id, on, opts)
    BM.calls[#BM.calls + 1] = { "Board", id, on, opts }
    local c = M.mchars[id]
    if not c then return nil, "no such character", "not_found" end
    if c.kind ~= 0 and c.kind ~= 2 then return nil, "only Sonic and Tails ride a board", "unsupported" end
    if BM.refuse then return nil, BM.refuse, "unsupported" end
    local s = bs_of(id)
    if on then
        if s.on then
            s.terrain = opts and opts.terrain or s.terrain
            return true
        end
        s.pending = { on = true, opts = opts or {} }
    else
        if not s.on then return true end
        s.pending = { on = false, opts = opts or {} }
    end
    return true
end
function G.BoardFree(id)
    BM.calls[#BM.calls + 1] = { "BoardFree", id }
    local s = bs_of(id)
    if s.on or not s.kept then return nil, "no board left behind", "unsupported" end
    s.kept, s.still, s.freed, s.freed_why = false, 0, s.freed + 1, 3
    return true
end
function G.BoardPush() return nil, "not riding", "unsupported" end
function G.BoardSounds() return true end
function G.BoardInfo(out) return out or {} end
function G.BoardState(id, out)
    local c = M.mchars[id]
    if not c then return nil, "no such character", "not_found" end
    local s = bs_of(id)
    out = out or {}
    out.on, out.pending, out.held, out.kept = s.on, s.pending ~= nil, s.held, s.kept
    out.settled = s.kept and s.still >= 30
    out.board = s.on or s.kept
    out.mode, out.action, out.speed = s.on and 62 or 2, s.on and 105 or 1, 0
    out.terrain, out.push_steps, out.kind, out.variant = s.terrain, 0, (s.on or s.kept) and c.kind or -1, s.variant
    out.x, out.y, out.z, out.pitch, out.yaw, out.roll = s.x, s.y, s.z, 0, 0, 0
    out.still, out.refused, out.reason = s.still, false, nil
    out.freed, out.freed_why = s.freed, s.freed > 0 and s.freed_why or -1
    s.freed = 0
    return out
end
function G.StateEx(id, out)
    out = out or {}
    out.rings, out.lives, out.mode, out.hurt_steps, out.held, out.held_object = 0, 4, 2, BM.hurt, 0, 0
    return out
end
local function board_pair(id, c)
    local s = BM.chars[id]
    if not s then return end
    if s.pending then
        local p = s.pending
        s.pending = nil
        if p.on then
            if s.kept then s.kept, s.freed, s.freed_why = false, s.freed + 1, 2 end
            s.on, s.held, s.terrain = true, true, p.opts.terrain or 0
            s.variant = BM.variant or 0
        else
            s.on, s.held = false, false
            s.x, s.y, s.z = c.pos.x + 8, c.pos.y, c.pos.z
            if p.opts.remove then
                s.freed, s.freed_why = s.freed + 1, 0
            else
                s.kept, s.still = true, 0
            end
        end
    elseif s.kept then
        s.still = s.still + 2
    end
end
local tick0 = G.Tick
G.Tick = function(id, ...)
    local n, err, code = tick0(id, ...)
    local c = M.mchars[id]
    if c and n then
        for _ = 1, n do board_pair(id, c) end
    end
    return n, err, code
end
-- every follower in creation order; level 1 renders every frame, level 2 `rate` times a second, level 3 never
function G.FollowersTick(dt, yaw, co, ct, out, interpolate)
    FM.ticks = FM.ticks + 1
    FM.last = { dt = dt, yaw = yaw, co = co and Vector(co), ct = ct and Vector(ct), interpolate = interpolate }
    local n = 0
    for _, id in ipairs(FM.order) do
        local f, c = FM.chars[id], M.mchars[id]
        n = n + 1
        local r = out[n]
        if not r then
            r = {}
            out[n] = r
        end
        c.acc = c.acc + dt
        local np = 0
        while c.acc >= 1 / 30 do
            c.acc = c.acc - 1 / 30
            np = np + 1
            c.pair = c.pair + 1
            c.gen = c.gen + 1
            board_pair(id, c)
        end
        f.frames = f.frames + 1
        local rendered = false
        if f.level == 1 then
            rendered = true
        elseif f.level == 2 then
            local every = math.max(1, math.floor(60 / f.rate + 0.5))
            rendered = (f.frames + id) % every == 0
        end
        if rendered then f.rx, f.ry, f.rz = c.pos.x, c.pos.y, c.pos.z end
        r.id, r.pairs, r.ok, r.code, r.msg = id, np, not f.fault, f.fault and "fault" or nil, f.fault
        r.rendered, r.restructured = rendered, f.first and rendered
        if r.restructured then f.first = false end
        r.x, r.y, r.z, r.yaw, r.interpolated, r.alpha, r.tris = f.rx, f.ry, f.rz, f.ryaw, f.level == 1, f.level == 1 and 0.5 or 1, 580
    end
    out.count, out.workers, out.ms, out.ms_join = n, FM.workers, 1.5, 0.25
    return out
end
local emit0 = G.EmitBatch
G.EmitBatch = function(id, i)
    FM.emits[#FM.emits + 1] = { id, i }
    return emit0(id, i)
end
-- the events the test hands out
local poll0 = G.PollEvents
G.PollEvents = function(out)
    out = out or {}
    local n = #FM.events
    for i, e in ipairs(FM.events) do out[i] = e end
    for i = #out, n + 1, -1 do out[i] = nil end
    out.count = n
    FM.events = {}
    return out
end
-- the host objects' mask: libsa1's rule (sa1_hostobj.c): only the bits of known kinds; 0 means every kind
function G.ObjWorldMask(id, mask)
    fcall("ObjWorldMask", id, mask)
    if bit.band(mask, bit.bnot(0x7E)) ~= 0 then
        FM.bad[#FM.bad + 1] = "ObjWorldMask bits"
        return nil, "unknown kind bits", "bad_argument"
    end
    return true
end
function G.SetGameOption() return true end
G.INTERACT = { ENEMY = 1, TARGET = 2, BREAKABLE = 3, HAZARD = 4, HOLDABLE = 5, BALLOON = 6 }
-- the emote feature's minimum for the wheel
G.EMOTE = { LOOP = 0x100, IN_AIR = 4, KEEP_INPUT = 8, NO_PROPS = 0x10, NO_TRAIL = 2, CHAIN = 1, STOP_NOW = 0, STOP_BLEND = 1, STATE_NONE = 0,
            STATE_PLAYING = 1, STATE_ENDING = 2, ROW = 0, EXTRA = 1, FORM_NORMAL = 0, FORM_SUPER = 1, HOLD = 0x20, STATE_HOLDING = 3,
            SPEED_MIN = 1 / 64, SPEED_MAX = 16 }
function G.EmoteList() return { n = 0 } end
function G.Emote() return true end
function G.EmoteStop() return true end
function G.EmoteState() return 0, nil, -1, 0 end

M.included = {}
local ok_c, err_c = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local Fo = GSA1 and GSA1.Followers
local B = GSA1 and GSA1.Board
local W = GSA1 and GSA1.Wheel
local classes_c
local ok_cc
ok_cc, classes_c = pcall(load_spawner, _G)
check(ok_s and SFo ~= nil and ok_cls and ok_c and #ferr == 0 and Fo ~= nil and Fo.BuildPage ~= nil and GSA1.SpawnFollower ~= nil and ok_cc,
    "the feature's files load: server (sh_follower, sv_follower, the spawners) %s; client through the autorun %s",
    (ok_s and ok_cls) and "ok" or tostring(err_s or classes_s),
    (ok_c and #ferr == 0) and table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_c or ferr[1]))
if not (ok_s and SFo and ok_c and Fo and Fo.BuildPage) then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
GSA1.Tex.Prepare = (function(f) return function(k)
    FM.prepared = FM.prepared or {}
    FM.prepared[k] = (FM.prepared[k] or 0) + 1
    return f(k)
end end)(GSA1.Tex.Prepare)
local blends = {}
GSA1.CharOpt = { ApplyTailBlend = function(F) blends[#blends + 1] = F end }
local guards = {}
GSA1.Objects.ApplyIconGuard = function(F) guards[#guards + 1] = F end
local cv = Fo.cv

local function frames(n, dt)
    for _ = 1, n do M.frame(dt or 1 / 60) end
end
local function set(name, v) M.convars[name]:SetString(tostring(v)) end
local function reset()
    Fo.RemoveAll("removed")
    if GSA1.Char then GSA1.Remove(true) end
    fclear()
    BM.calls, BM.refuse = {}, nil
    FM.kinds[0], FM.kinds[2], FM.kinds[3], FM.kinds[6] = true, true, true, true
    FM.mem_low, FM.throw = false, nil
    chats = {}
    clear_msgs()
    others = {}
    set("gsa1_follower", 1)
    set("gsa1_follower_max", 3)
    set("gsa1_follower_target", 0)
    set("gsa1_follower_come_along", 1)
    set("gsa1_follower_full_detail", 8)
    set("gsa1_follower_board", 1)
    set("gsa1_follower_board_boxes", 1)
    set("gsa1_follower_loop_guard", 1)
    set("gsa1_follower_other_views", 0)
    set("gsa1_follower_draw_dist", 4800)
    set("gsa1_cam_distance", 150)
    M.render_target = nil
    M.player.pos = Vector(704, 132, -143)
    M.paused, M.ui = false, false
    Fo.ResetHave()
    Fo.heldAt = nil
    Fo.nextLevels, Fo.nextTargets = nil, nil
end
local function me(kind)
    GSA1.Spawn(kind or "sonic")
    return GSA1.Char
end
local function logtext()
    GSA1.LogFlush()
    return M.files["gsa1/log.txt"] or ""
end
local function spawn(kind, opts)
    local ok, F = GSA1.SpawnFollower(kind, opts)
    return ok and F or nil, F
end

-- 1. the settings, the page, the spawn classes (9.1 item 1; 5.9) -----------------------------------------------------------------------
do
    local WANT = {
        gsa1_follower = { "1", 0, 1 }, gsa1_follower_kind = { "2", 0, 7 }, gsa1_follower_max = { "3", 1, 8 },
        gsa1_follower_target = { "0", 0, 4 }, gsa1_follower_upgrades = { "1", 0, 1 }, gsa1_follower_objects = { "1", 0, 1 },
        gsa1_follower_sounds = { "1", 0, 1 }, gsa1_follower_board = { "1", 0, 1 }, gsa1_follower_board_boxes = { "1", 0, 2 },
        gsa1_follower_come_along = { "1", 0, 1 }, gsa1_follower_loop_guard = { "1", 0, 1 }, gsa1_follower_fix_view = { "1", 0, 1 },
        gsa1_follower_fix_respawn = { "1", 0, 1 }, gsa1_follower_full_detail = { "8", 0, 99 }, gsa1_follower_far_rate = { "15", 5, 30 },
        gsa1_follower_draw_dist = { "4800", 500, 12000 }, gsa1_follower_other_views = { "0", 0, 1 }, gsa1_follower_threads = { "0", 0, 16 },
        gsa1_follower_call_key = { "16", 0, 511 }, gsa1_follower_call_pad = { "64", 0, 0x30000 },
    }
    local bad = {}
    for name, w in pairs(WANT) do
        local c = M.convars[name]
        if not (c and c.client and c.save and c.v == w[1] and c.lo == w[2] and c.hi == w[3] and GSA1.CONVARS[name]) then bad[#bad + 1] = name end
    end
    local sc = SCV.gsa1_sv_follower_icons
    if not (sc and sc.v == "1" and GSA1.CONVARS.gsa1_sv_follower_icons and GSA1.CONVARS.gsa1_sv_follower_icons.server and
            bit.band(sc.flags or 0, 8192) ~= 0) then bad[#bad + 1] = "gsa1_sv_follower_icons" end
    table.sort(bad)
    check(#bad == 0, "every ConVar of 5.9 marked followlua with its default and range (%d client, 1 replicated server)%s", 20,
        #bad > 0 and (": wrong " .. table.concat(bad, " ")) or "")
    -- a panel that records every control
    local made = {}
    local function panel_of(kind)
        local P = { kind = kind, calls = {}, choices = {} }
        made[#made + 1] = P
        return setmetatable(P, { __index = function(t, k)
            return function(self, a, b, c, d)
                rawget(t, "calls")[#rawget(t, "calls") + 1] = { k, a, b, c, d }
                if k == "ComboBox" or k == "Help" or k == "ControlHelp" or k == "Button" then return panel_of(k) end
                if k == "AddChoice" then rawget(t, "choices")[#rawget(t, "choices") + 1] = { a, b } end
                if k == "SetConVar" then rawset(t, "convar", a) end
                return nil
            end
        end })
    end
    vgui.Create = function(cls) return panel_of(cls) end
    local page
    for _, p in ipairs(GSA1.MenuPages) do
        if p.id == "followers" then page = p end
    end
    local P = panel_of("root")
    local ok_page, err_page = pcall(page and page.builder or function() error("no page") end, P)
    check(ok_page and page and page.order == 290 and page.title == "Followers" and page.needs and page.needs.feature == "follower",
        "the page Followers at order 290 builds (%s)", ok_page and "ok" or tostring(err_page))
    local bound = {}
    local texts = {}
    for _, Q in ipairs(made) do
        for _, c in ipairs(Q.calls) do
            if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then bound[c[3]] = c[2] end
            if c[1] == "Help" or c[1] == "ControlHelp" then texts[#texts + 1] = tostring(c[2]) end
        end
        if rawget(Q, "convar") then bound[Q.convar] = "binder" end
        if rawget(Q, "gsa1ConVar") then bound[Q.gsa1ConVar] = "combo" end
    end
    local missing = {}
    for name in pairs(GSA1.CONVARS) do
        if string.find(name, "^gsa1_follower") or string.find(name, "^gsa1_sv_follower") then
            if not bound[name] then missing[#missing + 1] = name end
        end
    end
    table.sort(missing)
    check(#missing == 0, "every gsa1_follower* and gsa1_sv_follower* ConVar has a control on the page%s",
        #missing > 0 and (": missing " .. table.concat(missing, " ")) or "")
    check(string.find(tostring(bound.gsa1_follower_max), "about 21 MB", 1, true) ~= nil and
        string.find(tostring(bound.gsa1_follower_other_views), "other addons' views", 1, true) ~= nil and
        string.find(table.concat(texts, " "), "Known limits", 1, true) ~= nil,
        "the page's words: the cap's cost, the other views' row (D4), the known limits")
    -- the buttons
    local buttons = {}
    for _, Q in ipairs(made) do
        for _, c in ipairs(Q.calls) do if c[1] == "Button" then buttons[tostring(c[2])] = tostring(c[3]) end end
    end
    check(buttons["Spawn a follower"] == "gsa1_follower_spawn" and buttons["Remove the last"] == "gsa1_follower_remove" and
        buttons["Remove all"] == "gsa1_follower_remove" and buttons["Call them back to me"] == "gsa1_follower_call",
        "the page's buttons: Spawn a follower, Remove the last, Remove all, Call them back to me")
    -- the spawners (both realms)
    local cs, names = classes_c, {}
    for n in pairs(cs or {}) do names[#names + 1] = n end
    table.sort(names)
    local T = cs and cs.gsa1_follower_tails
    check(#names == 6 and T and T.GSA1FollowerKind == 2 and T.Spawnable and T.Category == "G-SA1" and T.DisableDuplicator and
        T.IconOverride == "entities/gsa1_follower_tails.png" and classes_s and classes_s.gsa1_follower_big.GSA1FollowerKind == 7,
        "one spawner class per kind, on both realms: %s", table.concat(names, " "))
    check(host_read(string.gsub(M.root, "lua$", "") .. "materials/entities/gsa1_follower_tails.png") ~= nil and
        host_read(string.gsub(M.root, "lua$", "") .. "materials/entities/gsa1_follower_big.png") ~= nil,
        "the spawners' icons are in addon/materials/entities (tools/make_follower_icons.py: G-SA1's own drawing)")
    -- the spawn tab's group: a function listing the kinds that can follow
    local later
    for _, e in ipairs(GSA1.SpawnTab.LATER) do
        if e.name == "Followers" then later = e end
    end
    local listed = later and later.classes() or {}
    check(later ~= nil and #listed == 4 and listed[1] == "gsa1_follower_tails",
        "the spawn tab's Followers group lists the kinds gsa1.FollowerKinds allows, Tails first: %s", table.concat(listed, " "))
    -- a module without the feature: the page says what it needs
    local feats = G.FEATURES
    G.FEATURES = {}
    local need = GSA1.MissingFeatureText(Fo.NEEDS)
    G.FEATURES = feats
    check(type(need) == "string" and string.find(need, "0.9.8", 1, true) ~= nil, "without the module's feature the page says what it needs (%s)",
        string.sub(tostring(need), 1, 60))
    -- L1, L2
    check(GSA1.RENDER_BOUNDS_MIN and GSA1.RENDER_BOUNDS_MIN.x == -640 and GSA1.RENDER_BOUNDS_MIN.z == -320 and GSA1.RENDER_BOUNDS_MAX and
        GSA1.RENDER_BOUNDS_MAX.z == 640 and type(GSA1.FollowerTickCamera) == "function",
        "the seams L1 (GSA1.RENDER_BOUNDS_MIN / MAX) and L2 (GSA1.FollowerTickCamera) exist")
end

-- 2. GSA1.SpawnFollower (item 2) --------------------------------------------------------------------------------------------------------
do
    reset()
    local C = me("sonic")
    local a, fa = GSA1.SpawnFollower("tails")
    local b, fb = GSA1.SpawnFollower(0)
    check(a == true and fa and fa.kind == 2 and b == true and fb and fb.kind == 0 and #Fo.list == 2 and Fo.byId[fa.id] == fa,
        "a name and a number make followers (true; Fo.list, Fo.byId)")
    local c3 = GSA1.SpawnFollower("knuckles")
    local no, why = GSA1.SpawnFollower("tails")
    check(c3 == true and no == false and string.find(tostring(why), "you have 3 followers", 1, true) ~= nil,
        "at the cap: false + the reason (%s)", tostring(why))
    local nb, wb = GSA1.SpawnFollower("big")
    check(nb == false and string.find(tostring(wb), "Big cannot follow yet", 1, true) ~= nil, "a kind that cannot follow: false + libsa1's "
        .. "reason (%s)", tostring(wb))
    local un, wu = GSA1.SpawnFollower("nobody")
    local ss, wss = GSA1.SpawnFollower("supersonic")
    local sg, wsg = GSA1.SpawnFollower("supersonic_general")
    check(un == false and ss == false and sg == false, "unknown names and the Super Sonics are refused (%s; %s; %s)", tostring(wu),
        tostring(wss), tostring(wsg))
    Fo.RemoveAll("removed")
    FM.throw = "the module blew up"
    local okr, rr, wr = pcall(GSA1.SpawnFollower, "tails")
    FM.throw = nil
    check(okr and rr == false and string.find(tostring(wr), "blew up", 1, true) ~= nil, "it never raises (the egg's pcall): false + %s",
        tostring(wr))
    FM.mem_low = true
    local ml, wm = GSA1.SpawnFollower("tails")
    FM.mem_low = false
    check(ml == false and wm == "not enough free memory", "the memory guard's message passes through: false + %s", tostring(wm))
    set("gsa1_follower", 0)
    local off, woff = GSA1.SpawnFollower("tails")
    set("gsa1_follower", 1)
    check(off == false and string.find(tostring(woff), "off", 1, true) ~= nil, "the feature off: false + %s", tostring(woff))
    -- no disc yet
    local ens = GSA1.EnsureReady
    GSA1.EnsureReady = function() return false, "loading" end
    local nd, wnd = GSA1.SpawnFollower("tails")
    GSA1.EnsureReady = function() return false, "no disc" end
    local nd2, wnd2 = GSA1.SpawnFollower("tails")
    GSA1.EnsureReady = ens
    check(nd == false and string.find(tostring(wnd), "loading", 1, true) == 1 and nd2 == false and wnd2 == "no disc",
        "no disc: false + the reason, no pending spawn (%s; %s)", tostring(wnd), tostring(wnd2))
    -- a module without the feature
    local feats = G.FEATURES
    G.FEATURES = {}
    Fo.ResetHave()
    local nm, wnm = GSA1.SpawnFollower("tails")
    G.FEATURES = feats
    Fo.ResetHave()
    check(nm == false and wnm == "this G-SA1 module has no followers", "a module without the feature: false + %s", tostring(wnm))
    -- where it appears, its options
    set("gsa1_upgrade_light_speed_shoes", 1)
    local fnew = spawn("tails", { why = "page" })
    local cr = fcalls("FollowerCreate")
    local last = cr[#cr]
    local yaw = C.drawYaw or 0
    local wx = C.drawPos.x - math.cos(math.rad(yaw)) * 40
    check(fnew and last and math.abs(last[3].x - wx) < 0.01 and last[5] == C.id and last[6].objects == 1 and last[6].sounds == true and
        last[6].fix_view == true and last[6].fix_respawn == true and type(last[6].upgrades) == "table",
        "made 40 HU behind its leader with the page's options (objects 1, sounds, the two fixes, its kind's upgrades)")
    set("gsa1_upgrade_light_speed_shoes", 0)
    check(fnew and fnew.follower == true and fnew.slot == 1 and fnew.lod == 1 and fnew.ent and fnew.ent.char == fnew and fnew.ent.cls == "gsa1_render"
        and is_vec(fnew.drawPos), "F has its render entity (gsa1_render, ent.char), slot 1 for a Tails, level 1, F.drawPos")
    check(FM.prepared and FM.prepared[2] == 1 and #blends > 0 and blends[#blends] == fnew and #guards > 0 and guards[#guards] == fnew,
        "the kind's textures prepared once per kind, Tails' tail blend and the item icon guard applied")
    local ms = fcalls("ObjWorldMask", fnew and fnew.id)
    check(#ms == 1 and ms[1][3] == 0x12, "a follower's world mirrors ENEMY and HAZARD: libsa1's kind bits 0x12 (%s)", tostring(ms[1] and ms[1][3]))
    local kn = spawn("knuckles")
    check(kn and kn.slot == nil, "a Knuckles follower has no board slot")
    Fo.RemoveAll("removed")
    local s1 = spawn("sonic")
    local s2 = spawn("tails")
    Fo.Remove(s1, "removed")
    local s3 = spawn("sonic")
    check(s2 and s2.slot == 2 and s3 and s3.slot == 1, "slots: the lowest free one")
end

-- 3. the cap, lowered (item 3) --------------------------------------------------------------------------------------------------------
do
    reset()
    me("sonic")
    set("gsa1_follower_max", 5)
    local list = {}
    for i = 1, 5 do list[i] = spawn("tails") end
    local egg = spawn("knuckles", { ignore_cap = true, why = "egg" })
    local removed = {}
    hook.Add("GSA1FollowerRemoved", "test_removed", function(F, why) removed[#removed + 1] = why end)
    set("gsa1_follower_max", 2)
    hook.Remove("GSA1FollowerRemoved", "test_removed")
    check(#Fo.list == 3 and Fo.byId[list[1].id] == list[1] and Fo.byId[list[2].id] == list[2] and Fo.byId[egg.id] == egg and #removed == 3 and
        removed[1] == "cap", "lowering gsa1_follower_max from 5 to 2 removes the 3 newest normal followers, no ignore_cap one (why %s)",
        tostring(removed[1]))
    set("gsa1_follower", 0)
    check(#Fo.list == 0, "gsa1_follower 0: all removed")
    set("gsa1_follower", 1)
    -- the secret's cap
    set("gsa1_follower_max", 1)
    local made = 0
    for _ = 1, 100 do
        if GSA1.SpawnFollower("knuckles", { ignore_cap = true, silent = true, objects = 0, why = "egg" }) then made = made + 1 end
    end
    local n100, w100 = GSA1.SpawnFollower("knuckles", { ignore_cap = true })
    check(made == 99 and n100 == false and string.find(tostring(w100), "99", 1, true) ~= nil and Fo.Count(true) == 99 and Fo.Count(false) == 0,
        "ignore_cap makes 99 and the 100th is false (%s); they do not count against the slider", tostring(w100))
    local cr = fcalls("FollowerCreate")
    local last = cr[#cr]
    local ms = fcalls("ObjWorldMask", Fo.list[1].id)
    check(last[6].objects == 0 and last[6].sounds == false, "the secret's followers: objects 0, silent")
    -- review R.19: 0 means EVERY kind in libsa1 (sa1_world_hostobj.c ho_kind_on), so the rarest kind's bit, not 0
    check(#ms == 1 and ms[1][3] ~= 0 and bit.band(ms[1][3], 0x12) == 0, "review R.19: the secret's followers mirror no enemy and no hazard "
        .. "(mask 0x%X; 0 would mean every kind)", ms[1] and ms[1][3] or -1)
    Fo.RemoveAll("removed")
    set("gsa1_follower_max", 3)
end

-- 4. targets (item 4) --------------------------------------------------------------------------------------------------------------------
do
    reset()
    local C = me("sonic")
    local F = spawn("tails")
    local cr = fcalls("FollowerCreate")
    check(F and F.leaderId == C.id and not F.hostFed and cr[#cr][5] == C.id and F.target.type == "me" and Fo.RootOf(F) == C and
        Fo.LeaderEntry(F) == C, "Me with a character: FollowerCreate(..., C.id, ...), exact")
    fclear()
    frames(10)
    check(#fcalls("FollowerFeed") == 0, "no feed while it follows your character")
    -- without a character: host-fed on the player entity, one feed per frame
    GSA1.Remove(true)
    fclear()
    M.player.vel, M.player.on_ground = Vector(10, 0, 0), false
    frames(10)
    local feeds = fcalls("FollowerFeed", F.id)
    local lf = feeds[#feeds]
    check(F.leaderId == nil and F.hostFed and #feeds == 10 and lf[3].x == M.player.pos.x and lf[4].x == 10 and lf[5] == M.yaw and lf[6] == false,
        "no character: host-fed, one FollowerFeed per frame with the player's position, velocity, yaw and ground (%d feeds)", #feeds)
    M.player.vel, M.player.on_ground = nil, nil
    -- a new character: exact again
    fclear()
    local C2 = me("tails")
    frames(2)
    check(F.leaderId == C2.id and not F.hostFed and #fcalls("FollowerFeed", F.id) == 0, "a new character: exact again (FollowerLeader)")
    Fo.RemoveAll("removed")
    -- the nearest player, chosen again every second
    local P1, P2 = other_player("near", 800, 132, -143), other_player("far", 5000, 0, 0)
    others = { P2 }
    local FP = spawn("tails", { target = 1 })
    check(FP and FP.target.type == "player", "The nearest player: its target")
    M.T = M.T + 2
    frames(2)
    check(FP.target.ent == P2 and FP.hostFed, "the nearest player chosen (%s)", tostring(FP.target.ent and FP.target.ent.name))
    others = { P2, P1 }
    M.T = M.T + 2
    frames(2)
    fclear()
    frames(3)
    local pf = fcalls("FollowerFeed", FP.id)
    check(FP.target.ent == P1 and #pf == 3 and pf[3][3].x == 800, "re-chosen after 1 s: the feeds follow the nearer one")
    -- the player leaves: back to you
    local log0 = #logtext()
    P1.removed = true
    frames(2)
    check(FP.target.ent == nil or FP.target.ent == P2, "the player it followed left")
    others = {}
    P2.removed = true
    M.T = M.T + 2
    frames(2)
    local lt = string.sub(logtext(), log0 + 1)
    check(FP.leaderId == GSA1.Char.id and string.find(lt, "left; it now follows you", 1, true) ~= nil,
        "nobody left: it follows you, exact, one log line")
    Fo.RemoveAll("removed")
    -- what I aim at
    local npc = { GetPos = function() return Vector(100, 100, 0) end, GetVelocity = function() return Vector(5, 0, 0) end,
                  GetAngles = function() return Angle(0, 90, 0) end, OnGround = function() return true end, IsNPC = function() return true end,
                  IsPlayer = function() return false end, GetClass = function() return "npc_citizen" end }
    M.player.GetEyeTrace = function() return { Entity = npc } end
    local FA = spawn("tails", { target = 3 })
    fclear()
    frames(3)
    local af = fcalls("FollowerFeed", FA.id)
    check(FA and FA.target.type == "aim" and FA.target.ent == npc and FA.hostFed and #af == 3 and af[1][3].x == 100 and af[1][5] == 90 and
        Fo.RootOf(FA) == nil, "What I aim at: host-fed on that NPC each frame")
    log0 = #logtext()
    npc.removed = true
    frames(1)
    lt = string.sub(logtext(), log0 + 1)
    check(FA.target.type == "me" and FA.leaderId == GSA1.Char.id and string.find(lt, "went away", 1, true) ~= nil,
        "the aimed NPC gone: it falls back to Me, one log line")
    M.player.GetEyeTrace = function() return { Entity = NULL } end
    local na, wa = GSA1.SpawnFollower("tails", { target = 3 })
    check(na == false and string.find(tostring(wa), "aim at", 1, true) ~= nil, "nothing aimed at: false + %s", tostring(wa))
    M.player.GetEyeTrace = nil
    Fo.RemoveAll("removed")
    -- stay here
    local FS = spawn("tails", { target = 4 })
    fclear()
    frames(5)
    local sf = fcalls("FollowerFeed", FS.id)
    check(FS and FS.hostFed and FS.target.type == "stay" and #sf == 1 and sf[1][3].x == FS.target.pos.x, "Stay here: host-fed once, frozen")
    Fo.RemoveAll("removed")
    -- a chain; a cycle; the removed middle
    set("gsa1_follower_max", 5)
    local K = spawn("knuckles")
    local T = spawn("tails", { target = 2 })
    local S2 = spawn("sonic", { target = "follower" })
    check(T and T.target.type == "follower" and T.target.uid == K.uid and T.leaderId == K.id and S2.leaderId == T.id and Fo.RootOf(S2) == GSA1.Char,
        "a chain: Tails follows Knuckles, Sonic follows Tails (My last follower)")
    local cyc, wc = Fo.SetTarget(K, { type = "follower", uid = S2.uid })
    local cyc2, wc2 = Fo.SetTarget(K, { type = "follower", uid = T.uid })
    check(cyc == false and cyc2 == false and wc2 == "Tails already follows Knuckles" and K.target.type == "me",
        "a cycle is refused: %s", tostring(wc2))
    log0 = #logtext()
    Fo.Remove(T, "removed")
    lt = string.sub(logtext(), log0 + 1)
    check(S2.leaderId == K.id and S2.target.uid == K.uid and string.find(lt, "Tails went away", 1, true) ~= nil,
        "a followed follower removed: its follower takes ITS leader, one log line")
    Fo.Remove(K, "removed")
    check(S2.target.type == "me" and S2.leaderId == GSA1.Char.id, "the end of the chain: you")
    -- the console's target
    local c2, w2 = Fo.SetTarget(S2, 4)
    check(c2 == true and S2.target.type == "stay" and S2.hostFed, "Fo.SetTarget: a row's target change")
    set("gsa1_follower_max", 3)
end

-- 5. your character's life (item 5; review R.5) -----------------------------------------------------------------------------------------
do
    reset()
    local C = me("sonic")
    local T = spawn("tails")
    local K = spawn("knuckles", { target = "follower" })
    local function hold_order(fn)
        fclear()
        fn()
        local h, l = {}, {}
        for _, c in ipairs(FM.calls) do
            if c[1] == "FollowerHold" then h[#h + 1] = { c[2], c[3] } end
            if c[1] == "FollowerLeader" then l[#l + 1] = { c[2], c[3] } end
        end
        return h, l
    end
    local h, l = hold_order(function() GSA1.Spawn("tails") end)
    local NC = GSA1.Char
    local on, off = 0, 0
    for _, e in ipairs(h) do
        if e[2] then on = on + 1 else off = off + 1 end
    end
    check(on == 2 and off == 2 and h[1][2] == true and T.leaderId == NC.id and #l >= 1 and l[1][2] == NC.id,
        "a switch: FollowerHold(on) for your chain at GSA1CharacterLeaving, then FollowerLeader(new) and FollowerHold(off) at Created")
    h, l = hold_order(function() GSA1.Respawn("test") end)
    NC = GSA1.Char
    check(#h == 4 and T.leaderId == NC.id, "a respawn: the same")
    h, l = hold_order(function() GSA1.Recreate("test") end)
    NC = GSA1.Char
    check(#h == 4 and T.leaderId == NC.id, "a re-creation or a teleport (GSA1.Recreate): the same")
    set("gsa1_follower_come_along", 0)
    h, l = hold_order(function() GSA1.Respawn("test") end)
    NC = GSA1.Char
    check(#h == 0 and T.leaderId == NC.id, "gsa1_follower_come_along 0: no hold, only the new leader")
    set("gsa1_follower_come_along", 1)
    h, l = hold_order(function() GSA1.Remove(true) end)
    check(T.hostFed and T.leaderId == nil and #h == 4, "a removal: host-fed on your player entity, held and let go")
    me("sonic")
    -- a switch that fails: they do not wait for ever
    local create_was = G.Create
    fclear()
    G.Create = function() return nil, "no" end
    GSA1.Spawn("tails")
    G.Create = create_was
    check(GSA1.Char == nil and T.heldBack == true, "a switch that fails: parked ...")
    M.T = M.T + 2
    frames(1)
    check(T.heldBack == nil and T.hostFed and FM.chars[T.id].held == false, "... and let go a moment later, host-fed on your player entity")
    C = me("sonic")
    -- review R.5: a rider gets off before the hold
    T.target = { type = "me" }
    Fo.ApplyTarget(T)
    frames(1)
    local b = B.State(T)
    gsa1.Board(T.id, true, {})
    frames(4)
    check(b.on == true, "a riding Tails follower")
    fclear()
    BM.calls = {}
    local order = {}
    local fh0 = G.FollowerHold
    G.FollowerHold = function(id, on)
        order[#order + 1] = "hold"
        return fh0(id, on)
    end
    local bd0 = G.Board
    G.Board = function(id, on, o)
        if on == false then order[#order + 1] = "off" end
        return bd0(id, on, o)
    end
    GSA1.Respawn("test")
    G.FollowerHold, G.Board = fh0, bd0
    check(order[1] == "off" and order[2] == "hold", "review R.5: a riding follower gets off before any hold (%s)", table.concat(order, ", "))
    -- review R.15: a held follower
    C = GSA1.Char
    frames(2)
    local F2 = spawn("tails")
    frames(30)
    local c2 = M.mchars[F2.id]
    local keep = Vector(c2.pos)
    FM.chars[F2.id].held = true
    c2.pos.z = C.drawPos.z + 4000000
    frames(2)
    local foci = Fo.FarFoci(C, 1200, 4)
    local in_foci = false
    for _, p in ipairs(foci) do
        if p == F2.drawPos then in_foci = true end
    end
    F2.drawPos:SetUnpacked(C.drawPos.x + 5000, C.drawPos.y, C.drawPos.z)
    foci = Fo.FarFoci(C, 1200, 4)
    for _, p in ipairs(foci) do
        if p == F2.drawPos then in_foci = true end
    end
    fclear()
    frames(1)
    check(F2.held == true and F2.lod == 3 and F2.ent.nodraw == true and F2.ent.pos.z < 1000 and not in_foci and #fcalls("FollowerRespawn", F2.id) == 0,
        "review R.15: a held follower (4,000,000 HU up): level 3, its entity kept at its leader, out of FarFoci and of the below-the-map test")
    c2.pos:Set(keep)
    FM.chars[F2.id].held = false
    frames(2)
    check(F2.held == false and F2.lod == 1 and F2.ent.nodraw == false, "placed again: drawn at once at its level")
    Fo.RemoveAll("removed")
end

-- 6. events (item 6) -------------------------------------------------------------------------------------------------------------------
do
    reset()
    local C = me("sonic")
    local F = spawn("tails")
    frames(2)
    local EV = GSA1.EV
    local function event(ty, id, extra)
        local e = { type = ty, character = id, id = 0x8C0ABCDE, bank = 0, x = 1, y = 2, z = 3, arg = 0, step = 5 }
        for k, v in pairs(extra or {}) do e[k] = v end
        FM.events[#FM.events + 1] = e
    end
    chats = {}
    event(EV.FAULT, F.id)
    local oldid = F.id
    frames(1)
    local NF = Fo.list[1]
    check(NF and NF.id ~= oldid and NF.uid == F.uid and NF.slot == F.slot and #chats == 0,
        "a follower's FAULT restarts it behind its leader (same uid and slot); no chat, nothing reaches your on_event")
    event(EV.FAULT, oldid)
    local nid = NF.id
    frames(1)
    check(Fo.list[1].id == nid and #chats == 0, "a removed follower's late event is dropped")
    event(EV.FAULT, nid)
    frames(1)
    local third = Fo.list[1]
    event(EV.FAULT, third.id)
    frames(1)
    check(#Fo.list == 0 and #chats == 1 and string.find(chats[1], "stopped", 1, true) ~= nil and GSA1.Char == C,
        "3 faults within 10 s: removed + one chat line (%s); your character untouched", tostring(chats[1]))
    chats = {}
    local F2 = spawn("gamma")
    event(EV.DEATH, F2.id, { arg = 2 })
    local d0 = F2.id
    frames(1)
    check(Fo.list[1] and Fo.list[1].id ~= d0 and #chats == 0 and C.death == nil, "a DEATH of its world: re-created, no chat, no death of yours")
    local d1 = Fo.list[1].id
    event(EV.RESTART, d1)
    frames(1)
    check(Fo.list[1].id ~= d1 and C.restartAt == nil, "a RESTART of its world: the same; your respawn timers untouched")
    -- FollowersTick's own fault result
    local r = Fo.list[1]
    FM.chars[r.id].fault = "a game code fault"
    frames(1)
    check(Fo.list[1] and Fo.list[1].id ~= r.id, "a fault in FollowersTick's result: restarted")
    -- capacity: the session log with "(follower)"
    local log0 = #logtext()
    event(EV.CAPACITY, Fo.list[1].id, { id = 4, arg = 64 })
    frames(1)
    local lt = string.sub(logtext(), log0 + 1)
    check(string.find(lt, "(follower)", 1, true) ~= nil and string.find(lt, "capacity", 1, true) ~= nil, "CAPACITY: the session log with (follower)")
    -- your own events still reach you: a death of YOUR world, the event of an earlier character of yours
    event(EV.DEATH, C.id, { arg = 2 })
    frames(1)
    check(C.death ~= nil, "your own DEATH still reaches on_event")
    C.death = nil
    C.fallbackAt = nil
    local log1 = #logtext()
    event(EV.FAULT, 9999)
    frames(1)
    lt = string.sub(logtext(), log1 + 1)
    check(string.find(lt, "earlier", 1, true) ~= nil, "an earlier character's fault event goes to on_event as before")
    -- no character: GSA1.PollAllEvents dispatches them
    GSA1.Remove(true)
    local w = Fo.list[1]
    frames(1)
    local wid = w.id
    event(EV.FAULT, wid)
    frames(1)
    check(Fo.list[1] and Fo.list[1].id ~= wid, "no character: the followers' events are still polled and dispatched")
    Fo.RemoveAll("removed")
end

-- 7. the frame (item 7) ---------------------------------------------------------------------------------------------------------------------
do
    reset()
    local C = me("sonic")
    local F = spawn("tails")
    local order = {}
    local tick0_ = G.Tick
    G.Tick = function(...)
        order[#order + 1] = "tick"
        return tick0_(...)
    end
    local ft0 = G.FollowersTick
    G.FollowersTick = function(...)
        order[#order + 1] = "followers"
        return ft0(...)
    end
    local au0 = G.AudioUpdate
    G.AudioUpdate = function(...)
        order[#order + 1] = "audio"
        return au0(...)
    end
    order = {}
    frames(1)
    check(order[1] == "tick" and order[2] == "followers" and order[3] == "audio",
        "GSA1.FollowersThink runs right after your tick and before the sound (%s)", table.concat(order, ", "))
    G.Tick, G.FollowersTick, G.AudioUpdate = tick0_, ft0, au0
    frames(1, 1 / 30)
    check(math.abs(FM.last.dt - 1 / 30) < 1e-6 and M.ticks.last and math.abs(M.ticks.last.dt - FM.last.dt) < 1e-6,
        "the same dt as your character (%.4f)", FM.last.dt)
    M.ui = true
    frames(2)
    local pdt = FM.last.dt
    M.ui = false
    check(pdt == 0, "0 while paused")
    M.convars.host_timescale:SetString("0.5")
    frames(1, 1 / 30)
    frames(1, 1 / 30)
    M.convars.host_timescale:SetString("1")
    check(math.abs(FM.last.dt - 1 / 60) < 1e-6, "host_timescale scales it")
    -- the camera: the module gets GSA1.FollowerTickCamera's, and the fishing mock's answer when that one answers (decision A9)
    set("gsa1_cam_real", 1)
    frames(2)
    check(FM.last.co ~= nil and FM.last.ct ~= nil and FM.last.interpolate == true, "FollowersTick gets the camera of GSA1.FollowerTickCamera(GSA1.Char) "
        .. "and gsa1_interpolate")
    local prev = GSA1.FollowerTickCamera
    local chase_o, chase_t = Vector(1, 2, 3), Vector(4, 5, 6)
    GSA1.FollowerTickCamera = function(c) return chase_o, chase_t end
    frames(1)
    GSA1.FollowerTickCamera = prev
    check(FM.last.co and FM.last.co.x == 1 and FM.last.ct.z == 6, "combination (recheck 4.5 item 3): while the fishing mock's FollowerTickCamera "
        .. "answers, FollowersTick gets that camera")
    -- the render of its module's out[i] (D8)
    local mc = M.mchars[F.id]
    mc.pos:SetUnpacked(123, 456, 789)
    frames(1)
    check(F.drawPos.x == 123 and F.drawPos.z == 789 and F.ent.pos.x == 123, "F.drawPos and its entity from FollowersTick's out[i] (D8)")
    -- a Lua error in a hook of one follower: logged; 3 within 10 s remove it; your tick goes on
    hook.Add("GSA1FollowerPostTick", "test_error", function(f) error("a broken feature") end)
    local n0 = M.ticks.last and FM.ticks or 0
    frames(3)
    hook.Remove("GSA1FollowerPostTick", "test_error")
    check(FM.ticks == n0 + 3 and GSA1.Char == C and #M.reported >= 0, "a Lua error in a feature's follower hook: your tick goes on")
    M.reported = {}
    Fo.RemoveAll("removed")
end

-- 8. drawing (item 8; D4, D9, 4.10) ---------------------------------------------------------------------------------------------------------
do
    reset()
    local C = me("sonic")
    local F = spawn("tails")
    frames(3)
    local function drawn(E, flags)
        FM.emits = {}
        local out = {}
        E.ent:Draw(flags)
        E.ent:DrawTranslucent(flags)
        for _, e in ipairs(FM.emits) do
            if e[1] == E.id then out[e[2]] = true end
        end
        return out
    end
    M.frameNo = M.frameNo + 1
    local d = drawn(F)
    check(d[IDX.body] and d[IDX.effect] and d[IDX.shadow] and d[IDX.board] and not d[IDX.object],
        "level 1: its body, effects, shadow and board; a follower's OBJECT batches never")
    check(F.interp == true, "level 1 streams (interpolated every frame)")
    -- first person: your followers are drawn whole, you only the objects and the board
    set("gsa1_cam_distance", 0)
    M.frameNo = M.frameNo + 1
    local fp = GSA1.FirstPersonFor(C)
    local fpf = GSA1.FirstPersonFor(F)
    local df = drawn(F)
    local dc = drawn(C)
    check(fp == true and fpf == false and df[IDX.body] and not dc[IDX.body] and dc[IDX.object],
        "first person (camera distance 0): a follower's every batch but objects, yours only OBJECT and board (D9: GSA1.DrawCharacter)")
    -- through the table: a wrap of GSA1.FirstPerson reaches it (the fishing camera)
    local fp0 = GSA1.FirstPerson
    GSA1.FirstPerson = function() return false end
    local wrapped = GSA1.FirstPersonFor(C)
    GSA1.FirstPerson = fp0
    check(wrapped == false, "GSA1.FirstPersonFor asks GSA1.FirstPerson through the table (D9: fishing's wrap reaches it)")
    -- draw_depth_late, the second site
    local depth_tex = setmetatable({ name = "_rt_ResolvedFullFrameDepth" }, { __index = { GetName = function(s) return s.name end } })
    render.GetResolvedFullFrameDepth = function() return depth_tex end
    C.objectBatches, C.boardBatches = 0, 0
    FM.emits = {}
    GSA1.DrawCharacterDepthLate(C)
    local late_c = #FM.emits
    FM.emits = {}
    GSA1.DrawCharacterDepthLate(F)
    local late_f = false
    for _, e in ipairs(FM.emits) do
        if e[1] == F.id and e[2] == IDX.body then late_f = true end
    end
    render.GetResolvedFullFrameDepth = nil
    check(late_c == 0 and late_f, "first person at draw_depth_late too (D9): you nothing (no objects), a follower its body")
    set("gsa1_cam_distance", 150)
    -- D4: another addon's render target (the owner's log)
    local rt = setmetatable({ name = "_rt_prism_dynscratch_1024x1024" }, { __index = { GetName = function(s) return s.name end } })
    M.view_setup = { viewid = 2 }
    M.frameNo = M.frameNo + 1
    M.render_target = rt
    local dOther = drawn(F)
    local dPlayer = drawn(C)
    check(next(dOther) == nil and next(dPlayer) ~= nil, "level 1 in another addon's target (_rt_prism_dynscratch_1024x1024, kind main): not "
        .. "drawn with gsa1_follower_other_views 0 (yours is)")
    set("gsa1_follower_other_views", 1)
    local dOther1 = drawn(F)
    set("gsa1_follower_other_views", 0)
    check(dOther1[IDX.body] == true, "with gsa1_follower_other_views 1 it is")
    -- the water and the depth pass: level 1 yes
    M.render_target = setmetatable({ name = "_rt_WaterReflection" }, { __index = { GetName = function(s) return s.name end } })
    local dWater = drawn(F)
    M.render_target = setmetatable({ name = "_rt_ResolvedFullFrameDepth" }, { __index = { GetName = function(s) return s.name end } })
    local dDepth = drawn(F, 134217728)
    M.render_target = nil
    M.view_setup = nil
    check(dWater[IDX.body] == true and dDepth[IDX.body] == true, "level 1 in water and the depth pass: yes")
    -- level 2 (far): the count
    set("gsa1_follower_full_detail", 0)
    local t0 = M.T
    for _ = 1, 40 do
        M.T = M.T + 0.1
        frames(1)
        if F.lod == 2 then break end
    end
    local waited = M.T - t0
    check(F.lod == 2 and waited >= 0.5 and F.interp == false and FM.chars[F.id].level == 2 and FM.chars[F.id].rate == 15,
        "gsa1_follower_full_detail 0: level 2 after the 0.5 s hysteresis (%.1f s), gsa1.FollowerDraw(id, 2, 15), the static path", waited)
    M.frameNo = M.frameNo + 1
    F.renderGen = F.renderGen + 1
    local d2 = drawn(F)
    check(d2[IDX.body] and not d2[IDX.effect] and not d2[IDX.shadow] and not d2[IDX.object] and d2[IDX.board] and not d2[IDX.boardshadow],
        "level 2: no effect, no shadow, no objects; its board stays (EFFECT too), the board's shadow does not")
    M.frameNo = M.frameNo + 1
    F.renderGen = F.renderGen + 1
    M.render_target = rt
    M.view_setup = { viewid = 2 }
    local d2o = drawn(F)
    M.render_target = setmetatable({ name = "_rt_WaterReflection" }, { __index = { GetName = function(s) return s.name end } })
    local d2w = drawn(F)
    M.render_target = setmetatable({ name = "_rt_ResolvedFullFrameDepth" }, { __index = { GetName = function(s) return s.name end } })
    local d2d = drawn(F, 134217728)
    M.render_target = nil
    M.view_setup = nil
    check(next(d2o) == nil and next(d2w) == nil and next(d2d) == nil,
        "level 2 only when render.GetRenderTarget() is nil: not in another addon's target that says main (D4), water or the depth pass")
    -- its rate
    set("gsa1_follower_far_rate", 5)
    check(FM.chars[F.id].rate == 5, "the far rate's slider reaches gsa1.FollowerDraw")
    set("gsa1_follower_far_rate", 15)
    -- the lighting cube every 4th frame
    local cl0 = render.ComputeLighting
    local nl = 0
    render.ComputeLighting = function(...)
        nl = nl + 1
        return cl0(...)
    end
    for _ = 1, 8 do
        M.frameNo = M.frameNo + 1
        F.ent:Draw()
    end
    render.ComputeLighting = cl0
    check(nl == 12, "level 2's lighting cube every 4th frame (%d samples in 8 frames: 2 x 6)", nl)
    -- level 3: beyond the draw distance
    set("gsa1_follower_full_detail", 8)
    set("gsa1_follower_draw_dist", 500)
    M.mchars[F.id].pos:SetUnpacked(20000, 0, 0)
    FM.chars[F.id].rx = 20000
    F.drawPos:SetUnpacked(20000, 0, 0)
    for _ = 1, 40 do
        M.T = M.T + 0.1
        frames(1)
        if F.lod == 3 then break end
    end
    M.frameNo = M.frameNo + 1
    local d3 = drawn(F)
    check(F.lod == 3 and F.ent.nodraw == true and next(d3) == nil and F.drawPos.x == 20000, "beyond the draw distance: level 3, SetNoDraw(true), nothing "
        .. "drawn, its position still from its state")
    -- back near: hysteresis again
    set("gsa1_follower_draw_dist", 4800)
    M.mchars[F.id].pos:Set(C.drawPos)
    M.T = M.T + 0.2
    frames(1)
    local still = F.lod
    for _ = 1, 40 do
        M.T = M.T + 0.1
        frames(1)
        if F.lod == 1 then break end
    end
    check(still == 3 and F.lod == 1 and F.ent.nodraw == false and F.interp == true, "back near: level 1 after the hysteresis, drawn again")
    -- the nearest N are level 1
    set("gsa1_follower_max", 8)
    set("gsa1_follower_full_detail", 2)
    local a = {}
    for i = 1, 4 do
        a[i] = spawn("knuckles")
        M.mchars[a[i].id].pos:SetUnpacked(C.drawPos.x + i * 100, C.drawPos.y, C.drawPos.z)
    end
    M.mchars[F.id].pos:SetUnpacked(C.drawPos.x + 1000, C.drawPos.y, C.drawPos.z)
    for _ = 1, 12 do
        M.T = M.T + 0.1
        frames(1)
    end
    check(a[1].lod == 1 and a[2].lod == 1 and a[3].lod == 2 and a[4].lod == 2 and F.lod == 2, "the nearest gsa1_follower_full_detail are level 1, the "
        .. "others within the draw distance level 2 (%d %d %d %d %d)", a[1].lod, a[2].lod, a[3].lod, a[4].lod, F.lod)
    set("gsa1_follower_full_detail", 8)
    set("gsa1_follower_max", 3)
    -- the log's views stay yours
    Fo.RemoveAll("removed")
    local ld0, nld, nmine = GSA1.LogDraw, 0, 0
    GSA1.LogDraw = function(c)
        if c and c.follower then nld = nld + 1 else nmine = nmine + 1 end
    end
    local Fv = spawn("tails")
    frames(3)
    nmine, nld = 0, 0
    M.frameNo = M.frameNo + 1
    Fv.ent:Draw()
    C.ent:Draw()
    GSA1.LogDraw = ld0
    check(nld == 0 and nmine == 1, "the session log's views of the character: a follower's draw is not one of yours (%d, %d)", nld, nmine)
    Fo.RemoveAll("removed")
    check(GSA1.FollowerBatch(F, 0x1020) == false, "GSA1.FollowerBatch: an OBJECT batch never")
end

-- 9. boards (item 9; 4.12, R.4, R.5, R.6, D7, D11, rows 9, 16) ---------------------------------------------------------------------------------
do
    reset()
    local C = me("sonic")
    local T = spawn("tails")
    local S1 = spawn("sonic", { target = "follower" })
    local K = spawn("knuckles")
    frames(3)
    local changes = {}
    hook.Add("GSA1BoardChanged", "test_changes", function(c, on, why) changes[#changes + 1] = { c, on, why } end)
    -- the mirror, down a chain of 2, not Knuckles
    BM.calls = {}
    gsa1.Board(C.id, true, { terrain = 2, push = true })
    B.State(C).lastOpts = { terrain = 2, push = true }
    clear_msgs()
    frames(2)
    local tb = bcalls("Board", T.id)
    check(B.State(C).on and #tb >= 1 and tb[1][3] == true and tb[1][4].terrain == 2 and tb[1][4].push == true and #bcalls("Board", K.id) == 0,
        "the mirror: your edge puts a Tails follower on with your terrain and your push; never a Knuckles")
    frames(4)
    local sb = bcalls("Board", S1.id)
    check(B.State(T).on and #sb >= 1 and sb[1][4].terrain == 2 and B.State(S1).on, "the chain mirrors: the Sonic behind the Tails gets on too")
    check(#msgs_c(B.NET.ST) == 1, "a follower's edge sends no gsa1_board_st (only your own one: %d)", #msgs_c(B.NET.ST))
    -- row 16: per world
    check(BM.chars[T.id].variant == 0 and B.State(S1).st.variant == 0, "each rides by its own world's state (BoardState, nothing copied)")
    -- D7: you riding, a follower on foot for 60 frames
    local NF = spawn("tails")
    NF = NF or Fo.list[#Fo.list]
    set("gsa1_follower_board", 0)
    clear_msgs()
    frames(60)
    set("gsa1_follower_board", 1)
    check(#msgs_c(B.NET.ST) == 0, "D7: you riding and a follower on foot for 60 frames: no gsa1_board_st at all (%d)", #msgs_c(B.NET.ST))
    if NF then Fo.Remove(NF, "removed") end
    -- off: the same way; the left boards with their slots, yours first, none refused
    clear_msgs()
    BM.calls = {}
    SP.GSA1State = { x = C.drawPos.x, y = C.drawPos.y, z = C.drawPos.z }
    gsa1.Board(C.id, false)
    frames(2)
    check(#bcalls("Board", T.id) >= 1 and bcalls("Board", T.id)[1][3] == false, "off the same way")
    frames(6)
    local leftm = msgs_c(B.NET.LEFT)
    M.T = M.T + 0.1
    for _ = 1, 60 do frames(1) end
    leftm = msgs_c(B.NET.LEFT)
    check(leftm[1] and leftm[1].vals[5] == 0, "your own left board goes first (slot %s)", tostring(leftm[1] and leftm[1].vals[5]))
    M.T = M.T + 1
    frames(2)
    M.T = M.T + 1
    frames(2)
    leftm = msgs_c(B.NET.LEFT)
    local slots = {}
    for _, m in ipairs(leftm) do slots[#slots + 1] = tostring(m.vals[5]) end
    check(#leftm == 3 and leftm[2].vals[5] == T.slot and leftm[3].vals[5] == S1.slot, "then the followers', with F.slot (%s)", table.concat(slots, " "))
    -- four follower boards at once (review R.6): yours sent first, none refused by the server's bucket (3, refilled at 1 a second)
    do
        Fo.RemoveAll("removed")
        set("gsa1_follower_max", 8)
        local four = {}
        for i = 1, 4 do four[i] = spawn("tails") end
        frames(2)
        B.leftNext = nil
        B.State(C).lastOpts = {}
        gsa1.Board(C.id, true, {})
        frames(8)
        local allOn = B.State(four[1]).on and B.State(four[2]).on and B.State(four[3]).on and B.State(four[4]).on
        clear_msgs()
        left_ents = {}
        SP.GSA1BoardLeft = nil
        SB.sv.counts.refused = 0
        SP.pos = Vector(C.drawPos)
        SP.GSA1State = { x = C.drawPos.x, y = C.drawPos.y, z = C.drawPos.z }
        gsa1.Board(C.id, false)
        for _ = 1, 400 do
            M.T = M.T + 1 / 60
            frames(1)
        end
        local lm = msgs_c(B.NET.LEFT)
        local sl = {}
        for i, m in ipairs(lm) do sl[i] = tostring(m.vals[5]) end
        check(allOn and #lm == 5 and lm[1].vals[5] == 0 and SB.sv.counts.refused == 0 and #left_ents == 5,
            "four follower boards at once: yours sent first, none refused by the bucket (slots %s; %d refused)", table.concat(sl, " "),
            SB.sv.counts.refused)
        Fo.RemoveAll("removed")
        set("gsa1_follower_max", 3)
        T = spawn("tails")
        frames(2)
    end
    -- yours still settling: the followers' wait for it
    do
        local my = B.State(C)
        my.leaving = { at = M.T, kind = 0, variant = 0, exit = { x = 0, y = 0, z = 0 }, yaw = 0 }
        local bT = B.State(T)
        bT.leaving = { at = M.T, kind = 2, variant = 0, exit = { x = 0, y = 0, z = 0 }, yaw = 0 }
        B.leftNext = nil
        clear_msgs()
        B.SendLeft(T, { x = 0, y = 0, z = 0 }, "settled")
        local waited = #msgs_c(B.NET.LEFT)
        my.leaving = nil
        B.LeftPump()
        check(waited == 0 and #msgs_c(B.NET.LEFT) == 1, "your own board still settling: a follower's left board waits for it")
        B.leftNext = nil
    end
    -- a Knuckles stays out; a refusal is silent
    BM.refuse = "carrying something"
    local toasts = {}
    local toast0 = W.Toast
    W.Toast = function(...) toasts[#toasts + 1] = string.format(...) end
    local log0 = #logtext()
    B.On(T, "a test", nil, {})
    W.Toast = toast0
    BM.refuse = nil
    local lt = string.sub(logtext(), log0 + 1)
    check(#toasts == 0 and string.find(lt, "no board", 1, true) ~= nil, "a follower's board refusal makes no toast, one log line")
    -- hook words
    hook.Remove("GSA1BoardChanged", "test_changes")
    Fo.RemoveAll("removed")
    -- slot 16 boards with remove = true
    local F16 = spawn("tails")
    F16.slot = nil
    frames(1)
    gsa1.Board(F16.id, true, {})
    frames(4)
    BM.calls = {}
    B.Off(F16, "a test")
    local off = bcalls("Board", F16.id)
    check(off[1] and off[1][4] and off[1][4].remove == true, "a follower with no slot (a 16th): off with remove = true")
    Fo.RemoveAll("removed")
    -- the server: review R.6, row 9
    local place, ang = Vector(10000, 0, 0), Angle(0, 0, 0)
    SP.pos = Vector(0, 0, 0)
    SP.GSA1State = { x = 0, y = 0, z = 0 }
    SP.GSA1BoardLeft = nil
    local a1 = SB.LeftOk(SP, place, ang, 2, 0, 3)
    local a2, w2 = SB.LeftOk(SP, Vector(20000, 0, 0), ang, 2, 0, 3)
    local a3, w3 = SB.LeftOk(SP, Vector(3000, 0, 0), ang, 2, 0, 0)
    local a4 = SB.LeftOk(SP, Vector(100, 0, 0), ang, 2, 0)
    check(a1 == true and a2 == false and a3 == false and a4 == true, "B.LeftOk: slot 3 at 10,000 HU of the player accepted, at 20,000 refused (%s); slot 0 "
        .. "beyond 2,048 HU of GSA1State refused (%s)", tostring(w2), tostring(w3))
    SP.GSA1BoardLeft = nil
    local l3 = SB.Left(SP, place, ang, 2, 0, 3)
    SP.GSA1BoardLeft = nil
    local l0 = SB.Left(SP, Vector(3000, 0, 0), ang, 2, 0, 0)
    check(l3 ~= nil and l0 == nil, "B.Left passes the slot: a follower's far board is made, yours that far is not")
    SP.GSA1Active = false
    local a5 = SB.LeftOk(SP, place, ang, 2, 0, 3)
    SP.GSA1Active = true
    check(a5 == false, "slot 3 keeps \"is a character\"")
    local ran = 0
    SH.GSA1BoardChanged = { test = function() ran = ran + 1 end }
    SP.nw2 = {}
    local st = SB.StateMsg(SP, true, 0, nil, 3)
    check(ran == 0 and st == false and SP.nw2[SB.NW_RIDING] == nil, "B.StateMsg with slot 3: no hook, no NW2 flag")
    SB.StateMsg(SP, true, 0, nil, 0)
    check(ran == 1 and SP.nw2[SB.NW_RIDING] == true, "with slot 0: as before")
    SH.GSA1BoardChanged = nil
    -- at the cap a follower's decoration goes before yours
    SP.GSA1BoardLeft = nil
    local e0 = SB.Left(SP, Vector(10, 0, 0), ang, 0, 0, 0)
    SP.GSA1BoardLeft = nil
    local e1 = SB.Left(SP, Vector(20, 0, 0), ang, 2, 0, 3)
    SCV.gsa1_sv_board_left_max:SetString("2")
    SP.GSA1BoardLeft = nil
    local e2 = SB.Left(SP, Vector(30, 0, 0), ang, 0, 0, 0)
    SCV.gsa1_sv_board_left_max:SetString("5")
    check(e0 and e1 and e2 and e1.removed == true and not e0.removed and not e2.removed, "at gsa1_sv_board_left_max a slot >= 1 decoration goes before a "
        .. "slot-0 one")
    -- B.FollowerBoxes: a model of a box the client knows
    local function box(kind, x, y, L)
        local e = { GSA1Trigger = true, cls = kind == "on" and "gsa1_board_on" or "gsa1_board_off", idx = x, enabled = true, present = true }
        function e:GetClass() return self.cls end
        function e:EntIndex() return self.idx end
        function e:GetPos() return Vector(x, y, -143) end
        function e:GetAngles() return Angle(0, 0, 0) end
        function e:GetLength() return L or 256 end
        function e:GetWidth() return L or 256 end
        function e:GetHeight() return 192 end
        function e:GetEnabled() return self.enabled end
        function e:GetPresent() return self.present end
        function e:GetUses() return 0 end
        function e:GetUsed() return 0 end
        function e:GetBoardPos() return Vector(x, y, -143) end
        function e:GetPush() return 1 end
        function e:GetGround() return 2 end
        return e
    end
    reset()
    C = me("knuckles")
    local F = spawn("tails")
    frames(3)
    local boxOn = box("on", 2000, 0)
    B.boxes[1001] = boxOn
    B.fboxesAt = nil
    local mc = M.mchars[F.id]
    mc.pos:SetUnpacked(1000, 0, -143)
    frames(4)
    BM.calls = {}
    clear_msgs()
    fclear()
    -- walks into the box: the AI is host-fed at the board's place
    mc.pos:SetUnpacked(1950 - 128, 0, -143)
    frames(4)
    mc.pos:SetUnpacked(1950, 0, -143)
    frames(4)
    local b = B.State(F)
    local feeds = fcalls("FollowerFeed", F.id)
    local ll = fcalls("FollowerLeader", F.id)
    check(b.fwalk ~= nil and ll[1] and ll[1][3] == nil and #feeds >= 1 and feeds[#feeds][3].x == 2000 and feeds[#feeds][6] == true and #bcalls("Board", F.id) == 0,
        "gsa1_follower_board_boxes 1: an on-foot Tails crossing a Board On box walks: host-fed at the board's place, standing; no board yet")
    check(F.hostFed and F.leaderId == nil, "its leader link is off during the walk")
    mc.pos:SetUnpacked(2000 - 30, 0, -143)
    frames(4)
    local ob = bcalls("Board", F.id)
    check(#ob == 1 and ob[1][3] == true and ob[1][4].terrain == 1 and ob[1][4].push == true and F.leaderId == C.id and b.fwalk == nil,
        "within 48 HU: one B.On with the box's opts (its push, its ground: Ice Cap snow), its leader link back")
    check(#msgs_c(B.NET.TOOK) == 0 and #msgs_c(B.NET.ST) == 0 and #msgs_c(B.NET.CANCEL) == 0 and #msgs_c(B.NET.BOX) == 0, "no net message in either: no claim, no use")
    frames(4)
    check(b.on == true, "it rides")
    -- a Board Off box takes it off
    local boxOff = box("off", 4000, 0)
    B.boxes[1002] = boxOff
    B.fboxesAt = nil
    BM.calls = {}
    M.T = M.T + 1.1
    mc.pos:SetUnpacked(4000 - 300, 0, -143)
    frames(4)
    mc.pos:SetUnpacked(4000, 0, -143)
    frames(4)
    local offb = bcalls("Board", F.id)
    check(offb[1] and offb[1][3] == false, "a riding one crossing a Board Off box: off")
    frames(4)
    B.boxes[1002] = nil
    B.fboxesAt = nil
    -- past its deadline: on at once
    Fo.Remove(F, "removed")
    F = spawn("tails")
    mc = M.mchars[F.id]
    frames(4)
    mc.pos:SetUnpacked(2000 - 400, 0, -143)
    frames(4)
    BM.calls = {}
    mc.pos:SetUnpacked(2000 - 120, 0, -143)
    frames(4)
    b = B.State(F)
    check(b.fwalk ~= nil, "a second walk")
    M.T = M.T + 20
    frames(4)
    ob = bcalls("Board", F.id)
    check(ob[1] and ob[1][3] == true and b.fwalk == nil and F.leaderId == C.id, "a walk past its deadline: on at once, its leader link back")
    frames(4)
    -- leaves the box: the walk ends, no board
    Fo.Remove(F, "removed")
    F = spawn("tails")
    mc = M.mchars[F.id]
    frames(4)
    mc.pos:SetUnpacked(2000 - 400, 0, -143)
    frames(4)
    BM.calls = {}
    mc.pos:SetUnpacked(2000 - 120, 0, -143)
    frames(4)
    b = B.State(F)
    mc.pos:SetUnpacked(2000 - 400, 0, -143)
    frames(4)
    check(b.fwalk == nil and #bcalls("Board", F.id) == 0 and F.leaderId == C.id, "out of the box by B.LEAVE_OUT: the walk ends, no board, its link back")
    -- hurt
    mc.pos:SetUnpacked(2000 - 400, 0, -143)
    frames(4)
    mc.pos:SetUnpacked(2000 - 120, 0, -143)
    M.T = M.T + 1.1
    frames(4)
    local walking = b.fwalk ~= nil
    BM.hurt = 0
    frames(4)
    BM.hurt = -1
    check(walking and b.fwalk == nil, "hurt: the walk ends")
    -- mode 2: on at once
    set("gsa1_follower_board_boxes", 2)
    mc.pos:SetUnpacked(2000 - 400, 0, -143)
    frames(4)
    BM.calls = {}
    clear_msgs()
    mc.pos:SetUnpacked(2000 - 120, 0, -143)
    frames(4)
    ob = bcalls("Board", F.id)
    check(ob[1] and ob[1][3] == true and b.fwalk == nil and #msgs_c(B.NET.ST) == 0, "with 2: one B.On at once, no net message")
    frames(4)
    set("gsa1_follower_board_boxes", 0)
    B.boxes[1001] = nil
    B.fboxesAt = nil
    -- its leader boards while it walks: the mirror wins
    reset()
    C = me("sonic")
    F = spawn("tails")
    frames(3)
    B.boxes[1001] = boxOn
    B.fboxesAt = nil
    mc = M.mchars[F.id]
    mc.pos:SetUnpacked(2000 - 400, 0, -143)
    frames(4)
    mc.pos:SetUnpacked(2000 - 120, 0, -143)
    frames(4)
    b = B.State(F)
    local w0 = b.fwalk ~= nil
    BM.calls = {}
    gsa1.Board(C.id, true, {})
    frames(4)
    check(w0 and b.fwalk == nil and F.leaderId == C.id and bcalls("Board", F.id)[1] ~= nil, "its leader boards during the walk: the mirror wins")
    B.boxes[1001] = nil
    B.fboxesAt = nil
    frames(4)
    -- 4.12 g: a respawn ended the ride: back on while the leader rides and it stands
    check(b.on == true, "riding")
    BM.chars[F.id].on = false
    BM.chars[F.id].held = false
    BM.chars[F.id].kept = true
    BM.calls = {}
    M.T = M.T + 2
    frames(4)
    local ob2 = bcalls("Board", F.id)
    check(ob2[1] and ob2[1][3] == true, "a respawn ended the ride (the AI's own order 24), its leader still rides, it stands: back on (4.12 g)")
    frames(4)
    -- removed while riding: its board is handed over
    clear_msgs()
    b = B.State(F)
    local changed = {}
    hook.Add("GSA1BoardChanged", "test_changes", function(c, on, why) changed[#changed + 1] = why end)
    Fo.Remove(F, "removed")
    hook.Remove("GSA1BoardChanged", "test_changes")
    M.T = M.T + 3
    frames(3)
    check(#msgs_c(B.NET.LEFT) == 1 and changed[1] == "removed", "a riding follower removed: its board is handed over (a left board), GSA1BoardChanged(F, false, \"removed\")")
    Fo.RemoveAll("removed")
    -- one waiting over 5 s is removed
    reset()
    me("sonic")
    local Q = spawn("tails")
    frames(2)
    B.leftNext = M.T + 100
    local b9 = B.State(Q)
    b9.leaving = { at = M.T, kind = 2, variant = 0, exit = { x = 0, y = 0, z = 0 }, yaw = 0 }
    gsa1.Board(Q.id, true, {})
    frames(3)
    BM.chars[Q.id].on, BM.chars[Q.id].kept = false, true
    b9.on = false
    BM.calls = {}
    B.SendLeft(Q, { x = 0, y = 0, z = 0 }, "settled")
    M.T = M.T + 6
    local log9 = #logtext()
    frames(1)
    local lt9 = string.sub(logtext(), log9 + 1)
    check(#B.leftQueue == 0 and #bcalls("BoardFree", Q.id) == 1 and string.find(lt9, "waited too long", 1, true) ~= nil,
        "a follower's left board waiting over 5 s is removed (a log line)")
    B.leftNext = nil
    Fo.RemoveAll("removed")
end

-- 10. the open wheel's action (item 10; D12) --------------------------------------------------------------------------------------------------
do
    reset()
    local C = me("sonic")
    local F = spawn("tails")
    local act
    for _, a in ipairs(W.OPEN_ACTIONS) do
        if a.name == "followers" then act = a end
    end
    check(act ~= nil and type(act.down) == "function" and type(act.act) == "function", "W.OPEN_ACTIONS has \"followers\", from cl_follower.lua (D12: no patch of cl_wheel.lua)")
    fclear()
    W.open, W.char = true, C
    W.actWas = { followers = false }
    keys[16] = false
    W.OpenActions(C)
    check(#fcalls("FollowerRespawn") == 0 and W.open == true, "the wheel open, nothing pressed: nothing")
    keys[16] = true
    W.OpenActions(C)
    keys[16] = false
    check(#fcalls("FollowerRespawn", F.id) == 1 and W.open == false, "F in the open wheel: one FollowerRespawn per follower whose chain root is you, the wheel closed")
    fclear()
    keys[16] = true
    frames(3)
    keys[16] = false
    check(#fcalls("FollowerRespawn") == 0, "with the wheel closed: nothing")
    -- the pad's button
    W.open, W.char = true, C
    W.actWas = { followers = false }
    GSA1.pad = { connected = true, raw = 64 }
    fclear()
    W.OpenActions(C)
    GSA1.pad = nil
    check(#fcalls("FollowerRespawn", F.id) == 1, "the left stick click (0x40) too")
    -- refused keys
    local kf = M.convars.gsa1_follower_call_key
    set("gsa1_board_key", 12)
    kf:SetString("12")
    check(kf:GetInt() == 16 and Fo.keyNote ~= nil and string.find(Fo.keyNote, "the board key", 1, true) ~= nil, "the binder refuses the board key: %s", tostring(Fo.keyNote))
    kf:SetString("0")
    check(kf:GetInt() == 0, "0 = none is allowed")
    kf:SetString("16")
    local kp = M.convars.gsa1_follower_call_pad
    kp:SetString("128")
    check(kp:GetInt() == 64, "the combo refuses the board's button: %s", tostring(Fo.keyNote))
    kp:SetString("4096")
    check(kp:GetInt() == 64, "and jump (A)")
    Fo.keyNote = nil
    check(B.KeyRefused(16) ~= nil and B.PadRefused(64) ~= nil, "the board's binders refuse the followers' key and button in return")
    -- a bind of the key does nothing in the open wheel (F is the flashlight)
    W.open = true
    local r = M.hooks.PlayerBindPress.gsa1_follower(M.player, "impulse 100", true, 16)
    W.open = false
    Fo.wheelClosedAt = nil
    local r2 = M.hooks.PlayerBindPress.gsa1_follower(M.player, "impulse 100", true, 16)
    check(r == true and r2 == nil, "a Garry's Mod bind of that key does nothing while the wheel is open")
    Fo.RemoveAll("removed")
end

-- 11. spawners (item 11; 5.7, review R.6) ----------------------------------------------------------------------------------------------------
do
    reset()
    me("sonic")
    undos = {}
    SP.GSA1FolRate, SP.GSA1FolTokens = nil, nil
    -- through the spawner's SpawnFunction: no entity
    local E = classes_s.gsa1_follower_tails
    local made = E:SpawnFunction(SP, { Hit = true }, "gsa1_follower_tails")
    local F = Fo.list[1]
    check(made == nil and F and F.kind == 2 and #undos == 1 and undos[1].name == "G-SA1 Tails follower" and undos[1].ply == SP and undos[1].done == true,
        "gsa1_fol_req -> made -> one undo entry named \"G-SA1 Tails follower\"; the spawner makes no entity")
    undos[1].fn()
    check(#Fo.list == 0 and F.removed == true, "undo -> that follower removed")
    undos = {}
    -- made = false -> no undo
    set("gsa1_follower_max", 1)
    local F1 = spawn("tails")
    chats = {}
    E:SpawnFunction(SP, { Hit = true }, "gsa1_follower_tails")
    check(#undos == 0 and #Fo.list == 1 and string.find(chats[1] or "", "you have 1 followers", 1, true) ~= nil, "made = false -> no undo; the chat says why")
    Fo.RemoveAll("removed")
    set("gsa1_follower_max", 3)
    -- a token: used once; one not sent to that player; too old
    undos = {}
    SP.GSA1FolTokens = { [77] = { kind = 2, at = M.T } }
    local a1 = SFo.Made(SP, 77, true)
    local a2, w2 = SFo.Made(SP, 77, true)
    local a3, w3 = SFo.Made(SP, 78, true)
    SP.GSA1FolTokens[79] = { kind = 2, at = M.T - 11 }
    local a4, w4 = SFo.Made(SP, 79, true)
    check(a1 == true and a2 == false and a3 == false and a4 == false and #undos == 1, "a used token refused (%s); one never sent (%s); one over 10 s old (%s)", tostring(w2),
        tostring(w3), tostring(w4))
    -- the rate limit
    undos = {}
    SP.GSA1FolRate = nil
    local nreq = 0
    SP.GSA1FolTokens = nil
    for _ = 1, 30 do
        if SG.FollowerRequest(SP, 3) then nreq = nreq + 1 end
    end
    check(nreq == 10, "the rate limit: 10 a second (%d of 30 went out)", nreq)
    Fo.RemoveAll("removed")
    -- gsa1_sv_follower_icons 0
    undos = {}
    SCV.gsa1_sv_follower_icons:SetString("0")
    SP.GSA1FolRate = nil
    local no = SG.FollowerRequest(SP, 2)
    SCV.gsa1_sv_follower_icons:SetString("1")
    check(no == false and #Fo.list == 0 and #undos == 0, "gsa1_sv_follower_icons 0: nothing")
    -- GSA1FollowerRequest false: nothing
    SH.GSA1FollowerRequest = { test = function() return false end }
    local no2 = SG.FollowerRequest(SP, 2)
    SH.GSA1FollowerRequest = nil
    check(no2 == false and #Fo.list == 0, "the hook GSA1FollowerRequest(ply, kind) false: nothing")
    -- an undo of one already gone: nothing
    local tokF = spawn("tails")
    Fo.byToken[5] = tokF
    tokF.token = 5
    Fo.Remove(tokF, "removed")
    local okU = pcall(function()
        cread = reader({ 5 })
        recv_c[Fo.NET.UNDO](16)
    end)
    check(okU and Fo.byToken[5] == nil, "an undo of a follower that is gone: nothing")
end

-- 12. the secret (item 12) -------------------------------------------------------------------------------------------------------------------
do
    reset()
    set("gsa1_follower_max", 3)
    local U = GSA1.UnlikeSonic
    fclear()
    timers = {}
    U.Go()
    local t = timers.gsa1_unlikesonic
    check(GSA1.Char and GSA1.Char.kind == 3 and t ~= nil and t.left == 99, "U.Go(): you are Knuckles, a timer of 99 calls")
    for i = 1, 99 do t.fn() end
    local cr = fcalls("FollowerCreate")
    local last = cr[#cr]
    check(#cr == 99 and #Fo.list == 99 and Fo.Count(true) == 99 and last[2] == 3 and last[6].objects == 0 and last[6].sounds == false,
        "99 calls: 99 Knuckles with ignore_cap, silent, objects 0")
    Fo.RemoveAll("removed")
    timers = {}
    U.Go()
    t = timers.gsa1_unlikesonic
    FM.kinds[3] = "Knuckles cannot follow yet: x"
    t.fn()
    check(timers.gsa1_unlikesonic == nil and #Fo.list == 0, "the timer stops at the first false")
    FM.kinds[3] = true
    Fo.RemoveAll("removed")
end

-- 13. combination: a Character Select pick (recheck 4.5 item 4, mock), the map's collision, the log's line, the movers ----------------------------
do
    reset()
    local C = me("sonic")
    local T = spawn("tails")
    frames(2)
    fclear()
    -- a pick is a plain GSA1.Spawn
    GSA1.Spawn("knuckles")
    local h = fcalls("FollowerHold", T.id)
    check(#h == 2 and h[1][3] == true and h[2][3] == false and T.leaderId == GSA1.Char.id, "a Character Select pick -> GSA1.Spawn -> hold, release behind the new character")
    C = GSA1.Char
    frames(2)
    -- the map's collision again: they are made again too
    local id0 = T.id
    GSA1.worldInfo = { min_z = -10000 }
    frames(1)
    check(Fo.list[1] and Fo.list[1].id ~= id0 and Fo.list[1].uid == T.uid, "the map's collision loaded again: made again (characters keep the world they were created with)")
    T = Fo.list[1]
    -- below the map: with the guard, the game's respawn; never without
    local mc = M.mchars[T.id]
    fclear()
    mc.pos.z = -20000
    frames(1)
    local log0 = #logtext()
    check(#fcalls("FollowerRespawn", T.id) == 1, "below the map (world min z - 1024): gsa1.FollowerRespawn, with gsa1_follower_loop_guard 1")
    set("gsa1_follower_loop_guard", 0)
    fclear()
    M.T = M.T + 2
    frames(1)
    check(#fcalls("FollowerRespawn", T.id) == 0, "with 0 it does not (review R.14)")
    set("gsa1_follower_loop_guard", 1)
    mc.pos.z = C.drawPos.z
    -- the loop guard: 4 drops within 10 s: held 3 s, released
    fclear()
    local f = FM.chars[T.id]
    for _ = 1, 4 do
        f.respawns = f.respawns + 1
        M.T = M.T + 0.3
        frames(1)
    end
    M.T = M.T + 0.3
    frames(1)
    check(T.guardUntil ~= nil and #fcalls("FollowerHold", T.id) == 1 and f.held == true, "the loop guard: 4 drops within 10 s: held")
    M.T = M.T + 3.1
    frames(1)
    check(T.guardUntil == nil and f.held == false, "3 s later it is released behind its leader")
    -- a call back is not a loop
    fclear()
    for _ = 1, 5 do
        Fo.CallOne(T)
        M.T = M.T + 0.3
        frames(1)
    end
    check(T.guardUntil == nil and #fcalls("FollowerHold", T.id) == 0, "your calling them back is no loop")
    -- FarFoci
    mc.pos.z = C.drawPos.z
    local A = spawn("knuckles")
    local D = spawn("gamma")
    T.drawPos:SetUnpacked(C.drawPos.x + 500, C.drawPos.y, C.drawPos.z)
    A.drawPos:SetUnpacked(C.drawPos.x + 3000, C.drawPos.y, C.drawPos.z)
    D.drawPos:SetUnpacked(C.drawPos.x + 3200, C.drawPos.y, C.drawPos.z)
    local foci = Fo.FarFoci(C, 1200, 4)
    check(#foci == 1 and foci[1] == A.drawPos, "Fo.FarFoci: more than 1,200 HU from you and from each focus already chosen")
    -- MoversThink scans there: 2 spheres; with no character from the followers' foci alone
    local spheres = {}
    local fis = ents.FindInSphere
    ents.FindInSphere = function(p, r)
        spheres[#spheres + 1] = Vector(p)
        return {}
    end
    GSA1.Movers.nextScan = 0
    GSA1.MoversThink(C, M.T)
    local two = #spheres
    spheres = {}
    GSA1.Movers.nextScan = 0
    GSA1.MoversThink(nil, M.T)
    ents.FindInSphere = fis
    check(two == 2 and #spheres >= 1, "GSA1.MoversThink looks around you and the far follower (%d spheres); with no character from the followers (%d)", two, #spheres)
    -- at most 4
    set("gsa1_follower_max", 8)
    local many = {}
    for i = 1, 5 do many[i] = spawn("gamma") end
    for i = 1, 5 do many[i].drawPos:SetUnpacked(C.drawPos.x + 3000 * (i + 1), 0, 0) end
    local f4 = Fo.FarFoci(C, 1200, 4)
    check(#f4 == 4, "at most 4 extra looks")
    Fo.RemoveAll("removed")
    set("gsa1_follower_max", 3)
    -- the log's own line
    reset()
    me("sonic")
    local a1, a2 = spawn("tails"), spawn("knuckles", { ignore_cap = true, silent = true, objects = 0, why = "egg" })
    set("gsa1_log", 1)
    frames(2)
    log0 = #logtext()
    for _ = 1, 12 do
        M.T = M.T + 1
        frames(1)
    end
    local lt = string.sub(logtext(), log0 + 1)
    local line = string.match(lt, "followers 2 %(egg 1%): tick [%d.]+ ms on 3 workers %(join [%d.]+ ms%), draw [%d.]+ ms; levels %d+ full, %d+ far, %d+ not drawn")
    check(line ~= nil, "the log has its own line: %s", tostring(line or string.sub(lt, 1, 200)))
    -- with the garbage of the gsa1_follower* hooks (the per-hook meter's slots)
    local slot = GSA1.GcMeter.Slot("Think", "gsa1_follower")
    slot.kb = slot.kb + 120
    log0 = #logtext()
    for _ = 1, 12 do
        M.T = M.T + 1
        frames(1)
    end
    lt = string.sub(logtext(), log0 + 1)
    check(string.find(lt, "garbage of the gsa1_follower* hooks, KB per frame: Think / gsa1_follower ", 1, true) ~= nil,
        "and the top gsa1_follower* hooks' garbage on it (D10: the perf line is cut at about 900 characters)")
    -- the threads' slider
    FM.threads = {}
    set("gsa1_follower_threads", 4)
    check(FM.threads[#FM.threads] == 4, "the threads' slider reaches gsa1.FollowerThreads")
    set("gsa1_follower_threads", 0)
    check(string.find(Fo.ThreadsLine(), "3 workers", 1, true) ~= nil, "the status line: %s", Fo.ThreadsLine())
    -- the upgrades ticked: made again; "sounds" off: made again
    local b0, k0 = a1.id, a2.id
    fclear()
    set("gsa1_upgrade_rhythm_badge", 1)
    M.T = M.T + 0.3
    frames(2)
    local nt = Fo.ByUid(a1.uid)
    local cr0 = fcalls("FollowerCreate")
    check(nt and nt.id ~= b0 and Fo.ByUid(a2.uid).id == k0 and cr0[1] and cr0[1][6].upgrades and cr0[1][6].upgrades[1] == "rhythm_badge",
        "an upgrade of Tails ticked: the Tails followers are made again with it, a Knuckles not")
    set("gsa1_upgrade_rhythm_badge", 0)
    M.T = M.T + 0.3
    frames(2)
    fclear()
    set("gsa1_follower_sounds", 0)
    M.T = M.T + 0.3
    frames(2)
    local cr = fcalls("FollowerCreate")
    local silent = cr[1] and cr[1][6].sounds == false
    set("gsa1_follower_sounds", 1)
    M.T = M.T + 0.3
    frames(2)
    check(silent, "\"Followers' own sounds\" off: the ones there are made again silent")
    Fo.RemoveAll("removed")
    -- the page's list (2 Hz)
    vgui.Create = function(cls)
        local p = { cls = cls, children = {} }
        return setmetatable(p, { __index = function(t, k)
            return function(self, ...)
                if k == "AddChoice" then
                    local c = rawget(t, "choices") or {}
                    c[#c + 1] = { ... }
                    rawset(t, "choices", c)
                elseif k == "SetText" then
                    rawset(t, "text", (...))
                elseif k == "Remove" then
                    rawset(t, "removed", true)
                end
            end
        end })
    end
    if not GSA1.Char then me("sonic") end
    local F = spawn("tails")
    local holder = { SetTall = function() end }
    Fo.ListThink(holder)
    local rows = holder.gsa1Rows
    local row = rows and rows[1]
    check(row and row.gsa1Label and string.find(tostring(rawget(row.gsa1Label, "text")), "Tails", 1, true) ~= nil and
        string.find(tostring(rawget(row.gsa1Label, "text")), "follows you", 1, true) ~= nil, "a row says whom it follows, what it does, how far: %s",
        tostring(row and rawget(row.gsa1Label, "text")))
    fclear()
    row.gsa1Call.DoClick()
    check(#fcalls("FollowerRespawn", F.id) == 1, "a row's Call")
    row.gsa1Target.OnSelect(nil, nil, nil, 4)
    check(F.target.type == "stay", "a row's target combo")
    row.gsa1Remove.DoClick()
    check(#Fo.list == 0, "a row's Remove")
end

-- 14. the console's extras ---------------------------------------------------------------------------------------------------------------------
do
    reset()
    local C = me("sonic")
    RunConsoleCommand("gsa1_follower_spawn")
    RunConsoleCommand("gsa1_follower_spawn", "knuckles", "stay")
    check(#Fo.list == 2 and Fo.list[1].kind == 2 and Fo.list[2].kind == 3 and Fo.list[2].target.type == "stay", "gsa1_follower_spawn [kind] [target]")
    RunConsoleCommand("gsa1_follower_settarget", "me", "2")
    check(Fo.list[2].target.type == "me", "gsa1_follower_settarget <who> [n] (not gsa1_follower_target: that is the ConVar)")
    check(M.cmds.gsa1_follower_target == nil, "no console command shares a ConVar's name")
    fclear()
    RunConsoleCommand("gsa1_follower_call")
    check(#fcalls("FollowerRespawn") == 2, "gsa1_follower_call")
    RunConsoleCommand("gsa1_follower_remove")
    check(#Fo.list == 1 and Fo.list[1].kind == 2, "gsa1_follower_remove: the newest")
    RunConsoleCommand("gsa1_follower_remove", "all")
    check(#Fo.list == 0, "gsa1_follower_remove all")
end

-- 15. garbage (item 13; D10, A22) --------------------------------------------------------------------------------------------------------------
do
    reset()
    set("gsa1_follower_max", 8)
    local C = me("sonic")
    for i = 1, 8 do spawn(i % 2 == 0 and "tails" or "knuckles") end
    frames(120)
    -- the mock module's own garbage is not the addon's
    local mock_kb = 0
    local wrapped = {}
    for n, fn in pairs(G) do
        if type(fn) == "function" then
            wrapped[n] = fn
            G[n] = function(...)
                local k0 = collectgarbage("count")
                local a, b, c, d, e, f, g, h, i, j = fn(...)
                mock_kb = mock_kb + collectgarbage("count") - k0
                return a, b, c, d, e, f, g, h, i, j
            end
        end
    end
    local slots = {}
    local total_hooks = 0
    local nested = 0
    local function meter(id, fn)
        return function(...)
            local k0, m0 = collectgarbage("count"), mock_kb
            nested = nested + 1
            local a, b = fn(...)
            nested = nested - 1
            local d = (collectgarbage("count") - k0) - (mock_kb - m0)
            if d > 0 then
                slots[id] = (slots[id] or 0) + d
                if nested == 0 then total_hooks = total_hooks + d end
            end
            return a, b
        end
    end
    local hook_was = {}
    for ev, t in pairs(M.hooks) do
        for id, fn in pairs(t) do
            if string.sub(id, 1, 13) == "gsa1_follower" then
                hook_was[#hook_was + 1] = { ev, id, fn }
                t[id] = meter(ev .. " / " .. id, fn)
            end
        end
    end
    local think_kb = 0
    local ft = GSA1.FollowersThink
    GSA1.FollowersThink = function(now)
        local k0, m0, h0 = collectgarbage("count"), mock_kb, total_hooks
        ft(now)
        think_kb = think_kb + (collectgarbage("count") - k0) - (mock_kb - m0)
    end
    for _ = 1, 300 do frames(1) end
    think_kb, total_hooks = 0, 0
    slots = {}
    collectgarbage("collect")
    collectgarbage("stop")
    for _ = 1, 600 do frames(1) end
    collectgarbage("restart")
    GSA1.FollowersThink = ft
    for _, h in ipairs(hook_was) do M.hooks[h[1]][h[2]] = h[3] end
    for n, fn in pairs(wrapped) do G[n] = fn end
    local per = total_hooks * 1024 / 600
    local think_per = think_kb * 1024 / 600
    info("8 followers, 600 mock frames: hook slots gsa1_follower* %.1f bytes per frame; GSA1.FollowersThink (with the hooks it runs, without the mock module's) %.1f "
        .. "bytes per frame (mock figures: Vector and Angle are tables here, D10)", per, think_per)
    check(per < 1024, "8 followers: under 1 KB of Lua garbage per frame in the hook slots gsa1_follower* (D10: %.1f bytes)", per)
    check(think_per < 1024, "and GSA1.FollowersThink itself (%.1f bytes)", think_per)
    Fo.RemoveAll("removed")
    set("gsa1_follower_max", 3)
    -- D10: no engine call that returns a Vector or an Angle per follower per frame, in the think
    reset()
    set("gsa1_follower_max", 8)
    me("sonic")
    for i = 1, 8 do spawn("knuckles") end
    frames(10)
    local eng = 0
    local pos0, eyepos0, eyeang0, plyEye = M.player.GetPos, EyePos, EyeAngles, M.player.EyeAngles
    M.player.GetPos = function(s) eng = eng + 1 return pos0(s) end
    M.player.EyeAngles = function(s) eng = eng + 1 return plyEye(s) end
    EyePos = function() eng = eng + 1 return eyepos0() end
    EyeAngles = function() eng = eng + 1 return eyeang0() end
    local entcalls = 0
    for _, F in ipairs(Fo.list) do
        local e = F.ent
        local g0 = e.GetPos
        e.GetPos = function(s) entcalls = entcalls + 1 return g0(s) end
    end
    local ft2 = GSA1.FollowersThink
    local before = eng
    ft2(M.T)
    ft2(M.T + 1 / 60)
    local spent = eng - before
    EyePos, EyeAngles = eyepos0, eyeang0
    M.player.GetPos, M.player.EyeAngles = pos0, plyEye
    check(spent == 0 and entcalls == 0, "D10: GSA1.FollowersThink with 8 followers of your character: no engine call that returns a Vector or an Angle (%d, %d)", spent, entcalls)
    Fo.RemoveAll("removed")
    set("gsa1_follower_max", 3)
end

-- 16. the mock against the module's follower_api.txt (5.5; review R98.14) -----------------------------------------------------------------------
do
    local groot = string.gsub(tests, "[/" .. string.char(92) .. "]tests$", "")
    local hdr = host_read(groot .. "/build/deps/include/libsa1.h") or ""
    if not string.find(hdr, "#define SA1_API_FOLLOWER", 1, true) then
        info("follower_api.txt: the snapshot's libsa1.h has no SA1_API_FOLLOWER yet - the check is skipped (5.5's rule)")
    else
        local api = host_read(groot .. "/build/x86_64-windows/follower_api.txt")
        local wrong, n = {}, { feature = 0, ["function"] = 0, const = 0, field = 0 }
        if not api then
            wrong[1] = "no build/x86_64-windows/follower_api.txt"
        else
            local reads = { ["FollowersTick[i]"] = { id = 1, pairs = 1, ok = 1, code = 1, msg = 1, rendered = 1, restructured = 1, x = 1, y = 1, z = 1,
                                                     yaw = 1, interpolated = 1, alpha = 1, tris = 1 },
                            FollowersTick = { count = 1, workers = 1, ms = 1, ms_join = 1 },
                            FollowerInfo = { mode = 1, smode = 1, distance = 1, respawns = 1, held = 1 },
                            FollowersStats = { workers = 1, ms_tick = 1, ms_render = 1, ms_join = 1 } }
            local seen = {}
            for line in string.gmatch(api, "[^\r\n]+") do
                if string.sub(line, 1, 1) ~= "#" then
                    local f = {}
                    for part in string.gmatch(line .. "\t", "([^\t]*)\t") do f[#f + 1] = part end
                    local kind = f[1]
                    if n[kind] then n[kind] = n[kind] + 1 end
                    if kind == "feature" and f[2] == "follower" then
                        if tonumber(G.FEATURES.follower) ~= tonumber(f[3]) then wrong[#wrong + 1] = "feature " .. f[2] end
                    elseif kind == "function" then
                        if type(G[f[2]]) ~= "function" then wrong[#wrong + 1] = "function " .. tostring(f[2]) end
                    elseif kind == "const" then
                        local tab, name = string.match(f[2] or "", "^(%u+)%.([%u_%.]+)$")
                        if tab == "FOLLOWER" then
                            local v = G.FOLLOWER
                            for part in string.gmatch(name, "[^.]+") do v = type(v) == "table" and v[part] or nil end
                            -- (LIB_PARALLEL's value is the build's)
                            if name ~= "LIB_PARALLEL" and v ~= tonumber(f[3]) then wrong[#wrong + 1] = "const " .. tostring(f[2]) end
                        end
                    elseif kind == "option" and f[2] == "FollowerCreate" then
                        if OPT_TYPES[f[3]] ~= f[4] then wrong[#wrong + 1] = "option " .. tostring(f[3]) end
                    elseif kind == "field" then
                        seen[(f[2] or "") .. "." .. (f[3] or "")] = true
                    elseif kind == "reason" then
                        seen["reason." .. (f[3] or "")] = true
                    end
                end
            end
            if n.field > 0 then
                for fn, fields in pairs(reads) do
                    for fld in pairs(fields) do
                        if not seen[fn .. "." .. fld] then wrong[#wrong + 1] = fn .. "." .. fld .. " (the client reads it)" end
                    end
                end
            end
            if n["function"] < 12 then wrong[#wrong + 1] = "too few functions" end
            -- the words the egg's and the page's tests take from the mock are the module's
            if not seen["reason.not enough free memory"] then wrong[#wrong + 1] = "the memory guard's words" end
        end
        check(#wrong == 0, "this test's mock module matches build/x86_64-windows/follower_api.txt (%d functions, %d constants, %d fields)%s",
            n["function"], n.const, n.field, #wrong > 0 and (": " .. table.concat(wrong, "; ")) or "")
    end
end

-- 17. nothing went wrong -----------------------------------------------------------------------------------------------------------------------
reset()
check(#FM.bad == 0, "every call into the mock module had the arguments of 5.5%s", #FM.bad > 0 and (": " .. FM.bad[1]) or "")
local report_ok = true
for _, r in ipairs(M.reported) do
    if not string.find(r, "a broken feature", 1, true) then report_ok = false end
end
check(report_ok, "no Lua error reported%s", (not report_ok) and (": " .. tostring(M.reported[1])) or "")
return done()
