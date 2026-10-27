-- G-SA1 client: the session log, garrysmod/data/gsa1/log.txt (sadc docs/research/gsa1_lsd_lag.md section 6, with its
-- review's additions; round 4c).
--
-- The owner tests in Garry's Mod and reports in words; this file keeps what a report needs, so nobody has to copy
-- console text: a header per session (versions, the module's build, its vector mode and features, map, screen, the G-SA1
-- settings and upgrades),
-- every G-SA1 console message (module, disc and sound status, spawns, capacity events, errors), every libsa1 log
-- line, every hitch (a frame longer than gsa1_log_hitch_ms, 50 ms) with its breakdown, the time outside G-SA1, the
-- change of the Lua heap in that frame (a garbage collection shows as memory freed) and what the character was doing
-- and drawing; stutters (a frame about twice the median of the second before it, or more, and over 25 ms: one missed
-- vsync); a "jump" line when
-- the drawn character moves further in one frame than the game's own speed explains (0.8.0; 0.6.0 used a fixed 40
-- units, which Sonic's roll passes every frame); "pause" lines (the game paused or in the background for a second or
-- more: not a hitch, cl_hitch.lua); material creations, the material pre-warm (cl_warm.lua),
-- texture painting and render targets made at first use, with their times; the character's spawns, switches and
-- respawns with their times; 0.9.1: "game" lines for the game's own events (its jingles - the drowning countdown -,
-- the music stop at a drown, deaths with their cause, restart requests, game over; counted in the summary); a performance line every 10 seconds while a character is active (frame rate, G-SA1's own
-- time per frame, the Lua heap, the character's state, how much it drew and how much of the screen its effects
-- covered); Lua errors in G-SA1's hooks (GSA1.Guard); marker lines (gsa1_log_mark); a summary when the session ends
-- (map change, disconnect, quit). 0.9.2 (sadc docs/research/gsa1_090_plan.md 6.10 tasks 5 and 7): "fault" lines (a game
-- code fault and the restart, cl_character.lua), "player" lines (the Garry's Mod player's death with the attacker's class,
-- "dead while a character" and for how long), "water" lines (the game's water state changing, with Garry's Mod's
-- contents at the feet and the view), the views line with each view's own setup, EyePos, the STUDIO flags and
-- cl_render.lua's view kind / view id / shader, opaque-only views in the perf line; the summary counts the repeats that
-- were not written, faults, player deaths and the game's water where Garry's Mod has none. Plain text, read from disk
-- after a test:
--   garrysmod/data/gsa1/log.txt           this session and the ones before it
--   garrysmod/data/gsa1/log_previous.txt  older sessions (log.txt is moved here when it would pass 512 KB)
-- At most about 1 MB on disk; a session writes at most 4000 lines (then only its summary); the same line within 10
-- seconds is counted, not written again. Lines are buffered and appended every 2 seconds (errors, marks and the
-- summary at once), so the log never costs a frame: one file.Append per 2 s.
-- Privacy: data/ is readable by any server's clientside Lua, so the log holds no paths, player names or Steam ids
-- (the module already writes <disc> / <config> instead of those directories in everything it hands to Lua).
-- gsa1_log 0 turns it off (Q -> Options -> G-SA1 -> Disc and status -> Diagnostics); gsa1_log_where prints the file's
-- place; gsa1_log_mark <text> writes a marker line (bind a key: bind f9 "gsa1_log_mark lag").
GSA1 = GSA1 or {}
GSA1.LogState = GSA1.LogState or {
    buf = {}, nbuf = 0, lines = 0, dropped = 0, repeats = {}, nrepeats = 0, t0 = SysTime(), nextFlush = 0,
    header = false, summary = false, errors = 0, guardErrors = {},
    -- frame statistics (GSA1.LogFrame, called by cl_hitch.lua at the start of every frame)
    frames = 0, frameSum = 0, frameMax = 0, hist = {}, gsa1Sum = 0, gsa1Max = 0, sect = {}, sectMax = {},
    hitches = 0, worst = 0, stutters = 0, jumps = 0, win = nil, maxVerts = 0, maxSprites = 0, maxBlended = 0,
    maxCover = 0, gcFreed = 0, gcCycles = 0,
    -- the last second's frame times (stutters: the median), a ring
    ring = {}, ringT = {}, ringN = 0, ringI = 0, scratch = {}, nextStutter = 0, nextJump = 0,
    lastPos = nil, bigSprite = false, materials = 0, materialMs = 0,
}
local L = GSA1.LogState
-- 0.8.0: the jump detector's speeds (a ring of the last 4 ticks' speeds; L.lastDt is the time of the frame that
-- moved), the pauses (GSA1.LogPause)
L.vring = L.vring or { 0, 0, 0, 0 }
L.vringI = L.vringI or 0
L.pauses, L.pauseMax = L.pauses or 0, L.pauseMax or 0
-- F4: the views that draw the character (GSA1.LogDraw), per frame
L.views = L.views or { frame = -1, o = 0, b = 0, frames = 0, so = 0, sb = 0, mo = 0, mb = 0, probe = false,
                       probing = false, done = false, list = {} }

local DIR = "gsa1"
local FILE = "gsa1/log.txt"
local OLD = "gsa1/log_previous.txt"
GSA1.LOG_MAX_BYTES = GSA1.LOG_MAX_BYTES or 512 * 1024
GSA1.LOG_MAX_LINES = GSA1.LOG_MAX_LINES or 4000
local FLUSH_EVERY = 2.0
local REPEAT_WINDOW = 10.0
local PERF_EVERY = 10.0
local RING = 256                -- frame times kept for the stutter median (the last second of them is used)
local STUTTER_MS = 25           -- a stutter: at least this long and about twice the median of the second before (1.9x)
local JUMP_HU = 24              -- a "jump": the drawn character moved at least this far in one frame, and further than
                                -- 1.5 x the game's speed (the largest of the last 4 ticks) x the frame + 8 units
local BIG_SPRITE_HU = 160       -- a sprite this wide (40 SA1 units) is implausible (0.4 / 0.5 drew them 256 wide)
-- frame time histogram edges (ms): 8.4 (120 fps), 11.2 (90), 16.8 (60), 20.1 (50), 25.1 (40), 33.4 (30), 50, 100, 250
local EDGES = { 8.4, 11.2, 16.8, 20.1, 25.1, 33.4, 50, 100, 250 }

local function enabled()
    local cv = GSA1.cv and GSA1.cv.log
    return cv == nil or cv:GetBool()
