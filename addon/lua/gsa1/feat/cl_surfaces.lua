-- G-SA1 surfaces, client (0.8): the ground types' settings, the module calls and the Q-menu page Options > G-SA1 >
-- Surfaces (sadc docs/research/gsa1_060_dig.md 6.4 / F6 with its review: R4 G9, G10; plan gsa1_rounds_plan.md 14.1d).
-- 0.9.2 (gsa1_090_surfaces.md F3 with its review C3 / C5; plan gsa1_090_plan.md 6.9): every SA1 ground kind as a
-- checklist for the selected surface type (sh_surfaces.lua S.KINDS: plain names, the explanation as each tooltip, the
-- game's precedence of the grip kinds, "walls only" for not a floor / slide-off wall, a Normal button; footprints hidden
-- until a footprint task exists), the live line decoding every kind, each kind's share in the summary and the log.
--
--   gsa1_surfaces 1           ground types from Garry's Mod's materials (0: every ground is normal, as 0.7)
--   gsa1_dig_anywhere 0       Knuckles can dig anywhere (not the game's rule)
--   gsa1_surface_overrides    a read-only copy of the page's changes for the session log (the changes themselves are in
--                             garrysmod/data/gsa1/surfaces.txt: a ConVar is too short for the whole table)
-- The table and the two settings go to the module with every load of the map's collision (GSA1.MapOptionHooks,
-- cl_module.lua): a change loads it again - from the cache, the classes applied and the world prepared on a worker,
-- no rebuild - and the character is re-created where it stands. The page shows the map's surface types by walkable area,
-- each with its kinds (the checklist below the list changes the selected one), and a live line: what the ground under the
-- character is made of, and what the game makes of it. One line per map goes into the session log.
-- Nothing here runs per frame outside the page.
GSA1 = GSA1 or {}
local S = GSA1.Surfaces
if not S then return end

S.cv = {
    enabled = GSA1.ConVar("gsa1_surfaces", 1, "Ground types from Garry's Mod's materials: Knuckles digs where the map's "
        .. "ground is grass, dirt, sand ..., ice is slippery (0 = every ground is normal ground). Changing it reloads the "
        .. "map's collision (from the cache: no rebuild)", 0, 1),
    anywhere = GSA1.ConVar("gsa1_dig_anywhere", 0, "Knuckles can dig anywhere (not the game's rule: it only digs where "
        .. "the ground is diggable). Changing it reloads the map's collision (from the cache)", 0, 1),
    mirror = GSA1.ConVar("gsa1_surface_overrides", "", "Read-only: a copy of your changes on the Surfaces page, for the "
        .. "session log (the table itself is garrysmod/data/gsa1/surfaces.txt)"),
}

-- the owner's changes, from the file
function S.Load()
    local text = file.Read(S.FILE, "DATA")
    local t, bad = S.Parse(text)
    S.overrides = t
    S.badLines = bad
    return t
end

function S.Save()
    if file.CreateDir then file.CreateDir("gsa1") end
    file.Write(S.FILE, S.Serialize(S.overrides))
    if S.cv.mirror then S.cv.mirror:SetString(S.MirrorString(S.overrides)) end
end

S.overrides = S.overrides or S.Load()
if S.cv.mirror and S.cv.mirror:GetString() ~= S.MirrorString(S.overrides) then
    S.cv.mirror:SetString(S.MirrorString(S.overrides))
end

function S.HasModule()
    return GSA1.HasFeature and GSA1.HasFeature(S.NEEDS.feature, S.NEEDS.version) or false
end

-- the table and the settings into the module; returns its hash (nil: the module has no surfaces part)
function S.Push()
    if not S.HasModule() then return nil end
    local ok, hash, changed, skipped = gsa1.SetSurfaceTable(S.ToList(S.overrides),
        { enabled = S.cv.enabled:GetBool(), dig_anywhere = S.cv.anywhere:GetBool() })
    if not ok then
        GSA1.Msg("surfaces: %s", tostring(hash))
        return nil
    end
    S.hash = hash
    if (skipped or 0) > 0 then GSA1.Msg("surfaces: %d of your table's entries were not taken", skipped) end
    return hash
end

