-- feat_look_test.lua - the head look's addon side (round 0.9.8: sadc docs/research/gsa1_098_plan.md 5.9, 6.8 with 2.4 D10 and
-- decision A22; gsa1_096_plan.md 4.20, 5.5, 5.6, 6.6 with its review R.12 / R.13; look096.md 7.2, 8.3): feat/sh_look.lua and
-- feat/cl_look.lua in Garry's Mod's own LuaJIT, the client through the autorun against tests/lua_mock.lua (this test's own stubs
-- for what that file does not have: it is 098-gsa1-followlua's) and a MOCK MODULE of 5.5 (feature "look" 1: gsa1.Look,
-- gsa1.LookState, the constants; every call recorded, the arguments checked as src/module/bind_look.cpp checks them).
--   lua_host tests/feat_look_test.lua <tests dir> <addon/lua dir>
-- The mock is checked against build/x86_64-windows/look_api.txt (tests/feat_look_binding_test.cpp writes it) as soon as the
-- snapshot header build/deps/include/libsa1.h defines SA1_API_LOOK (5.5); before that the check is skipped.
--
-- API NOTES (098-gsa1-look, the full text; the report carries a summary):
--   * GSA1.Look = L (feat/sh_look.lua, both realms): L.Choose(looker, pool, n, options, now) -> candidate | nil (no allocation),
--     L.SetOptions, L.Radius(range, farthest), L.CategoryOf(I.Category's word), L.IsOurClass, L.IsItemClass, L.NewLooker(id,
--     follower), L.SetFacing(l, yawDegrees), L.Block(l, key, now), L.PointAt(candidate, now) -> x, y, z, L.NEEDS, L.CAT_*.
--   * feat/cl_look.lua: L.cv (every ConVar of 5.9's look rows), L.Have(), L.lookers / L.nlookers / L.byId (looker tables: never
--     another feature's), L.pool / L.npool / L.nall, L.Frame(C, now), L.Round, L.Scan(C, radius, now), L.Traces(now),
--     L.Send(C, now), L.StatusLines(), L.BuildPage(panel), L.ApplySuper(C, on), L.LogSettings(), L.LogLine(now),
--     L.HooksField(frames), L.stats. Hooks "gsa1_look": GSA1PreTick (everything per frame), GSA1CharacterCreated (the settings
--     line once, Super Sonic's head), GSA1CharacterLeaving, GSA1CharacterRemoved (one LOOK_OFF to every follower: review R.13),
--     GSA1CharacterDied, GSA1FollowerCreated, GSA1FollowerRemoved. It writes no field of a character or follower table.
--   * Choices the plan leaves open, each checked below: the leader's range is L.LEADER_RANGE (2,400 HU), not gsa1_look_range; a
--     follower never picks another follower of this client (else a group only looks at itself); gsa1.EmoteState gives the
--     emote's state (gsa1.GetState has no emote_state: re-checked against gsa1_module.cpp); a point is sent when it changed (a
--     look stays latched), moving from one round's sample to the next (no engine Vector per looker per frame: D10); a held follower
--     (F.held, 096 review R.15) gets one LOOK_OFF and is out of the lookers' choice, the candidates and the pool's radius.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_look_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files and the interaction's (I.EntityInfo, I.Category, I.killed); the other features have their own tests
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_look%.lua$") or string.find(n, "_interact%.lua$") then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end
hook.GetTable = function() return M.hooks end

-- the mock module with the feature ------------------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ features = { look = 1 } })
local R = { looks = {}, on = true, kind = {}, state = {}, opts = {}, refuse = { [6] = "the game never makes a look task for E-102" },
            emote = 0, yaw = 0 }
G.LOOK_OFF, G.LOOK_POINT, G.LOOK_ANGLES, G.LOOK_CAMERA, G.LOOK_OVERRIDE_GAME, G.COPT_SUPER_LOOK = 0, 1, 2, 3, 1, 7
local create = G.Create
function G.Create(kind, pos, yaw, ups, rings)
    local id = create(kind, pos, yaw, ups, rings)
    R.kind[id] = kind
    return id
