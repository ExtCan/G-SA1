/*
 * lua_host.c - runs a Lua test script in Garry's Mod's own LuaJIT (bin/win64/lua_shared.dll of the GMod install,
 * loaded read-only; GMOD_LUA_SHARED overrides the path), so the addon's Lua is tested offline in the interpreter it
 * runs in, against a mock of the GMod client (tests/lua_mock.lua). Built and run by build.py --test (Windows).
 *   lua_host script.lua [args...]          exit 0: the script returned true; 1: false or a Lua error; 3: no LuaJIT
 * Helpers the script gets (GMod's lua_shared.dll has no io library, its print goes to the engine console, and its
 * base library has no loadstring / load):
 *   host_read(path) -> contents | nil      host_load(source, name) -> function | nil, message
 *   host_write(text)                       host_clock() -> seconds (QueryPerformanceCounter)
 *   host_list(dir, pattern) -> { file names }   (the files - not directories - of dir matching pattern, e.g. "*.lua";
 *                                               lua_mock.lua's file.Find: the addon's feature files, G0)
 *   arg = { ... }                          the command line after the script
 * (sadc docs/research/gsa1_lsd_lag.md 6.5: the session log test; round 4c.)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include "gmod_paths.hpp"   // where Garry's Mod is (GARRYSMOD_DIR or Steam's library list)

typedef struct lua_State lua_State;
typedef int (*lua_CFunction)(lua_State *L);
static lua_State *(*p_luaL_newstate)(void);
static void (*p_luaL_openlibs)(lua_State *L);
static int (*p_luaL_loadbuffer)(lua_State *L, const char *b, size_t n, const char *name);
static int (*p_lua_pcall)(lua_State *L, int nargs, int nresults, int errfunc);
static const char *(*p_lua_tolstring)(lua_State *L, int idx, size_t *len);
static void (*p_lua_pushlstring)(lua_State *L, const char *s, size_t n);
static void (*p_lua_pushstring)(lua_State *L, const char *s);
static void (*p_lua_pushnil)(lua_State *L);
static void (*p_lua_pushnumber)(lua_State *L, double n);
static void (*p_lua_pushcclosure)(lua_State *L, lua_CFunction f, int n);
static void (*p_lua_setfield)(lua_State *L, int idx, const char *k);
static void (*p_lua_createtable)(lua_State *L, int a, int r);
static void (*p_lua_rawseti)(lua_State *L, int idx, int n);
static int (*p_lua_toboolean)(lua_State *L, int idx);
static void (*p_lua_close)(lua_State *L);
#define LUA_GLOBALSINDEX (-10002)

static char *slurp(const char *path, size_t *n)
{
    FILE *f = fopen(path, "rb");
    char *b;
    long len;
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    len = ftell(f);
    fseek(f, 0, SEEK_SET);
    b = (char *)malloc((size_t)len + 1);
    if (b && fread(b, 1, (size_t)len, f) != (size_t)len) {
        free(b);
        b = NULL;
    }
    fclose(f);
    if (b) {
        b[len] = 0;
        *n = (size_t)len;
    }
    return b;
}

/* host_load(src, name) -> function | nil, message */
static int host_load(lua_State *L)
{
    size_t n = 0;
    const char *src = p_lua_tolstring(L, 1, &n);
    const char *name = p_lua_tolstring(L, 2, NULL);
    if (!src) {
        p_lua_pushnil(L);
        return 1;
    }
    if (p_luaL_loadbuffer(L, src, n, name ? name : "chunk") != 0) {
        p_lua_pushnil(L);
        p_lua_pushstring(L, p_lua_tolstring(L, -2, NULL));
        return 2;
    }
    return 1;
}

static int host_write(lua_State *L)
{
    size_t n = 0;
    const char *s = p_lua_tolstring(L, 1, &n);
    if (s) fwrite(s, 1, n, stdout);
    fflush(stdout);
    return 0;
}

static int host_read(lua_State *L)
{
    size_t n = 0;
    const char *path = p_lua_tolstring(L, 1, NULL);
    char *b = path ? slurp(path, &n) : NULL;
    if (!b) {
        p_lua_pushnil(L);
        return 1;
    }
    p_lua_pushlstring(L, b, n);
    free(b);
    return 1;
}

