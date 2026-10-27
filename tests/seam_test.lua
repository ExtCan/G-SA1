-- seam_test.lua - the addon's side of the feature seam (G0, sadc docs/research/gsa1_rounds_plan.md section 5) in
-- Garry's Mod's own LuaJIT with a mocked GMod (tests/lua_mock.lua). Feature files that exist only in this test
-- (M.virtual) check that the autorun loads gsa1/feat/*.lua after the built-in files - sh_ in both realms first, then
-- cl_ on the client and sv_ on the server, alphabetically, the server sending sh_ and cl_ to the clients - that a feature
-- file which fails to load is reported while the others carry on, GSA1.ConVar (client and replicated server settings),
-- GSA1.AddMenuPage (after the built-in pages, by order; "needs G-SA1 module" when the module lacks the feature; a
-- builder's Lua error shown on the page and logged), GSA1.HasFeature and the "features" lines.
--   lua_host tests/seam_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 seam_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function list(t) return table.concat(t or {}, " ") end
local function index_of(t, v)
    for i, x in ipairs(t) do if x == v then return i end end
end

-- the test's feature files, and only those: the real ones (addon/lua/gsa1/feat) have their own tests, and frame_test
-- loads them through the autorun
local real_list = host_list
host_list = function(dir, pat)
    if string.find(dir, "/gsa1/feat$") then return {} end
    return real_list and real_list(dir, pat) or {}
end
M.virtual["gsa1/feat/sh_zeta.lua"] = [[
GSA1.SeamOrder = GSA1.SeamOrder or {}
table.insert(GSA1.SeamOrder, "sh_zeta")
GSA1.SeamCv = GSA1.ConVar("gsa1_seamtest_level", 3, "a test setting", 0, 10)
GSA1.SeamSv = GSA1.ConVar("gsa1_seamtest_server", 1, "a test server setting", 0, 1, { server = true })
]]
M.virtual["gsa1/feat/sh_alpha.lua"] = [[
GSA1.SeamOrder = GSA1.SeamOrder or {}
table.insert(GSA1.SeamOrder, "sh_alpha")
]]
M.virtual["gsa1/feat/cl_alpha.lua"] = [[
table.insert(GSA1.SeamOrder, "cl_alpha")
GSA1.AddMenuPage(20, "seamtest_b", "Seam B", function(panel) panel:Help("the B page") end)
GSA1.AddMenuPage(10, "seamtest_a", "Seam A", function(panel) panel:CheckBox("Level", "gsa1_seamtest_level") end,
    { feature = "seamtest", version = 2, module = "0.7.0" })
GSA1.AddMenuPage(30, "seamtest_err", "Seam Err", function(panel) error("a broken page") end)
GSA1.AddMenuPage(5, "seamtest_ok", "Seam OK", function(panel) panel:Help("the OK page") end,
    { feature = "seamtest", version = 1, module = "0.7.0" })
]]
M.virtual["gsa1/feat/cl_broken.lua"] = [[
table.insert(GSA1.SeamOrder, "cl_broken")
error("a broken feature file")
]]
M.virtual["gsa1/feat/sv_alpha.lua"] = [[table.insert(GSA1.SeamOrder, "sv_alpha")]]
M.virtual["gsa1/feat/readme.txt"] = "not Lua"                                  -- not *.lua: not listed
M.virtual["gsa1/feat/xx_odd.lua"] = [[table.insert(GSA1.SeamOrder, "xx_odd")]]  -- not sh_ / cl_ / sv_: ignored

-- 1. the client: the module has "seamtest" version 1
GSA1 = nil
M.module({ features = { seamtest = 1 } })
CLIENT, SERVER = true, false
local ok_load, err_load = pcall(M.load, "autorun/gsa1_autorun.lua")
check(ok_load, "the autorun runs on the client%s", ok_load and "" or (": " .. tostring(err_load)))
if not ok_load then
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return false
end
local order = list(GSA1.SeamOrder)
local menu_i, first_feat = index_of(M.included, "gsa1/cl_menu.lua"), index_of(M.included, "gsa1/feat/sh_alpha.lua")
check(order == "sh_alpha sh_zeta cl_alpha cl_broken" and menu_i and first_feat and menu_i < first_feat,
    "client: the feature files after the built-in ones (cl_menu.lua is file %s, the first feature file %s), sh_ then cl_, "
    .. "alphabetically: %s; sv_ and xx_ files not run", tostring(menu_i), tostring(first_feat), order)
local errs = GSA1.FeatureFileErrors or {}
check(list(GSA1.FeatureFiles) == "sh_alpha.lua sh_zeta.lua cl_alpha.lua" and #errs == 1 and
    string.find(errs[1], "^cl_broken%.lua: .*a broken feature file") ~= nil and #M.reported == 1,
    "a feature file that fails is reported (%s) and the others load: %s", tostring(errs[1]), list(GSA1.FeatureFiles))

-- 2. GSA1.ConVar
local cv, sv = M.convars.gsa1_seamtest_level, M.convars.gsa1_seamtest_server
check(GSA1.SeamCv == cv and cv and cv.client and cv.save and cv:GetInt() == 3 and cv.lo == 0 and cv.hi == 10 and
    GSA1.SeamSv == sv and sv and not sv.client and sv.flags == FCVAR_ARCHIVE + FCVAR_REPLICATED and
    GSA1.CONVARS.gsa1_seamtest_level and GSA1.CONVARS.gsa1_seamtest_server.server,
    "GSA1.ConVar: a client setting (archived, 0..10, default %s) and a replicated, archived server setting (flags %s)",
    cv and cv:GetString() or "?", sv and tostring(sv.flags) or "?")
local bad = pcall(GSA1.ConVar, "seamtest_noprefix", 1, "x")
check(not bad, "GSA1.ConVar refuses a name without the gsa1_ prefix")

-- 3. GSA1.HasFeature and the features line
GSA1.LoadModule()
local h1, v1 = GSA1.HasFeature("seamtest")
local h2, v2 = GSA1.HasFeature("seamtest", 2)
local h3, v3 = GSA1.HasFeature("nothing")
check(h1 and v1 == 1 and not h2 and v2 == 1 and not h3 and v3 == nil,
    "GSA1.HasFeature: seamtest %s (version %s), seamtest 2 %s, nothing %s", tostring(h1), tostring(v1), tostring(h2),
    tostring(h3))
local fl = GSA1.FeatureLine()
check(string.find(fl, "features: seamtest 1; feature files: sh_alpha.lua sh_zeta.lua cl_alpha.lua (failed: cl_broken.lua",
    1, true) ~= nil, "the features line: %s", fl)

-- 4. the menu pages: after the built-in ones, by order; needs; a broken builder
M.run_hook("PopulateToolMenu")
local names = {}
for _, e in ipairs(M.menu) do names[#names + 1] = e.name end
local feat_ok = true
for i = 8, #M.menu do
    local e = M.menu[i]
    feat_ok = feat_ok and e.tab == "Options" and e.category == "G-SA1" and string.find(e.class, "^gsa1_feat_") ~= nil
end
check(#M.menu == 11 and table.concat(names, ", ", 8) == "Seam OK, Seam A, Seam B, Seam Err" and feat_ok and
    M.menu[7].name == "Disc and status", "Options -> G-SA1: %s", table.concat(names, ", "))
-- a recording stand-in for a DForm: every method call is kept; controls it returns accept anything
local function panel()
    local P = { calls = {} }
    local any = setmetatable({}, { __index = function(t) return function() return t end end })
    return setmetatable(P, { __index = function(t, k)
        return function(self, ...)
            t.calls[#t.calls + 1] = { k, ... }
            return any
        end
    end })
end
local function text_of(P)
    local out = {}
    for _, c in ipairs(P.calls) do out[#out + 1] = c[1] .. "(" .. tostring(c[2]) .. ")" end
    return table.concat(out, " ")
end
local pages = {}
for i = 8, #M.menu do
    local P = panel()
    M.menu[i].cpanel(P)
    pages[M.menu[i].name] = text_of(P)
end
check(string.find(pages["Seam OK"], "Help(the OK page)", 1, true) ~= nil, "a page whose feature is there: built (%s)",
    pages["Seam OK"])
check(string.find(pages["Seam A"], "needs G-SA1 module 0.7.0 or newer (its seamtest part): module 0.6.0 has version 1 "
    .. "of it, version 2 is needed", 1, true) ~= nil and not string.find(pages["Seam A"], "CheckBox", 1, true),
    "a page whose module part is too old says so instead of erroring: %s", pages["Seam A"])
check(string.find(pages["Seam B"], "ClearControls(nil) Help(the B page)", 1, true) ~= nil, "a page without needs: %s",
    pages["Seam B"])
GSA1.LogFlush()
local log = M.files["gsa1/log.txt"] or ""
check(string.find(pages["Seam Err"], "could not be built: ", 1, true) ~= nil and
    string.find(log, "error +menu page seamtest_err: .*a broken page") ~= nil,
    "a page whose builder fails shows the error and logs it (%s)", string.sub(pages["Seam Err"], 1, 120))
check(string.find(log, "module 0.6.0 (API 6, build mock build), libsa1 0.2.0; vector mode 1 (two scratch Vectors written "
    .. "in place); features: seamtest 1", 1, true) ~= nil, "the session log's header names the module, its vector mode and "
    .. "the features")

-- 5. the server: the shared and server files run, the shared and client ones are sent
GSA1 = nil
M.included, M.cslua = {}, {}
local real_include = include
include = function(rel) M.included[#M.included + 1] = rel end      -- record only: the server files need a server
CLIENT, SERVER = false, true
local ok_sv, err_sv = pcall(M.load, "autorun/gsa1_autorun.lua")
include = real_include
CLIENT, SERVER = true, false
local sent = list(M.cslua)
check(ok_sv and list(M.included) == "gsa1/sh_config.lua gsa1/sh_net.lua gsa1/sv_gsa1.lua gsa1/feat/sh_alpha.lua "
    .. "gsa1/feat/sh_zeta.lua gsa1/feat/sv_alpha.lua" and string.find(sent, "gsa1/cl_menu.lua gsa1/feat/sh_alpha.lua "
    .. "gsa1/feat/sh_zeta.lua gsa1/feat/cl_alpha.lua gsa1/feat/cl_broken.lua", 1, true) ~= nil and
    not string.find(sent, "sv_alpha", 1, true) and not string.find(sent, "xx_odd", 1, true),
    "server: runs %s; sends %d files (the feature files: sh_alpha sh_zeta cl_alpha cl_broken)%s", list(M.included),
    #M.cslua, ok_sv and "" or (": " .. tostring(err_sv)))

print(string.format("\n%d checks, %d failed", M.checks, M.fails))
return M.fails == 0