end
local function bad(a) return type(a) ~= "number" or a ~= a or math.abs(a) > 1e30 end
function G.Look(id, kind, a, b, c, flags)
    if type(id) ~= "number" or id < 1 or type(kind) ~= "number" or kind < 0 or kind > 3 then
        R.badcalls = (R.badcalls or 0) + 1
        return false, "Look(id, kind [, a, b, c] [, flags])", "bad_argument"
    end
    if kind == G.LOOK_POINT and (bad(a) or bad(b) or bad(c)) then
        R.badcalls = (R.badcalls or 0) + 1
        return false, "Look(id, gsa1.LOOK_POINT, x, y, z [, flags])", "bad_argument"
    end
    if R.on then R.looks[#R.looks + 1] = { id = id, kind = kind, a = a, b = b, c = c, flags = flags, t = M.T } end
    local why = R.refuse[R.kind[id]]
    if why then return false, why, "unsupported" end
    R.state[id] = kind
    return true
end
function G.LookState(id, out)
    if type(id) ~= "number" or id < 1 then return nil, "LookState(id [, out])", "bad_argument" end
    out = out or {}
    out.kind, out.owner, out.head_y, out.head_z, out.eye_y, out.eye_z = R.state[id] or 0, R.owner or 0, 32, -4, 11.25, 0
    return out
end
function G.SetCharOption(id, option, value)
    R.opts[#R.opts + 1] = { id, option, value }
    if R.plain_sonic and R.kind[id] == 0 then
        return nil, "SA1_COPT_SUPER_LOOK: only Super Sonic and a Sonic created with SA1_CREATE_SUPER_CAPABLE", "unsupported"
    end
    return true
end
function G.EmoteState(id) return R.emote, nil, -1, 0 end
local getstate = G.GetState
function G.GetState(id, out)
    out = getstate(id, out)
    if out then out.yaw = R.yaw end
    return out
end

-- the world around the character: this test's stubs (ents.FindInSphere gives the scene)
-- (only for the look's own scan: cl_collision.lua's movers ask too, and want more of an entity)
local scene, scans = {}, { n = 0, r = 0, pos = nil, inside = false }
ents.FindInSphere = function(pos, r)
    local out = {}
    if not scans.inside then return out end
    scans.n, scans.r, scans.pos = scans.n + 1, r, pos
    if scans.by_radius then     -- (0.9.9's block: which sphere finds what matters there)
        local r2 = r * r
        for _, e in ipairs(scene) do
            local dx, dy, dz = e.x - pos.x, e.y - pos.y, e.z - pos.z
            if dx * dx + dy * dy + dz * dz <= r2 then out[#out + 1] = e end
        end
        return out
    end
    for i, e in ipairs(scene) do out[i] = e end
    return out
end
MOVETYPE_VPHYSICS = MOVETYPE_VPHYSICS or 6
local function ent(idx, class, x, y, z, how)
    how = how or {}
    local e = { idx = idx, class = class, x = x, y = y, z = z, nw2 = {} }
    function e:EntIndex() return self.idx end
    function e:GetClass() return self.class end
    function e:IsNPC() return how.npc == true end
    function e:IsNextBot() return how.nextbot == true end
    function e:IsPlayer() return how.player == true end
    function e:IsVehicle() return how.vehicle == true end
    function e:IsWeapon() return how.weapon == true end
    function e:IsWorld() return false end
    function e:IsDormant() return how.dormant == true end
    function e:GetMoveType() return how.mt or 0 end
    function e:Alive() return how.dead ~= true end
    function e:GetOwner() return how.owner or NULL end
    function e:GetPos() return Vector(self.x, self.y, self.z) end
    function e:EyePos() return Vector(self.x, self.y, self.z) end
    function e:WorldSpaceCenter() return Vector(self.x, self.y, self.z) end
    function e:GetNW2Bool(k, d) if self.nw2[k] == nil then return d end return self.nw2[k] end
    function e:GetNW2Int(k, d) if self.nw2[k] == nil then return d end return self.nw2[k] end
    function e:GetNW2Entity() return NULL end
    return e
end

-- the addon's client files through its own autorun
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local feat_errors = GSA1 and GSA1.FeatureFileErrors or {}
ok_load = ok_load and #feat_errors == 0
check(ok_load and GSA1 and GSA1.Look and GSA1.Look.Choose ~= nil, "feat/sh_look.lua and cl_look.lua load through the autorun (%s)",
    tostring(err_load or feat_errors[1] or "no errors"))
if not (ok_load and GSA1 and GSA1.Look) then return done() end
local L, I = GSA1.Look, GSA1.Interact
local real_scan = L.Scan
function L.Scan(C, radius, now)
    scans.inside = true
    real_scan(C, radius, now)
    scans.inside = false
end
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
check(GSA1.HasFeature("look", 1), "GSA1.HasFeature(\"look\", 1) with the module's feature")
local function setcv(name, v) GetConVar(name):SetString(tostring(v)) end

-- the frames
local function frames(n)
    for _ = 1, n do M.frame(1 / 60) end
end
local function seconds(s) frames(math.floor(s * 60 + 0.5)) end
local EYES = 28     -- the mock's CharacterInfo
local function fresh(name)
    GSA1.Remove(true)
    scene = {}
    R.looks = {}
    R.yaw = 0
    GSA1.Spawn(name or "sonic")
    local C = GSA1.Char
    frames(1)       -- its first tick: one OFF (nothing to look at)
    return C, C.drawPos.x, C.drawPos.y, C.drawPos.z + EYES
end
local function calls_of(id, kind)
    local out = {}
    for _, c in ipairs(R.looks) do
        if (id == nil or c.id == id) and (kind == nil or c.kind == kind) then out[#out + 1] = c end
    end
    return out
end
local function last(id)
    local l = calls_of(id)
    return l[#l]
end
local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-3) end
local function looks_at(id, x, y, z)
    local c = last(id)
    return c ~= nil and c.kind == G.LOOK_POINT and near(c.a, x) and near(c.b, y) and near(c.c, z)
end
local function looks_off(id)
    local c = last(id)
    return c ~= nil and c.kind == G.LOOK_OFF
end
local function npc(idx, x, y, z, rel)
    local e = ent(idx, "npc_citizen", x, y, z, { npc = true })
    I.rel[idx] = rel or I.REL_FRIENDLY
    return e
end

-- 1. a new character -------------------------------------------------------------------------------------------------------
do
    local C, x, y, z = fresh()
    check(looks_off(C.id) and #calls_of(C.id) == 1 and scans.n >= 1 and scans.pos == C.drawPos,
        "a new character: one LOOK_OFF, nothing else; the pool is around its drawn position")
    seconds(1)
    check(#calls_of(C.id) == 1, "nothing near it: no more gsa1.Look calls in 1 s (%d in all)", #calls_of(C.id))
    local n0 = scans.n
    seconds(1)
    check(scans.n - n0 >= 9 and scans.n - n0 <= 11, "one ents.FindInSphere every 0.1 s (%d in 1 s), radius %g = the range + 40",
        scans.n - n0, scans.r)
    check(near(scans.r, 160), "the radius with no follower: 120 + 40 = 160 HU (%g)", scans.r)
    local _ = x + y + z
end

-- 2. the range: people 119 / 121 HU, items 159 / 161 HU --------------------------------------------------------------------------
do
    local C, x, y, z = fresh()
    scene = { npc(101, x + 119, y, z) }
    seconds(0.8)
    check(looks_at(C.id, x + 119, y, z), "a friendly NPC at 119 HU: its eyes are looked at")
    C, x, y, z = fresh()
    scene = { npc(102, x + 121, y, z) }
    seconds(0.8)
    check(looks_off(C.id) and #calls_of(C.id, G.LOOK_POINT) == 0, "a friendly NPC at 121 HU: nothing")
    C, x, y, z = fresh()
    scene = { ent(103, "weapon_pistol", x + 159, y, z, { weapon = true }) }
    seconds(0.8)
    check(looks_at(C.id, x + 159, y, z), "a free weapon at 159 HU: looked at (the range + 40)")
    C, x, y, z = fresh()
    scene = { ent(104, "weapon_pistol", x + 161, y, z, { weapon = true }) }
    seconds(0.8)
    check(#calls_of(C.id, G.LOOK_POINT) == 0, "a free weapon at 161 HU: nothing")
    C, x, y, z = fresh()
    scene = { ent(105, "item_healthkit", x + 100, y, z) }
    seconds(0.8)
    check(looks_at(C.id, x + 100, y, z), "an item_* pickup in range: looked at")
    C, x, y, z = fresh()
    scene = { ent(106, "weapon_pistol", x + 100, y, z, { weapon = true, owner = ent(1, "player", 0, 0, 0, { player = true }) }),
              ent(107, "gsa1_obj_ring", x + 90, y, z), ent(108, "gsa1_obj_itembox", x + 80, y, z, { weapon = true }),
              ent(109, "prop_physics", x + 70, y, z), ent(110, "npc_citizen", x + 60, y, z, { npc = true, dormant = true }) }
    I.rel[110] = I.REL_FRIENDLY
    seconds(0.8)
    check(#calls_of(C.id, G.LOOK_POINT) == 0, "never: a weapon someone holds, G-SA1's rings and item boxes, a prop, a dormant NPC")
    -- other players
    C, x, y, z = fresh()
    scene = { ent(111, "player", x + 100, y, z, { player = true }) }
    seconds(0.8)
    check(looks_at(C.id, x + 100, y, z), "another player in range: looked at")
    C, x, y, z = fresh()
    scene = { ent(112, "player", x + 100, y, z, { player = true, dead = true }), M.player }
    M.player.EntIndex = function() return 1 end
    seconds(0.8)
    check(#calls_of(C.id, G.LOOK_POINT) == 0, "a dead player, and your own hidden player entity: nothing")
    local p2 = ent(113, "player", x + 100, y, z - EYES, { player = true })
    p2.nw2[GSA1.NW_CHAR] = true
    C, x, y, z = fresh()
    p2.x, p2.y, p2.z = x + 100, y, z - EYES
    scene = { p2 }
    seconds(0.8)
    check(looks_at(C.id, x + 100, y, z), "another player who is a G-SA1 character: its root + the eyes' height")
end

-- 3. the cone: +-100 degrees of the facing ---------------------------------------------------------------------------------------
do
    local function at(deg, yaw)
        local C, x, y, z = fresh()
        R.yaw = yaw or 0
        frames(1)
        local a = math.rad(deg + (yaw or 0))
        scene = { npc(120, x + 100 * math.cos(a), y + 100 * math.sin(a), z) }
        seconds(0.8)
        return #calls_of(C.id, G.LOOK_POINT) > 0
    end
    check(at(99) and at(-99), "99 degrees to either side of the facing: looked at")
    check(not at(101) and not at(-101), "101 degrees to either side: nothing")
    check(at(0) and not at(180), "straight ahead yes, straight behind no")
    check(at(99, 90) and not at(101, 90) and at(-99, 200) and not at(-101, 200), "the same relative to another facing (state.yaw 90, 200)")
    R.yaw = 0
end

-- 4. the hysteresis: a new target must be the best for 0.5 s; a target is held at least 1 s; what is gone goes at once ------------
do
    local C, x, y, z = fresh()
    local a, b = npc(130, x + 100, y, z), npc(131, x + 50, y, z)
    local function first_point_at(px, since)
        for _, c in ipairs(calls_of(C.id, G.LOOK_POINT)) do
            if c.t >= since and near(c.a, px) then return c.t end
        end
        return nil
    end
    local t0 = M.T
    scene = { a }
    seconds(0.4)
    check(#calls_of(C.id, G.LOOK_POINT) == 0, "0.4 s after something came near: no look yet")
    seconds(0.25)
    check(looks_at(C.id, x + 100, y, z), "0.65 s after: looked at (the best for 0.5 s)")
    local t_a = first_point_at(x + 100, t0)
    check(t_a and t_a - t0 >= 0.5 and t_a - t0 <= 0.65, "the first look %.2f s after it came near", t_a and t_a - t0 or -1)
    -- a nearer one comes at once after the first look: the first is held 1 s
    scene = { a, b }
    seconds(0.25)
    check(looks_at(C.id, x + 100, y, z), "a nearer one comes: 0.25 s later still the first")
    seconds(0.9)
    local t_b = first_point_at(x + 50, t0)
    check(looks_at(C.id, x + 50, y, z) and t_b and t_b - t_a >= 1.0 and t_b - t_a <= 1.2,
        "the nearer one takes over when the first was held 1 s (after %.2f s)", t_b and t_b - t_a or -1)
    -- a nearer one after the hold: it must be the best for 0.5 s
    seconds(1.0)
    local c3 = npc(132, x + 30, y, z)
    scene = { a, b, c3 }
    local t3 = M.T
    seconds(0.8)
    local t_c = first_point_at(x + 30, t3)
    check(t_c and t_c - t3 >= 0.5 and t_c - t3 <= 0.7, "after the hold, a nearer one takes over when it was the best for 0.5 s "
        .. "(after %.2f s)", t_c and t_c - t3 or -1)
    -- a candidate that stops being the best starts again
    scene = { a, b }
    seconds(0.2)
    check(looks_off(C.id), "the target goes away: LOOK_OFF within 0.2 s, not after 1 s")
    seconds(0.25)
    check(looks_off(C.id), "... and 0.45 s later the other one is not looked at yet")
    seconds(0.3)
    check(looks_at(C.id, x + 50, y, z), "... 0.75 s later it is")
    a, b = b, a
    -- hold: a target that stays best never flickers, and calls stop while nothing moves
    local n = #calls_of(C.id)
    seconds(2)
    check(#calls_of(C.id) == n, "a target standing still: no more gsa1.Look calls in 2 s (a look stays latched)")
    -- the point follows between two rounds' samples
    a.x = a.x + 10
    local n1 = #calls_of(C.id)
    frames(14)
    local mid = calls_of(C.id)[n1 + 2]
    check(#calls_of(C.id) - n1 >= 3 and mid and mid.a > x + 50 and mid.a < x + 60 and looks_at(C.id, x + 60, y, z), "a target that moves: the point goes "
        .. "there over a round, sent frame by frame (%d calls), with no engine call per frame (scan rate only)", #calls_of(C.id) - n1)
end

-- 5. line of sight ---------------------------------------------------------------------------------------------------------------
do
    local C, x, y, z = fresh()
    local a = npc(140, x + 100, y, z)
    local hit = false
    local traced = {}
    M.traceLine = function(t)
        traced[#traced + 1] = { mask = t.mask, filter = t.filter, sx = t.start.x, sz = t.start.z, ex = t.endpos.x }
        local out = t.output or {}
        out.Hit = hit
        return out
    end
    scene = { a }
    seconds(0.8)
    check(looks_at(C.id, x + 100, y, z) and #traced >= 1, "a free line: looked at, after its trace (%d traces)", #traced)
    check(traced[1].mask == (MASK_VISIBLE or 24705) and near(traced[1].sx, x) and near(traced[1].sz, z) and near(traced[1].ex, x + 100),
        "the trace goes from the looker's eyes to the point, MASK_VISIBLE")
    local fl = traced[1].filter
    check(type(fl) == "table" and fl[1] == C.ent and fl[2] == a, "its filter: the looker's own entity and the target")
    local n0 = #traced
    seconds(2)
    check(#traced - n0 >= 7 and #traced - n0 <= 9, "one looker: a trace every 0.25 s (%d in 2 s)", #traced - n0)
    hit = true
    seconds(0.3)
    check(looks_off(C.id), "the line is blocked: the target is dropped at the next trace (LOOK_OFF)")
    hit = false
    seconds(0.6)
    check(looks_off(C.id) and #calls_of(C.id, G.LOOK_POINT) > 0, "blocked less than 1 s ago: still nothing, though the line is free again")
    seconds(1.1)
    check(looks_at(C.id, x + 100, y, z), "after the 1 s the target may come back (the best for 0.5 s, a new trace)")
    -- never through a wall: no look before the first trace passed
    C, x, y, z = fresh()
    hit = true
    scene = { npc(141, x + 100, y, z) }
    seconds(1.5)
    check(#calls_of(C.id, G.LOOK_POINT) == 0, "behind a wall from the start: no look at all")
    hit = false
    M.traceLine = nil
end

-- 6. the categories' switches ------------------------------------------------------------------------------------------------------
do
    local C, x, y, z = fresh()
    scene = { npc(150, x + 80, y, z, I.REL_HOSTILE) }
    seconds(0.8)
    check(#calls_of(C.id, G.LOOK_POINT) == 0, "a hostile NPC: nothing by default")
    setcv("gsa1_look_hostile", 1)
    seconds(0.8)
    check(looks_at(C.id, x + 80, y, z), "with gsa1_look_hostile 1: looked at")
    setcv("gsa1_look_hostile", 0)
    seconds(0.3)
    check(looks_off(C.id), "... off again: at once")
    C, x, y, z = fresh()
    scene = { npc(151, x + 80, y, z, I.REL_NEUTRAL) }
    seconds(0.8)
    check(looks_at(C.id, x + 80, y, z), "a neutral NPC: looked at")
    setcv("gsa1_look_people", 0)
    seconds(0.3)
    check(looks_off(C.id), "gsa1_look_people 0: friendly and neutral NPCs and players are not")
    setcv("gsa1_look_people", 1)
    C, x, y, z = fresh()
    scene = { ent(152, "weapon_smg1", x + 80, y, z, { weapon = true }) }
    setcv("gsa1_look_items", 0)
    seconds(0.8)
    check(#calls_of(C.id, G.LOOK_POINT) == 0, "gsa1_look_items 0: items are not")
    setcv("gsa1_look_items", 1)
    -- priorities and the range option
    C, x, y, z = fresh()
    scene = { ent(153, "weapon_smg1", x + 20, y, z, { weapon = true }), npc(154, x + 100, y, z) }
    seconds(0.8)
    check(looks_at(C.id, x + 100, y, z), "people before items, the nearer item not looked at")
    setcv("gsa1_look_range", 300)
    C, x, y, z = fresh()
    scene = { npc(155, x + 280, y, z) }
    seconds(0.8)
    check(looks_at(C.id, x + 280, y, z) and near(scans.r, 340), "gsa1_look_range 300: 280 HU is near enough, radius %g", scans.r)
    setcv("gsa1_look_range", 120)
end

-- 7. what you defeated ---------------------------------------------------------------------------------------------------------------
do
    local C, x, y, z = fresh()
    local h = npc(160, x + 90, y, z, I.REL_HOSTILE)
    local f = npc(161, x + 40, y, z)
    scene = { h, f }
    seconds(0.8)
    check(looks_at(C.id, x + 40, y, z), "before: the friendly NPC (the hostile one is off)")
    -- the server says it was killed; the entity goes
    I.killed[160] = M.T + 3
    scene = { f }
    seconds(1.0)
    check(looks_at(C.id, x + 90, y, z), "defeated: it is looked at, at its last point, before the nearer friendly NPC")
    seconds(3.3)
    check(looks_at(C.id, x + 90, y, z), "... 4.3 s later still")
    seconds(1)
    check(looks_at(C.id, x + 40, y, z) or looks_off(C.id), "... gone after 5 s")
    seconds(0.8)
    check(looks_at(C.id, x + 40, y, z), "... and the friendly NPC again")
    C, x, y, z = fresh()
    setcv("gsa1_look_defeated", 0)
    h = npc(162, x + 90, y, z, I.REL_HOSTILE)
    scene = { h }
    seconds(0.5)
    I.killed[162] = M.T + 3
    scene = {}
    seconds(1)
    check(#calls_of(C.id, G.LOOK_POINT) == 0, "gsa1_look_defeated 0: nothing")
    setcv("gsa1_look_defeated", 1)
    -- a defeated one out of range
    C, x, y, z = fresh()
    h = npc(163, x + 170, y, z, I.REL_HOSTILE)
    scene = { h }
    setcv("gsa1_look_range", 400)
    seconds(0.3)
    setcv("gsa1_look_range", 120)
    seconds(0.15)
    I.killed[163] = M.T + 3
    scene = {}
    seconds(1)
    check(#calls_of(C.id, G.LOOK_POINT) == 0, "defeated 170 HU away (range + 40 = 160): nothing")
end

-- 8. gsa1_look 0, one OFF, then no calls; the camera key still works --------------------------------------------------------------------
do
    input = { IsButtonDown = function(code) return code == R.key end }
    local C, x, y, z = fresh()
    scene = { npc(170, x + 80, y, z) }
    seconds(0.8)
    check(looks_at(C.id, x + 80, y, z), "(a target)")
    local n0 = #calls_of(C.id)
    setcv("gsa1_look", 0)
    local s0 = scans.n
    seconds(2)
    local new = {}
    for i = n0 + 1, #calls_of(C.id) do new[#new + 1] = calls_of(C.id)[i] end
    check(#new == 1 and new[1].kind == G.LOOK_OFF, "gsa1_look 0: one LOOK_OFF, then no gsa1.Look call in 2 s (%d calls)", #new)
    check(scans.n - s0 <= 1, "... and no scan (%d)", scans.n - s0)
    setcv("gsa1_look_camera_key", 77)
    frames(7)
    R.key = 77
    frames(1)
    check(last(C.id).kind == G.LOOK_CAMERA, "the camera key still works with gsa1_look 0: LOOK_CAMERA while it is held")
    local n1 = #calls_of(C.id)
    seconds(1)
    check(#calls_of(C.id) == n1, "... latched: one call while it is held")
    R.key = nil
    frames(1)
    check(looks_off(C.id), "... released: LOOK_OFF")
    setcv("gsa1_look", 1)
    seconds(0.8)
    check(looks_at(C.id, x + 80, y, z), "gsa1_look 1 again: the target")
    R.key = 77
    frames(1)
    check(last(C.id).kind == G.LOOK_CAMERA, "the camera key over a target")
    R.key = nil
    frames(1)
    check(looks_at(C.id, x + 80, y, z), "... released: back to the target at once")
    -- first person: GSA1.FirstPerson through the table
    local fp = GSA1.FirstPerson
    GSA1.FirstPerson = function() return true end
    R.key = 77
    frames(2)
    check(looks_at(C.id, x + 80, y, z), "first person: the camera key is ignored (the eye is inside the head), targets stay")
    GSA1.FirstPerson = fp
    frames(1)
    check(last(C.id).kind == G.LOOK_CAMERA, "third person again: it works")
    -- a menu or chat has the keyboard
    R.key = nil
    frames(1)
    M.player.IsTyping = function() return true end
    R.key = 77
    frames(2)
    check(looks_at(C.id, x + 80, y, z), "typing in chat: the key is not the camera key")
    M.player.IsTyping = nil
    R.key = nil
    setcv("gsa1_look_camera_key", 0)
    seconds(0.2)
end

-- 9. emotes ---------------------------------------------------------------------------------------------------------------------------
do
    local C, x, y, z = fresh()
    scene = { npc(180, x + 80, y, z) }
    seconds(0.8)
    R.emote = 2
    seconds(0.3)
    check(looks_at(C.id, x + 80, y, z), "gsa1_look_emotes 1 (the default): the look goes on while an emote plays")
    setcv("gsa1_look_emotes", 0)
    seconds(0.2)
    local n = #calls_of(C.id)
    check(looks_off(C.id), "gsa1_look_emotes 0: LOOK_OFF while the emote plays")
    seconds(0.5)
    check(#calls_of(C.id) == n, "... one call")
    R.emote = 0
    frames(2)
    check(looks_at(C.id, x + 80, y, z), "the emote ends: the target again")
    setcv("gsa1_look_emotes", 1)
end

-- 10. E-102: one false, then no calls ----------------------------------------------------------------------------------------------------
do
    local C, x, y, z = fresh("gamma")
    check(#calls_of(C.id) == 1, "E-102: the first call answers false")
    local s0 = scans.n
    scene = { npc(190, x + 80, y, z) }
    seconds(1.5)
    check(#calls_of(C.id) == 1, "... and no more calls, with a target near (%d)", #calls_of(C.id))
    check(scans.n == s0, "... and no scan for him (%d)", scans.n - s0)
    check(string.find(table.concat(L.StatusLines(), " "), "E-102 never turns his head", 1, true) ~= nil,
        "the status line: E-102 never turns his head (%s)", table.concat(L.StatusLines(), " "))
    local _ = y + z
end

-- 11. the status lines ---------------------------------------------------------------------------------------------------------------------
do
    local C, x, y, z = fresh()
    scene = { npc(195, x + 84, y, z) }
    seconds(0.8)
    local s = table.concat(L.StatusLines(), " ")
    check(string.find(s, "Sonic looks at npc_citizen (friendly, 84 HU) - head +32 / -4", 1, true) ~= nil, "status: %s", s)
    R.owner = 2
    s = table.concat(L.StatusLines(), " ")
    check(string.find(s, "the game's own look", 1, true) ~= nil, "status while the game looks: %s", s)
    R.owner = nil
    scene = {}
    seconds(0.2)
    s = table.concat(L.StatusLines(), " ")
    check(string.find(s, "looks at nothing", 1, true) ~= nil, "status with nothing: %s", s)
end

-- 12. Super Sonic's head ---------------------------------------------------------------------------------------------------------------------
do
    local C = fresh("supersonic")
    check(#R.opts == 0, "gsa1_look_super 0: no option call at all (the game)")
    setcv("gsa1_look_super", 1)
    check(#R.opts == 1 and R.opts[1][1] == C.id and R.opts[1][2] == 7 and R.opts[1][3] == 1, "1: gsa1.SetCharOption(id, "
        .. "gsa1.COPT_SUPER_LOOK, 1) at once on kind 8")
    C = fresh("supersonic")
    check(#R.opts == 2 and R.opts[2][1] == C.id, "... and on the next kind-8 character")
    fresh("sonic")
    check(#R.opts == 3, "... and on a Sonic world (libsa1 knows which are super-capable)")
    fresh("tails")
    check(#R.opts == 3, "... never on Tails")
    GSA1.LogFlush()
    local log0 = #(M.files["gsa1/log.txt"] or "")
    R.plain_sonic = true
    fresh("sonic")
    R.plain_sonic = nil
    GSA1.LogFlush()
    local added = string.sub(M.files["gsa1/log.txt"] or "", log0 + 1)
    check(#R.opts == 4 and not string.find(added, "Super Sonic's head", 1, true) and #M.reported == 0,
        "... a plain Sonic's world refuses: nothing logged, nothing fails")
    setcv("gsa1_look_super", 0)
    R.opts = {}
end

-- 13. followers: the leader last, siblings never, the same pool, their own options ---------------------------------------------------------------
local function followers_of(C, n, kind, dist)
    local Fo = { list = {}, byId = {} }
    GSA1.Followers = Fo
    for i = 1, n do
        local a = (i - 1) * 2.4
        local F = { id = 1000 + i, kind = kind or 2, title = "Follower " .. i, follower = true, leaderId = C.id,
                    drawPos = Vector(C.drawPos.x + (dist or 100) * math.cos(a), C.drawPos.y + (dist or 100) * math.sin(a), C.drawPos.z),
                    drawYaw = math.deg(a) + 180, ent = { removed = false } }
        R.kind[F.id] = F.kind
        Fo.list[i], Fo.byId[F.id] = F, F
        M.run_hook("GSA1FollowerCreated", F, "page")
    end
    return Fo
end
do
    local C, x, y, z = fresh()
    local Fo = followers_of(C, 1)
    local F = Fo.list[1]
    F.drawPos:SetUnpacked(x + 100, y, C.drawPos.z)
    F.drawYaw = 180            -- it faces the character
    seconds(0.8)
    check(looks_at(F.id, x, y, z), "a follower with nothing else near looks at its leader (at its eyes)")
    check(near(scans.r, math.min(160 + 100, 2400)), "the radius: the range + 40 + the farthest follower (%g)", scans.r)
    scene = { npc(200, x + 60, y, z) }
    seconds(0.8)
    check(looks_at(F.id, x + 60, y, z), "something else near: that first, the leader is the last choice")
    scene = {}
    seconds(0.8)
    check(looks_at(F.id, x, y, z), "... and the leader again")
    F.drawYaw = 0              -- now it faces away from the character
    seconds(0.8)
    check(looks_off(F.id), "a leader out of the follower's +-100 degrees: not looked at")
    F.drawYaw = 180
    F.drawPos:SetUnpacked(x + 2000, y, C.drawPos.z)
    seconds(0.8)
    check(looks_at(F.id, x, y, z) and near(scans.r, 2160), "a leader 2,000 HU away: still looked at; radius %g", scans.r)
    F.drawPos:SetUnpacked(x + 3000, y, C.drawPos.z)
    seconds(0.3)
    check(looks_off(F.id) and near(scans.r, 2400), "beyond 2,400 HU: not; the radius stays at most 2,400 (%g)", scans.r)
    F.drawPos:SetUnpacked(x + 100, y, C.drawPos.z)
    seconds(0.8)
    -- your character looks at a follower in range
    local cl = last(C.id)
    check(cl.kind == G.LOOK_POINT and near(cl.a, x + 100) and near(cl.c, z), "your character looks at its follower in range (its drawn "
        .. "position + the eyes)")
    -- gsa1_look_followers 0: one OFF for the follower, your character goes on
    setcv("gsa1_look_followers", 0)
    local n0 = #calls_of(F.id)
    seconds(1)
    check(#calls_of(F.id) == n0 + 1 and looks_off(F.id), "gsa1_look_followers 0: one LOOK_OFF, no more calls for it")
    check(last(C.id).kind == G.LOOK_POINT, "... your character still looks")
    setcv("gsa1_look_followers", 1)
    seconds(0.8)
    check(looks_at(F.id, x, y, z), "1 again: it looks")
    -- the camera key
    setcv("gsa1_look_camera_key", 77)
    frames(7)
    R.key = 77
    frames(1)
    check(last(F.id).kind == G.LOOK_CAMERA and last(C.id).kind == G.LOOK_CAMERA, "the camera key turns the follower's head too")
    R.key = nil
    frames(1)
    setcv("gsa1_look_camera_all", 0)
    frames(7)
    R.key = 77
    frames(1)
    check(last(F.id).kind == G.LOOK_POINT and last(C.id).kind == G.LOOK_CAMERA, "gsa1_look_camera_all 0: only your character's")
    R.key = nil
    frames(1)
    setcv("gsa1_look_camera_all", 1)
    setcv("gsa1_look_camera_key", 0)
    -- an emote is your character's: a follower's look goes on
    setcv("gsa1_look_emotes", 0)
    R.emote = 1
    seconds(0.3)
    check(looks_off(C.id) and last(F.id).kind == G.LOOK_POINT, "gsa1_look_emotes 0: your character's emote ends only its own look")
    R.emote = 0
    setcv("gsa1_look_emotes", 1)
    -- held (096 review R.15): out of the look's lists, its look ended once; it stands far above its leader
    local bystander = #calls_of(C.id)
    local r0 = scans.r
    F.held = true
    F.drawPos:SetUnpacked(x + 100, y, C.drawPos.z + 4000000)
    seconds(0.3)
    local n_held = #calls_of(F.id)
    check(looks_off(F.id), "a held follower: one LOOK_OFF")
    seconds(0.5)
    check(#calls_of(F.id) == n_held, "... no more calls while it is held")
    check(near(scans.r, 160), "... it does not widen the pool (radius %g, before %g)", scans.r, r0)
    check(L.byKey[-F.id] == nil, "... and it is nobody's candidate")
    check(looks_off(C.id) or #calls_of(C.id) >= bystander, "(your character's own look goes on by its own rules)")
    F.held = nil
    F.drawPos:SetUnpacked(x + 100, y, C.drawPos.z)
    seconds(0.8)
    check(looks_at(F.id, x, y, z), "released: it looks at its leader again")
    -- a walk to a box's board: F.leaderId is nil for that time
    local lid = F.leaderId
    F.drawPos:SetUnpacked(x + 300, y, C.drawPos.z)
    seconds(0.8)
    check(looks_at(F.id, x, y, z), "(300 HU from its leader: looked at, as its leader)")
    F.leaderId = nil
    seconds(0.2)
    check(looks_off(F.id), "no leader for the moment (a walk to a box's board), you out of range: no look at you")
    F.leaderId = lid
    seconds(0.8)
    check(looks_at(F.id, x, y, z), "... and its leader again afterwards")
    F.drawPos:SetUnpacked(x + 100, y, C.drawPos.z)
    -- removed
    M.run_hook("GSA1FollowerRemoved", F, "removed")
    Fo.list[1], Fo.byId[F.id] = nil, nil
    local n1 = #calls_of(F.id)
    seconds(0.5)
    check(#calls_of(F.id) == n1 and L.byId[F.id] == nil, "a removed follower gets no more calls")
end
do  -- followers do not look at each other
    local C, x, y, z = fresh()
    local Fo = followers_of(C, 2)
    local A, B = Fo.list[1], Fo.list[2]
    A.drawPos:SetUnpacked(x + 100, y + 20, C.drawPos.z)
    B.drawPos:SetUnpacked(x + 100, y - 20, C.drawPos.z)
    A.drawYaw, B.drawYaw = 180, 180
    seconds(0.8)
    check(looks_at(A.id, x, y, z) and looks_at(B.id, x, y, z), "two followers side by side look at you, not at each other")
    -- a chain: a follower of a follower looks at its own leader last
    B.leaderId = A.id
    B.drawPos:SetUnpacked(x + 200, y, C.drawPos.z)
    seconds(1.8)
    check(looks_at(B.id, A.drawPos.x, A.drawPos.y, A.drawPos.z + EYES), "a follower of a follower looks at its leader")
    -- your character, as a candidate for a follower with another leader
    B.drawPos:SetUnpacked(x + 100, y - 20, C.drawPos.z)
    seconds(1.8)
    check(looks_at(B.id, x, y, z), "... and at you first when you are near: you are a character, its leader is the last choice")
    -- no character of yours: one OFF to every follower, then no calls (review R.13)
    local n0 = #R.looks
    GSA1.Remove(true)
    local new = {}
    for i = n0 + 1, #R.looks do new[#new + 1] = R.looks[i] end
    local offs = 0
    for _, c in ipairs(new) do if c.kind == G.LOOK_OFF and (c.id == A.id or c.id == B.id) then offs = offs + 1 end end
    check(#new == 2 and offs == 2, "your character is removed: one LOOK_OFF to every follower (%d calls)", #new)
    local n1 = #R.looks
    seconds(1)
    check(#R.looks == n1, "... and no more calls while you have none")
    GSA1.Spawn("sonic")
    C = GSA1.Char
    frames(1)
    check(last(C.id) ~= nil, "a character again: calls again")
    -- switching: no call to the old world, the followers stay
    local old = C.id
    local n2 = #calls_of(old)
    GSA1.Spawn("tails")
    frames(1)
    check(GSA1.Char.id ~= old and #calls_of(old) == n2 and last(GSA1.Char.id) ~= nil, "a switch: no call to the old world, the new one has its own")
    -- a death: one OFF; a new character has a new looker
    scene = { npc(205, GSA1.Char.drawPos.x + 60, GSA1.Char.drawPos.y, GSA1.Char.drawPos.z + EYES) }
    seconds(0.8)
    local id = GSA1.Char.id
    check(last(id).kind == G.LOOK_POINT, "(a target)")
    M.run_hook("GSA1CharacterDied", GSA1.Char, 1, {})
    frames(1)
    local n3 = #calls_of(id)
    seconds(1)
    check(looks_off(id) and #calls_of(id) == n3, "dying: one LOOK_OFF, no more calls")
    GSA1.Followers = nil
end
do  -- an E-102 follower
    local C, x, y, z = fresh()
    local Fo = followers_of(C, 1, 6)
    local F = Fo.list[1]
    seconds(1)
    check(#calls_of(F.id) == 1, "an E-102 follower: one false, then no calls")
    M.run_hook("GSA1FollowerRemoved", F, "removed")
    GSA1.Followers = nil
    local _ = x + y + z
end

-- 14. the trace budget: 100 lookers, at most 60 traces per simulated second ------------------------------------------------------------------
do
    local C, x, y, z = fresh()
    local Fo = followers_of(C, 99, 2, 60)
    scene = { npc(210, x + 5, y, z) }
    for _, F in ipairs(Fo.list) do
        F.drawYaw = math.deg(math.atan2(y - F.drawPos.y, x - F.drawPos.x))
    end
    M.traces = {}
    seconds(1)
    local per = {}
    for s = 1, 5 do
        M.traces = {}
        seconds(1)
        per[s] = #M.traces
    end
    M.traces = nil
    local maxn, minn = 0, 1e9
    for s = 1, 5 do
        maxn = math.max(maxn, per[s])
        minn = math.min(minn, per[s])
    end
    check(maxn <= 60 and minn >= 50, "100 lookers: at most 60 traces per simulated second (%d, %d, %d, %d, %d)", per[1], per[2], per[3],
        per[4], per[5])
    local looking = 0
    for _, F in ipairs(Fo.list) do if last(F.id).kind == G.LOOK_POINT then looking = looking + 1 end end
    check(looking == 99, "... and every follower got its line of sight checked and looks (%d of 99)", looking)
    check(L.npool <= L.POOL_MAX and L.nall == 101, "the pool: at most 64 candidates to choose from (%d; %d sampled, for the leaders)",
        L.npool, L.nall)
    for _, F in ipairs(Fo.list) do M.run_hook("GSA1FollowerRemoved", F, "removed") end
    GSA1.Followers = nil
end

-- 15. 100 lookers x 64 candidates under 0.1 ms per round, in this LuaJIT (the best of ten short runs: other lanes' builds may be running) ----
do
    local o = L.SetOptions({}, 120, true, true, true, true)
    local seed = 12345
    local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
    local pool = {}
    for i = 1, 64 do
        pool[i] = { key = i, cat = (i % 4) + 1, x = (rnd() - 0.5) * 1200, y = (rnd() - 0.5) * 1200, z = rnd() * 64, follower = false }
    end
    local lookers = {}
    for i = 1, 100 do
        local l = L.NewLooker(1000 + i, i > 1)
        l.x, l.y, l.z = (rnd() - 0.5) * 600, (rnd() - 0.5) * 600, 40
        lookers[i] = l
    end
    local best, garbage = 1e9, 1e9
    local now = 0
    for _ = 1, 10 do
        local t0 = host_clock()
        collectgarbage("collect")
        collectgarbage("stop")
        local k0 = collectgarbage("count")
        t0 = host_clock()
        for r = 1, 300 do
            now = now + 0.1
            for i = 1, 100 do
                local l = lookers[i]
                L.SetFacing(l, r + i)
                L.Choose(l, pool, 64, o, now)
            end
        end
        local ms = (host_clock() - t0) * 1000 / 300
        garbage = math.min(garbage, (collectgarbage("count") - k0) * 1024 / 300)
        collectgarbage("restart")
        best = math.min(best, ms)
    end
    check(best < 0.1, "100 lookers x 64 candidates: %.4f ms per round (under 0.1; look096.md 5.10: 0.031-0.035)", best)
    check(garbage < 16, "L.Choose makes no garbage (%.1f bytes per round)", garbage)
end

-- 16. the pure rules, one by one -----------------------------------------------------------------------------------------------------------------
do
    local o = L.SetOptions({}, 120, true, false, true, true)
    local l = L.NewLooker(1, true)
    local function c(key, cat, x, follower) return { key = key, cat = cat, x = x, y = 0, z = 0, follower = follower or false } end
    local defeated, friend, hostile, item, sibling = c(1, L.CAT_DEFEATED, 150), c(2, L.CAT_PEOPLE, 110), c(3, L.CAT_HOSTILE, 30),
        c(4, L.CAT_ITEM, 20), c(5, L.CAT_PEOPLE, 10, true)
    local pool = { sibling, item, hostile, friend, defeated }
    local t = L.Choose(l, pool, 5, o, 0)
    t = L.Choose(l, pool, 5, o, 0.5) or t
    check(t == defeated, "priority: defeated first, also when others are nearer")
    l = L.NewLooker(1, true)
    pool = { sibling, item, hostile, friend }
    L.Choose(l, pool, 4, o, 0)
    t = L.Choose(l, pool, 4, o, 0.5)
    check(t == friend, "then people (hostile off, a sibling follower never)")
    l = L.NewLooker(1, true)
    pool = { sibling, item, hostile }
    L.Choose(l, pool, 3, o, 0)
    t = L.Choose(l, pool, 3, o, 0.5)
    check(t == item, "then items")
    l = L.NewLooker(1, true)
    local leader = c(9, L.CAT_PEOPLE, 300)
    l.leaderKey, l.leaderEntry = 9, leader
    pool = { sibling, leader }
    L.Choose(l, pool, 2, o, 0)
    t = L.Choose(l, pool, 2, o, 0.5)
    check(t == leader, "then a follower's leader, also beyond the range")
    local notf = L.NewLooker(1, false)
    notf.leaderKey, notf.leaderEntry = 9, leader
    L.Choose(notf, { c(9, L.CAT_PEOPLE, 300) }, 1, o, 0)
    t = L.Choose(notf, { c(9, L.CAT_PEOPLE, 300) }, 1, o, 0.5)
    check(t == nil, "a leader is the last choice of followers only")
    l = L.NewLooker(1, false)
    local me = c(-1, L.CAT_PEOPLE, 5)
    L.Choose(l, { me }, 1, o, 0)
    check(L.Choose(l, { me }, 1, o, 0.5) == nil, "a looker never picks itself")
    local e = { x = 10, y = 0, z = 0, px = 0, py = 0, pz = 0, t = 5 }
    check(near(L.PointAt(e, 5), 0) and near(L.PointAt(e, 5.05), 5) and near(L.PointAt(e, 5.1), 10) and near(L.PointAt(e, 7), 10),
        "L.PointAt: one round from the sample before to the newest, then the newest")
    check(L.Radius(120, 0) == 160 and L.Radius(120, 100) == 260 and L.Radius(400, 5000) == 2400, "L.Radius: range + 40 + the farthest, at most 2,400")
end

-- 17. every row of 5.9 on the page ---------------------------------------------------------------------------------------------------------------------
do
    local made = {}
    local METHODS
    local function standin(kind)
        local P = { kind = kind, calls = {} }
        made[#made + 1] = P
        return setmetatable(P, { __index = function(t, k)
            if METHODS[k] then return METHODS[k] end
            if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
            return function(self, ...)
                t.calls[#t.calls + 1] = { k, ... }
                return standin(k)
            end
        end })
    end
    METHODS = { SetText = function(self, s) self.text = s end, SetConVar = function(self, c) self.convar = c end,
                SetTall = function() end, AddChoice = function(self, t, d)
                    self.choices = self.choices or {}
                    self.choices[#self.choices + 1] = { t, d }
                end }
    vgui.Create = function(cls) return standin(cls) end
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    local entry
    for _, e in ipairs(M.menu) do if e.class == "gsa1_feat_look" then entry = e end end
    check(entry and entry.name == "Head look" and entry.category == "G-SA1", "the page Options -> G-SA1 -> Head look")
    local page_order
    for _, p in ipairs(GSA1.MenuPages) do if p.id == "look" then page_order = p.order end end
    check(page_order == 287, "its order: 287, after Faces 285")
    if entry then
        local panel = standin("DForm")
        entry.cpanel(panel)
        local checks, sliders, combos, texts = {}, {}, {}, {}
        for _, P in ipairs(made) do
            for _, c in ipairs(P.calls) do
                if c[1] == "CheckBox" then checks[c[3]] = c[2]
                elseif c[1] == "NumSlider" then sliders[c[3]] = c
                elseif c[1] == "ComboBox" then combos[#combos + 1] = c[2]
                elseif c[1] == "Help" or c[1] == "ControlHelp" then texts[#texts + 1] = tostring(c[2])
                end
            end
        end
        local want = {
            gsa1_look_people = "Friendly and neutral NPCs and other players",
            gsa1_look_hostile = "Hostile NPCs too (the game never looks at enemies)",
            gsa1_look_items = "Items lying near",
            gsa1_look_defeated = "What you just defeated, for 5 seconds",
            gsa1_look_emotes = "Also while an emote plays",
            gsa1_look_camera_all = "The camera key turns your followers' heads too",
            gsa1_look_super = "Super Sonic turns his head too",
            gsa1_look_props = "Physics props",
            gsa1_look_usable = "Things you can use (doors, buttons, vehicles)",
        }
        local wrong = {}
        for cvname, label in pairs(want) do
            if checks[cvname] ~= label then wrong[#wrong + 1] = cvname .. " = " .. tostring(checks[cvname]) end
        end
        check(#wrong == 0, "the check boxes of 5.9 with their labels%s", #wrong > 0 and (": " .. table.concat(wrong, "; ")) or "")
        local r = sliders.gsa1_look_range
        check(r and r[2] == "How near (Hammer units)" and r[4] == 40 and r[5] == 400, "the slider: How near (Hammer units), 40-400")
        local has_combo = {}
        for _, n in ipairs(combos) do has_combo[n] = true end
        check(has_combo["Heads turn to look at"] and has_combo["Followers look at"], "the two combo boxes")
        local binder
        for _, P in ipairs(made) do if P.convar == "gsa1_look_camera_key" then binder = P end end
        check(binder ~= nil and binder.kind == "DBinder", "the binder for gsa1_look_camera_key")
        local all = table.concat(texts, " ")
        check(string.find(all, "Hold to look at the camera (the game's Z button)", 1, true) ~= nil, "its label")
        check(string.find(all, "E-102 never turns his head", 1, true) ~= nil and string.find(all, "Big moves only his eyes", 1, true) ~= nil
            and string.find(all, "Sonic standing moves only his eyes", 1, true) ~= nil and string.find(all, "eyes stay centred while they talk", 1, true) ~= nil,
            "the help lines of look096.md 7.2.3")
        -- a combo box sets its ConVar and follows it
        local combo
        for _, P in ipairs(made) do if P.choices and #P.choices == 2 and P.choices[1][1] == "only what the game looks at" then combo = P end end
        check(combo ~= nil and combo.choices[2][1] == "also Garry's Mod things", "the first combo's choices")
        if combo then
            combo:OnSelect(1, "x", 0)
            check(GetConVar("gsa1_look"):GetInt() == 0, "choosing sets gsa1_look")
            combo:Think()
            check(combo.text == "only what the game looks at", "the combo follows the ConVar")
            setcv("gsa1_look", 1)
            combo:Think()
            check(combo.text == "also Garry's Mod things", "... also a change from the console")
        end
        -- every option is a ConVar with its default
        local defaults = { gsa1_look = "1", gsa1_look_people = "1", gsa1_look_hostile = "0", gsa1_look_items = "1", gsa1_look_defeated = "1",
                           gsa1_look_range = "120", gsa1_look_emotes = "1", gsa1_look_followers = "1", gsa1_look_camera_key = "0",
                           gsa1_look_camera_all = "1", gsa1_look_super = "0", gsa1_look_props = "0", gsa1_look_usable = "0" }
        local bad_defaults, nrows = {}, 0
        for name, d in pairs(defaults) do
            nrows = nrows + 1
            if not (GSA1.CONVARS[name] and GSA1.CONVARS[name].default == d) then bad_defaults[#bad_defaults + 1] = name end
        end
        local extra = {}
        for name in pairs(GSA1.CONVARS) do
            if string.find(name, "^gsa1_look") and not defaults[name] then extra[#extra + 1] = name end
        end
        check(#bad_defaults == 0 and #extra == 0 and nrows == 13, "the 13 ConVars (5.9 and 0.9.9's two) with their defaults, no other%s", table.concat(bad_defaults, " ") .. table.concat(extra, " "))
        -- 0.9.9 (gsa1_099_plan.md 5.9): both rows on the page, with their help
        check(string.find(all, "Anything the physics moves: props, ragdolls, balloons. Not in the game. Not the prop you carry, not vehicles.", 1, true) ~= nil
            and string.find(all, "What the interact key can use right now. Not in the game. Never G-SA1's own objects.", 1, true) ~= nil
            and string.find(all, "Items, props, things to use and what you defeated: 40 more", 1, true) ~= nil,
            "the help of the two new rows and of the range")
        local rc = GSA1.CONVARS.gsa1_look_range
        check(rc.min == 40 and rc.max == 400, "gsa1_look_range's limits 40-400")
    end
    vgui.Create = nil
end

-- 18. the session log: one settings line from this file, its own line every 10 s with the hooks' garbage (2.4 D10, review R.13) ----------------------
do
    local GM = GSA1.GcMeter
    GM.Wrap()
    local C, x, y, z = fresh()
    scene = { npc(220, x + 80, y, z) }
    seconds(21)
    GSA1.LogFlush()
    local log = M.files["gsa1/log.txt"] or ""
    check(string.find(log, " settings +head look: heads turn 1, people 1, hostile 0, items 1, defeated 1, range 120, emotes 1, followers 1, camera "
        .. "key 0 %(followers too 1%), Super Sonic 0, physics props 0, interactables 0") ~= nil, "one settings line with every gsa1_look* value")
    check(string.find(log, " look +head look: lookers %d+") ~= nil and string.find(log, "GSA1PreTick / gsa1_look %d+ B", 1) ~= nil,
        "its own log line with the top gsa1_look* hooks' garbage")
    for line in string.gmatch(log, "[^\n]+") do
        if string.find(line, " look +head look:") then info("the line: %s", line) end
    end
end

-- 19. decision A22: at most 300 B of garbage a frame, by 0.9.5's per-hook meter (hook ids gsa1_look*) -----------------------------------------------------
do
    local GM = GSA1.GcMeter
    local function measure(what, setup, limit)
        local C, x, y, z = fresh()
        local cleanup = setup(C, x, y, z)
        R.on = false            -- (the mock's own record of the calls is not the addon's garbage)
        GM.Wrap()
        for _ = 1, 600 do M.frame(1 / 60) end
        local sum0, n = 0, 0
        for _, s in ipairs(GM.list) do if string.find(s.key, "/ gsa1_look", 1, true) then sum0 = sum0 + s.kb n = n + 1 end end
        collectgarbage("collect")
        collectgarbage("stop")
        for _ = 1, 600 do M.frame(1 / 60) end
        collectgarbage("restart")
        local sum1 = 0
        for _, s in ipairs(GM.list) do if string.find(s.key, "/ gsa1_look", 1, true) then sum1 = sum1 + s.kb end end
        local per = (sum1 - sum0) * 1024 / 600
        R.on = true
        if cleanup then cleanup() end
        if limit then
            check(per <= limit, "%s: %.1f bytes per frame (the budget: %d)", what, per, limit)
        else
            info("%s: %.1f bytes per frame", what, per)
        end
        return per
    end
    measure("nothing near", function() end, 300)
    measure("one friendly NPC and three items near", function(C, x, y, z)
        scene = { npc(230, x + 80, y, z), ent(231, "item_healthkit", x + 90, y, z), ent(232, "weapon_smg1", x + 100, y, z, { weapon = true }),
                  ent(233, "item_battery", x + 40, y, z) }
    end, 300)
    measure("(eight people near; the mock's Vector is a table, larger than GMod's userdata)", function(C, x, y, z)
        scene = {}
        for i = 1, 8 do scene[i] = npc(240 + i, x + 40 + i * 5, y, z) end
    end, 300)
    measure("(three followers, an NPC near)", function(C, x, y, z)
        scene = { npc(250, x + 60, y, z) }
        local Fo = followers_of(C, 3)
        return function()
            for _, F in ipairs(Fo.list) do M.run_hook("GSA1FollowerRemoved", F, "removed") end
            GSA1.Followers = nil
        end
    end)
    measure("(64 candidates: the most a scan keeps)", function(C, x, y, z)
        scene = {}
        for i = 1, 64 do scene[i] = npc(300 + i, x + 40 + i, y, z) end
    end)
    GSA1.Remove(true)
    scene = {}
    M.hooks.GSA1PreTick = M.hooks.GSA1PreTick or {}
end

-- 20. no module feature: nothing is called, nothing fails ------------------------------------------------------------------------------------------------
do
    local real = gsa1.Look
    gsa1.Look = nil
    R.looks = {}
    local n0 = scans.n
    GSA1.Spawn("sonic")
    frames(30)
    check(scans.n == n0 and #M.reported == 0, "without the feature: no scan, no Lua error%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
    local s = table.concat(L.StatusLines(), " ")
    check(string.find(s, "needs the G-SA1 module", 1, true) ~= nil, "the status line says what it needs: %s", s)
    GSA1.Remove(true)
    gsa1.Look = real
    check((R.badcalls or 0) == 0, "no call with a bad argument in the whole test (%d)", R.badcalls or 0)
    check(#M.reported == 0, "no Lua error in the whole test%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
end

-- 21. the mock against the module's look_api.txt (5.5): feat_look_binding_test.cpp writes it whenever the snapshot header has SA1_API_LOOK; then it must exist
-- and the mock must match it (missing or stale: a failure)
do
    local groot = string.gsub(tests, "[/" .. string.char(92) .. "]tests$", "")
    local hdr = host_read(groot .. "/build/deps/include/libsa1.h") or ""
    if not string.find(hdr, "#define SA1_API_LOOK", 1, true) then
        info("look_api.txt: the snapshot's libsa1.h has no SA1_API_LOOK yet - the check is skipped (5.5's rule)")
    else
        local api = host_read(groot .. "/build/x86_64-windows/look_api.txt")
        local wrong, n = {}, { feature = 0, ["function"] = 0, const = 0, field = 0 }
        if not api then
            wrong[1] = "no build/x86_64-windows/look_api.txt"
        else
            local st = G.LookState(1, {})
            for line in string.gmatch(api, "[^\r\n]+") do
                if string.sub(line, 1, 1) ~= "#" then
                    local rec = {}
                    for part in string.gmatch(line, "[^\t]+") do rec[#rec + 1] = part end
                    local what = rec[1]
                    if n[what] then n[what] = n[what] + 1 end
                    if what == "feature" then
                        if rec[2] ~= "look" or tonumber(rec[3]) ~= G.FEATURES.look then wrong[#wrong + 1] = line end
                    elseif what == "function" then
                        if type(G[rec[2]]) ~= "function" then wrong[#wrong + 1] = "the mock has no " .. tostring(rec[2]) end
                    elseif what == "const" then
                        if G[rec[2]] ~= tonumber(rec[3]) then wrong[#wrong + 1] = rec[2] .. ": the mock has " .. tostring(G[rec[2]]) end
                    elseif what == "field" then
                        if type(st[rec[3]]) ~= rec[4] then wrong[#wrong + 1] = "field " .. tostring(rec[3]) end
                    end
                end
            end
            if n.feature ~= 1 or n["function"] ~= 2 or n.const ~= 6 or n.field ~= 6 then
                wrong[#wrong + 1] = string.format("the file has %d feature, %d function, %d const, %d field records (stale?)", n.feature,
                    n["function"], n.const, n.field)
            end
        end
        check(#wrong == 0, "this test's mock module matches build/x86_64-windows/look_api.txt (%d functions, %d constants, %d fields)%s",
            n["function"], n.const, n.field, #wrong > 0 and (": " .. table.concat(wrong, "; ")) or "")
    end
end

-- 22. 0.9.9: physics props and things you can use (gsa1_099_plan.md 5.9, 5.10; small099.md 3.1, 6.1, 4.3) ---------------------------------------------------------
do
    GSA1.Followers = nil
    local keepTimer = timer.Create
    local timers = {}
    timer.Create = function(name, delay, reps, fn) timers[name] = { at = M.T + delay, fn = fn } end
    local function run_timers()
        for name, t in pairs(timers) do
            if M.T >= t.at then
                timers[name] = nil
                t.fn()
            end
        end
    end
    local function secs(s)
        for _ = 1, math.floor(s * 60 + 0.5) do
            M.frame(1 / 60)
            run_timers()
        end
    end
    local function prop(idx, x, y, z) return ent(idx, "prop_physics", x, y, z, { mt = MOVETYPE_VPHYSICS }) end
    local function door(idx, x, y, z, tag)
        local e = ent(idx, "prop_door_rotating", x, y, z, { mt = 7 })
        e.nw2.gsa1_use = tag
        return e
    end
    local function looking(id)
        local c = last(id)
        return c ~= nil and c.kind == G.LOOK_POINT
    end
    local function new_scene()
        setcv("gsa1_look_props", 0)
        setcv("gsa1_look_usable", 0)
        local C, x, y, z = fresh()
        return C, x, y, z
    end
    scans.by_radius = true

    do  -- 1, 2: off is 0.9.8's; on looks at its centre; off again ends it
        local C, x, y, z = new_scene()
        scene = { prop(2100, x + 80, y, z) }
        secs(0.8)
        check(not looking(C.id), "gsa1_look_props 0 (the default): a prop 80 HU in front is not looked at (0.9.8's behaviour)")
        setcv("gsa1_look_props", 1)
        secs(0.8)
        check(looks_at(C.id, x + 80, y, z), "gsa1_look_props 1: it is looked at, at its WorldSpaceCenter")
        local line = table.concat(L.StatusLines(), " ")
        check(string.find(line, "(prop,", 1, true) ~= nil, "the status line says it is a prop: %s", line)
        setcv("gsa1_look_props", 0)
        secs(0.8)
        check(not looking(C.id), "gsa1_look_props back to 0: the look ends")
    end
    do  -- 3: the reach is the items' row (range + 40)
        local C, x, y, z = new_scene()
        setcv("gsa1_look_props", 1)
        scene = { prop(2101, x + 165, y, z) }
        secs(0.8)
        check(not looking(C.id), "a prop 165 HU away is out of reach (120 + 40)")
        C, x, y, z = fresh()
        scene = { prop(2102, x + 155, y, z) }
        secs(0.8)
        check(looking(C.id), "a prop 155 HU away is in reach")
    end
    do  -- 4: the server's tag decides, a separate option
        local C, x, y, z = new_scene()
        scene = { door(2110, x + 60, y, z, true), door(2111, x + 60, y + 30, z, false) }
        setcv("gsa1_look_props", 1)
        secs(0.8)
        check(not looking(C.id), "gsa1_look_props alone: a door is not looked at")
        setcv("gsa1_look_props", 0)
        setcv("gsa1_look_usable", 1)
        secs(0.8)
        check(looks_at(C.id, x + 60, y, z), "gsa1_look_usable 1: the door the server tagged is looked at, the untagged one is not")
        local line = table.concat(L.StatusLines(), " ")
        check(string.find(line, "(usable,", 1, true) ~= nil, "the status line says it can be used: %s", line)
    end
    do  -- 5: never G-SA1's own, never what the character carries, not a vehicle as a prop, never a hazard
        local C, x, y, z = new_scene()
        setcv("gsa1_look_props", 1)
        setcv("gsa1_look_usable", 1)
        local ours = ent(2120, "gsa1_obj_ring", x + 60, y, z, { mt = MOVETYPE_VPHYSICS })
        ours.GSA1Object, ours.nw2.gsa1_use = true, true
        scene = { ours }
        secs(0.8)
        check(not looking(C.id), "G-SA1's own objects are never looked at, tag and VPHYSICS or not")
        scene = { prop(2121, x + 60, y, z) }
        local keepHeld = I.held
        I.held = { idx = 2121 }
        secs(0.8)
        check(not looking(C.id), "the prop the character carries is not looked at")
        I.held = keepHeld
        setcv("gsa1_look_usable", 0)
        scene = { ent(2122, "prop_vehicle_jeep", x + 60, y, z, { mt = MOVETYPE_VPHYSICS, vehicle = true }) }
        secs(0.8)
        check(not looking(C.id), "physics props alone: a vehicle is not a prop")
        local hazard = next(I.HAZARDS)
        scene = { ent(2123, hazard, x + 60, y, z, { mt = MOVETYPE_VPHYSICS }) }
        secs(0.8)
        check(not looking(C.id), "a hazard (%s) is never looked at", tostring(hazard))
    end
    do  -- 6, 7: people before them; hundreds of props crowd out nothing; an interactable before a nearer prop
        local C, x, y, z = new_scene()
        setcv("gsa1_look_props", 1)
        setcv("gsa1_look_usable", 1)
        local list = {}
        for i = 1, 400 do list[i] = prop(3000 + i, x + 30 + i % 100, y + (i % 7) * 3, z) end
        list[401] = npc(2130, x + 100, y, z)
        scene = list
        secs(1.5)
        check(looks_at(C.id, x + 100, y, z), "400 props and one friendly NPC: the NPC is looked at")
        check(L.npool <= 96 and L.nextra <= L.EXTRA_MAX, "the pool stays bounded: %d candidates, %d of them props (64 + 32 at most)", L.npool, L.nextra)
        scene = { door(2131, x + 60, y, z, true), prop(2132, x + 50, y, z) }
        secs(2.0)
        check(looks_at(C.id, x + 60, y, z), "an interactable before a physics prop, though the prop is nearer")
    end
    do  -- 8: a follower looks at a prop only its own sphere can find (the prop beyond your character's own reach), and with gsa1_look_followers 0 it does not
        local C, x, y, z = new_scene()
        setcv("gsa1_look_props", 1)
        local Fo = followers_of(C, 1)
        local F = Fo.list[1]
        F.drawPos:SetUnpacked(x + 100, y, C.drawPos.z)
        F.drawYaw = 0
        scene = { prop(2140, x + 240, y, z) }
        secs(1.2)
        check(looks_at(F.id, x + 240, y, z), "a follower looks at a prop near it that lies beyond your character's reach (its own sphere found it)")
        check(not looks_at(C.id, x + 240, y, z), "... your character does not")
        setcv("gsa1_look_followers", 0)
        secs(1.2)
        check(not looks_at(F.id, x + 240, y, z), "gsa1_look_followers 0: not the follower either")
        setcv("gsa1_look_followers", 1)
        M.run_hook("GSA1FollowerRemoved", F, "removed")
        GSA1.Followers = nil
    end
    do  -- 9: the counts (bench_props.lua's scene: seed 7, 64 props in 400 HU, every 8th a door)
        local count = { engine = 0, vec = 0 }
        local function meth(f)
            return function(...)
                count.engine = count.engine + 1
                return f(...)
            end
        end
        local function counted(idx, class, x, y, z, mt, use)
            local e = { idx = idx, class = class, x = x, y = y, z = z }
            e.EntIndex = meth(function(s) return s.idx end)
            e.GetClass = meth(function(s) return s.class end)
            e.IsNPC = meth(function() return false end)
            e.IsNextBot = meth(function() return false end)
            e.IsPlayer = meth(function() return false end)
            e.IsVehicle = meth(function() return false end)
            e.IsWeapon = meth(function() return false end)
            e.IsWorld = meth(function() return false end)
            e.IsDormant = meth(function() return false end)
            e.GetMoveType = meth(function() return mt end)
            e.GetOwner = meth(function() return NULL end)
            e.GetPos = meth(function(s) count.vec = count.vec + 1 return Vector(s.x, s.y, s.z) end)
            e.WorldSpaceCenter = meth(function(s) count.vec = count.vec + 1 return Vector(s.x, s.y, s.z) end)
            e.GetNW2Bool = meth(function(_, k, d) if k == "gsa1_use" then return use end return d end)
            e.GetNW2Int = meth(function(_, _, d) return d end)
            e.GetNW2Entity = meth(function() return NULL end)
            return e
        end
        local function measure(props, usable)
            local C = new_scene()
            local x, y, z = C.drawPos.x, C.drawPos.y, C.drawPos.z
            local rnd = math.random
            math.randomseed(7)
            scene = {}
            for i = 1, 64 do
                local a, r = rnd() * 6.283, 400 * math.sqrt(rnd())
                local use = (i % 8) == 0
                scene[i] = counted(5000 + i, use and "func_door" or "prop_physics", x + math.cos(a) * r, y + math.sin(a) * r, z + (rnd() - 0.5) * 80,
                    use and 7 or MOVETYPE_VPHYSICS, use)
            end
            setcv("gsa1_look_props", props)
            setcv("gsa1_look_usable", usable)
            for _ = 1, 60 do M.frame(1 / 60) end
            local rounds, inner = 0, L.Scan
            L.Scan = function(a, b, c)
                rounds = rounds + 1
                return inner(a, b, c)
            end
            count.engine, count.vec = 0, 0
            for _ = 1, 600 do M.frame(1 / 60) end
            L.Scan = inner
            return count.engine / math.max(rounds, 1), count.vec / math.max(rounds, 1), rounds
        end
        local off, voff, r0 = measure(0, 0)
        check(off == 88 and voff == 0, "both off: %.1f engine calls and %.1f Vectors a round over %d rounds (0.9.8's figure for this scene: 88 and 0)", off, voff, r0)
        local on, von, r1 = measure(1, 1)
        check(on <= off * 1.5, "both on: %.1f engine calls a round, at most 1.5 x (%d rounds)", on, r1)
        check(von <= L.EXTRA_MAX / L.EXTRA_REFRESH + 1, "both on: %.1f Vectors a round, at most EXTRA_MAX / EXTRA_REFRESH + the target", von)
        info("the second list: %.1f -> %.1f engine calls, %.1f Vectors a round", off, on, von)
        setcv("gsa1_look_props", 0)
        setcv("gsa1_look_usable", 0)
    end
    do  -- 10: the log (small099.md 6.1 item 10, C10): a drag writes one settings line, after it
        new_scene()
        scene = {}
        local n, was = 0, GSA1.Log
        GSA1.Log = function(kind, ...)
            if kind == "settings" then n = n + 1 end
            return was(kind, ...)
        end
        for i = 1, 30 do
            setcv("gsa1_look_range", 120 + i)
            M.frame(1 / 60)
            run_timers()
        end
        local during = n
        secs(1.5)
        GSA1.Log = was
        check(during == 0 and n == 1, "a 30-tick slider drag writes one settings line after it, none during it (during %d, after %d)", during, n)
        setcv("gsa1_look_range", 120)
        secs(1.5)
    end
    do  -- review R99.1: the question mark has no head; its looker stays, its followers go on
        setcv("gsa1_look_super", 1)
        local reported0 = #M.reported
        GSA1.Remove(true)
        scene, R.looks, R.opts = {}, {}, {}
        GSA1.Spawn("supersonic")
        local C = GSA1.Char
        C.question = true           -- (cl_character.lua sets it from the entry's form, before GSA1CharacterCreated)
        R.opts = {}
        L.ApplySuper(C, true)
        setcv("gsa1_look_super", 0)
        setcv("gsa1_look_super", 1)
        local x, y, z = C.drawPos.x, C.drawPos.y, C.drawPos.z + EYES
        local Fo = followers_of(C, 2, 2, 100)
        Fo.list[1].drawPos:SetUnpacked(x + 100, y, C.drawPos.z)
        Fo.list[1].drawYaw = 0
        Fo.list[2].drawPos:SetUnpacked(x + 100, y + 60, C.drawPos.z)
        Fo.list[2].drawYaw = 0
        scene = { npc(2150, x + 160, y + 30, z) }
        frames(100)
        check(#M.reported == reported0, "as the ?, with two followers and a person near them, 100 frames: no Lua error%s", #M.reported > reported0 and (": " .. M.reported[#M.reported]) or "")
        check(#calls_of(Fo.list[1].id, G.LOOK_POINT) > 0 and #calls_of(Fo.list[2].id, G.LOOK_POINT) > 0, "... the followers' gsa1.Look goes on")
        check(#calls_of(C.id) == 0, "... none for the ? itself (%d)", #calls_of(C.id))
        check(L.byId[C.id] ~= nil and L.byId[C.id].refused ~= nil, "... its looker exists, refused, as E-102's")
        check(#R.opts == 0, "... gsa1_look_super 1 sends nothing to its world (%d calls)", #R.opts)
        check(table.concat(L.StatusLines(), " ") == "The ? has no head.", "the page's status line: %s", table.concat(L.StatusLines(), " "))
        for _, F in ipairs(Fo.list) do M.run_hook("GSA1FollowerRemoved", F, "removed") end
        GSA1.Followers = nil
        setcv("gsa1_look_super", 0)
        -- the character list's own entry, when it is there: cl_character.lua sets C.question before the first look round
        if GSA1.CharacterByName and GSA1.CharacterByName("question") then
            GSA1.Remove(true)
            R.looks, R.opts = {}, {}
            GSA1.Spawn("question")
            C = GSA1.Char
            frames(12)
            check(C ~= nil and C.question == true and L.byId[C.id] ~= nil and L.byId[C.id].refused ~= nil and #calls_of(C.id) == 0,
                "the list's entry \"question\": C.question, its looker refused, no gsa1.Look")
        else
            info("the list has no \"question\" entry yet: only the stand-in ran (099-gsa1-playable's)")
        end
    end
    GSA1.Remove(true)
    scene = {}
    scans.by_radius = nil
    timer.Create = keepTimer
    check((R.badcalls or 0) == 0, "0.9.9's block: no call with a bad argument (%d)", R.badcalls or 0)
    check(#M.reported == 0, "0.9.9's block: no Lua error%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
end

return done()
