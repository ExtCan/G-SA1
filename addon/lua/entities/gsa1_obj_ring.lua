-- G-SA1 Ring (round 0.9.4; sadc docs/research/gsa1_094_plan.md 6.5 task 2): one of the game's rings (the SET object RING,
-- objexec_RING 8C0869E8) where you place it, 32 units above the surface. Every character's own game code collects it
-- (the ring sound, the sparkle, the HUD count, a 1-up at 100), and the server shares it: a ring one player takes is gone
-- for everyone ("Respawn after" brings it back; the game itself never does). The base: gsa1_base.lua.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "gsa1_base"
ENT.PrintName = "Ring"
ENT.Author = "G-SA1"
ENT.Information = "One of the game's own rings: your character collects it like in Sonic Adventure"
ENT.Category = "G-SA1"
ENT.Spawnable = true
ENT.Editable = true
ENT.GSA1Object = true
ENT.ScriptedEntityType = "gsa1_object"
