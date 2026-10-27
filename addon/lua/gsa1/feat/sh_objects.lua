-- G-SA1 feature "objects", shared part (both realms; round 0.9.4: spawnable Rings and Item Boxes; sadc
-- docs/research/gsa1_094_plan.md 6.5 with its Review R.1 / R.3 / R.15 / R.17, gsa1_090_rings.md 4.2 / 4.4 / 4.5 with its
-- review, gsa1_094_items.md 5, v1_arch.md 4 / 6 with its review).
--
-- The owner: "Spawnable Rings and Item Boxes. You already have them in-game, there's just no way to spawn them." Five
-- entities under Q menu > Entities > G-SA1 (addon/lua/entities/gsa1_obj_*.lua on the base gsa1_base.lua): a Ring, a
-- Ring line, a Ring circle, an Item Box on the ground and an Item Box in the air. They are only places: the game's own
-- code runs them in each character's world (the module's feature "objects", libsa1's SET objects), so the rings, the
-- boxes, their sounds, sparkles, items and the HUD are the game's. The server keeps the shared state - a Ring taken, a
-- box broken, a line's or circle's rings taken (NetworkVars State, Broken, TakenBits) - and checks each report against
-- the character's own positions (feat/sv_objects.lua); every client puts that state into its worlds (feat/cl_objects.lua).
--
-- This file: the catalogue (classes, sizes, defaults, the nine contents), the settings (ConVars with their controls on
-- the Objects page: cl_objects.lua), the network strings, the cleanup and the limit, the context-menu properties
-- ("Contents", "Respawn now"), and the pure rules both realms share - where the game puts a line's or circle's rings
-- (the same layout as the module's src/core/objects.cpp, read from the game's code_8C087B80.c), and the server's check of
-- a report (the touch, the reach per cause, the character's path at the report's age).
--
-- 0.9.4.1 (the owner's test of 0.9.4: "the ring circle is limited to only having 7 rings per circle. You can't do more?
-- Ideally, the line and the circle should be able to have at most 128 rings."; "selecting any object in the Context menu
-- (C Key) is very difficult. Nothing can be moved after being added."; and in his log, unnoted, "the server refused Ring
-- line 250: the touch was 216 units from it (at most 64)"):
--   * a Ring line and a Ring circle hold up to 128 rings. The game's limits are per record (a line record 8 rings, a
--     circle record 7 with a bit): a circle of N rings is m = N / n records of n rings each (n = the largest of 7..1 that
--     divides N), record k turned by k * 360 / N about the circle's axis, so the game's own circle layout puts record
--     k's ring i on the circle's place (i * m + k) mod N (O.CircleSplit, O.RingPositions; the module's objects.cpp; the
--     game's places measured with the disc in feat_objects_binding_test). A circle of a prime number of rings above 7
--     is that many records of 1 ring. The shared state of every record is the String NetworkVar TakenBits (two hex
--     digits per record; 0.9.4: Int NetworkVars UserBits0..7, too few for 127 records): O.BitsGet / O.BitsSet;
--   * the refusals were not a layout error (measured: the game's ring tasks sit within 0.01 HU of O.RingPositions at
--     every angle tried, and a touch on a ring names exactly its record and bit): a USERBITS event carries the touch of
--     the record's LAST touched ring while the bits it adds are of rings taken up to ~18 steps before (a ring's bit is
--     set after its 16-step sparkle), up to ~180 HU away at a run. O.CheckEvent now checks the touch against every ring
--     of the record and each added ring against the character's path in the half second before the touch;
--   * the pick hull (O.Hull, O.PickTrace, gsa1_base.lua TestCollision): the whole object (a line's length, a circle's
--     diameter, a box), hit by the Physics Gun's, the Tool Gun's and the context menu's traces only.
--
-- 0.9.4b (sadc docs/research/objects2_plan.md 6.3 task 5, section 7, owner answers 11.0; the owner's notes on 0.9.4: "big
-- pop-in with the spawnables. They should be visible from a much further distance."; "only bounding boxes can be seen
-- when not in Sonic Adventure mode"; "the menu icons should be rendered instead of SVG graphics"): the settings of the
-- range (gsa1_set_range: the game's own per-type range of the object list, 1,600 - the Dreamcast's - to 12,000 HU, the
-- far plane; default 4,800), the screen width (gsa1_set_view_wide), the pictures of the real objects (gsa1_set_view: no
-- character; gsa1_set_view_edit / gsa1_set_view_far: with one; gsa1_set_view_dist; gsa1_set_view_smooth, owner answer O6:
-- optional, off), the spawn-menu pictures (gsa1_set_icons, gsa1_set_icons_save), and the windows' new defaults and
-- limits (128 / 48 of 200 / 100: the ceiling of the game's own collision lists). feat/cl_objects.lua sends them to the
-- module and has their controls; feat/cl_objview.lua draws the pictures, feat/cl_objicons.lua the spawn-menu pictures.
GSA1 = GSA1 or {}
GSA1.Objects = GSA1.Objects or {}
local O = GSA1.Objects

O.NEEDS = { feature = "objects", version = 2, module = "0.9.4.1" }      -- 2: 128-ring lines and circles (0.9.4.1)
O.RANGE_VERSION = 3              -- feature "objects" 3 (0.9.4b): SetConfig's range and view_tan, SetLive

-- libsa1's numbers (libsa1.h "SET objects"; the module's gsa1.OBJECTS has the same, cl_objects.lua prefers it)
O.TYPE = { RING = 1, O_GRING = 2, ITEMBOX = 3, ITEMBOX_AIR = 4 }
O.STATE_PRESENT, O.STATE_BROKEN = 1, 2
O.EV = { SPAWNED = 1, DESPAWNED = 2, GONE = 3, USERBITS = 4, BROKEN = 7 }
O.CAUSE = { UNKNOWN = 0, BODY = 1, PROJECTILE = 2, MAGNET = 3 }
O.CAUSE_NAME = { [0] = "unknown", [1] = "body", [2] = "projectile", [3] = "magnet" }
O.GOPT_ITEM_ICON_LIMIT = 4
O.DRAW_OBJECT = 0x1000
O.LINE_MAX, O.LINE_GROUP, O.CIRCLE_MAX, O.CIRCLE_GROUP = 128, 8, 128, 7   -- 0.9.4: 64, 8, 7 (one circle record)
O.MAX_RECORDS = 128                              -- records of one object (a circle of 127 rings: 127 records of 1)
-- libsa1's SA1_SET_RING_WINDOW_MAX / BOX_WINDOW_MAX since 0.9.4b (0.9.4: 70 / 32; review R.14): the ConVars' own limits
-- (review R.9: CreateClientConVar clamps every value to its max before the module loads); the module's gsa1.OBJECTS
-- maxima clamp where the window is sent (cl_objects.lua O.Sync) and on the page's sliders
O.RING_WINDOW_MAX, O.BOX_WINDOW_MAX = 200, 100
O.RING_WINDOW_DEFAULT, O.BOX_WINDOW_DEFAULT = 128, 48   -- 0.9.4: 64 / 32 (a saved 64 / 32 moves to these once)
O.RANGE_GAME = 1600              -- HU: the game's spawner reaches 400 SA1 units around the character (attribute 0)
O.RANGE_MAX = 12000              -- HU: 3,000 SA1 units, the world's far plane (owner answer O1; libsa1's SA1_SET_RANGE_MAX)
O.RANGE_DEFAULT = 4800           -- HU: three times the Dreamcast's
O.RANGE = O.RANGE_DEFAULT        -- HU: the range in use (cl_objects.lua O.Sync keeps it at gsa1_set_range)
O.MARGIN = 400                   -- HU: the window's margin beyond the range (libsa1's default 100 SA1 units)
O.VIEW_DIST_MIN, O.VIEW_DIST_MAX, O.VIEW_DIST_DEFAULT = 1000, 32768, 8000   -- HU: the pictures' distance
O.KIND_GAMMA, O.KIND_BIG = 6, 7

