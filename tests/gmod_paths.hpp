/*
 * gmod_paths.hpp - where Garry's Mod is installed, for the offline tests that read its files (maps/gm_construct.bsp,
 * the VPKs, scripts/surfaceproperties.txt, bin/win64/lua_shared.dll). The tests only ever open them read-only.
 *
 * gsa1_garrysmod_dir() returns the game's "garrysmod" folder (<Steam library>/steamapps/common/GarrysMod/garrysmod):
 *   1. GARRYSMOD_DIR when it is set (build.py sets it for every test it runs: its --gmod argument or the same search);
 *   2. otherwise the first Steam library that has GarrysMod/garrysmod: STEAM_DIR when it is set, then Steam's default
 *      install places (Windows: C:\Program Files (x86)\Steam, C:\Program Files\Steam; Linux: ~/.steam/steam,
 *      ~/.local/share/Steam), each with every library listed in its steamapps/libraryfolders.vdf;
 *   3. otherwise "" (a test then reports the missing file as before, or skips what needs it).
 * Each test's own option (--gm, --bsp) still overrides it. C and C++ (lua_host.c includes it too).
 */
#ifndef GSA1_GMOD_PATHS_HPP
#define GSA1_GMOD_PATHS_HPP

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#define GSA1_PATH_SEP "\\"
#else
#define GSA1_PATH_SEP "/"
#endif

static inline int gsa1_is_dir(const char *p)
{
    struct stat st;
    return p && *p && stat(p, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR;
}

/* <lib>/steamapps/common/GarrysMod/garrysmod into out when it exists */
static inline int gsa1_try_library(const char *lib, char *out, size_t n)
{
    snprintf(out, n, "%s" GSA1_PATH_SEP "steamapps" GSA1_PATH_SEP "common" GSA1_PATH_SEP "GarrysMod" GSA1_PATH_SEP
             "garrysmod", lib);
    return gsa1_is_dir(out);
}

/* a Steam install: its own library, then every "path" of steamapps/libraryfolders.vdf (VDF doubles backslashes) */
static inline int gsa1_try_steam(const char *steam, char *out, size_t n)
{
    char vdf[1024], line[2048], lib[1024];
    FILE *f;
    if (!steam || !*steam) return 0;
    if (gsa1_try_library(steam, out, n)) return 1;
    snprintf(vdf, sizeof vdf, "%s" GSA1_PATH_SEP "steamapps" GSA1_PATH_SEP "libraryfolders.vdf", steam);
    f = fopen(vdf, "r");
    if (!f) return 0;
    while (fgets(line, sizeof line, f)) {
        const char *k = strstr(line, "\"path\""), *a, *b;
        size_t j = 0;
        if (!k) continue;
        a = strchr(k + 6, '"');
        if (!a) continue;
        for (b = a + 1; *b && *b != '"' && j + 1 < sizeof lib; b++) {
            if (*b == '\\' && b[1] == '\\') b++;
            lib[j++] = *b;
        }
        lib[j] = 0;
        if (j && gsa1_try_library(lib, out, n)) {
            fclose(f);
            return 1;
        }
    }
    fclose(f);
    return 0;
}

static inline const char *gsa1_garrysmod_dir(void)
{
    static char dir[1024];
    static int done = 0;
    const char *e, *cand[4];
    int i, nc = 0;
#ifndef _WIN32
    static char home1[1024], home2[1024];
#endif
    if (done) return dir;
    done = 1;
    dir[0] = 0;
    e = getenv("GARRYSMOD_DIR");
    if (e && *e) {
        snprintf(dir, sizeof dir, "%s", e);
        return dir;
    }
    cand[nc++] = getenv("STEAM_DIR");
#ifdef _WIN32
    cand[nc++] = "C:\\Program Files (x86)\\Steam";
    cand[nc++] = "C:\\Program Files\\Steam";
#else
    e = getenv("HOME");
    if (e && *e) {
        snprintf(home1, sizeof home1, "%s/.steam/steam", e);
        snprintf(home2, sizeof home2, "%s/.local/share/Steam", e);
        cand[nc++] = home1;
        cand[nc++] = home2;
    }
#endif
    for (i = 0; i < nc; i++) {
        if (gsa1_try_steam(cand[i], dir, sizeof dir)) return dir;
    }
    dir[0] = 0;
    return dir;
}

/* out = the folder `up` levels above the garrysmod folder, then rel; 0 (out "") when Garry's Mod was not found.
 * up 1: <GarrysMod> (bin/win64/lua_shared.dll); up 3: <Steam library>/steamapps (workshop/content/4000). */
static inline int gsa1_garrysmod_rel(char *out, size_t n, int up, const char *rel)
{
    const char *gm = gsa1_garrysmod_dir();
    size_t len = strlen(gm);
    out[0] = 0;
    if (!len) return 0;
    while (len > 1 && (gm[len - 1] == '\\' || gm[len - 1] == '/')) len--;
    while (up-- > 0) {
        while (len && gm[len - 1] != '\\' && gm[len - 1] != '/') len--;
        if (len) len--;
        if (!len) return 0;
    }
    snprintf(out, n, "%.*s" GSA1_PATH_SEP "%s", (int)len, gm, rel);
    return 1;
}

#endif
