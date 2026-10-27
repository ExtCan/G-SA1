-- render_test.lua - the character's drawing (cl_render.lua, with cl_warm.lua and cl_log.lua) in Garry's Mod's own LuaJIT
-- against the mock of GMod and the module (tests/lua_mock.lua). 0.8 (sadc docs/research/gsa1_060_shadow.md G2 / G4 / G5 /
-- T5 and gsa1_060_render.md review R7.3 / 4.5 with their reviews):
--   * the blob shadow's batch (SA1_DRAW_SHADOW, address mode WRAP_MASK) is drawn with gsa1_shadow 1 whatever
--     gsa1_effects says, not with gsa1_shadow 0, not in first person; it is drawn with ZERO / ONE_MINUS_SRC_COLOR under a
--     tone-mapping scale of 1, which is put back afterwards;
--   * camera-relative drawing: PrepareView gets the character's drawn root as its origin and both passes are drawn under
--     cam.Start3D(EyePos() - root, EyeAngles()), balanced by cam.End3D; with gsa1_relative 0, or a module without the
--     feature "render", absolute positions and no cam.Start3D; the static meshes (gsa1_interpolate 0) are built once per
--     game pair;
--   * gsa1_logdraws writes a "draws" header and one line per draw into the session log; the debug line names the
--     shadow batches;
--   * 0.9.1 (sadc docs/research/gsa1_070_translucency.md T1 with its review R3.3): the module's lit see-through batches
--     (key ".a<alpha>") get materials with that $alpha; one of alpha 0 drawn SRC_ALPHA with ONE_MINUS_SRC_ALPHA or ONE is
--     not drawn (Knuckles' top-speed copies' see-through parts), with another destination factor it is.
--   lua_host tests/render_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 render_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

-- batches { archive, tex, flags, src, dst, wrap, pass, tris, prims }: the body, an additive effect sprite, the shadow
local LIST = {
    { 0, 0, 0x20, 1, 0, 3, 0, 100, 1 },
    { 1, 2, 0x255, 4, 1, 3, 1, 2, 2 },
    { 2, 58, 0x841, 4, 5, 11, 1, 2, 1 },
}
local G = M.module({ archives = { [0] = { 28, 29, 96, 138 } }, batches = function() return LIST end,
                     features = { render = 1 } })
function G.TextureArchives(kind)
    return { { name = "SONIC", count = 28 }, { name = "SON_EFF", count = 29 }, { name = "OBJ_REGULAR", count = 96 },
             { name = "EFF_REGULAR", count = 138 } }
end
-- what the frame does: the batches drawn (EmitBatch), the blend and tone-mapping at each draw, PrepareView's origin,
-- cam.Start3D / End3D
local F = { drawn = {}, emits = 0, prep = {}, starts = {}, ends = 0, tone = { 0.5, 0.5, 0.5 }, toneSets = 0 }
local blend = nil
local old_ob = render.OverrideBlend
function render.OverrideBlend(on, s, d, ...)
    old_ob(on, s, d, ...)
    blend = on and { s, d } or nil
end
function render.GetToneMappingScaleLinear() return Vector(F.tone[1], F.tone[2], F.tone[3]) end
function render.SetToneMappingScaleLinear(v)
    F.tone = { v.x, v.y, v.z }
    F.toneSets = F.toneSets + 1
