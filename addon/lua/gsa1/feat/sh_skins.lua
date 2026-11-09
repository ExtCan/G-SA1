-- G-SA1 skins (round 0.9.9f; the owner, sadc docs/research/gsa1_rounds_plan.md 14.1bd; sadc docs/research/metal099e.md 4.2): the pure part, both realms, no engine call, so the tests run it as it is.
-- One data entry names the whole character: the base (whose world and code he runs), where the model and its textures are on YOUR disc, which of the base's rows draw another row's motion, and the voice.
-- Nothing of the game's is here: numbers and addresses only, the bytes are read from the owner's disc at run time.
-- 1.0.0 (sadc docs/research/gsa1_100_select.md 4.1, 4.2 with RX.4; the owner, rounds plan 14.1bj): THE REGISTRY. K.Register(id, entry) is the only place a skin is named: it makes the entry's GSA1.CHARACTERS row (before
-- the "?", which stays last) and its aliases, and every other file asks the registry (K.ForCharacter, K.Of, K.BaseOf). The entry carries the owner's skin.ini keys BY THEIR OWN NAMES (skin_for, char_name, char_color,
-- auto_generate_name, name_tex_location, char_nameplate, auto_generate_nameplate, nameplate_tex_location, use_life_icon, life_icon_location, upgrade_model_compatibility), so 1.1's loader only fills the same table
-- from a file. What 1.1's loader must know (select 4.1): lines are key=value; "##" starts a comment; a line with no "=" is prose and ignored; "[skin folder]" is garrysmod/data/gsa1/skins/<base>/<id>/; true / false;
-- char_color is 6 hex digits without "#"; the ini is never rewritten (HUD/generated.txt lists what G-SA1 made: feat/sh_skinhud.lua). The parser is not built in 1.0.0.
GSA1 = GSA1 or {}
local K = GSA1.Skins or {}
GSA1.Skins = K

K.SKINS = K.SKINS or {}           -- [id] = entry
K.ORDER = K.ORDER or {}           -- ids, in registration order
-- skin.ini's skin_for -> the base entry's name (1.1's loader; the owner's list, 14.1bj, with Amy)
K.INI_BASE = { sonic = "sonic", miles = "tails", tails = "tails", knuckles = "knuckles", amy = "amy", big = "big", gamma = "gamma", eggman = "eggman", tikal = "tikal" }
-- upgrade_model_compatibility -> the support ball (feat/cl_charselect_bar.lua)
K.COMPAT = { full = true, partial = true, none = true }
K.TURNS = { ["-z"] = 1, none = 0 }
K.why = K.why or {}               -- [id] = why K.Register refused it (the log of the client reads it)

local function hex_rgb(s)
    s = tostring(s or "")
    if not string.match(s, "^%x%x%x%x%x%x$") then return nil end
    return tonumber(string.sub(s, 1, 2), 16), tonumber(string.sub(s, 3, 4), 16), tonumber(string.sub(s, 5, 6), 16)
end
K.HexRGB = hex_rgb

