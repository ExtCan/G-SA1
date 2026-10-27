-- G-SA1 client: every setting in the spawn menu's Options tab (Q menu, right-hand side: Options -> G-SA1 ->
-- Character (with the upgrades) / Camera / Controller / Rendering / Sound / Collision / Disc and status). The console
-- commands and ConVars stay as they are. A feature's own page (G0: interaction, Super Sonic, followers, jukebox) is
-- registered by its file with GSA1.AddMenuPage and comes after these.
GSA1 = GSA1 or {}

local CATEGORY = "G-SA1"

-- Feature pages (G0, sadc docs/research/gsa1_rounds_plan.md section 5):
--   GSA1.AddMenuPage(order, id, title, builder [, needs])
-- adds the page `title` to Options -> G-SA1, after the built-in pages, ordered by `order` (then id; the same id again
-- replaces the page). builder(panel) fills it like the built-in pages do (a DForm; the controls are cleared before).
-- needs = { feature = "jukebox", version = 1, module = "0.7.0" }: if the loaded module lacks that feature
-- (GSA1.HasFeature), the page says that it needs G-SA1 module 0.7.0 instead of calling builder. A Lua error in builder
-- is shown on the page and written into the session log instead of breaking the menu. Call it while the addon's files
-- load (feat/cl_<feature>.lua): the spawn menu takes the pages once, when it is made.
GSA1.MenuPages = GSA1.MenuPages or {}
function GSA1.AddMenuPage(order, id, title, builder, needs)
    if type(id) ~= "string" or not string.match(id, "^[%w_]+$") or type(title) ~= "string" or type(builder) ~= "function" then
        error("GSA1.AddMenuPage(order, id, title, builder [, needs]): id a word, title a string, builder a function", 2)
    end
    for i, p in ipairs(GSA1.MenuPages) do
        if p.id == id then
            table.remove(GSA1.MenuPages, i)
            break
        end
    end
    GSA1.MenuPages[#GSA1.MenuPages + 1] = { order = tonumber(order) or 1000, id = id, title = title, builder = builder,
                                            needs = type(needs) == "table" and needs or nil }
    table.sort(GSA1.MenuPages, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
end

-- Character options of features (0.9.1; the seam rule of gsa1_070_bird.md review R.4 F4):
--   GSA1.AddCharacterOption(order, id, builder [, needs])
-- adds builder(panel) to the built-in Character page, after the upgrades, ordered by `order` (then id; the same id again
-- replaces it): Amy's bird, Tails' tail blend, drowning and lives (feat/cl_charopt.lua), later features' character
-- settings. needs: as for GSA1.AddMenuPage (without the module's feature the page shows what it needs instead). A Lua
-- error in builder is shown on the page and logged.
GSA1.CharacterOptions = GSA1.CharacterOptions or {}
function GSA1.AddCharacterOption(order, id, builder, needs)
    if type(id) ~= "string" or not string.match(id, "^[%w_]+$") or type(builder) ~= "function" then
        error("GSA1.AddCharacterOption(order, id, builder [, needs]): id a word, builder a function", 2)
    end
    for i, p in ipairs(GSA1.CharacterOptions) do
        if p.id == id then
            table.remove(GSA1.CharacterOptions, i)
            break
        end
    end
    GSA1.CharacterOptions[#GSA1.CharacterOptions + 1] = { order = tonumber(order) or 1000, id = id, builder = builder,
                                                          needs = type(needs) == "table" and needs or nil }
    table.sort(GSA1.CharacterOptions, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
end

-- why a feature's page cannot work with the loaded module (nil: it can)
function GSA1.MissingFeatureText(needs)
    if not needs or not needs.feature then return nil end
    local ok, have = GSA1.HasFeature(needs.feature, needs.version)
    if ok then return nil end
    local want = needs.module and ("G-SA1 module " .. tostring(needs.module) .. " or newer") or "a newer G-SA1 module"
    local now
    if not GSA1.mod then
        now = "the module is not loaded (" .. tostring(GSA1.moduleError or "?") .. ")"
    elseif have then
        now = string.format("module %s has version %s of it, version %s is needed", tostring(gsa1.VERSION), tostring(have),
            tostring(needs.version or 1))
    else
        now = "module " .. tostring(gsa1.VERSION) .. " does not have it"
    end
    return string.format("This page needs %s (its %s part): %s. Install the module and the addon of the same G-SA1 "
        .. "version together.", want, tostring(needs.feature), now)
end

local function feature_page(p)
    return function(panel)
        panel:ClearControls()
        local missing = GSA1.MissingFeatureText(p.needs)
        if missing then
            panel:Help(missing)
            return
        end
        local ok, err = xpcall(p.builder, debug.traceback, panel)
        if not ok then
            panel:Help("This page could not be built: " .. tostring(err))
            if GSA1.Log then GSA1.Log("error", "menu page %s: %s", p.id, tostring(err)) end
        end
    end
end

hook.Add("AddToolMenuCategories", "gsa1", function()
    spawnmenu.AddToolCategory("Options", CATEGORY, "G-SA1")
end)

-- a label that shows lines_fn() and refreshes itself every `interval` seconds while visible
local function live_label(panel, interval, lines_fn)
    local lbl = panel:Help("...")
    -- keep DLabel's own Think: with SetAutoStretchVertical (set by DForm:Help) it resizes the label to its text
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + interval
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

-- a label that shows GSA1.StatusLines() and refreshes itself twice a second while visible
local function status_label(panel, filter)
    return live_label(panel, 0.5, function()
        local lines = GSA1.StatusLines()
        if filter then lines = filter(lines) end
        return lines
    end)
end

-- a combo box for a ConVar whose values have titles (choices: { {title, value}, ... }): it shows the title of the
-- ConVar's value, also after a change from the console, and sets the ConVar when a choice is picked
local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[1], c[2]) end
    -- the combo already shows the picked title; the Think below follows once the ConVar has the new value
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand(cvname, tostring(data))
    end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local cv = GetConVar(cvname)
        local v = cv and cv:GetString() or ""
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        local n = tonumber(v)
        for _, c in ipairs(choices) do
            if c[2] == v or (n ~= nil and tonumber(c[2]) == n) then
                self:SetText(c[1])
                return
            end
        end
        self:SetText(v)
    end
    return combo
end

local function character_panel(panel)
    panel:ClearControls()
    panel:Help("Play a Sonic Adventure character from your own disc image (the module reads the disc path from its "
        .. "own config file: see the Disc section).")
    local combo = panel:ComboBox("Character", "gsa1_character")
    for _, c in ipairs(GSA1.CHARACTERS) do
        combo:AddChoice(c.title, c.name, c.name == GSA1.cv.character:GetString())
    end
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand("gsa1_character", data)
    end
    panel:Button("Spawn / switch to this character", "gsa1_spawn")
    panel:Button("Remove the character", "gsa1_remove")
    panel:Button("Respawn at the spawn point", "gsa1_respawn")
    panel:Help("Quick spawn:")
    for _, c in ipairs(GSA1.CHARACTERS) do
        panel:Button(c.title, "gsa1_spawn", c.name)
    end
    panel:Help("Upgrades")
    panel:ControlHelp("The items each character finds in the story. A character gets the ticked ones of its own when "
        .. "it is created; ticking or unticking one of the current character's re-creates it where it stands (same "
        .. "place and facing, standing still; the spawn point stays). Both Super Sonics use Sonic's upgrades; he has them "
        .. "again when he turns back.")
    -- 0.9.3a (RC4): one block per kind - an entry with a form (Super Sonic (General Gameplay), kind 0) has its kind's
    local shown = {}
    for _, c in ipairs(GSA1.CHARACTERS) do
        local ups = (c.form or shown[c.kind]) and {} or GSA1.UpgradesOf(c.kind)
        shown[c.kind] = true
        if #ups > 0 then
            panel:Help(c.title)
            for _, u in ipairs(ups) do
                panel:CheckBox(u.title, "gsa1_upgrade_" .. u.name)
                panel:ControlHelp(u.help .. ".")
            end
        end
    end
    panel:Button("All upgrades", "gsa1_upgrades_all", "1")
    panel:Button("No upgrades", "gsa1_upgrades_all", "0")
    panel:Button("Re-create the character here with its upgrades", "gsa1_upgrades_apply")
    -- the features' character options (GSA1.AddCharacterOption)
    for _, p in ipairs(GSA1.CharacterOptions) do
        local missing = GSA1.MissingFeatureText(p.needs)
        if missing then
            panel:Help(missing)
        else
            local ok, err = xpcall(p.builder, debug.traceback, panel)
            if not ok then
                panel:Help("These options could not be shown: " .. tostring(err))
                if GSA1.Log then GSA1.Log("error", "character option %s: %s", p.id, tostring(err)) end
            end
        end
    end
    panel:Help("Controls: movement keys / joystick = stick (relative to the camera), jump = A, crouch / attack / "
        .. "attack2 = B (action: spin dash, punch, ...), reload = Y, walk = half stick, mouse wheel = camera "
        .. "distance. Bind a key to gsa1_toggle to spawn and remove quickly.")
    panel:Help("Controller (see the Controller page): left stick = stick, A = jump, B / X = action, Y = Y, right "
        .. "stick = camera, LT / RT = turn the camera, LB / RB = L / R, Back = camera behind the character.")
    panel:CheckBox("Server moves my player along", "gsa1_follow_player")
    panel:ControlHelp("Keeps your (invisible) player where the character is, for other addons, sounds and triggers.")
    panel:CheckBox("Dreamcast stick dead zone (raw stick)", "gsa1_stick_raw")
    panel:ControlHelp("Off: keyboard directions run exactly where you point. On: like a Dreamcast pad (axis-aligned "
        .. "input runs about 6 degrees off).")
    status_label(panel, function(lines)
        local out, on = {}, false
        for _, l in ipairs(lines) do
            if string.find(l, "^characters") then on = true end
            if on and not string.find(l, "^render targets") then out[#out + 1] = l end
        end
        return out
    end)
end

local function camera_panel(panel)
    panel:ClearControls()
    panel:NumSlider("Camera distance", "gsa1_cam_distance", 0, 1000, 0)
    panel:ControlHelp("0 = first person (the character is hidden). The mouse wheel changes it while playing.")
    panel:NumSlider("Camera height", "gsa1_cam_height", -64, 128, 0)
    panel:ControlHelp("Above the character's centre. The camera stops at walls.")
end

local function controller_panel(panel)
    panel:ClearControls()
    panel:Help("An Xbox-style controller (Xbox 360 / One / Series and compatible pads: XInput), read by the module "
        .. "itself. Garry's Mod's own joystick setting is not needed: keep it off (joystick 0). While you use the "
        .. "controller it has priority; when it rests, the keyboard and mouse play as before.")
    panel:CheckBox("Use the controller", "gsa1_pad")
    local idx = { { "Automatic (the one you use)", "0" } }
    for i = 1, 4 do idx[#idx + 1] = { "Controller " .. i, tostring(i) } end
    choice_combo(panel, "Controller", "gsa1_pad_index", idx)
    panel:Help("Live status")
    live_label(panel, 0.1, function()
        if not GSA1.LoadModule() then return { "controller: " .. tostring(GSA1.moduleError) } end
        return GSA1.PadStatusLines()
    end)
    panel:Help("Sticks")
    panel:NumSlider("Left stick dead zone", "gsa1_pad_deadzone", 0, 0.9, 2)
    panel:ControlHelp("Radial. Outside it the stroke starts from zero: push a little to walk, all the way to run.")
    panel:NumSlider("Right stick dead zone", "gsa1_pad_deadzone_right", 0, 0.9, 2)
    panel:NumSlider("Full deflection at", "gsa1_pad_outer", 0.5, 1, 2)
    panel:ControlHelp("Raise a dead zone if the character creeps or the camera turns by itself.")
    panel:NumSlider("Trigger threshold", "gsa1_pad_trigger", 0, 0.9, 2)
    panel:CheckBox("D-pad moves the character", "gsa1_pad_dpad")
    panel:Help("Camera (right stick)")
    panel:NumSlider("Camera speed (degrees per second)", "gsa1_pad_cam_speed", 0, 720, 0)
    panel:NumSlider("Response curve (1 = linear)", "gsa1_pad_cam_curve", 1, 3, 2)
    panel:CheckBox("Invert Y (push up to look down)", "gsa1_pad_invert_y")
    panel:Help("Buttons and triggers")
    local actions = {}
    for _, a in ipairs(GSA1.PAD_ACTIONS) do actions[#actions + 1] = { a.title, tostring(a.id) } end
    for _, inp in ipairs(GSA1.PAD_INPUTS) do
        choice_combo(panel, inp.title, "gsa1_pad_" .. inp.name, actions)
    end
    panel:ControlHelp("A trigger set to camera left / right turns by how far it is pulled. The left stick always "
        .. "moves the character and the right stick always turns the camera.")
    panel:Button("Default buttons", "gsa1_pad_defaults")
    panel:Help("Rumble")
    panel:CheckBox("Rumble", "gsa1_pad_rumble")
    panel:ControlHelp("The game's own vibration (Knuckles' punches, ...), while you play with the controller.")
    panel:NumSlider("Rumble strength", "gsa1_pad_rumble_strength", 0, 1, 2)
    panel:Button("Test rumble", "gsa1_pad_test_rumble")
end

local function rendering_panel(panel)
    panel:ClearControls()
    panel:CheckBox("Interpolate animation and movement", "gsa1_interpolate")
    panel:ControlHelp("The game runs at 30 frames per second; on: smooth at any frame rate (one game frame behind), "
        .. "off: the game's own frames (cheaper: the meshes are rebuilt 30 times a second only).")
    panel:CheckBox("Map lighting (off = fullbright)", "gsa1_lighting")
    panel:CheckBox("Effects", "gsa1_effects")
    panel:ControlHelp("Spin dash ball and trail, punches, E-102's targeting lines, sprites.")
    panel:CheckBox("Character shadows (the game's blob)", "gsa1_shadow")
    panel:ControlHelp("Drawn where the game finds the ground under the character; it shrinks with height and disappears "
        .. "high up, as in the game. Not drawn in first person.")
    panel:NumSlider("Line effect width (pixels)", "gsa1_line_width", 1, 8, 1)
    panel:CheckBox("Vertex colours on effects and models", "gsa1_vertexcolor")
    panel:ControlHelp("The characters' bodies are always texture x lighting, like the game.")
    -- 0.9.2 (sadc docs/research/gsa1_090_render.md R1 / R1b): the character in Source's depth image
    choice_combo(panel, "Depth for post-processing effects", "gsa1_depthfix", {
        { "Off (as 0.9.1)", "0" },
        { "In the depth views (recommended)", "1" },
        { "In the depth views and after the opaque pass", "2" },
    })
    panel:ControlHelp("Effects such as sun shafts, depth of field and GShader's read a depth image of the scene. The "
        .. "character is drawn into it (and into lamp and flashlight shadow depth), so these effects treat him as a "
        .. "solid object instead of washing over him. If a wash remains, try the third choice; \"Off\" draws as 0.9.1 "
        .. "did.")
    panel:Help("Troubleshooting")
    panel:CheckBox("Reverse triangle winding", "gsa1_flip_winding")
    panel:CheckBox("Draw both sides", "gsa1_nocull")
    panel:CheckBox("Precise drawing far from the map's centre", "gsa1_relative")
    panel:ControlHelp("Draws the character relative to the camera, so its eyes and other thin layers do not flicker on "
        .. "big maps. Turn it off if the character is drawn in the wrong place or missing (and please report it).")
    panel:NumSlider("Texture runs painted per frame", "gsa1_texture_runs_per_frame", 500, 50000, 0)
    panel:CheckBox("Prepare the materials when a character appears", "gsa1_prewarm")
    panel:ControlHelp("Makes and draws once, invisibly, every material the character can use (its effects too) over "
        .. "its first seconds, a little per frame, so the first Light Speed charge or other effect does not stall the "
        .. "game. The session log says how long it took.")
    panel:Button("Check the painted textures (console)", "gsa1_texcheck")
    panel:Button("Repaint the textures", "gsa1_texrepaint")
    panel:CheckBox("Debug overlay and log", "gsa1_debug")
end

local function sound_panel(panel)
    panel:ClearControls()
    panel:CheckBox("Sound", "gsa1_sound")
    panel:ControlHelp("The game's sound effects, voices and jingles, decoded from your disc in memory and played "
        .. "through Garry's Mod's own audio output (its volume setting applies).")
    panel:NumSlider("Volume", "gsa1_sound_volume", 0, 4, 2)
    panel:NumSlider("Sound effects", "gsa1_sound_sfx", 0, 4, 2)
    panel:NumSlider("Voices", "gsa1_sound_voice", 0, 4, 2)
    panel:NumSlider("Music and jingles", "gsa1_sound_music", 0, 4, 2)
    panel:CheckBox("Character voices", "gsa1_sound_voices")
    panel:CheckBox("Jingles (invincibility, speed up, drowning, 1-up)", "gsa1_sound_jingles")
    panel:CheckBox("Background music", "gsa1_sound_bgm")
    panel:CheckBox("Other players' voices from their position", "gsa1_sound_3d_voices")
    -- 0.9.4a (sadc docs/research/super2_plan.md 10.3)
    panel:CheckBox("Rings don't pile up", "gsa1_sound_no_stack")
    panel:ControlHelp("A sound started again while it still plays starts over instead of adding up, so a fast ring line "
        .. "stays as loud as one ring. Off: the Dreamcast's way (the rings stack and get loud).")
    local combo = panel:ComboBox("Voice language", "gsa1_sound_japanese")
    local jp = GSA1.cv.snd_japanese:GetBool()
    combo:AddChoice("English", "0", not jp)
    combo:AddChoice("Japanese", "1", jp)
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand("gsa1_sound_japanese", data)
    end
    panel:Button("Reopen the sound banks and the output", "gsa1_sound_reopen")
    status_label(panel, function(lines)
        local out = {}
        for _, l in ipairs(lines) do
            if string.find(l, "^sound") or string.find(l, "^module") then out[#out + 1] = l end
        end
        return out
    end)
end

-- 0.9.3 (sadc docs/research/gsa1_091b_ceiling.md FIX-C3 with its review): solid ceilings over thin roofs. The ConVar
-- lives with its row (Collision page); every load of the map's collision passes it to the module (MapStart option
-- solid_ceilings; off = PrepareOptions::undersides_drop, the one-way platforms until 0.9.2) and puts it in the world's
-- key, so a change prepares the world again (a cache hit: no rebuild)
GSA1.cv = GSA1.cv or {}
GSA1.cv.solid_ceilings = GSA1.cv.solid_ceilings or CreateClientConVar("gsa1_solid_ceilings", "1", true, false,
    "Solid ceilings over thin roofs: ceilings and roofs thinner than about 24 units stop a jump from below (0 = as until 0.9.2: they can be jumped through from below; changing it prepares the map's collision again)", 0, 1)
GSA1.MapOptionHooks = GSA1.MapOptionHooks or {}
GSA1.MapOptionHooks.solid_ceilings = function(o)
    o.solid_ceilings = GSA1.cv.solid_ceilings:GetBool()
    if not o.solid_ceilings then o.world_key = (o.world_key or "") .. " oneway" end
end
cvars.AddChangeCallback("gsa1_solid_ceilings", function()
    if GSA1.mod and GSA1.World and GSA1.World.state ~= "idle" and GSA1.StartWorld then
        timer.Create("gsa1_world_settings", 0.5, 1, function() GSA1.StartWorld(false) end)
    end
end, "gsa1_solid_ceilings")

local function collision_panel(panel)
    panel:ClearControls()
    panel:Help("The map's collision is built the way G64 gets it - the map's brushes and displacements, its static "
        .. "props' physics models, brush entities and props - and cleaned for Sonic Adventure's collision (hidden "
        .. "faces removed, thin platforms solid from above and ceilings from below, loops kept whole, long faces cut "
        .. "into well-shaped pieces). It loads in the background; a spawn waits for it.")
    panel:Help("Map")
    panel:CheckBox("Static props collide", "gsa1_static_props")
    panel:ControlHelp("Their physics models become part of the map's collision (changing it loads the map's collision "
        .. "again; the character is re-created where it stands).")
    panel:NumSlider("Thin walls up to (units thick)", "gsa1_thin_walls", 0, 64, 0)
    panel:ControlHelp("Walls, fences, glass panes and doors this thin or thinner are made one surface in their middle "
        .. "that stops the character from both sides, so it cannot slip through them at speed. 0 = off. The default "
        .. "is 16; the character may look up to half the wall's thickness inside it. Changing it loads the map's "
        .. "collision again. Loops and pipes keep their inside whatever this is set to.")
    panel:CheckBox("Solid ceilings over thin roofs", "gsa1_solid_ceilings")
    panel:ControlHelp("Ceilings and roofs thinner than about 24 units stop a jump from below like every other ceiling "
        .. "(the game's own head contact). From above nothing changes: the character still runs over thin planks and "
        .. "platforms without being pulled through them. Off = as until 0.9.2: such roofs can be jumped through from "
        .. "below. Changing it prepares the map's collision again (no rebuild).")
    panel:CheckBox("Keep each map's collision in a cache", "gsa1_map_cache")
    panel:ControlHelp("garrysmod/data/gsa1/cache/<map>.dat: built from the map only (no game data); a second visit "
        .. "loads in about a second. Rebuilt by itself when the map or the settings change.")
    panel:CheckBox("Load the disc and the map's collision when the map starts", "gsa1_preload")
    panel:ControlHelp("In the background, so the first spawn does not wait.")
    panel:Button("Reload the map's collision", "gsa1_reload_world")
    panel:Button("Delete the cached maps", "gsa1_cache_purge")
    panel:Help("Moving objects")
    panel:CheckBox("Brush entities (doors, lifts, trains, func_brush, breakables)", "gsa1_brush_entities")
    panel:CheckBox("Physics props and vehicles", "gsa1_physics_props")
    panel:ControlHelp("The ones near the character collide and carry it along; switched-off and far ones are set "
        .. "aside without being freed.")
    panel:Help("Status")
    live_label(panel, 0.5, function()
        if not GSA1.LoadModule() then return { "module: " .. tostring(GSA1.moduleError) } end
        return GSA1.WorldLines()
    end)
end

local function disc_panel(panel)
    panel:ClearControls()
    panel:Help("Your Sonic Adventure (US, v1.005) disc image: the module keeps its path in its own config file "
        .. "(%APPDATA%\\gsa1\\config.txt on Windows), outside the game directory. Nothing from the disc is "
        .. "written anywhere.")
    panel:Button("Choose disc (.gdi) ...  (Windows file dialog)", "gsa1_choose_disc")
    panel:Button("Load the module, the disc and the map now", "gsa1_init")
    panel:ControlHelp("The disc, the sound banks and the map's collision load in the background (the game keeps "
        .. "running); the status below shows how far they are. Sounds start a moment after the first spawn if the "
        .. "sound banks are still opening.")
    panel:CheckBox("Load the disc and the map's collision when the map starts", "gsa1_preload")
    panel:Button("Reload the map's collision", "gsa1_reload_world")
    panel:Button("Print the status to the console", "gsa1_status")
    panel:Help("Diagnostics")
    panel:CheckBox("Keep a session log (for bug reports)", "gsa1_log")
    panel:ControlHelp("garrysmod/data/gsa1/log.txt: versions, messages, slow frames and stutters with what took the "
        .. "time, the character's spawns, materials, performance every 10 seconds and a summary per session, so you "
        .. "never have to copy console text: just say when you tested. Older sessions move to log_previous.txt; at "
        .. "most about 1 MB. No paths or names are written.")
    panel:NumSlider("Slow frame threshold for the log (ms)", "gsa1_log_hitch_ms", 20, 2000, 0)
    panel:Button("Mark this moment in the log", "gsa1_log_mark", "marked from the menu")
    panel:ControlHelp("Or bind a key: bind f9 \"gsa1_log_mark lag\" and press it when something happens.")
    panel:CheckBox("Log slow frames (hitches) to the console", "gsa1_hitch_log")
    panel:NumSlider("Slow frame threshold (ms)", "gsa1_hitch_ms", 20, 2000, 0)
    panel:ControlHelp("A frame that takes longer prints which part of G-SA1 took the time (or that it was not G-SA1). "
        .. "The session log has these lines too.")
    panel:Help("Status")
    status_label(panel)
end

-- 0.9.2 (sadc docs/research/gsa1_090_plan.md 6.10 tasks 3 and 4): the Character page's rings and water rows
-- rings F7 and the start rings (gsa1_090_rings.md F7 with its review R4.11; owner default: "Give rings" admin-only in
-- multiplayer): cl_character.lua GSA1.GiveRings / GSA1.StartRings
GSA1.AddCharacterOption(150, "rings", function(panel)
    panel:Help("Rings")
    panel:NumSlider("Start with N rings", "gsa1_start_rings", 0, 99, 0)
    panel:ControlHelp("A character starts with this many rings when it spawns or respawns (0 = the game's 0; at most 99, "
        .. "so a start never gives a 1-up). A re-creation - the map's collision reloaded, upgrades changed, a restart after "
        .. "a game code fault - keeps the rings the character had.")
    panel:Button("Give 10 rings", "gsa1_give_rings", "10")
    panel:Button("Give 50 rings", "gsa1_give_rings", "50")
    panel:Button("Give 100 rings", "gsa1_give_rings", "100")
    panel:ControlHelp("Through the game's own ring counter, so passing 100 gives the game's 1-up. In multiplayer only for "
        .. "admins and the server's host, or with sv_cheats 1 (the server checks it too).")
end)
-- WTR-A (gsa1_090_water.md WTR-A; owner default B1 (a): on): cl_character.lua GSA1.HostWaterFlags
GSA1.AddCharacterOption(160, "hostwater", function(panel)
    panel:CheckBox("Water follows Garry's Mod's water", "gsa1_hostwater")
    panel:ControlHelp("On: the character is in water only where Garry's Mod has water, so dry rooms, sewers and tunnels "
        .. "under a pool or a river stay dry (no bubbles, no drowning countdown). Off: the game's own rule - any water "
        .. "surface above the character counts. The session log writes a \"water\" line whenever the character enters or "
        .. "leaves the game's water.")
    if GSA1.mod and gsa1 and not gsa1.TICK_HOST_FLAGS then
        panel:ControlHelp("(The loaded G-SA1 module is older than 0.9.2: it always follows the game's rule.)")
    end
end)

hook.Add("PopulateToolMenu", "gsa1", function()
    spawnmenu.AddToolMenuOption("Options", CATEGORY, "gsa1_character", "Character", "", "", character_panel)
    spawnmenu.AddToolMenuOption("Options", CATEGORY, "gsa1_camera", "Camera", "", "", camera_panel)
    spawnmenu.AddToolMenuOption("Options", CATEGORY, "gsa1_controller", "Controller", "", "", controller_panel)
    spawnmenu.AddToolMenuOption("Options", CATEGORY, "gsa1_rendering", "Rendering", "", "", rendering_panel)
    spawnmenu.AddToolMenuOption("Options", CATEGORY, "gsa1_sound", "Sound", "", "", sound_panel)
    spawnmenu.AddToolMenuOption("Options", CATEGORY, "gsa1_collision", "Collision", "", "", collision_panel)
    spawnmenu.AddToolMenuOption("Options", CATEGORY, "gsa1_disc", "Disc and status", "", "", disc_panel)
    -- the features' pages (GSA1.AddMenuPage), after the built-in ones
    for _, p in ipairs(GSA1.MenuPages) do
        spawnmenu.AddToolMenuOption("Options", CATEGORY, "gsa1_feat_" .. p.id, p.title, "", "", feature_page(p))
    end
end)
