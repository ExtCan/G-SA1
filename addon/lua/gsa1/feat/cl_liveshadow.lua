-- G-SA1 feature "liveshadow": the characters' SUN SHADOW, drawn by G-SA1 (round 0.9.5; sadc docs/research/gsa1_095_plan.md
-- 4.17 with its review R.7, gsa1_090_render.md 5.2 S2 with its review; the owner's binding answer 14.1ad 5 and his explicit
-- note: "The G-SA1 drawn sun shadow should be toggleable"). Garry's Mod shadows the props on a map from the map's sun, but
-- not a G-SA1 character (its meshes are not a model: no render-to-texture shadow); this draws one like a prop's, and the
-- game's own round shadow (gsa1_shadow, cl_render.lua) stays as it is. Nothing here changes game logic.
--   * THE LIGHT, once per map, from the map file's entity lump (file.Open("maps/<map>.bsp", "rb", "GAME") as cl_module.lua
--     reads a workshop map): the header (ident "VBSP", the lump directory) and lump 0 only - an LZMA-compressed lump or one
--     above S.LUMP_MAX (8 MB) is refused -, read in slices of at most S.SLICE (256 KB) per frame and parsed S.PARSE_BLOCKS
--     entity blocks per frame, from a Think coroutine. shadow_control's angles / color / distance / disableallshadows, else
--     light_environment's direction, else straight down. The conventions differ (review R.7, measured on the owner's maps):
--     shadow_control's "angles" are Source angles, dir = Angle(p, y, r):Forward() (gm_construct "90 0 0": straight down);
--     light_environment's "pitch" is NEGATIVE downward (Garry's Mod's bin/base.fgd: "0 is horizontal, -90 is straight down"),
--     the pitch key when not 0, else the angles' pitch in the same convention: dir = Angle(-pitch, yaw, 0):Forward(). A
--     direction within 10 degrees of horizontal or pointing up (shadow_control "0 0 0" of gm_highway14800 / rp_nycity,
--     light_environment pitch 0 of gm_goldencity_v2) is not used: the next source, logged. Several entities of a class: the
--     first one (the count logged). A key the entity leaves out: bin/base.fgd's default of shadow_control (angles "80 30 0",
--     color "128 128 128", distance 75, disableallshadows 0); with no shadow_control the colour and distance are those
--     defaults too. One log line per map. A map whose shadow_control changes at run time keeps its first values.
--   * THE SILHOUETTE, at most once per game pair (S.REFRESH) while the character is drawn (third person; first person only
--     with gsa1_sunshadow_fp) and the map does not disable shadows: cl_render.lua's GSA1.DrawCharacterView with an
--     orthographic box along the light around the drawn root (the eye S.box x 2 back along the light, the box S.box from
--     the character's height) into a 256 x 256 render target (its own depth, cl_textures.lua's probed format), white on
--     black: one flat white UnlitGeneric for every batch drawn (colour modulation 1, fog off, both restored), only the
--     opaque body and board batches (no effects, no game objects, no blob shadow); then render.BlurRenderTarget once.
--   * THE RECEIVERS: a 9 x 9 grid over the silhouette's footprint, each point traced along the light (util.TraceLine,
--     MASK_SOLID: props count; the local player filtered) at most the light's distance past the character's feet; the hit
--     points (in the world: they stay on the ground between two grids, also on slopes and stairs; the picture's texture
--     coordinates come from the drawn root of each frame, so the shadow follows the character every frame) as a grid of
--     quads drawn right after the main view's opaque renderables (PostDrawOpaqueRenderables, the screen only) with a
--     decal material sampling
--     the render target, blended ZERO / ONE_MINUS_SRC_COLOR - dst x (1 - mask x (1 - colour / 255) x fade), the blob's
--     mask path - with gsa1_sunshadow_dark > 0 the darkness instead of the colour, fading from 1 at the feet to 0 at the
--     light's distance; the tone-mapping scale 1 and restored (cl_render.lua's mask path). A cell with a corner not hit, or
--     whose corners lie more than S.STEP_DEPTH apart along the light (a ledge), is left out. The grid is traced again when
--     the character moved S.RETRACE_MOVE or S.RETRACE_EVERY passed (a standing character makes no traces every pair).
--     Reused tables and Vectors: no Lua garbage per frame of its own.
--   * OFF (gsa1_sunshadow 0): its hooks are removed - nothing drawn, computed or read; the game's blob untouched. Skipped
--     also with no character, in first person without gsa1_sunshadow_fp, with disableallshadows 1, when the character is
--     not drawn this frame. An error: one log line, the sun shadow stops for this session (the page says so).
--   * Cost: the hitch section "SunShadow" and the perf line's "sun shadow N ms per frame" (cl_log.lua); S.stats.
-- Q menu > Options > G-SA1 > Rendering: the three switches and a status line (GSA1.SunShadowLine).
GSA1 = GSA1 or {}
local S = GSA1.SunShadow
if not (S and S.cv and S.cv.on) then error("gsa1/feat/sh_liveshadow.lua did not load: the sun shadow needs it") end
local cv = S.cv
local band = bit.band

