// feat_follower_pool_test: the followers' worker pool (round 0.9.8: sadc docs/research/gsa1_098_plan.md 2.4, 3.2, 6.6; gsa1_096_plan.md
// 4.11 d, 6.4 task 6 with its Review R.2; R98.17) - src/core/pool.{hpp,cpp} and, after SNAP-F, Session::tick_followers on real
// follower worlds. Linked like core_test by build.py (tests/feat_*_test.cpp) and run with --gdi when there is one.
//
//   feat_follower_pool_test [--gdi GAME.gdi]
//
// Fake jobs on 0 / 1 / 2 / 8 workers: chain levels respected (a phase never starts before the last one ended), every job run once, a
// throwing job marks only itself, the join, workers below normal priority, the automatic worker count for 1, 4, 5, 20, 99
// followers on 20 logical cores (0, 0, 2, 5, 8), the pool rebuilt between phases, 5,000 empty phases without a lost wake-up.
//
// Real follower worlds (libsa1 with SA1_API_FOLLOWER built, the disc, kPoolLibParallel true; before that exactly one line "SKIP
// behaviour: follower is not built yet"): 8 and 99 Knuckles followers (objects 0, silent) on 1 / 2 / 8 workers - every follower's
// state sequence (an FNV hash of sa1_state_ex per tick) equal to the 1-worker run, 0 faults in 600 pairs, jobs on at least 2 distinct
// threads with 2 and with 8 workers. kPoolLibParallel false is a failure from SNAP-F on (kLibHasT1, set with it). With
// GSA1_TEST_TIMING=1 also the wall time per FollowersTick, 3 runs each: median and spread (review R98.17; one info line when off).
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#include "../src/core/pool.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"

using namespace gsa1;

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

#define INFO(...)                                            \
    do {                                                     \
        std::printf("  info  ");                             \
        std::printf(__VA_ARGS__);                            \
        std::printf("\n");                                   \
    } while (0)

struct FakeJobs {
    std::vector<std::atomic<int>> runs;
    std::vector<std::atomic<uint64_t>> tid;
    std::vector<std::atomic<int>> threw;
    std::atomic<uint32_t> phase_active{0};
    std::atomic<uint32_t> overlaps{0};
    std::atomic<uint32_t> below_normal{0}, on_workers{0};
    uint64_t main_tid = 0;
    int throw_index = -1;
    int sleep_ms = 0;
    explicit FakeJobs(size_t n) : runs(n), tid(n), threw(n)
    {
        for (size_t i = 0; i < n; i++) {
            runs[i] = 0;
            tid[i] = 0;
            threw[i] = 0;
        }
        main_tid = (uint64_t)std::hash<std::thread::id>()(std::this_thread::get_id());
    }
};

static void fake_run(void *user, uint32_t i)
{
    FakeJobs *f = static_cast<FakeJobs *>(user);
    f->runs[i].fetch_add(1);
    uint64_t me = (uint64_t)std::hash<std::thread::id>()(std::this_thread::get_id());
    f->tid[i] = me;
#ifdef _WIN32
    if (me != f->main_tid) {
        f->on_workers.fetch_add(1);
        if (GetThreadPriority(GetCurrentThread()) == THREAD_PRIORITY_BELOW_NORMAL) {
            f->below_normal.fetch_add(1);
        }
    }
#endif
    if (f->sleep_ms > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(f->sleep_ms));
    }
    if ((int)i == f->throw_index) {
        throw std::runtime_error("job says no");
    }
}

static void fake_threw(void *user, uint32_t i, const char *what)
{
    FakeJobs *f = static_cast<FakeJobs *>(user);
    f->threw[i] = what && std::string(what) == "job says no" ? 1 : 2;
}

