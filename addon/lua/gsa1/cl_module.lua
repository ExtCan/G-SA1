-- G-SA1 client: loading the binary module, disc initialisation, the map's collision, status lines.
--
-- The map's collision (0.5) is loaded in the background, G64's way but cleaned (module: src/core/mapjob.*): the world
-- brushes, displacements and static props (their physics models) become the static world, the solid brush entities'
-- models become shapes of moving objects (cl_collision.lua). The module reads a map it finds itself on a worker thread;
-- a workshop or mounted map is read here through Garry's Mod's own file system - only the byte ranges the module asks
-- for (a few MB of a 100 MB map), a few milliseconds per frame - and so are the static props' .phy files. Each map's
-- result goes into garrysmod/data/gsa1/cache/<map>.dat (gsa1_map_cache), so a second visit loads in about a second.
-- Nothing of this blocks a frame: a spawn waits for the map ("loading the map's collision ... 40%") and happens
-- by itself when it is ready. gsa1_preload starts it when the map starts.
--
-- 0.5.1: the disc (gsa1.Init / InitPoll), the sound banks (gsa1.AudioOpen / AudioPoll) and libsa1's GRID synthesis of
-- the map (the job's "preparing" stage) load on the module's worker threads too; GSA1.InitThink and GSA1.AudioThink
-- (once per frame, cl_character.lua) carry on when they are done. gsa1.MapApply then only installs the prepared
-- geometry, which every character, respawn and re-creation shares; a reload (the map's settings changed, the cache
-- deleted, gsa1_reload_world) prepares again in the background and swaps it in when it is ready.
GSA1 = GSA1 or {}

local PREFIX_COLOR = Color(80, 160, 255)

-- a console line, also written into the session log (cl_log.lua) as a "msg" line
function GSA1.Msg(...)
    MsgC(PREFIX_COLOR, "[G-SA1] ", color_white, string.format(...), "\n")
    if GSA1.Log then GSA1.Log("msg", ...) end
end

-- the same with the log line's kind (capacity, spawn, libsa1, ...)
function GSA1.Note(kind, ...)
    MsgC(PREFIX_COLOR, "[G-SA1] ", color_white, string.format(...), "\n")
    if GSA1.Log then GSA1.Log(kind, ...) end
end

function GSA1.Chat(...)
    local text = string.format(...)
    GSA1.Msg("%s", text)
    if IsValid(LocalPlayer()) then
        chat.AddText(PREFIX_COLOR, "[G-SA1] ", color_white, text)
    end
end

local function prof(name, t0)
    if GSA1.HitchAdd then GSA1.HitchAdd(name, SysTime() - t0) end
end

-- 1. the module ---------------------------------------------------------------------------------------------------
function GSA1.LoadModule()
    if GSA1.mod then return true end
    if GSA1.moduleError then return false, GSA1.moduleError end
    local function fail(msg)
        GSA1.moduleError = msg
        return false, msg
    end
    if not system.IsWindows() and not system.IsLinux() then
        return fail("this platform has no G-SA1 module (Windows and Linux 64-bit only)")
    end
    if jit.arch ~= "x64" then
        return fail("G-SA1 needs the 64-bit Garry's Mod (Steam: Garry's Mod -> Properties -> launch the 64-bit version)")
    end
    if not util.IsBinaryModuleInstalled(GSA1.MODULE) then
        local file = system.IsWindows() and "gmcl_gsa1_win64.dll" or "gmcl_gsa1_linux64.dll"
        return fail("the module is not installed: copy " .. file .. " into garrysmod/lua/bin (see the README)")
    end
    local ok, err = pcall(require, GSA1.MODULE)
    if not ok or type(gsa1) ~= "table" then
        return fail("require(\"gsa1\") failed: " .. tostring(err))
    end
    if gsa1.API_VERSION ~= GSA1.REQUIRED_API then
        return fail(string.format("module API %s, this addon needs %d: update the module and the addon together",
            tostring(gsa1.API_VERSION), GSA1.REQUIRED_API))
    end
    GSA1.mod = gsa1
    GSA1.Msg("module %s loaded (libsa1 %s)", gsa1.VERSION, gsa1.LIBSA1_VERSION)
    if GSA1.Log then
        -- the vector mode is decided when the module opens (0.6.1), so this line and the session log's header have it
        local st = gsa1.Status and gsa1.Status() or {}
        GSA1.Log("module", "module %s (API %s, build %s), libsa1 %s, addon %s; vector mode %s; %s", tostring(gsa1.VERSION),
            tostring(gsa1.API_VERSION), tostring(st.build), tostring(gsa1.LIBSA1_VERSION), tostring(GSA1.VERSION),
            GSA1.VectorModeText(st.vector_mode), GSA1.FeatureLine())
    end
    -- a feature the module refused (a name clash, a bad name or version: gsa1_feature.hpp)
    for _, e in ipairs(type(gsa1.FEATURE_ERRORS) == "table" and gsa1.FEATURE_ERRORS or {}) do
        GSA1.Msg("module feature: %s", tostring(e))
    end
    -- the addon's upgrade list (ConVars, menu) against the module's
    local known = {}
    for _, u in ipairs(gsa1.Upgrades() or {}) do known[u.kind .. ":" .. u.name] = true end
    for _, u in ipairs(GSA1.UPGRADES) do
        if not known[u.kind .. ":" .. u.name] then
            GSA1.Msg("the module does not know the upgrade %s (%s): update the module and the addon together", u.name,
                u.title)
        end
    end
    return true
end

-- Features (G0, sadc docs/research/gsa1_rounds_plan.md section 5): a later part of G-SA1 (interaction, Super Sonic,
-- followers, jukebox) brings its own module functions, listed in gsa1.FEATURES = { name = version }, and its own Lua
-- files (addon/lua/gsa1/feat/, loaded by the autorun). The base API check above stays exact; a feature is checked by:
-- GSA1.HasFeature(name, min_version) -> true when the loaded module has it at min_version (default 1) or newer; second
-- result: the module's version of it (nil: none). It loads the module like the status lines do: call it from a page
-- builder or a hook, not while the addon's files load.
function GSA1.HasFeature(name, min_version)
    if not GSA1.LoadModule() then return false, nil end
    local f = gsa1.FEATURES
    local v = type(f) == "table" and tonumber(f[name]) or nil
    return v ~= nil and v >= (tonumber(min_version) or 1), v
end

-- "features: jukebox 1, interact 2" / "features: none" (the module's, then the addon's feature files)
function GSA1.FeatureLine()
    local mod = {}
    if GSA1.mod and type(gsa1.FEATURES) == "table" then
        for name, v in pairs(gsa1.FEATURES) do mod[#mod + 1] = tostring(name) .. " " .. tostring(v) end
        table.sort(mod)
    end
    local files = GSA1.FeatureFiles or {}
    local errs = GSA1.FeatureFileErrors or {}
    return string.format("features: %s; feature files: %s%s", #mod > 0 and table.concat(mod, ", ") or "none",
        #files > 0 and table.concat(files, " ") or "none", #errs > 0 and (" (failed: " .. table.concat(errs, "; ") .. ")")
        or "")
end

-- how the module hands Vectors to mesh.Position / mesh.Normal (gsa1.Status().vector_mode)
function GSA1.VectorModeText(m)
    if m == 1 then return "1 (two scratch Vectors written in place)" end
    if m == 0 then return "0 (a new Vector per vertex: garbage every frame)" end
    return tostring(m) .. " (not decided)"
end

-- 2. the disc (path from the module's own config file, never from Lua), loaded on a worker thread of the module:
-- returns true when it is loaded, false, "loading" while it loads (GSA1.InitThink carries on), false, why otherwise
function GSA1.InitDisc()
    local ok, err = GSA1.LoadModule()
    if not ok then return false, err end
    if gsa1.IsReady() then return true end
    local t0 = SysTime()
    local res, msg = gsa1.Init()
    prof("Init", t0)
    GSA1.DrainLog()
    if not res then
        GSA1.discLoading = false
        GSA1.discError = msg
        return false, msg
    end
    if gsa1.IsReady() then return true end
    if not GSA1.discLoading then
        GSA1.discLoading = true
        GSA1.discError = nil
    end
    return false, "loading"
end

-- once per frame: while the disc loads, ask the module (it installs the loaded disc on this thread: cheap); when it is
-- there, open the sound banks (on a worker too), hand over a map collision that waited for the disc, and do a spawn
-- that waited
function GSA1.InitThink()
    if not GSA1.discLoading or not GSA1.mod then return end
    local t0 = SysTime()
    local state, msg = gsa1.InitPoll()
    prof("Init", t0)
    if state == "loading" then return end
    GSA1.discLoading = false
    GSA1.DrainLog()
    if state ~= "ready" then
        GSA1.discError = tostring(msg)
        GSA1.Msg("disc: %s", GSA1.discError)
        if GSA1.pendingSpawn then
            GSA1.pendingSpawn = nil
            GSA1.Chat("cannot spawn: %s", GSA1.discError)
        end
        return
    end
    GSA1.Msg("%s", tostring(msg))
    GSA1.OpenAudio()
    if GSA1.World.state == "ready" then
        GSA1.ApplyWorld()    -- also does a spawn that waited
    elseif GSA1.pendingSpawn and GSA1.World.state ~= "loading" then
        local pending = GSA1.pendingSpawn
        GSA1.pendingSpawn = nil
        if GSA1.Spawn then GSA1.Spawn(pending) end
    end
end

-- 2b. sound: the disc's sound banks in the module, mixed into Garry's Mod's own audio output (BASS) -------------
function GSA1.ApplyAudioSettings()
    if not GSA1.mod or not gsa1.AudioSettings then return end
    local c = GSA1.cv
    gsa1.AudioSettings(c.snd_master:GetFloat(), c.snd_sfx:GetFloat(), c.snd_voice:GetFloat(), c.snd_music:GetFloat(),
        c.snd_voices:GetBool(), c.snd_jingles:GetBool(), c.snd_bgm:GetBool(), c.snd_3d:GetBool(),
        -- 0.9.4a (super2_plan.md 10.3): the rings' "no pile-up" (a module before 0.9.4a ignores it)
        c.snd_no_stack == nil or c.snd_no_stack:GetBool())
end

-- the sound banks open on a worker thread of the module (85 reads of the disc); GSA1.AudioThink reports when they are
-- open. Sounds of the character start then (a moment after a first spawn at most).
function GSA1.OpenAudio()
    if not GSA1.mod or not gsa1.IsReady() then return false, "not initialised" end
    if not GSA1.cv.sound:GetBool() then
        gsa1.AudioClose()
        GSA1.audioOpening = false
        return false, "sound is off (gsa1_sound 0)"
    end
    GSA1.ApplyAudioSettings()
    local t0 = SysTime()
    local ok, msg = gsa1.AudioOpen(GSA1.cv.snd_japanese:GetBool())
    prof("Sound", t0)
    GSA1.DrainLog()
    GSA1.audioOpening = ok and true or false
    if not ok then GSA1.Msg("sound: %s", tostring(msg)) end
    return ok, msg
end

-- once per frame while the sound banks open
function GSA1.AudioThink()
    if not GSA1.audioOpening or not GSA1.mod or not gsa1.AudioPoll then return end
    local t0 = SysTime()
    local ok, msg = gsa1.AudioPoll()
    prof("Sound", t0)
    if ok == nil then return end
    GSA1.audioOpening = false
    GSA1.DrainLog()
    GSA1.Msg("sound: %s", tostring(msg))
end

for _, name in ipairs({ "gsa1_sound_volume", "gsa1_sound_sfx", "gsa1_sound_voice", "gsa1_sound_music",
                        "gsa1_sound_voices", "gsa1_sound_jingles", "gsa1_sound_bgm", "gsa1_sound_3d_voices",
                        "gsa1_sound_no_stack" }) do
    cvars.AddChangeCallback(name, function() GSA1.ApplyAudioSettings() end, "gsa1_audio")
end
for _, name in ipairs({ "gsa1_sound", "gsa1_sound_japanese" }) do
    cvars.AddChangeCallback(name, function()
        if GSA1.mod and gsa1.IsReady() then GSA1.OpenAudio() end
    end, "gsa1_audio")
end

-- 3. the map's collision, in the background ------------------------------------------------------------------------
-- GSA1.World.state: "idle" | "loading" (the module's job runs) | "ready" (built, waits for the disc) | "applied" |
-- "failed"
GSA1.World = GSA1.World or { state = "idle" }
local W = GSA1.World
local READ_BUDGET = 0.004       -- seconds of file reading per frame
local MAX_FEED = 1048576        -- bytes per gsa1.MapFeed

-- Features that change the static world add their part (GSA1.MapOptionHooks[name] = function(opts); 0.8:
-- feat/cl_surfaces.lua hands the surface class table to the module): settings for the module, and opts.world_key, which
-- goes into the world's key - a change loads the world again (a cache hit, the classes applied and the world prepared
-- on a worker; no rebuild)
GSA1.MapOptionHooks = GSA1.MapOptionHooks or {}
function GSA1.MapOptions()
    local o = { static_props = GSA1.cv.static_props:GetBool(), brush_models = true, cache = GSA1.cv.map_cache:GetBool(),
                thin_wall_max = math.Clamp(math.floor(GSA1.cv.thin_walls:GetFloat() + 0.5), 0, 64) }
    local names = {}
    for name in pairs(GSA1.MapOptionHooks) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do GSA1.MapOptionHooks[name](o) end
    return o
end

local function close_file()
    if W.file then
        W.file:Close()
        W.file = nil
    end
end

local function world_failed(msg)
    close_file()
    W.state = "failed"
    W.err = tostring(msg)
    GSA1.Msg("map collision: %s", W.err)
    if GSA1.pendingSpawn then
        GSA1.pendingSpawn = nil
        GSA1.Chat("cannot spawn: the map's collision failed to load (%s)", W.err)
    end
end

-- starts loading the current map's collision (nothing happens if it is loading or loaded with these settings)
function GSA1.StartWorld(force)
    local ok, err = GSA1.LoadModule()
    if not ok then return false, err end
    local map = game.GetMap()
    local opts = GSA1.MapOptions()
    local key = map .. (opts.static_props and " props" or "") .. (opts.cache and " cache" or "") .. " tw"
        .. opts.thin_wall_max .. (opts.world_key or "")
    if not force and W.key == key and W.state ~= "failed" and W.state ~= "idle" then return true end
    close_file()
    W.key, W.map, W.err, W.progress, W.stage = key, map, nil, 0, "starting"
    W.t0 = SysTime()
    W.poll = {}
    local t0 = SysTime()
    local res, how, code = gsa1.MapStart(map, opts)
    if not res and code == "not_found" then
        -- a workshop / mounted map: Garry's Mod's own file system finds it; the module asks for the ranges it reads
        local f = file.Open("maps/" .. map .. ".bsp", "rb", "GAME")
        if not f then
            prof("LoadWorld", t0)
            world_failed("maps/" .. map .. ".bsp cannot be opened")
            return false, W.err
        end
        local size = f:Size()
        local head = f:Read(1036)
        if not head or #head < 1036 then
            f:Close()
            prof("LoadWorld", t0)
            world_failed("maps/" .. map .. ".bsp is too short")
            return false, W.err
        end
        res, how, code = gsa1.MapStartData(map, head, size, opts)
        if res then W.file = f else f:Close() end
    end
    prof("LoadWorld", t0)
    if not res then
        world_failed(how)
        return false, W.err
    end
    W.how = how
    W.state = "loading"
    return true
end

-- a file the map job asked for (a model's .phy / .mdl head, a material's .vmt, a surfaceproperties script): the whole
-- file, or its first `max` bytes; nil when it cannot be read. A material missing from "GAME" is looked for in the map's
-- own pak ("BSP": map-specific patch materials, in case "GAME" does not search it)
local function read_game_file(path, max)
    local f = file.Open(path, "rb", "GAME")
    if not f and string.sub(path, 1, 10) == "materials/" then f = file.Open(path, "rb", "BSP") end
    if not f then return nil end
    local size = f:Size()
    local n = (max and max > 0) and math.min(max, size) or size
    local data = n > 0 and f:Read(n) or nil
    f:Close()
    return data
end

-- 0.9.2a (the 0.9.2 verifier's leftover): 0.9.2's collision guard and thin stacks in the map line ("" when all are 0)
function GSA1.WorldGuardText(i)
    local parts = {}
    local function add(n, text) if (tonumber(n) or 0) > 0 then parts[#parts + 1] = string.format(text, n) end end
    add(i.tris_outside, "%d triangles outside the map left out")
    add(i.frags_outside, "%d pieces outside their solids left out")
    add(i.props_outside, "%d static props outside the map not placed")
    add(i.displacements_nohull, "%d displacements without collision left out")
    add(i.thin_stacks, "%d stacked faces made one")
    add(i.thin_wall_kept, "%d thin-wall pairs kept as two faces")
    if i.prepare_retried then
        parts[#parts + 1] = string.format("prepared again without %d triangles outside the map", i.prepare_left_out or 0)
    end
    return table.concat(parts, ", ")
end

function GSA1.ApplyWorld()
    local t0 = SysTime()
    local ok, info, code = gsa1.MapApply()
    prof("Apply", t0)
    GSA1.DrainLog()
    if not ok then
        if code == "busy" or code == "not_ready" then return false end
        world_failed(info)
        return false
    end
    W.state = "applied"
    W.info = info
    GSA1.worldMap = W.map
    GSA1.worldInfo = info
    -- features that report on the applied world (GSA1.WorldAppliedHooks[name] = function(map, info); 0.8: the surfaces
    -- log line)
    for name, fn in pairs(GSA1.WorldAppliedHooks or {}) do
        local hok, herr = pcall(fn, W.map, info)
        if not hok then GSA1.Msg("%s: %s", tostring(name), tostring(herr)) end
    end
    GSA1.Msg("world %s: %d collision triangles (%d static props placed, %d brush entity models, %d one-way platforms, "
        .. "%d thin walls) %s, %s, in %.1f s", W.map, info.triangles, info.props_placed, info.brush_models,
        info.one_way_solids, info.thin_walls or 0,
        info.from_cache and "from the cache" or ("built" .. (info.cache_written and ", cached" or "")),
        info.prepared and string.format("prepared for the game in %.0f ms on a worker (%d pieces)", info.prepare_ms,
            info.grid_triangles) or (info.too_big and "too big for the game" or ("not prepared ahead: " ..
            tostring(info.prepare_note))),
        SysTime() - (W.t0 or SysTime()))
    local guard = GSA1.WorldGuardText(info)
    if guard ~= "" then GSA1.Msg("world %s, collision clean-up: %s", W.map, guard) end
    if info.too_big then
        -- 0.9.2a: no character can be made here (gsa1.Create refuses at once, with the same words)
        GSA1.Chat("this map's collision is too big for the game, so no character can be created on this map (see the "
            .. "console)")
        GSA1.Msg("%s", tostring(info.too_big_note))
    end
    if info.props_note ~= "" then GSA1.Msg("static props: %s", info.props_note) end
    if info.props_missing > 0 then
        GSA1.Msg("%d static props have no physics model here (%d of %d model files missing)", info.props_missing,
            info.prop_models_missing, info.prop_models)
    end
    if not info.from_cache and info.cache_note ~= "" and GSA1.cv.debug:GetBool() then
        GSA1.Msg("map cache: %s", info.cache_note)
    end
    -- characters keep the world they were created with: the current one is re-created where it stands
    if GSA1.Char and GSA1.Recreate then GSA1.Recreate("the map's collision was loaded") end
    local pending = GSA1.pendingSpawn
    GSA1.pendingSpawn = nil
    if pending and GSA1.Spawn then GSA1.Spawn(pending) end
    return true
end

-- once per frame: drives the job (map bytes and model files within a time budget), then applies the result
function GSA1.WorldThink()
    if not GSA1.mod then return end
    if W.state == "ready" then
        if gsa1.IsReady() then GSA1.ApplyWorld() end
        return
    end
    if W.state ~= "loading" then return end
    local t0 = SysTime()
    local p = gsa1.MapPoll(W.poll)
    if not p then
        prof("LoadWorld", t0)
        world_failed("the map job is gone")
        return
    end
    W.progress, W.stage = p.progress, p.state
    if p.state == "reading" then
        if not W.file then
            prof("LoadWorld", t0)
            world_failed("the module asks for map bytes but the map is not open")
            return
        end
        for _, r in ipairs(p.needs) do
            local ofs, left = r.ofs, r.len
            while left > 0 do
                local n = math.min(left, MAX_FEED)
                W.file:Seek(ofs)
                local data = W.file:Read(n)
                if not data or #data ~= n then
                    prof("LoadWorld", t0)
                    world_failed(string.format("reading the map failed at byte %d", ofs))
                    return
                end
                local ok, err = gsa1.MapFeed(ofs, data)
                if not ok then
                    prof("LoadWorld", t0)
                    world_failed(err)
                    return
                end
                ofs, left = ofs + n, left - n
            end
            if SysTime() - t0 > READ_BUDGET then break end
        end
    elseif p.state == "files" then
        for _, f in ipairs(p.files) do
            gsa1.MapFeedFile(f.path, read_game_file(f.path, f.max))
            if SysTime() - t0 > READ_BUDGET then break end
        end
    elseif p.state == "ready" then
        close_file()
        W.state = "ready"
        prof("LoadWorld", t0)
        if gsa1.IsReady() then GSA1.ApplyWorld() end
        return
    elseif p.state == "failed" then
        prof("LoadWorld", t0)
        world_failed(p.error ~= "" and p.error or "failed")
        return
    end
    prof("LoadWorld", t0)
end

-- "loading the map's collision: reading 40%"
function GSA1.WorldLoadingText()
    if W.state == "loading" or W.state == "ready" then
        local stage = ({ cache = "checking the cache", reading = "reading the map", parsing = "parsing",
                         files = "reading the props' physics models and the materials",
                         materials = "reading the materials", building = "building",
                         preparing = "preparing it for the game", ready = "ready" })[W.stage]
            or W.stage or "starting"
        return string.format("loading the map's collision: %s %d%%", stage, math.floor((W.progress or 0) * 100 + 0.5))
    end
    if W.state == "failed" then return "the map's collision failed: " .. tostring(W.err) end
    return nil
end

-- what a spawn waits for, as text ("loading your disc; loading the map's collision: reading the map 40%"), or nil
function GSA1.LoadingText()
    local parts = {}
    if GSA1.discLoading then parts[#parts + 1] = "loading your disc" end
    local w = GSA1.WorldLoadingText()
    if w then parts[#parts + 1] = w end
    if #parts == 0 then return nil end
    return table.concat(parts, "; ")
end

-- everything a spawn needs; returns ok, message (message "loading": the disc or the map's collision is still loading -
-- the spawn happens by itself when they are ready). Both load at the same time, in the background.
function GSA1.EnsureReady()
    local ok, err = GSA1.InitDisc()
    if not ok and err ~= "loading" then return false, err end
    local current = W.state == "applied" and GSA1.worldMap == game.GetMap()
    if not current and W.state ~= "loading" and W.state ~= "ready" then
        local wok, werr = GSA1.StartWorld(false)
        if not wok then return false, "map collision: " .. tostring(werr) end
    end
    if not ok then return false, "loading" end
    if current then return true end
    if W.state == "ready" and GSA1.ApplyWorld() then return true end
    return false, "loading"
end

function GSA1.DrainLog()
    if not GSA1.mod then return end
    local lines = gsa1.PollLog()
    local dbg = GSA1.cv.debug:GetBool()
    for _, l in ipairs(lines) do
        if dbg or string.find(l, "error", 1, true) or string.find(l, "warn", 1, true) then
            GSA1.Note("libsa1", "%s", l)          -- console and log
        elseif GSA1.Log then
            GSA1.Log("libsa1", "%s", l)           -- the log only
        end
    end
end

-- the cache files (garrysmod/data/gsa1/cache/<map>.dat)
function GSA1.CacheFiles()
    local files = file.Find("gsa1/cache/*.dat", "DATA") or {}
    local bytes = 0
    for _, f in ipairs(files) do bytes = bytes + (file.Size("gsa1/cache/" .. f, "DATA") or 0) end
    return files, bytes
end

concommand.Add("gsa1_init", function()
    local ok, err = GSA1.EnsureReady()
    if ok then
        GSA1.Msg("ready")
    elseif err == "loading" then
        GSA1.Msg("%s (in the background; used as soon as it is ready)", GSA1.LoadingText() or "loading")
    else
        GSA1.Chat("%s", tostring(err))
    end
end, nil, "G-SA1: load the module, your disc and the map's collision")

concommand.Add("gsa1_choose_disc", function()
    local ok, err = GSA1.LoadModule()
    if not ok then GSA1.Chat("%s", err) return end
    local res, msg = gsa1.ChooseDisc()
    GSA1.Chat("%s", tostring(msg))
end, nil, "G-SA1: pick your .gdi in a file dialog (Windows); the path is stored by the module, not by Lua")

concommand.Add("gsa1_reload_world", function()
    local ok, err = GSA1.StartWorld(true)
    if not ok then GSA1.Chat("%s", tostring(err)) return end
    GSA1.Msg("reloading the map's collision (the character is re-created where it stands when it is ready)")
end, nil, "G-SA1: load the map's collision again (from the cache if there is one; gsa1_cache_purge first rebuilds it)")

concommand.Add("gsa1_cache_purge", function()
    local files = GSA1.CacheFiles()
    local n = 0
    for _, f in ipairs(files) do
        file.Delete("gsa1/cache/" .. f)
        if not file.Exists("gsa1/cache/" .. f, "DATA") then n = n + 1 end
    end
    -- this map's collision is built and prepared again in the background and swapped in when it is ready
    local rebuild = GSA1.mod and W.state ~= "idle" and W.state ~= "failed"
    GSA1.Msg("map cache: %d file(s) deleted (garrysmod/data/gsa1/cache)%s", n,
        rebuild and "; this map's collision is built again in the background" or "")
    if rebuild then GSA1.StartWorld(true) end
end, nil, "G-SA1: delete the cached map collision (garrysmod/data/gsa1/cache/*.dat); this map's is rebuilt in the background")

-- settings that change the static world: load it again
for _, name in ipairs({ "gsa1_static_props", "gsa1_map_cache", "gsa1_thin_walls" }) do
    cvars.AddChangeCallback(name, function()
        if GSA1.mod and W.state ~= "idle" then
            timer.Create("gsa1_world_settings", 0.5, 1, function() GSA1.StartWorld(false) end)
        end
    end, "gsa1_world")
end

-- the map starts: load the disc and the map's collision in the background (gsa1_preload), both on the module's
-- worker threads, so the first spawn finds them ready
hook.Add("InitPostEntity", "gsa1_preload", function()
    if not GSA1.cv.preload:GetBool() then return end
    timer.Simple(1, function()
        if util.IsBinaryModuleInstalled and util.IsBinaryModuleInstalled(GSA1.MODULE) and GSA1.LoadModule() then
            GSA1.StartWorld(false)
            local ok, err = GSA1.InitDisc()
            if not ok and err ~= "loading" then GSA1.Msg("disc: %s", tostring(err)) end
        end
    end)
end)

-- the state of everything, as lines (console and the options menu's read-out)
function GSA1.StatusLines()
    local out = {}
    if not GSA1.LoadModule() then
        out[1] = "module: " .. tostring(GSA1.moduleError)
        return out
    end
    local s = gsa1.Status()
    out[#out + 1] = string.format("module %s (API %d, libsa1 %s); addon %s", s.version, s.api, s.libsa1, GSA1.VERSION)
    out[#out + 1] = GSA1.FeatureLine()
    out[#out + 1] = string.format("config file %s", s.config)
    local disc
    if s.ready then
        disc = string.format("loaded (%.0f ms on a worker thread)", s.disc_ms)
    elseif s.disc_state == "loading" then
        disc = string.format("loading on a worker thread (%.1f s so far)", (s.disc_wait_ms or 0) / 1000)
    elseif s.disc_state == "failed" then
        disc = "failed: " .. tostring(s.disc_error)
    else
        disc = "not loaded"
    end
    out[#out + 1] = "disc: " .. disc
    for _, l in ipairs(GSA1.WorldLines()) do out[#out + 1] = l end
    local a = gsa1.AudioStatus()
    if a.open then
        out[#out + 1] = string.format("sound: %s voices; output %s%s; %d playing, %.0f ms queued, %d events",
            a.japanese and "Japanese" or "English", a.output and a.backend or "none",
            (a.error ~= "" and not a.output) and (" (" .. a.error .. ")") or "", a.active, a.queued_ms, a.events)
        if a.loader_thread ~= nil then
            out[#out + 1] = string.format("  disc reads %s: %s, %d clips cached (%.1f MB), %d read, slowest %.0f ms%s",
                a.loader_thread and "on libsa1's loader thread" or "ON THE GAME'S THREAD",
                a.preload_done and "preloaded" or "preloading", a.clips_cached, a.cache_mb, a.clip_reads, a.max_read_ms,
                a.cues_dropped > 0 and string.format(", %d cues dropped", a.cues_dropped) or "")
        end
    elseif a.opening then
        out[#out + 1] = string.format("sound: opening the sound banks on a worker thread (%.1f s so far)",
            (a.opening_ms or 0) / 1000)
    else
        out[#out + 1] = "sound: " .. (GSA1.cv.sound:GetBool() and ((a.open_error or "") ~= "" and
            ("failed: " .. a.open_error) or "not open") or "off")
    end
    if GSA1.PadStatusLine then out[#out + 1] = GSA1.PadStatusLine() end
    if GSA1.HitchLine then out[#out + 1] = GSA1.HitchLine() end
    if GSA1.LogLine then out[#out + 1] = GSA1.LogLine() end
    if GSA1.WarmLine then out[#out + 1] = GSA1.WarmLine() end
    out[#out + 1] = string.format("characters: %d", s.characters)
    local C = GSA1.Char
    if C then
        local st = C.state
        out[#out + 1] = string.format("%s: pos (%.0f %.0f %.0f) action %d mode %d %s; tick %.3f ms", C.title,
            st.x or 0, st.y or 0, st.z or 0, st.action or -1, st.mode or -1, st.ground and "ground" or "air",
            st.tick_ms or 0)
        out[#out + 1] = string.format("drawing: %d triangles in %d batches, %s; textures pending %d",
            C.triangles or 0, C.batches and C.batches.count or 0, C.interpolated and "interpolated" or
            (C.shifted and "moved with the root by libsa1" or "raw 30 Hz frames"), GSA1.Tex.Pending())
        out[#out + 1] = string.format("upgrades: %s (the game's equipment 0x%04X%s)", GSA1.UpgradeText(C.upgrades),
            st.equipment or 0, st.upgrades_ok == false and ": not what the upgrades ask for, see the console" or "")
    end
    if GSA1.Tex and GSA1.Tex.FormatLine then out[#out + 1] = GSA1.Tex.FormatLine() end
    return out
end

-- the map's collision as lines (StatusLines, the Collision page)
function GSA1.WorldLines()
    local out = {}
    local loading = GSA1.WorldLoadingText()
    if W.state == "applied" and W.info then
        local i = W.info
        out[#out + 1] = string.format("world %s: %d collision triangles (%s in %.1f s)", i.map, i.triangles,
            i.from_cache and "from the cache" or "built", i.from_cache and (i.cache_ms / 1000) or (i.build_ms / 1000))
        out[#out + 1] = string.format("  static props: %d of %d solid placed (%d physics pieces, %d triangles)%s",
            i.props_placed, i.props_solid, i.prop_hulls, i.prop_triangles,
            GSA1.cv.static_props:GetBool() and (i.props_missing > 0 and string.format(", %d without a physics model",
                i.props_missing) or "") or " - off")
        out[#out + 1] = string.format("  brush entities: %d models; one-way platforms: %d; thin walls: %d (up to %d "
            .. "units); displacements: %d", i.brush_models, i.one_way_solids, i.thin_walls or 0, i.thin_wall_max or 0,
            i.displacements)
        out[#out + 1] = i.prepared and string.format("  prepared for the game on a worker in %.0f ms: %d pieces in %d "
            .. "land objects (%d undersides left out); shared by every character", i.prepare_ms, i.grid_triangles,
            i.grid_objects, i.grid_undersides)
            or (i.too_big and ("  too big for the game: no character can be created on this map (" ..
                tostring(i.too_big_note) .. ")")
            or ("  not prepared ahead (" .. tostring(i.prepare_note) .. "): the first character builds it"))
        local guard = GSA1.WorldGuardText(i)
        if guard ~= "" then out[#out + 1] = "  collision clean-up: " .. guard end
    elseif loading then
        out[#out + 1] = loading
    else
        out[#out + 1] = "world: none yet"
    end
    if loading and W.state == "applied" then out[#out + 1] = loading end
    if GSA1.MoverLine then out[#out + 1] = GSA1.MoverLine() end
    local files, bytes = GSA1.CacheFiles()
    out[#out + 1] = string.format("map cache: %d map(s), %.1f MB (garrysmod/data/gsa1/cache)%s", #files, bytes / 1048576,
        GSA1.cv.map_cache:GetBool() and "" or ", off")
    return out
end

concommand.Add("gsa1_status", function()
    for _, l in ipairs(GSA1.StatusLines()) do GSA1.Msg("%s", l) end
end, nil, "G-SA1: print the module's state")

concommand.Add("gsa1_sound_reopen", function()
    local ok, msg = GSA1.OpenAudio()
    if not ok then GSA1.Chat("sound: %s", tostring(msg)) end
end, nil, "G-SA1: reopen the sound banks and the audio output")

-- the disc and the map's collision loading, on screen (while a spawn waits for them, or with gsa1_debug)
hook.Add("HUDPaint", "gsa1_world_loading", function()
    if not GSA1.pendingSpawn and not (GSA1.cv.debug:GetBool() and (W.state == "loading" or GSA1.discLoading)) then
        return
    end
    local text = GSA1.LoadingText()
    if not text then return end
    draw.SimpleTextOutlined("G-SA1: " .. text, "DermaLarge", ScrW() / 2, ScrH() * 0.2, color_white, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER, 1, color_black)
end)

hook.Add("ShutDown", "gsa1", function()
    if GSA1.LogSummary then GSA1.LogSummary("shutdown") end
    close_file()
    if GSA1.mod and gsa1.Shutdown then
        if gsa1.AudioClose then gsa1.AudioClose() end
        gsa1.Shutdown()
    end
end)