-- the base entry of a skin_for value (an entry name, or the ini's Sonic / Miles / ...); nil: none
function K.BaseEntry(skin_for)
    local n = string.lower(tostring(skin_for or ""))
    n = K.INI_BASE[n] or n
    for _, c in ipairs(GSA1.CHARACTERS or {}) do
        if c.name == n and not c.form then return c end
    end
    return nil
end

-- THE REGISTRY. true, or false and why (also kept in K.why[id])
function K.Register(id, e)
    local function no(why)
        K.why[tostring(id)] = why
        return false, why
    end
    if type(id) ~= "string" or not string.match(id, "^[a-z][a-z0-9_]*$") then return no("a skin's id is lower case letters, digits and _") end
    if type(e) ~= "table" then return no(id .. ": no entry") end
    local base = K.BaseEntry(e.skin_for)
    if not base then return no(id .. ": skin_for " .. tostring(e.skin_for) .. " is no character") end
    -- 1.0.0: libsa1 wears a skin over kind 0 only (sa1_skin_desc.base_kind 0; select 4.3.1); 1.1's custom models of other characters need a skeleton map per base
    if base.kind ~= 0 then return no(id .. ": 1.0.0 dresses Sonic only, not " .. tostring(base.title)) end
    if e.upgrade_model_compatibility ~= nil and not K.COMPAT[e.upgrade_model_compatibility] then return no(id .. ": upgrade_model_compatibility is full, partial or none") end
    if e.char_color ~= nil and not hex_rgb(e.char_color) then return no(id .. ": char_color is 6 hex digits") end
    e.id, e.base, e.base_kind = id, base.name, base.kind
    e.title = e.title or e.char_name or id
    e.char_name = e.char_name or e.title
    e.char_nameplate = e.char_nameplate or e.char_name
    e.upgrade_model_compatibility = e.upgrade_model_compatibility or "none"
    if e.auto_generate_name == nil then e.auto_generate_name = true end
    if e.auto_generate_nameplate == nil then e.auto_generate_nameplate = true end
    e.name_tex_location = e.name_tex_location or "[skin folder]/HUD/name.png"
    e.nameplate_tex_location = e.nameplate_tex_location or "[skin folder]/HUD/nameplate.png"
    if e.use_life_icon == nil then e.use_life_icon = false end
    if not K.SKINS[id] then K.ORDER[#K.ORDER + 1] = id end
    K.SKINS[id] = e
    K.why[id] = nil
    -- its row of GSA1.CHARACTERS (replaced on a reload of this file), before the "?" (pinned by three tests: metal099e.md RM.15)
    local list = GSA1.CHARACTERS or {}
    GSA1.CHARACTERS = list
    local row = { kind = base.kind, name = id, title = e.title, form = "skin", skin = id }
    local at, q
    for i, c in ipairs(list) do
        if c.name == id then at = i end
        if c.name == "question" then q = q or i end
    end
    if at then
        list[at] = row
    else
        table.insert(list, q or (#list + 1), row)
    end
    GSA1.CHARACTER_ALIASES = GSA1.CHARACTER_ALIASES or {}
    for _, a in ipairs(e.aliases or {}) do GSA1.CHARACTER_ALIASES[a] = id end
    return true
end

-- the skin of a list entry (GSA1.CHARACTERS: form "skin"); nil: none
function K.Of(def)
    if type(def) ~= "table" or def.form ~= "skin" then return nil end
    return K.SKINS[def.skin or def.name]
end

-- the base entry's name of an entry name (a skin's base; a character's own name; nil: none)
function K.BaseOf(name)
    local e = K.SKINS[name]
    if e then return e.base end
    return name
end

-- { base, its skins in registration order }: Sonic gives { "sonic", "metalsonic", "mechasonic" }. A skin's name gives its base's list
function K.ForCharacter(name)
    local base = K.BaseOf(name)
    local out = { base }
    for _, id in ipairs(K.ORDER) do
        local e = K.SKINS[id]
        if e and e.base == base then out[#out + 1] = id end
    end
    return out
end

-- the place of a name in its base's list (1 = the character itself), and the list's length
function K.IndexOf(name)
    local list = K.ForCharacter(name)
    for i, n in ipairs(list) do
        if n == name then return i, #list end
    end
    return 1, #list
end

-- the skin's name colour, 0..255 (nil: none)
function K.ColorOf(e)
    return hex_rgb(e and e.char_color)
end

-- the skin's folder (14.1bg): garrysmod/data/gsa1/skins/<base>/<id> (a DATA path)
function K.Folder(e)
    return "gsa1/skins/" .. tostring(e.base) .. "/" .. tostring(e.id)
end

-- an ini location with "[skin folder]" put in (a DATA path); nil: no location
function K.Location(e, loc)
    if type(loc) ~= "string" or loc == "" then return nil end
    local s = string.gsub(loc, "%[skin folder%]", function() return K.Folder(e) end)
    s = string.gsub(s, "\\", "/")
    if string.find(s, "..", 1, true) or string.sub(s, 1, 1) == "/" or string.find(s, ":", 1, true) then return nil end
    return s
end

-- an array of numbers from a table keyed by row, in a fixed order
local function pairs_of(t)
    local rows, out = {}, {}
    for from in pairs(t or {}) do rows[#rows + 1] = from end
    table.sort(rows)
    for _, from in ipairs(rows) do
        out[#out + 1] = from
        out[#out + 1] = t[from]
    end
    return out
end

-- the flat table the module's extras.skin and gsa1.FrontendSkin read (src/module/skin_args.hpp). 1.0.0: id, base_kind and the trail's colour (libsa1 sa1_skin_desc's new fields; zero: none)
function K.DescOf(skin)
    local parts = {}
    for _, p in ipairs(skin.rig.parts) do
        for i = 1, 4 do parts[#parts + 1] = p[i] end
    end
    local trail = skin.trail and skin.trail.color
    return {
        model_file = skin.model.file, model_sha1 = skin.model.sha1, model_load = skin.model.load, model_first = skin.model.first, model_end = skin.model.last,
        model_root = skin.model.root, tex_file = skin.textures.file, tex_sha1 = skin.textures.sha1, keep = skin.textures.keep, scale = skin.rig.scale, lift = skin.lift or 0,
        turn = K.TURNS[skin.rig.turn or "none"] or 0, ball_texture = skin.rig.ball_texture or -1, parts = parts, anim = pairs_of(skin.anim), anim_walk = pairs_of(skin.anim_walk),
        anim_fast = pairs_of(skin.anim_fast), fast_on = skin.fast_on or 0, fast_off = skin.fast_off or 0,
        glow_r = skin.glow and skin.glow.color[1] or 0, glow_g = skin.glow and skin.glow.color[2] or 0, glow_b = skin.glow and skin.glow.color[3] or 0, glow_inflate = skin.glow and skin.glow.inflate or 0,
        id = skin.id, base_kind = skin.base_kind or 0,
        trail_r = trail and trail[1] or 0, trail_g = trail and trail[2] or 0, trail_b = trail and trail[3] or 0,
    }
end

-- the create extras (cl_character.lua's seam GSA1.CreateExtras). nil without the module's flag: cl_character.lua refuses then, by name: never a plain Sonic
function K.ExtrasFor(skin, super)
    if type(super) ~= "table" or not super.CREATE_SKIN then return nil end
    return { create_flags = super.CREATE_SKIN, skin = K.DescOf(skin) }
end
-- THE SKINS ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- rig.parts: [figure node, from 0, depth first] = { Sonic's joint, Sonic's mesh node, the figure's bone end or -1, Sonic's bone end or -1 } (metal099e.md section 2, 3.2 with its review's RM.3: both columns).
-- options: the prefix of its ConVars gsa1_<options>_<key> (feat/cl_skins.lua), with these defaults; option_keys: which of K.OPTIONS (fly, walk_fly, voice, glow, trail; 1.0.0-beta1a plant, jog_pace) the skin has (1.0.0,
-- gsa1_100_master.md 3's R1 delta with RY.1: the ConVars are made by a loop, so a skin without a fly has no fly key and no fly box). anim_always: its anim rows are always on (no fly box to turn them)
K.Register("metalsonic", {
    skin_for = "sonic", char_name = "Metal Sonic", char_color = "3900b5",                  -- the owner's own example values (owner_mockups/skin.ini)
    auto_generate_name = true, name_tex_location = "[skin folder]/HUD/name.png",
    char_nameplate = "Metal Sonic", auto_generate_nameplate = true, nameplate_tex_location = "[skin folder]/HUD/nameplate.png",
    use_life_icon = false, life_icon_location = nil,                                        -- 1.1; 1.0.0 draws the base's icon
    upgrade_model_compatibility = "none",                                                   -- his parts replace Sonic's body: neither shoes nor ring ever draw on him (select 3.3)
    source = "disc",
    model = { file = "ADV02.PRS", sha1 = "ab5f600e707681f538794520c296c4fefe84659c", load = 0x0C900000,
              first = 0x0CA8B9CC, last = 0x0CA92EB8, root = 0x0CA92E84 },
    textures = { file = "ADV_MR03.PRS", sha1 = "cca1620491391e3d6e44d83be478d0687d5fa14f",
                 keep = { 76, 77, 97, 98, 99, 100, 101, 102, 103 } },
    rig = { scale = 0.70, turn = "-z", ball_texture = 101,
            parts = {
                { 1, 10, -1, -1 }, { 12, 22, -1, -1 }, { 12, 22, -1, -1 },                                                              -- torso, head, face
                { 25, 34, -1, -1 }, { 25, 34, 5, 27 }, { 27, 29, 6, 30 }, { 30, 30, -1, -1 }, { 30, 30, -1, -1 }, { 30, 30, -1, -1 },   -- the right arm
                { 36, 45, -1, -1 }, { 36, 45, 11, 38 }, { 38, 40, 12, 41 }, { 41, 41, -1, -1 }, { 41, 41, -1, -1 }, { 41, 41, -1, -1 }, -- the left arm
                { 47, 55, 16, 49 }, { 49, 51, 18, 52 }, { 49, 51, -1, -1 }, { 52, 52, -1, -1 }, { 52, 52, -1, -1 },                     -- the right leg
                { 57, 65, 21, 59 }, { 59, 61, 23, 62 }, { 59, 61, -1, -1 }, { 62, 62, -1, -1 }, { 62, 62, -1, -1 },                     -- the left leg
            } },
    anim = { [10] = 132, [11] = 133, [12] = 134, [13] = 134 }, anim_walk = { [9] = 131 }, lift = 1.0,   -- Sonic's row -> the row drawn: Super Sonic's flying; the walk behind gsa1_metal_walk_fly
    -- the way between a walk and a run: row 9 flies while he moves faster than a held walk can (MEASURED: a stick up to 0.8 holds at most 0.205; from 0.85 he only passes through on the way to row 10)
    anim_fast = { [9] = 132 }, fast_on = 0.25, fast_off = 0.215,
    -- the Light Speed glow: the parts again, three shells offset along their normals up to `inflate` SA1 units, in this colour, where the game draws Sonic's aura
    glow = { color = { 0.55, 0.10, 1.00 }, inflate = 0.30 },
    trail = { color = { 0.55, 0.10, 1.00 } },              -- 1.0.0 (the owner, 14.1bi: "His trails are still blue"): the Light Speed sparkles and streaks in his glow's colour
    voice = false,                                          -- voiceless (gsa1_metal_voice gives him Sonic's)
    options = "metal", defaults = { fly = 1, walk_fly = 0, voice = 0, glow = 1, trail = 1 },
    option_keys = { "fly", "walk_fly", "voice", "glow", "trail" },
    title = "Metal Sonic", aliases = { "metal", "metal_sonic" },
})

-- 1.0.0 (the owner, 14.1bf: "The Mecha Sonic should be in 1.0.0 as a skin for Sonic", an orange glow). The second robot of Metal Sonic's room on the disc (select 4.2; MEASURED by the prep lane, sadc
-- build/staging/upgdisp/LANDING.md B, D: 20 parts, 819 triangles, its feet on the ground at scale 0.52). THE OWNER'S ANSWER 17 (rounds plan 14.1bl, confirmed in 14.1bm): "He's a heavier robot
-- canonically, so he runs instead of flies. He never uses the arms behind back run animation though, he uses the Jog." So he is on his feet with no fly and no fly box: Sonic's own rows, Sonic's
-- jog (row 11) where Sonic runs with his arms behind him (rows 12 and 13, MEASURED: select 4.2.1), lift 0; his name stays orange. libsa1 poses a drawn row of Sonic's own tree by Sonic's own
-- mesh nodes, steps it as the game steps the jog at that speed but never faster than Sonic's own fastest jog, and stands his lowest point on the floor (1.0.0-beta1a; sa1_skin.c). The scale and
-- the lift are here and nowhere else
K.Register("mechasonic", {
    skin_for = "sonic", char_name = "Mecha Sonic", char_color = "ff8a1c",
    auto_generate_name = true, name_tex_location = "[skin folder]/HUD/name.png",
    char_nameplate = "Mecha Sonic", auto_generate_nameplate = true, nameplate_tex_location = "[skin folder]/HUD/nameplate.png",
    use_life_icon = false, life_icon_location = nil,
    upgrade_model_compatibility = "none",
    source = "disc",
    model = { file = "ADV02.PRS", sha1 = "ab5f600e707681f538794520c296c4fefe84659c", load = 0x0C900000,
              first = 0x0CA824C0, last = 0x0CA88AF8, root = 0x0CA88AC4 },
    textures = { file = "ADV_MR03.PRS", sha1 = "cca1620491391e3d6e44d83be478d0687d5fa14f",
                 keep = { 7, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96 } },
    rig = { scale = 0.52, turn = "-z", ball_texture = 86,                                       -- 86: the silver mrd_064s_msa
            parts = {
                { 1, 10, -1, -1 }, { 12, 22, -1, -1 }, { 12, 22, -1, -1 }, { 1, 10, -1, -1 },                       -- torso, head and quills, visor, piece under the torso
                { 47, 55, 5, 49 }, { 49, 51, 6, 52 }, { 52, 52, -1, -1 }, { 52, 52, -1, -1 }, { 52, 52, -1, -1 },     -- right thigh, shin, shoe, shoe front, heel wheel
                { 25, 34, 10, 27 }, { 27, 29, 11, 30 }, { 30, 30, -1, -1 },                                         -- right upper arm, forearm, fist
                { 57, 65, 13, 59 }, { 59, 61, 14, 62 }, { 62, 62, -1, -1 }, { 62, 62, -1, -1 }, { 62, 62, -1, -1 },     -- the left leg
                { 36, 45, 18, 38 }, { 38, 40, 19, 41 }, { 41, 41, -1, -1 },                                         -- the left arm
            } },
    -- the jog where Sonic runs with his arms behind him; no walk or fast rows (no flight to fade into); every field K.DescOf reads written ([RX.4])
    anim = { [12] = 11, [13] = 11 }, anim_walk = {}, anim_fast = {}, fast_on = 0, fast_off = 0, lift = 0,
    anim_always = true,                                     -- the rows are always on (libsa1 SA1_SKIN_ANIM_FLY: feat/cl_skins.lua K.AnimValue), never by a box
    glow = { color = { 1.00, 0.45, 0.05 }, inflate = 0.35 },
    trail = { color = { 1.00, 0.45, 0.05 } },
    voice = false,
    -- 1.0.0-beta1a (lane b1a-mecha; the owner: "Mecha Sonic is floating ... his run animation has stuttering and it animates far too fast"): the step that keeps his feet on the floor (libsa1 D9,
    -- now on the floor itself, slopes too, in every 60 Hz frame: since the lane's fix run libsa1's render calls sa1k_frame for the frames between two pairs) and his jog's pace (D10: never faster
    -- than Sonic's own jog at its fastest, 1 = that pace) are options of their own (feat/cl_skins.lua K.OPTIONS)
    options = "mecha", defaults = { voice = 0, glow = 1, trail = 1, plant = 1, jog_pace = 1 },
    option_keys = { "voice", "glow", "trail", "plant", "jog_pace" }, -- no fly, no walk_fly: gsa1_mecha_fly and gsa1_mecha_walk_fly are never made
    title = "Mecha Sonic", aliases = { "mecha", "mecha_sonic" },
})
