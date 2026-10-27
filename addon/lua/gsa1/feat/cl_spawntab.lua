-- G-SA1 client: a "G-SA1" tab at the top of the spawn menu (the owner, 2026-10-26: "I want G-SA1 objects to have their own tab
-- at the top of the spawn menu. Like how G64 does."). Built the way the sandbox builds its own Entities tab
-- (gamemodes/sandbox/gamemode/spawnmenu/creationmenu/content/contenttypes/entities.lua): a creation tab holding a
-- SpawnmenuContentPanel, a tree of categories on the left, and a ContentContainer of the usual entity icons for the category
-- clicked. The objects stay in Entities > G-SA1 as well. Later rounds (1.0's game objects) add their own categories to
-- GSA1.SpawnTab.CATEGORIES before the spawn menu is first opened.
--
-- 0.9.4b (the owner on 0.9.4a: "the spawn tab icon is HUGE, which makes the tab extremely wide. The icon for the tab should
-- be Sonic's 1-up icon."; sadc docs/research/objects2_plan.md 11.2): the tab's icon is 16 x 16 - a Garry's Mod silkicon
-- until feat/cl_objicons.lua has drawn Sonic's 1-up icon from the owner's disc into a 16 x 16 picture (T.SetIcon: a
-- material path before the spawn menu is built, else the built tab's image), never the 128-pixel entity picture (0.9.4a's
-- entities/gsa1_obj_ring.png made the tab as wide as the picture: the tab sizes its image to the texture).
GSA1 = GSA1 or {}

local T = GSA1.SpawnTab or {}
GSA1.SpawnTab = T
T.NAME = "G-SA1"
T.ICON = "icon16/coins.png"             -- a 16 x 16 silkicon until the 1-up icon exists (0.9.4a: the 128-pixel ring)
T.ICON_SIZE = 16                        -- the tab sizes its image to the texture: every icon given here is 16 x 16
T.ORDER = 60                            -- after the sandbox's own tabs (Spawnlists ... Vehicles)
T.TOOLTIP = "Sonic Adventure objects (G-SA1)"
T.HOOK = "PopulateGSA1"

-- each category: name, a 16x16 icon, classes() = the entity classes it lists (in this order)
T.CATEGORIES = T.CATEGORIES or {
    { name = "Rings and Item Boxes", icon = "icon16/coins.png", classes = function()
        local out = {}
        local O = GSA1.Objects
        for _, c in ipairs(O and O.CLASSES or {}) do out[#out + 1] = c.class end
        return out
    end },
}

local function spawnable()
    if not list then return {} end
    if list.Get then return list.Get("SpawnableEntities") or {} end
    if list.GetForEdit then return list.GetForEdit("SpawnableEntities") or {} end
    return {}
end

-- the icons of one category: only classes the spawn menu offers (a type this module cannot run was taken out of the
-- SpawnableEntities list by feat/cl_objects.lua O.Availability), with the fields the sandbox's entity icon takes
function T.Items(cat)
    local out, sp = {}, spawnable()
    local ok, classes = pcall(cat.classes)
    for _, cls in ipairs(ok and type(classes) == "table" and classes or {}) do
        local e = sp[cls]
        if type(e) == "table" then
            out[#out + 1] = {
                type = e.ScriptedEntityType or "entity",
                nicename = e.PrintName or cls,
                spawnname = cls,
                material = e.IconOverride or ("entities/" .. cls .. ".png"),
                admin = e.AdminOnly,
            }
        end
    end
    return out
end

-- fills the tab's tree (hook T.HOOK, called by the SpawnmenuContentPanel): one node per category with icons; the first
-- category opens at once
function T.Populate(pnlContent, tree)
    local first
    for _, cat in ipairs(T.CATEGORIES) do
        local items = T.Items(cat)
        if #items > 0 then
            local node = tree:AddNode(cat.name, cat.icon)
            node.DoPopulate = function(self)
                if self.PropPanel and (not IsValid or IsValid(self.PropPanel)) then return end
                self.PropPanel = vgui.Create("ContentContainer", pnlContent)
                self.PropPanel:SetVisible(false)
                self.PropPanel:SetTriggerSpawnlistChange(false)
                for _, it in ipairs(items) do
                    spawnmenu.CreateContentIcon(it.type, self.PropPanel, { nicename = it.nicename, spawnname = it.spawnname,
                        material = it.material, admin = it.admin })
                end
            end
            node.DoClick = function(self)
                self:DoPopulate()
                pnlContent:SwitchPanel(self.PropPanel)
            end
            first = first or node
        end
    end
    if first then
        if first.InternalDoClick then first:InternalDoClick() else first:DoClick() end
    end
    return first ~= nil
end

function T.Register()
    if not (spawnmenu and spawnmenu.AddCreationTab) then return false end
    spawnmenu.AddCreationTab(T.NAME, function()
        local ctrl = vgui.Create("SpawnmenuContentPanel")
        ctrl:CallPopulateHook(T.HOOK)
        return ctrl
    end, T.ICON, T.ORDER, T.TOOLTIP)
    return true
end

-- the built tab's image (the sandbox: g_SpawnMenu.CreateMenu:GetCreationTab(name).Tab.Image, a DImage), or nil
function T.TabImage()
    local sm = g_SpawnMenu
    if not (sm and (not IsValid or IsValid(sm))) then return nil end
    local cm = sm.CreateMenu or (sm.GetCreationMenu and sm:GetCreationMenu())
    local sheet = cm and cm.GetCreationTab and cm:GetCreationTab(T.NAME)
    local img = sheet and sheet.Tab and sheet.Tab.Image
    if img and (not IsValid or IsValid(img)) then return img, sheet.Tab end
    return nil
end

-- the tab's icon: a material path (a 16 x 16 PNG: before the spawn menu is built it becomes the tab's own icon) or an
-- IMaterial of a 16 x 16 texture (feat/cl_objicons.lua's render target); applied to the built tab at once
function T.SetIcon(icon)
    if icon == nil then return false end
    T.current = icon
    if type(icon) == "string" then
        T.ICON = icon
        local tabs = spawnmenu and spawnmenu.GetCreationTabs and spawnmenu.GetCreationTabs()
        if type(tabs) == "table" and tabs[T.NAME] then tabs[T.NAME].Icon = icon end
    end
    local img, tab = T.TabImage()
    if not img then return false end
    if type(icon) == "string" then
        if img.SetImage then img:SetImage(icon) end
    elseif img.SetMaterial then
        img:SetMaterial(icon)
    end
    if img.SetSize then img:SetSize(T.ICON_SIZE, T.ICON_SIZE) end
    if tab and tab.InvalidateLayout then tab:InvalidateLayout() end
    return true
end

hook.Add(T.HOOK, "gsa1_spawntab", function(pnlContent, tree) T.Populate(pnlContent, tree) end)
-- a spawn menu built (again) after the 1-up icon was made: its tab gets it too
hook.Add("SpawnMenuCreated", "gsa1_spawntab", function()
    if T.current ~= nil and type(T.current) ~= "string" then T.SetIcon(T.current) end
end)
T.Register()
