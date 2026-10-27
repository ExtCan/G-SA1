// feat_seam_binding_test: the seam's own feature binding test (plan section 5, G0), and the template of a feature's
// tests/feat_<feature>_binding_test.cpp. build.py links every tests/feat_*_binding_test.cpp like binding_test - with the
// module's objects (gsa1_module.cpp, gsa1_feature.cpp, every src/module/bind_<feature>.cpp) and libsa1 - and runs it
// with --gdi GAME.gdi when one is given; the mock Lua stack is tests/mock_lua.hpp.
//
//   feat_seam_binding_test [--gdi GAME.gdi]
//
// Checks: a feature registered in another file than gsa1_module.cpp (here: this test) reaches gsa1.FEATURES and the gsa1
// table at gmod13_open with nothing else edited; its function follows the binding rules (no Lua error, nil + message
// for a bad argument, the caller's stack untouched); the module's features found here are listed; gmod13_close runs
// its close hook and removes the table.
#include <cstdio>
#include <cstring>
#include <string>

#include "mock_lua.hpp"
#include "../src/module/gsa1_feature.hpp"
#include "../src/module/gsa1_module_internal.hpp"

static int g_closed = 0;

// gsa1.SeamAdd(a, b) -> a + b | nil, message, "bad_argument"
GSA1_FN(gsa1_seam_Add)
{
    double a = 0, b = 0;
    if (!gsa1::mod::arg_number(LUA, 1, a) || !gsa1::mod::arg_number(LUA, 2, b)) {
        return gsa1::mod::push_nil_msg(LUA, "SeamAdd(a, b): two numbers", "bad_argument");
    }
    LUA->PushNumber(a + b);
    return 1;
}

static const gsa1::FeatureFn k_seam_fns[] = {{"SeamAdd", gsa1_seam_Add}};
static void seam_close(ILuaBase *) { g_closed++; }
GSA1_FEATURE(seam, 1, k_seam_fns, nullptr, seam_close, gsa1::kCloseDefault);

int main(int argc, char **argv)
{
    std::printf("G-SA1 feat_seam_binding_test\n");
    (void)argc;
    (void)argv;
    MockLua L;
    lua_State state;
    std::memset(&state, 0, sizeof state);
    state.luabase = &L;
    L.state = &state;
    gmod13_open(&state);
    Val g = L.globals.tab->field("gsa1");
    CHECK(g.type == Type::Table && L.st.empty(), "gmod13_open registers the gsa1 table");
    if (g.type != Type::Table) return 1;
    Val feats = g.tab->field("FEATURES"), errs = g.tab->field("FEATURE_ERRORS");
    std::string names;
    if (feats.type == Type::Table) {
        for (auto &kv : feats.tab->s) names += (names.empty() ? "" : ", ") + kv.first + " " + std::to_string((int)kv.second.num);
    }
    CHECK(feats.type == Type::Table && feats.tab->field("seam").num == 1 && errs.type == Type::Table && errs.tab->n.empty(),
          "gsa1.FEATURES: %s; gsa1.FEATURE_ERRORS empty", names.c_str());
    auto r = L.call("SeamAdd", {Val::number(2), Val::number(40)});
    CHECK(r.size() == 1 && r[0].type == Type::Number && r[0].num == 42 && L.st.empty(), "gsa1.SeamAdd(2, 40) = %g",
          r.empty() ? -1.0 : r[0].num);
    r = L.call("SeamAdd", {Val::number(2)});
    CHECK(is_nil_msg(r) && str_of(r, 2) == "bad_argument", "gsa1.SeamAdd(2): nil, \"%s\", %s", str_of(r, 1).c_str(),
          str_of(r, 2).c_str());
    gmod13_close(&state);
    CHECK(g_closed == 1 && L.globals.tab->field("gsa1").type == Type::Nil, "gmod13_close: the close hook ran once and "
          "the gsa1 table is gone");
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
