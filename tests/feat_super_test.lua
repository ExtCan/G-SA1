-- feat_super_test.lua - Super Sonic's addon side (round 6a in round 0.9.3, round 0.9.3a: addon/lua/gsa1/feat/sh_super.lua
-- and cl_super.lua, sh_config.lua's character list, cl_character.lua's seams GSA1.CreateExtras and GSA1.FilterButtons,
-- cl_menu.lua's upgrade blocks, feat/cl_tools.lua's page name) in Garry's Mod's own LuaJIT with a mocked GMod
-- (tests/lua_mock.lua) and a mock of the module's feature "super" 2 (bind_super.cpp: every call recorded, the arguments
-- checked) and of its jukebox. Checks:
--   * the two Super Sonics in the list ("supersonic" = Vs. Perfect Chaos, kind 8; "supersonic_general" = General
--     Gameplay, kind 0 with a form), the aliases, Sonic's upgrades for kind 8, every setting with the owner's defaults and
--     every one on the Super Sonic page, the Character page's upgrade blocks (one per kind), the "Debug" page;
--   * the pure rules: the create extras with the review's RC1 (START only for a spawn, a switch, a respawn or a Super
--     re-creation; START_NORMAL for a kind 8 that turned back), the gesture's rule, the key's air rule;
--   * Super Sonic (Vs. Perfect Chaos): created with Sonic's upgrade names and his options (the voice, idle voices by form,
--     the aura animation), the game's trigger in the log, the rings-ran-out chat line, a re-creation after the revert
--     (an upgrade, a teleport) stays normal; the key only in the jump; no chat line for missing rings or the ground;
--   * the gesture (GSA1.FilterButtons): the press in the jump orders the form once and is kept from the game until it is
--     released, one change per jump, back in a later jump (General), Sonic's own press with too few rings or on the
--     ground; RC2 (the interact key's synthetic press never transforms), RC3 (other characters and a plain Sonic: the
--     buttons bit for bit), the key and the gesture share one latch;
--   * Super Sonic (General Gameplay): GENERAL | START, his options at once (speed, aura, golden effects, voice, aura
--     animation, idle voices: no re-creation), the drain / water options re-create him with his form (RC1), a respawn
--     keeps the entry; the voice Preview;
--   * music while Super; the pre-warm census (feat_super_test.cpp's material_census_super.txt: every line's exact
--     material for its character, the General entry with the Super states); a failing seam never stops a spawn or a tick.
-- Round 0.9.4a (sadc docs/research/super2_plan.md 6.4 with its review and the owner's answers of 10.1; the mock is the
-- module's feature "super" 4):
--   * the three new settings (gsa1_super_general_anims, gsa1_super_general_lsd_gold, gsa1_super_whoosh: default 1) with
--     their controls and help lines, the renamed "Golden trail, after-images and spin dash sparks", the old "stay Sonic's"
--     help gone; the fallback constants;
--   * SUPOPT_SUPER_ANIMS / SUPOPT_LSD_GOLD sent once at a change for the General entry and a Sonic who can transform,
--     never for kind 8; the golden effects send 3 (CLONES | DUST) and 0;
--   * the whoosh: gsa1.SuperWhoosh at the module's load and once per change; the status line for every bank state and
--     for a module without stage rules; the Preview plays 1035 for a Super-capable character and says why it cannot
--     otherwise (no chat);
--   * the census's golden Light Speed rows (SON_EFF lcharge01 / 02, WRAP_GOLD) and S.WarmRows giving them to the General
--     entry and a Sonic who can transform only, mapped by name (review R.2: today's only = "SUPERSONIC" filter drops them);
--   * the rings' "no pile-up" (super2_plan.md 10.3): the Sound page's checkbox and gsa1.AudioSettings' 9th argument.
--   lua_host tests/feat_super_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_super_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files, the jukebox's (the Super music plays through it) and the Debug page (0.9.3a: its new name)
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_super%.lua$") or string.find(n, "_jukebox%.lua$") or n == "cl_tools.lua" then
                keep[#keep + 1] = n
            end
        end
        return keep
    end
    return out
end

-- the census feat_super_test.cpp wrote, and the archives it names ("# archives <kind>: NAME count, ...")
local census_text = host_read(tests .. "/../build/x86_64-windows/material_census_super.txt")
local ARCH = {
    [0] = { { "SONIC", 28 }, { "SON_EFF", 29 }, { "OBJ_REGULAR", 96 }, { "EFF_REGULAR", 138 }, { "CON_REGULAR", 56 },
            { "SUPERSONIC", 73 } },
    [8] = { { "SUPERSONIC", 73 }, { "OBJ_REGULAR", 96 }, { "EFF_REGULAR", 138 }, { "CON_REGULAR", 56 }, { "SONIC", 28 },
            { "SON_EFF", 29 } },
}
if census_text then
    for line in string.gmatch(census_text, "[^\n]+") do
        local k, list = string.match(line, "^# archives (%d+): (.*)$")
        if k then
            local a = {}
            for name, n in string.gmatch(list, "([%w_]+) (%d+)") do a[#a + 1] = { name, tonumber(n) } end
            ARCH[tonumber(k)] = a
        end
    end
end

-- the mock module ------------------------------------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ features = { super = 4, jukebox = 1 } })
local R = { calls = {}, st = {}, bad = {}, extras = {}, ups = {}, padRaw = 0 }
local function rec(name, ...) R.calls[#R.calls + 1] = { name, ... } end
local function calls_of(name, id)
    local out = {}
    for _, c in ipairs(R.calls) do
        if c[1] == name and (id == nil or c[2] == id) then out[#out + 1] = c end
    end
    return out
end
local function last_call(name, id)
    local l = calls_of(name, id)
    return l[#l]
end
local function int_in(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end
G.BUTTON_ACTION = 2
G.SUPER = { KIND = 8, ORDER_SUPER = 46, ORDER_NORMAL = 47, NO_DRAIN = 1, KEEP_AT_ZERO = 2, FAITHFUL_REVERT = 4,
            SEA_PLANE = 8, CREATE_SUPER = 0x400, CREATE_SUPER_CAPABLE = 0x800, CREATE_WATER_FLOOR = 0x1000,
            STATE_SUPER = 8, EQUIPMENT = 0x8000, START_RINGS = 50, DRAIN_STEPS = 60, MUSIC_THEME = 86, MUSIC_CHAOS_1 = 22,
            MUSIC_CHAOS_2 = 23, GENERAL = 0x10, START = 0x20, WATER_WHILE_SUPER = 0x40, START_NORMAL = 0x80,
            SUPOPT_SPEED = 1, SUPOPT_NO_AURA = 2, SUPOPT_VOICE = 3, SUPOPT_SUPER_EFFECTS = 4, SPEED_GAME = 0, SPEED_RUN = 1,
            SPEED_HALF = 2, SPEED_SONIC = 3, GOPT_IDLE_BY_FORM = 2, GOPT_AURA_ANIM = 3, AURA_DREAMCAST = 0, AURA_CALM = 1,
            AURA_SLOW = 2, VOICE_DEFAULT = 1116,
            -- 0.9.4a (feature "super" 4)
            SUPOPT_SUPER_ANIMS = 5, SUPOPT_LSD_GOLD = 6, SUPER_EFFECTS_CLONES = 1, SUPER_EFFECTS_DUST = 2,
            DRAW_SUPER_GOLD = 0x2000, TEXTURE_VARIANT_SUPER_GOLD = 1, WHOOSH_STAGE = 19, WHOOSH_SLOW = 1035,
            WHOOSH_FAST = 1036 }
G.WRAP_GOLD = 0x10
local texture = G.Texture
function G.Texture(kind, index, archive, variant)
    if variant ~= nil then rec("Texture", kind, index, archive, variant) end
    if variant ~= nil and variant ~= 0 and not (kind == 0 and archive == 1 and index >= 25 and index <= 28) then
        return nil, "no variant"
    end
    local t = texture(kind, index, archive)
    if variant == 1 then t.name = t.name .. "_gold" end
    return t
end
function G.TextureArchives(kind)
    local out = {}
    for i, a in ipairs(ARCH[kind] or { { "ARCHIVE0", 4 } }) do out[i] = { name = a[1], count = a[2] } end
    return out
end
local create = G.Create
function G.Create(kind, pos, yaw, ups, rings, extras)
    local id = create(kind, pos, yaw, ups, rings)
    R.extras[id], R.ups[id] = extras, ups
    rec("Create", id, kind, rings, extras, ups)
    local cf = type(extras) == "table" and tonumber(extras.create_flags) or 0
    local sf = type(extras) == "table" and tonumber(extras.super_flags) or 0
    local capable = kind == 8 or bit.band(cf, 0x800) ~= 0
    R.st[id] = { super = false, capable = capable, kind = kind, rings = kind == 8 and (extras and extras.start_rings or 50)
                 or 0, equipment = 0, mode = 1, action = 0, speed = 0, changes = 0, change_step = 0, step = 0,
                 general = capable and kind == 0 and bit.band(sf, 0x10) ~= 0, start = bit.band(sf, 0x20) ~= 0 }
    return id
end
function G.SuperOrder(id, order)
    rec("SuperOrder", id, order)
    if not (int_in(id, 1, 1e9) and (order == 46 or order == 47)) then
        R.bad[#R.bad + 1] = "SuperOrder"
        return nil, "SuperOrder(id, order)", "bad_argument"
    end
    local s = R.st[id]
    if not s then return nil, "no such character", "not_found" end
    if not s.capable then return nil, "this Sonic cannot turn Super", "unsupported" end
    return true
end
function G.SuperState(id, out)
    local s = R.st[id]
    if not s then return nil end
    out = type(out) == "table" and out or {}
    for k, v in pairs(s) do out[k] = v end
    out.whoosh = s.capable == true and R.whoosh ~= false   -- 0.9.4a: the character's whoosh is routed
    return out
end
function G.SuperInfo(out)
    out = out or {}
    out.api, out.playable, out.forms, out.ready, out.stage_tones, out.tones_muted, out.general = true, true, R.forms ~= false,
        true, true, 3, true
    -- 0.9.4a: the whoosh's stage rules (R.rules false: a module whose libsa1 has none)
    out.whoosh, out.whoosh_on, out.whoosh_bank = R.rules ~= false, R.whoosh ~= false, R.bank or "ready"
    out.whoosh_characters = 1
    return out
end
function G.SuperWhoosh(on)
    rec("SuperWhoosh", on)
    if type(on) ~= "boolean" then
        R.bad[#R.bad + 1] = "SuperWhoosh"
        return nil, "SuperWhoosh(on)", "bad_argument"
    end
    if R.rules == false then return nil, "no stage rules", "unsupported" end
    R.whoosh = on
    return true
end
function G.SuperOption(id, opt, value)
    rec("SuperOption", id, opt, value)
    local s = R.st[id]
    -- libsa1's ranges: SUPER_EFFECTS bits 0..3 (0.9.4a), SUPER_ANIMS and LSD_GOLD 0 / 1
    local range_ok = (opt == 4 and int_in(value, 0, 3)) or ((opt == 5 or opt == 6) and int_in(value, 0, 1)) or
        (opt ~= 4 and opt ~= 5 and opt ~= 6)
    if not (int_in(opt, 1, 6) and int_in(value, 0, 2047) and range_ok) then
        R.bad[#R.bad + 1] = "SuperOption"
        return nil, "SuperOption(id, option, value)", "bad_argument"
    end
    if not s then return nil, "no such character", "not_found" end
    if opt ~= 3 and not s.general then return nil, "a General option", "unsupported" end
    if opt == 3 and not s.capable then return nil, "not capable", "unsupported" end
    return true
end
function G.SuperGameOption(id, opt, value)
    rec("SuperGameOption", id, opt, value)
    if not ((opt == 2 and int_in(value, 0, 1)) or (opt == 3 and int_in(value, 0, 2))) then
        R.bad[#R.bad + 1] = "SuperGameOption"
        return nil, "SuperGameOption(id, option, value)", "bad_argument"
    end
    if not R.st[id] then return nil, "no such character", "not_found" end
    return true
end
function G.SuperVoicePreview(tone, id)
    rec("SuperVoicePreview", tone, id)
    if not int_in(tone, 1, 2047) then
        R.bad[#R.bad + 1] = "SuperVoicePreview"
        return nil, "SuperVoicePreview(tone)", "bad_argument"
    end
    return true
end
function G.SuperVoiceClip(voice, id)
    rec("SuperVoiceClip", voice, id)
    if not int_in(voice, 0, 4095) then
        R.bad[#R.bad + 1] = "SuperVoiceClip"
        return nil, "SuperVoiceClip(voice)", "bad_argument"
    end
    return true
end
function G.PadPoll(dt, paused, out)
    out = out or {}
    out.connected, out.active, out.raw, out.buttons, out.sx, out.sy = R.padRaw ~= nil, false, R.padRaw or 0, 0, 0, 0
    out.yaw, out.pitch, out.reset, out.lx, out.ly, out.rx, out.ry, out.cx, out.cy, out.lt, out.rt = 0, 0, false, 0, 0, 0,
        0, 0, 0, 0, 0
    return out
end
-- the module's jukebox (bind_jukebox.cpp's Lua API), recorded
local TRACKS = { { 22, "CHAOS_P1" }, { 23, "CHAOS_P2" }, { 28, "ECOAST1" }, { 86, "SPRSONIC" } }
local JB = { ch = {} }
function G.MusicList()
    local out = {}
    for _, t in ipairs(TRACKS) do
        out[#out + 1] = { music = t[1], file = t[2] .. ".ADX", title = "Title " .. t[1], page = 1, entry = t[1], seconds = 90,
                          loop = true, loop_start = 5, loop_end = 90, rate = 44100, listed = true, jingle = false,
                          short = false, truncated = false }
    end
    return out
end
function G.JukeboxPlay(ch, music, start, plan, loops, fin, fout)
    rec("JukeboxPlay", ch, music, start, plan, loops, fin, fout)
    if not (int_in(ch, 0, 4) and int_in(music, 0, 255)) then R.bad[#R.bad + 1] = "JukeboxPlay" return false, "usage" end
    JB.ch[ch] = { music = music, state = "playing", position = 0, length = 90, loops_done = 0, error = "", paused = false }
    return true, "loading"
end
function G.JukeboxStop(ch, fade)
    rec("JukeboxStop", ch, fade)
    JB.ch[ch] = nil
    return true
end
function G.JukeboxPause(ch, paused)
    rec("JukeboxPause", ch, paused)
    if JB.ch[ch] then JB.ch[ch].paused = paused end
    return true
end
function G.JukeboxSeek(ch, t) rec("JukeboxSeek", ch, t) return true end
function G.JukeboxVolume(ch, v) rec("JukeboxVolume", ch, v) return true end
function G.JukeboxUpdate(...)
    JB.updates = (JB.updates or 0) + 1
    local n = 0
    for _, c in pairs(JB.ch) do if not c.paused then n = n + 1 end end
    return n
end
function G.JukeboxState(ch, out)
    out = out or {}
    local c = JB.ch[ch] or { music = -1, state = "idle", position = 0, length = 0, loops_done = 0, error = "" }
    for k, v in pairs(c) do out[k] = v end
    return out
end
function G.JukeboxStatus(out) out = out or {} out.ready = true return out end
function G.AudioMusicState(out) out = out or {} out.jingle, out.stopped = -1, false return out end
function G.AudioDuck(gain, dj) rec("AudioDuck", gain, dj) return true end
function G.AudioSettings(...) rec("AudioSettings", ...) return true end

-- the GMod parts the feature uses that lua_mock.lua does not have
local keys = {}
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    GetKeyName = function(code) return code == 17 and "g" or ("key" .. tostring(code)) end,
}
M.player.IsTyping = function() return M.typing == true end
local cursor = false
vgui.CursorVisible = function() return cursor end

local function frames(n, dt)
    for _ = 1, n do M.frame(dt or 1 / 60) end
end
local function console_has(text)
    for i = #M.console, 1, -1 do
        if string.find(M.console[i], text, 1, true) then return true end
    end
    return false
end
local function log_has(pat)
    GSA1.LogFlush()
    return string.find(M.files["gsa1/log.txt"] or "", pat) ~= nil
end
-- the buttons the last tick passed to the game (the mock module's Tick)
local function tick_buttons()
    return M.ticks.last and M.ticks.last.buttons or -1
end
-- the player's own action button (IN_DUCK -> SA1 action) held for n frames (the input reaches the tick a frame later)
local IN_ACTION = IN_DUCK
local function hold_action(n)
    M.keys = IN_ACTION
    frames(n)
end
local function release(n)
    M.keys = 0
    frames(n or 2)
end

-- 1. loading, the character list, the settings ------------------------------------------------------------------------------
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local S = GSA1 and GSA1.Super
check(ok_load and #ferr == 0 and S ~= nil and S.BuildPage ~= nil, "the autorun loads feat/sh_super.lua, cl_super.lua and "
    .. "cl_tools.lua (%s)", ok_load and table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_load or ferr[1]))
if not (ok_load and S) then return done() end
local k8, def8 = GSA1.KindByName("supersonic")
local kg, defg = GSA1.KindByName("supersonic_general")
check(k8 == 8 and def8.title == "Super Sonic (Vs. Perfect Chaos)" and kg == 0 and defg.form == "general" and
    defg.title == "Super Sonic (General Gameplay)" and #GSA1.CHARACTERS == 8 and GSA1.KindByName("super") == 8 and
    GSA1.KindByName("Super_Sonic") == 8 and GSA1.KindByName("vspc") == 8 and select(2, GSA1.KindByName("ssg")) == defg and
    select(2, GSA1.KindByName("super_general")) == defg and GSA1.CharacterByKind(0).name == "sonic" and
    GSA1.CharacterByName("0").name == "sonic" and GSA1.CharacterByName("8").name == "supersonic",
    "GSA1.CHARACTERS: \"Super Sonic (Vs. Perfect Chaos)\" (kind 8, \"supersonic\" / \"super\" / \"vspc\") and \"Super "
    .. "Sonic (General Gameplay)\" (kind 0, form general: \"supersonic_general\" / \"ssg\" / \"super_general\"); kind 0's "
    .. "own entry stays Sonic")
RunConsoleCommand("gsa1_upgrade_light_speed_shoes", "1")
RunConsoleCommand("gsa1_upgrade_ancient_light", "1")
local un8 = GSA1.UpgradeNames(8)
check(#GSA1.UpgradesOf(8) == 0 and GSA1.UpgradeKind(8) == 0 and GSA1.UpgradeKind(2) == 2 and #un8 == 2 and
    un8[1] == "light_speed_shoes" and un8[2] == "ancient_light",
    "kind 8 has Sonic's upgrades (GSA1.UpgradeNames(8): %s), none of his own", table.concat(un8, " "))
RunConsoleCommand("gsa1_upgrade_light_speed_shoes", "0")
RunConsoleCommand("gsa1_upgrade_ancient_light", "0")
local WANT = {
    gsa1_super_rings = { "50", 0, 99 }, gsa1_super_drain = { "1", 0, 1 }, gsa1_super_keep = { "0", 0, 1 },
    gsa1_super_faithful_revert = { "0", 0, 1 }, gsa1_super_water = { "1", 0, 1 }, gsa1_super_transform = { "1", 0, 1 },
    gsa1_super_transform_rings = { "50", 1, 99 }, gsa1_super_key = { "17", 0, 511 }, gsa1_super_pad = { "0", 0, 0x30000 },
    gsa1_super_music = { "0", 0, 4 }, gsa1_super_music_track = { "86", 0, 255 },
    -- 0.9.3a
    gsa1_super_general_rings = { "50", 0, 99 }, gsa1_super_general_drain = { "1", 0, 1 },
    gsa1_super_general_keep = { "0", 0, 1 }, gsa1_super_general_speed = { "1", 0, 3 },
    gsa1_super_general_aura = { "1", 0, 1 }, gsa1_super_general_water = { "1", 0, 1 },
    gsa1_super_general_effects = { "1", 0, 1 }, gsa1_super_gesture = { "1", 0, 1 }, gsa1_super_gesture_back = { "1", 0, 1 },
    gsa1_super_voice = { "4492", 0, 8191 }, gsa1_super_aura_anim = { "1", 0, 2 }, gsa1_super_idle_by_form = { "1", 0, 1 },
    -- 0.9.4a (super2_plan.md 7)
    gsa1_super_general_anims = { "1", 0, 1 }, gsa1_super_general_lsd_gold = { "1", 0, 1 }, gsa1_super_whoosh = { "1", 0, 1 },
}
local bad = {}
for name, w in pairs(WANT) do
    local c = M.convars[name]
    if not (c and c.client and c.save and c.v == w[1] and c.lo == w[2] and c.hi == w[3] and GSA1.CONVARS[name]) then
        bad[#bad + 1] = name
    end
end
local mine = 0
for name in pairs(GSA1.CONVARS) do if string.find(name, "^gsa1_super") then mine = mine + 1 end end
table.sort(bad)
check(#bad == 0 and mine == 26, "26 client settings with the owner's defaults: Vs. Perfect Chaos as 0.9.3; General "
    .. "Gameplay 50 rings, the drain on, Super run, the aura and the golden effects on, water while Super; the gesture and "
    .. "the gesture back on; the voice Super Sonic's \"Hm!\" (clip 396: 4492); the calm aura; idle voices by form; 0.9.4a: "
    .. "the Super poses, the golden Light Speed Dash and the aura whoosh on%s (%d)",
    #bad > 0 and (": wrong " .. table.concat(bad, " ")) or "", mine)
-- 0.9.4a: the fallback constants of sh_super.lua (the module's win when it has them)
local K = GSA1.Super.K
check(K.SUPOPT_SUPER_ANIMS == 5 and K.SUPOPT_LSD_GOLD == 6 and K.SUPER_EFFECTS_CLONES == 1 and K.SUPER_EFFECTS_DUST == 2 and
    K.WHOOSH_STAGE == 19 and GSA1.Super.WRAP_GOLD == 0x10 and GSA1.Super.Const("SUPOPT_LSD_GOLD") == 6,
    "the fallback constants: SUPOPT_SUPER_ANIMS 5, SUPOPT_LSD_GOLD 6, SUPER_EFFECTS_CLONES 1 / _DUST 2, WHOOSH_STAGE 19, "
    .. "WRAP_GOLD 0x10")

-- the pages: every setting has a control; the Character page has one upgrade block per kind; "Debug"
local made = {}
local METHODS
local function standin(kind)
    local P = { kind = kind, calls = {} }
    made[#made + 1] = P
    return setmetatable(P, { __index = function(t, k)
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
local entry, debug_entry, char_entry
for _, e in ipairs(M.menu) do
    if e.class == "gsa1_feat_super" then entry = e end
    if e.class == "gsa1_feat_tools" then debug_entry = e end
    if e.class == "gsa1_character" then char_entry = e end
end
check(entry and entry.name == "Super Sonic" and entry.category == "G-SA1", "the page Options -> G-SA1 -> Super Sonic")
check(debug_entry and debug_entry.name == "Debug", "the owner's rename: the \"Notes and tools\" page is \"Debug\" (%s)",
    debug_entry and tostring(debug_entry.name) or "missing")
local preview_button, whoosh_button
if entry then
    local panel = standin("DForm")
    entry.cpanel(panel)
    local bound, combos, texts, spawn, spawn_g = {}, {}, {}, false, false
    for _, P in ipairs(made) do
        for _, c in ipairs(P.calls) do
            if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then bound[c[3]] = true end
            if c[1] == "Help" or c[1] == "ControlHelp" then texts[#texts + 1] = tostring(c[2]) end
            if c[1] == "Button" and c[3] == "gsa1_spawn" and c[4] == "supersonic" then spawn = true end
            if c[1] == "Button" and c[3] == "gsa1_spawn" and c[4] == "supersonic_general" then spawn_g = true end
            if c[1] == "Button" and c[3] == "gsa1_super_key" then bound.gsa1_super_key_none = true end
        end
        if P.convar then bound[P.convar] = true end
        if P.kind == "ComboBox" and P.OnSelect then combos[#combos + 1] = P end
        if P.kind == "Button" and P.DoClick and P.args and P.args[1] == "Preview the voice" then preview_button = P end
        if P.kind == "Button" and P.DoClick and P.args and P.args[1] == "Preview the whoosh" then whoosh_button = P end
    end
    -- the combo boxes (OnSelect sets their ConVar): the controller button, the speed, the voice, the aura animation, the
    -- music
    local CB = { gsa1_super_pad = "0", gsa1_super_general_speed = "1", gsa1_super_voice = "4492",
                 gsa1_super_aura_anim = "1", gsa1_super_music = "0" }
    for _, P in ipairs(combos) do
        P.OnSelect(P, 1, "x", "2")
        for name, def in pairs(CB) do
            if M.convars[name].v == "2" then bound[name] = true end
            M.convars[name].v = def
        end
    end
    local missing = {}
    for name in pairs(WANT) do if not bound[name] then missing[#missing + 1] = name end end
    table.sort(missing)
    local pt = table.concat(texts, " ")
    check(#missing == 0 and spawn and spawn_g and bound.gsa1_super_key_none and #combos == 5 and preview_button ~= nil and
        string.find(pt, "37", 1, true) == nil,
        "every setting has a control (check boxes, sliders, the key binder, %d combo boxes), spawn buttons for both Super "
        .. "Sonics, a voice Preview; no \"+37 %%\" promise%s", #combos, #missing > 0 and (": missing " ..
        table.concat(missing, " ")) or "")
    -- 0.9.4a: the labels, their order on the page and the help lines (super2_plan.md 7)
    local order, label = {}, {}
    for _, P in ipairs(made) do
        if P.kind == "DForm" then
            for i, c in ipairs(P.calls) do
                if c[1] == "CheckBox" and type(c[3]) == "string" then
                    order[c[3]], label[c[3]] = i, c[2]
                elseif c[1] == "ComboBox" and c[2] == "Aura animation" then
                    order.aura_anim = i
                elseif c[1] == "Button" and c[2] == "Preview the whoosh" then
                    order.whoosh_preview = i
                end
            end
        end
    end
    check(label.gsa1_super_general_anims == "Super Sonic's own poses (floating stand, flying run)" and
        label.gsa1_super_general_effects == "Golden trail, after-images and spin dash sparks" and
        label.gsa1_super_general_lsd_gold == "Golden Light Speed Dash" and label.gsa1_super_whoosh == "Aura whoosh sounds" and
        (order.gsa1_super_general_aura or 99) < (order.gsa1_super_general_anims or 0) and
        order.gsa1_super_general_anims < (order.gsa1_super_general_effects or 0) and
        order.gsa1_super_general_effects < (order.gsa1_super_general_lsd_gold or 0) and
        (order.aura_anim or 99) < (order.gsa1_super_whoosh or 0) and order.gsa1_super_whoosh < (order.whoosh_preview or 0),
        "0.9.4a's controls: after \"Aura\" \"Super Sonic's own poses (floating stand, flying run)\", the renamed \"Golden "
        .. "trail, after-images and spin dash sparks\", \"Golden Light Speed Dash\"; after \"Aura animation\" \"Aura whoosh "
        .. "sounds\" and \"Preview the whoosh\"")
    check(string.find(pt, "The game's Super Sonic animations for standing and moving", 1, true) ~= nil and
        string.find(pt, "he taps his foot like Sonic", 1, true) ~= nil and
        string.find(pt, "G-SA1 gives them the golden texture of the Super after-images", 1, true) ~= nil and
        string.find(pt, "The Light Speed charge's sparkles, streaks and glow in Super Sonic's gold", 1, true) ~= nil and
        string.find(pt, "the sparkles and streaks stay the game's green", 1, true) ~= nil and
        string.find(pt, "from the Perfect Chaos stage's sound bank on your disc", 1, true) ~= nil and
        string.find(pt, "stay Sonic's", 1, true) == nil and whoosh_button ~= nil,
        "the help lines: the poses (with the owner's foot tap, O1), the sparks' borrowed gold (review R.5), the golden "
        .. "Light Speed Dash (the Crystal Ring's green kept, O3), the whoosh; the old \"... stay Sonic's\" gone")
end
if char_entry then
    made = {}
    local panel = standin("DForm")
    local cok, cerr = pcall(char_entry.cpanel, panel)
    local shoes, choices, quick, note = 0, {}, {}, ""
    for _, P in ipairs(made) do
        for _, c in ipairs(P.calls) do
            if c[1] == "CheckBox" and c[3] == "gsa1_upgrade_light_speed_shoes" then shoes = shoes + 1 end
            if c[1] == "AddChoice" then choices[#choices + 1] = tostring(c[3]) end
            if c[1] == "Button" and c[3] == "gsa1_spawn" and c[4] then quick[#quick + 1] = c[4] end
            if c[1] == "ControlHelp" and string.find(tostring(c[2]), "Super Sonics use Sonic's upgrades", 1, true) then
                note = c[2]
            end
        end
    end
    check(cok and shoes == 1 and #choices == 8 and #quick == 8 and note ~= "",
        "the Character page: both Super Sonics in the list (%d entries) and the quick spawn buttons (%d); Sonic's upgrade "
        .. "block once (RC4: %d), \"Both Super Sonics use Sonic's upgrades\"%s", #choices, #quick, shoes,
        cok and "" or (": " .. tostring(cerr)))
end
vgui.Create = function(cls) return standin(cls) end

-- 2. the pure rules ----------------------------------------------------------------------------------------------------------
local o = S.Options()
local e8 = S.ExtrasFor(8, "spawned", o, true, def8)
local e8r = S.ExtrasFor(8, "re-created", o, true, def8, { super = true })
local e8n = S.ExtrasFor(8, "re-created", o, true, def8, { super = false, reverted = true })
local e8f = S.ExtrasFor(8, "re-created", o, true, def8, { super = false, reverted = false })
local o2 = S.Options()
o2.water, o2.drain, o2.keep, o2.faithful = false, false, true, true
local e8b = S.ExtrasFor(8, "respawned", o2, true, def8)
local eg = S.ExtrasFor(0, "spawned", o, true, defg)
local egr = S.ExtrasFor(0, "respawned", o, true, defg, { super = false })
local egn = S.ExtrasFor(0, "re-created", o, true, defg, { super = false })
local egs = S.ExtrasFor(0, "re-created", o, true, defg, { super = true })
local o4 = S.Options()
o4.general_drain, o4.general_keep, o4.general_water = false, true, false
local eg4 = S.ExtrasFor(0, "spawned", o4, true, defg)
local e0 = S.ExtrasFor(0, "spawned", o, true, GSA1.CharacterByKind(0))
local e0s = S.ExtrasFor(0, "re-created", o, true, GSA1.CharacterByKind(0), { super = true })
local o3 = S.Options()
o3.transform = false
check(S.SuperFlags(o) == 0 and e8.create_flags == 0x1000 and e8.super_flags == 0 and e8.start_rings == 50 and
    e8r.start_rings == 0 and e8r.super_flags == 0 and e8n.super_flags == 0x80 and e8f.super_flags == 0 and
    e8b.create_flags == 0 and e8b.super_flags == 7,
    "Vs. Perfect Chaos: run on water (0x1000), the drain, 50 rings (0 on a re-creation: the old count is carried over); "
    .. "re-created after he had turned back: START_NORMAL 0x80 (RC1), while Super or before the trigger: the game's trigger")
check(eg.create_flags == 0x800 and eg.super_flags == 0x70 and eg.start_rings == 50 and egr.super_flags == 0x70 and
    egn.super_flags == 0x50 and egn.start_rings == 0 and egs.super_flags == 0x70 and eg4.super_flags == 0x13 + 0x20 and
    e0.create_flags == 0x800 and e0.super_flags == 0x50 and e0.start_rings == nil and e0s.super_flags == 0x70,
    "General Gameplay: SUPER_CAPABLE, GENERAL | START | WATER_WHILE_SUPER (0x70) and 50 rings when spawned or respawned; "
    .. "re-created normal: no START (0x50, RC1), re-created Super: START; no drain / stay Super / no water: 0x33; Sonic "
    .. "with the transformation: GENERAL | WATER (0x50) without START, START only when re-created while Super")
check(S.ExtrasFor(0, "spawned", o3, true, GSA1.CharacterByKind(0)) == nil and
    S.ExtrasFor(0, "spawned", o, false, defg) == nil and S.ExtrasFor(0, "spawned", o, false, GSA1.CharacterByKind(0)) == nil
    and S.ExtrasFor(2, "spawned", o, true, GSA1.CharacterByKind(2)) == nil and
    S.ExtrasFor(0, "spawned", o, true, defg, nil, false) == nil and
    S.ExtrasFor(0, "spawned", o, true, GSA1.CharacterByKind(0), nil, false).super_flags == 0,
    "nothing for: Sonic with the transformation off, no Super forms, Tails, the General entry with a module before "
    .. "0.9.3a; a Sonic with such a module gets 0.9.3's SUPER_CAPABLE world")
local GO = { gesture = true, back = true, need = 50 }
local function ga(st, opt) return S.GestureAction(st, opt or GO) end
check(ga({ capable = true, super = false, rings = 50, mode = 8 }) == "super" and
    ga({ capable = true, super = false, rings = 49, mode = 8 }) == nil and
    ga({ capable = true, super = false, rings = 80, mode = 1 }) == nil and
    ga({ capable = true, super = false, rings = 80, mode = 8 }, { gesture = false, back = true, need = 50 }) == nil and
    ga({ capable = false, super = false, rings = 80, mode = 8 }) == nil and
    ga({ capable = true, super = true, general = true, rings = 0, mode = 8 }) == "normal" and
    ga({ capable = true, super = true, general = true, rings = 9, mode = 8 }, { gesture = true, back = false, need = 50 })
        == nil and ga({ capable = true, super = true, general = false, rings = 50, mode = 8 }) == nil and
    ga({ capable = true, super = true, general = true, rings = 50, mode = 2 }) == nil,
    "the gesture's rule: the jump (mode 8) with 50 rings -> Super; 49 rings, the ground, the gesture off, a plain Sonic -> "
    .. "the game's press; a General Super Sonic in the jump -> back (unless the option is off); a Vs. Perfect Chaos Super "
    .. "Sonic -> the game's air stop")
local a1 = S.KeyAction({ capable = true, super = false, rings = 50, mode = 8 }, 50)
local a1g, w1g = S.KeyAction({ capable = true, super = false, rings = 50, mode = 1 }, 50)
local a2, w2 = S.KeyAction({ capable = true, super = false, rings = 49, mode = 8 }, 50)
local a3 = S.KeyAction({ capable = true, super = true, rings = 0, mode = 2 }, 50)
local a4, w4 = S.KeyAction({ capable = false, super = false, rings = 99, mode = 8 }, 50)
local a5, w5 = S.KeyAction(nil, 50)
local a6, w6 = S.KeyAction({ capable = true, super = false, rings = 99, mode = 8 }, 50, true)
check(a1 == "super" and a1g == nil and w1g == "ground" and a2 == nil and w2 == "rings" and a3 == "normal" and a4 == nil and
    w4 == "capable" and a5 == nil and w5 == "module" and a6 == nil and w6 == "dead",
    "the key's rule: 50 rings in the jump -> Super; standing -> refused (ground, owner note 455); 49 -> refused (rings); "
    .. "Super -> back to normal anywhere; a world that cannot turn Super, no module, a dying character -> refused")
check(S.MusicNumber(0, 86) == nil and S.MusicNumber(1, 0) == 86 and S.MusicNumber(2) == 22 and S.MusicNumber(3) == 23 and
    S.MusicNumber(4, 28) == 28 and S.MusicNumber(4, -1) == nil, "the music: off, Theme of Super Sonic 86, Perfect Chaos "
    .. "22 / 23, a jukebox track")

GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }

-- 3. Super Sonic (Vs. Perfect Chaos) from the list ----------------------------------------------------------------------------
RunConsoleCommand("gsa1_upgrade_light_speed_shoes", "1")
GSA1.Spawn("supersonic")
local C = GSA1.Char
local cr = last_call("Create")
check(C ~= nil and C.kind == 8 and C.name == "supersonic" and C.title == "Super Sonic (Vs. Perfect Chaos)" and cr and
    cr[3] == 8 and type(cr[5]) == "table" and cr[5].create_flags == 0x1000 and cr[5].super_flags == 0 and
    cr[5].start_rings == 50 and C.extras == cr[5] and type(cr[6]) == "table" and cr[6][1] == "light_speed_shoes" and
    M.convars.gsa1_character.v == "supersonic",
    "spawn Super Sonic (Vs. Perfect Chaos): gsa1.Create(8, ..., Sonic's ticked upgrades {%s}, extras {0x1000, 0, 50})",
    cr and type(cr[6]) == "table" and table.concat(cr[6], " ") or "?")
if not C then return done() end
local so8 = calls_of("SuperOption", C.id)
local go8 = calls_of("SuperGameOption", C.id)
check(#so8 == 1 and so8[1][3] == 3 and so8[1][4] == 0 and #go8 == 2 and go8[1][3] == 2 and go8[1][4] == 1 and
    go8[2][3] == 3 and go8[2][4] == 1,
    "his options before the first tick: no libsa1 tone for the voice (SuperOption 3 = 0: the clip is G-SA1's), idle voices by form (2 = 1) and the calm aura (3 "
    .. "= 1); nothing of the General form (%d / %d calls)", #so8, #go8)
frames(3)
R.st[C.id].super, R.st[C.id].changes, R.st[C.id].change_step, R.st[C.id].speed, R.st[C.id].mode = true, 1, 4, 0, 71
frames(2)
check(C.superForm == true and log_has("super +Super Sonic %(Vs%. Perfect Chaos%) turned Super %(the game's own trigger, as "
    .. "on Perfect Chaos%) at step 4: 50 rings"), "he turns Super (the game's trigger): the session log says so")
-- the key while Super: back to normal anywhere (the game's request 47)
R.st[C.id].mode = 71
keys[17] = true
frames(2)
keys[17] = nil
frames(1)
local so = calls_of("SuperOrder", C.id)
R.st[C.id].super, R.st[C.id].mode = false, 1
frames(2)
check(#so == 1 and so[1][3] == 47 and log_has("Super Sonic %(Vs%. Perfect Chaos%) turned back into normal Sonic %(the "
    .. "key%)"), "G while he is Super (mode 71): SuperOrder(47), back to normal Sonic by the key")
R.st[C.id].super, R.st[C.id].mode = true, 71
frames(1)
-- the rings run out: back to normal Sonic in his own world (the chat line stays: design C7)
R.st[C.id].super, R.st[C.id].rings, R.st[C.id].changes, R.st[C.id].change_step, R.st[C.id].mode = false, 0, 2, 3004, 1
M.console = {}
frames(2)
check(C.superForm == false and not console_has("the rings ran out, back to normal Sonic") and
    log_has("turned back into normal Sonic %(the rings ran out %(the game's drain%)%) at step 3004"),
    "at 0 rings: \"the rings ran out\" in the log only, no chat line (owner note on 0.9.3b); he stays the same character "
    .. "(kind %d)", C.kind)
-- owner notes 455 / 816: the key standing, the key with too few rings: nothing happens and nothing is said in the chat
R.st[C.id].rings, R.st[C.id].mode = 10, 8
M.console = {}
keys[17] = true
frames(2)
keys[17] = nil
frames(1)
R.st[C.id].rings, R.st[C.id].mode = 60, 1
keys[17] = true
frames(2)
keys[17] = nil
frames(1)
check(#calls_of("SuperOrder", C.id) == 1 and #M.console == 0 and log_has("transformation refused %(rings%)"),
    "G with 10 rings in the jump, G with 60 rings standing: no order and no chat line (only the log: %s)",
    log_has("transformation refused %(ground%)") and "rings, ground" or "rings")
R.st[C.id].mode = 8
keys[17] = true
frames(5)
keys[17] = nil
frames(1)
so = calls_of("SuperOrder", C.id)
check(#so == 2 and so[2][3] == 46, "G held for 5 frames with 60 rings in the jump: one SuperOrder(46) (%d calls)", #so)
R.st[C.id].super, R.st[C.id].changes, R.st[C.id].mode = true, 3, 74
frames(1)
check(C.superForm and log_has("Super Sonic %(Vs%. Perfect Chaos%) turned Super %(the key%)"), "turned Super: the cause is "
    .. "the key")
-- the action button in the air while he is Super: the game's air stop (never taken by the gesture)
R.st[C.id].mode = 8
local before = #calls_of("SuperOrder", C.id)
hold_action(3)
local tb = tick_buttons()
release(2)
check(#calls_of("SuperOrder", C.id) == before and bit.band(tb, 2) ~= 0, "the action button in the air while Super: the "
    .. "game gets it (the air stop), no order")
-- busy: a panel (GSA1.InputBlocked), the cursor, the chat
R.st[C.id].super, R.st[C.id].mode = false, 8
frames(1)
local n0 = #calls_of("SuperOrder")
local ib = GSA1.InputBlocked
GSA1.InputBlocked = function() return true end
keys[17] = true
frames(2)
keys[17] = nil
frames(1)
GSA1.InputBlocked = ib
cursor = true
keys[17] = true
frames(2)
keys[17] = nil
frames(1)
cursor = false
M.typing = true
keys[17] = true
frames(2)
keys[17] = nil
frames(1)
M.typing = false
check(#calls_of("SuperOrder") == n0, "no order while a panel has the input, the cursor is out or the chat is open")
-- 0.9.4b (objects2_plan.md 11.2, the owner: the right stick click should do "Nothing"): no controller button by default -
-- the right stick click in the jump gives no order; chosen on the page (128), it does, like gsa1_super
local nC = #calls_of("SuperOrder", C.id)
R.padRaw = 0x80
frames(2)
R.padRaw = 0
frames(3)
local by_default = #calls_of("SuperOrder", C.id) - nC
RunConsoleCommand("gsa1_super_pad", "128")
nC = #calls_of("SuperOrder", C.id)
R.padRaw = 0x80
frames(2)
R.padRaw = 0
frames(3)                           -- the command comes after a game step (the order latch, S.ORDER_GAP)
M.cmds.gsa1_super(nil, "gsa1_super", {}, "")
so = calls_of("SuperOrder", C.id)
RunConsoleCommand("gsa1_super_pad", "0")
check(by_default == 0 and #so == nC + 2 and so[#so - 1][3] == 46 and so[#so][3] == 46,
    "the right stick click does nothing by default (%d orders); chosen as the button (128) it and gsa1_super in the jump "
    .. "give one order each", by_default)
R.padRaw = nil
-- review RC1: re-created after he had turned back (an upgrade ticked, a teleport) he stays normal Sonic
R.st[C.id].super, R.st[C.id].rings, R.st[C.id].mode = false, 12, 1
frames(2)
local nc = #calls_of("Create")
RunConsoleCommand("gsa1_upgrade_crystal_ring", "1")
frames(30)
local NC = GSA1.Char
cr = last_call("Create")
check(#calls_of("Create") == nc + 1 and NC ~= C and NC.kind == 8 and NC.name == "supersonic" and cr[5].super_flags == 0x80
    and cr[5].start_rings == 0 and type(cr[6]) == "table" and #cr[6] == 2,
    "an upgrade ticked after he turned back: re-created with START_NORMAL (0x80: no trigger, he stays normal Sonic) and "
    .. "Sonic's two ticked upgrades")
C = NC
GSA1.Recreate("a teleport", Vector(100, 200, 300), 90)
cr = last_call("Create")
check(GSA1.Char.kind == 8 and cr[5].super_flags == 0x80, "a teleport (GSA1.Recreate with a place): START_NORMAL again")
C = GSA1.Char
R.st[C.id].super, R.st[C.id].changes = true, 1
frames(2)
GSA1.Recreate("a fault restart")
cr = last_call("Create")
check(cr[5].super_flags == 0, "re-created while Super: the game's trigger again (super flags 0x%X)", cr[5].super_flags)
RunConsoleCommand("gsa1_upgrade_light_speed_shoes", "0")
RunConsoleCommand("gsa1_upgrade_crystal_ring", "0")
frames(30)

-- 4. the gesture (GSA1.FilterButtons) -----------------------------------------------------------------------------------------
GSA1.Spawn("sonic")
C = GSA1.Char
cr = last_call("Create")
check(C and C.kind == 0 and C.name == "sonic" and type(cr[5]) == "table" and cr[5].create_flags == 0x800 and
    cr[5].super_flags == 0x50 and cr[5].start_rings == nil, "spawn Sonic with the transformation on: the General form "
    .. "(extras {0x800 SUPER_CAPABLE, 0x50 GENERAL | WATER_WHILE_SUPER}, no START)")
local so0 = calls_of("SuperOption", C.id)
local function opt_last(list, opt)
    for i = #list, 1, -1 do if list[i][3] == opt then return list[i][4] end end
    return nil
end
check(#so0 == 6 and opt_last(so0, 4) == 3 and opt_last(so0, 5) == 1 and opt_last(so0, 6) == 1, "a Sonic who can "
    .. "transform gets the General options at once (%d SuperOption calls: speed, aura, golden effects 3, voice; 0.9.4a: "
    .. "the Super poses, the golden Light Speed)", #so0)
frames(2)
local st0 = R.st[C.id]
st0.rings, st0.mode = 55, 1
-- standing: the action button is Sonic's crouch / spin dash
hold_action(3)
local stand_b = tick_buttons()
release()
check(bit.band(stand_b, 2) ~= 0 and #calls_of("SuperOrder", C.id) == 0, "standing with 55 rings: the action button "
    .. "reaches the game (spin dash), no order")
-- in the jump: the press orders Super once and is held back until released
st0.mode = 8
M.keys = IN_ACTION
frames(2)
local b1 = tick_buttons()
st0.super, st0.changes = true, 1
frames(4)
local b2 = tick_buttons()
st0.mode = 1
frames(3)
local b3 = tick_buttons()
so = calls_of("SuperOrder", C.id)
release(2)
local b4 = tick_buttons()
check(#so == 1 and so[1][3] == 46 and bit.band(b1, 2) == 0 and bit.band(b2, 2) == 0 and bit.band(b3, 2) == 0 and
    bit.band(b4, 2) == 0 and C.superForm and log_has("Sonic %(General%): the Super transformation asked by the action "
    .. "button in the jump"), "in the jump with 55 rings: one SuperOrder(46); the press is kept from the game while held, "
    .. "also after he lands (no spin dash): buttons %d %d %d", b1, b2, b3)
-- a new press after the release, on the ground: Sonic's own
hold_action(3)
local b5 = tick_buttons()
release()
check(bit.band(b5, 2) ~= 0 and #calls_of("SuperOrder", C.id) == 1, "a new press after the release (on the ground): the "
    .. "game's again")
-- one change per jump: Super in this jump already -> the next press in the same jump is the game's
st0.super, st0.mode = false, 8
frames(2)
hold_action(3)
release(1)
local ord1 = #calls_of("SuperOrder", C.id)
st0.super = true
hold_action(3)
local b6 = tick_buttons()
release(1)
check(ord1 == 2 and #calls_of("SuperOrder", C.id) == 2 and bit.band(b6, 2) ~= 0, "one form change per jump: the second "
    .. "press in the same jump reaches the game (%d orders)", #calls_of("SuperOrder", C.id))
-- a later jump while Super (General): back to Sonic
st0.mode = 1
frames(2)
st0.mode = 8
hold_action(3)
so = calls_of("SuperOrder", C.id)
local b7 = tick_buttons()
release(2)
check(#so == 3 and so[3][3] == 47 and bit.band(b7, 2) == 0, "a later jump while Super: the press turns him back "
    .. "(SuperOrder(47)), held back from the game")
st0.super = false
-- gesture back off: the press in the jump while Super is the game's
RunConsoleCommand("gsa1_super_gesture_back", "0")
st0.super, st0.mode = true, 1
frames(2)
st0.mode = 8
hold_action(3)
local b8 = tick_buttons()
release(2)
check(#calls_of("SuperOrder", C.id) == 3 and bit.band(b8, 2) ~= 0, "\"the same in a later jump turns him back\" off: "
    .. "Sonic's own air action")
RunConsoleCommand("gsa1_super_gesture_back", "1")
-- too few rings: the game's press, no chat line, no order
st0.super, st0.rings, st0.mode = false, 12, 1
frames(2)
st0.mode = 8
M.console = {}
hold_action(3)
local b9 = tick_buttons()
release(2)
check(#calls_of("SuperOrder", C.id) == 3 and bit.band(b9, 2) ~= 0 and #M.console == 0, "12 rings in the jump: Sonic's "
    .. "own air action, no order and no chat line (owner note 816)")
-- RC2: the interact key's synthetic press (GSA1.ExtraButtons) never transforms
st0.rings, st0.mode = 60, 1
frames(2)
st0.mode = 8
local eb = GSA1.ExtraButtons
local extra_on = true
GSA1.ExtraButtons = function() return extra_on and 2 or 0 end
frames(4)
local b10 = tick_buttons()
extra_on = false
frames(2)
GSA1.ExtraButtons = eb
check(#calls_of("SuperOrder", C.id) == 3 and bit.band(b10, 2) ~= 0, "RC2: the interact key's action press in the jump "
    .. "with 60 rings reaches the game and transforms nobody")
-- the key and the gesture in the same frame: one order (the shared latch, RC11)
st0.mode = 1
frames(2)
st0.mode = 8
M.keys = IN_ACTION
frames(1)
keys[17] = true                     -- the key's edge and the action button's edge in the same tick
frames(1)
keys[17] = nil
release(2)
so = calls_of("SuperOrder", C.id)
check(#so == 4 and so[4][3] == 46, "G and the action button pressed together in the jump: one order (%d)", #so - 3)
st0.super = false
-- gesture off: only the key
RunConsoleCommand("gsa1_super_gesture", "0")
st0.mode = 1
frames(2)
st0.mode = 8
hold_action(3)
local b11 = tick_buttons()
release(2)
check(#calls_of("SuperOrder", C.id) == 4 and bit.band(b11, 2) ~= 0, "gsa1_super_gesture 0: the press in the jump is "
    .. "Sonic's own")
RunConsoleCommand("gsa1_super_gesture", "1")
-- RC3: Tails and a Sonic with the transformation off see their buttons bit for bit
local SEQ = { 0, IN_ACTION, IN_ACTION, 0, IN_JUMP, IN_JUMP + IN_ACTION, IN_ACTION, 0, IN_ACTION, IN_ACTION, IN_ACTION, 0 }
local function sequence(c)
    local out = {}
    for _, k in ipairs(SEQ) do
        M.keys = k
        frames(1)
        out[#out + 1] = tick_buttons()
    end
    M.keys = 0
    frames(1)
    return table.concat(out, ",")
end
GSA1.Spawn("tails")
local CT = GSA1.Char
R.st[CT.id].mode, R.st[CT.id].rings = 8, 99
local seq_t = sequence(CT)
local real_filter = GSA1.FilterButtons
GSA1.FilterButtons = function(_, b) return b end
local identity = sequence(CT)
GSA1.FilterButtons = real_filter
RunConsoleCommand("gsa1_super_transform", "0")
GSA1.Spawn("sonic")
local CP = GSA1.Char
R.st[CP.id].mode, R.st[CP.id].rings = 8, 99
local seq_p = sequence(CP)
RunConsoleCommand("gsa1_super_transform", "1")
check(seq_t == identity and seq_p == seq_t and #calls_of("SuperOrder", CT.id) == 0 and #calls_of("SuperOrder", CP.id) == 0
    and CP.extras == nil, "RC3: Tails and a plain Sonic (transformation off) in mode 8 with 99 rings: the same buttons bit "
    .. "for bit (%s), no order", seq_t)
-- a failing filter never stops a tick
local fb = GSA1.FilterButtons
GSA1.FilterButtons = function() error("broken filter") end
frames(2)
GSA1.FilterButtons = fb
check(GSA1.Char ~= nil and log_has("GSA1.FilterButtons: .*broken filter"), "an error in GSA1.FilterButtons: logged, the "
    .. "tick goes on")

-- 5. Super Sonic (General Gameplay) ---------------------------------------------------------------------------------------------
frames(30)
GSA1.Spawn("supersonic_general")
C = GSA1.Char
cr = last_call("Create")
check(C and C.kind == 0 and C.name == "supersonic_general" and C.form == "general" and
    C.title == "Super Sonic (General Gameplay)" and cr[3] == 0 and cr[5].create_flags == 0x800 and cr[5].super_flags == 0x70
    and cr[5].start_rings == 50 and M.convars.gsa1_character.v == "supersonic_general",
    "spawn Super Sonic (General Gameplay): gsa1.Create(0, ..., extras {0x800, GENERAL | START | WATER_WHILE_SUPER 0x70, "
    .. "50 rings}), the entry kept (C.def)")
local function opt_of(list, opt)
    for i = #list, 1, -1 do if list[i][3] == opt then return list[i][4] end end
    return nil
end
local sog, gog = calls_of("SuperOption", C.id), calls_of("SuperGameOption", C.id)
check(opt_of(sog, 1) == 1 and opt_of(sog, 2) == 0 and opt_of(sog, 4) == 3 and opt_of(sog, 3) == 0 and opt_of(gog, 2) == 1
    and opt_of(gog, 3) == 1 and opt_of(sog, 5) == 1 and opt_of(sog, 6) == 1, "his options before the first tick: Super "
    .. "run (1), the aura (no-aura 0), the golden effects (0.9.4a: 3 = CLONES | DUST), no libsa1 voice tone (the clip is "
    .. "G-SA1's), idle voices by form, the calm aura; 0.9.4a: the Super poses (5 = 1) and the golden Light Speed (6 = 1)")
frames(2)
local sg = R.st[C.id]
sg.super, sg.changes, sg.change_step, sg.rings, sg.mode = true, 1, 2, 50, 12
frames(2)
check(C.superForm and log_has("Super Sonic %(General Gameplay%) turned Super %(the start %(Super from his first pair%)%)"),
    "Super from his first pair: the log names the start")
-- options at once: no re-creation
local ncr = #calls_of("Create")
RunConsoleCommand("gsa1_super_general_speed", "0")
RunConsoleCommand("gsa1_super_general_aura", "0")
RunConsoleCommand("gsa1_super_general_effects", "0")
RunConsoleCommand("gsa1_super_voice", "1121")
RunConsoleCommand("gsa1_super_aura_anim", "2")
RunConsoleCommand("gsa1_super_idle_by_form", "0")
frames(30)
sog, gog = calls_of("SuperOption", C.id), calls_of("SuperGameOption", C.id)
check(#calls_of("Create") == ncr and GSA1.Char == C and opt_of(sog, 1) == 0 and opt_of(sog, 2) == 1 and opt_of(sog, 4) == 0
    and opt_of(sog, 3) == 1121 and opt_of(gog, 3) == 2 and opt_of(gog, 2) == 0,
    "speed, aura, golden effects, voice, aura animation, idle voices changed: applied at once (SuperOption / "
    .. "SuperGameOption), no re-creation")
for name, v in pairs({ gsa1_super_general_speed = "1", gsa1_super_general_aura = "1", gsa1_super_general_effects = "1",
                       gsa1_super_voice = "4492", gsa1_super_aura_anim = "1", gsa1_super_idle_by_form = "1" }) do
    RunConsoleCommand(name, v)
end
sog = calls_of("SuperOption", C.id)
check(opt_of(sog, 4) == 3, "the golden effects back on: 3 again (CLONES | DUST)")
-- 0.9.4a: the Super poses and the golden Light Speed Dash apply at once - one SuperOption per change - for the General
-- entry and a Sonic who can transform; never for kind 8
local function opt_calls(id, opt)
    local n, last = 0, nil
    for _, c in ipairs(calls_of("SuperOption", id)) do
        if c[3] == opt then n, last = n + 1, c[4] end
    end
    return n, last
end
local function toggle_counts(id)
    local a0, l0 = opt_calls(id, 5), select(1, opt_calls(id, 6))
    RunConsoleCommand("gsa1_super_general_anims", "0")
    RunConsoleCommand("gsa1_super_general_lsd_gold", "0")
    frames(10)
    local a1, av = opt_calls(id, 5)
    local l1, lv = opt_calls(id, 6)
    RunConsoleCommand("gsa1_super_general_anims", "1")
    RunConsoleCommand("gsa1_super_general_lsd_gold", "1")
    frames(10)
    local a2, av2 = opt_calls(id, 5)
    local l2, lv2 = opt_calls(id, 6)
    return a1 - a0, av, l1 - l0, lv, a2 - a1, av2, l2 - l1, lv2
end
do
    local n1, v1, m1, w1, n2, v2, m2, w2 = toggle_counts(C.id)
    check(#calls_of("Create") == ncr and n1 == 1 and v1 == 0 and m1 == 1 and w1 == 0 and n2 == 1 and v2 == 1 and m2 == 1 and
        w2 == 1, "the General entry: \"Super Sonic's own poses\" and \"Golden Light Speed Dash\" off and on - one "
        .. "SuperOption(5) and one SuperOption(6) per change (0, then 1), applied at once, no re-creation")
end-- the drain option re-creates him where he stands with his form (RC1): Super -> START again
RunConsoleCommand("gsa1_super_general_drain", "0")
frames(30)
cr = last_call("Create")
local CG = GSA1.Char
check(#calls_of("Create") == ncr + 1 and CG ~= C and CG.name == "supersonic_general" and cr[5].super_flags == 0x71 and
    cr[5].start_rings == 0, "\"Lose a ring every second\" off while Super: re-created where he stands as the General entry "
    .. "with NO_DRAIN and START (0x71: he was Super), his rings carried over")
RunConsoleCommand("gsa1_super_general_drain", "1")
frames(30)
-- turned back, then re-created (an upgrade): no START (RC1)
C = GSA1.Char
R.st[C.id].super, R.st[C.id].changes, R.st[C.id].rings = true, 1, 3
frames(2)
R.st[C.id].super, R.st[C.id].changes, R.st[C.id].rings = false, 2, 0
frames(2)
RunConsoleCommand("gsa1_upgrade_light_speed_shoes", "1")
frames(30)
cr = last_call("Create")
check(GSA1.Char.name == "supersonic_general" and cr[5].super_flags == 0x50 and type(cr[6]) == "table" and
    cr[6][1] == "light_speed_shoes", "turned back at 0 rings, then an upgrade ticked: re-created normal (0x50, no START), "
    .. "with Sonic's upgrade")
-- a respawn (death) brings the General entry back Super (START)
GSA1.Respawn("a test")
cr = last_call("Create")
check(GSA1.Char.name == "supersonic_general" and GSA1.Char.form == "general" and cr[5].super_flags == 0x70 and
    cr[5].start_rings == 50, "a respawn keeps the entry: Super Sonic (General Gameplay) again, Super from the start with 50 "
    .. "rings")
RunConsoleCommand("gsa1_upgrade_light_speed_shoes", "0")
frames(30)
-- the voice Preview (the page's button and the command); the transformations above played the clip too (0.9.3b)
local pv0, pc0 = #calls_of("SuperVoicePreview"), #calls_of("SuperVoiceClip")
M.cmds.gsa1_super_voice_preview(nil, "gsa1_super_voice_preview", {}, "")
M.cmds.gsa1_super_voice_preview(nil, "gsa1_super_voice_preview", { "1126" }, "1126")
if preview_button then preview_button.DoClick() end
local pv, pc = calls_of("SuperVoicePreview"), calls_of("SuperVoiceClip")
pv, pc = { unpack(pv, pv0 + 1) }, { unpack(pc, pc0 + 1) }
check(#pv == 1 and pv[1][2] == 1126 and #pc == 2 and pc[1][2] == 396 and pc[1][3] == GSA1.Char.id and pc[2][2] == 396,
    "the voice Preview: gsa1_super_voice_preview plays the chosen voice (Super Sonic's clip 396) or the tone given "
    .. "(1126); the page's button too (%d tone, %d clip calls)", #pv, #pc)
-- 0.9.3b: a SUPER order plays the chosen clip once (libsa1 gets no tone); a chosen tone is libsa1's (no clip call)
do
    local CV = GSA1.Char
    local sv = R.st[CV.id]
    sv.super, sv.rings, sv.mode = false, 60, 8
    frames(4)
    local c0 = #calls_of("SuperVoiceClip")
    local okS = S.OrderForm(CV, "super", "test", sv)
    local pc1 = calls_of("SuperVoiceClip")
    frames(4)
    local okN = S.OrderForm(CV, "normal", "test", sv)
    RunConsoleCommand("gsa1_super_voice", "1116")
    frames(4)
    local okS2 = S.OrderForm(CV, "super", "test", sv)
    local so = calls_of("SuperOption", CV.id)
    check(okS and okN and okS2 and #pc1 == c0 + 1 and pc1[#pc1][2] == 396 and pc1[#pc1][3] == CV.id and
        #calls_of("SuperVoiceClip") == c0 + 1 and opt_of(so, 3) == 1116,
        "a SUPER order with Super Sonic's \"Hm!\" chosen: clip 396 once, as his own voice; turning back: none; with tone "
        .. "1116 chosen: libsa1's tone (SuperOption 3 = 1116), no clip")
    RunConsoleCommand("gsa1_super_voice", "4492")
    frames(4)
    -- an order while the state already says Super plays no clip (review 0.9.3b, 1); an old module without SuperVoiceClip:
    -- PlayVoice answers nil + a message, no error
    sv.super = true
    local c1 = #calls_of("SuperVoiceClip")
    local okD = S.OrderForm(CV, "super", "test", sv)
    sv.super = false
    local keep = G.SuperVoiceClip
    G.SuperVoiceClip = nil
    local okO, errO = S.PlayVoice(4492, CV.id)
    G.SuperVoiceClip = keep
    check(okD and #calls_of("SuperVoiceClip") == c1 and okO == nil and type(errO) == "string" and
        string.find(errO, "0.9.3b", 1, true) ~= nil, "no clip for an order while he is already Super; an older module: "
        .. "PlayVoice says it needs 0.9.3b (%s)", tostring(errO))
    frames(4)
    -- the one-time move of a saved 1116 (0.9.3a's default) to the new default
    local jar = {}
    local old_cookie = cookie
    cookie = { GetNumber = function(k, d) return tonumber(jar[k]) or d end, Set = function(k, v) jar[k] = v end }
    RunConsoleCommand("gsa1_super_voice", "1116")
    local m1 = S.MigrateVoice()
    local v1 = M.convars.gsa1_super_voice.v
    RunConsoleCommand("gsa1_super_voice", "1116")
    local m2 = S.MigrateVoice()
    local v2 = M.convars.gsa1_super_voice.v
    cookie = old_cookie
    RunConsoleCommand("gsa1_super_voice", "4492")
    check(m1 == true and v1 == "4492" and m2 == false and v2 == "1116", "a saved 1116 becomes Super Sonic's \"Hm!\" once "
        .. "(%s %s, then %s %s: a later choice of 1116 stays)", tostring(m1), tostring(v1), tostring(m2), tostring(v2))
    -- 0.9.4b: a saved 128 (the right stick click, 0.9.4a's default) becomes none once; a later choice of it stays; another
    -- saved button is never touched
    jar = {}
    cookie = { GetNumber = function(k, d) return tonumber(jar[k]) or d end, Set = function(k, v) jar[k] = v end }
    RunConsoleCommand("gsa1_super_pad", "128")
    local p1 = S.MigratePad()
    local pv1 = M.convars.gsa1_super_pad.v
    RunConsoleCommand("gsa1_super_pad", "128")
    local p2 = S.MigratePad()
    local pv2 = M.convars.gsa1_super_pad.v
    jar = {}
    RunConsoleCommand("gsa1_super_pad", "32768")
    local p3 = S.MigratePad()
    local pv3 = M.convars.gsa1_super_pad.v
    local cookie_set = jar.gsa1_super_pad_094b ~= nil
    cookie = old_cookie
    RunConsoleCommand("gsa1_super_pad", "0")
    local first = S.PAD_BUTTONS[1]
    check(p1 == true and pv1 == "0" and p2 == false and pv2 == "128" and p3 == false and pv3 == "32768" and cookie_set and
        S.PAD_DEFAULT == 0 and first[1] == 0 and first[2] == "None",
        "0.9.4b: a saved 128 (the right stick click) becomes none once (%s %s, then %s %s: a later choice stays); another "
        .. "saved button (Y) stays (%s); the default is none and \"None\" is the page's first choice", tostring(p1), pv1,
        tostring(p2), pv2, pv3)
end

-- 6. music while Super ---------------------------------------------------------------------------------------------------------
local P = GSA1.JukeboxPlayer
GSA1.Spawn("supersonic")
C = GSA1.Char
RunConsoleCommand("gsa1_super_music", "1")
frames(2)
check(#calls_of("JukeboxPlay") == 0, "music on, not Super yet: nothing plays")
-- the personal jukebox plays a track
P.Play(28)
frames(1)
R.st[C.id].super, R.st[C.id].changes = true, 1
frames(3)
local jp = calls_of("JukeboxPlay")
local pause = calls_of("JukeboxPause")
check(#jp == 2 and jp[2][2] == 2 and jp[2][3] == 86 and jp[2][5] == "forever" and #pause >= 1 and pause[1][2] == 0 and
    pause[1][3] == true and log_has("music 86 SPRSONIC.ADX plays while Super %(channel 2%); the personal jukebox is paused"),
    "Super with \"Theme of Super Sonic\": JukeboxPlay(2, 86, ..., \"forever\") once, the personal jukebox paused (channel 0)")
frames(10)
check(#calls_of("JukeboxPlay") == 2, "it plays on (no new play every frame)")
R.st[C.id].super = false
frames(2)
local js = calls_of("JukeboxStop")
pause = calls_of("JukeboxPause")
check(#js >= 1 and js[#js][2] == 2 and pause[#pause][2] == 0 and pause[#pause][3] == false,
    "back to normal Sonic: JukeboxStop(2), the personal jukebox goes on")
-- yours wins: the personal jukebox started while the Super music plays
R.st[C.id].super = true
frames(2)
local plays = #calls_of("JukeboxPlay")
P.Pause(false)
P.Play(23)
frames(2)
js = calls_of("JukeboxStop")
frames(5)
check(js[#js][2] == 2 and #calls_of("JukeboxPlay") == plays + 1 and S.music.yielded,
    "you start the personal jukebox while the Super music plays: the Super music stops and stays off")
P.Stop(0)
R.st[C.id].super = false
frames(2)
RunConsoleCommand("gsa1_super_music", "0")
R.st[C.id].super = true
frames(3)
check(#calls_of("JukeboxPlay") == plays + 1, "music off: nothing plays")
R.st[C.id].super = false
frames(2)

-- 7. the pre-warm census ------------------------------------------------------------------------------------------------------
local W, T = GSA1.Warm, GSA1.Tex
local n8 = #(GSA1.WarmCensus[8] or {})
check(n8 > 200, "GSA1.WarmCensus[8] made when Super Sonic was created: %d rows", n8)
local function warmed(kind)
    local names = {}
    for _, s in ipairs(W.States(kind)) do
        if not s.depth then names[T.Material(kind, s, true):GetName()] = true end
    end
    return names
end
if not census_text then
    info("no material_census_super.txt (feat_super_test.cpp writes it with the disc): the census checks are skipped")
else
    S.ApplyWarm(8)
    S.ApplyWarm(0)
    local w = { [8] = warmed(8), [0] = warmed(0) }
    local total, exact, miss = 0, 0, {}
    for line in string.gmatch(census_text, "[^\n]+") do
        local k, a, t, f, s, d, wr, p = string.match(line, "^(%d+) (%-?%d+) (%-?%d+) (%x+) (%d+) (%d+) (%d+) (%d+)")
        if k then
            k, a, t, f, s, d, wr, p = tonumber(k), tonumber(a), tonumber(t), tonumber(f, 16), tonumber(s), tonumber(d),
                tonumber(wr), tonumber(p)
            total = total + 1
            local b = { key = string.format("%d.%d.%X.%d.%d.%d.%d", a, t, f, s, d, wr, p), archive = a, tex = t, flags = f,
                        src = s, dst = d, wrap = wr, pass = p }
            local name = T.Material(k, b):GetName()
            if w[k][name] then exact = exact + 1 else miss[#miss + 1] = line end
        end
    end
    check(total > 100 and exact == total, "every state of the census (%d lines: Vs. Perfect Chaos and the General form) has "
        .. "its exact material warmed%s", total, #miss > 0 and ("; missing: " .. table.concat(miss, "; ", 1,
        math.min(#miss, 5))) or "")
    -- normal Sonic's core census on Super Sonic's SONIC archive (4), every SUPERSONIC effect texture
    local son, ss = S.ArchiveIndex(T.Archives(8), "SONIC"), S.ArchiveIndex(T.Archives(8), "SUPERSONIC")
    local core_ok, fx = 0, 0
    for _, r in ipairs(S.coreSonic) do
        if r[1] == 0 then
            local b = { key = string.format("%d.%d.%X.%d.%d.%d.%d", son, r[2], r[3], r[4], r[5], r[6], r[7]), archive = son,
                        tex = r[2], flags = r[3], src = r[4], dst = r[5], wrap = r[6], pass = r[7] }
            if w[8][T.Material(8, b):GetName()] then core_ok = core_ok + 1 end
        end
    end
    local ncore = 0
    for _, r in ipairs(S.coreSonic) do if r[1] == 0 then ncore = ncore + 1 end end
    for t = 32, 47 do
        local b = { key = string.format("%d.%d.%X.4.1.3.1", ss, t, 0x275), archive = ss, tex = t, flags = 0x275, src = 4,
                    dst = 1, wrap = 3, pass = 1 }
        if w[8][T.Material(8, b):GetName()] then fx = fx + 1 end
    end
    check(ncore > 10 and core_ok == ncore and fx == 16, "Super Sonic's pre-warm has normal Sonic's %d body states on his "
        .. "SONIC archive (%d) and the SUPERSONIC effect textures the census did not see (32-47: %d)", ncore, son, fx)
    local base = #S.Dedupe(S.MapRows(S.coreSonic, S.CORE_NAMES, T.Archives(0)))
    RunConsoleCommand("gsa1_super_transform", "0")
    S.ApplyWarm(0)
    local off = #GSA1.WarmCensus[0]
    S.ApplyWarm(0, { def = GSA1.CharacterByName("supersonic_general") })
    local general = #GSA1.WarmCensus[0]
    RunConsoleCommand("gsa1_super_transform", "1")
    S.ApplyWarm(0)
    local on = #GSA1.WarmCensus[0]
    check(off == base and on > off + 100 and general == on, "Sonic's census: the core's %d rows with the transformation "
        .. "off, %d with it on; the General entry %d whatever the switch says", off, on, general)
end

-- 7b. round 0.9.4a (super2_plan.md 6.4 with its review, 10.1 and 10.3) ----------------------------------------------------------
-- the golden Light Speed charge's census rows (review R.2): SON_EFF lcharge01 / 02 with WRAP_GOLD, given by S.WarmRows to the
-- General entry and a Sonic who can transform only, mapped by name (0.9.3a's only = "SUPERSONIC" filter drops them)
do
    local T0 = GSA1.Tex
    local gold, tex = 0, {}
    for _, r in ipairs(S.CENSUS[0] or {}) do
        if bit.band(r[6] or 0, 0x10) ~= 0 then
            gold = gold + 1
            if S.CENSUS_NAMES[0][r[1]] == "SON_EFF" then tex[r[2]] = true end
        end
    end
    local gold8 = 0
    for _, r in ipairs(S.CENSUS[8] or {}) do
        if bit.band(r[6] or 0, 0x10) ~= 0 then gold8 = gold8 + 1 end
    end
    check(gold >= 2 and tex[25] and tex[26] and not tex[27] and not tex[28] and gold8 == 0,
        "S.CENSUS[0] has the golden Light Speed rows (wrap & 0x10): SON_EFF lcharge01 (25) and lcharge02 (26), none of "
        .. "the Crystal Ring's lcharge03 / 04 (owner answer O3); kind 8 none (%d / %d rows)", gold, gold8)
    local A0 = T0.Archives(0)
    local eff = S.ArchiveIndex(A0, "SON_EFF")
    local function gold_of(rows)
        local n = 0
        for _, r in ipairs(rows or {}) do
            if r[1] == eff and bit.band(r[6] or 0, 0x10) ~= 0 then n = n + 1 end
        end
        return n
    end
    local with = S.WarmRows(0, A0, S.CENSUS, S.CENSUS_NAMES, S.coreSonic, S.CORE_NAMES, true)
    local without = S.WarmRows(0, A0, S.CENSUS, S.CENSUS_NAMES, S.coreSonic, S.CORE_NAMES, false)
    local k8rows = S.WarmRows(8, T0.Archives(8), S.CENSUS, S.CENSUS_NAMES, S.coreSonic, S.CORE_NAMES)
    local k8gold = 0
    for _, r in ipairs(k8rows or {}) do
        if bit.band(r[6] or 0, 0x10) ~= 0 then k8gold = k8gold + 1 end
    end
    local old = S.MapRows(S.CENSUS[0], S.CENSUS_NAMES[0], A0, {}, "SUPERSONIC")
    check(eff ~= nil and gold_of(with) == gold and gold_of(without) == 0 and k8gold == 0 and gold_of(old) == 0,
        "S.WarmRows: the %d golden rows for a Sonic with his Super forms (the General entry, the transformation), mapped to "
        .. "SON_EFF (%s) by name; none for plain Sonic or kind 8; 0.9.3a's SUPERSONIC-only mapping would drop them (%d)",
        gold_of(with), tostring(eff), gold_of(old))
    RunConsoleCommand("gsa1_super_transform", "0")
    S.ApplyWarm(0)
    local plain = gold_of(GSA1.WarmCensus[0])
    S.ApplyWarm(0, { def = GSA1.CharacterByName("supersonic_general") })
    local general = gold_of(GSA1.WarmCensus[0])
    RunConsoleCommand("gsa1_super_transform", "1")
    S.ApplyWarm(0)
    local transform = gold_of(GSA1.WarmCensus[0])
    frames(30)
    check(plain == 0 and general == gold and transform == gold, "the pre-warm census: plain Sonic (transformation off) "
        .. "without the golden rows, the General entry and a Sonic who can transform with them (%d / %d / %d)", plain, general,
        transform)
    -- their materials are made by the pre-warm (the golden variant's render target: gsa1.Texture(0, 25, 1, 1))
    local n0 = #calls_of("Texture")
    for _, r in ipairs(GSA1.WarmCensus[0]) do
        if bit.band(r[6] or 0, 0x10) ~= 0 then
            local b = { key = string.format("%d.%d.%X.%d.%d.%d.%d", r[1], r[2], r[3], r[4], r[5], r[6], r[7]), archive = r[1],
                        tex = r[2], flags = r[3], src = r[4], dst = r[5], wrap = r[6], pass = r[7] }
            T0.Material(0, b, true)
        end
    end
    local asked = {}
    for _, c in ipairs({ unpack(calls_of("Texture"), n0 + 1) }) do
        if c[5] == 1 then asked[c[3]] = true end
    end
    for _, c in ipairs(calls_of("Texture")) do
        if c[5] == 1 then asked[c[3]] = true end
    end
    check(asked[25] and asked[26], "the golden rows' render targets take gsa1.Texture(0, 25 / 26, SON_EFF, 1): the variant")
    -- review R.6: a gold batch whose variant the module refuses draws the game's own texture (never vgui/white), one log
    -- line; the golden one keeps the variant's pixels
    local e_ref = T0.Get(0, 1, 3, 0x13, false)
    local e_gold = T0.Get(0, 1, 25, 0x13, false)
    check(e_ref and not e_ref.gold and e_ref.info and e_ref.info.name == "tex1_3" and
        log_has("texture 3 of archive 1 of character 0 has no golden variant %(no variant%): its gold draws use the game's "
        .. "texture") and e_gold and e_gold.gold and e_gold.info.name == "tex1_25_gold",
        "a gold batch whose variant is refused: the game's texture in its render target and one log line (review R.6); "
        .. "lcharge01's draws the variant")
end

-- the Super poses and the golden Light Speed Dash for a Sonic who can transform (a General world), never for kind 8
do
    GSA1.Spawn("sonic")
    frames(5)
    local CS = GSA1.Char
    local before5, before6 = 0, 0
    for _, c in ipairs(calls_of("SuperOption", CS.id)) do
        if c[3] == 5 then before5 = before5 + 1 end
        if c[3] == 6 then before6 = before6 + 1 end
    end
    local n1, v1, m1, w1, n2, v2, m2, w2 = toggle_counts(CS.id)
    check(CS.kind == 0 and R.st[CS.id].general and before5 == 1 and before6 == 1 and n1 == 1 and v1 == 0 and m1 == 1 and
        w1 == 0 and n2 == 1 and v2 == 1 and m2 == 1 and w2 == 1,
        "a Sonic who can transform (a General world): the poses and the golden Light Speed set at his creation and once per "
        .. "change")
    GSA1.Spawn("supersonic")
    frames(5)
    local C8 = GSA1.Char
    toggle_counts(C8.id)
    local k8 = 0
    for _, c in ipairs(calls_of("SuperOption", C8.id)) do
        if c[3] == 5 or c[3] == 6 then k8 = k8 + 1 end
    end
    check(C8.kind == 8 and k8 == 0, "Super Sonic (Vs. Perfect Chaos): no SuperOption 5 / 6 at his creation or at a change "
        .. "(%d calls): he is the game's own Super Sonic", k8)
end

-- the aura's whoosh: gsa1.SuperWhoosh at the module's load and at every change; the page's status line; the Preview
do
    local all = calls_of("SuperWhoosh")
    local first_create, first_whoosh = nil, nil
    for i, c in ipairs(R.calls) do
        if c[1] == "Create" and not first_create then first_create = i end
        if c[1] == "SuperWhoosh" and not first_whoosh then first_whoosh = i end
    end
    check(#all >= 1 and all[1][2] == true and first_whoosh ~= nil and first_create ~= nil and first_whoosh < first_create,
        "the module's load applies \"Aura whoosh sounds\": gsa1.SuperWhoosh(true) before the first character is made")
    local n0 = #all
    RunConsoleCommand("gsa1_super_whoosh", "0")
    frames(2)
    local off = calls_of("SuperWhoosh")
    RunConsoleCommand("gsa1_super_whoosh", "1")
    frames(2)
    local on = calls_of("SuperWhoosh")
    check(#off == n0 + 1 and off[#off][2] == false and #on == n0 + 2 and on[#on][2] == true and
        log_has("the aura's whoosh off %(gsa1_super_whoosh = 0, applied at once%)"),
        "a change of \"Aura whoosh sounds\" calls gsa1.SuperWhoosh once (false, then true), logged")
    -- the status line for every bank state, the option off and a module without stage rules
    local function first_line()
        local okl, lines = pcall(S.StatusLines)
        return okl and type(lines) == "table" and tostring(lines[1]) or ""
    end
    local want = {
        ready = "the aura's whoosh: played (Perfect Chaos sound bank: ready)",
        loading = "the aura's whoosh: played (Perfect Chaos sound bank: loading)",
        failed = "the aura's whoosh: could not be read from the disc: silent",
        absent = "the aura's whoosh: played (Perfect Chaos sound bank: read when a Super Sonic appears)",
        closed = "the aura's whoosh: played (Perfect Chaos sound bank: read when the sound banks are open)",
    }
    local okst = 0
    for bank, text in pairs(want) do
        R.bank = bank
        if string.find(first_line(), text, 1, true) then okst = okst + 1 end
    end
    R.bank = "ready"
    RunConsoleCommand("gsa1_super_whoosh", "0")
    local offline = string.find(first_line(), "the aura's whoosh: off", 1, true) ~= nil
    RunConsoleCommand("gsa1_super_whoosh", "1")
    R.rules = false
    local norules = string.find(first_line(), "kept silent (this module's libsa1 has no stage rules)", 1, true) ~= nil
    R.rules = nil
    check(okst == 5 and offline and norules, "the page's whoosh status: played (ready / loading / read later), could not "
        .. "be read, off, kept silent without stage rules (%d of 5 bank states)", okst)
    -- the Preview: 1035 as the Super-capable character's own sound; without one the status says why, no chat line
    local chats = 0
    local add_text = chat.AddText
    chat.AddText = function(...) chats = chats + 1 end
    local p0 = #calls_of("SuperVoicePreview")
    if whoosh_button then whoosh_button.DoClick() end
    local pv = calls_of("SuperVoicePreview")
    local played = #pv == p0 + 1 and pv[#pv][2] == 1035 and pv[#pv][3] == GSA1.Char.id
    GSA1.Spawn("tails")
    frames(3)
    local p1 = #calls_of("SuperVoicePreview")
    M.cmds.gsa1_super_whoosh_preview(nil, "gsa1_super_whoosh_preview", {}, "")
    local okl, lines = pcall(S.StatusLines)
    local text = okl and table.concat(lines, " ") or ""
    chat.AddText = add_text
    check(played and #calls_of("SuperVoicePreview") == p1 and chats == 0 and
        string.find(text, "whoosh preview: no Super Sonic to play it", 1, true) ~= nil,
        "the whoosh Preview: SuperVoicePreview(1035, id) for Super Sonic; with Tails nothing is played, the page's status "
        .. "says why, no chat line (%d)", chats)
end

-- the rings' "no pile-up" (super2_plan.md 10.3): the Sound page's checkbox, gsa1.AudioSettings' 9th argument
do
    local c = M.convars.gsa1_sound_no_stack
    local snd
    for _, e in ipairs(M.menu) do
        if e.class == "gsa1_sound" then snd = e end
    end
    local bound = false
    if snd then
        made = {}
        local panel = standin("DForm")
        pcall(snd.cpanel, panel)
        for _, P in ipairs(made) do
            for _, k in ipairs(P.calls) do
                if k[1] == "CheckBox" and k[3] == "gsa1_sound_no_stack" and k[2] == "Rings don't pile up" then bound = true end
            end
        end
    end
    local n0 = #calls_of("AudioSettings")
    GSA1.ApplyAudioSettings()
    local a1 = calls_of("AudioSettings")
    RunConsoleCommand("gsa1_sound_no_stack", "0")
    local a2 = calls_of("AudioSettings")
    RunConsoleCommand("gsa1_sound_no_stack", "1")
    check(c and c.v == "1" and c.client and c.save and bound and #a1 == n0 + 1 and a1[#a1][10] == true and #a2 == n0 + 2 and
        a2[#a2][10] == false, "\"Rings don't pile up\" (gsa1_sound_no_stack, default 1) on the Sound page; "
        .. "gsa1.AudioSettings gets it as its 9th argument (true, then false at once)")
end

-- 8. a failing CreateExtras never stops a spawn -------------------------------------------------------------------------------
local ce = GSA1.CreateExtras
GSA1.CreateExtras = function() error("broken extras") end
GSA1.Spawn("amy")
GSA1.CreateExtras = ce
check(GSA1.Char and GSA1.Char.kind == 5 and last_call("Create")[5] == nil and
    log_has("GSA1.CreateExtras: .*broken extras"), "an error in GSA1.CreateExtras: logged, Amy made without extras")
-- the status lines
GSA1.Spawn("sonic")
R.st[GSA1.Char.id].rings = 12
local okl, lines = pcall(S.StatusLines)
local text = okl and table.concat(lines, " ") or ""
check(okl and type(lines) == "table" and #lines >= 3 and string.find(text, "Super Sonic in the character list: yes", 1, true)
    ~= nil and string.find(text, "the General form", 1, true) ~= nil and string.find(text, "needs 50 rings: 12 now", 1, true)
    ~= nil, "the page's status lines: the form and \"needs 50 rings: 12 now\" (%s)", okl and tostring(lines[2]) or
    tostring(lines))
-- 0.9.3a verifier: a second form order within one game step is held back (gesture back, then G at once)
do
    local CG = GSA1.Char
    local sg = R.st[CG.id]
    sg.rings, sg.mode = 60, 8
    frames(4)
    local n0 = #calls_of("SuperOrder", CG.id)
    local okA = S.OrderForm(CG, "super", "test", sg)
    frames(1)
    local okB = S.OrderForm(CG, "normal", "test", sg)
    frames(3)
    local okC = S.OrderForm(CG, "normal", "test", sg)
    check(okA == true and okB ~= true and okC == true and #calls_of("SuperOrder", CG.id) == n0 + 2, "two orders one frame "
        .. "apart: the second is held back until a game step has passed (%s %s %s, %d orders)", tostring(okA), tostring(okB),
        tostring(okC), #calls_of("SuperOrder", CG.id) - n0)
end
check(#R.bad == 0 and #M.reported == 0, "no call the module would refuse (%s), no Lua error reported (%s)",
    table.concat(R.bad, " "), tostring(M.reported[1]))
return done()
