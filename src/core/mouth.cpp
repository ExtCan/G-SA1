// G-SA1 core: the mouth table (see mouth.hpp). Table v2 (round 0.9.4e, kTableVersion 2) is sadc
// docs/research/lipsync2_show.md 5.2 with lipsync2_plan.md 4.6 and its review R.2 rows (Sonic's quiet "ah" 7>16@.30 F X,
// Amy's "eh" 0>8@.80 S) - 14 rows changed against 0.9.4c's phoneme_plan.md 4.3 (measured in phoneme_shapes.md 4 / 5,
// SADC/build/research/phoneme/visemes.json and lipsync2_show.md 4; review R.1 fv_level, R.15 Amy's "ee"). Not game data:
// the numbers are key indices and weights - a key number names one of the character's face shapes on the owner's disc.
// Also the player's own mouths (set_override, lipsync2_plan.md 4.7) and the measured mouth points (M9).
// Lua thread only (mouth.hpp THREADS): the microphone's thread never calls anything here.
#include "mouth.hpp"

#include <cmath>
#include <cstdio>
#include <cstring>

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
Entry L(float level) { return E(-1, -1, level, LADDER); }
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
    t.rows[viseme::FV] = R(L(fv_level));    // the f v th slit: the ladder kept to fv_level (pick: min(s, w))
    return t;
}

