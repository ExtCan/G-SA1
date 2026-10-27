// G-SA1 core: which of a character's own face keys shows each kind of sound (round 0.9.4c, feature "faces" 2; sadc
// docs/research/phoneme_plan.md 4.3 with its Review R.1 / R.14 / R.15, from phoneme_shapes.md 4 / 5 and visemes.json).
// Round 0.9.4e (feature "faces" 3; sadc docs/research/lipsync2_plan.md 4.6 / 4.7 / 5.4 with its review R.2 / R.8, and
// lipsync2_show.md 5.2 / 7 / 8): table v2 (kTableVersion 2: every character's mouths re-checked on renders - Sonic's "ah" is
// his open mouth with fangs, the smile only for "ee" and the f / v slit), the player's own mouths per character
// (set_override: "Your mouths" on the Faces page, saved by the addon in data/gsa1/mouth_shapes.txt) and the mouth point per
// kind for the tester's close-up (mouth_anchor).
//
// The table is data: key indices of the event head's shape motion (Sonic 21 keys, Tails / Knuckles / Amy 20, Big 8) and
// weights between two keys - numbers chosen by measuring the shapes, not game data. One entry `a>b@w` means the face block
// blends key a to key b at weight w (sa1_character_face_mouth). Each sound class has a normal entry and optional quiet /
// loud / plain ones:
//   how CLOSED   the mouth at rest (0>0@0): silence and m / b / p
//       SCALES   w x (f + (1 - f) x s), f = max(1 - size, the kind's floor): the loudness s sizes the shape
//       FIXED    w as it is
//       LADDER   the loudness ladder at min(s, the entry's w) (sa1_character_face_level): a = b = -1. G-SA1's f / v entries
//                carry w = fv_level (review R.1 of phoneme_plan.md: kept to a slit - an "f" is 27-34 dB under the vowel,
//                s still carries the vowel's openness); a player's "ladder@w" carries its own w (0.9.4e)
//   expression   the entry uses a key 8-19 that moves the eyes or brows a little ("bigger mouths for loud speech"); with
//                that switch off the row's plain entry, else its quiet one, else its normal one if it has none. The
//                player's own entries never have it ("Bigger mouths" does not change them).
//   quiet when s < 0.5, loud when the raw level is at or above the page's "loud speech" level (Lua decides the variant).
// Kinds 0 Sonic, 2 Tails, 3 Knuckles, 5 Amy and 7 Big have a table; E-102, Eggman, Tikal and Super Sonic (kind 8) none
// (their mouth stays closed: 0>0@0). Every key is below its kind's key count (tests/feat_mouth_test.cpp V8, and with the
// disc M8 against sa1_character_face_mouth).
//
// THREADS: everything in mouth:: runs on the Lua (game) thread only - the bindings (VisemeMouth, VisemeTable,
// VisemeOverride) and the core tests. The microphone's thread (mic.cpp's RECORDPROC) never calls mouth::, so the player's
// override tables need no lock.
//
// THE PLAYER'S MOUTHS (set_override; lipsync2_plan.md 4.7, lipsync2_show.md 7 / 8.1). A spec is the one grammar the
// addon's sh_mouths.lua shares (its F.MouthItemParse refuses exactly what this parser refuses: review R.8):
//   spec  = "" | item {"," item}                 at most 24 items and 512 characters; no spaces; one item per SOUND.variant
//   item  = SOUND ["." variant] "=" MOUTH
//   SOUND = AA | EH | EE | OH | OO | SS | FV      (SIL and MBP are always closed: refused)
//   variant = quiet | loud                       (the normal mouth has no variant word: "AA.normal" is refused)
//   MOUTH = KEY [":scales" | ":fixed"]           KEY alone = 0>KEY@1
//         | KEY ">" KEY "@" W [":scales" | ":fixed"]   fixed when left out
//         | "ladder" ["@" W]                     the loudness mouth, at most level W (1 when left out)
//   KEY   = "0" | [1-9][0-9]?                    below the kind's key count (Sonic 21, Tails / Knuckles / Amy 20, Big 8)
//   W     = [0-9] ["." 1-4 digits]               0..1 (".5", "1e-1", "+0.5", "0.12345", "nan" are refused)
// All or nothing: one bad item refuses the whole spec and the previous override stays. A class with a NORMAL item becomes
// {normal = yours, quiet = yours or none, loud = yours or none, plain = none}; a class with only quiet / loud items keeps
// G-SA1's row with those replaced; other classes are G-SA1's. The normal form (spec_of) lists the items in class order
// (AA .. FV), normal before quiet before loud, weights as %.4g, "k" for 0>k@1, ":scales" only when scaling, "ladder" for
// ladder@1. Nothing but key numbers and weights is kept.
#pragma once

