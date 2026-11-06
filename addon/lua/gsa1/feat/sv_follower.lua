-- G-SA1 feature "follower", server (round 0.9.8; sadc docs/research/gsa1_096_plan.md 5.7 with review R.6, follow096_gsa1.md 4.5):
-- followers are worlds on the client; the server only carries the spawn icons' request and the Undo entry. A spawner's
-- SpawnFunction (entities/gsa1_follower_spawner.lua) makes no entity and calls GSA1.FollowerRequest: the spawning client gets
-- gsa1_fol_req (a token, the kind); it answers gsa1_fol_made (the token, made); made -> an Undo entry whose function sends
-- gsa1_fol_undo, and the client removes that follower. A token lives Fo.TOKEN_LIFE s and is used once (review R.6: one token
-- can never make two Undo entries). Hook for other addons: GSA1FollowerRequest(ply, kind, skin) (false: nothing happens).
-- 0.9.9h: a skin's spawner (Metal Sonic) sends its entry's name after the kind (an empty string: none)
GSA1 = GSA1 or {}
local Fo = GSA1.Followers
if not Fo then return end
local cv = Fo.cv
local NET = Fo.NET

for _, name in pairs(NET) do util.AddNetworkString(name) end

local function now() return CurTime() end

-- a player's tokens: ply.GSA1FolTokens[token] = { kind, at }, the rate's bucket
local function rate_ok(ply)
    local tn = now()
    local b = ply.GSA1FolRate or { tokens = Fo.REQ_RATE, t = tn }
    ply.GSA1FolRate = b
    b.tokens = math.min(Fo.REQ_RATE, b.tokens + (tn - b.t) * Fo.REQ_RATE)
    b.t = tn
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

-- a spawner was used; true when the client was asked. skin: a skin entry's name (Fo.SkinDef) or nil
function GSA1.FollowerRequest(ply, kind, skin)
    if not IsValid(ply) or not Fo.KINDS[kind] then return false end
    local sd = nil
    if skin ~= nil and skin ~= "" then
        sd = Fo.SkinDef and Fo.SkinDef(skin)
        if not sd or sd.kind ~= kind then return false end
    end
    if cv.sv_icons and not cv.sv_icons:GetBool() then return false end
    if hook and hook.Run and hook.Run("GSA1FollowerRequest", ply, kind, sd and sd.name or nil) == false then return false end
    if not rate_ok(ply) then return false end
    local tokens = ply.GSA1FolTokens or {}
    ply.GSA1FolTokens = tokens
    -- (the old ones go here: a client that never answers)
    local tn = now()
    for t, rec in pairs(tokens) do
        if tn - rec.at > Fo.TOKEN_LIFE then tokens[t] = nil end
    end
    local token = (tonumber(ply.GSA1FolNext) or 0) % 65535 + 1
    ply.GSA1FolNext = token
    tokens[token] = { kind = kind, skin = sd and sd.name or nil, at = tn }
    net.Start(NET.REQ)
    net.WriteUInt(token, 16)
    net.WriteUInt(kind, 4)
    net.WriteString(sd and sd.name or "")
    net.Send(ply)
    return true
end

-- the client's answer: made -> the Undo entry; a token not sent to that player in the last 10 s, or used before: nothing
function Fo.Made(ply, token, made)
    local tokens = ply.GSA1FolTokens
    local rec = tokens and tokens[token]
    if not rec then return false, "no such token" end
    tokens[token] = nil
    if now() - rec.at > Fo.TOKEN_LIFE then return false, "the token is too old" end
    if not made then return false, "not made" end
    if not (undo and undo.Create) then return true end
    local title = "G-SA1 " .. (Fo.FollowerTitle and Fo.FollowerTitle(rec.kind, rec.skin) or Fo.KindTitle(rec.kind)) .. " follower"
    undo.Create(title)
    undo.AddFunction(function()
        net.Start(NET.UNDO)
        net.WriteUInt(token, 16)
        net.Send(ply)
    end)
    undo.SetPlayer(ply)
    if undo.SetCustomUndoText then undo.SetCustomUndoText("Undone " .. title) end
    undo.Finish()
    return true
end

net.Receive(NET.MADE, function(len, ply)
    if not IsValid(ply) then return end
    local token, made = net.ReadUInt(16), net.ReadBool()
    Fo.Made(ply, token, made)
end)
