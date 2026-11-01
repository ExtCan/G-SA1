-- G-SA1 trigger box base (round 0.9.5; sadc docs/research/gsa1_095_plan.md 6.4 task 2, board095_gsa1.md 5.1 / 5.2 / 5.9):
-- the base of the G-SA1 trigger boxes - "Board On" (gsa1_board_on) and "Board Off" (gsa1_board_off) in 0.9.5, 1.0's
-- camera / spline / scripted triggers later. Not spawnable itself.
--
-- A trigger box is a resizable volume: its origin is the CENTRE OF ITS BASE and it grows up from there (Length along its
-- forward, Width along its left, Height up; 32..8,192 HU). Nothing of the game is inside it: the server's swept edge test
-- (feat/sv_board.lua, on each character player's state packets) decides who enters, the client does the rest
-- (feat/cl_board.lua). It is sent to every client (TRANSMIT_ALWAYS: a far Board On box's board is drawn, and 0.9.6's
-- followers test the boxes on the client). The objects' patterns where they fit (0.9.4.1, feat/sh_objects.lua "THE PICK
-- HULL"): SOLID_OBB with the box as its collision bounds and custom collisions, so only the editing rays (the Physics Gun's,
-- the Tool Gun's, the context menu's: O.PickTrace) hit it and players, props and NPCs pass through (COLLISION_GROUP_WORLD);
-- a frozen physics box of it (at most 2,048 HU from the centre on each axis) that the Physics Gun carries and that is
-- frozen again where it is dropped. GSA1Object = true keeps it out of the collision and interaction scanners
-- (cl_collision.lua, feat/cl_interact.lua, feat/sv_interact.lua); GSA1Trigger = true keeps it out of the objects feature
-- (feat/sh_objects.lua O.IsObject). The editable values (size, Enabled, Uses and the class's own) survive a copy (the
-- duplicator, a save); the runtime state starts fresh. Placing: on the aimed surface, the placer's yaw, upright; the limit
-- sbox_maxgsa1_triggers; Utilities > Cleanup > "G-SA1 trigger boxes"; undo "Undone G-SA1 <name>".
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "G-SA1 trigger box"
ENT.Author = "G-SA1"
ENT.Category = "G-SA1"
ENT.Spawnable = false
ENT.Editable = true
ENT.GSA1Object = true
ENT.GSA1Trigger = true
ENT.ScriptedEntityType = "entity"
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.GSA1Model = "models/hunter/blocks/cube025x025x025.mdl"   -- never drawn (the box is the collision bounds)

-- every box's NetworkVars; the class's own come from ENT:GSA1Vars (gsa1_board_on.lua, gsa1_board_off.lua)
function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Enabled", { KeyName = "enabled",
        Edit = { type = "Boolean", order = 1, title = "Enabled" } })
    self:NetworkVar("Int", 0, "Uses", { KeyName = "uses",
        Edit = { type = "Combo", order = 2, title = "Uses", values = { ["Infinite uses"] = 0, ["1 use"] = 1 } } })
    self:NetworkVar("Float", 0, "Width", { KeyName = "width",
        Edit = { type = "Float", order = 20, min = 32, max = 8192, title = "Width (HU)" } })
    self:NetworkVar("Float", 1, "Length", { KeyName = "length",
        Edit = { type = "Float", order = 21, min = 32, max = 8192, title = "Length (HU)" } })
    self:NetworkVar("Float", 2, "Height", { KeyName = "height",
        Edit = { type = "Float", order = 22, min = 32, max = 8192, title = "Height (HU)" } })
    self:NetworkVar("Int", 1, "Used")                   -- runtime: the uses so far
    self:NetworkVar("Entity", 0, "Placer")              -- runtime: who placed it ("Reset this box")
    if self.GSA1Vars then self:GSA1Vars() end
    -- a new size: the server re-makes the hull and the board's place, the client its bounds (feat/sv_board.lua,
    -- feat/cl_board.lua)
    local B = GSA1 and GSA1.Board
    if B and B.OnVarChanged and self.NetworkVarNotify then
        for _, name in ipairs({ "Width", "Length", "Height" }) do self:NetworkVarNotify(name, B.OnVarChanged) end
    end
end

function ENT:SpawnFunction(ply, tr, ClassName)
    if not tr or not tr.Hit then return end
    local B = GSA1 and GSA1.Board
    if not (B and B.ServerSpawn) then return end
    return B.ServerSpawn(ply, tr, ClassName)
end

function ENT:Initialize()
    if self.GSA1Model and self.SetModel then self:SetModel(self.GSA1Model) end
    if self.DrawShadow then self:DrawShadow(false) end
    if self.EnableCustomCollisions then self:EnableCustomCollisions(true) end
    local B = GSA1 and GSA1.Board
    if SERVER then
        if B and B.ServerInit then B.ServerInit(self) end
    elseif B and B.ClientInit then
        B.ClientInit(self)
    end
end

if SERVER then
    function ENT:UpdateTransmitState()
        return TRANSMIT_ALWAYS
    end

    -- a copy keeps the editable values, not the runtime state
    function ENT:OnEntityCopyTableFinish(data)
        local B = GSA1 and GSA1.Board
        if B and B.FreshState then B.FreshState(data.DT) end
    end

    function ENT:OnDuplicated(data)
        local B = GSA1 and GSA1.Board
        if B and B.ResetBox then B.ResetBox(self, nil) end
    end
end

-- the pick hull: an editing ray hits the whole box, hull traces and every other ray pass (feat/sh_objects.lua O.PickTrace)
function ENT:TestCollision(startpos, delta, isbox, extents, mask)
    if isbox then return end
    local O = GSA1 and GSA1.Objects
    if not (O and O.PickTrace) then return end
    return O.PickTrace(self, startpos, delta, isbox)
end

function ENT:PhysgunPickup(ply)
    local B = GSA1 and GSA1.Board
    if B and B.MayPick then return B.MayPick(ply, self) end
    return true
end

function ENT:OnRemove()
    local B = GSA1 and GSA1.Board
    if CLIENT and B and B.ClientRemove then B.ClientRemove(self) end
end

-- the board lying in a Board On box (always), the volume while editing (feat/cl_board.lua B.DrawBox)
function ENT:Draw(flags)
    local B = GSA1 and GSA1.Board
    if B and B.DrawBox then B.DrawBox(self, 0, flags) end
end

function ENT:DrawTranslucent(flags)
    local B = GSA1 and GSA1.Board
    if B and B.DrawBox then B.DrawBox(self, 1, flags) end
end
