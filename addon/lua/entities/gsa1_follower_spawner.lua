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

-- 0.9.9h (the owner: "Skins (such as Metal Sonic) should be automatically added as spawnable followers"): one more per skin entry of GSA1.CHARACTERS (form "skin", not secret), from its
-- data alone; its kind is its base's (Metal Sonic: Sonic's world). Its icon is entities/gsa1_follower_<name>.png (tools/make_follower_icons.py), else its base's
local NAMES = {}
for _, k in ipairs(KINDS) do NAMES[k[1]] = k[2] end
local SKINS = {}
for _, c in ipairs(GSA1 and GSA1.CHARACTERS or {}) do
    if c.form == "skin" and not c.secret and NAMES[c.kind] then
        local icon = "entities/gsa1_follower_" .. c.name .. ".png"
        if file and file.Exists and not file.Exists("materials/" .. icon, "GAME") then icon = "entities/gsa1_follower_" .. NAMES[c.kind] .. ".png" end
        SKINS[#SKINS + 1] = { c.kind, c.name, c.title, c.name, icon }
    end
end

local function register(k)
    local E = {
        Type = "point", Base = "base_point", Category = "G-SA1", Spawnable = true, AdminOnly = false,
        PrintName = k[3] .. " (follower)", Author = "G-SA1", DisableDuplicator = true, GSA1FollowerKind = k[1], GSA1FollowerSkin = k[4],
        Information = "Spawns a " .. k[3] .. " who follows you, with the game's own follower code (Q menu > Options > G-SA1 > "
            .. "Followers)",
        ScriptedEntityType = "entity", IconOverride = k[5] or ("entities/gsa1_follower_" .. k[2] .. ".png"),
    }
    function E:SpawnFunction(ply, tr, class)
        if GSA1 and GSA1.FollowerRequest then GSA1.FollowerRequest(ply, self.GSA1FollowerKind, self.GSA1FollowerSkin) end
        return nil
    end
    scripted_ents.Register(E, "gsa1_follower_" .. k[2])
end
for _, k in ipairs(KINDS) do register(k) end
for _, k in ipairs(SKINS) do register(k) end
