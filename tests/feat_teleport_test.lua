-- feat_teleport_test.lua - map teleporters and the hidden player (0.9.2a; sadc docs/research/gsa1_091a_teleport.md T0 /
-- T4 / T5 with its review R.4: R-b, R-c, R-d, R-f), run by tests/lua_host.c in Garry's Mod's own LuaJIT:
--   lua_host tests/feat_teleport_test.lua <tests dir> <addon/lua dir>
-- The research model (sadc/build/research/teleport/review/teleport_review_model.lua, the stricter one of the review)
-- with the REAL files: both realms in one process as single player. The client is the addon's client files over
-- tests/lua_mock.lua with a kinematic character (the stick relative to the camera yaw, as libsa1's input; the booth's
-- walls and the floors from the owner's gm_genesis: review R.2.1 / R.3.1); the server is the addon's sh_config.lua,
-- sh_net.lua, sv_gsa1.lua and feat/sh_teleport.lua + feat/sv_teleport.lua in their own environment. Per server tick
-- (66.67 Hz): the messages that arrived (half the round trip later), the user command's view angles (uplink latency;
-- not while a FIXANGLE is pending), StartCommand, ProcessImpacts with the map's trigger_teleports (Source 2013's
-- CTriggerTeleport::Touch -> Teleport: the destination's origin and angles, SnapEyeAngles = a FIXANGLE, EF_NOINTERP;
-- UNVERIFIED for Garry's Mod's branch, the doc's model), PlayerPostThink, Think; a FIXANGLE reaches the client half the
-- round trip after the tick. The owner walks east into the booth of ent 893, lets go when the camera jumps, stands 3 s
-- turning the mouse, walks 1 s, stands 2 s.
-- 0.9.1a (no detection) gives 63-64 teleports, as many FIXANGLEs and the character stuck at the booth's wall; 0.9.2a:
--   * at 0, 60 and 150 ms: exactly 1 teleport and 1 FIXANGLE; the character re-created at the destination - right after,
--     within 2 units of (128 -12240) at the platform's floor z -14848 (+-1) - facing the destination's 90; the server
--     player within 12 units of it 3 s later; its rings and lives kept; a "teleport" log line with the cause;
--   * a chain (the destination inside a second teleporter): both followed, the character at the second destination;
--   * a loop (two teleporters sending to each other): at most 4 re-creations within 2 s and one "teleport loop" line;
--   * gsa1_sv_teleports 0 (R-f): 0 teleports, 0 FIXANGLEs, the camera follows the mouse (>= 350 of 362 degrees), the
--     character walks into the column;
--   * a dying character (R-b): one teleport, no re-creation, the respawn at the spawn point, one life lost;
--   * no G-SA1 teleport for: 0.9.2's respawn as a character (L6's SetPos), G-SA1's own respawn 2,000 units away, a dead or
--     seated player moved; gsa1_follow_player 0 (R-c): 1 message, confirmed, 0 re-creations; a client that never
--     confirms: the follow resumes after 1 s, one counted.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local CHECKS, FAILS = 0, 0
local function check(cond, fmt, ...)
    CHECKS = CHECKS + 1
    local msg = string.format(fmt, ...)
    host_write((cond and "  ok    " or "  FAIL  ") .. msg .. "\n")
    if not cond then FAILS = FAILS + 1 end
    return cond
end
local function info(fmt, ...) host_write("  info  " .. string.format(fmt, ...) .. "\n") end
host_write("G-SA1 feat_teleport_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")\n")

