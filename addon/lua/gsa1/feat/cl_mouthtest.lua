-- G-SA1 0.9.4e: the mouth shape tester and "Your mouths" (Q menu > Options > G-SA1 > Faces > Lip sync; sadc docs/research/
-- lipsync2_plan.md 4.7, 4.8, 6.3, 7.2 with its Review R.4 / R.8 / R.10; lipsync2_show.md 6 and 7). The owner saw wrong
-- mouths in 0.9.4c; here he sees every mouth of his character on demand and can pick his own.
--   * The tester: eight sound buttons (m b p, ah, eh, ee, oh, oo, s z sh, f v th). Point at one = the character shows that
--     mouth (exactly what talking draws: gsa1.VisemeMouth with "Show as" normal / quiet / loud and the page's size and
--     "Bigger mouths"); click = it stays F.TESTER_KEEP (20) s, also with the menu closed; "Play all" shows each for half a
--     second; Stop. Per frame F.TesterFrame (called first by cl_faces.lua's GSA1PreTick hook) sends ONE FaceMouth (or, for
--     a ladder entry, FaceLevel) and lip sync yields that frame (no -1 from it); when the tester lets go - F.TESTER_LETGO
--     (0.15) s after nothing is pointed at, the keep's end, Stop, another face animation - it sends ONE FaceLevel(id, -1,
--     0); when it lets go because the talk key went down it sends nothing and lip sync draws in the same frame. Idle it
--     costs one comparison per frame (no table, string or closure). It never opens the microphone, touches only the face
--     block through the host-only calls lip sync uses, and has no network code.
--   * Your mouths (feature "faces" 3: gsa1.VisemeOverride): per character and sound (and "Show as" variant) one of that
--     character's own mouths from a list (data: feat/sh_mouths.lua F.MOUTH_CHOICES; pointing at a line shows it) or a
--     pair of its face keys with a weight; "Back to G-SA1's", "Reset <character>", "Reset every character" (asks), "Use my
--     mouths" (gsa1_lipsync_shapes_custom). Saved in garrysmod/data/gsa1/mouth_shapes.txt (key numbers and weights only;
--     the grammar is sh_mouths.lua's F.MouthParseFile / F.MouthSerializeFile, the module parses again and decides),
--     written only by those actions, the whole file each time; lines that cannot be used stay in the file and are listed.
--     At load and whenever the module is (re)opened every face kind gets its line's spec or "" (review R.8: a module that
--     outlived a Lua state keeps no stale override).
--   * The close-up (gsa1_mouth_closeup): a 256 x 192 picture from the panel's Paint with render.RenderView, the camera 40 HU
--     in front of the mouth (gsa1.VisemeTable(kind).mouth_at, else 0.85 x the character's height); only while the panel
--     is painted, the box is ticked and a character with a face exists; in first person a text line instead (review R.10:
--     the body is not drawn there); an error -> a text line, one log line, no further close-up this session. It runs no
--     tick, no Think and no gsa1.Render (cl_render.lua draws the character's last batches; cl_render.lua is not changed);
--     the session log's "views" line counts it as a second main view.
-- Console (extras; the page has every control): gsa1_mouth_show <sound> [quiet|loud] (shows it 3 s), gsa1_mouth_reset
-- [<character>|all].
GSA1 = GSA1 or {}
local F = GSA1.Faces
if not (F and F.LipSyncFrame and F.cv) then error("gsa1/feat/cl_faces.lua did not load: the mouth shape tester needs it") end
local cv = F.cv
local log = F.LogLine or function() end

local FACE_KINDS = { 0, 2, 3, 5, 7 }
local TITLES = { [0] = "Sonic", [2] = "Tails", [3] = "Knuckles", [5] = "Amy", [7] = "Big" }
local NAMES = { "AA", "EH", "EE", "OH", "OO", "SS", "FV" }           -- classes 2..8, the file's order
local CLASS_OF = { MBP = 1, AA = 2, EH = 3, EE = 4, OH = 5, OO = 6, SS = 7, FV = 8 }
local VARIANT_KEY = { [0] = "", [1] = ".quiet", [2] = ".loud" }
local VARIANT_OF = { quiet = 1, loud = 2 }

-- the module has the tester's calls (0.9.4c's VisemeMouth / FaceMouth) / your mouths (0.9.4e's VisemeOverride)
local function tester_ok()
    return F.ShapesOk and F.ShapesOk() and gsa1.VisemeMouth ~= nil and gsa1.FaceMouth ~= nil
end
F.TesterOk = tester_ok
local function mouths_ok()
    return tester_ok() and gsa1.VisemeOverride ~= nil and F.MouthParseFile ~= nil and F.MouthSerializeFile ~= nil and
        F.MouthSpec ~= nil
end
F.MouthsOk = mouths_ok
local function mouth_file()
    return F.MOUTH_FILE or "gsa1/mouth_shapes.txt"
end
local function title_of(kind)
    return TITLES[tonumber(kind) or -1] or ("kind " .. tostring(kind))
end
-- "ah", "s z sh"; with the variant "ah (loud)"
local function key_words(key)
    local snd, var = string.match(tostring(key), "^(%u%u)%.?(%l*)$")
    local c = CLASS_OF[snd or ""]
    local w = c and F.VISEME_WORDS[c] or tostring(key)
    if var and var ~= "" then w = w .. " (" .. var .. ")" end
    return w
end

-- 1. the tester ---------------------------------------------------------------------------------------------------------
-- T: point / pointMouth / pointAt (the pointer: a sound button, a list line), play (Play all's start), pin / pinMouth /
-- pinUntil / pinShowAs (the kept mouth), drawing / drawId (the tester sent this character a mouth last frame), active
-- (any of these: the per-frame test), showAs (0 normal, 1 quiet, 2 loud), the last drawn numbers for the page's line
local T = F.tester or {}
F.tester = T
T.showAs = T.showAs or 0
T.logged = T.logged or {}
T.active, T.drawing, T.drawId = false, false, nil
T.point, T.pointMouth, T.pointAt, T.play, T.pin, T.pinMouth, T.pinUntil = nil, nil, nil, nil, nil, nil, nil
T.pvPoint, T.pvPin = T.pvPoint or {}, T.pvPin or {}
T.nowCls, T.nowA, T.nowB, T.nowW = nil, 0, 0, 0

-- a MOUTH of the file's grammar -> out = { a, b, w, how = "fixed" / "scales" / "ladder" } (the page's own reading, to
-- show a line before it is chosen; the module parses what is saved)
local function parse_mouth(text, out)
    text = tostring(text or "")
    local body, how = string.match(text, "^(.-):(%a+)$")
    if not body then body, how = text, "fixed" end
    if how ~= "fixed" and how ~= "scales" then return nil end
    if body == "ladder" then
        out.a, out.b, out.w, out.how = -1, -1, 1, "ladder"
        return out
    end
    local lw = string.match(body, "^ladder@([%d%.]+)$")
    if lw then
        out.a, out.b, out.w, out.how = -1, -1, math.min(math.max(tonumber(lw) or 1, 0), 1), "ladder"
        return out
    end
    local k = string.match(body, "^(%d+)$")
    if k then
        out.a, out.b, out.w, out.how = 0, tonumber(k), 1, how
        return out
    end
    local a, b, w = string.match(body, "^(%d+)>(%d+)@([%d%.]+)$")
    if not a then return nil end
    out.a, out.b, out.w, out.how = tonumber(a), tonumber(b), math.min(math.max(tonumber(w) or 0, 0), 1), how
    return out
end
F.TesterParseMouth = parse_mouth

local function send_level(id, lv, flags)
    if flags ~= 0 then
        gsa1.FaceLevel(id, lv, 0, flags)
    else
        gsa1.FaceLevel(id, lv, 0)
    end
end
local function pointing(now)
    return T.pointAt ~= nil and now - T.pointAt < F.TESTER_LETGO
end
local function show_as(i)
    return F.TESTER_SHOWAS[i or T.showAs] or F.TESTER_SHOWAS[0]
end
-- ends everything the tester shows; silent: no -1 (the talk key took over, the character left)
local function clear(silent)
    if T.drawing and T.drawId and not silent and F.Have() then gsa1.FaceLevel(T.drawId, -1, 0) end
    T.drawing, T.drawId, T.active = false, nil, false
    T.point, T.pointMouth, T.pointAt, T.play, T.pin, T.pinMouth, T.pinUntil, T.pinShowAs = nil, nil, nil, nil, nil, nil,
        nil, nil
    T.nowCls = nil
end
-- the once-per-session log line of a sound looked at: "mouth tester: Sonic ah 7>16@0.45 (G-SA1's, normal)"
local function log_once(C, cls, variant, a, b, w)
    local key = (tonumber(C.kind) or 0) * 100 + cls * 10 + variant
    if T.logged[key] then return end
    T.logged[key] = true
    local t = F.VisemeTable(C.kind)
    local mine = type(t) == "table" and type(t[cls]) == "table" and t[cls].custom == true and cv.custom:GetBool()
    local m = a < 0 and string.format("the voice slit (at most %.2f)", w) or string.format("%d>%d@%.2f", a, b, w)
    log("mouth tester: %s %s %s (%s, %s)", title_of(C.kind), F.VISEME_WORDS[cls] or "?", m, mine and "yours" or "G-SA1's",
        show_as(variant == 0 and 0 or (variant == 1 and 1 or 2)).name)
end
-- one sound, as talking draws it
local function draw_class(C, cls, sa)
    local a, b, w = gsa1.VisemeMouth(C.kind, cls, sa.s, cv.size:GetFloat(), sa.variant, cv.big:GetBool())
    a, b, w = tonumber(a) or 0, tonumber(b) or 0, tonumber(w) or 0
    local flags = F.FastFlag()
    if a >= 0 then
        gsa1.FaceMouth(C.id, a, b, w, flags)
    else
        w = math.min(w, F.LadderCap(C.kind))
        send_level(C.id, w, flags)
    end
    T.nowCls, T.nowA, T.nowB, T.nowW, T.nowMouth = cls, a, b, w, false
    log_once(C, cls, sa.variant, a, b, w)
end
-- a mouth of a list (not chosen yet), with the page's openness rules: scaling entries with "Show as"'s openness
local function draw_mouth(C, m, sa)
    local flags = F.FastFlag()
    if m.how == "ladder" then
        local lv = math.min(sa.s, m.w, F.LadderCap(C.kind))
        send_level(C.id, lv, flags)
        T.nowA, T.nowB, T.nowW = -1, -1, lv
    else
        local w = m.w
        if m.how == "scales" then
            local t = F.VisemeTable(C.kind)
            local floor = type(t) == "table" and tonumber(t.floor) or 0
            local f = math.max(1 - cv.size:GetFloat(), floor)
            w = w * (f + (1 - f) * sa.s)
        end
        gsa1.FaceMouth(C.id, m.a, m.b, w, flags)
        T.nowA, T.nowB, T.nowW = m.a, m.b, w
    end
    T.nowMouth = true
end

-- every frame from cl_faces.lua's GSA1PreTick hook, before lip sync: true when the tester sent this frame's mouth
function F.TesterFrame(C, now)
    if not T.active then return false end
    if not (C and C.id) then return false end
    -- the character changed under the tester (its leaving hook ends it: this is the guard)
    if T.drawId ~= nil and T.drawId ~= C.id then
        clear(true)
        return false
    end
    if C.gsa1FacesAt == nil or now - C.gsa1FacesAt > 1 or now < C.gsa1FacesAt then
        C.gsa1Faces, C.gsa1FacesAt = F.HasFaces(C.name), now
    end
    if C.gsa1Faces ~= true or not tester_ok() then
        clear(true)
        return false
    end
    -- talking wins over a kept mouth and Play all: the talk key going down ends them, no -1, lip sync draws this frame
    -- (with "Listen: always" there is no talk key: the keep ends by itself)
    if (T.pin or T.play) and cv.listen:GetInt() ~= 1 then
        local down = F.TalkKeyDown()
        if down and not T.keyWas then
            T.pin, T.pinMouth, T.play = nil, nil, nil
            if not pointing(now) then
                T.keyWas = down
                clear(true)
                return false
            end
        end
        T.keyWas = down
    end
    -- what to show: the pointer > Play all > the kept mouth
    if pointing(now) then
        if T.pointMouth then
            draw_mouth(C, T.pointMouth, show_as())
        else
            draw_class(C, T.point, show_as())
        end
    else
        local cls = nil
        if T.play then
            local i = math.floor((now - T.play) / F.TESTER_PLAY + 1e-6) + 1
            if i <= #F.TESTER_SOUNDS then cls = F.TESTER_SOUNDS[i] else T.play = nil end
        end
        if cls then
            draw_class(C, cls, show_as())
        elseif T.pin and now < (T.pinUntil or 0) then
            if T.pinMouth then
                draw_mouth(C, T.pinMouth, show_as(T.pinShowAs))
            else
                draw_class(C, T.pin, show_as(T.pinShowAs))
            end
        else
            -- nothing to show: let go (ONE -1, as lip sync)
            clear(false)
            return false
        end
    end
    T.drawing, T.drawId = true, C.id
    return true
end

-- the page's pointer (a sound button's Think while it is hovered, or its OnCursorEntered)
function F.TesterPoint(cls, now)
    T.point, T.pointMouth, T.pointAt, T.active = cls, nil, now or SysTime(), true
end
-- the pointer on a mouth of a list (its text: parsed once while it stays the same)
function F.TesterPointMouth(text, now)
    if T.pvPointText ~= text then
        T.pvPointText = text
        T.pvPointOk = parse_mouth(text, T.pvPoint) ~= nil
    end
    if not T.pvPointOk then return end
    T.pointMouth, T.pointAt, T.active = T.pvPoint, now or SysTime(), true
end
-- click: keep that sound F.TESTER_KEEP s (a second click lets go)
function F.TesterClick(cls, now)
    now = now or SysTime()
    if T.pin == cls and not T.pinMouth and now < (T.pinUntil or 0) then
        T.pin, T.pinUntil = nil, nil
        -- the pointer still on the button keeps showing it (point = show); else let go now
        if not T.play and not pointing(now) then clear(false) end
        return false
    end
    T.pin, T.pinMouth, T.pinUntil, T.pinShowAs, T.play, T.active = cls, nil, now + F.TESTER_KEEP, nil, nil, true
    T.keyWas = F.TalkKeyDown()
    return true
end
-- keep a mouth of a list (the custom pair's "Show") F.TESTER_KEEP s
function F.TesterKeepMouth(text, now)
    now = now or SysTime()
    if not parse_mouth(text, T.pvPin) then return false end
    T.pin, T.pinMouth, T.pinUntil, T.pinShowAs, T.play, T.active = 0, T.pvPin, now + F.TESTER_KEEP, nil, nil, true
    T.keyWas = F.TalkKeyDown()
    return true
end
-- gsa1_mouth_show: one sound for seconds, as a variant
function F.TesterShow(cls, variant, seconds, now)
    now = now or SysTime()
    T.pin, T.pinMouth, T.pinUntil, T.pinShowAs, T.play, T.active = cls, nil, now + (seconds or F.TESTER_SHOW), variant,
        nil, true
    T.keyWas = F.TalkKeyDown()
end
function F.TesterPlayAll(now)
    now = now or SysTime()
    T.play, T.pin, T.pinMouth, T.point, T.pointMouth, T.pointAt, T.active = now, nil, nil, nil, nil, nil, true
    T.keyWas = F.TalkKeyDown()
end
-- ends the tester now (Stop, a face animation, the character leaving: silent); true when it showed something
function F.TesterStop(why, silent)
    if not T.active and not T.drawing then return false end
    clear(silent)
    T.stopWhy = why
    return true
end
function F.TesterShowAs(i)
    i = tonumber(i) or 0
    if F.TESTER_SHOWAS[i] then T.showAs = i end
end

-- 2. your mouths (feature "faces" 3) ------------------------------------------------------------------------------------
-- F.mouthMap[kind] = { items = { ["AA"] = "7>16@0.45", ["AA.loud"] = ... } } (sh_mouths.lua's F.MouthParseFile);
-- F.mouthBad: the file's lines this G-SA1 cannot read (kept in the file); F.mouthRefused[kind]: the module's reason
F.mouthMap, F.mouthBad, F.mouthRefused = F.mouthMap or {}, F.mouthBad or {}, F.mouthRefused or {}
F.mouthVersion = F.mouthVersion or 0
local function face_kind(kind)
    return TITLES[tonumber(kind) or -1] ~= nil
end
function F.MouthLoad()
    local text = file.Read(mouth_file(), "DATA")
    local map, bad = {}, {}
    if type(text) == "string" and F.MouthParseFile then map, bad = F.MouthParseFile(text) end
    F.mouthMap, F.mouthBad = type(map) == "table" and map or {}, type(bad) == "table" and bad or {}
    F.mouthVersion = F.mouthVersion + 1
    return F.mouthMap
end
-- the spec the module gets for a kind now ("" = G-SA1's table: no line, or "Use my mouths" off)
local function spec_of(kind)
    local e = F.mouthMap[kind]
    if not (cv.custom:GetBool() and type(e) == "table" and type(e.items) == "table" and next(e.items) ~= nil) then
        return ""
    end
    return F.MouthSpec(e.items, kind) or ""
end
-- gsa1.VisemeOverride(kind, its spec); a refused line clears the kind (no stale override); true | false, why
function F.MouthApply(kind)
    local spec = spec_of(kind)
    local ok, err = gsa1.VisemeOverride(kind, spec)
    if not ok and spec ~= "" then
        F.mouthRefused[kind] = tostring(err)
        gsa1.VisemeOverride(kind, "")
    else
        F.mouthRefused[kind] = nil
    end
    if F.VisemeTableReset then F.VisemeTableReset(kind) end
    F.mouthVersion = F.mouthVersion + 1
    return ok == true or spec == "", err, spec
end
-- "Sonic - ah, ee; Amy - s z sh" (the summary ConVar, the load's log line)
function F.MouthSummaryText()
    local out = {}
    for _, kind in ipairs(FACE_KINDS) do
        local e = F.mouthMap[kind]
        if type(e) == "table" and type(e.items) == "table" and next(e.items) ~= nil then
            local words = {}
            for c = 2, 8 do
                local n = NAMES[c - 1]
                if e.items[n] or e.items[n .. ".quiet"] or e.items[n .. ".loud"] then words[#words + 1] = F.VISEME_WORDS[c] end
            end
            out[#out + 1] = title_of(kind) .. " - " .. table.concat(words, ", ")
        end
    end
    return table.concat(out, "; ")
end
function F.MouthSummaryUpdate()
    local s = F.MouthSummaryText()
    if s ~= "" and not cv.custom:GetBool() then s = s .. " (off)" end
    if cv.msummary:GetString() ~= s then cv.msummary:SetString(s) end
    return s
end
-- every face kind gets its line's spec or "" (load, module (re)open: review R.8); the refusals logged
function F.MouthApplyAll()
    for _, kind in ipairs(FACE_KINDS) do
        local ok, err, spec = F.MouthApply(kind)
        if not ok and spec ~= "" then
            log("mouth shapes: %s's saved mouths were not used: %s", title_of(kind), tostring(err))
        end
    end
    F.MouthSummaryUpdate()
end
-- once per loaded module: read the file, apply every kind (the character's creation, the page, the console)
function F.MouthEnsure()
    if not mouths_ok() then return false end
    if F.mouthApplied == gsa1 then return true end
    F.mouthApplied = gsa1
    F.MouthLoad()
    F.MouthApplyAll()
    local s = F.MouthSummaryText()
    if s ~= "" then log("mouth shapes: your mouths - %s%s", (string.gsub(s, " %- ", ": ")), cv.custom:GetBool() and "" or
        " (not used: 'Use my mouths' is off)") end
    if #F.mouthBad > 0 then
        log("mouth shapes: %d line%s of %s could not be read and stay%s in the file", #F.mouthBad, #F.mouthBad == 1 and ""
            or "s", mouth_file(), #F.mouthBad == 1 and "s" or "")
    end
    return true
end
-- the whole file, from the map (sh_mouths.lua keeps the lines that could not be read at its end, untouched)
function F.MouthSave()
    local text = F.MouthSerializeFile(F.mouthMap, F.mouthBad)
    if file.CreateDir then file.CreateDir("gsa1") end
    file.Write(mouth_file(), text)
end
local function mouth_words(mouth, kind)
    if F.MouthText then
        local ok, t = pcall(F.MouthText, mouth, kind)
        if ok and type(t) == "string" then return t end
    end
    return tostring(mouth)
end
-- Use: sound key ("AA", "AA.loud") of kind = mouth; true | false, why
function F.MouthUse(kind, key, mouth)
    if not mouths_ok() then return false, "needs G-SA1 module 0.9.4e" end
    kind = tonumber(kind)
    if not face_kind(kind) then return false, "this character has no face in the game" end
    local map = F.mouthMap
    local e = map[kind]
    local fresh = e == nil
    if fresh then e = { items = {} } map[kind] = e end
    local old = e.items[key]
    e.items[key] = mouth
    local ok, err = F.MouthApply(kind)
    if not ok then
        e.items[key] = old
        if fresh then map[kind] = nil end
        F.MouthApply(kind)
        F.mouthNote = string.format("%s's %s was not changed: %s", title_of(kind), key_words(key), tostring(err))
        return false, err
    end
    F.MouthSave()
    F.mouthNote = nil
    log("mouth shapes: %s's %s is now %s (yours)", title_of(kind), key_words(key), mouth_words(mouth, kind))
    F.MouthSummaryUpdate()
    return true
end
-- Back to G-SA1's (one sound key)
function F.MouthBack(kind, key)
    if not mouths_ok() then return false, "needs G-SA1 module 0.9.4e" end
    kind = tonumber(kind)
    local e = F.mouthMap[kind]
    if not (e and e.items and e.items[key]) then return false, "it is G-SA1's" end
    e.items[key] = nil
    if next(e.items) == nil then F.mouthMap[kind] = nil end
    F.MouthApply(kind)
    F.MouthSave()
    log("mouth shapes: %s's %s is back to G-SA1's", title_of(kind), key_words(key))
    F.MouthSummaryUpdate()
    return true
end
-- Reset <character>: every sound and variant of it
function F.MouthResetChar(kind)
    if not mouths_ok() then return false, "needs G-SA1 module 0.9.4e" end
    kind = tonumber(kind)
    if not F.mouthMap[kind] then return false, "nothing of yours" end
    F.mouthMap[kind] = nil
    F.MouthApply(kind)
    F.MouthSave()
    log("mouth shapes: %s reset to G-SA1's table", title_of(kind))
    F.MouthSummaryUpdate()
    return true
end
-- Reset every character: asks first (the only question on the page); confirmed = the answer was Yes
function F.MouthResetAll(confirmed)
    if not mouths_ok() then return false, "needs G-SA1 module 0.9.4e" end
    if not confirmed then
        if Derma_Query then
            Derma_Query("Remove your mouths for every character?", "G-SA1 mouth shapes", "Yes",
                function() F.MouthResetAll(true) end, "No", function() end)
        end
        return false, "asked"
    end
    local any = false
    for _, kind in ipairs(FACE_KINDS) do
        if F.mouthMap[kind] then
            F.mouthMap[kind] = nil
            F.MouthApply(kind)
            any = true
        end
    end
    F.MouthSave()
    log("mouth shapes: every character reset to G-SA1's table%s", any and "" or " (there was nothing of yours)")
    F.MouthSummaryUpdate()
    return true
end
-- "Use my mouths": off -> G-SA1's table for every kind with a line (the file untouched), on -> applied again
cvars.AddChangeCallback("gsa1_lipsync_shapes_custom", function(_, old, new)
    if ((tonumber(old) or 0) ~= 0) == ((tonumber(new) or 0) ~= 0) or not mouths_ok() then return end
    for _, kind in ipairs(FACE_KINDS) do
        if F.mouthMap[kind] then F.MouthApply(kind) end
    end
    F.MouthSummaryUpdate()
    log("mouth shapes: your mouths %s", cv.custom:GetBool() and "used" or "not used (G-SA1's for everyone)")
end, "gsa1_mouthtest")

hook.Add("GSA1CharacterCreated", "gsa1_mouthtest", function(C)
    F.MouthEnsure()
end)
-- the character goes: the tester lets go of it without a call (its face is gone)
hook.Add("GSA1CharacterLeaving", "gsa1_mouthtest", function(C)
    if T.active or T.drawing then F.TesterStop("the character left", true) end
end)
F.MouthEnsure()

-- 3. the page (Faces > Lip sync, after the "This character" line: cl_faces.lua's shapes_rows calls F.TesterRows) --------
-- the page's state, at most twice a second (numbers and strings made only when something changed): the character the page
-- shows (the one in play, else the Character setting), whether the tester and "Your mouths" can be used, why not
local PS = F.tpage or {}
F.tpage = PS
local function fmt_w(w)
    local t = string.format("%.4f", tonumber(w) or 0)
    t = string.gsub(t, "0+$", "")
    t = string.gsub(t, "%.$", "")
    return t
end
-- a row entry of gsa1.VisemeTable -> the file's MOUTH text ("7>16@0.45", "4:scales", "ladder@0.25")
local function entry_spec(e)
    if type(e) ~= "table" then return nil end
    local a, b, w = tonumber(e.a or e[1]) or 0, tonumber(e.b or e[2]) or 0, tonumber(e.w or e[3]) or 0
    if e.how == "ladder" or a < 0 then return w >= 0.99995 and "ladder" or ("ladder@" .. fmt_w(w)) end
    if e.how == "closed" or (a == 0 and b == 0) then return "0" end
    local s
    if a == 0 and w >= 0.99995 then s = tostring(b) else s = string.format("%d>%d@%s", a, b, fmt_w(w)) end
    if e.how == "scales" then s = s .. ":scales" end
    return s
end
F.TesterEntrySpec = entry_spec
-- the list's words for a mouth of a kind (F.MOUTH_CHOICES' text when one matches its numbers)
local choiceNums = setmetatable({}, { __mode = "k" })
function F.MouthDescription(kind, a, b, w)
    local list = F.MOUTH_CHOICES and F.MOUTH_CHOICES[tonumber(kind) or -1]
    if type(list) ~= "table" then return nil end
    for _, c in ipairs(list) do
        local n = choiceNums[c]
        if n == nil then
            n = parse_mouth(c.mouth, {}) or false
            choiceNums[c] = n
        end
        if n and n.a == a and n.b == b and math.abs(n.w - w) < 1e-3 then return c.text end
    end
    return nil
end
local function page_kind()
    local C = GSA1.Char
    local name = C and C.name or (GSA1.cv and GSA1.cv.character and GSA1.cv.character:GetString()) or "sonic"
    if not GSA1.KindByName(name) then name = "sonic" end
    return GSA1.KindByName(name), name, C
end
function F.TesterPageState(now)
    now = now or SysTime()
    if PS.at and now - PS.at < 0.5 and now >= PS.at then return PS end
    PS.at = now
    local kind, name, C = page_kind()
    local no = F.NoFaceText(name)
    local tok, mok = tester_ok(), mouths_ok()
    local usable = no == nil and tok and C ~= nil
    local key = (kind or -1) * 16 + (usable and 8 or 0) + (C and 4 or 0) + (tok and 2 or 0) + (mok and 1 or 0)
    local rows = ((F.mouthVersion * 4 + T.showAs) * 2 + (cv.custom:GetBool() and 1 or 0)) * 16 + (kind or 0)
    PS.rowsKey = rows * 64 + key
    if key == PS.key and name == PS.name then return PS end
    PS.key, PS.kind, PS.name, PS.usable, PS.mouths = key, kind, name, usable, no == nil and mok
    if no then
        PS.who = no
    elseif not tok then
        PS.who = "The mouth shape tester needs G-SA1 module 0.9.4c."
    elseif kind == 7 then
        PS.who = "Big's face has one mouth shape: only its size changes" .. (C and "" or " (spawn him to see it)")
    elseif C then
        PS.who = F.Title(name) .. " (your character)"
    else
        PS.who = F.Title(name) .. " (the Character setting: spawn it to see the mouths)"
    end
    if no then
        PS.mouthsWhy = no
    elseif not mok then
        PS.mouthsWhy = "Your mouths: needs G-SA1 module 0.9.4e"
    else
        PS.mouthsWhy = nil
    end
    PS.title = F.Title(name)
    PS.mouthsHead = "Your mouths for " .. tostring(PS.title)
    return PS
end
-- a live line that makes its text only when fn's answer changed (fn returns one string; idle: a constant one)
local function tlabel(parent, fn, every, role)
    local lbl = parent:Help("")
    lbl.gsa1Role = role
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        local now = SysTime()
        if now < (self.gsa1Next or 0) then return end
        self.gsa1Next = now + (every or 0.5)
        local text = fn(now)
        if text ~= self.gsa1Text then
            self.gsa1Text = text
            self:SetText(text)
            if self.InvalidateLayout then self:InvalidateLayout(true) end
            local parent2 = self.GetParent and self:GetParent()
            if parent2 and IsValid(parent2) and parent2.InvalidateLayout then parent2:InvalidateLayout() end
        end
    end
    return lbl
end
local IDLE_SHOWING = "Point at a sound: your character shows that mouth. Click: it stays 20 s, also with the menu closed "
    .. "(talking ends it)."
-- "Showing: ah (normal talking, G-SA1's) - 7>16 at 45 % - open "ah", fangs   kept: 14 s (close the menu to look)"
function F.TesterShowingText(now)
    if not T.active then return IDLE_SHOWING end
    if not T.drawing then return "Showing: -" end
    local ps = F.TesterPageState(now)
    local what
    if T.nowA < 0 then
        what = string.format("the voice slit (at most %d %%)", math.floor(T.nowW * 100 + 0.5))
    elseif T.nowA == 0 and T.nowB == 0 then
        what = "closed"
    else
        what = string.format("%d>%d at %d %%", T.nowA, T.nowB, math.floor(T.nowW * 100 + 0.5))
        local d = F.MouthDescription(ps.kind, T.nowA, T.nowB, T.nowW)
        if d then what = what .. " - " .. d end
    end
    local head
    if T.nowMouth then
        head = "Showing a mouth of the list"
    else
        local t = F.VisemeTable(ps.kind)
        local mine = type(t) == "table" and type(t[T.nowCls or -1]) == "table" and t[T.nowCls].custom == true and
            cv.custom:GetBool()
        head = string.format("Showing: %s (%s, %s)", F.VISEME_WORDS[T.nowCls or 0] or "?", show_as().text, mine and "yours"
            or "G-SA1's")
    end
    local tail = ""
    if T.pin and not pointing(now) and not T.play then
        tail = string.format("   kept: %d s (close the menu to look)", math.max(math.ceil((T.pinUntil or now) - now), 0))
    elseif T.play then
        tail = "   (Play all)"
    end
    local C = GSA1.Char
    if C and C.id and gsa1.FaceState then
        local letter = select(6, gsa1.FaceState(C.id))
        if (tonumber(letter) or -1) >= 0 then tail = tail .. " - a face animation is playing (the mouth waits)" end
    end
    return head .. " - " .. what .. tail
end
-- the rows of "Your mouths": the mouth now of a class for the "Show as" variant, whose it is, G-SA1's for comparison
function F.MouthRowTexts(kind, cls, variant)
    local t = F.VisemeTable(kind)
    local row = type(t) == "table" and t[cls] or nil
    if type(row) ~= "table" then return "(needs G-SA1 module 0.9.4c)", "", nil, false end
    local e, same = row, false
    if variant == 1 then
        e = row.quiet or row
        same = row.quiet == nil
    elseif variant == 2 then
        e = row.loud or row
        same = row.loud == nil
    end
    local spec = entry_spec(e)
    local words
    if spec and F.MouthText then
        local ok, w = pcall(F.MouthText, spec, kind)
        if ok and type(w) == "string" then words = w end
    end
    if not words then words = string.gsub(F.TableEntryText and F.TableEntryText(e) or tostring(spec), "^ ", "") end
    local d = F.MouthDescription(kind, tonumber(e.a) or 0, tonumber(e.b) or 0, tonumber(e.w) or 0)
    local nowText = words .. (d and ("  " .. d) or "") .. (same and "  (same as normal)" or "")
    local item = F.mouthMap[kind] and F.mouthMap[kind].items
    local key = NAMES[cls - 1] .. VARIANT_KEY[variant]
    local mine = type(item) == "table" and item[key] ~= nil
    local whose
    if mine or (type(item) == "table" and item[NAMES[cls - 1]] ~= nil) then
        whose = cv.custom:GetBool() and "yours *" or "yours (off)"
    else
        whose = "G-SA1's"
    end
    -- G-SA1's entry of this variant (pointing at "whose" shows it, to compare)
    local def = (row.custom == true and type(row.default) == "table") and row.default or row
    local de = def
    if variant == 1 then
        de = def.quiet or def
    elseif variant == 2 then
        de = def.loud or def
    end
    return nowText, whose, entry_spec(de), mine
end
-- the sound "Change" works on, and its key for the "Show as" variant ("AA", "AA.quiet", "AA.loud")
T.changeCls = T.changeCls or 2
T.pairA, T.pairB, T.pairW, T.pairScales = T.pairA or 0, T.pairB or 4, T.pairW or 1, T.pairScales or false
local function change_key()
    return NAMES[(T.changeCls or 2) - 1] .. VARIANT_KEY[T.showAs]
end
function F.PairSpec()
    local s = string.format("%d>%d@%s", T.pairA, T.pairB, fmt_w(T.pairW))
    if T.pairScales and T.pairA == 0 then s = s .. ":scales" end
    return s
end
-- "Use" from the page: the change list's line or the custom pair, for the sound being changed and the "Show as" variant
function F.MouthUseFromPage(mouth)
    local ps = F.TesterPageState()
    if not ps.mouths then return false, ps.mouthsWhy end
    local ok, err = F.MouthUse(ps.kind, change_key(), mouth)
    PS.at = nil
    return ok, err
end
local function layout_row(widths)
    return function(self, w, h)
        local kids = self.gsa1Kids
        local x = 0
        local flex = w
        for _, cw in ipairs(widths) do
            if cw > 0 then flex = flex - cw - 4 end
        end
        for i, k in ipairs(kids) do
            local cw = widths[i] > 0 and widths[i] or math.max(flex, 40)
            k:SetPos(x, 0)
            k:SetSize(cw, h)
            x = x + cw + 4
        end
    end
end
local function enable(p, on)
    on = on and true or false
    if p.gsa1On ~= on then
        p.gsa1On = on
        if p.SetEnabled then p:SetEnabled(on) end
    end
end
local function chain_think(p, fn)
    local base = p.Think
    p.Think = function(self)
        if base then base(self) end
        fn(self)
    end
end

function F.TesterRows(panel)
    F.MouthEnsure()
    local sub = vgui.Create("DForm", panel)
    if sub.SetName then sub:SetName("Mouth shape tester and your mouths") end
    if sub.SetExpanded then sub:SetExpanded(true) end
    sub.gsa1Role = "tester"
    panel:AddItem(sub)
    local ui = {}
    F.tui = ui
    if cv.style:GetInt() ~= F.STYLE_PHONEMES then
        sub:ControlHelp("The tester shows every mouth in every style; your own mouths are used with \"Mouth shapes from "
            .. "your voice\".")
    end
    tlabel(sub, function(now) return F.TesterPageState(now).who end, 0.5, "testerwho")
    local sa = sub:ComboBox("Show as")
    sa.gsa1Role = "showas"
    for i = 0, 2 do sa:AddChoice(F.TESTER_SHOWAS[i].text, i, i == T.showAs) end
    sa.OnSelect = function(_, _, _, data) F.TesterShowAs(data) end
    ui.showas = sa
    -- the eight sound buttons: point = show, click = keep 20 s
    local row = vgui.Create("DPanel")
    row:SetTall(28)
    if row.SetPaintBackground then row:SetPaintBackground(false) end
    local btns = {}
    for i, cls in ipairs(F.TESTER_SOUNDS) do
        local b = vgui.Create("DButton", row)
        local word = F.VISEME_WORDS[cls]
        b:SetText(word)
        b.gsa1Role, b.gsa1Class, b.gsa1Word, b.gsa1KeptText = "mouthbtn", cls, word, "[ " .. word .. " ]"
        b.DoClick = function()
            if F.TesterPageState().usable then F.TesterClick(cls, SysTime()) end
        end
        b.OnCursorEntered = function()
            if F.TesterPageState().usable then F.TesterPoint(cls, SysTime()) end
        end
        chain_think(b, function(self)
            local ps = F.TesterPageState()
            enable(self, ps.usable)
            if ps.usable and self.IsHovered and self:IsHovered() then F.TesterPoint(cls, SysTime()) end
            local kept = T.active and T.pin == cls and not T.pinMouth
            if kept ~= self.gsa1Kept then
                self.gsa1Kept = kept
                self:SetText(kept and self.gsa1KeptText or self.gsa1Word)
            end
        end)
        btns[i] = b
    end
    row.PerformLayout = function(self, w, h)
        local n, gap = #btns, 3
        local bw = math.floor((w - gap * (n - 1)) / n)
        for i, b in ipairs(btns) do
            b:SetPos((i - 1) * (bw + gap), 0)
            b:SetSize(i == n and (w - (n - 1) * (bw + gap)) or bw, h)
        end
    end
    sub:AddItem(row)
    ui.buttons = btns
    local _, pb = F.PageButtonRow(sub, {
        { "Play all (half a second each)", function()
            if F.TesterPageState().usable then F.TesterPlayAll(SysTime()) end
        end },
        { "Stop", function() F.TesterStop("Stop") end },
    })
    pb[1].gsa1Role, pb[2].gsa1Role = "playall", "stop"
    ui.playall, ui.stop = pb[1], pb[2]
    tlabel(sub, F.TesterShowingText, 0.25, "showing")
    sub:ControlHelp("Point at a sound: your character shows that mouth. Click: it stays 20 s, also with the menu closed "
        .. "(talking ends it).")
    -- the close-up
    local pic = vgui.Create("DPanel")
    pic:SetTall(F.CLOSEUP_H)
    pic.gsa1Role = "closeuppic"
    pic.Paint = function(self, w, h) F.CloseupPaint(self, w, h) end
    sub:AddItem(pic)
    ui.closeuppic = pic
    local cb = sub:CheckBox("Close-up of the face here", "gsa1_mouth_closeup")
    cb.gsa1Role = "closeup"
    sub:ControlHelp("A small live picture of your character's face while this page is open.")
    -- your mouths
    tlabel(sub, function(now)
        local ps = F.TesterPageState(now)
        return ps.mouthsWhy or ps.mouthsHead
    end, 0.5, "mouthsheader")
    local uc = sub:CheckBox("Use my mouths", "gsa1_lipsync_shapes_custom")
    uc.gsa1Role = "custom"
    sub:ControlHelp("Off: G-SA1's mouths for everyone (your choices stay saved).")
    ui.rows = {}
    for i = 1, #NAMES do
        local cls = i + 1
        local r = vgui.Create("DPanel")
        r:SetTall(22)
        if r.SetPaintBackground then r:SetPaintBackground(false) end
        r.gsa1Role, r.gsa1Class = "mouthrow", cls
        local snd = vgui.Create("DLabel", r)
        snd:SetText(F.VISEME_WORDS[cls])
        local nowl = vgui.Create("DLabel", r)
        local whose = vgui.Create("DLabel", r)
        if whose.SetMouseInputEnabled then whose:SetMouseInputEnabled(true) end
        local chg = vgui.Create("DButton", r)
        chg:SetText("Change")
        chg.gsa1Role = "change"
        local back = vgui.Create("DButton", r)
        back:SetText("Back to G-SA1's")
        back.gsa1Role = "back"
        r.gsa1Kids = { snd, nowl, whose, chg, back }
        r.gsa1Now, r.gsa1Whose, r.gsa1Change, r.gsa1Back = nowl, whose, chg, back
        r.PerformLayout = layout_row({ 52, 0, 70, 60, 100 })
        chg.DoClick = function()
            T.changeCls = cls
            PS.at = nil
        end
        back.DoClick = function()
            local ps = F.TesterPageState()
            if ps.mouths then F.MouthBack(ps.kind, NAMES[cls - 1] .. VARIANT_KEY[T.showAs]) end
            PS.at = nil
        end
        chain_think(r, function(self)
            local ps = F.TesterPageState()
            if ps.rowsKey ~= self.gsa1Key then
                self.gsa1Key = ps.rowsKey
                local nowText, whoseText, def, mine = F.MouthRowTexts(ps.kind, cls, T.showAs)
                nowl:SetText(nowText)
                whose:SetText(whoseText)
                self.gsa1Default, self.gsa1Mine = def, mine
                enable(chg, ps.mouths)
                enable(back, ps.mouths and mine)
            end
            -- pointing at "whose" shows G-SA1's mouth of this sound, to compare
            if ps.usable and self.gsa1Default and whose.IsHovered and whose:IsHovered() then
                F.TesterPointMouth(self.gsa1Default, SysTime())
            end
        end)
        sub:AddItem(r)
        ui.rows[i] = r
    end
    local _, rb = F.PageButtonRow(sub, {
        { "Reset this character to G-SA1's table", function()
            local ps = F.TesterPageState()
            if ps.mouths then F.MouthResetChar(ps.kind) end
            PS.at = nil
        end },
        { "Reset every character", function()
            F.MouthResetAll(false)
            PS.at = nil
        end },
    })
    rb[1].gsa1Role, rb[2].gsa1Role = "resetchar", "resetall"
    ui.resetchar, ui.resetall = rb[1], rb[2]
    chain_think(rb[1], function(self)
        local ps = F.TesterPageState()
        if ps.title ~= self.gsa1Title then
            self.gsa1Title = ps.title
            self:SetText("Reset " .. tostring(ps.title) .. " to G-SA1's table")
        end
        enable(self, ps.mouths and F.mouthMap[ps.kind] ~= nil)
    end)
    chain_think(rb[2], function(self) enable(self, F.TesterPageState().mouths) end)
    -- Change: the list of the character's own mouths for the sound (and the "Show as" variant)
    tlabel(sub, function(now)
        local ps = F.TesterPageState(now)
        if ps.mouthsWhy then return "" end
        local key = ps.rowsKey * 16 + (T.changeCls or 2)
        if ps.changeKey ~= key then
            ps.changeKey = key
            ps.changeText = string.format("Change \"%s\" (%s): point at a line = it shows on %s; double-click = use it",
                F.VISEME_WORDS[T.changeCls or 2], show_as().text, tostring(ps.title))
        end
        return ps.changeText
    end, 0.25, "changehead")
    local list = vgui.Create("DListView")
    if list.SetMultiSelect then list:SetMultiSelect(false) end
    list:SetTall(180)
    if list.AddColumn then
        local c1 = list:AddColumn("Mouth")
        if c1 and c1.SetFixedWidth then c1:SetFixedWidth(90) end
        list:AddColumn("What it looks like")
        local c3 = list:AddColumn("Moves")
        if c3 and c3.SetFixedWidth then c3:SetFixedWidth(90) end
    end
    list.gsa1Role = "changelist"
    list.DoDoubleClick = function(_, _, line)
        if line and line.gsa1Mouth then F.MouthUseFromPage(line.gsa1Mouth) end
    end
    list.OnRowSelected = function(_, _, line)
        T.changeSel = line and line.gsa1Mouth or nil
    end
    local TAGS = { talk = "talk", mouth = "mouth only", brows = "eyes / brows", head = "whole head" }
    chain_think(list, function(self)
        local ps = F.TesterPageState()
        enable(self, ps.mouths)
        if ps.kind == self.gsa1Kind then return end
        self.gsa1Kind = ps.kind
        self:Clear()
        T.changeSel = nil
        local choices = F.MOUTH_CHOICES and F.MOUTH_CHOICES[ps.kind or -1]
        for _, c in ipairs(type(choices) == "table" and choices or {}) do
            local text = c.mouth
            if F.MouthText then
                local ok, t = pcall(F.MouthText, c.mouth, ps.kind)
                if ok and type(t) == "string" then text = t end
            end
            local line = self:AddLine(text, tostring(c.text or ""), TAGS[c.tag] or tostring(c.tag or ""))
            if line then
                line.gsa1Mouth, line.gsa1Tag = c.mouth, c.tag
                if c.tag == "head" then
                    if line.SetTooltip then line:SetTooltip("Whole head: the eyes and brows move too - not for talking") end
                    for _, col in ipairs(type(line.Columns) == "table" and line.Columns or {}) do
                        if col.SetTextColor then col:SetTextColor(Color(140, 140, 140)) end
                    end
                end
                chain_think(line, function(ln)
                    if ln.IsHovered and ln:IsHovered() and F.TesterPageState().usable then
                        F.TesterPointMouth(ln.gsa1Mouth, SysTime())
                    end
                end)
            end
        end
    end)
    sub:AddItem(list)
    ui.list = list
    local useb = sub:Button("Use the selected mouth")
    useb.gsa1Role = "usefor"
    useb.DoClick = function()
        if T.changeSel then F.MouthUseFromPage(T.changeSel) end
    end
    chain_think(useb, function(self) enable(self, F.TesterPageState().mouths) end)
    ui.usefor = useb
    -- your own: two of the character's face keys and a weight
    sub:Help("Your own: two of the character's face keys and a weight")
    local ka = sub:ComboBox("Key A")
    local kb = sub:ComboBox("Key B")
    ka.gsa1Role, kb.gsa1Role = "keya", "keyb"
    local function fill_keys(combo, sel)
        local ps = F.TesterPageState()
        combo:Clear()
        local n = (F.MOUTH_KEYS and F.MOUTH_KEYS[ps.kind or -1]) or 0
        for k = 0, n - 1 do
            local d = F.MouthDescription(ps.kind, 0, k, 1)
            combo:AddChoice(d and string.format("%d - %s", k, d) or string.format("%d", k), k, k == sel)
        end
    end
    local function keys_think(combo, which)
        chain_think(combo, function(self)
            local ps = F.TesterPageState()
            if ps.kind ~= self.gsa1Kind then
                self.gsa1Kind = ps.kind
                local n = (F.MOUTH_KEYS and F.MOUTH_KEYS[ps.kind or -1]) or 0
                if T.pairA >= n then T.pairA = 0 end
                if T.pairB >= n then T.pairB = math.min(4, math.max(n - 1, 0)) end
                fill_keys(self, which == "a" and T.pairA or T.pairB)
            end
            enable(self, ps.mouths)
        end)
    end
    keys_think(ka, "a")
    keys_think(kb, "b")
    ka.OnSelect = function(_, _, _, data)
        T.pairA = math.floor(tonumber(data) or 0)
        if T.pairA ~= 0 then T.pairScales = false end
    end
    kb.OnSelect = function(_, _, _, data) T.pairB = math.floor(tonumber(data) or 0) end
    ui.keya, ui.keyb = ka, kb
    local wt = sub:NumSlider("Weight (1/64 steps)", nil, 0, 1, 3)
    wt.gsa1Role = "weight"
    if wt.SetValue then wt:SetValue(T.pairW) end
    wt.OnValueChanged = function(_, v)
        T.pairW = math.min(math.max(math.floor((tonumber(v) or 0) * 64 + 0.5) / 64, 0), 1)
    end
    ui.weight = wt
    local sc = sub:CheckBox("Size follows your loudness (only with key A = 0)")
    sc.gsa1Role = "scales"
    sc.OnChange = function(_, v) T.pairScales = v == true and T.pairA == 0 end
    chain_think(sc, function(self)
        local on = T.pairA == 0 and F.TesterPageState().mouths
        enable(self, on)
        if not on and T.pairScales then T.pairScales = false end
        if self.gsa1Checked ~= T.pairScales then
            self.gsa1Checked = T.pairScales
            if self.SetChecked then self:SetChecked(T.pairScales) end
        end
    end)
    ui.scales = sc
    local _, pr = F.PageButtonRow(sub, {
        { "Show", function()
            if F.TesterPageState().usable then F.TesterKeepMouth(F.PairSpec(), SysTime()) end
        end },
        { "Use", function() F.MouthUseFromPage(F.PairSpec()) end },
    })
    pr[1].gsa1Role, pr[2].gsa1Role = "pairshow", "pairuse"
    ui.pairshow, ui.pairuse = pr[1], pr[2]
    chain_think(pr[2], function(self) enable(self, F.TesterPageState().mouths) end)
    tlabel(sub, function()
        if F.mouthNote then return F.mouthNote end
        local n, why = #F.mouthBad, nil
        for _, k in ipairs(FACE_KINDS) do
            if F.mouthRefused[k] then
                n = n + 1
                why = why or (title_of(k) .. ": " .. F.mouthRefused[k])
            end
        end
        if n == 0 then return "" end
        if not why and type(F.mouthBad[1]) == "table" then why = tostring(F.mouthBad[1].why or "not readable") end
        if PS.unusedN ~= n or PS.unusedWhy ~= why then
            PS.unusedN, PS.unusedWhy = n, why
            PS.unusedText = string.format("%d line%s of %s %s not used: %s", n, n == 1 and "" or "s", mouth_file(),
                n == 1 and "was" or "were", tostring(why))
        end
        return PS.unusedText
    end, 0.5, "unused")
    local summaryLast, summaryText = nil, "Your mouths: none"
    local sl = tlabel(sub, function()
        local s = cv.msummary:GetString()
        if s ~= summaryLast then
            summaryLast = s
            summaryText = "Your mouths: " .. (s ~= "" and s or "none")
        end
        return summaryText
    end, 1, "mouthsummary")
    sl.gsa1ConVar = "gsa1_mouth_summary"
    sub:ControlHelp("Your own mouths are drawn as you chose them ('Bigger mouths' does not change them). Saved in "
        .. "garrysmod/data/gsa1/mouth_shapes.txt: key numbers and weights only.")
    return sub
end

-- 4. the close-up (lipsync2_plan.md 4.8 with review R.4b / R.10) -------------------------------------------------------
F.CLOSEUP_DIST, F.CLOSEUP_FOV, F.CLOSEUP_W, F.CLOSEUP_H = 40, 30, 256, 192
local CU = { origin = Vector(), angles = Angle(), view = {} }
-- the camera: F.CLOSEUP_DIST HU in front of the mouth point (VisemeTable(kind).mouth_at turned by the character's facing,
-- else 0.85 x its height above its position), looking back at it
function F.CloseupCamera(C, origin, angles)
    local t = F.VisemeTable(C.kind)
    local at = type(t) == "table" and type(t.mouth_at) == "table" and t.mouth_at or nil
    local fwd, up = tonumber(at and at.forward), tonumber(at and at.up)
    if not (fwd and up) then
        fwd, up = 0, 0.85 * (tonumber(C.info and C.info.height) or 40)
    end
    local yaw = tonumber(C.drawYaw) or 0
    local r = math.rad(yaw)
    local cx, cy = math.cos(r), math.sin(r)
    local p = C.drawPos
    local d = fwd + F.CLOSEUP_DIST
    origin:SetUnpacked(p.x + cx * d, p.y + cy * d, p.z + up)
    angles.p, angles.y, angles.r = 0, yaw + 180, 0
    return origin, angles
end
-- why there is no picture now (nil: draw it); "" = nothing at all (the box is not ticked)
function F.CloseupBlocked()
    if not cv.closeup:GetBool() then return "" end
    if F.closeupBroken then return "The close-up stopped for this session (see the session log)" end
    if not (render and render.RenderView) then return "The close-up is not available in this version" end
    local C = GSA1.Char
    if not (C and C.id and C.drawPos) then return "Spawn a character to see its face here" end
    local no = F.NoFaceText(C.name)
    if no or C.gsa1Faces == false then return no or "This character has no face" end
    if GSA1.FirstPerson and GSA1.FirstPerson() then return "The close-up needs the third-person camera" end
    return nil
end
-- the panel's Paint (only while the page is shown): render.RenderView into the panel's rectangle, in pcall
function F.CloseupPaint(panel, w, h)
    if panel.IsVisible and not panel:IsVisible() then return end
    w, h = math.min(w, F.CLOSEUP_W), math.min(h, F.CLOSEUP_H)
    surface.SetDrawColor(18, 18, 22, 255)
    surface.DrawRect(0, 0, w, h)
    local why = F.CloseupBlocked()
    if why then
        if why ~= "" then
            draw.SimpleText(why, "DermaDefault", math.floor(w / 2), math.floor(h / 2), color_white, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        return
    end
    local C = GSA1.Char
    F.CloseupCamera(C, CU.origin, CU.angles)
    local x, y = panel:LocalToScreen(0, 0)
    local v = CU.view
    v.origin, v.angles, v.x, v.y, v.w, v.h, v.fov = CU.origin, CU.angles, x, y, w, h, F.CLOSEUP_FOV
    v.drawviewmodel, v.drawhud, v.dopostprocess, v.drawviewer = false, false, false, false
    F.closeupDrawing = true
    local ok, err = pcall(render.RenderView, v)
    F.closeupDrawing = false
    if not ok then
        F.closeupBroken = tostring(err)
        log("mouth tester: the close-up stopped for this session: %s", F.closeupBroken)
        return
    end
    F.closeupViews = (F.closeupViews or 0) + 1
end

-- 5. console extras (the page has every control) ---------------------------------------------------------------------
local SOUND_OF = { mbp = 1, m = 1, b = 1, p = 1, ah = 2, aa = 2, a = 2, eh = 3, e = 3, ee = 4, i = 4, oh = 5, o = 5,
                   oo = 6, u = 6, s = 7, ss = 7, sh = 7, z = 7, f = 8, fv = 8, v = 8, th = 8 }
local function say(fmt, ...)
    if GSA1.Chat then GSA1.Chat(fmt, ...) else print(string.format(fmt, ...)) end
end
concommand.Add("gsa1_mouth_show", function(_, _, args)
    local cls = SOUND_OF[string.lower(tostring(args and args[1] or ""))]
    if not cls then return say("gsa1_mouth_show <ah | eh | ee | oh | oo | s | f | mbp> [quiet | loud]") end
    local C = GSA1.Char
    if not (C and C.id and tester_ok() and F.HasFaces(C.name)) then return say("mouth tester: no character with a face") end
    F.TesterShow(cls, VARIANT_OF[string.lower(tostring(args[2] or ""))] or 0, F.TESTER_SHOW)
end, nil, "G-SA1: shows a mouth of your character for 3 s (gsa1_mouth_show <ah|eh|ee|oh|oo|s|f|mbp> [quiet|loud])")
concommand.Add("gsa1_mouth_reset", function(_, _, args)
    if not F.MouthEnsure() then return say("mouth shapes: your mouths need G-SA1 module 0.9.4e") end
    local a = string.lower(tostring(args and args[1] or ""))
    if a == "all" then
        F.MouthResetAll(true)
        return
    end
    local kind
    if a == "" then
        kind = page_kind()
    else
        kind = (F.MOUTH_CHARS and F.MOUTH_CHARS[a]) or GSA1.KindByName(a)
    end
    if not face_kind(kind) then return say("mouth shapes: no face to reset (%s)", a ~= "" and a or "this character") end
    local ok, err = F.MouthResetChar(kind)
    if not ok then say("mouth shapes: %s: %s", title_of(kind), tostring(err)) end
end, nil, "G-SA1: your mouths back to G-SA1's (gsa1_mouth_reset [sonic|tails|knuckles|amy|big|all]; none = this "
    .. "character)")
