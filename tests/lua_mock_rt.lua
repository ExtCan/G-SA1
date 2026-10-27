-- lua_mock_rt.lua - a render-target pixel model for tests/lua_mock.lua (opt-in), so the addon's texture painting can be
-- checked offline (sadc docs/research/gsa1_060_alpha.md section 8 item 1 with its review). It replaces the mock's
-- render / surface / cam / mesh drawing calls with ones that keep the pixels of render targets, with the semantics
-- measured in the installed Garry's Mod and in Direct3D 9 (native and GMod's DXVK) - and nothing from the game:
--   * GetRenderTargetEx(name, w, h, size, depth, ...) keeps `depth`; a new target is OPAQUE black (0, 0, 0, 255): Source's
--     creation clear (CTexture::Download: ClearColor4ub(0, 0, 0, 255));
--   * render.PushRenderTarget / PopRenderTarget keep a stack; render.Clear(r, g, b, a, depth, stencil) on a target made
--     with MATERIAL_RT_DEPTH_NONE does NOTHING when depth or stencil is asked (D3DERR_INVALIDCALL drops the whole clear),
--     else fills RGBA (the alpha write mask is ignored, as D3D9's Clear ignores D3DRS_COLORWRITEENABLE);
--   * surface.SetDrawColor stores the alpha times the surface alpha multiplier (truncated; vgui's DrawSetColor);
--     surface.SetAlphaMultiplier / GetAlphaMultiplier; surface.DrawRect with alpha 0 draws NOTHING (vgui's
--     DrawFilledRect returns early), else blends its colour into the target;
--   * render.OverrideBlend(on, srcC, dstC, op [, srcA, dstA, opA]) - with the separate alpha factors when given (and
--     M.rt.separate_alpha is true: set it false to model a host that ignores them), else the colour factors for alpha
--     too; no override: SRC_ALPHA / ONE_MINUS_SRC_ALPHA; the alpha channel is written only under
--     render.OverrideAlphaWriteEnable(true, true);
--   * mesh quads (mesh.Begin(MATERIAL_QUADS) ... mesh.End()) inside cam.Start2D on a render target: axis-aligned quads
--     rasterised at pixel centres, the material's $basetexture sampled nearest (a render target by its name, or
--     vgui/white), times the vertex colour ($vertexcolor) and alpha ($vertexalpha), blended like DrawRect (a draw does
--     write alpha 0, unlike vgui's DrawRect);
--   * render.CapturePixels / ReadPixel(x, y) read the current target (RGBA8888).
--   * 0.9.1, Source's shader rule for the mesh quads (sadc docs/research/gsa1_070_translucency.md 4.3, verified in the
--     owner's stdshader_dx9.dll; T2.2 with its review R3.6): VertexLitGeneric IGNORES $vertexcolor and $vertexalpha and
--     multiplies $alpha (its lighting: a white ambient cube, x 1); UnlitGeneric honours $vertexcolor, $vertexalpha and
--     $alpha. M.rt.vlg_alpha = false models a host where VertexLitGeneric ignores $alpha too (the T3 check's "lost").
--     M.effective_alpha(mat, va, ta): the alpha a draw of material mat with vertex alpha va and texel alpha ta has.
-- M.rt.colour_clear_works = false models a host where even a colour-only clear fails (the addon then clears by
-- drawing). M.rt.linear = true (0.9.2a, gsa1_091a_perf.md T3b) models a framebuffer that blends in linear light
-- (sRGB-correct, the owner's Garry's Mod): the colour channels are decoded from sRGB, blended and encoded again (alpha
-- stays linear); default false, the gamma-space blend of the other tests. The original mock functions still run (call
-- counters, M.onDraw).
--   local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
--   local R = host_load(host_read(tests .. "/lua_mock_rt.lua"), "lua_mock_rt.lua")()(M)
return function(M)
    local R = { stack = {}, cur = nil, alphaWrite = nil, blend = nil, in2d = false, color = { 255, 255, 255, 255 },
                mult = 1, separate_alpha = true, colour_clear_works = true, captured = nil, dropped = 0, clears = 0,
                vlg_alpha = true, linear = false }
    M.rt = R
    BLEND_ZERO, BLEND_ONE, BLEND_DST_COLOR, BLEND_ONE_MINUS_DST_COLOR = 0, 1, 2, 3
    BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLEND_DST_ALPHA, BLEND_ONE_MINUS_DST_ALPHA = 4, 5, 6, 7
    BLEND_SRC_ALPHA_SATURATE, BLEND_SRC_COLOR, BLEND_ONE_MINUS_SRC_COLOR = 8, 9, 10
    BLENDFUNC_ADD = 0
    MATERIAL_TRIANGLES, MATERIAL_QUADS = 2, 7
    MATERIAL_RT_DEPTH_SHARED, MATERIAL_RT_DEPTH_SEPARATE, MATERIAL_RT_DEPTH_NONE = 0, 1, 2

    local RTMT = {}
    RTMT.__index = RTMT
    function RTMT:GetName() return self.name end
    function RTMT:Width() return self.w end
    function RTMT:Height() return self.h end
    -- fills every texel (tests use it to model a device reset)
    function RTMT:Fill(r, g, b, a)
        for i = 1, self.w * self.h do
            self.r[i], self.g[i], self.b[i], self.a[i] = r, g, b, a
        end
    end
    function RTMT:Get(x, y)
        local i = y * self.w + x + 1
        return self.r[i], self.g[i], self.b[i], self.a[i]
    end
    R.RTMT = RTMT

    function GetRenderTargetEx(name, w, h, size, depth, flags, rtflags, fmt)
        M.calls.GetRenderTargetEx = (M.calls.GetRenderTargetEx or 0) + 1
        local rt = M.rts[name]
        if not rt then
            rt = setmetatable({ name = name, w = w, h = h, depth = depth, flags = flags, fmt = fmt, r = {}, g = {}, b = {},
                                a = {} }, RTMT)
            rt:Fill(0, 0, 0, 255)            -- Source's creation clear: opaque black
            M.rts[name] = rt
            M.nrts = M.nrts + 1
        end
        return rt
    end

    function render.PushRenderTarget(rt)
        R.stack[#R.stack + 1] = R.cur or false
        R.cur = rt
    end
    function render.PopRenderTarget()
        local top = R.stack[#R.stack]
        R.stack[#R.stack] = nil
        R.cur = top or nil
    end
    function render.Clear(r, g, b, a, depth, stencil)
        local t = R.cur
        if not t then return end
        if (depth or stencil) and t.depth == MATERIAL_RT_DEPTH_NONE then
            R.dropped = R.dropped + 1        -- D3DERR_INVALIDCALL: nothing is cleared
            return
        end
        if not R.colour_clear_works then return end
        R.clears = R.clears + 1
        t:Fill(r, g, b, a or 255)
    end
    function render.OverrideAlphaWriteEnable(enable, write)
        if enable then R.alphaWrite = write and true or false else R.alphaWrite = nil end
    end
    function render.OverrideBlend(on, sc, dc, op, sa, da, opa)
        if not on then R.blend = nil return end
        R.blend = { sc, dc, sa, da }
    end
    function render.CapturePixels()
        local t = R.cur
        if not t then R.captured = nil return end
        local c = { w = t.w, h = t.h, r = {}, g = {}, b = {}, a = {} }
        for i = 1, t.w * t.h do c.r[i], c.g[i], c.b[i], c.a[i] = t.r[i], t.g[i], t.b[i], t.a[i] end
        R.captured = c
    end
    function render.ReadPixel(x, y)
        local c = R.captured
        if not c or x < 0 or y < 0 or x >= c.w or y >= c.h then return nil end
        local i = y * c.w + x + 1
        return c.r[i], c.g[i], c.b[i], c.a[i]
    end
    local old_setmat = render.SetMaterial
    function render.SetMaterial(m)
        old_setmat(m)
        R.material = m
    end
    cam.Start2D = function() R.in2d = true end
    cam.End2D = function() R.in2d = false end
    draw.NoTexture = function() end

    function surface.SetAlphaMultiplier(m) R.mult = math.min(math.max(m, 0), 1) end
    function surface.GetAlphaMultiplier() return R.mult end
    function surface.SetDrawColor(r, g, b, a)
        if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
        R.color = { r, g, b, math.floor((a or 255) * R.mult) }
    end

    -- blending one source colour into texel i of target t
    local function factor(f, s, d, c)
        if f == 0 then return 0 elseif f == 1 then return 1
        elseif f == 2 then return d[c] / 255 elseif f == 3 then return 1 - d[c] / 255
        elseif f == 4 then return s[4] / 255 elseif f == 5 then return 1 - s[4] / 255
        elseif f == 6 then return d[4] / 255 elseif f == 7 then return 1 - d[4] / 255
        elseif f == 9 then return s[c] / 255 elseif f == 10 then return 1 - s[c] / 255 end
        return 1
    end
    local function clamp8(v)
        v = math.floor(v + 0.5)
        if v < 0 then return 0 elseif v > 255 then return 255 end
        return v
    end
    -- sRGB <-> linear light on 0..255 (R.linear)
    local function dec8(v)
        v = v / 255
        return 255 * (v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4)
    end
    local function enc8(v)
        v = math.max(0, math.min(1, v / 255))
        return 255 * (v <= 0.0031308 and v * 12.92 or 1.055 * v ^ (1 / 2.4) - 0.055)
    end
    local function write(t, i, s)
        local d = { t.r[i], t.g[i], t.b[i], t.a[i] }
        local sc, dc, sa, da = 4, 5, nil, nil
        if R.blend then sc, dc, sa, da = R.blend[1], R.blend[2], R.blend[3], R.blend[4] end
        if sa == nil or not R.separate_alpha then sa, da = sc, dc end
        if R.linear then
            local sl = { dec8(s[1]), dec8(s[2]), dec8(s[3]), s[4] }
            local dl = { dec8(d[1]), dec8(d[2]), dec8(d[3]), d[4] }
            t.r[i] = clamp8(enc8(sl[1] * factor(sc, sl, dl, 1) + dl[1] * factor(dc, sl, dl, 1)))
            t.g[i] = clamp8(enc8(sl[2] * factor(sc, sl, dl, 2) + dl[2] * factor(dc, sl, dl, 2)))
            t.b[i] = clamp8(enc8(sl[3] * factor(sc, sl, dl, 3) + dl[3] * factor(dc, sl, dl, 3)))
        else
            t.r[i] = clamp8(s[1] * factor(sc, s, d, 1) + d[1] * factor(dc, s, d, 1))
            t.g[i] = clamp8(s[2] * factor(sc, s, d, 2) + d[2] * factor(dc, s, d, 2))
            t.b[i] = clamp8(s[3] * factor(sc, s, d, 3) + d[3] * factor(dc, s, d, 3))
        end
        if R.alphaWrite == true then
            t.a[i] = clamp8(s[4] * factor(sa, s, d, 4) + d[4] * factor(da, s, d, 4))
        end
    end
    R.write = write

    local old_rect = surface.DrawRect
    function surface.DrawRect(x, y, w, h)
        if old_rect then old_rect(x, y, w, h) end
        local t = R.cur
        if not t or not R.in2d then return end
        if R.color[4] == 0 then return end   -- vgui's DrawFilledRect: nothing for alpha 0
        local s = R.color
        for py = math.max(0, y), math.min(t.h, y + h) - 1 do
            for px = math.max(0, x), math.min(t.w, x + w) - 1 do
                write(t, py * t.w + px + 1, s)
            end
        end
    end

    -- mesh: quads drawn in 2D onto a render target
    local MB = { verts = {}, n = 0, prim = nil, imesh = false, cur = {} }
    local old_begin, old_end = mesh.Begin, mesh.End
    local old_pos, old_tc, old_col, old_adv = mesh.Position, mesh.TexCoord, mesh.Color, mesh.AdvanceVertex
    function mesh.Begin(a, b, c)
        old_begin(a, b, c)
        MB.imesh = type(a) == "table"
        MB.prim = MB.imesh and b or a
        MB.n = 0
        MB.cur = { x = 0, y = 0, z = 0, u = 0, v = 0, r = 255, g = 255, b = 255, a = 255 }
    end
    function mesh.Position(p)
        old_pos(p)
        MB.cur.x, MB.cur.y, MB.cur.z = p.x, p.y, p.z
    end
    function mesh.TexCoord(stage, u, v)
        old_tc(stage, u, v)
        MB.cur.u, MB.cur.v = u, v
    end
    function mesh.Color(r, g, b, a)
        old_col(r, g, b, a)
        MB.cur.r, MB.cur.g, MB.cur.b, MB.cur.a = r, g, b, a
    end
    function mesh.AdvanceVertex()
        old_adv()
        MB.n = MB.n + 1
        local c = MB.cur
        MB.verts[MB.n] = { x = c.x, y = c.y, z = c.z, u = c.u, v = c.v, r = c.r, g = c.g, b = c.b, a = c.a }
    end
    local function sample(mat, u, v)
        local p = mat and mat.params or {}
        local tex = p["$basetexture"]
        local rt = type(tex) == "string" and M.rts[tex] or nil
        if not rt then return 255, 255, 255, 255 end
        local x = math.min(rt.w - 1, math.max(0, math.floor(u * rt.w)))
        local y = math.min(rt.h - 1, math.max(0, math.floor(v * rt.h)))
        return rt:Get(x, y)
    end
    R.sample = sample
    -- a texel (tr, tg, tb, ta) as the material draws it with the vertex colour (vr, vg, vb, va): Source's rule (above)
    local function shade(mat, tr, tg, tb, ta, vr, vg, vb, va)
        local p = mat and mat.params or {}
        local vlg = mat ~= nil and mat.shader == "VertexLitGeneric"
        if not vlg then
            if p["$vertexcolor"] == 1 then
                tr, tg, tb = tr * vr / 255, tg * vg / 255, tb * vb / 255
            end
            if p["$vertexalpha"] == 1 then ta = ta * va / 255 end
        end
        local am = tonumber(p["$alpha"]) or 1
        if not vlg or R.vlg_alpha then ta = ta * am end
        return tr, tg, tb, ta
    end
    R.shade = shade
    function M.effective_alpha(mat, va, ta)
        local _, _, _, a = shade(mat, 255, 255, 255, ta or 255, 255, 255, 255, va or 255)
        return a
    end
    function mesh.End()
        old_end()
        local t = R.cur
        if MB.imesh or not t or not R.in2d or MB.prim ~= MATERIAL_QUADS then return end
        local mat = R.material
        for q = 0, math.floor(MB.n / 4) - 1 do
            local v1, v3 = MB.verts[q * 4 + 1], MB.verts[q * 4 + 3]
            local x0, x1 = math.min(v1.x, v3.x), math.max(v1.x, v3.x)
            local y0, y1 = math.min(v1.y, v3.y), math.max(v1.y, v3.y)
            for py = math.max(0, math.floor(y0)), math.min(t.h, math.ceil(y1)) - 1 do
                for px = math.max(0, math.floor(x0)), math.min(t.w, math.ceil(x1)) - 1 do
                    local cx, cy = px + 0.5, py + 0.5
                    if cx >= x0 and cx < x1 and cy >= y0 and cy < y1 then
                        local fu = (cx - v1.x) / (v3.x - v1.x)
                        local fv = (cy - v1.y) / (v3.y - v1.y)
                        local u = v1.u + fu * (v3.u - v1.u)
                        local v = v1.v + fv * (v3.v - v1.v)
                        local tr, tg, tb, ta = sample(mat, u, v)
                        tr, tg, tb, ta = shade(mat, tr, tg, tb, ta, v1.r, v1.g, v1.b, v1.a)
                        write(t, py * t.w + px + 1, { tr, tg, tb, ta })
                    end
                end
            end
        end
    end
    return R
end
