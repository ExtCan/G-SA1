-- G-SA1 feature "objects", client: the SPAWN-MENU PICTURES of the real objects and the G-SA1 tab's icon (round 0.9.4b;
-- sadc docs/research/objects2_plan.md 6.3 task 4 with its Review R.5 / R.7 / R.19, 11.0 (O4 / O5), 11.2; objects2_view.md
-- 5.4).
--
-- The owner on 0.9.4: "the menu icons should be rendered instead of SVG graphics", and on 0.9.4a: "the spawn tab icon is
-- HUGE ... The icon for the tab should be Sonic's 1-up icon."
--   * WHAT: one picture per class - Ring; Ring line and Ring circle with the class's default count and spacing / radius
--     (the ring at each place of gsa1.PreviewRingPlaces: the same drawing as the pictures on the map, review R.5); Item Box
--     and Item Box (Air) with the Objects page's contents (gsa1_set_box_content) - of the pictures' kind (feat/cl_objview.lua
--     V.KindNow), each from a settled copy whose textures are painted. An Extra Life box always wears the Dreamcast logo
--     here (owner answer O4: no character's world draws a spawn-menu picture).
--   * HOW (after the disc is ready, once the spawn menu has made its first G-SA1 icon; one class a frame in PostRender):
--     a 256 x 256 render target of cl_textures.lua's probed format (T.format: BGRA8888 keeps alpha on the owner's setups)
--     with its own depth (MATERIAL_RT_DEPTH_SEPARATE: a depth clear without a depth buffer clears nothing in D3D9), cleared
--     transparent; cam.Start3D framed from the copies' bounds (a three-quarter view from slightly above, distance =
--     radius / sin(fov / 2)); fixed lighting from above; tone-mapping scale 1 and fog off (both restored); the blended
--     batches with a separate alpha blend (ONE / ONE_MINUS_SRC_ALPHA on alpha: cl_textures.lua's fix 2c); then THE
--     READ-BACK CHECK (review R.7): render.CapturePixels / render.ReadPixel - the coverage check (THE CHECK, 0.9.4d,
--     below) - and only a passing render target replaces the drawn icon (where ReadPixel gives no alpha, only the PNG
--     check below can pass it).
--   * SHOWN at once: a material per class (UnlitGeneric, $basetexture = the render target, $translucent, $vertexalpha,
--     $vertexcolor); feat/cl_objects.lua's content type gsa1_object hands every icon it makes to I.Decorate (a weak list),
--     so a picture made later replaces the drawn one in place - in the G-SA1 tab and in Entities > G-SA1.
--   * KEPT (gsa1_set_icons_save 1; owner answer O5): render.Capture{format = "png", alpha = true} inside the same push,
--     written ONLY under garrysmod/data/gsa1/icons as gsa1_obj_<class>[_c<contents>]_<key>[_r<n>].png, then checked through
--     Material("../data/gsa1/icons/<file>") (not an error material; IMaterial:GetColor: the four corners transparent; 0.9.4f:
--     its coverage scanned only where ReadPixel gives no alpha, else a PNG is written only from a passing render target):
--     only a passing file goes into gsa1/icons/index.json {format = 1, key, made, files}, a failing one is deleted
--     with one log line. Next session, before the disc is ready (and without it: they are the owner's own files, review
--     R.19), a key that matches index.json gives the icons their PNG material at once - each only if its file exists and
--     its Material is not an error material.
--   * THE KEY: util.CRC of (the module's version, libsa1's version, the default contents, the picture format 1; 0.9.4f: not
--     the character - changing character made every picture again, at 1 fps);
--     a new key renders again and deletes the files the old index.json lists - only those, only under data/gsa1/icons, only
--     names matching ^gsa1_obj_[%w_]+%.png$ (index.json is a file anyone can edit). "Redraw the spawn-menu pictures" (the
--     Objects page) and the console command gsa1_icons_rebuild draw them again (new names: Source caches a material by its
--     path). Render targets lose their contents on a device reset (cl_textures.lua: the focus regained, a screen size
--     change): a render-target picture then switches to its PNG, or is drawn again.
--   * THE TAB'S ICON (11.2): Sonic's 1-up icon - the texture his Extra Life panel and his HUD's 1-up item icon use (kind 0,
--     archive 2, texture 31: libsa1's measurement, checked by feat_preview_binding_test) - drawn from the owner's disc into a
--     16 x 16 render target (the same checks and PNG rules: gsa1_obj_tab_<key>.png) and given to feat/cl_spawntab.lua
--     T.SetIcon; until then a 16 x 16 silkicon (never the 128-pixel picture: the tab sizes itself to its icon).
--   * gsa1_set_icons 0, no module or no disc: G-SA1's drawn pictures (materials/entities/gsa1_obj_*.png), nothing rendered
--     or written.
-- UNVERIFIED in game: render.Capture's PNG alpha, Material("../data/...") of a fresh PNG, IMaterial:GetColor on it, the
-- render target's alpha and colour on the owner's DXVK setup, the spawn menu's ContentIcon.Image:SetMaterial.
--
-- 0.9.4d (the owner on 0.9.4b: "the ring icons in the G-SA1 tab aren't very good, the circle of rings doesn't even have a
-- rendered icon"; his saved pictures: the ring pale, the circle seven tiny rings, the line not saved at all):
--   * THE COLOUR. The pale ring's pixels were the game's own dark gold (R = G, B = 0: the texture ring_ref_a) but their
--     ALPHA was 64-127 - Source writes the view depth into the destination alpha of opaque draws (the depth beyond the near
--     plane over 192 units: the boxes, farther away, got 160-223, the circle seen from far 255) - so the spawn menu showed a
--     half-transparent ring over its light background. Now render.SetWriteDepthToDestAlpha(false) while a picture is drawn,
--     and in case that is not honoured the eye stays I.NEAR_MIN from every corner with the near plane I.NEAR in front of it,
--     so every opaque pixel is opaque either way. Materials and colour rules are the world draw's (cl_textures.lua
--     T.Material of the pictures' kind for the same batches, sphere maps facing the picture's camera), lit like the world
--     draw (GSA1.ApplyLightCube: an ambient cube and NO local lights - 0.9.4b left the last model's lights set) by a fixed
--     neutral studio cube (I.STUDIO: white, the same on every side but brighter above); tone-mapping scale 1, fog off,
--     colour modulation and blend 1 (each restored).
--   * THE FRAMING per class (I.VIEWS, I.Fit: the bounds' corners fill I.FILL = 85 % of the picture, centred).
--   * THE CHECK: coverage over the whole picture (I.Coverage: every I.COVER_STEP-th pixel of every I.COVER_STEP-th row,
--     render.ReadPixel of the render target; 0.9.4f: the PNG is saved only from a render target that passed, its four
--     corners checked - or, where ReadPixel gives no alpha, scanned on its own at I.PNG_STEP): at least I.COVER_MIN of it
--     opaque and at least I.CLEAR_MIN fully transparent (the clear worked). 0.9.4b's 7 x 7 sample grid missed thin rings
--     (the circle and the line were refused although they were drawn).
--   * THE KEY carries I.PICTURES (2): the 0.9.4b / 0.9.4c pictures are made again, and the files of an index.json of
--     another key are deleted also at the first key of a session (0.9.4b deleted them only when the key changed while
--     running, so an update left the old files behind).
GSA1 = GSA1 or {}
local O = GSA1.Objects
if not O then return end
local I = GSA1.ObjIcons or {}
GSA1.ObjIcons = I
local cv = O.cv
local bor = bit.bor

I.SIZE, I.TAB_SIZE, I.FORMAT = 256, 16, 1        -- (I.FORMAT: index.json's layout)
I.PICTURES = 2              -- the pictures' own version, part of the key (2: 0.9.4d's colour, framing and check)
I.DIR = "gsa1/icons"
I.INDEX = "gsa1/icons/index.json"
I.PATTERN = "^gsa1_obj_[%w_]+%.png$"
I.TAB_KIND, I.TAB_ARCHIVE, I.TAB_TEX = 0, 2, 31
I.WAIT_MAX = 20             -- s: a class whose copy, textures or logo are not ready this long keeps its drawn picture
I.RING_R = 12.3             -- HU: a ring's half size (libsa1's bounds: 3.06 SA1 units)
-- THE CAMERA PER CLASS (0.9.4d). Every picture: the bounds' corners inside I.FILL of the picture's half width and height,
-- the picture centred on them (I.Fit); the field of view below, narrowed where the eye has to stay I.NEAR_MIN from the
-- nearest corner (the single ring then sees it nearly orthographic, about 7 degrees; a box about 24).
--   * Ring: a three-quarter view - 15 degrees from above, looking along +x - taken in the pair when the spinning ring
--     shows I.FACE (72-90 %) of its height as width (turned about 45-65 degrees from edge-on: I.RingAspect).
--   * Ring line: I.LINE - 5 rings at the class's default spacing (40 HU) as the game's layout places them
--     (gsa1.PreviewRingPlaces), the row turned 35 degrees from the view: a diagonal row of large rings, 25 degrees from
--     above; the same three-quarter moment of the rings' turn.
--   * Ring circle: I.CIRCLE - the default circle of 7, at a radius of 48 HU (the class's default 80 leaves the rings small
--     in the picture), seen 40 degrees from above so it reads as a circle; the same moment.
--   * Item Box, Item Box (Air): as 0.9.4b - 22 degrees from above, from the front-left (yaw 225), 30 degrees.
--   The rings look along the x axis (yaw 0): their bounds tell the ring's turn only up to a mirror image about the x
--   axis, and a view along x - with I.STUDIO the same on both sides - looks the same either way.
I.FILL = 0.85
I.FACE = { 0.72, 0.90 }     -- the ring's width / height (bounds y extent / z extent) for a three-quarter view
I.FACE_WAIT = 4             -- s: a ring that never shows that moment is drawn as it is
I.VIEWS = {
    gsa1_obj_ring = { ang = Angle(15, 0, 0), fov = 20 },
    gsa1_obj_ring_line = { ang = Angle(25, 0, 0), fov = 30 },
    gsa1_obj_ring_circle = { ang = Angle(40, 0, 0), fov = 30 },
}
I.FOV = 30
I.VIEW = Angle(22, 225, 0)  -- the boxes: looking down 22 degrees from the front-left-above corner (a three-quarter view)
I.LINE = { count = 5, size = 40, shape = 0, yaw = 35 }    -- size: the class's default spacing (feat/sh_objects.lua)
I.CIRCLE = { count = 7, size = 48, shape = 1, yaw = 0 }   -- the class's default count; radius 48 (its default: 80)
-- THE COLOUR (0.9.4d, above). Source's depth in the destination alpha reaches 1 at 192 units beyond the near plane
-- (measured from the owner's 0.9.4b pictures: ring alpha 64-127 at 40-80 HU beyond it, boxes 160-223, the far circle 255)
I.DESTALPHA_RANGE = 192
I.NEAR = 2                  -- HU: the near plane in front of the eye
I.NEAR_MIN = I.DESTALPHA_RANGE + I.NEAR + 8   -- HU from the eye to the nearest corner at least
-- the studio light: an ambient cube (BOX_FRONT +x, BOX_BACK -x, BOX_RIGHT -y, BOX_LEFT +y, BOX_TOP, BOX_BOTTOM), white
I.STUDIO = { [0] = Vector(0.9, 0.9, 0.9), [1] = Vector(0.9, 0.9, 0.9), [2] = Vector(0.9, 0.9, 0.9),
             [3] = Vector(0.9, 0.9, 0.9), [4] = Vector(1, 1, 1), [5] = Vector(0.6, 0.6, 0.6) }
-- THE CHECK (0.9.4d)
I.COVER_STEP = 8            -- every 8th pixel of every 8th row (1,024 of a 256 x 256 picture). 0.9.4f hot fix: 0.9.4d's
                            -- step 2 (16,384 reads) plus the same scan of the saved PNG made each picture take 17-27 s
                            -- at 1 fps (owner log 2026-10-27 20:54-20:58), and every character change made them all again
-- the saved PNG: written only from a render target that passed (its four corners checked), or scanned on its own at
-- I.PNG_STEP where render.ReadPixel gives no alpha
I.COVER_ALPHA = 128         -- a pixel counts as opaque from this alpha
I.PNG_STEP = 16             -- 0.9.4f: the PNG's own scan (only where render.ReadPixel gives no alpha): 256 reads
I.COVER_MIN = 0.02          -- at least 2 % of the picture opaque
I.CLEAR_MIN = 0.10          -- and at least 10 % of it fully transparent (else the clear failed)

I.icons = I.icons or setmetatable({}, { __mode = "k" })    -- [ContentIcon] = its class (weak: the menu may drop them)
I.pics = I.pics or {}       -- [class] = { mat, from = "rt" | "png", file, rt }
I.queue = I.queue or {}
I.stats = I.stats or { made = 0, saved = 0, rt_failed = 0, png_failed = 0, deleted = 0, waited = 0 }
I.gen = I.gen or 0          -- the redraws of this session (part of the new files' names)

local B_ONE, B_ZERO = BLEND_ONE or 1, BLEND_ZERO or 0
local F_ADD = BLENDFUNC_ADD or 0
local WRAP_CLAMP = 1 + 2

local function now_s() return SysTime() end
local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("icons", fmt, ...) end
end

-- the classes in their order and the tab's icon
function I.Classes()
    local out = {}
    for _, c in ipairs(O.CLASSES) do out[#out + 1] = c.class end
    return out
end

local function contents()
    return math.Clamp(cv.box_content and cv.box_content:GetInt() or O.DEFAULT_CONTENTS, 0, 8)
end

function I.Enabled()
    return cv.icons ~= nil and cv.icons:GetBool()
end

-- the key of this session's pictures (nil without the module): util.CRC of the module's and libsa1's versions, the default
-- contents, the picture format and I.PICTURES (the kind slot is always 0 since 0.9.4f). 0.9.4d: made again only when one of them changed (0.9.4b built
-- its string and CRC every frame: 160 bytes of Lua garbage a frame, tests/frame_test.lua)
local keyIn = {}
function I.Key()
    local ver = gsa1 and gsa1.VERSION
    if not ver then return nil end
    -- 0.9.4f hot fix: the character is NOT part of the key any more - the spawn-menu pictures always show the Dreamcast logo
    -- on the Extra Life box, so changing character must not make them all again (owner: 1 fps for a minute)
    local kind = 0
    local lib, con = gsa1.LIBSA1_VERSION, contents()
    if keyIn.key and keyIn[1] == ver and keyIn[2] == lib and keyIn[3] == kind and keyIn[4] == con and
       keyIn[5] == I.PICTURES then
        return keyIn.key
    end
    local s = table.concat({ tostring(ver), tostring(lib), tostring(kind), tostring(con), tostring(I.FORMAT),
        tostring(I.PICTURES) }, "|")
    keyIn[1], keyIn[2], keyIn[3], keyIn[4], keyIn[5] = ver, lib, kind, con, I.PICTURES
    keyIn.key = tostring(util.CRC and util.CRC(s) or s)
    return keyIn.key
end

-- the file of a class's picture (a name the deletion pattern accepts)
function I.FileName(class, key)
    local c = O.BY_CLASS[class]
    local part = class == "tab" and "gsa1_obj_tab" or class
    if c and c.contents then part = part .. "_c" .. contents() end
    local name = part .. "_" .. tostring(key):gsub("[^%w]", "") .. (I.gen > 0 and ("_r" .. I.gen) or "") .. ".png"
    return name
end

function I.SafeName(f)
    return type(f) == "string" and string.match(f, I.PATTERN) ~= nil and not string.find(f, "..", 1, true)
end

-- index.json ------------------------------------------------------------------------------------------------------------
-- any: also an index of another format (only to delete the files it lists: I.KeyChanged)
function I.ReadIndex(any)
    if not (file and file.Read) then return nil end
    local s = file.Read(I.INDEX, "DATA")
    if not s or s == "" then return nil end
    local t = util.JSONToTable and util.JSONToTable(s) or nil
    if type(t) ~= "table" or (not any and tonumber(t.format) ~= I.FORMAT) or type(t.files) ~= "table" then return nil end
    return t
end

function I.WriteIndex()
    if not (cv.icons_save and cv.icons_save:GetBool()) or not (file and file.Write and util.TableToJSON) then return end
    local files = {}
    for class, p in pairs(I.pics) do
        if p.file then files[class] = p.file end
    end
    file.CreateDir(I.DIR)
    file.Write(I.INDEX, util.TableToJSON({ format = I.FORMAT, key = I.key, made = os.date and os.date("%Y-%m-%d %H:%M:%S")
        or "", files = files, gen = I.gen }))
end

-- deletes the files an index lists (only under data/gsa1/icons, only names of the pattern), except keep[file]
function I.DeleteListed(index, keep)
    if not (index and type(index.files) == "table" and file and file.Delete) then return 0 end
    local n = 0
    for _, f in pairs(index.files) do
        if I.SafeName(f) and not (keep and keep[f]) and file.Exists(I.DIR .. "/" .. f, "DATA") then
            file.Delete(I.DIR .. "/" .. f)
            n = n + 1
        end
    end
    I.stats.deleted = I.stats.deleted + n
    return n
end

-- 0.9.4d verifier: pictures of OLDER keys that no index lists any more (0.9.4b and 0.9.4c wrote new indexes over the old ones):
-- every pattern-safe picture under data/gsa1/icons whose name does not end in this key's suffix
function I.DeleteOrphans(key)
    if key == nil or not (file and file.Find and file.Delete) then return 0 end
    local found = file.Find(I.DIR .. "/*.png", "DATA") or {}
    local suffix = "_" .. tostring(key) .. ".png"
    local n = 0
    for _, f in ipairs(found) do
        if I.SafeName(f) and string.sub(f, -#suffix) ~= suffix then
            file.Delete(I.DIR .. "/" .. f)
            n = n + 1
        end
    end
    I.stats.deleted = I.stats.deleted + n
    return n
end

-- a PNG's material, if its file exists and the material is not an error material (a deleted file would show the
-- checkerboard: review R.7)
function I.PngMaterial(f)
    if not I.SafeName(f) or not (file and file.Exists and file.Exists(I.DIR .. "/" .. f, "DATA")) then return nil end
    local m = Material("../data/" .. I.DIR .. "/" .. f)
    if not m or (m.IsError and m:IsError()) then return nil end
    return m
end

-- the pictures of a matching index.json at once (before the disc is ready, or without it: review R.19)
function I.LoadIndex(key)
    local idx = I.ReadIndex()
    if not (idx and key and tostring(idx.key) == key) then return false end
    I.gen = math.max(I.gen, tonumber(idx.gen) or 0)
    local n = 0
    for class, f in pairs(idx.files) do
        local m = I.PngMaterial(f)
        if m then
            I.pics[class] = { mat = m, from = "png", file = f }
            n = n + 1
            if class == "tab" then I.ApplyTab(I.pics[class]) else I.ApplyClass(class) end
        end
    end
    if n > 0 then log("%d spawn-menu pictures from garrysmod/data/gsa1/icons (key %s)", n, key) end
    return n > 0
end

-- the icons ---------------------------------------------------------------------------------------------------------------
local function apply(icon, p)
    if not (icon and (not IsValid or IsValid(icon)) and icon.Image) then return false end
    icon.Image:SetMaterial(p.mat)
    return true
end

local function restore(icon, class)
    if not (icon and (not IsValid or IsValid(icon))) then return end
    local name = icon.m_MaterialName or ("entities/" .. tostring(class) .. ".png")
    if icon.SetMaterial then icon:SetMaterial(name) elseif icon.Image then icon.Image:SetImage(name) end
end

function I.ApplyClass(class)
    local p = I.pics[class]
    for icon, c in pairs(I.icons) do
        if c == class then
            if p and I.Enabled() then apply(icon, p) else restore(icon, class) end
        end
    end
end

function I.ApplyTab(p)
    local T = GSA1.SpawnTab
    if not (T and T.SetIcon) or not p then return false end
    if p.from == "png" and p.file then return T.SetIcon("../data/" .. I.DIR .. "/" .. p.file) end
    return T.SetIcon(p.mat)
end

-- an icon the content type gsa1_object made (feat/cl_objects.lua): its picture now or when it is made
function I.Decorate(icon, class)
    if not icon or type(class) ~= "string" or not O.BY_CLASS[class] then return end
    I.icons[icon] = class
    I.wanted = true
    local p = I.pics[class]
    if p and I.Enabled() then apply(icon, p) end
end

-- the jobs ----------------------------------------------------------------------------------------------------------------
function I.QueueAll()
    I.queue = { "tab" }
    for _, c in ipairs(I.Classes()) do I.queue[#I.queue + 1] = c end
    I.job = nil
end

-- a new key: the old files go (those the old index lists), every picture is made again
function I.KeyChanged(key)
    local old = I.key
    I.key = key
    if old ~= nil or not I.LoadIndex(key) then
        if old ~= nil then
            log("the spawn-menu pictures' key changed (%s -> %s): drawn again", tostring(old), tostring(key))
            I.DeleteListed(I.ReadIndex(true))
            for class in pairs(I.pics) do I.pics[class] = nil end
            for _, class in ipairs(I.Classes()) do I.ApplyClass(class) end
        else
            -- 0.9.4d: the session's first key differs from index.json's (an update, another disc or contents): the
            -- files that index lists are another key's and go now (0.9.4b kept them, and wrote its new index over it)
            local idx = I.ReadIndex(true)
            if idx and tostring(idx.key) ~= key then
                local n = I.DeleteListed(idx)
                if n > 0 then
                    log("the spawn-menu pictures of another key (%s): %d file(s) deleted, drawn again", tostring(idx.key), n)
                end
            end
            local o = I.DeleteOrphans(key)
            if o > 0 then log("the spawn-menu pictures of older keys no index lists: %d file(s) deleted", o) end
        end
        I.QueueAll()
    else
        -- the PNGs of this key are there: only what is missing is made
        I.queue = {}
        if not I.pics.tab then I.queue[#I.queue + 1] = "tab" end
        for _, c in ipairs(I.Classes()) do
            if not I.pics[c] then I.queue[#I.queue + 1] = c end
        end
    end
end

-- the copies a class's picture draws: { {D, pos}, ... } and their bounds (HU), or nil while one is not ready
local ORIGIN = Vector(0, 0, 0)
function I.Instances(class)
    local V = GSA1.ObjView
    local T = O.TYPE
    local c = O.BY_CLASS[class]
    if not (V and c) then return nil end
    local out = {}
    local function need(t, p1)
        local D = V.Need(t, p1, 1)
        D.anchor = D.anchor or Vector(0, 0, 0)
        return D
    end
    if c.type == T.RING then
        out[1] = { D = need(T.RING, 0), pos = Vector(0, 0, 0), r = I.RING_R }
    elseif c.type == T.O_GRING then
        local d = c.shape == 1 and I.CIRCLE or I.LINE
        local places = V.Places({ type = T.O_GRING, count = d.count, size = d.size, shape = d.shape },
            Angle(0, d.yaw or 0, 0))
        if not places then return nil end
        local D = need(T.RING, 0)
        for i, p in ipairs(places) do out[i] = { D = D, pos = p.off, r = I.RING_R } end
    else
        out[1] = { D = need(c.type, contents()), pos = Vector(0, 0, 0) }
    end
    return out
end

-- the copies are drawn, settled, their textures painted (and the logo, for an Extra Life box)
function I.InstancesReady(inst)
    local Tx = GSA1.Tex
    local V = GSA1.ObjView
    local seen = {}
    for _, it in ipairs(inst) do
        local D = it.D
        if not seen[D] then
            seen[D] = true
            if not (D.id and D.ready) then return false end
            local ok, steps, settled = pcall(gsa1.PreviewInfo, D.id)
            if not ok or settled ~= true then return false end
            for i = 1, D.batches.count do
                local b = D.batches[i]
                if b.archive >= 0 and b.tex >= 0 then
                    local e = Tx and Tx.Get(V.kind or 0, b.archive, b.tex, b.wrap or 0, true)
                    if e and not e.done then return false end
                end
            end
            if D.hasLogo and not (V.logo and V.logo.done) then
                V.logoWanted = true
                return false
            end
        end
    end
    return true
end

-- the bounds of the instances (PreviewInfo's object-space bounds of a box; a ring's size around each ring)
local function bounds_of(inst)
    local mn, mx = Vector(1e9, 1e9, 1e9), Vector(-1e9, -1e9, -1e9)
    for _, it in ipairs(inst) do
        local a, b
        if it.r then
            a = Vector(it.pos.x - it.r, it.pos.y - it.r, it.pos.z - it.r)
            b = Vector(it.pos.x + it.r, it.pos.y + it.r, it.pos.z + it.r)
        else
            local _, _, x0, y0, z0, x1, y1, z1 = gsa1.PreviewInfo(it.D.id)
            a = Vector((x0 or -20) + it.pos.x, (y0 or -20) + it.pos.y, (z0 or 0) + it.pos.z)
            b = Vector((x1 or 20) + it.pos.x, (y1 or 20) + it.pos.y, (z1 or 40) + it.pos.z)
        end
        mn = Vector(math.min(mn.x, a.x), math.min(mn.y, a.y), math.min(mn.z, a.z))
        mx = Vector(math.max(mx.x, b.x), math.max(mx.y, b.y), math.max(mx.z, b.z))
    end
    return mn, mx
end

-- 0.9.4d: THE FRAMING (pure maths; tests/feat_objicons_test.lua). The eye for the bounds [mn, mx] seen along ang: every
-- corner of the box inside `fill` of the picture's half width and height at the field of view fov (degrees; a square
-- picture), the picture centred on the corners' projection, and the nearest corner at least minNear in front of the eye -
-- where that pushes the eye back, the field of view narrows so the fill stays. Returns eye, dist (along the view from the
-- eye to the aim point), fov, near, far. (The corners' table is reused: no garbage but the eye.)
local corners = { {}, {}, {}, {}, {}, {}, {}, {} }
local function fit_dist(k, ox, oy)
    local d = -math.huge
    for i = 1, 8 do
        local c = corners[i]
        local need = math.max(math.abs(c[1] - ox), math.abs(c[2] - oy)) / k - c[3]
        if need > d then d = need end
    end
    return d
end
-- the corners' projection at distance d with the aim shifted by (ox, oy): min / max of x / depth and y / depth
local function fit_extent(d, ox, oy)
    local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, 8 do
        local c = corners[i]
        local z = d + c[3]
        local sx, sy = (c[1] - ox) / z, (c[2] - oy) / z
        if sx < x0 then x0 = sx end
        if sx > x1 then x1 = sx end
        if sy < y0 then y0 = sy end
        if sy > y1 then y1 = sy end
    end
    return x0, x1, y0, y1
end
function I.Fit(mn, mx, ang, fov, fill, minNear)
    fill, minNear = fill or I.FILL, minNear or 0
    local f, r, u = ang:Forward(), ang:Right(), ang:Up()
    local cx, cy, cz = (mn.x + mx.x) / 2, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2
    for i = 0, 7 do
        local dx = (i % 2 == 0 and mn.x or mx.x) - cx
        local dy = (math.floor(i / 2) % 2 == 0 and mn.y or mx.y) - cy
        local dz = (i < 4 and mn.z or mx.z) - cz
        local c = corners[i + 1]
        c[1] = dx * r.x + dy * r.y + dz * r.z
        c[2] = dx * u.x + dy * u.y + dz * u.z
        c[3] = dx * f.x + dy * f.y + dz * f.z
    end
    local k = fill * math.tan(math.rad(fov / 2))
    local ox, oy = 0, 0
    local d = fit_dist(k, ox, oy)
    -- centred: the aim moves by the middle of the projection (a few rounds converge: the shift is small against d)
    for _ = 1, 4 do
        local x0, x1, y0, y1 = fit_extent(d, ox, oy)
        ox, oy = ox + (x0 + x1) / 2 * d, oy + (y0 + y1) / 2 * d
        d = fit_dist(k, ox, oy)
    end
    -- the nearest corner at least minNear in front of the eye: farther back, a narrower field of view
    local nearest = math.huge
    for i = 1, 8 do nearest = math.min(nearest, d + corners[i][3]) end
    if nearest < minNear then
        d = d + (minNear - nearest)
        for _ = 1, 2 do
            local x0, x1, y0, y1 = fit_extent(d, ox, oy)
            ox, oy = ox + (x0 + x1) / 2 * d, oy + (y0 + y1) / 2 * d
        end
        local x0, x1, y0, y1 = fit_extent(d, ox, oy)
        local half = math.max(-x0, x1, -y0, y1)
        fov = 2 * math.deg(math.atan(half / fill))
    end
    local far = -math.huge
    nearest = math.huge
    for i = 1, 8 do
        far = math.max(far, d + corners[i][3])
        nearest = math.min(nearest, d + corners[i][3])
    end
    local eye = Vector(cx + r.x * ox + u.x * oy - f.x * d, cy + r.y * ox + u.y * oy - f.y * d,
        cz + r.z * ox + u.z * oy - f.z * d)
    return eye, d, fov, math.max(0.5, math.min(I.NEAR, nearest * 0.5)), far + 16
end

-- the camera of a class: { ang, fov } (the boxes: I.VIEW / I.FOV)
function I.ViewOf(class)
    return I.VIEWS[class] or { ang = I.VIEW, fov = I.FOV }
end

-- 0.9.4d: the ring's turn from its bounds (object space: it stands upright and turns about z): its width as seen along x
-- (the y extent) over its height (the z extent) - 1 face-on to a view along x, about its thickness / its size edge-on
function I.RingAspect(x0, y0, z0, x1, y1, z1)
    local h = (tonumber(z1) or 0) - (tonumber(z0) or 0)
    if not (h > 0) then return nil end
    return ((tonumber(y1) or 0) - (tonumber(y0) or 0)) / h
end

-- the ring classes wait for the moment their rings show a three-quarter view (I.FACE), at most I.FACE_WAIT s
function I.FacingReady(class, inst, waited)
    local c = O.BY_CLASS[class]
    if not (c and (c.type == O.TYPE.RING or c.type == O.TYPE.O_GRING)) or not inst[1] then return true end
    if (waited or 0) > I.FACE_WAIT then return true end
    local ok, _, _, x0, y0, z0, x1, y1, z1 = pcall(gsa1.PreviewInfo, inst[1].D.id)
    local w = ok and I.RingAspect(x0, y0, z0, x1, y1, z1) or nil
    if not w then return true end
    return w >= I.FACE[1] and w <= I.FACE[2]
end

-- 0.9.4d: THE CHECK - the coverage of a picture over its whole area. read(x, y) -> the pixel's alpha (nil: not known).
-- Returns the opaque share (alpha >= I.COVER_ALPHA) and the fully transparent share of the samples, or nil
function I.Coverage(read, size, step)
    step = step or I.COVER_STEP
    local n, opaque, clear = 0, 0, 0
    for y = 0, size - 1, step do
        for x = 0, size - 1, step do
            local a = read(x, y)
            if a == nil then return nil end
            n = n + 1
            if a >= I.COVER_ALPHA then
                opaque = opaque + 1
            elseif a <= 0 then
                clear = clear + 1
            end
        end
    end
    if n == 0 then return nil end
    return opaque / n, clear / n
end

function I.CoverageOK(opaque, clear)
    return opaque ~= nil and clear ~= nil and opaque >= I.COVER_MIN and clear >= I.CLEAR_MIN
end

local function cover_text(opaque, clear)
    if opaque == nil then return "no alpha read back" end
    return string.format("%.1f %% opaque, %.1f %% clear", opaque * 100, (clear or 0) * 100)
end

-- the read-back of the pushed render target (after render.CapturePixels)
local function rt_alpha(x, y)
    local _, _, _, a = render.ReadPixel(x, y)
    return a
end

-- the PNG check (review R.7): the file's material, not an error, and its four corners transparent (a capture that ignored
-- alpha = true has an opaque background). 0.9.4f hot fix: the file's coverage is scanned only when scan is set - where
-- render.ReadPixel gives no alpha, every I.PNG_STEP-th pixel (256 reads); else the PNG is written only from a render target
-- that passed. 0.9.4d scanned 16,384 pixels of every PNG with IMaterial:GetColor4Part (about 1 ms a read): 15-27 s a
-- picture at 1 fps (owner log 2026-10-27)
local function png_check(f, size, scan)
    local m = I.PngMaterial(f)
    if not m or not (m.GetColor or m.GetColor4Part) then return nil, "Material() gave an error material" end
    local read
    if m.GetColor4Part then
        read = function(x, y)
            local _, _, _, a = m:GetColor4Part(x, y)
            return a
        end
    else
        read = function(x, y)
            local c = m:GetColor(x, y)
            return c and (c.a or 255) or nil
        end
    end
    local e = size - 1
    for i = 1, 4 do
        local a = read(i <= 2 and 0 or e, i % 2 == 1 and 0 or e)
        -- an unknown alpha counts as opaque (as IMaterial:GetColor's missing .a above)
        if a == nil or a > 0 then return nil, "a corner is not transparent (the PNG kept no alpha)" end
    end
    if scan then
        local opaque, clear = I.Coverage(read, size, I.PNG_STEP)
        if not I.CoverageOK(opaque, clear) then return nil, cover_text(opaque, clear) end
    end
    return m
end

-- writes the PNG of class (when saving is on) and checks it; returns its material and file name, or nil
local function save_png(class, data, size, scan)
    if not (data and cv.icons_save and cv.icons_save:GetBool() and file and file.Write) then return nil end
    local f = I.FileName(class, I.key)
    if not I.SafeName(f) then return nil end
    file.CreateDir(I.DIR)
    file.Write(I.DIR .. "/" .. f, data)
    local m, why = png_check(f, size, scan)
    if not m then
        I.stats.png_failed = I.stats.png_failed + 1
        if file.Delete then file.Delete(I.DIR .. "/" .. f) end
        log("the spawn-menu picture %s did not pass its check (%s): deleted", f, tostring(why))
        return nil
    end
    I.stats.saved = I.stats.saved + 1
    log("the spawn-menu picture %s saved (%d bytes)", f, #data)
    return m, f
end

-- the render state a picture is drawn under (0.9.4d: the world draw's colour rules, a neutral studio): set, then restored
local function studio_begin()
    local st = {}
    st.tone = render.GetToneMappingScaleLinear and render.GetToneMappingScaleLinear()
    if render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(Vector(1, 1, 1)) end
    st.fog = render.GetFogMode and render.GetFogMode()
    if render.FogMode then render.FogMode(MATERIAL_FOG_NONE or 0) end
    if render.GetColorModulation and render.SetColorModulation then
        st.cr, st.cg, st.cb = render.GetColorModulation()
        render.SetColorModulation(1, 1, 1)
    end
    if render.GetBlend and render.SetBlend then
        st.blend = render.GetBlend()
        render.SetBlend(1)
    end
    -- opaque draws keep alpha 1 (not the view depth: the 0.9.4b pale ring)
    if render.SetWriteDepthToDestAlpha then render.SetWriteDepthToDestAlpha(false) end
    return st
end
local function studio_light(centre)
    -- (again inside cam.Start3D's view, in case pushing the view sets it)
    if render.SetWriteDepthToDestAlpha then render.SetWriteDepthToDestAlpha(false) end
    if GSA1.ApplyLightCube then
        GSA1.ApplyLightCube(centre, I.STUDIO)       -- (cl_render.lua: the ambient cube, the local lights cleared)
    else
        render.SuppressEngineLighting(true)
        render.SetLightingOrigin(centre)
        render.ResetModelLighting(0, 0, 0)
        for i = 0, 5 do
            local l = I.STUDIO[i]
            render.SetModelLighting(i, l.x, l.y, l.z)
        end
        if render.SetLocalModelLights then render.SetLocalModelLights() end
    end
end
local function studio_end(st)
    if render.SetWriteDepthToDestAlpha then render.SetWriteDepthToDestAlpha(true) end     -- (the main view's state)
    if st.blend and render.SetBlend then render.SetBlend(st.blend) end
    if st.cr and render.SetColorModulation then render.SetColorModulation(st.cr, st.cg, st.cb) end
    if render.FogMode and st.fog then render.FogMode(st.fog) end
    if st.tone and render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(st.tone) end
end

local M = nil
-- draws class's picture (in PostRender); true when done (made, or given up)
function I.Render(class, inst)
    local V = GSA1.ObjView
    local Tx = GSA1.Tex
    local fmt = Tx and Tx.format or { name = "BGRA8888", fmt = IMAGE_FORMAT_BGRA8888 or 12 }
    local size = I.SIZE
    local t0 = SysTime()
    local rt = GetRenderTargetEx("gsa1_icon_" .. class .. "_" .. fmt.name, size, size, RT_SIZE_LITERAL or 1,
        MATERIAL_RT_DEPTH_SEPARATE or 1, bor(TEXTUREFLAGS_CLAMPS or 4, TEXTUREFLAGS_CLAMPT or 8), 0, fmt.fmt)
    local mn, mx = bounds_of(inst)
    local centre = (mn + mx) * 0.5
    local view = I.ViewOf(class)
    local ang = view.ang
    local eye, dist, fov, near, far = I.Fit(mn, mx, ang, view.fov, I.FILL, I.NEAR_MIN)
    -- every copy's view from this eye (sprites and sphere maps face the icon's camera)
    local refreshed = {}
    for _, it in ipairs(inst) do
        if not refreshed[it.D] then
            refreshed[it.D] = true
            V.Refresh(it.D, eye, ang, it.pos, true)
        end
    end
    M = M or Matrix()
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(0, 0, 0, 0, true, true)
    local st = studio_begin()
    cam.Start3D(eye, ang, fov, 0, 0, size, size, near, far)
    studio_light(centre)
    local ok, err = pcall(function()
        for pass = 0, 1 do
            for _, it in ipairs(inst) do
                M:Identity()
                M:SetTranslation(it.pos)
                cam.PushModelMatrix(M)
                local ok2, e2 = pcall(V.DrawDesc, it.D, pass, false, false, true, true, nil)
                cam.PopModelMatrix()
                if not ok2 then error(e2, 0) end
            end
        end
    end)
    if GSA1.EndLightCube then GSA1.EndLightCube() else render.SuppressEngineLighting(false) end
    cam.End3D()
    studio_end(st)
    local opaque, clear = nil, nil
    local data = nil
    local tc = 0             -- 0.9.4f: the render target's check time, in the log line (0.9.4d's pictures took 15-27 s
                             -- each; its log gave totals only - the PNG's GetColor4Part scan the likely cost)
    if ok then
        local t1 = SysTime()
        render.CapturePixels()
        opaque, clear = I.Coverage(rt_alpha, size)
        tc = SysTime() - t1
        if cv.icons_save:GetBool() and render.Capture then
            data = render.Capture({ format = "png", x = 0, y = 0, w = size, h = size, alpha = true })
        end
    end
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    if not ok then
        log("the spawn-menu picture of %s could not be drawn: %s", class, tostring(err))
        return true
    end
    local rt_ok = I.CoverageOK(opaque, clear)
    if not rt_ok then I.stats.rt_failed = I.stats.rt_failed + 1 end
    -- 0.9.4f hot fix: a PNG only of a picture that passed (its pixels are the render target's) - or, where render.ReadPixel
    -- gives no alpha (opaque nil), of every picture: then the PNG's own coverage scan decides
    local no_alpha = opaque == nil
    local pm, pf = save_png(class, (rt_ok or no_alpha) and data or nil, size, no_alpha)
    local p
    if rt_ok then
        local mat = CreateMaterial("gsa1_icon_" .. class .. "_" .. fmt.name, "UnlitGeneric", {
            ["$basetexture"] = rt:GetName(), ["$translucent"] = 1, ["$vertexalpha"] = 1, ["$vertexcolor"] = 1 })
        p = { mat = mat, from = "rt", rt = rt, file = pf }
    elseif pm then
        p = { mat = pm, from = "png", file = pf }
    end
    if not p then
        log("the spawn-menu picture of %s did not pass its read-back check (%s): G-SA1's drawing stays", class,
            cover_text(opaque, clear))
        return true
    end
    I.pics[class] = p
    I.stats.made = I.stats.made + 1
    I.ApplyClass(class)
    if pf then I.WriteIndex() end
    log("the spawn-menu picture of %s made (%.1f ms, %s; %s, the check %.1f ms; %.0f degrees at %.0f HU)", class,
        (SysTime() - t0) * 1000, p.from == "rt" and "render target" or "from its PNG", cover_text(opaque, clear), tc * 1000,
        fov, dist)
    return true
end
-- Sonic's 1-up icon into a 16 x 16 picture for the tab
function I.RenderTab()
    local Tx = GSA1.Tex
    if not Tx then return true end
    local e = Tx.Get(I.TAB_KIND, I.TAB_ARCHIVE, I.TAB_TEX, WRAP_CLAMP, true)
    if not e then
        log("Sonic's 1-up icon (texture %d of archive %d) is not on this disc: the tab keeps its silkicon", I.TAB_TEX,
            I.TAB_ARCHIVE)
        return true
    end
    if not e.done then return false end
    local fmt = Tx.format
    local size = I.TAB_SIZE
    local rt = GetRenderTargetEx("gsa1_tabicon_" .. fmt.name, size, size, RT_SIZE_LITERAL or 1, MATERIAL_RT_DEPTH_NONE or 2,
        bor(TEXTUREFLAGS_CLAMPS or 4, TEXTUREFLAGS_CLAMPT or 8), 0, fmt.fmt)
    local src = CreateMaterial("gsa1_tabicon_src_" .. fmt.name, "UnlitGeneric", { ["$basetexture"] = e.rt:GetName(),
        ["$translucent"] = 1, ["$vertexalpha"] = 1, ["$vertexcolor"] = 1 })
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(0, 0, 0, 0)
    cam.Start2D()
    render.OverrideBlend(true, B_ONE, B_ZERO, F_ADD, B_ONE, B_ZERO, F_ADD)
    surface.SetMaterial(src)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRect(0, 0, size, size)
    render.OverrideBlend(false)
    cam.End2D()
    render.CapturePixels()
    local seen = false
    for y = 0, size - 1, 3 do
        for x = 0, size - 1, 3 do
            local _, _, _, a = render.ReadPixel(x, y)
            if a and a > 0 then seen = true end
        end
    end
    local data = nil
    if cv.icons_save:GetBool() and render.Capture then
        data = render.Capture({ format = "png", x = 0, y = 0, w = size, h = size, alpha = true })
    end
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    local pm, pf = nil, nil
    if data and file and file.Write then
        pf = I.FileName("tab", I.key)
        file.CreateDir(I.DIR)
        file.Write(I.DIR .. "/" .. pf, data)
        pm = I.PngMaterial(pf)
        if pm and pm.GetColor then
            local any = false
            for y = 0, size - 1, 3 do
                for x = 0, size - 1, 3 do
                    local c = pm:GetColor(x, y)
                    if c and (c.a or 0) > 0 then any = true end
                end
            end
            if not any then pm = nil end
        end
        if not pm then
            if file.Delete then file.Delete(I.DIR .. "/" .. pf) end
            I.stats.png_failed = I.stats.png_failed + 1
            log("the tab's icon %s did not pass its check: deleted", pf)
            pf = nil
        else
            I.stats.saved = I.stats.saved + 1
        end
    end
    local p
    if pm then
        p = { mat = pm, from = "png", file = pf }
    elseif seen then
        p = { mat = CreateMaterial("gsa1_tabicon_" .. fmt.name, "UnlitGeneric", { ["$basetexture"] = rt:GetName(),
            ["$translucent"] = 1, ["$vertexalpha"] = 1, ["$vertexcolor"] = 1 }), from = "rt", rt = rt }
    end
    if not p then
        log("the tab's icon did not pass its read-back check: the silkicon stays")
        return true
    end
    I.pics.tab = p
    I.ApplyTab(p)
    if pf then I.WriteIndex() end
    log("the tab's icon: Sonic's 1-up icon, 16 x 16 (%s)", p.from == "rt" and "render target" or "PNG")
    return true
end

-- one step a frame (PostRender) ---------------------------------------------------------------------------------------------
function I.Step()
    if not I.Enabled() then return end
    local V = GSA1.ObjView
    local key = I.Key()
    if key and key ~= I.key and (V and V.Ready and V.Ready() or I.key == nil) then
        if V and V.Ready and V.Ready() then
            I.KeyChanged(key)
        elseif I.key == nil and not I.indexTried then
            I.indexTried = true
            I.LoadIndex(key)            -- before the disc: the owner's own files of this key (review R.19)
        end
    end
    if not (V and V.Ready and V.Ready()) or I.key == nil then return end
    local job = I.job
    if not job then
        local class = I.queue[1]
        if not class then return end
        -- the classes wait for the spawn menu's first G-SA1 icon (or its opening); the tab's icon does not
        if class ~= "tab" and not I.wanted then return end
        table.remove(I.queue, 1)
        job = { class = class, t0 = now_s(), start = now_s() }
        I.job = job
    end
    if job.class ~= "tab" and V.KindNow then
        -- 0.9.4f: a character change while a picture waits clears the showcase copies (cl_objview.lua V.Think); the wait
        -- starts again for the new kind's copies and textures instead of running out (a new key requeued them until 0.9.4e)
        local k = V.KindNow()
        if job.kind ~= k then
            if job.kind ~= nil then job.t0 = now_s() end
            job.kind = k
        end
    end
    local done
    if job.class == "tab" then
        done = I.RenderTab()
    else
        local inst = I.Instances(job.class)
        if inst and I.InstancesReady(inst) and I.FacingReady(job.class, inst, now_s() - job.t0) then
            done = I.Render(job.class, inst)
        end
    end
    if done then
        I.job = nil
    elseif now_s() - job.t0 > I.WAIT_MAX or now_s() - job.start > 3 * I.WAIT_MAX then   -- 3 x: a kind that never settles
        I.stats.waited = I.stats.waited + 1
        log("the spawn-menu picture of %s was not ready within %d s: G-SA1's drawing stays", job.class, I.WAIT_MAX)
        I.job = nil
    end
end

hook.Add("PostRender", "gsa1_objicons", function()
    local ok, err = pcall(I.Step)
    if not ok and not I.stepError then
        I.stepError = true
        log("error: %s", tostring(err))
        ErrorNoHalt("[G-SA1] spawn-menu pictures: " .. tostring(err) .. "\n")
    end
end)

-- the spawn menu opened: the pictures are wanted (also when no G-SA1 icon was made yet)
hook.Add("OnSpawnMenuOpen", "gsa1_objicons", function() I.wanted = true end)

-- a device reset (render targets lose their contents): a render-target picture switches to its PNG, else it is drawn again
function I.DeviceReset(why)
    local n = 0
    for class, p in pairs(I.pics) do
        if p.from == "rt" then
            local m = p.file and I.PngMaterial(p.file)
            if m then
                I.pics[class] = { mat = m, from = "png", file = p.file }
                if class == "tab" then I.ApplyTab(I.pics[class]) else I.ApplyClass(class) end
            else
                table.insert(I.queue, class)
            end
            n = n + 1
        end
    end
    if n > 0 then log("%d spawn-menu pictures after %s: their PNGs, or drawn again", n, why) end
    return n
end
local hadFocus = true
hook.Add("PostRender", "gsa1_objicons_reset", function()
    local focus = true
    if system and system.HasFocus then focus = system.HasFocus() and true or false end
    if focus and not hadFocus then I.DeviceReset("the game window got the focus back") end
    hadFocus = focus
end)
hook.Add("OnScreenSizeChanged", "gsa1_objicons", function() I.DeviceReset("a screen size change") end)

-- the switches
cvars.AddChangeCallback("gsa1_set_icons", function(_, _, new)
    for _, class in ipairs(I.Classes()) do I.ApplyClass(class) end
    local T = GSA1.SpawnTab
    if tonumber(new) == 0 then
        if T and T.SetIcon then T.SetIcon("icon16/coins.png") end
    elseif I.pics.tab then
        I.ApplyTab(I.pics.tab)
    end
end, "gsa1_objicons")

-- "Redraw the spawn-menu pictures"
function I.Rebuild()
    I.gen = I.gen + 1
    local old = I.ReadIndex()
    I.wanted = true
    I.QueueAll()
    log("redrawing the spawn-menu pictures")
    -- the old files go once the new index is written (their names stay valid until then)
    I.pendingDelete = old
    return true
end
concommand.Add("gsa1_icons_rebuild", function() I.Rebuild() end, nil,
    "G-SA1: draw the spawn-menu pictures of the rings and item boxes again from your disc")

-- after a redraw's last picture: the files of the old index that the new one does not list
hook.Add("Think", "gsa1_objicons", function()
    if I.pendingDelete and #I.queue == 0 and not I.job then
        local keep = {}
        local cur = I.ReadIndex()
        for _, f in pairs(cur and cur.files or {}) do keep[f] = true end
        I.DeleteListed(I.pendingDelete, keep)
        I.pendingDelete = nil
    end
end)

function I.StatusLine()
    if not I.Enabled() then return "spawn-menu pictures: off (G-SA1's drawings)" end
    local V = GSA1.ObjView
    if not (V and V.Have and V.Have()) then return "spawn-menu pictures: G-SA1's drawings (this module has no previews)" end
    local made, png = 0, 0
    for _, p in pairs(I.pics) do
        made = made + 1
        if p.file then png = png + 1 end
    end
    local why = ""
    if not V.Ready() then why = " - waiting for the disc"
    elseif not I.wanted then why = " - made when the spawn menu first shows a G-SA1 icon"
    elseif #I.queue > 0 or I.job then why = " - drawing" end
    return string.format("spawn-menu pictures: %d of %d made, %d kept in garrysmod/data/gsa1/icons, %d check(s) failed%s",
        made, #O.CLASSES + 1, png, I.stats.rt_failed + I.stats.png_failed, why)
end