O.NET = { EV = "gsa1_obj_ev", ST = "gsa1_obj_st" }

-- the game's nine contents (scl.x of both boxes: the table D_8C1B9BA0; names: the debug print's D_8C1B9C8C)
O.CONTENTS = {
    { value = 0, title = "Speed Shoes (HAYAASI)" },
    { value = 1, title = "Invincibility (MUTEKI)" },
    { value = 2, title = "5 Rings (5RING)" },
    { value = 3, title = "10 Rings (10RING)" },
    { value = 4, title = "Random Rings (RANDOMRING)" },
    { value = 5, title = "Barrier (BARIA)" },
    { value = 6, title = "Extra Life (1UP)" },
    { value = 7, title = "Bomb (EKUSUPUROSYON)" },
    { value = 8, title = "Magnetic Barrier (ITEM_TH_BARIA)" },
}
O.DEFAULT_CONTENTS = 3                           -- 10 Rings: the disc's most common box (110 + 128 placements)

-- the classes (the entity files carry the same fields; this table is what the rules, the page and the tests read)
--   count / spacing / radius: { min, max, default } (HU for sizes); lift: HU above the surface aimed at
O.CLASSES = {
    { class = "gsa1_obj_ring", title = "Ring", type = 1, lift = 32, ring = 16 },
    { class = "gsa1_obj_ring_line", title = "Ring line", type = 2, shape = 0, lift = 32, ring = 16,
      count = { 1, 128, 10 }, size = { 8, 400, 40 }, size_name = "Spacing" },
    { class = "gsa1_obj_ring_circle", title = "Ring circle", type = 2, shape = 1, lift = 32, ring = 16,
      count = { 1, 128, 7 }, size = { 16, 800, 80 }, size_name = "Radius" },
    { class = "gsa1_obj_itembox", title = "Item Box", type = 3, lift = 0, contents = true,
      mins = Vector(-20, -20, 0), maxs = Vector(20, 20, 60) },
    { class = "gsa1_obj_itembox_air", title = "Item Box (Air)", type = 4, lift = 40, contents = true,
      mins = Vector(-40, -40, -20), maxs = Vector(40, 40, 60) },
}
O.BY_CLASS = {}
for _, c in ipairs(O.CLASSES) do O.BY_CLASS[c.class] = c end

function O.IsObject(ent)
    return ent ~= nil and ent ~= NULL and type(ent) ~= "number" and ent.GSA1Object == true
end

-- the settings --------------------------------------------------------------------------------------------------------
-- client (GSA1.ConVar: nil on the server)
O.cv = O.cv or {}
local cv = O.cv
cv.on = GSA1.ConVar("gsa1_set", 1, "Rings and item boxes in your game: 1 = the G-SA1 objects on the map run in your "
    .. "character's world (the game's own rings and boxes); 0 = none (they are removed from your worlds)", 0, 1)
cv.draw = GSA1.ConVar("gsa1_set_draw", 1, "Draw the rings and item boxes (also in first person, whatever the Effects "
    .. "setting says); 0 = they still work, unseen", 0, 1)
cv.ring_window = GSA1.ConVar("gsa1_set_ring_window", O.RING_WINDOW_DEFAULT, "Rings the game handles at once around your "
    .. "character (each ring of a line or circle counts; the nearest first, then those in front of you)", 16,
    O.RING_WINDOW_MAX)