-- every load of the map's collision: the table goes with it, its hash into the world's key
GSA1.MapOptionHooks = GSA1.MapOptionHooks or {}
GSA1.MapOptionHooks.surfaces = function(o)
    local h = S.Push()
    if h then o.world_key = (o.world_key or "") .. string.format(" surf%.0f", h) end
end

-- loads the map's collision again with the current table (a cache hit: classes and preparation only)
function S.Reload()
    S.Push()
    if GSA1.mod and GSA1.World and GSA1.World.state ~= "idle" and GSA1.StartWorld then
        GSA1.StartWorld(false)
        return true
    end
    return false
end

for _, name in ipairs({ "gsa1_surfaces", "gsa1_dig_anywhere" }) do
    cvars.AddChangeCallback(name, function()
        timer.Create("gsa1_surfaces_reload", 0.5, 1, function() S.Reload() end)
    end, "gsa1_surfaces")
end

-- one type's kinds: nil = the built-in table's
function S.SetOverride(name, kinds)
    if not S.ValidName(name) then return false end
    kinds = kinds and S.NormalizeKinds(kinds)
    local d = S.Defaults()
    if kinds == nil or (d[name] ~= nil and d[name] == kinds) then
        S.overrides[name] = nil
    else
        S.overrides[name] = kinds
    end
    S.Save()
    S.pending = true
    return true
end

function S.ResetAll()
    S.overrides = {}
    S.Save()
    S.pending = false
    return S.Reload()
end

function S.Apply()
    S.Save()
    S.pending = false
    return S.Reload()
end

