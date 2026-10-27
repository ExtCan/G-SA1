// G-SA1 core: the module-owned configuration file (the disc path).
//
// Security (sadc docs/research/critique.md 5.2): the disc path never comes from Lua. It is read
// from a file that GMod's Lua cannot read or write - it lives outside the game directory:
//   Windows: %APPDATA%\gsa1\config.txt
//   Linux:   $XDG_CONFIG_HOME/gsa1/config.txt  (default ~/.config/gsa1/config.txt)
// and is validated here (strict grammar, absolute path, .gdi) and by libsa1's own path rules
// (no UNC / device / NT-object paths, no alternate data streams, no DOS device names).
//
// Grammar (UTF-8, optional BOM, at most 4096 bytes and 64 lines, LF or CRLF):
//   line    := ws* [ '#' comment | key ws* '=' ws* value ] ws*
//   key     := "disc"                     (unknown keys and repeated keys are errors)
//   value   := text without control characters, optionally in double quotes
#pragma once

#include <string>

namespace gsa1 {

struct Config {
    std::string disc;   // absolute path of the user's .gdi (UTF-8)
};

bool parse_config(const std::string &text, Config &out, std::string &err);
// The checks applied to `disc` (also used for paths picked in the native file dialog).
bool validate_disc_path(const std::string &path, std::string &err);
std::string serialize_config(const Config &c);

std::string config_dir();                // "" when the platform directory is unknown
std::string config_file();               // config_dir()/config.txt
const char *config_file_display();       // the path with the variable unexpanded (safe to show to Lua)

bool load_config_file(const std::string &path, Config &out, std::string &err);
bool load_config(Config &out, std::string &err);
bool save_config(const Config &c, std::string &err);

}  // namespace gsa1
