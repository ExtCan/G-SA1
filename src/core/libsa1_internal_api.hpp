// G-SA1 core: the libsa1 header (static linkage) plus the internal libsa1 functions G-SA1 uses.
//
// sa1_path_check_host / sa1_path_check_bare are libsa1's own path rules (LIB/src/sa1_disc.c, declared in
// LIB/src/sa1_internal.h, not in the public header). G-SA1 links libsa1 statically, so they are reachable;
// a public `sa1_path_check` is requested in g-sa1/README.md ("libsa1 API requests").
//
// sa1_character_world / sa1g_world_rd32 / sa1g_world_wr32 (LIB/src/sa1_api_world.h, LIB/src/world/sa1_world.h):
// the character's world and bounded word access to its arena. Used for one thing only: the upgrade event flags
// above 127 (sa1_character_desc.upgrades covers flags 0..127, every upgrade flag PInitialize reads is 141..481),
// written after sa1_character_create_ex(SA1_CREATE_WORLD) and before the first tick (session.cpp
// set_event_flags). Requested as a public API in README.md ("libsa1 API requests").
#pragma once

#ifndef SA1_STATIC
#define SA1_STATIC
#endif
#include "libsa1.h"

extern "C" {
sa1_status sa1_path_check_host(const char *path);   // the .gdi path rules (UNC, device, NT object, ADS)
sa1_status sa1_path_check_bare(const char *name);   // a bare file name (no separators, no device names)
struct sa1g_world;
struct sa1g_world *sa1_character_world(const sa1_context *ctx, sa1_character_id id);   // NULL: no world (yet)
int sa1g_world_rd32(const struct sa1g_world *w, uint32_t guest, uint32_t *v);           // 0 ok, -1 outside the arena
int sa1g_world_wr32(struct sa1g_world *w, uint32_t guest, uint32_t v);
}
