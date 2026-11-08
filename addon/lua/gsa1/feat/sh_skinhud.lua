-- G-SA1 a skin's name and nameplate pictures, the pure part (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 4.7; the owner, rounds plan 14.1bg: "The created text stuff should be saved as textures at
-- in-game resolutions so they don't have to be reloaded every time", 14.1bj: auto_generate_name, name_tex_location ...). Both realms, no engine call, so the tests run it as it is; feat/cl_skinhud.lua draws.
-- For every skin whose auto_generate_* is true and whose picture does not exist, G-SA1 makes it once into garrysmod/data/gsa1/skins/<base>/<id>/HUD/ and lists it in HUD/generated.txt there. A picture that
-- exists is used as it is and never overwritten (the owner's own name.png, dropped in by hand, included); "Make the skins' name pictures again" deletes only the files generated.txt lists. NO FONT is shipped:
-- the pictures are made with feat/sh_text.lua's elements skin_name and skin_plate (the owner's test fonts if they are there, else a family Windows has). Nothing of the game's is here.
GSA1 = GSA1 or {}
local H = GSA1.SkinHud or {}
GSA1.SkinHud = H

-- the pictures, at 4 x the game's own textures (MEASURED, select 2.2: m_sonic 256 x 64, B_SONIC_e 512 x 64), so a material swap on the game's vertices is all a draw needs
H.NAME = { w = 1024, h = 256, letters = 44 / 64, max_w = 960, outline = 0.1 }            -- letters 44/64 of the height; squeezed to 240/256 (m_knuckles' own width); an outline a tenth of the letters
-- the plate (B_..._e, rows of 64 at 4 x): black frame rows 0-2 and 59-61, white field, black text in rows 10-29, a black bar in rows 34-53, over x 0..389; the rest clear
H.PLATE = { w = 2048, h = 256, scale = 4, x1 = 389, frame = 3, text0 = 10, text1 = 29, bar0 = 34, bar1 = 53, bottom = 61, margin = 8 }
H.GENERATED = "generated.txt"

-- the picture's file names in a skin's HUD folder (only these two, by the ini's own keys; an odd location gives nil and the game's picture stays)
function H.Paths(e)
    local K = GSA1.Skins
    if not (K and K.Folder and e and e.id and e.base) then return nil end
    local dir = K.Folder(e) .. "/HUD"
    return { dir = dir, list = dir .. "/" .. H.GENERATED, name = K.Location(e, e.name_tex_location), plate = K.Location(e, e.nameplate_tex_location) }
end

-- generated.txt -> { [file name] = true }: one name a line, only plain .png names (anything else in the file is ignored)
function H.ParseGenerated(text)
    local out = {}
    for line in string.gmatch(tostring(text or ""), "[^\r\n]+") do
        local n = string.match(line, "^%s*([%w_%-%.]+%.png)%s*$")
        if n and not string.find(n, "..", 1, true) then out[n] = true end
    end
    return out
end

function H.FormatGenerated(set)
    local names = {}
    for n in pairs(set or {}) do names[#names + 1] = n end
    table.sort(names)
    return "# made by G-SA1; \"Make the skins' name pictures again\" deletes only these\n" .. table.concat(names, "\n") .. (#names > 0 and "\n" or "")
end

-- the file name part of a DATA path
function H.Base(path)
    return string.match(tostring(path or ""), "([^/]+)$")
end

-- what to do for one picture: "load" (it exists), "make" (it does not, and auto_generate_* is on), "none"
function H.Wants(e, which, exists)
    if exists then return "load" end
    local auto = (which == "name") and e.auto_generate_name or e.auto_generate_nameplate
    return auto and "make" or "none"
end

-- the sideways squeeze of a text of width tw into at most max_w (1 = none)
function H.Squeeze(tw, max_w)
    tw = tonumber(tw) or 0
    if tw <= max_w or tw <= 0 then return 1 end
    return max_w / tw
end

-- the text of each picture: the name and the plate in capitals, as the game's
function H.TextOf(e, which)
    return string.upper(tostring(which == "name" and (e.char_name or e.title) or (e.char_nameplate or e.char_name or e.title)))
end