// table v2: lipsync2_plan.md 4.6 (= lipsync2_show.md 5.2 with the review R.2 rows), row by row; "v2" marks the 14 rows that
// changed against 0.9.4c
struct Tables {
    Table sonic, tails, knuckles, amy, big;
    Tables()
    {
        using namespace viseme;
        // Sonic (21 keys; floor 0.8; the ladder 0 4 16: cap 0.5 = key 4; fv_level 0.25). 7 = his flat open talking mouth with
        // fangs, 16 the laugh, 4 the smile with both rows of teeth, 6 the pucker, 5 the lips just apart
        sonic = make(0, 21, 0.8f, 0.5f, 0.25f);
        sonic.rows[AA] = R(FX(7, 16, 0.45f), FX(7, 16, 0.30f), FX(7, 16, 0.75f), F(0, 7, 1.0f));     // v2 (review R.2 quiet)
        sonic.rows[EH] = R(FX(7, 16, 0.20f), none(), none(), F(0, 7, 1.0f));                      // v2
        sonic.rows[EE] = R(S(0, 4, 1.0f));
        sonic.rows[OH] = R(FX(6, 16, 0.40f), F(6, 7, 0.30f), none(), F(6, 7, 0.30f));
        sonic.rows[OO] = R(F(6, 7, 0.20f));                                                        // v2
        sonic.rows[SS] = R(F(5, 4, 0.60f));                                                        // v2
        // Tails (20 keys; the ladder 0 4 7 8: cap 0.667 = key 7; fv_level 1/6)
        tails = make(2, 20, 0.0f, 0.667f, 0.1667f);
        tails.rows[AA] = R(FX(16, 8, 0.50f), S(0, 16, 1.0f), FX(0, 8, 1.0f), S(0, 16, 1.0f));       // v2
        tails.rows[EH] = R(S(0, 4, 1.0f));
        tails.rows[EE] = R(S(0, 6, 1.0f));
        tails.rows[OH] = R(S(0, 7, 1.0f));
        tails.rows[OO] = R(S(0, 5, 0.70f));                                                        // v2
        tails.rows[SS] = R(S(0, 6, 0.60f));                                                        // v2
        // Knuckles (20 keys; floor 0.8; the ladder 0 4 7 16: cap 0.667 = key 7; fv_level 1/6)
        knuckles = make(3, 20, 0.8f, 0.667f, 0.1667f);
        knuckles.rows[AA] = R(FX(7, 16, 0.30f), F(0, 7, 1.0f), FX(7, 16, 0.60f), F(0, 7, 1.0f));
        knuckles.rows[EH] = R(F(4, 7, 0.50f));                                                     // v2
        knuckles.rows[EE] = R(S(0, 5, 1.0f));
        knuckles.rows[OH] = R(FX(7, 14, 0.30f), F(0, 7, 1.0f), none(), F(0, 7, 1.0f));
        knuckles.rows[OO] = R(F(0, 7, 1.0f));
        knuckles.rows[SS] = R(S(0, 4, 1.0f));
        // Amy (20 keys; the ladder 0 7 4 8 16: cap 1; fv_level 1/8)
        amy = make(5, 20, 0.0f, 1.0f, 0.125f);
        amy.rows[AA] = R(S(0, 8, 1.0f), none(), F(8, 16, 0.50f));
        amy.rows[EH] = R(S(0, 8, 0.80f));                                                          // v2 (review R.2)
        amy.rows[EE] = R(S(0, 10, 1.0f), S(0, 5, 1.0f));
        amy.rows[OH] = R(F(4, 6, 0.30f), S(0, 4, 1.0f));
        amy.rows[OO] = R(S(0, 6, 0.60f));                                                          // v2
        amy.rows[SS] = R(S(0, 10, 0.50f));                                                         // v2
        // Big (8 keys, one jaw-drop shape: only the size follows the vowel height; the ladder 0 4 5: cap 1; fv_level 1/8)
        big = make(7, 8, 0.0f, 1.0f, 0.125f);
        big.rows[AA] = R(S(0, 4, 1.0f), none(), S(0, 5, 1.0f));
        big.rows[EH] = R(S(0, 4, 0.55f));                                                          // v2
        big.rows[EE] = R(S(0, 4, 0.35f));                                                          // v2
        big.rows[OH] = R(S(0, 4, 0.70f));
        big.rows[OO] = R(S(0, 4, 0.30f));
        big.rows[SS] = R(S(0, 4, 0.25f));                                                          // v2
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

// the five face kinds' slots of the override tables
int face_slot(int kind)
{
    switch (kind) {
    case 0: return 0;
    case 2: return 1;
    case 3: return 2;
    case 5: return 3;
    case 7: return 4;
    default: return -1;
    }
}

// the player's mouths of one face kind (Lua thread only)
struct Override {
    bool has = false;
    Table t;                       // G-SA1's table with the player's rows (what table() returns while `has`)
    Entry item[viseme::COUNT][3];  // the player's items by class and variant (normal, quiet, loud); present = 1
    bool custom[viseme::COUNT] = {false, false, false, false, false, false, false, false, false};
};
Override g_over[5];

// M9 (tests/feat_mouth_test.cpp, with the disc, 2026-10-27): the centroid of the render's vertices that move more than
// 0.02 SA1 units (0.08 HU) between key 0 and the kind's widest mouth-only key at weight 1 (Sonic 7, Tails 16, Knuckles 7,
// Amy 16, Big 4) - two worlds of the kind standing on a flat floor in lock step - from the character's drawn position
// (sa1_render.position = the addon's C.drawPos) in its own frame (forward along sa1_render.yaw, up = host +Z), Hammer units
// at scale 1, rounded to 0.1. Measured: Sonic 3.78 / 29.87, Tails 3.43 / 22.27, Knuckles 6.06 / 25.81, Amy 4.28 / 25.03,
// Big 3.23 / 63.44 (sideways within 0.7). Numbers, not game data
const Anchor k_anchor[5] = {
    {3.8f, 29.9f},     // Sonic
    {3.4f, 22.3f},     // Tails
    {6.1f, 25.8f},     // Knuckles
    {4.3f, 25.0f},     // Amy
    {3.2f, 63.4f},     // Big
};

const char *const k_sound[viseme::COUNT] = {"SIL", "MBP", "AA", "EH", "EE", "OH", "OO", "SS", "FV"};
const char *const k_variant[3] = {"", "quiet", "loud"};

std::string fmt_w(float w)
{
    char b[32];
    std::snprintf(b, sizeof b, "%.4g", (double)w);
    return b;
}

// a piece of the player's text for a message: printable ASCII only, at most 40 characters
std::string shown(const std::string &s)
{
    std::string o;
    for (char c : s) {
        if (o.size() >= 40) {
            o += "...";
            break;
        }
        o += (c >= 32 && c < 127) ? c : '?';
    }
    return o;
}

bool all_digits(const std::string &s)
{
    if (s.empty()) {
        return false;
    }
    for (char c : s) {
        if (c < '0' || c > '9') {
            return false;
        }
    }
    return true;
}

// KEY = "0" | [1-9][0-9]? below the kind's count (digits are counted: "007" or "4294967300" never wrap into a key)
bool parse_key(int kind, int keys, const std::string &tok, int &out, std::string &why)
{
    if (!all_digits(tok) || tok.size() > 2 || (tok.size() == 2 && tok[0] == '0')) {
        why = "\"" + shown(tok) + "\" is not a key number (" + kind_name(kind) + "'s face keys are 0-" +
              std::to_string(keys - 1) + ")";
        return false;
    }
    int v = tok.size() == 1 ? tok[0] - '0' : (tok[0] - '0') * 10 + (tok[1] - '0');
    if (v >= keys) {
        why = "key " + std::to_string(v) + " is not one of " + kind_name(kind) + "'s " + std::to_string(keys) +
              " face keys (0-" + std::to_string(keys - 1) + ")";
        return false;
    }
    out = v;
    return true;
}

// W = [0-9] ["." 1-4 digits], 0..1
bool parse_weight(const std::string &tok, float &out, std::string &why)
{
    bool shape = tok.size() >= 1 && tok[0] >= '0' && tok[0] <= '9' &&
                 (tok.size() == 1 || (tok.size() >= 3 && tok[1] == '.' && all_digits(tok.substr(2))));
    if (!shape) {
        why = "weight " + shown(tok) + " is not a number like 0.45 (0..1, at most 4 decimals)";
        return false;
    }
    size_t nf = tok.size() >= 3 ? tok.size() - 2 : 0;
    if (nf > 4) {
        why = "weight " + shown(tok) + " has more than 4 decimals";
        return false;
    }
    long num = (long)(tok[0] - '0') * 10000;
    long scale = 1000;
    for (size_t i = 0; i < nf; i++, scale /= 10) {
        num += (long)(tok[2 + i] - '0') * scale;
    }
    if (num > 10000) {
        why = "weight " + shown(tok) + " is not 0..1";
        return false;
    }
    out = (float)((double)num / 10000.0);
    return true;
}

int sound_class(const std::string &s)
{
    for (int c = viseme::AA; c < viseme::COUNT; c++) {
        if (s == k_sound[c]) {
            return c;
        }
    }
    return -1;
}

// one item "SOUND[.variant]=MOUTH" -> class, variant, entry
bool parse_item(int kind, const std::string &item, int &cls, int &variant, Entry &e, std::string &why)
{
    size_t eq = item.find('=');
    if (eq == std::string::npos) {
        why = "not SOUND=MOUTH (e.g. AA=7>16@0.45)";
        return false;
    }
    std::string lhs = item.substr(0, eq), sound = lhs, var;
    size_t dot = lhs.find('.');
    if (dot != std::string::npos) {
        sound = lhs.substr(0, dot);
        var = lhs.substr(dot + 1);
    }
    if (sound == "SIL" || sound == "MBP") {
        why = "silence and m b p are always closed";
        return false;
    }
    cls = sound_class(sound);
    if (cls < 0) {
        why = "unknown sound " + shown(sound) + " (AA EH EE OH OO SS FV)";
        return false;
    }
    if (dot == std::string::npos) {
        variant = VARIANT_NORMAL;
    } else if (var == "quiet") {
        variant = VARIANT_QUIET;
    } else if (var == "loud") {
        variant = VARIANT_LOUD;
    } else {
        why = "unknown variant " + shown(var) + " (quiet or loud; the normal mouth has no variant word)";
        return false;
    }
    return parse_mouth(kind, item.substr(eq + 1), e, why);
}

}  // namespace

const Table *default_table(int kind)
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

const Table *table(int kind)
{
    int i = face_slot(kind);
    if (i >= 0 && g_over[i].has) {
        return &g_over[i].t;
    }
    return default_table(kind);
}

bool has_face(int kind)
{
    return default_table(kind) != nullptr;
}

const char *kind_name(int kind)
{
    static const char *const n[9] = {"Sonic", "Eggman", "Tails", "Knuckles", "Tikal", "Amy", "E-102", "Big", "Super Sonic"};
    return kind >= 0 && kind < 9 ? n[kind] : "?";
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
    case LADDER: {
        // 0.9.4e: the cap is the entry's own (G-SA1's f v entries carry fv_level: every 0.9.4c number kept)
        float cap = clamp01(e->w);
        a = b = -1;
        w = s < cap ? s : cap;
        break;
    }
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

// ---- 0.9.4e: the player's mouths ------------------------------------------------------------------------------------------

bool parse_mouth(int kind, const std::string &text, Entry &out, std::string &why)
{
    const Table *t = default_table(kind);
    if (!t) {
        why = std::string(kind_name(kind)) + " has no face in the game";
        return false;
    }
    Entry e;
    e.present = 1;
    e.expression = 0;
    if (text.compare(0, 6, "ladder") == 0) {
        std::string rest = text.substr(6);
        e.a = e.b = -1;
        e.how = LADDER;
        e.w = 1.0f;
        if (!rest.empty()) {
            if (rest[0] != '@') {
                why = "\"" + shown(text) + "\" is not a mouth (k, a>b@w or ladder[@w])";
                return false;
            }
            if (!parse_weight(rest.substr(1), e.w, why)) {
                return false;
            }
        }
        out = e;
        return true;
    }
    std::string body = text;
    e.how = FIXED;
    size_t colon = text.find(':');
    if (colon != std::string::npos) {
        body = text.substr(0, colon);
        std::string suf = text.substr(colon + 1);
        if (suf == "scales") {
            e.how = SCALES;
        } else if (suf != "fixed") {
            why = "unknown \":" + shown(suf) + "\" (:scales or :fixed)";
            return false;
        }
    }
    size_t gt = body.find('>');
    if (gt == std::string::npos) {
        e.a = 0;
        e.w = 1.0f;
        if (!parse_key(kind, t->keys, body, e.b, why)) {
            return false;
        }
        out = e;
        return true;
    }
    std::string ta = body.substr(0, gt), rest = body.substr(gt + 1);
    size_t at = rest.find('@');
    if (at == std::string::npos) {
        why = "\"" + shown(text) + "\": a>b needs its weight (e.g. 7>16@0.45)";
        return false;
    }
    if (!parse_key(kind, t->keys, ta, e.a, why) || !parse_key(kind, t->keys, rest.substr(0, at), e.b, why) ||
        !parse_weight(rest.substr(at + 1), e.w, why)) {
        return false;
    }
    out = e;
    return true;
}

std::string mouth_text(const Entry &e)
{
    switch (e.how) {
    case LADDER:
        return e.w >= 1.0f ? std::string("ladder") : "ladder@" + fmt_w(e.w);
    case CLOSED:
        return "closed";
    default: {
        std::string s = (e.a == 0 && e.w == 1.0f) ? std::to_string(e.b)
                                                   : std::to_string(e.a) + ">" + std::to_string(e.b) + "@" + fmt_w(e.w);
        return e.how == SCALES ? s + ":scales" : s;
    }
    }
}

bool set_override(int kind, const char *spec, std::string &err)
{
    err.clear();
    int slot = face_slot(kind);
    const Table *def = default_table(kind);
    if (slot < 0 || !def) {
        err = std::string(kind_name(kind)) + " has no face in the game";
        return false;
    }
    std::string s = spec ? spec : "";
    if (s.empty()) {
        g_over[slot] = Override();
        return true;
    }
    if (s.size() > (size_t)kSpecMaxChars) {
        err = "too long (24 items / 512 characters)";
        return false;
    }
    // split on ',' keeping empty items
    std::string items[kSpecMaxItems];
    int n = 0;
    size_t pos = 0;
    while (true) {
        size_t comma = s.find(',', pos);
        if (n >= kSpecMaxItems) {
            err = "too long (24 items / 512 characters)";
            return false;
        }
        items[n++] = s.substr(pos, comma == std::string::npos ? std::string::npos : comma - pos);
        if (comma == std::string::npos) {
            break;
        }
        pos = comma + 1;
    }
    Override o;
    for (int i = 0; i < n; i++) {
        if (items[i].empty()) {
            err = "an empty item (two commas, or a comma at an end)";
            return false;
        }
        int cls = 0, variant = 0;
        Entry e;
        std::string why;
        if (!parse_item(kind, items[i], cls, variant, e, why)) {
            err = shown(items[i]) + ": " + why;
            return false;
        }
        if (o.item[cls][variant].present) {
            err = shown(items[i]) + ": " + k_sound[cls] + (variant ? std::string(".") + k_variant[variant] : std::string()) +
                  " twice";
            return false;
        }
        o.item[cls][variant] = e;
    }
    // build the table in use (lipsync2_plan.md 4.7)
    o.t = *def;
    for (int c = viseme::AA; c < viseme::COUNT; c++) {
        const Entry *it = o.item[c];
        if (it[VARIANT_NORMAL].present) {
            o.t.rows[c] = R(it[VARIANT_NORMAL], it[VARIANT_QUIET], it[VARIANT_LOUD], none());
        } else {
            if (it[VARIANT_QUIET].present) {
                o.t.rows[c].quiet = it[VARIANT_QUIET];
            }
            if (it[VARIANT_LOUD].present) {
                o.t.rows[c].loud = it[VARIANT_LOUD];
            }
        }
        o.custom[c] = it[0].present || it[1].present || it[2].present;
    }
    o.has = true;
    g_over[slot] = o;
    return true;
}

std::string spec_of(int kind)
{
    int slot = face_slot(kind);
    if (slot < 0 || !g_over[slot].has) {
        return std::string();
    }
    std::string out;
    for (int c = viseme::AA; c < viseme::COUNT; c++) {
        for (int v = 0; v < 3; v++) {
            const Entry &e = g_over[slot].item[c][v];
            if (!e.present) {
                continue;
            }
            if (!out.empty()) {
                out += ",";
            }
            out += k_sound[c];
            if (v) {
                out += std::string(".") + k_variant[v];
            }
            out += "=" + mouth_text(e);
        }
    }
    return out;
}

bool has_override(int kind)
{
    int slot = face_slot(kind);
    return slot >= 0 && g_over[slot].has;
}

bool row_custom(int kind, int cls)
{
    int slot = face_slot(kind);
    return slot >= 0 && g_over[slot].has && cls >= 0 && cls < viseme::COUNT && g_over[slot].custom[cls];
}

bool mouth_anchor(int kind, Anchor &out)
{
    int slot = face_slot(kind);
    if (slot < 0) {
        out = Anchor();
        return false;
    }
    out = k_anchor[slot];
    return true;
}

}  // namespace mouth
}  // namespace gsa1
