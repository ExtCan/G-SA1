// luajit_base.hpp - the module's REAL Lua functions inside Garry's Mod's own LuaJIT (1.0.0-beta1a, lane b1a-tex).
//
// Beta 1 passed every stand-in and drew Metal Sonic and Mecha Sonic pure white in the game: the Lua tests ran the addon against
// tests/lua_mock.lua's gsa1 (which takes any archive) and the binding tests drove the module through tests/mock_lua.hpp's value
// stack, and no test ever called the module's gsa1.Texture with the archive the skins' batches draw from (64 + the skin's slot).
// This header puts the module's functions into a real LuaJIT state: Garry's Mod's bin/win64/lua_shared.dll, loaded read-only
// the way tests/lua_host.c loads it (GMOD_LUA_SHARED, else the install tests/gmod_paths.hpp finds). LuajitBase is the
// ILuaBase the module's functions get: every call goes straight to the DLL's own C API (lua_gettop, lua_rawset, lua_tolstring,
// ...) on the state the call came from, so the values the module reads and writes are LuaJIT's own (numbers, strings, tables,
// nil / none), not a mock's.
//   * The module's C functions are pushed as C closures of one trampoline with the function as an upvalue: when Lua calls one,
//     the trampoline makes a gmod-module-base lua_State whose luabase is this LuajitBase (the module never touches the rest of
//     it) and calls the module's function with it; LuaJIT's own lua_State is never written. Calls nest (a module function that
//     PCalls Lua that calls the module again).
//   * Vectors and Angles are userdata {UserData header, Vector} with a metatable of their own (x / y / z and p / y / r read and
//     written through __index / __newindex), the shape gmod-module-base's PushUserType_Value makes; GetVector gives a reference
//     into the userdata, as Garry's Mod's does (the module's init_vectors writes through it). Globals Vector(x, y, z) and
//     Angle(p, y, r) make them in Lua.
//   * Not covered (the module does not use them): GetCFunction (nullptr), PushCClosure's upvalues (the trampoline's own
//     upvalue comes first), CreateMetaTable / PushMetaTable / PushUserType of other types.
// What this still does NOT show: Garry's Mod's own ILuaBase (CLuaInterface) is not this one, and nothing here draws (render
// targets, materials, mesh): only the game shows those.
#ifndef GSA1_TESTS_LUAJIT_BASE_HPP
#define GSA1_TESTS_LUAJIT_BASE_HPP

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <new>
#include <string>

#include "GarrysMod/Lua/Interface.h"

