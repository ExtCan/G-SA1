// G-SA1 core: the mouth table (see mouth.hpp). The numbers are phoneme_plan.md 4.3 exactly (key indices and weights, as
// measured in phoneme_shapes.md 4 / 5 and SADC/build/research/phoneme/visemes.json; review R.1 fv_level, R.15 Amy's "ee").
// Not game data: a key number names one of the character's face shapes on the owner's disc.
#include "mouth.hpp"

#include <cmath>

#include "viseme.hpp"

namespace gsa1 {
namespace mouth {

namespace {

Entry E(int a, int b, float w, uint8_t how, uint8_t x = 0)
{
    Entry e;
    e.a = a;
    e.b = b;
    e.w = w;
    e.how = how;
    e.expression = x;
    e.present = 1;
    return e;
}
Entry closed() { return E(0, 0, 0.0f, CLOSED); }
Entry S(int a, int b, float w) { return E(a, b, w, SCALES); }
Entry F(int a, int b, float w) { return E(a, b, w, FIXED); }
Entry FX(int a, int b, float w) { return E(a, b, w, FIXED, 1); }
Entry L() { return E(-1, -1, 0.0f, LADDER); }
Entry none() { return Entry(); }

Row R(Entry normal, Entry quiet = none(), Entry loud = none(), Entry plain = none())
{
    Row r;
    r.normal = normal;
    r.quiet = quiet;
    r.loud = loud;
    r.plain = plain;
    return r;
}

Table make(int kind, int keys, float floor, float ladder_cap, float fv_level)
{
    Table t;
    t.kind = kind;
    t.keys = keys;
    t.floor = floor;
    t.ladder_cap = ladder_cap;
    t.fv_level = fv_level;
    t.rows[viseme::SIL] = R(closed());
    t.rows[viseme::MBP] = R(closed());
    t.rows[viseme::FV] = R(L());
    return t;
}

// phoneme_plan.md 4.3, column by column
struct Tables {
    Table sonic, tails, knuckles, amy, big;
    Tables()
    {
        using namespace viseme;
        // Sonic (21 keys; floor 0.8; the ladder 0 4 16: cap 0.5 = key 4; fv_level 0.25)
        sonic = make(0, 21, 0.8f, 0.5f, 0.25f);
        sonic.rows[AA] = R(FX(4, 16, 0.30f), F(0, 7, 1.0f), FX(4, 16, 0.60f), F(0, 7, 1.0f));
        sonic.rows[EH] = R(S(0, 4, 1.0f));
        sonic.rows[EE] = R(S(0, 4, 1.0f));
        sonic.rows[OH] = R(FX(6, 16, 0.40f), F(6, 7, 0.30f), none(), F(6, 7, 0.30f));
        sonic.rows[OO] = R(F(0, 6, 1.0f));
        sonic.rows[SS] = R(S(0, 4, 0.50f));
        // Tails (20 keys; the ladder 0 4 7 8: cap 0.667 = key 7; fv_level 1/6)
        tails = make(2, 20, 0.0f, 0.667f, 0.1667f);
        tails.rows[AA] = R(S(0, 16, 1.0f), none(), FX(16, 8, 0.50f));
        tails.rows[EH] = R(S(0, 4, 1.0f));
        tails.rows[EE] = R(S(0, 6, 1.0f));
        tails.rows[OH] = R(S(0, 7, 1.0f));
        tails.rows[OO] = R(S(0, 5, 1.0f));
        tails.rows[SS] = R(S(0, 4, 1.0f));
        // Knuckles (20 keys; floor 0.8; the ladder 0 4 7 16: cap 0.667 = key 7; fv_level 1/6)
        knuckles = make(3, 20, 0.8f, 0.667f, 0.1667f);
        knuckles.rows[AA] = R(FX(7, 16, 0.30f), F(0, 7, 1.0f), FX(7, 16, 0.60f), F(0, 7, 1.0f));
        knuckles.rows[EH] = R(S(0, 5, 1.0f));
        knuckles.rows[EE] = R(S(0, 5, 1.0f));
        knuckles.rows[OH] = R(FX(7, 14, 0.30f), F(0, 7, 1.0f), none(), F(0, 7, 1.0f));
        knuckles.rows[OO] = R(F(0, 7, 1.0f));
        knuckles.rows[SS] = R(S(0, 4, 1.0f));
        // Amy (20 keys; the ladder 0 7 4 8 16: cap 1; fv_level 1/8)
        amy = make(5, 20, 0.0f, 1.0f, 0.125f);
        amy.rows[AA] = R(S(0, 8, 1.0f), none(), F(8, 16, 0.50f));
        amy.rows[EH] = R(S(0, 7, 1.0f));
        amy.rows[EE] = R(S(0, 10, 1.0f), S(0, 5, 1.0f));
        amy.rows[OH] = R(F(4, 6, 0.30f), S(0, 4, 1.0f));
        amy.rows[OO] = R(S(0, 6, 1.0f));
        amy.rows[SS] = R(S(0, 7, 1.0f));
        // Big (8 keys, one jaw-drop shape; the ladder 0 4 5: cap 1; fv_level 1/8)
        big = make(7, 8, 0.0f, 1.0f, 0.125f);
        big.rows[AA] = R(S(0, 4, 1.0f), none(), S(0, 5, 1.0f));
        big.rows[EH] = R(S(0, 4, 0.40f));
        big.rows[EE] = R(S(0, 4, 0.40f));
        big.rows[OH] = R(S(0, 4, 0.70f));
        big.rows[OO] = R(S(0, 4, 0.30f));
        big.rows[SS] = R(S(0, 4, 0.40f));
    }
};

const Tables &tables()
{
    static const Tables t;     // constant data, built once (C++11 thread-safe static)
    return t;
}

float clamp01(float v)
{
    return v > 0.0f ? (v < 1.0f ? v : 1.0f) : 0.0f;    // NaN -> 0
}

}  // namespace

const Table *table(int kind)
{
    const Tables &t = tables();
    switch (kind) {
    case 0: return &t.sonic;
    case 2: return &t.tails;
    case 3: return &t.knuckles;
    case 5: return &t.amy;
    case 7: return &t.big;
    default: return nullptr;
    }
}

const Entry *entry(int kind, int cls, int variant, bool big)
{
    const Table *t = table(kind);
    if (!t || cls < 0 || cls >= viseme::COUNT) {
        return nullptr;
    }
    const Row &r = t->rows[cls];
    const Entry *e = &r.normal;
    if (variant == VARIANT_QUIET && r.quiet.present) {
        e = &r.quiet;
    } else if (variant == VARIANT_LOUD && r.loud.present) {
        e = &r.loud;
    }
    if (e->expression && !big) {
        if (r.plain.present) {
            e = &r.plain;
        } else if (r.quiet.present) {
            e = &r.quiet;
        } else if (!r.normal.expression) {
            e = &r.normal;
        }
    }
    return e;
}

void pick(int kind, int cls, float s, float size, int variant, bool big, int &a, int &b, float &w)
{
    a = b = 0;
    w = 0.0f;
    const Table *t = table(kind);
    const Entry *e = entry(kind, cls, variant, big);
    if (!t || !e) {
        return;
    }
    s = clamp01(s);
    size = clamp01(size);
    switch (e->how) {
    case SCALES: {
        float f = 1.0f - size;
        if (f < t->floor) {
            f = t->floor;
        }
        a = e->a;
        b = e->b;
        w = clamp01(e->w * (f + (1.0f - f) * s));
        break;
    }
    case FIXED:
        a = e->a;
        b = e->b;
        w = clamp01(e->w);
        break;
    case LADDER:
        a = b = -1;
        w = s < t->fv_level ? s : t->fv_level;
        break;
    default:    // CLOSED
        break;
    }
}

const char *how_name(uint8_t how)
{
    switch (how) {
    case CLOSED: return "closed";
    case SCALES: return "scales";
    case FIXED: return "fixed";
    case LADDER: return "ladder";
    default: return "?";
    }
}

}  // namespace mouth
}  // namespace gsa1
