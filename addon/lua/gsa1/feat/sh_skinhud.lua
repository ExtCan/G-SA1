-- G-SA1 a skin's name and nameplate pictures, the pure part (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 4.7; the owner, rounds plan 14.1bg: "The created text stuff should be saved as textures at
-- in-game resolutions so they don't have to be reloaded every time", 14.1bj: auto_generate_name, name_tex_location ...). Both realms, no engine call, so the tests run it as it is; feat/cl_skinhud.lua draws.
-- 1.0.0-beta1a: a skin whose auto_generate_* is true gets its picture made each session (feat/cl_text.lua's painter: no PNG is written; since the names fix into the text pictures' atlas). Beta 1 saved PNGs that had no alpha, in the
-- wrong face and never drew (sadc/build/research/b1a/b1a-text/NOTES.md); the ones it listed in hud/generated.txt are deleted once. A name.png / nameplate.png the owner put in the skin's hud folder
-- (not listed there, or newer than the list) is used as it is and never touched. NO FONT is shipped: the pictures use feat/sh_text.lua's elements skin_name (Bauhaus, the game's own names' face) and
-- skin_plate (Gill Sans Bold, the game's own plates'), the owner's test fonts if they are there, else a family Windows has. Nothing of the game's is here: only numbers MEASURED on its pictures.
GSA1 = GSA1 or {}
local H = GSA1.SkinHud or {}
GSA1.SkinHud = H

