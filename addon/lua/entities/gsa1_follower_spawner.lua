-- G-SA1 follower spawners (round 0.9.8; sadc docs/research/gsa1_096_plan.md 5.7, follow096_gsa1.md 4.5): one spawn icon per
-- character (gsa1_follower_tails, ...), in Entities > G-SA1 and in the G-SA1 tab's Followers group. A spawner makes NO entity:
-- its SpawnFunction asks the spawning client to make the follower (feat/sv_follower.lua GSA1.FollowerRequest) and returns nil, so
-- the sandbox makes no undo and no cleanup of its own (UNVERIFIED in game: Spawn_SENT returning early for a nil entity; the
-- owner's checklist covers it); the Undo entry comes when the client says it made one. This file's own class is never spawned.
AddCSLuaFile()

ENT.Type = "point"
ENT.Base = "base_point"
ENT.PrintName = "G-SA1 follower spawner"
ENT.Spawnable = false
ENT.DisableDuplicator = true

local KINDS = {
    { 2, "tails", "Tails" }, { 0, "sonic", "Sonic" }, { 3, "knuckles", "Knuckles" },
    { 6, "gamma", "E-102 Gamma" }, { 5, "amy", "Amy" }, { 7, "big", "Big" },
    { 1, "eggman", "Dr. Eggman" }, { 4, "tikal", "Tikal" },     -- (0.9.9e)
}

for _, k in ipairs(KINDS) do
    local E = {
        Type = "point", Base = "base_point", Category = "G-SA1", Spawnable = true, AdminOnly = false,
        PrintName = k[3] .. " (follower)", Author = "G-SA1", DisableDuplicator = true, GSA1FollowerKind = k[1],
        Information = "Spawns a " .. k[3] .. " who follows you, with the game's own follower code (Q menu > Options > G-SA1 > "
            .. "Followers)",
        ScriptedEntityType = "entity", IconOverride = "entities/gsa1_follower_" .. k[2] .. ".png",
    }
    function E:SpawnFunction(ply, tr, class)
        if GSA1 and GSA1.FollowerRequest then GSA1.FollowerRequest(ply, self.GSA1FollowerKind) end
        return nil
    end
    scripted_ents.Register(E, "gsa1_follower_" .. k[2])
end
