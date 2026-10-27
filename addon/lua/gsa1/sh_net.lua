-- G-SA1 shared (both realms): the state packet, the networked character flag, and the player's weapon while they are a
-- character.
--
-- Model (owner-authoritative, as G64 and docs/research/gmod.md 5): the owning client runs libsa1 at 60 Hz and
-- sends this packet; the server moves the player entity there (sv_gsa1.lua) and keeps the last packet in
-- ply.GSA1State. Multiplayer is not done yet. The hook for it:
--   * server: relay ply.GSA1State to the other players in the PVS (net.SendPVS), unreliable, ~20 Hz;
--   * other clients: one puppet per remote player, gsa1.CreatePuppet(kind) once, then every packet
--     gsa1.Pose(id, action, frame, pos, yaw) and the same render entity as the local character
--     (cl_render.lua), interpolated between packets; clients without the module or a disc keep the player model.
-- Nothing ripped from the disc ever goes over the network: every client poses from its own disc.
--
-- 0.8.0 (sadc docs/research/gsa1_060_weapon.md with its review): a character is the player's body, so the weapon the
-- player holds is put away while they are one (sv_gsa1.lua) - the 0.6.0 owner test saw the Physics Gun's glow stay on
-- screen. The parts both realms need are here:
--   * the character flag: the server sets the player's NW2 bool GSA1.NW_CHAR while the player is a character, so every
--     client knows it; GSA1.IsCharacter(ply) reads it in either realm (round 5's interaction layer: HOLDABLE props, the
--     attack scan; other players' Physics Gun beams, cl_character.lua). On the owning client it arrives a round trip
--     after the spawn: client code that needs the local player's own state at once checks GSA1.Char;
--   * the empty hands gsa1_hands: putting the weapon away is an ordinary switch to them, so the old weapon's own Holster
--     runs (the Physics Gun's beam and glow, the Gravity Gun's held object, the tool gun's ghost and help panel, the
--     camera's zoom and hidden HUD all stop);
--   * the gate: while a player is a character no other weapon becomes active (the spawn menu's Give + SelectWeapon, the
--     "use" command, the automatic switch after a pickup, other addons' SelectWeapon). Pickups still go into the
--     inventory. GM:PlayerSwitchWeapon is predicted: in multiplayer the client refuses the same switches; in single
--     player only the server runs it, which is enough.
GSA1 = GSA1 or {}
GSA1.Net = GSA1.Net or {}

local BAMS = 65536 / 360

-- s: { x, y, z, yaw (degrees), kind, action, frame, ground }
function GSA1.Net.WriteState(s)
    net.WriteVector(Vector(s.x, s.y, s.z))
    net.WriteUInt(math.floor((s.yaw % 360) * BAMS) % 65536, 16)
    net.WriteUInt(math.Clamp(s.kind or 0, 0, 15), 4)
    net.WriteUInt(math.Clamp(s.action or 0, 0, 1023), 10)
    net.WriteFloat(s.frame or 0)
    net.WriteBool(s.ground and true or false)
end

function GSA1.Net.ReadState()
    local s = {}
    local p = net.ReadVector()
    s.x, s.y, s.z = p.x, p.y, p.z
    s.yaw = net.ReadUInt(16) / BAMS
    s.kind = net.ReadUInt(4)
    s.action = net.ReadUInt(10)
    s.frame = net.ReadFloat()
    s.ground = net.ReadBool()
    return s
end

-- the character flag ---------------------------------------------------------------------------------------------------
-- (not "gsa1_active": that is the client -> server net message GSA1.NET_ACTIVE)
GSA1.NW_CHAR = "gsa1_char"
GSA1.HANDS = "gsa1_hands"

-- true while the player is a G-SA1 character (set by the server; both realms)
function GSA1.IsCharacter(ply)
    return IsValid(ply) and ply:GetNW2Bool(GSA1.NW_CHAR, false) == true
end

-- the empty hands (after Garry's Mod's own weapon_fists and TTT's unarmed weapon): no world model, no view model drawn,
-- no ammo, no attacks, never dropped, not in the spawn menu, not duplicated
local SWEP = {}
SWEP.Base = "weapon_base"
SWEP.PrintName = "G-SA1 character"
SWEP.Author = "G-SA1"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.DisableDuplicator = true
SWEP.Slot = 5
SWEP.SlotPos = 99
SWEP.ViewModel = Model("models/weapons/c_arms.mdl")
SWEP.WorldModel = ""
SWEP.UseHands = false
SWEP.ViewModelFOV = 54
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.DrawWeaponInfoBox = false
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.Weight = 0
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

function SWEP:Initialize()
    self:SetHoldType("normal")
end

function SWEP:Deploy()
    local owner = self:GetOwner()
    if SERVER and IsValid(owner) and owner:IsPlayer() then owner:DrawViewModel(false) end
    self:DrawShadow(false)
    return true
end

function SWEP:Holster() return true end
function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:Reload() end
function SWEP:ShouldDropOnDie() return false end
function SWEP:OnDrop()
    if SERVER then self:Remove() end
end
function SWEP:DrawWorldModel() end
function SWEP:DrawWorldModelTranslucent() end
function SWEP:PreDrawViewModel() return true end      -- GM:PreDrawViewModel returns it: the arms are never drawn
function SWEP:DrawHUD() end

weapons.Register(SWEP, GSA1.HANDS)

-- the gate: while a character, only the empty hands may become the active weapon (true = prevent the switch,
-- gamemodes/base/gamemode/player_shd.lua GM:PlayerSwitchWeapon)
hook.Add("PlayerSwitchWeapon", "gsa1", function(ply, old, new)
    if not GSA1.IsCharacter(ply) then return end
    if IsValid(new) and new:GetClass() == GSA1.HANDS then return end
    return true
end)
