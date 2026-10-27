-- G-SA1 emote wheel, the pure part (round 0.9.4a: sadc docs/research/faces_wheel_plan.md 4.6, 5.5, 7.1, 8.1, 8.3 with its
-- Review R.9 / R.18 and the owner's answers 10.1; faces_wheel_ui.md 2, 3; super2_plan.md 10.2, the CORRECTED reading;
-- round 0.9.4b, objects2_plan.md 11.2: the per-slot "Hold the last pose", the fonts per wheel size, the wheel's design;
-- round 0.9.4e, gsa1_rounds_plan.md 14.1aa: the per-slot play rate and the file's speed column).
-- GSA1.Wheel = W: the wheel's geometry (the slot of a direction, the 4-degree hysteresis, the centre, the quads the HUD
-- draws), the file data/gsa1/emote_wheel.txt (parse, serialize, the read-only mirror), the default wheels (names only), how
-- a slot finds its animation again (by key while the key's entry still has the stored internal name, else by that name -
-- internal names are not unique: review R.9), the keys the wheel may not use. No GMod calls at load: feat/cl_wheel.lua
-- (input, the HUD, the page) and the tests use it. The animations themselves are the game's (libsa1's catalogue through
-- the module's gsa1.EmoteList); this file holds only names and numbers.
GSA1 = GSA1 or {}
GSA1.Wheel = GSA1.Wheel or {}
local W = GSA1.Wheel

W.NEEDS = { feature = "emote", version = 1, module = "0.9.4a" }
W.PAGES, W.SLOTS = 4, 8
W.FILE = "gsa1/emote_wheel.txt"
W.CENTRE = 0.35                 -- inside this part of the radius nothing is highlighted (the centre)
W.HYSTERESIS = 4                -- degrees past a border before the highlight changes
W.CURSOR_MAX = 1.2              -- the mouse cursor's reach (the rim = 1)
W.MOUSE_COUNTS = 300            -- mouse counts from the centre to the rim at sensitivity 1
W.TAP = 0.2                     -- s: a release this soon with nothing highlighted is a tap
-- a slot's options (the file's options column): loop = "loop it"; nohold = "Hold the last pose" switched OFF (round 0.9.4b,
-- objects2_plan.md 11.2: on by default, so only the exception is written)
W.OPTIONS = { loop = true, nohold = true }
-- round 0.9.4b: the end mode HOLD needs the module's feature "emote" version 2 (gsa1.EMOTE.HOLD); older modules play the
-- animation as 0.9.4a did (back to standing)
W.HOLD_NEEDS = { feature = "emote", version = 2, module = "0.9.4b" }

