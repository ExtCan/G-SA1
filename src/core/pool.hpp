// G-SA1 core: the followers' worker pool (round 0.9.8: sadc docs/research/gsa1_098_plan.md 2.4, 3.2; gsa1_096_plan.md 4.11 d,
// 6.4 task 3 with its Review R.1 / R.2; follow096_scale.md 5.1, 5.3). No GMod dependency and no libsa1 dependency: the pool
// runs "jobs" (an index and a function); Session::tick_followers (session.cpp) gives them the follower worlds, and
// tests/feat_follower_pool_test.cpp gives them fake ones.
//
// The model. std::thread x T (gsa1.FollowerThreads(n), below) plus the game thread: a job list per PHASE, an atomic next index,
// a done count and an event. run_phase() starts one phase, takes jobs on the calling thread too, and returns after every job of
// that phase ended, so a phase's jobs never overlap the next phase's: Session runs one phase per chain level (a level-k follower
// never starts before every level k-1 follower ended, because a follower reads its leader's step ring) and no job runs when Lua
// runs (096 4.11 d). Workers run at THREAD_PRIORITY_BELOW_NORMAL. A job that throws marks only itself (the `threw` callback, on
// the thread that ran it); every other job of the phase still runs and the phase still ends.
//
// With 0 workers there is no thread and no lock: the caller runs the jobs itself, in index order.
#pragma once

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

namespace gsa1 {

// May a job call libsa1 on a worker? False until the libsa1 snapshot has L4 and T1 (SA1_API_PARALLEL's contract and the race fix,
// lanes/lib_threads_t1.txt): before that the contract's archives can crash on two threads (follow096_scale.md 2.7), so
// Session forces 0 workers for real worlds. Fake jobs (the pool test) use workers whatever this says. Set true by
// 098-gsa1-followmod right after SNAP-F (plan 6.6); from there on false is a failure of tests/feat_follower_pool_test.cpp.
extern const bool kPoolLibParallel;

// gsa1.FollowerThreads(0), automatic (096 4.11 d): no worker for up to 4 followers (the game thread runs them), else
// min(8, logical cores - 4, ceil(followers / 4)). On 20 logical cores: 1 -> 0, 4 -> 0, 5 -> 2, 20 -> 5, 99 -> 8
uint32_t pool_automatic_workers(size_t followers, unsigned logical_cores);
// std::thread::hardware_concurrency(), at least 1
unsigned pool_logical_cores();
// the largest worker count gsa1.FollowerThreads takes (the ConVar's slider, plan 5.9)
const uint32_t kPoolMaxWorkers = 16;

class Pool {
public:
    using RunFn = void (*)(void *user, uint32_t index);
    using ThrewFn = void (*)(void *user, uint32_t index, const char *what);

    Pool() = default;
    ~Pool();
    Pool(const Pool &) = delete;
    Pool &operator=(const Pool &) = delete;

    // the worker threads (not counting the caller of run_phase), at most kPoolMaxWorkers; between phases only: the pool is rebuilt
    void set_workers(uint32_t n);
    uint32_t workers() const { return (uint32_t)threads_.size(); }

    // jobs 0..n-1 of one phase: run(user, i) once each, on the workers and on this thread, in no fixed order (0 workers: in
    // index order). Returns after every job ended. A job that throws: threw(user, i, what) on its thread, nothing else happens
    void run_phase(RunFn run, ThrewFn threw, void *user, uint32_t n);

    // how long the calling thread waited for the workers after it had no job left, in the last run_phase and summed over the
    // phases since the last take_wait_ms()
    double last_wait_ms() const { return last_wait_ms_; }
    double take_wait_ms();
    uint64_t phases() const { return phases_; }
    uint64_t jobs_run() const { return jobs_run_.load(std::memory_order_relaxed); }

private:
    void worker_main();
    void take_jobs();

    std::vector<std::thread> threads_;
    std::mutex m_;
    std::condition_variable work_cv_, done_cv_;
    bool stop_ = false;
    uint64_t gen_ = 0;
    uint32_t busy_ = 0;                       // workers between their wake-up and the end of their take_jobs()
    // the phase (written under m_ while busy_ == 0: a late worker never sees a half-written phase)
    RunFn run_ = nullptr;
    ThrewFn threw_ = nullptr;
    void *user_ = nullptr;
    uint32_t n_ = 0;
    std::atomic<uint32_t> next_{0};
    std::atomic<uint32_t> done_{0};
    std::atomic<uint64_t> jobs_run_{0};
    double last_wait_ms_ = 0.0, wait_sum_ms_ = 0.0;
    uint64_t phases_ = 0;
};

}  // namespace gsa1
