// G-SA1 core: ground types from Garry's Mod's materials (see surfaces.hpp).
#include "surfaces.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <set>

#include "util.hpp"

namespace gsa1 {

namespace {

const size_t kMaxToken = 4096;
const int kMaxDepth = 32;
const size_t kMaxChain = 16;

uint32_t fnv1a(const std::string &s, uint32_t h = 2166136261u)
{
    for (unsigned char c : s) {
        h = (h ^ c) * 16777619u;
    }
    return h;
}

std::string lower(std::string s)
{
    for (char &c : s) {
        if (c >= 'A' && c <= 'Z') {
            c = (char)(c + 32);
        }
    }
    return s;
}

// '\' -> '/', and a run of '/' made one (as Source's file system reads a path)
std::string slashes(const std::string &in)
{
    std::string s;
    s.reserve(in.size());
    for (char c : in) {
        if (c == '\\') {
            c = '/';
        }
        if (c == '/' && !s.empty() && s.back() == '/') {
            continue;
        }
        s += c;
    }
    return s;
}

std::string trim(const std::string &s)
{
    size_t a = 0, b = s.size();
    while (a < b && (unsigned char)s[a] <= ' ') {
        a++;
    }
    while (b > a && (unsigned char)s[b - 1] <= ' ') {
        b--;
    }
    return s.substr(a, b - a);
}

struct Tok {
    enum Kind { End, Str, Open, Close, Cond } kind = End;
    std::string s;
};

// the KeyValues tokenizer
struct Lexer {
    const char *p = nullptr;
    size_t n = 0, i = 0;
    std::string err;

    bool next(Tok &t)
    {
        t.s.clear();
        for (;;) {
            while (i < n && (p[i] == ' ' || p[i] == '\t' || p[i] == '\r' || p[i] == '\n' || p[i] == '\v' || p[i] == '\f' ||
                             (unsigned char)p[i] == 0xEF || (unsigned char)p[i] == 0xBB || (unsigned char)p[i] == 0xBF)) {
                i++;   // white space (and a UTF-8 byte order mark)
            }
            if (i + 1 < n && p[i] == '/' && p[i + 1] == '/') {
                while (i < n && p[i] != '\n') {
                    i++;
                }
                continue;
            }
            break;
        }
        if (i >= n || p[i] == 0) {
            t.kind = Tok::End;
            return true;
        }
        char c = p[i];
        if (c == '{') {
            i++;
            t.kind = Tok::Open;
            return true;
        }
        if (c == '}') {
            i++;
            t.kind = Tok::Close;
            return true;
        }
        if (c == '"') {
            size_t j = i + 1;
            while (j < n && p[j] != '"' && p[j] != 0) {
                j++;
            }
            if (j >= n || p[j] != '"') {
                err = format("an unterminated string at byte %u", (unsigned)i);
                return false;
            }
            if (j - i - 1 > kMaxToken) {
                err = format("a string over %u bytes at byte %u", (unsigned)kMaxToken, (unsigned)i);
                return false;
            }
            t.s.assign(p + i + 1, j - i - 1);
            i = j + 1;
            t.kind = Tok::Str;
            return true;
        }
        if (c == '[') {
            size_t j = i + 1;
            while (j < n && p[j] != ']' && p[j] != '\n' && p[j] != 0) {
                j++;
            }
            if (j >= n || p[j] != ']' || j - i > kMaxToken) {
                err = format("an unterminated condition at byte %u", (unsigned)i);
                return false;
            }
            t.s.assign(p + i, j - i + 1);
            i = j + 1;
            t.kind = Tok::Cond;
            return true;
        }
        size_t j = i;
        while (j < n && p[j] != 0 && p[j] != ' ' && p[j] != '\t' && p[j] != '\r' && p[j] != '\n' && p[j] != '{' &&
               p[j] != '}' && p[j] != '"' && !(p[j] == '/' && j + 1 < n && p[j + 1] == '/')) {
            j++;
        }
        if (j - i > kMaxToken) {
            err = format("a token over %u bytes at byte %u", (unsigned)kMaxToken, (unsigned)i);
            return false;
        }
        t.s.assign(p + i, j - i);
        i = j;
        t.kind = Tok::Str;
        return true;
    }
};

struct Parser {
    Lexer lx;
    size_t nodes = 0, max_nodes = 0;
    Tok look;
    bool have = false;