static void test_automatic()
{
    std::printf("the automatic worker count (096 4.11 d)\n");
    CHECK(pool_automatic_workers(1, 20) == 0 && pool_automatic_workers(4, 20) == 0 && pool_automatic_workers(5, 20) == 2 &&
              pool_automatic_workers(20, 20) == 5 && pool_automatic_workers(99, 20) == 8,
          "on 20 logical cores: 1 -> 0, 4 -> 0, 5 -> 2, 20 -> 5, 99 -> 8");
    CHECK(pool_automatic_workers(99, 4) == 0 && pool_automatic_workers(99, 2) == 0 && pool_automatic_workers(99, 6) == 2 &&
              pool_automatic_workers(0, 20) == 0,
          "few cores: min(8, logical cores - 4, ceil(followers / 4)): 4 and 2 cores -> 0, 6 cores -> 2");
    INFO("this machine has %u logical cores", pool_logical_cores());
}

static void test_fake_jobs(uint32_t workers)
{
    std::printf("fake jobs on %u worker(s)\n", (unsigned)workers);
    Pool pool;
    pool.set_workers(workers);
    CHECK(pool.workers() == workers, "the pool has %u workers", (unsigned)pool.workers());

    // every job once, joined before run_phase returns
    {
        FakeJobs f(1000);
        pool.run_phase(fake_run, fake_threw, &f, 1000);
        int bad = 0;
        for (auto &r : f.runs) {
            bad += r.load() != 1;
        }
        CHECK(bad == 0 && pool.jobs_run() == 1000, "1,000 jobs: each ran once when run_phase returned (%d wrong)", bad);
    }

    // chain levels: 5 phases of 40 jobs; a job of phase k sees every job of phase k - 1 ended
    {
        struct Level {
            std::atomic<int> ended[5];
            std::atomic<int> early{0};
            int phase = 0;
        } lv;
        for (auto &e : lv.ended) {
            e = 0;
        }
        for (int p = 0; p < 5; p++) {
            lv.phase = p;
            pool.run_phase([](void *u, uint32_t) {
                Level *l = static_cast<Level *>(u);
                if (l->phase > 0 && l->ended[l->phase - 1].load() != 40) {
                    l->early.fetch_add(1);
                }
                std::this_thread::sleep_for(std::chrono::microseconds(200));
                l->ended[l->phase].fetch_add(1);
            }, nullptr, &lv, 40);
        }
        bool all = true;
        for (auto &e : lv.ended) {
            all = all && e.load() == 40;
        }
        CHECK(all && lv.early.load() == 0, "5 phases of 40 jobs: no job started before the phase before it had ended (%d early)",
              lv.early.load());
    }

    // a throwing job marks only itself
    {
        FakeJobs f(64);
        f.throw_index = 17;
        pool.run_phase(fake_run, fake_threw, &f, 64);
        int others = 0, threw = 0;
        for (size_t i = 0; i < 64; i++) {
            if (i != 17) {
                others += f.threw[i].load() != 0 || f.runs[i].load() != 1;
            } else {
                threw = f.threw[i].load();
            }
        }
        CHECK(threw == 1 && others == 0, "a job that throws: its own callback with the message, the other 63 ran and are unmarked");
        pool.run_phase(fake_run, nullptr, &f, 18);     // no callback: still no exception out of the pool
        CHECK(f.runs[17].load() == 2, "without a callback a throw is swallowed too");
    }

    // the threads
    if (workers > 0) {
        FakeJobs f(64);
        f.sleep_ms = 2;
        pool.run_phase(fake_run, fake_threw, &f, 64);
        std::set<uint64_t> ids;
        bool main_took = false;
        for (auto &t : f.tid) {
            ids.insert(t.load());
            main_took = main_took || t.load() == f.main_tid;
        }
        CHECK(ids.size() >= 2 && main_took, "%zu distinct threads ran 64 jobs of 2 ms, the game thread took jobs too", ids.size());
#ifdef _WIN32
        CHECK(f.on_workers.load() > 0 && f.below_normal.load() == f.on_workers.load(), "workers run below normal priority (%u of %u jobs)",
              f.below_normal.load(), f.on_workers.load());
#endif
    } else {
        FakeJobs f(16);
        pool.run_phase(fake_run, fake_threw, &f, 16);
        bool main_only = true;
        for (auto &t : f.tid) {
            main_only = main_only && t.load() == f.main_tid;
        }
        CHECK(main_only, "no worker: every job on the calling thread");
    }

    // no lost wake-up
    {
        std::atomic<uint64_t> total{0};
        double t0 = now_ms();
        for (int p = 0; p < 5000; p++) {
            pool.run_phase([](void *u, uint32_t) { static_cast<std::atomic<uint64_t> *>(u)->fetch_add(1); }, nullptr, &total, 3);
        }
        CHECK(total.load() == 15000u, "5,000 phases of 3 empty jobs: none lost (%.2f us a phase)", (now_ms() - t0) * 1000.0 / 5000.0);
        // jobs long enough for the workers to be awake in them
        std::atomic<uint64_t> spun{0};
        for (int p = 0; p < 1000; p++) {
            pool.run_phase([](void *u, uint32_t) {
                double t = now_ms();
                while (now_ms() - t < 0.02) {
                }
                static_cast<std::atomic<uint64_t> *>(u)->fetch_add(1);
            }, nullptr, &spun, 8);
        }
        CHECK(spun.load() == 8000u, "1,000 phases of 8 jobs of 20 us: none lost");
    }
}

