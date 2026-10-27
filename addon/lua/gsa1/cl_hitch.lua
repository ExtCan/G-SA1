-- G-SA1 client: the hitch logger (sadc docs/research/gsa1_ramp_freeze.md fix 11). The owner saw "random freezes" that
-- could not be reproduced offline; when a frame takes longer than gsa1_hitch_ms (100 ms), this prints which part of
-- G-SA1 took the time in that frame - or that it was not G-SA1 - so the next report names the freeze:
--   [G-SA1] hitch: a frame took 312 ms; G-SA1 297.0 ms: LoadWorld 290.1, Tick 4.2, EmitBatch 2.1, ... (15 ms elsewhere)
-- The sections are timed where they run (GSA1.HitchAdd); a frame is the time from one Think of cl_character.lua to
-- the next, so it holds that Think (tick, render, sound, controller, map loading, moving objects) and the drawing and
-- texture painting of the frame before it. Frames while Garry's Mod is not focused (alt-tab) are not reported.
-- 0.5.1 sections: Init (gsa1.Init / InitPoll: the disc loads on a worker), Sound (AudioOpen / AudioPoll: the sound
-- banks open on a worker), Apply (MapApply: the prepared collision installed), Create (gsa1.Create), Textures (a new
-- character's texture list), Texture info (the texture infos, at most about 3 ms per frame). 0.6.0: Materials (a
-- material made at its first use), Warm (the material pre-warm, cl_warm.lua), Texture target (a render target made at
-- its first use).
-- Session log (cl_log.lua, sadc docs/research/gsa1_lsd_lag.md section 6): every frame also goes to GSA1.LogFrame
-- (frame-time histogram, stutters, 10-second performance lines, slow seconds) with the change of the Lua heap over the
-- frame, and every frame over gsa1_log_hitch_ms (50 ms) is written into garrysmod/data/gsa1/log.txt with its breakdown
-- and what the character was doing; the console line keeps its own threshold (gsa1_hitch_ms) and its 2-second quiet
-- time. Two section tables are swapped every frame (no garbage per frame).
-- 0.8.0, pauses are not hitches (sadc docs/research/gsa1_060_pops.md F3 with its review): Think does not run while
-- single player is paused (escape menu, console), but the world is still drawn, so the next Think saw one "frame" as
-- long as the pause - 0.6.0's log had 11-45 s hitch lines whose EmitBatch summed 300-1000 ms of ordinary draws. A
-- PostRender hook counts the frames drawn between two Thinks and notes the escape menu and the focus in each. A frame
-- with the escape menu or without the focus in it, or one of over 0.25 s drawn several times without a Think, is a
-- pause: no hitch line, not in the frame statistics, one "pause" line in the session log when it lasted a second or
-- more, and the jump detector starts a new chain after it (cl_log.lua). The character's tick after a pause runs no
-- time (GSA1.Hitch.tickPaused, read by cl_character.lua): 0.6.0 ticked 0.25 s at once there, 7-8 game pairs the player
-- never saw (gsa1_060_pops.md R.4). UNVERIFIED in game: that PostRender runs while single player is paused (inferred
-- from the pause frames' EmitBatch sums).
GSA1 = GSA1 or {}
GSA1.Hitch = GSA1.Hitch or { cur = {}, spare = {}, last = nil, quiet = 0, count = 0, worst = 0, gc = nil }
local H = GSA1.Hitch
H.spare = H.spare or {}
H.drawn, H.uiSeen, H.unfocusedSeen, H.tickPaused = H.drawn or 0, false, false, false
local PAUSE_DRAWN = 3            -- more frames than this drawn without a Think, in a frame of over PAUSE_S: a pause
local PAUSE_S = 0.25

-- every drawn frame, also while single player is paused (the world is still drawn then)
hook.Add("PostRender", "gsa1_hitch_pause", function()
    H.drawn = H.drawn + 1
    if gui.IsGameUIVisible and gui.IsGameUIVisible() then H.uiSeen = true end
    if not system.HasFocus() then H.unfocusedSeen = true end
end)

-- the order the sections are printed in
local ORDER = { "Init", "Sound", "LoadWorld", "Apply", "Create", "Textures", "Tick", "Movers", "Render", "Batches",
                "PrepareView", "EmitBatch", "Warm", "Materials", "AudioUpdate", "PadUpdate", "Events", "Texture info",
                "Texture target", "Texture paint", "Texture check", "Shapes" }
local IN_ORDER = {}
for _, name in ipairs(ORDER) do IN_ORDER[name] = true end

function GSA1.HitchAdd(name, seconds)
    local cur = H.cur
    cur[name] = (cur[name] or 0) + seconds
end

-- "Tick 4.2, EmitBatch 2.1, ..." (sections of at least 0.5 ms) and their sum in seconds
local function breakdown(cur)
    local parts, total = {}, 0
    for _, name in ipairs(ORDER) do
        local v = cur[name]
        if v and v >= 0.0005 then
            parts[#parts + 1] = string.format("%s %.1f", name, v * 1000)
            total = total + v
        end
    end
    for name, v in pairs(cur) do
        if not IN_ORDER[name] and v >= 0.0005 then
            parts[#parts + 1] = string.format("%s %.1f", name, v * 1000)
            total = total + v
        end
    end
    return table.concat(parts, ", "), total
end

-- the start of a frame (cl_character.lua's Think): reports the frame that just ended if it was slow
function GSA1.HitchFrame(now)
    local last, cur = H.last, H.cur
    H.last = now
    -- swap the section tables (the spare one is emptied for this frame)
    local nxt = H.spare
    for k in pairs(nxt) do nxt[k] = nil end
    H.cur, H.spare = nxt, cur
    local heap = collectgarbage("count")
    local gc = H.gc and (heap - H.gc) or nil
    H.gc = heap
    -- a frame that began or ended without the focus or with the escape menu open (single player pauses there), or that
    -- had them in one of its drawn frames, or that was drawn several times without a Think, is not reported: its
    -- length is the pause, not a freeze
    local has_focus = system.HasFocus()
    local focused = has_focus and not (gui.IsGameUIVisible and gui.IsGameUIVisible())
    local was, had_focus = H.focused, H.hadFocus
    H.focused, H.hadFocus = focused, has_focus
    local drawn, ui, unfocused = H.drawn, H.uiSeen, H.unfocusedSeen
    H.drawn, H.uiSeen, H.unfocusedSeen = 0, false, false
    local dt = last and (now - last) or 0
    local long = dt > PAUSE_S
    local paused = ui or unfocused or (long and drawn > PAUSE_DRAWN)
    -- the game itself stood still (the character's tick runs no time): a long frame drawn without Thinks or spent in
    -- the background; single player's escape menu or console at any length (they pause the game)
    H.tickPaused = (long and (drawn > PAUSE_DRAWN or unfocused or not has_focus or had_focus == false)) or
        (ui and game.SinglePlayer())
    if not last or not GSA1.cv then return end
    local counted = focused and was and not paused
    if paused and dt >= 1 and GSA1.LogPause then GSA1.LogPause(dt, drawn, ui, unfocused or not focused or not was) end
    if GSA1.LogFrame then GSA1.LogFrame(dt, cur, counted, gc) end
    if not counted then return end
    local logms = GSA1.cv.log_hitch_ms and GSA1.cv.log_hitch_ms:GetFloat() or 50
    local console = GSA1.cv.hitch:GetBool() and dt * 1000 >= GSA1.cv.hitch_ms:GetFloat()
    if dt * 1000 < logms and not console then return end
    local parts, total = breakdown(cur)
    if dt * 1000 >= logms and GSA1.LogHitch then
        GSA1.LogHitch(dt * 1000, total * 1000, parts, math.max(0, dt - total) * 1000, gc)
    end
    if not console then return end
    H.count = H.count + 1
    H.worst = math.max(H.worst, dt)
    if now < H.quiet then return end
    H.quiet = now + 2
    -- the console only (GSA1.Msg would put it into the session log a second time)
    MsgC(Color(80, 160, 255), "[G-SA1] ", color_white, string.format("hitch: a frame took %.0f ms; G-SA1 %.1f ms%s%s "
        .. "(%.0f ms elsewhere: Garry's Mod, other addons)\n", dt * 1000, total * 1000, parts ~= "" and ": " or "",
        parts, math.max(0, dt - total) * 1000))
end

-- "hitches: N frames over 100 ms (worst 312 ms)"
function GSA1.HitchLine()
    if H.count == 0 then
        return string.format("hitches: none over %d ms", GSA1.cv.hitch_ms:GetInt())
    end
    return string.format("hitches: %d frames over %d ms (worst %.0f ms)%s", H.count, GSA1.cv.hitch_ms:GetInt(),
        H.worst * 1000, GSA1.cv.hitch:GetBool() and "" or " (logging off)")
end
