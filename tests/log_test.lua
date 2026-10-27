-- log_test.lua - the session log (cl_log.lua, cl_hitch.lua, cl_module.lua's GSA1.Msg, cl_textures.lua's material lines,
-- cl_warm.lua's summary) in Garry's Mod's own LuaJIT with a mocked GMod client (tests/lua_mock.lua): an in-memory
-- DATA folder, ConVars, hooks, a controllable SysTime.
--   lua_host tests/log_test.lua <tests dir> <addon/lua dir>
-- Returns true when every check passes (sadc docs/research/gsa1_lsd_lag.md 6.5 and its review R.4.4; round 4c).
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check = M.check
print("G-SA1 log_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

-- the addon files the log touches (the same order as gsa1_autorun.lua)
GSA1 = nil
M.load("gsa1/sh_config.lua")
local have_log = M.load("gsa1/cl_log.lua")
M.load("gsa1/cl_hitch.lua")
M.load("gsa1/cl_module.lua")
M.load("gsa1/cl_textures.lua")
M.load("gsa1/cl_warm.lua")
check(have_log and type(GSA1.Log) == "function", "the addon has a session log (GSA1.Log)")
if not have_log or type(GSA1.Log) ~= "function" then
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return false
end
local LOG, OLD = "gsa1/log.txt", "gsa1/log_previous.txt"
local function think(dt)
    M.T = M.T + dt
    M.frameNo = M.frameNo + 1
    GSA1.HitchFrame(M.T)
    for _, fn in pairs(M.hooks.Think or {}) do fn() end
end
local function count(pattern, text)
    local n = 0
    for _ in string.gmatch(text or M.files[LOG] or "", pattern) do n = n + 1 end
    return n
end

-- 1. header + messages; the module's line
M.module()
GSA1.LoadModule()
GSA1.Msg("disc loaded from %s", "<disc>/Sonic Adventure.gdi")
think(0.0167)
think(2.1)             -- the 2-second flush
local log = M.files[LOG] or ""
check(count("==== G%-SA1 session", log) == 1, "one session header")
check(string.find(log, "map gm_freespace_13", 1, true) ~= nil and string.find(log, "screen 3440x1440", 1, true) ~= nil,
    "the header names the map and the screen")
check(string.find(log, "upgrades: none", 1, true) ~= nil and string.find(log, "pre-warm 1", 1, true) ~= nil,
    "the header lists the settings (pre-warm) and the upgrades")
check(string.find(log, "Lua heap", 1, true) ~= nil, "the header has the Lua heap")
check(count(" msg +module 0%.6%.0 loaded", log) == 1, "GSA1.Msg lines go into the log")
check(string.find(log, "module +module 0.6.0 %(API 6, build mock build%)") ~= nil, "a module line with its build")
-- G0 (gsa1_lsd_lag.md review R.4.4, the round 4c verifier): the module decides its vector mode when it opens, so the
-- header (written with the module's first message) and the module line name it
local header = string.match(log, "==== G%-SA1 session.-Lua heap") or ""
check(string.find(header, "vector mode 1 (two scratch Vectors written in place)", 1, true) ~= nil and
    string.find(log, "module +module 0%.6%.0 .-; vector mode 1 %(two scratch") ~= nil and
    string.find(header, "features: none", 1, true) ~= nil,
    "the header and the module line name the vector mode (and the features)")
check(#M.console >= 2, "GSA1.Msg still prints to the console")
check(not string.find(log, "C:\\", 1, true) and not string.find(log, "Users", 1, true), "no paths in the log")
check(GSA1.LogLine and string.find(GSA1.LogLine(), "session log: on", 1, true) ~= nil, "the status line: %s",
    GSA1.LogLine and GSA1.LogLine() or "?")

-- 2. repeats are counted, not written
for i = 1, 100 do GSA1.Msg("capacity at (%d %d %d): the NEAR-poly list", 1, 2, 3) end
M.T = M.T + 11
GSA1.Hitch.last = nil       -- (a pause in the game: not a frame)
GSA1.Msg("capacity at (%d %d %d): the NEAR-poly list", 1, 2, 3)
GSA1.LogFlush()
log = M.files[LOG]
check(count("capacity at %(1 2 3%)", log) == 2, "a line repeated 101 times within 10 s is written twice")
check(string.find(log, "repeated 99 more times", 1, true) ~= nil, "... with the count of the ones left out")
GSA1.Note("capacity", "capacity at (%d %d %d): %s", 5, 6, 7, "the matrix stack")
GSA1.LogFlush()
check(count(" capacity +capacity at %(5 6 7%)", M.files[LOG]) == 1 and
    string.find(M.console[#M.console], "capacity at (5 6 7)", 1, true) ~= nil,
    "GSA1.Note: a capacity line in the log (kind \"capacity\") and the console")

-- 3. slow frames: 80 ms -> the log only; 150 ms -> the log and the console; the Lua heap and the GC in hitch lines
GSA1.Char = { id = 1, title = "Sonic", state = { mode = 4, action = 14, ground = true, pairs = 1, x = 1, y = 2, z = 3,
              draws = 40, sprites = 15, blend_layers = 0.21 }, triangles = 2971, batches = { count = 26 },
              blendedBatches = 6, spriteBatches = 2, alpha = 0.5, drawPos = Vector(1, 2, 3) }
local c0 = #M.console
think(0.0167)
GSA1.HitchAdd("EmitBatch", 0.004)
GSA1.HitchAdd("Tick", 0.0006)
think(0.080)
GSA1.HitchAdd("EmitBatch", 0.004)
think(0.150)
GSA1.LogFlush()
log = M.files[LOG]
check(count(" hitch +a frame took 80 ms", log) == 1, "an 80 ms frame is in the log")
check(string.find(log, "EmitBatch 4.0", 1, true) ~= nil and string.find(log, "mode 4 action 14", 1, true) ~= nil and
    string.find(log, "15 sprites", 1, true) ~= nil and string.find(log, "effects cover 0.21 screens", 1, true) ~= nil,
    "with its sections, what the character was doing and drawing, the effects' screen coverage")
check(string.find(log, "a frame took 80 ms[^\n]*elsewhere: Garry's Mod[^\n]*Lua heap [%d.]+ MB") ~= nil,
    "with the time outside G-SA1 and the Lua heap")
check(#M.console - c0 == 1 and string.find(M.console[#M.console], "hitch: a frame took 150 ms", 1, true) ~= nil,
    "only the 150 ms frame goes to the console (gsa1_hitch_ms 100)")
check(count(" hitch +a frame took 150 ms", log) == 1, "the 150 ms frame is in the log once (not twice through Msg)")
do
    -- a frame in which the Lua collector freed memory
    local saved = collectgarbage
    local heap = 50000
    collectgarbage = function(what) if what == "count" then return heap end return saved(what) end
    think(0.0167)
    heap = 42000
    think(0.090)
    collectgarbage = saved
    GSA1.LogFlush()
    check(count("a frame took 90 ms[^\n]*the GC freed 8000 KB in it", M.files[LOG]) == 1,
        "a hitch in which the Lua GC ran says how much it freed")
end

-- 4. performance lines every 10 s, slow seconds under 3/4 of fps_max
for i = 1, 600 do think(1 / 60) end
local slow0 = count(" slow +")
for i = 1, 80 do think(1 / 40) end       -- two seconds at 40 fps
for i = 1, 120 do think(1 / 60) end
GSA1.LogFlush()
log = M.files[LOG]
check(count(" perf +", log) >= 1, "a performance line every 10 s while a character is active (%d)", count(" perf +", log))
check(string.find(log, "mode/action 4/14", 1, true) ~= nil and string.find(log, "perf [^\n]*Lua heap") ~= nil and
    string.find(log, "effects up to 0.21 screens", 1, true) ~= nil,
    "... with the character's mode / action, the Lua heap and the effects' coverage")
check(count(" slow +4%d fps", log) >= 1 and count(" slow +", log) - slow0 <= 3,
    "the 40 fps seconds are reported (%d slow lines)", count(" slow +", log) - slow0)
check(count(" slow +[^\n]*worst frame 150 ms", log) == 1, "the second with the 150 ms frame is reported as slow")

-- 5. stutters (review R.4.4): a frame over twice the median of the second before it and at least 25 ms
local s0 = count(" stutter +")
for i = 1, 60 do think(1 / 60) end
check(count(" stutter +") == s0, "steady frames: no stutter line")
think(0.033)
for i = 1, 30 do think(1 / 60) end
GSA1.LogFlush()
log = M.files[LOG]
check(count(" stutter +", log) - s0 == 1 and string.find(log, "stutter +a frame took 33 ms %(the median of the second "
    .. "before: 16%.7 ms%)[^\n]*mode 4 action 14") ~= nil, "one 33 ms frame among 60 fps frames: exactly one stutter line")
think(0.022)
GSA1.LogFlush()
check(count(" stutter +", M.files[LOG]) - s0 == 1, "a 22 ms frame is no stutter (under 25 ms)")

-- 6. the drawn character jumping (review R.4.4: the 0.5.0 Light Speed release moved it 63 units per frame)
local j0 = count(" jump +")
for i = 1, 10 do
    GSA1.Char.drawPos.x = GSA1.Char.drawPos.x + 5
    think(1 / 60)
end
GSA1.Char.drawPos.x = GSA1.Char.drawPos.x + 63
think(1 / 60)
GSA1.Char.drawPos.x = GSA1.Char.drawPos.x + 63
think(1 / 60)
GSA1.LogFlush()
log = M.files[LOG]
check(count(" jump +", log) - j0 == 1 and string.find(log, "jump +the drawn character moved 63 units in one frame") ~= nil,
    "a drawPos step of 63 units gives one jump line (at most one per second); 5-unit steps none")

-- 6b. 0.8.0 (sadc docs/research/gsa1_060_pops.md F2 / D4, F3 and F4 with the review R.5). step(): one Think (LogFrame
-- judges the move made before it), then this Think's tick and render: a move of `move` units in `dt`, the state's speed
-- and the pairs the tick ran
do
    local C6, H = GSA1.Char, GSA1.Hitch
    local appends0 = M.appends
    local function step(dt, move, speed, pairs)
        think(dt)
        C6.drawPos.x = C6.drawPos.x + move
        C6.state.vx, C6.state.pairs = speed, pairs or 1
    end
    local function steady(n, speed) for i = 1, n do step(1 / 60, speed / 60, speed) end end
    local function jumps() GSA1.LogFlush() return count(" jump +") end
    steady(70, 970)
    -- (a) Sonic rolling at 2430 units/s: 40.5 units every 16.7 ms frame (0.6.0: a line every second)
    local j = jumps()
    steady(120, 2430)
    check(jumps() == j, "D4 (a): rolling at 2430 units/s, 40.5 units per frame: no jump line")
    -- (b) a 92 ms frame moving 89 units at 970 units/s (0.6.0: a line naming the 16.7 ms frame after it)
    steady(70, 970)
    j = jumps()
    step(0.092, 89, 970, 3)
    steady(70, 970)
    check(jumps() == j, "D4 (b): a long frame that moves as far as the speed says: no jump line")
    -- (c) 0.6.0's lurch (section 4.3): 36.2 units in a 119 ms frame (behind), then 65.7 units in 21.0 ms (catching up)
    steady(70, 799)
    j = jumps()
    step(0.119, 36.2, 799, 4)
    step(0.021, 65.7, 799, 0)
    steady(70, 799)
    local log6 = M.files[LOG]
    check(jumps() == j + 1 and string.find(log6, "jump +the drawn character moved 66 units in one frame of 21%.0 ms") ~= nil,
        "D4 (c): the lurch after a long frame: one line naming the 21.0 ms frame that moved")
    -- (e) the owner's 145 ms frame (section 4.4): 46 units in it, then 88, 54, 18 in 16.7 ms frames at 1061 units/s
    -- (F2 as first written printed nothing here)
    steady(70, 1061)
    j = jumps()
    step(0.145, 46, 1061, 5)
    step(1 / 60, 88, 1061, 0)
    step(1 / 60, 54, 1061, 1)
    step(1 / 60, 18, 1061, 1)
    steady(620, 1061)
    log6 = M.files[LOG]
    check(jumps() == j + 1 and string.find(log6, "jump +the drawn character moved 88 units in one frame of 16%.7 ms "
        .. "%(5280 units/s%), more than the game's speed explains %(up to 1061 units/s: at most 35 units%); 0 pairs") ~= nil,
        "D4 (e): the 88-unit frame after the 145 ms one: one line (the 54-unit frame within the second is not repeated)")
    check(string.find(log6, "perf [^\n]*ticks of 2%+ pairs %d+ %(largest 5%)") ~= nil,
        "the perf line counts the ticks of 2 or more pairs (and the largest)")
    -- (f) an uncounted frame (alt-tab), then a move of 200 units: no line (0.6.0 compared across it)
    j = jumps()
    M.focus = false
    think(1 / 60)
    C6.drawPos.x = C6.drawPos.x + 200
    M.focus = true
    think(1 / 60)
    steady(70, 1061)
    check(jumps() == j, "D4 (f): a move across an uncounted frame is not a jump")

    -- F3: pauses are not hitches
    local pr = M.hooks.PostRender and M.hooks.PostRender.gsa1_hitch_pause
    check(pr ~= nil, "cl_hitch.lua counts the drawn frames (a PostRender hook)")
    pr = pr or function() end
    local function hist_sum()
        local n = 0
        for _, v in pairs(GSA1.LogState.hist) do n = n + v end
        return n
    end
    for i = 1, 30 do step(1 / 60, 13, 780) pr() end
    local L6 = GSA1.LogState
    local h0, max0, hit0, p0 = hist_sum(), L6.frameMax, count(" hitch +"), count(" pause +")
    j = jumps()
    -- 45 s of single player paused in the escape menu: 2,700 frames drawn, no Think; the character "moved" in it
    for i = 1, 900 do pr() end
    M.ui = true
    for i = 1, 900 do pr() end
    M.ui = false
    for i = 1, 900 do pr() end
    C6.drawPos.x = C6.drawPos.x + 200
    think(45)
    local paused1 = H.tickPaused
    check(hist_sum() == h0 and L6.frameMax == max0, "F3: the 45 s pause is not in the frame statistics (histogram %d -> %d, "
        .. "worst frame %.0f -> %.0f ms)", h0, hist_sum(), max0 * 1000, L6.frameMax * 1000)
    step(1 / 60, 13, 780)
    pr()
    local paused2 = H.tickPaused
    -- the same pause without the escape menu (frames drawn without a Think only)
    for i = 1, 2700 do pr() end
    think(45)
    local paused3 = H.tickPaused
    for i = 1, 70 do step(1 / 60, 13, 780) pr() end
    GSA1.LogFlush()
    log6 = M.files[LOG]
    check(count(" hitch +", log6) == hit0 and not string.find(log6, "a frame took 45000 ms", 1, true),
        "F3: no hitch line for the pauses")
    check(count(" pause +", log6) == p0 + 2 and string.find(log6, "pause +the game was paused or in the background for "
        .. "45%.0 s %(the escape menu or console was open; 2701 frames drawn without a tick%); not a hitch") ~= nil and
        string.find(log6, "pause +the game was paused or in the background for 45%.0 s %(2701 frames drawn without a "
        .. "tick%)") ~= nil,
        "F3: one pause line each (with the escape menu, and drawn without ticking)")
    check(paused1 == true and paused2 == false and paused3 == true, "F3: the tick after a pause runs no time "
        .. "(GSA1.Hitch.tickPaused %s, then %s; without the menu %s)", tostring(paused1), tostring(paused2), tostring(paused3))
    check(jumps() == j, "F3: the frame after a pause gives no jump line")
    -- a real freeze (one frame drawn in it) is still a hitch
    pr()
    think(0.389)
    local paused4 = H.tickPaused
    GSA1.LogFlush()
    check(count(" hitch +a frame took 389 ms", M.files[LOG]) == 1 and paused4 == false,
        "F3: a 389 ms freeze drawn once is a hitch, and its tick runs")
    steady(70, 780)

    -- F4: the views that draw the character (cl_render.lua is not loaded here: a stand-in DrawCharacter)
    local calls6 = 0
    GSA1.DrawCharacter = function(C, pass) calls6 = calls6 + 1 end
    think(1 / 60)
    local wrapped = GSA1.DrawCharacter
    local frames6 = 0
    for f = 1, 640 do
        step(1 / 60, 13, 780)
        frames6 = frames6 + 1
        -- the water reflection first (a render target, its own origin), then the screen; two blended passes
        M.render_target = { GetName = function() return "_rt_WaterReflection" end }
        M.view_setup = { origin = Vector(1, 2, 3) }
        GSA1.DrawCharacter(C6, 0)
        M.render_target, M.view_setup = nil, nil
        GSA1.DrawCharacter(C6, 0)
        GSA1.DrawCharacter(C6, 1)
        GSA1.DrawCharacter(C6, 1)
    end
    think(1 / 60)
    GSA1.LogFlush()
    log6 = M.files[LOG]
    check(calls6 == 4 * frames6 and wrapped ~= nil, "F4: the draws are counted and still drawn (%d of %d)", calls6,
        4 * frames6)
    check(string.find(log6, "perf [^\n]*; the character drawn in 2%.00 opaque / 2%.00 blended views per frame %(at most "
        .. "2 / 2%)") ~= nil, "F4: the perf line gives the views per frame")
    check(count("views +the character was drawn in", log6) == 1 and string.find(log6, "views +the character was drawn in 2 opaque and 2 blended "
        .. "views in one frame: opaque pass, origin %(1 2 3%), target _rt_WaterReflection, called from [^;]*main chunk") ~= nil
        and string.find(log6, "; opaque pass, origin %?, target the screen", 1, false) ~= nil,
        "F4: one views line per session describes each view (origin, render target, the Lua caller)")
    GSA1.DrawCharacter = nil
    check(M.appends - appends0 <= 40, "the log is still appended in batches (%d appends in this section)",
        M.appends - appends0)
    M.appends = appends0             -- (section 10 counts the appends of the original sections)
end
-- 7. errors in guarded hooks
local calls = 0
local guarded = GSA1.Guard("Think", function() calls = calls + 1 error("boom " .. calls) end)
for i = 1, 8 do guarded() end
log = M.files[LOG]
check(calls == 8, "a guarded hook keeps running after errors")
check(count(" error +Lua error in Think: ", log) == 5, "the first 5 errors are logged (%d)",
    count(" error +Lua error in Think: ", log))
check(#M.reported == 5, "... and reported like Garry's Mod reports errors")
local okv = GSA1.Guard("CalcView", function() return { origin = 1 } end)()
check(type(okv) == "table" and okv.origin == 1, "a guarded hook returns its result")

-- 8. materials made at their first use: one line each (the same batches resolved again: none); the pre-warm's
-- materials are not logged one by one
local m0 = count(" material +")
local keys = { "0.3.20.1.0.3.0", "1.5.255.4.1.3.1", "-1.-1.211.1.1.0.1" }
for round = 1, 2 do
    for _, k in ipairs(keys) do
        local a, t, f, s, d, w, p = string.match(k, "^(%-?%d+)%.(%-?%d+)%.(%x+)%.(%d+)%.(%d+)%.(%d+)%.(%d+)$")
        GSA1.Tex.Material(0, { key = k, archive = tonumber(a), tex = tonumber(t), flags = tonumber(f, 16),
                               src = tonumber(s), dst = tonumber(d), wrap = tonumber(w), pass = tonumber(p) })
    end
end
GSA1.LogFlush()
log = M.files[LOG]
check(count(" material +", log) - m0 == 3 and string.find(log, "material +gsa1m_white_x000 %(UnlitGeneric, additive, "
    .. "batch %-1%.%-1%.211%.1%.1%.0%.1%) created at its first use in") ~= nil,
    "3 batches resolved twice: 3 material lines (name, shader, what, the time)")
check(count(" texture +render target gsa1_BGRA8888_0_0_3_3 [^\n]*made at its first use", log) == 1,
    "a render target made for a batch at its first use is logged")
GSA1.Char.kind = 0
GSA1.Char.drawPos = Vector(0, 0, 0)
local n = GSA1.Warm.Start(GSA1.Char)
check(n > 50, "the pre-warm queues %d materials and states for a character", n)
M.material_cost = 0.0002
M.draw_cost = 0.0001
local frames = 0
while GSA1.Warm.total and not GSA1.Warm.total.done and frames < 2000 do
    frames = frames + 1
    M.frameNo = M.frameNo + 1
    GSA1.Warm.Step(GSA1.Char, 0)
    GSA1.Warm.Step(GSA1.Char, 1)
end
M.material_cost, M.draw_cost = 0, 0
GSA1.LogFlush()
log = M.files[LOG]
check(GSA1.Warm.total.done and count(" warm +Sonic: %d+ materials and states prepared in [%d.]+ ms over %d+ frames", log) == 1
    and count(" material +", log) - m0 == 3, "the pre-warm's summary is one warm line (%d frames); its materials are not "
    .. "logged one by one", frames)

-- 9. a session log mark, the summary at the line cap, rotation
GSA1.Log("mark", "%s", "lag here")
check(count(" mark +lag here", M.files[LOG]) == 1, "a mark line is written at once")
GSA1.LOG_MAX_BYTES = 8192
for i = 1, 400 do
    GSA1.Log("test", "line %d %s", i, string.rep("x", 60))
    if i % 50 == 0 then GSA1.LogFlush() end
end
GSA1.LogFlush()
check(M.files[OLD] ~= nil, "log.txt is moved to log_previous.txt at the cap")
check(#M.files[LOG] <= 8192, "log.txt stays under the cap (%d bytes)", #M.files[LOG])
GSA1.LOG_MAX_LINES = GSA1.LogState.lines + 10
for i = 1, 50 do GSA1.Log("test", "capped %d", i) end
GSA1.LogSummary("test")
GSA1.LogSummary("again")
log = M.files[LOG]
check(count("capped %d+", log) == 10, "at most LOG_MAX_LINES lines per session (%d written)", count("capped %d+", log))
check(count(" summary +session end %(test%)", log) == 1 and count("summary +frame times:", log) == 1,
    "one summary per session, written past the line cap")
check(string.find(log, "40 not written", 1, true) ~= nil and string.find(log, "summary +pre%-warm: Sonic") ~= nil and
    string.find(log, "stutters", 1, true) ~= nil and string.find(log, "summary +module 0.6.0 %(build mock build") ~= nil,
    "the summary counts the lines left out, the stutters, the pre-warm and the module's build")

-- 10. gsa1_log 0: nothing more is written; appends are batched
local before = M.files[LOG]
GSA1.cv.log:SetString("0")
GSA1.Log("test", "not written")
GSA1.LogFlush()
check(M.files[LOG] == before, "gsa1_log 0 writes nothing")
check(M.appends < 60, "the log is appended in batches (%d file.Append calls)", M.appends)
check(GSA1.LogLine() == "session log: off (gsa1_log 0)", "the status line says it is off")

-- 11. 0.9.2 (sadc docs/research/gsa1_090_plan.md 6.10 tasks 5 and 7; gsa1_090_player.md review R.5 item 9,
-- gsa1_090_water.md WTR-LOG with its review R3.2, gsa1_090_render.md D1 / review RC3), in a fresh session (cl_log.lua
-- loaded again with a new state): repeats that end inside the 10-s window reach the summary; the player's death with the
-- attacker's class and "dead while a character"; the game's water entered and left, with Garry's Mod's contents at the
-- feet and at the view; the views line with the STUDIO flags, EyePos and cl_render.lua's view kind
GSA1.cv.log:SetString("1")
GSA1.LogState = nil
M.files[LOG], M.files[OLD] = nil, nil
GSA1.LOG_MAX_LINES, GSA1.LOG_MAX_BYTES = 4000, 512 * 1024
M.load("gsa1/cl_log.lua")
local log_think = M.hooks.Think and M.hooks.Think.gsa1_log
local C11 = { id = 11, title = "Sonic", state = { x = 1, y = 2, z = 3, mode = 4, action = 14 }, drawPos = Vector(1, 2, 3),
              batches = { count = 0 } }
GSA1.Char = C11
-- (a) two identical lines 2 s apart, and nothing after them
GSA1.Log("hurt", "the player took %d damage (type %d)", 3, 2)
M.T = M.T + 2
GSA1.Log("hurt", "the player took %d damage (type %d)", 3, 2)
-- (b) the player's death (feat/cl_interact.lua runs the hook with the server's attacker class)
hook.Run("GSA1PlayerDied", C11, "npc_drg_fnaf1_bonnie", 1)
-- (c) dead while a character, for 3 s
M.player.alive = false
log_think()
M.T = M.T + 3
M.player.alive = true
log_think()
-- (d) the game's water: entered (Garry's Mod water at the feet, the view above the surface), left, entered where Garry's Mod
-- has none
M.contents = function(p) return p.z < 0 and CONTENTS_WATER or 0 end
GSA1.view = { origin = Vector(0, 0, 50), angles = Angle(0, 0, 0), frame = FrameNumber() }
C11.hostFlags = 3
local function water11(...) if GSA1.LogWater then GSA1.LogWater(...) end end
water11(C11, { x = 10, y = 20, z = -50, water_attr = 0x400002, water_level = 0 })
M.T = M.T + 1
water11(C11, { x = 10, y = 20, z = 10, water_attr = 0, water_level = 0 })
M.T = M.T + 1
water11(C11, { x = 10, y = 20, z = 100, water_attr = 0x400002, water_level = 300 })
M.T = M.T + 0.5
water11(C11, { x = 10, y = 20, z = 100, water_attr = 0x400002, water_level = 300 })
-- (e) the views line: two opaque views in one frame (the depth pass with its STUDIO flag), described the next frame
GSA1.ViewInfo = function(live, flags)
    return { kind = flags == 134217728 and "ssao" or "main", viewid = flags == 134217728 and 8 or 0,
             shader = flags == 134217728 and "DepthWrite" or "VertexLitGeneric", live = live }
end
local drawn11 = 0
GSA1.DrawCharacter = function(C, pass, flags) drawn11 = drawn11 + 1 end
log_think()                                    -- the draw counter wraps GSA1.DrawCharacter
for f = 1, 3 do
    M.frameNo = M.frameNo + 1
    GSA1.DrawCharacter(C11, 0, 134217728)
    GSA1.DrawCharacter(C11, 0, 1)
    GSA1.DrawCharacter(C11, 1, 1)
end
M.frameNo = M.frameNo + 1
GSA1.DrawCharacter(C11, 0, 1)
GSA1.DrawCharacter = nil
GSA1.ViewInfo = nil
M.contents = nil
GSA1.LogSummary("0.9.2 test")
log = M.files[LOG] or ""
check(count(" player +player died %(npc_drg_fnaf1_bonnie%)", log) == 1 and
    string.find(log, "player died (npc_drg_fnaf1_bonnie): killed outright", 1, true) ~= nil,
    "L7: a mocked player death gives one \"player died (npc_drg_fnaf1_bonnie)\" line, with how")
check(count(" player +dead while a character %(Sonic%)", log) == 1 and
    string.find(log, "the player was dead for 3.0 s while a character (Sonic); alive again", 1, true) ~= nil,
    "L7: \"dead while a character\" and for how long (3.0 s)")
local enter = string.match(log, "water +Sonic entered the game's water at %(10 20 %-50%)[^\n]*")
local leave = string.match(log, "water +Sonic left the game's water at %(10 20 10%)[^\n]*")
check(enter ~= nil and leave ~= nil and string.find(enter, "Garry's Mod: water (0x20) at the feet, empty (0x0) at the view "
    .. "(0 0 50); host flags 3", 1, true) ~= nil and string.find(enter, "its surface at 0", 1, true) ~= nil and
    string.find(leave, "Garry's Mod: empty (0x0) at the feet, empty (0x0) at the view", 1, true) ~= nil,
    "WTR-LOG: a water enter and exit give two lines with Garry's Mod's contents at the feet and at the view")
check(count("water +Sonic entered", log) == 2 and count("water +Sonic left", log) == 1,
    "... one line per change (the same state again writes nothing)")
check(string.find(log, "summary +water: in the game's water 2 times [^\n]*game water where Garry's Mod has none at the "
    .. "feet: 1 times") ~= nil, "the summary counts the game's water where Garry's Mod has none")
local views11 = string.match(log, "views +the character was drawn in 2 opaque and 1 blended views in one frame:[^\n]*") or ""
check(drawn11 == 10 and string.find(views11, "opaque pass, origin %?, target the screen, flags 134217728, called from") ~= nil
    and string.find(views11, "[eye (", 1, true) ~= nil and
    string.find(views11, "kind ssao, view id 8, shader DepthWrite", 1, true) ~= nil and
    string.find(views11, "kind main, view id 0, shader VertexLitGeneric", 1, true) ~= nil,
    "D1: the draw counter forwards the STUDIO flags; the views line has them, EyePos and cl_render.lua's view kind, view id "
    .. "and shader")
check(string.find(log, "summary +repeats: 1 repeat of 1 line within 10 s counted, not written %(1 of them only counted "
    .. "here%)") ~= nil, "two identical lines 2 s apart and nothing after: the summary reports 1 repeat (0.9.1: lost)")
check(string.find(log, "summary +the player: 1 deaths while a character; dead while a character 1 times, 3.0 s") ~= nil and
    string.find(log, "summary +the game: [^\n]*1 player deaths %(npc_drg_fnaf1_bonnie x1%)") ~= nil,
    "the summary counts the player's deaths and the time dead while a character")
GSA1.Char = nil

print(string.format("\n%d checks, %d failed", M.checks, M.fails))
if arg[3] == "dump" then
    host_write("---- the log ----\n" .. (M.files[OLD] or "") .. (M.files[LOG] or "") .. "---- end ----\n")
end
return M.fails == 0
