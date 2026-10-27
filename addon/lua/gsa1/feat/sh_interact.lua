-- G-SA1 interaction (round 5), both realms: the settings, the network strings, libsa1's numbers and the pure rules
-- (no GMod entity call, no module call), so the client (cl_interact.lua), the server (sv_interact.lua) and the tests
-- share them. Design: sadc docs/libsa1_interaction.md section 3 and its addendum (section 6: holdable props, balloons,
-- the per-category switches, PvP); plan docs/research/gsa1_rounds_plan.md 9.3 with the owner's additions: pushing
-- physics props by running or rolling into them, an interact button for doors and buttons, a minimal ring counter
-- (feat/cl_hud.lua).
--
-- What the owner decided (libsa1_interaction.md "Owner decisions" 1-7): hits on the character cost rings by the game's
-- own rules (Garry's Mod health untouched by default); the characters' attacks do scaled Garry's Mod damage per attack
-- kind; touching a hostile NPC hurts, a neutral one does not by default; attacks on other players are on (the victim is
-- knocked back and loses rings in their own game); props a player can carry with E can be carried by the characters;
-- every kind of target has its own switches (attack, homing / lock-on, touch harm); balloons are homing targets that
-- pop and launch the character up.
-- 0.9.2 (sadc docs/research/gsa1_090_player.md L1, L5-L8, H1-H3 with its review; rounds plan 14.1j): the characters'
-- sizes (GSA1.CHAR_SIZE), the hit shape of bullets, the player's death passed to the character and back, the held
-- props' clearance (the pure parts here; cl_interact.lua / sv_interact.lua do the rest).
GSA1 = GSA1 or {}
local I = GSA1.Interact or {}
GSA1.Interact = I

I.NEEDS = { feature = "interact", version = 1, module = "0.9.0" }

-- libsa1's numbers (include/libsa1.h, host objects API 0.3); the module's gsa1.INTERACT has the same table (the client
-- compares them once, feat_interact_binding_test compares this file with libsa1.h)
I.K = {
    ENEMY = 1, TARGET = 2, BREAKABLE = 3, HAZARD = 4, HOLDABLE = 5, BALLOON = 6,
    SOLID = 0x01, NOT_SOLID = 0x02, NO_HOMING = 0x04, NO_LOCKON = 0x08, NO_BONUS = 0x10, DISABLED = 0x20,
    REPORT_TOUCH = 0x40, HOLD_HITS = 0x80, HOLD_LOCKED = 0x100, HEAVY = 0x200, POP_ON_TOUCH = 0x400,
    LAUNCH_BOUNCE = 0x800, KEEP_HSPEED = 0x1000,
    SPHERE = 0, CYLINDER = 1, BOX = 4,
    EVENT_HIT = 1, EVENT_LOCKED = 2, EVENT_TARGETED = 3, EVENT_UNLOCKED = 4, EVENT_TOUCH = 5, EVENT_LIFTED = 6,
    EVENT_RELEASED = 7,
    HITF_BOUNCED = 0x1, HITF_PROJECTILE = 0x2, HITF_LOCKED = 0x4, HITF_LAUNCHED = 0x8,
    RELEASE_THROW = 1, RELEASE_THROW_AIMED = 2, RELEASE_PUT_DOWN = 3, RELEASE_DROP = 4, RELEASE_FORCED = 5,
    HOLD_NONE = 0, HOLD_LIFTING = 1, HOLD_CARRYING = 2, HOLD_THROWING = 3,
    COPT_NO_DEATH = 1, COPT_KEEP_RINGS = 2, COPT_NO_DAMAGE = 3,
    DAMAGE_FACE_SOURCE = 0x1, DAMAGE_KILL = 0x2,
    CONTACT_SIDE = 1, CONTACT_LANDING = 2, CONTACT_HEAD = 3,
}

-- network strings (registered by sv_interact.lua)
I.NET = {
    HIT = "gsa1_hit",                   -- client -> server: the character hit an entity
    KILL = "gsa1_kill",                 -- server -> client: an NPC the character damaged died (E-102's time bonus)
    HURT = "gsa1_hurt",                 -- server -> client: the player took damage: the character is hit
    REL = "gsa1_rel",                   -- server -> client: NPC relations (hostile / neutral / friendly)
    HOLD = "gsa1_hold",                 -- client -> server: lifted / released a prop
    HOLD_POSE = "gsa1_hold_pose",       -- client -> server: where the held prop is
    HOLD_DROP = "gsa1_hold_drop",       -- server -> client: the held prop is gone or taken (drop it)
    HOLD_DENY = "gsa1_hold_deny",       -- server -> client: the lift is not allowed (drop it)
    PUSH = "gsa1_push",                 -- client -> server: the character ran or rolled into physics props
    USE = "gsa1_use",                   -- client -> server: the interact key (press / release)
    USE_RESULT = "gsa1_use_result",     -- server -> client: what the interact key did
    USE_VEHICLE = "gsa1_use_vehicle",   -- server -> client: a vehicle is in front: step out of the character
    ENTER_VEHICLE = "gsa1_enter_vehicle", -- client -> server: the character is gone, enter the vehicle
    VEHICLE_LEFT = "gsa1_vehicle_left", -- server -> client: left the vehicle: become the character again
    DEAD = "gsa1_dead",                 -- client -> server: the character died (gsa1_sv_kill_on_death)
    PLAYER_DIED = "gsa1_player_died",   -- server -> client: the player died (a NextBot's Kill...): the character dies too
    RESPAWN = "gsa1_respawn",           -- client -> server: the character respawned: bring the dead player back with it
}

-- 0.9.2 (sadc docs/research/gsa1_090_player.md L1 with its review): the characters' sizes in Hammer units, the game's
-- physics table (sa1_physics_get: rad, height, eyes_height, center_height) x 4 - what gsa1.CharacterInfo(kind) says on
-- the client (feat_interact_size_binding_test compares them with the disc); here for the server, which has no module:
-- the hit shape of trace attacks (L5), the held prop over the head, and from 0.9.3 the player's hull. By kind.
GSA1.CHAR_SIZE = {
    [0] = { radius = 16, height = 40, eyes = 28, center = 21.6 },      -- Sonic
    [2] = { radius = 14, height = 36, eyes = 24, center = 18 },        -- Tails
    [3] = { radius = 16, height = 45.6, eyes = 36, center = 22.8 },    -- Knuckles
    [5] = { radius = 14, height = 40, eyes = 28, center = 20 },        -- Amy
    [6] = { radius = 16, height = 84, eyes = 80, center = 56 },        -- E-102
    [7] = { radius = 38, height = 68, eyes = 60, center = 32 },        -- Big
}
-- a kind without its own row (Super Sonic, kind 8, until the round that adds him measures it) has Sonic's
function I.CharSize(kind)
    return GSA1.CHAR_SIZE[kind or 0] or GSA1.CHAR_SIZE[0]
end

-- L5 (review R.3.6): a trace attack (a bullet) on a character's player counts only within this many units of the
-- character's own cylinder; the damage types it applies to (DMG_BULLET, DMG_BUCKSHOT)
I.HIT_MARGIN = 8
I.TRACE_DAMAGE = 2 + 536870912

-- how far a point is outside a character's cylinder (feet at fx, fy, fz; radius r, height h): 0 inside
function I.CylinderOutside(fx, fy, fz, r, h, px, py, pz)
    local dx, dy = px - fx, py - fy
    local side = math.max(0, math.sqrt(dx * dx + dy * dy) - r)
    local up = math.max(0, fz - pz, pz - (fz + h))
    return math.sqrt(side * side + up * up)
end

-- H1-H3 (gsa1_090_player.md P2): a box (OBB mins / maxs in its own space) turned by the angle `ang`: how far its lowest
-- corner is below the box's centre (<= 0), the half extents of its world-aligned bounds (x, y) and those bounds relative to
-- the entity's origin (mins, maxs as {x, y, z}). Angle:Forward / Right / Up are Garry's Mod's (the local y axis is -Right).
function I.TurnedBox(mins, maxs, ang)
    local f, r, u = ang:Forward(), ang:Right(), ang:Up()
    local cx, cy, cz = (mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2, (mins.z + maxs.z) / 2
    local lo = { x = math.huge, y = math.huge, z = math.huge }
    local hi = { x = -math.huge, y = -math.huge, z = -math.huge }
    for i = 0, 7 do
        local x = (i % 2 == 0) and mins.x or maxs.x
        local y = (math.floor(i / 2) % 2 == 0) and mins.y or maxs.y
        local z = (math.floor(i / 4) == 0) and mins.z or maxs.z
        local wx = f.x * x - r.x * y + u.x * z
        local wy = f.y * x - r.y * y + u.y * z
        local wz = f.z * x - r.z * y + u.z * z
        lo.x, lo.y, lo.z = math.min(lo.x, wx), math.min(lo.y, wy), math.min(lo.z, wz)
        hi.x, hi.y, hi.z = math.max(hi.x, wx), math.max(hi.y, wy), math.max(hi.z, wz)
    end
    local low = lo.z - (f.z * cx - r.z * cy + u.z * cz)
    return low, (hi.x - lo.x) / 2, (hi.y - lo.y) / 2, lo, hi
end

-- H1: how much a held prop's centre (at height cz, its lowest corner `low` below it) must go up so that its bottom is
-- `clear` units above the floor at height `floor`
function I.LiftFor(cz, low, floor, clear)
    return math.max(0, floor + (clear or 1) - (cz + low))
end

-- the server's free-spot search for a released prop (H2): the lifts tried in turn, the last one the prop's height
I.RELEASE_LIFTS = { 0, 2, 8, 16 }

-- the interact key's results (USE_RESULT)
I.USE_NOTHING, I.USE_USED, I.USE_DENIED, I.USE_VEHICLE, I.USE_OFF = 0, 1, 2, 3, 4

-- the attacks (SA1_ATTACK_*, libsa1_interaction.md 2.6), their Garry's Mod damage (decision 2: 3.2's table) and type
-- (DMG_CLUB 128, DMG_SHOCK 256, DMG_ENERGYBEAM 1024, DMG_BLAST 64) and the server's reach check (3.2: melee 240 HU, the
-- lure 800, the laser 1100)
I.ATTACKS = {
    [0] = { name = "other", title = "Other", dmg = 40, type = 128, reach = 240 },
    [1] = { name = "spin", title = "Spin (jump, roll)", dmg = 50, type = 128, reach = 240 },
    [2] = { name = "spindash", title = "Spin dash", dmg = 75, type = 128, reach = 240 },
    [3] = { name = "homing", title = "Homing attack", dmg = 60, type = 128, reach = 240 },
    [4] = { name = "lsa", title = "Light Speed Attack", dmg = 150, type = 384, reach = 240 },
    [5] = { name = "tail", title = "Tails' tail attack", dmg = 50, type = 128, reach = 240 },
    [6] = { name = "flight", title = "Tails flying into it", dmg = 50, type = 128, reach = 240 },
    [7] = { name = "punch", title = "Knuckles' punch", dmg = 90, type = 128, reach = 240 },
    [8] = { name = "maxheat", title = "Maximum Heat", dmg = 150, type = 384, reach = 240 },
    [9] = { name = "dig", title = "Knuckles digging", dmg = 50, type = 128, reach = 240 },
    [10] = { name = "hammer", title = "Amy's hammer", dmg = 90, type = 128, reach = 240 },
    [11] = { name = "laser", title = "E-102's laser", dmg = 80, type = 1024, reach = 1100 },
    [12] = { name = "blast", title = "E-102's laser blast", dmg = 30, type = 64, reach = 1100 },
    [13] = { name = "lure", title = "Big's lure", dmg = 50, type = 128, reach = 800 },
    [14] = { name = "big", title = "Big's attack", dmg = 80, type = 128, reach = 240 },
    [15] = { name = "sparkle", title = "Sonic's sparkles", dmg = 20, type = 256, reach = 240 },
    [16] = { name = "invincible", title = "Invincibility", dmg = 200, type = 384, reach = 240 },
    [17] = { name = "super", title = "Super Sonic", dmg = 200, type = 384, reach = 240 },
}
I.MAX_ATTACK = 17

-- the characters' weight for pushing props, kg (G-SA1's choice: a Garry's Mod player is 85 kg)
I.CHAR_MASS = { [0] = 60, [2] = 45, [3] = 75, [5] = 50, [6] = 250, [7] = 200, [8] = 60 }
I.PUSH_E = 0.25             -- how bouncy a push is (1-D collision: 0 = the prop takes the character's speed share only)
I.PUSH_DV_MAX = 3000        -- HU/s: the most one push adds to a prop's speed
I.PUSH_REACH = 160          -- HU: the server's distance check (+ the player's ping allowance)

-- the target categories (addendum 6.3.1): attack (send the hits: Garry's Mod damage), targeting (0 off, 1 E-102's
-- lock-on only, 2 homing and lock-on), touch harm; the ConVars gsa1_<id>_attack / _target / _touch / _push
I.CATEGORIES = {
    { id = "hostile", title = "Hostile NPCs", attack = 1, target = 2, touch = 1 },
    { id = "neutral", title = "Neutral NPCs", attack = 1, target = 2, touch = 0 },
    { id = "friendly", title = "Friendly NPCs", attack = 0, target = 0 },
    { id = "vehicle", title = "Vehicles", attack = 1, target = 2 },
    { id = "player", title = "Players (PvP)", attack = 1, target = 2 },
    { id = "prop", title = "Props and breakables", attack = 1, target = 1, push = 1 },
    { id = "hazard", title = "Hazards (fire, grenades, rockets)", touch = 1 },
}
I.TARGET_CHOICES = { { "Off", "0" }, { "E-102's lock-on only", "1" }, { "Homing and lock-on", "2" } }

-- NPCs that are friendly until the server says otherwise (libsa1_interaction.md 3.1); NextBots are hostile unless listed
I.FRIENDLY = {}
for _, c in ipairs({ "npc_citizen", "npc_alyx", "npc_barney", "npc_vortigaunt", "npc_kleiner", "npc_eli", "npc_mossman",
                     "npc_dog", "npc_monk", "npc_magnusson", "npc_breen", "npc_gman", "npc_fisherman" }) do
    I.FRIENDLY[c] = true
end
-- flying NPCs get a sphere (the rest a vertical cylinder)
I.FLYING = {}
for _, c in ipairs({ "npc_helicopter", "npc_combinegunship", "npc_combinedropship", "npc_manhack", "npc_cscanner",
                     "npc_clawscanner", "npc_turret_ceiling", "npc_rollermine" }) do
    I.FLYING[c] = true
end
I.HAZARDS = {}
for _, c in ipairs({ "env_fire", "entityflame", "npc_grenade_frag", "grenade_ar2", "rpg_missile", "prop_combine_ball",
                     "crossbow_bolt", "npc_satchel", "npc_tripmine", "grenade_helicopter" }) do
    I.HAZARDS[c] = true
end
I.BREAKABLES = { func_breakable = true, func_breakable_surf = true, func_physbox = true }

-- relations (server -> client; the client's default by class until one arrives)
I.REL_HOSTILE, I.REL_NEUTRAL, I.REL_FRIENDLY = 0, 1, 2

-- ConVars ------------------------------------------------------------------------------------------------------------
-- client (archived; Q menu > Options > G-SA1 > Interaction); GSA1.ConVar makes them on the client only
local cv = {}
I.cv = cv
cv.interact = GSA1.ConVar("gsa1_interact", 1, "Interaction with Garry's Mod's world: NPCs, players, vehicles, props, "
    .. "balloons and hazards become things the character can attack, target, touch and carry", 0, 1)
for _, c in ipairs(I.CATEGORIES) do
    if c.attack then
        cv[c.id .. "_attack"] = GSA1.ConVar("gsa1_" .. c.id .. "_attack", c.attack, c.title .. ": the character's "
            .. "attacks damage them (scaled Garry's Mod damage; off: the character still bounces off them)", 0, 1)
    end
    if c.target then
        cv[c.id .. "_target"] = GSA1.ConVar("gsa1_" .. c.id .. "_target", c.target, c.title .. ": 0 = not a target, "
            .. "1 = E-102 locks on, 2 = homing attack (and every other aimed move) and lock-on", 0, 2)
    end
    if c.touch then
        cv[c.id .. "_touch"] = GSA1.ConVar("gsa1_" .. c.id .. "_touch", c.touch, c.title .. ": touching them hurts the "
            .. "character (as touching an enemy in Sonic Adventure: rings lost)", 0, 1)
    end
end
cv.prop_push = GSA1.ConVar("gsa1_prop_push", 1, "Running, rolling or spin-dashing into a physics prop pushes it "
    .. "(heavier props move less; standing on a prop never shoves it)", 0, 1)
cv.push_strength = GSA1.ConVar("gsa1_push_strength", 1, "How hard the character pushes props (1 = a character's own "
    .. "weight; 0 = not at all)", 0, 4)
cv.push_roll = GSA1.ConVar("gsa1_push_roll", 2, "Rolling, jumping into or spin-dashing into a prop pushes this many "
    .. "times harder", 1, 4)
cv.hold = GSA1.ConVar("gsa1_hold", 1, "The characters pick up props a player could pick up with E (the game's own lift, "
    .. "carry, put down and throw with the action button)", 0, 1)
-- 0.9.2 (gsa1_090_player.md H1-H3): the game holds a prop by its centre at the hands, so a prop taller than the hands
-- reached into the floor (an oil drum 9.8 units below it under Sonic)
cv.hold_clear = GSA1.ConVar("gsa1_hold_clear", 1, "Keep carried props above the ground: a prop taller than the "
    .. "character's hands is lifted clear of the floor, and put down on it (off: its centre at the hands, as the game)", 0, 1)
cv.hold_overhead = GSA1.ConVar("gsa1_hold_overhead", 0, "Props taller than the character's hands are carried over its "
    .. "head (off: lifted clear of the ground at the hands)", 0, 1)
cv.balloon = GSA1.ConVar("gsa1_balloon", 1, "Balloons are targets: the homing attack hits them, they pop and launch the "
    .. "character up", 0, 1)
cv.balloon_launch = GSA1.ConVar("gsa1_balloon_launch", 0, "A popped balloon launches the character like a spring (0: "
    .. "the spring's pose, no homing until landing) or like an enemy bounce (1: stays in the ball, homing chains on)", 0, 1)
cv.balloon_speed = GSA1.ConVar("gsa1_balloon_speed", 0, "The balloon's launch speed in units per second (0 = the "
    .. "game's spring, 1200)", 0, 5000)
cv.balloon_touch = GSA1.ConVar("gsa1_balloon_touch", 0, "Touching a balloon pops it too (off: only an attack pops it)", 0,
    1)
cv.can_die = GSA1.ConVar("gsa1_can_die", 1, "The character can die (a hit with no rings; off: it is only knocked back)",
    0, 1)
cv.lose_rings = GSA1.ConVar("gsa1_lose_rings", 1, "Hits scatter the character's rings (off: knocked back, rings kept)",
    0, 1)
cv.knockback = GSA1.ConVar("gsa1_knockback_from_source", 0, "Hits knock the character back away from the attacker (off: "
    .. "backwards along its facing, as in the game)", 0, 1)
cv.solid_npcs = GSA1.ConVar("gsa1_solid_npcs", 1, "NPCs are solid to the character (it cannot run through them)", 0, 1)
cv.window = GSA1.ConVar("gsa1_obj_window", 64, "NPCs and props near the character the game sees at once (16-64)", 16, 64)
cv.debug = GSA1.ConVar("gsa1_obj_debug", 0, "Draw the shapes the game sees for NPCs, props and the rest", 0, 1)
cv.key = GSA1.ConVar("gsa1_interact_key", 0, "The interact key (a key code; 0 = the key bound to +use, E): use doors, "
    .. "buttons and vehicles in front of the character", 0, 512)
cv.lift_key = GSA1.ConVar("gsa1_lift_key", 0, "An extra key for the game's lift / put down / throw (a key code; 0 = "
    .. "none: the action button does it, and the interact key with gsa1_interact_lift)", 0, 512)
cv.key_lift = GSA1.ConVar("gsa1_interact_lift", 1, "The interact key also lifts, puts down and throws props (as the "
    .. "game's action button does)", 0, 1)
cv.key_vehicles = GSA1.ConVar("gsa1_interact_vehicles", 1, "The interact key on a vehicle: the character steps out "
    .. "and you drive", 0, 1)
cv.vehicle_return = GSA1.ConVar("gsa1_vehicle_return", 1, "Leaving that vehicle makes you the character again", 0, 1)

-- server (archived, replicated; the page's admin section)
local SV = { server = true }
I.svcv = {
    damage = GSA1.ConVar("gsa1_sv_damage", 1, "G-SA1 characters damage NPCs, props and players", 0, 1, SV),
    damage_mode = GSA1.ConVar("gsa1_sv_damage_mode", 0, "Damage a G-SA1 player takes: 0 = rings (the game's rules, "
        .. "health untouched), 1 = health (Garry's Mod's), 2 = both", 0, 2, SV),
    pvp = GSA1.ConVar("gsa1_sv_pvp", 1, "G-SA1 characters can hit other players", 0, 1, SV),
    pvp_knockback = GSA1.ConVar("gsa1_sv_pvp_knockback", 1, "A character hit by another is knocked back away from him",
        0, 1, SV),
    dmg_scale = GSA1.ConVar("gsa1_sv_dmg_scale", 1, "Multiplies the damage of every attack", 0, 10, SV),
    hold = GSA1.ConVar("gsa1_sv_hold", 1, "G-SA1 characters can pick up props", 0, 1, SV),
    hold_mass = GSA1.ConVar("gsa1_sv_hold_mass", 35, "The heaviest prop a character can pick up (kg)", 1, 250, SV),
    hold_size = GSA1.ConVar("gsa1_sv_hold_size", 128, "The largest prop a character can pick up (units)", 16, 256, SV),
    balloon_pop = GSA1.ConVar("gsa1_sv_balloon_pop", 1, "A character's attack pops balloons", 0, 1, SV),
    push = GSA1.ConVar("gsa1_sv_push", 1, "G-SA1 characters can push physics props", 0, 1, SV),
    push_max = GSA1.ConVar("gsa1_sv_push_max", 4, "The strongest push a player's setting may ask for", 0, 10, SV),
    interact = GSA1.ConVar("gsa1_sv_interact", 1, "G-SA1 characters can use doors, buttons and other usable things", 0, 1,
        SV),
    interact_vehicles = GSA1.ConVar("gsa1_sv_interact_vehicles", 1, "A character's interact key can enter vehicles", 0,
        1, SV),
    interact_reach = GSA1.ConVar("gsa1_sv_interact_reach", 96, "How far in front of the character the interact key "
        .. "reaches (units; a player's is 80)", 32, 256, SV),
    min_damage = GSA1.ConVar("gsa1_sv_min_damage", 1, "Damage below this does not hit the character", 0, 1000, SV),
    kill_damage = GSA1.ConVar("gsa1_sv_kill_damage", 1000, "Damage of at least this kills the character at once (a "
        .. "trigger_hurt pit)", 1, 100000, SV),
    kill_on_death = GSA1.ConVar("gsa1_sv_kill_on_death", 0, "The character's death kills the player", 0, 1, SV),
    -- 0.9.2 (gsa1_090_player.md L5 / L6 with the review R.3.6, owner answer: a kill of the player kills the character
    -- too and both come back together)
    hit_shape = GSA1.ConVar("gsa1_sv_hit_shape", 1, "Bullets hit a character's player only where the character's body "
        .. "is (a shot more than 8 units outside it misses; off: anywhere on the invisible player)", 0, 1, SV),
    respawn = GSA1.ConVar("gsa1_sv_respawn_with_character", 1, "A player who died while a character (a NextBot's kill, "
        .. "a script) comes back when the character respawns, as the character (off: the gamemode's own respawn)", 0, 1,
        SV),
}
I.svcv.dmg = {}
for a = 0, I.MAX_ATTACK do
    local def = I.ATTACKS[a]
    I.svcv.dmg[a] = GSA1.ConVar("gsa1_sv_dmg_" .. def.name, def.dmg, def.title .. ": Garry's Mod damage of one hit "
        .. "(times gsa1_sv_dmg_scale)", 0, 500, SV)
end

-- the pure rules ---------------------------------------------------------------------------------------------------------
local function num(cvar, default)
    if not cvar then return default end
    return cvar:GetFloat()
end

-- the client's settings as a table (tests pass their own)
function I.Settings()
    local s = { interact = num(cv.interact, 1) ~= 0 }
    for _, c in ipairs(I.CATEGORIES) do
        s[c.id] = {
            attack = c.attack ~= nil and num(cv[c.id .. "_attack"], c.attack) ~= 0 or false,
            target = c.target ~= nil and math.floor(num(cv[c.id .. "_target"], c.target)) or 0,
            touch = c.touch ~= nil and num(cv[c.id .. "_touch"], c.touch) ~= 0 or false,
        }
    end
    s.prop.push = num(cv.prop_push, 1) ~= 0
    s.hold = num(cv.hold, 1) ~= 0
    s.balloon = num(cv.balloon, 1) ~= 0
    s.balloon_launch = math.floor(num(cv.balloon_launch, 0))
    s.balloon_speed = num(cv.balloon_speed, 0)
    s.balloon_touch = num(cv.balloon_touch, 0) ~= 0
    s.solid_npcs = num(cv.solid_npcs, 1) ~= 0
    s.pvp = num(I.svcv.pvp, 1) ~= 0
    return s
end

-- the category of an entity from what the client knows about it (info: {class, npc, nextbot, player, vehicle,
-- character (a G-SA1 player), holdable (the server's tag), hp (the server's health tag), rel (the server's relation)}),
-- or nil: not a host object
function I.Category(info)
    local cls = info.class or ""
    if info.player then return "player" end
    if info.npc or info.nextbot then
        local rel = info.rel
        if rel == nil then
            rel = I.FRIENDLY[cls] and I.REL_FRIENDLY or I.REL_HOSTILE
        end
        if rel == I.REL_FRIENDLY then return "friendly" end
        if rel == I.REL_NEUTRAL then return "neutral" end
        return "hostile"
    end
    if cls == "gmod_balloon" then return "balloon" end
    if info.vehicle or string.find(cls, "^prop_vehicle_") or string.find(cls, "^lvs_") or
        string.find(cls, "^gmod_sent_vehicle_fphysics") or string.find(cls, "^wac_") then
        return "vehicle"
    end
    if I.HAZARDS[cls] then return "hazard" end
    if info.holdable then return "holdable" end
    if I.BREAKABLES[cls] or ((info.hp or 0) > 0 and string.find(cls, "^prop_physics")) then return "breakable" end
    return nil
end

-- a class that can be a host object without being an NPC, a NextBot, a player or a vehicle (the look-around's quick
-- test before it asks an entity anything else)
function I.CandidateClass(cls)
    return cls == "gmod_balloon" or I.HAZARDS[cls] ~= nil or I.BREAKABLES[cls] ~= nil or
        string.sub(cls, 1, 12) == "prop_physics" or string.sub(cls, 1, 13) == "prop_vehicle_" or
        string.sub(cls, 1, 4) == "lvs_" or string.sub(cls, 1, 26) == "gmod_sent_vehicle_fphysics" or
        string.sub(cls, 1, 4) == "wac_"
end

-- targeting -> flags (0: neither homing nor lock-on; 1: lock-on only; 2: both)
local function target_flags(t)
    if t <= 0 then return I.K.NO_HOMING + I.K.NO_LOCKON end
    if t == 1 then return I.K.NO_HOMING end
    return 0
end

-- what a category becomes in the game: kind, flags, touch, armor - or nil (no proxy: everything about it is off)
-- (addendum 6.3.1's table)
function I.Describe(cat, s, info)
    local K = I.K
    if not s.interact then return nil end
    if cat == "hostile" or cat == "neutral" then
        local c = s[cat]
        if not c.attack and c.target <= 0 and not c.touch then return nil end
        local f = target_flags(c.target) + (s.solid_npcs and K.SOLID or K.NOT_SOLID)
        return K.ENEMY, f, c.touch and 1 or 0, -1
    elseif cat == "friendly" then
        local c = s.friendly
        if not c.attack and c.target <= 0 then return nil end
        return K.TARGET, target_flags(c.target) + K.NO_BONUS + (s.solid_npcs and K.SOLID or K.NOT_SOLID), 0, -1
    elseif cat == "vehicle" then
        local c = s.vehicle
        if not c.attack and c.target <= 0 then return nil end
        return K.TARGET, target_flags(c.target) + K.NO_BONUS + K.NOT_SOLID, 0, -1
    elseif cat == "player" then
        local c = s.player
        if not s.pvp or (not c.attack and c.target <= 0) then return nil end
        return K.ENEMY, target_flags(c.target) + K.NO_BONUS + K.NOT_SOLID, 0, -1
    elseif cat == "breakable" then
        local c = s.prop
        if not c.attack and c.target <= 0 then return nil end
        if c.target > 0 then return K.TARGET, target_flags(c.target) + K.NO_BONUS + K.NOT_SOLID, 0, -1 end
        return K.BREAKABLE, K.NOT_SOLID, 0, -1
    elseif cat == "holdable" then
        if not s.hold then
            -- not liftable: a breakable one is still a breakable / target
            if (info and (info.hp or 0) > 0) then return I.Describe("breakable", s, info) end
            return nil
        end
        local f = (info and info.movers) and K.NOT_SOLID or 0       -- the moving collision object is its body
        if info and (info.hp or 0) > 0 and s.prop.attack then f = f + K.HOLD_HITS end
        if info and info.held_elsewhere then f = f + K.HOLD_LOCKED end
        return K.HOLDABLE, f, 0, -1
    elseif cat == "balloon" then
        if not s.balloon then return nil end
        local f = K.NO_BONUS + K.NOT_SOLID
        if s.balloon_touch then f = f + K.POP_ON_TOUCH end
        if s.balloon_launch == 1 then f = f + K.LAUNCH_BOUNCE end
        return K.BALLOON, f, 0, -1
    elseif cat == "hazard" then
        if not s.hazard.touch then return nil end
        return K.HAZARD, 0, 2, -1
    end
    return nil
end

-- whether a hit on a category goes to the server (its attack switch; balloons: always, the server decides the pop)
function I.SendsHits(cat, s)
    if cat == "balloon" then return true end
    if cat == "holdable" or cat == "breakable" then return s.prop.attack end
    local c = s[cat]
    return c ~= nil and c.attack == true
end

-- the shape of an entity from its OBB (mins / maxs in its own space): form, half sizes (sx, sy, sz) and the centre's
-- height above the registered position (the addon registers the OBB's world centre, so it is 0)
function I.ShapeFromOBB(cat, cls, mins, maxs, character)
    local K = I.K
    local dx, dy, dz = maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z
    dx, dy, dz = math.max(dx, 1), math.max(dy, 1), math.max(dz, 1)
    if cat == "player" and character then
        -- a G-SA1 player's entity hull is a player's; the character itself is small
        return K.CYLINDER, 16, 20, 0
    end
    if cat == "hostile" or cat == "neutral" or cat == "friendly" or cat == "player" then
        if I.FLYING[cls] then return K.SPHERE, 0.4 * math.max(dx, dy, dz), 0, 0 end
        return K.CYLINDER, 0.4 * (dx + dy) / 2, dz / 2, 0
    end
    if cat == "balloon" or cat == "hazard" then
        return K.SPHERE, math.max(dx, dy, dz) / 2, 0, 0
    end
    return K.BOX, dx / 2, dy / 2, dz / 2
end

-- a push (owner addition A), on the server: the speed a prop of mass mp (kg) gains along the push direction when the
-- character (mass mc) comes in at vin (HU/s, along the direction) and the prop already moves at vp along it - a 1-D
-- collision with a little bounce, times the player's strength k (their setting, times the rolling factor; capped by the
-- server); 0 when the character is not faster than the prop
function I.PushDeltaV(vin, vp, mc, mp, k)
    if not (vin and vp and mc and mp and k) or k <= 0 or mc <= 0 then return 0 end
    mp = math.max(mp, 0.1)
    local approach = vin - math.max(vp, 0)
    if approach <= 0 then return 0 end
    local dv = (1 + I.PUSH_E) * mc / (mc + mp) * approach * k
    return math.min(dv, I.PUSH_DV_MAX)
end

-- a contact report -> the push direction (unit vector components): side contacts push horizontally away from the
-- character (-normal, its height dropped), a head contact (the character hit it from below) pushes it up; a landing
-- never pushes (nil)
function I.PushDirection(typ, nx, ny, nz)
    if typ == I.K.CONTACT_HEAD then return 0, 0, 1 end
    if typ ~= I.K.CONTACT_SIDE then return nil end
    local x, y = -nx, -ny
    local l = math.sqrt(x * x + y * y)
    if l < 0.2 then return nil end
    return x / l, y / l, 0
end

-- the player's push strength the server accepts: their setting times the rolling factor, at most the server's cap
function I.PushFactor(strength, rolling, roll, cap)
    local k = math.max(0, strength or 1) * (rolling and math.max(1, roll or 1) or 1)
    return math.min(k, math.max(0, cap or 4))
end

-- the attack's damage (the server's ConVar, or the default) times the scale
function I.DamageFor(attack, scale, value)
    local def = I.ATTACKS[attack] or I.ATTACKS[0]
    return math.max(0, (value or def.dmg) * (scale or 1))
end

function I.Reach(attack)
    local def = I.ATTACKS[attack] or I.ATTACKS[0]
    return def.reach
end

-- the interact key ------------------------------------------------------------------------------------------------------
-- what using an entity means (info: {class, vehicle, spawnflags (a function: has(flag)), sent_use (a scripted entity
-- with a Use function), player, npc, weapon}): "impulse" (one use per press, like a player's E on a door or a button),
-- "continuous" (every tick while held: momentary buttons), "vehicle", or nil (not usable). Source's own rules for its
-- doors and buttons (Source SDK's ObjectCaps; the spawn flag numbers are Hammer's): func_door / func_door_rotating need
-- "Use Opens" (256); prop_door_rotating unless "Ignore player +USE" (32768); func_button / func_rot_button unless only
-- "Touch Activates" (256) without "Use Activates" (1024).
I.USE_CLASSES = {
    func_door = function(has) return has(256) and "impulse" or nil end,
    func_door_rotating = function(has) return has(256) and "impulse" or nil end,
    prop_door_rotating = function(has) return (not has(32768)) and "impulse" or nil end,
    func_button = function(has) return ((not has(256)) or has(1024)) and "impulse" or nil end,
    func_rot_button = function(has) return ((not has(256)) or has(1024)) and "impulse" or nil end,
    momentary_rot_button = function() return "continuous" end,
}
function I.UseKind(info)
    if not info or info.player or info.npc or info.weapon then return nil end
    local cls = info.class or ""
    if info.vehicle or string.find(cls, "^prop_vehicle_") or string.find(cls, "^lvs_") or
        string.find(cls, "^gmod_sent_vehicle_fphysics") or string.find(cls, "^wac_") then
        return "vehicle"
    end
    local rule = I.USE_CLASSES[cls]
    if rule then return rule(info.spawnflags or function() return false end) end
    if info.sent_use then return "impulse" end
    return nil
end

-- the directions the interact key looks along (degrees above the facing: the characters are short, a player's buttons
-- sit at a player's eye height), then a search around
I.USE_TILTS = { 0, 25, 45, 60, -20 }

-- the entity the interact key uses. origin: the character's centre; fx, fy: its facing (unit, horizontal); reach (HU);
-- env: trace(start, endpos) -> {ent, pos, world} or nil, usable(ent) -> kind or nil (following the parent chain:
-- returns the usable entity and its kind), around(origin, radius) -> list of {ent, point (its nearest point to
-- origin)}, visible(origin, point, ent) -> bool. Returns ent, kind (nil: nothing).
function I.FindUseTarget(origin, fx, fy, reach, env)
    for _, tilt in ipairs(I.USE_TILTS) do
        local r = math.rad(tilt)
        local c, s = math.cos(r), math.sin(r)
        local ex, ey, ez = origin.x + fx * c * reach, origin.y + fy * c * reach, origin.z + s * reach
        local hit = env.trace(origin, { x = ex, y = ey, z = ez })
        if hit and hit.ent then
            local e, kind = env.usable(hit.ent)
            if e then return e, kind end
        end
    end
    local best, best_kind, best_d
    for _, it in ipairs(env.around(origin, reach) or {}) do
        local e, kind = env.usable(it.ent)
        if e then
            local p = it.point
            local dx, dy, dz = p.x - origin.x, p.y - origin.y, p.z - origin.z
            local h = math.sqrt(dx * dx + dy * dy)
            local dot = h > 1e-3 and (dx * fx + dy * fy) / h or 1
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dot >= 0.5 and dist <= reach then
                -- off the facing line (horizontal), then the distance
                local side = h > 1e-3 and math.abs(dx * fy - dy * fx) or 0
                local score = side + 0.25 * dist
                if (not best_d or score < best_d) and env.visible(origin, p, it.ent) then
                    best, best_kind, best_d = e, kind, score
                end
            end
        end
    end
    return best, best_kind
end

-- a holdable prop in front of the character (the client's E-lift): pos (the character's feet), fx, fy (facing), the
-- prop's centre and radius; true when the game's lift can take it (the grab cylinder: at most max(60, radius + 32) HU
-- away horizontally, the facing within 40 degrees, its centre within 0..72 HU above the feet)
function I.HoldableInFront(pos, fx, fy, center, radius)
    local dx, dy, dz = center.x - pos.x, center.y - pos.y, center.z - pos.z
    local h = math.sqrt(dx * dx + dy * dy)
    local reach = math.max(60, (radius or 0) + 32)
    if h > reach or dz < -8 or dz > 72 then return false end
    if h < 1 then return true end
    return (dx * fx + dy * fy) / h >= math.cos(math.rad(40))
end
