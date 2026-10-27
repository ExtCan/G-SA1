-- G-SA1 feature "teleport", client part (0.9.2a; sadc docs/research/gsa1_091a_teleport.md T0 / T3 / T4 / T5 with its
-- review R.4; the rule and the messages: feat/sh_teleport.lua). The server says the hidden player was teleported
-- (P.NET); the character goes there and the client confirms (P.NET_ACK), after which the server follows the character
-- again from the destination.
--   * facing: the destination's direction when the teleport turned the view (Source turns a player's view to a
--     trigger_teleport's destination: the camera, already turned, ends behind the character), else unchanged (a
--     landmark door, another addon's SetPos);
--   * method: gsa1.Warp (libsa1's sa1_character_warp, the doc's T1 / T3, keeping the speed with "Keep running through
--     teleporters") when the module has it; until then the character is re-created there (GSA1.Recreate: rings, lives
--     and the HUD time kept; it arrives standing, without the game's item state - barrier, invincibility, speed shoes,
--     a held object);
--   * no character, "Server moves my player along" off (gsa1_follow_player 0: the server does not see that ConVar, so it
--     may still send one message; review R-c) or a dying character (review R-b: the death plays where it is and the
--     respawn goes to the spawn point as before): confirmed only;
--   * the session log: one "teleport" line per teleport (from, to, distance, facing, the view turned, speed, method and
--     its time, the cause - "trigger_teleport -> genesis_acf_teleport_dest" - and the server's check that found it), a
--     "teleport loop" line once per loop, and the summary's count (T4).
local P = GSA1.Teleport
P.state = P.state or { got = 0, taken = 0, confirmed = 0, loops = 0, last = nil }
local PS = P.state

local function log(kind, fmt, ...)
    if GSA1.Log then GSA1.Log(kind, fmt, ...) end
end

-- moved: the character went there (false: confirmed only - the server then keeps the hidden player at the destination
-- while the client's packets still come from where the teleport began, e.g. a death playing out in the teleporter)
local function ack(gen, moved)
    net.Start(P.NET_ACK)
    net.WriteUInt(gen, P.GEN_BITS)
    net.WriteBool(moved and true or false)
    net.SendToServer()
end

-- the "Keep running through teleporters" setting
local function keep_speed()
    return P.cv_keep == nil or P.cv_keep:GetBool()
end

-- m = { gen, pos, ang, turned, vel, loop, cause, dist, where }: moves the character there; returns what was done
-- ("loop", "none", "follow off", "dying", "warp", "re-created", "failed")
function P.Handle(m)
    PS.got = PS.got + 1
    local C = GSA1.Char
    local what
    if m.loop then
        -- the server's loop guard (a destination inside another teleporter): logged once, the character stays where the
        -- last teleport put it; the server tells again when the teleports stop
        PS.loops = PS.loops + 1
        log("teleport", "teleport loop at (%.0f %.0f %.0f): more than %d teleports within %.0f s (%s); the character stays "
            .. "where the last one put it", m.pos.x, m.pos.y, m.pos.z, P.LOOP_MAX, P.LOOP_WINDOW, tostring(m.cause))
        if GSA1.LogCount then GSA1.LogCount("teleports", "loop") end
        return "loop"
    end
    if not C then
        what = "none"
    elseif GSA1.cv and GSA1.cv.follow and not GSA1.cv.follow:GetBool() then
        what = "follow off"
    elseif C.death or C.respawnAt or C.fallbackAt then
        what = "dying"
    end
    if what then
        PS.confirmed = PS.confirmed + 1
        log("teleport", "teleport to (%.0f %.0f %.0f) by %s: confirmed only (%s)", m.pos.x, m.pos.y, m.pos.z,
            tostring(m.cause), what == "none" and "no character" or (what == "follow off" and "\"Server moves my player "
            .. "along\" is off" or "the character is dying: it respawns at its spawn point"))
        if GSA1.LogCount then GSA1.LogCount("teleports", "confirmed only") end
        return what
    end
    local from = Vector(C.drawPos)
    local old_yaw = C.drawYaw or C.spawnYaw or 0
    local yaw = m.turned and m.ang.y or old_yaw
    local t0 = SysTime()
    local speed = "not kept (re-created)"
    if gsa1.Warp then
        -- T1 / T3 (the module's warp): position and facing, the speed kept along the new facing (flag 1) or stopped
        local ok, err = gsa1.Warp(C.id, m.pos, yaw, m.vel, keep_speed() and 1 or 0)
        if ok then
            what = "warp"
            speed = keep_speed() and "kept" or "stopped (Keep running through teleporters is off)"
            gsa1.GetState(C.id, C.state)
            C.drawPos:Set(m.pos)
            if IsValid(C.ent) then C.ent:SetPos(C.drawPos) end
        else
            log("teleport", "gsa1.Warp failed (%s): re-creating the character there", tostring(err))
        end
    end
    if not what then
        local NC = GSA1.Recreate and GSA1.Recreate("teleported", m.pos, yaw)
        what = NC and "re-created" or "failed"
    end
    local NC = GSA1.Char
    if NC then NC.nextNet = 0 end            -- the next state packet goes out at once, from the destination
    if GSA1.MoversClear then GSA1.MoversClear() end
    local ms = (SysTime() - t0) * 1000
    PS.taken = PS.taken + (what == "failed" and 0 or 1)
    PS.last = { from = from, to = Vector(m.pos), yaw = yaw, what = what, cause = m.cause }
    log("teleport", "teleport: %s from (%.0f %.0f %.0f) to (%.0f %.0f %.0f), %.0f units; facing %.0f%s; speed %s; %s in "
        .. "%.1f ms; cause: %s (found %s)", C.title or "?", from.x, from.y, from.z, m.pos.x, m.pos.y, m.pos.z,
        from:Distance(m.pos), yaw, m.turned and " (the teleport turned the view)" or " (unchanged)", speed, what, ms,
        tostring(m.cause), m.where == "packet" and "before a state packet" or "after a user command")
    if GSA1.LogCount then GSA1.LogCount("teleports", what) end
    if GSA1.cv and GSA1.cv.debug and GSA1.cv.debug:GetBool() then
        GSA1.Msg("teleported to (%.0f %.0f %.0f) by %s", m.pos.x, m.pos.y, m.pos.z, tostring(m.cause))
    end
    return what
end

net.Receive(P.NET, function()
    local m = {}
    m.gen = net.ReadUInt(P.GEN_BITS)
    m.pos = net.ReadVector()
    m.ang = net.ReadAngle()
    m.turned = net.ReadBool()
    m.vel = net.ReadVector()
    m.loop = net.ReadBool()
    m.cause = net.ReadString()
    m.dist = net.ReadFloat()
    m.where = net.ReadString()
    local ok, what = pcall(P.Handle, m)
    if not ok then
        log("error", "teleport: %s", tostring(what))
        ErrorNoHalt("[G-SA1] teleport: " .. tostring(what) .. "\n")
    end
    ack(m.gen, ok and (what == "warp" or what == "re-created"))
end)

-- "teleports: 3 (2 re-created, 1 confirmed only), 0 loops" (gsa1_status)
function P.Line()
    return string.format("teleports: %d (%d taken, %d confirmed only), %d loops", PS.got, PS.taken, PS.confirmed, PS.loops)
end

-- T5: the Character page (owner rule: every option in the Options tab)
if GSA1.AddCharacterOption then
    GSA1.AddCharacterOption(170, "teleport", function(panel)
        panel:Help("Teleporters")
        panel:CheckBox("Map teleporters move my character", "gsa1_sv_teleports")
        panel:ControlHelp("A map's teleporter (or another addon's teleport) moves the character there, facing the "
            .. "teleporter's direction like a Garry's Mod player; the camera turns with it. Off: a character never "
            .. "triggers a map teleporter (it walks through). A server setting: in multiplayer the server's host or an "
            .. "admin sets it.")
        panel:CheckBox("Keep running through teleporters", "gsa1_teleport_keep_speed")
        panel:ControlHelp("Run on out of the destination at the same speed. This needs libsa1's warp, which is not in "
            .. "this version yet: until then the character is re-created at the destination and arrives standing (rings "
            .. "and lives are kept).")
    end)
end
