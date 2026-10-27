// G-SA1 core: the feature "objects" (round 0.9.4: spawnable Rings and Item Boxes; sadc docs/research/gsa1_094_plan.md
// 6.5 with its "Review (adversarial)", gsa1_090_rings.md 4.2 / 4.4 / 4.5, gsa1_094_items.md 5, v1_arch.md 4 / 6). No
// GMod dependency: the module's bind_objects.cpp and the offline tests drive exactly this code.
//
// The game's own objects run in every character world of the client: G-SA1 hands libsa1 SET records (SA1_API_SET,
// libsa1 0.4) and the game's SET manager and spawner make the game's tasks from them. One GMod entity is one OBJECT
// here, and an object is one or more libsa1 records:
//   RING         one record (objexec_RING)
//   O_GRING      a Ring line of 1..128 rings: one record per 8 rings (the game's line of n + 1 rings, n = 7 at most, so
//                every ring has a bit of the 8-bit user flag); a Ring circle of N = 1..128 rings (0.9.4.1): m = N / n
//                records of n rings each, n = the largest of 7..1 that divides N (a game circle record holds at most 7
//                rings with a bit: its 8th ring has none, rings review R.2.7), record k turned about the circle's axis
//                by k * 360 / N degrees, so the game's own circle layout puts record k's ring i at the circle's place
//                (i * m + k) mod N - the union is the evenly spaced N-ring circle (measured with the disc:
//                feat_objects_binding_test)
//   ITEMBOX      one record, upright (the game draws the ground box upright and its cylinder is vertical: decision 10)
//   ITEMBOX_AIR  one record, the entity's full rotation
// Each record's user tag is (object id << 8) | its index, so every libsa1 event names its object and record.
//
// Layout (read from the game's code, not guessed: SADC src/1st_read/code_8C087B80.c):
//   * a line record's ring i (0..n) sits at local z = +ceil(i / 2) * s for odd i, -(i / 2) * s for even i (func_8C087EEE,
//     8C10D148 = ceilf; base vector D_8C159484 = 0): the record's position is the line's ring 0, the others alternate
//     around it, so a record of k rings covers k consecutive places; the object's line is centred on the entity and runs
//     along its forward axis, record g holding the places 8g .. 8g + k - 1;
//   * a circle record's ring i (1..n) sits at (s sin a, 0, s cos a), a = i * 360 / n degrees (func_8C088000); record k
//     of a circle of N rings is turned by k * 360 / N degrees about its local +y (the host's local up: R_k = R_0 Rz(t)),
//     so its ring i lands at the angle (i * m + k) * 360 / N;
//   * both turned by njRotateZ, njRotateX, njRotateY of the SET angles (libsa1: R_sa1 = A^T R_host A).
//   The game's local +z is the host's local -y (host = 4 (x, -z, y)), so every record's host rotation is the entity's
//   rotation times a quarter turn about its up axis: the game's forward (+z) is the entity's forward.
//   MEASURED (0.9.4.1, feat_objects_binding_test with the disc): the game's ring tasks sit within 0.01 HU of
//   ring_positions for lines of 10 / 20 and circles of 7 at yaw 0 / 37 / 90 / 200, pitch 30, roll 45 and (-60, 120, 20),
//   and a touch at each predicted place names exactly that ring's record and bit (the owner's 0.9.4 refusals came from
//   the touch a USERBITS event carries - the record's LAST touched ring, up to ~180 HU from the rings it adds at a run:
//   feat/sh_objects.lua O.CheckEvent).
//
// Units: host space = Source / Hammer units (libsa1's SOURCE preset, 4 HU per SA1 unit); angles: GMod's pitch, yaw, roll
// in degrees; the spacing / radius of a ring group in HU here (SA1 units in the record).
#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "libsa1_internal_api.hpp"

#if !defined(SA1_API_SET)
#error "the G-SA1 feature objects needs libsa1 0.4 (SA1_API_SET, round 0.9.4): snapshot a newer libsa1"
#endif

