-- feat_skins_test.lua - Metal Sonic, the addon's side (round 0.9.9f; sadc docs/research/metal099e.md 7, T1, T3, T4, T5, T6, T7, T8 with its review RM.5, RM.15). 1.0.0 (sadc docs/research/gsa1_100_select.md
-- 7.2 T1 with RX.4, RX.12): the registry K.Register, Mecha Sonic, the skin.ini's keys, no file naming metalsonic by hand. The whole addon through its autorun, tests/lua_mock.lua
-- in Garry's Mod's own LuaJIT, a mock of the module's "super" and front end.
--   lua_host tests/feat_skins_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_skins_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

local cookies = {}
cookie = { GetNumber = function(k, d) return tonumber(cookies[k]) or d end, Set = function(k, v) cookies[k] = v end, GetString = function(k, d) return cookies[k] or d end }

local G = M.module({ speed = 300, features = { super = 5, jukebox = 1, emote = 3, follower = 2, frontend = 1 } })
G.SUPER = G.SUPER or { KIND = 8, KIND_SONIC = 0, CREATE_QUESTION = 0x2000, ARCHIVE_QUESTION = 62, COPT_QUESTION_SPIN = 8, CREATE_WATER_FLOOR = 0x1000, NO_DRAIN = 1, KEEP_AT_ZERO = 2, START_RINGS = 50 }
G.SUPER.CREATE_SKIN, G.SUPER.ARCHIVE_SKIN, G.SUPER.COPT_SKIN_ANIM, G.SUPER.SKIN_ANIM_FLY, G.SUPER.SKIN_ANIM_WALK, G.SUPER.SKIN_ANIM_GLOW = 0x4000, 61, 9, 1, 2, 4
local creates, options, voiceless = {}, {}, {}
local create = G.Create
function G.Create(kind, pos, yaw, ups, rings, extras)
    creates[#creates + 1] = { kind = kind, extras = extras }
    return create(kind, pos, yaw, ups, rings, extras)
end
function G.SetCharOption(id, opt, v)
    options[#options + 1] = { id = id, opt = opt, v = v }
    return true
end
function G.SetVoiceless(id, on)
    voiceless[id] = on
    return true
end
local fe = { on = nil, calls = 0, refuse = nil, ticks = {} }
function G.FrontendSkin(desc, quiet)
    fe.calls = fe.calls + 1
    if fe.refuse and desc then return nil, fe.refuse, "not_loaded" end
    fe.on, fe.quiet = desc, quiet
    return true
end

local function load_addon()
    GSA1 = nil
    M.included = {}
    local ok, err = pcall(M.load, "autorun/gsa1_autorun.lua")
    local errs = GSA1 and GSA1.FeatureFileErrors or {}
    check(ok and #errs == 0, "the addon's client files load (%s)", tostring(err or errs[1] or "no error"))
    if not ok or #errs > 0 then return false end
    GSA1.LoadModule()
    GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
    GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }
    return true
end
if not load_addon() then return done() end

local function panel_rec()
    local P = { calls = {} }
    setmetatable(P, { __index = function(t, k)
        return function(self, ...)
            local a = { k, ... }
            t.calls[#t.calls + 1] = a
            if k == "ComboBox" then
                local combo = { items = {} }
                combo.AddChoice = function(s, title, data) s.items[#s.items + 1] = { title, data } end
                a.combo = combo
                return combo
            end
            return setmetatable({}, { __index = function() return function() end end })
        end
    end })
    return P
end
vgui.Create = function() return setmetatable({}, { __index = function() return function() end end }) end
local function page_text(P)
    local out = {}
    for _, c in ipairs(P.calls) do
        for i = 2, #c do if type(c[i]) == "string" then out[#out + 1] = c[i] end end
        if c.combo then for _, it in ipairs(c.combo.items) do out[#out + 1] = tostring(it[1]) .. "=" .. tostring(it[2]) end end
    end
    return table.concat(out, "\n")
end
local function character_page()
    M.menu = {}
    M.run_hook("PopulateToolMenu")
    for _, e in ipairs(M.menu) do
        if e.class == "gsa1_character" then
            local P = panel_rec()
            local ok, err = pcall(e.cpanel, P)
            check(ok, "the Character page builds (%s)", tostring(err))
            return P
        end
    end
    check(false, "the Character page is on the menu")
    return panel_rec()
end

-- ---- T1: the entry -----------------------------------------------------------------------------------------------------------------------------------------------------
do
    local desc = GSA1.Skins.DescOf(GSA1.Skins.SKINS.metalsonic)
    check(desc.glow_r == 0.55 and desc.glow_g == 0.10 and desc.glow_b == 1.00 and desc.glow_inflate == 0.30, "T1 the glow is the entry's data: colour and inflation in DescOf")
    check(desc.fast_on == 0.25 and desc.fast_off == 0.215 and desc.anim_fast[1] == 9 and desc.anim_fast[2] == 132, "T1 the way between a walk and a run is the entry's data")
end
local K, W, S, F = GSA1.Skins, GSA1.Wheel, GSA1.CharSelect, GSA1.Faces
local d = GSA1.CharacterByName("metalsonic")
check(d and d.kind == 0 and d.form == "skin" and d.title == "Metal Sonic" and not d.secret, "T1 the entry: kind 0, form skin, not secret")
check(GSA1.CharacterByName("metal") == d and GSA1.CharacterByName("metal_sonic") == d, "T1 the aliases find him")
check(GSA1.CharacterByKind(0).name == "sonic", "T1 CharacterByKind(0) stays Sonic")
check(K.Of(d) == K.SKINS.metalsonic and K.SKINS.metalsonic.base == "sonic" and GSA1.CharacterByName(K.SKINS.metalsonic.base).kind == d.kind, "T1 the base resolves to his kind")
local names = {}
for i, c in ipairs(GSA1.CHARACTERS) do names[c.name] = i end
check(#GSA1.CHARACTERS == 13 and names.metalsonic == names.supersonic_general + 1 and names.mechasonic == names.metalsonic + 1 and names.question == 13, "T1 K.Register: after supersonic_general, Metal then Mecha, ? still last, 13 rows (RM.15)")
check(S.SLOT_SKINS == nil and S.ENTRY_SLOT.metalsonic == nil and S.SlotOf("metalsonic") == 0 and S.SlotOf("mechasonic") == 0, "T1 S.SLOT_SKINS is gone; a skin takes its base's slot")
do
    local function same(a, b)
        if #a ~= #b then return false end
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return true
    end
    check(same(K.ForCharacter("sonic"), { "sonic", "metalsonic", "mechasonic" }) and same(K.ForCharacter("mechasonic"), { "sonic", "metalsonic", "mechasonic" }), "T1 K.ForCharacter(sonic) = { sonic, metalsonic, mechasonic }")
    check(same(K.ForCharacter("tails"), { "tails" }) and same(S.SlotNames(1), { "tails" }) and same(S.SlotNames(6), { "supersonic" }), "T1 Tails' is { tails }; the Super Sonic slot has no skins")
    local m = GSA1.CharacterByName("mechasonic")
    check(m and m.kind == 0 and m.form == "skin" and m.title == "Mecha Sonic" and GSA1.CharacterByName("mecha") == m and GSA1.CharacterByName("mecha_sonic") == m, "T1 Mecha Sonic: kind 0, form skin, his aliases")
    -- [14.1bl] the owner's answer 17 ("he runs instead of flies ... he uses the Jog"): Sonic's own rows, the jog (11) where Sonic runs with his arms behind him (12, 13); RX.4: every field
    -- K.DescOf reads is still written on his entry
    local me, dm = K.SKINS.mechasonic, K.DescOf(K.SKINS.mechasonic)
    local nanim = 0
    for _ in pairs(me.anim or {}) do nanim = nanim + 1 end
    check(nanim == 2 and me.anim[12] == 11 and me.anim[13] == 11 and type(me.anim_walk) == "table" and next(me.anim_walk) == nil and type(me.anim_fast) == "table" and next(me.anim_fast) == nil
        and me.fast_on == 0 and me.fast_off == 0 and me.lift == 0 and me.anim_always == true,
        "T1 [14.1bl] Mecha's entry: anim exactly { [12] = 11, [13] = 11 }, anim_walk and anim_fast empty, fast_on, fast_off and lift 0, anim_always true")
    check(dm.fast_on == 0 and dm.fast_off == 0 and dm.lift == 0 and #dm.anim == 4 and dm.anim[1] == 12 and dm.anim[2] == 11 and dm.anim[3] == 13 and dm.anim[4] == 11 and #dm.anim_walk == 0 and #dm.anim_fast == 0,
        "T1 RX.4: and DescOf sends them (anim 12, 11, 13, 11; no walk or fast rows; lift 0)")
    local function same_keys(a, b)
        if #a ~= #b then return false end
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return true
    end
    check(same_keys(me.option_keys or {}, { "voice", "glow", "trail", "plant", "jog_pace" }) and same_keys(K.SKINS.metalsonic.option_keys or {}, { "fly", "walk_fly", "voice", "glow", "trail" }),
        "T1 [14.1bl] [RY.1] option_keys: Mecha voice, glow, trail and (1.0.0-beta1a) plant, jog_pace; Metal his five")
    check(#dm.parts == 80 and #dm.keep == 22 and dm.turn == 1 and dm.ball_texture == 86 and dm.scale == 0.52 and dm.model_root == 0x0CA88AC4 and dm.model_first == 0x0CA824C0 and dm.model_end == 0x0CA88AF8,
        "T1 Mecha's numbers: 20 parts by four, 22 textures, -z, ball 86, scale 0.52 (the prep lane's), his root and bytes")
    check(dm.id == "mechasonic" and dm.base_kind == 0 and dm.trail_r == 1.00 and dm.trail_g == 0.45 and dm.trail_b == 0.05 and dm.glow_r == 1.00 and dm.glow_inflate == 0.35, "T1 DescOf carries id, base_kind 0, the trail's colour (1.0.0's sa1_skin_desc fields)")
    local dmeta = K.DescOf(K.SKINS.metalsonic)
    check(dmeta.id == "metalsonic" and dmeta.base_kind == 0 and dmeta.trail_r == 0.55 and dmeta.trail_b == 1.00, "T1 Metal's trail is his glow's purple")
    -- the owner's skin.ini keys, by their own names (14.1bj), on both
    local keys = { "skin_for", "char_name", "char_color", "auto_generate_name", "name_tex_location", "char_nameplate", "auto_generate_nameplate", "nameplate_tex_location", "use_life_icon", "upgrade_model_compatibility" }
    local missing = {}
    for _, id in ipairs({ "metalsonic", "mechasonic" }) do
        for _, k in ipairs(keys) do
            if K.SKINS[id][k] == nil then missing[#missing + 1] = id .. "." .. k end
        end
    end
    check(#missing == 0, "T1 the skin.ini's keys on both entries (%s)", table.concat(missing, ", "))
    check(K.SKINS.metalsonic.char_color == "3900b5" and K.SKINS.mechasonic.char_color == "ff8a1c" and K.SKINS.metalsonic.upgrade_model_compatibility == "none", "T1 the owner's example values: Metal 3900b5, Mecha ff8a1c, none")
    check(K.Location(me, me.name_tex_location) == "gsa1/skins/sonic/mechasonic/HUD/name.png" and K.Location(me, "../../x.png") == nil and K.Location(me, "C:/x.png") == nil, "T1 [skin folder] is garrysmod/data/gsa1/skins/<base>/<id>; no way out of it")
    -- the registry refuses what it cannot wear
    check(K.Register("Bad Id", { skin_for = "sonic" }) == false and K.Register("x", { skin_for = "nobody" }) == false and K.Register("tailsskin", { skin_for = "Miles" }) == false and K.Register("y", { skin_for = "sonic", char_color = "#123" }) == false,
        "T1 K.Register refuses a bad id, an unknown base, a base other than Sonic (1.0.0) and a bad colour")
    check(#GSA1.CHARACTERS == 13 and GSA1.CHARACTERS[13].name == "question", "T1 a refused entry adds no row")
    check(K.BaseEntry("Miles").name == "tails" and K.BaseEntry("Gamma").name == "gamma" and K.BaseEntry("Amy").name == "amy", "T1 1.1's ini names map to the bases (Amy included)")
end
-- RX.12: no file names metalsonic by hand any more: the registry's entry is the only place (the wheel's lines are r1-ev's files, changed last in the round)
do
    local found = {}
    for _, dir in ipairs({ "/gsa1", "/gsa1/feat", "/autorun", "/entities" }) do
        for _, f in ipairs(host_list(root .. dir, "*.lua")) do
            local src = host_read(root .. dir .. "/" .. f) or ""
            if string.find(src, "metalsonic", 1, true) and not (dir == "/gsa1/feat" and f == "sh_skins.lua") then found[#found + 1] = f end
        end
    end
    check(#found == 0, "T1 RX.12: no file names metalsonic by hand but the registry (%s)", table.concat(found, ", "))
end
check(W.UNPLAYABLE ~= nil, "T1 the wheel's rows are loaded")
do
    local src = host_read(root .. "/gsa1/feat/cl_wheel.lua")
    check(string.find(src, "(skin and W.UNPLAYABLE[skin.base])", 1, true) ~= nil, "T1 a skin's wheel page greys what its base's greys (RM.15; 1.0.0: by the registry)")
    local kf, form = W.KindForm("metalsonic")
    check(kf == 0 and form == 0, "T5 his wheel's rows are Sonic's: kind 0, form 0")
end
-- a page: the button (the owner: "a button in the Q menu")
do
    local text = page_text(character_page())
    check(string.find(text, "Metal Sonic", 1, true) ~= nil, "T1 the Quick spawn list on the Character page has him")
    check(string.find(text, "gsa1_metal_fly", 1, true) and string.find(text, "gsa1_metal_walk_fly", 1, true) and string.find(text, "gsa1_metal_voice", 1, true), "T7 his three options have controls on the page")
    check(string.find(text, "gsa1_charselect_skins", 1, true) ~= nil, "T7 gsa1_charselect_skins has a control on the page")
    check(string.find(text, "gsa1_metal_glow", 1, true) ~= nil, "T7 gsa1_metal_glow has a control on the page")
    local upgrades = 0
    for _ in string.gmatch(text, "gsa1_upgrade_light_speed_shoes") do upgrades = upgrades + 1 end
    check(upgrades <= 1, "T1 no extra upgrade block (%d)", upgrades)
end
-- [14.1bl] [RY.1, RY.13] at run time, in the suite's ConVar mock (the names are built with "..", so a grep proves nothing): Mecha's three options and no fly box; K.AnimValue gives him FLY always,
-- never WALK, GLOW and TRAIL by his own ConVars; Metal what 0.9.9g gives
do
    local made = {}
    for _, key in ipairs({ "fly", "walk_fly", "voice", "glow", "trail" }) do
        made[#made + 1] = key .. ":" .. (M.convars["gsa1_metal_" .. key] and "metal" or "-") .. "/" .. (M.convars["gsa1_mecha_" .. key] and "mecha" or "-")
    end
    check(M.convars.gsa1_mecha_fly == nil and M.convars.gsa1_mecha_walk_fly == nil and M.convars.gsa1_mecha_voice ~= nil and M.convars.gsa1_mecha_glow ~= nil and M.convars.gsa1_mecha_trail ~= nil
        and M.convars.gsa1_mecha_plant ~= nil and M.convars.gsa1_mecha_jog_pace ~= nil and M.convars.gsa1_metal_plant == nil and M.convars.gsa1_metal_jog_pace == nil
        and M.convars.gsa1_metal_fly ~= nil and M.convars.gsa1_metal_walk_fly ~= nil and M.convars.gsa1_metal_voice ~= nil and M.convars.gsa1_metal_glow ~= nil and M.convars.gsa1_metal_trail ~= nil,
        "T1 [14.1bl] the ConVars made: Metal's five, Mecha's voice, glow, trail, plant and jog_pace (1.0.0-beta1a); gsa1_mecha_fly, gsa1_mecha_walk_fly, gsa1_metal_plant, gsa1_metal_jog_pace never created (%s)", table.concat(made, " "))
    check(M.convars.gsa1_mecha_voice and M.convars.gsa1_mecha_voice:GetInt() == 0 and M.convars.gsa1_mecha_glow:GetInt() == 1 and M.convars.gsa1_mecha_trail:GetInt() == 1
        and M.convars.gsa1_mecha_plant and M.convars.gsa1_mecha_plant:GetInt() == 1 and M.convars.gsa1_mecha_jog_pace and M.convars.gsa1_mecha_jog_pace:GetFloat() == 1,
        "T1 [14.1bl] Mecha's defaults: voice 0, glow 1, trail 1; 1.0.0-beta1a: plant 1, jog_pace 1 (Sonic's own fastest jog)")
    local P = character_page()
    local boxes, slider = {}, nil
    for _, c in ipairs(P.calls) do
        if (c[1] == "CheckBox" or c[1] == "NumSlider") and type(c[3]) == "string" and string.sub(c[3], 1, 11) == "gsa1_mecha_" then boxes[#boxes + 1] = c[3] end
        if c[1] == "NumSlider" and c[3] == "gsa1_mecha_jog_pace" then slider = c end
    end
    check(#boxes == 5 and boxes[1] == "gsa1_mecha_voice" and boxes[2] == "gsa1_mecha_glow" and boxes[3] == "gsa1_mecha_trail" and boxes[4] == "gsa1_mecha_plant" and boxes[5] == "gsa1_mecha_jog_pace",
        "T1 [14.1bl] 1.0.0-beta1a: five controls under Mecha Sonic, no fly box (%s)", table.concat(boxes, ", "))
    check(slider and slider[2] == "Mecha Sonic: jog pace when running fast" and slider[4] == 0.5 and slider[5] == 2.5 and slider[6] == 2,
        "T1 1.0.0-beta1a: \"Mecha Sonic: jog pace when running fast\" is a slider 0.5 .. 2.5 (%s)", slider and tostring(slider[2]) or "none")
    local plant_box
    for _, c in ipairs(P.calls) do if c[1] == "CheckBox" and c[3] == "gsa1_mecha_plant" then plant_box = c[2] end end
    check(plant_box == "Mecha Sonic: keep his feet on the floor", "T1 1.0.0-beta1a: the box \"Mecha Sonic: keep his feet on the floor\" (%s)", tostring(plant_box))
    -- the lane's fix run (its verifier, LOW): the page's words say what is now true: no "nothing to choose, so no box" under his five controls, and the box's off text is the MEASURED one
    local stale, off_text = nil, nil
    for _, c in ipairs(P.calls) do
        if c[1] == "ControlHelp" and type(c[2]) == "string" then
            if string.find(c[2], "nothing to choose", 1, true) or string.find(c[2], "which floats", 1, true) then stale = c[2] end
            if string.find(c[2], "sink up to about 6 units into the floor", 1, true) then off_text = c[2] end
        end
    end
    check(stale == nil and off_text ~= nil, "T1 1.0.0-beta1a fix run: the Character page's help under Mecha Sonic says what is true (stale: %s; the off text: %s)", tostring(stale), tostring(off_text ~= nil))
    local sup = G.SUPER
    local had = sup.SKIN_ANIM_TRAIL
    sup.SKIN_ANIM_TRAIL = 8
    local mecha, metal = K.SKINS.mechasonic, K.SKINS.metalsonic
    local v = {}
    for _, f in ipairs({ "0", "1" }) do
        M.convars.gsa1_metal_fly:SetString(f)
        v[#v + 1] = K.AnimValue(mecha)
        v[#v + 1] = K.AnimValue(metal)
    end
    M.convars.gsa1_metal_walk_fly:SetString("1")
    local walk_m, walk_t = K.AnimValue(mecha), K.AnimValue(metal)
    M.convars.gsa1_metal_walk_fly:SetString("0")
    M.convars.gsa1_mecha_glow:SetString("0")
    local noglow = K.AnimValue(mecha)
    M.convars.gsa1_mecha_glow:SetString("1")
    M.convars.gsa1_mecha_trail:SetString("0")
    local notrail = K.AnimValue(mecha)
    M.convars.gsa1_mecha_trail:SetString("1")
    sup.SKIN_ANIM_TRAIL = had
    -- 1.0.0-beta1a: and SA1_SKIN_ANIM_PACE(100) (25600) for his jog's default pace
    local P100 = 100 * 256
    check(v[1] == 13 + P100 and v[3] == 13 + P100 and walk_m == 13 + P100 and noglow == 9 + P100 and notrail == 5 + P100,
        "T1 [14.1bl] K.AnimValue: Mecha FLY + GLOW + TRAIL (13) + the pace 1.00 (100 x 256) with gsa1_metal_fly 0 and 1 and gsa1_metal_walk_fly 1, never WALK (%s %s %s); without his glow %s, without his trail %s",
        tostring(v[1]), tostring(v[3]), tostring(walk_m), tostring(noglow), tostring(notrail))
    -- 1.0.0-beta1a: the plant's box and the jog's slider (libsa1.h SA1_SKIN_ANIM_NO_PLANT 16, SA1_SKIN_ANIM_PACE(h) h << 8, SA1_SKIN_ANIM_PACE_FREE 2047)
    sup.SKIN_ANIM_TRAIL = 8
    M.convars.gsa1_mecha_plant:SetString("0")
    local noplant = K.AnimValue(mecha)
    M.convars.gsa1_mecha_plant:SetString("1")
    M.convars.gsa1_mecha_jog_pace:SetString("0.5")
    local slow = K.AnimValue(mecha)
    M.convars.gsa1_mecha_jog_pace:SetString("1.65")
    local p165 = K.AnimValue(mecha)
    M.convars.gsa1_mecha_jog_pace:SetString("2.5")
    local free = K.AnimValue(mecha)
    M.convars.gsa1_mecha_jog_pace:SetString("9")
    local clamped = K.AnimValue(mecha)
    M.convars.gsa1_mecha_jog_pace:SetString("1")
    local metal_v = K.AnimValue(metal)
    sup.SKIN_ANIM_TRAIL = had
    check(noplant == 13 + 16 + P100 and slow == 13 + 50 * 256 and p165 == 13 + 165 * 256 and free == 13 + 2047 * 256 and clamped == free and metal_v < 256,
        "T1 1.0.0-beta1a: plant off adds NO_PLANT (%s); the pace 0.5 -> 50, 1.65 -> 165, the top 2.5 -> 2047 no limit, past the top clamped (%s %s %s %s); Metal has neither (%s)",
        tostring(noplant), tostring(slow), tostring(p165), tostring(free), tostring(clamped), tostring(metal_v))
    local ct = K.CheckText(mecha, true)
    check(ct and string.find(ct, "self-check: Mecha Sonic: keep his feet on the floor on; jog pace when running fast 1.00 x Sonic's own fastest jog (4.0 jog cycles a second)", 1, true) ~= nil
        and K.CheckText(metal, true) == nil, "T1 1.0.0-beta1a: the self-check line: %s", tostring(ct))
    check(v[2] == 12 and v[4] == 13 and walk_t == 15, "T1 Metal as 0.9.9g: fly 0 gives GLOW + TRAIL (%s), fly 1 FLY + GLOW + TRAIL (%s), with the walk too (%s)", tostring(v[2]), tostring(v[4]), tostring(walk_t))
end
-- the data never carries the game: numbers and names
do
    local desc = K.DescOf(K.SKINS.metalsonic)
    check(#desc.parts == 100 and #desc.keep == 9 and desc.turn == 1 and desc.anim[1] == 10 and desc.anim[2] == 132 and #desc.anim == 8 and desc.anim_walk[1] == 9 and desc.anim_walk[2] == 131,
        "T1 the flat table for the module: 25 parts by four, nine textures, the running rows, the walk")
    check(K.SKINS.metalsonic.voice == false, "T1 voiceless by the entry")
end

-- ---- T3, T6, T4: the spawn -----------------------------------------------------------------------------------------------------------------------------------------------
M.cv("gsa1_super_transform", "1")
do
    creates = {}
    GSA1.Spawn("metalsonic")
    M.frame(1 / 60)
    local C = GSA1.Char
    check(C and C.name == "metalsonic" and C.kind == 0 and C.skin == K.SKINS.metalsonic and C.noSuper == true and not C.question, "T3 spawned: kind 0, C.skin, C.noSuper")
    local ex = creates[1] and creates[1].extras
    check(ex and ex.create_flags == 0x4000 and type(ex.skin) == "table" and #ex.skin.parts == 100, "T3 extras: CREATE_SKIN and the entry, and never SUPER_CAPABLE, with gsa1_super_transform on (0x%X)", ex and ex.create_flags or 0)
    check(voiceless[C.id] == true, "T3 voiceless at creation")
    local anim
    for _, o in ipairs(options) do if o.opt == 9 then anim = o.v end end
    check(anim == 5, "T3 SA1_COPT_SKIN_ANIM at creation: fly on, walk off, glow on (%s)", tostring(anim))
    -- the options at once
    options = {}
    M.convars.gsa1_metal_walk_fly:SetString("1")
    if cvars and cvars.Run then cvars.Run("gsa1_metal_walk_fly") end
    K.ApplyAnim(C)
    check(options[#options] and options[#options].opt == 9 and options[#options].v == 7, "T7 gsa1_metal_walk_fly: fly + walk + glow at once, no re-creation (%s)", options[#options] and tostring(options[#options].v) or "none")
    M.convars.gsa1_metal_walk_fly:SetString("0")
    M.convars.gsa1_metal_voice:SetString("1")
    K.ApplyVoice(C)
    check(voiceless[C.id] == false, "T7 gsa1_metal_voice: Sonic's voice at once")
    M.convars.gsa1_metal_voice:SetString("0")
    K.ApplyVoice(C)
    -- T4
    local Su = GSA1.Super
    check(Su ~= nil and Su.Press ~= nil and Su.Filter ~= nil and Su.OnForm ~= nil, "T4 Super Sonic's file is there to ask")
    if Su then
        local ok, why = Su.Press(C, "key")
        check(ok == false and string.find(tostring(why), "Metal Sonic does not turn Super", 1, true) ~= nil, "T4 the key and the command: %s", tostring(why))
        check(Su.Filter(C, 3) == 3, "T4 the gesture: the buttons pass unchanged")
        check(C.superForm == nil, "T4 the created hook gave him no form (S.OnForm is only reached past the same test in S.KeyThink)")
        check(Su.Extras(0, "spawned", nil, d) == nil, "T4 S.Extras: nil for him, whatever gsa1_super_transform says")
    end
    -- T5
    check(F.HasFaces("metalsonic") == false, "T5 no faces, no lip sync")
    check(F.NoFaceText("metalsonic") == "Metal Sonic has no face", "T5 the refusal says so: %s", tostring(F.NoFaceText("metalsonic")))
    check(F.Title("metalsonic") == "Metal Sonic", "T5 his name on the wheel's face page")
    do
        local a, b = W.DEFAULTS.metalsonic, W.DEFAULTS.sonic
        local same, faces = #a == #b, 0
        for i, it in ipairs(a) do
            same = same and it.row == b[i].row and it.action == b[i].action
            if it.face then faces = faces + 1 end
        end
        check(same and #a > 0 and faces == 0 and a.centre == nil, "T5 the wheel's default rows are Sonic's, no face among them (%d rows)", #a)
    end
    GSA1.Remove(true)
    GSA1.cv.character:SetString("sonic")
end
-- T6: a module without the flag: refused, never a plain Sonic
do
    local saved = G.SUPER.CREATE_SKIN
    G.SUPER.CREATE_SKIN = nil
    creates = {}
    GSA1.Spawn("metalsonic")
    check(#creates == 0 and (GSA1.Char == nil or GSA1.Char.name ~= "sonic"), "T6 a module without the flag: no Create, never a plain Sonic (%d creates)", #creates)
    G.SUPER.CREATE_SKIN = saved
    if GSA1.Char then GSA1.Remove(true) end
    GSA1.cv.character:SetString("sonic")
end

-- [14.1bl] Mecha Sonic spawned: his rows on from his creation (FLY + GLOW; the mock's module has no TRAIL bit), and the log line says he jogs
do
    local logged = {}
    local log0 = GSA1.Log
    GSA1.Log = function(cat, fmt, ...)
        if cat == "skin" then logged[#logged + 1] = string.format(fmt, ...) end
        if log0 then return log0(cat, fmt, ...) end
    end
    options = {}
    GSA1.Spawn("mechasonic")
    M.frame(1 / 60)
    GSA1.Log = log0
    local C = GSA1.Char
    local anim, jogs = nil, false
    for _, o in ipairs(options) do if o.opt == 9 then anim = o.v end end
    for _, l in ipairs(logged) do
        if string.find(l, "jogs", 1, true) and not string.find(l, "flies", 1, true) then jogs = true end
    end
    local selfcheck
    for _, l in ipairs(logged) do
        if string.find(l, "self-check: Mecha Sonic: keep his feet on the floor on; jog pace when running fast 1.00", 1, true) and string.find(l, "taken by libsa1", 1, true) then selfcheck = l end
    end
    check(C and C.name == "mechasonic" and anim == 5 + 100 * 256 and jogs, "T1 [14.1bl] Mecha spawned: SA1_COPT_SKIN_ANIM %s at creation (FLY + GLOW + the pace 1.00), the log line says he jogs (%s)", tostring(anim), tostring(logged[1]))
    check(selfcheck ~= nil, "T1 1.0.0-beta1a: once a spawn, the self-check line (%s)", tostring(selfcheck or logged[#logged]))
    if GSA1.Char then GSA1.Remove(true) end
    GSA1.cv.character:SetString("sonic")
end

-- ---- T8: Character Select (1.0.0: Up / Down step the slot's skins, feat/cl_charselect_bar.lua) --------------------------------------------------------------------------------------------------------------
do
    local st = { slot = 0, design = "R", state = { phase = 0 }, skins = {} }
    fe.calls, fe.on = 0, nil
    S.st = st
    check(S.StepSkin(st, 1) == true and st.skins[0] == 2 and fe.on ~= nil and fe.quiet == true and fe.on.id == "metalsonic", "T8 Up on slot 0: Metal Sonic on the screen, voiceless by the entry")
    check(S.EntryName(0) == "metalsonic" and S.SlotTitle(0) == "Metal Sonic", "T8 S.EntryName(0) and the title follow (%s)", tostring(S.EntryName(0)))
    check(S.EntryName(1) == "tails" and S.SlotTitle(1) == "Tails", "T8 another slot does not")
    check(S.StepSkin(st, 1) == true and st.skins[0] == 3 and fe.on and fe.on.id == "mechasonic" and S.EntryName(0) == "mechasonic", "T8 Up again: Mecha Sonic")
    check(S.StepSkin(st, 1) == true and st.skins[0] == 1 and fe.on == nil and S.EntryName(0) == "sonic", "T8 Up again: Sonic")
    check(S.StepSkin(st, -1) == true and st.skins[0] == 3 and S.EntryName(0) == "mechasonic", "T8 Down: back to Mecha Sonic")
    S.SetSkin(st, 0, 1)
    st.slot = 1
    check(S.StepSkin(st, 1) == false and (st.skins[1] or 1) == 1, "T8 Up on another slot: nothing")
    st.slot = 0
    fe.refuse = "SA1_CREATE_SKIN: no disc file"
    check(S.StepSkin(st, 1) == false and (st.skins[0] or 1) == 1 and S.EntryName(0) == "sonic", "T8 a refusal leaves the index: the pick names what the screen showed")
    fe.refuse = nil
    S.st = nil
end
-- the input code, by its source: in phase 0 only, one press, Up and Down forwarded always (RM.5, F2)
do
    local src = host_read(root .. "/gsa1/feat/cl_charselect.lua")
    local bar = host_read(root .. "/gsa1/feat/cl_charselect_bar.lua")
    check(string.find(src, "if band(pad, S.PAD_UP) ~= 0 then b = bor(b, F.UP) end", 1, true) ~= nil and string.find(src, "if band(pad, S.PAD_DOWN) ~= 0 then b = bor(b, F.DOWN) end", 1, true) ~= nil,
        "T8 RM.5: Up and Down reach gsa1.FrontendTick on every slot in every phase: the forwarding lines stand, unconditional")
    check(string.find(bar, "if GSA1.CharSelect.cv.skins:GetBool() and idle(st) then", 1, true) ~= nil and string.find(bar, "return tonumber(st.state and st.state.phase) == 0", 1, true) ~= nil, "T8 the skins step only while idle (phase 0, not picked)")
end
-- Start and Escape pinned: the functions compared with the frozen release (when it is there)
do
    -- (r1-verify-s: without build/release_0.9.9g, a fresh clone or a scratch copy, these shrank to an info line.) Each is compared with the FNV-1a 32 of 0.9.9g's own, stored here, always;
    -- with the frozen release beside the addon also with its text, and the stored hash is checked against it
    local PIN_0999G = { ["S.StartAllowed"] = "faabfcad", ["S.OnKey"] = "64a662a4", ["S.Close"] = "ff72216e", ["S.Finish"] = "74a449e1" }
    local function fnv1a(s)
        local h = bit.tobit(0x811C9DC5)
        for i = 1, #s do
            h = bit.bxor(h, string.byte(s, i))
            h = bit.tobit(bit.lshift(h, 24) + h * 403)
        end
        return bit.tohex(h)
    end
    local src = host_read(root .. "/gsa1/feat/cl_charselect.lua")
    local rel = host_read(root .. "/../../build/release_0.9.9g/addon/lua/gsa1/feat/cl_charselect.lua")
    if not rel then info("T8 no frozen release beside the addon (a fresh clone or a scratch copy): S.StartAllowed, S.OnKey, S.Close, S.Finish against 0.9.9g's hashes stored here") end
    local function fn(text, name)
        -- (r1-verify2: CRs first, then the search for "\n" .. "end" .. "\n": a CRLF checkout, a Windows clone with core.autocrlf, finds the same block as the frozen release)
        text = string.gsub(text, "\r", "")
        local a = string.find(text, "function " .. name, 1, true)
        if not a then return "" end
        local b = string.find(text, "\nend\n", a, true)
        return b and string.sub(text, a, b) or ""
    end
    check(fnv1a("a") == "e40c292c", "T8 the pins' hash is FNV-1a 32")
    for _, name in ipairs({ "S.StartAllowed", "S.OnKey", "S.Close", "S.Finish" }) do
        local x = fn(src or "", name)
        check(x ~= "" and fnv1a(x) == PIN_0999G[name] and (not rel or (x == fn(rel, name) and fnv1a(fn(rel, name)) == PIN_0999G[name])),
            "T8 %s: not one line changed against 0.9.9g (%s)", name, rel and "its stored hash and the frozen release" or "its stored hash")
    end
end
return done()
