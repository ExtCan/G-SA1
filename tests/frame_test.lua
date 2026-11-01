-- frame_test.lua - the addon's whole client frame (Think, CreateMove, CalcView, the character's Draw and
-- DrawTranslucent, PostRender) in Garry's Mod's own LuaJIT with a mocked GMod client and module (tests/lua_mock.lua):
-- Sonic spawns, stands, charges the Light Speed Dash (the effects' batches change every game pair: ball shells,
-- sparkles, ribbons, then the aura) for 10 s at 60 fps. Checks that nothing raises a Lua error, that the spawn, the
-- pre-warm and the materials are in the session log, and measures the Lua garbage and Lua time per frame.
--   lua_host tests/frame_test.lua <tests dir> <addon/lua dir> [measure]
-- (measure: only print the figures - for an older addon without the session log or the pre-warm.) Round 4c.
-- 0.9.5 (sadc docs/research/board095_perf.md G1 / 3.3, gsa1_095_plan.md 6.5 task 7): first 1200 frames with the module and
-- the world ready and NO character - G-SA1's own Lua garbage per frame under 64 bytes (0.9.4f: 320, one Vector and one
-- Angle a frame for the sound listener: cl_character.lua update_audio) -; then the charge as before, now with the board's
-- batches (a riding character: SA1_DRAW_BOARD) and the sun shadow on (feat/cl_liveshadow.lua: the frame runs the main
-- view's PreRender / PostDrawOpaqueRenderables too), inside the same 4 KB budget.
local tests, root, measure_only = arg[1] or "tests", arg[2] or "addon/lua", arg[3] == "measure"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 frame_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")" ..
    (measure_only and ": measurements only" or ""))

