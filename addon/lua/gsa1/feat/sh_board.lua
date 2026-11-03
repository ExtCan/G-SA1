-- G-SA1 feature "board", shared part (both realms; round 0.9.5: sadc docs/research/gsa1_095_plan.md 4, 5.5, 5.6, 5.8 and
-- 6.4 with its Review R.3 / R.5 / R.10 / R.12, board095_gsa1.md 3, 5, 8; the owner's binding answers gsa1_rounds_plan.md
-- 14.1ad).
--
-- The owner: Sonic and Tails ride the sand / snow board of Sand Hill and Ice Cap by the game's own code - on and off with
-- the board key (B) or button (right stick click) while the emote wheel is open, or through two trigger boxes of the
-- G-SA1 spawn tab: "Board On" (a board lies in its middle; a Sonic / Tails walking in walks to it by himself and gets on)
-- and "Board Off" (he gets off; the board stays behind). A board left behind is decoration that nobody rides again (a
-- gsa1_board_left entity). Only Sonic and Tails; everything is per CHARACTER world (0.9.6's followers board the same way:
-- the messages carry a character slot).
--
-- This file: the settings (every one has a control on Q menu > Options > G-SA1 > Board: feat/cl_board.lua), the
-- constants, the network strings' names, the cleanup / limit language, the context menu's "Reset this box", and the pure
-- rules both realms share:
--   * B.Edge - the swept edge test of a character's positions against the boxes (the server runs it on each NEW state
--     packet of a character player, 20 Hz; the client may run it for 0.9.6's followers): the point is the reported
--     position (the feet) + LIFT; "inside" is the point in the box's own frame, grown by EXIT_PAD while it was inside
--     (hysteresis); a JUMP (no sample before, or a move longer than max(JUMP_MIN, SPEED_CAP x dt + SLACK): a teleport, a
--     respawn) tests only the new point; otherwise the segment from the last sample to this one enters the box (the slab
--     test's entry parameter t in [0, 1]); several entries of one packet in the order of t; a broad phase (the segment's
--     distance to the box's centre against its half diagonal + EXIT_PAD). Prototyped by res-gsa1-board (9 of 9 cases,
--     3.1-3.3 us per packet with 200 boxes in Garry's Mod's LuaJIT: board095_gsa1.md 5.6);
--   * B.CanBoard(C) - only Sonic (kind 0) and Tails (kind 2); never Super Sonic (Vs. Perfect Chaos, kind 8); General
--     Gameplay Super Sonic and a Sonic while Super only with gsa1_board_super 1 (review R.12: the game would take order 44
--     from them; G-SA1's refusal is a host rule behind that option); boards on (gsa1_board); the module's feature; alive;
--     not a puppet;
--   * B.WalkDeadline(distance) = max(4, distance / 40 + 2) s (review R.3: the client's walk and the server's claim);
--   * B.FovDegrees(spd) - Sand Hill's speed field of view (0C90327E: BAMS 12743 + 5461 sqrt(0.12787 spd.x) below 7.82);
--   * the box's frame, its hull and where a new box goes.
GSA1 = GSA1 or {}
GSA1.Board = GSA1.Board or {}
local B = GSA1.Board

B.NEEDS = { feature = "board", version = 1, module = "0.9.5" }
B.KIND_SONIC, B.KIND_TAILS, B.KIND_SUPER = 0, 2, 8
B.SONIC_MODES, B.TAILS_MODES = { 62, 68 }, { 48, 54 }
-- the wheel's board rows (the board actions: the board task holds a lying board to him while his action is one of them,
-- 8C0B2F46 / 8C0BF804; review R.12)
B.BOARD_ROWS = { [0] = { 102, 124 }, [2] = { 107, 127 } }
B.TERRAIN = { MAP = 0, SNOW = 1, SAND = 2 }
B.TERRAIN_TITLE = { [0] = "the map's surfaces", [1] = "Ice Cap snow", [2] = "Sand Hill sand" }
B.DRAW = 0x4000                        -- SA1_DRAW_BOARD (the render lane's rule: cl_render.lua)
B.PREVIEW_BOARD = 0x100                -- SA1_PREVIEW_BOARD (the module's gsa1.PREVIEW.BOARD wins)

-- the net protocol (gsa1_095_plan.md 5.6)
B.NET = { BOX = "gsa1_board_box", TOOK = "gsa1_board_took", CANCEL = "gsa1_board_cancel", ST = "gsa1_board_st",
          LEFT = "gsa1_board_left" }
B.WHAT = { GO = 1, OFF = 2, RIDING = 3, GONE = 4, SPENT = 5 }
B.WHAT_NAME = { [1] = "GO", [2] = "OFF", [3] = "RIDING", [4] = "GONE", [5] = "SPENT" }
B.WHY = { WHEEL = 0, BOX = 1, RECREATED = 2, RESPAWNED = 3, OFF_BOX = 4 }
B.WHY_NAME = { [0] = "the wheel", [1] = "a Board On box", [2] = "re-created", [3] = "respawned", [4] = "a Board Off box" }
-- GSA1BoardChanged(C, on, why)'s word (gsa1_095_plan.md 5.5): "wheel", "box", "re-created", "respawned", "off box", "removed"
B.WHY_WORD = { [0] = "wheel", [1] = "box", [2] = "re-created", [3] = "respawned", [4] = "off box" }
-- why a walk to a box's board ended without getting on (gsa1_board_cancel's u3)
B.CANCEL = { JUMP = 1, DEADLINE = 2, LEFT = 3, HURT = 4, GONE = 5, REFUSED = 6, TIMEOUT = 7 }
B.CANCEL_NAME = { [1] = "jumped", [2] = "the walk took too long", [3] = "left the box", [4] = "was hurt",
                  [5] = "the character went", [6] = "could not get on", [7] = "the server took the board back" }
B.NW_RIDING = "gsa1_board"             -- the player's NW2 bool (slot 0): riding a board (for 0.9.x's puppets)

