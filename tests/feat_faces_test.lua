-- feat_faces_test.lua - the event faces' addon side (round 0.9.4a: addon/lua/gsa1/feat/sh_faces.lua and cl_faces.lua;
-- sadc docs/research/faces_wheel_plan.md 6.4 with its Review R.2 / R.6 / R.10 / R.19) in Garry's Mod's own LuaJIT with a
-- mocked GMod (tests/lua_mock.lua) and a mock of the module's feature "faces" 1 (bind_faces.cpp: every call recorded, the
-- arguments checked). The stubs of this test live here (lua_mock.lua is not changed): input.*, the player's IsSpeaking /
-- VoiceVolume / IsTyping, the vgui controls of the page, the Face* / Mic* functions. Checks:
--   (1) every gsa1_face* / gsa1_lipsync* setting with its default and range, each bound to a control on the "Faces" page;
--   (2) the switch: gsa1.FaceMode(id, true / false, pace) once when it changes, for a new character only while it is on
--       (review R.6), never for E-102 or the Super Sonics;
--   (3) the library: the defaults without a file, a save / load round trip, rename and delete fire GSA1FaceLibraryChanged
--       with the change table, bad lines counted, unique names, 32 entries at most, the mirror gsa1_face_summary;
--   (4) the maker: double-click appends {letter, 0, 0}, Up / Down / Remove, the number fields clamp, the total line, the
--       32nd entry refused while it blends back (review R.10) and a 32-entry file line loaded without the blend, Big's
--       expression list = the module's 14, Preview of "Happy" = FaceSequence(id, "b:10:90,A:8:0", 0) and with "keep the
--       last face" "b:10:90" with HOLD_LAST;
--   (5) GSA1.Faces.Play / CanShow / Stop (Big + "Happy": "Big can't show b");
--   (6) the hotkeys: once per press, a second press lets a kept face go, nothing while typing or in a menu;
--   (7) lip sync from Garry's Mod's voice: FaceLevel = F.Smooth's values, exactly one -1 after the hang, then no call
--       (review R.6); nothing with gsa1_lipsync 0, one -1 when it is switched off while talking;
--   (8) automatic: no voice level from Garry's Mod for 0.5 s with the talk key held -> MicOpen once, MicListen(true) while
--       held and (false) on release; never opened without the key; one log line per decision;
--   (9) E-102: no Face* call ever; the page says "E-102 has no face in the game".
--   lua_host tests/feat_faces_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_faces_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_faces%.lua$") then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end

