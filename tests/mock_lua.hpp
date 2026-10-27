// mock_lua.hpp - a mock of Garry's Mod's Lua for the module's binding tests (tests/binding_test.cpp and every feature's
// tests/feat_<feature>_binding_test.cpp; build.py links them with the module's objects): an ILuaBase with a small
// Lua-like value stack (nil, booleans, numbers, strings, tables, Vectors, Angles, C functions, references), a mock of
// GMod's mesh library (what gsa1.EmitBatch calls) and CHECK counters. A Lua error raised by the module (ThrowError,
// ArgError, Check*) ends the test: the module must report failures as return values.
//
//   MockLua L; lua_State state; std::memset(&state, 0, sizeof state); state.luabase = &L; L.state = &state;
//   gmod13_open(&state);
//   auto r = L.call("Status", {});                 // gsa1.Status() with a fresh frame; r: its results
//   CHECK(r.size() == 1 && r[0].type == Type::Table, "Status() -> a table");
//   ... gmod13_close(&state); return g_fail ? 1 : 0;
#ifndef GSA1_TESTS_MOCK_LUA_HPP
#define GSA1_TESTS_MOCK_LUA_HPP

#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

using namespace GarrysMod::Lua;

extern "C" int gmod13_open(lua_State *L);
extern "C" int gmod13_close(lua_State *L);

