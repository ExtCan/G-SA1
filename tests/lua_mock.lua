-- lua_mock.lua - a mock of the Garry's Mod client for the addon's Lua, run in Garry's Mod's own LuaJIT by
-- tests/lua_host.c (build.py --test, Windows). Loaded by the test scripts:
--   local M = host_load(host_read(tests_dir .. "/lua_mock.lua"), "lua_mock.lua")()
--   M.root = <addon/lua directory>; M.load("gsa1/sh_config.lua"); ...
-- It provides the GMod globals the client files use (hooks, ConVars, console commands, an in-memory DATA folder,
-- Vector / Angle, render / mesh / cam / surface / draw, CreateMaterial, GetRenderTargetEx, entities, a local player)
-- with a controllable clock (M.T: SysTime, RealTime), and a mock of the module (M.module(): the gsa1 table, a character
-- whose draws can change every game pair, as during the Light Speed charge). M.frame(dt) runs one client frame the way
-- Garry's Mod does: Think, CreateMove, CalcView, the character entity's Draw and DrawTranslucent, PostRender.
-- G0 (the feature seam): include / AddCSLuaFile (M.included, M.cslua), file.Find on the "LUA" path (the addon's real
-- files under M.root through host_list, plus M.virtual[path] = source for test files that exist only in the test), the
-- spawn menu's options recorded in M.menu, FCVAR_* constants, gsa1.FEATURES in the mock module (opts.features).
-- 0.8.0: Model, weapons.Register / GetStored (the scripted weapons registered, M.weapons), NULL, the local player's
-- active weapon (M.player.active) and NW2 values, render.GetViewSetup / GetRenderTarget (M.view_setup, M.render_target;
-- nil unless a test sets them) - the shared file registers the character's empty hands (sh_net.lua, gsa1_060_weapon.md
-- review R.3.1) and the session log describes the views that draw the character (cl_log.lua, F4).
-- 0.9.2 (092-gsa1-char): util.PointContents (M.contents(pos) -> CONTENTS_* bits, 0 = empty) and the CONTENTS_* constants,
-- the local player's Alive (M.player.alive: false = dead), the user command's GetButtons / SetButtons (M.keys in, M.cmdOut
-- = the buttons left after the hooks), the mock module's host flags and host camera in Tick (M.ticks: the last tick's
-- arguments), the start rings in Create (M.creates), the game's water in GetState (M.mchars[id].water_attr /
-- water_level), the module's 0.9.2 constants (opts.host_flags = false / opts.host_camera = true change them).
-- No GMod code or data is used; the mock only follows the documented function signatures.
local M = {
    T = 1000.0, frameNo = 0, dt = 1 / 60, paused = false, ui = false, focus = true,
    console = {}, reported = {}, hooks = {}, cmds = {}, convars = {}, cvcb = {}, files = {}, appends = 0,
    classes = {}, entities = {}, materials = {}, nmaterials = 0, rts = {}, nrts = 0, calls = {},
    pitch = 10, yaw = 0, fov = 92.5, scrw = 3440, scrh = 1440, root = "addon/lua",
    material_cost = 0, draw_cost = 0, virtual = {}, included = {}, cslua = {}, menu = {}, weapons = {},
}
local noop = function() end
local function count(name) M.calls[name] = (M.calls[name] or 0) + 1 end

-- clock and frames
function SysTime() return M.T end
RealTime = SysTime
CurTime = SysTime
function FrameNumber() return M.frameNo end
function FrameTime() return M.paused and 0 or M.dt end
function RealFrameTime() return M.dt end
VERSION, VERSIONSTR, BRANCH = 251015, "2025.10.15", "x86-64"
CLIENT, SERVER = true, false