/* host_list(dir, pattern) -> array of the names of the files in dir that match pattern (FindFirstFile), sorted */
static int cmp_names(const void *a, const void *b) { return strcmp(*(const char *const *)a, *(const char *const *)b); }
static int host_list(lua_State *L)
{
    const char *dir = p_lua_tolstring(L, 1, NULL);
    const char *pat = p_lua_tolstring(L, 2, NULL);
    char path[2048];
    char *names[512];
    int n = 0, i;
    WIN32_FIND_DATAA fd;
    HANDLE h;
    p_lua_createtable(L, 0, 0);
    if (!dir || !pat || strlen(dir) + strlen(pat) + 2 >= sizeof path) return 1;
    snprintf(path, sizeof path, "%s/%s", dir, pat);
    h = FindFirstFileA(path, &fd);
    if (h == INVALID_HANDLE_VALUE) return 1;
    do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && n < 512) names[n++] = _strdup(fd.cFileName);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    qsort(names, (size_t)n, sizeof names[0], cmp_names);
    for (i = 0; i < n; i++) {
        p_lua_pushstring(L, names[i]);
        p_lua_rawseti(L, -2, i + 1);
        free(names[i]);
    }
    return 1;
}

static int host_clock(lua_State *L)
{
    static LARGE_INTEGER freq;
    LARGE_INTEGER now;
    if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&now);
    p_lua_pushnumber(L, (double)now.QuadPart / (double)freq.QuadPart);
    return 1;
}

#define LOAD(name)                                                                                                     \
    do {                                                                                                               \
        *(FARPROC *)&p_##name = GetProcAddress(h, #name);                                                             \
        if (!p_##name) {                                                                                               \
            printf("lua_host: %s has no %s\n", dll, #name);                                                            \
            return 3;                                                                                                  \
        }                                                                                                              \
    } while (0)

int main(int argc, char **argv)
{
    const char *dll = getenv("GMOD_LUA_SHARED");
    HMODULE h;
    lua_State *L;
    char *src;
    size_t n;
    int i, ok;
    static char dllbuf[1100];
    /* GMOD_LUA_SHARED, else <GarrysMod>\bin\win64\lua_shared.dll of the install gmod_paths.hpp finds */
    if (!dll && gsa1_garrysmod_rel(dllbuf, sizeof dllbuf, 1, "bin\\win64\\lua_shared.dll")) dll = dllbuf;
    if (argc < 2) {
        printf("usage: lua_host script.lua [args]\n");
        return 2;
    }
    if (!dll) {
        printf("lua_host: Garry's Mod's lua_shared.dll not found: set GMOD_LUA_SHARED (the dll) or GARRYSMOD_DIR (the garrysmod folder)\n");
        return 2;
    }
    /* its own directory first for its dependencies (tier0.dll, ...); nothing is written there */
    h = LoadLibraryExA(dll, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!h) {
        printf("lua_host: cannot load %s (error %lu)\n", dll, GetLastError());
        return 3;
    }
    LOAD(luaL_newstate);
    LOAD(luaL_openlibs);
    LOAD(luaL_loadbuffer);
    LOAD(lua_pcall);
    LOAD(lua_tolstring);
    LOAD(lua_pushlstring);
    LOAD(lua_pushstring);
    LOAD(lua_pushnil);
    LOAD(lua_pushnumber);
    LOAD(lua_pushcclosure);
    LOAD(lua_setfield);
    LOAD(lua_createtable);
    LOAD(lua_rawseti);
    LOAD(lua_toboolean);
    LOAD(lua_close);
    L = p_luaL_newstate();
    p_luaL_openlibs(L);
    p_lua_pushcclosure(L, host_read, 0);
    p_lua_setfield(L, LUA_GLOBALSINDEX, "host_read");
    p_lua_pushcclosure(L, host_write, 0);
    p_lua_setfield(L, LUA_GLOBALSINDEX, "host_write");
    p_lua_pushcclosure(L, host_load, 0);
    p_lua_setfield(L, LUA_GLOBALSINDEX, "host_load");
    p_lua_pushcclosure(L, host_clock, 0);
    p_lua_setfield(L, LUA_GLOBALSINDEX, "host_clock");
    p_lua_pushcclosure(L, host_list, 0);
    p_lua_setfield(L, LUA_GLOBALSINDEX, "host_list");
    p_lua_createtable(L, argc, 0);
    for (i = 2; i < argc; i++) {
        p_lua_pushstring(L, argv[i]);
        p_lua_rawseti(L, -2, i - 1);
    }
    p_lua_setfield(L, LUA_GLOBALSINDEX, "arg");
    src = slurp(argv[1], &n);
    if (!src) {
        printf("lua_host: cannot read %s\n", argv[1]);
        return 3;
    }
    if (p_luaL_loadbuffer(L, src, n, argv[1]) != 0 || p_lua_pcall(L, 0, 1, 0) != 0) {
        printf("lua error: %s\n", p_lua_tolstring(L, -1, NULL));
        return 1;
    }
    ok = p_lua_toboolean(L, -1);
    p_lua_close(L);
    return ok ? 0 : 1;
}
