-- G-SA1 client: Sonic Adventure's own HUD (round 0.9.1, feature "hud"; sadc docs/research/gsa1_070_hud.md F8 with its
-- review R.5.7, plan gsa1_rounds_plan.md 14.1h). Replaces round 5's ring counter (0.9.0: "RINGS 000 / SCORE / SONIC x 4"
-- drawn with a Garry's Mod font).
--
-- What is drawn is the game's: libsa1 runs the game's own HUD functions in the character's world where the game's frame
-- step calls them (8C08A4BA rings and lives, 8C08A724 the time) and captures every 2D draw of the world's tasks too
-- (Big's WEIGHT / rings / lives and his fishing reel, line-tension gauge and line length; E-102's countdown colours, his
-- "+N" time bonus and last-seconds digits; the drowning countdown above the head; Knuckles' radar where its task runs).
-- The module hands them over as gsa1.HudScreen's flat arrays (bind_hud.cpp): sprites and 2D polygons on the Dreamcast's
-- 640 x 480 screen, with the game's textures (CON_REGULAR, FISHING, E102TIME: the character's archives, painted into
-- render targets by cl_textures.lua with its alpha fix), colours, blend and order (opaque first, then blended, by the
-- game's 2D priority). This file only places them on Garry's Mod's screen and draws them in HUDPaint:
--   * scale s = min(W / 640, H / 480) x gsa1_hud_scale (3 at 3440 x 1440: the HUD as tall as the game's);
--   * on a screen wider (or taller) than 4:3 each element - the records of one part (rings, lives, time) or of one drawing
--     task, split into the screen's upper and lower half - is anchored to the edge it belongs to: its centre xc in the
--     game's 640 gives t = clamp((xc - 160) / 320, 0, 1) and X = x s + (W - 640 s) t + safe W (1 - 2 t), the same for Y
--     with 120 / 240 and 480 (left-quarter elements stay at the left edge, centred ones in the middle, right-quarter ones
--     at the right edge, and a moving one - E-102's "+N" flying to the timer - moves continuously); gsa1_hud_layout 1
--     puts the whole HUD in a centred 4:3 box instead (t = 0.5);
--   * the drowning countdown (the task 8C07BE6E, whose display 8C07BDA0 projects the player with libsa1's camera adapter
--     and draws 96 px above) is re-anchored above the character as Garry's Mod's camera sees it (drown review R4.5);
--   * not interpolated: the game draws its HUD once per 1/30 s pair.
-- Hidden without a character, with gsa1_hud 0, while the player looks through a camera (a view entity) and with
-- cl_drawhud 0. Garry's Mod's health and suit display is hidden while the HUD shows and the rings are the damage (the
-- server's damage mode "rings", round 5 decision 1).
--
-- The game's settings the HUD shows go to the character's world with gsa1.HudSettings: the parts (a part that is off
-- costs nothing: the game's call is not made), the game clock (gsa1_clock, on: worlds boot with it stopped) and E-102's
-- 3-minute limit (gsa1_e102_time_limit, off: his clock is held, no time-up death; owner default 14.1h). A respawn or
-- re-creation of the same character keeps the time (gsa1_hud_keep_time); the lives are cl_character.lua's (its lives
-- mode, libsa1's sa1_character_set_lives). The score (gsa1_hud_score, round 5's switch, off by default) is not part of the
-- game's action-stage HUD: G-SA1 draws it under the rings with the game's own digits.
-- Settings: Q menu > Options > G-SA1 > HUD (every one; the Interaction page keeps a pointer and the on / off switch).
GSA1 = GSA1 or {}
local H = GSA1.Hud or {}
GSA1.Hud = H
H.NEEDS = { feature = "hud", version = 1, module = "0.9.1" }

local band = bit.band
local floor, min, max, cos, sin = math.floor, math.min, math.max, math.cos, math.sin
-- SA1_DRAW_* / SA1_PRIM_* (libsa1.h) and gsa1.HUD (bind_hud.cpp)
local DRAW_BLEND, DRAW_ALPHA_TEST, DRAW_NO_TEXTURE, DRAW_ADDITIVE = 0x1, 0x2, 0x80, 0x200
local PRIM_TRIANGLES, PRIM_SPRITES, PRIM_LINES = 0, 1, 2
local PART_RINGS, PART_LIVES, PART_TIME, PART_CHARACTER = 1, 2, 4, 8
local DS, SS, VS = 11, 15, 8          -- the strides of gsa1.HudScreen's flat arrays (gsa1.HUD.D / S / V)
local QUADS, TRIANGLES, LINES = MATERIAL_QUADS or 7, MATERIAL_TRIANGLES or 2, MATERIAL_LINES or 1
local SRC_COUNTDOWN = 0x8C07BE6E      -- the drowning countdown task (its display 8C07BDA0 draws the digits)
-- where libsa1's camera adapter projects player 0 on the 640 x 480 screen: 40 units behind him, 7 above, looking level
-- (LIB src/world/sa1_world_tick.c SA1G_VIEW_DIST / SA1G_VIEW_HEIGHT; njInitSystem's screen distance 457.06)
local ADAPTER_X, ADAPTER_Y = 320, 240 + 7 * 457.06 / 40
local WRAP_SMOOTH, WRAP_SHARP = 3, 7  -- cl_textures.lua's address modes: clamped; clamped + point sampling
-- the score row (G-SA1's, gsa1_hud_score): under the TIME label / ring icon (CON_REGULAR cell 11, 64 x 64 at (16, 32))
local SCORE_X, SCORE_DIGITS_X, SCORE_Y, SCORE_DIGITS = 16, 64, 98, 7
local YELLOW = Color(255, 220, 40, 255)

-- settings (owner defaults 14.1h: the action-stage HUD, every part, the clock running, E-102's limit off; the corners of
-- a wide screen). gsa1_hud_rings and gsa1_hud_score are round 5's switches (same names, same meaning: the ring count, the
-- score); gsa1_hud_lives was round 5's "lives under the rings" (off) and is now the game's lives part (on)
H.cv = {
    on = GSA1.ConVar("gsa1_hud", 1, "Show Sonic Adventure's own HUD while you are a character", 0, 1),
    rings = GSA1.ConVar("gsa1_hud_rings", 1, "HUD: the ring counter (with the TIME label while the time shows)", 0, 1),
    lives = GSA1.ConVar("gsa1_hud_lives", 1, "HUD: the character's life icon and lives", 0, 1),
    time = GSA1.ConVar("gsa1_hud_time", 1, "HUD: the time (E-102: his countdown)", 0, 1),
    character = GSA1.ConVar("gsa1_hud_character", 1, "HUD: the characters' own displays (Big's fishing HUD, E-102's time "
        .. "bonus and last seconds, the drowning countdown, Knuckles' radar)", 0, 1),
    score = GSA1.ConVar("gsa1_hud_score", 0, "HUD: the score under the rings (not part of the game's action-stage HUD)",
        0, 1),
    scale = GSA1.ConVar("gsa1_hud_scale", 1, "HUD size (1: the game's HUD at your screen's height)", 0.5, 3),
    safe = GSA1.ConVar("gsa1_hud_safe", 0, "HUD distance from the screen's edges, in percent", 0, 10),
    layout = GSA1.ConVar("gsa1_hud_layout", 0, "HUD on wide screens: 0 in the corners of the screen, 1 in a centred 4:3 "
        .. "box", 0, 1),
    filter = GSA1.ConVar("gsa1_hud_filter", 0, "HUD textures: 0 smooth (bilinear), 1 sharp", 0, 1),
    hide_gmod = GSA1.ConVar("gsa1_hud_hide_gmod", 1, "Hide Garry's Mod's health and suit display while the HUD shows "
        .. "and the rings are the damage", 0, 1),
    keep_time = GSA1.ConVar("gsa1_hud_keep_time", 1, "Keep the time when the character respawns or is re-created", 0, 1),
    clock = GSA1.ConVar("gsa1_clock", 1, "The game clock runs (the HUD's time)", 0, 1),
    e102_limit = GSA1.ConVar("gsa1_e102_time_limit", 0, "E-102's 3-minute time limit (he dies at 0:00, as in the game)",
        0, 1),
}

-- CON_REGULAR (the HUD's 56 textures, a common archive of every character) is not painted at a spawn: its textures are
-- made at their first use (cl_textures.lua T.Prepare; as OBJ_REGULAR)
if GSA1.Tex and GSA1.Tex.NO_PREPARE then GSA1.Tex.NO_PREPARE.CON_REGULAR = true end

-- the module has the HUD (checked again when the module table changes)
local feat_of, feat_ok = nil, false
function H.Ready()
    if not GSA1.mod or not gsa1 then return false end
    if feat_of ~= gsa1 then
        feat_of = gsa1
        feat_ok = GSA1.HasFeature and GSA1.HasFeature(H.NEEDS.feature, H.NEEDS.version) and true or false
    end
    return feat_ok
end

-- the parts mask for libsa1 (gsa1_hud 0: none, the world makes no HUD calls)
function H.Parts()
    local cv = H.cv
    if not cv.on:GetBool() then return 0 end
    local p = 0
    if cv.rings:GetBool() then p = p + PART_RINGS end
    if cv.lives:GetBool() then p = p + PART_LIVES end
    if cv.time:GetBool() then p = p + PART_TIME end
    if cv.character:GetBool() then p = p + PART_CHARACTER end
    return p
end

function H.PartsText(p)
    local t = {}
    if band(p, PART_RINGS) ~= 0 then t[#t + 1] = "rings" end
    if band(p, PART_LIVES) ~= 0 then t[#t + 1] = "lives" end
    if band(p, PART_TIME) ~= 0 then t[#t + 1] = "time" end
    if band(p, PART_CHARACTER) ~= 0 then t[#t + 1] = "character" end
    return #t > 0 and table.concat(t, " ") or "none"
end

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("hud", fmt, ...) end
end

-- layout --------------------------------------------------------------------------------------------------------------
-- the screen's metrics: W x Hh pixels, the size option, the edge distance in percent, box (the centred 4:3 layout)
function H.Metrics(W, Hh, scale, safe, box, out)
    out = out or {}
    local s = min(W / 640, Hh / 480) * scale
    out.W, out.H, out.s, out.box = W, Hh, s, box and true or false
    out.ex, out.ey = W - 640 * s, Hh - 480 * s
    out.safex, out.safey = W * safe / 100, Hh * safe / 100
    return out
end

-- the anchor of an element whose bounding box is centred at (xc, yc) on the game's screen: 0 the left / top edge, 1 the
-- right / bottom edge, continuous between the screen's quarters (the box layout: 0.5)
function H.Anchor(m, xc, yc)
    if m.box then return 0.5, 0.5 end
    return math.Clamp((xc - 160) / 320, 0, 1), math.Clamp((yc - 120) / 240, 0, 1)
end

-- the element's offset: a point (x, y) of the game's screen is drawn at (x s + ox, y s + oy)
function H.Offset(m, tx, ty)
    return m.ex * tx + m.safex * (1 - 2 * tx), m.ey * ty + m.safey * (1 - 2 * ty)
end

-- (x, y) of the game's screen -> Garry's Mod's, for an element centred at (xc, yc)
function H.Place(m, x, y, xc, yc)
    local ox, oy = H.Offset(m, H.Anchor(m, xc, yc))
    return x * m.s + ox, y * m.s + oy
end

-- the frame's elements: pooled tables by a numeric key (part, source, upper / lower half), no garbage per frame
H.scr = H.scr or {}
H.m = H.m or {}
local pool, used, nused = {}, {}, 0
local spr_el, drw_el = {}, {}                 -- [sprite index] / [draw index] (0-based) -> element
local qx, qy = {}, {}                         -- the sprites' corners on the game's screen, 4 per sprite
local function element(part, source, lower)
    local key = (part * 4294967296 + source) * 2 + (lower and 1 or 0)
    local e = pool[key]
    if not e then
        e = { part = part, source = source }
        pool[key] = e
    end
    if e.frame ~= H.frameNo then
        e.frame = H.frameNo
        e.x0, e.y0, e.x1, e.y1 = 1e9, 1e9, -1e9, -1e9
        nused = nused + 1
        used[nused] = e
    end
    return e
end
local function grow(e, x, y)
    if x < e.x0 then e.x0 = x end
    if x > e.x1 then e.x1 = x end
    if y < e.y0 then e.y0 = y end
    if y > e.y1 then e.y1 = y end
end

-- the sprites' corners and every element's bounds and offset (once per frame: the countdown follows the camera)
function H.Layout(scr, m, C)
    H.frameNo = (H.frameNo or 0) + 1
    nused = 0
    local D, S, V = scr.d, scr.s, scr.v
    for d = 0, (scr.nd or 0) - 1 do
        local k = d * DS
        local prim, first, count, part, source = D[k + 1], D[k + 2], D[k + 3], D[k + 10], D[k + 11]
        if prim == PRIM_SPRITES then
            for j = first, first + count - 1 do
                local o = j * SS
                local x0, y0, x1, y1, px, py, ang = S[o + 1], S[o + 2], S[o + 3], S[o + 4], S[o + 5], S[o + 6], S[o + 7]
                local c = j * 4
                if ang ~= 0 then
                    local ca, sa = cos(ang), sin(ang)
                    qx[c + 1], qy[c + 1] = px + x0 * ca - y0 * sa, py + x0 * sa + y0 * ca
                    qx[c + 2], qy[c + 2] = px + x1 * ca - y0 * sa, py + x1 * sa + y0 * ca
                    qx[c + 3], qy[c + 3] = px + x1 * ca - y1 * sa, py + x1 * sa + y1 * ca
                    qx[c + 4], qy[c + 4] = px + x0 * ca - y1 * sa, py + x0 * sa + y1 * ca
                else
                    qx[c + 1], qy[c + 1] = px + x0, py + y0
                    qx[c + 2], qy[c + 2] = px + x1, py + y0
                    qx[c + 3], qy[c + 3] = px + x1, py + y1
                    qx[c + 4], qy[c + 4] = px + x0, py + y1
                end
                local e = element(part, source, (qy[c + 1] + qy[c + 3]) * 0.5 >= 240)
                for i = 1, 4 do grow(e, qx[c + i], qy[c + i]) end
                spr_el[j] = e
            end
        elseif count > 0 then
            local sy = 0
            for v = first, first + count - 1 do sy = sy + V[v * VS + 2] end
            local e = element(part, source, sy / count >= 240)
            for v = first, first + count - 1 do grow(e, V[v * VS + 1], V[v * VS + 2]) end
            drw_el[d] = e
        end
    end
    local head = nil
    for i = 1, nused do
        local e = used[i]
        e.ox, e.oy = H.Offset(m, H.Anchor(m, (e.x0 + e.x1) * 0.5, (e.y0 + e.y1) * 0.5))
        if e.source == SRC_COUNTDOWN and C and C.drawPos and not (GSA1.FirstPerson and GSA1.FirstPerson()) then
            -- above the character as Garry's Mod's camera sees it (the game: 96 px above its own projection)
            head = head or C.drawPos:ToScreen()
            if head and head.visible then
                e.ox, e.oy = head.x - ADAPTER_X * m.s, head.y - ADAPTER_Y * m.s
            end
        end
    end
    return nused
end

-- drawing -------------------------------------------------------------------------------------------------------------
local mats = {}                  -- [kind][key] = material (the texture painted), key: archive, texture, mode, filter
local white = {}                 -- [mode] = untextured material
local MODE_LETTER = { [0] = "o", [1] = "a", [2] = "t", [3] = "x" }
local function make_material(name, tex, mode)
    local params = { ["$basetexture"] = tex, ["$vertexcolor"] = 1, ["$nocull"] = 1, ["$ignorez"] = 1 }
    if mode >= 2 then
        params["$vertexalpha"] = 1
        if mode == 3 then params["$additive"] = 1 else params["$translucent"] = 1 end
    elseif mode == 1 then
        params["$alphatest"] = 1
        params["$alphatestreference"] = 0.5
    end
    H.nmats = (H.nmats or 0) + 1
    return CreateMaterial(name, "UnlitGeneric", params)
end

-- the material of a draw and its mode; nil, mode, true while its texture is not painted yet (a render target is opaque
-- black until then); nil, mode, false for a texture the module cannot give (never drawn)
function H.Material(kind, archive, tex, flags, sharp)
    local mode = 0
    if band(flags, DRAW_BLEND) ~= 0 then
        mode = band(flags, DRAW_ADDITIVE) ~= 0 and 3 or 2
    elseif band(flags, DRAW_ALPHA_TEST) ~= 0 then
        mode = 1
    end
    if archive < 0 or tex < 0 then
        local m = white[mode]
        if not m then
            m = make_material("gsa1hud_white_" .. MODE_LETTER[mode], "vgui/white", mode)
            white[mode] = m
        end
        return m, mode
    end
    local key = ((archive * 4096 + tex) * 4 + mode) * 2 + (sharp and 1 or 0)
    local mk = mats[kind]
    if not mk then
        mk = {}
        mats[kind] = mk
    end
    local m = mk[key]
    if m then return m, mode end
    local T = GSA1.Tex
    local e = T and T.Get(kind, archive, tex, sharp and WRAP_SHARP or WRAP_SMOOTH, true, "first use (HUD)")
    if not e then return nil, mode, false end
    if not e.done then return nil, mode, true end
    local rt = e.rt:GetName()
    m = make_material("gsa1hud_" .. rt .. "_" .. MODE_LETTER[mode], rt, mode)
    mk[key] = m
    return m, mode
end

local VP = Vector(0, 0, 0)
local function vtx(x, y, u, v, r, g, b, a)
    VP:SetUnpacked(x, y, 0)
    mesh.Position(VP)
    mesh.TexCoord(0, u, v)
    mesh.Color(r, g, b, a)
    mesh.AdvanceVertex()
end

-- the CON_REGULAR archive of a character kind (the score's digits)
local con_of = {}
function H.ConArchive(kind)
    local a = con_of[kind]
    if a == nil then
        a = false
        local list = GSA1.Tex and GSA1.Tex.Archives(kind)
        for i = 0, (list and list.n or 0) - 1 do
            if list[i] and list[i].name == "CON_REGULAR" then a = i end
        end
        con_of[kind] = a
    end
    return a or nil
end

local font_size = nil
local function score_font(px)
    px = max(8, floor(px + 0.5))
    if px ~= font_size and surface.CreateFont then
        font_size = px
        surface.CreateFont("GSA1HudScore", { font = "Arial Black", size = px, weight = 900, italic = true,
            antialias = true })
    end
    return "GSA1HudScore"
end

-- G-SA1's score row (round 5's switch): "SCORE" and 7 of the game's digits (CON_REGULAR cells 0-9, 16 x 16, as the
-- timer's), anchored with the top-left elements
function H.DrawScore(C, m, score, sharp)
    local arc = H.ConArchive(C.kind)
    if not arc then return 0 end
    local ox, oy = H.Offset(m, 0, 0)
    local s = m.s
    local n = math.Clamp(floor(tonumber(score) or 0), 0, 9999999)
    local drawn = 0
    for k = 0, SCORE_DIGITS - 1 do
        local digit = floor(n / 10 ^ (SCORE_DIGITS - 1 - k)) % 10
        local mat = H.Material(C.kind, arc, digit, DRAW_BLEND, sharp)
        if mat then
            render.SetMaterial(mat)
            local x0, y0 = (SCORE_DIGITS_X + 16 * k) * s + ox, SCORE_Y * s + oy
            mesh.Begin(QUADS, 1)
            vtx(x0, y0, 0, 0, 255, 255, 255, 255)
            vtx(x0 + 16 * s, y0, 1, 0, 255, 255, 255, 255)
            vtx(x0 + 16 * s, y0 + 16 * s, 1, 1, 255, 255, 255, 255)
            vtx(x0, y0 + 16 * s, 0, 1, 255, 255, 255, 255)
            mesh.End()
            drawn = drawn + 1
        end
    end
    if draw and draw.SimpleText then
        draw.SimpleText("SCORE", score_font(13 * s), SCORE_X * s + ox, (SCORE_Y + 1) * s + oy, YELLOW, TEXT_ALIGN_LEFT or 0,
            TEXT_ALIGN_TOP or 3)
    end
    return drawn
end

-- whether the HUD shows now
local cv_drawhud = nil
function H.Visible()
    local C = GSA1.Char
    if not C or not H.cv.on:GetBool() or not H.Ready() then return false end
    local ply = LocalPlayer()
    local ve = IsValid(ply) and ply.GetViewEntity and ply:GetViewEntity()
    if IsValid(ve) and ve ~= ply then return false end
    cv_drawhud = cv_drawhud or GetConVar("cl_drawhud")
    if cv_drawhud and not cv_drawhud:GetBool() then return false end
    return true
end

-- one frame of the HUD (HUDPaint); returns the draws made (the tests)
function H.Paint()
    if not H.Visible() then return 0 end
    local C = GSA1.Char
    local scr = H.scr
    local gen, err = gsa1.HudScreen(C.id, scr)
    if not gen then
        if not H.screenError then
            H.screenError = true
            log("the HUD of %s: %s", tostring(C.title), tostring(err))
        end
        return 0
    end
    local cv = H.cv
    local m = H.Metrics(ScrW(), ScrH(), cv.scale:GetFloat(), cv.safe:GetFloat(), cv.layout:GetInt() == 1, H.m)
    H.Layout(scr, m, C)
    local sharp = cv.filter:GetInt() == 1
    local D, S, V = scr.d, scr.s, scr.v
    local s = m.s
    local T = GSA1.Tex
    local BS, BD = T and T.BLEND_SRC or {}, T and T.BLEND_DST or {}
    local made, waiting = 0, 0
    for d = 0, (scr.nd or 0) - 1 do
        local k = d * DS
        local prim, first, count, flags = D[k + 1], D[k + 2], D[k + 3], D[k + 6]
        -- a texture of an archive libsa1 does not load: nothing (a white box is not the game's)
        if count > 0 and band(flags, DRAW_NO_TEXTURE) == 0 then
            local mat, mode, pending = H.Material(C.kind, D[k + 4], D[k + 5], flags, sharp)
            if not mat then
                if pending then waiting = waiting + 1 end
            else
                render.SetMaterial(mat)
                if mode >= 2 then render.OverrideBlend(true, BS[D[k + 7]] or 4, BD[D[k + 8]] or 5, BLENDFUNC_ADD or 0) end
                if prim == PRIM_SPRITES then
                    mesh.Begin(QUADS, count)
                    for j = first, first + count - 1 do
                        local e, o, c = spr_el[j], j * SS, j * 4
                        local ox, oy = e.ox, e.oy
                        local u0, v0, u1, v1 = S[o + 8], S[o + 9], S[o + 10], S[o + 11]
                        local r, g, b, a = S[o + 12], S[o + 13], S[o + 14], S[o + 15]
                        vtx(qx[c + 1] * s + ox, qy[c + 1] * s + oy, u0, v0, r, g, b, a)
                        vtx(qx[c + 2] * s + ox, qy[c + 2] * s + oy, u1, v0, r, g, b, a)
                        vtx(qx[c + 3] * s + ox, qy[c + 3] * s + oy, u1, v1, r, g, b, a)
                        vtx(qx[c + 4] * s + ox, qy[c + 4] * s + oy, u0, v1, r, g, b, a)
                    end
                    mesh.End()
                else
                    local e = drw_el[d]
                    local ox, oy = e.ox, e.oy
                    if prim == PRIM_LINES then
                        mesh.Begin(LINES, floor(count / 2))
                    else
                        mesh.Begin(TRIANGLES, floor(count / 3))
                    end
                    for v = first, first + count - 1 do
                        local o = v * VS
                        vtx(V[o + 1] * s + ox, V[o + 2] * s + oy, V[o + 3], V[o + 4], V[o + 5], V[o + 6], V[o + 7], V[o + 8])
                    end
                    mesh.End()
                end
                if mode >= 2 then render.OverrideBlend(false) end
                made = made + 1
            end
        end
    end
    if cv.score:GetBool() and H.score then
        made = made + H.DrawScore(C, m, H.score, sharp)
    end
    H.lastDraws, H.lastWaiting = made, waiting
    if H.loggedFor ~= C and (scr.nd or 0) > 0 and waiting == 0 then
        H.loggedFor = C
        log("HUD of %s: parts %s, size %.2f (x%.2f at %dx%d), %s, %s textures; %d draws, %d sprites, %d vertices",
            tostring(C.title), H.PartsText(H.aParts or 0), cv.scale:GetFloat(), s, m.W, m.H,
            m.box and "a centred 4:3 box" or "the corners of the screen", sharp and "sharp" or "smooth", scr.nd or 0,
            scr.ns or 0, scr.nv or 0)
    end
    return made
end

-- the character's settings and the time it keeps ----------------------------------------------------------------------
-- cl_character.lua's hooks (0.9.1): GSA1CharacterLeaving(C, how) before a character is destroyed (its world still
-- there: its time is read then), GSA1CharacterCreated(C, how, old) right after gsa1.Create, before the first tick (the
-- settings and, for "respawned" / "re-created", the old character's time go to the new world then). Without those hooks
-- (an older cl_character.lua) Think notices the new character at its next frame and does the same (prev: the time of
-- the character seen last; the same kind seen right after it counts as its respawn).
local prev = { valid = false, id = 0, kind = -1, m = 0, s = 0, f = 0 }
local leaving = { valid = false, id = 0, kind = -1, m = 0, s = 0, f = 0 }
H.prev, H.leaving = prev, leaving

-- the settings, when one changed since they were sent to this character
function H.Apply(C)
    local parts = H.Parts()
    local clock = H.cv.clock:GetBool() and 1 or 0
    local free = H.cv.e102_limit:GetBool() and 0 or 1
    if parts == H.aParts and clock == H.aClock and free == H.aFree then return end
    H.aParts, H.aClock, H.aFree = parts, clock, free
    local ok, err = gsa1.HudSettings(C.id, parts, clock, free)
    if ok then
        log("%s: HUD parts %s, the clock %s, E-102's time limit %s", tostring(C.title), H.PartsText(parts),
            clock == 1 and "runs" or "stopped", free == 1 and "off" or "on")
    else
        log("the HUD settings of %s: %s", tostring(C.title), tostring(err))
    end
end

-- a new character: the time it keeps (src: the character before it, same kind) and its settings
function H.Setup(C, src)
    H.char = C
    H.aParts, H.aClock, H.aFree = nil, nil, nil
    H.screenError = nil
    if src and src.valid and src.id ~= C.id and src.kind == C.kind and H.cv.keep_time:GetBool() then
        local ok, err = gsa1.HudSetTime(C.id, src.m, src.s, src.f)
        if ok then
            log("the time %02d:%02d:%02d kept for the new %s", src.m, src.s, src.f, tostring(C.title))
        else
            log("the time could not be kept for %s: %s", tostring(C.title), tostring(err))
        end
    end
    H.Apply(C)
end

function H.Think()
    local C = GSA1.Char
    if not C then
        prev.valid = false
        H.char = nil
        return
    end
    if not H.Ready() then return end
    if H.char ~= C then H.Setup(C, prev) end
    H.Apply(C)
    local m, s, f, _, score = gsa1.HudCounters(C.id)
    if m then
        prev.valid, prev.id, prev.kind, prev.m, prev.s, prev.f = true, C.id, C.kind, m, s, f
        H.score = score
    end
end

hook.Add("GSA1CharacterLeaving", "gsa1_hud", function(C)
    leaving.valid = false
    if not (C and C.id and H.Ready()) then return end
    local m, s, f = gsa1.HudCounters(C.id)
    if m then leaving.valid, leaving.id, leaving.kind, leaving.m, leaving.s, leaving.f = true, C.id, C.kind, m, s, f end
end)
hook.Add("GSA1CharacterCreated", "gsa1_hud", function(C, how, old)
    if not (C and C.id and H.Ready()) then return end
    local keep = (how == "respawned" or how == "re-created") and old and leaving.valid and leaving.id == old.id
    H.Setup(C, keep and leaving or nil)
    leaving.valid = false
end)

-- (a hook that returns a value stops Garry's Mod's other hooks of the event: these return nothing)
local guard = GSA1.Guard or function(_, fn) return fn end
hook.Add("Think", "gsa1_hud", guard("HUD settings", function() H.Think() end))
hook.Add("HUDPaint", "gsa1_hud", guard("HUD", function() H.Paint() end))

-- Garry's Mod's health and suit while the rings are the damage (the server's mode 0) and the HUD shows
local GMOD_HEALTH = { CHudHealth = true, CHudBattery = true }
hook.Add("HUDShouldDraw", "gsa1_hud", function(name)
    if not GMOD_HEALTH[name] or not H.cv.hide_gmod:GetBool() or H.Parts() == 0 or not H.Visible() then return end
    local mode = GetConVar("gsa1_sv_damage_mode")
    if not mode or mode:GetInt() ~= 0 then return end
    return false
end)

-- the Q menu ------------------------------------------------------------------------------------------------------------
local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[1], c[2]) end
    combo.OnSelect = function(_, _, _, data) RunConsoleCommand(cvname, tostring(data)) end
    local cvar = GetConVar(cvname)
    local v = cvar and cvar:GetString() or ""
    for _, c in ipairs(choices) do
        if tonumber(c[2]) == tonumber(v) then combo:SetValue(c[1]) end
    end
    return combo
end
H.LAYOUTS = { { "In the corners of the screen", "0" }, { "In a centred 4:3 box", "1" } }
H.FILTERS = { { "Smooth", "0" }, { "Sharp", "1" } }

function H.BuildPage(panel)
    panel:Help("Sonic Adventure's own HUD while you are a character, drawn by the game's code with the textures from "
        .. "your disc: the rings, the time and the lives with the character's icon, and the characters' own displays - "
        .. "Big's fishing HUD (weight, reel, line tension), E-102's countdown, time bonus and last seconds, the drowning "
        .. "countdown above the head. E-102's lock-on cursor is drawn in the world (not part of this page).")
    panel:CheckBox("Show the Sonic Adventure HUD", "gsa1_hud")
    panel:Help("Parts")
    panel:CheckBox("Rings (with the TIME label while the time shows)", "gsa1_hud_rings")
    panel:CheckBox("Lives (the character's icon and lives)", "gsa1_hud_lives")
    panel:CheckBox("Time (E-102: his countdown)", "gsa1_hud_time")
    panel:CheckBox("The characters' own displays (Big's fishing, E-102's bonus and last seconds, drowning countdown)",
        "gsa1_hud_character")
    panel:CheckBox("Score under the rings (not in the game's action-stage HUD)", "gsa1_hud_score")
    panel:Help("Layout")
    panel:NumSlider("Size (1 = the game's at your screen's height)", "gsa1_hud_scale", 0.5, 3, 2)
    choice_combo(panel, "On wide screens", "gsa1_hud_layout", H.LAYOUTS)
    panel:NumSlider("Distance from the screen's edges (%)", "gsa1_hud_safe", 0, 10, 1)
    choice_combo(panel, "Textures", "gsa1_hud_filter", H.FILTERS)
    panel:CheckBox("Hide Garry's Mod's health and suit display (while the rings are the damage)", "gsa1_hud_hide_gmod")
    panel:Help("Game clock")
    panel:CheckBox("The game clock runs", "gsa1_clock")
    panel:CheckBox("E-102's 3-minute time limit (he dies at 0:00, as in the game)", "gsa1_e102_time_limit")
    panel:ControlHelp("Off (the default): E-102's clock stays at 3:00 plus any time bonus, so the time never runs out.")
    panel:CheckBox("Keep the time when the character respawns or is re-created", "gsa1_hud_keep_time")
    panel:ControlHelp("The lives are kept as the Character page's lives setting says.")
end
GSA1.AddMenuPage(260, "hud", "HUD", H.BuildPage, H.NEEDS)

-- the Interaction page's HUD section (round 5's ring counter was there): the switch and a pointer to the HUD page
function H.MenuControls(panel)
    panel:CheckBox("Show the Sonic Adventure HUD", "gsa1_hud")
    panel:ControlHelp("Its parts, size and layout are on the HUD page (Options > G-SA1 > HUD).")
end