-- the edge test (board095_gsa1.md 5.6)
B.LIFT, B.EXIT_PAD = 16, 16            -- HU: the reported feet + LIFT; the hysteresis while inside
B.JUMP_MIN, B.SPEED_CAP, B.SLACK = 512, 6000, 256
-- the walk (gsa1_095_plan.md 4.14, board095_gsa1.md 5.4: the game's walk is a stick of 0.6-0.8, 45-49 HU/s)
B.WALK_STICK, B.JOG_STICK, B.STICK_MIN = 0.7, 1.0, 0.6
B.WALK_FAST = 0.5                      -- SA1 units per step: faster than this he keeps running (stick 1.0)
B.REACH_H, B.REACH_V = 24, 40          -- HU: the last pair's path this close to the board -> on
B.WALK_SPEED = 40                      -- HU/s: the deadline's walking speed
B.WALK_MIN_TIME, B.WALK_SLACK = 4, 2   -- s
B.CLAIM_EXTRA = 2                      -- s: a claim lives the walk's deadline + this (review R.3)
B.LEAVE_OUT = 64                       -- HU outside the box: the walk ends
-- the hand-over of a board got off (gsa1_095_plan.md 4.8, review R.5)
B.LEAVE_MAX = 2                        -- s: the kept board is handed over when settled, or after this long
B.FREE_AFTER = 1                       -- s: the rider's world frees its board at the latest this long after sending
B.LEFT_RADIUS = 2048                   -- HU: a left board within this of the sender's character
B.LEFT_BUCKET, B.LEFT_REFILL = 3, 1    -- gsa1_board_left: a bucket of 3, refilled at 1 a second (review R.5)
B.OFF_USE_WINDOW = 5                   -- s: a Board Off box counts a use only after the server's OFF (review R.3)
B.MSG_RATE, B.MSG_BURST = 10, 10       -- client messages per second per player
B.GONE_EVERY = 2                       -- s: GONE / SPENT at most this often per player and box
-- the boxes
B.SIZE_MIN, B.SIZE_MAX = 32, 8192
B.DEFAULT = { Width = 256, Length = 256, Height = 192, RefillAfter = 5, Push = 1, Ground = 0, Uses = 0 }
B.REFILL_MAX = 600
B.PHYS_MAX = 2048                      -- HU: the physics box's half size at most (sh_objects.lua O.PHYS_MAX)
B.TRACE_DOWN = 4096                    -- HU: the board place is traced down this far from the base centre
-- the view (board095_gsa1.md 8)
B.CAM_TAU, B.CAM_PAUSE = 0.4, 1.0      -- s: the camera's time constant behind the board; the pause after a turn
B.FOV_RATE = 512 * 360 / 65536 * 60    -- 168.75 degrees a second (Ice Cap's 0x200 BAMS a frame)

B.CLASSES = {
    { class = "gsa1_board_on", title = "Board On", kind = "on" },
    { class = "gsa1_board_off", title = "Board Off", kind = "off" },
}
B.BY_CLASS = {}
for _, c in ipairs(B.CLASSES) do B.BY_CLASS[c.class] = c end
B.LEFT_CLASS = "gsa1_board_left"

-- a trigger box of this feature (Board On / Off); the left board is no box
function B.IsBox(ent)
    return ent ~= nil and ent ~= NULL and type(ent) ~= "number" and ent.GSA1Trigger == true and
        B.BY_CLASS[ent.GetClass and ent:GetClass() or ""] ~= nil
end
function B.IsLeft(ent)
    return ent ~= nil and ent ~= NULL and type(ent) ~= "number" and ent.GetClass ~= nil and ent:GetClass() == B.LEFT_CLASS
end
function B.BoxKind(ent)
    local c = B.BY_CLASS[ent and ent.GetClass and ent:GetClass() or ""]
    return c and c.kind or nil
end

-- the settings (gsa1_095_plan.md 5.8) -------------------------------------------------------------------------------------
B.cv = B.cv or {}
local cv = B.cv
-- client (GSA1.ConVar: nil on the server)
cv.on = GSA1.ConVar("gsa1_board", 1, "Boards for Sonic and Tails: 1 = the board key in the open emote wheel and the Board On "
    .. "/ Board Off boxes work for you (0 = they do nothing)", 0, 1)
cv.key = GSA1.ConVar("gsa1_board_key", 12, "The board key while the emote wheel is open (a key code; 12 = B; 0 = none): "
    .. "Sonic or Tails gets on a board, or off it", 0, 511)
cv.pad = GSA1.ConVar("gsa1_board_pad", 0x0080, "The board button while the emote wheel is open (XInput bits: 128 = right "
    .. "stick click; 0 = none)", 0, 0x30000)
cv.terrain = GSA1.ConVar("gsa1_board_terrain", 0, "The ground under the board: 0 = the map's own surfaces (the game's rule: "
    .. "snow and sand speed the board up downhill), 1 = Ice Cap snow everywhere, 2 = Sand Hill sand everywhere (1 and 2 "
    .. "are not the game's own behaviour)", 0, 2)
cv.walk = GSA1.ConVar("gsa1_board_walk", 0, "Walking to a Board On box's board: 0 = the game's walk, 1 = a jog (a run-in "
    .. "keeps running either way)", 0, 1)
cv.push = GSA1.ConVar("gsa1_board_push", 0, "Ice Cap's start push (about 960 HU/s) when you get on with the wheel (Board On "
    .. "boxes have their own setting)", 0, 1)
cv.camera = GSA1.ConVar("gsa1_board_camera", 1, "The camera turns behind the board while you ride (it waits a second "
    .. "after you turn it yourself)", 0, 1)
cv.fov = GSA1.ConVar("gsa1_board_fov", 0, "Widen the view at speed while riding (the game's 70 to 100 degrees)", 0, 1)
cv.fov_mode = GSA1.ConVar("gsa1_board_fov_mode", 0, "The field of view while riding: 0 = yours plus up to 30 degrees, "
    .. "1 = the game's own 70 to 100 degrees", 0, 1)
cv.sounds = GSA1.ConVar("gsa1_board_sounds", 1, "Board sounds: Ice Cap's snow and Sand Hill's sand while riding (0 = silent)",
    0, 1)
cv.respawn = GSA1.ConVar("gsa1_board_respawn", 0, "Back on a board after a respawn, when you died riding one", 0, 1)
cv.tails_jump = GSA1.ConVar("gsa1_board_tails_jump", 0, "Keep the game's Tails jump: higher each time he gets on a board "
    .. "(the game's own bug; 0 = his jump is restored when he gets off)", 0, 1)
cv.super = GSA1.ConVar("gsa1_board_super", 0, "Super Sonic may ride a board too (General Gameplay Super Sonic, and Sonic "
    .. "while Super; the game lets him - how he looks: unverified). Super Sonic (Vs. Perfect Chaos) never rides", 0, 1)
cv.box_show = GSA1.ConVar("gsa1_board_box_show", 0, "Show the Board On / Off boxes: 0 = while editing (no character, or the "
    .. "context menu open), 1 = always", 0, 1)
-- server (replicated, archived: both realms)
cv.sv_on = GSA1.ConVar("gsa1_sv_board", 1, "Board On / Board Off boxes work on this server (0 = they can be placed but do "
    .. "nothing)", 0, 1, { server = true })
cv.sv_left_time = GSA1.ConVar("gsa1_sv_board_left_time", 120, "Seconds a board left behind stays (0 = until undone or "
    .. "cleaned up)", 0, 3600, { server = true })
cv.sv_left_max = GSA1.ConVar("gsa1_sv_board_left_max", 5, "Boards left behind per player (the oldest goes first; 0 = none: "
    .. "the board vanishes when you get off)", 0, 64, { server = true })
-- the sandbox limit (sbox_max<name>; GSA1.ConVar takes only gsa1_ names): made here and listed by hand
local LIMIT_FLAGS = bit.bor(FCVAR_ARCHIVE or 128, FCVAR_NOTIFY or 256, FCVAR_REPLICATED or 8192)
cv.sv_limit = GetConVar("sbox_maxgsa1_triggers") or CreateConVar("sbox_maxgsa1_triggers", "100", LIMIT_FLAGS,
    "Most G-SA1 trigger boxes (Board On / Board Off) one player may place", 0, 10000)
GSA1.CONVARS = GSA1.CONVARS or {}
GSA1.CONVARS.sbox_maxgsa1_triggers = { cv = cv.sv_limit, default = "100", help = "Most G-SA1 trigger boxes per player",
    min = 0, max = 10000, server = true }

-- the cleanup (Utilities > Cleanup) and the limit's text -----------------------------------------------------------------
if cleanup and cleanup.Register then
    cleanup.Register("gsa1_triggers")
    cleanup.Register("gsa1_board_left")
end
if CLIENT and language and language.Add then
    language.Add("Cleanup_gsa1_triggers", "G-SA1 trigger boxes")
    language.Add("Cleaned_gsa1_triggers", "Cleaned up the G-SA1 trigger boxes")
    language.Add("SBoxLimit_gsa1_triggers", "You have reached the G-SA1 trigger boxes limit!")
    language.Add("Cleanup_gsa1_board_left", "G-SA1 left boards")
    language.Add("Cleaned_gsa1_board_left", "Cleaned up the G-SA1 left boards")
    for _, c in ipairs(B.CLASSES) do language.Add(c.class, "G-SA1 " .. c.title) end
    language.Add(B.LEFT_CLASS, "G-SA1 left board")
end

-- pure rules ----------------------------------------------------------------------------------------------------------------
local rad, sin, cos, sqrt, abs, max, min = math.rad, math.sin, math.cos, math.sqrt, math.abs, math.max, math.min

-- Source's AngleVectors: forward, right, up of (pitch, yaw, roll) degrees as {x, y, z}
function B.Axes(p, y, r)
    local sp, cp, sy, cy, sr, cr = sin(rad(p or 0)), cos(rad(p or 0)), sin(rad(y or 0)), cos(rad(y or 0)),
        sin(rad(r or 0)), cos(rad(r or 0))
    return { cp * cy, cp * sy, -sp }, { -sr * sp * cy + cr * sy, -sr * sp * sy - cr * cy, -sr * cp },
        { cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp }
end

-- the up axis alone, as three numbers (no table: the per-frame drawing)
function B.UpOf(p, y, r)
    local sp, cp, sy, cy, sr, cr = sin(rad(p or 0)), cos(rad(p or 0)), sin(rad(y or 0)), cos(rad(y or 0)),
        sin(rad(r or 0)), cos(rad(r or 0))
    return cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp
end

-- a box's data for the edge test: base centre (x, y, z), angles, Length (forward), Width (left), Height (up); key: what
-- the players' "inside" is kept by (the entity)
function B.MakeBox(key, x, y, z, p, yw, r, L, W, H)
    local f, rt, u = B.Axes(p, yw, r)
    local b = { key = key, x = x, y = y, z = z, f = f, r = rt, u = u, lo = { -L / 2, -W / 2, 0 }, hi = { L / 2, W / 2, H } }
    b.cx, b.cy, b.cz = x + u[1] * H / 2, y + u[2] * H / 2, z + u[3] * H / 2
    b.rad = sqrt((L / 2) ^ 2 + (W / 2) ^ 2 + (H / 2) ^ 2)
    return b
end

-- a point in the box's frame (forward, left = -right, up: as sh_objects.lua O.RayHull)
local function to_local(b, x, y, z)
    local dx, dy, dz = x - b.x, y - b.y, z - b.z
    local f, r, u = b.f, b.r, b.u
    return dx * f[1] + dy * f[2] + dz * f[3], -(dx * r[1] + dy * r[2] + dz * r[3]), dx * u[1] + dy * u[2] + dz * u[3]
end
B.ToLocal = to_local

local function inside(b, x, y, z, pad)
    local a, c, e = to_local(b, x, y, z)
    pad = pad or 0
    return a >= b.lo[1] - pad and a <= b.hi[1] + pad and c >= b.lo[2] - pad and c <= b.hi[2] + pad and
        e >= b.lo[3] - pad and e <= b.hi[3] + pad
end
B.Inside = inside

-- how far (HU) a point lies outside the box (0 inside)
function B.Outside(b, x, y, z)
    local a, c, e = to_local(b, x, y, z)
    local da = max(b.lo[1] - a, 0, a - b.hi[1])
    local dc = max(b.lo[2] - c, 0, c - b.hi[2])
    local de = max(b.lo[3] - e, 0, e - b.hi[3])
    return sqrt(da * da + dc * dc + de * de)
end

-- the entry parameter t in [0, 1] of the segment p0 -> p1 into the box (slabs); nil: it misses
local o_, d_ = { 0, 0, 0 }, { 0, 0, 0 }
local function seg_enter(b, x0, y0, z0, x1, y1, z1)
    local o1, o2, o3 = to_local(b, x0, y0, z0)
    local e1, e2, e3 = to_local(b, x1, y1, z1)
    o_[1], o_[2], o_[3], d_[1], d_[2], d_[3] = o1, o2, o3, e1 - o1, e2 - o2, e3 - o3
    local t0, t1 = 0, 1
    for i = 1, 3 do
        if abs(d_[i]) < 1e-9 then
            if o_[i] < b.lo[i] or o_[i] > b.hi[i] then return nil end
        else
            local a, c = (b.lo[i] - o_[i]) / d_[i], (b.hi[i] - o_[i]) / d_[i]
            if a > c then a, c = c, a end
            if a > t0 then t0 = a end
            if c < t1 then t1 = c end
            if t0 > t1 then return nil end
        end
    end
    return t0
end
B.SegEnter = seg_enter

-- the broad phase: the segment passes within the box's half diagonal + EXIT_PAD of its centre
local function seg_near(b, x0, y0, z0, x1, y1, z1)
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local L2 = dx * dx + dy * dy + dz * dz
    local t = 0
    if L2 > 0 then t = max(0, min(1, ((b.cx - x0) * dx + (b.cy - y0) * dy + (b.cz - z0) * dz) / L2)) end
    local px, py, pz = x0 + dx * t - b.cx, y0 + dy * t - b.cy, z0 + dz * t - b.cz
    local R = b.rad + B.EXIT_PAD
    return px * px + py * py + pz * pz <= R * R
end
B.SegNear = seg_near

-- a new box: each track's "inside" from its last sample (placing a box on a character does nothing until he leaves and
-- comes back)
function B.Seed(track, b)
    local l = track and track.last
    if not l then return false end
    local inn = inside(b, l[1], l[2], l[3], 0)
    track.inside[b.key] = inn or nil
    return inn
end

local NO_ENTRIES = {}
-- one sample (x, y, z: the reported feet; t: the time of the sample) of a track ({inside = {[key] = true}, last}) against
-- the list of boxes: the entries of this sample in the order crossed ({box, t} ...; NO_ENTRIES when none: never written)
-- and, in exits (a list given by the caller, or nil), the boxes it left
function B.Edge(track, list, x, y, z, t, exits)
    z = z + B.LIFT
    local l = track.last
    local jump = l == nil
    if l then
        local dx, dy, dz = x - l[1], y - l[2], z - l[3]
        jump = sqrt(dx * dx + dy * dy + dz * dz) > max(B.JUMP_MIN, B.SPEED_CAP * (t - l[4]) + B.SLACK)
    end
    local ev = nil
    local states, pad = track.inside, B.EXIT_PAD
    for i = 1, #list do
        local b = list[i]
        local key = b.key
        local was = states[key] == true
        local near = jump or seg_near(b, l[1], l[2], l[3], x, y, z)
        local now_in = near and inside(b, x, y, z, was and pad or 0) or false
        if not was and near then
            local th
            if jump then
                th = now_in and 1 or nil
            else
                th = seg_enter(b, l[1], l[2], l[3], x, y, z)
            end
            if th then
                ev = ev or {}
                ev[#ev + 1] = { box = b, t = th }
            end
        end
        if was and not now_in and exits then exits[#exits + 1] = b end
        states[key] = now_in or nil
    end
    if ev and #ev > 1 then table.sort(ev, function(a, c) return a.t < c.t end) end
    if l then
        l[1], l[2], l[3], l[4] = x, y, z, t
    else
        track.last = { x, y, z, t }
    end
    return ev or NO_ENTRIES
end

function B.NewTrack() return { inside = {}, last = nil } end

-- the walk's deadline (s) for a board `distance` HU away; the server's claim lives this + CLAIM_EXTRA (review R.3)
function B.WalkDeadline(distance)
    return max(B.WALK_MIN_TIME, (tonumber(distance) or 0) / B.WALK_SPEED + B.WALK_SLACK)
end

-- the game's speed field of view (degrees) at spd.x (SA1 units per step): Sand Hill's 0C90327E
function B.FovDegrees(spd)
    spd = tonumber(spd) or 0
    local k = 0
    if spd >= 7.82 then
        k = 1
    elseif spd > 0 then
        k = sqrt(0.12787 * spd)
    end
    return (12743 + 5461 * k) * 360 / 65536
end

-- the board mode ranges of a kind (Sonic 62-68, Tails 48-54)
function B.IsBoardMode(kind, mode)
    mode = tonumber(mode) or -1
    local r = (kind == B.KIND_SONIC and B.SONIC_MODES) or (kind == B.KIND_TAILS and B.TAILS_MODES) or nil
    return r ~= nil and mode >= r[1] and mode <= r[2]
end

-- a wheel row that is one of the kind's board actions (review R.12); e: the wheel's catalogue entry
function B.IsBoardRow(kind, e)
    if type(e) ~= "table" or e.source == 1 then return false end
    local r = B.BOARD_ROWS[kind]
    local n = tonumber(e.index) or -1
    return r ~= nil and n >= r[1] and n <= r[2]
end

-- may character C ride a board (true, or false and the plain reason); opts.have: the module's feature (the caller knows)
function B.CanBoard(C, have)
    if not C then return false, "no character" end
    if C.puppet then return false, "another player's character" end
    if C.form == "question" then return false, "the ? doesn't ride a board" end
    if C.kind == B.KIND_SUPER then return false, "Super Sonic doesn't ride a board" end
    if C.kind ~= B.KIND_SONIC and C.kind ~= B.KIND_TAILS then return false, "only Sonic and Tails ride a board" end
    if (C.form == "general" or C.superForm == true) and not (cv.super and cv.super:GetBool()) then
        return false, "Super Sonic doesn't ride a board"
    end
    if cv.on and not cv.on:GetBool() then return false, "boards are off (Board page)" end
    if have == false then return false, "this G-SA1 module has no board (G-SA1 module 0.9.5 or newer)" end
    if C.death then return false, "the character is dead" end
    return true
end

-- the box's hull in its own frame: the base centre is the origin, the box grows up from it
function B.Size(ent)
    local function get(name)
        local g = ent and ent["Get" .. name]
        local v = g and tonumber(g(ent)) or 0
        if v <= 0 then v = B.DEFAULT[name] end
        return math.Clamp(v, B.SIZE_MIN, B.SIZE_MAX)
    end
    return get("Length"), get("Width"), get("Height")
end
function B.Hull(ent)
    local L, W, H = B.Size(ent)
    return Vector(-L / 2, -W / 2, 0), Vector(L / 2, W / 2, H)
end

-- where a new box goes: its base on the aimed surface, the placer's yaw, upright
function B.SpawnPlace(tr, yaw)
    local pos = Vector(tr.HitPos)
    pos.z = pos.z + 0.5
    return pos, Angle(0, math.NormalizeAngle(tonumber(yaw) or 0), 0)
end

-- the angles of a board lying on ground of normal n (a table x, y, z; up = n), turned by yaw (degrees): pitch, yaw, roll
function B.GroundAngles(yaw, n)
    local nx, ny, nz = n and n.x or 0, n and n.y or 0, n and n.z or 1
    local l = sqrt(nx * nx + ny * ny + nz * nz)
    if l < 1e-6 or nz < 0.05 then return 0, yaw, 0 end
    nx, ny, nz = nx / l, ny / l, nz / l
    local fx, fy = cos(rad(yaw)), sin(rad(yaw))
    -- forward on the plane
    local d = fx * nx + fy * ny
    local px, py, pz = fx - nx * d, fy - ny * d, -nz * d
    local pl = sqrt(px * px + py * py + pz * pz)
    if pl < 1e-6 then return 0, yaw, 0 end
    px, py, pz = px / pl, py / pl, pz / pl
    local pitch = math.deg(math.asin(math.Clamp(-pz, -1, 1)))
    local yw = math.deg(math.atan2(py, px))
    local _, r0, u0 = B.Axes(pitch, yw, 0)
    -- up = cos(roll) u0 + sin(roll) r0 (Source's AngleVectors)
    local roll = math.deg(math.atan2(nx * r0[1] + ny * r0[2] + nz * r0[3], nx * u0[1] + ny * u0[2] + nz * u0[3]))
    return pitch, yw, roll
end

-- a copy (the duplicator, a save) keeps the editable values and starts fresh: the board there, no use counted
function B.FreshState(dt)
    if type(dt) ~= "table" then return end
    if dt.Used ~= nil then dt.Used = 0 end
    if dt.Present ~= nil then dt.Present = true end
    if dt.RespawnAt ~= nil then dt.RespawnAt = 0 end
end

-- a box with Uses 1 that was used
function B.Spent(ent)
    local uses = ent.GetUses and tonumber(ent:GetUses()) or 0
    local used = ent.GetUsed and tonumber(ent:GetUsed()) or 0
    return uses == 1 and used >= 1
end

-- the context menu's properties that make no sense on a box or a left board (as sh_objects.lua O.NO_PROPERTIES)
B.NO_PROPERTIES = { collision = true, gravity = true, drive = true, keepupright = true, ignite = true, extinguish = true,
                    statue = true, bonemanipulate = true, skin = true, bodygroups = true, persist = true }
if hook and hook.Add then
    hook.Add("CanProperty", "gsa1_board", function(ply, property, ent)
        if B.NO_PROPERTIES[property] and (B.IsBox(ent) or B.IsLeft(ent)) then return false end
    end)
end

-- may ply reset ent ("Reset this box"): admins, the box's placer, single player, the listen server's host, the console
function B.MayReset(ply, ent)
    if not IsValid(ply) then return true end
    if game and game.SinglePlayer and game.SinglePlayer() then return true end
    if ply.IsListenServerHost and ply:IsListenServerHost() then return true end
    if ply.IsAdmin and ply:IsAdmin() then return true end
    if ent and ent.GetPlacer then
        local p = ent:GetPlacer()
        if IsValid(p) and p == ply then return true end
    end
    return false
end

-- the context menu: "Reset this box" (both realms)
if properties and properties.Add then
    properties.Add("gsa1_board_reset", {
        MenuLabel = "Reset this box",
        Order = 610,
        MenuIcon = "icon16/arrow_refresh.png",
        Filter = function(self, ent, ply)
            if not B.IsBox(ent) or not B.MayReset(ply, ent) then return false end
            if gamemode and gamemode.Call and not gamemode.Call("CanProperty", ply, "gsa1_board_reset", ent) then
                return false
            end
            return true
        end,
        Action = function(self, ent)
            self:MsgStart()
            net.WriteEntity(ent)
            self:MsgEnd()
        end,
        Receive = function(self, length, ply)
            local ent = net.ReadEntity()
            if not properties.CanBeTargeted(ent, ply) or not self:Filter(ent, ply) then return end
            if B.ResetBox then B.ResetBox(ent, "Reset this box") end
        end,
    })
end
