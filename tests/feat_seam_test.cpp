// feat_seam_test: the seam's own feature core test (plan section 5, G0), and the template of a feature's
// tests/feat_<feature>_test.cpp. build.py links every tests/feat_*_test.cpp (not *_binding_test.cpp) like core_test -
// the core objects (src/core/*.cpp, a feature's src/core/<feature>.cpp among them) and libsa1, no module and no Lua -
// and runs it with --gdi GAME.gdi when one is given (and SA1_TEST_GDI is set by the caller).
//
//   feat_seam_test [--gdi GAME.gdi]
//
// Checks: a Session can be made and destroyed without a disc; with the disc, a character is created, ticks, renders and
// is destroyed (the link line works and the disc argument arrives).
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "session.hpp"

static int g_fail = 0, g_checks = 0;
#define CHECK(cond, ...)                      \
    do {                                      \
        g_checks++;                           \
        std::printf((cond) ? "  ok    " : "  FAIL  "); \
        if (!(cond)) g_fail++;                \
        std::printf(__VA_ARGS__);             \
        std::printf("\n");                    \
    } while (0)

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") gdi = argv[++i];
    }
    std::printf("G-SA1 feat_seam_test\n");
    {
        gsa1::Session s;
        CHECK(!s.ready(), "a Session without a disc is not ready");
    }
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the disc checks are skipped\n");
    } else {
        gsa1::Session s;
        std::string err;
        bool ok = s.init(gdi, err);
        CHECK(ok, "Session::init with the disc%s%s", ok ? "" : ": ", err.c_str());
        if (ok) {
            // a 2048-unit square floor at z 0 (host space, Hammer units)
            std::vector<sa1_collision_tri> floor;
            sa1_collision_tri a = {{{-1024, -1024, 0}, {1024, -1024, 0}, {1024, 1024, 0}}, SA1_SURFACE_SOLID};
            sa1_collision_tri b = {{{-1024, -1024, 0}, {1024, 1024, 0}, {-1024, 1024, 0}}, SA1_SURFACE_SOLID};
            floor.push_back(a);
            floor.push_back(b);
            CHECK(s.set_world(floor, err), "a floor%s%s", err.empty() ? "" : ": ", err.c_str());
            const float pos[3] = {0.0f, 0.0f, 40.0f};
            int32_t id = s.create(SA1_CHAR_SONIC, pos, 0.0f, err);
            bool ticked = id > 0 && s.tick(id, 0.0f, 0.0f, 0.0f, 0, 1.0f / 60.0f) == SA1_OK &&
                          s.render(id, -1.0f) == SA1_OK;
            CHECK(id > 0 && ticked, "Sonic created (id %d), one tick and one render%s%s", (int)id, err.empty() ? "" : ": ",
                  err.c_str());
            if (id > 0) s.destroy(id);
            s.shutdown();
        }
    }
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