cv.box_window = GSA1.ConVar("gsa1_set_box_window", O.BOX_WINDOW_DEFAULT, "Item boxes the game handles at once around your "
    .. "character (the nearest first, then those in front of you)", 4, O.BOX_WINDOW_MAX)
-- 0.9.4b: the range and the screen width (objects2_plan.md section 7)
cv.range = GSA1.ConVar("gsa1_set_range", O.RANGE_DEFAULT, "How far away (HU) your character's game runs rings and item "
    .. "boxes: 1600 = the Dreamcast's own distance, up to 12000 (the game's far plane). Farther costs frame rate with many "
    .. "rings on screen", O.RANGE_GAME, O.RANGE_MAX)
cv.view_wide = GSA1.ConVar("gsa1_set_view_wide", 1, "Rings and boxes use your whole screen width (1) or the game's 4:3 "
    .. "view (0): only their drawing changes", 0, 1)
-- 0.9.4b: the pictures of the real objects (feat/cl_objview.lua) and the spawn-menu pictures (feat/cl_objicons.lua)
cv.view = GSA1.ConVar("gsa1_set_view", 1, "Show the real rings and item boxes (pictures from your disc) when you have no "
    .. "character; 0 = outlines", 0, 1)
cv.view_edit = GSA1.ConVar("gsa1_set_view_edit", 1, "With a character, show the rings and boxes your game is not running "
    .. "as pictures while you hold the Physics Gun or the Tool Gun", 0, 1)
cv.view_far = GSA1.ConVar("gsa1_set_view_far", 1, "While playing, show far rings and item boxes (beyond your game's "
    .. "distance) as pictures; they become the real ones as you get close", 0, 1)
cv.view_dist = GSA1.ConVar("gsa1_set_view_dist", O.VIEW_DIST_DEFAULT, "How far away (HU) the pictures of rings and item "
    .. "boxes are drawn", O.VIEW_DIST_MIN, O.VIEW_DIST_MAX)
cv.view_smooth = GSA1.ConVar("gsa1_set_view_smooth", 0, "Smooth the pictures to your frame rate (1) or turn them at the "
    .. "game's own 30 steps a second (0, the Dreamcast's)", 0, 1)
cv.icons = GSA1.ConVar("gsa1_set_icons", 1, "Spawn-menu pictures of the real objects, drawn from your disc (0 = "
    .. "G-SA1's own drawings)", 0, 1)
cv.icons_save = GSA1.ConVar("gsa1_set_icons_save", 1, "Keep the spawn-menu pictures in garrysmod/data/gsa1/icons so they "
    .. "show at once next time (they stay on your computer; G-SA1 never uploads or shares them)", 0, 1)
cv.icon_guard = GSA1.ConVar("gsa1_set_icon_guard", 1, "Keep the game's item icon list safe: 1 = when 20 item pictures "
    .. "are already on screen the next one is skipped (you still get the item); 0 = the game's own list, which breaking "
    .. "more than 20 boxes within about 2 seconds overruns", 0, 1)
cv.markers = GSA1.ConVar("gsa1_set_markers", 1, "Show the objects' outlines while you hold the Physics Gun or the Tool "
    .. "Gun (and, without a character, whenever the real objects' pictures are not shown)", 0, 1)
cv.debug = GSA1.ConVar("gsa1_set_debug", 0, "Show the objects' range around your character and a line with the records "
    .. "and events (debugging)", 0, 1)
-- review R.15: GSA1.ConVar makes no userinfo ConVar (the server reads this one when you place a box) and takes only
-- gsa1_ names (the sandbox limit is sbox_max<name>): both made here and listed in GSA1.CONVARS by hand
if CLIENT then
    cv.box_content = CreateClientConVar("gsa1_set_box_content", tostring(O.DEFAULT_CONTENTS), true, true,
        "What a new item box you place holds: 0 Speed Shoes, 1 Invincibility, 2 5 Rings, 3 10 Rings, 4 Random Rings, "
        .. "5 Barrier, 6 Extra Life, 7 Bomb, 8 Magnetic Barrier", 0, 8)
end
GSA1.CONVARS = GSA1.CONVARS or {}
GSA1.CONVARS.gsa1_set_box_content = { cv = cv.box_content, default = tostring(O.DEFAULT_CONTENTS),
    help = "What a new item box you place holds (0..8)", min = 0, max = 8, server = false, userinfo = true }
-- server (replicated, archived: both realms)
cv.sv_on = GSA1.ConVar("gsa1_sv_set", 1, "G-SA1 objects on this server: 1 = players can place rings and item boxes and "
    .. "take them; 0 = no new ones, and nothing is taken", 0, 1, { server = true })
cv.sv_respawn = GSA1.ConVar("gsa1_sv_set_respawn", 0, "Respawn after (seconds) for newly placed G-SA1 objects: a taken "
    .. "ring or broken box comes back after this long (0 = never, the game's rule; not the game's own behaviour, a host "
    .. "option)", 0, 3600, { server = true })
cv.sv_slack = GSA1.ConVar("gsa1_sv_set_reach_slack", 128, "Allowed distance slack (Hammer units) when the server checks "
    .. "where a character took a ring or broke a box against where it was (network lag)", 0, 2048, { server = true })
local LIMIT_FLAGS = bit.bor(FCVAR_ARCHIVE or 128, FCVAR_NOTIFY or 256, FCVAR_REPLICATED or 8192)
cv.sv_limit = GetConVar("sbox_maxgsa1_objects") or CreateConVar("sbox_maxgsa1_objects", "1000", LIMIT_FLAGS,
    "Most G-SA1 objects (rings, ring lines and circles, item boxes) one player may place", 0, 100000)
