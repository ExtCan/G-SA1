-- G-SA1 character options (round 0.9.1; the module's feature "charopt", src/module/bind_charopt.cpp, libsa1 API 0.3):
-- the Character page's game settings (Q -> Options -> G-SA1 -> Character, after the upgrades; GSA1.AddCharacterOption)
-- and what they do to each character this client creates (the hooks of cl_character.lua: GSA1CharacterCreated runs
-- before the character's first tick, GSA1CharacterLeaving while its world is still there, GSA1PreTick before every
-- tick):
--   * Amy's bird (Birdie), gsa1_amy_bird 1 (sadc docs/research/gsa1_070_bird.md F4 with its review R.4): the game's own
--     Birdie task (8C0DECDA / 8C0DE964, libsa1's companion API: made and freed with the game's calls) follows Amy, as in
--     her story. Amy only; applied at once (no re-creation); local only - other players' Amys are posed copies without a
--     game and show no bird yet; hidden in first person with Amy's body. Never applied to a follower (round 6b decides).
--   * Tails' tail blend, gsa1_tails_tail_blend 1 (sadc docs/research/gsa1_rounds_plan.md 14.1h, the owner's answer "add a
--     switch, default like the game"): on = the game's morph of his bent tails into the propeller (and back) over 100
--     pairs, whose in-between tails look flat; off = libsa1's SA1_GOPT_TAILS_SNAP_TAILS: the display uses the blend
--     weight snapped to 0 / 1, so the tails switch at once (50 pairs into a run). A deviation available on request.
--   * Characters can drown, gsa1_drown 1 (gsa1_070_drown.md owner question 3, default on = the game's air timer: 18 s
--     under water, the countdown jingle and the numbers, the drown at 31 s). Off holds the game's air timer at 0 before
--     every tick (gsa1.HoldAir): no countdown starts, a running one ends at once by the game's own rule (as when the
--     character gets air); the water still slows the character. A host option, never used by the reference worlds.
--   * Lives, gsa1_lives 0 (gsa1_070_drown.md G1, the owner default: count down, game over gives 4 again; 1 = infinite):
--     the game's life counter goes from character to character - a respawn after the game's own death takes one (the
--     game takes one when it restarts the act: 8C08A120(-1)), a death with none left is game over and the new character
--     starts with the game's 4 again; a respawn without a death (fell out of the world, the Respawn button), a switch and
--     a re-creation keep the count; a first spawn starts with the game's 4. The 1-ups (100 rings) are the game's.
-- Session log lines "game" (the game over, the settings when they change).
GSA1 = GSA1 or {}

local O = {}
GSA1.CharOpt = O
O.NEEDS = { feature = "charopt", version = 1, module = "0.9.1" }
O.KIND_TAILS, O.KIND_AMY = 2, 5
O.COMPANION_BIRD, O.TAILS_SNAP_TAILS = 1, 1          -- gsa1.CHAROPT's numbers (the module's table wins when present)
O.LIVES_START = 4                                     -- the game's (8C08A04A); a game over gives it again
O.LIVES_MAX = 127
O.MODE_COUNT, O.MODE_INFINITE = 0, 1

local cv = {
    bird       = GSA1.ConVar("gsa1_amy_bird", 1, "Amy's bird (Birdie) follows Amy, as in her story: the game's own bird "
        .. "(1 = on; Amy only, applies at once)", 0, 1),
    tail_blend = GSA1.ConVar("gsa1_tails_tail_blend", 1, "Tails' tail blend: 1 = the game's morph between his bent tails "
        .. "and the propeller as he speeds up and slows down (the in-between tails look flat, as on the Dreamcast); 0 = "
        .. "they switch at once", 0, 1),
    drown      = GSA1.ConVar("gsa1_drown", 1, "Characters can drown: 1 = the game's air timer (18 s under water start "
        .. "the countdown, then the character drowns); 0 = the air timer is held at 0 (no countdown, no drowning)", 0, 1),
    lives      = GSA1.ConVar("gsa1_lives", 0, "Lives: 0 = count down like the game (a death takes one; a death with none "
        .. "left is game over and gives 4 again), 1 = infinite (deaths take none)", 0, 1),
}
O.cv = cv

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("game", fmt, ...) end
end

