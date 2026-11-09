-- G-SA1 a skin's name and nameplate pictures, the client part (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 4.7 with RX.11; the pure part is feat/sh_skinhud.lua, which says what may be here).
-- Made the first time a skin's slot is shown on Character Select (S.SkinShown), in PostRender, one step a frame; until a picture has read back right the game's own name and plate stay (no blank
-- frame). Drawn by feat/cl_charselect_bar.lua's draw filter at the game's own quad (H.Picture, H.Shown).
-- 1.0.0-beta1a (the owner: "The nameplates aren't generated", "The name.png files that are generated are the wrong font"; sadc/build/research/b1a/b1a-text/NOTES.md): the game's faces and places
-- (MEASURED, sh_skinhud.lua), checked by reading back, corrected once if the letters are not where the game has them, fitted once to the game's width when squeezed. A picture the owner put there
-- (sh_skinhud.lua H.IsMade) is copied with its own alpha. Nothing is written but generated.txt's lines.
-- THE NAMES FIX after beta 1a (sadc/build/research/b1a2; the owner: "The pulsating names appear for a second and then turn into black squares"). Beta 1a painted each picture into a whole render target
-- of its own (1024 x 256, 2048 x 256: the only ones of that kind), three paints and three read-backs in one frame, then drew it smaller than its texels through mesh, and never read it again: a canvas
-- that lost its texels stayed a silent black box (MEASURED by the trace lane's negative control; which engine event does it is UNVERIFIED). NOW, only paths the owner's game has shown right:
--   * each picture is a part of a text atlas page (feat/cl_text.lua T.Place: the pages, painter and read-back that kept the bar's labels right all session), one paint and one read a frame;
--   * it is drawn at the game's quad with surface.DrawTexturedRectUV as the labels are (cl_charselect_bar.lua S.DrawFilter), never smaller than 0.77 of its texels (sh_skinhud.lua H.AtlasScale);
--   * THE SELF-CHECK: while shown, one read a second at most (a clear texel and an ink texel of each shown picture, the page's canary, and on the CPU what its material samples); the log says
--     once when a picture still reads right 5 s after its first draw, and at once if it ever reads changed;
--   * b1a2-fix2 (the verifier: each check was one capture of a whole 2048 x 1024 page, 8 MiB, for 5 texels): a read is now cl_text.lua T.ReadTexels, those texels drawn through the page's own
--     material into a 16 x 4 target and read there, so it also sees what the material samples. The make reads them the same way right after its read of the page (what the checks compare
--     with: like with like), and the canary is compared with what it read at the page's make, not with the painted colour; the log says what the first read cost;
--   * THE FALLBACK: a picture that reads changed, black or not at all is never drawn again: the game's own name or plate is (never a black square), the log says why, and it is made again once.
GSA1 = GSA1 or {}
local H = GSA1.SkinHud
if not H then error("gsa1/feat/sh_skinhud.lua did not load: the skins' pictures need it") end
local K = GSA1.Skins

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("skinhud", fmt, ...) end
end

H.mats = H.mats or {}           -- [id] = { name = picture | false, plate = picture | false }: what the draw filter may draw now (feat_charselect_test.lua T5 sets it as it is)
H.state = H.state or {}         -- [id] = { name = record, plate = record }: what made each picture, what it read at the make, its shows and checks (kept across its remakes)
H.queue = H.queue or {}
H.stats = H.stats or { made = 0, loaded = 0, failed = 0, deleted = 0, drawn = 0, reads = 0, kept = 0, changed = 0, remade = 0 }
H.said = H.said or {}
H.check = H.check or { period = H.CHECK_PERIOD, reads = 0 }

local BLACK = { r = 0, g = 0, b = 0, a = 255 }
local WHICH = { "name", "plate" }

local function title(e) return tostring(e and e.title or "?") end
local function what(which) return which == "name" and "name" or "nameplate" end

local function queue(id, which, path, how)
    for _, j in ipairs(H.queue) do
        if j.id == id and j.which == which then return end
    end
    local cur = H.job
    if cur and cur.id == id and cur.which == which then return end
    H.queue[#H.queue + 1] = { id = id, which = which, path = path, how = how }
end

local function record(id, which)
    local st = H.state[id]
    if not st then
        st = {}
        H.state[id] = st
    end
    local s = st[which]
    if not s then
        s = { changes = 0, remakes = 0 }
        st[which] = s
    end
    return s
end

-- beta 1's made files of a skin (in generated.txt and not newer than it): deleted once; the list keeps only what is still G-SA1's (nothing, from beta 1a on). A newer file of that name is the owner's
local function forget_made(P, e)
    if H.said["old_" .. e.id] then return end
    H.said["old_" .. e.id] = true
    local text = file.Read(P.list, "DATA")
    if not text then return end
    local set = H.ParseGenerated(text)
    local tl = file.Time and file.Time(P.list, "DATA") or 0
    local gone, kept = {}, {}
    for name in pairs(set) do
        local path = P.dir .. "/" .. name
        if file.Exists(path, "DATA") then
            if H.IsMade(set, name, file.Time and file.Time(path, "DATA") or 0, tl) then
                file.Delete(path)
                gone[#gone + 1] = name
            else
                kept[#kept + 1] = name
            end
        end
    end
    file.Write(P.list, H.FormatGenerated({}))
    table.sort(gone)
    if #gone > 0 then
        H.stats.deleted = H.stats.deleted + #gone
        log("%s: beta 1's made %s deleted (no alpha, the wrong face): made each session into the text pictures' atlas from now on", title(e), table.concat(gone, " and "))
    end
    if #kept > 0 then log("%s: %s newer than generated.txt: yours, used as it is", title(e), table.concat(kept, " and ")) end
end

-- a skin was shown: its two pictures queued (made, or the owner's own copied)
function H.Want(e)
    if not (e and e.id) or H.mats[e.id] then return end
    local t = { name = false, plate = false }
    H.mats[e.id] = t
    H.state[e.id] = H.state[e.id] or {}
    local P = H.Paths(e)
    if not P then return end
    forget_made(P, e)
    for _, which in ipairs(WHICH) do
        local path = P[which]
        if path then
            local w = H.Wants(e, which, file.Exists(path, "DATA") == true)
            if w ~= "none" then queue(e.id, which, path, w) end
        end
    end
end

-- the picture of a skin's name or plate to draw now: { mat (its atlas page), u0, v0, u1, v1, w, h, page, ... }, or nil: not made yet, not read right, its page emptied (made again), the text
-- pictures not handed out (cl_text.lua T.Handing), or read changed once (the fallback): the game's own is drawn
function H.Picture(id, which)
    local e = K and K.SKINS and K.SKINS[id]
    if not e then return nil end
    if not H.mats[id] then H.Want(e) end
    local t = H.mats[id]
    local pic = t and t[which]
    if not pic then return nil end
    local s = H.state[id] and H.state[id][which]
    if s and s.pic == pic then
        local Tx = GSA1.Text
        if not (Tx and Tx.PicValid and Tx.PicValid(pic)) then
            -- (its page was emptied for room, or lost with every picture: made again; the game's own meanwhile)
            t[which] = false
            s.pic = nil
            queue(id, which, s.path, s.how)
            return nil
        end
        if not (Tx.Handing and Tx.Handing()) then return nil end
    end
    return pic
end
H.Material = H.Picture          -- (beta 1a's name for it)

-- the draw filter drew the picture of (id, which) in place of the game's draw `gname` (archive, tex of kind): its page is in use, its show's clock runs (a show after H.RESHOW s away starts it again,
-- so its first check comes H.CHECK_PERIOD after every show), and the first draw of each make says so in the log
function H.Shown(id, which, gname, archive, tex, kind)
    local t = H.mats[id]
    local pic = t and t[which]
    local fr, now = FrameNumber(), RealTime()
    if pic and pic.page then pic.page.used = fr end
    local s = H.state[id] and H.state[id][which]
    if not (s and pic and s.pic == pic) then return end
    if not s.first then s.first = now end
    if not s.last or now - s.last >= H.RESHOW then
        s.shown = now
        s.next = now + (H.check.period or H.CHECK_PERIOD)
    end
    s.last, s.used = now, fr
    if gname then
        local g = s.game                -- (kept in place: nothing made a frame)
        if not g then
            g = {}
            s.game = g
        end
        g.name, g.archive, g.tex, g.kind = gname, archive, tex, kind
    end
    if not s.drawn then
        s.drawn = true
        H.stats.drawn = H.stats.drawn + 1
        local e = K and K.SKINS and K.SKINS[id]
        log("skin %s drawn for %s on Character Select (%s, a picture of %d x %d on text page %d, drawn as the bar's labels are, in place of the game's %s; checked once a second while shown)", which == "name" and "name" or "plate",
            title(e), s.how == "load" and ("your own " .. tostring(H.Base(s.path))) or "made", pic.w or 0, pic.h or 0, pic.page and pic.page.index or 0, tostring(gname))
    end
end

-- THE MAKE ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- the letters' rows and columns in a painted picture (one read-back of its page, T.ReadPic, in the picture's own px; its margin read too, so a letter painted off is seen): the name's ink (alpha >= 128,
-- its outline included), the plate's dark letters in its white field; its clear texel (sh_skinhud.lua H.ClearPoint); on the plate the white field's alpha; and one ink texel the self-check reads again
-- (on the middle row of the letters from their first column: the name's fill, else its outline; the plate's dark letters). nil: not readable
local function measure(Tx, pic, L, which, x, width)
    local M = H.MARGIN * L.s
    return Tx.ReadPic(pic, function(read)
        local function is_ink(r, g, b, a)
            if which == "name" then return (a or 255) >= 128 end
            return math.max(r, g, b) < 100
        end
        local unread = false
        local function ink_at(xx, yy)
            local r, g, b, a = read(xx, yy)
            if r == nil then
                unread = true
                return false
            end
            return is_ink(r, g, b, a)
        end
        local top, bot = nil, nil
        local y0, y1 = -M, L.h - 1 + M
        if which == "plate" then y0, y1 = L.frame + L.s, L.bar[2] - L.s end
        local cols = 16
        for i = 0, cols - 1 do
            local xx = math.max(-M, math.min(L.w - 1 + M, math.floor(x + (i + 0.5) * width / cols)))
            for yy = y0, y1 do
                if ink_at(xx, yy) then
                    if not top or yy < top then top = yy end
                    if not bot or yy > bot then bot = yy end
                end
                if unread then return nil end
            end
        end
        -- the ink's first and last columns (from each side inwards, every other row of the letters'; the plate's inside its white field)
        local left, right = nil, nil
        local xa, xb = -M, L.w - 1 + M
        if which == "plate" then xa, xb = L.frame + 1, L.x1 + L.s - L.frame - 2 end
        if top then
            local step = math.max(1, math.floor(L.s / 2))
            local function col(xx)
                for yy = top, bot, step do
                    if ink_at(xx, yy) then return true end
                end
                return ink_at(xx, bot) == true
            end
            for xx = xa, xb do
                if col(xx) then left = xx break end
            end
            if left then
                for xx = xb, left, -1 do
                    if col(xx) then right = xx break end
                end
            end
        end
        if unread then return nil end
        local ink = nil
        if top and left then
            local rows = { math.floor((top + bot) / 2), math.floor((3 * top + bot) / 4), math.floor((top + 3 * bot) / 4) }
            for pass = 1, 2 do
                for _, yy in ipairs(rows) do
                    for xx = left, right or left do
                        local r, g, b, a = read(xx, yy)
                        if r == nil then return nil end
                        local solid = (a or 0) >= 250
                        local want = pass == 2 and is_ink(r, g, b, a) or (pass == 1 and solid and (which == "plate" and math.max(r, g, b) < 100 or which == "name" and math.max(r, g, b) >= 40))
                        if want then
                            ink = { xx, yy, r, g, b, a or 255 }
                            break
                        end
                    end
                    if ink then break end
                end
                if ink then break end
            end
        end
        local cx, cy = H.ClearPoint(L)
        local cr, cg, cb, ca = read(cx, cy)
        if cr == nil then return nil end
        local fa = nil
        if which == "plate" then fa = select(4, read(L.frame + 1, L.frame + 1)) end
        return { top = top, bot = bot, left = left, right = right, corner = ca, clear = { cr, cg, cb, ca or 255 }, clearAt = { cx, cy }, field = fa, ink = ink }
    end)
end

-- the read-back's verdict on a made picture: nil = good, or why it is not drawn (the game's own stays). Since the names fix a picture that cannot be read back is not drawn either
local function verdict(got, which, L)
    if not got then return "not readable here (render.ReadPixel gave nothing): only a picture that read back right is drawn" end
    if got.corner ~= nil and got.corner > 1 then return string.format("a texel that must be clear reads alpha %d, not 0: it would draw as a box", got.corner) end
    if not got.top then return "no letter read back: they would not show" end
    if which == "plate" and got.field ~= nil and got.field < 200 then return string.format("the white field reads alpha %d, not 255: it would not show", got.field) end
    if L and (got.top < 0 or got.bot > L.h - 1 or (got.left or 0) < 0 or (got.right or 0) > L.w - 1) then
        return string.format("the letters reach outside the picture (rows %d..%d, columns %s..%s of %d x %d): they would be cut", got.top, got.bot, tostring(got.left), tostring(got.right), L.w, L.h)
    end
    if not got.ink then return "no ink texel to check it by" end
    return nil
end
H.Verdict = verdict

local function fit_of(L, th, adv, n, mt)
    local sx, sy, x, y, track, width = H.Fit(L, th, adv, n, mt)
    return { sx = sx, sy = sy, x = x, y = y, track = track, width = width }
end

-- one paint of a made name or plate into its box, from the fit f, and its read
local function paint_read(Tx, job)
    local L, pic, which, f = job.L, job.pic, job.which, job.fit
    local ok, err = Tx.PaintPic(pic, function(ox, oy)
        Tx.ClearRect(pic.ax, pic.ay, pic.aw, pic.ah, 0, 0, 0)
        if which == "plate" then
            local s = L.s
            Tx.FillRect(ox, oy, L.x1 + s, L.bottom + s, 0, 0, 0, 255)
            Tx.FillRect(ox + L.frame, oy + L.frame, L.x1 + s - 2 * L.frame, L.bottom + s - 2 * L.frame, 255, 255, 255, 255)
            local b = L.bar
            Tx.FillRect(ox + b[1], oy + b[2], b[3] - b[1] + s, b[4] - b[2] + s, 0, 0, 0, 255)
        end
        Tx.DrawLetters({ text = job.text, font = job.font, x = ox + f.x, y = oy + f.y, color = job.color, outline = job.ol, ocolor = BLACK, track = f.track, space = L.space, sx = f.sx, sy = f.sy, bold = L.bold })
    end)
    if not ok then return false, tostring(err) end
    local got, rerr = measure(Tx, pic, L, which, f.x - job.ol, f.width + 2 * job.ol)
    if not got then return false, "not readable here (" .. tostring(rerr or "render.ReadPixel gave nothing") .. "): only a picture that read back right is drawn" end
    return true, got
end

-- after a read: the engine's font not quite the file's proportions? (the letters' rows against the game's, MEASURED in sh_skinhud.lua) -> the fit from what was read, or nil
local function correction(job, got)
    local L, which, ol, f = job.L, job.which, job.ol, job.fit
    if not (got and got.top) then return nil end
    local want0 = which == "name" and (L.cy - L.cap / 2 - ol) or (L.cy - L.cap / 2)
    local want1 = which == "name" and (L.cy + L.cap / 2 + ol) or (L.cy + L.cap / 2)
    local cap = (got.bot - got.top + 1) - (which == "name" and 2 * ol or 0)
    local k = cap / L.cap
    local off = (got.top + got.bot + 1) / 2 - (want0 + want1) / 2
    if math.abs(k - 1) <= 0.03 and math.abs(off) <= math.max(2, L.s / 2) then return nil end
    local captop = got.top + (which == "name" and ol or 0)
    local real = { cap = cap / (job.th * f.sy), asc = (captop - f.y) / (job.th * f.sy) + cap / (job.th * f.sy) }
    if not (real.cap > 0.1 and real.cap < 1.5) then return nil end
    return fit_of(L, job.th, job.adv, job.n, real)
end

-- squeezed (a long text): the game's own fill their room exactly (MEASURED: m_supersonic 8..246 with its outline, B_SONIC_e and B_KNUCKLES_e x 10..379), and a face's ink is narrower than its advances:
-- fitted to the room once from the columns read back, the line scaled sideways about its own start and its ink centred where the game's is -> the fit, or nil
local function widthfit(job, got)
    local L, which, ol, f = job.L, job.which, job.ol, job.fit
    if not (f.sx < f.sy * 0.999 and got and got.left and got.right) then return nil end
    local o = which == "name" and ol or 0
    local fl, fr = got.left + o, got.right - o
    local fw = fr - fl + 1
    local room = L.max_w - 2 * ol
    local q = room / math.max(1, fw)
    if not (math.abs(fw - room) > L.s and q > 0.85 and q < 1.15) then return nil end
    local cf = (fl + fr + 1) / 2
    return { sx = f.sx * q, sy = f.sy, x = L.cx - (cf - f.x) * q, y = f.y, track = f.track * q, width = f.width * q }
end

-- the owner's own picture into its box, its colour and alpha as they are (drawn ONE / ZERO, as feat/cl_objicons.lua copies the 1-up icon), and read back: the corner's alpha, and the two texels
-- the self-check reads again (as they are: an own picture need not be clear anywhere)
local function paint_file(Tx, job)
    local L, pic = job.L, job.pic
    local png = Material("../data/" .. job.path, "smooth")
    if not png or (png.IsError and png:IsError()) then return false, job.path .. " does not load as a picture" end
    local ok, err = Tx.PaintPic(pic, function(ox, oy)
        Tx.ClearRect(pic.ax, pic.ay, pic.aw, pic.ah, 0, 0, 0)
        render.OverrideBlend(true, 1, 0, 0, 1, 0, 0)
        surface.SetMaterial(png)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(ox, oy, L.w, L.h)
    end)
    if not ok then return false, tostring(err) end
    local cx, cy = H.ClearPoint(L)
    local mx, my = math.floor(L.w / 2), math.floor(L.h / 2)
    local got = Tx.ReadPic(pic, function(read)
        local _, _, _, a1 = read(1, 1)
        local r2, g2, b2, a2 = read(cx, cy)
        local r3, g3, b3, a3 = read(mx, my)
        if r2 == nil or r3 == nil then return nil end
        return { a = a1, clear = { r2, g2, b2, a2 or 255 }, clearAt = { cx, cy }, ink = { mx, my, r3, g3, b3, a3 or 255 } }
    end)
    if not got then return false, "not readable here (render.ReadPixel gave nothing): only a picture that read back right is drawn" end
    local own = png.GetColor and png:GetColor(0, 0)
    job.info = string.format("your own %s (a corner's alpha %s, %s in the file)", tostring(H.Base(job.path)), tostring(got.a), tostring(own and own.a))
    return true, got
end

-- what a page's material samples, on the CPU (IMaterial:GetTexture): "<name> <w> x <h>" or why it cannot; nil: this engine cannot tell
local function binding_of(page)
    local mat = page and page.mat
    if not mat then return "no material" end
    if mat.IsError and mat:IsError() then return "an error material" end
    if not mat.GetTexture then return nil end
    local tex = mat:GetTexture("$basetexture")
    if not tex then return "no $basetexture" end
    if tex.IsError and tex:IsError() then return "the error texture" end
    return string.format("%s %s x %s", string.lower(tostring(tex.GetName and tex:GetName())), tostring(tex.Width and tex:Width()), tostring(tex.Height and tex:Height()))
end
local function binding_want(page)
    return string.format("%s %d x %d", string.lower(tostring(page.rt and page.rt.GetName and page.rt:GetName())), page.rw or page.w, page.rh or page.h)
end
H.BindingOf = binding_of

-- b1a2-fix2: the two texels the self-check reads again, and the page's canary, read at the make THE WAY THE CHECK READS THEM (cl_text.lua T.ReadTexels: drawn through the page's own material into
-- the small target), right after the page's own read in the same frame. -> the reference { clear, ink, canary }, or nil and why it is not drawn: not readable that way, or the copy's alpha (which
-- no colour space touches) not the page's: what the material samples is not the picture
local function reference(Tx, pic, got, how)
    local page = pic.page
    local ca, ia = got.clearAt, { got.ink[1], got.ink[2] }
    local rd, err = Tx.ReadTexels({ { page = page, x = pic.x + ca[1], y = pic.y + ca[2] }, { page = page, x = pic.x + ia[1], y = pic.y + ia[2] }, { page = page, x = 1, y = page.h - 1 } })
    if not rd then return nil, "not readable through its page's material (" .. tostring(err or "render.ReadPixel gave nothing") .. "): only a picture that read back right is drawn" end
    local pc, pi = got.clear, { got.ink[3], got.ink[4], got.ink[5], got.ink[6] }
    local tol = H.CHECK_TOL
    if (how ~= "load" and rd[1][4] > 1) or math.abs(rd[1][4] - (pc[4] or 255)) > tol or math.abs(rd[2][4] - (pi[4] or 255)) > tol then
        return nil, string.format("drawn through its page's material it reads %s at its clear texel and %s at its ink texel, the page itself %s and %s: it would not draw as it was made",
            H.RGBA(rd[1]), H.RGBA(rd[2]), H.RGBA(pc), H.RGBA(pi))
    end
    return { clear = rd[1], ink = rd[2], canary = rd[3], pclear = pc, pink = pi }
end

local function same4(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4] end

-- a made picture done: what it read at the make is kept (the self-check compares with it), and it may be drawn
local function finish(Tx, job, e, t)
    local got, L, pic, which = job.got, job.L, job.pic, job.which
    if job.how ~= "load" then
        local bad = verdict(got, which, L)
        if bad then return false, bad end
    end
    local ref, rbad = reference(Tx, pic, got, job.how)
    if not ref then return false, rbad end
    local page = pic.page
    if page.canary0 == nil and Tx.NoteCanary then Tx.NoteCanary(page, ref.canary) end        -- (the page's make read nothing: this read is the reference, by cl_text.lua's rule)
    local s = record(job.id, which)
    s.pic, s.how, s.path, s.L, s.bad = pic, job.how, job.path, L, nil
    s.made = { clear = ref.clear, clearAt = got.clearAt, ink = ref.ink, inkAt = { got.ink[1], got.ink[2] }, clear_alpha_only = job.how ~= "load", pclear = ref.pclear, pink = ref.pink }
    s.first, s.last, s.used, s.shown, s.next, s.kept, s.drawn = nil, nil, nil, nil, nil, false, false
    -- what the page's material samples at the make: the self-check compares with it (one line if it is not the page's own target here)
    if page.bind0 == nil then
        page.bind0 = binding_of(page) or false
        if page.bind0 and page.bind0 ~= binding_want(page) and not H.said["bind_" .. tostring(page.index)] then
            H.said["bind_" .. tostring(page.index)] = true
            log("skin pictures check: text page %d's material samples \"%s\" (its target is \"%s\"): compared with what it samples now from then on", page.index or 0, tostring(page.bind0), binding_want(page))
        end
    end
    t[which] = pic
    if job.how == "load" then H.stats.loaded = H.stats.loaded + 1 else H.stats.made = H.stats.made + 1 end
    local info = job.info
    if job.how ~= "load" then
        local fname = job.fkey and Tx.FONTS[job.fkey] and Tx.FONTS[job.fkey].title or ("today's " .. tostring(job.font))
        info = string.format("\"%s\" in %s, letters in rows %d..%d (the game's own: %d..%d), columns %s..%s%s; a clear corner's alpha %d", job.text, fname, got.top, got.bot, L.rows[1], L.rows[2],
            tostring(got.left), tostring(got.right), job.note or "", got.corner or -1)
    end
    local asis = same4(ref.clear, ref.pclear) and same4(ref.ink, ref.pink)
    log("%s's %s in the text pictures' atlas: page %d, %d x %d at %d,%d (%d x the game's), %d paint%s and read%s in %d frame%s: %s; checked by its texels at %d,%d (%s) and %d,%d (%s), read through the page's material%s",
        title(e), what(which), page.index or 0, L.w, L.h, pic.x, pic.y, L.s, job.paints or 1, (job.paints or 1) > 1 and "s" or "", (job.paints or 1) > 1 and "s" or "", job.paints or 1,
        (job.paints or 1) > 1 and "s" or "", tostring(info), s.made.clearAt[1], s.made.clearAt[2], H.RGBA(s.made.clear), s.made.inkAt[1], s.made.inkAt[2], H.RGBA(s.made.ink),
        asis and " as the page holds them" or string.format(" (the page itself holds %s and %s)", H.RGBA(ref.pclear), H.RGBA(ref.pink)))
    if Tx.check and Tx.check.state == nil then
        job.step = "atlas"
        return "more"
    end
    return "done"
end

-- one step of a job (one paint and its read at most): "more" (next frame), "done", "drop", or false and why it failed
local function step(job)
    local e = K and K.SKINS and K.SKINS[job.id]
    local t = H.mats[job.id]
    if not (e and t) then return "drop" end
    local Tx = GSA1.Text
    if not (Tx and Tx.Place and Tx.PaintPic and Tx.ReadPic and Tx.PicValid and Tx.ReadTexels) then return false, "feat/cl_text.lua is not there" end
    if Tx.check and Tx.check.state == "bad" then return false, "the text pictures' alpha check read NOT OK: " .. tostring(Tx.check.why) end
    if job.step ~= "first" and not Tx.PicValid(job.pic) then
        job.step, job.pic, job.paints = "first", nil, 0        -- (its page was emptied for room meanwhile: from the start, next frame)
        return "more"
    end
    if job.step == "atlas" then
        -- the text pictures' first read-back after a start or a reset (T.AlphaCheck, on this picture when no text was made before it): T.Handing obeys it
        if Tx.check.state == nil and Tx.AlphaCheck then Tx.AlphaCheck(job.pic) end
        return "done"
    end
    if job.step == "first" then
        local bw, bh = Tx.PageBound()
        local s = H.AtlasScale(ScrW and ScrW(), ScrH and ScrH(), bw, Tx.MaxPicH(bh))
        local L = H.Layout(job.which, s)
        local pic, why = Tx.Place(L.w, L.h, H.MARGIN * s)
        if not pic then return false, why end
        job.L, job.pic, job.paints = L, pic, 1
        if job.how == "load" then
            local ok, got = paint_file(Tx, job)
            if not ok then return false, got end
            job.got = got
            return finish(Tx, job, e, t)
        end
        local which = job.which
        local text = H.TextOf(e, which)
        local element = which == "name" and "skin_name" or "skin_plate"
        local fkey = Tx.Pick(element)
        local mt = (fkey and H.METRICS[fkey]) or H.METRICS_DEFAULT
        local size = math.min(H.MAX_FONT, math.max(8, math.ceil(L.cap / mt.cap)))
        local font = Tx.FontFor(element, size)
        surface.SetFont(font)
        local _, th = surface.GetTextSize("H")
        th = tonumber(th) or size
        local per, adv = Tx.Layout(text, font, 0, L.space, 1)
        local color = BLACK
        if which == "name" then
            local r, g, b = K.ColorOf(e)
            color = { r = r or 255, g = g or 255, b = b or 255, a = 255 }
        end
        job.text, job.font, job.fkey, job.th, job.adv, job.n, job.color, job.ol, job.note = text, font, fkey, th, adv, #per, color, L.outline or 0, ""
        job.fit = fit_of(L, th, adv, #per, mt)
        local ok, got = paint_read(Tx, job)
        if not ok then return false, got end
        job.got = got
        local f2 = correction(job, got)
        if f2 then
            job.fit, job.step = f2, "correct"
            return "more"
        end
        local f3 = widthfit(job, got)
        if f3 then
            job.fit, job.step = f3, "fit"
            return "more"
        end
        return finish(Tx, job, e, t)
    end
    local before = job.got
    job.paints = (job.paints or 1) + 1
    local ok, got = paint_read(Tx, job)
    if not ok then return false, got end
    job.got = got
    if job.step == "correct" then
        job.note = job.note .. string.format("; corrected once from rows %d..%d", before.top, before.bot)
        local f3 = widthfit(job, got)
        if f3 then
            job.fit, job.step = f3, "fit"
            return "more"
        end
    else
        job.note = job.note .. string.format("; fitted once to the game's width from columns %d..%d", before.left, before.right)
    end
    return finish(Tx, job, e, t)
end

-- one step of the make (PostRender, one a frame: the job's paint and its read)
function H.Step()
    local job = H.job
    if not job then
        job = table.remove(H.queue, 1)
        if not job then return end
        job.step = "first"
        H.job = job
    end
    H.makeFrame = FrameNumber()
    local res, err = step(job)
    if res == "more" then return end
    H.job = nil
    if res == "done" or res == "drop" then return end
    H.stats.failed = H.stats.failed + 1
    local e = K and K.SKINS and K.SKINS[job.id]
    local t = H.mats[job.id]
    if t then t[job.which] = false end
    local s = H.state[job.id] and H.state[job.id][job.which]
    local again = s and (s.remakes or 0) > 0
    if s and again then s.off = "its remake failed" end
    log("%s's %s picture could not be made (%s): the game's own stays%s", title(e), job.which, tostring(err), again and " for the rest of this session" or "")
end

-- THE SELF-CHECK AND THE FALLBACK -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- (on a change only) the control: one texel of the game's own texture the picture is drawn in place of (cl_textures.lua's render target of m_<name> / B_<name>_e), against the module's: "right" tells a
-- change of the skin's picture alone from every render target's
local function control(s)
    local g = s.game
    local X = GSA1.Tex
    local Tx = GSA1.Text
    if not (g and g.archive and X and X.entries and Tx and Tx.ReadBack) then return "the game's own texture not read" end
    local e = nil
    for _, v in pairs(X.entries) do
        if v and v.done and v.rt and v.kind == g.kind and v.archive == g.archive and v.index == g.tex and not v.gold and not v.mask then
            e = v
            break
        end
    end
    local info = e and e.info
    if not (info and info.runs) then return string.format("the game's own %s texture not found", tostring(g.name)) end
    -- (its first opaque texel that is not black, so a black target does not read "right"; else its first opaque one)
    local px, py, want = nil, nil, nil
    for pass = 1, 2 do
        for r = 1, tonumber(info.nruns) or 0 do
            local o = (r - 1) * 10 + 1
            local x0, x1, y0, y1, _, _, cr, cg, cb, ca = string.byte(info.runs, o, o + 9)
            if ca == 255 and (pass == 2 or math.max(cr, cg, cb) >= 40) then
                px, py, want = x0 + x1 * 256, y0 + y1 * 256, { cr, cg, cb, ca }
                break
            end
        end
        if px then break end
    end
    if not px then return string.format("the game's own %s texture has no opaque texel to read", tostring(g.name)) end
    local got = Tx.ReadBack(e, function(read)
        local r, gg, b, a = read(px, py)
        if r == nil then return nil end
        return { r, gg, b, a or 255 }
    end)
    if not got then return string.format("the game's own %s texture not readable", tostring(g.name)) end
    local d = math.max(math.abs(got[1] - want[1]), math.abs(got[2] - want[2]), math.abs(got[3] - want[3]), math.abs(got[4] - want[4]))
    return string.format("the game's own %s texture reads %s at %d,%d, the module %s: %s", tostring(g.name), H.RGBA(got), px, py, H.RGBA(want), d <= H.CHECK_TOL and "right" or "changed too")
end

local function slow_line(now)
    local t = H.check.slow
    if not t then return "no frame of 50 ms or more before it" end
    return string.format("the last frame of 50 ms or more %.1f s before", math.max(0, now - t))
end

-- a picture that read changed or not at all: never drawn again (the game's own is), one line why, made again once a session (a second time: the game's own for the rest of the session)
local function fallback(it, changed, details, now)
    local id, which, s = it.id, it.which, it.s
    local t = H.mats[id]
    if t then t[which] = false end
    s.pic, s.bad = nil, details
    s.changes = (s.changes or 0) + 1
    H.stats.changed = H.stats.changed + 1
    local e = K and K.SKINS and K.SKINS[id]
    local since = s.first and (now - s.first) or 0
    local tail
    if (s.remakes or 0) < 1 and not s.off then
        s.remakes = (s.remakes or 0) + 1
        H.stats.remade = H.stats.remade + 1
        queue(id, which, s.path, s.how)
        tail = string.format("the game's own %s is drawn from now on; made again once", what(which))
    else
        s.off = details
        tail = string.format("the game's own %s is drawn for the rest of this session", what(which))
    end
    log("skin pictures check: %s's %s %s %.1f s after its first draw (%s): %s. Please report this line", title(e), what(which), changed and "CHANGED" or "NOT READABLE", since, details, tail)
end

-- the page of the shown picture (drawn in one of the last H.SHOWN_FRAMES frames) whose check is due first, or nil (every frame: nothing made)
local function due_page(fr, now)
    local best, soonest = nil, nil
    for id, st in pairs(H.state) do
        local t = H.mats[id]
        for i = 1, 2 do
            local which = WHICH[i]
            local s = st[which]
            local pic = s and s.pic
            if pic and t and t[which] == pic and s.used and s.used >= fr - H.SHOWN_FRAMES and s.next and now >= s.next - H.EPS and GSA1.Text.PicValid(pic) then
                if not soonest or s.next < soonest then best, soonest = pic.page, s.next end
            end
        end
    end
    return best
end

-- the shown pictures of page `best`; -> list
local function shown_on(fr, best)
    local list = {}
    for id, st in pairs(H.state) do
        local t = H.mats[id]
        for _, which in ipairs(WHICH) do
            local s = st[which]
            local pic = s and s.pic
            if pic and pic.page == best and t and t[which] == pic and s.used and s.used >= fr - H.SHOWN_FRAMES and GSA1.Text.PicValid(pic) then list[#list + 1] = { id = id, which = which, s = s, pic = pic } end
        end
    end
    table.sort(list, function(a, b) return a.id .. a.which < b.id .. b.which end)
    return list
end

-- one check (PostRender, in a frame where no make step ran, with the window's focus): at most one read each H.check.period, of one page's shown pictures (b1a2-fix2: their texels and the page's
-- canary through cl_text.lua T.ReadTexels, the small target, not a capture of the page); one line the first time a picture reads right H.CHECK_KEPT s or more after its first draw, one line whenever
-- one reads changed or cannot be read (the fallback), one line about the session's first read and what it cost
function H.SelfCheck()
    local C = H.check
    local Tx = GSA1.Text
    if not (Tx and Tx.ReadTexels and Tx.PicValid) then return end
    if system and system.HasFocus and not system.HasFocus() then return end
    local now, fr = RealTime(), FrameNumber()
    -- (the window away, or no frame for a second, less than a second ago: cl_text.lua's own canary read comes first, so a device reset is made again as one, not taken for a change)
    if C.away and now - C.away < 1 then return end
    if C.last and now - C.last < (C.period or H.CHECK_PERIOD) - H.EPS then return end
    local page = due_page(fr, now)
    if not page then return end
    local list = shown_on(fr, page)
    if #list == 0 then return end
    local t0 = SysTime()
    local req = {}
    for _, it in ipairs(list) do
        local pic, made = it.pic, it.s.made
        req[#req + 1] = { page = page, x = pic.x + made.clearAt[1], y = pic.y + made.clearAt[2] }
        req[#req + 1] = { page = page, x = pic.x + made.inkAt[1], y = pic.y + made.inkAt[2] }
    end
    req[#req + 1] = { page = page, x = 1, y = page.h - 1 }
    local got, err = Tx.ReadTexels(req)
    local res = nil
    if got then
        res = { canary = got[#req] }
        for i = 1, #list do res[i] = { clear = got[2 * i - 1], ink = got[2 * i] } end
    end
    local dt = SysTime() - t0
    local ms = dt * 1000
    C.last, C.reads = now, (C.reads or 0) + 1
    C.lastMs = ms
    H.stats.reads = H.stats.reads + 1
    if GSA1.HitchAdd then GSA1.HitchAdd("Skin pictures check", dt) end
    for _, it in ipairs(list) do it.s.next = now + (C.period or H.CHECK_PERIOD) end
    local rd = Tx.Reader and Tx.Reader()
    local how = string.format("%d texels drawn through its material into the %d x %d target", #req, rd and rd.w or 0, rd and rd.h or 0)
    if not H.said.first_read then
        H.said.first_read = true
        log("skin pictures check: the first read: %s %s and read there (%d bytes, where a capture of the whole page is %d MiB), %s: the read took %.1f ms",
            how, rd and rd.name or "?", (rd and rd.w or 0) * (rd and rd.h or 0) * 4, math.floor((page.rw or page.w) * (page.rh or page.h) * 4 / 1048576 + 0.5), res and "readable" or "NOT readable", ms)
    end
    -- what the page's material samples now, against the make (CPU)
    local bind = binding_of(page)
    local bindBad = nil
    if page.bind0 and bind ~= page.bind0 then bindBad = string.format("its material now samples \"%s\", at the make \"%s\"", tostring(bind), tostring(page.bind0)) end
    if not res then
        local why = string.format("text page %d: %s", page.index or 0, tostring(err or "render.ReadPixel gave nothing"))
        for _, it in ipairs(list) do fallback(it, false, why, now) end
        return
    end
    -- the canary against what the same read gave at the page's make (cl_text.lua p.canary0); the painted colour only as a line here, and as the reference for a page whose make read nothing
    local painted = Tx.CanaryPainted and Tx.CanaryPainted() or { Tx.CANARY_RGB[1], Tx.CANARY_RGB[2], Tx.CANARY_RGB[3], 0 }
    local made0 = page.canary0 or painted
    local canaryBad = H.CanaryVerdict(res.canary, made0)
    local ctl = nil
    local lost = false
    for i, it in ipairs(list) do
        local s = it.s
        local why = H.CheckVerdict(s.made, res[i])
        if why or canaryBad or bindBad then
            ctl = ctl or control(s)
            local parts = { why or string.format("clear %s, ink %s as made", H.RGBA(res[i].clear), H.RGBA(res[i].ink)) }
            parts[#parts + 1] = string.format("page %d's canary %s%s", page.index or 0, H.RGBA(res.canary), canaryBad and string.format(" (at the make %s, painted %s)", H.RGBA(made0), H.RGBA(painted)) or " as at the make")
            parts[#parts + 1] = bindBad or "binding ok"
            parts[#parts + 1] = ctl
            parts[#parts + 1] = slow_line(now)
            fallback(it, true, table.concat(parts, "; "), now)
            lost = true
        elseif not s.kept and s.first and now - s.first >= H.CHECK_KEPT - H.EPS then
            s.kept = true
            H.stats.kept = H.stats.kept + 1
            local e = K and K.SKINS and K.SKINS[it.id]
            local clear = s.made.clear_alpha_only and string.format("clear alpha %d", res[i].clear[4]) or string.format("clear %s as made", H.RGBA(res[i].clear))
            local binding = bind == nil and "its material not checkable here" or bind == binding_want(page) and string.format("its material on page %d's %d x %d target", page.index or 0, page.rw or page.w, page.rh or page.h)
                or string.format("its material samples \"%s\" as at the make", tostring(bind))
            log("skin pictures check: %s's %s read right %.1f s after its first draw (%s; ink %s as made; page %d's canary %s as at the make, painted %s; %s; %s, the read took %.1f ms): read again once %s while shown, a line only if it changes",
                title(e), what(it.which), now - s.first, clear, H.RGBA(res[i].ink), page.index or 0, H.RGBA(res.canary), H.RGBA(painted), binding, how, ms,
                (C.period or H.CHECK_PERIOD) <= 1 and "a second" or string.format("every %d s", C.period))
        end
    end
    -- the page's canary itself changed: its target was lost (a device reset); every text picture is made again when next shown (cl_text.lua's own line)
    if canaryBad and Tx.LoseAll then Tx.LoseAll(string.format("the render targets were lost (device reset): page %d's canary reads %s, at its make %s", page.index or 0, H.RGBA(res.canary), H.RGBA(made0))) end
    -- (only if the small read itself is slow: the checks every H.CHECK_PERIOD_SLOW s, said once)
    if not lost and ms >= H.CHECK_SLOW_MS and (C.period or H.CHECK_PERIOD) < H.CHECK_PERIOD_SLOW then
        C.period = H.CHECK_PERIOD_SLOW
        log("skin pictures check: one read of text page %d (%s) took %.1f ms: read every %d s from now on (a hitch each second otherwise)", page.index or 0, how, ms, C.period)
    end
end

hook.Add("PostRender", "gsa1_skinhud", function()
    local C, now = H.check, RealTime()
    local ft = RealFrameTime and RealFrameTime()
    if ft and ft >= 0.05 then C.slow = now end
    local focus = not (system and system.HasFocus) or system.HasFocus()
    if not focus or (C.frameT and now - C.frameT > 1) then C.away = now end
    C.frameT = now
    if H.job or #H.queue > 0 then
        local ok, err = pcall(H.Step)
        if not ok then
            local job = H.job
            H.job = nil
            H.stats.failed = H.stats.failed + 1
            if job and H.mats[job.id] then H.mats[job.id][job.which] = false end
            log("a skin's picture: %s: the game's own stays", tostring(err))
        end
        return
    end
    local ok, err = pcall(H.SelfCheck)
    if not ok then
        -- (a fault of the check itself: nothing is drawn that is not checked; the game's own names and plates from now on)
        for _, t in pairs(H.mats) do
            for _, which in ipairs(WHICH) do t[which] = false end
        end
        if not H.said.check_error then
            H.said.check_error = true
            log("skin pictures check: %s: the game's own names and plates are drawn from now on. Please report this line", tostring(err))
        end
    end
end)

-- "Make the skins' name pictures again" (the Text page): every skin's pictures made again (and checked again from the start); of the files, only the ones each hud/generated.txt lists as G-SA1's go
-- (the owner's own pictures stay)
function H.Remake()
    local n = 0
    H.job = nil
    H.check.last = nil
    for _, id in ipairs(K and K.ORDER or {}) do
        local e = K.SKINS[id]
        local P = e and H.Paths(e)
        if P then
            local set = H.ParseGenerated(file.Read(P.list, "DATA"))
            local tl = file.Time and file.Time(P.list, "DATA") or 0
            for name in pairs(set) do
                local path = P.dir .. "/" .. name
                if file.Exists(path, "DATA") and H.IsMade(set, name, file.Time and file.Time(path, "DATA") or 0, tl) then
                    file.Delete(path)
                    n = n + 1
                end
            end
            if next(set) then file.Write(P.list, H.FormatGenerated({})) end
            H.mats[id], H.state[id] = nil, nil
            H.said["old_" .. id] = true
            H.Want(e)
        end
    end
    H.stats.deleted = H.stats.deleted + n
    log("the skins' pictures: made again one step a frame (%d old made files deleted)", n)
    return n
end
if concommand and concommand.Add then
    concommand.Add("gsa1_skins_hud_remake", function() H.Remake() end, nil, "G-SA1: make the skins' name and nameplate pictures again (yours stay)")
end