static void test_rebuild()
{
    std::printf("the pool rebuilt between phases\n");
    Pool pool;
    for (uint32_t n : {8u, 2u, 0u, 3u, 16u, 100u, 1u, 0u}) {
        pool.set_workers(n);
        FakeJobs f(32);
        pool.run_phase(fake_run, fake_threw, &f, 32);
        int bad = 0;
        for (auto &r : f.runs) {
            bad += r.load() != 1;
        }
        CHECK(pool.workers() == std::min(n, kPoolMaxWorkers) && bad == 0, "set_workers(%u): %u workers, 32 jobs each ran once", (unsigned)n,
              (unsigned)pool.workers());
    }
    pool.run_phase(fake_run, fake_threw, nullptr, 0);
    CHECK(true, "a phase of no jobs returns at once");
}

#if defined(SA1_API_FOLLOWER)
// set true with kPoolLibParallel, right after SNAP-F (L4 and T1 are in the snapshot)
static const bool kLibHasT1 = true;

static uint64_t fnv_state(uint64_t h, const sa1_state_ex &st)
{
    const uint8_t *b = reinterpret_cast<const uint8_t *>(&st);
    for (size_t i = 0; i < sizeof st; i++) {
        h = (h ^ b[i]) * 1099511628211ull;
    }
    return h;
}

// a flat SOLID floor (host space, z up)
static std::vector<sa1_collision_tri> floor_tris(float half, float tile)
{
    std::vector<sa1_collision_tri> out;
    for (float x = -half; x < half - 0.5f; x += tile) {
        for (float y = -half; y < half - 0.5f; y += tile) {
            const float p[4][3] = {{x, y, 0.0f}, {x + tile, y, 0.0f}, {x + tile, y + tile, 0.0f}, {x, y + tile, 0.0f}};
            sa1_collision_tri a, b;
            std::memset(&a, 0, sizeof a);
            std::memset(&b, 0, sizeof b);
            std::memcpy(a.v[0], p[0], 12);
            std::memcpy(a.v[1], p[1], 12);
            std::memcpy(a.v[2], p[2], 12);
            std::memcpy(b.v[0], p[0], 12);
            std::memcpy(b.v[1], p[2], 12);
            std::memcpy(b.v[2], p[3], 12);
            a.surface = b.surface = SA1_SURFACE_SOLID;
            out.push_back(a);
            out.push_back(b);
        }
    }
    return out;
}

struct RealRun {
    bool ok = false;
    std::vector<uint64_t> hashes;       // per follower
    uint32_t faults = 0, threads = 0, workers = 0;
    double ms_tick_mean = 0.0;
};