    bool peek(Tok &t)
    {
        if (!have) {
            if (!lx.next(look)) {
                return false;
            }
            have = true;
        }
        t = look;
        return true;
    }
    bool take(Tok &t)
    {
        if (!peek(t)) {
            return false;
        }
        have = false;
        return true;
    }

    // pairs until '}' (depth > 0) or the end (depth 0)
    bool pairs(std::vector<KvNode> &out, int depth, std::string &err)
    {
        if (depth > kMaxDepth) {
            err = "nested too deep";
            return false;
        }
        Tok t;
        for (;;) {
            if (!take(t)) {
                err = lx.err;
                return false;
            }
            if (t.kind == Tok::End) {
                if (depth > 0) {
                    return true;   // a missing '}' at the end: what was read stands (Source is as lenient)
                }
                return true;
            }
            if (t.kind == Tok::Close) {
                if (depth == 0) {
                    continue;      // a stray '}' at the top level
                }
                return true;
            }
            if (t.kind == Tok::Cond) {
                continue;          // a condition without a key
            }
            if (t.kind == Tok::Open) {
                // an anonymous block: read and dropped
                std::vector<KvNode> tmp;
                if (!pairs(tmp, depth + 1, err)) {
                    return false;
                }
                continue;
            }
            if (++nodes > max_nodes) {
                err = "too many key/value pairs";
                return false;
            }
            KvNode kn;
            kn.key = lower(t.s);
            bool keep = true;
            Tok v;
            if (!take(v)) {
                err = lx.err;
                return false;
            }
            if (v.kind == Tok::Cond) {
                keep = kv_condition(v.s);
                if (!take(v)) {
                    err = lx.err;
                    return false;
                }
            }
            if (v.kind == Tok::Open) {
                kn.block = true;
                if (!pairs(kn.kids, depth + 1, err)) {
                    return false;
                }
            } else if (v.kind == Tok::Str) {
                kn.value = v.s;
                Tok c;
                if (!peek(c)) {
                    err = lx.err;
                    return false;
                }
                if (c.kind == Tok::Cond) {
                    take(c);
                    keep = keep && kv_condition(c.s);
                }
            } else if (v.kind == Tok::End) {
                return true;       // a key without a value at the end
            } else {
                // a key followed by '}': the block ends here
                if (depth > 0) {
                    return true;
                }
                continue;
            }
            if (keep && kn.key.size() && kn.key[0] != '#') {
                out.push_back(std::move(kn));
            }
        }
    }
};

bool cond_atom(std::string a)
{
    a = trim(a);
    bool neg = false;
    while (!a.empty() && a[0] == '!') {
        neg = !neg;
        a = trim(a.substr(1));
    }
    a = lower(a);
    bool v = a == "$win32" || a == "$windows" || a == "$pc" || a == "$win64";
    return neg ? !v : v;
}

void put_kinds(std::map<std::string, uint32_t> &m, std::initializer_list<const char *> names, uint32_t kinds)
{
    for (const char *n : names) {
        m[n] = kinds;
    }
}

}  // namespace

const KvNode *KvNode::find(const char *k) const
{
    for (const KvNode &c : kids) {
        if (c.key == k) {
            return &c;
        }
    }
    return nullptr;
}

bool kv_condition(const std::string &cond)
{
    std::string c = cond;
    if (!c.empty() && c.front() == '[') {
        c.erase(0, 1);
    }
    if (!c.empty() && c.back() == ']') {
        c.pop_back();
    }
    // a || b || c, each a && b
    size_t pos = 0;
    for (;;) {
        size_t bar = c.find("||", pos);
        std::string alt = c.substr(pos, bar == std::string::npos ? std::string::npos : bar - pos);
        bool all = true;
        size_t q = 0;
        for (;;) {
            size_t amp = alt.find("&&", q);
            all = all && cond_atom(alt.substr(q, amp == std::string::npos ? std::string::npos : amp - q));
            if (amp == std::string::npos) {
                break;
            }
            q = amp + 2;
        }
        if (all) {
            return true;
        }
        if (bar == std::string::npos) {
            return false;
        }
        pos = bar + 2;
    }
}

bool kv_parse(const char *p, size_t n, std::vector<KvNode> &out, std::string &err, size_t max_nodes)
{
    out.clear();
    if (!p && n) {
        err = "no text";
        return false;
    }
    Parser ps;
    ps.lx.p = p;
    ps.lx.n = n;
    ps.max_nodes = max_nodes;
    if (!ps.pairs(out, 0, err)) {
        out.clear();
        if (err.empty()) {
            err = "a parse error";
        }
        return false;
    }
    return true;
}

// ---- materials ---------------------------------------------------------------------------------------------------------
bool parse_vmt(const char *p, size_t n, VmtInfo &out, std::string &err)
{
    out = VmtInfo();
    std::vector<KvNode> root;
    if (!kv_parse(p, n, root, err, 20000)) {
        return false;
    }
    const KvNode *m = nullptr;
    for (const KvNode &k : root) {
        if (k.block) {
            m = &k;
            break;
        }
    }
    if (!m) {
        err = "no shader block";
        return false;
    }
    out.shader = m->key;
    auto lowv = [](const KvNode &k) { return lower(trim(k.value)); };
    for (const KvNode &k : m->kids) {
        if (k.block) {
            if (k.key == "insert" || k.key == "replace") {
                bool ins = k.key == "insert";
                for (const KvNode &q : k.kids) {
                    if (q.block) {
                        continue;
                    }
                    if (q.key == "$surfaceprop") {
                        (ins ? out.ins_sp : out.rep_sp) = true;
                        (ins ? out.ins_sp_v : out.rep_sp_v) = lowv(q);
                    } else if (q.key == "$surfaceprop2") {
                        (ins ? out.ins_sp2 : out.rep_sp2) = true;
                        (ins ? out.ins_sp2_v : out.rep_sp2_v) = lowv(q);
                    }
                }
            }
            continue;
        }
        if (k.key == "$surfaceprop") {
            out.has_sp = true;
            out.sp = lowv(k);
        } else if (k.key == "$surfaceprop2") {
            out.has_sp2 = true;
            out.sp2 = lowv(k);
        } else if (k.key == "include" && out.shader == "patch") {
            out.include = vmt_path(trim(k.value));
        }
    }
    if (out.has_sp && out.sp.empty()) {
        out.has_sp = false;
    }
    if (out.has_sp2 && out.sp2.empty()) {
        out.has_sp2 = false;
    }
    return true;
}

std::string vmt_path(const std::string &in)
{
    std::string s = slashes(lower(trim(in)));
    if (!s.empty() && s[0] == '/') {
        return std::string();   // absolute
    }
    if (s.empty() || s.size() > 200 || s.find("..") != std::string::npos || s.find(':') != std::string::npos) {
        return std::string();
    }
    for (char c : s) {
        if ((unsigned char)c < 0x20 || (unsigned char)c > 0x7E) {
            return std::string();
        }
    }
    if (s.compare(0, 10, "materials/") != 0) {
        s = "materials/" + s;
    }
    if (s.size() < 4 || s.compare(s.size() - 4, 4, ".vmt") != 0) {
        s += ".vmt";
    }
    if (s.size() <= 14) {
        return std::string();   // "materials/.vmt"
    }
    return s;
}

VmtSurface resolve_vmt(const std::string &path, const std::function<const VmtInfo *(const std::string &)> &lookup,
                       int max_depth)
{
    VmtSurface r;
    const VmtInfo *v = path.empty() ? nullptr : lookup(path);
    if (!v) {
        return r;
    }
    r.found = true;
    if (v->shader == "patch") {
        r.patched = true;
        VmtSurface base;
        if (v->include.empty() || max_depth <= 0) {
            r.include_missing = true;
        } else {
            base = resolve_vmt(v->include, lookup, max_depth - 1);
            if (!base.found || base.include_missing) {
                r.include_missing = true;
            }
        }
        r.sp = base.sp;
        r.sp2 = base.sp2;
        r.explicit_sp = base.explicit_sp;
        r.explicit_sp2 = base.explicit_sp2;
        // parameters written straight into a patch are treated like insert (G-SA1's choice; not standard)
        if (v->has_sp) {
            r.sp = v->sp;
            r.explicit_sp = true;
        }
        if (v->has_sp2) {
            r.sp2 = v->sp2;
            r.explicit_sp2 = true;
        }
        if (v->ins_sp && !v->ins_sp_v.empty()) {
            r.sp = v->ins_sp_v;
            r.explicit_sp = true;
        }
        if (v->ins_sp2 && !v->ins_sp2_v.empty()) {
            r.sp2 = v->ins_sp2_v;
            r.explicit_sp2 = true;
        }
        if (v->rep_sp && !v->rep_sp_v.empty() && base.explicit_sp) {
            r.sp = v->rep_sp_v;
        }
        if (v->rep_sp2 && !v->rep_sp2_v.empty() && base.explicit_sp2) {
            r.sp2 = v->rep_sp2_v;
        }
        return r;
    }
    if (v->has_sp) {
        r.sp = v->sp;
        r.explicit_sp = true;
    }
    if (v->has_sp2) {
        r.sp2 = v->sp2;
        r.explicit_sp2 = true;
    }
    return r;
}

// ---- surface types -------------------------------------------------------------------------------------------------
const std::string &SurfaceType::name() const
{
    static const std::string none;
    return chain.empty() ? none : chain[0];
}

bool SurfacePropDb::add_script(const char *p, size_t n, std::string &err)
{
    std::vector<KvNode> root;
    if (!kv_parse(p, n, root, err, 50000)) {
        return false;
    }
    for (const KvNode &k : root) {
        if (!k.block) {
            continue;
        }
        std::string name = lower(trim(k.key));
        if (!valid_surface_name(name) || e_.count(name) || order_.size() >= 8000) {
            continue;
        }
        Entry e;
        for (const KvNode &q : k.kids) {
            if (q.block) {
                continue;
            }
            if (q.key == "base") {
                std::string b = lower(trim(q.value));
                if (valid_surface_name(b)) {
                    e.base = b;
                }
            } else if (q.key == "gamematerial") {
                std::string g = trim(q.value);
                if (g.size() == 1) {
                    char c = g[0];
                    e.letter = (c >= 'a' && c <= 'z') ? (char)(c - 32) : c;
                } else if (!g.empty() && g.size() <= 3 && std::all_of(g.begin(), g.end(), [](char c) {
                               return c >= '0' && c <= '9';
                           })) {
                    int v = std::atoi(g.c_str());
                    e.letter = (v > 32 && v < 127) ? (char)v : 0;
                }
            }
        }
        e_[name] = e;
        order_.push_back(name);
    }
    return true;
}

bool SurfacePropDb::parse_manifest(const char *p, size_t n, std::vector<std::string> &files, std::string &err)
{
    files.clear();
    std::vector<KvNode> root;
    if (!kv_parse(p, n, root, err, 5000)) {
        return false;
    }
    std::set<std::string> seen;
    for (const KvNode &k : root) {
        if (!k.block) {
            continue;
        }
        for (const KvNode &q : k.kids) {
            if (q.block || q.key != "file") {
                continue;
            }
            std::string f = slashes(lower(trim(q.value)));
            bool ok = !f.empty() && f.size() <= 128 && f.find("..") == std::string::npos && f.find(':') == std::string::npos &&
                      f[0] != '/' && f.compare(0, 8, "scripts/") == 0;
            for (char c : f) {
                ok = ok && (unsigned char)c >= 0x20 && (unsigned char)c <= 0x7E;
            }
            if (ok && seen.insert(f).second && files.size() < 64) {
                files.push_back(f);
            }
        }
        break;
    }
    return true;
}

SurfaceType SurfacePropDb::resolve(const std::string &name) const
{
    SurfaceType t;
    std::string n = name;
    while (!n.empty() && t.chain.size() < kMaxChain) {
        if (std::find(t.chain.begin(), t.chain.end(), n) != t.chain.end()) {
            break;   // a loop in the bases
        }
        t.chain.push_back(n);
        auto it = e_.find(n);
        if (it == e_.end()) {
            break;
        }
        if (!t.letter && it->second.letter) {
            t.letter = it->second.letter;
        }
        n = it->second.base;
    }
    if (!t.letter && e_.count(name) && name != "default") {
        auto d = e_.find("default");
        if (d != e_.end()) {
            t.letter = d->second.letter;   // Source copies "default" into a type without a base
        }
    }
    if (t.chain.empty()) {
        t.chain.push_back(name);
    }
    return t;
}

// ---- the class table -------------------------------------------------------------------------------------------------
static const KindInfo kKinds[kKindCount] = {
    {kKindDig, "dig", SA1_SURFACE_DIG},
    {kKindSlippery, "slippery", SA1_SURFACE_SLIPPERY},
    {kKindSand, "sand", SA1_SURFACE_SAND},
    {kKindHurt, "hurt", SA1_SURFACE_HURT},
    {kKindNoClimb, "noclimb", SA1_SURFACE_NO_CLIMB},
    {kKindSnow, "snow", SA1_SURFACE_SNOW},
    {kKindFast, "fast", SA1_SURFACE_BOOST},
    {kKindSlide, "slide", SA1_SURFACE_SLIDE},
    {kKindSpeedPath, "speedpath", SA1_SURFACE_SPEED_PATH},
    {kKindStairs, "stairs", SA1_SURFACE_STAIRS},
    {kKindNoLand, "noland", SA1_SURFACE_NO_LAND},
    {kKindWallSlide, "wallslide", SA1_SURFACE_WALL_SLIDE},
    {kKindFootprints, "footprints", SA1_SURFACE_FOOTPRINTS},
};

const KindInfo *kind_table()
{
    return kKinds;
}

bool parse_kinds(const std::string &s, uint32_t &out)
{
    static const struct {
        const char *alias, *word;
    } aliases[] = {{"diggable", "dig"},      {"ice", "slippery"},        {"hurts", "hurt"},
                   {"no_climb", "noclimb"},  {"boost", "fast"},          {"sliding", "slide"},
                   {"speed_path", "speedpath"}, {"speedtrack", "speedpath"}, {"stair", "stairs"},
                   {"no_land", "noland"},    {"wall_slide", "wallslide"}, {"footprint", "footprints"}};
    out = 0;
    std::string w;
    std::string t = lower(s) + ",";
    for (char c : t) {
        if (c == ',' || c == ' ' || c == '+' || c == '|') {
            if (w.empty()) {
                continue;
            }
            for (const auto &a : aliases) {
                if (w == a.alias) {
                    w = a.word;
                    break;
                }
            }
            bool known = w == "normal" || w == "plain" || w == "none";
            for (const KindInfo &k : kKinds) {
                if (w == k.word) {
                    out |= k.kind;
                    known = true;
                    break;
                }
            }
            if (!known) {
                return false;
            }
            w.clear();
        } else {
            w += c;
        }
    }
    return true;
}

std::string kinds_string(uint32_t k)
{
    std::string s;
    for (const KindInfo &n : kKinds) {
        if (k & n.kind) {
            s += (s.empty() ? "" : ",");
            s += n.word;
        }
    }
    return s.empty() ? std::string("normal") : s;
}

uint32_t kinds_surface(uint32_t k)
{
    uint32_t s = 0;
    for (const KindInfo &n : kKinds) {
        if (k & n.kind) {
            s |= n.surface;
        }
    }
    return s;
}

bool valid_surface_name(const std::string &n)
{
    if (n.empty() || n.size() > 64) {
        return false;
    }
    for (char c : n) {
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == ' ')) {
            return false;
        }
    }
    return true;
}

