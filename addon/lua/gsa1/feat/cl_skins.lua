-- G-SA1 skins, the client part (round 0.9.9f; sadc docs/research/metal099e.md 4.6, 5.1, 6; the pure part is feat/sh_skins.lua). A skin is a row of GSA1.CHARACTERS (form "skin", made by K.Register): the Quick
-- spawn button, the list, the menubar and the console name it like anyone. Its world is its base's, byte for byte: this file only gives the module its create extras, the options the render step takes at once and
-- the voice. Loads before feat/cl_super.lua, whose GSA1.CreateExtras wrapper is outermost and returns nil for a skin (S.Extras' first line).
-- 1.0.0 (sadc docs/research/gsa1_100_select.md 6): every skin's options come from its entry (options = the ConVar prefix, defaults = their defaults); Metal Sonic's are 0.9.9f's four and a fifth,
-- the Light Speed trails in the skin's colour (libsa1 SA1_SKIN_ANIM_TRAIL, select 4.3.2); Mecha Sonic's are new (his voice, glow and trails).
-- The owner's answer 17 (rounds plan 14.1bl; gsa1_100_master.md 3's R1 delta with RY.1, RY.13): a skin has only the options its entry's option_keys name (Metal all five, Mecha voice, glow and trail:
-- gsa1_mecha_fly and gsa1_mecha_walk_fly are never made, so no fly box shows); an entry with anim_always (Mecha) has its rows on always: SKIN_ANIM_FLY always, never WALK.
-- 1.0.0-beta1a (lane b1a-mecha; the owner on beta 1: "Mecha Sonic is floating ... his run animation has stuttering and it animates far too fast"): a skin of Sonic's own tree (Mecha) has two more:
-- "plant" (libsa1 SA1_SKIN_ANIM_NO_PLANT when off: D9, his lowest point on the floor every frame) and "jog_pace", a slider (SA1_SKIN_ANIM_PACE: D10, his jog in rows 12 and 13 never faster than this
-- times Sonic's own fastest jog; the slider's top is no limit, beta 1's). Both in the render option's value, at once; a self-check line in the log at every spawn says what libsa1 took.
-- The lane's fix run: the frames between two pairs (half of Garry's Mod's) are libsa1's own now (sa1_character.c's render calls sa1k_frame; libsa1 logs "the 60 Hz frames between two pairs are
-- drawn by sa1k_frame" once a character); the off text says what was MEASURED with the box off (his lowest point from -1.43 to +0.60 SA1 units, about -6 to +2 Garry's Mod units).
GSA1 = GSA1 or {}
local K = GSA1.Skins
if not K then error("gsa1/feat/sh_skins.lua did not load: the skins need it") end

-- the five options of a skin, by their ConVar suffix; the help texts name the skin by its entry's title
K.OPTIONS = {
    { key = "fly", label = "%s: run with Super Sonic's flying", help = "%s: run with Super Sonic's flying (off: Sonic's own run on him). At once, no re-creation",
      page = "Off: Sonic's own run on him. At once, no re-creation." },
    { key = "walk_fly", label = "... and when walking", help = "%s: fly when walking too (Sonic's row 9 becomes Super Sonic's 131): toes may touch for a frame",
      page = "Sonic's slow walk flies too (Super Sonic's slow move): the toes may touch the ground for a frame." },
    { key = "voice", label = "%s: speak with Sonic's voice", help = "%s: speak with Sonic's voice (off: voiceless, sound effects stay). At once",
      page = "Off: voiceless. Sound effects stay either way. At once." },
    { key = "glow", label = "%s: glow when charged", help = "%s: glow when charged, where Sonic's Light Speed glow would draw. At once",
      page = "The model again, slightly larger, in the skin's colour, where Sonic's Light Speed glow would draw. At once." },
    { key = "trail", label = "%s: Light Speed trails in the skin's colour", help = "%s: the Light Speed Dash's sparkles and streaks in the skin's colour (off: the game's blue). At once",
      page = "The charge's sparkles and streaks (also with the Crystal Ring) in the skin's own colour. Off: the game's blue. At once." },
    -- 1.0.0-beta1a: only the entries whose option_keys name them (Mecha Sonic)
    { key = "plant", label = "%s: keep his feet on the floor", help = "%s: keep his feet on the floor while he stands, walks and runs (off: drawn where Sonic's own body would put him, so his shorter legs sink into the floor or stand off it). At once",
      page = "On: his lowest point stays on the floor in every frame while he stands, walks and runs, on slopes too; it only dips where Sonic's own toes dip. Off: drawn where Sonic's own body would put him: his shorter legs then sink up to about 6 units into the floor, or stand up to about 2 units above it. At once." },
    { key = "jog_pace", slider = { 0.5, 2.5, 2 }, label = "%s: jog pace when running fast",
      help = "%s: jog pace when running fast, times Sonic's own fastest jog (1: never faster than Sonic's jog gets; 2.5: no limit, as in beta 1). At once",
      page = "1 (the default): never faster than Sonic's own jog at its fastest (4 jog cycles a second). Lower is slower. At 2.5 there is no limit: the jog speeds up with him, as in beta 1. At once." },
}
K.PACE_FREE = 2.5           -- the slider's top: no limit (libsa1 SA1_SKIN_ANIM_PACE_FREE)
K.PACE_TOP_CPS = 4.0179     -- Sonic's own jog at its fastest, cycles a second (4.2853 of its 32 frames a pair, 30 pairs a second: libsa1 sa1_skin.c SK_OWN_TOP_FRAMES)

-- whether a skin's entry has an option (its option_keys; an entry that lists none has all five, as 0.9.9f's)
function K.HasOption(e, key)
    local keys = e and e.option_keys
    if keys == nil then return true end
    for _, k in ipairs(keys) do
        if k == key then return true end
    end
    return false
end

-- the rows of K.OPTIONS a skin has, in K.OPTIONS' order
function K.OptionsOf(e)
    local out = {}
    for _, o in ipairs(K.OPTIONS) do
        if K.HasOption(e, o.key) then out[#out + 1] = o end
    end
    return out
end

K.cvs = K.cvs or {}          -- [options prefix] = { [key] = ConVar } for the skin's own keys (Metal: fly, walk_fly, voice, glow, trail; Mecha: voice, glow, trail)
local function cvs_for(e)
    local pre = e.options
    if type(pre) ~= "string" or pre == "" then return nil end
    local t = K.cvs[pre]
    if t then return t end
    t = {}
    local d = e.defaults or {}
    for _, o in ipairs(K.OptionsOf(e)) do
        local lo, hi = 0, 1
        if o.slider then lo, hi = o.slider[1], o.slider[2] end
        t[o.key] = GSA1.ConVar("gsa1_" .. pre .. "_" .. o.key, tonumber(d[o.key]) or 0, string.format(o.help, e.title or e.id), lo, hi)
    end
    K.cvs[pre] = t
    return t
end
for _, id in ipairs(K.ORDER) do cvs_for(K.SKINS[id]) end
K.cv = K.cvs.metal or K.cv        -- (0.9.9f's name, Metal Sonic's set)

-- a skin's options (nil: a skin without any; then the defaults of 0.9.9f: fly, glow, voiceless)
function K.CvOf(skin)
    return skin and K.cvs[skin.options or ""] or nil
end

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("skin", fmt, ...) end
end

-- the seam (kept across a reload of this file, as Q.prevExtras is)
K.prevExtras = K.prevExtras or GSA1.CreateExtras
GSA1.CreateExtras = function(kind, how, rings, def, old)
    local skin = K.Of(def)
    if skin then return K.ExtrasFor(skin, gsa1 and gsa1.SUPER) end
    if K.prevExtras then return K.prevExtras(kind, how, rings, def, old) end
    return nil
end

local function on(c, key, default)
    local v = c and c[key]
    if v then return v:GetBool() end
    return default
end

-- the value of the render step's option for a skin: SA1_SKIN_ANIM_FLY, _WALK, _GLOW, and 1.0.0's _TRAIL (only when the module has it). An entry with anim_always (Mecha Sonic, the owner's
-- answer 17): FLY always (in libsa1 the bit that turns an entry's rows on, sa1_skin.c sa1k_step), never WALK; GLOW and TRAIL by its own ConVars
function K.AnimValue(skin)
    local c, sup = K.CvOf(skin), gsa1 and gsa1.SUPER or {}
    local v = 0
    if skin and skin.anim_always then
        v = v + (sup.SKIN_ANIM_FLY or 1)
    elseif on(c, "fly", true) then
        v = v + (sup.SKIN_ANIM_FLY or 1)
        if K.HasOption(skin, "walk_fly") and on(c, "walk_fly", false) then v = v + (sup.SKIN_ANIM_WALK or 2) end
    end
    if on(c, "glow", true) and sup.SKIN_ANIM_GLOW then v = v + sup.SKIN_ANIM_GLOW end
    if on(c, "trail", true) and sup.SKIN_ANIM_TRAIL and skin and skin.trail then v = v + sup.SKIN_ANIM_TRAIL end
    -- 1.0.0-beta1a: D9 off by its box; D10's top in hundredths of Sonic's own fastest jog, the slider's top 2047 (no limit). The bits are libsa1.h's (the module's table may not have them yet)
    if K.HasOption(skin, "plant") and not on(c, "plant", true) then v = v + (sup.SKIN_ANIM_NO_PLANT or 16) end
    if K.HasOption(skin, "jog_pace") then v = v + K.PaceField(K.Pace(skin)) * 2 ^ (sup.SKIN_ANIM_PACE_SHIFT or 8) end
    return v
end

-- the jog's pace of a skin that has the slider, 0.5 .. 2.5 (1 without the ConVar)
function K.Pace(skin)
    local c = K.CvOf(skin)
    local x = c and c.jog_pace and c.jog_pace:GetFloat() or 1
    if x ~= x then x = 1 end
    return math.min(K.PACE_FREE, math.max(0.5, x))
end

-- libsa1's field: hundredths (50 .. 249), 2047 at the slider's top (SA1_SKIN_ANIM_PACE_FREE: no limit)
function K.PaceField(x)
    if x >= K.PACE_FREE - 0.005 then return 2047 end
    return math.max(1, math.min(2046, math.floor(x * 100 + 0.5)))
end

-- the self-check line's words for a skin's feet and jog (nil: the skin has neither option)
function K.CheckText(skin, took, err)
    if not (K.HasOption(skin, "plant") or K.HasOption(skin, "jog_pace")) then return nil end
    local c, x = K.CvOf(skin), K.Pace(skin)
    local pace = x >= K.PACE_FREE - 0.005 and "no limit (as in beta 1)" or string.format("%.2f x Sonic's own fastest jog (%.1f jog cycles a second)", x, x * K.PACE_TOP_CPS)
    return string.format("self-check: %s: keep his feet on the floor %s; jog pace when running fast %s; render option %d %s libsa1 %s", tostring(skin.title or skin.id),
        on(c, "plant", true) and "on" or "off", pace, K.AnimValue(skin), took and "taken by" or ("refused (" .. tostring(err) .. ") by"), tostring(gsa1 and gsa1.LIBSA1_VERSION or "?"))
end

-- the options of the render step, at once and before a new character's first tick
function K.ApplyAnim(C)
    if not (C and C.skin and C.id and gsa1 and gsa1.SetCharOption and gsa1.SUPER and gsa1.SUPER.COPT_SKIN_ANIM) then return false end
    local ok, err, code = gsa1.SetCharOption(C.id, gsa1.SUPER.COPT_SKIN_ANIM, K.AnimValue(C.skin))
    if not ok then log("the running: refused: %s (%s)", tostring(err), tostring(code)) end
    C.skinAnimOk, C.skinAnimErr = ok == true, err      -- 1.0.0-beta1a: for the self-check line
    return ok == true
end

function K.ApplyVoice(C)
    if not (C and C.skin and C.id and gsa1 and gsa1.SetVoiceless) then return false end
    return gsa1.SetVoiceless(C.id, K.Voiceless(C.skin)) == true
end

-- the entry's voice setting, with the owner's option over it
function K.Voiceless(skin)
    return not (skin and skin.voice) and not on(K.CvOf(skin), "voice", false)
end

hook.Add("GSA1CharacterCreated", "gsa1_skins", function(C, how)
    if not (C and C.skin) then return end
    K.ApplyAnim(C)
    K.ApplyVoice(C)
    local c = K.CvOf(C.skin)
    local jog = C.skin.anim_always
    log("%s %s: over Sonic's world; running %s, walking %s, %s, %s, %s", C.title or "?", how or "created",
        jog and "jogs (Sonic's jog where Sonic runs with his arms behind him)" or (on(c, "fly", true) and "flies" or "as Sonic"),
        (not jog and on(c, "fly", true) and on(c, "walk_fly", false)) and "flies" or "as Sonic", K.Voiceless(C.skin) and "voiceless" or "with Sonic's voice",
        on(c, "glow", true) and "glows when charged" or "no glow", on(c, "trail", true) and "trails in its colour" or "the game's blue trails")
    -- 1.0.0-beta1a: once a spawn, what the render step took for his feet and his jog
    local check = K.CheckText(C.skin, C.skinAnimOk, C.skinAnimErr)
    if check then log("%s", check) end
end)

-- 0.9.9h: your character and every follower that wears a skin (feat/cl_follower.lua F.skin), at once
function K.Worn()
    local out = {}
    if GSA1.Char and GSA1.Char.skin then out[#out + 1] = GSA1.Char end
    for _, F in ipairs(GSA1.Followers and GSA1.Followers.list or {}) do
        if F.skin and not F.removed then out[#out + 1] = F end
    end
    return out
end
local function anim_changed()
    for _, C in ipairs(K.Worn()) do K.ApplyAnim(C) end
end
local function voice_changed()
    for _, C in ipairs(K.Worn()) do K.ApplyVoice(C) end
end
if cvars and cvars.AddChangeCallback then
    for pre, t in pairs(K.cvs) do
        for _, o in ipairs(K.OPTIONS) do
            if t[o.key] then cvars.AddChangeCallback("gsa1_" .. pre .. "_" .. o.key, o.key == "voice" and voice_changed or anim_changed, "gsa1_skins") end
        end
    end
end

-- Q menu > Options > G-SA1 > Character (the owner's rule: every option on the Q menu): each skin's block, in registration order
function K.BuildOptions(panel)
    for _, id in ipairs(K.ORDER) do
        local e = K.SKINS[id]
        if e and e.options and K.cvs[e.options] then
            panel:Help(e.title or id)
            for _, o in ipairs(K.OptionsOf(e)) do
                if o.slider then
                    panel:NumSlider(string.format(o.label, e.title or id), "gsa1_" .. e.options .. "_" .. o.key, o.slider[1], o.slider[2], o.slider[3])
                else
                    panel:CheckBox(string.format(o.label, e.title or id), "gsa1_" .. e.options .. "_" .. o.key)
                end
                panel:ControlHelp(o.page)
            end
            if e.anim_always then panel:ControlHelp((e.title or id) .. " always runs on his feet with Sonic's jog where Sonic runs with his arms behind him, so there is no flying box for him.") end
            panel:ControlHelp("These are " .. (e.title or id) .. "'s as a follower too (Q menu > Options > G-SA1 > Followers: Character to spawn).")
        end
    end
end
if GSA1.AddCharacterOption then GSA1.AddCharacterOption(178, "skins", K.BuildOptions) end
