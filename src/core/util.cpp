// G-SA1 core: platform helpers.
#include "util.hpp"

#include <chrono>
#include <cstdarg>
#include <cstring>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dirent.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#endif

namespace gsa1 {

void Worker::start(std::function<void()> fn)
{
    join();
    auto done = std::make_shared<std::atomic<bool>>(false);
    done_ = done;
    t_ = std::thread([fn, done]() {
        try {
            fn();
        } catch (...) {
        }
        done->store(true);
    });
}

void Worker::join()
{
    if (t_.joinable()) {
        t_.join();
    }
}

void Graveyard::add(std::unique_ptr<Worker> w)
{
    if (w) {
        w_.push_back(std::move(w));
    }
    reap();
}

void Graveyard::reap()
{
    for (size_t i = 0; i < w_.size();) {
        if (!w_[i]->started() || w_[i]->done()) {
            w_[i]->join();
            w_.erase(w_.begin() + (std::ptrdiff_t)i);
        } else {
            i++;
        }
    }
}

void Graveyard::join_all()
{
    for (auto &w : w_) {
        w->join();
    }
    w_.clear();
}

double now_ms()
{
    using clock = std::chrono::steady_clock;
    return std::chrono::duration<double, std::milli>(clock::now().time_since_epoch()).count();
}

std::string format(const char *fmt, ...)
{
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = std::vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    if (n < 0) {
        return std::string();
    }
    if ((size_t)n < sizeof buf) {
        return std::string(buf, (size_t)n);
    }
    std::string s((size_t)n + 1, '\0');
    va_start(ap, fmt);
    std::vsnprintf(&s[0], s.size(), fmt, ap);
    va_end(ap);
    s.resize((size_t)n);
    return s;
}

static char lower_ascii(char c)
{
    return (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c;
}

bool iequals(const std::string &a, const std::string &b)
{
    if (a.size() != b.size()) {
        return false;
    }
    for (size_t i = 0; i < a.size(); i++) {
        if (lower_ascii(a[i]) != lower_ascii(b[i])) {
            return false;
        }
    }
    return true;
}

bool ends_with_ci(const std::string &s, const char *suffix)
{
    size_t n = std::strlen(suffix);
    return s.size() >= n && iequals(s.substr(s.size() - n), suffix);
}

std::string to_lower(std::string s)
{
    for (char &c : s) {
        c = lower_ascii(c);
    }
    return s;
}

char path_sep()
{
#ifdef _WIN32
    return '\\';
#else
    return '/';
#endif
}

bool is_sep(char c)
{
#ifdef _WIN32
    return c == '/' || c == '\\';
#else
    return c == '/';
#endif
}

std::string join_path(const std::string &a, const std::string &b)
{
    if (a.empty()) {
        return b;
    }
    if (is_sep(a.back())) {
        return a + b;
    }
    return a + path_sep() + b;
}

std::string parent_dir(const std::string &p)
{
    size_t n = p.size();
    while (n > 0 && is_sep(p[n - 1])) {
        n--;
    }
    while (n > 0 && !is_sep(p[n - 1])) {
        n--;
    }
    while (n > 1 && is_sep(p[n - 1])) {
        n--;
    }
    return p.substr(0, n);
}

std::string base_name(const std::string &p)
{
    size_t n = p.size();
    while (n > 0 && is_sep(p[n - 1])) {
        n--;
    }
    size_t s = n;
    while (s > 0 && !is_sep(p[s - 1])) {
        s--;
    }
    return p.substr(s, n - s);
}

#ifdef _WIN32
std::wstring widen(const std::string &utf8)
{
    if (utf8.empty()) {
        return std::wstring();
    }
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), (int)utf8.size(), nullptr, 0);
    if (n <= 0) {
        return std::wstring();
    }
    std::wstring w((size_t)n, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), (int)utf8.size(), &w[0], n);
    return w;
}

std::string narrow(const std::wstring &w)
{
    if (w.empty()) {
        return std::string();
    }
    int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    if (n <= 0) {
        return std::string();
    }
    std::string s((size_t)n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), &s[0], n, nullptr, nullptr);
    return s;
}
#endif

static std::FILE *open_utf8(const std::string &path, const char *mode)
{
#ifdef _WIN32
    std::wstring w = widen(path);
    if (w.empty()) {
        return nullptr;
    }
    std::wstring m;
    for (const char *q = mode; *q; q++) {
        m.push_back((wchar_t)*q);
    }
    return _wfopen(w.c_str(), m.c_str());
#else
    return std::fopen(path.c_str(), mode);
#endif
}

bool file_exists(const std::string &utf8_path)
{
#ifdef _WIN32
    std::wstring w = widen(utf8_path);
    if (w.empty()) {
        return false;
    }
    DWORD a = GetFileAttributesW(w.c_str());
    return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
#else
    struct stat st;
    return stat(utf8_path.c_str(), &st) == 0 && S_ISREG(st.st_mode);
#endif
}

