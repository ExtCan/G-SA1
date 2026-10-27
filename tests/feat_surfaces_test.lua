-- feat_surfaces_test.lua - the surfaces feature's addon side (addon/lua/gsa1/feat/sh_surfaces.lua and cl_surfaces.lua,
-- with cl_module.lua's hooks: sadc docs/research/gsa1_060_dig.md F6 with its review R4 G9 / G10) in Garry's Mod's own
-- LuaJIT with a mocked GMod (tests/lua_mock.lua) and a mock of the module's surfaces functions (bind_surfaces.cpp's Lua
-- API, every call recorded). Checks: the ConVars (each with a control on the page), the overrides file (parse, write,
-- bad lines), the table going to the module with every load of the map's collision and its hash into the world's key,
-- a setting's change loading the world again, the page (the map's types by area from SurfaceInfo, a type's kind changed
-- with the box, Apply, Reset to the built-in table, the live "under the character" line, "needs G-SA1 module 0.8.0"
-- without the module's part), the changes surviving a reload of the addon, the session log's surfaces line when a map
-- is applied, and the map job's materials read from the map's own pak ("BSP") when "GAME" lacks them.
-- 0.9.2 (sadc docs/research/gsa1_090_surfaces.md F3 with its review C3 / C5; plan gsa1_090_plan.md 6.9): every SA1 ground
-- kind - NormalizeKinds("Snow, fast"), Describe("wallslide"), a 0.8 surfaces.txt read unchanged, the page's checklist
-- (12 kinds with their explanations, footprints hidden, snow "slow to speed up", "walls only", the precedence note, a
-- Normal button), the live line decoding every kind, each kind's share in the summary, feature version 2.
--   lua_host tests/feat_surfaces_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_surfaces_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

