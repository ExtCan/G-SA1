-- G-SA1 Board Off box (round 0.9.5; sadc docs/research/gsa1_095_plan.md 6.4 task 2, board095_gsa1.md 5.2 / 5.5; the owner's
-- answers gsa1_rounds_plan.md 14.1ad 3, 4, 7): a Sonic or Tails riding a board into the box gets off (the game's own exit,
-- order 24); the board stays behind where he got off, as decoration nobody rides again (gsa1_board_left). "1 use" boxes
-- work once (a use counts only after the server told that rider to get off).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "gsa1_trigger"
ENT.PrintName = "Board Off"
ENT.Author = "G-SA1"
ENT.Information = "Sonic or Tails riding a board into this box gets off; the board stays behind (right-click > Edit "
    .. "Properties: size, uses)"
ENT.Category = "G-SA1"
ENT.Spawnable = true
ENT.Editable = true
ENT.GSA1Object = true
ENT.GSA1Trigger = true
ENT.GSA1BoxKind = "off"
ENT.ScriptedEntityType = "entity"
