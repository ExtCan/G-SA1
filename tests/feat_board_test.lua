-- feat_board_test.lua - the board feature's addon side (round 0.9.5; sadc docs/research/gsa1_095_plan.md 4, 5.4 - 5.8 and
-- 6.4 with its Review R.3 / R.5 / R.10 / R.11 / R.12 / R.13; board095_gsa1.md 10 items 1-12; the owner's binding answers
-- gsa1_rounds_plan.md 14.1ad): feat/sh_board.lua, cl_board.lua, sv_board.lua, the entities gsa1_trigger, gsa1_board_on,
-- gsa1_board_off, gsa1_board_left and the patches in sh_objects.lua (O.IsObject), cl_spawntab.lua (T.LATER), cl_wheel.lua
-- (W.OPEN_ACTIONS, the hint, the binder rows, W.PLAY_GATES), sh_wheel.lua (the board key refused), cl_super.lua - in
-- Garry's Mod's own LuaJIT: the client through the autorun against tests/lua_mock.lua and a MOCK MODULE of gsa1_095_plan.md
-- 5.4 (feature "board" 1: gsa1.Board / BoardPush / BoardFree / BoardState / BoardSounds / BoardInfo / gsa1.BOARD, a small
-- model of libsa1's board per character: order 44 taken at the next pair, a kept board that settles after 30 steps, frees
-- and refusals once; the emote feature for the wheel); the server's files in their own environment with a small model of
-- scripted entities (NetworkVars with notifications, Edit tables, physics boxes, a client copy of every entity) and net
-- messages delivered at once between the realms; a fake GSA1.ObjView for the extra pictures (feat_objview_test.lua tests
-- the seam itself).
--   lua_host tests/feat_board_test.lua <tests dir> <addon/lua dir>
-- The mock is checked against build/<target>/board_api.txt (095-gsa1-boardmod's binding test writes it) as soon as the
-- snapshot header build/deps/include/libsa1.h defines SA1_API_BOARD (review R.6); before that the check is skipped.
--
-- API NOTES (095-gsa1-boardlua, the full text; the report carries a summary):
--   * GSA1.Board = B (feat/sh_board.lua, both realms): B.cv (every ConVar of 5.8), B.NET / WHAT / WHY / CANCEL, B.Edge(track,
--     boxes, x, y, z, t, exits) -> entries {box, t} in the order crossed (the pure swept edge test; B.NewTrack, B.Seed,
--     B.MakeBox(key, x, y, z, p, y, r, L, W, H)), B.CanBoard(C, have) -> ok, why, B.WalkDeadline(d), B.FovDegrees(spd),
--     B.IsBoardRow(kind, e), B.GroundAngles(yaw, normal), B.Hull(ent), B.Spent(ent);
--   * client (feat/cl_board.lua): B.State(C) -> C.board = { on, entering, walk, leaving, refusal, st }; B.Toggle(C, how);
--     B.Poll(C) after every tick (GSA1PostTick); hook.Run("GSA1BoardChanged", C, on, why) on each edge; the wheel's
--     W.OPEN_ACTIONS entry "board" and W.PLAY_GATES entry "board"; GSA1.FilterStick / FilterButtons / ViewOverride chained;
--     CreateMove "gsa1_board_camera"; the extras "box:<index>" and "left:<index>" (feat/cl_objview.lua V.Extra*); the page
--     at order 275; the spawn tab's T.LATER "Board";
--   * server (feat/sv_board.lua): B.Enter(ply, ent, slot), B.Took, B.Cancel, B.StateMsg, B.Left, B.ResetBox, B.Retest,
--     B.EdgeThink / B.SlowThink (the Think hook "gsa1_board"); hooks GSA1BoardBox(ply, ent, what) (false: nothing),
--     GSA1BoardChanged(ply, on); the NW2 bool "gsa1_board"; gsa1_sv_board_reset;
--   * the entities: gsa1_trigger (base; GSA1Object + GSA1Trigger; NetworkVars Enabled, Uses, Width, Length, Height, Used,
--     Placer), gsa1_board_on (+ Refill, RefillAfter, Push, Ground, Present, RespawnAt, BoardPos, BoardAng), gsa1_board_off,
--     gsa1_board_left (Kind, Variant, Slot, Rider; no duplicator).
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_board_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files, the wheel's, the objects' shared file (O.IsObject, the Rings category) and the spawn tab
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_board%.lua$") or string.find(n, "_wheel[%w_]*%.lua$") or n == "sh_objects.lua" or
                n == "cl_spawntab.lua" then
                keep[#keep + 1] = n
            end
        end
        return keep
    end
    return out
end

-- GMod constants and helpers the mock lacks (the stubs this test needs live here: lua_mock.lua is 095-gsa1-render's) -----
SOLID_VPHYSICS, MOVETYPE_VPHYSICS, MOVETYPE_NONE, TRANSMIT_ALWAYS, SOLID_NONE = 6, 6, 0, 0, 0
SOLID_BBOX, SOLID_OBB = 2, 3
RENDERGROUP_TRANSLUCENT, COLLISION_GROUP_NONE = 1, 0
MOVETYPE_NOCLIP, MOVETYPE_WALK, MASK_SOLID = 8, 2, 33570827
local VMT = getmetatable(Vector())
function VMT:Dot(v) return self.x * v.x + self.y * v.y + self.z * v.z end
VMT.__div = function(a, k) return Vector(a.x / k, a.y / k, a.z / k) end
VMT.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
local AMT = getmetatable(Angle())
local drawn = { wire = 0, boxes = 0, texts = {} }
render.DrawWireframeBox = function() drawn.wire = drawn.wire + 1 end
render.DrawBox = function() drawn.boxes = drawn.boxes + 1 end
render.SetColorMaterial = function() end
cam.Start3D2D = function() end
cam.End3D2D = function() end
draw.SimpleTextOutlined = function(text) drawn.texts[#drawn.texts + 1] = text end
surface.CreateFont = function() end
surface.SetFont = function() end
surface.GetTextSize = function(s) return #tostring(s) * 8, 16 end
surface.DrawPoly = function() end
local chats = {}
chat.AddText = function(...)
    local t = {}
    for _, v in ipairs({ ... }) do if type(v) == "string" then t[#t + 1] = v end end
    chats[#chats + 1] = table.concat(t)
end
local spawn_list = {}
list = { GetForEdit = function(name) spawn_list[name] = spawn_list[name] or {} return spawn_list[name] end,
         Get = function(name) return spawn_list[name] or {} end,
         Set = function(name, k, v) spawn_list[name] = spawn_list[name] or {} spawn_list[name][k] = v end }
-- the keyboard
local keys, binds, codes = {}, {}, {}
local KEYNAMES = { [67] = "TAB", [107] = "MOUSE1", [108] = "MOUSE2", [17] = "G", [12] = "B", [65] = "SPACE", [33] = "W",
                   [15] = "E" }
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    IsKeyDown = function(code) return keys[code] == true end,
    IsMouseDown = function(code) return keys[code] == true end,
    LookupBinding = function(b) return binds[b] end,
    GetKeyCode = function(name) return codes[name] end,
    GetKeyName = function(code) return KEYNAMES[code] or ("key" .. tostring(code)) end,
    LookupKeyBinding = function(code)
        if code == 67 then return "+showscores" end
        if code == 12 then return "say_team" end         -- a bind of B the board feature swallows in the open wheel
    end,
}
binds["+jump"], codes["SPACE"] = "SPACE", 65
binds["+forward"], codes["W"] = "W", 33
binds["+attack"], codes["MOUSE1"] = "MOUSE1", 107
binds["+use"], codes["E"] = "E", 15
local KEY_TAB, KEY_B = 67, 12
M.player.IsTyping = function() return false end
M.player.GetAimVector = function() return Vector(1, 0, 0) end
M.player.IsAdmin = function() return true end

-- a model of scripted entities (both realms) --------------------------------------------------------------------------------
local EMT = {}
local function phys_object()
    return { motion = true, gravity = true, vel = Vector(),
             EnableMotion = function(s, b) s.motion = b end, IsMotionEnabled = function(s) return s.motion end,
             EnableGravity = function(s, b) s.gravity = b end, SetVelocity = function(s, v) s.vel = Vector(v) end,
             Wake = function() end }
end
local function install_dt(e) e.dt, e.dtn, e.edit, e.keys, e.types = {}, {}, {}, {}, {} end
local DEFAULTS = { Bool = false, String = "", Entity = NULL }
function EMT:NetworkVar(typ, slot, name, other)
    local d = DEFAULTS[typ]
    if d == nil then d = 0 end
    if typ == "Vector" then d = Vector() elseif typ == "Angle" then d = Angle() end
    self.dt[name] = d
    self.dtn[name] = self.dtn[name] or {}
    self.types[name] = typ
    self["Get" .. name] = function(s) return s.dt[name] end
    self["Set" .. name] = function(s, v)
        for _, f in ipairs(s.dtn[name]) do f(s, name, s.dt[name], v) end
        s.dt[name] = v
        if s.peer and s.peer["Set" .. name] then s.peer["Set" .. name](s.peer, s.toClient(v)) end
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
    self.solid = SOLID_BBOX
    self.cbounds = { Vector(mn), Vector(mx) }
end
function EMT:SetSolid(s) self.solid = s end
function EMT:EnableCustomCollisions(b) self.customcol = (b ~= false) end
function EMT:SetMoveType(m) self.movetype = m end
function EMT:SetCollisionBounds(a, b) self.cbounds = { Vector(a), Vector(b) } end
function EMT:SetCollisionGroup(g) self.group = g end
function EMT:GetPhysicsObject() return self.phys or NULL end
function EMT:SetRenderBounds(a, b) self.rbounds = { Vector(a), Vector(b) } end
function EMT:OBBMins() return self.cbounds and Vector(self.cbounds[1]) or Vector(-8, -8, -8) end
function EMT:OBBMaxs() return self.cbounds and Vector(self.cbounds[2]) or Vector(8, 8, 8) end
function EMT:IsPlayer() return false end
function EMT:Activate() end
function EMT:GetNW2Bool(k, d) local v = (self.nw2 or {})[k] if v == nil then return d end return v end
function EMT:SetNW2Bool(k, v) self.nw2 = self.nw2 or {} self.nw2[k] = v end

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
    local e = setmetatable({ cls = cls, idx = idx, pos = Vector(), ang = Angle(0, 0, 0), toClient = function(v) return v end },
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
    local c = setmetatable({ name = name, v = tostring(default), lo = lo, hi = hi, flags = flags },
        getmetatable(M.cv("fps_max")))
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
local undos = {}
S.undo = { Create = function(n) undos[#undos + 1] = { name = n, ents = {} } end,
           AddEntity = function(e) table.insert(undos[#undos].ents, e) end,
           SetPlayer = function(p) undos[#undos].ply = p end,
           SetCustomUndoText = function(t) undos[#undos].text = t end,
           Finish = function() undos[#undos].done = true end }
-- the floor: a trace down hits z = FLOOR_Z with the normal FLOOR_N (a slope for one check)
local FLOOR_Z, FLOOR_N = 0, Vector(0, 0, 1)
S.MASK_SOLID_BRUSHONLY = 16395
S.util = { AddNetworkString = function(n) strings[n] = true end, IsInWorld = function() return true end,
           TraceLine = function(t)
               if t.start.z >= FLOOR_Z and t.endpos.z <= FLOOR_Z then
                   return { Hit = true, HitPos = Vector(t.start.x, t.start.y, FLOOR_Z), HitNormal = Vector(FLOOR_N) }
               end
               return { Hit = false, HitPos = Vector(t.endpos) }
           end }
-- the client's traces: the floor too
util.TraceLine = function(t)
    local out = t.output or {}
    if t.start.z >= FLOOR_Z and t.endpos.z <= FLOOR_Z then
        out.Hit, out.HitPos, out.HitNormal = true, Vector(t.start.x, t.start.y, FLOOR_Z), Vector(FLOOR_N)
    else
        out.Hit, out.HitPos = false, Vector(t.endpos)
    end
    return out
end

local SCLASSES, SENTS, next_idx = {}, {}, 100
local CCLASSES, CENTS = {}, {}
-- the players (the server's view)
local function new_player(idx, name)
    local p = setmetatable({ idx = idx, name = name, pos = Vector(), infos = {}, admin = false, host = false, chats = {},
                             limit = true, counts = {}, cleanups = {}, nw2 = {} }, { __index = EMT })
    function p:IsValid() return true end
    function p:IsPlayer() return true end
    function p:Nick() return self.name end
    function p:CheckLimit(k) return self.limit end
    function p:AddCount(k, e) self.counts[#self.counts + 1] = e end
    function p:AddCleanup(k, e) self.cleanups[#self.cleanups + 1] = { k, e } end
    function p:IsAdmin() return self.admin end
    function p:IsListenServerHost() return self.host end
    function p:ChatPrint(s) self.chats[#self.chats + 1] = s end
    function p:EyeAngles() return Angle(0, self.yaw or 0, 0) end
    return p
end
local P1 = new_player(1, "player one")
local P2 = new_player(2, "player two")
S.player = { GetAll = function() return { P1, P2 } end }
local function to_client(v)
    if v == P1 then return M.player end
    if type(v) == "table" and v.peer then return v.peer end
    return v
end
local function network_to_client(se)
    local ce = setmetatable({ cls = se.cls, idx = se.idx, pos = Vector(se.pos), ang = Angle(se.ang),
                              toClient = function(v) return v end }, { __index = class_lookup(CCLASSES, se.cls) })
    install_dt(ce)
    if ce.SetupDataTables then ce:SetupDataTables() end
    for k, v in pairs(se.dt) do ce.dt[k] = to_client(v) end
    se.peer = ce
    se.toClient = to_client
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
            if s.removed then return end
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
}
S.Entity = function(i) return SENTS[i] or NULL end
Entity = function(i) return CENTS[i] or NULL end
S.scripted_ents = { Register = function(t, name) SCLASSES[name] = t end }
-- net, both directions, delivered at once (the client's messages from P1)
local out_c, out_s, sent_c, sent_s = nil, nil, {}, {}
local function reader(vals)
    local i = 0
    return function() i = i + 1 return vals[i] end
end
local cread
local function copyv(v)
    if type(v) == "table" and getmetatable(v) == VMT then return Vector(v) end
    if type(v) == "table" and getmetatable(v) == AMT then return Angle(v) end
    return v
end
net.Start = function(name) out_c = { name = name, vals = {} } end
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteInt", "WriteFloat", "WriteVector", "WriteAngle", "WriteEntity",
                     "WriteString" }) do
    net[w] = function(v) if out_c then out_c.vals[#out_c.vals + 1] = copyv(v) end end
end
net.Receive = function(name, fn) recv_c[name] = fn end
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadInt", "ReadFloat", "ReadVector", "ReadAngle", "ReadEntity",
                     "ReadString" }) do
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
for _, w in ipairs({ "WriteBool", "WriteUInt", "WriteInt", "WriteFloat", "WriteVector", "WriteAngle", "WriteString",
                     "WriteEntity" }) do
    S.net[w] = function(v) if out_s then out_s.vals[#out_s.vals + 1] = copyv(v) end end
end
for _, r in ipairs({ "ReadBool", "ReadUInt", "ReadInt", "ReadFloat", "ReadVector", "ReadAngle", "ReadString",
                     "ReadEntity" }) do
    S.net[r] = function() return S.sread() end
end
util.NetworkStringToID = function(n) return strings[n] and 1 or 0 end
local function msgs_c(name)
    local out = {}
    for _, m in ipairs(sent_c) do if m.name == name then out[#out + 1] = m end end
    return out
end
local function msgs_s(name, to)
    local out = {}
    for _, m in ipairs(sent_s) do if m.name == name and (to == nil or m.to == to) then out[#out + 1] = m end end
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
local ENT_NAMES = { "gsa1_trigger", "gsa1_board_on", "gsa1_board_off", "gsa1_board_left" }

-- the server's files ---------------------------------------------------------------------------------------------------------
rawset(S, "GSA1", {})
local ok_s, err_s = pcall(function()
    sinclude("gsa1/sh_config.lua")
    sinclude("gsa1/sh_net.lua")
    sinclude("gsa1/feat/sh_board.lua")
    sinclude("gsa1/feat/sv_board.lua")
    for _, n in ipairs(ENT_NAMES) do load_entity(S, n) end
end)
local SG = rawget(S, "GSA1")
local SB = SG and SG.Board

-- the client: the autorun with a mock module that has the board (5.4), the emote wheel and the previews ----------------------
GSA1 = nil
local G = M.module({ features = { board = 1, emote = 3, preview = 2 } })
local BM = { calls = {}, chars = {}, refuse = nil, bad = {}, hurt = -1, held = 0, walk = nil, sounds = {} }
local function bcall(name, ...) BM.calls[#BM.calls + 1] = { name, ... } end
local function bcalls(name)
    local out = {}
    for _, c in ipairs(BM.calls) do if c[1] == name then out[#out + 1] = c end end
    return out
end
G.BOARD = { TERRAIN_MAP = 0, TERRAIN_SNOW = 1, TERRAIN_SAND = 2, DRAW = 0x4000, SETTLE_STEPS = 30,
            SONIC_MODES = { 62, 68 }, TAILS_MODES = { 48, 54 }, FREED_REMOVED = 0, FREED_FELL = 1, FREED_REPLACED = 2,
            FREED_FREE = 3, SNOW_TONES = { 208, 238 }, SAND_TONES = { 690, 698 } }
G.PREVIEW = { BOARD = 0x100, ROT_NONE = 0, ROT_OUTER = 1, ROT_INNER = 2 }
local OPT_TYPES = { terrain = "number", push = "boolean", tails_jump = "boolean", reuse = "boolean", remove = "boolean" }
local function bs_of(id)
    local s = BM.chars[id]
    if not s then
        s = { on = false, held = false, kept = false, still = 0, x = 0, y = 0, z = 0, terrain = 0, variant = 0, kind = -1,
              freed = 0, freed_why = -1, push = 0, refusedOnce = false, opts = nil }
        BM.chars[id] = s
    end
    return s
end
local function int_in(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end
-- gsa1.Board(id, on [, opts]) -> true | nil, message, code (5.4)
function G.Board(id, on, opts, ...)
    bcall("Board", id, on, opts)
    if not (int_in(id, 1, 1e9) and type(on) == "boolean" and (opts == nil or type(opts) == "table") and select("#", ...) == 0)
    then
        BM.bad[#BM.bad + 1] = "Board arguments"
        return nil, "Board(id, on [, opts])", "bad_argument"
    end
    for k, v in pairs(opts or {}) do
        if OPT_TYPES[k] == nil or type(v) ~= OPT_TYPES[k] or (k == "terrain" and not int_in(v, 0, 2)) then
            BM.bad[#BM.bad + 1] = "Board opts." .. tostring(k)
            return nil, "Board: opts." .. tostring(k), "bad_argument"
        end
    end
    local c = M.mchars[id]
    if not c then return nil, "no such character", "not_found" end
    if c.kind == 8 then return nil, "Super Sonic doesn't ride a board", "unsupported" end
    if c.kind ~= 0 and c.kind ~= 2 then return nil, "only Sonic and Tails ride a board", "unsupported" end
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
    bcall("BoardFree", id)
    local s = bs_of(id)
    if s.on or not s.kept then return nil, "no board left behind", "unsupported" end
    s.kept, s.still, s.freed, s.freed_why = false, 0, s.freed + 1, 3
    return true
end
function G.BoardPush(id) bcall("BoardPush", id) return nil, "not riding", "unsupported" end
function G.BoardSounds(on)
    bcall("BoardSounds", on)
    BM.sounds[#BM.sounds + 1] = on
    return true
end
function G.BoardInfo(out)
    out = out or {}
    out.available, out.version, out.kinds, out.textures, out.rules = true, 1, { 0, 2 }, { [0] = 2, [2] = 1 }, true
    return out
end
-- per frame, no table made when out is given
function G.BoardState(id, out)
    local c = M.mchars[id]
    if not c then return nil, "no such character", "not_found" end
    local s = bs_of(id)
    out = out or {}
    out.on, out.pending, out.held, out.kept = s.on, s.pending ~= nil, s.held, s.kept
    out.settled = s.kept and s.still >= 30
    out.board = s.on or s.kept
    out.mode, out.action = s.on and 62 or 2, s.on and 105 or 1
    out.speed = BM.speed or 0
    out.terrain, out.push_steps, out.kind, out.variant = s.terrain, s.push, (s.on or s.kept) and c.kind or -1, s.variant
    out.x, out.y, out.z, out.pitch, out.yaw, out.roll = s.x, s.y, s.z, 0, s.yaw or 0, 0
    out.still = s.still
    out.refused = s.refusedOnce
    out.reason = s.refusedOnce and s.reason or nil
    s.refusedOnce = false
    out.freed, out.freed_why = s.freed, s.freed > 0 and s.freed_why or -1
    s.freed = 0
    return out
end
function G.StateEx(id, out)
    out = out or {}
    out.rings, out.lives, out.mode, out.hurt_steps, out.held, out.held_object = 0, 4, 2, BM.hurt, BM.held, 0
    return out
end
-- the pairs: the board's pending order at the next pair, the kept board's rest; the walk model moves the character along
-- the stick (BM.walk = HU/s at full stick; the game's walk at 0.7: 45 HU/s)
local tick0 = G.Tick
G.Tick = function(id, sx, sy, yaw, buttons, dt, ...)
    local n, err, code = tick0(id, sx, sy, yaw, buttons, dt, ...)
    local c = M.mchars[id]
    if c and n and BM.walk then
        local mag = math.sqrt(sx * sx + sy * sy)
        local v = mag >= 0.6 and (mag >= 0.9 and BM.walk * 5.9 or BM.walk) or 0
        local y = math.rad(yaw)
        local fx, fy, rx, ry = math.cos(y), math.sin(y), math.sin(y), -math.cos(y)
        if mag > 0 then
            c.pos.x = c.pos.x + (sx * rx + sy * fx) / mag * v * dt
            c.pos.y = c.pos.y + (sx * ry + sy * fy) / mag * v * dt
        end
    end
    local s = BM.chars[id]
    if s and n and n > 0 then
        for _ = 1, n do
            if s.pending then
                local p = s.pending
                s.pending = nil
                if p.on then
                    if BM.refuse then
                        s.refusedOnce, s.reason = true, BM.refuse
                    else
                        if s.kept then s.kept, s.freed, s.freed_why = false, s.freed + 1, 2 end
                        s.on, s.held, s.terrain, s.opts = true, true, p.opts.terrain or 0, p.opts
                        s.variant = BM.variant or 0
                    end
                else
                    s.on, s.held = false, false
                    s.x, s.y, s.z, s.yaw = c.pos.x + 8, c.pos.y, c.pos.z, 30
                    if p.opts.remove then
                        s.freed, s.freed_why = s.freed + 1, 0
                    else
                        s.kept, s.still = true, 0
                    end
                end
            elseif s.kept then
                s.still = s.still + 2
                if BM.fall then
                    s.kept, s.freed, s.freed_why, BM.fall = false, s.freed + 1, 1, nil
                end
            end
        end
    end
    return n, err, code
end
-- the wheel's emote feature (bind_emote.cpp's shape, a small catalogue with a board row)
G.EMOTE = { LOOP = 0x100, IN_AIR = 4, KEEP_INPUT = 8, NO_PROPS = 0x10, NO_TRAIL = 2, CHAIN = 1, STOP_NOW = 0, STOP_BLEND = 1,
            STATE_NONE = 0, STATE_PLAYING = 1, STATE_ENDING = 2, ROW = 0, EXTRA = 1, FORM_NORMAL = 0, FORM_SUPER = 1,
            HOLD = 0x20, STATE_HOLDING = 3, SPEED_MIN = 1 / 64, SPEED_MAX = 16 }
local function L(rows)
    local out = { n = #rows }
    for i, r in ipairs(rows) do
        out[i] = { key = r[1], source = 0, index = tonumber(string.sub(r[1], 2)), name = r[2], label = "LABEL_" .. r[2],
                   frames = 30, play = "once", group = r[3], class = 0, flags = 0, dup = 0, dup_key = "" }
    end
    return out
end
local LISTS = { [0] = L({ { "a5", "s_wait_a1", "idle" }, { "a75", "s_kimepose0", "pose" }, { "a105", "s_sbjump1", "board" } }),
                [2] = L({ { "a5", "m_wait_a1", "idle" }, { "a110", "m_sbjump1", "board" } }),
                [3] = L({ { "a5", "k_wait_a1", "idle" } }) }
function G.EmoteList(kind, form)
    local l = LISTS[kind] or { n = 0 }
    local out = { n = l.n }
    for i = 1, l.n do
        local e = {}
        for k, v in pairs(l[i]) do e[k] = v end
        out[i] = e
    end
    return out
end
local emotes = {}
function G.Emote(id, key, flags, speed) emotes[#emotes + 1] = key return true end
function G.EmoteStop() return true end
function G.EmoteState() return 0, nil, -1, 0 end
local PAD = { connected = false, raw = 0, rx = 0, ry = 0, lx = 0, ly = 0, yaw = 0, pitch = 0, reset = false }
function G.PadPoll(dt, paused, out)
    out = out or {}
    for k, v in pairs(PAD) do out[k] = v end
    out.active, out.buttons, out.sx, out.sy = false, 0, 0, 0
    return out
end

M.included = {}
local ok_c, err_c = pcall(M.load, "autorun/gsa1_autorun.lua")
local ok_e, err_e = pcall(function()
    for _, n in ipairs(ENT_NAMES) do load_entity(nil, n) end
end)
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local B = GSA1 and GSA1.Board
local W = GSA1 and GSA1.Wheel
check(ok_s and SB ~= nil and ok_c and ok_e and #ferr == 0 and B ~= nil and B.BuildPage ~= nil and W ~= nil,
    "the board's files load: server (sh_board, sv_board, the four entities) %s; client through the autorun %s",
    ok_s and "ok" or tostring(err_s), (ok_c and ok_e and #ferr == 0) and table.concat(GSA1.FeatureFiles or {}, " ") or
    tostring(err_c or err_e or ferr[1]))
if not (ok_s and SB and ok_c and B and W) then return done() end

-- the extra pictures (feat/cl_objview.lua's seam), faked: what was added, removed and drawn where
local XV = { adds = {}, removes = {}, draws = {}, live = {}, minz = -3 }
GSA1.ObjView = {
    Ready = function() return true end,
    ExtraAdd = function(key, desc)
        if XV.live[key] ~= desc then XV.adds[#XV.adds + 1] = { key = key, desc = desc } end
        XV.live[key] = desc
        return true
    end,
    ExtraRemove = function(key)
        if XV.live[key] then XV.removes[#XV.removes + 1] = key end
        XV.live[key] = nil
        return true
    end,
    ExtraDraw = function(key, pos, ang, pass, flags)
        if not XV.live[key] then return false end
        if not XV.quiet then XV.draws[#XV.draws + 1] = { key = key, pos = Vector(pos), ang = Angle(ang), pass = pass } end
        return true
    end,
    ExtraBounds = function(key) return -24, -8, XV.minz, 24, 8, 2 end,
}

-- 1. the settings, the classes (board095_gsa1.md 10 item 1) ---------------------------------------------------------------------
do
    local WANT = {
        gsa1_board = { "1", 0, 1 }, gsa1_board_key = { "12", 0, 511 }, gsa1_board_pad = { "128", 0, 0x30000 },
        gsa1_board_terrain = { "0", 0, 2 }, gsa1_board_walk = { "0", 0, 1 }, gsa1_board_push = { "0", 0, 1 },
        gsa1_board_camera = { "1", 0, 1 }, gsa1_board_fov = { "0", 0, 1 }, gsa1_board_fov_mode = { "0", 0, 1 },
        gsa1_board_sounds = { "1", 0, 1 }, gsa1_board_respawn = { "0", 0, 1 }, gsa1_board_tails_jump = { "0", 0, 1 },
        gsa1_board_super = { "0", 0, 1 }, gsa1_board_box_show = { "0", 0, 1 },
    }
    local SWANT = { gsa1_sv_board = { "1", 0, 1 }, gsa1_sv_board_left_time = { "120", 0, 3600 },
                    gsa1_sv_board_left_max = { "5", 0, 64 }, sbox_maxgsa1_triggers = { "100", 0, 10000 } }
    local bad = {}
    for name, w in pairs(WANT) do
        local c = M.convars[name]
        if not (c and c.client and c.save and c.v == w[1] and c.lo == w[2] and c.hi == w[3] and GSA1.CONVARS[name]) then
            bad[#bad + 1] = name
        end
    end
    for name, w in pairs(SWANT) do
        local c, sc = M.convars[name], SCV[name]
        if not (c and sc and c.v == w[1] and sc.v == w[1] and sc.lo == w[2] and sc.hi == w[3] and GSA1.CONVARS[name] and
            GSA1.CONVARS[name].server and bit.band(sc.flags or 0, 8192) ~= 0) then
            bad[#bad + 1] = name
        end
    end
    table.sort(bad)
    check(#bad == 0, "every ConVar of 5.8 with its default and range (14 client, 3 replicated server settings and "
        .. "sbox_maxgsa1_triggers made by hand, listed in GSA1.CONVARS)%s", #bad > 0 and (": wrong " .. table.concat(bad, " ")) or "")
    local on, off, base, left = CCLASSES.gsa1_board_on, CCLASSES.gsa1_board_off, CCLASSES.gsa1_trigger, CCLASSES.gsa1_board_left
    check(on.Spawnable and off.Spawnable and on.Category == "G-SA1" and off.Category == "G-SA1" and on.Base == "gsa1_trigger"
        and off.Base == "gsa1_trigger" and not base.Spawnable and base.GSA1Object and base.GSA1Trigger and on.GSA1Trigger and
        left.GSA1Object and left.GSA1Trigger and not left.Spawnable and left.DisableDuplicator == true and
        on.ScriptedEntityType == "entity", "Board On / Board Off: spawnable in G-SA1 on the base gsa1_trigger (not spawnable; "
        .. "GSA1Object and GSA1Trigger); the left board: not spawnable, no duplicator")
end

-- 2. placing, the hull, the limit, undo, cleanup, copies (item 2) --------------------------------------------------------------
local function place(cls, x, y, z, yaw, ply)
    ply = ply or P1
    ply.yaw = yaw or 0
    return SB.ServerSpawn(ply, { Hit = true, HitPos = Vector(x, y, z), HitNormal = Vector(0, 0, 1) }, cls)
end
local E1
do
    E1 = place("gsa1_board_on", 100, 200, 0, 37)
    local ok = E1 ~= nil
    local edit = ok and E1.edit or {}
    local function nvals(k) local n = 0 for _ in pairs(edit[k] and edit[k].values or {}) do n = n + 1 end return n end
    check(ok and E1.pos.x == 100 and E1.pos.y == 200 and math.abs(E1.pos.z - 0.5) < 1e-6 and E1.ang.p == 0 and
        E1.ang.y == 37 and E1.ang.r == 0 and E1:GetWidth() == 256 and E1:GetLength() == 256 and E1:GetHeight() == 192 and
        E1:GetEnabled() == true and E1:GetUses() == 0 and E1:GetRefill() == true and E1:GetRefillAfter() == 5 and
        E1:GetPush() == 1 and E1:GetGround() == 0 and E1:GetPresent() == true and E1:GetUsed() == 0,
        "a Board On box sits with its base on the aimed surface (z %.1f), the placer's yaw 37, upright; 256 x 256 x 192, "
        .. "enabled, infinite uses, refill on after 5 s, Ice Cap's push, the rider's ground, the board there", ok and E1.pos.z or -1)
    check(nvals("uses") == 2 and nvals("push") == 3 and nvals("ground") == 4 and edit.width and edit.width.min == 32 and
        edit.width.max == 8192 and edit.height and edit.refillafter and edit.refillafter.max == 600 and edit.enabled and
        edit.refill and edit.length, "the Edit Properties rows: Enabled, Uses (a combo of 2), Width / Length / Height "
        .. "(32..8,192), Refill, Refill after (0..600), Push (3), Ground (4)")
    local cb = E1.cbounds or {}
    local ph = E1.phys
    local CE1 = CENTS[E1.idx]
    check(E1.solid == SOLID_OBB and E1.customcol and E1.group == COLLISION_GROUP_WORLD and cb[1] and cb[1].x == -128 and
        cb[1].z == 0 and cb[2].x == 128 and cb[2].z == 192 and ph and ph.motion == false and ph.gravity == false and
        E1.movetype == MOVETYPE_VPHYSICS and CE1 and CE1.solid == SOLID_OBB and CE1.cbounds and CE1.cbounds[2].z == 192 and
        CE1.rbounds ~= nil, "the pick hull: SOLID_OBB of the box (-128 -128 0 .. 128 128 192), custom collisions, "
        .. "COLLISION_GROUP_WORLD, a frozen physics box without gravity; the client copy the same with its render bounds")
    local bp, ba = E1:GetBoardPos(), E1:GetBoardAng()
    check(bp.x == 100 and bp.y == 200 and bp.z == 0 and math.abs(ba.y - 37) < 1e-6 and math.abs(ba.p) < 1e-6,
        "the board's place: traced down from the base centre to the ground (%.0f %.0f %.0f), the box's yaw (review R.3: one "
        .. "value, BoardPos / BoardAng)", bp.x, bp.y, bp.z)
    local u = { Entities = { E1 } }
    run_s("CanCreateUndo", P1, u)
    check(u.CustomUndoText == "Undone G-SA1 Board On box" and P1.counts[1] == E1 and P1.cleanups[1] and
        P1.cleanups[1][1] == "gsa1_triggers", "undo \"%s\", the count and the cleanup \"gsa1_triggers\"",
        tostring(u.CustomUndoText))
    P1.limit = false
    local refused = place("gsa1_board_off", 0, 0, 0, 0)
    P1.limit = true
    check(refused == nil, "the limit sbox_maxgsa1_triggers refuses a box")
    -- a copy keeps the editable values and starts fresh
    E1:SetUsed(3)
    E1:SetPresent(false)
    E1:SetRespawnAt(M.T + 50)
    E1:SetWidth(300)
    local data = { DT = E1:GetNetworkVars() }
    E1:OnEntityCopyTableFinish(data)
    check(data.DT.Used == 0 and data.DT.Present == true and data.DT.RespawnAt == 0 and data.DT.Width == 300,
        "a copy (duplicator, save) keeps the editable values (Width 300) and starts fresh (no use, the board there)")
    E1:SetUsed(0)
    E1:SetPresent(true)
    E1:SetRespawnAt(0)
    E1:SetWidth(256)
    SB.SlowThink(M.T)
    -- the board on a slope: its up is the ground's normal, its yaw the box's
    FLOOR_N = Vector(0.3, -0.2, 0.932)
    local slope = place("gsa1_board_on", -400, 0, 0, 120)
    FLOOR_N = Vector(0, 0, 1)
    local sa = slope:GetBoardAng()
    local _, _, up = SB.Axes(sa.p, sa.y, sa.r)
    local n = Vector(0.3, -0.2, 0.932)
    local l = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
    local dot = (up[1] * n.x + up[2] * n.y + up[3] * n.z) / l
    check(dot > 0.9999, "on a slope the lying board's up is the ground's normal (dot %.5f; angles %.1f %.1f %.1f)", dot,
        sa.p, sa.y, sa.r)
    slope:Remove()
    -- O.IsObject and the scanners' flag (review R.10)
    local O = GSA1.Objects
    local fake_obj = { GSA1Object = true }
    check(O and O.IsObject(CE1) == false and O.IsObject(fake_obj) == true and O.IsObject(nil) == false and
        O.IsObject(NULL) == false and O.IsObject(5) == false and CE1.GSA1Object == true,
        "O.IsObject: false for a trigger box (GSA1Trigger), still true for an object, nil / NULL / a number false; the box "
        .. "keeps GSA1Object for the collision and interaction scanners")
    check(run_s("CanProperty", P1, "collision", E1) == false and run_s("CanProperty", P1, "drive", E1) == false and
        run_s("CanProperty", P1, "gsa1_board_reset", E1) == nil, "the context menu refuses collision, drive (the "
        .. "objects' list) on a box, not its own \"Reset this box\"")
end

-- 3. the edge test, the prototype's nine cases and its cost (item 3, board095_gsa1.md 5.6) ----------------------------------
local function run_track(tr, list, x0, y0, z0, vx, vy, vz, hz, seconds, t0)
    local n, steps = 0, math.floor(seconds * hz + 0.5)
    for i = 0, steps do
        local t = (t0 or 0) + i / hz
        n = n + #B.Edge(tr, list, x0 + vx * i / hz, y0 + vy * i / hz, z0 + vz * i / hz, t)
    end
    return n
end
do
    local box = B.MakeBox("a", 0, 0, 0, 0, 0, 0, 256, 256, 192)
    local A = B.NewTrack()
    local n1 = run_track(A, { box }, -600, 0, 0, 300, 0, 0, 20, 4)
    local n2 = run_track(A, { box }, 600, 0, 0, -300, 0, 0, 20, 4, 10)
    local res = { n1 == 1 and n2 == 1 }
    -- jitter on the face with and without the exit pad
    local Bt, B0 = B.NewTrack(), B.NewTrack()
    local j16, j0 = 0, 0
    for i = 0, 40 do
        local x = 128 + ((i % 2 == 0) and -8 or 8)
        j16 = j16 + #B.Edge(Bt, { box }, x, 0, 0, i / 20)
        local pad = B.EXIT_PAD
        B.EXIT_PAD = 0
        j0 = j0 + #B.Edge(B0, { box }, x, 0, 0, i / 20)
        B.EXIT_PAD = pad
    end
    res[2] = j16 == 1 and j0 > 10
    local thin = B.MakeBox("t", 0, 0, 0, 0, 0, 0, 64, 512, 192)
    res[3] = run_track(B.NewTrack(), { thin }, -2850, 0, 0, 6000, 0, 0, 20, 1) == 1
    local t32 = B.MakeBox("t32", 0, 0, 0, 0, 0, 0, 32, 512, 192)
    res[4] = run_track(B.NewTrack(), { t32 }, -1000, 0, 0, 1800, 0, 0, 20, 1.2) == 1
    local bon, boff = B.MakeBox("on", 140, 0, 0, 0, 0, 0, 40, 512, 192), B.MakeBox("off", 20, 0, 0, 0, 0, 0, 40, 512, 192)
    local D = B.NewTrack()
    B.Edge(D, { bon, boff }, -100, 0, 0, 0)
    local ev5 = B.Edge(D, { bon, boff }, 200, 0, 0, 0.05)
    res[5] = #ev5 == 2 and ev5[1].box.key == "off" and ev5[2].box.key == "on"
    local mid = B.MakeBox("m", (-3693 + 298) / 2, (-611 - 2301) / 2, (207 - 86) / 2 - 96, 0, 0, 0, 400, 400, 192)
    local E = B.NewTrack()
    B.Edge(E, { mid }, -3693, -611, 207, 0)
    local ev6 = B.Edge(E, { mid }, 298, -2301, -86, 0.05)
    local land = B.MakeBox("l", 298, -2301, -96, 0, 0, 0, 256, 256, 192)
    local E2 = B.NewTrack()
    B.Edge(E2, { land }, -3693, -611, 207, 0)
    local ev6b = B.Edge(E2, { land }, 298, -2301, -86, 0.05)
    res[6] = #ev6 == 0 and #ev6b == 1
    res[7] = #B.Edge(B.NewTrack(), { box }, 10, 10, 0, 0) == 1
    local Gt = B.NewTrack()
    B.Edge(Gt, {}, 0, 0, 0, 0)
    local placed = B.MakeBox("p", 0, 0, 0, 0, 0, 0, 256, 256, 192)
    B.Seed(Gt, placed)
    local n8a = run_track(Gt, { placed }, 0, 0, 0, 0, 0, 0, 20, 1, 0.05)
    local n8b = run_track(Gt, { placed }, 0, 0, 0, 300, 0, 0, 20, 2, 2)
    local n8c = run_track(Gt, { placed }, 600, 0, 0, -300, 0, 0, 20, 2, 5)
    res[8] = n8a == 0 and n8b == 0 and n8c == 1
    local R = B.MakeBox("r", 500, -300, 40, 20, 37, 10, 300, 200, 150)
    local good = 0
    local probes = { { 149, 0, 75, true }, { 151, 0, 75, false }, { -149, 0, 75, true }, { -151, 0, 75, false },
                     { 0, 99, 75, true }, { 0, 101, 75, false }, { 0, -99, 75, true }, { 0, -101, 75, false },
                     { 0, 0, 1, true }, { 0, 0, -1, false }, { 0, 0, 149, true }, { 0, 0, 151, false },
                     { 149, 99, 149, true }, { 151, 101, 151, false } }
    for _, q in ipairs(probes) do
        local x = R.x + R.f[1] * q[1] - R.r[1] * q[2] + R.u[1] * q[3]
        local y = R.y + R.f[2] * q[1] - R.r[2] * q[2] + R.u[2] * q[3]
        local z = R.z + R.f[3] * q[1] - R.r[3] * q[2] + R.u[3] * q[3]
        if B.Inside(R, x, y, z, 0) == q[4] then good = good + 1 end
    end
    res[9] = good == #probes
    local all = true
    for i = 1, 9 do all = all and res[i] end
    check(all, "B.Edge, the prototype's nine cases: walking through and back (one entry each way) %s, the 16 HU exit pad "
        .. "on the face (1 entry; %d without it) %s, 6,000 HU/s through 64 HU %s, 1,800 HU/s through 32 HU %s, two boxes in "
        .. "one packet in the order crossed %s, a teleport %s, appearing inside %s, a box placed on a character %s, a "
        .. "turned box's faces (%d / %d) %s", tostring(res[1]), j0, tostring(res[2]), tostring(res[3]), tostring(res[4]),
        tostring(res[5]), tostring(res[6]), tostring(res[7]), tostring(res[8]), good, #probes, tostring(res[9]))
    -- the cost: 200 boxes over a 16,384 HU cube, 8 players at 1,800 HU/s, 20 packets a second, 60 s
    math.randomseed(5)
    local list = {}
    for i = 1, 200 do
        list[i] = B.MakeBox(i, math.random(-8192, 8192), math.random(-8192, 8192), math.random(-2048, 2048), 0,
            math.random(0, 359), 0, math.random(64, 1024), math.random(64, 1024), math.random(96, 512))
    end
    local tracks = {}
    for i = 1, 8 do tracks[i] = B.NewTrack() end
    local packets = 0
    local t0 = host_clock()
    for k = 0, 60 * 20 - 1 do
        for i, tr in ipairs(tracks) do
            local a = math.rad(i * 45 + k * 0.5)
            local x = 6000 * math.cos(i) + 1800 * k / 20 * math.cos(a) % 8000
            local y = 6000 * math.sin(i) + 1800 * k / 20 * math.sin(a) % 8000
            B.Edge(tr, list, x, y, 0, k / 20)
            packets = packets + 1
        end
    end
    local spent = host_clock() - t0
    B.edgeCost = spent * 1e6 / packets
    info("the edge test's cost in Garry's Mod's LuaJIT: %d packets x 200 boxes in %.1f ms = %.2f us per packet (%.3f ms per "
        .. "server second with 8 players at 20 Hz)", packets, spent * 1000, B.edgeCost, spent * 1000 / 60)
    check(B.edgeCost < 50, "the edge test costs %.2f us per packet with 200 boxes (prototype 3.1-3.3 us)", B.edgeCost)
end

-- a character, the server's Think and its state packets (sv_gsa1.lua's part: GSA1State 20 Hz) -----------------------------
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
local next_state = 0
local function server_tick()
    local C = GSA1.Char
    if C and P1.GSA1Active and M.T >= next_state then
        next_state = M.T + 1 / 20
        P1.GSA1State = { x = C.state.x, y = C.state.y, z = C.state.z, time = M.T, kind = C.kind }
    end
    run_s("Think")
end
local function frames(n, dt)
    for _ = 1, n or 1 do
        M.frame(dt or 1 / 60)
        server_tick()
    end
end
local function seconds(s) frames(math.floor(s * 60 + 0.5)) end
local function spawn(name, x, y)
    GSA1.Spawn(name)
    local C = GSA1.Char
    if C then
        local mc = M.mchars[C.id]
        mc.pos = Vector(x or 0, y or 0, 0)
        P1.GSA1Active, P1.GSA1Kind = true, C.kind
        P1.GSA1State, P1.GSA1BoardTrack = nil, nil
    end
    frames(2)
    return GSA1.Char
end
local function moveto(C, x, y) M.mchars[C.id].pos = Vector(x, y, 0) end
-- walk the character from where it is towards (x, y) at `speed` HU/s (the player's own stick: no walk model)
local function run_to(C, x, y, speed)
    local mc = M.mchars[C.id]
    for _ = 1, 2000 do
        local dx, dy = x - mc.pos.x, y - mc.pos.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 1 then break end
        local step = math.min(d, speed / 60)
        mc.pos = Vector(mc.pos.x + dx / d * step, mc.pos.y + dy / d * step, 0)
        frames(1)
    end
end
local function box_msgs(to) return msgs_s(B.NET.BOX, to or P1) end
local function last_box(to)
    local l = box_msgs(to)
    return l[#l]
end

-- 4. Board On: GO, the walk, the reach, took; refill, GONE, a released claim, a timeout, a spent box (items 3, 4) ------------
local C = spawn("sonic", 0, 0)
check(C ~= nil and C.kind == 0, "Sonic spawned (the mock module's world)")
if not C then return done() end
local E2 = place("gsa1_board_on", 600, 0, 0, 0)
local CE2 = CENTS[E2.idx]
local changes = {}
hook.Add("GSA1BoardChanged", "test", function(c, on, why) changes[#changes + 1] = (on and "on " or "off ") .. tostring(why) end)
do
    clear_msgs()
    BM.calls = {}
    run_to(C, 300, 0, 300)
    local before = #box_msgs()
    run_to(C, 480, 0, 300)                                   -- into the box (its edge at 472)
    local go = last_box()
    local b = C.board
    local w = b and b.walk
    local life = go and go.vals[9] or -1
    check(before == 0 and #box_msgs() == 1 and go and go.vals[2] == B.WHAT.GO and go.vals[1] == E2.idx and
        go.vals[4] == E2.GSA1Claim.id and go.vals[5].x == 600 and w ~= nil and w.idx == E2.idx and
        math.abs(life - (B.WalkDeadline(go.vals[5].x - P1.GSA1State.x) + B.CLAIM_EXTRA)) < 0.6,
        "a Sonic walking into a Board On box gets ONE GO (box %d, claim %d, the board's place, the claim's life %.1f s = the "
        .. "walk's deadline + 2) and his client starts the walk", E2.idx, go and go.vals[4] or -1, life)
    -- the stick towards the board in the tick's camera frame, 0.7 / 1.0, never below 0.6 (item 4)
    local sx, sy = GSA1.FilterStick(C, 0.3, -0.2)
    M.yaw = 90
    local rx, ry = GSA1.FilterStick(C, 0, 0)
    M.yaw = 200
    local ax, ay = GSA1.FilterStick(C, 0, 0)
    M.yaw = 0
    local e200x, e200y = math.sin(math.rad(200)) * 0.7, math.cos(math.rad(200)) * 0.7
    BM.speed = 1.2
    frames(1)                                               -- (BoardState's speed: the state after the last tick)
    local fx, fy = GSA1.FilterStick(C, 0, 0)
    BM.speed = 0
    frames(1)
    M.convars.gsa1_board_walk:SetString("1")
    local jx, jy = GSA1.FilterStick(C, 0, 0)
    M.convars.gsa1_board_walk:SetString("0")
    local p1 = { B.StickTowards(0, 0, 100, 0, 0, 0.7) }
    local p2 = { B.StickTowards(0, 0, 100, 0, 90, 0.7) }
    local p3 = { B.StickTowards(0, 0, 0, 100, 200, 0.7) }
    check(math.abs(sx) < 1e-6 and math.abs(sy - 0.7) < 1e-6 and math.abs(rx - 0.7) < 1e-6 and math.abs(ry) < 1e-6 and
        math.abs(ax - e200x) < 1e-6 and math.abs(ay - e200y) < 1e-6 and math.abs(fy - 1) < 1e-6 and
        math.abs(jy - 1) < 1e-6 and B.WalkStick(0) >= B.STICK_MIN and B.WalkStick(0) == 0.7 and
        math.abs(p1[2] - 0.7) < 1e-9 and math.abs(p2[1] - 0.7) < 1e-9 and math.abs(p3[1] - math.sin(math.rad(200)) * 0 -
        (0 * math.sin(math.rad(200)) - 1 * math.cos(math.rad(200))) * 0.7) < 1e-9,
        "the walk's stick replaces his own: towards the board ahead at camera yaw 0 (%.2f, %.2f), to the right at yaw 90 "
        .. "(%.2f, %.2f), at yaw 200 (%.2f, %.2f); 0.7 standing, 1.0 above 0.5 units a step (%.2f) and with "
        .. "gsa1_board_walk 1 (%.2f); never below 0.6", sx, sy, rx, ry, ax, ay, fy, jy)
    -- his buttons held back except jump (a jump held when it began is no press)
    local held = GSA1.FilterButtons(C, 2)
    check(held == 0 and C.board.walk ~= nil, "his buttons are held back during the walk (action %d -> %d)", 2, held)
    -- the walk itself (the mock's walk: 45 HU/s at a stick of 0.6-0.8)
    BM.walk = 45
    BM.calls = {}
    local t0 = M.T
    for _ = 1, 600 do
        frames(1)
        if C.board.on then break end
    end
    local took_at = M.T - t0
    BM.walk = nil
    local bc = bcalls("Board")
    local opts = bc[1] and bc[1][4] or {}
    local took = msgs_c(B.NET.TOOK)
    local st = msgs_c(B.NET.ST)
    check(#bc == 1 and bc[1][3] == true and opts.push == true and opts.terrain == 0 and opts.tails_jump == false and
        C.board.on and #took == 1 and took[1].vals[1] == E2.idx and took[1].vals[3] == go.vals[4] and E2:GetPresent() == false
        and E2:GetUsed() == 1 and math.abs(E2:GetRespawnAt() - (M.T + 5)) < 0.6 and #st == 1 and st[1].vals[1] == true and
        st[1].vals[2] == B.WHY.BOX and P1:GetNW2Bool(B.NW_RIDING, false) == true,
        "he walks to the board (%.1f s from the box's edge at 45 HU/s) and gets on with the box's options (Ice Cap's push, "
        .. "the map's surfaces); the server hears gsa1_board_took once: the board gone, 1 use, the refill in 5 s; "
        .. "gsa1_board_st on (a Board On box) -> the NW2 bool", took_at)
    check(B.hidden[E2.idx] ~= nil, "the lying board is hidden for him from the first held pair (review R.12)")
    -- the refill: back after 5 s; he stays inside, served: nothing is sent (review R.3)
    local n0 = #box_msgs()
    seconds(5.5)
    check(E2:GetPresent() == true and #box_msgs() == n0, "the board comes back after 5 s; a served rider inside gets "
        .. "nothing at the refill (%d messages)", #box_msgs() - n0)
end

-- 5. Board Off and the hand-over (item 8; gsa1_095_plan.md 4.8, review R.5) -------------------------------------------------
local function lefts_of(ply)
    local n, out = 0, {}
    for _, e in pairs(SENTS) do
        if e.cls == "gsa1_board_left" and (ply == nil or e:GetRider() == ply) then
            n = n + 1
            out[#out + 1] = e
        end
    end
    return n, out
end
local E3 = place("gsa1_board_off", 1000, 0, 0, 0)
do
    clear_msgs()
    BM.calls = {}
    undos = {}
    run_to(C, 1000, 0, 600)                                  -- riding into the Board Off box
    local off = last_box()
    frames(2)
    local bc = bcalls("Board")
    local st = msgs_c(B.NET.ST)
    check(off and off.vals[2] == B.WHAT.OFF and #bc == 1 and bc[1][3] == false and bc[1][4] == nil and not C.board.on and
        #st == 1 and st[1].vals[1] == false and st[1].vals[2] == B.WHY.OFF_BOX and st[1].vals[3] == E3.idx and
        E3:GetUsed() == 1 and P1:GetNW2Bool(B.NW_RIDING, true) == false,
        "riding into a Board Off box: OFF -> gsa1.Board(id, false) -> off -> gsa1_board_st (a Board Off box %d); the box "
        .. "counts its use (the server sent OFF: review R.3)", E3.idx)
    -- the kept board settles (30 steps), its pose goes to the server, which makes the decoration; the world frees its own
    seconds(0.7)
    local left = msgs_c(B.NET.LEFT)
    local n, ents = lefts_of(P1)
    local le = ents[1]
    local frees = bcalls("BoardFree")
    local ce = le and CENTS[le.idx]
    check(#left == 1 and n == 1 and le:GetKind() == 0 and le:GetVariant() == 0 and le:GetRider() == P1 and
        math.abs(le.pos.x - left[1].vals[1].x) < 1e-6 and ce ~= nil and ce:GetRider() == M.player and #frees == 1 and
        not C.board.st.kept and undos[1] and undos[1].text == "Undone G-SA1 left board" and undos[1].ply == P1,
        "when it settled: ONE gsa1_board_left with its pose (%.0f %.0f %.0f) -> the server's gsa1_board_left (Sonic's, "
        .. "variant 0, his; undo \"Undone G-SA1 left board\") -> its arrival frees the world's board (BoardFree %d)",
        left[1] and left[1].vals[1].x or 0, left[1] and left[1].vals[1].y or 0, left[1] and left[1].vals[1].z or 0, #frees)
    -- a forged use of an Off box: gsa1_board_st why 4 without the server's OFF counts nothing
    SB.StateMsg(P1, false, B.WHY.OFF_BOX, E3, 0)
    check(E3:GetUsed() == 1, "gsa1_board_st (why 4) without the server's OFF counts no use (%d)", E3:GetUsed())
    -- the cap (5 per player: the oldest goes) and the lifetime (120 s)
    local first = le
    for i = 1, 5 do
        seconds(1.1)
        SB.Left(P1, Vector(800 + i * 10, 50, 0), Angle(0, 0, 0), 0, 1, 0)
    end
    local n5 = lefts_of(P1)
    check(n5 == 5 and first.removed == true, "a sixth left board removes the oldest (%d left, the first removed %s)", n5,
        tostring(first.removed))
    local okb, whyb = SB.LeftOk(P1, Vector(99999, 0, 0), Angle(0, 0, 0), 0, 0)
    local okk = SB.LeftOk(P1, Vector(800, 0, 0), Angle(0, 0, 0), 3, 0)
    check(not okb and not okk, "a left board far from the character (%s) or of Knuckles' kind is refused", tostring(whyb))
    seconds(121)
    check(lefts_of(P1) == 0, "after gsa1_sv_board_left_time (120 s) the left boards are gone")
end
-- off / on within 0.3 s: the board got off is still handed over (EV_FREED 2: a new board replaced it; review R.5)
local function wheel_toggle() return B.Toggle(C, "the test") end
do
    clear_msgs()
    wheel_toggle()
    frames(2)
    local on1 = C.board.on
    wheel_toggle()
    frames(2)
    wheel_toggle()
    frames(3)
    local left = msgs_c(B.NET.LEFT)
    local n = lefts_of(P1)
    check(on1 and C.board.on and #left == 1 and n == 1 and C.board.pendingFree == nil,
        "off and on again within 0.3 s: the board got off still stays behind (one gsa1_board_left, made by the server; "
        .. "no BoardFree pending: libsa1 freed it for the new board)")
    -- a kept board that falls out of the land (EV_FREED 1): handed over with its last resting pose
    clear_msgs()
    wheel_toggle()
    frames(4)
    BM.fall = true
    frames(2)
    local left2 = msgs_c(B.NET.LEFT)
    check(#left2 == 1 and not C.board.st.kept, "a kept board that fell is handed over at once with its last resting pose "
        .. "(%d message)", #left2)
    -- gsa1_sv_board_left_max 0: every OFF asks libsa1 to remove the board, nothing is sent
    seconds(1.2)
    M.convars.gsa1_sv_board_left_max:SetString("0")
    SCV.gsa1_sv_board_left_max:SetString("0")
    wheel_toggle()
    frames(2)
    clear_msgs()
    BM.calls = {}
    wheel_toggle()
    seconds(2.5)
    local bc = bcalls("Board")
    check(#bc == 1 and bc[1][3] == false and type(bc[1][4]) == "table" and bc[1][4].remove == true and
        #msgs_c(B.NET.LEFT) == 0, "with gsa1_sv_board_left_max 0 the OFF passes remove = true and nothing is handed over")
    M.convars.gsa1_sv_board_left_max:SetString("5")
    SCV.gsa1_sv_board_left_max:SetString("5")
    seconds(1)
end

-- 6. claims with two players: GONE, a released claim, the jump cancel, leaving and coming back, a timeout, uses (review R.3) --
local function p2_at(x, y, kind)
    P2.GSA1Active, P2.GSA1Kind = true, kind or 0
    P2.GSA1State = { x = x, y = y, z = 0, time = M.T, kind = kind or 0 }
    frames(1)
end
local E4 = place("gsa1_board_on", 0, 1000, 0, 0)
do
    clear_msgs()
    moveto(C, 0, 600)
    frames(4)
    p2_at(0, 600)
    p2_at(0, 900)                                            -- P2 (another Sonic) into the box first
    local go2 = last_box(P2)
    local claim2 = go2 and go2.vals[4]
    run_to(C, 0, 900, 600)                                   -- then P1
    local gone = last_box(P1)
    check(go2 and go2.vals[2] == B.WHAT.GO and E4.GSA1Claim and E4.GSA1Claim.ply == P2 and gone and
        gone.vals[2] == B.WHAT.GONE and C.board.walk == nil and P1.GSA1BoardTrack.served[E4] == nil,
        "the first player gets the board (GO, claimed), the second GONE and stays unserved")
    -- P2 cancels (a jump): the claim is released, P1 (inside, unserved) gets GO; P2 gets nothing more
    local n2 = #box_msgs(P2)
    SB.Cancel(P2, E4, 0, claim2, B.CANCEL.JUMP)
    local go1 = last_box(P1)
    check(go1 and go1.vals[2] == B.WHAT.GO and E4.GSA1Claim and E4.GSA1Claim.ply == P1 and C.board.walk ~= nil and
        #box_msgs(P2) == n2, "a released claim re-tests the unserved player inside: P1 gets GO, P2 (who cancelled) nothing")
    -- P1 jumps: the walk ends (gsa1_board_cancel, why 1); no second GO while he stays in the box
    local walk = C.board.walk
    GSA1.FilterButtons(C, 0)
    GSA1.FilterButtons(C, 1)
    local cancel = msgs_c(B.NET.CANCEL)
    local n1 = #box_msgs(P1)
    frames(30)
    check(C.board.walk == nil and walk and #cancel == 1 and cancel[1].vals[4] == B.CANCEL.JUMP and E4.GSA1Claim == nil and
        #box_msgs(P1) == n1 and #box_msgs(P2) == n2, "a jump ends the walk (gsa1_board_cancel why 1, the claim released) "
        .. "and gives no second GO while he stays inside (review R.3)")
    -- leaving the box and coming back: GO again
    run_to(C, 0, 600, 600)
    frames(4)
    run_to(C, 0, 900, 600)
    local again = last_box(P1)
    check(again and again.vals[2] == B.WHAT.GO and #box_msgs(P1) == n1 + 1, "leaving the box and coming back gives GO "
        .. "again")
    -- the client's deadline: no walk model (he does not move): cancelled after max(4, d / 40 + 2) s
    clear_msgs()
    seconds(6)
    local c2 = msgs_c(B.NET.CANCEL)
    check(#c2 == 1 and c2[1].vals[4] == B.CANCEL.DEADLINE and C.board.walk == nil, "a walk that cannot reach the board "
        .. "ends at its deadline (gsa1_board_cancel why %s)", tostring(c2[1] and c2[1].vals[4]))
    -- the server's claim timeout (P2 never answers)
    run_to(C, 0, 600, 600)
    p2_at(0, 600)
    frames(10)
    p2_at(0, 900)
    local t2 = SB.sv.counts.timeouts
    local had = E4.GSA1Claim and E4.GSA1Claim.ply == P2
    seconds(B.WalkDeadline(100) + B.CLAIM_EXTRA + 1)
    check(had and E4.GSA1Claim == nil and SB.sv.counts.timeouts == t2 + 1 and E4:GetPresent() == true,
        "a claim nobody answers times out after the walk's deadline + 2 s; the board stays")
    -- a 1-use box: spent after one took (SPENT on the next entry, never refilled)
    local E5 = place("gsa1_board_on", 2000, 2000, 0, 0)
    E5:SetUses(1)
    p2_at(2000, 1500)
    p2_at(2000, 1950)
    local g5 = last_box(P2)
    local took = SB.Took(P2, E5, 0, g5 and g5.vals[4])
    p2_at(2000, 1500)
    seconds(2.2)
    p2_at(2000, 1950)
    local sp = last_box(P2)
    seconds(10)
    check(took and B.Spent(E5) and sp and sp.vals[2] == B.WHAT.SPENT and not E5:GetPresent() and E5:GetRespawnAt() == 0,
        "a 1-use box is spent after one took: SPENT, never refilled")
    -- Knuckles gets nothing; GSA1BoardBox may refuse; gsa1_sv_board 0: inert
    local E6 = place("gsa1_board_on", -2000, 2000, 0, 0)
    local nk = #box_msgs(P2)
    p2_at(-2000, 1500, 3)
    p2_at(-2000, 1950, 3)
    local knux = #box_msgs(P2) - nk
    p2_at(-2000, 1500, 0)
    S.hook.Add("GSA1BoardBox", "test", function() return false end)
    p2_at(-2000, 1950, 0)
    local hooked = #box_msgs(P2) - nk
    S.hook.Remove("GSA1BoardBox", "test")
    p2_at(-2000, 1500, 0)
    SCV.gsa1_sv_board:SetString("0")
    p2_at(-2000, 1950, 0)
    local inert = #box_msgs(P2) - nk
    SCV.gsa1_sv_board:SetString("1")
    check(knux == 0 and hooked == 0 and inert == 0 and E6:GetPresent(), "Knuckles gets nothing from a Board On box; "
        .. "GSA1BoardBox returning false refuses; gsa1_sv_board 0 leaves the boxes inert")
    -- "Reset this box" / gsa1_sv_board_reset: the board back, no use counted
    P2.admin = false
    single = false
    scmds.gsa1_sv_board_reset(P2)
    local still = B.Spent(E5)
    P2.admin = true
    scmds.gsa1_sv_board_reset(P2)
    single = true
    check(still and not B.Spent(E5) and E5:GetPresent() == true and E5:GetUsed() == 0, "\"Reset every Board box\": "
        .. "refused for a non-admin, then every box back as placed")
    P2.GSA1Active, P2.GSA1State = false, nil
    frames(2)
    E5:Remove()
    E6:Remove()
end

-- 6b. a 2,048 HU box (review R.3), carrying something, a hit, a rider's ground, Super Sonic, the sounds ----------------------
do
    -- the walk from the edge of a 2,048 HU box ends at the board, not at the claim's timeout
    local big = place("gsa1_board_on", 6000, 6000, 0, 0)
    big:SetWidth(2048)
    big:SetLength(2048)
    seconds(0.3)
    moveto(C, 4800, 6000)
    frames(4)
    clear_msgs()
    run_to(C, 4990, 6000, 300)
    local go = last_box()
    BM.walk = 45
    local t0 = M.T
    for _ = 1, 60 * 40 do
        frames(1)
        if C.board.on or not C.board.walk then break end
    end
    BM.walk = nil
    local took = #msgs_c(B.NET.TOOK)
    check(go and go.vals[2] == B.WHAT.GO and C.board.on and took == 1 and big:GetUsed() == 1,
        "a 2,048 HU box: the walk from its edge (%.0f s at 45 HU/s; deadline %.1f s, claim %.1f s) ends on the board, not "
        .. "at a timeout", M.T - t0, go and (go.vals[9] - B.CLAIM_EXTRA) or -1, go and go.vals[9] or -1)
    -- a rider entering a Board On box with its own ground: only the terrain changes (RIDING)
    big:SetGround(2)
    big:SetPresent(true)
    BM.calls = {}
    run_to(C, 4800, 6000, 600)
    frames(4)
    run_to(C, 5200, 6000, 600)
    local rb = bcalls("Board")
    local riding = last_box()
    check(riding and riding.vals[2] == B.WHAT.RIDING and #rb == 1 and rb[1][3] == true and rb[1][4].terrain == 1 and
        C.board.on, "a rider entering a Board On box gets RIDING: its ground (Ice Cap snow) applies, he keeps riding")
    wheel_toggle()
    seconds(1.5)
    big:Remove()
    frames(2)
    -- carrying something: the walk does not even start (gsa1_board_cancel at once)
    local E7 = place("gsa1_board_on", -6000, 6000, 0, 0)
    moveto(C, -6000, 5500)
    frames(4)
    clear_msgs()
    BM.held = 77
    run_to(C, -6000, 5950, 600)
    BM.held = 0
    local c1 = msgs_c(B.NET.CANCEL)
    check(#c1 == 1 and c1[1].vals[4] == B.CANCEL.REFUSED and C.board.walk == nil and E7.GSA1Claim == nil,
        "carrying something (gsa1.StateEx().held): no walk, gsa1_board_cancel at once, the claim released")
    -- a hit during the walk ends it
    run_to(C, -6000, 5500, 600)
    frames(4)
    clear_msgs()
    run_to(C, -6000, 5880, 600)
    frames(4)
    local walking = C.board.walk ~= nil
    BM.hurt = 0
    frames(3)
    BM.hurt = -1
    local c2 = msgs_c(B.NET.CANCEL)
    check(walking and #c2 == 1 and c2[1].vals[4] == B.CANCEL.HURT and C.board.walk == nil, "a hit during the walk "
        .. "ends it (gsa1_board_cancel why 4)")
    -- leaving the box (64 HU outside) during the walk ends it
    run_to(C, -6000, 5500, 600)
    frames(4)
    clear_msgs()
    run_to(C, -6000, 5880, 600)
    frames(4)
    local walking2 = C.board.walk ~= nil
    run_to(C, -6000, 5700, 2000)
    frames(2)
    local c3 = msgs_c(B.NET.CANCEL)
    check(walking2 and #c3 == 1 and c3[1].vals[4] == B.CANCEL.LEFT and C.board.walk == nil, "leaving the box (more "
        .. "than 64 HU outside it) ends the walk (gsa1_board_cancel why 3)")
    E7:Remove()
    frames(2)
    -- gsa1_sv_board_left_max 0 and a Board Off box: that OFF passes remove = true too (review R.5)
    M.convars.gsa1_sv_board_left_max:SetString("0")
    SCV.gsa1_sv_board_left_max:SetString("0")
    moveto(C, 700, 0)
    frames(4)
    wheel_toggle()
    frames(3)
    BM.calls = {}
    clear_msgs()
    run_to(C, 1000, 0, 600)
    frames(3)
    local ob = bcalls("Board")
    seconds(2.5)
    check(#ob == 1 and ob[1][3] == false and type(ob[1][4]) == "table" and ob[1][4].remove == true and
        #msgs_c(B.NET.LEFT) == 0 and not C.board.on, "with gsa1_sv_board_left_max 0 a Board Off box's OFF passes remove = "
        .. "true as well; nothing is handed over")
    M.convars.gsa1_sv_board_left_max:SetString("5")
    SCV.gsa1_sv_board_left_max:SetString("5")
    moveto(C, -3000, -3000)
    frames(4)
    -- Super Sonic: kind 8 never; General Gameplay / Sonic while Super only with gsa1_board_super 1 (review R.12)
    local fake8, gen = { kind = 8 }, { kind = 0, form = "general" }
    local a1, w1 = B.CanBoard(fake8, true)
    local a2, w2 = B.CanBoard(gen, true)
    M.convars.gsa1_board_super:SetString("1")
    local a3 = B.CanBoard(gen, true)
    local a4 = B.CanBoard({ kind = 0, superForm = true }, true)
    local a5 = B.CanBoard(fake8, true)
    M.convars.gsa1_board_super:SetString("0")
    local a6, w6 = B.CanBoard({ kind = 0 }, false)
    M.convars.gsa1_board:SetString("0")
    local a7, w7 = B.CanBoard({ kind = 2 }, true)
    M.convars.gsa1_board:SetString("1")
    check(not a1 and w1 == "Super Sonic doesn't ride a board" and not a2 and a3 and a4 and not a5 and not a6 and
        string.find(w6, "0.9.5", 1, true) and not a7 and string.find(w7, "Board page", 1, true),
        "Super Sonic (Vs. Perfect Chaos) never rides; General Gameplay Super Sonic and Sonic while Super only with "
        .. "gsa1_board_super 1; no module feature: \"%s\"; gsa1_board 0: \"%s\"", tostring(w6), tostring(w7))
    -- "Board sounds": sent at once on a change
    local n0 = #BM.sounds
    M.convars.gsa1_board_sounds:SetString("0")
    M.convars.gsa1_board_sounds:SetString("1")
    check(#BM.sounds == n0 + 2 and BM.sounds[n0 + 1] == false and BM.sounds[n0 + 2] == true, "\"Board sounds\" goes to "
        .. "the module at once (gsa1.BoardSounds false, then true)")
end

-- the 1 s fallback: a left board that never arrives still frees the world's board 1 s after sending
do
    local recv = recv_s[B.NET.LEFT]
    recv_s[B.NET.LEFT] = nil
    BM.calls = {}
    wheel_toggle()
    frames(2)
    wheel_toggle()
    seconds(0.7)
    local sent = #msgs_c(B.NET.LEFT)
    local f0 = #bcalls("BoardFree")
    seconds(1.1)
    local f1 = #bcalls("BoardFree")
    recv_s[B.NET.LEFT] = recv
    check(sent >= 1 and f0 == 0 and f1 == 1 and not C.board.st.kept, "a left board that never arrives: the world's own "
        .. "board is freed 1 s after sending (%d -> %d)", f0, f1)
    seconds(1.2)
end

-- 7. the wheel: open + B / RS (item 5; the owner's answer 14.1ad 1) --------------------------------------------------------
local function open_wheel()
    keys[KEY_TAB] = true
    frames(1)
end
local function close_keys()
    keys[KEY_TAB], keys[KEY_B] = nil, nil
    PAD.raw = 0
    frames(1)
end
CreateClientConVar("gsa1_super_key", "17", true, false)
CreateClientConVar("gsa1_super_pad", "0", true, false)
do
    moveto(C, -3000, -3000)
    frames(2)
    BM.calls = {}
    open_wheel()
    local was_open = W.open
    local hint = W.HintLine and W.HintLine() or ""
    local bind_open = M.run_hook("PlayerBindPress", M.player, "say_team", true, KEY_B)
    keys[KEY_B] = true
    frames(1)
    local bc = bcalls("Board")
    local closed, guard = not W.open, (W.guardTicks or 0) > 0
    close_keys()
    frames(2)
    local on = C.board.on
    check(was_open and #bc == 1 and bc[1][3] == true and type(bc[1][4]) == "table" and bc[1][4].push == false and
        bc[1][4].terrain == 0 and closed and guard and on and bind_open == true and
        string.find(hint, "B / RS: board", 1, true) ~= nil,
        "open wheel + the B key: ONE gsa1.Board(id, true, the wheel's options), the wheel closes and the press is held "
        .. "back; he rides; a Garry's Mod bind of B is swallowed while the wheel is open; the hint says \"B / RS: board\"")
    seconds(0.3)
    local bind_closed = M.run_hook("PlayerBindPress", M.player, "say_team", true, KEY_B)
    -- B with the wheel closed: nothing
    BM.calls = {}
    keys[KEY_B] = true
    frames(2)
    keys[KEY_B] = nil
    frames(1)
    check(#bcalls("Board") == 0 and bind_closed == nil, "the B key with the wheel closed does nothing (and its bind works)")
    -- open + RS (pad 0x80): off again
    PAD.connected = true
    open_wheel()
    PAD.raw = 0x80
    frames(1)
    local bc2 = bcalls("Board")
    local closed2 = not W.open
    close_keys()
    frames(2)
    check(#bc2 == 1 and bc2[1][3] == false and closed2 and not C.board.on, "open wheel + the right stick click: off, the "
        .. "wheel closes")
    -- the pad's B button still only cancels the wheel
    BM.calls = {}
    open_wheel()
    PAD.raw = 0x2000
    frames(1)
    local cancelled = not W.open
    close_keys()
    check(cancelled and #bcalls("Board") == 0, "the controller's B button still cancels the wheel (no board)")
    PAD.connected = false
    -- a held B when the wheel opens is no press
    BM.calls = {}
    keys[KEY_B] = true
    open_wheel()
    frames(2)
    local held_open = W.open
    close_keys()
    check(held_open and #bcalls("Board") == 0, "a B held while the wheel opens is no press")
    seconds(1.5)
end
-- the binders' refusals (the old key / button stays), the wheel key refuses the board key
do
    local r = { B.KeyRefused(KEY_TAB), B.KeyRefused(17), B.KeyRefused(107), B.KeyRefused(65), B.KeyRefused(15),
                B.KeyRefused(KEY_B) }
    RunConsoleCommand("gsa1_board_key", "67")
    local kept = M.convars.gsa1_board_key.v
    RunConsoleCommand("gsa1_board_pad", tostring(0x2000))
    local kept_pad = M.convars.gsa1_board_pad.v
    local p = { B.PadRefused(2), B.PadRefused(0x10000), B.PadRefused(0x0100), B.PadRefused(0x0200), B.PadRefused(0x2000),
                B.PadRefused(0x1000), B.PadRefused(0x0010), B.PadRefused(0x0040) }
    check(r[1] == "the wheel key" and r[2] == "the Super transformation key" and r[3] == "the face trigger" and
        r[4] and string.find(r[4], "jump") and r[5] and string.find(r[5], "interact") and r[6] == nil and kept == "12" and
        kept_pad == "128" and p[1] == "the wheel button" and p[2] == "the face trigger" and p[3] and p[4] and p[5] and p[6]
        and p[7] and p[8] == nil and W.KeyRefused(KEY_B) == "the board key",
        "the board key refuses TAB (%s), G (%s), the left mouse (the face trigger), a +jump key, +use; the button refuses the wheel "
        .. "button, LT, LB, RB, B, A, Start (LS is free); a refused choice keeps B / RS; the wheel key refuses B (%s)",
        tostring(r[1]), tostring(r[2]), tostring(W.KeyRefused(KEY_B)))
end
-- Knuckles: a toast, no board call, the wheel stays open; no hint
do
    local K = spawn("knuckles", -3000, -3000)
    BM.calls = {}
    open_wheel()
    local hint = W.HintLine and W.HintLine() or ""
    keys[KEY_B] = true
    frames(1)
    local still = W.open
    local toast = W.toastText or ""
    close_keys()
    check(K and K.kind == 3 and #bcalls("Board") == 0 and still and string.find(toast, "only Sonic and Tails", 1, true) and
        not string.find(hint, "board", 1, true), "Knuckles: the board key in the open wheel shows \"%s\", no gsa1.Board "
        .. "call, the wheel stays open; no board hint", toast)
    C = spawn("sonic", -3000, -3000)
end
-- the board rows refused while a kept board lies (review R.12)
do
    wheel_toggle()
    frames(2)
    wheel_toggle()
    frames(2)
    emotes = {}
    local kept = C.board.st.kept
    local rowref = W.PlayBody(C, { body = "a105", name = "s_sbjump1" }, 1, 1, "the test", nil, "sonic")
    local other = W.PlayBody(C, { body = "a75", name = "s_kimepose0" }, 1, 2, "the test", nil, "sonic")
    local toast = W.toastText or ""
    seconds(1.5)
    local freed = not C.board.st.kept
    local after = W.PlayBody(C, { body = "a105", name = "s_sbjump1" }, 1, 1, "the test", nil, "sonic")
    check(kept and rowref == false and other == true and freed and after == true and #emotes == 2 and
        emotes[1] == "a75" and emotes[2] == "a105", "while the board got off lies in his world, the wheel's board rows "
        .. "(Sonic 102-124) are refused (\"%s\"), others play; once it is handed over the row plays", toast)
end

-- 8. the hooks: re-created, teleported, respawned, switched, removed (item 7) ------------------------------------------------
do
    seconds(1.2)
    wheel_toggle()
    frames(3)
    BM.calls = {}
    local NC = GSA1.Recreate("upgrades changed")
    frames(3)
    local bc = bcalls("Board")
    check(NC and NC ~= C and #bc == 1 and bc[1][3] == true and NC.board.on, "re-created while riding (upgrades, the map's "
        .. "collision, a fault): on a new board at once (%d gsa1.Board)", #bc)
    C = NC
    BM.calls = {}
    local TC = GSA1.Recreate("teleported", Vector(-3500, -3000, 0), 0)
    frames(3)
    check(TC and #bcalls("Board") == 1 and TC.board.on, "teleported while riding: still on a board after it")
    C = TC
    -- a death on the board: back on foot (gsa1_board_respawn 0) / on a new board (1)
    BM.calls = {}
    M.run_hook("GSA1CharacterDied", C, 1)
    GSA1.Respawn("the test")
    frames(3)
    local foot = #bcalls("Board") == 0 and not GSA1.Char.board.on
    C = GSA1.Char
    wheel_toggle()
    frames(3)
    M.convars.gsa1_board_respawn:SetString("1")
    BM.calls = {}
    M.run_hook("GSA1CharacterDied", C, 1)
    GSA1.Respawn("the test")
    frames(3)
    local again = #bcalls("Board") == 1 and GSA1.Char.board.on
    M.convars.gsa1_board_respawn:SetString("0")
    C = GSA1.Char
    check(foot and again, "dying on a board: the respawn is on foot (gsa1_board_respawn 0), on a new board with 1")
    -- switched to Tails: on foot, the server hears it; removed: the same
    clear_msgs()
    BM.calls = {}
    local T2 = spawn("tails", -3000, -3000)
    local st = msgs_c(B.NET.ST)
    check(T2 and T2.kind == 2 and #bcalls("Board") == 0 and not T2.board.on and #st == 1 and st[1].vals[1] == false and
        P1:GetNW2Bool(B.NW_RIDING, true) == false, "switched to Tails while riding: on foot, gsa1_board_st off")
    C = T2
    wheel_toggle()
    frames(3)
    local tails_on = T2.board.on
    clear_msgs()
    GSA1.Remove(true)
    frames(1)
    local st2 = msgs_c(B.NET.ST)
    check(tails_on and #st2 == 1 and st2[1].vals[1] == false, "Tails rides too; removing the character sends "
        .. "gsa1_board_st off")
    -- the server takes that "off" although the player stopped being a character first (GSA1.Remove tells it so before)
    P1:SetNW2Bool(B.NW_RIDING, true)
    P1.GSA1Active = false
    local okoff = SB.StateMsg(P1, false, B.WHY.WHEEL, nil, 0)
    local okon = SB.StateMsg(P1, true, B.WHY.WHEEL, nil, 0)
    check(okoff and P1:GetNW2Bool(B.NW_RIDING, true) == false and not okon, "the server takes gsa1_board_st off from a "
        .. "player who just stopped being a character (the NW2 bool cleared), never on")
    C = spawn("sonic", -3000, -3000)
    -- a death on the board leaves no board behind (the respawn is a new world)
    wheel_toggle()
    frames(3)
    clear_msgs()
    C.death = { cause = 1, step = 0, at = SysTime() }
    M.run_hook("GSA1CharacterDied", C, 1)
    gsa1.Board(C.id, false)
    seconds(3)
    check(#msgs_c(B.NET.LEFT) == 0 and C.board.leaving == nil, "a death on the board leaves no board behind")
    C = spawn("sonic", -3000, -3000)
end

-- 9. the view: the speed field of view, the camera behind the board (items 9, 10) -----------------------------------------
do
    wheel_toggle()
    frames(2)
    BM.speed = 4
    frames(2)
    seconds(1)
    local base = M.fov
    local f_off = GSA1.view.fov
    M.convars.gsa1_board_fov:SetString("1")
    frames(2)
    local f1 = GSA1.view.fov
    seconds(1)
    local f_on = GSA1.view.fov
    local want = base + B.FovDegrees(4) - 70
    M.convars.gsa1_board_fov_mode:SetString("1")
    seconds(1)
    local f_abs = GSA1.view.fov
    M.convars.gsa1_board_fov_mode:SetString("0")
    -- chained: a previous override's view gets the fov
    local prev = B.prevView
    B.prevView = function(view) return { origin = Vector(1, 2, 3), angles = Angle(0, 0, 0), fov = 50 } end
    seconds(0.5)
    local f_chain = GSA1.view.fov
    local o_chain = GSA1.view.origin
    B.prevView = prev
    M.convars.gsa1_board_fov:SetString("0")
    seconds(1)
    local f_back = GSA1.view.fov
    BM.speed = 0
    check(math.abs(f_off - base) < 1e-6 and f1 > base and f1 - base < 2 * B.FOV_RATE / 60 + 1e-3 and
        math.abs(f_on - want) < 1e-3 and math.abs(f_abs - B.FovDegrees(4)) < 1e-3 and
        math.abs(f_chain - (50 + B.FovDegrees(4) - 70)) < 1e-3 and o_chain and o_chain.x == 1 and
        math.abs(f_back - base) < 1e-6,
        "the speed field of view: off -> %.2f (yours); on -> eased at 168.75 degrees a second to yours + (%.2f - 70) = %.2f; "
        .. "mode 1 -> the game's %.2f; a previous GSA1.ViewOverride's view gets it (%.2f); off -> back to %.2f",
        f_off, B.FovDegrees(4), f_on, f_abs, f_chain, f_back)
    check(math.abs(B.FovDegrees(0) - 70) < 0.01 and math.abs(B.FovDegrees(1) - 80.73) < 0.01 and
        math.abs(B.FovDegrees(4) - 91.45) < 0.01 and math.abs(B.FovDegrees(7) - 98.38) < 0.01 and
        math.abs(B.FovDegrees(9) - 100) < 0.01, "the game's speed field of view (0C90327E): 70.00 / 80.73 / 91.45 / 98.38 / "
        .. "100.00 degrees at 0 / 1 / 4 / 7 / 9 units a step (board095_gsa1.md 8.1)")
    -- the camera behind the board: the view yaw eases towards the drawn yaw; a mouse turn pauses it for 1 s; off: never
    local cmd = { va = Angle(0, 90, 0), mx = 0, sets = 0 }
    function cmd:GetViewAngles() return Angle(self.va) end
    function cmd:SetViewAngles(a) self.va = Angle(a) self.sets = self.sets + 1 end
    function cmd:GetMouseX() return self.mx end
    function cmd:GetMouseY() return 0 end
    C.drawYaw = 0
    B.cam.last = SysTime()
    M.T = M.T + 1 / 60
    B.CameraMove(cmd)
    local y1 = cmd.va.y
    local want1 = 90 - 90 * (1 - math.exp(-(1 / 60) / B.CAM_TAU))
    for _ = 1, 60 do
        M.T = M.T + 1 / 60
        C.drawYaw = 0
        B.CameraMove(cmd)
    end
    local y60 = cmd.va.y
    cmd.va, cmd.mx = Angle(0, 90, 0), 3
    M.T = M.T + 1 / 60
    B.CameraMove(cmd)
    cmd.mx = 0
    local sets0 = cmd.sets
    for _ = 1, 50 do
        M.T = M.T + 1 / 60
        B.CameraMove(cmd)
    end
    local paused = cmd.sets == sets0 and cmd.va.y == 90
    for _ = 1, 20 do
        M.T = M.T + 1 / 60
        B.CameraMove(cmd)
    end
    local resumed = cmd.va.y < 90
    M.convars.gsa1_board_camera:SetString("0")
    cmd.va = Angle(0, 90, 0)
    local s0 = cmd.sets
    for _ = 1, 30 do
        M.T = M.T + 1 / 60
        B.CameraMove(cmd)
    end
    M.convars.gsa1_board_camera:SetString("1")
    check(math.abs(y1 - want1) < 1e-6 and y60 < 90 * math.exp(-1 / B.CAM_TAU) + 1 and paused and resumed and
        cmd.sets == s0, "the camera behind the board: the view yaw eases towards the board's (90 -> %.2f in a frame, %.1f "
        .. "after 1 s: time constant 0.4 s); a mouse turn pauses it for 1 s; off: never", y1, y60)
    wheel_toggle()
    seconds(2)
end

-- 10. the page: every row of 5.8, the binders, the free buttons (item 6) ----------------------------------------------------
local function panel_recorder()
    local P = { calls = {}, made = {} }
    local function ctl(kind, extra)
        local o = { kind = kind, choices = {} }
        function o:AddChoice(text, data) self.choices[#self.choices + 1] = { text, data } end
        function o:SetText(t) self.text = t end
        function o:SetConVar(c) self.convar = c end
        function o:SetTall() end
        function o:InvalidateLayout() end
        P.made[#P.made + 1] = o
        return o
    end
    local mt = {}
    mt.__index = function(t, k)
        return function(self, ...)
            local args = { ... }
            P.calls[#P.calls + 1] = { k, unpack(args) }
            if k == "ComboBox" or k == "Help" or k == "ControlHelp" or k == "CheckBox" or k == "NumSlider" or
                k == "Button" or k == "TextEntry" then
                return ctl(k)
            end
        end
    end
    return setmetatable({}, mt), P
end
local VG = {}
VG.__index = function(t, k)
    if k == "SetConVar" then return function(self, c) self.convar = c end end
    return function() end
end
vgui.Create = function(cls) return setmetatable({ cls = cls }, VG) end
spawnmenu.CreateContentIcon = function() end
do
    local panel, P = panel_recorder()
    local ok, err = pcall(B.BuildPage, panel)
    local bound = {}
    for _, c in ipairs(P.calls) do
        if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then bound[c[3]] = true end
        if c[1] == "AddItem" and type(c[2]) == "table" and c[2].convar then bound[c[2].convar] = true end
        if c[1] == "Button" and type(c[3]) == "string" then bound[c[3]] = true end
    end
    for _, o in ipairs(P.made) do
        if o.kind == "ComboBox" and o.OnSelect then
            local before = {}
            for n, cvo in pairs(M.convars) do before[n] = cvo.v end
            pcall(o.OnSelect, o, 1, "x", "1")
            for n, cvo in pairs(M.convars) do
                if cvo.v ~= before[n] then
                    bound[n] = true
                    cvo.v = before[n]
                end
            end
        end
    end
    local want = { "gsa1_board", "gsa1_board_key", "gsa1_board_pad", "gsa1_board_terrain", "gsa1_board_walk",
                   "gsa1_board_push", "gsa1_board_camera", "gsa1_board_fov", "gsa1_board_fov_mode", "gsa1_board_sounds",
                   "gsa1_board_respawn", "gsa1_board_tails_jump", "gsa1_board_super", "gsa1_board_box_show",
                   "gsa1_sv_board", "sbox_maxgsa1_triggers", "gsa1_sv_board_left_time", "gsa1_sv_board_left_max",
                   "gsa1_board_toggle", "gsa1_sv_board_reset" }
    local missing = {}
    for _, n in ipairs(want) do if not bound[n] then missing[#missing + 1] = n end end
    local text = {}
    for _, c in ipairs(P.calls) do if c[1] == "Help" or c[1] == "ControlHelp" then text[#text + 1] = tostring(c[2]) end end
    local pt = table.concat(text, " ")
    local page
    for _, p in ipairs(GSA1.MenuPages or {}) do if p.id == "board" then page = p end end
    check(ok and #missing == 0 and page and page.order == 275 and page.needs and page.needs.feature == "board" and
        string.find(pt, "Known limits", 1, true) ~= nil, "the Board page (order 275, needs the feature \"board\") has a "
        .. "control for every row of 5.8 - check boxes, sliders, the binder, the combos, the two buttons - and the known "
        .. "limits%s%s", ok and "" or (": " .. tostring(err)), #missing > 0 and (": missing " .. table.concat(missing, " ")) or "")
    check(B.FreeButtons() == "LS, D-pad up / left / right", "the page's free-button line with the defaults: \"%s\"",
        B.FreeButtons())
    local status = table.concat(B.StatusLines(), " | ")
    check(string.find(status, "Sonic: on foot", 1, true) ~= nil, "the status line: %s", status)
    -- the Emote wheel page's two rows bound to the same settings
    local wp, WP = panel_recorder()
    local okw, werr = pcall(W.BuildPage, wp)
    local wb, wc = false, false
    for _, c in ipairs(WP.calls) do
        if c[1] == "AddItem" and type(c[2]) == "table" and c[2].convar == "gsa1_board_key" then wb = true end
    end
    for _, o in ipairs(WP.made) do
        if o.kind == "ComboBox" and o.OnSelect then
            local before = {}
            for n, cvo in pairs(M.convars) do before[n] = cvo.v end
            pcall(o.OnSelect, o, 1, "x", "64")
            if M.convars.gsa1_board_pad.v == "64" then wc = true end
            for n, cvo in pairs(M.convars) do cvo.v = before[n] end
        end
    end
    check(okw and wb and wc, "the Emote wheel page has the two rows: the board key binder and the board button combo%s",
        okw and "" or (": " .. tostring(werr)))
end

-- 11. the spawn tab: "Rings and Item Boxes" then "Board", although cl_board.lua loads first (item 11; review R.10) ----------
do
    local T = GSA1.SpawnTab
    for _, c in ipairs(GSA1.Objects.CLASSES) do list.Set("SpawnableEntities", c.class, { PrintName = c.title }) end
    for _, c in ipairs(B.CLASSES) do list.Set("SpawnableEntities", c.class, { PrintName = c.title }) end
    local nodes = {}
    local tree = { AddNode = function(self, name, icon)
        local n = { name = name, icon = icon }
        nodes[#nodes + 1] = n
        n.DoClick = function() end
        return n
    end }
    local okp, perr = pcall(T.Populate, { SwitchPanel = function() end }, tree)
    local board_cat
    for _, c in ipairs(T.LATER or {}) do if c.name == "Board" then board_cat = c end end
    local items = board_cat and T.Items(board_cat) or {}
    check(okp and nodes[1] and nodes[1].name == "Rings and Item Boxes" and nodes[2] and nodes[2].name == "Board" and
        #items == 2 and items[1].spawnname == "gsa1_board_on" and items[2].spawnname == "gsa1_board_off" and
        items[1].material == "entities/gsa1_board_on.png" and board_cat.icon and string.find(board_cat.icon, "^icon16/"),
        "the G-SA1 tab: \"%s\" then \"%s\" (T.LATER), the Board category lists both classes with their icons (a 16 x 16 "
        .. "silkicon)%s", nodes[1] and nodes[1].name or "?", nodes[2] and nodes[2].name or "?", okp and "" or (": " .. tostring(perr)))
end

-- 12. the drawing: the lying board always, the volumes while editing, the left boards (gsa1_095_plan.md 6.4 task 4) --------
do
    XV.adds, XV.removes, XV.draws = {}, {}, {}
    B.hidden = {}
    frames(1)
    local key = "box:" .. E2.idx
    local live = XV.live[key]
    drawn.wire = 0
    CE2:Draw(0)
    CE2:DrawTranslucent(1)
    local d = XV.draws[#XV.draws]
    local playing_wire = drawn.wire
    check(live and live.kind == 0 and live.type == 0x100 and live.params[1] == 0 and d and d.key == key and
        math.abs(d.pos.z - 3) < 1e-6 and d.pos.x == 600 and playing_wire == 0, "the board lying in a Board On box is "
        .. "always drawn (Sonic's BOARD picture at the board's place, lifted by the picture's -minz: z %.1f); no volume "
        .. "while playing", d and d.pos.z or -1)
    M.convars.gsa1_board_box_show:SetString("1")
    drawn.wire = 0
    CE2:DrawTranslucent(1)
    local always = drawn.wire
    M.convars.gsa1_board_box_show:SetString("0")
    C = spawn("tails", -3000, -3000)
    frames(1)
    local tails_desc = XV.live[key]
    local Ctab = GSA1.Char
    GSA1.Remove(true)
    frames(1)
    drawn.wire = 0
    CE2:DrawTranslucent(1)
    local nochar = drawn.wire
    check(always == 1 and tails_desc and tails_desc.kind == 2 and nochar == 1 and Ctab ~= nil, "the volume while editing "
        .. "(no character) and with \"Show the boxes: always\"; a Tails player sees Tails' board in the box")
    E2:SetPresent(false)
    frames(1)
    local gone = XV.live[key] == nil
    E2:SetPresent(true)
    frames(1)
    -- a left board at its pose
    P1.GSA1State = { x = 0, y = 0, z = 0, time = M.T }
    local le = SB.Left(P1, Vector(10, 20, 30), Angle(5, 40, 0), 2, 0, 0)
    local cle = le and CENTS[le.idx]
    XV.draws = {}
    if cle then cle:Draw(0) end
    local ld = XV.draws[1]
    check(gone and cle and ld and ld.key == "left:" .. le.idx and XV.live[ld.key].kind == 2 and ld.pos.z == 30 and
        ld.ang.y == 40, "the lying board goes while the box is refilling; a left board is drawn at its own pose with its "
        .. "kind (Tails')")
    if le then le:Remove() end
    check(XV.live["left:" .. (le and le.idx or 0)] == nil, "a removed left board's picture goes")
    C = spawn("sonic", -3000, -3000)
end

-- 13. the garbage while riding (item 12): the board's own part of a frame under 256 bytes ----------------------------------
do
    wheel_toggle()
    frames(2)
    BM.speed = 3
    M.convars.gsa1_board_fov:SetString("1")
    local cmd = { va = Angle(0, 90, 0) }
    function cmd:GetViewAngles() return self.va end
    function cmd:SetViewAngles(a) self.va = a end
    function cmd:GetMouseX() return 0 end
    function cmd:GetMouseY() return 0 end
    local view = { origin = Vector(), angles = Angle(), fov = 90 }
    local st = {}
    for _ = 1, 30 do                                         -- warm up (tables made once)
        B.Poll(C, C.state, 1 / 60)
        GSA1.FilterStick(C, 0, 1)
        GSA1.FilterButtons(C, 1)
        B.CameraMove(cmd)
        B.FovApply(view, C)
        B.Think()
        CE2:Draw(0)
        CE2:DrawTranslucent(1)
        M.T = M.T + 1 / 60
    end
    XV.quiet = true
    collectgarbage("collect")
    collectgarbage("stop")
    local k0 = collectgarbage("count")
    local n = 120
    for _ = 1, n do
        B.Poll(C, C.state, 1 / 60)
        GSA1.FilterStick(C, 0, 1)
        GSA1.FilterButtons(C, 1)
        B.CameraMove(cmd)
        view.fov = 90
        B.FovApply(view, C)
        B.Think()
        CE2:Draw(0)
        CE2:DrawTranslucent(1)
        M.T = M.T + 1 / 60
    end
    local per = (collectgarbage("count") - k0) * 1024 / n
    collectgarbage("restart")
    XV.quiet = false
    M.convars.gsa1_board_fov:SetString("0")
    BM.speed = 0
    info("the board's Lua garbage per frame while riding (BoardState, the stick and button filters, the camera, the field "
        .. "of view, the extras, a Board On box's draws; the mock's userdata are tables here): %.0f bytes", per)
    check(per < 256, "the board's garbage per frame while riding is under 256 bytes (%.0f)", per)
    wheel_toggle()
    seconds(2)
end

-- 14. the mock against the module's board_api.txt (5.4, review R.6): 095-gsa1-boardmod's feat_board_binding_test.cpp writes
-- it (tab-separated records: feature, function, option, const, field, info, reason, preview, surface, behaviour) whenever
-- the snapshot header has SA1_API_BOARD; then it must exist and the mock must match it (a missing file is a failure)
do
    local groot = string.gsub(tests, "[/" .. string.char(92) .. "]tests$", "")
    local hdr = host_read(groot .. "/build/deps/include/libsa1.h") or ""
    if not string.find(hdr, "#define SA1_API_BOARD", 1, true) then
        info("board_api.txt: the snapshot's libsa1.h has no SA1_API_BOARD yet - the check is skipped (5.4's rule)")
    else
        local api = host_read(groot .. "/build/x86_64-windows/board_api.txt")
        local wrong, n = {}, { feature = 0, ["function"] = 0, option = 0, const = 0, field = 0 }
        if not api then
            wrong[1] = "no build/x86_64-windows/board_api.txt"
        else
            local mockst = G.BoardState(C.id, {})
            local seen_field, reasons = {}, {}
            for line in string.gmatch(api, "[^\r\n]+") do
                if string.sub(line, 1, 1) ~= "#" then
                    local f = {}
                    for part in string.gmatch(line .. "\t", "([^\t]*)\t") do f[#f + 1] = part end
                    local kind = f[1]
                    if n[kind] then n[kind] = n[kind] + 1 end
                    if kind == "feature" and (f[2] == "board" or f[2] == "preview") then
                        if tonumber(G.FEATURES[f[2]]) ~= tonumber(f[3]) then wrong[#wrong + 1] = "feature " .. f[2] end
                    elseif kind == "function" then
                        if type(G[f[2]]) ~= "function" then wrong[#wrong + 1] = "function " .. f[2] end
                    elseif kind == "option" and f[2] == "Board" then
                        if OPT_TYPES[f[3]] ~= f[4] then wrong[#wrong + 1] = "option " .. f[3] end
                    elseif kind == "const" then
                        local tab, name = string.match(f[2] or "", "^(%u+)%.([%u_]+)$")
                        local t = tab == "BOARD" and G.BOARD or (tab == "PREVIEW" and G.PREVIEW or nil)
                        local v = t and t[name]
                        local a, b = string.match(f[3] or "", "^(-?[%d.]+),(-?[%d.]+)$")
                        if a then
                            if not (type(v) == "table" and v[1] == tonumber(a) and v[2] == tonumber(b)) then
                                wrong[#wrong + 1] = "const " .. tostring(f[2])
                            end
                        elseif v ~= tonumber(f[3]) then
                            wrong[#wrong + 1] = "const " .. tostring(f[2])
                        end
                    elseif kind == "reason" then
                        reasons[f[3] or ""] = true
                    elseif kind == "field" and f[2] == "BoardState" then
                        seen_field[f[3]] = true
                        local ty = string.match(f[4] or "", "^(%a+)")
                        local mv = mockst[f[3]]
                        if f[3] ~= "reason" and mv ~= nil and type(mv) ~= ty then wrong[#wrong + 1] = "field " .. f[3] end
                    end
                end
            end
            if n.field > 0 then
                for _, fld in ipairs({ "on", "pending", "held", "kept", "settled", "mode", "action", "speed", "terrain",
                                       "push_steps", "kind", "variant", "x", "y", "z", "pitch", "yaw", "roll", "still",
                                       "refused", "reason", "freed", "freed_why" }) do
                    if not seen_field[fld] then wrong[#wrong + 1] = "BoardState." .. fld .. " (the client reads it)" end
                end
            end
            if n["function"] < 6 or n.const < 10 then wrong[#wrong + 1] = "too few records" end
            -- the client's own refusal words are the module's (feat/sh_board.lua B.CanBoard)
            local _, wk = B.CanBoard({ kind = 3 }, true)
            local _, ws = B.CanBoard({ kind = 8 }, true)
            if next(reasons) and not (reasons[wk] and reasons[ws] and reasons["carrying something"]) then
                wrong[#wrong + 1] = "the refusal words (" .. tostring(wk) .. " / " .. tostring(ws) .. ")"
            end
        end
        check(#wrong == 0, "this test's mock module matches build/x86_64-windows/board_api.txt (%d functions, %d options, %d "
            .. "constants, %d BoardState fields)%s", n["function"], n.option, n.const, n.field,
            #wrong > 0 and (": " .. table.concat(wrong, "; ")) or "")
    end
end

-- 15. nothing went wrong -----------------------------------------------------------------------------------------------------
do
    local seen = {}
    for _, c in ipairs(changes) do seen[c] = true end
    check(seen["on box"] and seen["off off box"] and seen["on wheel"] and seen["off wheel"] and seen["on re-created"] and
        seen["off removed"], "GSA1BoardChanged(C, on, why) on every edge with 5.5's words (%d edges: box, off box, wheel, "
        .. "re-created, removed, ...)", #changes)
end
check(#BM.bad == 0, "every call into the mock module had the arguments of 5.4%s", #BM.bad > 0 and (": " .. BM.bad[1]) or "")
check(#M.reported == 0 and not B.pollError and not B.thinkError, "no Lua error%s",
    #M.reported > 0 and (": " .. M.reported[1]) or "")
check(#BM.sounds >= 1 and BM.sounds[1] == true, "gsa1.BoardSounds(gsa1_board_sounds) is sent once the module has the board")
return done()
