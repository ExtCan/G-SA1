// G-SA1 core: which of a character's own face keys shows each kind of sound (round 0.9.4c, feature "faces" 2; sadc
// docs/research/phoneme_plan.md 4.3 with its Review R.1 / R.14 / R.15, from phoneme_shapes.md 4 / 5 and visemes.json).
//
// The table is data: key indices of the event head's shape motion (Sonic 21 keys, Tails / Knuckles / Amy 20, Big 8) and
// weights between two keys - numbers chosen by measuring the shapes, not game data. One entry `a>b@w` means the face block
// blends key a to key b at weight w (sa1_character_face_mouth). Each sound class has a normal entry and optional quiet /
// loud / plain ones:
//   how CLOSED   the mouth at rest (0>0@0): silence and m / b / p
//       SCALES   w x (f + (1 - f) x s), f = max(1 - size, the kind's floor): the loudness s sizes the shape
//       FIXED    w as it is
//       LADDER   the loudness ladder at min(s, fv_level) (sa1_character_face_level): a = b = -1 (review R.1: kept to a
//                slit - an "f" is 27-34 dB under the vowel, s still carries the vowel's openness)
//   expression   the entry uses a key 8-19 that moves the eyes or brows a little ("bigger mouths for loud speech"); with
//                that switch off the row's plain entry, else its quiet one, else its normal one if it has none.
//   quiet when s < 0.5, loud when the raw level is at or above the page's "loud speech" level (Lua decides the variant).
// Kinds 0 Sonic, 2 Tails, 3 Knuckles, 5 Amy and 7 Big have a table; E-102, Eggman, Tikal and Super Sonic (kind 8) none
// (their mouth stays closed: 0>0@0). Every key is below its kind's key count (tests/feat_viseme_test.cpp V8, and with the
// disc against sa1_face_info).
#pragma once

#include <cstdint>

namespace gsa1 {
namespace mouth {

enum : uint8_t { CLOSED = 0, SCALES = 1, FIXED = 2, LADDER = 3 };

struct Entry {
    int a = 0, b = 0;             // keys (-1 / -1 for LADDER)
    float w = 0.0f;               // the weight (SCALES: at full openness)
    uint8_t how = CLOSED;
    uint8_t expression = 0;       // uses an expression key (8-19)
    uint8_t present = 0;          // 1: the entry exists (quiet / loud / plain are optional)
};

struct Row {
    Entry normal, quiet, loud, plain;
};

struct Table {
    int kind = -1;
    int keys = 0;                 // the kind's key count (sa1_face_info.keys)
    float floor = 0.0f;           // the SCALES floor (Sonic, Knuckles 0.8: their lips open as a slit first)
    float ladder_cap = 1.0f;      // the loudness ladder's top with "bigger mouths" off (the last mouth-only key)
    float fv_level = 0.0f;        // the LADDER entries' highest level (review R.1)
    Row rows[9];                  // by sound class (gsa1::viseme SIL .. FV)
};

enum : int { VARIANT_NORMAL = 0, VARIANT_QUIET = 1, VARIANT_LOUD = 2 };

// the table of a kind (nullptr: no face)
const Table *table(int kind);
// the entry phoneme_plan.md 4.3's rule picks (before sizing): the variant asked for (a missing quiet / loud -> normal),
// then the expression rule when big is off
const Entry *entry(int kind, int cls, int variant, bool big);
// 4.3's rule: a, b, w for the face. SIL / MBP, a kind without a face, or a bad argument: 0, 0, 0. A LADDER entry: -1, -1,
// min(s, fv_level). s and size are clamped to 0..1; w to 0..1.
void pick(int kind, int cls, float s, float size, int variant, bool big, int &a, int &b, float &w);
// "closed", "scales", "fixed", "ladder"
const char *how_name(uint8_t how);

}  // namespace mouth
}  // namespace gsa1