SurfaceTable SurfaceTable::defaults()
{
    SurfaceTable t;
    put_kinds(t.names, {"dirt", "grass", "mud", "sand", "gravel", "snow", "quicksand", "antlionsand"}, kKindDig);
    put_kinds(t.names, {"ice", "gmod_ice", "slipperyslime", "slipperymetal", "friction_00", "friction_10", "frictionm_00",
                        "frictionm_10"},
              kKindSlippery);
    put_kinds(t.names, {"carpet", "plaster", "cardboard", "paper", "papercup", "ceiling_tile", "rubber", "floatingstandable",
                        "foliage", "rock"},
              0u);
    for (char c : {'D', 'N', 'U', 'J'}) {
        t.letters[c] = kKindDig;
    }
    return t;
}

uint32_t SurfaceTable::kinds_of(const SurfaceType &t, std::string *how) const
{
    for (size_t i = 0; i < t.chain.size(); i++) {
        auto it = names.find(t.chain[i]);
        if (it != names.end()) {
            if (how) {
                *how = i == 0 ? std::string("listed") : "base " + t.chain[i];
            }
            return it->second & kKindsAll;
        }
    }
    if (t.letter) {
        auto it = letters.find(t.letter);
        if (it != letters.end()) {
            if (how) {
                *how = std::string("letter ") + t.letter;
            }
            return it->second & kKindsAll;
        }
    }
    if (how) {
        how->clear();
    }
    return 0;
}