end
GSA1.LogEnabled = enabled

local function stamp()
    return string.format("%s +%.3f", os.date("%H:%M:%S"), SysTime() - L.t0)
end

-- one line: no control characters, at most 800 characters
local function clean(text)
    text = string.gsub(tostring(text), "%c", " ")
    if #text > 800 then text = string.sub(text, 1, 800) .. " ..." end
    return text
end

local function push(line)
    if L.lines >= GSA1.LOG_MAX_LINES then
        L.dropped = L.dropped + 1
        return
    end
    L.lines = L.lines + 1
    L.nbuf = L.nbuf + 1
    L.buf[L.nbuf] = line .. "\n"
end

-- moves log.txt to log_previous.txt when `incoming` more bytes would take it past the cap
local function rotate(incoming)
    local size = file.Size(FILE, "DATA") or -1
    if size < 0 or size + incoming <= GSA1.LOG_MAX_BYTES then return end
    if file.Exists(OLD, "DATA") then file.Delete(OLD) end
    if file.Rename then
        file.Rename(FILE, OLD)
    else
        file.Write(OLD, file.Read(FILE, "DATA") or "")
        file.Delete(FILE)
    end
end

function GSA1.LogFlush()
    if L.nbuf == 0 then return end
    local chunk = table.concat(L.buf, "", 1, L.nbuf)
    for i = L.nbuf, 1, -1 do L.buf[i] = nil end
    L.nbuf = 0
    if not enabled() then return end
    file.CreateDir(DIR)
    rotate(#chunk)
    file.Append(FILE, chunk)
end

-- GSA1.Log(kind, fmt, ...): kind is a short word (msg, libsa1, module, hitch, stutter, jump, slow, perf, material, warm,
-- texture, paint, spawn, capacity, error, mark, summary; 0.9.1: game - the game's own events, cl_character.lua and
-- feat/cl_charopt.lua: its music calls, deaths, restart requests, respawns, game over; 0.9.2: fault, player, water)
function GSA1.Log(kind, fmt, ...)
    if not enabled() then return end
    local ok, text = pcall(string.format, fmt, ...)
    if not ok then text = tostring(fmt) end
    text = clean(text)
    if not L.header then GSA1.LogHeader() end
    local now = SysTime()
    local key = kind .. "|" .. text
    local r = L.repeats[key]
    if r and now - r.t < REPEAT_WINDOW then
        r.n = r.n + 1
        -- 0.9.2 (gsa1_090_player.md review R.4 G5 / R.5 item 9): every repeat is counted for the summary, also those of a
        -- line that never comes back after its window (0.9.1 lost them: "hits taken went 113 -> 118 around one hurt line")
        L.repeatCount = (L.repeatCount or 0) + 1
        if r.n == 1 then L.repeatLines = (L.repeatLines or 0) + 1 end
        return
    end
    if r and r.n > 0 then
        push(string.format("%s %-8s (the line before was repeated %d more times)", stamp(), kind, r.n))
        L.repeatReported = (L.repeatReported or 0) + r.n
    end
    if not r then
        L.nrepeats = L.nrepeats + 1
        if L.nrepeats > 400 then L.repeats, L.nrepeats = {}, 0 end
    end
    L.repeats[key] = { t = now, n = 0 }
    push(string.format("%s %-8s %s", stamp(), kind, text))
    if kind == "error" or kind == "mark" then GSA1.LogFlush() end
end

local function cvstr(name)
    local cv = GetConVar(name)
    return cv and cv:GetString() or "?"
end

-- the session header: written before the first line of a session
function GSA1.LogHeader()
    if L.header then return end
    L.header = true
    push("")
    push(string.format("==== G-SA1 session %s ====", os.date("%Y-%m-%d %H:%M:%S")))
    push(string.format("addon %s (module API %d); Garry's Mod %s (%s, branch %s); %s; %s", GSA1.VERSION or "?",
        GSA1.REQUIRED_API or 0, tostring(VERSIONSTR or VERSION), tostring(jit and jit.arch), tostring(BRANCH),
        jit and jit.version or "Lua", system.IsWindows() and "Windows" or (system.IsLinux() and "Linux" or "macOS")))
    push(string.format("map %s, gamemode %s, %s; screen %dx%d, DX level %s, fps_max %s, mat_queue_mode %s, "
        .. "fov_desired %s, mat_vsync %s", game.GetMap(), engine.ActiveGamemode(), game.SinglePlayer() and
        "single player" or "multiplayer", ScrW(), ScrH(), tostring(render.GetDXLevel and render.GetDXLevel() or "?"),
        cvstr("fps_max"), cvstr("mat_queue_mode"), cvstr("fov_desired"), cvstr("mat_vsync")))
    local c = GSA1.cv
    if c then
        local ups = {}
        for _, u in ipairs(GSA1.UPGRADES or {}) do
            local v = c["up_" .. u.name]
            if v and v:GetBool() then ups[#ups + 1] = u.name end
        end
        push(string.format("settings: interpolate %s, lighting %s, vertexcolor %s, effects %s, shadows %s, relative %s, "
            .. "camera %s/%s, pad %s, "
            .. "sound %s, static props %s, physics props %s, pre-warm %s, slow frames %s ms (console) / %s ms (log); "
            .. "upgrades: %s", c.interp:GetString(), c.lighting:GetString(), c.vcolor:GetString(), c.effects:GetString(),
            c.shadow and c.shadow:GetString() or "?", c.relative and c.relative:GetString() or "?",
            c.cam_dist:GetString(), c.cam_height:GetString(), c.pad:GetString(), c.sound:GetString(),
            c.static_props:GetString(), c.phys_props:GetString(), c.prewarm and c.prewarm:GetString() or "?",
            c.hitch_ms:GetString(), c.log_hitch_ms and c.log_hitch_ms:GetString() or "?",
            #ups > 0 and table.concat(ups, " ") or "none"))
        -- 0.9.2: the settings of this round's fixes
        push(string.format("settings 0.9.2: water follows Garry's Mod's water %s, depth for post-processing %s, start rings "
            .. "%s", c.hostwater and c.hostwater:GetString() or "?", c.depthfix and c.depthfix:GetString() or "?",
            c.start_rings and c.start_rings:GetString() or "?"))
    end
    -- the module: loaded already in the usual case (a session's first line is its "loaded" message); its vector mode
    -- (how EmitBatch hands Vectors to the mesh library) is decided when it opens (review R.3 G4 of gsa1_lsd_lag.md)
    local st = nil
    if GSA1.mod and gsa1 and gsa1.Status then
        local ok, res = pcall(gsa1.Status)
        if ok and type(res) == "table" then st = res end
    end
    if st then
        push(string.format("module %s (API %s, build %s), libsa1 %s; vector mode %s; %s", tostring(st.version),
            tostring(st.api), tostring(st.build), tostring(st.libsa1), GSA1.VectorModeText and
            GSA1.VectorModeText(st.vector_mode) or tostring(st.vector_mode), GSA1.FeatureLine and GSA1.FeatureLine()
            or ""))
    else
        push("module: not loaded yet (its \"module\" line, with the vector mode, follows when it loads)")
    end
    push(string.format("Lua heap %.1f MB", collectgarbage("count") / 1024))
end

-- GSA1.Guard(name, fn): fn wrapped for a hook or a draw; a Lua error in it goes into the log (the first 5 per name,
-- then counted) and is reported the way Garry's Mod reports errors, without removing the hook. Returns fn's first
-- result (CalcView's view, HUDShouldDraw's bool).
function GSA1.Guard(name, fn)
    local function handler(err)
        L.errors = L.errors + 1
        local n = (L.guardErrors[name] or 0) + 1
        L.guardErrors[name] = n
        if n <= 5 then
            local tb = string.gsub(debug.traceback("", 2), "\n%s*", " <- ")
            GSA1.Log("error", "Lua error in %s: %s |%s", name, tostring(err), tb)
        end
        return err
    end
    return function(...)
        local ok, res = xpcall(fn, handler, ...)
        if ok then return res end
        if (L.guardErrors[name] or 0) <= 5 then
            if ErrorNoHaltWithStack then ErrorNoHaltWithStack(tostring(res)) else ErrorNoHalt(tostring(res) .. "\n") end
        end
    end
end

-- what the character is doing, for hitch / stutter / slow / mark lines
function GSA1.LogContext()
    local C = GSA1.Char
    if not C then return "no character" end
    local s = C.state or {}
    -- s.draws / s.sprites / s.blend_layers: the module's GetState since 0.6.0; older modules leave them out
    return string.format("%s mode %d action %d %s, %d triangles in %d batches (%d blended, %d with sprites) = %d "
        .. "vertices%s%s%s, effects %s, pairs %d alpha %.2f%s, at (%.0f %.0f %.0f)", C.title or "?", s.mode or -1,
        s.action or -1, s.ground and "ground" or "air", C.triangles or 0, C.batches and C.batches.count or 0,
        C.blendedBatches or 0, C.spriteBatches or 0, (C.triangles or 0) * 3,
        s.sprites and string.format(", %d draws, %d sprites", s.draws or 0, s.sprites) or "",
        s.shadow_draws and string.format(", shadow draws %d", s.shadow_draws) or "",
        s.blend_layers and string.format(", effects cover %.2f screens", s.blend_layers) or "",
        (GSA1.cv and GSA1.cv.effects:GetBool()) and "on" or "off", s.pairs or 0, C.alpha or 0,
        C.shifted and ", moved with the root" or "", s.x or 0, s.y or 0, s.z or 0)
end

-- the median of the frame times of the second before `now` (ms), or nil with fewer than 8 frames
local function median_ms(now)
    local sc = L.scratch
    local n = 0
    for i = 1, L.ringN do
        if now - L.ringT[i] <= 1.0 then
            n = n + 1
            sc[n] = L.ring[i]
        end
    end
    for i = #sc, n + 1, -1 do sc[i] = nil end
    if n < 8 then return nil end
    table.sort(sc)
    return sc[math.floor((n + 1) / 2)] * 1000
end

-- called by cl_hitch.lua at the start of every frame: dt = the frame that just ended (s), sections = its G-SA1 times
-- (s, by name), counted = the frame had the focus (no alt-tab, no escape menu), gc = the Lua heap's change over the
-- frame (KB; negative: the collector freed memory)
function GSA1.LogFrame(dt, sections, counted, gc)
    if not counted or not enabled() then
        -- (a pause, alt-tab, the escape menu): the next counted frame starts a new chain of moves (review R.3.6)
        L.lastPos, L.lastDt = nil, nil
        return
    end
    local ms = dt * 1000
    local now = SysTime()
    local g = 0
    for name, v in pairs(sections) do
        g = g + v
        L.sect[name] = (L.sect[name] or 0) + v
        if v > (L.sectMax[name] or 0) then L.sectMax[name] = v end
    end
    L.frames = L.frames + 1
    L.frameSum = L.frameSum + dt
    if dt > L.frameMax then L.frameMax = dt end
    L.gsa1Sum = L.gsa1Sum + g
    if g > L.gsa1Max then L.gsa1Max = g end
    if gc and gc < 0 then
        L.gcFreed = L.gcFreed - gc
        L.gcCycles = L.gcCycles + 1
    end
    local b = #EDGES + 1
    for i, e in ipairs(EDGES) do
        if ms <= e then
            b = i
            break
        end
    end
    L.hist[b] = (L.hist[b] or 0) + 1
    -- stutters: a frame of 25 ms or more that is over twice as long as the median of the second before it, below the
    -- hitch threshold (those get a hitch line); at most one line per second
    local logms = GSA1.cv and GSA1.cv.log_hitch_ms and GSA1.cv.log_hitch_ms:GetFloat() or 50
    if ms >= STUTTER_MS and ms < logms and now >= L.nextStutter then
        local med = median_ms(now - dt)
        -- "twice": a missed vsync at 60 Hz is 33.3 ms against 16.7, measured a little either side of 2.0
        if med and ms >= 1.9 * med then
            L.stutters = L.stutters + 1
            L.nextStutter = now + 1
            GSA1.Log("stutter", "a frame took %.0f ms (the median of the second before: %.1f ms); G-SA1 %.1f ms%s; %s",
                ms, med, g * 1000, gc and gc < 0 and string.format(", the Lua GC freed %.0f KB", -gc) or "",
                GSA1.LogContext())
        end
    end
    L.ringI = L.ringI % RING + 1
    L.ring[L.ringI], L.ringT[L.ringI] = dt, now
    if L.ringN < RING then L.ringN = L.ringN + 1 end
    local C = GSA1.Char
    if not C then
        L.win = nil
        L.lastPos, L.lastDt = nil, nil
        return
    end
    L.maxVerts = math.max(L.maxVerts, (C.triangles or 0) * 3)
    L.maxBlended = math.max(L.maxBlended, C.blendedBatches or 0)
    L.maxSprites = math.max(L.maxSprites, C.spriteBatches or 0)
    local st = C.state or {}
    local cover = st.blend_layers or 0
    if cover > L.maxCover then L.maxCover = cover end
    -- the drawn character jumped against the camera, which follows it (0.8.0: sadc docs/research/gsa1_060_pops.md 5.3
    -- with its review's D4). LogFrame runs at the START of a frame, before the tick: C.drawPos is the previous frame's
    -- render and L.lastPos the one before it, so the move d belongs to the previous frame, whose time is L.lastDt, and
    -- C.state is the state after that frame's tick (0.6.0 printed this frame's time and compared with a fixed 40 units:
    -- Sonic's roll passes that every frame, and after a long frame it named the short frame that followed it). A jump
    -- is a move further than the game's own speed explains: d > max(JUMP_HU, 1.5 x vmax x L.lastDt + 8), vmax the
    -- largest speed of the last 4 ticks (a stop against a wall, the spin dash's release). A run at any speed and a long
    -- frame are not jumps; 0.6.0's lurch after a tick of several pairs (the drawn root up to (k - 1) pairs behind, then
    -- 3-5x as fast) and a teleport are. A new character, an uncounted frame (pause, alt-tab) and no character start a
    -- new chain. UNVERIFIED on moving platforms: the state's speed may leave out the carrier's motion.
    local p = C.drawPos
    local sp = math.sqrt((st.vx or 0) ^ 2 + (st.vy or 0) ^ 2 + (st.vz or 0) ^ 2)
    local vr = L.vring
    if p then
        local lp = L.lastPos
        if lp and lp.id == C.id and L.lastDt and L.lastDt > 0 then
            L.vringI = L.vringI % 4 + 1
            vr[L.vringI] = sp
            local vmax = math.max(vr[1], vr[2], vr[3], vr[4])
            local dx, dy, dz = p.x - lp.x, p.y - lp.y, p.z - lp.z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            local fdt = L.lastDt
            local limit = math.max(JUMP_HU, 1.5 * vmax * fdt + 8)
            if d > limit and now >= L.nextJump then
                L.jumps = L.jumps + 1
                L.nextJump = now + 1
                GSA1.Log("jump", "the drawn character moved %.0f units in one frame of %.1f ms (%.0f units/s), more than "
                    .. "the game's speed explains (up to %.0f units/s: at most %.0f units); %d pairs, alpha %.2f; mode %d "
                    .. "action %d", d, fdt * 1000, d / fdt, vmax, limit, st.pairs or 0, C.alpha or 0, st.mode or -1,
                    st.action or -1)
            end
        else
            -- a new chain: this render is the first of it; the speeds are this tick's
            if not lp then
                lp = {}
                L.lastPos = lp
            end
            vr[1], vr[2], vr[3], vr[4] = sp, sp, sp, sp
        end
        lp.id, lp.x, lp.y, lp.z = C.id, p.x, p.y, p.z
    end
    L.lastDt = dt
    if not L.bigSprite and (st.sprite_max or 0) > BIG_SPRITE_HU then
        L.bigSprite = true
        GSA1.Log("sprite", "an implausible sprite size: %.0f units wide (the game's are at most about 160); %s",
            st.sprite_max, GSA1.LogContext())
    end
    -- the 1-second and 10-second windows while a character is active
    local w = L.win
    if not w then
        w = { t0 = now, frames = 0, sum = 0, max = 0, g = 0, gmax = 0, s1 = now, f1 = 0, sum1 = 0, max1 = 0,
              modes = {}, verts = 0, blended = 0, sect = {}, cover = 0, gcFreed = 0, multi = 0, kmax = 0 }
        L.win = w
    end
    -- ticks that ran 2 or more game pairs (a frame of 33 ms or more): 0.6.0's lurch came after each of them, until
    -- libsa1 captured the last two pairs of such a tick (gsa1_060_pops.md P1 / F1)
    local pr = st.pairs or 0
    if pr >= 2 then
        w.multi = w.multi + 1
        if pr > w.kmax then w.kmax = pr end
    end
    w.frames, w.sum, w.g = w.frames + 1, w.sum + dt, w.g + g
    if dt > w.max then w.max = dt end
    if g > w.gmax then w.gmax = g end
    if gc and gc < 0 then w.gcFreed = w.gcFreed - gc end
    for name, v in pairs(sections) do w.sect[name] = (w.sect[name] or 0) + v end
    -- mode / action as one number (no string per frame)
    local key = math.max(st.mode or 0, 0) * 4096 + math.max(st.action or 0, 0) % 4096
    w.modes[key] = (w.modes[key] or 0) + 1
    w.verts = math.max(w.verts, (C.triangles or 0) * 3)
    w.blended = math.max(w.blended, C.blendedBatches or 0)
    if cover > w.cover then w.cover = cover end
    w.f1, w.sum1 = w.f1 + 1, w.sum1 + dt
    if dt > w.max1 then w.max1 = dt end
    if now - w.s1 >= 1.0 then
        -- a slow second: under 3/4 of the frame rate cap (fps_max; 60 without one) or a frame of 50 ms or more
        local cap = tonumber(cvstr("fps_max")) or 0
        if cap <= 0 or cap > 1000 then cap = 60 end
        local fps = w.f1 / math.max(w.sum1, 1e-6)
        if fps < 0.75 * cap or w.max1 >= 0.05 then
            GSA1.Log("slow", "%.0f fps over %.2f s (worst frame %.0f ms); %s", fps, w.sum1, w.max1 * 1000,
                GSA1.LogContext())
        end
        w.s1, w.f1, w.sum1, w.max1 = now, 0, 0, 0
    end
    if now - w.t0 >= PERF_EVERY then
        local top = {}
        for name, v in pairs(w.sect) do top[#top + 1] = { name, v } end
        table.sort(top, function(x, y) return x[2] > y[2] end)
        local parts = {}
        for i = 1, math.min(4, #top) do
            parts[i] = string.format("%s %.2f", top[i][1], top[i][2] * 1000 / w.frames)
        end
        local modes = {}
        for k, n in pairs(w.modes) do modes[#modes + 1] = { k, n } end
        table.sort(modes, function(x, y) return x[2] > y[2] end)
        local mm = {}
        for i = 1, math.min(3, #modes) do
            local k = modes[i][1]
            local m = math.floor(k / 4096)
            mm[i] = string.format("%d/%d x%d", m, k - m * 4096, modes[i][2])
        end
        local mesh = ""
        if GSA1.mod and gsa1.Status then
            local ok, s = pcall(gsa1.Status)
            if ok and type(s) == "table" and s.mesh_calls then
                if L.mesh0 then
                    mesh = string.format("; %.0f mesh calls per frame (%.0f saved), vector mode %s",
                        (s.mesh_calls - L.mesh0) / w.frames, (s.mesh_saved or 0) - (L.saved0 or 0), tostring(s.vector_mode))
                end
                L.mesh0, L.saved0 = s.mesh_calls, s.mesh_saved or 0
            end
        end
        -- F4: how many views drew the character per frame (GSA1.LogDraw); 0.9.2 (D1, gsa1_090_render.md review RC3): the
        -- opaque-only views (the depth pass, a lamp's or flashlight's shadow depth draw no blended pass) counted
        -- separately, and the last frame's views by kind (cl_render.lua GSA1.ViewsLine)
        local V, views = L.views, ""
        if V.frames > 0 then
            views = string.format("; the character drawn in %.2f opaque / %.2f blended views per frame (at most %d / %d), "
                .. "%.2f opaque-only views per frame%s", V.so / V.frames, V.sb / V.frames, V.mo, V.mb,
                (V.soo or 0) / V.frames, GSA1.ViewsLine and (" (last frame: " .. tostring(GSA1.ViewsLine()) .. ")") or "")
        end
        V.frames, V.so, V.sb, V.mo, V.mb, V.soo = 0, 0, 0, 0, 0, 0
        GSA1.Log("perf", "%d frames, %.1f fps, frame %.1f ms mean / %.0f ms worst; G-SA1 %.2f ms per frame (worst "
            .. "%.1f): %s; mode/action %s; up to %d vertices, %d blended batches, effects up to %.2f screens; ticks of 2+ "
            .. "pairs %d (largest %d); Lua heap %.1f MB (the GC freed %.1f MB in the window)%s%s", w.frames,
            w.frames / math.max(w.sum, 1e-6), w.sum * 1000 / w.frames, w.max * 1000, w.g * 1000 / w.frames,
            w.gmax * 1000, table.concat(parts, ", "), table.concat(mm, ", "), w.verts, w.blended, w.cover, w.multi,
            w.kmax, collectgarbage("count") / 1024, w.gcFreed / 1024, mesh, views)
        L.win = nil
    end
end

-- a slow frame (from cl_hitch.lua): every frame over gsa1_log_hitch_ms goes into the file, with its sections
function GSA1.LogHitch(ms, gsa1ms, parts, elsewhere, gc)
    L.hitches = L.hitches + 1
    if ms > L.worst then L.worst = ms end
    GSA1.Log("hitch", "a frame took %.0f ms; G-SA1 %.1f ms%s (%.0f ms elsewhere: Garry's Mod, other addons, the GPU); "
        .. "Lua heap %.1f MB%s; %s", ms, gsa1ms, parts ~= "" and (": " .. parts) or "", elsewhere,
        collectgarbage("count") / 1024, gc and (gc < 0 and string.format(", the GC freed %.0f KB in it", -gc)
            or string.format(", +%.0f KB in it", gc)) or "", GSA1.LogContext())
end

-- a pause of a second or more (from cl_hitch.lua): single player's escape menu or console, the game in the background,
-- or frames drawn without a Think; not a hitch, not in the frame statistics
function GSA1.LogPause(seconds, drawn, menu, background)
    L.pauses = L.pauses + 1
    if seconds > L.pauseMax then L.pauseMax = seconds end
    GSA1.Log("pause", "the game was paused or in the background for %.1f s (%s%d frames drawn without a tick); not a "
        .. "hitch", seconds, menu and "the escape menu or console was open; " or (background and
        "Garry's Mod was in the background; " or ""), drawn)
end

-- a material made outside the pre-warm (cl_textures.lua): its first use costs this frame the time it took
function GSA1.LogMaterial(name, shader, what, ms)
    L.materials = L.materials + 1
    L.materialMs = L.materialMs + ms
    GSA1.Log("material", "%s (%s, %s) created at its first use in %.2f ms", name, shader, what, ms)
end

-- 0.9.1 (sadc docs/research/gsa1_070_drown.md G2): counts of the game's events for the summary line "the game:"
-- GSA1.LogCount(group, key): group deaths / restarts / respawns / jingles, key the cause, id or music number
L.counts = L.counts or {}
function GSA1.LogCount(group, key)
    local g = L.counts[group]
    if not g then
        g = { n = 0, by = {} }
        L.counts[group] = g
    end
    g.n = g.n + 1
    if key ~= nil then g.by[tostring(key)] = (g.by[tostring(key)] or 0) + 1 end
end

function GSA1.LogSummary(reason)
    if L.summary or not enabled() then return end
    L.summary = true
    if not L.header then GSA1.LogHeader() end
    local names = { "<=8", "<=11", "<=17", "<=20", "<=25", "<=33", "<=50", "<=100", "<=250", ">250" }
    local h = {}
    for i = 1, #EDGES + 1 do
        if (L.hist[i] or 0) > 0 then h[#h + 1] = string.format("%s ms %d", names[i], L.hist[i]) end
    end
    local sect = {}
    for name, v in pairs(L.sect) do
        sect[#sect + 1] = string.format("%s %.2f/%.1f", name, v * 1000 / math.max(L.frames, 1),
            (L.sectMax[name] or 0) * 1000)
    end
    table.sort(sect)
    local lines = {
        string.format("session end (%s) after %.0f s: %d frames counted, %.1f fps, worst frame %.0f ms; %d slow frames "
            .. "over %s ms (worst %.0f ms), %d stutters, %d pauses of a second or more (longest %.0f s), %d jumps of the "
            .. "drawn character; %d Lua errors; %d lines written, %d not written (line cap)", tostring(reason),
            SysTime() - L.t0, L.frames, L.frames / math.max(L.frameSum, 1e-6), L.frameMax * 1000, L.hitches,
            (GSA1.cv and GSA1.cv.log_hitch_ms) and GSA1.cv.log_hitch_ms:GetString() or "?", L.worst, L.stutters,
            L.pauses, L.pauseMax, L.jumps, L.errors, L.lines, L.dropped),
        "frame times: " .. table.concat(h, ", "),
        string.format("G-SA1 per frame: %.2f ms mean, %.1f ms worst; by section (mean/worst ms): %s",
            L.gsa1Sum * 1000 / math.max(L.frames, 1), L.gsa1Max * 1000, table.concat(sect, ", ")),
        string.format("drawing: up to %d vertices per frame, %d blended batches, %d batches with sprites, effects "
            .. "covering up to %.2f screens; %d materials made at their first use (%.1f ms in all)", L.maxVerts,
            L.maxBlended, L.maxSprites, L.maxCover, L.materials, L.materialMs),
        string.format("Lua: heap %.1f MB now; the GC freed %.1f MB in %d frames of the session", collectgarbage("count")
            / 1024, L.gcFreed / 1024, L.gcCycles),
    }
    local game = {}
    for _, grp in ipairs({ "deaths", "restarts", "respawns", "jingles", "faults", "player deaths", "teleports" }) do
        local g = L.counts[grp]
        if g and g.n > 0 then
            local by = {}
            for k, n in pairs(g.by) do by[#by + 1] = string.format("%s x%d", k, n) end
            table.sort(by)
            game[#game + 1] = string.format("%d %s%s", g.n, grp, #by > 0 and (" (" .. table.concat(by, ", ") .. ")") or "")
        end
    end
    if #game > 0 then lines[#lines + 1] = "the game: " .. table.concat(game, "; ") end
    -- 0.9.2: the repeats counted instead of written, the water, the player's deaths (WTR-LOG, L7)
    local rc = L.repeatCount or 0
    if rc > 0 then
        lines[#lines + 1] = string.format("repeats: %d repeat%s of %d line%s within %d s counted, not written (%d of them "
            .. "only counted here)", rc, rc == 1 and "" or "s", L.repeatLines or 0, (L.repeatLines or 0) == 1 and "" or "s",
            REPEAT_WINDOW, rc - (L.repeatReported or 0))
    end
    if GSA1.WaterLine then
        local okw, wl = pcall(GSA1.WaterLine)
        if okw and wl then lines[#lines + 1] = wl end
    end
    if (L.deadEpisodes or 0) > 0 or (L.playerDeaths or 0) > 0 then
        local open = L.dead and (SysTime() - L.dead.t) or 0
        lines[#lines + 1] = string.format("the player: %d deaths while a character; dead while a character %d times, %.1f s "
            .. "in all (longest %.1f s)%s", L.playerDeaths or 0, L.deadEpisodes or 0, (L.deadSeconds or 0) + open,
            math.max(L.deadMax or 0, open), L.dead and "; still dead at the end" or "")
    end
    if GSA1.WarmLine then
        local ok, wl = pcall(GSA1.WarmLine)
        if ok and wl then lines[#lines + 1] = wl end
    end
    if GSA1.mod then
        local ok, s = pcall(gsa1.Status)
        if ok and type(s) == "table" then
            lines[#lines + 1] = string.format("module %s (build %s, libsa1 %s): %s mesh calls (%s saved), %s failed; "
                .. "vector mode %s; %s characters", tostring(s.version), tostring(s.build), tostring(s.libsa1),
                tostring(s.mesh_calls), tostring(s.mesh_saved), tostring(s.mesh_errors), tostring(s.vector_mode),
                tostring(s.characters))
        end
        local ok2, a = pcall(gsa1.AudioStatus)
        if ok2 and type(a) == "table" and a.open then
            -- 0.9.2a (gsa1_091a_perf.md A0 / A2): the lead the feed keeps in BASS's push queue and BASS's own playback
            -- buffer (latency, not counted as queued any more)
            local feed = a.lead_ms and string.format(" (push queue lead %.0f ms now, BASS's playback buffer %.0f ms)",
                tonumber(a.lead_ms) or 0, tonumber(a.playback_ms) or 0) or ""
            lines[#lines + 1] = string.format("sound: %s events, %s underruns%s, %s cues dropped, slowest disc read %s ms, "
                .. "%s files read on the game's thread", tostring(a.events), tostring(a.underruns), feed,
                tostring(a.cues_dropped), tostring(a.max_read_ms), tostring(a.caller_reads))
        end
    end
    if GSA1.MoverLine then
        local ok3, m = pcall(GSA1.MoverLine)
        if ok3 and m then lines[#lines + 1] = m end
    end
    if GSA1.Tex and GSA1.Tex.FormatLine then
        local ok4, f = pcall(GSA1.Tex.FormatLine)
        if ok4 and f then lines[#lines + 1] = f end
    end
    for _, l in ipairs(lines) do
        L.lines = math.min(L.lines, GSA1.LOG_MAX_LINES - 1)    -- the summary is always written
        push(string.format("%s %-8s %s", stamp(), "summary", clean(l)))
    end
    GSA1.LogFlush()
end

-- F4 (sadc docs/research/gsa1_060_pops.md 5.5 with its review R.4): how many views draw the character per frame.
-- 0.6.0's mesh calls were exactly twice one view's in every perf line: something drew the character in a second view
-- every frame (the water reflection with r_waterforceexpensive 1? another addon's render.RenderView? both UNVERIFIED).
-- The calls of GSA1.DrawCharacter are counted per FrameNumber and pass; the perf line gives the views per frame, and
-- the first frame after one with more than one opaque view is described once per session (a "views" line): each
-- view's origin, its render target and the Lua that asked for it (debug.traceback without G-SA1's own frames; no Lua
-- caller: the engine made the view). cl_render.lua's draws call GSA1.DrawCharacter through the global, so the counter
-- wraps it (installed again by the Think hook below when the function is replaced, e.g. by a Lua refresh); a renderer
-- that calls GSA1.LogDraw(C, pass, flags) itself sets GSA1.LogDrawDirect = true and gets no wrapper.
-- 0.9.2 (D1, gsa1_090_render.md review RC3): the view's own setup (render.GetViewSetup(true): the view being drawn, not
-- the player's), the STUDIO flags of ENT:Draw (the counter forwards them), and after the callers EyePos() and what
-- cl_render.lua makes of the view (GSA1.ViewInfo(true, flags): its kind - main, depth pass, shadow depth, water -, the
-- view id and the shader the character is drawn with there). A views line is written again (at most 5 per session)
-- whenever a frame draws the character in more opaque views than any frame described before (a flashlight's shadow depth
-- view joining the depth pass: S1's premise, review RC6).
local function describe_view(pass, flags)
    local origin, target = "?", "the screen"
    if render.GetViewSetup then
        local ok, vs = pcall(render.GetViewSetup, true)
        if ok and type(vs) == "table" and vs.origin then
            origin = string.format("(%.0f %.0f %.0f)", vs.origin.x, vs.origin.y, vs.origin.z)
        end
    end
    local extra = {}
    if EyePos then
        local ok, e = pcall(EyePos)
        if ok and e and e.x then extra[#extra + 1] = string.format("eye (%.0f %.0f %.0f)", e.x, e.y, e.z) end
    end
    if GSA1.ViewInfo then
        local ok, vi = pcall(GSA1.ViewInfo, true, flags)
        if ok and type(vi) == "table" then
            extra[#extra + 1] = string.format("kind %s, view id %s, shader %s", tostring(vi.kind), tostring(vi.viewid),
                tostring(vi.shader))
        end
    end
    if render.GetRenderTarget then
        local ok, rt = pcall(render.GetRenderTarget)
        if ok and rt then
            local ok2, name = pcall(function() return rt:GetName() end)
            target = ok2 and tostring(name) or "?"
        end
    end
    local callers = {}
    for line in string.gmatch(debug.traceback("", 2), "[^\n]+") do
        line = string.Trim(line)
        if line ~= "" and line ~= "stack traceback:" and line ~= "[C]: ?" and not string.find(line, "gsa1/", 1, true)
           and not string.find(line, "'xpcall'", 1, true) and not string.find(line, "'pcall'", 1, true) then
            callers[#callers + 1] = line
        end
    end
    return string.format("%s pass, origin %s, target %s%s, called from %s%s", pass == 0 and "opaque" or "blended", origin,
        target, flags and string.format(", flags %s", tostring(flags)) or "",
        #callers > 0 and string.sub(table.concat(callers, " <- "), 1, 120) or "no Lua (the engine's own view)",
        #extra > 0 and (" [" .. table.concat(extra, ", ") .. "]") or "")
end

local VIEWS_LINES_MAX = 5
local function commit_views(V)
    if V.o > 0 or V.b > 0 then
        V.frames, V.so, V.sb = V.frames + 1, V.so + V.o, V.sb + V.b
        V.soo = (V.soo or 0) + math.max(V.o - V.b, 0)
        if V.o > V.mo then V.mo = V.o end
        if V.b > V.mb then V.mb = V.b end
    end
    if V.probing then
        V.probing = false
        V.lines = (V.lines or 0) + 1
        V.done = V.lines >= VIEWS_LINES_MAX
        GSA1.Log("views", "the character was drawn in %d opaque and %d blended views in one frame: %s", V.o, V.b,
            table.concat(V.list, "; "))
    elseif not V.done and V.o >= 2 and V.o > (V.described or 1) then
        V.probe = true                   -- describe the views of the next frame
        V.described = V.o
    end
    V.o, V.b = 0, 0
end

function GSA1.LogDraw(C, pass, flags)
    local V = L.views
    local fn = FrameNumber()
    if fn ~= V.frame then
        commit_views(V)
        V.frame = fn
        if V.probe then
            V.probe, V.probing, V.list = false, true, {}
        end
    end
    if pass == 0 then V.o = V.o + 1 else V.b = V.b + 1 end
    if V.probing and #V.list < 6 then V.list[#V.list + 1] = describe_view(pass, flags) end
end

local function count_draws()
    if GSA1.LogDrawDirect then return end
    local f = GSA1.DrawCharacter
    if type(f) ~= "function" or f == L.drawWrap then return end
    local inner = f
    L.drawWrap = function(C, pass, ...)
        pcall(GSA1.LogDraw, C, pass, ...)       -- counting never stops a draw; the STUDIO flags go along (D1)
        return inner(C, pass, ...)
    end
    GSA1.DrawCharacter = L.drawWrap
end

-- 0.9.2, L7 (gsa1_090_player.md L7 with its review R.4 G5, R.5 item 9; plan 6.10 task 7): the Garry's Mod player's death
-- while a character - the interaction feature's message gives the attacker's class (for a kill outright the server's
-- guess: the NPC or NextBot next to the player) and how (feat/cl_interact.lua, hook GSA1PlayerDied) - and the time the
-- player stays dead while a character ("dead while a character": 0.9.0's corpse that never respawned); counted in the
-- summary
local HOW_DIED = { [0] = "a deadly hit", [1] = "killed outright (Garry's Mod's Kill)", [2] = "a silent kill" }
hook.Add("GSA1PlayerDied", "gsa1_log", function(C, class, how)
    L.playerDeaths = (L.playerDeaths or 0) + 1
    GSA1.LogCount("player deaths", class or "?")
    local s = C and C.state or {}
    GSA1.Log("player", "player died (%s): %s; %s", tostring(class or "?"), HOW_DIED[how] or tostring(how),
        C and string.format("%s at (%.0f %.0f %.0f), %s", C.title or "?", s.x or 0, s.y or 0, s.z or 0,
            C.death and "already dying" or "alive") or "no character")
end)

local function dead_watch(now)
    local C = GSA1.Char
    local ply = LocalPlayer and LocalPlayer()
    local dead = C ~= nil and IsValid(ply) and ply.Alive ~= nil and not ply:Alive()
    local D = L.dead
    if dead and not D then
        L.dead = { t = now, title = C.title or "?" }
        L.deadEpisodes = (L.deadEpisodes or 0) + 1
        GSA1.Log("player", "dead while a character (%s): the player is dead%s", C.title or "?",
            C.death and ", the character is dying too" or ", the character lives")
    elseif D and not dead then
        local s = now - D.t
        L.deadSeconds = (L.deadSeconds or 0) + s
        if s > (L.deadMax or 0) then L.deadMax = s end
        L.dead = nil
        GSA1.Log("player", "the player was dead for %.1f s while a character (%s)%s", s, D.title,
            C == nil and "; the character is gone" or "; alive again")
    end
end

-- 0.9.2, WTR-LOG (gsa1_090_water.md WTR-LOG with its review R3.2; plan 6.10 task 5), called by cl_character.lua after
-- every tick with the state: a "water" line whenever the game's water state changes - the character enters or leaves the
-- game's water (sa1_state_ex.water_attr & 0x400002, gsa1.GetState) - with the position, the game's water level, Garry's
-- Mod's contents at the feet AND at the view's origin (a chase camera crossing the surface switches Garry's Mod's own
-- underwater view and sound while the game's state stays the same: review R3.2) and the host flags the tick passed; at
-- most 4 lines a second (the others counted in the next line). The summary: the entries and the time in the game's water,
-- and "game water where Garry's Mod has none" (the game had the character in water while util.PointContents said dry at
-- its feet: the dry rooms under water of the 0.9.0 report, WTR-A's target).
local WATER_BITS = 0x400002
local CONTENTS_WATER_, CONTENTS_SLIME_, CONTENTS_SOLID_ = CONTENTS_WATER or 0x20, CONTENTS_SLIME or 0x10, CONTENTS_SOLID or 1
local WATER_LINE_EVERY = 0.25
L.water = L.water or { id = nil, wet = false, entries = 0, seconds = 0, falseEntries = 0, falseSeconds = 0, lastLine = -1e9,
                       skipped = 0, notWritten = 0, lastT = nil }
local wprobe = Vector()
local function contents_at(x, y, z)
    if not util.PointContents then return nil end
    wprobe:SetUnpacked(x, y, z)
    local ok, c = pcall(util.PointContents, wprobe)
    return ok and tonumber(c) or nil
end
local function contents_word(c)
    if c == nil then return "?" end
    local w
    if bit.band(c, CONTENTS_WATER_) ~= 0 then
        w = "water"
    elseif bit.band(c, CONTENTS_SLIME_) ~= 0 then
        w = "slime"
    elseif bit.band(c, CONTENTS_SOLID_) ~= 0 then
        w = "solid"
    else
        w = "empty"
    end
    return string.format("%s (0x%X)", w, c)
end
local function gm_wet(c)
    return c ~= nil and bit.band(c, CONTENTS_WATER_ + CONTENTS_SLIME_) ~= 0
end

function GSA1.LogWater(C, st)
    if not (C and st) or st.water_attr == nil then return end      -- a module without the field
    local W = L.water
    local now = SysTime()
    local wet = bit.band(tonumber(st.water_attr) or 0, WATER_BITS) ~= 0
    if W.id ~= C.id then
        -- a new character starts dry: one that starts in water gets an "entered" line
        if W.wet and W.enteredAt then W.seconds = W.seconds + (now - W.enteredAt) end
        W.id, W.wet, W.enteredAt, W.falseNow, W.lastT = C.id, false, nil, false, now
    end
    local dt = now - (W.lastT or now)
    W.lastT = now
    -- the game's water where Garry's Mod has none at the feet (the probe point: the feet + 4 units)
    local feet = nil
    if wet then
        feet = contents_at(st.x or 0, st.y or 0, (st.z or 0) + 4)
        local fake = feet ~= nil and not gm_wet(feet)
        if fake then
            W.falseSeconds = W.falseSeconds + dt
            if not W.falseNow then W.falseEntries = W.falseEntries + 1 end
        end
        W.falseNow = fake
    else
        W.falseNow = false
    end
    if wet == W.wet then return end
    W.wet = wet
    if wet then
        W.entries = W.entries + 1
        W.enteredAt = now
    elseif W.enteredAt then
        W.seconds = W.seconds + (now - W.enteredAt)
        W.enteredAt = nil
    end
    if now - W.lastLine < WATER_LINE_EVERY then
        W.skipped = W.skipped + 1
        W.notWritten = W.notWritten + 1
        return
    end
    feet = feet or contents_at(st.x or 0, st.y or 0, (st.z or 0) + 4)
    local v = GSA1.view
    local vo
    if v and v.origin and v.frame and FrameNumber() - v.frame <= 2 then
        vo = v.origin
    elseif EyePos then
        vo = EyePos()
    end
    local eye = vo and contents_at(vo.x, vo.y, vo.z) or nil
    GSA1.Log("water", "%s %s the game's water at (%.0f %.0f %.0f)%s; Garry's Mod: %s at the feet, %s at the view (%s); "
        .. "host flags %d%s", C.title or "?", wet and "entered" or "left", st.x or 0, st.y or 0, st.z or 0,
        wet and string.format(", its surface at %.0f (water attr 0x%X)", tonumber(st.water_level) or 0,
            tonumber(st.water_attr) or 0) or "", contents_word(feet), contents_word(eye),
        vo and string.format("%.0f %.0f %.0f", vo.x, vo.y, vo.z) or "?", tonumber(C.hostFlags) or 0,
        W.skipped > 0 and string.format(" (%d more changes since the last water line)", W.skipped) or "")
    W.lastLine = now
    W.skipped = 0
end

-- the summary's water line (nil when the character never was in the game's water)
function GSA1.WaterLine()
    local W = L.water
    local secs = W.seconds + ((W.wet and W.enteredAt) and (SysTime() - W.enteredAt) or 0)
    if W.entries == 0 then return nil end
    return string.format("water: in the game's water %d times (%.1f s); game water where Garry's Mod has none at the feet: "
        .. "%d times, %.1f s; %d water changes not written (at most %d lines a second)", W.entries, secs, W.falseEntries,
        W.falseSeconds, W.notWritten, math.floor(1 / WATER_LINE_EVERY + 0.5))
end

hook.Add("Think", "gsa1_log", function()
    local now = SysTime()
    if now >= L.nextFlush then
        L.nextFlush = now + FLUSH_EVERY
        GSA1.LogFlush()
    end
    count_draws()
    dead_watch(now)
end)

-- cl_module.lua's ShutDown hook writes the summary before the module goes; this one is the fallback
hook.Add("ShutDown", "gsa1_log", function()
    GSA1.LogSummary("shutdown")
end)

-- "session log: on (garrysmod/data/gsa1/log.txt), 120 lines this session" (the status lines)
function GSA1.LogLine()
    if not enabled() then return "session log: off (gsa1_log 0)" end
    return string.format("session log: on (garrysmod/data/gsa1/log.txt), %d lines this session%s", L.lines,
        L.dropped > 0 and string.format(" (%d over the cap left out)", L.dropped) or "")
end

concommand.Add("gsa1_log_mark", function(ply, cmd, args, argstr)
    GSA1.Log("mark", "%s; %s", (argstr and argstr ~= "") and argstr or "mark", GSA1.LogContext())
    MsgC(Color(80, 160, 255), "[G-SA1] ", color_white, "marked in the session log\n")
end, nil, "G-SA1: write a marker line into garrysmod/data/gsa1/log.txt (bind a key to it during a test)")

concommand.Add("gsa1_log_where", function()
    GSA1.LogFlush()
    MsgC(Color(80, 160, 255), "[G-SA1] ", color_white, string.format("session log: garrysmod/data/gsa1/log.txt (%d "
        .. "bytes; older sessions in log_previous.txt)%s\n", math.max(file.Size(FILE, "DATA") or 0, 0),
        enabled() and "" or " - off (gsa1_log 0)"))
end, nil, "G-SA1: where the session log is")
