-- G-SA1 upgrade models, the pure part (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 3.2, 4.6 with RX.1; the owner, rounds plan 14.1bj and its answers): both realms, no engine call, so the tests run it as it is.
-- The owner's two switches: ACTIVE is the ability, exactly today's gsa1_upgrade_<name> (the game's own event flag, set before the world's first step); VISIBLE only decides which of two models the game's own
-- drawing code picks, at the line where it picks (libsa1 game option 5, SA1_GOPT_UPGRADE_MODELS: a display set read by nine SA1_GA blocks; never written to playerwk.equipment). So hiding the shoes keeps the
-- Light Speed Dash and showing them does not give it. The model ConVar gsa1_upgrade_model_<name>: 0 "with the upgrade" (the game; the default, so a person who never opens the panel keeps today's look),
-- 1 "always shown", 2 "never shown". The four states of the A cycle on the two ConVars (select 4.6):
--   on     = active and visible      (1, 0)        hidden = active and invisible   (1, 2)
--   shown  = inactive but visible    (0, 1)        off    = disabled entirely      (0, 0)  (what L sets; R sets "on")
GSA1 = GSA1 or {}
local U = GSA1.UpgradeModels or {}
GSA1.UpgradeModels = U

-- the equipment bits of each upgrade's model (libsa1 SA1_UPGRADE_*, gsa1_091b_upgrades.md 5.2; sadc build/staging/upgdisp/LANDING.md A4): the value of game option 5 is ON | the bits drawn
U.BITS = {
    crystal_ring = 0x1, light_speed_shoes = 0x2, ancient_light = 0x4, jet_anklet = 0x8, rhythm_badge = 0x10, fighting_gloves = 0x20, shovel_claw = 0x40, long_hammer = 0x80,
    warrior_feather = 0x100, laser_blaster = 0x200, jet_booster = 0x400, power_rod = 0x800, life_belt = 0x1000,
    lure_1 = 0x10000, lure_2 = 0x20000, lure_3 = 0x40000, lure_4 = 0x80000,
}
U.ON = 0x80000000           -- SA1_UPGRADE_MODELS_ON
U.ALL = 0xF1FFF             -- SA1_UPGRADE_MODELS_ALL
-- the owner's answer 16 ("Default", rounds plan 14.1bl; select 4.0 D-2): Ancient Light has no model in the game, so only Active / Inactive, its VISIBLE always greyed, and no model ConVar
U.NO_MODEL = { ancient_light = true }

-- THE NAMES' COLOURS, the one place to change them (gsa1_100_select.md 4.6.1; sadc tools/research/upgrade_colours.py --check compares this table with the owner's disc). The owner's answer 18
-- (rounds plan 14.1bl): "the name should be main color of the upgrade unless it doesn't have a color in which case it should default to the character's main color" ("the green hammer should have a
-- green name": the Long Hammer). So each name is its own model's main colour, MEASURED on the disc (what the upgrade adds over the plain part it replaces; select 4.6.1's method), and false means none of
-- its own: the character's colour, resolved at draw time (U.NameHex). The owner's answers 22 ("Other ways. The silver names work better.") and 29 ("The light speed shoes should be yellow. Tails' Jet
-- Anklet should be silver.", rounds plan 14.1bn) chose four of them: the Light Speed Shoes the yellow of the owner's mockup F4FF00 (measured EEB71A, their gold gem), the Jet Anklet (measured 53617B),
-- the Shovel Claw and the Laser Blaster (no colour of their own) silver C0C0C0: the owner's choices, not measures. Ancient Light has no model: false (Sonic's blue, Super Sonic's yellow, the skin's own)
U.COLORS = {
    light_speed_shoes = "F4FF00",       -- the owner's (answer 29)
    crystal_ring = "0CC1A6",
    ancient_light = false,              -- no model: the character's (answer 18; answer 22's reading)
    jet_anklet = "C0C0C0",              -- the owner's (answer 29)
    rhythm_badge = "5C4CB6",
    shovel_claw = "C0C0C0",             -- the owner's (answer 22)
    fighting_gloves = "ECBC10",
    warrior_feather = "5D87B6",
    long_hammer = "0ADF05",             -- the green hammer (answer 18)
    jet_booster = "C00202",
    laser_blaster = "C0C0C0",           -- the owner's (answer 22)
    life_belt = "018601",
    power_rod = "ACD700",
    lure_1 = "D92D99", lure_2 = "4E5EF2", lure_3 = "4F6080", lure_4 = "CE8511",
}
-- the characters' main colours: the fill of each one's own pulsing name on Character Select (M_CHNAM.PRS's m_<name>, MEASURED select 4.6.1), by the screen's slot (S.SLOT_ENTRY: Sonic, Tails,
-- Knuckles, Amy, Big, E-102, Super Sonic) and by the character's kind (where no slot is known)
U.SLOT_COLOR = { [0] = "0053FA", [1] = "F6C400", [2] = "F41000", [3] = "F985B7", [4] = "7331C7", [5] = "868686", [6] = "F1F100" }
U.KIND_COLOR = { [0] = "0053FA", [2] = "F6C400", [3] = "F41000", [5] = "F985B7", [6] = "868686", [7] = "7331C7", [8] = "F1F100" }

-- an upgrade's name colour, "RRGGBB": its own (U.COLORS), else (false: none of its own) the shown skin's char_color (Metal Sonic 3900B5, Mecha Sonic FF8A1C), else the slot's character's (slot 6:
-- Super Sonic's yellow), else its own character's; never white
function U.NameHex(name, slot, skin)
    local c = U.COLORS[name]
    if type(c) == "string" and U.RGB(c) then return string.upper(c) end
    if type(skin) == "table" and U.RGB(skin.char_color) then return string.upper(skin.char_color) end
    if slot ~= nil and U.SLOT_COLOR[slot] then return U.SLOT_COLOR[slot] end
    for _, u in ipairs(GSA1.UPGRADES or {}) do
        if u.name == name and U.KIND_COLOR[u.kind] then return U.KIND_COLOR[u.kind] end
    end
    return U.KIND_COLOR[0]
end
-- what stays different, said under the combo boxes (select 3.2)
U.NOTES = {
    long_hammer = "Hidden, Amy swings the normal hammer but reaches as far as the long one; shown without it, the long hammer reaches as the normal one.",
    laser_blaster = "The shots start where the real part is, a few units from the drawn one.",
    power_rod = "The line starts where the real rod is.",
    light_speed_shoes = "Hidden, the charge's sparkles still come (they belong to the ability).",
    jet_booster = "Shown without the ability, the booster is drawn but never its flame.",
    life_belt = "Shown without the ability, the belt is drawn and never inflates.",
    ancient_light = "It has no model in the game: only active or inactive.",
}

U.STATES = { "on", "hidden", "shown", "off" }                 -- the owner's A order (14.1bj)
U.STATE = {
    on = { active = true, visible = true, cv = { 1, 0 } },
    hidden = { active = true, visible = false, cv = { 1, 2 } },
    shown = { active = false, visible = true, cv = { 0, 1 } },
    off = { active = false, visible = false, cv = { 0, 0 } },
}

-- the model is drawn: always shown, or "with the upgrade" and active
function U.Visible(active, model)
    model = tonumber(model) or 0
    return model == 1 or (model == 0 and active == true)
end

-- the state of the two ConVars' values (active: boolean; model 0..2)
function U.StateOf(active, model, name)
    if name and U.NO_MODEL[name] then return active and "on" or "off" end
    local v = U.Visible(active, model)
    if active then return v and "on" or "hidden" end
    return v and "shown" or "off"
end

-- the next state on A (an upgrade without a model: on <-> off)
function U.Next(state, name)
    if name and U.NO_MODEL[name] then return state == "on" and "off" or "on" end
    for i, s in ipairs(U.STATES) do
        if s == state then return U.STATES[i % #U.STATES + 1] end
    end
    return "on"
end

-- the two ConVar values of a state: active 0 / 1, model 0 / 1 / 2
function U.ConVarsOf(state)
    local s = U.STATE[state] or U.STATE.off
    return s.cv[1], s.cv[2]
end

-- the upgrades a slot's list shows (question 15's default: only the character's own). kind: the character's kind (Super Sonic's 8 shows Sonic's: GSA1.UpgradeKind)
function U.ListFor(kind)
    if kind == nil or not GSA1.UpgradesOf then return {} end
    local uk = GSA1.UpgradeKind and GSA1.UpgradeKind(kind) or kind
    return GSA1.UpgradesOf(uk)
end

-- the bits of a kind's upgrades marked VISIBLE, and whether any of them is drawn otherwise than its ability says. get(name) -> active (boolean), model (0..2)
local function visible_bits(kind, get)
    local bits, differs = 0, false
    for _, u in ipairs(U.ListFor(kind)) do
        local b = U.BITS[u.name]
        if b and not U.NO_MODEL[u.name] then
            local active, model = get(u.name)
            local v = U.Visible(active, model)
            if v ~= (active == true) then differs = true end
            if v then bits = bit.bor(bits, b) end
        end
    end
    return bits, differs
end

-- the game option of a kind: 0 (the game) while every upgrade of it is drawn exactly as its ability says, else ON | the bits drawn. get(name) -> active (boolean), model (0..2)
function U.OptionValue(kind, get)
    local bits, differs = visible_bits(kind, get)
    if not differs then return 0 end
    -- (as an unsigned number: the module takes it whole)
    return U.ON + bit.band(bits, U.ALL)
end

-- the same for the 3D character in Character Select's circle (r1-verify-s): the menu's characters hold no upgrade there (no event flag in the menu's world, select 4.3.3), so "the game" (0)
-- would draw the plain parts whatever VISIBLE says. The circle gets ON | the bits marked VISIBLE, and 0 only when none is, so it shows exactly what the panel says
function U.FrontendValue(kind, get)
    local bits = visible_bits(kind, get)
    if bits == 0 then return 0 end
    return U.ON + bit.band(bits, U.ALL)
end

-- the layout of the panel, in game px (the owner's 10.webp, MEASURED: select 4.6)
U.LAYOUT = {
    band_h = 324, band_solid = 210, band_fade = 400, from = { 32, 122, 1 }, to = { 189, 246, 4 }, to_x = 200,
    title_x = 19, title_y = 42, title_h = 23,
    pitch = 77.25, status_y = 88.5, status_h = 19, name_y = 112, name_h = 24.5, x = 19, room = 236,
    white = { 252, 251, 252 }, grey = { 136, 136, 136 },
    slide = 0.25, fade = 0.2, fade_at = 0.1, fade_each = 0.04, close = 0.15,
}
-- the pitch and the rows' scale for n rows: never larger than the mockup's own, smaller to fit 236 game px
function U.Layout(n)
    local L = U.LAYOUT
    n = math.max(1, tonumber(n) or 1)
    local pitch = math.min(L.pitch, L.room / n)
    return pitch, pitch / L.pitch
end

-- the band's colour and alpha at game x (the gradient: green to yellow over 0..200, solid to 210, faded out by 400)
function U.BandAt(x)
    local L = U.LAYOUT
    local t = math.max(0, math.min(1, x / L.to_x))
    local r = L.from[1] + (L.to[1] - L.from[1]) * t
    local g = L.from[2] + (L.to[2] - L.from[2]) * t
    local b = L.from[3] + (L.to[3] - L.from[3]) * t
    local a = 1
    if x > L.band_solid then a = math.max(0, 1 - (x - L.band_solid) / (L.band_fade - L.band_solid)) end
    return r, g, b, a
end

-- the game's name pulse (READ code_8C9031C0.c:476): 0.1845 * (sin(ring) + 1) + 0.615, ring in BAMS; the rows scale by it over its mean 0.7995 (0.77 .. 1.23)
U.RING_STEP = 0x5B0          -- the game's ring += 0x5B0 per idle frame (:239)
function U.Pulse(ring)
    return 0.1845 * (math.sin((tonumber(ring) or 0) * math.pi * 2 / 65536) + 1) + 0.615
end
function U.PulseScale(ring)
    return U.Pulse(ring) / 0.7995
end

-- an "RRGGBB" as r, g, b (nil: not one)
function U.RGB(hex)
    hex = tostring(hex or "")
    if not string.match(hex, "^%x%x%x%x%x%x$") then return nil end
    return tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16)
end
