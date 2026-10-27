-- G-SA1 event faces, client (round 0.9.4a: the owner's request "Event faces ... animatable, easy to use, a switch to
-- toggle between event faces and regular faces, ... microphone support (like how Garry's Mod can lip sync speaking into
-- microphones)" and his face animations "a list of expression names, that when double clicked will be added to an
-- animation list ... frames to enter the expression, and frames to hold the expression"; sadc docs/research/
-- faces_wheel_plan.md 4.2-4.4, 4.7, 6.4, 7.2, 8.2 with its Review R.2 / R.6 / R.10; faces_wheel_ui.md 4, 5, 9). The
-- module's feature "faces" (src/module/bind_faces.cpp) on libsa1's faces (SA1_API_FACE): the game's own cutscene head
-- (the "EV head"), its face block, reader and blend. Q -> Options -> G-SA1 -> Faces has every setting.
--   * The switch (gsa1_face_event, off by default: the owner's answer FQ4): on = the cutscene head all the time with the
--     game's blinking idle; off = the regular face (face animations and talking show the cutscene head while they play).
--     Sent at once when it changes, and to a new character only while it is on (review R.6: a character of an owner who
--     never uses faces gets no face call at all). gsa1_face_pace: the game's cutscene speed for its own expressions.
--   * Face animations (data/gsa1/face_anims.txt, the defaults of sh_faces.lua): made with the maker on the page; played by
--     the ten hotkeys, the emote wheel's face trigger (feat/cl_wheel.lua through GSA1.Faces.Play) and the console.
--   * Lip sync (gsa1_lipsync*): every frame while you talk, one level (Garry's Mod's own voice level, or the microphone's
--     loudness read by the module through Garry's Mod's bass.dll - only while you hold the voice chat key by default,
--     nothing recorded or sent); ONE -1 when talking ends, then no call until the next talk (review R.6). libsa1 decides
--     which face wins (a face animation > talking > a kept face > the switch's face).
--   * 0.9.4c, the owner's note "I was hoping the lipsync system would actually do the phonemes" (sadc docs/research/
--     phoneme_plan.md 4.2-4.9, 6.3, 7.1 with its Review and the owner's answers 10.1): gsa1_lipsync_style 2 "mouth shapes
--     from your voice", the default (a saved 0 moved once). Per frame: gsa1.MicViseme (the module's classifier on the
--     microphone's 10 ms blocks: one of 9 kinds of sound, only while you hold the talk key) -> F.HoldClass -> F.Smooth ->
--     F.Variant -> gsa1.VisemeMouth (the character's mouth for it) -> gsa1.FaceMouth (or, for f / v, gsa1.FaceLevel kept
--     to a slit), with gsa1.FACE.SAME_PAIR ("Faster mouth") when the module has it. Garry's Mod's own voice level, a failed
--     microphone or an older module: the 0.9.4a mouth. The voice learning lives in the module's memory for the session
--     only: nothing of it is saved, logged or sent (the owner's answer PQ7). A 30-second microphone test on the page.
--   * Session log lines "faces" (the sources chosen, the face animations played, refusals; a summary at the end).
--   * 0.9.4e, the owner's note "the phoneme detection is pretty bad. it could be better" - worst: wrong shapes (sadc docs/
--     research/lipsync2_plan.md 4.4, 4.5, 4.8, 4.9, 6.3, 7.1 with its Review R.3 / R.5 / R.6 / R.7 / R.10): the microphone
--     by NAME (gsa1_lipsync_device_name; resolved to BASS's number at each open, exactly, then with Windows' "3- " renumbering
--     taken out, then Windows' default; speaker loopbacks never listed nor opened; a saved loopback number moved once; a
--     stalled stream opened again), "Sound detection" (gsa1_lipsync_hearing: the module's classifier v2 or 0.9.4c's), the
--     guided warm-up "Teach it my vowels" (F.Warm*: the module learns in its memory for the session only; this file keeps
--     only the result line's text), the numbers line v2 (gsa1.MicVisemeFeatures of the same frame, only with the log
--     switch on), the mouth shape tester's hook (feat/cl_mouthtest.lua: F.TesterFrame wins the frame, lip sync yields
--     without its -1; a face animation ends a kept tester mouth).
-- Characters without a face (E-102, both Super Sonics) never get a face call.
GSA1 = GSA1 or {}
local F = GSA1.Faces
if not F then error("gsa1/feat/sh_faces.lua did not load: the faces need it") end

local band = bit.band

-- settings (every one has a control on the Faces page) -------------------------------------------------------------------
local cv = {
    event = GSA1.ConVar("gsa1_face_event", 0, "Event faces: the character always wears its cutscene face and blinks like in "
        .. "the game's cutscenes (0 = the regular face; face animations and talking show the cutscene face while they play)",
        0, 1),
    event_key = GSA1.ConVar("gsa1_face_event_key", 0, "A key that switches event faces on and off (a key code; 0 = none: "
        .. "bind gsa1_face_toggle instead)", 0, 511),
    pace = GSA1.ConVar("gsa1_face_pace", 0, "Event faces: the game's own expressions and blinks at the cutscenes' half "
        .. "speed (your own enter / hold frames never change)", 0, 1),
    summary = GSA1.ConVar("gsa1_face_summary", "", "Read-only: your face animations, for the session log (the animations "
        .. "themselves are garrysmod/data/gsa1/face_anims.txt)"),
    lipsync = GSA1.ConVar("gsa1_lipsync", 1, "Lip sync: the mouth moves when you talk (only while you hold the voice chat "
        .. "key unless gsa1_lipsync_listen is 1)", 0, 1),
    source = GSA1.ConVar("gsa1_lipsync_source", 0, "Lip sync's voice: 0 = automatic (Garry's Mod's voice level when it "
        .. "reports yours, else the microphone), 1 = Garry's Mod's voice chat, 2 = the microphone (G-SA1 reads only its "
        .. "loudness; nothing is recorded or sent)", 0, 2),
    listen = GSA1.ConVar("gsa1_lipsync_listen", 0, "Lip sync listens 0 = only while you hold the voice chat key, 1 = always "
        .. "(an open microphone)", 0, 1),
    key = GSA1.ConVar("gsa1_lipsync_key", 0, "Lip sync's talk key (a key code; 0 = the key bound to +voicerecord)", 0, 511),
    device = GSA1.ConVar("gsa1_lipsync_device", -1, "G-SA1's cache of the microphone's number (choose by name on the "
        .. "Faces page)", -1, 63),
    -- 0.9.4e (lipsync2_plan.md 7.1 / 7.2)
    device_name = GSA1.ConVar("gsa1_lipsync_device_name", "", "The microphone for lip sync, by its name (empty = Windows' "
        .. "default). Speaker devices (what your PC plays) are never used"),
    hearing = GSA1.ConVar("gsa1_lipsync_hearing", 2, "Sound detection: 2 = G-SA1 0.9.4e's (vowels in the middle of words "
        .. "keep the mouth open, 'ee' only for a real 'ee', 's' told from 'f'), 1 = as in 0.9.4c", 1, 2),
    custom = GSA1.ConVar("gsa1_lipsync_shapes_custom", 1, "Use my mouths (Faces page > Mouth shape tester); 0 = G-SA1's "
        .. "mouths for everyone (your choices stay saved in garrysmod/data/gsa1/mouth_shapes.txt)", 0, 1),
    closeup = GSA1.ConVar("gsa1_mouth_closeup", 1, "A small live picture of your character's face on the Faces page's "
        .. "mouth shape tester while the page is open", 0, 1),
    msummary = GSA1.ConVar("gsa1_mouth_summary", "", "Read-only: your own mouths, for the session log (the mouths themselves "
        .. "are garrysmod/data/gsa1/mouth_shapes.txt)"),
    style = GSA1.ConVar("gsa1_lipsync_style", 2, "The mouth: 0 = it opens with your voice (like Garry's Mod's mouths), "
        .. "1 = the game's talking animations while you talk, 2 = mouth shapes from your voice (G-SA1 hears which kind of "
        .. "sound you make while you hold the talk key and gives the character the matching mouth; needs Voice from "
        .. "Automatic or The microphone)", 0, 2),
    -- 0.9.4c (phoneme_plan.md 7.1 with its Review R.6 / R.10 and the owner's answers 10.1)
    fast = GSA1.ConVar("gsa1_lipsync_fast", 1, "Faster mouth: the mouth appears 1/30 s sooner (the game's own face blend "
        .. "is done just before the frame is drawn instead of just after); 0 = exactly the game's order", 0, 1),
    size = GSA1.ConVar("gsa1_lipsync_shapes_size", 0.5, "Mouth shapes: how much loudness changes the mouth's size (0 = "
        .. "every sound shows its full mouth, 1 = quiet talking gives small mouths)", 0, 1),
    big = GSA1.ConVar("gsa1_lipsync_shapes_big", 1, "Bigger mouths for loud speech (Sonic's laugh mouth, Knuckles' "
        .. "shout, Tails' big 'ah': the eyes or brows move a little); 0 = only the game's own talking mouths (also limits "
        .. "'opens with your voice')", 0, 1),
    loud = GSA1.ConVar("gsa1_lipsync_shapes_loud", 0.8, "Mouth shapes: the loud mouths from this level (the 'Sound now' "
        .. "line shows yours)", 0.5, 1),
    steady = GSA1.ConVar("gsa1_lipsync_shapes_steady", 0, "Mouth shape changes: 0 = quick (a shape stays at least one "
        .. "game frame), 1 = steadier (two), 2 = instant", 0, 2),
    sgate = GSA1.ConVar("gsa1_lipsync_shapes_gate", 6, "Mouth shapes: a sound must be this many dB above the room's own "
        .. "noise to count as speech", 3, 12),
    adapt = GSA1.ConVar("gsa1_lipsync_shapes_adapt", 1, "Mouth shapes learn how high or low your voice is while you talk "
        .. "(in memory for this session only; nothing is saved or sent; also what 'Teach it my vowels' learned)", 0, 1),
    rise = GSA1.ConVar("gsa1_lipsync_shapes_rise", 0.015, "Mouth shapes: seconds the mouth takes to open (the kind of "
        .. "sound decides when it changes; this only smooths its size)", 0.005, 0.06),
    slog = GSA1.ConVar("gsa1_lipsync_shapes_log", 0, "Mouth shapes: one line of numbers per sentence in the session log "
        .. "(how often each kind of sound came, two averages per vowel, how loud and, per kind of sound, how loud, voiced "
        .. "and hissy it was; never the sound)", 0, 1),
    gain = GSA1.ConVar("gsa1_lipsync_gain", 2, "Lip sync's sensitivity (2 = Garry's Mod's own)", 0.5, 8),
    gate = GSA1.ConVar("gsa1_lipsync_gate", 0.05, "Lip sync ignores sounds quieter than this (0..0.5)", 0, 0.5),
    release = GSA1.ConVar("gsa1_lipsync_release", 0.12, "Seconds the mouth takes to close", 0.03, 0.5),
    hang = GSA1.ConVar("gsa1_lipsync_hang", 0.6, "Seconds of silence before the regular face comes back", 0.2, 3),
}
F.HOTKEYS = 10
cv.hotkey, cv.hotkey_anim = {}, {}
for i = 1, F.HOTKEYS do
    cv.hotkey[i] = GSA1.ConVar("gsa1_face_hotkey_" .. i, 0, "Face hotkey " .. i .. ": a key code (0 = none) that plays "
        .. "gsa1_face_hotkey_anim_" .. i, 0, 511)
    cv.hotkey_anim[i] = GSA1.ConVar("gsa1_face_hotkey_anim_" .. i, "", "Face hotkey " .. i .. ": the face animation it "
        .. "plays (a name of the Faces page)")
end
F.cv = cv

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("faces", fmt, ...) end
end
F.LogLine = log

-- 0.9.4c (phoneme_plan.md 10.1 PQ1, the owner: "Yes"): a saved 0 (0.9.4a's default, "opens with your voice") becomes 2
-- ("mouth shapes from your voice") once per installation (a cookie, as cl_super.lua's voice move); a saved 1 or 2 stays,
-- and so does a 0 chosen afterwards. true when it changed the setting
F.STYLE_COOKIE = "gsa1_lipsync_style_094c"
function F.MigrateStyle()
    if not (cookie and cookie.GetNumber and cookie.Set) or cookie.GetNumber(F.STYLE_COOKIE, 0) ~= 0 then
        return false
    end
    cookie.Set(F.STYLE_COOKIE, "1")
    if cv.style:GetInt() ~= 0 then return false end
    RunConsoleCommand("gsa1_lipsync_style", "2")
    log("lip sync: the mouth moved once from \"opens with your voice\" (0.9.4a's default) to \"mouth shapes from your "
        .. "voice\" (0.9.4c's default); the Faces page's \"Mouth\" choice takes it back")
    return true
end
F.MigrateStyle()

-- the loaded module has the feature
local function have()
    return GSA1.mod ~= nil and gsa1 ~= nil and gsa1.FaceSequence ~= nil and gsa1.FaceLevel ~= nil
end
F.Have = have
local function const(name, default)
    local t = gsa1 and gsa1.FACE
    return t and tonumber(t[name]) or default
end
F.Const = const

-- 1. the characters' faces ------------------------------------------------------------------------------------------------
F.SHORT = { gamma = "E-102", supersonic = "Super Sonic", supersonic_general = "Super Sonic" }
local function entry_of(name)
    if name == nil or name == "" then return nil end
    local kind, def = GSA1.KindByName(name)
    return kind, def
end
function F.Title(entry_name)
    local _, def = entry_of(entry_name)
    if not def then return tostring(entry_name) end
    return F.SHORT[def.name] or def.title
end
-- why an entry has no face (nil when it has one)
function F.NoFaceText(entry_name)
    local kind, def = entry_of(entry_name)
    if not kind then return "no such character" end
    if def.name == "gamma" or kind == 6 then return "E-102 has no face in the game" end
    if kind == 8 or def.form == "general" then return "Super Sonic has no cutscene face in the game" end
    if not F.FACE_KINDS[kind] then return F.Title(entry_name) .. " has no face in G-SA1" end
    return nil
end
function F.HasFaces(entry_name)
    if F.NoFaceText(entry_name) then return false end
    if not have() then return false end
    local kind = entry_of(entry_name)
    local info = F.Info(kind)
    return info == nil or info.has_face ~= false
end

-- gsa1.FaceInfo(kind) reads the disc in libsa1 (tens of ms; review R.2): once per kind per session. "not_ready" (the disc
-- is still loading) is asked again after 2 s at the earliest; any other failure is not asked again in this session (a
-- failing disc read every 2 s would be a hitch every 2 s): the faces then go by the expected letters and libsa1's checks
F.info, F.infoTry, F.infoFail = F.info or {}, F.infoTry or {}, F.infoFail or {}
function F.Info(kind)
    kind = tonumber(kind)
    if kind == nil then return nil end
    local i = F.info[kind]
    if i then return i end
    if F.infoFail[kind] or not (have() and gsa1.FaceInfo) then return nil end
    local now = SysTime()
    if now - (F.infoTry[kind] or -1e9) < 2 then return nil end
    F.infoTry[kind] = now
    local t, err, code = gsa1.FaceInfo(kind)
    if type(t) == "table" then
        F.info[kind] = t
        return t
    end
    F.infoError = tostring(err)
    if code ~= "not_ready" then
        F.infoFail[kind] = F.infoError
        log("the face numbers of kind %d could not be read: %s", kind, F.infoError)
    end
    return nil
end
-- the letters an entry can show (the module's mask; before the disc is read the expected one, then `exact` is false)
function F.Letters(entry_name)
    local kind = entry_of(entry_name)
    if kind == nil or F.NoFaceText(entry_name) then return 0, true end
    local info = F.Info(kind)
    if info then return tonumber(info.letters) or 0, true end
    return F.EXPECTED_LETTERS[kind] or 0, false
end

-- 2. the library (data/gsa1/face_anims.txt) ------------------------------------------------------------------------------
function F.LoadLibrary()
    local text = file.Read(F.FILE, "DATA")
    if text == nil then
        F.lib, F.badLines, F.loadNotes, F.fromFile = F.CopyList(F.DEFAULTS), 0, {}, false
    else
        F.lib, F.badLines, F.loadNotes = F.ParseLibrary(text)
        F.fromFile = true
    end
    F.libVersion = (F.libVersion or 0) + 1
    if cv.summary and cv.summary:GetString() ~= F.MirrorString(F.lib) then cv.summary:SetString(F.MirrorString(F.lib)) end
    return F.lib
end
function F.SaveLibrary()
    if file.CreateDir then file.CreateDir("gsa1") end
    file.Write(F.FILE, F.SerializeLibrary(F.lib))
    F.fromFile = true
    F.libVersion = (F.libVersion or 0) + 1
    if cv.summary then cv.summary:SetString(F.MirrorString(F.lib)) end
end
function F.Library()
    return F.lib or F.LoadLibrary()
end
function F.Find(name)
    if type(name) ~= "string" then return nil end
    for _, a in ipairs(F.Library()) do
        if a.name == name then return a end
    end
    return nil
end
local function find_ci(name, except)
    for i, a in ipairs(F.Library()) do
        if string.lower(a.name) == string.lower(name) and a ~= except then return a, i end
    end
    return nil
end
local function changed(change)
    change.renamed, change.deleted, change.saved = change.renamed or {}, change.deleted or {}, change.saved or {}
    -- the hotkeys follow a rename and forget a deleted one
    for i = 1, F.HOTKEYS do
        local n = cv.hotkey_anim[i]:GetString()
        if change.renamed[n] then
            cv.hotkey_anim[i]:SetString(change.renamed[n])
        elseif change.deleted[n] then
            cv.hotkey_anim[i]:SetString("")
        end
    end
    hook.Run("GSA1FaceLibraryChanged", change)
end
F.LoadLibrary()

-- 3. playing ----------------------------------------------------------------------------------------------------------
F.counts = F.counts or { played = 0, refused = 0 }
-- can the entry show the face animation (a name or an animation table)? true | false, why
function F.CanShow(name, entry_name)
    local anim = type(name) == "table" and name or F.Find(name)
    if not anim then return false, string.format("no face animation named \"%s\"", tostring(name)) end
    local no = F.NoFaceText(entry_name)
    if no then return false, no end
    if not have() then return false, "the loaded G-SA1 module has no faces (0.9.4a or newer is needed)" end
    local mask = F.Letters(entry_name)
    local missing = band(F.UsedMask(anim), bit.bnot(mask))
    if missing ~= 0 then return false, string.format("%s can't show %s", F.Title(entry_name), F.LettersText(missing)) end
    return true
end

-- plays an animation table on C now (Play, the hotkeys, Preview); true | nil, reason
function F.PlayAnim(C, anim, why)
    if not C or not C.id then return nil, "no character" end
    local ok, no = F.CanShow(anim, C.name)
    if not ok then
        F.counts.refused = F.counts.refused + 1
        log("%s not played on %s (%s): %s", tostring(anim.name or "the face animation"), C.title or "?", why or "?", no)
        return nil, no
    end
    -- 0.9.4e: a face animation ends a mouth the tester keeps (lipsync2_plan.md 4.8)
    if F.TesterStop then F.TesterStop("a face animation") end
    local spec, flags = F.SpecOf(anim, const("HOLD_LAST", 4))
    local r, err = gsa1.FaceSequence(C.id, spec, flags)
    if not r then
        F.counts.refused = F.counts.refused + 1
        log("%s refused on %s (%s): %s", tostring(anim.name), C.title or "?", why or "?", tostring(err))
        return nil, tostring(err)
    end
    F.counts.played = F.counts.played + 1
    F.held = anim.hold_last and { id = C.id, name = anim.name } or nil
    log("expression %s (%s) on %s: %s%s", tostring(anim.name), why or "?", C.title or "?", spec,
        anim.hold_last and " (keeps the last face)" or "")
    return true
end
function F.Play(C, name, why)
    local anim = F.Find(name)
    if not anim then return nil, string.format("no face animation named \"%s\"", tostring(name)) end
    return F.PlayAnim(C, anim, why)
end
function F.Stop(C)
    F.held = nil
    if not (C and C.id and have()) or not F.HasFaces(C.name) then return nil, "no character with a face" end
    local r, err = gsa1.FaceStop(C.id)
    if not r then return nil, tostring(err) end
    log("expression stopped on %s", C.title or "?")
    return true
end

-- 4. the switch -----------------------------------------------------------------------------------------------------------
-- sends the switch to C (review R.6: only when it changes, or to a new character while it is on)
function F.ApplyMode(C, how)
    if not (C and C.id and have() and gsa1.FaceMode) or not F.HasFaces(C.name) then return false end
    local on, pace = cv.event:GetBool(), cv.pace:GetBool()
    local r, err = gsa1.FaceMode(C.id, on, on and pace)
    if not r then
        log("event faces %s on %s refused: %s", on and "on" or "off", C.title or "?", tostring(err))
        return false
    end
    log("event faces %s%s on %s (%s)", on and "on" or "off", (on and pace) and " at the cutscene pace" or "", C.title or "?",
        how or "the switch")
    return true
end
local function on_of(v)
    return (tonumber(v) or 0) ~= 0
end
cvars.AddChangeCallback("gsa1_face_event", function(_, old, new)
    if on_of(old) == on_of(new) then return end
    F.ApplyMode(GSA1.Char, F.switchHow or "the switch")
end, "gsa1_faces")
cvars.AddChangeCallback("gsa1_face_pace", function(_, old, new)
    if on_of(old) == on_of(new) or not cv.event:GetBool() then return end
    F.ApplyMode(GSA1.Char, "the cutscene pace")
end, "gsa1_faces")
function F.Toggle(how)
    F.switchHow = how
    RunConsoleCommand("gsa1_face_event", cv.event:GetBool() and "0" or "1")
    F.switchHow = nil
end

-- 5. lip sync (faces_wheel_ui.md 5.2-5.4) ----------------------------------------------------------------------------------
local L = F.lip or { s = 0, quiet = 1e9 }
F.lip = L
L.talkTime, L.levelSum, L.levelN = L.talkTime or 0, L.levelSum or 0, L.levelN or 0
-- 0.9.4c: style 2's state (F.HoldClass / F.Variant), the spurt's numbers, the microphone test
L.hold, L.spurt = L.hold or {}, L.spurt or {}
F.mtest = F.mtest or { running = false, counts = {}, n = 0 }
F.MICTEST_SECONDS = 30
-- 0.9.4e: the vowel warm-up's page state (F.Warm*): the step, its times, the result code and the result line's text only
F.warm = F.warm or { running = false }
-- the talk key: gsa1_lipsync_key, else the key bound to +voicerecord (looked up once a second)
function F.TalkKeyCode()
    local k = cv.key:GetInt()
    if k > 0 then return k end
    local now = SysTime()
    if L.bindAt == nil or now - L.bindAt > 1 then
        L.bindAt = now
        L.bindCode = 0
        local b = input and input.LookupBinding and input.LookupBinding("+voicerecord")
        if b and input.GetKeyCode then L.bindCode = tonumber(input.GetKeyCode(b)) or 0 end
    end
    return L.bindCode or 0
end
local function typing()
    local ply = LocalPlayer()
    return IsValid(ply) and ply.IsTyping ~= nil and ply:IsTyping() == true
end
function F.TalkKeyDown()
    if typing() then return false end
    local code = F.TalkKeyCode()
    return code > 0 and input and input.IsButtonDown and input.IsButtonDown(code) == true or false
end
-- 0.9.4e: the microphone by its NAME (lipsync2_plan.md 4.5 with review R.6 / R.7). gsa1_lipsync_device_name is the
-- setting ("" = Windows' default); BASS's number moves whenever a controller, a voice changer or a re-plugged USB
-- microphone comes or goes, so the name is resolved to the number at each open (gsa1.MicDevices once per open, never per
-- frame): exactly, then normalised, then Windows' default. Speaker loopbacks (BASS's "what the PC plays" devices) are never
-- listed nor opened. gsa1_lipsync_device stays as the cache of the last number opened.
F.MOVE_COOKIE = "gsa1_lipsync_device_094e"
F.STALL_SECONDS = 1.5            -- MicLevel's blocks unchanged this long while listening: the stream stalled
F.REOPEN_EVERY = 5               -- s: at most one forced re-open
F.devMissingLogged = F.devMissingLogged or {}
-- "Microphone (3- Studio Pro)" -> "microphone (studio pro)": Windows numbers a second instance of a USB device "3- ..." and
-- renumbers it when the device comes back on another port (review R.6)
function F.MicNormName(name)
    local n = string.lower(tostring(name or ""))
    n = string.gsub(n, "%(%s*%d+%s*%-%s*", "(")
    return n
end
-- BASS's own "Default" entry (its first device: a duplicate of Windows' default)
local function bass_default_entry(d)
    return string.lower(tostring(d.name or "")) == "default"
end
-- a device the Microphone list offers: enabled, not a loopback (what the PC plays), not BASS's own "Default"
local function listable(d)
    return type(d) == "table" and d.index ~= nil and d.enabled ~= false and d.loopback ~= true and not bass_default_entry(d)
end
F.MicListable = listable
-- Windows' own "what the PC plays" recording inputs: listed (with a note), as they are not loopbacks
local PLAYS_NAMES = { "stereo mix", "what u hear", "wave out mix" }
function F.MicPlaysName(name)
    local n = string.lower(tostring(name or ""))
    for _, p in ipairs(PLAYS_NAMES) do
        if string.find(n, p, 1, true) then return true end
    end
    return false
end
-- gsa1.MicDevices() (at each open and at the page's build, never per frame); F.devList / F.devNames keep the last list
function F.MicDevicesList()
    if not (have() and gsa1.MicDevices) then return nil, "the module has no microphone list" end
    local list, err = gsa1.MicDevices()
    if type(list) ~= "table" then
        F.devListError = tostring(err)
        return nil, F.devListError
    end
    F.devList, F.devListError = list, nil
    F.devNames = {}
    for _, d in ipairs(list) do
        if d.index ~= nil then F.devNames[d.index] = tostring(d.name) end
    end
    return list
end
-- Windows' default input as BASS lists it (review R.6): the enabled, non-loopback entry with the default flag other than
-- BASS's own "Default" entry; nil when the list has none
function F.MicDefaultName(list)
    for _, d in ipairs(list or F.devList or {}) do
        if listable(d) and d.default then return tostring(d.name) end
    end
    return nil
end
-- "Windows default (Microphone (X))" / "Windows default"
function F.MicDefaultText(list)
    local n = F.MicDefaultName(list)
    return n and ("Windows default (" .. n .. ")") or "Windows default"
end
-- the setting's name -> BASS's number now: index (-1 = Windows' default), the device's name, how ("exact", "normalised",
-- "default", "missing"); the cached number first when its name still matches
function F.MicResolve(name, list)
    name = tostring(name or "")
    list = list or F.devList or {}
    if name ~= "" then
        local cached = cv.device:GetInt()
        for _, d in ipairs(list) do
            if d.index == cached and listable(d) and d.name == name then return d.index, name, "exact" end
        end
        for _, d in ipairs(list) do
            if listable(d) and d.name == name then return d.index, name, "exact" end
        end
        local norm = F.MicNormName(name)
        for _, d in ipairs(list) do
            if listable(d) and F.MicNormName(d.name) == norm then return d.index, tostring(d.name), "normalised" end
        end
        return -1, F.MicDefaultName(list), "missing"
    end
    return -1, F.MicDefaultName(list), "default"
end
-- the cache gsa1_lipsync_device (its change callback leaves G-SA1's own writes alone)
local function cache_index(idx)
    if cv.device:GetInt() == idx then return end
    F.devCacheValue = idx
    cv.device:SetInt(idx)
end
local function set_device_name(name)
    if cv.device_name:GetString() ~= name then cv.device_name:SetString(name) end
end
-- 0.9.4e, once per installation (a cookie, as cl_super.lua's 0.9.3b move): a 0.9.4a-0.9.4d number becomes a name. A real
-- input -> its name; a speaker loopback "Speakers (X)" -> "Microphone (X)" or "Headset Microphone (X)" when exactly one
-- exists (review R.6: a USB microphone's own speaker output is a loopback next to it), else Windows' default; gone -> Windows'
-- default. One log line and, when it was moved, the page's note. true when it ran
function F.MigrateDevice(list)
    -- owner answer EQ1 (lipsync2_plan.md 10.1, binding): the saved device is moved ONLY when BASS flags it a loopback at run
    -- time; a real input keeps its choice (by name), whether BASS lists it as enabled or not, and a device that is not
    -- connected right now changes nothing - the move waits for a start where it is there (0.9.4e verifier)
    if not (cookie and cookie.GetNumber and cookie.Set) or cookie.GetNumber(F.MOVE_COOKIE, 0) ~= 0 then return false end
    list = list or F.MicDevicesList()
    if type(list) ~= "table" then return false end
    local idx = cv.device:GetInt()
    if cv.device_name:GetString() ~= "" or idx < 0 then
        cookie.Set(F.MOVE_COOKIE, "1")
        return true
    end
    local dev
    for _, d in ipairs(list) do
        if d.index == idx then
            dev = d
            break
        end
    end
    if not dev then
        if not F.migrateAbsentLogged then
            F.migrateAbsentLogged = true
            log("lip sync: the saved microphone %d is not connected now - kept; its name is taken once it is there", idx)
        end
        return false
    end
    cookie.Set(F.MOVE_COOKIE, "1")
    if bass_default_entry(dev) then
        log("lip sync: the microphone is chosen by its name now: %d was Windows' default", idx)
        return true
    end
    if not dev.loopback then
        set_device_name(tostring(dev.name))
        log("lip sync: the microphone is chosen by its name now: %d '%s'%s", idx, tostring(dev.name),
            listable(dev) and "" or " (listed as not enabled - kept)")
        return true
    end
    local to
    local inner = string.match(tostring(dev.name), "%((.*)%)%s*$")
    if inner then
        local want1, want2 = F.MicNormName("Microphone (" .. inner .. ")"), F.MicNormName("Headset Microphone (" ..
            inner .. ")")
        local found, n = nil, 0
        for _, d in ipairs(list) do
            local nn = listable(d) and F.MicNormName(d.name)
            if nn and (nn == want1 or nn == want2) then
                found, n = d, n + 1
            end
        end
        if n == 1 then to = tostring(found.name) end
    end
    set_device_name(to or "")
    local nowText = to and ("'" .. to .. "'") or F.MicDefaultText(list)
    F.devNote = string.format("Your saved microphone was '%s', which records what your PC plays: %s is used now. Pick "
        .. "your microphone above.", tostring(dev.name), nowText)
    log("lip sync: microphone %d '%s' records what the PC plays - not used; %s instead", idx, tostring(dev.name), nowText)
    return true
end
-- a number typed into gsa1_lipsync_device on the console picks that device's name once (a loopback: Windows' default)
function F.PickDeviceIndex(idx)
    idx = math.floor(tonumber(idx) or -1)
    if idx < 0 then
        set_device_name("")
        return true
    end
    local list = F.MicDevicesList()
    if type(list) ~= "table" then return false end
    for _, d in ipairs(list) do
        if d.index == idx then
            if d.loopback then
                log("lip sync: microphone %d '%s' records what the PC plays - not used; Windows' default instead", idx,
                    tostring(d.name))
                set_device_name("")
            else
                set_device_name(bass_default_entry(d) and "" or tostring(d.name))
                log("lip sync: microphone %d '%s' chosen by its number", idx, tostring(d.name))
            end
            return true
        end
    end
    log("lip sync: there is no microphone %d - Windows' default instead", idx)
    set_device_name("")
    return true
end
cvars.AddChangeCallback("gsa1_lipsync_device", function(_, old, new)
    local idx = tonumber(new)
    if idx == nil then return end
    if idx == F.devCacheValue then
        F.devCacheValue = nil
        return
    end
    if tonumber(old) == idx then return end
    F.PickDeviceIndex(idx)
end, "gsa1_faces")
-- opens the device the setting names now (force: the open one again, a stalled stream - the module keeps the voice);
-- true when it is open. Log lines carry the device's name (a device name is not personal data)
function F.OpenMic(force)
    local list = F.MicDevicesList()
    if list then F.MigrateDevice(list) end
    local name = cv.device_name:GetString()
    local idx, devName, how = F.MicResolve(name, list)
    if how == "missing" then
        F.devMissing = name
        if not F.devMissingLogged[name] then
            F.devMissingLogged[name] = true
            log("lip sync: the microphone '%s' is not connected - %s instead", name, F.MicDefaultText(list))
        end
    else
        F.devMissing = nil
    end
    local ok, err, code
    if force then
        ok, err, code = gsa1.MicOpen(idx, true)
    else
        ok, err, code = gsa1.MicOpen(idx)
    end
    if not ok then
        L.micFailed, L.micFailedName, L.micFailedCode = tostring(err or "it could not be opened"), name, code
        if code == "unsupported" then
            log("lip sync: microphone %d '%s' could not be used: %s", idx, tostring(devName), L.micFailed)
        else
            log("lip sync: the microphone failed: %s", L.micFailed)
        end
        return false
    end
    L.micDevice, L.micOpenName, L.micDevName, L.micHow, L.micFailed, L.micListen = idx, name, devName, how, nil, false
    L.stallBlocks = nil
    cache_index(idx)
    local _, _, state = gsa1.MicLevel()
    local label = idx < 0 and ("Windows' default" .. (devName and (" '" .. devName .. "'") or "")) or
        string.format("%d '%s'", idx, tostring(devName))
    if force then
        log("lip sync: the microphone stopped sending sound (unplugged?); opened again: %s", label)
    else
        log("lip sync: microphone %s opened (%s)", label, tostring(state))
    end
    return true
end
-- opens (once per device name) and starts / pauses the microphone; false when it cannot be used. While the microphone
-- test or the vowel warm-up runs it always listens (lip sync never pauses it then: phoneme_plan.md 6.3)
local function mic_want(on)
    if not (gsa1.MicOpen and gsa1.MicListen) then return false end
    if F.mtest.running or (F.warm and F.warm.running) then on = true end
    if on then
        local name = cv.device_name:GetString()
        if L.micDevice == nil or L.micOpenName ~= name then
            if L.micFailed and L.micFailedName == name then return false end
            if not F.OpenMic(false) then return false end
        end
        if not L.micListen then
            local ok = gsa1.MicListen(true)
            L.micListen = ok == true
        end
        return L.micListen
    elseif L.micListen then
        gsa1.MicListen(false)
        L.micListen = false
    end
    return false
end
F.MicWant = mic_want
-- 0.9.4e: the stream stalled (MicLevel's 4th value, the blocks since open, unchanged for F.STALL_SECONDS while listening
-- with the state "on": the USB microphone was pulled out and came back) -> the name resolved again and the device opened
-- again keeping the voice, at most once every F.REOPEN_EVERY s. Every frame (Think); a module without blocks: nothing
function F.MicStallThink(now)
    if not (L.micListen and L.micDevice ~= nil and have() and gsa1.MicLevel) then
        L.stallBlocks = nil
        return
    end
    local _, _, state, blocks = gsa1.MicLevel()
    if blocks == nil or state ~= "on" then
        L.stallBlocks = nil
        return
    end
    if blocks ~= L.stallBlocks then
        L.stallBlocks, L.stallAt = blocks, now
        return
    end
    if now - L.stallAt < F.STALL_SECONDS - 1e-4 or now - (L.reopenAt or -1e9) < F.REOPEN_EVERY - 1e-4 then return end
    L.reopenAt = now
    if F.OpenMic(true) then
        local ok = gsa1.MicListen(true)
        L.micListen = ok == true
    end
    L.stallBlocks = nil
end
local SOURCE_NAMES = { gmod = "Garry's Mod voice", mic = "the microphone" }
-- 0.9.4c: the microphone failed on the device chosen NOW (a failure of another device no longer keeps Automatic on Garry's
-- Mod's level after a working device is chosen again); 0.9.4e: by the name
local function mic_failed()
    return L.micFailed ~= nil and L.micFailedName == cv.device_name:GetString()
end
F.MicFailed = mic_failed
-- the device lip sync listens to now, in words: "Microphone (X)" / "Windows default (Microphone (Y))"
function F.MicNowText()
    if L.micDevice ~= nil then
        if L.micDevice < 0 then
            return L.micDevName and ("Windows default (" .. L.micDevName .. ")") or "Windows default"
        end
        return tostring(L.micDevName or ("device " .. L.micDevice))
    end
    local idx, devName = F.MicResolve(cv.device_name:GetString(), F.devList)
    if idx < 0 then return devName and ("Windows default (" .. devName .. ")") or "Windows default" end
    return tostring(devName)
end
local function decide(use, why)
    if L.use ~= use then
        L.use = use
        log("lip sync source %s -> %s (%s)", cv.source:GetInt() == 0 and "automatic" or "chosen", SOURCE_NAMES[use], why)
    end
end

-- 0.9.4c: the module can do mouth shapes - feature "faces" 2 with the classifier and the mouth call (review R.4:
-- gsa1.FACE.MOUTH exists only in a module built with libsa1's sa1_character_face_mouth)
local function shapes_ok()
    if not have() or gsa1.MicViseme == nil or gsa1.VisemeMouth == nil or gsa1.FaceMouth == nil or
        gsa1.MicVisemeOn == nil then
        return false
    end
    local f = gsa1.FEATURES
    return type(f) == "table" and (tonumber(f.faces) or 0) >= 2 and type(gsa1.FACE) == "table" and gsa1.FACE.MOUTH ~= nil
end
F.ShapesOk = shapes_ok
-- "Faster mouth": gsa1.FACE.SAME_PAIR while the switch is on and the module has it (review R.2: only when libsa1 built
-- SA1_FACE_SAME_PAIR), else 0
local function fast_flag()
    if not cv.fast:GetBool() then return 0 end
    return const("SAME_PAIR", 0)
end
F.FastFlag = fast_flag
-- gsa1.VisemeTable(kind), once per kind per session (not per frame: it makes a table)
F.vtab = F.vtab or {}
function F.VisemeTable(kind)
    kind = tonumber(kind)
    if kind == nil or not shapes_ok() or gsa1.VisemeTable == nil then return nil end
    local t = F.vtab[kind]
    if t == nil then
        t = gsa1.VisemeTable(kind)
        if type(t) ~= "table" then t = false end
        F.vtab[kind] = t
    end
    return t or nil
end
-- 0.9.4e: the cached table of a kind after its mouths changed (gsa1.VisemeOverride; nil: every kind)
function F.VisemeTableReset(kind)
    if kind == nil then
        for k in pairs(F.vtab) do F.vtab[k] = nil end
    else
        F.vtab[tonumber(kind) or -1] = nil
    end
end
-- the loudness ladder's top: 1 with "bigger mouths", else the kind's last mouth-only key (VisemeTable's ladder_cap; 1 when
-- the module has no table: an older module's ladder is not capped)
local function ladder_cap(kind)
    if cv.big:GetBool() then return 1 end
    local t = F.VisemeTable(kind)
    return t and tonumber(t.ladder_cap) or 1
end
F.LadderCap = ladder_cap
-- gsa1.FaceLevel with the flags argument only when there is a flag (0.9.4a's calls keep their three arguments)
local function send_level(id, lv, style, flags)
    if flags ~= 0 then
        gsa1.FaceLevel(id, lv, style, flags)
    else
        gsa1.FaceLevel(id, lv, style)
    end
end

-- the classifier's settings (gsa1.MicVisemeTune; the module applies them at its next 10 ms block)
local function clamp(v, lo, hi)
    return math.min(math.max(tonumber(v) or lo, lo), hi)
end
local function steady_of()
    return math.floor(clamp(cv.steady:GetInt(), 0, 2))
end
function F.Tune(name, value)
    if not (shapes_ok() and gsa1.MicVisemeTune) then return false end
    local ok, err = gsa1.MicVisemeTune(name, value)
    if not ok then log("lip sync: the module refused %s %s: %s", tostring(name), tostring(value), tostring(err)) end
    return ok == true
end
local function tune_gate() return F.Tune("gate_min_db", clamp(cv.sgate:GetFloat(), 3, 12)) end
local function tune_adapt() return F.Tune("adapt", cv.adapt:GetBool() and 1 or 0) end
local function tune_smooth() return F.Tune("smooth", F.SHAPES_SMOOTH[steady_of()]) end
-- 0.9.4e: "Sound detection" (lipsync2_plan.md 4.3): the module's feature "faces" 3 has both classifiers, v2 (2, the
-- default) and 0.9.4c's (1), the vowel warm-up and the per-frame features; an older module hears the 0.9.4c way
local function hearing_ok()
    if not shapes_ok() or gsa1.MicVisemeTune == nil then return false end
    local f = gsa1.FEATURES
    return type(f) == "table" and (tonumber(f.faces) or 0) >= 3
end
F.HearingOk = hearing_ok
local function hearing_of()
    return math.floor(clamp(cv.hearing:GetInt(), 1, 2))
end
local function tune_engine()
    if not hearing_ok() then return false end
    return F.Tune("engine", hearing_of())
end
-- the hearing in use: 2 / 1 (an older module: 1, the 0.9.4c way)
function F.HearingTag()
    return hearing_ok() and hearing_of() or 1
end
-- the saved settings, each time the classifier is switched on (the module's own start values are 6 / 1 / 3; voice_done.txt;
-- 0.9.4e: and the engine, 2)
function F.SendTunes()
    tune_gate()
    tune_adapt()
    tune_smooth()
    tune_engine()
end
local function changed_num(old, new)
    return tonumber(old) ~= tonumber(new)
end
cvars.AddChangeCallback("gsa1_lipsync_shapes_gate", function(_, old, new)
    if changed_num(old, new) then tune_gate() end
end, "gsa1_faces")
cvars.AddChangeCallback("gsa1_lipsync_shapes_adapt", function(_, old, new)
    if changed_num(old, new) then
        -- the warm-up needs the learning (4.4): it stops
        if F.warm and F.warm.running then F.WarmStop("'Learn my voice' changed") end
        tune_adapt()
        -- learning off also forgets what the warm-up learned (lipsync2_plan.md 4.4): the page's result line goes
        if not cv.adapt:GetBool() and F.warm then F.warm.text, F.warm.result = nil, nil end
    end
end, "gsa1_faces")
cvars.AddChangeCallback("gsa1_lipsync_shapes_steady", function(_, old, new)
    if changed_num(old, new) then tune_smooth() end
end, "gsa1_faces")
cvars.AddChangeCallback("gsa1_lipsync_hearing", function(_, old, new)
    if not changed_num(old, new) then return end
    if F.warm and F.warm.running then F.WarmStop("'Sound detection' changed") end
    if tune_engine() then
        log("lip sync: sound detection %s", hearing_of() == 2 and "G-SA1 0.9.4e" or "as in 0.9.4c")
    end
end, "gsa1_faces")
-- "Forget my voice": the module's speaker number back to the adult prior (nothing of the learning is kept anywhere);
-- 0.9.4e: also what the warm-up learned (the module forgets it with the voice), so its page line goes
function F.ForgetVoice()
    local ok = F.Tune("reset_voice", 0)
    if ok then log("lip sync: the voice learning was reset (it learns again while you talk)") end
    if F.warm then
        if F.warm.running then F.WarmStop("the voice was forgotten") end
        F.warm.text, F.warm.result = nil, nil
    end
    return ok
end

-- the classifier on (style 2 with the microphone, the microphone test: review R.18, or the vowel warm-up) or off; one
-- call per change
local function vis_apply()
    if not shapes_ok() then return end
    local want = L.visWant == true or F.mtest.running or (F.warm and F.warm.running) or false
    if want == (L.visSent == true) then return end
    gsa1.MicVisemeOn(want)
    L.visSent = want
    if want then F.SendTunes() end
end
F.VisApply = vis_apply

-- 0.9.4e: the spurt line's mouths tag: "G-SA1's v2" (the module's table version), or "yours (ah, ee)" for the rows the
-- player chose for this kind (gsa1.VisemeTable's row.custom)
function F.MouthsTag(kind)
    local t = kind ~= nil and F.VisemeTable(kind) or nil
    if type(t) ~= "table" then return "G-SA1's" end
    local mine = {}
    for c = 2, F.VISEME_COUNT - 1 do
        if type(t[c]) == "table" and t[c].custom == true then mine[#mine + 1] = F.VISEME_WORDS[c] end
    end
    if #mine > 0 then return "yours (" .. table.concat(mine, ", ") .. ")" end
    return "G-SA1's v" .. tostring(tonumber(t.table_version) or 1)
end
-- the end of a talk spurt: its line of numbers (only with gsa1_lipsync_shapes_log 1, off by default: review R.10); 0.9.4e:
-- with the hearing and the mouths tags
local function end_spurt()
    local sp = L.spurt
    if cv.slog:GetBool() and sp.n and sp.n > 0 then
        local line = F.SpurtLine(sp, F.HearingTag(), F.MouthsTag(L.spurtKind))
        if line then log("%s", line) end
    end
    F.SpurtReset(sp)
end
-- talking ends: ONE -1 (0.9.4a review R.6) in the style it was sent with
local function stop_talking()
    if L.talking and L.sentId and have() then gsa1.FaceLevel(L.sentId, -1, L.sentStyle or F.STYLE_LADDER) end
    if L.talking then end_spurt() end
    L.talking, L.sentId = false, nil
    L.hold.shown, L.hold.v, L.hold.vc = nil, nil, nil
end
F.StopTalking = stop_talking
-- 0.9.4e (lipsync2_plan.md 4.8): the mouth shape tester drew this frame's mouth - lip sync ends its talk spurt WITHOUT its
-- -1 (the tester's call is the frame's last before the pair, so no -1 may close the tester's mouth) and leaves the
-- microphone as it is; talking starts again cleanly once the tester lets go
function F.LipSyncYield(C, now)
    if L.talking then
        end_spurt()
        L.talking, L.sentId = false, nil
        L.hold.shown, L.hold.v, L.hold.vc = nil, nil, nil
    end
    L.s, L.quiet = 0, 1e9
    L.last = now or SysTime()
end

-- style 2, one frame (phoneme_plan.md 4.2 step 3 and 4.4): the classifier's newest class held (F.HoldClass), the openness
-- (F.Smooth with the shapes' rise; the hang does not start while the shown class is a sound), the variant (F.Variant), the
-- character's mouth for them (gsa1.VisemeMouth) -> gsa1.FaceMouth, or for a ladder entry (f / v: a < 0) gsa1.FaceLevel with
-- VisemeMouth's w - already kept to the kind's slit (review R.1) -, capped like style 0
local function shapes_frame(C, now, dt, held)
    -- the newest classifier frame (one atomic load in the module), only while listening
    local cls, level, f1, f2, conf, seq = -1, 0, 0, 0, 0, nil
    if held and L.micListen then cls, level, f1, f2, conf, seq = gsa1.MicViseme() end
    cls, level = tonumber(cls) or -1, tonumber(level) or 0
    local H = L.hold
    local hold_s = F.SHAPES_HOLD[steady_of()]
    local shown = F.HoldClass(H, cls, seq, now, hold_s)
    local newest = H.newest
    L.cls, L.f1, L.f2, L.conf = newest, tonumber(f1) or 0, tonumber(f2) or 0, tonumber(conf) or 0
    -- the openness follows the level while the classifier hears a sound (its adaptive gate decides what is speech: noise
    -- under it holds neither the mouth nor the cutscene head)
    local raw = newest ~= F.SIL and level or 0
    L.raw = raw
    local s = F.Smooth(L, raw, dt, cv.gain:GetFloat(), cv.gate:GetFloat(), cv.release:GetFloat(), cv.hang:GetFloat(),
        shown ~= F.SIL, cv.rise:GetFloat())
    L.now = s
    if s < 0 then
        if L.talking then stop_talking() end
        return
    end
    -- a talk spurt starts with a sound
    if not L.talking and shown == F.SIL then return end
    local variant = F.Variant(H, s, raw, cv.loud:GetFloat(), now, hold_s)
    local a, b, w = gsa1.VisemeMouth(C.kind, shown, s, cv.size:GetFloat(), variant, cv.big:GetBool())
    a, b, w = tonumber(a) or 0, tonumber(b) or 0, tonumber(w) or 0
    local flags = fast_flag()
    if a >= 0 then
        gsa1.FaceMouth(C.id, a, b, w, flags)
    else
        send_level(C.id, math.min(w, ladder_cap(C.kind)), F.STYLE_LADDER, flags)
    end
    if not L.talking then
        log("lip sync: talking (the microphone, mouth shapes)")
        F.SpurtReset(L.spurt)
    end
    L.talking, L.sentId, L.sentStyle = true, C.id, F.STYLE_LADDER
    L.shown, L.variant, L.mouthA, L.mouthB, L.mouthW = shown, variant, a, b, w
    L.spurtKind = C.kind
    L.talkTime, L.levelSum, L.levelN = L.talkTime + dt, L.levelSum + s, L.levelN + 1
    if cv.slog:GetBool() then
        -- 0.9.4e (4.9, review R.3): the classifier's features of the same 10 ms frame (atomic 2, one load), only while the
        -- numbers log is on and its seq is this frame's
        if seq ~= nil and gsa1.MicVisemeFeatures then
            local rl, per, nbr, eep, _, rcls, fseq, lowr, zcr = gsa1.MicVisemeFeatures()
            if fseq ~= nil and fseq == seq then
                F.SpurtAdd(L.spurt, newest, f1, f2, s, raw, dt, rl, per, nbr, eep, rcls, lowr, zcr)
                return
            end
        end
        F.SpurtAdd(L.spurt, newest, f1, f2, s, raw, dt)
    end
end

-- one frame: the source's level, smoothed, sent while talking; one -1 when talking ends (styles 0 / 1; style 2 above)
function F.LipSyncFrame(C, now)
    local dt = L.last and math.min(math.max(now - L.last, 0), 0.25) or 0
    L.last = now
    L.frameAt = now
    local style = cv.style:GetInt()
    -- whether C has a face: asked again once a second (the numbers arrive when the disc is read)
    if C and (C.gsa1FacesAt == nil or now - C.gsa1FacesAt > 1 or now < C.gsa1FacesAt) then
        C.gsa1Faces, C.gsa1FacesAt = F.HasFaces(C.name), now
    end
    local active = cv.lipsync:GetBool() and C ~= nil and have() and C.gsa1Faces == true
    if not active then
        L.visWant = false
        vis_apply()
        mic_want(false)
        stop_talking()
        L.s, L.quiet, L.keyDown, L.mode = 0, 1e9, false, nil
        return
    end
    local ply = LocalPlayer()
    local speaking = IsValid(ply) and ply.IsSpeaking ~= nil and ply:IsSpeaking() == true
    local vol = speaking and ply.VoiceVolume ~= nil and (tonumber(ply:VoiceVolume()) or 0) or 0
    if speaking and vol > 0.01 then L.gmodSeen = now end
    local always = cv.listen:GetInt() == 1
    -- the microphone test and the vowel warm-up listen without the key (the mouth follows them then)
    local held = always or F.mtest.running or F.warm.running or F.TalkKeyDown()
    local source = cv.source:GetInt()
    if held and not L.keyDown then L.pressAt = now end
    L.keyDown = held
    local shapes = style == F.STYLE_PHONEMES and shapes_ok()
    if style == F.STYLE_PHONEMES and not shapes and not L.oldModuleLogged then
        L.oldModuleLogged = true
        log("lip sync: mouth shapes need G-SA1 module 0.9.4c (this one: %s); the mouth opens with the voice",
            tostring(gsa1.VERSION))
    end
    local use
    if source == 1 then
        use = "gmod"
    elseif source == 2 then
        use = "mic"
    elseif shapes then
        -- automatic with mouth shapes: the microphone at the first held frame (Garry's Mod gives a level, not the sound:
        -- phoneme_plan.md 4.7)
        if held then
            decide(mic_failed() and "gmod" or "mic", mic_failed() and ("the microphone failed: " .. L.micFailed) or
                "mouth shapes need the microphone's sound")
        end
        use = L.use or "mic"
    else
        -- automatic: Garry's Mod's level when it reported one in the last 0.5 s; else, 0.5 s into a press (or of an open
        -- microphone), the microphone; between: the last decision
        if now - (L.gmodSeen or -1e9) < 0.5 then
            decide("gmod", "Garry's Mod reports your voice level")
        elseif held and now - (L.pressAt or now) >= 0.5 then
            decide(mic_failed() and "gmod" or "mic", mic_failed() and ("the microphone failed: " .. L.micFailed) or
                "Garry's Mod reported no level in 0.5 s")
        end
        use = L.use or "gmod"
    end
    local micOk = false
    if use == "mic" then
        micOk = mic_want(held)
    else
        mic_want(false)
    end
    -- style 2 runs on the microphone's sound; Garry's Mod's level, a failed microphone or an older module: the mouth opens
    -- with the voice (style 0's ladder; phoneme_plan.md 4.7)
    local phon = shapes and use == "mic" and not mic_failed()
    L.visWant = phon and (held or L.visWant == true)
    vis_apply()
    local eff = phon and F.STYLE_PHONEMES or (style == F.STYLE_TALK and F.STYLE_TALK or F.STYLE_LADDER)
    -- the style or the source changed while talking: one -1, then talking starts again the new way (0.9.4a review R.6)
    local mode = eff * 10 + (use == "mic" and 1 or 0)
    if L.mode ~= nil and mode ~= L.mode and L.talking then
        stop_talking()
        L.s, L.quiet = 0, 1e9
    end
    L.mode = mode
    if eff == F.STYLE_PHONEMES then return shapes_frame(C, now, dt, held) end
    local raw = 0
    if use == "mic" and micOk then
        raw = tonumber((gsa1.MicLevel())) or 0
    else
        raw = speaking and vol or 0
    end
    L.raw = raw
    local lv = F.Smooth(L, raw, dt, cv.gain:GetFloat(), cv.gate:GetFloat(), cv.release:GetFloat(), cv.hang:GetFloat(),
        use == "gmod" and speaking)
    L.now = lv
    if lv >= 0 then
        if eff == F.STYLE_LADDER then
            -- 0.9.4c: "Faster mouth", and with bigger mouths off the ladder kept to the mouth-only keys
            send_level(C.id, math.min(lv, ladder_cap(C.kind)), F.STYLE_LADDER, fast_flag())
        else
            send_level(C.id, lv, F.STYLE_TALK, 0)
        end
        if not L.talking then log("lip sync: talking (%s)", SOURCE_NAMES[use]) end
        L.talking, L.sentId, L.sentStyle = true, C.id, eff
        L.talkTime, L.levelSum, L.levelN = L.talkTime + dt, L.levelSum + lv, L.levelN + 1
    elseif L.talking then
        stop_talking()
    end
end

-- the microphone test (phoneme_plan.md 6.3 and 7.1 with review R.18): 30 s of listening without the talk key, the
-- classifier on whatever the style, the classes counted - nothing stored; it stops at 30 s or when the page closes (the
-- page's button tells it every frame it is shown: F.MicTestSeen)
function F.MicTestStart(now)
    local T = F.mtest
    now = now or SysTime()
    if T.running then return true end
    if not shapes_ok() then
        T.note = "The microphone test needs G-SA1 module 0.9.4c."
        return false, T.note
    end
    -- 0.9.4e: the test and the vowel warm-up both listen without the key: one at a time
    if F.warm.running then
        T.note = "'Teach it my vowels' is listening: wait for it (or stop it) first."
        return false, T.note
    end
    T.running = true
    if not mic_want(true) then
        T.running = false
        T.note = "The microphone failed: " .. tostring(L.micFailed or "it could not be opened")
        return false, T.note
    end
    T.startAt, T.endsAt, T.seenAt, T.n, T.seq, T.note, T.done = now, now + F.MICTEST_SECONDS, now, 0, nil, nil, false
    for c = 0, F.VISEME_COUNT - 1 do T.counts[c] = 0 end
    vis_apply()
    log("lip sync: the 30-second microphone test started (nothing is stored)")
    return true
end
function F.MicTestStop(why)
    local T = F.mtest
    if not T.running then return false end
    T.running, T.done, T.why = false, true, why or "stopped"
    vis_apply()
    -- the microphone back to what lip sync wants: paused unless it listens now (a held talk key, a frame just now)
    local now = SysTime()
    if not (L.keyDown and L.frameAt and now - L.frameAt < 0.5 and L.use == "mic" and cv.lipsync:GetBool()) then
        mic_want(false)
    end
    log("lip sync: the microphone test ended (%s)", T.why)
    return true
end
function F.MicTestSeen(now)
    F.mtest.seenAt = now or SysTime()
end
-- every frame (the Think hook; also without a character)
function F.MicTestThink(now)
    local T = F.mtest
    if not T.running then return end
    if now >= T.endsAt then return F.MicTestStop("30 s") end
    if now - (T.seenAt or now) > 0.5 then return F.MicTestStop("the page closed") end
    if not shapes_ok() then return F.MicTestStop("the module has no mouth shapes") end
    local cls, _, _, _, _, seq = gsa1.MicViseme()
    cls = tonumber(cls) or -1
    if cls >= 0 and cls < F.VISEME_COUNT and seq ~= T.seq then
        cls = math.floor(cls)
        T.seq = seq
        T.counts[cls] = T.counts[cls] + 1
        T.n = T.n + 1
    end
end
-- "heard: ah 41, ee 12, ... (silence 140)"
function F.MicTestHeard()
    local T = F.mtest
    local words = (gsa1 and type(gsa1.VISEME) == "table" and type(gsa1.VISEME.WORDS) == "table") and gsa1.VISEME.WORDS or
        F.VISEME_WORDS
    local out = {}
    for c = 1, F.VISEME_COUNT - 1 do
        if (T.counts[c] or 0) > 0 then out[#out + 1] = string.format("%s %d", tostring(words[c]), T.counts[c]) end
    end
    return string.format("heard: %s (silence %d)", #out > 0 and table.concat(out, ", ") or "nothing", T.counts[0] or 0)
end
function F.MicTestLines(now)
    local T = F.mtest
    now = now or SysTime()
    if T.running then
        return { string.format("Listening (%d s left): say a, e, i, o, u slowly. %s", math.max(math.ceil(T.endsAt - now), 0),
            F.MicTestHeard()) }
    end
    if T.note then return { T.note } end
    if T.done then return { string.format("Last test (%s): %s. Nothing was stored.", T.why or "?", F.MicTestHeard()) } end
    return { "Listens for 30 s without the talk key: say a, e, i, o, u and see what it hears. Nothing is stored." }
end

-- 0.9.4e: the guided warm-up "Teach it my vowels" (lipsync2_plan.md 4.4 with review R.1 / R.5) --------------------------
-- about 10 s of listening without the talk key (as the microphone test does), the classifier on; at each step's start the
-- module gets the step (gsa1.MicVisemeWarmup "gap" / "ah" / "ee" / "oo" / "oh" / "done"), then the page waits for the
-- result. The module learns in its memory for this session only; the page keeps the result code and its line's text,
-- never a number of it (the owner's answer PQ7: no file, ConVar, cookie, log number or net message). One log line,
-- without numbers. With or without a character; not while the microphone test runs (and the reverse).
function F.WarmOk()
    if not have() then return false, "needs the G-SA1 module" end
    if not (hearing_ok() and gsa1.MicVisemeWarmup and gsa1.MicVisemeWarmupState) then
        return false, "needs G-SA1 module 0.9.4e"
    end
    if hearing_of() ~= 2 then return false, "needs 'Sound detection' G-SA1 0.9.4e" end
    if not cv.adapt:GetBool() then return false, "needs 'Learn my voice'" end
    return true
end
local function warm_finish(W, result, line)
    W.running, W.step = false, nil
    W.result = result
    W.text = line or F.WARM_RESULT_TEXT[result] or "Stopped"
    vis_apply()
    -- the microphone back to what lip sync wants (as after the microphone test: paused unless lip sync listens now)
    local now = SysTime()
    if not (F.mtest.running or (L.keyDown and L.frameAt and now - L.frameAt < 0.5 and L.use == "mic" and
            cv.lipsync:GetBool())) then
        mic_want(false)
    end
    log("lip sync: vowel warm-up %s (this session only)", F.WARM_LOG_WORD[result] or "stopped")
end
-- step i of F.WARM_STEPS from now: the module's call; false (the warm-up ended) when the module refuses it
local function warm_step(W, i, now)
    local st = F.WARM_STEPS[i]
    W.step, W.stepAt = i, now
    local ok, err = gsa1.MicVisemeWarmup(st.call)
    if not ok then
        if i > 1 then gsa1.MicVisemeWarmup("cancel") end
        warm_finish(W, F.WARM_CANCELLED, "Stopped: " .. tostring(err or "the module refused it"))
        return false
    end
    return true
end
function F.WarmStart(now)
    local W = F.warm
    now = now or SysTime()
    if W.running then return true end
    local ok, why = F.WarmOk()
    if not ok then
        W.text = "Teach it my vowels " .. why .. "."
        return false, W.text
    end
    if F.mtest.running then
        W.text = "The microphone test is listening: wait for it (or stop it) first."
        return false, W.text
    end
    W.running = true
    if not mic_want(true) then
        W.running = false
        W.text = "The microphone failed: " .. tostring(L.micFailed or "it could not be opened")
        return false, W.text
    end
    vis_apply()
    W.startAt, W.seenAt, W.text, W.result, W.sawPhase = now, now, nil, nil, false
    if not warm_step(W, 1, now) then return false, W.text end
    return true
end
-- the button "Stop", the page closing, the microphone failing, "Sound detection" / "Learn my voice" changing
function F.WarmStop(why)
    local W = F.warm
    if not W.running then return false end
    if have() and gsa1.MicVisemeWarmup then gsa1.MicVisemeWarmup("cancel") end
    warm_finish(W, F.WARM_CANCELLED, "Stopped (" .. tostring(why or "stopped") .. ")")
    return true
end
-- the page's button tells the warm-up every frame it is shown (as the microphone test's)
function F.WarmSeen(now)
    F.warm.seenAt = now or SysTime()
end
-- every frame (the Think hook; also without a character)
function F.WarmThink(now)
    local W = F.warm
    if not W.running then return end
    if now - (W.seenAt or now) > 0.5 then return F.WarmStop("the page closed") end
    local ok, why = F.WarmOk()
    if not ok then return F.WarmStop(why) end
    if mic_failed() or not L.micListen then return F.WarmStop("the microphone failed") end
    local phase, n1, n2, n3, _, result = gsa1.MicVisemeWarmupState()
    phase, result = tonumber(phase) or -1, tonumber(result) or 0
    if phase >= 0 then W.sawPhase = true end
    local st = F.WARM_STEPS[W.step]
    if st.call ~= "done" then
        if now - W.stepAt >= st.secs - 1e-4 then warm_step(W, W.step + 1, now) end
        return
    end
    -- "done" was sent: the result once the module applied it (phase back to -1 after this warm-up's own steps)
    if W.sawPhase and phase < 0 and (result == F.WARM_LEARNED or result == F.WARM_SHORT or result == F.WARM_UNCLEAR) then
        local line
        if result == F.WARM_SHORT then
            line = string.format("%s (heard: ah %d, ee %d, oo %d)", F.WARM_RESULT_TEXT[F.WARM_SHORT], tonumber(n1) or 0,
                tonumber(n2) or 0, tonumber(n3) or 0)
        end
        return warm_finish(W, result, line)
    end
    if now - W.stepAt >= F.WARM_RESULT_WAIT - 1e-4 then
        return warm_finish(W, F.WARM_CANCELLED, "Stopped (the module gave no result)")
    end
end
-- the bar's share (0..1)
function F.WarmProgress(now)
    local W = F.warm
    if not W.running then return 0 end
    return math.min(math.max(((now or SysTime()) - (W.startAt or 0)) / math.max(F.WARM_SECONDS, 1e-3), 0), 1)
end
-- the page's lines: the prompt, the frames heard per sound and the live sound while it runs (read from the module, not
-- kept); else the result line or the help
function F.WarmLines(now)
    local W = F.warm
    now = now or SysTime()
    if W.running then
        local st = F.WARM_STEPS[W.step] or F.WARM_STEPS[1]
        local out = { st.text }
        local _, n1, n2, n3, n4 = gsa1.MicVisemeWarmupState()
        out[2] = string.format("Heard: ah %d, ee %d, oo %d, oh %d", tonumber(n1) or 0, tonumber(n2) or 0, tonumber(n3) or 0,
            tonumber(n4) or 0)
        local cls = tonumber((gsa1.MicViseme())) or -1
        out[3] = "Sound now: " .. ((cls >= 0 and cls < F.VISEME_COUNT) and F.SHAPE_TEXT[math.floor(cls)] or "-")
        return out
    end
    if W.text then return { W.text } end
    local ok, why = F.WarmOk()
    if not ok then return { "Teach it my vowels " .. why .. "." } end
    return { "Say each sound when asked (about 10 s). Kept only until you leave the game; nothing is saved or sent." }
end
-- in words, for gsa1_lipsync_status (no number)
function F.WarmStateText()
    local W = F.warm
    if W.running then return "listening (" .. tostring((F.WARM_STEPS[W.step] or {}).step or "?") .. ")" end
    if W.result then return F.WARM_LOG_WORD[W.result] or "stopped" end
    return "not used this session"
end

-- 0.9.4e (lipsync2_plan.md 4.8): the mouth shape tester (feat/cl_mouthtest.lua) draws first; while it shows a mouth,
-- lip sync yields (no -1 from it); else lip sync's frame as in 0.9.4c
hook.Add("GSA1PreTick", "gsa1_faces", function(C)
    if not C or not have() then return end
    local now = SysTime()
    if F.TesterFrame and F.TesterFrame(C, now) then
        F.LipSyncYield(C, now)
    else
        F.LipSyncFrame(C, now)
    end
end)

-- the hotkeys and the switch key: edge-triggered, not while a menu, the cursor or the chat has the input
local function busy()
    if GSA1.InputBlocked and GSA1.InputBlocked() then return true end
    if vgui.CursorVisible() or gui.IsGameUIVisible() then return true end
    return typing()
end
F.Busy = busy
F.keyDown = F.keyDown or {}
local function key_down(code)
    return code > 0 and input and input.IsButtonDown and input.IsButtonDown(code) == true or false
end
function F.Hotkey(i, C)
    local name = cv.hotkey_anim[i]:GetString()
    if name == "" or not C then return end
    if F.held and F.held.id == C.id and F.held.name == name then
        F.Stop(C)
        return
    end
    local ok, err = F.Play(C, name, "hotkey " .. i)
    if not ok and GSA1.Chat and err then GSA1.Chat("face hotkey %d: %s", i, err) end
end
local function keys_think()
    local b = busy()
    local k = cv.event_key:GetInt()
    local d = (not b) and key_down(k)
    if d and not F.keyDown.event then F.Toggle("the key") end
    F.keyDown.event = d
    local C = GSA1.Char
    for i = 1, F.HOTKEYS do
        local hk = cv.hotkey[i]:GetInt()
        local down = (not b) and hk > 0 and key_down(hk)
        if down and not F.keyDown[i] then F.Hotkey(i, C) end
        F.keyDown[i] = down
    end
    -- 0.9.4c: the microphone test runs with or without a character; 0.9.4e: so do the vowel warm-up and the stall check
    local now = SysTime()
    F.MicTestThink(now)
    F.WarmThink(now)
    F.MicStallThink(now)
end
hook.Add("Think", "gsa1_faces", GSA1.Guard and GSA1.Guard("Faces", keys_think) or keys_think)

-- 6. the characters ---------------------------------------------------------------------------------------------------------
hook.Add("GSA1CharacterCreated", "gsa1_faces", function(C, how)
    if not C or not have() then return end
    if not F.loggedModule then
        F.loggedModule = true
        local function cvs(n)
            local c = GetConVar(n)
            return c and c:GetString() or "?"
        end
        log("module faces %s / emote %s; voice_enable %s, voice_loopback %s, sv_voiceenable %s; GMod %s %s",
            tostring(gsa1.FEATURES and gsa1.FEATURES.faces or "-"), tostring(gsa1.FEATURES and gsa1.FEATURES.emote or "-"),
            cvs("voice_enable"), cvs("voice_loopback"), cvs("sv_voiceenable"), tostring(VERSIONSTR), tostring(BRANCH))
    end
    local no = F.NoFaceText(C.name)
    if no then
        log("%s %s: %s", C.title or "?", how or "created", no)
        return
    end
    local mask, exact = F.Letters(C.name)
    log("%s %s: %d face animations%s (event faces %s)", C.title or "?", how or "created", F.CountLetters(mask),
        exact and "" or " expected", cv.event:GetBool() and "on" or "off")
    -- review R.6: the switch's mode only while it is on (a new world starts with the regular face)
    if cv.event:GetBool() then F.ApplyMode(C, how or "created") end
end)
-- the character goes while talking: its one -1 (review R.6); 0.9.4c: the classifier and the microphone rest until the
-- next character talks (a character without a face then gets no Mic* call at all)
hook.Add("GSA1CharacterLeaving", "gsa1_faces", function(C)
    if C and L.talking and L.sentId == C.id and have() then
        F.StopTalking()
    end
    if F.held and C and F.held.id == C.id then F.held = nil end
    if have() then
        L.visWant = false
        F.VisApply()
        F.MicWant(false)
    end
    L.mode, L.keyDown = nil, false
end)
hook.Add("ShutDown", "gsa1_faces", function()
    if (F.counts.played or 0) > 0 or (L.talkTime or 0) > 0 then
        log("summary: %d face animations played, %d refused; lip sync: talking %.0f s, source %s, mean level %.2f",
            F.counts.played, F.counts.refused, L.talkTime or 0, SOURCE_NAMES[L.use or "gmod"],
            (L.levelN or 0) > 0 and L.levelSum / L.levelN or 0)
    end
    if have() and gsa1.MicClose then gsa1.MicClose() end
end)

-- 7. console -------------------------------------------------------------------------------------------------------------
local function say(fmt, ...)
    if GSA1.Chat then GSA1.Chat(fmt, ...) else print(string.format(fmt, ...)) end
end
concommand.Add("gsa1_face_toggle", function() F.Toggle("the command") end, nil,
    "G-SA1: event faces (the cutscene face) on / off")
concommand.Add("gsa1_face_play", function(_, _, args, argstr)
    local name = string.Trim(argstr or "")
    local ok, err = F.Play(GSA1.Char, name, "the command")
    if not ok then say("face animation \"%s\": %s", name, tostring(err)) end
end, nil, "G-SA1: play a face animation of the Faces page by its name")
concommand.Add("gsa1_face_stop", function() F.Stop(GSA1.Char) end, nil, "G-SA1: stop the face animation")
concommand.Add("gsa1_face_script", function(_, _, args)
    local C = GSA1.Char
    if not (C and have() and gsa1.FaceScript) then return say("no character with a face") end
    local no = F.NoFaceText(C.name)
    if no then return say("%s", no) end
    local ok, err = gsa1.FaceScript(C.id, tostring(args and args[1] or ""), const("NOW", 1))
    if not ok then say("face script: %s", tostring(err)) else log("face script %s (the command)", tostring(args[1])) end
end, nil, "G-SA1: the game's face script (letters A-Z a-e, e.g. CDE), as the game's events send it")

-- 8. the Faces page (Q -> Options -> G-SA1 -> Faces) -------------------------------------------------------------------------
function F.MeterLines()
    local out = {}
    local ply = LocalPlayer()
    local speaking = IsValid(ply) and ply.IsSpeaking ~= nil and ply:IsSpeaking() == true
    local vol = IsValid(ply) and ply.VoiceVolume ~= nil and (tonumber(ply:VoiceVolume()) or 0) or 0
    out[#out + 1] = string.format("Garry's Mod voice: speaking %s, level %.2f", speaking and "yes" or "no", vol)
    if have() and gsa1.MicLevel then
        local lv, _, state = gsa1.MicLevel()
        -- 0.9.4e: the device by its name
        local dev = L.micDevice ~= nil and F.MicNowText() or nil
        if state == "on" then
            out[#out + 1] = string.format("Microphone: %.2f (%s)", tonumber(lv) or 0, dev or "?")
        elseif L.micFailed then
            out[#out + 1] = "Microphone: failed: " .. L.micFailed
        elseif state == "paused" then
            out[#out + 1] = string.format("Microphone: paused (%s; it listens while you hold the talk key)", dev or "?")
        else
            out[#out + 1] = "Microphone: " .. tostring(state) .. " (it opens when it is needed)"
        end
    end
    out[#out + 1] = string.format("Lip sync now: %s (source: %s)", L.talking and string.format("%.2f", L.now or 0) or "off",
        cv.source:GetInt() == 1 and "Garry's Mod voice" or (cv.source:GetInt() == 2 and "the microphone" or
        ("automatic -> " .. SOURCE_NAMES[L.use or "gmod"])))
    -- 0.9.4c: the style in use, the last sound, the voice learning (shown, never written)
    local st = cv.style:GetInt()
    local styleText = st == F.STYLE_PHONEMES and (F.ShapesOk() and "mouth shapes from your voice" or
        "mouth shapes (need module 0.9.4c: opens with the voice)") or (st == F.STYLE_TALK and "the game's talking animations"
        or "opens with your voice")
    local mouthLine = "Mouth: " .. styleText
    if st == F.STYLE_PHONEMES and F.ShapesOk() then
        mouthLine = mouthLine .. string.format("; last sound %s; %s", L.cls ~= nil and F.SHAPE_TEXT[L.cls] or "-",
            F.VoiceText())
    end
    out[#out + 1] = mouthLine
    return out
end

-- 0.9.4c: "voice 6.83 (learned)" - the module's speaker number for the page and the console (never logged or saved:
-- the owner's answer PQ7)
function F.VoiceText()
    if not cv.adapt:GetBool() then return "voice learning off" end
    if not (F.ShapesOk() and gsa1.MicVisemeVoice) then return "voice -" end
    -- 0.9.4e: the fifth value says the vowel warm-up taught it this session (shown, never written)
    local g, frames, _, _, warmed = gsa1.MicVisemeVoice()
    g, frames = tonumber(g) or 0, tonumber(frames) or 0
    return string.format("voice %.2f (%s%s)", g, frames > 0 and "learned" or "not learned yet",
        (tonumber(warmed) or 0) ~= 0 and ", vowels taught" or "")
end
-- "Sound now: AH (open) - level 0.72 - F1 720 F2 1240 - voice 6.83 (learned)" (phoneme_plan.md 7.1); F.soundCls = the class
-- the page's nine words light up (the page asks at most 10 times a second: review R.6 / R.18)
function F.SoundNowLines()
    F.soundCls = -1
    if not have() then return { "Sound now: -" } end
    if not F.ShapesOk() then return { "Sound now: needs G-SA1 module 0.9.4c" } end
    if not L.visSent then
        return { "Sound now: off (it listens with \"Mouth shapes from your voice\" while you hold the talk key, or during "
            .. "the microphone test)" }
    end
    local cls, level, f1, f2 = gsa1.MicViseme()
    cls, level, f1, f2 = tonumber(cls) or -1, tonumber(level) or 0, tonumber(f1) or 0, tonumber(f2) or 0
    if cls < 0 or cls >= F.VISEME_COUNT then
        return { string.format("Sound now: - (hold your talk key) - %s", F.VoiceText()) }
    end
    cls = math.floor(cls)
    F.soundCls = cls
    return { string.format("Sound now: %s - level %.2f - F1 %d F2 %d - %s", F.SHAPE_TEXT[cls], level, f1, f2,
        F.VoiceText()) }
end
-- the level next to the "Loud speech from" slider
function F.LoudLines()
    local lv = 0
    if F.ShapesOk() and L.visSent then
        local _, l = gsa1.MicViseme()
        lv = tonumber(l) or 0
    end
    return { string.format("Your level now: %.2f (loud mouths from %.2f)", lv, cv.loud:GetFloat()) }
end
-- the device lip sync listens to, in words
local function device_text()
    -- 0.9.4e: by its name ("Windows default (Microphone (X))")
    return F.MicNowText()
end
-- phoneme_plan.md 4.7: which way the mouth goes in style 2, and why it only opens with the voice (nil in styles 0 / 1)
function F.ShapesStatus(C)
    if cv.style:GetInt() ~= F.STYLE_PHONEMES or not have() then return nil end
    if not F.ShapesOk() then return "Mouth shapes need G-SA1 module 0.9.4c" end
    C = C or GSA1.Char
    local no = C and F.NoFaceText(C.name)
    if no then return no end
    local out = {}
    if C and tonumber(C.kind) == 7 then
        out[#out + 1] = "Big's face has one mouth shape: it opens more or less with each sound"
    end
    if cv.source:GetInt() == 1 then
        out[#out + 1] = "Mouth shapes need G-SA1's own microphone listening (Voice from: Automatic or The microphone); "
            .. "now the mouth only opens with the voice"
    elseif F.MicFailed() then
        out[#out + 1] = "The microphone failed: " .. tostring(L.micFailed) .. "; the mouth only opens with the voice"
    else
        out[#out + 1] = "Mouth shapes: from your microphone (" .. device_text() .. ")"
    end
    return table.concat(out, "\n")
end
-- "This character: ah 4>16 (30 %), eh / ee 0>4, ..." from gsa1.VisemeTable (the character, else the Character setting)
function F.CharacterShapesLines()
    local C = GSA1.Char
    local name = C and C.name or (GSA1.cv and GSA1.cv.character and GSA1.cv.character:GetString()) or "sonic"
    local kind = GSA1.KindByName(name)
    local no = F.NoFaceText(name)
    if no then return { "This character: " .. no } end
    if not F.ShapesOk() then return { "This character: (mouth shapes need G-SA1 module 0.9.4c)" } end
    local text = F.TableText(F.VisemeTable(kind), kind)
    return { string.format("This character (%s): %s", F.Title(name), text or "?") }
end
function F.StatusLines()
    local out = {}
    if not have() then
        out[1] = GSA1.MissingFeatureText and GSA1.MissingFeatureText(F.NEEDS) or "the module has no faces"
        return out
    end
    local C = GSA1.Char
    if C then
        local no = F.NoFaceText(C.name)
        if no then
            out[#out + 1] = no
        else
            local mode, shown, _, _, _, letter = gsa1.FaceState(C.id)
            out[#out + 1] = string.format("%s: event faces %s%s; the cutscene face %s; playing %s", C.title or "?",
                cv.event:GetBool() and "on" or "off", (tonumber(mode) or 0) >= 256 and " (cutscene pace)" or "",
                shown and "shows" or "does not show", (tonumber(letter) or -1) >= 0 and ("'" .. tostring(F.Letter(letter))
                .. "' " .. F.Label(F.Letter(letter))) or ((tonumber(letter) or -1) == -2 and "a held face / lip sync" or
                "nothing"))
        end
    else
        out[#out + 1] = "no character"
    end
    local shapes = F.ShapesStatus(C)
    if shapes then out[#out + 1] = shapes end
    out[#out + 1] = cv.summary:GetString() .. ((F.badLines or 0) > 0 and string.format(" (%d bad lines in the file were "
        .. "skipped)", F.badLines) or "")
    for _, n in ipairs(F.loadNotes or {}) do out[#out + 1] = n end
    return out
end
concommand.Add("gsa1_lipsync_status", function()
    for _, l in ipairs(F.MeterLines()) do print("[G-SA1] " .. l) end
    local shapes = F.ShapesStatus()
    if shapes then print("[G-SA1] " .. shapes) end
    -- 0.9.4e: the device's name, the hearing, the warm-up's state in words (never a learned number)
    print("[G-SA1] Microphone: " .. F.MicNowText() .. (cv.device_name:GetString() ~= "" and (" (chosen: '" ..
        cv.device_name:GetString() .. "')") or " (chosen: Windows default)"))
    print("[G-SA1] Sound detection: " .. (F.HearingTag() == 2 and "G-SA1 0.9.4e" or "as in 0.9.4c") ..
        "; Teach it my vowels: " .. F.WarmStateText())
end, nil, "G-SA1: what lip sync hears now (the style, the source, the last sound, the voice, the microphone, the "
    .. "sound detection)")
concommand.Add("gsa1_lipsync_forget_voice", function()
    if not F.ForgetVoice() then print("[G-SA1] lip sync: the voice learning needs G-SA1 module 0.9.4c") end
end, nil, "G-SA1: lip sync forgets how high or low your voice is (it learns it again while you talk; nothing is kept)")

-- the face animation maker's state (pure functions; the page calls them)
F.ed = F.ed or { entry = "sonic", name = "", base = nil, entries = {}, back = F.BACK_DEFAULT, hold_last = false, sel = 0,
                 note = "" }
function F.EdNew(E)
    E.name, E.base, E.entries, E.back, E.hold_last, E.sel, E.note = "", nil, {}, F.BACK_DEFAULT, false, 0, ""
end
function F.EdLoad(E, name)
    local a = F.Find(name)
    if not a then return false end
    local c = F.CopyAnim(a)
    E.name, E.base, E.entries, E.back, E.hold_last, E.sel, E.note = c.name, c.name, c.entries, c.back, c.hold_last,
        #c.entries > 0 and 1 or 0, ""
    return true
end
function F.EdAnim(E)
    return { name = E.name ~= "" and E.name or "(unsaved)", entries = E.entries, back = E.back, hold_last = E.hold_last }
end
function F.EdAppend(E, letter)
    if not F.Index(letter) then return false end
    local max = F.MaxEntries(E.back, E.hold_last)
    if #E.entries >= max then
        E.note = string.format("at most %d entries%s", max, max < F.SEQ_MAX and " while it blends back to neutral" or "")
        return false
    end
    E.entries[#E.entries + 1] = { letter, 0, 0 }
    E.sel, E.note = #E.entries, ""
    return true
end
function F.EdRemove(E, i)
    i = tonumber(i) or E.sel
    if not E.entries[i] then return false end
    table.remove(E.entries, i)
    E.sel = math.min(i, #E.entries)
    return true
end
function F.EdMove(E, i, d)
    i = tonumber(i) or E.sel
    local j = i + d
    if not E.entries[i] or not E.entries[j] then return false end
    E.entries[i], E.entries[j] = E.entries[j], E.entries[i]
    E.sel = j
    return true
end
local function clampi(v, lo, hi)
    v = math.floor((tonumber(v) or 0) + 0.5)
    return math.min(math.max(v, lo), hi)
end
function F.EdSet(E, i, enter, hold)
    local e = E.entries[tonumber(i) or E.sel]
    if not e then return false end
    if enter ~= nil then e[2] = clampi(enter, 0, F.ENTER_MAX) end
    if hold ~= nil then e[3] = clampi(hold, 0, F.HOLD_MAX) end
    return true
end
function F.EdSetBack(E, n)
    n = clampi(n, 0, F.BACK_MAX)
    if n > 0 and not E.hold_last and #E.entries >= F.SEQ_MAX then
        E.back, E.note = 0, string.format("%d entries: no room for the blend back to neutral (%d at most with it)",
            #E.entries, F.SEQ_MAX - 1)
        return false
    end
    E.back = n
    return true
end
function F.EdSetKeep(E, on)
    E.hold_last = on == true
    if not E.hold_last and E.back > 0 and #E.entries >= F.SEQ_MAX then
        E.back, E.note = 0, string.format("%d entries: the blend back to neutral is off (%d at most with it)", #E.entries,
            F.SEQ_MAX - 1)
    end
    return true
end
-- an entry's frames: enter (0 = the game's first step) + the game's other steps + hold
function F.EntryFrames(e, info)
    if not info then return nil end
    local i = F.Index(e[1])
    local steps, first = tonumber(info.steps and info.steps[i]), tonumber(info.first and info.first[i])
    if not steps or not first then return nil end
    local enter = e[2] > 0 and e[2] or first
    return enter + (steps - first) + e[3], enter, steps - first
end
local function secs(n)
    return string.format("%.2f s", n / F.FPS)
end
function F.EdEntryText(E, i, info)
    local e = E.entries[i]
    if not e then return "" end
    local total, enter, plays = F.EntryFrames(e, info)
    if not total then return string.format("enter %s + hold %d (the game's frames: the disc is not read yet)",
        e[2] > 0 and tostring(e[2]) or "the game's", e[3]) end
    return string.format("enter %d + plays %d + hold %d = %d frames (%s)", enter, plays, e[3], total, secs(total))
end
function F.EdTotal(E, info)
    local n = 0
    for _, e in ipairs(E.entries) do
        local t = F.EntryFrames(e, info)
        if not t then return nil, "? frames (the disc is not read yet)" end
        n = n + t
    end
    if E.back > 0 and not E.hold_last and #E.entries > 0 then n = n + E.back end
    return n, string.format("%d frames (%s)%s", n, secs(n), E.hold_last and ", then the last face stays" or "")
end
-- mode "save" (the edited one, or a new one), "new" (save as new), "rename"; true | false, why
function F.EdSave(E, mode)
    local name, why = F.CleanName(E.name)
    if not name then E.note = why return false, why end
    if #E.entries == 0 then E.note = "add an expression first (double-click one)" return false, E.note end
    if #E.entries > F.MaxEntries(E.back, E.hold_last) then
        E.note = string.format("at most %d entries", F.MaxEntries(E.back, E.hold_last))
        return false, E.note
    end
    local lib = F.Library()
    local cur = E.base and F.Find(E.base) or nil
    local change = {}
    if mode == "rename" then
        if not cur then E.note = "pick a saved face animation to rename" return false, E.note end
        if find_ci(name, cur) then E.note = "a face animation with that name exists" return false, E.note end
        local old = cur.name
        cur.name = name
        change.renamed = { [old] = name }
    elseif mode == "new" or not cur then
        if find_ci(name) then E.note = "a face animation with that name exists (use Save, or another name)" return false,
            E.note end
        cur = { name = name }
        lib[#lib + 1] = cur
        change.saved = { [name] = true }
    else
        local other = find_ci(name, cur)
        if other then E.note = "another face animation has that name" return false, E.note end
        if cur.name ~= name then change.renamed = { [cur.name] = name } end
        cur.name = name
        change.saved = { [name] = true }
    end
    local c = F.CopyAnim(F.EdAnim(E))
    cur.entries, cur.back, cur.hold_last = c.entries, c.back, c.hold_last
    E.name, E.base = name, name
    F.SaveLibrary()
    E.note = "saved"
    log("face animation %s %s: %s, back %d, keep %d", name, mode == "rename" and "renamed" or "saved",
        F.EntriesText(cur.entries), cur.back, cur.hold_last and 1 or 0)
    changed(change)
    return true
end
function F.EdDelete(E)
    local cur, i = nil, nil
    if E.base then cur, i = find_ci(E.base) end
    if not cur then E.note = "pick a saved face animation to delete" return false, E.note end
    table.remove(F.Library(), i)
    F.SaveLibrary()
    log("face animation %s deleted", cur.name)
    changed({ deleted = { [cur.name] = true } })
    F.EdNew(E)
    E.note = "deleted"
    return true
end
function F.EdPreview(E, C)
    C = C or GSA1.Char
    if not C then E.note = "spawn a character to preview" return false, E.note end
    if #E.entries == 0 then E.note = "add an expression first" return false, E.note end
    local ok, err = F.PlayAnim(C, F.EdAnim(E), "preview")
    E.note = ok and ("playing on " .. (C.title or "?")) or tostring(err)
    return ok == true, err
end

-- page helpers
local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    combo.gsa1ConVar = cvname
    for _, c in ipairs(choices) do combo:AddChoice(c[2], tostring(c[1])) end
    combo.OnSelect = function(_, _, _, data) RunConsoleCommand(cvname, tostring(data)) end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local c = GetConVar(cvname)
        local v = c and c:GetString() or ""
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        for _, ch in ipairs(choices) do
            -- 0.9.4e: names (the microphone) compare as text; numbers also as numbers ("2" = "2.0")
            if tostring(ch[1]) == v or (type(ch[1]) == "number" and tonumber(ch[1]) == tonumber(v)) then
                self:SetText(ch[2])
                return
            end
        end
        self:SetText(v)
    end
    return combo
end
F.PageChoiceCombo = choice_combo
local function live_label(panel, lines_fn, every)
    local lbl = panel:Help("...")
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + (every or 0.5)
        local text = table.concat(lines_fn(), "\n")
        if text ~= self.gsa1Text then
            self.gsa1Text = text
            self:SetText(text)
            self:InvalidateLayout(true)
            local parent = self:GetParent()
            if IsValid(parent) then parent:InvalidateLayout() end
        end
    end
    return lbl
end
F.PageLiveLabel = live_label
local function binder(panel, cvname, label)
    if label then panel:Help(label) end
    local b = vgui.Create("DBinder", panel)
    if b.SetConVar then b:SetConVar(cvname) end
    if b.SetTall then b:SetTall(26) end
    panel:AddItem(b)
    return b
end
local function button_row(panel, defs)
    local row = vgui.Create("DPanel")
    row:SetTall(24)
    if row.SetPaintBackground then row:SetPaintBackground(false) end
    local buttons = {}
    for i, d in ipairs(defs) do
        local b = vgui.Create("DButton", row)
        b:SetText(d[1])
        b.DoClick = d[2]
        b.gsa1Name = d[1]
        buttons[i] = b
    end
    row.PerformLayout = function(self, w, h)
        local n, gap = #buttons, 4
        local bw = math.floor((w - gap * (n - 1)) / n)
        for i, b in ipairs(buttons) do
            b:SetPos((i - 1) * (bw + gap), 0)
            b:SetSize(i == n and (w - (n - 1) * (bw + gap)) or bw, h)
        end
    end
    panel:AddItem(row)
    F.pageButtons = F.pageButtons or {}
    for _, b in ipairs(buttons) do F.pageButtons[b.gsa1Name] = b end
    return row, buttons
end
F.PageButtonRow = button_row

-- the maker: character, expressions, the animation's entries, its settings, the library
local function maker(panel)
    local E = F.ed
    local C = GSA1.Char
    E.entry = C and C.name or (GSA1.cv and GSA1.cv.character and GSA1.cv.character:GetString()) or E.entry or "sonic"
    if not GSA1.KindByName(E.entry) then E.entry = "sonic" end
    local ui = {}
    F.ui = ui
    local cc = panel:ComboBox("Character")
    for _, d in ipairs(GSA1.CHARACTERS) do cc:AddChoice(d.title, d.name, d.name == E.entry) end
    ui.character = cc
    ui.why = panel:Help("")
    local ex = vgui.Create("DListView")
    ex:SetMultiSelect(false)
    ex:SetTall(230)
    ex:AddColumn("#"):SetFixedWidth(26)
    ex:AddColumn("Letter"):SetFixedWidth(40)
    ex:AddColumn("Expression")
    ex:AddColumn("Frames"):SetFixedWidth(50)
    ex.gsa1Role = "expressions"
    panel:AddItem(ex)
    ui.expressions = ex
    panel:ControlHelp("Double-click an expression to add it to the animation below. Frames: 60 = 1 second (the game's own "
        .. "face timing). Enter: how long the change into the expression takes (0 = the game's). Hold: how long its last "
        .. "face stays.")
    local lc = panel:ComboBox("Face animation")
    ui.library = lc
    local el = vgui.Create("DListView")
    el:SetMultiSelect(false)
    el:SetTall(170)
    el:AddColumn("#"):SetFixedWidth(26)
    el:AddColumn("Expression")
    el:AddColumn("Enter"):SetFixedWidth(44)
    el:AddColumn("Plays"):SetFixedWidth(44)
    el:AddColumn("Hold"):SetFixedWidth(44)
    el:AddColumn("Total"):SetFixedWidth(52)
    el.gsa1Role = "entries"
    panel:AddItem(el)
    ui.entries = el
    local refresh
    button_row(panel, {
        { "Remove", function() F.EdRemove(E) refresh() end },
        { "Up", function() F.EdMove(E, E.sel, -1) refresh() end },
        { "Down", function() F.EdMove(E, E.sel, 1) refresh() end },
        { "New", function() F.EdNew(E) refresh() end },
    })
    ui.enter = panel:NumSlider("Enter (frames; 0 = the game's)", nil, 0, F.ENTER_MAX, 0)
    ui.hold = panel:NumSlider("Hold (frames)", nil, 0, F.HOLD_MAX, 0)
    ui.entryLine = panel:Help("")
    ui.back = panel:NumSlider("Back to neutral over N frames", nil, 0, F.BACK_MAX, 0)
    ui.keep = panel:CheckBox("Keep the last face (until the next face command)")
    panel:ControlHelp("At the end the face blends back to neutral over these frames (0 = it jumps back, like the game), "
        .. "unless the last face is kept; a hotkey's second press lets a kept face go.")
    ui.name = panel:TextEntry("Name")
    button_row(panel, {
        { "Save", function() F.EdSave(E, "save") refresh() end },
        { "Save as new", function() F.EdSave(E, "new") refresh() end },
        { "Rename", function() F.EdSave(E, "rename") refresh() end },
        { "Delete", function() F.EdDelete(E) refresh() end },
        { "Preview", function() F.EdPreview(E) refresh() end },
    })
    ui.total = panel:Help("")
    local syncing = false
    refresh = function()
        syncing = true
        local info = F.Info(GSA1.KindByName(E.entry) or 0)
        local no = F.NoFaceText(E.entry)
        local mask, exact = F.Letters(E.entry)
        -- the expressions this entry can show (rebuilt when the entry or its numbers change)
        local exKey = string.format("%s %s %s", E.entry, tostring(mask), tostring(info ~= nil))
        if ui.exKey == exKey then
            -- unchanged
        elseif no then
            ui.exKey = exKey
            ex:Clear()
            ex:AddLine("", "", no, "")
        else
            ui.exKey = exKey
            ex:Clear()
            for i = 0, 30 do
                if band(mask, bit.lshift(1, i)) ~= 0 then
                    local f = F.FACES[i]
                    local line = ex:AddLine(tostring(i), f[1], f[2], info and tostring(info.steps[i] or "?") or "?")
                    line.gsa1Letter = f[1]
                    if line.SetTooltip then line:SetTooltip(f[3]) end
                end
            end
        end
        -- the animation's entries
        el:Clear()
        for i, e in ipairs(E.entries) do
            local total, enter, plays = F.EntryFrames(e, info)
            local line = el:AddLine(tostring(i), e[1] .. " " .. F.Label(e[1]), enter and tostring(enter) or
                (e[2] > 0 and tostring(e[2]) or "game"), plays and tostring(plays) or "?", tostring(e[3]),
                total and tostring(total) or "?")
            line.gsa1Index = i
            if i == E.sel and el.SelectItem then el:SelectItem(line) end
        end
        local cur = E.entries[E.sel]
        ui.enter:SetValue(cur and cur[2] or 0)
        ui.hold:SetValue(cur and cur[3] or 0)
        ui.entryLine:SetText(cur and string.format("Entry %d: %s", E.sel, F.EdEntryText(E, E.sel, info)) or
            "Select an entry to set its frames.")
        ui.back:SetValue(E.back)
        if ui.keep.SetChecked then ui.keep:SetChecked(E.hold_last) end
        if ui.name.SetValue then ui.name:SetValue(E.name) end
        -- the library
        lc:Clear()
        lc:AddChoice("(a new face animation)", "", E.base == nil)
        for _, a in ipairs(F.Library()) do lc:AddChoice(a.name, a.name, a.name == E.base) end
        local _, total = F.EdTotal(E, info)
        local cant = ""
        if not no and #E.entries > 0 then
            local ok, why = F.CanShow(F.EdAnim(E), E.entry)
            if not ok and why then cant = why end
        end
        ui.why:SetText(no or (exact and string.format("%s can show %d of the 31 expressions.", F.Title(E.entry),
            F.CountLetters(mask)) or "The disc is not read yet: the list may change."))
        ui.total:SetText(string.format("Total: %s%s%s", total, cant ~= "" and ("\n" .. cant) or "",
            E.note ~= "" and ("\n" .. E.note) or ""))
        syncing = false
    end
    F.Refresh = refresh
    cc.OnSelect = function(_, _, _, data)
        E.entry = data
        refresh()
    end
    ex.DoDoubleClick = function(_, _, line)
        if line and line.gsa1Letter then
            F.EdAppend(E, line.gsa1Letter)
            refresh()
        end
    end
    el.OnRowSelected = function(_, _, line)
        if line and line.gsa1Index and not syncing then
            E.sel = line.gsa1Index
            refresh()
        end
    end
    lc.OnSelect = function(_, _, _, data)
        if syncing then return end
        if data == "" or data == nil then F.EdNew(E) else F.EdLoad(E, data) end
        refresh()
    end
    ui.enter.OnValueChanged = function(_, v)
        if syncing then return end
        F.EdSet(E, E.sel, v, nil)
        refresh()
    end
    ui.hold.OnValueChanged = function(_, v)
        if syncing then return end
        F.EdSet(E, E.sel, nil, v)
        refresh()
    end
    ui.back.OnValueChanged = function(_, v)
        if syncing then return end
        F.EdSetBack(E, v)
        refresh()
    end
    ui.keep.OnChange = function(_, v)
        if syncing then return end
        F.EdSetKeep(E, v == true)
        refresh()
    end
    ui.name.OnChange = function(self)
        if syncing then return end
        E.name = self.GetValue and self:GetValue() or E.name
    end
    refresh()
end

-- the hotkeys: ten rows of a key and a face animation
local function hotkeys(panel)
    local sub = vgui.Create("DForm", panel)
    if sub.SetName then sub:SetName("Face hotkeys") end
    if sub.SetExpanded then sub:SetExpanded(false) end
    panel:AddItem(sub)
    sub:ControlHelp("A press plays its face animation; a face animation that keeps its last face is let go by a second "
        .. "press. Not while a menu or the chat is open.")
    for i = 1, F.HOTKEYS do
        binder(sub, "gsa1_face_hotkey_" .. i, "Key " .. i)
        local combo = sub:ComboBox("Face animation " .. i)
        combo.gsa1ConVar = "gsa1_face_hotkey_anim_" .. i
        local function fill(self)
            self:Clear()
            self:AddChoice("(none)", "")
            for _, a in ipairs(F.Library()) do self:AddChoice(a.name, a.name) end
            self.gsa1Ver = F.libVersion
        end
        fill(combo)
        combo.OnSelect = function(_, _, _, data) RunConsoleCommand("gsa1_face_hotkey_anim_" .. i, tostring(data or "")) end
        -- follows the library (a save, rename or delete) and the setting (also a change from the console)
        local baseThink = combo.Think
        combo.Think = function(self)
            if baseThink then baseThink(self) end
            if self.gsa1Ver ~= F.libVersion then
                fill(self)
                self.gsa1Value = nil
            end
            local v = cv.hotkey_anim[i]:GetString()
            if v ~= self.gsa1Value then
                self.gsa1Value = v
                self:SetText(v == "" and "(none)" or v)
            end
        end
    end
    return sub
end

local function meter(panel)
    local bar = vgui.Create("DPanel")
    bar:SetTall(14)
    bar.Paint = function(self, w, h)
        surface.SetDrawColor(30, 30, 30, 255)
        surface.DrawRect(0, 0, w, h)
        local v = L.talking and (L.now or 0) or 0
        surface.SetDrawColor(80, 200, 90, 255)
        surface.DrawRect(0, 0, math.floor(w * math.min(math.max(v, 0), 1)), h)
    end
    panel:AddItem(bar)
    return bar
end

-- 0.9.4c: the nine kinds of sound, the one heard now lit (F.soundCls, set by the "Sound now" line at most 10 times a second)
local function words_of()
    local v = gsa1 and gsa1.VISEME
    return (type(v) == "table" and type(v.WORDS) == "table") and v.WORDS or F.VISEME_WORDS
end
local function sound_words(panel)
    local bar = vgui.Create("DPanel")
    bar:SetTall(18)
    bar.gsa1Role = "soundwords"
    local words = words_of()
    local total = 0
    for c = 0, F.VISEME_COUNT - 1 do total = total + #tostring(words[c]) + 2 end
    bar.Paint = function(self, w, h)
        surface.SetDrawColor(30, 30, 30, 255)
        surface.DrawRect(0, 0, w, h)
        local x = 0
        for c = 0, F.VISEME_COUNT - 1 do
            local word = tostring(words[c])
            local cw = w * (#word + 2) / total
            local lit = F.soundCls == c
            if lit then
                surface.SetDrawColor(80, 200, 90, 255)
                surface.DrawRect(math.floor(x), 0, math.ceil(cw), h)
            end
            draw.SimpleText(word, "DermaDefault", math.floor(x + cw / 2), math.floor(h / 2), lit and color_black or
                color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            x = x + cw
        end
    end
    panel:AddItem(bar)
    return bar
end
-- the button "Test the microphone (30 s)" with its countdown; while it is shown it tells the test the page is open
local function mic_test_button(panel)
    local b = vgui.Create("DButton")
    b:SetText("Test the microphone (30 s)")
    if b.SetTall then b:SetTall(24) end
    b.gsa1Role = "mictest"
    b.DoClick = function()
        if F.mtest.running then F.MicTestStop("stopped") else F.MicTestStart(SysTime()) end
    end
    local baseThink = b.Think
    b.Think = function(self)
        if baseThink then baseThink(self) end
        local T = F.mtest
        local now = SysTime()
        local secs = -1
        if T.running then
            F.MicTestSeen(now)
            secs = math.max(math.ceil(T.endsAt - now), 0)
        end
        if secs ~= self.gsa1Secs then
            self.gsa1Secs = secs
            self:SetText(secs >= 0 and string.format("Listening: %d s (press to stop)", secs) or
                "Test the microphone (30 s)")
        end
    end
    panel:AddItem(b)
    F.ui = F.ui or {}
    F.ui.micTest = b
    return b
end
-- 0.9.4e: the button "Teach it my vowels" with its countdown (while it is shown it tells the warm-up the page is open),
-- greyed with engine 1, "Learn my voice" off or an older module; its progress bar
local function warm_button(panel)
    local b = vgui.Create("DButton")
    b:SetText("Teach it my vowels (about 10 s, this session only)")
    if b.SetTall then b:SetTall(24) end
    b.gsa1Role = "warmup"
    b.DoClick = function()
        if F.warm.running then F.WarmStop("stopped") else F.WarmStart(SysTime()) end
    end
    local baseThink = b.Think
    b.Think = function(self)
        if baseThink then baseThink(self) end
        local now = SysTime()
        local secs = -1
        if F.warm.running then
            F.WarmSeen(now)
            secs = math.max(math.ceil((F.warm.startAt or now) + F.WARM_SECONDS - now), 0)
        end
        local usable = F.warm.running or F.WarmOk()
        if usable ~= self.gsa1Usable then
            self.gsa1Usable = usable
            if self.SetEnabled then self:SetEnabled(usable and true or false) end
        end
        if secs ~= self.gsa1Secs then
            self.gsa1Secs = secs
            self:SetText(secs >= 0 and string.format("Listening: %d s (press to stop)", secs) or
                "Teach it my vowels (about 10 s, this session only)")
        end
    end
    panel:AddItem(b)
    F.ui = F.ui or {}
    F.ui.warmup = b
    local bar = vgui.Create("DPanel")
    bar:SetTall(8)
    bar.gsa1Role = "warmbar"
    bar.Paint = function(self, w, h)
        if not F.warm.running then return end
        surface.SetDrawColor(30, 30, 30, 255)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(80, 160, 230, 255)
        surface.DrawRect(0, 0, math.floor(w * F.WarmProgress(SysTime())), h)
    end
    panel:AddItem(bar)
    return b
end
-- 0.9.4e: the "Microphone" combo by name (lipsync2_plan.md 4.5 / 7.1 with review R.6 / R.7): Windows default, then every
-- enabled device that is not a loopback nor BASS's own "Default"; Windows' "Stereo Mix"-like inputs with a note; a saved
-- name that is not connected stays shown
function F.MicChoices()
    local choices = { { "", "Windows default" } }
    local name = cv.device_name:GetString()
    local seen, left = false, 0
    for _, d in ipairs(type(F.devList) == "table" and F.devList or {}) do
        if listable(d) then
            local n = tostring(d.name)
            choices[#choices + 1] = { n, n .. (F.MicPlaysName(n) and " (records what your PC plays)" or "") }
            if n == name then seen = true end
        elseif type(d) == "table" and d.loopback == true and d.enabled ~= false then
            left = left + 1
        end
    end
    if name ~= "" and not seen then choices[#choices + 1] = { name, name .. " (not connected)" } end
    return choices, left
end
-- "Listening to: Microphone (X)" / "Listening to: Windows default (Microphone (Y))", the loopbacks left out, the notes
function F.MicListeningLines()
    local out = {}
    if F.devListError then out[#out + 1] = "Microphones: " .. F.devListError end
    if mic_failed() then
        out[#out + 1] = "The microphone could not be used: " .. tostring(L.micFailed)
    else
        out[#out + 1] = "Listening to: " .. F.MicNowText()
    end
    local _, left = F.MicChoices()
    if left > 0 then
        out[#out + 1] = string.format("%d device%s that record%s what your PC plays %s not listed", left, left == 1 and ""
            or "s", left == 1 and "s" or "", left == 1 and "is" or "are")
    end
    if F.devNote then out[#out + 1] = F.devNote end
    if F.devMissing and F.devMissing == cv.device_name:GetString() then
        out[#out + 1] = string.format("Your microphone '%s' is not connected: Windows' default is used", F.devMissing)
    end
    return out
end
local function mic_rows(panel)
    if have() then
        F.MicDevicesList()
        F.MigrateDevice(F.devList)
    end
    local choices = F.MicChoices()
    local combo = choice_combo(panel, "Microphone", "gsa1_lipsync_device_name", choices)
    combo.gsa1Role = "microphone"
    panel:ControlHelp("Pick your microphone by its name. Speaker devices (what your PC plays) are not listed. Voice "
        .. "changers (virtual microphones) pass their effects on, which changes the vowels G-SA1 hears: pick the real "
        .. "microphone.")
    live_label(panel, F.MicListeningLines, 0.5).gsa1Role = "listening"
end
-- the Lip sync section's rows of phoneme_plan.md 7.1, in its order after "Microphone"
local function shapes_rows(panel)
    local ok = F.ShapesOk()
    local mouth = choice_combo(panel, "Mouth", "gsa1_lipsync_style", { { 0, "Opens with your voice (like Garry's Mod)" },
        { 1, "The game's talking animations" },
        { 2, ok and "Mouth shapes from your voice" or "Mouth shapes from your voice (needs module 0.9.4c)" } })
    mouth.gsa1Role = "mouth"
    panel:ControlHelp("Mouth shapes: G-SA1 hears which kind of sound you make (only while you hold the talk key) and "
        .. "gives your character the matching mouth from the game's own faces. Needs 'Voice from' Automatic or The "
        .. "microphone; with Garry's Mod's voice chat the mouth only opens with the voice.")
    if not ok then
        panel:ControlHelp("Mouth shapes need G-SA1 module 0.9.4c: with this module the mouth opens with your voice.")
    end
    local fast = panel:CheckBox("Faster mouth (shown in the same game frame)", "gsa1_lipsync_fast")
    fast.gsa1Role = "fast"
    if const("SAME_PAIR", nil) == nil then
        if fast.SetEnabled then fast:SetEnabled(false) end
        panel:ControlHelp("Faster mouth: not available in this module.")
    else
        panel:ControlHelp("The mouth appears 1/30 s sooner: the game's own face blend is done just before the frame is "
            .. "drawn instead of just after. Off: exactly the game's order.")
    end
    panel:NumSlider("Loudness changes the mouth's size", "gsa1_lipsync_shapes_size", 0, 1, 2)
    panel:ControlHelp("0: every sound always shows its full mouth. 1: quiet talking gives small mouths. (Sonic's and "
        .. "Knuckles' mouths never go below 80 %: their lips open as a thin slit first.)")
    panel:CheckBox("Bigger mouths for loud speech (the eyes or brows move a little)", "gsa1_lipsync_shapes_big")
    panel:ControlHelp("Sonic's laugh mouth, Knuckles' shout, Tails' big 'ah'. Off: only the game's own talking mouths "
        .. "(smaller; Sonic's eyes still move a little on some, as in the game's talking). Also limits 'Opens with your "
        .. "voice'.")
    panel:NumSlider("Loud speech from (the meter's level)", "gsa1_lipsync_shapes_loud", 0.5, 1, 2)
    live_label(panel, F.LoudLines, 0.1)
    panel:ControlHelp("Above this level the loud mouths are used. Headsets differ: watch the level in the 'Sound now' "
        .. "line while you shout and set this just under it.")
    choice_combo(panel, "Mouth shape changes", "gsa1_lipsync_shapes_steady", { { 0, "Quick" }, { 1, "Steadier" },
        { 2, "Instant" } })
    panel:ControlHelp("Quick: a shape stays at least one game frame. Steadier: two (calmer in fast speech, 1/30 s "
        .. "later). Instant: every change (twitchy).")
    panel:NumSlider("Ignore background noise below (dB)", "gsa1_lipsync_shapes_gate", 3, 12, 1)
    panel:ControlHelp("How far above the room's own noise a sound must be to count as speech. Raise it if the mouth moves "
        .. "on keyboard clicks or a fan.")
    -- 0.9.4e (lipsync2_plan.md 7.1): "Sound detection" and "Teach it my vowels"
    local hok = F.HearingOk()
    local hearing = choice_combo(panel, "Sound detection", "gsa1_lipsync_hearing", { { 2, hok and "G-SA1 0.9.4e (better)"
        or "G-SA1 0.9.4e (needs module 0.9.4e)" }, { 1, "As in 0.9.4c" } })
    hearing.gsa1Role = "hearing"
    if not hok then
        if hearing.SetEnabled then hearing:SetEnabled(false) end
        panel:ControlHelp("Sound detection needs G-SA1 module 0.9.4e: this module hears the 0.9.4c way.")
    end
    panel:ControlHelp("0.9.4e: vowels in the middle of words keep the mouth open, 'ee' only for a real 'ee', 's' told from "
        .. "'f'. As in 0.9.4c: the old way, to compare.")
    warm_button(panel)
    live_label(panel, F.WarmLines, 0.25).gsa1Role = "warmline"
    panel:ControlHelp("Say a long 'ahh', 'eee', 'ooo' (as in 'you') and 'ohh' (as in 'go') when asked. It helps most with "
        .. "'oo' and 'oh' (British voices). Kept only until you leave the game; nothing is saved or sent. 'Forget my "
        .. "voice' forgets it too.")
    panel:CheckBox("Learn my voice (how high or low it is; nothing is saved)", "gsa1_lipsync_shapes_adapt")
    panel:Button("Forget my voice", "gsa1_lipsync_forget_voice")
    panel:ControlHelp("It adjusts within 1-2 seconds of talking, every session, in memory only (nothing is saved or "
        .. "sent). Forget it if someone else talks into your microphone. (Also what 'Teach it my vowels' learned.)")
    panel:NumSlider("Mouth opens in (s)", "gsa1_lipsync_shapes_rise", 0.005, 0.06, 3)
    panel:ControlHelp("With mouth shapes the kind of sound decides when the mouth changes; this only smooths its size.")
    panel:CheckBox("Log my voice's numbers for tuning (never the sound)", "gsa1_lipsync_shapes_log")
    panel:ControlHelp("One line per sentence in the session log: how often each kind of sound came, the averages of two "
        .. "numbers per vowel, how loud and, per kind of sound, how loud, voiced and hissy it was. Nothing else.")
    local now = live_label(panel, F.SoundNowLines, 0.1)
    now.gsa1Role = "soundnow"
    sound_words(panel)
    live_label(panel, F.CharacterShapesLines, 1).gsa1Role = "character"
    -- 0.9.4e: the mouth shape tester and your mouths (feat/cl_mouthtest.lua; lipsync2_plan.md 4.8 / 7.2)
    if F.TesterRows then F.TesterRows(panel) end
    mic_test_button(panel)
    live_label(panel, F.MicTestLines, 0.25).gsa1Role = "mictestline"
    live_label(panel, function() return { F.ShapesStatus() or "" } end, 0.5).gsa1Role = "shapesstatus"
end

function F.BuildPage(panel)
    panel:Help("Faces: the game's own cutscene face (the \"event head\") on your character - a switch, face animations "
        .. "you make from the game's 31 expressions, and lip sync.")
    local C = GSA1.Char
    if C and F.NoFaceText(C.name) then panel:ControlHelp(F.NoFaceText(C.name) .. ": nothing on this page changes him.") end
    panel:Help("Event faces")
    panel:CheckBox("Event faces (the cutscene face) instead of the regular face", "gsa1_face_event")
    panel:ControlHelp("On: the character always wears its cutscene head and blinks like in the game's cutscenes (a hit then "
        .. "shows no hurt face, as in the game's events). Off: the regular face; face animations and talking show the "
        .. "cutscene head while they play. Applies at once.")
    binder(panel, "gsa1_face_event_key", "Switch key")
    panel:Button("No key (or bind gsa1_face_toggle)", "gsa1_face_event_key", "0")
    panel:CheckBox("Cutscene speed for blinks and the game's expressions", "gsa1_face_pace")
    panel:ControlHelp("The game's cutscenes play faces at half speed. Your own enter / hold frames are never changed.")
    panel:Help("Face animations")
    maker(panel)
    local sl = live_label(panel, function() return { "Saved: " .. cv.summary:GetString() } end, 1)
    sl.gsa1ConVar = "gsa1_face_summary"
    hotkeys(panel)
    panel:Help("Lip sync")
    panel:CheckBox("Lip sync: the mouth moves when you talk", "gsa1_lipsync")
    panel:ControlHelp("Like Garry's Mod's own mouths. Only while you hold your voice chat key unless you choose 'always'.")
    choice_combo(panel, "Voice from", "gsa1_lipsync_source", { { 0, "Automatic" }, { 1, "Garry's Mod voice chat" },
        { 2, "The microphone (G-SA1 listens itself)" } })
    panel:ControlHelp("Automatic uses Garry's Mod's voice level when it reports yours, else G-SA1 reads the microphone "
        .. "itself (only the loudness; nothing is recorded or sent).")
    choice_combo(panel, "Listen", "gsa1_lipsync_listen", { { 0, "Only while I hold the voice chat key" },
        { 1, "Always (open microphone)" } })
    binder(panel, "gsa1_lipsync_key", "Talk key (none = your voice chat key)")
    panel:Button("Use my voice chat key", "gsa1_lipsync_key", "0")
    -- 0.9.4e: the microphone by its name (gsa1_lipsync_device is G-SA1's cache of the number: no control of its own)
    mic_rows(panel)
    shapes_rows(panel)
    panel:NumSlider("Sensitivity", "gsa1_lipsync_gain", 0.5, 8, 2)
    panel:ControlHelp("2 is Garry's Mod's own.")
    panel:NumSlider("Ignore sounds quieter than", "gsa1_lipsync_gate", 0, 0.5, 2)
    panel:ControlHelp("Raise it if the mouth moves with background noise.")
    panel:NumSlider("Mouth closes in (s)", "gsa1_lipsync_release", 0.03, 0.5, 2)
    panel:NumSlider("Back to the regular face after (s) of silence", "gsa1_lipsync_hang", 0.2, 3, 2)
    meter(panel)
    live_label(panel, F.MeterLines, 0.1)
    panel:Help("Status")
    live_label(panel, F.StatusLines)
end

GSA1.AddMenuPage(285, "faces", "Faces", F.BuildPage, F.NEEDS)
