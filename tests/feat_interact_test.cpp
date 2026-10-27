// feat_interact_test: the interaction feature's core (src/core/interact.*; sadc docs/libsa1_interaction.md 2-3 and the
// addendum, plan gsa1_rounds_plan.md 9.3 with the owner's additions), offline. build.py links it like core_test (the
// core and libsa1) and runs it with --gdi when there is one.
//
//   feat_interact_test [--gdi GAME.gdi] [--verbose]
//
// Without the disc: make_desc (validation, clamping, degrees -> radians, the HOLDABLE body limit, the round-5 tails),
// summarize (contacts folded per entity: unknown objects dropped, the strongest side contact, landings, damaged input).
// With the disc, through gsa1::Session on a flat floor (the module's code path):
//   * the Registry: an ENEMY sphere (a "zombie": the entity index as the user tag) ahead of Sonic; the same description
//     again is not sent, an unchanged move is not sent; Sonic runs and jumps on it: one HIT naming the entity, SPIN,
//     BOUNCED; removed KILLED; a new context forgets every id;
//   * a HOLDABLE box prop registered the way the addon does (its OBB centre, a BOX shape): the action button lifts it
//     (LIFTED names the entity, sa1_character_held the object), a run and the action button throw it (RELEASED THROW);
//   * a BALLOON: the homing attack onto it -> HIT HOMING LAUNCHED (the owner's balloons, decision 7);
//   * the owner's pushing props (addition A): a physics prop's box as a moving object (Movers, entity 55); Sonic runs
//     into it -> contacts folded to entity 55 through Movers::entity_of, SIDE, the approach speed of the run; pushing on
//     -> side contacts every game pair (the slow approach speed of pushing on); standing on it -> LANDING / RIDING only
//     (standing on a prop never shoves it); a spin dash at it: the game stops the ball short of the crate without a
//     contact - the speed collapse the addon's roll-impact rule (cl_interact.lua I.RollImpact) turns into a push.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "../src/core/interact.hpp"
#include "../src/core/session.hpp"
#include "../src/core/shape.hpp"
#include "../src/core/util.hpp"

using namespace gsa1;
using namespace gsa1::interact;

static int g_fail = 0, g_checks = 0;
static bool g_verbose = false;

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

static const double kPi = 3.14159265358979323846;

static ObjArgs sphere_args(int32_t ent, uint32_t kind, float x, float y, float z, float r)
{
    ObjArgs a;
    a.ent = ent;
    a.kind = kind;
    a.pos[0] = x;
    a.pos[1] = y;
    a.pos[2] = z;
    a.nshapes = 1;
    a.shapes[0].form = SA1_SHAPE_SPHERE;
    a.shapes[0].size[0] = r;
    return a;
}

