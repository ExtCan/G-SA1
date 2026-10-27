-- gc_bench.lua - how long Garry's Mod's LuaJIT collector can hold a frame (a measurement tool, not a test; round 4c,
-- the Light Speed charge freeze: "Lua GC from per-frame garbage" was one of the suspects).
--   lua_host tests/gc_bench.lua [heap MB = 200]
-- Builds a live heap of about the given size (small tables and strings, like a GMod session with addons), then runs
-- 1200 "frames" that each make some garbage, letting the collector run as it does in the game (incremental, driven by
-- allocation), and prints the slowest frame and the mean for 3 KB (G-SA1 0.6.0's measured garbage per frame, mock
-- included), 30 KB and 300 KB of garbage per frame; finally one full collectgarbage("collect") of the heap (what an
-- addon calling collectgarbage() costs).
local mb = tonumber(arg and arg[1]) or 200
local clock = host_clock
local function out(fmt, ...) host_write(string.format(fmt, ...) .. "\n") end
out("gc_bench in %s: building a live heap of about %d MB", tostring(jit and jit.version), mb)
collectgarbage("collect")
local live = {}
local n = 0
while collectgarbage("count") < mb * 1024 do
    n = n + 1
    live[n] = { x = n, y = n * 2, s = "s" .. n, t = { n } }
end
out("  %d live objects, heap %.0f MB", n * 3, collectgarbage("count") / 1024)
collectgarbage("collect")
local junk = {}
for _, per in ipairs({ 3, 30, 300 }) do
    local per_tables = math.floor(per * 1024 / 64)          -- about 64 bytes per small table
    local worst, sum = 0, 0
    for f = 1, 1200 do
        local t0 = clock()
        for i = 1, per_tables do junk[(i % 64) + 1] = { i, i } end
        local dt = clock() - t0
        sum = sum + dt
        if dt > worst then worst = dt end
    end
    out("  %4d KB of garbage per frame: mean %.3f ms, slowest frame %.2f ms (the collector's steps included)", per,
        sum * 1000 / 1200, worst * 1000)
end
local t0 = clock()
collectgarbage("collect")
out("  one full collectgarbage(\"collect\") of the %.0f MB heap: %.1f ms", collectgarbage("count") / 1024,
    (clock() - t0) * 1000)
live = nil
return true
