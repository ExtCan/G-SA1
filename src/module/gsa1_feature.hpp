// G-SA1 module features: the seam that lets a later feature (interaction, Super Sonic, followers, jukebox) add Lua
// functions to the module without editing gsa1_module.cpp (sadc docs/research/gsa1_rounds_plan.md section 5, G0).
//
// A feature lives in its own files - src/module/bind_<feature>.cpp (its Lua functions), src/core/<feature>.{hpp,cpp},
// addon/lua/gsa1/feat/{sh,cl,sv}_<feature>.lua, tests/feat_<feature>_test.cpp and tests/feat_<feature>_binding_test.cpp
// - and registers itself here, at static-initialisation time, with one line:
//
//     #include "gsa1_feature.hpp"
//     #include "gsa1_module_internal.hpp"
//     GSA1_FN(gsa1_jukebox_Play) { ... }                      // Lua functions: the same rules as gsa1_module.cpp's
//     static const gsa1::FeatureFn k_jukebox_fns[] = {
//         {"JukeboxPlay", gsa1_jukebox_Play},
//         ...
//     };
//     static void jukebox_close(GarrysMod::Lua::ILuaBase *L) { ... }   // stop the worker, free BASS handles
//     GSA1_FEATURE(jukebox, 1, k_jukebox_fns, nullptr, jukebox_close, gsa1::kCloseFirst);
//
// build.py compiles every src/module/*.cpp into the module (and into the binding tests), so nothing else has to know.
// What the module does with the registered features (gsa1_module.cpp):
//   * GMOD_MODULE_OPEN, after the built-in functions and constants: every feature's functions go into the gsa1 table
//     (features by name, functions in their array's order), gsa1.FEATURES = {name = version, ...}, then every feature's
//     open hook runs (by name) with the gsa1 table's stack index (for constants: raw sets only). A function whose name
//     is taken already (a built-in or another feature's) is NOT replaced; the clash is listed in gsa1.FEATURE_ERRORS (an
//     array of strings, empty when all is well), as is a feature with a bad name or version (then nothing of it is
//     registered).
//   * gsa1.Shutdown(): every feature's shutdown hook (close order, below) before the session's characters go.
//   * GMOD_MODULE_CLOSE: every feature's close hook, lowest close_priority first (ties by name), BEFORE the session,
//     the sound output, the controller and the map workers are destroyed (gsa1::mod::session() is still valid there);
//     the jukebox closes first (kCloseFirst).
// The Lua side checks a feature with GSA1.HasFeature(name, min_version) (cl_module.lua); the base gsa1.API_VERSION /
// GSA1.REQUIRED_API change only for a breaking change of the built-in functions (README "Versioning").
#ifndef GSA1_FEATURE_HPP
#define GSA1_FEATURE_HPP

#include <cstddef>

#include "GarrysMod/Lua/Interface.h"

namespace gsa1 {

struct FeatureFn {
    const char *name;                // the gsa1.<name> key; nullptr ends the array early (optional)
    GarrysMod::Lua::CFunc fn;
};

enum : int {
    kCloseFirst = 0,                 // the jukebox (its worker owns BASS handles that must go before the sound output)
    kCloseDefault = 100,
    kCloseLast = 1000,
};

struct Feature {
    const char *name;                // gsa1.FEATURES key: [a-z][a-z0-9_]*, at most 32 characters
    int version;                     // >= 1; raised when the feature's Lua functions grow (GSA1.HasFeature(name, v))
    const FeatureFn *fns;            // its Lua functions
    size_t nfns;                     // entries in fns (a {nullptr, nullptr} entry ends it earlier)
    void (*open)(GarrysMod::Lua::ILuaBase *L, int gsa1_table);   // may be null; gsa1_table: an absolute stack index
    void (*close)(GarrysMod::Lua::ILuaBase *L);                  // may be null
    int close_priority;              // lower closes first
    void (*shutdown)();              // gsa1.Shutdown(); may be null (GSA1_FEATURE_ON_SHUTDOWN)
    Feature *next;                   // the registry's list (set by FeatureRegistrar)
};

// adds f to the registry (static-initialisation time; a feature registered twice is ignored)
class FeatureRegistrar {
public:
    explicit FeatureRegistrar(Feature &f);
};

// the registered features in registration order (a linked list through Feature::next; nullptr when there is none)
Feature *feature_list();
size_t feature_count();

// ---- the module's side (gsa1_module.cpp) ----
// GMOD_MODULE_OPEN: registers the features' functions into the gsa1 table at absolute stack index t, sets
// t.FEATURES and t.FEATURE_ERRORS, runs the open hooks; returns the number of features registered
int open_features(GarrysMod::Lua::ILuaBase *L, int t);
// gsa1.Shutdown(): the shutdown hooks, in close order
void shutdown_features();
// GMOD_MODULE_CLOSE (before anything of the module is destroyed): the close hooks, lowest close_priority first
void close_features(GarrysMod::Lua::ILuaBase *L);

}  // namespace gsa1

// GSA1_FEATURE(name, version, fns, open_fn, close_fn, close_priority): registers feature `name` (an identifier: it is
// also the gsa1.FEATURES key) with the Lua functions of the array `fns` (an array, not a pointer: its size is taken).
#define GSA1_FEATURE(name, version, fns, open_fn, close_fn, close_priority)                                      \
    static ::gsa1::Feature gsa1_feature_##name = {#name, (version), (fns), sizeof(fns) / sizeof((fns)[0]),     \
                                                  (open_fn), (close_fn), (close_priority), nullptr, nullptr};   \
    static ::gsa1::FeatureRegistrar gsa1_feature_registrar_##name(gsa1_feature_##name)

// GSA1_FEATURE_ON_SHUTDOWN(name, fn): fn() runs at gsa1.Shutdown() (after GSA1_FEATURE(name, ...) in the same file)
#define GSA1_FEATURE_ON_SHUTDOWN(name, fn) \
    [[maybe_unused]] static const bool gsa1_feature_shutdown_##name = (gsa1_feature_##name.shutdown = (fn), true)

#endif
