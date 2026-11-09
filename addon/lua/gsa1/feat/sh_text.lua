-- G-SA1 text in a chosen font (round 0.9.9g; the owner, sadc docs/research/gsa1_rounds_plan.md 14.1bg: "The created text stuff should be saved as textures at in-game resolutions so they don't have to be reloaded every
-- time."): the pure part, both realms, no engine call, so the tests run it as it is. feat/cl_text.lua does the drawing.
-- NO FONT FILE IS HERE AND NONE MAY BE: the three below are all rights reserved by their makers. The names are only what to ask the engine for. The files are looked for in garrysmod/resource/fonts on the player's own PC;
-- with no file an element keeps today's font. The pictures made from them live in render targets on that PC (1.0.0-beta1a; beta 1 saved PNGs in garrysmod/data/gsa1/textcache, deleted now) and
-- never go into the addon or a repo (repos/sync_repos.py refuses both).
GSA1 = GSA1 or {}
local T = GSA1.Text or {}
GSA1.Text = T

T.DIR = "gsa1/textcache"            -- garrysmod/data/...
T.FONT_DIR = "resource/fonts"       -- garrysmod/...
T.MAX_FILES, T.MAX_BYTES = 256, 16 * 1024 * 1024
T.PAD = 2                           -- px round the text in its picture: a letter may overhang its box
T.MAX_SIDE = 4096
T.VERSION = 3                       -- part of the hash: a new way of making them makes new ones (2, 1.0.0: every picture starts with a full-bucket replace draw, sadc docs/research/gsa1_100_select.md 4.8;
                                    -- every name changes, so a picture 0.9.9g made over another's leftovers is never loaded again. 3, 1.0.0-beta1a: no PNG any more, the pictures live in a
                                    -- render-target atlas, feat/cl_text.lua; the hash is only the picture's key there)

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
    -- (1.0.0-beta1a: the owner's pages, rounds plan 14.1bg, name ITC Bauhaus Bold for Character Select's names and Gill Sans Bold for its nameplates; MEASURED against the game's own m_sonic, m_knuckles,
    -- m_supersonic and B_SONIC_e, B_KNUCKLES_e, B_BIG_e, B_AMY_e: sadc/build/research/b1a/b1a-text/NOTES.md. Beta 1 drew both in Rodin, the title cards' face)
    skin_name = { title = "A skin's name under the character", font = "bauhaus", system = "arial_black", fallback = "DermaLarge" },
    skin_plate = { title = "A skin's nameplate", font = "gill", system = "arial_black", fallback = "DermaLarge" },
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

-- 1.0.0-beta1a, THE ATLAS (feat/cl_text.lua draws). Beta 1's pictures were PNGs of render targets that were never cleared (their clear asked for a depth buffer they do not have) and came out without alpha:
-- now a picture is a part of one of a few render-target pages, kept in the game's memory and drawn from there; no PNG is written or read. Pure: the packing, so the tests run it as it is.
T.PAGE_W, T.PAGE_H, T.PAGES = 2048, 1024, 4     -- 8 MB each (BGRA8888): the bound. A full atlas empties its least recently used page (its pictures are made again when next shown)
T.GUTTER = 2                                     -- px of clear between two pictures (bilinear filtering never reaches a neighbour)
T.CANARY = 4                                     -- the last rows of a page: its device-reset canary lives there, no picture
T.SHELF_STEP = 8                                 -- a shelf's height: the picture's, rounded up to this
T.MAX_MEM = 1024                                 -- the known texts' table: past this, entries of emptied pages are forgotten

function T.NewPage(w, h)
    return { w = w, h = h, shelves = {}, top = 0, n = 0, area = 0, gen = 1, used = 0 }
end

-- a place for a w x h picture on the page: x, y (and the page's counts updated), or nil. Shelves of one height class, left to right, top to bottom
function T.PackInto(page, w, h)
    local G = T.GUTTER
    if w <= 0 or h <= 0 or w > page.w or h > page.h - T.CANARY then return nil end
    local hc = math.ceil(h / T.SHELF_STEP) * T.SHELF_STEP
    for _, s in ipairs(page.shelves) do
        if s.h == hc and s.x + w <= page.w then
            local x = s.x
            s.x = s.x + w + G
            page.n, page.area = page.n + 1, page.area + w * h
            return x, s.y
        end
    end
    if page.top + hc > page.h - T.CANARY then return nil end
    local s = { y = page.top, h = hc, x = w + G }
    page.shelves[#page.shelves + 1] = s
    page.top = page.top + hc + G
    page.n, page.area = page.n + 1, page.area + w * h
    return 0, s.y
end

-- empties a page for new pictures: every picture it held is stale from now on (its generation changes)
function T.EmptyPage(page)
    page.shelves, page.top, page.n, page.area = {}, 0, 0, 0
    page.gen = page.gen + 1
    page.fresh = true
end

-- the page to empty when none has room: the least recently used (its last frame shown), the lowest number on a tie
function T.Victim(pages)
    local best, bi = nil, nil
    for i, p in ipairs(pages) do
        if not best or (p.used or 0) < (best.used or 0) then best, bi = p, i end
    end
    return bi
end
