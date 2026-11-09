-- feat_skintex_test.lua - the skins' textures in the addon (1.0.0-beta1a, lane b1a-tex; the owner on beta 1: "Metal Sonic and Mecha Sonic are PURE WHITE"):
-- cl_textures.lua's self-check lines and cl_warm.lua's pre-warm of a skin, in Garry's Mod's own LuaJIT with a mocked GMod client (tests/lua_mock.lua).
--   lua_host tests/feat_skintex_test.lua <tests dir> <addon/lua dir>
-- A MOCK proves nothing about what the module answers (that is tests/feat_skintex_binding_test.cpp, the module's real functions in the same LuaJIT): this
-- test pins what the ADDON does with the answers. Its module mock answers as beta 1's module did (every archive above 63 refused with the usage line,
-- the owner's log) and as the fixed one does.
--   * T.SkinCheck: the first texture asked of a skin's archive (64 .. 79) asks every texture of it once, lists each for painting and writes ONE line,
--     "skin textures: <title>, archive <a>: the module gives <given> of <n> (painted next, then read back)" ("(the others draw white)" when short); beta 1's
--     answers give the refusal or "0 of 9"; the title comes from cl_warm.lua's spawn, your character, a follower or Character Select's circle (only when the
--     circle draws from that archive: the verifier's LOW); never twice for one archive; a plain archive (0 .. 63) has no such line.
--   * T.SkinPaintCheck (the verifier's LOW: the first line only says the module gave the runs): once the painting is idle, ONE more line per archive: the
--     textures painted into render targets, one render target read back (one render.CapturePixels) against the module's runs, the skin's batch materials
--     textured / white: "... 22 of 22 made (painted; read back 8 of 8 texels as the module gives them; its batches: 1 textured, 0 white)"; never while the
--     painting runs; a wrong read-back, red and blue swapped, no read-back and a refused texture each say so. Painting is modelled on a pixel buffer per
--     render target (Source's opaque-black creation clear, colour-only render.Clear, vgui skipping alpha-0 rects, OverrideBlend's separate alpha).
--   * cl_warm.lua: a character wearing a skin is warmed (beta 1 skipped it): every texture of its archive in the body's state, none of the base's body
--     (archive 0) census states, the base's effects as before; the line is written even with gsa1_prewarm 0; a module without gsa1.SkinArchive: no pre-warm
--     for the skin, as before.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_skintex_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

GSA1 = nil
M.load("gsa1/sh_config.lua")
M.load("gsa1/cl_log.lua")
M.load("gsa1/cl_hitch.lua")
M.load("gsa1/cl_module.lua")
M.load("gsa1/cl_textures.lua")
M.load("gsa1/cl_warm_census.lua")
M.load("gsa1/cl_warm.lua")
local ARCHIVES = { [0] = { 28, 29, 96, 138, 56, 73, 1, 1 } }
local G = M.module({ archives = ARCHIVES })
function G.TextureArchives(kind)
    local out = {}
    for i, n in ipairs(ARCHIVES[kind] or {}) do
        out[i] = { name = (n == 96 and "OBJ_REGULAR") or (n == 138 and "EFF_REGULAR") or ("ARCHIVE" .. (i - 1)), count = n }
    end
    return out
end
GSA1.LoadModule()
local T, W = GSA1.Tex, GSA1.Warm
check(T.SkinCheck ~= nil and T.IsSkinArchive ~= nil and T.SkinTitle ~= nil and T.SkinPaintCheck ~= nil,
    "cl_textures.lua has the skins' self-check (T.SkinCheck, T.IsSkinArchive, T.SkinTitle, T.SkinPaintCheck)")

-- the module's skin answers: Metal Sonic in archive 64 (9 textures), Mecha Sonic in 65 (22); a skin texture is 16 x 16, one run per row in a colour of its own
G.SUPER = { CREATE_SKIN = 0x4000, ARCHIVE_SKIN = 61, ARCHIVE_SKIN_FIRST = 64, ARCHIVE_SKIN_LAST = 79, SKINS_MAX = 16 }
local SKIN_N = { [64] = 9, [65] = 22 }
local worn = { [7] = 64, [8] = 65, [9] = 65 }          -- module ids -> their skin's archive
local beta1 = true
local refuse = {}                                        -- ["archive.index"] = true: the fixed module refuses that texture (section 5)
local asked = {}
local plain_texture = G.Texture
local function skin_runs(archive, index)
    local t = {}
    for y = 0, 15 do
        -- (row 15 half see-through: alpha 128 is read back as painted)
        t[#t + 1] = string.char(0, 0, y, 0, 16, 0, archive, (index * 11) % 256, 160 + y * 5, y == 15 and 128 or 255)
    end
    return table.concat(t), 16
end
function G.Texture(kind, index, archive, variant)
    asked[#asked + 1] = archive .. "." .. index
    if archive > 63 then
        -- beta 1's module: arg_int(archive, 0, 63) failed -> push_nil_msg with the usage line (the owner's log, 23:06:17)
        if beta1 then return nil, "Texture(kind, index [, archive [, variant]])" end
        if not SKIN_N[archive] or index >= SKIN_N[archive] then return nil, "not_found: no such texture" end
        if refuse[archive .. "." .. index] then return nil, "decode_failed: a test refusal" end
        local runs, n = skin_runs(archive, index)
        return { w = 16, h = 16, fmt = 0, dfmt = 0, alpha = 1, name = "skin" .. archive .. "_" .. index, runs = runs, nruns = n, canary = false }
    end
    return plain_texture(kind, index, archive)
end
function G.TextureCount(kind, archive)
    if archive > 63 and beta1 then return nil, "TextureCount(kind [, archive])" end
    if SKIN_N[archive] then return SKIN_N[archive] end
    local a = ARCHIVES[kind] and ARCHIVES[kind][archive + 1]
    if a then return a end
    return nil, "not_found: no such archive"
end
function G.SkinArchive(id)
    if worn[id] then return worn[id] end
    return nil, "unsupported", "unsupported"
end

local lines = {}
local real_log = GSA1.Log
GSA1.Log = function(kind, fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    if kind == "texture" and ok and string.find(text, "skin textures:", 1, true) then lines[#lines + 1] = text end
    return real_log(kind, fmt, ...)
end
local function reset()
    T.infos, T.entries, T.skinChecked, T.skinTitles, T.queue, T.later = {}, {}, {}, {}, {}, {}
    T.skinPaint, T.skinPainted, T.skinMats = {}, {}, {}
    lines, asked = {}, {}
    T.ForgetKeys()
end
local function later_of(archive)
    local n = 0
    for _, it in ipairs(T.later) do if it[2] == archive then n = n + 1 end end
    return n
end
local GIVES_ALL = " (painted next, then read back)"

-- 1. beta 1's module: the line says what the owner saw (white)
reset()
local line = T.SkinCheck(0, 64, "Metal Sonic")
check(line == "skin textures: Metal Sonic, archive 64: the module refused the archive (TextureCount(kind [, archive])): its parts draw white" and #lines == 1,
    "beta 1's module: \"%s\" (one line)", tostring(lines[1]))
check(next(T.skinPaint) == nil and #T.later == 0, "nothing to paint, no paint check")
reset()
local tc = G.TextureCount
G.TextureCount = function(kind, archive) if archive > 63 then return SKIN_N[archive] end return tc(kind, archive) end    -- (a count, and every texture refused)
T.SkinCheck(0, 64, "Metal Sonic")
check(lines[1] == "skin textures: Metal Sonic, archive 64: the module gives 0 of 9 (the others draw white)" and #lines == 1 and next(T.skinPaint) == nil,
    "beta 1's textures refused: \"%s\", no paint check", tostring(lines[1]))
G.TextureCount = tc

-- 2. the fixed module: a batch's first use (T.Material -> T.Get -> info_of) runs the check once, with your character's title
beta1 = false
reset()
GSA1.Char = { id = 8, kind = 0, title = "Mecha Sonic", skin = { title = "Mecha Sonic" } }
local mat = T.Material(0, { key = "65.3.22.1.0.3.0", archive = 65, tex = 3, flags = 0x22, src = 1, dst = 0, wrap = 3, pass = 0 })
check(mat ~= nil and not string.find(mat:GetName(), "white", 1, true), "the fixed module: the skin's batch gets its render target's material (%s), not vgui/white", mat and mat:GetName() or "nil")
check(#lines == 1 and lines[1] == "skin textures: Mecha Sonic, archive 65: the module gives 22 of 22" .. GIVES_ALL, "its first use writes \"%s\" (%d line)", tostring(lines[1]), #lines)
local n65 = 0
for _, a in ipairs(asked) do if string.sub(a, 1, 3) == "65." then n65 = n65 + 1 end end
check(n65 == 22 and later_of(65) == 22 and T.skinPaint["0_65"] ~= nil, "every texture of archive 65 asked once (%d asks), listed for painting (%d), its paint check waiting", n65, later_of(65))
T.Get(0, 65, 4, 3, true, "first use")
T.SkinCheck(0, 65)
check(#lines == 1, "never twice for one archive (%d lines)", #lines)
T.Get(0, 1, 2, 3, true, "first use")
check(#lines == 1, "a plain archive (Sonic's 1) has no such line")
GSA1.Char = nil

-- 3. the title from a follower, from Character Select's circle (only when it draws from the archive), and without one
reset()
GSA1.Followers = GSA1.Followers or {}
local fl = GSA1.Followers.list
GSA1.Followers.list = { { id = 9, kind = 0, title = "Mecha Sonic", skin = { title = "Mecha Sonic" } } }
T.Get(0, 65, 0, 3, true, "first use")
check(lines[1] == "skin textures: Mecha Sonic, archive 65: the module gives 22 of 22" .. GIVES_ALL, "a follower's skin: \"%s\"", tostring(lines[1]))
GSA1.Followers.list = fl
reset()
local CS = GSA1.CharSelect
-- (the circle's batch table as feat/cl_charselect.lua paint_3d fills it: gsa1.FrontendBatches, its count)
GSA1.CharSelect = { st = { batches = { count = 2, { archive = 1, tex = 0 }, { archive = 64, tex = 2 } } },
                    SkinEntry = function(st, slot) return slot == 0 and { title = "Metal Sonic" } or nil end }
T.Get(0, 64, 2, 3, true, "first use")
check(lines[1] == "skin textures: Metal Sonic, archive 64: the module gives 9 of 9" .. GIVES_ALL, "Character Select's circle drawing from 64: \"%s\"", tostring(lines[1]))
reset()
T.Get(0, 65, 2, 3, true, "first use")
check(lines[1] == "skin textures: the skin of character 0, archive 65: the module gives 22 of 22" .. GIVES_ALL,
    "another skin (65) first drawn while the circle draws 64 is not named after the circle's: \"%s\"", tostring(lines[1]))
GSA1.CharSelect = CS
reset()
T.Get(0, 64, 2, 3, true, "first use")
check(lines[1] == "skin textures: the skin of character 0, archive 64: the module gives 9 of 9" .. GIVES_ALL, "no title known: \"%s\"", tostring(lines[1]))

-- 4. the pre-warm of a skin (beta 1: none)
reset()
GSA1.cv.prewarm:SetString("1")
local C = { id = 7, kind = 0, title = "Metal Sonic", skin = { title = "Metal Sonic" }, drawPos = Vector(0, 0, 0) }
local plainStates = W.States(0)
local states = W.States(0, 64)
local skin64, body0, census0 = 0, 0, 0
for _, b in ipairs(states) do
    if b.archive == 64 then skin64 = skin64 + 1 end
    if b.archive == 0 then body0 = body0 + 1 end
end
for _, b in ipairs(plainStates) do
    if b.archive == 0 then census0 = census0 + 1 end
end
check(skin64 == 9 and body0 == 0 and census0 > 0, "W.States(0, 64): the 9 textures of the skin's archive in the body's state, none of Sonic's body (archive 0: %d states for plain Sonic)", census0)
check(#states - skin64 == #plainStates - census0, "the rest is Sonic's (his effects, the shader and depth states): %d states", #states - skin64)
local n = W.Start(C)
check(n > 0 and W.total and not W.total.done and #lines == 1 and lines[1] == "skin textures: Metal Sonic, archive 64: the module gives 9 of 9" .. GIVES_ALL,
    "W.Start(Metal Sonic): %d items to warm (beta 1: 0), and the line \"%s\"", n, tostring(lines[1]))
local frames = 0
while W.total and not W.total.done and frames < 5000 do
    frames = frames + 1
    M.frameNo = M.frameNo + 1
    W.Step(C, 0)
    W.Step(C, 1)
end
local rt64 = 0
for key, e in pairs(T.entries) do
    if e and string.sub(key, 1, 5) == "0_64_" then rt64 = rt64 + 1 end
end
check(W.total and W.total.done and W.total.drawn == n and rt64 == 9, "the warm-up drew its %d items in %d frames; the skin's 9 render targets are made (%d)", n, frames, rt64)
reset()
GSA1.cv.prewarm:SetString("0")
check(W.Start(C) == 0 and #lines == 1, "gsa1_prewarm 0: no warm-up, the line all the same (%d)", #lines)
GSA1.cv.prewarm:SetString("1")
local sa = G.SkinArchive
G.SkinArchive = nil
reset()
check(W.Start(C) == 0 and W.total == nil and #lines == 0, "a module without gsa1.SkinArchive: no pre-warm for a skin, as before")
G.SkinArchive = sa
W.total = nil

-- 5. the paint check (T.SkinPaintCheck), painting on the project's render-target pixel model (tests/lua_mock_rt.lua: Source's opaque-black creation clear,
-- colour-only render.Clear, vgui skipping alpha-0 rects, OverrideBlend's separate alpha, CapturePixels / ReadPixel); its alpha probe runs first, as in the game
M.rts, M.nrts = {}, 0
local R = host_load(host_read(tests .. "/lua_mock_rt.lua"), "lua_mock_rt.lua")()(M)
local captures = 0
local read_mode = "ok"         -- "ok" | "swap" (red and blue the other way round) | "none" (render.ReadPixel gives nothing) | "black"
local model_capture, model_read = render.CapturePixels, render.ReadPixel
render.CapturePixels = function()
    if R.cur and string.find(R.cur.name, "_65_", 1, true) then captures = captures + 1 end
    return model_capture()
end
render.ReadPixel = function(x, y)
    local r, g, b, a = model_read(x, y)
    if r == nil or not (R.cur and string.find(R.cur.name, "_65_", 1, true)) then return r, g, b, a end
    if read_mode == "none" then return nil end
    if read_mode == "swap" then return b, g, r, a end
    if read_mode == "black" then return 0, 0, 0, 255 end
    return r, g, b, a
end
T.probe = nil
T.PaintFrame()
check(T.probe and T.probe[T.format.name] and T.probe[T.format.name].ok, "(the model: the addon's alpha probe passes on it: %s)", T.FormatLine())

-- frames until the paint check's line of `key` (at most 400); returns the frames
local function run_until(key)
    for f = 1, 400 do
        M.run_hook("PostRender")
        if T.skinPainted[key] then return f end
    end
    return nil
end
local skincheck = M.hooks.PostRender and M.hooks.PostRender.gsa1_texture_skincheck
local B65 = { key = "65.3.22.1.0.3.0", archive = 65, tex = 3, flags = 0x22, src = 1, dst = 0, wrap = 3, pass = 0 }
local function first_use()
    reset()
    captures = 0
    GSA1.Char = { id = 8, kind = 0, title = "Mecha Sonic", skin = { title = "Mecha Sonic" } }
    T.Material(0, B65)
    GSA1.Char = nil
end

first_use()
local busy = #T.queue > 0 and #T.later == 22
if skincheck then skincheck() end
check(skincheck ~= nil and busy and T.skinPainted["0_65"] == nil and T.skinPaint["0_65"] ~= nil and #lines == 1 and captures == 0,
    "the PostRender hook gsa1_texture_skincheck waits while textures are to paint (%d queued, %d listed): no second line, no read-back", #T.queue, #T.later)
local f = run_until("0_65")
local done = 0
for _, e in pairs(T.entries) do if e and e.archive == 65 and e.done then done = done + 1 end end
check(f ~= nil and #T.queue == 0 and #T.later == 0 and done == 22, "it comes when the painting is idle: %s frames, the 22 render targets painted (%d)", tostring(f), done)
check(#lines == 2 and lines[2] == "skin textures: Mecha Sonic, archive 65: 22 of 22 made (painted; read back 8 of 8 texels as the module gives them; its batches: 1 textured, 0 white)",
    "the second line: \"%s\"", tostring(lines[2]))
check(captures == 1, "ONE render.CapturePixels for it (%d)", captures)
for _ = 1, 20 do M.run_hook("PostRender") end
check(#lines == 2 and captures == 1, "never twice for one archive (%d lines, %d captures)", #lines, captures)
local e3 = T.entries["0_65_3_3"]
local okpx = e3 ~= nil and e3.rt.Get ~= nil
if okpx then
    for y = 0, 15 do
        local r, g, b, a = e3.rt:Get(5, y)
        if not (r == 65 and g == 33 and b == 160 + y * 5 and a == (y == 15 and 128 or 255)) then okpx = false end
    end
end
check(okpx, "(the model: texture 3's render target holds the module's colours, row 15 at alpha 128)")

read_mode = "swap"
first_use()
run_until("0_65")
check(lines[2] ~= nil and string.find(lines[2], "skin textures: Mecha Sonic, archive 65: 22 of 22 painted, but 8 of 8 texels read back wrong (", 1, true) == 1
    and string.find(lines[2], "; red and blue read swapped; its batches: 1 textured, 0 white): please report this line", 1, true) ~= nil,
    "red and blue read the other way round: \"%s\"", tostring(lines[2]))
read_mode = "black"
first_use()
run_until("0_65")
check(lines[2] ~= nil and string.find(lines[2], "22 of 22 painted, but 8 of 8 texels read back wrong (skin65_", 1, true) ~= nil and string.find(lines[2], ": read 0 0 0 255, the module 65 ", 1, true) ~= nil
    and not string.find(lines[2], "swapped", 1, true), "a render target read back black: \"%s\"", tostring(lines[2]))
read_mode = "none"
first_use()
run_until("0_65")
check(lines[2] == "skin textures: Mecha Sonic, archive 65: 22 of 22 made (painted; not read back: render.ReadPixel gives nothing here; its batches: 1 textured, 0 white)",
    "render.ReadPixel giving nothing: \"%s\"", tostring(lines[2]))
read_mode = "ok"
refuse["65.3"] = true
first_use()
run_until("0_65")
check(lines[1] == "skin textures: Mecha Sonic, archive 65: the module gives 21 of 22 (the others draw white)"
    and lines[2] == "skin textures: Mecha Sonic, archive 65: 21 of 22 made (painted, 1 not painted; read back 8 of 8 texels as the module gives them; its batches: 0 textured, 1 white)",
    "a texture the module refuses: \"%s\" / \"%s\"", tostring(lines[1]), tostring(lines[2]))
refuse["65.3"] = nil
-- the pre-warm: the line waits for its end
first_use()
W.total = { done = false }          -- (GSA1.WarmRunning: cl_warm.lua's)
for _ = 1, 50 do M.run_hook("PostRender") end
local waited = #lines == 1 and #T.queue == 0 and #T.later == 0
W.total.done = true
run_until("0_65")
check(waited and #lines == 2, "while a pre-warm runs, the paint check waits, then: \"%s\"", tostring(lines[2]))
W.total = nil

print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
