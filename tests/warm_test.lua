-- warm_test.lua - the material pre-warm (cl_warm.lua) and the materials' naming (cl_textures.lua) in Garry's Mod's own
-- LuaJIT with a mocked GMod client (tests/lua_mock.lua), checked against the material census core_test writes (every
-- render state six characters drew in 13 s of scripted play with all their upgrades).
--   lua_host tests/warm_test.lua <tests dir> <addon/lua dir> [material_census.txt]
-- Returns true when every check passes (round 4c: the Light Speed charge freeze). G0 (the round 4c verifier's finding):
-- the pre-warm makes the EXACT material - render target in its address mode, mode, lighting, culling, half-Lambert -
-- of every census state of the spawned character kind, under lighting on and off and "both sides"; the addon's census
-- data (cl_warm_census.lua) has every state of the census core_test wrote (else: run tools/gen_warm_census.py).
-- 0.9.1 (sadc docs/research/gsa1_070_translucency.md T1, T2.4): the census has the lit see-through batches' alphas (its
-- 10th column; their key ".a<alpha>", their material's $alpha); those states' exact materials ("_a<alpha>") are warmed
-- too, and a census state has only a few alphas.
local tests, root, census = arg[1] or "tests", arg[2] or "addon/lua", arg[3]
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 warm_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

GSA1 = nil
M.load("gsa1/sh_config.lua")
M.load("gsa1/cl_log.lua")
M.load("gsa1/cl_hitch.lua")
M.load("gsa1/cl_module.lua")
M.load("gsa1/cl_textures.lua")
M.load("gsa1/cl_warm_census.lua")
if not M.load("gsa1/cl_warm.lua") or not GSA1.Warm then
    check(false, "the addon has the material pre-warm (cl_warm.lua)")
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return false
end
-- the characters' texture archives as the disc has them (texture counts per archive; core_test's texture transfer);
-- 0.8: libsa1 loads OBJ_REGULAR (96 textures, the blob shadow's) before EFF_REGULAR (138)
local ARCHIVES = { [0] = { 28, 29, 96, 138 }, [2] = { 24, 96, 138 }, [3] = { 22, 21, 96, 138 }, [5] = { 53, 4, 96, 138 },
                   [6] = { 35, 14, 12, 14, 17, 96, 138 }, [7] = { 36, 65, 8, 96, 138 } }
local G = M.module({ archives = ARCHIVES })
function G.TextureArchives(kind)
    local out = {}
    for i, n in ipairs(ARCHIVES[kind] or {}) do
        out[i] = { name = (n == 96 and "OBJ_REGULAR") or (n == 138 and "EFF_REGULAR") or ("ARCHIVE" .. (i - 1)), count = n }
    end
    return out
end
GSA1.LoadModule()
local W, T = GSA1.Warm, GSA1.Tex
local KINDS = { 0, 2, 3, 5, 6, 7 }
local NAMES = { [0] = "Sonic", [2] = "Tails", [3] = "Knuckles", [5] = "Amy", [6] = "E-102", [7] = "Big" }

-- a material's state as a word: mode, lit, both sides, half-Lambert, textured
local function sig(b)
    local mode, lit, nocull, hl = T.MaterialState(b)
    return string.format("%d%d%d%d%d", mode, lit and 1 or 0, nocull and 1 or 0, hl and 1 or 0, b.archive >= 0 and 1 or 0)
end

-- 1. the states of each character
local per = {}
for _, k in ipairs(KINDS) do
    local st = W.States(k)
    local fx, obj = 0, 0
    for a = 2, #ARCHIVES[k] do
        if ARCHIVES[k][a] ~= 96 then fx = fx + ARCHIVES[k][a] end
    end
    -- OBJ_REGULAR's textures are not warmed in the effect states (only the shadow's census state)
    for _, s in ipairs(st) do
        if ARCHIVES[k][s.archive + 1] == 96 then obj = obj + 1 end
    end
    per[#per + 1] = string.format("%s %d (%d effect textures, %d OBJ_REGULAR states)", NAMES[k], #st, fx, obj)
    if #st < 3 * fx + 60 or obj > 2 then
        check(false, "%s: %d states for %d effect textures, %d of OBJ_REGULAR", NAMES[k], #st, fx, obj)
    end
end
check(true, "states to warm: %s", table.concat(per, ", "))

-- 1b. (0.9.2, sadc docs/research/gsa1_090_render.md R1 step 5) the DepthWrite states of the depth views: $color_depth 1
-- and 0 x culled / both sides, plus every alpha-tested opaque census state's cut-out in both colour modes
local dper, dbad = {}, nil
for _, k in ipairs(KINDS) do
    local nd, cd1, cd0, atest = 0, 0, 0, 0
    for _, s in ipairs(W.States(k)) do
        if s.depth then
            nd = nd + 1
            if s.depth == 1 then cd1 = cd1 + 1 else cd0 = cd0 + 1 end
            if s.archive >= 0 then atest = atest + 1 end
        end
    end
    local want_atest = 0
    for _, c in ipairs((GSA1.WarmCensus or {})[k] or {}) do
        if c[7] == 0 and c[1] >= 0 and bit.band(c[3], 0x2) ~= 0 and bit.band(c[3], 0x1) == 0 then
            want_atest = want_atest + 2
        end
    end
    dper[#dper + 1] = string.format("%s %d", NAMES[k], nd)
    if nd ~= 4 + want_atest or cd1 ~= cd0 or atest ~= want_atest then
        dbad = dbad or string.format("%s: %d depth states (%d / %d by colour mode, %d cut-outs; %d expected)", NAMES[k],
            nd, cd1, cd0, atest, 4 + want_atest)
    end
end
check(T.DepthMaterial ~= nil and dbad == nil, "DepthWrite states to warm (4 + the alpha-tested census states x 2): %s%s",
    table.concat(dper, ", "), dbad and (" - " .. dbad) or "")

-- 2. the census: every state a character drew is warmed - its exact material (the render target in its address mode,
-- mode, lighting, culling, half-Lambert), its material state and, blended, its blend factors
local lines = census and host_read(census)
if not lines then
    info("no material census (%s): core_test writes it (with the disc); the coverage checks are skipped", tostring(census))
else
    -- the addon's census data against the census core_test wrote now
    -- a census line: kind archive texture flags src dst wrap pass prims [alpha] (0.9.1: alpha; older censuses: 255)
    local function census_alpha(line)
        return tonumber(string.match(line, "^%d+ %-?%d+ %-?%d+ %x+ %d+ %d+ %d+ %d+ %x+ (%d+)")) or 255
    end
    local have, nmiss, miss1, ncensus = {}, 0, nil, 0
    for k, list in pairs(GSA1.WarmCensus or {}) do
        for _, c in ipairs(list) do
            have[string.format("%d %d %d %X %d %d %d %d %d", k, c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8] or 255)] = true
        end
    end
    local per_state, most, most_state, nalpha = {}, 0, "-", 0
    for line in string.gmatch(lines, "[^\n]+") do
        local st = string.match(line, "^(%d+ %-?%d+ %-?%d+ %x+ %d+ %d+ %d+ %d+)")
        if st then
            ncensus = ncensus + 1
            local a = census_alpha(line)
            if not have[st .. " " .. a] then
                nmiss = nmiss + 1
                miss1 = miss1 or line
            end
            if a < 255 then
                nalpha = nalpha + 1
                local t = per_state[st] or {}
                per_state[st] = t
                if not t[a] then
                    t[a] = true
                    t.n = (t.n or 0) + 1
                    if t.n > most then most, most_state = t.n, st end
                end
            end
        end
    end
    check(ncensus > 60 and nmiss == 0, "cl_warm_census.lua has all %d census states%s", ncensus, nmiss > 0 and
        string.format(" - %d missing (e.g. %s): run tools/gen_warm_census.py", nmiss, miss1) or "")
    check(most <= 4, "the census's lit see-through states: %d with an alpha below 255, at most %d alphas per render state "
        .. "(%s; the module keeps 8 exactly)", nalpha, most, most_state)
    local settings = { { "1", "0" }, { "0", "0" }, { "1", "1" } }   -- gsa1_lighting, gsa1_nocull
    for _, set in ipairs(settings) do
        GSA1.cv.lighting:SetString(set[1])
        GSA1.cv.nocull:SetString(set[2])
        T.ForgetKeys()
        local states, pairs_ok, exact, total, missing = 0, 0, 0, 0, {}
        local dtotal, dexact, dmissing = 0, 0, {}          -- 0.9.2: the depth views' DepthWrite materials
        local exact_kind = {}
        local warm_sig, warm_pair, warm_name = {}, {}, {}
        local per_kind = {}
        for _, k in ipairs(KINDS) do
            local ws, wp, wn = {}, {}, {}
            local wd = {}
            for _, s in ipairs(W.States(k)) do
                if s.depth then
                    -- 0.9.2: a DepthWrite state (its material: T.DepthMaterial)
                    wd[T.DepthMaterial(k, s, s.depth == 1, true):GetName()] = true
                else
                    ws[sig(s)] = true
                    if s.pass == 1 then wp[select(1, T.MaterialState(s)) .. ":" .. s.src .. ":" .. s.dst] = true end
                    wn[T.Material(k, s, true):GetName()] = true
                end
            end
            per_kind[k] = { ws, wp, wn, wd }
        end
        for line in string.gmatch(lines, "[^\n]+") do
            local k, a, t, f, s, d, w, p = string.match(line,
                "^(%d+) (%-?%d+) (%-?%d+) (%x+) (%d+) (%d+) (%d+) (%d+)")
            if k then
                k, a, t, f, s, d, w, p = tonumber(k), tonumber(a), tonumber(t), tonumber(f, 16), tonumber(s), tonumber(d),
                    tonumber(w), tonumber(p)
                -- the batch as the module gives it: its key, with ".a<alpha>" for a lit see-through batch (no alpha field)
                local al = census_alpha(line)
                local b = { key = string.format("%d.%d.%X.%d.%d.%d.%d", a, t, f, s, d, w, p) ..
                            (al < 255 and (".a" .. al) or ""), archive = a, tex = t, flags = f, src = s, dst = d, wrap = w,
                            pass = p }
                local ws, wp, wn = per_kind[k][1], per_kind[k][2], per_kind[k][3]
                total = total + 1
                local ok = ws[sig(b)]
                if ok then states = states + 1 else missing[#missing + 1] = line .. " (state " .. sig(b) .. ")" end
                if p == 1 then
                    local mode = T.MaterialState(b)
                    if wp[mode .. ":" .. s .. ":" .. d] then pairs_ok = pairs_ok + 1 else
                        missing[#missing + 1] = line .. " (blend factors)" end
                else
                    pairs_ok = pairs_ok + 1
                end
                -- the exact material (a batch's own: T.Material as cl_render.lua calls it)
                local name = T.Material(k, b):GetName()
                if wn[name] then
                    exact = exact + 1
                    exact_kind[k] = (exact_kind[k] or 0) + 1
                else
                    missing[#missing + 1] = line .. " (" .. name .. " not warmed)"
                end
                -- 0.9.2: an opaque state (not the shadow) is drawn in the depth views too: its DepthWrite materials of
                -- both colour modes are warmed
                if p == 0 and bit.band(f, 0x800) == 0 then
                    for _, color in ipairs({ true, false }) do
                        dtotal = dtotal + 1
                        local dn = T.DepthMaterial and T.DepthMaterial(k, b, color):GetName() or "(no T.DepthMaterial)"
                        if per_kind[k][4][dn] then
                            dexact = dexact + 1
                        else
                            dmissing[#dmissing + 1] = line .. " (" .. dn .. " not warmed)"
                        end
                    end
                end
            end
        end
        local per = {}
        for _, k in ipairs(KINDS) do per[#per + 1] = string.format("%s %d", NAMES[k], exact_kind[k] or 0) end
        check(total > 60 and states == total and pairs_ok == total and exact == total and #missing == 0,
            "lighting %s, both sides %s: %d census states, %d with their exact material warmed (%s), %d with a warmed "
            .. "material state, %d with warmed blend factors%s", set[1], set[2], total, exact, table.concat(per, ", "),
            states, pairs_ok, #missing > 0 and ("; missing: " .. table.concat(missing, "; ")) or "")
        check(dtotal > 60 and dexact == dtotal and #dmissing == 0, "lighting %s, both sides %s: %d depth-view materials "
            .. "of the opaque census states (x 2 colour modes), %d warmed%s", set[1], set[2], dtotal, dexact,
            #dmissing > 0 and ("; missing: " .. table.concat(dmissing, "; ", 1, math.min(#dmissing, 4))) or "")
    end
    GSA1.cv.lighting:SetString("1")
    GSA1.cv.nocull:SetString("0")
    T.ForgetKeys()
end

-- 3. one material per state: batches that differ only in what the material does not see (the blend factors, which
-- render.OverrideBlend sets; the effect and loading flags) share it; known batch keys are found without a new string
local m1 = T.Material(0, { key = "1.3.255.4.1.3.1", archive = 1, tex = 3, flags = 0x255, src = 4, dst = 1, wrap = 3, pass = 1 })
local m2 = T.Material(0, { key = "1.3.215.1.1.3.1", archive = 1, tex = 3, flags = 0x215, src = 1, dst = 1, wrap = 3, pass = 1 })
local m3 = T.Material(0, { key = "1.3.15.4.5.3.1", archive = 1, tex = 3, flags = 0x15, src = 4, dst = 5, wrap = 3, pass = 1 })
check(m1 == m2 and m1 ~= m3 and m1:GetName() == "gsa1m_gsa1_BGRA8888_0_1_3_3_x010" and m3.params["$translucent"] == 1 and
    m1.params["$additive"] == 1, "materials by state: additive ONE/ONE and SRC_ALPHA/ONE share %s; translucent is %s",
    m1:GetName(), m3:GetName())
local known = { key = "1.3.255.4.1.3.1" }
collectgarbage("collect")
collectgarbage("stop")
local k0 = collectgarbage("count")
for i = 1, 1000 do
    T.Material(0, known)
end
local k1 = collectgarbage("count")
collectgarbage("restart")
check(T.Material(0, known) == m1 and (k1 - k0) * 1024 / 1000 < 8, "a known batch key's material: %.2f bytes of "
    .. "garbage per lookup (0.5.1 formatted its name with string.format and two string.gsub every time)",
    (k1 - k0) * 1024 / 1000)

-- 4. the warm-up's pace: at most WARM_BUDGET per frame, at least one item per pass, one slow item per frame
local C = { id = 1, kind = 0, title = "Sonic", drawPos = Vector(0, 0, 0) }
local n = W.Start(C)
local frames, worst = 0, 0
M.draw_cost = 0.0002              -- 0.2 ms per item (the materials exist: no CreateMaterial)
while not W.total.done and frames < 5000 do
    frames = frames + 1
    M.frameNo = M.frameNo + 1
    local t0 = SysTime()
    W.Step(C, 0)
    W.Step(C, 1)
    worst = math.max(worst, SysTime() - t0)
end
check(W.total.done and W.total.drawn == n and worst <= 0.0022 and frames >= n / 9,
    "Sonic's %d items at 0.2 ms each: done in %d frames, at most %.1f ms per frame", n, frames, worst * 1000)
GSA1.cv.lighting:SetString("0")
T.ForgetKeys()
n = W.Start(C)
M.draw_cost = 0.010               -- every item makes a shader (10 ms)
frames, worst = 0, 0
local items = 0
while not W.total.done and frames < 5000 do
    frames = frames + 1
    M.frameNo = M.frameNo + 1
    local d0 = W.total.drawn
    local t0 = SysTime()
    W.Step(C, 0)
    W.Step(C, 1)
    worst = math.max(worst, SysTime() - t0)
    items = math.max(items, W.total.drawn - d0)
end
M.draw_cost = 0
check(W.total.done and items == 1 and frames == n, "items of 10 ms each (a shader made every time): one per frame (%d "
    .. "items in %d frames, at most %d per frame, %.0f ms)", n, frames, items, worst * 1000)
n = W.Start(C)
check(n == 0, "a second spawn of the same character (same settings): nothing left to warm (%d items)", n)
GSA1.cv.prewarm:SetString("0")
check(W.Start(C) == 0 and W.total == nil, "gsa1_prewarm 0: no warm-up")
GSA1.cv.prewarm:SetString("1")
GSA1.cv.lighting:SetString("1")

print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
