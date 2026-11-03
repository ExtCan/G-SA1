-- G-SA1 "?": the pure part (round 0.9.9; sadc docs/research/gsa1_099_plan.md 4.1 B10, 5.5, 5.6, 5.9; playable099.md 5). The Question Mark
-- of the game's character select, as a joke character: libsa1's SA1_CREATE_QUESTION on a kind-8 world. The world, its state, its events
-- and its sounds are byte for byte Super Sonic's (Vs. Perfect Chaos), only the output differs: a spinning "?", no golden Sonic, no aura.
-- It is its own list entry (sh_config.lua: "question", form "question") with its own options (feat/cl_question.lua) and shares nothing
-- with either Super Sonic: not his upgrades, his options, his key, his music or his log lines. No engine call and no state here: both
-- realms load it (the server has no module) and the tests run it as it is.
GSA1 = GSA1 or {}
local Q = GSA1.Question or {}
GSA1.Question = Q

-- libsa1.h's numbers; the module's gsa1.SUPER wins when it is there (Q.Const). A module without CREATE_QUESTION refuses the flag by name
-- ("only SUPER_CAPABLE and WATER_FLOOR"), so the entry can never come up as a plain Super Sonic
Q.K = { CREATE_QUESTION = 0x2000, ARCHIVE_QUESTION = 62, COPT_QUESTION_SPIN = 8, CREATE_WATER_FLOOR = 0x1000, NO_DRAIN = 0x1,
        KEEP_AT_ZERO = 0x2, START_RINGS = 50 }
function Q.Const(name)
    local t = gsa1 ~= nil and type(gsa1) == "table" and gsa1.SUPER or nil
    return (type(t) == "table" and tonumber(t[name])) or Q.K[name]
end

-- the list entry of the "?"
function Q.IsDef(def)
    return type(def) == "table" and def.form == "question"
end

-- the create extras (cl_character.lua's seam GSA1.CreateExtras). how: cl_character.lua's ("spawned", "switched to", "respawned",
-- "re-created": a re-creation gets its rings through GSA1.KeepRings); o: { rings, drain, water } (Q.Options, its own ConVars only).
-- KEEP_AT_ZERO always: "turns back" has no meaning for a "?": with the drain on it stays what it is at 0
function Q.ExtrasFor(how, o)
    local flags = Q.Const("CREATE_QUESTION")
    if o.water then flags = bit.bor(flags, Q.Const("CREATE_WATER_FLOOR")) end
    local sf = Q.Const("KEEP_AT_ZERO")
    if not o.drain then sf = bit.bor(sf, Q.Const("NO_DRAIN")) end
    local rings = math.min(math.max(math.floor(tonumber(o.rings) or Q.K.START_RINGS), 0), 99)
    return { create_flags = flags, super_flags = sf, start_rings = how == "re-created" and 0 or rings }
end
