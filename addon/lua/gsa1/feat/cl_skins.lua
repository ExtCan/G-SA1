-- G-SA1 skins, the client part (round 0.9.9f; sadc docs/research/metal099e.md 4.6, 5.1, 6; the pure part is feat/sh_skins.lua). Metal Sonic is a row of GSA1.CHARACTERS (form "skin"): the Quick spawn
-- button, the list, the menubar and the console name him like anyone. His world is Sonic's, byte for byte: this file only gives the module its create extras, the two options the render step takes at once and the voice.
-- Loads before feat/cl_super.lua, whose GSA1.CreateExtras wrapper is outermost and returns nil for a skin (S.Extras' first line).
GSA1 = GSA1 or {}
local K = GSA1.Skins
if not K then error("gsa1/feat/sh_skins.lua did not load: the skins need it") end

K.cv = K.cv or {
    fly = GSA1.ConVar("gsa1_metal_fly", 1, "Metal Sonic: run with Super Sonic's flying (off: Sonic's own run on him). At once, no re-creation", 0, 1),
    walk_fly = GSA1.ConVar("gsa1_metal_walk_fly", 0, "Metal Sonic: fly when walking too (Sonic's row 9 becomes Super Sonic's 131): toes may touch for a frame", 0, 1),
    voice = GSA1.ConVar("gsa1_metal_voice", 0, "Metal Sonic: speak with Sonic's voice (off: voiceless, sound effects stay). At once", 0, 1),
}
local cv = K.cv

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

-- the two options of the render step, at once and before a new character's first tick
function K.ApplyAnim(C)
    if not (C and C.skin and C.id and gsa1 and gsa1.SetCharOption and gsa1.SUPER and gsa1.SUPER.COPT_SKIN_ANIM) then return false end
    local v = 0
    if cv.fly:GetBool() then
        v = gsa1.SUPER.SKIN_ANIM_FLY
        if cv.walk_fly:GetBool() then v = v + gsa1.SUPER.SKIN_ANIM_WALK end
    end
    local ok, err, code = gsa1.SetCharOption(C.id, gsa1.SUPER.COPT_SKIN_ANIM, v)
    if not ok then log("the running: refused: %s (%s)", tostring(err), tostring(code)) end
    return ok == true
end

function K.ApplyVoice(C)
    if not (C and C.skin and C.id and gsa1 and gsa1.SetVoiceless) then return false end
    return gsa1.SetVoiceless(C.id, K.Voiceless(C.skin)) == true
end

-- the entry's voice setting, with the owner's option over it
function K.Voiceless(skin)
    return not (skin and skin.voice) and not cv.voice:GetBool()
end

hook.Add("GSA1CharacterCreated", "gsa1_skins", function(C, how)
    if not (C and C.skin) then return end
    K.ApplyAnim(C)
    K.ApplyVoice(C)
    log("%s %s: over Sonic's world; running %s, walking %s, %s", C.title or "?", how or "created", cv.fly:GetBool() and "flies" or "as Sonic",
        (cv.fly:GetBool() and cv.walk_fly:GetBool()) and "flies" or "as Sonic", K.Voiceless(C.skin) and "voiceless" or "with Sonic's voice")
end)

local function anim_changed()
    if GSA1.Char and GSA1.Char.skin then K.ApplyAnim(GSA1.Char) end
end
local function voice_changed()
    if GSA1.Char and GSA1.Char.skin then K.ApplyVoice(GSA1.Char) end
end
if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("gsa1_metal_fly", anim_changed, "gsa1_skins")
    cvars.AddChangeCallback("gsa1_metal_walk_fly", anim_changed, "gsa1_skins")
    cvars.AddChangeCallback("gsa1_metal_voice", voice_changed, "gsa1_skins")
end

-- Q menu > Options > G-SA1 > Character (the owner's rule: every option on the Q menu)
function K.BuildOptions(panel)
    panel:Help("Metal Sonic")
    panel:CheckBox("Metal Sonic: run with Super Sonic's flying", "gsa1_metal_fly")
    panel:ControlHelp("Off: Sonic's own run on him. At once, no re-creation.")
    panel:CheckBox("... and when walking", "gsa1_metal_walk_fly")
    panel:ControlHelp("Sonic's slow walk flies too (Super Sonic's slow move): his toes may touch the ground for a frame.")
    panel:CheckBox("Metal Sonic: speak with Sonic's voice", "gsa1_metal_voice")
    panel:ControlHelp("Off: voiceless. Sound effects stay either way. At once.")
end
if GSA1.AddCharacterOption then GSA1.AddCharacterOption(178, "skins", K.BuildOptions) end
