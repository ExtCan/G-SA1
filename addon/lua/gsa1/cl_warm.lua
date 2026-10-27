-- G-SA1 client: the material pre-warm (round 4c; the owner's 0.5.0 report: "there's a lag spike when charging up" - the
-- whole game froze briefly; sadc docs/research/gsa1_lsd_lag.md C3 and its review).
--
-- Offline nothing G-SA1 or libsa1 does explains a frozen frame at the Light Speed charge (the game's code, the module's
-- work, the GPU fill: all well under a millisecond). What the charge does for the first time in a session is on
-- Garry's Mod's side: five new materials in its first half second (the spin texture, the ball's two shells, the
-- sparkle sprite, the ribbons) and the aura at completion. A new material means CreateMaterial, then at its first draw
-- Source loads the shader combination it needs and DXVK builds the Vulkan pipeline for that shader and render state;
-- a render target made at its first use is painted too. Any of these can stall a frame, and none can be measured
-- outside the game.
--
-- So when a character appears, every material it can use is made and drawn once, a few per frame, before it is needed:
--   1. every material state - opaque, alpha-tested, translucent, additive x unlit, lit, lit half-Lambert x culled,
--      both sides - on vgui/white and on one of the character's render targets, the blended ones with the game's blend
--      factor pairs; this makes Source load each shader combination and DXVK build each pipeline;
--   2. the exact material of every render state the character kind drew in core_test's material census
--      (cl_warm_census.lua, generated from build/<target>/material_census.txt by tools/gen_warm_census.py): its
--      texture's render target in that state's address mode (the point-sampled and repeating ones are render targets
--      of their own), mode, lighting, culling and half-Lambert - body textures translucent and palette-lit, both
--      sides, sphere-mapped, unlit; Big's lit lure and rod; E-102's and Amy's point-sampled textures;
--   3. every texture of the character's own model archive in the body's state (opaque, palette-lit: Sonic's spin
--      texture appears with the first spin dash or Light Speed charge);
--   4. every texture of the character's effect archives in the states effects draw them: additive or translucent,
--      unlit, both sides (sprites, the 3D polygons: ribbons, the barrier) and additive unlit culled (effect models).
-- One item per material and draw state: states that make the same material (the same render target, mode, lighting,
-- culling, half-Lambert; the sphere map, the effect flag and the primitives do not change it) with the same blend
-- factors are one item. Materials the character's own first frames make while the warm-up runs are counted with it;
-- a material made at its first use after the warm-up has finished gets a "material" line of its own in the session log.
-- "Drawn once" is a triangle of zero area at the character in its own ENT:Draw / ENT:DrawTranslucent, with the lighting
-- set up as for its batches: the same render target, depth and blend states as the real draws, and nothing visible.
-- The material census in core_test (build/<target>/material_census.txt: every render state six characters drew in
-- 13 s of scripted play with all their upgrades) is checked against this list by tests/warm_test.lua: every state's
-- exact material, under lighting on and off and "both sides".
-- The warm-up takes at most WARM_BUDGET per frame (one slow item at a time), is written into the session log ("warm"
-- lines: how many, how long, the slowest), and is skipped for materials made already (another spawn, a respawn).
-- gsa1_prewarm 0 turns it off (Q -> Options -> G-SA1 -> Rendering).
-- 0.8: libsa1 loads OBJ_REGULAR (the blob shadow's archive, 96 textures) before EFF_REGULAR; its textures are neither
-- painted at a spawn nor warmed in the effect states (item 4) - the shadow's own state (its mask render target, the
-- census's state with address mode WRAP_MASK) comes from the census (item 2). Items drawn while cl_render.lua draws
-- camera-relative sit at the frame's origin, and blended items use cl_textures.lua's T.BlendOf (the mask's ZERO /
-- ONE_MINUS_SRC_COLOR).
-- 0.9.1 (sadc docs/research/gsa1_070_translucency.md T1): a lit see-through batch's material carries its alpha ($alpha;
-- the module keys the batch ".a<alpha>"), so the census has the alphas the characters' see-through copies drew with (Tails'
-- 170 / 85, Amy's 76 / 51, E-102's 216; 255 is left out) as an 8th field, and those exact materials are warmed in item 2.
-- $alpha changes no shader combination (the material is translucent either way), so item 1 needs no alpha states.
-- 0.9.2 (sadc docs/research/gsa1_090_render.md R1, step 5): cl_render.lua draws the opaque batches in Source's depth views
-- with DepthWrite materials (cl_textures.lua T.DepthMaterial), so the first depth pass or lamp shadow makes no material:
--   5. the DepthWrite states - $color_depth 1 (the depth pass) and 0 (shadow depth) x culled, both sides - and, for every
--      alpha-tested opaque census state of the character, its cut-out DepthWrite material in both colour modes.
-- They are drawn like the others (a zero-area triangle in the main view's opaque pass: the material is made and its shader
-- loaded; nothing is written).
GSA1 = GSA1 or {}
GSA1.Warm = GSA1.Warm or { queue = { [0] = {}, [1] = {} }, head = { [0] = 1, [1] = 1 }, done = {}, total = nil }
local W = GSA1.Warm