bool dir_exists(const std::string &utf8_path)
{
#ifdef _WIN32
    std::wstring w = widen(utf8_path);
    if (w.empty()) {
        return false;
    }
    DWORD a = GetFileAttributesW(w.c_str());
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
#else
    struct stat st;
    return stat(utf8_path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
#endif
}

bool make_dirs(const std::string &utf8_dir)
{
    if (utf8_dir.empty() || dir_exists(utf8_dir)) {
        return !utf8_dir.empty();
    }
    std::string up = parent_dir(utf8_dir);
    if (!up.empty() && up != utf8_dir && !dir_exists(up)) {
        if (!make_dirs(up)) {
            return false;
        }
    }
#ifdef _WIN32
    std::wstring w = widen(utf8_dir);
    if (w.empty()) {
        return false;
    }
    return CreateDirectoryW(w.c_str(), nullptr) != 0 || GetLastError() == ERROR_ALREADY_EXISTS;
#else
    return mkdir(utf8_dir.c_str(), 0700) == 0 || errno == EEXIST;
#endif
}

std::vector<std::string> list_subdirs(const std::string &utf8_dir)
{
    std::vector<std::string> out;
#ifdef _WIN32
    std::wstring w = widen(join_path(utf8_dir, "*"));
    if (w.empty()) {
        return out;
    }
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(w.c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE) {
        return out;
    }
    do {
        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !(fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
            std::string n = narrow(fd.cFileName);
            if (n != "." && n != ".." && !n.empty()) {
                out.push_back(n);
            }
        }
    } while (FindNextFileW(h, &fd) && out.size() < 4096);
    FindClose(h);
#else
    DIR *d = opendir(utf8_dir.c_str());
    if (!d) {
        return out;
    }
    while (struct dirent *e = readdir(d)) {
        std::string n = e->d_name;
        if (n == "." || n == ".." || n.empty()) {
            continue;
        }
        if (dir_exists(join_path(utf8_dir, n))) {
            out.push_back(n);
        }
        if (out.size() >= 4096) {
            break;
        }
    }
    closedir(d);
#endif
    return out;
}

bool read_small_file(const std::string &utf8_path, size_t max_bytes, std::string &out, std::string &err)
{
    File f;
    if (!f.open(utf8_path, err)) {
        return false;
    }
    if (f.size() > max_bytes) {
        err = format("file is larger than %u bytes", (unsigned)max_bytes);
        return false;
    }
    out.assign((size_t)f.size(), '\0');
    if (!out.empty() && !f.read_at(0, &out[0], out.size())) {
        err = "read error";
        return false;
    }
    return true;
}

bool write_file_replace(const std::string &utf8_path, const std::string &data, std::string &err)
{
    std::string tmp = utf8_path + ".tmp";
    std::FILE *f = open_utf8(tmp, "wb");
    if (!f) {
        err = "cannot create the file";
        return false;
    }
    bool ok = data.empty() || std::fwrite(data.data(), 1, data.size(), f) == data.size();
    ok = (std::fclose(f) == 0) && ok;
    if (!ok) {
        err = "write error";
        return false;
    }
#ifdef _WIN32
    std::wstring a = widen(tmp), b = widen(utf8_path);
    if (!MoveFileExW(a.c_str(), b.c_str(), MOVEFILE_REPLACE_EXISTING)) {
        err = "cannot replace the file";
        return false;
    }
#else
    if (std::rename(tmp.c_str(), utf8_path.c_str()) != 0) {
        err = "cannot replace the file";
        return false;
    }
#endif
    return true;
}

File::~File()
{
    close();
}

bool File::open(const std::string &utf8_path, std::string &err)
{
    close();
    f_ = open_utf8(utf8_path, "rb");
    if (!f_) {
        err = "cannot open the file";
        return false;
    }
#ifdef _WIN32
    if (_fseeki64(f_, 0, SEEK_END) != 0) {
        close();
        err = "cannot seek";
        return false;
    }
    long long n = _ftelli64(f_);
#else
    if (fseeko(f_, 0, SEEK_END) != 0) {
        close();
        err = "cannot seek";
        return false;
    }
    long long n = (long long)ftello(f_);
#endif
    if (n < 0) {
        close();
        err = "cannot tell the size";
        return false;
    }
    size_ = (uint64_t)n;
    return true;
}

void File::close()
{
    if (f_) {
        std::fclose(f_);
        f_ = nullptr;
    }
    size_ = 0;
}

bool File::read_at(uint64_t offset, void *dst, size_t n)
{
    if (!f_ || offset > size_ || n > size_ - offset) {
        return false;
    }
    if (n == 0) {
        return true;
    }
#ifdef _WIN32
    if (_fseeki64(f_, (long long)offset, SEEK_SET) != 0) {
        return false;
    }
#else
    if (fseeko(f_, (off_t)offset, SEEK_SET) != 0) {
        return false;
    }
#endif
    return std::fread(dst, 1, n, f_) == n;
}

bool valid_utf8(const char *s, size_t n)
{
    const unsigned char *p = (const unsigned char *)s;
    size_t i = 0;
    while (i < n) {
        unsigned c = p[i];
        if (c < 0x80) {
            i++;
            continue;
        }
        size_t len;
        unsigned cp;
        if (c >= 0xC2 && c <= 0xDF) {
            len = 2;
            cp = c & 0x1F;
        } else if (c >= 0xE0 && c <= 0xEF) {
            len = 3;
            cp = c & 0x0F;
        } else if (c >= 0xF0 && c <= 0xF4) {
            len = 4;
            cp = c & 0x07;
        } else {
            return false;
        }
        if (i + len > n) {
            return false;
        }
        for (size_t k = 1; k < len; k++) {
            if ((p[i + k] & 0xC0) != 0x80) {
                return false;
            }
            cp = (cp << 6) | (p[i + k] & 0x3F);
        }
        if ((len == 3 && cp < 0x800) || (len == 4 && (cp < 0x10000 || cp > 0x10FFFF)) || (cp >= 0xD800 && cp <= 0xDFFF)) {
            return false;
        }
        i += len;
    }
    return true;
}

}  // namespace gsa1
