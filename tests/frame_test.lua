-- frame_test.lua - the addon's whole client frame (Think, CreateMove, CalcView, the character's Draw and
-- DrawTranslucent, PostRender) in Garry's Mod's own LuaJIT with a mocked GMod client and module (tests/lua_mock.lua):
-- Sonic spawns, stands, charges the Light Speed Dash (the effects' batches change every game pair: ball shells,
-- sparkles, ribbons, then the aura) for 10 s at 60 fps. Checks that nothing raises a Lua error, that the spawn, the
-- pre-warm and the materials are in the session log, and measures the Lua garbage and Lua time per frame.
--   lua_host tests/frame_test.lua <tests dir> <addon/lua dir> [measure]
-- (measure: only print the figures - for an older addon without the session log or the pre-warm.) Round 4c.
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
    M.frame(1 / 60)
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
