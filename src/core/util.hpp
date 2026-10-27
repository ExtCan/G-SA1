// G-SA1 core: small platform helpers (UTF-8 paths, files, timing, string formatting).
// No GMod and no libsa1 dependency.
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace gsa1 {

double now_ms();

// A function on a thread of its own (0.5.1: the disc, the sound banks, the map's collision and its preparation for
// libsa1 load off the game's thread). done() never blocks; join() does (the destructor joins).
class Worker {
public:
    Worker() = default;
    ~Worker() { join(); }
    Worker(const Worker &) = delete;
    Worker &operator=(const Worker &) = delete;
    void start(std::function<void()> fn);
    bool started() const { return t_.joinable(); }
    bool done() const { return done_ && done_->load(); }
    void join();

private:
    std::thread t_;
    std::shared_ptr<std::atomic<bool>> done_;
};

// Workers that nobody waits for any more (a sound bank load that was replaced, a map job that was cancelled): reap()
// joins the finished ones without blocking; the destructor (module unload) joins the rest.
class Graveyard {
public:
    ~Graveyard() { join_all(); }
    void add(std::unique_ptr<Worker> w);
    void reap();
    void join_all();
    size_t size() const { return w_.size(); }

private:
    std::vector<std::unique_ptr<Worker>> w_;
};

std::string format(const char *fmt, ...)
#if defined(__GNUC__) || defined(__clang__)
    __attribute__((format(printf, 1, 2)))
#endif
    ;

bool iequals(const std::string &a, const std::string &b);
bool ends_with_ci(const std::string &s, const char *suffix);
std::string to_lower(std::string s);

// Path helpers (both separators accepted on input; output uses the platform separator).
char path_sep();
bool is_sep(char c);
std::string join_path(const std::string &a, const std::string &b);
std::string parent_dir(const std::string &p);   // "" when there is none
std::string base_name(const std::string &p);

#ifdef _WIN32
std::wstring widen(const std::string &utf8);    // empty on invalid UTF-8
std::string narrow(const std::wstring &w);
#endif

bool file_exists(const std::string &utf8_path);
bool dir_exists(const std::string &utf8_path);
bool make_dirs(const std::string &utf8_dir);
// Subdirectory names of a directory (no "." / ".."); empty on failure.
std::vector<std::string> list_subdirs(const std::string &utf8_dir);

// Reads a whole (small) file; fails when it is larger than max_bytes.
bool read_small_file(const std::string &utf8_path, size_t max_bytes, std::string &out, std::string &err);
// Writes a file through a temporary name and a rename.
bool write_file_replace(const std::string &utf8_path, const std::string &data, std::string &err);

// Read-only file with 64-bit offsets.
class File {
public:
    File() = default;
    ~File();
    File(const File &) = delete;
    File &operator=(const File &) = delete;
    bool open(const std::string &utf8_path, std::string &err);
    void close();
    bool is_open() const { return f_ != nullptr; }
    uint64_t size() const { return size_; }
    bool read_at(uint64_t offset, void *dst, size_t n);

private:
    std::FILE *f_ = nullptr;
    uint64_t size_ = 0;
};

// Valid UTF-8 without overlong forms or surrogates.
bool valid_utf8(const char *s, size_t n);

}  // namespace gsa1
