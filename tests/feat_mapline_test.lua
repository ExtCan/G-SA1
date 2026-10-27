-- feat_mapline_test.lua - the map's collision line (0.9.2a; the 0.9.2 verifier's leftovers): 0.9.2's collision guard and
-- thin-stack counters in the map line and the Collision page's lines, and a map too big for the game's collision memory
-- (MapApply's info.too_big: no "the first character builds it", one plain chat line, and the spawn says the same words),
-- run by tests/lua_host.c in Garry's Mod's own LuaJIT:
--   lua_host tests/feat_mapline_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check = M.check
print("G-SA1 feat_mapline_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local G = M.module({})
GSA1 = nil
M.load("autorun/gsa1_autorun.lua")
local said = {}
chat.AddText = function(...)
    local t = {}
    for _, v in ipairs({ ... }) do if type(v) == "string" then t[#t + 1] = v end end
    said[#said + 1] = table.concat(t)
end
GSA1.LoadModule()

local function info(over)
    local i = { map = "gm_test", triangles = 1000, props_placed = 3, props_solid = 3, prop_hulls = 4, prop_triangles = 40,
                props_missing = 0, prop_models = 2, prop_models_missing = 0, brush_models = 2, one_way_solids = 1,
                thin_walls = 5, thin_wall_max = 16, displacements = 2, from_cache = false, cache_written = true,
                cache_ms = 1, build_ms = 900, prepared = true, prepare_ms = 120, grid_triangles = 2000, grid_objects = 30,
                grid_undersides = 4, props_note = "", cache_note = "", prepare_note = "", thin_wall_kept = 0,
                thin_stacks = 0, tris_outside = 0, frags_outside = 0, displacements_nohull = 0, props_outside = 0,
                prepare_retried = false, prepare_left_out = 0, too_big = false, too_big_note = "" }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end
local function apply(i)
    G.MapApply = function() return true, i end
    GSA1.World.state, GSA1.World.map = "ready", game.GetMap()
    local c0 = #M.console
    local ok = GSA1.ApplyWorld()
    return ok, table.concat(M.console, "\n", c0 + 1)
end

-- 1. a clean map: no clean-up line
local ok1, out1 = apply(info())
check(ok1 and string.find(out1, "collision clean-up", 1, true) == nil, "a map with nothing cleaned: no clean-up line")
-- 2. the counters, in the map line and on the Collision page
local ok2, out2 = apply(info({ tris_outside = 12, frags_outside = 3, props_outside = 2, displacements_nohull = 1,
                               thin_stacks = 40, thin_wall_kept = 7, prepare_retried = true, prepare_left_out = 12 }))
local wl = table.concat(GSA1.WorldLines(), "\n")
local want = { "12 triangles outside the map left out", "3 pieces outside their solids left out",
               "2 static props outside the map not placed", "1 displacements without collision left out",
               "40 stacked faces made one", "7 thin-wall pairs kept as two faces",
               "prepared again without 12 triangles outside the map" }
local miss = {}
for _, w in ipairs(want) do
    if not (string.find(out2, w, 1, true) and string.find(wl, w, 1, true)) then miss[#miss + 1] = w end
end
check(ok2 and #miss == 0, "the guard and thin-stack counters in the map line and the Collision page%s",
    #miss > 0 and ("; missing: " .. table.concat(miss, "; ")) or "")
-- 3. too big for the game: one plain chat line, the Collision page says so, no "the first character builds it"
local note = "this map's collision is too big for the game: its 4000000 triangles need more than the game's collision "
    .. "memory holds (64 MB ...), so no character can be created on this map (libsa1: ...)"
said = {}
local ok3, out3 = apply(info({ prepared = false, too_big = true, too_big_note = note, prepare_note = note }))
local wl3 = table.concat(GSA1.WorldLines(), "\n")
check(ok3 and GSA1.World.state == "applied" and #said == 1 and string.find(said[1], "too big for the game", 1, true) and
    string.find(out3, note, 1, true) and string.find(wl3, "too big for the game: no character can be created", 1, true) and
    string.find(wl3 .. out3, "the first character builds it", 1, true) == nil,
    "a map too big for the game: applied (no reload loop), one chat line (\"%s\"), the plain reason in the console and "
    .. "on the Collision page", said[1] or "none")
-- the spawn: the module refuses at once with the same words (gsa1.Create's "too_big")
G.Create = function() return nil, note, "too_big" end
said = {}
GSA1.Spawn("sonic")
check(GSA1.Char == nil and said[1] and string.find(said[1], "no character can be created on this map", 1, true) ~= nil,
    "spawning there: \"%s\"", said[1] or "nothing said")
check(#M.reported == 0, "no Lua error (%s)", M.reported[1] or "none")
print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