-- only this feature's files (another feature's files have their own tests)
local real_list = host_list
host_list = function(dir, pat)
    local out = real_list and real_list(dir, pat) or {}
    if string.find(dir, "/gsa1/feat$") then
        local keep = {}
        for _, n in ipairs(out) do
            if string.find(n, "_surfaces%.lua$") then keep[#keep + 1] = n end
        end
        return keep
    end
    return out
end

-- timers: recorded, run by the test
local timers = {}
timer.Create = function(name, delay, reps, fn) timers[name] = fn end
timer.Simple = function() end

-- the module's surfaces functions, recorded
local SF = { calls = {}, hash = 1000 }
local function last(name)
    for i = #SF.calls, 1, -1 do
        if SF.calls[i][1] == name then return SF.calls[i] end
    end
end
local function n_of(name)
    local n = 0
    for _, c in ipairs(SF.calls) do n = n + (c[1] == name and 1 or 0) end
    return n
end
local INFO = { map = "gm_construct", enabled = true, dig_anywhere = false, materials = 204, materials_used = 193,
    vmt_found = 210, vmt_missing = 2, vmt_patches = 153, walkable = 1000, dig = 953, slippery = 0, sand = 0,
    types = { { name = "grass", kinds = "dig", how = "listed", area = 932, tris = 16303, chain = "grass > dirt", letter = "U" },
              { name = "concrete", kinds = "normal", how = "", area = 46, tris = 8858, chain = "concrete", letter = "C" },
              { name = "sand", kinds = "dig", how = "listed", area = 21, tris = 4154, chain = "sand > dirt", letter = "N" },
              { name = "zzz_unused", kinds = "normal", how = "", area = 0, tris = 0, chain = "zzz_unused", letter = "" } } }
local function add_surfaces(G)
    function G.SetSurfaceTable(list, o)
        SF.calls[#SF.calls + 1] = { "SetSurfaceTable", list, o }
        local key = table.concat(list or {}, ";") .. tostring(o and o.enabled) .. tostring(o and o.dig_anywhere)
        local changed = key ~= SF.key
        if changed then SF.hash = SF.hash + 1 end
        SF.key = key
        return true, SF.hash, changed, 0
    end
    function G.SurfaceDefaults()
        SF.calls[#SF.calls + 1] = { "SurfaceDefaults" }
        return { grass = "dig", dirt = "dig", sand = "dig", ice = "slippery", carpet = "normal", rock = "normal" },
            { D = "dig", N = "dig", U = "dig", J = "dig" }
    end
    function G.SurfaceKind(name, letter)
        SF.calls[#SF.calls + 1] = { "SurfaceKind", name, letter }
        if name == "grass" or name == "sand" then return "dig", "listed" end
        if letter == 68 or letter == "D" then return "dig", "letter D" end
        return "normal", ""
    end
    function G.SurfaceInfo(out)
        SF.calls[#SF.calls + 1] = { "SurfaceInfo" }
        return INFO
    end
    function G.MapApply()
        return true, { map = "gm_construct", triangles = 32902, props_placed = 4, brush_models = 6, one_way_solids = 3,
            thin_walls = 10, from_cache = true, prepared = true, prepare_ms = 90, grid_triangles = 40000, props_note = "",
            props_missing = 0, prop_models_missing = 0, prop_models = 3, cache_note = "" }
    end
end

-- 1. loading -----------------------------------------------------------------------------------------------------------
GSA1 = nil
local G = M.module({ features = { surfaces = 2 } })
add_surfaces(G)
M.included = {}
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
local ferr = GSA1 and GSA1.FeatureFileErrors or {}
local S = GSA1 and GSA1.Surfaces
check(ok_load and #ferr == 0 and S ~= nil and S.cv ~= nil, "the autorun loads sh_surfaces.lua and cl_surfaces.lua (%s)",
    ok_load and table.concat(GSA1.FeatureFiles or {}, " ") or tostring(err_load or ferr[1]))
if not (ok_load and S and S.cv) then return done() end
local WANT = { gsa1_surfaces = { "1", 0, 1 }, gsa1_dig_anywhere = { "0", 0, 1 }, gsa1_surface_overrides = { "" } }
local bad = {}
for name, w in pairs(WANT) do
    local c = M.convars[name]
    if not (c and c.client and c.save and c.v == w[1] and c.lo == w[2] and c.hi == w[3] and GSA1.CONVARS[name]) then
        bad[#bad + 1] = name
    end
end
check(#bad == 0, "the ConVars gsa1_surfaces (1), gsa1_dig_anywhere (0) and gsa1_surface_overrides (a copy for the log): "
    .. "client, archived, in GSA1.CONVARS%s", #bad > 0 and (": wrong " .. table.concat(bad, " ")) or "")
check(n_of("SetSurfaceTable") == 0 and n_of("SurfaceDefaults") == 0, "nothing calls the module while the files load")

-- 2. the pure part ----------------------------------------------------------------------------------------------------
check(S.NormalizeKinds("Sand, Dig") == "dig,sand" and S.NormalizeKinds("normal") == "normal" and S.NormalizeKinds("ice") ==
    "slippery" and S.NormalizeKinds("dig,lava") == nil and S.Describe("dig,sand") == "diggable, slow sand" and
    S.Describe("normal") == "normal ground", "kinds: \"Sand, Dig\" -> dig,sand; aliases; unknown words refused; described "
    .. "in words")
local parsed, nbad = S.Parse("# header\nconcrete = dig\n  Grass=normal  \nlava = lava\n=dig\nice = sand,dig # a comment\n")
local text = S.Serialize(parsed)
local again = S.Parse(text)
check(parsed.concrete == "dig" and parsed.grass == "normal" and parsed.ice == "dig,sand" and nbad == 2 and
    again.concrete == "dig" and again.ice == "dig,sand" and string.find(text, "^# G%-SA1 ground types") ~= nil and
    table.concat(S.ToList(parsed), ";") == "concrete=dig;grass=normal;ice=dig,sand",
    "the overrides file: 3 lines taken, 2 bad skipped, comments; written sorted with a header and read back")
-- 0.9.2: every SA1 ground kind
check(S.NormalizeKinds and S.NormalizeKinds("Snow, fast") == "snow,fast" and S.Describe("wallslide") == "slide-off wall"
    and S.NormalizeKinds("no_land speed_path|boost") == "fast,speedpath,noland" and
    S.Describe("snow,fast,slide,speedpath,stairs,noland") == "snow, fast ground, sliding floor, speed track, stairs, not a floor",
    "0.9.2's kinds: \"Snow, fast\" -> %s (0.9.1: nil); Describe(\"wallslide\") = \"%s\"; aliases; described in words",
    tostring(S.NormalizeKinds("Snow, fast")), tostring(S.Describe("wallslide")))
-- a file 0.8 / 0.9.1 wrote: read unchanged
local OLD = "# G-SA1 ground types: your changes to the Surfaces page's table (Options > G-SA1 > Surfaces).\n"
    .. "# One \"surface type = kinds\" per line; kinds: normal, dig, slippery, sand, hurt, noclimb (several: dig,sand).\n"
    .. "antlionsand = normal\nconcrete = dig\nice = sand\nmetal = hurt,noclimb\nmud = dig,sand\nplaster = slippery\n"
    .. "tile = dig,slippery,sand,hurt,noclimb\n"
local WANT08 = { antlionsand = "normal", concrete = "dig", ice = "sand", metal = "hurt,noclimb", mud = "dig,sand",
                 plaster = "slippery", tile = "dig,slippery,sand,hurt,noclimb" }
local old_t, old_bad = S.Parse(OLD)
local same08, n08 = old_bad == 0, 0
for k, v in pairs(old_t) do
    n08 = n08 + 1
    same08 = same08 and WANT08[k] == v
end
local body = string.gsub(S.Serialize(old_t), "^#[^\n]*\n#[^\n]*\n", "")
local old_body = string.gsub(OLD, "^#[^\n]*\n#[^\n]*\n", "")
check(same08 and n08 == 7 and body == old_body,
    "a surfaces.txt of 0.8 / 0.9.1 (every old word and combination): %d lines read unchanged and written back the same", n08)
-- the checklist's data
local ids, visible, in_order, tips = {}, 0, true, true
local order_set = {}
for _, w in ipairs(S.ORDER or {}) do order_set[w] = true end
for _, k in ipairs(S.KINDS or {}) do
    ids[k.id] = k
    if not k.hidden then visible = visible + 1 end
    in_order = in_order and order_set[k.id] == true
    tips = tips and type(k.tip) == "string" and #k.tip > 10 and type(k.bit) == "number"
end
check(#(S.KINDS or {}) == 13 and #(S.ORDER or {}) == 13 and visible == 12 and in_order and tips and ids.footprints and
    ids.footprints.hidden and ids.snow and ids.snow.title == "Snow (slow to speed up)" and
    string.find(ids.snow.tip, "a seventh of the acceleration, you stop normally", 1, true) ~= nil and
    string.find(ids.noland.title, "walls only", 1, true) ~= nil and string.find(ids.wallslide.title, "walls only", 1, true)
    ~= nil and string.find(S.PRECEDENCE or "", "snow, ice, slow sand and fast ground only the first counts", 1, true) ~= nil,
    "the checklist: 13 kinds (12 shown, footprints hidden until a footprint task exists), each with an explanation; snow "
    .. "\"Snow (slow to speed up)\" (C5); \"walls only\" on not a floor / slide-off wall; the precedence note")
local every = 0
for _, k in ipairs(S.KINDS or {}) do every = every + k.bit end
local dec = S.DecodeGame and S.DecodeGame(every) or {}
check(#dec == 13 and dec[1] == "diggable" and dec[13] == "footprints" and #S.DecodeGame(1) == 0 and S.WithKind and
    S.WithKind("dig", "snow", true) == "dig,snow" and S.WithKind("dig,snow", "dig", false) == "snow" and
    S.WithKind("snow", "snow", false) == "normal" and S.HasKind("fast,noland", "noland") and not S.HasKind("normal", "dig"),
    "the game's SA1_SURFACE_* bits decode to every kind (%s); a kind ticked / unticked in a kinds string",
    table.concat(dec, ", "))

-- 3. the table goes with every load of the map's collision ---------------------------------------------------------------
GSA1.LoadModule()
local o = GSA1.MapOptions()
local st = last("SetSurfaceTable")
check(st and o.world_key == " surf1001" and type(st[2]) == "table" and #st[2] == 0 and st[3].enabled == true and
    st[3].dig_anywhere == false and o.static_props ~= nil,
    "GSA1.MapOptions(): the table (no changes) and the switches go to the module, its hash into the world's key (\"%s\")",
    tostring(o.world_key))
local started = {}
GSA1.StartWorld = function(force) started[#started + 1] = force return true end
GSA1.World.state = "applied"
M.convars.gsa1_dig_anywhere:SetString("1")
local tmr = timers.gsa1_surfaces_reload
if tmr then tmr() end
st = last("SetSurfaceTable")
check(tmr ~= nil and #started == 1 and started[1] == false and st[3].dig_anywhere == true,
    "gsa1_dig_anywhere 1: the map's collision loads again (StartWorld) with dig anywhere on")
M.convars.gsa1_dig_anywhere:SetString("0")
if timers.gsa1_surfaces_reload then timers.gsa1_surfaces_reload() end

-- 4. the page -----------------------------------------------------------------------------------------------------------
local made = {}
local METHODS
local function standin(kind)
    local P = { kind = kind, calls = {} }
    made[#made + 1] = P
    return setmetatable(P, { __index = function(t, k)
        if METHODS[k] then return METHODS[k] end
        if type(k) ~= "string" or not string.match(k, "^%u") then return nil end
        return function(self, ...)
            local child = standin(k)
            t.calls[#t.calls + 1] = { k, ... }
            t.calls[#t.calls].ret = child
            return child
        end
    end })
end
METHODS = {
    SetText = function(self, s) self.text = s end,
    SetValue = function(self, s) self.value = s end,
    AddLine = function(self, ...)
        local l = standin("line")
        l.cols = { ... }
        self.lines = self.lines or {}
        self.lines[#self.lines + 1] = l
        return l
    end,
    Clear = function(self) self.lines = {} end,
    SetChecked = function(self, v) self.checked = v end,
    SetTooltip = function(self, s) self.tip = s end,
}
vgui.Create = function(cls) return standin(cls) end
M.menu = {}
M.run_hook("PopulateToolMenu")
local entry
for _, e in ipairs(M.menu) do
    if e.class == "gsa1_feat_surfaces" then entry = e end
end
check(entry and entry.name == "Surfaces" and entry.tab == "Options" and entry.category == "G-SA1",
    "the page Options -> G-SA1 -> Surfaces")
if not entry then return done() end
local panel = standin("DForm")
entry.cpanel(panel)
local bound, helps = {}, {}
local kindbox, normal_btn = {}, nil
local TITLE = {}
for _, k in ipairs(S.KINDS or {}) do TITLE[k.title] = k end
for _, call in ipairs(panel.calls) do
    if call[1] == "CheckBox" and call[3] then bound[call[3]] = true end
    if call[1] == "CheckBox" and not call[3] and TITLE[call[2]] then kindbox[TITLE[call[2]].id] = call.ret end
    if call[1] == "Button" and string.find(tostring(call[2]), "^Normal") then normal_btn = call.ret end
    if call[1] == "Help" or call[1] == "ControlHelp" then helps[#helps + 1] = tostring(call[2]) end
end
local list, live
for _, P in ipairs(made) do
    if P.kind == "DListView" then list = P end
    if P.kind == "Help" and rawget(P, "Think") then live = P end
end
local page_text = table.concat(helps, " ")
local nboxes, ntips, foot = 0, 0, kindbox.footprints ~= nil
local KIND = {}
for _, k in ipairs(S.KINDS or {}) do KIND[k.id] = k end
for id, cb in pairs(kindbox) do
    nboxes = nboxes + 1
    if KIND[id] and cb.tip == KIND[id].tip then ntips = ntips + 1 end
end
check(bound.gsa1_surfaces and bound.gsa1_dig_anywhere and list and live and nboxes == 12 and ntips == 12 and not foot and
    normal_btn and string.find(page_text, "could not be built", 1, true) == nil and
    string.find(page_text, "only the first counts", 1, true) ~= nil and string.find(page_text, "walls only", 1, true) ~= nil,
    "the page builds with every kind: check boxes for gsa1_surfaces and gsa1_dig_anywhere, the list, the live line, %d "
    .. "kind boxes with their explanations as tooltips (footprints hidden), the precedence and walls-only notes, a Normal "
    .. "button", nboxes)
if not (list and live and kindbox.dig and kindbox.snow and kindbox.noland and normal_btn) then return done() end
local rows = {}
for _, l in ipairs(list.lines or {}) do rows[#rows + 1] = l.gsa1Name end
local first = list.lines and list.lines[1]
check(rows[1] == "grass" and rows[2] == "concrete" and rows[3] == "sand" and first and first.cols[2] == "diggable" and
    first.cols[3] == "93.2%" and #rows >= 8,
    "the list: the map's types by walkable ground (%s ...), then the built-in table's; grass %s on %s of the ground",
    table.concat(rows, " ", 1, math.min(#rows, 4)), first and tostring(first.cols[2]) or "?",
    first and tostring(first.cols[3]) or "?")
-- a box ticked while no type is selected: nothing changes, the box goes back
kindbox.snow.checked = true
kindbox.snow.OnChange(kindbox.snow, true)
check(next(S.overrides) == nil and kindbox.snow.checked == false, "a kind ticked with no type selected changes nothing")
-- concrete: diggable, then snow and not a floor, then snow off, then Normal, then diggable again
local concrete
for _, l in ipairs(list.lines) do
    if l.gsa1Name == "concrete" then concrete = l end
end
list.OnRowSelected(list, 2, concrete)
local unticked = not kindbox.dig.checked and not kindbox.snow.checked
kindbox.dig.OnChange(kindbox.dig, true)
local file_text = M.files[S.FILE] or ""
check(unticked and S.overrides.concrete == "dig" and string.find(file_text, "concrete = dig", 1, true) ~= nil and
    M.convars.gsa1_surface_overrides.v == "concrete=dig" and S.pending and kindbox.dig.checked,
    "concrete selected (no box ticked), Diggable ticked: kept in data/%s, copied to gsa1_surface_overrides (\"%s\"), "
    .. "waiting for Apply", S.FILE, M.convars.gsa1_surface_overrides.v)
local relisted
for _, l in ipairs(list.lines) do
    if l.gsa1Name == "concrete" then relisted = l end
end
check(relisted and relisted.cols[2] == "diggable *", "its line says diggable, marked as your change (\"%s\")",
    relisted and tostring(relisted.cols[2]) or "?")
kindbox.snow.OnChange(kindbox.snow, true)
kindbox.noland.OnChange(kindbox.noland, true)
local three = S.overrides.concrete
local ticks3 = kindbox.dig.checked and kindbox.snow.checked and kindbox.noland.checked and not kindbox.fast.checked
kindbox.snow.OnChange(kindbox.snow, false)
local two = S.overrides.concrete
check(three == "dig,snow,noland" and ticks3 and two == "dig,noland" and not kindbox.snow.checked and
    string.find(M.files[S.FILE] or "", "concrete = dig,noland", 1, true) ~= nil,
    "Snow and Not a floor ticked: \"%s\" (the boxes show it); Snow unticked: \"%s\"", tostring(three), tostring(two))
normal_btn.DoClick(normal_btn)
local cleared = S.overrides.concrete
local none_ticked = true
for _, cb in pairs(kindbox) do none_ticked = none_ticked and not cb.checked end
kindbox.dig.OnChange(kindbox.dig, true)
check(cleared == "normal" and none_ticked and S.overrides.concrete == "dig",
    "Normal clears the selected type's kinds (\"%s\", every box unticked); Diggable again: \"%s\"", tostring(cleared),
    tostring(S.overrides.concrete))
-- grass set to its built-in kind: no entry kept
local grass_line
for _, l in ipairs(list.lines) do
    if l.gsa1Name == "grass" then grass_line = l end
end
list.OnRowSelected(list, 1, grass_line)
local grass_dig = kindbox.dig.checked
kindbox.dig.OnChange(kindbox.dig, true)
check(grass_dig and S.overrides.grass == nil, "grass selected shows Diggable ticked; set to its built-in kind it keeps no entry")
-- Apply
started = {}
M.cmds.gsa1_surfaces_apply()
st = last("SetSurfaceTable")
check(#started == 1 and st and table.concat(st[2], ";") == "concrete=dig" and not S.pending,
    "Apply: the table with concrete=dig goes to the module and the map's collision loads again")
-- the live line
util.TraceLine = function(t)
    return { Hit = true, SurfaceProps = 7, HitPos = t.endpos }
end
util.GetSurfacePropName = function(i) return i == 7 and "grass" or "" end
util.GetSurfaceData = function(i) return { material = 85 } end
MASK_SOLID = 33570827
bit = bit or {}
GSA1.Char = { drawPos = Vector(-3120, 982, -44), state = { surface = 0x1001, ground = true } }
live.Think(live)
local line1 = live.text or ""
GSA1.Char.state.surface = 1
M.T = M.T + 1
live.Think(live)
local line2 = live.text or ""
GSA1.Char.state.surface = 0x1 + 0x8000 + 0x10000 + 0x400 + 0x20000 + 0x200
M.T = M.T + 1
live.Think(live)
local line3 = live.text or ""
GSA1.Char = nil
check(string.find(line1, "Under the character: grass (diggable)", 1, true) ~= nil and
    string.find(line1, "the game: diggable", 1, true) ~= nil and string.find(line2, "the game: normal ground", 1, true) ~= nil,
    "the live line: \"%s\" / then \"%s\"", line1, line2)
check(string.find(line3, "the game: snow, speed track, stairs, not a floor, footprints", 1, true) ~= nil,
    "the live line decodes every kind (0.9.2): \"%s\"", line3)
-- Reset
started = {}
M.cmds.gsa1_surfaces_reset()
st = last("SetSurfaceTable")
check(next(S.overrides) == nil and #st[2] == 0 and #started == 1 and
    string.find(M.files[S.FILE] or "", "concrete", 1, true) == nil,
    "Reset to the built-in table: no entries (file and module), the map's collision loads again")

-- 5. the session log: one line when a map is applied --------------------------------------------------------------------
GSA1.World.state = "ready"
GSA1.World.map = "gm_construct"
local okA = GSA1.ApplyWorld()
GSA1.LogFlush()
local log = M.files["gsa1/log.txt"] or ""
check(okA and string.find(log, "surfaces: 193 materials (2 without a .vmt, 153 patch), 3 surface types on the map, "
    .. "walkable ground 95.3% diggable, - slippery; overrides: none", 1, true) ~= nil,
    "the session log's line when the map is applied: %s", string.match(log, "surfaces: [^\n]*") or "(none)")
-- 0.9.2: each kind's share (the module's version-2 fields)
local INFO2 = { enabled = true, materials_used = 10, vmt_missing = 0, vmt_patches = 0, walkable = 1000, dig = 500,
    slippery = 0, sand = 0, snow = 50, fast = 0, slide = 0, speedpath = 120, stairs = 30, hurt = 0, footprints = 0,
    noland = 0, wallslide = 0, wall = 400, walls = { noland = 100, wallslide = 0, noclimb = 40, snow = 0 },
    wall_only_floors = 12, types = {} }
local sum2 = S.SummaryLine(INFO2)
check(string.find(sum2, "walkable ground 50.0% diggable, - slippery, 5.0% snow, 12.0% speed track, 3.0% stairs; walls: "
    .. "25.0% not a floor, 10.0% no climbing (12 floor triangles of a walls-only kind kept as floors); overrides:", 1, true)
    ~= nil, "the summary / log line reports each kind's share: %s", sum2)

-- 6. the changes survive a reload of the addon ------------------------------------------------------------------------
S.SetOverride("metal", "slippery")
local saved = M.files[S.FILE]
GSA1 = nil
M.included = {}
local ok2 = pcall(M.load, "autorun/gsa1_autorun.lua")
local S2 = GSA1 and GSA1.Surfaces
check(ok2 and S2 and S2.overrides.metal == "slippery" and saved and M.convars.gsa1_surface_overrides.v == "metal=slippery",
    "after a reload of the addon (a new map): metal still slippery, read from data/%s", S.FILE)

-- 7. the map job's materials from the map's own pak ---------------------------------------------------------------------
local fed = {}
local real_open = file.Open
file.Open = function(path, mode, where)
    if where == "BSP" and path == "materials/maps/gm_x/patch_1_2_3.vmt" then
        return { Size = function() return 9 end, Read = function(_, n) return "patch { }" end, Close = function() end }
    end
    return nil
end
GSA1.LoadModule()
G.MapPoll = function(out)
    return { state = "files", progress = 0.6, files = { { path = "materials/maps/gm_x/patch_1_2_3.vmt", max = 0 },
                                                         { path = "materials/nowhere.vmt", max = 0 } }, needs = {} }
end
G.MapFeedFile = function(path, data) fed[path] = data or false return true end
GSA1.World.state = "loading"
GSA1.WorldThink()
file.Open = real_open
check(fed["materials/maps/gm_x/patch_1_2_3.vmt"] == "patch { }" and fed["materials/nowhere.vmt"] == false,
    "a material \"GAME\" lacks is read from the map's pak (\"BSP\"); a missing one is reported missing")

-- 8. a module without the version-2 part (0.9.1's: surfaces 1) ----------------------------------------------------------
G.FEATURES = { surfaces = 1 }
local calls_before = n_of("SetSurfaceTable")
local o2 = GSA1.MapOptions()
local panel2 = standin("DForm")
for _, e in ipairs(M.menu) do
    if e.class == "gsa1_feat_surfaces" then entry = e end
end
M.menu = {}
M.run_hook("PopulateToolMenu")
for _, e in ipairs(M.menu) do
    if e.class == "gsa1_feat_surfaces" then entry = e end
end
entry.cpanel(panel2)
local t2 = {}
for _, call in ipairs(panel2.calls) do t2[#t2 + 1] = call[1] .. "(" .. tostring(call[2]) .. ")" end
local t2s = table.concat(t2, " ")
check(o2.world_key == nil and n_of("SetSurfaceTable") == calls_before and
    string.find(t2s, "0.9.2", 1, true) ~= nil and string.find(t2s, "version 2 is needed", 1, true) ~= nil and
    not string.find(t2s, "CheckBox", 1, true),
    "a module with only version 1 of the surfaces part (0.9.1's): no table, no world key, the page says it needs G-SA1 "
    .. "module 0.9.2 (version 2)")
check(#M.reported == 0, "no Lua error%s", #M.reported > 0 and (": " .. M.reported[1]) or "")
info("module calls: SetSurfaceTable %d, SurfaceInfo %d, SurfaceKind %d", n_of("SetSurfaceTable"), n_of("SurfaceInfo"),
    n_of("SurfaceKind"))
return done()
