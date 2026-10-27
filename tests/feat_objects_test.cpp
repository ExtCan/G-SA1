// feat_objects_test: the objects feature's core (src/core/objects.{hpp,cpp}; round 0.9.4, sadc docs/research/
// gsa1_094_plan.md 6.5 with its Review), offline and without the disc. build.py links it like core_test (the core and
// libsa1) and runs it.
//
//   feat_objects_test [--gdi GAME.gdi]     (the disc is not needed: feat_objects_binding_test runs the worlds)
//
// Checks:
//   * the angles: Source's AngleMatrix (forward, left, up) and the records' quarter turn (the game's +z = forward);
//   * the records of each kind: a RING (the record's rotation, params 0), the ground Item Box (upright: no rotation, the
//     contents), the air one (its rotation), contents 9 / 2.5 / -1 refused, a Ring circle of 129 refused, a Ring line
//     of 129 refused (0.9.4.1: 128 each), spacing out of range refused;
//   * THE LINE SPLIT: a line of 20 -> 3 records of 8 / 8 / 4 rings (n = 7, 7, 3) whose positions put the 20 rings on 20
//     consecutive places 40 HU apart, centred on the entity, along its forward axis - computed twice: from the records
//     the way the game places a line's rings (func_8C087EEE: odd i at +ceil(i / 2), even i at -(i / 2) spacings, turned
//     by the record's rotation, the host's (x, -z, y) axes), and by ring_positions (the addon's markers and the server's
//     reach use the same layout); 64 rings -> 8 records, 128 -> 16; a yawed and pitched line keeps both in step;
//   * the circle: 7 rings, radius 80 HU, ring i at i * 360 / 7 degrees (func_8C088000) - the same two ways;
//   * 0.9.4.1 - THE CIRCLE OF N RINGS from several records (N = 1..128): m = N / n records of n rings (n = the largest of
//     7..1 dividing N: 8 -> 2 x 4, 12 -> 2 x 6, 64 -> 16 x 4, 127 -> 127 x 1, 128 -> 32 x 4), record k turned by
//     k * 360 / N about the circle's axis: the game's own circle layout of every record puts the N rings on the N evenly
//     spaced places (each once, 360 / N apart, at the radius), the same as ring_positions, at several angles; a circle
//     made bigger / smaller adds / removes records;
//   * the registry with a recording sink (records <-> entities): add / update (a longer and a shorter line: records
//     added and removed, the others updated), the state for every record, a record's bits, bits going down re-make the
//     group (sa1_set_update), BROKEN refused on anything but the ground box, a failure leaves nothing added, remove, a
//     new context forgets everything (generation + 1);
//   * the event filter: an event of a live record -> its object, record index and the host's tag; an event of a removed
//     object, or of a record id that is not the tag's -> dropped;
//   * the render (review R.1, with Session::rebatch on made-up draws): an OBJECT draw and a non-OBJECT draw of the same
//     state are two batches and the batch's flags carry SA1_DRAW_OBJECT; a ring's blob shadow (SHADOW | EFFECT | OBJECT)
//     and the character's (SHADOW | EFFECT) are two batches; one draw of 20,000 triangles is split over 3 batches of at
//     most 8,000 (0.9.3a skipped it); object_draw_bounds covers only the OBJECT draws (one 1,500 HU away).
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "../src/core/objects.hpp"
#include "../src/core/session.hpp"
#include "../src/core/util.hpp"

using namespace gsa1;
namespace ob = gsa1::objects;

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

