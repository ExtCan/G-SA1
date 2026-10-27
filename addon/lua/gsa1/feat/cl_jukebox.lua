-- G-SA1 jukebox (round 6c, J2): your own jukebox - the music of Sonic Adventure from your disc, which only you hear -
-- and its page Q -> Options -> G-SA1 -> Jukebox. The module's jukebox engine (feature "jukebox", module 0.7.0:
-- src/core/jukebox.*, src/module/bind_jukebox.cpp) reads and decodes the music on a thread of its own with its own
-- libsa1 objects and keeps a few seconds queued in Garry's Mod's own audio output, so the music goes on through the
-- game's stutters; this file is the player around it: the track list, play / pause / stop / previous / next / seek, the
-- play modes (repeat the track, play the list, shuffle), silencing the game's music while the jukebox plays, and a
-- Think hook that hands the module the listener, the volumes and the pause state every frame (gsa1.JukeboxUpdate).
-- The pure functions (groups, next / previous, shuffle order, plans, times, search) are sh_jukebox.lua.
-- Design: sadc docs/research/jukebox.md 6.5 with its review (R2.2: the game's own sound test plays a track without a
-- loop once - repeating it is the jukebox's choice; R2.3; R4 J2); plan sadc docs/research/gsa1_rounds_plan.md 10.3;
-- the owner's defaults (plan 14.2): the 5 tracks the sound test does not list in their own group under their file
-- names, play mode "repeat the track", the drowning countdown (a jingle) stays audible while the game's music is
-- silenced. Nothing runs before the jukebox is first used (the page, a gsa1_jukebox_* command): no cost per frame.
-- The session log gets music numbers and file names only (lines "jukebox").
-- 0.9.1 (sadc docs/research/gsa1_070_drown.md J1, rules R1-R5, with its review R4.4; the owner's report "the music
-- doesn't duck"): the jukebox steps aside for the game's jingles - the drowning countdown, invincibility, speed shoes,
-- Big's fishing - as the game's own stage music does: from the game's music state in the module's mixer
-- (gsa1.AudioMusicState, feature "musicstate", libsa1 audio header 4) it fades out in 0.2 s and pauses where it is while
-- a jingle plays, after the game's music stop at a drown, and from the game's restart request until the character has
-- respawned (the hooks GSA1CharacterRestart / GSA1CharacterRespawned of cl_character.lua: the game's music comes back
-- one frame after the restart request, a second before the respawn); then it fades back in over 0.5 s.
-- gsa1_jukebox_jingle: 2 pause (default), 1 lower to 25 %, 0 keep playing. The 1-up (a sound effect) never holds it.
GSA1 = GSA1 or {}
local J = GSA1.Jukebox
if not J then error("gsa1/feat/sh_jukebox.lua did not load: the jukebox needs it") end

local P = {}
GSA1.JukeboxPlayer = P
P.NEEDS = { feature = "jukebox", version = 1, module = "0.7.0" }   -- what the page and the commands need
P.CH = 0                        -- the personal channel (2D; channels 1-4 are the engine's world channels, unused)
P.FUNCTIONS = { "MusicList", "JukeboxPlay", "JukeboxStop", "JukeboxPause", "JukeboxSeek", "JukeboxVolume",
                "JukeboxUpdate", "JukeboxState", "JukeboxStatus" }
P.used = false                  -- the jukebox has been used (the Think hook does nothing before)
P.version = 0                   -- +1 when a track list arrives (the page's list follows)
P.history = {}                  -- music numbers played (Previous in shuffle)
P.shuffle = {}                  -- J.ShuffleNext's state
P.duckGain, P.duckJingles, P.duckAgain = 1, false, 0
P.quietUntil, P.nextState, P.nextList = 0, 0, 0
P.startedAt, P.startPos, P.skips = 0, 0, 0
P.audible = 0
P.rand = nil                    -- J.Shuffle's random function (nil: math.random; the test sets its own)
-- 0.9.1 (J1): the step aside for the game's jingles
P.jgain = 1                     -- the hold's gain (J.HoldGain): 1 = the jukebox at its level
P.holdWhy = nil                 -- why it holds now ("jingle", "stopped", "restart"; nil: it does not)
P.respawnHold = false           -- from the game's restart request until the character has respawned
P.respawnHoldUntil = 0
P.holdT = nil                   -- the time of the last hold step
P.RESPAWN_HOLD_MAX = 15         -- s: a respawn hold ends by itself after this (the respawn never came)

local STATE_TEXT = { idle = "stopped", loading = "loading", playing = "playing", paused = "paused", ended = "ended",
                     failed = "failed" }

-- settings (every one has a control on the page) ---------------------------------------------------------------------
local cv = {
    mode         = GSA1.ConVar("gsa1_jukebox_mode", 0, "Jukebox play mode: 0 = repeat the track (a looping track "
        .. "loops at the game's loop point, one without a loop starts again; the game's own sound test plays those once), "
        .. "1 = play the list, 2 = shuffle", 0, 2),
    loops        = GSA1.ConVar("gsa1_jukebox_loops", 2, "Jukebox, play the list and shuffle: times through a looping "
        .. "track's loop before it fades out and the next track starts", 1, 10),
    fade         = GSA1.ConVar("gsa1_jukebox_fade", 4, "Jukebox, play the list and shuffle: fade-out in seconds at the "
        .. "end of a looping track", 0, 10),
    jingles      = GSA1.ConVar("gsa1_jukebox_jingles", 0, "Jukebox: play the list and shuffle include the jingles and "
        .. "title cards (the 15 tracks without a loop that are shorter than 25 s)", 0, 1),
    hidden       = GSA1.ConVar("gsa1_jukebox_hidden", 1, "Jukebox: show the 5 tracks that are not in the game's sound "
        .. "test (under their file names) among all tracks", 0, 1),
    volume       = GSA1.ConVar("gsa1_jukebox_volume", 1, "Jukebox volume (1 = the level the game plays its music at)",
        0, 1),
    duck         = GSA1.ConVar("gsa1_jukebox_duck", 1, "Silence the game's music while the jukebox plays (its jingles, "
        .. "like the drowning countdown, stay unless gsa1_jukebox_duck_jingles)", 0, 1),
    duck_jingles = GSA1.ConVar("gsa1_jukebox_duck_jingles", 0, "With gsa1_jukebox_duck: silence the game's jingles "
        .. "too (invincibility, speed up, the drowning countdown)", 0, 1),
    gmod_music   = GSA1.ConVar("gsa1_jukebox_gmod_music", 1, "The jukebox follows Garry's Mod's music volume "
        .. "(snd_musicvolume)", 0, 1),
    background   = GSA1.ConVar("gsa1_jukebox_background", 0, "The jukebox keeps playing while the game is paused or "
        .. "in the background", 0, 1),
    group        = GSA1.ConVar("gsa1_jukebox_group", 0, "Jukebox: the tracks the page shows and the list plays: 0 = "
        .. "all, 1-6 = the game's sound-test pages, 7 = the tracks the sound test does not list", 0, 7),
    jingle       = GSA1.ConVar("gsa1_jukebox_jingle", 2, "Jukebox while the game plays a jingle (the drowning "
        .. "countdown, invincibility, speed shoes, fishing) and after a drown until the character is back: 2 = pause it "
        .. "and carry on afterwards, 1 = lower it to 25 %, 0 = keep playing", 0, 2),
}
P.cv = cv

-- helpers --------------------------------------------------------------------------------------------------------------
local PREFIX_COLOR = Color(80, 160, 255)

-- a console line (titles come from your disc: they go to the console only, never into the session log)
local function say(...)
    MsgC(PREFIX_COLOR, "[G-SA1] ", color_white, string.format(...), "\n")
end

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("jukebox", fmt, ...) end
end

local function prof(t0)
    if GSA1.HitchAdd then GSA1.HitchAdd("Jukebox", SysTime() - t0) end
end

-- the loaded module has the jukebox (cheap: for the Think hook)
local function have()
    return GSA1.mod ~= nil and gsa1 ~= nil and gsa1.JukeboxUpdate ~= nil
end

-- whether the jukebox can work: true, or false and why (loads the module like the status lines do)
function P.Ready()
    local ok, v = GSA1.HasFeature(P.NEEDS.feature, P.NEEDS.version)
    if not ok then
        if not GSA1.mod then
            return false, "the jukebox needs the G-SA1 module: " .. tostring(GSA1.moduleError or "not loaded")
        end
        return false, string.format("the jukebox needs G-SA1 module %s or newer (module %s %s); install the module "
            .. "and the addon of the same G-SA1 version together", P.NEEDS.module, tostring(gsa1.VERSION),
            v and ("has version " .. tostring(v) .. " of it") or "has no jukebox")
    end
    for _, name in ipairs(P.FUNCTIONS) do
        if type(gsa1[name]) ~= "function" then
            return false, "the module's jukebox has no gsa1." .. name .. " (the module's feature errors are in the console)"
        end
    end
    return true
end

-- the track list (sh_jukebox.lua's tracks); nil, "loading" while the module reads it, nil, why otherwise. The first
-- call starts the module's jukebox engine.
function P.Tracks()
    if P.tracks then return P.tracks end
    local ok, why = P.Ready()
    if not ok then return nil, why end
    P.used = true
    local t0 = SysTime()
    local list, msg = gsa1.MusicList()
    prof(t0)
    if type(list) ~= "table" then
        P.listError = tostring(msg or "loading")
        return nil, P.listError
    end
    local tracks, by = J.Normalize(list)
    if #tracks == 0 then
        P.listError = "the module found no music on your disc"
        return nil, P.listError
    end
    P.tracks, P.by, P.listError = tracks, by, nil
    P.version = P.version + 1
    local listed = 0
    for _, t in ipairs(tracks) do
        if t.listed then listed = listed + 1 end
    end
    log("track list: %d tracks on the disc, %d of them in the game's sound test", #tracks, listed)
    return tracks
end

-- the plan time (seconds) the track is at: the engine's position, or until it answers the time since the start
function P.Position()
    local st = P.state
    if st and P.current ~= nil and tonumber(st.music) == P.current and tonumber(st.position) then
        return tonumber(st.position)
    end
    if P.paused or P.current == nil then return P.startPos end
    return P.startPos + (SysTime() - P.startedAt)
end

-- where in the file the track is (seconds): the engine's track_position, or the plan time folded like the engine does
function P.TrackPosition()
    if not P.track then return 0 end
    local st = P.state
    if st and tonumber(st.music) == P.current and tonumber(st.track_position) then
        return math.min(math.max(tonumber(st.track_position), 0), P.track.seconds)
    end
    return J.TrackTime(P.track, P.plan, P.Position())
end

-- playing ------------------------------------------------------------------------------------------------------------
-- plays track `music` on the personal channel from `start` seconds (the plan's time) with the play mode's plan.
-- opts.replan: the same track with another plan (not added to the history). Returns true, or false and why.
function P.Play(music, start, opts)
    local ok, why = P.Ready()
    if not ok then return false, why end
    local tracks, msg = P.Tracks()
    if not tracks then
        return false, msg == "loading" and "the track list is still loading from your disc" or msg
    end
    local t = P.by[tonumber(music) or -1]
    if not t then return false, string.format("there is no track %s on your disc", tostring(music)) end
    local plan, loops = J.PlanFor(t, cv.mode:GetInt(), cv.loops:GetInt())
    local fade = plan == "loops" and math.Clamp(cv.fade:GetFloat(), 0, 10) or 0
    start = math.max(tonumber(start) or 0, 0)
    local t0 = SysTime()
    gsa1.JukeboxVolume(P.CH, math.Clamp(cv.volume:GetFloat(), 0, 1))
    local res, err = gsa1.JukeboxPlay(P.CH, t.music, start, plan, loops, 0, fade)
    prof(t0)
    if not res then
        local m = tostring(err or "the module refused it")
        log("play %d %s refused: %s", t.music, t.file, m)
        return false, m
    end
    local now = SysTime()
    P.current, P.track, P.plan, P.planLoops, P.planFade = t.music, t, plan, loops, fade
    P.startedAt, P.startPos, P.paused, P.state, P.lastError = now, start, false, nil, nil
    P.nextState = now + 0.1
    P.last, P.used = t.music, true
    if not (opts and opts.replan) and P.history[#P.history] ~= t.music then
        P.history[#P.history + 1] = t.music
        if #P.history > 64 then table.remove(P.history, 1) end
    end
    log("play %d %s: %s%s from %.1f s", t.music, t.file, plan, plan == "loops" and (" " .. loops) or "", start)
    return true
end

-- stops the personal channel (fading out over `fade` seconds, 0.3 by default)
function P.Stop(fade)
    if not have() then return false, "the jukebox is not running" end
    gsa1.JukeboxStop(P.CH, math.Clamp(tonumber(fade) or 0.3, 0, 10))
    if P.current ~= nil then log("stop %d %s", P.current, P.track and P.track.file or "?") end
    P.current, P.track, P.state, P.paused = nil, nil, nil, false
    P.quietUntil = SysTime() + 2
    return true
end

-- pauses (on = true), resumes (false) or toggles (nil)
function P.Pause(on)
    if P.current == nil or not have() then return false, "nothing is playing" end
    if on == nil then on = not P.paused end
    on = on and true or false
    if on then P.startPos = P.Position() end
    gsa1.JukeboxPause(P.CH, on)
    if not on then P.startedAt = SysTime() end
    P.paused = on
    return true
end

-- goes to `t` seconds into the file
function P.Seek(t)
    if P.current == nil or not have() then return false, "nothing is playing" end
    t = math.Clamp(tonumber(t) or 0, 0, P.track and P.track.seconds or 0)
    gsa1.JukeboxSeek(P.CH, t)
    P.startedAt, P.startPos, P.state = SysTime(), t, nil
    P.nextState = SysTime() + 0.1
    return true
end

-- the track after (step 1) or before (-1) the current one in the page's group: the list's order (without the short
-- tracks unless they are included), or the shuffle's next one
function P.NextTrack(step)
    if not P.tracks then return nil end
    local visible = J.Visible(P.tracks, cv.group:GetInt(), cv.hidden:GetBool())
    local inc = cv.jingles:GetBool()
    local from = P.current
    if from == nil then from = P.last end
    if cv.mode:GetInt() == J.MODE_SHUFFLE and step > 0 then
        local list = J.Playlist(visible, inc)
        if #list == 0 then list = visible end
        local key = string.format("%d:%s:%s:%d:%d", cv.group:GetInt(), tostring(cv.hidden:GetBool()), tostring(inc),
            #list, P.version)
        return J.ShuffleNext(P.shuffle, list, key, from, P.rand)
    end
    return J.Step(visible, from, step, function(t) return J.Playable(t, inc) end) or J.Step(visible, from, step)
end

function P.Next()
    local tracks, msg = P.Tracks()
    if not tracks then return false, msg end
    local t = P.NextTrack(1)
    if not t then return false, "no track in this group" end
    return P.Play(t.music)
end

-- Previous: later than 3 s into a track it starts again; else the track before (shuffle: the one played before)
function P.Previous()
    local tracks, msg = P.Tracks()
    if not tracks then return false, msg end
    if P.current ~= nil and P.Position() > J.PREV_RESTART_SECONDS then return P.Seek(0) end
    if cv.mode:GetInt() == J.MODE_SHUFFLE and #P.history >= 2 then
        table.remove(P.history)
        return P.Play(P.history[#P.history])
    end
    local t = P.NextTrack(-1)
    if not t then return false, "no track in this group" end
    return P.Play(t.music)
end

-- the Play button: the selected track, a paused one resumed, else the last one or the first of the list
function P.PlayButton()
    if P.selected ~= nil and P.selected ~= P.current then
        local m = P.selected
        P.selected = nil
        return P.Play(m)
    end
    if P.current ~= nil then
        if P.paused then return P.Pause(false) end
        return true
    end
    local tracks, msg = P.Tracks()
    if not tracks then return false, msg end
    local m = P.last
    if m == nil then
        local t = P.NextTrack(1)
        m = t and t.music
    end
    if m == nil then return false, "no track in this group" end
    return P.Play(m)
end

-- "28", "ecoast1", words of a title; while the list loads the request waits for it
function P.PlayQuery(q)
    q = string.Trim(tostring(q or ""))
    if q == "" then return P.PlayButton() end
    local ok, why = P.Ready()
    if not ok then return false, why end
    local tracks, msg = P.Tracks()
    if not tracks then
        if msg == "loading" then
            P.pending, P.used = q, true
            return true, "the track list is loading from your disc; the track plays when it is there"
        end
        return false, msg
    end
    local t, n = J.Find(tracks, q)
    if not t then return false, "no track matches \"" .. q .. "\" (gsa1_jukebox_list shows them)" end
    local res, err = P.Play(t.music)
    if not res then return false, err end
    return true, string.format("playing %d %s%s", t.music, t.label, n > 1 and
        string.format(" (%d tracks match; the first one plays)", n) or "")
end

-- the engine's state of the personal channel (4 times a second while a track is on): the end of a track and errors
local function track_ended()
    local m
    if cv.mode:GetInt() == J.MODE_REPEAT then
        m = P.current                   -- a plan that ends (started in another mode): repeat means it starts again
    else
        local t = P.NextTrack(1)
        m = t and t.music
    end
    if m ~= nil then
        local ok, why = P.Play(m)
        if ok then return true end
        P.Stop(0)                       -- not again every quarter second
        P.lastError = tostring(why)
        return false
    end
    return P.Stop(0)
end

function P.Observe(st, now)
    P.state = st
    if tonumber(st.music) ~= P.current or now - P.startedAt < 0.5 then return end   -- the last command not taken yet
    local s = st.state
    if s == "playing" then
        P.skips = 0
    elseif s == "ended" then
        log("end %d %s", P.current, P.track and P.track.file or "?")
        track_ended()
    elseif s == "failed" then
        local err = tostring(st.error or "failed")
        local file = P.track and P.track.file or tostring(P.current)
        log("failed %d %s: %s", P.current, file, err)
        local shown = file .. ": " .. err
        P.skips = P.skips + 1
        if cv.mode:GetInt() ~= J.MODE_REPEAT and P.skips <= #(P.tracks or {}) then
            local t = P.NextTrack(1)
            if t and t.music ~= P.current and P.Play(t.music) then
                P.lastError = shown
                return
            end
        end
        P.current, P.track, P.paused, P.lastError = nil, nil, false, shown
        P.quietUntil = now + 2
    end
end

-- every frame -------------------------------------------------------------------------------------------------------
local cv_volume, cv_music, cv_focus
local function game_paused()
    return FrameTime() == 0 or (game.SinglePlayer() and gui.IsGameUIVisible())
end

-- the game's jingles (J1) ---------------------------------------------------------------------------------------------
-- how the game's last jingle ended (gsa1.MUSIC_STATE.END_*)
local END_TEXT = { [1] = "it played to its end", [2] = "the game went back to its music", [3] = "the game stopped its music",
                   [4] = "new background music", [5] = "another jingle", [6] = "its character went", [7] = "its file could "
                   .. "not be read" }
local HOLD_TEXT = { jingle = "jingle", stopped = "music stop", restart = "restart" }

local function hold_log(why, was, ms, mode)
    if P.current == nil then return end                    -- nothing of the jukebox plays: nothing held
    local verb = mode == J.HOLD_LOWER and "lowered" or "paused"
    if why == "jingle" then
        local j = tonumber(ms and ms.jingle) or -1
        local name = ms and type(ms.name) == "string" and ms.name ~= "" and ms.name or "?"
        log("%s for the game's jingle %d, %s", verb, j, GSA1.JINGLES and GSA1.JINGLES[j] or name)
    elseif why == "stopped" then
        log("%s: the game stopped its music (a drown); it waits until the character is back", verb)
    elseif why == "restart" then
        log("%s until the character respawns (the game asked for the restart)", verb)
    else
        local how = ms and was == "jingle" and END_TEXT[tonumber(ms.last_end) or 0] or nil
        log("back after the game's %s%s", HOLD_TEXT[was] or "music", how and (" (" .. how .. ")") or "")
    end
end

-- one step of the hold: the music volume factor and whether the engine holds the music (the game's pause is the
-- engine's own; the user's pause stays the user's)
local ms_out = {}
function P.HoldStep(now, mode)
    if P.respawnHold and now >= P.respawnHoldUntil then P.respawnHold = false end
    local ms = nil
    if gsa1.AudioMusicState then
        local r = gsa1.AudioMusicState(ms_out)
        if type(r) == "table" then ms = r end
    end
    P.music = ms
    local why = J.HoldReason(ms, P.respawnHold)
    if mode == J.HOLD_KEEP then why = nil end
    local dt = P.holdT and math.Clamp(now - P.holdT, 0, 0.25) or 0
    P.holdT = now
    P.jgain = J.HoldGain(P.jgain, why ~= nil, dt)
    if why ~= P.holdWhy then
        hold_log(why, P.holdWhy, ms, mode)
        P.holdWhy = why
    end
    return J.HoldApply(mode, P.jgain)
end

-- the game asked for the restart (a death): the jukebox waits for the respawn (review R4.4: the game's music comes back
-- one frame after the request, a second before the character does)
hook.Add("GSA1CharacterRestart", "gsa1_jukebox", function()
    P.respawnHold = true
    P.respawnHoldUntil = SysTime() + P.RESPAWN_HOLD_MAX
end)
hook.Add("GSA1CharacterRespawned", "gsa1_jukebox", function() P.respawnHold = false end)
hook.Add("GSA1CharacterRemoved", "gsa1_jukebox", function() P.respawnHold = false end)

-- the listener, volumes and pause to the module; the game's music silenced while the jukebox is heard
local function update(now)
    local v = GSA1.view
    local origin, ang
    if v and v.frame and v.origin and v.angles and FrameNumber() - v.frame <= 2 then
        origin, ang = v.origin, v.angles
    else
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        origin, ang = ply:EyePos(), ply:EyeAngles()
    end
    cv_volume = cv_volume or GetConVar("volume")
    cv_music = cv_music or GetConVar("snd_musicvolume")
    cv_focus = cv_focus or GetConVar("snd_mute_losefocus")
    local paused = false
    if not cv.background:GetBool() then
        paused = game_paused() or (cv_focus ~= nil and cv_focus:GetBool() and not system.HasFocus())
    end
    local music = 1
    if cv.gmod_music:GetBool() and cv_music then music = math.Clamp(cv_music:GetFloat(), 0, 1) end
    -- the game's jingles (J1): faded out and held (or lowered) while the game plays one
    local factor, hold = P.HoldStep(now, cv.jingle:GetInt())
    local n = tonumber(gsa1.JukeboxUpdate(origin, ang:Forward(), ang:Up(), cv_volume and cv_volume:GetFloat() or 1,
        music * factor, (paused or hold) and true or false)) or 0
    P.audible = n
    if gsa1.AudioDuck then
        -- held for a jingle the jukebox still counts as playing: the game's own music stays silenced
        local playing = n > 0 or (P.holdWhy ~= nil and P.current ~= nil and not P.paused and not paused)
        local want = (cv.duck:GetBool() and playing) and 0 or 1
        local dj = cv.duck_jingles:GetBool()
        if want ~= P.duckGain or (want < 1 and (dj ~= P.duckJingles or now >= P.duckAgain)) then
            gsa1.AudioDuck(want, dj)
            if want ~= P.duckGain then
                log(want < 1 and "the game's music silenced%s" or "the game's music back%s",
                    dj and " (and its jingles)" or "")
            end
            P.duckGain, P.duckJingles, P.duckAgain = want, dj, now + 1
        end
    end
end

local function think()
    if not P.used or not have() then return end
    local now = SysTime()
    if P.tracks == nil and (P.wantList or P.pending) and now >= P.nextList then
        local tracks, msg = P.Tracks()
        P.nextList = now + ((tracks or msg == "loading") and 0.25 or 2)
        if tracks and P.pending then
            local q = P.pending
            P.pending = nil
            local ok, m = P.PlayQuery(q)
            if m then say("jukebox: %s", m) end
            if not ok then P.lastError = m end
        elseif not tracks and msg ~= "loading" and P.pending then
            P.pending = nil
            say("jukebox: %s", tostring(msg))
        end
    end
    if P.current ~= nil or P.duckGain < 1 or now < P.quietUntil then
        local t0 = SysTime()
        update(now)
        if P.current ~= nil and now >= P.nextState then
            P.nextState = now + 0.25
            P.stateOut = P.stateOut or {}
            local st = gsa1.JukeboxState(P.CH, P.stateOut)      -- filled in place: no garbage
            if type(st) == "table" then P.Observe(st, now) end
        end
        prof(t0)
    end
end
hook.Add("Think", "gsa1_jukebox", GSA1.Guard and GSA1.Guard("Jukebox", think) or think)

-- settings that act at once: the volume, and the play mode (the playing track gets the new mode's plan where it is in
-- the file; loops and fade-out apply from the next track)
cvars.AddChangeCallback("gsa1_jukebox_volume", function(_, _, new)
    if P.used and have() then gsa1.JukeboxVolume(P.CH, math.Clamp(tonumber(new) or 1, 0, 1)) end
end, "gsa1_jukebox")
cvars.AddChangeCallback("gsa1_jukebox_mode", function()
    if P.current == nil or not P.track or not have() then return end
    local plan = J.PlanFor(P.track, cv.mode:GetInt(), cv.loops:GetInt())
    if plan == P.plan then return end
    local was_paused = P.paused
    if P.Play(P.current, P.TrackPosition(), { replan = true }) and was_paused then P.Pause(true) end
end, "gsa1_jukebox")

-- read-outs ------------------------------------------------------------------------------------------------------------
-- the page's "now playing" lines
function P.NowLines()
    local out = {}
    if P.current == nil or not P.track then
        if P.lastError then
            out[1] = "Not playing: " .. P.lastError
        elseif not P.tracks then
            out[1] = (P.listError == nil or P.listError == "loading") and "Reading the track list from your disc ..."
                or ("No track list: " .. P.listError)
        else
            out[1] = "Not playing. Double-click a track below."
        end
        return out
    end
    local t = P.track
    out[1] = t.label
    local st = P.state
    local s = (st and tonumber(st.music) == P.current and st.state) or "loading"
    if P.paused and s ~= "failed" then s = "paused" end
    out[2] = J.FormatTime(P.TrackPosition()) .. " / " .. J.FormatTime(t.seconds) .. ", " .. J.LoopText(t)
    local what
    if P.plan == "forever" then
        what = t.loop and "repeat: it loops at the game's loop point" or "repeat: it starts again at its end"
    elseif P.plan == "loops" then
        local done = st and tonumber(st.loops_done) or J.LoopsDone(t, P.Position())
        what = string.format("loop %d of %d, then the next track", math.min(done + 1, P.planLoops), P.planLoops)
    else
        what = "once, then the next track"
    end
    out[3] = (STATE_TEXT[s] or tostring(s)) .. " - " .. what
    if s == "failed" then out[3] = "failed: " .. tostring(st and st.error or "?") end
    if P.lastError then out[4] = "(" .. P.lastError .. ")" end
    return out
end

-- the page's status lines (the module's jukebox engine)
function P.StatusLines()
    local ok, why = P.Ready()
    if not ok then return { tostring(why) } end
    P.statusOut = P.statusOut or {}
    local s = gsa1.JukeboxStatus(P.statusOut)
    if type(s) ~= "table" then s = {} end
    local out = {}
    local err = (type(s.error) == "string" and s.error ~= "") and s.error or nil
    if s.ready then
        local rec = tonumber(s.recoveries) or 0
        out[1] = string.format("engine ready: %d tracks%s, %d playing, %.1f MB, slowest disc open %.0f ms, %d underruns%s",
            tonumber(s.tracks) or 0, tonumber(s.list_ms) and string.format(" (listed in %.0f ms)", s.list_ms) or "",
            tonumber(s.active) or 0, tonumber(s.memory_mb) or 0, tonumber(s.max_open_ms) or 0,
            tonumber(s.underruns) or 0, rec > 0 and string.format(", %d output recoveries", rec) or "")
        if err then out[2] = "last error: " .. err end
    else
        out[1] = "engine: " .. (err and ("not running: " .. err) or "starting (reading the track list from your disc)")
    end
    if P.tracks then
        local listed = 0
        for _, t in ipairs(P.tracks) do
            if t.listed then listed = listed + 1 end
        end
        out[#out + 1] = string.format("tracks: %d on your disc, %d of them in the game's sound test", #P.tracks, listed)
    end
    out[#out + 1] = P.duckGain < 1 and ("the game's music" .. (P.duckJingles and " and jingles are" or " is")
        .. " silenced while the jukebox plays") or "the game's music: not silenced"
    local mode = cv.jingle:GetInt()
    if P.holdWhy then
        out[#out + 1] = string.format("%s for the game's %s", mode == J.HOLD_LOWER and "lowered" or "paused",
            HOLD_TEXT[P.holdWhy] or "music")
    else
        out[#out + 1] = mode == J.HOLD_KEEP and "the game's jingles: the jukebox keeps playing" or
            (gsa1.AudioMusicState and "the game's jingles: none playing" or
             "the game's jingles: this module cannot tell (it needs G-SA1 module 0.9.1)")
    end
    return out
end

-- console ------------------------------------------------------------------------------------------------------------
local function report(ok, msg)
    if msg then say("jukebox: %s", tostring(msg)) end
    if ok == false and msg then P.lastError = tostring(msg) end
end

local function complete(cmd, argstr)
    local typed = string.lower(string.Trim(argstr or ""))
    local out = {}
    for _, t in ipairs(P.tracks or {}) do
        local f = string.lower((string.gsub(t.file, "%.[Aa][Dd][Xx]$", "")))
        if typed == "" or string.sub(f, 1, #typed) == typed then out[#out + 1] = cmd .. " " .. f end
        if #out >= 40 then break end
    end
    return out
end

concommand.Add("gsa1_jukebox_play", function(ply, cmd, args, argstr)
    report(P.PlayQuery(argstr or table.concat(args or {}, " ")))
end, complete, "G-SA1 jukebox: play a track - its number (28), its file (ecoast1) or words of its title; without an "
    .. "argument: the selected or last track, or resume")
concommand.Add("gsa1_jukebox_stop", function() report(P.Stop()) end, nil, "G-SA1 jukebox: stop")
concommand.Add("gsa1_jukebox_pause", function(ply, cmd, args)
    local a, on = args and args[1], nil
    if a ~= nil and a ~= "" then on = tonumber(a) ~= 0 end
    report(P.Pause(on))
end, nil, "G-SA1 jukebox: pause or resume (1 = pause, 0 = resume, nothing = toggle)")
concommand.Add("gsa1_jukebox_next", function() report(P.Next()) end, nil, "G-SA1 jukebox: the next track")
concommand.Add("gsa1_jukebox_prev", function() report(P.Previous()) end, nil,
    "G-SA1 jukebox: the track before (later than 3 s into a track: start it again)")
concommand.Add("gsa1_jukebox_list", function(ply, cmd, args, argstr)
    local tracks, msg = P.Tracks()
    if not tracks then
        P.wantList = true
        say("jukebox: %s", msg == "loading" and "the track list is still loading from your disc; try again in a moment"
            or tostring(msg))
        return
    end
    local words = J.Words(argstr or table.concat(args or {}, " "))
    local n = 0
    for _, g in ipairs(J.GROUPS) do
        if g.id ~= J.GROUP_ALL then
            local first = true
            for _, t in ipairs(tracks) do
                if t.group == g.id and J.Matches(t, words) then
                    if first then
                        say("%s", g.title)
                        first = false
                    end
                    say("  %s", J.Line(t))
                    n = n + 1
                end
            end
        end
    end
    say("jukebox: %d of %d tracks; gsa1_jukebox_play <number | file | words of the title> plays one", n, #tracks)
end, nil, "G-SA1 jukebox: list the tracks on your disc (optionally those matching words of the title or file)")

-- the page: Q -> Options -> G-SA1 -> Jukebox ---------------------------------------------------------------------------
-- a label showing lines_fn() and refreshing itself every `interval` seconds while it is visible
local function live_label(panel, interval, lines_fn)
    local lbl = panel:Help("...")
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + interval
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

-- a combo box for a ConVar whose values have titles ({ {title, value}, ... }): it shows the ConVar's value, also after
-- a change from the console, and sets the ConVar when a choice is picked
local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[1], c[2]) end
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand(cvname, tostring(data))
    end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local c = GetConVar(cvname)
        local v = c and c:GetString() or ""
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        local n = tonumber(v)
        for _, ch in ipairs(choices) do
            if ch[2] == v or (n ~= nil and tonumber(ch[2]) == n) then
                self:SetText(ch[1])
                return
            end
        end
        self:SetText(v)
    end
    return combo
end

-- a button's action: a refusal shows on the page and in the console
local function act(fn)
    return function()
        local ok, msg = fn()
        if ok == false then report(false, msg) end
    end
end

-- Previous, Play, Pause / Resume, Stop, Next in one row
local function transport(panel)
    local row = vgui.Create("DPanel")
    row:SetTall(24)
    row:SetPaintBackground(false)
    local defs = {
        { "Previous", act(P.Previous) },
        { "Play", act(P.PlayButton) },
        { "Pause", act(function() return P.Pause() end) },
        { "Stop", act(function() return P.Stop() end) },
        { "Next", act(P.Next) },
    }
    local buttons = {}
    for i, d in ipairs(defs) do
        local b = vgui.Create("DButton", row)
        b:SetText(d[1])
        b.DoClick = d[2]
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
    local pause = buttons[3]
    local baseThink = pause.Think
    pause.Think = function(self)
        if baseThink then baseThink(self) end
        local text = P.paused and "Resume" or "Pause"
        if text ~= self.gsa1Text then
            self.gsa1Text = text
            self:SetText(text)
        end
    end
    panel:AddItem(row)
    return row
end

-- the position in the track: follows the music; dragging (or typing) it seeks when it is let go
local function seek_slider(panel)
    local seek = panel:NumSlider("Position (seconds)", nil, 0, 1, 0)
    seek.OnValueChanged = function() end      -- a seek happens when the slider is let go (below)
    local baseThink = seek.Think
    seek.Think = function(self)
        if baseThink then baseThink(self) end
        if self:IsEditing() then
            self.gsa1Edit = true
            return
        end
        local now = RealTime()
        if self.gsa1Edit then
            self.gsa1Edit = false
            if P.current ~= nil then report(P.Seek(self:GetValue())) end
            self.gsa1Hold = now + 0.75        -- the engine's position follows a moment later
            return
        end
        if now < (self.gsa1Hold or 0) or now < (self.gsa1Next or 0) then return end
        self.gsa1Next = now + 0.25
        local len = P.track and math.max(math.floor(P.track.seconds), 1) or 1
        if len ~= self.gsa1Max then
            self.gsa1Max = len
            self:SetMax(len)
        end
        local pos = math.floor(P.TrackPosition())
        if pos ~= self.gsa1Pos then
            self.gsa1Pos = pos
            self:SetValue(pos)
        end
    end
    return seek
end

-- the track list of the group (number, title, length, loop start); double-click plays, a selected line plays with Play
local function track_list(panel)
    local list = vgui.Create("DListView")
    list:SetMultiSelect(false)
    list:SetTall(330)
    list:AddColumn("No."):SetFixedWidth(32)
    list:AddColumn("Title")
    list:AddColumn("Length"):SetFixedWidth(44)
    list:AddColumn("Loops from"):SetFixedWidth(62)
    list.DoDoubleClick = function(self, id, line)
        if line and line.gsa1Music ~= nil then
            P.selected = nil
            report(P.Play(line.gsa1Music))
        end
    end
    list.OnRowSelected = function(self, id, line)
        if line and line.gsa1Music ~= nil then P.selected = line.gsa1Music end
    end
    local function title_of(t)
        return (t.music == P.current and "> " or "") .. t.name
    end
    local function rebuild(self)
        self:Clear()
        self.gsa1Lines = {}
        local tracks = P.tracks
        if not tracks then
            self:AddLine("", (P.listError == nil or P.listError == "loading") and "Reading the track list from your "
                .. "disc ..." or tostring(P.listError), "", "")
            return
        end
        for _, t in ipairs(J.Visible(tracks, cv.group:GetInt(), cv.hidden:GetBool())) do
            local line = self:AddLine(tostring(t.music), title_of(t), J.FormatTime(t.seconds),
                t.loop and J.FormatTime(t.loop_start) or "no loop")
            line:SetSortValue(1, t.music)
            line:SetSortValue(3, t.seconds)
            line:SetSortValue(4, t.loop and t.loop_start or -1)
            line:SetTooltip(J.Describe(t))
            line.gsa1Music = t.music
            self.gsa1Lines[t.music] = line
        end
    end
    local baseThink = list.Think
    list.Think = function(self)
        if baseThink then baseThink(self) end
        local group, hidden = cv.group:GetInt(), cv.hidden:GetBool()
        if self.gsa1Version ~= P.version or self.gsa1Group ~= group or self.gsa1Hidden ~= hidden or
            (P.tracks == nil and self.gsa1Error ~= P.listError) then
            self.gsa1Version, self.gsa1Group, self.gsa1Hidden, self.gsa1Error = P.version, group, hidden, P.listError
            self.gsa1Playing = P.current
            rebuild(self)
            return
        end
        if self.gsa1Playing ~= P.current then
            -- the "> " mark moves to the playing track
            for _, m in ipairs({ self.gsa1Playing or -1, P.current or -1 }) do
                local line = self.gsa1Lines and self.gsa1Lines[m]
                local t = P.by and P.by[m]
                if line and t then line:SetColumnText(2, title_of(t)) end
            end
            self.gsa1Playing = P.current
        end
    end
    panel:AddItem(list)
    return list
end

local function page(panel)
    P.wantList, P.used = true, true
    P.Tracks()                         -- the module's jukebox engine starts and reads the track list from the disc
    panel:Help("Your own jukebox: the music of Sonic Adventure from your disc, played by the module on a thread of its "
        .. "own, so it keeps playing through the game's stutters. Only you hear it. It needs no character, and the "
        .. "game's sound (Sound page) may be off.")
    panel:Help("Now playing")
    live_label(panel, 0.25, P.NowLines)
    transport(panel)
    seek_slider(panel)
    local groups = {}
    for _, g in ipairs(J.GROUPS) do groups[#groups + 1] = { g.title, tostring(g.id) } end
    choice_combo(panel, "Tracks", "gsa1_jukebox_group", groups)
    track_list(panel)
    panel:ControlHelp("Double-click a track to play it, or select it and press Play. The titles are the game's own "
        .. "sound test's, read from your disc; the number is the game's music number (gsa1_jukebox_play 28). Hover a "
        .. "track for its loop and notes.")
    panel:Help("Playing")
    local modes = {}
    for _, m in ipairs(J.MODES) do modes[#modes + 1] = { m.title, tostring(m.id) } end
    local mode = choice_combo(panel, "Play mode", "gsa1_jukebox_mode", modes)
    mode:SetTooltip("Repeat the track: a looping track loops at the game's own loop point for as long as you like; a "
        .. "track without a loop starts again from its beginning (the game's own sound test plays those once and stops).")
    panel:ControlHelp("Repeat the track (the default): a looping track loops at the game's loop point; one without a "
        .. "loop starts again (the game's own sound test plays those once). Play the list: the tracks of the group above "
        .. "in the sound test's order, round and round. Shuffle: every track of the group once, in a random order, then "
        .. "again.")
    panel:NumSlider("Loops before the next track", "gsa1_jukebox_loops", 1, 10, 0)
    panel:ControlHelp("Play the list and shuffle: times through a looping track's loop, then it fades out and the next "
        .. "one starts; a track without a loop plays once. Applies from the next track.")
    panel:NumSlider("Fade-out at the end (seconds)", "gsa1_jukebox_fade", 0, 10, 1)
    panel:CheckBox("Include jingles and title cards in the list and shuffle", "gsa1_jukebox_jingles")
    panel:ControlHelp("The 15 short tracks without a loop (jingles such as the item and speed-up tunes, the stage "
        .. "title cards). Double-clicking one plays it either way.")
    panel:CheckBox("Show the tracks that are not in the game's sound test", "gsa1_jukebox_hidden")
    panel:ControlHelp("5 files on your disc that the sound test does not list, under their file names (their own group "
        .. "always shows them). SSRACING.ADX is cut short on the disc; TITLE2.ADX is a piece of the menus.")
    panel:Help("Volume")
    panel:NumSlider("Jukebox volume", "gsa1_jukebox_volume", 0, 1, 2)
    panel:ControlHelp("1 = the level the game plays its music at. Garry's Mod's own volume applies too.")
    panel:CheckBox("Follow Garry's Mod's music volume", "gsa1_jukebox_gmod_music")
    panel:ControlHelp("Garry's Mod's music volume (snd_musicvolume, in its audio options) scales the jukebox too.")
    panel:CheckBox("Silence the game's music while the jukebox plays", "gsa1_jukebox_duck")
    panel:ControlHelp("The characters' own music (Sound page: background music) fades out while you hear the jukebox and "
        .. "back in when it stops. The jingles stay - so the drowning countdown still warns you - unless the next box is "
        .. "ticked.")
    panel:CheckBox("... and the game's jingles (the drowning countdown too)", "gsa1_jukebox_duck_jingles")
    local holds = {}
    for _, m in ipairs(J.HOLD_MODES) do holds[#holds + 1] = { m.title, tostring(m.id) } end
    choice_combo(panel, "When the game plays a jingle", "gsa1_jukebox_jingle", holds)
    panel:ControlHelp("The game's jingles - the drowning countdown, invincibility, speed shoes, Big's fishing - replace "
        .. "its stage music for a while, and a drown stops all music until the character is back. Pause (the "
        .. "default): the jukebox fades out, waits where it is and carries on afterwards. Lower: it plays on at a "
        .. "quarter of its level. Keep playing: it ignores them. The 1-up sound never stops it.")
    panel:CheckBox("Keep playing while the game is paused or in the background", "gsa1_jukebox_background")
    panel:ControlHelp("Off: the jukebox pauses with the escape menu (single player) and, when Garry's Mod mutes its "
        .. "sound out of focus (snd_mute_losefocus), while you are in another window.")
    panel:Help("Status")
    live_label(panel, 0.5, P.StatusLines)
    panel:ControlHelp("Console: gsa1_jukebox_play <number | file | words of the title>, gsa1_jukebox_pause, "
        .. "gsa1_jukebox_stop, gsa1_jukebox_next, gsa1_jukebox_prev, gsa1_jukebox_list [words]; every setting is a "
        .. "gsa1_jukebox_* ConVar.")
end

GSA1.AddMenuPage(400, "jukebox", "Jukebox", page, P.NEEDS)
