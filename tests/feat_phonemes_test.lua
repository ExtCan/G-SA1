-- feat_phonemes_test.lua - lip sync's style 2, "mouth shapes from your voice" (round 0.9.4c: sadc docs/research/
-- phoneme_plan.md 6.3 P1-P13 with its Review R.1 / R.2 / R.5 / R.6 / R.10 / R.11 / R.18, and the owner's answers 10.1),
-- the addon's side (addon/lua/gsa1/feat/sh_faces.lua, cl_faces.lua) in Garry's Mod's own LuaJIT with tests/lua_mock.lua
-- and a mock of the module's feature "faces" 2 (src/module/bind_faces.cpp, phoneme_plan.md 5.5) made in this file:
-- MicViseme scripted per frame, VisemeMouth / VisemeTable returning fixed numbers, FaceMouth / FaceLevel / MicOpen /
-- MicListen / MicVisemeOn / MicVisemeTune recording their calls. The stubs lua_mock.lua lacks live here (cookie, input,
-- the player's voice, the page's controls, the module's new functions); lua_mock.lua is not changed.
--   P1  convars: every ConVar of phoneme_plan.md 7.1 with its default and range, each bound to a control on the Faces page;
--       the "Mouth" combo has three choices; the Forget button, the Sound now line, the words, the microphone test.
--   P2  move: a saved style 0 without the cookie becomes 2 once (one log line); 1 stays 1; a second load changes nothing.
--   P3  frame: SIL, AA x5, EH x3, MBP, OO x4, FV x3, SIL...: each talking frame one VisemeMouth(kind, held class, s, 0.5,
--       variant, true) and then FaceMouth(id, a, b, w, SAME_PAIR) with exactly its numbers; a = -1 -> FaceLevel(id, w, 0,
--       SAME_PAIR) (VisemeMouth's w, not s: review R.1); exactly one FaceLevel(id, -1, 0) after the hang; nothing before.
--   P4  hold (review R.5): F.HoldClass's one rule (quick 1/30 s, steadier 2/30 s, instant; MBP at once; SIL held; cls -1
--       and a seq frozen 0.1 s = SIL) and through the frames (a one-frame blip inside the hold is never sent).
--   P5  hang: MBP and vowels keep talking alive; SIL longer than the hang -> -1 once.
--   P6  variants (review R.6): quiet / loud, the hysteresis (0.78 / 0.82 alternating stays loud), a variant change waits
--       for the hold; big off -> VisemeMouth's big false and style 0's level capped at VisemeTable(kind).ladder_cap.
--   P7  fall-backs (phoneme_plan.md 4.7): Garry's Mod's source -> style 0 and the status line; Automatic -> MicOpen at the
--       first held frame; MicOpen failing -> Garry's Mod's level and the status line; feature "faces" 1 -> style 0 and
--       "needs module 0.9.4c"; E-102 and both Super Sonics: no Face* / Viseme* / Mic* call.
--   P8  fast: SAME_PAIR in style 0 and 2, never in style 1; off -> no flag; FACE.SAME_PAIR missing (review R.2) -> no flag
--       and the switch greyed.
--   P9  analysis: MicVisemeOn(true) once when style 2 starts with the microphone, (false) when the style changes or lip
--       sync goes off; one MicVisemeTune per ConVar change with the mapped value; Forget (button, command) -> reset_voice.
--   P10 the microphone test (review R.18): 30 s without the talk key, the classifier on in every style and restored after,
--       the classes counted, stopped at 30 s or when the page closes; lip sync never pauses it; works without a character.
--   P11 log: one numbers-only spurt line per talk spurt with gsa1_lipsync_shapes_log 1, none with 0 (the default, R.10).
--   P12 smooth: F.Smooth called the 0.9.4a way returns exactly the 0.9.4a values (a table kept here).
--   P13 contract (review R.11): build/<target>/faces2_api.txt (written by feat_faces_binding_test V9) against this file's
--       mock: every function with the same arguments and results, every constant with the same value.
--   P14 privacy (the owner's answer PQ7, BINDING): the voice learning is never written (no DATA file, ConVar, cookie or log
--       line holds the learned number) nor sent (no net message), the Lua keeps no copy of it, and a new session starts
--       without it.
-- Round 0.9.4e (sadc docs/research/lipsync2_plan.md 6.3 with its Review R.3 / R.4c / R.5 / R.6 / R.7; the mock is feature
-- "faces" 3 now; device names are invented, never the owner's):
--   P13 the contract is REQUIRED as soon as src/module/bind_faces.cpp declares GSA1_FEATURE(faces, 3: faces2_api.txt must
--       exist, say faces 3 and match this mock in every 0.9.4e function, return, tune and field (a stale 0.9.4c file fails).
--   P14w privacy of the learning AND the vowel warm-up: a warm-up and 20 s of talking with distinctive learned numbers -> no
--       file (but the session log), cookie, sqlite, PData, ConVar, console command, net write or log line holds any of them
--       or a warm-up count; the Lua keeps none; a new session starts unwarmed and tells the module nothing learned.
--   P15 the microphone by name: the combo by name (no loopback, no BASS "Default"), resolved at each open after the numbers
--       shift, the "3- " renumbering matched (review R.6), "Windows default (<name>)", a vanished name -> Windows' default and
--       the note, the one-time move of a saved number (a loopback "Speakers (Y)" -> "Microphone (Y)"; a loopback without
--       one -> Windows' default; a real input -> its name; once), the open line with the name, "unsupported" in words.
--   P16 a stalled stream (MicLevel's blocks frozen 1.5 s while listening): one MicOpen(index, true) and one log line, at
--       most once in 5 s.
--   P17 Sound detection: ("engine", 2) with the saved tunes when the classifier starts, ("engine", 1) on a change; greyed
--       without feature "faces" 3 (and no engine tune then).
--   P18 the vowel warm-up: its MicVisemeWarmup calls at lipsync2_plan.md 4.4's times, listening without the talk key and
--       the analysis on during it and restored after, the results 1-4 (review R.5) as page lines, one log line without
--       numbers, Stop / the page closing -> "cancel", the microphone test and the warm-up exclude each other, greyed with
--       engine 1, "Learn my voice" off or an older module.
--   P19 the numbers line v2 (review R.3): medians over the sound frames (70 % SIL no longer gives 0.01), the closing pause,
--       per raw class the medians of rel_loc / per / nbr / lowr / zcr, "ee near", the tags; MicVisemeFeatures read only with
--       the switch on and used only when its seq is the frame's; never a MicVisemeVoice or warm-up number.
--   lua_host tests/feat_phonemes_test.lua <tests dir> <addon/lua dir>
--
-- API NOTES (094c-gsa1-lipsync; the Lua side of phoneme_plan.md 5.5 as used):
--   ConVars (client, archived; Q menu > Options > G-SA1 > Faces > Lip sync): gsa1_lipsync_style 0..2 default 2 (a saved 0
--   moved to 2 once: cookie gsa1_lipsync_style_094c, one "faces" log line), gsa1_lipsync_fast 1, gsa1_lipsync_shapes_size
--   0.5 (0..1), _big 1, _loud 0.8 (0.5..1), _steady 0 (0 quick / 1 steadier / 2 instant), _gate 6 dB (3..12), _adapt 1,
--   _rise 0.015 s (0.005..0.06), _log 0. Console: gsa1_lipsync_status, gsa1_lipsync_forget_voice.
--   Per frame (GSA1PreTick, style 2 with the microphone): cls, level, f1, f2, conf, seq = gsa1.MicViseme(); the shown class
--   F.HoldClass(st, cls, seq, now, hold) (hold = F.SHAPES_HOLD[steady]); raw = level while the NEWEST class is not SIL, else
--   0 (the classifier's own gate decides speech); s = F.Smooth(L, raw, dt, gain, gate, release, hang, shown ~= SIL, rise);
--   talking starts with a sound (shown ~= SIL); variant = F.Variant(st, s, raw, loud, now, hold); a, b, w =
--   gsa1.VisemeMouth(C.kind, shown, s, size, variant, big); a >= 0: gsa1.FaceMouth(C.id, a, b, w, flags) else
--   gsa1.FaceLevel(C.id, min(w, cap), 0, flags) (flags = gsa1.FACE.SAME_PAIR with "Faster mouth" when the module has it, else
--   0; FaceLevel gets the 4th argument only when it is not 0; cap = VisemeTable(kind).ladder_cap with big off, else 1); the
--   hang's end: ONE gsa1.FaceLevel(id, -1, 0). Styles 0 / 1 as 0.9.4a; style 0 also gets the flag and the cap. Style 2 falls
--   back to style 0 with Garry's Mod's source, a failed microphone or a module without feature "faces" 2 / FACE.MOUTH.
--   0.9.4e (094e-gsa1-lua): ConVars gsa1_lipsync_device_name "" (the microphone by its name; gsa1_lipsync_device is the
--   cache of the number), gsa1_lipsync_hearing 2 (1..2, "Sound detection"). At each open: gsa1.MicDevices() once, the name
--   matched exactly, then normalised (lower case, a "<digits>- " after the "(" taken out), else -1 (Windows' default);
--   loopbacks and BASS's "Default" never offered nor opened; gsa1.MicOpen(index) (a stalled stream: MicOpen(index, true),
--   MicLevel's 4th value = blocks); the cookie gsa1_lipsync_device_094e moves a saved number once. F.SendTunes adds
--   ("engine", hearing) with faces 3. The warm-up: F.WarmStart / F.WarmStop / F.WarmThink / F.WarmSeen / F.WarmLines,
--   gsa1.MicVisemeWarmup("gap" | "ah" | "ee" | "oo" | "oh" | "done" | "cancel") at F.WARM_STEPS' times, the result from
--   gsa1.MicVisemeWarmupState() (phase -1 again, result 1 / 2 / 4); only the result line's text is kept. The numbers line:
--   gsa1.MicVisemeFeatures() of the frame whose MicViseme seq it carries, only with gsa1_lipsync_shapes_log 1.
--   gsa1.MicVisemeOn(true) when style 2 first uses the microphone (then the three saved tunes, each time it is switched on:
--   gate_min_db, adapt, smooth = F.SHAPES_SMOOTH[steady] 3 / 2 / 0), (false) when the style, the source or lip sync
--   changes, or the character leaves; one MicVisemeTune per change of _gate / _adapt / _steady; "reset_voice" from the
--   Forget button / command. The microphone test: F.MicTestStart / Stop / Think / Lines (30 s, listens without the key,
--   the classifier on whatever the style, restored after). gsa1.MicVisemeVoice is read only for the page and the console;
--   nothing of it is logged, saved or sent.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_phonemes_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

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

-- cookies (GMod's cookie library: a key-value store on disk) and the net library's writes, watched (P2, P14)
local jar = {}
cookie = {
    GetNumber = function(k, d) return tonumber(jar[k]) or d end,
    GetString = function(k, d) return jar[k] or d end,
    Set = function(k, v) jar[k] = tostring(v) end,
}
local netWrites = {}
for _, n in ipairs({ "WriteFloat", "WriteUInt", "WriteString", "WriteBool", "WriteVector" }) do
    local f = net[n]
    net[n] = function(...)
        for i = 1, select("#", ...) do netWrites[#netWrites + 1] = tostring((select(i, ...))) end
        return f(...)
    end
end

-- Garry's Mod's cvars.AddChangeCallback replaces a callback of the same identifier (the addon loaded again - P14, P14w -
-- must not run its callbacks twice); lua_mock.lua appends, so this file follows the documented rule
do
    local ids = {}
    cvars.AddChangeCallback = function(name, fn, id)
        M.cvcb[name] = M.cvcb[name] or {}
        local key = id ~= nil and (name .. "|" .. tostring(id)) or nil
        if key and ids[key] then
            M.cvcb[name][ids[key]] = fn
            return
        end
        table.insert(M.cvcb[name], fn)
        if key then ids[key] = #M.cvcb[name] end
    end
end

-- the mock module with the feature "faces" 3 ---------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ features = { faces = 3 } })
local R = { calls = {}, bad = {}, mic = { open = false, listen = false, level = 0, fail = nil, blocks = 0, stall = false },
            vis = { on = false, cls = -1, level = 0, f1 = 0, f2 = 0, conf = 0, seq = 0 },
            -- the learned voice (distinctive numbers the privacy checks look for: never in a file, setting, log or message)
            voice = { g = 6.83, frames = 120, f1 = 611, f2 = 1733, warmed = 0 },
            tune = { engine = 2, adapt = 1 }, devCalls = 0,
            warm = { phase = -1, n = { 0, 0, 0, 0 }, result = 0, next = 1, rate = 1, calls = {} },
            feat = { rl = -4, per = 0.9, nbr = 0.95, eep = 0.1, cat = 1, raw = 2, lowr = 0.5, zcr = 0.1, seqOff = 0,
                     calls = 0 } }
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
-- the declared contract of this mock (P13 checks it against the binding's faces2_api.txt)
local MOCK_API = {
    MicViseme = { args = {}, rets = { "cls", "level", "f1", "f2", "conf", "seq" } },
    MicVisemeOn = { args = { "on" } },
    MicVisemeTune = { args = { "name", "value" } },
    MicVisemeVoice = { args = {}, rets = { "g", "frames", "f1", "f2", "warmed" } },
    -- 0.9.4e (lipsync2_plan.md 5.5)
    MicDevices = { args = {} },
    MicOpen = { args = { "device", "[force]" } },
    MicLevel = { args = {}, rets = { "level", "peak", "state", "blocks" } },
    MicVisemeWarmup = { args = { "step" } },
    MicVisemeWarmupState = { args = {}, rets = { "phase", "n_ah", "n_ee", "n_oo", "n_oh", "result" } },
    MicVisemeFeatures = { args = {}, rets = { "rel_loc", "per", "nbr", "eep", "cat", "raw", "seq", "lowr", "zcr" } },
    VisemeOverride = { args = { "kind", "spec" } },
    VisemeMouth = { args = { "kind", "cls", "s", "size", "variant", "big" }, rets = { "a", "b", "w" } },
    VisemeTable = { args = { "kind" } },
    FaceMouth = { args = { "id", "key_a", "key_b", "weight", "[flags]" } },
    FaceLevel = { args = { "id", "level", "style", "[flags]" } },
}
local MOCK_CONST = { ["FACE.SAME_PAIR"] = SAME_PAIR, ["FACE.MOUTH"] = 1, ["VISEME.SIL"] = 0, ["VISEME.MBP"] = 1,
                     ["VISEME.AA"] = 2, ["VISEME.EH"] = 3, ["VISEME.EE"] = 4, ["VISEME.OH"] = 5, ["VISEME.OO"] = 6,
                     ["VISEME.SS"] = 7, ["VISEME.FV"] = 8, ["VISEME.COUNT"] = 9, ["FEATURES.faces"] = 3 }

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
    return 0, false, -1, -1, 0, -1, 0
end
function G.FaceLevel(id, level, style, flags)
    rec("FaceLevel", id, level, style, flags)
    if not (int_in(id, 1, 1e9) and num_in(level, -1, 1) and (style == 0 or style == 1) and (flags == nil or flags == 0 or
            (flags == SAME_PAIR and style == 0 and G.FACE.SAME_PAIR ~= nil))) then
        bad("FaceLevel", string.format("%s, %s, %s, %s", tostring(id), tostring(level), tostring(style), tostring(flags)))
    end
    if not face_id(id) then bad("FaceLevel", "a kind without a face") end
end
function G.FaceMouth(id, a, b, w, flags)
    rec("FaceMouth", id, a, b, w, flags)
    local nk = KEYS[kinds[id] or -1] or 0
    if not (int_in(id, 1, 1e9) and int_in(a, 0, nk - 1) and int_in(b, 0, nk - 1) and num_in(w, 0, 1) and (flags == nil or
            flags == 0 or (flags == SAME_PAIR and G.FACE.SAME_PAIR ~= nil))) then
        bad("FaceMouth", string.format("%s, %s, %s, %s, %s", tostring(id), tostring(a), tostring(b), tostring(w),
            tostring(flags)))
    end
    if not face_id(id) then bad("FaceMouth", "a kind without a face") end
end
-- fixed numbers (not phoneme_plan.md 4.3's table: the module's own test checks that one)
local FAKE = { [2] = { 4, 16, 0.3 }, [3] = { 0, 4, 1 }, [4] = { 0, 4, 1 }, [5] = { 6, 16, 0.4 }, [6] = { 0, 6, 1 },
               [7] = { 0, 4, 0.5 } }
local FV_LEVEL = { [0] = 0.25, [2] = 1 / 6, [3] = 1 / 6, [5] = 0.125, [7] = 0.125 }
local LADDER_CAP = { [0] = 0.5, [2] = 2 / 3, [3] = 2 / 3, [5] = 1, [7] = 1 }
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
    if FV_LEVEL[kind] == nil or cls <= 1 then
        a, b, w = 0, 0, 0
    elseif cls == 8 then
        a, b, w = -1, -1, math.min(s, FV_LEVEL[kind])
    else
        local e = FAKE[cls]
        a, b, w = e[1], e[2], math.min(e[3] * (0.5 + 0.5 * s) + (variant == 2 and 0.1 or 0), 1)
        if kind == 7 then a, b = 0, 4 end
    end
    c.ret = { a, b, w }
    return a, b, w
end
function G.VisemeTable(kind)
    rec("VisemeTable", kind)
    if FV_LEVEL[kind] == nil then return nil end
    local t = { floor = (kind == 0 or kind == 3) and 0.8 or 0, ladder_cap = LADDER_CAP[kind], fv_level = FV_LEVEL[kind],
                table_version = 2, custom_spec = "", mouth_at = { forward = 4, up = 30 } }
    for c = 0, 8 do
        if c <= 1 then
            t[c] = { a = 0, b = 0, w = 0, how = "closed", expression = false }
        elseif c == 8 then
            t[c] = { a = -1, b = -1, w = FV_LEVEL[kind], how = "ladder", expression = false }
        else
            local e = FAKE[c]
            t[c] = { a = kind == 7 and 0 or e[1], b = kind == 7 and 4 or e[2], w = e[3], how = e[1] == 0 and "scales" or
                     "fixed", expression = c == 2 }
        end
        t[c].custom = false
    end
    return t
end
function G.VisemeOverride(kind, spec)
    rec("VisemeOverride", kind, spec)
    if FV_LEVEL[kind] == nil then return nil, "this character has no face in the game", "unsupported" end
    return true
end
-- invented device names (review R.7): BASS's "Default", Windows' default input, other inputs, then the loopbacks
local DEVS_A = {
    { index = 0, name = "Default", default = true, enabled = true, loopback = false },
    { index = 1, name = "Microphone (Test USB Mic)", default = true, enabled = true, loopback = false },
    { index = 2, name = "Line In (Test Card)", default = false, enabled = true, loopback = false },
    { index = 3, name = "Stereo Mix (Test Card)", default = false, enabled = true, loopback = false },
    { index = 4, name = "Speakers (Test Card)", default = false, enabled = true, loopback = true },
    { index = 5, name = "Speakers (Test Headphones)", default = false, enabled = true, loopback = true },
}
R.devs = DEVS_A
function G.MicDevices()
    R.devCalls = R.devCalls + 1
    local out = {}
    for i, d in ipairs(R.devs) do
        out[i] = { index = d.index, name = d.name, default = d.default, enabled = d.enabled, loopback = d.loopback }
    end
    return out
end
local function dev_of(i)
    for _, d in ipairs(R.devs) do
        if d.index == i then return d end
    end
end
function G.MicOpen(dev, force)
    rec("MicOpen", dev, force)
    if not int_in(dev, -1, 63) or not (force == nil or type(force) == "boolean") then
        bad("MicOpen", tostring(dev) .. " " .. tostring(force))
    end
    local d = dev_of(dev)
    if (d and d.loopback) or R.mic.unsupported == dev then
        return nil, "that device records what your PC plays (a speaker output), not a microphone", "unsupported"
    end
    if dev >= 0 and not d then return nil, "no microphone " .. tostring(dev), "error" end
    if R.mic.fail then return nil, R.mic.fail, "error" end
    R.mic.open, R.mic.dev, R.mic.blocks = true, dev, 0
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
    if not R.mic.stall then R.mic.blocks = R.mic.blocks + 1 end
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
    if type(on) ~= "boolean" then bad("MicVisemeOn", on) end
    R.vis.on = on == true
    return true
end
local TUNES = { gate_min_db = { 3, 12 }, adapt = { 0, 1 }, smooth = { 0, 3 }, engine = { 1, 2 } }
function G.MicVisemeTune(name, value)
    rec("MicVisemeTune", name, value)
    if name == "reset_voice" then
        R.voice.frames, R.voice.warmed = 0, 0
        R.warm.phase, R.warm.result = -1, 0
        return true
    end
    local r = TUNES[name]
    if not r or not num_in(value, r[1], r[2]) or (name == "engine" and G.FEATURES.faces < 3) then
        bad("MicVisemeTune", tostring(name) .. " " .. tostring(value))
        return nil, "MicVisemeTune(name, value)", "bad_argument"
    end
    if name == "engine" or name == "adapt" then R.tune[name] = value end
    return true
end
function G.MicVisemeVoice()
    rec("MicVisemeVoice")
    return R.voice.g, R.voice.frames, R.voice.f1, R.voice.f2, R.voice.warmed
end
-- 0.9.4e: the per-frame features (atomic 2) of the newest frame; seqOff makes their seq another frame's
function G.MicVisemeFeatures()
    R.feat.calls = R.feat.calls + 1
    local f = R.feat
    return f.rl, f.per, f.nbr, f.eep, f.cat, f.raw, (R.vis.seq + f.seqOff) % 65536, f.lowr, f.zcr
end
-- 0.9.4e: the vowel warm-up (as the module: a step applies at once here; "done" gives R.warm.next)
local WARM_PHASE = { ah = 0, ee = 1, oo = 2, oh = 3, gap = 4 }
function G.MicVisemeWarmup(step)
    rec("MicVisemeWarmup", step)
    R.warm.calls[#R.warm.calls + 1] = { step = step, t = M.T }
    local W = R.warm
    if WARM_PHASE[step] == nil and step ~= "done" and step ~= "cancel" then
        return nil, "MicVisemeWarmup: no step " .. tostring(step), "bad_argument"
    end
    if step ~= "cancel" then
        if R.tune.engine ~= 2 then return nil, "needs 'Sound detection' 0.9.4e", "unsupported" end
        if R.tune.adapt ~= 1 then return nil, "needs 'Learn my voice'", "unsupported" end
        if not R.mic.open then return nil, "the microphone is not open", "unsupported" end
    end
    if step == "ah" then W.n = { 0, 0, 0, 0 } end
    if step == "done" then
        W.phase, W.result = -1, W.next
        if W.next == 1 then R.voice.warmed = 1 end
    elseif step == "cancel" then
        W.phase, W.result = -1, 3
    else
        W.phase = WARM_PHASE[step]
    end
    return true
end
function G.MicVisemeWarmupState()
    local W = R.warm
    return W.phase, W.n[1], W.n[2], W.n[3], W.n[4], W.result
end

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
            if string.sub(nm, 1, #p) == p then n = n + 1 break end
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
M.player.IsTyping = function() return M.typing == true end
M.player.IsSpeaking = function() return M.speaking == true end
M.player.VoiceVolume = function() return M.volume or 0 end
vgui.CursorVisible = function() return false end
surface.DrawRect = function() end

-- the page's controls: stand-ins that record their calls (as feat_faces_test.lua)
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
            if k == "SetEnabled" then t.enabled = a[1] return end
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

-- 0. loading, with a saved 0.9.4a style 0 and no cookie (P2) --------------------------------------------------------------------
M.cv("gsa1_lipsync_style", "0")
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local F = GSA1 and GSA1.Faces
check(ok_load and #ferr == 0 and F ~= nil and F.LipSyncFrame ~= nil and F.HoldClass ~= nil and F.Variant ~= nil and
    F.SpurtLine ~= nil and F.MigrateStyle ~= nil, "the autorun loads feat/sh_faces.lua and cl_faces.lua with style 2 (%s)",
    ok_load and table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_load or ferr[1]))
if not (ok_load and F) then return done() end
local L = F.lip
local function log_text()
    GSA1.LogFlush()
    return M.files["gsa1/log.txt"] or ""
end
local function count_in(text, plain)
    local n, i = 0, 1
    while true do
        local a, b = string.find(text, plain, i, true)
        if not a then return n end
        n, i = n + 1, b + 1
    end
end

-- P2. the one-time move -----------------------------------------------------------------------------------------------------------
local moved = count_in(log_text(), "the mouth moved once")
check(M.convars.gsa1_lipsync_style.v == "2" and jar[F.STYLE_COOKIE] == "1" and moved == 1, "P2 a saved style 0 without "
    .. "the cookie became 2 at the load (style %s, cookie %s, %d log line)", M.convars.gsa1_lipsync_style.v,
    tostring(jar[F.STYLE_COOKIE]), moved)
local again = F.MigrateStyle()
RunConsoleCommand("gsa1_lipsync_style", "0")
local again0 = F.MigrateStyle()
local stays0 = M.convars.gsa1_lipsync_style.v == "0"
jar = {}
RunConsoleCommand("gsa1_lipsync_style", "1")
local m1 = F.MigrateStyle()
check(again == false and again0 == false and stays0 and m1 == false and M.convars.gsa1_lipsync_style.v == "1" and
    jar[F.STYLE_COOKIE] == "1" and count_in(log_text(), "the mouth moved once") == 1, "P2 a second load changes nothing (a "
    .. "0 chosen later stays 0); a saved 1 stays 1 (the cookie set); still one log line")
RunConsoleCommand("gsa1_lipsync_style", "2")

-- every "faces" log line from here on (GSA1.Log is looked up at each call)
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

GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }

-- P1. the settings and the page ----------------------------------------------------------------------------------------------------
local WANT = {
    gsa1_lipsync_style = { "2", 0, 2 }, gsa1_lipsync_fast = { "1", 0, 1 }, gsa1_lipsync_shapes_size = { "0.5", 0, 1 },
    gsa1_lipsync_shapes_big = { "1", 0, 1 }, gsa1_lipsync_shapes_loud = { "0.8", 0.5, 1 },
    gsa1_lipsync_shapes_steady = { "0", 0, 2 }, gsa1_lipsync_shapes_gate = { "6", 3, 12 },
    gsa1_lipsync_shapes_adapt = { "1", 0, 1 }, gsa1_lipsync_shapes_rise = { "0.015", 0.005, 0.06 },
    gsa1_lipsync_shapes_log = { "0", 0, 1 },
    -- 0.9.4e (lipsync2_plan.md 7.1): the microphone by name, "Sound detection"
    gsa1_lipsync_device_name = { "", nil, nil }, gsa1_lipsync_hearing = { "2", 1, 2 },
}
local wrong = {}
for name, w in pairs(WANT) do
    local c, d = M.convars[name], GSA1.CONVARS[name]
    if not (c and c.client and c.save and d and d.default == w[1] and c.lo == w[2] and c.hi == w[3]) then
        wrong[#wrong + 1] = name
    end
end
table.sort(wrong)
check(#wrong == 0, "P1 the ConVars of phoneme_plan.md 7.1 with their defaults and ranges (style 2, fast 1, size 0.5, big "
    .. "1, loud 0.8, steady 0, gate 6, adapt 1, rise 0.015, log 0)%s", #wrong > 0 and (": wrong " ..
    table.concat(wrong, " ")) or "")

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
local function page_role(role)
    for _, P in ipairs(made) do
        if rawget(P, "gsa1Role") == role then return P end
    end
end
local function page_texts()
    local t = {}
    for _, P in ipairs(made) do
        if P.text then t[#t + 1] = tostring(P.text) end
    end
    return table.concat(t, "\n")
end
local function page_control(cvname)
    for _, P in ipairs(made) do
        if P.convar == cvname or rawget(P, "gsa1ConVar") == cvname then return P end
    end
end
local function page_has_call(name, arg2)
    for _, P in ipairs(made) do
        for _, c in ipairs(P.calls) do
            if c[1] == name and c[3] == arg2 then return true end
        end
    end
    return false
end
check(entry ~= nil, "P1 the page Options -> G-SA1 -> Faces")
if not entry then return done() end
local pok = build_page()
local missing = {}
for name in pairs(WANT) do
    if not page_control(name) then missing[#missing + 1] = name end
end
table.sort(missing)
local mouth = page_role("mouth")
local mch = mouth and mouth.choices or {}
check(pok and #missing == 0, "P1 every new ConVar has its control on the Faces page%s", #missing > 0 and (": missing " ..
    table.concat(missing, " ")) or "")
check(mouth ~= nil and #mch == 3 and mch[1][2] == "0" and mch[2][2] == "1" and mch[3][2] == "2" and
    mch[3][1] == "Mouth shapes from your voice" and rawget(mouth, "gsa1ConVar") == "gsa1_lipsync_style",
    "P1 the \"Mouth\" combo has three choices (%s / %s / %s)", tostring(mch[1] and mch[1][1]),
    tostring(mch[2] and mch[2][1]), tostring(mch[3] and mch[3][1]))
check(page_has_call("Button", "gsa1_lipsync_forget_voice") and page_role("soundnow") and page_role("soundwords") and
    page_role("mictest") and page_role("character") and page_role("shapesstatus") and
    string.find(page_texts(), "Mouth shapes: G-SA1 hears which kind of sound you make", 1, true) ~= nil,
    "P1 the page has the Forget button, the \"Sound now\" line with the nine words, the \"This character\" line, the "
    .. "microphone test and the status line")
local fastCb = page_control("gsa1_lipsync_fast")
check(fastCb and fastCb.enabled ~= false, "P8 with FACE.SAME_PAIR the \"Faster mouth\" switch is usable")

-- P12. F.Smooth the 0.9.4a way --------------------------------------------------------------------------------------------------
-- the 0.9.4a values (sh_faces.lua of 0.9.4b's release, its F.Smooth run over the script below, printed with %.17g)
local SMOOTH_094A = {
    0.31542246865429979, 0.60722129963041738, 0.51330663144259425, 0.70370815176946167, 0.83000153854111236,
    0.73541256546605815, 0.84819205435200928, 0.91289967188934307, 0.85156268243921196, 0.91483358128440928,
    0.8143568241978576, 0.85839072682849316, 0.91875119510970638, 0.84629498069293452, 0.94940138545323527,
    0.97096887181921887, 0.84505821715881813, 0.64010213096311575, 0.55709671163584273, 0.4848550428171482,
    0.36726078726140782, 0.3196361439826399, 0.27818723937813317, 0.21071713299395528, 0.18339233100136221,
    0.15961088019870695, 0.12089967586326639, 0.1052219772490431, 0.091577288500920687, 0.06936660259259593,
    0.060371469383394806, 0.052542782539262013, 0.039799325522435987, 0.034638337073667959, 0.030146601216964632,
    0.022834999161540262, 0.019873864384673229, 0.017296715571840711, 0.013101658881470133, 0.011402697673978099,
    0.0099240497268660282, 0.0075171216005784558, 0.0065423367960797023, 0.0056939574783577696, 0.0043129742324311349,
    0.003753688116367105, 0.0032669275807412565, 0.0024745837194097668, 0.0021536913971470771, 0.0018744108747517614,
    0.0014198008739125132, 0.0012356878063259163, 0.0010754496512562668, 0.00081461560817330087, 0.00070898010584302868,
    0.00061704291623916206, 0.0004673884917755355, 0.00040677976096222484, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1,
}
do
    local st, worst, n = { s = 0, quiet = 1e9 }, 0, 0
    for i = 1, 72 do
        local raw = ((i * 37) % 100) / 100
        if i > 16 then raw = 0 end
        local dt = (i % 3 == 0) and (1 / 30) or (1 / 60)
        local v = F.Smooth(st, raw, dt, 2, 0.05, 0.12, 0.6, i % 5 == 0 and i <= 16)
        if v == SMOOTH_094A[i] then n = n + 1 else worst = math.max(worst, math.abs(v - SMOOTH_094A[i])) end
    end
    local st2, st3 = { s = 0, quiet = 1e9 }, { s = 0, quiet = 1e9 }
    local same = true
    for i = 1, 40 do
        local a = F.Smooth(st2, 0.5, 1 / 60, 2, 0.05, 0.12, 0.6, false)
        local b = F.Smooth(st3, 0.5, 1 / 60, 2, 0.05, 0.12, 0.6, false, nil)
        same = same and a == b
    end
    local st4 = { s = 0, quiet = 1e9 }
    local fast1 = F.Smooth(st4, 0.5, 1 / 60, 2, 0.05, 0.12, 0.6, false, 0.015)
    check(n == 72 and same and math.abs(fast1 - (1 - math.exp(-(1 / 60) / 0.015))) < 1e-12, "P12 F.Smooth called the "
        .. "0.9.4a way returns exactly the 0.9.4a values (%d of 72 bit-equal, worst %.3g); rise nil = F.RISE; rise 0.015 "
        .. "rises in 15 ms (%.4f)", n, worst, fast1)
end

-- P4 / P6 pure. F.HoldClass and F.Variant ------------------------------------------------------------------------------------------
do
    local Q, S2 = F.SHAPES_HOLD[0], F.SHAPES_HOLD[1]
    local ok = Q == 1 / 30 and S2 == 2 / 30 and F.SHAPES_HOLD[2] == 0 and F.SHAPES_SMOOTH[0] == 3 and
        F.SHAPES_SMOOTH[1] == 2 and F.SHAPES_SMOOTH[2] == 0
    local st = {}
    local r = {}
    r[1] = F.HoldClass(st, 2, 1, 0, Q)              -- after silence for ever: at once
    r[2] = F.HoldClass(st, 3, 2, 1 / 60, Q)         -- inside the hold: waits
    r[3] = F.HoldClass(st, 3, 3, 2 / 60, Q)         -- the hold's end, still the newest: shown
    r[4] = F.HoldClass(st, 4, 4, 3 / 60, Q)         -- a blip inside the next hold ...
    r[5] = F.HoldClass(st, 3, 5, 4 / 60, Q)         -- ... gone: never shown
    r[6] = F.HoldClass(st, 3, 6, 5 / 60, Q)
    local quickOk = r[1] == 2 and r[2] == 2 and r[3] == 3 and r[4] == 3 and r[5] == 3 and r[6] == 3
    st = {}
    local s1 = F.HoldClass(st, 2, 1, 0, S2)
    local s2 = F.HoldClass(st, 3, 2, 1 / 60, S2)
    local s3 = F.HoldClass(st, 3, 3, 3 / 60, S2)
    local s4 = F.HoldClass(st, 3, 4, 4 / 60, S2)
    local steadyOk = s1 == 2 and s2 == 2 and s3 == 2 and s4 == 3
    st = {}
    local i1, i2, i3 = F.HoldClass(st, 2, 1, 0, 0), F.HoldClass(st, 3, 2, 0.001, 0), F.HoldClass(st, 2, 3, 0.002, 0)
    local instantOk = i1 == 2 and i2 == 3 and i3 == 2
    local mbpOk = true
    for _, h in ipairs({ Q, S2, 0 }) do
        st = {}
        F.HoldClass(st, 2, 1, 0, h)
        mbpOk = mbpOk and F.HoldClass(st, 1, 2, 0.001, h) == 1
    end
    st = {}
    F.HoldClass(st, 2, 1, 0, Q)
    local sil1 = F.HoldClass(st, 0, 2, 1 / 60, Q)
    local sil2 = F.HoldClass(st, 0, 3, 2 / 60, Q)
    st = {}
    F.HoldClass(st, 2, 1, 0, Q)
    local neg1 = F.HoldClass(st, -1, 1, 1 / 60, Q)
    local neg2 = F.HoldClass(st, -1, 1, 2 / 60, Q)
    st = {}
    F.HoldClass(st, 5, 7, 0, Q)
    local fr1 = F.HoldClass(st, 5, 7, 0.05, Q)
    local fr2 = F.HoldClass(st, 5, 7, 0.1, Q)
    local fresh = F.HoldClass(st, 5, 8, 0.15, Q)
    check(ok and quickOk and steadyOk and instantOk and mbpOk and sil1 == 2 and sil2 == 0 and neg1 == 2 and neg2 == 0 and
        fr1 == 5 and fr2 == 0 and st.stale == false and fresh == 5, "P4 F.HoldClass's one rule (review R.5): quick: a "
        .. "new class at the hold's end only if still the newest, a blip inside the hold never; steadier 2/30 s; instant "
        .. "every change; MBP at once in every mode; SIL held like a vowel; cls -1 and a seq frozen for 0.1 s count as SIL")
    -- F.Variant
    st = { shown = 2, at = -1 }
    local v1 = F.Variant(st, 0.3, 0.3, 0.8, 0, Q)          -- quiet
    local v2 = F.Variant(st, 0.53, 0.3, 0.8, 1, Q)         -- 0.5 < s <= 0.55: still quiet (hysteresis)
    local v3 = F.Variant(st, 0.6, 0.3, 0.8, 2, Q)          -- normal
    local v4 = F.Variant(st, 1, 0.82, 0.8, 3, Q)           -- loud
    local alt = true
    for i = 1, 40 do
        alt = alt and F.Variant(st, 1, (i % 2 == 0) and 0.82 or 0.78, 0.8, 3 + i, Q) == 2
    end
    local v5 = F.Variant(st, 1, 0.73, 0.8, 50, Q)          -- under 0.8 - 0.06: normal again
    st = { shown = 2, at = 10, v = 0, vc = 0 }
    local w1 = F.Variant(st, 1, 0.9, 0.8, 10 + 1 / 60, Q)  -- loud, but the shape was set 1/60 s ago: waits
    local w2 = F.Variant(st, 1, 0.9, 0.8, 10 + 2 / 60, Q)  -- the hold's end
    st = { shown = 3, at = 20, v = 0, vc = 0 }
    local j1 = F.Variant(st, 1, 0.9, 0.8, 20, Q)           -- the class changed in this frame: joins it
    check(v1 == 1 and v2 == 1 and v3 == 0 and v4 == 2 and alt and v5 == 0 and w1 == 0 and w2 == 2 and j1 == 2,
        "P6 F.Variant: quiet under 0.5 until above 0.55, loud from gsa1_lipsync_shapes_loud until 0.06 under it (0.78 / "
        .. "0.82 alternating stays loud), a change waits for the hold, joins a class change of the same frame (review R.6)")
end

-- talking through the frames -----------------------------------------------------------------------------------------------------
local function vis(cls, level, f1, f2)
    R.vis.cls, R.vis.level, R.vis.f1, R.vis.f2, R.vis.conf = cls, level or 0, f1 or 0, f2 or 0, 0.8
    R.vis.seq = (R.vis.seq + 1) % 65536
end
local F1 = { [2] = 712, [3] = 530, [4] = 290, [5] = 570, [6] = 330 }
local F2 = { [2] = 1240, [3] = 1840, [4] = 2290, [5] = 840, [6] = 870 }
local LEVEL = { [0] = 0, 0.3, 0.7, 0.7, 0.7, 0.7, 0.7, 0.5, 0.2 }
local function frame(cls, level)
    vis(cls, level or LEVEL[cls], F1[cls] or 0, F2[cls] or 0)
    M.frame(1 / 60)
    local W = R.warm
    if W.phase >= 0 and W.phase <= 3 and R.mic.listen and R.vis.on then
        W.n[W.phase + 1] = math.min(W.n[W.phase + 1] + W.rate, 255)
    end
end
-- frames of silence until talking ended (at most n), the number of frames run
local function quiet(n)
    for i = 1, n or 200 do
        frame(0)
        if not L.talking then return i end
    end
    return n or 200
end
local function expand(spec)
    local out = {}
    for _, s in ipairs(spec) do
        for _ = 1, s[2] do out[#out + 1] = s[1] end
    end
    return out
end
-- the independent model of the hold rule (phoneme_plan.md 4.4): frame k at time k/60, silence before
local function model_hold(seq, hold)
    local shown, at, out = 0, -1e9, {}
    for k, c in ipairs(seq) do
        local t = k / 60
        if c ~= shown and (c == 1 or t - at >= hold - 1e-4) then shown, at = c, t end
        out[k] = shown
    end
    return out
end
-- the mouth calls of a stretch: { {vm = VisemeMouth call, face = FaceMouth / FaceLevel call}, ... }, the -1 calls, others
local function mouth_events(m, id)
    local ev, minus, stray = {}, {}, 0
    for i = m + 1, #R.calls do
        local c = R.calls[i]
        if c[1] == "VisemeMouth" then
            ev[#ev + 1] = { vm = c }
        elseif (c[1] == "FaceMouth" or c[1] == "FaceLevel") and c[2] == id then
            if c[1] == "FaceLevel" and c[3] == -1 then
                minus[#minus + 1] = c
            elseif ev[#ev] and ev[#ev].face == nil then
                ev[#ev].face = c
            else
                stray = stray + 1
            end
        end
    end
    return ev, minus, stray
end

GSA1.Spawn("sonic")
local C = GSA1.Char
check(C ~= nil and C.kind == 0, "Sonic spawned")
if not C then return done() end
for _ = 1, 10 do frame(0) end
check(count_prefixes(0, { "Mic", "Face", "Viseme" }) == count_prefixes(0, { "MicViseme" }) and
    #calls_since(0, "MicViseme") == 0, "nothing pressed: no Face* / Mic* / Viseme* call (the module untouched)")

-- P7 (b) + P9: style 2 + Automatic: the microphone at the first held frame; the classifier on once with the saved tunes
local m0 = mark()
keys[KEY_X] = true
frame(0)
local opens, on1 = calls_since(m0, "MicOpen"), calls_since(m0, "MicVisemeOn")
local tunes = calls_since(m0, "MicVisemeTune")
local tunesOk = #tunes == 4 and tunes[1][2] == "gate_min_db" and tunes[1][3] == 6 and tunes[2][2] == "adapt" and
    tunes[2][3] == 1 and tunes[3][2] == "smooth" and tunes[3][3] == 3 and tunes[4][2] == "engine" and tunes[4][3] == 2
check(#opens == 1 and R.mic.listen and #on1 == 1 and on1[1][2] == true and tunesOk, "P7 style 2 + Automatic: MicOpen at "
    .. "the first held frame (no 0.5 s wait), listening; P9 MicVisemeOn(true) once, then the three saved tunes (gate_min_db "
    .. "6, adapt 1, smooth 3) and P17 the engine 2")
check(#logs_with("mouth shapes need the microphone's sound") == 1, "P7 one log line for the source decision")
for _ = 1, 5 do frame(0) end

-- P3. the frame sequence -----------------------------------------------------------------------------------------------------------
do
    local seq = expand({ { 0, 1 }, { 2, 5 }, { 3, 3 }, { 1, 1 }, { 6, 4 }, { 8, 3 }, { 0, 100 } })
    local want = model_hold(seq, 1 / 30)
    local ref = { s = L.s, quiet = L.quiet }
    local m = mark()
    local exp, firstCall, tprev = {}, nil, M.T
    local talking = false
    for k, c in ipairs(seq) do
        local before = mark()
        frame(c)
        local dt = M.T - tprev
        tprev = M.T
        local raw = c ~= 0 and LEVEL[c] or 0
        local s = F.Smooth(ref, raw, dt, 2, 0.05, 0.12, 0.6, want[k] ~= 0, 0.015)
        if s >= 0 and (talking or want[k] ~= 0) then
            talking = true
            exp[#exp + 1] = { cls = want[k], s = s }
        elseif s < 0 then
            talking = false
        end
        if firstCall == nil and count_prefixes(before, { "Face" }) > 0 then firstCall = k end
    end
    local ev, minus, stray = mouth_events(m, C.id)
    local okEv, why = #ev == #exp and #ev > 20, string.format("%d calls, %d expected", #ev, #exp)
    local fvLevel, mouths = 0, 0
    for i = 1, math.min(#ev, #exp) do
        local vm, face, e = ev[i].vm, ev[i].face, exp[i]
        local r = vm.ret
        local okv = vm[2] == 0 and vm[3] == e.cls and math.abs(vm[4] - e.s) < 1e-12 and vm[5] == 0.5 and
            int_in(vm[6], 0, 2) and vm[7] == true and face ~= nil
        if okv and r[1] >= 0 then
            okv = face[1] == "FaceMouth" and face[3] == r[1] and face[4] == r[2] and face[5] == r[3] and face[6] == SAME_PAIR
            mouths = mouths + 1
        elseif okv then
            okv = face[1] == "FaceLevel" and face[3] == r[3] and face[4] == 0 and face[5] == SAME_PAIR and r[3] <= 0.25
            fvLevel = fvLevel + 1
        end
        if not okv and okEv then
            okEv, why = false, string.format("call %d: VisemeMouth(%s, %s, %s, %s, %s, %s) -> %s %s %s, then %s %s %s %s %s "
                .. "(expected class %d, s %.6f)", i, tostring(vm[2]), tostring(vm[3]), tostring(vm[4]), tostring(vm[5]),
                tostring(vm[6]), tostring(vm[7]), tostring(r[1]), tostring(r[2]), tostring(r[3]),
                tostring(face and face[1]), tostring(face and face[3]), tostring(face and face[4]),
                tostring(face and face[5]), tostring(face and face[6]), e.cls, e.s)
        end
    end
    check(okEv and fvLevel == 3 and mouths > 15 and stray == 0, "P3 each talking frame one VisemeMouth(kind, the held "
        .. "class, s, 0.5, variant, true), then FaceMouth(id, a, b, w, SAME_PAIR) with exactly its numbers; f / v -> "
        .. "FaceLevel(id, w, 0, SAME_PAIR) with VisemeMouth's w (review R.1: %d frames) (%s)", fvLevel, why)
    check(firstCall == 2 and #minus == 1 and minus[1][4] == 0 and minus[1][5] == nil and not L.talking and
        count_prefixes(m, { "Face" }) == #ev * 1 + 1, "P3 nothing before the first sound (first call at frame %s), exactly "
        .. "one FaceLevel(id, -1, 0) after the hang (%d)", tostring(firstCall), #minus)
    local held = {}
    for i, e in ipairs(ev) do if i <= 18 then held[#held + 1] = tostring(e.vm[3]) end end
    info("held classes of the first 18 talking frames: %s", table.concat(held, " "))
    local sn = F.SoundNowLines()[1]
    check(sn == "Sound now: silence - level 0.00 - F1 0 F2 0 - voice 6.83 (learned)" or
        string.find(sn, "Sound now: ", 1, true) == 1, "the Sound now line: %s", sn)
end

-- the Sound now line while an "ah" is heard
frame(2)
local soundNow = F.SoundNowLines()[1]
check(soundNow == "Sound now: AH (open) - level 0.70 - F1 712 F2 1240 - voice 6.83 (learned)" and F.soundCls == 2,
    "the page's live line: \"%s\" (the word \"ah\" lit)", soundNow)
quiet()

-- P4 through the frames: a one-frame blip inside the hold is never sent; steadier; instant
do
    local m = mark()
    for _, c in ipairs(expand({ { 2, 1 }, { 4, 1 }, { 2, 6 } })) do frame(c) end
    quiet()
    local ev = mouth_events(m, C.id)
    local blip = 0
    for _, e in ipairs(ev) do if e.vm[3] == 4 then blip = blip + 1 end end
    RunConsoleCommand("gsa1_lipsync_shapes_steady", "1")
    m = mark()
    local at = {}
    for k, c in ipairs(expand({ { 2, 1 }, { 3, 6 } })) do
        local b = mark()
        frame(c)
        for _, x in ipairs(calls_since(b, "VisemeMouth")) do if x[3] == 3 and not at.eh then at.eh = k end end
    end
    quiet()
    RunConsoleCommand("gsa1_lipsync_shapes_steady", "2")
    m = mark()
    local inst = {}
    for _, c in ipairs({ 2, 3, 2, 3, 6 }) do
        local b = mark()
        frame(c)
        local x = calls_since(b, "VisemeMouth")
        inst[#inst + 1] = x[1] and tostring(x[1][3]) or "-"
    end
    quiet()
    RunConsoleCommand("gsa1_lipsync_shapes_steady", "0")
    check(blip == 0 and at.eh == 5 and table.concat(inst, " ") == "2 3 2 3 6", "P4 through the frames: a one-frame \"ee\" "
        .. "inside the hold never sent (%d); steadier: \"eh\" after \"ah\" shown 4 frames (2/30 s) later (frame %s); "
        .. "instant: every change (%s)", blip, tostring(at.eh), table.concat(inst, " "))
end

-- P5. the hang -------------------------------------------------------------------------------------------------------------------
do
    local m = mark()
    for _, c in ipairs(expand({ { 2, 10 }, { 1, 60 }, { 6, 10 } })) do frame(c) end
    local _, minus1 = mouth_events(m, C.id)
    local alive = L.talking
    local n = quiet(300)
    local _, minus2 = mouth_events(m, C.id)
    check(#minus1 == 0 and alive and #minus2 == 1 and n > 36, "P5 a second of m / b / p between vowels keeps talking "
        .. "alive (no -1); silence longer than the hang: one -1 (%d frames of silence)", n)
end

-- P6 through the frames ------------------------------------------------------------------------------------------------------
do
    local function variants_of(m)
        local v = {}
        for _, x in ipairs(calls_since(m, "VisemeMouth")) do if x[3] ~= 0 then v[#v + 1] = x[6] end end
        return v
    end
    local m = mark()
    for _ = 1, 20 do frame(2, 0.1) end
    local q = variants_of(m)
    quiet()
    m = mark()
    for i = 1, 40 do frame(2, (i % 2 == 1) and 0.82 or 0.78) end
    local alt = variants_of(m)
    quiet()
    m = mark()
    frame(2, 0.7)
    frame(2, 0.9)
    frame(2, 0.9)
    local w = variants_of(m)
    quiet()
    local allQuiet, allLoud = #q > 15, #alt == 40
    for i = 2, #q do allQuiet = allQuiet and q[i] == 1 end
    for _, v in ipairs(alt) do allLoud = allLoud and v == 2 end
    check(allQuiet and allLoud and w[1] == 0 and w[2] == 0 and w[3] == 2, "P6 through the frames: quiet talking -> "
        .. "variant 1; a level alternating 0.82 / 0.78 frame by frame stays loud (2) all 40 frames; a loud level one frame "
        .. "after the shape changed waits for the hold (%s %s %s)", tostring(w[1]), tostring(w[2]), tostring(w[3]))
    -- bigger mouths off: VisemeMouth's big false; style 0's level capped at VisemeTable(kind).ladder_cap
    RunConsoleCommand("gsa1_lipsync_shapes_big", "0")
    m = mark()
    for _ = 1, 10 do frame(2) end
    quiet()
    local bigs = calls_since(m, "VisemeMouth")
    local bigOff = #bigs > 5
    for _, x in ipairs(bigs) do bigOff = bigOff and x[7] == false end
    RunConsoleCommand("gsa1_lipsync_style", "0")
    R.mic.level = 0.9
    m = mark()
    for _ = 1, 30 do frame(0) end
    R.mic.level = 0
    quiet()
    local lv = calls_since(m, "FaceLevel", C.id)
    local top = 0
    for _, x in ipairs(lv) do if x[3] > top then top = x[3] end end
    RunConsoleCommand("gsa1_lipsync_shapes_big", "1")
    RunConsoleCommand("gsa1_lipsync_style", "2")
    for _ = 1, 3 do frame(0) end
    check(bigOff and #lv > 10 and math.abs(top - 0.5) < 1e-12, "P6 bigger mouths off: VisemeMouth's big is false; style "
        .. "0's level is capped at Sonic's ladder_cap 0.5 (the highest sent %.3f)", top)
end

-- P8. "Faster mouth" -------------------------------------------------------------------------------------------------------------------
do
    local function flags_of(m, name)
        local out = {}
        for _, x in ipairs(calls_since(m, name, C.id)) do
            if not (name == "FaceLevel" and x[3] == -1) then
                local f
                if name == "FaceMouth" then f = x[6] else f = x[5] end
                out[#out + 1] = f == nil and "none" or f
            end
        end
        return out
    end
    local function all(list, v)
        if #list == 0 then return false end
        for _, x in ipairs(list) do if x ~= v then return false end end
        return true
    end
    local m = mark()
    for _ = 1, 10 do frame(2) end
    quiet()
    local f2on = flags_of(m, "FaceMouth")
    RunConsoleCommand("gsa1_lipsync_style", "0")
    R.mic.level = 0.6
    m = mark()
    for _ = 1, 20 do frame(0) end
    R.mic.level = 0
    quiet()
    local f0on = flags_of(m, "FaceLevel")
    RunConsoleCommand("gsa1_lipsync_style", "1")
    R.mic.level = 0.6
    m = mark()
    for _ = 1, 20 do frame(0) end
    R.mic.level = 0
    quiet()
    local f1on, s1 = flags_of(m, "FaceLevel"), calls_since(m, "FaceLevel", C.id)
    local style1 = #s1 > 0
    for _, x in ipairs(s1) do style1 = style1 and x[4] == 1 end
    RunConsoleCommand("gsa1_lipsync_fast", "0")
    RunConsoleCommand("gsa1_lipsync_style", "2")
    m = mark()
    for _ = 1, 10 do frame(2) end
    quiet()
    local f2off = flags_of(m, "FaceMouth")
    RunConsoleCommand("gsa1_lipsync_style", "0")
    R.mic.level = 0.6
    m = mark()
    for _ = 1, 20 do frame(0) end
    R.mic.level = 0
    quiet()
    local f0off = flags_of(m, "FaceLevel")
    RunConsoleCommand("gsa1_lipsync_fast", "1")
    RunConsoleCommand("gsa1_lipsync_style", "2")
    -- a module whose libsa1 did not build SAME_PAIR (review R.2): no gsa1.FACE.SAME_PAIR
    G.FACE.SAME_PAIR = nil
    m = mark()
    for _ = 1, 10 do frame(2) end
    quiet()
    local fnone = flags_of(m, "FaceMouth")
    build_page()
    local cb = page_control("gsa1_lipsync_fast")
    local greyed = cb ~= nil and cb.enabled == false and string.find(page_texts(), "not available in this module", 1, true)
        ~= nil
    G.FACE.SAME_PAIR = SAME_PAIR
    check(all(f2on, SAME_PAIR) and all(f0on, SAME_PAIR) and all(f1on, "none") and style1 and all(f2off, 0) and
        all(f0off, "none") and greyed and all(fnone, 0), "P8 \"Faster mouth\" on: "
        .. "SAME_PAIR in style 2's FaceMouth and style 0's FaceLevel, never in style 1; off: no flag; a module without "
        .. "FACE.SAME_PAIR: no flag and the switch greyed \"not available in this module\"")
    check(all(f1on, "none") and all(f0off, "none"), "P8 style 1, and style 0 with the switch off: FaceLevel keeps 0.9.4a's "
        .. "three arguments (%d, %d calls)", #f1on, #f0off)
end

-- P9. the classifier on / off, the tunes, Forget ------------------------------------------------------------------------------------
do
    for _ = 1, 3 do frame(0) end
    local m = mark()
    RunConsoleCommand("gsa1_lipsync_style", "0")
    frame(0)
    local off1 = calls_since(m, "MicVisemeOn")
    m = mark()
    RunConsoleCommand("gsa1_lipsync_style", "2")
    frame(0)
    frame(0)
    local on2, tun2 = calls_since(m, "MicVisemeOn"), #calls_since(m, "MicVisemeTune")
    m = mark()
    RunConsoleCommand("gsa1_lipsync", "0")
    frame(0)
    frame(0)
    local off2 = calls_since(m, "MicVisemeOn")
    m = mark()
    RunConsoleCommand("gsa1_lipsync", "1")
    frame(0)
    frame(0)
    local on3, tun3 = calls_since(m, "MicVisemeOn"), #calls_since(m, "MicVisemeTune")
    local seqOk = #off1 == 1 and off1[1][2] == false and #on2 == 1 and on2[1][2] == true and #off2 == 1 and
        off2[1][2] == false and #on3 == 1 and on3[1][2] == true
    check(seqOk and tun2 == 4 and tun3 == 4, "P9 MicVisemeOn(false) once when the style changes to 0, (true) once back in "
        .. "style 2, (false) once when lip sync goes off, (true) once when it is back; the saved tunes after each (true): "
        .. "the three of 0.9.4c and the engine (the module starts from its own values: voice_done.txt)")
    m = mark()
    RunConsoleCommand("gsa1_lipsync_shapes_gate", "9")
    RunConsoleCommand("gsa1_lipsync_shapes_adapt", "0")
    RunConsoleCommand("gsa1_lipsync_shapes_steady", "1")
    RunConsoleCommand("gsa1_lipsync_shapes_steady", "2")
    RunConsoleCommand("gsa1_lipsync_shapes_steady", "0")
    RunConsoleCommand("gsa1_lipsync_shapes_adapt", "1")
    RunConsoleCommand("gsa1_lipsync_shapes_gate", "6")
    local t = calls_since(m, "MicVisemeTune")
    local got = {}
    for _, x in ipairs(t) do got[#got + 1] = tostring(x[2]) .. " " .. tostring(x[3]) end
    local text = table.concat(got, ", ")
    check(text == "gate_min_db 9, adapt 0, smooth 2, smooth 0, smooth 3, adapt 1, gate_min_db 6", "P9 one MicVisemeTune "
        .. "per ConVar change with the mapped value (steady 1 / 2 / 0 -> smooth 2 / 0 / 3): %s", text)
    build_page()
    m = mark()
    M.cmds["gsa1_lipsync_forget_voice"](nil, "gsa1_lipsync_forget_voice", {}, "")
    local fv = calls_since(m, "MicVisemeTune")
    check(page_has_call("Button", "gsa1_lipsync_forget_voice") and #fv == 1 and fv[1][2] == "reset_voice" and
        R.voice.frames == 0, "P9 \"Forget my voice\" (the page's button runs gsa1_lipsync_forget_voice) -> "
        .. "MicVisemeTune(\"reset_voice\")")
    R.voice.frames = 120
end

-- P11. the per-spurt numbers line ---------------------------------------------------------------------------------------------
do
    local n0 = #logs_with("lip sync spurt:")
    for _ = 1, 20 do frame(2) end
    quiet()
    local n1 = #logs_with("lip sync spurt:") - n0
    RunConsoleCommand("gsa1_lipsync_shapes_log", "1")
    for _, c in ipairs(expand({ { 2, 20 }, { 1, 2 }, { 4, 12 }, { 7, 6 } })) do frame(c) end
    quiet()
    for _, c in ipairs(expand({ { 5, 30 }, { 6, 9 } })) do frame(c) end
    quiet()
    local lines = logs_with("lip sync spurt:")
    local mine = {}
    for i = n0 + 1, #lines do mine[#mine + 1] = lines[i] end
    RunConsoleCommand("gsa1_lipsync_shapes_log", "0")
    for _ = 1, 20 do frame(2) end
    quiet()
    local n3 = #logs_with("lip sync spurt:") - n0 - #mine
    local numbersOnly = #mine == 2
    for _, l in ipairs(mine) do
        local rest = l
        -- 0.9.4e: the line v2's words (lipsync2_plan.md 4.9): the tags, the closing pause, the features' names, ee near
        for _, wd in ipairs({ "lip sync spurt", "sound frames", "frames", "F1/F2 Hz", "openness median", "level median",
            "none", "closing pause", "loc/per/nbr/lowr/zcr", "ee near", "hearing", "mouths G-SA1's v", "of", "SIL",
            "MBP", "AA", "EH", "EE", "OH", "OO", "SS", "FV" }) do
            rest = string.gsub(rest, (string.gsub(wd, "%p", "%%%0")), "")
        end
        rest = string.gsub(rest, "n(%d)", "%1")
        rest = string.gsub(rest, "(%d) s,", "%1,")
        numbersOnly = numbersOnly and string.find(rest, "[%a]") == nil
    end
    info("spurt lines: %s", table.concat(mine, " | "))
    check(n1 == 0 and #mine == 2 and numbersOnly and n3 == 0 and string.find(mine[1] or "", "AA 712/1240", 1, true) ~= nil,
        "P11 gsa1_lipsync_shapes_log 1: one line per talk spurt (2), numbers and class names only; 0 (the default, "
        .. "review R.10): none")
end

-- P7 (a) Garry's Mod's source, (c) a failing microphone, (d) an older module -----------------------------------------------
do
    RunConsoleCommand("gsa1_lipsync_source", "1")
    M.speaking, M.volume = true, 0.5
    local m = mark()
    for _ = 1, 20 do frame(2) end
    M.speaking, M.volume = false, 0
    quiet()
    local lv, fm = calls_since(m, "FaceLevel", C.id), calls_since(m, "FaceMouth", C.id)
    local status = F.ShapesStatus() or ""
    local okA = #lv > 10 and #fm == 0 and #calls_since(m, "VisemeMouth") == 0 and lv[1][4] == 0 and lv[1][5] == SAME_PAIR
        and string.find(status, "Mouth shapes need G-SA1's own microphone listening", 1, true) ~= nil
    check(okA, "P7 Garry's Mod's source in style 2: the 0.9.4a mouth (FaceLevel style 0, %d calls, no FaceMouth) and the "
        .. "status line \"%s\"", #lv, status)
    RunConsoleCommand("gsa1_lipsync_source", "0")
    for _ = 1, 3 do frame(0) end
    -- (c) another microphone that fails
    R.mic.fail = "the device is busy"
    RunConsoleCommand("gsa1_lipsync_device", "1")
    M.speaking, M.volume = true, 0.5
    m = mark()
    for _ = 1, 20 do frame(2) end
    M.speaking, M.volume = false, 0
    quiet()
    lv, fm = calls_since(m, "FaceLevel", C.id), calls_since(m, "FaceMouth", C.id)
    status = F.ShapesStatus() or ""
    local opensC = calls_since(m, "MicOpen")
    check(#opensC == 1 and opensC[1][2] == 1 and M.convars.gsa1_lipsync_device_name.v == "Microphone (Test USB Mic)" and
        #lv > 10 and #fm == 0 and string.find(status,
        "The microphone failed: the device is busy; the mouth only opens with the voice", 1, true) ~= nil,
        "P7 the microphone failing: Garry's Mod's level on the 0.9.4a mouth (%d FaceLevel) and the status line \"%s\"",
        #lv, status)
    R.mic.fail = nil
    RunConsoleCommand("gsa1_lipsync_device", "-1")
    m = mark()
    for _ = 1, 10 do frame(2) end
    quiet()
    check(#calls_since(m, "FaceMouth", C.id) > 5, "P7 back on the working microphone: mouth shapes again")
    -- (d) a module with feature "faces" 1 (no MicViseme)
    local savedMV = G.MicViseme
    G.MicViseme, G.FEATURES.faces = nil, 1
    R.mic.level = 0.6
    m = mark()
    for _ = 1, 20 do frame(0) end
    R.mic.level = 0
    quiet()
    lv = calls_since(m, "FaceLevel", C.id)
    status = F.ShapesStatus() or ""
    build_page()
    local mouthOld = page_role("mouth")
    local third = mouthOld and mouthOld.choices[3] and mouthOld.choices[3][1] or ""
    G.MicViseme, G.FEATURES.faces = savedMV, 3
    check(#lv > 10 and #calls_since(m, "FaceMouth") == 0 and #calls_since(m, "VisemeMouth") == 0 and
        status == "Mouth shapes need G-SA1 module 0.9.4c" and third == "Mouth shapes from your voice (needs module 0.9.4c)"
        and #logs_with("mouth shapes need G-SA1 module 0.9.4c") == 1, "P7 an older module (feature \"faces\" 1): style 0 "
        .. "(%d FaceLevel), \"%s\", the combo's third choice \"%s\"", #lv, status, third)
    for _ = 1, 3 do frame(0) end
end

-- the "This character" line
do
    local line = F.CharacterShapesLines()[1]
    GSA1.Spawn("big")
    local big = F.CharacterShapesLines()[1]
    local bigStatus = F.ShapesStatus() or ""
    local CB = GSA1.Char
    local m = mark()
    keys[KEY_X] = true
    for _ = 1, 10 do frame(2) end
    quiet()
    local fm = calls_since(m, "FaceMouth", CB.id)
    local bigKeys = #fm > 5
    local opened = 0
    for _, x in ipairs(fm) do
        bigKeys = bigKeys and x[3] == 0 and (x[4] == 4 or (x[4] == 0 and x[5] == 0))
        if x[4] == 4 then opened = opened + 1 end
    end
    bigKeys = bigKeys and opened >= 8
    check(string.find(line, "This character (Sonic): ah 4>16 (", 1, true) == 1 and string.find(line,
        "f v th: opens with the voice", 1, true) ~= nil and big == "This character (Big): one mouth shape: it opens more or "
        .. "less with each sound" and string.find(bigStatus, "Big's face has one mouth shape", 1, true) ~= nil and bigKeys,
        "the page's \"This character\" line from VisemeTable (%s) and Big's (%s); Big talks with his keys 0 / 4 (closed "
        .. "0 > 0 in the silence)", line, big)
    GSA1.Spawn("sonic")
    C = GSA1.Char
    for _ = 1, 3 do frame(0) end
end

-- P10. the microphone test --------------------------------------------------------------------------------------------------------
do
    RunConsoleCommand("gsa1_lipsync_style", "0")
    keys[KEY_X] = false
    for _ = 1, 5 do frame(0) end
    local visBefore = R.vis.on
    build_page()
    local btn = F.ui and F.ui.micTest
    local m = mark()
    btn.DoClick(btn)
    local started = F.mtest.running and R.mic.listen and R.vis.on
    local pauses = 0
    local function step(cls)
        btn.Think(btn)
        local b = mark()
        frame(cls)
        for _, x in ipairs(calls_since(b, "MicListen")) do if x[2] == false then pauses = pauses + 1 end end
    end
    for _ = 1, 600 do step(2) end
    for _ = 1, 300 do step(4) end
    GSA1.Remove(true)                -- no character: the test goes on
    for _ = 1, 300 do step(6) end
    local mid = F.mtest.running and pauses == 0
    local countdown = btn.text
    for _ = 1, 650 do step(0) end
    local T = F.mtest
    local restored = calls_since(m, "MicVisemeOn")
    local ended = not T.running and T.why == "30 s" and R.vis.on == visBefore and R.mic.listen == false
    local heard = F.MicTestHeard()
    local lines = F.MicTestLines()[1]
    check(started and mid and countdown ~= nil and string.find(countdown, "Listening: ", 1, true) == 1 and ended and
        #restored == 2 and restored[1][2] == true and restored[2][2] == false and T.counts[2] > 500 and
        T.counts[4] > 250 and T.counts[6] > 250, "P10 the test listens 30 s without the talk key (MicListen(true)), the "
        .. "classifier on in style 0 and off again after (review R.18), the classes counted (%s), no pause by lip sync, "
        .. "with and without a character; stopped at 30 s; button \"%s\"", heard, tostring(countdown))
    check(string.find(lines, "Last test (30 s): heard: ah", 1, true) == 1, "P10 the result line: %s", lines)
    -- the page closes: the button is no longer shown
    btn.DoClick(btn)
    local again = F.mtest.running
    for _ = 1, 40 do frame(0) end
    check(again and not F.mtest.running and F.mtest.why == "the page closed" and R.vis.on == false, "P10 the test stops "
        .. "when the page closes (%s)", tostring(F.mtest.why))
    GSA1.Spawn("sonic")
    C = GSA1.Char
    RunConsoleCommand("gsa1_lipsync_style", "2")
    for _ = 1, 3 do frame(0) end
end

-- P7 (e). E-102 and both Super Sonics: no Face* / Viseme* / Mic* call ------------------------------------------------------
do
    local bad3 = {}
    for _, n in ipairs({ "gamma", "supersonic", "supersonic_general" }) do
        GSA1.Spawn(n)
        local X = GSA1.Char
        local m = mark()
        keys[KEY_X] = true
        RunConsoleCommand("gsa1_lipsync_style", "0")
        RunConsoleCommand("gsa1_lipsync_style", "2")
        for _, c in ipairs(expand({ { 2, 20 }, { 0, 60 } })) do frame(c) end
        local n3 = count_prefixes(m, { "Face", "Viseme", "Mic" })
        if n3 > 0 or not X then bad3[#bad3 + 1] = n .. " " .. tostring(n3) end
    end
    build_page()
    local tx = page_texts()
    local line = F.CharacterShapesLines()[1]
    check(#bad3 == 0 and string.find(line, "E-102", 1, true) == nil and string.find(line, "Super Sonic has no cutscene face",
        1, true) ~= nil, "P7 E-102 and both Super Sonics talking in style 2: no Face* / Viseme* / Mic* call%s (%s)",
        #bad3 > 0 and (": " .. table.concat(bad3, ", ")) or "", line)
    GSA1.Spawn("gamma")
    check(F.CharacterShapesLines()[1] == "This character: E-102 has no face in the game" and
        F.ShapesStatus() == "E-102 has no face in the game", "P7 E-102: \"E-102 has no face in the game\"")
    GSA1.Spawn("sonic")
    C = GSA1.Char
    keys[KEY_X] = false
    for _ = 1, 3 do frame(0) end
end

-- P14. privacy: the voice learning is never written nor sent (the owner's answer PQ7) -------------------------------------
do
    keys[KEY_X] = true
    RunConsoleCommand("gsa1_lipsync_shapes_log", "1")
    for _, c in ipairs(expand({ { 2, 30 }, { 4, 20 }, { 5, 20 } })) do frame(c) end
    build_page()
    local lineNow = F.SoundNowLines()[1]
    local meter = table.concat(F.MeterLines(), "\n")
    M.cmds["gsa1_lipsync_status"](nil, "gsa1_lipsync_status", {}, "")
    quiet()
    RunConsoleCommand("gsa1_lipsync_shapes_log", "0")
    keys[KEY_X] = false
    M.run_hook("ShutDown")
    GSA1.LogFlush()
    local G_TEXT = { "6.83", "6.830" }
    local function holds(text)
        for _, g in ipairs(G_TEXT) do
            if string.find(tostring(text), g, 1, true) then return true end
        end
        return false
    end
    local where = {}
    for path, text in pairs(M.files) do
        if holds(text) then where[#where + 1] = "file " .. path end
    end
    for name, c in pairs(M.convars) do
        if holds(c.v) then where[#where + 1] = "ConVar " .. name end
    end
    for k, v in pairs(jar) do
        if holds(v) then where[#where + 1] = "cookie " .. k end
    end
    for _, l in ipairs(logs) do
        if holds(l.text) or string.find(l.text, "voice %d") then where[#where + 1] = "log " .. l.text end
    end
    for _, v in ipairs(netWrites) do
        if holds(v) then where[#where + 1] = "net " .. v end
    end
    -- the Lua keeps no copy: no number of F's tables equals the learned one
    local seen, copies = {}, 0
    local function scan(t, depth)
        if seen[t] or depth > 4 then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "number" and math.abs(v - R.voice.g) < 1e-9 then copies = copies + 1 end
            if type(v) == "table" and k ~= "calls" then scan(v, depth + 1) end
        end
    end
    scan(F, 0)
    local tunesOnly = true
    for _, x in ipairs(calls_since(0, "MicVisemeTune")) do
        tunesOnly = tunesOnly and (x[2] == "gate_min_db" or x[2] == "adapt" or x[2] == "smooth" or x[2] == "reset_voice" or
            x[2] == "engine")
    end
    check(holds(lineNow) and holds(meter) and #where == 0 and copies == 0 and tunesOnly, "P14 the voice learning (6.83 "
        .. "here) is shown on the page and the console only: no DATA file, ConVar, cookie, log line (also with the numbers "
        .. "log on) or net write holds it, the Lua tables keep no copy, and the module is only ever told the settings "
        .. "and \"reset_voice\"%s", #where > 0 and (": " .. table.concat(where, "; ")) or "")
    -- a new session: the addon loads again and tells the module no voice (the learning lives in the module's memory only)
    local m = mark()
    local okRe = pcall(M.load, "gsa1/feat/cl_faces.lua")
    local sent = 0
    for _, x in ipairs(calls_since(m, "MicVisemeTune")) do if x[2] ~= "reset_voice" then sent = sent + 1 end end
    check(okRe and sent == 0 and #calls_since(m, "MicVisemeVoice") == 0, "P14 a new session's load gives the module no "
        .. "voice to start from (it starts from its adult prior)")
end

-- 0.9.4e ---------------------------------------------------------------------------------------------------------------------------
-- the page again (after P14's reload of cl_faces.lua) and a few helpers
local function role_think(r)
    local P = page_role(r)
    if P and rawget(P, "Think") then
        P.gsa1Next = nil
        P.Think(P)
    end
    return P
end
local function digits_in(text)
    return string.find(tostring(text), "%d") ~= nil
end
F = GSA1.Faces
L = F.lip
for _ = 1, 3 do frame(0) end

-- P17. Sound detection ----------------------------------------------------------------------------------------------------------
do
    keys[KEY_X] = false
    RunConsoleCommand("gsa1_lipsync_style", "0")
    for _ = 1, 3 do frame(0) end
    RunConsoleCommand("gsa1_lipsync_style", "2")
    local m = mark()
    keys[KEY_X] = true
    frame(0)
    local tunes = calls_since(m, "MicVisemeTune")
    local started = #tunes == 4 and tunes[4][2] == "engine" and tunes[4][3] == 2
    m = mark()
    RunConsoleCommand("gsa1_lipsync_hearing", "1")
    local t1 = calls_since(m, "MicVisemeTune")
    local changed = #t1 == 1 and t1[1][2] == "engine" and t1[1][3] == 1 and R.tune.engine == 1 and
        #logs_with("lip sync: sound detection as in 0.9.4c") == 1
    RunConsoleCommand("gsa1_lipsync_hearing", "2")
    keys[KEY_X] = false
    quiet()
    build_page()
    local hc = page_role("hearing")
    local okCombo = hc ~= nil and hc.enabled ~= false and rawget(hc, "gsa1ConVar") == "gsa1_lipsync_hearing" and
        #hc.choices == 2 and hc.choices[1][2] == "2" and hc.choices[2][2] == "1"
    -- an older module (faces 2): the combo greyed, no engine tune
    G.FEATURES.faces = 2
    build_page()
    local hc2 = page_role("hearing")
    local greyed = hc2 ~= nil and hc2.enabled == false and string.find(page_texts(), "needs G-SA1 module 0.9.4e", 1, true) ~=
        nil
    keys[KEY_X] = true
    RunConsoleCommand("gsa1_lipsync_style", "0")
    frame(0)
    RunConsoleCommand("gsa1_lipsync_style", "2")
    m = mark()
    frame(0)
    local noEngine = true
    for _, x in ipairs(calls_since(m, "MicVisemeTune")) do noEngine = noEngine and x[2] ~= "engine" end
    keys[KEY_X] = false
    quiet()
    G.FEATURES.faces = 3
    for _ = 1, 3 do frame(0) end
    check(started and changed, "P17 Sound detection: (\"engine\", 2) with the saved tunes when the classifier starts, "
        .. "(\"engine\", 1) and one log line on a change")
    check(okCombo and greyed and noEngine, "P17 the \"Sound detection\" combo (2 / 1) on the page; greyed \"needs G-SA1 "
        .. "module 0.9.4e\" and no engine tune with feature \"faces\" 2")
end

-- P15. the microphone by name ---------------------------------------------------------------------------------------------------
do
    local DEVS_B = {        -- a re-plug later: the numbers moved, Windows renumbered the USB device "3-" -> "4-"
        { index = 0, name = "Default", default = true, enabled = true, loopback = false },
        { index = 1, name = "Headset Microphone (Test Pad)", default = false, enabled = true, loopback = false },
        { index = 2, name = "Microphone (Test USB Mic)", default = true, enabled = true, loopback = false },
        { index = 3, name = "Microphone (4- Studio Pro)", default = false, enabled = true, loopback = false },
        { index = 4, name = "Line In (Test Card)", default = false, enabled = true, loopback = false },
        { index = 5, name = "Speakers (4- Studio Pro)", default = false, enabled = true, loopback = true },
        { index = 6, name = "Speakers (Test Card)", default = false, enabled = true, loopback = true },
    }
    local DEVS_C = {        -- the owner's case, invented names: index 6 a loopback whose own microphone is listed
        { index = 0, name = "Default", default = true, enabled = true, loopback = false },
        { index = 1, name = "Microphone (Voice Box)", default = true, enabled = true, loopback = false },
        { index = 2, name = "Microphone (3- Studio Pro)", default = false, enabled = true, loopback = false },
        { index = 3, name = "Stereo Mix (Test Card)", default = false, enabled = true, loopback = false },
        { index = 4, name = "Line In (Test Card)", default = false, enabled = true, loopback = false },
        { index = 5, name = "Speakers (Test Card)", default = false, enabled = true, loopback = true },
        { index = 6, name = "Speakers (3- Studio Pro)", default = false, enabled = true, loopback = true },
    }
    local function open_now()
        local m = mark()
        local ok = F.OpenMic(false)
        local o = calls_since(m, "MicOpen")
        return ok, o[#o] and o[#o][2], #o
    end
    -- (a) the combo by name; the lines
    R.devs = DEVS_A
    RunConsoleCommand("gsa1_lipsync_device_name", "")
    build_page()
    local mc = page_role("microphone")
    local names = {}
    for _, ch in ipairs(mc and mc.choices or {}) do names[#names + 1] = ch[1] end
    local listed = table.concat(names, " | ")
    local comboOk = mc ~= nil and rawget(mc, "gsa1ConVar") == "gsa1_lipsync_device_name" and #mc.choices == 4 and
        mc.choices[1][1] == "Windows default" and mc.choices[1][2] == "" and string.find(listed, "Speakers", 1, true) == nil
        and string.find(listed, "| Default", 1, true) == nil and mc.choices[4][1] ==
        "Stereo Mix (Test Card) (records what your PC plays)" and mc.choices[4][2] == "Stereo Mix (Test Card)"
    local lines = table.concat(F.MicListeningLines(), " / ")
    local linesOk = string.find(lines, "Listening to: Windows default (Microphone (Test USB Mic))", 1, true) ~= nil and
        string.find(lines, "2 devices that record what your PC plays are not listed", 1, true) ~= nil
    check(comboOk and linesOk, "P15 the \"Microphone\" combo lists names (%s), no loopback, no BASS \"Default\", Stereo "
        .. "Mix with its note; \"%s\"", listed, lines)
    check(string.find(page_texts(), "Pick your microphone by its name. Speaker devices (what your PC plays) are not listed. "
        .. "Voice changers (virtual microphones) pass their effects on, which changes the vowels G-SA1 hears: pick the real "
        .. "microphone.", 1, true) ~= nil, "P15 the help line of lipsync2_plan.md 7.1, in general words (review R.7)")
    -- (b) a name resolves to its number after the numbers moved
    RunConsoleCommand("gsa1_lipsync_device_name", "Line In (Test Card)")
    local okb1, idx1 = open_now()
    R.devs = DEVS_B
    local okb2, idx2 = open_now()
    check(okb1 and idx1 == 2 and okb2 and idx2 == 4 and M.convars.gsa1_lipsync_device.v == "4", "P15 \"Line In (Test "
        .. "Card)\" opens number %s, then %s after the numbers moved (the cache gsa1_lipsync_device %s)", tostring(idx1),
        tostring(idx2), M.convars.gsa1_lipsync_device.v)
    -- (c) review R.6: "Microphone (3- Studio Pro)" saved, "Microphone (4- Studio Pro)" present
    RunConsoleCommand("gsa1_lipsync_device_name", "Microphone (3- Studio Pro)")
    local n0 = #logs_with("opened")
    local okc, idxc = open_now()
    local openLines = logs_with("opened")
    check(okc and idxc == 3 and #openLines == n0 + 1 and string.find(openLines[#openLines],
        "microphone 3 'Microphone (4- Studio Pro)' opened", 1, true) ~= nil, "P15 review R.6: the saved \"Microphone (3- "
        .. "Studio Pro)\" opens \"Microphone (4- Studio Pro)\" (number %s); the open line carries the name: %s",
        tostring(idxc), tostring(openLines[#openLines]))
    -- (d) Windows' default shown and logged as the device it is
    RunConsoleCommand("gsa1_lipsync_device_name", "")
    local okd, idxd = open_now()
    local dl = logs_with("opened")
    check(okd and idxd == -1 and string.find(dl[#dl], "Windows' default 'Microphone (Test USB Mic)' opened", 1, true) ~=
        nil and F.MicNowText() == "Windows default (Microphone (Test USB Mic))", "P15 \"Windows default\" is shown and "
        .. "logged with the device it is now (%s)", F.MicNowText())
    -- (e) a vanished name: Windows' default and the note, one log line per name per session
    RunConsoleCommand("gsa1_lipsync_device_name", "Microphone (Gone Mic)")
    local oke, idxe = open_now()
    open_now()
    local el = table.concat(F.MicListeningLines(), " / ")
    check(oke and idxe == -1 and string.find(el, "Your microphone 'Microphone (Gone Mic)' is not connected: Windows' "
        .. "default is used", 1, true) ~= nil and #logs_with("the microphone 'Microphone (Gone Mic)' is not connected") ==
        1, "P15 a microphone that is not connected: MicOpen(-1), the page's note, one log line (%s)", el)
    -- (f) the one-time move (cookie gsa1_lipsync_device_094e)
    local function move_case(devs, idx)
        jar[F.MOVE_COOKIE] = nil
        R.devs = devs
        F.devNote = nil
        RunConsoleCommand("gsa1_lipsync_device_name", "")
        F.devCacheValue = idx
        RunConsoleCommand("gsa1_lipsync_device", tostring(idx))
        local l0 = #logs
        local ok, opened = open_now()
        return ok, opened, M.convars.gsa1_lipsync_device_name.v, F.devNote, #logs - l0
    end
    -- the owner's case: index 6 = "Speakers (3- Studio Pro)", its microphone "Microphone (3- Studio Pro)" is listed
    local ok6, op6, name6, note6 = move_case(DEVS_C, 6)
    check(ok6 and name6 == "Microphone (3- Studio Pro)" and op6 == 2 and note6 ~= nil and string.find(note6, "Your saved "
        .. "microphone was 'Speakers (3- Studio Pro)', which records what your PC plays: 'Microphone (3- Studio Pro)' is "
        .. "used now", 1, true) ~= nil, "P15 review R.6: a saved loopback \"Speakers (Y)\" moves to \"Microphone (Y)\" "
        .. "(number %s) with the note \"%s\"", tostring(op6), tostring(note6))
    -- a loopback without its microphone: Windows' default, the note, one log line
    local ok5, op5, name5, note5 = move_case(DEVS_C, 5)
    local moveLog = logs_with("microphone 5 'Speakers (Test Card)' records what the PC plays - not used")
    check(ok5 and name5 == "" and op5 == -1 and note5 ~= nil and string.find(note5, "Windows default (Microphone (Voice "
        .. "Box)) is used now", 1, true) ~= nil and #moveLog == 1, "P15 a saved loopback number without its microphone: "
        .. "Windows' default (MicOpen(-1)), the note \"%s\", one log line", tostring(note5))
    -- a real input's number -> its name; a second load changes nothing
    local ok4, op4, name4, _, nlog4 = move_case(DEVS_C, 4)
    RunConsoleCommand("gsa1_lipsync_device_name", "Microphone (Voice Box)")
    local again = F.MigrateDevice(DEVS_C)
    check(ok4 and name4 == "Line In (Test Card)" and op4 == 4 and again == false and
        M.convars.gsa1_lipsync_device_name.v == "Microphone (Voice Box)", "P15 a saved real input's number becomes its "
        .. "name (\"%s\"); a second load changes nothing", tostring(name4))
    -- owner answer EQ1 (0.9.4e verifier): a REAL input listed as not enabled keeps the choice (its name, no "records what
    -- your PC plays" note); a saved device that is not connected changes nothing and the move waits (no cookie)
    local DEVS_D = {
        { index = 0, name = "Default", default = true, enabled = true, loopback = false },
        { index = 1, name = "Microphone (Voice Box)", default = true, enabled = true, loopback = false },
        { index = 6, name = "Microphone (3- Example Mic)", default = false, enabled = false, loopback = false },
    }
    jar[F.MOVE_COOKIE] = nil
    F.devNote = nil
    RunConsoleCommand("gsa1_lipsync_device_name", "")
    RunConsoleCommand("gsa1_lipsync_device", "6")
    local dRan = F.MigrateDevice(DEVS_D)
    local dName, dNote = M.convars.gsa1_lipsync_device_name.v, F.devNote
    local DEVS_E = {
        { index = 0, name = "Default", default = true, enabled = true, loopback = false },
        { index = 1, name = "Microphone (Voice Box)", default = true, enabled = true, loopback = false },
    }
    jar[F.MOVE_COOKIE] = nil
    F.devNote = nil
    RunConsoleCommand("gsa1_lipsync_device_name", "")
    RunConsoleCommand("gsa1_lipsync_device", "6")
    local eRan = F.MigrateDevice(DEVS_E)
    local eName, eCookie, eNote = M.convars.gsa1_lipsync_device_name.v, jar[F.MOVE_COOKIE], F.devNote
    local eLater = F.MigrateDevice(DEVS_D)
    local eLaterName = M.convars.gsa1_lipsync_device_name.v
    check(dRan == true and dName == "Microphone (3- Example Mic)" and dNote == nil and eRan == false and eName == "" and
        eCookie == nil and eNote == nil and eLater == true and eLaterName == "Microphone (3- Example Mic)",
        "EQ1: a real input listed as not enabled keeps its choice (\"%s\", no speaker note); an unplugged saved microphone "
        .. "changes nothing and the move waits (cookie %s), then takes its name when it is back (\"%s\")", tostring(dName),
        tostring(eCookie), tostring(eLaterName))
    -- (g) a number typed on the console picks that device's name (a loopback: Windows' default)
    R.devs = DEVS_C
    RunConsoleCommand("gsa1_lipsync_device", "2")
    local typed2 = M.convars.gsa1_lipsync_device_name.v
    RunConsoleCommand("gsa1_lipsync_device", "6")
    local typed6 = M.convars.gsa1_lipsync_device_name.v
    check(typed2 == "Microphone (3- Studio Pro)" and typed6 == "", "P15 a number typed into gsa1_lipsync_device picks "
        .. "that device's name once (2: \"%s\"; the loopback 6: Windows' default)", typed2)
    -- (h) MicOpen's "unsupported" -> a plain-word failure on the page and in the status
    RunConsoleCommand("gsa1_lipsync_device_name", "Line In (Test Card)")
    R.mic.unsupported = 4
    local okh = open_now()
    local hl = table.concat(F.MicListeningLines(), " / ")
    local hs = F.ShapesStatus() or ""
    R.mic.unsupported = nil
    check(okh == false and string.find(hl, "The microphone could not be used: that device records what your PC plays "
        .. "(a speaker output), not a microphone", 1, true) ~= nil and string.find(hs, "The microphone failed: that device "
        .. "records what your PC plays", 1, true) ~= nil, "P15 MicOpen's \"unsupported\" in plain words: \"%s\"", hl)
    -- back to the first list and Windows' default
    R.devs = DEVS_A
    RunConsoleCommand("gsa1_lipsync_device_name", "")
    F.OpenMic(false)
    for _ = 1, 3 do frame(0) end
end

-- P16. a stalled stream -----------------------------------------------------------------------------------------------------
do
    keys[KEY_X] = true
    for _ = 1, 10 do frame(2) end
    local m = mark()
    local l0 = #logs_with("stopped sending sound")
    R.mic.stall = true
    local firstAt, n = nil, 0
    for i = 1, 60 * 8 do
        local b = mark()
        frame(2)
        for _, x in ipairs(calls_since(b, "MicOpen")) do
            if x[3] == true then
                n = n + 1
                firstAt = firstAt or i
            end
        end
    end
    R.mic.stall = false
    local reopens = {}
    for _, x in ipairs(calls_since(m, "MicOpen")) do reopens[#reopens + 1] = tostring(x[2]) .. "/" .. tostring(x[3]) end
    local logsN = #logs_with("stopped sending sound") - l0
    keys[KEY_X] = false
    quiet()
    check(firstAt ~= nil and firstAt >= 89 and firstAt <= 92 and n == 2 and logsN == 2 and R.mic.listen == false,
        "P16 blocks frozen 1.5 s while listening: MicOpen(index, true) after %s frames, at most once in 5 s (%d in 8 s: %s), "
        .. "one log line each", tostring(firstAt), n, table.concat(reopens, " "))
    keys[KEY_X] = true
    local m2 = mark()
    for _ = 1, 240 do frame(2) end
    keys[KEY_X] = false
    quiet()
    local forced = 0
    for _, x in ipairs(calls_since(m2, "MicOpen")) do if x[3] == true then forced = forced + 1 end end
    check(forced == 0, "P16 a stream that sends: no re-open (%d)", forced)
end

-- P18. the vowel warm-up -------------------------------------------------------------------------------------------------------
do
    RunConsoleCommand("gsa1_lipsync_style", "0")
    keys[KEY_X] = false
    for _ = 1, 5 do frame(0) end
    build_page()
    local wb = page_role("warmup")
    local function wframe(cls, think)
        if think ~= false then wb.Think(wb) end
        frame(cls or 0)
    end
    local visBefore, listenBefore = R.vis.on, R.mic.listen
    -- result 1 (learned)
    R.warm.next, R.warm.calls = 1, {}
    local l0 = #logs
    local t0 = M.T
    wb.DoClick(wb)
    local during = R.mic.listen and R.vis.on and F.warm.running
    local midLines
    for i = 1, 60 * 12 do
        wframe(i < 60 * 11 and 2 or 0)
        if i == 60 * 5 then midLines = table.concat(F.WarmLines(), " / ") end
        if not F.warm.running then break end
    end
    local steps, times = {}, {}
    for _, c in ipairs(R.warm.calls) do
        steps[#steps + 1] = c.step
        times[#times + 1] = string.format("%.2f", c.t - t0)
    end
    local WANT_T = { 0, 1.0, 3.0, 3.6, 5.6, 6.2, 8.2, 8.8, 10.8 }
    local timesOk = #R.warm.calls == 9
    for i, c in ipairs(R.warm.calls) do
        timesOk = timesOk and WANT_T[i] ~= nil and math.abs((c.t - t0) - WANT_T[i]) <= 1 / 60 + 1e-6
    end
    local learnedLog = logs_with("lip sync: vowel warm-up learned (this session only)")
    local myLogs = {}
    for i = l0 + 1, #logs do
        if string.find(logs[i].text, "warm-up", 1, true) then myLogs[#myLogs + 1] = logs[i].text end
    end
    check(table.concat(steps, " ") == "gap ah gap ee gap oo gap oh done" and timesOk, "P18 MicVisemeWarmup %s at %s s "
        .. "(lipsync2_plan.md 4.4: 0, 1, 3, 3.6, 5.6, 6.2, 8.2, 8.8, 10.8)", table.concat(steps, " "), table.concat(times,
        " "))
    check(during and not F.warm.running and R.vis.on == visBefore and R.mic.listen == listenBefore, "P18 listening without "
        .. "the talk key and the analysis on during it, both restored after (classifier %s, listening %s)",
        tostring(R.vis.on), tostring(R.mic.listen))
    check(F.WarmLines()[1] == F.WARM_RESULT_TEXT[1] and #learnedLog == 1 and #myLogs == 1 and not digits_in(myLogs[1]) and
        midLines ~= nil and string.find(midLines, "Heard: ah", 1, true) ~= nil, "P18 result 1: \"%s\"; one log line "
        .. "without numbers (%s); while it ran: \"%s\"", F.WarmLines()[1], tostring(myLogs[1]), tostring(midLines))
    -- result 2 (too short, with the counts on the page only), 4 (unclear)
    local function run_to_end(nextResult, rate)
        R.warm.next, R.warm.rate, R.warm.calls = nextResult, rate or 1, {}
        F.WarmStart(M.T)
        for _ = 1, 60 * 12 do
            wframe(2)
            if not F.warm.running then break end
        end
        R.warm.rate = 1
        return F.WarmLines()[1]
    end
    local short = run_to_end(2)
    local unclear = run_to_end(4)
    local shortLog = logs_with("vowel warm-up too short (this session only)")
    check(string.find(short, "Too short - say each sound for the whole two seconds (heard: ah ", 1, true) == 1 and
        unclear == F.WARM_RESULT_TEXT[4] and #shortLog == 1 and #logs_with("vowel warm-up unclear (this session only)") ==
        1, "P18 result 2: \"%s\"; result 4 (review R.5): \"%s\"", short, unclear)
    -- Stop and the page closing -> "cancel" (result 3)
    R.warm.calls = {}
    wb.DoClick(wb)
    for _ = 1, 90 do wframe(2) end
    wb.DoClick(wb)
    local stopCalls = {}
    for _, c in ipairs(R.warm.calls) do stopCalls[#stopCalls + 1] = c.step end
    local stopLine = F.WarmLines()[1]
    R.warm.calls = {}
    wb.DoClick(wb)
    for _ = 1, 60 do wframe(2, false) end
    local closeCalls = {}
    for _, c in ipairs(R.warm.calls) do closeCalls[#closeCalls + 1] = c.step end
    check(stopCalls[#stopCalls] == "cancel" and string.find(stopLine, "Stopped", 1, true) == 1 and
        closeCalls[#closeCalls] == "cancel" and not F.warm.running and string.find(F.WarmLines()[1], "the page closed", 1,
        true) ~= nil, "P18 Stop (%s) and the page closing (%s) end with \"cancel\": \"%s\"", table.concat(stopCalls, " "),
        table.concat(closeCalls, " "), stopLine)
    -- the microphone test and the warm-up exclude each other
    local mt = page_role("mictest")
    F.WarmStart(M.T)
    local okT = F.MicTestStart(M.T)
    F.WarmStop("test")
    mt.DoClick(mt)
    local okW = F.WarmStart(M.T)
    local wText = F.WarmLines()[1]
    mt.DoClick(mt)
    for _ = 1, 5 do frame(0) end
    check(okT == false and okW == false and not F.mtest.running and string.find(wText, "microphone test", 1, true) ~= nil,
        "P18 the warm-up and the microphone test refuse each other (\"%s\")", wText)
    -- greyed with engine 1, "Learn my voice" off, an older module
    local function greyed_now()
        wb.Think(wb)
        return wb.enabled == false and F.WarmStart(M.T) == false and not F.warm.running
    end
    RunConsoleCommand("gsa1_lipsync_hearing", "1")
    local g1 = greyed_now()
    RunConsoleCommand("gsa1_lipsync_hearing", "2")
    RunConsoleCommand("gsa1_lipsync_shapes_adapt", "0")
    local g2 = greyed_now()
    RunConsoleCommand("gsa1_lipsync_shapes_adapt", "1")
    G.FEATURES.faces = 2
    local g3 = greyed_now()
    G.FEATURES.faces = 3
    wb.Think(wb)
    check(g1 and g2 and g3 and wb.enabled == true, "P18 the button greyed with \"As in 0.9.4c\", \"Learn my voice\" off and "
        .. "an older module; usable again after")
    -- "Forget my voice" also clears the page's result
    F.warm.text, F.warm.result = F.WARM_RESULT_TEXT[1], 1
    M.cmds["gsa1_lipsync_forget_voice"](nil, "gsa1_lipsync_forget_voice", {}, "")
    check(F.warm.result == nil and F.WarmLines()[1] ~= F.WARM_RESULT_TEXT[1], "P18 \"Forget my voice\" also clears the "
        .. "warm-up's result line")
    RunConsoleCommand("gsa1_lipsync_style", "2")
    for _ = 1, 3 do frame(0) end
end

-- P19. the numbers line v2 -----------------------------------------------------------------------------------------------------
do
    keys[KEY_X] = true
    for _ = 1, 3 do frame(0) end
    -- with the switch off: MicVisemeFeatures is never read
    RunConsoleCommand("gsa1_lipsync_shapes_log", "0")
    local f0 = R.feat.calls
    for _ = 1, 20 do frame(2) end
    quiet()
    local offReads = R.feat.calls - f0
    RunConsoleCommand("gsa1_lipsync_shapes_log", "1")
    local n0 = #logs_with("lip sync spurt:")
    -- a spurt with 70 % silence: AA frames then a long pause inside the spurt (shorter than the hang) and the hang
    R.feat.rl, R.feat.per, R.feat.nbr, R.feat.lowr, R.feat.zcr, R.feat.raw, R.feat.eep = -4, 0.9, 0.95, 0.5, 0.1, 2, 0.45
    for i = 1, 12 do frame(2) end
    R.feat.raw, R.feat.rl, R.feat.per, R.feat.nbr, R.feat.lowr, R.feat.zcr, R.feat.eep = 7, -14, 0.3, 0.08, 0.04, 0.66, 0
    for i = 1, 6 do frame(7) end
    quiet()
    -- the same with the features of ANOTHER frame (their seq is not the frame's): not used
    R.feat.seqOff = 1
    for i = 1, 10 do frame(2) end
    quiet()
    R.feat.seqOff = 0
    RunConsoleCommand("gsa1_lipsync_shapes_log", "0")
    keys[KEY_X] = false
    local lines = logs_with("lip sync spurt:")
    local l1, l2 = lines[n0 + 1] or "", lines[n0 + 2] or ""
    info("P19 lines: %s | %s", l1, l2)
    local lv = tonumber(string.match(l1, "level median ([%d%.]+)")) or 0
    local soundN = tonumber(string.match(l1, "%(of (%d+) sound frames%)")) or -1
    local closing = tonumber(string.match(l1, "SIL %d+%% %(closing pause (%d+)%%%)")) or -1
    local okLine = string.find(l1, "(hearing 2, mouths G-SA1's v2)", 1, true) ~= nil and lv > 0.5 and soundN == 18 and
        closing >= 60 and string.find(l1, "AA -4/.90/.95/.50/.10", 1, true) ~= nil and
        string.find(l1, "SS -14/.30/.08/.04/.66", 1, true) ~= nil and string.find(l1, "ee near 12", 1, true) ~= nil
    check(offReads == 0, "P19 the switch off: MicVisemeFeatures never read (%d)", offReads)
    check(okLine, "P19 the line v2: the tags, the medians over the %s sound frames (level %.2f, not 0.01), the closing pause "
        .. "%s %%, per raw class rel_loc / per / nbr / lowr / zcr (AA -4/.90/.95/.50/.10, SS -14/.30/.08/.04/.66), ee near "
        .. "12", tostring(soundN), lv, tostring(closing))
    check(string.find(l2, "loc/per/nbr/lowr/zcr none", 1, true) ~= nil, "P19 features of another frame (seq not the "
        .. "frame's) are not used")
    local voiceIn = false
    for _, l in ipairs({ l1, l2 }) do
        for _, v in ipairs({ "6.83", "611", "1733" }) do
            if string.find(l, v, 1, true) then voiceIn = true end
        end
    end
    check(not voiceIn, "P19 no learned voice number in the lines")
    for _ = 1, 3 do frame(0) end
end

-- P14w. privacy of the learning and the vowel warm-up (the owner's answer PQ7) ----------------------------------------------------
do
    -- distinctive numbers: the learned voice and the warm-up's counts
    R.voice.g, R.voice.f1, R.voice.f2, R.voice.frames = 6.83, 611, 1733, 120
    local WCOUNT = { 173, 191, 157, 149 }
    local SECRET = { "6.83", "611", "1733", "173", "191", "157", "149" }
    local function holds(text)
        text = tostring(text)
        for _, v in ipairs(SECRET) do
            if string.find(text, v, 1, true) then return v end
        end
        return nil
    end
    -- every way out watched: files, cookies, sqlite, PData, ConVars, console commands, net, the log
    local outs = {}
    local function out(kind, ...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
        outs[#outs + 1] = { kind = kind, text = table.concat(t, " ") }
    end
    local saved = { write = file.Write, append = file.Append, mkdir = file.CreateDir, set = cookie.Set, rcc = RunConsoleCommand }
    file.Write = function(p, s2) out("file.Write " .. tostring(p), s2) return saved.write(p, s2) end
    file.Append = function(p, s2) out("file.Append " .. tostring(p), s2) return saved.append(p, s2) end
    file.CreateDir = function(p) out("file.CreateDir", p) end
    cookie.Set = function(k, v) out("cookie.Set", k, v) return saved.set(k, v) end
    sql = { Query = function(q) out("sql.Query", q) end, QueryValue = function(q) out("sql.QueryValue", q) end }
    util.SetPData = function(...) out("util.SetPData", ...) end
    M.player.SetPData = function(_, ...) out("SetPData", ...) end
    RunConsoleCommand = function(...) out("RunConsoleCommand", ...) return saved.rcc(...) end
    local netSaved = {}
    for _, n in ipairs({ "Start", "WriteString", "WriteFloat", "WriteUInt", "WriteBool", "WriteDouble", "WriteInt",
                         "WriteData", "WriteTable", "SendToServer" }) do
        netSaved[n] = net[n]
        net[n] = function(...)
            out("net." .. n, ...)
            if netSaved[n] then return netSaved[n](...) end
        end
    end
    local cvBefore = {}
    for n, c in pairs(M.convars) do cvBefore[n] = c.v end
    -- a warm-up (learned) with these counts, then 20 s of talking
    RunConsoleCommand("gsa1_lipsync_style", "2")
    RunConsoleCommand("gsa1_lipsync_shapes_log", "1")
    build_page()
    local wb = page_role("warmup")
    R.warm.next = 1
    wb.DoClick(wb)
    for _ = 1, 60 * 12 do
        wb.Think(wb)
        if R.warm.phase >= 0 and R.warm.phase <= 3 then R.warm.n[R.warm.phase + 1] = WCOUNT[R.warm.phase + 1] end
        frame(0)
        F.WarmLines()
        if not F.warm.running then break end
    end
    local learned = F.warm.result == 1
    keys[KEY_X] = true
    for i = 1, 60 * 20 do
        frame((i % 40 < 30) and ((i % 7) + 2) or 0)
        if i % 30 == 0 then
            F.SoundNowLines()
            F.MeterLines()
        end
    end
    M.cmds["gsa1_lipsync_status"](nil, "gsa1_lipsync_status", {}, "")
    keys[KEY_X] = false
    quiet()
    RunConsoleCommand("gsa1_lipsync_shapes_log", "0")
    GSA1.LogFlush()
    -- restore the watchers
    file.Write, file.Append, file.CreateDir, cookie.Set, RunConsoleCommand = saved.write, saved.append, saved.mkdir,
        saved.set, saved.rcc
    for n, f in pairs(netSaved) do net[n] = f end
    local where = {}
    local VOICE = { "6.83", "611", "1733" }
    for _, o in ipairs(outs) do
        local logFile = string.find(o.kind, "gsa1/log", 1, true) ~= nil
        if logFile then
            -- the session log: no learned voice number anywhere in it (the warm-up's counts: its lines below)
            for _, v in ipairs(VOICE) do
                if string.find(o.text, v, 1, true) then where[#where + 1] = o.kind .. " (" .. v .. ")" end
            end
        elseif not (o.kind == "file.CreateDir" and o.text == "gsa1") then
            local v = holds(o.text)
            if v then where[#where + 1] = o.kind .. " (" .. v .. ")" end
            -- no file but the session log (the warm-up never touches mouth_shapes.txt)
            if string.sub(o.kind, 1, 5) == "file." then where[#where + 1] = o.kind end
        end
    end
    for n, c in pairs(M.convars) do
        if cvBefore[n] ~= c.v and holds(c.v) then where[#where + 1] = "ConVar " .. n end
    end
    for k, v in pairs(jar) do
        if holds(v) then where[#where + 1] = "cookie " .. k end
    end
    for _, l in ipairs(logs) do
        local v = holds(l.text)
        if v and (string.find(l.text, "warm", 1, true) or string.find(l.text, "voice", 1, true)) then
            where[#where + 1] = "log " .. l.text
        end
    end
    -- the Lua keeps none of them (the page lines' text aside)
    local seen, copies = {}, {}
    local NUMS = { 6.83, 611, 1733, 173, 191, 157, 149 }
    local function scan(t, depth, path)
        if seen[t] or depth > 5 then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "number" then
                for _, x in ipairs(NUMS) do
                    if math.abs(v - x) < 1e-9 then copies[#copies + 1] = path .. "." .. tostring(k) end
                end
            elseif type(v) == "table" and k ~= "calls" and k ~= "lines" and k ~= "choices" then
                scan(v, depth + 1, path .. "." .. tostring(k))
            end
        end
    end
    scan(F, 0, "F")
    check(learned and #where == 0 and #copies == 0, "P14w a vowel warm-up (counts 173 / 191 / 157 / 149) and 20 s of talking "
        .. "with the learned voice 6.83 / 611 / 1733 Hz: no file but the session log, no cookie, sqlite, PData, ConVar, "
        .. "console command, net write or log line holds any of them; the Lua keeps no copy%s%s", #where > 0 and (": " ..
        table.concat(where, "; ")) or "", #copies > 0 and (" (copies: " .. table.concat(copies, ", ") .. ")") or "")
    -- a new session: the addon loads again on the module as a new session finds it (the learning forgotten at its close)
    R.voice.frames, R.voice.warmed, R.warm.phase, R.warm.result = 0, 0, -1, 0
    local m = mark()
    GSA1 = nil
    M.included = {}
    local okRe = pcall(M.load, "autorun/gsa1_autorun.lua")
    local F2 = GSA1 and GSA1.Faces
    local sentLearned = 0
    for _, x in ipairs(calls_since(m)) do
        if x[1] == "MicVisemeWarmup" then sentLearned = sentLearned + 1 end
        if x[1] == "MicVisemeTune" and not (x[2] == "gate_min_db" or x[2] == "adapt" or x[2] == "smooth" or
                x[2] == "engine") then
            sentLearned = sentLearned + 1
        end
        for i = 2, #x do
            if type(x[i]) == "number" then
                for _, v in ipairs(NUMS) do
                    if math.abs(x[i] - v) < 1e-9 then sentLearned = sentLearned + 1 end
                end
            end
        end
    end
    check(okRe and F2 ~= nil and F2.warm.result == nil and not F2.warm.running and F2.WarmStateText() ==
        "not used this session" and sentLearned == 0, "P14w a new session starts unwarmed (\"%s\") and tells the module "
        .. "nothing learned", F2 and F2.WarmStateText() or "?")
end

-- P13. the Lua <-> module contract (review R.11): build/<target>/faces2_api.txt, written by feat_faces_binding_test.cpp's V9
-- from the module as built (lines "feature faces 2", "fn Name(arg, arg, [opt]) -> ret, ret", "const TABLE.KEY value",
-- "const VISEME.NAMES[i] text", "tune name lo..hi", "field VisemeTable ...", "field VisemeTable.row ..."; # comments)
do
    local gsa1root = string.gsub(tests, "[/\\]tests$", "")
    local text = host_read(gsa1root .. "/build/x86_64-windows/faces2_api.txt")
    -- 0.9.4e (review R.4c): REQUIRED as soon as bind_faces.cpp declares feature "faces" 3 (a stale 0.9.4c file fails)
    local bindsrc = host_read(gsa1root .. "/src/module/bind_faces.cpp") or ""
    local required = string.find(bindsrc, "GSA1_FEATURE(faces, 3", 1, true) ~= nil
    if not required then
        info("P13 skipped: src/module/bind_faces.cpp does not declare GSA1_FEATURE(faces, 3 yet")
    elseif not text then
        check(false, "P13 build/x86_64-windows/faces2_api.txt is missing although bind_faces.cpp declares faces 3 (the "
            .. "binding test writes it before the Lua tests in build.py --test)")
    else
        local function trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
        local function list(s)
            local out = {}
            s = trim(s or "")
            if s == "" then return out end
            for item in string.gmatch(s .. ",", "([^,]*),") do out[#out + 1] = trim(item) end
            return out
        end
        local fns, consts, strs, tunes, fields, feature = {}, {}, {}, {}, {}, nil
        local steps, results, texts, codes = {}, {}, {}, {}
        for line in string.gmatch(text, "[^\r\n]+") do
            line = trim(line)
            if line ~= "" and string.sub(line, 1, 1) ~= "#" then
                local fname, fargs, frets = string.match(line, "^fn%s+([%w_]+)%s*%((.-)%)%s*%->%s*(.*)$")
                local cname, cval = string.match(line, "^const%s+(%S+)%s+(.+)$")
                local tname, tlo, thi = string.match(line, "^tune%s+([%w_]+)%s+([%-%d%.]+)%.%.([%-%d%.]+)$")
                local fld, frest = string.match(line, "^field%s+(%S+)%s+(.+)$")
                if fname then
                    local rets = trim(frets)
                    -- "true | nil, message, code" and "table | nil, ..." are status results, "nothing" none
                    local status = string.find(rets, "|", 1, true) ~= nil
                    fns[fname] = { args = list(fargs), rets = (status or rets == "nothing") and nil or list(rets),
                                   status = status }
                elseif string.match(line, "^feature%s") then
                    feature = line
                elseif cname and string.find(cname, "%[") then
                    strs[cname] = trim(cval)
                elseif cname then
                    consts[cname] = tonumber(cval)
                elseif tname then
                    tunes[tname] = { tonumber(tlo), tonumber(thi) }
                elseif string.match(line, "^tune%s+([%w_]+)$") then
                    tunes[string.match(line, "^tune%s+([%w_]+)$")] = true
                elseif fld then
                    local set = {}
                    for w in string.gmatch(frest, "[%w_]+") do set[w] = true end
                    fields[fld] = set
                end
                -- 0.9.4e: "step <Name> <words>", "result <Name>.<field> <list>", "text <Name>.<case> <message>",
                -- "code <Name>.<case> <code>"
                local kw, key, rest = string.match(line, "^(%a+)%s+(%S+)%s+(.+)$")
                if kw == "step" then
                    local set = {}
                    for w in string.gmatch(rest, "%S+") do set[w] = true end
                    steps[key] = set
                elseif kw == "result" then
                    results[key] = rest
                elseif kw == "text" then
                    texts[key] = rest
                elseif kw == "code" then
                    codes[key] = rest
                end
            end
        end
        local diffs = {}
        local nf, nc = 0, 0
        for name, want in pairs(MOCK_API) do
            nf = nf + 1
            local f = fns[name]
            if not f then
                diffs[#diffs + 1] = name .. " is not in the binding"
            else
                if table.concat(f.args, ", ") ~= table.concat(want.args, ", ") then
                    diffs[#diffs + 1] = string.format("%s(%s) (mock: %s)", name, table.concat(f.args, ", "),
                        table.concat(want.args, ", "))
                end
                if want.rets and table.concat(f.rets or {}, ", ") ~= table.concat(want.rets, ", ") then
                    diffs[#diffs + 1] = string.format("%s -> %s (mock: %s)", name, table.concat(f.rets or {}, ", "),
                        table.concat(want.rets, ", "))
                end
            end
        end
        local noSamePair = consts["FACE.SAME_PAIR"] == nil
        for name, v in pairs(MOCK_CONST) do
            nc = nc + 1
            if not (name == "FACE.SAME_PAIR" and noSamePair) and consts[name] ~= v then
                diffs[#diffs + 1] = string.format("%s = %s (mock %s)", name, tostring(consts[name]), tostring(v))
            end
        end
        for i = 0, 8 do
            for _, sub in ipairs({ "NAMES", "WORDS" }) do
                local k = string.format("VISEME.%s[%d]", sub, i)
                local mine = G.VISEME[sub][i]
                if strs[k] ~= nil and strs[k] ~= mine and strs[k] ~= ("\"" .. mine .. "\"") then
                    diffs[#diffs + 1] = string.format("%s = %s (mock %s)", k, strs[k], mine)
                end
            end
        end
        -- what cl_faces.lua sends: gate_min_db 3..12, adapt 0 / 1, smooth 0 / 2 / 3, reset_voice
        for name, r in pairs(TUNES) do
            local x = tunes[name]
            if type(x) ~= "table" or x[1] ~= r[1] or x[2] ~= r[2] then
                diffs[#diffs + 1] = string.format("tune %s %s (mock %d..%d)", name, type(x) == "table" and
                    (tostring(x[1]) .. ".." .. tostring(x[2])) or tostring(x), r[1], r[2])
            end
        end
        if not tunes.reset_voice then diffs[#diffs + 1] = "tune reset_voice missing" end
        local tf, rf = fields["VisemeTable"] or {}, fields["VisemeTable.row"] or {}
        -- 0.9.4e: the fields the page and the tester read (lipsync2_plan.md 5.5)
        for _, k in ipairs({ "ladder_cap", "table_version", "custom_spec", "mouth_at" }) do
            if not tf[k] then diffs[#diffs + 1] = "VisemeTable has no " .. k end
        end
        for _, k in ipairs({ "a", "b", "w", "how", "custom", "default" }) do
            if not rf[k] then diffs[#diffs + 1] = "VisemeTable's rows have no " .. k end
        end
        local df = fields["MicDevices"] or fields["MicDevices.entry"] or fields["MicDevices.device"]
        if not (df and df.loopback and df.name and df.index) then
            diffs[#diffs + 1] = "MicDevices' entries: no field line with index, name and loopback"
        end
        if feature ~= "feature faces 3" then diffs[#diffs + 1] = "feature line: " .. tostring(feature) end
        -- 0.9.4e: the warm-up's step words cl_faces.lua sends, its result codes as the page reads them, the refusal texts
        -- and codes this mock gives (lipsync2_plan.md 5.5)
        local ws = steps["MicVisemeWarmup"] or {}
        for _, st in ipairs(F.WARM_STEPS or {}) do
            if not ws[st.call] then diffs[#diffs + 1] = "MicVisemeWarmup has no step " .. tostring(st.call) end
        end
        if not ws.cancel then diffs[#diffs + 1] = "MicVisemeWarmup has no step cancel" end
        local rr = results["MicVisemeWarmupState.result"] or ""
        for code = 1, 4 do
            local want = string.format("%d %s", code, F.WARM_LOG_WORD[code])
            if not string.find(rr, want, 1, true) then diffs[#diffs + 1] = "MicVisemeWarmupState result " .. want end
        end
        local WANT_TEXT = { ["MicOpen.loopback"] = "that device records what your PC plays (a speaker output), not a microphone",
                            ["MicVisemeWarmup.engine1"] = "needs 'Sound detection' 0.9.4e",
                            ["MicVisemeWarmup.adapt0"] = "needs 'Learn my voice'",
                            ["MicVisemeWarmup.closed"] = "the microphone is not open" }
        for k, v in pairs(WANT_TEXT) do
            if texts[k] ~= v then diffs[#diffs + 1] = string.format("text %s = %s (mock %s)", k, tostring(texts[k]), v) end
        end
        local WANT_CODE = { ["MicOpen.loopback"] = "unsupported", ["MicVisemeWarmup.refused"] = "unsupported",
                            ["MicVisemeWarmup.word"] = "bad_argument", ["VisemeOverride.faceless"] = "unsupported" }
        for k, v in pairs(WANT_CODE) do
            if codes[k] ~= v then diffs[#diffs + 1] = string.format("code %s = %s (mock %s)", k, tostring(codes[k]), v) end
        end
        table.sort(diffs)
        if noSamePair then
            info("P13 the module has no FACE.SAME_PAIR (libsa1 did not build it): the switch greys (P8 tested it)")
        end
        check(#diffs == 0, "P13 this file's mock of the module equals faces2_api.txt (%d functions with their arguments "
            .. "and results, %d constants, the names and words, the tunes, the fields of VisemeTable and MicDevices; 0.9.4e: "
            .. "the warm-up's steps and results, the refusal texts and codes)%s", nf, nc, #diffs > 0 and
            (": " .. table.concat(diffs, "; ")) or "")
    end
end

check(#R.bad == 0, "every module call had valid arguments%s", #R.bad > 0 and (": " .. table.concat(R.bad, "; ", 1,
    math.min(#R.bad, 6))) or "")
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