#include <cstdint>
#include <string>

namespace gsa1 {
namespace mouth {

// 0.9.4e: the table's version (VisemeTable's table_version; 2 = lipsync2_show.md 5.2 with lipsync2_plan.md's review R.2)
const int kTableVersion = 2;
// the override grammar's limits
const int kSpecMaxItems = 24;
const int kSpecMaxChars = 512;

enum : uint8_t { CLOSED = 0, SCALES = 1, FIXED = 2, LADDER = 3 };

struct Entry {
    int a = 0, b = 0;             // keys (-1 / -1 for LADDER)
    float w = 0.0f;               // the weight (SCALES: at full openness; LADDER: the highest level)
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
    float fv_level = 0.0f;        // G-SA1's LADDER entries' highest level (review R.1); their Entry::w
    Row rows[9];                  // by sound class (gsa1::viseme SIL .. FV)
};

enum : int { VARIANT_NORMAL = 0, VARIANT_QUIET = 1, VARIANT_LOUD = 2 };

// the mouth point of a face kind (M9): where the mouth is in the character's own frame at scale 1, in Hammer units from
// the character's drawn position (sa1_render.position): `forward` along its facing, `up` along the host's up axis
struct Anchor {
    float forward = 0.0f, up = 0.0f;
};

// the table of a kind in use: the player's override table when has_override(kind), else G-SA1's (nullptr: no face)
const Table *table(int kind);
// G-SA1's own table of a kind (VisemeTable's .default; nullptr: no face)
const Table *default_table(int kind);
// the entry phoneme_plan.md 4.3's rule picks (before sizing): the variant asked for (a missing quiet / loud -> normal),
// then the expression rule when big is off
const Entry *entry(int kind, int cls, int variant, bool big);
// 4.3's rule: a, b, w for the face. SIL / MBP, a kind without a face, or a bad argument: 0, 0, 0. A LADDER entry: -1, -1,
// min(s, the entry's w). s and size are clamped to 0..1; w to 0..1.
void pick(int kind, int cls, float s, float size, int variant, bool big, int &a, int &b, float &w);
// "closed", "scales", "fixed", "ladder"
const char *how_name(uint8_t how);

// ---- 0.9.4e: the player's mouths (Lua thread only) --------------------------------------------------------------------
// parses `spec` (the grammar above) for `kind` as a whole and installs it; "" (or nullptr) removes the kind's override.
// false with err "<item>: <why>" (or "<why>" for the whole spec) and nothing changed; a kind without a face: false with
// "<name> has no face in the game" (the binding reports "unsupported" for it: has_face(kind) is false)
bool set_override(int kind, const char *spec, std::string &err);
// the kind's override in normal form ("" for none)
std::string spec_of(int kind);
bool has_override(int kind);
// any entry of that row is the player's
bool row_custom(int kind, int cls);
// the kind has a mouth table (Sonic, Tails, Knuckles, Amy, Big)
bool has_face(int kind);
// "Sonic", "Eggman", "Tails", "Knuckles", "Tikal", "Amy", "E-102", "Big", "Super Sonic" ("?" outside 0..8)
const char *kind_name(int kind);
// M9's measured mouth point; false for a kind without a face
bool mouth_anchor(int kind, Anchor &out);
// one MOUTH of the grammar for `kind` (tests, the binding's messages): false with why
bool parse_mouth(int kind, const std::string &text, Entry &out, std::string &why);
// an entry in the grammar's normal form ("7>16@0.45", "6:scales", "ladder@0.25")
std::string mouth_text(const Entry &e);

}  // namespace mouth
}  // namespace gsa1
