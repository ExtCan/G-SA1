// gamefs.hpp - an offline stand-in for Garry's Mod's own file system (the GAME path) for the tests and tools: the
// model files a map's static props and entities need (models/*.phy, the first bytes of *.mdl), the materials (.vmt) and
// scripts the surface types need (0.8), looked up in the map's pak lump (a zip), mounted workshop GMAs (add_gma:
// garrysmod/cache/workshop/<id>.gma, uncompressed), garrysmod/addons/*/, garrysmod/ and the game's VPKs
// (garrysmod/garrysmod_dir.vpk, sourceengine/*_dir.vpk). Read-only; nothing is extracted to disk. In Garry's Mod the
// addon reads the same files with file.Open(path, "rb", "GAME") and hands their bytes to the module.
#pragma once

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "bsp.hpp"
#include "util.hpp"

namespace gamefs {

inline std::string lower(std::string s)
{
    for (char &c : s) {
        if (c >= 'A' && c <= 'Z') {
            c = (char)(c + 32);
        }
        if (c == '\\') {
            c = '/';
        }
    }
    return s;
}

inline bool read_range(const std::string &path, uint64_t ofs, size_t n, std::string &out)
{
    gsa1::File f;
    std::string e;
    if (!f.open(path, e)) {
        return false;
    }
    out.resize(n);
    return n == 0 || f.read_at(ofs, &out[0], n);
}

struct Vpk {
    struct Entry {
        uint16_t archive;
        uint32_t offset, length;
        std::string preload;
    };
    std::string dir_path;
    uint64_t base = 0;
    std::map<std::string, Entry> entries;

    bool load(const std::string &path)
    {
        std::string d;
        gsa1::File f;
        std::string e;
        if (!f.open(path, e) || f.size() < 12 || f.size() > (256u << 20)) {
            return false;
        }
        d.resize((size_t)f.size());
        if (!f.read_at(0, &d[0], d.size())) {
            return false;
        }
        uint32_t sig, ver, tree;
        std::memcpy(&sig, d.data(), 4);
        std::memcpy(&ver, d.data() + 4, 4);
        std::memcpy(&tree, d.data() + 8, 4);
        if (sig != 0x55AA1234u || (ver != 1 && ver != 2)) {
            return false;
        }
        size_t hs = ver == 1 ? 12 : 28, p = hs;
        base = hs + tree;
        auto cstr = [&](std::string &s) {
            size_t q = d.find('\0', p);
            if (q == std::string::npos) {
                return false;
            }
            s.assign(d, p, q - p);
            p = q + 1;
            return true;
        };
        std::string ext, dir, name;
        while (cstr(ext) && !ext.empty()) {
            while (cstr(dir) && !dir.empty()) {
                while (cstr(name) && !name.empty()) {
                    if (p + 18 > d.size()) {
                        return false;
                    }
                    Entry en;
                    uint16_t pre;
                    std::memcpy(&pre, d.data() + p + 4, 2);
                    std::memcpy(&en.archive, d.data() + p + 6, 2);
                    std::memcpy(&en.offset, d.data() + p + 8, 4);
                    std::memcpy(&en.length, d.data() + p + 12, 4);
                    p += 18;
                    if (p + pre > d.size()) {
                        return false;
                    }
                    en.preload.assign(d, p, pre);
                    p += pre;
                    std::string full = (dir == " " ? std::string() : dir + "/") + name + "." + ext;
                    entries[lower(full)] = std::move(en);
                }
            }
        }
        dir_path = path;
        return true;
    }

    bool read(const std::string &name, std::string &out, uint32_t max) const
    {
        auto it = entries.find(name);
        if (it == entries.end()) {
            return false;
        }
        const Entry &en = it->second;
        std::string body;
        size_t want = en.length;
        if (max && en.preload.size() + want > max) {
            want = max > en.preload.size() ? max - en.preload.size() : 0;
        }
        if (want) {
            std::string ap = dir_path;
            uint64_t ofs = en.offset;
            if (en.archive == 0x7FFF) {
                ofs += base;
            } else {
                char num[16];
                std::snprintf(num, sizeof num, "_%03u.vpk", (unsigned)en.archive);
                ap = dir_path.substr(0, dir_path.size() - 8) + num;   // "_dir.vpk" -> "_NNN.vpk"
            }
            if (!read_range(ap, ofs, want, body)) {
                return false;
            }
        }
        out = en.preload + body;
        if (max && out.size() > max) {
            out.resize(max);
        }
        return true;
    }
};

// a zip of stored (uncompressed) entries: a map's pak lump
struct Zip {
    struct Entry {
        uint32_t ofs, size;
        uint16_t method;
    };
    std::string data;
    std::map<std::string, Entry> entries;