local WARM_BUDGET = 0.0015      -- seconds of warm-up per frame (both passes)
local SLOW = 0.004              -- a single item this slow is named in the log (the first SLOW_LINES of a warm-up)
local SLOW_LINES = 12

-- SA1_DRAW_* (libsa1.h)
local BLEND, ALPHA_TEST, DOUBLE_SIDED, UNLIT, PALETTE_LIT, EFFECT, ADDITIVE = 0x1, 0x2, 0x4, 0x10, 0x20, 0x40, 0x200
-- the game's blend factor pairs (SA1_BLEND_*: 1 ONE, 4 SRC_ALPHA, 5 INV_SRC_ALPHA) of its translucent and additive
-- draws (the material census: every blended batch of the six characters used one of these)
W.PAIRS = { [2] = { { 4, 5 } }, [3] = { { 4, 1 }, { 1, 1 } } }
local MODES = { [0] = 0, [1] = ALPHA_TEST, [2] = BLEND, [3] = BLEND + ADDITIVE }
local LIGHTS = { UNLIT, 0, PALETTE_LIT }
local CLAMP = 3                 -- WRAP_CLAMP_U | WRAP_CLAMP_V: the address mode the spawn paints every texture in
local band = bit.band

-- a synthetic gsa1.Batches entry (the module's key format: archive.tex.flags.src.dst.wrap.pass, and 0.9.1 ".a<alpha>"
-- for a lit see-through batch's alpha below 255)
local function state(archive, tex, flags, src, dst, wrap, pass, alpha)
    alpha = alpha or 255
    local key = string.format("%d.%d.%X.%d.%d.%d.%d", archive, tex, flags, src, dst, wrap, pass)
    if alpha < 255 then key = key .. ".a" .. alpha end
    return { key = key, archive = archive, tex = tex, flags = flags, src = src, dst = dst, wrap = wrap, pass = pass,
             alpha = alpha }
end
W.State = state

-- one item per material and draw state (see the top): the material's identity under the current settings (render
-- target = archive, texture, address mode; or vgui/white; 0.9.1: a lit see-through material's $alpha), and for blended
-- states the blend factors
local function item_key(b)
    local mode, lit, nocull, hl, alpha = GSA1.Tex.MaterialState(b)
    if b.depth then
        -- 0.9.2: a DepthWrite state (T.DepthMaterial): colour mode, both sides, the cut-out's texture
        local atest = mode == 1 and b.archive >= 0 and b.tex >= 0
        return string.format("depth%d_%s_%d", b.depth, atest and (b.archive .. "_" .. b.tex .. "_" .. b.wrap) or "x",
            nocull and 1 or 0)
    end
    local tex = (b.archive >= 0 and b.tex >= 0) and (b.archive .. "_" .. b.tex .. "_" .. b.wrap) or "white"
    return string.format("%s_%d%d%d%d_%d_%d_%d%s", tex, mode, lit and 1 or 0, nocull and 1 or 0, hl and 1 or 0, b.pass,
        b.pass == 1 and b.src or 0, b.pass == 1 and b.dst or 0, (alpha or 255) < 255 and ("_a" .. alpha) or "")
end

-- every state to warm for a character (an array of synthetic batches, in order: the shader states first, then the
-- census's states, then the textures by archive), one per material and draw state under the current settings
function W.States(kind)
    local all = {}
    local A = GSA1.Tex.Archives(kind)
    -- 1. the material states, untextured and on one of the character's textures (its first effect texture; not one of
    -- OBJ_REGULAR's, which are never painted at a spawn: cl_textures.lua T.NO_PREPARE)
    local skip = GSA1.Tex.NO_PREPARE or {}
    local reps = { { -1, -1 } }
    for a = 1, (A.n or 0) - 1 do
        if (A[a].count or 0) > 0 and not skip[A[a].name or ""] then
            reps[2] = { a, 0 }
            break
        end
    end
    if not reps[2] and (A.n or 0) > 0 and (A[0].count or 0) > 0 then
        reps[2] = { 0, 0 }
    end
    for _, r in ipairs(reps) do
        for mode = 0, 3 do
            for _, light in ipairs(LIGHTS) do
                for _, sides in ipairs({ 0, DOUBLE_SIDED }) do
                    local flags = MODES[mode] + light + sides
                    local wrap = r[1] >= 0 and CLAMP or 0
                    if mode >= 2 then
                        for _, pr in ipairs(W.PAIRS[mode]) do
                            all[#all + 1] = state(r[1], r[2], flags, pr[1], pr[2], wrap, 1)
                        end
                    else
                        all[#all + 1] = state(r[1], r[2], flags, 1, 0, wrap, 0)
                    end
                end
            end
        end
    end
    -- 2. the census's states of this kind, exactly (cl_warm_census.lua; 0.9.1: with a lit see-through batch's alpha, the
    -- 8th field); a texture the archives do not have is left out
    for _, c in ipairs((GSA1.WarmCensus or {})[kind] or {}) do
        local a, t = c[1], c[2]
        if a < 0 or t < 0 or (a < (A.n or 0) and t < (A[a].count or 0)) then
            all[#all + 1] = state(a, t, c[3], c[4], c[5], c[6], c[7], c[8])
        end
    end
    -- 3. the model's own textures in the body's state (opaque, palette-lit): the ones the first frames do not draw, such
    -- as Sonic's spin texture, which the first spin dash or Light Speed charge brings
    for i = 0, ((A.n or 0) > 0 and A[0].count or 0) - 1 do
        all[#all + 1] = state(0, i, PALETTE_LIT, 1, 0, CLAMP, 0)
    end
    -- 4. every texture of the effect archives as effects draw them (OBJ_REGULAR left out: of its 96 textures only the
    -- blob shadow's is drawn, in the census's own state - item 2)
    for a = 1, (A.n or 0) - 1 do
        for i = 0, (skip[A[a].name or ""] and 0 or (A[a].count or 0)) - 1 do
            all[#all + 1] = state(a, i, BLEND + ADDITIVE + UNLIT + EFFECT + DOUBLE_SIDED, 4, 1, CLAMP, 1)
            all[#all + 1] = state(a, i, BLEND + UNLIT + EFFECT + DOUBLE_SIDED, 4, 5, CLAMP, 1)
            all[#all + 1] = state(a, i, BLEND + ADDITIVE + UNLIT + EFFECT, 4, 1, CLAMP, 1)
        end
    end
    -- 5. (0.9.2) the DepthWrite states of the depth views: untextured in both colour modes, culled and both sides, then
    -- the census's alpha-tested opaque states (their cut-out) in both colour modes
    for _, color in ipairs({ 1, 0 }) do
        for _, sides in ipairs({ 0, DOUBLE_SIDED }) do
            local d = state(-1, -1, sides, 1, 0, 0, 0)
            d.depth = color
            all[#all + 1] = d
        end
        for _, c in ipairs((GSA1.WarmCensus or {})[kind] or {}) do
            local a, t = c[1], c[2]
            if c[7] == 0 and band(c[3], ALPHA_TEST) ~= 0 and band(c[3], BLEND) == 0 and a >= 0 and t >= 0 and
               a < (A.n or 0) and t < (A[a].count or 0) then
                local d = state(a, t, c[3], c[4], c[5], c[6], 0)
                d.depth = color
                all[#all + 1] = d
            end
        end
    end
    -- one item per material and draw state
    local out, seen = {}, {}
    for _, b in ipairs(all) do
        local k = item_key(b)
        if not seen[k] then
            seen[k] = true
            out[#out + 1] = b
        end
    end
    return out
end

-- queues a character's warm-up (at its creation, and again when the material settings change)
function W.Start(C)
    if not C or not GSA1.cv.prewarm:GetBool() then
        W.total = nil
        W.queue, W.head = { [0] = {}, [1] = {} }, { [0] = 1, [1] = 1 }
        return 0
    end
    local t0 = SysTime()
    local q = { [0] = {}, [1] = {} }
    local n = 0
    for _, b in ipairs(W.States(C.kind)) do
        -- one item per material and pass / blend factors (W.States); items done already (this session) are skipped
        local id = C.kind .. ":" .. item_key(b)
        if not W.done[id] then
            b.id = id
            local list = q[b.pass]
            list[#list + 1] = b
            n = n + 1
        end
    end
    W.queue, W.head = q, { [0] = 1, [1] = 1 }
    W.total = { kind = C.kind, title = C.title, items = n, drawn = 0, created = 0, createMs = 0, ms = 0, frames = 0,
                lastFrame = -1, slowest = 0, slowName = "", t0 = SysTime(), listMs = (SysTime() - t0) * 1000,
                materials0 = GSA1.Tex.nmats or 0, slowLines = 0, done = n == 0 }   -- nothing left: done (no log line)
    return n
end

-- a material the pre-warm made (cl_textures.lua T.Material); own: made by the character's own draws meanwhile
function GSA1.WarmCreated(name, dt, own)
    local s = W.total
    if s then
        if own then
            s.own = (s.own or 0) + 1
        else
            s.created = s.created + 1
        end
        s.createMs = s.createMs + dt * 1000
    end
end

-- a render target a batch needed while the warm-up runs (cl_textures.lua T.Get)
function GSA1.WarmTarget(dt)
    local s = W.total
    if s then s.targets = (s.targets or 0) + 1 end
end

-- the warm-up is running: materials made meanwhile are counted with it (cl_textures.lua)
function GSA1.WarmRunning()
    return W.total ~= nil and not W.total.done
end

local P, N = Vector(0, 0, 0), Vector(0, 0, 1)

-- one zero-area triangle with the item's material and state (the blend factors of T.BlendOf: the shadow's mask too), at
-- the character (relative to the frame's origin while cl_render.lua draws camera-relative); 0.9.2: a DepthWrite state
-- (b.depth: its $color_depth) with T.DepthMaterial
local function draw_item(C, b)
    local T = GSA1.Tex
    local mat
    if b.depth then
        mat = T.DepthMaterial(C.kind, b, b.depth == 1, true)
    else
        mat = T.Material(C.kind, b, true)
    end
    render.SetMaterial(mat)
    if b.pass == 1 then
        local s, d = T.BlendOf(b)
        render.OverrideBlend(true, s, d, BLENDFUNC_ADD)
    end
    P:Set(C.drawPos)
    if C.relOrigin then P:Sub(C.relOrigin) end
    mesh.Begin(MATERIAL_TRIANGLES, 1)
    for _ = 1, 3 do
        mesh.Position(P)
        mesh.Normal(N)
        mesh.TexCoord(0, 0, 0)
        mesh.Color(255, 255, 255, 0)
        mesh.AdvanceVertex()
    end
    mesh.End()
    if b.pass == 1 then render.OverrideBlend(false) end
end

local function finished(s)
    s.done = true
    if GSA1.Log then
        GSA1.Log("warm", "%s: %d materials and states prepared in %.1f ms over %d frames (%d materials made, %d more and "
            .. "%d render targets by the character's own first frames, %.1f ms of CreateMaterial; the slowest item "
            .. "%.2f ms: %s)", s.title or "?", s.drawn, s.ms, s.frames, s.created, s.own or 0, s.targets or 0, s.createMs,
            s.slowest * 1000, s.slowName)
    end
end

-- called by GSA1.DrawCharacter in each pass (with the lighting set up): a few items of this pass within the budget
function W.Step(C, pass)
    local s = W.total
    if not s or s.done or not C or C.kind ~= s.kind or not C.drawPos then return end
    local fn = FrameNumber()
    if s.lastFrame ~= fn then
        s.lastFrame = fn
        s.frames = s.frames + 1
        s.frameUsed = 0
    end
    if s.slowFrame == fn then return end      -- one slow item per frame at most (a shader or pipeline was made)
    local list, head = W.queue[pass], W.head[pass]
    local t0 = SysTime()
    local here = 0
    while head <= #list do
        -- the frame's budget (both passes); at least one item per pass and frame
        if here > 0 and s.frameUsed >= WARM_BUDGET then break end
        here = here + 1
        local b = list[head]
        head = head + 1
        local ti = SysTime()
        draw_item(C, b)
        local dt = SysTime() - ti
        W.done[b.id] = true
        s.drawn = s.drawn + 1
        s.frameUsed = s.frameUsed + dt
        if dt > s.slowest then
            s.slowest = dt
            s.slowName = b.key
        end
        if dt >= SLOW and GSA1.Log and s.slowLines < SLOW_LINES then
            s.slowLines = s.slowLines + 1
            GSA1.Log("warm", "%s took %.1f ms (its first use: a shader or pipeline was made)", b.key, dt * 1000)
        end
        if dt >= SLOW then
            s.slowFrame = fn
            break
        end
    end
    W.head[pass] = head
    local spent = SysTime() - t0
    s.ms = s.ms + spent * 1000
    if GSA1.HitchAdd then GSA1.HitchAdd("Warm", spent) end
    if W.head[0] > #W.queue[0] and W.head[1] > #W.queue[1] then finished(s) end
end

-- "pre-warm: Sonic, 561 of 561 materials and states (82 made) in 210 ms over 140 frames" (status, summary)
function GSA1.WarmLine()
    local s = W.total
    if not s then return "pre-warm: " .. (GSA1.cv.prewarm:GetBool() and "nothing yet" or "off (gsa1_prewarm 0)") end
    return string.format("pre-warm: %s, %d of %d materials and states (%d made, %.1f ms of CreateMaterial) in %.1f ms "
        .. "over %d frames%s; the slowest %.2f ms", s.title or "?", s.drawn, s.items, s.created, s.createMs, s.ms, s.frames,
        s.done and "" or " (going on)", s.slowest * 1000)
end