uint32_t SurfaceTable::hash() const
{
    uint32_t h = 2166136261u;
    for (const auto &kv : names) {
        h = fnv1a(kv.first + "=" + std::to_string(kv.second & kKindsAll) + ";", h);
    }
    for (const auto &kv : letters) {
        h = fnv1a(std::string("#") + kv.first + "=" + std::to_string(kv.second & kKindsAll) + ";", h);
    }
    return h;
}

uint32_t SurfaceSettings::hash() const
{
    uint32_t h = table.hash();
    h = fnv1a(format("enabled %d; anywhere %d", (int)enabled, (int)dig_anywhere), h);
    return h;
}

void apply_surface_classes(std::vector<sa1_collision_tri> &world, const std::vector<uint32_t> &tags,
                           const std::vector<SurfaceType> &types, const SurfaceSettings &s, SurfaceSummary &out)
{
    double t0 = now_ms();
    out = SurfaceSummary();
    out.enabled = s.enabled;
    out.dig_anywhere = s.dig_anywhere;
    out.hash = s.hash();
    out.overrides = s.overrides;
    out.types.resize(types.size());
    std::vector<uint32_t> bits(types.size(), 0), extra(types.size(), 0);
    for (size_t i = 0; i < types.size(); i++) {
        out.types[i].kinds = s.table.kinds_of(types[i], &out.types[i].how);
        if (s.enabled) {
            bits[i] = kinds_surface(out.types[i].kinds);
            extra[i] = kinds_surface(out.types[i].kinds & kKindsSecondSlot);
        }
    }
    const uint32_t wall_only = kinds_surface(kKindsWallOnly);
    const bool tagged = tags.size() == world.size();
    for (size_t i = 0; i < world.size(); i++) {
        sa1_collision_tri &t = world[i];
        bool kill_only = (t.surface & SA1_SURFACE_KILL) && !(t.surface & SA1_SURFACE_SOLID);
        if ((t.surface & (SA1_SURFACE_WATER | SA1_SURFACE_HEAVY_WATER)) || kill_only) {
            continue;   // water surfaces and the kill plane: never classed
        }
        // the triangle's orientation (Source space, z up; front side counter-clockwise): a floor has n.z >= 0.7 (the
        // walkable test of the statistics); a double-sided triangle is a floor from its back too (n.z <= -0.7)
        double e1[3], e2[3];
        for (int k = 0; k < 3; k++) {
            e1[k] = (double)t.v[1][k] - t.v[0][k];
            e2[k] = (double)t.v[2][k] - t.v[0][k];
        }
        double nx = e1[1] * e2[2] - e1[2] * e2[1], ny = e1[2] * e2[0] - e1[0] * e2[2], nz = e1[0] * e2[1] - e1[1] * e2[0];
        double l = std::sqrt(nx * nx + ny * ny + nz * nz);
        double area = 0.5 * l;
        const double z = l > 0.0 ? nz / l : 0.0;
        const bool is_floor = l > 0.0 && (z >= 0.7 || ((t.surface & SA1_SURFACE_DOUBLE_SIDED) && z <= -0.7));
        uint32_t tag = tagged ? tags[i] : kNoSurfaceTag;
        uint32_t p = tag & 0xFFFFu, q = tag >> 16;
        const bool hidden = q == kHiddenSurface;   // never drawn (nodraw, sky, clip): no ground for the statistics
        uint32_t add = 0;
        if (p < types.size()) {
            add |= bits[p];
        }
        if (q < types.size()) {
            add |= extra[q];
        }
        if (is_floor && (add & wall_only)) {
            add &= ~wall_only;   // "not a floor" / "slide-off wall" on a floor: a trap (Review C3) - walls only
            out.wall_only_floors++;
        }
        if (s.dig_anywhere) {
            add |= SA1_SURFACE_DIG;
        }
        t.surface |= add;
        // the statistics: the area of walkable land per type and per kind
        bool walk = !hidden && l > 0.0 && z >= 0.7;
        out.tris++;
        if (p >= types.size()) {
            out.tris_untagged++;
        } else {
            out.types[p].tris++;
            if (walk) {
                out.types[p].area += area;
            }
        }
        if (add) {
            out.tris_classed++;
        }
        if (add & SA1_SURFACE_DIG) {
            out.tris_dig++;
        }
        if (add & SA1_SURFACE_SLIPPERY) {
            out.tris_slippery++;
        }
        const uint32_t all = t.surface;
        for (unsigned k = 0; k < kKindCount; k++) {
            if (!(all & kKinds[k].surface)) {
                continue;
            }
            out.kind_tris[k]++;
            if (walk) {
                out.kind_area[k] += area;
            } else if (!hidden && l > 0.0) {
                out.kind_wall[k] += area;
            }
        }
        if (walk) {
            out.walkable += area;
            if (all & SA1_SURFACE_DIG) out.dig += area;
            if (all & SA1_SURFACE_SLIPPERY) out.slippery += area;
            if (all & SA1_SURFACE_SAND) out.sand += area;
            if (all & SA1_SURFACE_HURT) out.hurt += area;
            if (all & SA1_SURFACE_NO_CLIMB) out.noclimb += area;
        } else if (!hidden && l > 0.0) {
            out.wall += area;
        }
    }
    out.ms = now_ms() - t0;
}

