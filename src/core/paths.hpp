// G-SA1 core: where the module is, where Garry's Mod keeps its maps.
//
// The module never opens a path that Lua gave it. The garrysmod directory is derived from the module's own
// file location (garrysmod/lua/bin/gmcl_gsa1_<platform>.dll); a map is looked up by its bare NAME (validated
// strictly) in a fixed list of directories below it.
#pragma once

#include <string>
#include <vector>

namespace gsa1 {

// Full path of the binary that contains this code (the module DLL / .so, or the test executable).
std::string self_module_path();
// "<...>/garrysmod" when module_path is "<...>/garrysmod/lua/bin/<file>" (case-insensitive on Windows).
bool garrysmod_dir_from_module(const std::string &module_path, std::string &garrysmod_dir);

// Map names: 1-64 characters of [A-Za-z0-9_-.+], no leading '.', and libsa1's bare-file-name rules.
bool valid_map_name(const std::string &name);

// Looks for <name>.bsp in garrysmod/maps, garrysmod/download/maps and garrysmod/addons/*/maps.
// `searched` lists the directories (relative to garrysmod) for messages.
bool find_map_file(const std::string &garrysmod_dir, const std::string &name, std::string &path_out,
                   std::string &searched);

}  // namespace gsa1
