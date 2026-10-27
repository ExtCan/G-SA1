-- feat_mouthtest_test.lua - the mouth shape tester and "Your mouths" (round 0.9.4e: sadc docs/research/lipsync2_plan.md 4.7,
-- 4.8, 6.3 L3-L14 with its Review R.4b / R.8 / R.10; lipsync2_show.md 6 and 7), the addon's side (addon/lua/gsa1/feat/
-- cl_mouthtest.lua with cl_faces.lua / sh_faces.lua and the mouths lane's sh_mouths.lua) in Garry's Mod's own LuaJIT with
-- tests/lua_mock.lua and a mock of the module's feature "faces" 3 made in this file (every Face* / Viseme* / Mic* call
-- recorded and its arguments checked; gsa1.VisemeOverride keeps the spec it got and VisemeMouth / VisemeTable follow it).
-- The stubs lua_mock.lua lacks live here (cookie, input, the player's voice, Derma_Query, render.RenderView, the page's
-- controls with their hover / visible state); lua_mock.lua is not changed. Each case fails without the feature.
--   L3  point: per frame exactly one FaceMouth(id, a, b, w, flags) with VisemeMouth's numbers for the pointed sound and the
--       "Show as" variant (a ladder entry: one FaceLevel), none from lip sync in that frame; moving between two buttons
--       sends no -1; nothing pointed at for 0.15 s -> exactly one FaceLevel(id, -1, 0).
--   L4  keep: survives the panel being hidden (no Think) for 20 s of frames, then one -1; ends at once on another button,
--       Stop, a second click, F.PlayAnim, the character changing; on the talk key going down the tester sends nothing and
--       lip sync's mouth comes in the same frame.
--   L5  Play all: the 8 sounds in order, 0.5 s each, then one -1.
--   L6  lip sync yields: talking + a pointer -> no -1 from lip sync while the tester draws; talking restarts cleanly after;
--       over the whole scripted run every talk spurt ends with exactly one -1 (0.9.4a's rule).
--   L7  Use / Back / Reset character / Reset all (Yes; No changes nothing): the right VisemeOverride(kind, spec) calls, the
--       file written once per action through F.MouthSerializeFile, the table cache cleared, the summary ConVar updated; a
--       line the module refuses stays in the file and is listed on the page; at load every face kind gets its spec or ""
--       (review R.8).
--   L9  gsa1_lipsync_shapes_custom 0 -> VisemeOverride(k, "") for every kind with a line, the file untouched; 1 -> again.
--   L10 no face (E-102, both Super Sonics): buttons greyed, no module call at all; Big: the one-shape line.
--   L11 an older module (no VisemeOverride; FEATURES.faces 2): the tester works, "Your mouths" greyed with its text.
--   L12 the page build: the tester's controls with roles (mouthbtn x 8, showas, playall, stop, closeup, custom, resetchar,
--       resetall, 7 mouthrow) and every ConVar of lipsync2_plan.md 7.1 / 7.2 bound to its control.
--   L13 the close-up's guard (review R.4b): RenderView only while the panel is painted visible, the box ticked and a
--       character with a face exists; this file's RenderView runs every render hook the loaded addon registered (and the
--       entities' Draw / DrawTranslucent, as the engine does) with EyePos() = the close-up's origin, a test-only hook proves
--       it ran (negative control: a RenderView that runs nothing fails that proof); during it no GSA1PreTick, Think,
--       gsa1.Tick, gsa1.Render, PollEvents, AudioUpdate or frame / tick counter advances; first person -> the text line, no
--       RenderView (review R.10); an error -> the text line, one log line, no further RenderView this session.
--   L14 garbage: 600 idle frames (the tester shown with nothing pointed at, and not shown) allocate nothing in the tester's
--       code (F.TesterFrame and the tester's controls' Think; collectgarbage("count") with the collector stopped).
--   lua_host tests/feat_mouthtest_test.lua <tests dir> <addon/lua dir>
--
-- API NOTES (094e-gsa1-lua; lipsync2_plan.md 4.7 / 4.8 / 5.5 / 5.6 / 7.2 as built):
--   Files: feat/cl_mouthtest.lua (new, loaded after cl_faces.lua); uses sh_mouths.lua's F.MOUTH_FILE, F.MOUTH_CHOICES,
--   F.MOUTH_KEYS, F.MOUTH_CHARS, F.MouthParseFile, F.MouthSerializeFile, F.MouthSpec, F.MouthText (its own reading of a
--   MOUTH text, F.TesterParseMouth, is only to show a list line before it is chosen; the module parses what is saved).
--   ConVars (client, archived; cl_faces.lua): gsa1_mouth_closeup 1, gsa1_lipsync_shapes_custom 1, gsa1_mouth_summary ""
--   (read-only mirror: "Sonic - ah, ee; Amy - s z sh", " (off)" appended with "Use my mouths" off). Console:
--   gsa1_mouth_show <ah|eh|ee|oh|oo|s|f|mbp> [quiet|loud] (3 s), gsa1_mouth_reset [sonic|tails|knuckles|amy|big|all].
--   Per frame: cl_faces.lua's GSA1PreTick hook: now = SysTime(); if F.TesterFrame(C, now) then F.LipSyncYield(C, now) else
--   F.LipSyncFrame(C, now) end. F.TesterFrame idle = one comparison (T.active); while active: one VisemeMouth(kind, cls,
--   s, size, variant, big) with "Show as" {1, 0} / {0.35, 1} / {1, 2} and FaceMouth(id, a, b, w, flags) or FaceLevel(id,
--   min(w, ladder cap), 0[, flags]) (flags = FACE.SAME_PAIR with "Faster mouth"); a list line: FaceMouth with its own
--   numbers ("scales" lines scaled by "Show as"'s openness with the kind's floor). Let go: ONE FaceLevel(id, -1, 0); the talk
--   key going down (not in "Listen: always"): nothing, lip sync draws that frame. State functions: F.TesterPoint(cls, now),
--   F.TesterPointMouth(text, now), F.TesterClick(cls, now) (second click lets go), F.TesterKeepMouth(text, now),
--   F.TesterShow(cls, variant, s), F.TesterPlayAll(now), F.TesterStop(why, silent), F.TesterShowAs(0..2).
--   Your mouths: F.MouthEnsure() (once per loaded module: F.MouthLoad + F.MouthApplyAll = VisemeOverride for EVERY face
--   kind 0, 2, 3, 5, 7 with its line's spec or "", review R.8; a refused spec -> VisemeOverride(kind, "") too, the line
--   kept and listed), F.MouthUse(kind, key, mouth) / F.MouthBack(kind, key) / F.MouthResetChar(kind) /
--   F.MouthResetAll(confirmed) (Derma_Query first) -> VisemeOverride(kind, spec), file.Write of the whole file once
--   (F.MouthSerializeFile + the unreadable lines kept at its end), F.VisemeTableReset(kind), the summary ConVar. Keys:
--   "AA", "AA.quiet", "AA.loud" (the "Show as" variant). The switch: VisemeOverride(kind, "" | spec) for every kind with a
--   line, the file untouched.
--   The close-up: render.RenderView{origin, angles, x, y, w, h, fov = 30, drawviewmodel / drawhud / dopostprocess /
--   drawviewer = false} from the panel's Paint in pcall; the camera F.CLOSEUP_DIST (40) HU in front of
--   VisemeTable(kind).mouth_at {forward, up} (else 0.85 x CharacterInfo's height) looking back. It runs no tick and no
--   gsa1.Render (cl_render.lua draws the last batches); the session log's "views" line counts it as a second main view;
--   sprites in it face the main camera (PrepareView runs once per frame with the main eye).
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_mouthtest_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only the faces' files, the mouths' data and the tester
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_faces%.lua$") or n == "sh_mouths.lua" or n == "cl_mouthtest.lua" then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end
local haveFiles = {}
for _, n in ipairs(real_list and real_list(root .. "/gsa1/feat", "*.lua") or {}) do haveFiles[n] = true end
check(haveFiles["cl_mouthtest.lua"] and haveFiles["sh_mouths.lua"], "the tester's file and the mouths' data are there "
    .. "(cl_mouthtest.lua %s, sh_mouths.lua %s)", tostring(haveFiles["cl_mouthtest.lua"] == true),
    tostring(haveFiles["sh_mouths.lua"] == true))

-- cookies, files written, the question box
local jar = {}
cookie = {
    GetNumber = function(k, d) return tonumber(jar[k]) or d end,
    GetString = function(k, d) return jar[k] or d end,
    Set = function(k, v) jar[k] = tostring(v) end,
}
local writes = {}
local fwrite, fappend = file.Write, file.Append
file.Write = function(p, s)
    writes[#writes + 1] = { "Write", p }
    return fwrite(p, s)
end
local queries = {}
function Derma_Query(text, title, b1, f1, b2, f2)
    queries[#queries + 1] = { text = text, yes = f1, no = f2, b1 = b1, b2 = b2 }
end

-- the mock module with the feature "faces" 3 ---------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ features = { faces = 3 } })
local R = { calls = {}, bad = {}, mic = { open = false, listen = false, level = 0, blocks = 0 },
            vis = { on = false, cls = -1, level = 0, f1 = 0, f2 = 0, conf = 0, seq = 0 }, over = {}, spec = {}, anim = -1,
            counts = { Tick = 0, Render = 0, PollEvents = 0, AudioUpdate = 0 } }
local function rec(name, ...)
    local c = { name, ... }
    R.calls[#R.calls + 1] = c
    return c
end
local function bad(name, why) R.bad[#R.bad + 1] = name .. " (" .. tostring(why) .. ")" end
local function int_in(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end
local function num_in(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi end
local SAME_PAIR = 0x200
G.FACE = { MODE_GAME = 0, MODE_EVENT = 1, PACE_CUTSCENE = 0x100, NOW = 1, LOOP = 2, HOLD_LAST = 4, LEVEL_LADDER = 0,
           LEVEL_TALK = 1, ACT_NONE = 0, ACT_SEQUENCE = 1, ACT_SCRIPT = 2, ACT_HELD = 3, ACT_LIPSYNC = 4,
           ACT_GAMEPLAY = 5, SEQ_MAX = 32, HOLD_MAX = 3600, ENTER_MAX = 127, SAME_PAIR = SAME_PAIR, MOUTH = 1 }
G.VISEME = { SIL = 0, MBP = 1, AA = 2, EH = 3, EE = 4, OH = 5, OO = 6, SS = 7, FV = 8, COUNT = 9,
             NAMES = { [0] = "SIL", "MBP", "AA", "EH", "EE", "OH", "OO", "SS", "FV" },
             WORDS = { [0] = "silence", "m b p", "ah", "eh", "ee", "oh", "oo", "s z sh", "f v th" } }
for _, n in ipairs({ "Tick", "Render", "PollEvents", "AudioUpdate" }) do
    local f = G[n]
    G[n] = function(...)
        R.counts[n] = R.counts[n] + 1
        return f(...)
    end
end
local kinds = {}
local create = G.Create
function G.Create(kind, pos, yaw, ups, rings, extras)
    local id = create(kind, pos, yaw, ups, rings)
    kinds[id] = kind
    rec("Create", id, kind)
    return id
end
local KEYS = { [0] = 21, [2] = 20, [3] = 20, [5] = 20, [7] = 8 }
function G.FaceInfo(kind)
    if not int_in(kind, 0, 8) then return nil, "FaceInfo(kind)", "bad_argument" end
    local letters = (kind == 0 or kind == 2 or kind == 3 or kind == 5) and 0x7FFFFFFF or (kind == 7 and 0x01FC0C1F or 0)
    local t = { has_face = letters ~= 0, keys = KEYS[kind] or 0, letters = letters, ladder = "0,4,16", ladder_len = 3,
                steps = {}, first = {}, last = {} }
    for i = 0, 30 do t.steps[i], t.first[i], t.last[i] = 16, 4, 0 end
    return t
end
local function face_id(id) return kinds[id] ~= nil and kinds[id] ~= 6 and kinds[id] ~= 8 end
function G.FaceMode(id, ev, pace) rec("FaceMode", id, ev, pace) return true end
function G.FaceSequence(id, spec, flags) rec("FaceSequence", id, spec, flags) return true end
function G.FaceScript(id, l, f) rec("FaceScript", id, l, f) return true end
function G.FaceStop(id) rec("FaceStop", id) return true end
function G.FaceState(id)
    if not kinds[id] then return nil end
    return 0, false, -1, -1, 0, R.anim, 0
end
function G.FaceLevel(id, level, style, flags)
    rec("FaceLevel", id, level, style, flags)
    if not (int_in(id, 1, 1e9) and num_in(level, -1, 1) and (style == 0 or style == 1) and (flags == nil or flags == 0 or
            (flags == SAME_PAIR and style == 0))) then
        bad("FaceLevel", string.format("%s, %s, %s, %s", tostring(id), tostring(level), tostring(style), tostring(flags)))
    end
    if not face_id(id) then bad("FaceLevel", "a kind without a face (" .. tostring(id) .. ")") end
end
function G.FaceMouth(id, a, b, w, flags)
    rec("FaceMouth", id, a, b, w, flags)
    local nk = KEYS[kinds[id] or -1] or 0
    if not (int_in(id, 1, 1e9) and int_in(a, 0, nk - 1) and int_in(b, 0, nk - 1) and num_in(w, 0, 1) and (flags == nil or
            flags == 0 or flags == SAME_PAIR)) then
        bad("FaceMouth", string.format("%s, %s, %s, %s, %s", tostring(id), tostring(a), tostring(b), tostring(w),
            tostring(flags)))
    end
    if not face_id(id) then bad("FaceMouth", "a kind without a face (" .. tostring(id) .. ")") end
end
-- G-SA1's mouths here are fixed invented numbers (the module's own tests check the real table); an override's entries win
local FAKE = { [2] = { 7, 16, 0.45, "fixed" }, [3] = { 7, 16, 0.2, "fixed" }, [4] = { 0, 4, 1, "scales" },
               [5] = { 6, 16, 0.4, "fixed" }, [6] = { 6, 7, 0.2, "fixed" }, [7] = { 5, 4, 0.6, "fixed" } }
local FV_LEVEL = { [0] = 0.25, [2] = 1 / 6, [3] = 1 / 6, [5] = 0.125, [7] = 0.125 }
local LADDER_CAP = { [0] = 0.5, [2] = 2 / 3, [3] = 2 / 3, [5] = 1, [7] = 1 }
local SNAMES = { "AA", "EH", "EE", "OH", "OO", "SS", "FV" }
local function parse_m(m)
    local body, how = string.match(m, "^(.-):(%a+)$")
    if not body then body, how = m, "fixed" end
    if body == "ladder" then return { a = -1, b = -1, w = 1, how = "ladder" } end
    local lw = string.match(body, "^ladder@([%d%.]+)$")
    if lw then return { a = -1, b = -1, w = tonumber(lw), how = "ladder" } end
    local k = string.match(body, "^(%d+)$")
    if k then return { a = 0, b = tonumber(k), w = 1, how = how } end
    local a, b, w = string.match(body, "^(%d+)>(%d+)@([%d%.]+)$")
    if a then return { a = tonumber(a), b = tonumber(b), w = tonumber(w), how = how } end
    return nil
end
local function over_of(kind, cls, variant)
    local o = R.over[kind]
    local n = SNAMES[cls - 1]
    if not o or not n then return nil end
    local key = n .. (variant == 1 and ".quiet" or (variant == 2 and ".loud" or ""))
    if o[key] then return o[key] end
    if o[n] then return variant == 0 and o[n] or o[n] end
    return nil
end
function G.VisemeMouth(kind, cls, s, size, variant, big)
    local c = rec("VisemeMouth", kind, cls, s, size, variant, big)
    if not (int_in(kind, 0, 8) and int_in(cls, 0, 8) and num_in(s, 0, 1) and num_in(size, 0, 1) and int_in(variant, 0, 2)
            and type(big) == "boolean") then
        bad("VisemeMouth", string.format("%s, %s, %s, %s, %s, %s", tostring(kind), tostring(cls), tostring(s),
            tostring(size), tostring(variant), tostring(big)))
        c.ret = { 0, 0, 0 }
        return 0, 0, 0
    end
    local a, b, w
    local o = over_of(kind, cls, variant)
    if FV_LEVEL[kind] == nil or cls <= 1 then
        a, b, w = 0, 0, 0
    elseif o then
        a, b, w = o.a, o.b, o.how == "ladder" and math.min(s, o.w) or o.w
    elseif cls == 8 then
        a, b, w = -1, -1, math.min(s, FV_LEVEL[kind])
    else
        local e = FAKE[cls]
        a, b = e[1], e[2]
        w = math.min(e[3] * (e[4] == "scales" and (0.5 + 0.5 * s) or 1) + (variant == 2 and 0.05 or 0), 1)
        if kind == 7 then a, b = 0, 4 end
    end
    c.ret = { a, b, w }
    return a, b, w
end
function G.VisemeTable(kind)
    rec("VisemeTable", kind)
    if FV_LEVEL[kind] == nil then return nil, "this character has no face in the game", "unsupported" end
    local t = { kind = kind, keys = KEYS[kind], floor = (kind == 0 or kind == 3) and 0.8 or 0, ladder_cap = LADDER_CAP[kind],
                fv_level = FV_LEVEL[kind], table_version = 2, custom_spec = R.spec[kind] or "",
                mouth_at = { forward = 6, up = 31 } }
    for c = 0, 8 do
        local row
        if c <= 1 then
            row = { a = 0, b = 0, w = 0, how = "closed", expression = false }
        elseif c == 8 then
            row = { a = -1, b = -1, w = FV_LEVEL[kind], how = "ladder", expression = false }
        else
            local e = FAKE[c]
            row = { a = kind == 7 and 0 or e[1], b = kind == 7 and 4 or e[2], w = e[3], how = e[4], expression = c == 2 }
            if c == 2 then row.loud = { a = 7, b = 16, w = 0.75, how = "fixed", expression = true } end
        end
        local o = c >= 2 and over_of(kind, c, 0) or nil
        local anyMine = false
        if R.over[kind] and c >= 2 then
            for k in pairs(R.over[kind]) do
                if string.sub(k, 1, 2) == SNAMES[c - 1] then anyMine = true end
            end
        end
        if anyMine then
            local def = row
            row = o and { a = o.a, b = o.b, w = o.w, how = o.how, expression = false } or
                { a = def.a, b = def.b, w = def.w, how = def.how, expression = def.expression }
            row.custom, row.default = true, def
        else
            row.custom = false
        end
        t[c] = row
    end
    return t
end
R.refuse = nil
function G.VisemeOverride(kind, spec)
    rec("VisemeOverride", kind, spec)
    if not int_in(kind, 0, 8) or type(spec) ~= "string" then
        bad("VisemeOverride", tostring(kind) .. " " .. tostring(spec))
        return nil, "VisemeOverride(kind, spec)", "bad_argument"
    end
    if FV_LEVEL[kind] == nil then
        bad("VisemeOverride", "a faceless kind " .. kind)
        return nil, "this character has no face in the game", "unsupported"
    end
    if R.refuse and string.find(spec, R.refuse, 1, true) then
        return nil, R.refuse .. ": key 99 is not one of the character's face keys", "bad_argument"
    end
    local o = {}
    for it in string.gmatch(spec .. ",", "([^,]*),") do
        if it ~= "" then
            local k, m = string.match(it, "^([%u%.%l]+)=(.+)$")
            local p = m and parse_m(m)
            if not p then return nil, it .. ": not a mouth", "bad_argument" end
            o[k] = p
        end
    end
    R.over[kind] = spec ~= "" and o or nil
    R.spec[kind] = spec
    return true
end
function G.MicDevices()
    return { { index = 0, name = "Default", default = true, enabled = true, loopback = false },
             { index = 1, name = "Microphone (Example USB Mic)", default = true, enabled = true, loopback = false },
             { index = 2, name = "Speakers (Example Card)", default = false, enabled = true, loopback = true } }
end
function G.MicOpen(dev, force)
    rec("MicOpen", dev, force)
    R.mic.open, R.mic.blocks = true, 0
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
    if not R.mic.open then return 0, 0, "off", 0 end
    if not R.mic.listen then return 0, 0, "paused", R.mic.blocks end
    R.mic.blocks = R.mic.blocks + 1
    return R.mic.level, R.mic.level, "on", R.mic.blocks
end
function G.MicViseme()
    rec("MicViseme")
    local v = R.vis
    if not (R.mic.open and R.mic.listen and v.on) then return -1, 0, 0, 0, 0, v.seq end
    return v.cls, v.level, v.f1, v.f2, v.conf, v.seq
end
function G.MicVisemeOn(on)
    rec("MicVisemeOn", on)
    R.vis.on = on == true
    return true
end
function G.MicVisemeTune(name, value)
    rec("MicVisemeTune", name, value)
    return true
end
function G.MicVisemeVoice() return 6.83, 0, 0, 0, 0 end
function G.MicVisemeFeatures() return 0, 0, 0, 0, -1, -1, R.vis.seq, 0, 0 end
function G.MicVisemeWarmup(step)
    rec("MicVisemeWarmup", step)
    return true
end
function G.MicVisemeWarmupState() return -1, 0, 0, 0, 0, 0 end

-- call lists
local function mark() return #R.calls end
local function calls_since(m, name, id)
    local out = {}
    for i = m + 1, #R.calls do
        local c = R.calls[i]
        if (name == nil or c[1] == name) and (id == nil or c[2] == id) then out[#out + 1] = c end
    end
    return out
end
local function count_prefixes(m, prefixes)
    local n = 0
    for i = m + 1, #R.calls do
        local nm = R.calls[i][1]
        for _, p in ipairs(prefixes) do
            if string.sub(nm, 1, #p) == p then
                n = n + 1
                break
            end
        end
    end
    return n
end

-- the GMod parts the feature uses that lua_mock.lua does not have
local keys = {}
local KEY_X = 34
input = {
    IsButtonDown = function(code) return keys[code] == true end,
    GetKeyName = function(code) return "key" .. tostring(code) end,
    LookupBinding = function(b) return b == "+voicerecord" and "x" or nil end,
    GetKeyCode = function(n) return n == "x" and KEY_X or 0 end,
}
M.player.IsTyping = function() return false end
M.player.IsSpeaking = function() return false end
M.player.VoiceVolume = function() return 0 end
vgui.CursorVisible = function() return false end

-- the page's controls: stand-ins that record their calls, with a hover and a visible state (rawset by the test). Event
-- handlers and Think / Paint are the addon's own (nil until it sets them), as on a fresh Derma control
local made = {}
local HANDLERS = { Think = true, Paint = true, PerformLayout = true, DoClick = true, OnSelect = true, OnCursorEntered = true,
                   OnCursorExited = true, OnValueChanged = true, OnChange = true, DoDoubleClick = true, OnRowSelected = true }
-- the queries Derma answers every frame (no record, one shared function: Garry's Mod's are methods, they make nothing)
local QUERIES = {
    IsHovered = function(self) return rawget(self, "hovered") == true end,
    IsVisible = function(self) return rawget(self, "visible") ~= false end,
    GetParent = function() return nil end,
}
local function standin(kind)
    local P = { kind = kind, calls = {}, lines = {}, choices = {} }
    made[#made + 1] = P
    return setmetatable(P, { __index = function(t, k)
        if QUERIES[k] then return QUERIES[k] end
        if type(k) ~= "string" or not string.match(k, "^%u") or HANDLERS[k] then return nil end
        return function(self, ...)
            local a = { ... }
            t.calls[#t.calls + 1] = { k, ... }
            if k == "SetText" then t.text = a[1] return end
            if k == "SetConVar" then t.convar = a[1] return end
            if k == "SetValue" then t.value = a[1] return end
            if k == "GetValue" then return t.value end
            if k == "SetChecked" then t.checked = a[1] return end
            if k == "SetEnabled" then t.enabled = a[1] return end
            if k == "LocalToScreen" then return 100, 200 end
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

-- the close-up's RenderView: the render hooks the loaded addon registered and the entities' draws, with EyePos() = the
-- view's origin (as the engine runs a view); rv.mode "run" (default), "nothing" (the negative control), "error"
local rv = { calls = 0, mode = "run", hookSeen = 0, eyes = {} }
local RENDER_HOOKS = { "PreDrawOpaqueRenderables", "PostDrawOpaqueRenderables", "PreDrawTranslucentRenderables",
                       "PostDrawTranslucentRenderables", "PreDrawHalos", "PostDrawEffects" }
render.RenderView = function(v)
    rv.calls = rv.calls + 1
    rv.last = { origin = Vector(v.origin), angles = Angle(v.angles), x = v.x, y = v.y, w = v.w, h = v.h, fov = v.fov,
                hud = v.drawhud, post = v.dopostprocess, vm = v.drawviewmodel }
    if rv.mode == "error" then error("RenderView: test error") end
    if rv.mode == "nothing" then return end
    local saved = M.view_origin
    M.view_origin = Vector(v.origin)
    M.run_hook("PreDrawOpaqueRenderables", false, false, false)
    for _, e in ipairs(M.entities) do
        if not e.removed and e.Draw then e:Draw(0) end
    end
    M.run_hook("PostDrawOpaqueRenderables", false, false, false)
    M.run_hook("PreDrawTranslucentRenderables", false, false, false)
    for _, e in ipairs(M.entities) do
        if not e.removed and e.DrawTranslucent then e:DrawTranslucent(0) end
    end
    M.run_hook("PostDrawTranslucentRenderables", false, false, false)
    M.run_hook("PreDrawHalos")
    M.run_hook("PostDrawEffects")
    M.view_origin = saved
end
-- a test-only hook: proves this RenderView ran the render hooks with the close-up's eye
hook.Add("PreDrawOpaqueRenderables", "gsa1_test_closeup", function()
    rv.hookSeen = rv.hookSeen + 1
    rv.eyes[#rv.eyes + 1] = EyePos()
end)

-- 0. loading -------------------------------------------------------------------------------------------------------------
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local F = GSA1 and GSA1.Faces
check(ok_load and #ferr == 0 and F ~= nil and F.TesterFrame ~= nil and F.TesterRows ~= nil and F.MouthUse ~= nil and
    F.MouthParseFile ~= nil, "the autorun loads sh_faces.lua, sh_mouths.lua, cl_faces.lua and cl_mouthtest.lua (%s)",
    ok_load and table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_load or ferr[1]))
if not (ok_load and F and F.TesterFrame) then return done() end
local T, L = F.tester, F.lip
local logs = {}
local realLog = GSA1.Log
GSA1.Log = function(kind, fmt, ...)
    local okf, text = pcall(string.format, fmt, ...)
    logs[#logs + 1] = { kind = kind, text = okf and text or tostring(fmt) }
    return realLog(kind, fmt, ...)
end
local function logs_with(plain)
    local out = {}
    for _, l in ipairs(logs) do
        if string.find(l.text, plain, 1, true) then out[#out + 1] = l.text end
    end
    return out
end

-- a saved file: Sonic's ee and loud ah, Amy's s; one line of a character this G-SA1 does not know (kept, not applied)
local MOUTH_FILE = F.MOUTH_FILE or "gsa1/mouth_shapes.txt"
local sample = { [0] = { items = { EE = "0>17@0.8:scales", ["AA.loud"] = "7>16@0.7" } }, [5] = { items = { SS = "0>5@0.6:scales" } } }
M.files[MOUTH_FILE] = F.MouthSerializeFile(sample) .. "shadow\tAA=4\n"
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }

-- L7 (load, review R.8): every face kind gets its line's spec or ""
local m0 = mark()
GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil and C.kind == 0, "Sonic spawned")
if not C then return done() end
do
    local ov = calls_since(m0, "VisemeOverride")
    local got = {}
    for _, c in ipairs(ov) do got[c[2]] = c[3] end
    local okKinds = got[0] == F.MouthSpec(sample[0].items) and got[5] == F.MouthSpec(sample[5].items) and got[2] == "" and
        got[3] == "" and got[7] == "" and #ov == 5
    check(okKinds and #F.mouthBad == 1 and F.mouthBad[1] and string.find(tostring(F.mouthBad[1].text), "shadow", 1, true),
        "L7 at load every face kind gets its spec or \"\" (review R.8: %d calls; Sonic \"%s\"); the unknown character's "
        .. "line is kept, not applied", #ov, tostring(got[0]))
    check(M.convars.gsa1_mouth_summary.v == "Sonic - ah, ee; Amy - s z sh" and #logs_with("mouth shapes: your mouths - "
        .. "Sonic: ah, ee; Amy: s z sh") == 1, "L7 the summary ConVar \"%s\" and one load line",
        M.convars.gsa1_mouth_summary.v)
end

local function frames(n, think)
    for _ = 1, n or 1 do
        if think then think() end
        M.frame(1 / 60)
    end
end

-- L12. the page -----------------------------------------------------------------------------------------------------------
M.menu = {}
M.run_hook("PopulateToolMenu")
local entry
for _, e in ipairs(M.menu) do
    if e.class == "gsa1_feat_faces" then entry = e end
end
local function build_page()
    made = {}
    local panel = standin("DForm")
    local pok, perr = pcall(entry.cpanel, panel)
    if not pok then print("        page: " .. tostring(perr)) end
    return pok
end
local function roles(role)
    local out = {}
    for _, P in ipairs(made) do
        if rawget(P, "gsa1Role") == role then out[#out + 1] = P end
    end
    return out
end
local function role(r) return roles(r)[1] end
local function bound_convars()
    local bound = {}
    for _, P in ipairs(made) do
        for _, c in ipairs(P.calls) do
            if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" then bound[c[3]] = true end
        end
        if P.convar then bound[P.convar] = true end
        if rawget(P, "gsa1ConVar") then bound[rawget(P, "gsa1ConVar")] = true end
    end
    return bound
end
-- the page's thinks (Derma runs them every frame while the page is shown)
local thinkers = {}
local function collect_thinkers()
    thinkers = {}
    for _, P in ipairs(made) do
        if rawget(P, "Think") then thinkers[#thinkers + 1] = P end
    end
end
local function page_think()
    for i = 1, #thinkers do
        local P = thinkers[i]
        P.Think(P)
    end
end
check(entry ~= nil, "the page Options -> G-SA1 -> Faces")
if not entry then return done() end
local pok = build_page()
collect_thinkers()
local btn = roles("mouthbtn")
local words = {}
for i, b in ipairs(btn) do words[i] = tostring(rawget(b, "gsa1Class")) end
local want = { "showas", "playall", "stop", "closeup", "custom", "resetchar", "resetall", "closeuppic", "showing",
               "changelist", "usefor", "keya", "keyb", "weight", "scales", "pairshow", "pairuse", "mouthsummary",
               "microphone", "listening", "hearing", "warmup", "warmline" }
local missing = {}
for _, r in ipairs(want) do
    if not role(r) then missing[#missing + 1] = r end
end
check(pok and #btn == 8 and table.concat(words, " ") == "1 2 3 4 5 6 7 8" and #roles("mouthrow") == 7 and #missing == 0,
    "L12 the tester's controls: 8 sound buttons (%s), 7 mouth rows, %s", table.concat(words, " "), #missing == 0 and
    "every role" or ("missing " .. table.concat(missing, " ")))
do
    local bound = bound_convars()
    local cvs = { "gsa1_lipsync_device_name", "gsa1_lipsync_hearing", "gsa1_lipsync_shapes_adapt", "gsa1_lipsync_shapes_log",
                  "gsa1_mouth_closeup", "gsa1_lipsync_shapes_custom", "gsa1_mouth_summary" }
    local miss = {}
    for _, n in ipairs(cvs) do
        if not bound[n] then miss[#miss + 1] = n end
    end
    local defs = { gsa1_lipsync_device_name = { "" }, gsa1_lipsync_hearing = { "2", 1, 2 }, gsa1_mouth_closeup = { "1", 0, 1 },
                   gsa1_lipsync_shapes_custom = { "1", 0, 1 }, gsa1_mouth_summary = { nil } }
    local wrong = {}
    for n, w in pairs(defs) do
        local c = M.convars[n]
        local okc = c and c.client and c.save and GSA1.CONVARS[n]
        if okc and w[1] ~= nil then okc = GSA1.CONVARS[n].default == w[1] end
        if okc and w[2] ~= nil then okc = c.lo == w[2] and c.hi == w[3] end
        if not okc then wrong[#wrong + 1] = n end
    end
    table.sort(wrong)
    check(#miss == 0 and #wrong == 0, "L12 every ConVar of lipsync2_plan.md 7.1 / 7.2 has its control and default%s%s",
        #miss > 0 and (": no control for " .. table.concat(miss, " ")) or "", #wrong > 0 and ("; wrong " ..
        table.concat(wrong, " ")) or "")
end

-- helpers for the tester's frames
local function hover(b, on) rawset(b, "hovered", on and true or nil) end
local function minus_of(cs)
    local n = 0
    for _, c in ipairs(cs) do
        if c[1] == "FaceLevel" and c[3] == -1 then n = n + 1 end
    end
    return n
end
-- per frame: the mouth calls for the character after VisemeMouth calls (pairs)
local function frame_calls(m, id)
    local vm, face, minus = {}, {}, 0
    for i = m + 1, #R.calls do
        local c = R.calls[i]
        if c[1] == "VisemeMouth" then
            vm[#vm + 1] = c
        elseif (c[1] == "FaceMouth" or c[1] == "FaceLevel") and c[2] == id then
            if c[1] == "FaceLevel" and c[3] == -1 then minus = minus + 1 else face[#face + 1] = c end
        end
    end
    return vm, face, minus
end
local function vis(cls, level)
    R.vis.cls, R.vis.level, R.vis.f1, R.vis.f2, R.vis.conf = cls, level or 0.7, 700, 1200, 0.8
    R.vis.seq = (R.vis.seq + 1) % 65536
end
frames(10, page_think)

-- L3. point ---------------------------------------------------------------------------------------------------------------
do
    local ah, ee, fv = btn[2], btn[4], btn[8]
    local perFrame, sameNumbers, okCls = true, true, true
    local m = mark()
    hover(ah, true)
    for _ = 1, 20 do
        local f0 = mark()
        frames(1, page_think)
        local vm, face, minus = frame_calls(f0, C.id)
        perFrame = perFrame and #vm == 1 and #face == 1 and minus == 0
        if vm[1] and face[1] then
            local r = vm[1].ret
            okCls = okCls and vm[1][3] == 2 and vm[1][4] == 1 and vm[1][6] == 0
            sameNumbers = sameNumbers and face[1][1] == "FaceMouth" and face[1][3] == r[1] and face[1][4] == r[2] and
                face[1][5] == r[3] and face[1][6] == SAME_PAIR
        end
    end
    -- moving to the next button: no -1
    hover(ah, false)
    hover(ee, true)
    local mm = mark()
    frames(10, page_think)
    local vmE, _, minusMove = frame_calls(mm, C.id)
    local eeOk = #vmE == 10 and vmE[10][3] == 4
    -- "Show as" quiet, then a ladder entry (f v th): one FaceLevel per frame with VisemeMouth's w, capped
    role("showas").OnSelect(role("showas"), 2, "quiet", 1)
    local mq = mark()
    frames(3, page_think)
    local vmQ = frame_calls(mq, C.id)
    local quietOk = #vmQ == 3 and vmQ[3][4] == 0.35 and vmQ[3][6] == 1
    role("showas").OnSelect(role("showas"), 1, "normal", 0)
    hover(ee, false)
    hover(fv, true)
    local mf = mark()
    frames(5, page_think)
    local vmF, faceF = frame_calls(mf, C.id)
    local fvOk = #vmF == 5 and #faceF == 5 and faceF[5][1] == "FaceLevel" and faceF[5][3] == vmF[5].ret[3] and
        faceF[5][4] == 0 and faceF[5][5] == SAME_PAIR
    -- nothing pointed at: still shown for 0.15 s, then exactly one -1
    hover(fv, false)
    local ml = mark()
    local shownAfter = 0
    for _ = 1, 30 do
        local f0 = mark()
        frames(1, page_think)
        local vm = frame_calls(f0, C.id)
        if #vm > 0 then shownAfter = shownAfter + 1 end
    end
    local _, _, minusEnd = frame_calls(ml, C.id)
    local lastMinus = calls_since(ml, "FaceLevel", C.id)
    check(perFrame and sameNumbers and okCls, "L3 pointing at \"ah\": every frame exactly one VisemeMouth(0, 2, 1, size, 0, "
        .. "big) and one FaceMouth(id, a, b, w, SAME_PAIR) with its numbers, no -1")
    check(eeOk and minusMove == 0 and quietOk and fvOk, "L3 moving to \"ee\" sends no -1; \"Show as\" quiet = s 0.35, "
        .. "variant 1; \"f v th\" (a ladder entry) = one FaceLevel(id, w, 0, SAME_PAIR) per frame with VisemeMouth's w")
    check(minusEnd == 1 and shownAfter >= 7 and shownAfter <= 10 and lastMinus[#lastMinus][4] == 0 and
        lastMinus[#lastMinus][5] == nil and not T.active, "L3 nothing pointed at: the mouth stays 0.15 s (%d frames), then "
        .. "exactly one FaceLevel(id, -1, 0) (%d)", shownAfter, minusEnd)
    check(#calls_since(m, "MicOpen") == 0 and #calls_since(m, "MicListen") == 0, "the tester never opens the microphone")
end

-- L4. keep ------------------------------------------------------------------------------------------------------------------
do
    local ah, oh = btn[2], btn[5]
    local m = mark()
    ah.DoClick(ah)
    local shown, minus = 0, 0
    -- the page hidden (no Think) for 20 s
    for _ = 1, 20 * 60 + 30 do
        local f0 = mark()
        frames(1)
        local vm, face, mi = frame_calls(f0, C.id)
        if #vm == 1 and #face == 1 then shown = shown + 1 end
        minus = minus + mi
    end
    check(shown >= 1195 and shown <= 1202 and minus == 1 and not T.active, "L4 a click keeps \"ah\" 20 s with the page "
        .. "hidden (%d frames), then one -1 (%d)", shown, minus)
    -- another button: no -1, the new one at once; a second click: one -1
    ah.DoClick(ah)
    frames(5)
    local mo = mark()
    oh.DoClick(oh)
    frames(1)
    local vmO, _, minO = frame_calls(mo, C.id)
    local ms = mark()
    oh.DoClick(oh)
    frames(3)
    local vmS, _, minS = frame_calls(ms, C.id)
    check(#vmO == 1 and vmO[1][3] == 5 and minO == 0 and #vmS == 0 and minS == 1, "L4 another button takes over at once "
        .. "(no -1); a second click lets go with one -1")
    -- Stop
    ah.DoClick(ah)
    frames(3)
    local mst = mark()
    role("stop").DoClick(role("stop"))
    local minStop = minus_of(calls_since(mst))
    frames(3)
    check(minStop == 1 and #calls_since(mst, "VisemeMouth") == 0, "L4 Stop: one -1 at once, nothing after")
    -- a face animation
    ah.DoClick(ah)
    frames(3)
    local ma = mark()
    F.Play(C, "Happy", "test")
    local seqA = calls_since(ma)
    frames(3)
    local orderOk = seqA[1] and seqA[1][1] == "FaceLevel" and seqA[1][3] == -1 and seqA[2] and seqA[2][1] == "FaceSequence"
    check(orderOk and #calls_since(ma, "VisemeMouth") == 0, "L4 F.PlayAnim ends the kept mouth: one -1, then its "
        .. "FaceSequence, then no tester call")
    -- the character changing: no call to the old one, nothing to the new one
    ah.DoClick(ah)
    frames(3)
    local oldId = C.id
    local mc = mark()
    GSA1.Spawn("tails")
    C = GSA1.Char
    frames(5)
    check(C.kind == 2 and #calls_since(mc, "FaceLevel", oldId) == 0 and #calls_since(mc, "FaceMouth", oldId) == 0 and
        #calls_since(mc, "VisemeMouth") == 0 and not T.active, "L4 the character changing ends the kept mouth (no call to "
        .. "the old one, none to the new one)")
    GSA1.Spawn("sonic")
    C = GSA1.Char
    frames(5, page_think)
    -- the talk key: nothing from the tester, lip sync's mouth in the same frame
    ah.DoClick(ah)
    frames(10)
    vis(4, 0.7)
    local mk = mark()
    keys[KEY_X] = true
    frames(1)
    local vmK, faceK, minK = frame_calls(mk, C.id)
    local lipOk = #vmK == 1 and vmK[1][3] == 4 and #faceK == 1 and minK == 0 and L.talking == true and not T.active
    for _ = 1, 20 do
        vis(4, 0.7)
        frames(1)
    end
    keys[KEY_X] = false
    for _ = 1, 80 do
        vis(0, 0)
        frames(1)
    end
    check(lipOk, "L4 the talk key going down ends the kept mouth: no tester call, lip sync's \"ee\" (VisemeMouth class 4 "
        .. "and its FaceMouth) in the same frame")
end

-- L5. Play all -----------------------------------------------------------------------------------------------------------------
do
    local m = mark()
    local pa = role("playall")
    pa.DoClick(pa)
    local seq = {}
    for _ = 1, 8 * 30 + 20 do
        local f0 = mark()
        frames(1)
        local vm = frame_calls(f0, C.id)
        if vm[1] then seq[#seq + 1] = vm[1][3] end
    end
    local runs, last, n = {}, nil, 0
    for _, c in ipairs(seq) do
        if c ~= last then
            if last then runs[#runs + 1] = { last, n } end
            last, n = c, 0
        end
        n = n + 1
    end
    if last then runs[#runs + 1] = { last, n } end
    local order, lengths = {}, true
    for i, r in ipairs(runs) do
        order[i] = tostring(r[1])
        lengths = lengths and r[2] >= 29 and r[2] <= 31
    end
    local _, _, minus = frame_calls(m, C.id)
    check(table.concat(order, " ") == "1 2 3 4 5 6 7 8" and lengths and minus == 1 and not T.active, "L5 Play all: the 8 "
        .. "sounds in order (%s), half a second each, then one -1 (%d)", table.concat(order, " "), minus)
end

-- L6. lip sync yields; every talk spurt ends with exactly one -1 ---------------------------------------------------------------
do
    local m = mark()
    local ah = btn[2]
    keys[KEY_X] = true
    for _ = 1, 20 do
        vis(3, 0.7)
        frames(1, page_think)
    end
    local talking1 = L.talking
    -- a pointer while talking
    hover(ah, true)
    local mp = mark()
    local one = true
    for _ = 1, 30 do
        vis(3, 0.7)
        local f0 = mark()
        frames(1, page_think)
        local vm, face = frame_calls(f0, C.id)
        one = one and #vm == 1 and vm[1][3] == 2 and #face == 1
    end
    local _, _, minusWhile = frame_calls(mp, C.id)
    hover(ah, false)
    for _ = 1, 30 do
        vis(3, 0.7)
        frames(1, page_think)
    end
    local talkingAgain = L.talking
    keys[KEY_X] = false
    for _ = 1, 90 do
        vis(0, 0)
        frames(1, page_think)
    end
    -- the run's stream of mouth calls for the character: every stretch of mouths ends with exactly one -1
    local stream, okStream, mouths = {}, true, 0
    for i = m + 1, #R.calls do
        local c = R.calls[i]
        if (c[1] == "FaceMouth" or c[1] == "FaceLevel") and c[2] == C.id then
            local isMinus = c[1] == "FaceLevel" and c[3] == -1
            if isMinus then
                okStream = okStream and mouths > 0
                mouths = 0
                stream[#stream + 1] = "-1"
            else
                mouths = mouths + 1
            end
        end
    end
    okStream = okStream and mouths == 0 and #stream == 2
    check(talking1 and one and minusWhile == 0, "L6 talking + a pointer: the tester's mouth every frame, lip sync's -1 "
        .. "never sent while it draws")
    check(talkingAgain and okStream and not L.talking, "L6 talking restarts cleanly after the pointer; the whole run's "
        .. "mouth stretches each end with exactly one -1 (%d)", #stream)
end

-- L7. Use / Back / Reset character / Reset all ---------------------------------------------------------------------------------
do
    local function file_writes(m)
        local n = 0
        for i = m + 1, #writes do
            if writes[i][2] == MOUTH_FILE then n = n + 1 end
        end
        return n
    end
    local ser = 0
    local realSer = F.MouthSerializeFile
    F.MouthSerializeFile = function(...)
        ser = ser + 1
        return realSer(...)
    end
    local function cached(kind) return F.vtab[kind] ~= nil end
    -- Use: "ah" of Sonic from the change list (its first line that is not G-SA1's ah)
    local rows = roles("mouthrow")
    local chg = nil
    for _, P in ipairs(made) do
        if rawget(P, "gsa1Role") == "change" then chg = chg or P end
    end
    chg.DoClick(chg)                       -- "Change" of the first row: ah
    local list = role("changelist")
    page_think()
    local line = list.lines[2] or list.lines[1]
    F.VisemeTable(0)
    local w0, s0, m = #writes, ser, mark()
    list.DoDoubleClick(list, 2, line)
    local ov = calls_since(m, "VisemeOverride")
    local want = F.MouthSpec({ AA = line.gsa1Mouth, EE = "0>17@0.8:scales", ["AA.loud"] = "7>16@0.7" })
    local useOk = #ov == 1 and ov[1][2] == 0 and ov[1][3] == want and file_writes(w0) == 1 and ser - s0 == 1 and
        not cached(0) and string.find(M.files[MOUTH_FILE] or "", "AA=" .. line.gsa1Mouth, 1, true) ~= nil and
        string.find(M.files[MOUTH_FILE] or "", "shadow\tAA=4", 1, true) ~= nil
    check(useOk, "L7 Use (double-click a line of the list): VisemeOverride(0, \"%s\"), the file written once through "
        .. "F.MouthSerializeFile (the unknown character's line kept), the table cache cleared", tostring(ov[1] and ov[1][3]))
    check(#logs_with("mouth shapes: Sonic's ah is now") == 1, "L7 Use: one log line")
    -- Back to G-SA1's (ah's row)
    F.VisemeTable(0)
    page_think()
    w0, s0, m = #writes, ser, mark()
    local backBtn
    for _, P in ipairs(made) do
        if rawget(P, "gsa1Role") == "back" then backBtn = backBtn or P end
    end
    backBtn.DoClick(backBtn)
    ov = calls_since(m, "VisemeOverride")
    local backOk = #ov == 1 and ov[1][3] == F.MouthSpec(sample[0].items) and file_writes(w0) == 1 and ser - s0 == 1 and
        not cached(0) and M.convars.gsa1_mouth_summary.v == "Sonic - ah, ee; Amy - s z sh"
    check(backOk, "L7 Back to G-SA1's: VisemeOverride(0, the saved rest), the file once, the cache cleared, the summary "
        .. "\"%s\"", M.convars.gsa1_mouth_summary.v)
    -- Reset Sonic
    F.VisemeTable(0)
    w0, s0, m = #writes, ser, mark()
    role("resetchar").DoClick(role("resetchar"))
    ov = calls_since(m, "VisemeOverride")
    check(#ov == 1 and ov[1][2] == 0 and ov[1][3] == "" and file_writes(w0) == 1 and ser - s0 == 1 and not cached(0) and
        M.convars.gsa1_mouth_summary.v == "Amy - s z sh" and #logs_with("Sonic reset to G-SA1's table") == 1,
        "L7 Reset Sonic: VisemeOverride(0, \"\"), the file once, the summary \"%s\"", M.convars.gsa1_mouth_summary.v)
    -- Reset every character: No changes nothing, Yes resets
    w0, s0, m = #writes, ser, mark()
    role("resetall").DoClick(role("resetall"))
    local q = queries[#queries]
    local asked = q ~= nil and string.find(q.text, "every character", 1, true) ~= nil and #calls_since(m) == 0 and
        file_writes(w0) == 0
    q.no()
    local noOk = #calls_since(m, "VisemeOverride") == 0 and file_writes(w0) == 0 and M.convars.gsa1_mouth_summary.v ==
        "Amy - s z sh"
    role("resetall").DoClick(role("resetall"))
    queries[#queries].yes()
    ov = calls_since(m, "VisemeOverride")
    check(asked and noOk and #ov == 1 and ov[1][2] == 5 and ov[1][3] == "" and file_writes(w0) == 1 and ser - s0 == 1 and
        M.convars.gsa1_mouth_summary.v == "" and string.find(M.files[MOUTH_FILE] or "", "shadow\tAA=4", 1, true) ~= nil,
        "L7 Reset every character asks first (No: nothing), Yes: VisemeOverride(5, \"\"), the file once (the unknown "
        .. "line kept), the summary empty")
    -- a line the module refuses: kept in the file, listed on the page, the kind cleared in the module
    R.refuse = "OO=6"
    local text = F.MouthSerializeFile({ [0] = { items = { OO = "6" } }, [2] = { items = { EE = "6" } } })
    M.files[MOUTH_FILE] = text
    F.mouthApplied = nil
    m = mark()
    w0 = #writes
    F.MouthEnsure()
    ov = calls_since(m, "VisemeOverride")
    local sonicCalls = {}
    for _, c in ipairs(ov) do if c[2] == 0 then sonicCalls[#sonicCalls + 1] = c[3] end end
    local unused = role("unused")
    unused.gsa1Next = nil
    unused.Think(unused)
    check(F.mouthRefused[0] ~= nil and sonicCalls[#sonicCalls] == "" and file_writes(w0) == 0 and
        string.find(tostring(unused.text), "1 line", 1, true) ~= nil and #logs_with("Sonic's saved mouths were not used") ==
        1, "L7 a line the module refuses: not applied (VisemeOverride(0, \"\") after it), the file untouched, the page "
        .. "says \"%s\", one log line", tostring(unused.text))
    -- the next action keeps the refused line in the file
    w0 = #writes
    F.MouthUse(2, "AA", "0>16@1")
    check(string.find(M.files[MOUTH_FILE] or "", "OO=6", 1, true) ~= nil and file_writes(w0) == 1, "L7 the refused line "
        .. "stays in the file after another action")
    R.refuse = nil
    F.MouthSerializeFile = realSer
end

-- L9. "Use my mouths" ------------------------------------------------------------------------------------------------------
do
    M.files[MOUTH_FILE] = F.MouthSerializeFile(sample)
    F.mouthApplied = nil
    F.MouthEnsure()
    local before = M.files[MOUTH_FILE]
    local w0, m = #writes, mark()
    RunConsoleCommand("gsa1_lipsync_shapes_custom", "0")
    local off = calls_since(m, "VisemeOverride")
    local offKinds = {}
    for _, c in ipairs(off) do offKinds[#offKinds + 1] = c[2] .. "=" .. (c[3] == "" and "empty" or c[3]) end
    m = mark()
    RunConsoleCommand("gsa1_lipsync_shapes_custom", "1")
    local on = calls_since(m, "VisemeOverride")
    local onOk = #on == 2 and on[1][2] == 0 and on[1][3] == F.MouthSpec(sample[0].items) and on[2][2] == 5 and
        on[2][3] == F.MouthSpec(sample[5].items)
    local nw = 0
    for i = w0 + 1, #writes do if writes[i][2] == MOUTH_FILE then nw = nw + 1 end end
    check(table.concat(offKinds, " ") == "0=empty 5=empty" and onOk and nw == 0 and M.files[MOUTH_FILE] == before,
        "L9 \"Use my mouths\" off: VisemeOverride(kind, \"\") for each kind with a line (%s), the file untouched; on: "
        .. "applied again", table.concat(offKinds, " "))
end

-- L10. no face; Big ------------------------------------------------------------------------------------------------------------
do
    local okAll, why = true, ""
    for _, n in ipairs({ "gamma", "supersonic", "supersonic_general" }) do
        GSA1.Spawn(n)
        local X = GSA1.Char
        F.tpage.at = nil
        page_think()
        local greyed = true
        for _, b in ipairs(btn) do greyed = greyed and b.enabled == false end
        local m = mark()
        hover(btn[2], true)
        btn[2].OnCursorEntered(btn[2])
        btn[3].DoClick(btn[3])
        role("playall").DoClick(role("playall"))
        frames(20, page_think)
        hover(btn[2], false)
        local n3 = count_prefixes(m, { "Face", "Viseme", "Mic" })
        if not (X and greyed and n3 == 0) then
            okAll = false
            why = why .. string.format(" %s (greyed %s, %d calls)", n, tostring(greyed), n3)
        end
    end
    check(okAll, "L10 E-102 and both Super Sonics: the sound buttons greyed, pointing / clicking / Play all make no module "
        .. "call at all%s", why)
    GSA1.Spawn("big")
    F.tpage.at = nil
    local who = role("testerwho")
    who.gsa1Next = nil
    who.Think(who)
    check(string.find(tostring(who.text), "Big's face has one mouth shape: only its size changes", 1, true) ~= nil,
        "L10 Big: \"%s\"", tostring(who.text))
    GSA1.Spawn("sonic")
    C = GSA1.Char
    F.tpage.at = nil
    frames(5, page_think)
end

-- L13. the close-up ---------------------------------------------------------------------------------------------------------------
do
    local pic = role("closeuppic")
    local function paint() pic.Paint(pic, 256, 192) end
    local counted = {}
    local pre, think = 0, 0
    hook.Add("GSA1PreTick", "gsa1_test_count", function() pre = pre + 1 end)
    hook.Add("Think", "gsa1_test_count", function() think = think + 1 end)
    frames(3, page_think)
    local function snapshot()
        return { pre = pre, think = think, tick = R.counts.Tick, render = R.counts.Render, poll = R.counts.PollEvents,
                 audio = R.counts.AudioUpdate, T = M.T, frame = M.frameNo, clast = C.last, llast = L.last,
                 gen = C.renderGen, vframe = GSA1.view and GSA1.view.frame }
    end
    local function same(a, b)
        for k, v in pairs(a) do
            if b[k] ~= v then return false, k end
        end
        return true
    end
    -- the negative control: a RenderView that runs nothing does not prove the hooks ran
    rv.mode = "nothing"
    local h0 = rv.hookSeen
    paint()
    local negative = rv.hookSeen == h0 and rv.calls == 1
    rv.mode = "run"
    local s0 = snapshot()
    h0 = rv.hookSeen
    local e0 = #rv.eyes
    local calls0 = rv.calls
    paint()
    local s1 = snapshot()
    local stable, which = same(s0, s1)
    local eye = rv.eyes[#rv.eyes]
    local lv = rv.last
    local eyeOk = #rv.eyes == e0 + 1 and eye and lv and math.abs(eye.x - lv.origin.x) < 1e-6 and
        math.abs(eye.z - lv.origin.z) < 1e-6
    -- the camera: 40 HU in front of the mouth point (VisemeTable's mouth_at {6, 31}) facing back
    local yaw = math.rad(tonumber(C.drawYaw) or 0)
    local camOk = lv and math.abs(lv.origin.x - (C.drawPos.x + math.cos(yaw) * 46)) < 1e-6 and
        math.abs(lv.origin.z - (C.drawPos.z + 31)) < 1e-6 and lv.fov == 30 and lv.hud == false and lv.post == false and
        lv.vm == false and lv.w == 256 and lv.h == 192 and lv.x == 100 and lv.y == 200
    check(negative, "L13 the negative control: a RenderView that runs nothing leaves the test hook unrun")
    check(rv.calls == calls0 + 1 and rv.hookSeen == h0 + 1 and eyeOk and camOk, "L13 the close-up: one RenderView "
        .. "{origin 40 HU in front of the mouth, fov 30, 256 x 192 at the panel, no HUD / view model / post-processing}; "
        .. "the render hooks ran with EyePos() = its origin")
    check(stable, "L13 during it no GSA1PreTick, Think, gsa1.Tick, gsa1.Render, PollEvents, AudioUpdate, clock, frame or "
        .. "tick counter advanced%s", stable and "" or (": " .. tostring(which)))
    -- not visible, the box off, no character, first person: no RenderView
    local c1 = rv.calls
    rawset(pic, "visible", false)
    paint()
    rawset(pic, "visible", nil)
    RunConsoleCommand("gsa1_mouth_closeup", "0")
    paint()
    RunConsoleCommand("gsa1_mouth_closeup", "1")
    local dist = GSA1.cv.cam_dist:GetString()
    RunConsoleCommand(GSA1.cv.cam_dist.name, "0")
    local drawn = {}
    local realText = draw.SimpleText
    draw.SimpleText = function(t) drawn[#drawn + 1] = t end
    paint()
    RunConsoleCommand(GSA1.cv.cam_dist.name, dist)
    local fpText = drawn[#drawn]
    GSA1.Spawn("gamma")
    paint()
    local gText = drawn[#drawn]
    GSA1.Spawn("sonic")
    C = GSA1.Char
    frames(3, page_think)
    check(rv.calls == c1 and fpText == "The close-up needs the third-person camera" and gText ==
        "E-102 has no face in the game", "L13 no RenderView while the panel is hidden, the box is off, in first person "
        .. "(\"%s\", review R.10) or without a face (\"%s\")", tostring(fpText), tostring(gText))
    -- an error: the text line, one log line, no further RenderView this session
    rv.mode = "error"
    paint()
    local c2 = rv.calls
    paint()
    paint()
    local eText = drawn[#drawn]
    rv.mode = "run"
    draw.SimpleText = realText
    check(rv.calls == c2 and #logs_with("the close-up stopped for this session") == 1 and string.find(tostring(eText),
        "stopped", 1, true) ~= nil, "L13 an error: one log line, the text line \"%s\", no further RenderView",
        tostring(eText))
    hook.Remove("GSA1PreTick", "gsa1_test_count")
    hook.Remove("Think", "gsa1_test_count")
end

-- L11. an older module (no VisemeOverride, feature "faces" 2) ------------------------------------------------------------------
do
    local saved = G.VisemeOverride
    G.VisemeOverride, G.FEATURES.faces = nil, 2
    F.tpage.at = nil
    local okb = build_page()
    collect_thinkers()
    btn = roles("mouthbtn")
    page_think()
    local head = role("mouthsheader")
    head.gsa1Next = nil
    head.Think(head)
    local greyed = role("resetall").enabled == false and role("changelist").enabled == false and
        role("pairuse").enabled == false
    local m = mark()
    hover(btn[2], true)
    frames(5, page_think)
    hover(btn[2], false)
    frames(15, page_think)
    local vm, face, minus = frame_calls(m, C.id)
    check(okb and string.find(tostring(head.text), "needs G-SA1 module 0.9.4e", 1, true) ~= nil and greyed and #vm >= 5 and
        #face >= 5 and minus == 1 and #M.reported == 0, "L11 an older module: the tester works (%d mouths, one -1), "
        .. "\"Your mouths\" greyed: \"%s\"", #face, tostring(head.text))
    G.VisemeOverride, G.FEATURES.faces = saved, 3
    F.tpage.at = nil
    build_page()
    collect_thinkers()
    btn = roles("mouthbtn")
    frames(3, page_think)
end

-- L14. no garbage while idle ------------------------------------------------------------------------------------------------------
do
    -- the tester's code only: F.TesterFrame and the tester's controls' Think, each measured around its own call
    local mine = {}
    for _, P in ipairs(thinkers) do
        local r = rawget(P, "gsa1Role")
        if r == "mouthbtn" or r == "mouthrow" or r == "showing" or r == "testerwho" or r == "mouthsheader" or
            r == "changehead" or r == "changelist" or r == "usefor" or r == "keya" or r == "keyb" or r == "scales" or
            r == "pairuse" or r == "unused" or r == "mouthsummary" or r == "resetchar" or r == "resetall" then
            mine[#mine + 1] = P
        end
    end
    local tf = F.TesterFrame
    local kb = 0
    local perRole = {}
    F.TesterFrame = function(c, now)
        local k0 = collectgarbage("count")
        local r = tf(c, now)
        kb = kb + collectgarbage("count") - k0
        return r
    end
    local function run(shown)
        for _ = 1, 300 do
            if shown then
                for i = 1, #mine do
                    local P = mine[i]
                    local k0 = collectgarbage("count")
                    P.Think(P)
                    local dk = collectgarbage("count") - k0
                    kb = kb + dk
                    if dk > 0 then
                        local r = rawget(P, "gsa1Role")
                        perRole[r] = (perRole[r] or 0) + dk
                    end
                end
            end
            M.frame(1 / 60)
        end
    end
    -- warm up (the first refresh of each line makes its text once), then measure with the JIT compiler off: its traces
    -- are objects of the collector too, so with it on the count would include the compiler's work, not the addon's
    for _ = 1, 3 do
        for i = 1, #mine do mine[i].Think(mine[i]) end
        M.frame(0.6)
    end
    run(true)
    run(false)
    if jit and jit.off then
        jit.off()
        jit.flush()
    end
    collectgarbage("collect")
    collectgarbage("stop")
    kb = 0
    for r in pairs(perRole) do perRole[r] = nil end
    run(true)
    run(false)
    collectgarbage("restart")
    if jit and jit.on then jit.on() end
    F.TesterFrame = tf
    for r, v in pairs(perRole) do info("L14 garbage in %s: %d bytes", tostring(r), math.floor(v * 1024 + 0.5)) end
    -- the harness sees garbage when there is some (a Think that makes one table a frame)
    local probe = 0
    collectgarbage("stop")
    for _ = 1, 10 do
        local k0 = collectgarbage("count")
        local t = { probe }
        probe = probe + collectgarbage("count") - k0 + (#t - 1)
    end
    collectgarbage("restart")
    check(probe > 0, "L14 the measurement sees a table made per frame (%d bytes in 10 frames)", math.floor(probe * 1024 +
        0.5))
    check(kb == 0 and #mine >= 20, "L14 600 idle frames (the tester shown with nothing pointed at, then not shown): %d "
        .. "bytes made in the tester's code (%d controls' Think and F.TesterFrame)", math.floor(kb * 1024 + 0.5), #mine)
end

check(#R.bad == 0, "every module call had valid arguments%s", #R.bad > 0 and (": " .. table.concat(R.bad, "; ", 1,
    math.min(#R.bad, 6))) or "")
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