// ---- moving objects ----------------------------------------------------------------------------------------------------
uint32_t surface_col(uint32_t surface)
{
    static const uint32_t map[][2] = {
        {SA1_SURFACE_SOLID, 0x1u},       {SA1_SURFACE_WATER, 0x2u},       {SA1_SURFACE_NO_CLIMB, 0x1000u},
        {SA1_SURFACE_HURT, 0x10000u},    {SA1_SURFACE_SLIPPERY, 0x4u},    {SA1_SURFACE_HEAVY_WATER, 0x400000u},
        {SA1_SURFACE_SAND, 0x10u},       {SA1_SURFACE_BOOST, 0x80u},      {SA1_SURFACE_SLIDE, 0x20000u},
        {SA1_SURFACE_STAIRS, 0x4000u},   {SA1_SURFACE_NO_LAND, 0x40u},    {SA1_SURFACE_WALL_SLIDE, 0x200000u},
        {SA1_SURFACE_DIG, 0x100u},
        // round 0.9.2 (libsa1's sa1ca_surface_to_col; gsa1_090_surfaces.md Review C4: without them two words that differ
        // only in these bits counted as one, and an object libsa1 refuses passed the 4-word cap)
        {SA1_SURFACE_SNOW, 0x8u},        {SA1_SURFACE_SPEED_PATH, 0x800000u}, {SA1_SURFACE_FOOTPRINTS, 0x100000u},
    };
    uint32_t col = 0;
    for (const auto &m : map) {
        if (surface & m[0]) {
            col |= m[1];
        }
    }
    if (!(surface & (SA1_SURFACE_SOLID | SA1_SURFACE_WATER | SA1_SURFACE_HEAVY_WATER | SA1_SURFACE_KILL))) {
        col |= 0x1u;
    }
    return col;
}