// a scripted Sonic and n Knuckles followers (objects 0, silent), 600 pairs, one FollowersTick per pair
static RealRun real_run(Session &s, size_t n, uint32_t workers, int pairs)
{
    RealRun r;
    std::string err;
    const float start[3] = {0.0f, 0.0f, 40.0f};
    int32_t leader = s.create(SA1_CHAR_SONIC, start, 0.0f, err);
    if (leader <= 0) {
        CHECK(false, "the leader: %s", err.c_str());
        return r;
    }
    std::vector<int32_t> ids;
    FollowerOpts o;
    o.objects = 0;
    o.sounds = false;
    for (size_t i = 0; i < n; i++) {
        o.seed_given = true;
        o.seed = (uint32_t)(1000 + i);
        const float p[3] = {-40.0f * (float)(i % 10), -40.0f * (float)(i / 10), 40.0f};
        const char *code = nullptr;
        int32_t id = s.create_follower(SA1_CHAR_KNUCKLES, p, 0.0f, leader, o, err, &code);
        if (id <= 0) {
            CHECK(false, "follower %zu: %s (%s)", i, err.c_str(), code ? code : "");
            return r;
        }
        ids.push_back(id);
    }
    r.hashes.assign(n, 1469598103934665603ull);
    s.set_follower_threads(workers);
    std::vector<FollowerTickResult> out;
    std::set<uint64_t> threads;
    double sum = 0.0;
    const float dt = 1.0f / 30.0f;
    for (int t = 0; t < pairs; t++) {
        // run, turn, jump: the same script in every run
        float sx = std::sin((float)t * 0.02f), sy = std::cos((float)t * 0.02f);
        uint32_t buttons = (t % 120) >= 100 ? SA1_BUTTON_JUMP : 0u;
        s.tick(leader, sx, sy, 0.0f, buttons, dt);
        double t0 = now_ms();
        s.tick_followers(dt, 0.0f, nullptr, true, out);
        sum += now_ms() - t0;
        for (size_t i = 0; i < n; i++) {
            Character *c = s.get(ids[i]);
            if (!c || c->faulted) {
                r.faults++;
                continue;
            }
            r.hashes[i] = fnv_state(r.hashes[i], c->st);
            if (t >= pairs - 10) {
                threads.insert(c->job_thread);
            }
        }
    }
    r.threads = (uint32_t)threads.size();
    r.workers = s.pool().workers();
    r.ms_tick_mean = sum / (double)pairs;
    for (int32_t id : ids) {
        s.destroy(id);
    }
    s.destroy(leader);
    std::vector<sa1_event> ev;
    s.poll_events(ev);
    r.ok = true;
    return r;
}