// ---- 1. descriptions --------------------------------------------------------------------------------------------------
static void test_desc()
{
    std::printf("descriptions (make_desc)\n");
    sa1_hostobj_desc d;
    std::string e;
    ObjArgs a = sphere_args(77, SA1_HOSTOBJ_ENEMY, 10, 20, 30, 18);
    a.yaw_deg = 370.0f;
    bool ok = make_desc(a, d, e);
    CHECK(ok && d.struct_size == sizeof d && d.kind == SA1_HOSTOBJ_ENEMY && d.user == 77u && d.num_shapes == 1 &&
              d.position[2] == 30.0f && std::fabs(d.yaw - (float)(10.0 * kPi / 180.0)) < 1e-5f && d.armor == -1 &&
              d.touch == -1 && d.shapes[0].size[0] == 18.0f,
          "an ENEMY sphere: user = the entity index (%llu), 370 degrees -> %.4f rad, armor / touch the kind's default",
          (unsigned long long)d.user, (double)d.yaw);
    int bad = 0;
    std::string why;
    auto refuse = [&](ObjArgs x, const char *what) {
        std::string err;
        sa1_hostobj_desc t;
        if (!make_desc(x, t, err)) {
            bad++;
            why += std::string(what) + ": " + err + "; ";
        }
    };
    ObjArgs b = a;
    b.ent = 0;
    refuse(b, "entity 0");
    b = a;
    b.kind = 7;
    refuse(b, "kind 7");
    b = a;
    b.flags = 0x80000u;
    refuse(b, "flags");
    b = a;
    b.pos[1] = NAN;
    refuse(b, "NaN");
    b = a;
    b.pos[0] = 1e6f;
    refuse(b, "far");
    b = a;
    b.nshapes = 0;
    refuse(b, "no shape");
    b = a;
    b.nshapes = 5;
    refuse(b, "5 shapes");
    b = a;
    b.shapes[0].size[0] = 0.0f;
    refuse(b, "radius 0");
    b = a;
    b.shapes[0].form = 2;
    refuse(b, "form 2");
    b = a;
    b.armor = 4;
    refuse(b, "armor 4");
    b = a;
    b.cooldown = 4000;
    refuse(b, "cooldown");
    b = a;
    b.shapes[0].form = SA1_SHAPE_CYLINDER;
    refuse(b, "a cylinder without a height");
    CHECK(bad == 12, "refused: entity 0, kind 7, unknown flags, NaN, beyond 65536, 0 and 5 shapes, radius 0, form 2, armor "
          "4, cooldown 4000, a cylinder without its height (%d of 12)", bad);
    if (g_verbose) {
        INFO("%s", why.c_str());
    }
    b = a;
    b.shapes[0].size[0] = 2.0f;
    sa1_hostobj_desc t1, t2;
    make_desc(b, t1, e);
    b.shapes[0].size[0] = 9000.0f;
    make_desc(b, t2, e);
    CHECK(t1.shapes[0].size[0] == kMinSize && t2.shapes[0].size[0] == kMaxSize,
          "sizes clamped to 16..4000 HU (4..1000 SA1 units): 2 -> %.0f, 9000 -> %.0f", (double)t1.shapes[0].size[0],
          (double)t2.shapes[0].size[0]);
    ObjArgs h;
    h.ent = 5;
    h.kind = SA1_HOSTOBJ_HOLDABLE;
    h.nshapes = 1;
    h.shapes[0].form = SA1_SHAPE_BOX;
    h.shapes[0].size[0] = 200.0f;
    h.shapes[0].size[1] = 100.0f;
    h.shapes[0].size[2] = 20.0f;
    h.grab_reach = 12.0f;
    h.launch_speed = 500.0f;
    sa1_hostobj_desc hd;
    ok = make_desc(h, hd, e);
    float hr = std::sqrt(hd.shapes[0].size[0] * hd.shapes[0].size[0] + hd.shapes[0].size[1] * hd.shapes[0].size[1]);
    CHECK(ok && hr <= kMaxHoldSize && hd.shapes[0].size[0] / hd.shapes[0].size[1] > 1.99f && hd.grab_reach == 12.0f &&
              hd.launch_speed == 0.0f,
          "a HOLDABLE box 400 x 200: scaled to a horizontal half diagonal of %.1f HU (at most 128, the proportions kept); "
          "its grab reach kept, a launch speed only for balloons", (double)hr);
    ObjArgs bl = sphere_args(9, SA1_HOSTOBJ_BALLOON, 0, 0, 0, 20);
    bl.launch_speed = 900.0f;
    bl.grab_reach = 5.0f;
    bl.flags = SA1_HOSTOBJ_POP_ON_TOUCH | SA1_HOSTOBJ_LAUNCH_BOUNCE;
    sa1_hostobj_desc bd;
    ok = make_desc(bl, bd, e);
    CHECK(ok && bd.launch_speed == 900.0f && bd.grab_reach == 0.0f && bd.flags == bl.flags,
          "a BALLOON keeps its launch speed and flags (POP_ON_TOUCH | LAUNCH_BOUNCE)");
}

// ---- 2. contacts folded per entity ----------------------------------------------------------------------------------------
static sa1_contact contact(uint32_t obj, uint32_t type, uint32_t flags, float nx, float ny, float nz, float vx, float vy,
                           float vz, float depth, uint32_t step)
{
    sa1_contact c;
    std::memset(&c, 0, sizeof c);
    c.character = 1;
    c.object = obj;
    c.type = type;
    c.flags = flags;
    c.step = step;
    c.normal[0] = nx;
    c.normal[1] = ny;
    c.normal[2] = nz;
    c.velocity[0] = vx;
    c.velocity[1] = vy;
    c.velocity[2] = vz;
    c.point[0] = 100.0f;
    c.depth = depth;
    return c;
}

