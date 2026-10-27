-- feat_hud_test.lua - the HUD feature's addon side (addon/lua/gsa1/feat/cl_hud.lua; round 0.9.1, sadc
-- docs/research/gsa1_070_hud.md F8 with its review R.5.7) in Garry's Mod's own LuaJIT: the client through the autorun
-- against tests/lua_mock.lua and a mock of the module's HUD functions (bind_hud.cpp's Lua API: HudSettings, HudSetTime,
-- HudCounters, HudScreen, gsa1.HUD; every call recorded) with a synthetic screen - the game's HUD as libsa1 hands it
-- over (the TIME label / ring icon, ring, lives and timer digits at the game's places), Big's reel (turned) and his
-- line-tension bar (an opaque gouraud polygon), E-102's "+N" counter on its way to the timer, the drowning countdown
-- (task 8C07BE6E) and a draw whose texture libsa1 does not load.
--   lua_host tests/feat_hud_test.lua <tests dir> <addon/lua dir>
-- Checks: the settings and their defaults (owner 14.1h; round 5's switch names kept), each with a control on the HUD
-- page; the layout maths (640 x 480 the identity; 3440 x 1440: scale 3, offsets 0 / 1520 / 760 for left / right / centre
-- elements, the box 760; 1920 x 1080; 4:3; 5:4 (bottom elements to the bottom edge); the size and edge-distance options);
-- the settings sent to the character (parts mask, clock, E-102's limit) and again on a change; a frame at 3440 x 1440
-- drawn where the layout says (corners, the countdown above the character as Garry's Mod's camera sees it, a turned
-- sprite's corners), with the game's UVs, colours and blend, nothing drawn before a texture is painted and nothing for an
-- unloaded texture, the screen copied only when it changed; the box layout, 1920 x 1080, 4:3, 5:4, the size and the edge
-- distance; hidden without a character, with gsa1_hud 0, through a camera and with cl_drawhud 0; Garry's Mod's health
-- hidden only while the HUD shows in rings mode; the time kept for a respawn and a re-creation (not for another
-- character, not with the option off); the score row; the session log; a module without the feature.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_hud_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

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
            if string.find(n, "_hud%.lua$") then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end

-- what the mock lacks: drawing recorded vertex by vertex, the text, a projection for Vector:ToScreen
MATERIAL_QUADS, MATERIAL_LINES = 7, 1
local prims, verts, blends, texts = {}, {}, {}, {}
local cur = {}
mesh.Begin = function(prim, n) prims[#prims + 1] = { prim = prim, n = n, mat = M.current, first = #verts + 1 } end
mesh.Position = function(v) cur.x, cur.y = v.x, v.y end
mesh.TexCoord = function(_, u, v) cur.u, cur.v = u, v end
mesh.Color = function(r, g, b, a) cur.r, cur.g, cur.b, cur.a = r, g, b, a end
mesh.AdvanceVertex = function()
    verts[#verts + 1] = { x = cur.x, y = cur.y, u = cur.u, v = cur.v, r = cur.r, g = cur.g, b = cur.b, a = cur.a,
                          mat = M.current }
end
mesh.End = function() end
render.OverrideBlend = function(on, s, d) blends[#blends + 1] = { on = on, s = s, d = d } end
draw.SimpleText = function(text, font, x, y) texts[#texts + 1] = { text = text, font = font, x = x, y = y } end
surface.CreateFont = function() end
local head = { x = 1720, y = 900, visible = true }
getmetatable(Vector()).ToScreen = function() return { x = head.x, y = head.y, visible = head.visible } end
local function clear()
    prims, verts, blends, texts = {}, {}, {}, {}
end
M.cv("cl_drawhud", "1")
-- Garry's Mod's hook.Run (cl_character.lua 0.9.1 runs the features' hooks GSA1CharacterCreated / Leaving through it)
hook.Run = function(name, ...) return M.run_hook(name, ...) end
M.cv("gsa1_sv_damage_mode", "0")

-- the module: the HUD functions -------------------------------------------------------------------------------------------
local G = M.module({ features = { hud = 1 } })
local MOD = { calls = {}, counters = {}, score = 120, copies = 0 }
local function rec(name, ...) MOD.calls[#MOD.calls + 1] = { name, ... } end
local function calls_of(name)
    local out = {}
    for _, c in ipairs(MOD.calls) do if c[1] == name then out[#out + 1] = c end end
    return out
end
G.HUD = { RINGS = 1, LIVES = 2, TIME = 4, CHARACTER = 8, ALL = 15, D = 11, S = 15, V = 8 }
local CON = 4                                   -- CON_REGULAR's archive index in this mock
G.TextureArchives = function()
    return { { name = "SONIC", count = 30 }, { name = "SON_EFF", count = 20 }, { name = "OBJ_REGULAR", count = 96 },
             { name = "EFF_REGULAR", count = 40 }, { name = "CON_REGULAR", count = 56 } }
end
function G.HudSettings(id, parts, clock, free) rec("HudSettings", id, parts, clock, free) return true end
function G.HudSetTime(id, m, s, f) rec("HudSetTime", id, m, s, f) return true end
function G.HudCounters(id)
    local t = MOD.counters[id] or { 0, 0, 0 }
    return t[1], t[2], t[3], true, MOD.score, 7, 4
end

-- the synthetic screen: draws {prim, first, count, archive, texture, flags, src, dst, priority, part, source}, sprites
-- {x0, y0, x1, y1, px, py, angle, u0, v0, u1, v1, r, g, b, a}, vertices {x, y, u, v, r, g, b, a}
local BLEND, UNLIT, NO_TEXTURE = 0x1, 0x10, 0x80
local SRC_BIG_LURE, SRC_BONUS, SRC_COUNTDOWN = 0x8C0E943C, 0x8C0D520A, 0x8C07BE6E
local SCR = { gen = 1, draws = {}, sprites = {}, verts = {} }
local function sprite(x, y, w, h, cell, part, source, t)
    t = t or {}
    local first = #SCR.sprites
    SCR.sprites[#SCR.sprites + 1] = { t.x0 or 0, t.y0 or 0, t.x1 or w, t.y1 or h, x, y, t.angle or 0, 0, t.v0 or 0, 1, 1,
                                      255, t.g or 255, t.g or 255, 255 }
    SCR.draws[#SCR.draws + 1] = { 1, first, 1, t.archive or CON, cell, (t.flags or 0) + BLEND + UNLIT, 4, 5,
                                  t.pri or -1.5, part, source or 0 }
end
-- the tension bar first: the opaque draws come first (an untextured gouraud quad as two triangles)
local bar = { { 574, 368 }, { 606, 368 }, { 606, 233 }, { 574, 368 }, { 606, 233 }, { 574, 233 } }
for i, p in ipairs(bar) do
    SCR.verts[i] = { p[1], p[2], 0, 0, 255, p[2] < 300 and 0 or 255, 255, 255 }
end
SCR.draws[#SCR.draws + 1] = { 0, 0, 6, -1, -1, UNLIT, 1, 0, -1.82, 8, SRC_BIG_LURE }
sprite(16, 32, 64, 64, 11, 1)                                       -- the TIME label and the ring icon
sprite(46, 52, 16, 16, 0, 1, 0, { g = 128 })                        -- ring digits "007", blinking at no rings
sprite(62, 52, 16, 16, 0, 1, 0, { g = 128 })
sprite(78, 52, 16, 16, 7, 1, 0, { g = 128 })
sprite(16, 400, 32, 32, 12, 2)                                      -- the life icon and "04"
sprite(49, 416, 16, 16, 0, 2)
sprite(65, 416, 16, 16, 4, 2)
for k = 0, 7 do sprite(64 + 16 * k, 33, 16, 16, k == 2 and 10 or k, 4) end   -- the timer
sprite(592, 394, 64, 32, 58, 8, SRC_BIG_LURE, { archive = 1, x0 = -20, y0 = -16, x1 = 44, y1 = 16,
                                                 angle = math.pi / 2 })            -- Big's reel, turned
sprite(400, 120, 16, 16, 33, 8, SRC_BONUS, { archive = 1 })         -- E-102's "+N" on its way to the timer
sprite(320, 224, 32, 32, 5, 8, SRC_COUNTDOWN)                       -- the drowning countdown "5"
sprite(300, 300, 16, 16, 9, 8, 0x8C0FFFF0, { flags = NO_TEXTURE, archive = -1 })   -- an unloaded texture
function G.HudScreen(id, out, force)
    if out.id == id and out.gen == SCR.gen and not force then return SCR.gen, false end
    MOD.copies = MOD.copies + 1
    out.id, out.gen, out.w, out.h, out.nd, out.ns, out.nv = id, SCR.gen, 640, 480, #SCR.draws, #SCR.sprites, #SCR.verts
    out.d, out.s, out.v = out.d or {}, out.s or {}, out.v or {}
    for i, d in ipairs(SCR.draws) do for k = 1, 11 do out.d[(i - 1) * 11 + k] = d[k] end end
    for i, s in ipairs(SCR.sprites) do for k = 1, 15 do out.s[(i - 1) * 15 + k] = s[k] end end
    for i, v in ipairs(SCR.verts) do for k = 1, 8 do out.v[(i - 1) * 8 + k] = v[k] end end
    return SCR.gen, true
end

-- the client: the autorun ---------------------------------------------------------------------------------------------------
GSA1 = nil
M.included = {}
local ok_c, err_c = pcall(M.load, "autorun/gsa1_autorun.lua")
local H = GSA1 and GSA1.Hud
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
check(ok_c and #ferr == 0 and H ~= nil and H.Paint ~= nil, "the client loads cl_hud through the autorun (%s)",
    ok_c and table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_c or ferr[1]))
if not H then return done() end
check(#MOD.calls == 0 and GSA1.Tex.NO_PREPARE.CON_REGULAR == true and GSA1.Tex.NO_PREPARE.OBJ_REGULAR == true,
    "nothing calls the module while the files load; CON_REGULAR is not painted at a spawn (made at its first use)")

-- 1. settings: defaults and every one on the HUD page -------------------------------------------------------------------------
local function cvv(name) local c = M.convars[name] return c and c.v end
local MINE = { "gsa1_hud", "gsa1_hud_rings", "gsa1_hud_lives", "gsa1_hud_time", "gsa1_hud_character", "gsa1_hud_score",
               "gsa1_hud_scale", "gsa1_hud_safe", "gsa1_hud_layout", "gsa1_hud_filter", "gsa1_hud_hide_gmod",
               "gsa1_hud_keep_time", "gsa1_clock", "gsa1_e102_time_limit" }
check(cvv("gsa1_hud") == "1" and cvv("gsa1_hud_rings") == "1" and cvv("gsa1_hud_lives") == "1" and
    cvv("gsa1_hud_time") == "1" and cvv("gsa1_hud_character") == "1" and cvv("gsa1_hud_score") == "0" and
    cvv("gsa1_hud_scale") == "1" and cvv("gsa1_hud_safe") == "0" and cvv("gsa1_hud_layout") == "0" and
    cvv("gsa1_hud_filter") == "0" and cvv("gsa1_hud_hide_gmod") == "1" and cvv("gsa1_hud_keep_time") == "1" and
    cvv("gsa1_clock") == "1" and cvv("gsa1_e102_time_limit") == "0",
    "defaults (owner 14.1h): the HUD on with every part, the score off (round 5's), size 1, the corners, smooth, Garry's "
    .. "Mod's health hidden, the time kept, the clock running, E-102's limit off")
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
for _, e in ipairs(M.menu) do if e.class == "gsa1_feat_hud" then entry = e end end
check(entry and entry.name == "HUD" and entry.category == "G-SA1", "the page Options -> G-SA1 -> HUD")
if not entry then return done() end
local panel = standin("DForm")
entry.cpanel(panel)
local bound = {}
for _, P in ipairs(made) do
    for _, c in ipairs(P.calls) do
        if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then bound[c[3]] = true end
    end
end
-- the combo boxes set their ConVar through OnSelect: choose "1" in each, see which setting changed, put them back
local ncombo = 0
for _, P in ipairs(made) do
    if P.kind == "ComboBox" and P.OnSelect then
        ncombo = ncombo + 1
        local before = {}
        for _, name in ipairs(MINE) do before[name] = cvv(name) end
        P.OnSelect(P, 2, "x", "1")
        for _, name in ipairs(MINE) do
            if cvv(name) ~= before[name] then bound[name] = true end
            M.convars[name]:SetString(before[name])
        end
    end
end
local missing, listed = {}, {}
for _, name in ipairs(MINE) do
    listed[name] = true
    if not GSA1.CONVARS[name] then missing[#missing + 1] = name .. " (not made)" elseif not bound[name] then
        missing[#missing + 1] = name end
end
for name in pairs(GSA1.CONVARS) do
    if string.find(name, "^gsa1_hud") and not listed[name] then missing[#missing + 1] = name .. " (not listed here)" end
end
check(#missing == 0 and ncombo == 2, "every HUD setting has a control on the page (check boxes, sliders, %d combo "
    .. "boxes)%s", ncombo, #missing > 0 and (": missing " .. table.concat(missing, ", ")) or "")
local ip = standin("DForm")
H.MenuControls(ip)
check(ip.calls[1] and ip.calls[1][1] == "CheckBox" and ip.calls[1][3] == "gsa1_hud", "the Interaction page's HUD "
    .. "section: the on / off switch and a pointer to the HUD page")

-- 2. the layout maths ---------------------------------------------------------------------------------------------------------
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.01) end
local function place(W, Hh, scale, safe, box, x, y, xc, yc)
    local m = H.Metrics(W, Hh, scale, safe, box, {})
    return H.Place(m, x, y, xc or x, yc or y)
end
local ax, ay = place(640, 480, 1, 0, false, 600, 400)
local bx, by = place(640, 480, 1, 0, false, 16, 32)
check(near(ax, 600) and near(ay, 400) and near(bx, 16) and near(by, 32), "640 x 480: the identity")
local m3 = H.Metrics(3440, 1440, 1, 0, false, {})
local lx = H.Place(m3, 16, 32, 48, 64)
local rx = H.Place(m3, 592, 394, 590, 300)
local cx = H.Place(m3, 320, 380, 320, 400)
local bxx = H.Place(H.Metrics(3440, 1440, 1, 0, true, {}), 16, 32, 48, 64)
check(near(m3.s, 3) and near(lx - 16 * 3, 0) and near(rx - 592 * 3, 1520) and near(cx - 320 * 3, 760) and
    near(bxx - 16 * 3, 760), "3440 x 1440: scale %.2f; offsets left %.0f, right %.0f, centre %.0f; the box %.0f", m3.s,
    lx - 48, rx - 1776, cx - 960, bxx - 48)
local m2 = H.Metrics(1920, 1080, 1, 0, false, {})
check(near(m2.s, 2.25) and near(H.Place(m2, 592, 394, 590, 300) - 592 * 2.25, 480) and
    near(H.Place(m2, 320, 380, 320, 400) - 320 * 2.25, 240), "1920 x 1080: scale 2.25, right +480, centre +240")
local m4 = H.Metrics(1024, 768, 1, 0, false, {})
local x4, y4 = H.Place(m4, 592, 416, 590, 416)
check(near(m4.s, 1.6) and near(x4, 592 * 1.6) and near(y4, 416 * 1.6), "4:3 (1024 x 768): scale 1.6, no offsets")
local m5 = H.Metrics(1280, 1024, 1, 0, false, {})
local _, y5 = H.Place(m5, 16, 416, 30, 416)
local _, y5t = H.Place(m5, 16, 32, 48, 64)
check(near(m5.s, 2) and near(y5, 416 * 2 + 64) and near(y5t, 64), "5:4 (1280 x 1024): scale 2 by the width; the lives "
    .. "at the bottom edge (%.0f), the top-left elements at the top (%.0f)", y5, y5t)
local mh = H.Metrics(3440, 1440, 0.5, 0, false, {})
local hx, hy = H.Place(mh, 16, 416, 30, 416)
local hrx = H.Place(mh, 592, 394, 590, 300)
check(near(mh.s, 1.5) and near(hx, 24) and near(hy, 416 * 1.5 + 720) and near(hrx, 592 * 1.5 + 2480),
    "size 0.5 at 3440 x 1440: scale 1.5, the corners stay corners (lives y %.0f, the reel x %.0f)", hy, hrx)
local ms = H.Metrics(3440, 1440, 1, 5, false, {})
local sx1, sy1 = H.Place(ms, 16, 32, 48, 64)
local sx2 = H.Place(ms, 592, 394, 590, 300)
local sx3 = H.Place(ms, 320, 380, 320, 400)
check(near(sx1, 48 + 172) and near(sy1, 96 + 72) and near(sx2, 1776 + 1520 - 172) and near(sx3, 960 + 760),
    "5 %% from the edges: left +172, top +72, right -172, the centre unchanged")

-- 3. a character: the settings it gets ---------------------------------------------------------------------------------------
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil, "Sonic spawned")
if not C then return done() end
if GSA1.RunHook then
    local early = calls_of("HudSettings")
    check(#early == 1 and early[1][2] == C.id, "cl_character.lua's GSA1CharacterCreated: the settings reach the world "
        .. "before its first tick")
else
    info("cl_character.lua without the features' hooks: the settings follow at the next frame (Think)")
end
M.frame(1 / 60)
local hs = calls_of("HudSettings")
check(#hs == 1 and hs[1][2] == C.id and hs[1][3] == 15 and hs[1][4] == 1 and hs[1][5] == 1,
    "the first frame sends the settings: parts 15 (all), the clock 1, E-102's limit off (no-limit 1): %s",
    hs[1] and table.concat({ tostring(hs[1][3]), tostring(hs[1][4]), tostring(hs[1][5]) }, " ") or "none")
M.frame(1 / 60)
check(#calls_of("HudSettings") == 1, "unchanged settings are not sent again")
M.convars.gsa1_hud_rings:SetString("0")
M.convars.gsa1_clock:SetString("0")
M.frame(1 / 60)
M.convars.gsa1_hud_rings:SetString("1")
M.convars.gsa1_clock:SetString("1")
M.convars.gsa1_e102_time_limit:SetString("1")
M.frame(1 / 60)
M.convars.gsa1_hud:SetString("0")
M.frame(1 / 60)
M.convars.gsa1_hud:SetString("1")
M.convars.gsa1_e102_time_limit:SetString("0")
M.frame(1 / 60)
hs = calls_of("HudSettings")
local function hsv(i) local c = hs[i] return c and (c[3] .. "/" .. c[4] .. "/" .. c[5]) or "-" end
check(#hs == 5 and hsv(2) == "14/0/1" and hsv(3) == "15/1/0" and hsv(4) == "0/1/0" and hsv(5) == "15/1/1",
    "changes are sent at the next frame: rings off + clock off %s, E-102's limit on %s, the HUD off %s (no HUD calls in "
    .. "the world), back %s", hsv(2), hsv(3), hsv(4), hsv(5))

-- 4. a frame at 3440 x 1440 -----------------------------------------------------------------------------------------------------
M.scrw, M.scrh = 3440, 1440
clear()
M.run_hook("HUDPaint")
local waiting = H.lastWaiting or 0
local first_prims = #prims
check(first_prims == 1 and waiting > 0, "the first frame: only the untextured bar is drawn, %d draws wait for their "
    .. "textures (a render target is opaque black until it is painted)", waiting)
for _ = 1, 30 do M.run_hook("PostRender") end
clear()
M.run_hook("HUDPaint")
-- vertex lookups
-- the quad whose first corner (the sprite's x0, y0) is at (x, y)
local function quad_at(x, y)
    for _, p in ipairs(prims) do
        if p.prim == 7 then
            for q = 0, p.n - 1 do
                local i = p.first + 4 * q
                local v = verts[i]
                if v and near(v.x, x, 0.05) and near(v.y, y, 0.05) then return i end
            end
        end
    end
end
local function quad_text(i)
    if not i then return "none" end
    local v = verts[i]
    return string.format("(%.1f, %.1f)", v.x, v.y)
end
local nq = 0
for _, p in ipairs(prims) do if p.prim == 7 then nq = nq + p.n end end
local label, ring0, life, timer0 = quad_at(48, 96), quad_at(138, 156), quad_at(48, 1200), quad_at(192, 99)
check(H.lastWaiting == 0 and nq == 18 and label and ring0 and life and timer0,
    "painted: 18 sprites drawn (the unloaded texture left out); the TIME label at (48, 96), ring digit (138, 156), the "
    .. "life icon (48, 1200), the timer (192, 99): the top-left and bottom-left corners at scale 3")
local lv = label and verts[label]
local lv3 = label and verts[label + 2]
check(lv and lv.u == 0 and lv.v == 0 and lv3 and lv3.u == 1 and lv3.v == 1 and near(lv3.x, 48 + 192) and
    near(lv3.y, 96 + 192) and lv.mat and lv.mat.shader == "UnlitGeneric" and lv.mat.params["$translucent"] == 1 and
    lv.mat.params["$vertexalpha"] == 1 and string.find(lv.mat.params["$basetexture"], "_" .. CON .. "_11_3$") ~= nil,
    "the label quad: UVs 0..1, 192 x 192 px, an unlit translucent material on CON_REGULAR cell 11's render target "
    .. "(%s, clamped, smooth)", lv and lv.mat and tostring(lv.mat.params["$basetexture"]) or "?")
local rv = ring0 and verts[ring0]
check(rv and rv.r == 255 and rv.g == 128 and rv.b == 128 and rv.a == 255, "the ring digits carry the game's colour (the "
    .. "zero-ring blink: %s %s %s %s)", rv and rv.r, rv and rv.g, rv and rv.b, rv and rv.a)
local translucent_blends = 0
for _, b in ipairs(blends) do if b.on and b.s == 4 and b.d == 5 then translucent_blends = translucent_blends + 1 end end
check(translucent_blends == 18, "every blended draw with the game's SRC_ALPHA / INV_SRC_ALPHA (%d of 18)",
    translucent_blends)
-- Big's gauge element (the bar and the reel): the right edge
local bar_v
for _, p in ipairs(prims) do if p.prim == 2 then bar_v = verts[p.first] end end
check(bar_v and near(bar_v.x, 574 * 3 + 1520) and near(bar_v.y, 368 * 3) and bar_v.mat and
    bar_v.mat.params["$translucent"] == nil and string.find(bar_v.mat.params["$basetexture"], "white", 1, true),
    "Big's tension bar: 2 triangles at the right edge (x %s), opaque, untextured", bar_v and string.format("%.0f", bar_v.x)
    or "?")
-- the reel turned by 90 degrees: its corner (x0, y0) = (-20, -16) goes to (16, -20) around the pivot
local reel = quad_at((592 + 16) * 3 + 1520, (394 - 20) * 3)
check(reel ~= nil, "Big's reel turned (angle 90 degrees): its first corner at %s", quad_text(reel))
local bonus = quad_at(400 * 3 + 1520 * 0.775, 120 * 3)
check(bonus ~= nil, "E-102's \"+N\" between the right edge and the timer: anchored at t = 0.775 (x %.0f)",
    400 * 3 + 1520 * 0.775)
local count_q = quad_at(1720 + (320 - 320) * 3, 900 + (224 - (240 + 7 * 457.06 / 40)) * 3)
check(count_q ~= nil, "the drowning countdown above the character as Garry's Mod's camera sees it (the head at (1720, "
    .. "900): %s)", quad_text(count_q))
local mats_n = H.nmats
M.run_hook("HUDPaint")
check(MOD.copies == 1 and H.nmats == mats_n, "the next frame: the screen is not copied again (the same generation; %d "
    .. "copies), no new material", MOD.copies)
SCR.gen = 2
clear()
M.run_hook("HUDPaint")
check(MOD.copies == 2 and #prims > 0, "a new pair (generation 2): copied again")
head.visible = false
clear()
M.run_hook("HUDPaint")
local cnt2 = quad_at(320 * 3 + 1520 * (336 - 160) / 320, 224 * 3)
check(cnt2 ~= nil, "the character off screen: the countdown where the game put it, anchored as any element (%s)",
    quad_text(cnt2))
head.visible = true

-- 5. the other layouts ---------------------------------------------------------------------------------------------------------
M.convars.gsa1_hud_layout:SetString("1")
clear()
M.run_hook("HUDPaint")
check(quad_at(48 + 760, 96) and quad_at(48 + 760, 1200) and quad_at((592 + 16) * 3 + 760, (394 - 20) * 3) and
    quad_at(400 * 3 + 760, 120 * 3), "the centred 4:3 box: everything +760 (the label at (808, 96), the reel, E-102's "
    .. "\"+N\")")
M.convars.gsa1_hud_layout:SetString("0")
M.scrw, M.scrh = 1920, 1080
clear()
M.run_hook("HUDPaint")
check(quad_at(36, 72) and quad_at(36, 900) and quad_at(78 * 2.25, 52 * 2.25), "1920 x 1080: scale 2.25 (the label at "
    .. "(36, 72), the life icon at (36, 900))")
M.scrw, M.scrh = 1024, 768
clear()
M.run_hook("HUDPaint")
check(quad_at(16 * 1.6, 32 * 1.6) and quad_at(16 * 1.6, 400 * 1.6), "4:3 (1024 x 768): scale 1.6, no offsets")
M.scrw, M.scrh = 1280, 1024
clear()
M.run_hook("HUDPaint")
check(quad_at(32, 64) and quad_at(32, 864), "5:4 (1280 x 1024): the lives at the bottom edge (y 864)")
M.scrw, M.scrh = 3440, 1440
M.convars.gsa1_hud_scale:SetString("0.5")
M.convars.gsa1_hud_safe:SetString("5")
clear()
M.run_hook("HUDPaint")
check(quad_at(24 + 172, 48 + 72) and quad_at(24 + 172, 600 + 720 - 72), "size 0.5 and 5 %% from the edges at 3440 x "
    .. "1440: the label at (196, 120), the life icon at (196, 1248)")
M.convars.gsa1_hud_scale:SetString("1")
M.convars.gsa1_hud_safe:SetString("0")
M.convars.gsa1_hud_filter:SetString("1")
clear()
M.run_hook("HUDPaint")
for _ = 1, 30 do M.run_hook("PostRender") end
clear()
M.run_hook("HUDPaint")
local sl = quad_at(48, 96)
check(sl and string.find(verts[sl].mat.params["$basetexture"], "_" .. CON .. "_11_7$") ~= nil, "sharp textures: the "
    .. "point-sampled render target (address mode 7): %s", sl and verts[sl].mat.params["$basetexture"] or "?")
M.convars.gsa1_hud_filter:SetString("0")

-- 6. hidden ------------------------------------------------------------------------------------------------------------------
local function drawn_now()
    clear()
    M.run_hook("HUDPaint")
    return #prims
end
local n_on = drawn_now()
M.convars.gsa1_hud:SetString("0")
local n_off = drawn_now()
M.convars.gsa1_hud:SetString("1")
M.player.view_entity = { class = "gmod_cameraprop" }
local n_cam = drawn_now()
M.player.view_entity = nil
M.convars.cl_drawhud:SetString("0")
local n_dh = drawn_now()
M.convars.cl_drawhud:SetString("1")
check(n_on > 0 and n_off == 0 and n_cam == 0 and n_dh == 0, "hidden with gsa1_hud 0 (%d), through a camera (%d), with "
    .. "cl_drawhud 0 (%d); shown otherwise (%d draws)", n_off, n_cam, n_dh, n_on)
local hh = M.run_hook("HUDShouldDraw", "CHudHealth")
local hb = M.run_hook("HUDShouldDraw", "CHudBattery")
local hc = M.run_hook("HUDShouldDraw", "CHudChat")
M.convars.gsa1_sv_damage_mode:SetString("1")
local hh_health = M.run_hook("HUDShouldDraw", "CHudHealth")
M.convars.gsa1_sv_damage_mode:SetString("0")
M.convars.gsa1_hud_hide_gmod:SetString("0")
local hh_opt = M.run_hook("HUDShouldDraw", "CHudHealth")
M.convars.gsa1_hud_hide_gmod:SetString("1")
check(hh == false and hb == false and hc == nil and hh_health == nil and hh_opt == nil, "Garry's Mod's health and suit "
    .. "hidden while the HUD shows in rings mode; shown in health mode and with the option off; other HUD elements "
    .. "untouched")

-- 7. the score row ------------------------------------------------------------------------------------------------------------
M.convars.gsa1_hud_score:SetString("1")
clear()
M.run_hook("HUDPaint")
for _ = 1, 30 do M.run_hook("PostRender") end
clear()
M.run_hook("HUDPaint")
local digits, digit_tex = 0, {}
for k = 0, 6 do
    local i = quad_at((64 + 16 * k) * 3, 98 * 3)
    if i then
        digits = digits + 1
        digit_tex[#digit_tex + 1] = string.match(verts[i].mat.params["$basetexture"], "_(%d+)_3$") or "?"
    end
end
local label_t = texts[1]
check(digits == 7 and table.concat(digit_tex, "") == "0000120" and label_t and label_t.text == "SCORE" and
    near(label_t.x, 48) and near(label_t.y, 297), "the score row: \"SCORE\" and 7 of the game's digits (CON_REGULAR "
    .. "cells %s) under the ring icon", table.concat(digit_tex, ","))
M.convars.gsa1_hud_score:SetString("0")

-- 8. the time across a respawn ------------------------------------------------------------------------------------------------
MOD.counters[C.id] = { 1, 23, 45 }
M.frame(1 / 60)
local old_id = C.id
GSA1.Respawn("test")
local C2 = GSA1.Char
M.frame(1 / 60)
local st = calls_of("HudSetTime")
check(C2 and C2.id ~= old_id and #st == 1 and st[1][2] == C2.id and st[1][3] == 1 and st[1][4] == 23 and st[1][5] == 45,
    "a respawn keeps the time: HudSetTime(%s, %s, %s, %s) on the new character", st[1] and st[1][2], st[1] and st[1][3],
    st[1] and st[1][4], st[1] and st[1][5])
hs = calls_of("HudSettings")
check(hs[#hs][2] == C2.id and hs[#hs][3] == 15, "and its settings")
MOD.counters[C2.id] = { 0, 10, 0 }
M.frame(1 / 60)
GSA1.Recreate("test")
M.frame(1 / 60)
st = calls_of("HudSetTime")
check(#st == 2 and st[2][2] == GSA1.Char.id and st[2][4] == 10, "a re-creation (upgrades) keeps it too")
MOD.counters[GSA1.Char.id] = { 2, 0, 0 }
M.frame(1 / 60)
GSA1.Spawn("tails")
M.frame(1 / 60)
check(#calls_of("HudSetTime") == 2, "another character starts at 00:00:00 (no HudSetTime)")
M.convars.gsa1_hud_keep_time:SetString("0")
MOD.counters[GSA1.Char.id] = { 3, 0, 0 }
M.frame(1 / 60)
GSA1.Respawn("test")
M.frame(1 / 60)
check(#calls_of("HudSetTime") == 2, "keep the time off: a respawn starts at 00:00:00")
M.convars.gsa1_hud_keep_time:SetString("1")
-- an older cl_character.lua without the features' hooks: Think notices the new character at its next frame
local run = hook.Run
hook.Run = nil
MOD.counters[GSA1.Char.id] = { 4, 5, 6 }
M.frame(1 / 60)
GSA1.Respawn("test")
M.frame(1 / 60)
st = calls_of("HudSetTime")
hs = calls_of("HudSettings")
check(#st == 3 and st[3][2] == GSA1.Char.id and st[3][3] == 4 and st[3][5] == 6 and hs[#hs][2] == GSA1.Char.id,
    "without cl_character.lua's hooks: the next frame keeps the time (%s:%s:%s) and sends the settings", st[3] and st[3][3],
    st[3] and st[3][4], st[3] and st[3][5])
hook.Run = run
GSA1.Remove(true)
M.frame(1 / 60)
local n_none = drawn_now()
check(n_none == 0 and M.run_hook("HUDShouldDraw", "CHudHealth") == nil, "no character: no HUD, Garry's Mod's health shown")

-- 9. the session log ------------------------------------------------------------------------------------------------------------
GSA1.LogFlush()
local logtext = M.files["gsa1/log.txt"] or ""
check(string.find(logtext, "HUD of Sonic: parts rings lives time character, size 1.00 (x3.00 at 3440x1440), the corners "
    .. "of the screen, smooth textures", 1, true) ~= nil and string.find(logtext, "the time 01:23:45 kept for the new "
    .. "Sonic", 1, true) ~= nil and string.find(logtext, "Sonic: HUD parts rings lives time character, the clock runs, "
    .. "E-102's time limit off", 1, true) ~= nil, "the session log has the HUD's settings, its first frame and the kept time")

-- 10. a module without the feature -------------------------------------------------------------------------------------------
local n_calls = #MOD.calls
M.module({ features = {} })
GSA1.LoadModule()
GSA1.Spawn("sonic")
M.frame(1 / 60)
local n_old = drawn_now()
check(#MOD.calls == n_calls and n_old == 0, "a module without the HUD: no HUD calls, nothing drawn")
made = {}
M.menu = {}
M.run_hook("PopulateToolMenu")
for _, e in ipairs(M.menu) do if e.class == "gsa1_feat_hud" then entry = e end end
local panel2 = standin("DForm")
entry.cpanel(panel2)
local t2 = {}
for _, c in ipairs(panel2.calls) do t2[#t2 + 1] = c[1] .. "(" .. tostring(c[2]) .. ")" end
check(string.find(table.concat(t2, " "), "0.9.1", 1, true) ~= nil, "its page says it needs G-SA1 module 0.9.1")
check(#M.reported == 0, "no Lua error%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
return done()
