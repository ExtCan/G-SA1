-- G-SA1 client: the local player's character (single player first).
--
-- Flow per frame: CreateMove reads the player's movement keys / joystick and buttons into a stick and SA1 buttons
-- and clears the user command (the player entity does not move by itself); Think advances libsa1 by the real
-- frame time (SysTime, scaled by host_timescale, 0 while paused) - libsa1 runs whole 1/30 s pairs of 60 Hz steps
-- from its own accumulator - then renders the character at the accumulator's fraction (gsa1.Render: animation
-- and position interpolated between the last two pairs; gsa1_interpolate 0 = the raw pairs), polls the events
-- (the module has already handed the sound events to its mixer), feeds the audio output and reports the position
-- to the server (owner-authoritative, sh_net.lua); CalcView puts the camera behind the character (mouse orbit,
-- hull trace, 0 = first person). The camera yaw is the player's view yaw, so the stick is relative to the
-- camera, as in the game. A controller (cl_pad.lua, read by the module through XInput) is polled at the start of
-- Think: while it is in use its stick replaces the keyboard's and its buttons add to them, and CreateMove turns the
-- view by its right stick.
--
-- Upgrades (Options -> G-SA1 -> Character, ConVars gsa1_upgrade_<name>): a character is created with the ticked
-- upgrades of its kind; ticking or unticking one of the current character's re-creates it where it stands
-- (GSA1.Recreate: same place and facing, standing still; the spawn point stays).
--
-- 0.5: the map's collision loads in the background (cl_module.lua); a spawn before it is ready waits for it and
-- happens by itself. 0.5.1: the disc and the sound banks load in the background too (GSA1.InitThink /
-- GSA1.AudioThink below, once per frame), and a character is cheap to create (the map's collision was prepared by the
-- module's worker; the textures' infos are fetched a few per frame by the texture painter). The moving objects near the character (cl_collision.lua) go to the module before each tick.
-- Every part of a frame is timed for the hitch logger (cl_hitch.lua). The game's capacity reports
-- (SA1_EVENT_CAPACITY: the NEAR-poly list full, the matrix stack restored, ...) are printed with the position:
-- a map-side report of geometry that is too dense or layered there.
-- 0.6.0 (round 4c): the frame is drawn exactly as libsa1 renders it - libsa1 itself moves the draws it could not
-- interpolate along with the root and places the root at the step the game drew, so the camera and the body agree
-- (0.5's "forward and backward" flicker in jumps and falls: sadc docs/research/gsa1_vertical_flicker.md); a new
-- character's materials are pre-warmed (cl_warm.lua); spawns, switches, respawns and capacity reports go into the
-- session log with their times (cl_log.lua); the hooks run under GSA1.Guard (a Lua error is logged, the hook stays);
-- the per-frame tables (events, the view, the camera traces, the state sent to the server) are reused.
-- 0.8.0 (sadc docs/research/gsa1_060_weapon.md with its review): the server puts the player's weapon away while they
-- are a character (sv_gsa1.lua, sh_net.lua); here the weapon keys do nothing (number keys, last weapon), no Physics
-- Gun beam or glow is drawn for a character (the local one at once, other players' by their networked flag), and a
-- character switch tells the server only the new kind (no "off" between: the weapon stays put away). The tick after a
-- pause of single player runs no time (cl_hitch.lua's pause note; 0.6.0 ticked 0.25 s at once: gsa1_060_pops.md R.4).
-- 0.9.1 (sadc docs/research/gsa1_070_drown.md G1 / G2 with its review R4.3 / R4.9): a death is the game's own
-- (SA1_EVENT_DEATH with its cause: a hit with no rings, a kill, drowning, a death zone; E-102's time running out) - a
-- chat and log line and the hook GSA1CharacterDied - and the game plays its own death through (the drowning one too:
-- the body rises while the drown animation plays) until it asks for the restart (SA1_EVENT_RESTART: 2 s after a hit, 4 s
-- after a drown); the character respawns at its spawn point 1.0 s after that request, as after falling out of the world
-- (and 6 s after a death whose request never comes). The lives go with the respawn (feat/cl_charopt.lua). The session
-- log gets a "game" line for each of the game's events a report needs: its music calls (a jingle - the drowning
-- countdown - starting, the countdown stopping because the character got air, the music stop at the drown, background
-- music), deaths, restart requests, E-102's time running out, respawns. Hooks for the features (hook.Run; an error in
-- one is logged and never breaks a spawn or a tick): GSA1CharacterCreated(C, how, old) right after gsa1.Create, before
-- the first tick (how: "spawned", "switched to", "respawned", "re-created"; old: the character before, gone already),
-- GSA1CharacterLeaving(C, how) before a character is destroyed (its world still there), GSA1CharacterRespawned(C,
-- reason, old), GSA1CharacterRemoved(C, switching), GSA1CharacterDied(C, cause, event), GSA1CharacterRestart(C, id,
-- event), GSA1PreTick(C) before every gsa1.Tick. A character that goes (respawn, re-creation, switch, removal) ends the
-- game's jingle or music stop its world started (gsa1.AudioMusicEnd): the game's restart starts the act's music again.
-- 0.9.2 (sadc docs/research/gsa1_090_plan.md 6.10; gsa1_090_faults.md F3, gsa1_090_player.md L6 / L9, gsa1_090_rings.md F7,
-- gsa1_090_water.md WTR-A / WTR-LOG, with their reviews):
--   * a game code fault (or a fatal stub: the module answers code "fault" for both) restarts the character where it stood
--     (GSA1.TickFault -> GSA1.Recreate) with its rings and lives, with a "fault" line in the session log and a short chat
--     line; 3 faults within 10 s stop it as before, saying why (0.9.0 removed the character at the first fault: "the
--     script dies");
--   * a re-creation (map collision reloaded, upgrades changed, the fault restart) keeps the ring count through the game's
--     own ring call (gsa1.AddRings: 8C08A198); a 1-up it gives for the rings carried over is taken back (gsa1.SetLives) -
--     the game's 1-up sound may still play once (UNVERIFIED in game); a respawn after a death keeps the game's 0 (or the
--     start rings);
--   * "Start with N rings" (gsa1_start_rings) through the module's Create (SA1_CREATE_START_RINGS) for spawns, switches and
--     respawns; "Give 10 / 50 / 100 rings" (GSA1.GiveRings, gsa1_give_rings: single player, an admin or the listen
--     server's host);
--   * "Water follows Garry's Mod's water" (gsa1_hostwater): every tick passes the host's water at the character
--     (GSA1.HostWaterFlags: util.PointContents at the previous tick's state position + 4 units, never the drawn position
--     or the player) as sa1_input.host_flags; the game's water state goes into the session log ("water" lines,
--     GSA1.LogWater in cl_log.lua);
--   * while the Garry's Mod player is dead (a NextBot's Player:Kill) CreateMove lets jump and attack through, so the
--     gamemode's own respawn still works (the interaction feature brings the player back with the character);
--   * seams for later features (the G0 seam rule; no change while unused): GSA1.ViewOverride, GSA1.TickYaw,
--     GSA1.InputBlocked, GSA1.TickCamera, GSA1.NetSendOverride and the hook GSA1PostTick (below, "seams").
-- 0.9.3a (sadc docs/research/super_general_design.md 6.1 / 6.3 / 6.5 with its Review R.4): a character is made by its list
-- entry (C.def: "Super Sonic (General Gameplay)" is kind 0 with a form), and a spawn, a respawn and a re-creation keep it;
-- the seam GSA1.FilterButtons may hold back a press of the player's own buttons (the Super gesture); Super Sonic (Vs.
-- Perfect Chaos, kind 8) has Sonic's upgrades (GSA1.UpgradeKind).
GSA1 = GSA1 or {}

local BTN_JUMP, BTN_ACTION, BTN_ACTION2 = 1, 2, 4
local EV = { SOUND = 1, SOUND_STOP = 2, VOICE = 3, JINGLE = 4, RUMBLE = 5, DEATH = 6, RESTART = 7, RESPAWN = 8,
             MISSING_ACTION = 9, UNIMPLEMENTED = 10, CAPACITY = 11, TIME_UP = 12, FAULT = 13 }
local EV_NAME = {}
for k, v in pairs(EV) do EV_NAME[v] = k end
-- SA1_EVENT_DEATH's cause (arg; libsa1.h SA1_DEATH_*): the chat line and the respawn's reason
local DEATH_TEXT = { [0] = "died", [1] = "was hit with no rings", [2] = "was killed", [3] = "drowned",
                     [4] = "fell into a death zone" }
local DEATH_WORD = { [0] = "died", [1] = "hit with no rings", [2] = "killed", [3] = "drowned", [4] = "death zone" }
GSA1.DEATH_TEXT, GSA1.DEATH_WORD = DEATH_TEXT, DEATH_WORD
-- the game's music calls behind SA1_EVENT_JINGLE (arg = the DC function, id = the music number)
local MUSIC_JINGLE, MUSIC_SET, MUSIC_DELAYED = 0x8C107C80, 0x8C107AC6, 0x8C04EF52
local MUSIC_STOP, MUSIC_RESTORE = 0x8C107ADA, 0x8C107B26
-- the eight music numbers the game plays as jingles (libsa1_audio.h SA1_AUDIO_JINGLE_*: file names only)
GSA1.JINGLES = {
    [96] = "the drowning countdown (TIMER.ADX)", [55] = "invincibility (INVNCIBL.ADX)", [85] = "speed shoes (SPEEDUP.ADX)",
    [45] = "fishing (FISHING.ADX)", [44] = "a fish caught (FISHGET.ADX)", [46] = "the line broke (FISHMISS.ADX)",
    [56] = "an item (ITEM1.ADX)", [26] = "continue (CONTINUE.ADX)",
}
GSA1.RESPAWN_AFTER_RESTART = 1.0     -- s from the game's restart request to the respawn
GSA1.RESPAWN_FALLBACK = 6.0          -- s from a death to the respawn when the game asks for no restart (a drown: 4 s)

-- a feature's hook (hook.Run): an error in it goes into the log and never breaks the caller (a spawn, the tick)
local function run_hook(name, ...)
    if not hook.Run then return end
    local ok, err = pcall(hook.Run, name, ...)
    if not ok then
        if GSA1.Log then GSA1.Log("error", "hook %s: %s", name, tostring(err)) end
        ErrorNoHalt("[G-SA1] hook " .. name .. ": " .. tostring(err) .. "\n")
    end
end
GSA1.RunHook = run_hook

-- a session log line about the game's own events (G2)
local function game_log(fmt, ...)
    if GSA1.Log then GSA1.Log("game", fmt, ...) end
end
local function game_count(group, key)
    if GSA1.LogCount then GSA1.LogCount(group, key) end
end
-- SA1_CAPACITY_* (libsa1.h): what filled up (0.9.2, 092-lib-coll: [3] is no longer reported, the NEAR-poly list holds 512,
-- [8] / [9] are new)
local CAPACITY = {
    [1] = "more collision objects in range than the land collision window holds (128)",
    [2] = "the land collision's polygon budget",
    [3] = "more than 14 land objects within 40 units of the character (a libsa1 before 0.9.2)",
    [4] = "more moving objects than a world holds (64)",
    [5] = "the NEAR-poly list (512 polygons): the map's geometry is too dense or layered here",
    [6] = "the game's matrix stack was left deeper after a step and restored",
    [7] = "more host objects (NPCs, props) near the character than the game's memory takes",
    [8] = "the land collision's query took 15 objects (more land objects around the character than the game's land "
        .. "collision takes at once)",
    [9] = "the land collision's arrays (192) were full (should never happen)",
}
GSA1.CAPACITY_TEXT = CAPACITY

local function prof(name, t0)
    if GSA1.HitchAdd then GSA1.HitchAdd(name, SysTime() - t0) end
end

local input_state = { sx = 0, sy = 0, buttons = 0, pad = false }
local cv_fwd, cv_side, cv_timescale = GetConVar("cl_forwardspeed"), GetConVar("cl_sidespeed"), GetConVar("host_timescale")

function GSA1.FirstPerson()
    return GSA1.Char ~= nil and GSA1.cv.cam_dist:GetFloat() <= 0
end

-- the server runs this addon too (it pooled the network strings); otherwise nothing is sent
local function server_has_gsa1()
    return util.NetworkStringToID(GSA1.NET_ACTIVE) ~= 0 and util.NetworkStringToID(GSA1.NET_STATE) ~= 0
end

local function send_active(on, pos, kind)
    if not server_has_gsa1() then return end
    net.Start(GSA1.NET_ACTIVE)
    net.WriteBool(on)
    if on then
        net.WriteUInt(kind or 0, 4)
    else
        net.WriteVector(pos or LocalPlayer():GetPos())
    end
    net.SendToServer()
end

-- the character's draws for this frame: interpolated root (the drawn position: the root of the step the game drew,
-- which the camera follows) and the render batches. A frame whose draws libsa1 could not interpolate (no draw
-- matched the previous pair: Knuckles' jump draws the ball and the curled body in turn) comes from libsa1 already
-- moved along with the interpolated root (shifted: only reported; 0.4 - 0.5.1 moved it a second time here).
function GSA1.FrameRender(C)
    C.interp = GSA1.cv.interp:GetBool()
    local t0 = SysTime()
    local gen, bgen, x, y, z, yaw, interpolated, alpha, tris, shifted = gsa1.Render(C.id, C.interp and -1 or 1)
    prof("Render", t0)
    if not gen then return false, bgen end
    C.renderGen, C.interpolated, C.alpha, C.triangles, C.drawYaw = gen, interpolated, alpha, tris, yaw
    C.shifted = shifted and true or false
    C.drawPos:SetUnpacked(x, y, z)
    if IsValid(C.ent) then C.ent:SetPos(C.drawPos) end
    if bgen ~= C.batchGen then
        C.batchGen = bgen
        local tb = SysTime()
        gsa1.Batches(C.id, C.batches)
        -- for the session log's context lines
        local nb, ns = 0, 0
        for i = 1, C.batches.count or 0 do
            local b = C.batches[i]
            if b.pass == 1 then nb = nb + 1 end
            if b.prims and bit.band(b.prims, 2) ~= 0 then ns = ns + 1 end
        end
        C.blendedBatches, C.spriteBatches = nb, ns
        prof("Batches", tb)
        C.matsDirty = true
    end
    return true
end

-- the names of a character's ticked upgrades (gsa1_upgrade_<name>); 0.9.3a: Super Sonic (Vs. Perfect Chaos, kind 8) gets
-- Sonic's (GSA1.UpgradeKind; the module gives a kind-8 world Sonic's event flags)
function GSA1.UpgradeNames(kind)
    local out = {}
    for _, u in ipairs(GSA1.UpgradesOf(GSA1.UpgradeKind and GSA1.UpgradeKind(kind) or kind)) do
        local cvar = GSA1.cv["up_" .. u.name]
        if cvar and cvar:GetBool() then out[#out + 1] = u.name end
    end
    return out
end

-- upgrade names -> "Title, Title" ("none")
function GSA1.UpgradeText(names)
    local titles = {}
    for _, n in ipairs(names or {}) do
        for _, u in ipairs(GSA1.UPGRADES) do
            if u.name == n then titles[#titles + 1] = u.title end
        end
    end
    return #titles > 0 and table.concat(titles, ", ") or "none"
end

-- the class of the weapon in the local player's hands ("none"; the empty hands of a character do not count)
local function held_weapon()
    local ply = LocalPlayer()
    local w = IsValid(ply) and ply.GetActiveWeapon and ply:GetActiveWeapon()
    if IsValid(w) and w:GetClass() ~= GSA1.HANDS then return w:GetClass() end
    return "none"
end

-- 0.9.2 (rings F7, gsa1_090_rings.md review R4.11): the rings a new character starts with - "Start with N rings"
-- (gsa1_start_rings, 1..99), nil = the game's 0
function GSA1.StartRings()
    local cv = GSA1.cv.start_rings
    local n = cv and cv:GetInt() or 0
    if n <= 0 then return nil end
    return math.min(n, tonumber(gsa1 and gsa1.START_RINGS_MAX) or 99)
end

-- how: "spawned", "switched to", "respawned", "re-created" (the session log's spawn line); old: the character before
-- (destroyed already; the GSA1CharacterCreated hook gets it: its lives, its death); rings: the start rings (nil = the
-- game's 0; a re-creation passes none and carries the old count over afterwards, GSA1.Recreate); def (0.9.3a): the list
-- entry (GSA1.CHARACTERS) - the character is made BY ENTRY: "Super Sonic (General Gameplay)" is kind 0 with a form (its
-- extras, feat/cl_super.lua); nil = the kind's own entry
local function create_character(kind, pos, yaw, how, old, rings, def)
    def = def or GSA1.CharacterByKind(kind)
    local ups = GSA1.UpgradeNames(kind)
    local t0 = SysTime()
    -- seam (0.9.3): a feature's extras for the module's Create (Super Sonic's world, feat/cl_super.lua); an error in it is
    -- logged and the character is made without them. 0.9.3a: also the entry and the character before (its form)
    local extras = nil
    if GSA1.CreateExtras then
        local eok, ex = pcall(GSA1.CreateExtras, kind, how, rings, def, old)
        if eok then extras = ex elseif GSA1.Log then GSA1.Log("error", "GSA1.CreateExtras: %s", tostring(ex)) end
    end
    local id, err = gsa1.Create(kind, pos, yaw, ups, rings, extras)
    local create_ms = (SysTime() - t0) * 1000
    prof("Create", t0)
    GSA1.DrainLog()
    if not id then return nil, err end
    local tt = SysTime()
    GSA1.Tex.Prepare(kind)
    local tex_ms = (SysTime() - tt) * 1000
    prof("Textures", tt)
    local ent = ents.CreateClientside("gsa1_render")
    ent:Spawn()
    local C = {
        id = id, kind = kind, name = def and def.name or tostring(kind), title = def and def.title or tostring(kind),
        def = def, form = def and def.form or nil,
        info = gsa1.CharacterInfo(kind) or {}, state = {}, batches = { count = 0 }, batchGen = -1, mats = {},
        static = {}, matsDirty = true, last = SysTime(), spawnPos = pos, spawnYaw = yaw, ent = ent, nextNet = 0,
        nextActive = 0, drawPos = Vector(pos), upgrades = ups, startRings = rings, extras = extras,
    }
    ent.char = C
    gsa1.GetState(id, C.state)
    C.drawPos:SetUnpacked(C.state.x, C.state.y, C.state.z)
    ent:SetPos(C.drawPos)
    -- the features set the new character up before its first tick (its lives, Amy's bird, Tails' tail blend)
    run_hook("GSA1CharacterCreated", C, how or "created", old)
    local tr = SysTime()
    GSA1.FrameRender(C)
    local render_ms = (SysTime() - tr) * 1000
    local warm = GSA1.Warm and GSA1.Warm.Start(C) or 0
    if GSA1.Log then
        -- a first spawn: the weapon the server puts away (sv_gsa1.lua)
        local weapon = how == "spawned" and ("; weapon put away: " .. held_weapon()) or ""
        GSA1.Log("spawn", "%s %s in %.1f ms (gsa1.Create %.1f ms, texture list %.1f ms, first render %.1f ms); "
            .. "upgrades: %s; %d textures to paint, %d materials and states to pre-warm%s%s%s", C.title, how or "created",
            (SysTime() - t0) * 1000, create_ms, tex_ms, render_ms, GSA1.UpgradeText(ups), GSA1.Tex.Pending(), warm,
            weapon, C.lives and string.format("; lives %d", C.lives) or "",
            rings and string.format("; starts with %d rings", rings) or "")
    end
    return C
end

-- the game's music its world started (a jingle, the music stop at a drown) ends with the character: the game's own
-- restart starts the act's music again (gsa1_070_drown.md J1: the jukebox waits for no jingle of a world that is gone)
local music_out = {}
local function end_game_music(C, how)
    if not (GSA1.mod and gsa1.AudioMusicState and gsa1.AudioMusicEnd) then return end
    local ms = gsa1.AudioMusicState(music_out)
    if type(ms) ~= "table" then return end
    local j = tonumber(ms.jingle) or -1
    if j < 0 and not ms.stopped then return end
    gsa1.AudioMusicEnd()
    game_log("the game's %s ended with %s (%s)", j >= 0 and string.format("jingle %d %s", j, tostring(ms.name or ""))
        or "music stop", C.title or "the character", how or "removed")
end

-- how: "removed", "switched", "respawned", "re-created"
local function destroy_character(C, how)
    run_hook("GSA1CharacterLeaving", C, how or "removed")
    if GSA1.mod and C.id then gsa1.Destroy(C.id) end
    end_game_music(C, how)
    GSA1.FreeStaticMeshes(C)
    if IsValid(C.ent) then C.ent:Remove() end
end

-- switching: another character follows at once (GSA1.Spawn), so the server is not told "off" - it would give the
-- weapon back and put it away again, and the empty hands removed in between are still there in that tick (Entity:Remove
-- takes effect at the start of the next one: gsa1_060_weapon.md review R.3.2)
function GSA1.Remove(silent, switching)
    GSA1.pendingSpawn = nil
    local C = GSA1.Char
    if not C then return end
    GSA1.Char = nil
    destroy_character(C, switching and "switched" or "removed")
    if GSA1.MoversClear then GSA1.MoversClear() end
    if not switching then send_active(false, C.drawPos) end
    if not silent then GSA1.Msg("%s removed", C.title) end
    run_hook("GSA1CharacterRemoved", C, switching and true or false)
end

function GSA1.Spawn(name)
    if not name or name == "" then name = GSA1.cv.character:GetString() end
    local kind, def = GSA1.KindByName(name)
    if not kind then
        GSA1.Chat("unknown character '%s' (sonic, tails, knuckles, amy, gamma, big, supersonic, supersonic_general)", tostring(name))
        return
    end
    GSA1.pendingSpawn = nil
    local ok, err = GSA1.EnsureReady()
    if not ok then
        if err == "loading" then
            -- the disc or the map's collision is still loading: the spawn happens by itself when they are ready
            -- (cl_module.lua: GSA1.InitThink, GSA1.ApplyWorld)
            GSA1.pendingSpawn = def.name
            GSA1.Chat("%s; %s spawns when it is ready", GSA1.LoadingText() or "loading", def.title)
        else
            GSA1.Chat("%s", tostring(err))
        end
        return
    end
    local ply = LocalPlayer()
    local pos = GSA1.Char and Vector(GSA1.Char.drawPos) or ply:GetPos() + Vector(0, 0, 4)
    local yaw = ply:EyeAngles().y
    local how = GSA1.Char and "switched to" or "spawned"
    local switching = GSA1.Char ~= nil
    local old = GSA1.Char
    GSA1.Remove(true, switching)
    local C, cerr = create_character(kind, pos, yaw, how, old, GSA1.StartRings(), def)
    if not C then
        GSA1.Chat("cannot create %s: %s", def.title, tostring(cerr))
        if switching then send_active(false, pos) end        -- the old character is gone and no new one came
        return
    end
    GSA1.Char = C
    GSA1.cv.character:SetString(def.name)
    send_active(true, nil, kind)
    GSA1.Msg("%s spawned at (%.0f %.0f %.0f), upgrades: %s; %d textures loading", def.title, pos.x, pos.y, pos.z,
        GSA1.UpgradeText(C.upgrades), GSA1.Tex.Pending())
end

-- recreate the current character at its spawn point (death, restart request, world reload)
function GSA1.Respawn(reason)
    local C = GSA1.Char
    if not C then return end
    destroy_character(C, "respawned")
    GSA1.Char = nil
    local NC, err = create_character(C.kind, C.spawnPos, C.spawnYaw, "respawned", C, GSA1.StartRings(), C.def)
    if not NC then
        GSA1.Chat("cannot respawn %s: %s", C.title, tostring(err))
        send_active(false, C.drawPos)
        run_hook("GSA1CharacterRemoved", C, false)
        return
    end
    GSA1.Char = NC
    game_count("respawns", C.death and (C.timeUp and "time up" or (DEATH_WORD[C.death.cause] or "died")) or
        (C.fellOut and "fell out of the world" or (C.restartAt and "restart" or "other")))
    GSA1.Msg("%s respawned (%s)%s", NC.title, reason or "", NC.lives and string.format("; lives %d", NC.lives) or "")
    run_hook("GSA1CharacterRespawned", NC, reason or "", C)
end

-- why the current character respawns now (the session log, GSA1.Respawn's message)
local function respawn_reason(C)
    if C.death then
        local w = C.timeUp and "time up" or (DEATH_WORD[C.death.cause] or "died")
        return C.restartAt and w or (w .. "; the game asked for no restart")
    end
    if C.fellOut then return "fell out of the world" end
    if C.restartAt then return "the game asked for the restart" end
    return "respawn"
end

-- the game's ring count of character C (the interaction feature's gsa1.StateEx; nil without it)
local rings_probe = {}
function GSA1.CharacterRings(C)
    if not (C and C.id and GSA1.mod and gsa1.StateEx) then return nil end
    local ok, s = pcall(gsa1.StateEx, C.id, rings_probe)
    if not ok or type(s) ~= "table" then return nil end
    return tonumber(s.rings)
end

-- L9 (gsa1_090_player.md review R.4 G2 / R.5 item 8): a re-created character gets the rings of the one before it through
-- the game's own ring call (gsa1.AddRings: 8C08A198; one call per 1000). That call gives a 1-up for every hundred it
-- passes, as in the game; those are not new rings, so the life counter is put back (gsa1.SetLives) - the lives went over
-- already (feat/cl_charopt.lua). Returns true when the rings were carried over.
function GSA1.KeepRings(NC, n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 or not NC or not (GSA1.mod and gsa1.AddRings) then return false end
    local lives0 = gsa1.GetLives and tonumber(gsa1.GetLives(NC.id)) or nil
    local left = n
    while left > 0 do
        local step = math.min(left, 1000)
        local ok, err = gsa1.AddRings(NC.id, step)
        if not ok then
            game_log("%s: the %d rings could not be kept: %s", NC.title or "?", n, tostring(err))
            return false
        end
        left = left - step
    end
    if lives0 and gsa1.SetLives then
        local lives1 = tonumber(gsa1.GetLives(NC.id))
        if lives1 and lives1 ~= lives0 then
            gsa1.SetLives(NC.id, lives0)
            NC.lives = lives0
        end
    end
    NC.keptRings = n
    return true
end

-- re-create the current character where it stands (its upgrades changed, the map's collision was reloaded, a game code
-- fault): the same place and facing, standing still (a new character starts in its standing action; the speed is not
-- kept), its rings (0.9.2, L9) and lives (feat/cl_charopt.lua); the spawn point for deaths stays the old one.
-- 0.9.2a (sadc docs/research/gsa1_091a_teleport.md T0): pos / yaw (optional) re-create it there instead (a teleport,
-- feat/cl_teleport.lua); returns the new character (nil if none)
function GSA1.Recreate(reason, at, at_yaw)
    local C = GSA1.Char
    if not C then return end
    local pos = Vector(at or C.drawPos)
    pos.z = pos.z + 1
    local yaw = at_yaw or C.drawYaw or C.spawnYaw
    local rings = GSA1.CharacterRings(C)       -- read while its world is still there
    destroy_character(C, "re-created")
    GSA1.Char = nil
    local NC, err = create_character(C.kind, pos, yaw, "re-created", C, nil, C.def)
    if not NC then
        GSA1.Chat("cannot re-create %s: %s", C.title, tostring(err))
        send_active(false, C.drawPos)
        run_hook("GSA1CharacterRemoved", C, false)
        return
    end
    NC.spawnPos, NC.spawnYaw = C.spawnPos, C.spawnYaw
    GSA1.Char = NC
    local kept = GSA1.KeepRings(NC, rings)
    GSA1.Msg("%s re-created %s (%s); upgrades: %s%s", NC.title, at and string.format("at (%.0f %.0f %.0f)", pos.x, pos.y,
        pos.z) or "where it stood", reason or "", GSA1.UpgradeText(NC.upgrades),
        kept and string.format("; %d rings kept", rings) or "")
    return NC
end

-- F3 (gsa1_090_faults.md F3 with its review R.2.5 / R.2.7; owner defaults: restart where it stood, rings kept, no life
-- lost, a short chat line): a tick that failed with code "fault" - a game code fault, or a fatal stub (a module of 0.9.2
-- answers "fault" for both; an older one says "not implemented") - restarts the character instead of removing it. The
-- session log gets a "fault" line with the message (the game function and address) and the count; FAULT_MAX faults within
-- FAULT_WINDOW seconds stop it as 0.9.1 did, with a chat line saying why (no restart loop). Returns true when it handled
-- the failure.
GSA1.FAULT_WINDOW, GSA1.FAULT_MAX = 10, 3
local fault_times = {}
function GSA1.TickFault(C, err, code)
    local msg = tostring(err or "?")
    if code ~= "fault" and not string.find(msg, "not implemented", 1, true) then return false end
    local now = SysTime()
    for i = #fault_times, 1, -1 do
        if now - fault_times[i] > GSA1.FAULT_WINDOW then table.remove(fault_times, i) end
    end
    fault_times[#fault_times + 1] = now
    local n = #fault_times
    if GSA1.Log then
        GSA1.Log("fault", "%s: game code fault %d within %d s: %s", C.title or "?", n, GSA1.FAULT_WINDOW, msg)
    end
    game_count("faults", n >= GSA1.FAULT_MAX and "stopped" or "restarted")
    run_hook("GSA1CharacterFault", C, msg, n)
    if n >= GSA1.FAULT_MAX then
        for i = #fault_times, 1, -1 do fault_times[i] = nil end
        GSA1.Chat("%s stopped: its game code faulted %d times within %d s (see the session log); spawn it again to "
            .. "retry", C.title or "?", GSA1.FAULT_MAX, GSA1.FAULT_WINDOW)
        GSA1.Remove(true)
        return true
    end
    GSA1.Chat("%s's game code faulted; restarted where it stood (rings kept, no life lost)", C.title or "?")
    GSA1.Recreate("restart after a game code fault")
    return true
end

-- Rings F7 (gsa1_090_rings.md F7 with its review R4.11; owner default: admin-only in multiplayer): "Give 10 / 50 / 100
-- rings" on the Character page and gsa1_give_rings <n> - the game's own ring call (gsa1.AddRings: 8C08A198), so 100 gives
-- the game's 1-up. 0.9.2a: one rule with gsa1_rings (feat/sh_giverings.lua GSA1.RingsRule: single player, sv_cheats 1, an
-- admin or the listen server's host), asked of the server too in multiplayer (GSA1.RingsRequest).
function GSA1.RingsAllowed()
    if GSA1.RingsRule then return (GSA1.RingsRule(LocalPlayer())) end
    if game.SinglePlayer() then return true end
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end
    local sc = GetConVar("sv_cheats")
    if sc and sc:GetBool() then return true end
    if ply.IsListenServerHost and ply:IsListenServerHost() then return true end
    return ply.IsAdmin ~= nil and ply:IsAdmin() == true
end

function GSA1.GiveRings(n)
    n = math.floor(tonumber(n) or 0)
    local C = GSA1.Char
    if not C then
        GSA1.Chat("Give rings: no character (spawn one first)")
        return false
    end
    if n <= 0 or n > 999 then
        GSA1.Chat("Give rings: 1 to 999 rings, e.g. gsa1_give_rings 50")
        return false
    end
    if not (GSA1.mod and gsa1.AddRings) then
        GSA1.Chat("Give rings needs the G-SA1 module 0.9.0 or newer (its interaction part)")
        return false
    end
    if not GSA1.RingsAllowed() then
        GSA1.Chat("Give rings: in multiplayer only an admin or the server's host may give rings (or anyone with sv_cheats 1)")
        game_log("Give rings %d refused: multiplayer, not an admin", n)
        return false
    end
    local function apply()
        local CC = GSA1.Char
        if not CC then return false end
        local ok, err = gsa1.AddRings(CC.id, n)
        if not ok then
            GSA1.Chat("Give rings: %s", tostring(err))
            return false
        end
        game_log("%s got %d rings (Give rings)", CC.title or "?", n)
        GSA1.Msg("%s got %d rings", CC.title or "?", n)
        return true
    end
    -- multiplayer: the server checks the same rule first (feat/sh_giverings.lua)
    if GSA1.RingsRequest then return GSA1.RingsRequest("Give rings", n, apply) end
    return apply()
end

-- an upgrade of the current character was ticked or unticked: re-create it a moment later (one re-creation for
-- several changes in a row, e.g. "all on")
local recreate_at = nil
for _, u in ipairs(GSA1.UPGRADES) do
    cvars.AddChangeCallback("gsa1_upgrade_" .. u.name, function()
        local C = GSA1.Char
        if C and GSA1.UpgradeKind(C.kind) == u.kind then recreate_at = SysTime() + 0.25 end
    end, "gsa1_upgrades")
end

-- the game's music calls (SA1_EVENT_JINGLE): session log lines (G2); the module's mixer has played them already
local function music_event(C, e)
    local fn, m = tonumber(e.arg) or 0, tonumber(e.id) or -1
    if fn == MUSIC_JINGLE then
        -- the drowning countdown asks for its jingle in two frames in a row (8C07BE6E): one line
        if C.lastJingle == m and (e.step or 0) - (C.lastJingleStep or -1000) <= 4 then return end
        C.lastJingle, C.lastJingleStep = m, e.step or 0
        if m == 96 then C.countdown = e.step or 0 end
        game_count("jingles", m)
        game_log("%s: the game plays the jingle %d, %s (step %d)", C.title, m, GSA1.JINGLES[m] or "not one of its usual "
            .. "jingles", e.step or 0)
    elseif fn == MUSIC_STOP then
        game_log("%s: the game stopped its music (step %d)%s", C.title, e.step or 0,
            C.countdown and ": the drown, the countdown ran out" or "")
    elseif fn == MUSIC_RESTORE then
        if C.countdown and not C.death then
            game_log("%s: the drowning countdown stopped, %s got air or left the water (step %d, %d steps after it "
                .. "started)", C.title, C.title, e.step or 0, (e.step or 0) - C.countdown)
        else
            game_log("%s: the game went back to its music (step %d)", C.title, e.step or 0)
        end
        C.countdown = nil
    elseif fn == MUSIC_SET or fn == MUSIC_DELAYED then
        game_log("%s: the game asked for the background music %d (step %d)", C.title, m, e.step or 0)
    end
end

local function on_event(C, e, now)
    local dbg = GSA1.cv.debug:GetBool()
    now = now or SysTime()
    if e.type == EV.DEATH then
        -- libsa1 reports a world's first death only (its later restart requests are no new death)
        if not C.death then
            local cause = tonumber(e.arg) or 0
            C.death = { cause = cause, step = e.step or 0, at = now }
            local what = C.timeUp and "ran out of time" or (DEATH_TEXT[cause] or "died")
            GSA1.Chat("%s %s", C.title, what)
            game_log("%s %s (death cause %d, step %d) at (%.0f %.0f %.0f)%s", C.title, what, cause, e.step or 0, e.x or 0,
                e.y or 0, e.z or 0, (e.id or 0) ~= 0 and string.format(", by host object %d", e.id) or "")
            -- the game plays its death through (the drown: about 4 s) and asks for the restart itself; the respawn
            -- follows that request (review R4.3: not a timer from here), this one only when none comes
            C.fallbackAt = now + GSA1.RESPAWN_FALLBACK
            game_count("deaths", C.timeUp and "time up" or (DEATH_WORD[cause] or cause))
            run_hook("GSA1CharacterDied", C, cause, e)
        end
    elseif e.type == EV.RESTART or e.type == EV.RESPAWN then
        if not C.restartAt then
            C.restartAt = now
            C.respawnAt = C.respawnAt or (now + GSA1.RESPAWN_AFTER_RESTART)
            game_log("%s: the game asked for %s (id %d, step %d)%s; respawn in %.1f s", C.title,
                e.type == EV.RESTART and "the restart" or "the start position", e.id or 0, e.step or 0,
                C.death and string.format(", %.1f s after the death", now - C.death.at) or "",
                math.max(C.respawnAt - now, 0))
            game_count("restarts", "id " .. tostring(e.id or 0))
            run_hook("GSA1CharacterRestart", C, e.id or 0, e)
        end
    elseif e.type == EV.TIME_UP then
        C.timeUp = true
        game_log("%s's time ran out (step %d)", C.title, e.step or 0)
    elseif e.type == EV.JINGLE then
        music_event(C, e)
    elseif e.type == EV.FAULT then
        -- a character restarted after a fault (GSA1.TickFault) gets its predecessor's fault event with its first events:
        -- the restart said it already
        if e.character and e.character ~= 0 and e.character ~= C.id then
            if GSA1.Log then GSA1.Log("fault", "the earlier %s's fault event (address %08X)", C.title, e.id) end
        else
            GSA1.Chat("%s's game code faulted (address %08X); see the console", C.title, e.id)
        end
    elseif e.type == EV.UNIMPLEMENTED then
        if dbg then GSA1.Msg("game code reached %08X, which libsa1 does not have", e.id) end
    elseif e.type == EV.CAPACITY then
        -- libsa1 reports each situation once when it begins; a map-side report of where the geometry is too dense
        local now = SysTime()
        C.capacityAt = C.capacityAt or {}
        if now >= (C.capacityAt[e.id] or 0) then
            C.capacityAt[e.id] = now + 5
            GSA1.Note("capacity", "capacity at (%.0f %.0f %.0f): %s (%d)", e.x, e.y, e.z,
                CAPACITY[e.id] or ("limit " .. e.id), e.arg)
        end
    end
    if dbg then
        GSA1.Msg("event %s id %.0f bank %.0f arg %.0f step %.0f at (%.0f %.0f %.0f)", EV_NAME[e.type] or tostring(e.type),
            e.id, e.bank, e.arg, e.step, e.x, e.y, e.z)
    end
    -- sound effects, voices and jingles: the module has already given them to its mixer (gsa1.AudioUpdate)
end

-- seams (0.9.2; sadc docs/research/gsa1_090_plan.md 6.10 task 8, decision 7: later features hook in here instead of
-- editing this file). Each default changes nothing. A feature replaces the function, keeps the one it replaced, and calls
-- it when it has nothing to say itself:
--   GSA1.ViewOverride(view, C, ply) -> view | nil   CalcView ("gsa1_view"), after the view-entity check and G-SA1's own
--                                                   view: a table with an origin is this frame's view (the fishing
--                                                   camera, 0.9.6)
--   GSA1.TickYaw(C) -> degrees | nil                the tick's camera yaw, the stick's frame (same); nil: the view's yaw
--   GSA1.InputBlocked() -> bool                     true: the character gets a neutral pad (stick 0, no buttons) and the
--                                                   controller does not turn the view (a panel has the input: the
--                                                   Character Select chooser, 0.9.3)
--   GSA1.TickCamera(C) -> origin, target | nil      the host camera passed into sa1_input (asked only when the module and
--                                                   libsa1 take it: gsa1.TICK_HOST_CAMERA, libsa1's round 0.9.4); by
--                                                   default this frame's main view and a point 100 units ahead of it
--   GSA1.NetSendOverride = fn(C, state, now)        set: called every tick instead of the built-in 20 Hz gsa1_state send
--                                                   (the player follow, 0.9.3)
--   hook GSA1PostTick(C, state, dt)                 after each tick (state: C.state from gsa1.GetState; dt: the time
--                                                   ticked), before the respawn checks
--   GSA1.CreateExtras(kind, how, rings, def, old) -> table | nil   (0.9.3) the extras table of gsa1.Create for a new
--                                                   character (how: as GSA1CharacterCreated's; rings: the start rings
--                                                   asked for; 0.9.3a: def = its list entry, old = the character before):
--                                                   Super Sonic's world (feat/cl_super.lua); kept in C.extras
--   GSA1.FilterButtons(C, buttons) -> buttons       (0.9.3a) the player's own buttons for this tick (keyboard and
--                                                   controller, before GSA1.ExtraButtons): the Super gesture's press is
--                                                   held back (feat/cl_super.lua); by default unchanged
--   GSA1.FilterStick(C, sx, sy) -> sx, sy           (0.9.4a) the stick for this tick, right before GSA1.FilterButtons: the
--                                                   emote wheel stops the character while you choose (feat/cl_wheel.lua,
--                                                   gsa1_wheel_move 0); by default unchanged
--   GSA1.BindOverride(ply, bind, pressed, code) -> bool | nil   (0.9.4a) asked first by the PlayerBindPress hook "gsa1"
--                                                   (bind in lower case): true / false is the hook's answer, nil lets
--                                                   G-SA1 decide - the open emote wheel turns its pages with the mouse
--                                                   wheel instead of the camera distance (feat/cl_wheel.lua)
GSA1.CreateExtras = GSA1.CreateExtras or function(kind, how, rings, def, old) return nil end
GSA1.FilterButtons = GSA1.FilterButtons or function(C, buttons) return buttons end
GSA1.FilterStick = GSA1.FilterStick or function(C, sx, sy) return sx, sy end
GSA1.BindOverride = GSA1.BindOverride or function() return nil end
GSA1.ViewOverride = GSA1.ViewOverride or function(view, C, ply) return nil end
GSA1.TickYaw = GSA1.TickYaw or function(C) return nil end
GSA1.InputBlocked = GSA1.InputBlocked or function() return false end
function GSA1.DefaultTickCamera(C)
    local v = GSA1.view
    if not (v and v.frame and v.origin and v.angles and FrameNumber() - v.frame <= 2) then return nil end
    C.camO, C.camT = C.camO or Vector(), C.camT or Vector()
    C.camO:Set(v.origin)
    C.camT:Set(v.angles:Forward())
    C.camT:Mul(100)
    C.camT:Add(v.origin)
    return C.camO, C.camT
end
GSA1.TickCamera = GSA1.TickCamera or GSA1.DefaultTickCamera

-- WTR-A, the G-SA1 half (gsa1_090_water.md WTR-A with its review R3.5; owner default B1 (a)): the host's water at the
-- character for the next tick - util.PointContents 4 units (the game's probe point, the feet + 1 SA1 unit) above the
-- previous tick's libsa1 state position (C.state; never the drawn position or the player entity, which lag behind) -
-- KNOWN | IN_WATER in Garry's Mod water or slime, else KNOWN; 0 with "Water follows Garry's Mod's water" off
-- (gsa1_hostwater 0: the game's own rule) or a module that does not take host flags
local CONTENTS_WET = bit.bor(CONTENTS_WATER or 0x20, CONTENTS_SLIME or 0x10)
local water_probe = Vector()
function GSA1.HostWaterFlags(C)
    if not (GSA1.mod and gsa1.TICK_HOST_FLAGS and GSA1.cv.hostwater and GSA1.cv.hostwater:GetBool()) then return 0 end
    local s = C and C.state
    if not (s and s.x and util.PointContents) then return 0 end
    water_probe:SetUnpacked(s.x, s.y, s.z + 4)
    local known = tonumber(gsa1.INPUT_HOST_WATER_KNOWN) or 1
    if bit.band(util.PointContents(water_probe) or 0, CONTENTS_WET) ~= 0 then
        return bit.bor(known, tonumber(gsa1.INPUT_HOST_IN_WATER) or 2)
    end
    return known
end

-- input --------------------------------------------------------------------------------------------------------------
-- L6, client half (gsa1_090_player.md review R.2 (d), R.5 item 7): while the player is dead its jump and attack presses
-- go through to the server, where the gamemode's PlayerDeathThink respawns it (the interaction feature holds that back
-- while the character is about to bring the player back); 0.9.1 cleared them and a dead G-SA1 player never came back
local DEAD_KEEP = bit.bor(IN_JUMP or 2, IN_ATTACK or 1, IN_ATTACK2 or 2048)
hook.Add("CreateMove", "gsa1_input", GSA1.Guard("CreateMove", function(cmd)
    if not GSA1.Char then return end
    if GSA1.InputBlocked and GSA1.InputBlocked() then
        input_state.sx, input_state.sy, input_state.buttons = 0, 0, 0
    else
        local fs = math.max(cv_fwd and cv_fwd:GetFloat() or 10000, 1)
        local ss = math.max(cv_side and cv_side:GetFloat() or 10000, 1)
        local x, y = cmd:GetSideMove() / ss, cmd:GetForwardMove() / fs
        local m = math.sqrt(x * x + y * y)
        if m > 1 then x, y = x / m, y / m end
        if cmd:KeyDown(IN_WALK) then x, y = x * 0.5, y * 0.5 end
        local b = 0
        if cmd:KeyDown(IN_JUMP) then b = bit.bor(b, BTN_JUMP) end
        if cmd:KeyDown(IN_DUCK) or cmd:KeyDown(IN_ATTACK) or cmd:KeyDown(IN_ATTACK2) then b = bit.bor(b, BTN_ACTION) end
        if cmd:KeyDown(IN_RELOAD) then b = bit.bor(b, BTN_ACTION2) end
        input_state.sx, input_state.sy, input_state.buttons = x, y, b
        if GSA1.PadView then GSA1.PadView(cmd) end
    end
    local keep = 0
    local ply = LocalPlayer()
    if IsValid(ply) and ply.Alive and not ply:Alive() and cmd.GetButtons then
        keep = bit.band(cmd:GetButtons(), DEAD_KEEP)
    end
    cmd:ClearMovement()
    cmd:ClearButtons()
    if keep ~= 0 then cmd:SetButtons(keep) end
end))

-- simulation -----------------------------------------------------------------------------------------------------
local next_log = 0
local cv_volume, cv_mute_focus = GetConVar("volume"), GetConVar("snd_mute_losefocus")
local function game_paused()
    return FrameTime() == 0 or (game.SinglePlayer() and gui.IsGameUIVisible())
end

-- the listener is the view (the chase camera's origin and angles from CalcView, else the player's eyes)
local audio_fwd, audio_up = Vector(), Vector()
local function update_audio()
    if not gsa1.AudioUpdate then return end
    local v = GSA1.view
    local origin, ang
    if v and v.frame and FrameNumber() - v.frame <= 2 then
        origin, ang = v.origin, v.angles
    else
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        origin, ang = ply:EyePos(), ply:EyeAngles()
    end
    local paused = game_paused() or (cv_mute_focus and cv_mute_focus:GetBool() and not system.HasFocus())
    -- (0.9.4d: the listener's axes into reused Vectors, not two new ones a frame)
    local fwd, up
    if GSA1.AngleAxes then
        GSA1.AngleAxes(ang, audio_fwd, nil, audio_up)
        fwd, up = audio_fwd, audio_up
    else
        fwd, up = ang:Forward(), ang:Up()
    end
    gsa1.AudioUpdate(origin, fwd, up, cv_volume and cv_volume:GetFloat() or 1, paused and true or false, RealFrameTime())
end

local net_state = {}            -- the state packet's table (reused)
local events = {}               -- gsa1.PollEvents' table (reused, with its event tables: no garbage per frame)

local function tick_character(now)
    local C = GSA1.Char
    if not C or not GSA1.mod then return end
    local dt = math.Clamp(now - C.last, 0, 0.25)
    C.last = now
    -- paused now, or during the frame that just ended (Think does not run while single player is paused, so the first
    -- Think after the escape menu saw the whole pause: cl_hitch.lua's note)
    if game_paused() or (GSA1.Hitch and GSA1.Hitch.tickPaused) then dt = 0 end
    dt = dt * (cv_timescale and cv_timescale:GetFloat() or 1)
    -- the stick's frame: the view's yaw, or a feature's (GSA1.TickYaw: the fishing camera, 0.9.6)
    local yaw = GSA1.TickYaw and GSA1.TickYaw(C) or LocalPlayer():EyeAngles().y
    local sx, sy, buttons = input_state.sx, input_state.sy, input_state.buttons
    local extra = 0
    if GSA1.InputBlocked and GSA1.InputBlocked() then
        -- a panel has the input (GSA1.InputBlocked): a neutral pad
        sx, sy, buttons = 0, 0, 0
        input_state.pad = false
    else
        -- the controller has priority while it is in use (its stick; its buttons add to the keyboard's)
        local psx, psy, pbuttons
        if GSA1.PadInput then psx, psy, pbuttons = GSA1.PadInput() end
        input_state.pad = psx ~= nil
        if psx then
            sx, sy, buttons = psx, psy, bit.bor(buttons, pbuttons)
        end
        -- a feature may press the game's buttons for a moment (round 5: the interact key lifts / throws a prop with the
        -- game's action button, feat/cl_interact.lua); added after GSA1.FilterButtons (below)
        if GSA1.ExtraButtons then extra = GSA1.ExtraButtons(C) or 0 end
    end
    if GSA1.MoversThink then GSA1.MoversThink(C, now) end
    -- features before the game's steps ("Characters can drown" off holds the air timer: feat/cl_charopt.lua)
    run_hook("GSA1PreTick", C)
    if GSA1.Char ~= C then return end
    -- seam (0.9.3a, sadc docs/research/super_general_design.md 6.3 with its Review RC2 / RC3): a feature may take a button
    -- of the player's OWN input (keyboard and controller) away for this tick - the Super transformation's gesture (jump,
    -- then the action button in the air) keeps its press from the game until it is released (feat/cl_super.lua). The
    -- synthetic presses of GSA1.ExtraButtons are added after it, so the interact key never transforms anybody. An error is
    -- logged and the buttons go through unchanged.
    -- seam (0.9.4a): a feature may change the stick for this tick (the emote wheel: "stop while choosing"); an error is
    -- logged and the stick goes through unchanged
    if GSA1.FilterStick then
        local sok, fsx, fsy = pcall(GSA1.FilterStick, C, sx, sy)
        if sok then
            if type(fsx) == "number" and type(fsy) == "number" then sx, sy = fsx, fsy end
        elseif GSA1.Log then
            GSA1.Log("error", "GSA1.FilterStick: %s", tostring(fsx))
        end
        if GSA1.Char ~= C then return end
    end
    if GSA1.FilterButtons then
        local fok, fb = pcall(GSA1.FilterButtons, C, buttons)
        if fok then
            if type(fb) == "number" then buttons = fb end
        elseif GSA1.Log then
            GSA1.Log("error", "GSA1.FilterButtons: %s", tostring(fb))
        end
        if GSA1.Char ~= C then return end
    end
    buttons = bit.bor(buttons, extra)
    -- 0.9.2: the host's water at the character (WTR-A) and, when libsa1 takes it, the host camera (seams)
    local hflags = GSA1.HostWaterFlags(C)
    C.hostFlags = hflags
    local co, ct
    if gsa1.TICK_HOST_CAMERA and GSA1.TickCamera then co, ct = GSA1.TickCamera(C) end
    local t0 = SysTime()
    local npairs, err, code = gsa1.Tick(C.id, sx, sy, yaw, buttons, dt, GSA1.cv.stick_raw:GetBool(), hflags, co, ct)
    prof("Tick", t0)
    if not npairs then
        -- F3: a game code fault restarts the character (GSA1.TickFault); anything else stops it as before
        if GSA1.TickFault(C, err, code) then return end
        GSA1.Chat("%s stopped: %s", C.title, tostring(err))
        GSA1.Remove(true)
        return
    end
    local st = C.state
    gsa1.GetState(C.id, st)
    -- WTR-LOG: the game's water state against Garry's Mod's (cl_log.lua)
    if GSA1.LogWater then GSA1.LogWater(C, st) end
    local rok, rerr = GSA1.FrameRender(C)
    if not rok and not C.renderError then
        C.renderError = true
        GSA1.Msg("render: %s", tostring(rerr))
    end
    local te = SysTime()
    local ev = gsa1.PollEvents(events)
    for i = 1, ev.count or #ev do
        on_event(C, ev[i], now)
    end
    prof("Events", te)
    -- the features after the tick (seam: the player follow, 0.9.3)
    run_hook("GSA1PostTick", C, st, dt)
    if GSA1.Char ~= C then return end
    -- below the map (a hole in the collision): back to the spawn point (no death of the game: no life lost)
    local wi = GSA1.worldInfo
    if wi and st.z < wi.min_z - 1024 and not C.respawnAt then
        C.respawnAt = now
        C.fellOut = true
    end
    if (C.respawnAt and now >= C.respawnAt) or (C.fallbackAt and now >= C.fallbackAt) then
        GSA1.Respawn(respawn_reason(C))
        return
    end
    -- owner-authoritative state to the server (it moves the player entity along); a feature may send it its own way
    -- (seam GSA1.NetSendOverride: the player follow, 0.9.3)
    if GSA1.NetSendOverride then
        local ok, nerr = pcall(GSA1.NetSendOverride, C, st, now)
        if not ok and GSA1.Log then GSA1.Log("error", "GSA1.NetSendOverride: %s", tostring(nerr)) end
    elseif GSA1.cv.follow:GetBool() and now >= C.nextNet and server_has_gsa1() then
        C.nextNet = now + 1 / 20
        net.Start(GSA1.NET_STATE, true)
        local ns = net_state
        ns.x, ns.y, ns.z, ns.yaw, ns.kind, ns.action, ns.frame, ns.ground = st.x, st.y, st.z, st.yaw, C.kind, st.action,
            st.frame, st.ground
        GSA1.Net.WriteState(ns)
        net.SendToServer()
    end
    if now >= C.nextActive then
        C.nextActive = now + 2
        send_active(true, nil, C.kind)     -- idempotent; survives a player respawn on the server
    end
end

hook.Add("Think", "gsa1_tick", GSA1.Guard("Think", function()
    local now = SysTime()
    if GSA1.HitchFrame then GSA1.HitchFrame(now) end
    if GSA1.InitThink then GSA1.InitThink() end
    if GSA1.AudioThink then GSA1.AudioThink() end
    if GSA1.WorldThink then GSA1.WorldThink() end
    if GSA1.mod and now >= next_log then
        next_log = now + 0.5
        GSA1.DrainLog()
    end
    if recreate_at and now >= recreate_at then
        recreate_at = nil
        GSA1.Recreate("upgrades changed")
    end
    -- the controller first: its input goes into this frame's tick
    if GSA1.mod and GSA1.PadUpdate then
        local tp = SysTime()
        GSA1.PadUpdate(game_paused())
        prof("PadUpdate", tp)
    end
    tick_character(now)
    -- after the tick: this frame's sound events are mixed right away
    if GSA1.mod then
        local ta = SysTime()
        update_audio()
        prof("AudioUpdate", ta)
    end
end))

-- camera -------------------------------------------------------------------------------------------------------------
-- the traces' tables and the points are reused (util.TraceHull writes into `output`); the view table is new per frame
-- (Garry's Mod hands it to other hooks), GSA1.view is reused
local hull_min, hull_max = Vector(-5, -5, -5), Vector(5, 5, 5)
local cam_centre, cam_top, cam_back = Vector(), Vector(), Vector()
local up_res, back_res = {}, {}
local up_trace = { start = cam_centre, endpos = cam_top, mins = hull_min, maxs = hull_max, mask = MASK_SOLID_BRUSHONLY,
                   output = up_res }
local back_trace = { start = nil, endpos = cam_back, mins = hull_min, maxs = hull_max, mask = MASK_SOLID_BRUSHONLY,
                     output = back_res }
GSA1.view = GSA1.view or {}
hook.Add("CalcView", "gsa1_view", GSA1.Guard("CalcView", function(ply, origin, angles, fov, znear, zfar)
    local C = GSA1.Char
    if not C or not C.drawPos then return end
    -- looking through a camera (the Camera tool's gmod_cameraprop, or any other view entity): its view wins
    local ve = ply:GetViewEntity()
    if IsValid(ve) and ve ~= ply then return end
    local dist = GSA1.cv.cam_dist:GetFloat()
    local view
    if dist <= 0 then
        cam_centre:Set(C.drawPos)
        cam_centre.z = cam_centre.z + (C.info.eyes or 28)
        view = { origin = Vector(cam_centre), angles = angles, fov = fov, drawviewer = false }
    else
        cam_centre:Set(C.drawPos)
        cam_centre.z = cam_centre.z + (C.info.center or 20)
        cam_top:Set(cam_centre)
        cam_top.z = cam_top.z + GSA1.cv.cam_height:GetFloat()
        util.TraceHull(up_trace)
        local hit = up_res.HitPos or cam_top
        back_trace.start = hit
        if GSA1.AngleAxes then GSA1.AngleAxes(angles, cam_back) else cam_back:Set(angles:Forward()) end
        cam_back:Mul(-dist)
        cam_back:Add(hit)
        util.TraceHull(back_trace)
        view = { origin = Vector(back_res.HitPos or cam_back), angles = angles, fov = fov, drawviewer = false }
    end
    -- seam (0.9.2): a feature's view instead (the fishing camera, 0.9.6)
    if GSA1.ViewOverride then
        local ov = GSA1.ViewOverride(view, C, ply)
        if type(ov) == "table" and ov.origin and ov.angles then view = ov end
    end
    local v = GSA1.view
    v.origin, v.angles, v.fov, v.frame = view.origin, view.angles, view.fov or fov, FrameNumber()
    return view
end))

hook.Add("ShouldDrawLocalPlayer", "gsa1", function(ply)
    if GSA1.Char then return false end
end)

hook.Add("PreDrawViewModel", "gsa1", function()
    if GSA1.Char then return true end
end)

local hidden_hud = { CHudCrosshair = true, CHudWeaponSelection = true, CHudAmmo = true, CHudSecondaryAmmo = true }
hook.Add("HUDShouldDraw", "gsa1", function(name)
    if GSA1.Char and hidden_hud[name] then return false end
end)

-- mouse wheel: camera distance while a character is active; the weapon keys (number keys, last weapon) do nothing then
-- (the hidden weapon selection already blocks them; the server's gate, sh_net.lua, refuses any switch that gets through)
local WEAPON_BINDS = { lastinv = true }
for i = 0, 10 do WEAPON_BINDS["slot" .. i] = true end
hook.Add("PlayerBindPress", "gsa1", function(ply, bind, pressed, code)
    -- seam (0.9.4a): a feature answers first (the open emote wheel: the mouse wheel turns its pages)
    if GSA1.BindOverride then
        local r = GSA1.BindOverride(ply, string.lower(tostring(bind or "")), pressed, code)
        if r ~= nil then return r end
    end
    if not GSA1.Char then return end
    local b = string.lower(bind)
    if b == "invprev" or b == "invnext" then
        if pressed then
            local d = GSA1.cv.cam_dist:GetFloat() + (b == "invnext" and 20 or -20)
            GSA1.cv.cam_dist:SetFloat(math.Clamp(d, 0, 1000))
        end
        return true
    end
    if WEAPON_BINDS[b] then return true end
end)

-- the Physics Gun's beam and glow of a character draw nothing (return false: no default effects, the glow sprites
-- included - GM:DrawPhysgunBeam): the local character at once, before the server's switch to the empty hands arrives;
-- other players' characters by their networked flag (multiplayer)
hook.Add("DrawPhysgunBeam", "gsa1", function(ply)
    if (GSA1.Char and ply == LocalPlayer()) or GSA1.IsCharacter(ply) then return false end
end)

-- debug overlay
hook.Add("HUDPaint", "gsa1_debug", function()
    local C = GSA1.Char
    if not C or not GSA1.cv.debug:GetBool() then return end
    local s = C.state
    local lines = {
        string.format("G-SA1 %s  id %d", C.title, C.id),
        string.format("pos %.1f %.1f %.1f   vel %.0f %.0f %.0f", s.x or 0, s.y or 0, s.z or 0, s.vx or 0, s.vy or 0, s.vz or 0),
        string.format("mode %d/%d  action %d  frame %.1f  %s  surface %X", s.mode or 0, s.smode or 0, s.action or 0,
            s.frame or 0, s.ground and "ground" or "air", s.surface or 0),
        string.format("step %d  alpha %.2f (%s)  tick %.3f ms  render %.3f + %.3f ms", s.step or 0, C.alpha or 0,
            C.interpolated and "interpolated" or (C.shifted and "moved with the root by libsa1" or "raw"),
            s.tick_ms or 0, s.render_ms or 0, s.view_ms or 0),
        string.format("upgrades: %s  (equipment 0x%04X%s)", GSA1.UpgradeText(C.upgrades), s.equipment or 0,
            s.upgrades_ok == false and ", NOT what the upgrades ask for" or ""),
        string.format("%d triangles in %d batches, drawn in %.2f ms  textures pending %d  sounds playing %d",
            C.triangles or 0, C.batches.count or 0, C.drawMs or 0, GSA1.Tex.Pending(),
            gsa1.AudioStatus and gsa1.AudioStatus().active or 0),
        string.format("stick %.2f %.2f  buttons %d", input_state.sx, input_state.sy, input_state.buttons),
        string.format("effects cover %.2f screens (sprites %.2f); widest sprite %.0f units; %s", s.blend_layers or 0,
            s.sprite_layers or 0, s.sprite_max or 0, GSA1.WarmLine and GSA1.WarmLine() or ""),
    }
    if s.water_attr ~= nil then
        -- 0.9.2 (WTR-A / WTR-LOG): the game's water state and the host flags the last tick passed
        lines[#lines + 1] = string.format("water: %s (attr 0x%X, surface %.0f); host flags %d%s",
            s.in_water and "in the game's water" or "dry", s.water_attr or 0, s.water_level or 0, C.hostFlags or 0,
            (GSA1.cv.hostwater and not GSA1.cv.hostwater:GetBool()) and " (off: the game's own rule)" or "")
    end
    if GSA1.MoverLine then lines[#lines + 1] = GSA1.MoverLine() end
    if GSA1.HitchLine then lines[#lines + 1] = GSA1.HitchLine() end
    local p = GSA1.pad
    if p and p.connected then
        lines[#lines + 1] = string.format("controller %d %s  stick %.2f %.2f  buttons %d  camera %.2f %.2f  rumble %.2f",
            p.index, input_state.pad and "in use" or "idle", p.sx, p.sy, p.buttons, p.cx, p.cy, p.rumble or 0)
    end
    for i, l in ipairs(lines) do
        draw.SimpleText(l, "DermaDefault", 16, 16 + (i - 1) * 14, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
end)

-- render settings changed: new materials, new static meshes (lighting and both sides change the materials: their
-- batch keys are forgotten and the new ones pre-warmed)
for _, name in ipairs({ "gsa1_lighting", "gsa1_vertexcolor", "gsa1_flip_winding", "gsa1_nocull", "gsa1_interpolate",
                        "gsa1_line_width" }) do
    cvars.AddChangeCallback(name, function()
        local C = GSA1.Char
        if name == "gsa1_lighting" or name == "gsa1_nocull" then GSA1.Tex.ForgetKeys() end
        if C then
            C.matsDirty = true
            GSA1.FreeStaticMeshes(C)
            if (name == "gsa1_lighting" or name == "gsa1_nocull") and GSA1.Warm then GSA1.Warm.Start(C) end
        end
    end, "gsa1_rebuild")
end
cvars.AddChangeCallback("gsa1_prewarm", function()
    if GSA1.Char and GSA1.Warm then GSA1.Warm.Start(GSA1.Char) end
end, "gsa1_rebuild")

-- commands -----------------------------------------------------------------------------------------------------------
local function complete_names(cmd, args)
    local out = {}
    local typed = string.lower(string.Trim(args or ""))
    for _, c in ipairs(GSA1.CHARACTERS) do
        if typed == "" or string.StartWith(c.name, typed) then out[#out + 1] = cmd .. " " .. c.name end
    end
    return out
end

concommand.Add("gsa1_spawn", function(ply, cmd, args)
    GSA1.Spawn(args[1])
end, complete_names, "G-SA1: become a character (sonic, tails, knuckles, amy, gamma, big, supersonic, supersonic_general) where you stand")

concommand.Add("gsa1_remove", function()
    GSA1.Remove(false)
end, nil, "G-SA1: stop being a character")

concommand.Add("gsa1_toggle", function(ply, cmd, args)
    if GSA1.Char then GSA1.Remove(false) else GSA1.Spawn(args[1]) end
end, complete_names, "G-SA1: spawn or remove (bind a key to it)")

concommand.Add("gsa1_respawn", function()
    GSA1.Respawn("command")
end, nil, "G-SA1: put the character back at its spawn point")

concommand.Add("gsa1_give_rings", function(ply, cmd, args)
    GSA1.GiveRings(args[1])
end, nil, "G-SA1: gsa1_give_rings <n>: give your character n rings through the game's own ring counter (100 gives a 1-up; "
    .. "in multiplayer for admins and the server's host)")

concommand.Add("gsa1_upgrades_apply", function()
    if not GSA1.Char then GSA1.Msg("no character") return end
    GSA1.Recreate("gsa1_upgrades_apply")
end, nil, "G-SA1: re-create the character where it stands with the ticked upgrades")

-- gsa1_upgrades_all 1|0 [character]: tick / untick every upgrade (of one character)
concommand.Add("gsa1_upgrades_all", function(ply, cmd, args)
    local on = args[1] ~= "0"
    local kind = nil
    if args[2] then
        kind = GSA1.KindByName(args[2])
        if not kind then
            GSA1.Msg("unknown character '%s' (sonic, tails, knuckles, amy, gamma, big, supersonic, supersonic_general)", tostring(args[2]))
            return
        end
    end
    for _, u in ipairs(GSA1.UPGRADES) do
        if kind == nil or u.kind == GSA1.UpgradeKind(kind) then
            RunConsoleCommand("gsa1_upgrade_" .. u.name, on and "1" or "0")
        end
    end
end, nil, "G-SA1: gsa1_upgrades_all 1|0 [character]: give or take every upgrade (of one character)")