static void test_summarize()
{
    std::printf("contacts folded per entity (summarize)\n");
    std::vector<sa1_contact> c;
    // object 3 = entity 55 (chunk 1): a side contact at 600 HU/s, then two slower ones while pushing
    c.push_back(contact(3, SA1_CONTACT_SIDE, SA1_CONTACTF_FIRST | SA1_CONTACTF_WALL, -1, 0, 0, 600, 0, 0, 0.5f, 10));
    c.push_back(contact(3, SA1_CONTACT_SIDE, SA1_CONTACTF_WALL, -1, 0, 0, 40, 0, 0, 0.9f, 11));
    // object 8 = entity 70: standing on it
    c.push_back(contact(8, SA1_CONTACT_LANDING, SA1_CONTACTF_RIDING, 0, 0, 1, 0, 0, -10, 0.2f, 10));
    c.push_back(contact(8, SA1_CONTACT_LANDING, SA1_CONTACTF_RIDING, 0, 0, 1, 0, 0, -10, 0.2f, 11));
    // object 4 (not an entity's: parked or another host's) and a damaged one
    c.push_back(contact(4, SA1_CONTACT_SIDE, 0, 0, 1, 0, 0, -300, 0, 0.3f, 11));
    sa1_contact nan_c = contact(3, SA1_CONTACT_SIDE, 0, NAN, 0, 0, 900, 0, 0, 0.1f, 11);
    c.push_back(nan_c);
    // object 3 again from below (HEAD), slower than the side contact
    c.push_back(contact(3, SA1_CONTACT_HEAD, 0, 0, 0, -1, 0, 0, 100, 1.5f, 12));
    auto lookup = [](uint32_t obj, int32_t &ent, uint32_t &chunk) {
        if (obj == 3) { ent = 55; chunk = 1; return true; }
        if (obj == 8) { ent = 70; chunk = 0; return true; }
        return false;
    };
    std::vector<ContactSum> s = summarize(c.data(), c.size(), lookup);
    const ContactSum *a = s.size() >= 1 ? &s[0] : nullptr, *b = s.size() >= 2 ? &s[1] : nullptr;
    CHECK(s.size() == 2 && a && a->ent == 55 && a->chunk == 1 && b && b->ent == 70,
          "two entities (55 first, 70); the unknown object and the NaN contact dropped (%zu entries)", s.size());
    if (a && b) {
        CHECK(a->steps == 3 && a->side == 2 && a->head == 1 && a->first == 1 && a->wall == 2 && a->type == SA1_CONTACT_SIDE &&
                  a->vin == 600.0f && a->normal[0] == -1.0f && a->depth == 1.5f && a->last_step == 12,
              "entity 55: 3 steps (2 side, 1 head), the strongest is the first side contact (approach %.0f HU/s, normal "
              "-x), deepest %.1f", (double)a->vin, (double)a->depth);
        CHECK(b->landing == 2 && b->riding == 2 && b->side == 0 && b->type == SA1_CONTACT_LANDING && b->vin == 0.0f &&
                  b->normal[2] == 1.0f,
              "entity 70: 2 landings, riding, no approach speed (standing on a prop pushes nothing)");
    }
    CHECK(summarize(nullptr, 5, lookup).empty() && summarize(c.data(), c.size(), nullptr).empty(),
          "no contacts / no lookup: nothing");
}

// ---- 3. through gsa1::Session (the disc) ----------------------------------------------------------------------------------
static std::vector<sa1_collision_tri> flat_floor(float half, float tile, float z)
{
    std::vector<sa1_collision_tri> out;
    for (float x0 = -half; x0 < half - 0.5f; x0 += tile) {
        for (float y0 = -half; y0 < half - 0.5f; y0 += tile) {
            float x1 = x0 + tile, y1 = y0 + tile;
            sa1_collision_tri a = {{{x0, y0, z}, {x1, y0, z}, {x1, y1, z}}, SA1_SURFACE_SOLID};
            sa1_collision_tri b = {{{x0, y0, z}, {x1, y1, z}, {x0, y1, z}}, SA1_SURFACE_SOLID};
            out.push_back(a);
            out.push_back(b);
        }
    }
    return out;
}

static std::vector<sa1_hostobj_event> poll_ho(Session &s)
{
    std::vector<sa1_hostobj_event> out;
    sa1_hostobj_event buf[64];
    for (int round = 0; round < 16; round++) {
        uint32_t n = 0;
        if (sa1_poll_hostobj_events(s.ctx(), buf, 64, &n) != SA1_OK || n == 0) {
            break;
        }
        out.insert(out.end(), buf, buf + n);
        if (n < 64) {
            break;
        }
    }
    return out;
}

static const sa1_hostobj_event *find_ev(const std::vector<sa1_hostobj_event> &v, uint32_t type, uint64_t user)
{
    for (const sa1_hostobj_event &e : v) {
        if (e.type == type && e.user == user) {
            return &e;
        }
    }
    return nullptr;
}

// one pair at a time (the module's ticks run whole pairs); the stick is camera-relative with camera yaw 0
static bool pair(Session &s, int32_t id, float sy, uint32_t b)
{
    return s.tick(id, 0.0f, sy, 0.0f, b, 1.0f / 30.0f) == SA1_OK;
}

static void settle(Session &s, int32_t id, int n)
{
    for (int i = 0; i < n; i++) {
        pair(s, id, 0.0f, 0);
    }
}

