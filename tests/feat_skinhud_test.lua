-- feat_skinhud_test.lua - a skin's name and nameplate pictures (1.0.0 beta 1; sadc docs/research/gsa1_100_select.md 4.7 with RX.11, 7.2 T6): feat/sh_skinhud.lua and feat/cl_skinhud.lua through the
-- addon's autorun, tests/lua_mock.lua, in Garry's Mod's own LuaJIT. NO FONT and no game byte: the pictures are the fake bytes this test's render.Capture gives.
--   lua_host tests/feat_skinhud_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_skinhud_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")
local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end
local cookies = {}
cookie = { GetNumber = function(k, d) return tonumber(cookies[k]) or d end, Set = function(k, v) cookies[k] = v end, GetString = function(k, d) return cookies[k] or d end }
local G = M.module({ speed = 300, features = { super = 5, frontend = 1 } })

-- the engine, as far as the pictures ask
local made, rts, cur, scales, texts, dirs = {}, {}, nil, {}, {}, {}
GetRenderTargetEx = function(name, w, h) rts[name] = rts[name] or { name = name, w = w, h = h } return rts[name] end
render.PushRenderTarget = function(rt) cur = rt end
render.PopRenderTarget = function() cur = nil end
render.OverrideAlphaWriteEnable = function() end
render.Clear = function() end
render.OverrideBlend = function() end
cam.Start2D = cam.Start2D or function() end
cam.End2D = cam.End2D or function() end
cam.PushModelMatrix = function(m) scales[#scales + 1] = { sx = m.sx, sy = m.sy } end
cam.PopModelMatrix = function() end
Matrix = function()
    local t = { sx = 1, sy = 1 }
    function t:Translate() end
    function t:Scale(v) self.sx, self.sy = v.x, v.y end
    return t
end
surface.SetDrawColor = function() end
surface.DrawRect = function() end
surface.CreateFont = function() end
surface.SetFont = function() end
surface.GetTextSize = function(s) return 60 * #s, 128 end                 -- a wide face: "METAL SONIC" must be squeezed
surface.SetTextColor = function() end
surface.SetTextPos = function() end
surface.DrawText = function(s) texts[#texts + 1] = s end
render.Capture = function(t)
    made[#made + 1] = { rt = cur and cur.name, w = t.w, h = t.h }
    return "\137PNG fake picture"
end
Material = function(path)
    return { path = path, IsError = function(self) return M.files[string.gsub(self.path, "^%.%./data/", "")] == nil end,
             GetTexture = function() return { Download = function() end, GetName = function() return path end } end }
end
CreateMaterial = function(name) return { name = name, SetTexture = function() end } end
file.CreateDir = function(d) dirs[d] = true end

GSA1 = nil
M.included = {}
do
    local ok, err = pcall(M.load, "autorun/gsa1_autorun.lua")
    local errs = GSA1 and GSA1.FeatureFileErrors or {}
    check(ok and #errs == 0, "the addon's client files load (%s)", tostring(err or errs[1] or "no error"))
end
local H, K = GSA1 and GSA1.SkinHud, GSA1 and GSA1.Skins
check(H ~= nil and H.Want ~= nil and K ~= nil, "feat/sh_skinhud.lua and cl_skinhud.lua are there")
if not (H and K) then return done() end
local metal, mecha = K.SKINS.metalsonic, K.SKINS.mechasonic

-- the places: the skin's own folder (14.1bg), the ini's keys
do
    local P = H.Paths(metal)
    check(P.dir == "gsa1/skins/sonic/metalsonic/HUD" and P.name == "gsa1/skins/sonic/metalsonic/HUD/name.png" and P.plate == "gsa1/skins/sonic/metalsonic/HUD/nameplate.png" and
        P.list == "gsa1/skins/sonic/metalsonic/HUD/generated.txt", "T6 garrysmod/data/gsa1/skins/<base>/<id>/HUD: name.png, nameplate.png, generated.txt")
    check(H.NAME.w == 1024 and H.NAME.h == 256 and H.PLATE.w == 2048 and H.PLATE.h == 256, "T6 sizes 1024 x 256 and 2048 x 256 (4 x the game's m_sonic and B_SONIC_e)")
    check(H.TextOf(metal, "name") == "METAL SONIC" and H.TextOf(mecha, "plate") == "MECHA SONIC", "T6 the texts in capitals, from char_name and char_nameplate")
    local set = H.ParseGenerated("# a comment\nname.png\n../../evil.png\nnameplate.png\nC:/x.png\n")
    check(set["name.png"] and set["nameplate.png"] and not set["../../evil.png"] and not set["C:/x.png"], "T6 generated.txt: plain .png names only")
end

-- a missing picture: queued once, made and saved, with its line in generated.txt
do
    check(H.Material("metalsonic", "name") == nil, "T6 not made yet: nil (the game's own name stays, no blank frame)")
    check(#H.queue == 2, "T6 both pictures queued once (%d)", #H.queue)
    H.Material("metalsonic", "name")
    check(#H.queue == 2, "T6 asked again: not queued again")
    M.run_hook("PostRender")
    check(#made == 1 and made[1].w == 1024 and made[1].h == 256 and M.files["gsa1/skins/sonic/metalsonic/HUD/name.png"] ~= nil, "T6 the next frame: the name made at 1024 x 256 and saved")
    check(#H.queue == 1, "T6 one picture a frame")
    M.run_hook("PostRender")
    check(#made == 2 and made[2].w == 2048 and made[2].h == 256 and M.files["gsa1/skins/sonic/metalsonic/HUD/nameplate.png"] ~= nil, "T6 then the plate at 2048 x 256")
    local list = H.ParseGenerated(M.files["gsa1/skins/sonic/metalsonic/HUD/generated.txt"])
    check(list["name.png"] and list["nameplate.png"], "T6 both are listed in generated.txt")
    check(H.Material("metalsonic", "name") ~= nil and H.Material("metalsonic", "plate") ~= nil, "T6 from then on the materials are there")
    check(dirs["gsa1/skins/sonic/metalsonic/HUD"] and dirs["gsa1/skins"], "T6 the folders are made one level at a time")
    -- the squeeze: METAL SONIC is 11 letters of 60 px = 660 px at its font: scaled up to the letters' height and squeezed to 960 of 1024
    local s = scales[1]
    check(s and s.sx < s.sy and math.abs(660 * s.sx - H.NAME.max_w) < 1, "T6 \"METAL SONIC\" squeezed sideways to 960 px (%.3f x %.3f)", s and s.sx or 0, s and s.sy or 0)
    check(texts[#texts] == "METAL SONIC" and #texts > 16, "T6 the name drawn with its outline first (%d draws)", #texts)
end
-- an existing picture is loaded and never made; the owner's own stays
do
    M.files["gsa1/skins/sonic/mechasonic/HUD/name.png"] = "the owner's own picture"
    local n0 = #made
    H.Want(mecha)
    check(#H.queue == 1 and H.queue[1].which == "plate", "T6 Mecha: his own name.png is there: only the plate is queued")
    M.run_hook("PostRender")
    check(#made == n0 + 1 and M.files["gsa1/skins/sonic/mechasonic/HUD/name.png"] == "the owner's own picture", "T6 the plate made; the owner's own name.png never touched")
    local s = scales[#scales]
    check(s ~= nil, "T6 the plate's text drawn")
    local list = H.ParseGenerated(M.files["gsa1/skins/sonic/mechasonic/HUD/generated.txt"])
    check(list["nameplate.png"] and not list["name.png"], "T6 generated.txt lists only what G-SA1 made")
end
-- make again: only the listed files go
do
    M.files["gsa1/skins/sonic/metalsonic/HUD/other.txt"] = "someone's note"
    local n = H.Remake()
    check(n == 3 and M.files["gsa1/skins/sonic/metalsonic/HUD/name.png"] == nil and M.files["gsa1/skins/sonic/mechasonic/HUD/name.png"] == "the owner's own picture" and
        M.files["gsa1/skins/sonic/metalsonic/HUD/other.txt"] ~= nil, "T6 \"Make again\" deletes the three made files only (%d), the owner's and other files stay", n)
    check(#H.queue == 3, "T6 and queues them again, one a frame (%d)", #H.queue)
    for _ = 1, 3 do M.run_hook("PostRender") end
    check(M.files["gsa1/skins/sonic/metalsonic/HUD/name.png"] ~= nil and #H.queue == 0, "T6 made again")
    check(M.cmds and M.cmds.gsa1_skins_hud_remake ~= nil, "T6 the command gsa1_skins_hud_remake (the Text page's button)")
end
-- a skin with auto_generate_name = false and no file: nothing is made
do
    local e = { id = "testskin", base = "sonic", char_name = "Test", auto_generate_name = false, auto_generate_nameplate = false,
                name_tex_location = "[skin folder]/HUD/name.png", nameplate_tex_location = "[skin folder]/HUD/nameplate.png" }
    check(H.Wants(e, "name", false) == "none" and H.Wants(e, "name", true) == "load" and H.Wants(metal, "name", false) == "make", "T6 auto_generate_* off and no file: none; a file: load")
end
-- nothing under the addon
do
    local src = host_read(root .. "/gsa1/feat/cl_skinhud.lua") .. host_read(root .. "/gsa1/feat/sh_skinhud.lua")
    check(string.find(src, "addons/", 1, true) == nil and string.find(src, "materials/", 1, true) == nil and string.find(src, ".ttf", 1, true) == nil, "T6 the pictures go to garrysmod/data only; no font named")
end
check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
