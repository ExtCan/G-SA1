-- G-SA1 "?": the client part (round 0.9.9; sadc docs/research/gsa1_099_plan.md 4.1 B10, 5.6, 5.9; playable099.md 5.5-5.7; the pure part is
-- feat/sh_question.lua). Its own options, on the Character page (feat/cl_playable.lua's builder calls Q.BuildOptions):
--   gsa1_question_rings, _drain, _water go into the world at its creation (GSA1.CreateExtras below): a change re-creates a "?" that
--   exists, where it stands; gsa1_question_spin goes through gsa1.SetCharOption at once.
-- This file loads before feat/cl_super.lua, whose GSA1.CreateExtras wrapper is outermost: its S.Extras returns nil for this entry, so the
-- chain falls through to the wrapper here. Everything Super Sonic's file does is guarded by C.question (cl_character.lua sets it from
-- the list entry): overlap rows 1, 2, 8-11, 18, 20 of playable099.md 5.7 and review R99.4.
GSA1 = GSA1 or {}
local Q = GSA1.Question
if not Q then error("gsa1/feat/sh_question.lua did not load: the ? needs it") end

Q.RECREATE_DELAY = 0.25         -- s after a change of a box: one re-creation for several changes, as Super Sonic's option_changed
Q.DRAG_DELAY = 1                -- s after the last tick of the rings slider: one re-creation and one log line for a whole drag

-- 0.9.9e: its ConVars are made by Q.Activate, when it is unlocked: before that `find` and `cvarlist` show nothing of it
local cv = {}
Q.cv = cv

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("question", fmt, ...) end
end

-- the ?'s own options, and nothing of Super Sonic's
function Q.Options()
    Q.Activate()
    return { rings = cv.rings:GetInt(), drain = cv.drain:GetBool(), water = cv.water:GetBool() }
end

-- the seam (kept across a reload of this file, as S.prevFilter and W.prevBind are)
Q.prevExtras = Q.prevExtras or GSA1.CreateExtras
GSA1.CreateExtras = function(kind, how, rings, def, old)
    if Q.IsDef(def) then return Q.ExtrasFor(how, Q.Options()) end
    if Q.prevExtras then return Q.prevExtras(kind, how, rings, def, old) end
    return nil
end

-- the spin, at once and before a new character's first tick
function Q.ApplySpin(C)
    if not (C and C.question and C.id and gsa1 and gsa1.SetCharOption and cv.spin) then return false end
    local ok, err, code = gsa1.SetCharOption(C.id, Q.Const("COPT_QUESTION_SPIN"), cv.spin:GetBool() and 1 or 0)
    if not ok then log("the spin: refused: %s (%s)", tostring(err), tostring(code)) end
    return ok == true
end
hook.Add("GSA1CharacterCreated", "gsa1_question", function(C, how)
    if not (C and C.question) then return end
    Q.ApplySpin(C)
    local ex = C.extras
    log("%s %s: its own options (create flags 0x%X, super flags 0x%X, start rings %s), spin %s", C.title or "?", how or "created",
        ex and tonumber(ex.create_flags) or 0, ex and tonumber(ex.super_flags) or 0, ex and tostring(ex.start_rings) or "?",
        cv.spin:GetBool() and "on" or "off")
end)
-- rings, drain, water change the world: re-created where it stands a moment later. The rings slider's re-creation gives the slider's
-- rings (C.ringsOnRecreate, cl_character.lua GSA1.Recreate); any other keeps what it has, as for anyone
Q.recreateAt, Q.recreateWhy, Q.ringsChanged = nil, nil, nil
local function ask_recreate(delay, why)
    local C = GSA1.Char
    if not (C and C.question) then return end
    Q.recreateAt = SysTime() + delay
    Q.recreateWhy = why
