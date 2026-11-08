-- G-SA1 skins, the client part (round 0.9.9f; sadc docs/research/metal099e.md 4.6, 5.1, 6; the pure part is feat/sh_skins.lua). A skin is a row of GSA1.CHARACTERS (form "skin", made by K.Register): the Quick
-- spawn button, the list, the menubar and the console name it like anyone. Its world is its base's, byte for byte: this file only gives the module its create extras, the options the render step takes at once and
-- the voice. Loads before feat/cl_super.lua, whose GSA1.CreateExtras wrapper is outermost and returns nil for a skin (S.Extras' first line).
-- 1.0.0 (sadc docs/research/gsa1_100_select.md 6): every skin's options come from its entry (options = the ConVar prefix, defaults = their defaults); Metal Sonic's are 0.9.9f's four and a fifth,
-- the Light Speed trails in the skin's colour (libsa1 SA1_SKIN_ANIM_TRAIL, select 4.3.2); Mecha Sonic's are new (his voice, glow and trails).
-- The owner's answer 17 (rounds plan 14.1bl; gsa1_100_master.md 3's R1 delta with RY.1, RY.13): a skin has only the options its entry's option_keys name (Metal all five, Mecha voice, glow and trail:
-- gsa1_mecha_fly and gsa1_mecha_walk_fly are never made, so no fly box shows); an entry with anim_always (Mecha) has its rows on always: SKIN_ANIM_FLY always, never WALK.
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
}

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
        t[o.key] = GSA1.ConVar("gsa1_" .. pre .. "_" .. o.key, tonumber(d[o.key]) or 0, string.format(o.help, e.title or e.id), 0, 1)
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
    return v
end

-- the options of the render step, at once and before a new character's first tick
function K.ApplyAnim(C)
    if not (C and C.skin and C.id and gsa1 and gsa1.SetCharOption and gsa1.SUPER and gsa1.SUPER.COPT_SKIN_ANIM) then return false end
    local ok, err, code = gsa1.SetCharOption(C.id, gsa1.SUPER.COPT_SKIN_ANIM, K.AnimValue(C.skin))
    if not ok then log("the running: refused: %s (%s)", tostring(err), tostring(code)) end
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
                panel:CheckBox(string.format(o.label, e.title or id), "gsa1_" .. e.options .. "_" .. o.key)
                panel:ControlHelp(o.page)
            end
            if e.anim_always then panel:ControlHelp((e.title or id) .. " runs on his feet with Sonic's jog where Sonic runs with his arms behind him: nothing to choose, so no box.") end
            panel:ControlHelp("These are " .. (e.title or id) .. "'s as a follower too (Q menu > Options > G-SA1 > Followers: Character to spawn).")
        end
    end
end
if GSA1.AddCharacterOption then GSA1.AddCharacterOption(178, "skins", K.BuildOptions) end
