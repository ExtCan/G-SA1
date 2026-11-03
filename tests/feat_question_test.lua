-- feat_question_test.lua - the "?", the addon's side (round 0.9.9; sadc docs/research/gsa1_099_plan.md 4.1 B10, 5.6, 5.9, 5.10, 6.5 with its review
-- R99.4; playable099.md 5.5-5.7, 7.4; small099.md 3.2 with the plan's C1, C4): feat/sh_question.lua, feat/cl_question.lua and EVERY ROW of the overlap
-- audit of playable099.md 5.7 and of review R99.4 by name, on the whole addon through its autorun, tests/lua_mock.lua in Garry's Mod's own LuaJIT and a
-- mock of the module's feature "super" with every call recorded: it shares nothing with either Super Sonic.
--   lua_host tests/feat_question_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_question_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- the mock module -----------------------------------------------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ speed = 300, features = { super = 5, jukebox = 1, emote = 3 } })
local R = { calls = {}, st = {}, extras = {}, ups = {}, texture = {}, opts = {} }
local function rec(name, ...) R.calls[#R.calls + 1] = { name, ... } end
local function calls_of(name, id)
    local out = {}
    for _, c in ipairs(R.calls) do
        if c[1] == name and (id == nil or c[2] == id) then out[#out + 1] = c end
    end
    return out
end
G.BUTTON_ACTION = 2
G.SUPER = { KIND = 8, ORDER_SUPER = 46, ORDER_NORMAL = 47, NO_DRAIN = 1, KEEP_AT_ZERO = 2, FAITHFUL_REVERT = 4, SEA_PLANE = 8, CREATE_SUPER = 0x400,
            CREATE_SUPER_CAPABLE = 0x800, CREATE_WATER_FLOOR = 0x1000, STATE_SUPER = 8, EQUIPMENT = 0x8000, START_RINGS = 50, DRAIN_STEPS = 60,
            MUSIC_THEME = 86, MUSIC_CHAOS_1 = 22, MUSIC_CHAOS_2 = 23, GENERAL = 0x10, START = 0x20, WATER_WHILE_SUPER = 0x40, START_NORMAL = 0x80,
            SUPOPT_SPEED = 1, SUPOPT_NO_AURA = 2, SUPOPT_VOICE = 3, SUPOPT_SUPER_EFFECTS = 4, SPEED_GAME = 0, SPEED_RUN = 1, SPEED_HALF = 2, SPEED_SONIC = 3,
            GOPT_IDLE_BY_FORM = 2, GOPT_AURA_ANIM = 3, AURA_DREAMCAST = 0, AURA_CALM = 1, AURA_SLOW = 2, VOICE_DEFAULT = 1116, SUPOPT_SUPER_ANIMS = 5,
            SUPOPT_LSD_GOLD = 6, SUPER_EFFECTS_CLONES = 1, SUPER_EFFECTS_DUST = 2, DRAW_SUPER_GOLD = 0x2000, TEXTURE_VARIANT_SUPER_GOLD = 1, WHOOSH_STAGE = 19,
            WHOOSH_SLOW = 1035, WHOOSH_FAST = 1036,
            -- 0.9.9 (feature "super" 5)
            CREATE_QUESTION = 0x2000, ARCHIVE_QUESTION = 62, COPT_QUESTION_SPIN = 8 }
G.WRAP_GOLD = 0x10
G.EMOTE = { LOOP = 0x100, IN_AIR = 4, KEEP_INPUT = 8, NO_PROPS = 0x10, NO_TRAIL = 2, HOLD = 0x20, SPEED_MIN = 1 / 64, SPEED_MAX = 16, STOP_NOW = 0, STOP_BLEND = 1 }
-- the disc's names of AVA_CHSEL(_E), in archive 62 of kind 8 only
local CHSEL = { [0] = "cs_ce_bd_1", "cs_ce_bd_2", "cs_ce_bd_3", "CS_CE_BU", "CS_CE_O", "CS_CE_OD", "CS_CE_OU", "CS_CE_TX", "cs_sinkou_e", "CS_TX_e", "sstx_body" }
local texture = G.Texture
function G.Texture(kind, index, archive, variant)
    rec("Texture", kind, index, archive)
    if kind == 8 and archive == 62 then
        if not CHSEL[index] then return nil, "no such texture" end
        local t = texture(kind, index, archive)
        t.name = CHSEL[index]
        return t
    end
    return texture(kind, index, archive)
end
function G.TextureArchives(kind)
    if kind == 8 then
        return { { name = "SUPERSONIC", count = 3 }, { name = "OBJ_REGULAR", count = 2 }, { name = "EFF_REGULAR", count = 2 }, { name = "CON_REGULAR", count = 2 },
                 { name = "SONIC", count = 3 }, { name = "SON_EFF", count = 2 } }
    end
    return { { name = "ARCHIVE0", count = 4 }, { name = "ARCHIVE1", count = 3 } }
end
local create = G.Create
function G.Create(kind, pos, yaw, ups, rings, extras)
    local id = create(kind, pos, yaw, ups, rings)
    R.extras[id], R.ups[id] = extras, ups
    rec("Create", id, kind, rings, extras, ups)
    local cf = type(extras) == "table" and tonumber(extras.create_flags) or 0
    local sf = type(extras) == "table" and tonumber(extras.super_flags) or 0
    local capable = kind == 8 or bit.band(cf, 0x800) ~= 0
    R.st[id] = { super = kind == 8, capable = capable, kind = kind, rings = kind == 8 and (extras and extras.start_rings or 50) or 0, equipment = 0, mode = 1, action = 0, speed = 0,
                 changes = 0, change_step = 0, step = 0, general = capable and kind == 0 and bit.band(sf, 0x10) ~= 0, start = bit.band(sf, 0x20) ~= 0 }
    return id
end
function G.SuperOrder(id, order) rec("SuperOrder", id, order) return true end
function G.SuperState(id, out)
    local s = R.st[id]
    if not s then return nil end
    out = type(out) == "table" and out or {}
    for k, v in pairs(s) do out[k] = v end
    out.whoosh = s.capable == true
    return out
end
function G.SuperInfo(out)
    out = out or {}
    out.api, out.playable, out.forms, out.ready, out.stage_tones, out.tones_muted, out.general = true, true, true, true, true, 3, true
    out.whoosh, out.whoosh_on, out.whoosh_bank, out.whoosh_characters = true, true, "ready", 1
    return out
end
function G.SuperWhoosh(on) rec("SuperWhoosh", on) return true end
function G.SuperOption(id, opt, value) rec("SuperOption", id, opt, value) return true end
function G.SuperGameOption(id, opt, value) rec("SuperGameOption", id, opt, value) return true end
function G.SuperVoicePreview(tone, id) rec("SuperVoicePreview", tone, id) return true end
function G.SuperVoiceClip(voice, id) rec("SuperVoiceClip", voice, id) return true end
function G.SetCharOption(id, opt, value) rec("SetCharOption", id, opt, value) R.opts[opt] = value return true end
function G.StateEx(id, out)
    out = out or {}
    out.rings = R.st[id] and R.st[id].rings or 0
    return out
end
function G.AddRings(id, n)
    rec("AddRings", id, n)
    if R.st[id] then R.st[id].rings = R.st[id].rings + n end
    return true
end
function G.GetLives() return 4 end
function G.SetLives() return true end
-- the emote feature: kind 8's catalogue exists, so only the guards keep the "?" from it (C4)
function G.EmoteList(kind, form)
    if kind ~= 8 then return { n = 0 } end
    return { n = 2, { key = "a130", name = "s_stationary", frames = 40, kind = "loop", class = "idle", source = 0, index = 130 },
             { key = "a131", name = "s_float", frames = 40, kind = "loop", class = "idle", source = 0, index = 131 } }
end
function G.Emote(id, key, flags, speed) rec("Emote", id, key, flags, speed) return true end
function G.EmoteStop(id, how) rec("EmoteStop", id, how) return true end
function G.EmoteState() return 0, nil, -1, 0 end
function G.EmoteInfo() return {} end
-- the jukebox (the music while Super)
function G.MusicList() return { { music = 86, file = "SPRSONIC.ADX", title = "Theme", page = 1, entry = 86, seconds = 90, loop = true, loop_start = 5, loop_end = 90, rate = 44100, listed = true, jingle = false, short = false, truncated = false } } end
function G.JukeboxPlay(ch, music) rec("JukeboxPlay", ch, music) return true, "loading" end
function G.JukeboxStop(ch) rec("JukeboxStop", ch) return true end
function G.JukeboxPause() return true end
function G.JukeboxSeek() return true end
function G.JukeboxVolume() return true end
function G.JukeboxUpdate() return 0 end
function G.JukeboxState(ch, out) out = out or {} out.music, out.state, out.position, out.length, out.loops_done, out.error = -1, "idle", 0, 0, 0, "" return out end
function G.JukeboxStatus(out) out = out or {} out.ready = true return out end
function G.AudioMusicState(out) out = out or {} out.jingle, out.stopped = -1, false return out end
function G.AudioDuck() return true end
function G.AudioSettings() return true end

-- the GMod parts lua_mock.lua does not have
local keys = {}
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    GetKeyName = function(code) return "key" .. tostring(code) end,
}
M.player.IsTyping = function() return false end
vgui.CursorVisible = function() return false end
util.NetworkStringToID = function() return 1 end
-- timer.Create that runs (the slider's debounce; small099.md 4.3: the mock stays as it is, the test runs them)
local timers = {}
timer.Create = function(name, delay, reps, fn) timers[name] = { at = M.T + delay, fn = fn } end
local function run_timers()
    for name, t in pairs(timers) do
        if M.T >= t.at then
            timers[name] = nil
            t.fn()
        end
    end
end

local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local Q, S = GSA1 and GSA1.Question, GSA1 and GSA1.Super
check(ok_load and #ferr == 0 and Q ~= nil and S ~= nil, "the addon loads, with feat/sh_question.lua and cl_question.lua (%s)", tostring(err_load or ferr[1] or "ok"))
if not (ok_load and Q and S) then return done() end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
local W, F, B, CS, T = GSA1.Wheel, GSA1.Faces, GSA1.Board, GSA1.CharSelect, GSA1.Tex
local function frames(n, dt)
    for _ = 1, n do
        M.frame(dt or 1 / 60)
        run_timers()
    end
end
local function setcv(name, v) GetConVar(name):SetString(tostring(v)) end
local function log_text()
    GSA1.LogFlush()
    return M.files["gsa1/log.txt"] or ""
end
local function log_count(text)
    local n, from = 0, 1
    local s = log_text()
    while true do
        local a, b = string.find(s, text, from, true)
        if not a then return n end
        n, from = n + 1, b + 1
    end
end

-- 0. the entry ---------------------------------------------------------------------------------------------------------------------------
local kq, dq = GSA1.KindByName("question")
check(kq == 8 and dq.title == "?" and dq.form == "question" and dq.nowheel == true and dq.noUpgrades == true, "the entry: \"?\", kind 8, its own form")
check(select(2, GSA1.KindByName("?")) == dq and select(2, GSA1.KindByName("qm")) == dq and select(2, GSA1.KindByName("question_mark")) == dq and
    select(2, GSA1.KindByName("questionmark")) == dq, "its aliases")
check(GSA1.CharacterByKind(8).name == "supersonic" and GSA1.CharacterByName("8").name == "supersonic" and GSA1.KindByName("super") == 8 and
    select(2, GSA1.KindByName("super")).name == "supersonic", "kind 8 and \"super\" stay Super Sonic (Vs. Perfect Chaos)")
check(Q.IsDef(dq) and not Q.IsDef(GSA1.CharacterByKind(8)) and not Q.IsDef(nil), "GSA1.Question.IsDef")
check(GetConVar("gsa1_question_rings"):GetInt() == 50 and GetConVar("gsa1_question_drain"):GetInt() == 0 and GetConVar("gsa1_question_water"):GetInt() == 1 and
    GetConVar("gsa1_question_spin"):GetInt() == 1 and GetConVar("gsa1_charselect_qmark"):GetInt() == 1 and GetConVar("gsa1_charselect_super"):GetString() == "question",
    "the defaults (5.9, addendum A4): rings 50, no drain, water on, spin on, gold, the slot on \"question\"")

-- 1. row 3: tick Sonic's upgrades first; row 1: the extras -------------------------------------------------------------------------------
setcv("gsa1_upgrade_light_speed_shoes", 1)
setcv("gsa1_upgrade_crystal_ring", 1)
setcv("gsa1_super_rings", 7)
setcv("gsa1_super_drain", 1)
setcv("gsa1_super_keep", 0)
setcv("gsa1_super_water", 0)
setcv("gsa1_super_faithful_revert", 1)
GSA1.Spawn("question")
local C = GSA1.Char
frames(3)
check(C ~= nil and C.kind == 8 and C.question == true and C.def == dq and C.name == "question" and C.form == "question", "\"?\" comes up: kind 8, C.question, its entry")
local ex = R.extras[C.id]
check(type(ex) == "table" and ex.create_flags == 0x2000 + 0x1000 and ex.super_flags == 2 + 1 and ex.start_rings == 50,
    "row 1: the extras carry only the gsa1_question_* values (flags 0x%X, super flags 0x%X, rings %s): gsa1_super_rings 7, _drain 1, _keep 0, _water 0, _faithful_revert 1 are not read",
    ex and ex.create_flags or 0, ex and ex.super_flags or 0, tostring(ex and ex.start_rings))
check(S.Extras(8, "spawned", nil, dq) == nil, "row 1: S.Extras returns nil for this entry")
check(#R.ups[C.id] == 0 and #C.upgrades == 0, "row 3: Sonic's ticked upgrades are not its")
check(GSA1.UpgradeText(C.upgrades) == "none", "the status line: upgrades none")
check(calls_of("SetCharOption", C.id)[1] ~= nil and calls_of("SetCharOption", C.id)[1][3] == 8 and calls_of("SetCharOption", C.id)[1][4] == 1, "the spin: COPT_QUESTION_SPIN 1 at the creation")
check(#T.later == 0, "no T.Prepare: none of Super Sonic's archives is listed (%d)", #T.later)
-- row 9
check(#calls_of("SuperOption", C.id) == 0 and #calls_of("SuperGameOption", C.id) == 0, "row 9: S.ApplyOptions did not run at its creation")
check(log_count("Super Sonic's world") == 0 and C.superForm == nil and GSA1.WarmCensus[8] == nil, "row 9: no log line \"Super Sonic's world\", no C.superForm, S.ApplyWarm(8) did not run")
check(GSA1.Warm.Start(C) == 0 and GSA1.Warm.total == nil, "no census of its own: GSA1.Warm.Start answers as with the pre-warm off")
-- row 10: the world says Super (it is a Super Sonic world), the host does not care
R.st[C.id].super = true
frames(5)
check(C.superForm == nil and log_count("turned Super") == 0, "row 10: no S.OnForm: no C.superForm, no log line \"turned Super\"")
-- row 11
setcv("gsa1_super_music", 1)
check(S.MusicWanted(C) == nil, "row 11: S.MusicWanted(C) nil")
frames(5)
check(#calls_of("JukeboxPlay") == 0, "row 11: no Super music")
setcv("gsa1_super_music", 0)

-- 2. row 2: Super Sonic's options; row 18: those that apply at once; row 4, 5: the upgrades; nothing re-creates it ---------------------------
local function no_recreate(what)
    local before, id = #M.creates, C.id
    frames(40)
    check(#M.creates == before and GSA1.Char == C and C.id == id, "%s: it is not re-created", what)
end
for _, name in ipairs({ "gsa1_super_drain", "gsa1_super_keep", "gsa1_super_faithful_revert", "gsa1_super_water", "gsa1_super_general_drain", "gsa1_super_general_keep",
                        "gsa1_super_general_water", "gsa1_super_transform" }) do
    setcv(name, GetConVar(name):GetInt() == 1 and 0 or 1)
    no_recreate("row 2: " .. name)
end
for _, name in ipairs({ "gsa1_super_general_speed", "gsa1_super_general_aura", "gsa1_super_general_effects", "gsa1_super_voice", "gsa1_super_idle_by_form", "gsa1_super_aura_anim",
                        "gsa1_super_general_anims", "gsa1_super_general_lsd_gold" }) do
    local a, b = #calls_of("SuperOption", C.id), #calls_of("SuperGameOption", C.id)
    setcv(name, GetConVar(name):GetInt() == 1 and 0 or 1)
    check(#calls_of("SuperOption", C.id) == a and #calls_of("SuperGameOption", C.id) == b, "row 18: %s: no gsa1.SuperOption, no gsa1.SuperGameOption for its id", name)
end
check(S.ApplyOptions(C) == 0, "row 18: S.ApplyOptions(C) = 0")
setcv("gsa1_upgrade_ancient_light", 1)
no_recreate("row 4: a Sonic upgrade ticked")
setcv("gsa1_upgrade_ancient_light", 0)
no_recreate("row 4: unticked")
M.cmds["gsa1_upgrades_apply"]()
no_recreate("row 5: gsa1_upgrades_apply")
M.cmds["gsa1_upgrades_all"](nil, "gsa1_upgrades_all", { "1", "supersonic" })
no_recreate("row 5: gsa1_upgrades_all")
M.cmds["gsa1_upgrades_all"](nil, "gsa1_upgrades_all", { "0", "supersonic" })
no_recreate("row 5: gsa1_upgrades_all off")

-- 3. row 8: the G key, the gesture, the command --------------------------------------------------------------------------------------------
keys[17] = true
frames(5)
keys[17] = false
frames(2)
local cmd_super = M.cmds["gsa1_super"]
cmd_super()
local press_ok, press_why = S.Press(C, "test")
check(#calls_of("SuperOrder") == 0 and press_ok == false and press_why == "the ? is not a Super Sonic", "row 8: the G key and gsa1_super: no gsa1.SuperOrder")
R.st[C.id].mode = 8
R.st[C.id].rings = 50
local B0 = S.Filter(C, 2)
check(B0 == 2 and C.gesture == nil, "row 8: the gesture: S.Filter passes the action button, it is the game's air stop")
M.keys = IN_DUCK
frames(4)
M.keys = 0
frames(2)
check(#calls_of("SuperOrder") == 0, "row 8: jump + action through the whole chain: no gsa1.SuperOrder")
R.st[C.id].mode = 1

-- 4. rows 14, 15, 16, 19, 20, 21 and C4 ----------------------------------------------------------------------------------------------------
check(F.SHORT.question == "?" and F.NoFaceText("question") == "The ? has no face" and not F.HasFaces("question"), "row 14: \"The ? has no face\"")
W.Open(C, "test")
check(not W.open and W.toastText == "? has no emotes", "row 15: the wheel key: \"%s\"", tostring(W.toastText))
local names = {}
for _, c in ipairs(W.Entries()) do names[c.name] = true end
check(not names.question and names.supersonic, "row 15: W.Entries leaves it out")
-- C4: gsa1_emote: W.ListOf gives kind 8's list, and W.PlayBody refuses first
M.cmds["gsa1_emote"](nil, "gsa1_emote", { "a130" }, "a130")
check(#calls_of("Emote") == 0, "C4: gsa1_emote as \"?\": no gsa1.Emote call")
check(W.PlayBody(C, { body = "a130", name = "s_stationary" }, 1, 1, "test") == false and #calls_of("Emote") == 0, "C4: W.PlayBody refuses")
local can, why = B.CanBoard(C, true)
check(can == false and why == "the ? doesn't ride a board", "row 16: \"%s\"", tostring(why))
check(W.CurrentEntry() ~= "question", "row 19: W.CurrentEntry() as \"?\": %s", tostring(W.CurrentEntry()))
local lines = table.concat(S.StatusLines(), " ")
check(string.find(lines, "? is a character of its own, not one of these two", 1, true) ~= nil, "row 20: the Super Sonic page's status says it is not one of the Super Sonics")
check(string.find(lines, "Vs. Perfect Chaos form", 1, true) == nil and string.find(lines, "cannot turn Super", 1, true) == nil, "row 20: not \"(the Vs. Perfect Chaos form)\", not \"cannot turn Super\"")
check(CS.SlotTitle(6) == "?", "row 21: S.SlotTitle(6) on the default \"question\": \"?\"")
setcv("gsa1_charselect_super", "last")
check(CS.SlotTitle(6) == "Super Sonic", "row 21: S.SlotTitle(6) on \"last\": Super Sonic")
setcv("gsa1_charselect_super", "question")
check(CS.SlotOf("question") == 6 and CS.FirstSlot() == 6, "Character Select opens on slot 6 as \"?\"")

-- 5. rows 6, 7, 17; S.SuperEntry ---------------------------------------------------------------------------------------------------------
check(GetConVar("gsa1_character"):GetString() == "question", "row 17: gsa1_character remembers the name")
check(GetConVar("gsa1_charselect_super_last"):GetString() == "", "row 7: being \"?\" does not change gsa1_charselect_super_last")
check(CS.SuperEntry("question", "supersonic") == "question" and CS.SuperEntry("last", "supersonic") == "supersonic" and CS.SuperEntry("last", "question") ~= "question" and
    CS.SuperEntry("last", "") == CS.SUPER_FIRST, "S.SuperEntry: the choice gives \"question\"; \"last\" never becomes it")
check(#CS.SUPER_CHOICES == 4 and CS.SUPER_CHOICES[4][1] == "The Question Mark" and CS.SUPER_CHOICES[4][2] == "question", "the 4th choice")
GSA1.Remove(true)
check(GSA1.Char == nil and W.CurrentEntry() ~= "question", "row 19: with gsa1_character \"question\" and no character: W.CurrentEntry() is %s", tostring(W.CurrentEntry()))
setcv("gsa1_character", "eggman")
check(W.CurrentEntry() ~= "eggman", "row 19: with gsa1_character \"eggman\" and no character: %s", tostring(W.CurrentEntry()))
GSA1.Spawn("eggman")
check(W.CurrentEntry() ~= "eggman", "row 19: as Dr. Eggman: %s", tostring(W.CurrentEntry()))
setcv("gsa1_upgrade_light_speed_shoes", 1)
GSA1.Spawn("supersonic")
check(GetConVar("gsa1_charselect_super_last"):GetString() == "supersonic" and GSA1.Char.question == nil and GSA1.Char.kind == 8, "a real Super Sonic: \"last\" holds him, no C.question")
frames(3)
check(R.extras[GSA1.Char.id].start_rings == 7 and #R.ups[GSA1.Char.id] > 0, "... with his own options and Sonic's upgrades, as before")
GSA1.Spawn("question")
C = GSA1.Char
frames(3)
check(GetConVar("gsa1_charselect_super_last"):GetString() == "supersonic", "row 7: \"?\" again: \"last\" still holds him")
-- the page: row 6 (the upgrade block once, Super Sonic's note), row 12 (the whoosh's help)
do
    local made, METHODS = {}, nil
    local function standin(kind)
        local Pn = { kind = kind, calls = {} }
        made[#made + 1] = Pn
        return setmetatable(Pn, { __index = function(t, k)
            if METHODS[k] then return METHODS[k] end
            if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
            return function(self, ...)
                t.calls[#t.calls + 1] = { k, ... }
                local child = standin(k)
                child.args = { ... }
                return child
            end
        end })
    end
    METHODS = { SetText = function(self, s) self.text = s end, SetConVar = function(self, c) self.convar = c end }
    vgui.Create = function(cls) return standin(cls) end
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    local char_entry, super_entry
    for _, e in ipairs(M.menu) do
        if e.class == "gsa1_character" then char_entry = e end
        if e.class == "gsa1_feat_super" then super_entry = e end
    end
    local function page(e)
        made = {}
        local cok, cerr = pcall(e.cpanel, standin("DForm"))
        check(cok, "the page %s builds (%s)", tostring(e.name), tostring(cerr or "ok"))
        local out = { boxes = {}, sliders = {}, combos = {}, helps = {}, choices = {} }
        for _, Pn in ipairs(made) do
            for _, c in ipairs(Pn.calls) do
                if c[1] == "CheckBox" then out.boxes[c[3]] = (out.boxes[c[3]] and 2) or c[2] end
                if c[1] == "NumSlider" then out.sliders[c[3]] = { c[2], c[4], c[5], c[6] } end
                if c[1] == "ComboBox" then out.combos[c[2]] = Pn end
                if c[1] == "ControlHelp" or c[1] == "Help" then out.helps[#out.helps + 1] = tostring(c[2]) end
                if c[1] == "AddChoice" then out.choices[#out.choices + 1] = tostring(c[2]) .. "=" .. tostring(c[3]) end
            end
        end
        out.text = table.concat(out.helps, " ")
        out.chose = table.concat(out.choices, " | ")
        return out
    end
    local cp = page(char_entry)
    check(cp.boxes.gsa1_upgrade_light_speed_shoes ~= 2, "row 6: Sonic's upgrade block once")
    local sl = cp.sliders.gsa1_question_rings
    check(sl and sl[1] == "The ?: start with N rings" and sl[2] == 0 and sl[3] == 99, "the control: the rings' slider, 0..99")
    check(cp.boxes.gsa1_question_drain == "The ?: lose a ring every second (Perfect Chaos' rule). It stays what it is at 0", "the control: the drain")
    check(cp.boxes.gsa1_question_water == "The ?: runs on water", "the control: the water")
    check(cp.boxes.gsa1_question_spin == "The ?: spins as on the character menu. Off: it faces the way it runs", "the control: the spin")
    check(string.find(cp.chose, "The Question Mark=question", 1, true) ~= nil, "the slot's combo has \"The Question Mark\"")
    check(string.find(cp.chose, "gold (the menu's sstx_body; not what the game's code picks)=1", 1, true) ~= nil and
        string.find(cp.chose, "as the Dreamcast draws it (the words Player Select mirrored over it)=0", 1, true) ~= nil, "the control: the texture's combo, two choices")
    local sp = page(super_entry)
    check(string.find(sp.text, "keeps Super Sonic's sounds, this one too, under this same switch", 1, true) ~= nil, "row 12: the whoosh is shared on purpose, said in the option's help")
    vgui.Create = nil
end

-- 6. its own options -----------------------------------------------------------------------------------------------------------------------
R.st[C.id].rings = 33
-- the spin: at once, no re-creation
local n0 = #calls_of("SetCharOption", C.id)
setcv("gsa1_question_spin", 0)
local sc = calls_of("SetCharOption", C.id)
check(#sc == n0 + 1 and sc[#sc][3] == 8 and sc[#sc][4] == 0, "gsa1_question_spin 0: COPT_QUESTION_SPIN at once")
no_recreate("the spin")
setcv("gsa1_question_spin", 1)
-- drain: a re-creation where it stands, the rings kept, the flags new
local b0 = #M.creates
setcv("gsa1_question_drain", 1)
frames(30)
check(#M.creates == b0 + 1 and GSA1.Char ~= C and GSA1.Char.question == true and GSA1.Char.def == dq, "gsa1_question_drain 1: re-created, still \"?\"")
C = GSA1.Char
check(R.extras[C.id].super_flags == 2 and R.extras[C.id].start_rings == 0, "... without NO_DRAIN, KEEP_AT_ZERO stays; start rings 0 for a re-creation")
check(R.st[C.id].rings == 33, "... the rings kept (%s)", tostring(R.st[C.id].rings))
check(calls_of("SetCharOption", C.id)[1] ~= nil and calls_of("SetCharOption", C.id)[1][4] == 1, "... with its spin")
setcv("gsa1_question_drain", 0)
frames(30)
C = GSA1.Char
-- water
b0 = #M.creates
setcv("gsa1_question_water", 0)
frames(30)
C = GSA1.Char
check(#M.creates == b0 + 1 and R.extras[C.id].create_flags == 0x2000, "gsa1_question_water 0: re-created, no WATER_FLOOR")
setcv("gsa1_question_water", 1)
frames(30)
C = GSA1.Char
-- the rings slider: 30 ticks, one re-creation and one log line, after the drag (R99.15)
b0 = #M.creates
local l0 = log_count("gsa1_question_rings = ")
for i = 1, 30 do
    setcv("gsa1_question_rings", 20 + i)
    frames(1, 1 / 30)
end
check(#M.creates == b0 and log_count("gsa1_question_rings = ") == l0, "the rings slider, 30 ticks: no re-creation and no log line during the drag")
frames(90)
C = GSA1.Char
check(#M.creates == b0 + 1, "one re-creation after it (%d)", #M.creates - b0)
check(log_count("gsa1_question_rings = ") == l0 + 1 and log_count("gsa1_question_rings = 50") == 1, "one log line after it, the last value")
check(R.st[C.id].rings == 50, "the re-created \"?\" has the slider's rings (%s)", tostring(R.st[C.id].rings))
-- with no "?": no re-creation
GSA1.Spawn("sonic")
frames(2)
b0 = #M.creates
setcv("gsa1_question_rings", 40)
setcv("gsa1_question_drain", 1)
frames(90)
check(#M.creates == b0 and GSA1.Char.name == "sonic", "another character: the ?'s options re-create nothing")
setcv("gsa1_question_rings", 50)
setcv("gsa1_question_drain", 0)
frames(90)
-- a respawn and a switch keep the entry
GSA1.Spawn("question")
C = GSA1.Char
frames(2)
GSA1.Respawn("test")
check(GSA1.Char.def == dq and GSA1.Char.question == true and R.extras[GSA1.Char.id].start_rings == 50, "a respawn: still \"?\", its own 50 rings")
C = GSA1.Char

-- 7. C1, C2: the texture, on the character -------------------------------------------------------------------------------------------------
local function asked()
    local e = {}
    for k in pairs(T.entries) do e[#e + 1] = k end
    table.sort(e)
    return table.concat(e, " ")
end
local QB = { key = "62.7.28.1.0.3.0", archive = 62, tex = 7, flags = 0x28, wrap = 3, src = 1, dst = 0, pass = 0, tris = 692, all = 0x28, mat = 0x9461A400 }
T.entries = {}
T.ForgetKeys()
local m1 = T.Material(8, QB)
check(string.find(asked(), "8_62_10_3", 1, true) ~= nil and string.find(asked(), "8_62_7_3", 1, true) == nil,
    "C1: {archive 62, tex 7, flags 0x28, wrap 3}, option 1: the render target 8_62_10_3: %s", asked())
C.matsDirty = false
setcv("gsa1_charselect_qmark", 0)
check(C.matsDirty == true, "the option's change: C.matsDirty on a \"?\" that exists (T.ForgetKeys does not reach its C.mats)")
T.entries = {}
T.Material(8, QB)
check(string.find(asked(), "8_62_7_3", 1, true) ~= nil and string.find(asked(), "8_62_10_3", 1, true) == nil, "C1: option 0: 8_62_7_3: %s", asked())
setcv("gsa1_charselect_qmark", 1)
T.entries = {}
T.ForgetKeys()
-- a plain Super Sonic's sphere-mapped batch: not touched, whatever its archive holds
T.Material(8, { key = "0.2.28.1.0.3.0", archive = 0, tex = 2, flags = 0x28, wrap = 3, src = 1, dst = 0, pass = 0, tris = 9, all = 0x28, mat = 0 })
check(string.find(asked(), "8_0_2_3", 1, true) ~= nil, "a sphere-mapped batch of another name keeps its texture: %s", asked())
-- C2: one gsa1.Texture call for such a batch, not a walk of its archive
T.entries = {}
T.ForgetKeys()
T.infos = {}
R.calls = {}
T.Material(8, { key = "4.1.28.1.0.3.0", archive = 4, tex = 1, flags = 0x28, wrap = 3, src = 1, dst = 0, pass = 0, tris = 9, all = 0x28, mat = 0 })
check(#calls_of("Texture") == 1, "C2: a sphere-mapped batch of another name makes one gsa1.Texture call (%d)", #calls_of("Texture"))

-- 7b. A1 (the plan's addendum: "the matcap texture has been scaled down and it's repeating"), the Lua half: what the render target and the material do
-- with the texture. The module's half (the real UVs, the real runs) is tests/feat_question_binding_test.cpp
do
    T.entries = {}
    T.ForgetKeys()
    M.rts = {}
    local mt = T.Material(8, QB)
    local rtname, rt
    for name, r in pairs(M.rts) do
        if string.find(name, "8_62_10_3", 1, true) then rtname, rt = name, r end
    end
    check(rt ~= nil and rt.w == 16 and rt.h == 16 and rt.size_mode == RT_SIZE_LITERAL, "A1: the render target has the texture's own size, literally, no scale (%s, %s x %s)",
        tostring(rtname), tostring(rt and rt.w), tostring(rt and rt.h))
    check(rt ~= nil and bit.band(rt.flags or 0, 0x4) ~= 0 and bit.band(rt.flags or 0, 0x8) ~= 0, "A1: its flags hold CLAMPS and CLAMPT (0x%X): the sampler cannot repeat", rt and rt.flags or 0)
    -- a 256 x 32 target, as the disc's CS_CE_TX: its size, and every rectangle of the paint inside it, one texel high
    local keep_tex = G.Texture
    function G.Texture(kind, index, archive)
        local t = keep_tex(kind, index, archive)
        if t and kind == 8 and archive == 62 and index == 7 then
            t.w, t.h = 256, 32
            t.runs, t.nruns = string.char(0, 0, 0, 0, 0, 1, 255, 255, 255, 255) .. string.char(0, 0, 31, 0, 0, 1, 255, 255, 0, 255), 2
        end
        return t
    end
    setcv("gsa1_charselect_qmark", 0)
    T.entries = {}
    T.infos = {}
    M.rts = {}
    local rects = {}
    local keep_rect = surface.DrawRect
    surface.DrawRect = function(x, y, w, h) rects[#rects + 1] = { x, y, w, h } keep_rect(x, y, w, h) end
    T.Material(8, QB)
    local e = T.entries["8_62_7_3"]
    T.PaintNow(8)
    M.run_hook("PostRender")
    local inside = #rects > 0
    for _, r in ipairs(rects) do
        inside = inside and r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= 256 and r[2] + r[4] <= 32 and r[4] == 1
    end
    check(e ~= nil and e.rt.w == 256 and e.rt.h == 32 and inside and bit.band(e.rt.flags or 0, 0xC) == 0xC,
        "A1: the non-square 256 x 32 texture: a 256 x 32 target, clamped; %d rectangles painted, each one texel high, none outside it: nothing is stretched or filled", #rects)
    surface.DrawRect = keep_rect
    G.Texture = keep_tex
    setcv("gsa1_charselect_qmark", 1)
    T.entries = {}
    T.infos = {}
    T.ForgetKeys()
    local mm = T.Material(8, QB)
    check(mm ~= nil and mm.params["$basetexturetransform"] == nil and mm.params["$basetexture"] ~= nil and string.find(mm.params["$basetexture"], "8_62_10_3", 1, true) ~= nil,
        "A1: the material: its $basetexture is that target, with no $basetexturetransform (no scale, no repeat): %s", tostring(mm and mm.params["$basetexture"]))
end

-- 8. a module without the "?": the flag is still asked for, so the module refuses it by name: never a plain Super Sonic under this entry -------
do
    local keep = G.SUPER
    G.SUPER = nil
    local e = Q.ExtrasFor("spawned", { rings = 50, drain = false, water = true })
    check(e.create_flags == 0x2000 + 0x1000 and e.super_flags == 3, "with no gsa1.SUPER: libsa1.h's numbers: the flag 0x2000 goes to the module")
    G.SUPER = keep
end
-- the refusal of a libsa1 that has no "?": a chat line, no character
do
    local mk = G.Create
    local said = {}
    local ca = chat.AddText
    chat.AddText = function(...) for _, v in ipairs({ ... }) do if type(v) == "string" then said[#said + 1] = v end end end
    function G.Create() return nil, "cannot create the character (unsupported): the question mark is not built yet" end
    GSA1.Remove(true)
    GSA1.Spawn("question")
    check(GSA1.Char == nil and string.find(table.concat(said, " "), "not built yet", 1, true) ~= nil, "libsa1 with no \"?\": no character, and it says why")
    G.Create = mk
    chat.AddText = ca
end

-- 9. the mock against the module's question_api.txt (5.5) ----------------------------------------------------------------------------------
do
    local groot = string.gsub(tests, "[/" .. string.char(92) .. "]tests$", "")
    local hdr = host_read(groot .. "/build/deps/include/libsa1.h") or ""
    if not string.find(hdr, "#define SA1_API_QUESTION", 1, true) then
        info("question_api.txt: the snapshot's libsa1.h has no SA1_API_QUESTION - the check is skipped (5.5's rule)")
    else
        local api = host_read(groot .. "/build/x86_64-windows/question_api.txt")
        local wrong, nc = {}, 0
        if not api then
            wrong[1] = "no build/x86_64-windows/question_api.txt"
        else
            for line in string.gmatch(api, "[^\r\n]+") do
                if string.sub(line, 1, 1) ~= "#" then
                    local f = {}
                    for part in string.gmatch(line .. "\t", "([^\t]*)\t") do f[#f + 1] = part end
                    if f[1] == "feature" and tonumber(G.FEATURES[f[2]]) ~= tonumber(f[3]) then
                        wrong[#wrong + 1] = "feature " .. tostring(f[2])
                    elseif f[1] == "const" then
                        nc = nc + 1
                        if tonumber(G.SUPER[f[2]]) ~= tonumber(f[3]) or tonumber(Q.K[f[2]]) ~= tonumber(f[3]) then wrong[#wrong + 1] = "const " .. f[2] end
                    end
                end
            end
            if nc < 3 then wrong[#wrong + 1] = string.format("only %d constants", nc) end
        end
        check(#wrong == 0, "the mock and sh_question.lua's numbers agree with question_api.txt%s", #wrong > 0 and (": " .. table.concat(wrong, ", ")) or "")
    end
end

check(#M.reported == 0, "no Lua error reported (%d%s)", #M.reported, M.reported[1] and (": " .. M.reported[1]) or "")
return done()
