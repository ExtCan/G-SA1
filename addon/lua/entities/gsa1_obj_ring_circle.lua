-- G-SA1 Ring circle (round 0.9.4; sadc docs/research/gsa1_094_plan.md 6.5 task 2): a flat circle of 1 to 128 of the
-- game's rings around the entity, the game's own ring group O_GRING (8C087B80) as circles (code_8C087B80.c
-- func_8C088000). A game circle has a bit in its user flag for 7 rings at most (the 8th would never be shared: sadc
-- docs/research/gsa1_090_rings.md review R.2.7), so since 0.9.4.1 a circle of N rings is several game circles of n rings
-- (n = the largest of 7..1 dividing N), each turned by its share of the turn: together the evenly spaced N
-- (feat/sh_objects.lua O.CircleSplit). Count and Radius (Hammer units) are editable.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "gsa1_base"
ENT.PrintName = "Ring circle"
ENT.Author = "G-SA1"
ENT.Information = "A circle of the game's rings (1 to 128) around this place; Count and Radius in Edit Properties"
ENT.Category = "G-SA1"
ENT.Spawnable = true
ENT.Editable = true
ENT.GSA1Object = true
ENT.ScriptedEntityType = "gsa1_object"

function ENT:GSA1Vars()
    self:NetworkVar("Int", 2, "Count", { KeyName = "count",
        Edit = { type = "Int", order = 1, min = 1, max = 128, title = "Count (rings)" } })
    self:NetworkVar("Float", 2, "Radius", { KeyName = "radius",
        Edit = { type = "Float", order = 2, min = 16, max = 800, title = "Radius (Hammer units)" } })
    -- the rings taken: the game's group user flag (bits 1..n) of each record (up to 127), two hex digits per record
    self:NetworkVar("String", 0, "TakenBits")
end
