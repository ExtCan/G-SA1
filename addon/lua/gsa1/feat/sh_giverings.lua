-- G-SA1 feature "giverings", shared part (0.9.2a; the 0.9.2 verifier's leftover): ONE rule for every way of changing a
-- character's rings by hand - "Give 10 / 50 / 100 rings" and gsa1_give_rings (cl_character.lua GSA1.GiveRings, the
-- Character page) and gsa1_rings / gsa1_rings_add (feat/cl_tools.lua, the "Debug" page): allowed in single
-- player, with sv_cheats 1, for an admin and for the listen server's host (0.9.2 had two rules: the buttons left out
-- sv_cheats, the console commands the host). The client checks it, and in multiplayer it also asks the server
-- (feat/sv_giverings.lua), which checks the same rule with its own view of the player before the client changes the
-- rings (the character runs on the client: the server's answer is what lets it go ahead). Single player, or a server
-- without G-SA1's network string: the client's check alone.
GSA1 = GSA1 or {}
GSA1.GiveRingsNet = { ASK = "gsa1_rings_ask", ANSWER = "gsa1_rings_answer" }
local NETS = GSA1.GiveRingsNet

-- ply may change rings? Returns ok, why (why: a plain sentence when not)
function GSA1.RingsRule(ply)
    if game.SinglePlayer() then return true end
    local sc = GetConVar("sv_cheats")
    if sc and sc:GetBool() then return true end
    if IsValid(ply) and ply.IsListenServerHost and ply:IsListenServerHost() then return true end
    if IsValid(ply) and ply.IsAdmin and ply:IsAdmin() == true then return true end
    return false, "in multiplayer only an admin or the server's host may change rings (or anyone with sv_cheats 1)"
end

if CLIENT then
    local pending, token = {}, 0

    -- run apply() now (single player, or no server half), or after the server agrees; returns true when it ran now or
    -- the question went out, false when refused at once. what: a short text for the messages ("Give rings")
    function GSA1.RingsRequest(what, n, apply)
        local ok, why = GSA1.RingsRule(LocalPlayer())
        if not ok then
            GSA1.Chat("%s: %s", what, why)
            if GSA1.Log then GSA1.Log("game", "%s %s refused: %s", what, tostring(n), why) end
            return false
        end
        if game.SinglePlayer() or util.NetworkStringToID(NETS.ASK) == 0 then
            return apply() ~= false
        end
        token = (token + 1) % 256
        pending[token] = { what = what, n = n, apply = apply, at = SysTime() }
        net.Start(NETS.ASK)
        net.WriteUInt(token, 8)
        net.WriteInt(math.floor(tonumber(n) or 0), 16)
        net.SendToServer()
        return true
    end

    net.Receive(NETS.ANSWER, function()
        local t = net.ReadUInt(8)
        local ok = net.ReadBool()
        local why = net.ReadString()
        local p = pending[t]
        pending[t] = nil
        if not p or SysTime() - p.at > 10 then return end
        if ok then
            local aok, err = pcall(p.apply)
            if not aok and GSA1.Log then GSA1.Log("error", "%s: %s", p.what, tostring(err)) end
        else
            GSA1.Chat("%s: the server says no: %s", p.what, why ~= "" and why or "not allowed")
            if GSA1.Log then GSA1.Log("game", "%s %s refused by the server: %s", p.what, tostring(p.n), why) end
        end
    end)
end
