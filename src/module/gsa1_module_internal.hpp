// G-SA1 module internals shared with the feature bindings (src/module/bind_<feature>.cpp; gsa1_feature.hpp).
//
// The binding rules of gsa1_module.cpp hold for every feature function too: it runs on the Lua main thread, never
// raises a Lua error (no ThrowError / ArgError / Check*: write it with GSA1_FN, which also turns a C++ exception into
// `nil, message`), validates every argument (the arg_* helpers: finite numbers, bounded strings), reports failures as
// `nil, message[, code]` or `false, message[, code]`, writes caller tables with raw sets only, takes no filesystem path
// from Lua and hands no directory to Lua (scrubbed() replaces the disc's and the config's directories).
// Units: Hammer units and degrees in Lua.
#ifndef GSA1_MODULE_INTERNAL_HPP
#define GSA1_MODULE_INTERNAL_HPP

#include <cstdint>
#include <exception>
#include <string>

#include "GarrysMod/Lua/Interface.h"

#include "../core/audio.hpp"
#include "../core/session.hpp"

namespace gsa1 {
namespace mod {

using GarrysMod::Lua::ILuaBase;

// the module's state (nullptr before gmod13_open and after gmod13_close; the session is also nullptr when it failed
// to start). Feature close hooks run while all of these still exist.
gsa1::Session *session();
gsa1::AudioOut *audio_out();          // the BASS push stream of the game's sound (nullptr until the banks open)
const std::string &gmod_dir();        // the garrysmod directory the module was loaded from ("" outside lua/bin)

// a message for Lua with the disc's and the config's directories replaced (Session::scrub)
std::string scrubbed(const std::string &m);

// units
float deg2rad(double d);
double rad2deg(double r);
double now_s();                       // the module's monotonic clock, seconds

// stack index helpers
int absidx(ILuaBase *L, int i);

// arguments (false when the argument is missing, of another type, out of range or not finite)
bool arg_number(ILuaBase *L, int i, double &out);
bool arg_int(ILuaBase *L, int i, int32_t &out, double lo, double hi);        // a whole number in [lo, hi]
bool arg_string(ILuaBase *L, int i, std::string &out, size_t max);          // at most max bytes
bool arg_vector(ILuaBase *L, int i, float out[3]);
bool arg_angle(ILuaBase *L, int i, float out[3]);                           // pitch, yaw, roll (degrees)

// results: nil / false, message[, code]; returns the number of values pushed
int push_nil_msg(ILuaBase *L, const std::string &msg, const char *code = nullptr);
int push_false_msg(ILuaBase *L, const std::string &msg, const char *code = nullptr);

// raw table writes (t: the absolute index of a table)
void raw_num(ILuaBase *L, int t, const char *k, double v);
void raw_bool(ILuaBase *L, int t, const char *k, bool v);
void raw_str(ILuaBase *L, int t, const char *k, const std::string &v);
// t[k] (rawget) when it is a finite number / a boolean
bool raw_get_number(ILuaBase *L, int t, const char *k, double &out);
bool raw_get_bool(ILuaBase *L, int t, const char *k, bool &out);
// pushes t[i] if it is a table, else a new table stored at t[i]; returns its absolute index
int raw_subtable_i(ILuaBase *L, int t, int i);
// the caller's table at index i (or a new one), left on the top of the stack; returns its absolute index
int out_table(ILuaBase *L, int i);

// true when the disc is loaded; otherwise pushes `nil, "G-SA1 is not initialised ...", "not_ready"` and sets ret
bool ready_or(ILuaBase *L, int &ret);

// 0.9.4b: gsa1.EmitBatch's loop (call between mesh.Begin and mesh.End): streams batch b (1-based) of c's prepared view
// (Session::prepare_view; prepared again from c's last view when it is not) into GMod's mesh builder; pushes the vertices
// written | nil, message. c: a character's render or a preview copy's holder (bind_preview.cpp)
int emit_batch(ILuaBase *L, gsa1::Character &c, int32_t b);

}  // namespace mod
}  // namespace gsa1

// GSA1_FN(name) { body with LUA }: a Lua function of the module (LUA_FUNCTION, external linkage: name it
// gsa1_<feature>_<Function>). No C++ exception reaches Lua: it becomes `nil, "G-SA1 internal error: ..."`.
#define GSA1_FN(name)                                                                                             \
    static int name##_body(::GarrysMod::Lua::ILuaBase *LUA);                                                      \
    LUA_FUNCTION(name)                                                                                            \
    {                                                                                                             \
        try {                                                                                                     \
            return name##_body(LUA);                                                                              \
        } catch (const std::exception &e) {                                                                       \
            return ::gsa1::mod::push_nil_msg(LUA, std::string("G-SA1 internal error: ") + e.what());              \
        } catch (...) {                                                                                           \
            return ::gsa1::mod::push_nil_msg(LUA, "G-SA1 internal error");                                        \
        }                                                                                                         \
    }                                                                                                             \
    static int name##_body(::GarrysMod::Lua::ILuaBase *LUA)

#endif
