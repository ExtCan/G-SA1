-- feat_skins_test.lua - Metal Sonic, the addon's side (round 0.9.9f; sadc docs/research/metal099e.md 7, T1, T3, T4, T5, T6, T7, T8 with its review RM.5, RM.15). The whole addon through its autorun, tests/lua_mock.lua
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
check(#GSA1.CHARACTERS == 12 and names.metalsonic == names.supersonic_general + 1 and names.question == 12, "T1 after supersonic_general, ? still last, 12 rows (RM.15)")
check(S.ENTRY_SLOT.metalsonic == 0 and S.SLOT_SKINS[0][1] == "metalsonic" and not S.SLOT_SKINS[1], "T1 Sonic's slot, Up cycles through S.SLOT_SKINS")
check(W.UNPLAYABLE ~= nil, "T1 the wheel's rows are loaded")
do
    local src = host_read(root .. "/gsa1/feat/cl_wheel.lua")
    check(string.find(src, 'entry == "metalsonic" and W.UNPLAYABLE.sonic', 1, true) ~= nil, "T1 his wheel page greys what Sonic's greys (RM.15)")
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

-- ---- T8: Character Select -------------------------------------------------------------------------------------------------------------------------------------------------
do
    local st = { slot = 0, design = "R" }
    fe.calls, fe.on = 0, nil
    check(S.ToggleSkin(st) == true and st.skin == true and fe.on ~= nil and fe.quiet == true, "T8 Up on slot 0: the skin on the screen, voiceless by the entry")
    S.st = st
    check(S.EntryName(0) == "metalsonic" and S.SlotTitle(0) == "Metal Sonic", "T8 S.EntryName(0) and the title follow (%s)", tostring(S.EntryName(0)))
    check(S.EntryName(1) == "tails" and S.SlotTitle(1) == "Tails", "T8 another slot does not")
    check(string.find(S.SkinHint(st), "METAL SONIC", 1, true) ~= nil, "T8 the line: %s", tostring(S.SkinHint(st)))
    check(S.ToggleSkin(st) == true and st.skin == false and fe.on == nil and S.EntryName(0) == "sonic", "T8 Up again: Sonic")
    check(string.find(S.SkinHint(st), "Up: Metal Sonic", 1, true) ~= nil, "T8 the line: %s", tostring(S.SkinHint(st)))
    st.slot = 1
    check(S.ToggleSkin(st) == false and not st.skin, "T8 Up on another slot: nothing")
    st.slot = 0
    fe.refuse = "SA1_CREATE_SKIN: no disc file"
    check(S.ToggleSkin(st) == false and st.skin == false and S.EntryName(0) == "sonic", "T8 a refusal leaves st.skin false: the pick names what the screen showed")
    fe.refuse = nil
    S.st = nil
end
-- the input code, by its source: in phase 0 only, one press, Up forwarded always (RM.5)
do
    local src = host_read(root .. "/gsa1/feat/cl_charselect.lua")
    local a = string.find(src, "band(pressed, S.PAD_UP) ~= 0 and S.SLOT_SKINS[st.slot] and cv.skins:GetBool() and tonumber(st.state.phase) == 0 then S.ToggleSkin(st) end", 1, true)
    local b = string.find(src, "if band(pad, S.PAD_UP) ~= 0 then b = bor(b, F.UP) end", 1, true)
    check(a ~= nil and b ~= nil and a < b, "T8 RM.5: Up toggles in phase 0 only, by the press; and it reaches gsa1.FrontendTick on every slot in every phase: the forwarding line stands, unconditional")
    check(string.find(src, "(code == KEY_MOVE_UP or code == KEY_LETTER_W) and cv.skins:GetBool() and tonumber(st.state.phase) == 0", 1, true) ~= nil, "T8 the keyboard: the same phase test")
end
-- Start and Escape pinned: the functions compared with the frozen release (when it is there)
do
    local src = host_read(root .. "/gsa1/feat/cl_charselect.lua")
    local rel = host_read(root .. "/../../build/release_0.9.9d/addon/lua/gsa1/feat/cl_charselect.lua")
    if not rel then
        info("T8 no frozen release beside the addon (a scratch copy of the tree): S.StartAllowed, S.Close, S.Finish, S.OnKey not compared")
    else
        local function fn(text, name)
            local a = string.find(text, "function " .. name, 1, true)
            if not a then return "" end
            local b = string.find(text, "\nend\n", a, true)
            return b and string.sub(text, a, b):gsub("\r", "") or ""
        end
        for _, name in ipairs({ "S.StartAllowed", "S.OnKey", "S.Close", "S.Finish" }) do
            local x, y = fn(src, name), fn(rel, name)
            check(x ~= "" and x == y, "T8 %s: not one line changed against the release", name)
        end
    end
end
return done()
