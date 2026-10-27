-- G-SA1 Item Box (Air) (round 0.9.4; sadc docs/research/gsa1_094_plan.md 6.5 task 2, gsa1_094_items.md): the game's
-- floating item box (O_ItemBoxAir, objexec 8C05D9F6), 40 units above the surface you aim at (low enough to touch while
-- running; move it with the Physics Gun), turned like the entity. Any character breaks it by touching it and gets the
-- item; it is then gone for everyone (State). Contents: as the Item Box's.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "gsa1_base"
ENT.PrintName = "Item Box (Air)"
ENT.Author = "G-SA1"
ENT.Information = "The game's floating item box: touch it to get its item (Contents: right-click)"
ENT.Category = "G-SA1"
ENT.Spawnable = true
ENT.Editable = true
ENT.GSA1Object = true
ENT.ScriptedEntityType = "gsa1_object"

local CONTENTS = { "Speed Shoes (HAYAASI)", "Invincibility (MUTEKI)", "5 Rings (5RING)", "10 Rings (10RING)",
                   "Random Rings (RANDOMRING)", "Barrier (BARIA)", "Extra Life (1UP)", "Bomb (EKUSUPUROSYON)",
                   "Magnetic Barrier (ITEM_TH_BARIA)" }

function ENT:GSA1Vars()
    local values = {}
    for i, name in ipairs(CONTENTS) do values[name] = i - 1 end
    self:NetworkVar("Int", 2, "Contents", { KeyName = "contents",
        Edit = { type = "Combo", order = 1, values = values, title = "Contents" } })
end
