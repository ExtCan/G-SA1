-- G-SA1 feature "giverings", server part (0.9.2a; feat/sh_giverings.lua): a client asks before it changes its
-- character's rings by hand; the server answers with the same rule (single player, sv_cheats 1, an admin, the listen
-- server's host), from its own view of the player. At most 5 questions a second per player.
local NETS = GSA1.GiveRingsNet
util.AddNetworkString(NETS.ASK)
util.AddNetworkString(NETS.ANSWER)

net.Receive(NETS.ASK, function(len, ply)
    if not IsValid(ply) then return end
    local now = SysTime()
    if now - (ply.GSA1RingsAsked or 0) < 0.2 then return end
    ply.GSA1RingsAsked = now
    local token = net.ReadUInt(8)
    local n = net.ReadInt(16)
    local ok, why = GSA1.RingsRule(ply)
    net.Start(NETS.ANSWER)
    net.WriteUInt(token, 8)
    net.WriteBool(ok and true or false)
    net.WriteString(ok and "" or tostring(why or "not allowed"))
    net.Send(ply)
    if not ok then
        print(string.format("[G-SA1] %s asked to change their character's rings by %d: refused (%s)", tostring(ply:Nick()),
            n, tostring(why)))
    end
end)
