-- feat_jukebox_test.lua - the jukebox's addon side (round 6c J2: addon/lua/gsa1/feat/sh_jukebox.lua and cl_jukebox.lua)
-- in Garry's Mod's own LuaJIT with a mocked GMod (tests/lua_mock.lua) and a mock of the module's jukebox (the Lua API
-- of sadc docs/research/gsa1_rounds_plan.md 10.2, every call recorded). Checks the pure functions (the groups of the
-- game's sound test, next / previous, shuffle without repeats, plans, file times, search), the player (a play while
-- the track list loads, the play modes and their plans, a track's end, failures, previous / restart, pause, seek, the
-- volume, the duck sparing the jingles, JukeboxUpdate's pause and music-volume rules), the console commands, the Q-menu
-- page (every gsa1_jukebox_* setting has a control; without the module's feature it says what it needs), that nothing
-- runs before the jukebox is used and that the session log gets no titles (they come from the player's disc).
-- The track table holds numbers and file names only (sadc docs/research/jukebox.md 1.6); the titles are made up.
--   lua_host tests/feat_jukebox_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_jukebox_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end
local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6) end

-- only the jukebox's feature files (another feature's files have their own tests)
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_jukebox%.lua$") then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end

-- the disc's music: { music, file, page (0-based, -1 not in the sound test), entry, Hz, seconds, loop start, end }
local ROWS = {
    {0,"ADVAMY",4,7,44100,89.7,18.4,89.7}, {1,"ADVBIG",4,9,44100,58.0,1.2,58.0}, {2,"ADVE102",4,8,32000,64.2,8.0,64.0},
    {3,"ADVKNKLS",4,6,44100,81.3,21.8,81.3}, {4,"ADVMILES",4,5,44100,72.3,2.3,72.3},
    {5,"ADVSONIC",4,4,44100,49.5,7.8,49.5}, {6,"AMY",0,4,44100,310.5,nil,nil}, {7,"BIG",0,5,44100,242.4,nil,nil},
    {8,"BOSSALL",1,37,32000,78.4,9.5,78.2}, {9,"BOSSE101",1,34,32000,138.2,18.0,138.0},
    {10,"BOSSEVNT",1,38,32000,103.7,6.8,103.4}, {11,"BOSSTRGT",1,39,44100,82.2,2.2,82.2},
    {12,"CASINO1",1,19,44100,116.5,5.2,116.5}, {13,"CASINO2",1,20,44100,83.0,8.0,83.0},
    {14,"CASINO3",1,21,44100,78.3,6.9,78.3}, {15,"CASINO4",1,22,44100,76.6,0.6,76.6},
    {16,"CHAO",0,10,32000,129.0,27.3,128.9}, {17,"CHAOGOAL",2,10,32000,6.3,nil,nil},
    {18,"CHAOHALL",2,8,32000,67.2,30.1,67.0}, {19,"CHAORACE",2,9,32000,124.3,6.1,124.2},
    {20,"CHAOS",1,30,44100,141.7,3.3,141.7}, {21,"CHAOS_6",1,31,44100,97.6,12.5,97.6},
    {22,"CHAOS_P1",1,32,44100,130.5,4.8,130.5}, {23,"CHAOS_P2",1,33,44100,77.9,7.2,77.9},
    {24,"CHARACTR",4,2,32000,66.4,4.2,66.1}, {25,"CIRCUIT",2,5,32000,116.2,28.3,116.0},
    {26,"CONTINUE",5,10,32000,30.2,nil,nil}, {27,"E102",0,6,32000,272.1,nil,nil},
    {28,"ECOAST1",1,0,44100,112.1,42.8,112.1}, {29,"ECOAST2",1,1,44100,117.1,28.9,117.1},
    {30,"ECOAST3",1,2,44100,99.3,2.1,99.3}, {31,"EGCARER1",2,2,32000,152.6,34.3,152.4},
    {32,"EGCARER2",2,3,32000,96.9,7.8,96.7}, {33,"EGGMAN",0,7,44100,91.6,34.4,91.6},
    {34,"EGGMBL23",1,35,44100,53.9,3.1,53.9}, {35,"EGGROBO",1,36,44100,74.7,8.8,74.7},
    {36,"EVTBGM00",3,0,44100,44.0,12.8,44.0}, {37,"EVTBGM01",3,1,44100,56.5,7.3,56.5},
    {38,"EVTBGM02",3,2,44100,56.5,23.1,56.5}, {39,"EVTBGM03",3,3,44100,78.3,nil,nil},
    {40,"EVTBGM04",3,4,44100,89.6,nil,nil}, {41,"EVTBGM05",3,5,32000,24.5,nil,nil},
    {42,"FINALEG1",1,28,44100,94.1,16.8,94.1}, {43,"FINALEG2",1,29,44100,106.1,29.8,106.1},
    {44,"FISHGET",5,2,32000,7.6,nil,nil}, {45,"FISHING",5,1,44100,50.1,10.1,50.1}, {46,"FISHMISS",5,3,32000,4.9,nil,nil},
    {47,"HAMMER",2,7,32000,40.5,9.4,40.5}, {48,"HIGHWAY1",1,16,44100,111.5,7.1,111.5},
    {49,"HIGHWAY2",1,17,32000,40.3,nil,nil}, {50,"HIGHWAY3",1,18,44100,139.7,19.7,139.7},
    {51,"HURRYUP",5,0,32000,28.6,6.6,28.4}, {52,"ICECAP1",1,3,44100,102.3,3.1,102.3},
    {53,"ICECAP2",1,4,44100,87.5,3.6,87.5}, {54,"ICECAP3",1,5,44100,141.5,11.3,141.5},
    {55,"INVNCIBL",5,5,44100,23.5,nil,nil}, {56,"ITEM1",5,8,44100,6.0,nil,nil}, {57,"JINGLE_1",5,15,32000,88.4,1.0,88.3},
    {58,"JINGLE_2",5,16,32000,66.7,4.7,66.6}, {59,"JINGLE_3",5,17,32000,101.2,39.1,101.0},
    {60,"JINGLE_4",5,18,32000,58.2,2.5,58.2}, {61,"JINGLE_5",5,19,32000,27.2,3.1,27.1},
    {62,"KNUCKLES",0,3,44100,269.1,nil,nil}, {63,"LSTWRLD1",1,9,44100,127.6,8.6,127.6},
    {64,"LSTWRLD2",1,10,44100,67.6,8.1,67.6}, {65,"LSTWRLD3",1,11,44100,86.9,14.2,86.9},
    {66,"MAINTHEM",0,0,44100,272.7,nil,nil}, {67,"MSTCLN",2,1,44100,119.0,11.3,119.0},
    {68,"NIGHTS_A",-1,-1,32000,265.2,nil,nil}, {70,"NIGHTS_S",-1,-1,32000,335.9,nil,nil},
    {71,"ONE_UP",5,7,32000,6.3,nil,nil}, {72,"OPTION",4,1,44100,54.6,19.2,54.6},
    {73,"REDMNTN1",1,26,44100,87.5,18.0,87.5}, {74,"REDMNTN2",1,27,32000,281.3,8.5,281.2},
    {75,"RNDCLEAR",5,6,32000,7.6,nil,nil}, {76,"S_SQUARE",2,0,44100,95.4,4.7,95.4},
    {77,"SANDHILL",2,6,32000,104.2,21.1,104.1}, {78,"SCRAMBLE",2,4,32000,68.3,16.1,68.1},
    {79,"SHELTER1",1,14,44100,121.9,33.5,121.9}, {80,"SHELTER2",1,15,44100,97.8,17.9,97.8},
    {81,"SKYDECK1",1,12,44100,96.8,3.2,96.8}, {82,"SKYDECK2",1,13,32000,86.8,7.5,86.6},
    {83,"SONIC",0,1,44100,267.2,nil,nil}, {84,"SONIC_CD",-1,-1,32000,181.2,1.7,181.1},
    {85,"SPEEDUP",5,4,32000,15.8,nil,nil}, {86,"SPRSONIC",0,8,44100,52.9,19.5,52.9},
    {87,"SSRACING",-1,-1,32000,176.0,nil,nil}, {88,"TAILS",0,2,44100,230.8,nil,nil},
    {89,"THEAMY",3,9,44100,95.7,0.4,95.7}, {90,"THEBIG",3,11,44100,64.4,5.9,64.4},
    {91,"THEE102",3,10,32000,80.5,24.4,80.5}, {92,"THEKNKLS",3,8,44100,72.5,3.9,72.5},
    {93,"THEMILES",3,7,44100,44.6,3.0,44.6}, {94,"THESONIC",3,6,44100,55.2,11.8,55.2},
    {95,"TICAL",0,9,32000,117.3,54.1,117.3}, {96,"TIMER",5,9,32000,15.2,nil,nil}, {97,"TITL_EGG",5,14,32000,10.1,nil,nil},
    {98,"TITL_MR1",5,12,32000,8.2,nil,nil}, {99,"TITL_MR2",5,13,32000,9.2,nil,nil},
    {100,"TITL_SS",5,11,32000,6.0,nil,nil}, {101,"TITLE",4,0,44100,57.6,nil,nil}, {102,"TITLE2",-1,-1,44100,13.1,nil,nil},
    {103,"TRIAL",4,3,44100,53.9,3.4,53.9}, {104,"TWNKLPK1",1,23,32000,108.3,27.4,108.2},
    {105,"TWNKLPK2",1,24,44100,87.6,2.4,87.6}, {106,"TWNKLPK3",1,25,32000,50.3,4.7,50.2},
    {107,"WNDYVLY1",1,6,44100,89.8,2.5,89.8}, {108,"WNDYVLY2",1,7,32000,50.9,15.8,50.6},
    {109,"WNDYVLY3",1,8,44100,87.6,5.3,87.6},
}
local JINGLES = { [26] = true, [44] = true, [45] = true, [46] = true, [55] = true, [56] = true, [85] = true, [96] = true }

-- gsa1.MusicList()'s entries as the module gives them (bind_jukebox.cpp: loop points in seconds, without a loop 0 and
-- the length; made-up titles); frames = true: libsa1's unit (frames), which Normalize also takes
local function music_list(frames)
    local out = {}
    for _, r in ipairs(ROWS) do
        local m, f, p, e, rate, len, ls, le = r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]
        local k = frames and rate or 1
        out[#out + 1] = { music = m, file = f .. ".ADX", title = p >= 0 and ("Title " .. m) or nil, page = p, entry = e,
            seconds = len, loop = ls ~= nil, loop_start = (ls or 0) * k, loop_end = (le or len) * k, rate = rate,
            listed = p >= 0, jingle = JINGLES[m] or false, short = ls == nil and len < 25, truncated = m == 87 }
    end
    return out