GSA1.CONVARS.sbox_maxgsa1_objects = { cv = cv.sv_limit, default = "1000", help = "Most G-SA1 objects per player",
    min = 0, max = 100000, server = true }

-- the cleanup (Utilities > Cleanup > G-SA1 objects) and the limit's text ------------------------------------------------
if cleanup and cleanup.Register then cleanup.Register("gsa1_objects") end
if CLIENT and language and language.Add then
    language.Add("Cleanup_gsa1_objects", "G-SA1 objects")
    language.Add("Cleaned_gsa1_objects", "Cleaned up the G-SA1 objects")
    language.Add("SBoxLimit_gsa1_objects", "You have reached the G-SA1 objects limit!")
    for _, c in ipairs(O.CLASSES) do language.Add(c.class, "G-SA1 " .. c.title) end
end

-- the layout ------------------------------------------------------------------------------------------------------------
-- an entity's shared description: type, shape, count, size (HU), contents (accessors may be missing: the class defaults)
function O.Describe(ent)
    local c = O.BY_CLASS[ent.GetClass and ent:GetClass() or ""] or {}
    local d = { class = c.class, type = c.type, shape = c.shape or 0, count = 1, size = 0, contents = O.DEFAULT_CONTENTS }
    if c.count then
        d.count = math.Clamp(math.floor(tonumber(ent.GetCount and ent:GetCount()) or c.count[3]), c.count[1], c.count[2])
    end
    if c.size then
        local getter = c.shape == 1 and ent.GetRadius or ent.GetSpacing
        d.size = math.Clamp(tonumber(getter and getter(ent)) or c.size[3], c.size[1], c.size[2])
    end
    if c.contents then
        d.contents = math.Clamp(math.floor(tonumber(ent.GetContents and ent:GetContents()) or O.DEFAULT_CONTENTS), 0, 8)
    end
    return d
end

-- a Ring circle of `count` rings as game records (the module's objects.cpp circle_split): n rings per record (the
-- largest of 7..1 that divides count: a game circle record has a bit for 7 rings at most) and m = count / n records
function O.CircleSplit(count)
    count = math.max(1, math.floor(tonumber(count) or 1))
    for n = O.CIRCLE_GROUP, 1, -1 do
        if count % n == 0 then return n, count / n end
    end
    return 1, count
end

-- how many records the game gets for d (a line: one per 8 rings; a circle: m)
function O.RecordCount(d)
    if d.type ~= O.TYPE.O_GRING then return 1 end
    if d.shape == 1 then
        local _, m = O.CircleSplit(d.count)
        return m
    end
    return math.floor((d.count + O.LINE_GROUP - 1) / O.LINE_GROUP)
end

-- the user bits of record k's rings (a line record of k rings: bits 0 .. k-1; a circle record of n rings: bits 1 .. n)
function O.RecordMask(d, k)
    if d.type ~= O.TYPE.O_GRING or k < 0 then return 0 end
    if d.shape == 1 then
        local n, m = O.CircleSplit(d.count)
        if k >= m then return 0 end
        return bit.band(bit.lshift(1, n + 1) - 2, 0xFF)
    end
    local n = math.min(O.LINE_GROUP, d.count - O.LINE_GROUP * k)
    if n <= 0 then return 0 end
    return bit.lshift(1, n) - 1
end

-- the shared state of a ring group (its rings taken, per record): two hex digits per record - record k at characters
-- 2k + 1 .. 2k + 2 - in the entity's String NetworkVar TakenBits; missing digits are 0, trailing zero records are left
-- out (an empty string: nothing taken)
function O.BitsGet(s, k)
    if type(s) ~= "string" or k < 0 then return 0 end
    return bit.band(tonumber(string.sub(s, 2 * k + 1, 2 * k + 2), 16) or 0, 0xFF)
end