S.RT_SIZE, S.GRID, S.BLUR = 256, 9, 2
S.SLICE, S.LUMP_MAX, S.PARSE_BLOCKS = 256 * 1024, 8 * 1024 * 1024, 400
S.REFRESH = 1 / 30                  -- at most once per game pair
S.RETRACE_MOVE, S.RETRACE_EVERY = 0.5, 0.25
S.MIN_DOWN = math.sin(math.rad(10)) -- a direction within 10 degrees of horizontal (or up) is not used
S.STEP_DEPTH = 24                   -- HU along the light: a cell spanning more is a ledge, left out
S.LIFT = 0.5                        -- HU: the receiver quads lie this much towards the light
S.BOX_MIN = 48                      -- HU: the silhouette box's half size, at least
S.DEFAULT = { angles = { 80, 30, 0 }, color = { 128, 128, 128 }, distance = 75, disable = 0 }  -- bin/base.fgd shadow_control
local HOOK = "gsa1_sunshadow"
local DRAW_EFFECT, DRAW_SHADOW, DRAW_OBJECT, DRAW_BOARD = 0x40, 0x800, 0x1000, 0x4000
local B_ZERO, B_ONE_MINUS_SRC_COLOR, B_FUNC_ADD = 0, 10, 0
local MASK = MASK_SOLID or 33570827
local log = function(fmt, ...) if GSA1.Log then GSA1.Log("sunshadow", fmt, ...) end end

-- ---- the light ---------------------------------------------------------------------------------------------------------
-- a little-endian int32 at byte i of s
local function le32(s, i)
    local a, b, c, d = string.byte(s, i, i + 3)
    if not d then return nil end
    local v = a + b * 256 + c * 65536 + d * 16777216
    if v >= 2147483648 then v = v - 4294967296 end
    return v
end
S.LE32 = le32
S.HEADER_BYTES = 8 + 64 * 16 + 4

-- the BSP header: { version, ofs, len, fourcc } of lump 0 (fourcc not 0: LZMA-compressed, its uncompressed size), or nil, why
function S.ParseHeader(h)
    if type(h) ~= "string" or #h < 24 then return nil, "the map's file is too short" end
    if string.sub(h, 1, 4) ~= "VBSP" then return nil, "not a Source map (no VBSP header)" end
    return { version = le32(h, 5), ofs = le32(h, 9), len = le32(h, 13), fourcc = le32(h, 21) }
end

