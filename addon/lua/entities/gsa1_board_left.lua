-- G-SA1 left board (round 0.9.5; sadc docs/research/gsa1_095_plan.md 4.8, 6.4 task 2, board095_gsa1.md 5.5; the owner's
-- answer gsa1_rounds_plan.md 14.1ad 7: "A left-behind board just stays there: decoration only, nobody can get back on it"):
-- the board a Sonic or Tails got off, where it came to rest in his world - made by the server from the rider's client's
-- gsa1_board_left message (feat/sv_board.lua) and drawn by every client from the game's board model (feat/cl_board.lua,
-- the BOARD preview). The rider's world then frees its own board (gsa1.BoardFree), so nobody sees two. Not spawnable, no
-- collision, no physics, no duplicator (a decoration with a lifetime is not saved); owned by its player: Undo ("Undone
-- G-SA1 left board"), Utilities > Cleanup > "G-SA1 left boards", removed after gsa1_sv_board_left_time seconds (0 =
-- never), at most gsa1_sv_board_left_max per player (the oldest goes). GSA1Object keeps it out of the collision and
-- interaction scanners, GSA1Trigger out of the objects feature (it is no box: nothing triggers on it).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Left board"
ENT.Author = "G-SA1"
ENT.Category = "G-SA1"
ENT.Spawnable = false
ENT.Editable = false
ENT.DisableDuplicator = true
ENT.GSA1Object = true
ENT.GSA1Trigger = true
ENT.ScriptedEntityType = "entity"
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.GSA1Model = "models/hunter/blocks/cube025x025x025.mdl"   -- never drawn

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Kind")                   -- whose board: 0 Sonic, 2 Tails
    self:NetworkVar("Int", 1, "Variant")                -- Sonic: 0 MIW_B001, 1 SB_BOARD1 (the game's pick); Tails: 0
    self:NetworkVar("Int", 2, "Slot")                   -- the rider's character slot (0: his own; 0.9.6: followers)
    self:NetworkVar("Entity", 0, "Rider")               -- the player whose character got off
end

function ENT:Initialize()
    if self.GSA1Model and self.SetModel then self:SetModel(self.GSA1Model) end
    if self.DrawShadow then self:DrawShadow(false) end
    if SERVER then
        if self.SetSolid then self:SetSolid(SOLID_NONE or 0) end
        if self.SetMoveType then self:SetMoveType(MOVETYPE_NONE or 0) end
        if self.SetCollisionGroup then self:SetCollisionGroup(COLLISION_GROUP_WORLD or 20) end
    else
        if self.SetRenderBounds then self:SetRenderBounds(Vector(-64, -64, -24), Vector(64, 64, 40)) end
        local B = GSA1 and GSA1.Board
        if B and B.LeftInit then B.LeftInit(self) end
    end
end

if SERVER then
    function ENT:UpdateTransmitState()
        return TRANSMIT_ALWAYS
    end
end

function ENT:OnRemove()
    local B = GSA1 and GSA1.Board
    if CLIENT and B and B.LeftRemove then B.LeftRemove(self) end
end

function ENT:Draw(flags)
    local B = GSA1 and GSA1.Board
    if B and B.DrawLeft then B.DrawLeft(self, 0, flags) end
end

function ENT:DrawTranslucent(flags)
    local B = GSA1 and GSA1.Board
    if B and B.DrawLeft then B.DrawLeft(self, 1, flags) end
end
