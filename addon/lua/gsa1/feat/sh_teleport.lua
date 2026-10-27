-- G-SA1 feature "teleport", shared part (both realms). 0.9.2a: sadc docs/research/gsa1_091a_teleport.md T0 + T4 + T5
-- with its review R.4 (R-b, R-c, R-d, R-f); owner defaults (rounds plan 14.1l): keep running speed, the camera turns as
-- Garry's Mod turns a player's, all teleports - map teleporters and other addons' SetPos - move the character.
--
-- The owner's 0.9.1a note "Teleports don't work. They snap the camera to a side view, and the player remains in the
-- original place" (gm_genesis): a trigger_teleport moved only the hidden server player (sv_gsa1.lua) - the character is
-- libsa1's, on the client - the next state packet put the player back into the trigger, the trigger fired again (about
-- 20 times a second) and each teleport snapped the view to the destination's angles. The rule since: G-SA1 is the only
-- thing that moves a character player's entity, so a move it did not make is a teleport, whatever made it.
--   * server (feat/sv_teleport.lua): every G-SA1 placement goes through GSA1.PlacePlayer, which records it; after each
--     user command (PlayerPostThink, where the trigger's Touch has run) and before a state packet is applied, a player
--     that is 32 units or more from its record (1 with EF_NOINTERP, the engine's teleport) was teleported: the server
--     holds it there, tells the owning client (P.NET: a 4-bit generation, the position, the view angles now, whether the
--     view turned, the velocity, the cause) and drops the client's state packets until the client confirms (P.NET_ACK)
--     or 1 s passes (a client without this feature: the old follow resumes, counted);
--   * client (feat/cl_teleport.lua): the character goes there, facing the destination's direction when the teleport
--     turned the view (the camera, which the engine turned, ends behind it); until libsa1 can move a character
--     (sa1_character_warp, the doc's T1) it is re-created there (GSA1.Recreate: rings and lives kept, the speed and the
--     game's item state - barrier, invincibility, speed shoes - not); a dying character only confirms (review R-b);
--   * "Map teleporters move my character" (gsa1_sv_teleports, server, default 1): 0 = the server never places the
--     hidden player where it overlaps a trigger_teleport, so a map teleporter never fires for a character (review R-f:
--     instead of undoing each teleport, which would snap the view as often), and moves are not followed;
--   * "Keep running through teleporters" (gsa1_teleport_keep_speed, client, default 1): used by the warp (T1 / T3) when
--     the module has one; the interim re-creation arrives standing either way.
GSA1 = GSA1 or {}
GSA1.Teleport = GSA1.Teleport or {}
local P = GSA1.Teleport

P.NET = "gsa1_teleport"              -- server -> client: the hidden player was teleported
P.NET_ACK = "gsa1_teleport_ack"      -- client -> server: the character is there (or the client will not follow)
P.MIN_JUMP = 32                      -- units: a smaller move of a noclip player whose commands are cleared is not one
P.ACK_TIMEOUT = 1.0                  -- s without a confirmation: the old follow resumes
P.LOOP_WINDOW, P.LOOP_MAX = 2.0, 4   -- more than 4 teleports within 2 s: a loop (a destination inside a teleporter)
P.GEN_BITS = 4
P.HULL_MIN, P.HULL_MAX = Vector(-16, -16, 0), Vector(16, 16, 72)   -- the player's standing hull (GetHull's default)

P.cv_server = GSA1.ConVar("gsa1_sv_teleports", "1", "Map teleporters move G-SA1 characters: 1 = a teleporter (or another "
    .. "addon's teleport) moves the character there, facing the teleporter's direction; 0 = a character's hidden player "
    .. "is never put into a map teleporter, so teleporters do not fire for characters", 0, 1, { server = true })
P.cv_keep = GSA1.ConVar("gsa1_teleport_keep_speed", "1", "Keep running through teleporters (needs libsa1's warp; until "
    .. "then the character arrives standing)", 0, 1)

-- the next 4-bit generation
function P.NextGen(gen)
    return ((tonumber(gen) or 0) + 1) % bit.lshift(1, P.GEN_BITS)
end

-- a move of `dist` units from the last placement: a teleport? (noint: the engine's EF_NOINTERP, set by Teleport)
function P.IsTeleport(dist, noint)
    dist = tonumber(dist) or 0
    return dist >= P.MIN_JUMP or (noint == true and dist >= 1)
end

-- did the view turn (degrees, the yaw before and after)?
function P.Turned(before, after)
    if before == nil or after == nil then return false end
    return math.abs(math.NormalizeAngle(after - before)) > 0.5
end

-- does the player hull at `pos` overlap the box mins..maxs (world space)?
function P.HullInBox(pos, mins, maxs)
    local a, b = pos + P.HULL_MIN, pos + P.HULL_MAX
    return a.x <= maxs.x and b.x >= mins.x and a.y <= maxs.y and b.y >= mins.y and a.z <= maxs.z and b.z >= mins.z
end

-- the loop guard: times = the teleports of one player (SysTime, oldest first), now = this one. Returns the count within
-- the window (this one included) and whether it is past the guard (then the client is not told again until the window
-- has room; the first one past it is sent with the loop flag)
function P.LoopCount(times, now)
    for i = #times, 1, -1 do
        if now - times[i] > P.LOOP_WINDOW then table.remove(times, i) end
    end
    times[#times + 1] = now
    return #times, #times > P.LOOP_MAX
end
