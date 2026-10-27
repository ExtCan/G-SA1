// G-SA1 core: .phy / .mdl header parsing (see phy.hpp).
#include "phy.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <utility>

#include "surfaces.hpp"
#include "util.hpp"

namespace gsa1 {

namespace {

const double kInchPerMetre = 1.0 / 0.0254;

int32_t rd_i32(const uint8_t *p)
{
    int32_t v;
    std::memcpy(&v, p, 4);
    return v;
}

uint32_t rd_u32(const uint8_t *p)
{
    uint32_t v;
    std::memcpy(&v, p, 4);
    return v;
}

int16_t rd_i16(const uint8_t *p)
{
    int16_t v;
    std::memcpy(&v, p, 2);
    return v;
}

// the convex pieces of one IVP compact surface [s, end) (end: the solid's end), appended to out
bool parse_surface(const uint8_t *s, const uint8_t *end, PhyModel &out, std::string &err)
{
    const size_t kHeader = 48, kNode = 28, kLedge = 16, kTri = 16, kPoint = 16;
    if ((size_t)(end - s) < kHeader) {
        err = "a physics solid is too short";
        return false;
    }
    uint32_t byte_size = rd_u32(s + 28) >> 8;
    const uint8_t *se = end;
    if (byte_size >= kHeader && byte_size <= (size_t)(end - s)) {
        se = s + byte_size;
    }
    int32_t root = rd_i32(s + 32);
    if (root < (int32_t)kHeader || (size_t)root + kNode > (size_t)(se - s)) {
        err = "a physics solid's ledge tree lies outside it";
        return false;
    }
    std::vector<const uint8_t *> stack;
    stack.push_back(s + root);
    uint32_t visited = 0;
    while (!stack.empty()) {
        const uint8_t *node = stack.back();
        stack.pop_back();
        if (++visited > 65536) {
            err = "a physics solid's ledge tree is too large";
            return false;
        }
        if (node < s + kHeader || node + kNode > se) {
            err = "a physics solid's ledge tree node lies outside it";
            return false;
        }
        int32_t right = rd_i32(node), ledge_ofs = rd_i32(node + 4);
        if (right != 0) {
            // inner node: the left child follows it, the right one is `right` bytes on
            int64_t r = (int64_t)(node - s) + right;
            if (r < (int64_t)kHeader || r + (int64_t)kNode > (int64_t)(se - s)) {
                err = "a physics solid's ledge tree is damaged";
                return false;
            }
            stack.push_back(node + kNode);
            stack.push_back(s + r);
            continue;
        }
        // terminal node: one convex piece
        int64_t lo = (int64_t)(node - s) + ledge_ofs;
        if (lo < (int64_t)kHeader || lo + (int64_t)kLedge > (int64_t)(se - s)) {
            err = "a physics solid's convex piece lies outside it";
            return false;
        }
        const uint8_t *L = s + lo;
        int32_t cpo = rd_i32(L);
        int16_t ntri = rd_i16(L + 12);
        if (ntri < 1 || (size_t)ntri * kTri + kLedge > (size_t)(se - L)) {
            err = "a physics solid's convex piece has a bad triangle count";
            return false;
        }
        int64_t pbase = lo + cpo;
        std::vector<float> h;
        h.reserve((size_t)ntri * 9);
        for (int16_t t = 0; t < ntri; t++) {
            const uint8_t *T = L + kLedge + (size_t)t * kTri;
            float tri[9];
            for (int k = 0; k < 3; k++) {
                uint32_t idx = rd_u32(T + 4 + 4 * k) & 0xFFFFu;
                int64_t pa = pbase + (int64_t)idx * (int64_t)kPoint;
                if (pa < (int64_t)kHeader || pa + 12 > (int64_t)(se - s)) {
                    err = "a physics solid's point index lies outside it";
                    return false;
                }
                float v[3];
                std::memcpy(v, s + pa, 12);
                if (!std::isfinite(v[0]) || !std::isfinite(v[1]) || !std::isfinite(v[2]) || std::fabs(v[0]) > 2000.0f ||
                    std::fabs(v[1]) > 2000.0f || std::fabs(v[2]) > 2000.0f) {
                    err = "a physics solid has a point out of range";
                    return false;
                }
                tri[3 * k + 0] = (float)(v[0] * kInchPerMetre);
                tri[3 * k + 1] = (float)(v[2] * kInchPerMetre);
                tri[3 * k + 2] = (float)(-v[1] * kInchPerMetre);
            }
            h.insert(h.end(), tri, tri + 9);
        }
        // counter-clockwise seen from outside: each triangle turned away from the piece's centre
        double c[3] = {0, 0, 0};
        size_t nv = h.size() / 3;
        for (size_t i = 0; i < nv; i++) {
            for (int k = 0; k < 3; k++) {
                c[k] += h[3 * i + k];
            }
        }
        for (int k = 0; k < 3; k++) {
            c[k] /= (double)nv;
        }
        for (size_t t = 0; t < h.size() / 9; t++) {
            float *a = &h[9 * t], *b = a + 3, *cc = a + 6;
            double e1[3] = {b[0] - a[0], b[1] - a[1], b[2] - a[2]}, e2[3] = {cc[0] - a[0], cc[1] - a[1], cc[2] - a[2]};
            double nx = e1[1] * e2[2] - e1[2] * e2[1], ny = e1[2] * e2[0] - e1[0] * e2[2], nz = e1[0] * e2[1] - e1[1] * e2[0];
            double mx = (a[0] + b[0] + cc[0]) / 3.0 - c[0], my = (a[1] + b[1] + cc[1]) / 3.0 - c[1],
                   mz = (a[2] + b[2] + cc[2]) / 3.0 - c[2];
            if (nx * mx + ny * my + nz * mz < 0.0) {
                for (int k = 0; k < 3; k++) {
                    std::swap(b[k], cc[k]);
                }
            }
        }
        for (size_t i = 0; i < nv; i++) {
            for (int k = 0; k < 3; k++) {
                float v = h[3 * i + k];
                if (out.hulls.empty() && out.ledges == 0 && i == 0) {
                    out.mins[k] = out.maxs[k] = v;
                }
                out.mins[k] = std::min(out.mins[k], v);
                out.maxs[k] = std::max(out.maxs[k], v);
            }
        }
        out.ledges++;
        out.triangles += (uint32_t)ntri;
        out.hulls.push_back(std::move(h));
        if (out.hulls.size() > 4096) {
            err = "a physics model has too many convex pieces";
            return false;
        }
    }
    return true;
}

}  // namespace

bool parse_phy(const void *data, size_t n, PhyModel &out, std::string &err)
{
    out = PhyModel();
    const uint8_t *d = (const uint8_t *)data;
    if (!d || n < 16 || n > (64u << 20)) {
        err = "not a physics model (.phy)";
        return false;
    }
    int32_t hsize = rd_i32(d), solids = rd_i32(d + 8);
    if (hsize < 16 || (size_t)hsize > n || solids < 1 || solids > 128) {
        err = "not a physics model (.phy header)";
        return false;
    }
    out.solids = (uint32_t)solids;
    size_t pos = (size_t)hsize;
    std::vector<std::pair<size_t, size_t>> ranges;
    for (int32_t i = 0; i < solids; i++) {
        if (pos + 4 > n) {
            err = "a physics model is truncated";
            return false;
        }
        int32_t sz = rd_i32(d + pos);
        pos += 4;
        if (sz < 0 || (size_t)sz > n - pos) {
            err = "a physics model is truncated";
            return false;
        }
        ranges.push_back({pos, (size_t)sz});
        pos += (size_t)sz;
    }
    // the text section (key values): ragdolls have constraints between their solids (bones); each solid block names
    // its surface type ("surfaceprop"; a block without "index" is the next solid). A text section that does not parse
    // only loses the surface types.
    out.solid_surfaceprop.assign((size_t)solids, std::string());
    if (pos < n) {
        std::string text((const char *)d + pos, n - pos);
        out.ragdoll = text.find("ragdollconstraint") != std::string::npos;
        std::vector<KvNode> kv;
        std::string kerr;
        if (kv_parse(text.data(), text.size(), kv, kerr, 20000)) {
            int32_t next = 0;
            for (const KvNode &k : kv) {
                if (!k.block || k.key != "solid") {
                    continue;
                }
                int32_t index = next;
                if (const KvNode *ix = k.find("index")) {
                    index = std::atoi(ix->value.c_str());
                }
                next = index + 1;
                const KvNode *sp = k.find("surfaceprop");
                if (sp && index >= 0 && index < solids) {
                    std::string v = to_lower(sp->value);
                    while (!v.empty() && (unsigned char)v.back() <= ' ') {
                        v.pop_back();
                    }
                    while (!v.empty() && (unsigned char)v.front() <= ' ') {
                        v.erase(0, 1);
                    }
                    if (valid_surface_name(v)) {
                        out.solid_surfaceprop[(size_t)index] = v;
                    }
                }
            }
        }
    }
    for (size_t i = 0; i < ranges.size(); i++) {
        if (out.ragdoll && i > 0) {
            out.skipped_solids++;
            continue;
        }
        const uint8_t *s = d + ranges[i].first, *e = s + ranges[i].second;
        if (ranges[i].second >= 28 && std::memcmp(s, "VPHY", 4) == 0) {
            int16_t model_type = rd_i16(s + 6);
            if (model_type != 0) {
                out.skipped_solids++;   // a polygon soup (MOPP): not a convex model
                continue;
            }
            s += 28;
        }
        if (!parse_surface(s, e, out, err)) {
            return false;
        }
        out.hull_solid.resize(out.hulls.size(), (uint16_t)i);
        out.solids_used++;
    }
    if (out.hulls.empty()) {
        err = "the physics model has no convex pieces";
        return false;
    }
    return true;
}

bool parse_mdl_hull(const void *data, size_t n, float mins[3], float maxs[3], std::string &err)
{
    const uint8_t *d = (const uint8_t *)data;
    if (!d || n < 128 || std::memcmp(d, "IDST", 4) != 0) {
        err = "not a studio model (.mdl)";
        return false;
    }
    int32_t version = rd_i32(d + 4);
    if (version < 37 || version > 53) {
        err = format("studio model version %d", (int)version);
        return false;
    }
    float v[6];
    std::memcpy(v, d + 104, 24);
    for (int k = 0; k < 6; k++) {
        if (!std::isfinite(v[k]) || std::fabs(v[k]) > 65536.0f) {
            err = "the studio model's hull is damaged";
            return false;
        }
    }
    for (int k = 0; k < 3; k++) {
        mins[k] = v[k];
        maxs[k] = v[3 + k];
        if (!(maxs[k] > mins[k])) {
            err = "the studio model's hull is empty";
            return false;
        }
    }
    return true;
}

}  // namespace gsa1
