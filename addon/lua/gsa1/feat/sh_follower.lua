-- G-SA1 feature "follower", shared part (both realms; round 0.9.8: sadc docs/research/gsa1_098_plan.md 2.4, 5.6, 5.9, 6.7;
-- gsa1_096_plan.md 4.10, 4.12-4.19, 4.21, 5.6, 5.7, 6.5 with its review; follow096_gsa1.md 3, 4.4-4.6, 6-9; the owner's answers
-- gsa1_rounds_plan.md 14.1a Q1 (a), 14.1n, 14.2, 14.1ad 6).
--
-- A follower is a whole game world of its own (libsa1's follower world) in which the game's own "1.5P" follower AI steers the
-- character after its leader. This file: every setting (each has a control on Q menu > Options > G-SA1 > Followers:
-- feat/cl_follower.lua), the constants, the net messages' names and the spawn classes' names.
GSA1 = GSA1 or {}
GSA1.Followers = GSA1.Followers or {}
local Fo = GSA1.Followers

Fo.NEEDS = { feature = "follower", version = 1, module = "0.9.8" }
-- Tails first (14.2), then the bring-up order of libsa1's kinds; 0.9.9e (the owner, rounds plan 14.1bc): Dr. Eggman and Tikal, nothing repaired (Fo.PLAYABLE_NOTE)
Fo.KIND_ORDER = { 2, 0, 3, 6, 5, 7, 1, 4 }
Fo.KINDS = {
    [0] = { name = "sonic", title = "Sonic", letter = "S" },
    [2] = { name = "tails", title = "Tails", letter = "T" },
    [3] = { name = "knuckles", title = "Knuckles", letter = "K" },
    [5] = { name = "amy", title = "Amy", letter = "A" },
    [6] = { name = "gamma", title = "E-102 Gamma", letter = "E" },
    [7] = { name = "big", title = "Big", letter = "B" },
    [1] = { name = "eggman", title = "Dr. Eggman", letter = "D" },
    [4] = { name = "tikal", title = "Tikal", letter = "T" },
}
-- what they do, on the page: libsa1's tests/follower_test.c case FPL measured it, their code in the game has nothing for the follower AI's orders
Fo.PLAYABLE_NOTE = "Dr. Eggman and Tikal as followers: their own code, nothing repaired. They run after you and jump, but they have no flight or glide: when they drop in from above the camera they just fall. "
    .. "Tikal takes the follower code's flying button for her debug button, so after a drop-in she can hang in the air where she is until you move away. A hit does nothing to them. Their air timer still runs under water, but their code has no drown: "
    .. "when it ends they just stand there. Neither plays an emote, turns their head or rides a board."
Fo.BOARD_SLOTS = 15                     -- the board messages' u4 slot: 1 .. 15 (a 16th boards with remove = true)
Fo.EGG_MAX, Fo.NORMAL_MAX = 99, 8       -- made with ignore_cap at most; normal ones at most (4.14)
Fo.BEHIND = 40                          -- HU behind its leader (the game's mode 0 places it 10 units behind)
Fo.FAULT_WINDOW, Fo.FAULT_MAX = 10, 3   -- s, faults: then removed with one chat line
Fo.LOOP_WINDOW, Fo.LOOP_MAX, Fo.LOOP_HOLD = 10, 4, 3     -- s, drops, s: the loop guard (a host rule, gsa1_follower_loop_guard)
Fo.HOLD_ABOVE = 1000000                 -- HU above which a follower is a held one (AI modes 6-8: 1,000,000 units over its leader)
Fo.LEVEL_DELAY = 0.5                    -- s: the hysteresis of every draw level change
Fo.NET = { REQ = "gsa1_fol_req", MADE = "gsa1_fol_made", UNDO = "gsa1_fol_undo" }
Fo.REQ_RATE, Fo.TOKEN_LIFE = 10, 10     -- requests per second per player; s a token lives

function Fo.SpawnerClass(kind)
    local k = Fo.KINDS[kind]
    return k and ("gsa1_follower_" .. k.name) or nil
end

-- "the follower's title" for a kind
function Fo.KindTitle(kind)
    local k = Fo.KINDS[kind]
    return k and k.title or tostring(kind)
end

-- the settings (gsa1_098_plan.md 5.9) -----------------------------------------------------------------------------------------
Fo.cv = Fo.cv or {}
local cv = Fo.cv
cv.on = GSA1.ConVar("gsa1_follower", 1, "Followers: 0 = none can be made and yours are removed", 0, 1)
cv.kind = GSA1.ConVar("gsa1_follower_kind", 2, "The character the Spawn button makes (2 Tails, 0 Sonic, 3 Knuckles, 6 E-102, "
    .. "5 Amy, 7 Big, 1 Dr. Eggman, 4 Tikal)", 0, 7)
cv.max = GSA1.ConVar("gsa1_follower_max", 3, "Most followers at once (each is a whole game, about 21 MB); lowering it removes "
    .. "the newest", 1, Fo.NORMAL_MAX)
cv.target = GSA1.ConVar("gsa1_follower_target", 0, "New followers follow: 0 me, 1 the nearest player, 2 my last follower, 3 what "
    .. "I aim at, 4 stay here", 0, 4)
cv.upgrades = GSA1.ConVar("gsa1_follower_upgrades", 1, "Followers get your ticked upgrades of their character", 0, 1)
cv.objects = GSA1.ConVar("gsa1_follower_objects", 1, "New followers and the rings and item boxes: 0 they pass through them, 1 they "
    .. "touch them in their own game (nothing changes for you)", 0, 1)
cv.sounds = GSA1.ConVar("gsa1_follower_sounds", 1, "Followers' own sounds (the game's: a following Tails' own sound effects are "
    .. "silent)", 0, 1)
cv.board = GSA1.ConVar("gsa1_follower_board", 1, "Sonic and Tails followers get on a board when the one they follow does (and off "
    .. "again)", 0, 1)
cv.board_boxes = GSA1.ConVar("gsa1_follower_board_boxes", 1, "In Board On / Off boxes: 0 not at all, 1 walk to the box's board like "
    .. "you, 2 get on at once with a board of their own", 0, 2)
cv.come_along = GSA1.ConVar("gsa1_follower_come_along", 1, "Followers come along when you switch character, respawn or teleport",
    0, 1)
cv.loop_guard = GSA1.ConVar("gsa1_follower_loop_guard", 1, "A follower that keeps dropping in (4 times within 10 s) waits 3 s and "
    .. "comes back behind you; one that falls below the map drops in again at once (a host rule)", 0, 1)
-- round 0.9.9 (sadc docs/research/gsa1_099_plan.md 4.1 B3, B4, B5, 5.9; follow099.md 6.3, 7): keeping up, standing apart, emoting with you
Fo.SPEED_MAX, Fo.SPACING_MAX, Fo.SPACING_EGG = 4, 160, 40
cv.speed = GSA1.ConVar("gsa1_follower_speed", 1, "Followers behind you may run up to this many times their own speed until they have caught up; near you they run at the "
    .. "game's own speed (1 = the game; Sonic 1.2, Knuckles 1.3, Tails 1.5, E-102 2.5, Big 3.5, Amy 4 stay with Sonic at full speed)", 1, Fo.SPEED_MAX)
cv.spacing = GSA1.ConVar("gsa1_follower_spacing", 64, "Room between followers in units: with two or more, each has its own spot around the one it follows (0 = the game's own place: "
    .. "they can stand inside each other)", 0, Fo.SPACING_MAX)
cv.emotes = GSA1.ConVar("gsa1_follower_emotes", 1, "Your followers play the same slot of their own wheel when you play one from the emote wheel", 0, 1)

-- the spot of the i-th of n followers, x, y in HU (pure: the tests call it): a sunflower in world axes. One follower: the game's own place
function Fo.SpotOf(i, n, s)
    if n < 2 or s <= 0 then return 0, 0 end
    local r, a = s * math.sqrt(i), i * 2.39996323
    return r * math.cos(a), r * math.sin(a)
end

cv.fix_view = GSA1.ConVar("gsa1_follower_fix_view", 1, "New followers: their own animations run where the game's camera cannot see "
    .. "them (not in the game)", 0, 1)
cv.fix_respawn = GSA1.ConVar("gsa1_follower_fix_respawn", 1, "New followers: after dropping in, those other than Tails forget where "
    .. "they were, which stops Knuckles bouncing back (not in the game)", 0, 1)
cv.full_detail = GSA1.ConVar("gsa1_follower_full_detail", 8, "Followers drawn in full detail (the nearest; the others more cheaply)",
    0, 99)
cv.far_rate = GSA1.ConVar("gsa1_follower_far_rate", 15, "Far followers: pictures per second", 5, 30)
cv.draw_dist = GSA1.ConVar("gsa1_follower_draw_dist", 4800, "Followers drawn up to this many units", 500, 12000)
cv.other_views = GSA1.ConVar("gsa1_follower_other_views", 0, "Followers in other addons' views (reflections, cube maps): off = on "
    .. "the screen, in the depth pass and in water only", 0, 1)
cv.threads = GSA1.ConVar("gsa1_follower_threads", 0, "CPU threads for followers (0 = automatic)", 0, 16)
cv.call_key = GSA1.ConVar("gsa1_follower_call_key", 16, "Call your followers back, while the emote wheel is open (a key code; 16 = "
    .. "F; 0 = none)", 0, 511)
cv.call_pad = GSA1.ConVar("gsa1_follower_call_pad", 64, "The controller button that calls your followers back, while the emote "
    .. "wheel is open (XInput bits: 64 = left stick click; 0 = none)", 0, 0x30000)
-- server (replicated, archived: both realms)
cv.sv_icons = GSA1.ConVar("gsa1_sv_follower_icons", 1, "Follower icons in the spawn menu work on this server", 0, 1,
    { server = true })