static void test_registry(Session &s)
{
    std::printf("the Registry: an enemy, a held prop, a balloon\n");
    Registry R;
    std::string e;
    float start[3] = {0.0f, 0.0f, 8.0f};
    int32_t id = s.create(SA1_CHAR_SONIC, start, 0.0f, e);
    CHECK(id > 0, "Sonic on the flat floor (%s)", e.c_str());
    if (id <= 0) {
        return;
    }
    settle(s, id, 20);
    Character *c = s.get(id);
    float x0 = c->st.position[0], y0 = c->st.position[1];
    // a "zombie" as the addon registers an NPC (cl_interact.lua): a vertical cylinder from its OBB (32 x 32 x 72 HU:
    // radius 0.4 x the mean width, half its height, centred on the OBB's centre), 120 HU ahead
    ObjArgs z = sphere_args(101, SA1_HOSTOBJ_ENEMY, x0 + 120.0f, y0, 0.0f, 12.8f);
    z.flags = SA1_HOSTOBJ_SOLID;
    z.shapes[0].form = SA1_SHAPE_CYLINDER;
    z.shapes[0].size[1] = 36.0f;
    z.shapes[0].center[2] = 36.0f;
    uint32_t oid = 0, oid2 = 0;
    bool added = false, added2 = true;
    sa1_status st = R.set(s.ctx(), z, oid, &added, e);
    sa1_status st2 = R.set(s.ctx(), z, oid2, &added2, e);
    float p[3] = {x0 + 120.0f, y0, 0.0f};
    R.move(s.ctx(), 101, p, 0.0f);
    int32_t back = 0;
    CHECK(st == SA1_OK && added && oid != 0 && st2 == SA1_OK && !added2 && oid2 == oid && R.stats().unchanged == 1 &&
              R.stats().moves_skipped == 1 && R.ent_of(oid, back) && back == 101 && R.size() == 1,
          "entity 101 registered (id %u); the same description again and an unchanged move are not sent", (unsigned)oid);
    std::vector<sa1_hostobj_event> all;
    bool pressed = false;
    for (int i = 0; i < 120 && !find_ev(all, SA1_HOSTOBJ_EVENT_HIT, 101); i++) {
        uint32_t b = 0;
        if (!pressed && s.get(id)->st.position[0] >= z.pos[0] - 40.0f) {
            b = SA1_BUTTON_JUMP;
            pressed = true;
        }
        if (g_verbose && i < 40) {
            const Character *cc = s.get(id);
            std::printf("        pair %d: x %.1f z %.1f mode %d flag 0x%X%s\n", i, (double)cc->st.position[0],
                        (double)cc->st.position[2], (int)cc->st.mode, (unsigned)cc->st.game_flags, b ? " JUMP" : "");
        }
        pair(s, id, 1.0f, b);
        std::vector<sa1_hostobj_event> ev = poll_ho(s);
        all.insert(all.end(), ev.begin(), ev.end());
    }
    if (g_verbose) {
        INFO("after the run: Sonic at %.1f %.1f %.1f (yaw %.3f), the enemy at %.1f %.1f %.1f; %zu events",
             (double)s.get(id)->st.position[0], (double)s.get(id)->st.position[1], (double)s.get(id)->st.position[2],
             (double)s.get(id)->st.yaw, (double)z.pos[0], (double)z.pos[1], (double)z.pos[2], all.size());
    }
    const sa1_hostobj_event *h = find_ev(all, SA1_HOSTOBJ_EVENT_HIT, 101);
    CHECK(h && h->object == oid && h->attack == SA1_ATTACK_SPIN && (h->flags & SA1_HITF_BOUNCED) && h->character == id,
          "Sonic runs and jumps on it: HIT naming entity 101, attack %u (SPIN), flags 0x%X (BOUNCED)",
          h ? (unsigned)h->attack : 99u, h ? (unsigned)h->flags : 0u);
    CHECK(R.remove(s.ctx(), 101, true) && !R.remove(s.ctx(), 101, false) && R.size() == 0,
          "removed KILLED; a second removal finds nothing");
    settle(s, id, 30);
    // a HOLDABLE box prop, registered as the addon does: position = its OBB centre, one BOX shape (half extents)
    c = s.get(id);
    float yaw = c->st.yaw;
    float px = c->st.position[0] + 40.0f * std::cos(yaw), py = c->st.position[1] + 40.0f * std::sin(yaw);
    ObjArgs hb;
    hb.ent = 202;
    hb.kind = SA1_HOSTOBJ_HOLDABLE;
    hb.flags = SA1_HOSTOBJ_NOT_SOLID;
    hb.pos[0] = px;
    hb.pos[1] = py;
    hb.pos[2] = c->st.position[2] + 10.0f;
    hb.nshapes = 1;
    hb.shapes[0].form = SA1_SHAPE_BOX;
    hb.shapes[0].size[0] = hb.shapes[0].size[1] = hb.shapes[0].size[2] = 10.0f;
    uint32_t hid = 0;
    st = R.set(s.ctx(), hb, hid, &added, e);
    CHECK(st == SA1_OK && hid != 0, "a HOLDABLE box prop (20 HU, its centre 40 HU ahead) registered (%s)", e.c_str());
    settle(s, id, 2);
    all.clear();
    int took = 0;
    for (int i = 0; i < 40 && !took; i++) {
        pair(s, id, 0.0f, i == 0 ? SA1_BUTTON_ACTION : 0u);
        std::vector<sa1_hostobj_event> ev = poll_ho(s);
        all.insert(all.end(), ev.begin(), ev.end());
        took = find_ev(all, SA1_HOSTOBJ_EVENT_LIFTED, 202) ? i + 1 : 0;
    }
    sa1_hostobj_held held;
    std::memset(&held, 0, sizeof held);
    held.struct_size = sizeof held;
    sa1_character_held(s.ctx(), id, &held);
    CHECK(took > 0 && held.object == hid && s.get(id)->st.held_object == hid,
          "the action button lifts it: LIFTED (entity 202) after %d pairs; sa1_character_held: the object, phase %u", took,
          (unsigned)held.phase);
    all.clear();
    const sa1_hostobj_event *rel = nullptr;
    // 0.9.3a (the owner's 0.9.2 note "Moving while carrying objects causes the object to jitter"; sadc
    // docs/research/super_general_design.md 4.12 / 6.7, D13): within each pair of the run, the prop's offset along the run
    // from the body's render root at alpha 0 and at alpha 1. The drawn steps (sa1_hostobj_held.drawn_prev -> drawn, what
    // cl_interact.lua's DrawHeld interpolates now) keep it constant; the last pair's two steps (position_prev -> position,
    // 0.9.3) give the 30 Hz sawtooth.
    double sum_d = 0.0, sum_o = 0.0, worst_d = 0.0;
    int n_d = 0, over_d = 0;
    auto along = [](const float pt[3], const float root[3], float yaw) {
        return (double)(pt[0] - root[0]) * std::cos((double)yaw) + (double)(pt[1] - root[1]) * std::sin((double)yaw);
    };
    for (int i = 0; i < 25; i++) {
        pair(s, id, 1.0f, 0);
#if defined(SA1_API_SUPER_GENERAL)
        if (i < 5) {
            continue;       // the carry pose settles (the walk -> run carry actions)
        }
        sa1_hostobj_held hd;
        std::memset(&hd, 0, sizeof hd);
        hd.struct_size = sizeof hd;
        if (sa1_character_held(s.ctx(), id, &hd) != SA1_OK || hd.object != hid) {
            continue;
        }
        const Character *hc = s.get(id);
        s.render(id, 0.0f);
        float p0[3] = {hc->r_pos[0], hc->r_pos[1], hc->r_pos[2]}, y0 = hc->r_yaw;
        s.render(id, 1.0f);
        float p1[3] = {hc->r_pos[0], hc->r_pos[1], hc->r_pos[2]}, y1 = hc->r_yaw;
        double fd = std::fabs(along(hd.drawn, p1, y1) - along(hd.drawn_prev, p0, y0));
        double fo = std::fabs(along(hd.position, p1, y1) - along(hd.position_prev, p0, y0));
        sum_d += fd;
        sum_o += fo;
        worst_d = std::max(worst_d, fd);
        over_d += fd >= 0.04;
        n_d++;
#endif
    }
#if defined(SA1_API_SUPER_GENERAL)
    CHECK(n_d >= 15 && sum_d / n_d < 0.05 && over_d <= 3 && sum_o / n_d > 1.0,
          "carried at a run (%d pairs): the prop's offset from the body within a pair, drawn_prev -> drawn %.4f HU mean "
          "(worst %.4f, %d over 0.04: the carry pose changing), position_prev -> position %.2f HU mean (the 0.9.3 sawtooth)",
          n_d, n_d ? sum_d / n_d : -1.0, worst_d, over_d, n_d ? sum_o / n_d : -1.0);
#endif
    for (int i = 0; i < 60 && !rel; i++) {
        pair(s, id, 1.0f, i == 0 ? SA1_BUTTON_ACTION : 0u);
        std::vector<sa1_hostobj_event> ev = poll_ho(s);
        all.insert(all.end(), ev.begin(), ev.end());
        rel = find_ev(all, SA1_HOSTOBJ_EVENT_RELEASED, 202);
    }
    CHECK(rel && rel->reason == SA1_RELEASE_THROW && rel->speed > 400.0f,
          "running + the action button: RELEASED THROW at %.0f HU/s (the addon gives the prop this velocity)",
          rel ? (double)rel->speed : -1.0);
    R.remove(s.ctx(), 202, false);
    settle(s, id, 20);
    // a balloon in front, at the height of a jump: jump, then jump again in the air (the homing attack)
    c = s.get(id);
    yaw = c->st.yaw;
    ObjArgs ba = sphere_args(303, SA1_HOSTOBJ_BALLOON, c->st.position[0] + 160.0f * std::cos(yaw),
                             c->st.position[1] + 160.0f * std::sin(yaw), c->st.position[2] + 40.0f, 24.0f);
    uint32_t bid = 0;
    R.set(s.ctx(), ba, bid, &added, e);
    settle(s, id, 2);
    all.clear();
    for (int i = 0; i < 60 && !find_ev(all, SA1_HOSTOBJ_EVENT_HIT, 303); i++) {
        uint32_t b = (i == 0 || i == 6) ? SA1_BUTTON_JUMP : 0u;
        pair(s, id, 0.0f, b);
        std::vector<sa1_hostobj_event> ev = poll_ho(s);
        all.insert(all.end(), ev.begin(), ev.end());
    }
    const sa1_hostobj_event *bh = find_ev(all, SA1_HOSTOBJ_EVENT_HIT, 303);
    CHECK(bh && bh->attack == SA1_ATTACK_HOMING && (bh->flags & SA1_HITF_LAUNCHED),
          "a balloon 40 units ahead: the homing attack hits it (attack %u, flags 0x%X: LAUNCHED)",
          bh ? (unsigned)bh->attack : 99u, bh ? (unsigned)bh->flags : 0u);
    R.clear(s.ctx());
    uint32_t g0 = R.generation();
    uint32_t x = 0, x2 = 0;
    R.set(s.ctx(), z, x, &added, e);
    R.bind(nullptr);
    CHECK(R.size() == 0 && R.generation() == g0 + 1 && !R.id_of(101, x2),
          "another context (none): every id forgotten, the generation raised");
    sa1_hostobj_remove(s.ctx(), x, SA1_HOSTOBJ_REMOVE_SILENT);   // (this test's context lives on: tidy up)
    s.destroy(id);
}

