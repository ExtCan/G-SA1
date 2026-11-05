-- G-SA1 skins (round 0.9.9f; the owner, sadc docs/research/gsa1_rounds_plan.md 14.1bd; sadc docs/research/metal099e.md 4.2): the pure part, both realms, no engine call, so the tests run it as it is.
-- One data entry names the whole character: the base (whose world and code he runs), where the model and its textures are on YOUR disc, which of the base's rows draw another row's motion, and the voice.
-- Nothing of the game's is here: numbers and addresses only, the bytes are read from the owner's disc at run time. This is the simple template 2.0's mod support (14.1p) can start from; no file format, no mod
-- support is built now.
GSA1 = GSA1 or {}
local K = GSA1.Skins or {}
GSA1.Skins = K

-- [figure node] = { Sonic's joint, Sonic's mesh node, the figure's bone end or -1, Sonic's bone end or -1 } (metal099e.md section 2, 3.2 with its review's RM.3: both columns). Figure nodes count from 0, depth first
K.SKINS = {
    metalsonic = {
        base = "sonic",                                     -- the world: Sonic's kind and code
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
        voice = false,                                      -- voiceless (gsa1_metal_voice gives him Sonic's)
    },
}

K.TURNS = { ["-z"] = 1, none = 0 }

-- the skin of a list entry (GSA1.CHARACTERS: form "skin"); nil: none
function K.Of(def)
    if type(def) ~= "table" or def.form ~= "skin" then return nil end
    return K.SKINS[def.skin or def.name]
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

-- the flat table the module's extras.skin and gsa1.FrontendSkin read (src/module/skin_args.hpp)
function K.DescOf(skin)
    local parts = {}
    for _, p in ipairs(skin.rig.parts) do
        for i = 1, 4 do parts[#parts + 1] = p[i] end
    end
    return {
        model_file = skin.model.file, model_sha1 = skin.model.sha1, model_load = skin.model.load, model_first = skin.model.first, model_end = skin.model.last,
        model_root = skin.model.root, tex_file = skin.textures.file, tex_sha1 = skin.textures.sha1, keep = skin.textures.keep, scale = skin.rig.scale, lift = skin.lift or 0,
        turn = K.TURNS[skin.rig.turn or "none"] or 0, ball_texture = skin.rig.ball_texture or -1, parts = parts, anim = pairs_of(skin.anim), anim_walk = pairs_of(skin.anim_walk),
    }
end

-- the create extras (cl_character.lua's seam GSA1.CreateExtras). nil without the module's flag: cl_character.lua refuses then, by name: never a plain Sonic
function K.ExtrasFor(skin, super)
    if type(super) ~= "table" or not super.CREATE_SKIN then return nil end
    return { create_flags = super.CREATE_SKIN, skin = K.DescOf(skin) }
end