-- the characters' batches per game pair: the body (18 opaque textures), from pair 60 the charge (the spin texture,
-- the ball's two additive shells, sparkle sprites of changing textures, the ribbons), from pair 120 the aura
local memo = {}
local function batches(pair, kind)
    -- the same list object for the same structure (the mock module counts a new object as a new batch structure)
    local phase = pair >= 120 and 2 or (pair >= 60 and 1 or 0)
    local id = phase * 8 + (phase > 0 and pair % 7 or 0) + (phase > 0 and 1000 * (pair % 20) or 0)
    if memo[id] then return memo[id] end
    local out = {}
    memo[id] = out
    for i = 0, 17 do out[#out + 1] = { 0, i, 0x20, 1, 0, 3, 0, 55, 1 } end
    out[#out + 1] = { 0, 18, 0x21, 4, 5, 3, 1, 20, 1 }
    -- 0.9.5: riding - the board's model draw and its motion draw (SA1_DRAW_BOARD | EFFECT | NO_TEXTURE (+ PALETTE_LIT))
    out[#out + 1] = { -1, -1, 0x40C0, 1, 0, 0, 0, 44, 1 }
    out[#out + 1] = { -1, -1, 0x40E0, 1, 0, 0, 0, 44, 1 }
    if pair >= 60 then
        out[#out + 1] = { 0, 19, 0x20, 1, 0, 3, 0, 40, 1 }
        out[#out + 1] = { 1, 0, 0x271, 1, 1, 3, 1, 120, 1 }
        out[#out + 1] = { 1, 1, 0x271, 1, 1, 3, 1, 120, 1 }
        for s = 0, pair % 7 do
            out[#out + 1] = { 1, 2 + (pair + s) % 20, 0x275, 4, 1, 3, 1, 2, 2 }
        end
        out[#out + 1] = { 1, 27, 0x255, 4, 1, 3, 1, 40, 1 }
    end
    if pair >= 120 then
        out[#out + 1] = { -1, -1, 0x211, 1, 1, 0, 1, 870, 1 }
    end
    return out
end
local G = M.module({ archives = { [0] = { 28, 29, 138 } }, batches = batches })
-- the garbage the mock module itself makes is not the addon's: counted apart
local mock_kb = 0
for n, fn in pairs(G) do
    if type(fn) == "function" then
        G[n] = function(...)
            local k0 = collectgarbage("count")
            local a, b, c, d, e, f, g, h, i, j = fn(...)
            mock_kb = mock_kb + collectgarbage("count") - k0
            return a, b, c, d, e, f, g, h, i, j
        end
    end
end

-- the addon's client files through its own autorun: the built-in files, then gsa1/feat/*.lua (G0: the features' files)
GSA1 = nil
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local files = M.included
local feat_errors = GSA1 and GSA1.FeatureFileErrors or {}
ok_load = ok_load and #feat_errors == 0
check(ok_load and #files >= 8, "the addon's %d client files load through its autorun (%s)", #files, ok_load and
    table.concat(files, " ") or tostring(err_load or feat_errors[1]))
if not ok_load then
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return false
end
-- the module, the disc and the map are there (cl_module.lua's state after the preload)
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
GSA1.cv.upgrade_light_speed_shoes = nil

-- the frame with the main view's hooks (the sun shadow draws after the opaque renderables), its arguments made once
local CMDT = setmetatable({}, { __index = function() return function() return 0 end end })
local EYE, ANG = Vector(704, 132, -79), Angle(M.pitch, M.yaw, 0)
local HUD = { "CHudHealth", "CHudBattery", "CHudAmmo", "CHudCrosshair", "CHudWeaponSelection", "CHudChat", "CHudGMod" }
local function frame_full(dt)
    M.dt = dt
    M.T = M.T + dt
    M.frameNo = M.frameNo + 1
    M.run_hook("Think")
    M.run_hook("CreateMove", CMDT)
    local view = M.run_hook("CalcView", M.player, EYE, ANG, M.fov, 3, 30000)
    M.view_origin = view and view.origin or EYE
    M.run_hook("PreRender")
    M.run_hook("PreDrawOpaqueRenderables", false, false, false)
    for _, e in ipairs(M.entities) do
        if not e.removed and e.Draw then e:Draw() end
    end
    M.run_hook("PostDrawOpaqueRenderables", false, false, false)
    M.run_hook("PreDrawTranslucentRenderables", false, false)
    for _, e in ipairs(M.entities) do
        if not e.removed and e.DrawTranslucent then e:DrawTranslucent() end
    end
    M.run_hook("PostDrawTranslucentRenderables", false, false)
    for _, n in ipairs(HUD) do M.run_hook("HUDShouldDraw", n) end
    M.run_hook("HUDPaint")
    M.run_hook("PostRender")
end
M.camStarts = nil     -- (the mock's own record of table views is not the addon's garbage)
-- the ground for the sun shadow's traces (the trace's result table and its HitPos reused: what is measured is the addon's)
M.traceLine = function(t)
    local out = t.output or {}
    local st, en = t.start, t.endpos
    out.HitPos = out.HitPos or Vector()
    out.Hit, out.StartSolid, out.Fraction = false, false, 1
    local z = -143
    if st.z >= z and en.z <= z and st.z ~= en.z then
        local f = (st.z - z) / (st.z - en.z)
        out.Hit, out.Fraction = true, f
        out.HitPos:SetUnpacked(st.x + (en.x - st.x) * f, st.y + (en.y - st.y) * f, z)
    end
    return out
end

-- 0.9.5: no character - G-SA1's hooks' own garbage per frame (each outermost hook call measured; the driver's and the mock
-- module's left out), one collection before the window and the collector stopped for it (board095_perf.md 1: a
-- collection before every frame would count the Lua stack growing again as garbage)
local nochar_per
do
    local acc, depth = 0, 0
    local run0 = M.run_hook
    local cg = collectgarbage
    local function measured(ev, ...)
        local first
        for _, fn in pairs(M.hooks[ev] or {}) do
            local outer = depth == 0
            depth = depth + 1
            local k0, m0 = cg("count"), mock_kb
            local r = fn(...)
            if outer then acc = acc + (cg("count") - k0) - (mock_kb - m0) end
            depth = depth - 1
            if first == nil and r ~= nil then first = r end
        end
        return first
    end
    -- (a long warm-up: the JIT compiler's traces are objects of the collector too, made once)
    for _ = 1, 900 do frame_full(1 / 60) end
    M.run_hook = measured
    for _ = 1, 300 do frame_full(1 / 60) end
    acc = 0
    cg("collect")
    cg("stop")
    for _ = 1, 1200 do frame_full(1 / 60) end
    cg("restart")
    M.run_hook = run0
    nochar_per = acc * 1024 / 1200
    info("no character, the module and the world ready: G-SA1's hooks made %.1f bytes of Lua garbage per frame over 1200 "
        .. "frames (0.9.4f: about 320 in this mock - the sound listener's Vector and Angle every frame)", nochar_per)
    check(GSA1.Char == nil and nochar_per < 64, "no character: G-SA1's own Lua garbage under 64 bytes per frame (%.1f; "
        .. "0.9.4f: 320)", nochar_per)
end
GSA1.Spawn("sonic")
check(GSA1.Char ~= nil, "Sonic spawned")
if not GSA1.Char then
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return false
end
-- 10 s at 60 fps; action held from 2 s (the charge: the mock's batches follow the pairs)
local draws_missing, lua_ms, lua_n = 0, 0, 0
local kb_frames, kb = 0, 0
M.keys = 0
for f = 1, 600 do
    if f == 120 then M.keys = IN_DUCK end
    local ends0 = M.calls["mesh.End"] or 0
    local measure = f > 360 and f <= 600
    if measure then
        collectgarbage("collect")
        collectgarbage("stop")
    end
    local k0 = collectgarbage("count") - mock_kb
    local t0 = host_clock()
    frame_full(1 / 60)
    local t1 = host_clock()
    local k1 = collectgarbage("count") - mock_kb
    if measure then
        collectgarbage("restart")
        kb, kb_frames = kb + (k1 - k0), kb_frames + 1
        lua_ms, lua_n = lua_ms + (t1 - t0) * 1000, lua_n + 1
    end
    if (M.calls["mesh.End"] or 0) == ends0 then draws_missing = draws_missing + 1 end
end
local per_frame = kb * 1024 / math.max(kb_frames, 1)
info("Lua garbage per frame while charged (frames 361-600; the mock module's own left out, the mock's Vector and Angle "
    .. "are tables, larger than GMod's userdata): %.0f bytes; Lua time per frame (with the mock module): %.3f ms", per_frame,
    lua_ms / math.max(lua_n, 1))
info("materials made: %d; render targets made: %d; mesh.Begin calls: %d", M.nmaterials, M.nrts, M.calls["mesh.Begin"] or 0)
-- 0.9.5: the sun shadow drew in the measured frames (its silhouettes and receivers are inside the budget)
local SS = GSA1.SunShadow
local CB = GSA1.Char and GSA1.Char.boardBatches or 0
check(SS and SS.stats and SS.stats.refreshes >= 200 and SS.grid and SS.grid.ncells > 0 and CB == 2,
    "the sun shadow drew while charging on the board (%d silhouettes, %d receiver cells, %d board batches; the light: %s)",
    SS and SS.stats and SS.stats.refreshes or 0, SS and SS.grid and SS.grid.ncells or 0, CB, SS and SS.light and
    SS.light.text or "none")
check(#M.reported == 0, "no Lua error in 600 frames%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
check(draws_missing == 0, "the character drew in every frame (%d frames without a draw)", draws_missing)
-- owner note (plan 14.1e): a spawned camera (the Camera tool's gmod_cameraprop) sets the player's view entity; G-SA1's
-- chase camera must step aside while the player looks through it, and come back afterwards
M.player.view_entity = { class = "gmod_cameraprop" }
local view_cam = M.run_hook("CalcView", M.player, M.player:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
M.player.view_entity = nil
local view_own = M.run_hook("CalcView", M.player, M.player:EyePos(), Angle(M.pitch, M.yaw, 0), M.fov, 3, 30000)
check(view_cam == nil and type(view_own) == "table", "looking through a spawned camera: G-SA1's camera steps aside "
    .. "(%s) and is back afterwards (%s)", view_cam == nil and "no view returned" or "it still returned a view",
    type(view_own) == "table" and "a view" or "no view")
if not measure_only then
    GSA1.LogFlush()
    local log = M.files["gsa1/log.txt"] or ""
    check(string.find(log, " spawn +Sonic spawned in [%d.]+ ms %(gsa1%.Create") ~= nil, "the spawn is in the log with "
        .. "its times")
    check(GSA1.Warm.total and GSA1.Warm.total.done and string.find(log, " warm +Sonic: ") ~= nil,
        "the pre-warm finished during the first seconds (%s)", GSA1.WarmLine())
    local first_use = 0
    for _ in string.gmatch(log, " material +") do first_use = first_use + 1 end
    check(first_use == 0, "the charge's materials (spin texture, ball shells, sparkles, ribbons, aura) were all made by "
        .. "the pre-warm: %d made at their first use", first_use)
    check(per_frame < 4096, "Lua garbage per frame under 4 KB (%.0f bytes; 0.5.1 under the same mock: 4475)", per_frame)
    check(not string.find(log, " error +", 1, true), "no error lines in the session log")
end
print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