static void test_real(const std::string &gdi)
{
    std::printf("real follower worlds (096 6.4 task 6, review R.2)\n");
    if (sa1_follower_kinds() == 0 || !((sa1_follower_kinds() >> SA1_CHAR_KNUCKLES) & 1u)) {
        std::printf("SKIP behaviour: follower is not built yet\n");
        INFO("sa1_follower_kinds() = 0x%X; kPoolLibParallel %s", (unsigned)sa1_follower_kinds(), kPoolLibParallel ? "true" : "false");
        return;
    }
    if (gdi.empty()) {
        INFO("no --gdi: the real worlds need the disc");
        return;
    }
    std::printf("  info  kPoolLibParallel %s\n", kPoolLibParallel ? "true" : "false");
    CHECK(kPoolLibParallel == kLibHasT1, "kPoolLibParallel is %s (true from SNAP-F on: it holds L4 and T1)", kPoolLibParallel ? "true" : "false");
    if (!kPoolLibParallel) {
        std::printf("SKIP behaviour: follower is not built yet\n");
        INFO("the follower API is built, but this snapshot has no L4 and T1 yet: no job may run on two threads");
        return;
    }
    Session s;
    std::string err;
    if (!s.init(gdi, err)) {
        CHECK(false, "the disc: %s", err.c_str());
        return;
    }
    CHECK(s.set_world(floor_tris(16384.0f, 256.0f), err), "a flat SOLID floor as the static collision (%s)", err.c_str());
    const bool timing = std::getenv("GSA1_TEST_TIMING") != nullptr;
    if (!timing) {
        INFO("GSA1_TEST_TIMING is not set: the 3-run timing repeats are off (review R98.17)");
    }
    for (size_t n : {(size_t)3, (size_t)8, (size_t)99}) {
        RealRun base;
        for (uint32_t w : {1u, 2u, 8u}) {
            RealRun r = real_run(s, n, w, 600);
            if (!r.ok) {
                CHECK(false, "%zu followers on %u workers did not run", n, (unsigned)w);
                continue;
            }
            CHECK(r.faults == 0, "%zu Knuckles on %u worker(s): 0 faults in 600 pairs (%u)", n, (unsigned)w, r.faults);
            if (w == 1) {
                base = r;
            } else {
                size_t differ = 0;
                for (size_t i = 0; i < n && i < base.hashes.size() && i < r.hashes.size(); i++) {
                    differ += base.hashes[i] != r.hashes[i];
                }
                CHECK(differ == 0 && r.hashes.size() == n, "%zu Knuckles on %u workers: every state sequence equal to the 1-worker run "
                      "(%zu of %zu differ)", n, (unsigned)w, differ, n);
                if (n >= 8) {       // (3 short jobs may all end on one thread before another wakes)
                    CHECK(r.threads >= 2, "%zu Knuckles on %u workers: the last 10 frames' jobs ran on %u distinct threads", n, (unsigned)w, r.threads);
                }
            }
            INFO("%zu Knuckles on %u worker(s): FollowersTick %.2f ms (mean of 600 pairs)", n, (unsigned)w, r.ms_tick_mean);
            if (timing) {
                std::vector<double> ms;
                for (int k = 0; k < 3; k++) {
                    RealRun t = real_run(s, n, w, 600);
                    ms.push_back(t.ms_tick_mean);
                }
                std::sort(ms.begin(), ms.end());
                INFO("timing: %zu Knuckles on %u worker(s): FollowersTick median %.2f ms, spread %.2f..%.2f (3 runs)", n, (unsigned)w, ms[1], ms[0], ms[2]);
            }
        }
    }
    // workers get the exe's default stack: gmod.exe reserves 1.5 MB (read from its PE header), and the player's world has always run on
    // that main thread. The game thread takes jobs too, so its committed stack shows what follower jobs ask of a stack
#ifdef _WIN32
    {
        const NT_TIB *tib = reinterpret_cast<const NT_TIB *>(NtCurrentTeb());
        MEMORY_BASIC_INFORMATION mbi;
        std::memset(&mbi, 0, sizeof mbi);
        size_t committed = 0;
        if (VirtualQuery(reinterpret_cast<const char *>(tib->StackBase) - 1, &mbi, sizeof mbi)) {
            const char *a = static_cast<const char *>(mbi.AllocationBase);
            const char *top = static_cast<const char *>(tib->StackBase);
            while (a < top && VirtualQuery(a, &mbi, sizeof mbi)) {
                if (mbi.State == MEM_COMMIT) {
                    committed += mbi.RegionSize;
                }
                a += mbi.RegionSize;
            }
        }
        CHECK(committed > 0 && committed < 1200u * 1024u, "the deepest stack on this thread after all that: %zu KB committed (gmod.exe reserves 1,536 KB a thread)", committed / 1024u);
    }
#endif
    s.shutdown();
}
#endif

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) {
        gdi = e;
    }
    for (int i = 1; i + 1 < argc; i++) {
        if (std::string(argv[i]) == "--gdi") {
            gdi = argv[++i];
        }
    }
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("G-SA1 feat_follower_pool_test\n");
    // a lost wake-up would hang the test run: this ends it with a failure instead
    std::thread watchdog([] {
        for (int s = 0; s < 1200; s++) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
        std::printf("  FAIL  the pool test did not end within 20 minutes\n");
        std::fflush(stdout);
        std::_Exit(2);
    });
    watchdog.detach();
    test_automatic();
    for (uint32_t w : {0u, 1u, 2u, 8u}) {
        test_fake_jobs(w);
    }
    test_rebuild();
#if defined(SA1_API_FOLLOWER)
    test_real(gdi);
#else
    std::printf("  info  this libsa1.h has no SA1_API_FOLLOWER: only the fake jobs ran; kPoolLibParallel %s\n", kPoolLibParallel ? "true" : "false");
#endif
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
