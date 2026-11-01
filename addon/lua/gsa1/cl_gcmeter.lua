-- G-SA1 client: the Lua garbage meter (round 0.9.5; sadc docs/research/board095_perf.md P2). The owner's sessions free
-- 5-22 MB of Lua garbage a second, also with no character; this says, in his session log, how much of it is G-SA1's.
--   * WHAT IS MEASURED: every hook G-SA1 added (an id that is a string starting with "gsa1" - all of G-SA1's are) is
--     wrapped once the addons have loaded (InitPostEntity + 1 s, then again every window: a hook G-SA1 adds or re-adds
--     later is wrapped then); the wrapper reads collectgarbage("count") before and after the hook and adds the change to
--     that hook's slot. The character's entity draws (cl_render.lua ENT:Draw / DrawTranslucent) and the objects' entities
--     (entities/gsa1_base.lua) bracket themselves the same way (slots "Draw / the character", "Draw / objects"). Not
--     measured (stated in the lines): G-SA1's Q-menu pages and spawn-menu icons (VGUI Think / Paint, only while a menu is
--     open: the window counts those frames), net messages, timers, console commands.
--   * ALL OF THE GAME'S LUA: the heap's change from one Think to the next (cl_hitch.lua); a frame in which the collector
--     freed memory (a fall) is left out, and the median of the others is the garbage per frame (LuaJIT collects in cycles:
--     between them the heap only grows, so most frames show exactly what all Lua allocated).
--   * G-SA1'S SHARE: G-SA1's slots summed over the same frames (the frames with a fall left out too: a collector step
--     inside one of G-SA1's hooks would free memory there and hide its garbage); a negative hook change is never added
--     (counted as "disturbed").
--   * BURSTS: a frame whose heap grew by GM.BURST_KB (4 MB) or more gets a "garbage" line (at most one per 10 s; all are
--     counted for the summary) with G-SA1's part of it and the growth between G-SA1's hooks (Think -> PreRender ->
--     HUDPaint -> PostRender -> the next Think: where in the frame the garbage was made; another addon's hook of the SAME
--     event may run before or after G-SA1's).
--   * LINES: the perf line (a character) gets "Lua garbage N KB per frame (...), of it G-SA1's M KB (P %: top 3 hooks)";
--     with no character a short perf line ("perf no character: ...") every GM.NOCHAR_EVERY (30) s; a burst a "garbage"
--     line; the summary a "Lua garbage" line.
--   * COST: about 50-80 ns per wrapped call (two collectgarbage("count") calls; Garry's Mod's LuaJIT: tests/feat_gcmeter_test.lua
--     measures it) - about 0.005-0.008 ms a frame for G-SA1's ~100 hook calls - and no garbage of its own; the median, once
--     per window, 0.1 ms. Off, a wrapper is one test and the call (under 1 ns).
--   * gsa1_log_garbage 0 (Q menu > Options > G-SA1 > Disc and status > Diagnostics): the wrappers pass straight through.
GSA1 = GSA1 or {}
GSA1.GcMeter = GSA1.GcMeter or { slots = {}, list = {}, wrapped = {} }
local GM = GSA1.GcMeter
local cg = collectgarbage
GM.BURST_KB, GM.NOCHAR_EVERY, GM.RING, GM.PREFIX = 4096, 30, 1024, "gsa1"
GM.CHECKPOINTS = { Think = 1, PreRender = 2, HUDPaint = 3, PostRender = 4 }
GM.PHASES = { "Think -> PreRender", "PreRender -> HUDPaint", "HUDPaint -> PostRender", "PostRender -> the next Think" }
GM.on = GM.on or false
GM.cpf, GM.cpk = GM.cpf or { -1, -1, -1, -1 }, GM.cpk or { 0, 0, 0, 0 }
GM.frameKb = GM.frameKb or 0         -- G-SA1's slots in the frame running now
GM.ring, GM.ringN, GM.scratch = GM.ring or {}, GM.ringN or 0, GM.scratch or {}
-- (filled once: growing them inside a window would be garbage of the meter's own)
for i = #GM.ring + 1, GM.RING do GM.ring[i] = 0 end
for i = #GM.scratch + 1, GM.RING do GM.scratch[i] = 0 end

local function slot_of(ev, id)
    local key = ev .. " / " .. id
    local s = GM.slots[key]
    if not s then
        s = { key = key, ev = ev, cp = GM.CHECKPOINTS[ev], kb = 0, wkb = 0, n = 0, neg = 0, tkb = 0 }
        GM.slots[key] = s
        GM.list[#GM.list + 1] = s
    end
    return s
end
GM.Slot = slot_of

-- the change since k0 into slot s (the wrappers and the entity draws). A slot includes the G-SA1 hooks nested in it (the
-- GSA1* events hook.Run inside G-SA1's Think, the render hooks inside a RenderView); G-SA1's frame total adds only the
-- outermost ones (outer: no G-SA1 hook or draw was running when it began)
GM.depth = GM.depth or 0
local function add(s, k0, outer)
    local d = cg("count") - k0
    if d >= 0 then
        s.kb = s.kb + d
        if outer then GM.frameKb = GM.frameKb + d end
    else
        s.neg = s.neg + 1
    end
    s.n = s.n + 1
end
-- (for the entity draws: GM.Enter() -> k0, outer; then GM.Add(slot, k0, outer))
function GM.Enter()
    local outer = GM.depth == 0
    GM.depth = GM.depth + 1
    return cg("count"), outer
end
function GM.Add(s, k0, outer)
    GM.depth = GM.depth - 1
    add(s, k0, outer)
end
local function post(s, k0, outer, ...)
    GM.depth = GM.depth - 1
    add(s, k0, outer)
    return ...
end
GM.pf, GM.pk = GM.pf or { -1, -1, -1, -1 }, GM.pk or { 0, 0, 0, 0 }
local function checkpoint(s, k0)
    local i = s.cp
    local fn = FrameNumber()
    if GM.cpf[i] ~= fn then
        if i == 1 then      -- a new frame's first G-SA1 Think: the frame before keeps its marks for GM.Burst
            local pf, pk, cf, ck = GM.pf, GM.pk, GM.cpf, GM.cpk
            pf[1], pf[2], pf[3], pf[4], pk[1], pk[2], pk[3], pk[4] = cf[1], cf[2], cf[3], cf[4], ck[1], ck[2], ck[3], ck[4]
        end
        GM.cpf[i], GM.cpk[i] = fn, k0
    end
end
local function wrap(s, fn)
    -- (an error in fn skips post: GM.depth stays one too high until GM.Frame puts it right, at most a frame later)
    if s.cp then
        return function(...)
            if not GM.on then return fn(...) end
            local outer = GM.depth == 0
            GM.depth = GM.depth + 1
            local k0 = cg("count")
            checkpoint(s, k0)
            return post(s, k0, outer, fn(...))
        end
    end
    return function(...)
        if not GM.on then return fn(...) end
        local outer = GM.depth == 0
        GM.depth = GM.depth + 1
        return post(s, cg("count"), outer, fn(...))
    end
end

-- wraps every G-SA1 hook not wrapped yet (idempotent; a hook G-SA1 re-added since is wrapped again)
function GM.Wrap()
    local ht = hook.GetTable and hook.GetTable()
    if type(ht) ~= "table" then return 0 end
    local todo, n = {}, 0
    for ev, t in pairs(ht) do
        if type(ev) == "string" and type(t) == "table" then
            for id, fn in pairs(t) do
                if type(id) == "string" and string.sub(id, 1, #GM.PREFIX) == GM.PREFIX and type(fn) == "function" then
                    local w = GM.wrapped[ev] and GM.wrapped[ev][id]
                    if not w or w.wrapper ~= fn then todo[#todo + 1] = { ev, id, fn } end
                end
            end
        end
    end
    for _, e in ipairs(todo) do
        local ev, id, fn = e[1], e[2], e[3]
        local s = slot_of(ev, id)
        local w = wrap(s, fn)
        GM.wrapped[ev] = GM.wrapped[ev] or {}
        GM.wrapped[ev][id] = { wrapper = w, original = fn }
        hook.Add(ev, id, w)
        n = n + 1
    end
    GM.hooks = 0
    for _, t in pairs(GM.wrapped) do for _ in pairs(t) do GM.hooks = GM.hooks + 1 end end
    return n
end

-- the window (reset by each line)
local W = GM.win or { t0 = nil, frames = 0, pos = 0, posSum = 0, gsa1 = 0, falls = 0, menu = 0, n = 0, neg = 0 }
GM.win = W
local function reset_window(now)
    W.t0, W.frames, W.pos, W.posSum, W.gsa1, W.falls, W.menu = now, 0, 0, 0, 0, 0, 0
    GM.ringN = 0
    for _, s in ipairs(GM.list) do s.wkb, s.wn, s.wneg = 0, s.n, s.neg end
end
local S = GM.sess or { frames = 0, pos = 0, posSum = 0, gsa1 = 0, bursts = 0, burstMax = 0, burstGsa1 = 0, phase = {},
                       nextBurst = 0, windows = 0, medSum = 0 }
GM.sess = S

local function menu_open()
    local sm, cm = g_SpawnMenu, g_ContextMenu
    return (IsValid and sm and IsValid(sm) and sm:IsVisible()) or (IsValid and cm and IsValid(cm) and cm:IsVisible()) or
        false
end

-- once per frame from cl_hitch.lua (GSA1.HitchFrame): gc = the heap's change over the frame that ended (KB), counted =
-- a focused frame (no pause)
function GM.Frame(now, gc, counted)
    local mine = GM.frameKb
    GM.frameKb = 0
    -- called inside cl_character.lua's Think hook (gsa1_tick): one level deep when that hook is wrapped (this also ends a
    -- depth left too high by a hook error)
    local tw = GM.wrapped.Think and GM.wrapped.Think.gsa1_tick
    GM.depth = (GM.on and tw and hook.GetTable and (hook.GetTable().Think or {}).gsa1_tick == tw.wrapper) and 1 or 0
    if not GM.on then return end
    if not W.t0 then reset_window(now) end
    -- the frame's phases (the checkpoints of the frame that ended; the next Think checkpoint is now's heap)
    local heap = cg("count")
    if counted and gc then
        W.frames, S.frames = W.frames + 1, S.frames + 1
        if gc >= 0 then
            W.pos, S.pos = W.pos + 1, S.pos + 1
            W.posSum, S.posSum = W.posSum + gc, S.posSum + gc
            W.gsa1, S.gsa1 = W.gsa1 + mine, S.gsa1 + mine
            for _, s in ipairs(GM.list) do s.wkb = s.wkb + (s.kb - (s.last or 0)) end
            if GM.ringN < GM.RING then
                GM.ringN = GM.ringN + 1
                GM.ring[GM.ringN] = gc
            end
            if gc >= GM.BURST_KB then GM.Burst(now, gc, mine, heap) end
        else
            W.falls = W.falls + 1
        end
        if menu_open() then W.menu = W.menu + 1 end
    end
    for _, s in ipairs(GM.list) do s.last = s.kb end
    if not GSA1.Char and now - W.t0 >= GM.NOCHAR_EVERY then GM.WindowLine(now) end
end

-- a frame that made GM.BURST_KB or more
function GM.Burst(now, gc, mine, heap)
    S.bursts = S.bursts + 1
    if gc > S.burstMax then S.burstMax = gc end
    if mine > S.burstGsa1 then S.burstGsa1 = mine end
    local k, ph = GM.pk, {}
    local pf = GM.pf
    local okAll = pf[1] >= 0 and pf[2] == pf[1] and pf[3] == pf[1] and pf[4] == pf[1] and GM.cpf[1] > pf[1]
    local big, bigI = -1, nil
    if okAll then
        local marks = { k[1], k[2], k[3], k[4], GM.cpk[1] }
        for i = 1, 4 do
            local d = marks[i + 1] - marks[i]
            ph[i] = d
            if d > big then big, bigI = d, i end
        end
        if bigI then S.phase[bigI] = (S.phase[bigI] or 0) + 1 end
    end
    if now < S.nextBurst then return end
    S.nextBurst = now + 10
    local where = "the phases of the frame not known (a G-SA1 hook missing in it)"
    if okAll then
        where = string.format("between G-SA1's hooks: %s %.0f KB, %s %.0f KB, %s %.0f KB, %s %.0f KB", GM.PHASES[1], ph[1],
            GM.PHASES[2], ph[2], GM.PHASES[3], ph[3], GM.PHASES[4], ph[4])
    end
    GSA1.Log("garbage", "a frame made %.0f KB of Lua garbage (all of the game's Lua); G-SA1's hooks %.1f KB of it; %s; %s",
        gc, mine, where, GSA1.LogContext and GSA1.LogContext() or "")
end

-- the median of the window's growing frames (KB), nil with fewer than 8
local function median()
    local n = GM.ringN
    if n < 8 then return nil end
    local sc = GM.scratch
    for i = 1, n do sc[i] = GM.ring[i] end
    for i = n + 1, GM.RING do sc[i] = math.huge end     -- (the unused tail sorts last; the table keeps its size)
    table.sort(sc)
    return sc[math.floor((n + 1) / 2)]
end

-- "Lua garbage 188 KB per frame (all of the game's Lua: the median of 571 frames without a collector free; 10.6 MB/s),
-- of it G-SA1's 2.9 KB (1.5 %: CalcView / gsa1_view 0.7, ...; 0 disturbed)"
function GM.Field(now)
    if W.frames == 0 or W.pos == 0 then return nil end
    local med = median()
    local secs = math.max(now - (W.t0 or now), 1e-6)
    local mean = W.posSum / W.pos
    local rate = mean * W.frames / secs / 1024
    local mineF = W.gsa1 / W.pos
    local top = {}
    for _, s in ipairs(GM.list) do
        if s.wkb > 0 then top[#top + 1] = s end
    end
    table.sort(top, function(a, b) return a.wkb > b.wkb end)
    local parts = {}
    for i = 1, math.min(3, #top) do parts[i] = string.format("%s %.2f", top[i].key, top[i].wkb / W.pos) end
    local neg = 0
    for _, s in ipairs(GM.list) do neg = neg + (s.neg - (s.wneg or 0)) end
    local base = med or mean
    S.windows, S.medSum = S.windows + 1, S.medSum + base
    return string.format("Lua garbage %.0f KB per frame (all of the game's Lua: the %s of %d frames without a collector "
        .. "free, %d with one; %.1f MB/s), of it G-SA1's hooks %.2f KB (%.1f %%%s; %d hook samples disturbed by the "
        .. "collector, %d hooks measured%s)", base, med and "median" or "mean", W.pos, W.falls, rate, mineF,
        base > 0 and mineF * 100 / base or 0, #parts > 0 and (": " .. table.concat(parts, ", ")) or "", neg, GM.hooks or 0,
        W.menu > 0 and string.format("; a menu open in %d frames: its pages are not measured", W.menu) or "")
end

-- with no character: a short perf line every GM.NOCHAR_EVERY s
function GM.WindowLine(now)
    local f = GM.Field(now)
    if f then
        GSA1.Log("perf", "no character: %d frames, %.1f fps; %s", W.frames, W.frames / math.max(now - W.t0, 1e-6), f)
    end
    GM.Wrap()
    reset_window(now)
end
-- with a character: cl_log.lua's perf line (every 10 s) takes the field and starts a new window
function GM.TakeField(now)
    if not GM.on then return nil end
    local f = GM.Field(now)
    GM.Wrap()
    reset_window(now)
    return f
end

-- the summary's line
function GM.SummaryLine()
    if S.frames == 0 then return nil end
    local per = S.pos > 0 and S.gsa1 / S.pos or 0
    local base = S.windows > 0 and S.medSum / S.windows or (S.pos > 0 and S.posSum / S.pos or 0)
    local ph = ""
    local best, bi = 0, nil
    for i = 1, 4 do if (S.phase[i] or 0) > best then best, bi = S.phase[i], i end end
    if bi then ph = string.format(", %d of them %s", best, GM.PHASES[bi]) end
    return string.format("Lua garbage: about %.0f KB per frame over the session (all of the game's Lua; the windows' "
        .. "medians), of it G-SA1's hooks %.2f KB (%.1f %%); %d frames made %d KB or more (the largest %.0f KB; G-SA1's "
        .. "hooks at most %.1f KB in one of them%s)", base, per, base > 0 and per * 100 / base or 0, S.bursts, GM.BURST_KB,
        S.burstMax, S.burstGsa1, ph)
end

GM.cv = GSA1.ConVar and GSA1.ConVar("gsa1_log_garbage", 1, "Measure G-SA1's own Lua garbage and all of the game's in "
    .. "the session log (perf / garbage lines; about 0.005 ms a frame)", 0, 1)
function GM.Apply()
    GM.on = not GM.cv or GM.cv:GetBool()
end
if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("gsa1_log_garbage", function() GM.Apply() end, "gsa1_gcmeter")
end
GM.Apply()
hook.Add("InitPostEntity", "gsa1_gcmeter", function()
    timer.Simple(1, function() GM.Wrap() end)
end)
