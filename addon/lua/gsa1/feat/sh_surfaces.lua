-- G-SA1 surfaces (0.8; every SA1 ground kind since 0.9.2): the pure part of the ground types, in both realms (no GMod
-- call, no module call, no state). The client's settings, the module calls and the Q-menu page are cl_surfaces.lua.
-- Design: sadc docs/research/gsa1_060_dig.md 6.4 / F6 with its review; 0.9.2: gsa1_090_surfaces.md sections 2-5 and F3
-- with its review (C3: "not a floor" / "slide-off wall" on walls only; C5: snow's label; R4 G9: footprints stay hidden
-- until a footprint task exists in G-SA1's worlds); the module's side is src/module/bind_surfaces.cpp
-- (gsa1.SetSurfaceTable, SurfaceDefaults, SurfaceKind, SurfaceInfo; feature version 2).
--
-- What it is about: Sonic Adventure marks its ground: Knuckles digs only where the ground is diggable, Ice Cap's ice is
-- slippery and its snow slope slow to speed up, Sand Hill's sand slow, Speed Highway has fast ground, sliding floors and
-- speed tracks, stairs are walked upright, some walls cannot be stood on or climbed. A Garry's Mod map marks its ground
-- too - every material names a surface type ("grass", "concrete", "ice") - and G-SA1 turns those types into the game's
-- marks through a table: by default grass, dirt, mud, sand, gravel and snow are diggable, ice is slippery, everything
-- else is normal ground (the new kinds are the owner's choice). The owner can change any type on the Surfaces page; the
-- changes are kept in garrysmod/data/gsa1/surfaces.txt ("type = kinds" lines; 0.8's files read unchanged).
GSA1 = GSA1 or {}
local S = GSA1.Surfaces or {}
GSA1.Surfaces = S

S.NEEDS = { feature = "surfaces", version = 2, module = "0.9.2" }
S.FILE = "gsa1/surfaces.txt"            -- in DATA
-- the module's order (kinds_string: 0.8's five first, then 0.9.2's eight, so 0.8's strings stay the same)
S.ORDER = { "dig", "slippery", "sand", "hurt", "noclimb", "snow", "fast", "slide", "speedpath", "stairs", "noland",
            "wallslide", "footprints" }

-- the page's checklist, in the page's order (gsa1_090_surfaces.md 5.1 with Review C5): the module's word, the label, the
-- explanation (the tooltip), the SA1_SURFACE_* bit sa1_state.surface reports (the live line), walls = the kind goes on
-- the type's walls only, hidden = not offered yet
S.KINDS = {
    { id = "dig", title = "Diggable", bit = 0x1000,
      tip = "Knuckles can dig here (hold attack, press jump)" },
    { id = "slippery", title = "Ice", bit = 0x10,
      tip = "Like Ice Cap's ice: hard to speed up, you keep sliding" },
    { id = "snow", title = "Snow (slow to speed up)", bit = 0x8000,
      tip = "Like Ice Cap's snow slope: a seventh of the acceleration, you stop normally" },
    { id = "sand", title = "Slow sand", bit = 0x40,
      tip = "Like Sand Hill: half the acceleration" },
    { id = "fast", title = "Fast ground", bit = 0x80,
      tip = "Half again the acceleration" },
    { id = "slide", title = "Sliding floor", bit = 0x100,
      tip = "Speed Highway's sliding floor" },
    { id = "speedpath", title = "Speed track", bit = 0x10000,
      tip = "Speed Highway / Casinopolis track: keeps high-speed turns and slopes" },
    { id = "stairs", title = "Stairs", bit = 0x200,
      tip = "Walk up and down upright, as on the game's stairs (not for ordinary slopes)" },
    { id = "noland", title = "Not a floor (walls only)", bit = 0x400, walls = true,
      tip = "You cannot stand on it; it behaves like a wall. Only the walls of this type get it: on a floor it would trap you" },
    { id = "wallslide", title = "Slide-off wall (walls only)", bit = 0x800, walls = true,
      tip = "You slide off; you cannot stand on or climb it. Only the walls of this type get it" },
    { id = "noclimb", title = "No climbing", bit = 0x04,
      tip = "Knuckles cannot climb it" },
    { id = "hurt", title = "Hurts", bit = 0x08,
      tip = "Touching it hurts (you lose your rings; with none you die)" },
    { id = "footprints", title = "Footprints", bit = 0x20000, hidden = true,
      tip = "Leaves footprints, like Emerald Coast's beach (not yet: G-SA1's worlds have no footprint task)" },
}
S.PRECEDENCE = "Of snow, ice, slow sand and fast ground only the first counts (the game's own rule)."

local WORDS = { dig = "diggable", slippery = "slippery", sand = "slow sand", hurt = "hurts", noclimb = "no climbing",
                snow = "snow", fast = "fast ground", slide = "sliding floor", speedpath = "speed track", stairs = "stairs",
                noland = "not a floor", wallslide = "slide-off wall", footprints = "footprints" }
local KNOWN = {}
for _, w in ipairs(S.ORDER) do KNOWN[w] = true end
local ALIAS = { diggable = "dig", ice = "slippery", hurts = "hurt", no_climb = "noclimb", plain = "normal", none = "normal",
                boost = "fast", sliding = "slide", speed_path = "speedpath", speedtrack = "speedpath", stair = "stairs",
                no_land = "noland", wall_slide = "wallslide", footprint = "footprints" }

-- "Dig, sand" -> "dig,sand" (the module's order); "normal" for none; nil when a word is unknown
function S.NormalizeKinds(k)
    if type(k) ~= "string" then return nil end
    local have = {}
    for w in string.gmatch(string.lower(k), "[^,%s+|]+") do
        w = ALIAS[w] or w
        if KNOWN[w] then
            have[w] = true
        elseif w ~= "normal" then
            return nil
        end
    end
    local out = {}
    for _, w in ipairs(S.ORDER) do
        if have[w] then out[#out + 1] = w end
    end
    return #out > 0 and table.concat(out, ",") or "normal"
end

-- does a kinds string have the word?
function S.HasKind(kinds, word)
    local n = S.NormalizeKinds(kinds)
    if not n or n == "normal" then return false end
    for w in string.gmatch(n, "[^,]+") do
        if w == word then return true end
    end
    return false
end

-- a kinds string with the word added (on) or taken out (not on); "normal" when none is left
function S.WithKind(kinds, word, on)
    local n = S.NormalizeKinds(kinds) or "normal"
    local out = {}
    for w in string.gmatch(n, "[^,]+") do
        if w ~= "normal" and w ~= word then out[#out + 1] = w end
    end
    if on and KNOWN[word] then out[#out + 1] = word end
    return S.NormalizeKinds(#out > 0 and table.concat(out, ",") or "normal")
end

-- "dig,sand" -> "diggable, slow sand"; "normal" -> "normal ground"
function S.Describe(kinds)
    local n = S.NormalizeKinds(kinds) or "normal"
    if n == "normal" then return "normal ground" end
    local out = {}
    for w in string.gmatch(n, "[^,]+") do out[#out + 1] = WORDS[w] or w end
    return table.concat(out, ", ")
end

-- what the game makes of the ground it stands on: sa1_state.surface (SA1_SURFACE_* bits) -> { "diggable", ... } in the
-- page's order (every kind, footprints included)
function S.DecodeGame(surface)
    local out = {}
    if type(surface) ~= "number" then return out end
    for _, k in ipairs(S.KINDS) do
        if bit and bit.band and bit.band(surface, k.bit) ~= 0 then out[#out + 1] = WORDS[k.id] end
    end
    return out
end

-- a surface type name the module takes (bind_surfaces.cpp: 1..64 bytes of a-z 0-9 _ . - and spaces)
function S.ValidName(name)
    return type(name) == "string" and #name >= 1 and #name <= 64 and string.find(name, "^[a-z0-9_%.%- ]+$") ~= nil
end

-- the overrides file -> { [type] = kinds }, number of lines skipped. Lines "type = kinds"; '#' starts a comment.
function S.Parse(text)
    local out, bad = {}, 0
    if type(text) ~= "string" then return out, 0 end
    local n = 0
    for line in string.gmatch(text, "[^\r\n]+") do
        line = string.gsub(line, "#.*$", "")
        if string.find(line, "%S") then
            local name, kinds = string.match(line, "^%s*(.-)%s*=%s*(.-)%s*$")
            name = name and string.lower(name)
            kinds = S.NormalizeKinds(kinds)
            if S.ValidName(name) and kinds and n < 1024 then
                out[name] = kinds
                n = n + 1
            else
                bad = bad + 1
            end
        end
    end
    return out, bad
end

local function sorted_names(t)
    local names = {}
    for name in pairs(t) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- { [type] = kinds } -> the file's text (sorted, with a header)
function S.Serialize(t)
    local lines = { "# G-SA1 ground types: your changes to the Surfaces page's table (Options > G-SA1 > Surfaces).",
                    "# One \"surface type = kinds\" per line; kinds: normal, dig, slippery, sand, hurt, noclimb, snow, "
                    .. "fast, slide, speedpath, stairs, noland, wallslide (several: dig,sand)." }
    for _, name in ipairs(sorted_names(t or {})) do lines[#lines + 1] = name .. " = " .. t[name] end
    return table.concat(lines, "\n") .. "\n"
end

-- { [type] = kinds } -> { "type=kinds", ... } (gsa1.SetSurfaceTable's argument; sorted)
function S.ToList(t)
    local out = {}
    for _, name in ipairs(sorted_names(t or {})) do out[#out + 1] = name .. "=" .. t[name] end
    return out
end

-- the overrides for the ConVar mirror and the session log: "concrete=dig;ice=normal" (at most 240 characters)
function S.MirrorString(t)
    local s = table.concat(S.ToList(t), ";")
    if #s > 240 then s = string.sub(s, 1, 236) .. "..." end
    return s
end

-- a walkable area as a share of the map's: "7.5%" ("-" without any)
function S.Share(area, total)
    if not (type(area) == "number" and type(total) == "number") or total <= 0 or area <= 0 then return "-" end
    local p = 100 * area / total
    if p < 0.05 then return "<0.1%" end
    return string.format("%.1f%%", p)
end

-- each kind's share in gsa1.SurfaceInfo's numbers: "95.3% diggable, - slippery" (both always, as 0.8 wrote them), then
-- every other ground kind present (its share of the walkable ground), then "; walls: 4.0% not a floor, ..." (not a
-- floor, slide-off wall and no climbing: their share of the land that is no walkable ground) when the module has them
local FLOOR_KINDS = { "sand", "snow", "fast", "slide", "speedpath", "stairs", "hurt", "footprints" }
local WALL_KINDS = { "noland", "wallslide", "noclimb" }
function S.KindShares(i)
    if type(i) ~= "table" then return "" end
    local s = S.Share(i.dig, i.walkable) .. " diggable, " .. S.Share(i.slippery, i.walkable) .. " slippery"
    for _, k in ipairs(FLOOR_KINDS) do
        if type(i[k]) == "number" and i[k] > 0 then s = s .. ", " .. S.Share(i[k], i.walkable) .. " " .. WORDS[k] end
    end
    return s
end
function S.WallShares(i)
    if type(i) ~= "table" or type(i.walls) ~= "table" or type(i.wall) ~= "number" or i.wall <= 0 then return "" end
    local out = {}
    for _, k in ipairs(WALL_KINDS) do
        local a = i.walls[k]
        if type(a) == "number" and a > 0 then out[#out + 1] = S.Share(a, i.wall) .. " " .. WORDS[k] end
    end
    return #out > 0 and ("; walls: " .. table.concat(out, ", ")) or ""
end