end
-- 0.9.9e: from the unlocking on (at load when it is unlocked already)
function Q.Activate()
    if cv.rings then return end
    cv.rings = GSA1.ConVar("gsa1_question_rings", 50, "The ?: the rings it starts with (its own, not Super Sonic's; at most 99)", 0, 99)
    cv.drain = GSA1.ConVar("gsa1_question_drain", 0, "The ?: lose a ring every second (Perfect Chaos' rule); it stays what it is at 0", 0, 1)
    cv.water = GSA1.ConVar("gsa1_question_water", 1, "The ?: runs on Garry's Mod's water", 0, 1)
    cv.spin = GSA1.ConVar("gsa1_question_spin", 1, "The ?: 1 = spins as on the character menu, 0 = faces the way it runs", 0, 1)
    cvars.AddChangeCallback("gsa1_question_spin", function(_, _, new)
        local applied = Q.ApplySpin(GSA1.Char)
        log("gsa1_question_spin = %s%s", tostring(new), applied and " (applied at once)" or "")
    end, "gsa1_question")
    for _, name in ipairs({ "gsa1_question_drain", "gsa1_question_water" }) do
        cvars.AddChangeCallback(name, function(_, _, new)
            log("%s = %s", name, tostring(new))
            ask_recreate(Q.RECREATE_DELAY, "its options changed (" .. name .. ")")
        end, "gsa1_question")
    end
    cvars.AddChangeCallback("gsa1_question_rings", function(_, _, new)
        -- one line about a second after the last tick (small099.md 3.3)
        timer.Create("gsa1_question_log_rings", 1, 1, function() log("gsa1_question_rings = %s", tostring(new)) end)
        local C = GSA1.Char
        if C and C.question then Q.ringsChanged = true end
        ask_recreate(Q.DRAG_DELAY, "its options changed (gsa1_question_rings)")
    end, "gsa1_question")
end
function Q.RecreateThink(now)
    if not (Q.recreateAt and now >= Q.recreateAt) then return end
    Q.recreateAt = nil
    local C = GSA1.Char
    if C and C.question and GSA1.Recreate then
        if Q.ringsChanged then C.ringsOnRecreate = cv.rings:GetInt() end
        GSA1.Recreate(Q.recreateWhy)
    end
    Q.ringsChanged = nil
end
local function think()
    if Q.recreateAt then Q.RecreateThink(SysTime()) end
end
hook.Add("Think", "gsa1_question", GSA1.Guard and GSA1.Guard("question", think) or think)

-- the Character page's rows (the owner's rule: every option on the Q menu)
function Q.BuildOptions(panel)
    panel:Help("?")
    panel:ControlHelp("The spinning Question Mark of the character menu as a character of its own, with Super Sonic's moves and sounds: run, jump, "
        .. "homing, no golden Sonic, no aura. It shares nothing else with him: Sonic's upgrades, the Super Sonic page's options and the G key do "
        .. "nothing here. It has no emotes, faces, head look or boards.")
    panel:NumSlider("The ?: start with N rings", "gsa1_question_rings", 0, 99, 0)
    panel:CheckBox("The ?: lose a ring every second (Perfect Chaos' rule). It stays what it is at 0", "gsa1_question_drain")
    panel:CheckBox("The ?: runs on water", "gsa1_question_water")
    panel:CheckBox("The ?: spins as on the character menu. Off: it faces the way it runs", "gsa1_question_spin")
    panel:ControlHelp("Rings, the drain and the water re-create a ? where it stands. Its look is \"The question mark's texture\" below. "
        .. "Its whoosh is Super Sonic's, under the Super Sonic page's switch.")
end

-- the secret (the owner, rounds plan 14.1bc). Client only: the character is the client's, the server only hears its kind. No help text and no completion: it is in no help, menu or README. Using it unlocks for
-- good (sh_config.lua: a cookie) and says so in the chat. A plain console command: it does show in `cvarlist` among thousands, and when its first letters are typed; FCVAR_HIDDEN could hide it, but whether Garry's Mod then still runs it
-- is UNVERIFIED and a secret that does not work is worse
Q.COMMAND = "iwonderwhotheseventhcharacteris"
function Q.Unlock()
    local was = GSA1.QuestionUnlocked()
    GSA1.questionUnlocked = true
    if cookie and cookie.Set then cookie.Set(GSA1.QUESTION_COOKIE, "1") end
    Q.Activate()
    if was then
        GSA1.Chat("The seventh character is already unlocked.")
        return false
    end
    log("the ? is unlocked")
    GSA1.Chat("You found the seventh character: ? is on the Character page now.")
    if hook and hook.Run then hook.Run("GSA1QuestionUnlocked") end
    return true
end
concommand.Add(Q.COMMAND, function() Q.Unlock() end)

-- a character saved as "?" before this version, or typed into gsa1_character while it is locked, goes back to Sonic, the ConVar's default. true when it changed it
function Q.CheckSaved()
    local c = GSA1.cv and GSA1.cv.character
    if not (c and GSA1.LockedName(c:GetString())) then return false end
    c:SetString("sonic")
    log("the character saved was the ?, which is locked: Sonic")
    return true
end
Q.CheckSaved()
if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("gsa1_character", function() Q.CheckSaved() end, "gsa1_question")
end
if GSA1.QuestionUnlocked() then Q.Activate() end