namespace gsa1 {
struct Character;
namespace objects {

const uint32_t kLineGroup = 8;          // rings per line record (n = 7: bits 0..7 of the game's Sint8 user flag)
const uint32_t kLineMax = 128;          // rings of a Ring line entity (16 records; 0.9.4: 64)
const uint32_t kCircleGroup = 7;        // rings per circle record at most (a game circle's 8th ring has no bit)
const uint32_t kCircleMax = 128;        // rings of a Ring circle entity (0.9.4: 7, one record)
const uint32_t kMaxRecords = 128;       // records per object (a circle of a prime N > 7: N records of 1; 0.9.4: 8)
const uint32_t kContentsMax = 8;        // item box contents 0..8 (the game's table D_8C1B9BA0)
const float kMinSpacing = 4.0f;         // HU: a ring group's spacing / radius (1 SA1 unit) ...
const float kMaxSpacing = 4000.0f;      // ... to 1000 SA1 units (libsa1's limit)
const float kMaxCoord = 65536.0f;       // HU: positions
const uint32_t kShapeLine = 0, kShapeCircle = 1;

// an object as the host describes it (the flat arguments of gsa1.SetAdd)
struct Desc {
    uint32_t type = 0;                  // SA1_OBJTYPE_*
    float pos[3] = {0.0f, 0.0f, 0.0f};  // HU: the entity's position
    float ang[3] = {0.0f, 0.0f, 0.0f};  // degrees: the entity's pitch, yaw, roll
    // RING: unused. O_GRING: ring count, spacing (line) / radius (circle) in HU, kShapeLine / kShapeCircle.
    // ITEMBOX: contents 0..8, the item panel's start angle (degrees), 0. ITEMBOX_AIR: contents 0..8, 0, 0.
    float p[3] = {0.0f, 0.0f, 0.0f};
};

// a Ring circle of `count` rings (1..kCircleMax) as game records: n rings per record (the largest of 7..1 that divides
// count) and m = count / n records; record k's ring i (1..n) is the circle's place (i * m + k) mod count
void circle_split(uint32_t count, uint32_t &n, uint32_t &m);

// GMod's angles -> a host rotation matrix (row-major; its columns are the entity's forward, left and up: Source's
// AngleMatrix)
void angle_matrix(const float ang_deg[3], float m[9]);
// the record rotation of an entity: angle_matrix x a quarter turn about up (the game's +z is the entity's forward)
void record_matrix(const float ang_deg[3], float m[9]);

// the records of d (host space, params as the game reads them), user tags (object << 8) | index; false with err when
// d cannot be an object (unknown type, a count or contents out of range, numbers that are not finite)
bool make_records(const Desc &d, float hu_per_unit, uint32_t object, std::vector<sa1_set_record> &out, std::string &err);
// how many records d makes (0 for a bad d)
uint32_t record_count(const Desc &d);

// where the game puts the rings of a RING / O_GRING object (host space): per ring its record, its bit in the record's
// user flag (RING: 0) and its place along the object (a line: 0 .. count - 1 from the back; a circle: 0 .. count - 1,
// place p at p * 360 / count degrees from the entity's forward towards its left)
struct RingPos {
    uint32_t record = 0;
    uint32_t bit = 0;
    uint32_t place = 0;
    float pos[3] = {0.0f, 0.0f, 0.0f};
};
bool ring_positions(const Desc &d, std::vector<RingPos> &out);

// where the records go: libsa1 in the module (bind_objects.cpp), a recorder in the tests
class Sink {
public:
    virtual ~Sink() {}
    virtual sa1_status add(const sa1_set_record &r, uint32_t &id) = 0;
    virtual sa1_status update(uint32_t id, const sa1_set_record &r) = 0;
    virtual sa1_status remove(uint32_t id) = 0;
    virtual sa1_status state(uint32_t id, uint32_t state, uint32_t bits) = 0;
    virtual std::string error() { return std::string(); }   // the last failure's text (libsa1's sa1_last_error)
};

// a libsa1 SET event mapped to its object
struct Event {
    uint32_t object = 0;                // the object id
    uint64_t user = 0;                  // the host's tag of the object (G-SA1: the entity index)
    uint32_t index = 0;                 // its record (0 .. records - 1)
    uint32_t type = 0;                  // the object's SA1_OBJTYPE_*
    sa1_set_event ev{};
};

struct Obj {
    uint32_t id = 0;
    uint64_t user = 0;
    Desc desc;
    uint32_t state = SA1_SET_STATE_PRESENT;     // the host's state word (every record)
    std::vector<uint32_t> records;              // libsa1 record ids, by index
    std::vector<uint32_t> bits;                 // the host's user bits per record (O_GRING)
};

struct Stats {
    uint64_t adds = 0, updates = 0, removes = 0, states = 0, remakes = 0, failures = 0, forgets = 0, events = 0,
             dropped = 0;
    std::string last_error;
};

// the objects of one libsa1 context
class Registry {
public:
    // the context the records belong to: another context (or none) forgets every object - they went with the old one
    void bind(const void *ctx);
    // forgets every object without calling the sink (the context is gone or going); raises the generation
    void forget();
    // a new object; id: its object id (never 0). state: its first state word (SA1_SET_STATE_*); the records are added
    // and, when state is not PRESENT alone, given it. Nothing stays added on a failure.
    sa1_status add(const Desc &d, uint64_t user, uint32_t state, Sink &s, uint32_t &id, std::string &err);
    // a new place / description: the records updated (libsa1 frees a live task and makes it again at the new place),
    // records added or removed when the count changes (a longer or shorter line); state and bits are kept
    sa1_status update(uint32_t id, const Desc &d, Sink &s, std::string &err);
    // removes every record of the object (silent)
    sa1_status remove(uint32_t id, Sink &s);
    // the shared state: index < 0 - the state word for every record (each with its own bits); index 0..records-1 - the
    // state word and that record's bits. A group whose bits went DOWN (a respawn, a reset: libsa1's state only adds
    // bits) is made again from the registry (sa1_set_update of the same record)
    sa1_status set_state(uint32_t id, uint32_t state, int32_t index, uint32_t bits, Sink &s, std::string &err);
    // removes every object; returns how many
    size_t clear(Sink &s);
    // an event of libsa1 -> its object (false: not one of this registry's records - dropped)
    bool map(const sa1_set_event &e, Event &out);
    const Obj *find(uint32_t id) const;
    size_t size() const { return objs_.size(); }
    size_t record_total() const;
    uint32_t generation() const { return gen_; }
    const Stats &stats() const { return st_; }
    float hu_per_unit = 4.0f;

private:
    const void *ctx_ = nullptr;
    std::map<uint32_t, Obj> objs_;
    uint32_t next_ = 1;
    uint32_t gen_ = 1;
    Stats st_;
};

// the host-space box of the SA1_DRAW_OBJECT draws of a character's last render (triangles, sprites with their size,
// lines); false when it drew none
bool object_draw_bounds(const Character &c, float mn[3], float mx[3]);

}  // namespace objects
}  // namespace gsa1
