-- G-SA1 Super Sonic (round 6a in round 0.9.3, the module's feature "super": src/module/bind_super.cpp, libsa1 API 0.4;
-- sadc docs/research/gsa1_rounds_plan.md 11.3 with the owner's answer 14.1a, gsa1_090_plan.md 7.5, super_sonic.md 4.3-4.7
-- with its Review R.4). The pure part, in both realms (no drawing, no module calls): the options -> the Super flags and
-- the module's create extras, the transformation key's rule, the music choices, the controller buttons and the pre-warm
-- census rows. The client side is feat/cl_super.lua.
--
-- 0.9.3a (sadc docs/research/super_general_design.md 6 with its Review R.4; libsa1.h "THE GENERAL FORM"): two Super Sonics.
-- "Super Sonic (Vs. Perfect Chaos)" is kind 8 exactly as in 0.9.3; "Super Sonic (General Gameplay)" (the list entry with
-- form "general") is a Sonic world in the General form - Sonic's own moves (spin dash, Light Speed Dash, carrying) with
-- the game's Super bit, body, aura and physics task, on the map's own stage (never level 19: Sonic keeps his own voices).
-- A Sonic with the transformation on is a General world too. The rules added here: the General create extras with the
-- review's RC1 (the form survives a re-creation: SA1_SUPER_START only for a spawn, a switch, a respawn or a re-creation
-- of a Super Sonic; a kind 8 re-created after it had turned back gets SA1_SUPER_START_NORMAL), the gesture (jump, then the
-- action button newly pressed in the air: S.GestureAction), the key's air rule (S.KeyAction "ground"), the page's choices
-- (speed, voice, aura animation) and the census rows of the General form. Clean room: behaviour only from the SADX mod's
-- prose (super_general_mod.md); every number is the Dreamcast game's own or our own (super_general_design.md 10).
GSA1 = GSA1 or {}
local S = GSA1.Super or {}
GSA1.Super = S

S.KIND = 8                      -- SA1_CHAR_SUPER_SONIC (GSA1.CHARACTERS: "supersonic")
S.KIND_SONIC = 0
S.FORM_GENERAL = "general"      -- GSA1.CHARACTERS: "supersonic_general" (kind 0)
-- libsa1.h's numbers; the module's gsa1.SUPER wins when it is there (S.Const)
S.K = {
    ORDER_SUPER = 46, ORDER_NORMAL = 47,                                      -- sa1_character_order: the game's PL_OP
    NO_DRAIN = 0x1, KEEP_AT_ZERO = 0x2, FAITHFUL_REVERT = 0x4, SEA_PLANE = 0x8,  -- sa1_character_desc.super_flags
    CREATE_SUPER = 0x400, CREATE_SUPER_CAPABLE = 0x800, CREATE_WATER_FLOOR = 0x1000,
    STATE_SUPER = 0x8, EQUIPMENT = 0x8000, START_RINGS = 50, DRAIN_STEPS = 60,
    MUSIC_THEME = 86, MUSIC_CHAOS_1 = 22, MUSIC_CHAOS_2 = 23,                 -- SPRSONIC.ADX, CHAOS_P1.ADX, CHAOS_P2.ADX
    -- 0.9.3a (feature "super" 2)
    GENERAL = 0x10, START = 0x20, WATER_WHILE_SUPER = 0x40, START_NORMAL = 0x80,
    SUPOPT_SPEED = 1, SUPOPT_NO_AURA = 2, SUPOPT_VOICE = 3, SUPOPT_SUPER_EFFECTS = 4,
    SPEED_GAME = 0, SPEED_RUN = 1, SPEED_HALF = 2, SPEED_SONIC = 3,
    GOPT_IDLE_BY_FORM = 2, GOPT_AURA_ANIM = 3, AURA_DREAMCAST = 0, AURA_CALM = 1, AURA_SLOW = 2,
    VOICE_DEFAULT = 1116,       -- libsa1's tone default (0.9.3a: Sonic's push grunt); G-SA1's default is S.VOICE_DEFAULT
    MODE_JUMP = 8,              -- Sonic's jump (playerwk mode 8: the only state in which he turns Super, owner note 455)
    -- 0.9.4a (feature "super" 4; sadc docs/research/super2_plan.md 5.3): the Super poses, the golden Light Speed charge,
    -- the golden spin dash sparks (SUPER_EFFECTS is bits now), the aura's whoosh from the Perfect Chaos stage (19)
    SUPOPT_SUPER_ANIMS = 5, SUPOPT_LSD_GOLD = 6, SUPER_EFFECTS_CLONES = 1, SUPER_EFFECTS_DUST = 2,
    DRAW_SUPER_GOLD = 0x2000, TEXTURE_VARIANT_SUPER_GOLD = 1, WHOOSH_STAGE = 19, WHOOSH_SLOW = 1035, WHOOSH_FAST = 1036,
}
-- 0.9.4a: the render state bit of a batch drawn with the texture's golden variant (gsa1.WRAP_GOLD, session.hpp WRAP_GOLD)
S.WRAP_GOLD = 0x10