function O.BitsSet(s, k, v)
    s = type(s) == "string" and s or ""
    local n = math.max(math.floor(#s / 2), k + 1)
    local parts = {}
    for j = 0, n - 1 do
        parts[j + 1] = string.format("%02X", j == k and bit.band(tonumber(v) or 0, 0xFF) or O.BitsGet(s, j))
    end
    local out = table.concat(parts)
    while #out >= 2 and string.sub(out, -2) == "00" do out = string.sub(out, 1, -3) end
    return out
end

-- record k's bits of an entity (its TakenBits; an entity without them: 0)
function O.BitsOf(ent, k)
    local get = ent and ent.GetTakenBits
    return get and O.BitsGet(get(ent), k) or 0
end

-- where the game puts the rings (host space; the module's objects.cpp ring_positions, the game's func_8C087EEE /
-- func_8C088000): { {record, bit, place, pos}, ... }; a RING: its own place. pos / ang: the entity's
function O.RingPositions(d, pos, ang)
    local out = {}
    if d.type == O.TYPE.RING then
        out[1] = { record = 0, bit = 0, place = 0, pos = Vector(pos) }
        return out
    end
    if d.type ~= O.TYPE.O_GRING then return out end
    local fwd = ang:Forward()
    local left = -ang:Right()
    local s = d.size
    if d.shape == 1 then
        -- record k's ring i (bit 1 << i) on the place (i * m + k) mod count, place p at p * 360 / count degrees from the
        -- entity's forward towards its left (func_8C088000 on the record turned by k * 360 / count)
        local n, m = O.CircleSplit(d.count)
        for k = 0, m - 1 do
            for i = 1, n do
                local place = (i * m + k) % d.count
                local a = math.rad(place * 360 / d.count)
                local p = Vector(pos)
                p:Add(fwd * (s * math.cos(a)))
                p:Add(left * (s * math.sin(a)))
                out[#out + 1] = { record = k, bit = bit.lshift(1, i), place = place, pos = p }
            end
        end
        return out
    end
    local groups = O.RecordCount(d)
    for g = 0, groups - 1 do
        local k = math.min(O.LINE_GROUP, d.count - O.LINE_GROUP * g)
        local centre = O.LINE_GROUP * g + math.floor((k - 1) / 2)
        for i = 0, k - 1 do
            local rel = (i % 2 == 1) and (i + 1) / 2 or -(i / 2)
            local place = centre + rel
            local p = Vector(pos)
            p:Add(fwd * (s * (place - (d.count - 1) / 2)))
            out[#out + 1] = { record = g, bit = bit.lshift(1, i), place = place, pos = p }
        end
    end
    return out
end

-- THE PICK HULL (0.9.4.1; the owner on 0.9.4: "selecting any object in the Context menu (C Key) is very difficult.
-- Nothing can be moved after being added."). 0.9.4 made a frozen physics box of the hull, then SOLID_VPHYSICS; the
-- likely cause (UNVERIFIED, not measurable offline): Garry's Mod traces such an entity against its MODEL's collision
-- (models/hunter/blocks/cube025x025x025, 12 HU at the centre; the client had no physics object at all), so a line or
-- circle could only be picked at its middle, and nothing made a trace hit the rest of it. Now, for every
-- object (entities/gsa1_base.lua, sv_objects.lua O.ApplyHull, cl_objects.lua):
--   * the hull is the WHOLE object in the entity's frame (x forward, y left, z up: a line's full length, a circle's
--     diameter, a box's size; rings padded to 24 HU around each ring) - O.Hull;
--   * SOLID_OBB with these collision bounds (both realms: the collision bounds and the solid type are networked) and
--     Entity:EnableCustomCollisions (FSOLID_CUSTOMRAYTEST | FSOLID_CUSTOMBOXTEST), so the engine asks ENT:TestCollision
--     for every trace that reaches the box (the GMod wiki, ENTITY:TestCollision: "must have Entity:EnableCustomCollisions
--     enabled ... should have SOLID_OBB or SOLID_VPHYSICS ... collision bounds set accordingly"; the pattern of GMod's own
--     lua/entities/widget_base.lua: COLLISION_GROUP_WORLD, EnableCustomCollisions, a TestCollision that answers rays and
--     returns nothing for hull traces);
--   * TestCollision (O.PickTrace) answers only RAYS that start at the shoot position of a player holding the Physics Gun
--     or the Tool Gun (O.PICK_WEAPONS), or any client ray while the context menu (C) is open: the physgun's, the tool
--     gun's and the context menu's own traces hit the hull exactly (O.RayHull, the oriented box), bullets and every other
--     trace pass through; HULL traces (isbox: player and NPC movement) never hit it, so players walk through;
--   * COLLISION_GROUP_WORLD ("Doesn't collide with players/props", what the sandbox's "Disable Collisions" sets) for the
--     physics object: props and NPCs do not bump into it, the world still holds it while it is carried;
--   * a physics box (server, PhysicsInitBox: the Physics Gun moves physics objects) of the hull, at most O.PHYS_MAX from
--     the centre on each axis, frozen and without gravity; ENT:PhysgunPickup (the sandbox's GM:PhysgunPickup asks it)
--     allows the Physics Gun; GM:OnPhysgunPickup marks it held and lets it move; GM:PhysgunDrop freezes it again where it
--     was dropped and raises Moved (the clients move the game's object at once); a frozen box is frozen again within
--     0.1 s whatever unfroze it (the Physics Gun's reload, the duplicator);
--   * no custom collision check (Entity:SetCustomCollisionCheck + GM:ShouldCollide): that hook decides pairs of entities
--     (physics, movement), not which ray hits the hull, and the wiki warns it "can cause all physics to break"; the
--     collision group and TestCollision already give both halves;
--   * the context menu leaves out the properties that make no sense on a place in the game (O.NO_PROPERTIES: "Enable
--     Collisions" would make the hull solid for players again, gravity, drive, ignite, ...).
-- Only the owner can confirm in game (UNVERIFIED offline): that Garry's Mod's Physics Gun grabs a SOLID_OBB entity with a
-- physics box through a TestCollision hit, the context menu's halo / menu on the hull, and that nothing else (an
-- addon's traces from a player holding the Physics Gun) is bothered by the hull.
O.PICK_PAD = 8                       -- HU added around a ring's 16 (a ring is small to aim at)
O.PICK_WEAPONS = { weapon_physgun = true, gmod_tool = true }
O.PICK_START = 72                    -- HU: a ray starting this close to an editing player's shoot position is his
O.PHYS_MAX = 2048                    -- HU: the physics box's half size at most (a line of 128 rings 400 HU apart is
                                     -- 50,800 HU long: the traces use the whole hull, the physics a part of it)

-- the entity's box (local): the whole object (see above)
function O.Hull(d)
    local c = O.BY_CLASS[d.class or ""] or {}
    if c.mins then return Vector(c.mins), Vector(c.maxs) end
    local r = (c.ring or 16) + O.PICK_PAD
    if d.type == O.TYPE.O_GRING and d.shape == 0 then
        local half = d.size * (d.count - 1) / 2 + r
        return Vector(-half, -r, -r), Vector(half, r, r)
    elseif d.type == O.TYPE.O_GRING then
        local e = d.size + r
        return Vector(-e, -e, -r), Vector(e, e, r)
    end
    return Vector(-r, -r, -r), Vector(r, r, r)
end

-- the physics box of a hull (at most O.PHYS_MAX from the centre on each axis)
function O.PhysBox(mins, maxs)
    local L = O.PHYS_MAX
    return Vector(math.max(mins.x, -L), math.max(mins.y, -L), math.max(mins.z, -L)),
        Vector(math.min(maxs.x, L), math.min(maxs.y, L), math.min(maxs.z, L))
end

-- the hull as the entity's collision (both realms: the server's is networked, a client sets the same at once): SOLID_OBB
-- with the hull as its collision bounds and custom collisions (gsa1_base.lua TestCollision)
function O.ApplyPickShape(ent, mins, maxs)
    if not mins then mins, maxs = O.Hull(O.Describe(ent)) end
    if ent.SetSolid then ent:SetSolid(SOLID_OBB or 3) end
    if ent.SetCollisionBounds then ent:SetCollisionBounds(mins, maxs) end
    if ent.EnableCustomCollisions then ent:EnableCustomCollisions(true) end
end

-- a trace starting at `start` is an editing one: from the shoot position of a player holding the Physics Gun or the
-- Tool Gun, or (client) any while the context menu is open
function O.EditorRay(start)
    if not start then return false end
    if CLIENT and g_ContextMenu and g_ContextMenu.IsVisible and g_ContextMenu:IsVisible() then return true end
    local list = (player and player.GetAll) and player.GetAll() or {}
    if CLIENT and LocalPlayer then list = { LocalPlayer(), unpack(list) } end
    local lim = O.PICK_START * O.PICK_START
    for _, ply in ipairs(list) do
        if IsValid(ply) and ply.GetActiveWeapon then
            local w = ply:GetActiveWeapon()
            if IsValid(w) and O.PICK_WEAPONS[w:GetClass()] then
                local sp = (ply.GetShootPos and ply:GetShootPos()) or (ply.EyePos and ply:EyePos())
                if sp then
                    local dx, dy, dz = start.x - sp.x, start.y - sp.y, start.z - sp.z
                    if dx * dx + dy * dy + dz * dz <= lim then return true end
                end
            end
        end
    end
    return false
end

-- a ray (start, start + delta) against the entity's oriented hull (its collision bounds in its own frame): the trace
-- result GMod takes from TestCollision ({HitPos, Fraction, Normal}), or nil (a miss, or a ray starting inside)
function O.RayHull(ent, start, delta)
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local f, r, u = ang:Forward(), ang:Right(), ang:Up()
    local axes = { f, -r, u }
    local rel = start - pos
    local o = { rel:Dot(f), -rel:Dot(r), rel:Dot(u) }
    local dv = { delta:Dot(f), -delta:Dot(r), delta:Dot(u) }
    local lo, hi = { mins.x, mins.y, mins.z }, { maxs.x, maxs.y, maxs.z }
    local t0, t1, axis, sign = 0, 1, nil, 0
    for i = 1, 3 do
        if math.abs(dv[i]) < 1e-9 then
            if o[i] < lo[i] or o[i] > hi[i] then return nil end
        else
            local a, b, sg = (lo[i] - o[i]) / dv[i], (hi[i] - o[i]) / dv[i], -1
            if a > b then a, b, sg = b, a, 1 end
            if a > t0 then t0, axis, sign = a, i, sg end
            if b < t1 then t1 = b end
            if t0 > t1 then return nil end
        end
    end
    if not axis then return nil end
    return { HitPos = start + delta * t0, Fraction = t0, Normal = axes[axis] * sign }
end

-- ENT:TestCollision's answer: the hull for an editing ray, nothing for anything else (hull traces included)
function O.PickTrace(ent, start, delta, isbox)
    if isbox or not O.EditorRay(start) then return nil end
    return O.RayHull(ent, start, delta)
end

-- may ply pick ent with the Physics Gun (ENT:PhysgunPickup; the sandbox has checked persistence before)
function O.MayPick(ply, ent)
    return O.IsObject(ent)
end

-- the context menu's properties that make no sense on a G-SA1 object (the gamemode's CanProperty)
O.NO_PROPERTIES = { collision = true, gravity = true, drive = true, keepupright = true, ignite = true, extinguish = true,
                    statue = true, bonemanipulate = true, skin = true, bodygroups = true }
if hook and hook.Add then
    hook.Add("CanProperty", "gsa1_objects", function(ply, property, ent)
        if O.NO_PROPERTIES[property] and O.IsObject(ent) then return false end
    end)
end

-- where a new entity goes for a trace and a player: position, angles (yaw = the player's; the ground box upright, its
-- base AT the surface; the others lifted along the surface's normal)
function O.SpawnPlace(class, tr, yaw)
    local c = O.BY_CLASS[class] or {}
    local pos = Vector(tr.HitPos)
    local lift = c.lift or 0
    if c.type == O.TYPE.ITEMBOX then
        pos.z = pos.z + 0.5
    elseif tr.HitNormal then
        pos:Add(tr.HitNormal * lift)
    end
    return pos, Angle(0, math.NormalizeAngle(tonumber(yaw) or 0), 0)
end

-- the server's check of a report ---------------------------------------------------------------------------------------
O.AGE_ERROR = 0.3        -- s: how far the report's age may be off (the client's frame, the network's jitter)
O.GROUP_LAG = 0.5        -- s: a group's ring is taken this long at most before the touch its bits come with (the ring's
                         -- 16-step sparkle + 2: measured 18 steps, feat_objects_binding_test; 0.5 s with a margin)
O.MAX_AGE = 2.0          -- s: older reports are not believed
O.SPEED_CAP = 6000       -- HU/s: the fastest a character goes (Light Speed Dash) - the speed slack's ceiling
O.REACH = {              -- HU (gsa1_094_items.md 5.2, review R.3)
    ring_body = 64,      -- a ring touches the character's collision
    box_body = 80,       -- a box broken by the body (Big: 62 HU measured)
    projectile = 80,     -- the attacker (E-102's shot) near the box ...
    projectile_char = 1040,   -- ... and the character within its lock-on reach (250 units)
    unknown = 80,        -- no touch seen: the object's place
    unknown_far = 1040,  -- ... E-102 and Big
    magnet = 320,        -- the Magnetic Barrier pulls a ring from 50 units (200 HU); libsa1's set_test 'magnet' measured a
                         -- pulled ring caught 275 HU from its place while the character ran away (0.9.4 verifier): + margin
    magnet_att = 64,     -- the pulled ring (the attacker) at the touch
}

local function vdist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
O.Dist = vdist

-- distance from p to the segment a..b (tables or Vectors with x, y, z)
local function seg_dist(p, a, b)
    local abx, aby, abz = b.x - a.x, b.y - a.y, b.z - a.z
    local l2 = abx * abx + aby * aby + abz * abz
    local t = 0
    if l2 > 1e-9 then
        t = math.Clamp(((p.x - a.x) * abx + (p.y - a.y) * aby + (p.z - a.z) * abz) / l2, 0, 1)
    end
    local dx, dy, dz = p.x - (a.x + abx * t), p.y - (a.y + aby * t), p.z - (a.z + abz * t)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- the character's path (hist: { {t, x, y, z}, ... } oldest first) around time t (+- err): the shortest distance from p to
-- it, and the speed there. Outside the history the nearest end counts, with speed x the time beyond it added
function O.PathDistance(hist, t, p, err)
    local n = #hist
    if n == 0 then return math.huge, 0 end
    err = err or O.AGE_ERROR
    local lo, hi = t - err, t + err
    local function at(time)
        if time <= hist[1].t then return hist[1] end
        if time >= hist[n].t then return hist[n] end
        for i = 2, n do
            local b = hist[i]
            if b.t >= time then
                local a = hist[i - 1]
                local f = (b.t > a.t) and (time - a.t) / (b.t - a.t) or 0
                return { t = time, x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, z = a.z + (b.z - a.z) * f }
            end
        end
        return hist[n]
    end
    local pts = { at(lo) }
    for i = 1, n do
        if hist[i].t > lo and hist[i].t < hi then pts[#pts + 1] = hist[i] end
    end
    pts[#pts + 1] = at(hi)
    local best = math.huge
    if #pts == 1 then best = vdist(p, pts[1]) end
    for i = 2, #pts do best = math.min(best, seg_dist(p, pts[i - 1], pts[i])) end
    -- the speed near t (the samples around it)
    local speed = 0
    for i = 2, n do
        local a, b = hist[i - 1], hist[i]
        if b.t > a.t and b.t >= lo - 0.5 and a.t <= hi + 0.5 then
            speed = math.max(speed, vdist(a, b) / (b.t - a.t))
        end
    end
    speed = math.min(speed, O.SPEED_CAP)
    -- a report from beyond the history's ends (just spawned, or the packets came late): the time beyond, at that speed
    local beyond = math.max(0, hist[1].t - hi, lo - hist[n].t)
    return best, speed, beyond
end

-- the report e (kind, index, bits, age, pos = the touch, cause, att = the attacker) about object obj ({type, pos, d
-- (O.Describe), state, broken, bits = {[record] = its bits}, rings = O.RingPositions}) from a character of kind ckind with
-- path hist (hist.synthetic: single player's stand-in of one point),
-- received at `now` with the slack (HU). Returns ok, why (a plain sentence when not), the bits it adds (USERBITS)
function O.CheckEvent(e, obj, hist, now, slack, ckind)
    local T, EV, C = O.TYPE, O.EV, O.CAUSE
    local kind, typ = e.kind, obj.type
    local age = tonumber(e.age) or -1
    if not (age >= 0 and age <= O.MAX_AGE) then return false, string.format("a report %.2f s old", age) end
    local targets, add, added = {}, 0, {}
    if kind == EV.GONE then
        if typ ~= T.RING and typ ~= T.ITEMBOX_AIR then return false, "this object is never taken whole" end
        if (obj.state or 1) == 0 then return false, "it was taken already" end
        targets[1] = obj.pos
    elseif kind == EV.BROKEN then
        if typ ~= T.ITEMBOX then return false, "only an item box on the ground breaks" end
        if obj.broken then return false, "it was broken already" end
        targets[1] = obj.pos
    elseif kind == EV.USERBITS then
        if typ ~= T.O_GRING then return false, "only a ring line or circle has rings of its own" end
        local k = tonumber(e.index) or -1
        if k < 0 or k >= O.RecordCount(obj.d) then return false, "no such part of the ring group" end
        local mask = O.RecordMask(obj.d, k)
        local have = (obj.bits and obj.bits[k]) or 0
        add = bit.band(tonumber(e.bits) or 0, bit.bnot(have))
        if add == 0 then return false, "no ring that was not taken already" end
        if bit.band(add, bit.bnot(mask)) ~= 0 then return false, "a ring the group does not have" end
        -- 0.9.4.1: the touch a USERBITS event carries is the record's LAST touched ring (libsa1 freezes its latch when a
        -- ring of the group is taken), the bits it adds belong to rings taken up to ~18 steps earlier (a ring's bit
        -- comes after its sparkle): at a run up to ~180 HU from them (the owner's 0.9.4 refusals, 67-226 HU). The touch
        -- is checked against EVERY ring of the record; each added ring against the path before the touch (below)
        for _, r in ipairs(obj.rings or {}) do
            if r.record == k then
                targets[#targets + 1] = r.pos
                if bit.band(r.bit, add) ~= 0 then added[#added + 1] = r.pos end
            end
        end
        if #added == 0 then return false, "no ring of the group there" end
    else
        return false, "not a report the server takes"
    end
    -- the reach per cause: the nearest of the object's places that changed
    local touch, att = e.pos, e.att or e.pos
    local function nearest(p)
        local best = math.huge
        for _, q in ipairs(targets) do best = math.min(best, vdist(p, q)) end
        return best
    end
    local rings = typ == T.RING or typ == T.O_GRING
    local far = ckind == O.KIND_GAMMA or ckind == O.KIND_BIG
    local cause = tonumber(e.cause) or C.UNKNOWN
    local R = O.REACH
    local path_extra = 0             -- UNKNOWN: the touch is the object's place; the path must pass within the reach
    if cause == C.BODY then
        local reach = rings and R.ring_body or R.box_body
        if nearest(touch) > reach then
            return false, string.format("the touch was %.0f units from it (at most %d)", nearest(touch), reach)
        end
    elseif cause == C.MAGNET and rings then
        if nearest(touch) > R.magnet then
            return false, string.format("a pulled ring %.0f units away (at most %d)", nearest(touch), R.magnet)
        end
        if vdist(att, touch) > R.magnet_att then
            return false, string.format("the pulled ring %.0f units from the character (at most %d)", vdist(att, touch),
                R.magnet_att)
        end
    elseif cause == C.PROJECTILE then
        if nearest(att) > R.projectile then
            return false, string.format("the shot was %.0f units from it (at most %d)", nearest(att), R.projectile)
        end
        if nearest(touch) > R.projectile_char then
            return false, string.format("the shooter was %.0f units from it (at most %d)", nearest(touch),
                R.projectile_char)
        end
    else
        -- no touch seen (libsa1 gives the object's place): the character's path within the reach of the object
        path_extra = far and R.unknown_far or R.unknown
        touch = added[1] or targets[1]
    end
    -- the touch against the character's own path at the report's age (never the player's position now)
    local d, speed, beyond = O.PathDistance(hist or {}, now - age, touch, O.AGE_ERROR)
    if d == math.huge then return false, "the server has no position of this character yet" end
    local allowed = (tonumber(slack) or 128) + path_extra + speed * (beyond or 0)
    if d > allowed then
        return false, string.format("the character was %.0f units from that place then (at most %.0f)", d, allowed)
    end
    -- a ring group's added rings: each on the character's path within GROUP_LAG before the touch (a ring is taken by
    -- touching it; a pulled one from the Magnetic Barrier's reach). Not with the stand-in path of single player
    if kind == EV.USERBITS and not (hist and hist.synthetic) then
        local reach = cause == C.MAGNET and R.magnet or (cause == C.UNKNOWN and path_extra) or R.ring_body
        local mid, half = now - age - O.GROUP_LAG / 2, O.GROUP_LAG / 2 + O.AGE_ERROR
        for _, q in ipairs(added) do
            local d2, sp2, beyond2 = O.PathDistance(hist or {}, mid, q, half)
            local allowed2 = (tonumber(slack) or 128) + reach + sp2 * (beyond2 or 0)
            if d2 > allowed2 then
                return false, string.format("the character passed %.0f units from a ring it took (at most %.0f)", d2,
                    allowed2)
            end
        end
    end
    return true, nil, add
end

-- the context menu (properties: both realms) ----------------------------------------------------------------------------
if properties and properties.Add then
    properties.Add("gsa1_contents", {
        MenuLabel = "Contents",
        Order = 600,
        MenuIcon = "icon16/box.png",
        Filter = function(self, ent, ply)
            if not O.IsObject(ent) or not ent.GetContents then return false end
            if gamemode and gamemode.Call and not gamemode.Call("CanProperty", ply, "gsa1_contents", ent) then return false end
            return true
        end,
        MenuOpen = function(self, option, ent, tr)
            local sub = option:AddSubMenu()
            for _, c in ipairs(O.CONTENTS) do
                local opt = sub:AddOption(c.title)
                if opt.SetRadio then opt:SetRadio(true) end
                if opt.SetChecked then opt:SetChecked(ent:GetContents() == c.value) end
                if opt.SetIsCheckable then opt:SetIsCheckable(true) end
                opt.OnChecked = function(s, checked) if checked then self:SetContents(ent, c.value) end end
            end
        end,
        Action = function(self, ent) end,
        SetContents = function(self, ent, v)
            self:MsgStart()
            net.WriteEntity(ent)
            net.WriteUInt(v, 4)
            self:MsgEnd()
        end,
        Receive = function(self, length, ply)
            local ent = net.ReadEntity()
            local v = net.ReadUInt(4)
            if not properties.CanBeTargeted(ent, ply) or not self:Filter(ent, ply) then return end
            if v > 8 then return end
            ent:SetContents(v)
        end,
    })
    properties.Add("gsa1_respawn", {
        MenuLabel = "Respawn now",
        Order = 601,
        MenuIcon = "icon16/arrow_refresh.png",
        Filter = function(self, ent, ply)
            if not O.IsObject(ent) then return false end
            if gamemode and gamemode.Call and not gamemode.Call("CanProperty", ply, "gsa1_respawn", ent) then return false end
            return true
        end,
        Action = function(self, ent)
            self:MsgStart()
            net.WriteEntity(ent)
            self:MsgEnd()
        end,
        Receive = function(self, length, ply)
            local ent = net.ReadEntity()
            if not properties.CanBeTargeted(ent, ply) or not self:Filter(ent, ply) then return end
            if O.Respawn then O.Respawn(ent, "Respawn now") end
        end,
    })
end