static int g_fail = 0, g_checks = 0;
#define CHECK(cond, ...)                                     \
    do {                                                     \
        g_checks++;                                          \
        if (cond) {                                          \
            std::printf("  ok    ");                         \
        } else {                                             \
            std::printf("  FAIL  ");                         \
            g_fail++;                                        \
        }                                                    \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

// ---- the mock ----------------------------------------------------------------------------------------------------
struct Table;
struct Val {
    int type = Type::Nil;
    double num = 0;
    bool b = false;
    std::string str;
    std::shared_ptr<Table> tab;
    Vector vec;                          // Angle values
    std::shared_ptr<Vector> vp;          // Vector values: shared like a Lua userdata (identity survives copies)
    CFunc fn = nullptr;
    static Val number(double d) { Val v; v.type = Type::Number; v.num = d; return v; }
    static Val string(const std::string &s) { Val v; v.type = Type::String; v.str = s; return v; }
    static Val boolean(bool x) { Val v; v.type = Type::Bool; v.b = x; return v; }
    static Val vector(float x, float y, float z)
    {
        Val v;
        v.type = Type::Vector;
        v.vp = std::make_shared<Vector>();
        v.vp->x = x;
        v.vp->y = y;
        v.vp->z = z;
        return v;
    }
    static Val table();
    static Val angle(float p, float y, float r)
    {
        Val v;
        v.type = Type::Angle;
        v.vec.x = p;
        v.vec.y = y;
        v.vec.z = r;
        return v;
    }
};
struct Table {
    std::map<std::string, Val> s;
    std::map<double, Val> n;
    Val get(const Val &k) const
    {
        if (k.type == Type::String) { auto it = s.find(k.str); return it == s.end() ? Val() : it->second; }
        if (k.type == Type::Number) { auto it = n.find(k.num); return it == n.end() ? Val() : it->second; }
        return Val();
    }
    void set(const Val &k, const Val &v)
    {
        if (k.type == Type::String) {
            if (v.type == Type::Nil) s.erase(k.str); else s[k.str] = v;
        } else if (k.type == Type::Number) {
            if (v.type == Type::Nil) n.erase(k.num); else n[k.num] = v;
        } else {
            std::printf("  FAIL  table key of type %d\n", k.type);
            g_fail++;
        }
    }
    Val field(const char *k) const { return get(Val::string(k)); }
    Val at(double i) const { return get(Val::number(i)); }
};
inline Val Val::table() { Val v; v.type = Type::Table; v.tab = std::make_shared<Table>(); return v; }

inline void lua_error_called(const char *what, const char *msg)
{
    std::printf("  FAIL  the module called %s(%s): Lua errors must never be raised\n", what, msg ? msg : "");
    std::exit(3);
}

class MockLua : public ILuaBase {
public:
    std::vector<Val> st;
    Val globals = Val::table(), registry = Val::table();
    lua_State *state = nullptr;

    int abs(int i) const { return i < 0 ? (int)st.size() + i + 1 : i; }
    Val &at(int i)
    {
        static Val none;
        int a = abs(i);
        if (a < 1 || a > (int)st.size()) { none = Val(); none.type = Type::None; return none; }
        return st[(size_t)a - 1];
    }
    Val pop() { Val v = st.back(); st.pop_back(); return v; }
    Table *tab(int i)
    {
        Val &v = at(i);
        if (v.type != Type::Table) {
            std::printf("  FAIL  table expected at stack index %d (type %d)\n", i, v.type);
            g_fail++;
            static Table dummy;
            return &dummy;
        }
        return v.tab.get();
    }

    int Top() override { return (int)st.size(); }
    void Push(int i) override { st.push_back(at(i)); }
    void Pop(int n) override { while (n-- > 0 && !st.empty()) st.pop_back(); }
    void GetTable(int i) override { Table *t = tab(i); Val k = pop(); st.push_back(t->get(k)); }
    void GetField(int i, const char *name) override
    {
        Val &v = at(i);
        if (v.type == Type::Vector && v.vp) {     // the Vector metatable's __index
            std::string k = name;
            st.push_back(k == "x" ? Val::number(v.vp->x) : k == "y" ? Val::number(v.vp->y) : k == "z" ? Val::number(v.vp->z) : Val());
            return;
        }
        Table *t = tab(i);
        st.push_back(t->get(Val::string(name)));
    }
    void SetField(int i, const char *name) override { Table *t = tab(i); Val v = pop(); t->set(Val::string(name), v); }
    void CreateTable() override { st.push_back(Val::table()); }
    void SetTable(int i) override { Table *t = tab(i); Val v = pop(); Val k = pop(); t->set(k, v); }
    void SetMetaTable(int) override { pop(); }
    bool GetMetaTable(int) override { return false; }
    void Call(int, int) override { lua_error_called("Call", "the module must use PCall"); }
    // calls a C function with a fresh frame; results are dropped (nresults 0 only); a C function that "raises"
    // (returns -1 here) leaves an error message like lua_pcall
    int PCall(int nargs, int nresults, int) override
    {
        if (nresults != 0 || (int)st.size() < nargs + 1) {
            lua_error_called("PCall", "unexpected arguments");
        }
        std::vector<Val> args(st.end() - nargs, st.end());
        st.resize(st.size() - (size_t)nargs);
        Val fn = pop();
        pcalls++;
        if (fn.type != Type::Function || !fn.fn) {
            st.push_back(Val::string("attempt to call a non-function"));
            return 2;
        }
        std::vector<Val> saved;
        saved.swap(st);
        st = args;
        int n = fn.fn(state);
        st.swap(saved);
        if (n < 0) {
            st.push_back(Val::string("mock error"));
            return 2;
        }
        return 0;
    }
    int Equal(int, int) override { return 0; }
    int RawEqual(int, int) override { return 0; }
    void Insert(int i) override { Val v = pop(); st.insert(st.begin() + (abs(i) - 1), v); }
    void Remove(int i) override { st.erase(st.begin() + (abs(i) - 1)); }
    int Next(int) override { return 0; }
    void *NewUserdata(unsigned int) override { lua_error_called("NewUserdata", ""); return nullptr; }
    void ThrowError(const char *m) override { lua_error_called("ThrowError", m); }
    void CheckType(int, int) override { lua_error_called("CheckType", ""); }
    void ArgError(int, const char *m) override { lua_error_called("ArgError", m); }
    void RawGet(int i) override { Table *t = tab(i); Val k = pop(); st.push_back(t->get(k)); }
    void RawSet(int i) override { Table *t = tab(i); Val v = pop(); Val k = pop(); t->set(k, v); }
    const char *GetString(int i, unsigned int *len) override
    {
        Val &v = at(i);
        if (v.type != Type::String) return nullptr;
        if (len) *len = (unsigned int)v.str.size();
        return v.str.c_str();
    }
    double GetNumber(int i) override { Val &v = at(i); return v.type == Type::Number ? v.num : 0.0; }
    bool GetBool(int i) override { Val &v = at(i); return !(v.type == Type::Nil || v.type == Type::None || (v.type == Type::Bool && !v.b)); }
    CFunc GetCFunction(int i) override { return at(i).fn; }
    void *GetUserdata(int) override { return nullptr; }
    void PushNil() override { st.push_back(Val()); }
    void PushString(const char *s, unsigned int len) override { st.push_back(Val::string(std::string(s, len ? len : std::strlen(s)))); }
    void PushNumber(double d) override { st.push_back(Val::number(d)); }
    void PushBool(bool b) override { st.push_back(Val::boolean(b)); }
    void PushCFunction(CFunc f) override { Val v; v.type = Type::Function; v.fn = f; st.push_back(v); }
    void PushCClosure(CFunc f, int) override { PushCFunction(f); }
    void PushUserdata(void *) override { lua_error_called("PushUserdata", ""); }
    std::map<int, Val> refs;
    int next_ref = 1;
    uint64_t pcalls = 0, vectors_pushed = 0;
    int ReferenceCreate() override { refs[next_ref] = pop(); return next_ref++; }
    void ReferenceFree(int r) override { refs.erase(r); }
    void ReferencePush(int r) override { auto it = refs.find(r); st.push_back(it == refs.end() ? Val() : it->second); }
    void PushSpecial(int t) override { st.push_back(t == SPECIAL_REG ? registry : globals); }
    bool IsType(int i, int t) override { return at(i).type == t; }
    int GetType(int i) override { return at(i).type; }
    const char *GetTypeName(int) override { return "?"; }
    void CreateMetaTableType(const char *, int) override { CreateTable(); }
    const char *CheckString(int) override { lua_error_called("CheckString", ""); return ""; }
    double CheckNumber(int) override { lua_error_called("CheckNumber", ""); return 0; }
    int ObjLen(int) override { return 0; }
    const QAngle &GetAngle(int i) override { return at(i).vec; }
    const Vector &GetVector(int i) override
    {
        static Vector zero;
        Val &v = at(i);
        return v.type == Type::Vector && v.vp ? *v.vp : zero;
    }
    void PushAngle(const QAngle &a) override { Val v; v.type = Type::Angle; v.vec.x = a.x; v.vec.y = a.y; v.vec.z = a.z; st.push_back(v); }
    void PushVector(const Vector &a) override { st.push_back(Val::vector(a.x, a.y, a.z)); vectors_pushed++; }
    void SetState(lua_State *L) override { state = L; }
    int CreateMetaTable(const char *) override { CreateTable(); return 255; }
    bool PushMetaTable(int) override { return false; }
    void PushUserType(void *, int) override { lua_error_called("PushUserType", ""); }
    void SetUserType(int, void *) override {}

    // calls gsa1.<name>(args...) with a fresh frame; checks that the frame holds the declared results
    std::vector<Val> call(const char *name, std::vector<Val> args)
    {
        Val fn = globals.tab->field("gsa1");
        if (fn.type == Type::Table) fn = fn.tab->field(name);
        if (fn.type != Type::Function) {
            std::printf("  FAIL  gsa1.%s is not a function\n", name);
            g_fail++;
            return {};
        }
        std::vector<Val> saved;
        saved.swap(st);
        st = args;
        int n = fn.fn(state);
        std::vector<Val> res;
        if (n < 0 || n > (int)st.size()) {
            std::printf("  FAIL  gsa1.%s returned %d values with %d on its stack\n", name, n, (int)st.size());
            g_fail++;
        } else {
            res.assign(st.end() - n, st.end());
        }
        st.swap(saved);
        return res;
    }
};

// ---- a mock of GMod's mesh library (what gsa1.EmitBatch calls) ---------------------------------------------------
struct MeshRec {
    uint64_t pos = 0, nrm = 0, tc = 0, col = 0, adv = 0, bad = 0;
    Vector p, n;
    float u = 0, v = 0;
    double c[4] = {0, 0, 0, 0};
    std::vector<float> vp, vn, vuv;
    std::vector<double> vc;
};
static MeshRec g_mesh;

inline MockLua *mock_of(lua_State *L) { return static_cast<MockLua *>(L->luabase); }

inline int mock_mesh_position(lua_State *L)
{
    Val &v = mock_of(L)->at(1);
    if (v.type != Type::Vector || !v.vp) { g_mesh.bad++; return 0; }
    g_mesh.p = *v.vp;
    g_mesh.pos++;
    return 0;
}
inline int mock_mesh_normal(lua_State *L)
{
    Val &v = mock_of(L)->at(1);
    if (v.type != Type::Vector || !v.vp) { g_mesh.bad++; return 0; }
    g_mesh.n = *v.vp;
    g_mesh.nrm++;
    return 0;
}
inline int mock_mesh_texcoord(lua_State *L)
{
    MockLua *m = mock_of(L);
    if (m->at(1).type != Type::Number || m->at(2).type != Type::Number || m->at(3).type != Type::Number) { g_mesh.bad++; return 0; }
    g_mesh.u = (float)m->at(2).num;
    g_mesh.v = (float)m->at(3).num;
    g_mesh.tc++;
    return 0;
}
inline int mock_mesh_color(lua_State *L)
{
    MockLua *m = mock_of(L);
    for (int k = 0; k < 4; k++) {
        if (m->at(k + 1).type != Type::Number) { g_mesh.bad++; return 0; }
        g_mesh.c[k] = m->at(k + 1).num;
    }
    g_mesh.col++;
    return 0;
}
inline int mock_mesh_advance(lua_State *)
{
    g_mesh.adv++;
    g_mesh.vp.insert(g_mesh.vp.end(), {g_mesh.p.x, g_mesh.p.y, g_mesh.p.z});
    g_mesh.vn.insert(g_mesh.vn.end(), {g_mesh.n.x, g_mesh.n.y, g_mesh.n.z});
    g_mesh.vuv.insert(g_mesh.vuv.end(), {g_mesh.u, g_mesh.v});
    g_mesh.vc.insert(g_mesh.vc.end(), {g_mesh.c[0], g_mesh.c[1], g_mesh.c[2], g_mesh.c[3]});
    return 0;
}

inline void install_mesh_library(MockLua &L)
{
    Val m = Val::table();
    auto fn = [](CFunc f) { Val v; v.type = Type::Function; v.fn = f; return v; };
    m.tab->set(Val::string("Position"), fn(mock_mesh_position));
    m.tab->set(Val::string("Normal"), fn(mock_mesh_normal));
    m.tab->set(Val::string("TexCoord"), fn(mock_mesh_texcoord));
    m.tab->set(Val::string("Color"), fn(mock_mesh_color));
    m.tab->set(Val::string("AdvanceVertex"), fn(mock_mesh_advance));
    L.globals.tab->set(Val::string("mesh"), m);
}

inline std::string str_of(const std::vector<Val> &r, size_t i)
{
    return i < r.size() && r[i].type == Type::String ? r[i].str : std::string("<") + (i < r.size() ? std::to_string(r[i].type) : "none") + ">";
}

inline bool is_nil_msg(const std::vector<Val> &r)
{
    return r.size() >= 2 && (r[0].type == Type::Nil || (r[0].type == Type::Bool && !r[0].b)) && r[1].type == Type::String;
}

#endif
