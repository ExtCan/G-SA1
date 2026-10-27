-- G-SA1 shared configuration: constants, character names, ConVars, network strings.
GSA1 = GSA1 or {}

GSA1.VERSION = "0.9.4e"
GSA1.REQUIRED_API = 6          -- gsa1.API_VERSION the addon is written for
GSA1.SCALE = 4.0               -- Hammer units per SA1 unit (libsa1's Source preset)
GSA1.MODULE = "gsa1"           -- require("gsa1") -> garrysmod/lua/bin/gmcl_gsa1_<platform>.dll

-- The game's own character ids (sa1_character_desc.kind). Eggman and Tikal cannot be played yet. 0.9.3: Super Sonic
-- (kind 8, the module's feature "super" with libsa1 0.4: feat/{sh,cl}_super.lua; "super" also finds him).
-- 0.9.3a (sadc docs/research/super_general_design.md 6.1 with its Review R.4 RC4): two Super Sonics. A character is made by
-- its ENTRY (cl_character.lua create_character(..., def)), not only by its kind: "Super Sonic (Vs. Perfect Chaos)" is
-- kind 8 as in 0.9.3; "Super Sonic (General Gameplay)" is a Sonic (kind 0) world in the General form (form = "general":
-- feat/cl_super.lua gives it its create extras), so the HUD, the interaction layer and the textures see Sonic. An entry
-- with a form shares its kind's upgrades (cl_menu.lua builds one upgrade block per kind).
GSA1.CHARACTERS = {
    { kind = 0, name = "sonic",    title = "Sonic" },
    { kind = 2, name = "tails",    title = "Tails" },
    { kind = 3, name = "knuckles", title = "Knuckles" },
    { kind = 5, name = "amy",      title = "Amy" },
    { kind = 6, name = "gamma",    title = "E-102 Gamma" },
    { kind = 7, name = "big",      title = "Big" },
    { kind = 8, name = "supersonic", title = "Super Sonic (Vs. Perfect Chaos)" },
    { kind = 0, name = "supersonic_general", title = "Super Sonic (General Gameplay)", form = "general" },
}

-- other names of the entries (0.9.3a: "super" stays the Vs. Perfect Chaos Super Sonic of 0.9.3)
GSA1.CHARACTER_ALIASES = {
    e102 = "gamma", ["e-102"] = "gamma",
    super = "supersonic", super_sonic = "supersonic", ["super-sonic"] = "supersonic", vspc = "supersonic",
    supergeneral = "supersonic_general", super_general = "supersonic_general", ssg = "supersonic_general",
}

-- the entry of a list name, an alias or a kind number ("0" is Sonic's own entry); nil: none
function GSA1.CharacterByName(name)
    name = string.lower(tostring(name or ""))
    if name == "" then name = "sonic" end
    name = GSA1.CHARACTER_ALIASES[name] or name
    for _, c in ipairs(GSA1.CHARACTERS) do
        if c.name == name then return c end
    end
    for _, c in ipairs(GSA1.CHARACTERS) do
        if not c.form and tostring(c.kind) == name then return c end
    end
    return nil
end

-- kind, entry of a name (the entry decides the form: "supersonic_general" gives kind 0 and the General entry)
function GSA1.KindByName(name)
    local c = GSA1.CharacterByName(name)
    if c then return c.kind, c end
    return nil
end

-- the plain entry of a kind (an entry with a form is never the kind's own: kind 0 is "sonic")
function GSA1.CharacterByKind(kind)
    for _, c in ipairs(GSA1.CHARACTERS) do
        if c.kind == kind and not c.form then return c end
    end
end

-- 0.9.3a (design 6.5, D12): whose upgrades a kind uses - Super Sonic (Vs. Perfect Chaos, kind 8) has Sonic's (the game keeps
-- the upgrade bits when he turns back: 0x8007, then 0x0007), every other kind its own
function GSA1.UpgradeKind(kind)
    if kind == 8 then return 0 end
    return kind
end

-- The characters' upgrades (the module's gsa1.Upgrades(kind) has the same names; cl_module.lua compares them). In
-- the game each is an event flag that PInitialize turns into an equipment bit when the character starts; G-SA1 gives
-- the ticked ones to a character when it is created, and re-creates the current character where it stands when one
-- of its upgrades is ticked or unticked (cl_character.lua). ConVar: gsa1_upgrade_<name>.
GSA1.UPGRADES = {
    { kind = 0, name = "light_speed_shoes", title = "Light Speed Shoes",
      help = "Hold action to charge the light speed dash" },
    { kind = 0, name = "crystal_ring",      title = "Crystal Ring",
      help = "With the shoes: the light speed dash charges faster" },
    { kind = 0, name = "ancient_light",     title = "Ancient Light",
      help = "With the shoes: the charged dash attacks a target" },
    { kind = 2, name = "jet_anklet",        title = "Jet Anklet",
      help = "Stronger steering while flying; the anklets are drawn" },
    { kind = 2, name = "rhythm_badge",      title = "Rhythm Badge",
      help = "Hold action for the tail attack chain" },
    { kind = 3, name = "shovel_claw",       title = "Shovel Claw",
      help = "Dig (hold action, press jump) where the ground is diggable; the claws are drawn" },
    { kind = 3, name = "fighting_gloves",   title = "Fighting Gloves",
      help = "Hold action on the ground to charge the Maximum Heat attack; the gloves are drawn" },
    { kind = 5, name = "warrior_feather",   title = "Warrior Feather",
      help = "The feather and its jumping hammer attack" },
    { kind = 5, name = "long_hammer",       title = "Long Hammer",
      help = "The longer hammer" },
    { kind = 6, name = "jet_booster",       title = "Jet Booster",
      help = "Hold jump in the air to hover" },
    { kind = 6, name = "laser_blaster",     title = "Laser Blaster",
      help = "The laser blaster parts and their shots" },
    { kind = 7, name = "life_belt",         title = "Life Belt",
      help = "Stay afloat in water" },
    { kind = 7, name = "power_rod",         title = "Power Rod",
      help = "The power rod for fishing" },
    { kind = 7, name = "lure_1",            title = "Lure upgrade 1", help = "Big's lures: the game counts them" },
    { kind = 7, name = "lure_2",            title = "Lure upgrade 2", help = "Big's lures: the game counts them" },
    { kind = 7, name = "lure_3",            title = "Lure upgrade 3", help = "Big's lures: the game counts them" },
    { kind = 7, name = "lure_4",            title = "Lure upgrade 4", help = "Big's lures: the game counts them" },
}

-- the upgrades of one character
function GSA1.UpgradesOf(kind)
    local out = {}
    for _, u in ipairs(GSA1.UPGRADES) do
        if u.kind == kind then out[#out + 1] = u end
    end
    return out
end

-- Controller (XInput, read by the module; cl_pad.lua): what a button or trigger does (gsa1.PAD_ACT_* values) ...
GSA1.PAD_ACTIONS = {
    { id = 0, title = "Nothing" },
    { id = 1, title = "Jump (SA1 A)" },
    { id = 2, title = "Action (SA1 B: spin dash, punch, ...)" },
    { id = 3, title = "SA1 Y" },
    { id = 4, title = "SA1 L" },
    { id = 5, title = "SA1 R" },
    { id = 6, title = "Camera left (look around)" },
    { id = 7, title = "Camera right (look around)" },
    { id = 8, title = "Camera reset (behind the character)" },
}
-- ... and the mappable inputs (ConVar gsa1_pad_<name>; the module's map keys)
GSA1.PAD_INPUTS = {
    { name = "a",     title = "A",                  default = 1 },
    { name = "b",     title = "B",                  default = 2 },
    { name = "x",     title = "X",                  default = 2 },
    { name = "y",     title = "Y",                  default = 3 },
    { name = "lb",    title = "Left bumper (LB)",   default = 4 },
    { name = "rb",    title = "Right bumper (RB)",  default = 5 },
    { name = "lt",    title = "Left trigger (LT)",  default = 6 },
    { name = "rt",    title = "Right trigger (RT)", default = 7 },
    { name = "start", title = "Start / Menu",       default = 0 },
    { name = "back",  title = "Back / View",        default = 8 },
    { name = "ls",    title = "Left stick click",   default = 0 },
    { name = "rs",    title = "Right stick click",  default = 0 },
}

-- network strings (registered on the server in sv_gsa1.lua)
GSA1.NET_ACTIVE = "gsa1_active"   -- client -> server: the local player starts / stops being a character
GSA1.NET_STATE  = "gsa1_state"    -- client -> server: owner-authoritative state packet (sh_net.lua)

if CLIENT then
    local function cv(name, default, help, lo, hi)
        return CreateClientConVar(name, default, true, false, help, lo, hi)
    end
    GSA1.cv = {
        -- character
        character    = cv("gsa1_character", "sonic", "Character for gsa1_spawn without an argument"),
        stick_raw    = cv("gsa1_stick_raw", "0", "1 = pass the stick like a Dreamcast pad (axis-aligned input runs about 6 degrees off)", 0, 1),
        follow       = cv("gsa1_follow_player", "1", "Let the server move your player entity along with the character", 0, 1),
        -- 0.9.2 (sadc docs/research/gsa1_090_plan.md 6.10): Character page
        hostwater    = cv("gsa1_hostwater", "1", "Water follows Garry's Mod's water: 1 = the character is in water only where Garry's Mod has water (no water in dry rooms, sewers and tunnels under a pool or a river), 0 = the game's own rule (any water surface above the character)", 0, 1),
        start_rings  = cv("gsa1_start_rings", "0", "Rings a character starts with when it spawns or respawns (0 = the game's 0; at most 99, so a start never gives a 1-up)", 0, 99),
        -- camera
        cam_dist     = cv("gsa1_cam_distance", "150", "Chase camera distance in Hammer units (0 = first person)", 0, 1000),
        cam_height   = cv("gsa1_cam_height", "20", "Chase camera height above the character's centre", -64, 128),
        -- rendering
        interp       = cv("gsa1_interpolate", "1", "Interpolate the animation and the movement between the game's 30 Hz frames (0 = the raw frames)", 0, 1),
        lighting     = cv("gsa1_lighting", "1", "Light the character with the map's lighting (0 = fullbright)", 0, 1),
        vcolor       = cv("gsa1_vertexcolor", "1", "Multiply effect and model textures by their SA1 vertex colours (the characters' bodies are lit like the game: texture x lighting)", 0, 1),
        effects      = cv("gsa1_effects", "1", "Draw the characters' effects (spin dash trail, punches, targeting lines, sprites)", 0, 1),
        shadow       = cv("gsa1_shadow", "1", "Draw the characters' shadows: the game's own blob, where the game finds the ground under the character (it shrinks with height and disappears high above the ground, as in the game)", 0, 1),
        relative     = cv("gsa1_relative", "1", "Draw the characters relative to the camera: precise far from the map's centre (no flickering eyes on big maps); turn it off if a character is drawn in the wrong place", 0, 1),
        depthfix     = cv("gsa1_depthfix", "1", "Depth for post-processing effects (sun shafts, depth of field, GShader): 0 = off (as 0.9.1: the character is missing from the depth image), 1 = the characters are drawn into Source's depth views (the depth pass, lamp and flashlight shadow depth), 2 = also once more after the opaque pass, if 1 still leaves a wash over the character", 0, 2),
        line_width   = cv("gsa1_line_width", "2", "Width in pixels of the game's line effects (E-102's targeting)", 1, 8),
        flip         = cv("gsa1_flip_winding", "0", "Reverse the triangle winding of the character mesh (if it draws inside out)", 0, 1),
        nocull       = cv("gsa1_nocull", "0", "Draw both sides of every character triangle", 0, 1),
        paint_budget = cv("gsa1_texture_runs_per_frame", "6000", "Texture runs painted per frame while textures load", 500, 200000),
        prewarm      = cv("gsa1_prewarm", "1", "Prepare every material a character can use while it appears (a few milliseconds per frame over its first seconds), so the first use of an effect (the Light Speed charge) does not stall the game", 0, 1),
        -- sound
        sound        = cv("gsa1_sound", "1", "Play the game's sounds (sound effects, voices, jingles) from your disc", 0, 1),
        snd_master   = cv("gsa1_sound_volume", "1", "G-SA1 master volume (1 = the game's level)", 0, 4),
        snd_sfx      = cv("gsa1_sound_sfx", "1", "Sound effect volume", 0, 4),
        snd_voice    = cv("gsa1_sound_voice", "1", "Voice volume", 0, 4),
        snd_music    = cv("gsa1_sound_music", "1", "Music and jingle volume", 0, 4),
        snd_voices   = cv("gsa1_sound_voices", "1", "Character voices", 0, 1),
        snd_jingles  = cv("gsa1_sound_jingles", "1", "Jingles (invincibility, speed up, drowning, 1-up)", 0, 1),
        snd_bgm      = cv("gsa1_sound_bgm", "0", "Background music changes the game asks for", 0, 1),
        snd_3d       = cv("gsa1_sound_3d_voices", "1", "Other players' voices come from their position", 0, 1),
        -- 0.9.4a (sadc docs/research/super2_plan.md 10.3, the owner's note on 0.9.4's rings)
        snd_no_stack = cv("gsa1_sound_no_stack", "1", "A sound effect started again while it still plays restarts instead of piling up: a fast ring line stays as loud as one ring (0 = the Dreamcast's: they pile up)", 0, 1),
        snd_japanese = cv("gsa1_sound_japanese", "0", "Japanese voices (0 = English)", 0, 1),
        -- controller (XInput, read by the module; cl_pad.lua)
        pad          = cv("gsa1_pad", "1", "Use an Xbox-style controller (XInput), read by the module itself (keep Garry's Mod's own joystick 0)", 0, 1),
        pad_index    = cv("gsa1_pad_index", "0", "Controller: 0 = automatic (the one you use), 1-4 = that XInput slot", 0, 4),
        pad_dead     = cv("gsa1_pad_deadzone", "0.2", "Left stick dead zone (radial, fraction of full deflection)", 0, 0.9),
        pad_dead_r   = cv("gsa1_pad_deadzone_right", "0.2", "Right stick dead zone (radial)", 0, 0.9),
        pad_outer    = cv("gsa1_pad_outer", "0.95", "Stick deflection that counts as full (both sticks)", 0.5, 1),
        pad_trigger  = cv("gsa1_pad_trigger", "0.12", "Trigger threshold (fraction of a full pull)", 0, 0.9),
        pad_cam      = cv("gsa1_pad_cam_speed", "180", "Camera speed: degrees per second at full right-stick deflection (and full triggers)", 0, 720),
        pad_curve    = cv("gsa1_pad_cam_curve", "1.5", "Right stick response curve (1 = linear, higher = finer near the centre)", 1, 3),
        pad_invert_y = cv("gsa1_pad_invert_y", "0", "Invert the right stick's Y (push up to look down)", 0, 1),
        pad_dpad     = cv("gsa1_pad_dpad", "0", "The D-pad moves the character (full stroke) while the left stick rests", 0, 1),
        pad_rumble   = cv("gsa1_pad_rumble", "1", "Controller rumble from the game's vibration (punches, hits, ...)", 0, 1),
        pad_rumble_k = cv("gsa1_pad_rumble_strength", "1", "Rumble strength", 0, 1),
        -- map collision (cl_module.lua, cl_collision.lua)
        static_props = cv("gsa1_static_props", "1", "Static props collide (their physics models become part of the map's collision; changing it reloads the map's collision)", 0, 1),
        brush_ents   = cv("gsa1_brush_entities", "1", "Brush entities (doors, lifts, trains, func_brush, breakables) collide as moving objects", 0, 1),
        phys_props   = cv("gsa1_physics_props", "1", "Physics props and vehicles collide as moving objects", 0, 1),
        map_cache    = cv("gsa1_map_cache", "1", "Keep each map's collision in garrysmod/data/gsa1/cache (a second visit loads in about a second)", 0, 1),
        thin_walls   = cv("gsa1_thin_walls", "16", "Thin walls: a wall, fence, pane or door at most this many units thick is made one surface that stops the character from both sides (0 = off; changing it reloads the map's collision)", 0, 64),
        preload      = cv("gsa1_preload", "1", "Load your disc and the map's collision in the background as soon as the map starts (no wait at the first spawn)", 0, 1),
        -- debugging
        debug        = cv("gsa1_debug", "0", "Debug overlay; print libsa1 log lines and game events", 0, 1),
        hitch        = cv("gsa1_hitch_log", "1", "Print a breakdown to the console when a frame takes longer than gsa1_hitch_ms (which part of G-SA1 took the time)", 0, 1),
        hitch_ms     = cv("gsa1_hitch_ms", "100", "Frame time in milliseconds above which gsa1_hitch_log prints", 20, 2000),
        log          = cv("gsa1_log", "1", "Keep a session log in garrysmod/data/gsa1/log.txt (versions, messages, slow frames, stutters, performance, a summary) for bug reports", 0, 1),
        log_hitch_ms = cv("gsa1_log_hitch_ms", "50", "Frames longer than this (ms) go into the session log with a breakdown", 20, 2000),
    }
    for _, u in ipairs(GSA1.UPGRADES) do
        local who = GSA1.CharacterByKind(u.kind)
        GSA1.cv["up_" .. u.name] = cv("gsa1_upgrade_" .. u.name, "0", (who and who.title or "?") .. "'s " .. u.title
            .. " (1 = has it). " .. u.help .. ". Changing it re-creates the character where it stands.", 0, 1)
    end
    local actions = {}
    for _, a in ipairs(GSA1.PAD_ACTIONS) do actions[#actions + 1] = a.id .. " " .. string.lower(a.title) end
    for _, inp in ipairs(GSA1.PAD_INPUTS) do
        GSA1.cv["pad_" .. inp.name] = cv("gsa1_pad_" .. inp.name, tostring(inp.default),
            "What the controller's " .. inp.title .. " does: " .. table.concat(actions, ", "), 0, #GSA1.PAD_ACTIONS - 1)
    end
end

-- Feature ConVars (G0, sadc docs/research/gsa1_rounds_plan.md section 5): the files of a feature
-- (addon/lua/gsa1/feat/{sh,cl,sv}_<feature>.lua) make their settings with this helper instead of editing this file.
--   GSA1.ConVar(name, default, help, min, max)          a client setting, archived (nil on the server)
--   GSA1.ConVar(name, default, help, min, max, flags)   flags = { server = true [, notify = true] [, archive = false]
--       [, replicated = false] }: a server setting, archived and replicated to the clients (call it in a sh_ file:
--       it is made in both realms, so the clients can read it); or a number: the FCVAR_* bits of a server setting
-- The name must start with "gsa1_". Every one is listed in GSA1.CONVARS[name] = { cv, default, help, min, max,
-- server } (pages, the session log). The owner's rule: each gets a control on its feature's Q-menu page
-- (GSA1.AddMenuPage, cl_menu.lua); console commands are extras.
GSA1.CONVARS = GSA1.CONVARS or {}
function GSA1.ConVar(name, default, help, min, max, flags)
    if type(name) ~= "string" or not string.match(name, "^gsa1_[%w_]+$") then
        error("GSA1.ConVar: a name like gsa1_<word> is needed, not " .. tostring(name), 2)
    end
    default = tostring(default)
    local server, bits = false, 0
    if type(flags) == "table" and flags.server then
        server = true
        bits = bit.bor(flags.archive == false and 0 or (FCVAR_ARCHIVE or 128),
            flags.replicated == false and 0 or (FCVAR_REPLICATED or 8192), flags.notify and (FCVAR_NOTIFY or 256) or 0)
    elseif type(flags) == "number" then
        server, bits = true, flags
    end
    local cv
    if server then
        cv = CreateConVar(name, default, bits, help, min, max)
    elseif CLIENT then
        cv = CreateClientConVar(name, default, true, false, help, min, max)
    end
    GSA1.CONVARS[name] = { cv = cv, default = default, help = help, min = min, max = max, server = server }
    return cv
end
