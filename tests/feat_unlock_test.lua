-- feat_unlock_test.lua - round 0.9.9e, the addon's side of the owner's message (sadc docs/research/gsa1_rounds_plan.md 14.1bc): the "?" as an unlockable, the Adventure character select's ? slot, Dr. Eggman and
-- Tikal in every place a follower can be made, and the sun shadow's slider in the log. The whole addon through its autorun, tests/lua_mock.lua in Garry's Mod's own LuaJIT, a cookie table that outlives a reload of the
-- addon as cl.db outlives a map or a session.
--   lua_host tests/feat_unlock_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check = M.check
print("G-SA1 feat_unlock_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

local COMMAND = "iwonderwhotheseventhcharacteris"
local cookies = {}
cookie = { GetNumber = function(k, d) return tonumber(cookies[k]) or d end, Set = function(k, v) cookies[k] = v end, GetString = function(k, d) return cookies[k] or d end }

-- what the console knows: every command's help and completion, every ConVar's help
local helps, completes = {}, {}
local cc_add = concommand.Add
concommand.Add = function(name, fn, comp, help, flags)
    helps[name], completes[name] = help or "", comp
    return cc_add(name, fn, comp, help, flags)
end

-- the mock's timer.Create does nothing: this test runs them by hand
local timers = {}
timer.Create = function(name, d, n, fn) timers[name] = fn end
local function run_timers()
    local t = timers
    timers = {}
    for _, fn in pairs(t) do fn() end
end

local chats = {}
local chat_add = chat.AddText
chat.AddText = function(...)
    local parts = {}
    for _, a in ipairs({ ... }) do if type(a) == "string" then parts[#parts + 1] = a end end
    chats[#chats + 1] = table.concat(parts)
    return chat_add(...)
end
local function chats_have(text)
    for _, c in ipairs(chats) do if string.find(c, text, 1, true) then return true end end
    return false
end

local G = M.module({ speed = 300, features = { super = 5, jukebox = 1, emote = 3, follower = 2 } })
G.SUPER = G.SUPER or { KIND = 8, CREATE_QUESTION = 0x2000, ARCHIVE_QUESTION = 62, COPT_QUESTION_SPIN = 8, CREATE_WATER_FLOOR = 0x1000, NO_DRAIN = 1, KEEP_AT_ZERO = 2, START_RINGS = 50 }
local creates = {}
local create = G.Create
function G.Create(kind, pos, yaw, ups, rings, extras)
    creates[#creates + 1] = { kind = kind, extras = extras }
    return create(kind, pos, yaw, ups, rings, extras)
end
function G.SetCharOption() return true end
-- the follower feature, as far as the page and the spawn route need it (tests/feat_follower_test.lua has the rest)
local fcreates = {}
function G.FollowerKinds(out)
    out = out or {}
    for _, k in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7 }) do out[k] = true end
    return out
end
local nextId = 5000
function G.FollowerCreate(kind, pos, yaw, leader, opts)
    nextId = nextId + 1
    fcreates[#fcreates + 1] = kind
    return nextId
end
G.FOLLOWER = { MAX = 112, MAX_CHARACTERS = 128, OBJECTS_NONE = 0, OBJECTS_OWN = 1, DRAW_FULL = 1, DRAW_FAR = 2, DRAW_NONE = 3, RATE_MIN = 5, RATE_MAX = 30, RATE_DEFAULT = 15, POOL_MAX = 16, MODE = { PLACE = 0, RESPAWN = 2, NORMAL = 4, TAKEOVER = 5, PARKED = 6 } }
for _, n in ipairs({ "FollowerFeed", "FollowerSetLeader", "FollowerHold", "FollowerRespawn", "FollowerStand", "FollowerSpeed", "FollowerSpot", "FollowerHostFlags", "FollowerDraw" }) do G[n] = function() return true end end
function G.FollowerInfo(id, out) out = out or {} out.mode, out.held = 4, false return out end
function G.FollowerThreads(n) return n == 0 and 3 or n end
function G.FollowersTick(dt, yaw, co, ct, out) out = out or {} out.count = 0 return out end
function G.FollowersStats(out) out = out or {} out.followers, out.workers, out.ms_tick, out.ms_render, out.ms_join, out.frames = 0, 3, 0, 0, 0, 1 return out end

-- what Garry's Mod kept from 0.9.9d: the last character was the "?", the slot's two saved values
M.cv("gsa1_character", "question")
M.cv("gsa1_charselect_super", "question")
M.cv("gsa1_charselect_super_last", "supersonic_general")

local function load_addon()
    GSA1 = nil
    M.included = {}
    local ok, err = pcall(M.load, "autorun/gsa1_autorun.lua")
    local errs = GSA1 and GSA1.FeatureFileErrors or {}
    check(ok and #errs == 0, "the addon's client files load (%s)", tostring(err or errs[1] or "no error"))
    if not ok or #errs > 0 then return false end
    GSA1.LoadModule()
    GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
    GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
    return true
end
if not load_addon() then return done() end

local function pages()
    local made = {}
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    return made
end
-- every control of a page, by M.menu's builders on a recording panel
vgui.Create = function() return setmetatable({}, { __index = function() return function() end end }) end
local function panel_rec()
    local P = { calls = {} }
    setmetatable(P, { __index = function(t, k)
        return function(self, ...)
            local a = { k, ... }
            t.calls[#t.calls + 1] = a
            if k == "ComboBox" then
                local combo = { items = {} }
                combo.AddChoice = function(s, title, data) s.items[#s.items + 1] = { title, data } end
                a.combo = combo
                return combo
            end
            return setmetatable({}, { __index = function() return function() end end })
        end
    end })
    return P
end
local function page_text(P)
    local out = {}
    for _, c in ipairs(P.calls) do
        for i = 2, #c do if type(c[i]) == "string" then out[#out + 1] = c[i] end end
        if c.combo then for _, it in ipairs(c.combo.items) do out[#out + 1] = tostring(it[1]) .. "=" .. tostring(it[2]) end end
    end
    return table.concat(out, "\n")
end
local function character_page()
    pages()
    for _, e in ipairs(M.menu) do
        if e.class == "gsa1_character" then
            local P = panel_rec()
            local ok, err = pcall(e.cpanel, P)
            check(ok, "the Character page builds (%s)", tostring(err))
            return P
        end
    end
    check(false, "the Character page is on the menu")
    return panel_rec()
end
local function menubar()
    local opts = {}
    local menu = { AddOption = function(_, t) opts[t] = true return {} end, AddSpacer = function() end }
    M.run_hook("PopulateMenuBar", { AddOrGetMenu = function() return menu end })
    return opts, menu
end

-- ---- 1. locked ----------------------------------------------------------------------------------------------------------------------------------------------------------
check(GSA1.QuestionUnlocked and GSA1.QuestionUnlocked() == false, "U1 locked to begin with")
for _, nm in ipairs({ "question", "?", "qm", "question_mark", "questionmark", "QUESTION" }) do
    check(GSA1.CharacterByName(nm) == nil and GSA1.KindByName(nm) == nil, "U1 no name finds it while locked: %s", nm)
end
do
    local names = {}
    for _, c in ipairs(GSA1.ListedCharacters()) do names[#names + 1] = c.name end
    check(#names == 11 and not string.find(table.concat(names, " "), "question", 1, true), "U1 the list has the eleven others: %s", table.concat(names, " "))
    check(#GSA1.CHARACTERS == 12, "U1 the entry itself stays in the table (the seam for the unlocking)")
end
-- a saved "?" goes back to Sonic
check(GetConVar("gsa1_character"):GetString() == "sonic", "U2 gsa1_character saved as question falls back to sonic at load (%s)", GetConVar("gsa1_character"):GetString())
GSA1.LogFlush()
check(string.find(M.files["gsa1/log.txt"] or "", "the character saved was the ?, which is locked: Sonic", 1, true) ~= nil, "U2 ... with one log line")
do
    creates = {}
    GSA1.cv.character:SetString("question")
    check(GSA1.cv.character:GetString() == "sonic", "U2 typed into gsa1_character: it goes back at once, by the ConVar's change callback (%s)", GSA1.cv.character:GetString())
    M.convars.gsa1_character.v = "question"     -- (should the callback ever come late: the plain spawn asks too)
    M.frame(1 / 60)
    GSA1.Spawn()
    check(#creates == 1 and creates[1].kind == 0 and GSA1.Char and GSA1.Char.name == "sonic" and not GSA1.Char.question, "U2 typed into gsa1_character, then the plain spawn: Sonic (kind %s)", creates[1] and tostring(creates[1].kind) or "none")
    check(GetConVar("gsa1_character"):GetString() == "sonic", "U2 the ConVar goes back too")
    GSA1.Remove(true)
end
-- no spawn route
do
    local routes = {
        { "GSA1.Spawn", function() GSA1.Spawn("question") end },
        { "GSA1.Spawn ?", function() GSA1.Spawn("?") end },
        { "gsa1_spawn", function() RunConsoleCommand("gsa1_spawn", "question") end },
        { "gsa1_spawn qm", function() RunConsoleCommand("gsa1_spawn", "qm") end },
        { "gsa1_toggle", function() RunConsoleCommand("gsa1_toggle", "question_mark") end },
        { "gsa1_follower_spawn", function() RunConsoleCommand("gsa1_follower_spawn", "question") end },
    }
    for _, r in ipairs(routes) do
        creates, fcreates = {}, {}
        chats = {}
        r[2]()
        check(#creates == 0 and #fcreates == 0 and GSA1.Char == nil, "U3 %s makes nothing", r[1])
        check(chats_have("unknown character") and not chats_have("question,") and not chats_have(", question"), "U3 %s: the answer is the same as for any wrong name, and does not list it (%s)", r[1], tostring(chats[1]))
    end
end
-- no help, no menu
do
    local bad = {}
    for name, help in pairs(helps) do
        if string.find(string.lower(help), "question", 1, true) then bad[#bad + 1] = name end
        if name ~= COMMAND and string.find(help, COMMAND, 1, true) then bad[#bad + 1] = name end
    end
    check(#bad == 0, "U4 no command's help names it: %s", table.concat(bad, " "))
    check(helps[COMMAND] == "" and completes[COMMAND] == nil, "U4 the secret has no help text and no completion")
    local comp = completes.gsa1_spawn("gsa1_spawn", "")
    check(not string.find(table.concat(comp, " "), "question", 1, true) and #comp == 11, "U4 gsa1_spawn's completion has the eleven others")
    local cvs = {}
    for n, d in pairs(GSA1.CONVARS) do
        if string.find(n, "gsa1_question", 1, true) or string.find(n, "charselect_super", 1, true) then cvs[#cvs + 1] = n end
        if string.find(string.lower(tostring(d.help or "")), COMMAND, 1, true) then cvs[#cvs + 1] = n end
    end
    check(#cvs == 0, "U4 no ConVar of it exists before the unlocking: %s", table.concat(cvs, " "))
    check(M.convars.gsa1_question_rings == nil, "U4 gsa1_question_rings is not there")
    local P = character_page()
    local text = page_text(P)
    check(not string.find(text, "question=", 1, true) and not string.find(text, "?=", 1, true) and not string.find(text, "\nquestion", 1, true), "U4 the Character page's list and quick spawn do not have it")
    check(not string.find(text, "gsa1_question", 1, true), "U4 the page has no rows of its options")
    check(not string.find(text, 'the character "?"', 1, true), "U4 the texture's help does not name the character")
    check(not string.find(text, "The ? slot plays", 1, true), "U9 the slot's combo box is gone")
    local opts = menubar()
    check(opts["Sonic"] and opts["Tikal"] and not opts["?"], "U4 the menubar does not have it")
    local rd = host_read(root .. "/gsa1/feat/cl_follower.lua")
    check(string.find(rd, "and ? have no wheel", 1, true) == nil, "U4 the Followers page's text does not name it")
end
-- 0.9.9f (099e-verify): every page of the menu read while it is locked, not only the Character page: the Super Sonic page's whoosh help named it
do
    pages()
    local n, bad = 0, {}
    for _, e in ipairs(M.menu) do
        local P = panel_rec()
        local ok, err = pcall(e.cpanel, P)
        check(ok, "U4 the page %s builds (%s)", tostring(e.class), tostring(err))
        n = n + 1
        local text = page_text(P)
        for _, word in ipairs({ 'the character "?"', 'character \"?\"', "question mark", "gsa1_question", COMMAND, "? slot", "? is a", "The ? ", " the ?." }) do
            -- (Character Select's own "question mark on this screen" is the game's menu icon, on any disc: not the character)
            if string.find(text, word, 1, true) and not (word == "question mark" and string.find(text, "The question mark on this screen", 1, true)) then
                bad[#bad + 1] = tostring(e.class) .. ": " .. word
            end
        end
    end
    check(n >= 8, "U4 every page of the menu was read (%d)", n)
    check(#bad == 0, "U4 no page names the ? while it is locked: %s", table.concat(bad, "; "))
    local un_whoosh = host_read(root .. "/gsa1/feat/cl_super.lua")
    check(string.find(un_whoosh, 'GSA1.QuestionUnlocked() and " The character', 1, true) ~= nil, "U4 the whoosh help says it only once it is unlocked")
end
-- no list anywhere reads the table itself (only what must: the character's own lookups)
do
    local allowed = { ["gsa1/sh_config.lua"] = true, ["gsa1/feat/sh_wheel.lua"] = true }      -- (sh_wheel: nowheel keeps it out)
    local bad = {}
    for _, f in ipairs({ "gsa1/cl_menu.lua", "gsa1/cl_character.lua", "gsa1/feat/cl_charselect.lua", "gsa1/feat/cl_faces.lua", "gsa1/feat/cl_tools.lua", "gsa1/feat/cl_spawntab.lua", "gsa1/feat/cl_wheel.lua", "gsa1/feat/cl_mouthtest.lua", "gsa1/feat/cl_objview.lua" }) do
        local src = host_read(root .. "/" .. f) or ""
        if not allowed[f] and string.find(src, "ipairs(GSA1.CHARACTERS", 1, true) then bad[#bad + 1] = f end
    end
    check(#bad == 0, "U4 the lists use GSA1.ListedCharacters: %s", table.concat(bad, " "))
end
-- the README never says it
do
    local readme = host_read(root .. "/../../README.md")
    if readme then
        check(string.find(readme, COMMAND, 1, true) == nil, "U4 the README does not name the command")
    else
        M.info("U4 no README beside the addon (a scratch copy of the tree): not read")
    end
end

-- ---- 2. the ? slot, while it is locked ---------------------------------------------------------------------------------------------------------------------------------------
local S = GSA1.CharSelect
check(S.EntryOf(6) == "supersonic" and S.EntryName(6) == "supersonic", "U5 the ? slot plays Super Sonic (Vs. Perfect Chaos), locked (%s)", tostring(S.EntryName(6)))
check(S.SlotTitle(6) == "Super Sonic", "U5 its button says so (%s)", tostring(S.SlotTitle(6)))
check(S.SuperEntry == nil and S.SUPER_CHOICES == nil and S.MigrateSlot == nil and S.cv.super == nil and S.cv.super_last == nil, "U5 gsa1_charselect_super, its memory, its one-time move and its choices are gone")
check(GSA1.CONVARS.gsa1_charselect_super == nil and GSA1.CONVARS.gsa1_charselect_super_last == nil, "U5 neither is a ConVar of the addon any more")
check(cookies.gsa1_charselect_super_099 == nil, "U5 the old marker is not written")
M.convars.gsa1_charselect_super:SetString("question")
check(S.EntryName(6) == "supersonic", "U5 a saved value is ignored: question")
M.convars.gsa1_charselect_super:SetString("supersonic_general")
check(S.EntryName(6) == "supersonic", "U5 a saved value is ignored: supersonic_general")
do
    creates = {}
    local name = S.EntryName(6)
    GSA1.Spawn(name)
    check(GSA1.Char and GSA1.Char.name == "supersonic" and GSA1.Char.kind == 8 and not GSA1.Char.question and #creates == 1, "U5 the pick is the entry supersonic, kind 8, no \"?\"")
    local ex = creates[1] and creates[1].extras
    check(not (ex and bit.band(tonumber(ex.create_flags) or 0, 0x2000) ~= 0), "U5 ... with no CREATE_QUESTION")
    GSA1.Remove(true)
    GSA1.cv.character:SetString("sonic")
end

-- ---- 3. the followers: Dr. Eggman and Tikal ------------------------------------------------------------------------------------------------------------------------------------
local Fo = GSA1.Followers
check(Fo.KINDS[1] and Fo.KINDS[1].name == "eggman" and Fo.KINDS[4] and Fo.KINDS[4].name == "tikal", "U6 Fo.KINDS has both")
do
    local seen = {}
    for _, k in ipairs(Fo.KIND_ORDER) do seen[k] = true end
    check(seen[1] and seen[4] and #Fo.KIND_ORDER == 8, "U6 the order has both")
    check(Fo.SpawnerClass(1) == "gsa1_follower_eggman" and Fo.SpawnerClass(4) == "gsa1_follower_tikal", "U6 their spawner classes")
    local classes = table.concat(Fo.SpawnerClasses(), " ")
    check(string.find(classes, "gsa1_follower_eggman", 1, true) and string.find(classes, "gsa1_follower_tikal", 1, true), "U6 the spawn tab's group has both: %s", classes)
    local titles = {}
    for _, c in ipairs(Fo.KindChoices()) do titles[#titles + 1] = c[2] end
    local t = table.concat(titles, ", ")
    check(string.find(t, "Dr. Eggman", 1, true) and string.find(t, "Tikal", 1, true) and not string.find(t, "can't follow", 1, true), "U6 the page's combo has both, with no reason: %s", t)
    ENT = {}
    M.classes = M.classes or {}
    M.load("entities/gsa1_follower_spawner.lua")
    check(M.classes.gsa1_follower_eggman and M.classes.gsa1_follower_eggman.GSA1FollowerKind == 1 and M.classes.gsa1_follower_tikal and M.classes.gsa1_follower_tikal.GSA1FollowerKind == 4, "U6 the spawner entities exist with the right kinds")
    check(host_read(root .. "/../materials/entities/gsa1_follower_eggman.png") ~= nil and host_read(root .. "/../materials/entities/gsa1_follower_tikal.png") ~= nil, "U6 their spawn icons exist (G-SA1's own drawing)")
    local page = host_read(root .. "/gsa1/feat/cl_playable.lua")
    check(string.find(page, "cannot be followers", 1, true) == nil, "U6 the Character page no longer says they cannot be followers")
    local FP = panel_rec()
    local fok, ferr = pcall(Fo.BuildPage, FP)
    check(fok, "U6 the Followers page builds (%s)", tostring(ferr))
    check(string.find(page_text(FP), "they have no flight or glide", 1, true) ~= nil, "U6 the Followers page says what they do")
end
do
    GSA1.Spawn("sonic")
    M.frame(1 / 60)
    for _, nm in ipairs({ "eggman", "tikal" }) do
        fcreates = {}
        RunConsoleCommand("gsa1_follower_spawn", nm)
        check(#fcreates == 1 and fcreates[1] == Fo.KINDS[nm == "eggman" and 1 or 4] and false or (#fcreates == 1 and fcreates[1] == (nm == "eggman" and 1 or 4)), "U7 gsa1_follower_spawn %s makes kind %s", nm, tostring(fcreates[1]))
    end
    check(#Fo.list == 2 and Fo.list[1].def and Fo.list[1].def.nowheel and Fo.list[2].def and Fo.list[2].def.nowheel, "U7 two followers with their own entries, no wheel")
    fcreates = {}
    GetConVar("gsa1_follower_kind"):SetString("4")
    RunConsoleCommand("gsa1_follower_spawn")
    check(#fcreates == 1 and fcreates[1] == 4, "U7 the page's Spawn button with Tikal chosen: kind %s", tostring(fcreates[1]))
    GetConVar("gsa1_follower_kind"):SetString("2")
    Fo.RemoveAll("a test")
    GSA1.Remove(true)
    GSA1.cv.character:SetString("sonic")
end

-- ---- 4. the sun shadow's slider in the log -------------------------------------------------------------------------------------------------------------------------------------
do
    GetConVar("gsa1_sunshadow_dark"):SetString("30")
    GetConVar("gsa1_sunshadow_dark"):SetString("31")
    run_timers()
    GSA1.LogFlush()
    local lg = M.files["gsa1/log.txt"] or ""
    check(string.find(lg, "sun shadow darkness = 31", 1, true) ~= nil and string.find(lg, "sun shadow darkness = 30", 1, true) == nil, "U8 the slider's value is in the log, once, a second after its last tick")
    GetConVar("gsa1_sunshadow_dark"):SetString("0")
    run_timers()
end

-- ---- 5. the unlocking -----------------------------------------------------------------------------------------------------------------------------------------------------------
do
    local P0 = character_page()         -- the page exists already, as on a machine whose player opened it
    local opts0, menu0 = menubar()
    chats = {}
    RunConsoleCommand(COMMAND)
    check(GSA1.QuestionUnlocked() == true and tonumber(cookies.gsa1_question_unlocked) == 1, "U10 the command unlocks, and writes the cookie")
    check(chats_have("seventh character") and chats_have("?"), "U10 a small message in the chat: %s", tostring(chats[1]))
    check(GSA1.CharacterByName("question") ~= nil and GSA1.CharacterByName("?") ~= nil and select(1, GSA1.KindByName("qm")) == 8, "U10 the names find it now")
    local text = page_text(P0)
    check(string.find(text, "?=question", 1, true) ~= nil and string.find(text, "gsa1_question_rings", 1, true) ~= nil, "U10 the open page is built again with it and its rows")
    check(opts0["?"] == true, "U10 the menubar that was already filled has it")
    local names = {}
    for _, c in ipairs(GSA1.ListedCharacters()) do names[#names + 1] = c.name end
    check(#names == 12 and names[12] == "question", "U10 the list has it, last")
    check(M.convars.gsa1_question_rings ~= nil and M.convars.gsa1_question_spin ~= nil, "U10 its options exist now")
    creates = {}
    RunConsoleCommand("gsa1_spawn", "question")
    check(GSA1.Char and GSA1.Char.question == true and GSA1.Char.kind == 8 and #creates == 1, "U10 gsa1_spawn question makes it")
    local ex = creates[1] and creates[1].extras
    check(ex and bit.band(tonumber(ex.create_flags) or 0, 0x2000) ~= 0, "U10 with its own flag")
    check(GSA1.cv.character:GetString() == "question", "U10 gsa1_character keeps it, as any other")
    check(S.EntryName(6) == "supersonic", "U10 the ? slot still plays Super Sonic: unlocked too")
    chats = {}
    RunConsoleCommand(COMMAND)
    check(chats_have("already"), "U10 a second use only says so")
    GSA1.Remove(true)
end

-- ---- 6. for good: a new session (or a map change: the client's Lua starts again) ----------------------------------------------------------------------------------------------
do
    M.cmds[COMMAND] = nil
    M.convars.gsa1_question_rings, M.convars.gsa1_question_drain, M.convars.gsa1_question_water, M.convars.gsa1_question_spin = nil, nil, nil, nil
    if not load_addon() then return done() end
    check(GSA1.QuestionUnlocked() == true, "U11 a new session: still unlocked, from the cookie")
    check(M.convars.gsa1_question_rings ~= nil, "U11 its options exist at load")
    check(GSA1.cv.character:GetString() == "question", "U11 the saved \"?\" stays when it is unlocked")
    creates = {}
    GSA1.Spawn()
    check(GSA1.Char and GSA1.Char.question == true, "U11 the plain spawn gives it")
    GSA1.Remove(true)
    cookies.gsa1_question_unlocked = nil
    M.cv("gsa1_character", "?")
    GSA1.cv.character:SetString("?")
    if not load_addon() then return done() end
    check(GSA1.QuestionUnlocked() == false and GSA1.cv.character:GetString() == "sonic", "U11 with no cookie it is locked again, and an alias saved falls back too (%s)", GSA1.cv.character:GetString())
end

return done()