-- the mock module with the feature "faces" ---------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ features = { faces = 1 } })
local R = { calls = {}, bad = {}, mic = { open = false, listen = false, level = 0, opens = 0 } }
local function rec(name, ...) R.calls[#R.calls + 1] = { name, ... } end
local function calls_of(name, id)
    local out = {}
    for _, c in ipairs(R.calls) do
        if c[1] == name and (id == nil or c[2] == id) then out[#out + 1] = c end
    end
    return out
end
local function count_calls(prefix, id)
    local n = 0
    for _, c in ipairs(R.calls) do
        if string.sub(c[1], 1, #prefix) == prefix and (id == nil or c[2] == id) then n = n + 1 end
    end
    return n
end
local function int_in(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end
G.FACE = { MODE_GAME = 0, MODE_EVENT = 1, PACE_CUTSCENE = 0x100, NOW = 1, LOOP = 2, HOLD_LAST = 4, LEVEL_LADDER = 0,
           LEVEL_TALK = 1, ACT_NONE = 0, ACT_SEQUENCE = 1, ACT_SCRIPT = 2, ACT_HELD = 3, ACT_LIPSYNC = 4,
           ACT_GAMEPLAY = 5, SEQ_MAX = 32, HOLD_MAX = 3600, ENTER_MAX = 127 }
local kinds = {}
local create = G.Create
function G.Create(kind, pos, yaw, ups, rings, extras)
    local id = create(kind, pos, yaw, ups, rings)
    kinds[id] = kind
    rec("Create", id, kind)
    return id
end
R.infoCalls = 0
function G.FaceInfo(kind)
    R.infoCalls = R.infoCalls + 1
    if not int_in(kind, 0, 8) then return nil, "FaceInfo(kind)", "bad_argument" end
    local letters = (kind == 0 or kind == 2 or kind == 3 or kind == 4 or kind == 5) and 0x7FFFFFFF or
        (kind == 7 and 0x01FC0C1F or 0)
    local t = { has_face = letters ~= 0, keys = letters ~= 0 and 20 or 0, letters = letters, ladder = "0,5,4,6,7",
                ladder_len = 5, steps = {}, first = {}, last = {} }
    for i = 0, 30 do t.steps[i], t.first[i], t.last[i] = 16, 4, 0 end
    t.steps[27], t.first[27] = 10, 10         -- 'b': one step of 10 frames (the plan's "enter 10 + plays 0 + hold 90")
    return t
end
local function face_id(id)
    return kinds[id] ~= nil and kinds[id] ~= 6 and kinds[id] ~= 8
end
function G.FaceMode(id, ev, pace)
    rec("FaceMode", id, ev, pace)
    if not (int_in(id, 1, 1e9) and type(ev) == "boolean" and type(pace) == "boolean") then
        R.bad[#R.bad + 1] = "FaceMode"
        return nil, "FaceMode(id, event, pace)", "bad_argument"
    end
    if not face_id(id) then return nil, "no face", "unsupported" end
    return true
end
function G.FaceSequence(id, spec, flags)
    rec("FaceSequence", id, spec, flags)
    if not (int_in(id, 1, 1e9) and type(spec) == "string" and (flags == 0 or flags == 4)) then
        R.bad[#R.bad + 1] = "FaceSequence"
        return nil, "FaceSequence(id, spec, flags)", "bad_argument"
    end
    if not face_id(id) then return nil, "no face", "unsupported" end
    return true
end
function G.FaceScript(id, letters, flags)
    rec("FaceScript", id, letters, flags)
    return true
end
function G.FaceStop(id)
    rec("FaceStop", id)
    if not face_id(id) then return nil, "no face", "unsupported" end
    return true
end
-- 0.9.4c: the optional flags argument (gsa1.FACE.SAME_PAIR with style 0; this module has none, so never a flag)
function G.FaceLevel(id, level, style, flags)
    rec("FaceLevel", id, level, style, flags)
    if not (int_in(id, 1, 1e9) and type(level) == "number" and level >= -1 and level <= 1 and (style == 0 or style == 1)
            and (flags == nil or flags == 0)) then
        R.bad[#R.bad + 1] = "FaceLevel"
    end
end
function G.FaceState(id)
    if not kinds[id] then return nil end
    return 0, false, -1, -1, 0, -1, 0
end
function G.MicDevices()
    return { { index = 0, name = "Headset Microphone", default = true, enabled = true },
             { index = 1, name = "Line In", default = false, enabled = false } }
end
function G.MicOpen(dev)
    rec("MicOpen", dev)
    R.mic.open, R.mic.opens = true, R.mic.opens + 1
    return true
end
function G.MicListen(on)
    rec("MicListen", on)
    if not R.mic.open then return nil, "not open" end
    R.mic.listen = on == true
    return true
end
function G.MicClose()
    rec("MicClose")
    R.mic.open, R.mic.listen = false, false
    return true
end
function G.MicLevel()
    if not R.mic.open then return 0, 0, "off" end
    if not R.mic.listen then return 0, 0, "paused" end
    return R.mic.level, R.mic.level, "on"
end

-- the GMod parts the feature uses that lua_mock.lua does not have
local keys = {}
local KEY_X, KEY_HOT, KEY_SWITCH = 34, 50, 51
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    GetKeyName = function(code) return "key" .. tostring(code) end,
    LookupBinding = function(b) return b == "+voicerecord" and "x" or nil end,
    GetKeyCode = function(n) return n == "x" and KEY_X or 0 end,
}
M.player.IsTyping = function() return M.typing == true end
M.player.IsSpeaking = function() return M.speaking == true end
M.player.VoiceVolume = function() return M.volume or 0 end
local cursor = false
vgui.CursorVisible = function() return cursor end
surface.DrawRect = function() end

local function frames(n, dt)
    for _ = 1, n do M.frame(dt or 1 / 60) end
end
local function log_count(pat)
    GSA1.LogFlush()
    local n = 0
    for _ in string.gmatch(M.files["gsa1/log.txt"] or "", pat) do n = n + 1 end
    return n
end

-- the page's controls: stand-ins that record their calls
local made = {}
local function standin(kind)
    local P = { kind = kind, calls = {}, lines = {}, choices = {} }
    made[#made + 1] = P
    return setmetatable(P, { __index = function(t, k)
        if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
        return function(self, ...)
            local a = { ... }
            t.calls[#t.calls + 1] = { k, ... }
            if k == "SetText" then t.text = a[1] return end
            if k == "SetConVar" then t.convar = a[1] return end
            if k == "SetValue" then t.value = a[1] return end
            if k == "GetValue" then return t.value end
            if k == "SetChecked" then t.checked = a[1] return end
            if k == "Clear" then t.lines, t.choices = {}, {} return end
            if k == "AddChoice" then t.choices[#t.choices + 1] = { a[1], a[2] } return end
            if k == "AddLine" then
                local line = standin("Line")
                line.cols = a
                t.lines[#t.lines + 1] = line
                return line
            end
            local child = standin(k)
            if k == "CheckBox" or k == "NumSlider" or k == "TextEntry" then child.convar = a[2] end
            if k == "Help" or k == "ControlHelp" then child.text = a[1] end
            return child
        end
    end })
end
vgui.Create = function(cls) return standin(cls) end

-- 0. loading ---------------------------------------------------------------------------------------------------------------
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local F = GSA1 and GSA1.Faces
check(ok_load and #ferr == 0 and F ~= nil and F.BuildPage ~= nil and F.Play ~= nil,
    "the autorun loads feat/sh_faces.lua and cl_faces.lua (%s)", ok_load and table.concat(GSA1.FeatureFiles or {}, " ") or
    tostring(err_load or ferr[1]))
if not (ok_load and F) then return done() end
check(type(F.Library) == "function" and type(F.Find) == "function" and type(F.HasFaces) == "function" and
    type(F.CanShow) == "function" and type(F.Play) == "function" and type(F.Stop) == "function",
    "GSA1.Faces has the contract the emote wheel uses: Library, Find, HasFaces, CanShow, Play, Stop")

-- 1. the settings and the page ----------------------------------------------------------------------------------------------
local WANT = {
    gsa1_face_event = { "0", 0, 1 }, gsa1_face_event_key = { "0", 0, 511 }, gsa1_face_pace = { "0", 0, 1 },
    gsa1_face_summary = { nil }, gsa1_lipsync = { "1", 0, 1 }, gsa1_lipsync_source = { "0", 0, 2 },
    gsa1_lipsync_listen = { "0", 0, 1 }, gsa1_lipsync_key = { "0", 0, 511 }, gsa1_lipsync_device = { "-1", -1, 63 },
    gsa1_lipsync_style = { "2", 0, 2 }, gsa1_lipsync_gain = { "2", 0.5, 8 }, gsa1_lipsync_gate = { "0.05", 0, 0.5 },
    gsa1_lipsync_release = { "0.12", 0.03, 0.5 }, gsa1_lipsync_hang = { "0.6", 0.2, 3 },
    -- 0.9.4c (phoneme_plan.md 7.1): style 2 the default; the mouth shapes' settings (tests/feat_phonemes_test.lua checks them)
    gsa1_lipsync_fast = { "1", 0, 1 }, gsa1_lipsync_shapes_size = { "0.5", 0, 1 }, gsa1_lipsync_shapes_big = { "1", 0, 1 },
    gsa1_lipsync_shapes_loud = { "0.8", 0.5, 1 }, gsa1_lipsync_shapes_steady = { "0", 0, 2 },
    gsa1_lipsync_shapes_gate = { "6", 3, 12 }, gsa1_lipsync_shapes_adapt = { "1", 0, 1 },
    gsa1_lipsync_shapes_rise = { "0.015", 0.005, 0.06 }, gsa1_lipsync_shapes_log = { "0", 0, 1 },
    -- 0.9.4e (lipsync2_plan.md 7.1 / 7.2): the microphone by its name (the "Microphone" combo's ConVar now), "Sound
    -- detection", "Use my mouths" (its control is the mouth shape tester's: tests/feat_mouthtest_test.lua L12)
    gsa1_lipsync_device_name = { "" }, gsa1_lipsync_hearing = { "2", 1, 2 }, gsa1_lipsync_shapes_custom = { "1", 0, 1 },
}
-- 0.9.4e: no control on this page (lipsync2_plan.md 7.1): gsa1_lipsync_device is G-SA1's cache of the microphone's number;
-- gsa1_lipsync_shapes_custom's checkbox is on the tester's sub-form (feat/cl_mouthtest.lua, not loaded by this test)
local NO_CONTROL_HERE = { gsa1_lipsync_device = true, gsa1_lipsync_shapes_custom = true }
for i = 1, 10 do
    WANT["gsa1_face_hotkey_" .. i] = { "0", 0, 511 }
    WANT["gsa1_face_hotkey_anim_" .. i] = { "" }
end
local bad, nwant = {}, 0
for name, w in pairs(WANT) do
    nwant = nwant + 1
    local c = M.convars[name]
    local okv = c and c.client and c.save and GSA1.CONVARS[name]
    if okv and w[1] ~= nil then okv = c.v == w[1] end
    if okv and w[2] ~= nil then okv = c.lo == w[2] and c.hi == w[3] end
    if not okv then bad[#bad + 1] = name end
end
local mine = 0
for name in pairs(GSA1.CONVARS) do
    if string.find(name, "^gsa1_face") or string.find(name, "^gsa1_lipsync") then mine = mine + 1 end
end
table.sort(bad)
check(#bad == 0 and mine == nwant and nwant == 46, "%d client settings with the plan's defaults (7.2): event faces off, no "
    .. "keys, lip sync on, automatic, push-to-talk, Windows' default microphone (by name, 0.9.4e), the mouth shapes from "
    .. "the voice (0.9.4c), gain 2, gate 0.05, release 0.12 s, hang 0.6 s%s (%d)", nwant, #bad > 0 and (": wrong " ..
    table.concat(bad, " ")) or "", mine)

GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }

M.menu = {}
M.run_hook("PopulateToolMenu")
local entry
for _, e in ipairs(M.menu) do
    if e.class == "gsa1_feat_faces" then entry = e end
end
check(entry and entry.name == "Faces" and entry.category == "G-SA1", "the page Options -> G-SA1 -> Faces")
local function build_page()
    made = {}
    local panel = standin("DForm")
    local pok, perr = pcall(entry.cpanel, panel)
    if not pok then print("        page: " .. tostring(perr)) end
    return pok
end
local function page_role(role)
    for _, P in ipairs(made) do
        if P.gsa1Role == role then return P end
    end
end
local function page_texts()
    local t = {}
    for _, P in ipairs(made) do
        if P.text then t[#t + 1] = tostring(P.text) end
    end
    return table.concat(t, "\n")
end
if entry then
    local pok = build_page()
    local bound = {}
    for _, P in ipairs(made) do
        for _, c in ipairs(P.calls) do
            if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then bound[c[3]] = true end
            if c[1] == "Button" and type(c[3]) == "string" and M.convars[c[3]] then bound[c[3] .. "#none"] = true end
        end
        if P.convar then bound[P.convar] = true end
        if P.gsa1ConVar then
            -- a combo (OnSelect sets its ConVar) or the read-only summary line
            local onsel = rawget(P, "OnSelect")
            if onsel then
                local before = M.convars[P.gsa1ConVar].v
                onsel(P, 1, "x", P.choices[#P.choices] and P.choices[#P.choices][2] or "1")
                -- 0.9.4c: the Mouth combo's last choice is its default (2): its first one changes it
                if M.convars[P.gsa1ConVar].v == before and P.choices[1] then onsel(P, 1, "x", P.choices[1][2]) end
                if M.convars[P.gsa1ConVar].v ~= before or #P.choices <= 1 then bound[P.gsa1ConVar] = true end
                M.convars[P.gsa1ConVar].v = before
            else
                bound[P.gsa1ConVar] = true
            end
        end
    end
    local missing = {}
    for name in pairs(WANT) do if not bound[name] and not NO_CONTROL_HERE[name] then missing[#missing + 1] = name end end
    table.sort(missing)
    local tx = page_texts()
    check(pok and #missing == 0 and bound["gsa1_face_event_key#none"] and string.find(tx, "60 = 1 second", 1, true) ~= nil,
        "every setting has a control on the page (check boxes, sliders, key binders, combo boxes, the summary line), a "
        .. "\"No key\" button, the unit line \"Frames: 60 = 1 second\"%s", #missing > 0 and (": missing " ..
        table.concat(missing, " ")) or "")
end

-- 2. the switch (review R.6) ---------------------------------------------------------------------------------------------------
check(#calls_of("FaceMode") == 0, "no character: no FaceMode")
GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil and C.name == "sonic" and #calls_of("FaceMode") == 0 and count_calls("Face") == 0,
    "Sonic spawned with event faces off: no face call at all (review R.6)")
if not C then return done() end
frames(5)
check(count_calls("Face", C.id) == 0, "nobody talks, nothing pressed: still no face call in 5 frames")
RunConsoleCommand("gsa1_face_event", "1")
local fm = calls_of("FaceMode", C.id)
check(#fm == 1 and fm[1][3] == true and fm[1][4] == false, "event faces on: FaceMode(id, true, false) once at once")
RunConsoleCommand("gsa1_face_pace", "1")
fm = calls_of("FaceMode", C.id)
check(#fm == 2 and fm[2][3] == true and fm[2][4] == true, "the cutscene pace: FaceMode(id, true, true)")
RunConsoleCommand("gsa1_face_event", "0")
fm = calls_of("FaceMode", C.id)
check(#fm == 3 and fm[3][3] == false and fm[3][4] == false, "event faces off: FaceMode(id, false, false)")
RunConsoleCommand("gsa1_face_pace", "1")
RunConsoleCommand("gsa1_face_pace", "0")
check(#calls_of("FaceMode", C.id) == 3, "the pace while event faces are off: no call")
RunConsoleCommand("gsa1_face_event", "1")
GSA1.Spawn("tails")
local CT = GSA1.Char
fm = CT and calls_of("FaceMode", CT.id) or {}
check(CT and CT.kind == 2 and #fm == 1 and fm[1][3] == true, "a new character while the switch is on: FaceMode(new id, "
    .. "true, ...) once")
for _, n in ipairs({ "gamma", "supersonic", "supersonic_general" }) do
    GSA1.Spawn(n)
    local X = GSA1.Char
    RunConsoleCommand("gsa1_face_event", "0")
    RunConsoleCommand("gsa1_face_event", "1")
    frames(3)
    check(X and count_calls("Face", X.id) == 0, "%s: never a face call (spawned with the switch on, the switch flipped)", n)
end
check(F.HasFaces("sonic") and F.HasFaces("big") and not F.HasFaces("gamma") and not F.HasFaces("supersonic") and
    not F.HasFaces("supersonic_general"), "HasFaces: Sonic and Big yes; E-102 and both Super Sonics no")
RunConsoleCommand("gsa1_face_event", "0")

-- 3. the library ---------------------------------------------------------------------------------------------------------------
local lib = F.Library()
local names = {}
for i, a in ipairs(lib) do names[i] = a.name end
check(#lib == 11 and names[1] == "Happy" and lib[1].entries[1][1] == "b" and lib[1].entries[1][2] == 10 and
    lib[1].entries[1][3] == 90 and lib[1].back == 8 and F.Find("Talk") and #F.Find("Talk").entries == 3 and
    M.files[F.FILE] == nil, "the defaults without a file: 11 face animations (%s)", table.concat(names, ", "))
local seen = {}
local function on_change(change) seen[#seen + 1] = change end
hook.Add("GSA1FaceLibraryChanged", "test", on_change)
local E = F.ed
F.EdNew(E)
E.name = "Grin"
F.EdAppend(E, "b")
F.EdAppend(E, "A")
F.EdSet(E, 1, 10, 90)
local okSave = F.EdSave(E, "save")
local text1 = M.files[F.FILE]
check(okSave and text1 ~= nil and F.Find("Grin") and #seen == 1 and seen[1].saved and seen[1].saved.Grin,
    "Save: written to data/gsa1/face_anims.txt, GSA1FaceLibraryChanged with saved = {Grin}")
local back, bl, notes = F.ParseLibrary(text1)
check(bl == 0 and #notes == 0 and F.SerializeLibrary(back) == text1 and #back == 12 and string.find(text1, "Grin\t8\t0\tb:10:90,A:0:0\t",
    1, true) ~= nil and string.find(text1, "version\t1", 1, true) ~= nil, "a save / load round trip is equal (12 lines, "
    .. "\"Grin<tab>8<tab>0<tab>b:10:90,A:0:0\")")
check(M.convars.gsa1_face_summary.v == F.MirrorString(F.Library()) and string.find(M.convars.gsa1_face_summary.v,
    "12 face animations", 1, true) == 1, "the read-only mirror gsa1_face_summary: \"%s\"", M.convars.gsa1_face_summary.v)
RunConsoleCommand("gsa1_face_hotkey_anim_3", "Grin")
E.name = "Big grin"
F.EdSave(E, "rename")
check(F.Find("Big grin") and not F.Find("Grin") and #seen == 2 and seen[2].renamed and seen[2].renamed.Grin == "Big grin"
    and M.convars.gsa1_face_hotkey_anim_3.v == "Big grin", "Rename: GSA1FaceLibraryChanged with renamed = {Grin = Big "
    .. "grin}; a hotkey follows the rename")
F.EdNew(E)
E.name = "happy"
F.EdAppend(E, "b")
local dupOk = F.EdSave(E, "new")
check(not dupOk and string.find(E.note, "exists", 1, true) ~= nil, "unique names: \"happy\" next to \"Happy\" is refused "
    .. "(%s)", E.note)
F.EdLoad(E, "Big grin")
F.EdDelete(E)
check(not F.Find("Big grin") and #seen == 3 and seen[3].deleted and seen[3].deleted["Big grin"] and
    M.convars.gsa1_face_hotkey_anim_3.v == "", "Delete: GSA1FaceLibraryChanged with deleted = {Big grin}; the hotkey "
    .. "forgets it")
local e33 = {}
for i = 1, 33 do e33[i] = "B:0:0" end
local e32 = {}
for i = 1, 32 do e32[i] = "B:0:0" end
local badText = table.concat({ "# a comment", "version\t1", "Ok\t8\t0\tb:10:90\t", "Ok\t8\t0\tZ:0:0\t", "NoEntries\t8\t0\t\t",
    "BadLetter\t8\t0\tf:0:0\t", "BadEnter\t8\t0\tb:200:0\t", "BadKeep\t8\t2\tb:0:0\t", "TooMany\t0\t0\t" ..
    table.concat(e33, ",") .. "\t", "Full\t8\t0\t" .. table.concat(e32, ",") .. "\t", "garbage" }, "\n")
local pl, pbad, pnotes = F.ParseLibrary(badText)
check(#pl == 2 and pl[1].name == "Ok" and pl[2].name == "Full" and pbad == 7 and pl[2].back == 0 and #pnotes == 1,
    "bad lines skipped and counted (%d: a duplicate name, no entries, 'f', enter 200, keep 2, 33 entries, garbage); a "
    .. "32-entry line with back 8 loads with back 0 and a note (review R.10: %s)", pbad, tostring(pnotes[1]))

-- 4. the maker ------------------------------------------------------------------------------------------------------------------
GSA1.Spawn("sonic")
C = GSA1.Char
build_page()
local ex, el = page_role("expressions"), page_role("entries")
local ui = F.ui
check(ex and el and ui and #ex.lines == 31, "the maker: Sonic's expression list has the 31 face animations (%d lines)",
    ex and #ex.lines or -1)
F.EdNew(E)
F.Refresh()
local function line_of(letter)
    for _, l in ipairs(ex.lines) do
        if l.gsa1Letter == letter then return l end
    end
end
ex.DoDoubleClick(ex, 1, line_of("b"))
ex.DoDoubleClick(ex, 1, line_of("A"))
ex.DoDoubleClick(ex, 1, line_of("Z"))
check(#E.entries == 3 and E.entries[1][1] == "b" and E.entries[1][2] == 0 and E.entries[1][3] == 0 and
    E.entries[3][1] == "Z" and #el.lines == 3, "double-click appends {letter, 0, 0}: b, A, Z (%d lines in the animation's "
    .. "list)", #el.lines)
E.sel = 3
F.pageButtons.Up.DoClick()
check(E.entries[2][1] == "Z" and E.sel == 2, "Up moves the selected entry up")
F.pageButtons.Down.DoClick()
check(E.entries[3][1] == "Z" and E.sel == 3, "Down moves it back")
F.pageButtons.Remove.DoClick()
check(#E.entries == 2 and E.entries[2][1] == "A", "Remove takes it out")
E.sel = 1
ui.enter.OnValueChanged(ui.enter, 200)
ui.hold.OnValueChanged(ui.hold, 5000)
check(E.entries[1][2] == 127 and E.entries[1][3] == 3600, "the number fields clamp: enter 200 -> 127, hold 5000 -> 3600")
F.EdSet(E, 1, 10, 90)
F.EdSet(E, 2, 8, 0)
E.back = 0
local total, ttext = F.EdTotal(E, F.Info(0))
check(total == 100 + 8 + 12 and string.find(ttext, "120 frames (2.00 s)", 1, true) == 1 and
    F.EdEntryText(E, 1, F.Info(0)) == "enter 10 + plays 0 + hold 90 = 100 frames (1.67 s)",
    "the total line \"%s\"; entry 1: \"%s\"", tostring(ttext), F.EdEntryText(E, 1, F.Info(0)))
F.EdNew(E)
for _ = 1, 31 do F.EdAppend(E, "B") end
local ok32 = F.EdAppend(E, "B")
local n31 = #E.entries
F.EdSetKeep(E, true)
local ok32k = F.EdAppend(E, "B")
F.EdSetBack(E, 8)
local back8 = E.back == 8
F.EdSetKeep(E, false)
check(not ok32 and n31 == 31 and ok32k and #E.entries == 32 and E.back == 0 and back8,
    "review R.10: a 32nd entry is refused while it blends back to neutral (31), taken with \"keep the last face\"; then "
    .. "unticking \"keep\" turns the blend back off (%s)", E.note)
-- Big's list
ui.character.OnSelect(ui.character, 6, "Big", "big")
local letters = {}
for _, l in ipairs(ex.lines) do letters[#letters + 1] = l.gsa1Letter end
check(#ex.lines == 14 and table.concat(letters) == "ABCDEKLSTUVWXY", "Big's expression list is the module's 14: %s",
    table.concat(letters))
ui.character.OnSelect(ui.character, 5, "E-102 Gamma", "gamma")
check(#ex.lines == 1 and string.find(tostring(ex.lines[1].cols[3]), "E-102 has no face in the game", 1, true) ~= nil and
    string.find(tostring(ui.why.text), "E-102 has no face in the game", 1, true) ~= nil,
    "E-102 in the maker: \"E-102 has no face in the game\"")
ui.character.OnSelect(ui.character, 1, "Sonic", "sonic")
F.EdLoad(E, "Happy")
local n0 = #calls_of("FaceSequence", C.id)
F.pageButtons.Preview.DoClick()
local fs = calls_of("FaceSequence", C.id)
check(#fs == n0 + 1 and fs[#fs][3] == "b:10:90,A:8:0" and fs[#fs][4] == 0,
    "Preview of \"Happy\": FaceSequence(id, \"b:10:90,A:8:0\", 0) (%s)", fs[#fs] and tostring(fs[#fs][3]) or "-")
ui.keep.OnChange(ui.keep, true)
F.pageButtons.Preview.DoClick()
fs = calls_of("FaceSequence", C.id)
check(fs[#fs][3] == "b:10:90" and fs[#fs][4] == 4, "with \"keep the last face\": FaceSequence(id, \"b:10:90\", HOLD_LAST)")

-- 5. Play / CanShow / Stop ----------------------------------------------------------------------------------------------------------
local okB, whyB = F.CanShow("Happy", "big")
local okT = F.CanShow("Talk", "big")
local okS = F.CanShow("Happy", "sonic")
local okG, whyG = F.CanShow("Happy", "gamma")
check(okB == false and whyB == "Big can't show b" and okT == true and okS == true and okG == false and
    whyG == "E-102 has no face in the game", "CanShow: Big + Happy -> false, \"%s\"; Big + Talk, Sonic + Happy -> true; "
    .. "E-102 -> \"%s\"", tostring(whyB), tostring(whyG))
GSA1.Spawn("big")
local CB = GSA1.Char
local pb, pbw = F.Play(CB, "Happy", "test")
check(pb == nil and pbw == "Big can't show b" and #calls_of("FaceSequence", CB.id) == 0, "Play(Big, Happy) -> nil, \"Big "
    .. "can't show b\" and nothing sent")
local pt = F.Play(CB, "Talk", "test")
fs = calls_of("FaceSequence", CB.id)
check(pt == true and #fs == 1 and fs[1][3] == "C:0:0,D:0:0,E:0:0,A:8:0" and fs[1][4] == 0, "Play(Big, Talk) -> "
    .. "FaceSequence(id, \"C:0:0,D:0:0,E:0:0,A:8:0\", 0)")
F.Stop(CB)
check(#calls_of("FaceStop", CB.id) == 1, "Stop -> FaceStop(id)")

-- 6. the hotkeys ------------------------------------------------------------------------------------------------------------------
GSA1.Spawn("sonic")
C = GSA1.Char
F.EdNew(E)
E.name = "Kept"
F.EdAppend(E, "V")
E.hold_last = true
F.EdSave(E, "save")
RunConsoleCommand("gsa1_face_hotkey_1", tostring(KEY_HOT))
RunConsoleCommand("gsa1_face_hotkey_anim_1", "Happy")
RunConsoleCommand("gsa1_face_hotkey_2", tostring(KEY_HOT + 2))
RunConsoleCommand("gsa1_face_hotkey_anim_2", "Kept")
local h0 = #calls_of("FaceSequence", C.id)
keys[KEY_HOT] = true
frames(10)
keys[KEY_HOT] = false
frames(2)
local h1 = #calls_of("FaceSequence", C.id)
keys[KEY_HOT] = true
frames(1)
keys[KEY_HOT] = false
frames(1)
local h2 = #calls_of("FaceSequence", C.id)
check(h1 == h0 + 1 and h2 == h0 + 2, "a hotkey plays its face animation once per press (held 10 frames: %d, a second "
    .. "press: %d)", h1 - h0, h2 - h0)
keys[KEY_HOT + 2] = true
frames(1)
keys[KEY_HOT + 2] = false
frames(1)
fs = calls_of("FaceSequence", C.id)
local st0 = #calls_of("FaceStop", C.id)
keys[KEY_HOT + 2] = true
frames(1)
keys[KEY_HOT + 2] = false
frames(1)
check(fs[#fs][3] == "V:0:0" and fs[#fs][4] == 4 and #calls_of("FaceStop", C.id) == st0 + 1 and
    #calls_of("FaceSequence", C.id) == #fs, "a face animation that keeps its last face: the first press plays it "
    .. "(HOLD_LAST), the second lets it go (FaceStop)")
local h3 = #calls_of("FaceSequence", C.id)
M.typing = true
keys[KEY_HOT] = true
frames(2)
keys[KEY_HOT] = false
frames(1)
M.typing = false
cursor = true
keys[KEY_HOT] = true
frames(2)
keys[KEY_HOT] = false
frames(1)
cursor = false
M.ui = true
keys[KEY_HOT] = true
frames(2)
keys[KEY_HOT] = false
frames(1)
M.ui = false
check(#calls_of("FaceSequence", C.id) == h3, "nothing while typing, with the cursor (a menu) or in the game's menu")
-- the switch key
RunConsoleCommand("gsa1_face_event_key", tostring(KEY_SWITCH))
local sw0 = #calls_of("FaceMode", C.id)
keys[KEY_SWITCH] = true
frames(3)
keys[KEY_SWITCH] = false
frames(1)
fm = calls_of("FaceMode", C.id)
check(#fm == sw0 + 1 and fm[#fm][3] == true and M.convars.gsa1_face_event.v == "1", "the switch key: event faces on "
    .. "(one FaceMode)")
RunConsoleCommand("gsa1_face_event", "0")

-- 7. lip sync from Garry's Mod's voice --------------------------------------------------------------------------------------------
RunConsoleCommand("gsa1_lipsync_source", "1")
frames(120)
local L = F.lip
local exp = { s = L.s, quiet = L.quiet }
local lv0 = #calls_of("FaceLevel", C.id)
local script = {}
for i = 1, 30 do script[#script + 1] = { true, 0.1 + 0.02 * (i % 7) } end
for _ = 1, 10 do script[#script + 1] = { true, 0.0 } end
for _ = 1, 70 do script[#script + 1] = { false, 0.0 } end
local want = {}
local tprev = M.T
for _, s in ipairs(script) do
    M.speaking, M.volume = s[1], s[2]
    M.frame(1 / 60)
    local dt = M.T - tprev
    tprev = M.T
    local v = F.Smooth(exp, s[1] and s[2] or 0, dt, 2, 0.05, 0.12, 0.6, s[1])
    want[#want + 1] = v
end
M.speaking, M.volume = false, 0
local got = calls_of("FaceLevel", C.id)
local sent, worst, minus, after = {}, 0, 0, 0
for i = lv0 + 1, #got do sent[#sent + 1] = got[i][3] end
local wi = 0
for _, v in ipairs(want) do
    if v >= 0 then
        wi = wi + 1
        worst = math.max(worst, math.abs((sent[wi] or -9) - v))
    end
end
local talkN = wi
for i = talkN + 1, #sent do
    if sent[i] == -1 then minus = minus + 1 else after = after + 1 end
end
frames(60)
local later = #calls_of("FaceLevel", C.id) - #got
check(talkN > 40 and worst < 1e-6 and minus == 1 and after == 0 and later == 0 and #sent == talkN + 1,
    "the GMod source: %d FaceLevel values equal to F.Smooth's (worst %.2g), exactly one -1 after the 0.6 s hang, then no "
    .. "call (review R.6: %d in the next second)", talkN, worst, later)
RunConsoleCommand("gsa1_lipsync", "0")
local off0 = #calls_of("FaceLevel", C.id)
M.speaking, M.volume = true, 0.5
frames(30)
check(#calls_of("FaceLevel", C.id) == off0, "gsa1_lipsync 0: no FaceLevel while talking")
RunConsoleCommand("gsa1_lipsync", "1")
frames(20)
local on1 = #calls_of("FaceLevel", C.id)
RunConsoleCommand("gsa1_lipsync", "0")
frames(30)
got = calls_of("FaceLevel", C.id)
check(on1 > off0 and #got == on1 + 1 and got[#got][3] == -1, "lip sync switched off while talking: exactly one -1")
M.speaking, M.volume = false, 0
RunConsoleCommand("gsa1_lipsync", "1")
frames(60)

-- 8. automatic: Garry's Mod reports no level -> the microphone, only while the talk key is held ------------------------------------
RunConsoleCommand("gsa1_lipsync_source", "0")
R.mic.opens = 0
local mo0 = #calls_of("MicOpen")
local dec0 = log_count("lip sync source automatic")
M.speaking, M.volume = true, 0           -- Garry's Mod says "speaking" but reports no level (single player)
frames(60)
check(#calls_of("MicOpen") == mo0, "without the talk key (listen 0) the microphone is never opened")
keys[KEY_X] = true
frames(20)
local early = #calls_of("MicOpen") - mo0
frames(20)
local opens = #calls_of("MicOpen") - mo0
local li = calls_of("MicListen")
check(early == 0 and opens == 1 and R.mic.listen == true and li[#li][2] == true, "the talk key held, no level from "
    .. "Garry's Mod for 0.5 s: MicOpen once (%d before 0.33 s), MicListen(true)", early)
R.mic.level = 0.6
frames(30)
local lvls = calls_of("FaceLevel", C.id)
check(lvls[#lvls][3] > 0.5, "the microphone's level reaches the mouth (%.2f)", lvls[#lvls][3])
keys[KEY_X] = false
frames(2)
li = calls_of("MicListen")
check(R.mic.listen == false and li[#li][2] == false and #calls_of("MicOpen") - mo0 == 1, "released: MicListen(false), "
    .. "the device stays open (MicOpen once)")
keys[KEY_X] = true
frames(3)
check(R.mic.listen == true and #calls_of("MicOpen") - mo0 == 1, "pressed again: listening at once, no second MicOpen")
keys[KEY_X] = false
frames(60)
M.speaking, M.volume = false, 0
local dec = log_count("lip sync source automatic") - dec0
check(dec == 1, "one log line per decision (%d)", dec)

-- 9. E-102 ------------------------------------------------------------------------------------------------------------------------------
GSA1.Spawn("gamma")
local CG = GSA1.Char
RunConsoleCommand("gsa1_face_event", "1")
RunConsoleCommand("gsa1_face_event", "0")
RunConsoleCommand("gsa1_lipsync_source", "1")
M.speaking, M.volume = true, 0.7
frames(30)
M.speaking, M.volume = false, 0
frames(60)
keys[KEY_HOT] = true
frames(2)
keys[KEY_HOT] = false
frames(1)
RunConsoleCommand("gsa1_face_play", "Talk")
RunConsoleCommand("gsa1_face_stop")
build_page()
local tx = page_texts()
check(CG and CG.kind == 6 and count_calls("Face", CG.id) == 0 and string.find(tx, "E-102 has no face in the game", 1, true)
    ~= nil, "E-102: no Face* call ever (the switch, talking, a hotkey, the console); the page says \"E-102 has no face in "
    .. "the game\"")

check(#R.bad == 0, "every module call had valid arguments%s", #R.bad > 0 and (": " .. table.concat(R.bad, " ")) or "")
check(R.infoCalls <= 9, "gsa1.FaceInfo once per kind (review R.2: %d calls)", R.infoCalls)
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