namespace luajit {

struct State;                       // LuaJIT's lua_State (opaque: gmod-module-base's lua_State is the module's own view)
typedef int (*CFn)(State *J);

const int kRegistry = -10000, kEnviron = -10001, kGlobals = -10002;
inline int upvalue(int i) { return kGlobals - i; }
const int kTNone = -1, kTUserdata = 7;

#define GSA1_LUAJIT_API(X)                                                                                                       \
    X(State *, luaL_newstate, (void))                                                                                           \
    X(void, luaL_openlibs, (State *))                                                                                           \
    X(int, luaL_loadbuffer, (State *, const char *, size_t, const char *))                                                      \
    X(void, lua_close, (State *))                                                                                               \
    X(int, lua_pcall, (State *, int, int, int))                                                                                 \
    X(void, lua_call, (State *, int, int))                                                                                      \
    X(int, lua_gettop, (State *))                                                                                               \
    X(void, lua_settop, (State *, int))                                                                                         \
    X(void, lua_pushvalue, (State *, int))                                                                                      \
    X(void, lua_remove, (State *, int))                                                                                         \
    X(void, lua_insert, (State *, int))                                                                                         \
    X(int, lua_type, (State *, int))                                                                                            \
    X(int, lua_equal, (State *, int, int))                                                                                      \
    X(int, lua_rawequal, (State *, int, int))                                                                                   \
    X(double, lua_tonumber, (State *, int))                                                                                     \
    X(int, lua_toboolean, (State *, int))                                                                                       \
    X(const char *, lua_tolstring, (State *, int, size_t *))                                                                    \
    X(size_t, lua_objlen, (State *, int))                                                                                       \
    X(void *, lua_touserdata, (State *, int))                                                                                   \
    X(void, lua_pushnil, (State *))                                                                                             \
    X(void, lua_pushnumber, (State *, double))                                                                                  \
    X(void, lua_pushlstring, (State *, const char *, size_t))                                                                   \
    X(void, lua_pushstring, (State *, const char *))                                                                            \
    X(void, lua_pushcclosure, (State *, CFn, int))                                                                              \
    X(void, lua_pushboolean, (State *, int))                                                                                    \
    X(void, lua_pushlightuserdata, (State *, void *))                                                                           \
    X(void, lua_gettable, (State *, int))                                                                                       \
    X(void, lua_getfield, (State *, int, const char *))                                                                         \
    X(void, lua_rawget, (State *, int))                                                                                         \
    X(void, lua_rawgeti, (State *, int, int))                                                                                   \
    X(void, lua_createtable, (State *, int, int))                                                                               \
    X(void *, lua_newuserdata, (State *, size_t))                                                                               \
    X(int, lua_getmetatable, (State *, int))                                                                                    \
    X(void, lua_settable, (State *, int))                                                                                       \
    X(void, lua_setfield, (State *, int, const char *))                                                                         \
    X(void, lua_rawset, (State *, int))                                                                                         \
    X(void, lua_rawseti, (State *, int, int))                                                                                   \
    X(int, lua_setmetatable, (State *, int))                                                                                    \
    X(int, lua_error, (State *))                                                                                                \
    X(int, lua_next, (State *, int))                                                                                            \
    X(int, luaL_ref, (State *, int))                                                                                            \
    X(void, luaL_unref, (State *, int, int))                                                                                    \
    X(int, luaL_newmetatable, (State *, const char *))                                                                          \
    X(double, luaL_checknumber, (State *, int))                                                                                 \
    X(const char *, luaL_checklstring, (State *, int, size_t *))                                                                \
    X(int, luaL_argerror, (State *, int, const char *))

struct Api {
#define GSA1_LUAJIT_FIELD(ret, name, args) ret(*name) args = nullptr;
    GSA1_LUAJIT_API(GSA1_LUAJIT_FIELD)
#undef GSA1_LUAJIT_FIELD
};

class LuajitBase : public GarrysMod::Lua::ILuaBase {
public:
    Api a;
    HMODULE dll = nullptr;
    State *main = nullptr;          // the state luaL_newstate made
    State *J = nullptr;             // the state of the call under way (the trampoline sets it)
    int vec_mt = -1, ang_mt = -1;   // registry references of the Vector / Angle metatables
    uint64_t calls = 0;             // module functions called through the trampoline

    static LuajitBase *&self()
    {
        static LuajitBase *s = nullptr;
        return s;
    }