namespace {

uint32_t count_words(const std::vector<sa1_collision_tri> &tris)
{
    std::vector<uint32_t> cols;
    for (const sa1_collision_tri &t : tris) {
        uint32_t c = surface_col(t.surface);
        if (!(c & 0x400003u)) {
            continue;   // not collidable (libsa1's SA1CA_COL_COLLIDABLE)
        }
        if (std::find(cols.begin(), cols.end(), c) == cols.end()) {
            cols.push_back(c);
        }
    }
    return (uint32_t)cols.size();
}

}  // namespace

uint32_t cap_object_words(std::vector<sa1_collision_tri> &tris, uint32_t droppable, uint32_t max_words)
{
    uint32_t removed = 0;
    for (sa1_collision_tri &t : tris) {
        if (t.surface & SA1_SURFACE_DIG) {
            t.surface &= ~SA1_SURFACE_DIG;
            removed |= SA1_SURFACE_DIG;
        }
    }
    droppable &= ~SA1_SURFACE_DIG;
    if (!droppable || count_words(tris) <= max_words) {
        return removed;
    }
    for (sa1_collision_tri &t : tris) {
        if (t.surface & droppable) {
            removed |= t.surface & droppable;
            t.surface &= ~droppable;
        }
    }
    return removed;
}

bool shape_from_phy_classed(const PhyModel &m, const std::vector<uint32_t> &solid_bits, Shape &out, std::string &err,
                            float thin_wall_max, uint32_t *capped)
{
    std::vector<ConvexSolid> solids;
    uint32_t droppable = 0;
    for (size_t h = 0; h < m.hulls.size(); h++) {
        ConvexSolid cs;
        cs.tris = m.hulls[h];
        uint32_t si = h < m.hull_solid.size() ? m.hull_solid[h] : 0u;
        uint32_t bits = si < solid_bits.size() ? solid_bits[si] & kClassSurfaceBits & ~kMoverNeverSurfaceBits : 0u;
        cs.surface = SA1_SURFACE_SOLID | bits;
        droppable |= bits;
        solids.push_back(std::move(cs));
    }
    std::vector<sa1_collision_tri> tris;
    BspWorldStats st;
    if (!clean_solids(solids, mover_options(thin_wall_max), tris, st, err)) {
        return false;
    }
    if (tris.empty()) {
        err = "the physics model left no collision";
        return false;
    }
    make_shape(tris, out);
    for (ShapeChunk &c : out.chunks) {
        if (cap_object_words(c.tris, droppable) & droppable) {
            if (capped) {
                (*capped)++;
            }
        }
    }
    return true;
}

}  // namespace gsa1