function S.Const(name)
    local t = gsa1 ~= nil and type(gsa1) == "table" and gsa1.SUPER or nil
    return (type(t) == "table" and tonumber(t[name])) or S.K[name]
end

local band = bit.band

-- the Super flags of the options (o: { drain, keep, faithful }): the game's drain unless off, "stay Super at 0 rings",
-- the game's physics bug after turning back. The sea plane (the Perfect Chaos water, which sinks and kills a reverted
-- Sonic) is never asked for: G-SA1's worlds are the map's, at 0 rings he only turns back into normal Sonic
function S.SuperFlags(o)
    local f = 0
    if not o.drain then f = f + S.Const("NO_DRAIN") end
    if o.keep then f = f + S.Const("KEEP_AT_ZERO") end
    if o.faithful then f = f + S.Const("FAITHFUL_REVERT") end
    return f
end

-- 0.9.3a: the Super flags of the General form (o: { general_drain, general_keep, general_water }): the game's drain unless
-- off, "stay Super at 0 rings", water while Super (SA1_SUPER_WATER_WHILE_SUPER: host water is a floor only while he is
-- Super and only below him). The revert fix is always on (no FAITHFUL_REVERT: that switch is the Vs. Perfect Chaos one).
function S.GeneralFlags(o)
    local f = S.Const("GENERAL")
    if not o.general_drain then f = f + S.Const("NO_DRAIN") end
    if o.general_keep then f = f + S.Const("KEEP_AT_ZERO") end
    if o.general_water then f = f + S.Const("WATER_WHILE_SUPER") end
    return f
end

-- the entry is "Super Sonic (General Gameplay)"
function S.IsGeneralDef(def)
    return type(def) == "table" and def.form == S.FORM_GENERAL
end

-- review RC1: a re-creation keeps the form - SA1_SUPER_START for a new General character only when it is spawned,
-- switched to or respawned (Super at once), or re-created while it was Super; a re-creation of a normal one leaves it out
local NEW = { spawned = true, ["switched to"] = true, respawned = true, created = true }
function S.StartsSuper(how, old_super)
    if how == "re-created" then return old_super == true end
    return NEW[how] == true or how == nil
end

