-- G-SA1 jukebox (round 6c, J2): the pure functions of the jukebox, in both realms. No GMod call, no module call and no
-- state: the client's personal jukebox and its Q-menu page are cl_jukebox.lua (a world jukebox of a later round would
-- use these on the server too). Design: sadc docs/research/jukebox.md 6.5 with its review (R2.2, R2.3, R4 J2); plan
-- sadc docs/research/gsa1_rounds_plan.md 10.3; the module's functions (gsa1.MusicList, gsa1.Jukebox*) are 10.2's.
--
-- A track (GSA1.Jukebox.Normalize of gsa1.MusicList()'s entries, the music on the player's own disc):
--   music      the game's music number (0..109; 69 is not on the disc and never listed)
--   file       "ECOAST1.ADX"
--   title      the game's sound-test title, read from the disc by the module (nil when the sound test does not list it
--              or the disc's menus are not the supported version); name = title or file; label = "title (file)"
--   page, entry  the sound-test page 0..5 and the position on it (-1 when not listed); group = page + 1, or 7 (not in
--              the sound test)
--   seconds, rate  the length of the data present in the file (87 SSRACING.ADX is cut short on the disc) and Hz
--   loop, loop_start, loop_end  the file's own loop (the game's loop points), in seconds; no loop: loop false
--   listed, jingle (the game plays it over the stage music: 8C107C80), short (no loop and under 25 s: jingles and
--   title cards), truncated
GSA1 = GSA1 or {}
local J = {}
GSA1.Jukebox = J

J.SHORT_SECONDS = 25            -- no loop and shorter: a jingle or a title card (jukebox.md 1.5: 15 tracks)
J.PREV_RESTART_SECONDS = 3      -- "Previous" later than this into a track starts it again

-- the groups of the page: all, the game's six sound-test pages (jukebox.md 1.4; our names, the page captions are
-- textures), the tracks the sound test does not list
J.GROUP_ALL, J.GROUP_UNLISTED = 0, 7
J.GROUPS = {
    { id = 0, title = "All tracks" },
    { id = 1, title = "Sound test 1: songs and character themes" },
    { id = 2, title = "Sound test 2: action stages and bosses" },
    { id = 3, title = "Sound test 3: adventure fields and mini-games" },
    { id = 4, title = "Sound test 4: events and appearances" },
    { id = 5, title = "Sound test 5: menus and tutorials" },
    { id = 6, title = "Sound test 6: jingles and short pieces" },
    { id = 7, title = "Not in the sound test (file names)" },
}

-- play modes (gsa1_jukebox_mode)
J.MODE_REPEAT, J.MODE_LIST, J.MODE_SHUFFLE = 0, 1, 2
J.MODES = {
    { id = 0, title = "Repeat the track" },
    { id = 1, title = "Play the list" },
    { id = 2, title = "Shuffle" },
}

-- what is known about a track beyond the module's flags (numbers only; jukebox.md 1.5 and its review R2.3)
J.NOTES = {
    [102] = "a menu piece: the menus' music table plays it before the title music (which screen: unverified)",
}

local function truthy(v)
    if type(v) == "number" then return v ~= 0 end
    return v and true or false
end

