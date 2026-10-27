// G-SA1 core: configuration file.
#include "config.hpp"

#include <cstdlib>
#include <cstring>

#include "libsa1_internal_api.hpp"
#include "util.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

namespace gsa1 {

static const size_t kMaxConfigBytes = 4096;
static const int kMaxConfigLines = 64;
static const size_t kMaxPathBytes = 1024;

static bool is_ws(char c)
{
    return c == ' ' || c == '\t';
}

static std::string trim(const std::string &s)
{
    size_t a = 0, b = s.size();
    while (a < b && is_ws(s[a])) {
        a++;
    }
    while (b > a && is_ws(s[b - 1])) {
        b--;
    }
    return s.substr(a, b - a);
}

bool validate_disc_path(const std::string &path, std::string &err)
{
    if (path.empty()) {
        err = "the disc path is empty";
        return false;
    }
    if (path.size() > kMaxPathBytes) {
        err = "the disc path is longer than 1024 bytes";
        return false;
    }
    if (!valid_utf8(path.data(), path.size())) {
        err = "the disc path is not valid UTF-8";
        return false;
    }
    for (unsigned char c : path) {
        if (c < 0x20 || c == 0x7F) {
            err = "the disc path contains a control character";
            return false;
        }
    }
#ifdef _WIN32
    bool absolute = path.size() >= 3 && ((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z')) &&
                    path[1] == ':' && (path[2] == '\\' || path[2] == '/');
#else
    bool absolute = path[0] == '/' && !(path.size() > 1 && path[1] == '/');
#endif
    if (!absolute) {
#ifdef _WIN32
        err = "the disc path must be absolute (like D:\\games\\sa1\\game.gdi)";
#else
        err = "the disc path must be absolute (like /home/me/sa1/game.gdi)";
#endif
        return false;
    }
    // no "." / ".." components: the path names the file directly
    size_t start = 0;
    for (size_t i = 0; i <= path.size(); i++) {
        if (i == path.size() || path[i] == '/' || path[i] == '\\') {
            std::string comp = path.substr(start, i - start);
            if (comp == "." || comp == "..") {
                err = "the disc path must not contain '.' or '..' components";
                return false;
            }
            start = i + 1;
        }
    }
    if (!ends_with_ci(path, ".gdi")) {
        err = "the disc path must name a .gdi file";
        return false;
    }
    if (sa1_path_check_host(path.c_str()) != SA1_OK) {
        err = "the disc path is rejected by libsa1 (UNC, device or stream path)";
        return false;
    }
    return true;
}

bool parse_config(const std::string &text_in, Config &out, std::string &err)
{
    out = Config();
    if (text_in.size() > kMaxConfigBytes) {
        err = "the config file is larger than 4096 bytes";
        return false;
    }
    std::string text = text_in;
    if (text.size() >= 3 && (unsigned char)text[0] == 0xEF && (unsigned char)text[1] == 0xBB &&
        (unsigned char)text[2] == 0xBF) {
        text = text.substr(3);
    }
    if (std::memchr(text.data(), 0, text.size()) != nullptr) {
        err = "the config file contains a NUL byte";
        return false;
    }
    if (!valid_utf8(text.data(), text.size())) {
        err = "the config file is not valid UTF-8";
        return false;
    }
    bool have_disc = false;
    int line_no = 0;
    size_t pos = 0;
    while (pos <= text.size()) {
        size_t nl = text.find('\n', pos);
        std::string line = text.substr(pos, nl == std::string::npos ? std::string::npos : nl - pos);
        pos = (nl == std::string::npos) ? text.size() + 1 : nl + 1;
        line_no++;
        if (line_no > kMaxConfigLines) {
            err = "the config file has more than 64 lines";
            return false;
        }
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        for (unsigned char c : line) {
            if ((c < 0x20 && c != '\t') || c == 0x7F) {
                err = format("line %d: control character", line_no);
                return false;
            }
        }
        std::string t = trim(line);
        if (t.empty() || t[0] == '#') {
            continue;
        }
        size_t eq = t.find('=');
        if (eq == std::string::npos) {
            err = format("line %d: expected 'key = value'", line_no);
            return false;
        }
        std::string key = trim(t.substr(0, eq));
        std::string value = trim(t.substr(eq + 1));
        if (key.empty()) {
            err = format("line %d: missing key", line_no);
            return false;
        }
        for (char c : key) {
            if (!((c >= 'a' && c <= 'z') || c == '_')) {
                err = format("line %d: invalid key", line_no);
                return false;
            }
        }
        if (!value.empty() && value[0] == '"') {
            if (value.size() < 2 || value.back() != '"') {
                err = format("line %d: unterminated quote", line_no);
                return false;
            }
            value = value.substr(1, value.size() - 2);
            if (value.find('"') != std::string::npos) {
                err = format("line %d: quote inside the value", line_no);
                return false;
            }
        } else if (value.find('"') != std::string::npos) {
            err = format("line %d: quote inside the value", line_no);
            return false;
        }
        if (key == "disc") {
            if (have_disc) {
                err = format("line %d: 'disc' is given twice", line_no);
                return false;
            }
            std::string perr;
            if (!validate_disc_path(value, perr)) {
                err = format("line %d: ", line_no) + perr;
                return false;
            }
            out.disc = value;
            have_disc = true;
        } else {
            err = format("line %d: unknown key '%s' (the only key is 'disc')", line_no, key.c_str());
            return false;
        }
    }
    if (!have_disc) {
        err = "the config file has no 'disc = <path of your .gdi>' line";
        return false;
    }
    return true;
}

std::string serialize_config(const Config &c)
{
    std::string s = "# G-SA1 configuration (read by the gmcl_gsa1 module only; Lua cannot read or write this file)\n";
    s += "# disc = absolute path of your Sonic Adventure (US, v1.005) .gdi\n";
    s += "disc = " + c.disc + "\n";
    return s;
}

std::string config_dir()
{
#ifdef _WIN32
    wchar_t buf[2048];
    DWORD n = GetEnvironmentVariableW(L"APPDATA", buf, (DWORD)(sizeof buf / sizeof buf[0]));
    if (n == 0 || n >= sizeof buf / sizeof buf[0]) {
        return std::string();
    }
    std::string base = narrow(std::wstring(buf, n));
    if (base.size() < 3 || base[1] != ':') {
        return std::string();   // not a local drive path (UNC profile directories are not used)
    }
    return join_path(base, "gsa1");
#else
    const char *x = std::getenv("XDG_CONFIG_HOME");
    if (x && x[0] == '/') {
        return join_path(x, "gsa1");
    }
    const char *h = std::getenv("HOME");
    if (h && h[0] == '/') {
        return join_path(join_path(h, ".config"), "gsa1");
    }
    return std::string();
#endif
}

std::string config_file()
{
    std::string d = config_dir();
    return d.empty() ? d : join_path(d, "config.txt");
}

const char *config_file_display()
{
#ifdef _WIN32
    return "%APPDATA%\\gsa1\\config.txt";
#else
    return "~/.config/gsa1/config.txt (or $XDG_CONFIG_HOME/gsa1/config.txt)";
#endif
}

bool load_config_file(const std::string &path, Config &out, std::string &err)
{
    std::string text;
    if (!file_exists(path)) {
        err = "missing";
        return false;
    }
    if (!read_small_file(path, kMaxConfigBytes, text, err)) {
        return false;
    }
    return parse_config(text, out, err);
}

bool load_config(Config &out, std::string &err)
{
    std::string path = config_file();
    if (path.empty()) {
        err = "the configuration directory is unknown (APPDATA / HOME not set)";
        return false;
    }
    std::string e;
    if (!load_config_file(path, out, e)) {
        if (e == "missing") {
            err = format("no configuration file: create %s with the line  disc = <absolute path of your .gdi>  "
                         "(or run gsa1_choose_disc on Windows)", config_file_display());
        } else {
            err = std::string(config_file_display()) + ": " + e;
        }
        return false;
    }
    return true;
}

bool save_config(const Config &c, std::string &err)
{
    std::string e;
    if (!validate_disc_path(c.disc, e)) {
        err = e;
        return false;
    }
    std::string dir = config_dir();
    if (dir.empty() || !make_dirs(dir)) {
        err = "cannot create the configuration directory";
        return false;
    }
    if (!write_file_replace(config_file(), serialize_config(c), e)) {
        err = std::string(config_file_display()) + ": " + e;
        return false;
    }
    return true;
}

}  // namespace gsa1
