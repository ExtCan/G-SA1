-- feat/cl_climbcam.lua - the climbing camera (0.9.9c; the owner's note "When Knuckles climbs a wall, the camera will sometimes break", and what breaking
-- looked like: "It would go into the wall"; the evidence: sadc build/research/r099c/cam). Only the view: nothing here writes the game's state.
--
-- WHY. On a wall the game puts Knuckles' position ON the wall's polygon and draws the body at position + up x center, up being the wall's normal
-- (func_8C0C9000, func_8C0C46AC). 0.9.9b's CalcView starts its two traces at position + (0, 0, center): on the wall or inside it. A box trace that starts
-- inside a brush is not stopped by that brush, so the eye went into the wall. Where G-SA1's thin-wall rule made one surface in the middle of a wall, the
-- polygon is also up to half the wall's thickness behind what you see.
--
-- WHAT. From the first frame of mode 24 until the camera has handed back, GSA1.ClimbEye (asked by cl_character.lua's CalcView) gives the frame's eye:
--   * The anchor is the drawn body's middle: position + an offset that follows up x center. Up goes between the last two game pairs by the same alpha that
--     gsa1.Render took the position between them, a straight line as the drawn corners do. The grab moves the position by about up x center in the very pair that
--     turns up, and jumping off moves it back, so the two cancel and the body stays where it is: that is the blend, it is the game's own (a plain gate on
--     mode 24 jumps about 30 units in a frame, MEASURED; this moves about what the body moves). FOLLOW_RATE only bounds the offset should up ever do something else. It goes on
--     after mode 24: the game enters mode 25 (over the top) and mode 1 with up still on the wall, and the body is still drawn there; at a wall's end on the owner's map, at 72
--     frames a second, mode 9 keeps up on the wall for 8.7 to 10.4 s (MEASURED). While up is less upright than ON_WALL_Z the offset follows it, for as long as that lasts. If up stays
--     tilted, but no more than a slope is, after LEAVE_HOLD seconds the offset goes to straight up in BLEND_TIME.
--   * A start inside something is noticed (StartSolid), not trusted. In this order: a place along the wall's normal, out and back by 8, by 16, then out by 40, 64
--     (out: the polygon may be behind the visible face; back: a wall opposite may stand in the way), each the start of a trace back to the anchor, so the nearest open place
--     is found; else the sweep from this climb's last open anchor, on the climb's first frame from the eye of the frame before, if that ends near; else further out along the
--     normal, 96, 128 (something stands in front of the wall: the thin-wall slider at its most, MEASURED on the owner's map); else that sweep's far end; else nothing is
--     open: 0.9.9b's own eye for that frame, counted in the session log.
--   * The back trace from an open anchor can only start inside by rounding or a brush that moved between the traces. Then the distance of the frame before,
--     checked by a trace of its own; on the first frame there is none, so the eye at the open anchor.
--   * The view's distance snaps in, because the eye must not pass the wall, and eases out, the whole distance in OUT_TIME at the fastest: the anchor coming
--     up past a wall's top would otherwise throw the eye out in one frame.
--   * First person: the same anchor and search, the eye eyes - center above it (0.9.9b's position + (0, 0, eyes) was in the wall too).
-- It hands back when the character is off the wall and the offset straight up, the anchor open and the distance not easing: that frame gives exactly the eye
-- CalcView's old traces give in the chase camera (in first person it can differ by up to 10 units, for that frame only: this traces, the old eye does not), and from the next frame on they do. There is no time limit on being stuck in a wall with the way out in reach: the old traces would put the eye
-- straight back in. Only a body out of reach ends it: nothing open, or the nearest open place further from it than LOST_FAR (the ladder's reach), off the wall, for LOST_MAX
-- seconds on end: then the camera lets go, 0.9.9b's eye at once, a line in the session log.
-- A new character on the spot, a switch or a re-creation on the wall (GSA1CharacterCreated), is one more way off the wall: the game starts it on the wall's polygon, so the old traces
-- would go straight in. The camera goes on with it, the offset to straight up in BLEND_TIME, and hands back the same way. A respawn, a teleport: it ends there.
-- Everything else goes through CalcView's old code: tests/feat_climbcam_test.lua compares it with a recording of the frozen 0.9.9b.
--
-- STILL WRONG, said plainly: looking straight away from a wall the eye sits between the wall and Knuckles' back, against or inside the body.
-- The eye snaps in when something comes between it and the anchor. When the game takes the body through a wall the eye waits on its own side while the body is inside and then
-- cuts to the far side: it can not get there any other way without going through the wall. The traces see what MASK_SOLID_BRUSHONLY sees, as 0.9.9b's: a wall made of a prop
-- is not known to be seen.
GSA1.ClimbCam = GSA1.ClimbCam or {}
local K = GSA1.ClimbCam

local cv = GSA1.ConVar("gsa1_cam_climb", "1", "While Knuckles climbs, the camera follows his body and stays out of the wall, with no jump when he grabs or leaves it (first person too). "
    .. "0 = as 0.9.9b: the camera starts from inside the wall", 0, 1)

local KNUCKLES_KIND, MODE_CLIMB = 3, 24      -- SA1_CHAR_KNUCKLES; func_8C0C9000 sets the mode. Another character's mode 24 is something else
local FOLLOW_RATE = 1000                     -- units a second the offset may move while it follows up (the grab: 32 units in one pair = 967)
local BLEND_TIME = 0.3                       -- seconds of the way to straight up when up stays tilted, or the character is a new one
local LEAVE_HOLD = 1.0                       -- seconds off the wall in which up is followed, however upright it is (mode 25 lasts 0.6 s, up comes back after it)
local ON_WALL_Z = 0.5                        -- up less upright than this (more than 60 degrees over) is still a wall: the body is drawn out from it
local LOST_FAR = 129                         -- the anchor's open place further than this from where the anchor should be: the body is out of reach (the ladder reaches 128)
local SWEEP_NEAR = 64                        -- the sweep from the earlier point ending this near the anchor is taken before the far end of the ladder (a jump of 100 at a corner otherwise, MEASURED)
local LOST_MAX = 3.0                         -- seconds off the wall that the camera waits for a body out of reach
local OUT_TIME = 0.3                         -- seconds the eye takes at the least to ease out by the whole camera distance
local DONE = 0.01                            -- units from straight up that count as straight up
local CARRY_FAR = 8                          -- a new character this near the old one takes the climbing camera over (GSA1.Recreate: 1 unit above the old one)
-- along the wall's normal from the anchor: + out of the wall. With the thin-wall slider at its most (64) the polygon is 32 behind the face
local LADDER, LADDER_FAR = { 8, -8, 16, -16, 40, 64 }, { 96, 128 }
-- the trace back to the anchor ends this far past it: an anchor that only just touches something counts as inside, and a trace that ends right there would not be stopped
local PAST = 0.25

local hull_min, hull_max = Vector(-5, -5, -5), Vector(5, 5, 5)     -- the box of CalcView's own traces
local centre, top, back, eye, from_p, to_p = Vector(), Vector(), Vector(), Vector(), Vector(), Vector()
local up_res, back_res, probe_res = {}, {}, {}
local up_trace = { start = centre, endpos = top, mins = hull_min, maxs = hull_max, mask = MASK_SOLID_BRUSHONLY, output = up_res }
local back_trace = { start = nil, endpos = back, mins = hull_min, maxs = hull_max, mask = MASK_SOLID_BRUSHONLY, output = back_res }
local probe_trace = { start = from_p, endpos = to_p, mins = hull_min, maxs = hull_max, mask = MASK_SOLID_BRUSHONLY, output = probe_res }
local sqrt = math.sqrt

-- the frame's offset; once a frame (another CalcView in the same frame moves nothing)
local function update_offset(C, S, st, center)
    local frame = FrameNumber()
    if S.frame == frame then return end
    S.frame = frame
    local ux, uy, uz = st.upx, st.upy, st.upz
    local has_up = false
    if ux and uy and uz then
        local l2 = ux * ux + uy * uy + uz * uz
        has_up = l2 > 0.98 and l2 < 1.02
    end
    local climbing = has_up and st.mode == MODE_CLIMB and C.kind == KNUCKLES_KIND
    S.climbing = climbing
    if climbing and not S.active then
        S.active = true
        S.ox, S.oy, S.oz = 0, 0, center
        S.px, S.py, S.pz, S.cx, S.cy, S.cz = 0, 0, 1, 0, 0, 1
        S.step, S.d, S.ax, S.ay, S.az = nil, nil, nil, nil, nil
        S.away, S.time, S.lost, S.carried = 0, 0, 0, nil
        S.solid, S.along, S.earlier, S.nowhere, S.backSolid = 0, 0, 0, 0, 0
    end
    if not S.active then return end
    local dt = FrameTime()
    S.dt, S.lostDt = dt, dt
    S.time = S.time + dt
    -- up before and after the last pair
    if st.step ~= S.step then
        S.step = st.step
        S.px, S.py, S.pz = S.cx, S.cy, S.cz
        if has_up then S.cx, S.cy, S.cz = ux, uy, uz end
    end
    if climbing then
        S.away, S.carried = 0, nil
        S.nx, S.ny, S.nz = ux, uy, uz
    else
        S.away = S.away + dt
    end
    local a = C.alpha or 1
    local ix, iy, iz = S.px + (S.cx - S.px) * a, S.py + (S.cy - S.py) * a, S.pz + (S.cz - S.pz) * a
    local tx, ty, tz, rate
    if not climbing and (S.carried or (S.away >= LEAVE_HOLD and iz >= ON_WALL_Z)) then
        tx, ty, tz, rate = 0, 0, center, center * 1.41421356 / BLEND_TIME
    else
        tx, ty, tz, rate = ix * center, iy * center, iz * center, FOLLOW_RATE
    end
    local dx, dy, dz = tx - S.ox, ty - S.oy, tz - S.oz
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    local step = rate * dt
    if len <= step then
        S.ox, S.oy, S.oz = tx, ty, tz
    else
        local f = step / len
        S.ox, S.oy, S.oz = S.ox + dx * f, S.oy + dy * f, S.oz + dz * f
    end
    -- straight up, exactly: the old traces' own start
    if not climbing and S.ox * S.ox + S.oy * S.oy + (S.oz - center) * (S.oz - center) <= DONE * DONE then
        S.ox, S.oy, S.oz = 0, 0, center
    end
end

-- out of `list` along the normal: the nearest open place from the anchor at x, y, z, or false
local function rungs(S, list, x, y, z)
    local nx, ny, nz = S.nx or 0, S.ny or 0, S.nz or 1
    for i = 1, #list do
        local r = list[i]
        local past = r > 0 and -PAST or PAST
        from_p:SetUnpacked(x + nx * r, y + ny * r, z + nz * r)
        to_p:SetUnpacked(x + nx * past, y + ny * past, z + nz * past)
        util.TraceHull(probe_trace)
        if not probe_res.StartSolid then
            centre:Set(probe_res.HitPos or to_p)
            S.along = S.along + 1
            return true
        end
    end
    return false
end

-- `centre` starts inside something: an open place for it, or false. See the head of this file
local function open_anchor(S)
    local x, y, z = centre.x, centre.y, centre.z
    if rungs(S, LADDER, x, y, z) then return true end
    local v = GSA1.view
    local swept = true
    if S.ax then
        from_p:SetUnpacked(S.ax, S.ay, S.az)
    elseif v and v.origin and v.frame and FrameNumber() - v.frame <= 2 then
        from_p:Set(v.origin)
    else
        swept = false
    end
    local sx, sy, sz
    if swept then
        local dx, dy, dz = x - from_p.x, y - from_p.y, z - from_p.z
        local f = PAST / math.max(sqrt(dx * dx + dy * dy + dz * dz), 1)
        to_p:SetUnpacked(x + dx * f, y + dy * f, z + dz * f)
        util.TraceHull(probe_trace)
        if probe_res.StartSolid then
            swept = false
        else
            local h = probe_res.HitPos or to_p
            sx, sy, sz = h.x, h.y, h.z
            dx, dy, dz = sx - x, sy - y, sz - z
            if dx * dx + dy * dy + dz * dz <= SWEEP_NEAR * SWEEP_NEAR then
                centre:SetUnpacked(sx, sy, sz)
                S.earlier = S.earlier + 1
                return true
            end
        end
    end
    if rungs(S, LADDER_FAR, x, y, z) then return true end
    if not swept then return false end
    centre:SetUnpacked(sx, sy, sz)
    S.earlier = S.earlier + 1
    return true
end

-- how: how it ended, the end of the climb's line in the session log
local function finish(S, how)
    S.active = false
    if GSA1.Log then
        GSA1.Log("camera", "climbing camera: %.1f s; the anchor started inside something on %d frames (found along the wall's normal %d, from an earlier point %d, "
            .. "nowhere: 0.9.9b's eye %d), the back trace on %d; %s", S.time, S.solid, S.along, S.earlier, S.nowhere, S.backSolid, how)
    end
end

-- the eye of this frame, or nil
local function climb_eye(C, S, st, angles, dist)
    local center = C.info.center or 20
    update_offset(C, S, st, center)
    if not S.active then return nil end
    local pos = C.drawPos
    local first_person = dist <= 0
    local rise = first_person and ((C.info.eyes or 28) - center) or GSA1.cv.cam_height:GetFloat()
    local wx, wy, wz = pos.x + S.ox, pos.y + S.oy, pos.z + S.oz
    centre:SetUnpacked(wx, wy, wz)
    top:SetUnpacked(wx, wy, wz + rise)
    util.TraceHull(up_trace)
    local inside = up_res.StartSolid and true or false
    local nowhere, lost = false, false
    if inside then
        S.solid = S.solid + 1
        if open_anchor(S) then
            top:SetUnpacked(centre.x, centre.y, centre.z + rise)
            util.TraceHull(up_trace)
        end
        if up_res.StartSolid then
            S.nowhere = S.nowhere + 1
            nowhere, lost = true, true
        else
            local fx, fy, fz = centre.x - wx, centre.y - wy, centre.z - wz
            lost = fx * fx + fy * fy + fz * fz > LOST_FAR * LOST_FAR
        end
    end
    -- off the wall, a body the eye can not get near: it waits, then lets go
    if lost and not S.climbing then
        S.lost = S.lost + S.lostDt
        S.lostDt = 0
        if S.lost >= LOST_MAX then
            finish(S, "let go: the body stayed out of reach")
            return nil
        end
    else
        S.lost = 0
    end
    if nowhere then return nil end
    S.ax, S.ay, S.az = centre.x, centre.y, centre.z
    local hit = up_res.HitPos or top
    local eased = false
    if first_person then
        eye:Set(hit)
    else
        if GSA1.AngleAxes then GSA1.AngleAxes(angles, back) else back:Set(angles:Forward()) end
        local fx, fy, fz = back.x, back.y, back.z
        back:Mul(-dist)
        back:Add(hit)
        back_trace.start = hit
        util.TraceHull(back_trace)
        if back_res.StartSolid then
            S.backSolid = S.backSolid + 1
            local d = S.d or 0
            eye:SetUnpacked(hit.x - fx * d, hit.y - fy * d, hit.z - fz * d)
            if d > 0 then
                from_p:Set(eye)
                to_p:Set(eye)
                util.TraceHull(probe_trace)
                if probe_res.StartSolid then
                    d = 0
                    eye:Set(hit)
                end
            end
            S.d = d
            eased = true    -- (no hand back on such a frame)
        else
            local h = back_res.HitPos or back
            local ex, ey, ez = h.x - hit.x, h.y - hit.y, h.z - hit.z
            local traced = sqrt(ex * ex + ey * ey + ez * ez)
            local d = S.d
            local grown = d and d + dist / OUT_TIME * (S.dt or 0)
            if d and traced > grown then
                eased = true
                S.d = grown
                eye:SetUnpacked(hit.x - fx * grown, hit.y - fy * grown, hit.z - fz * grown)
            else
                S.d = traced
                eye:Set(h)
            end
            S.dt = 0        -- (another CalcView in the same frame eases no further)
        end
    end
    if not S.climbing and not inside and not eased and S.ox == 0 and S.oy == 0 and S.oz == center then finish(S, "handed back") end
    return eye
end

-- CalcView's seam (cl_character.lua). Nil: its old code gives this frame's eye. The returned Vector is reused: CalcView copies it
function GSA1.ClimbEye(C, angles, dist)
    local S = C.climbCam
    if (C.kind ~= KNUCKLES_KIND or C.state.mode ~= MODE_CLIMB) and not (S and S.active) then return nil end
    if C.climbOff then return nil end
    if not cv:GetBool() then
        if S and S.active then finish(S, "the option was unticked") end
        return nil
    end
    if not S then
        S = { active = false }
        C.climbCam = S
    end
    local ok, res = pcall(climb_eye, C, S, C.state, angles, dist)
    if ok then return res end
    -- never take the view away: this character goes on without it
    C.climbOff, C.climbCam = true, nil
    if GSA1.Log then GSA1.Log("error", "the climbing camera stopped for this character: %s", tostring(res)) end
    return nil
end

-- the session log: the setting, one line per change at a new character (as feat/cl_gamecam.lua; cl_log.lua stays as it is)
function K.LogSettings()
    if not GSA1.Log then return end
    local line = string.format("settings 0.9.9c: the climbing camera (gsa1_cam_climb) %s", cv:GetString())
    if line == K.settingsLine then return end
    K.settingsLine = line
    GSA1.Log("settings", "%s", line)
end
-- a new character: if it stands where the old one climbed (a switch, a re-creation) the camera goes on with it, else the climb's line ends here
hook.Add("GSA1CharacterCreated", "gsa1_climbcam", function(C, how, old)
    K.LogSettings()
    local S = old and old.climbCam
    if not (S and S.active) then return end
    old.climbCam = nil
    local a, b = C.drawPos, old.drawPos
    local same_spot = false
    if a and b and (how == "switched to" or how == "re-created") then
        local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
        same_spot = dx * dx + dy * dy + dz * dz <= CARRY_FAR * CARRY_FAR
    end
    if same_spot and cv:GetBool() then
        S.carried = true
        C.climbCam = S
    else
        finish(S, "the character went")
    end
end)
hook.Add("GSA1CharacterRemoved", "gsa1_climbcam", function(C, switching)
    local S = C.climbCam
    if S and S.active and not switching then finish(S, "the character went") end
end)