// one frame of a script: tick, contacts folded per entity
struct PushRec {
    uint32_t side = 0, landing = 0, head = 0, riding = 0, frames_side = 0, other_ents = 0;
    float vin_first = 0.0f, vin_max = 0.0f, vin_sum = 0.0f;
    uint32_t vin_n = 0;
    float fwd_sum = 0.0f;
};

static void push_frames(Session &s, int32_t id, int frames, float sy, uint32_t b_first, PushRec &R, const char *label)
{
    static const float kCratePos[3] = {400.0f, 0.0f, 0.0f}, kCrateAng[3] = {0.0f, 0.0f, 0.0f};
    for (int i = 0; i < frames; i++) {
        s.movers().update(55, "x:crate", kCratePos, kCrateAng, true, now_ms() / 1000.0);   // the addon does it every frame
        s.commit_movers(now_ms() / 1000.0);
        if (s.tick(id, 0.0f, sy, 0.0f, i == 0 ? b_first : 0u, 1.0f / 60.0f) != SA1_OK) {
            break;
        }
        sa1_contact buf[128];
        uint32_t n = 0;
        sa1_character_contacts(s.ctx(), id, buf, 128, &n);
        auto lookup = [&](uint32_t obj, int32_t &ent, uint32_t &chunk) {
            return s.movers().entity_of(obj, ent, &chunk);
        };
        std::vector<ContactSum> sum = summarize(buf, n, lookup);
        const Character *c = s.get(id);
        if (g_verbose && (i % 10 == 0 || (label[0] == 's' && label[1] == 'p' && i < 12))) {
            std::printf("        %s frame %d: x %.1f y %.1f z %.1f, %u contacts (%zu entities), mode %d\n", label, i,
                        (double)c->st.position[0], (double)c->st.position[1], (double)c->st.position[2], (unsigned)n,
                        sum.size(), (int)c->st.mode);
        }
        for (const ContactSum &k : sum) {
            if (k.ent != 55) {
                R.other_ents++;
                continue;
            }
            R.side += k.side;
            R.landing += k.landing;
            R.head += k.head;
            R.riding += k.riding;
            if (k.side) {
                R.frames_side++;
                if (R.vin_n == 0) {
                    R.vin_first = k.vin;
                }
                R.vin_max = std::max(R.vin_max, k.vin);
                R.vin_sum += k.vin;
                R.vin_n++;
                R.fwd_sum += c->st.player_speed[0] * 240.0f;
            }
            if (g_verbose && (k.side || i < 3)) {
                std::printf("        %s frame %d: %u steps (side %u landing %u head %u riding %u wall %u first %u) vin "
                            "%.0f vout %.0f normal %.2f %.2f %.2f; forward speed %.0f HU/s, mode %d\n",
                            label, i, k.steps, k.side, k.landing, k.head, k.riding, k.wall, k.first, (double)k.vin,
                            (double)k.vout, (double)k.normal[0], (double)k.normal[1], (double)k.normal[2],
                            (double)(c->st.player_speed[0] * 240.0f), (int)c->st.mode);
            }
        }
    }
}

