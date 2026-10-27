-- G-SA1 "Your mouths", the shared data part (round 0.9.4e: sadc docs/research/lipsync2_plan.md 4.7 / 5.6 with its review
-- R.2 / R.8, lipsync2_show.md 6.4 and 7). Pure data and functions (both realms load it; only the client uses it; no file,
-- network or module call here - feat/cl_mouthtest.lua does the file I/O and the module calls):
--   F.NEEDS_MOUTHS, F.MOUTH_FILE, F.MOUTH_CHARS / F.MOUTH_CHAR_OF, F.MOUTH_KEYS, F.MOUTH_SOUNDS, F.MOUTH_NAMES
--   F.MOUTH_CHOICES[kind]  the Faces page's lists: { mouth = "7>16@0.45", text = "open \"ah\", fangs", gsa1 = "AA" | nil,
--                          tag = "talk" | "mouth" | "brows" | "head" } in the page's order ("head" = the whole head moves:
--                          listed last, greyed with a tooltip, still selectable). gsa1 = "AA", "AA.quiet", "AA.loud",
--                          "OH.quiet" ...: the entry IS G-SA1's mouth for that sound and variant (table v2,
--                          src/core/mouth.cpp; tests/feat_mouths_test.lua L8b checks it against the module)
--   F.MouthItemParse(item, kind) -> sound, variant, mouth | nil, why   one "SOUND[.variant]=MOUTH" (variant "" / "quiet" /
--                          "loud"; mouth in the grammar's normal form); refuses exactly what the module's parser refuses
--                          (mouth.hpp's grammar; review R.8)
--   F.MouthSpecParse(spec, kind) -> items, n | nil, why   a whole spec (also the spec-level rules: 512 characters, 24 items,
--                          empty items, a SOUND.variant twice); items = { ["AA"] = "7>16@0.45", ["AA.loud"] = "16" }
--   F.MouthSpec(items [, kind]) -> spec   the normal form (equal to the module's mouth::spec_of: items in class order,
--                          normal before quiet before loud)
--   F.MouthNormal(mouth [, kind]) -> mouth | nil, why   one MOUTH in the normal form ("0>6@1:scales" -> "6:scales")
--   F.MouthParseFile(text) -> map, bad   map[kind] = { items = {...}, spec = "..." }; bad = { { line = n, text = "...",
--                          why = "..." } } (kept in the file, never applied)
--   F.MouthSerializeFile(map [, bad]) -> text   the header, "version\t1", one sorted line per character with items, then the
--                          kept bad lines unchanged
--   F.MouthText(mouth, kind) -> "7>16 45 %", "4", "the f v slit", "your voice" ... (the page's words)
-- The grammar (src/core/mouth.hpp): spec = "" | item {"," item}; item = SOUND ["." variant] "=" MOUTH; SOUND AA EH EE OH OO
-- SS FV; variant quiet | loud; MOUTH = KEY [":scales" | ":fixed"] | KEY ">" KEY "@" W [":scales" | ":fixed"] | "ladder"
-- ["@" W]; KEY "0" or 1-99 without a leading zero, below the character's key count; W one digit, optionally "." and 1-4
-- digits, 0..1. The file holds key numbers and weights only (and two words per line): never anything the microphone heard.
GSA1 = GSA1 or {}
local F = GSA1.Faces or {}
GSA1.Faces = F

F.NEEDS_MOUTHS = { feature = "faces", version = 3, module = "0.9.4e" }
F.MOUTH_FILE = "gsa1/mouth_shapes.txt"
F.MOUTH_FILE_VERSION = "1"
F.MOUTH_CHARS = { sonic = 0, tails = 2, knuckles = 3, amy = 5, big = 7 }
F.MOUTH_CHAR_OF = { [0] = "sonic", [2] = "tails", [3] = "knuckles", [5] = "amy", [7] = "big" }
F.MOUTH_CHAR_ORDER = { 0, 2, 3, 5, 7 }
F.MOUTH_KEYS = { [0] = 21, [2] = 20, [3] = 20, [5] = 20, [7] = 8 }
F.MOUTH_SOUNDS = { "AA", "EH", "EE", "OH", "OO", "SS", "FV" }       -- classes 2..8, the file's order
F.MOUTH_SOUND_CLASS = { AA = 2, EH = 3, EE = 4, OH = 5, OO = 6, SS = 7, FV = 8 }
F.MOUTH_VARIANTS = { "", "quiet", "loud" }
F.MOUTH_NAMES = { [0] = "Sonic", [1] = "Eggman", [2] = "Tails", [3] = "Knuckles", [4] = "Tikal", [5] = "Amy", [6] = "E-102",
                  [7] = "Big", [8] = "Super Sonic" }
F.MOUTH_FV = { [0] = 0.25, [2] = 0.1667, [3] = 0.1667, [5] = 0.125, [7] = 0.125 }   -- G-SA1's f v slit (fv_level)
F.MOUTH_MAX_ITEMS = 24
F.MOUTH_MAX_CHARS = 512

-- the lists (lipsync2_show.md 6.4 with lipsync2_plan.md's review R.2: Sonic gains G-SA1's quiet ah; Amy's 7>8 50 % loses its
-- G-SA1 tag and 0>8 80 % (scales) joins as G-SA1's eh). "voice" = the loudness mouth, "slit" = G-SA1's f v slit
local function C(mouth, text, tag, gsa1) return { mouth = mouth, text = text, tag = tag, gsa1 = gsa1 } end
F.MOUTH_CHOICES = {
    [0] = {
        C("0", "closed", "talk"),
        C("5", "lips just apart, a thin line", "talk"),
        C("4:scales", "small smile, both rows of teeth", "talk", "EE"),
        C("7", "flat open mouth, teeth and fangs", "talk"),
        C("6", "pucker: a tiny round \"o\" (the eyes widen)", "talk"),
        C("7>16@0.2", "half open, teeth", "mouth", "EH"),
        C("7>16@0.3", "open \"ah\", smaller", "mouth", "AA.quiet"),
        C("7>16@0.45", "open \"ah\", fangs", "mouth", "AA"),
        C("7>16@0.75", "wide open, tongue", "mouth", "AA.loud"),
        C("4>16@0.3", "open grin (0.9.4c's ah)", "mouth"),
        C("6>16@0.4", "round open \"oh\"", "mouth", "OH"),
        C("6>7@0.2", "small round \"o\"", "mouth", "OO"),
        C("6>7@0.3", "small flat \"o\"", "mouth", "OH.quiet"),
        C("5>4@0.6", "lips apart over the teeth", "mouth", "SS"),
        C("5>4@0.5", "thin line over the upper teeth (an f v stand-in)", "mouth"),
        C("0>4@0.5:scales", "thin smile line (0.9.4c's s)", "mouth"),
        C("16", "big laugh, tongue (the eyes move a little)", "brows"),
        C("17", "smile with teeth (eyes and brows move)", "brows"),
        C("11", "small open, worried (eyes and brows move)", "brows"),
        C("14", "angry shout (brows and muzzle move)", "brows"),
        C("ladder", "opens with your voice", "mouth"),
        C("ladder@0.25", "the f v slit", "mouth", "FV"),
        C("8", "surprise (the whole head moves)", "head"),
        C("9", "yell (the whole head moves)", "head"),
        C("10", "grimace (the whole head moves)", "head"),
    },
    [2] = {
        C("0", "closed (no mouth shows)", "talk"),
        C("4:scales", "wide oval", "talk", "EH"),
        C("5", "tall round", "talk"),
        C("6:scales", "wide flat", "talk", "EE"),
        C("7:scales", "round", "talk", "OH"),
        C("16:scales", "open, D-shaped", "mouth", "AA.quiet"),
        C("18", "small round on his left", "mouth"),
        C("16>8@0.5", "open \"ah\" (the brows move a little)", "brows", "AA"),
        C("8", "wide open (the brows move)", "brows", "AA.loud"),
        C("0>5@0.7:scales", "small round \"oo\"", "talk", "OO"),
        C("0>6@0.6:scales", "flat slit", "talk", "SS"),
        C("0>4@0.5:scales", "small slit", "talk"),
        C("17", "big happy open (the brows move)", "brows"),
        C("12", "wide open wail (the brows move)", "brows"),
        C("ladder", "opens with your voice", "mouth"),
        C("ladder@0.1667", "the f v slit", "mouth", "FV"),
        C("9", "big round yell (the whole head moves)", "head"),
    },
    [3] = {
        C("0", "closed", "talk"),
        C("6", "closed (his talking closes it)", "talk"),
        C("4:scales", "slit with teeth", "talk", "SS"),
        C("5:scales", "wide smile, both rows of teeth", "talk", "EE"),
        C("7", "small rounded open, teeth, tongue", "talk", "OO"),
        C("4>7@0.5", "half open, teeth", "talk", "EH"),
        C("7>16@0.3", "open \"ah\"", "mouth", "AA"),
        C("7>16@0.6", "wide open", "mouth", "AA.loud"),
        C("7>14@0.3", "round \"oh\"", "mouth", "OH"),
        C("18", "smile on his left", "mouth"),
        C("19", "smirk on his left", "mouth"),
        C("0>4@0.5", "thin slit", "talk"),
        C("8", "round open (the brows move)", "brows"),
        C("16", "big laugh (the brows move)", "brows"),
        C("17", "wide happy grin (the brows move)", "brows"),
        C("14", "big round shout (the brows move)", "brows"),
        C("ladder", "opens with your voice", "mouth"),
        C("ladder@0.1667", "the f v slit", "mouth", "FV"),
        C("9", "yell (the whole face moves)", "head"),
        C("10", "grimace (the whole face moves)", "head"),
        C("12", "sad (the whole face moves)", "head"),
    },
    [5] = {
        C("0", "closed", "talk"),
        C("7", "flat oval", "talk"),
        C("5", "small flat oval", "talk"),
        C("4", "small open, round bottom", "talk"),
        C("6", "tall narrow oval", "talk"),
        C("8:scales", "open \"ah\", D-shaped", "mouth", "AA"),
        C("10:scales", "wide", "mouth", "EE"),
        C("16", "big open", "mouth"),
        C("19", "small, on her left", "mouth"),
        C("7>8@0.5", "half open", "mouth"),
        C("0>8@0.8:scales", "smaller open \"ah\"", "mouth", "EH"),
        C("8>16@0.5", "wide open", "mouth", "AA.loud"),
        C("4>6@0.3", "round \"oh\"", "talk", "OH"),
        C("0>6@0.6:scales", "small round \"oo\"", "talk", "OO"),
        C("0>10@0.5:scales", "flat slit", "mouth", "SS"),
        C("0>7@0.5", "small slit", "talk"),
        C("9", "big yell (the brows move)", "brows"),
        C("14", "angry (the brows move)", "brows"),
        C("17", "happy (the brows move)", "brows"),
        C("ladder", "opens with your voice", "mouth"),
        C("ladder@0.125", "the f v slit", "mouth", "FV"),
    },
    [7] = {
        C("0", "closed", "talk"),
        C("0>4@0.25:scales", "jaw a quarter open", "talk", "SS"),
        C("0>4@0.3:scales", "jaw a little open", "talk", "OO"),
        C("0>4@0.35:scales", "jaw a third open", "talk", "EE"),
        C("0>4@0.55:scales", "jaw half open", "talk", "EH"),
        C("0>4@0.7:scales", "jaw mostly open", "talk", "OH"),
        C("4:scales", "jaw drop (his cheeks rise with every opening)", "talk", "AA"),
        C("5:scales", "big jaw drop", "talk", "AA.loud"),
        C("ladder", "opens with your voice", "mouth"),
        C("ladder@0.125", "the f v slit", "mouth", "FV"),
    },
}

-- ---- the grammar (mouth.hpp; the same refusals as the module: review R.8) ----------------------------------------------------
-- a piece of the player's text for a message: printable ASCII, at most 40 characters (as the module's)
local function shown(s)
    s = tostring(s or "")
    local o = string.gsub(string.sub(s, 1, 40), "[^\32-\126]", "?")
    if #s > 40 then o = o .. "..." end
    return o
end

local function parse_key(tok, kind, keys)
    if not string.match(tok, "^%d%d?$") or (#tok == 2 and string.sub(tok, 1, 1) == "0") then
        return nil, string.format("\"%s\" is not a key number (%s's face keys are 0-%d)", shown(tok),
            F.MOUTH_NAMES[kind] or "?", (keys or 100) - 1)
    end
    local v = tonumber(tok)
    if keys and v >= keys then
        return nil, string.format("key %d is not one of %s's %d face keys (0-%d)", v, F.MOUTH_NAMES[kind] or "?", keys,
            keys - 1)
    end
    return v
end

local function parse_weight(tok)
    local int, frac = string.match(tok, "^(%d)%.(%d+)$")
    if not int then
        if string.match(tok, "^%d$") then int, frac = tok, "" end
    end
    if not int then
        return nil, string.format("weight %s is not a number like 0.45 (0..1, at most 4 decimals)", shown(tok))
    end
    if #frac > 4 then
        return nil, string.format("weight %s has more than 4 decimals", shown(tok))
    end
    local num = tonumber(int) * 10000 + (frac ~= "" and tonumber(frac .. string.rep("0", 4 - #frac)) or 0)
    if num > 10000 then
        return nil, string.format("weight %s is not 0..1", shown(tok))
    end
    return num / 10000
end

local function fmt_w(w) return string.format("%.4g", w) end

-- one MOUTH -> its normal form; keys = the kind's key count (nil: any 0-99)
local function parse_mouth(text, kind, keys)
    if string.sub(text, 1, 6) == "ladder" then
        local rest = string.sub(text, 7)
        if rest == "" then return "ladder" end
        if string.sub(rest, 1, 1) ~= "@" then
            return nil, string.format("\"%s\" is not a mouth (k, a>b@w or ladder[@w])", shown(text))
        end
        local w, why = parse_weight(string.sub(rest, 2))
        if not w then return nil, why end
        return w >= 1 and "ladder" or ("ladder@" .. fmt_w(w))
    end
    local body, suffix = text, nil
    local colon = string.find(text, ":", 1, true)
    local scales = false
    if colon then
        body, suffix = string.sub(text, 1, colon - 1), string.sub(text, colon + 1)
        if suffix == "scales" then
            scales = true
        elseif suffix ~= "fixed" then
            return nil, string.format("unknown \":%s\" (:scales or :fixed)", shown(suffix))
        end
    end
    local gt = string.find(body, ">", 1, true)
    local a, b, w, why
    if not gt then
        a, w = 0, 1
        b, why = parse_key(body, kind, keys)
        if not b then return nil, why end
    else
        local ta, rest = string.sub(body, 1, gt - 1), string.sub(body, gt + 1)
        local at = string.find(rest, "@", 1, true)
        if not at then
            return nil, string.format("\"%s\": a>b needs its weight (e.g. 7>16@0.45)", shown(text))
        end
        a, why = parse_key(ta, kind, keys)
        if not a then return nil, why end
        b, why = parse_key(string.sub(rest, 1, at - 1), kind, keys)
        if not b then return nil, why end
        w, why = parse_weight(string.sub(rest, at + 1))
        if not w then return nil, why end
    end
    local s = (a == 0 and w == 1) and tostring(b) or string.format("%d>%d@%s", a, b, fmt_w(w))
    return scales and (s .. ":scales") or s
end

function F.MouthNormal(mouth, kind)
    if type(mouth) ~= "string" then return nil, "not a mouth" end
    return parse_mouth(mouth, kind, kind ~= nil and F.MOUTH_KEYS[kind] or nil)
end

-- sound ("AA"), variant ("" / "quiet" / "loud"), mouth (normal form) | nil, why
function F.MouthItemParse(item, kind)
    local keys = F.MOUTH_KEYS[kind]
    if not keys then return nil, string.format("%s has no face in the game", F.MOUTH_NAMES[kind] or "this character") end
    if type(item) ~= "string" then return nil, "not SOUND=MOUTH (e.g. AA=7>16@0.45)" end
    local eq = string.find(item, "=", 1, true)
    if not eq then return nil, "not SOUND=MOUTH (e.g. AA=7>16@0.45)" end
    local lhs = string.sub(item, 1, eq - 1)
    local sound, variant = lhs, ""
    local dot = string.find(lhs, ".", 1, true)
    if dot then sound, variant = string.sub(lhs, 1, dot - 1), string.sub(lhs, dot + 1) end
    if sound == "SIL" or sound == "MBP" then return nil, "silence and m b p are always closed" end
    if not F.MOUTH_SOUND_CLASS[sound] then
        return nil, string.format("unknown sound %s (AA EH EE OH OO SS FV)", shown(sound))
    end
    if dot and variant ~= "quiet" and variant ~= "loud" then
        return nil, string.format("unknown variant %s (quiet or loud; the normal mouth has no variant word)", shown(variant))
    end
    local mouth, why = parse_mouth(string.sub(item, eq + 1), kind, keys)
    if not mouth then return nil, why end
    return sound, variant, mouth
end

-- items, n | nil, why
function F.MouthSpecParse(spec, kind)
    if not F.MOUTH_KEYS[kind] then
        return nil, string.format("%s has no face in the game", F.MOUTH_NAMES[kind] or "this character")
    end
    if spec == nil or spec == "" then return {}, 0 end
    if type(spec) ~= "string" then return nil, "not a spec" end
    if #spec > F.MOUTH_MAX_CHARS then return nil, "too long (24 items / 512 characters)" end
    local parts, pos = {}, 1
    while true do
        local comma = string.find(spec, ",", pos, true)
        if #parts >= F.MOUTH_MAX_ITEMS then return nil, "too long (24 items / 512 characters)" end
        parts[#parts + 1] = string.sub(spec, pos, comma and comma - 1 or nil)
        if not comma then break end
        pos = comma + 1
    end
    local items, n = {}, 0
    for _, item in ipairs(parts) do
        if item == "" then return nil, "an empty item (two commas, or a comma at an end)" end
        local sound, variant, mouth = F.MouthItemParse(item, kind)
        if not sound then return nil, shown(item) .. ": " .. tostring(variant) end
        local key = variant ~= "" and (sound .. "." .. variant) or sound
        if items[key] then return nil, shown(item) .. ": " .. key .. " twice" end
        items[key] = mouth
        n = n + 1
    end
    return items, n
end

-- the normal form of an items map (unknown keys and mouths the grammar refuses are left out)
function F.MouthSpec(items, kind)
    if type(items) ~= "table" then return "" end
    local out = {}
    for _, sound in ipairs(F.MOUTH_SOUNDS) do
        for _, variant in ipairs(F.MOUTH_VARIANTS) do
            local key = variant ~= "" and (sound .. "." .. variant) or sound
            local m = items[key] and F.MouthNormal(items[key], kind)
            if m then out[#out + 1] = key .. "=" .. m end
        end
    end
    return table.concat(out, ",")
end

-- ---- the file (lipsync2_show.md 7) -------------------------------------------------------------------------------------------
F.MOUTH_FILE_HEADER = table.concat({
    "# G-SA1 mouth shapes - your changes to G-SA1's mouth table (Q menu > Options > G-SA1 > Faces > Mouth shape tester).",
    "# One character per line, tab-separated:  character  shapes",
    "#   character  sonic, tails, knuckles, amy, big",
    "#   shapes     comma list of SOUND[.variant]=MOUTH; only what differs from G-SA1's table",
    "#     SOUND    AA EH EE OH OO SS FV (ah eh ee oh oo s f; silence and m b p are always closed)",
    "#     variant  normal (left out), quiet, loud",
    "#     MOUTH    k | a>b@w  [:scales | :fixed]   keys of this character (Sonic 0-20, Tails / Knuckles / Amy 0-19,",
    "#                                              Big 0-7), w 0..1; k alone = 0>k@1; fixed when left out",
    "#              ladder[@w]                      the loudness mouth, at most level w (1 when left out)",
    "# Key numbers name the character's own face shapes on your disc. Nothing else is stored here.",
}, "\n")

-- map, bad: map[kind] = { items = {...}, spec = normal form }; bad lines are kept (never applied, never rewritten)
function F.MouthParseFile(text)
    local map, bad = {}, {}
    if type(text) ~= "string" or text == "" then return map, bad end
    local version, n = F.MOUTH_FILE_VERSION, 0
    local pos = 1
    while pos <= #text do
        local nl = string.find(text, "\n", pos, true)
        local line = string.sub(text, pos, nl and nl - 1 or nil)
        pos = nl and nl + 1 or #text + 1
        n = n + 1
        local why
        local bare = string.gsub(line, "\r$", "")
        if bare == "" or string.sub(bare, 1, 1) == "#" then
            why = false
        elseif string.find(line, "\r", 1, true) then
            why = "a Windows line end (CR LF): G-SA1 writes LF only"
        else
            local name, rest = string.match(line, "^([^\t]*)\t(.*)$")
            if not name then
                why = "not \"character<TAB>shapes\""
            elseif name == "version" then
                version = rest
                why = rest ~= F.MOUTH_FILE_VERSION and string.format("version %s: this G-SA1 reads version %s", shown(rest),
                    F.MOUTH_FILE_VERSION) or false
            elseif version ~= F.MOUTH_FILE_VERSION then
                why = string.format("under version %s (this G-SA1 reads version %s)", shown(version), F.MOUTH_FILE_VERSION)
            else
                local kind = F.MOUTH_CHARS[name]
                if not kind then
                    why = string.format("unknown character %s (sonic, tails, knuckles, amy, big)", shown(name))
                elseif map[kind] then
                    why = name .. " twice"
                else
                    local items, err = F.MouthSpecParse(rest, kind)
                    if not items then
                        why = err
                    else
                        map[kind] = { items = items, spec = F.MouthSpec(items, kind) }
                        why = false
                    end
                end
            end
        end
        if why then bad[#bad + 1] = { line = n, text = line, why = why } end
    end
    return map, bad
end

-- the whole file: header, version, one line per character with items (sonic, tails, knuckles, amy, big), the kept bad lines
function F.MouthSerializeFile(map, bad)
    local out = { F.MOUTH_FILE_HEADER, "version\t" .. F.MOUTH_FILE_VERSION }
    for _, kind in ipairs(F.MOUTH_CHAR_ORDER) do
        local e = type(map) == "table" and map[kind]
        local spec = e and F.MouthSpec(e.items, kind) or ""
        if spec ~= "" then out[#out + 1] = F.MOUTH_CHAR_OF[kind] .. "\t" .. spec end
    end
    for _, b in ipairs(type(bad) == "table" and bad or {}) do
        if type(b.text) == "string" then out[#out + 1] = b.text end
    end
    return table.concat(out, "\n") .. "\n"
end

-- the page's words for a mouth: "7>16 45 %", "4", "0>8 80 % (scales)", "the f v slit", "your voice (up to 40 %)"
function F.MouthText(mouth, kind)
    local m = F.MouthNormal(mouth, kind)
    if not m then return tostring(mouth) end
    if m == "ladder" then return "your voice" end
    local lw = string.match(m, "^ladder@(.+)$")
    if lw then
        local w = tonumber(lw)
        if F.MOUTH_FV[kind] and math.abs(w - F.MOUTH_FV[kind]) < 1e-4 then return "the f v slit" end
        return string.format("your voice (up to %s %%)", string.format("%g", math.floor(w * 1000 + 0.5) / 10))
    end
    local scales = string.sub(m, -7) == ":scales"
    local base = scales and string.sub(m, 1, -8) or m
    local a, b, w = string.match(base, "^(%d+)>(%d+)@(.+)$")
    local words = base
    if a then
        words = string.format("%s>%s %s %%", a, b, string.format("%g", math.floor(tonumber(w) * 1000 + 0.5) / 10))
    end
    if scales then words = words .. " (scales)" end
    return words
end
