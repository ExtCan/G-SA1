-- texture_alpha_test.lua - the textures' alpha (cl_textures.lua) against a render-target pixel model of Garry's Mod
-- (tests/lua_mock_rt.lua: Source's opaque-black creation clear, Direct3D 9 dropping a clear that asks for depth on a
-- target without a depth buffer, vgui skipping alpha-0 rectangles, the surface alpha multiplier), in Garry's Mod's own
-- LuaJIT. sadc docs/research/gsa1_060_alpha.md section 8 item 2 with its review: the owner's 0.6.0 report "Knuckles'
-- particles have inverted alphas" and the log line "BGRA8888 read back 96 where 96 was painted, 255 where 0".
--   lua_host tests/texture_alpha_test.lua <tests dir> <addon/lua dir>
-- On 0.6.0 / 0.7.0's addon the probe reports exactly the owner's line and the painting, multiplier, mask and T.Prepare
-- checks fail; on 0.8 every check passes. The textures are generated patterns (no game data).
-- 0.9.1 (sadc docs/research/gsa1_070_translucency.md T1 / T2.3 / T3 with its review): the model knows Source's shader
-- rule (VertexLitGeneric ignores $vertexalpha and $vertexcolor, multiplies $alpha); lit see-through batches (the
-- module's key ".a<alpha>") cover alpha / 255 with the lighting on and off - 0.9.0's materials covered 1.0 lit - and the
-- startup check of $alpha on lit materials (T3) reads ok / lost.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local R = host_load(host_read(tests .. "/lua_mock_rt.lua"), "lua_mock_rt.lua")()(M)
local check, info = M.check, M.info
print("G-SA1 texture_alpha_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

GSA1 = nil
M.load("gsa1/sh_config.lua")
M.load("gsa1/cl_log.lua")
M.load("gsa1/cl_hitch.lua")
M.load("gsa1/cl_module.lua")
M.load("gsa1/cl_textures.lua")
local G = M.module({})
local T = GSA1.Tex

-- synthetic textures, run-length encoded like the module (Session::texture_runs: u16 x, y, length, u8 r, g, b, a per run
-- of equal texels, (0, 0, 0, 0) runs left out)
local function make(name, w, h, px)
    local img, runs, n = {}, {}, 0
    for y = 0, h - 1 do
        local x = 0
        while x < w do
            local r, g, b, a = px(x, y)
            local len = 1
            while x + len < w do
                local r2, g2, b2, a2 = px(x + len, y)
                if r2 ~= r or g2 ~= g or b2 ~= b or a2 ~= a then break end
                len = len + 1
            end
            if r + g + b + a > 0 then
                runs[#runs + 1] = string.char(x % 256, math.floor(x / 256), y % 256, math.floor(y / 256), len % 256,
                    math.floor(len / 256), r, g, b, a)
                n = n + 1
            end
            for k = 0, len - 1 do img[y * w + x + k + 1] = { r, g, b, a } end
            x = x + len
        end
    end
    return { w = w, h = h, fmt = 0, dfmt = 0, alpha = 0, name = name, runs = table.concat(runs), nruns = n,
             canary = false, img = img }
end
-- a dirt clod (Knuckles' tsuchi_yama kind: opaque centre, a soft ring, a border of alpha-0 texels that carry RGB, clear
-- corners)
local CLOD = make("clod", 32, 32, function(x, y)
    local d = math.sqrt((x - 15.5) ^ 2 + (y - 15.5) ^ 2)
    if d < 8 then return 120, 80, 40, 255 end
    if d < 12 then return 130, 90, 50, math.floor(238 - (d - 8) / 4 * 221) end
    if d < 15 then return 160, 96, 48, 0 end
    return 0, 0, 0, 0
end)
local FLAT96 = make("flat96", 4, 4, function() return 200, 100, 50, 96 end)
-- the blob shadow's kind of texture: black in every texel, the shape in the alpha (255 core, 221, 17, 0 outside)
local SHADOWTEX = make("shadowlike", 16, 16, function(x, y)
    local d = math.sqrt((x - 7.5) ^ 2 + (y - 7.5) ^ 2)
    if d < 5 then return 0, 0, 0, 255 elseif d < 6 then return 0, 0, 0, 221 elseif d < 7 then return 0, 0, 0, 17 end
    return 0, 0, 0, 0
end)
local TEX = { ["1_0"] = CLOD, ["0_0"] = FLAT96, ["2_58"] = SHADOWTEX }
function G.Texture(kind, index, archive)
    local t = TEX[archive .. "_" .. index]
    if not t then return nil, "no such texture" end
    return t
end
function G.TextureArchives(kind)
    return { { name = "SONIC", count = 2 }, { name = "SON_EFF", count = 1 }, { name = "OBJ_REGULAR", count = 96 },
             { name = "EFF_REGULAR", count = 3 } }
end
GSA1.LoadModule()

local function paint_all()
    for _ = 1, 400 do
        if #T.queue == 0 then break end
        T.PaintFrame()
    end
end

-- compares render target rt with texture tex: returns wrong texels, the first wrong one, and the alpha-0-with-RGB
-- texels' worst alpha
local function compare(rt, tex, a0tol)
    local wrong, first, a0worst = 0, nil, 0
    for y = 0, tex.h - 1 do
        for x = 0, tex.w - 1 do
            local want = tex.img[y * tex.w + x + 1]
            local r, g, b, a = rt:Get(x, y)
            local ok
            if want[4] == 0 and want[1] + want[2] + want[3] > 0 then
                ok = r == want[1] and g == want[2] and b == want[3] and a <= a0tol
                a0worst = math.max(a0worst, a)
            else
                ok = r == want[1] and g == want[2] and b == want[3] and a == want[4]
            end
            if not ok then
                wrong = wrong + 1
                first = first or string.format("(%d, %d): %d %d %d %d, want %d %d %d %d", x, y, r, g, b, a, want[1],
                    want[2], want[3], want[4])
            end
        end
    end
    return wrong, first, a0worst
end

-- 1. the probe (the first PostRender), on the painter's own path
T.probe = nil
M.run_hook("PostRender")
local line = T.FormatLine and T.FormatLine() or "?"
local p = T.probe and T.probe[T.format.name] or {}
if string.find(line, "probe 96 -> 96, 0 -> 255", 1, true) then
    info("the model gives the owner's 0.6.0 log line: %s", line)
end
local s = p.sample or {}
check(string.find(line, "alpha kept", 1, true) ~= nil and p.painted == 96 and p.a0 == 0 and p.clear == 0 and
    s.ar and math.abs(s.ar - 234) <= 4 and math.abs(s.ag - 197) <= 4 and math.abs(s.ab - 178) <= 4 and s.b >= 251 and
    s.c >= 251 and R.dropped == 0,
    "probe: %s (clears dropped by Direct3D 9: %d)", line, R.dropped)

-- 2. painting: every texel of a clod as decoded (alpha-0 texels with their RGB and alpha 0)
local e = T.Get(0, 1, 0, 3, true)
paint_all()
local wrong, first, a0w = compare(e.rt, CLOD, 0)
check(e.done and wrong == 0, "paint: the clod's %d texels exactly as decoded (%d wrong%s; alpha-0 texels with RGB: alpha "
    .. "at most %d) [0.6.0: every alpha-0 texel opaque black]", 32 * 32, wrong, first and (", e.g. " .. first) or "", a0w)

-- 3. the surface alpha multiplier another addon left at 0.5
surface.SetAlphaMultiplier(0.5)
local e96 = T.Get(0, 0, 0, 3, true)
paint_all()
local r96, g96, b96, a96 = e96.rt:Get(1, 1)
check(a96 == 96 and r96 == 200 and R.mult == 0.5, "multiplier 0.5 left set: a texel of alpha 96 painted as %d %d %d %d, "
    .. "the multiplier put back (%.2f) [0.6.0: alpha 48]", r96, g96, b96, a96, R.mult)
surface.SetAlphaMultiplier(1)

-- 4. a device reset (the targets come back opaque black): repainted right
e.rt:Fill(0, 0, 0, 255)
T.RepaintAll("test")
paint_all()
wrong, first = compare(e.rt, CLOD, 0)
check(wrong == 0, "repaint after a device reset: %d wrong texels%s", wrong, first and (", e.g. " .. first) or "")

-- 5. a host that ignores the separate alpha blend: the probe switches to alpha 1 for alpha-0 texels
R.separate_alpha = false
T.probe = nil
M.run_hook("PostRender")
local line2 = T.FormatLine()
local e2 = T.Get(0, 1, 0, 0, true)
paint_all()
local wrong2, first2, a0w2 = compare(e2.rt, CLOD, 1)
check(T.a0mode == "alpha1" and string.find(line2, "alpha kept", 1, true) ~= nil and e2.done and wrong2 == 0 and a0w2 == 1,
    "no separate alpha blend: %s; the clod's alpha-0 texels painted with alpha %d, %d wrong%s", line2, a0w2, wrong2,
    first2 and (", e.g. " .. first2) or "")
R.separate_alpha = true

-- 6. a host where even a colour-only clear fails: the textures are cleared by drawing
R.colour_clear_works = false
T.probe = nil
M.run_hook("PostRender")
local line3 = T.FormatLine()
local e3 = T.Get(0, 1, 0, 1, true)
paint_all()
local wrong3, first3 = compare(e3.rt, CLOD, 0)
check(T.clearMode == "draw" and string.find(line3, "alpha kept", 1, true) ~= nil and e3.done and wrong3 == 0,
    "no colour clear: %s; the clod %d wrong%s", line3, wrong3, first3 and (", e.g. " .. first3) or "")
R.colour_clear_works = true
T.probe = nil
M.run_hook("PostRender")

-- 7. the blob shadow's mask: a WRAP_MASK render target holds RGB = the texel's alpha
local em = T.Get(0, 2, 58, 3 + 8, true)
paint_all()
local mwrong, mfirst = 0, nil
for y = 0, 15 do
    for x = 0, 15 do
        local want = SHADOWTEX.img[y * 16 + x + 1][4]
        local r, g, b
        if em then r, g, b = em.rt:Get(x, y) end
        if not (r == want and g == want and b == want) then
            mwrong = mwrong + 1
            mfirst = mfirst or string.format("(%d, %d): %s %s %s, want %d", x, y, tostring(r), tostring(g), tostring(b), want)
        end
    end
end
check(em and em.done and em.mask and mwrong == 0, "the shadow's mask render target: RGB = the texel's alpha in all 256 "
    .. "texels (%d wrong%s)", mwrong, mfirst and (", e.g. " .. mfirst) or "")

-- 8. its material and blend: unlit, translucent, no fog, ZERO / ONE_MINUS_SRC_COLOR, and the result is the game's
local sb = { key = "2.58.841.4.5.11.1", archive = 2, tex = 58, flags = 0x841, src = 4, dst = 5, wrap = 11, pass = 1 }
local m = T.Material(0, sb)
-- (the plain path's batch as the module keys it since 0.9.1: lit, blended, not the mask - its vertex alpha 204 is the
-- material's $alpha)
local plain = { key = "2.58.841.4.5.3.1.a204", archive = 2, tex = 58, flags = 0x841, src = 4, dst = 5, wrap = 3, pass = 1 }
local bs, bd, ps, pd
if T.BlendOf then
    bs, bd = T.BlendOf(sb)
    ps, pd = T.BlendOf(plain)
end
local mp = m and m.params or {}
-- draw the mask over mid grey the way cl_render.lua does, and the plain texture SA / ISA with vertex alpha 204: the same
local function over_grey(mat, s, d, vr, va)
    local tgt = GetRenderTargetEx("test_grey_" .. tostring(s), 16, 16, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, 12)
    tgt:Fill(128, 128, 128, 255)
    render.PushRenderTarget(tgt)
    cam.Start2D()
    render.SetMaterial(mat)
    render.OverrideBlend(true, s, d, BLENDFUNC_ADD)
    mesh.Begin(MATERIAL_QUADS, 1)
    local cs = { { 0, 0, 0, 0 }, { 16, 0, 1, 0 }, { 16, 16, 1, 1 }, { 0, 16, 0, 1 } }
    for _, c in ipairs(cs) do
        mesh.Position(Vector(c[1], c[2], 0))
        mesh.TexCoord(0, c[3], c[4])
        mesh.Color(vr, vr, vr, va)
        mesh.AdvanceVertex()
    end
    mesh.End()
    render.OverrideBlend(false)
    cam.End2D()
    render.PopRenderTarget()
    return tgt
end
local maxd = -1
if m and bs then
    local pm = T.Material(0, plain)
    paint_all()
    local g1 = over_grey(m, bs, bd, 204, 255)
    local g2 = over_grey(pm, ps, pd, 178, 204)
    maxd = 0
    for y = 0, 15 do
        for x = 0, 15 do
            local a = g1:Get(x, y)
            local b = g2:Get(x, y)
            maxd = math.max(maxd, math.abs(a - b))
        end
    end
end
check(m and m.shader == "UnlitGeneric" and mp["$translucent"] == 1 and mp["$nofog"] == 1 and mp["$vertexcolor"] == 1 and
    mp["$vertexalpha"] == nil and em and mp["$basetexture"] == em.rt:GetName() and bs == 0 and bd == 10 and ps == 4 and
    pd == 5 and maxd >= 0 and maxd <= 1,
    "the shadow's mask material %s (%s): blend %s/%s (the plain one %s/%s); over grey it darkens like the game's SA/ISA "
    .. "blend of the black texture with alpha 204 (largest difference %d)", m and m:GetName() or "-",
    m and m.shader or "-", tostring(bs), tostring(bd), tostring(ps), tostring(pd), maxd)

-- 9. T.Prepare lists no OBJ_REGULAR texture (96 render targets per character kind otherwise; review R.3.2)
T.later = {}
T.Prepare(0)
local listed, obj = #T.later, 0
for _, it in ipairs(T.later) do if it[2] == 2 then obj = obj + 1 end end
check(listed == 6 and obj == 0, "T.Prepare: %d textures listed for painting, %d of OBJ_REGULAR (archive 2)", listed, obj)
T.later = {}

-- 10. 0.9.1, T3: the startup check of lit see-through materials - "ok" where VertexLitGeneric honours $alpha (the
-- model's default), "lost" where it does not; then lit see-through batches get unlit materials (see-through, fullbright)
-- until the check reads ok again
local copy = { key = "0.0.21.4.5.3.1.a170", archive = 0, tex = 0, flags = 0x21, src = 4, dst = 5, wrap = 3, pass = 1 }
T.probe = nil
M.run_hook("PostRender")
local l1, lit1 = T.FormatLine(), T.lit or {}
check(T.litAlpha == "ok" and lit1.control == 255 and lit1.test and math.abs(lit1.test - 128) <= 1 and
    string.find(l1, "lit see-through materials: ok", 1, true) ~= nil, "T3, $alpha honoured: %s", l1)
R.vlg_alpha = false
T.probe = nil
M.run_hook("PostRender")
local l2, lit2 = T.FormatLine(), T.lit or {}
local mlost = T.Material(0, copy)
local plost = mlost and mlost.params or {}
check(T.litAlpha == "lost" and lit2.test == 255 and mlost and mlost.shader == "UnlitGeneric" and plost["$vertexalpha"] == 1
    and plost["$alpha"] == nil and string.find(l2, "IGNORED", 1, true) ~= nil,
    "T3, $alpha ignored: %s; a lit see-through batch then gets %s (%s)", l2, mlost and mlost:GetName() or "-",
    mlost and mlost.shader or "-")
R.vlg_alpha = true
T.probe = nil
M.run_hook("PostRender")
local mok = T.Material(0, copy)
local pok = mok and mok.params or {}
check(T.litAlpha == "ok" and mok and mok.shader == "VertexLitGeneric" and pok["$alpha"] and
    math.abs(pok["$alpha"] - 170 / 255) < 1e-6 and string.find(mok:GetName(), "_a170$") ~= nil,
    "T3 ok again: the batch's material %s (%s, $alpha %s)", mok and mok:GetName() or "-", mok and mok.shader or "-",
    tostring(pok["$alpha"]))

-- 10b. 0.9.2a, T3b (sadc docs/research/gsa1_091a_perf.md 3.4 with its review RC15): a framebuffer that blends in LINEAR
-- light (the owner's Garry's Mod: the $alpha 0.5 quad reads 0.74 of the control, 188 of 255) is "ok (linear light)" -
-- 0.9.1a said "not measured" - and the lit see-through batches keep VertexLitGeneric with $alpha
R.linear = true
T.probe = nil
M.run_hook("PostRender")
local l3, lit3 = T.FormatLine(), T.lit or {}
local mlin = T.Material(0, copy)
local plin = mlin and mlin.params or {}
local sp = T.probe and T.probe[T.format.name] and T.probe[T.format.name].sample or {}
check(T.litAlpha == "ok" and lit3.space == "linear" and lit3.control == 255 and lit3.test and math.abs(lit3.test - 188) <= 1
    and string.find(l3, "blends in linear light", 1, true) ~= nil and mlin and mlin.shader == "VertexLitGeneric" and
    plin["$alpha"] and math.abs(plin["$alpha"] - 170 / 255) < 1e-6,
    "T3b, linear light: %s; the copy's material %s (%s)", T.LitLine(), mlin and mlin:GetName() or "-",
    mlin and mlin.shader or "-")
info("the unlit sample seen through a translucent material in linear light: %s %s %s (the owner's logs: 237 214 208)",
    tostring(sp.ar), tostring(sp.ag), tostring(sp.ab))
R.linear = false
T.probe = nil
M.run_hook("PostRender")
local l4, lit4 = T.FormatLine(), T.lit or {}
check(T.litAlpha == "ok" and lit4.space == "gamma" and string.find(l4, "blends in gamma space", 1, true) ~= nil,
    "T3b, gamma space again: %s", T.LitLine())
-- the verdict table of the review (T.LitVerdict on control / test pairs)
local cases = {
    { 255, 188, "ok", "linear" }, { 255, 128, "ok", "gamma" }, { 255, 255, "lost", nil }, { 255, 222, nil, nil },
    { 200, 147, "ok", "linear" }, { 40, 24, "ok", nil }, { 20, 10, nil, nil },
}
local bad = {}
for _, c in ipairs(cases) do
    local r = T.LitVerdict({ control = c[1], test = c[2] })
    if r.verdict ~= c[3] or r.space ~= c[4] then
        bad[#bad + 1] = string.format("%d/%d -> %s %s", c[1], c[2], tostring(r.verdict), tostring(r.space))
    end
end
local nm = T.LitVerdict({ control = 255, test = 222 })
check(#bad == 0 and string.find(tostring(nm.why), "linear light 188, gamma 128 expected", 1, true) ~= nil,
    "T.LitVerdict: 188 of 255 ok (linear), 128 ok (gamma), 255 lost, 222 not measured (%s), 147 of 200 ok (linear), "
    .. "24 of 40 ok without a space (too dark to tell), a control of 20 decides nothing%s", tostring(nm.why),
    #bad > 0 and ("; wrong: " .. table.concat(bad, ", ")) or "")

-- 11. 0.9.1, T1 (T2.3): lit see-through batches carry their alpha in the material. Drawn over black with the module's
-- vertex colour (white, the draw's alpha) the coverage is alpha / 255 with the lighting on and off (0.9.0, lit: 1.0 -
-- VertexLitGeneric dropped the vertex alpha); batches of different alphas never share a lit material; unlit batches are
-- not keyed by alpha and keep $vertexalpha only (no $alpha: the alpha would apply twice)
local function cover_black(mat, va)
    local tgt = GetRenderTargetEx("test_black", 4, 4, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, 12)
    tgt:Fill(0, 0, 0, 255)
    render.PushRenderTarget(tgt)
    cam.Start2D()
    render.SetMaterial(mat)
    render.OverrideBlend(true, 4, 5, BLENDFUNC_ADD)
    mesh.Begin(MATERIAL_QUADS, 1)
    for _, c in ipairs({ { 0, 0 }, { 4, 0 }, { 4, 4 }, { 0, 4 } }) do
        mesh.Position(Vector(c[1], c[2], 0))
        mesh.TexCoord(0, c[1] / 4, c[2] / 4)
        mesh.Color(255, 255, 255, va)
        mesh.AdvanceVertex()
    end
    mesh.End()
    render.OverrideBlend(false)
    cam.End2D()
    render.PopRenderTarget()
    return (tgt:Get(1, 1)) / 255
end
local function lb(key, flags)
    return { key = key, archive = -1, tex = -1, flags = flags, src = 4, dst = 5, wrap = 0, pass = 1 }
end
local CASES = {
    { "Tails' first blur copy", lb("-1.-1.21.4.5.0.1.a170", 0x21), 170 },
    { "Tails' second blur copy", lb("-1.-1.21.4.5.0.1.a85", 0x21), 85 },
    { "Amy's first hammer ghost (sphere-mapped)", lb("-1.-1.29.4.5.0.1.a76", 0x29), 76 },
    { "Amy's second hammer ghost", lb("-1.-1.21.4.5.0.1.a51", 0x21), 51 },
    { "E-102's etx_right3 part", lb("-1.-1.21.4.5.0.1.a216", 0x21), 216 },
    { "a lit translucent part of alpha 255", lb("-1.-1.21.4.5.0.1", 0x21), 255 },
    { "an unlit sprite (Amy's dizzy star)", lb("-1.-1.55.4.5.0.1", 0x55), 25 },
}
for _, set in ipairs({ "1", "0" }) do
    GSA1.cv.lighting:SetString(set)
    T.ForgetKeys()
    local bad, shared, alphas, got = {}, {}, {}, {}
    for _, cs in ipairs(CASES) do
        local m = T.Material(0, cs[2])
        local cov = cover_black(m, cs[3])
        got[#got + 1] = string.format("%s %.3f", cs[1], cov)
        if math.abs(cov - cs[3] / 255) > 1.01 / 255 then
            bad[#bad + 1] = string.format("%s covers %.3f, the game %.3f (%s %s)", cs[1], cov, cs[3] / 255, m:GetName(),
                m.shader)
        end
        local lit = m.shader == "VertexLitGeneric"
        if lit then
            if alphas[m] and alphas[m] ~= cs[3] then shared[#shared + 1] = m:GetName() end
            alphas[m] = cs[3]
        end
        local p = m.params or {}
        local want_lit = set == "1" and bit.band(cs[2].flags, 0x10) == 0
        if lit ~= want_lit or (not lit and p["$alpha"] ~= nil) or
            (lit and cs[3] < 255 and string.find(m:GetName(), "_a" .. cs[3] .. "$") == nil) then
            bad[#bad + 1] = string.format("%s: material %s (%s, $alpha %s)", cs[1], m:GetName(), m.shader,
                tostring(p["$alpha"]))
        end
    end
    check(#bad == 0 and #shared == 0, "lighting %s: over black each batch covers alpha / 255 (%s)%s%s", set,
        table.concat(got, ", "), #bad > 0 and ("; " .. table.concat(bad, "; ")) or "",
        #shared > 0 and ("; lit materials shared by different alphas: " .. table.concat(shared, ", ")) or "")
end
GSA1.cv.lighting:SetString("1")
T.ForgetKeys()
check(T.BatchAlpha({ key = "0.15.21.4.5.3.1.a170" }) == 170 and T.BatchAlpha({ key = "0.15.21.4.5.3.1" }) == 255 and
    T.BatchAlpha({ key = "x", alpha = 85 }) == 85 and T.BatchAlpha({ key = "-1.-1.211.1.1.0.1" }) == 255,
    "T.BatchAlpha: the key's .a<alpha> (255 without), or the batch's own alpha field")

check(#M.reported == 0, "no Lua error%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