-- the module's create extras (gsa1.Create's 6th argument) for a new character of `kind` made from the list entry `def`;
-- how: cl_character.lua's ("spawned", "switched to", "respawned", "re-created"); o: the options (S.Options); forms:
-- Sonic's Super forms are loaded (gsa1.SuperInfo().forms); old: { super = was the character before Super, reverted = it
-- had turned Super and back } (re-creations only); general_api: the module has the General form (feature "super" 2).
-- nil: nothing to add (0.9.2's create)
--   Vs. Perfect Chaos (kind 8): run on water (SA1_CREATE_WATER_FLOOR), the Super flags, his start rings - none on a
--               re-creation, which carries the old count over itself (cl_character.lua GSA1.KeepRings; without a start
--               libsa1 would give 50); re-created after it had turned back: SA1_SUPER_START_NORMAL (RC1: no trigger, he
--               stays normal Sonic and takes the transformation again)
--   General Gameplay (kind 0, form "general"): SA1_CREATE_SUPER_CAPABLE with GENERAL, START (RC1), the General drain /
--               "stay Super" / water bits and gsa1_super_general_rings (none on a re-creation)
--   Sonic:      with the transformation on, a General world without START (he starts normal; a re-creation of a Super
--               Sonic gets START, so he is Super again without a second voice); before 0.9.3a's module the 0.9.3 world
--               (SUPER_CAPABLE: a level-19 world in which the transformation is the game's request 46)
function S.ExtrasFor(kind, how, o, forms, def, old, general_api)
    old = old or {}
    if general_api == nil then general_api = true end
    if kind == S.KIND then
        local rings = math.Clamp(math.floor(tonumber(o.rings) or S.K.START_RINGS), 0, 99)
        local sf = S.SuperFlags(o)
        if how == "re-created" and old.reverted and general_api then sf = sf + S.Const("START_NORMAL") end
        return { create_flags = o.water and S.Const("CREATE_WATER_FLOOR") or 0, super_flags = sf,
                 start_rings = how == "re-created" and 0 or rings }
    end
    if kind ~= S.KIND_SONIC or not forms then return nil end
    if S.IsGeneralDef(def) then
        if not general_api then return nil end
        local rings = math.Clamp(math.floor(tonumber(o.general_rings) or S.K.START_RINGS), 0, 99)
        local sf = S.GeneralFlags(o)
        if S.StartsSuper(how, old.super) then sf = sf + S.Const("START") end
        return { create_flags = S.Const("CREATE_SUPER_CAPABLE"), super_flags = sf,
                 start_rings = how == "re-created" and 0 or rings }
    end
    if not o.transform then return nil end
    if not general_api then
        return { create_flags = S.Const("CREATE_SUPER_CAPABLE"), super_flags = S.SuperFlags(o) }
    end
    local sf = S.GeneralFlags(o)
    if how == "re-created" and old.super == true then sf = sf + S.Const("START") end
    return { create_flags = S.Const("CREATE_SUPER_CAPABLE"), super_flags = sf }
end

-- what the transformation key does with the state st (gsa1.SuperState): "super" (turn Super), "normal" (turn back), or
-- nil and why: "module" (no state), "capable" (not a world that can turn Super), "dead", "rings" (fewer than need),
-- "ground" (0.9.3a, owner note 455: "only ... when jumping, not standing" - Super only in the jump, mode 8; back anywhere)
function S.KeyAction(st, need, dead)
    if type(st) ~= "table" then return nil, "module" end
    if not st.capable then return nil, "capable" end
    if dead then return nil, "dead" end
    if st.super then return "normal" end
    if (tonumber(st.rings) or 0) < (tonumber(need) or 50) then return nil, "rings" end
    if tonumber(st.mode) ~= S.K.MODE_JUMP then return nil, "ground" end
    return "super"
end

-- 0.9.3a, the gesture (owner note 847: "50 rings, jumps and presses the spindash button midair"; design 6.3): what a NEW
-- press of the action button in the jump does, with the state st (gsa1.SuperState: capable, super, general, rings, mode)
-- and the options o ({ gesture, back, need }): "super" (at least `need` rings, the gesture on), "normal" (a General Super
-- Sonic with "the same in a later jump turns him back" on), nil (the press is the game's: Sonic's own air action; a Vs.
-- Perfect Chaos Super Sonic keeps the game's air stop)
function S.GestureAction(st, o)
    if type(st) ~= "table" or not st.capable then return nil end
    if tonumber(st.mode) ~= S.K.MODE_JUMP then return nil end
    if st.super then
        if st.general and o.back then return "normal" end
        return nil
    end
    if not o.gesture then return nil end
    if (tonumber(st.rings) or 0) < (tonumber(o.need) or 50) then return nil end
    return "super"
end

-- the page's choices (0.9.3a): the General form's speed set (gsa1_super_general_speed: libsa1's SA1_SUPER_SPEED_*), the
-- transformation voice (gsa1_super_voice: the game's tones, res-game 3.1's candidates by their sound only), the aura
-- animation (gsa1_super_aura_anim: SA1_AURA_ANIM_*)
S.SPEED_CHOICES = {
    { 1, "Super run - faster on the ground, Sonic's jumps (default)" },
    { 0, "The game's Super Sonic - fastest, floaty jumps" },
    { 2, "Half-way" },
    { 3, "Sonic's speed" },
}
-- values from S.VOICE_CLIP up are voice clips (S.VOICE_CLIP + the clip's number in the voice archive; 0.9.3b: the owner's
-- "HM!" is Super Sonic's own line 396, which 0.9.3's level-19 Sonic played as an idle line); below it, the game's tones
S.VOICE_CLIP = 4096
S.VOICE_DEFAULT = S.VOICE_CLIP + 396
S.VOICE_CHOICES = {
    { S.VOICE_CLIP + 396, "Hm! (Super Sonic's line 396)" },
    { S.VOICE_CLIP + 388, "Super Sonic's longer line (388)" },
    { 1116, "grunt (1116, starting to push)" },
    { 1126, "hm? (1126)" },
    { 1121, "grunt (1121, hanging)" },
    { 1114, "strain (1114, lifting)" },
    { 0, "none" },
}
S.AURA_CHOICES = {
    { 1, "Calm - all 8 frames in order (default)" },
    { 0, "Dreamcast - the game exactly" },
    { 2, "Slow - half as fast as Calm" },
}
-- the tone libsa1 plays at a transformation for the voice setting v: a tone itself, 0 for a voice clip (G-SA1 plays clips)
function S.VoiceTone(v)
    v = math.floor(tonumber(v) or 0)
    if v <= 0 or v >= S.VOICE_CLIP or v > 2047 then return 0 end
    return v
end
function S.ChoiceTitle(choices, v)
    v = tonumber(v)
    for _, c in ipairs(choices) do
        if c[1] == v then return c[2] end
    end
    return tostring(v)
end

-- music while Super (gsa1_super_music): its choices and the music number of a choice (nil: none)
S.MUSIC_OFF, S.MUSIC_TRACK = 0, 4
S.MUSIC_CHOICES = {
    { 0, "Off" },
    { 1, "Theme of Super Sonic (SPRSONIC.ADX)" },
    { 2, "Perfect Chaos 1 (CHAOS_P1.ADX)" },
    { 3, "Perfect Chaos 2 (CHAOS_P2.ADX)" },
    { 4, "A jukebox track (the number below)" },
}
function S.MusicNumber(mode, track)
    mode = tonumber(mode) or 0
    if mode == 1 then return S.Const("MUSIC_THEME") end
    if mode == 2 then return S.Const("MUSIC_CHAOS_1") end
    if mode == 3 then return S.Const("MUSIC_CHAOS_2") end
    if mode == S.MUSIC_TRACK then
        track = math.floor(tonumber(track) or -1)
        if track >= 0 and track <= 255 then return track end
    end
    return nil
end

-- the controller button of the transformation (gsa1_super_pad): XInput's raw bits as the module reports them
-- (GSA1.pad.raw, cl_pad.lua: triggers 0x10000 / 0x20000); A (jump) and Start (the Character Select chooser) are left out.
-- Round 0.9.4b (objects2_plan.md 11.2, the owner: the right-stick click should do "Nothing" for Super Sonic): the default
-- is none - on the controller he turns Super and back with the jump + action-button gesture; 0.9.4a's default, the right
-- stick click (S.PAD_OLD_DEFAULT), is moved to none once (cl_super.lua S.MigratePad)
S.PAD_NONE, S.PAD_DEFAULT, S.PAD_OLD_DEFAULT = 0, 0, 0x0080
S.PAD_BUTTONS = {
    { 0, "None" }, { 0x0080, "Right stick click (RS)" }, { 0x0040, "Left stick click (LS)" }, { 0x8000, "Y" },
    { 0x4000, "X" }, { 0x2000, "B" }, { 0x0100, "Left bumper (LB)" }, { 0x0200, "Right bumper (RB)" },
    { 0x10000, "Left trigger (LT)" }, { 0x20000, "Right trigger (RT)" }, { 0x0020, "Back / View" },
    { 0x0001, "D-pad up" }, { 0x0002, "D-pad down" }, { 0x0004, "D-pad left" }, { 0x0008, "D-pad right" },
}
function S.PadTitle(b)
    for _, p in ipairs(S.PAD_BUTTONS) do
        if p[1] == b then return p[2] end
    end
    return string.format("button 0x%X", tonumber(b) or 0)
end

-- the pre-warm census (cl_warm.lua): rows { archive, texture, flags, src, dst, wrap, pass [, alpha] } recorded with the
-- archive names `names` ({ [0] = name, ... }), moved to the archives of a character (archives: cl_textures.lua's
-- T.Archives: { n, [i] = { name, count } }) by name; a row whose archive has no namesake there, or whose texture does not
-- exist, is left out; untextured rows (-1) stay
local function index_of(archives, name)
    for i = 0, (archives.n or 0) - 1 do
        if archives[i] and archives[i].name == name then return i end
    end
    return nil
end
S.ArchiveIndex = index_of

function S.MapRows(rows, names, archives, out, only)
    out = out or {}
    for _, r in ipairs(rows or {}) do
        local a = r[1]
        if a < 0 then
            if not only then out[#out + 1] = r end
        else
            local name = names[a]
            local to = name and (not only or only == name) and index_of(archives, name) or nil
            if to and r[2] >= 0 and r[2] < (archives[to].count or 0) then
                out[#out + 1] = { to, r[2], r[3], r[4], r[5], r[6], r[7], r[8] }
            end
        end
    end
    return out
end

-- every effect state (SA1_DRAW_EFFECT, not the shadow's) of archive `a` in rows, on every texture of that archive that
-- no body row uses: the aura and the trail animate through their textures, so a 16 s census does not see every frame
local EFFECT, SHADOW = 0x40, 0x800
function S.ExpandEffects(rows, a, count, out)
    out = out or {}
    local body, states, seen = {}, {}, {}
    for _, r in ipairs(rows) do
        if r[1] == a then
            if band(r[3], EFFECT) == 0 and band(r[3], SHADOW) == 0 then
                body[r[2]] = true
            elseif band(r[3], SHADOW) == 0 then
                local k = string.format("%X.%d.%d.%d.%d.%d", r[3], r[4], r[5], r[6], r[7], r[8] or 255)
                if not seen[k] then
                    seen[k] = true
                    states[#states + 1] = r
                end
            end
        end
    end
    for _, s in ipairs(states) do
        for t = 0, (count or 0) - 1 do
            if not body[t] then out[#out + 1] = { a, t, s[3], s[4], s[5], s[6], s[7], s[8] } end
        end
    end
    return out
end

-- 0.9.4a (sadc docs/research/super2_plan.md 6.4 task 7 with its review R.2): the census rows of the golden Light Speed
-- charge - textured rows whose wrap has S.WRAP_GOLD (SON_EFF lcharge01 / 02 of the General form) - moved to the archive of
-- the same name, whatever that archive is (S.MapRows' `only` keeps the SUPERSONIC rows alone)
function S.MapGoldRows(rows, names, archives, out)
    out = out or {}
    for _, r in ipairs(rows or {}) do
        if r[1] >= 0 and band(r[6] or 0, S.WRAP_GOLD) ~= 0 then
            local name = names[r[1]]
            local to = name and index_of(archives, name) or nil
            if to and r[2] >= 0 and r[2] < (archives[to].count or 0) then
                out[#out + 1] = { to, r[2], r[3], r[4], r[5], r[6], r[7], r[8] }
            end
        end
    end
    return out
end

-- one row per state
function S.Dedupe(rows)
    local out, seen = {}, {}
    for _, r in ipairs(rows) do
        local k = string.format("%d.%d.%X.%d.%d.%d.%d.%d", r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8] or 255)
        if not seen[k] then
            seen[k] = true
            out[#out + 1] = r
        end
    end
    return out
end

-- the census rows of a character for the pre-warm:
--   kind 8: his own census (recorded as kind 8), a transformed Sonic's SUPERSONIC states, and normal Sonic's states (the
--           core census, GSA1.WarmCensus[0] as tools/gen_warm_census.py made it) moved to his SONIC / SON_EFF / common
--           archives - after the drain he is normal Sonic, drawn from those;
--   kind 0: Sonic's core census, plus (with his SUPERSONIC archive: the transformation, or the General entry) the Super
--           states moved there (0.9.3a: census[0] is the General form's, feat_super_test.cpp general_script) and (0.9.4a)
--           the golden Light Speed charge's rows (WRAP_GOLD, SON_EFF: S.MapGoldRows) - never for plain Sonic or kind 8;
-- then every effect state of the SUPERSONIC archive on all of its effect textures (S.ExpandEffects).
-- census: { [8] = rows, [0] = rows }, names: { [8] = names, [0] = names } (the archive names they were recorded with),
-- core: the core census rows of Sonic, core_names: their archive names
function S.WarmRows(kind, archives, census, names, core, core_names, with_super)
    local rows = {}
    if kind == S.KIND then
        S.MapRows(census[8], names[8], archives, rows)
        S.MapRows(census[0], names[0], archives, rows, "SUPERSONIC")
        S.MapRows(core, core_names, archives, rows)
    elseif kind == S.KIND_SONIC then
        S.MapRows(core, core_names, archives, rows)
        if with_super then
            S.MapRows(census[0], names[0], archives, rows, "SUPERSONIC")
            S.MapRows(census[8], names[8], archives, rows, "SUPERSONIC")
            S.MapGoldRows(census[0], names[0], archives, rows)
        end
    else
        return nil
    end
    local ss = index_of(archives, "SUPERSONIC")
    if ss and (kind == S.KIND or with_super) then
        S.ExpandEffects(rows, ss, archives[ss].count, rows)
    end
    return S.Dedupe(rows)
end