-- "p y r" -> { numbers } (nil when there is none)
local function numbers(s)
    if type(s) ~= "string" then return nil end
    local t = {}
    for w in string.gmatch(s, "%S+") do
        local n = tonumber(w)
        if n then t[#t + 1] = n end
    end
    return #t > 0 and t or nil
end
S.Numbers = numbers

-- the keyvalues of one entity block (keys in lower case; the first of a key wins)
local function keyvalues(block)
    local kv = {}
    for k, v in string.gmatch(block, '"([^"]*)"%s*"([^"]*)"') do
        k = string.lower(k)
        if kv[k] == nil then kv[k] = v end
    end
    return kv
end
S.KeyValues = keyvalues

-- the sun's entities in an entity lump's text: { shadow_control = { n, kv (the first) }, light_environment = { n, kv } };
-- step() is called every S.PARSE_BLOCKS blocks (the coroutine's yield)
function S.ParseEntities(text, step)
    local found = { shadow_control = { n = 0 }, light_environment = { n = 0 } }
    local i = 0
    for block in string.gmatch(text, "{([^{}]*)}") do
        i = i + 1
        if step and i % S.PARSE_BLOCKS == 0 then step() end
        if string.find(block, "shadow_control", 1, true) or string.find(block, "light_environment", 1, true) then
            local kv = keyvalues(block)
            local f = found[string.lower(kv.classname or "")]
            if f then
                f.n = f.n + 1
                if f.n == 1 then f.kv = kv end
            end
        end
    end
    return found
end

-- Source's AngleVectors forward of (pitch, yaw) - Angle(p, y, r):Forward(); the roll does not change it
local function forward(p, y)
    local rp, ry = math.rad(p), math.rad(y)
    return math.cos(rp) * math.cos(ry), math.cos(rp) * math.sin(ry), -math.sin(rp)
end
S.Forward = forward

local function fmt3(t)
    return string.format("(%s, %s, %s)", tostring(t[1] or 0), tostring(t[2] or 0), tostring(t[3] or 0))
end

-- the light of the found entities: { source = "shadow_control" | "light_environment" | "down", dx, dy, dz (unit, the
-- direction the light travels), color = { r, g, b }, distance, disabled, text }
function S.LightOf(found, why)
    local D = S.DEFAULT
    local L = { source = "down", dx = 0, dy = 0, dz = -1, color = { D.color[1], D.color[2], D.color[3] },
                distance = D.distance, disabled = false }
    local sc = found and found.shadow_control
    local le = found and found.light_environment
    local notes = {}
    local sckv = sc and sc.n > 0 and sc.kv or nil
    if sckv then
        local c = numbers(sckv.color)
        if c and #c >= 3 then L.color = { c[1], c[2], c[3] } end
        L.distance = tonumber(sckv.distance) or D.distance
        L.disabled = (tonumber(sckv.disableallshadows) or D.disable) ~= 0
    end
    local dirText
    if sckv then
        local a = numbers(sckv.angles) or D.angles
        local x, y, z = forward(a[1] or 0, a[2] or 0)
        if z <= -S.MIN_DOWN then
            L.source, L.dx, L.dy, L.dz = "shadow_control", x, y, z
            dirText = "shadow_control angles " .. fmt3(a)
        else
            notes[#notes + 1] = "shadow_control angles " .. fmt3(a) .. " point within 10 degrees of horizontal or up: "
                .. "not used"
        end
        if sc.n > 1 then notes[#notes + 1] = string.format("the first of %d shadow_control", sc.n) end
    end
    local lekv = le and le.n > 0 and le.kv or nil
    if L.source == "down" and lekv then
        local a = numbers(lekv.angles) or { 0, 0, 0 }
        local pitch = tonumber(lekv.pitch) or 0
        if pitch == 0 then pitch = a[1] or 0 end
        local x, y, z = forward(-pitch, a[2] or 0)
        if z <= -S.MIN_DOWN then
            L.source, L.dx, L.dy, L.dz = "light_environment", x, y, z
            dirText = string.format("light_environment pitch %s, yaw %s", tostring(pitch), tostring(a[2] or 0))
        else
            notes[#notes + 1] = string.format("light_environment pitch %s points within 10 degrees of horizontal or up: "
                .. "not used", tostring(pitch))
        end
        if le.n > 1 then notes[#notes + 1] = string.format("the first of %d light_environment", le.n) end
    end
    if L.source == "down" then
        dirText = "straight down: " .. (why or ((sckv or lekv) and "the map's sun is not usable" or
            "the map has neither shadow_control nor light_environment"))
    end
    L.text = string.format("%s, colour (%s, %s, %s), distance %s%s%s", dirText, tostring(L.color[1]),
        tostring(L.color[2]), tostring(L.color[3]), tostring(L.distance), L.disabled and
        "; the map disables shadows (disableallshadows 1): none drawn" or "", #notes > 0 and ("; " ..
        table.concat(notes, "; ")) or "")
    return L
end

-- the job (a coroutine, one step per frame from the Think hook): the header, lump 0 in slices, the parse in steps
local function light_job(map)
    local f = file.Open("maps/" .. map .. ".bsp", "rb", "GAME")
    if not f then return S.LightOf(nil, "the map's file could not be read") end
    S.file = f
    local H, why = S.ParseHeader(f:Read(S.HEADER_BYTES))
    local text
    if H then
        if H.fourcc ~= 0 then
            H, why = nil, "the map's entities are compressed (LZMA)"
        elseif not (H.ofs and H.len and H.ofs > 0 and H.len > 0) then
            H, why = nil, "the map has no entities"
        elseif H.len > S.LUMP_MAX then
            H, why = nil, string.format("the map's entities are %.1f MB (more than %d MB)", H.len / 1048576,
                S.LUMP_MAX / 1048576)
        end
    end
    if H then
        f:Seek(H.ofs)
        local parts, got = {}, 0
        while got < H.len do
            local part = f:Read(math.min(S.SLICE, H.len - got))
            if not part or #part == 0 then break end
            parts[#parts + 1] = part
            got = got + #part
            coroutine.yield()
        end
        text = table.concat(parts)
        if string.sub(text, 1, 4) == "LZMA" then text, why = nil, "the map's entities are compressed (LZMA)" end
    end
    f:Close()
    S.file = nil
    if not text then return S.LightOf(nil, why) end
    return S.LightOf(S.ParseEntities(text, coroutine.yield))
end

local function step_light()
    local map = game.GetMap()
    if S.lightMap == map or S.broken then return end
    if not S.job or S.jobMap ~= map then S.job, S.jobMap = coroutine.create(light_job), map end
    local ok, L = coroutine.resume(S.job, map)
    if not ok then
        if S.file then pcall(function() S.file:Close() end) S.file = nil end
        L = S.LightOf(nil, "the map's entities could not be read (" .. tostring(L) .. ")")
    elseif coroutine.status(S.job) ~= "dead" then
        return
    end
    S.light, S.lightMap, S.job = L, map, nil
    log("sun shadow: %s", L.text)
end
S.StepLight = step_light

-- ---- the silhouette and the receivers ------------------------------------------------------------------------------------
-- the batches the silhouette draws: opaque, the body (no effect) and the board; no game object, no blob shadow
local function silhouette_batch(b)
    if b.pass ~= 0 then return false end
    local f = b.flags or 0
    if band(f, DRAW_SHADOW) ~= 0 or band(f, DRAW_OBJECT) ~= 0 then return false end
    if band(f, DRAW_BOARD) ~= 0 then return true end
    return band(f, DRAW_EFFECT) == 0
end
S.SilhouetteBatch = silhouette_batch

local ORTHO = { left = -S.BOX_MIN, right = S.BOX_MIN, top = -S.BOX_MIN, bottom = S.BOX_MIN }
local VIEW = { kind = "sunshadow", hitch = false, opaque = true, x = 0, y = 0, w = S.RT_SIZE, h = S.RT_SIZE, znear = 1,
               zfar = 4 * S.BOX_MIN, filter = silhouette_batch, ortho = ORTHO, eye = Vector(), ang = Angle() }
S.view = VIEW
local FWD, RIGHT, UP = Vector(), Vector(), Vector()
local N = S.GRID
local NN = N * N
-- wx, wy, wz: the hit points in the world (lifted towards the light); u, v: their texture coordinates of this frame
local G = { hit = {}, wx = {}, wy = {}, wz = {}, fade = {}, depth = {}, u = {}, v = {}, cells = {}, ncells = 0, box = 48 }
S.grid = G
for k = 1, NN do
    G.hit[k], G.wx[k], G.wy[k], G.wz[k], G.fade[k], G.depth[k], G.u[k], G.v[k] = false, 0, 0, 0, 0, 0, 0, 0
end
S.basis = { fwd = FWD, right = RIGHT, up = UP }
for c = 1, (N - 1) * (N - 1) do G.cells[c] = 0 end
local TR = { start = Vector(), endpos = Vector(), mask = MASK, output = {} }
local POS = Vector()
local TONE_ONE = Vector(1, 1, 1)
S.stats = { refreshes = 0, refreshMs = 0, traces = 0, frames = 0, frameMs = 0 }

-- the render target and the two materials (made at the first silhouette)
local function targets()
    if S.rt then return S.rt end
    local Tx = GSA1.Tex
    local fmt = Tx and Tx.format or { name = "BGRA8888", fmt = IMAGE_FORMAT_BGRA8888 or 12 }
    S.rt = GetRenderTargetEx("gsa1_sunshadow_" .. fmt.name, S.RT_SIZE, S.RT_SIZE, RT_SIZE_LITERAL or 5,
        MATERIAL_RT_DEPTH_SEPARATE or 1, bit.bor(TEXTUREFLAGS_CLAMPS or 4, TEXTUREFLAGS_CLAMPT or 8), 0, fmt.fmt)
    -- the flat white of the silhouette (opaque: the view depth Source writes into the alpha of opaque draws stays out)
    S.white = CreateMaterial("gsa1_sunshadow_white", "UnlitGeneric", { ["$basetexture"] = "vgui/white",
        ["$nocull"] = 1, ["$ignorez"] = 1 })
    -- the receivers: the silhouette as a decal (polygon offset), no depth writes, no fog (it would pull the darkening
    -- towards the fog colour: the blob's mask material, cl_textures.lua)
    S.recv = CreateMaterial("gsa1_sunshadow_" .. fmt.name, "UnlitGeneric", { ["$basetexture"] = S.rt:GetName(),
        ["$vertexcolor"] = 1, ["$translucent"] = 1, ["$nofog"] = 1, ["$decal"] = 1, ["$nocull"] = 1 })
    VIEW.material = S.white
    return S.rt
end

-- the 9 x 9 grid along the light from the box's light side, at most the light's distance past the feet
local function trace_grid(C, L, cx, cy, cz, box)
    local p = C.drawPos
    local px, py, pz = p.x, p.y, p.z
    local dx, dy, dz = L.dx, L.dy, L.dz
    local rx, ry, rz = RIGHT.x, RIGHT.y, RIGHT.z
    local ux, uy, uz = UP.x, UP.y, UP.z
    local dist = L.distance
    TR.filter = LocalPlayer()
    local st, en = TR.start, TR.endpos
    local hit, wx, wy, wz, fade, dep = G.hit, G.wx, G.wy, G.wz, G.fade, G.depth
    local lift = S.LIFT
    local any = false
    for k = 1, NN do
        local i, j = (k - 1) % N, math.floor((k - 1) / N)
        local xv = -box + 2 * box * i / (N - 1)
        local yv = box - 2 * box * j / (N - 1)            -- row 0 at the top of the picture (the view's up)
        local gx = cx + rx * xv + ux * yv - dx * box
        local gy = cy + ry * xv + uy * yv - dy * box
        local gz = cz + rz * xv + uz * yv - dz * box
        local len = dist - ((gx - px) * dx + (gy - py) * dy + (gz - pz) * dz)
        hit[k] = false
        if len > 0 then
            st:SetUnpacked(gx, gy, gz)
            en:SetUnpacked(gx + dx * len, gy + dy * len, gz + dz * len)
            local r = util.TraceLine(TR)
            if r == nil then r = TR.output end
            S.stats.traces = S.stats.traces + 1
            if r and r.Hit and not r.StartSolid and r.HitPos then
                local hp = r.HitPos
                local hx, hy, hz = hp.x - px, hp.y - py, hp.z - pz
                local depth = hx * dx + hy * dy + hz * dz
                hit[k] = true
                any = true
                wx[k], wy[k], wz[k] = hp.x - dx * lift, hp.y - dy * lift, hp.z - dz * lift
                fade[k] = 1 - math.min(math.max(depth / math.max(dist, 1), 0), 1)
                dep[k] = depth
            end
        end
    end
    -- the cells drawn: every corner hit, the corners within S.STEP_DEPTH along the light
    local nc = 0
    if any then
        for j = 0, N - 2 do
            for i = 0, N - 2 do
                local k = j * N + i + 1
                if hit[k] and hit[k + 1] and hit[k + N] and hit[k + N + 1] then
                    local a, b, c, d = dep[k], dep[k + 1], dep[k + N], dep[k + N + 1]
                    if math.max(a, b, c, d) - math.min(a, b, c, d) <= S.STEP_DEPTH then
                        nc = nc + 1
                        G.cells[nc] = k
                    end
                end
            end
        end
    end
    G.ncells = nc
    G.px, G.py, G.pz, G.at, G.C, G.box = px, py, pz, SysTime(), C, box
end

-- one silhouette (and, when the character moved, the grid): true when it was made
local function refresh(C, L, now)
    S.refreshAt, S.refreshC = now, C
    local dx, dy, dz = L.dx, L.dy, L.dz
    local ang = VIEW.ang
    ang.p, ang.y, ang.r = math.deg(math.atan2(-dz, math.sqrt(dx * dx + dy * dy))), math.deg(math.atan2(dy, dx)), 0
    GSA1.AngleAxes(ang, FWD, RIGHT, UP)
    local info = C.info or {}
    local box = math.max(S.BOX_MIN, 0.75 * (tonumber(info.height) or 40) + 16)
    local p = C.drawPos
    local cx, cy, cz = p.x, p.y, p.z + (tonumber(info.center) or 20)
    ORTHO.left, ORTHO.right, ORTHO.top, ORTHO.bottom = -box, box, -box, box
    VIEW.eye:SetUnpacked(cx - dx * 2 * box, cy - dy * 2 * box, cz - dz * 2 * box)
    VIEW.znear, VIEW.zfar = 1, 4 * box
    local rt = targets()
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 255, true, true)
    local fog = render.GetFogMode and render.GetFogMode()
    if render.FogMode then render.FogMode(MATERIAL_FOG_NONE or 0) end
    local mr, mg, mb
    if render.GetColorModulation and render.SetColorModulation then
        mr, mg, mb = render.GetColorModulation()
        render.SetColorModulation(1, 1, 1)
    end
    local ok, drawn, why = pcall(GSA1.DrawCharacterView, C, VIEW)
    if mr then render.SetColorModulation(mr, mg, mb) end
    if fog and render.FogMode then render.FogMode(fog) end
    render.PopRenderTarget()
    if not ok then error(drawn, 0) end
    if not drawn then return false, why end
    if render.BlurRenderTarget then render.BlurRenderTarget(rt, S.BLUR, S.BLUR, 1) end
    S.picture = true
    S.stats.refreshes = S.stats.refreshes + 1
    local moved = G.C ~= C or not G.at or now - G.at >= S.RETRACE_EVERY - 1e-6 or
        math.abs(p.x - G.px) + math.abs(p.y - G.py) + math.abs(p.z - G.pz) >= S.RETRACE_MOVE
    if moved then trace_grid(C, L, cx, cy, cz, box) end
    return true
end

local function vertex(k, cr, cg, cb)
    local f = G.fade[k]
    POS:SetUnpacked(G.wx[k], G.wy[k], G.wz[k])
    mesh.Position(POS)
    mesh.TexCoord(0, G.u[k], G.v[k])
    mesh.Color(cr * f, cg * f, cb * f, 255)
    mesh.AdvanceVertex()
end

-- the cells' two triangles each (in pcall: mesh.End must follow mesh.Begin)
local function emit_cells(nc, cr, cg, cb)
    local cells = G.cells
    for c = 1, nc do
        local k = cells[c]
        vertex(k, cr, cg, cb)
        vertex(k + N, cr, cg, cb)
        vertex(k + 1, cr, cg, cb)
        vertex(k + 1, cr, cg, cb)
        vertex(k + N, cr, cg, cb)
        vertex(k + N + 1, cr, cg, cb)
    end
end

-- the receiver quads, the picture placed at the drawn root of THIS frame: each hit point's texture coordinates are its
-- place in the light's view around the character's centre now (the picture's orientation: u along the view's right, v
-- down its up, as in a perspective view)
local function draw_receivers(C, L)
    local nc = G.ncells
    if not S.picture or nc == 0 or G.C ~= C then return end
    local p = C.drawPos
    local info = C.info or {}
    local cx, cy, cz = p.x, p.y, p.z + (tonumber(info.center) or 20)
    local rx, ry, rz, ux, uy, uz = RIGHT.x, RIGHT.y, RIGHT.z, UP.x, UP.y, UP.z
    local k2 = 0.5 / G.box
    local hit, wx, wy, wz, U, V = G.hit, G.wx, G.wy, G.wz, G.u, G.v
    for k = 1, NN do
        if hit[k] then
            local ex, ey, ez = wx[k] - cx, wy[k] - cy, wz[k] - cz
            U[k] = 0.5 + (ex * rx + ey * ry + ez * rz) * k2
            V[k] = 0.5 - (ex * ux + ey * uy + ez * uz) * k2
        end
    end
    local dark = cv.dark and cv.dark:GetFloat() or 0
    local cr, cg, cb
    if dark > 0 then
        cr = 255 * math.min(dark, 100) / 100
        cg, cb = cr, cr
    else
        local col = L.color
        cr, cg, cb = 255 - (col[1] or 128), 255 - (col[2] or 128), 255 - (col[3] or 128)
    end
    local tone = render.GetToneMappingScaleLinear and render.GetToneMappingScaleLinear()
    if tone and render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(TONE_ONE) end
    render.SetMaterial(S.recv)
    render.OverrideBlend(true, B_ZERO, B_ONE_MINUS_SRC_COLOR, B_FUNC_ADD)
    mesh.Begin(MATERIAL_TRIANGLES, 2 * nc)
    local ok, err = pcall(emit_cells, nc, cr, cg, cb)
    mesh.End()
    render.OverrideBlend(false)
    if tone and render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(tone) end
    if not ok then error(err, 0) end
end

-- the main view, right after its opaque renderables (the character's ENT:Draw has run: its batches of this frame)
local function main_view(isDrawingDepth, isDrawSkybox, isDraw3DSkybox)
    if isDrawingDepth or isDrawSkybox or isDraw3DSkybox or S.broken then return end
    if render.GetRenderTarget and render.GetRenderTarget() then return end      -- the screen's main view only
    local C = GSA1.Char
    local L = S.light
    if not (C and C.batches and C.drawPos and L) or L.disabled then return end
    local fn = FrameNumber()
    if C.viewFrame ~= fn or S.drawnFrame == fn then return end
    if GSA1.FirstPerson and GSA1.FirstPerson() and not cv.fp:GetBool() then return end
    S.drawnFrame = fn
    local t0 = SysTime()
    local ok, err = true, nil
    if S.refreshC ~= C or not S.refreshAt or t0 - S.refreshAt >= S.REFRESH - 1e-6 or t0 < S.refreshAt then
        local t1 = SysTime()
        ok, err = pcall(refresh, C, L, t0)
        S.stats.refreshMs = S.stats.refreshMs + (SysTime() - t1) * 1000
    end
    if ok then ok, err = pcall(draw_receivers, C, L) end
    local dt = SysTime() - t0
    S.stats.frames, S.stats.frameMs = S.stats.frames + 1, S.stats.frameMs + dt * 1000
    if GSA1.HitchAdd then GSA1.HitchAdd("SunShadow", dt) end
    if not ok then
        S.broken = tostring(err)
        log("sun shadow: stopped for this session: %s", S.broken)
    end
end

-- first person with gsa1_sunshadow_fp: cl_render.lua's DrawCharacter prepares the frame's batches without drawing them
local function pre_render()
    local C = GSA1.Char
    if C then C.viewWanted = cv.fp:GetBool() and GSA1.FirstPerson ~= nil and GSA1.FirstPerson() or false end
end

-- the page's status line
function GSA1.SunShadowLine()
    if not cv.on:GetBool() then return "Sun shadow: off" end
    if S.broken then return "Sun shadow: stopped for this session (see the session log)" end
    local L = S.light
    if not L then return "Sun shadow: reading the map's sun ..." end
    local st = S.stats
    return string.format("Sun shadow: %s%s", L.text, st.frames > 0 and string.format(" (%.2f ms per frame)",
        st.frameMs / st.frames) or "")
end

-- on / off: the hooks exist only while it is on (off costs nothing)
local guard = GSA1.Guard or function(_, fn) return fn end
local think_g, pre_g, view_g = guard("SunShadow", step_light), guard("SunShadow", pre_render), main_view
function S.Apply()
    local on = cv.on and cv.on:GetBool() or false
    if on == S.hooked then return end
    S.hooked = on
    if on then
        hook.Add("Think", HOOK, think_g)
        hook.Add("PreRender", HOOK, pre_g)
        hook.Add("PostDrawOpaqueRenderables", HOOK, view_g)
    else
        hook.Remove("Think", HOOK)
        hook.Remove("PreRender", HOOK)
        hook.Remove("PostDrawOpaqueRenderables", HOOK)
        if GSA1.Char then GSA1.Char.viewWanted = nil end
        G.ncells, S.picture = 0, false
    end
end
if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("gsa1_sunshadow", function() S.Apply() end, HOOK)
end
S.hooked = nil
S.Apply()