    // loads lua_shared.dll (read-only, from its own folder for tier0.dll and the others) and every function above
    bool load(const std::string &path, std::string &err)
    {
        dll = LoadLibraryExA(path.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
        if (!dll) {
            err = "cannot load " + path + " (error " + std::to_string((unsigned long)GetLastError()) + ")";
            return false;
        }
#define GSA1_LUAJIT_LOAD(ret, name, args)                                                                                        \
    *(FARPROC *)&a.name = GetProcAddress(dll, #name);                                                                           \
    if (!a.name) {                                                                                                              \
        err = path + " has no " #name;                                                                                          \
        return false;                                                                                                           \
    }
        GSA1_LUAJIT_API(GSA1_LUAJIT_LOAD)
#undef GSA1_LUAJIT_LOAD
        return true;
    }

    // a new state with LuaJIT's libraries, the Vector / Angle metatables and their constructors
    bool open()
    {
        main = J = a.luaL_newstate();
        if (!J) {
            return false;
        }
        self() = this;
        a.luaL_openlibs(J);
        vec_mt = make_mt("gsa1_test_Vector", vec_index, vec_newindex);
        ang_mt = make_mt("gsa1_test_Angle", ang_index, ang_newindex);
        a.lua_pushcclosure(J, new_vector, 0);
        a.lua_setfield(J, kGlobals, "Vector");
        a.lua_pushcclosure(J, new_angle, 0);
        a.lua_setfield(J, kGlobals, "Angle");
        return true;
    }

    void close()
    {
        if (main) {
            a.lua_close(main);
        }
        main = J = nullptr;
    }

    // a raw C function of the test (not the module's) as a global
    void global_fn(const char *name, CFn f)
    {
        a.lua_pushcclosure(J, f, 0);
        a.lua_setfield(J, kGlobals, name);
    }

    // gmod13_open / gmod13_close with this ILuaBase on the main state
    int call_module(int (*fn)(lua_State *))
    {
        lua_State g;
        std::memset(&g, 0, sizeof g);
        g.luabase = this;
        State *saved = J;
        J = main;
        int r = fn(&g);
        J = saved;
        return r;
    }

    // ---- ILuaBase ------------------------------------------------------------------------------------------------------------
    int Top(void) override { return a.lua_gettop(J); }
    void Push(int i) override { a.lua_pushvalue(J, i); }
    void Pop(int n) override { a.lua_settop(J, -n - 1); }
    void GetTable(int i) override { a.lua_gettable(J, i); }
    void GetField(int i, const char *k) override { a.lua_getfield(J, i, k); }
    void SetField(int i, const char *k) override { a.lua_setfield(J, i, k); }
    void CreateTable() override { a.lua_createtable(J, 0, 0); }
    void SetTable(int i) override { a.lua_settable(J, i); }
    void SetMetaTable(int i) override { a.lua_setmetatable(J, i); }
    bool GetMetaTable(int i) override { return a.lua_getmetatable(J, i) != 0; }
    void Call(int n, int r) override { a.lua_call(J, n, r); }
    int PCall(int n, int r, int e) override { return a.lua_pcall(J, n, r, e); }
    int Equal(int x, int y) override { return a.lua_equal(J, x, y); }
    int RawEqual(int x, int y) override { return a.lua_rawequal(J, x, y); }
    void Insert(int i) override { a.lua_insert(J, i); }
    void Remove(int i) override { a.lua_remove(J, i); }
    int Next(int i) override { return a.lua_next(J, i); }
    void *NewUserdata(unsigned int n) override { return a.lua_newuserdata(J, n); }
    void ThrowError(const char *s) override
    {
        a.lua_pushstring(J, s);
        a.lua_error(J);
    }
    void CheckType(int i, int t) override
    {
        if (GetType(i) != t) {
            a.luaL_argerror(J, i, "wrong type");
        }
    }
    void ArgError(int i, const char *m) override { a.luaL_argerror(J, i, m); }
    void RawGet(int i) override { a.lua_rawget(J, i); }
    void RawSet(int i) override { a.lua_rawset(J, i); }
    const char *GetString(int i, unsigned int *len) override
    {
        size_t n = 0;
        const char *s = a.lua_tolstring(J, i, &n);
        if (len) {
            *len = (unsigned int)n;
        }
        return s;
    }
    double GetNumber(int i) override { return a.lua_tonumber(J, i); }
    bool GetBool(int i) override { return a.lua_toboolean(J, i) != 0; }
    GarrysMod::Lua::CFunc GetCFunction(int) override { return nullptr; }
    void *GetUserdata(int i) override { return a.lua_touserdata(J, i); }
    void PushNil() override { a.lua_pushnil(J); }
    void PushString(const char *s, unsigned int n) override
    {
        if (n) {
            a.lua_pushlstring(J, s, n);
        } else {
            a.lua_pushstring(J, s ? s : "");
        }
    }
    void PushNumber(double v) override { a.lua_pushnumber(J, v); }
    void PushBool(bool v) override { a.lua_pushboolean(J, v ? 1 : 0); }
    void PushCFunction(GarrysMod::Lua::CFunc f) override
    {
        a.lua_pushlightuserdata(J, (void *)f);
        a.lua_pushcclosure(J, tramp, 1);
    }
    void PushCClosure(GarrysMod::Lua::CFunc f, int n) override
    {
        a.lua_pushlightuserdata(J, (void *)f);
        a.lua_insert(J, -n - 1);
        a.lua_pushcclosure(J, tramp, n + 1);
    }
    void PushUserdata(void *p) override { a.lua_pushlightuserdata(J, p); }
    int ReferenceCreate() override { return a.luaL_ref(J, kRegistry); }
    void ReferenceFree(int r) override { a.luaL_unref(J, kRegistry, r); }
    void ReferencePush(int r) override { a.lua_rawgeti(J, kRegistry, r); }
    void PushSpecial(int t) override
    {
        a.lua_pushvalue(J, t == GarrysMod::Lua::SPECIAL_GLOB ? kGlobals : t == GarrysMod::Lua::SPECIAL_ENV ? kEnviron : kRegistry);
    }
    bool IsType(int i, int t) override { return GetType(i) == t; }
    int GetType(int i) override
    {
        int t = a.lua_type(J, i);
        if (t != kTUserdata) {
            return t;                               // LuaJIT's LUA_T* are Garry's Mod's Type 0 .. 8 (and LUA_TNONE -1: Type::None)
        }
        if (i < 0 && i > kRegistry) {
            i = a.lua_gettop(J) + i + 1;
        }
        int out = GarrysMod::Lua::Type::UserData;
        if (a.lua_getmetatable(J, i)) {
            a.lua_rawgeti(J, kRegistry, vec_mt);
            if (a.lua_rawequal(J, -1, -2)) {
                out = GarrysMod::Lua::Type::Vector;
            }
            a.lua_settop(J, -2);
            a.lua_rawgeti(J, kRegistry, ang_mt);
            if (a.lua_rawequal(J, -1, -2)) {
                out = GarrysMod::Lua::Type::Angle;
            }
            a.lua_settop(J, -3);
        }
        return out;
    }
    const char *GetTypeName(int t) override
    {
        static const char *const names[] = {"nil", "bool", "lightuserdata", "number", "string", "table", "function", "userdata", "thread", "entity", "vector", "angle"};
        return t >= 0 && t < (int)(sizeof names / sizeof names[0]) ? names[t] : "?";
    }
    void CreateMetaTableType(const char *name, int) override { a.luaL_newmetatable(J, name); }
    const char *CheckString(int i) override { return a.luaL_checklstring(J, i, nullptr); }
    double CheckNumber(int i) override { return a.luaL_checknumber(J, i); }
    int ObjLen(int i) override { return (int)a.lua_objlen(J, i); }
    const QAngle &GetAngle(int i) override { return *vec_at(i, GarrysMod::Lua::Type::Angle); }
    const Vector &GetVector(int i) override { return *vec_at(i, GarrysMod::Lua::Type::Vector); }
    void PushAngle(const QAngle &v) override { push_vec(v, ang_mt, GarrysMod::Lua::Type::Angle); }
    void PushVector(const Vector &v) override { push_vec(v, vec_mt, GarrysMod::Lua::Type::Vector); }
    void SetState(lua_State *) override {}   // (the trampoline's gmod lua_State: J stays LuaJIT's own)
    int CreateMetaTable(const char *name) override
    {
        a.luaL_newmetatable(J, name);
        return GarrysMod::Lua::Type::Type_Count;
    }
    bool PushMetaTable(int t) override
    {
        if (t == GarrysMod::Lua::Type::Vector || t == GarrysMod::Lua::Type::Angle) {
            a.lua_rawgeti(J, kRegistry, t == GarrysMod::Lua::Type::Vector ? vec_mt : ang_mt);
            return true;
        }
        return false;
    }
    void PushUserType(void *data, int t) override
    {
        UserData *ud = (UserData *)a.lua_newuserdata(J, sizeof(UserData));
        ud->data = data;
        ud->type = (unsigned char)t;
        if (PushMetaTable(t)) {
            a.lua_setmetatable(J, -2);
        }
    }
    void SetUserType(int i, void *data) override
    {
        UserData *ud = (UserData *)a.lua_touserdata(J, i);
        if (ud) {
            ud->data = data;
        }
    }

private:
    struct VecUD : UserData {
        Vector value;
    };

    // the Vector (Angle) at index i, or a zero one
    Vector *vec_at(int i, int t)
    {
        static Vector zero;
        if (GetType(i) != t) {
            zero = Vector();
            return &zero;
        }
        VecUD *ud = (VecUD *)a.lua_touserdata(J, i);
        return ud && ud->data ? (Vector *)ud->data : &zero;
    }

    void push_vec(const Vector &v, int mt, int t)
    {
        VecUD *ud = (VecUD *)a.lua_newuserdata(J, sizeof(VecUD));
        new (&ud->value) Vector(v);
        ud->data = &ud->value;
        ud->type = (unsigned char)t;
        a.lua_rawgeti(J, kRegistry, mt);
        a.lua_setmetatable(J, -2);
    }

    int make_mt(const char *name, CFn index, CFn newindex)
    {
        a.luaL_newmetatable(J, name);
        a.lua_pushcclosure(J, index, 0);
        a.lua_setfield(J, -2, "__index");
        a.lua_pushcclosure(J, newindex, 0);
        a.lua_setfield(J, -2, "__newindex");
        return a.luaL_ref(J, kRegistry);
    }

    // the field of a Vector (x, y, z) / an Angle (p, y, r; pitch, yaw, roll); -1: none
    static int field_of(const char *k, bool angle)
    {
        if (!k) {
            return -1;
        }
        if (!angle) {
            return std::strcmp(k, "x") == 0 ? 0 : std::strcmp(k, "y") == 0 ? 1 : std::strcmp(k, "z") == 0 ? 2 : -1;
        }
        return (std::strcmp(k, "p") == 0 || std::strcmp(k, "pitch") == 0) ? 0
               : (std::strcmp(k, "y") == 0 || std::strcmp(k, "yaw") == 0) ? 1
               : (std::strcmp(k, "r") == 0 || std::strcmp(k, "roll") == 0) ? 2
                                                                          : -1;
    }
    static float *comp(LuajitBase *s, State *J, bool angle)
    {
        VecUD *ud = (VecUD *)s->a.lua_touserdata(J, 1);
        size_t n = 0;
        int f = field_of(s->a.lua_type(J, 2) == 4 ? s->a.lua_tolstring(J, 2, &n) : nullptr, angle);
        if (!ud || !ud->data || f < 0) {
            return nullptr;
        }
        Vector *v = (Vector *)ud->data;
        return f == 0 ? &v->x : f == 1 ? &v->y : &v->z;
    }
    static int get(State *J, bool angle)
    {
        LuajitBase *s = self();
        float *c = comp(s, J, angle);
        if (c) {
            s->a.lua_pushnumber(J, *c);
        } else {
            s->a.lua_pushnil(J);
        }
        return 1;
    }
    static int set(State *J, bool angle)
    {
        LuajitBase *s = self();
        float *c = comp(s, J, angle);
        if (c) {
            *c = (float)s->a.lua_tonumber(J, 3);
        }
        return 0;
    }
    static int vec_index(State *J) { return get(J, false); }
    static int ang_index(State *J) { return get(J, true); }
    static int vec_newindex(State *J) { return set(J, false); }
    static int ang_newindex(State *J) { return set(J, true); }
    static int make(State *J, bool angle)
    {
        LuajitBase *s = self();
        Vector v;
        v.x = (float)s->a.lua_tonumber(J, 1);
        v.y = (float)s->a.lua_tonumber(J, 2);
        v.z = (float)s->a.lua_tonumber(J, 3);
        State *saved = s->J;
        s->J = J;
        s->push_vec(v, angle ? s->ang_mt : s->vec_mt, angle ? GarrysMod::Lua::Type::Angle : GarrysMod::Lua::Type::Vector);
        s->J = saved;
        return 1;
    }
    static int new_vector(State *J) { return make(J, false); }
    static int new_angle(State *J) { return make(J, true); }

    // every module function: its own pointer is upvalue 1
    static int tramp(State *J)
    {
        LuajitBase *s = self();
        GarrysMod::Lua::CFunc f = (GarrysMod::Lua::CFunc)s->a.lua_touserdata(J, upvalue(1));
        lua_State g;
        std::memset(&g, 0, sizeof g);
        g.luabase = s;
        State *saved = s->J;
        s->J = J;
        s->calls++;
        int r = f ? f(&g) : 0;
        s->J = saved;
        return r;
    }
};

}  // namespace luajit

#endif  // _WIN32
#endif