-- the built-in table (the module's; {} without it)
function S.Defaults()
    if not S.defaults and S.HasModule() then S.defaults = gsa1.SurfaceDefaults() end
    return S.defaults or {}
end

-- the kinds the current table gives a type: the owner's entry, else the module's resolution
function S.KindOf(name, letter)
    if S.overrides[name] then return S.overrides[name], "your table" end
    if not S.HasModule() then return "normal", "" end
    local k, how = gsa1.SurfaceKind(name, letter)
    return k or "normal", how or ""
end

-- the live line: the surface under the character (a trace down through Garry's Mod's own collision), its kinds, and
-- what the game makes of the ground it stands on (sa1_state.surface: every kind's SA1_SURFACE_* bit, S.DecodeGame)
function S.UnderLine()
    local C = GSA1.Char
    local ply = LocalPlayer and LocalPlayer()
    local pos = C and C.drawPos or (IsValid(ply) and ply:GetPos()) or nil
    if not pos then return "Under the character: (no character)" end
    if not (util.TraceLine and util.GetSurfacePropName) then return "Under the character: -" end
    local tr = util.TraceLine({ start = pos + Vector(0, 0, 16), endpos = pos - Vector(0, 0, 72), mask = MASK_SOLID,
                                filter = { ply, C and C.ent or nil } })
    if not tr or not tr.Hit then return "Under the character: nothing solid within 72 units" end
    local name = string.lower(util.GetSurfacePropName(tr.SurfaceProps or 0) or "")
    if name == "" then name = "default" end
    local data = util.GetSurfaceData and util.GetSurfaceData(tr.SurfaceProps or 0)
    local kinds, how = S.KindOf(name, data and data.material)
    local line = string.format("Under the character: %s (%s%s)", name, S.Describe(kinds),
        (how ~= "" and how ~= "listed") and (": " .. how) or "")
    if not S.cv.enabled:GetBool() then line = line .. " - ground types are off" end
    if C and C.state and C.state.surface and C.state.ground then
        local seen = S.DecodeGame(C.state.surface)
        line = line .. "; the game: " .. (#seen > 0 and table.concat(seen, ", ") or "normal ground")
    end
    return line
end

-- "surfaces: 271 materials (3 without a .vmt), 9 surface types on the map, walkable ground 7.5% diggable, 0.0%
-- slippery, 2.0% snow; walls: 12.5% no climbing; overrides: none" (every kind present: S.KindShares / S.WallShares)
function S.SummaryLine(i)
    if not i then return "surfaces: no map loaded yet" end
    if not i.enabled then
        return string.format("surfaces: off (gsa1_surfaces 0); %d materials, overrides: %s", i.materials or 0,
            S.MirrorString(S.overrides) ~= "" and S.MirrorString(S.overrides) or "none")
    end
    local on_map = 0
    for _, t in ipairs(i.types or {}) do
        if (t.tris or 0) > 0 then on_map = on_map + 1 end
    end
    local mirror = S.MirrorString(S.overrides)
    local kept = (i.wall_only_floors or 0) > 0 and string.format(" (%d floor triangles of a walls-only kind kept as "
        .. "floors)", i.wall_only_floors) or ""
    return string.format("surfaces: %d materials (%d without a .vmt, %d patch), %d surface types on the map, walkable "
        .. "ground %s%s%s%s; overrides: %s", i.materials_used or 0, i.vmt_missing or 0,
        i.vmt_patches or 0, on_map, S.KindShares(i), i.dig_anywhere and " (dig anywhere)" or "", S.WallShares(i), kept,
        mirror ~= "" and mirror or "none")
end

-- the session log: one line per applied map
GSA1.WorldAppliedHooks = GSA1.WorldAppliedHooks or {}
GSA1.WorldAppliedHooks.surfaces = function(map, info)
    if not S.HasModule() then return end
    S.info = gsa1.SurfaceInfo()
    local line = S.SummaryLine(S.info)
    if GSA1.Log then GSA1.Log("surfaces", "%s", line) end
    if GSA1.cv and GSA1.cv.debug and GSA1.cv.debug:GetBool() then GSA1.Msg("%s", line) end
    if S.refresh then S.refresh() end
end

concommand.Add("gsa1_surfaces_apply", function()
    if S.Apply() then GSA1.Msg("surfaces: the map's collision loads again with your table") end
end, nil, "G-SA1: apply the Surfaces page's table (the map's collision loads again from the cache)")
concommand.Add("gsa1_surfaces_reset", function()
    S.ResetAll()
    GSA1.Msg("surfaces: the built-in table again")
end, nil, "G-SA1: forget your changes to the Surfaces table")
concommand.Add("gsa1_surfaces_list", function()
    if not S.HasModule() then GSA1.Msg("surfaces: needs G-SA1 module %s or newer", S.NEEDS.module) return end
    local i = gsa1.SurfaceInfo()
    GSA1.Msg("%s", S.SummaryLine(i))
    for _, t in ipairs(i and i.types or {}) do
        if (t.tris or 0) > 0 then
            local k = S.KindOf(t.name)
            GSA1.Msg("  %-24s %-28s %6s of the walkable ground (%s)", t.name, S.Describe(k), S.Share(t.area, i.walkable),
                t.chain)
        end
    end
end, nil, "G-SA1: list this map's surface types and their kinds")

-- the page --------------------------------------------------------------------------------------------------------
local function page(panel)
    panel:Help("Sonic Adventure marks its ground: Knuckles digs only where the ground is diggable (hold attack or crouch "
        .. "and press jump, standing or walking slowly), Ice Cap's ice is slippery and its snow slow to speed up, Sand "
        .. "Hill's sand is slow, Speed Highway has fast ground, sliding floors and speed tracks, some walls cannot be stood "
        .. "on or climbed. Garry's Mod's ground says what it is made of: every material names a surface type (grass, "
        .. "concrete, ice ...). This table turns the types into the game's ground: by default grass, dirt, mud, sand, "
        .. "gravel and snow are diggable, ice is slippery, the rest is normal ground. Select a type in the list and tick "
        .. "its kinds below.")
    panel:CheckBox("Ground types from Garry's Mod materials", "gsa1_surfaces")
    panel:ControlHelp("Off: every ground is normal ground (G-SA1 0.7). Changing it reloads the map's collision.")
    panel:CheckBox("Knuckles can dig anywhere (not the game's rule)", "gsa1_dig_anywhere")
    local live = panel:Help("Under the character: -")
    local next_live = 0
    live.Think = function(self)
        local now = RealTime()
        if now < next_live then return end
        next_live = now + 0.25
        self:SetText(S.UnderLine())
    end
    local summary = panel:Help(S.SummaryLine(S.info))
    local list = vgui.Create("DListView", panel)
    list:SetMultiSelect(false)
    list:AddColumn("Surface type")
    list:AddColumn("Kind")
    list:AddColumn("Walkable ground")
    list:SetTall(330)
    panel:AddItem(list)
    local sel_line = panel:Help("The selected type: (select a surface type in the list)")
    -- the checklist: one box per kind (S.KINDS; hidden ones left out), the explanation as its tooltip
    local boxes, syncing = {}, false
    local selected
    local fill
    local function sync()
        syncing = true
        local k = selected and S.KindOf(selected) or "normal"
        for id, cb in pairs(boxes) do
            if cb.SetChecked then cb:SetChecked(selected ~= nil and S.HasKind(k, id)) end
        end
        sel_line:SetText(selected and string.format("The selected type: %s (%s)", selected, S.Describe(k)) or
            "The selected type: (select a surface type in the list)")
        syncing = false
    end
    for _, kd in ipairs(S.KINDS) do
        if not kd.hidden then
            local cb = panel:CheckBox(kd.title)
            if cb then
                if cb.SetTooltip then cb:SetTooltip(kd.tip) end
                cb.OnChange = function(self, on)
                    if syncing then return end
                    if not selected then
                        sync()   -- nothing selected: the box goes back
                        return
                    end
                    S.SetOverride(selected, S.WithKind(S.KindOf(selected), kd.id, on and true or false))
                    fill()
                    sync()
                end
                boxes[kd.id] = cb
            end
        end
    end
    panel:ControlHelp(S.PRECEDENCE .. " \"Not a floor\" and \"Slide-off wall\" go on the type's walls only (on a floor "
        .. "they would trap the character). Your change is kept in garrysmod/data/gsa1/surfaces.txt; Apply loads the "
        .. "map's collision again with it.")
    local normal = panel:Button("Normal (clear the selected type's kinds)")
    if normal then
        normal.DoClick = function()
            if not selected then return end
            S.SetOverride(selected, "normal")
            fill()
            sync()
        end
    end
    local note = panel:Help("")
    panel:Button("Apply (loads the map's collision again, from the cache)", "gsa1_surfaces_apply")
    panel:Button("Reset to the built-in table", "gsa1_surfaces_reset")
    panel:ControlHelp("Types whose base type is listed take its kind (gravel is a kind of rock, but listed itself); a "
        .. "type nobody lists takes its game-material letter's (dirt, sand, grass, snow: diggable). Physics props get "
        .. "every kind except diggable (the game cannot dig moving objects) and not a floor / slide-off wall (a prop can "
        .. "turn over). After a workshop update of a map's materials: gsa1_cache_purge.")

    fill = function()
        if not IsValid(list) then
            S.refresh = nil   -- the spawn menu was made again: its new page refreshes itself
            return
        end
        list:Clear()
        local i = S.HasModule() and gsa1.SurfaceInfo() or nil
        S.info = i or S.info
        summary:SetText(S.SummaryLine(S.info))
        local rows, seen = {}, {}
        for _, t in ipairs(i and i.types or {}) do
            rows[#rows + 1] = t
            seen[t.name] = true
        end
        for name in pairs(S.Defaults()) do
            if not seen[name] then rows[#rows + 1] = { name = name, tris = 0, area = 0 } seen[name] = true end
        end
        for name in pairs(S.overrides) do
            if not seen[name] then rows[#rows + 1] = { name = name, tris = 0, area = 0 } seen[name] = true end
        end
        for _, t in ipairs(rows) do
            local k = S.KindOf(t.name)
            local line = list:AddLine(t.name, S.Describe(k) .. (S.overrides[t.name] and " *" or ""),
                (t.tris or 0) > 0 and S.Share(t.area, i and i.walkable) or "-")
            if line then line.gsa1Name = t.name end
        end
        note:SetText(S.pending and "Changed: press Apply to load the map's collision with it (* = your change)." or
            (next(S.overrides) and "* = your change." or ""))
    end
    S.refresh = fill

    list.OnRowSelected = function(_, _, line)
        selected = line and line.gsa1Name
        sync()
    end
    fill()
    sync()
end

GSA1.AddMenuPage(300, "surfaces", "Surfaces", page, S.NEEDS)
