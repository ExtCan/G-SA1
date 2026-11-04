-- feat_gcmeter_test.lua - the Lua garbage meter (round 0.9.5: sadc docs/research/board095_perf.md P2, 3.5-3.7; gsa1_095_plan.md
-- 6.5 task 2): addon/lua/gsa1/cl_gcmeter.lua with its patches in cl_hitch.lua (GSA1.GcMeter.Frame), cl_log.lua (the perf
-- line's field, the summary), cl_render.lua (the character's entity draws) and entities/gsa1_base.lua (the objects'), in
-- Garry's Mod's own LuaJIT against tests/lua_mock.lua (hook.GetTable is this file's: the mock's hook table).
--   lua_host tests/feat_gcmeter_test.lua <tests dir> <addon/lua dir>   (named feat_*: build.py --test runs it by its glob;
--   it was tests/gcmeter_test.lua, which the gate never ran - the 0.9.5 verifier's fail 3, 095-fix)
-- The frame driver runs every event G-SA1 has a hook in, in the engine's order, plus PostDrawHUD for another addon's burst.
-- Checks (board095_perf.md 3.7; each fails without the meter): (1) it loads through the autorun; (2) every G-SA1 hook
-- (an id starting with "gsa1") wrapped exactly once, a second Wrap wraps none, another addon's hooks untouched; (3) return
-- values (their number too) and errors pass through, a re-added G-SA1 hook is wrapped again; (4) 40 s with no character
-- and the collector running: a perf line every 30 s with all of the game's Lua 100-140 KB per frame for hooks that make
-- about 110, G-SA1's 9-12.5 KB for a test hook that makes 10; (5) the top hook named; (6) a 5,000 KB frame made in
-- PostDrawHUD by another addon: one burst line, G-SA1's part under 15 KB, placed "HUDPaint -> PostRender"; (7) a G-SA1
-- hook during which the collector frees memory: every sample "disturbed", nothing added; (8) a G-SA1 event fired inside a
-- G-SA1 hook counts once in the frame total (35 KB for 10 + 20 + 5); (9) after an unguarded error in a G-SA1 hook the
-- totals go on; (10) with a character the perf line carries the field; (11) the character's entity draws are a slot
-- ("Draw / the character") and the objects' entity draws too ("Draw / objects", entities/gsa1_base.lua); (12)
-- gsa1_log_garbage 0: no line, no sample; (13) the summary line with the burst count; (14) no Lua error. Measured (info):
-- the wrapper's cost per call (ns), a whole no-character frame's garbage with the meter on.
--
-- API NOTES (095-gsa1-render; board095_perf.md 3.5 as built): GSA1.GcMeter = GM: GM.Wrap() -> n (wraps every hook whose id
-- starts with GM.PREFIX "gsa1" not wrapped yet; at InitPostEntity + 1 s and at every window), GM.Slot(event, id) -> slot,
-- GM.Enter() -> k0, outer and GM.Add(slot, k0, outer) (a draw that is not a hook brackets itself while GM.on),
-- GM.Frame(now, gc, counted) (cl_hitch.lua, once per frame), GM.TakeField(now) -> text | nil (cl_log.lua's perf line,
-- every 10 s with a character: starts a new window), GM.WindowLine(now) (no character: a "perf" line "no character: ..."
-- every GM.NOCHAR_EVERY 30 s), GM.Burst (a "garbage" line for a frame of GM.BURST_KB 4096 KB or more, at most one per
-- 10 s), GM.SummaryLine() -> text | nil (the summary's "Lua garbage: ..."); GM.on = gsa1_log_garbage (client, archived,
-- 1; Q menu > Options > G-SA1 > Disc and status > Diagnostics); GM.slots[key] = { kb, n, neg, ... }, GM.hooks (measured).
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_gcmeter_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
hook.GetTable = function() return M.hooks end
local G = M.module({ archives = { [0] = { 28, 29, 138 } } })
GSA1 = nil
M.included = {}
local ok, err = pcall(M.load, "autorun/gsa1_autorun.lua")
check(ok and GSA1 and GSA1.GcMeter and GSA1.GcMeter.Wrap and GSA1.GcMeter.on == true, "the meter loads through the "
    .. "autorun, on by default (%s)", tostring(err or "ok"))
if not (ok and GSA1 and GSA1.GcMeter and GSA1.GcMeter.Wrap) then
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return false
end
local GM = GSA1.GcMeter
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
-- the frame as Garry's Mod runs it (every event G-SA1 has a hook in, plus PostDrawHUD for another addon's burst)
local HUD = { "CHudHealth", "CHudBattery", "CHudAmmo", "CHudCrosshair", "CHudWeaponSelection", "CHudChat", "CHudGMod" }
local cmdobj = setmetatable({}, { __index = { ClearButtons = function() end, GetButtons = function() return 0 end,
    SetButtons = function() end, GetViewAngles = function() return Angle(M.pitch, M.yaw, 0) end, SetViewAngles = function() end,
    GetMouseX = function() return 0 end, GetMouseY = function() return 0 end, KeyDown = function() return false end,
    GetForwardMove = function() return 0 end, GetSideMove = function() return 0 end, GetUpMove = function() return 0 end,
    SetForwardMove = function() end, SetSideMove = function() end, SetUpMove = function() end,
    GetMouseWheel = function() return 0 end, ClearMovement = function() end, CommandNumber = function() return 1 end, TickCount = function() return 1 end } })
local EYE, ANG, ANG0 = Vector(704, 132, -79), Angle(10, 0, 0), Angle()
local run = M.run_hook
local function frame()
    M.T = M.T + 1 / 60
    M.frameNo = M.frameNo + 1
    run("Think")
    run("CreateMove", cmdobj)
    local view = run("CalcView", M.player, EYE, ANG, M.fov, 3, 30000)
    M.view_origin = view and view.origin or EYE
    run("InputMouseApply", cmdobj, 0, 0, ANG0)
    run("PreRender")
    run("PreDrawOpaqueRenderables", false, false, false)
    for _, e in ipairs(M.entities) do if not e.removed and e.Draw then e:Draw(0) end end
    run("PostDrawOpaqueRenderables", false, false, false)
    for _, e in ipairs(M.entities) do if not e.removed and e.DrawTranslucent then e:DrawTranslucent(0) end end
    run("PostDrawTranslucentRenderables", false, false)
    for _, n in ipairs(HUD) do run("HUDShouldDraw", n) end
    run("HUDPaint")
    run("PostDrawHUD")
    run("PostRender")
end
local logs = {}
local realLog = GSA1.Log
GSA1.Log = function(kind, fmt, ...)
    local okf, text = pcall(string.format, fmt, ...)
    logs[#logs + 1] = { kind = kind, text = okf and text or tostring(fmt) }
    return realLog(kind, fmt, ...)
end
local function lines_of(kind)
    local out = {}
    for _, l in ipairs(logs) do if l.kind == kind then out[#out + 1] = l.text end end
    return out
end

-- synthetic hooks: G-SA1-named ones that allocate a known amount, another addon's that allocates more
local junk = {}
local X1000 = string.rep("x", 1000)
local function alloc_kb(kb, tag, keep)
    -- strings of 1 KB each, distinct per caller, index and frame (no interning); about kb KB
    local t = keep or junk
    for i = 1, kb do t[keep and i or ((i % 64) + 1)] = X1000 .. tag .. i .. "|" .. M.frameNo end
end
hook.Add("Think", "gsa1_test_alloc", function() alloc_kb(10, "g") end)
hook.Add("Think", "other_addon_think", function() alloc_kb(100, "o") end)
local burstAt, burstKeep = nil, nil
hook.Add("PostDrawHUD", "other_addon_burst", function()
    -- (kept alive for a frame, so the mock's small heap does not collect it inside the same frame)
    if burstAt and M.frameNo == burstAt then burstKeep = {} alloc_kb(5000, "b", burstKeep) else burstKeep = nil end
end)
hook.Add("HUDPaint", "gsa1_test_multi", function() return nil end)
hook.Add("Think", "gsa1_test_returns", function() end)

-- 1. wrapping
local n1 = GM.Wrap()
local n2 = GM.Wrap()
local gsa1n, othern = 0, 0
for ev, t in pairs(M.hooks) do
    for id in pairs(t) do
        if type(id) == "string" and string.sub(id, 1, 4) == "gsa1" then gsa1n = gsa1n + 1 else othern = othern + 1 end
    end
end
check(n1 == gsa1n and n2 == 0 and GM.hooks == gsa1n, "every G-SA1 hook wrapped once (%d of %d; a second Wrap: %d), "
    .. "none of the other %d", n1, gsa1n, n2, othern)
local unwrapped = M.hooks.Think.other_addon_think
check(GM.wrapped.Think.other_addon_think == nil and type(unwrapped) == "function", "another addon's hook is left alone")
-- return values and their count pass through; errors pass through
hook.Add("Think", "gsa1_test_returns", function() return 1, nil, 3 end)
GM.Wrap()
local w = M.hooks.Think.gsa1_test_returns
local a, b, c = w()
local cnt = select("#", w())
hook.Add("Think", "gsa1_test_returns", function() end)
GM.Wrap()
local cnt0 = select("#", M.hooks.Think.gsa1_test_returns())
hook.Add("Think", "gsa1_test_err", function() error("boom", 0) end)
GM.Wrap()
local okE, errE = pcall(M.hooks.Think.gsa1_test_err)
hook.Remove("Think", "gsa1_test_err")
check(a == 1 and b == nil and c == 3 and cnt == 3 and cnt0 == 0 and not okE and errE == "boom", "return values (1, nil, 3: "
    .. "%d values; none: %d) and errors (\"%s\") pass through the wrapper; a re-added G-SA1 hook is wrapped again", cnt, cnt0,
    tostring(errE))

-- 2. no character: 40 s; the collector runs as usual (falls happen)
for _ = 1, 60 do frame() end
burstAt = M.frameNo + 900
for _ = 1, 2400 do
    -- the burst frame and the next (whose Think measures it) without collector work, as between the cycles of the owner's
    -- 300-600 MB heap (the mock's heap is a few MB: its collector would run inside the burst)
    if M.frameNo == burstAt - 1 then collectgarbage("stop") end
    frame()
    if M.frameNo == burstAt + 1 then collectgarbage("restart") end
end
local gl = lines_of("garbage")
local nochar, burst = {}, {}
for _, l in ipairs(lines_of("perf")) do
    if string.find(l, "no character:", 1, true) then nochar[#nochar + 1] = l end
end
for _, l in ipairs(gl) do
    if string.find(l, "a frame made", 1, true) then burst[#burst + 1] = l end
end
for _, l in ipairs(nochar) do gl[#gl + 1] = l end
info("garbage lines: %d no-character, %d burst", #nochar, #burst)
for _, l in ipairs(gl) do info("  %s", string.sub(l, 1, 400)) end
local last = nochar[#nochar] or ""
local allKb = tonumber(string.match(last, "Lua garbage (%d+) KB per frame"))
local mineKb = tonumber(string.match(last, "of it G%-SA1's hooks ([%d.]+) KB"))
check(#nochar >= 1 and allKb and allKb >= 100 and allKb <= 140 and mineKb and mineKb >= 9 and mineKb <= 12.5,
    "a no-character perf line every 30 s: all Lua %s KB per frame (the hooks make about 110 + the driver), G-SA1's %s "
    .. "KB (its test hook makes about 10)", tostring(allKb), tostring(mineKb))
check(string.find(last, "Think / gsa1_test_alloc", 1, true) ~= nil, "the top G-SA1 hook is named")
local bl = burst[1] or ""
local bKb = tonumber(string.match(bl, "a frame made (%d+) KB"))
local bMine = tonumber(string.match(bl, "G%-SA1's hooks ([%d.]+) KB of it"))
local hp = tonumber(string.match(bl, "HUDPaint %-> PostRender (%d+) KB"))
check(#burst == 1 and bKb and bKb >= GM.BURST_KB and bMine and bMine < 15 and hp and hp >= 0.9 * bKb - 200, "the burst frame: one line, "
    .. "%s KB, G-SA1's %s KB of it, %s KB between HUDPaint and PostRender (where another addon made it)", tostring(bKb),
    tostring(bMine), tostring(hp))

-- 3. disturbed samples: a G-SA1 hook during which the collector frees memory is not added
hook.Add("Think", "gsa1_test_collect", function()
    alloc_kb(50, "c")
    collectgarbage("collect")
end)
GM.Wrap()
local s = GM.slots["Think / gsa1_test_collect"]
for _ = 1, 30 do frame() end
check(s and s.neg >= 25 and s.kb < 50, "a hook in which the collector frees memory: %d of 30 samples disturbed, %.1f KB "
    .. "added (never a negative change)", s and s.neg or -1, s and s.kb or -1)
hook.Remove("Think", "gsa1_test_collect")

-- 3b. nesting: a G-SA1 event run inside a G-SA1 hook counts once in G-SA1's total; an unguarded error is recovered
do
    hook.Add("Think", "gsa1_test_nest", function() alloc_kb(20, "n") hook.Run("GSA1TestNested") end)
    hook.Add("GSA1TestNested", "gsa1_test_inner", function() alloc_kb(5, "i") end)
    GM.Wrap()
    for _ = 1, 30 do frame() end
    local base = GM.sess.gsa1
    local pos0 = GM.sess.pos
    for _ = 1, 120 do frame() end
    local perFrame = (GM.sess.gsa1 - base) / math.max(GM.sess.pos - pos0, 1)
    local outerS, innerS = GM.slots["Think / gsa1_test_nest"], GM.slots["GSA1TestNested / gsa1_test_inner"]
    check(perFrame >= 10 + 25 - 1 and perFrame <= 10 + 25 + 3 and outerS.kb > innerS.kb, "a nested G-SA1 hook counts once "
        .. "in G-SA1's frame total (%.1f KB per frame for 10 + 20 + 5 made)", perFrame)
    hook.Add("PostRender", "gsa1_test_raise", function() error("unguarded", 0) end)
    GM.Wrap()
    local r0 = M.reported and #M.reported or 0
    local okf = pcall(frame)
    hook.Remove("PostRender", "gsa1_test_raise")
    base, pos0 = GM.sess.gsa1, GM.sess.pos
    for _ = 1, 60 do frame() end
    perFrame = (GM.sess.gsa1 - base) / math.max(GM.sess.pos - pos0, 1)
    check(not okf and perFrame >= 34 and GM.depth <= 1, "after an unguarded error in a G-SA1 hook the totals go on "
        .. "(%.1f KB per frame, depth %d)", perFrame, GM.depth)
    hook.Remove("Think", "gsa1_test_nest")
    hook.Remove("GSA1TestNested", "gsa1_test_inner")
end

-- 4. with a character: the perf line carries the field; the character's draws are a slot of their own
GSA1.Spawn("sonic")
for _ = 1, 700 do frame() end
local perf = lines_of("perf")
local pl = perf[#perf] or ""
check(string.find(pl, "Lua garbage %d+ KB per frame") ~= nil and string.find(pl, "of it G-SA1's hooks", 1, true) ~= nil,
    "the perf line carries the garbage field (%s)", string.match(pl, "Lua garbage.*$") or "none")
local ds = GM.slots["Draw / the character"]
check(ds and ds.n > 1000, "the character's entity draws are measured (%d samples)", ds and ds.n or 0)
-- the objects' entity draws (entities/gsa1_base.lua): their own slot
do
    ENT = {}
    local okE, errE = pcall(M.load, "entities/gsa1_base.lua")
    local BASE = ENT
    ENT = nil
    local O0 = GSA1.Objects
    local keepO = {}
    GSA1.Objects = { DrawEntity = function(e, pass) keepO[#keepO + 1] = string.rep("o", 1000) .. pass .. #keepO end }
    local e = setmetatable({}, { __index = BASE })
    -- 095-fix: the collector is held for these 40 draws (a full cycle first), so no sample is "disturbed" by a collector
    -- step that happens to fall in them (check (7) tests that case): a sum over 40 single samples measured 25.4 KB once in
    -- the gate (41.7-46.3 KB in other runs) when a step came in the middle
    collectgarbage("collect")
    collectgarbage("stop")
    for _ = 1, 20 do
        e:Draw(0)
        e:DrawTranslucent(0)
    end
    collectgarbage("restart")
    GSA1.Objects = O0
    local os_ = GM.slots["Draw / objects"]
    check(okE and os_ and os_.n == 40 and os_.kb >= 30, "the objects' entity draws are a slot of their own (\"Draw / "
        .. "objects\": %d samples, %.1f KB for 40 draws of about 1 KB)%s", os_ and os_.n or 0, os_ and os_.kb or 0,
        okE and "" or (": " .. tostring(errE)))
end

-- 5. off: no lines, the wrappers pass through
RunConsoleCommand("gsa1_log_garbage", "0")
GSA1.Remove(true)
local before = #lines_of("garbage") + #lines_of("perf")
local n0 = GM.slots["Think / gsa1_test_alloc"].n
for _ = 1, 1900 do frame() end
check(#lines_of("garbage") + #lines_of("perf") == before and GM.slots["Think / gsa1_test_alloc"].n == n0, "gsa1_log_garbage 0: no line, no "
    .. "sample (the wrappers pass straight through)")
RunConsoleCommand("gsa1_log_garbage", "1")
-- 6. the summary
GSA1.LogSummary("test")
if GSA1.LogFlush then GSA1.LogFlush() end
local sl = string.match(M.files["gsa1/log.txt"] or "", "summary%s+(Lua garbage: about[^%c]*)")
check(sl ~= nil and string.find(sl, "1 frames made 4096 KB or more", 1, true) ~= nil, "the summary line: %s", tostring(sl))
-- 7. the wrapper's cost: the meter's own garbage per frame (no character, collector stopped, the test hooks removed)
hook.Remove("Think", "gsa1_test_alloc")
hook.Remove("Think", "other_addon_think")
for _ = 1, 60 do frame() end
collectgarbage("collect")
collectgarbage("stop")
local k0 = collectgarbage("count")
for _ = 1, 300 do frame() end
local per = (collectgarbage("count") - k0) * 1024 / 300
collectgarbage("restart")
info("a whole no-character frame with the meter on (G-SA1's hooks wrapped, the driver's own included): %.1f bytes", per)
-- the wrapper's cost per call (host_clock; the JIT on): a wrapped empty G-SA1 hook against the same function unwrapped
do
    local function empty() end
    hook.Add("Think", "gsa1_test_cost", empty)
    GM.Wrap()
    local w = M.hooks.Think.gsa1_test_cost
    local N = 1000000
    local t0 = host_clock()
    for _ = 1, N do empty() end
    local t1 = host_clock()
    for _ = 1, N do w() end
    local t2 = host_clock()
    RunConsoleCommand("gsa1_log_garbage", "0")
    local t3 = host_clock()
    for _ = 1, N do w() end
    local t4 = host_clock()
    RunConsoleCommand("gsa1_log_garbage", "1")
    hook.Remove("Think", "gsa1_test_cost")
    GM.costNs = ((t2 - t1) - (t1 - t0)) * 1e9 / N
    info("the wrapper's cost: %.1f ns per wrapped call while measuring, %.1f ns with gsa1_log_garbage 0 (a direct call "
        .. "%.1f ns)", ((t2 - t1) - (t1 - t0)) * 1e9 / N, ((t4 - t3) - (t1 - t0)) * 1e9 / N, (t1 - t0) * 1e9 / N)
end
-- the Disc and status page: the check box of gsa1_log_garbage (default 1, client, archived)
do
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    local page
    for _, e in ipairs(M.menu) do if e.class == "gsa1_disc" then page = e end end
    local calls = {}
    local any = setmetatable({}, { __index = function(t) return function() return t end end })
    local P = setmetatable({}, { __index = function(_, k)
        return function(_, ...)
            calls[#calls + 1] = { k, ... }
            return any
        end
    end })
    local built = page and pcall(page.cpanel, P)
    local box, after = nil, false
    for i, c in ipairs(calls) do
        if c[1] == "CheckBox" and c[3] == "gsa1_log_garbage" then box = c end
        if c[1] == "NumSlider" and c[3] == "gsa1_log_hitch_ms" and calls[i + 1] and calls[i + 1][3] == "gsa1_log_garbage" then
            after = true
        end
    end
    local d = GSA1.CONVARS.gsa1_log_garbage
    check(built and box and after and d and d.default == "1" and M.convars.gsa1_log_garbage.client and
        M.convars.gsa1_log_garbage.save, "Options > G-SA1 > Disc and status: \"%s\" under the slow-frame threshold "
        .. "(gsa1_log_garbage, on)", box and box[2] or "-")
    -- (fardraw stage 1, sadc docs/research/fardraw.md 4.4, review RF.10: the log's sample has its own box on the same page, beside the log's)
    local behind = nil
    for _, c in ipairs(calls) do
        if c[1] == "CheckBox" and c[3] == "gsa1_log_behind" then behind = c end
    end
    local db = GSA1.cv.log_behind
    check(behind and db and db:GetBool() and M.convars.gsa1_log_behind.save, "the same page: \"%s\" (gsa1_log_behind, on)", behind and behind[2] or "-")
end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
