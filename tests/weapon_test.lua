-- weapon_test.lua - the player's weapon while they are a G-SA1 character (sadc docs/research/gsa1_060_weapon.md with
-- its review; the 0.6.0 owner test: "Entering character mode with a weapon keeps the weapons effects visible (Physics
-- Gun light)"). Both realms of single player in Garry's Mod's own LuaJIT (tests/lua_host.c): the addon's client through
-- its autorun against tests/lua_mock.lua, its server files through the autorun's server branch in their own
-- environment, and a model of Garry's Mod's weapon handling (below).
--   lua_host tests/weapon_test.lua <tests dir> <addon/lua dir> [nobeamhook]
-- nobeamhook: without the client's DrawPhysgunBeam hook (what the server's holster alone achieves).
--
-- The model (GMod's engine code is not readable, so its C++ parts are a model; evidence in the doc, sections 3-5 and
-- the review R.1-R.3):
--   Weapon_Switch (Player:SelectWeapon, a usercmd weapon selection, Give's automatic switch): the PlayerSwitchWeapon
--     hook (true = prevent, base player_shd.lua), then old:Holster(new) (false = refuse), then new:Deploy()
--   Player:SetActiveWeapon: no hook, no Holster, no Deploy ("bypasses GM:PlayerSwitchWeapon and the active weapon's
--     Holster return value", wiki)
--   Entity:Remove is deferred: "The Entity will continue to exist until the start of the next tick" (wiki); until then
--     the weapon is still owned (HasWeapon, GetWeapon, IsValid) and IsMarkedForDeletion() is true
--   Player:Give is refused by GM:PlayerCanPickupWeapon (wiki)
--   Player:DrawWorldModel(false): the active weapon's world model is drawn for nobody (drive.lua)
--   the Physics Gun's beam and glow (the physgun_beam entity): drawn while the gun is deployed (STRICT) or while it is
--     the active weapon (LENIENT), unless a DrawPhysgunBeam hook returns false (which also hides the glow sprites, wiki)
--   gmod_tool: help panel (SWEP:DrawHUD) and ghost (TOOL:Think) while active; Holster releases the ghost
--   gmod_camera: SWEP:HUDShouldDraw hides everything but the weapon selection and the chat (GM:HUDShouldDraw asks the
--     active weapon), so G-SA1's overlay (a HUDPaint, CHudGMod) is hidden while the camera is out
--   weapon_physcannon: Holster refused while it holds an object; Entity:ForcePlayerDrop / Player:DropObject let go
-- The number keys and last weapon are also blocked by the hidden weapon selection HUD (review R.2.1); the model does not
-- draw that HUD, so checks 8-9 test G-SA1's own bind hook. GM:PlayerSwitchWeapon is predicted: in single player the
-- client realm does not run it (review R.2.2); check 11 is the multiplayer half.
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
local ply = M.player
print("G-SA1 weapon_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

-- the model of Garry's Mod's weapons -------------------------------------------------------------------------------
local W = { notes = {}, strings = {}, recv = {}, sweps = {}, autoswitch = true, timers = {}, pending = {} }
local function note(fmt, ...) W.notes[#W.notes + 1] = string.format(fmt, ...) end

-- engine weapon classes (the sandbox loadout's)
local CPP = {
    weapon_physgun = { WorldModel = "models/weapons/w_physics.mdl" },
    weapon_physcannon = { WorldModel = "models/weapons/w_physics.mdl",
                          Holster = function(self) if IsValid(self.holding) then return false end return true end },
    weapon_crowbar = { WorldModel = "models/weapons/w_crowbar.mdl" },
    weapon_357 = { WorldModel = "models/weapons/w_357.mdl" },
    gmod_tool = { scripted = true, WorldModel = "models/weapons/w_toolgun.mdl", DrawHUD = function() end },
    gmod_camera = { scripted = true, WorldModel = "models/MaxOfS2D/camera.mdl",
                    HUDShouldDraw = function(self, name)
                        if name == "CHudWeaponSelection" or name == "CHudChat" then return true end
                        return false
                    end },
}
local WEP = {}
WEP.__index = function(t, k)
    local v = rawget(WEP, k)
    if v ~= nil then return v end
    local cls = rawget(t, "classdef")
    return cls and cls[k]
end
function WEP:GetClass() return self.cls end
function WEP:GetOwner() return self.owner or NULL end
function WEP:IsWeapon() return true end
function WEP:DrawShadow() end
function WEP:SetHoldType() end
function WEP:IsMarkedForDeletion() return self.marked == true end
-- deferred: the weapon goes at the start of the next tick (W.frame)
function WEP:Remove()
    if self.marked or self.removed then return end
    self.marked = true
    W.pending[#W.pending + 1] = self
end
local function really_remove(w)
    w.removed = true
    local o = w.owner
    if o and o.inv[w.cls] == w then o.inv[w.cls] = nil end
    if o and o.active == w then o.active = nil end
end
function WEP:DoHolster(to)
    local f = self.classdef.Holster
    if f and f(self, to) == false then return false end
    self.deployed = false
    if self.cls == "gmod_tool" then self.ghost = nil end
    return true
end
function WEP:DoDeploy()
    self.deployed = true
    if self.classdef.Deploy then self.classdef.Deploy(self) end
    if self.cls == "gmod_tool" then self.ghost = "ghost" end
end
local function new_weapon(cls, owner)
    local def = CPP[cls]
    if not def and W.sweps[cls] then def = setmetatable({ scripted = true }, { __index = W.sweps[cls] }) end
    if not def then return nil end
    local w = setmetatable({ cls = cls, classdef = def, owner = owner, deployed = false }, WEP)
    if def.Initialize then def.Initialize(w) end
    return w
end

-- Garry's Mod's hook.Call: the first hook that returns something wins, else the gamemode's function
local function call(hooks, gm, ev, ...)
    for _, fn in pairs(hooks[ev] or {}) do
        local a, b = fn(...)
        if a ~= nil then return a, b end
    end
    local g = gm[ev]
    if g then return g(gm, ...) end
end
-- the client gamemode (base cl_init.lua)
W.CGM = {
    HUDShouldDraw = function(gm, name)
        local wep = LocalPlayer():GetActiveWeapon()
        if IsValid(wep) and type(wep.HUDShouldDraw) == "function" then
            local r = wep:HUDShouldDraw(name)
            if r ~= nil then return r end
        end
        return true
    end,
    DrawPhysgunBeam = function() return true end,
    PreDrawViewModel = function(gm, vm, p, wep)
        if not IsValid(wep) or wep.PreDrawViewModel == nil then return false end
        return wep:PreDrawViewModel(vm, wep, p)
    end,
    PlayerBindPress = function() return false end,
    PlayerSwitchWeapon = function() return false end,
}
function W.C_call(ev, ...) return call(M.hooks, W.CGM, ev, ...) end

-- the server realm: its own globals over the mock's
local SH = {}
local S = setmetatable({}, { __index = _G })
W.S, W.SH = S, SH
S.SERVER, S.CLIENT = true, false
W.SGM = {
    PlayerSwitchWeapon = function() return false end,
    PlayerSwitchFlashlight = function() return true end,
    PlayerCanPickupWeapon = function() return true end,
    PlayerSpawn = function(gm, p)                      -- the sandbox loadout (player_sandbox.lua)
        p:StripWeapons()
        for _, c in ipairs({ "weapon_crowbar", "weapon_physcannon", "gmod_tool", "gmod_camera", "weapon_physgun" }) do
            p:Give(c)
        end
        p:SwitchToDefaultWeapon()
    end,
}
function W.S_call(ev, ...) return call(SH, W.SGM, ev, ...) end
S.hook = {
    Add = function(ev, name, fn) SH[ev] = SH[ev] or {} SH[ev][name] = fn end,
    Remove = function(ev, name) if SH[ev] then SH[ev][name] = nil end end,
    Run = function(ev, ...) return W.S_call(ev, ...) end,
    Call = function(ev, gm, ...) return call(SH, gm or {}, ev, ...) end,
}
local inbuf, inpos = {}, 0
local function rd() inpos = inpos + 1 return inbuf[inpos] end
S.net = {
    Receive = function(name, fn) W.recv[name] = fn end,
    ReadBool = rd, ReadUInt = rd, ReadFloat = rd, ReadVector = rd,
    Start = function() end, Send = function() end, Broadcast = function() end, SendPVS = function() end,
    WriteBool = function() end, WriteUInt = function() end, WriteFloat = function() end, WriteVector = function() end,
}
S.util = {
    AddNetworkString = function(n) W.strings[n] = true end,
    NetworkStringToID = function(n) return W.strings[n] and 1 or 0 end,
    IsInWorld = function() return true end,
    TraceHull = function(t) return { StartSolid = false, Hit = false, HitPos = Vector(t.endpos) } end,
}
local SCV = {}
S.CreateConVar = function(name, default)
    local cv = setmetatable({ name = name, v = tostring(default) }, getmetatable(M.cv("fps_max")))
    SCV[name] = cv
    return cv
end
S.GetConVar = function(name) return SCV[name] end
S.player = { GetAll = function() return { ply } end }
S.weapons = { Register = function(t, name) t.ClassName = name W.sweps[name] = t end,
              GetStored = function(name) return W.sweps[name] end }
S.MOVETYPE_WALK, S.MOVETYPE_NOCLIP, S.MASK_PLAYERSOLID = 2, 8, 33636363
S.AddCSLuaFile = function() end
S.include = function(rel)
    local src = host_read(M.root .. "/" .. rel)
    if not src then error("server include: no file " .. rel) end
    local fn, err = host_load(src, "sv:" .. rel)
    if not fn then error(err) end
    setfenv(fn, S)
    fn()
end

-- client -> server messages, delivered at once
local out = nil
local function push(v) if out then out.vals[#out.vals + 1] = v end end
net.Start = function(name) out = { name = name, vals = {} } end
net.WriteBool, net.WriteUInt, net.WriteFloat = push, push, push
net.WriteVector = function(v) push(Vector(v)) end
net.SendToServer = function()
    local m = out
    out = nil
    local fn = m and W.recv[m.name]
    W.sent = W.sent or {}
    if m then W.sent[#W.sent + 1] = m.name .. ":" .. tostring(m.vals[1]) end
    if fn then
        inbuf, inpos = m.vals, 0
        fn(#m.vals * 8, ply)
    end
end
util.NetworkStringToID = function(n) return W.strings[n] and 1 or 0 end

-- the player entity (one table, both realms)
ply.inv, ply.alive = {}, true
ply.movetype, ply.nodraw, ply.shadow, ply.drawWorld, ply.drawView, ply.flashlight = 2, false, true, true, true, false
function ply:HasWeapon(c) return self.inv[c] ~= nil end
function ply:GetWeapon(c) return self.inv[c] or NULL end
function ply:Alive() return self.alive end
function ply:SetNoDraw(b) self.nodraw = b end
function ply:GetNoDraw() return self.nodraw end
function ply:DrawShadow(b) self.shadow = b end
function ply:SetMoveType(m) self.movetype = m end
function ply:GetMoveType() return self.movetype end
function ply:GetHull() return Vector(-16, -16, 0), Vector(16, 16, 72) end
function ply:SetVelocity() end
function ply:GetVelocity() return Vector() end
function ply:DrawWorldModel(b) self.drawWorld = b end
function ply:DrawViewModel(b) self.drawView = b end
function ply:FlashlightIsOn() return self.flashlight end
function ply:Flashlight(b) self.flashlight = b end
function ply:StripWeapons()
    for _, w in pairs(self.inv) do w.removed = true end
    self.inv, self.active = {}, nil
end
-- Weapon_Switch
function W.switch(p, new, why)
    local old = p.active
    if old == new then return true end
    if W.S_call("PlayerSwitchWeapon", p, old or NULL, new) == true then
        note("%s: the switch to %s was prevented by PlayerSwitchWeapon", why, new.cls)
        return false
    end
    if old and not old:DoHolster(new) then
        note("%s: %s refused to holster", why, old.cls)
        return false
    end
    p.active = new
    new:DoDeploy()
    return true
end
function ply:SelectWeapon(c)
    local w = self.inv[c]
    if w then W.switch(self, w, "SelectWeapon") end
end
function ply:SetActiveWeapon(w)
    if w == nil or not IsValid(w) then self.active = nil else self.active = w end
end
function ply:Give(c)
    if self.inv[c] then return NULL end
    local w = new_weapon(c, self)
    if not w then return NULL end
    if W.S_call("PlayerCanPickupWeapon", self, w) == false then
        note("Give: %s refused by PlayerCanPickupWeapon", c)
        return NULL
    end
    self.inv[c] = w
    if not IsValid(self.active) or (W.autoswitch and w.classdef.AutoSwitchTo ~= false) then W.switch(self, w, "Give") end
    return w
end
function ply:SwitchToDefaultWeapon()            -- extensions/player.lua with cl_defaultweapon weapon_physgun
    if self:HasWeapon("weapon_physgun") then self:SelectWeapon("weapon_physgun") end
end
function ply:DropObject()
    local w = self.active
    if w and w.cls == "weapon_physcannon" then w.holding = nil end
end
function W.prop()
    return { ForcePlayerDrop = function(self)
        for _, w in pairs(ply.inv) do if w.holding == self then w.holding = nil end end
    end }
end
-- the player's input: a bind, then (when no PlayerBindPress hook swallowed it) the weapon selection it makes
function W.press(bind, select_class)
    if W.C_call("PlayerBindPress", ply, bind, true) == true then return "swallowed" end
    if select_class and ply.inv[select_class] then
        local predicted = W.C_call("PlayerSwitchWeapon", ply, ply:GetActiveWeapon(), ply.inv[select_class]) ~= true
        W.switch(ply, ply.inv[select_class], "usercmd " .. bind)
        return predicted and "predicted" or "refused by the client"
    end
    return "passed"
end
function W.flashlight_key()                     -- impulse 100
    local on = not ply.flashlight
    if W.S_call("PlayerSwitchFlashlight", ply, on) ~= false then ply.flashlight = on end
end
-- one tick: the pending removals first (the start of the tick), then the client's frame, the server's timers and Think
function W.frame(dt)
    local list = W.pending
    W.pending = {}
    for _, w in ipairs(list) do really_remove(w) end
    M.frame(dt)
    W.S_call("Think")
end
function W.frames(n) for _ = 1, n do W.frame(1 / 60) end end
-- what is visible of the weapon
function W.effects()
    local a = ply.active
    local beam_hook = W.C_call("DrawPhysgunBeam", ply, a or NULL, false, NULL, 0, Vector()) ~= false
    local e = { active = a and a.cls or "none" }
    e.glow_lenient = a ~= nil and a.cls == "weapon_physgun" and a.deployed and beam_hook
    e.glow_strict = false
    for _, w in pairs(ply.inv) do
        if w.cls == "weapon_physgun" and w.deployed and beam_hook then e.glow_strict = true end
    end
    e.viewmodel = a ~= nil and ply.drawView ~= false and W.C_call("PreDrawViewModel", {}, ply, a) ~= true
    e.worldmodel_others = a ~= nil and (a.WorldModel or "") ~= "" and ply.drawWorld ~= false
    e.tool_hud = a ~= nil and a.cls == "gmod_tool" and a.deployed
    e.tool_ghost = false
    for _, w in pairs(ply.inv) do if w.cls == "gmod_tool" and w.ghost then e.tool_ghost = true end end
    e.hud_gmod = W.C_call("HUDShouldDraw", "CHudGMod") ~= false
    return e
end
local function state()
    local e = W.effects()
    return string.format("active %s, hands owned %s, physgun deployed %s, glow %s/%s", e.active,
        tostring(ply:HasWeapon("gsa1_hands")), tostring(ply.inv.weapon_physgun and ply.inv.weapon_physgun.deployed),
        tostring(e.glow_lenient), tostring(e.glow_strict))
end

-- the addon: the server's files (its autorun branch), then the client's -------------------------------------------
-- GSA1.IsCharacter of one realm (false when the addon has none: an older addon fails the checks, not the test)
local function is_char(G) return G ~= nil and G.IsCharacter ~= nil and G.IsCharacter(ply) == true end
rawset(S, "GSA1", {})                -- the server's own GSA1 table (the client's is the mock's global)
local ok_s, err_s = pcall(S.include, "autorun/gsa1_autorun.lua")
local SG = rawget(S, "GSA1")
GSA1 = nil
local ok_c, err_c = pcall(M.load, "autorun/gsa1_autorun.lua")
if not check(ok_s and ok_c and SG ~= nil, "the addon loads in both realms (%s)", tostring(err_s or err_c or "ok")) then
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return false
end
check(W.sweps.gsa1_hands ~= nil and M.weapons.gsa1_hands ~= nil and SH.PlayerSwitchWeapon and SH.PlayerSwitchWeapon.gsa1
    and M.hooks.PlayerSwitchWeapon and M.hooks.PlayerSwitchWeapon.gsa1,
    "both realms register the empty hands (gsa1_hands) and the weapon-switch gate")
local nobeam = arg[3] == "nobeamhook"
if nobeam then
    M.hooks.DrawPhysgunBeam = nil
    print("(without the client's DrawPhysgunBeam hook)")
end
M.module({})
GSA1.LoadModule()
GSA1.World.state, GSA1.World.info = "applied", { min_z = -10000 }
GSA1.worldMap, GSA1.worldInfo = game.GetMap(), { min_z = -10000 }

-- the sandbox loadout: the Physics Gun in the hands (cl_defaultweapon)
W.S_call("PlayerSpawn", ply)
W.frames(2)
local e = W.effects()
check(e.active == "weapon_physgun" and e.glow_lenient and e.glow_strict and e.viewmodel,
    "baseline: the Physics Gun is out, glowing, its view model drawn")

-- 1. the Physics Gun --------------------------------------------------------------------------------------------------
print("-- the Physics Gun in the hands, then gsa1_spawn sonic")
ply.flashlight = true
GSA1.Spawn("sonic")
W.frames(3)
e = W.effects()
check(GSA1.Char ~= nil and ply.nodraw, "Sonic spawned, the player entity hidden")
check(not e.glow_lenient, "1 the Physics Gun's glow is gone (LENIENT: drawn while it is the active weapon; active %s)",
    e.active)
check(not e.glow_strict, "2 the Physics Gun's glow is gone (STRICT: drawn while it is deployed)")
check(not e.viewmodel, "3 no view model is drawn")
check(not e.worldmodel_others, "4 other players see no weapon at the hidden player (active %s, DrawWorldModel %s)",
    e.active, tostring(ply.drawWorld))
check(e.active == "gsa1_hands" and not ply.inv.weapon_physgun.deployed, "5 the weapon was put away by a real switch "
    .. "(%s)", state())
check(is_char(GSA1) and is_char(SG) and ply.nw2.gsa1_char == true,
    "6 both realms can tell that the player is a character (the NW2 flag gsa1_char, GSA1.IsCharacter)")
local other = { nw2 = { gsa1_char = true }, GetNW2Bool = ply.GetNW2Bool }
check(W.C_call("DrawPhysgunBeam", other, NULL, false, NULL, 0, Vector()) == false, "7 another player who is a "
    .. "character: no Physics Gun beam or glow drawn for them")
check(not ply.flashlight, "the flashlight that was on is switched off")
GSA1.LogFlush()
check(string.find(M.files["gsa1/log.txt"] or "", "spawn +Sonic spawned in [^\n]*; weapon put away: weapon_physgun") ~= nil,
    "the session log's spawn line names the weapon put away")

-- 2. the weapon keys and other switches while a character
print("-- weapon keys and switches while a character")
local r = W.press("slot3", "weapon_crowbar")
check(r == "swallowed", "8 the number keys do nothing (slot3: %s; active %s)", r, W.effects().active)
r = W.press("lastinv", "weapon_physgun")
check(r == "swallowed", "9 last weapon does nothing (lastinv: %s; active %s)", r, W.effects().active)
r = W.press("invnext")
check(r == "swallowed" and GSA1.cv.cam_dist:GetFloat() == 170, "the mouse wheel still sets the camera distance (%s)",
    GSA1.cv.cam_dist:GetString())
GSA1.cv.cam_dist:SetFloat(150)
W.switch(ply, ply.inv.weapon_crowbar, "the use command")
check(W.effects().active == "gsa1_hands", "10 a switch that gets through anyway is refused by the server (active %s)",
    W.effects().active)
check(W.C_call("PlayerSwitchWeapon", ply, ply:GetActiveWeapon(), ply.inv.weapon_crowbar) == true,
    "11 multiplayer: the client predicts the same refusal (its flag arrived)")
ply:Give("weapon_357")
ply:SelectWeapon("weapon_357")
check(W.effects().active == "gsa1_hands" and ply:HasWeapon("weapon_357"), "12 a weapon from the spawn menu (Give + "
    .. "SelectWeapon) goes into the inventory, not into the hands (active %s)", W.effects().active)
W.flashlight_key()
check(not ply.flashlight, "13 the flashlight cannot be switched on")
ply:SetActiveWeapon(ply.inv.weapon_crowbar)        -- an addon's SetActiveWeapon bypasses the gate
W.frames(20)
check(W.effects().active == "gsa1_hands" and not ply.inv.weapon_crowbar.deployed,
    "a weapon an addon made active is put away again within 0.33 s (%s)", W.effects().active)

-- 3. back to the player
print("-- gsa1_remove")
GSA1.Remove(false)
check(ply:HasWeapon("gsa1_hands"), "the empty hands stay in the inventory for the rest of the tick")
W.frames(2)
e = W.effects()
check(e.active == "weapon_physgun" and ply.inv.weapon_physgun.deployed, "14 the weapon held before (the Physics Gun) "
    .. "is back in the hands (active %s)", e.active)
check(not ply:HasWeapon("gsa1_hands"), "15 the empty hands are gone from the inventory a tick later")
check(ply.drawWorld ~= false and ply.drawView ~= false and not ply.nodraw, "16 player, world and view models drawn again")
check(not is_char(GSA1), "17 the networked flag is cleared")
check(e.glow_lenient and e.glow_strict, "18 the Physics Gun glows again")
W.flashlight_key()
check(ply.flashlight, "19 the flashlight works again")
ply.flashlight = false

-- 4. tool gun
print("-- the tool gun")
ply:SelectWeapon("gmod_tool")
W.frames(2)
e = W.effects()
check(e.tool_hud and e.tool_ghost, "baseline: the tool gun's help panel and ghost")
GSA1.Spawn("sonic")
W.frames(3)
e = W.effects()
check(not e.tool_hud, "20 tool gun: no help panel while a character (active %s)", e.active)
check(not e.tool_ghost, "21 tool gun: its ghost entity is released")
GSA1.Remove(false)
W.frames(2)
check(W.effects().active == "gmod_tool", "22 the tool gun is back (%s)", W.effects().active)

-- 5. camera
print("-- the camera")
ply:SelectWeapon("gmod_camera")
W.frames(2)
check(not W.effects().hud_gmod, "baseline: the camera hides the HUD (CHudGMod)")
GSA1.Spawn("sonic")
W.frames(3)
check(W.effects().hud_gmod, "23 camera: the HUD (CHudGMod: G-SA1's overlay, later its 2D HUD) is drawn while a "
    .. "character (active %s)", W.effects().active)
GSA1.Remove(false)
W.frames(2)
check(W.effects().active == "gmod_camera", "24 the camera is back (%s)", W.effects().active)

-- 6. Gravity Gun holding something
print("-- the Gravity Gun holding a barrel")
ply:SelectWeapon("weapon_physcannon")
W.frames(1)
local barrel = W.prop()
ply.inv.weapon_physcannon.holding = barrel
W.S_call("GravGunOnPickedUp", ply, barrel)
GSA1.Spawn("sonic")
W.frames(3)
check(ply.inv.weapon_physcannon.holding == nil, "25 gravity gun: the barrel is let go")
check(W.effects().active == "gsa1_hands", "26 gravity gun: put away (active %s)", W.effects().active)
GSA1.Remove(false)
W.frames(2)
check(W.effects().active == "weapon_physcannon", "27 the gravity gun is back (%s)", W.effects().active)
-- a weapon that never lets itself be put away: the hands within HOLSTER_FORCE
print("-- a weapon that refuses to be put away")
local cd = ply.inv.weapon_physcannon.classdef
local old_holster = cd.Holster
cd.Holster = function() return false end
GSA1.Spawn("sonic")
W.frames(80)
check(W.effects().active == "gsa1_hands", "28 a weapon whose Holster always refuses: the empty hands are active within "
    .. "1.4 s (active %s)", W.effects().active)
GSA1.Remove(false)
W.frames(2)
cd.Holster = old_holster
check(W.effects().active == "weapon_physcannon", "29 ... and it is given back afterwards (%s)", W.effects().active)

-- 7. killed while a character: the server respawns the player with the loadout, the client keeps its character
print("-- respawn while a character")
ply:SelectWeapon("weapon_physgun")
GSA1.Spawn("sonic")
W.frames(3)
W.S_call("PlayerSpawn", ply)
W.frames(150)
e = W.effects()
check(e.active == "gsa1_hands" and not e.glow_lenient and is_char(GSA1), "30 after a respawn the weapon is put "
    .. "away again within 2.5 s (the client's repeat; active %s)", e.active)
GSA1.Remove(false)
W.frames(2)
check(W.effects().active == "weapon_physgun", "31 ... and given back afterwards (%s)", W.effects().active)

-- 8. a gamemode or addon that refuses every pickup (SkateGM while skating): no hands can be given
print("-- every pickup refused (no empty hands can be given)")
SH.PlayerCanPickupWeapon = { test = function() return false end }
ply:SelectWeapon("weapon_physgun")
GSA1.Spawn("sonic")
W.frames(80)
e = W.effects()
-- (SetActiveWeapon skips the Physics Gun's Holster: under the STRICT model only the client's beam hook hides its glow)
check(not e.glow_lenient and (nobeam or not e.glow_strict) and not e.worldmodel_others, "32 without the hands the weapon "
    .. "is still put away within 1.4 s (active %s: the G64 / SkateGM fallback)", e.active)
GSA1.Remove(false)
W.frames(2)
check(W.effects().active == "weapon_physgun", "33 ... and given back afterwards (%s)", W.effects().active)
SH.PlayerCanPickupWeapon = nil

-- 9. no weapon in the hands before: none afterwards
print("-- no weapon before")
ply:SetActiveWeapon(NULL)
GSA1.Spawn("sonic")
W.frames(3)
GSA1.Remove(false)
W.frames(2)
check(W.effects().active == "none" and not ply:HasWeapon("gsa1_hands"), "34 no weapon before, none after (%s)",
    W.effects().active)

-- 10. Entity:Remove is deferred (review R.3.2): a character switch, and remove + spawn within one tick
print("-- R1: Sonic, then switch to Knuckles (the Q menu's Spawn / switch)")
ply:SelectWeapon("weapon_physgun")
W.frames(1)
GSA1.Spawn("sonic")
W.frames(3)
W.sent = {}
GSA1.Spawn("knuckles")
check(#W.sent == 1 and W.sent[1] == "gsa1_active:true" and GSA1.Char and GSA1.Char.name == "knuckles",
    "R1 a character switch tells the server only the new character (%s)", table.concat(W.sent, ", "))
e = W.effects()
check(e.active == "gsa1_hands" and not e.glow_lenient and not e.glow_strict, "R1a in the tick of the switch the hands "
    .. "stay active, no glow (%s)", state())
W.frames(3)
e = W.effects()
check(e.active == "gsa1_hands" and not e.glow_strict and is_char(SG), "R1b after the switch: %s", state())
GSA1.Remove(false)
W.frames(3)
check(W.effects().active == "weapon_physgun" and not ply:HasWeapon("gsa1_hands"), "R1c the Physics Gun comes back after "
    .. "the switch and remove, no hands left over (%s)", state())

print("-- R2: gsa1_remove and gsa1_spawn sonic within one tick")
GSA1.Spawn("sonic")
W.frames(3)
GSA1.Remove(false)
GSA1.Spawn("sonic")
e = W.effects()
check(e.active == "gsa1_hands" and ply.inv.gsa1_hands and not ply.inv.gsa1_hands.marked and not e.glow_strict,
    "R2a in that tick the weapon is put away again, with hands that are not being removed (%s)", state())
W.frames(3)
check(W.effects().active == "gsa1_hands" and ply:HasWeapon("gsa1_hands"), "R2b the next ticks: the hands stay (%s)",
    state())
GSA1.Remove(false)
W.frames(3)
check(W.effects().active == "weapon_physgun" and not ply:HasWeapon("gsa1_hands"), "R2c the Physics Gun back (%s)", state())

-- hands that are being removed (another addon stripped them) are not selected: new ones once they are gone
print("-- hands removed by someone else while a character")
GSA1.Spawn("sonic")
W.frames(3)
if ply.inv.gsa1_hands then ply.inv.gsa1_hands:Remove() end
ply:SetActiveWeapon(ply.inv.weapon_crowbar)
W.frames(30)
e = W.effects()
check(e.active == "gsa1_hands" and ply.inv.gsa1_hands and not ply.inv.gsa1_hands.marked, "the dying hands are not "
    .. "selected; new ones are given once they are gone (%s)", state())
GSA1.Remove(false)
W.frames(3)

-- 11. (not the weapon, but the same whole client) the character's tick after a pause of single player runs no time:
-- Think does not run while paused, and 0.6.0's first tick after the escape menu ran 0.25 s at once (cl_hitch.lua's
-- pause note, cl_character.lua; sadc docs/research/gsa1_060_pops.md review R.4)
print("-- the character's tick after a pause")
GSA1.Spawn("sonic")
W.frames(3)
local real_tick, dts = gsa1.Tick, {}
gsa1.Tick = function(id, sx, sy, yaw, b, dt, ...)
    dts[#dts + 1] = dt
    return real_tick(id, sx, sy, yaw, b, dt, ...)
end
local pr = M.hooks.PostRender and M.hooks.PostRender.gsa1_hitch_pause or function() end
for i = 1, 2700 do pr() end              -- 45 s of the escape menu: the world drawn, no Think
M.T = M.T + 45
W.frame(1 / 60)
W.frame(1 / 60)
gsa1.Tick = real_tick
check(dts[1] == 0 and dts[2] and math.abs(dts[2] - 1 / 60) < 1e-6, "the first tick after a 45 s pause runs no time "
    .. "(dt %s, then %s)", tostring(dts[1]), tostring(dts[2]))
GSA1.Remove(false)
W.frames(3)

check(#M.reported == 0, "no Lua error (%s)", tostring(M.reported[1]))
for _, n in ipairs(W.notes) do info("%s", n) end
print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
