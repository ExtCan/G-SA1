// G-SA1 core: module location and map lookup.
#include "paths.hpp"

#include "libsa1_internal_api.hpp"
#include "util.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace gsa1 {

static void self_anchor() {}

std::string self_module_path()
{
#ifdef _WIN32
    HMODULE h = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCWSTR)(void *)&self_anchor, &h)) {
        return std::string();
    }
    std::wstring buf(32768, L'\0');
    DWORD n = GetModuleFileNameW(h, &buf[0], (DWORD)buf.size());
    if (n == 0 || n >= buf.size()) {
        return std::string();
    }
    buf.resize(n);
    return narrow(buf);
#else
    Dl_info info;
    if (dladdr((void *)&self_anchor, &info) == 0 || info.dli_fname == nullptr) {
        return std::string();
    }
    return info.dli_fname;
#endif
}

static bool name_eq(const std::string &a, const char *b)
{
#ifdef _WIN32
    return iequals(a, b);
#else
    return a == b;
#endif
}

bool garrysmod_dir_from_module(const std::string &module_path, std::string &garrysmod_dir)
{
    std::string bin = parent_dir(module_path);
    std::string lua = parent_dir(bin);
    std::string gm = parent_dir(lua);
    if (bin.empty() || lua.empty() || gm.empty()) {
        return false;
    }
    if (!name_eq(base_name(bin), "bin") || !name_eq(base_name(lua), "lua")) {
        return false;
    }
    garrysmod_dir = gm;
    return true;
}

bool valid_map_name(const std::string &name)
{
    if (name.empty() || name.size() > 64 || name[0] == '.') {
        return false;
    }
    for (char c : name) {
        bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' ||
                  c == '.' || c == '+';
        if (!ok) {
            return false;
        }
    }
    return sa1_path_check_bare(name.c_str()) == SA1_OK && sa1_path_check_bare((name + ".bsp").c_str()) == SA1_OK;
}

bool find_map_file(const std::string &garrysmod_dir, const std::string &name, std::string &path_out,
                   std::string &searched)
{
    searched.clear();
    if (!valid_map_name(name) || garrysmod_dir.empty()) {
        return false;
    }
    const std::string file = name + ".bsp";
    std::vector<std::pair<std::string, std::string>> dirs;   // (absolute, shown)
    dirs.push_back({join_path(garrysmod_dir, "maps"), "maps"});
    dirs.push_back({join_path(join_path(garrysmod_dir, "download"), "maps"), "download/maps"});
    std::string addons = join_path(garrysmod_dir, "addons");
    for (const std::string &a : list_subdirs(addons)) {
        if (sa1_path_check_bare(a.c_str()) != SA1_OK) {
            continue;
        }
        dirs.push_back({join_path(join_path(addons, a), "maps"), "addons/*/maps"});
    }
    std::string last_shown;
    for (const auto &d : dirs) {
        if (d.second != last_shown) {
            searched += (searched.empty() ? "" : ", ") + d.second;
            last_shown = d.second;
        }
        std::string p = join_path(d.first, file);
        if (file_exists(p)) {
            path_out = p;
            return true;
        }
    }
    return false;
}

}  // namespace gsa1