-- the pictures, at H.SCALE x the game's own textures (MEASURED, select 2.2: m_sonic 256 x 64, B_SONIC_e 512 x 64), so a material swap on the game's vertices is all a draw needs
H.SCALE = H.SCALE or 4
-- THE NAME, in the game's px (MEASURED on m_sonic, m_knuckles, m_supersonic, m_tails, m_big, m_amy, m_e102 read from the disc at run time; numbers only): a flat fill in the character's colour, a black
-- outline 4 px wide all round (no inner line), the fill's capitals 37 px tall in rows 13..49 (with the outline rows 9..53), centred; long names squeezed sideways to 240 px with the outline (m_supersonic
-- 8..246); the letters close (fill to fill 3-6 px: the outlines merge): the game's face is ITC Bauhaus Bold (the owner's pages). Bauhaus Std Bold at 37 px with a tracking of -0.05 of the capitals gives
-- SONIC 140 px wide (the game's 143), KNUCKLES 224 (227), stems 10-15 px (11-15)
H.NAME = { gw = 256, gh = 64, cap = 37, cx = 128, cy = 31.5, outline = 4, max_w = 240, track = -0.05, space = 0.5, rows = { 9, 53 } }
-- THE PLATE (B_..._e, MEASURED on B_SONIC_e, B_KNUCKLES_e, B_BIG_e, B_AMY_E, B_SUPERSONIC_e): black 0..389 x 0..61, white 3..386 x 3..58, a black bar 9..380 x 34..53, the rest clear; black capitals 21 px
-- tall in rows 9..29 (centre 19.5), centred near x 193, long names squeezed to 370 px (x 10..379). Gill Sans Bold at a cap of 20.5 px with a tracking of +0.025: SONIC THE HEDGEHOG 369 px (the game's 370),
-- BIG THE CAT 207 (204); the game's stems one game pixel bolder: the fill drawn a quarter of a game pixel either side too
H.PLATE = { gw = 512, gh = 64, x1 = 389, bottom = 61, frame = 3, bar = { 9, 34, 380, 53 }, cap = 20.5, cx = 193, cy = 19.5, max_w = 370, track = 0.025, space = 1, bold = 0.25, rows = { 9, 29 } }
H.GENERATED = "generated.txt"
-- the fonts' own proportions (MEASURED on the owner's files and Windows' own, numbers only): the capitals' height and the ascent, each over the line's height (what surface.CreateFont's size is)
H.METRICS = {
    bauhaus = { cap = 0.5873, asc = 0.8103 }, gill = { cap = 0.5702, asc = 0.7995 }, rodin = { cap = 0.5821, asc = 0.8224 },
    arial_black = { cap = 0.507, asc = 0.7805 }, impact = { cap = 0.6477, asc = 0.8271 },
}
H.METRICS_DEFAULT = { cap = 0.62, asc = 0.8 }        -- (today's engine fonts: a guess, corrected by the read-back below)
H.MAX_FONT = 128                                      -- the largest font size made (seen drawn in the owner's game, beta 1); larger letters are scaled up

-- a picture's layout in the target's px: { w, h, s (px per game px), and the fields above times s }
function H.Layout(which, scale)
    local s = scale or H.SCALE
    local L = which == "name" and H.NAME or H.PLATE
    local o = { w = L.gw * s, h = L.gh * s, s = s, which = which }
    for k, v in pairs(L) do
        if type(v) == "number" and k ~= "gw" and k ~= "gh" and k ~= "w" and k ~= "h" and k ~= "track" and k ~= "space" then o[k] = v * s end
    end
    o.track, o.space = L.track, L.space
    if L.bar then o.bar = { L.bar[1] * s, L.bar[2] * s, L.bar[3] * s, L.bar[4] * s } end
    o.rows = { L.rows[1] * s, L.rows[2] * s + s - 1 }      -- (the game's own letters' rows, MEASURED: the name's with its outline, the plate's capitals)
    return o
end
-- (beta 1's fields, kept for its callers: the sizes)
H.NAME.w, H.NAME.h = H.NAME.gw * H.SCALE, H.NAME.gh * H.SCALE
H.PLATE.w, H.PLATE.h = H.PLATE.gw * H.SCALE, H.PLATE.gh * H.SCALE

-- the scale for a screen of sw x sh px: H.SCALE at most, and small enough that the plate's frame (H.PLATE.x1 + 1 game px wide) and a picture's height fit inside the screen (the verifier's LOW,
-- UNVERIFIED whether Garry's Mod draws into a render target past the screen's size: this keeps every drawn texel inside it either way). The owner's 3440 x 1440, and 1920 x 1080, take 4
function H.ScaleFor(sw, sh)
    local s = H.SCALE
    sw, sh = tonumber(sw), tonumber(sh)
    if not (sw and sh) or sw <= 0 or sh <= 0 then return s end
    while s > 1 and ((H.PLATE.x1 + 1) * s > sw or H.PLATE.gh * s > sh) do s = s - 1 end
    return s
end

-- where the letters go: L a layout, th the font's line height in its px (GetTextSize), adv the letters' natural width in font px (spaces already times L.space), n letters, m the font's metrics.
-- -> sx, sy (target px per font px), x, y (the line box's top left), track (target px between letters), width (the fill's, target px)
function H.Fit(L, th, adv, n, m)
    th = math.max(1, tonumber(th) or 1)
    local sy = L.cap / (th * m.cap)
    local track = L.track * L.cap
    local width = adv * sy + track * math.max(0, n - 1)
    local sx = sy
    local room = L.max_w - 2 * (L.outline or 0)
    if width > room and width > 0 then
        local k = room / width
        sx, track, width = sy * k, track * k, room
    end
    local x = L.cx - width / 2
    local y = (L.cy - L.cap / 2) - (m.asc - m.cap) * th * sy
    return sx, sy, x, y, track, width
end

-- the picture's file names in a skin's hud folder (only these two, by the ini's own keys; an odd location gives nil and the game's picture stays). Lower case: Garry's Mod writes the data folder so
-- (the owner's folders read "hud"); Windows finds either
function H.Paths(e)
    local K = GSA1.Skins
    if not (K and K.Folder and e and e.id and e.base) then return nil end
    local dir = string.lower(K.Folder(e) .. "/HUD")
    local function low(p) return p and string.lower(p) or nil end
    return { dir = dir, list = dir .. "/" .. H.GENERATED, name = low(K.Location(e, e.name_tex_location)), plate = low(K.Location(e, e.nameplate_tex_location)) }
end

-- generated.txt -> { [file name] = true }: one name a line, only plain .png names (anything else in the file is ignored)
function H.ParseGenerated(text)
    local out = {}
    for line in string.gmatch(tostring(text or ""), "[^\r\n]+") do
        local n = string.match(line, "^%s*([%w_%-%.]+%.png)%s*$")
        if n and not string.find(n, "..", 1, true) then out[string.lower(n)] = true end
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

-- is a file one G-SA1 made (beta 1)? Listed in generated.txt and not newer than the list (G-SA1 wrote the list right after the picture; a file the owner dropped in over it later is theirs)
function H.IsMade(set, base, t_file, t_list)
    if not (set and base and set[string.lower(base)]) then return false end
    t_file, t_list = tonumber(t_file) or 0, tonumber(t_list) or 0
    if t_file > 0 and t_list > 0 and t_file > t_list + 2 then return false end
    return true
end

-- what to do for one picture: "load" (the owner's own file is there), "make" (none, and auto_generate_* is on), "none"
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

-- THE NAMES FIX after 1.0.0-beta1a (sadc/build/research/b1a2: the owner, "The pulsating names appear for a second and then turn into black squares"). Beta 1a made each name and plate in a whole render
-- target of its own (1024 x 256, 2048 x 256), drew it smaller than its texels through mesh on the game's own vertices, and never read it again after its make: a lost canvas stayed a silent black box
-- (MEASURED, the trace lane's negative control). NOW each picture is a part of a text atlas page (feat/cl_text.lua, the pages that kept the bar's labels right all through the owner's session), drawn
-- with surface.DrawTexturedRectUV as the labels are (feat/cl_charselect_bar.lua S.DrawFilter), never smaller than the owner's game has shown right, and read again once a second while shown: a picture
-- that ever reads changed is never drawn again; the game's own name and plate are. Pure numbers here, the tests run them as they are.
H.MARGIN = 8                  -- game px of clear round a picture in its atlas box: a letter painted a little off (before the read-back corrects it) stays inside the box, never on a neighbour
H.CHECK_PERIOD = 1            -- s between two reads of the self-check (all pictures together: one read at most a second)
-- b1a2-fix2: a read is no longer a whole page's capture (8 MiB) but the few texels it checks, drawn through the page's own material into a 16 x 4 target (feat/cl_text.lua T.ReadTexels): the
-- checks stay once a second, and go every H.CHECK_PERIOD_SLOW s only if one of THOSE reads still takes H.CHECK_SLOW_MS or more (said in the log)
H.CHECK_PERIOD_SLOW = 5       -- s between two reads once one small read took H.CHECK_SLOW_MS or more (a hitch each second otherwise)
H.CHECK_SLOW_MS = 10
H.CHECK_KEPT = 5              -- s after a picture's first draw: the first read right from then on says so in the log, once
H.CHECK_TOL = 8               -- a channel may differ this much from what was read at the make (the canary's tolerance, cl_text.lua)
H.SHOWN_FRAMES = 2            -- a picture is shown while it was drawn in one of the last frames
H.RESHOW = 2                  -- s away: the next draw is a new show (its first read comes H.CHECK_PERIOD after it)
H.EPS = 0.01                  -- s: half a frame and more, so a 60 Hz clock lands on whole seconds

-- the scale of the atlas pictures for a screen of sw x sh px and a page part of pw x ph px (cl_text.lua T.PageBound, T.MaxPicH): never drawn smaller than 0.8 of its texels (the pulse's
-- smallest, 0.615 of the game's size, then reads 0.77 of a texel a pixel at the least, the atlas's own drawn range on the upgrade row), at most H.ScaleFor's, and the plate with its margin inside
-- the page. 3440 x 1440: 2 (the name 512 x 128, the plate 1024 x 128); 1920 x 1080: 1
function H.AtlasScale(sw, sh, pw, ph)
    local s = H.ScaleFor(sw, sh)
    sw, sh = tonumber(sw), tonumber(sh)
    if sw and sh and sw > 0 and sh > 0 then s = math.min(s, math.floor(0.8 * math.min(sw / 640, sh / 480))) end
    s = math.max(1, s)
    pw, ph = tonumber(pw) or 2048, tonumber(ph) or 1016
    while s > 1 and ((H.PLATE.gw + 2 * H.MARGIN) * s > pw or (H.PLATE.gh + 2 * H.MARGIN) * s > ph) do s = s - 1 end
    return s
end

-- a picture's texel that must stay clear, in its own px: the name's top left, the plate's right of its black frame
function H.ClearPoint(L)
    if L.which == "name" then return 2, 1 end
    return (H.PLATE.x1 + 1) * L.s + 2, L.h - 2
end

-- the self-check's verdict on one picture: made = { clear = { r, g, b, a }, ink = { r, g, b, a }, clear_alpha_only = true (a made picture: alpha 1 at most) }, got = the same read now.
-- -> nil (right) or what changed
local function near(a, b, tol)
    return a ~= nil and b ~= nil and math.abs(a - b) <= tol
end
local function rgba(c) return string.format("%d %d %d %d", c[1], c[2], c[3], c[4]) end
H.RGBA = rgba
function H.CheckVerdict(made, got)
    local tol = H.CHECK_TOL
    local bad = {}
    local c, mc = got.clear, made.clear
    if made.clear_alpha_only then
        if not (c[4] <= 1) then bad[#bad + 1] = string.format("clear alpha %d, made %d", c[4], mc[4]) end
    elseif not (near(c[1], mc[1], tol) and near(c[2], mc[2], tol) and near(c[3], mc[3], tol) and near(c[4], mc[4], tol)) then
        bad[#bad + 1] = string.format("clear %s, made %s", rgba(c), rgba(mc))
    end
    local i, mi = got.ink, made.ink
    if not (near(i[1], mi[1], tol) and near(i[2], mi[2], tol) and near(i[3], mi[3], tol) and near(i[4], mi[4], tol)) then
        bad[#bad + 1] = string.format("ink %s, made %s", rgba(i), rgba(mi))
    end
    if #bad == 0 then return nil end
    return table.concat(bad, "; ")
end

-- the page's canary as read now against `want`: b1a2-fix2, what the same read gave at the page's make (cl_text.lua p.canary0, { r, g, b, a }), not the painted T.CANARY_RGB (a want of three
-- channels is taken at alpha 0). Every channel within H.CHECK_TOL: nil (right), else how it reads
function H.CanaryVerdict(c, want)
    local tol = H.CHECK_TOL
    if near(c[1], want[1], tol) and near(c[2], want[2], tol) and near(c[3], want[3], tol) and near(c[4], want[4] or 0, tol) then return nil end
    return rgba(c)
end