    bool load(std::string bytes)
    {
        data.swap(bytes);
        entries.clear();
        if (data.size() < 22) {
            return false;
        }
        size_t lo = data.size() > 65557 ? data.size() - 65557 : 0;
        size_t eocd = std::string::npos;
        for (size_t i = data.size() - 22 + 1; i-- > lo;) {
            if (std::memcmp(data.data() + i, "PK\x05\x06", 4) == 0) {
                eocd = i;
                break;
            }
        }
        if (eocd == std::string::npos) {
            return false;
        }
        uint16_t n;
        uint32_t cd_size, cd_ofs;
        std::memcpy(&n, data.data() + eocd + 10, 2);
        std::memcpy(&cd_size, data.data() + eocd + 12, 4);
        std::memcpy(&cd_ofs, data.data() + eocd + 16, 4);
        size_t p = cd_ofs;
        for (uint16_t i = 0; i < n; i++) {
            if (p + 46 > data.size() || std::memcmp(data.data() + p, "PK\x01\x02", 4) != 0) {
                return false;
            }
            uint16_t method, nl, el, cl;
            uint32_t csize, lofs;
            std::memcpy(&method, data.data() + p + 10, 2);
            std::memcpy(&csize, data.data() + p + 20, 4);
            std::memcpy(&nl, data.data() + p + 28, 2);
            std::memcpy(&el, data.data() + p + 30, 2);
            std::memcpy(&cl, data.data() + p + 32, 2);
            std::memcpy(&lofs, data.data() + p + 42, 4);
            if (p + 46 + nl > data.size()) {
                return false;
            }
            std::string name = lower(data.substr(p + 46, nl));
            p += 46u + nl + el + cl;
            if (lofs + 30u > data.size() || std::memcmp(data.data() + lofs, "PK\x03\x04", 4) != 0) {
                continue;
            }
            uint16_t lnl, lel;
            std::memcpy(&lnl, data.data() + lofs + 26, 2);
            std::memcpy(&lel, data.data() + lofs + 28, 2);
            Entry en{(uint32_t)(lofs + 30u + lnl + lel), csize, method};
            if ((uint64_t)en.ofs + en.size <= data.size()) {
                entries[name] = en;
            }
        }
        return true;
    }

    bool read(const std::string &name, std::string &out, uint32_t max) const
    {
        auto it = entries.find(name);
        if (it == entries.end() || it->second.method != 0) {
            return false;
        }
        size_t n = it->second.size;
        if (max && n > max) {
            n = max;
        }
        out.assign(data, it->second.ofs, n);
        return true;
    }
};

// a workshop addon (.gma, "GMAD" versions 1-3, not compressed): its file table; the files are read on demand
struct Gma {
    std::string path;
    std::map<std::string, std::pair<uint64_t, uint64_t>> entries;   // name -> (offset, size) in the file

    bool load(const std::string &p)
    {
        entries.clear();
        gsa1::File f;
        std::string e, d;
        if (!f.open(p, e) || f.size() < 32) {
            return false;
        }
        size_t n = (size_t)std::min<uint64_t>(f.size(), 8u << 20);
        if (!read_range(p, 0, n, d) || d.compare(0, 4, "GMAD") != 0) {
            return false;
        }
        uint8_t ver = (uint8_t)d[4];
        size_t i = 4 + 1 + 8 + 8;
        auto cstr = [&](std::string &out) {
            size_t q = d.find('\0', i);
            if (q == std::string::npos) {
                return false;
            }
            out.assign(d, i, q - i);
            i = q + 1;
            return true;
        };
        std::string str;
        if (ver > 1) {
            do {
                if (!cstr(str)) {
                    return false;
                }
            } while (!str.empty());   // required content
        }
        for (int k = 0; k < 3; k++) {
            if (!cstr(str)) {   // name, description, author
                return false;
            }
        }
        i += 4;   // addon version
        std::vector<std::pair<std::string, uint64_t>> list;
        for (;;) {
            if (i + 4 > d.size()) {
                return false;
            }
            uint32_t num;
            std::memcpy(&num, d.data() + i, 4);
            i += 4;
            if (num == 0) {
                break;
            }
            std::string name;
            if (!cstr(name) || i + 12 > d.size()) {
                return false;
            }
            int64_t size;
            std::memcpy(&size, d.data() + i, 8);
            i += 12;   // size, crc
            if (size < 0) {
                return false;
            }
            list.push_back({lower(name), (uint64_t)size});
        }
        uint64_t ofs = i;
        for (const auto &it : list) {
            if (ofs + it.second > f.size()) {
                return false;
            }
            entries[it.first] = {ofs, it.second};
            ofs += it.second;
        }
        path = p;
        return true;
    }