-- the map (bsp_ents.py / booth_geom.py on the owner's gm_genesis; review R.2.1, R.3.1) --------------------------------
local T893 = { mins = { 1994, -9862, -8832 }, maxs = { 2006, -9850, -8720 }, dest = { 128, -12240, -14846 },
               ang = 90, target = "genesis_acf_teleport_dest" }
local TB_CHAIN = { mins = { 100, -12270, -14850 }, maxs = { 160, -12210, -14740 }, dest = { -10512, 12808, -8190 },
                   ang = 180, target = "genesis_teleporter2_dest" }
local TB_LOOP = { mins = { 100, -12270, -14850 }, maxs = { 160, -12210, -14740 }, dest = { 2000, -9856, -8832 },
                  ang = 0, target = "genesis_spawn_column" }
local BOOTH = { x0 = 1968, x1 = 2040, y0 = -9908, y1 = -9804, stop = 20 }   -- the inner faces; Sonic stops 20 units off
local START = { 1830, -9870, -8832 }
local FLOORS = {
    { x0 = 1400, x1 = 2040, y0 = -10600, y1 = -9400, z = -8832 },            -- the spawn room and the booth
    { x0 = 88, x1 = 168, y0 = -12272, y1 = -12208, z = -14848 },              -- the destination's platform
    { x0 = -400, x1 = 600, y0 = -12700, y1 = -11800, z = -14976 },            -- below its edges
    { x0 = -10700, x1 = -10300, y0 = 12600, y1 = 13000, z = -8192 },          -- the second destination
}
local SPEED = 300                     -- HU/s (a jog: the log's actions 9-11)

local function floor_z(x, y)
    for _, f in ipairs(FLOORS) do
        if x >= f.x0 and x <= f.x1 and y >= f.y0 and y <= f.y1 then return f.z end
    end
    return nil
end

-- one world: the mock client, the real server files, the loopback --------------------------------------------------------
-- opt: rtt (ms), triggers (list), sv_teleports (0/1), follow_player (0/1), client_feature (false: no teleport receiver)
local function new_world(opt)
    local W = { opt = opt, log = {} }
    local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
    M.root = root
    W.M = M
    local LAT = (opt.rtt or 0) / 2000
    local TRIG = {}
    for _, t in ipairs(opt.triggers or { T893 }) do
        TRIG[#TRIG + 1] = { mins = Vector(t.mins[1], t.mins[2], t.mins[3]), maxs = Vector(t.maxs[1], t.maxs[2], t.maxs[3]),
                            dest = Vector(t.dest[1], t.dest[2], t.dest[3]), ang = Angle(0, t.ang, 0), target = t.target }
    end
    W.TRIG = TRIG
    local HULL_MIN, HULL_MAX = Vector(-16, -16, 0), Vector(16, 16, 72)

    -- loopback: client -> server
    local Q, cur = {}, nil
    local RECV, STRINGS = {}, {}
    local function push(v) if cur then cur.vals[#cur.vals + 1] = v end end
    net.Start = function(name) cur = { name = string.lower(name), vals = {} } end
    net.WriteVector = function(v) push(Vector(v)) end
    net.WriteAngle = function(a) push(Angle(a)) end
    net.WriteUInt, net.WriteFloat, net.WriteBool, net.WriteString = push, push, push, push
    net.WriteNormal = function(v) push(Vector(v)) end
    net.SendToServer = function()
        if cur then cur.at = M.T Q[#Q + 1] = cur end
        cur = nil
    end
    util.NetworkStringToID = function(n) return STRINGS[n] and 1 or 0 end
    -- server -> client
    local TOCLIENT, CRECV = {}, {}
    local cin, cpos = {}, 0
    local function crd() cpos = cpos + 1 return cin[cpos] end
    net.Receive = function(name, fn) CRECV[string.lower(name)] = fn end
    net.ReadVector, net.ReadUInt, net.ReadFloat, net.ReadBool, net.ReadAngle, net.ReadString = crd, crd, crd, crd, crd, crd
    W.CRECV = CRECV

    -- the server realm
    local S = setmetatable({}, { __index = _G })
    S.SERVER, S.CLIENT = true, false
    local SH = {}
    S.hook = {
        Add = function(ev, name, fn) SH[ev] = SH[ev] or {} SH[ev][name] = fn end,
        Remove = function(ev, name) if SH[ev] then SH[ev][name] = nil end end,
        Run = function(ev, ...)
            for _, fn in pairs(SH[ev] or {}) do
                local a, b = fn(...)
                if a ~= nil then return a, b end
            end
        end,
    }
    local inbuf, inpos = {}, 0
    local function rd() inpos = inpos + 1 return inbuf[inpos] end
    local sout = nil
    local function spush(v) if sout then sout.vals[#sout.vals + 1] = v end end
    W.sent = 0
    S.net = {
        Receivers = RECV,
        Receive = function(name, fn) RECV[string.lower(name)] = fn end,
        ReadBool = rd, ReadUInt = rd, ReadFloat = rd, ReadVector = rd, ReadNormal = rd, ReadAngle = rd, ReadString = rd,
        Start = function(name) sout = { name = string.lower(name), vals = {} } end,
        Send = function(to)
            if sout then
                sout.at = M.T
                TOCLIENT[#TOCLIENT + 1] = sout
                if sout.name == "gsa1_teleport" then W.sent = W.sent + 1 end
            end
            sout = nil
        end,
        Broadcast = function() sout = nil end, SendPVS = function() sout = nil end, SendOmit = function() sout = nil end,
        WriteBool = spush, WriteUInt = spush, WriteFloat = spush, WriteString = spush,
        WriteVector = function(v) spush(Vector(v)) end, WriteAngle = function(a) spush(Angle(a)) end,
    }
    S.util = {
        AddNetworkString = function(n) STRINGS[n] = true end,
        NetworkStringToID = function(n) return STRINGS[n] and 1 or 0 end,
        IsInWorld = function() return true end,
        TraceHull = function(t) return { StartSolid = false, Hit = false, HitPos = Vector(t.endpos) } end,
    }
    local SCV = {}
    S.CreateConVar = function(name, default)
        local cv = { v = tostring(default) }
        function cv:GetBool() return tonumber(self.v) ~= 0 end
        function cv:GetFloat() return tonumber(self.v) or 0 end
        function cv:GetInt() return math.floor(tonumber(self.v) or 0) end
        function cv:GetString() return self.v end
        function cv:SetString(v) self.v = tostring(v) end
        SCV[name] = cv
        return cv
    end
    S.GetConVar = function(name) return SCV[name] end
    S.weapons = { Register = function() end }
    S.Model = function(m) return m end
    S.MOVETYPE_NONE, S.MOVETYPE_WALK, S.MOVETYPE_NOCLIP, S.MOVETYPE_OBSERVER = 0, 2, 8, 10
    S.MASK_PLAYERSOLID = 33636363
    S.EF_NOINTERP = 8
    S.OBS_MODE_NONE = 0
    S.AddCSLuaFile = function() end
    S.NULL = NULL
    S.engine = { TickInterval = function() return 1 / 66.666667 end }
    local trig_ents = {}
    for i, t in ipairs(TRIG) do
        trig_ents[i] = { IsValid = function() return true end, WorldSpaceAABB = function() return Vector(t.mins), Vector(t.maxs) end,
                         GetInternalVariable = function(self, k) if k == "target" then return t.target end end,
                         GetClass = function() return "trigger_teleport" end }
    end
    S.ents = { FindByClass = function(c) return c == "trigger_teleport" and trig_ents or {} end, FindInBox = function() return {} end }
    S.concommand = { Add = function() end }

    local function new_player()
        local p = { pos = Vector(0, 0, 0), movetype = 2, nodraw = false, alive = true, nw = {}, setpos = 0,
                    eye = Angle(0, 0, 0), vel = Vector(0, 0, 0), noint = false, fixangle = false, invehicle = false }
        function p:IsValid() return true end
        function p:IsPlayer() return true end
        function p:GetPos() return Vector(self.pos) end
        function p:SetPos(v) self.pos = Vector(v) self.setpos = self.setpos + 1 end
        function p:EyeAngles() return Angle(self.eye) end
        function p:SetEyeAngles(a) self.eye = Angle(a) self.fixangle = true end
        function p:GetMoveType() return self.movetype end
        function p:SetMoveType(m) self.movetype = m end
        function p:GetNoDraw() return self.nodraw end
        function p:SetNoDraw(b) self.nodraw = b end
        function p:IsEffectActive(f) return f == S.EF_NOINTERP and self.noint end
        function p:DrawShadow() end
        function p:DrawWorldModel() end
        function p:DrawViewModel() end
        function p:FlashlightIsOn() return false end
        function p:Flashlight() end
        function p:SetNW2Bool(k, v) self.nw[k] = v end
        function p:GetNW2Bool(k, d) if self.nw[k] == nil then return d end return self.nw[k] end
        function p:GetActiveWeapon() return NULL end
        function p:GetWeapon() return NULL end
        function p:HasWeapon() return false end
        function p:Give() return NULL end
        function p:SelectWeapon() end
        function p:SetActiveWeapon() end
        function p:DropObject() end
        function p:SwitchToDefaultWeapon() end
        function p:Alive() return self.alive end
        function p:InVehicle() return self.invehicle end
        function p:GetObserverMode() return 0 end
        function p:GetHull() return Vector(HULL_MIN), Vector(HULL_MAX) end
        function p:SetVelocity(v) self.vel = self.vel + v end
        function p:GetVelocity() return Vector(self.vel) end
        return p
    end
    local A = new_player()
    W.A = A
    S.player = { GetAll = function() return { A } end }
    local function sinclude(rel)
        local fn, err = host_load(host_read(root .. "/" .. rel), "sv:" .. rel)
        if not fn then error(err) end
        setfenv(fn, S)
        fn()
    end
    rawset(S, "GSA1", {})
    sinclude("gsa1/sh_config.lua")
    sinclude("gsa1/sh_net.lua")
    sinclude("gsa1/sv_gsa1.lua")
    sinclude("gsa1/feat/sh_teleport.lua")
    sinclude("gsa1/feat/sv_teleport.lua")
    local SG = rawget(S, "GSA1")
    W.SG, W.S, W.SCV = SG, S, SCV
    W.TS = SG.Teleport.Stats
    if opt.sv_teleports ~= nil then SCV.gsa1_sv_teleports:SetString(opt.sv_teleports) end
    S.hook.Run("InitPostEntity")

    -- the client realm
    local G = M.module({})
    GSA1 = nil
    local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
    if not ok_load then error("the client files: " .. tostring(err_load)) end
    W.G = G
    if opt.client_feature == false then CRECV["gsa1_teleport"] = nil end
    if opt.follow_player == 0 then GetConVar("gsa1_follow_player"):SetString("0") end
    local K = {}
    W.K = K
    W.creates = 0
    local create0, tick0, state0, render0 = G.Create, G.Tick, G.GetState, G.Render
    G.Create = function(kind, pos, yaw, ups, rings, extras)
        local id = create0(kind, pos, yaw, ups, rings)
        W.creates = W.creates + 1
        local z = floor_z(pos.x, pos.y) or (pos.z - 1)
        K[id] = { pos = Vector(pos.x, pos.y, z), yaw = yaw or 0, vel = Vector(0, 0, 0), rings = 0, lives = 4,
                  created = Vector(pos.x, pos.y, z), cyaw = yaw }
        W.lastCreate = K[id]
        return id
    end
    local function walls(c)
        if c.pos.x > BOOTH.x0 - BOOTH.stop and c.pos.y > -10000 and c.pos.y < -9700 then
            c.pos.y = math.Clamp(c.pos.y, BOOTH.y0 + BOOTH.stop, BOOTH.y1 - BOOTH.stop)
            c.pos.x = math.min(c.pos.x, BOOTH.x1 - BOOTH.stop)
        end
    end
    G.Tick = function(id, sx, sy, yaw, buttons, dt, raw)
        local n, err = tick0(id, sx, sy, yaw, buttons, dt)
        local c = K[id]
        if not n or not c then return n, err end
        if c.dying then sx, sy = 0, 0 end
        local r = math.rad(yaw or 0)
        local fx, fy = math.cos(r), math.sin(r)
        local rx, ry = math.sin(r), -math.cos(r)
        local wx, wy = fx * (sy or 0) + rx * (sx or 0), fy * (sy or 0) + ry * (sx or 0)
        local m = math.sqrt(wx * wx + wy * wy)
        c.vel = Vector(wx * SPEED, wy * SPEED, 0)
        for _ = 1, 2 * n do
            c.pos.x, c.pos.y = c.pos.x + c.vel.x / 60, c.pos.y + c.vel.y / 60
            walls(c)
            c.pos.z = floor_z(c.pos.x, c.pos.y) or c.pos.z
        end
        if m > 0.1 then c.yaw = math.deg(math.atan2(wy, wx)) end
        return n
    end
    G.GetState = function(id, out)
        out = state0(id, out)
        local c = K[id]
        if out and c then
            out.x, out.y, out.z, out.yaw, out.vx, out.vy, out.vz = c.pos.x, c.pos.y, c.pos.z, c.yaw, c.vel.x, c.vel.y, 0
            out.mode, out.action = (c.vel.x ~= 0 or c.vel.y ~= 0) and 2 or 1, (c.vel.x ~= 0 or c.vel.y ~= 0) and 10 or 0
            out.ground = true
        end
        return out
    end
    G.Render = function(id, alpha)
        local gen, bgen = render0(id, alpha)
        local c = K[id]
        if not gen or not c then return gen, bgen end
        return gen, bgen, c.pos.x, c.pos.y, c.pos.z, c.yaw, true, 1, 0, false
    end
    -- the game's events of a test (a death, the restart request)
    W.events = {}
    G.PollEvents = function(out)
        out = out or {}
        local n = 0
        for _, e in ipairs(W.events) do
            n = n + 1
            local t = out[n] or {}
            out[n] = t
            t.type, t.id, t.bank, t.x, t.y, t.z, t.arg, t.step, t.character = e.type, 0, 0, 0, 0, 0, e.arg or 0, 0,
                GSA1.Char and GSA1.Char.id or 0
        end
        out[n + 1] = nil
        out.count = n
        W.events = {}
        return out
    end
    -- rings and lives (round 5's and 0.9.1's module functions)
    G.StateEx = function(id, out) local c = K[id] if not c then return nil end out = out or {} out.rings = c.rings return out end
    G.AddRings = function(id, n) local c = K[id] if not c then return nil, "no such character" end c.rings = c.rings + n return true end
    G.GetLives = function(id) local c = K[id] return c and c.lives or nil end
    G.SetLives = function(id, n) local c = K[id] if not c then return nil end c.lives = n return n end
    G.SetCompanion = function() return true end
    G.SetGameOption = function() return true end
    GSA1.LoadModule()
    GSA1.World.state, GSA1.World.info = "applied", { min_z = -16000 }
    GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -16000 }
    -- the session log's lines (GSA1.Log), kept for the checks
    local log0 = GSA1.Log
    GSA1.Log = function(kind, fmt, ...)
        local ok, line = pcall(string.format, fmt, ...)
        W.log[#W.log + 1] = { kind = kind, line = ok and line or tostring(fmt) }
        if log0 then return log0(kind, fmt, ...) end
    end

    -- the engine: the trigger_teleports
    local TICK = 1 / 66.666667
    local server_time = M.T
    W.tele = { n = 0 }
    local YH, FQ = {}, {}
    W.FIXN, W.snaps = 0, 0
    local function overlaps(p, t)
        local a0, a1 = p + HULL_MIN, p + HULL_MAX
        return a0.x <= t.maxs.x and a1.x >= t.mins.x and a0.y <= t.maxs.y and a1.y >= t.mins.y and a0.z <= t.maxs.z and
            a1.z >= t.mins.z
    end
    local function process_impacts(p)
        if not p.alive then return end
        for _, t in ipairs(TRIG) do
            if overlaps(p.pos, t) then
                p.pos = Vector(t.dest)
                p.eye = Angle(t.ang)
                p.fixangle = true
                p.noint = true
                W.tele.n = W.tele.n + 1
                return
            end
        end
    end
    local cmd = { GetViewAngles = function() return Angle(A.eye) end }
    function W.char_pos()
        local C = GSA1.Char
        return C and K[C.id] and K[C.id].pos or nil
    end
    local function server_ticks(now)
        while server_time + TICK <= now do
            server_time = server_time + TICK
            local keep = {}
            for _, m in ipairs(Q) do
                if m.at + LAT < server_time - 1e-9 then
                    local fn = RECV[m.name]
                    if fn then
                        inbuf, inpos = m.vals, 0
                        fn(#m.vals * 8, A)
                    end
                else
                    keep[#keep + 1] = m
                end
            end
            Q = keep
            if not A.fixangle then           -- pl.v_angle = the user command's angles (uplink latency)
                for i = #YH, 1, -1 do if YH[i].t + LAT <= server_time + 1e-9 then A.eye = Angle(0, YH[i].yaw, 0) break end end
            end
            S.hook.Run("StartCommand", A, cmd)
            if W.beforeImpacts then W.beforeImpacts(A) end
            process_impacts(A)
            S.hook.Run("PlayerPostThink", A)
            S.hook.Run("Think")
            A.noint = false
            if A.fixangle then FQ[#FQ + 1] = { at = server_time, yaw = A.eye.y, p = A.eye.p } A.fixangle = false end
        end
    end
    function W.frame()
        local dt = 1 / 60
        local now = M.T + dt
        server_ticks(now)
        M.player.pos = Vector(A.pos)
        local fkeep = {}
        for _, f in ipairs(FQ) do
            if f.at + LAT <= now + 1e-9 then
                W.FIXN = W.FIXN + 1
                if math.abs(math.NormalizeAngle(M.yaw - f.yaw)) > 1 then W.snaps = W.snaps + 1 end
                M.yaw, M.pitch = f.yaw, f.p
            else
                fkeep[#fkeep + 1] = f
            end
        end
        FQ = fkeep
        local tc, later = TOCLIENT, {}
        TOCLIENT = {}
        for _, m in ipairs(tc) do
            if m.at + LAT <= M.T + dt + 1e-9 then
                local fn = CRECV[m.name]
                if fn then
                    cin, cpos = m.vals, 0
                    fn(#m.vals * 8)
                end
            else
                later[#later + 1] = m
            end
        end
        for _, m in ipairs(later) do TOCLIENT[#TOCLIENT + 1] = m end
        if W.input then W.input() end
        M.frame(dt)
        YH[#YH + 1] = { t = M.T, yaw = M.yaw }
    end
    function W.run(seconds, input)
        W.input = input
        local t1 = M.T + seconds
        while M.T < t1 - 1e-9 do W.frame() end
        W.input = nil
    end
    function W.logs(pat)
        local out = {}
        for _, l in ipairs(W.log) do
            if string.find(l.line, pat, 1, true) then out[#out + 1] = l.line end
        end
        return out
    end
    -- spawn Sonic at the room's start, as the owner did
    M.player.pos = Vector(START[1], START[2], START[3] - 4)
    A.pos = Vector(M.player.pos)
    M.yaw = 0
    GSA1.Spawn("sonic")
    W.run(20 / 60)
    return W
end

-- the owner at the booth: walk east, let go when the camera jumps (or in the booth), stand 3 s turning the mouse (back
-- towards the booth; "spin": +2 degrees a frame, the review's 362-degree turn), walk 1 s, stand 2 s
local function owner_booth(W, mode, on_frame)
    local M = W.M
    local phase, phase_t, t0 = "walk", M.T, M.T
    local res = { seen = 0, turned = 0, maxx = -1e9 }
    local lastyaw
    local function input()
        local cp = W.char_pos()
        local t = M.T - phase_t
        if phase == "walk" then
            M.forward = 10000
            if (cp and cp.x >= 1990) or W.snaps > 0 then phase, phase_t = "stand1", M.T end
        elseif phase == "stand1" then
            M.forward = 0
            if mode == "spin" then
                M.yaw = M.yaw + 2
                res.turned = res.turned + 2
            else
                M.yaw = M.yaw + math.Clamp(math.NormalizeAngle(0 - M.yaw), -2, 2)
            end
            if t >= 3 then
                phase, phase_t = "walk2", M.T
                local c = W.char_pos()
                res.after = { char = c and Vector(c), server = Vector(W.A.pos) }
            end
        elseif phase == "walk2" then
            M.forward = 10000
            if t >= 1 then phase, phase_t = "stand2", M.T end
        elseif phase == "stand2" then
            M.forward = 0
            if t >= 2 then phase = "done" end
        end
        if phase == "stand1" and lastyaw then res.seen = res.seen + math.NormalizeAngle(M.yaw - lastyaw) end
        lastyaw = M.yaw
        if cp then res.maxx = math.max(res.maxx, cp.x) end
        if on_frame then on_frame(W, res, phase) end
    end
    while phase ~= "done" and M.T - t0 < 20 do
        W.input = input
        W.frame()
    end
    W.input = nil
    res.phase = phase
    return res
end

local function near_xy(p, x, y, tol) return p and math.abs(p.x - x) <= tol and math.abs(p.y - y) <= tol end

-- 1. gm_genesis' ACF teleporter at 0, 60 and 150 ms round trips ------------------------------------------------------
for _, rtt in ipairs({ 0, 60, 150 }) do
    host_write(string.format("the ACF teleporter (ent 893 -> ent 946), round trip %d ms:\n", rtt))
    local W = new_world({ rtt = rtt })
    local first = GSA1.Char
    W.K[first.id].rings = 37
    local res = owner_booth(W, "back")
    local NC = GSA1.Char
    local arr = W.lastCreate
    check(W.tele.n == 1 and W.FIXN == 1 and W.snaps == 1, "one teleport (%d), one FIXANGLE reached the client (%d), the "
        .. "camera turned once (%d snaps) [0.9.1a: 63-64 of each]", W.tele.n, W.FIXN, W.snaps)
    check(W.creates == 2 and arr and near_xy(arr.created, 128, -12240, 2) and math.abs(arr.created.z + 14848) <= 1 and
        math.abs(math.NormalizeAngle((arr.cyaw or 0) - 90)) < 0.5,
        "the character re-created at the destination right away: (%.1f %.1f %.1f), facing %.1f (the destination's 90)",
        arr and arr.created.x or 0, arr and arr.created.y or 0, arr and arr.created.z or 0, arr and arr.cyaw or -1)
    local a = res.after
    local gap = a and a.char and (a.server - a.char):Length() or 1e9
    check(gap < 12, "3 s later the server player is with the character (%.1f units; the character at (%.0f %.0f %.0f))",
        gap, a and a.char and a.char.x or 0, a and a.char and a.char.y or 0, a and a.char and a.char.z or 0)
    local NK = NC and W.K[NC.id]
    check(NC and NC ~= first and NK and NK.rings == 37 and NK.lives == 4, "rings and lives kept (%s rings, %s lives)",
        tostring(NK and NK.rings), tostring(NK and NK.lives))
    local tl = W.logs("teleport: Sonic from")
    check(#tl == 1 and string.find(tl[1], "cause: trigger_teleport -> genesis_acf_teleport_dest", 1, true) ~= nil and
        string.find(tl[1], "re-created", 1, true) ~= nil, "the session log: %s", tl[1] or "no teleport line")
    local TS = W.TS
    check(TS.detected == 1 and TS.sent == 1 and TS.acked == 1 and TS.timeouts == 0,
        "server: %d detected, %d sent, %d confirmed, %d without a confirmation; %d stale packets dropped while waiting",
        TS.detected, TS.sent, TS.acked, TS.timeouts, TS.dropped)
    check(#W.M.reported == 0, "no Lua error (%s)", W.M.reported[1] or "none")
end

-- 2. a chain: the destination lies inside a second teleporter (review R.3.4) ------------------------------------------
do
    host_write("a chain of two teleporters (the first destination inside the second teleporter), 60 ms:\n")
    local W = new_world({ rtt = 60, triggers = { T893, TB_CHAIN } })
    local res = owner_booth(W, "back")
    local a = res.after
    check(W.tele.n == 2 and W.FIXN == 2 and a and near_xy(a.char, -10512, 12808, 2) and (a.server - a.char):Length() < 12,
        "both followed: %d teleports, %d FIXANGLEs; the character at (%.0f %.0f %.0f) (the second destination -10512 "
        .. "12808), the server player %.1f units from it", W.tele.n, W.FIXN, a and a.char and a.char.x or 0,
        a and a.char and a.char.y or 0, a and a.char and a.char.z or 0, a and a.char and (a.server - a.char):Length() or -1)
end

-- 3. a loop: two teleporters that send to each other ----------------------------------------------------------------
do
    host_write("a loop (the destination inside a teleporter that sends back), 60 ms:\n")
    local W = new_world({ rtt = 60, triggers = { T893, TB_LOOP } })
    local first_at, made2
    owner_booth(W, "back", function(W2, res, phase)
        if W2.tele.n > 0 and not first_at then first_at = W2.M.T end
        if first_at and not made2 and W2.M.T >= first_at + 2 then made2 = W2.creates - 1 end
    end)
    local loops = W.logs("teleport loop at")
    check((made2 or 99) <= 4 and #loops == 1 and W.TS.loops == 1,
        "%d engine teleports; the character re-created %s times in the first 2 s (at most 4), %d \"teleport loop\" line(s); "
        .. "server: %d sent, %d not sent", W.tele.n, tostring(made2), #loops, W.TS.sent, W.TS.suppressed)
end

-- 4. "Map teleporters move my character" off (review R-f) -------------------------------------------------------------
for _, rtt in ipairs({ 0, 60, 150 }) do
    local W = new_world({ rtt = rtt, sv_teleports = "0" })
    local res = owner_booth(W, "spin")
    check(W.tele.n == 0 and W.FIXN == 0 and res.seen >= 350 and res.maxx >= 1990 and W.TS.kept_out > 0,
        "gsa1_sv_teleports 0, %d ms: %d teleports, %d FIXANGLEs; the camera followed %.0f of %.0f degrees; the character "
        .. "walked to x %.0f (the column at 1994-2006); %d spots in the teleporter not taken", rtt, W.tele.n, W.FIXN, res.seen,
        res.turned, res.maxx, W.TS.kept_out)
end

-- 5. a dying character (review R-b) ----------------------------------------------------------------------------------
do
    host_write("a character that dies at the teleporter, 60 ms:\n")
    local W = new_world({ rtt = 60 })
    local M = W.M
    local died, restart_at, t0 = false, nil, M.T
    while M.T - t0 < 9 do
        W.input = function()
            local cp = W.char_pos()
            if not died then
                M.forward = 10000
                if cp and cp.x >= 1978 then
                    died = true
                    W.K[GSA1.Char.id].dying = true
                    W.events[#W.events + 1] = { type = 6, arg = 1 }     -- SA1_EVENT_DEATH, hit with no rings
                    restart_at = M.T + 2
                end
            else
                M.forward = 0
                if restart_at and M.T >= restart_at then
                    restart_at = nil
                    W.events[#W.events + 1] = { type = 7 }              -- SA1_EVENT_RESTART
                end
            end
        end
        W.frame()
    end
    W.input = nil
    local cp = W.char_pos()
    local NK = GSA1.Char and W.K[GSA1.Char.id]
    local conf = W.logs("confirmed only (the character is dying")
    check(died and W.tele.n == 1 and W.creates == 2 and #conf == 1 and near_xy(cp, START[1], START[2], 2) and NK and
        NK.lives == 3 and (W.A.pos - cp):Length() < 12,
        "the teleport fired %d time(s); confirmed only (%d line); the character respawned at its spawn point (%.0f %.0f), "
        .. "%d characters made (the spawn and the respawn: no re-creation at the destination); lives 4 -> %s; the server "
        .. "player %.1f units from it; %d packets from the teleporter dropped", W.tele.n, #conf, cp and cp.x or 0,
        cp and cp.y or 0, W.creates, tostring(NK and NK.lives), cp and (W.A.pos - cp):Length() or -1, W.TS.stayed)
end

-- 6. moves that are not teleports, and the clients that do not follow ---------------------------------------------------
do
    host_write("moves G-SA1 makes, a dead or seated player, follow off, a client that never confirms:\n")
    local W = new_world({ rtt = 0 })
    local M, A, S = W.M, W.A, W.S
    local function still() M.forward = 0 end
    W.run(1, still)
    local sent0 = W.sent
    -- 0.9.2's L6: the player respawns as the character, the server puts it at the character's position
    A.GSA1SpawnAsChar = { pos = Vector(START[1] + 2000, START[2], START[3]), kind = 0 }
    S.hook.Run("PlayerSpawn", A)
    W.run(1, still)
    local l6 = W.sent - sent0
    -- G-SA1's own moves: the character is 2,000 units away at once, then respawns at its spawn point
    local C = GSA1.Char
    W.K[C.id].pos = Vector(START[1] - 2000, START[2], START[3])
    W.run(0.5, still)
    GSA1.Respawn("test")
    W.run(1, still)
    local own = W.sent - sent0 - l6
    -- a dead player moved (a jumpscare), then the gamemode's respawn (the character's player again within 2 s)
    A.alive = false
    A.pos = A.pos + Vector(500, 0, 0)
    W.run(0.5, still)
    local dead = W.sent - sent0 - l6 - own
    A.alive = true
    S.hook.Run("PlayerSpawn", A)
    W.run(2.5, still)
    local after_spawn = W.sent - sent0 - l6 - own - dead
    -- a seated player moved
    A.invehicle = true
    local back = Vector(A.pos)
    A.pos = A.pos + Vector(0, 500, 0)
    W.run(0.5, still)
    local seated = W.sent - sent0 - l6 - own - dead - after_spawn
    A.pos = back
    A.invehicle = false
    W.run(0.5, still)
    check(l6 == 0 and own == 0 and dead == 0 and after_spawn == 0 and seated == 0 and W.creates == 2,
        "no teleport message for: the respawn as a character (%d), G-SA1's own 2,000-unit move and respawn (%d), a dead "
        .. "player moved (%d) and its respawn (%d), a seated player moved (%d); %d characters made (the spawn, the "
        .. "respawn)", l6, own, dead, after_spawn, seated, W.creates)
    -- "Server moves my player along" off (review R-c): the server cannot see it - one message, confirmed, no re-creation
    GetConVar("gsa1_follow_player"):SetString("0")
    local s1, c1 = W.sent, W.creates
    A.pos = A.pos + Vector(400, 0, 0)                 -- another addon's SetPos
    W.run(1, still)
    local conf = W.logs("\"Server moves my player along\" is off")
    check(W.sent - s1 == 1 and W.creates == c1 and #conf == 1, "gsa1_follow_player 0: %d message, confirmed (%d line), %d "
        .. "re-creations", W.sent - s1, #conf, W.creates - c1)
    GetConVar("gsa1_follow_player"):SetString("1")
    W.run(1.5, still)
    -- a client without the feature never confirms: the follow resumes after 1 s, counted
    W.CRECV["gsa1_teleport"] = nil
    local t1, s2 = W.TS.timeouts, W.sent
    A.pos = A.pos + Vector(500, 300, 0)
    W.run(1.6, still)
    local cp = W.char_pos()
    check(W.sent - s2 == 1 and W.TS.timeouts - t1 == 1 and cp and (A.pos - cp):Length() < 12,
        "a client that never confirms: %d message, %d without a confirmation, then the old follow (the server player %.1f "
        .. "units from the character)", W.sent - s2, W.TS.timeouts - t1, cp and (A.pos - cp):Length() or -1)
    check(#M.reported == 0, "no Lua error (%s)", M.reported[1] or "none")
    -- the rules
    local P = GSA1.Teleport
    local times, past = {}, false
    for i = 1, 5 do local _, p = P.LoopCount(times, 100 + i * 0.1) past = p end
    local _, later = P.LoopCount(times, 103)
    check(P.NextGen(15) == 0 and P.NextGen(3) == 4 and P.IsTeleport(32, false) and not P.IsTeleport(31, false) and
        P.IsTeleport(2, true) and not P.IsTeleport(0.5, true) and P.Turned(0, 90) and not P.Turned(10, 10.3) and past and
        not later, "the rules: the 4-bit generation wraps, 32 units (1 with EF_NOINTERP), the view turned, the 5th within "
        .. "2 s is a loop")
    -- T5: the Character page's controls
    local opt
    for _, o in ipairs(GSA1.CharacterOptions or {}) do if o.id == "teleport" then opt = o end end
    local boxes = {}
    if opt then
        local panel = setmetatable({}, { __index = function(t, k)
            return function(self, label, cvar) if k == "CheckBox" then boxes[#boxes + 1] = cvar end return setmetatable({},
                { __index = function() return function() end end }) end
        end })
        opt.builder(panel)
    end
    check(table.concat(boxes, " ") == "gsa1_sv_teleports gsa1_teleport_keep_speed" and GSA1.CONVARS.gsa1_sv_teleports and
        GSA1.CONVARS.gsa1_sv_teleports.server and GSA1.CONVARS.gsa1_teleport_keep_speed,
        "the Character page: %s (every new ConVar has a control; gsa1_sv_teleports is a server setting)",
        table.concat(boxes, ", "))
end

host_write(string.format("\n%d checks, %d failed\n", CHECKS, FAILS))
return FAILS == 0
