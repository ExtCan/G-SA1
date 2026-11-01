-- G-SA1 feature "liveshadow" (the characters' sun shadow), shared part: its settings. Round 0.9.5 (sadc docs/research/
-- gsa1_095_plan.md 4.17 and 5.8; the owner's binding answer 14.1ad 5: "the characters need to feel like they're in the
-- world", no CSM addon, so G-SA1 draws the sun shadow itself, like Garry's Mod shadows the props on his maps; and,
-- explicitly: "The G-SA1 drawn sun shadow should be toggleable"). The drawing is feat/cl_liveshadow.lua; the game's own
-- round shadow (gsa1_shadow) is not touched. Client settings (GSA1.ConVar: nil on the server), each with its control on
-- Q menu > Options > G-SA1 > Rendering (cl_menu.lua rendering_panel):
--   gsa1_sunshadow       1  the sun shadow on / off (off: no hook, nothing drawn, nothing computed, nothing read)
--   gsa1_sunshadow_fp    0  also in first person (you see your own shadow on the ground)
--   gsa1_sunshadow_dark  0  its darkness in percent (0 = the map's own shadow colour: shadow_control's "color")
GSA1 = GSA1 or {}
GSA1.SunShadow = GSA1.SunShadow or {}
local S = GSA1.SunShadow
S.cv = S.cv or {}
S.cv.on = GSA1.ConVar("gsa1_sunshadow", 1, "Your character's sun shadow, drawn by G-SA1 in the direction, colour and length "
    .. "Garry's Mod uses for the props on this map (its shadow_control, else its light_environment, else straight down), "
    .. "on the ground and on props; 0 = off (nothing of it is drawn or computed). The game's round shadow is gsa1_shadow",
    0, 1)
S.cv.fp = GSA1.ConVar("gsa1_sunshadow_fp", 0, "The sun shadow in first person too (you see your own shadow on the "
    .. "ground)", 0, 1)
S.cv.dark = GSA1.ConVar("gsa1_sunshadow_dark", 0, "The sun shadow's darkness in percent: 0 = the map's own shadow colour, "
    .. "1-100 = this darkness instead", 0, 100)