-- console
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    host_write(table.concat(t, " ") .. "\n")
end
function MsgC(...)
    local t = {}
    for _, v in ipairs({ ... }) do if type(v) == "string" then t[#t + 1] = v end end
    M.console[#M.console + 1] = table.concat(t)
end
Msg = MsgC
function ErrorNoHalt(e) M.reported[#M.reported + 1] = tostring(e) end
ErrorNoHaltWithStack = ErrorNoHalt
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
color_white, color_black = Color(255, 255, 255), Color(0, 0, 0)

-- GMod's additions to the standard libraries
function math.Clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
function math.NormalizeAngle(a) return (a + 180) % 360 - 180 end
function string.Trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
function string.StartWith(s, p) return string.sub(s, 1, #p) == p end

-- Vector / Angle (tables with metatables; GMod's are userdata)
local VMT = {}
VMT.__index = VMT
function Vector(x, y, z)
    if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, VMT) end
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT)
end
function VMT.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function VMT.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function VMT.__mul(a, b)
    if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end
    return Vector(a.x * b, a.y * b, a.z * b)
end
function VMT.__unm(a) return Vector(-a.x, -a.y, -a.z) end
function VMT:Set(v) self.x, self.y, self.z = v.x, v.y, v.z end
function VMT:SetUnpacked(x, y, z) self.x, self.y, self.z = x, y, z end
function VMT:Add(v) self.x, self.y, self.z = self.x + v.x, self.y + v.y, self.z + v.z end
function VMT:Sub(v) self.x, self.y, self.z = self.x - v.x, self.y - v.y, self.z - v.z end
function VMT:Mul(k) self.x, self.y, self.z = self.x * k, self.y * k, self.z * k end
function VMT:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function VMT:Distance(v) return (self - v):Length() end
function VMT:Unpack() return self.x, self.y, self.z end

local AMT = {}
AMT.__index = AMT
function Angle(p, y, r)
    if type(p) == "table" then return setmetatable({ p = p.p, y = p.y, r = p.r }, AMT) end
    return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, AMT)
end
function AMT:Forward()
    local p, y = math.rad(self.p), math.rad(self.y)
    return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
function AMT:Right()
    local y = math.rad(self.y)
    return Vector(math.sin(y), -math.cos(y), 0)
end
function AMT:Up()
    local f, r = self:Forward(), self:Right()
    return Vector(r.y * f.z - r.z * f.y, r.z * f.x - r.x * f.z, r.x * f.y - r.y * f.x)
end

-- hooks, commands, ConVars
hook = {
    Add = function(ev, name, fn) M.hooks[ev] = M.hooks[ev] or {} M.hooks[ev][name] = fn end,
    Remove = function(ev, name) if M.hooks[ev] then M.hooks[ev][name] = nil end end,
}
function M.run_hook(ev, ...)
    local first
    for _, fn in pairs(M.hooks[ev] or {}) do
        local r = fn(...)
        if first == nil and r ~= nil then first = r end
    end
    return first
end
-- hook.Run (0.9.1: the character hooks of cl_character.lua, GSA1CharacterCreated ...): every listener, recorded in
-- M.hook_runs[name]
M.hook_runs = {}
hook.Run = function(ev, ...)
    M.hook_runs[ev] = (M.hook_runs[ev] or 0) + 1
    return M.run_hook(ev, ...)
end
concommand = { Add = function(name, fn) M.cmds[name] = fn end }
cvars = {
    AddChangeCallback = function(name, fn)
        M.cvcb[name] = M.cvcb[name] or {}
        table.insert(M.cvcb[name], fn)
    end,
}
local CVMT = {}
CVMT.__index = CVMT
function CVMT:GetString() return self.v end
function CVMT:GetFloat() return tonumber(self.v) or 0 end
function CVMT:GetInt() return math.floor(tonumber(self.v) or 0) end
function CVMT:GetBool() return (tonumber(self.v) or 0) ~= 0 end
function CVMT:SetString(s)
    local old = self.v
    self.v = tostring(s)
    for _, fn in ipairs(M.cvcb[self.name] or {}) do fn(self.name, old, self.v) end
end
CVMT.SetFloat, CVMT.SetInt = CVMT.SetString, CVMT.SetString
function CVMT:SetBool(b) self:SetString(b and "1" or "0") end
function M.cv(name, default)
    local cv = M.convars[name]
    if cv then return cv end
    cv = setmetatable({ name = name, v = tostring(default) }, CVMT)
    M.convars[name] = cv
    return cv
end
function CreateClientConVar(name, default, save, userinfo, help, lo, hi)
    local cv = M.cv(name, default)
    cv.save, cv.help, cv.lo, cv.hi, cv.client = save, help, lo, hi, true
    return cv
end
function CreateConVar(name, default, flags, help, lo, hi)
    local cv = M.cv(name, default)
    cv.flags, cv.help, cv.lo, cv.hi, cv.client = flags, help, lo, hi, false
    return cv
end
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 128, 8192, 256
function GetConVar(name) return M.convars[name] end
function RunConsoleCommand(name, ...)
    local cv = M.convars[name]
    if cv then
        cv:SetString((...))
    elseif M.cmds[name] then
        M.cmds[name](nil, name, { ... }, table.concat({ ... }, " "))
    end
end
M.cv("fps_max", "60.19"); M.cv("mat_queue_mode", "-1"); M.cv("fov_desired", "92.5"); M.cv("mat_vsync", "1")
M.cv("volume", "1"); M.cv("snd_mute_losefocus", "1"); M.cv("host_timescale", "1"); M.cv("cl_forwardspeed", "10000")
M.cv("cl_sidespeed", "10000"); M.cv("joystick", "0")

-- the game, the system, files
system = {
    HasFocus = function() return M.focus end,
    IsWindows = function() return true end,
    IsLinux = function() return false end,
}
gui = { IsGameUIVisible = function() return M.ui end }
vgui = { CursorVisible = function() return false end }
game = { GetMap = function() return "gm_freespace_13" end, SinglePlayer = function() return true end }
engine = { ActiveGamemode = function() return "sandbox" end }
function ScrW() return M.scrw end
function ScrH() return M.scrh end
timer = { Simple = noop, Create = noop, Remove = noop }
chat = { AddText = noop }
spawnmenu = {
    AddToolCategory = noop,
    AddToolMenuOption = function(tab, category, class, name, cmd, config, cpanel)
        M.menu[#M.menu + 1] = { tab = tab, category = category, class = class, name = name, cpanel = cpanel }
    end,
}
net = {
    Start = noop, SendToServer = noop, WriteVector = noop, WriteUInt = noop, WriteFloat = noop, WriteBool = noop,
    Receive = noop, ReadVector = function() return Vector() end, ReadUInt = function() return 0 end,
    ReadFloat = function() return 0 end, ReadBool = function() return false end,
    WriteString = noop, ReadString = function() return "" end,               -- 0.9.2: the attacker's class (interact)
}
util = {
    IsBinaryModuleInstalled = function() return true end,
    NetworkStringToID = function() return 0 end,
    AddNetworkString = noop,
    IsInWorld = function() return true end,
    -- 0.9.2: the contents at a point (M.contents(pos) -> CONTENTS_* bits; none: empty)
    PointContents = function(p)
        count("PointContents")
        return M.contents and M.contents(p) or 0
    end,
    TraceHull = function(t)
        count("TraceHull")
        local out = t.output or {}
        out.HitPos = Vector(t.endpos)
        out.Hit = false
        return out
    end,
}
file = {
    Size = function(p) return M.files[p] and #M.files[p] or -1 end,
    Exists = function(p) return M.files[p] ~= nil end,
    Delete = function(p) M.files[p] = nil end,
    Rename = function(a, b) M.files[b] = M.files[a] M.files[a] = nil return true end,
    Write = function(p, s) M.files[p] = s end,
    Read = function(p) return M.files[p] end,
    Append = function(p, s) M.files[p] = (M.files[p] or "") .. s M.appends = M.appends + 1 end,
    CreateDir = noop,
    -- the "LUA" path: the addon's files below M.root (host_list) and the test's virtual ones; other paths: nothing
    Find = function(pattern, path)
        if path ~= "LUA" then return {}, {} end
        local dir, filepat = string.match(pattern, "^(.*)/([^/]*)$")
        if not dir then dir, filepat = "", pattern end
        local out, seen = {}, {}
        for _, n in ipairs(host_list and host_list(M.root .. "/" .. dir, filepat) or {}) do
            seen[n] = true
            out[#out + 1] = n
        end
        local lpat = "^" .. string.gsub(string.gsub(filepat, "%.", "%%."), "%*", ".*") .. "$"
        for rel in pairs(M.virtual) do
            local d, n = string.match(rel, "^(.*)/([^/]*)$")
            if d == dir and string.match(n, lpat) and not seen[n] then out[#out + 1] = n end
        end
        table.sort(out)
        return out, {}
    end,
    Open = function() return nil end,
}

-- drawing
render = {}
for _, n in ipairs({ "OverrideBlend", "OverrideAlphaWriteEnable", "PushRenderTarget", "PopRenderTarget", "Clear",
                     "CapturePixels", "SuppressEngineLighting", "SetLightingOrigin", "ResetModelLighting",
                     "SetModelLighting", "SetLocalModelLights" }) do
    render[n] = function() count(n) end
end
function render.SetMaterial(m)
    count("SetMaterial")
    M.current = m
end
function render.GetDXLevel() return 95 end
function render.ComputeLighting() return Vector(0.5, 0.5, 0.5) end
function render.ReadPixel() return nil end
function render.GetViewSetup() return M.view_setup end            -- (a table with origin, angles, ... in GMod)
function render.GetRenderTarget() return M.render_target end      -- nil: the screen
mesh = {}
local in_mesh = {}
function mesh.Begin(a, b, c)
    count("mesh.Begin")
    in_mesh.mat, in_mesh.verts = M.current, 0
    M.inMesh = in_mesh
end
function mesh.End()
    count("mesh.End")
    if M.draw_cost > 0 then M.T = M.T + M.draw_cost end
    if M.onDraw and M.inMesh then M.onDraw(M.inMesh) end
    M.inMesh = nil
end
function mesh.Position() count("mesh.Position") end
function mesh.Normal() count("mesh.Normal") end
function mesh.TexCoord() count("mesh.TexCoord") end
function mesh.Color() count("mesh.Color") end
function mesh.AdvanceVertex()
    count("mesh.AdvanceVertex")
    if M.inMesh then M.inMesh.verts = M.inMesh.verts + 1 end
end
cam = { Start2D = noop, End2D = noop, Start3D = noop, End3D = noop }
surface = { SetDrawColor = noop, DrawRect = function() count("DrawRect") end }
draw = { NoTexture = noop, SimpleText = noop, SimpleTextOutlined = noop }
local MATMT = {}
MATMT.__index = MATMT
function MATMT:GetName() return self.name end
function CreateMaterial(name, shader, params)
    count("CreateMaterial")
    if M.material_cost > 0 then M.T = M.T + M.material_cost end
    local m = setmetatable({ name = name, shader = shader, params = params }, MATMT)
    M.nmaterials = M.nmaterials + 1
    M.materials[name] = m
    return m
end
function GetRenderTargetEx(name, w, h)
    count("GetRenderTargetEx")
    local rt = M.rts[name]
    if not rt then
        rt = setmetatable({ name = name, w = w, h = h }, MATMT)
        M.rts[name] = rt
        M.nrts = M.nrts + 1
    end
    return rt
end
function Mesh(mat) return { mat = mat, Draw = noop, Destroy = noop } end
MATERIAL_TRIANGLES, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO = 2, 0, 1, 0
IMAGE_FORMAT_BGRA8888, IMAGE_FORMAT_RGBA8888, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE = 12, 0, 5, 2
MASK_SOLID_BRUSHONLY, RENDERGROUP_BOTH, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, TEXT_ALIGN_CENTER = 16395, 2, 0, 3, 1
IN_JUMP, IN_DUCK, IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_WALK = 2, 4, 1, 2048, 8192, 262144
CONTENTS_SOLID, CONTENTS_SLIME, CONTENTS_WATER = 1, 16, 32
COLLISION_GROUP_DEBRIS, COLLISION_GROUP_WORLD = 1, 20

-- entities and the local player
scripted_ents = { Register = function(t, name) M.classes[name] = t end }
function Model(path) return path end                              -- (precaches the model in GMod)
weapons = {
    Register = function(t, name)
        t.ClassName = name
        M.weapons[name] = t
    end,
    GetStored = function(name) return M.weapons[name] end,
}
NULL = setmetatable({ removed = true }, { __tostring = function() return "[NULL Entity]" end })
local function new_entity(cls)
    local e = setmetatable({ cls = cls, pos = Vector() }, { __index = M.classes[cls] or {} })
    e.Spawn, e.DrawShadow, e.SetRenderBounds = noop, noop, noop
    e.SetPos = function(self, p) self.pos:Set(p) end
    e.GetPos = function(self) return Vector(self.pos) end
    e.Remove = function(self)
        self.removed = true
        if self.OnRemove then self:OnRemove() end
    end
    e.GetClass = function(self) return self.cls end
    return e
end
ents = {
    CreateClientside = function(cls)
        local e = new_entity(cls)
        M.entities[#M.entities + 1] = e
        if e.Initialize then e:Initialize() end
        return e
    end,
    FindInSphere = function() return {} end,
}
function IsValid(x)
    return x ~= nil and x ~= false and not (type(x) == "table" and x.removed)
end
M.player = new_entity("player")
M.player.pos = Vector(704, 132, -143)
M.player.EyeAngles = function() return Angle(M.pitch, M.yaw, 0) end
M.player.EyePos = function(self) return self.pos + Vector(0, 0, 64) end
M.player.IsPlayer = function() return true end
M.player.Alive = function(self) return self.alive ~= false end     -- 0.9.2 (CreateMove while dead)
M.player.nw2 = {}
M.player.GetActiveWeapon = function(self) return self.active or NULL end
-- the view entity: the player itself unless a test looks through a camera (M.player.view_entity)
M.player.GetViewEntity = function(self) return self.view_entity or self end
M.player.GetNW2Bool = function(self, k, d)
    local v = self.nw2[k]
    if v == nil then return d end
    return v
end
M.player.SetNW2Bool = function(self, k, v) self.nw2[k] = v end
function LocalPlayer() return M.player end
function EyePos() return M.view_origin or Vector(0, 0, 0) end
function EyeAngles() return Angle(M.pitch, M.yaw, 0) end

-- require("gsa1"): the mock module (M.module() makes it)
function require(name)
    if name == "gsa1" and gsa1 then return gsa1 end
    error("module '" .. tostring(name) .. "' not found")
end

-- loading the addon's files (M.virtual[rel]: a file that exists only in the test)
function M.load(rel)
    local src = M.virtual[rel] or host_read(M.root .. "/" .. rel)
    if not src then return false end
    local fn, err = host_load(src, rel)
    if not fn then error(err) end
    fn()
    return true
end

-- GMod's include (a missing file is an error here, so a test notices it) and AddCSLuaFile (recorded)
function include(rel)
    M.included[#M.included + 1] = rel
    if not M.load(rel) then error("include: no file " .. tostring(rel)) end
end
function AddCSLuaFile(rel) M.cslua[#M.cslua + 1] = rel end

-- the mock module -------------------------------------------------------------------------------------------------
-- opts.archives: { [kind] = { count of archive 0, of archive 1, ... } }; opts.batches(pair, kind) -> list of
-- { archive, tex, flags, src, dst, wrap, pass, tris, prims }: the character's batches for a game pair
function M.module(opts)
    opts = opts or {}
    local G = {
        VERSION = "0.6.0", API_VERSION = 6, LIBSA1_VERSION = "0.2.0", SCALE = 4.0,
        BUTTON_JUMP = 1, BUTTON_ACTION = 2, BUTTON_ACTION2 = 4,
        FEATURES = opts.features or {}, FEATURE_ERRORS = opts.feature_errors or {},
        -- 0.9.2: the tick's host flags and host camera, the start rings
        TICK_HOST_FLAGS = opts.host_flags ~= false, TICK_HOST_CAMERA = opts.host_camera == true,
        INPUT_HOST_WATER_KNOWN = 1, INPUT_HOST_IN_WATER = 2, START_RINGS_MAX = 99,
    }
    local chars, nextId = {}, 1
    M.mchars, M.ticks, M.creates = chars, {}, {}
    local mesh_calls = 0
    function G.IsReady() return true end
    function G.Init() return true, "already initialised" end
    function G.InitPoll() return "ready", "", 0, false end
    function G.Status()
        return { ready = true, version = G.VERSION, api = 6, libsa1 = "0.2.0", build = "mock build", mesh_calls = mesh_calls,
                 mesh_errors = 0, mesh_saved = 0, vector_mode = 1, characters = 1, config = "<config>", disc_ms = 1,
                 disc_state = "ready" }
    end
    function G.Upgrades()
        local out = {}
        for _, u in ipairs(GSA1.UPGRADES) do out[#out + 1] = { kind = u.kind, name = u.name } end
        return out
    end
    function G.CharacterInfo() return { radius = 16, height = 40, eyes = 28, center = 20 } end
    function G.TextureArchives(kind)
        local a = (opts.archives or {})[kind] or { 4, 3 }
        local out = {}
        for i, n in ipairs(a) do out[i] = { name = "ARCHIVE" .. (i - 1), count = n } end
        return out
    end
    function G.Texture(kind, index, archive)
        return { w = 16, h = 16, fmt = 0, dfmt = 0, alpha = 0, name = "tex" .. archive .. "_" .. index,
                 runs = string.rep("\0\0\0\0\16\0\255\255\255\255", 16), nruns = 16, canary = false }
    end
    function G.Create(kind, pos, yaw, ups, rings)
        local id = nextId
        nextId = nextId + 1
        chars[id] = { kind = kind, pos = Vector(pos), acc = 0, pair = 0, gen = 1, bgen = 1, batches = nil,
                      startRings = rings }
        M.creates[#M.creates + 1] = { id = id, kind = kind, pos = Vector(pos), yaw = yaw, rings = rings }
        return id
    end
    function G.Destroy(id) chars[id] = nil return true end
    function G.Tick(id, sx, sy, yaw, buttons, dt, raw, hflags, co, ct)
        local c = chars[id]
        M.ticks.last = { id = id, sx = sx, sy = sy, yaw = yaw, buttons = buttons, dt = dt, raw = raw, hflags = hflags,
                         co = co and Vector(co), ct = ct and Vector(ct) }
        if not c then return nil, "no such character", "not_found" end
        c.hflags = hflags
        c.acc = c.acc + dt
        local n = 0
        while c.acc >= 1 / 30 do
            c.acc = c.acc - 1 / 30
            n = n + 1
            c.pair = c.pair + 1
            c.gen = c.gen + 1
            c.pos.x = c.pos.x + (opts.speed or 0) / 30
        end
        c.buttons = buttons
        return n
    end
    function G.GetState(id, out)
        local c = chars[id]
        if not c then return nil end
        out = out or {}
        out.x, out.y, out.z, out.vx, out.vy, out.vz, out.yaw = c.pos.x, c.pos.y, c.pos.z, opts.speed or 0, 0, 0, 0
        out.action, out.mode, out.ground, out.frame, out.step, out.pairs = 14, 4, true, 0, c.pair * 2, 1
        out.alpha, out.tick_ms, out.render_ms, out.view_ms, out.equipment, out.upgrades_ok = c.acc * 30, 0.05, 0.05,
            0.01, 0, true
        out.draws, out.sprites, out.lines, out.blended, out.sprite_batches = 40, 15, 0, 6, 2
        out.vertices, out.blend_layers, out.sprite_layers, out.sprite_max = 6000, 0.2, 0.1, 49.6
        out.water_attr, out.water_level, out.host_flags = c.water_attr or 0, c.water_level or 0, c.hflags or 0
        out.in_water = (c.water_attr or 0) % 4 >= 2
        return out
    end
    -- opts.batches returns the same list object for the same batch structure (a new object: a new structure)
    local default = { { 0, 0, 0x20, 1, 0, 3, 0, 500, 1 }, { 0, 1, 0x20, 1, 0, 3, 0, 300, 1 } }
    local function batches_of(c)
        if c.bpair == c.pair and c.batches then return c.batches end
        local list = opts.batches and opts.batches(c.pair, c.kind) or default
        if list ~= c.batches then c.bgen = c.bgen + 1 end
        c.batches, c.bpair = list, c.pair
        return list
    end
    -- the batch keys (made once per batch entry, as the module's strings are interned by Lua)
    local keys = setmetatable({}, { __mode = "k" })
    local function key_of(b)
        local k = keys[b]
        if not k then
            k = string.format("%d.%d.%X.%d.%d.%d.%d", b[1], b[2], b[3], b[4], b[5], b[6], b[7])
            keys[b] = k
        end
        return k
    end
    function G.Render(id, alpha)
        local c = chars[id]
        if not c then return nil, "no such character" end
        local list = batches_of(c)
        local tris = 0
        for _, b in ipairs(list) do tris = tris + b[8] end
        local a = alpha < 0 and c.acc * 30 or alpha
        return c.gen, c.bgen, c.pos.x, c.pos.y, c.pos.z, 0, true, a, tris, false
    end
    function G.Batches(id, out)
        local c = chars[id]
        if not c then return nil end
        local list = batches_of(c)
        local tris = 0
        for i, b in ipairs(list) do
            local e = out[i]
            if type(e) ~= "table" then
                e = {}
                out[i] = e
            end
            e.key = key_of(b)
            e.archive, e.tex, e.flags, e.src, e.dst, e.wrap, e.pass, e.tris, e.prims =
                b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9]
            e.all, e.mat, e.order, e.source = b[3], 0, i, 0
            tris = tris + b[8]
        end
        out.gen, out.count, out.triangles = c.bgen, #list, tris
        return #list
    end
    function G.PrepareView() return true end
    function G.EmitBatch(id, i)
        local c = chars[id]
        local b = c and c.batches and c.batches[i]
        if not b then return nil, "EmitBatch(id, batch)" end
        mesh_calls = mesh_calls + b[8] * 3 * 5
        return b[8] * 3
    end
    function G.PollEvents(out)
        out = out or {}
        out.pool = out.pool or {}
        local e = out.pool[1] or {}
        out.pool[1] = e
        e.type, e.id, e.bank, e.x, e.y, e.z, e.arg, e.step, e.character = 1, 724, 0, 0, 0, 0, 0, 0, 1
        out[1], out[2], out.count = e, nil, 1
        return out
    end
    function G.PollLog() return {} end
    function G.AudioUpdate() return 0 end
    function G.AudioStatus() return { open = false, active = 0 } end
    function G.AudioSettings() return true end
    function G.MoverCommit() return 0, 0 end
    function G.MoverUpdate() return true end
    function G.MoverForget() end
    function G.MoverStatus() return {} end
    function G.ShapeKnown() return false end
    function G.PadSettings() return true end
    function G.PadPoll(dt, paused, out)
        out = out or {}
        out.connected, out.active, out.yaw, out.pitch, out.reset = false, false, 0, 0, false
        return out
    end
    function G.PadStatus() return { enabled = true, available = false, backend = "mock" } end
    function G.WorldInfo() return nil end
    gsa1 = G
    return G
end

-- one client frame, the way Garry's Mod runs it: Think, CreateMove, CalcView, the entities' Draw / DrawTranslucent,
-- PostRender
local CMD = {}
CMD.__index = CMD
function CMD:GetSideMove() return 0 end
function CMD:GetForwardMove() return M.forward or 0 end
function CMD:KeyDown(k) return (M.keys or 0) % (2 * k) >= k end
function CMD:ClearMovement() end
function CMD:ClearButtons() M.cmdOut = 0 end
function CMD:GetButtons() return M.keys or 0 end
function CMD:SetButtons(b) M.cmdOut = b end
function CMD:GetViewAngles() return Angle(M.pitch, M.yaw, 0) end
function CMD:SetViewAngles() end
function CMD:GetMouseX() return 0 end
function CMD:GetMouseY() return 0 end
local cmd = setmetatable({}, CMD)
function M.frame(dt)
    dt = dt or M.dt
    M.dt = dt
    M.T = M.T + dt
    M.frameNo = M.frameNo + 1
    M.run_hook("Think")
    M.run_hook("CreateMove", cmd)
    local view = M.run_hook("CalcView", M.player, M.player:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
    M.view_origin = view and view.origin or M.player:EyePos()
    for _, e in ipairs(M.entities) do
        if not e.removed and e.Draw then e:Draw() end
    end
    for _, e in ipairs(M.entities) do
        if not e.removed and e.DrawTranslucent then e:DrawTranslucent() end
    end
    M.run_hook("PostRender")
end

-- check(cond, fmt, ...) with counters
M.fails, M.checks = 0, 0
function M.check(cond, fmt, ...)
    M.checks = M.checks + 1
    local msg = string.format(fmt, ...)
    print((cond and "  ok    " or "  FAIL  ") .. msg)
    if not cond then M.fails = M.fails + 1 end
    return cond
end
function M.info(fmt, ...) print("  info  " .. string.format(fmt, ...)) end

return M