    bool range(const std::string &name, uint64_t &ofs, uint64_t &len) const
    {
        auto it = entries.find(lower(name));
        if (it == entries.end()) {
            return false;
        }
        ofs = it->second.first;
        len = it->second.second;
        return true;
    }

    bool read(const std::string &name, std::string &out, uint32_t max) const
    {
        uint64_t o, l;
        if (!range(name, o, l)) {
            return false;
        }
        if (max && l > max) {
            l = max;
        }
        return l < (256u << 20) && read_range(path, o, (size_t)l, out);
    }
};

class GameFs {
public:
    explicit GameFs(const std::string &garrysmod_dir) : gm_(garrysmod_dir)
    {
        for (const std::string &a : gsa1::list_subdirs(gsa1::join_path(gm_, "addons"))) {
            addons_.push_back(gsa1::join_path(gsa1::join_path(gm_, "addons"), a));
        }
        std::vector<std::string> dirs = {gsa1::join_path(gm_, "garrysmod_dir.vpk")};
        std::string se = gsa1::join_path(gsa1::parent_dir(gm_), "sourceengine");
        for (const char *n : {"hl2_misc_dir.vpk", "content_hl2_dir.vpk", "content_cstrike_dir.vpk",
                              "hl2_textures_dir.vpk", "fallbacks_dir.vpk"}) {
            dirs.push_back(gsa1::join_path(se, n));
        }
        for (const std::string &d : dirs) {
            std::unique_ptr<Vpk> v(new Vpk());
            if (v->load(d)) {
                vpks_.push_back(std::move(v));
            }
        }
    }

    // the map's pak lump (lump 40); base: where the map starts in the file (a map inside a GMA)
    void set_map(const std::string &bsp_path, uint64_t base = 0)
    {
        pak_ = Zip();
        gsa1::File f;
        std::string e;
        if (!f.open(bsp_path, e) || f.size() < base + 1036) {
            return;
        }
        uint8_t h[1036];
        if (!f.read_at(base, h, sizeof h)) {
            return;
        }
        int32_t ofs, len;
        std::memcpy(&ofs, h + 8 + 16 * 40, 4);
        std::memcpy(&len, h + 8 + 16 * 40 + 4, 4);
        std::string b;
        if (ofs > 0 && len > 22 && base + (uint64_t)ofs + (uint64_t)len <= f.size() &&
            read_range(bsp_path, base + (uint64_t)ofs, (size_t)len, b)) {
            pak_.load(std::move(b));
        }
    }

    // a workshop addon's files (searched after the map's pak, before addons/ and the VPKs)
    bool add_gma(const std::string &path)
    {
        std::unique_ptr<Gma> g(new Gma());
        if (!g->load(path)) {
            return false;
        }
        gmas_.push_back(std::move(g));
        return true;
    }

    bool read(const std::string &path, std::string &out, uint32_t max = 0)
    {
        std::string p = lower(path);
        if (pak_.read(p, out, max)) {
            return true;
        }
        for (const auto &g : gmas_) {
            if (g->read(p, out, max)) {
                return true;
            }
        }
        for (const std::string &a : addons_) {
            std::string fp = gsa1::join_path(a, p);
            if (gsa1::file_exists(fp)) {
                gsa1::File f;
                std::string e;
                if (f.open(fp, e)) {
                    size_t n = (size_t)f.size();
                    if (max && n > max) {
                        n = max;
                    }
                    return read_range(fp, 0, n, out);
                }
            }
        }
        std::string fp = gsa1::join_path(gm_, p);
        if (gsa1::file_exists(fp)) {
            gsa1::File f;
            std::string e;
            if (f.open(fp, e)) {
                size_t n = (size_t)f.size();
                if (max && n > max) {
                    n = max;
                }
                return read_range(fp, 0, n, out);
            }
        }
        for (const auto &v : vpks_) {
            if (v->read(p, out, max)) {
                return true;
            }
        }
        return false;
    }

    size_t vpks() const { return vpks_.size(); }
    size_t pak_files() const { return pak_.entries.size(); }

private:
    std::string gm_;
    std::vector<std::string> addons_;
    std::vector<std::unique_ptr<Vpk>> vpks_;
    std::vector<std::unique_ptr<Gma>> gmas_;
    Zip pak_;
};

}  // namespace gamefs