local function trim_lower(s)
    return string.lower((string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")))
end

-- the sound test's order: its pages and their entries, then the tracks it does not list by number
function J.Before(a, b)
    if a.group ~= b.group then return a.group < b.group end
    if a.entry ~= b.entry then return a.entry < b.entry end
    return a.music < b.music
end

-- gsa1.MusicList()'s entries -> tracks (sorted as J.Before; t.index = the position), by music number. Tolerant: a
-- loop given in frames (libsa1's unit) is turned into seconds, pages 1..6 into 0..5, a missing `short` is computed;
-- entries that are not tables, have no number, are said not to be on the disc or repeat a number are left out.
function J.Normalize(list)
    local out, by = {}, {}
    if type(list) ~= "table" then return out, by end
    local minp, maxp = math.huge, -math.huge
    for _, e in ipairs(list) do
        local p = type(e) == "table" and tonumber(e.page) or nil
        if p and p >= 0 then minp, maxp = math.min(minp, p), math.max(maxp, p) end
    end
    local shift = (minp == 1 and maxp == 6) and 1 or 0
    for _, e in ipairs(list) do
        local music = type(e) == "table" and tonumber(e.music) or nil
        if music and music >= 0 and e.on_disc ~= false and not by[math.floor(music)] then
            local t = { music = math.floor(music) }
            t.file = type(e.file) == "string" and e.file ~= "" and e.file or ("MUSIC" .. t.music)
            t.title = type(e.title) == "string" and e.title ~= "" and e.title or nil
            t.rate = tonumber(e.rate or e.sample_rate) or 0
            local secs = tonumber(e.seconds or e.length)
            if not secs and tonumber(e.num_frames) and t.rate > 0 then secs = tonumber(e.num_frames) / t.rate end
            t.seconds = math.max(secs or 0, 0)
            t.loop = truthy(e.loop)
            if t.loop then
                local ls, le = tonumber(e.loop_start) or 0, tonumber(e.loop_end) or t.seconds
                if le > t.seconds + 1 and t.rate > 0 then ls, le = ls / t.rate, le / t.rate end   -- frames
                if le > ls and ls >= 0 then
                    t.loop_start, t.loop_end = ls, le
                else
                    t.loop = false
                end
            end
            local page = tonumber(e.page) or -1
            if page >= 0 then page = page - shift end
            if e.listed ~= nil then t.listed = truthy(e.listed) else t.listed = page >= 0 end
            if not t.listed or page < 0 or page > 5 then
                t.listed, t.page, t.entry = false, -1, -1
            else
                t.page, t.entry = page, math.max(math.floor(tonumber(e.entry) or 0), 0)
            end
            t.group = t.listed and (t.page + 1) or J.GROUP_UNLISTED
            t.jingle = truthy(e.jingle)
            t.truncated = truthy(e.truncated)
            if e.short ~= nil then
                t.short = truthy(e.short)
            else
                t.short = not t.loop and t.seconds < J.SHORT_SECONDS
            end
            t.name = t.title or t.file
            t.label = t.title and (t.title .. " (" .. t.file .. ")") or t.file
            out[#out + 1] = t
            by[t.music] = t
        end
    end
    table.sort(out, J.Before)
    for i, t in ipairs(out) do t.index = i end
    return out, by
end

-- the tracks a group shows (0 = all, 1..6 a sound-test page, 7 the unlisted ones), in the sound test's order. The
-- unlisted tracks show in "all" only with show_unlisted; their own group always shows them. Without any listed track
-- (the disc's menus not the supported version: no titles) every track is shown.
function J.Visible(tracks, group, show_unlisted)
    local out = {}
    group = tonumber(group) or 0
    local any_listed = false
    for _, t in ipairs(tracks or {}) do
        if t.listed then
            any_listed = true
            break
        end
    end
    for _, t in ipairs(tracks or {}) do
        local shown = t.listed or show_unlisted or group == J.GROUP_UNLISTED or not any_listed
        if shown and (group == J.GROUP_ALL or t.group == group or (not any_listed and group == J.GROUP_UNLISTED)) then
            out[#out + 1] = t
        end
    end
    return out
end

-- whether "play the list" and shuffle play a track: the short ones (jingles, title cards) only when include_short
function J.Playable(t, include_short)
    return include_short and true or not t.short
end

-- the visible tracks that the list and shuffle play
function J.Playlist(visible, include_short)
    local out = {}
    for _, t in ipairs(visible or {}) do
        if J.Playable(t, include_short) then out[#out + 1] = t end
    end
    return out
end

-- the track `step` places (1 next, -1 previous) after the track `music` in `list`, wrapping around, skipping the ones
-- ok(t) refuses; when `music` is not in the list: the first (next) or the last (previous) one ok accepts. nil when
-- none is; the track itself when it is the only one.
function J.Step(list, music, step, ok)
    local n = #(list or {})
    if n == 0 then return nil end
    step = (tonumber(step) or 1) < 0 and -1 or 1
    local start
    for i, t in ipairs(list) do
        if t.music == music then
            start = i
            break
        end
    end
    if not start then start = step > 0 and 0 or n + 1 end
    for k = 1, n do
        local t = list[(start - 1 + step * k) % n + 1]
        if not ok or ok(t) then return t end
    end
    return nil
end

-- a shuffled copy of `list` (Fisher-Yates; rand(n) -> an integer 1..n, math.random by default). The track `avoid` (a
-- music number) is not put first when there is another one, so no track plays twice in a row across a reshuffle.
function J.Shuffle(list, rand, avoid)
    rand = rand or math.random
    local out = {}
    for i, t in ipairs(list or {}) do out[i] = t end
    for i = #out, 2, -1 do
        local j = rand(i)
        out[i], out[j] = out[j], out[i]
    end
    if avoid ~= nil and #out > 1 and out[1].music == avoid then
        local j = 1 + rand(#out - 1)
        out[1], out[j] = out[j], out[1]
    end
    return out
end

-- shuffle's next track: every track of `list` once before any plays again. state = { key, order, pos } kept by the
-- caller; `key` names the list (a new key - another group, filter or track list - starts a new round without the
-- track `current`, which is playing); a used-up round is shuffled again, not starting with `current`.
function J.ShuffleNext(state, list, key, current, rand)
    if #(list or {}) == 0 then return nil end
    if state.key ~= key or type(state.order) ~= "table" then
        local rest = {}
        for _, t in ipairs(list) do
            if t.music ~= current then rest[#rest + 1] = t end
        end
        if #rest == 0 then rest = list end
        state.key, state.order, state.pos = key, J.Shuffle(rest, rand), 0
    end
    state.pos = (state.pos or 0) + 1
    if state.pos > #state.order then
        state.order, state.pos = J.Shuffle(list, rand, current), 1
    end
    return state.order[state.pos]
end

-- the module's plan for a track in a play mode, and its loops (1..10; the module takes 1 or more for every plan and
-- uses it with "loops" only):
--   repeat the track -> "forever": a looping track loops at the game's loop point, one without a loop starts again
--     from its beginning (a jukebox choice: the game's own sound test plays those once, review R2.2)
--   play the list / shuffle -> "loops" (loops times through the loop, then the fade-out) for a looping track, "once"
--     (to its end) for one without a loop
function J.PlanFor(t, mode, loops)
    if tonumber(mode) == J.MODE_REPEAT or not t then return "forever", 1 end
    if t.loop then return "loops", math.min(math.max(math.floor(tonumber(loops) or 2), 1), 10) end
    return "once", 1
end

-- seconds from the start of a plan to its end (fade included); nil: it never ends
function J.PlanLength(t, plan, loops, fade)
    if plan == "forever" then return nil end
    if plan == "loops" and t.loop then
        return t.loop_start + (tonumber(loops) or 1) * (t.loop_end - t.loop_start) + math.max(tonumber(fade) or 0, 0)
    end
    return t.seconds
end

-- where in the file the plan's time `pt` (seconds) is: a looping track (forever and loops) wraps from loop_end to
-- loop_start; "forever" of a track without a loop starts again at 0; "once" stops at the end
function J.TrackTime(t, plan, pt)
    pt = math.max(tonumber(pt) or 0, 0)
    if not t then return pt end
    if plan ~= "once" and t.loop and pt >= t.loop_end then
        return t.loop_start + (pt - t.loop_start) % (t.loop_end - t.loop_start)
    end
    if plan == "forever" and not t.loop and t.seconds > 0 then return pt % t.seconds end
    return math.min(pt, t.seconds)
end

-- how many times a looping plan has gone through the loop at plan time `pt`
function J.LoopsDone(t, pt)
    pt = tonumber(pt) or 0
    if not t or not t.loop or pt < t.loop_end then return 0 end
    return math.floor((pt - t.loop_start) / (t.loop_end - t.loop_start))
end

-- "1:52" ("1:02:05" from an hour on); whole seconds, rounded down
function J.FormatTime(s)
    s = math.max(math.floor(tonumber(s) or 0), 0)
    if s >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
    end
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- whether every word of `words` (lower case) is in the track's title or file name
function J.Matches(t, words)
    local hay = string.lower((t.title or "") .. " " .. t.file)
    for _, w in ipairs(words) do
        if not string.find(hay, w, 1, true) then return false end
    end
    return true
end

-- the words of a query, lower case
function J.Words(query)
    local words = {}
    for w in string.gmatch(trim_lower(query), "%S+") do words[#words + 1] = w end
    return words
end

-- a track by "28" (its number), "ecoast1" / "ECOAST1.ADX" (its file) or words of its title or file ("emerald 1");
-- returns the track (the first in the sound test's order), the number of tracks that match and their list
function J.Find(tracks, query)
    local q = trim_lower(query)
    if q == "" then return nil, 0, {} end
    if string.match(q, "^%d+$") then
        local n = tonumber(q)
        for _, t in ipairs(tracks or {}) do
            if t.music == n then return t, 1, { t } end
        end
        return nil, 0, {}
    end
    for _, t in ipairs(tracks or {}) do
        local f = string.lower(t.file)
        if f == q or f == q .. ".adx" then return t, 1, { t } end
    end
    local words, found = J.Words(q), {}
    for _, t in ipairs(tracks or {}) do
        if J.Matches(t, words) then found[#found + 1] = t end
    end
    return found[1], #found, found
end

-- "loops from 0:42" / "no loop"
function J.LoopText(t)
    if not t.loop then return "no loop" end
    return "loops from " .. J.FormatTime(t.loop_start)
end

-- one line of gsa1_jukebox_list: "28  Emerald Coast:  Type 1 (ECOAST1.ADX)  1:52, loops from 0:42"
function J.Line(t)
    local extra = {}
    if t.jingle then extra[#extra + 1] = "jingle" end
    if t.short then extra[#extra + 1] = "short" end
    if t.truncated then extra[#extra + 1] = "cut short on the disc" end
    return string.format("%3d  %s  %s, %s%s", t.music, t.label, J.FormatTime(t.seconds), J.LoopText(t),
        #extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or "")
end

-- a track's tooltip: what the jukebox does with it
function J.Describe(t)
    local n = {}
    n[#n + 1] = string.format("%d %s, %s, %d Hz", t.music, t.file, J.FormatTime(t.seconds), t.rate)
    if t.loop then
        n[#n + 1] = string.format("loops from %s to %s (the game's loop points)", J.FormatTime(t.loop_start),
            J.FormatTime(t.loop_end))
    else
        n[#n + 1] = "no loop: \"Repeat the track\" starts it again from its beginning"
    end
    if not t.listed then n[#n + 1] = "not in the game's sound test" end
    if J.NOTES[t.music] then n[#n + 1] = J.NOTES[t.music] end
    if t.truncated then n[#n + 1] = "cut short on the disc (the file holds less than its header says)" end
    if t.jingle then n[#n + 1] = "the game plays it as a jingle over the stage music" end
    if t.short then
        n[#n + 1] = "short: \"Play the list\" and \"Shuffle\" leave it out unless jingles and title cards are included"
    end
    return table.concat(n, "\n")
end

-- 0.9.1: the jukebox steps aside for the game's jingles (sadc docs/research/gsa1_070_drown.md J1, rules R1-R5, with its
-- review R4.4). The game plays a jingle - the drowning countdown, invincibility, speed shoes, Big's fishing - *instead
-- of* its stage music and stops all music at a drown; the jukebox stands in for the stage music, so while the game's
-- mixer has a jingle (gsa1.AudioMusicState().jingle >= 0), after its music stop (.stopped) and from the game's restart
-- request until the character has respawned, it holds: gsa1_jukebox_jingle 2 (the default) fades it out in 0.2 s and
-- pauses it where it is, 1 lowers it to 25 %, 0 keeps it playing; afterwards it fades back in over 0.5 s. The 1-up is
-- a sound effect (tone 704): it never holds the jukebox.
J.HOLD_KEEP, J.HOLD_LOWER, J.HOLD_PAUSE = 0, 1, 2
J.HOLD_MODES = {
    { id = 2, title = "Pause the jukebox (it carries on afterwards)" },
    { id = 1, title = "Lower the jukebox to 25 %" },
    { id = 0, title = "Keep playing" },
}
J.HOLD_FADE_OUT = 0.2           -- s from full to silent when a jingle starts
J.HOLD_FADE_IN = 0.5            -- s back to full afterwards
J.HOLD_FLOOR = 0.25             -- "lower": the jukebox's level during a jingle

-- the hold gain after dt seconds (1 = the jukebox at its level, 0 = silent)
function J.HoldGain(gain, hold, dt)
    gain = tonumber(gain) or 1
    dt = math.max(tonumber(dt) or 0, 0)
    if hold then return math.max(0, gain - dt / J.HOLD_FADE_OUT) end
    return math.min(1, gain + dt / J.HOLD_FADE_IN)
end

-- what the hold does in a mode: the music volume factor and whether the engine holds (pauses) the music
function J.HoldApply(mode, gain)
    if mode == J.HOLD_KEEP then return 1, false end
    if mode == J.HOLD_LOWER then return math.max(gain, J.HOLD_FLOOR), false end
    return gain, gain <= 0
end

-- why the jukebox holds, from the game's music state (gsa1.AudioMusicState's table or nil) and the respawn hold:
-- "jingle", "stopped", "restart" or nil
function J.HoldReason(ms, respawn_hold)
    if type(ms) == "table" then
        if (tonumber(ms.jingle) or -1) >= 0 then return "jingle" end
        if truthy(ms.stopped) then return "stopped" end
    end
    if respawn_hold then return "restart" end
    return nil
end
