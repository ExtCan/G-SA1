// G-SA1 core: the followers' worker pool (see pool.hpp).
#include "pool.hpp"

#include <algorithm>
#include <exception>

#include "util.hpp"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace gsa1 {

const bool kPoolLibParallel = true;     // SNAP-F holds L4 and T1 (lanes/lib_threads_t1.txt)

uint32_t pool_automatic_workers(size_t followers, unsigned logical_cores)
{
    if (followers <= 4) {
        return 0;
    }
    size_t quarter = (followers + 3) / 4;
    size_t spare = logical_cores > 4 ? logical_cores - 4u : 0u;
    return (uint32_t)std::min<size_t>(8u, std::min(spare, quarter));
}

unsigned pool_logical_cores()
{
    unsigned n = std::thread::hardware_concurrency();
    return n > 0 ? n : 1u;
}

Pool::~Pool()
{
    set_workers(0);
}

void Pool::set_workers(uint32_t n)
{
    n = std::min(n, kPoolMaxWorkers);
    if (n == threads_.size()) {
        return;
    }
    {
        std::lock_guard<std::mutex> lk(m_);
        stop_ = true;
    }
    work_cv_.notify_all();
    for (std::thread &t : threads_) {
        t.join();
    }
    threads_.clear();
    stop_ = false;
    busy_ = 0;
    threads_.reserve(n);
    for (uint32_t i = 0; i < n; i++) {
        threads_.emplace_back([this] { worker_main(); });
    }
}

void Pool::worker_main()
{
#ifdef _WIN32
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
#endif
    uint64_t seen = 0;
    {
        // a worker made between phases does not run the phase before it (set_workers runs between phases only)
        std::lock_guard<std::mutex> lk(m_);
        seen = gen_;
    }
    std::unique_lock<std::mutex> lk(m_);
    for (;;) {
        work_cv_.wait(lk, [&] { return stop_ || gen_ != seen; });
        if (stop_) {
            return;
        }
        seen = gen_;
        busy_++;
        lk.unlock();
        take_jobs();
        lk.lock();
        if (--busy_ == 0) {
            done_cv_.notify_all();
        }
    }
}

void Pool::take_jobs()
{
    const uint32_t n = n_;
    for (;;) {
        uint32_t i = next_.fetch_add(1, std::memory_order_relaxed);
        if (i >= n) {
            return;
        }
        try {
            run_(user_, i);
        } catch (const std::exception &e) {
            if (threw_) {
                threw_(user_, i, e.what());
            }
        } catch (...) {
            if (threw_) {
                threw_(user_, i, "an unknown exception");
            }
        }
        jobs_run_.fetch_add(1, std::memory_order_relaxed);
        if (done_.fetch_add(1, std::memory_order_acq_rel) + 1 == n) {
            std::lock_guard<std::mutex> lk(m_);
            done_cv_.notify_all();
        }
    }
}

void Pool::run_phase(RunFn run, ThrewFn threw, void *user, uint32_t n)
{
    last_wait_ms_ = 0.0;
    if (n == 0 || !run) {
        return;
    }
    phases_++;
    if (threads_.empty() || n == 1) {
        // no worker needed: the caller's thread, in index order
        for (uint32_t i = 0; i < n; i++) {
            try {
                run(user, i);
            } catch (const std::exception &e) {
                if (threw) {
                    threw(user, i, e.what());
                }
            } catch (...) {
                if (threw) {
                    threw(user, i, "an unknown exception");
                }
            }
            jobs_run_.fetch_add(1, std::memory_order_relaxed);
        }
        return;
    }
    {
        std::unique_lock<std::mutex> lk(m_);
        done_cv_.wait(lk, [&] { return busy_ == 0; });     // a late worker of the last phase is out of take_jobs()
        run_ = run;
        threw_ = threw;
        user_ = user;
        n_ = n;
        next_.store(0, std::memory_order_relaxed);
        done_.store(0, std::memory_order_relaxed);
        gen_++;
    }
    work_cv_.notify_all();
    take_jobs();
    double t0 = now_ms();
    {
        std::unique_lock<std::mutex> lk(m_);
        done_cv_.wait(lk, [&] { return done_.load(std::memory_order_acquire) == n; });
    }
    last_wait_ms_ = now_ms() - t0;
    wait_sum_ms_ += last_wait_ms_;
}

double Pool::take_wait_ms()
{
    double v = wait_sum_ms_;
    wait_sum_ms_ = 0.0;
    return v;
}

}  // namespace gsa1
