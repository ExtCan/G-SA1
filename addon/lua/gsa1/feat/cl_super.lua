-- G-SA1 Super Sonic (round 6a in round 0.9.3; sadc docs/research/gsa1_rounds_plan.md 11.3 with the owner's answer 14.1a
-- "add him as a separate character, as well as a transformation", gsa1_090_plan.md 7.5; super_sonic.md 4.3-4.7 with its
-- Review R.4). The module's feature "super" (src/module/bind_super.cpp) on libsa1's API 0.4; the pure rules are
-- feat/sh_super.lua. Q -> Options -> G-SA1 -> Super Sonic has every setting.
--
-- 0.9.3a (the owner's request of 2026-10-25 "two versions of Super Sonic ... Vs. Perfect Chaos Super Sonic should stay
-- exactly as he is. General Gameplay Super Sonic should play more like regular Sonic (Spindash, optional auras, faster
-- than base form)", and his notes on 0.9.3; design sadc docs/research/super_general_design.md 6 with its Review R.4):
--   * "Super Sonic (Vs. Perfect Chaos)" (GSA1.CHARACTERS "supersonic", kind 8): the game's own Super Sonic of 0.9.3 - the
--     Perfect Chaos stage's trigger turns him Super in his second game pair; his options (gsa1_super_rings, _drain,
--     _keep, _faithful_revert, _water) go into the module's Create through cl_character.lua's seam GSA1.CreateExtras.
--     New for him (each an owner note): Sonic's upgrades (cl_character.lua GSA1.UpgradeNames), Sonic's own idle voices
--     after he turned back (gsa1_super_idle_by_form), the calmer aura animation (gsa1_super_aura_anim), the
--     transformation voice when the player turns him Super again (gsa1_super_voice), turning Super again only in the jump
--     (the key; the action button in the air too), and no chat line when the rings are missing. Re-created after he had
--     turned back (an upgrade ticked, a teleport, a fault restart) he stays normal Sonic (review RC1: libsa1's
--     SA1_SUPER_START_NORMAL); otherwise he is the game's Super Sonic as before.
--   * "Super Sonic (General Gameplay)" ("supersonic_general", kind 0 with form "general"): a Sonic world in libsa1's
--     General form (SA1_SUPER_GENERAL) - golden right after his first pair (SA1_SUPER_START), with every one of Sonic's
--     moves (spin dash, homing attack, Light Speed Dash and Attack with the upgrades, carrying), the game's Super bit
--     (a hit only halves his speed), the aura (optional), the game's golden trail and after-images (optional), a speed
--     set (gsa1_super_general_speed), the ring drain and running on water while Super. At 0 rings he turns back into
--     Sonic and turns Super again with the gesture or the key. His world is the map's own stage (level 1), never level
--     19: normal Sonic keeps his own voice lines (owner note: "Sonic has Super Sonic's voice clips in general").
--   * The transformation for normal Sonic (gsa1_super_transform 1) is the General form now: the gesture - jump, then the
--     action (spin dash) button newly pressed in the air with at least gsa1_super_transform_rings rings (owner notes 455
--     and 847: "only ... when jumping, not standing"; "has 50 rings, jumps and presses the spindash button midair") - or
--     the key (G; a controller button only if chosen - none by default since 0.9.4b; Super only in the jump, back
--     anywhere). The press that transforms is kept from the game until it is released (GSA1.FilterButtons, review
--     RC2 / RC3: only the player's own buttons; the interact key's presses are added after it), and one jump changes
--     the form at most once. The same gesture in a later jump turns a General Super Sonic back
--     (gsa1_super_gesture_back). Too few rings, standing, dying: nothing happens and nothing is said in the chat
--     (owner note 816); the session log notes it at most every 2 s.
--   * The "Hm!" (owner note 463): gsa1_super_voice plays with every transformation the player makes, in both versions
--     (none at the game's own trigger or a re-creation); the page has a Preview. 0.9.3b: the owner's "HM!" is Super
--     Sonic's own line 396 (a voice clip, the default; G-SA1 plays it at the order, S.PlayVoice); the game's tones (1116,
--     Sonic's push grunt, ...) stay as choices and libsa1 plays those itself (SA1_SUPOPT_VOICE takes tones only). A saved
--     1116 (0.9.3a's default, which the owner rejected) becomes the new default once.
--   * The game's aura and its effects come with the game's tasks. The aura's whoosh sounds belong to the Perfect Chaos
--     stage's sound bank, which the module does not have: they are kept out of the mixer (bind_super.cpp). The game's HUD
--     (feat/cl_hud.lua) shows the rings as they drain.
--   * Interaction (feat/*_interact.lua): his attacks are the game's ("super" by the bit), and a hit only halves his speed.
--   * Music while Super (gsa1_super_music, off by default): played by the module's jukebox engine on a channel of its own
--     (S.MUSIC_CH) while he is Super; your personal jukebox pauses meanwhile and goes on afterwards.
--   * The material pre-warm (cl_warm.lua) gets his census (GSA1.WarmCensus[8]; Sonic's [0] gains the General form's
--     SUPERSONIC states for the General entry and while the transformation is on): S.CENSUS, generated by
--     tests/feat_super_test.cpp --census-lua.
--   * Session log lines "super": the worlds made, every change of form with its form and cause, refusals, the options.
--
-- 0.9.4a (the owner's notes on 0.9.3a, sadc docs/research/super2_plan.md 6.4 with its review and the owner's answers of
-- 10.1; module feature "super" 4, libsa1 SA1_API_SUPER_POLISH and libsa1_audio.h version 5):
--   * "Super Sonic's own poses" (gsa1_super_general_anims, on): the General form floats when he stands and flies when he
--     moves - the game's own Super Sonic motions (130 Stationary, 131-134 by the game's speed bands; SA1_SUPOPT_SUPER_ANIMS);
--     after standing still a while he does Sonic's foot-tapping idle on the golden body (owner answer O1); jumps, spin dash,
--     brake, carrying keep Sonic's moves.
--   * "Golden Light Speed Dash" (gsa1_super_general_lsd_gold, on): the plain charge's sparkles and streaks in libsa1's
--     golden texture variant (drawn by cl_textures.lua's WRAP_GOLD render targets), the charged glow in the complement of
--     the game's blue (SA1_SUPOPT_LSD_GOLD); the Crystal Ring's green ones stay green (owner answer O3).
--   * "Golden trail, after-images and spin dash sparks" (gsa1_super_general_effects, renamed): SA1_SUPOPT_SUPER_EFFECTS 3
--     = the game's golden clones and the spin dash sparks in the after-images' golden texture.
--   * "Aura whoosh sounds" (gsa1_super_whoosh, on; both Super Sonics): the game's swoosh above about 1,700 and 3,100 HU/s
--     from the Perfect Chaos stage's sound bank on the disc (gsa1.SuperWhoosh: libsa1's stage rules), with a Preview.
--   * The pre-warm census (S.CENSUS) holds the golden charge's rows (SON_EFF lcharge01 / 02 with WRAP_GOLD) for the General
--     entry and a Sonic with the transformation on (sh_super.lua S.MapGoldRows), so their render targets are made by the
--     pre-warm, never at the first charge.
GSA1 = GSA1 or {}
local S = GSA1.Super
if not S then error("gsa1/feat/sh_super.lua did not load: Super Sonic needs it") end

S.NEEDS = { feature = "super", version = 2, module = "0.9.3a" }
S.MUSIC_CH = 2                  -- the jukebox engine's channel for the Super music (0 is the personal jukebox)
S.RECREATE_DELAY = 0.25         -- s after an option change (one re-creation for several changes)
S.REFUSE_EVERY = 1.0            -- s between two chat lines about a refused transformation (configuration reasons)
S.SILENT_EVERY = 2.0            -- s between two log lines about a silent refusal ("rings", "ground", "dead")

local band, bor, bnot = bit.band, bit.bor, bit.bnot

-- settings (every one has a control on the Super Sonic page) -----------------------------------------------------------
local cv = {
    -- Super Sonic (Vs. Perfect Chaos), as in 0.9.3
    rings     = GSA1.ConVar("gsa1_super_rings", 50, "Super Sonic (Vs. Perfect Chaos) starts with this many rings (the "
        .. "game's Perfect Chaos: 50; at most 99)", 0, 99),
    drain     = GSA1.ConVar("gsa1_super_drain", 1, "Super Sonic (Vs. Perfect Chaos) loses a ring every second (the game's "
        .. "rule; 0 = no drain)", 0, 1),
    keep      = GSA1.ConVar("gsa1_super_keep", 0, "When Super Sonic's (Vs. Perfect Chaos) rings run out: 0 = he turns back "
        .. "into normal Sonic (the game's rule), 1 = he stays Super", 0, 1),
    faithful  = GSA1.ConVar("gsa1_super_faithful_revert", 0, "Keep the game's physics bug after Super Sonic (Vs. Perfect "
        .. "Chaos) turns back (he runs slower afterwards; 0 = libsa1's fix)", 0, 1),
    water     = GSA1.ConVar("gsa1_super_water", 1, "Super Sonic (Vs. Perfect Chaos) runs on Garry's Mod's water, as on the "
        .. "Perfect Chaos sea (1 = on)", 0, 1),
    -- Super Sonic (General Gameplay) (0.9.3a); a Sonic who transforms uses these too
    general_rings = GSA1.ConVar("gsa1_super_general_rings", 50, "Super Sonic (General Gameplay) starts with this many "
        .. "rings (at most 99)", 0, 99),
    general_drain = GSA1.ConVar("gsa1_super_general_drain", 1, "Super Sonic (General Gameplay, and a Sonic who "
        .. "transformed) loses a ring every second while Super (the game's rule; 0 = no drain)", 0, 1),
    general_keep  = GSA1.ConVar("gsa1_super_general_keep", 0, "Super Sonic (General Gameplay): 0 = at 0 rings he turns "
        .. "back into Sonic, 1 = he stays Super", 0, 1),
    general_speed = GSA1.ConVar("gsa1_super_general_speed", 1, "Super Sonic (General Gameplay)'s speed: 1 = Super run "
        .. "(faster on the ground, Sonic's jumps), 0 = the game's Super Sonic (floaty jumps), 2 = half-way, 3 = Sonic's", 0,
        3),
    general_aura  = GSA1.ConVar("gsa1_super_general_aura", 1, "Super Sonic (General Gameplay) has the golden aura "
        .. "(0 = no aura; the Vs. Perfect Chaos one always has it)", 0, 1),
    general_water = GSA1.ConVar("gsa1_super_general_water", 1, "Super Sonic (General Gameplay) runs on Garry's Mod's water "
        .. "while Super (water below him is a floor; deeper water he is in stays water)", 0, 1),
    general_effects = GSA1.ConVar("gsa1_super_general_effects", 1, "Super Sonic (General Gameplay): the game's golden "
        .. "trail and ball after-images, and the spin dash sparks in the after-images' gold, while Super (0 = Sonic's blue "
        .. "ones)", 0, 1),
    -- 0.9.4a (super2_plan.md 7)
    general_anims = GSA1.ConVar("gsa1_super_general_anims", 1, "Super Sonic (General Gameplay, and a Sonic who "
        .. "transformed) uses Super Sonic's own floating stand and flying moves (0 = Sonic's moves on the golden body, as "
        .. "0.9.3a)", 0, 1),
    general_lsd_gold = GSA1.ConVar("gsa1_super_general_lsd_gold", 1, "Super Sonic (General Gameplay): the Light Speed "
        .. "charge's sparkles, streaks and glow in gold while Super (0 = the game's blue)", 0, 1),
    whoosh    = GSA1.ConVar("gsa1_super_whoosh", 1, "Super Sonic's aura whoosh from the Perfect Chaos sound bank on your "
        .. "disc (0 = silent)", 0, 1),
    -- turning Super
    transform = GSA1.ConVar("gsa1_super_transform", 1, "Super transformation: Sonic with enough rings turns Super in a "
        .. "jump (the action button in the air, or the key) and back again (changing it re-creates Sonic where he stands)",
        0, 1),
    need      = GSA1.ConVar("gsa1_super_transform_rings", 50, "Rings needed for the Super transformation (at least)", 1, 99),
    gesture   = GSA1.ConVar("gsa1_super_gesture", 1, "Jump, then the action (spin dash) button in the air turns Sonic "
        .. "Super (0 = only the key)", 0, 1),
    gesture_back = GSA1.ConVar("gsa1_super_gesture_back", 1, "The same in a later jump turns Super Sonic (General "
        .. "Gameplay) back into Sonic", 0, 1),
    key       = GSA1.ConVar("gsa1_super_key", 17, "The Super transformation key (a key code; 17 = G; 0 = none: bind a key "
        .. "to gsa1_super instead). Super only in the jump, back anywhere", 0, 511),
    pad       = GSA1.ConVar("gsa1_super_pad", S.PAD_DEFAULT, "The controller button of the Super transformation (XInput "
        .. "bits: 0 = none, the default - the jump + action button gesture turns him Super and back; 128 = the right "
        .. "stick click)", 0, 0x30000),
    -- both Super Sonics (0.9.3a)
    voice     = GSA1.ConVar("gsa1_super_voice", S.VOICE_DEFAULT, "The voice when the player turns Sonic Super ("
        .. S.VOICE_DEFAULT .. " = Super Sonic's \"Hm!\", voice clip 396; 4096 + n = voice clip n; 1..2047 = a game tone; "
        .. "0 = none)", 0, S.VOICE_CLIP + 4095),
    aura_anim = GSA1.ConVar("gsa1_super_aura_anim", 1, "Super Sonic's aura animation: 1 = calm (all 8 frames in order), "
        .. "0 = the Dreamcast's, 2 = slow", 0, 2),
    idle_by_form = GSA1.ConVar("gsa1_super_idle_by_form", 1, "Super Sonic's own idle voice lines while Super, Sonic's "
        .. "while normal (0 = the game's choice by the stage)", 0, 1),
    music     = GSA1.ConVar("gsa1_super_music", 0, "Music while Super: 0 = off, 1 = Theme of Super Sonic, 2 = Perfect "
        .. "Chaos 1, 3 = Perfect Chaos 2, 4 = the jukebox track gsa1_super_music_track", 0, 4),
    track     = GSA1.ConVar("gsa1_super_music_track", 86, "Music while Super, choice 4: the jukebox track number (the "
        .. "Jukebox page lists them; 86 = Theme of Super Sonic)", 0, 255),
}
S.cv = cv
-- 0.9.3b: a saved 1116 (0.9.3a's default; the owner: none of the grunts was his "HM!") becomes the new default, once per
-- installation (a cookie); true when it changed the setting
function S.MigrateVoice()
    if not (cookie and cookie.GetNumber and cookie.Set) or cookie.GetNumber("gsa1_super_voice_093b", 0) ~= 0 then
        return false
    end
    cookie.Set("gsa1_super_voice_093b", "1")
    if cv.voice:GetInt() ~= 1116 then return false end
    RunConsoleCommand("gsa1_super_voice", tostring(S.VOICE_DEFAULT))
    return true
end
S.MigrateVoice()
-- 0.9.4b (objects2_plan.md 11.2): a saved 128 (the right stick click, 0.9.4a's default; the owner: pressing the right stick
-- detransformed Super Sonic, it should do "Nothing") becomes none, once per installation (a cookie, like the voice above);
-- a button chosen later, even the right stick click again, stays. true when it changed the setting
function S.MigratePad()
    if not (cookie and cookie.GetNumber and cookie.Set) or cookie.GetNumber("gsa1_super_pad_094b", 0) ~= 0 then
        return false
    end
    cookie.Set("gsa1_super_pad_094b", "1")
    if cv.pad:GetInt() ~= S.PAD_OLD_DEFAULT then return false end
    RunConsoleCommand("gsa1_super_pad", tostring(S.PAD_DEFAULT))
    return true
end
S.MigratePad()

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("super", fmt, ...) end
end
S.LogLine = log

-- the loaded module has the feature (cheap: for the hooks)
local function have()
    return GSA1.mod ~= nil and gsa1 ~= nil and gsa1.SuperOrder ~= nil and gsa1.SuperState ~= nil
end
S.Have = have
-- ... and its version 2 (0.9.3a: the General form, the Super options)
local function have_general()
    return have() and gsa1.SuperOption ~= nil and gsa1.SuperGameOption ~= nil and type(gsa1.SUPER) == "table" and
        gsa1.SUPER.GENERAL ~= nil
end
S.HaveGeneral = have_general
-- ... and its version 4 (0.9.4a: the Super poses, the golden Light Speed charge, the golden spin dash sparks)
local function have_polish()
    return have_general() and gsa1.SUPER.SUPOPT_SUPER_ANIMS ~= nil and gsa1.SUPER.SUPOPT_LSD_GOLD ~= nil
end
S.HavePolish = have_polish
-- ... and the whoosh call (gsa1.SuperWhoosh, feature "super" 4)
local function have_whoosh()
    return have() and gsa1.SuperWhoosh ~= nil
end
S.HaveWhoosh = have_whoosh

-- the options as sh_super.lua's rules take them
function S.Options()
    return { rings = cv.rings:GetInt(), drain = cv.drain:GetBool(), keep = cv.keep:GetBool(),
             faithful = cv.faithful:GetBool(), water = cv.water:GetBool(), transform = cv.transform:GetBool(),
             general_rings = cv.general_rings:GetInt(), general_drain = cv.general_drain:GetBool(),
             general_keep = cv.general_keep:GetBool(), general_water = cv.general_water:GetBool(),
             gesture = cv.gesture:GetBool(), back = cv.gesture_back:GetBool(), need = cv.need:GetInt() }
end

-- the module's Super info (gsa1.SuperInfo), asked again after a while (the disc may load later); fresh: now (the page's
-- status lines, twice a second: the whoosh's bank state)
local info_out, info_at = {}, -1e9
function S.Info(fresh)
    if not have() or not gsa1.SuperInfo then return nil end
    local now = SysTime()
    if fresh or now - info_at > 1 or not info_out.ready then
        info_at = now
        gsa1.SuperInfo(info_out)
    end
    return info_out
end

-- character C's Super state now (gsa1.SuperState; the table is reused) or nil
local state_out = {}
function S.State(C)
    if not C or not C.id or not have() then return nil end
    local s = gsa1.SuperState(C.id, state_out)
    return type(s) == "table" and s or nil
end

-- the form of a character, for the other features and the status (true: Super now)
function S.IsSuper(C)
    return C ~= nil and C.superForm == true
end

-- which Super Sonic a character is ("General", "Vs. Perfect Chaos") or "normal Sonic" (a world that cannot turn Super)
function S.FormName(C, st)
    if not C then return "?" end
    if (st and st.general) or C.superGeneral then return "General" end
    if C.kind == S.KIND then return "Vs. Perfect Chaos" end
    if (st and st.capable) or C.superCapable then return "the game's Super modes" end
    return "normal Sonic"
end

-- 1. the create extras (cl_character.lua's seam) ------------------------------------------------------------------------
local prev_extras = GSA1.CreateExtras
function S.Extras(kind, how, rings, def, old)
    if kind ~= S.KIND and kind ~= S.KIND_SONIC then return nil end
    if not have() then return nil end
    local inf = S.Info()
    local was = nil
    if how == "re-created" and type(old) == "table" then
        -- review RC1: the form survives a re-creation (a kind 8 that turned back stays normal; a Super one stays Super)
        was = { super = old.superForm == true,
                reverted = old.superForm ~= true and ((old.superCount or 0) > 0 or old.superReverted == true) }
    end
    local forms = inf ~= nil and inf.forms == true
    local ex = S.ExtrasFor(kind, how, S.Options(), forms, def, was, have_general())
    if ex == nil and S.IsGeneralDef(def) then
        log("%s: the General form cannot be made (%s); a plain Sonic instead", def.title or "?",
            not have_general() and "the module has no General form: feature \"super\" 2 is needed" or
            (forms and "?" or "Sonic's Super forms are not loaded from the disc"))
    end
    return ex
end
GSA1.CreateExtras = function(kind, how, rings, def, old)
    local ex = S.Extras(kind, how, rings, def, old)
    if ex ~= nil then return ex end
    if prev_extras then return prev_extras(kind, how, rings, def, old) end
    return nil
end

-- 2. the material pre-warm (cl_warm.lua) ------------------------------------------------------------------------------------
-- The census of tests/feat_super_test.cpp (--census-lua; material_census_super.txt, checked by tests/feat_super_test.lua):
-- every render state Super Sonic drew in 16 s of scripted play (standing, running into both dash auras, jumps, homing
-- attacks, the air stop, then the drain's revert and normal Sonic's moves; recorded as kind 8) and every SUPERSONIC state
-- of the General form (kind 0, 0.9.3a: the transformation in a jump, running into both dash auras, the Super ball and
-- homing, his air action, a spin dash and its roll with the golden after-images, the Light Speed charge, the revert;
-- G-SA1's default options; 0.9.4a: with the Super poses, the golden spin dash sparks and the golden Light Speed charge,
-- whose rows - SON_EFF lcharge01 / 02 with WRAP_GOLD (wrap 19), from a second charge with the shoes alone - S.WarmRows maps
-- by name (sh_super.lua S.MapGoldRows, review R.2). Numbers only: archive and texture numbers of the characters' own
-- archives, SA1_DRAW_*
-- flags, blend factors, address modes, passes. S.WarmRows (sh_super.lua) moves them to the archives the module reports
-- (by name) and adds normal Sonic's core census for Super Sonic's SONIC / SON_EFF archives and every effect state of the
-- SUPERSONIC archive on all of its effect textures.
S.CENSUS_NAMES = {
    [8] = { [0] = "SUPERSONIC", "OBJ_REGULAR", "EFF_REGULAR", "CON_REGULAR", "SONIC", "SON_EFF" },
    [0] = { [0] = "SONIC", "SON_EFF", "OBJ_REGULAR", "EFF_REGULAR", "CON_REGULAR", "SUPERSONIC" },
}
-- the archive names of the core census of Sonic (cl_warm_census.lua, core_test: Sonic's archives at the time)
S.CORE_NAMES = { [0] = "SONIC", "SON_EFF", "OBJ_REGULAR", "EFF_REGULAR", "CON_REGULAR" }
S.CENSUS = {
    [8] = {
        { 0, 0, 0x20, 1, 0, 3, 0 }, { 0, 1, 0x20, 1, 0, 3, 0 }, { 0, 10, 0x20, 1, 0, 3, 0 },
        { 0, 11, 0x20, 1, 0, 3, 0 }, { 0, 12, 0x20, 1, 0, 3, 0 }, { 0, 13, 0x28, 1, 0, 3, 0 },
        { 0, 14, 0x21, 4, 5, 3, 1 }, { 0, 15, 0x20, 1, 0, 3, 0 }, { 0, 16, 0x275, 4, 1, 2, 1 },
        { 0, 17, 0x275, 4, 1, 2, 1 }, { 0, 18, 0x275, 4, 1, 2, 1 }, { 0, 19, 0x275, 4, 1, 2, 1 },
        { 0, 2, 0x20, 1, 0, 3, 0 }, { 0, 20, 0x275, 4, 1, 2, 1 }, { 0, 21, 0x275, 4, 1, 2, 1 },
        { 0, 22, 0x275, 4, 1, 2, 1 }, { 0, 23, 0x275, 4, 1, 2, 1 }, { 0, 24, 0x275, 4, 1, 2, 1 },
        { 0, 25, 0x275, 4, 1, 2, 1 }, { 0, 26, 0x275, 4, 1, 2, 1 }, { 0, 27, 0x275, 4, 1, 2, 1 },
        { 0, 28, 0x275, 4, 1, 2, 1 }, { 0, 29, 0x275, 4, 1, 2, 1 }, { 0, 3, 0x20, 1, 0, 3, 0 },
        { 0, 30, 0x275, 4, 1, 2, 1 }, { 0, 31, 0x275, 4, 1, 2, 1 }, { 0, 4, 0x20, 1, 0, 3, 0 },
        { 0, 48, 0x271, 1, 1, 3, 1 }, { 0, 49, 0x271, 1, 1, 3, 1 }, { 0, 5, 0x20, 1, 0, 3, 0 },
        { 0, 50, 0x275, 4, 1, 3, 1 }, { 0, 51, 0x275, 4, 1, 3, 1 }, { 0, 52, 0x275, 4, 1, 3, 1 },
        { 0, 53, 0x275, 4, 1, 3, 1 }, { 0, 54, 0x275, 4, 1, 3, 1 }, { 0, 55, 0x275, 4, 1, 3, 1 },
        { 0, 56, 0x275, 4, 1, 3, 1 }, { 0, 57, 0x275, 4, 1, 3, 1 }, { 0, 58, 0x275, 4, 1, 3, 1 },
        { 0, 59, 0x275, 4, 1, 3, 1 }, { 0, 6, 0x20, 1, 0, 3, 0 }, { 0, 60, 0x275, 4, 1, 3, 1 },
        { 0, 61, 0x275, 4, 1, 3, 1 }, { 0, 62, 0x275, 4, 1, 3, 1 }, { 0, 63, 0x275, 4, 1, 3, 1 },
        { 0, 65, 0x275, 4, 1, 3, 1 }, { 0, 67, 0x275, 4, 1, 3, 1 }, { 0, 69, 0x275, 4, 1, 3, 1 },
        { 0, 7, 0x20, 1, 0, 3, 0 }, { 0, 71, 0x275, 4, 1, 3, 1 }, { 0, 8, 0x20, 1, 0, 3, 0 },
        { 0, 9, 0x20, 1, 0, 3, 0 }, { 1, 58, 0x841, 4, 5, 11, 1 }, { 4, 0, 0x20, 1, 0, 3, 0 },
        { 4, 0, 0x60, 1, 0, 3, 0 }, { 4, 1, 0x20, 1, 0, 3, 0 }, { 4, 1, 0x60, 1, 0, 3, 0 }, { 4, 10, 0x20, 1, 0, 3, 0 },
        { 4, 11, 0x20, 1, 0, 3, 0 }, { 4, 11, 0x60, 1, 0, 3, 0 }, { 4, 13, 0x20, 1, 0, 3, 0 },
        { 4, 15, 0x21, 4, 5, 3, 1 }, { 4, 15, 0x61, 4, 5, 3, 1 }, { 4, 16, 0x20, 1, 0, 3, 0 },
        { 4, 16, 0x60, 1, 0, 3, 0 }, { 4, 17, 0x20, 1, 0, 3, 0 }, { 4, 17, 0x60, 1, 0, 3, 0 },
        { 4, 18, 0x20, 1, 0, 3, 0 }, { 4, 2, 0x20, 1, 0, 3, 0 }, { 4, 2, 0x60, 1, 0, 3, 0 },
        { 4, 23, 0x20, 1, 0, 3, 0 }, { 4, 23, 0x60, 1, 0, 3, 0 }, { 4, 24, 0x20, 1, 0, 3, 0 },
        { 4, 24, 0x60, 1, 0, 3, 0 }, { 4, 3, 0x20, 1, 0, 3, 0 }, { 4, 3, 0x60, 1, 0, 3, 0 }, { 4, 4, 0x20, 1, 0, 3, 0 },
        { 4, 4, 0x60, 1, 0, 3, 0 }, { 4, 5, 0x20, 1, 0, 3, 0 }, { 4, 5, 0x24, 1, 0, 3, 0 }, { 4, 5, 0x60, 1, 0, 3, 0 },
        { 4, 6, 0x20, 1, 0, 3, 0 }, { 4, 6, 0x60, 1, 0, 3, 0 }, { 4, 7, 0x20, 1, 0, 0, 0 }, { 4, 7, 0x20, 1, 0, 3, 0 },
        { 4, 7, 0x60, 1, 0, 0, 0 }, { 4, 7, 0x60, 1, 0, 3, 0 }, { 4, 8, 0x20, 1, 0, 3, 0 }, { 4, 8, 0x60, 1, 0, 3, 0 },
        { 4, 9, 0x20, 1, 0, 3, 0 }, { 4, 9, 0x60, 1, 0, 3, 0 }, { 5, 0, 0x271, 1, 1, 3, 1 },
        { 5, 1, 0x271, 1, 1, 3, 1 }, { 5, 10, 0x275, 4, 1, 3, 1 }, { 5, 11, 0x275, 4, 1, 3, 1 },
        { 5, 12, 0x275, 4, 1, 3, 1 }, { 5, 13, 0x275, 4, 1, 3, 1 }, { 5, 14, 0x275, 4, 1, 3, 1 },
        { 5, 15, 0x275, 4, 1, 3, 1 }, { 5, 16, 0x275, 4, 1, 3, 1 }, { 5, 17, 0x275, 4, 1, 3, 1 },
        { 5, 18, 0x275, 4, 1, 3, 1 }, { 5, 19, 0x275, 4, 1, 3, 1 }, { 5, 2, 0x275, 4, 1, 3, 1 },
        { 5, 20, 0x275, 4, 1, 3, 1 }, { 5, 21, 0x275, 4, 1, 3, 1 }, { 5, 22, 0x275, 4, 1, 3, 1 },
        { 5, 23, 0x275, 4, 1, 3, 1 }, { 5, 3, 0x275, 4, 1, 3, 1 }, { 5, 4, 0x275, 4, 1, 3, 1 },
        { 5, 5, 0x275, 4, 1, 3, 1 }, { 5, 6, 0x275, 4, 1, 3, 1 }, { 5, 7, 0x275, 4, 1, 3, 1 },
        { 5, 8, 0x275, 4, 1, 3, 1 }, { 5, 9, 0x275, 4, 1, 3, 1 },
    },
    [0] = {
        { 1, 25, 0x255, 4, 1, 19, 1 }, { 1, 26, 0x255, 4, 1, 19, 1 }, { 5, 0, 0x20, 1, 0, 3, 0 },
        { 5, 1, 0x20, 1, 0, 3, 0 }, { 5, 10, 0x20, 1, 0, 3, 0 }, { 5, 11, 0x20, 1, 0, 3, 0 },
        { 5, 12, 0x20, 1, 0, 3, 0 }, { 5, 13, 0x20, 1, 0, 3, 0 }, { 5, 13, 0x28, 1, 0, 3, 0 },
        { 5, 14, 0x21, 4, 5, 3, 1 }, { 5, 15, 0x20, 1, 0, 3, 0 }, { 5, 16, 0x275, 4, 1, 2, 1 },
        { 5, 17, 0x275, 4, 1, 2, 1 }, { 5, 18, 0x275, 4, 1, 2, 1 }, { 5, 19, 0x20, 1, 0, 3, 0 },
        { 5, 19, 0x275, 4, 1, 2, 1 }, { 5, 2, 0x20, 1, 0, 3, 0 }, { 5, 20, 0x20, 1, 0, 3, 0 },
        { 5, 20, 0x275, 4, 1, 2, 1 }, { 5, 21, 0x20, 1, 0, 3, 0 }, { 5, 21, 0x275, 4, 1, 2, 1 },
        { 5, 22, 0x20, 1, 0, 3, 0 }, { 5, 22, 0x275, 4, 1, 2, 1 }, { 5, 23, 0x275, 4, 1, 2, 1 },
        { 5, 24, 0x275, 4, 1, 2, 1 }, { 5, 25, 0x275, 4, 1, 2, 1 }, { 5, 26, 0x275, 4, 1, 2, 1 },
        { 5, 27, 0x275, 4, 1, 2, 1 }, { 5, 28, 0x275, 4, 1, 2, 1 }, { 5, 29, 0x275, 4, 1, 2, 1 },
        { 5, 3, 0x20, 1, 0, 3, 0 }, { 5, 30, 0x275, 4, 1, 2, 1 }, { 5, 31, 0x275, 4, 1, 2, 1 },
        { 5, 4, 0x20, 1, 0, 3, 0 }, { 5, 48, 0x271, 1, 1, 3, 1 }, { 5, 49, 0x271, 1, 1, 3, 1 },
        { 5, 5, 0x20, 1, 0, 3, 0 }, { 5, 50, 0x275, 4, 1, 3, 1 }, { 5, 51, 0x275, 4, 1, 3, 1 },
        { 5, 52, 0x275, 4, 1, 3, 1 }, { 5, 53, 0x275, 4, 1, 3, 1 }, { 5, 54, 0x275, 4, 1, 3, 1 },
        { 5, 55, 0x275, 4, 1, 3, 1 }, { 5, 56, 0x275, 4, 1, 3, 1 }, { 5, 57, 0x275, 4, 1, 3, 1 },
        { 5, 58, 0x275, 4, 1, 3, 1 }, { 5, 59, 0x275, 4, 1, 3, 1 }, { 5, 6, 0x20, 1, 0, 3, 0 },
        { 5, 60, 0x275, 4, 1, 3, 1 }, { 5, 61, 0x275, 4, 1, 3, 1 }, { 5, 62, 0x275, 4, 1, 3, 1 },
        { 5, 63, 0x275, 4, 1, 3, 1 }, { 5, 64, 0x275, 4, 1, 3, 1 }, { 5, 65, 0x275, 4, 1, 3, 1 },
        { 5, 66, 0x275, 4, 1, 3, 1 }, { 5, 67, 0x275, 4, 1, 3, 1 }, { 5, 68, 0x275, 4, 1, 3, 1 },
        { 5, 69, 0x275, 4, 1, 3, 1 }, { 5, 7, 0x20, 1, 0, 0, 0 }, { 5, 7, 0x20, 1, 0, 3, 0 },
        { 5, 70, 0x275, 4, 1, 3, 1 }, { 5, 71, 0x275, 4, 1, 3, 1 }, { 5, 8, 0x20, 1, 0, 3, 0 },
        { 5, 9, 0x20, 1, 0, 3, 0 },
    },
}

-- Sonic's core census as cl_warm_census.lua made it (GSA1.WarmCensus[0] gets the Super states added while the
-- transformation is on; this is the base)
S.coreSonic = S.coreSonic or (GSA1.WarmCensus and GSA1.WarmCensus[0]) or {}

-- the census rows of `kind` into GSA1.WarmCensus (before its pre-warm starts: GSA1CharacterCreated runs first); C (0.9.3a):
-- the new character (the General entry gets the Super states whatever the transformation switch says)
function S.ApplyWarm(kind, C)
    if kind ~= S.KIND and kind ~= S.KIND_SONIC then return end
    if not (GSA1.WarmCensus and GSA1.Tex and GSA1.Tex.Archives) then return end
    local A = GSA1.Tex.Archives(kind)
    -- archives without Sonic's (an unexpected list): Sonic keeps the core census as it is
    if kind == S.KIND_SONIC and S.ArchiveIndex(A, "SONIC") == nil then return nil end
    -- 0.9.3a: the General entry always has the Super states (C: the new character; its list entry)
    local with_super = kind == S.KIND_SONIC and (cv.transform:GetBool() or (C ~= nil and S.IsGeneralDef(C.def))) and
        S.ArchiveIndex(A, "SUPERSONIC") ~= nil
    local rows = S.WarmRows(kind, A, S.CENSUS, S.CENSUS_NAMES, S.coreSonic, S.CORE_NAMES, with_super)
    if rows then GSA1.WarmCensus[kind] = rows end
    return rows
end

-- 3. the options that apply at once (0.9.3a: no re-creation) -----------------------------------------------------------------
-- The General form's speed set, aura, golden effects; the transformation voice (any world that can turn Super); the idle
-- voices by form and the aura animation (SA1_GA switches in the game's own code). Applied right after a create (before the
-- first tick: libsa1 keeps them for the world it builds) and at once when a setting changes.
local function super_option(C, opt, value, what)
    local ok, err, code = gsa1.SuperOption(C.id, opt, value)
    if not ok then log("%s: %s = %s refused: %s (%s)", C.title or "?", what, tostring(value), tostring(err), tostring(code)) end
    return ok
end
local function game_option(C, opt, value, what)
    local ok, err, code = gsa1.SuperGameOption(C.id, opt, value)
    if not ok then log("%s: %s = %s refused: %s (%s)", C.title or "?", what, tostring(value), tostring(err), tostring(code)) end
    return ok
end
-- plays the voice setting v once (the Preview, and a voice clip at a SUPER order): a voice clip (v >= S.VOICE_CLIP) through
-- gsa1.SuperVoiceClip (module 0.9.3b), a tone through gsa1.SuperVoicePreview; as character id's own sound when given
function S.PlayVoice(v, id)
    v = math.floor(tonumber(v) or 0)
    if v >= S.VOICE_CLIP then
        if not gsa1.SuperVoiceClip then return nil, "voice clips need the G-SA1 module 0.9.3b or newer" end
        return gsa1.SuperVoiceClip(v - S.VOICE_CLIP, id)
    end
    return gsa1.SuperVoicePreview(v, id)
end
-- the value of SA1_SUPOPT_SUPER_EFFECTS for "Golden trail, after-images and spin dash sparks": 0.9.4a's bits CLONES | DUST
-- (3), or 0.9.3a's 1 with a module before feature "super" 4 (its libsa1 takes 0 / 1 only)
function S.EffectsValue(on)
    if not on then return 0 end
    if not have_polish() then return 1 end
    return bit.bor(S.Const("SUPER_EFFECTS_CLONES"), S.Const("SUPER_EFFECTS_DUST"))
end

-- only: nil = all, else one of "speed", "aura", "effects", "anims", "lsd", "voice", "idle", "aura_anim"
function S.ApplyOptions(C, only)
    if not C or not C.id or not have_general() then return 0 end
    if C.kind ~= S.KIND and C.kind ~= S.KIND_SONIC then return 0 end
    local st = S.State(C)
    if not st or not st.capable then return 0 end
    local n = 0
    local function want(w) return only == nil or only == w end
    if st.general then
        if want("speed") and super_option(C, S.Const("SUPOPT_SPEED"), cv.general_speed:GetInt(), "speed") then n = n + 1 end
        if want("aura") and super_option(C, S.Const("SUPOPT_NO_AURA"), cv.general_aura:GetBool() and 0 or 1, "no aura") then
            n = n + 1
        end
        if want("effects") and super_option(C, S.Const("SUPOPT_SUPER_EFFECTS"), S.EffectsValue(cv.general_effects:GetBool()),
            "golden effects") then n = n + 1 end
        -- 0.9.4a: the General form only (never kind 8: libsa1 refuses it there)
        if have_polish() then
            if want("anims") and super_option(C, S.Const("SUPOPT_SUPER_ANIMS"), cv.general_anims:GetBool() and 1 or 0,
                "Super poses") then n = n + 1 end
            if want("lsd") and super_option(C, S.Const("SUPOPT_LSD_GOLD"), cv.general_lsd_gold:GetBool() and 1 or 0,
                "golden Light Speed") then n = n + 1 end
        end
    end
    if want("voice") and super_option(C, S.Const("SUPOPT_VOICE"), S.VoiceTone(cv.voice:GetInt()), "voice") then
        n = n + 1
    end
    if want("idle") and game_option(C, S.Const("GOPT_IDLE_BY_FORM"), cv.idle_by_form:GetBool() and 1 or 0,
        "idle voices by form") then n = n + 1 end
    if want("aura_anim") and game_option(C, S.Const("GOPT_AURA_ANIM"), cv.aura_anim:GetInt(), "aura animation") then
        n = n + 1
    end
    return n
end

-- 4. the transformation ------------------------------------------------------------------------------------------------------
local REFUSE_TEXT = {
    module = "Super Sonic needs the G-SA1 module 0.9.3 or newer (its \"super\" part)",
    capable = "this Sonic cannot turn Super: the Super transformation is off (Q menu > Options > G-SA1 > Super Sonic)",
    other = "only Sonic can turn Super",
    rings = "%s needs %d rings to turn Super (%d now)",
    ground = "%s turns Super only in a jump",
    dead = "not while the character is dying",
}
-- owner note 816 ("there should be no note in the chat when you try to turn into Super Sonic without the rings"): these
-- are log lines only (at most one per S.SILENT_EVERY); the configuration reasons keep their chat line
S.SILENT = { rings = true, ground = true, dead = true }
local refused_at, silent_at = -1e9, -1e9

local function refuse(C, why, need, rings)
    local text
    if why == "capable" and C.kind ~= S.KIND_SONIC and C.kind ~= S.KIND then
        text = REFUSE_TEXT.other
    elseif why == "rings" then
        text = string.format(REFUSE_TEXT.rings, C.title or "Sonic", need, rings or 0)
    elseif why == "ground" then
        text = string.format(REFUSE_TEXT.ground, C.title or "Sonic")
    else
        text = REFUSE_TEXT[why] or tostring(why)
    end
    local now = SysTime()
    if S.SILENT[why] then
        if now - silent_at >= S.SILENT_EVERY then
            silent_at = now
            log("transformation refused (%s): %s", tostring(why), text)
        end
        return false, text
    end
    log("transformation refused (%s): %s", tostring(why), text)
    if now - refused_at >= S.REFUSE_EVERY then
        refused_at = now
        GSA1.Chat("%s", text)
    end
    return false, text
end

-- the game's request in C's world (gsa1.SuperOrder); why: the cause for the log ("the key", "the command", ...)
function S.Order(C, order, why)
    if not C or not have() then return false, REFUSE_TEXT.module end
    local ok, err, code = gsa1.SuperOrder(C.id, order)
    if not ok then
        log("%s: the order %d (%s) failed: %s (%s)", C.title or "?", order, tostring(why), tostring(err), tostring(code))
        return false, err
    end
    C.superAsked = { order = order, why = why, at = SysTime() }
    return true
end

-- one form order per frame for a character (review RC11: the key and the gesture share this latch, so one press is one
-- transformation and one voice); act "super" / "normal"; st: the state it was decided on (its mode: a change in the jump
-- uses the jump up, C.gesture.jumpUsed). The latch also holds for S.ORDER_GAP after an order, longer than one game pair, so
-- the world has applied an order before the next one goes out (0.9.3a verifier: NORMAL then SUPER with no pair between left
-- two aura and two physics tasks running).
S.ORDER_GAP = 0.05
function S.OrderForm(C, act, why, st)
    if C.superOrderFrame == FrameNumber() then return false, "one form change per frame" end
    if C.superOrderAt and SysTime() - C.superOrderAt < S.ORDER_GAP then return false, "one form change per game step" end
    local ord = act == "super" and S.Const("ORDER_SUPER") or S.Const("ORDER_NORMAL")
    local ok, err = S.Order(C, ord, why)
    if not ok then return false, err end
    C.superOrderFrame = FrameNumber()
    C.superOrderAt = SysTime()
    -- a clip plays only for a real change (not Super yet in the state the order was decided on; review 0.9.3b, 1)
    if act == "super" and cv.voice:GetInt() >= S.VOICE_CLIP and not (st and st.super) then
        local vok, verr = S.PlayVoice(cv.voice:GetInt(), C.id)
        if not vok and not S.voiceFailLogged then
            S.voiceFailLogged = true
            log("the transformation voice %d did not play: %s", cv.voice:GetInt(), tostring(verr))
        end
    end
    if st and tonumber(st.mode) == S.K.MODE_JUMP then
        C.gesture = C.gesture or { held = false, masked = false, jumpUsed = false }
        C.gesture.jumpUsed = true
    end
    log("%s (%s): %s asked by %s (%d rings, %.0f HU/s, mode %d)", C.title or "?", S.FormName(C, st), act == "super" and
        "the Super transformation" or "back to normal Sonic", tostring(why), st and tonumber(st.rings) or 0,
        st and tonumber(st.speed) or 0, st and tonumber(st.mode) or -1)
    return true
end

-- the transformation key / button / command: Super with enough rings in the jump, back to normal Sonic when Super
function S.Press(C, how)
    C = C or GSA1.Char
    if not C then return false, "no character" end
    local st = S.State(C)
    local need = cv.need:GetInt()
    local act, why = S.KeyAction(st, need, C.death ~= nil)
    if not act then return refuse(C, why, need, st and st.rings) end
    return S.OrderForm(C, act, how or "the key", st)
end

-- the key and the controller button, edge-triggered, before every tick (GSA1PreTick); not while a panel or the chat has
-- the input (GSA1.InputBlocked: the Character Select chooser; the cursor; typing)
S.keyDown, S.cmdDown = false, false
function S.InputBusy()
    if GSA1.InputBlocked and GSA1.InputBlocked() then return true end
    if vgui.CursorVisible() or gui.IsGameUIVisible() then return true end
    local ply = LocalPlayer()
    return IsValid(ply) and ply.IsTyping ~= nil and ply:IsTyping() == true
end
function S.KeyDown()
    if S.cmdDown then return true end
    if S.InputBusy() then return false end
    local k = cv.key:GetInt()
    if k > 0 and input and input.IsButtonDown and input.IsButtonDown(k) then return true end
    local b = cv.pad:GetInt()
    local p = GSA1.pad
    if b > 0 and p and p.connected and band(tonumber(p.raw) or 0, b) ~= 0 then return true end
    return false
end
function S.KeyThink(C)
    local down = S.KeyDown()
    if down and not S.keyDown then S.Press(C, S.cmdDown and "the command +gsa1_super" or "the key") end
    S.keyDown = down
end

concommand.Add("gsa1_super", function()
    local C = GSA1.Char
    if not C then
        GSA1.Chat("Super transformation: no character (spawn Sonic or Super Sonic first)")
        return
    end
    S.Press(C, "the command gsa1_super")
end, nil, "G-SA1: Sonic with enough rings turns Super in a jump, Super Sonic turns back (bind a key to it)")
concommand.Add("+gsa1_super", function() S.cmdDown = true end, nil, "G-SA1: the Super transformation key (hold-style)")
concommand.Add("-gsa1_super", function() S.cmdDown = false end)

hook.Add("GSA1PreTick", "gsa1_super", function(C)
    if not C or not have() then return end
    if C.kind ~= S.KIND and C.kind ~= S.KIND_SONIC then
        S.keyDown = false          -- other characters: the key is not theirs (the command still answers)
        return
    end
    S.KeyThink(C)
end)

-- the gesture (0.9.3a; design 6.3 with the review's RC2 / RC3), through cl_character.lua's seam GSA1.FilterButtons: the
-- player's own buttons (keyboard and controller; the interact key's presses come after this) before every tick. A NEW
-- press of the action button while the last tick's state is the jump (mode 8), in a world that can turn Super, asks
-- S.GestureAction; when it says "super" (or "normal": a General Super Sonic, gsa1_super_gesture_back) the form is ordered
-- (the shared latch, S.OrderForm), and that press is kept from the game until the button is released - the game never
-- sees it (no air action, no spin dash when he lands with it held) - and the rest of this jump changes nothing more.
-- Everything else goes through unchanged: other characters, a Sonic who cannot turn Super, too few rings (Sonic's own air
-- action; no chat line), a Vs. Perfect Chaos Super Sonic (the game's air stop).
function S.ActionBit()
    return tonumber(gsa1 and gsa1.BUTTON_ACTION) or 2
end
function S.Filter(C, buttons)
    if not C or (C.kind ~= S.KIND and C.kind ~= S.KIND_SONIC) or not have() then return buttons end
    local g = C.gesture
    if not g then
        g = { held = false, masked = false, jumpUsed = false }
        C.gesture = g
    end
    local A = S.ActionBit()
    local down = band(buttons, A) ~= 0
    if g.masked then
        if down then
            g.held = true
            return band(buttons, bnot(A))
        end
        g.masked = false
    end
    local edge = down and not g.held
    g.held = down
    local st = S.State(C)
    if not st or not st.capable then return buttons end
    if tonumber(st.mode) ~= S.K.MODE_JUMP then g.jumpUsed = false end
    if edge and tonumber(st.mode) == S.K.MODE_JUMP and not g.jumpUsed and not C.death and not S.InputBusy() then
        local want = S.GestureAction(st, S.Options())
        if want and S.OrderForm(C, want, "the action button in the jump", st) then
            g.masked, g.jumpUsed = true, true
            return band(buttons, bnot(A))
        end
    end
    return buttons
end
-- the seam's function before this file (kept across a reload of this file: S survives it)
S.prevFilter = S.prevFilter or GSA1.FilterButtons
GSA1.FilterButtons = function(C, buttons)
    local b = S.Filter(C, buttons)
    if S.prevFilter then b = S.prevFilter(C, b) end
    return b
end

-- 5. the form after every tick: the log, a chat line when the rings run out ------------------------------------------------
local function cause_of(C, st, super)
    local asked = C.superAsked
    C.superAsked = nil
    if asked and SysTime() - asked.at < 2 and asked.order == (super and S.Const("ORDER_SUPER") or S.Const("ORDER_NORMAL")) then
        return asked.why
    end
    if super then
        if C.superStartCause and (C.superCount or 0) == (C.superCountAtCreate or 0) then return C.superStartCause end
        if C.kind == S.KIND and (C.superCount or 0) == (C.superCountAtCreate or 0) and not C.startedNormal then
            return "the game's own trigger, as on Perfect Chaos"
        end
        return "the game"
    end
    if C.death then return "the death" end
    if (tonumber(st.rings) or 0) <= 0 then return "the rings ran out (the game's drain)" end
    return "the game"
end

function S.OnForm(C, st)
    local super = st.super == true
    local was = C.superForm == true
    C.superForm = super
    if was == super then return end
    local why = cause_of(C, st, super)
    C.superSince = SysTime()
    local form = S.FormName(C, st)
    if super then
        C.superCount = (C.superCount or 0) + 1
        if S.music then S.music.yielded, S.music.failed, S.music.noted = false, nil, nil end   -- a new transformation
        log("%s turned Super (%s) at step %d: %d rings, %.0f HU/s; the %s form%s", C.title or "?", why,
            tonumber(st.change_step) or 0, tonumber(st.rings) or 0, tonumber(st.speed) or 0, form,
            C.kind == S.KIND_SONIC and " (Sonic's own moves; speed and facing kept)" or "")
    else
        C.superReverted = true
        log("%s turned back into normal Sonic (%s) at step %d: %d rings, %.0f HU/s; the %s form", C.title or "?", why,
            tonumber(st.change_step) or 0, tonumber(st.rings) or 0, tonumber(st.speed) or 0, form)
        -- (0.9.3b owner note: "remove the chat message that says 'the rings ran out, back to normal Sonic'. It doesn't need
        -- to exist." - the log line above keeps it)
    end
    if GSA1.RunHook then GSA1.RunHook("GSA1SuperForm", C, super, why) end
end

hook.Add("GSA1PostTick", "gsa1_super", function(C, state, dt)
    if not C or not have() then return end
    if C.kind ~= S.KIND and C.kind ~= S.KIND_SONIC then return end
    local st = S.State(C)
    if not st then return end
    C.superCapable = st.capable == true
    C.superGeneral = st.general == true
    C.superRings = tonumber(st.rings)
    if (st.super == true) ~= (C.superForm == true) then S.OnForm(C, st) end
end)

-- a new character: its census rows before its pre-warm starts (cl_character.lua runs this hook first), the options that
-- apply at once, the log. Review RC1: the form of a re-created character was decided by its create extras (S.ExtrasFor:
-- SA1_SUPER_START / SA1_SUPER_START_NORMAL), so nothing is ordered here; the count of transformations goes over to it.
hook.Add("GSA1CharacterCreated", "gsa1_super", function(C, how, old)
    if not C then return end
    S.ApplyWarm(C.kind, C)
    if not have() or (C.kind ~= S.KIND and C.kind ~= S.KIND_SONIC) then return end
    C.superForm = false
    if how == "re-created" and type(old) == "table" then
        C.superCount, C.superReverted = old.superCount, old.superReverted
    end
    C.superCountAtCreate = C.superCount or 0
    local st = S.State(C)
    C.superCapable = st ~= nil and st.capable == true
    C.superGeneral = st ~= nil and st.general == true
    local ex = C.extras
    local sf = ex and tonumber(ex.super_flags) or 0
    C.superStartCause = nil
    C.startedNormal = band(sf, S.Const("START_NORMAL")) ~= 0
    if band(sf, S.Const("START")) ~= 0 then
        C.superStartCause = how == "re-created" and "the re-creation (he was Super)" or "the start (Super from his first pair)"
    end
    local opts = S.ApplyOptions(C)
    -- 0.9.4a: the aura's whoosh (the setting reached the module at its load: S.ApplyWhoosh; again here if it did not)
    local wh = S.whoosh or {}
    if have_whoosh() and wh.applied ~= cv.whoosh:GetBool() then S.ApplyWhoosh("a character was made") end
    local sw = S.State(C)
    if sw and sw.whoosh then
        wh.since = wh.since or SysTime()
        log("the aura's whoosh: from the Perfect Chaos sound bank (CHAOS7B.MLT bank 5) for %s #%s", C.title or "?",
            tostring(C.id))
    end
    if C.kind == S.KIND then
        log("%s %s: Super Sonic's world (the Vs. Perfect Chaos form; super flags 0x%X, create flags 0x%X, start rings %s)%s"
            .. "; %d options", C.title or "?", how or "created", sf, ex and ex.create_flags or 0,
            ex and ex.start_rings ~= nil and tostring(ex.start_rings) or "the game's 50",
            band(sf, S.Const("START_NORMAL")) ~= 0 and "; he had turned back: he starts as normal Sonic" or "", opts)
    elseif C.superGeneral then
        log("%s %s: the General form (super flags 0x%X%s), can turn Super with %d rings; %d options", C.title or "?",
            how or "created", sf, C.superStartCause and ", Super from his first pair" or "", cv.need:GetInt(), opts)
    else
        log("%s %s: %s", C.title or "?", how or "created", C.superCapable and string.format("can turn Super with %d rings "
            .. "(super flags 0x%X)", cv.need:GetInt(), sf) or "the Super transformation is off")
    end
    -- a module before 0.9.3a (no General form): a Sonic re-created while Super is ordered Super again, as in 0.9.3
    if not have_general() and how == "re-created" and old and old.superForm and C.kind == S.KIND_SONIC and C.superCapable then
        S.Order(C, S.Const("ORDER_SUPER"), "the re-creation (he was Super)")
    end
end)

-- 6. options: those that change a world re-create the current character where it stands a moment later (as the
-- upgrades); the others apply at once (S.ApplyOptions)
local recreate_at, recreate_why = nil, nil
-- which: "vspc" (Super Sonic (Vs. Perfect Chaos)), "general" (a General world: the General entry, a Sonic who can
-- transform), "sonic" (Sonic's own entry)
local function option_changed(name, which)
    return function(_, _, new)
        log("%s = %s", name, tostring(new))
        local C = GSA1.Char
        if not C then return end
        local mine = (which == "vspc" and C.kind == S.KIND) or (which == "general" and C.kind == S.KIND_SONIC and
            (C.superGeneral or S.IsGeneralDef(C.def))) or (which == "sonic" and C.kind == S.KIND_SONIC and
            not S.IsGeneralDef(C.def))
        if mine then
            recreate_at = SysTime() + S.RECREATE_DELAY
            recreate_why = "Super Sonic's options changed (" .. name .. ")"
        end
    end
end
cvars.AddChangeCallback("gsa1_super_drain", option_changed("gsa1_super_drain", "vspc"), "gsa1_super")
cvars.AddChangeCallback("gsa1_super_keep", option_changed("gsa1_super_keep", "vspc"), "gsa1_super")
cvars.AddChangeCallback("gsa1_super_faithful_revert", option_changed("gsa1_super_faithful_revert", "vspc"), "gsa1_super")
cvars.AddChangeCallback("gsa1_super_water", option_changed("gsa1_super_water", "vspc"), "gsa1_super")
cvars.AddChangeCallback("gsa1_super_general_drain", option_changed("gsa1_super_general_drain", "general"), "gsa1_super")
cvars.AddChangeCallback("gsa1_super_general_keep", option_changed("gsa1_super_general_keep", "general"), "gsa1_super")
cvars.AddChangeCallback("gsa1_super_general_water", option_changed("gsa1_super_general_water", "general"), "gsa1_super")
cvars.AddChangeCallback("gsa1_super_transform", option_changed("gsa1_super_transform", "sonic"), "gsa1_super")
local AT_ONCE = { gsa1_super_general_speed = "speed", gsa1_super_general_aura = "aura",
                  gsa1_super_general_effects = "effects", gsa1_super_voice = "voice", gsa1_super_idle_by_form = "idle",
                  gsa1_super_aura_anim = "aura_anim",
                  -- 0.9.4a
                  gsa1_super_general_anims = "anims", gsa1_super_general_lsd_gold = "lsd" }
for name, what in pairs(AT_ONCE) do
    cvars.AddChangeCallback(name, function(_, _, new)
        local n = S.ApplyOptions(GSA1.Char, what)
        log("%s = %s%s", name, tostring(new), n > 0 and " (applied at once)" or "")
    end, "gsa1_super")
end
for _, name in ipairs({ "gsa1_super_rings", "gsa1_super_transform_rings", "gsa1_super_music", "gsa1_super_music_track",
                        "gsa1_super_general_rings", "gsa1_super_gesture", "gsa1_super_gesture_back" }) do
    cvars.AddChangeCallback(name, function(_, _, new) log("%s = %s", name, tostring(new)) end, "gsa1_super")
end
function S.RecreateThink(now)
    if recreate_at and now >= recreate_at then
        recreate_at = nil
        if GSA1.Char and GSA1.Recreate then GSA1.Recreate(recreate_why) end
    end
end
function S.RecreatePending() return recreate_at ~= nil end

-- the page's voice Preview (gsa1_super_voice_preview [tone]): the tone once through the mixer, without transforming
function S.PreviewVoice(tone)
    tone = math.floor(tonumber(tone) or cv.voice:GetInt())
    if tone <= 0 then
        GSA1.Chat("Super Sonic's voice: none is chosen")
        return false
    end
    if not (have() and gsa1.SuperVoicePreview) then
        GSA1.Chat("%s", REFUSE_TEXT.module)
        return false
    end
    local C = GSA1.Char
    local ok, err = S.PlayVoice(tone, C and C.id or nil)
    log("voice preview %d (%s): %s", tone, S.ChoiceTitle(S.VOICE_CHOICES, tone), ok and "played" or tostring(err))
    if not ok then GSA1.Chat("voice preview: %s", tostring(err)) end
    return ok
end
concommand.Add("gsa1_super_voice_preview", function(_, _, args) S.PreviewVoice(args and args[1]) end, nil,
    "G-SA1: play Super Sonic's transformation voice (gsa1_super_voice, or the tone given) once")

-- 6b. the aura's whoosh (0.9.4a; sadc docs/research/super2_plan.md 6.4 tasks 5 / 6, super2_sound.md 7) -----------------------
-- gsa1.SuperWhoosh(on): every super-capable character's whoosh (1035 above speed 7, 1036 above 13) from the Perfect Chaos
-- stage's sound bank on the disc through libsa1's stage rules, at once; applied when the module loads and when the setting
-- changes. The game plays it from the aura: no aura (the General form's "Aura" off), no whoosh (owner answer O7's default).
S.whoosh = S.whoosh or { applied = nil, since = nil, noted = nil, next = 0, preview = nil, info = {} }
local WH = S.whoosh
function S.ApplyWhoosh(why)
    if not have_whoosh() then return false end
    local on = cv.whoosh:GetBool()
    local ok, err, code = gsa1.SuperWhoosh(on)
    WH.applied = on
    if why then
        log("the aura's whoosh %s (%s)%s", on and "on" or "off", why, ok and "" or string.format(": %s (%s)", tostring(err),
            tostring(code)))
    end
    return ok == true
end
cvars.AddChangeCallback("gsa1_super_whoosh", function(_, _, new)
    S.ApplyWhoosh("gsa1_super_whoosh = " .. tostring(new) .. ", applied at once")
end, "gsa1_super")
-- the module's load (GSA1.LoadModule, cl_module.lua): the setting goes to the module before any character is made
if not S.loadWrapped and GSA1.LoadModule then
    S.loadWrapped = true
    local prev_load = GSA1.LoadModule
    GSA1.LoadModule = function(...)
        local had = GSA1.mod ~= nil
        local ok, err = prev_load(...)
        if ok and not had and GSA1.mod ~= nil and S.ApplyWhoosh then
            local okw, werr = pcall(S.ApplyWhoosh, "the module loaded")
            if not okw then log("the aura's whoosh: %s", tostring(werr)) end
        end
        return ok, err
    end
end
-- (a module loaded before this file - a Lua refresh - gets the setting now)
if GSA1.mod ~= nil and have_whoosh() and WH.applied == nil then
    S.ApplyWhoosh("the feature loaded")
end

-- the whoosh's line for the page and the session log
function S.WhooshText(inf)
    inf = inf or S.Info() or {}
    if not have_whoosh() or inf.whoosh == false then return "kept silent (this module's libsa1 has no stage rules)" end
    if not cv.whoosh:GetBool() then return "off" end
    local bank = tostring(inf.whoosh_bank or "absent")
    if bank == "failed" then return "could not be read from the disc: silent" end
    if bank == "ready" then return "played (Perfect Chaos sound bank: ready)" end
    if bank == "loading" then return "played (Perfect Chaos sound bank: loading)" end
    if bank == "closed" then return "played (Perfect Chaos sound bank: read when the sound banks are open)" end
    return "played (Perfect Chaos sound bank: read when a Super Sonic appears)"
end

-- once a session: the Perfect Chaos stage's banks are ready, or could not be read (watched from the first character whose
-- whoosh is routed until one of the two)
function S.WhooshThink(now)
    if WH.noted or not WH.since or now < WH.next or not have_whoosh() then return end
    WH.next = now + 0.1
    local inf = gsa1.SuperInfo(WH.info)
    local bank = type(inf) == "table" and inf.whoosh_bank or nil
    if bank == "ready" then
        WH.noted = "ready"
        log("Perfect Chaos sound bank ready in %.0f ms (the aura's whoosh, CHAOS7B.MLT bank 5)", (now - WH.since) * 1000)
    elseif bank == "failed" then
        WH.noted = "failed"
        log("Perfect Chaos sound bank (CHAOS7B.MLT bank 5) could not be read: the whoosh stays silent")
    end
end

-- the page's Preview: the slower whoosh (1035) once as the local character's own sound (Session::preview_sound: its stage
-- rule makes it the Perfect Chaos bank's); without a Super-capable character the page's status says why (no chat)
function S.PreviewWhoosh()
    local C = GSA1.Char
    local ok, text = false, nil
    if not (have() and gsa1.SuperVoicePreview) then
        text = REFUSE_TEXT.module
    elseif not C or not C.id or not (C.kind == S.KIND or C.superCapable) then
        text = "no Super Sonic to play it: the whoosh is Super Sonic's (spawn one, or turn on Sonic's Super transformation)"
    elseif not cv.whoosh:GetBool() then
        text = "\"Aura whoosh sounds\" is off: tick it to hear the whoosh"
    else
        local err
        ok, err = gsa1.SuperVoicePreview(S.Const("WHOOSH_SLOW"), C.id)
        text = ok and string.format("played the whoosh (%d) for %s", S.Const("WHOOSH_SLOW"), C.title or "?") or
            ("not played: " .. tostring(err))
    end
    WH.preview = { text = text, at = RealTime() }
    log("whoosh preview: %s", text)
    return ok == true, text
end
concommand.Add("gsa1_super_whoosh_preview", function() S.PreviewWhoosh() end, nil,
    "G-SA1: play Super Sonic's aura whoosh once (needs a Super-capable character: Super Sonic, or Sonic with the Super "
    .. "transformation on)")

-- the session summary (cl_log.lua GSA1.LogSummary): one "super" line about the whoosh's stage rules before the summary
function S.SoundSummaryLine()
    if not have_whoosh() then return nil end
    local inf = gsa1.SuperInfo({}) or {}
    return string.format("sound: stage rules: %d characters, stage %d %s; stage tones kept out: %d; the aura's whoosh %s",
        tonumber(inf.whoosh_characters) or 0, S.Const("WHOOSH_STAGE"), tostring(inf.whoosh_bank or "?"),
        tonumber(inf.tones_muted) or 0, cv.whoosh:GetBool() and "on" or "off")
end
if not S.summaryWrapped and GSA1.LogSummary then
    S.summaryWrapped = true
    local prev_summary = GSA1.LogSummary
    GSA1.LogSummary = function(...)
        if not WH.summarized and GSA1.mod and S.SoundSummaryLine then
            WH.summarized = true
            local okl, line = pcall(S.SoundSummaryLine)
            if okl and line then log("%s", line) end
        end
        return prev_summary(...)
    end
end

-- 7. music while Super (the jukebox engine, feat/cl_jukebox.lua's player GSA1.JukeboxPlayer) ---------------------------------
-- The track plays on the engine's channel S.MUSIC_CH from the moment the character is Super until he is not (or is gone);
-- the personal jukebox (channel 0) is paused meanwhile and goes on afterwards; starting it yourself ends the Super music
-- (your choice wins) until the next transformation. While the personal jukebox has a track (playing or paused) its own
-- Think hands the engine the listener, the volumes, the pause and the step aside for the game's jingles (every channel);
-- otherwise this does the same (sh_jukebox.lua's J.Hold* rules, the jukebox page's settings).
S.music = S.music or { playing = nil, failed = nil, yielded = false, pausedPersonal = false, gain = 1, holdT = nil,
                       duck = false, noted = nil }
local M = S.music

local function jukebox()
    local P = GSA1.JukeboxPlayer
    if not P or not P.Ready then return nil end
    return P
end

-- the music number the character should have now (nil: none)
function S.MusicWanted(C)
    if not C or not C.superForm or not GSA1.cv.sound:GetBool() then return nil end
    return S.MusicNumber(cv.music:GetInt(), cv.track:GetInt())
end

local function note_once(fmt, ...)
    local text = string.format(fmt, ...)
    if M.noted == text then return end
    M.noted = text
    log("music: %s", text)
end

function S.MusicStop(why, fade)
    local P = jukebox()
    if M.playing ~= nil and have() and gsa1.JukeboxStop then gsa1.JukeboxStop(S.MUSIC_CH, fade or 1.0) end
    if M.playing ~= nil then log("music %d stops (%s)", M.playing, why or "?") end
    M.playing = nil
    if M.duck and gsa1 and gsa1.AudioDuck then
        gsa1.AudioDuck(1, false)
        M.duck = false
    end
    if M.pausedPersonal and P and P.current ~= nil and P.paused then P.Pause(false) end
    M.pausedPersonal = false
end

function S.MusicStart(want)
    local P = jukebox()
    local ok, why = false, "the jukebox page is not loaded"
    if P then ok, why = P.Ready() end
    if not ok then
        M.failed = want
        note_once("music %d cannot play: %s", want, tostring(why))
        return false
    end
    local tracks, msg = P.Tracks()
    if not tracks then
        if msg ~= "loading" then
            M.failed = want
            note_once("music %d cannot play: %s", want, tostring(msg))
        end
        return false                                       -- the list loads: again next frame
    end
    local t = P.by and P.by[want]
    if not t then
        M.failed = want
        note_once("there is no track %d on the disc", want)
        return false
    end
    if P.current ~= nil and not P.paused then
        P.Pause(true)
        M.pausedPersonal = true
    end
    gsa1.JukeboxVolume(S.MUSIC_CH, math.Clamp(P.cv.volume:GetFloat(), 0, 1))
    local res, err = gsa1.JukeboxPlay(S.MUSIC_CH, want, 0, "forever", 2, 0.5, 0)
    if not res then
        M.failed = want
        note_once("music %d %s refused: %s", want, tostring(t.file), tostring(err))
        if M.pausedPersonal then P.Pause(false) end
        M.pausedPersonal = false
        return false
    end
    M.playing, M.failed, M.gain, M.holdT = want, nil, 1, nil
    log("music %d %s plays while Super (channel %d)%s", want, tostring(t.file), S.MUSIC_CH,
        M.pausedPersonal and "; the personal jukebox is paused" or "")
    return true
end

-- the engine's frame update when the personal jukebox's Think does not make it (cl_jukebox.lua update())
local ms_out = {}
function S.MusicUpdate(now)
    local P = jukebox()
    if not P or not have() or not gsa1.JukeboxUpdate then return end
    if P.current ~= nil or (P.duckGain or 1) < 1 or now < (P.quietUntil or 0) then return end
    local v = GSA1.view
    local origin, ang
    if v and v.frame and v.origin and v.angles and FrameNumber() - v.frame <= 2 then
        origin, ang = v.origin, v.angles
    else
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        origin, ang = ply:EyePos(), ply:EyeAngles()
    end
    local pcv = P.cv
    local paused = false
    if not pcv.background:GetBool() then
        local focus = GetConVar("snd_mute_losefocus")
        paused = FrameTime() == 0 or (game.SinglePlayer() and gui.IsGameUIVisible()) or
            (focus ~= nil and focus:GetBool() and not system.HasFocus())
    end
    local music = 1
    local smv = GetConVar("snd_musicvolume")
    if pcv.gmod_music:GetBool() and smv then music = math.Clamp(smv:GetFloat(), 0, 1) end
    -- the game's jingles: the same step aside as the personal jukebox (sh_jukebox.lua)
    local J = GSA1.Jukebox
    local factor, hold = 1, false
    if J and J.HoldReason and gsa1.AudioMusicState then
        local ms = gsa1.AudioMusicState(ms_out)
        local hwhy = J.HoldReason(type(ms) == "table" and ms or nil, false)
        local mode = pcv.jingle:GetInt()
        if mode == J.HOLD_KEEP then hwhy = nil end
        local dt = M.holdT and math.Clamp(now - M.holdT, 0, 0.25) or 0
        M.holdT = now
        M.gain = J.HoldGain(M.gain, hwhy ~= nil, dt)
        factor, hold = J.HoldApply(mode, M.gain)
    end
    local n = tonumber(gsa1.JukeboxUpdate(origin, ang:Forward(), ang:Up(), GetConVar("volume") and
        GetConVar("volume"):GetFloat() or 1, music * factor, (paused or hold) and true or false)) or 0
    -- the game's own music silenced while the Super music is heard (the jukebox page's setting)
    local want_duck = pcv.duck:GetBool() and n > 0
    if want_duck ~= M.duck and gsa1.AudioDuck then
        gsa1.AudioDuck(want_duck and 0 or 1, pcv.duck_jingles:GetBool())
        M.duck = want_duck
    end
end

function S.MusicThink(now)
    local C = GSA1.Char
    local want = S.MusicWanted(C)
    if want == nil then
        M.yielded, M.failed = false, nil
    end
    local P = jukebox()
    -- you started the personal jukebox while the Super music played: yours wins until the next transformation
    if M.playing ~= nil and P and P.current ~= nil and not P.paused then
        M.pausedPersonal = false
        S.MusicStop("the personal jukebox started")
        M.yielded = true
        return
    end
    if M.yielded or (want ~= nil and want == M.failed) then want = nil end
    if want ~= M.playing then
        if M.playing ~= nil then S.MusicStop(C and (C.superForm and "another track" or "not Super any more") or
            "the character is gone") end
        if want ~= nil then S.MusicStart(want) end
    end
    if M.playing ~= nil then S.MusicUpdate(now) end
end

hook.Add("GSA1CharacterRemoved", "gsa1_super", function(C, switching)
    if M.playing ~= nil then S.MusicStop("the character is gone") end
end)

-- every frame: the option re-creation, the music (nothing to do while neither is wanted)
local function think()
    local now = SysTime()
    S.RecreateThink(now)
    S.WhooshThink(now)
    if M.playing ~= nil or (GSA1.Char and GSA1.Char.superForm and cv.music:GetInt() ~= S.MUSIC_OFF) then
        S.MusicThink(now)
    end
end
hook.Add("Think", "gsa1_super", GSA1.Guard and GSA1.Guard("Super", think) or think)

-- 8. the Super Sonic page (Q -> Options -> G-SA1 -> Super Sonic) ---------------------------------------------------------
-- the transformation key's name ("G", "none")
function S.KeyName()
    local k = cv.key:GetInt()
    if k <= 0 then return "none" end
    local name = input and input.GetKeyName and input.GetKeyName(k)
    return string.upper(tostring(name or k))
end

-- the page's live lines
function S.StatusLines()
    local out = {}
    if not have() then
        out[1] = GSA1.MissingFeatureText and GSA1.MissingFeatureText(S.NEEDS) or "the module has no Super Sonic"
        return out
    end
    local inf = S.Info(true) or {}
    out[#out + 1] = string.format("Super Sonic in the character list: %s; the General form: %s; Sonic's Super forms: %s; "
        .. "the aura's whoosh: %s", inf.playable and "yes" or "no (the module or libsa1 is too old)",
        (inf.general and have_general()) and "yes" or "no (the module is older than 0.9.3a)",
        inf.forms and "loaded (the transformation can work)" or (inf.ready and "not loaded" or "the disc is not loaded yet"),
        S.WhooshText(inf))
    local C = GSA1.Char
    local need = cv.need:GetInt()
    if C and (C.kind == S.KIND or C.kind == S.KIND_SONIC) then
        local st = S.State(C)
        if st then
            local rings = tonumber(st.rings) or 0
            local form = st.capable and S.FormName(C, st) or "normal Sonic"
            out[#out + 1] = string.format("%s (the %s form): %s, %d rings%s, %.0f HU/s; %d transformation%s so far%s",
                C.title or "?", form, st.super and "Super" or "normal Sonic", rings,
                (not st.super and st.capable) and (rings >= need and string.format(" (enough: %d needed)", need) or
                string.format(" (needs %d rings: %d now)", need, rings)) or "", tonumber(st.speed) or 0, C.superCount or 0,
                (C.superCount or 0) == 1 and "" or "s", st.capable and "" or " (this Sonic cannot turn Super)")
            if st.general then
                out[#out + 1] = string.format("speed: %s; aura %s; golden trail %s; poses: %s; golden Light Speed: %s",
                    S.ChoiceTitle(S.SPEED_CHOICES, cv.general_speed:GetInt()), cv.general_aura:GetBool() and "on" or "off",
                    cv.general_effects:GetBool() and "on" or "off",
                    (cv.general_anims:GetBool() and have_polish()) and "the game's" or "Sonic's",
                    (cv.general_lsd_gold:GetBool() and have_polish()) and "on" or "off")
            end
        end
    elseif C then
        out[#out + 1] = string.format("%s cannot turn Super (only Sonic)", C.title or "?")
    else
        out[#out + 1] = "no character"
    end
    out[#out + 1] = string.format("to turn Super: jump, then the action button in the air%s; the key %s%s; needs %d rings",
        cv.gesture:GetBool() and "" or " (off)", S.KeyName(), cv.pad:GetInt() > 0 and (", the controller's " ..
        S.PadTitle(cv.pad:GetInt()) .. " (in the jump)") or " (no controller button)", need)
    -- 0.9.4a: the whoosh's Preview said why it was silent (no Super-capable character, the option off)
    local wp = S.whoosh and S.whoosh.preview
    if wp and RealTime() - (wp.at or 0) < 15 then
        out[#out + 1] = "whoosh preview: " .. tostring(wp.text)
    end
    if M.playing ~= nil then
        out[#out + 1] = string.format("music while Super: track %d (channel %d)", M.playing, S.MUSIC_CH)
    elseif cv.music:GetInt() ~= S.MUSIC_OFF then
        out[#out + 1] = "music while Super: " .. (M.yielded and "your personal jukebox has it now" or (M.noted or
            "waits for the transformation"))
    end
    return out
end

-- a combo box for a ConVar whose values have titles: it follows the ConVar (also a change from the console)
local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[2], tostring(c[1])) end
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand(cvname, tostring(data))
    end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local c = GetConVar(cvname)
        local v = c and c:GetString() or ""
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        local n = tonumber(v)
        for _, ch in ipairs(choices) do
            if n ~= nil and tonumber(ch[1]) == n then
                self:SetText(ch[2])
                return
            end
        end
        self:SetText(v)
    end
    return combo
end

-- a label that refreshes itself twice a second while visible
local function live_label(panel, lines_fn)
    local lbl = panel:Help("...")
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + 0.5
        local text = table.concat(lines_fn(), "\n")
        if text ~= self.gsa1Text then
            self.gsa1Text = text
            self:SetText(text)
            self:InvalidateLayout(true)
            local parent = self:GetParent()
            if IsValid(parent) then parent:InvalidateLayout() end
        end
    end
    return lbl
end

function S.BuildPage(panel)
    panel:Help("Super Sonic from your disc, in two versions. Pick one like any character, or let Sonic turn Super in a "
        .. "jump with enough rings.")
    -- Vs. Perfect Chaos
    panel:Help("Super Sonic (Vs. Perfect Chaos)")
    panel:ControlHelp("The game's own Super Sonic, exactly as in the last fight: golden with his aura, faster, a hit only "
        .. "slows him down; run, jump, homing attack, the air stop (no spin dash, no Light Speed Dash).")
    panel:Button("Spawn / switch to Super Sonic (Vs. Perfect Chaos)", "gsa1_spawn", "supersonic")
    panel:NumSlider("Start with N rings", "gsa1_super_rings", 0, 99, 0)
    panel:ControlHelp("Like the game's Perfect Chaos: 50. Also after a respawn.")
    panel:CheckBox("Lose a ring every second", "gsa1_super_drain")
    panel:CheckBox("Stay Super when the rings run out", "gsa1_super_keep")
    panel:ControlHelp("Off (the game): at 0 rings he turns back into normal Sonic right where he is and keeps running; "
        .. "with enough rings again he turns Super in a jump (the action button in the air, or the key). On: he stays "
        .. "Super at 0 rings.")
    panel:CheckBox("Keep the game's physics bug after turning back", "gsa1_super_faithful_revert")
    panel:ControlHelp("The Dreamcast restores the wrong values when Super Sonic turns back, so normal Sonic runs slower "
        .. "afterwards. Off (recommended): fixed.")
    panel:CheckBox("Run on water", "gsa1_super_water")
    panel:ControlHelp("Changing one of these re-creates him where he stands (his rings stay; after he turned back he "
        .. "stays normal Sonic).")
    -- General Gameplay
    panel:Help("Super Sonic (General Gameplay)")
    panel:ControlHelp("Super Sonic who plays like Sonic: spin dash, homing attack, Light Speed Dash with the shoes, "
        .. "carrying - golden, faster, and a hit only slows him down. Sonic's upgrades are his too.")
    panel:Button("Spawn / switch to Super Sonic (General Gameplay)", "gsa1_spawn", "supersonic_general")
    panel:NumSlider("Start with N rings", "gsa1_super_general_rings", 0, 99, 0)
    panel:CheckBox("Lose a ring every second", "gsa1_super_general_drain")
    panel:CheckBox("Stay Super when the rings run out", "gsa1_super_general_keep")
    panel:ControlHelp("Off: at 0 rings he turns back into Sonic and can turn Super again in a jump with enough rings.")
    choice_combo(panel, "Speed", "gsa1_super_general_speed", S.SPEED_CHOICES)
    panel:ControlHelp("Super run: the game's Super Sonic's ground values with Sonic's jumps - he picks up speed like "
        .. "Sonic and keeps getting faster on long straights; spin dashes roll much further. The game's Super Sonic: the "
        .. "same on the ground, floaty jumps. Applies at once.")
    panel:CheckBox("Aura", "gsa1_super_general_aura")
    -- 0.9.4a (super2_plan.md 7, owner answers O1 / O3 / O4)
    panel:CheckBox("Super Sonic's own poses (floating stand, flying run)", "gsa1_super_general_anims")
    panel:ControlHelp("The game's Super Sonic animations for standing and moving, as in the Perfect Chaos fight: he floats "
        .. "when he stands and flies when he runs. After standing still a while he taps his foot like Sonic. Jumping, spin "
        .. "dash, braking, pushing and carrying keep Sonic's moves on the golden body. Applies at once.")
    panel:CheckBox("Golden trail, after-images and spin dash sparks", "gsa1_super_general_effects")
    panel:ControlHelp("The game's own golden Super effects for his homing attack, rolls and dashes. The game's spin dash "
        .. "sparks are only blue: G-SA1 gives them the golden texture of the Super after-images (off: Sonic's blue ones). "
        .. "Applies at once.")
    panel:CheckBox("Golden Light Speed Dash", "gsa1_super_general_lsd_gold")
    panel:ControlHelp("The Light Speed charge's sparkles, streaks and glow in Super Sonic's gold while he is Super. The game "
        .. "has them only in Sonic's blue, so G-SA1 colours them gold; with the Crystal Ring the sparkles and streaks stay "
        .. "the game's green. Off: the game's colours. Applies at once.")
    panel:CheckBox("Run on water while Super", "gsa1_super_general_water")
    panel:ControlHelp("Water below him is a floor while he is Super; turning back on it drops him in. Changing the drain, "
        .. "\"stay Super\" or the water re-creates him where he stands. A Sonic who transforms uses these settings too.")
    -- turning Super
    panel:Help("Turning Super (Sonic, and a Super Sonic who turned back)")
    panel:CheckBox("Super transformation", "gsa1_super_transform")
    panel:ControlHelp("Sonic with enough rings turns Super in a jump - keeping his speed - into the General Gameplay form, "
        .. "and back again. Changing it re-creates Sonic where he stands.")
    panel:NumSlider("Rings needed", "gsa1_super_transform_rings", 1, 99, 0)
    panel:CheckBox("Jump, then the action button in the air", "gsa1_super_gesture")
    panel:ControlHelp("The action (spin dash) button pressed in the air turns him Super instead of Sonic's air action; "
        .. "with too few rings it is Sonic's own move (nothing is said in the chat). Standing it is always the crouch / "
        .. "spin dash.")
    panel:CheckBox("The same in a later jump turns him back (General Gameplay)", "gsa1_super_gesture_back")
    panel:Help("Transformation key (now: " .. S.KeyName() .. ")")
    local binder = vgui.Create("DBinder", panel)
    if binder.SetConVar then binder:SetConVar("gsa1_super_key") end
    if binder.SetTall then binder:SetTall(28) end
    panel:AddItem(binder)
    panel:Button("No key (bind gsa1_super yourself)", "gsa1_super_key", "0")
    choice_combo(panel, "Controller button", "gsa1_super_pad", S.PAD_BUTTONS)
    panel:ControlHelp("The key works like the action button: Super only in the jump; back anywhere. Not while a menu or "
        .. "the chat is open. The controller button is \"None\" by default: on the controller the jump + action button "
        .. "gesture turns him Super and back (the right stick click does nothing unless you choose it here).")
    -- both
    panel:Help("Both Super Sonics")
    choice_combo(panel, "Transformation voice", "gsa1_super_voice", S.VOICE_CHOICES)
    local prev = panel:Button("Preview the voice")
    if prev then prev.DoClick = function() S.PreviewVoice() end end
    panel:ControlHelp("Played when you turn him Super (not at the start of a Super Sonic picked from the list). The "
        .. "\"Hm!\" and line 388 are voice lines: \"Character voices\" off (Sound page) mutes them too.")
    choice_combo(panel, "Aura animation", "gsa1_super_aura_anim", S.AURA_CHOICES)
    -- 0.9.4a (super2_plan.md 7, owner answers O8 / O10)
    panel:CheckBox("Aura whoosh sounds", "gsa1_super_whoosh")
    panel:ControlHelp("The game's swoosh when he goes faster than about 1,700 and 3,100 HU/s (two seconds each, again after "
        .. "slowing down), from the Perfect Chaos stage's sound bank on your disc. It comes with the aura: none while the "
        .. "General Gameplay aura is off.")
    local wprev = panel:Button("Preview the whoosh")
    if wprev then wprev.DoClick = function() S.PreviewWhoosh() end end
    panel:CheckBox("Super Sonic's own idle lines while Super", "gsa1_super_idle_by_form")
    panel:ControlHelp("Sonic's own lines while he is normal Sonic. Off: the game's choice.")
    panel:Help("Music while Super")
    choice_combo(panel, "Music", "gsa1_super_music", S.MUSIC_CHOICES)
    panel:NumSlider("Jukebox track (for the last choice)", "gsa1_super_music_track", 0, 255, 0)
    panel:ControlHelp("From your disc, through the jukebox (only you hear it). Your personal jukebox pauses while it "
        .. "plays and goes on afterwards; the jukebox page's volume and settings apply. The Jukebox page lists the track "
        .. "numbers (86 is \"Theme of Super Sonic\").")
    panel:Help("Status")
    live_label(panel, S.StatusLines)
end

GSA1.AddMenuPage(270, "super", "Super Sonic", S.BuildPage, S.NEEDS)