-- the loaded module has the character options (cheap: for the hooks)
local function have()
    return GSA1.mod ~= nil and gsa1 ~= nil and gsa1.SetCompanion ~= nil and gsa1.SetLives ~= nil
end
O.Have = have

local function num(k, default)
    local t = gsa1 and gsa1.CHAROPT
    return type(t) == "table" and tonumber(t[k]) or default
end

-- an error once per character and setting (the log; the console with gsa1_debug)
local function failed(C, what, err)
    C.charoptErrors = C.charoptErrors or {}
    if C.charoptErrors[what] then return end
    C.charoptErrors[what] = true
    log("%s: %s failed: %s", C.title or "?", what, tostring(err))
end

-- the lives after a respawn: (lives before, died, mode) -> lives, game over
function O.NextLives(lives, died, mode)
    lives = math.Clamp(math.floor(tonumber(lives) or O.LIVES_START), 0, O.LIVES_MAX)
    if not died or mode == O.MODE_INFINITE then return lives, false end
    if lives <= 0 then return O.LIVES_START, true end   -- the game: no life left at the death -> game over
    return lives - 1, false                             -- the game takes one at the act's restart
end

-- Amy's bird for character C (on: the ConVar's value); true when applied
function O.ApplyBird(C, on)
    if not C or C.kind ~= O.KIND_AMY or not have() then return false end
    if on == nil then on = cv.bird:GetBool() end
    local ok, err = gsa1.SetCompanion(C.id, num("COMPANION_BIRD", O.COMPANION_BIRD), on and true or false)
    if not ok then
        failed(C, "Amy's bird", err)
        return false
    end
    C.bird = on and true or false
    return true
end

-- Tails' tail blend for character C
function O.ApplyTailBlend(C, blend)
    if not C or C.kind ~= O.KIND_TAILS or not have() then return false end
    if blend == nil then blend = cv.tail_blend:GetBool() end
    local ok, err = gsa1.SetGameOption(C.id, num("TAILS_SNAP_TAILS", O.TAILS_SNAP_TAILS), blend and 0 or 1)
    if not ok then
        failed(C, "Tails' tail blend", err)
        return false
    end
    C.tailSnap = not blend
    return true
end

-- a character goes: its life counter while its world is still there
hook.Add("GSA1CharacterLeaving", "gsa1_charopt", function(C, how)
    if not C or not C.id or not have() then return end
    C.livesLeft = tonumber(gsa1.GetLives(C.id))
end)

-- a new character, before its first tick: its lives, Amy's bird, Tails' tail blend
hook.Add("GSA1CharacterCreated", "gsa1_charopt", function(C, how, old)
    if not C or not have() then return end
    O.ApplyBird(C)
    O.ApplyTailBlend(C)
    if old and old.livesLeft ~= nil then
        local died = how == "respawned" and old.death ~= nil
        local n, over = O.NextLives(old.livesLeft, died, cv.lives:GetInt())
        local v, err = gsa1.SetLives(C.id, n)
        if v == nil then
            failed(C, "the lives", err)
        else
            C.lives = tonumber(v)
            if over then
                C.gameOver = true
                GSA1.Chat("Game over: %s starts again with %d lives", C.title or "?", C.lives)
                log("game over: %s had no life left at the death; it starts again with %d", C.title or "?", C.lives)
            end
        end
    else
        C.lives = tonumber(gsa1.GetLives(C.id))
    end
end)

-- before every tick: "Characters can drown" off holds the game's air timer at 0
hook.Add("GSA1PreTick", "gsa1_charopt", function(C)
    if not C or cv.drown:GetBool() or not have() or not gsa1.HoldAir then return end
    local b, err = gsa1.HoldAir(C.id)
    if b == nil then failed(C, "holding the air timer", err) end
end)

