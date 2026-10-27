-- G-SA1 Item Box (round 0.9.4; sadc docs/research/gsa1_094_plan.md 6.5 task 2, gsa1_094_items.md): the game's item box
-- standing on the ground (O_ITEMBOX, objexec 8C05D10C), its base on the surface you aim at, always upright (the game draws
-- it upright and its cylinder is vertical). Every character breaks it the way the game does - jump on it, roll or spin-dash
-- into it, Knuckles' punch, E-102's laser, Big just walks up to it - and gets the item; walking into it only blocks. It
-- stays as its broken base, for everyone (Broken). Contents: one of the game's nine items (right-click > Contents, or Edit
-- Properties); a new box holds what the Objects page says (gsa1_set_box_content, 10 Rings).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "gsa1_base"
ENT.PrintName = "Item Box"
ENT.Author = "G-SA1"
ENT.Information = "The game's item box on the ground: break it to get its item (Contents: right-click)"
ENT.Category = "G-SA1"
ENT.Spawnable = true
ENT.Editable = true
ENT.GSA1Object = true
ENT.ScriptedEntityType = "gsa1_object"

-- the nine contents for the Edit Properties combo (the same names as feat/sh_objects.lua O.CONTENTS)
local CONTENTS = { "Speed Shoes (HAYAASI)", "Invincibility (MUTEKI)", "5 Rings (5RING)", "10 Rings (10RING)",
                   "Random Rings (RANDOMRING)", "Barrier (BARIA)", "Extra Life (1UP)", "Bomb (EKUSUPUROSYON)",
                   "Magnetic Barrier (ITEM_TH_BARIA)" }

function ENT:GSA1Vars()
    local values = {}
    for i, name in ipairs(CONTENTS) do values[name] = i - 1 end
    self:NetworkVar("Int", 2, "Contents", { KeyName = "contents",
        Edit = { type = "Combo", order = 1, values = values, title = "Contents" } })
end
