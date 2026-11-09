-- feat_skinhud_real.lua: run by feat_skinhud_binding_test in Garry's Mod's own LuaJIT with the module's REAL functions (gsa1, opened by gmod13_open through tests/luajit_base.hpp); never by
-- lua_host. THE NAMES FIX after 1.0.0-beta1a (sadc/build/research/b1a2; based on the trace lane's probe there). Globals from the test: SKINHUD = { gdi, tests, lua (the addon/lua under test),
-- module }, host_write, host_read, host_load, host_sleep, host_list, Vector, Angle. Returns checks, fails.
-- The addon's whole client Lua through its own autorun, on tests/lua_mock.lua and tests/lua_mock_rt.lua (the pixel model of render targets), at 3440 x 1440; Character Select from the disc through
-- the real gsa1.Frontend* calls; the owner's keys (Up to Metal Sonic, Mecha Sonic, Sonic, Metal Sonic again); 60 frames a second. Stand-ins (none on the draw path): no pad, no sound, vgui panels, a
-- font as metrics and a box a letter (no font file anywhere). Checked through what the paint really hands Garry's Mod: S.DrawFilter's answers, surface.DrawTexturedRectUV, render.SetMaterial and
-- mesh, render.CapturePixels, GetRenderTargetEx, CreateMaterial, and the log's lines.
-- THE NEGATIVE CONTROL: on the second visit to Metal Sonic, a second after his name is drawn again, his name's picture is filled with Source's opaque black creation colour, as a lost target reads
-- (the trace lane's run 3). The fix must read it within a second, draw the game's own name from then on and make it again; beta 1a (--module and --lua of build/release_1.0.0-beta1a) drew a
-- black box to the end, silently, and fails here.
-- b1a2-fix2 (the names fix's verifier): every self-check capture is of the 16 x 4 target cl_text.lua T.ReadTexels draws the texels into through the page's own material, never of a 2048 x 1024 page;
-- one such read timed here (the Lua side); THE CANARY'S RULE: with a copy that reads colours at 3/4, the page's canary is said once and compared with its make's read, and nothing is made again.
local REAL = gsa1
local CFG = SKINHUD or {}
local checks, fails = 0, 0
local function out(s) host_write(s .. "\n") end
local function check(ok, fmt, ...)
    checks = checks + 1
    if not ok then fails = fails + 1 end
    out(string.format("  %s  %s", ok and "ok  " or "FAIL", string.format(fmt, ...)))
    return ok
end
local function info(fmt, ...) out("  info  " .. string.format(fmt, ...)) end
if (CFG.gdi or "") == "" then
    info("no disc (--gdi or SA1_TEST_GDI): Character Select through the real module is not run here")
    return checks, fails
end
local TESTS, LUA_ROOT = CFG.tests, CFG.lua
local function load_file(path, name)
    local src = host_read(path)
    if not src then error("no file " .. path) end
    local f, e = host_load(src, name)
    if not f then error(e) end
    return f
end

-- the module's Vector / Angle userdata (tests/luajit_base.hpp: x y z / p y r only): Garry's Mod's methods the paint uses
local RV, RA = Vector, Angle
local vmt, amt = getmetatable(RV(0, 0, 0)), getmetatable(RA(0, 0, 0))
local vget, aget = vmt.__index, amt.__index
local VM, AM = {}, {}
function VM.Unpack(u) return u.x, u.y, u.z end
function VM.Length(u) return math.sqrt(u.x * u.x + u.y * u.y + u.z * u.z) end
function VM.Dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function VM.SetUnpacked(u, x, y, z) u.x, u.y, u.z = x, y, z end
function VM.Set(u, v) u.x, u.y, u.z = v.x, v.y, v.z end
function VM.Distance(a, b) local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z return math.sqrt(dx * dx + dy * dy + dz * dz) end
function VM.ToScreen() return { x = 0, y = 0, visible = false } end
vmt.__index = function(u, k) local f = VM[k] if f ~= nil then return f end return vget(u, k) end
vmt.__add = function(a, b) return RV(a.x + b.x, a.y + b.y, a.z + b.z) end
vmt.__sub = function(a, b) return RV(a.x - b.x, a.y - b.y, a.z - b.z) end
vmt.__mul = function(a, b)
    if type(a) == "number" then return RV(b.x * a, b.y * a, b.z * a) end
    if type(b) == "number" then return RV(a.x * b, a.y * b, a.z * b) end
    return RV(a.x * b.x, a.y * b.y, a.z * b.z)
end
vmt.__unm = function(a) return RV(-a.x, -a.y, -a.z) end
local function trig(a)
    local p, y, r = math.rad(a.p), math.rad(a.y), math.rad(a.r)
    return math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
end
function AM.Forward(a) local sp, cp, sy, cy = trig(a) return RV(cp * cy, cp * sy, -sp) end
function AM.Right(a) local sp, cp, sy, cy, sr, cr = trig(a) return RV(-sr * sp * cy + cr * sy, -sr * sp * sy - cr * cy, -sr * cp) end
function AM.Up(a) local sp, cp, sy, cy, sr, cr = trig(a) return RV(cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp) end
function AM.Unpack(a) return a.p, a.y, a.r end
amt.__index = function(u, k) local f = AM[k] if f ~= nil then return f end return aget(u, k) end

-- the GMod stand-in and its pixel model
local M = load_file(TESTS .. "\\lua_mock.lua", "lua_mock.lua")()
M.root = LUA_ROOT
local R = load_file(TESTS .. "\\lua_mock_rt.lua", "lua_mock_rt.lua")()(M)
M.scrw, M.scrh = 3440, 1440
local W, H = 3440, 1440
R.RTMT.IsError = function() return false end
-- (a capture without the copy: the pixel model copies 4 x 2 M values of a 2048 x 1024 page; every read-back of the addon reads right after its capture, nothing writes in between)
render.CapturePixels = function() R.captured = R.cur end
render.ReadPixel = function(x, y)
    local t = R.captured
    if not t or x < 0 or y < 0 or x >= t.w or y >= t.h then return nil end
    return t:Get(x, y)
end

-- RECORDING ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local FR = -1                   -- the frame since Character Select opened
local function from(file)
    for lv = 3, 24 do
        local i = debug.getinfo(lv, "S")
        if not i then break end
        if string.find(i.short_src or "", file, 1, true) then return true end
    end
    return false
end
local made_rts, made_mats = {}, {}
local rGRT = GetRenderTargetEx
GetRenderTargetEx = function(name, ...)
    made_rts[#made_rts + 1] = { name = tostring(name), f = FR }
    return rGRT(name, ...)
end
local rCM = CreateMaterial
CreateMaterial = function(name, shader, params)
    made_mats[#made_mats + 1] = { name = tostring(name), f = FR }
    if M.materials[name] then return M.materials[name] end     -- (Garry's Mod: CreateMaterial does not make a material whose name exists)
    return rCM(name, shader, params)
end
local MATMT = getmetatable(rCM("gsa1real_meta", "UnlitGeneric", {}))
M.materials["gsa1real_meta"] = nil
for _, k in ipairs({ "SetTexture", "SetInt", "SetFloat", "SetString", "SetVector", "SetMatrix", "SetUndefined", "Recompute" }) do
    MATMT[k] = MATMT[k] or function(self, key, v) if self.params and key then self.params[key] = type(v) == "table" and v.name or v end end
end
function MATMT:GetInt(k) return tonumber(self.params and self.params[k]) end
function MATMT:GetFloat(k) return tonumber(self.params and self.params[k]) end
function MATMT:GetString(k) local v = self.params and self.params[k] return v and tostring(v) or nil end
function MATMT:GetShader() return self.shader end
function Material(path) return setmetatable({ name = tostring(path), params = {} }, MATMT) end
local RTMT = R.RTMT
function RTMT:Download() end
function RTMT:IsErrorTexture() return false end
function RTMT:GetMappingWidth() return self.w end
function RTMT:GetMappingHeight() return self.h end
-- every capture: its frame, whether feat/cl_skinhud.lua asked for it, and (b1a2-fix2) which target it read: a text page (2048 x 1024, 8 MiB) or the small read's 16 x 4
local captures = {}
local rCap = render.CapturePixels
render.CapturePixels = function(...)
    local t = R.cur
    captures[#captures + 1] = { f = FR, skinhud = from("cl_skinhud.lua"), frame = M.frameNo, name = t and tostring(t.name) or "?", w = t and t.w or 0, h = t and t.h or 0 }
    return rCap(...)
end
-- (b1a2-fix2, THE CANARY'S RULE in the real binding) XFORM, when set, changes the colours a read of the small target gives: a host whose copy reads colours otherwise than the page holds them
local XFORM = nil
local rRead = render.ReadPixel
render.ReadPixel = function(x, y)
    local r, g, b, a = rRead(x, y)
    local t = R.captured
    if XFORM and r and t and string.find(tostring(t.name), "gsa1_textread_", 1, true) then r, g, b = XFORM(r), XFORM(g), XFORM(b) end
    return r, g, b, a
end

-- FONTS (no font file: metrics and a box per letter) and the model matrix
local FONTS, curfont, tpos, tcol = {}, nil, { 0, 0 }, { 255, 255, 255, 255 }
function surface.CreateFont(name, data) FONTS[name] = { family = tostring(data.font), size = tonumber(data.size) or 16, weight = data.weight or 400 } end
function surface.SetFont(n) curfont = n end
function surface.GetFont() return curfont end
local function fontinfo(n) return FONTS[n] or { family = "engine:" .. tostring(n), size = 32 } end
local function adv_of(f, ch)
    if ch == " " then return math.floor(f.size * 0.3 + 0.5) end
    return math.floor(f.size * ((f.family == "GSA1 no such font") and 0.62 or 0.58) + 0.5)
end
local UTF = "[%z\1-\127\194-\244][\128-\191]*"
function surface.GetTextSize(text)
    local f = fontinfo(curfont)
    local w = 0
    for ch in string.gmatch(tostring(text), UTF) do w = w + adv_of(f, ch) end
    return w, f.size
end
function surface.SetTextPos(x, y) tpos[1], tpos[2] = x, y end
function surface.GetTextPos() return tpos[1], tpos[2] end
function surface.SetTextColor(r, g, b, a)
    if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
    tcol[1], tcol[2], tcol[3], tcol[4] = r, g, b, a or 255
end
local MSTACK = { { tx = 0, ty = 0, sx = 1, sy = 1 } }
local MXMT = {}
MXMT.__index = MXMT
function Matrix() return setmetatable({ tx = 0, ty = 0, sx = 1, sy = 1 }, MXMT) end
function MXMT:Translate(v) self.tx, self.ty = self.tx + self.sx * v.x, self.ty + self.sy * v.y end
function MXMT:Scale(v) self.sx, self.sy = self.sx * v.x, self.sy * v.y end
function MXMT:SetTranslation(v) self.tx, self.ty = v.x, v.y end
function MXMT:SetScale(v) self.sx, self.sy = v.x, v.y end
function MXMT:Rotate() end
function cam.PushModelMatrix(m, mult)
    local t = MSTACK[#MSTACK]
    if mult then
        MSTACK[#MSTACK + 1] = { tx = t.tx + t.sx * m.tx, ty = t.ty + t.sy * m.ty, sx = t.sx * m.sx, sy = t.sy * m.sy }
    else
        MSTACK[#MSTACK + 1] = { tx = m.tx, ty = m.ty, sx = m.sx, sy = m.sy }
    end
end
function cam.PopModelMatrix() if #MSTACK > 1 then MSTACK[#MSTACK] = nil end end
-- a letter = its box (0.14 .. 0.80 of the size), drawn through the pixel model's own blend; a texel already written at alpha 255 in the same text call is not written again (exact for the over blend)
local STAMP = 0
function surface.DrawText(text)
    local f = fontinfo(curfont)
    local t = R.cur
    local x = tpos[1]
    local s = { tcol[1], tcol[2], tcol[3], math.floor((tcol[4] or 255) * R.mult) }
    STAMP = STAMP + 1
    for ch in string.gmatch(tostring(text), UTF) do
        local a = adv_of(f, ch)
        if t and R.in2d and ch ~= " " and s[4] > 0 then
            local mx = MSTACK[#MSTACK]
            local X0, X1 = mx.tx + mx.sx * (x + 0.06 * a), mx.tx + mx.sx * (x + a - 0.06 * a)
            local Y0, Y1 = mx.ty + mx.sy * (tpos[2] + 0.14 * f.size), mx.ty + mx.sy * (tpos[2] + 0.80 * f.size)
            if X0 > X1 then X0, X1 = X1, X0 end
            if Y0 > Y1 then Y0, Y1 = Y1, Y0 end
            t.stamp = t.stamp or {}
            local st, ded = t.stamp, s[4] == 255
            for py = math.max(0, math.floor(Y0)), math.min(t.h, math.ceil(Y1)) - 1 do
                local cy = py + 0.5
                if cy >= Y0 and cy < Y1 then
                    for px = math.max(0, math.floor(X0)), math.min(t.w, math.ceil(X1)) - 1 do
                        local cx = px + 0.5
                        if cx >= X0 and cx < X1 then
                            local i = py * t.w + px + 1
                            if not (ded and st[i] == STAMP) then
                                R.write(t, i, s)
                                st[i] = STAMP
                            end
                        end
                    end
                end
            end
        end
        x = x + a
    end
    tpos[1] = x
end

-- unknown drawing calls: a no-op for the void-like names, nil for the others (the addon's existence checks then fail as without them)
local VOID = { "^Set", "^Push", "^Pop", "^Draw", "^Override", "^Suppress", "^Reset", "^Enable", "^Start", "^End", "^Clear", "^Fog", "^Cull", "^Blur", "^Update", "^Turn", "^Disable", "^Material", "^Model", "^Render" }
for _, lib in pairs({ render = render, surface = surface, draw = draw, cam = cam, mesh = mesh }) do
    setmetatable(lib, { __index = function(_, key)
        for _, pat in ipairs(VOID) do
            if string.match(key, pat) then
                local f = function() end
                rawset(lib, key, f)
                return f
            end
        end
        return nil
    end })
end
-- vgui panels (the EditablePanel of cl_charselect.lua make_panel)
local PANEL = {}
PANEL.__index = PANEL
for _, k in ipairs({ "SetPos", "SetSize", "MakePopup", "SetKeyboardInputEnabled", "SetMouseInputEnabled", "SetConVar", "SetTall", "SetWide", "SetImage", "Dock", "SetText", "SizeToContents",
                     "SetVisible", "SetZPos", "MoveToFront", "SetCursor", "SetTooltip", "DockMargin", "DockPadding", "SetPaintBackground", "SetAlpha", "AddItem", "SetValue" }) do PANEL[k] = function() end end
function PANEL:GetWide() return W end
function PANEL:GetTall() return H end
function PANEL:CursorPos() return 0, 0 end
function PANEL:IsVisible() return not self.removed end
function PANEL:IsValid() return not self.removed end
function PANEL:Remove() self.removed = true if self.OnRemove then self:OnRemove() end end
function PANEL:GetChildren() return {} end
vgui.Create = function(cls) return setmetatable({ cls = cls }, PANEL) end
gui.IsConsoleVisible = gui.IsConsoleVisible or function() return false end
input = input or {}
input.IsButtonDown = input.IsButtonDown or function() return false end
input.IsKeyDown = input.IsKeyDown or function() return false end
input.LookupBinding = input.LookupBinding or function() return nil end
input.LookupKeyBinding = input.LookupKeyBinding or function() return nil end
input.GetCursorPos = input.GetCursorPos or function() return 0, 0 end
TEXFILTER = TEXFILTER or { NONE = 0, POINT = 1, LINEAR = 2, ANISOTROPIC = 3 }
STENCIL_ALWAYS = STENCIL_ALWAYS or 8
-- the fonts the owner's log says are there (garrysmod/resource/fonts: only their names, as file.Exists sees them; no font data anywhere)
M.files["resource/fonts/BauhausStd-Bold.ttf"] = ""
M.files["resource/fonts/Gill Sans Bold.otf"] = ""

-- the REAL module, with its input and sound kept out (the owner's pad and speakers are not the test's)
gsa1 = REAL
REAL.PadPoll = function(dt, paused, o)
    o = o or {}
    o.connected, o.active, o.yaw, o.pitch, o.reset, o.raw, o.sx, o.sy = false, false, 0, 0, false, 0, 0, 0
    return o
end
REAL.AudioOpen = function() return false, "the test opens no sound" end
for _, n in ipairs({ "JukeboxPlay", "JukeboxStop", "JukeboxPause", "JukeboxSeek", "JukeboxVolume" }) do
    if REAL[n] then REAL[n] = function() return nil, "the test plays no sound" end end
end

-- THE ADDON (the client files under test, through their own autorun)
GSA1 = nil
M.included = {}
do
    local ok, err = pcall(M.load, "autorun/gsa1_autorun.lua")
    local errs = GSA1 and GSA1.FeatureFileErrors or {}
    check(ok and #errs == 0, "the addon's client files load through its autorun (%s)", tostring(err or errs[1] or "no error"))
end
local S, Hh, Tx = GSA1 and GSA1.CharSelect, GSA1 and GSA1.SkinHud, GSA1 and GSA1.Text
if not (S and S.DrawFilter and S.Open and Hh and Tx and GSA1.Hud and GSA1.Hud.Material) then
    check(false, "the addon's Character Select, skin pictures and text pictures loaded")
    return checks, fails
end
-- the frames a make step of the skins' pictures ran in (the self-check never reads in one): the fix's H.Step, beta 1a's H.Make
local MAKEFRAMES = {}
for _, fn in ipairs({ "Step", "Make" }) do
    local f0 = Hh[fn]
    if f0 then Hh[fn] = function(...) MAKEFRAMES[M.frameNo] = true return f0(...) end end
end
local LOG = {}
do
    local orig = GSA1.Log
    GSA1.Log = function(cat, f, ...)
        local ok, s = pcall(string.format, f, ...)
        LOG[#LOG + 1] = { f = FR, cat = tostring(cat), text = ok and s or tostring(f) }
        if orig then return orig(cat, f, ...) end
    end
end
local function logged(pat, after)
    for _, l in ipairs(LOG) do
        if (not after or l.f > after) and string.find(l.text, pat, 1, true) then return l.text, l.f end
    end
    return nil
end
M.cv("gsa1_sound"):SetString("0")

-- THE PAINT'S RECORD: for the game's m_sonic (the name) and B_SONIC_e (the plate) each frame: S.DrawFilter's answer, a surface.DrawTexturedRectUV in that call (the picture: its page and UVs), the
-- material GSA1.Hud.Material gave for the game's own draw, the placed quad; the order of the draws (a sequence number); paint_3d's triangles projected (the H2 probe)
local SEQ = 0
local REC = {}                  -- [frame] = { name = {...}, plate = {...}, tails = seq, sup = seq, skin = n }
local cur = nil                 -- the m_sonic / B_SONIC_e call being recorded
local function rec_of(f)
    local r = REC[f]
    if not r then
        r = {}
        REC[f] = r
    end
    return r
end
local sTRUV, sSetMat = surface.DrawTexturedRectUV, surface.SetMaterial
local SMAT = nil
surface.SetMaterial = function(m) SMAT = m if sSetMat then return sSetMat(m) end end
surface.DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1)
    SEQ = SEQ + 1
    if cur then cur.truv = { x = x, y = y, w = w, h = h, uv = { u0, v0, u1, v1 }, mat = SMAT, seq = SEQ, c = { R.color[1], R.color[2], R.color[3], R.color[4] } } end
    if sTRUV then return sTRUV(x, y, w, h, u0, v0, u1, v1) end
end
-- what the name shows at its top left corner, a texel the name keeps clear: "black" = an opaque dark texel there (the owner's black square), "clear", "game" (the game's own), "other"
local function sample(rt, u, v)
    if not (rt and rt.Get) then return nil end
    return rt:Get(math.min(rt.w - 1, math.max(0, math.floor(u * rt.w))), math.min(rt.h - 1, math.max(0, math.floor(v * rt.h))))
end
local function corner(c)
    if not c then return "none" end
    local rt, u, v = nil, nil, nil
    if c.ret == false and c.truv and c.truv.mat then
        rt = M.rts[tostring(c.truv.mat.params and c.truv.mat.params["$basetexture"])]
        local q = c.truv.uv
        u, v = q[1] + 0.004 * (q[3] - q[1]), q[2] + 0.02 * (q[4] - q[2])
    elseif type(c.ret) == "table" and c.ret.params then
        rt = M.rts[tostring(c.ret.params["$basetexture"])]     -- (beta 1a: a canvas material on the game's own UVs 0..1)
        u, v = 0.004, 0.02
    elseif c.ret == nil then
        return "game"
    end
    local r, g, b, a = sample(rt, u, v)
    if not r then return "other" end
    if a >= 128 and math.max(r, g, b) <= 12 then return "black" end
    return a <= 1 and "clear" or "other"
end
local realDF = S.DrawFilter
S.DrawFilter = function(st, name, D, k)
    SEQ = SEQ + 1
    local ln = name and string.lower(name)
    if ln == "m_sonic" or ln == "b_sonic_e" then
        local c = { seq = SEQ, skin = st.skins and st.skins[st.slot] or 1 }
        -- the game's quad, placed as paint_2d places it (S.PlaceX / S.PlaceY on this paint's layout)
        local V, first, count = st.scr.v, D[k + 2], D[k + 3]
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
        for v = first, first + count - 1 do
            local o = v * 8
            x0, y0, x1, y1 = math.min(x0, V[o + 1]), math.min(y0, V[o + 2]), math.max(x1, V[o + 1]), math.max(y1, V[o + 2])
        end
        local m = st.m
        c.box = { S.PlaceX(m, x0), S.PlaceY(m, y0), S.PlaceX(m, x1), S.PlaceY(m, y1) }
        c.count = count
        c.vc = { V[first * 8 + 5], V[first * 8 + 6], V[first * 8 + 7], V[first * 8 + 8] }
        cur = c
        local r = realDF(st, name, D, k)
        cur = nil
        c.ret = r
        c.corner = corner(c)            -- (what it shows now: the texels as they are in this frame)
        rec_of(FR)[ln == "m_sonic" and "name" or "plate"] = c
        c.wantGame = r == nil
        return r
    end
    if ln == "m_tails" or ln == "m_supersonic" then rec_of(FR)[ln] = SEQ end
    return realDF(st, name, D, k)
end
local realHM = GSA1.Hud.Material
GSA1.Hud.Material = function(kind, archive, tex, flags, sharp)
    local m, mode, x = realHM(kind, archive, tex, flags, sharp)
    local r = REC[FR]
    for _, which in ipairs({ "name", "plate" }) do
        local c = r and r[which]
        if c and c.wantGame and not c.game then
            c.game = m and tostring(m.name or (m.GetName and m:GetName())) or "nil"
            c.wantGame = false
            break
        end
    end
    return m, mode, x
end
-- H2 (the judge: not ruled out): paint_3d's triangles projected through the view cam.Start3D got, against the name's box
local VIEW, TRIS, H2ON = nil, nil, false
local rStart3D = cam.Start3D
cam.Start3D = function(eye, ang, fov, x, y, w, h, ...)
    VIEW = { eye = eye and RV(eye.x, eye.y, eye.z), ang = ang and RA(ang.p, ang.y, ang.r), fov = fov or 70, x = x or 0, y = y or 0, w = w or W, h = h or H }
    if H2ON then TRIS = {} end
    if rStart3D then return rStart3D(eye, ang, fov, x, y, w, h, ...) end
end
local mPos = mesh.Position
local VB = {}
mesh.Position = function(p)
    if H2ON and TRIS and S.st and S.st.in3d and p then
        VB[#VB + 1] = p.x
        VB[#VB + 1] = p.y
        VB[#VB + 1] = p.z
    end
    return mPos(p)
end
local mEnd = mesh.End
mesh.End = function(...)
    if H2ON and TRIS and #VB >= 9 then TRIS[#TRIS + 1] = VB end
    VB = {}
    return mEnd(...)
end
local mBegin = mesh.Begin
mesh.Begin = function(...)
    VB = {}
    return mBegin(...)
end
-- how much of the box (screen px) the projected triangles cover: a grid of 24 x 6 points
local function coverage(box)
    if not (VIEW and VIEW.eye and VIEW.ang and TRIS and #TRIS > 0) then return nil end
    local f, r, u = VIEW.ang:Forward(), VIEW.ang:Right(), VIEW.ang:Up()
    local k = (VIEW.w / 2) / math.tan(math.rad(VIEW.fov) / 2)
    local cx, cy = VIEW.x + VIEW.w / 2, VIEW.y + VIEW.h / 2
    local ex, ey, ez = VIEW.eye.x, VIEW.eye.y, VIEW.eye.z
    local function proj(x, y, z)
        local dx, dy, dz = x - ex, y - ey, z - ez
        local zz = dx * f.x + dy * f.y + dz * f.z
        if zz <= 1 then return nil end
        return cx + (dx * r.x + dy * r.y + dz * r.z) / zz * k, cy - (dx * u.x + dy * u.y + dz * u.z) / zz * k
    end
    local pts = {}
    for iy = 0, 5 do
        for ix = 0, 23 do pts[#pts + 1] = { box[1] + (ix + 0.5) * (box[3] - box[1]) / 24, box[2] + (iy + 0.5) * (box[4] - box[2]) / 6, false } end
    end
    local tris, front = 0, 0
    for _, vb in ipairs(TRIS) do
        for t = 0, math.floor(#vb / 9) - 1 do
            local o = t * 9
            local ax, ay = proj(vb[o + 1], vb[o + 2], vb[o + 3])
            local bx, by = proj(vb[o + 4], vb[o + 5], vb[o + 6])
            local qx, qy = proj(vb[o + 7], vb[o + 8], vb[o + 9])
            tris = tris + 1
            if ax and bx and qx then
                front = front + 1
                if math.max(ax, bx, qx) >= box[1] and math.min(ax, bx, qx) <= box[3] and math.max(ay, by, qy) >= box[2] and math.min(ay, by, qy) <= box[4] then
                    for _, pt in ipairs(pts) do
                        if not pt[3] then
                            local d1 = (pt[1] - bx) * (ay - by) - (ax - bx) * (pt[2] - by)
                            local d2 = (pt[1] - qx) * (by - qy) - (bx - qx) * (pt[2] - qy)
                            local d3 = (pt[1] - ax) * (qy - ay) - (qx - ax) * (pt[2] - ay)
                            local neg, pos = d1 < 0 or d2 < 0 or d3 < 0, d1 > 0 or d2 > 0 or d3 > 0
                            if not (neg and pos) then pt[3] = true end
                        end
                    end
                end
            end
        end
    end
    local n = 0
    for _, pt in ipairs(pts) do if pt[3] then n = n + 1 end end
    return n / #pts, tris, front
end

-- ONE FRAME as Garry's Mod runs it here (UNVERIFIED order, the trace lane's): the panel's key, the panel's Think, the Think hooks, PostRender, then the vgui paint of the panel. 60 a second
local DT = 1 / 60
local FAULT = nil               -- the negative control: { at = frame, done = false }
local function frame(key)
    M.dt = DT
    M.T = M.T + DT
    M.frameNo = M.frameNo + 1
    if FR >= 0 then FR = FR + 1 end
    local st = S.st
    if key and st and st.panel and st.panel.OnKeyCodePressed then st.panel:OnKeyCodePressed(key) end
    st = S.st
    if st and st.panel and st.panel.Think then st.panel:Think() end
    M.run_hook("Think")
    M.run_hook("PostRender")
    st = S.st
    if st and st.panel and st.panel.Paint then st.panel:Paint(W, H) end
    -- the negative control, between two frames: the name's picture filled with opaque black (the fix's: its box on the atlas page; beta 1a's: its canvas)
    if FAULT and not FAULT.done and FR == FAULT.at then
        FAULT.done = true
        local t = Hh.mats and Hh.mats.metalsonic and Hh.mats.metalsonic.name
        local s = Hh.state and Hh.state.metalsonic and Hh.state.metalsonic.name
        if type(t) == "table" and t.page and t.aw then
            local rt = t.page.rt
            for y = t.ay, t.ay + t.ah - 1 do
                for x = t.ax, t.ax + t.aw - 1 do
                    local i = y * rt.w + x + 1
                    rt.r[i], rt.g[i], rt.b[i], rt.a[i] = 0, 0, 0, 255
                end
            end
            FAULT.what = string.format("the name's box on %s (%d,%d %dx%d)", tostring(rt.name), t.ax, t.ay, t.aw, t.ah)
        elseif s and s.canvas and s.canvas.rt and s.canvas.rt.Fill then
            s.canvas.rt:Fill(0, 0, 0, 255)
            FAULT.what = "beta 1a's canvas " .. tostring(s.canvas.rt.name)
        end
    end
end

local c0 = os.clock()
local lok, lerr = GSA1.LoadModule()
local dok, derr = GSA1.InitDisc()
local waited = 0
while not REAL.IsReady() and waited < 20000 do
    frame()
    host_sleep(2)
    waited = waited + 1
end
check(REAL.IsReady(), "the disc through the real module (LoadModule %s %s, InitDisc %s %s; %d frames, %.1f s)", tostring(lok), tostring(lerr), tostring(dok), tostring(derr), waited, os.clock() - c0)
if not REAL.IsReady() then return checks, fails end
for _ = 1, 3 do frame() end

FR = 0
local okOpen = S.Open("cmenu")
check(okOpen ~= false and S.st and S.st.design == "R", "Character Select opened on the game's own screen (design %s)", tostring(S.st and S.st.design))
if not (S.st and S.st.design == "R") then return checks, fails end
local function idle(n) for _ = 1, n do frame() end end
local function up(label)
    local s0 = S.st
    local before = s0 and s0.skins and s0.skins[s0.slot] or 1
    for _ = 1, 300 do
        frame(KEY_UP or 88)
        local s1 = S.st
        local now = s1 and s1.skins and s1.skins[s1.slot] or 1
        if now ~= before then return FR end
    end
    check(false, "Up -> %s: no change after 300 frames", label)
    return FR
end
-- the H2 probe on a few frames of each visit (every 45th: the pulse's period)
local H2 = { [1] = {}, [2] = {}, [3] = {} }
local function h2_frames(n, skin)
    for i = 1, n do
        H2ON = i % 45 == 0
        frame()
        if H2ON then
            local r = REC[FR]
            local c = r and r.name
            local cov, tris, frontn = coverage(c and c.box or { 0, 0, 0, 0 })
            if cov then H2[skin][#H2[skin] + 1] = { cov = cov, tris = tris, front = frontn } end
        end
        H2ON = false
    end
end
local t0 = os.clock()
idle(1)
h2_frames(119, 1)
local f_metal = up("Metal Sonic")
h2_frames(420, 2)
local f_mecha = up("Mecha Sonic")
h2_frames(180, 3)
local f_sonic = up("Sonic")
idle(150)
local f_metal2 = up("Metal Sonic again")
-- the second visit: when his name is drawn again, the fault a second later
local f_draw2 = nil
for _ = 1, 30 do
    frame()
    local c = REC[FR] and REC[FR].name
    if c and (c.ret == false or type(c.ret) == "table") then f_draw2 = FR break end
end
FAULT = { at = (f_draw2 or FR) + 60 }
idle(240)
local f_end = FR
info("the run: %d frames after the open (Metal Sonic at %d, Mecha Sonic at %d, Sonic at %d, Metal Sonic again at %d, drawn again at %s; the fault at %d: %s), %.1f s",
    f_end, f_metal, f_mecha, f_sonic, f_metal2, tostring(f_draw2), FAULT.at, tostring(FAULT.what), os.clock() - t0)

-- THE CHECKS -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 1. no render target or material of its own (beta 1a: gsa1_canvas_name_1_1024x256_BGRA8888 and the plate's)
do
    local bad = {}
    for _, r in ipairs(made_rts) do if string.find(r.name, "gsa1_canvas_", 1, true) then bad[#bad + 1] = r.name end end
    for _, r in ipairs(made_mats) do if string.find(r.name, "gsa1_canvas_", 1, true) then bad[#bad + 1] = "material " .. r.name end end
    check(#bad == 0, "no gsa1_canvas_* render target or material was made (%d: %s)", #bad, table.concat(bad, ", "))
end
-- 2. every frame of each visit from the name's first drawn frame on: the name and the plate drawn as atlas pictures with surface.DrawTexturedRectUV at the game's quads, before the ring's neighbour names
local function visit(label, fa, fb, id)
    local first, pics, game, wrong, order, plates, gap = nil, 0, 0, {}, 0, 0, 0
    for f = fa, fb do
        local r = REC[f]
        local c = r and r.name
        if c then
            local pic = c.ret == false and c.truv and c.truv.mat and string.find(tostring(c.truv.mat.params and c.truv.mat.params["$basetexture"]), "gsa1_textpage_", 1, true)
            if pic then
                first = first or f
                pics = pics + 1
                local t = c.truv
                local px, py = math.floor(c.box[1] + 0.5), math.floor(c.box[2] + 0.5)
                if not (t.x == px and t.y == py and t.w == math.floor(c.box[3] + 0.5) - px and t.h == math.floor(c.box[4] + 0.5) - py and t.c[4] == c.vc[4]) then wrong[#wrong + 1] = f end
                if (r.m_tails and r.m_tails < t.seq) or (r.m_supersonic and r.m_supersonic < t.seq) then order = order + 1 end
                local p = r.plate
                if p and p.ret == false and p.truv then plates = plates + 1 end
            elseif first then
                gap = gap + 1
            else
                game = game + 1
            end
        end
    end
    check(first ~= nil and #wrong == 0 and order == 0 and gap == 0 and pics == fb - first + 1,
        "%s: from frame +%s on the name drawn as its atlas picture in every frame (%d of %d) with surface.DrawTexturedRectUV at the game's m_sonic quad, in its colour (%d wrong), before m_tails / m_supersonic (%d after), never back to the game's (%d); the game's own until then (%d frames)",
        label, tostring(first and first - fa), pics, first and (fb - first + 1) or 0, #wrong, order, gap, game)
    check(plates >= pics - 2 and plates > 0, "%s: the plate drawn as its atlas picture at B_SONIC_e's quad too (%d frames)", label, plates)
    return first
end
local first_metal = visit("Metal Sonic", f_metal, f_mecha - 1, "metalsonic")
visit("Mecha Sonic", f_mecha, f_sonic - 1, "mechasonic")
do
    local l1 = logged("Metal Sonic's name in the text pictures' atlas")
    local l2 = logged("skin name drawn for Metal Sonic on Character Select")
    check(l1 ~= nil and l2 ~= nil and string.find(l1, "page 1, 512 x 128", 1, true) ~= nil, "the log: made in the atlas at 2 x on 3440 x 1440 (%s), and drawn (%s)", tostring(l1), tostring(l2))
end
-- 3. the self-check: one page read at most once a second (60 frames), only in frames without a make step
do
    local fs = {}
    for _, c in ipairs(captures) do
        if c.skinhud and not MAKEFRAMES[c.frame] and (not fs[#fs] or fs[#fs] ~= c.f) then fs[#fs + 1] = c.f end
    end
    local close = 0
    for i = 2, #fs do if fs[i] - fs[i - 1] < 59 then close = close + 1 end end
    check(#fs >= 5 and close == 0, "the self-check read %d times in %d frames, never two within a second (%d too close)", #fs, f_end, close)
    -- b1a2-fix2: none of them a capture of a page; each one of the 16 x 4 target the texels are drawn into through the page's material. (On a change only: one texel of the game's own texture,
    -- cl_textures.lua's target of m_sonic, the line's control)
    local page, small, ctl, other = 0, 0, {}, {}
    for _, c in ipairs(captures) do
        if c.skinhud and not MAKEFRAMES[c.frame] then
            if string.find(c.name, "gsa1_textpage_", 1, true) then page = page + 1
            elseif string.find(c.name, "gsa1_textread_", 1, true) and c.w == 16 and c.h == 4 then small = small + 1
            elseif string.match(c.name, "^gsa1_%u%u%u%u8888_[%d_]+$") then ctl[#ctl + 1] = string.format("%s %d x %d", c.name, c.w, c.h)
            else other[#other + 1] = c.name end
        end
    end
    local changes = 0
    for _, l in ipairs(LOG) do if string.find(l.text, "skin pictures check: ", 1, true) and (string.find(l.text, " CHANGED ", 1, true) or string.find(l.text, " NOT READABLE ", 1, true)) then changes = changes + 1 end end
    check(#fs >= 5 and page == 0 and #other == 0 and small >= #fs and #ctl <= changes,
        "b1a2-fix2 the self-check's captures: %d of the 16 x 4 target, %d of a 2048 x 1024 page (8 MiB each), %d of another target (%s); on its %d change(s) only, %d of the game's own texture, the line's control (%s)",
        small, page, #other, table.concat(other, ", "), changes, #ctl, table.concat(ctl, ", "))
    local first = logged("skin pictures check: the first read: ")
    check(first ~= nil and string.find(first, "texels drawn through its material into the 16 x 4 target gsa1_textread_BGRA8888 and read there (256 bytes, where a capture of the whole page is 8 MiB), readable: the read took", 1, true) ~= nil,
        "b1a2-fix2 the log says what the first read read and what it cost: %s", tostring(first))
end
-- 4. the kept line, once, 5 s after the first draw
do
    local line, lf = logged("skin pictures check: Metal Sonic's name read right")
    check(line ~= nil and first_metal and lf - first_metal >= 299 and lf - first_metal <= 301, "the kept line 5 s after the name's first draw (frame +%s): %s", tostring(lf and first_metal and lf - first_metal), tostring(line))
end
-- 5. THE NEGATIVE CONTROL
do
    local line, lf = logged("skin pictures check: Metal Sonic's name CHANGED", FAULT.at - 1)
    local c = lf and REC[lf] and REC[lf].name
    local game_from = c and c.ret == nil and c.game and string.find(c.game, "gsa1hud_", 1, true) and string.find(c.game, "_32_5_0_", 1, true)
    local black, back = 0, nil
    for f = 0, f_end do
        local r = REC[f]
        if r and r.name and r.name.corner == "black" then black = black + 1 end
        if lf and f > lf and r and r.name and r.name.ret == false and not back and r.name.corner == "clear" then back = f end
    end
    check(line ~= nil and lf - FAULT.at <= 60, "NEGATIVE CONTROL (%s): read changed within a second (frame +%s): %s", tostring(FAULT.what), tostring(lf and lf - FAULT.at), tostring(line))
    check(game_from, "NEGATIVE CONTROL: from that frame the game's own name, through cl_hud's material (%s)", tostring(c and c.game))
    check(black <= 60, "NEGATIVE CONTROL: the name's corner black on the screen %d frames in all (at most a second; beta 1a: to the end)", black)
    check(back ~= nil and line and string.find(line, "made again once", 1, true), "NEGATIVE CONTROL: made again once, read right and drawn again from frame +%s", tostring(back and lf and back - lf))
end
-- 5b. b1a2-fix2 THE SMALL READ'S COST here: the self-check's own read (Metal Sonic's name and plate: their clear and ink texels and page 1's canary, 5 texels) timed over 400 reads in Garry's
-- Mod's LuaJIT with the module's real functions. MEASURED here: the Lua side (the fill, five mesh quads, one capture, five ReadPixel) with this stand-in's pixel model drawing in Lua; what the
-- GPU and the render thread add only the game's log can show ("the read took ... ms")
do
    local sn, sp = Hh.state and Hh.state.metalsonic and Hh.state.metalsonic.name, Hh.state and Hh.state.metalsonic and Hh.state.metalsonic.plate
    local req = {}
    for _, s in ipairs({ sn or false, sp or false }) do
        if s and s.pic and s.made and s.made.clearAt and s.made.inkAt and Tx.PicValid and Tx.PicValid(s.pic) then
            req[#req + 1] = { page = s.pic.page, x = s.pic.x + s.made.clearAt[1], y = s.pic.y + s.made.clearAt[2] }
            req[#req + 1] = { page = s.pic.page, x = s.pic.x + s.made.inkAt[1], y = s.pic.y + s.made.inkAt[2] }
        end
    end
    if #req > 0 then req[#req + 1] = { page = req[1].page, x = 1, y = req[1].page.h - 1 } end
    local ms, ok = nil, false
    if Tx.ReadTexels and #req == 5 then
        local got = Tx.ReadTexels(req)
        ok = got ~= nil and #got == 5
        local N = 400
        local c0 = os.clock()
        for _ = 1, N do Tx.ReadTexels(req) end
        ms = (os.clock() - c0) * 1000 / N
    end
    check(ok and ms ~= nil and ms < (Hh.CHECK_SLOW_MS or 10), "b1a2-fix2 one small read of the self-check's 5 texels: %s ms (400 reads, Lua side in this LuaJIT; under the %s ms that would make the checks every 5 s)",
        ms and string.format("%.3f", ms) or "nil", tostring(Hh.CHECK_SLOW_MS))
    if ms then info("the small read here: %.3f ms a read (MEASURED: the Lua side in Garry's Mod's LuaJIT with the stand-in's pixel model; the GPU's share only the game's log shows)", ms) end
end
-- 5c. b1a2-fix2 THE CANARY'S RULE in the real binding: a copy that reads colours at 3/4 (the canary 27 150 69 0, not the painted 37 201 93 0); every picture made again; 7 s on Metal Sonic: the page's
-- canary said once and compared with its make's read from then on: no change, no device reset, no remake, the name drawn from its picture in every frame
do
    local f0 = FR
    XFORM = function(v) return math.floor(v * 0.75) end
    local function lost() return Tx.stats and Tx.stats.lost or 0 end
    local function changed() return Hh.stats and Hh.stats.changed or 0 end
    local lost0, changed0 = lost(), changed()
    if Tx.LoseAll then Tx.LoseAll("the test: a copy that reads colours at 3/4") end
    idle(420)
    local f1 = FR
    local said = logged("text pictures: page 1's canary reads 27 150 69 0 at its make through its material (painted 37 201 93 0)", f0)
    local nsaid = 0
    for _, l in ipairs(LOG) do if l.f > f0 and string.find(l.text, "canary reads", 1, true) then nsaid = nsaid + 1 end end
    local first, pics, gap = nil, 0, 0
    for f = f0 + 1, f1 do
        local c = REC[f] and REC[f].name
        local pic = c and c.ret == false and c.truv and c.truv.mat and string.find(tostring(c.truv.mat.params and c.truv.mat.params["$basetexture"]), "gsa1_textpage_", 1, true)
        if pic then
            first = first or f
            pics = pics + 1
        elseif first then
            gap = gap + 1
        end
    end
    check(said ~= nil and nsaid == 1, "b1a2-fix2 REAL BINDING, a canary read at its make otherwise than painted: said once (%s)", tostring(said))
    check(not logged("CHANGED", f0) and not logged("were lost (device reset)", f0) and lost() == lost0 + 1 and changed() == changed0 and first ~= nil and gap == 0,
        "b1a2-fix2 REAL BINDING, and it still works: no change, no device reset, nothing made again but by the test's own LoseAll; the name drawn from its picture in every frame from +%s (%d frames, %d not)",
        tostring(first and first - f0), pics, gap)
    local kept = logged("skin pictures check: Metal Sonic's name read right", f0)
    check(kept ~= nil and string.find(kept, "page 1's canary 27 150 69 0 as at the make, painted 37 201 93 0", 1, true) ~= nil, "b1a2-fix2 REAL BINDING, read right against its make's read: %s", tostring(kept))
    local n = Tx.CheckLost and Tx.CheckLost() or 0
    check(n >= 1 and lost() == lost0 + 1, "b1a2-fix2 REAL BINDING, T.CheckLost (the focus back) by the same rule: %d page(s) read, nothing lost", n)
    XFORM = nil
end
-- 6. H2 (the judge: not ruled out offline): does a batch of the skin's 3D model cover the name's box where Sonic's does not? A report, not a verdict
do
    local function worst(list)
        local w, n = 0, 0
        for _, x in ipairs(list) do
            w = math.max(w, x.cov)
            n = math.max(n, x.front or 0)
        end
        return w, #list, n
    end
    local s1, n1, t1 = worst(H2[1])
    local s2, n2, t2 = worst(H2[2])
    local s3, n3, t3 = worst(H2[3])
    info("H2: the 3D pass's triangles over the name's box (a grid of 144 points, projected through the view cam.Start3D got): Sonic %.0f %% (%d frames, %d triangles in front), Metal Sonic %.0f %% (%d, %d), Mecha Sonic %.0f %% (%d, %d)%s",
        100 * s1, n1, t1, 100 * s2, n2, t2, 100 * s3, n3, t3, (s2 > s1 + 0.02 or s3 > s1 + 0.02) and (math.max(s2, s3) < 0.25 and ": a skin's model reaches a little further into the name's box than Sonic's, too little to cover the name"
            or ": A SKIN'S MODEL COVERS THE NAME WHERE SONIC'S DOES NOT") or ": no skin's model covers more of it than Sonic's own")
end
if S.st then S.Close("the test") end
info("what only the game can show: what the engine does to a page in the owner's session (the log's \"skin pictures check\" lines), and the screen itself")
return checks, fails
