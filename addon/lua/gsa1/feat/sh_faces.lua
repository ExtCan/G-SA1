-- G-SA1 event faces, the shared part (round 0.9.4a: sadc docs/research/faces_wheel_plan.md 4.3 / 4.7 / 5.5 / 6.4 / 8.2 /
-- 8.3 with its Review R.2 / R.6 / R.10 / R.19; faces_wheel_ui.md 4 and 5). Pure data and functions (both realms load it;
-- only the client uses it): the 31 face animations with G-SA1's own labels, the face animation format "letter:enter:hold",
-- the library file garrysmod/data/gsa1/face_anims.txt (parse / serialize, the defaults), the letter masks, the lip-sync
-- maths. The client part (the Faces page, the face animation maker, the switch, the hotkeys, lip sync, GSA1.Faces.Play) is
-- feat/cl_faces.lua; the module's feature "faces" is src/module/bind_faces.cpp.
--
-- The Lua contract other features use (faces_wheel_plan.md 5.5; the emote wheel, feat/cl_wheel.lua):
--   GSA1.Faces.Library()              the face animations in the page's order: { name, entries = { {letter, enter, hold},
--                                     ... }, back, hold_last }
--   GSA1.Faces.Find(name)             that face animation or nil
--   GSA1.Faces.HasFaces(entry_name)   false for gamma, supersonic, supersonic_general (and without the module's "faces")
--   GSA1.Faces.CanShow(name, entry)   true | false, why ("Big can't show b")
--   GSA1.Faces.Play(C, name, why)     plays it on the character table C now; true | nil, reason; why = "wheel", ...
--   GSA1.Faces.Stop(C)
--   hook "GSA1FaceLibraryChanged"(change)  change = { renamed = { [old] = new }, deleted = { [name] = true },
--                                     saved = { [name] = true } } after every save, rename or delete
-- Units: frames are the game's 60 Hz logic steps (the face table's own unit; 60 = 1 second).
-- Round 0.9.4c (sadc docs/research/phoneme_plan.md 4.2-4.4, 4.8, 6.3 with its Review R.1 / R.5 / R.6 / R.10 and the owner's
-- answers 10.1): lip sync's style 2, "mouth shapes from your voice" - F.Smooth's optional rise, the pure helpers of the
-- style (F.HoldClass, F.Variant, the per-spurt numbers F.SpurtAdd / F.SpurtLine, F.TableText) and its constants.
-- Round 0.9.4e (sadc docs/research/lipsync2_plan.md 4.4, 4.8, 4.9 with its Review R.3 / R.5): the guided warm-up's steps
-- (F.WARM_STEPS), the numbers line v2 (medians over the sound frames, the closing pause, per raw class the classifier's
-- rel_loc / per / nbr / lowr / zcr, the "ee" near misses, the hearing and mouths tags), F.TableText marking the player's
-- own mouths "(yours)", the mouth shape tester's constants (feat/cl_mouthtest.lua). Still numbers and class names only:
-- never a learned voice number or a warm-up count (the owner's answer PQ7).
GSA1 = GSA1 or {}
local F = GSA1.Faces or {}
GSA1.Faces = F

F.NEEDS = { feature = "faces", version = 1, module = "0.9.4a" }
F.FILE = "gsa1/face_anims.txt"
F.SEQ_MAX = 32           -- SA1_FACE_SEQ_MAX: entries per call, G-SA1's appended {A, back, 0} included (review R.10)
F.ENTER_MAX = 127        -- frames (a step's time is a signed byte in the game's data)
F.HOLD_MAX = 3600        -- SA1_FACE_HOLD_MAX
F.BACK_MAX = 60          -- the maker's "back to neutral over N frames" (the file takes up to ENTER_MAX)
F.BACK_DEFAULT = 8       -- the game's 'A' (8 steps)
F.NAME_MAX = 32
F.FPS = 60
F.RISE = 0.03            -- s: lip sync's rise time constant (faces_wheel_ui.md 5.4)
F.LOUD = 0.05            -- a smoothed level above this is talking
F.ALL = 0x7FFFFFFF

-- the 31 face animations (the game's letters 'A'-'Z', 'a'-'e' = 0-30): G-SA1's own labels and short descriptions (review
-- R.19: not the sadocs wiki's text). Which ones a character can show comes from the module (gsa1.FaceInfo's letters).
F.FACES = {
    [0] = { "A", "Neutral", "The plain face (the game also rests on it between expressions)." },
    { "B", "Blink", "One quick blink." },
    { "C", "Talk (long)", "A long stretch of talking mouth shapes." },
    { "D", "Talk (medium)", "Talking, shorter." },
    { "E", "Talk (short)", "A few words." },
    { "F", "Angry talk", "Talking with a frown." },
    { "G", "Happy talk", "Talking with a grin." },
    { "H", "Blink, surprise, annoyed", "Blinks, looks surprised, then annoyed." },
    { "I", "Hurt", "The pained face the game shows when he is hit." },
    { "J", "Shock, then a yell", "Shocked, then shouting." },
    { "K", "Slow blink", "Closes the eyes for about a second." },
    { "L", "Short eyes closed", "Closes the eyes briefly." },
    { "M", "Slow surprise", "Surprise that builds up slowly." },
    { "N", "Worried", "Worried, close to sad." },
    { "O", "Very sad", "Sad, mouth turned down." },
    { "P", "\"Ha!\", then happy", "A short laugh into a happy face." },
    { "Q", "Laughing", "Laughing (the game never uses it)." },
    { "R", "Slow \"oh\"", "A slow, surprised \"oh\"." },
    { "S", "Short \"oh\"", "A quick \"oh\"." },
    { "T", "Narrowed eyes", "Eyes narrowed, then back." },
    { "U", "Eyes slowly closing", "The lids sink until the eyes are shut." },
    { "V", "Eyes closed", "Eyes shut." },
    { "W", "Sleepy", "Heavy lids that droop and lift." },
    { "X", "Eyes slowly opening", "The eyes open from shut." },
    { "Y", "Lids a little down", "Relaxed lids (the game never uses it)." },
    { "Z", "Surprised", "Wide eyes, mouth open." },
    { "a", "Worried look", "A worried look." },
    { "b", "Happy", "A happy, open smile." },
    { "c", "Side smile", "A smile in the corner of the mouth (unused in the game)." },
    { "d", "Slight side smile", "A small smile in the corner of the mouth (unused in the game)." },
    { "e", "Long surprise", "Surprised for three seconds (the game's frozen face)." },
}

-- before the module has read the disc (gsa1.FaceInfo): the masks faces_events.md measured, for the page only - the module's
-- numbers win as soon as they are there, and libsa1 checks every call itself
F.EXPECTED_LETTERS = { [0] = F.ALL, [2] = F.ALL, [3] = F.ALL, [5] = F.ALL, [7] = 0x01FC0C1F }
F.FACE_KINDS = { [0] = true, [2] = true, [3] = true, [5] = true, [7] = true }

local band, bor, lshift = bit.band, bit.bor, bit.lshift

function F.Letter(i)
    local f = F.FACES[tonumber(i) or -1]
    return f and f[1] or nil
end
function F.Index(letter)
    if type(letter) ~= "string" or #letter ~= 1 then return nil end
    local b = string.byte(letter)
    if b >= 65 and b <= 90 then return b - 65 end
    if b >= 97 and b <= 101 then return 26 + b - 97 end
    return nil
end
function F.Label(letter)
    local i = F.Index(letter)
    return i and F.FACES[i][2] or tostring(letter)
end
function F.Bit(letter)
    local i = F.Index(letter)
    return i and lshift(1, i) or 0
end
-- "F, G, Z" of a mask
function F.LettersText(mask)
    local out = {}
    for i = 0, 30 do
        if band(mask, lshift(1, i)) ~= 0 then out[#out + 1] = F.FACES[i][1] end
    end
    return table.concat(out, ", ")
end
function F.CountLetters(mask)
    local n = 0
    for i = 0, 30 do
        if band(mask, lshift(1, i)) ~= 0 then n = n + 1 end
    end
    return n
end

local function int_in(v, lo, hi)
    v = tonumber(v)
    return v ~= nil and v == math.floor(v) and v >= lo and v <= hi
end

-- the most entries of a face animation's own: 31 when G-SA1 appends {A, back, 0} (review R.10)
function F.MaxEntries(back, hold_last)
    if (tonumber(back) or 0) > 0 and not hold_last then return F.SEQ_MAX - 1 end
    return F.SEQ_MAX
end

-- "b:10:90,A:8:0" -> { {letter, enter, hold}, ... } | nil, why
function F.ParseEntries(text)
    if type(text) ~= "string" or string.Trim(text) == "" then return nil, "no entries" end
    local out = {}
    for item in string.gmatch(text .. ",", "([^,]*),") do
        item = string.Trim(item)
        local l, en, ho = string.match(item, "^(%a):(%d+):(%d+)$")
        if not l or not F.Index(l) then return nil, string.format("\"%s\" is not letter:enter:hold", item) end
        en, ho = tonumber(en), tonumber(ho)
        if not int_in(en, 0, F.ENTER_MAX) or not int_in(ho, 0, F.HOLD_MAX) then
            return nil, string.format("\"%s\": enter 0-%d, hold 0-%d frames", item, F.ENTER_MAX, F.HOLD_MAX)
        end
        out[#out + 1] = { l, en, ho }
        if #out > F.SEQ_MAX then return nil, string.format("more than %d entries", F.SEQ_MAX) end
    end
    return out
end

function F.EntriesText(entries)
    local t = {}
    for i, e in ipairs(entries or {}) do t[i] = string.format("%s:%d:%d", e[1], e[2], e[3]) end
    return table.concat(t, ",")
end

-- what goes to gsa1.FaceSequence: the spec (with G-SA1's {A, back, 0} unless back is 0 or the last face is kept) and the
-- flags (HOLD_LAST when the last face is kept)
function F.SpecOf(anim, hold_flag)
    local spec = F.EntriesText(anim.entries)
    local back = tonumber(anim.back) or 0
    if back > 0 and not anim.hold_last then spec = spec .. string.format(",A:%d:0", back) end
    return spec, anim.hold_last and (hold_flag or 4) or 0
end

-- the letters a face animation shows (its entries and the appended 'A')
function F.UsedMask(anim)
    local m = 0
    for _, e in ipairs(anim.entries or {}) do m = bor(m, F.Bit(e[1])) end
    if (tonumber(anim.back) or 0) > 0 and not anim.hold_last then m = bor(m, 1) end
    return m
end

-- a name for a face animation: 1-32 characters, no tab, comma or line break
function F.CleanName(name)
    name = string.Trim(tostring(name or ""))
    if name == "" then return nil, "give it a name" end
    if #name > F.NAME_MAX then return nil, string.format("a name has at most %d characters", F.NAME_MAX) end
    if string.find(name, "[\t,\r\n]") then return nil, "a name may not contain a comma or a tab" end
    return name
end

-- the defaults (faces_wheel_plan.md 8.3; letters are the game's animation ids, the names G-SA1's)
F.DEFAULTS = {
    { name = "Happy", entries = { { "b", 10, 90 } }, back = 8, hold_last = false },
    { name = "Surprised", entries = { { "Z", 6, 60 } }, back = 8, hold_last = false },
    { name = "Sad", entries = { { "N", 20, 60 } }, back = 12, hold_last = false },
    { name = "Talk", entries = { { "C", 0, 0 }, { "D", 0, 0 }, { "E", 0, 0 } }, back = 8, hold_last = false },
    { name = "Blink", entries = { { "B", 0, 0 } }, back = 0, hold_last = false },
    { name = "Eyes closed", entries = { { "V", 8, 60 }, { "X", 0, 0 } }, back = 0, hold_last = false },
    { name = "Sleepy", entries = { { "W", 0, 0 }, { "U", 0, 30 }, { "X", 0, 0 } }, back = 0, hold_last = false },
    { name = "Ha!", entries = { { "P", 0, 30 } }, back = 8, hold_last = false },
    { name = "Angry talk", entries = { { "F", 0, 0 } }, back = 8, hold_last = false },
    { name = "Shock", entries = { { "J", 0, 30 } }, back = 12, hold_last = false },
    { name = "Squint", entries = { { "T", 0, 0 } }, back = 8, hold_last = false },
}

function F.CopyAnim(a)
    local e = {}
    for i, x in ipairs(a.entries or {}) do e[i] = { x[1], x[2], x[3] } end
    return { name = a.name, entries = e, back = tonumber(a.back) or 0, hold_last = a.hold_last == true }
end
function F.CopyList(list)
    local out = {}
    for i, a in ipairs(list or {}) do out[i] = F.CopyAnim(a) end
    return out
end

F.HEADER = {
    "# G-SA1 face animations - written by Q menu > Options > G-SA1 > Faces; one face animation per line, tab-separated:",
    "# name  back  keep  entries  label",
    "#   name     1-32 characters, unique, no tab or comma",
    "#   back     frames (60 = 1 s) of the blend back to the neutral face at the end; 0 = none (G-SA1 appends A:<back>:0)",
    "#   keep     1 = the last face stays until the next face command (then \"back\" is not appended); 0 = no",
    "#   entries  comma list of letter:enter:hold - letter A-Z a-e = the game's face animations 0-30; enter 0-127 (0 = the",
    "#            game's own); hold 0-3600; at most 32 entries, 31 when back is not 0 and keep is 0",
    "#   label    reserved; empty",
}

-- the file's text -> list, bad lines, notes (review R.10: a 32-entry line with back > 0 and keep 0 loads with back 0)
function F.ParseLibrary(text)
    local list, bad, notes, seen = {}, 0, {}, {}
    if type(text) ~= "string" then return list, 0, notes end
    for line in string.gmatch(text, "[^\n]+") do
        line = string.gsub(line, "\r$", "")
        if string.Trim(line) ~= "" and string.sub(line, 1, 1) ~= "#" and not string.match(line, "^version\t") then
            local f = {}
            for field in string.gmatch(line .. "\t", "([^\t]*)\t") do f[#f + 1] = field end
            local name = F.CleanName(f[1])
            local back, keep = tonumber(f[2]), tonumber(f[3])
            local entries = f[4] and F.ParseEntries(f[4]) or nil
            if not name or seen[string.lower(name)] or not int_in(back, 0, F.ENTER_MAX) or not (keep == 0 or keep == 1) or
                not entries then
                bad = bad + 1
            else
                local a = { name = name, entries = entries, back = back, hold_last = keep == 1 }
                if #entries > F.MaxEntries(a.back, a.hold_last) then
                    a.back = 0
                    notes[#notes + 1] = string.format("\"%s\" has %d entries: its blend back to neutral is off (31 entries "
                        .. "at most with it)", name, #entries)
                end
                seen[string.lower(name)] = true
                list[#list + 1] = a
            end
        end
    end
    return list, bad, notes
end

function F.SerializeLibrary(list)
    local out = {}
    for _, h in ipairs(F.HEADER) do out[#out + 1] = h end
    out[#out + 1] = "version\t1"
    for _, a in ipairs(list or {}) do
        out[#out + 1] = string.format("%s\t%d\t%d\t%s\t", a.name, tonumber(a.back) or 0, a.hold_last and 1 or 0,
            F.EntriesText(a.entries))
    end
    return table.concat(out, "\n") .. "\n"
end

-- the read-only mirror for the session log: "11 face animations: Happy, Surprised, ..."
function F.MirrorString(list)
    local names = {}
    for i, a in ipairs(list or {}) do names[i] = a.name end
    local s = string.format("%d face animation%s", #names, #names == 1 and "" or "s")
    if #names > 0 then s = s .. ": " .. table.concat(names, ", ") end
    if #s > 240 then s = string.sub(s, 1, 237) .. "..." end
    return s
end

-- lip sync (faces_wheel_ui.md 5.4), pure: st = { s, quiet } (a new table: talking off); returns the level to send
-- (0..1) while talking, -1 when not. raw: the source's level 0..1; dt seconds; speaking: Garry's Mod says the player talks
-- (its own source only; style 2: the shown sound is not silence). rise (0.9.4c, optional): the rise time constant in
-- seconds (default F.RISE: every 0.9.4a call returns what it returned; style 2 passes gsa1_lipsync_shapes_rise)
function F.Smooth(st, raw, dt, gain, gate, release, hang, speaking, rise)
    raw = tonumber(raw) or 0
    dt = math.max(tonumber(dt) or 0, 0)
    local m = raw < (tonumber(gate) or 0) and 0 or math.min(math.max(raw * (tonumber(gain) or 1), 0), 1)
    local s = tonumber(st.s) or 0
    rise = tonumber(rise)
    if rise == nil or rise <= 0 then rise = F.RISE end
    local tau = m > s and rise or math.max(tonumber(release) or 0.12, 1e-3)
    if dt > 0 then s = s + (m - s) * (1 - math.exp(-dt / tau)) end
    st.s = s
    if s > F.LOUD or speaking then
        st.quiet = 0
    else
        st.quiet = (tonumber(st.quiet) or 1e9) + dt
    end
    if st.quiet < (tonumber(hang) or 0.6) then return s end
    return -1
end

-- 0.9.4c: lip sync style 2, "mouth shapes from your voice" (phoneme_plan.md 4.2-4.4). The module (feature "faces" 2,
-- src/module/bind_faces.cpp) hears which kind of sound the microphone gets (gsa1.MicViseme: one of 9 classes per 10 ms) and
-- knows each character's mouth for it (gsa1.VisemeMouth); these pure helpers decide per frame which class to show and its
-- variant; cl_faces.lua's F.LipSyncFrame sends it. Nothing here keeps a sound: only class numbers, levels and times.
F.STYLE_LADDER, F.STYLE_TALK, F.STYLE_PHONEMES = 0, 1, 2
F.NEEDS_SHAPES = { feature = "faces", version = 2, module = "0.9.4c" }
F.SIL, F.MBP, F.FV = 0, 1, 8
F.VISEME_COUNT = 9
-- the module's gsa1.VISEME.NAMES / WORDS (the module's win when it has them)
F.VISEME_NAMES = { [0] = "SIL", "MBP", "AA", "EH", "EE", "OH", "OO", "SS", "FV" }
F.VISEME_WORDS = { [0] = "silence", "m b p", "ah", "eh", "ee", "oh", "oo", "s z sh", "f v th" }
-- the "Sound now" line's words
F.SHAPE_TEXT = { [0] = "silence", "M B P (closed)", "AH (open)", "EH (half open)", "EE (spread)", "OH (round)",
                 "OO (small round)", "S Z SH (nearly shut)", "F V TH (a slit)" }
-- gsa1_lipsync_shapes_steady 0 quick / 1 steadier / 2 instant: how long a shown shape stays at least (s), and the
-- classifier's vote for each (gsa1.MicVisemeTune "smooth": 3 = 2-of-3 with immediate open / close, 2 = with vowel
-- hysteresis, 0 = none)
F.SHAPES_HOLD = { [0] = 1 / 30, 2 / 30, 0 }
F.SHAPES_SMOOTH = { [0] = 3, 2, 0 }
F.SHAPES_RISE = 0.015            -- s: style 2's default rise (the class carries the timing)
F.SHAPE_QUIET = 0.5              -- the quiet variant while the openness is under this ...
F.SHAPE_QUIET_END = 0.55         -- ... until it is above this (review R.6)
F.SHAPE_LOUD_HYST = 0.06         -- the loud variant ends under gsa1_lipsync_shapes_loud - this (3 dB; review R.6)
F.STALE = 0.1                    -- s: a classifier frame not renewed this long while listening counts as silence (R.5)
F.HOLD_EPS = 1e-4                -- s: frame times are sums of floats

-- the class to show (phoneme_plan.md 4.4 as review R.5 rewrote it): the NEWEST class as soon as the shown one has been
-- shown for hold_s seconds; a class that comes during the hold is shown at its end only if it is still the newest (a blip
-- that ended is never shown); MBP at once (the lips close on m, b, p); SIL is held like any class (a t / d / k closure keeps
-- the vowel's mouth). cls < 0 or nil (not listening, no frame yet) and a frame whose seq has not changed for F.STALE s
-- (a dead device must not freeze a mouth) count as SIL. st: a table kept per character (a new one: silence for ever);
-- st.newest = the newest class as counted, st.stale = the frame was stale. Returns the shown class, true when it changed.
function F.HoldClass(st, cls, seq, now, hold_s)
    cls = tonumber(cls) or -1
    now = tonumber(now) or 0
    seq = tonumber(seq)
    st.stale = false
    if seq ~= nil then
        if seq ~= st.seq or st.seqAt == nil then
            st.seq, st.seqAt = seq, now
        elseif now - st.seqAt >= F.STALE - F.HOLD_EPS then
            st.stale = true
        end
    end
    if cls < 0 or cls >= F.VISEME_COUNT or cls ~= math.floor(cls) or st.stale then cls = F.SIL end
    st.newest = cls
    if st.shown == nil then st.shown, st.at = F.SIL, -1e9 end
    if cls == st.shown then return cls, false end
    if cls == F.MBP or now - (st.at or -1e9) >= (tonumber(hold_s) or 0) - F.HOLD_EPS then
        st.shown, st.at = cls, now
        return cls, true
    end
    return st.shown, false
end

-- the variant of the shown mouth (phoneme_plan.md 4.3 with review R.6): 1 quiet while the openness s is under
-- F.SHAPE_QUIET (it ends above F.SHAPE_QUIET_END), 2 loud while the raw level is at least `loud` (gsa1_lipsync_shapes_loud;
-- it ends under loud - F.SHAPE_LOUD_HYST), else 0 normal. On the st of F.HoldClass: a change waits for the same hold (the
-- shape - class and variant - stays at least hold_s) and joins a class change made in the same frame (now); while the
-- shown class is SIL or MBP (a closed mouth) the variant follows at once without restarting the hold. Returns the variant.
function F.Variant(st, s, raw, loud, now, hold_s)
    s, raw, loud = tonumber(s) or 0, tonumber(raw) or 0, tonumber(loud) or 0.8
    local c = st.vc or 0
    local quiet
    if c == 1 then quiet = s <= F.SHAPE_QUIET_END else quiet = s < F.SHAPE_QUIET end
    local isloud
    if c == 2 then isloud = raw >= loud - F.SHAPE_LOUD_HYST else isloud = raw >= loud end
    c = quiet and 1 or (isloud and 2 or 0)
    st.vc = c
    if st.v == nil or st.shown == nil or st.shown == F.SIL or st.shown == F.MBP then
        st.v = c
        return c
    end
    if c ~= st.v then
        now = tonumber(now)
        if now == nil or st.at == nil or st.at == now or now - st.at >= (tonumber(hold_s) or 0) - F.HOLD_EPS then
            st.v = c
            if now ~= nil and st.at ~= now then st.at = now end
        end
    end
    return st.v
end

-- per talk spurt numbers for the session log (phoneme_plan.md 4.8 with review R.10; only with gsa1_lipsync_shapes_log 1,
-- off by default): how often each class came, the mean F1 / F2 of each vowel class, the openness and level medians -
-- numbers and class names only. Never the sound, and never the voice learning's numbers (the owner, PQ7: nothing of the
-- learning is written anywhere). sp: one table reused from spurt to spurt (F.SpurtReset makes no new table after its first).
-- 0.9.4e (lipsync2_plan.md 4.9 with review R.3): the openness and level medians over the SOUND frames (class not SIL;
-- 0.9.4c's "level median 0.01" came from the silent frames) with their count; the closing pause (the SIL frames after the
-- spurt's last sound); per RAW class of the module's atomic 2 (the classifier's own decision of that 10 ms frame, before
-- the vote and the hold; not SIL) the medians of rel_loc (dB), per, nbr, lowr and zcr; "ee near" = frames counted as
-- another vowel whose "ee" posterior was 0.35-0.55 (the gate's near misses); the hearing and mouths tags. Histograms in
-- tables made once (no per-frame allocation).
F.SPURT_BINS = 50
F.SPURT_LOC_BINS = 64            -- rel_loc: 1 dB bins, 0 .. -63 dB (a median is the bin's upper end: -4.6 dB reads -4)
F.SPURT_FEAT_BINS = 101          -- per / nbr / lowr / zcr: 0.01 bins, 0 .. 1 (a median is the bin's lower end: .90)
F.EE_NEAR_LO, F.EE_NEAR_HI = 0.35, 0.55
F.SPURT_FEATS = { "loc", "per", "nbr", "lowr", "zcr" }
local function zero(h, n)
    for i = 0, n - 1 do h[i] = 0 end
    return h
end
function F.SpurtReset(sp)
    sp.n, sp.time = 0, 0
    sp.count, sp.f1, sp.f2, sp.fn = sp.count or {}, sp.f1 or {}, sp.f2 or {}, sp.fn or {}
    for c = 0, F.VISEME_COUNT - 1 do sp.count[c], sp.f1[c], sp.f2[c], sp.fn[c] = 0, 0, 0, 0 end
    sp.hs, sp.hr = sp.hs or {}, sp.hr or {}
    for i = 0, F.SPURT_BINS - 1 do sp.hs[i], sp.hr[i] = 0, 0 end
    sp.sound, sp.tail, sp.near = 0, 0, 0
    -- per raw class 1..8: { n, [1] = rel_loc bins, [2..5] = per / nbr / lowr / zcr bins }
    sp.feat = sp.feat or {}
    for c = 1, F.VISEME_COUNT - 1 do
        local fc = sp.feat[c]
        if not fc then
            fc = { n = 1 }
            for k = 1, 5 do fc[k] = {} end
            sp.feat[c] = fc
        end
        if fc.n > 0 then
            zero(fc[1], F.SPURT_LOC_BINS)
            for k = 2, 5 do zero(fc[k], F.SPURT_FEAT_BINS) end
            fc.n = 0
        end
    end
    return sp
end
local function bin_of(v)
    return math.min(math.max(math.floor((tonumber(v) or 0) * F.SPURT_BINS), 0), F.SPURT_BINS - 1)
end
-- a feature 0..1 -> its 0.01 bin (1e-6: 0.95 is 94.999... in binary)
local function feat_bin(v)
    return math.min(math.max(math.floor((tonumber(v) or 0) * 100 + 1e-6), 0), F.SPURT_FEAT_BINS - 1)
end
-- one frame of a spurt: the class counted (cls < 0: SIL), its F1 / F2 (Hz, 0 = none), the openness s, the level raw;
-- 0.9.4e, optional (gsa1.MicVisemeFeatures of the same frame): rel_loc (dB, <= 0), per, nbr, eep (the "ee" posterior),
-- rcls (the raw class), lowr, zcr - left out when the frame has none
function F.SpurtAdd(sp, cls, f1, f2, s, raw, dt, rel_loc, per, nbr, eep, rcls, lowr, zcr)
    if sp.n == nil or sp.feat == nil then F.SpurtReset(sp) end
    cls = tonumber(cls) or -1
    if cls < 0 or cls >= F.VISEME_COUNT then cls = F.SIL end
    cls = math.floor(cls)
    sp.n = sp.n + 1
    sp.time = sp.time + math.max(tonumber(dt) or 0, 0)
    sp.count[cls] = sp.count[cls] + 1
    f1, f2 = tonumber(f1) or 0, tonumber(f2) or 0
    if cls >= 2 and cls <= 6 and f1 > 0 and f2 > 0 then
        sp.f1[cls], sp.f2[cls], sp.fn[cls] = sp.f1[cls] + f1, sp.f2[cls] + f2, sp.fn[cls] + 1
    end
    if cls == F.SIL then
        sp.tail = sp.tail + 1
    else
        sp.tail = 0
        sp.sound = sp.sound + 1
        local i = bin_of(s)
        sp.hs[i] = sp.hs[i] + 1
        i = bin_of(raw)
        sp.hr[i] = sp.hr[i] + 1
    end
    rcls = tonumber(rcls)
    if rcls ~= nil and rcls >= 1 and rcls < F.VISEME_COUNT and rcls == math.floor(rcls) and tonumber(rel_loc) then
        local fc = sp.feat[rcls]
        fc.n = fc.n + 1
        local li = math.min(math.max(math.floor(-tonumber(rel_loc) + 1e-6), 0), F.SPURT_LOC_BINS - 1)
        fc[1][li] = fc[1][li] + 1
        local b = feat_bin(per)
        fc[2][b] = fc[2][b] + 1
        b = feat_bin(nbr)
        fc[3][b] = fc[3][b] + 1
        b = feat_bin(lowr)
        fc[4][b] = fc[4][b] + 1
        b = feat_bin(zcr)
        fc[5][b] = fc[5][b] + 1
    end
    eep = tonumber(eep)
    if eep and eep >= F.EE_NEAR_LO and eep <= F.EE_NEAR_HI and cls >= 2 and cls <= 6 and cls ~= 4 then
        sp.near = sp.near + 1
    end
end
-- the median bin of a histogram h[0 .. nb - 1] of n values (its index)
local function median_index(h, n, nb)
    if n <= 0 then return 0 end
    local acc = 0
    for i = 0, nb - 1 do
        acc = acc + (h[i] or 0)
        if acc * 2 >= n then return i end
    end
    return nb - 1
end
local function median_of(h, n)
    if n <= 0 then return 0 end
    return (median_index(h, n, F.SPURT_BINS) + 0.5) / F.SPURT_BINS
end
F.SpurtMedian = median_of
-- ".71" / "1.00"
local function frac2(v)
    local t = string.format("%.2f", v)
    if string.sub(t, 1, 2) == "0." then t = string.sub(t, 2) end
    return t
end
-- "lip sync spurt: 1.4 s, 84 frames (hearing 2, mouths G-SA1's v2): SIL 31% (closing pause 17%), MBP 6%, ...; F1/F2 Hz AA
-- 712/1240 n42, ...; loc/per/nbr/lowr/zcr MBP -9/.71/.55/.81/.06, ...; ee near 3; openness median 0.97, level median 0.71
-- (of 58 sound frames)" | nil (no frame). hearing (1 / 2) and mouths ("G-SA1's v2", "yours (ah, ee)"): the tags, optional
function F.SpurtLine(sp, hearing, mouths)
    if not sp.n or sp.n <= 0 then return nil end
    local parts = {}
    for c = 0, F.VISEME_COUNT - 1 do
        local p = string.format("%s %d%%", F.VISEME_NAMES[c], math.floor(100 * sp.count[c] / sp.n + 0.5))
        if c == F.SIL then
            p = p .. string.format(" (closing pause %d%%)", math.floor(100 * (sp.tail or 0) / sp.n + 0.5))
        end
        parts[#parts + 1] = p
    end
    local vow = {}
    for c = 2, 6 do
        if sp.fn[c] > 0 then
            vow[#vow + 1] = string.format("%s %d/%d n%d", F.VISEME_NAMES[c], math.floor(sp.f1[c] / sp.fn[c] + 0.5),
                math.floor(sp.f2[c] / sp.fn[c] + 0.5), sp.fn[c])
        end
    end
    local feats = {}
    for c = 1, F.VISEME_COUNT - 1 do
        local fc = sp.feat and sp.feat[c]
        if fc and fc.n > 0 then
            local nb = F.SPURT_FEAT_BINS
            feats[#feats + 1] = string.format("%s %d/%s/%s/%s/%s", F.VISEME_NAMES[c],
                -median_index(fc[1], fc.n, F.SPURT_LOC_BINS), frac2(median_index(fc[2], fc.n, nb) / 100),
                frac2(median_index(fc[3], fc.n, nb) / 100), frac2(median_index(fc[4], fc.n, nb) / 100),
                frac2(median_index(fc[5], fc.n, nb) / 100))
        end
    end
    local tags = ""
    if hearing ~= nil or mouths ~= nil then
        tags = string.format(" (hearing %s, mouths %s)", tostring(hearing or "?"), tostring(mouths or "?"))
    end
    local sound = sp.sound or 0
    return string.format("lip sync spurt: %.1f s, %d frames%s: %s; F1/F2 Hz %s; loc/per/nbr/lowr/zcr %s; ee near %d; "
        .. "openness median %.2f, level median %.2f (of %d sound frames)", sp.time, sp.n, tags, table.concat(parts, ", "),
        #vow > 0 and table.concat(vow, ", ") or "none", #feats > 0 and table.concat(feats, ", ") or "none", sp.near or 0,
        median_of(sp.hs, sound), median_of(sp.hr, sound), sound)
end

-- 0.9.4e, the guided warm-up "Teach it my vowels" (lipsync2_plan.md 4.4 with review R.1 / R.5): the page's steps, their
-- seconds, the prompt and the module call at each step's start (gsa1.MicVisemeWarmup). The module learns nothing in the
-- "ready" second and the gaps (phase 4); after "done" the page waits up to F.WARM_RESULT_WAIT s for the result. The page
-- keeps no number of it: only the result line's text (the owner's answer PQ7)
F.WARM_STEPS = {
    { step = "ready", secs = 1.0, text = "Get ready: say a long 'ahh' when the bar fills", call = "gap" },
    { step = "ah", secs = 2.0, text = "Say 'ahh' (as in 'father')", call = "ah" },
    { step = "gap", secs = 0.6, text = "Breathe", call = "gap" },
    { step = "ee", secs = 2.0, text = "Say 'eee' (as in 'see')", call = "ee" },
    { step = "gap", secs = 0.6, text = "Breathe", call = "gap" },
    { step = "oo", secs = 2.0, text = "Say your normal 'ooo' (as in 'you')", call = "oo" },
    { step = "gap", secs = 0.6, text = "Breathe", call = "gap" },
    { step = "oh", secs = 2.0, text = "Say 'ohh' (as in 'go')", call = "oh" },
    { step = "done", secs = 0, text = "Listening done: working it out", call = "done" },
}
F.WARM_RESULT_WAIT = 0.5
F.WARM_SECONDS = 0
for _, st in ipairs(F.WARM_STEPS) do F.WARM_SECONDS = F.WARM_SECONDS + st.secs end
-- the module's result codes (gsa1.MicVisemeWarmupState's 6th value) -> the page's line (review R.5: 4 "unclear")
F.WARM_LEARNED, F.WARM_SHORT, F.WARM_CANCELLED, F.WARM_UNCLEAR = 1, 2, 3, 4
F.WARM_RESULT_TEXT = {
    [1] = "Learned for this session. Talk normally: 'oo' and 'oh' should round better.",
    [2] = "Too short - say each sound for the whole two seconds",
    [3] = "Stopped",
    [4] = "The sounds did not come out as ah, ee and oo - try again, one sound per prompt",
}
F.WARM_LOG_WORD = { [1] = "learned", [2] = "too short", [3] = "stopped", [4] = "unclear" }

-- 0.9.4e, the mouth shape tester (lipsync2_plan.md 4.8; feat/cl_mouthtest.lua): a clicked mouth stays F.TESTER_KEEP s,
-- the tester lets go F.TESTER_LETGO s after nothing is pointed at, "Play all" shows each sound F.TESTER_PLAY s; "Show as"
-- normal / quiet / loud = the openness s and the variant gsa1.VisemeMouth gets (as talking draws them)
F.TESTER_KEEP = 20
F.TESTER_LETGO = 0.15
F.TESTER_PLAY = 0.5
F.TESTER_SHOW = 3                -- gsa1_mouth_show: seconds
F.TESTER_SOUNDS = { 1, 2, 3, 4, 5, 6, 7, 8 }   -- m b p, ah, eh, ee, oh, oo, s z sh, f v th
F.TESTER_SHOWAS = {
    [0] = { name = "normal", text = "normal talking", s = 1, variant = 0 },
    [1] = { name = "quiet", text = "quiet", s = 0.35, variant = 1 },
    [2] = { name = "loud", text = "loud", s = 1, variant = 2 },
}

-- the Faces page's "This character" line from gsa1.VisemeTable(kind) (phoneme_plan.md 5.5: rows [0..8] = { a, b, w, how =
-- "closed" / "scales" / "fixed" / "ladder", expression, quiet, loud, plain }; a, b, w named or in 1..3): "ah 4>16 (30 %),
-- eh / ee 0>4, oh 6>16 (40 %), oo 6, s z sh 0>4 (50 %), f v th: opens with the voice". Big (kind 7): his one shape.
local function entry_text(e)
    if type(e) ~= "table" then return "?" end
    local a, b, w = tonumber(e.a or e[1]) or 0, tonumber(e.b or e[2]) or 0, tonumber(e.w or e[3]) or 0
    if e.how == "ladder" or a < 0 then return ": opens with the voice" end
    if e.how == "closed" or (a == 0 and b == 0) then return " closed" end
    local t = (a == 0 and w >= 0.999) and tostring(b) or string.format("%d>%d", a, b)
    if w < 0.999 then t = t .. string.format(" (%d %%)", math.floor(w * 100 + 0.5)) end
    return " " .. t
end
-- 0.9.4e: a row of the player's own mouths (gsa1.VisemeTable's row.custom, feature "faces" 3) is marked "(yours)"
F.TableEntryText = entry_text
function F.TableText(t, kind)
    if tonumber(kind) == 7 then
        local text = "one mouth shape: it opens more or less with each sound"
        if type(t) == "table" then
            local mine = {}
            for c = 2, F.VISEME_COUNT - 1 do
                if type(t[c]) == "table" and t[c].custom == true then mine[#mine + 1] = F.VISEME_WORDS[c] end
            end
            if #mine > 0 then text = text .. " (yours: " .. table.concat(mine, ", ") .. ")" end
        end
        return text
    end
    if type(t) ~= "table" then return nil end
    local out, last = {}, nil
    for c = 2, F.VISEME_COUNT - 1 do
        local x = entry_text(t[c])
        if type(t[c]) == "table" and t[c].custom == true then x = x .. " (yours)" end
        if last and last.text == x then
            last.words = last.words .. " / " .. F.VISEME_WORDS[c]
        else
            last = { words = F.VISEME_WORDS[c], text = x }
            out[#out + 1] = last
        end
    end
    for i, o in ipairs(out) do out[i] = o.words .. o.text end
    return table.concat(out, ", ")
end
