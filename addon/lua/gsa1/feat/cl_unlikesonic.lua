-- G-SA1 client: a secret (2026-10-25, the owner's request; the "& Knuckles" meme). Saying "/unlikesonicIdontchuckle" in chat
-- (any case, also with "!"):
--   * you become Knuckles where you stand (GSA1.Spawn("knuckles")),
--   * Knuckles' theme "Unknown from M.E." plays on the jukebox (music 62, KNUCKLES.ADX, from your own disc),
--   * 99 Knuckles followers (100 Knuckles in all; the owner, ignoring the normal follower cap) - once followers exist (round 0.9.5: the feature then
--     provides GSA1.SpawnFollower(kind) returning true while it can make another one); before that, nothing more happens.
-- The chat line itself is not shown. Session log: a "msg" line.
GSA1 = GSA1 or {}

local U = {}
GSA1.UnlikeSonic = U
U.MUSIC = "62"                 -- KNUCKLES.ADX, "KNUCKLES: Unknown from M.E." (the game's sound test title)
U.MAX_FOLLOWERS = 99           -- the owner: 99 followers + you = 100 Knuckles (ignores the normal follower cap)

local function pattern_ok(text)
    if type(text) ~= "string" then return false end
    local t = string.lower(string.gsub(text, "%s+", ""))
    return t == "/unlikesonicidontchuckle" or t == "!unlikesonicidontchuckle"
end
U.Matches = pattern_ok

function U.Go()
    -- 1. Knuckles
    if GSA1.Spawn then GSA1.Spawn("knuckles") end
    -- 2. his theme
    RunConsoleCommand("gsa1_jukebox_play", U.MUSIC)
    -- 3. the followers (when the feature exists): one per frame, until it says no
    local made = 0
    if GSA1.SpawnFollower then
        timer.Create("gsa1_unlikesonic", 0.05, U.MAX_FOLLOWERS, function()
            local ok, more = pcall(GSA1.SpawnFollower, "knuckles", { ignore_cap = true })
            if ok and more == false then ok = false end
            if ok then made = made + 1 end
            if not ok or not GSA1.SpawnFollower then timer.Remove("gsa1_unlikesonic") end
        end)
    end
    if chat and chat.AddText then chat.AddText(Color(220, 40, 40), "& Knuckles") end
    if GSA1.Log then GSA1.Log("msg", "& Knuckles (the secret chat command)") end
end

hook.Add("OnPlayerChat", "gsa1_unlikesonic", function(ply, text)
    if ply ~= LocalPlayer() or not pattern_ok(text) then return end
    U.Go()
    return true
end)
