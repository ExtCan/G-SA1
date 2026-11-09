-- feat_skintex_real.lua: run by feat_skintex_binding_test in Garry's Mod's own LuaJIT with the module's REAL functions (gsa1, opened by gmod13_open through
-- tests/luajit_base.hpp); never by lua_host with tests/lua_mock.lua (whose gsa1.Texture takes any archive: why beta 1's tests never saw the white skins).
-- 1.0.0-beta1a, lane b1a-tex. Globals from the test: SKINTEX = { gdi, bsp, skins (the addon's feat/sh_skins.lua), textures (the addon's cl_textures.lua),
-- model (tests/lua_mock_rt.lua) }, host_write, host_read, host_load, host_sleep, host_flat_floor, Vector, Angle. Returns checks, fails.
-- Section 5 runs the addon's own cl_textures.lua on the module's real answers (its self-check lines, its painter on the project's render-target pixel model).
local checks, fails = 0, 0
local function check(ok, fmt, ...)
    checks = checks + 1
    if not ok then fails = fails + 1 end
    host_write(string.format("  %s  " .. fmt .. "\n", ok and "ok  " or "FAIL", ...))
    return ok
end
local function info(fmt, ...) host_write(string.format("  info  " .. fmt .. "\n", ...)) end

check(type(gsa1) == "table" and type(gsa1.Texture) == "function" and type(gsa1.SkinArchive) == "function",
    "gsa1 in Garry's Mod's LuaJIT %s: the module %s's own functions (gsa1.Texture, gsa1.SkinArchive)", tostring(jit and jit.version), tostring(gsa1 and gsa1.VERSION))
local S = gsa1.SUPER or {}
local FIRST, LAST = S.ARCHIVE_SKIN_FIRST, S.ARCHIVE_SKIN_LAST
check(FIRST == 64 and LAST == 79 and S.SKINS_MAX == 16, "gsa1.SUPER.ARCHIVE_SKIN_FIRST %s .. ARCHIVE_SKIN_LAST %s (libsa1.h's), SKINS_MAX %s", tostring(FIRST), tostring(LAST), tostring(S.SKINS_MAX))
-- the binding's own refusal: its usage line ("Texture(kind, index [, archive [, variant]])", "TextureCount(kind [, archive])", "FrontendTexture(index [, archive])",
-- "FrontendTextureCount([archive])"), never libsa1's text
local function usage(msg)
    return type(msg) == "string" and (string.find(msg, "archive]", 1, true) ~= nil or string.find(msg, "archive [", 1, true) ~= nil)
end
check(usage("Texture(kind, index [, archive [, variant]])") and usage("TextureCount(kind [, archive])") and usage("FrontendTexture(index [, archive])")
    and usage("FrontendTextureCount([archive])") and not usage("not loaded: ") and not usage("not found: "), "the test tells the binding's usage lines from libsa1's answers")

if (SKINTEX.gdi or "") == "" then
    info("no disc (--gdi / SA1_TEST_GDI): the behaviour part is skipped")
    return checks, fails
end

-- the disc
gsa1.Init()
local st, smsg = "loading", ""
for _ = 1, 120000 do
    st, smsg = gsa1.InitPoll()
    if st ~= "loading" then break end
    host_sleep(1)
end
if not check(st == "ready", "the disc through gsa1.Init / InitPoll: %s %s", tostring(st), tostring(smsg)) then return checks, fails end
local map = host_read(SKINTEX.bsp)
if not map then
    info("no gm_construct at %s: the behaviour part is skipped", tostring(SKINTEX.bsp))
    return checks, fails
end
local wok, wmsg = gsa1.WorldLoadData(map, "gm_construct")
map = nil
check(wok == true, "gsa1.WorldLoadData(gm_construct) (Create needs a world): %s", tostring(wmsg))
local fok, fmsg = host_flat_floor()
check(fok, "a flat SOLID floor (%s)", tostring(fmsg))

-- the addon's own skin entries (feat/sh_skins.lua: pure, both realms) and the flat tables the addon hands the module (K.DescOf)
GSA1 = { CHARACTERS = { { kind = 0, name = "sonic", title = "Sonic" } } }
local chunk, lerr = host_load(host_read(SKINTEX.skins) or "", "sh_skins.lua")
if not check(chunk ~= nil, "the addon's feat/sh_skins.lua loads (%s)", tostring(lerr)) then return checks, fails end
chunk()
local K = GSA1.Skins
local METAL, MECHA = K and K.SKINS.metalsonic, K and K.SKINS.mechasonic
if not check(METAL and MECHA, "its registry has Metal Sonic and Mecha Sonic") then return checks, fails end

-- every texture of archive `a` of `kind` through gsa1.Texture (runs), gsa1.TexturePixel at its first run's texel; returns made, asked
local function texture_pass(who, kind, a, want)
    local n, nerr = gsa1.TextureCount(kind, a)
    check(n == want, "%s: gsa1.TextureCount(%d, %d) = %s (%d: its entry's keep list) %s", who, kind, a, tostring(n), want, n and "" or tostring(nerr))
    local made, pixels, bad = 0, 0, {}
    for i = 0, (tonumber(n) or 0) - 1 do
        local t, e = gsa1.Texture(kind, i, a)
        if type(t) == "table" and (t.w or 0) > 0 and (t.h or 0) > 0 and (t.nruns or 0) > 0 and type(t.runs) == "string" and #t.runs == 10 * t.nruns then
            made = made + 1
            local x0, x1, y0, y1, _, _, r, g, b, al = string.byte(t.runs, 1, 10)
            local x, y = x0 + 256 * x1, y0 + 256 * y1
            local pr, pg, pb, pa = gsa1.TexturePixel(kind, a, i, x, y)
            if pr == r and pg == g and pb == b and pa == al then pixels = pixels + 1 else bad[#bad + 1] = i .. " (pixel)" end
        else
            bad[#bad + 1] = i .. ": " .. tostring(e)
        end
    end
    check(n ~= nil and n > 0 and made == n, "%s: gsa1.Texture(%d, i, %d) for every i of 0 .. %d: %d of %s return runs%s", who, kind, a, (tonumber(n) or 0) - 1, made, tostring(n),
        #bad > 0 and (" (not: " .. table.concat(bad, ", ") .. ")") or "")
    check(n ~= nil and pixels == n, "%s: gsa1.TexturePixel(%d, %d, i, x, y) at each texture's first run = the run's colour: %d of %s", who, kind, a, pixels, tostring(n))
    return made, tonumber(n) or 0
end

-- every batch of a batch table: the skin's own (archive 64 .. 79) textured, each (archive, texture) given by gsa1.Texture(kind, ...); returns the skin archive seen
local function batch_pass(who, kind, B)
    local seen, tris, skinb, untex, bad, asked = nil, 0, 0, 0, {}, {}
    local other = 0
    for i = 1, tonumber(B.count) or 0 do
        local b = B[i]
        if type(b) == "table" then
            if b.archive >= FIRST and b.archive <= LAST then
                skinb = skinb + 1
                tris = tris + (b.tris or 0)
                if seen and seen ~= b.archive then bad[#bad + 1] = "two skin archives " .. seen .. ", " .. b.archive end
                seen = seen or b.archive
                if b.tex < 0 then
                    bad[#bad + 1] = "batch " .. i .. " untextured"
                elseif not asked[b.archive .. "_" .. b.tex] then
                    asked[b.archive .. "_" .. b.tex] = true
                    local t, e = gsa1.Texture(kind, b.tex, b.archive)
                    if not (type(t) == "table" and (t.nruns or 0) > 0) then bad[#bad + 1] = b.archive .. "." .. b.tex .. ": " .. tostring(e) end
                end
            elseif b.archive < 0 then
                untex = untex + 1
            else
                other = other + 1
            end
        end
    end
    local na = 0
    for _ in pairs(asked) do na = na + 1 end
    check(seen ~= nil and tris > 0 and #bad == 0, "%s: %d batches, %d triangles on its skin archive %s, every one textured, its %d textures given by gsa1.Texture(%d, tex, archive)%s; "
        .. "%d batches of other archives, %d untextured", who, skinb, tris, tostring(seen), na, kind, #bad > 0 and (" (not: " .. table.concat(bad, "; ") .. ")") or "", other, untex)
    return seen
end

local function tick(id, n)
    for _ = 1, n do gsa1.Tick(id, 0, 0, 0, 0, 1 / 30) end
end

local made_all, asked_all = 0, 0
local archives = {}
local ids = {}                  -- [title] = the character wearing it (section 5)
-- 1. your character wearing each skin
for _, e in ipairs({ { "Metal Sonic", METAL, Vector(0, 0, 8) }, { "Mecha Sonic", MECHA, Vector(300, 0, 8) } }) do
    local title, skin, pos = e[1], e[2], e[3]
    local ex = K.ExtrasFor(skin, gsa1.SUPER)
    local id, cerr = gsa1.Create(0, pos, 0, nil, nil, ex)
    if check(type(id) == "number" and id > 0, "%s: gsa1.Create(0, ..., {create_flags = CREATE_SKIN, skin = K.DescOf(entry)}) = %s %s", title, tostring(id), cerr and tostring(cerr) or "") then
        tick(id, 40)
        gsa1.Render(id, -1)
        local B = {}
        gsa1.Batches(id, B)
        local a, aerr = gsa1.SkinArchive(id)
        check(type(a) == "number" and a >= FIRST and a <= LAST, "%s: gsa1.SkinArchive(id) = %s (64 + its slot) %s", title, tostring(a), aerr and tostring(aerr) or "")
        if type(a) == "number" then
            archives[title] = a
            local m, n = texture_pass(title, 0, a, #skin.textures.keep)
            made_all, asked_all = made_all + m, asked_all + n
            local seen = batch_pass(title .. " in play", 0, B)
            check(seen == a, "%s: its batches draw from the archive gsa1.SkinArchive names (%s, %s)", title, tostring(seen), tostring(a))
        end
        -- (kept until the end: a second create of the same skin wears the loaded one)
        ids[title] = id
    end
end
check(archives["Metal Sonic"] and archives["Mecha Sonic"] and archives["Metal Sonic"] ~= archives["Mecha Sonic"],
    "two skins, two archives: Metal Sonic %s, Mecha Sonic %s (the owner's log: 64 and 65)", tostring(archives["Metal Sonic"]), tostring(archives["Mecha Sonic"]))
info("the self-check lines the addon writes for each (cl_textures.lua T.SkinCheck, T.SkinPaintCheck: section 5): \"skin textures: Metal Sonic, archive %s: the module gives ... of ...\", then \"... of ... made (...)\"",
    tostring(archives["Metal Sonic"]))

-- 2. the range is libsa1's, not the binding's
local t80, e80 = gsa1.Texture(0, 0, LAST + 1)
check(t80 == nil and usage(e80), "gsa1.Texture(0, 0, %d), past libsa1's range: refused by the binding (%s)", LAST + 1, tostring(e80))
local free = nil
for x = FIRST, LAST do
    if x ~= archives["Metal Sonic"] and x ~= archives["Mecha Sonic"] then free = x break end
end
local tf, ef = gsa1.Texture(0, 0, free)
local cf, ecf = gsa1.TextureCount(0, free)
check(tf == nil and not usage(ef) and cf == nil and not usage(ecf), "gsa1.Texture / TextureCount(0, .., %d), a skin archive no skin uses yet: libsa1's answer, not the binding's refusal (%s; %s)", free, tostring(ef), tostring(ecf))
local tq, eq = gsa1.Texture(0, 0, 63)
check(tq == nil and not usage(eq), "gsa1.Texture(0, 0, 63): libsa1's answer as before (%s)", tostring(eq))

-- 3. a follower wearing each (beside a plain Sonic to follow)
local lead = gsa1.Create(0, Vector(0, 300, 8), 0)
if check(type(lead) == "number" and lead > 0, "a plain Sonic to follow (%s)", tostring(lead)) then
    local fids = {}
    for _, e in ipairs({ { "Metal Sonic", METAL, Vector(0, 260, 8) }, { "Mecha Sonic", MECHA, Vector(0, 340, 8) } }) do
        local fid, ferr = gsa1.FollowerCreate(0, e[3], 0, lead, { skin = K.DescOf(e[2]), voiceless = true })
        check(type(fid) == "number" and fid > 0, "a %s follower: gsa1.FollowerCreate(0, ..., {skin = K.DescOf(entry)}) = %s %s", e[1], tostring(fid), ferr and tostring(ferr) or "")
        fids[#fids + 1] = { e[1], fid }
    end
    local out = {}
    for _ = 1, 60 do
        gsa1.Tick(lead, 0, 0, 0, 0, 1 / 30)
        gsa1.FollowersTick(1 / 30, 0, nil, nil, out)
    end
    for _, f in ipairs(fids) do
        local title, fid = f[1], f[2]
        if type(fid) == "number" and fid > 0 then
            local B = {}
            gsa1.Batches(fid, B)
            local a = gsa1.SkinArchive(fid)
            check(a == archives[title], "the %s follower: gsa1.SkinArchive = %s, its skin's archive (%s): the loaded skin is worn again", title, tostring(a), tostring(archives[title]))
            local seen = batch_pass("the " .. title .. " follower", 0, B)
            check(seen == a, "the %s follower's batches draw from it (%s)", title, tostring(seen))
            gsa1.Destroy(fid)
        end
    end
    gsa1.Destroy(lead)
end

-- 4. Character Select: the circle's Sonic wearing each skin (gsa1.FrontendSkin), its batches' textures through gsa1.Texture with the holder's kind (cl_charselect.lua's
-- paint_3d: T.Material(kind, b)); the menu's own archives through the Frontend* texture calls
local ook, oerr = gsa1.FrontendOpen()
if check(ook == true, "gsa1.FrontendOpen (%s)", tostring(oerr)) then
    local function fe_tick(n)
        for _ = 1, n do gsa1.FrontendTick(1 / 60, 0, 0, 0) end
    end
    fe_tick(30)
    for _, e in ipairs({ { "Metal Sonic", METAL }, { "Mecha Sonic", MECHA } }) do
        local title, skin = e[1], e[2]
        local sok, serr = gsa1.FrontendSkin(K.DescOf(skin), true)
        check(sok == true, "Character Select: gsa1.FrontendSkin(K.DescOf(%s), true) (%s)", title, tostring(serr))
        fe_tick(2)
        local n, _, kind = gsa1.FrontendRender()
        local B = {}
        gsa1.FrontendBatches(B)
        check(type(n) == "number" and n > 0 and kind == 0, "Character Select with %s: gsa1.FrontendRender = %s draws, the holder's kind %s", title, tostring(n), tostring(kind))
        local seen = batch_pass("Character Select's circle with " .. title, kind or 0, B)
        check(seen == archives[title], "Character Select's circle draws %s from its archive %s (%s)", title, tostring(archives[title]), tostring(seen))
    end
    gsa1.FrontendSkin()
    -- the menu's own archives (kind gsa1.FRONTEND.KIND: gsa1.FrontendTexture*)
    local FA = gsa1.FrontendTextureArchives()
    local na, nt, nmade, npix, fbad = 0, 0, 0, 0, {}
    for ai, ent in ipairs(type(FA) == "table" and FA or {}) do
        local a = ai - 1
        na = na + 1
        local c = gsa1.FrontendTextureCount(a)
        if c ~= ent.count then fbad[#fbad + 1] = "count of " .. a end
        for i = 0, (tonumber(c) or 0) - 1 do
            nt = nt + 1
            local t, e = gsa1.FrontendTexture(i, a)
            if type(t) == "table" and (t.nruns or 0) > 0 and #t.runs == 10 * t.nruns then
                nmade = nmade + 1
                local x0, x1, y0, y1, _, _, r, g, b, al = string.byte(t.runs, 1, 10)
                local pr, pg, pb, pa = gsa1.FrontendTexturePixel(a, i, x0 + 256 * x1, y0 + 256 * y1)
                if pr == r and pg == g and pb == b and pa == al then npix = npix + 1 end
            elseif type(t) == "table" and (t.nruns or 0) == 0 then
                nmade, npix = nmade + 1, npix + 1       -- (a texture with no visible texel: nothing to paint)
            else
                fbad[#fbad + 1] = a .. "." .. i .. ": " .. tostring(e)
            end
        end
    end
    check(na > 0 and nt > 0 and nmade == nt and npix == nt and #fbad == 0, "Character Select's menu: %d archives, %d textures, %d through gsa1.FrontendTexture, %d texels through gsa1.FrontendTexturePixel%s",
        na, nt, nmade, npix, #fbad > 0 and (" (not: " .. table.concat(fbad, "; ") .. ")") or "")
    local tm, em = gsa1.FrontendTexture(0, FIRST)
    local cm, ecm = gsa1.FrontendTextureCount(FIRST)
    check(tm == nil and not usage(em) and cm == nil and not usage(ecm), "gsa1.FrontendTexture / FrontendTextureCount(.., %d): libsa1's answer for the menu, not the binding's refusal (%s; %s)", FIRST, tostring(em), tostring(ecm))
    gsa1.FrontendClose()
end

check(asked_all > 0 and made_all == asked_all, "THE SELF-CHECK OF THIS ROUND: the skins' textures, %d of %d made through the module's real gsa1.Texture (beta 1: 0 of %d)", made_all, asked_all, asked_all)

-- 5. the ADDON'S OWN cl_textures.lua (SKINTEX.textures) on these real answers: Character Select's circle wearing Metal Sonic (T.Material(holder kind, b), as
-- feat/cl_charselect.lua paint_3d), Mecha Sonic in play (T.Material(0, b), as cl_render.lua), painted by the addon's painter on the project's render-target pixel
-- model (SKINTEX.model, tests/lua_mock_rt.lua: Source's opaque-black creation clear, colour-only render.Clear, vgui skipping alpha-0 rects, OverrideBlend's separate
-- alpha, CapturePixels / ReadPixel). Its two self-check lines per skin, and every texel of the skins' render targets against gsa1.TexturePixel. The alpha probe is
-- not run here (the game's own; tests/feat_skintex_test.lua runs it on the model). What only the game shows: Garry's Mod's own render targets, on screen.
-- (a test built before these fields: the paths next to the addon's feat/sh_skins.lua, <g-sa1>/addon/lua/gsa1/feat/sh_skins.lua)
local base_dir = string.match(SKINTEX.skins or "", "^(.*)[\\/]addon[\\/]lua[\\/]gsa1[\\/]feat[\\/]sh_skins%.lua$")
SKINTEX.textures = SKINTEX.textures or (base_dir and (base_dir .. "\\addon\\lua\\gsa1\\cl_textures.lua"))
SKINTEX.model = SKINTEX.model or (base_dir and (base_dir .. "\\tests\\lua_mock_rt.lua"))
if not (SKINTEX.textures and SKINTEX.model and host_read(SKINTEX.textures) and host_read(SKINTEX.model)) then
    info("no cl_textures.lua / lua_mock_rt.lua path: section 5 is skipped")
    return checks, fails
end
local noop = function() end
render = setmetatable({ SetMaterial = noop }, { __index = function() return noop end })
surface = { DrawRect = noop }
mesh = { Begin = noop, End = noop, Position = noop, TexCoord = noop, Color = noop, AdvanceVertex = noop, Normal = noop }
cam = setmetatable({}, { __index = function() return noop end })
draw = setmetatable({}, { __index = function() return noop end })
local hooks = {}
hook = { Add = function(ev, name, fn) hooks[ev] = hooks[ev] or {} hooks[ev][name] = fn end, Remove = noop, Run = noop }
concommand = { Add = noop }
system = { HasFocus = function() return true end }
SysTime, RealTime, CurTime = os.clock, os.clock, os.clock
local MATMT = { __index = { GetName = function(self) return self.name end } }
function CreateMaterial(name, shader, params) return setmetatable({ name = name, shader = shader, params = params }, MATMT) end
local MR = { calls = {}, rts = {}, nrts = 0 }
local mchunk = host_load(host_read(SKINTEX.model), "lua_mock_rt.lua")
mchunk()(MR)
local function cvar(v) return { GetInt = function() return v end, GetBool = function() return v ~= 0 end, GetFloat = function() return v end } end
local LOG = {}
GSA1.cv = { paint_budget = cvar(6000), nocull = cvar(0), lighting = cvar(1) }
GSA1.Msg = function(fmt, ...) LOG[#LOG + 1] = "msg      " .. string.format(fmt, ...) end
GSA1.Log = function(cat, fmt, ...) LOG[#LOG + 1] = string.format("%-8s ", cat) .. string.format(fmt, ...) end
GSA1.mod = true
local tchunk, terr = host_load(host_read(SKINTEX.textures), "cl_textures.lua")
if not check(tchunk ~= nil, "the addon's cl_textures.lua loads (%s)", tostring(terr)) then return checks, fails end
tchunk()
local T = GSA1.Tex
T.probe = { [T.format.name] = { readable = true, ok = true, clearMode = "clear", a0mode = "exact" } }
check(T.SkinCheck and T.SkinPaintCheck and hooks.PostRender and hooks.PostRender.gsa1_texture_skincheck, "cl_textures.lua: T.SkinCheck, T.SkinPaintCheck and its PostRender hook")

-- every batch of B through the addon's T.Material(kind, b): the skin's batches, and of them white
local function draw_batches(kind, B)
    local skinb, white = 0, 0
    for i = 1, tonumber(B.count) or 0 do
        local b = B[i]
        if type(b) == "table" and (b.tris or 0) > 0 then
            local m = T.Material(kind, b)
            if b.archive >= FIRST and b.archive <= LAST then
                skinb = skinb + 1
                if not m or m.params["$basetexture"] == "vgui/white" then white = white + 1 end
            end
        end
    end
    return skinb, white
end
-- PostRender frames until the paint check of `key` wrote its line (at most 20000)
local function paint_until(key)
    for f = 1, 20000 do
        for _, fn in pairs(hooks.PostRender) do fn() end
        if T.skinPainted[key] then return f end
    end
    return nil
end
-- the render targets of (kind, archive) against libsa1's decoded texels (gsa1.TexturePixel), every texel
local function verify_rts(kind, a)
    local ents, texels, bad, first = 0, 0, 0, nil
    for _, e in pairs(T.entries) do
        if e and e.kind == kind and e.archive == a and not e.mask and not e.gold then
            ents = ents + 1
            for y = 0, e.rt.h - 1 do
                for x = 0, e.rt.w - 1 do
                    texels = texels + 1
                    local pr, pg, pb, pa = e.rt:Get(x, y)
                    local er, eg, eb, ea = gsa1.TexturePixel(kind, a, e.index, x, y)
                    if not (er ~= nil and pa == ea and (ea == 0 or (pr == er and pg == eg and pb == eb))) then
                        bad = bad + 1
                        first = first or string.format("%s (%d,%d): painted %d %d %d %d, libsa1 %s %s %s %s", e.rt.name, x, y, pr, pg, pb, pa, tostring(er), tostring(eg), tostring(eb), tostring(ea))
                    end
                end
            end
        end
    end
    return ents, texels, bad, first
end
local function lines_of(a)
    local out = {}
    for _, l in ipairs(LOG) do
        if string.find(l, "skin textures: ", 1, true) and string.find(l, ", archive " .. a .. ": ", 1, true) then out[#out + 1] = string.sub(l, 10) end
    end
    return out
end
local function made_line(l, title, a, n)
    local head = string.format("skin textures: %s, archive %d: %d of %d made (painted; read back ", title, a, n, n)
    return type(l) == "string" and string.sub(l, 1, #head) == head and string.find(l, " as the module gives them; its batches: ", 1, true) ~= nil
        and string.sub(l, -10) == ", 0 white)"
end

local a64, a65 = archives["Metal Sonic"], archives["Mecha Sonic"]
local n64, n65 = #METAL.textures.keep, #MECHA.textures.keep
local ook2 = gsa1.FrontendOpen()
if check(ook2 == true and a64 and a65 and ids["Mecha Sonic"], "Character Select open again, Metal Sonic on archive %s, Mecha Sonic on %s", tostring(a64), tostring(a65)) then
    for _ = 1, 30 do gsa1.FrontendTick(1 / 60, 0, 0, 0) end
    gsa1.FrontendSkin(K.DescOf(METAL), true)
    for _ = 1, 2 do gsa1.FrontendTick(1 / 60, 0, 0, 0) end
    local _, _, kind = gsa1.FrontendRender()
    local CB = {}
    gsa1.FrontendBatches(CB)
    GSA1.CharSelect = { st = { batches = CB }, SkinEntry = function(st, slot) return slot == 0 and METAL or nil end }
    local skinb, white = draw_batches(kind or 0, CB)
    local L = lines_of(a64)
    check(skinb > 0 and white == 0 and L[1] == string.format("skin textures: %s, archive %d: the module gives %d of %d (painted next, then read back)", METAL.title, a64, n64, n64) and #L == 1,
        "Character Select's circle with Metal Sonic: %d skin batches, %d white; the first line \"%s\"", skinb, white, tostring(L[1]))
    -- the verifier's LOW: another skin first drawn while the circle draws Metal Sonic is not named after the circle's skin
    local MB = {}
    gsa1.Render(ids["Mecha Sonic"], -1)
    gsa1.Batches(ids["Mecha Sonic"], MB)
    local mskin, mwhite = draw_batches(0, MB)
    local L65 = lines_of(a65)
    check(mskin > 0 and mwhite == 0 and L65[1] == string.format("skin textures: the skin of character 0, archive %d: the module gives %d of %d (painted next, then read back)", a65, n65, n65),
        "Mecha Sonic (%d skin batches, %d white) first drawn while the circle shows Metal Sonic: \"%s\"", mskin, mwhite, tostring(L65[1]))
    GSA1.CharSelect = nil
    local f64 = paint_until("0_" .. a64)
    local f65 = paint_until("0_" .. a65)
    L, L65 = lines_of(a64), lines_of(a65)
    check(f64 and #L == 2 and made_line(L[2], METAL.title, a64, n64), "painted (%s frames): \"%s\"", tostring(f64), tostring(L[2]))
    check(f65 and #L65 == 2 and made_line(L65[2], "the skin of character 0", a65, n65), "painted (%s frames): \"%s\"", tostring(f65), tostring(L65[2]))
    for _, s in ipairs({ { METAL.title, a64, n64 }, { MECHA.title, a65, n65 } }) do
        local ents, texels, bad, first = verify_rts(0, s[2])
        check(ents >= s[3] and texels > 0 and bad == 0, "%s, archive %d: %d render targets painted by the addon's painter from the module's runs, %d texels, %d differ from gsa1.TexturePixel%s",
            s[1], s[2], ents, texels, bad, first and (" (first: " .. first .. ")") or "")
    end
    local nref, nwhite = 0, 0
    for _, l in ipairs(LOG) do
        if string.find(l, "Texture(kind", 1, true) then nref = nref + 1 end
    end
    for key, c in pairs(T.skinMats) do nwhite = nwhite + c.white end
    check(nref == 0 and nwhite == 0, "no refusal in the addon's log (%d) and no skin batch material on vgui/white (%d)", nref, nwhite)
    gsa1.FrontendSkin()
    gsa1.FrontendClose()
end
return checks, fails