namespace {

const double kPi = 3.14159265358979323846;

bool near3(const float *a, const float *b, float tol)
{
    return std::fabs(a[0] - b[0]) <= tol && std::fabs(a[1] - b[1]) <= tol && std::fabs(a[2] - b[2]) <= tol;
}

// the game's ring places of a record, as the game computes them (in SA1 local units, then the record's host rotation
// and the host's axes: host = scale x (x, -z, y))
void game_rings(const sa1_set_record &r, float hu, std::vector<std::vector<float>> &out)
{
    out.clear();
    uint32_t n = (uint32_t)r.params[0];
    float s = r.params[1];
    bool circle = r.params[2] == 1.0f;
    for (uint32_t i = 0; i <= n; i++) {
        float v[3] = {0.0f, 0.0f, 0.0f};    // SA1 local (x, y, z)
        if (!circle) {
            // func_8C087EEE
            if (i % 2) {
                v[2] = s * std::ceil((float)i * 0.5f);
            } else {
                v[2] = -(s * (float)i * 0.5f);
            }
        } else {
            if (i == 0) continue;
            // func_8C088000 (njSin / njCos of the BAMS angle; exact here)
            double a = (double)i * 360.0 / (double)n * kPi / 180.0;
            v[2] = (float)(s * std::cos(a));
            v[0] = (float)(s * std::sin(a));
        }
        // SA1 local -> host local (x, -z, y), scaled
        float hl[3] = {v[0] * hu, -v[2] * hu, v[1] * hu};
        std::vector<float> p(3);
        for (int c = 0; c < 3; c++) {
            p[c] = r.position[c] + r.rotation[3 * c + 0] * hl[0] + r.rotation[3 * c + 1] * hl[1] +
                   r.rotation[3 * c + 2] * hl[2];
        }
        out.push_back(p);
    }
}

struct Call {
    std::string what;
    uint32_t id = 0, state = 0, bits = 0;
    sa1_set_record rec{};
};

class Recorder : public ob::Sink {
public:
    std::vector<Call> calls;
    uint32_t next = 100;
    std::set<uint32_t> live;
    int fail_add_at = -1;           // the n-th add fails (0-based), -1: none
    int adds = 0;
    sa1_status add(const sa1_set_record &r, uint32_t &id) override
    {
        if (fail_add_at >= 0 && adds++ == fail_add_at) {
            return SA1_ERR_LIMIT;
        }
        id = next++;
        live.insert(id);
        Call c;
        c.what = "add";
        c.id = id;
        c.rec = r;
        calls.push_back(c);
        return SA1_OK;
    }
    sa1_status update(uint32_t id, const sa1_set_record &r) override
    {
        Call c;
        c.what = "update";
        c.id = id;
        c.rec = r;
        calls.push_back(c);
        return live.count(id) ? SA1_OK : SA1_ERR_NOT_FOUND;
    }
    sa1_status remove(uint32_t id) override
    {
        Call c;
        c.what = "remove";
        c.id = id;
        calls.push_back(c);
        return live.erase(id) ? SA1_OK : SA1_ERR_NOT_FOUND;
    }
    sa1_status state(uint32_t id, uint32_t st, uint32_t bits) override
    {
        Call c;
        c.what = "state";
        c.id = id;
        c.state = st;
        c.bits = bits;
        calls.push_back(c);
        return live.count(id) ? SA1_OK : SA1_ERR_NOT_FOUND;
    }
    int count(const char *w) const
    {
        int n = 0;
        for (const Call &c : calls) n += c.what == w;
        return n;
    }
    std::string text() const
    {
        std::string s;
        for (const Call &c : calls) s += (s.empty() ? "" : " ") + c.what;
        return s;
    }
};

ob::Desc desc(uint32_t type, float x, float y, float z, float p0 = 0, float p1 = 0, float p2 = 0, float pitch = 0,
              float yaw = 0, float roll = 0)
{
    ob::Desc d;
    d.type = type;
    d.pos[0] = x;
    d.pos[1] = y;
    d.pos[2] = z;
    d.ang[0] = pitch;
    d.ang[1] = yaw;
    d.ang[2] = roll;
    d.p[0] = p0;
    d.p[1] = p1;
    d.p[2] = p2;
    return d;
}

// both ways of placing a group's rings agree (and every place is taken once); returns the largest difference
float check_layout(const ob::Desc &d, std::string &why)
{
    std::vector<sa1_set_record> recs;
    std::string err;
    std::vector<ob::RingPos> rp;
    if (!ob::make_records(d, 4.0f, 7, recs, err) || !ob::ring_positions(d, rp)) {
        why = "no records / positions: " + err;
        return 1e9f;
    }
    float worst = 0.0f;
    size_t matched = 0;
    for (size_t g = 0; g < recs.size(); g++) {
        std::vector<std::vector<float>> gr;
        game_rings(recs[g], 4.0f, gr);
        uint32_t i0 = recs[g].params[2] == 1.0f ? 1u : 0u;
        for (size_t k = 0; k < gr.size(); k++) {
            uint32_t bit = 1u << (uint32_t)(k + i0);
            bool found = false;
            for (const ob::RingPos &r : rp) {
                if (r.record == g && r.bit == bit) {
                    float dd = std::max(std::fabs(r.pos[0] - gr[k][0]),
                                        std::max(std::fabs(r.pos[1] - gr[k][1]), std::fabs(r.pos[2] - gr[k][2])));
                    worst = std::max(worst, dd);
                    found = true;
                    matched++;
                }
            }
            if (!found) {
                why = format("record %u ring %u has no position", (unsigned)g, (unsigned)k);
                return 1e9f;
            }
        }
    }
    if (matched != rp.size()) {
        why = format("%u game rings for %u positions", (unsigned)matched, (unsigned)rp.size());
        return 1e9f;
    }
    std::set<uint32_t> places;
    for (const ob::RingPos &r : rp) places.insert(r.place);
    if (places.size() != rp.size()) {
        why = "a place is taken twice";
        return 1e9f;
    }
    return worst;
}

void push_tri_draw(Character &c, uint32_t ntri, float x, float y, float z, uint32_t flags, int32_t archive, int32_t tex,
                   uint8_t bs = SA1_BLEND_ONE, uint8_t bd = SA1_BLEND_ZERO)
{
    sa1_draw d;
    std::memset(&d, 0, sizeof d);
    d.prim = SA1_PRIM_TRIANGLES;
    d.first = c.r_triangles;
    d.count = ntri;
    d.archive = archive;
    d.texture = tex;
    d.flags = flags;
    d.blend_src = bs;
    d.blend_dst = bd;
    d.order = (uint32_t)c.r_draws.size();
    for (uint32_t t = 0; t < ntri; t++) {
        for (int k = 0; k < 3; k++) {
            c.r_tpos.push_back(x + (float)k);
            c.r_tpos.push_back(y);
            c.r_tpos.push_back(z + (float)(t % 7));
            c.r_tnrm.insert(c.r_tnrm.end(), {0.0f, 0.0f, 1.0f});
            c.r_tuv.insert(c.r_tuv.end(), {0.0f, 0.0f});
            c.r_tcol.insert(c.r_tcol.end(), {255, 255, 255, 255});
        }
    }
    c.r_triangles += ntri;
    c.r_draws.push_back(d);
}

}  // namespace

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    std::printf("G-SA1 feat_objects_test\n");

    // ---- angles --------------------------------------------------------------------------------------------------------
    {
        float m[9], r[9];
        const float a0[3] = {0, 90, 0};
        ob::angle_matrix(a0, m);
        ob::record_matrix(a0, r);
        const float fwd[3] = {m[0], m[3], m[6]}, left[3] = {m[1], m[4], m[7]}, up[3] = {m[2], m[5], m[8]};
        const float rx[3] = {r[0], r[3], r[6]}, ry[3] = {r[1], r[4], r[7]};
        const float wf[3] = {0, 1, 0}, wl[3] = {-1, 0, 0}, wu[3] = {0, 0, 1}, wmf[3] = {0, -1, 0};
        CHECK(near3(fwd, wf, 1e-5f) && near3(left, wl, 1e-5f) && near3(up, wu, 1e-5f) && near3(rx, wl, 1e-5f) &&
                  near3(ry, wmf, 1e-5f),
              "yaw 90: forward (%.2f %.2f %.2f), left (%.2f %.2f %.2f); the record's x = left, y = -forward (the game's "
              "+z = host local -y = the entity's forward)", fwd[0], fwd[1], fwd[2], left[0], left[1], left[2]);
        const float a1[3] = {-30, 10, 0};
        ob::angle_matrix(a1, m);
        CHECK(m[6] > 0.49f && m[6] < 0.51f, "pitch -30 looks up: forward z %.3f (Source: -sin pitch)", m[6]);
    }

    // ---- records of each kind -----------------------------------------------------------------------------------------
    {
        std::vector<sa1_set_record> r;
        std::string err;
        bool ring = ob::make_records(desc(SA1_OBJTYPE_RING, 10, 20, 30, 0, 0, 0, 0, 45), 4.0f, 5, r, err) && r.size() == 1 &&
                    r[0].type == SA1_OBJTYPE_RING && r[0].position[0] == 10 && r[0].params[0] == 0 &&
                    r[0].user == ((5ull << 8) | 0u) && r[0].rotation[8] > 0.99f && r[0].struct_size == sizeof r[0];
        bool gbox = ob::make_records(desc(SA1_OBJTYPE_ITEMBOX, 0, 0, 0, 3, 0, 0, 20, 70, 10), 4.0f, 6, r, err) &&
                    r.size() == 1 && r[0].params[0] == 3 && r[0].params[1] == 0 && r[0].params[2] == 0;
        bool zero = true;
        for (int k = 0; k < 9 && gbox; k++) zero = zero && r[0].rotation[k] == 0.0f;
        bool abox = ob::make_records(desc(SA1_OBJTYPE_ITEMBOX_AIR, 0, 0, 40, 6, 0, 0, 0, 30), 4.0f, 7, r, err) &&
                    r.size() == 1 && r[0].params[0] == 6 && r[0].rotation[8] > 0.99f;
        int refused = 0;
        refused += !ob::make_records(desc(SA1_OBJTYPE_ITEMBOX, 0, 0, 0, 9), 4.0f, 1, r, err);
        refused += !ob::make_records(desc(SA1_OBJTYPE_ITEMBOX, 0, 0, 0, 2.5f), 4.0f, 1, r, err);
        refused += !ob::make_records(desc(SA1_OBJTYPE_ITEMBOX_AIR, 0, 0, 0, -1), 4.0f, 1, r, err);
        refused += !ob::make_records(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 129, 80, 1), 4.0f, 1, r, err);
        refused += !ob::make_records(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 129, 40, 0), 4.0f, 1, r, err);
        refused += !ob::make_records(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 5, 1, 0), 4.0f, 1, r, err);
        refused += !ob::make_records(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 5, 40, 2), 4.0f, 1, r, err);
        refused += !ob::make_records(desc(5, 0, 0, 0), 4.0f, 1, r, err);
        refused += !ob::make_records(desc(SA1_OBJTYPE_RING, 1e9f, 0, 0), 4.0f, 1, r, err);
        CHECK(ring && gbox && zero && abox && refused == 9,
              "records: a RING (params 0, its rotation, user tag object << 8 | index), the ground box upright (no rotation, "
              "contents 3) at any angle, the air box turned; refused %d of 9 (contents 9 / 2.5 / -1, a circle of 129, a "
              "line of 129, spacing 1 HU, shape 2, type 5, a position off the map): %s", refused, err.c_str());
    }

    // ---- the line split ---------------------------------------------------------------------------------------------
    {
        std::vector<sa1_set_record> r;
        std::string err;
        bool ok = ob::make_records(desc(SA1_OBJTYPE_O_GRING, 100, 200, 300, 20, 40, 0), 4.0f, 9, r, err);
        bool shape = ok && r.size() == 3 && r[0].params[0] == 7 && r[1].params[0] == 7 && r[2].params[0] == 3 &&
                     r[0].params[1] == 10.0f && r[0].params[2] == 0.0f && r[2].user == ((9ull << 8) | 2u);
        // record centres: places 3, 11, 17 of 0..19 (centred at 9.5): -260, +60, +300 HU along +x
        bool centres = shape && std::fabs(r[0].position[0] - (100 - 260)) < 1e-3f &&
                       std::fabs(r[1].position[0] - (100 + 60)) < 1e-3f && std::fabs(r[2].position[0] - (100 + 300)) < 1e-3f &&
                       r[0].position[1] == 200 && r[2].position[2] == 300;
        std::vector<ob::RingPos> rp;
        ob::ring_positions(desc(SA1_OBJTYPE_O_GRING, 100, 200, 300, 20, 40, 0), rp);
        std::vector<float> xs;
        for (const ob::RingPos &p : rp) xs.push_back(p.pos[0]);
        std::sort(xs.begin(), xs.end());
        bool spaced = xs.size() == 20 && std::fabs(xs.front() - (100 - 380)) < 1e-3f && std::fabs(xs.back() - (100 + 380)) < 1e-3f;
        for (size_t k = 1; k < xs.size() && spaced; k++) spaced = std::fabs(xs[k] - xs[k - 1] - 40.0f) < 1e-3f;
        std::string why;
        float w = check_layout(desc(SA1_OBJTYPE_O_GRING, 100, 200, 300, 20, 40, 0), why);
        CHECK(shape && centres && spaced && w < 1e-3f,
              "a Ring line of 20 (40 HU apart) -> 3 records of 8 / 8 / 4 rings (n %g %g %g, spacing %g units) centred at "
              "-260 / +60 / +300 HU: its 20 rings 40 HU apart from -380 to +380 around the entity; the game's own line "
              "layout of the records puts every ring where ring_positions says (largest difference %g HU)%s%s",
              ok ? r[0].params[0] : -1.0, r.size() > 1 ? r[1].params[0] : -1.0, r.size() > 2 ? r[2].params[0] : -1.0,
              ok ? r[0].params[1] : -1.0, (double)w, why.empty() ? "" : ": ", why.c_str());
        std::string why2, why3, why4;
        float w2 = check_layout(desc(SA1_OBJTYPE_O_GRING, -50, 10, 5, 64, 32, 0, -20, 135, 15), why2);
        float w3 = check_layout(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 1, 40, 0, 0, 33), why3);
        float w4 = check_layout(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 13, 40, 0, 10, -60, 0), why4);
        std::string why5;
        float w5 = check_layout(desc(SA1_OBJTYPE_O_GRING, 30, -20, 64, 128, 40, 0, 15, -100, 5), why5);
        bool n64 = ob::record_count(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 64, 40, 0)) == 8 &&
                   ob::record_count(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 128, 40, 0)) == 16;
        CHECK(w2 < 1e-2f && w3 < 1e-3f && w4 < 1e-2f && w5 < 2e-2f && n64,
              "a pitched, yawed and rolled line of 64 (8 records), a line of 1, a line of 13 and a turned line of 128 (16 "
              "records, 0.9.4.1): the game's layout and ring_positions agree (%g, %g, %g, %g HU)%s%s%s%s", (double)w2,
              (double)w3, (double)w4, (double)w5, why2.c_str(), why3.c_str(), why4.c_str(), why5.c_str());
        // a line along the entity's forward: yaw 90 -> +y
        ob::ring_positions(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 2, 40, 0, 0, 90), rp);
        bool along = rp.size() == 2 && std::fabs(rp[0].pos[0]) < 1e-3f && std::fabs(rp[1].pos[0]) < 1e-3f &&
                     std::fabs(std::fabs(rp[0].pos[1] - rp[1].pos[1]) - 40.0f) < 1e-3f;
        CHECK(along, "a line of 2 at yaw 90 runs along +y (the entity's forward): (%.1f %.1f) (%.1f %.1f)",
              rp.size() > 0 ? rp[0].pos[0] : 0.0f, rp.size() > 0 ? rp[0].pos[1] : 0.0f, rp.size() > 1 ? rp[1].pos[0] : 0.0f,
              rp.size() > 1 ? rp[1].pos[1] : 0.0f);
    }

    // ---- the circle -------------------------------------------------------------------------------------------------
    {
        std::vector<sa1_set_record> r;
        std::string err, why;
        bool ok = ob::make_records(desc(SA1_OBJTYPE_O_GRING, 0, 0, 50, 7, 80, 1, 0, 25), 4.0f, 3, r, err) && r.size() == 1 &&
                  r[0].params[0] == 7 && r[0].params[1] == 20 && r[0].params[2] == 1;
        float w = check_layout(desc(SA1_OBJTYPE_O_GRING, 0, 0, 50, 7, 80, 1, 0, 25), why);
        std::vector<ob::RingPos> rp;
        ob::ring_positions(desc(SA1_OBJTYPE_O_GRING, 0, 0, 50, 7, 80, 1), rp);
        bool round = rp.size() == 7;
        for (const ob::RingPos &p : rp) {
            round = round && std::fabs(std::sqrt(p.pos[0] * p.pos[0] + p.pos[1] * p.pos[1]) - 80.0f) < 1e-3f &&
                    std::fabs(p.pos[2] - 50.0f) < 1e-3f && p.bit >= 2 && p.bit <= 128;
        }
        const float last[3] = {80, 0, 50};
        bool front = round && near3(rp[6].pos, last, 1e-3f) && rp[6].place == 0 && rp[0].place == 1;
        CHECK(ok && w < 1e-3f && round && front,
              "a Ring circle of 7 (radius 80 HU): one record (7, 20 units, 1); its rings 80 HU around the entity, bits 1 << "
              "1..7, ring 7 straight ahead; the game's circle layout agrees (%g HU)%s", (double)w, why.c_str());
    }

    // ---- 0.9.4.1: a circle of N rings from several records ----------------------------------------------------------
    {
        struct Case { uint32_t n_rings, per, recs; float pitch, yaw, roll; };
        const Case cases[] = {{1, 1, 1, 0, 0, 0},        {7, 7, 1, 0, 37, 0},      {8, 4, 2, 0, 0, 0},
                              {12, 6, 2, 0, 90, 0},      {64, 4, 16, 30, 37, 0},   {127, 1, 127, 0, 200, 0},
                              {128, 4, 32, -60, 120, 20}, {100, 5, 20, 0, 10, 45}};
        int good = 0, n = 0;
        std::string bad;
        for (const Case &cs : cases) {
            n++;
            ob::Desc d = desc(SA1_OBJTYPE_O_GRING, 100, -40, 70, (float)cs.n_rings, 120, 1, cs.pitch, cs.yaw, cs.roll);
            uint32_t per = 0, recs = 0;
            ob::circle_split(cs.n_rings, per, recs);
            std::vector<sa1_set_record> r;
            std::string err, why;
            bool made = ob::make_records(d, 4.0f, 11, r, err) && r.size() == cs.recs && per == cs.per && recs == cs.recs &&
                        ob::record_count(d) == cs.recs;
            for (size_t k = 0; made && k < r.size(); k++) {
                made = r[k].params[0] == (float)cs.per && r[k].params[1] == 30.0f && r[k].params[2] == 1.0f &&
                       r[k].user == ((11ull << 8) | (uint64_t)k);
            }
            float w = check_layout(d, why);
            // every place once, at the radius, place p at p * 360 / N from the entity's forward towards its left
            std::vector<ob::RingPos> rp;
            ob::ring_positions(d, rp);
            float am[9];
            ob::angle_matrix(d.ang, am);
            std::set<uint32_t> places;
            float worst = 0.0f;
            for (const ob::RingPos &p : rp) {
                places.insert(p.place);
                double a = (double)p.place * 2.0 * kPi / (double)cs.n_rings;
                for (int c = 0; c < 3; c++) {
                    double want = d.pos[c] + 120.0 * (std::cos(a) * am[3 * c + 0] + std::sin(a) * am[3 * c + 1]);
                    worst = std::max(worst, (float)std::fabs(want - p.pos[c]));
                }
            }
            bool even = rp.size() == cs.n_rings && places.size() == cs.n_rings && *places.rbegin() == cs.n_rings - 1 &&
                        worst < 1e-2f;
            if (made && w < 2e-2f && even) {
                good++;
            } else {
                bad += format(" [%u rings: records %zu x %u (%s), game layout off %g HU %s, evenly spaced %s (off %g)]",
                              cs.n_rings, r.size(), per, made ? "ok" : "bad", (double)w, why.c_str(), even ? "yes" : "no",
                              (double)worst);
            }
        }
        CHECK(good == n,
              "Ring circles of 1, 7, 8, 12, 64, 127, 128 and 100 rings at several angles: records of n = 1 / 7 / 4 / 6 / 4 / "
              "1 / 4 / 5 rings (1, 1, 2, 2, 16, 127, 32, 20 records, each turned by k * 360 / N), the game's own circle "
              "layout of every record puts each ring on one of the N evenly spaced places, every place once (%d of %d)%s",
              good, n, bad.c_str());
        // golden places, the same numbers feat_objects_test.lua checks O.RingPositions against (module and addon in step)
        auto golden = [](const ob::Desc &d, uint32_t record, uint32_t bit, uint32_t place, float x, float y) {
            std::vector<ob::RingPos> rp;
            ob::ring_positions(d, rp);
            for (const ob::RingPos &p : rp) {
                if (p.record == record && p.bit == bit) {
                    return p.place == place && std::fabs(p.pos[0] - x) < 1e-3f && std::fabs(p.pos[1] - y) < 1e-3f &&
                           std::fabs(p.pos[2]) < 1e-3f;
                }
            }
            return false;
        };
        bool g1 = golden(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 12, 100, 1), 1, 4, 5, -86.60254f, 50.0f);
        bool g2 = golden(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 128, 100, 1), 31, 16, 31, 4.90677f, 99.87955f);
        bool g3 = golden(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 20, 40, 0), 2, 8, 19, 380.0f, 0.0f);
        CHECK(g1 && g2 && g3,
              "golden places shared with feat_objects_test.lua (O.RingPositions): a circle of 12 (r 100) record 1 bit 4 -> "
              "place 5 (-86.6, 50); of 128 record 31 bit 16 -> place 31 (4.91, 99.88); a line of 20 record 2 bit 8 -> place "
              "19 (380, 0)");
        // a circle made bigger / smaller: records added / removed
        ob::Registry reg;
        Recorder rec;
        int ctx = 0;
        reg.bind(&ctx);
        uint32_t id = 0;
        std::string err;
        reg.add(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 7, 80, 1), 55, SA1_SET_STATE_PRESENT, rec, id, err);
        bool one = rec.text() == "add" && reg.find(id)->records.size() == 1;
        rec.calls.clear();
        reg.update(id, desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 128, 80, 1), rec, err);
        bool grown = rec.count("update") == 1 && rec.count("add") == 31 && reg.find(id)->records.size() == 32 &&
                     rec.calls[0].rec.params[0] == 4;
        rec.calls.clear();
        sa1_status s127 = reg.set_state(id, SA1_SET_STATE_PRESENT, 31, 0x1E, rec, err);
        bool last_bits = s127 == SA1_OK && rec.text() == "state" && rec.calls[0].id == reg.find(id)->records[31] &&
                         rec.calls[0].bits == 0x1E;
        rec.calls.clear();
        reg.update(id, desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 12, 80, 1), rec, err);
        bool shrunk = rec.count("update") == 2 && rec.count("remove") == 30 && reg.find(id)->records.size() == 2;
        CHECK(one && grown && last_bits && shrunk,
              "a circle of 7 (1 record) made 128 rings: 1 updated + 31 added (records of 4); record 31's bits 0x1E -> "
              "sa1_set_state of that record; made 12: 2 updated, 30 removed");
    }

    // ---- the registry (records <-> entities) --------------------------------------------------------------------------
    {
        ob::Registry reg;
        Recorder rec;
        int dummy_ctx = 0;
        reg.bind(&dummy_ctx);
        uint32_t gen0 = reg.generation();
        std::string err;
        uint32_t line = 0, ring = 0, box = 0, abox = 0;
        sa1_status s1 = reg.add(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 20, 40, 0), 1234, SA1_SET_STATE_PRESENT, rec, line, err);
        bool add_ok = s1 == SA1_OK && line != 0 && rec.text() == "add add add" && reg.find(line) &&
                      reg.find(line)->records.size() == 3 && rec.calls[1].rec.user == (((uint64_t)line << 8) | 1u);
        rec.calls.clear();
        reg.update(line, desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 30, 40, 0), rec, err);
        bool longer = rec.text() == "update update update add" && reg.find(line)->records.size() == 4;
        rec.calls.clear();
        reg.update(line, desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 8, 40, 0), rec, err);
        bool shorter = rec.text() == "update remove remove remove" && reg.find(line)->records.size() == 1;
        CHECK(add_ok && longer && shorter,
              "a Ring line of 20 -> 3 records (user tags object << 8 | index); made 30 long: 3 updated + 1 added; made 8 "
              "long: 1 updated + 3 removed");
        reg.update(line, desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 20, 40, 0), rec, err);
        rec.calls.clear();
        sa1_status sb = reg.set_state(line, SA1_SET_STATE_PRESENT, 1, 0x05, rec, err);
        bool bits1 = sb == SA1_OK && rec.text() == "state" && rec.calls[0].bits == 0x05 && rec.calls[0].id == reg.find(line)->records[1];
        rec.calls.clear();
        reg.set_state(line, SA1_SET_STATE_PRESENT, 1, 0x07, rec, err);
        bool more = rec.text() == "state";
        rec.calls.clear();
        reg.set_state(line, SA1_SET_STATE_PRESENT, 1, 0x00, rec, err);
        bool remade = rec.text() == "state update" && rec.calls[1].id == reg.find(line)->records[1] &&
                      rec.calls[1].rec.params[0] == 7;
        rec.calls.clear();
        sa1_status sx = reg.set_state(line, SA1_SET_STATE_PRESENT, 5, 1, rec, err);
        CHECK(bits1 && more && remade && sx == SA1_ERR_INVALID_ARGUMENT && rec.calls.empty(),
              "a line's record 1: bits 0x05 -> sa1_set_state(record 1, PRESENT, 0x05) only; 0x07 -> a state; 0x00 (a "
              "respawn: bits went down) -> the state and sa1_set_update of that record (the group made again); record 5 "
              "of 3 refused");
        reg.add(desc(SA1_OBJTYPE_RING, 0, 0, 0), 77, SA1_SET_STATE_PRESENT, rec, ring, err);
        reg.add(desc(SA1_OBJTYPE_ITEMBOX, 0, 0, 0, 3), 78, SA1_SET_STATE_PRESENT | SA1_SET_STATE_BROKEN, rec, box, err);
        bool broken_add = rec.calls.size() == 3 && rec.calls[2].what == "state" && rec.calls[2].state == 3;
        reg.add(desc(SA1_OBJTYPE_ITEMBOX_AIR, 0, 0, 40, 6), 79, SA1_SET_STATE_PRESENT, rec, abox, err);
        rec.calls.clear();
        sa1_status r0 = reg.set_state(ring, 0, -1, 0, rec, err);
        bool ring0 = r0 == SA1_OK && rec.text() == "state" && rec.calls[0].state == 0;
        rec.calls.clear();
        sa1_status rb = reg.set_state(ring, SA1_SET_STATE_PRESENT | SA1_SET_STATE_BROKEN, -1, 0, rec, err);
        sa1_status ab = reg.set_state(abox, SA1_SET_STATE_PRESENT | SA1_SET_STATE_BROKEN, -1, 0, rec, err);
        sa1_status gb = reg.set_state(box, SA1_SET_STATE_PRESENT, -1, 0, rec, err);
        sa1_status rbits = reg.set_state(ring, SA1_SET_STATE_PRESENT, 0, 1, rec, err);
        CHECK(broken_add && ring0 && rb == SA1_ERR_INVALID_ARGUMENT && ab == SA1_ERR_INVALID_ARGUMENT && gb == SA1_OK &&
                  rbits == SA1_ERR_INVALID_ARGUMENT,
              "a ground box added BROKEN gets its state at once; a RING PRESENT 0 -> one state; BROKEN on a RING and on an "
              "air box refused, the ground box's taken; bits on a RING refused");
        rec.calls.clear();
        rec.fail_add_at = 1;
        rec.adds = 0;
        uint32_t bad = 0;
        sa1_status sf = reg.add(desc(SA1_OBJTYPE_O_GRING, 0, 0, 0, 24, 40, 0), 80, SA1_SET_STATE_PRESENT, rec, bad, err);
        bool undone = sf == SA1_ERR_LIMIT && bad == 0 && rec.text() == "add remove" && reg.size() == 4;
        rec.fail_add_at = -1;
        CHECK(undone, "the second record of a line failing (SA1_ERR_LIMIT): the first one removed again, no object (%s)",
              rec.text().c_str());

        // the event filter
        sa1_set_event e;
        std::memset(&e, 0, sizeof e);
        e.type = SA1_SET_EVENT_USERBITS;
        e.record = reg.find(line)->records[2];
        e.user = ((uint64_t)line << 8) | 2u;
        e.user_bits = 0x09;
        ob::Event m;
        bool mapped = reg.map(e, m) && m.object == line && m.index == 2 && m.user == 1234 &&
                      m.type == SA1_OBJTYPE_O_GRING && m.ev.user_bits == 0x09;
        sa1_set_event e2 = e;
        e2.record = reg.find(line)->records[0];
        bool wrong = !reg.map(e2, m);
        reg.remove(ring, rec);
        sa1_set_event e3;
        std::memset(&e3, 0, sizeof e3);
        e3.type = SA1_SET_EVENT_GONE;
        e3.user = (uint64_t)ring << 8;
        e3.record = 999;
        bool gone = !reg.map(e3, m);
        CHECK(mapped && wrong && gone && reg.stats().dropped == 2,
              "events: a record's USERBITS -> its object (entity 1234), record 2, bits 0x09; a record id that is not the "
              "tag's, and an event of a removed RING -> dropped (%llu)", (unsigned long long)reg.stats().dropped);
        size_t nobj = reg.size();
        int other_ctx = 0;
        reg.bind(&other_ctx);
        CHECK(nobj == 3 && reg.size() == 0 && reg.generation() == gen0 + 1,
              "a new context forgets the %u objects (generation %u -> %u: the addon adds them again)", (unsigned)nobj,
              (unsigned)gen0, (unsigned)reg.generation());
    }

    // ---- the render: OBJECT batches, the split, the bounds --------------------------------------------------------------
    {
        Session s;
        Character c;
        c.kind = SA1_CHAR_SONIC;
        c.num_archives = 3;
        const uint32_t OBJ = SA1_DRAW_OBJECT;
        const uint32_t SH = SA1_DRAW_SHADOW | SA1_DRAW_EFFECT | SA1_DRAW_BLEND | SA1_DRAW_UNLIT;
        push_tri_draw(c, 50, 0, 0, 0, SA1_DRAW_PALETTE_LIT, 0, 1);                    // Sonic's body
        push_tri_draw(c, 96, 1500, 0, 10, SA1_DRAW_EFFECT | SA1_DRAW_ENV_MAP | OBJ, 2, 50);   // a ring, far away
        push_tri_draw(c, 96, 40, 0, 10, SA1_DRAW_EFFECT | SA1_DRAW_ENV_MAP, 2, 50);   // the same state without OBJECT
        push_tri_draw(c, 2, 0, 0, 0, SH, -1, -1, SA1_BLEND_SRC_ALPHA, SA1_BLEND_INV_SRC_ALPHA);        // Sonic's blob
        push_tri_draw(c, 2, 1500, 0, 0, SH | OBJ, -1, -1, SA1_BLEND_SRC_ALPHA, SA1_BLEND_INV_SRC_ALPHA);  // the ring's
        push_tri_draw(c, 20000, -300, 0, 0, SA1_DRAW_EFFECT | OBJ, 2, 51);           // a merged run of rings
        s.rebatch(c);
        int obj_batches = 0, plain_ring = 0, blobs = 0, obj_blobs = 0, big = 0;
        uint32_t big_tris = 0, max_tris = 0, total = 0;
        for (uint32_t b = 0; b < c.batch_count; b++) {
            const RenderBatch &rb = c.batches[b];
            total += rb.triangles;
            max_tris = std::max(max_tris, rb.triangles);
            obj_batches += (rb.flags & OBJ) ? 1 : 0;
            plain_ring += rb.texture == 50 && !(rb.flags & OBJ);
            if (rb.flags & SA1_DRAW_SHADOW) {
                blobs++;
                obj_blobs += (rb.flags & OBJ) ? 1 : 0;
            }
            if (rb.texture == 51) {
                big++;
                big_tris += rb.triangles;
            }
        }
        CHECK(plain_ring == 1 && blobs == 2 && obj_blobs == 1 && big == 3 && big_tris == 20000 && max_tris <= 8000 &&
                  total == 50 + 96 + 96 + 2 + 2 + 20000 && c.split_draws == 1,
              "rebatch: a ring and a non-OBJECT draw of the same state are two batches (OBJECT batches %d); the ring's blob "
              "shadow and Sonic's are two batches (%d shadow batches, %d OBJECT); one draw of 20,000 triangles -> %d "
              "batches, %u triangles, at most %u per batch (0.9.3a skipped it); %u triangles in all", obj_batches, blobs,
              obj_blobs, big, big_tris, max_tris, total);
        float mn[3], mx[3];
        bool bounded = ob::object_draw_bounds(c, mn, mx) && mx[0] >= 1500.0f && mn[0] <= -300.0f && mn[0] > -400.0f;
        Character none;
        push_tri_draw(none, 10, 0, 0, 0, SA1_DRAW_PALETTE_LIT, 0, 1);
        float mn2[3], mx2[3];
        bool nothing = !ob::object_draw_bounds(none, mn2, mx2);
        CHECK(bounded && nothing,
              "object_draw_bounds: x %.0f .. %.0f (the rings 1,500 HU away and the run at -300; Sonic's body at 0 is not "
              "what widens it); a render without OBJECT draws: none", bounded ? mn[0] : 0.0f, bounded ? mx[0] : 0.0f);
    }

    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
