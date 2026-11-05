-- G-SA1 Character Select (round 0.9.8; sadc docs/research/gsa1_098_plan.md 6.10, charsel098.md 6): the pure part, loaded in
-- both realms before feat/cl_charselect.lua: which list entry a slot of the game's ring plays, where the game's 640 x 480
-- screen goes on yours, the shortest run of presses to a sphere, and the draws hidden from the bottom bar. No engine call and
-- no state here, so the tests run it as it is. A pick is a plain GSA1.Spawn: the server never hears of this screen.
GSA1 = GSA1 or {}
local S = GSA1.CharSelect or {}
GSA1.CharSelect = S

S.SLOTS = 7                     -- the game's ring: 0 Sonic .. 5 E-102, 6 the spinning "?"
S.SUPER_SLOT = 6
-- the game's slot -> G-SA1's list entry (sh_config.lua GSA1.CHARACTERS)
S.SLOT_ENTRY = { [0] = "sonic", [1] = "tails", [2] = "knuckles", [3] = "amy", [4] = "big", [5] = "gamma", [6] = "supersonic" }
-- (Dr. Eggman and Tikal are not on the game's ring: S.SlotOf gives them Sonic's slot)
S.ENTRY_SLOT = { sonic = 0, tails = 1, knuckles = 2, amy = 3, big = 4, gamma = 5, supersonic = 6, supersonic_general = 6, question = 6, metalsonic = 0 }
-- 0.9.9f (the owner, rounds plan 14.1bd: "you hover over Sonic and press UP on the D-pad"): the skins of a slot; a later skin is one more name and Up cycles through them
S.SLOT_SKINS = { [0] = { "metalsonic" } }
-- 0.9.9e (the owner, rounds plan 14.1bc: "When you use the Adventure character select, Super Sonic (Vs. Perfect Chaos) should always be the choice"): slot 6 always plays him, the "?" locked or not.
-- gsa1_charselect_super, its one-time move and its combo box are gone; a value saved in them is ignored
S.SUPER_ENTRY = "supersonic"
-- the game's own sphere colours (FF0000FF, the selected one FFFF0000)
S.SPHERE = { 0, 0, 255 }
S.SPHERE_SELECTED = { 255, 0, 0 }
S.MUSIC = 24                    -- "Choose Your Buddy!" (the game's BGM 24: charsel098 3.3)
-- the XInput bits of GSA1.pad.raw (src/core/pad.hpp)
S.PAD_UP, S.PAD_DOWN, S.PAD_LEFT, S.PAD_RIGHT = 0x0001, 0x0002, 0x0004, 0x0008
S.PAD_START, S.PAD_BACK, S.PAD_A, S.PAD_B = 0x0010, 0x0020, 0x1000, 0x2000
S.RUN_FRAMES = 21               -- frames between the presses of a run: the ring's slide (charsel098 6.3)
S.STICK = 0.5                   -- Design S: how far the stick counts as a press

-- the list entry of a slot (nil: no such slot)
function S.EntryOf(slot)
    return S.SLOT_ENTRY[slot]
end

-- the slot of a list entry (the current character -> the first selection; an unknown name: Sonic's)
function S.SlotOf(name)
    return S.ENTRY_SLOT[name] or 0
end

-- from slot `from` to slot `to` on a ring of n: direction (-1 left, +1 right, 0 there already) and the presses. RIGHT is the
-- next slot. A tie goes right.
function S.ShortestRun(from, to, n)
    local right = (to - from) % n
    if right == 0 then return 0, 0 end
    local left = n - right
    if right <= left then return 1, right end
    return -1, left
end

-- the k-th sphere draw of a frame (k from 0) is this slot (the game's 8C9038E0 starts at the selected one)
function S.SphereSlot(slot, k, n)
    return (slot + k) % n
end

-- the game's 640 x 480 screen on W x H. Default: s = min(W / 640, H / 480), the 4:3 box centred; wide (gsa1_charselect_wide 1):
-- stretched to the whole screen. Host presentation only.
function S.Layout(W, H, wide, out)
    local m = out or {}
    m.W, m.H = W, H
    if wide then
        m.sx, m.sy, m.ox, m.oy = W / 640, H / 480, 0, 0
        m.s = math.min(m.sx, m.sy)
    else
        local s = math.min(W / 640, H / 480)
        m.s, m.sx, m.sy = s, s, s
        m.ox, m.oy = (W - 640 * s) / 2, (H - 480 * s) / 2
    end
    return m
end

-- a vertex of the game's screen on yours: one at x <= 0 or x >= 640 goes to the screen's edge (the title and bottom bars reach
-- it, as on the Dreamcast); y keeps the box (the sky is drawn to the edges by S.SkyEdges' rule in the panel)
function S.PlaceX(m, x)
    if x <= 0 then return 0 end
    if x >= 640 then return m.W end
    return m.ox + x * m.sx
end
function S.PlaceY(m, y)
    return m.oy + y * m.sy
end

-- the draws of the bottom bar's "File 1 / Clear 0 %" (host presentation, gsa1_charselect_file 0 hides them; found by the
-- texture's name, which is meaningless here)
local HIDDEN_EXACT = { cs_sinkou_e = true, FS_FILE_e = true }
function S.HiddenTexture(name)
    if type(name) ~= "string" then return false end
    if HIDDEN_EXACT[name] then return true end
    return string.sub(name, 1, 11) == "fs_file_num" or string.sub(name, 1, 7) == "sinkou_"
end

-- Design S: the rectangle of button `slot` on W x H: seven in a row, centred
function S.ButtonRect(slot, W, H)
    local gap = math.floor(W / 64)
    local bw = math.floor(math.min((W - gap * (S.SLOTS + 1)) / S.SLOTS, H / 4))
    local bh = math.floor(bw * 1.25)
    local x0 = math.floor((W - (bw * S.SLOTS + gap * (S.SLOTS - 1))) / 2)
    return x0 + slot * (bw + gap), math.floor((H - bh) / 2), bw, bh
end

-- Design S: the button under a point, or nil
function S.ButtonAt(px, py, W, H)
    for slot = 0, S.SLOTS - 1 do
        local x, y, w, h = S.ButtonRect(slot, W, H)
        if px >= x and px < x + w and py >= y and py < y + h then return slot end
    end
    return nil
end