-- round 0.9.4e (gsa1_rounds_plan.md 14.1aa; the owner: "being able to change the animation's play rate"): each slot has a
-- play rate (W.SPEEDS, default 1x: the game's own rate) and gsa1_wheel_speed (W.SPEED_MIN..W.SPEED_MAX, default 1)
-- multiplies every one; the product goes to the module as gsa1.Emote's 4th argument, libsa1's sa1_emote_item.speed ("a
-- multiplier of the game's rate"; libsa1 takes 1/64..16: W.LIB_SPEED_MIN / MAX). It needs the module's feature "emote"
-- version 3; an older module plays at the game's rate. Only the body animation: a slot's face animation keeps its own
-- timing (the frames of its sequence, the Faces page).
W.SPEED_NEEDS = { feature = "emote", version = 3, module = "0.9.4e" }
W.SPEEDS = { 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4 }
W.SPEED_MIN, W.SPEED_MAX = 0.25, 4
W.LIB_SPEED_MIN, W.LIB_SPEED_MAX = 1 / 64, 16

-- a slot's own play rate (nil, a bad or out-of-range value: 1)
function W.SlotSpeed(slot)
    local v = slot and tonumber(slot.speed)
    if not v or v ~= v or v < W.SPEED_MIN or v > W.SPEED_MAX then return 1 end
    return v
end
-- the rate an animation plays at: the slot's x the global one (gsa1_wheel_speed; nil / bad: 1), kept inside libsa1's range
function W.PlayRate(slot, global)
    local g = tonumber(global)
    if not g or g ~= g or g <= 0 then g = 1 end
    local r = W.SlotSpeed(slot) * g
    return math.min(math.max(r, W.LIB_SPEED_MIN), W.LIB_SPEED_MAX)
end
-- "2x", "0.5x", "0.75x", "1.5x", "0.0625x" (4 decimals at most)
function W.SpeedText(v)
    return string.format("%gx", math.floor((tonumber(v) or 1) * 10000 + 0.5) / 10000)
end
-- the file's speed column: "" -> nil (1x); a number in W.SPEED_MIN..W.SPEED_MAX -> it (1 -> nil); else nil, why
function W.ParseSpeed(text)
    text = tostring(text or "")
    if text == "" then return nil end
    local v = string.match(text, "^%d+%.?%d*$") and tonumber(text) or nil
    if not v or v < W.SPEED_MIN or v > W.SPEED_MAX then return nil, "speed " .. text end
    if v == 1 then return nil end
    return v
end

-- does a slot hold its animation's last frame (round 0.9.4b): its "Hold the last pose" is on (the default), it is not
-- looped ("loop it") and the animation plays once (a looping animation loops until the player moves). e: the catalogue
-- entry ({ play = "loop" / "once" / "hold" }); nil: unknown -> false
function W.HoldApplies(slot, e)
    if not slot or not e or slot.loop or slot.nohold then return false end
    return e.play ~= "loop"
end

-- the slot of a direction: degrees clockwise from up (0 = up, 90 = right); slot 1 up, then clockwise
function W.SlotOfAngle(deg)
    local a = (tonumber(deg) or 0) % 360
    return math.floor(((a + 22.5) % 360) / 45) + 1
end

-- the direction of a slot's middle (degrees clockwise from up)
function W.AngleOfSlot(slot)
    return ((tonumber(slot) or 1) - 1) * 45
end

-- degrees clockwise from up of a vector (x right, y UP); the mouse's y grows downwards: pass -dy
function W.Angle(x, y)
    return math.deg(math.atan2(x, y)) % 360
end

-- the highlighted slot for a direction with the hysteresis: prev stays while the direction is inside its sector widened
-- by W.HYSTERESIS degrees on both sides
function W.Pick(prev, deg)
    if prev and prev >= 1 and prev <= W.SLOTS then
        local d = math.abs(((deg - W.AngleOfSlot(prev)) + 180) % 360 - 180)
        if d <= 22.5 + W.HYSTERESIS then return prev end
    end
    return W.SlotOfAngle(deg)
end

-- the mouse cursor (x right, y up; the rim = 1) after a mouse move of (dx, dy) counts (dy down) at a sensitivity
function W.MoveCursor(cx, cy, dx, dy, sens)
    local k = (tonumber(sens) or 1) / W.MOUSE_COUNTS
    cx = cx + (tonumber(dx) or 0) * k
    cy = cy - (tonumber(dy) or 0) * k
    local len = math.sqrt(cx * cx + cy * cy)
    if len > W.CURSOR_MAX then
        cx, cy = cx * W.CURSOR_MAX / len, cy * W.CURSOR_MAX / len
    end
    return cx, cy
end

-- the slot the cursor points at (0: the centre)
function W.CursorSlot(prev, cx, cy)
    if math.sqrt(cx * cx + cy * cy) < W.CENTRE then return 0 end
    return W.Pick(prev ~= 0 and prev or nil, W.Angle(cx, cy))
end

-- the slot a point of a drawn wheel is in (x right, y DOWN from the wheel's centre; radii in the same unit): 0 the centre
-- (inside the inner radius), nil outside the wheel
function W.SlotAt(x, y, rin, rout)
    local len = math.sqrt(x * x + y * y)
    if len > rout then return nil end
    if len < rin then return 0 end
    return W.SlotOfAngle(W.Angle(x, -y))
end

-- the wheel's drawing: per slot `steps` convex quads (an annular sector is not convex) of { {x =, y =}, ... } in screen
-- coordinates (y down), clockwise on screen (surface.DrawPoly draws clockwise polygons), a gap of `gap` degrees between
-- sectors. Computed once per screen and wheel size (feat/cl_wheel.lua keeps them).
function W.SectorQuads(cx, cy, rin, rout, gap, steps)
    steps = steps or 6
    gap = gap or 1.5
    local out = {}
    for s = 1, W.SLOTS do
        local a0 = W.AngleOfSlot(s) - 22.5 + gap / 2
        local a1 = W.AngleOfSlot(s) + 22.5 - gap / 2
        local quads = {}
        for i = 0, steps - 1 do
            local b0 = math.rad(a0 + (a1 - a0) * i / steps)
            local b1 = math.rad(a0 + (a1 - a0) * (i + 1) / steps)
            local s0, c0, s1, c1 = math.sin(b0), math.cos(b0), math.sin(b1), math.cos(b1)
            quads[#quads + 1] = {
                { x = cx + s0 * rout, y = cy - c0 * rout },
                { x = cx + s1 * rout, y = cy - c1 * rout },
                { x = cx + s1 * rin, y = cy - c1 * rin },
                { x = cx + s0 * rin, y = cy - c0 * rin },
            }
        end
        out[s] = quads
    end
    return out
end

-- where a slot's label goes (the sector's middle, half-way between the radii)
function W.LabelPos(cx, cy, rin, rout, slot)
    local a = math.rad(W.AngleOfSlot(slot))
    local r = (rin + rout) / 2
    return cx + math.sin(a) * r, cy - math.cos(a) * r
end

-- a point at `r` from (cx, cy) in the direction `deg` (clockwise from up; screen y down)
function W.Polar(cx, cy, r, deg)
    local a = math.rad(deg)
    return cx + math.sin(a) * r, cy - math.cos(a) * r
end

-- a full ring (r0 < r1) as n convex quads, clockwise on screen (round 0.9.4b: the wheel's rims)
function W.RingQuads(cx, cy, r0, r1, n)
    n = n or 48
    local out = {}
    for i = 0, n - 1 do
        local a0, a1 = i * 360 / n, (i + 1) * 360 / n
        local x0, y0 = W.Polar(cx, cy, r1, a0)
        local x1, y1 = W.Polar(cx, cy, r1, a1)
        local x2, y2 = W.Polar(cx, cy, r0, a1)
        local x3, y3 = W.Polar(cx, cy, r0, a0)
        out[#out + 1] = { { x = x0, y = y0 }, { x = x1, y = y1 }, { x = x2, y = y2 }, { x = x3, y = y3 } }
    end
    return out
end

-- a filled circle as one convex polygon of n points, clockwise on screen
function W.Disc(cx, cy, r, n)
    n = n or 32
    local out = {}
    for i = 0, n - 1 do
        local x, y = W.Polar(cx, cy, r, i * 360 / n)
        out[#out + 1] = { x = x, y = y }
    end
    return out
end

-- twice the signed area of a polygon in screen coordinates (y down): > 0 when it runs clockwise on screen, the way
-- surface.DrawPoly needs it
function W.PolyArea2(poly)
    local a = 0
    for i = 1, #poly do
        local p, q = poly[i], poly[i % #poly + 1]
        a = a + p.x * q.y - q.x * p.y
    end
    return a
end

-- the separators: a thin radial bar (width px) in the middle of each gap between two sectors, from rin to rout; one
-- convex quad per border, clockwise on screen
function W.SeparatorQuads(cx, cy, rin, rout, width)
    local out = {}
    local h = (tonumber(width) or 2) / 2
    for s = 1, W.SLOTS do
        local b = math.rad(W.AngleOfSlot(s) - 22.5)
        local dx, dy = math.sin(b), -math.cos(b)          -- outwards
        local nx, ny = -dy, dx                            -- across (clockwise side)
        local q = {
            { x = cx + dx * rout - nx * h, y = cy + dy * rout - ny * h },
            { x = cx + dx * rout + nx * h, y = cy + dy * rout + ny * h },
            { x = cx + dx * rin + nx * h, y = cy + dy * rin + ny * h },
            { x = cx + dx * rin - nx * h, y = cy + dy * rin - ny * h },
        }
        if W.PolyArea2(q) < 0 then q = { q[4], q[3], q[2], q[1] } end
        out[s] = q
    end
    return out
end

-- the wheel's radii in pixels for a screen height and the size setting (faces_wheel_ui.md 2.2: 0.30 / 0.12 x ScrH)
function W.Radii(sh, size)
    local k = (tonumber(sh) or 768) * math.max(tonumber(size) or 1, 0.1)
    return 0.30 * k, 0.12 * k
end

-- the wheel's fonts (round 0.9.4b, the owner: "The animation wheel's font doesn't resize with the wheel ... the font
-- sucks"): fonts Garry's Mod ships (garrysmod/resource/fonts: "Roboto", "Roboto Cn" = Roboto Condensed, "Roboto Bk" =
-- Roboto Black - the tool gun's own font) or that Windows always has; never a font file of G-SA1's. Per choice (the
-- setting gsa1_wheel_font, 0-based) the face and weight of each role: label (a slot's animation name), small (numbers,
-- details, the hint), big (the centre's name: condensed, so long internal names fit), toast (what plays).
W.FONT_CHOICES = {
    { title = "Roboto (Garry's Mod's own)", label = { "Roboto Cn", 700 }, small = { "Roboto", 500 },
      big = { "Roboto Cn", 700 }, toast = { "Roboto Bk", 900 } },
    { title = "Segoe UI (Windows)", label = { "Segoe UI", 700 }, small = { "Segoe UI", 400 }, big = { "Segoe UI", 800 },
      toast = { "Segoe UI", 800 } },
    { title = "Bahnschrift (Windows 10 and 11)", label = { "Bahnschrift", 600 }, small = { "Bahnschrift", 400 },
      big = { "Bahnschrift", 700 }, toast = { "Bahnschrift", 700 } },
    { title = "Coolvetica (Garry's Mod's classic)", label = { "Coolvetica", 500 }, small = { "Roboto", 500 },
      big = { "Coolvetica", 500 }, toast = { "Coolvetica", 500 } },
}
W.FONT_ROLES = { "label", "small", "big", "toast" }
-- an even pixel size (fewer distinct fonts while the size slider moves), clamped
local function even_px(v, lo, hi)
    return math.max(lo, math.min(hi, math.floor(v / 2 + 0.5) * 2))
end
-- the pixel sizes of the roles for a screen height and the wheel's size: label / small / big follow the wheel's outer
-- radius (so they scale with gsa1_wheel_size and the screen), toast the screen only
function W.FontSizes(sh, size)
    local rout = W.Radii(sh, size)
    return { label = even_px(rout * 0.072, 10, 96), small = even_px(rout * 0.050, 10, 64),
             big = even_px(rout * 0.105, 14, 128), toast = even_px((tonumber(sh) or 768) * 0.030, 14, 96) }
end
-- the Garry's Mod font name of a role at a choice and size (made once per name by feat/cl_wheel.lua)
function W.FontName(role, choice, px)
    return string.format("gsa1_wheel_%s_%d_%d", role, tonumber(choice) or 0, tonumber(px) or 0)
end
-- the surface.CreateFont data of a role
function W.FontData(role, choice, px)
    local c = W.FONT_CHOICES[(tonumber(choice) or 0) + 1] or W.FONT_CHOICES[1]
    local f = c[role] or c.label
    return { font = f[1], size = px, weight = f[2], antialias = true, extended = true }
end

-- the wheel's accent colour (round 0.9.4b): the character's (Sonic blue, Tails orange, Knuckles red, Amy pink, E-102 grey,
-- Big purple), gold for Super Sonic - both entries, and Sonic while he is Super (super: true)
W.GOLD = { 255, 196, 40 }
function W.Accent(entry, super)
    if super then return W.GOLD end
    return W.COLOURS[entry] or W.COLOURS.sonic
end

-- the open / close animation (round 0.9.4b): 0..1 eased (ease-out cubic)
W.OPEN_TIME, W.CLOSE_TIME = 0.14, 0.12
function W.Ease(t)
    t = math.min(math.max(tonumber(t) or 0, 0), 1)
    local u = 1 - t
    return 1 - u * u * u
end
-- one step of a highlight's glow toward its target (0 or 1) over dt seconds (about 60 ms to most of the way)
function W.GlowStep(g, target, dt)
    local k = 1 - math.exp(-math.max(tonumber(dt) or 0, 0) * 22)
    return g + (target - g) * k
end

-- a text shortened with "..." to at most n characters
function W.Shorten(s, n)
    s = tostring(s or "")
    n = math.max(tonumber(n) or 12, 4)
    if #s <= n then return s end
    return string.sub(s, 1, n - 3) .. "..."
end

-- the controller buttons the wheel and its face trigger can use (XInput bits as the module reports them in GSA1.pad.raw;
-- feat/sh_super.lua's list, the same bits)
W.PAD_BUTTONS = {
    { 0, "None" }, { 0x0002, "D-pad down" }, { 0x0001, "D-pad up" }, { 0x0004, "D-pad left" }, { 0x0008, "D-pad right" },
    { 0x10000, "Left trigger (LT)" }, { 0x20000, "Right trigger (RT)" }, { 0x0100, "Left bumper (LB)" },
    { 0x0200, "Right bumper (RB)" }, { 0x0080, "Right stick click (RS)" }, { 0x0040, "Left stick click (LS)" },
    { 0x8000, "Y" }, { 0x4000, "X" }, { 0x0020, "Back / View" },
}
function W.PadTitle(b)
    for _, p in ipairs(W.PAD_BUTTONS) do
        if p[1] == b then return p[2] end
    end
    return string.format("button 0x%X", tonumber(b) or 0)
end
-- the pad bits the open wheel reads itself: A, B (cancel), LB / RB (pages)
W.PAD_A, W.PAD_B, W.PAD_LB, W.PAD_RB = 0x1000, 0x2000, 0x0100, 0x0200
W.PAD_DPAD = 0x000F
W.MOUSE_LEFT, W.MOUSE_RIGHT = 107, 108

-- the entries (GSA1.CHARACTERS): kind and the catalogue's form (1 = the General form while Super), the HUD's colour
W.COLOURS = {
    sonic = { 35, 110, 255 }, tails = { 250, 150, 30 }, knuckles = { 230, 45, 45 }, amy = { 245, 110, 180 },
    gamma = { 150, 160, 175 }, big = { 150, 90, 220 }, supersonic = { 255, 196, 40 }, supersonic_general = { 255, 196, 40 },
}
function W.Entries()
    local out = {}
    for _, c in ipairs(GSA1.CHARACTERS or {}) do out[#out + 1] = c end
    return out
end
function W.EntryOf(name)
    for _, c in ipairs(GSA1.CHARACTERS or {}) do
        if c.name == name then return c end
    end
    return nil
end
-- kind, form of an entry's catalogue (nil: not an entry)
function W.KindForm(name)
    local c = W.EntryOf(name)
    if not c then return nil end
    return c.kind, c.form == "general" and 1 or 0
end
function W.Title(name)
    local c = W.EntryOf(name)
    return c and c.title or tostring(name)
end

-- the default wheels (faces_wheel_plan.md 8.3; bodies from emote_wheel_lib.md 3.4, every one offered in the research's
-- TSVs; faces are the face animations of feat/sh_faces.lua's defaults; "x" = an extra motion found by its name). Page 1 only.
local function d(body, name, face) return { body = body, name = name, face = face } end
W.DEFAULTS = {
    sonic = { centre = "Happy",
        d("a75", "s_kimepose0", "Happy"), d("a3", "s_wait3"), d("a5", "s_wait_a1", "Blink"), d("a26", "s_rollfly", "Surprised"),
        d("a70", "s_zitabata", "Shock"), d("a81", "s_furatsuki0", "Eyes closed"), d("a84", "s_awa0"), d("a47", "s_tukamari0") },
    tails = { centre = "Happy",
        d("a54", "m_kimepose0", "Happy"), d("a56", "m_losepose0", "Sad"), d("x", "m_taiki0", "Sleepy"),
        d("a5", "m_wait_a1", "Blink"), d("a33", "m_rollfly0", "Surprised"), d("a94", "m_zitabata", "Shock"),
        d("a37", "m_flyup"), d("a43", "m_atack_1") },
    knuckles = { centre = "Happy",
        d("a40", "k_kimepose1", "Happy"), d("x", "k_taiki1", "Angry talk"), d("x", "k_wait_b1"), d("x", "k_item_fg1"),
        d("a5", "k_wait_a1", "Blink"), d("a39", "k_panch0"), d("a56", "k_panch2"), d("a30", "k_rollfly0", "Surprised") },
    amy = { centre = "Happy",
        d("a42", "a_kimepose0", "Happy"), d("x", "a_taiki0", "Angry talk"), d("x", "a_kakure0", "Surprised"),
        d("x", "a_mogura1"), d("a5", "a_wait_a1", "Blink"), d("a85", "a_rollat0"), d("a81", "a_attack1"),
        d("a87", "a_rollat2", "Eyes closed") },
    gamma = {
        d("a67", "e_taiki0"), d("x", "e_kimepose0"), d("a43", "e_wait2"), d("a46", "e_wwait0"), d("a49", "e_hover1"),
        d("a77", "e_item_f1"), d("a80", "e_item_g1"), d("a62", "e_shoot0") },
    big = { centre = "Talk",
        d("a48", "b_kimepose0", "Talk"), d("a2", "b_wait_a1", "Blink"), d("a60", "b_joysmall", "Talk"),
        d("a61", "b_joymiddle"), d("a62", "b_joybig0", "Talk"), d("a47", "b_zitabata0"), d("a92", "b_wwait0", "Sleepy"),
        d("x", "b_item_u1") },
    supersonic = {
        d("a130", "ss_wait0"), d("a139", "s_kimepose0"), d("a131", "ss_move0"), d("a132", "ss_move1"),
        d("a133", "ss_move2"), d("a3", "s_wait3"), d("a5", "s_wait_a1"), d("a81", "s_furatsuki0") },
}
W.DEFAULTS.supersonic_general = W.DEFAULTS.supersonic

-- a wheel: { pages = { [1..4] = { [1..8] = slot } }, centre = { face = name | nil } }; slot = { body = "a75" | "x3" | "x" |
-- "stop" | nil, name = internal name | nil, face = name | nil, loop = true | nil, nohold = true | nil (round 0.9.4b: "Hold
-- the last pose" switched off), label = "", speed = 0.25..4 | nil (round 0.9.4e: the play rate; nil = 1x) }
function W.EmptyWheel()
    local w = { pages = {}, centre = {} }
    for p = 1, W.PAGES do
        w.pages[p] = {}
        for s = 1, W.SLOTS do w.pages[p][s] = {} end
    end
    return w
end
function W.CopyWheel(src)
    local w = W.EmptyWheel()
    if not src then return w end
    for p = 1, W.PAGES do
        for s = 1, W.SLOTS do
            local o = src.pages and src.pages[p] and src.pages[p][s]
            if o then
                w.pages[p][s] = { body = o.body, name = o.name, face = o.face, loop = o.loop, nohold = o.nohold,
                                  label = o.label, speed = o.speed }
            end
        end
    end
    w.centre = { face = src.centre and src.centre.face or nil }
    return w
end
-- an entry's default wheel (page 1 of W.DEFAULTS, pages 2-4 empty)
function W.DefaultWheel(entry)
    local w = W.EmptyWheel()
    local def = W.DEFAULTS[entry]
    if not def then return w end
    for s = 1, W.SLOTS do
        local o = def[s]
        if o then w.pages[1][s] = { body = o.body, name = o.name, face = o.face } end
    end
    w.centre.face = def.centre
    return w
end

-- something in a slot (a body or a face)
function W.SlotUsed(slot)
    return slot ~= nil and (slot.body ~= nil or slot.face ~= nil)
end
function W.PageUsed(w, p)
    for s = 1, W.SLOTS do
        if W.SlotUsed(w.pages[p] and w.pages[p][s]) then return true end
    end
    return false
end
-- the pages to show: page 1 always, then every page with something on it
function W.Pages(w)
    local out = { 1 }
    for p = 2, W.PAGES do
        if W.PageUsed(w, p) then out[#out + 1] = p end
    end
    return out
end
-- the next page to show from p in direction dir (+1 / -1), empty pages skipped, round
function W.NextPage(w, p, dir)
    local list = W.Pages(w)
    local at = 1
    for i, q in ipairs(list) do
        if q == p then at = i end
    end
    at = ((at - 1 + (dir < 0 and -1 or 1)) % #list) + 1
    return list[at]
end
-- slots used / 33 (32 slots and the centre)
function W.UsedCount(w)
    local n = 0
    for p = 1, W.PAGES do
        for s = 1, W.SLOTS do
            if W.SlotUsed(w.pages[p][s]) then n = n + 1 end
        end
    end
    if w.centre and w.centre.face then n = n + 1 end
    return n
end

-- the file (faces_wheel_plan.md 8.1) -----------------------------------------------------------------------------------
W.HEADER = {
    "# G-SA1 emote wheel - written by Q menu > Options > G-SA1 > Emote wheel; one line per slot, tab-separated:",
    "# entry  page  slot  body  name  face  options  label  [speed]",
    "#   entry    a GSA1.CHARACTERS name: sonic tails knuckles amy gamma big supersonic supersonic_general",
    "#   page     1-4 and slot 1-8 (1 = up, then clockwise); page 0 slot 0 = the centre (its body is always \"-\")",
    "#   body     a<row> (an action row) | x<extra> (an extra motion) | stop | - (no body animation)",
    "#   name     the body's internal name (\"-\" for stop / -): the key is used while its entry has this name, else the name",
    "#            finds the entry again (a renumbered row; names are not unique, so never the name alone); a name found",
    "#            nowhere is kept in the file and shown as \"missing: <name>\"",
    "#   face     a face animation's name in face_anims.txt, or \"-\"",
    "#   options  comma list (loop: loop it; nohold: \"Hold the last pose\" off) or \"-\"",
    "#   label    reserved for custom names (later); empty",
    "#   speed    (G-SA1 0.9.4e, only when not 1) the slot's play rate: 0.25-4 times the game's rate; absent = 1",
}

local function valid_body(b)
    return b == "-" or b == "stop" or b == "x" or string.match(b, "^a%d+$") ~= nil or string.match(b, "^x%d+$") ~= nil
end

-- text -> wheels { [entry] = wheel }, bad lines (count), notes { "line 7: ..." }
function W.Parse(text)
    local out, bad, notes = {}, 0, {}
    if type(text) ~= "string" then return out, 0, notes end
    local n = 0
    for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
        n = n + 1
        line = string.gsub(line, "\r$", "")
        if line ~= "" and string.sub(line, 1, 1) ~= "#" and not string.match(line, "^version\t") then
            local f = {}
            for field in string.gmatch(line .. "\t", "([^\t]*)\t") do f[#f + 1] = field end
            local entry, page, slot = f[1], tonumber(f[2]), tonumber(f[3])
            local body, name, face, opts = f[4], f[5], f[6], f[7]
            -- 0.9.4e: the 9th column, the slot's play rate (absent in older files: 1x)
            local speed, swhy = W.ParseSpeed(f[9])
            local why
            if not (entry and W.EntryOf(entry)) then
                why = "unknown character " .. tostring(entry)
            elseif not (page and slot and page == math.floor(page) and slot == math.floor(slot) and
                ((page == 0 and slot == 0) or (page >= 1 and page <= W.PAGES and slot >= 1 and slot <= W.SLOTS))) then
                why = "page / slot " .. tostring(f[2]) .. " / " .. tostring(f[3])
            elseif not (body and valid_body(body)) then
                why = "body " .. tostring(body)
            elseif page == 0 and body ~= "-" then
                why = "the centre has no body animation"
            elseif not (name and name ~= "" and face and face ~= "" and opts and opts ~= "") then
                why = "too few columns"
            elseif swhy then
                why = swhy
            else
                local loop, nohold = false, false
                if opts ~= "-" then
                    for o in string.gmatch(opts, "[^,]+") do
                        if o == "loop" then
                            loop = true
                        elseif o == "nohold" then
                            nohold = true
                        elseif not W.OPTIONS[o] then
                            why = "option " .. o
                        end
                    end
                end
                if not why then
                    local w = out[entry]
                    if not w then
                        w = W.EmptyWheel()
                        out[entry] = w
                    end
                    if page == 0 then
                        w.centre.face = face ~= "-" and face or nil
                    else
                        w.pages[page][slot] = {
                            body = body ~= "-" and body or nil, name = name ~= "-" and name or nil,
                            face = face ~= "-" and face or nil, loop = loop or nil, nohold = nohold or nil,
                            label = f[8] or "", speed = speed,
                        }
                    end
                end
            end
            if why then
                bad = bad + 1
                notes[#notes + 1] = string.format("line %d: %s", n, why)
            end
        end
    end
    return out, bad, notes
end

local function clean(s)
    s = tostring(s or "")
    s = string.gsub(s, "[\t\r\n]", " ")
    return s
end

-- wheels -> text (the edited entries, each written whole: 32 slots and the centre, in GSA1.CHARACTERS order). The speed
-- column (0.9.4e) is written only for a slot with an animation whose rate is not 1x: without changed rates the slot lines
-- are exactly 0.9.4d's (the header has one comment line more), and 0.9.4d's reader takes a line with the 9th column (it
-- reads columns 1-8 and ignores the rest), so going back to 0.9.4d loses only the rates
function W.Serialize(wheels)
    local lines = {}
    for _, l in ipairs(W.HEADER) do lines[#lines + 1] = l end
    lines[#lines + 1] = "version\t1"
    for _, c in ipairs(W.Entries()) do
        local w = wheels and wheels[c.name]
        if w then
            for p = 1, W.PAGES do
                for s = 1, W.SLOTS do
                    local o = w.pages[p][s] or {}
                    local opts = {}
                    if o.loop then opts[#opts + 1] = "loop" end
                    if o.nohold then opts[#opts + 1] = "nohold" end
                    local cols = { c.name, tostring(p), tostring(s), clean(o.body or "-"),
                        clean(o.body and o.body ~= "stop" and o.name or "-"), clean(o.face or "-"),
                        #opts > 0 and table.concat(opts, ",") or "-", clean(o.label or "") }
                    local sp = W.SlotSpeed(o)
                    if o.body and o.body ~= "stop" and sp ~= 1 then cols[#cols + 1] = string.format("%g", sp) end
                    lines[#lines + 1] = table.concat(cols, "\t")
                end
            end
            lines[#lines + 1] = table.concat({ c.name, "0", "0", "-", "-", clean(w.centre and w.centre.face or "-"), "-",
                "" }, "\t")
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

-- the read-only mirror for the session log: "sonic 9/33; big 9/33" (the edited entries), "" when none
function W.MirrorString(wheels)
    local out = {}
    for _, c in ipairs(W.Entries()) do
        local w = wheels and wheels[c.name]
        if w then out[#out + 1] = string.format("%s %d/33", c.name, W.UsedCount(w)) end
    end
    return table.concat(out, "; ")
end

-- the catalogue ------------------------------------------------------------------------------------------------------------
-- a list from gsa1.EmoteList ({ n, [i] = { key, name, dup, ... } }) gets its key index (list.byKey) once
function W.Index(list)
    if not list then return nil end
    if list.byKey then return list end
    local by = {}
    for i = 1, tonumber(list.n) or #list do
        local e = list[i]
        if e and e.key then
            e.pos = i
            by[e.key] = e
        end
    end
    list.byKey = by
    return list
end

-- the entry a slot plays (review R.9): the stored key while its entry still has the stored internal name; else the first
-- entry with that name that is no duplicate of another (dup 0); nil, "missing" when the name is nowhere. A body without a
-- name (an old line, a hand edit) goes by its key.
function W.Resolve(list, body, name)
    if not body or body == "-" or body == "stop" then return nil end
    list = W.Index(list)
    if not list then return nil, "no list" end
    local named = name ~= nil and name ~= "" and name ~= "-"
    local e = list.byKey[body]
    if e and (not named or e.name == name) then return e, "key" end
    if named then
        local first
        for i = 1, tonumber(list.n) or #list do
            local x = list[i]
            if x and x.name == name then
                if (tonumber(x.dup) or 0) == 0 then return x, "name" end
                first = first or x
            end
        end
        if first then return first, "name" end
    end
    return nil, "missing"
end

-- the keys the wheel key may not be (faces_wheel_ui.md 2.5): the character's own input (the binds below, found with
-- input.LookupBinding), the interact key (+use), the voice chat key and the Super key (gsa1_super_key); the face trigger
-- may be a mouse button (it acts only while the wheel is open) but not the wheel key itself. Returns the reason or nil.
W.RESERVED_BINDS = {
    { "+jump", "the jump key" }, { "+duck", "the action key (crouch)" }, { "+attack", "the action key (attack)" },
    { "+attack2", "the action key (attack 2)" }, { "+reload", "the second action key" }, { "+forward", "a movement key" },
    { "+back", "a movement key" }, { "+moveleft", "a movement key" }, { "+moveright", "a movement key" },
    { "+use", "the interact key" }, { "+voicerecord", "the voice chat key" },
}
function W.KeyRefusal(code, lookup, keycode, super_key)
    code = tonumber(code) or 0
    if code <= 0 then return nil end
    if super_key and code == super_key then return "the Super transformation key" end
    if lookup and keycode then
        for _, b in ipairs(W.RESERVED_BINDS) do
            local name = lookup(b[1])
            local k = name and keycode(name)
            if k and k == code then return b[2] .. " (" .. b[1] .. ")" end
        end
    elseif code == W.MOUSE_LEFT or code == W.MOUSE_RIGHT then
        return "a mouse button (the action key)"
    end
    return nil
end
