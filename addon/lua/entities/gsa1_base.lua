-- G-SA1 object base (round 0.9.4; sadc docs/research/gsa1_094_plan.md 6.5 task 1, v1_arch.md 4.2 / 4.5 with its review):
-- the base of the G-SA1 game objects (gsa1_obj_ring, gsa1_obj_ring_line, gsa1_obj_ring_circle, gsa1_obj_itembox,
-- gsa1_obj_itembox_air; 0.9.5's Board On / Off boxes and 1.0's objects reuse it). Not spawnable itself.
--
-- An object entity is a place: the game's own code runs the ring or the box in every character's world (feat/
-- cl_objects.lua hands the place to the module), so the entity draws nothing of the game - only an outline while you
-- edit (gsa1_set_markers: holding the Physics Gun or the Tool Gun, or without a character). It is sent to every client
-- (TRANSMIT_ALWAYS: the game spawns by distance, not by sight), it carries the shared state the server keeps (State: a
-- Ring or air box there or taken; Broken: the ground box's broken base; TakenBits: a line's or circle's rings taken, per
-- record; RespawnAt), and (0.9.4.1) a pick hull of the WHOLE object - a line's length, a circle's diameter, a box - that
-- the Physics Gun, the Tool Gun and the context menu (C) hit and nothing else does: SOLID_OBB with the hull as its
-- collision bounds, custom collisions, and TestCollision below answering only their rays (feat/sh_objects.lua "THE PICK
-- HULL" says what each choice relies on); players walk through it, props and NPCs pass it (COLLISION_GROUP_WORLD). The
-- Physics Gun may pick it (PhysgunPickup), carries its physics box and freezes it again where it is dropped
-- (feat/sv_objects.lua); a drop (or a SetPos, once the entity has been still for 0.25 s) moves the game's object; the
-- runtime state of a copy (a dupe, a save) starts fresh. The rules are in feat/sh_objects.lua, the server's half in
-- feat/sv_objects.lua.
--
-- 0.9.4b (sadc docs/research/objects2_plan.md 6.3 task 3 with its review R.8): the entity draws the PICTURE of its real
-- object (feat/cl_objview.lua: the game's own models from the owner's disc, run in libsa1's playerless showcase) - for a
-- player without a character, and with one for the records his world is not running (far away) - in its own Draw
-- (opaque batches) and DrawTranslucent (blended batches): RENDERGROUP_BOTH, so Source's PVS, frustum, translucent sorting
-- and views apply (its render bounds are the hull + 16 HU: cl_objects.lua O.EntityBounds). The outlines and the context
-- menu's hover outline come after the picture in DrawTranslucent (feat/cl_objects.lua O.DrawEntity).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "G-SA1 object"
ENT.Author = "G-SA1"
ENT.Category = "G-SA1"
ENT.Spawnable = false
ENT.Editable = true
ENT.GSA1Object = true
ENT.ScriptedEntityType = "gsa1_object"
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.GSA1Model = "models/hunter/blocks/cube025x025x025.mdl"   -- never drawn (the hull is O.Hull, not the model)

-- the class's own NetworkVars come from ENT:GSA1Vars (the derived files); these are every object's
function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "State")              -- 1: there; 0: taken (a Ring, an air box)
    self:NetworkVar("Int", 1, "Moved")              -- raised by the server when a Physics Gun drop ends a move
    self:NetworkVar("Bool", 0, "Broken")            -- the ground box's broken base
    self:NetworkVar("Float", 0, "RespawnAfter", { KeyName = "respawnafter",
        Edit = { type = "Float", order = 50, min = 0, max = 600, title = "Respawn after (s, 0 = never)" } })
    self:NetworkVar("Float", 1, "RespawnAt")        -- CurTime of the respawn (0: none due)
    if self.GSA1Vars then self:GSA1Vars() end
    -- a change of any of them: the client puts it into its worlds at once (feat/cl_objects.lua), the server re-makes the
    -- hull when the layout changed (feat/sv_objects.lua)
    local O = GSA1 and GSA1.Objects
    if O and O.OnVarChanged and self.NetworkVarNotify and self.GetNetworkVars then
        for name in pairs(self:GetNetworkVars() or {}) do
            self:NetworkVarNotify(name, O.OnVarChanged)
        end
    end
end

function ENT:SpawnFunction(ply, tr, ClassName)
    if not tr or not tr.Hit then return end
    local O = GSA1 and GSA1.Objects
    if not O or not O.ServerSpawn then return end
    return O.ServerSpawn(ply, tr, ClassName)
end

function ENT:Initialize()
    if self.GSA1Model and self.SetModel then self:SetModel(self.GSA1Model) end
    if self.DrawShadow then self:DrawShadow(false) end
    if self.EnableCustomCollisions then self:EnableCustomCollisions(true) end    -- traces ask TestCollision (both realms)
    local O = GSA1 and GSA1.Objects
    if SERVER then
        if O and O.ServerInit then O.ServerInit(self) end
    elseif O and O.ClientInit then
        O.ClientInit(self)
    end
end

if SERVER then
    function ENT:UpdateTransmitState()
        return TRANSMIT_ALWAYS
    end

    -- a copy (the duplicator, a save) keeps the editable values, not the runtime state: it starts as a new object
    function ENT:OnEntityCopyTableFinish(data)
        local O = GSA1 and GSA1.Objects
        if O and O.FreshState then O.FreshState(data.DT) end
    end

    function ENT:OnDuplicated(data)
        local O = GSA1 and GSA1.Objects
        if O and O.Respawn then O.Respawn(self, nil) end
    end
end

-- the pick hull (0.9.4.1): an editing ray (the Physics Gun's, the Tool Gun's, the context menu's) hits the whole object;
-- hull traces (player and NPC movement) and every other ray pass through (feat/sh_objects.lua O.PickTrace)
function ENT:TestCollision(startpos, delta, isbox, extents, mask)
    if isbox then return end
    local O = GSA1 and GSA1.Objects
    if not (O and O.PickTrace) then return end
    return O.PickTrace(self, startpos, delta, isbox)
end

-- the Physics Gun may pick it up (the sandbox's GM:PhysgunPickup asks the entity, both realms)
function ENT:PhysgunPickup(ply)
    local O = GSA1 and GSA1.Objects
    if O and O.MayPick then return O.MayPick(ply, self) end
    return true
end

function ENT:OnRemove()
    local O = GSA1 and GSA1.Objects
    if CLIENT and O and O.Untrack then O.Untrack(self) end
end

-- the picture of the real object, the outline while editing and the hover outline (feat/cl_objects.lua O.DrawEntity);
-- flags: the STUDIO flags (the depth views draw the opaque batches only: cl_render.lua GSA1.ViewKind)
function ENT:Draw(flags)
    local O = GSA1 and GSA1.Objects
    if O and O.DrawEntity then
        O.DrawEntity(self, 0, flags)
    elseif O and O.DrawMarker then
        O.DrawMarker(self)
    end
end

function ENT:DrawTranslucent(flags)
    local O = GSA1 and GSA1.Objects
    if O and O.DrawEntity then O.DrawEntity(self, 1, flags) end
end