end
local old_emit = G.EmitBatch
function G.EmitBatch(id, i)
    F.drawn[#F.drawn + 1] = i
    F.emits = F.emits + 1
    F.at = F.at or {}
    F.at[i] = { blend = blend and (blend[1] .. "/" .. blend[2]) or "none", tone = table.concat(F.tone, " ") }
    return old_emit(id, i)
end
local old_prep = G.PrepareView
function G.PrepareView(...)
    F.prep = { n = select("#", ...), origin = (select(12, ...)) }
    return old_prep(...)
end
cam.Start3D = function(pos, ang) F.starts[#F.starts + 1] = { pos = Vector(pos), ang = ang } end
cam.End3D = function() F.ends = F.ends + 1 end
function G.DrawList(id, out)
    local d = {
        { order = 1, prim = 0, source = 0, flags = 0x20, archive = 0, tex = 0, texname = "body", aname = "SONIC", mat = 0x94318400,
          src = 1, dst = 0, n = 100, amin = 255, amax = 255, diffuse = 0xB2B2B2FF, batch = 1, pass = 0 },
        { order = 2, prim = 1, source = 2, flags = 0x255, archive = 1, tex = 2, texname = "spark", aname = "SON_EFF",
          mat = 0, src = 4, dst = 1, n = 1, amin = 255, amax = 255, diffuse = 0, batch = 2, pass = 1 },
        { order = 3, prim = 0, source = 1, flags = 0x841, archive = 2, tex = 58, texname = "shadow",
          aname = "OBJ_REGULAR", mat = 0x94318400, src = 4, dst = 5, n = 2, amin = 204, amax = 204, diffuse = 0xB2B2B2CC,
          batch = 3, pass = 1 },
    }
    for i, e in ipairs(d) do out[i] = e end
    out.count, out.gen, out.alpha = #d, 7, 0.5
    return #d
end

GSA1 = nil
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
check(ok_load, "the addon loads through its autorun%s", ok_load and "" or (": " .. tostring(err_load)))
if not ok_load then
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return false
end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
GSA1.cv.prewarm:SetString("0")          -- the pre-warm's own draws are not what this test looks at
GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil, "Sonic spawned")
if not C then
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return false
end

-- one frame; returns the batches drawn in it (sorted) and the frame's records
local function frame()
    F.drawn, F.starts, F.ends, F.at, F.prep = {}, {}, 0, {}, {}
    M.frame(1 / 60)
    local d = {}
    for _, i in ipairs(F.drawn) do d[#d + 1] = i end
    table.sort(d)
    return table.concat(d, " ")
end
for _ = 1, 10 do frame() end

-- 1. defaults: everything drawn, the shadow with the mask's blend under a tone-mapping scale of 1
local d1 = frame()
local sh = F.at[3] or {}
local o = F.prep.origin
local st = F.starts[1]
local want_eye = st and C.drawPos and (EyePos() - C.drawPos)
check(d1 == "1 2 3" and sh.blend == "0/10" and sh.tone == "1 1 1" and F.tone[1] == 0.5 and F.toneSets >= 2,
    "defaults: batches drawn %s; the shadow with blend %s under tone-mapping scale %s (put back to %.1f afterwards)", d1,
    tostring(sh.blend), tostring(sh.tone), F.tone[1])
check(F.prep.n == 12 and o ~= nil and o.x == C.drawPos.x and o.y == C.drawPos.y and o.z == C.drawPos.z and #F.starts == 2 and
    F.ends == 2 and want_eye and math.abs(st.pos.x - want_eye.x) < 1e-3 and math.abs(st.pos.y - want_eye.y) < 1e-3 and
    math.abs(st.pos.z - want_eye.z) < 1e-3,
    "camera-relative: PrepareView's origin is the drawn root (%s), both passes inside cam.Start3D(EyePos() - root) (%d "
    .. "starts, %d ends; eye %s)", o and string.format("%.1f %.1f %.1f", o.x, o.y, o.z) or "none", #F.starts, F.ends,
    st and string.format("%.1f %.1f %.1f", st.pos.x, st.pos.y, st.pos.z) or "-")

-- 2. effects off: the shadow stays; 3. shadows off: the effects stay
GSA1.cv.effects:SetString("0")
local d2 = frame()
GSA1.cv.effects:SetString("1")
GSA1.cv.shadow:SetString("0")
local d3 = frame()
GSA1.cv.shadow:SetString("1")
check(d2 == "1 3" and d3 == "1 2", "gsa1_effects 0: batches %s (the shadow has its own switch); gsa1_shadow 0: batches %s",
    d2, d3)

-- 4. gsa1_relative 0, and a module without the feature: absolute positions, no extra view
GSA1.cv.relative:SetString("0")
frame()
local n4, s4 = F.prep.origin, #F.starts
GSA1.cv.relative:SetString("1")
G.FEATURES.render = nil
frame()
local n5, s5 = F.prep.origin, #F.starts
G.FEATURES.render = 1
check(n4 == nil and s4 == 0 and n5 == nil and s5 == 0, "gsa1_relative 0: origin %s, %d cam.Start3D; a module without "
    .. "the feature \"render\": origin %s, %d cam.Start3D", tostring(n4), s4, tostring(n5), s5)

-- 5. the static meshes (gsa1_interpolate 0): built once per game pair, also when drawn camera-relative
GSA1.cv.interp:SetString("0")
frame()
local e0 = F.emits
for _ = 1, 9 do frame() end
local static_emits = F.emits - e0
GSA1.cv.interp:SetString("1")
check(static_emits <= 3 * 6 and static_emits > 0, "gsa1_interpolate 0: %d batch emissions in 9 frames (at most one per "
    .. "batch and game pair: 3 x 5)", static_emits)

-- 6. first person: nothing of the character, the shadow neither
GSA1.cv.cam_dist:SetString("0")
local d6 = frame()
GSA1.cv.cam_dist:SetString("150")
check(d6 == "", "first person: batches drawn: \"%s\"", d6)

-- 7. gsa1_logdraws: a header and one line per draw in the session log
frame()
GSA1.LogFlush()
local before = M.files["gsa1/log.txt"] or ""
local nb = 0
for _ in string.gmatch(before, " draws +") do nb = nb + 1 end
M.cmds["gsa1_logdraws"]()
local log = M.files["gsa1/log.txt"] or ""
local nd, shadow_line = 0, nil
for l in string.gmatch(log, "[^\n]+") do
    if string.find(l, " draws +") then
        nd = nd + 1
        if string.find(l, "SHADOW", 1, true) then shadow_line = l end
    end
end
nd = nd - nb
check(nd == 4 and shadow_line and string.find(shadow_line, "texture 58 \"shadow\"", 1, true) and
    string.find(shadow_line, "OBJ_REGULAR", 1, true) and string.find(shadow_line, "alpha 204..204", 1, true),
    "gsa1_logdraws: %d lines (a header and 3 draws); the shadow's: %s", nd, tostring(shadow_line))
local rl = GSA1.RenderLine and GSA1.RenderLine(C) or ""
check(string.find(rl, "shadow batches 1", 1, true) ~= nil, "the debug line: %s", rl)

-- 8. 0.9.1, lit see-through batches: the module keys them by their vertex alpha (".a<alpha>", the 10th field here)
LIST = {
    { 0, 0, 0x20, 1, 0, 3, 0, 100, 1 },
    { 0, 15, 0x21, 4, 5, 3, 1, 10, 1, 170 },      -- Tails' first blur copy
    { 0, 15, 0x21, 4, 5, 3, 1, 10, 1, 85 },       -- the second
    { 0, 16, 0x21, 4, 5, 3, 1, 10, 1, 0 },        -- Knuckles' kind: alpha 0, SRC_ALPHA / INV_SRC_ALPHA: not drawn
    { 0, 17, 0x21, 4, 1, 3, 1, 10, 1, 0 },        -- alpha 0, SRC_ALPHA / ONE: not drawn
    { 0, 18, 0x21, 4, 0, 3, 1, 10, 1, 0 },        -- alpha 0, SRC_ALPHA / ZERO: still writes, drawn
    { 1, 2, 0x255, 4, 1, 3, 1, 2, 2 },            -- an unlit effect
}
local old_batches = G.Batches
function G.Batches(id, out)
    local n = old_batches(id, out)
    if n then
        for i, b in ipairs(LIST) do
            if b[10] and out[i] then out[i].key = out[i].key .. ".a" .. b[10] end
        end
    end
    return n
end
for _ = 1, 4 do frame() end
local d8 = frame()
local mats = C.mats or {}
local function alpha_of(i)
    local m = mats[i]
    return m and m.params and m.params["$alpha"]
end
local a2, a3 = alpha_of(2), alpha_of(3)
local rl8 = GSA1.RenderLine and GSA1.RenderLine(C) or ""
check(d8 == "1 2 3 6 7" and mats[2] and mats[2].shader == "VertexLitGeneric" and a2 and math.abs(a2 - 170 / 255) < 1e-6 and
    a3 and math.abs(a3 - 85 / 255) < 1e-6 and mats[2] ~= mats[3] and alpha_of(1) == nil and alpha_of(7) == nil and
    C.hiddenBatches == 2 and string.find(rl8, "(2 with alpha 0, not drawn)", 1, true) ~= nil,
    "lit see-through batches: drawn %s (alpha 0 with SRC_ALPHA / INV_SRC_ALPHA or ONE left out); $alpha %s / %s on %s / %s; "
    .. "the body and the unlit effect without; %s", d8, tostring(a2), tostring(a3), mats[2] and mats[2]:GetName() or "-",
    mats[3] and mats[3]:GetName() or "-", rl8)
GSA1.cv.lighting:SetString("0")
local d9 = frame()
local m9 = C.mats or {}
check(d9 == "1 2 3 6 7" and m9[2] and m9[2].shader == "UnlitGeneric" and m9[2].params["$alpha"] == nil and
    m9[2].params["$vertexalpha"] == 1, "gsa1_lighting 0: the copies are unlit (%s, $vertexalpha: the vertex alpha), "
    .. "batches drawn %s", m9[2] and m9[2]:GetName() or "-", d9)
GSA1.cv.lighting:SetString("1")

check(#M.reported == 0, "no Lua error%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
