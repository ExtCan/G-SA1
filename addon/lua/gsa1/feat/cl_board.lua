-- G-SA1 feature "board", client (round 0.9.5; sadc docs/research/gsa1_095_plan.md 4, 5.4 - 5.8 and 6.4 task 4 with its
-- Review R.3 / R.5 / R.10 / R.11 / R.12; board095_gsa1.md 3, 4, 5, 6, 8; the owner's binding answers gsa1_rounds_plan.md
-- 14.1ad).
--
-- Per CHARACTER C (C.board = { on, entering, walk, leaving, refusal, st }: 0.9.6's followers reuse it with their own C):
--   * THE WHEEL: while the emote wheel is open, the board key (gsa1_board_key, B) or button (gsa1_board_pad, right stick
--     click) closes the wheel and puts Sonic / Tails on a board - libsa1 runs the stage code's own entry in his world
--     (gsa1.Board: order 44 and the board task) - or takes him off (order 24, Ice Cap's goal); the board stays where it
--     fell. Other characters: a toast "only Sonic and Tails ride a board", the wheel stays open. A Garry's Mod bind of the
--     key does nothing while the wheel is open. The controller's B button still only cancels the wheel. While a board
--     lies in his world the wheel's board rows (Sonic 102-124, Tails 107-127) are refused: the game's board task would
--     hold that board to him (review R.12).
--   * BOARD ON (the server's GO, feat/sv_board.lua): he walks to the board - the stick towards it in the tick's camera
--     frame (GSA1.FilterStick), 0.7 (the game's walk) while he is at most 0.5 units a step fast, else 1.0 (a run-in keeps
--     running; gsa1_board_walk 1: 1.0), never below 0.6; his buttons held back except jump, which stops the walk; when the
--     last pair's path passes within 24 HU (40 HU up / down) of the board he gets on with the box's push and ground, and
--     the server hears gsa1_board_took once he rides. The walk ends (gsa1_board_cancel with the reason) at a jump, the
--     deadline max(4, distance / 40 + 2) s, 64 HU outside the box, a hit, death, the character going, a refusal.
--   * BOARD OFF (the server's OFF): off, then gsa1_board_st with the box.
--   * THE HAND-OVER (gsa1_095_plan.md 4.8, review R.5): after every exit the kept board is watched until it settles (or 2 s,
--     or it fell / a new ON replaced it / the world goes: then its last resting pose, else the exit place traced down);
--     its pose goes to the server (gsa1_board_left), which makes the decoration gsa1_board_left; when that entity arrives
--     (at the latest 1 s later) the world frees its own board (gsa1.BoardFree). With gsa1_sv_board_left_max 0 every OFF
--     asks libsa1 to remove the board at the exit and nothing is sent.
--   * the hooks: re-created (upgrades, the map's collision, a fault, a teleport) while riding -> on a new board;
--     "respawned" after dying on a board -> a new board only with gsa1_board_respawn 1; "spawned" / "switched to" -> on
--     foot; the server's NW2 flag gsa1_board follows (gsa1_board_st); GSA1BoardChanged(C, on, why) on every edge.
--   * the view: the camera eases behind the board while riding (gsa1_board_camera; a CreateMove hook, time constant 0.4 s,
--     a pause of 1 s after a mouse or right-stick turn); the game's speed field of view (gsa1_board_fov, off) through the
--     chained GSA1.ViewOverride, eased at Ice Cap's 168.75 degrees a second.
--   * the drawing: the boxes' volumes only while editing (no character, or the context menu open; gsa1_board_box_show 1:
--     always); the board lying in every Board On box ALWAYS, the left boards at their pose - both the game's board model
--     from the disc (the BOARD preview) through feat/cl_objview.lua's extra-picture seam (V.Extra*: their own kind - the
--     local character's, else Sonic's - one copy per kind and variant); without the module or the disc a G-SA1-drawn
--     stand-in while editing.
--   * Q menu > Options > G-SA1 > Board (order 275): every client and server row of gsa1_095_plan.md 5.8.
GSA1 = GSA1 or {}
local B = GSA1.Board
if not B then return end
local W = GSA1.Wheel                     -- feat/sh_wheel.lua (the sh_ files load before every cl_ file)
local cv = B.cv
local band, bor = bit.band, bit.bor
local sqrt, cos, sin, rad, max, min, abs = math.sqrt, math.cos, math.sin, math.rad, math.max, math.min, math.abs
local WHAT, WHY, CANCEL = B.WHAT, B.WHY, B.CANCEL

local function log(fmt, ...)
    if GSA1.Log then GSA1.Log("board", fmt, ...) end
end
local function now_s() return SysTime() end

-- the module --------------------------------------------------------------------------------------------------------------
local have_cache, have_at = false, -1e9
function B.Have()
    local t = SysTime()
    if t - have_at > 2 then
        have_at = t
        have_cache = (GSA1.mod ~= nil and gsa1 ~= nil and gsa1.Board ~= nil and GSA1.HasFeature ~= nil and
            GSA1.HasFeature(B.NEEDS.feature, B.NEEDS.version)) and true or false
        if have_cache and not B.soundsSent then B.ApplySounds() end
    end
    return have_cache
end
function B.ResetHave() have_at = -1e9 end

local function bconst(name, d)
    local t = gsa1 and gsa1.BOARD
    local v = t and tonumber(t[name])
    if v == nil then return d end
    return v
end
function B.PreviewType()
    local p = gsa1 and gsa1.PREVIEW
    return p and tonumber(p.BOARD) or B.PREVIEW_BOARD
end

-- "Board sounds" (gsa1.BoardSounds: module-wide; stops always pass)
function B.ApplySounds()
    if not (GSA1.mod and gsa1 and gsa1.BoardSounds) then return false end
    local on = cv.sounds == nil or cv.sounds:GetBool()
    gsa1.BoardSounds(on and true or false)
    B.soundsSent = true
    return true
end
cvars.AddChangeCallback("gsa1_board_sounds", function() B.ApplySounds() end, "gsa1_board")

local function server_has(name)
    return util.NetworkStringToID(name) ~= 0
end

-- a toast (the wheel's: gsa1_wheel_toast, never while the wheel is hidden), else the console
local function toast(fmt, ...)
    if W and W.Toast then
        W.Toast(fmt, ...)
    elseif GSA1.Msg then
        GSA1.Msg(fmt, ...)
    end
end
B.Toast = toast

-- the state of one character -----------------------------------------------------------------------------------------------
function B.State(C)
    local b = C.board
    if not b then
        b = { on = false, entering = nil, walk = nil, leaving = nil, refusal = nil, st = {}, why = WHY.WHEEL }
        C.board = b
    end
    return b
end

-- carrying something (gsa1.StateEx: the interaction feature's held object)
local exbuf = {}
local function state_ex(C)
    if not (C and C.id and gsa1 and gsa1.StateEx) then return nil end
    local ok, s = pcall(gsa1.StateEx, C.id, exbuf)
    if ok and type(s) == "table" then return s end
    return nil
end
function B.Carrying(C)
    local s = state_ex(C)
    return s ~= nil and ((tonumber(s.held) or 0) ~= 0 or (tonumber(s.held_object) or 0) ~= 0)
end

-- the server knows this riding state of the slot (only an edge is sent)
B.sent = B.sent or {}
function B.SendState(on, why, idx)
    if not server_has(B.NET.ST) then
        B.sent[0] = on
        return false
    end
    net.Start(B.NET.ST)
    net.WriteBool(on and true or false)
    net.WriteUInt(math.Clamp(tonumber(why) or 0, 0, 7), 3)
    net.WriteUInt(math.Clamp(tonumber(idx) or 0, 0, 65535), 16)
    net.WriteUInt(0, 4)
    net.SendToServer()
    B.sent[0] = on
    return true
end

-- a refusal: a toast, a log line, nothing else
function B.Refuse(C, why, how, code)
    local b = C and B.State(C)
    why = tostring(why or "can't get on a board now")
    if b then b.refusal = { why = why, at = now_s() } end
    local title = C and C.title or "the character"
    toast("%s can't ride a board now: %s", title, why)
    log("%s: no board (%s): %s%s", title, tostring(how or "?"), why, code and (" [" .. tostring(code) .. "]") or "")
    return false, why
end

-- the terrain of a setting (0 map, 1 snow, 2 sand) as the module's constant
local function terrain_const(t)
    t = tonumber(t) or 0
    if t == 1 then return bconst("TERRAIN_SNOW", 1) end
    if t == 2 then return bconst("TERRAIN_SAND", 2) end
    return bconst("TERRAIN_MAP", 0)
end
function B.WheelOpts()
    return { terrain = terrain_const(cv.terrain:GetInt()), push = cv.push:GetBool(), tails_jump = cv.tails_jump:GetBool() }
end
-- a Board On box's options: Push 1 the push, 0 none, 2 the rider's setting; Ground 0 the rider's setting, 1 map, 2 snow,
-- 3 sand
function B.BoxOpts(push, ground)
    push, ground = tonumber(push) or 1, tonumber(ground) or 0
    local p = (push == 1) or (push == 2 and cv.push:GetBool())
    local t = ground == 0 and cv.terrain:GetInt() or (ground - 1)
    return { terrain = terrain_const(t), push = p and true or false, tails_jump = cv.tails_jump:GetBool() }
end

-- on: libsa1's entry in the character's world (whether the game took it shows after the next pair: BoardState)
function B.On(C, how, why, opts)
    local b = B.State(C)
    local ok, err, code = gsa1.Board(C.id, true, opts)
    if not ok then return B.Refuse(C, err, how, code) end
    b.entering = { at = now_s(), how = how }
    b.why = why or WHY.WHEEL
    b.lastOpts = opts
    log("%s: getting on a board (%s; %s%s)", C.title or "?", tostring(how), B.TERRAIN_TITLE[tonumber(opts and
        opts.terrain) or 0] or "?", (opts and opts.push) and ", Ice Cap's start push" or "")
    return true
end

-- off: the game's exit (order 24); with gsa1_sv_board_left_max 0 the board is removed at the exit (review R.5)
function B.LeftMax()
    local c = cv.sv_left_max
    return c and c:GetInt() or 5
end
function B.Off(C, how, why, idx)
    local b = B.State(C)
    local remove = B.LeftMax() <= 0
    local ok, err, code = gsa1.Board(C.id, false, remove and { remove = true } or nil)
    if not ok then return B.Refuse(C, err, how, code) end
    b.why, b.offBox, b.removeOnExit = why or WHY.WHEEL, idx, remove
    log("%s: getting off the board (%s)%s", C.title or "?", tostring(how), remove and "; the board is removed" or "")
    return true
end

-- the wheel's toggle, the page's button, gsa1_board_toggle
function B.Toggle(C, how)
    C = C or GSA1.Char
    if not C then return false, "no character" end
    local b = B.State(C)
    local have = B.Have()
    if b.on or (b.st and b.st.on) then
        if not have then return B.Refuse(C, "this G-SA1 module has no board", how) end
        return B.Off(C, how or "the wheel", WHY.WHEEL, nil)
    end
    local ok, why = B.CanBoard(C, have)
    if not ok then return B.Refuse(C, why, how) end
    if B.Carrying(C) then return B.Refuse(C, "carrying something", how) end
    -- a walk to a box's board ends (the board he gets now is not the box's: no use counted there)
    if b.walk then B.WalkCancel(C, CANCEL.GONE, "got on by " .. tostring(how or "the wheel")) end
    return B.On(C, how or "the wheel", WHY.WHEEL, B.WheelOpts())
end
concommand.Add("gsa1_board_toggle", function() B.Toggle(GSA1.Char, "the command gsa1_board_toggle") end, nil,
    "G-SA1: Sonic or Tails gets on a board, or off it (Q menu > Options > G-SA1 > Board)")

-- the wheel ----------------------------------------------------------------------------------------------------------------
local function key_down(code)
    code = tonumber(code) or 0
    return code > 0 and input ~= nil and input.IsButtonDown ~= nil and input.IsButtonDown(code) == true
end
local function pad_raw()
    local p = GSA1.pad
    if p and p.connected then return tonumber(p.raw) or 0 end
    return 0
end
-- the board key / button held (read by the wheel only while it is open: W.OPEN_ACTIONS)
function B.WheelDown(C)
    if key_down(cv.key:GetInt()) then return true end
    local p = cv.pad:GetInt()
    return p > 0 and band(pad_raw(), p) ~= 0
end
-- the press in the open wheel: Sonic / Tails -> the wheel closes (the press held back) and the toggle; anyone else -> a toast,
-- the wheel stays open (returns false)
function B.WheelAct(C)
    local ok, why = B.CanBoard(C, B.Have())
    if not ok then
        toast("%s", why)
        log("board key in the wheel: %s", why)
        return false
    end
    if W and W.Close then W.Close(nil, true) end
    B.wheelClosedAt = now_s()
    B.Toggle(C, "the wheel")
    return true
end
-- the wheel's centre hint for Sonic and Tails
local function short_pad(b)
    local t = W and W.PadTitle and W.PadTitle(b) or tostring(b)
    return string.match(t, "%((%u+)%)") or t
end
function B.WheelHint(C)
    if not C or (C.kind ~= B.KIND_SONIC and C.kind ~= B.KIND_TAILS) or not cv.on:GetBool() then return nil end
    local k, p = cv.key:GetInt(), cv.pad:GetInt()
    local parts = {}
    if k > 0 then parts[#parts + 1] = W and W.KeyName and W.KeyName(k) or tostring(k) end
    if p > 0 then parts[#parts + 1] = short_pad(p) end
    if #parts == 0 then return nil end
    return table.concat(parts, " / ") .. ": board"
end
-- review R.12: the board rows are refused while a kept board lies in his world
function B.RowGate(C, e)
    local b = C and C.board
    if b and b.st and b.st.kept and B.IsBoardRow(C.kind, e) then return "a board is lying here" end
    return nil
end
if W then
    W.OPEN_ACTIONS = W.OPEN_ACTIONS or {}
    for i = #W.OPEN_ACTIONS, 1, -1 do
        if W.OPEN_ACTIONS[i].name == "board" then table.remove(W.OPEN_ACTIONS, i) end
    end
    W.OPEN_ACTIONS[#W.OPEN_ACTIONS + 1] = { name = "board", down = function(C) return B.WheelDown(C) end,
                                             act = function(C) return B.WheelAct(C) end,
                                             hint = function(C) return B.WheelHint(C) end }
    W.PLAY_GATES = W.PLAY_GATES or {}
    for i = #W.PLAY_GATES, 1, -1 do
        if W.PLAY_GATES[i].name == "board" then table.remove(W.PLAY_GATES, i) end
    end
    W.PLAY_GATES[#W.PLAY_GATES + 1] = { name = "board", gate = function(C, e) return B.RowGate(C, e) end }
end
-- a Garry's Mod bind of the board key does nothing while the wheel is open (or right after the key closed it)
hook.Add("PlayerBindPress", "gsa1_board", function(ply, bind, pressed, code)
    if not GSA1.Char or not W then return end
    local recent = B.wheelClosedAt and now_s() - B.wheelClosedAt < 0.1
    if not (W.open or recent) then return end
    local k = cv.key:GetInt()
    if k <= 0 then return end
    if code ~= nil then
        if code == k then return true end
        return
    end
    local name = input and input.LookupKeyBinding and input.LookupKeyBinding(k)
    if name and bind and string.lower(name) == string.lower(bind) then return true end
end)

-- the binders' refusals: the old key / button stays (the note says why) --------------------------------------------------------
local function cvi(name)
    local c = GetConVar(name)
    return c and c:GetInt() or 0
end
function B.KeyRefused(code)
    code = tonumber(code) or 0
    if code <= 0 then return nil end
    local others = {}
    local function add(name, why)
        local k = cvi(name)
        if k > 0 then others[k] = others[k] or why end
    end
    add("gsa1_wheel_key", "the wheel key")
    add("gsa1_wheel_face_key", "the face trigger")
    add("gsa1_wheel_hide_key", "the hide key")
    add("gsa1_interact_key", "the interact key")
    add("gsa1_lift_key", "the lift key")
    if others[code] then return others[code] end
    if W and W.KeyRefusal then
        local lookup = input and input.LookupBinding
        local keycode = input and input.GetKeyCode
        return W.KeyRefusal(code, lookup and function(b) return lookup(b) end or nil,
            keycode and function(n) return keycode(n) end or nil, cvi("gsa1_super_key"))
    end
    return nil
end
B.PAD_RESERVED = { [0x0100] = "the wheel's page button (LB)", [0x0200] = "the wheel's page button (RB)",
                   [0x2000] = "the wheel's cancel button (B)", [0x1000] = "jump (A)",
                   [0x0010] = "Start (kept for the Character Select)" }
function B.PadRefused(bits)
    bits = tonumber(bits) or 0
    if bits <= 0 then return nil end
    if bits == cvi("gsa1_wheel_pad") then return "the wheel button" end
    if bits == cvi("gsa1_wheel_face_pad") then return "the face trigger" end
    if bits == cvi("gsa1_super_pad") then return "the Super transformation button" end
    return B.PAD_RESERVED[bits]
end
cvars.AddChangeCallback("gsa1_board_key", function(name, old, new)
    local why = B.KeyRefused(tonumber(new))
    if why then
        local kn = W and W.KeyName or tostring
        B.keyNote = string.format("%s is %s: the board key stays %s", kn(tonumber(new)), why, kn(tonumber(old)))
        log("%s", B.keyNote)
        if GSA1.Chat then GSA1.Chat("%s", B.keyNote) end
        RunConsoleCommand("gsa1_board_key", tostring(old))
    elseif tonumber(new) ~= tonumber(old) then
        B.keyNote = nil
    end
end, "gsa1_board")
cvars.AddChangeCallback("gsa1_board_pad", function(name, old, new)
    local why = B.PadRefused(tonumber(new))
    if why then
        local pt = W and W.PadTitle or tostring
        B.keyNote = string.format("%s is %s: the board button stays %s", pt(tonumber(new)), why, pt(tonumber(old)))
        log("%s", B.keyNote)
        if GSA1.Chat then GSA1.Chat("%s", B.keyNote) end
        RunConsoleCommand("gsa1_board_pad", tostring(old))
    elseif tonumber(new) ~= tonumber(old) then
        B.keyNote = nil
    end
end, "gsa1_board")

-- the free controller buttons now (the page's line: the pad map, the wheel, the Super button, Start, the D-pad)
B.PAD_FREE_ORDER = { { 0x0040, "LS", "ls" }, { 0x0080, "RS", "rs" }, { 0x0001, "D-pad up" }, { 0x0004, "D-pad left" },
                     { 0x0008, "D-pad right" }, { 0x0002, "D-pad down" }, { 0x0020, "Back", "back" },
                     { 0x8000, "Y", "y" }, { 0x4000, "X", "x" } }
function B.FreeButtons()
    local used = { [0x1000] = true, [0x2000] = true, [0x0100] = true, [0x0200] = true, [0x0010] = true }
    for _, bt in ipairs({ cvi("gsa1_wheel_pad"), cvi("gsa1_wheel_face_pad"), cvi("gsa1_super_pad"), cv.pad:GetInt() }) do
        if bt > 0 then used[bt] = true end
    end
    local dpad = GSA1.cv and GSA1.cv.pad_dpad and GSA1.cv.pad_dpad:GetBool()
    local names, dp = {}, {}
    for _, e in ipairs(B.PAD_FREE_ORDER) do
        local bits, title, mapname = e[1], e[2], e[3]
        local mapped = mapname and GSA1.cv and GSA1.cv["pad_" .. mapname] and GSA1.cv["pad_" .. mapname]:GetInt() ~= 0
        local isd = band(bits, 0x000F) ~= 0
        if not used[bits] and not mapped and not (isd and dpad) then
            if isd then dp[#dp + 1] = string.sub(title, 7) else names[#names + 1] = title end
        end
    end
    if #dp > 0 then names[#names + 1] = "D-pad " .. table.concat(dp, " / ") end
    return #names > 0 and table.concat(names, ", ") or "none"
end

-- the walk to a box's board (Board On) --------------------------------------------------------------------------------------
-- the tick's camera yaw (cl_character.lua tick_character: GSA1.TickYaw, else the view's)
function B.TickYaw(C)
    local y = GSA1.TickYaw and GSA1.TickYaw(C)
    if y then return y end
    local ply = LocalPlayer()
    return IsValid(ply) and ply:EyeAngles().y or 0
end

-- the stick (sx right, sy forward) towards (tx, ty) from (x, y) in the camera frame of yaw (degrees), of length mag
function B.StickTowards(x, y, tx, ty, yaw, mag)
    local dx, dy = tx - x, ty - y
    local d = sqrt(dx * dx + dy * dy)
    if d < 1e-3 then return 0, 0 end
    dx, dy = dx / d, dy / d
    local cy, sy = cos(rad(yaw)), sin(rad(yaw))
    return (dx * sy - dy * cy) * mag, (dx * cy + dy * sy) * mag
end

-- the stick's length: 0.7 (the game's walk) while at most 0.5 units a step fast (gsa1_board_walk 1: 1.0), 1.0 faster;
-- never below 0.6
function B.WalkStick(speed)
    local m = ((tonumber(speed) or 0) > B.WALK_FAST or cv.walk:GetInt() == 1) and B.JOG_STICK or B.WALK_STICK
    return max(m, B.STICK_MIN)
end

-- the last pair's path a -> b passes the board t: within REACH_H horizontally and REACH_V vertically
function B.PathReach(ax, ay, az, bx, by, bz, t)
    local dx, dy = bx - ax, by - ay
    local L2 = dx * dx + dy * dy
    local k = 0
    if L2 > 1e-9 then k = math.Clamp(((t.x - ax) * dx + (t.y - ay) * dy) / L2, 0, 1) end
    local px, py, pz = ax + dx * k - t.x, ay + dy * k - t.y, az + (bz - az) * k - t.z
    return px * px + py * py <= B.REACH_H * B.REACH_H and abs(pz) <= B.REACH_V
end

-- the box's edge-test data on the client (its pose and size now)
function B.ClientBoxData(ent)
    local L, Wd, H = B.Size(ent)
    local pos, ang = ent:GetPos(), ent:GetAngles()
    return B.MakeBox(ent, pos.x, pos.y, pos.z, ang.p, ang.y, ang.r, L, Wd, H)
end

local function send_cancel(w, why)
    if not (w and server_has(B.NET.CANCEL)) then return end
    net.Start(B.NET.CANCEL)
    net.WriteUInt(w.idx or 0, 16)
    net.WriteUInt(0, 4)
    net.WriteUInt(w.claim or 0, 8)
    net.WriteUInt(why or 0, 3)
    net.SendToServer()
end

function B.WalkCancel(C, why, text)
    local b = C and C.board
    local w = b and b.walk
    if not w then return end
    b.walk = nil
    send_cancel(w, why)
    log("%s: the walk to the board of Board On box %d ended: %s", C.title or "?", w.idx or 0, tostring(text or
        B.CANCEL_NAME[why] or "?"))
end

-- the server's GO: the walk starts (or a cancel at once: not Sonic / Tails, carrying something, riding)
function B.StartWalk(C, idx, claim, place, push, ground, life)
    local b = B.State(C)
    local w0 = { idx = idx, claim = claim }
    local ok, why = B.CanBoard(C, B.Have())
    if ok and B.Carrying(C) then ok, why = false, "carrying something" end
    if ok and (b.on or (b.st and b.st.on)) then ok, why = false, "already on a board" end
    if not ok then
        send_cancel(w0, CANCEL.REFUSED)
        log("%s: Board On box %d: no walk (%s)", C.title or "?", idx, why)
        return false, why
    end
    if b.walk then B.WalkCancel(C, CANCEL.GONE, "another box") end
    local s = C.state or {}
    local dx, dy = place.x - (s.x or 0), place.y - (s.y or 0)
    local dist = sqrt(dx * dx + dy * dy)
    local ent = Entity(idx)
    local tn = now_s()
    b.walk = { idx = idx, claim = claim, ent = ent, target = Vector(place), push = push, ground = ground, at = tn,
               deadline = tn + B.WalkDeadline(dist), life = life, step0 = tonumber(s.step) or 0,
               lx = s.x, ly = s.y, lz = s.z, box = IsValid(ent) and B.ClientBoxData(ent) or nil }
    log("%s: walking to the board of Board On box %d (%.0f HU away; at most %.1f s)", C.title or "?", idx, dist,
        b.walk.deadline - tn)
    return true
end

-- GSA1.FilterStick: the walk's stick replaces the player's
function B.Stick(C, sx, sy)
    local b = C and C.board
    local w = b and b.walk
    if not w then return sx, sy end
    if w.reached then return w.sx or sx, w.sy or sy end
    local s = C.state
    if not (s and s.x) then return sx, sy end
    local nx, ny = B.StickTowards(s.x, s.y, w.target.x, w.target.y, B.TickYaw(C), B.WalkStick(b.st and b.st.speed))
    w.sx, w.sy = nx, ny
    return nx, ny
end
B.prevStick = B.prevStick or GSA1.FilterStick
GSA1.FilterStick = function(C, sx, sy)
    if B.prevStick then sx, sy = B.prevStick(C, sx, sy) end
    return B.Stick(C, sx, sy)
end

-- GSA1.FilterButtons: his buttons held back during the walk, except jump - a new jump press ends the walk
local function jump_bit() return tonumber(gsa1 and gsa1.BUTTON_JUMP) or 1 end
function B.Buttons(C, buttons)
    local b = C and C.board
    local w = b and b.walk
    if not w then return buttons end
    local J = jump_bit()
    local jump = band(buttons, J) ~= 0
    if w.jumpHeld == nil then
        w.jumpHeld = jump                 -- (a jump held when the walk started is no press)
    elseif jump and not w.jumpHeld then
        B.WalkCancel(C, CANCEL.JUMP, "jumped")
        return buttons
    else
        w.jumpHeld = jump
    end
    return band(buttons, J)
end
B.prevFilter = B.prevFilter or GSA1.FilterButtons
GSA1.FilterButtons = function(C, buttons)
    if B.prevFilter then buttons = B.prevFilter(C, buttons) end
    return B.Buttons(C, buttons)
end

-- after each tick: the reach, the deadline, leaving the box, a hit, death
function B.WalkThink(C, st, tn)
    local b = C.board
    local w = b.walk
    if not w then return end
    if C.death then return B.WalkCancel(C, CANCEL.GONE, "died") end
    if tn > w.deadline then return B.WalkCancel(C, CANCEL.DEADLINE, "the walk took too long") end
    if w.reached then return end
    local s = C.state
    local px, py, pz = s.x or 0, s.y or 0, s.z or 0
    local ax, ay, az = w.lx or px, w.ly or py, w.lz or pz
    w.lx, w.ly, w.lz = px, py, pz
    if B.PathReach(ax, ay, az, px, py, pz, w.target) then
        w.reached = true
        local ok, err, code = gsa1.Board(C.id, true, B.BoxOpts(w.push, w.ground))
        if not ok then
            B.Refuse(C, err, "a Board On box", code)
            return B.WalkCancel(C, CANCEL.REFUSED, err)
        end
        b.entering = { at = tn, how = "a Board On box" }
        b.why = WHY.BOX
        b.hideBox = w.idx
        b.lastOpts = B.BoxOpts(w.push, w.ground)
        log("%s: at the board of Board On box %d after %.2f s", C.title or "?", w.idx, tn - w.at)
        return
    end
    if w.box and B.Outside(w.box, px, py, pz + B.LIFT) > B.LEAVE_OUT then
        return B.WalkCancel(C, CANCEL.LEFT, "left the box")
    end
    local ex = state_ex(C)
    local hs = ex and tonumber(ex.hurt_steps)
    if hs and hs >= 0 and hs < (tonumber(s.step) or 0) - w.step0 then
        return B.WalkCancel(C, CANCEL.HURT, "was hurt")
    end
end

-- on the board: the server hears it once
function B.WalkTook(C)
    local b = C.board
    local w = b.walk
    if not w then return end
    b.walk = nil
    if server_has(B.NET.TOOK) then
        net.Start(B.NET.TOOK)
        net.WriteUInt(w.idx or 0, 16)
        net.WriteUInt(0, 4)
        net.WriteUInt(w.claim or 0, 8)
        net.SendToServer()
    end
    log("%s: on the board of Board On box %d", C.title or "?", w.idx or 0)
end

-- the server's messages ------------------------------------------------------------------------------------------------------
B.boxNote = B.boxNote or {}
function B.OnBox(idx, what, slot, claim, place, yaw, push, ground, secs)
    local C = GSA1.Char                    -- slot 0: the player's own character (0.9.6: followers)
    if slot ~= 0 then return end
    if what == WHAT.GO then
        if not C then
            send_cancel({ idx = idx, claim = claim }, CANCEL.GONE)
            return
        end
        B.StartWalk(C, idx, claim, place, push, ground, secs)
    elseif what == WHAT.OFF then
        if C and B.State(C).on then B.Off(C, "a Board Off box", WHY.OFF_BOX, idx) end
    elseif what == WHAT.RIDING then
        -- a rider in a Board On box: the box's ground from now on (riding: only the terrain changes)
        if C and B.State(C).on and (tonumber(ground) or 0) ~= 0 then
            local opts = B.BoxOpts(push, ground)
            gsa1.Board(C.id, true, { terrain = opts.terrain })
        end
    elseif what == WHAT.GONE then
        B.boxNote[idx] = { at = now_s(), secs = secs, what = what }
    elseif what == WHAT.SPENT then
        B.boxNote[idx] = { at = now_s(), what = what }
    end
end
net.Receive(B.NET.BOX, function(len)
    local idx, what, slot, claim = net.ReadUInt(16), net.ReadUInt(3), net.ReadUInt(4), net.ReadUInt(8)
    local place, yaw = net.ReadVector(), net.ReadFloat()
    local push, ground, secs = net.ReadUInt(2), net.ReadUInt(2), net.ReadFloat()
    B.OnBox(idx, what, slot, claim, place, yaw, push, ground, secs)
end)

-- the hand-over of a board got off (gsa1_095_plan.md 4.8, review R.5) ---------------------------------------------------------
local trace_out = {}
function B.ExitPose(L)
    local p = L and L.exit
    if not p then return nil end
    local tr = util.TraceLine and util.TraceLine({ start = Vector(p.x, p.y, p.z + 16), endpos = Vector(p.x, p.y, p.z - 256),
        mask = MASK_SOLID_BRUSHONLY, output = trace_out })
    local z = (tr and tr.Hit and tr.HitPos) and tr.HitPos.z or p.z
    return { x = p.x, y = p.y, z = z, p = 0, yaw = L.yaw or 0, r = 0 }
end
local function copy_pose(s, into)
    into = into or {}
    into.x, into.y, into.z, into.p, into.yaw, into.r = s.x, s.y, s.z, s.pitch or 0, s.yaw or 0, s.roll or 0
    return into
end

function B.StartLeaving(C)
    local b = C.board
    if b.removeOnExit then
        b.removeOnExit = nil
        return
    end
    local s = C.state or {}
    b.leaving = { at = now_s(), kind = C.kind, variant = tonumber(b.st.variant) or 0,
                  exit = { x = s.x or 0, y = s.y or 0, z = s.z or 0 }, yaw = C.drawYaw or s.yaw or 0 }
end

function B.SendLeft(C, pose, why)
    local b = C.board
    local L = b.leaving
    b.leaving = nil
    if not (L and pose) then return false end
    if not server_has(B.NET.LEFT) then
        log("%s: the board stays in your world (the server has no G-SA1 board)", C.title or "?")
        return false
    end
    if B.LeftMax() <= 0 then return false end
    -- the world's own board goes when the decoration arrives, at the latest FREE_AFTER later (not when it fell or a new
    -- board replaced it: libsa1 freed it already); set before sending (the entity may arrive at once)
    if why ~= "it fell" and why ~= "a new board" and why ~= "the world goes" then
        b.pendingFree = { at = now_s() + B.FREE_AFTER, sent = now_s() }
    end
    net.Start(B.NET.LEFT)
    net.WriteVector(Vector(pose.x, pose.y, pose.z))
    net.WriteAngle(Angle(pose.p or 0, pose.yaw or 0, pose.r or 0))
    net.WriteUInt(math.Clamp(L.kind or 0, 0, 15), 4)
    net.WriteUInt(math.Clamp(L.variant or 0, 0, 15), 4)
    net.WriteUInt(0, 4)
    net.SendToServer()
    log("%s: the board got off is handed over at (%.0f %.0f %.0f) (%s)", C.title or "?", pose.x, pose.y, pose.z, why)
    return true
end

function B.LeaveThink(C, s, tn)
    local b = C.board
    local L = b.leaving
    if not L then return end
    if s.kept then
        L.pose = copy_pose(s, L.pose)
        if (tonumber(s.kind) or -1) >= 0 then L.kind = s.kind end
        L.variant = tonumber(s.variant) or L.variant
        if (tonumber(s.still) or 0) > 0 then L.rest = copy_pose(s, L.rest) end
        if s.settled then return B.SendLeft(C, L.pose, "settled") end
    end
    if tn - L.at >= B.LEAVE_MAX then return B.SendLeft(C, L.pose or L.rest or B.ExitPose(L), "after 2 s") end
end

function B.FreeKept(C, why)
    local b = C and C.board
    if not (b and b.pendingFree) then return end
    b.pendingFree = nil
    if gsa1.BoardFree then
        local ok, err = gsa1.BoardFree(C.id)
        log("%s: the world's board freed (%s)%s", C.title or "?", why, ok and "" or (": " .. tostring(err)))
    end
end

-- libsa1 freed a board task (BoardState.freed): it fell, or a new ON replaced it while it was watched -> handed over with
-- its last resting pose (else the exit place traced down): a board the owner got off is never lost
function B.OnFreed(C, s)
    local b = C.board
    local why = tonumber(s.freed_why) or -1
    if b.leaving and (why == 1 or why == 2) then
        local L = b.leaving
        B.SendLeft(C, L.rest or B.ExitPose(L), why == 1 and "it fell" or "a new board")
    end
    if why ~= 3 then b.pendingFree = nil end
end

-- after each tick ------------------------------------------------------------------------------------------------------------
B.hidden = B.hidden or {}                -- [box index] = until (the local character took that box's board)
function B.Poll(C, st, dt)
    local b = B.State(C)
    if not B.Have() then return end
    local s = gsa1.BoardState(C.id, b.st)
    if type(s) ~= "table" then return end
    local tn = now_s()
    local on = s.on == true
    if on ~= b.on then
        b.on = on
        local why = b.why or WHY.WHEEL
        if on then
            b.entering = nil
            if b.walk then B.WalkTook(C) end
        elseif not C.death then
            B.StartLeaving(C)              -- (a death on the board leaves no board behind: the respawn is a new world)
        end
        B.SendState(on, why, (not on and why == WHY.OFF_BOX) and b.offBox or nil)
        B.lastEdge = { on = on, why = why, at = tn }
        if GSA1.RunHook then GSA1.RunHook("GSA1BoardChanged", C, on, B.WHY_WORD[why] or tostring(why)) end
        log("%s %s (%s)", C.title or "?", on and "rides a board" or "got off the board", B.WHY_NAME[why] or "?")
        b.why, b.offBox = WHY.WHEEL, nil
    elseif (B.sent[0] == true) ~= on then
        B.SendState(on, WHY.WHEEL, nil)
    end
    if s.refused then
        b.entering = nil
        local reason = tostring(s.reason or "can't get on a board now")
        B.Refuse(C, reason, "the game")
        if b.walk then B.WalkCancel(C, CANCEL.REFUSED, reason) end
    end
    if s.held and b.hideBox then
        B.hidden[b.hideBox] = tn + 3
        b.hideBox = nil
    end
    if (tonumber(s.freed) or 0) > 0 then B.OnFreed(C, s) end
    if b.leaving then B.LeaveThink(C, s, tn) end
    if b.walk then B.WalkThink(C, st, tn) end
    if b.pendingFree and tn >= b.pendingFree.at then B.FreeKept(C, "1 s after sending") end
end

hook.Add("GSA1PostTick", "gsa1_board", function(C, st, dt)
    if not C then return end
    local ok, err = pcall(B.Poll, C, st, dt)
    if not ok and not B.pollError then
        B.pollError = true
        log("error: %s", tostring(err))
        ErrorNoHalt("[G-SA1] board: " .. tostring(err) .. "\n")
    end
end)

-- a re-created character (upgrades, the map's collision, a fault, a teleport) that rode: on a new board before its first
-- tick; a respawn after dying on a board: only with gsa1_board_respawn 1; spawned / switched: on foot
hook.Add("GSA1CharacterCreated", "gsa1_board", function(C, how, old)
    if not C then return end
    local b = B.State(C)
    local ob = old and old.board
    if not ob then return end
    if how == "re-created" and (ob.on or ob.wasOn) then
        b.reapply, b.reapplyOpts = WHY.RECREATED, ob.lastOpts
    elseif how == "respawned" and ob.diedOnBoard and cv.respawn:GetBool() then
        b.reapply, b.reapplyOpts = WHY.RESPAWNED, ob.lastOpts
    end
end)
hook.Add("GSA1PreTick", "gsa1_board", function(C)
    local b = C and C.board
    if not (b and b.reapply) then return end
    local why, opts = b.reapply, b.reapplyOpts
    b.reapply, b.reapplyOpts = nil, nil
    if not B.Have() then return end
    local ok = B.CanBoard(C, true)
    if ok then B.On(C, B.WHY_NAME[why], why, opts or B.WheelOpts()) end
end)
hook.Add("GSA1CharacterDied", "gsa1_board", function(C)
    local b = C and C.board
    if b and b.on then
        b.diedOnBoard = true
        b.leaving = nil
    end
end)
hook.Add("GSA1CharacterLeaving", "gsa1_board", function(C, how)
    local b = C and C.board
    if not b then return end
    if b.walk then B.WalkCancel(C, CANCEL.GONE, "the character was " .. tostring(how or "removed")) end
    if b.leaving then
        local L = b.leaving
        B.SendLeft(C, L.pose or L.rest or B.ExitPose(L), "the world goes")
    end
    b.pendingFree = nil
    b.wasOn = b.on
end)
hook.Add("GSA1CharacterRemoved", "gsa1_board", function(C, switching)
    if B.sent[0] then B.SendState(false, WHY.WHEEL, nil) end
    if C and C.board and C.board.on and GSA1.RunHook then GSA1.RunHook("GSA1BoardChanged", C, false, "removed") end
end)

-- the left boards' arrival: the rider's world frees its own board (review R.5) --------------------------------------------------
B.lefts = B.lefts or {}
function B.CheckArrival(ent)
    if not B.IsLeft(ent) then return end
    local C = GSA1.Char
    local b = C and C.board
    if not (b and b.pendingFree) then return end
    local rider = ent.GetRider and ent:GetRider()
    local slot = ent.GetSlot and tonumber(ent:GetSlot()) or 0
    if rider == LocalPlayer() and slot == 0 then B.FreeKept(C, "the left board arrived") end
end
function B.LeftInit(ent)
    B.lefts[ent:EntIndex()] = ent
    B.CheckArrival(ent)
end
function B.LeftRemove(ent)
    local idx = ent:EntIndex()
    B.lefts[idx] = nil
    local V = GSA1.ObjView
    if V and V.ExtraRemove then V.ExtraRemove("left:" .. idx) end
end
hook.Add("NetworkEntityCreated", "gsa1_board", function(ent) B.CheckArrival(ent) end)

-- the view ----------------------------------------------------------------------------------------------------------------------
-- the camera behind the board (gsa1_board_camera): the view yaw eases towards the drawn yaw; a mouse or right-stick turn
-- pauses it for a second
B.cam = B.cam or { pauseUntil = 0, last = 0 }
function B.CameraMove(cmd)
    local C = GSA1.Char
    local b = C and C.board
    local cam = B.cam
    local tn = now_s()
    local dt = math.Clamp(tn - (cam.last or tn), 0, 0.1)
    cam.last = tn
    if not (b and b.on and cv.camera:GetBool() and C.drawYaw) then return false end
    local mx = cmd.GetMouseX and cmd:GetMouseX() or 0
    local my = cmd.GetMouseY and cmd:GetMouseY() or 0
    local p = GSA1.pad
    local rx, ry = 0, 0
    if p and p.connected then rx, ry = tonumber(p.rx) or 0, tonumber(p.ry) or 0 end
    local dz = GSA1.cv and GSA1.cv.pad_dead_r and GSA1.cv.pad_dead_r:GetFloat() or 0.2
    if mx ~= 0 or my ~= 0 or rx * rx + ry * ry > dz * dz then cam.pauseUntil = tn + B.CAM_PAUSE end
    if tn < cam.pauseUntil or dt <= 0 then return false end
    local va = cmd:GetViewAngles()
    local d = math.NormalizeAngle(C.drawYaw - va.y)
    if abs(d) < 0.01 then return false end
    va.y = va.y + d * (1 - math.exp(-dt / B.CAM_TAU))
    cmd:SetViewAngles(va)
    return true
end
hook.Add("CreateMove", "gsa1_board_camera", function(cmd)
    if not GSA1.Char then return end
    B.CameraMove(cmd)
end)

-- the game's speed field of view while riding (gsa1_board_fov; mode 0: yours + (degrees - 70), 1: the game's degrees),
-- eased at 168.75 degrees a second; back to yours after the ride
function B.FovApply(view, C)
    local b = C and C.board
    local base = tonumber(view and view.fov)
    if not base then return false end
    local riding = b and b.on and cv.fov:GetBool()
    if not riding and not B.fovCur then return false end
    local target = base
    if riding then
        local deg = B.FovDegrees(b.st and b.st.speed)
        target = cv.fov_mode:GetInt() == 1 and deg or (base + deg - 70)
    end
    local tn = now_s()
    local dt = math.Clamp(tn - (B.fovAt or tn), 0, 0.25)
    B.fovAt = tn
    local cur = B.fovCur or base
    local step = B.FOV_RATE * dt
    if abs(target - cur) <= step then cur = target else cur = cur + (target > cur and step or -step) end
    if not riding and abs(cur - base) < 0.01 then
        B.fovCur, B.fovAt = nil, nil
        return false
    end
    B.fovCur = cur
    view.fov = cur
    return true
end
B.prevView = B.prevView or GSA1.ViewOverride
GSA1.ViewOverride = function(view, C, ply)
    local ov = B.prevView and B.prevView(view, C, ply) or nil
    local v = (type(ov) == "table" and ov.origin and ov.angles) and ov or view
    B.FovApply(v, C)
    return ov
end

-- the drawing -------------------------------------------------------------------------------------------------------------------
B.boxes = B.boxes or {}                 -- [entity index] = the box entity (client)
B.boundsDirty = B.boundsDirty or {}
B.COL_ON, B.COL_OFF, B.COL_GREY = Color(60, 220, 90), Color(255, 90, 60), Color(140, 140, 140)
B.FACE_ALPHA = 40

function B.ApplyBounds(ent)
    local mins, maxs = B.Hull(ent)
    if ent.SetSolid then ent:SetSolid(SOLID_OBB or 3) end
    if ent.SetCollisionBounds then ent:SetCollisionBounds(mins, maxs) end
    if ent.EnableCustomCollisions then ent:EnableCustomCollisions(true) end
    if ent.SetRenderBounds then
        local lo, hi = Vector(mins.x - 16, mins.y - 16, mins.z - 16), Vector(maxs.x + 16, maxs.y + 16, maxs.z + 16)
        -- the lying board may lie below a box lifted into the air
        if ent.GetBoardPos then
            local bp = ent:GetBoardPos()
            local pos = ent:GetPos()
            if bp and pos then lo.z = math.min(lo.z, bp.z - pos.z - 32) end
        end
        ent:SetRenderBounds(lo, hi)
    end
end
function B.ClientInit(ent)
    B.ApplyBounds(ent)
    B.boxes[ent:EntIndex()] = ent
end
function B.ClientRemove(ent)
    local idx = ent:EntIndex()
    B.boxes[idx] = nil
    B.hidden[idx] = nil
    local V = GSA1.ObjView
    if V and V.ExtraRemove then V.ExtraRemove("box:" .. idx) end
end
function B.OnVarChanged(ent, name, old, new)
    if old ~= new then B.boundsDirty[ent] = true end
end

-- the boxes show: gsa1_board_box_show 1, no character, or the context menu open (a character never holds the Physics
-- Gun or the Tool Gun: board095_gsa1.md F5)
function B.ShowBoxes()
    if cv.box_show:GetInt() == 1 then return true end
    if not GSA1.Char then return true end
    if g_ContextMenu and g_ContextMenu.IsVisible and g_ContextMenu:IsVisible() then return true end
    local O = GSA1.Objects
    return O ~= nil and O.Editing ~= nil and O.Editing() == true
end

-- the extras' keys, made once per entity index (no string a frame)
B.boxKeys, B.leftKeys = B.boxKeys or {}, B.leftKeys or {}
local function box_key(idx)
    local k = B.boxKeys[idx]
    if not k then
        k = "box:" .. idx
        B.boxKeys[idx] = k
    end
    return k
end
local function left_key(idx)
    local k = B.leftKeys[idx]
    if not k then
        k = "left:" .. idx
        B.leftKeys[idx] = k
    end
    return k
end

-- the pictures' description of a board: kind 0 (variant 0 MIW_B001 / 1 SB_BOARD1) or kind 2; one table per (kind, variant)
B.descs = B.descs or {}
function B.Desc(kind, variant)
    kind = (tonumber(kind) == B.KIND_TAILS) and B.KIND_TAILS or B.KIND_SONIC
    variant = kind == B.KIND_SONIC and math.Clamp(math.floor(tonumber(variant) or 0), 0, 1) or 0
    local key = kind * 16 + variant
    local d = B.descs[key]
    if not d or d.type ~= B.PreviewType() then
        d = { kind = kind, type = B.PreviewType(), params = { variant, 0, 0 }, state = 1 }
        B.descs[key] = d
    end
    return d
end
-- the lying boards' kind: the local character's (Tails sees Tails' board), else Sonic's
function B.PicKind()
    local C = GSA1.Char
    if C and C.kind == B.KIND_TAILS then return B.KIND_TAILS end
    return B.KIND_SONIC
end
function B.PicsReady()
    local V = GSA1.ObjView
    return V ~= nil and V.ExtraAdd ~= nil and V.Ready ~= nil and V.Ready() and B.Have()
end

local function hidden_box(idx, ent)
    local h = B.hidden[idx]
    if not h then return false end
    if now_s() > h or (ent.GetPresent and not ent:GetPresent()) then
        B.hidden[idx] = nil
        return false
    end
    return true
end

-- once per frame: the extras of the lying boards (made while their board lies there), the boxes' bounds after a size change
function B.Think()
    for ent in pairs(B.boundsDirty) do
        B.boundsDirty[ent] = nil
        if IsValid(ent) then B.ApplyBounds(ent) end
    end
    local V = GSA1.ObjView
    if not (V and V.ExtraAdd) then return end
    local ready = B.PicsReady()
    local kind = B.PicKind()
    for idx, ent in pairs(B.boxes) do
        if not IsValid(ent) then
            B.boxes[idx] = nil
            V.ExtraRemove(box_key(idx))
        elseif ready and B.BoxKind(ent) == "on" and ent:GetPresent() and not hidden_box(idx, ent) then
            V.ExtraAdd(box_key(idx), B.Desc(kind, 0))
        else
            V.ExtraRemove(box_key(idx))
        end
    end
end
hook.Add("Think", "gsa1_board", function()
    local ok, err = pcall(B.Think)
    if not ok and not B.thinkError then
        B.thinkError = true
        log("error: %s", tostring(err))
    end
end)

-- the lying board's pose: the board place lifted by the picture's -minz along the ground's normal
local liePos, lieAng = Vector(), Angle()
function B.LyingPose(ent, key)
    local bp, ba = ent:GetBoardPos(), ent:GetBoardAng()
    local V = GSA1.ObjView
    local minz = 0
    if V and V.ExtraBounds then
        local mz = select(3, V.ExtraBounds(key))
        minz = tonumber(mz) or 0
    end
    local ux, uy, uz = B.UpOf(ba.p, ba.y, ba.r)
    liePos:SetUnpacked(bp.x - ux * minz, bp.y - uy * minz, bp.z - uz * minz)
    lieAng.p, lieAng.y, lieAng.r = ba.p, ba.y, ba.r
    return liePos, lieAng
end

local standMin, standMax = Vector(-24, -7, 0), Vector(24, 7, 2)
local function draw_volume(ent)
    if not (render and render.DrawWireframeBox) then return end
    local kind = B.BoxKind(ent)
    local col = kind == "on" and B.COL_ON or B.COL_OFF
    local spent = B.Spent(ent)
    local enabled = not ent.GetEnabled or ent:GetEnabled()
    if spent or not enabled or (cv.sv_on and not cv.sv_on:GetBool()) then col = B.COL_GREY end
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local mins, maxs = B.Hull(ent)
    B.faceCol = B.faceCol or Color(0, 0, 0, B.FACE_ALPHA)
    B.faceCol.r, B.faceCol.g, B.faceCol.b, B.faceCol.a = col.r, col.g, col.b, B.FACE_ALPHA
    if render.SetColorMaterial then render.SetColorMaterial() end
    if render.DrawBox then render.DrawBox(pos, ang, mins, maxs, B.faceCol) end
    render.DrawWireframeBox(pos, ang, mins, maxs, (B.hover == ent) and color_white or col, true)
    -- the label above the box
    if cam and cam.Start3D2D and draw and draw.SimpleTextOutlined then
        local text = (kind == "on" and "Board On" or "Board Off") .. ((tonumber(ent:GetUses()) or 0) == 1 and
            (spent and " - used" or " - 1 use left") or "") .. ((not enabled) and " - disabled" or "")
        if kind == "on" and not spent and not ent:GetPresent() then
            local at = tonumber(ent:GetRespawnAt()) or 0
            text = text .. (at > 0 and string.format(" - back in %.0f s", max(0, at - CurTime())) or " - no refill")
        end
        local ux, uy, uz = B.UpOf(ang.p, ang.y, ang.r)
        local top = Vector(pos.x + ux * (maxs.z + 12), pos.y + uy * (maxs.z + 12), pos.z + uz * (maxs.z + 12))
        local eye = EyeAngles()
        cam.Start3D2D(top, Angle(0, eye.y - 90, 90), 0.25)
        draw.SimpleTextOutlined(text, "DermaLarge", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
        cam.End3D2D()
    end
end

-- gsa1_trigger.lua ENT:Draw (pass 0) / DrawTranslucent (pass 1)
function B.DrawBox(ent, pass, flags)
    local idx = ent:EntIndex()
    local key = box_key(idx)
    local drawn = false
    if B.BoxKind(ent) == "on" and ent:GetPresent() and not hidden_box(idx, ent) then
        local V = GSA1.ObjView
        if V and V.ExtraDraw and B.PicsReady() then
            local pos, ang = B.LyingPose(ent, key)
            drawn = V.ExtraDraw(key, pos, ang, pass, flags) == true
        end
        -- without the module or the disc: a stand-in while editing
        if not drawn and pass == 1 and B.ShowBoxes() and render and render.DrawBox then
            if render.SetColorMaterial then render.SetColorMaterial() end
            render.DrawBox(ent:GetBoardPos(), ent:GetBoardAng(), standMin, standMax, color_white)
        end
    end
    if pass == 1 and B.ShowBoxes() then draw_volume(ent) end
end

-- gsa1_board_left.lua ENT:Draw / DrawTranslucent: the game's board model at the entity's pose
function B.DrawLeft(ent, pass, flags)
    local V = GSA1.ObjView
    if not (V and V.ExtraDraw and B.PicsReady()) then
        if pass == 1 and B.ShowBoxes() and render and render.DrawBox then
            if render.SetColorMaterial then render.SetColorMaterial() end
            render.DrawBox(ent:GetPos(), ent:GetAngles(), standMin, standMax, color_white)
        end
        return
    end
    local key = left_key(ent:EntIndex())
    V.ExtraAdd(key, B.Desc(ent.GetKind and ent:GetKind() or 0, ent.GetVariant and ent:GetVariant() or 0))
    V.ExtraDraw(key, ent:GetPos(), ent:GetAngles(), pass, flags)
end

-- the context menu's hover outline (the box under its cursor, as cl_objects.lua O.FindHover finds the objects)
hook.Add("PreDrawHalos", "gsa1_board_hover", function()
    B.hover = nil
    if not (vgui and vgui.GetHoveredPanel and properties and properties.GetHovered) then return end
    local p = vgui.GetHoveredPanel()
    if not (IsValid(p) and p.IsWorldClicker and p:IsWorldClicker()) then return end
    local ply = LocalPlayer()
    if not (IsValid(ply) and ply.GetAimVector) then return end
    local ok, ent = pcall(properties.GetHovered, EyePos(), ply:GetAimVector())
    if ok and B.IsBox(ent) then B.hover = ent end
end)

-- the spawn tab: a "Board" category after "Rings and Item Boxes" (feat/cl_spawntab.lua T.LATER: any load order) ---------------
GSA1.SpawnTab = GSA1.SpawnTab or {}
do
    local T = GSA1.SpawnTab
    T.LATER = T.LATER or {}
    for i = #T.LATER, 1, -1 do
        if T.LATER[i].name == "Board" then table.remove(T.LATER, i) end
    end
    T.LATER[#T.LATER + 1] = { name = "Board", icon = "icon16/arrow_right.png", classes = function()
        local out = {}
        for _, c in ipairs(B.CLASSES) do out[#out + 1] = c.class end
        return out
    end }
end

-- the page (Q menu > Options > G-SA1 > Board) ------------------------------------------------------------------------------------
function B.StatusLine(C)
    C = C or GSA1.Char
    if not C then return "No character: spawn Sonic or Tails (Character page)." end
    local def = GSA1.CharacterByKind and GSA1.CharacterByKind(C.kind)
    local ok, why = B.CanBoard(C, B.Have())
    if not ok then
        if why == "only Sonic and Tails ride a board" then
            return string.format("%s has no board (only Sonic and Tails)", C.title or (def and def.title) or "?")
        end
        return string.format("%s: %s", C.title or "?", why)
    end
    local b = B.State(C)
    if b.walk then return string.format("%s: walking to the board of Board On box %d", C.title, b.walk.idx or 0) end
    if b.on then
        local spd = (tonumber(b.st.speed) or 0) * 240
        return string.format("%s: on the board (%s), %.0f HU/s", C.title, B.TERRAIN_TITLE[tonumber(b.st.terrain) or 0] or
            "?", spd)
    end
    if b.refusal and now_s() - b.refusal.at < 10 then
        return string.format("%s: can't get on now: %s", C.title, b.refusal.why)
    end
    if b.st and b.st.kept then return string.format("%s: on foot (the board got off lies here)", C.title) end
    return string.format("%s: on foot", C.title)
end

function B.StatusLines()
    local out = { B.StatusLine() }
    if GSA1.cv and GSA1.cv.follow and not GSA1.cv.follow:GetBool() then
        out[#out + 1] = "The boxes need \"Let the server move your player entity\" (Character page)."
    end
    if not server_has(B.NET.ST) then
        out[#out + 1] = "This server does not run G-SA1's boards: the boxes do nothing here (the wheel still works)."
    end
    out[#out + 1] = "Free on your controller now: " .. B.FreeButtons() .. "."
    if B.keyNote then out[#out + 1] = B.keyNote end
    return out
end

local function choice_combo(panel, label, cvname, choices)
    local combo = panel:ComboBox(label)
    for _, c in ipairs(choices) do combo:AddChoice(c[2], tostring(c[1])) end
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
            if n ~= nil and tonumber(ch[1]) == n then
                self:SetText(ch[2])
                return
            end
        end
        self:SetText(v)
    end
    combo.gsa1ConVar = cvname
    return combo
end
B.ChoiceCombo = choice_combo

local function live_label(panel, lines_fn)
    local lbl = panel:Help("...")
    local baseThink = lbl.Think
    lbl.Think = function(self)
        if baseThink then baseThink(self) end
        if RealTime() < (self.gsa1Next or 0) then return end
        self.gsa1Next = RealTime() + 0.5
        local text = table.concat(lines_fn(), "\n")
        if text ~= self.gsa1Text then
            self.gsa1Text = text
            self:SetText(text)
            if self.InvalidateLayout then self:InvalidateLayout(true) end
        end
    end
    return lbl
end

local function binder(panel, cvname)
    local b = vgui.Create("DBinder", panel)
    if b.SetConVar then b:SetConVar(cvname) end
    if b.SetTall then b:SetTall(28) end
    panel:AddItem(b)
    return b
end
B.Binder = binder

function B.PadChoices()
    if W and W.PAD_BUTTONS then return W.PAD_BUTTONS end
    return { { 0, "None" }, { 0x0080, "Right stick click (RS)" }, { 0x0040, "Left stick click (LS)" } }
end

local function admin_part()
    local ply = LocalPlayer()
    if game.SinglePlayer() then return true end
    if IsValid(ply) and ply.IsListenServerHost and ply:IsListenServerHost() then return true end
    return IsValid(ply) and ply.IsAdmin ~= nil and ply:IsAdmin() == true
end

function B.BuildPage(panel)
    panel:Help("Sonic and Tails ride the sand and snow board of Sand Hill and Ice Cap with the game's own board code. Get "
        .. "on and off with the board key while the emote wheel is open, or through Board On / Board Off boxes (Q menu > "
        .. "G-SA1 tab > Board, or Entities > G-SA1).")
    panel:CheckBox("Boards for Sonic and Tails", "gsa1_board")
    panel:ControlHelp("Knuckles, Amy, E-102, Big and Super Sonic cannot ride (as in the game).")
    live_label(panel, B.StatusLines)
    -- getting on and off
    panel:Help("Getting on and off: in the open emote wheel")
    panel:Help("Board key in the open wheel")
    binder(panel, "gsa1_board_key")
    panel:Button("No board key", "gsa1_board_key", "0")
    choice_combo(panel, "Board button in the open wheel", "gsa1_board_pad", B.PadChoices())
    panel:ControlHelp("Open the wheel (TAB, or D-pad down) and press the key or the button: the wheel closes and he gets on, "
        .. "or off. The controller's B button still only closes the wheel; with the wheel closed the key does nothing new. "
        .. "Keys and buttons the character or the wheel use are refused.")
    panel:Button("Get on / off now", "gsa1_board_toggle")
    -- riding
    panel:Help("Riding")
    choice_combo(panel, "Ground under the board", "gsa1_board_terrain", { { 0, "The map's own surfaces (the game's rule)" },
        { 1, "Ice Cap snow everywhere" }, { 2, "Sand Hill sand everywhere" } })
    panel:ControlHelp("The map's surfaces: on its snow and sand the board gathers speed downhill (the game's snow and sand), "
        .. "on concrete or grass it keeps the speed it has. Walking on snow and sand stays as it is. The other two are not "
        .. "the game's own behaviour.")
    choice_combo(panel, "Walking to a box's board", "gsa1_board_walk", { { 0, "Walk (the game's walk)" }, { 1, "Jog" } })
    panel:CheckBox("Ice Cap's start push when you get on with the wheel", "gsa1_board_push")
    panel:ControlHelp("About 960 HU/s on flat ground, as Ice Cap starts its board course. Board On boxes have their own "
        .. "setting (Edit Properties).")
    panel:CheckBox("The camera turns behind the board", "gsa1_board_camera")
    panel:ControlHelp("So that holding W keeps going forward; it waits a second after you turn the camera yourself.")
    panel:CheckBox("Widen the view at speed (the game's 70 to 100 degrees)", "gsa1_board_fov")
    choice_combo(panel, "Field of view", "gsa1_board_fov_mode", { { 0, "Yours, plus up to 30 degrees" },
        { 1, "The game's own (70 to 100 degrees)" } })
    panel:CheckBox("Board sounds (Ice Cap's snow, Sand Hill's sand)", "gsa1_board_sounds")
    panel:CheckBox("Back on a board after a respawn", "gsa1_board_respawn")
    panel:ControlHelp("When he died riding a board (off: back on foot).")
    panel:CheckBox("Keep the game's Tails jump (higher each time he gets on: the game's own bug)", "gsa1_board_tails_jump")
    panel:CheckBox("Super Sonic may ride a board too (the game lets General Gameplay Super Sonic; how he looks: "
        .. "UNVERIFIED)", "gsa1_board_super")
    panel:ControlHelp("Super Sonic (Vs. Perfect Chaos) never rides: his world has no board.")
    -- the boxes
    panel:Help("Board On / Board Off boxes")
    choice_combo(panel, "Show the boxes", "gsa1_board_box_show", { { 0, "While editing (no character, or the context "
        .. "menu)" }, { 1, "Always" } })
    panel:ControlHelp("Each box: right-click > Edit Properties - size, 1 use / infinite, refill, refill time, start push, "
        .. "ground; \"Reset this box\" brings its board back. The board lying in a Board On box always shows.")
    -- the server part
    if admin_part() then
        panel:Help("Server (admins and the listen server's host)")
        panel:CheckBox("Board On / Off boxes work on this server", "gsa1_sv_board")
        panel:NumSlider("Most trigger boxes per player", "sbox_maxgsa1_triggers", 0, 1000, 0)
        panel:NumSlider("Left-behind boards stay (s, 0 = until removed)", "gsa1_sv_board_left_time", 0, 3600, 0)
        panel:NumSlider("Left-behind boards per player (0 = none: the board vanishes)", "gsa1_sv_board_left_max", 0, 64, 0)
        panel:Button("Reset every Board box", "gsa1_sv_board_reset")
    end
    panel:Help("Known limits: the board barely speeds up on flat concrete or grass (the game's rule: it gathers speed "
        .. "downhill on snow and sand); other players do not see your board yet (multiplayer characters are not drawn "
        .. "yet); the boxes need \"Let the server move your player entity\" (Character page, on by default).")
end

GSA1.AddMenuPage(275, "board", "Board", B.BuildPage, B.NEEDS)
