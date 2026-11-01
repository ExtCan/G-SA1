-- G-SA1 Board On box (round 0.9.5; sadc docs/research/gsa1_095_plan.md 6.4 task 2, board095_gsa1.md 5.2 - 5.4; the owner's
-- answers gsa1_rounds_plan.md 14.1ad 3, 4, 8): a board lies on the ground in the middle of the box (the game's own board,
-- drawn from your disc); a Sonic or Tails who enters the box WALKS to it by himself (the game's own walking, fed by the
-- stick; a jump stops it) and gets on it with the game's own code (feat/cl_board.lua). The board is then gone from the
-- box and comes back after "Refill after" seconds (Refill off: never, until "Reset this box"); "1 use" boxes work once.
-- Push: Ice Cap's start push when he gets on (default), none, or the rider's own setting; Ground: the rider's setting,
-- the map's surfaces, Ice Cap snow or Sand Hill sand. A rider entering the box keeps riding (the box's ground applies).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "gsa1_trigger"
ENT.PrintName = "Board On"
ENT.Author = "G-SA1"
ENT.Information = "Sonic or Tails walks to the board lying in this box and gets on it (right-click > Edit Properties: size, "
    .. "uses, refill, push, ground)"
ENT.Category = "G-SA1"
ENT.Spawnable = true
ENT.Editable = true
ENT.GSA1Object = true
ENT.GSA1Trigger = true
ENT.GSA1BoxKind = "on"
ENT.ScriptedEntityType = "entity"

function ENT:GSA1Vars()
    self:NetworkVar("Bool", 1, "Refill", { KeyName = "refill",
        Edit = { type = "Boolean", order = 3, title = "Refill (the board comes back)" } })
    self:NetworkVar("Float", 3, "RefillAfter", { KeyName = "refillafter",
        Edit = { type = "Float", order = 4, min = 0, max = 600, title = "Refill after (s)" } })
    self:NetworkVar("Int", 2, "Push", { KeyName = "push",
        Edit = { type = "Combo", order = 5, title = "Start push",
                 values = { ["Ice Cap's start push"] = 1, ["None"] = 0, ["The rider's own setting"] = 2 } } })
    self:NetworkVar("Int", 3, "Ground", { KeyName = "ground",
        Edit = { type = "Combo", order = 6, title = "Ground under the board",
                 values = { ["The rider's own setting"] = 0, ["The map's surfaces"] = 1, ["Ice Cap snow"] = 2,
                            ["Sand Hill sand"] = 3 } } })
    self:NetworkVar("Bool", 2, "Present")               -- runtime: the board lies there
    self:NetworkVar("Float", 4, "RespawnAt")            -- runtime: CurTime of the refill (0: none due)
    self:NetworkVar("Vector", 0, "BoardPos")            -- runtime: where the board lies (the server's trace down)
    self:NetworkVar("Angle", 0, "BoardAng")             -- runtime: its angles (the ground's normal, the box's yaw)
end
