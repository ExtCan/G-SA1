-- G-SA1: Sonic Adventure characters in Garry's Mod (Lua side). Bootstrap, both realms.
--
-- The game logic, collision and character meshes come from the binary module gmcl_gsa1_<platform>.dll
-- (garrysmod/lua/bin, not part of any addon) and from the player's own Sonic Adventure disc image; this addon
-- holds no game data. The server side is pure Lua and needs neither the module nor a disc.
--
-- Features (G0): after the built-in files, every gsa1/feat/*.lua is loaded - sh_<feature>.lua in both realms first,
-- then cl_<feature>.lua on the client and sv_<feature>.lua on the server, each group in alphabetical order (the server
-- sends the sh_ and cl_ files to the clients). A feature file that fails to load is reported and left out; the
-- others and G-SA1 itself carry on (GSA1.FeatureFiles, GSA1.FeatureFileErrors: the status lines, the session log).
GSA1 = GSA1 or {}

local shared = { "gsa1/sh_config.lua", "gsa1/sh_net.lua" }
local client = { "gsa1/cl_log.lua", "gsa1/cl_hitch.lua", "gsa1/cl_module.lua", "gsa1/cl_collision.lua", "gsa1/cl_pad.lua",
                 "gsa1/cl_textures.lua", "gsa1/cl_warm_census.lua", "gsa1/cl_warm.lua", "gsa1/cl_render.lua",
                 "gsa1/cl_character.lua", "gsa1/cl_menu.lua" }

-- the feature files, by kind (sh / cl / sv), each sorted
local function feature_files()
    local found = file.Find("gsa1/feat/*.lua", "LUA") or {}
    local kinds = { sh = {}, cl = {}, sv = {} }
    for _, name in ipairs(found) do
        local list = kinds[string.sub(string.lower(name), 1, 2)]
        if list and string.sub(name, 3, 3) == "_" then list[#list + 1] = name end
    end
    for _, list in pairs(kinds) do table.sort(list) end
    return kinds
end

local function load_feature(name, run, send)
    local path = "gsa1/feat/" .. name
    if send then AddCSLuaFile(path) end
    if not run then return end
    local ok, err = pcall(include, path)
    if ok then
        GSA1.FeatureFiles[#GSA1.FeatureFiles + 1] = name
    else
        GSA1.FeatureFileErrors[#GSA1.FeatureFileErrors + 1] = name .. ": " .. tostring(err)
        ErrorNoHalt("[G-SA1] the feature file " .. path .. " failed to load: " .. tostring(err) .. "\n")
    end
end

GSA1.FeatureFiles, GSA1.FeatureFileErrors = {}, {}
local feat = feature_files()
if SERVER then
    for _, f in ipairs(shared) do AddCSLuaFile(f) include(f) end
    for _, f in ipairs(client) do AddCSLuaFile(f) end
    include("gsa1/sv_gsa1.lua")
    for _, f in ipairs(feat.sh) do load_feature(f, true, true) end
    for _, f in ipairs(feat.cl) do load_feature(f, false, true) end
    for _, f in ipairs(feat.sv) do load_feature(f, true, false) end
else
    for _, f in ipairs(shared) do include(f) end
    for _, f in ipairs(client) do include(f) end
    for _, f in ipairs(feat.sh) do load_feature(f, true, false) end
    for _, f in ipairs(feat.cl) do load_feature(f, true, false) end
end
