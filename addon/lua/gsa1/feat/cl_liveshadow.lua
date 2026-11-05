-- G-SA1 feature "liveshadow": the characters' SUN SHADOW, drawn by G-SA1 (round 0.9.5; sadc docs/research/gsa1_095_plan.md
-- 4.17 with its review R.7, gsa1_090_render.md 5.2 S2 with its review; the owner's binding answer 14.1ad 5 and their explicit
-- note: "The G-SA1 drawn sun shadow should be toggleable"). Garry's Mod shadows the props on a map from the map's sun, but
-- not a G-SA1 character (its meshes are not a model: no render-to-texture shadow); this draws one like a prop's, and the
-- game's own round shadow (gsa1_shadow, cl_render.lua) stays as it is. Nothing here changes game logic.
--   * THE LIGHT, once per map, from the map file's entity lump (file.Open("maps/<map>.bsp", "rb", "GAME") as cl_module.lua
--     reads a workshop map): the header (ident "VBSP", the lump directory) and lump 0 only - an LZMA-compressed lump or one
--     above S.LUMP_MAX (8 MB) is refused -, read in slices of at most S.SLICE (256 KB) per frame and parsed S.PARSE_BLOCKS
--     entity blocks per frame, from a Think coroutine. shadow_control's angles / color / distance / disableallshadows, else
--     light_environment's direction, else straight down. The conventions differ (review R.7, measured on the owner's maps):
--     shadow_control's "angles" are Source angles, dir = Angle(p, y, r):Forward() (gm_construct "90 0 0": straight down);
--     light_environment's "pitch" is NEGATIVE downward (Garry's Mod's bin/base.fgd: "0 is horizontal, -90 is straight down"),
--     the pitch key when not 0, else the angles' pitch in the same convention: dir = Angle(-pitch, yaw, 0):Forward(). A
--     direction within 10 degrees of horizontal or pointing up (shadow_control "0 0 0" of gm_highway14800 / rp_nycity,
--     light_environment pitch 0 of gm_goldencity_v2) is not used: the next source, logged. Several entities of a class: the
--     first one (the count logged). A key the entity leaves out: bin/base.fgd's default of shadow_control (angles "80 30 0",
--     color "128 128 128", distance 75, disableallshadows 0); with no shadow_control the colour and distance are those
--     defaults too. One log line per map (it also says when the map has no sky_camera: a 2D sky). A map whose shadow_control
--     changes at run time keeps its first values.
--   * THE SILHOUETTE, in every frame (0.9.5b; the owner: "it runs at a lower frame rate to the rest of the game"), or at
--     most gsa1_sunshadow_rate times a second when that is above 0, in a frame whose main view took the character (see THE MAIN
--     VIEW; third person; first person only with gsa1_sunshadow_fp) and the map does not disable shadows: made in the
--     PostRender hook, OUTSIDE EVERY VIEW (0.9.5a, see below): cl_render.lua's GSA1.DrawCharacterView with an
--     orthographic box along the light around the drawn root (the eye S.box x 2 back along the light, the box S.box from
--     the character's height) into a 256 x 256 render target (its own depth, cl_textures.lua's probed format), white on
--     black: one flat white UnlitGeneric for every batch drawn (colour modulation 1, fog off, the tone-mapping scale 1, all
--     restored), only the opaque body and board batches (no effects, no game objects, no blob shadow); then
--     render.BlurRenderTarget once, before the target is popped. The first picture shows from the frame after it, so the picture on screen is 1 frame
--     old (older with gsa1_sunshadow_rate above 0). Only its pose lags, not its place: see below.
--   * THE RECEIVERS: a 9 x 9 grid over the silhouette's footprint, each point traced along the light (util.TraceLine,
--     MASK_SOLID: props count; the local player filtered) at most the light's distance past the character's feet; the hit
--     points (in the world: they stay on the ground between two grids, also on slopes and stairs) as a grid of quads drawn
--     right after the main view's opaque renderables (PostDrawOpaqueRenderables, the screen only; no render target, clear,
--     blur or cam.Start there) with a decal material sampling the render target, blended ZERO / ONE_MINUS_SRC_COLOR - dst x
--     (1 - mask x (1 - colour / 255) x fade), the blob's mask path - with gsa1_sunshadow_dark > 0 the darkness instead of
--     the colour, fading from 1 at the feet to 0 at the light's distance; the tone-mapping scale 1 and restored
--     (cl_render.lua's mask path). A cell with a corner not hit, or whose corners lie more than S.STEP_DEPTH apart along the
--     light (a ledge), is left out. Every frame the picture's texture coordinates and the fade come from the drawn root of
--     THAT frame, so the shadow stays with the character whatever the age of the picture and the grid. The grid is traced
--     in the same hook, right before the quads (util.TraceLine changes no render state; 0.9.5 traced in this hook too), when
--     the root moved S.RETRACE_MOVE or S.RETRACE_EVERY passed: the quads never lie more than S.RETRACE_MOVE behind the
--     character, the grid's half size is 48 HU. A grid of an earlier frame's end would lie 1 to 3 frames behind: at 1000
--     HU/s and more the picture left the quads in some frames, a flash at 20 to 30 Hz. So a standing character traces 4
--     grids a second, one faster than S.RETRACE_MOVE a frame (about 480 HU/s at 60 fps) 81 traces every frame. Reused
--     tables and Vectors: no Lua garbage per frame of its own (what the engine's calls return aside - the owner's 0.9.5 log
--     had up to 6.8 KB a frame in this feature's hook at up to 30 grids a second, so about twice that now at speed:
--     UNVERIFIED that it is util.TraceLine's).
--     The quads are tested against the depth buffer like any world surface, no depth bias: on displacements a quad between
--     four hit points lies more than S.LIFT under the surface for 0.34 % (gm_snowrider_day_v3) / 0.36 % (gm_highway14800)
--     of the sampled points (0.21 % at their logged ground positions on gm_snowrider_day_v3, nearly all of them on a
--     displacement; only at creases; measured from the maps' displacement lumps), and a bias would show the shadow through
--     near walls (SADC/build/research/fix095a/diagnosis.md section 4). That measures the collision surface the traces hit
--     against itself: that the drawn surface is the same mesh is an assumption, UNVERIFIED on this machine; if it fails, no
--     shadow shows on such ground with no reason in the log.
--   * THE MAIN VIEW (0.9.5a; the owner's session on gm_snowrider_day_v3: "not seeing any sun shadows"): a call of
--     PostDrawOpaqueRenderables(isDrawingDepth, isDrawSkybox, isDraw3DSkybox) without depth, not the 3D skybox, with the
--     screen bound. isDrawSkybox alone does not exclude a view: on a map with a 2D sky it can be true in every call, the
--     main view's too (Garry's Mod wiki, the hook's page), and 0.9.5 returned on it - nothing was ever drawn on a map with
--     no sky_camera. Only on a map with a sky_camera (or whose entities could not be read), where the main view comes with
--     it false, a call with isDrawSkybox but not isDraw3DSkybox also asks render.GetViewSetup(true).viewid: VIEW_3DSKY or
--     no answer is not the main view.
--   * WHY THE RENDER TARGET WORK LEFT THE VIEW (0.9.5a; the owner's session on gm_highway14800: "the sun shadow is
--     flashing", "makes all G-SA1 effects flash", "distant models flash rapidly"): 0.9.5 made the silhouette inside the
--     main view, right after the opaque renderables, so everything drawn later in a frame with a refresh - the translucent
--     pass - came after a render target, a clear, an orthographic cam.Start and a blur, and in a frame without one it did
--     not: about 30 times a second. cam.Start3D takes what it leaves out from the last render operation (wiki), and
--     cl_render.lua's camera-relative draw of the blended batches passes only an eye and angles.
--   * WHY THE BLUR IS INSIDE THE PAIR (0.9.9a; the owner: "screenshots are completely black", then with the sun shadow off: "The sun
--     shadows were the cause"; every .tga of theirs is black with it on, normal with it off): 0.9.5b to 0.9.9 blurred after
--     render.PopRenderTarget. render.BlurRenderTarget is Lua, garrysmod/lua/includes/extensions/client/render.lua:84-103, and it ends with
--     render.SetRenderTarget(rt): this picture's target stayed bound at every frame's end (halo.lua:102-105 sets the scene's target again
--     right after it; bloom.lua:38-45 has it inside a push and a pop, as here). So the pop comes after the blur and is the picture's last
--     target call: it restores the target and the viewport whatever the blur left, also when the blur fails. That a screenshot reads what
--     is bound at the frame's end, so that this is the exact step, is UNVERIFIED here: only a screenshot in the game can show it.
--   * NOT DRAWN, WHY: PostRender looks at every frame (no garbage: constant strings); a frame without quads has a reason
--     (S.WHY) and one that lasts S.WHY_AFTER (5 s) goes into the session log, "sun shadow: not drawn for 5 s: <reason>", at
--     most once per reason per map ("no character" only on the page); GSA1.SunShadowLine shows it from S.WHY_SHOW (1 s).
--   * OFF (gsa1_sunshadow 0): its hooks are removed - nothing drawn, computed or read; the game's blob untouched. Skipped
--     also with no character, in first person without gsa1_sunshadow_fp, with disableallshadows 1, when the character is
--     not drawn this frame; nothing of a character is drawn with a picture of another one (a new character: from the frame
--     after its first picture). An error: one log line, the sun shadow stops for this session (the page says so).
--   * Cost: the hitch section "SunShadow" and the perf line's "sun shadow N ms per frame" (cl_log.lua), both hooks' time;
--     S.stats.
--   * THE FOLLOWERS (0.9.9a; the owner's note on 0.9.9: "Followers don't have sun shadows"; the owner's word on the method above: "The
--     shadows work perfectly"): the same method, nothing of your character's shadow changed. gsa1_sunshadow_followers (default 3, 0..8)
--     says how many: the nearest of cl_follower.lua's list by distance (Fo.order, 10 times a second, never a held one) that are in full
--     detail (level 1): the far levels and a held one have none, at once, and the place goes to the next one within S.CHOOSE_EVERY. One
--     that fell behind keeps its place until another is clearly nearer (S.CHOOSE_NEARER), so two about as near do not swap to and fro.
--     Each place has a target of its own from a pool that only grows (a target is made when its place first draws), not cells of one
--     target: the same calls as your character's, which the owner has seen working, no texture coordinates running into a neighbour
--     (SADC/build/research/r099a/misc/diagnosis.md section 1). Its picture is S.FOLLOWER_RT 128 x 128 with NO BLUR, on purpose: the
--     texture's own filter over the larger texel softens its edges, a little less than your blur does. render.BlurRenderTarget sets the
--     $basetexture of one shared material (render.lua:86) and the draws that read it may run later on the render thread when
--     mat_queue_mode -1 means the threaded queue (UNVERIFIED): a second target's blur in a frame could make every blur of that frame read
--     the last target, and your character's shadow would show a follower's pose. What is shared: the light,
--     its axes, the view's table, the flat white, one tone-mapping scale around all their quads. Cheaper than yours in the part the
--     ground costs: S.FOLLOWER_GRID 7 x 7 (the ledge rule scaled with the cell, so the same slopes and the same lowest sun count); at most
--     S.PICTURES_PER_FRAME pictures a frame, by turns above that, so 8 followers get one every other frame; gsa1_sunshadow_rate holds
--     for them too. First person is about your character (GSA1.FirstPersonFor): a follower stays whole there, and so does its shadow. Their
--     time is the hitch section "FollowerShadow" (the perf line's "sun shadow" stays yours), the page's line has it too; an error in their
--     part stops only them.
--   * ONLY WHERE THE SUN REACHES (0.9.9c, gsa1_sunshadow_sunlit, default 1; the owner's note: "Sun Shadows appear in Shadowed areas when they
--     should only be in bright spots". A prop's shadow in Garry's Mod has the same fault: a projected shadow asks nothing about the sun).
--     WHAT DECIDES THE SHADE: the map's baked light, and VRAD bakes the sun from the FIRST light_environment alone, in its direction, not
--     shadow_control's (READ, source-sdk-2013 utils/vrad/lightmap.cpp ParseLightEnvironment, GatherSampleSkyLightSSE; trace.cpp): a ray from the
--     luxel towards the sun reaches a sky face, or it is blocked by a world brush of MASK_OPAQUE (nodraw sides too, windows and water not); a
--     ray that hits nothing counts as seen; a surface turned away from the sun gets none. So the check asks towards light_environment even when
--     the shadow itself falls along shadow_control: on gm_construct_remaster_csm the shadow falls straight down and the sun comes from pitch
--     -50, yaw 34 (MEASURED: the map's light lumps hold that normal; SADC/build/research/r099c/fix/notes.txt and fix2/notes.txt have the numbers below).
--     HOW IT ASKS: a lattice of ground samples fixed in the world (S.SUN_CELL, shared by your character and every follower): each corner asks one
--     trace towards the sun, MASK_OPAQUE, from its ground, the plane of the point of a grid that first needs it, the answer kept S.SUN_KEEP s. That plane comes through the point's own normal, the HitNormal of
--     its grid trace: a normal made from the grid's neighbours can lean over a ledge (099c's verifier: on the sunny top of a ledge the shadow faded away after 4 s). A corner says only whether the sun gets to
--     that place. A ray stopped within S.SUN_STEP of height above its start gets a second ray from that much higher; if that one gets there, the blocker was a low step and the corner counts as sun: the narrow shade
--     of a curb or a stair's riser is no reason to fade a whole cell of the lattice (099c's second verifier: a corner on the foot of a step did). Taller things, walls, roofs: shade, as ever. WHAT THAT COSTS: the shade of
--     a step up to 26 HU high, or up to 44 where the ray went furthest before it stopped, is not drawn: a shadow lies on it, as in 0.9.9b; a ray or two on stairs. MEASURED: second rays are 0.2-0.7 % of the corners on four of
--     the five maps below, and they change the agreement with the map's light by 0.03 points or less on those four (gm_snowrider_day_v3: 5.9 %, 72.7 to 71.2, 3 of its 198 samples).
--     Whether a surface faces the sun is the point's own. A point that faces it asks its corners. A point turned from it asks nothing, so the side of a step never answers for its top; what it reads goes by how wide its
--     surface is as the grid sees it (sun_broad: from its plane and where that meets its neighbours' planes, not from how many rows lie on it now, so it does not change as the rows move): S.SUN_WIDE cells or more: none, as
--     VRAD gives it; a cell or less, a sliver such as a riser under a steep light: what the points around it that face the sun read, so a row of the grid falling on a riser makes no notch (099c's second verifier: on
--     a map whose shadow is slanted another way than the sun, in full sun, a fixed place changed by 0.943 of the shadow in a frame on stairs, 0.720 on a curb; now about what the box off gives, 0.01-0.03, MEASURED,
--     tests/feat_sunlit_test.lua section 5d); between, in proportion. Under S.SUN_FACING broad ground fades towards none, as a baked surface does; a sliver keeps what its corners say. WHAT THAT COSTS: no ray, and a surface
--     turned from the sun no wider than a cell (12 HU of your grid, 16 of a follower's) gets the shadow, as in 0.9.9b. A point of a shadow's grid takes the bilinear mean of its four corners, counting only those on its own surface (S.SUN_SAME), so the fade is a
--     property of the place: it does not swim with the grid, a walk across a shade line on even ground changes nothing suddenly (where a shade line crosses steps it can: each tread reads different corners, 0.6-0.98 of the shadow in a frame on stairs and curbs at such a line, MEASURED by 099c's third verifier, rare, no worse than before its fix), and a shadow half in the sun
--     keeps its sunny part at full strength and fades out over one cell on the shaded side. Only the ground under the shadow is asked, never the
--     character. A corner asked again with another answer (a roof that moved: S.SUN_KEEP) goes over in S.SUN_FADE s; in time too the value belongs to the
--     place, not to a point of the moving grid (a fade on the grid's points made a fixed spot of the ground swing by a quarter of the shadow while walking,
--     MEASURED in the test). One place where the moving grid does show: a crease in the ground whose far side is broad and turned from the sun has its line at the nearest grid points, as the shadow's cells have: right beside it
--     a fixed place changes by up to 0.53 of the shadow in a frame under the character, by up to 0.99 where the grid's outer rows pass over it (a row there alone on such ground reads what is around it, until the next row joins it), further than a cell from it by 0.000.
--     A band of 16 HU turned from the sun, by turns one row or two: 0.59 at most, 0.15 by 20 HU, none from 32 (MEASURED, SADC/build/research/r099c/fix2/crease_after.txt). That the outer rows hold no picture of a character is READ from the box's size, UNVERIFIED by eye.
--     WHAT IS NOT ANSWERED YET: traces a frame are bounded (S.SUN_YOU, S.SUN_THEM corners), a corner not traced yet does not count and is asked the next frame. A point with no answer at all keeps its value while
--     the shadow stays about where that was asked; a new shadow, or one that jumped S.SUN_JUMP, starts from nothing: what is not known yet is not drawn. So a shadow arriving in the shade is never lit for a
--     frame (099c's verifier: 1-3 frames at full darkness, with several followers, a teleport, a tall character); one arriving in the sun can come a frame or a few late. A KNOWN LIMIT: at very high speed the budget runs out and
--     a shadow's values start from nothing each frame, so in open sun vertices fall short of full: on flat ground none up to 5000 HU/s at 60 fps with 1 + 3 or 1 + 8 (on a slope or stairs a grid spans more of the lattice: from 3000-3600 HU/s at 60 fps and 1500-2000 at 30 fps for the followers' shadows, your own from 2500-3600 at 30 fps, MEASURED by 099c's third verifier); 1 + 8 at 6000: 19 of 150 frames; at 8000: all, and 1 + 3 100 of 150; lower
--     speeds at lower frame rates, 1 + 8 at 3000 HU/s and 30 fps 9 of 75, at 2500 HU/s and 20 fps all, 1 + 3 2 of 50 (MEASURED, 099c's second verifier, re-run the same on this code). The highest speed in a log searched is 3602 HU/s, at about 57 fps.
--     MEASURED on five of the owner's maps (all ground within 400 HU of where the logs have them, indoor floors too; rays through world brushes and displacements, no props), % agreeing with the map's own
--     light: the ray on gm_construct_remaster_csm, gm_construct, gm_construct_in_flatgrass_v3 99.0, 99.2, 97.7, on gm_c17map 97.7 and gm_snowrider_day_v3 73.7 (those two with a proxy for the truth); always
--     drawing 31.7, 31.8, 55.7, 54.7, 67.2; along shadow_control 73.4, 81.3, 87.6, 97.7 (the same direction there); the lattice as built 99.1, 98.75, 97.6, 96.15, 71.2, so it loses up to 1.6 points of the ray's on the first
--     four, 2.5 on the fifth, whose 198 samples move half a point each. Cells of 24, 32 and 48 HU differ by little on the same samples; the 12 and 16 HU rows were run on a quarter of them only (1970 of 7830 on the first map).
--     099c's verifier counted more luxels, those in the corners of a lightmap's rectangle outside the face's polygon too, which agree only 72-78 % (099c's second verifier, MEASURED on two maps; the height a ray starts from
--     changes nothing, 1 or 8 HU): by that count the ray 92.8, 92.1, 91.0, 88.6, 80.4, always drawing 33.8, 31.4, 43.7, 46.6, 70.7. For ground that exists the first numbers are the fairer ones.
--     WHAT IT GETS WRONG, and which way: a tree's leaves or a prop with no collision (a trace goes through them; if the map baked their shade,
--     drawn in shade); a func_brush overhead (it stops a trace, the map baked no shade: not drawn in light). A physics prop overhead should not stop it: Source's filter skips a non-brush model unless the mask
--     has CONTENTS_MONSTER, and MASK_OPAQUE has none (READ source-sdk-2013 util_shared.cpp StandardFilterRules; UNVERIFIED that Garry's Mod's filter follows it); for the same reason the ray needs no player
--     filter. A sun that another addon or the map turned off at run time, Real CSM's among them (a trace cannot know: the ground it finds "lit" stays so, drawn on ground that
--     is now dark, and Real CSM's lamps may come from env_sun's direction, not light_environment's). A window: lit through it, as baked. Water: as
--     baked, it stops nothing. A map with no light_environment, or none usable (no light, within 10 degrees of horizontal, its entities unreadable):
--     not asked, drawn everywhere as 0.9.9b, since there is no sun to fall back on and every prop's shadow is drawn there too. A map with a
--     light_environment and no sky over this ground, an indoor one: shade, not drawn: VRAD lit none of it either. A corner with no answer does not count; a point whose own ray starts in solid: drawn.
--     So what cannot be known falls on the side of 0.9.9b's shadow.
--     COST, A STATED LIMIT, ON BY DEFAULT: own Lua 0.0 bytes a frame, on and off (MEASURED, tests/feat_sunlit_test.lua section 6). Each ray's result is engine objects the harness cannot weigh, as each grid trace's: on top of the
--     grid's 81 + 49 a follower, at 1500 HU/s 3.9 to 5.3 rays a frame for your shadow on flat ground, 12.7 to 15 up stairs (their height bands ask more corners; second rays 0 to 0.35 of that), 35 to 46 for 1 + 8; standing about 0.1 a
--     frame per shadow. Their weight in bytes is UNVERIFIED. So the check does add engine garbage per frame, a little; a ray is the only question that names a direction. To be rid of it: untick "Sun shadow only where the sun reaches".
--     Off (0): none of this runs, exactly 0.9.9b's drawing and traces.
--     THE OTHER WAYS (SADC/build/research/r099c/fix/notes.txt): render.ComputeLighting / GetLightColor read the leaf's few stored samples, by the wiki "ambient and dynamic", and need a threshold no map states; even the
--     best one for each map agrees less than the ray (80-87 %, UNVERIFIED that the formula is the engine's) and they cannot tell a lamp from the sun. The map's lightmap itself is right on 98.7-99.8 % with a threshold, but
--     Lua has no call that reads it (render.GetSurfaceColor by the wiki is a surface's colour, UNVERIFIED whether lit), and reading it from the file means the map's tree in the Lua heap, which the stutter study says not to
--     grow. The log therefore gets a few samples of those calls next to the ray's answer, at most S.PROBE_EACH each way per map, for the next round: "sun check sample".
-- Q menu > Options > G-SA1 > Rendering: the switches, the followers' slider and a status line (GSA1.SunShadowLine).
GSA1 = GSA1 or {}
local S = GSA1.SunShadow
if not (S and S.cv and S.cv.on) then error("gsa1/feat/sh_liveshadow.lua did not load: the sun shadow needs it") end
local cv = S.cv
local band = bit.band

S.RT_SIZE, S.GRID, S.BLUR = 256, 9, 2
S.SLICE, S.LUMP_MAX, S.PARSE_BLOCKS = 256 * 1024, 8 * 1024 * 1024, 400
S.RETRACE_MOVE, S.RETRACE_EVERY = 8, 0.25    -- the grid again: HU the root moved (x + y + z) / s passed
S.MIN_DOWN = math.sin(math.rad(10)) -- a direction within 10 degrees of horizontal (or up) is not used
S.STEP_DEPTH = 24                   -- HU along the light: a cell spanning more is a ledge, left out (so is a cell on ground
                                    -- falling away from the sun steeper than its height minus 26.6 degrees, or under a sun
                                    -- below 26.6 degrees: 12 / tan(the difference) HU. For 0.9.8: diagnosis.md section 8)
S.LIFT = 0.5                        -- HU: the receiver quads lie this much towards the light
S.BOX_MIN = 48                      -- HU: the silhouette box's half size, at least
S.DEFAULT = { angles = { 80, 30, 0 }, color = { 128, 128, 128 }, distance = 75, disable = 0 }  -- bin/base.fgd shadow_control
S.WHY_AFTER, S.WHY_SHOW = 5, 1      -- s: a reason not to draw goes into the session log / onto the page after this long
-- why a frame has no quads (constant strings: nothing made per frame)
S.WHY = {
    reading = "the map's sun is still being read",
    disabled = "this map turns shadows off (disableallshadows 1)",
    nochar = "no character",
    firstperson = "first person (\"Sun shadow in first person too\" is off)",
    nohook = "Garry's Mod did not call G-SA1's hook after the opaque renderables (another addon's hook may have answered "
        .. "first)",
    depth = "only depth views reached the hook, no main view",
    sky = "only the 3D skybox's view reached the hook, no main view",
    target = "only views into a render target reached the hook, not the screen",
    notdrawn = "the character was not drawn this frame",
    nopicture = "no silhouette yet",
    nopost = "G-SA1's hook at the frame's end was not called, so no silhouette is made (another addon's PostRender hook may "
        .. "have answered first)",
    noground = "no ground under the character that the shadow can lie on, within the light's distance (or ground falling "
        .. "away from the sun too steeply: its cells count as ledges)",
    shade = "the ground under the character is in the shade (\"Sun shadow only where the sun reaches\" is on)",
}
local WHY = S.WHY
local HOOK = "gsa1_sunshadow"
local VIEW_3DSKY = 1                -- Source's view id of the 3D skybox
local DRAW_EFFECT, DRAW_SHADOW, DRAW_OBJECT, DRAW_BOARD = 0x40, 0x800, 0x1000, 0x4000
local B_ZERO, B_ONE_MINUS_SRC_COLOR, B_FUNC_ADD = 0, 10, 0
local MASK = MASK_SOLID or 33570827
local log = function(fmt, ...) if GSA1.Log then GSA1.Log("sunshadow", fmt, ...) end end

-- ---- the light ---------------------------------------------------------------------------------------------------------
-- a little-endian int32 at byte i of s
local function le32(s, i)
    local a, b, c, d = string.byte(s, i, i + 3)
    if not d then return nil end
    local v = a + b * 256 + c * 65536 + d * 16777216
    if v >= 2147483648 then v = v - 4294967296 end
    return v
end
S.LE32 = le32
S.HEADER_BYTES = 8 + 64 * 16 + 4

-- the BSP header: { version, ofs, len, fourcc } of lump 0 (fourcc not 0: LZMA-compressed, its uncompressed size), or nil, why
function S.ParseHeader(h)
    if type(h) ~= "string" or #h < 24 then return nil, "the map's file is too short" end
    if string.sub(h, 1, 4) ~= "VBSP" then return nil, "not a Source map (no VBSP header)" end
    return { version = le32(h, 5), ofs = le32(h, 9), len = le32(h, 13), fourcc = le32(h, 21) }
end

-- "p y r" -> { numbers } (nil when there is none)
local function numbers(s)
    if type(s) ~= "string" then return nil end
    local t = {}
    for w in string.gmatch(s, "%S+") do
        local n = tonumber(w)
        if n then t[#t + 1] = n end
    end
    return #t > 0 and t or nil
end
S.Numbers = numbers

-- the keyvalues of one entity block (keys in lower case; the first of a key wins)
local function keyvalues(block)
    local kv = {}
    for k, v in string.gmatch(block, '"([^"]*)"%s*"([^"]*)"') do
        k = string.lower(k)
        if kv[k] == nil then kv[k] = v end
    end
    return kv
end
S.KeyValues = keyvalues

-- the sun's entities in an entity lump's text: { shadow_control = { n, kv (the first) }, light_environment = { n, kv } },
-- and sky_camera = { n, kv } (a 3D skybox: THE MAIN VIEW at the top); step() is called every S.PARSE_BLOCKS blocks (the
-- coroutine's yield)
function S.ParseEntities(text, step)
    local found = { shadow_control = { n = 0 }, light_environment = { n = 0 }, sky_camera = { n = 0 } }
    local i = 0
    for block in string.gmatch(text, "{([^{}]*)}") do
        i = i + 1
        if step and i % S.PARSE_BLOCKS == 0 then step() end
        if string.find(block, "shadow_control", 1, true) or string.find(block, "light_environment", 1, true) or
           string.find(block, "sky_camera", 1, true) then
            local kv = keyvalues(block)
            local f = found[string.lower(kv.classname or "")]
            if f then
                f.n = f.n + 1
                if f.n == 1 then f.kv = kv end
            end
        end
    end
    -- (0.9.9c: VRAD aims a light with a "target" at that entity; only the first light_environment's, once)
    local le = found.light_environment.kv
    local target = le and le.target
    if target and target ~= "" then
        for block in string.gmatch(text, "{([^{}]*)}") do
            if string.find(block, target, 1, true) then
                local kv = keyvalues(block)
                if kv.targetname == target then
                    found.light_environment.targetOrigin = numbers(kv.origin)
                    break
                end
            end
        end
    end
    return found
end

-- Source's AngleVectors forward of (pitch, yaw) - Angle(p, y, r):Forward(); the roll does not change it
local function forward(p, y)
    local rp, ry = math.rad(p), math.rad(y)
    return math.cos(rp) * math.cos(ry), math.cos(rp) * math.sin(ry), -math.sin(rp)
end
S.Forward = forward

local function fmt3(t)
    return string.format("(%s, %s, %s)", tostring(t[1] or 0), tostring(t[2] or 0), tostring(t[3] or 0))
end

-- 0.9.9c: the baked sun of the found entities, the one that decides the map's shade: { known = true, dx, dy, dz (unit, the way its light
-- travels), text } or { known = false, why, text }. VRAD's rules (the top of this file): the first light_environment; a "target", else the
-- "angle" key (-1 up, -2 down) or the angles' yaw, the "pitch" key or the angles' pitch; a pitch is negative downward
function S.SunOf(found, why)
    local le = found and found.light_environment
    local kv = le and le.n > 0 and le.kv or nil
    if not kv then
        local w = why or "the map has no light_environment"
        return { known = false, why = w, text = "not asked here, drawn everywhere: " .. w }
    end
    local function none(w) return { known = false, why = w, text = "not asked here, drawn everywhere: " .. w } end
    local c = numbers(kv._light)
    if c and ((c[1] or 0) <= 0 and (c[2] or 0) <= 0 and (c[3] or 0) <= 0 or (c[4] and c[4] <= 0)) then
        return none("the map's light_environment gives no light")
    end
    local a = numbers(kv.angles) or { 0, 0, 0 }
    local pitch = tonumber(kv.pitch) or 0
    if pitch == 0 then pitch = a[1] or 0 end
    local angle = tonumber(kv.angle) or 0
    local x, y, z
    local o, t = numbers(kv.origin), le.targetOrigin
    if t and o and #t >= 3 and #o >= 3 then
        local ex, ey, ez = t[1] - o[1], t[2] - o[2], t[3] - o[3]
        local n = math.sqrt(ex * ex + ey * ey + ez * ez)
        if n <= 0 then return none("the map's light_environment points at itself") end
        x, y, z = ex / n, ey / n, ez / n
    elseif angle == -1 then
        x, y, z = 0, 0, 1
    elseif angle == -2 then
        x, y, z = 0, 0, -1
    else
        x, y, z = forward(-pitch, angle ~= 0 and angle or (a[2] or 0))
    end
    if z > -S.MIN_DOWN then
        return none(string.format("the map's light_environment (pitch %s) points within 10 degrees of horizontal or up", tostring(pitch)))
    end
    return { known = true, dx = x, dy = y, dz = z, text = string.format("asked towards the map's baked sun, light_environment pitch %s, yaw %s",
        tostring(pitch), tostring(angle ~= 0 and angle or (a[2] or 0))) }
end

-- the light of the found entities: { source = "shadow_control" | "light_environment" | "down", dx, dy, dz (unit, the
-- direction the light travels), color = { r, g, b }, distance, disabled, sky3d (false: the map has no sky_camera; true also
-- when its entities could not be read), sun (S.SunOf), text }
function S.LightOf(found, why)
    local D = S.DEFAULT
    local L = { source = "down", dx = 0, dy = 0, dz = -1, color = { D.color[1], D.color[2], D.color[3] },
                distance = D.distance, disabled = false }
    local sc = found and found.shadow_control
    local le = found and found.light_environment
    local sky = found and found.sky_camera
    L.sky3d = not sky or sky.n > 0
    L.sun = S.SunOf(found, why)
    local notes = {}
    local sckv = sc and sc.n > 0 and sc.kv or nil
    if sckv then
        local c = numbers(sckv.color)
        if c and #c >= 3 then L.color = { c[1], c[2], c[3] } end
        L.distance = tonumber(sckv.distance) or D.distance
        L.disabled = (tonumber(sckv.disableallshadows) or D.disable) ~= 0
    end
    local dirText
    if sckv then
        local a = numbers(sckv.angles) or D.angles
        local x, y, z = forward(a[1] or 0, a[2] or 0)
        if z <= -S.MIN_DOWN then
            L.source, L.dx, L.dy, L.dz = "shadow_control", x, y, z
            dirText = "shadow_control angles " .. fmt3(a)
        else
            notes[#notes + 1] = "shadow_control angles " .. fmt3(a) .. " point within 10 degrees of horizontal or up: "
                .. "not used"
        end
        if sc.n > 1 then notes[#notes + 1] = string.format("the first of %d shadow_control", sc.n) end
    end
    local lekv = le and le.n > 0 and le.kv or nil
    if L.source == "down" and lekv then
        local a = numbers(lekv.angles) or { 0, 0, 0 }
        local pitch = tonumber(lekv.pitch) or 0
        if pitch == 0 then pitch = a[1] or 0 end
        local x, y, z = forward(-pitch, a[2] or 0)
        if z <= -S.MIN_DOWN then
            L.source, L.dx, L.dy, L.dz = "light_environment", x, y, z
            dirText = string.format("light_environment pitch %s, yaw %s", tostring(pitch), tostring(a[2] or 0))
        else
            notes[#notes + 1] = string.format("light_environment pitch %s points within 10 degrees of horizontal or up: "
                .. "not used", tostring(pitch))
        end
        if le.n > 1 then notes[#notes + 1] = string.format("the first of %d light_environment", le.n) end
    end
    if L.source == "down" then
        dirText = "straight down: " .. (why or ((sckv or lekv) and "the map's sun is not usable" or
            "the map has neither shadow_control nor light_environment"))
    end
    if not L.sky3d then notes[#notes + 1] = "a 2D sky (no sky_camera)" end
    L.text = string.format("%s, colour (%s, %s, %s), distance %s%s%s", dirText, tostring(L.color[1]),
        tostring(L.color[2]), tostring(L.color[3]), tostring(L.distance), L.disabled and
        "; the map disables shadows (disableallshadows 1): none drawn" or "", #notes > 0 and ("; " ..
        table.concat(notes, "; ")) or "")
    return L
end

-- the job (a coroutine, one step per frame from the Think hook): the header, lump 0 in slices, the parse in steps
local function light_job(map)
    local f = file.Open("maps/" .. map .. ".bsp", "rb", "GAME")
    if not f then return S.LightOf(nil, "the map's file could not be read") end
    S.file = f
    local H, why = S.ParseHeader(f:Read(S.HEADER_BYTES))
    local text
    if H then
        if H.fourcc ~= 0 then
            H, why = nil, "the map's entities are compressed (LZMA)"
        elseif not (H.ofs and H.len and H.ofs > 0 and H.len > 0) then
            H, why = nil, "the map has no entities"
        elseif H.len > S.LUMP_MAX then
            H, why = nil, string.format("the map's entities are %.1f MB (more than %d MB)", H.len / 1048576,
                S.LUMP_MAX / 1048576)
        end
    end
    if H then
        f:Seek(H.ofs)
        local parts, got = {}, 0
        while got < H.len do
            local part = f:Read(math.min(S.SLICE, H.len - got))
            if not part or #part == 0 then break end
            parts[#parts + 1] = part
            got = got + #part
            coroutine.yield()
        end
        text = table.concat(parts)
        if string.sub(text, 1, 4) == "LZMA" then text, why = nil, "the map's entities are compressed (LZMA)" end
    end
    f:Close()
    S.file = nil
    if not text then return S.LightOf(nil, why) end
    return S.LightOf(S.ParseEntities(text, coroutine.yield))
end

local function step_light()
    local map = game.GetMap()
    if S.lightMap == map or S.broken then return end
    if not S.job or S.jobMap ~= map then S.job, S.jobMap = coroutine.create(light_job), map end
    local ok, L = coroutine.resume(S.job, map)
    if not ok then
        if S.file then pcall(function() S.file:Close() end) S.file = nil end
        L = S.LightOf(nil, "the map's entities could not be read (" .. tostring(L) .. ")")
    elseif coroutine.status(S.job) ~= "dead" then
        return
    end
    S.light, S.lightMap, S.job = L, map, nil
    log("sun shadow: %s; pictures: %s; followers with one: %s; only where the sun reaches: %s (%s)", L.text, cv.rate:GetFloat() > 0 and
        cv.rate:GetString() .. " a second" or "every frame", cv.followers:GetString(), cv.sunlit:GetString(), L.sun.text)
end
S.StepLight = step_light

-- ---- the silhouette and the receivers ------------------------------------------------------------------------------------
-- the batches the silhouette draws: opaque, the body (no effect) and the board; no game object, no blob shadow
local function silhouette_batch(b)
    if b.pass ~= 0 then return false end
    local f = b.flags or 0
    if band(f, DRAW_SHADOW) ~= 0 or band(f, DRAW_OBJECT) ~= 0 then return false end
    if band(f, DRAW_BOARD) ~= 0 then return true end
    return band(f, DRAW_EFFECT) == 0
end
S.SilhouetteBatch = silhouette_batch

local ORTHO = { left = -S.BOX_MIN, right = S.BOX_MIN, top = -S.BOX_MIN, bottom = S.BOX_MIN }
local VIEW = { kind = "sunshadow", hitch = false, opaque = true, x = 0, y = 0, w = S.RT_SIZE, h = S.RT_SIZE, znear = 1,
               zfar = 4 * S.BOX_MIN, filter = silhouette_batch, ortho = ORTHO, eye = Vector(), ang = Angle() }
S.view = VIEW
local FWD, RIGHT, UP = Vector(), Vector(), Vector()
S.stats = { refreshes = 0, refreshMs = 0, traces = 0, frames = 0, frameMs = 0 }
-- one shadow's grid of n x n points. wx, wy, wz: the hit points in the world (lifted towards the light); u, v, fade: their texture
-- coordinates and fade of this frame; depth: along the light below the root at the grid's time (only the ledge rule's differences
-- use it); stats: whose traces these are
local function new_grid(n, stats)
    local g = { n = n, stats = stats, hit = {}, wx = {}, wy = {}, wz = {}, fade = {}, depth = {}, u = {}, v = {}, cells = {}, ncells = 0,
                box = 48, sun = {}, nx = {}, ny = {}, nz = {}, facing = {}, normals = false, sunWas = false, sunPending = false, dark = false, sx = 0, sy = 0, sz = 0 }
    for k = 1, n * n do
        g.hit[k], g.wx[k], g.wy[k], g.wz[k], g.fade[k], g.depth[k], g.u[k], g.v[k] = false, 0, 0, 0, 0, 0, 0, 0
        g.sun[k], g.nx[k], g.ny[k], g.nz[k], g.facing[k] = 0, 0, 0, 1, 1
    end
    for c = 1, (n - 1) * (n - 1) do g.cells[c] = 0 end
    return g
end
local G = new_grid(S.GRID, S.stats)
S.grid = G
S.basis = { fwd = FWD, right = RIGHT, up = UP }
local TR = { start = Vector(), endpos = Vector(), mask = MASK, output = {} }
local POS = Vector()
local TONE_ONE = Vector(1, 1, 1)

-- one shadow's render target and its receivers' material: the silhouette as a decal (polygon offset), no depth writes, no fog (it
-- would pull the darkening towards the fog colour: the blob's mask material, cl_textures.lua)
local function new_target(prefix, size)
    local Tx = GSA1.Tex
    local fmt = Tx and Tx.format or { name = "BGRA8888", fmt = IMAGE_FORMAT_BGRA8888 or 12 }
    local rt = GetRenderTargetEx(prefix .. fmt.name, size, size, RT_SIZE_LITERAL or 5,
        MATERIAL_RT_DEPTH_SEPARATE or 1, bit.bor(TEXTUREFLAGS_CLAMPS or 4, TEXTUREFLAGS_CLAMPT or 8), 0, fmt.fmt)
    return rt, CreateMaterial(prefix .. fmt.name, "UnlitGeneric", { ["$basetexture"] = rt:GetName(),
        ["$vertexcolor"] = 1, ["$translucent"] = 1, ["$nofog"] = 1, ["$decal"] = 1, ["$nocull"] = 1 })
end

-- your character's render target and the two materials (made at the first silhouette)
local function targets()
    if S.rt then return S.rt end
    S.rt, S.recv = new_target("gsa1_sunshadow_", S.RT_SIZE)
    -- the flat white of the silhouette (opaque: the view depth Source writes into the alpha of opaque draws stays out)
    S.white = CreateMaterial("gsa1_sunshadow_white", "UnlitGeneric", { ["$basetexture"] = "vgui/white",
        ["$nocull"] = 1, ["$ignorez"] = 1 })
    VIEW.material = S.white
    return S.rt
end

-- the grid along the light from the box's light side, at most the light's distance past the feet. Its ledge rule goes with the cell:
-- S.STEP_DEPTH is for S.GRID's cell, so a coarser grid keeps the same slopes and the same lowest sun
local function trace_grid(g, C, L, cx, cy, cz, box)
    local N = g.n
    local NN = N * N
    local step = S.STEP_DEPTH * (S.GRID - 1) / (N - 1)
    local stats = g.stats
    local p = C.drawPos
    local px, py, pz = p.x, p.y, p.z
    local dx, dy, dz = L.dx, L.dy, L.dz
    local rx, ry, rz = RIGHT.x, RIGHT.y, RIGHT.z
    local ux, uy, uz = UP.x, UP.y, UP.z
    local dist = L.distance
    TR.filter = LocalPlayer()
    local st, en = TR.start, TR.endpos
    local hit, wx, wy, wz, dep = g.hit, g.wx, g.wy, g.wz, g.depth
    local lift = S.LIFT
    local any = false
    -- (0.9.9c: the surface's own normal, for the sun check alone: sun_at)
    local normals = cv.sunlit:GetBool() and L.sun ~= nil and L.sun.known
    local nx, ny, nz = g.nx, g.ny, g.nz
    for k = 1, NN do
        local i, j = (k - 1) % N, math.floor((k - 1) / N)
        local xv = -box + 2 * box * i / (N - 1)
        local yv = box - 2 * box * j / (N - 1)            -- row 0 at the top of the picture (the view's up)
        local gx = cx + rx * xv + ux * yv - dx * box
        local gy = cy + ry * xv + uy * yv - dy * box
        local gz = cz + rz * xv + uz * yv - dz * box
        local len = dist - ((gx - px) * dx + (gy - py) * dy + (gz - pz) * dz)
        hit[k] = false
        if len > 0 then
            st:SetUnpacked(gx, gy, gz)
            en:SetUnpacked(gx + dx * len, gy + dy * len, gz + dz * len)
            local r = util.TraceLine(TR)
            if r == nil then r = TR.output end
            stats.traces = stats.traces + 1
            if r and r.Hit and not r.StartSolid and r.HitPos then
                local hp = r.HitPos
                local hx, hy, hz = hp.x - px, hp.y - py, hp.z - pz
                local depth = hx * dx + hy * dy + hz * dz
                hit[k] = true
                any = true
                wx[k], wy[k], wz[k] = hp.x - dx * lift, hp.y - dy * lift, hp.z - dz * lift
                dep[k] = depth
                if normals then
                    local hn = r.HitNormal
                    if hn then nx[k], ny[k], nz[k] = hn.x, hn.y, hn.z else nx[k], ny[k], nz[k] = 0, 0, 0 end
                end
            end
        end
    end
    -- the cells drawn: every corner hit, the corners within S.STEP_DEPTH along the light
    local nc = 0
    if any then
        for j = 0, N - 2 do
            for i = 0, N - 2 do
                local k = j * N + i + 1
                if hit[k] and hit[k + 1] and hit[k + N] and hit[k + N + 1] then
                    local a, b, c, d = dep[k], dep[k + 1], dep[k + N], dep[k + N + 1]
                    if math.max(a, b, c, d) - math.min(a, b, c, d) <= step then
                        nc = nc + 1
                        g.cells[nc] = k
                    end
                end
            end
        end
    end
    g.ncells = nc
    g.px, g.py, g.pz, g.at, g.C, g.box = px, py, pz, SysTime(), C, box
    g.normals = normals
end

-- the silhouette box of a character this frame: its half size, its centre (the drawn root, up by the character's centre)
local function box_of(C)
    local info = C.info or {}
    local p = C.drawPos
    return math.max(S.BOX_MIN, 0.75 * (tonumber(info.height) or 40) + 16), p.x, p.y, p.z + (tonumber(info.center) or 20)
end

-- one silhouette, in PostRender - never inside a view (the top of this file): true when it was made. Also the light's axes that the
-- grid and the texture coordinates use. s: a follower's place (the followers' part below), else your character's
local function refresh(C, L, now, s)
    if s then s.refreshAt = now else S.refreshAt, S.refreshC = now, C end
    local dx, dy, dz = L.dx, L.dy, L.dz
    local ang = VIEW.ang
    ang.p, ang.y, ang.r = math.deg(math.atan2(-dz, math.sqrt(dx * dx + dy * dy))), math.deg(math.atan2(dy, dx)), 0
    GSA1.AngleAxes(ang, FWD, RIGHT, UP)
    local box, cx, cy, cz = box_of(C)
    ORTHO.left, ORTHO.right, ORTHO.top, ORTHO.bottom = -box, box, -box, box
    VIEW.eye:SetUnpacked(cx - dx * 2 * box, cy - dy * 2 * box, cz - dz * 2 * box)
    VIEW.znear, VIEW.zfar = 1, 4 * box
    local size = s and S.FOLLOWER_RT or S.RT_SIZE
    VIEW.w, VIEW.h = size, size
    local rt = s and s.rt or targets()
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 255, true, true)
    local fog = render.GetFogMode and render.GetFogMode()
    if render.FogMode then render.FogMode(MATERIAL_FOG_NONE or 0) end
    local mr, mg, mb
    if render.GetColorModulation and render.SetColorModulation then
        mr, mg, mb = render.GetColorModulation()
        render.SetColorModulation(1, 1, 1)
    end
    -- (white stays white whatever the scale at the frame's end is: an HDR map's exposure would make the picture grey)
    local tone = render.GetToneMappingScaleLinear and render.GetToneMappingScaleLinear()
    if tone and render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(TONE_ONE) end
    local ok, drawn, why = pcall(GSA1.DrawCharacterView, C, VIEW)
    if mr then render.SetColorModulation(mr, mg, mb) end
    if fog and render.FogMode then render.FogMode(fog) end
    -- (0.9.9a: inside the pair, and the pop last, whatever the blur does: WHY THE BLUR IS INSIDE THE PAIR at the top of this file. Yours
    -- only: a follower's picture has none, THE FOLLOWERS there say why)
    local blurred, blurErr = true, nil
    if ok and drawn and not s and render.BlurRenderTarget then
        blurred, blurErr = pcall(render.BlurRenderTarget, rt, S.BLUR, S.BLUR, 1)
    end
    if tone and render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(tone) end
    render.PopRenderTarget()
    if not ok then error(drawn, 0) end
    if not blurred then error(blurErr, 0) end
    if not drawn then return false, why end
    if s then
        s.picture = true
        s.stats.pictures = s.stats.pictures + 1
    else
        S.picture, S.pictureC = true, C
        S.stats.refreshes = S.stats.refreshes + 1
    end
    return true
end

local function vertex(g, k, cr, cg, cb)
    local f = g.fade[k]
    POS:SetUnpacked(g.wx[k], g.wy[k], g.wz[k])
    mesh.Position(POS)
    mesh.TexCoord(0, g.u[k], g.v[k])
    mesh.Color(cr * f, cg * f, cb * f, 255)
    mesh.AdvanceVertex()
end

-- the cells' two triangles each (in pcall: mesh.End must follow mesh.Begin)
local function emit_cells(g, nc, cr, cg, cb)
    local cells, N = g.cells, g.n
    for c = 1, nc do
        local k = cells[c]
        vertex(g, k, cr, cg, cb)
        vertex(g, k + N, cr, cg, cb)
        vertex(g, k + 1, cr, cg, cb)
        vertex(g, k + 1, cr, cg, cb)
        vertex(g, k + N, cr, cg, cb)
        vertex(g, k + N + 1, cr, cg, cb)
    end
end

-- ---- where the sun reaches (0.9.9c; ONLY WHERE THE SUN REACHES at the top of this file) -----------------------------------------------------------
S.SUN_CELL = 32                     -- HU: the lattice of ground samples, fixed in the world. From 24 to 48 HU agreed alike with the maps' baked light (12 and 16: run on a quarter of the samples, alike there); the
                                    -- fade across a shade line is one cell wide, about what a lightmap's own edge is, and a grid's points 12 or 16 HU apart show it
S.SUN_SLOTS = 2048                  -- the lattice's answers kept, by a hash of the corner: a clash only asks again
S.SUN_BAND = 32                     -- HU: heights a corner keeps apart (two levels on one x, y): the band of the point asking
S.SUN_SAME = 48                     -- HU: a corner whose ground lies further than this from the point asking is another surface: it does not count
S.SUN_LIFT = 8                      -- HU: its ray starts this far off its ground (a plane through a point of a curved surface can lie under the surface). MEASURED, agreement with the baked light at 4 / 8 / 12 / 16: 99.12 99.09 98.91 98.58,
                                    -- 98.90 98.75 98.74 98.71, 97.65 97.60 97.58 97.57, 96.15 96.16 96.04 95.95; gm_snowrider_day_v3's 198 samples 69.2 72.7 72.2 71.7
S.SUN_STEP = 18                     -- HU of height: a ray stopped within this of its start gets a second ray from this much higher (sun_ray). About what a player walks over, UNVERIFIED for Garry's Mod. MEASURED, 12 or 24: within 0.1 points of this on four maps
S.SUN_FAR = 56755                   -- HU: a ray to the sun, VRAD's MAX_TRACE_LENGTH
S.SUN_KEEP = 4                      -- s: an answer kept (what moves: doors, props); a standing shadow asks about 6 corners a second again
S.SUN_FADE = 0.25                   -- s: an answer that changes (something moved into the sun's way) goes over from the old one in this time
S.SUN_FACING = 0.1                  -- how far a point's surface must face the sun (the cosine) for all of its sun: under it less, to none at 0. Flat ground under the lowest sun used (10 degrees) has 0.17
S.SUN_PLANE = 0.25                  -- of a grid's cell, along the light: how far a neighbour may lie off a point's plane and still be on it
S.SUN_WIDE = 1.4                    -- cells: a surface this wide or wider, turned from the sun, reads none; a cell or less reads what is around it (sun_broad). Under the square root of 2: ground across the grid at any angle is this wide
S.SUN_JUMP = 96                     -- HU (x + y + z): a shadow that moved so far since its points were last asked starts from nothing: more than a frame's run at 30 fps, less than a teleport
S.SUN_YOU, S.SUN_THEM = 32, 48      -- corners asked in a frame at most, for your shadow / for all the followers': the rest the next frame
S.PROBE_EACH, S.PROBE_EVERY = 6, 5  -- "sun check sample" log lines: per answer and map, seconds apart
local MASK_SUN = MASK_OPAQUE or 16513                   -- VRAD's blockers: no windows, no water, no grates
local SF = { left = 0, st = {}, kx = {}, ky = {}, kb = {}, zg = {}, lit = {}, at = {}, from = {}, t0 = {}, n = 0, traces = 0, fading = false,
             probe = { [0] = 0, [1] = 0, next = 0 } }
S.sunfield = SF
local TRS = { start = Vector(), endpos = Vector(), mask = MASK_SUN, output = {} }

-- empties the answers (the first use, a new map's light; and the tests)
function S.ResetSun()
    local st, kx, ky, kb, zg, lit, at, from, t0 = SF.st, SF.kx, SF.ky, SF.kb, SF.zg, SF.lit, SF.at, SF.from, SF.t0
    for i = 1, S.SUN_SLOTS do st[i], kx[i], ky[i], kb[i], zg[i], lit[i], at[i], from[i], t0[i] = 0, 0, 0, 0, 0, 0, 0, 0, 0 end
    SF.n = S.SUN_SLOTS
end

-- a ray towards the sun from a point: 1 it gets there, or hits nothing (VRAD's miss is "seen"); 0 something stops it; -1 it started in solid. Stopped within S.SUN_STEP of height above its start, a second ray from
-- that much higher says whether it was only a low step: then this counts as sun, since the narrow shade of a curb or a stair's riser is no reason to fade a whole cell of the lattice
local sun_ray
function sun_ray(x, y, z, sun, again)
    local st, en = TRS.start, TRS.endpos
    local far = S.SUN_FAR
    st:SetUnpacked(x, y, z)
    en:SetUnpacked(x - sun.dx * far, y - sun.dy * far, z - sun.dz * far)
    local r = util.TraceLine(TRS)
    if r == nil then r = TRS.output end
    SF.traces = SF.traces + 1
    if r.StartSolid or r.AllSolid then return -1 end
    if not r.Hit or r.HitSky then return 1 end
    if not again and r.Fraction * far * -sun.dz <= S.SUN_STEP then
        SF.left = SF.left - 1
        return sun_ray(x, y, z + S.SUN_STEP, sun, true) == 1 and 1 or 0
    end
    return 0
end

-- what the log gets beside the ray's answer: the engine's own lighting at that place, for a later round to weigh (ONLY WHERE THE SUN REACHES)
local function probe_line(x, y, z, ans, sun)
    local at = Vector(x, y, z + 20)
    local a, b = render.ComputeLighting(at, Vector(-sun.dx, -sun.dy, -sun.dz)), render.ComputeLighting(at, Vector(sun.dx, sun.dy, sun.dz))
    local c = render.GetSurfaceColor and render.GetSurfaceColor(Vector(x, y, z + 16), Vector(x, y, z - 16))
    log("sun check sample: the ray says %s at (%.0f %.0f %.0f); render.ComputeLighting towards the sun (%.3f %.3f %.3f), away from it (%.3f %.3f %.3f); "
        .. "render.GetSurfaceColor %s", ans == 1 and "sun" or "shade", x, y, z, a.x, a.y, a.z, b.x, b.y, b.z, c and string.format("(%.3f %.3f %.3f)", c.x, c.y, c.z) or "none")
end

-- a corner of the lattice in this band: its slot, asked now if it has no fresh answer; 0 when this frame's budget is spent and it has no answer at all. Its ground is the plane of the point asking, through
-- that point's own normal (nx, ny, nz, facing the sun: sun_points does not ask for the others), so one trace a corner, two beside a low step. Asked again with another answer, it goes over from the old one in S.SUN_FADE s (sun_value)
local function sun_corner(ix, iy, band, L, now, g, k, nx, ny, nz)
    local cell = S.SUN_CELL
    local h = (ix * 61 + iy * 1021 + band * 131) % S.SUN_SLOTS + 1
    local st, at = SF.st, SF.at
    local mine = st[h] ~= 0 and SF.kx[h] == ix and SF.ky[h] == iy and SF.kb[h] == band
    if mine and now >= at[h] and now - at[h] < S.SUN_KEEP then return h end
    if SF.left <= 0 then return mine and h or 0 end
    SF.left = SF.left - 1
    local had = mine and st[h] == 1
    local old = had and SF.lit[h] or 0
    if had and now - SF.t0[h] < S.SUN_FADE and now >= SF.t0[h] then
        old = SF.from[h] + (old - SF.from[h]) * (now - SF.t0[h]) / S.SUN_FADE
    end
    SF.kx[h], SF.ky[h], SF.kb[h], at[h] = ix, iy, band, now
    local x, y = ix * cell, iy * cell
    local vz = g.wz[k]
    local gz = vz
    if nz >= 0.3 then gz = vz - (nx * (x - g.wx[k]) + ny * (y - g.wy[k])) / nz end
    SF.zg[h] = gz
    local sun, lift = L.sun, S.SUN_LIFT
    local ans = sun_ray(x + nx * lift, y + ny * lift, gz + nz * lift, sun)
    if ans < 0 then
        st[h] = 2
        return h
    end
    st[h], SF.lit[h] = 1, ans
    if had and old ~= ans then
        SF.from[h], SF.t0[h] = old, now
    else
        SF.from[h], SF.t0[h] = ans, 0
    end
    local P = SF.probe
    if now >= P.next and P[ans] < S.PROBE_EACH and GSA1.LogEnabled and GSA1.LogEnabled() then
        P.next = now + S.PROBE_EVERY
        P[ans] = P[ans] + 1
        if not pcall(probe_line, x, y, gz, ans, sun) then P[0], P[1] = S.PROBE_EACH, S.PROBE_EACH end
    end
    return h
end

-- a corner's value now: its answer, or on the way to it
local function sun_value(h, now)
    local v = SF.lit[h]
    local dt = now - SF.t0[h]
    if dt < S.SUN_FADE and dt >= 0 then
        SF.fading = true
        return SF.from[h] + (v - SF.from[h]) * dt / S.SUN_FADE
    end
    return v
end

-- no corner counts (a narrow ledge, a beam, all four in walls): the point's own ray, kept like a corner on a finer lattice; a point with no answer is drawn. -1: not asked yet
local function sun_own(x, y, z, sun, now)
    local ix, iy, band = math.floor(x / 8), math.floor(y / 8), math.floor(z / 8) + 100000
    local h = (ix * 61 + iy * 1021 + band * 131) % S.SUN_SLOTS + 1
    local st = SF.st
    local mine = st[h] == 3 and SF.kx[h] == ix and SF.ky[h] == iy and SF.kb[h] == band
    if mine and now >= SF.at[h] and now - SF.at[h] < S.SUN_KEEP then return SF.lit[h] end
    if SF.left <= 0 then return mine and SF.lit[h] or -1 end
    SF.left = SF.left - 1
    local ans = sun_ray(x, y, z + S.SUN_LIFT, sun)
    if ans < 0 then ans = 1 end
    st[h], SF.kx[h], SF.ky[h], SF.kb[h], SF.at[h], SF.lit[h], SF.from[h], SF.t0[h] = 3, ix, iy, band, now, ans, ans, 0
    return ans
end

-- how much sun at a point of a shadow's grid that faces the sun, 0 .. 1: the bilinear mean of the four corners on its own surface (a trace with no normal counts as flat ground). -1: not known yet (the budget)
local function sun_at(g, k, L, now)
    local nx, ny, nz = g.nx[k], g.ny[k], g.nz[k]
    if nx == 0 and ny == 0 and nz == 0 then nz = 1 end
    local sun = L.sun
    local x, y, z = g.wx[k], g.wy[k], g.wz[k]
    local cell = S.SUN_CELL
    local fx, fy = x / cell, y / cell
    local ix, iy = math.floor(fx), math.floor(fy)
    local ax, ay = fx - ix, fy - iy
    local band = math.floor(z / S.SUN_BAND)
    local st, zg, same = SF.st, SF.zg, S.SUN_SAME
    local sum, W, late = 0, 0, false
    local h = sun_corner(ix, iy, band, L, now, g, k, nx, ny, nz)
    if h == 0 then late = true
    elseif st[h] == 1 and math.abs(zg[h] - z) <= same then
        local w = (1 - ax) * (1 - ay)
        sum, W = sum + w * sun_value(h, now), W + w
    end
    h = sun_corner(ix + 1, iy, band, L, now, g, k, nx, ny, nz)
    if h == 0 then late = true
    elseif st[h] == 1 and math.abs(zg[h] - z) <= same then
        local w = ax * (1 - ay)
        sum, W = sum + w * sun_value(h, now), W + w
    end
    h = sun_corner(ix, iy + 1, band, L, now, g, k, nx, ny, nz)
    if h == 0 then late = true
    elseif st[h] == 1 and math.abs(zg[h] - z) <= same then
        local w = (1 - ax) * ay
        sum, W = sum + w * sun_value(h, now), W + w
    end
    h = sun_corner(ix + 1, iy + 1, band, L, now, g, k, nx, ny, nz)
    if h == 0 then late = true
    elseif st[h] == 1 and math.abs(zg[h] - z) <= same then
        local w = ax * ay
        sum, W = sum + w * sun_value(h, now), W + w
    end
    local v
    if W > 1e-3 then v = sum / W
    elseif late then return -1
    else
        v = sun_own(x, y, z, sun, now)
        if v < 0 then return -1 end
    end
    return v
end

-- a point's plane in the grid's own terms: how fast the depth along the light changes along the grid's rows and columns (the next i, the next j). nil: a surface edge-on to the light
local function plane_slope(g, k, L)
    local ax, ay, az = g.nx[k], g.ny[k], g.nz[k]
    if ax == 0 and ay == 0 and az == 0 then az = 1 end
    local nl = ax * L.dx + ay * L.dy + az * L.dz
    if nl > -1e-3 then return nil end
    return -(ax * RIGHT.x + ay * RIGHT.y + az * RIGHT.z) / nl, (ax * UP.x + ay * UP.y + az * UP.z) / nl
end

-- how far a point's plane runs towards its neighbour m, 0 .. s (a cell), by depth: to where it meets m's plane when that lies between the two; else all the way when m lies on it, else not at all.
-- Ak: k's slope towards m; along: 1 the rows, 2 the columns; way: 1 or -1 along them
local function sun_reach(g, L, k, m, s, Ak, along, way)
    local dd = g.depth[m] - g.depth[k]
    local on = math.abs(dd - Ak * s) <= S.SUN_PLANE * s
    local a, b = plane_slope(g, m, L)
    if not a then return on and s or 0 end
    local Am = (along == 1 and a or b) * way
    local t = (dd - Am * s) / (Ak - Am)        -- (parallel planes: infinite, or nothing over nothing when they are one)
    if t > 0 and t < s then return t end
    return on and s or 0
end

-- how far a point's plane runs along one axis of the grid, from its reach each way. The grid's rim and a point with no hit tell nothing: a neighbour on the plane on the side that can be read says it goes on, anything less counts once
local function sun_span(e1, e2, s)
    if e1 and e2 then return e1 + e2 end
    local e = e1 or e2 or 0
    return e >= s and 2 * s or e
end

-- how wide the surface of a point is, as the grid sees it (across the way it falls, in the plane the grid's rows lie in), from its plane and where that meets its neighbours' planes, so it is a property of the surface: it
-- does not change as the grid's rows move over it. 0: a cell wide or less, such as a riser under a steep light: a row falls on it only now and then, so what it reads would blink. 1: S.SUN_WIDE cells or more: rows are always on it
local function sun_broad(g, k, L)
    local a, b = plane_slope(g, k, L)
    if not a then return 0 end
    local N, hit = g.n, g.hit
    local s = 2 * g.box / (N - 1)
    local i, j = (k - 1) % N, math.floor((k - 1) / N)
    local wu = sun_span(i > 0 and hit[k - 1] and sun_reach(g, L, k, k - 1, s, -a, 1, -1), i < N - 1 and hit[k + 1] and sun_reach(g, L, k, k + 1, s, a, 1, 1), s)
    local wv = sun_span(j > 0 and hit[k - N] and sun_reach(g, L, k, k - N, s, -b, 2, -1), j < N - 1 and hit[k + N] and sun_reach(g, L, k, k + N, s, b, 2, 1), s)
    local G = math.sqrt(a * a + b * b)
    local w = G > 1e-3 and math.max(wu * math.abs(a), wv * math.abs(b)) / G or math.max(wu, wv)
    return math.max(math.min((w / s - 1) / (S.SUN_WIDE - 1), 1), 0)
end

-- what a point turned from the sun reads: on broad ground none; on a sliver, a riser the grid's light happens to hit, what the points around it that face the sun read, so one row of points makes no notch and asks
-- no corner. Nothing around it faces the sun (stairs whose steps fall exactly on the grid's rows): it keeps what it read, less what its surface is broad
local function sun_turned(g, k, T, L)
    local N, hit, F = g.n, g.hit, g.facing
    local broad = sun_broad(g, k, L)
    local i, j = (k - 1) % N, math.floor((k - 1) / N)
    local sum, n = 0, 0
    for dj = -1, 1 do
        if j + dj >= 0 and j + dj < N then
            for di = -1, 1 do
                if i + di >= 0 and i + di < N then
                    local m = k + di + dj * N
                    if hit[m] and F[m] > 0 then sum, n = sum + T[m], n + 1 end
                end
            end
        end
    end
    T[k] = (n > 0 and sum / n or T[k]) * (1 - broad)
end

-- this grid's points: g.sun. One not known yet (the budget) keeps its value and is asked again next frame, and so is the grid while a corner it uses is on its way to a new answer; but a value belongs near where it
-- was asked: a new shadow, or one that jumped S.SUN_JUMP, starts from nothing, so what it does not know yet is not drawn, in the sun for a frame or two, and never lit in the shade
local function sun_points(g, L, now, px, py, pz, was)
    if SF.n == 0 or SF.L ~= L then
        S.ResetSun()
        SF.L = L
        SF.probe[0], SF.probe[1], SF.probe.next = 0, 0, 0
    end
    local hit, T, F, nx, ny, nz = g.hit, g.sun, g.facing, g.nx, g.ny, g.nz
    local NN = g.n * g.n
    if not was or math.abs(px - g.sx) + math.abs(py - g.sy) + math.abs(pz - g.sz) >= S.SUN_JUMP then
        for k = 1, NN do T[k] = 0 end
    end
    g.sx, g.sy, g.sz = px, py, pz
    local late, turned = false, false
    SF.fading = false
    local sun, lim = L.sun, S.SUN_FACING
    for k = 1, NN do
        if hit[k] then
            local ax, ay, az = nx[k], ny[k], nz[k]
            if ax == 0 and ay == 0 and az == 0 then az = 1 end
            F[k] = -(ax * sun.dx + ay * sun.dy + az * sun.dz)
        end
    end
    for k = 1, NN do
        if hit[k] then
            local f = F[k]
            if f <= 0 then
                turned = true
            else
                local v = sun_at(g, k, L, now)
                if v < 0 then
                    late = true
                else
                    -- (broad ground that hardly faces the sun fades towards none, as a baked surface does; a thin thing keeps what its corners say)
                    if f < lim then v = v * (1 - sun_broad(g, k, L) * (1 - f / lim)) end
                    T[k] = v
                end
            end
        end
    end
    if turned then
        for k = 1, NN do
            if hit[k] and F[k] <= 0 then sun_turned(g, k, T, L) end
        end
    end
    g.sunPending = late or SF.fading
end

-- a shadow's grid, placed at the drawn root of THIS frame: first the grid again when due (the top of this file), then each hit point's
-- texture coordinates, its place in the light's view around the character's centre now (the picture's orientation: u along the view's
-- right, v down its up, as in a perspective view), and its fade, its depth along the light below the feet now (from the hit point: the
-- lift taken off). The cells to draw. The picture itself was finished in an earlier frame's PostRender
local function place_grid(g, C, L, now)
    local box, cx, cy, cz = box_of(C)
    local p = C.drawPos
    local px, py, pz = p.x, p.y, p.z
    -- (0.9.9c: where the sun reaches: THE TOP OF THIS FILE. Off, or a map with no sun to ask: as 0.9.9b)
    local sunOn = cv.sunlit:GetBool() and L.sun ~= nil and L.sun.known
    local traced = false
    if g.C ~= C or not g.at or now - g.at >= S.RETRACE_EVERY - 1e-6 or
       math.abs(px - g.px) + math.abs(py - g.py) + math.abs(pz - g.pz) >= S.RETRACE_MOVE or (sunOn and not g.normals) then
        trace_grid(g, C, L, cx, cy, cz, box)
        traced = true
    end
    local nc = g.ncells
    g.dark = false
    if nc == 0 then return 0 end
    local sv, brightest = g.sun, 0
    if sunOn then
        if traced or not g.sunWas or g.sunPending then sun_points(g, L, now, px, py, pz, g.sunWas) end
        g.sunWas = true
    else
        g.sunWas = false
    end
    local rx, ry, rz, ux, uy, uz = RIGHT.x, RIGHT.y, RIGHT.z, UP.x, UP.y, UP.z
    local dx, dy, dz = L.dx, L.dy, L.dz
    local k2 = 0.5 / box
    local over, lift = 1 / math.max(L.distance, 1), S.LIFT
    local hit, wx, wy, wz, U, V, fade = g.hit, g.wx, g.wy, g.wz, g.u, g.v, g.fade
    for k = 1, g.n * g.n do
        if hit[k] then
            local x, y, z = wx[k], wy[k], wz[k]
            local ex, ey, ez = x - cx, y - cy, z - cz
            U[k] = 0.5 + (ex * rx + ey * ry + ez * rz) * k2
            V[k] = 0.5 - (ex * ux + ey * uy + ez * uz) * k2
            local f = 1 - math.min(math.max(((x - px) * dx + (y - py) * dy + (z - pz) * dz + lift) * over, 0), 1)
            if sunOn then
                local s0 = sv[k]
                if s0 > brightest then brightest = s0 end
                f = f * s0
            end
            fade[k] = f
        end
    end
    if sunOn and brightest <= 0.002 then g.dark = true end
    return nc
end

-- the receivers' colour: the darkness option, else the map's shadow colour
local function quad_colour(L)
    local dark = cv.dark and cv.dark:GetFloat() or 0
    if dark > 0 then
        local c = 255 * math.min(dark, 100) / 100
        return c, c, c
    end
    local col = L.color
    return 255 - (col[1] or 128), 255 - (col[2] or 128), 255 - (col[3] or 128)
end

-- one shadow's quads
local function draw_cells(g, recv, nc, cr, cg, cb)
    render.SetMaterial(recv)
    render.OverrideBlend(true, B_ZERO, B_ONE_MINUS_SRC_COLOR, B_FUNC_ADD)
    mesh.Begin(MATERIAL_TRIANGLES, 2 * nc)
    local ok, err = pcall(emit_cells, g, nc, cr, cg, cb)
    mesh.End()
    render.OverrideBlend(false)
    return ok, err
end

-- your character's receiver quads
local function draw_receivers(C, L, fn, now)
    if not S.picture or S.pictureC ~= C then return end
    SF.left = S.SUN_YOU
    local nc = place_grid(G, C, L, now)
    if nc == 0 then return end
    if G.dark then
        S.shadeFrame = fn       -- (all of it in the shade: no draw; the reason, why_not)
        return
    end
    local cr, cg, cb = quad_colour(L)
    local tone = render.GetToneMappingScaleLinear and render.GetToneMappingScaleLinear()
    if tone and render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(TONE_ONE) end
    local ok, err = draw_cells(G, S.recv, nc, cr, cg, cb)
    if tone and render.SetToneMappingScaleLinear then render.SetToneMappingScaleLinear(tone) end
    if not ok then error(err, 0) end
    S.quadsFrame = fn
end

local function stop(err)
    S.broken = tostring(err)
    log("sun shadow: stopped for this session: %s", S.broken)
end

-- ---- the followers' shadows (0.9.9a; the top of this file) ----------------------------------------------------------------
S.FOLLOWER_GRID = 7                 -- 49 traces and 36 cells for your character's 81 and 64
S.FOLLOWER_RT = 128                 -- its picture's size, no blur (your character's: S.RT_SIZE 256, blurred)
S.PICTURES_PER_FRAME = 4            -- at most so many followers' pictures a frame: 8 followers each get one every other frame
S.CHOOSE_EVERY = 0.1                -- s: who has one, as often as cl_follower.lua sorts them
S.CHOOSE_NEARER = 0.81              -- a follower takes the place of one with a shadow when its squared distance is below this share
                                    -- of that one's (10 % nearer): two about as near do not swap to and fro
S.FOLLOWERS_MAX = 8
local FS = { slots = {}, stats = { pictures = 0, traces = 0, frames = 0, ms = 0 }, nextChoose = 0, turn = 1 }
S.followers = FS

local function fo_can(F)
    return F.lod == 1 and not F.held and not F.removed and F.batches ~= nil and F.drawPos ~= nil
end

local function fo_release(s)
    s.F, s.picture, s.seen, s.refreshAt = nil, false, nil, nil
    s.g.C, s.g.at, s.g.ncells, s.g.sunWas = nil, nil, 0, false
end

local function fo_stop(err)
    FS.broken = tostring(err)
    log("sun shadow: the followers' sun shadows stopped for this session: %s", FS.broken)
    for _, s in ipairs(FS.slots) do fo_release(s) end
end

-- the first place without a follower, made when it is needed, within the slider
local function fo_free(want)
    local slots = FS.slots
    for i = 1, want do
        local s = slots[i]
        if not s then
            s = { g = new_grid(S.FOLLOWER_GRID, FS.stats), stats = FS.stats, picture = false }
            slots[i] = s
        end
        if not s.F then return s end
    end
    return nil
end

local function fo_has(F, want)
    local slots = FS.slots
    for i = 1, math.min(want, #slots) do
        if slots[i].F == F then return true end
    end
    return false
end

-- who has one: cl_follower.lua's list by distance (Fo.order: never a held one), the nearest that are in full detail. One that is not
-- among them any more keeps its place until a clearly nearer one wants it
local function fo_choose(want)
    local slots = FS.slots
    for i = 1, #slots do
        local s = slots[i]
        if s.F and (i > want or not fo_can(s.F)) then fo_release(s) end
    end
    if want <= 0 then return end
    local Fo = GSA1.Followers
    local order = Fo and Fo.order
    if not order then return end
    local seen = 0
    for r = 1, #order do
        local F = order[r]
        if fo_can(F) then
            seen = seen + 1
            if seen > want then break end
            if not fo_has(F, want) then
                local s = fo_free(want)
                if not s then
                    local far, fd = nil, -1
                    for i = 1, want do
                        local d = slots[i].F.dist2 or 0
                        if d > fd then far, fd = slots[i], d end
                    end
                    if far and (F.dist2 or 0) < fd * S.CHOOSE_NEARER then
                        fo_release(far)
                        s = far
                    end
                end
                if s then s.F = F end
            end
        end
    end
end

-- their quads, in the main view: the same as your character's, one tone-mapping scale around them all (FS.tone: restored by the caller)
local function fo_quads(L, fn, now)
    local slots = FS.slots
    local cr, cg, cb
    SF.left = S.SUN_THEM
    for i = 1, #slots do
        local s = slots[i]
        local F = s.F
        if F and F.viewFrame == fn and fo_can(F) then
            s.seen = fn
            if s.picture then
                local nc = place_grid(s.g, F, L, now)
                if nc > 0 and not s.g.dark then
                    if not cr then
                        cr, cg, cb = quad_colour(L)
                        local tone = render.GetToneMappingScaleLinear and render.GetToneMappingScaleLinear()
                        if tone and render.SetToneMappingScaleLinear then
                            FS.tone = tone
                            render.SetToneMappingScaleLinear(TONE_ONE)
                        end
                    end
                    local ok, err = draw_cells(s.g, s.recv, nc, cr, cg, cb)
                    if not ok then error(err, 0) end
                end
            end
        end
    end
end

local function fo_main_view(L, fn)
    if FS.quadFrame == fn or FS.broken or #FS.slots == 0 then return end
    FS.quadFrame = fn
    local t0 = SysTime()
    local ok, err = pcall(fo_quads, L, fn, t0)
    if FS.tone then
        render.SetToneMappingScaleLinear(FS.tone)
        FS.tone = nil
    end
    local dt = SysTime() - t0
    FS.stats.ms = FS.stats.ms + dt * 1000
    FS.stats.frames = FS.stats.frames + 1
    if GSA1.HitchAdd then GSA1.HitchAdd("FollowerShadow", dt) end
    if not ok then fo_stop(err) end
end

-- their pictures, at the frame's end: each one the main view took this frame, by turns when there are more than S.PICTURES_PER_FRAME
local function fo_pictures(L, fn, now)
    local want = math.max(math.min(cv.followers:GetInt(), S.FOLLOWERS_MAX), 0)
    if want ~= FS.want or now >= FS.nextChoose or now < (FS.chosenAt or 0) then
        FS.want, FS.chosenAt, FS.nextChoose = want, now, now + S.CHOOSE_EVERY
        fo_choose(want)
    end
    local slots = FS.slots
    local n = #slots
    local rate = cv.rate:GetFloat()
    local left, last = S.PICTURES_PER_FRAME, nil
    for k = 0, n - 1 do
        if left <= 0 then break end
        local i = (FS.turn + k - 1) % n + 1
        local s = slots[i]
        local F = s.F
        if F and s.seen == fn and F.viewFrame == fn and fo_can(F) and (rate <= 0 or not s.refreshAt or
           now - s.refreshAt >= 1 / rate - 1e-6 or now < s.refreshAt) then
            if not s.rt then
                targets()           -- (the flat white, in the view's table)
                s.rt, s.recv = new_target("gsa1_sunshadow_f" .. i .. "_", S.FOLLOWER_RT)
            end
            refresh(F, L, now, s)
            left, last = left - 1, i
        end
    end
    if last then FS.turn = last % n + 1 end
end

local function fo_frame_end(L, fn)
    if FS.broken then return end
    if #FS.slots == 0 and cv.followers:GetInt() <= 0 then return end
    local t0 = SysTime()
    local ok, err = pcall(fo_pictures, L, fn, t0)
    local dt = SysTime() - t0
    FS.stats.ms = FS.stats.ms + dt * 1000
    -- (no follower has had a place yet: no section)
    if #FS.slots > 0 and GSA1.HitchAdd then GSA1.HitchAdd("FollowerShadow", dt) end
    if not ok then fo_stop(err) end
end

-- a call with isDrawSkybox and not isDraw3DSkybox: the 3D skybox's own view? Never on a map with no sky_camera (there it is
-- the main view under a 2D sky); else Source's view id says (no answer: yes, 0.9.5's way on such a map)
local function sky_view()
    local L = S.light
    if L and L.sky3d == false then return false end
    local vs = render.GetViewSetup and render.GetViewSetup(true)
    local id = type(vs) == "table" and vs.viewid or nil
    return id == nil or id == VIEW_3DSKY
end

-- the reason of this frame: a new one starts its time; one that lasted S.WHY_AFTER: a log line, at most one per reason per
-- map
local function note_why(why, now)
    if why ~= S.why then
        S.why, S.whySince, S.whyDone = why, now, false
    elseif why and not S.whyDone and now - S.whySince >= S.WHY_AFTER then
        S.whyDone = true
        if why ~= WHY.nochar then
            local map = game.GetMap()
            if S.whyMap ~= map then S.whyMap, S.whyLogged = map, {} end
            if not S.whyLogged[why] then
                S.whyLogged[why] = true
                log("sun shadow: not drawn for %d s: %s", S.WHY_AFTER, why)
            end
        end
    end
end

-- the hook after a view's opaque renderables: only in the main view (the top of this file; the character's ENT:Draw has run:
-- its batches of this frame), only the grid when due and the quads
local function main_view(isDrawingDepth, isDrawSkybox, isDraw3DSkybox)
    if S.broken then return end
    local fn = FrameNumber()
    S.hookFrame = fn
    if isDrawingDepth then S.skipWhy = WHY.depth return end
    -- (a map with no sky_camera has no 3D skybox's view: whatever the third argument says, this is its main view)
    if isDraw3DSkybox and not (S.light and S.light.sky3d == false) then S.skipWhy = WHY.sky return end
    if render.GetRenderTarget and render.GetRenderTarget() then S.skipWhy = WHY.target return end
    if isDrawSkybox and sky_view() then S.skipWhy = WHY.sky return end
    S.mainFrame = fn
    -- post_render gives the reasons; with no PostRender reaching us (another addon's hook answered first) this hook says so
    local now = SysTime()
    if not S.postAt then S.postAt = now
    elseif now - S.postAt >= S.WHY_AFTER then note_why(WHY.nopost, now) end
    local C = GSA1.Char
    local L = S.light
    -- (the followers first: what follows is about your character)
    if L and not L.disabled then fo_main_view(L, fn) end
    if not (C and C.batches and C.drawPos and L) or L.disabled then return end
    if C.viewFrame ~= fn or S.drawnFrame == fn then return end
    if GSA1.FirstPerson and GSA1.FirstPerson() and not cv.fp:GetBool() then return end
    S.drawnFrame = fn
    local t0 = SysTime()
    local ok, err = pcall(draw_receivers, C, L, fn, t0)
    local dt = SysTime() - t0
    S.stats.frames, S.stats.frameMs = S.stats.frames + 1, S.stats.frameMs + dt * 1000
    if GSA1.HitchAdd then GSA1.HitchAdd("SunShadow", dt) end
    if not ok then stop(err) end
end

-- why this frame has no quads (nil: it has), in the order that names the real cause first
local function why_not(C, L, fn)
    if S.quadsFrame == fn then return nil end
    if S.shadeFrame == fn then return WHY.shade end
    if not L then return WHY.reading end
    if L.disabled then return WHY.disabled end
    if not (C and C.batches and C.drawPos) then return WHY.nochar end
    if GSA1.FirstPerson and GSA1.FirstPerson() and not cv.fp:GetBool() then return WHY.firstperson end
    if S.hookFrame ~= fn then return WHY.nohook end
    if S.mainFrame ~= fn then return S.skipWhy or WHY.nohook end
    if S.drawnFrame ~= fn then return WHY.notdrawn end
    if not S.picture or S.pictureC ~= C then return WHY.nopicture end
    return WHY.noground
end

-- the frame's end, outside every view: the silhouette when due, then this frame's reason
local function post_render()
    if S.broken then return end
    local fn = FrameNumber()
    local C, L = GSA1.Char, S.light
    local t0 = SysTime()
    S.postAt = t0
    local rate = cv.rate:GetFloat()
    if S.drawnFrame == fn and C and L and C.viewFrame == fn and (rate <= 0 or S.refreshC ~= C or not S.refreshAt or
       t0 - S.refreshAt >= 1 / rate - 1e-6 or t0 < S.refreshAt) then
        local ok, err = pcall(refresh, C, L, t0)
        local dt = SysTime() - t0
        local st = S.stats
        st.refreshMs, st.frameMs = st.refreshMs + dt * 1000, st.frameMs + dt * 1000
        if GSA1.HitchAdd then GSA1.HitchAdd("SunShadow", dt) end
        if not ok then
            stop(err)
            return
        end
    end
    note_why(why_not(C, L, fn), t0)
    if L and not L.disabled then fo_frame_end(L, fn) end
end

-- 0.9.9c: all the traces of this feature so far, for the perf line (cl_log.lua): each one's result is engine objects, the part of its garbage no test here can see
function GSA1.SunShadowTraces()
    return S.stats.traces + FS.stats.traces + SF.traces
end

-- first person with gsa1_sunshadow_fp: cl_render.lua's DrawCharacter prepares the frame's batches without drawing them
local function pre_render()
    local C = GSA1.Char
    if C then C.viewWanted = cv.fp:GetBool() and GSA1.FirstPerson ~= nil and GSA1.FirstPerson() or false end
end

-- the page's status line
function GSA1.SunShadowLine()
    if not cv.on:GetBool() then return "Sun shadow: off" end
    if S.broken then return "Sun shadow: stopped for this session (see the session log)" end
    local L = S.light
    if not L then return "Sun shadow: reading the map's sun ..." end
    local st = S.stats
    local why = S.why and SysTime() - (S.whySince or 0) >= S.WHY_SHOW and S.why or nil
    local fo = ""
    if FS.broken then
        fo = "; the followers' shadows stopped for this session (see the session log)"
    else
        local n = 0
        for _, s in ipairs(FS.slots) do if s.F then n = n + 1 end end
        if n > 0 then fo = string.format("; %d follower%s with one (%.2f ms per frame for all)", n, n == 1 and "" or "s",
            FS.stats.ms / math.max(FS.stats.frames, 1)) end
    end
    local sun = (cv.sunlit:GetBool() and L.sun) and ("; only where the sun reaches: " .. L.sun.text) or ""
    return string.format("Sun shadow: %s%s%s%s%s", L.text, st.frames > 0 and string.format(" (%.2f ms per frame)",
        st.frameMs / st.frames) or "", sun, why and ("; not drawn now: " .. why) or "", fo)
end

-- on / off: the hooks exist only while it is on (off costs nothing)
local guard = GSA1.Guard or function(_, fn) return fn end
local think_g, pre_g, view_g, post_g = guard("SunShadow", step_light), guard("SunShadow", pre_render), main_view,
    guard("SunShadow", post_render)
function S.Apply()
    local on = cv.on and cv.on:GetBool() or false
    if on == S.hooked then return end
    S.hooked = on
    if on then
        hook.Add("Think", HOOK, think_g)
        hook.Add("PreRender", HOOK, pre_g)
        hook.Add("PostDrawOpaqueRenderables", HOOK, view_g)
        hook.Add("PostRender", HOOK, post_g)
    else
        hook.Remove("Think", HOOK)
        hook.Remove("PreRender", HOOK)
        hook.Remove("PostDrawOpaqueRenderables", HOOK)
        hook.Remove("PostRender", HOOK)
        if GSA1.Char then GSA1.Char.viewWanted = nil end
        G.ncells, G.at, S.picture, G.sunWas = 0, nil, false, false       -- (on again: the first quads trace a grid at once)
        for _, s in ipairs(FS.slots) do fo_release(s) end
        FS.want = nil
        S.why, S.whySince, S.whyDone, S.postAt = nil, nil, false, nil
    end
end
if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("gsa1_sunshadow", function() S.Apply() end, HOOK)
end
S.hooked = nil
S.Apply()
