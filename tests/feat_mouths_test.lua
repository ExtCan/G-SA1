-- feat_mouths_test.lua - "Your mouths", the shared data part (round 0.9.4e: sadc docs/research/lipsync2_plan.md 4.7 / 5.6 /
-- 6.2 with its review R.2 / R.4c / R.8; lipsync2_show.md 6.4 and 7): addon/lua/gsa1/feat/sh_mouths.lua in Garry's Mod's own
-- LuaJIT with tests/lua_mock.lua (only its check / info and globals; sh_mouths.lua is pure functions and data).
--   L1  the file round trip of lipsync2_show.md 7's example: header and "version<TAB>1" written; the characters' lines in
--       G-SA1's sorted normal form (the example's sonic line lists EE before AA.loud: written back sorted, then stable); an
--       unknown character, a bad version (and the lines under it) and CR LF lines kept and listed as bad, not applied, and
--       written back unchanged.
--   L2  no voice data: every line F.MouthSerializeFile writes is a header line, "version<TAB>1", a character line of the
--       grammar (written out below as a checker) or a kept line; a fuzz of 100 random maps (also with junk keys and junk
--       mouths in them) produces no other text.
--   L8  the lists F.MOUTH_CHOICES: every key below the kind's count (Sonic 21, Tails / Knuckles / Amy 20, Big 8); Big lists only
--       0, 4, 5 (and the voice / slit); descriptions 1-60 characters; tags talk / mouth / brows / head; every mouth already in
--       the grammar's normal form; review R.2: Sonic has G-SA1's quiet ah 7>16 30 %, Amy's 7>8 50 % is not G-SA1's and
--       0>8 80 % (scales) is G-SA1's eh.
--   L8b against build/x86_64-windows/faces_tables.txt (written by tests/feat_faces_binding_test.cpp from the module as built;
--       review R.4c: REQUIRED once src/module/bind_faces.cpp declares GSA1_FEATURE(faces, 3 - a missing or stale file then
--       fails; skipped with a message only before): each "G-SA1's <sound>" entry of the lists equals that kind's table row;
--       F.MouthSpec gives the module's normal form for its 40 seeded specs; (review R.8) F.MouthSpecParse /
--       F.MouthItemParse refuse exactly its 30 invalid specs and accept the 40.
--   lua_host tests/feat_mouths_test.lua <tests dir> <addon/lua dir>
local tests, root = arg[1] or "tests", arg[2] or "addon/lua"
local M = host_load(host_read(tests .. "/lua_mock.lua"), "lua_mock.lua")()
M.root = root
local check, info = M.check, M.info
print("G-SA1 feat_mouths_test (Garry's Mod's LuaJIT " .. tostring(jit and jit.version) .. ")")

local function done()
    print(string.format("\n%d checks, %d failed", M.checks, M.fails))
    return M.fails == 0
end

GSA1 = nil
M.load("gsa1/feat/sh_mouths.lua")
local F = GSA1 and GSA1.Faces
if not (F and F.MouthParseFile and F.MouthSerializeFile and F.MouthItemParse and F.MouthSpec and F.MOUTH_CHOICES) then
    check(false, "sh_mouths.lua loads and defines F.MouthParseFile / F.MouthSerializeFile / F.MouthItemParse / F.MouthSpec / "
        .. "F.MOUTH_CHOICES")
    return done()
end
check(F.NEEDS_MOUTHS.feature == "faces" and F.NEEDS_MOUTHS.version == 3 and F.MOUTH_FILE == "gsa1/mouth_shapes.txt" and
    F.MOUTH_KEYS[0] == 21 and F.MOUTH_KEYS[7] == 8 and #F.MOUTH_SOUNDS == 7 and F.MOUTH_CHARS.big == 7 and
    F.MOUTH_CHAR_OF[5] == "amy", "sh_mouths.lua's constants: NEEDS_MOUTHS faces 3, the file gsa1/mouth_shapes.txt, the key "
    .. "counts, the 7 sounds, the characters")

local function lines_of(text)
    local out = {}
    for l in string.gmatch(text, "([^\n]*)\n") do out[#out + 1] = l end
    return out
end

-- ---- L1 the file round trip ----------------------------------------------------------------------------------------------
do
    local example = F.MOUTH_FILE_HEADER .. "\nversion\t1\nsonic\tEE=0>17@0.8:scales,AA.loud=7>16@0.7\namy\tSS=0>5@0.6:scales\n"
    local map, bad = F.MouthParseFile(example)
    local text = F.MouthSerializeFile(map, bad)
    local map2, bad2 = F.MouthParseFile(text)
    local text2 = F.MouthSerializeFile(map2, bad2)
    local want = F.MOUTH_FILE_HEADER .. "\nversion\t1\nsonic\tAA.loud=7>16@0.7,EE=0>17@0.8:scales\namy\tSS=0>5@0.6:scales\n"
    local L = lines_of(text)
    check(#bad == 0 and map[0] and map[5] and map[0].items["EE"] == "0>17@0.8:scales" and map[0].items["AA.loud"] ==
        "7>16@0.7" and map[5].items["SS"] == "0>5@0.6:scales" and not map[2] and text == want and text2 == text and
        string.sub(L[1], 1, 18) == "# G-SA1 mouth shap" and L[11] == "version\t1",
        "L1 lipsync2_show.md 7's example: sonic (ah loud, ee) and amy (s) read; written back with the header, version 1 and "
        .. "the lines in G-SA1's sorted normal form (sonic AA.loud before EE); a second round trip is identical")
    -- kept lines: an unknown character, a bad key, CR LF, a bad version and the lines under it
    local messy = "version\t1\nsonic\tAA=7\nshadow\tAA=4\nbig\tAA=9\ntails\tOO=5\r\n# a comment\r\n\nknuckles\tEH=4\n"
        .. "version\t2\namy\tAA=8\n"
    local m, b = F.MouthParseFile(messy)
    local whys = {}
    for _, x in ipairs(b) do whys[#whys + 1] = x.line .. " " .. x.why end
    local out = F.MouthSerializeFile(m, b)
    local kept = 0
    for _, x in ipairs(b) do
        if string.find(out, x.text, 1, true) then kept = kept + 1 end
    end
    local m2, b2 = F.MouthParseFile(out)
    local same_map = m2[0] and m2[0].spec == "AA=7" and m2[3] and m2[3].spec == "EH=4" and not m2[7] and not m2[2] and
        not m2[5] and #b2 == #b
    check(m[0] and m[0].spec == "AA=7" and m[3] and m[3].spec == "EH=4" and not m[7] and not m[2] and not m[5] and #b == 5 and
        kept == 5 and same_map,
        "L1 kept and listed, never applied: %s; written back unchanged (%d of %d) and read the same again", table.concat(whys,
        "; "), kept, #b)
end

-- ---- L2 no voice data ----------------------------------------------------------------------------------------------------------
local SOUNDS = { AA = true, EH = true, EE = true, OH = true, OO = true, SS = true, FV = true }
local CHARS = { sonic = true, tails = true, knuckles = true, amy = true, big = true }
-- the grammar written out (mouth.hpp): the only text a character line may hold
local function item_ok(item)
    local lhs, mouth = string.match(item, "^([%u%.%l]+)=(.+)$")
    if not lhs then return false end
    local sound, variant = string.match(lhs, "^(%u%u)%.(%l+)$")
    if not sound then sound = string.match(lhs, "^(%u%u)$") end
    if not sound or not SOUNDS[sound] or (variant and variant ~= "quiet" and variant ~= "loud") then return false end
    if mouth == "ladder" or string.match(mouth, "^ladder@%d$") or string.match(mouth, "^ladder@%d%.%d%d?%d?%d?$") then
        return true
    end
    local body = string.gsub(mouth, ":scales$", "")
    local w = "%d%.?%d?%d?%d?%d?"
    return string.match(body, "^%d%d?$") ~= nil or string.match(body, "^%d%d?>%d%d?@" .. w .. "$") ~= nil
end
local header = {}
for _, l in ipairs(lines_of(F.MOUTH_FILE_HEADER .. "\n")) do header[l] = true end
local function file_ok(text, kept)
    for _, l in ipairs(lines_of(text)) do
        if not (header[l] or l == "version\t1" or (kept and kept[l])) then
            local name, spec = string.match(l, "^(%l+)\t(.+)$")
            if not name or not CHARS[name] then return false, l end
            for item in string.gmatch(spec .. ",", "([^,]*),") do
                if not item_ok(item) then return false, l end
            end
        end
    end
    return true
end
do
    local seed = 4242
    local function rnd(n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return math.floor(seed / 65536) % n
    end
    local junk = { "hello", "7>16@0.45\nmic 0.73", "AA=4", "-1", "0.5", "ladder@9", "4>99@0.5", "f1 712 f2 1240", "4:loud" }
    local good, bad_lines, all = 0, nil, 0
    for i = 1, 100 do
        local map = {}
        for _, kind in ipairs(F.MOUTH_CHAR_ORDER) do
            if rnd(3) > 0 then
                local items = {}
                for _, s in ipairs(F.MOUTH_SOUNDS) do
                    for _, v in ipairs(F.MOUTH_VARIANTS) do
                        if rnd(4) == 0 then
                            local key = v ~= "" and (s .. "." .. v) or s
                            local r = rnd(5)
                            local keys = F.MOUTH_KEYS[kind]
                            items[key] = r == 0 and tostring(rnd(keys)) or r == 1 and string.format("%d>%d@0.%d", rnd(keys),
                                rnd(keys), rnd(10000)) or r == 2 and "ladder@0." .. rnd(1000) or r == 3 and (rnd(keys) ..
                                ":scales") or junk[rnd(#junk) + 1]
                        end
                    end
                end
                if rnd(3) == 0 then items["XX"] = "4"; items["voice"] = 0.734 end    -- junk keys
                map[kind] = { items = items }
            end
        end
        if rnd(4) == 0 then map[6] = { items = { AA = "4" } } end                -- a kind without a face
        local text = F.MouthSerializeFile(map)
        local ok, l = file_ok(text)
        all = all + #lines_of(text)
        if ok then good = good + 1 elseif not bad_lines then bad_lines = l end
    end
    check(good == 100, "L2 every line of 100 random maps (junk keys and mouths, a kind without a face included) written by "
        .. "F.MouthSerializeFile is the header, \"version 1\" or a character line of the grammar (%d of 100 files, %d lines)%s",
        good, all, bad_lines and (": " .. bad_lines) or "")
end

-- ---- L8 the lists ---------------------------------------------------------------------------------------------------------------
do
    local n, keys_ok, desc_ok, tag_ok, norm_ok, big_ok = 0, 0, 0, 0, 0, true
    local first
    local TAGS = { talk = true, mouth = true, brows = true, head = true }
    for _, kind in ipairs(F.MOUTH_CHAR_ORDER) do
        local list = F.MOUTH_CHOICES[kind] or {}
        for _, e in ipairs(list) do
            n = n + 1
            local m = F.MouthNormal(e.mouth, kind)
            local kc = F.MOUTH_KEYS[kind]
            local a, b = string.match(e.mouth, "^(%d+)>(%d+)@")
            if not a then b = string.match(e.mouth, "^(%d+)") a = "0" end
            local ka, kb = tonumber(a), tonumber(b)
            local below = (e.mouth == "ladder" or string.sub(e.mouth, 1, 7) == "ladder@") or (ka and kb and ka < kc and kb < kc)
            keys_ok = keys_ok + (below and m ~= nil and 1 or 0)
            norm_ok = norm_ok + (m == e.mouth and 1 or 0)
            desc_ok = desc_ok + ((type(e.text) == "string" and #e.text >= 1 and #e.text <= 60) and 1 or 0)
            tag_ok = tag_ok + ((TAGS[e.tag] and (e.gsa1 == nil or string.match(e.gsa1, "^%u%u$") or
                string.match(e.gsa1, "^%u%u%.quiet$") or string.match(e.gsa1, "^%u%u%.loud$"))) and 1 or 0)
            if kind == 7 and not (string.sub(e.mouth, 1, 6) == "ladder" or (ka and kb and (ka == 0 or ka == 4 or ka == 5) and
                    (kb == 0 or kb == 4 or kb == 5))) then
                big_ok = false
            end
            if not (below and m == e.mouth) and not first then first = kind .. " " .. tostring(e.mouth) end
        end
    end
    local function find(kind, mouth)
        for _, e in ipairs(F.MOUTH_CHOICES[kind]) do if e.mouth == mouth then return e end end
    end
    local sq, a78, a08 = find(0, "7>16@0.3"), find(5, "7>8@0.5"), find(5, "0>8@0.8:scales")
    check(n > 80 and keys_ok == n and desc_ok == n and tag_ok == n and norm_ok == n and big_ok,
        "L8 the lists (%d entries): every key below the kind's count and every mouth in the grammar's normal form (%d, %d); "
        .. "descriptions 1-60 characters (%d); tags and G-SA1 marks well formed (%d); Big only 0, 4, 5 and the voice / slit%s",
        n, keys_ok, norm_ok, desc_ok, tag_ok, first and (" - first bad: " .. first) or "")
    check(sq and sq.gsa1 == "AA.quiet" and a78 and a78.gsa1 == nil and a08 and a08.gsa1 == "EH",
        "L8 review R.2: Sonic's list has G-SA1's quiet ah 7>16 30 %%; Amy's 7>8 50 %% is not G-SA1's, 0>8 80 %% (scales) is "
        .. "G-SA1's eh")
end

-- ---- L8b against the module's faces_tables.txt ------------------------------------------------------------------------------
do
    local gsa1root = string.gsub(tests, "[/\\]tests$", "")
    local text = host_read(gsa1root .. "/build/x86_64-windows/faces_tables.txt")
    local bind = host_read(gsa1root .. "/src/module/bind_faces.cpp") or ""
    local required = string.find(bind, "GSA1_FEATURE(faces, 3", 1, true) ~= nil
    if not required then
        info("L8b skipped: src/module/bind_faces.cpp does not declare GSA1_FEATURE(faces, 3 yet")
    elseif not text then
        check(false, "L8b build/x86_64-windows/faces_tables.txt is missing although bind_faces.cpp declares faces 3 (the binding "
            .. "test writes it before the Lua tests run)")
    else
        local function fields(l)
            local t = {}
            for f in string.gmatch(l .. "\t", "([^\t]*)\t") do t[#t + 1] = f end
            return t
        end
        local feature, rows, specs, bads = nil, {}, {}, {}
        for l in string.gmatch(text, "([^\n]*)\n") do
            local f = fields(l)
            if f[1] == "feature" then
                feature = f[3]
            elseif f[1] == "row" then
                rows[f[2] .. " " .. f[3] .. (f[4] ~= "normal" and ("." .. f[4]) or "")] = f[5]
            elseif f[1] == "spec" then
                specs[#specs + 1] = { kind = tonumber(f[2]), spec = f[3], normal = f[4] }
            elseif f[1] == "bad" then
                bads[#bads + 1] = { kind = tonumber(f[2]), spec = f[3], code = f[4], why = f[5] }
            end
        end
        -- each "G-SA1's" entry of the lists equals the module's row
        local tagged, same, diff = 0, 0, nil
        for _, kind in ipairs(F.MOUTH_CHAR_ORDER) do
            for _, e in ipairs(F.MOUTH_CHOICES[kind]) do
                if e.gsa1 then
                    tagged = tagged + 1
                    local want = rows[kind .. " " .. e.gsa1]
                    if want and want == F.MouthNormal(e.mouth, kind) then
                        same = same + 1
                    elseif not diff then
                        diff = string.format("%s %s: list %s, module %s", F.MOUTH_NAMES[kind], e.gsa1, e.mouth, tostring(want))
                    end
                end
            end
        end
        check(feature == "3" and tagged > 30 and same == tagged,
            "L8b faces_tables.txt (feature faces %s): each \"G-SA1's\" entry of the lists equals the module's table v2 row "
            .. "(%d of %d)%s", tostring(feature), same, tagged, diff and (" - " .. diff) or "")
        local sp_ok, sp_first = 0, nil
        for _, s in ipairs(specs) do
            local items = F.MouthSpecParse(s.spec, s.kind)
            local mine = items and F.MouthSpec(items, s.kind)
            if mine == s.normal then
                sp_ok = sp_ok + 1
            elseif not sp_first then
                sp_first = string.format("%d %s -> %s (module %s)", s.kind, s.spec, tostring(mine), s.normal)
            end
        end
        check(#specs == 40 and sp_ok == 40, "L8b F.MouthSpec gives the module's normal form for its %d seeded specs (%d)%s",
            #specs, sp_ok, sp_first and (" - first: " .. sp_first) or "")
        local refused, items_refused, acc = 0, 0, nil
        for _, b in ipairs(bads) do
            local ok, why = F.MouthSpecParse(b.spec, b.kind)
            if not ok then
                refused = refused + 1
            elseif not acc then
                acc = string.format("%d \"%s\" (module: %s)", b.kind, string.sub(b.spec, 1, 40), b.why)
            end
            -- a one-item spec: F.MouthItemParse refuses it too
            if not string.find(b.spec, ",", 1, true) and #b.spec <= 512 then
                items_refused = items_refused + ((F.MouthItemParse(b.spec, b.kind)) == nil and 1 or 0)
            else
                items_refused = items_refused + 1
            end
        end
        check(#bads == 30 and refused == 30 and items_refused == 30,
            "L8b review R.8: the 30 invalid specs the module refused are refused here too (F.MouthSpecParse %d, "
            .. "F.MouthItemParse on the one-item ones %d)%s", refused, items_refused, acc and (" - accepted: " .. acc) or "")
    end
end

check(#M.reported == 0, "no Lua error reported (%s)", tostring(M.reported[1]))
return done()
