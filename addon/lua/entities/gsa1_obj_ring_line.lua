-- G-SA1 Ring line (round 0.9.4; sadc docs/research/gsa1_094_plan.md 6.5 task 2): a row of 1 to 128 (0.9.4: 64) of the
-- game's rings along the entity's forward direction (the way you looked when you placed it), centred on the entity. The
-- game's own ring group O_GRING (8C087B80) runs it: one group of up to 8 rings per 8 places (the game's line of n + 1
-- rings, laid out by its code_8C087B80.c func_8C087EEE), so every ring taken is shared through the groups' user bits
-- (TakenBits: two hex digits per group, feat/sh_objects.lua O.BitsGet).
-- Count and Spacing (Hammer units; the game's usual 10 units = 40) are editable (right-click > Edit Properties).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "gsa1_base"
ENT.PrintName = "Ring line"
ENT.Author = "G-SA1"
ENT.Information = "A row of the game's rings (1 to 128) along the way you look; Count and Spacing in Edit Properties"
ENT.Category = "G-SA1"
ENT.Spawnable = true
ENT.Editable = true
ENT.GSA1Object = true
ENT.ScriptedEntityType = "gsa1_object"

function ENT:GSA1Vars()
    self:NetworkVar("Int", 2, "Count", { KeyName = "count",
        Edit = { type = "Int", order = 1, min = 1, max = 128, title = "Count (rings)" } })
    self:NetworkVar("Float", 2, "Spacing", { KeyName = "spacing",
        Edit = { type = "Float", order = 2, min = 8, max = 400, title = "Spacing (Hammer units)" } })
    -- the rings taken: the game's group user flag of each record (up to 16), two hex digits per record (0.9.4.1)
    self:NetworkVar("String", 0, "TakenBits")
end
