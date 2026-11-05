-- G-SA1 photo mode (0.9.9d; sadc docs/research/photo099d.md with its review RP.1-16, and the owner's later answers, which win over it: "12. Freezing the world should be optional", "13. No, while you're in Photomode you are completely
-- invincible and untouchable"), both realms: the table, the message, the client's settings (GSA1.ConVar: nil on the server), each with its control on Q menu > Options > G-SA1 > Photo mode (feat/cl_photo.lua Photo.Page).
GSA1 = GSA1 or {}
GSA1.Photo = GSA1.Photo or {}
local P = GSA1.Photo
-- client -> server: UInt(2) flags (1 in photo mode, 2 the world too), Bool an eye follows, Vector the eye
-- server -> client: UInt(3) the world's parts that took (P.WORLD's bits)
P.NET = "gsa1_photo"
if SERVER then util.AddNetworkString(P.NET) end
-- what stops with "Freeze the world too": server ConVars, in single player only. feat/sv_photo.lua says what each leaves behind and what was rejected
P.WORLD = {
    { name = "phys_timescale", on = "0", bit = 1, what = "props and everything else on physics" },     -- READ: Sandbox's own Utilities slider goes down to 0 (lua/autorun/utilities_menu.lua)
    { name = "ai_disabled", on = "1", bit = 2, what = "NPCs" },                                         -- READ: Sandbox's own menu bar, NPCs > Disable AI (lua/autorun/menubar.lua)
    { name = "nb_stop", on = "1", bit = 4, what = "NextBots" },                                         -- MEASURED: the name and "Stop all NextBots" are in the game's server.dll; whether it takes without sv_cheats is UNVERIFIED: the page says
}
P.WORLD_ALL = 7
P.cv = P.cv or {}
local cv = P.cv
cv.key = GSA1.ConVar("gsa1_photo_key", 21, "The photo mode key: freezes you and your followers mid-pose, press it again to go on from the same moment; 0 = no key (bind gsa1_photo yourself)", 0, 200)
cv.pad = GSA1.ConVar("gsa1_photo_pad", 0, "The controller button for photo mode (XInput bits; 0 = none)", 0, 65535)
cv.hud = GSA1.ConVar("gsa1_photo_hud", 1, "Hide the HUD while frozen", 0, 1)
cv.shadows = GSA1.ConVar("gsa1_photo_shadows", 0, "Hide the sun shadows and the game's round shadow while frozen", 0, 1)
cv.jukebox = GSA1.ConVar("gsa1_photo_jukebox", 1, "The jukebox and Super Sonic's music keep playing while frozen", 0, 1)
cv.speed = GSA1.ConVar("gsa1_photo_speed", 200, "The free camera's speed, units a second", 20, 2000)
cv.hint = GSA1.ConVar("gsa1_photo_hint", 1, "Show four seconds of what the keys do when photo mode starts", 0, 1)
cv.world = GSA1.ConVar("gsa1_photo_world", 0, "Freeze the world too while frozen, in single player: props, NPCs and NextBots stop", 0, 1)