static void test_push(Session &s)
{
    std::printf("pushing props: contacts with a moving object, per entity (owner addition A)\n");
    std::string e;
    // a physics prop's box (a 64 x 64 x 48 HU crate) as the addon hands it to the module: ShapeBox + MoverUpdate
    float mn[3] = {-32.0f, -32.0f, 0.0f}, mx[3] = {32.0f, 32.0f, 48.0f};
    Shape sh;
    bool ok = shape_box(mn, mx, sh, e);
    s.movers().set_shape("x:crate", std::move(sh));
    float pos[3] = {400.0f, 0.0f, 0.0f}, ang[3] = {0.0f, 0.0f, 0.0f};
    float start[3] = {0.0f, 0.0f, 8.0f};
    int32_t id = s.create(SA1_CHAR_SONIC, start, 0.0f, e);
    s.movers().update(55, "x:crate", pos, ang, true, now_ms() / 1000.0);
    s.commit_movers(now_ms() / 1000.0);
    int32_t ent = 0;
    std::vector<uint32_t> ids = s.movers().object_ids();
    bool mapped = !ids.empty() && s.movers().entity_of(ids[0], ent) && ent == 55;
    CHECK(ok && id > 0 && mapped && !s.movers().entity_of(0, ent) && !s.movers().entity_of(999999u, ent),
          "a 64 x 64 x 48 crate as a moving object of entity 55; Movers::entity_of maps its libsa1 object back (unknown "
          "objects: no entity)");
    if (id <= 0 || !mapped) {
        return;
    }
    for (int i = 0; i < 40; i++) {
        s.movers().update(55, "x:crate", pos, ang, true, now_ms() / 1000.0);
        s.commit_movers(now_ms() / 1000.0);
        s.tick(id, 0.0f, 0.0f, 0.0f, 0, 1.0f / 60.0f);
    }
    sa1_contact drain[128];
    uint32_t dn = 0;
    sa1_character_contacts(s.ctx(), id, drain, 128, &dn);
    // run into its side (its face at x 368)
    PushRec run;
    push_frames(s, id, 150, 1.0f, 0, run, "run");
    if (g_verbose) {
        INFO("after the run: Sonic at %.1f %.1f %.1f; movers active %u", (double)s.get(id)->st.position[0],
             (double)s.get(id)->st.position[1], (double)s.get(id)->st.position[2], s.movers().stats().active);
    }
    CHECK(run.side > 0 && run.landing == 0 && run.other_ents == 0 && run.vin_first > 100.0f,
          "Sonic runs into it: %u side contacts over %u frames, none else; the first approach %.0f HU/s (the run's speed "
          "into the crate)", run.side, run.frames_side, (double)run.vin_first);
    INFO("pushing against it: approach speed %.1f HU/s on average (max %.0f), the game's forward speed %.0f HU/s on "
         "average while touching", run.vin_n ? (double)(run.vin_sum / run.vin_n) : 0.0, (double)run.vin_max,
         run.vin_n ? (double)(run.fwd_sum / run.vin_n) : 0.0);
    CHECK(run.side >= 60 && run.frames_side >= 30,
          "pushing on against it keeps reporting: %u side contact steps in %u frames (one report per game pair, two steps "
          "each)", run.side, run.frames_side);
    s.destroy(id);
    // standing on it: landing / riding only
    float top[3] = {400.0f, 0.0f, 80.0f};
    id = s.create(SA1_CHAR_SONIC, top, 0.0f, e);
    PushRec stand;
    for (int i = 0; i < 3; i++) {
        s.movers().update(55, "x:crate", pos, ang, true, now_ms() / 1000.0);
    }
    push_frames(s, id, 90, 0.0f, 0, stand, "stand");
    CHECK(stand.landing >= 60 && stand.riding >= 60 && stand.side == 0 && stand.head == 0,
          "Sonic standing on it: %u landings (%u riding), no side or head contact: the addon pushes nothing",
          stand.landing, stand.riding);
    s.destroy(id);
    // a spin dash into it: a larger approach speed than the run's first contact (rolling pushes harder); the dash
    // covers about 320 HU, so it starts 200 HU from the crate's face
    float near_start[3] = {168.0f, 0.0f, 8.0f};
    id = s.create(SA1_CHAR_SONIC, near_start, 0.0f, e);
    for (int i = 0; i < 20; i++) {
        s.movers().update(55, "x:crate", pos, ang, true, now_ms() / 1000.0);
        s.commit_movers(now_ms() / 1000.0);
        s.tick(id, 0.0f, 0.0f, 0.0f, 0, 1.0f / 60.0f);
    }
    sa1_character_contacts(s.ctx(), id, drain, 128, &dn);
    // charge: hold action, then let go (Sonic's spin dash); the stick forward keeps the roll going
    for (int i = 0; i < 40; i++) {
        s.movers().update(55, "x:crate", pos, ang, true, now_ms() / 1000.0);
        s.commit_movers(now_ms() / 1000.0);
        s.tick(id, 0.0f, 0.0f, 0.0f, SA1_BUTTON_ACTION, 1.0f / 60.0f);
    }
    // the dash: one pair at a time; the game stops a fast ball short of a wall (its sweep finds the wall a step
    // ahead), so the ball never touches the crate and libsa1 reports no contact for the impact: the addon's rule
    // (cl_interact.lua I.RollImpact) - rolling faster than 300 HU/s, the speed down to under 40% within a frame, a
    // physics prop within a step's travel + 48 HU ahead along the old velocity (GMod's own trace) - is the impact
    float v_before = 0.0f, v_after = 0.0f, gap = 0.0f;
    uint32_t impact_contacts = 0;
    bool impact = false, was_ball = false;
    for (int i = 0; i < 40 && !impact; i++) {
        const Character *c0 = s.get(id);
        float v0 = std::sqrt(c0->st.velocity[0] * c0->st.velocity[0] + c0->st.velocity[1] * c0->st.velocity[1]);
        bool ball0 = (c0->st.game_flags & 0x100u) != 0;
        s.movers().update(55, "x:crate", pos, ang, true, now_ms() / 1000.0);
        s.commit_movers(now_ms() / 1000.0);
        s.tick(id, 0.0f, 1.0f, 0.0f, 0, 1.0f / 30.0f);
        uint32_t n = 0;
        sa1_character_contacts(s.ctx(), id, drain, 128, &n);
        impact_contacts += n;
        const Character *c1 = s.get(id);
        float v1 = std::sqrt(c1->st.velocity[0] * c1->st.velocity[0] + c1->st.velocity[1] * c1->st.velocity[1]);
        if (ball0 && v0 > 300.0f && v1 < 0.4f * v0) {
            impact = true;
            was_ball = ball0;
            v_before = v0;
            v_after = v1;
            gap = 368.0f - c1->st.position[0];
        }
    }
    CHECK(impact && was_ball && v_before > 1500.0f && gap > 0.0f && gap < 2.0f * v_before / 60.0f + 48.0f,
          "a spin dash at the crate: the ball stops from %.0f to %.0f HU/s %.0f HU before its face (within a step's travel "
          "+ 48 HU: the addon's roll impact; %u contacts reported in that pair)", (double)v_before, (double)v_after,
          (double)gap, (unsigned)impact_contacts);
    s.destroy(id);
    s.movers().forget(55);
    s.commit_movers(now_ms() / 1000.0 + 10.0);
}

int main(int argc, char **argv)
{
    std::string gdi;
    if (const char *e = std::getenv("SA1_TEST_GDI")) gdi = e;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--gdi" && i + 1 < argc) gdi = argv[++i];
        else if (a == "--verbose") g_verbose = true;
    }
    std::printf("G-SA1 feat_interact_test\n");
    test_desc();
    test_summarize();
    if (gdi.empty()) {
        std::printf("  info  no --gdi / SA1_TEST_GDI: the checks through the game need the disc\n");
    } else {
        Session s;
        std::string e;
        bool ok = s.init(gdi, e);
        CHECK(ok, "the disc (%s)", e.c_str());
        if (ok) {
            std::vector<sa1_collision_tri> floor = flat_floor(8192.0f, 1024.0f, 0.0f);
            ok = s.set_world(floor, e);
            CHECK(ok, "a flat floor (%s)", e.c_str());
        }
        if (ok) {
            test_registry(s);
            test_push(s);
        }
        s.shutdown();
    }
    std::printf("\n%d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
