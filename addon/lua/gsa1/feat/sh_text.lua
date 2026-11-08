-- G-SA1 text in a chosen font (round 0.9.9g; the owner, sadc docs/research/gsa1_rounds_plan.md 14.1bg: "The created text stuff should be saved as textures at in-game resolutions so they don't have to be reloaded every
-- time."): the pure part, both realms, no engine call, so the tests run it as it is. feat/cl_text.lua does the drawing.
-- NO FONT FILE IS HERE AND NONE MAY BE: the three below are all rights reserved by their makers. The names are only what to ask the engine for. The files are looked for in garrysmod/resource/fonts on the player's own PC;
-- with no file an element keeps today's font. The pictures made from them go to garrysmod/data/gsa1/textcache on that PC and never into the addon or a repo (repos/sync_repos.py refuses both).
GSA1 = GSA1 or {}
local T = GSA1.Text or {}
GSA1.Text = T

T.DIR = "gsa1/textcache"            -- garrysmod/data/...
T.FONT_DIR = "resource/fonts"       -- garrysmod/...
T.MAX_FILES, T.MAX_BYTES = 256, 16 * 1024 * 1024
T.PAD = 2                           -- px round the text in its picture: a letter may overhang its box
T.MAX_SIDE = 4096
T.VERSION = 2                       -- part of the hash: a new way of making them makes new ones (2, 1.0.0: every picture starts with a full-bucket replace draw, sadc docs/research/gsa1_100_select.md 4.8;
                                    -- every name changes, so a picture 0.9.9g made over another's leftovers is never loaded again)

-- family: the family name in the font's own name table (MEASURED on the owner's files), which is what surface.CreateFont asks for
T.FONTS = {
    rodin = { title = "FOT-Rodin Pro UB", family = "FOT-Rodin Pro UB", file = "FOT-Rodin Pro UB.otf", weight = 400 },
    gill = { title = "Gill Sans Bold", family = "Gill Sans", file = "Gill Sans Bold.otf", weight = 700 },
    bauhaus = { title = "Bauhaus Std Bold", family = "Bauhaus Std Medium", file = "BauhausStd-Bold.ttf", weight = 700 },
    -- 1.0.0 (select 4.7 with RX.11): the families Windows has, the new elements' second choice; no file is looked for, the engine is only asked (T.Probe tells whether it took one)
    arial_black = { title = "Arial Black", family = "Arial Black", weight = 900, system = true },
    impact = { title = "Impact", family = "Impact", weight = 400, system = true },
}
T.FONT_ORDER = { "rodin", "gill", "bauhaus" }       -- the owner's three test copies (their files are only looked for, never shipped)

-- the elements that use it, and today's font each falls back to. Nothing else in the addon changes its look. Bauhaus is the sure test: a .ttf; whether .otf loads is the first thing this shows
-- 1.0.0 (select 4.7 with RX.11; the owner, 14.1bg: "The fonts on my PC would be useful just to test the feature"): each new element names one of the owner's three first, then a family Windows has (system),
-- then today's engine font (fallback). The choice of each is here and nowhere else
T.ELEMENTS = {
    photo_hint = { title = "Photo mode's reminder", font = "rodin", fallback = "DermaLarge" },
    charselect_skin = { title = "Character Select's skin line", font = "bauhaus", fallback = "GSA1CharSelectHint" },        -- (1.0.0: the simple chooser's only)
    skin_name = { title = "A skin's name under the character", font = "rodin", system = "arial_black", fallback = "DermaLarge" },
    skin_plate = { title = "A skin's nameplate", font = "rodin", system = "arial_black", fallback = "DermaLarge" },
    upgrades_title = { title = "CHOOSE YOUR UPGRADE", font = "rodin", system = "arial_black", fallback = "DermaLarge" },
    upgrades_status = { title = "The upgrades' ACTIVE/VISIBLE lines", font = "bauhaus", system = "impact", fallback = "DermaLarge" },
    upgrades_name = { title = "The upgrades' names", font = "bauhaus", system = "impact", fallback = "DermaLarge" },
    bar_label = { title = "The bar's Upgrades, Skins and the two tabs", font = "gill", system = "arial_black", fallback = "DermaDefaultBold" },
}
T.ELEMENT_ORDER = { "photo_hint", "charselect_skin", "skin_name", "skin_plate", "upgrades_title", "upgrades_status", "upgrades_name", "bar_label" }

-- two FNV-1a, 32 bits each, one forwards and one backwards so that a pair that meets in one does not meet in the other, written so that no step leaves a double's exact range
local function fnv(s, h, first, last, step)
    local band, bxor, lshift, tobit = bit.band, bit.bxor, bit.lshift, bit.tobit
    for i = first, last, step do
        h = bxor(h, string.byte(s, i))
        h = tobit(lshift(h, 24) + band(h, 0xFFFF) * 403 + band(bit.rshift(h, 16), 0xFFFF) * 403 * 65536)
    end
    return h
end

function T.Hash(s)
    return bit.tohex(fnv(s, bit.tobit(0x811C9DC5), 1, #s, 1)) .. bit.tohex(fnv(s, bit.tobit(0x050C5D1F), #s, 1, -1))
end

-- the picture's file name: a hash of everything that makes it what it is
function T.FileName(text, font, size, color, sw, sh, outline)
    local f = T.FONTS[font]
    text = tostring(text)
    -- (the text's length first: whatever bytes it holds, it cannot run into the next field; 1.0.0: the outline's key, its width or "width:r,g,b", when there is one)
    local key = table.concat({ tostring(T.VERSION), tostring(#text), text, tostring(font), f and f.family or "", tostring(size), tostring(color.r), tostring(color.g), tostring(color.b),
        tostring(color.a or 255), tostring(sw), tostring(sh), tostring(outline or 0) }, "\0")
    return T.Hash(key) .. ".png"
end

-- the render target's side for a picture's: render targets are never freed, so a few sizes only
function T.Bucket(v)
    local b = 64
    while b < v do b = b * 2 end
    return b
end

-- what to delete so that the folder keeps to its bounds: oldest first. list: { { name =, size =, time = }, ... }; keep: a name never to delete
function T.Trim(list, max_files, max_bytes, keep)
    local sorted, total = {}, 0
    for _, e in ipairs(list) do
        sorted[#sorted + 1] = e
        total = total + (tonumber(e.size) or 0)
    end
    table.sort(sorted, function(a, b)
        if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) < (b.time or 0) end
        return a.name < b.name
    end)
    local out, n = {}, #sorted
    for _, e in ipairs(sorted) do
        if n <= max_files and total <= max_bytes then break end
        if e.name ~= keep then
            out[#out + 1] = e.name
            n = n - 1
            total = total - (tonumber(e.size) or 0)
        end
    end
    return out
end
