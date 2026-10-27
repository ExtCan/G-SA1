-- feat_charopt_test.lua - round 0.9.1's character side in Garry's Mod's own LuaJIT with a mocked GMod and module
-- (tests/lua_mock.lua): the deaths and respawns of cl_character.lua (sadc docs/research/gsa1_070_drown.md G1 with its
-- review R4.3 / R4.9), the session log's game lines (G2), the lives across respawns (E2 / G1: count down, game over gives
-- 4 again, infinite), Amy's bird (gsa1_070_bird.md F4: Amy only, at once, on by default), Tails' tail blend (rounds plan
-- 14.1h), "Characters can drown" (the air timer held before every tick when off), the Character page's controls
-- (GSA1.AddCharacterOption) and the game's jingle ended with its character. The module's feature "charopt" and
-- "musicstate" are mocked (bind_charopt.cpp / bind_musicstate.cpp: every call recorded, the arguments checked).
--   lua_host tests/feat_charopt_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_charopt_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end
local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6) end

-- only this feature's files (the other features have their own tests)
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_charopt%.lua$") then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end

-- the mock module with the features ---------------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ features = { charopt = 1, musicstate = 1 } })
local R = { calls = {}, kind = {}, lives = {}, bad = {}, queue = {}, ms = { jingle = -1 }, breath = {}, fell = false }
local function rec(name, ...) R.calls[#R.calls + 1] = { name, ... } end
local function calls_of(name, id)
    local out = {}
    for _, c in ipairs(R.calls) do
        if c[1] == name and (id == nil or c[2] == id) then out[#out + 1] = c end
    end
    return out
end
local function last(name, id)
    local l = calls_of(name, id)
    return l[#l]
end
local function int_in(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end
G.CHAROPT = { COMPANION_BIRD = 1, TAILS_SNAP_TAILS = 1, DEATH_OTHER = 0, DEATH_HURT = 1, DEATH_HOST = 2,
              DEATH_DROWN = 3, DEATH_ZONE = 4, EVENT_DEATH = 6, EVENT_RESTART = 7, EVENT_TIME_UP = 12, LIVES_START = 4,
              LIVES_MAX = 127, BREATH_COUNTDOWN = 1080 }
local create = G.Create
function G.Create(kind, pos, yaw, ups)
    local id = create(kind, pos, yaw, ups)
    R.kind[id], R.lives[id] = kind, 4
    rec("Create", id, kind)
    return id
end
local destroy = G.Destroy
function G.Destroy(id)
    rec("Destroy", id)
    R.lives[id] = nil
    return destroy(id)
end
local getstate = G.GetState
function G.GetState(id, out)
    out = getstate(id, out)
    if out and R.fell then out.z = -20000 end
    return out
end
function G.SetLives(id, n)
    rec("SetLives", id, n)
    if not (int_in(id, 1, 1e9) and type(n) == "number") or R.lives[id] == nil then
        R.bad[#R.bad + 1] = "SetLives"
        return nil, "SetLives(id of a character of yours, lives)", "bad_argument"
    end
    R.lives[id] = math.min(math.max(math.floor(n), 0), 127)
    return R.lives[id]
end
function G.GetLives(id)
    rec("GetLives", id)
    return R.lives[id]
end
function G.SetCompanion(id, comp, on)
    rec("SetCompanion", id, comp, on)
    if not (int_in(id, 1, 1e9) and int_in(comp, 0, 255) and (type(on) == "boolean" or type(on) == "number")) then
        R.bad[#R.bad + 1] = "SetCompanion"
        return nil, "SetCompanion(id, companion, on)", "bad_argument"
    end
    if R.kind[id] ~= 5 then return nil, "sa1_character_set_companion: not Amy", "invalid argument" end
    return true
end
function G.Companion(id, comp) return false end
function G.SetGameOption(id, opt, v)
    rec("SetGameOption", id, opt, v)
    if not (int_in(id, 1, 1e9) and int_in(opt, 0, 255) and int_in(v, -1e6, 1e6)) then
        R.bad[#R.bad + 1] = "SetGameOption"
        return nil, "SetGameOption(id, option, value)", "bad_argument"
    end
    return true
end
function G.HoldAir(id)
    rec("HoldAir", id)
    if not int_in(id, 1, 1e9) then R.bad[#R.bad + 1] = "HoldAir" end
    local b = R.breath[id] or 0
    R.breath[id] = 0
    return b
end
function G.AudioMusicState(out)
    out = type(out) == "table" and out or {}
    for k, v in pairs(R.ms) do out[k] = v end
    out.name = R.ms.name or ""
    out.stopped = R.ms.stopped or false
    return out
end
function G.AudioMusicEnd()
    rec("AudioMusicEnd")
    R.ms = { jingle = -1, last_end = 6 }
    return true
end
-- the game's events: what the test queues comes out of the next PollEvents
local pool = {}
function G.PollEvents(out)
    out = out or {}
    local n = 0
    for _, q in ipairs(R.queue) do
        n = n + 1
        local e = pool[n] or {}
        pool[n] = e
        -- the living character's id, as the module reports it (gsa1_091b_itembox.md review R.4.1: a filter by
        -- e.character must not drop these after a respawn)
        e.type, e.id, e.bank, e.x, e.y, e.z, e.arg, e.step, e.character = q.type, q.id or 0, 0, 1, 2, 3, q.arg or 0,
            q.step or 0, (GSA1.Char and GSA1.Char.id) or 1
        out[n] = e
    end
    out[n + 1] = nil
    out.count = n
    R.queue = {}
    return out
end
local EV = { DEATH = 6, RESTART = 7, JINGLE = 4, TIME_UP = 12 }
local F_JINGLE, F_STOP, F_RESTORE = 0x8C107C80, 0x8C107ADA, 0x8C107B26
local function push(type, id, arg, step) R.queue[#R.queue + 1] = { type = type, id = id, arg = arg, step = step } end
local function frames(n, dt)
    for _ = 1, n do M.frame(dt or 1 / 60) end
end
local function console_has(text)
    for i = #M.console, 1, -1 do
        if string.find(M.console[i], text, 1, true) then return true end
    end
    return false
end
-- runs frames until the character is replaced (or `max` seconds): the time it took, or nil
local function until_respawn(max)
    local C0 = GSA1.Char
    local t0 = M.T
    for _ = 1, math.floor(max * 60) do
        M.frame(1 / 60)
        if GSA1.Char ~= C0 then return M.T - t0 end
    end
    return nil
end
-- the hooks the test sees
local seen = {}
for _, name in ipairs({ "GSA1CharacterCreated", "GSA1CharacterLeaving", "GSA1CharacterRespawned", "GSA1CharacterRemoved",
                        "GSA1CharacterDied", "GSA1CharacterRestart" }) do
    seen[name] = {}
    hook.Add(name, "charopt_test", function(...) table.insert(seen[name], { ... }) end)
end

-- 1. loading ----------------------------------------------------------------------------------------------------------
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local O = GSA1 and GSA1.CharOpt
check(ok_load and #ferr == 0 and O ~= nil, "the autorun loads feat/cl_charopt.lua (%s)", ok_load and
    table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_load or ferr[1]))
if not (ok_load and O) then return done() end
local WANT = { gsa1_amy_bird = { "1", 0, 1 }, gsa1_tails_tail_blend = { "1", 0, 1 }, gsa1_drown = { "1", 0, 1 },
               gsa1_lives = { "0", 0, 1 } }
local bad = {}
for name, w in pairs(WANT) do
    local c = M.convars[name]
    if not (c and c.client and c.save and c.v == w[1] and c.lo == w[2] and c.hi == w[3] and GSA1.CONVARS[name]) then
        bad[#bad + 1] = name
    end
end
check(#bad == 0, "4 client settings with the owner's defaults: Amy's bird on, Tails' tail blend on (the game), "
    .. "characters can drown on, lives count down%s", #bad > 0 and (": wrong " .. table.concat(bad, " ")) or "")
-- the pure lives rule
local l1, o1 = O.NextLives(4, true, 0)
local l2, o2 = O.NextLives(1, true, 0)
local l3, o3 = O.NextLives(0, true, 0)
local l4 = O.NextLives(0, true, 1)
local l5 = O.NextLives(3, false, 0)
check(l1 == 3 and not o1 and l2 == 0 and not o2 and l3 == 4 and o3 and l4 == 0 and l5 == 3, "the lives after a respawn: "
    .. "a death takes one (4 -> %d, 1 -> %d), a death with none left is game over (0 -> %d), infinite takes none, no "
    .. "death keeps them", l1, l2, l3)

GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }

-- 2. a spawn: the hooks, the lives ------------------------------------------------------------------------------------
GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil and #seen.GSA1CharacterCreated == 1 and seen.GSA1CharacterCreated[1][2] == "spawned" and
    seen.GSA1CharacterCreated[1][3] == nil and C.lives == 4 and #calls_of("SetLives") == 0 and
    #calls_of("SetCompanion") == 0 and #calls_of("SetGameOption") == 0, "Sonic spawned: GSA1CharacterCreated "
    .. "(\"spawned\") before the first tick, the game's 4 lives untouched, no bird, no tail option")
if not C then return done() end
frames(10)
check(#calls_of("HoldAir") == 0, "characters can drown (on): the air timer is never touched")

-- 3. drowning: the game's own sequence, then the respawn 1.0 s after its restart request (G1, review R4.3) -----------
M.console = {}
push(EV.JINGLE, 96, F_JINGLE, 1082)
frames(1)
push(EV.JINGLE, 96, F_JINGLE, 1083)
frames(1)
R.ms = { jingle = 96, name = "TIMER.ADX" }
frames(60)
push(EV.JINGLE, 0, F_STOP, 1862)
push(EV.DEATH, 0, 3, 1862)
R.ms = { jingle = -1, stopped = true, last_end = 3 }
local t_death = M.T + 1 / 60
frames(1)
local died = seen.GSA1CharacterDied[#seen.GSA1CharacterDied]
check(console_has("Sonic drowned") and died and died[1] == C and died[2] == 3, "DEATH cause 3: \"Sonic drowned\" in the "
    .. "chat and GSA1CharacterDied(C, 3)")
-- 0.8.0 respawned 2.5 s after the death: the drown animation is the game's own and runs until its restart request
local early = false
for _ = 1, 239 do
    M.frame(1 / 60)
    if GSA1.Char ~= C then early = true end
end
check(not early, "no respawn in the 4 s of the drown animation (0.8.0 respawned 2.5 s after the death)")
push(EV.RESTART, 2, 0, 2102)
local t_restart = M.T + 1 / 60
frames(1)
push(EV.JINGLE, 0, F_RESTORE, 2103)
R.ms = { jingle = -1, stopped = false, last_end = 3 }
local took = until_respawn(3)
local NC = GSA1.Char
local t_resp = t_restart + (took or 99)
check(took ~= nil and near(t_resp - t_restart, 1.0, 1.5 / 60) and near(t_resp - t_death, 5.0, 2 / 60) and NC ~= C and
    #seen.GSA1CharacterRestart >= 1, "RESTART 4.0 s after the drown: the respawn comes %.3f s after it (%.3f s after "
    .. "the death; review R4.3: at t + 5.0, not t + 2.5)", took or -1, t_resp - t_death)
local sl = last("SetLives")
check(NC and sl and sl[2] == NC.id and sl[3] == 3 and NC.lives == 3 and NC.spawnPos.x == C.spawnPos.x and
    console_has("Sonic respawned (drowned); lives 3"), "respawned at the spawn point with lives 4 - 1 = 3 (\"Sonic "
    .. "respawned (drowned); lives 3\")")
local rs = seen.GSA1CharacterRespawned[#seen.GSA1CharacterRespawned]
local lv = seen.GSA1CharacterLeaving[#seen.GSA1CharacterLeaving]
check(rs and rs[1] == NC and rs[2] == "drowned" and rs[3] == C and lv and lv[1] == C and lv[2] == "respawned" and
    #calls_of("AudioMusicEnd") == 0, "the hooks: GSA1CharacterLeaving(C, \"respawned\") and GSA1CharacterRespawned(NC, "
    .. "\"drowned\", C); no game music to end (the game's music came back)")
C = NC

-- 4. the countdown cancelled (air); a death with no restart request; RESTART without a death -------------------------
push(EV.JINGLE, 96, F_JINGLE, 1200)
frames(1)
push(EV.JINGLE, 96, F_JINGLE, 1201)
frames(30)
push(EV.JINGLE, 0, F_RESTORE, 1228)
frames(2)
GSA1.LogFlush()
local log = M.files["gsa1/log.txt"] or ""
check(string.find(log, "game +Sonic: the drowning countdown stopped, Sonic got air or left the water %(step 1228, 28 "
    .. "steps after it started%)") ~= nil, "the countdown cancelled: its log line")
push(EV.DEATH, 0, 1, 500)
local took2 = until_respawn(8)
check(took2 ~= nil and near(took2, 6.0, 2 / 60) and GSA1.Char.lives == 2, "a death whose restart request never comes: "
    .. "the respawn 6 s later (%.2f s), lives 3 -> %d", took2 or -1, GSA1.Char and GSA1.Char.lives or -1)
C = GSA1.Char
push(EV.RESTART, 2, 0, 900)
local took3 = until_respawn(3)
check(took3 ~= nil and near(took3, 1.0, 2 / 60) and GSA1.Char.lives == 2, "a restart request without a death (review "
    .. "R4.9): GSA1.Respawn %.2f s later, no life taken (%d)", took3 or -1, GSA1.Char and GSA1.Char.lives or -1)
C = GSA1.Char

-- 5. game over, infinite, falling out of the world, the Respawn button --------------------------------------------------
R.lives[C.id] = 0
M.console = {}
push(EV.DEATH, 0, 4, 300)
frames(1)
push(EV.RESTART, 2, 0, 421)
until_respawn(3)
check(GSA1.Char.lives == 4 and GSA1.Char.gameOver and console_has("Game over: Sonic starts again with 4 lives") and
    console_has("Sonic fell into a death zone"), "a death zone with no life left: \"Game over\", the new Sonic has 4 "
    .. "lives")
C = GSA1.Char
M.convars.gsa1_lives:SetString("1")
push(EV.DEATH, 0, 1, 300)
frames(1)
push(EV.RESTART, 2, 0, 421)
until_respawn(3)
check(GSA1.Char.lives == 4, "infinite lives: a death takes none (%d)", GSA1.Char.lives or -1)
M.convars.gsa1_lives:SetString("0")
C = GSA1.Char
R.fell = true
local took4 = until_respawn(1)
R.fell = false
check(took4 ~= nil and took4 < 0.05 and GSA1.Char.lives == 4 and console_has("respawned (fell out of the world)"),
    "below the map: respawned at once, no life taken (not a death of the game)")
C = GSA1.Char
RunConsoleCommand("gsa1_respawn")
check(GSA1.Char ~= C and GSA1.Char.lives == 4, "the Respawn button keeps the lives")
C = GSA1.Char

-- 6. the game's jingle ends with its character --------------------------------------------------------------------------
R.ms = { jingle = 55, name = "INVNCIBL.ADX", kind = 3 }
local ends = #calls_of("AudioMusicEnd")
RunConsoleCommand("gsa1_respawn")
check(#calls_of("AudioMusicEnd") == ends + 1 and R.ms.jingle == -1, "a respawn while the game's invincibility jingle "
    .. "plays ends it (gsa1.AudioMusicEnd)")
C = GSA1.Char

-- 7. Amy's bird, Tails' tail blend, switches keep the lives -------------------------------------------------------------
R.lives[C.id] = 7
GSA1.Spawn("amy")
local A = GSA1.Char
local sc = last("SetCompanion", A and A.id)
local swl = last("SetLives", A and A.id)
check(A and A.kind == 5 and sc and sc[3] == 1 and sc[4] == true and A.bird and swl and swl[3] == 7 and A.lives == 7,
    "Amy (a switch): the bird asked for before her first tick (SetCompanion(id, BIRD, true)); the lives carried over (7)")
local created = seen.GSA1CharacterCreated[#seen.GSA1CharacterCreated]
check(created and created[1] == A and created[2] == "switched to" and created[3] and created[3].kind == 0,
    "GSA1CharacterCreated(Amy, \"switched to\", the Sonic before)")
M.convars.gsa1_amy_bird:SetString("0")
local off = last("SetCompanion", A.id)
M.convars.gsa1_amy_bird:SetString("1")
local on = last("SetCompanion", A.id)
check(off and off[4] == false and on and on[4] == true and GSA1.Char == A, "unticking / ticking Amy's bird applies at "
    .. "once, without re-creating her")
GSA1.Spawn("tails")
local T = GSA1.Char
local go = last("SetGameOption", T and T.id)
M.convars.gsa1_tails_tail_blend:SetString("0")
local go2 = last("SetGameOption", T and T.id)
M.convars.gsa1_tails_tail_blend:SetString("1")
local go3 = last("SetGameOption", T and T.id)
local amy_calls = #calls_of("SetCompanion")
M.convars.gsa1_amy_bird:SetString("0")
M.convars.gsa1_amy_bird:SetString("1")
check(go and go[3] == 1 and go[4] == 0 and go2 and go2[4] == 1 and go3 and go3[4] == 0 and GSA1.Char == T and
    #calls_of("SetCompanion") == amy_calls and #calls_of("SetCompanion", T.id) == 0, "Tails: his tail blend as the game "
    .. "(SetGameOption(id, TAILS_SNAP_TAILS, 0)), off -> 1 at once; Amy's bird never touches Tails")
GSA1.Spawn("sonic")
C = GSA1.Char

-- 8. "Characters can drown" off: the air timer held before every tick ---------------------------------------------------
M.convars.gsa1_drown:SetString("0")
local h0 = #calls_of("HoldAir", C.id)
frames(30)
local h1 = #calls_of("HoldAir", C.id)
M.convars.gsa1_drown:SetString("1")
frames(30)
check(h1 - h0 == 30 and #calls_of("HoldAir", C.id) == h1, "drowning off: gsa1.HoldAir before each of 30 ticks; on: "
    .. "never (%d)", h1 - h0)

-- 9. an error in a feature's hook never breaks a spawn --------------------------------------------------------------------
hook.Add("GSA1CharacterCreated", "charopt_test_broken", function() error("a broken feature hook") end)
GSA1.Spawn("knuckles")
hook.Remove("GSA1CharacterCreated", "charopt_test_broken")
GSA1.LogFlush()
log = M.files["gsa1/log.txt"] or ""
check(GSA1.Char and GSA1.Char.kind == 3 and string.find(log, "error +hook GSA1CharacterCreated: .*a broken feature hook")
    ~= nil, "a feature hook's Lua error is logged and the spawn goes on")
M.reported = {}

-- 10. the Character page ---------------------------------------------------------------------------------------------------
local made = {}
local function standin(kind)
    local S = { kind = kind, calls = {} }
    made[#made + 1] = S
    return setmetatable(S, { __index = function(t, k)
        if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
        return function(self, ...)
            t.calls[#t.calls + 1] = { k, ... }
            return standin(k)
        end
    end })
end
vgui.Create = function(cls) return standin(cls) end
M.menu = {}
M.run_hook("PopulateToolMenu")
local entry
for _, e in ipairs(M.menu) do
    if e.class == "gsa1_character" then entry = e end
end
local panel = standin("DForm")
if entry then entry.cpanel(panel) end
local boxes, text, lives_combo = {}, {}, nil
for _, call in ipairs(panel.calls) do
    if call[1] == "CheckBox" then boxes[call[3]] = call[2] end
    if call[1] == "Help" or call[1] == "ControlHelp" then text[#text + 1] = tostring(call[2]) end
end
for _, S in ipairs(made) do
    if S.kind == "ComboBox" and rawget(S, "OnSelect") then
        for _, c in ipairs(S.calls) do
            if c[1] == "AddChoice" and c[2] == "Infinite" then lives_combo = S end
        end
    end
end
local page_text = table.concat(text, " ")
local upgrades_at, options_at = nil, nil
for i, call in ipairs(panel.calls) do
    if call[1] == "Button" and call[3] == "gsa1_upgrades_apply" then upgrades_at = i end
    if call[1] == "CheckBox" and call[3] == "gsa1_amy_bird" then options_at = i end
end
local lives_ok = false
if lives_combo then
    local was = M.convars.gsa1_lives.v
    lives_combo.OnSelect(lives_combo, 2, "Infinite", "1")
    lives_ok = M.convars.gsa1_lives.v == "1"
    M.convars.gsa1_lives:SetString(was)
end
check(entry and boxes.gsa1_amy_bird == "Amy's bird (Birdie)" and boxes.gsa1_tails_tail_blend == "Tails' tail blend" and
    boxes.gsa1_drown == "Characters can drown" and lives_ok and upgrades_at and options_at and options_at > upgrades_at
    and string.find(page_text, "could not be shown", 1, true) == nil, "Q -> Options -> G-SA1 -> Character: \"Amy's bird "
    .. "(Birdie)\", \"Tails' tail blend\", \"Characters can drown\" and the Lives box (it sets gsa1_lives), after the "
    .. "upgrades")
local saved = gsa1.FEATURES
gsa1.FEATURES = {}
local panel2 = standin("DForm")
entry.cpanel(panel2)
gsa1.FEATURES = saved
local t2 = {}
for _, call in ipairs(panel2.calls) do t2[#t2 + 1] = call[1] .. "(" .. tostring(call[3] or call[2]) .. ")" end
local t2s = table.concat(t2, " ")
check(string.find(t2s, "needs G-SA1 module 0.9.1 or newer (its charopt part)", 1, true) ~= nil and
    not string.find(t2s, "gsa1_amy_bird", 1, true) and string.find(t2s, "gsa1_upgrades_apply", 1, true) ~= nil,
    "a module without the feature: the Character page says which module is needed instead of the options")

-- 11. the session log -------------------------------------------------------------------------------------------------
GSA1.LogSummary("test")
log = M.files["gsa1/log.txt"] or ""
local want = {
    "game +Sonic: the game plays the jingle 96, the drowning countdown %(TIMER%.ADX%) %(step 1082%)",
    "game +Sonic: the game stopped its music %(step 1862%): the drown, the countdown ran out",
    "game +Sonic drowned %(death cause 3, step 1862%)",
    "game +Sonic: the game asked for the restart %(id 2, step 2102%), 4%.%d s after the death; respawn in 1%.0 s",
    "game +Sonic: the game went back to its music %(step 2103%)",
    "msg +Sonic respawned %(drowned%); lives 3",
    "spawn +Sonic respawned in .*lives 3",
    "game +the game's jingle 55 INVNCIBL%.ADX ended with Sonic %(respawned%)",
    "game +game over: Sonic had no life left at the death",
    "summary +the game: 4 deaths %(death zone x1, drowned x1, hit with no rings x2%); 4 restarts %(id 2 x4%); ",
}
local missing = {}
for _, w in ipairs(want) do
    if not string.find(log, w) then missing[#missing + 1] = w end
end
local one96 = select(2, string.gsub(log, "the game plays the jingle 96", ""))
check(#missing == 0, "the session log's game lines (jingles, the music stop, deaths, restart requests, respawns, the "
    .. "game over, the summary)%s", #missing > 0 and (": missing " .. table.concat(missing, " | ")) or "")
check(one96 == 2, "the countdown's jingle, asked for in two frames in a row, is one line each time (%d lines for 2 "
    .. "countdowns)", one96)
check(#M.reported == 0 and #R.bad == 0, "no Lua error, every module call with arguments bind_charopt.cpp accepts%s",
    #M.reported > 0 and (": " .. M.reported[1]) or (#R.bad > 0 and (": refused " .. table.concat(R.bad, " ")) or ""))
info("calls: SetLives %d, GetLives %d, SetCompanion %d, SetGameOption %d, HoldAir %d, AudioMusicEnd %d",
    #calls_of("SetLives"), #calls_of("GetLives"), #calls_of("SetCompanion"), #calls_of("SetGameOption"),
    #calls_of("HoldAir"), #calls_of("AudioMusicEnd"))
return done()