end

-- the module's jukebox, recorded; it checks its arguments as bind_jukebox.cpp does (a call it would refuse counts as
-- JB.bad and returns false, usage)
local JB = { calls = {}, n = {}, loads = 2, audible = 0, refuse = nil, bad = {},
             ch = { music = -1, state = "idle", position = 0, length = 0, loops_done = 0, error = "" } }
local function int_in(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end
local function opt_in(v, lo, hi) return v == nil or (type(v) == "number" and v >= lo and v <= hi) end
local function refused(name, usage)
    JB.bad[#JB.bad + 1] = name
    return false, usage, "bad_argument"
end
local function fill(out, t)
    out = type(out) == "table" and out or {}
    for k, x in pairs(t) do out[k] = x end
    return out
end
local function rec(name, ...)
    JB.n[name] = (JB.n[name] or 0) + 1
    if name ~= "JukeboxUpdate" and name ~= "JukeboxState" then JB.calls[#JB.calls + 1] = { name, ... } end
    if name == "JukeboxUpdate" then JB.update = { ... } end
end
local function last(name)
    for i = #JB.calls, 1, -1 do
        if JB.calls[i][1] == name then return JB.calls[i] end
    end
end
local function n_of(name) return JB.n[name] or 0 end
local function add_jukebox(G)
    function G.MusicList()
        rec("MusicList")
        if JB.loads > 0 then
            JB.loads = JB.loads - 1
            return nil, "loading"
        end
        return music_list()
    end
    local PLANS = { forever = true, loops = true, once = true }
    function G.JukeboxPlay(ch, music, start, plan, loops, fi, fo)
        rec("JukeboxPlay", ch, music, start, plan, loops, fi, fo)
        if not (int_in(ch, 0, 4) and int_in(music, 0, 1000000) and opt_in(start, 0, 1e7) and (plan == nil or
            PLANS[plan]) and (loops == nil or int_in(loops, 1, 1000)) and opt_in(fi, 0, 60) and opt_in(fo, 0, 60)) then
            return refused("JukeboxPlay", "JukeboxPlay(channel 0..4, music, start >= 0, plan, loops 1..1000, fades 0..60)")
        end
        if JB.refuse then return false, JB.refuse, "not_found" end
        JB.ch = { music = music, state = "loading", position = start or 0, track_position = start or 0, length = 0,
                  loops_done = 0, error = "" }
        return true, "loading"
    end
    function G.JukeboxStop(ch, fade)
        rec("JukeboxStop", ch, fade)
        if not (int_in(ch, 0, 4) and opt_in(fade, 0, 60)) then return refused("JukeboxStop", "JukeboxStop(ch, fade)") end
        JB.ch.state = "idle"
        return true
    end
    function G.JukeboxPause(ch, p)
        rec("JukeboxPause", ch, p)
        if not (int_in(ch, 0, 4) and type(p) == "boolean") then return refused("JukeboxPause", "JukeboxPause(ch, b)") end
        return true
    end
    function G.JukeboxSeek(ch, t)
        rec("JukeboxSeek", ch, t)
        if not (int_in(ch, 0, 4) and type(t) == "number" and t >= 0) then return refused("JukeboxSeek", "(ch, t)") end
        JB.ch.position, JB.ch.track_position = t, t
        return true
    end
    function G.JukeboxSync(ch, t) rec("JukeboxSync", ch, t) return true end
    function G.JukeboxVolume(ch, v)
        rec("JukeboxVolume", ch, v)
        if not (int_in(ch, 0, 4) and type(v) == "number" and v >= 0 and v <= 1) then
            return refused("JukeboxVolume", "JukeboxVolume(ch, 0..1)")
        end
        return true
    end
    function G.JukeboxPlace(ch, pos, r) rec("JukeboxPlace", ch, pos, r) return true end
    function G.JukeboxUpdate(eye, fwd, up, gv, mv, paused)
        rec("JukeboxUpdate", eye, fwd, up, gv, mv, paused)
        if type(eye) ~= "table" or type(fwd) ~= "table" or type(up) ~= "table" or type(gv) ~= "number" or
            type(mv) ~= "number" or type(paused) ~= "boolean" then
            JB.bad[#JB.bad + 1] = "JukeboxUpdate"
        end
        return JB.audible
    end
    function G.JukeboxState(ch, out)
        rec("JukeboxState", ch)
        local c = JB.ch
        return fill(out, { music = c.music, state = c.state, position = c.position,
            track_position = c.track_position or c.position, length = c.length, loops_done = c.loops_done,
            error = c.error, plan_length = 0, paused = false, placed = false, volume = 1, queued = 3 })
    end
    function G.JukeboxStatus(out)
        return fill(out, { ready = true, tracks = #ROWS, active = JB.ch.state == "playing" and 1 or 0, memory_mb = 2.5,
            max_open_ms = 8, underruns = 0, error = "", started = true, failed = false, listed = 104, titles = true,
            recoveries = 0, opens = 3, list_ms = 850, backend = "mock" })
    end
    function G.AudioDuck(g, dj)
        rec("AudioDuck", g, dj)
        if not (type(g) == "number" and g >= 0 and g <= 1 and (dj == nil or type(dj) == "boolean")) then
            return refused("AudioDuck", "AudioDuck(gain 0..1, duck_jingles boolean)")
        end
        return true
    end
    -- 0.9.1 (feature "musicstate", bind_musicstate.cpp): the game's music state in the mixer, set by the test (JB.ms)
    function G.AudioMusicState(out)
        JB.n.AudioMusicState = (JB.n.AudioMusicState or 0) + 1
        if out ~= nil and type(out) ~= "table" then JB.bad[#JB.bad + 1] = "AudioMusicState" end
        local m = JB.ms
        return fill(out, { jingle = m.jingle, left = m.left or 0, stopped = m.stopped or false, bgm = m.bgm or -1,
            kind = m.kind or 0, waiting = false, loops = false, length = m.length or 0, time = 0, started = m.started or 0,
            ended = m.ended or 0, last_jingle = m.last_jingle or -1, last_end = m.last_end or 0, bgm_playing = false,
            name = m.name or "" })
    end
    function G.AudioMusicEnd()
        rec("AudioMusicEnd")
        JB.ms = { jingle = -1, last_end = 6 }
        return true
    end
end
JB.ms = { jingle = -1 }
local function frames(n, dt)
    for _ = 1, n do M.frame(dt or 1 / 60) end
end
local function console_has(text)
    for i = #M.console, 1, -1 do
        if string.find(M.console[i], text, 1, true) then return true end
    end
    return false
end

-- 1. loading -----------------------------------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ features = { jukebox = 1 } })
add_jukebox(G)
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local J, P = GSA1 and GSA1.Jukebox, GSA1 and GSA1.JukeboxPlayer
check(ok_load and #ferr == 0 and J ~= nil and P ~= nil, "the autorun loads sh_jukebox.lua and cl_jukebox.lua (%s)",
    ok_load and table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_load or ferr[1]))
if not (ok_load and J and P) then return done() end
local WANT = { gsa1_jukebox_mode = { "0", 0, 2 }, gsa1_jukebox_loops = { "2", 1, 10 }, gsa1_jukebox_fade = { "4", 0, 10 },
    gsa1_jukebox_jingles = { "0", 0, 1 }, gsa1_jukebox_hidden = { "1", 0, 1 }, gsa1_jukebox_volume = { "1", 0, 1 },
    gsa1_jukebox_duck = { "1", 0, 1 }, gsa1_jukebox_duck_jingles = { "0", 0, 1 }, gsa1_jukebox_gmod_music = { "1", 0, 1 },
    gsa1_jukebox_background = { "0", 0, 1 }, gsa1_jukebox_group = { "0", 0, 7 }, gsa1_jukebox_jingle = { "2", 0, 2 } }
local bad = {}
for name, w in pairs(WANT) do
    local c = M.convars[name]
    if not (c and c.client and c.save and c.v == w[1] and c.lo == w[2] and c.hi == w[3] and GSA1.CONVARS[name]) then
        bad[#bad + 1] = name
    end
end
check(#bad == 0, "12 client settings with the plan's defaults and ranges (mode repeat, loops 2, fade 4, jingles 0, the "
    .. "unlisted tracks shown, volume 1, duck 1 sparing the jingles, snd_musicvolume 1, background 0, group all, the "
    .. "game's jingles: pause)%s",
    #bad > 0 and (": wrong " .. table.concat(bad, " ")) or "")

-- 2. the pure functions ----------------------------------------------------------------------------------------------
local tracks, by = J.Normalize(music_list())
local listed, short, groups = 0, 0, { 0, 0, 0, 0, 0, 0, 0 }
for _, t in ipairs(tracks) do
    if t.listed then listed = listed + 1 end
    if t.short then short = short + 1 end
    groups[t.group] = groups[t.group] + 1
end
check(#tracks == 109 and by[69] == nil and listed == 104 and short == 15 and table.concat(groups, " ") ==
    "11 40 11 12 10 20 5", "Normalize: %d tracks (69 absent), %d in the sound test, %d short; groups %s", #tracks, listed,
    short, table.concat(groups, " "))
check(tracks[1].music == 66 and tracks[1].page == 0 and tracks[1].entry == 0 and tracks[105].music == 68 and
    tracks[109].music == 102 and tracks[105].group == 7 and tracks[105].name == "NIGHTS_A.ADX" and
    by[28].label == "Title 28 (ECOAST1.ADX)", "the sound test's order (page, entry), the unlisted ones after it by "
    .. "number under their file names: first %d, 105th %d, last %d", tracks[1].music, tracks[105].music,
    tracks[109].music)
local ec = by[28]
local _, byf = J.Normalize(music_list(true))
check(ec.loop and near(ec.loop_start, 42.8, 1e-4) and near(ec.loop_end, 112.1, 1e-4) and by[87].truncated and
    by[96].jingle and by[96].short and not by[45].short and not by[66].loop and by[66].loop_start == nil and
    near(byf[28].loop_start, 42.8, 1e-4) and near(byf[28].loop_end, 112.1, 1e-4),
    "loop points in seconds (ECOAST1 %.2f - %.2f), also when given in frames (libsa1's unit); flags kept",
    ec.loop_start, ec.loop_end)
local alt = J.Normalize({ { music = 5, file = "A.ADX", seconds = 60, loop = 1, loop_start = 10, loop_end = 60,
    rate = 44100, page = 1, entry = 0, listed = true, title = "x" }, { music = 6, file = "B.ADX", seconds = 10, loop = 0,
    rate = 32000, page = 6, entry = 2, listed = true, title = "y" }, { music = 7 }, "junk", { music = 5, file = "dup" },
    { music = 69, file = "C.ADX", on_disc = false } })
check(#alt == 3 and alt[1].music == 5 and alt[1].page == 0 and alt[1].loop_start == 10 and alt[1].loop_end == 60 and
    alt[2].music == 6 and alt[2].group == 6 and alt[2].short and not alt[2].loop and alt[3].file == "MUSIC7" and
    alt[3].group == 7, "Normalize is tolerant: loop points in seconds kept, pages 1..6 moved to 0..5, a missing file "
    .. "name, junk, a repeated number and a file not on the disc")
local all = J.Visible(tracks, 0, true)
check(#all == 109 and #J.Visible(tracks, 0, false) == 104 and #J.Visible(tracks, 7, false) == 5 and
    #J.Visible(tracks, 2, true) == 40 and #J.Playlist(all, false) == 94 and #J.Playlist(all, true) == 109,
    "Visible / Playlist: all 109 (104 without the unlisted ones; their own group shows its 5 anyway), action stages 40; "
    .. "the list and shuffle play 94 (109 with the jingles and title cards)")
local notitles = {}
for i, e in ipairs(music_list()) do
    e.title, e.page, e.entry, e.listed = nil, -1, -1, false
    notitles[i] = e
end
check(#J.Visible(J.Normalize(notitles), 0, false) == 109, "a disc without the supported sound test (no titles): every "
    .. "track is shown anyway")
local p6 = J.Visible(tracks, 6, true)
local playable = function(t) return J.Playable(t, false) end
local s1, s2, s3 = J.Step(p6, 45, 1, playable), J.Step(p6, 61, 1, playable), J.Step(p6, 51, -1, playable)
local s4, s5 = J.Step(p6, 999, 1, playable), J.Step(p6, 999, -1, playable)
local s6 = J.Step(p6, 45, 1)
check(s1.music == 26 and s2.music == 51 and s3.music == 61 and s4.music == 51 and s5.music == 61 and s6.music == 44 and
    J.Step({}, 1, 1) == nil and J.Step({ ec }, 28, 1) == ec, "Step: after 45 the next playable is %d (the 8 short ones "
    .. "skipped; %d with them), wraps %d -> %d and back, from outside the list %d / %d", s1.music, s6.music, 61,
    s2.music, s4.music, s5.music)
local seed = 12345
local function rand(n)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % n + 1
end
local sh = J.Shuffle(J.Playlist(all, false), rand)
local sorted = {}
for i, t in ipairs(sh) do sorted[i] = t.music end
table.sort(sorted)
local pl = {}
for i, t in ipairs(J.Playlist(all, false)) do pl[i] = t.music end
table.sort(pl)
check(table.concat(sorted, ",") == table.concat(pl, ","), "Shuffle is a permutation of the list")
local list94 = J.Playlist(all, false)
local state, cur, seen1, seen2, twice, in_row = {}, 28, {}, {}, 0, 0
for i = 1, 93 + 94 do
    local t = J.ShuffleNext(state, list94, "all", cur, rand)
    if t.music == cur then in_row = in_row + 1 end
    local seen = i <= 93 and seen1 or seen2
    if seen[t.music] then twice = twice + 1 end
    seen[t.music] = true
    cur = t.music
end
local n1, n2 = 0, 0
for _ in pairs(seen1) do n1 = n1 + 1 end
for _ in pairs(seen2) do n2 = n2 + 1 end
check(n1 == 93 and not seen1[28] and n2 == 94 and twice == 0 and in_row == 0, "ShuffleNext: the first round plays the "
    .. "93 others once (not the playing one), the next all 94 once, never the same track twice in a row (%d / %d / %d "
    .. "/ %d)", n1, n2, twice, in_row)
local pf1 = J.PlanFor(ec, 0, 2)
local pf2, pl2 = J.PlanFor(ec, 1, 3)
local pf3 = J.PlanFor(by[66], 2, 2)
check(pf1 == "forever" and pf2 == "loops" and pl2 == 3 and pf3 == "once" and select(2, J.PlanFor(ec, 1, 99)) == 10,
    "PlanFor: repeat -> forever; list / shuffle -> loops n for a looping track, once for one without a loop")
check(near(J.PlanLength(ec, "loops", 2, 4), 42.8 + 2 * 69.3 + 4, 1e-4) and J.PlanLength(ec, "forever") == nil and
    near(J.PlanLength(by[66], "once"), 272.7), "PlanLength: intro + n loops + fade; forever none; once the file")
check(near(J.TrackTime(ec, "forever", 120), 42.8 + (120 - 42.8) % 69.3, 1e-4) and near(J.TrackTime(by[66], "forever",
    300), 300 - 272.7, 1e-4) and near(J.TrackTime(by[66], "once", 300), 272.7) and J.TrackTime(ec, "loops", 50) == 50 and
    J.LoopsDone(ec, 120) == 1 and J.LoopsDone(ec, 100) == 0, "TrackTime / LoopsDone: a loop wraps at the game's loop "
    .. "point, repeat of a track without a loop starts again, once stops at the end")
check(J.FormatTime(0) == "0:00" and J.FormatTime(112.1) == "1:52" and J.FormatTime(59.99) == "0:59" and
    J.FormatTime(3725) == "1:02:05" and J.FormatTime(-3) == "0:00", "FormatTime: %s %s %s %s", J.FormatTime(0),
    J.FormatTime(112.1), J.FormatTime(59.99), J.FormatTime(3725))
local f1, c1 = J.Find(tracks, "28")
local f2 = J.Find(tracks, " ecoast1 ")
local f3 = J.Find(tracks, "ECOAST1.ADX")
local f4, c4 = J.Find(tracks, "title 28")
local f5, c5 = J.Find(tracks, "jingle")
local f6, c6 = J.Find(tracks, "69")
local f7 = J.Find(tracks, "nosuch")
check(f1 == ec and c1 == 1 and f2 == ec and f3 == ec and f4 == ec and c4 == 1 and f5.music == 57 and c5 == 5 and
    f6 == nil and c6 == 0 and f7 == nil, "Find: by number, file (any case, with or without .ADX), words; 69 is not there")
check(string.find(J.Line(by[87]), "cut short", 1, true) and string.find(J.Describe(by[102]), "menu piece", 1, true) and
    string.find(J.Describe(by[66]), "starts it again", 1, true) and string.find(J.Describe(by[96]), "jingle", 1, true)
    and J.LoopText(ec) == "loops from 0:42", "the list lines and tooltips say what is special about a track")

-- 3. the player ------------------------------------------------------------------------------------------------------
frames(30)
check(n_of("MusicList") == 0 and n_of("JukeboxUpdate") == 0 and n_of("JukeboxState") == 0, "before the jukebox is "
    .. "used nothing runs (no module call in 30 frames)")
GSA1.LoadModule()
RunConsoleCommand("gsa1_jukebox_play", "28")
check(n_of("JukeboxPlay") == 0 and P.pending == "28" and console_has("plays when it is there"), "a play while the track "
    .. "list loads waits for it")
frames(60)
local c = last("JukeboxPlay")
local v = last("JukeboxVolume")
check(c and c[2] == 0 and c[3] == 28 and c[4] == 0 and c[5] == "forever" and c[7] == 0 and c[8] == 0 and v and v[3] == 1
    and P.current == 28 and console_has("playing 28 Title 28 (ECOAST1.ADX)"), "... and plays track 28 when it is "
    .. "there: JukeboxPlay(0, 28, 0, \"forever\", ...) after JukeboxVolume(0, 1)")
JB.ch.state, JB.ch.position, JB.ch.track_position = "playing", 12.5, 12.5
frames(30)
local now = P.NowLines()
check(now[1] == "Title 28 (ECOAST1.ADX)" and now[2] == "0:12 / 1:52, loops from 0:42" and
    string.find(now[3] or "", "^playing %- repeat") ~= nil, "now playing: %s | %s | %s", tostring(now[1]),
    tostring(now[2]), tostring(now[3]))
local u = JB.update
check(u and u[4] == 1 and u[5] == 1 and u[6] == false and n_of("JukeboxUpdate") >= 30, "JukeboxUpdate every frame: "
    .. "volume 1, music volume 1 (no snd_musicvolume), not paused")
M.ui = true
frames(2)
local p1 = JB.update[6]
M.convars.gsa1_jukebox_background:SetString("1")
frames(2)
local p2 = JB.update[6]
M.convars.gsa1_jukebox_background:SetString("0")
M.ui = false
M.focus = false
frames(2)
local p3 = JB.update[6]
M.focus = true
frames(2)
check(p1 == true and p2 == false and p3 == true and JB.update[6] == false, "paused with the escape menu (single "
    .. "player) and out of focus (snd_mute_losefocus), not with \"keep playing in the background\"")
M.cv("snd_musicvolume", "0.5")
frames(2)
local mv1 = JB.update[5]
M.convars.gsa1_jukebox_gmod_music:SetString("0")
frames(2)
local mv2 = JB.update[5]
M.convars.gsa1_jukebox_gmod_music:SetString("1")
check(mv1 == 0.5 and mv2 == 1, "Garry's Mod's music volume followed (%s), or not (%s)", tostring(mv1), tostring(mv2))
-- the duck
JB.audible = 1
frames(2)
local d1 = last("AudioDuck")
M.convars.gsa1_jukebox_duck_jingles:SetString("1")
frames(2)
local d2 = last("AudioDuck")
M.convars.gsa1_jukebox_duck_jingles:SetString("0")
frames(2)
local d3 = last("AudioDuck")
M.convars.gsa1_jukebox_duck:SetString("0")
frames(2)
local d4 = last("AudioDuck")
M.convars.gsa1_jukebox_duck:SetString("1")
frames(2)
check(d1 and d1[2] == 0 and d1[3] == false and d2[2] == 0 and d2[3] == true and d3[2] == 0 and d3[3] == false and
    d4[2] == 1 and last("AudioDuck")[2] == 0, "the game's music is silenced while the jukebox is heard, its jingles "
    .. "(the drowning countdown) only with the option; the option off brings it back")
M.convars.gsa1_jukebox_volume:SetString("0.5")
local vv = last("JukeboxVolume")
M.convars.gsa1_jukebox_volume:SetString("1")
check(vv[2] == 0 and vv[3] == 0.5, "the volume setting goes to the module at once")
RunConsoleCommand("gsa1_jukebox_pause")
local pa1 = last("JukeboxPause")
local paused_line = P.NowLines()[3] or ""
RunConsoleCommand("gsa1_jukebox_pause")
local pa2 = last("JukeboxPause")
check(pa1[3] == true and pa2[3] == false and string.find(paused_line, "^paused") ~= nil and not P.paused,
    "gsa1_jukebox_pause pauses and resumes (\"%s\")", paused_line)
-- the play mode changes the playing track's plan where it is in the file
JB.ch.position, JB.ch.track_position = 120, 42.8 + (120 - 42.8) % 69.3
frames(20)
local live_state = P.state
P.state = { music = 28, state = "playing", position = 120 }       -- an engine without track_position
local folded = P.TrackPosition()
P.state = live_state
check(near(folded, 42.8 + (120 - 42.8) % 69.3, 1e-4) and near(P.TrackPosition(), 42.8 + (120 - 42.8) % 69.3, 1e-4),
    "the position in the file: the engine's track_position, or the plan time folded at the loop (%.2f s)", folded)
RunConsoleCommand("gsa1_jukebox_mode", "1")
c = last("JukeboxPlay")
check(c[3] == 28 and c[5] == "loops" and c[6] == 2 and near(c[4], 42.8 + (120 - 42.8) % 69.3, 1e-3) and c[8] == 4 and
    P.plan == "loops", "play the list: the playing track gets the plan \"loops 2\" with a 4 s fade-out, from where it "
    .. "is in the file (%.2f s)", c[4])
-- the end of a track: the next one of the list
JB.ch.state = "ended"
frames(40)
c = last("JukeboxPlay")
check(c[3] == 29 and c[5] == "loops", "at the end of 28 the list goes on with %s (\"%s\")", tostring(c[3]),
    tostring(c[5]))
P.Play(45)
JB.ch.state = "ended"
frames(40)
c = last("JukeboxPlay")
local after45 = c[3]
local plan45 = c[5]
M.convars.gsa1_jukebox_jingles:SetString("1")
P.Play(45)
JB.ch.state = "ended"
frames(40)
c = last("JukeboxPlay")
M.convars.gsa1_jukebox_jingles:SetString("0")
check(after45 == 26 and plan45 == "once" and c[3] == 44 and c[5] == "once", "the list skips the jingles and title "
    .. "cards (45 -> %s, played once), unless they are included (45 -> %s)", tostring(after45), tostring(c[3]))
-- shuffle: every track of the group once
M.convars.gsa1_jukebox_group:SetString("2")
M.convars.gsa1_jukebox_mode:SetString("2")
P.rand = rand
P.Play(29)
local got, dup, other = {}, 0, 0
for _ = 1, 39 do
    JB.ch.state = "ended"
    frames(40)
    local m = last("JukeboxPlay")[3]
    if got[m] or m == 29 then dup = dup + 1 end
    if by[m].group ~= 2 then other = other + 1 end
    got[m] = true
end
check(dup == 0 and other == 0, "shuffle in the action stages: 39 ends play the 39 other tracks of the group once each "
    .. "(%d repeated, %d from elsewhere)", dup, other)
-- Previous in shuffle goes back in the history; later than 3 s it starts the track again
local hist = P.history[#P.history - 1]
P.Previous()
local back = last("JukeboxPlay")[3]
JB.ch.state, JB.ch.position = "playing", 10
frames(40)
local seeks = n_of("JukeboxSeek")
P.Previous()
local sk = last("JukeboxSeek")
check(back == hist and n_of("JukeboxSeek") == seeks + 1 and sk[3] == 0, "Previous: the track played before (%s), and "
    .. "10 s into a track it starts again", tostring(back))
M.convars.gsa1_jukebox_mode:SetString("1")
M.convars.gsa1_jukebox_group:SetString("0")
P.Play(29)
P.Previous()
check(last("JukeboxPlay")[3] == 28, "Previous in the list: the track before (28)")
-- failures: the list goes on, repeat stops with the message
JB.ch.state, JB.ch.error = "failed", "a read error"
frames(40)
local fl = last("JukeboxPlay")[3]
local shown = P.lastError
M.convars.gsa1_jukebox_mode:SetString("0")
P.Play(28)
JB.ch.state, JB.ch.error = "failed", "a read error"
frames(40)
check(fl == 29 and shown == "ECOAST1.ADX: a read error" and P.current == nil and
    P.NowLines()[1] == "Not playing: ECOAST1.ADX: a read error", "a failed track: the list goes on with the next (%s), "
    .. "repeat stops and says why", tostring(fl))
JB.refuse = "bad arguments"
local okr, why = P.Play(28)
JB.refuse = nil
check(okr == false and why == "bad arguments", "a play the module refuses returns its message")
M.convars.gsa1_jukebox_mode:SetString("1")
P.Play(28)
JB.refuse = "the disc is gone"
JB.ch.state = "ended"
local plays = n_of("JukeboxPlay")
frames(90)
JB.refuse = nil
check(n_of("JukeboxPlay") == plays + 1 and P.current == nil and P.lastError == "the disc is gone", "a next track the "
    .. "module refuses: the list stops with the message instead of asking again every quarter second (%d tries)",
    n_of("JukeboxPlay") - plays)
M.convars.gsa1_jukebox_mode:SetString("0")
RunConsoleCommand("gsa1_jukebox_play", "ecoast2")
check(last("JukeboxPlay")[3] == 29 and P.current == 29, "gsa1_jukebox_play <file>")
RunConsoleCommand("gsa1_jukebox_play", "jingle")
check(last("JukeboxPlay")[3] == 57 and console_has("(5 tracks match; the first one plays)"), "gsa1_jukebox_play <words>")
RunConsoleCommand("gsa1_jukebox_play", "nosuch")
check(console_has("no track matches \"nosuch\"") and P.current == 57, "gsa1_jukebox_play with no match says so")
RunConsoleCommand("gsa1_jukebox_next")
check(last("JukeboxPlay")[3] == 58, "gsa1_jukebox_next")
RunConsoleCommand("gsa1_jukebox_prev")
check(last("JukeboxPlay")[3] == 57, "gsa1_jukebox_prev")
M.console = {}
RunConsoleCommand("gsa1_jukebox_list", "")
local listed_lines = 0
for _, l in ipairs(M.console) do
    if string.find(l, "^%[G%-SA1%]   +%d+  ") then listed_lines = listed_lines + 1 end
end
local has_groups = console_has("Sound test 2: action stages and bosses") and console_has("Not in the sound test")
RunConsoleCommand("gsa1_jukebox_list", "jingle")
check(listed_lines == 109 and has_groups and console_has("jukebox: 109 of 109 tracks") and
    console_has("jukebox: 5 of 109 tracks"), "gsa1_jukebox_list prints the %d tracks by group (and with words, the "
    .. "matching ones)", listed_lines)
-- the game's jingles (0.9.1: gsa1_070_drown.md J1, rules R1-R5, with its review R4.4) ----------------------------------
-- JB.ms is the game's music state in the mixer (gsa1.AudioMusicState); H the frames' JukeboxUpdate pause and volume
JB.ch.state = "playing"
M.convars.gsa1_jukebox_gmod_music:SetString("0")        -- music volume 1 (snd_musicvolume is 0.5 from above)
local H = {}
local function hold_frames(n, dt)
    for _ = 1, n do
        M.frame(dt or 1 / 60)
        H[#H + 1] = { JB.update[6], JB.update[5] }
    end
end
local pauses_before = n_of("JukeboxPause")
JB.ms = { jingle = -1 }
hold_frames(5)
check(P.current == 57 and JB.update[6] == false and near(JB.update[5], 1), "no jingle: the jukebox plays (not held, "
    .. "music volume 1)")
JB.ms = { jingle = 96, kind = 2, name = "TIMER.ADX", left = 15.2, started = 1 }
H = {}
hold_frames(6)
local mid = H[6] and H[6][2]
local mid_paused = H[6] and H[6][1]
hold_frames(8)
check(near(mid, 0.5, 0.06) and mid_paused == false and JB.update[6] == true and near(JB.update[5], 0),
    "the drowning countdown (jingle 96): the jukebox fades out in 0.2 s (volume %.2f after 0.1 s) and then pauses",
    tonumber(mid) or -1)
hold_frames(60)
check(JB.update[6] == true and P.current == 57 and n_of("JukeboxPause") == pauses_before and not P.paused and
    last("AudioDuck")[2] == 0, "held while the jingle plays: the track kept, the user's pause untouched, the game's own "
    .. "music still silenced")
JB.ms = { jingle = -1, last_jingle = 96, last_end = 2, started = 1, ended = 1 }
H = {}
hold_frames(15)
local first_paused, at_quarter = H[1][1], H[15][2]
hold_frames(20)
check(first_paused == false and near(at_quarter, 0.5, 0.06) and JB.update[6] == false and near(JB.update[5], 1),
    "the jingle over (the countdown cancelled): playing again at once, faded in over 0.5 s (%.2f after 0.25 s)",
    at_quarter)
-- the 1-up is a sound effect (tone 704): the music state does not change, nothing holds
H = {}
hold_frames(30)
local held_1up = false
for _, h in ipairs(H) do held_1up = held_1up or h[1] or h[2] < 0.999 end
check(not held_1up, "the 1-up (a sound, not a jingle) leaves the jukebox playing")
M.convars.gsa1_jukebox_jingle:SetString("1")
JB.ms = { jingle = 55, kind = 3, name = "INVNCIBL.ADX", left = 23.5, started = 2, ended = 1 }
H = {}
hold_frames(30)
local lowered_paused = false
for _, h in ipairs(H) do lowered_paused = lowered_paused or h[1] end
check(not lowered_paused and near(JB.update[5], 0.25), "\"lower\": invincibility (55) lowers the jukebox to 25 %% (%.2f) "
    .. "and never pauses it", JB.update[5])
JB.ms = { jingle = -1, last_jingle = 55, last_end = 1, started = 2, ended = 2 }
hold_frames(40)
M.convars.gsa1_jukebox_jingle:SetString("0")
JB.ms = { jingle = 85, kind = 4, name = "SPEEDUP.ADX", left = 15.8, started = 3, ended = 2 }
H = {}
hold_frames(30)
local keep_touched = false
for _, h in ipairs(H) do keep_touched = keep_touched or h[1] or h[2] < 0.999 end
check(not keep_touched, "\"keep playing\": the speed shoes (85) leave the jukebox alone")
JB.ms = { jingle = -1, last_jingle = 85, last_end = 2, started = 3, ended = 3 }
M.convars.gsa1_jukebox_jingle:SetString("2")
hold_frames(40)
-- the drown (review R4.4): JINGLE 96, MUSIC_STOP, RESTART, then the game's music back one frame later - held until the
-- character has respawned
JB.ms = { jingle = 96, kind = 2, name = "TIMER.ADX", left = 15.2, started = 4, ended = 3 }
hold_frames(30)
JB.ms = { jingle = -1, stopped = true, last_jingle = 96, last_end = 3, started = 4, ended = 4 }
hold_frames(60)
local held_stop = JB.update[6]
hook.Run("GSA1CharacterRestart", { title = "Sonic" }, 2)
hold_frames(1)
JB.ms = { jingle = -1, stopped = false, last_jingle = 96, last_end = 3, started = 4, ended = 4 }
hold_frames(60)
local held_restart = JB.update[6]
hook.Run("GSA1CharacterRespawned", { title = "Sonic" }, "drowned")
hold_frames(40)
check(held_stop == true and held_restart == true and JB.update[6] == false and near(JB.update[5], 1), "the drown: "
    .. "held through the countdown, the music stop, the restart request and the game's music coming back a frame later, "
    .. "until the character has respawned; then it fades back in")
hook.Run("GSA1CharacterRestart", { title = "Sonic" }, 2)
hold_frames(60)
local held_alone = JB.update[6]
for _ = 1, 16 do hold_frames(60) end
check(held_alone == true and JB.update[6] == false, "a restart request whose respawn never comes holds the jukebox for "
    .. "15 s at most")
hook.Run("GSA1CharacterRestart", { title = "Sonic" }, 2)
hold_frames(30)
local held_rm = JB.update[6]
hook.Run("GSA1CharacterRemoved", { title = "Sonic" }, false)
hold_frames(40)
check(held_rm == true and JB.update[6] == false, "the character removed during the hold: the jukebox carries on")
local status_lines = table.concat(P.StatusLines(), " | ")
check(string.find(status_lines, "the game's jingles: none playing", 1, true) ~= nil, "the status lines say what the "
    .. "jingle rule is doing (%s)", status_lines)
M.convars.gsa1_jukebox_gmod_music:SetString("1")
-- stop: the game's music comes back, the per-frame calls end
RunConsoleCommand("gsa1_jukebox_stop")
local st = last("JukeboxStop")
JB.audible = 0
frames(10)
local d5 = last("AudioDuck")
frames(150)
local u1 = n_of("JukeboxUpdate")
frames(30)
check(st[2] == 0 and near(st[3], 0.3) and d5[2] == 1 and n_of("JukeboxUpdate") == u1 and P.current == nil,
    "gsa1_jukebox_stop: stopped with a short fade, the game's music back, and no more calls once quiet")

-- 4. the page -------------------------------------------------------------------------------------------------------
-- stand-ins for Derma: every call recorded; a few getters answer like the real panels
local made = {}
local METHODS
local function standin(kind)
    local S = { kind = kind, calls = {} }
    made[#made + 1] = S
    return setmetatable(S, { __index = function(t, k)
        if METHODS[k] then return METHODS[k] end
        if type(k) ~= "string" or not string.match(k, "^%u") then return nil end    -- a field: nil, as on a panel
        return function(self, ...)
            t.calls[#t.calls + 1] = { k, ... }
            return standin(k)
        end
    end })
end
METHODS = {
    IsEditing = function(self) return self.editing or false end,
    GetValue = function(self) return self.value or 0 end,
    SetValue = function(self, x) self.value = x end,
    GetParent = function() return nil end,
    SetText = function(self, s) self.text = s end,
    AddLine = function(self, ...)
        local l = standin("line")
        l.cols = { ... }
        self.lines = self.lines or {}
        self.lines[#self.lines + 1] = l
        return l
    end,
    Clear = function(self) self.lines = {} end,
    SetColumnText = function(self, i, s) self.cols[i] = s end,
}
vgui.Create = function(cls) return standin(cls) end
local function run_thinks(times)
    for _ = 1, times or 1 do
        M.T = M.T + 0.6
        for _, S in ipairs(made) do
            local th = rawget(S, "Think")
            if th then th(S) end
        end
    end
end
M.menu = {}
M.run_hook("PopulateToolMenu")
local entry
for _, e in ipairs(M.menu) do
    if e.class == "gsa1_feat_jukebox" then entry = e end
end
check(entry and entry.name == "Jukebox" and entry.tab == "Options" and entry.category == "G-SA1",
    "the page Options -> G-SA1 -> Jukebox")
if not entry then return done() end
local panel = standin("DForm")
entry.cpanel(panel)
local bound, combos, text = {}, {}, {}
for _, call in ipairs(panel.calls) do
    if (call[1] == "CheckBox" or call[1] == "NumSlider") and call[3] then bound[call[3]] = true end
    if call[1] == "Help" or call[1] == "ControlHelp" then text[#text + 1] = tostring(call[2]) end
end
for _, S in ipairs(made) do
    if S.kind == "ComboBox" and rawget(S, "OnSelect") then combos[#combos + 1] = S end
end
for _, combo in ipairs(combos) do
    local before = {}
    for name in pairs(WANT) do before[name] = M.convars[name].v end
    combo.OnSelect(combo, 2, "x", "1")
    for name in pairs(WANT) do
        if M.convars[name].v ~= before[name] then
            bound[name] = true
            M.convars[name]:SetString(before[name])
        end
    end
end
local missing = {}
for name in pairs(WANT) do
    if not bound[name] then missing[#missing + 1] = name end
end
local page_text = table.concat(text, " ")
check(#missing == 0 and #combos == 3 and string.find(page_text, "could not be built", 1, true) == nil, "every "
    .. "gsa1_jukebox_* setting has a control on the page (check boxes, sliders, the group, play-mode and jingle boxes)%s",
    #missing > 0 and (": missing " .. table.concat(missing, " ")) or "")
local modebox
for _, S in ipairs(made) do
    if S.kind == "ComboBox" then
        for _, call in ipairs(S.calls) do
            if call[1] == "SetTooltip" and string.find(tostring(call[2]), "plays those once", 1, true) then modebox = S end
        end
    end
end
check(modebox ~= nil, "the play mode's tooltip says that the game's own sound test plays a track without a loop once")
run_thinks(3)
local list
for _, S in ipairs(made) do
    if S.kind == "DListView" then list = S end
end
local n_all = list and list.lines and #list.lines or 0
M.convars.gsa1_jukebox_hidden:SetString("0")
run_thinks(1)
local n_listed = list and #list.lines or 0
M.convars.gsa1_jukebox_group:SetString("7")
run_thinks(1)
local n_unlisted = list and #list.lines or 0
M.convars.gsa1_jukebox_group:SetString("0")
M.convars.gsa1_jukebox_hidden:SetString("1")
run_thinks(1)
check(n_all == 109 and n_listed == 104 and n_unlisted == 5, "the page's list: %d tracks, %d without the unlisted ones, "
    .. "%d in their own group", n_all, n_listed, n_unlisted)
local first = list and list.lines[1]
if first then list.DoDoubleClick(list, 1, first) end
run_thinks(1)
check(first and first.gsa1Music == 66 and last("JukeboxPlay")[3] == 66 and first.cols[2] == "> Title 66",
    "double-click plays the line's track and marks it (%s)", first and tostring(first.cols[2]) or "?")
local label_ok = false
for _, S in ipairs(made) do
    if S.kind == "Help" and S.text and string.find(S.text, "Title 66 (MAINTHEM.ADX)", 1, true) then label_ok = true end
end
check(label_ok, "the now-playing line follows the track")
local seek, stop
for _, S in ipairs(made) do
    if S.kind == "NumSlider" and rawget(S, "Think") and rawget(S, "OnValueChanged") then seek = S end
    if S.kind == "DButton" and S.text == "Stop" then stop = S end
end
if seek then
    seek.editing = true
    run_thinks(1)
    seek.editing, seek.value = false, 30
    run_thinks(1)
end
local sk2 = last("JukeboxSeek")
if stop then stop.DoClick(stop) end
check(seek and sk2 and sk2[3] == 30 and stop and last("JukeboxStop") ~= st, "the position slider seeks when it is let "
    .. "go; the Stop button stops")
-- the page without the module's feature
local saved = gsa1.FEATURES
gsa1.FEATURES = {}
local panel2 = standin("DForm")
entry.cpanel(panel2)
local t2 = {}
for _, call in ipairs(panel2.calls) do t2[#t2 + 1] = call[1] .. "(" .. tostring(call[2]) .. ")" end
M.console = {}
RunConsoleCommand("gsa1_jukebox_play", "28")
gsa1.FEATURES = saved
local t2s = table.concat(t2, " ")
check(string.find(t2s, "needs G-SA1 module 0.7.0 or newer (its jukebox part)", 1, true) ~= nil and
    not string.find(t2s, "CheckBox", 1, true) and console_has("the jukebox needs G-SA1 module 0.7.0 or newer"),
    "a module without the jukebox: the page and the commands say which module is needed")

-- 5. the session log and errors ----------------------------------------------------------------------------------------
GSA1.LogFlush()
local log = M.files["gsa1/log.txt"] or ""
check(string.find(log, "jukebox +play 28 ECOAST1%.ADX: forever") ~= nil and string.find(log, "jukebox +track list: 109 "
    .. "tracks") ~= nil and string.find(log, "Title ", 1, true) == nil, "the session log has the jukebox's numbers and "
    .. "file names, never a title")
check(string.find(log, "jukebox +paused for the game's jingle 96, the drowning countdown %(TIMER%.ADX%)") ~= nil and
    string.find(log, "jukebox +back after the game's jingle %(the game went back to its music%)") ~= nil and
    string.find(log, "jukebox +paused: the game stopped its music %(a drown%)") ~= nil and
    string.find(log, "jukebox +paused until the character respawns") ~= nil and
    string.find(log, "jukebox +lowered for the game's jingle 55") ~= nil, "the session log: the jukebox paused for the "
    .. "game's jingle 96 (the drowning countdown), lowered for 55, held for the music stop and the respawn, and back")
check(#M.reported == 0 and not string.find(log, " error +", 1, true), "no Lua error%s", #M.reported > 0 and
    (": " .. M.reported[1]) or "")
check(#JB.bad == 0, "every call takes arguments bind_jukebox.cpp accepts (loops 1..1000 for every plan, fades 0..60, "
    .. "a boolean pause, volume 0..1, Vectors and numbers for JukeboxUpdate)%s", #JB.bad > 0 and (": refused " ..
    table.concat(JB.bad, " ")) or "")
info("module calls: JukeboxPlay %d, JukeboxUpdate %d, JukeboxState %d, AudioDuck %d, MusicList %d", n_of("JukeboxPlay"),
    n_of("JukeboxUpdate"), n_of("JukeboxState"), n_of("AudioDuck"), n_of("MusicList"))

-- 6. the server: sh_jukebox.lua runs there too (pure functions, no module), cl_jukebox.lua is only sent
GSA1 = nil
M.included, M.cslua = {}, {}
local real_include = include
include = function(rel)
    M.included[#M.included + 1] = rel
    if rel == "gsa1/sh_config.lua" or rel == "gsa1/feat/sh_jukebox.lua" then M.load(rel) end   -- the rest needs a server
end
CLIENT, SERVER = false, true
local ok_sv, err_sv = pcall(M.load, "autorun/gsa1_autorun.lua")
include = real_include
CLIENT, SERVER = true, false
local inc, sent = table.concat(M.included, " "), table.concat(M.cslua, " ")
check(ok_sv and GSA1 and GSA1.Jukebox and GSA1.Jukebox.FormatTime(61) == "1:01" and GSA1.JukeboxPlayer == nil and
    #(GSA1.FeatureFileErrors or {}) == 0 and string.find(inc, "gsa1/feat/sh_jukebox.lua", 1, true) and
    not string.find(inc, "cl_jukebox", 1, true) and string.find(sent, "gsa1/feat/sh_jukebox.lua", 1, true) and
    string.find(sent, "gsa1/feat/cl_jukebox.lua", 1, true), "server: sh_jukebox.lua runs, both files are sent to the "
    .. "clients%s", ok_sv and "" or (": " .. tostring(err_sv)))
return done()