-- the settings act at once on the current character
cvars.AddChangeCallback("gsa1_amy_bird", function(_, _, new)
    local C = GSA1.Char
    log("Amy's bird %s", tonumber(new) ~= 0 and "on" or "off")
    if C and C.kind == O.KIND_AMY then O.ApplyBird(C, tonumber(new) ~= 0) end
end, "gsa1_charopt")
cvars.AddChangeCallback("gsa1_tails_tail_blend", function(_, _, new)
    local C = GSA1.Char
    log("Tails' tail blend %s", tonumber(new) ~= 0 and "on (the game's morph)" or "off (instant switch)")
    if C and C.kind == O.KIND_TAILS then O.ApplyTailBlend(C, tonumber(new) ~= 0) end
end, "gsa1_charopt")
cvars.AddChangeCallback("gsa1_drown", function(_, _, new)
    log("characters can drown: %s", tonumber(new) ~= 0 and "on (the game's air timer)" or "off (air timer held at 0)")
end, "gsa1_charopt")
cvars.AddChangeCallback("gsa1_lives", function(_, _, new)
    log("lives: %s", tonumber(new) == O.MODE_INFINITE and "infinite" or "count down (game over gives 4 again)")
end, "gsa1_charopt")

-- the Character page --------------------------------------------------------------------------------------------------
-- a combo box for a ConVar whose values have titles: it follows the ConVar (also a change from the console)
local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[1], c[2]) end
    combo.OnSelect = function(_, _, _, data)
        RunConsoleCommand(cvname, tostring(data))
    end
    local baseThink = combo.Think
    combo.Think = function(self)
        if baseThink then baseThink(self) end
        local c = GetConVar(cvname)
        local v = c and c:GetString() or ""
        if v == self.gsa1Value then return end
        self.gsa1Value = v
        local n = tonumber(v)
        for _, ch in ipairs(choices) do
            if ch[2] == v or (n ~= nil and tonumber(ch[2]) == n) then
                self:SetText(ch[1])
                return
            end
        end
        self:SetText(v)
    end
    return combo
end

function O.Options(panel)
    panel:Help("Game rules and companions")
    panel:CheckBox("Amy's bird (Birdie)", "gsa1_amy_bird")
    panel:ControlHelp("The little bird that follows Amy in her story - the game's own bird: it hovers above her, flaps "
        .. "faster when she moves and has its own shadow. Amy only; applies at once. Only you see it for now (other "
        .. "players' Amys have no bird), and not in first person.")
    panel:CheckBox("Tails' tail blend", "gsa1_tails_tail_blend")
    panel:ControlHelp("On (the game): when Tails speeds up into a run his two bent tails morph into the spinning "
        .. "propeller over about three seconds, and back when he slows down; the tails in between look flat, as on the "
        .. "Dreamcast. Off: they switch at once, halfway through. Applies at once.")
    panel:CheckBox("Characters can drown", "gsa1_drown")
    panel:ControlHelp("On (the game): after 18 seconds under water the countdown music starts and the numbers 5 to 1 "
        .. "appear; then the character drowns and comes back at its spawn point. Off: the air timer stays at 0 under "
        .. "water - no countdown, no drowning; the water still slows the character down.")
    choice_combo(panel, "Lives", "gsa1_lives", {
        { "Count down (game over gives 4 again)", tostring(O.MODE_COUNT) },
        { "Infinite", tostring(O.MODE_INFINITE) },
    })
    panel:ControlHelp("A character starts with the game's 4 lives and gets one for every 100 rings. Count down (the "
        .. "game): every death takes one; a death with none left is game over, and the character starts again with 4. "
        .. "Infinite: deaths take none. Falling out of the map, the Respawn button, switching characters and the "
        .. "upgrades keep the count.")
end

if GSA1.AddCharacterOption then
    GSA1.AddCharacterOption(100, "charopt", O.Options, O.NEEDS)
end
