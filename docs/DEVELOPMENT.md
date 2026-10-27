# G-SA1

The Sonic Adventure characters in Garry's Mod: the GMod host for [libsa1](../libsa1/README.md), as G64 is for
libsm64. A binary client module (`gmcl_gsa1_win64.dll`, `gmcl_gsa1_linux64.dll`) runs the game's own decompiled
character code through libsa1 (linked statically) on collision built from the current map's BSP, and a Lua addon
gives the local player a character: input (keyboard and mouse, or an Xbox-style controller read through XInput),
60 Hz game steps, the character drawn as the game draws it (textures, materials, effects, interpolated to any frame
rate), the game's sounds, a chase camera and a settings page in the spawn menu. Everything the game needs is read at run time from **your own disc image**: the module and the addon
contain no SEGA data, and nothing ripped is ever written to disk.

Status (0.6.0, 2026-10-21): the round after the owner's test of 0.5.0 ("lightspeed dash particles are still huge and
there's a lag spike when charging up" - the whole game froze briefly; "the horizontal speed position flickering thing
from earlier happens with vertical movement too"; the sound works). See "What 0.6.0 changes": the Light Speed sparkles
at the game's size and the charged glow translucent (libsa1 round 4c); the up-and-down flicker gone (G-SA1 no longer
moves a frame that libsa1 already moved, and the camera follows the step the game drew); every material a character
can use prepared while it appears (the most likely cause of the freeze, which cannot be measured outside the game);
and a **session log** in `garrysmod/data/gsa1/log.txt`, so a test needs no console copying. Built and tested offline;
not run inside Garry's Mod yet (0.5.0 is installed). 0.5.1 (2026-10-21, not released on its own): **nothing slow runs
on the game's thread any more** (see "What 0.5.1 changes"): the disc,
the sound banks and libsa1's synthesis of the map's collision load on worker threads, a character is created in about
3 ms (no call of the addon's frames took more than 8 ms offline: first spawn, respawn, character switch, map reload),
and the thin-wall threshold is on the Collision page. 0.5.0 (2026-10-21): the fourth round, after the owner's in-game test of 0.3.0 ("1. The ball animations
are weird, they flatten and widen randomly 2. Going up a ramp too fast makes you fall through it 3. The game is randomly
freezing up"; "I think the collision should be generated in the same way G64 is"); see "What 0.5.0 changes": the map's
collision now comes from G64's sources (world brushes, displacements, **static props**, **brush entities and physics
props as moving objects**) read through Garry's Mod's own file system in small pieces, **built on a worker thread** and
kept in a per-map cache,
always cleaned for SA1's collision (one-way thin platforms, double-sided thin walls, hidden faces, buried terrain);
the ball keeps its shape (libsa1 interpolates each drawn part as a transform); sound files load on libsa1's own thread;
a hitch logger names any slow frame. Single player.

| Part | State |
|---|---|
| Module: Lua API (53 functions, plus the features' own through the feature seam: none registered yet), disc from a module-owned config file (loaded on a worker thread), map collision (background job, cache, libsa1's preparation on the worker), moving collision objects, characters (with upgrades), state, render batches, textures, events, sound (banks opened on a worker), controller | done; offline tests pass (core 113 checks, binding 80 checks through a mock Lua stack and a mock `mesh` library (with the game's thread timed on gm_construct and gm_freespace_13; the feature seam with two dummy features), collision 23 checks, map 50 checks, pad 44 checks, the seam's feature tests 4 + 5; in Garry's Mod's own LuaJIT: log 45, warm 11, frame 9, seam 14) |
| Map collision: world brushes, displacements, static props (their `.phy` physics models), brush entity models; hidden faces, one-way thin platforms, double-sided thin walls, buried terrain, stairs as ramps, water, kill plane; background job in the module, workshop maps read through GMod's file system (only the lumps needed), cache in `garrysmod/data/gsa1/cache` | done offline (`map_test`, `tests/diag_maps.cpp` on 13 real maps); works in the game (the owner's test of 0.5.0: the ramps and the garage roof, no freezes on the maps; the Collision page not checked yet) |
| Moving collision: brush entities (doors, lifts, trains, func_brush, breakables), physics props and vehicles near the character as libsa1 moving objects, placed by a matrix every frame, parked (not freed) when off or far | done offline (`map_test`: lift, wall, 300 crates, a gm_construct func_brush); works in the game (the owner's test of 0.5.0: standing on props and moving parts) |
| Controller: XInput read by the module (left stick, right-stick camera, buttons, triggers, rumble from the game's events), Options page | done offline (`pad_test` with a fake XInput, `binding_test`; the real XInput loads and reads on this machine); in game untested |
| Rendering: libsa1's render API (every draw of the game with its material state, effects of every texture archive, sprites, lines), every drawn part interpolated as a transform (libsa1 0.5 round) | done offline (batches, winding, effects of every character, interpolation, the frame loop at 60 / 144 / 240 fps, texel-exact texture transfer); runs in the game (0.5.0: the ball keeps its shape); 0.6.0: drawn exactly as libsa1 renders it, the camera on the drawn step's root |
| Sound: libsa1's audio layer (sound banks, voices, jingles from the disc, its mixer; files read and decoded on its own loader thread), output through Garry's Mod's own BASS | done; works in the game (the owner's test of 0.5.0: "the sound works great too!") |
| Addon: spawn commands, settings in the spawn menu's Options tab (now with a Collision page), input, 60 Hz accumulator, render-target textures, chase camera, respawn on death, server-side player follow, the map loader, moving objects, the hitch logger, the session log, the material pre-warm (every census state's exact material), the feature files, pages and settings (G0) | written, syntax-checked offline (`tools/lua_check.py`) and run in Garry's Mod's own LuaJIT against a mock of the game (`log_test`, `warm_test`, `frame_test`, `seam_test`); 0.5.0 runs in game |
| Multiplayer (owner-authoritative + puppets) | design hook only (`sh_net.lua`, `gsa1.CreatePuppet` / `gsa1.Pose` in the module) |

## What 0.9.4d changes: better spawn-menu pictures of the rings, less Lua garbage per frame

The owner (0.9.4b test): "the ring icons in the G-SA1 tab aren't very good, the circle of rings doesn't even have a rendered
icon". His saved pictures showed why: the single ring's pixels had the game's own gold colour but were half see-through,
the circle was seven tiny rings, and the ring line's picture was refused by its check.

* **The colour.** Source writes the view depth into the alpha of every opaque draw; the ring, close to the picture's
  camera, came out 25-50 % see-through and looked pale over the spawn menu's light background. The pictures are now drawn
  with that switched off (`render.SetWriteDepthToDestAlpha(false)`) and, in case it is not honoured, with the camera at
  least 200 HU from every part. They use the world draw's materials and colour rules, lit by a fixed neutral studio light
  (no left-over lights of other models; colour modulation, blend and tone mapping at 1, all restored afterwards).
* **The framing.** Each picture fits its object to about 85 % of the picture, centred. The single ring gets a
  three-quarter view: the picture waits for the moment in its spin when the ring is turned about 45-65 degrees from
  edge-on. The ring line shows 5 rings at the default spacing, laid out by the game, on a diagonal. The ring circle shows
  the default 7 at a radius of 48 HU, seen 40 degrees from above so it reads as a circle.
* **The check.** It now measures how much of the whole picture is covered: at least 2 % opaque and at least 10 % fully
  transparent. The old 7 x 7 sample grid missed thin rings. An empty, an all-opaque or a half-transparent picture still
  fails, and G-SA1's own drawing stays.
* **Re-made once.** The pictures' key has a new part (`I.PICTURES` 2), so the 0.9.4b / 0.9.4c pictures are drawn again.
  The PNGs listed by an old `index.json` are now deleted at the first start too, not only when the key changes while
  running.
* **Less Lua garbage per frame** (`tests/frame_test.lua`, mock: 0.9.4c 4,020-4,201 bytes in ten runs, 0.9.4d 2,746-2,922
  in eleven; the 4 KB budget is unchanged). The spawn-menu pictures computed their key, a string and a CRC, every frame (0.9.4b). The
  object pictures made a table every frame. The character's draw, the sound listener and the chase camera made new
  Vectors for an angle's axes every frame; these now go into reused Vectors (`GSA1.AngleAxes`).

UNVERIFIED in game: the pictures' colour on the owner's DXVK setup, `render.SetWriteDepthToDestAlpha` (the camera distance
is the fallback), how the three-quarter ring and the 48 HU circle look.

## What 0.9.4c changes: phoneme lip sync

The owner (0.9.4a test): "I was hoping the lipsync system would actually do the phonemes" (sadc `docs/research/phoneme_plan.md`
with its review and the owner's answers 10.1; research `phoneme_shapes.md`, `phoneme_audio.md`).

* **Mouth shapes from your voice** (Faces page, Mouth: the new default; a saved 0.9.4a "Opens with your voice" switched over once):
  a small classifier of our own in the module listens to the microphone capture and names the sound every pair (silence, m / b / p,
  "ah", "eh", "ee", "oh", "oo", "s", f / v); a per-character table picks the game's own face keys or a two-key blend for it
  (Sonic, Tails, Knuckles, Amy; Big has one mouth shape and opens a different amount per sound); f / v (no face can make them) use the
  loudness mouth kept to a slit. libsa1 draws it with the game's own blend (sa1_character_face_mouth).
* **Faster mouth** (on, a switch): the mouth shows in the same game frame it is told (the face task's own blend run before the draw;
  game state unchanged); **bigger mouths for loud speech** (on, a switch: Sonic's and Knuckles' loudest mouths move the eyes or brows a
  little); quick or steadier shape changes (quick).
* **Your voice's pitch** is learned while you talk, in memory for the session only: nothing of it is saved or sent (tested). The
  per-sentence statistics log line exists but is off.
* **"Opens with your voice" fixed**: louder always opens wider now (in 0.9.4a Knuckles' mouth closed again and Sonic's shrank to a
  small "o" when talking loudly) - new per-character ladders.

UNVERIFIED in game: the classifier on the owner's real microphone (only synthetic speech was measured; a real "oh" may sometimes read
as "ah"), each character's loud mouth by eye.

## What 0.9.4b changes: objects from afar, real objects for everyone, rendered icons, a better wheel

The owner's notes on 0.9.4 and 0.9.4a (sadc `docs/research/objects2_plan.md` with its review and the owner's answers 11.0-11.2).

* **Draw distance** (Objects page, "How far away rings and item boxes appear", default 4,800 HU, up to 12,000 HU): the game's own
  per-type spawn range (the object list's attribute bit and fRange, as Twinkle Circuit uses for these types) - the spawner itself is
  unchanged. The window reaches the range, orders what is near first, then what is ahead of the camera; maxima 200 rings / 100 boxes
  (defaults 128 / 48); capture room 2,048 records.
* **The whole screen width** ("Use the whole screen width", on): the game's view test of the four object displays uses Garry's Mod's
  field of view instead of the Dreamcast's 4:3 (only those displays; game logic unchanged).
* **Big ring circles**: a group is ordered by its nearest ring, so every ring of a 128-ring circle becomes live and collectable as
  the character walks around it (fixes 0.9.4.1's "always the same part"); the window's under-fill is fixed.
* **The real objects without a character**: a private showcase world (no player, nothing can be collected) runs one live copy of
  each object description; G-SA1 draws those pictures at every placed object when there is no character, while editing, and (option)
  beyond the draw distance. Without a character the Extra Life box shows the Dreamcast logo, drawn by G-SA1 in code (the disc has no
  such texture; no image is shipped). "Smooth the pictures" (off: the game's 30 steps a second).
* **Spawn-menu pictures** of the real objects, rendered from the owner's disc and kept in garrysmod/data/gsa1/icons (a switch);
  the G-SA1 tab's icon is Sonic's 1-up face at 16x16. The context menu's hover outline covers the whole object.
* **Emotes hold their last pose**: an animation that ends in a pose stays on its last frame until the player moves (per slot,
  "Hold the last pose", on for once-animations; libsa1's SA1_EMOTE_HOLD).
* **A better wheel**: a GTA V style ring with an accent colour (Sonic blue, gold for Super Sonic), the chosen animation large in the
  centre, labels that scale with the wheel (fonts per size), size and opacity options.
* **The right-stick click does nothing for Super Sonic** by default (gsa1_super_pad 0; a saved 128 moved to 0 once).
* Fixed on the way: a libsa1 registry id overflow after 16,383 adds in one context (a ghost record).

UNVERIFIED in game: render-target colour and alpha on the owner's setup, the saved PNGs, the pictures' lighting and cost with many
objects, the logo's look on the box.

## What 0.9.4a changes: Super Sonic polish, event faces, the emote wheel, the G-SA1 spawn-menu tab

Owner notes and requests of 2026-10-26 (sadc `docs/research/super2_plan.md` and its addendum `faces_wheel_plan.md`, each with its
review and the owner's answers 10.1-10.3 / 10.1).

* **General Gameplay Super Sonic animations** (Super Sonic page, "Super Sonic's own animations", on): he stands in the game's
  floating Super stand (130) and walks / runs with Super Sonic's own motions (131-134, picked by Sonic's speed bands like the
  game's selector); after standing a while he does Sonic's foot-tapping idle on the Super body (owner O1); moves Super Sonic never
  had (spin dash, Light Speed Dash, braking, carrying, ...) keep Sonic's motions. Gameplay is identical.
* **The run animation at extreme speed** no longer breaks: the render interpolation hint now follows the motion frame that was
  actually drawn (libsa1 latches it at sub step 0). This changes the in-between frames of every character slightly (game state and
  per-pair draws unchanged; 0.9.4a verifier: e.g. Sonic's spin dash 35 -> 13 and Knuckles' run 53 -> 34 models more than 20 degrees
  off the drawn motion; Sonic's / Tails' / Amy's run +2..+4) - accepted by the orchestrator.
* **Golden Light Speed Dash while Super** ("Golden Light Speed Dash", on): the charged glow turns gold, the plain blue / violet
  sparkles and streaks turn gold, the Crystal Ring's green ones stay green (owner O3); the spin dash sparks use the game's golden
  after-image texture. Vs. Perfect Chaos Super Sonic and normal Sonic are unchanged.
* **The aura's whoosh sounds** (1035 / 1036 from the Perfect Chaos stage bank) play for both Super Sonics, through libsa1's new
  per-character stage rules (audio header 5; the board of 0.9.5 reuses them).
* **Ring sound**: a fast ring line no longer gets louder - a sound effect started again while it still plays restarts instead of
  piling up (Sound page, "Rings don't pile up", on; off = the Dreamcast's own behaviour, where they pile up).
* **Event faces** (Options > G-SA1 > Faces): a switch between the normal face and the game's cutscene head (off at start, owner
  FQ4); a face-animation maker (double-click the game's expressions into a list, each entry with frames to enter and frames to hold,
  60 frames = 1 second; preview, name, save); face hotkeys; lip sync - the mouth opens with your voice like Garry's Mod's mouths, in
  single player from your microphone's loudness while the voice key is held (owner FQ9 / FQ10). Super Sonic and E-102 have no face
  (as in the game); Big uses only his valid faces.
* **Emote wheel** (Options > G-SA1 > Emote wheel): hold TAB (controller: D-pad down) for a GTA-style wheel with no slow motion;
  release plays the highlighted slot's animation through the game's own cutscene action queue; left mouse (controller: LT) plays
  the slot's face animation together with its body animation, or only the centre's face animation. Each character has his own
  wheel; the page lists every animation by its internal name, the ones that cannot play yet greyed out with a tooltip saying why
  (owner FQ19); standing only, with "Allow animations in the air" (off).
* **The G-SA1 tab** at the top of the spawn menu (like G64): Rings and Item Boxes.

UNVERIFIED in game (the owner's checklist): the gold and the whoosh by eye and ear, lip sync with Garry's Mod's own voice level and
the microphone fallback, the wheel's look, TAB not opening the scoreboard while you are a character, the greyed rows' tooltips.

## What 0.9.4.1 changes: rings in lines and circles of up to 128, objects you can pick and move, no refused rings

The owner's test of 0.9.4 (sadc `build/research/owner_logs/log_094_20261026_prev.txt` and `log_094_20261026.txt`): "the
rings cannot be moved once placed down"; "selecting the line and circle of rings in the context (C key) menu is very
hard."; "selecting any object in the Context menu (C Key) is very difficult. Nothing can be moved after being added.";
"the ring circle is limited to only having 7 rings per circle. You can't do more? Ideally, the line and the circle should
be able to have at most 128 rings." And in the log, unnoted: the server refused rings Sonic took from lines and circles
("the server refused Ring line 250: the touch was 216 units from it (at most 64)"), and a refusal puts the ring back.

* **Up to 128 rings in a Ring line and a Ring circle** (Count 1-128 for both; 0.9.4: 64 and 7). The game's own limits are
  per game record: a line record holds 8 rings (G-SA1 already split long lines into records of 8), a circle record 7 that
  can be shared (its 8th ring has no bit in the game's user flag). A circle of N rings is now m game circles of n rings
  each (n = the largest of 7..1 that divides N, m = N / n: 12 = 2 x 6, 64 = 16 x 4, 128 = 32 x 4, a prime like 127 =
  127 x 1), circle k turned about the circle's axis by k x 360 / N degrees, so the game's own circle layout puts its
  ring i on the evenly spaced place (i x m + k) mod N (`src/core/objects.cpp` circle_split / make_records,
  `feat/sh_objects.lua` O.CircleSplit / O.RingPositions). Measured with the disc (`feat_objects_binding_test`): circles of
  7, 12, 64, 127 and 128 rings at two angles each - every ring of the game within 0.2 HU of its place, and Sonic put on a
  ring gets the event naming that ring. The shared state of every record is now one String NetworkVar, TakenBits (two
  hex digits per record; 0.9.4's UserBits0..7 had room for 8 records); a copy of a 0.9.4 object starts fresh.
  **Limit**: the game handles at most 70 ring objects near the character at once (Objects page, "Rings the game handles
  at once": 64 at first, 70 at most - libsa1's limit, which keeps the HUD drawn when everything is in view). A circle with
  more rings than that slider (about 68) always shows the SAME part of itself, wherever the character goes (all of its
  game records share the circle's centre, so libsa1's window always picks the same ones): the other rings never appear
  and cannot be collected until round 0.9.4b fixes the window (nearest ring of each record, not its centre). A long line
  works fully: the part nearest to the character follows him (all 128 collected in the verifier's run). Raising the
  maximum is libsa1 work (the capture budget) for a later round. Also UNVERIFIED in game: the context menu's hover
  outline is drawn by GMod from the entity's (hidden) model, so it shows a small box at the object's origin, not the
  whole line or circle.
* **No refused rings any more.** It was not a wrong layout: measured with the disc, the game's rings sit within 0.01 HU of
  where G-SA1 says (lines of 10 and 20, circles of 7, at yaw 0 / 37 / 90 / 200, pitched, rolled) and a touch on a ring
  names exactly its record and bit. The cause: the game sets a ring's bit in its group only after the ring's sparkle
  (16 steps), and libsa1 reports it with the group's LAST touch - at a run the touch of a ring up to ~180 HU further on
  (measured: 171 HU in the binding test; the owner's log 67-226 HU). The server now checks a group's report against
  every ring of that group, and each ring it adds against the character's path in the half second before the touch
  (`O.CheckEvent`; `feat_objects_test.lua` replays the owner's refused reports: accepted now, refused by 0.9.4's rule;
  a touch far from every ring, or a claimed ring the character never passed, is still refused).
* **Pick and move every object.** 0.9.4's objects were frozen physics boxes made SOLID_VPHYSICS; most likely (UNVERIFIED:
  it cannot be measured outside the game) Garry's Mod traced them against their MODEL (a 12-unit cube at the centre; the
  client had no physics object at all), so the Physics Gun, the Tool Gun and the context menu (C) could hit a line or a
  circle only at its middle, if at all. Now each object has a **pick hull of
  the whole object** - a line's full length, a circle's diameter (a ring 24 HU around), a box's size - and what each choice
  relies on (`feat/sh_objects.lua` "THE PICK HULL", `entities/gsa1_base.lua`, `feat/sv_objects.lua` O.ApplyHull):
  * SOLID_OBB with the hull as its collision bounds, and `Entity:EnableCustomCollisions` so the engine asks
    `ENT:TestCollision` (the wiki: it needs custom collisions, SOLID_OBB or SOLID_VPHYSICS and fitting collision bounds;
    the solid type and the bounds are networked, so the client's traces see the same hull);
  * `ENT:TestCollision` answers only rays from the shoot position of a player holding the Physics Gun or the Tool Gun,
    and every client ray while the context menu is open, with the exact hit on the turned hull; hull traces (player
    and NPC movement) and every other ray (bullets) pass through - the pattern of Garry's Mod's own widgets
    (`lua/entities/widget_base.lua`: COLLISION_GROUP_WORLD, EnableCustomCollisions, a TestCollision for rays only);
  * COLLISION_GROUP_WORLD (what "Disable Collisions" sets): props and NPCs do not bump into the physics box;
  * a physics box of the hull (at most 2,048 HU from the centre; the Physics Gun moves physics objects), frozen without
    gravity; `ENT:PhysgunPickup` allows the Physics Gun (the sandbox asks it), `OnPhysgunPickup` lets the box move while
    carried, the drop freezes it again and the game's object follows at once; anything else that unfreezes it (the
    Physics Gun's reload, a dupe) is undone within 0.1 s; a new Count / Spacing / Radius rebuilds the hull (after the
    drop when it is being carried);
  * no custom collision check (`SetCustomCollisionCheck` + `ShouldCollide`): that hook decides pairs of entities
    (physics, movement), not which ray picks the hull, and the wiki warns it can break physics;
  * the context menu leaves out "Enable Collisions", gravity, drive, ignite and the like for G-SA1 objects (they would
    make a place in the game solid or move it by physics); undo, the duplicator, Edit Properties, Contents, Respawn now
    and Remove work as before.
* The feature "objects" is version 2 (the module and the addon go together); module and addon 0.9.4.1.

Owner checklist (UNVERIFIED in game - only the owner can confirm): the Physics Gun grabs a Ring, a Ring line (anywhere
along it), a Ring circle (anywhere across it) and both boxes, moves them, and the game's rings follow where it is dropped;
the Tool Gun (e.g. the remover) and the context menu (C: the hover outline, right-click, Edit Properties) work anywhere on
them; players walk through every object, props and NPCs are not blocked, bullets fly through; a circle of 128 rings
(radius 800) with the ring slider at 70; running Sonic through a line and a circle: no "server refused" lines in the log.

## What 0.9.4 changes: spawnable Rings and Item Boxes

The owner (2026-10-25): "Spawnable Rings and Item Boxes. You already have them in-game, there's just no way to spawn them."
and "The rings and boxes should have their own round" (sadc `docs/research/gsa1_094_plan.md` with its review).

* **Q menu > Entities > G-SA1**: Ring, Ring line (Count 1-64, Spacing), Ring circle (Count 1-7, Radius), Item Box and Item Box
  (Air), each with "Respawn after"; boxes have a Contents choice of the game's nine items (right-click > Contents) and a
  default on the Objects page. Undo, Cleanup (G-SA1 objects) and `sbox_maxgsa1_objects` work like other entities.
* Collected and broken **by the game's own code in each character's world**: the SET layer of libsa1 (the game's set manager
  8C090FA0, the ring / group-ring execs, the decompiled ground box 8C05D10C and the air box), with the game's sounds, sparkle,
  HUD, 1-ups, item icons and power-ups. Every character breaks boxes the game's way (set_test measured them all, Tails' tail
  swipe and Amy's hammer included).
* **Shared in multiplayer**: the server checks every touch against the character's recent path (rings 64 HU, boxes 80 HU,
  E-102's shots, the Magnetic Barrier's pull up to 320 HU - the verifier's measured 275 HU case) and tells every player.
* **Objects page** (Options > G-SA1): on / off, draw, the ring and box windows, the default contents, the item-icon guard (on:
  breaking many boxes at once can no longer overflow the game's icon list), markers, debug; server: on / off, respawn,
  reach slack, the object limit and "Reset G-SA1 objects".
* Rendering: rings and boxes no longer slide when one is collected (the captured draws follow their own task), and they are
  drawn in first person and with "Effects" off (the OBJECT draw class).
* Also: the "the rings ran out, back to normal Sonic" chat line is gone (owner note on 0.9.3b; the session log keeps it).

Owner checklist: `gsa1_094_plan.md` 6.7 (placing, collecting with each character, the nine contents, respawn, a row of 30 boxes,
the Magnetic Barrier, the physgun / tool gun on the objects, two instances). UNVERIFIED in game: whether the physgun and tool gun
pick the objects (a frozen physics box in the 'Disable Collisions' group) and the spawn icons in Entities > G-SA1.

Known limits (the game's own): objects appear within about 1,600 HU of the character and are culled by the game's camera view.

## What 0.9.3b changes: Super Sonic's own "Hm!"

The owner (2026-10-26, testing 0.9.3a): "None of the grunt options are the correct one" and "Super Sonic's voice from the
last version had the HM! sound for an idle line". In 0.9.3 a Sonic who could transform was a level-19 world, so the game's
voice choice (8C07DCE0) gave him Super Sonic's lines: 396 (the default of level 19) or the level-19 list's 388. Decoded
from the disc: 396 is 0.35 s, one closed burst (the "Hm!"); 388 is a 2.7 s line.

* The transformation voice can now be a voice clip: `gsa1_super_voice` = 4096 + the clip's number; the default is
  4492 = Super Sonic's line 396. The page lists it first ("Hm! (Super Sonic's line 396)"), then line 388 and the four
  tones of 0.9.3a. A saved 1116 (0.9.3a's default) becomes 4492 once.
* A clip is played by G-SA1 when the player's SUPER order goes out (`gsa1.SuperVoiceClip`, module feature super 3:
  `Session::preview_voice`, an SA1_EVENT_VOICE into the mixer, as the game's PlayVoice 8C107BA0 makes it), as the
  character's own voice; libsa1's transformation voice (SA1_SUPOPT_VOICE) takes tones only and gets 0 then. A tone choice
  is played by libsa1 as in 0.9.3a.
* Built against 0.9.3a's libsa1 snapshot (no libsa1 change).

## What 0.9.3a changes: two Super Sonics, and the owner's notes on 0.9.3

The owner (2026-10-25): "I want two versions of Super Sonic. Super Sonic (Vs. Perfect Chaos) should stay exactly as he
is. Super Sonic (General Gameplay) should play more like regular Sonic (Spindash, optional auras, faster than base
form)", modelled on the behaviour of the SADX mod kellsnc/sadx-super-sonic. Clean room: only the mod's prose was read
(its README, release notes, issues); none of its code or tuning was used - every number is the Dreamcast game's own
(sadc `docs/research/super_general_design.md` with its review, section 10).

| Owner request / note | 0.9.3a |
|---|---|
| Two Super Sonics | **Super Sonic (Vs. Perfect Chaos)** is 0.9.3's Super Sonic (the game's Super modes); **Super Sonic (General Gameplay)** is new: golden Super Sonic who plays as Sonic - spin dash, homing attack, Light Speed Dash and Attack with the shoes, carrying - with the game's Super bit (a hit only slows him down), faster than Sonic on the ground, an optional aura and the game's golden trail and after-images |
| "only be able to turn into Super Sonic when jumping, not standing" / "50 rings, jumps and presses the spindash button midair" | Sonic (transformation on) turns Super with at least 50 rings by **jumping and pressing the action (spin dash) button in the air**; the key (G) and the controller button work only in the jump too; standing, the action button is always Sonic's crouch / spin dash |
| "Sonic has a HM! sound byte that should be used while transforming" | his push grunt (the game's tone 1116) plays with every transformation the player makes; the page has the voice choice and a Preview |
| "Detransforming from Super Sonic removes his upgrades and it doesn't update his idle voice lines" | Super Sonic (Vs. Perfect Chaos) gets Sonic's ticked upgrades (he has them again when he turns back); idle lines follow the form: Super Sonic's while Super, Sonic's own while normal |
| "Sonic has Super Sonic's voice clips in general" | a Sonic who can transform is no longer a Perfect Chaos (level 19) world: he keeps Sonic's own voice lines |
| "Super Sonic's aura's textures switch much faster than they should" | an aura animation choice for both versions: **Calm** (default: all 8 frames in order), Dreamcast (the game exactly), Slow; measured through G-SA1's own drawing at 60 and 144 fps: 30 / 30 / 15 changes a second |
| "there should be no note in the chat when you try to turn into Super Sonic without the rings" | no chat line for too few rings, the ground or a dying character (the session log notes it) |
| "rename the Notes and Tools tab to 'Debug'" | done |
| (0.9.2) "Moving while carrying objects causes the object to jitter" | a carried prop is drawn at the same game steps as the body (libsa1 now reports them): offset within a pair 0.0000 HU instead of 2.6 HU on average at a run |

Also: a General Gameplay Super Sonic runs on water while Super (libsa1's "water floor while Super"), turning back on
it drops him in; a re-creation keeps the form (an upgrade ticked, a teleport, a fault restart: a Super Sonic who turned
back stays normal Sonic); leaving a vehicle brings back the same list entry. Two form orders are always at least one
game step apart (S.ORDER_GAP, 0.05 s): the 0.9.3a verifier found that turning back and Super again with no game step
between left two auras running (libsa1's own guard follows in 0.9.4).

Known (0.9.3a verifier): leaving a vehicle re-spawns the character, so a Super Sonic who had turned back returns Super
with his start rings, like any spawn.

## What 0.9.3 changes: Super Sonic, and the collision fixed properly

Each map's collision rebuilds once on its first load with 0.9.3.

| Owner report / request | 0.9.3 |
|---|---|
| Super Sonic (a 7th character and a transformation) | Super Sonic in the character list (the game's own code on its Perfect Chaos rules: the ring drain, back to normal Sonic at 0 rings, running on water; options on the Super Sonic page); normal Sonic transforms with 50+ rings and a key (G) / the right stick click, keeping his speed, and back on the key or at 0 rings; music while Super (option) |
| "every single ceiling can be jumped through" (gm_construct_in_flatgrass_v3, gm_bigcity) | ceilings over thin roofs stay solid (front-only undersides; the game's touch from behind no longer lands the character on the roof): construct 3,261 -> 56 jumps through of ~5,000, highway 227 -> 2 of ~420; Collision page 'Solid ceilings over thin roofs' (on) |
| "I still fall through the ground with tunnels" / sinking (gm_highway14800) | the tunnel floors were thrown away because a bit of terrain shared their plane: now kept; buried floors under terrain are left out: tunnel deaths 139/200 -> 0/200 |
| loops put the character on top (gm_genesis) | loop surfaces are recognised as curved and keep their inside: loops are completed at the game's loop speed (20/28 small-loop runs, never on top) |
| Knuckles climbing through thin walls | 4/240 -> 0/240 on rp_downtown_v4c |
| 'the land collision's query took 15 objects' log spam | every object in reach is in the character's collision now; the lines are gone |
| sound crackles | the sound queue is measured correctly (BASS's playback buffer no longer counted), fewer drop-outs |
| teleports do not work | the map's teleporters (and addons' teleports) move the character to the destination (the character arrives standing; keeping the speed needs a later libsa1 call) |
| power-up glow invisible (barrier, invincibility, magnetic barrier) | drawn |
| a stale fault message after a restart | fixed |

Still open: some steep sloped ceilings and thin slabs (8-12 HU) can be jumped through; one building on
gm_construct_in_flatgrass_v3 (x -9040..-7184, y -3984..-2064) has no floors in G-SA1's collision; rare wall entries.

## What 0.9.2 changes (the owner's test of 0.9.0)

Each map's collision rebuilds once on its first load with 0.9.2.

| Owner report / log | 0.9.2 |
|---|---|
| Falling through a floor with a floor underneath; at high speed; clipping through walls with spin dashes / homing; stuck between the two faces of thin fences | walls get their own GRID objects (the game's TOUCH no longer averages a wall with the floor), thin stacks become one double-sided face, at most 16 land objects per collision query (also fixes a host crash with E-102 on busy maps). gm_highway14800: wall entries 31 -> 4, falls 26/200 -> about 1/200. Known: Knuckles' jump-climb can still pass very thin double-sided faces |
| rp_rockford_v2b: no character could spawn (GRID over 4,194,304 triangles) | thin-wall faces no longer stretch far outside prop hulls; the map loads; an honest limit message otherwise |
| gm_goldencity_v2: the game stopped after a respawn; Knuckles digging up an item box stopped the game | the item box code is decompiled (air item boxes with all 9 items, the item icon, the bomb); a hit can no longer reach a character that was just re-created; a fault guard restarts the character on the spot instead of removing it |
| Water where there is none; jumping in water flips out of and back into water | 'in water' follows Garry's Mod's own water in dry places under water (option, on); the water object stays in the character's window |
| Sun shafts and other effects wash over the character; the character invisible through the top of water | the character is drawn correctly in Garry's Mod's extra views (depth, water refraction/reflection) |
| The Garry's Mod player dies to NextBots | a kill of the player kills the character too and both respawn together (owner choice); rings kept across collision reloads; a 'Give rings' button |
| Big held props clip through the ground; the Surfaces page lacks Adventure's surfaces | held props keep clear of the ground; the Surfaces page has all of the game's ground types |

## What 0.9.1 changes (the owner's test of 0.7.0, and the game's HUD)

| Owner report / request | 0.9.1 |
|---|---|
| "Drowning doesn't drown" | deep GMod water (deeper than ~1,600 HU, e.g. gm_genesis' sea) is now seen by the game: water physics, the air timer, the countdown and the drown death; deaths and lives are handled (respawn at the spawn point; lives count down, game over gives 4 again; Character page: 'Characters can drown', lives mode incl. infinite) |
| "the music doesn't duck like you said it would" | the jukebox pauses while the game plays a jingle (drowning countdown, invincibility, speed shoes) and resumes after; the 1-up keeps it playing |
| "Afterimages in general aren't transparent" | lit see-through batches carry their alpha in the material: Tails' blur copies 67 % / 33 %, Amy's hammer ghosts 30 % / 20 %, as on the Dreamcast (Knuckles' copies stay solid, as in the original game) |
| "Tails' tails flatten out" | the ball's interpolation fix; plus Character page 'Tails' tail blend' (on = the game's morph, default; off = the tails switch instantly) |
| "Amy has no bird with her, it should be toggleable" | the game's own Birdie, Character page 'Amy's bird (Birdie)' (on by default) |
| "Add in the HUD" | the game's own HUD drawn by its own code: rings, time, lives with the character icon, score, E-102's timer, Big's fishing display, the drowning countdown digits; a HUD page (on/off, scale, layout for wide screens); replaces 0.9.0's small counter |

libsa1: deep-water window, death events for drowning and death zones, lives, the companion API, the tail-blend option, screw
interpolation for anchor groups, FTRC alpha, audio header 4 (the game's music and jingle state), 2D capture and the screen API,
the HUD pass with the clock (E-102's 3-minute limit off by default), CON_REGULAR. SADC: Big's HUD and the HUD number draw landed.
Known: 'Characters can drown' off holds the air timer from the module through libsa1 internals (a libsa1 option is to come).

## What 0.9.0 changes: interaction (round 5)

Characters now take part in the world (details: "Interaction: enemies, damage, props, balloons, doors (round 5)"):
getting hit costs rings by the game's rules; attacks damage NPCs, scaled per attack; touching hostile NPCs hurts; PvP is on;
switches per category (friendly / hostile / neutral NPCs, vehicles, players, props) for attacking, targeting and touch harm;
Sonic's homing attack and E-102's lock-on reach NPCs, vehicles and balloons; balloons pop and launch the character upward;
props a player could pick up with E can be lifted, carried and thrown; physics props are pushed by running and rolling
into them; the interact key (E by default) uses doors, buttons and vehicles in front of the character; a small ring
counter (to be replaced by the game's own HUD). All on the Options page "Interaction". Release fixes after the round's
verifier: several targets hit in one frame are all counted (a client-wide and a per-player limit dropped all but one);
with "Interaction with the world" off, E no longer uses things twice. Known: pushing is weak below full running speed
(the game slows the character before the contact; to check in game).

## What 0.8.0 changes (the owner's test of 0.6.0)

| Owner report | Cause | 0.8.0 |
|---|---|---|
| "Knuckles' particles have inverted alphas" (and the log's 'render targets: no format kept the alpha channel') | G-SA1 cleared its texture render targets with depth/stencil flags; the targets have no depth buffer, so Direct3D 9 dropped the whole clear and every transparent texel stayed opaque black (since 0.4) | colour-only clears, alpha-0 texels painted correctly; `texture_alpha_test` fails on 0.7.0 and passes ("Shadows, see-through textures and precise drawing") |
| "Characters have no shadows" | libsa1 removed the game's blob shadow; its texture setup 8C099500 was a stub; OBJ_REGULAR was not loaded | the game's own blob (8C099500 decompiled, OBJ_REGULAR loaded), drawn by G-SA1; Rendering page switch |
| "Knuckles can't dig into grass, dirt and sand" | G-SA1 never read the map's materials, so no ground carried SA1's diggable bit | materials -> surface types -> SA1 ground bits; an Options page "Surfaces" ("Ground types" below) |
| "Big's eye textures have Z-fighting" | eyes interpolated separately from the head; float precision far from the map origin | anchored interpolation in libsa1, camera-relative drawing in G-SA1 |
| "Entering character mode with a weapon keeps the weapons effects visible" | the weapon was never put away | holstered while a character (physgun beam hidden, switches gated, flashlight off), given back after; `weapon_test` |
| log 'jump' lines; a lurch after Garry's Mod stalls | a tick of several pairs rendered between pairs k apart; the detector also misread long frames | libsa1 renders between the last two pairs; an honest jump detector; pauses are not hitches |
| (0.6.0, owner note) spawned cameras do not work in SA mode | G-SA1's chase camera overrode the view of a view entity | the chase camera steps aside while you look through a camera; `frame_test` |

Also in 0.8.0 (libsa1, not visible yet): the round-5 game layer for damage, attacks, holdable props and balloons, with new
references replayed strictly (the G-SA1 side comes in the next version).

## What 0.7.0 changes: the jukebox, the feature seam, the exact pre-warm

* **The feature seam** (G0, sadc `docs/research/gsa1_rounds_plan.md` section 5): the coming parts - the interaction
  layer, Super Sonic, followers, the jukebox - each live in their own files (module bindings, core, Lua, Q-menu page,
  settings, tests) and register themselves; see "Features" and "Versioning" below. Nothing is registered yet, so the
  game behaves as 0.6.0 does; `gsa1.FEATURES` is empty and the status lines say "features: none".
* **The pre-warm makes the exact material of every census state** (the round 4c verifier's finding). 0.6.0 warmed
  every census state's material *state* (shader, lighting, culling, blend factors), but the exact material - the
  texture's render target in the state's own address mode, made with its mode, lighting, culling and half-Lambert - of
  only 201 of the 346 states: 145 were still made at their first use (Sonic 4, Tails 15, Knuckles 1, Amy 64, E-102 46,
  Big 15: translucent palette-lit body textures, both-sided and sphere-mapped ones, unlit ones, point-sampled and
  repeating address modes - E-102's and Amy's point-sampled textures are render targets of their own -, Big's lit lure
  and rod). Now `cl_warm.lua` also warms, for the spawned character kind, every state of core_test's census exactly
  (`addon/lua/gsa1/cl_warm_census.lua`, numbers only, generated from `build/<target>/material_census.txt` by
  `tools/gen_warm_census.py`), spread over the first frames within the same 1.5 ms budget, one item per material and
  draw state: Sonic 591 items, Tails 510, Knuckles 557, Amy 600, E-102 727, Big 741 (0.6.0: 589, 498, 559, 539, 680,
  729 with duplicates). `warm_test` asserts the exact material of all 346 census states under lighting on and off and
  "both sides" (on 0.6.0's addon: 201 / 210 / 209 of 346), and that the addon's census data has every state of the
  census core_test wrote (if libsa1 changes what a character draws, run `py -3.12 tools/gen_warm_census.py`). Render
  states outside the census (13 s of scripted play per character on a flat floor: no climbing, water or EFF_REGULAR
  particles) still get their shader states warmed and their materials made at the first use, logged.
* **The session log's header names the module's vector mode** (how `gsa1.EmitBatch` hands Vectors to the mesh
  library; the review's R.4.4 of `gsa1_lsd_lag.md`): the module decides it when it opens instead of at the first
  `EmitBatch`, so the header (written with the module's first message) and the `module` line say "vector mode 1 (two
  scratch Vectors written in place)", with the module's features.
* `build.py` holds a lock (`build/.build.lock`) for the whole build and test run, so two builds of g-sa1 at the same
  time (agents, terminals) wait for each other instead of overwriting each other's outputs.
* **The jukebox** (round 6c, the owner's request; sadc `docs/research/jukebox.md` 6.5 with its review, plan
  `gsa1_rounds_plan.md` 10.3): Q -> Options -> G-SA1 -> **Jukebox**, your own jukebox - the game's music from your
  disc, which only you hear. The 104 tracks of the game's own sound test under its titles (read from your disc), in
  its six pages, and the 5 files it does not list (`NIGHTS_A`, `NIGHTS_S`, `SONIC_CD`, `SSRACING` - cut short on the
  disc - and `TITLE2`, a piece of the menus) in their own group under their file names; play, pause, stop, previous,
  next, a position slider, double-click a track to play it; play modes **Repeat the track** (the default: a looping
  track loops at the game's own loop point, one without a loop starts again - the game's own sound test plays those
  once), **Play the list** (each looping track twice through its loop, then a 4 s fade-out; the 15 jingles and title
  cards are left out unless ticked) and **Shuffle** (every track of the group once, then again); the jukebox's volume
  (1 = the game's music level), Garry's Mod's music volume, "silence the game's music while the jukebox plays" (the
  jingles - the drowning countdown - stay unless that box is ticked too), "keep playing while paused". The module's
  part (feature `jukebox` 1: `src/core/jukebox.*`, `src/module/bind_jukebox.cpp`) reads and decodes the music on a
  thread of its own with its own libsa1 objects and keeps a few seconds queued, so the music plays on through the
  game's stutters; the addon's part is `addon/lua/gsa1/feat/sh_jukebox.lua` (pure functions: groups, next / previous,
  shuffle order, plans, times, search) and `cl_jukebox.lua` (the player, the page, the commands), tested by
  `tests/feat_jukebox_test.lua` in Garry's Mod's LuaJIT against a mock of the module's jukebox. A module without the
  feature: the page says it needs module 0.7.0. The world jukebox (a radio everyone hears) is not built: the owner
  chose the personal one for now.

## What 0.6.0 changes (the owner's test of 0.5.0)

Research: `sadc/docs/research/gsa1_vertical_flicker.md`, `gsa1_lsd_lag.md` and `lightspeed_visuals.md`, each with its
adversarial review. libsa1's part was done in the same round (round 4c: the capture emitter's sprite sizes, the Light
Speed aura's material, polygon and line topology; the render root at the drawn step); G-SA1 builds on it. Every
figure below is measured offline on this machine (x64) unless it says otherwise.

| Reported (0.5.0) | Cause | Fix and measurement |
|---|---|---|
| "lightspeed dash particles are still huge" | libsa1 sized every sparkle from the texture times the matrix scale of an unrelated draw: 64 x 64 SA1 units, 256 Hammer units wide, 6.6 times Sonic's height | libsa1 (round 4c F1) sizes sprites as the game does. At the owner's settings (3440 x 1440, fov 92.5, camera 220) the widest sparkle is now **49.6 units (12.40 SA1 units)** instead of 256, and the blended effects cover at most **0.20 of the screen** while charging (0.5.0: 4.31 screens); 0.47 at camera 150 (7.89), 1.21 with the camera pulled to 60 units by a wall (13.4). The charged aura is now the game's translucent additive glow (libsa1 F2: unlit, additive, ONE / ONE), the charge's ribbons are thin textured strips (F4), Big's fishing line is one continuous line (F5) |
| "there's a lag spike when charging up" - "Whole game froze briefly" | **Not reproduced outside Garry's Mod.** libsa1's game code for the charge costs under 0.3 ms per game pair, G-SA1's module under 0.6 ms per frame, the GPU's additive fill under 0.7 ms even in 0.5.0's worst case (measured on an RTX 5060 Ti: 134 Gpx/s), the sound is preloaded (no disc read), and G-SA1's Lua makes about 3 KB of garbage per frame (measured against a mock of the game), which costs Garry's Mod's own LuaJIT 0.002 ms per frame and starts no collection by itself. What the charge does for the **first time** in a session is on Garry's Mod's side: in its first half second it brings five new materials (Sonic's spin texture, the ball's two shells, the sparkle sprite, the ribbons) and the aura at completion. A new material is a `CreateMaterial`, then at its first draw Source loads the shader combination and DXVK (the owner's Vulkan layer) builds the pipeline for it - neither can be timed offline, and either can stall a frame | **The material pre-warm** (`cl_warm.lua`): when a character appears, every material it can use is made and drawn once, invisibly (a zero-area triangle in its own draw passes, with its lighting), at most 1.5 ms per frame and one slow item per frame: every material state (opaque, alpha-tested, translucent, additive x unlit / lit / half-Lambert x culled / both sides) on vgui/white and on a render target, the blended ones with the game's blend factor pairs; every texture of the character's model archive in the body's state (the spin texture); every texture of its effect archives in the effects' states. Sonic: 589 items, Tails 498, Knuckles 559, Amy 539, E-102 680, Big 729. `core_test` writes a **material census** (346 render states the six characters drew in 13 s each of scripted play with all their upgrades: runs, jumps, actions in the air, held actions - the Light Speed charge and its aura, Maximum Heat, the lock-on, the cast) and `warm_test` checks the pre-warm against them in Garry's Mod's own LuaJIT, under lighting on and off and "both sides": in 0.6.0 every census state had its material state (shader, lighting, culling) and its blend factor pair warmed, but only 201 of the 346 had their exact material (the render target in the state's address mode, the material made); the other 145 (Sonic 4, Tails 15, Knuckles 1, Amy 64, E-102 46, Big 15) were made at their first use, logged. (This row first said "11 others": that was only the effect-archive subset; corrected after the round 4c verifier. Sonic's 4 are body states his first frames draw or the charge does not use, so the Light Speed charge itself was covered. Since 0.6.0 all 346 are warmed exactly: see above.) In `frame_test` (the whole addon frame in Garry's Mod's LuaJIT against a mock of the game and the module) the charge makes **0 materials at their first use**. The textured charge ribbons use the render target the spawn painted (UVs inside the texture: clamped, like sprites), so they create no render target either. **The session log** (below) records every material still made at its first use, every render target made at its first use, and every slow frame with what took the time, the time outside G-SA1 and whether the Lua collector ran in it - the next test settles what the freeze was. Also: **fewer Lua calls per vertex** (E1: `mesh.Normal` only for lit materials, `mesh.TexCoord` only for textured ones: a charged frame 24,183 mesh calls instead of 29,655, -18.5 %), **less Lua garbage per frame** (the events, the camera's traces, the section timers, the materials' names are reused: 4,475 -> 2,895 bytes per frame in the same mock), and the module measures **how much of the screen the effects cover** (E5, for the log) |
| "the horizontal speed position flickering thing from earlier happens with vertical movement too" | Two causes (`gsa1_vertical_flicker.md`). **A, the main one (a 0.5 regression):** since the 0.5 round libsa1 moves every draw it cannot interpolate along with the root itself, and G-SA1 still did so a second time (`Session::follow_root`): during such pairs the body ran at twice the camera's speed and snapped back at every pair. Knuckles' jump draws the ball and the curled body in turn, so his whole jump was such pairs (up to 16 in a row): a 30 Hz up-and-down sawtooth of 10-25 units, 55 units on a long fall; every character's jump start and landing had one. **B (since 0.2):** the camera followed the root one 60 Hz step after the step the game drew, so on steps, ledges, landings, falls and the Light Speed release the body moved against the camera by up to a body length | **A:** `follow_root` is gone; the frame is drawn exactly as libsa1 renders it. **B:** libsa1 (round 4c) now reports the root of the drawn step, which the camera follows. `core_test` ("frame loop against the camera"): in Knuckles' standing and running jumps and Sonic's running jump, at 60 / 144 / 240 / 100-200 fps and uneven frame times, the drawn vertices equal libsa1's own render in every frame (**0.000000 units**; with 0.5.1's second move re-applied: 10.5-26.8 units) and the body against the camera drifts **0.00 units** within a pair (6.0-24.7); Knuckles jumping at the edge of a 3000-unit tower and falling: 0.00 (0.5.1: a second move of 53 units). The body against the camera per frame: a 3000-unit fall **1.62 / 0.80 units** at 60 / 144 fps (0.5.0: 13.29 / 5.54), Amy on raw stairs **1.67 / 0.70** (15.36 / 6.40), the Light Speed release **1.11** at 60 fps and 60 fps on the owner's 84 Hz display (31.5 / 44.9: the "lurch"); the drawn body's centre against the camera's root while running and after a spin dash: **-1.4 / 0.0 units** (15.8 / 39.6). Left as the game draws it: Knuckles' rise alternates between the ball and the curled body every pair (steps of about 2 units at the pair edges; the review expected them) |
| "the sound works great too!" | - | The BASS output is confirmed in the game; the README's "untested" notes are gone |

**The session log** (`cl_log.lua`; `gsa1_lsd_lag.md` section 6 with its review). The owner no longer copies console
text: after a test, Claude reads `garrysmod/data/gsa1/log.txt` (older sessions: `log_previous.txt`; at most about
1 MB on disk; a session writes at most 4000 lines, its summary always). It holds: a header per session (the addon,
module and libsa1 versions and the module's build, Garry's Mod's version, the map, the screen, the frame rate cap,
the G-SA1 settings, the ticked upgrades, the Lua heap); every `[G-SA1]` console line and every libsa1 log line;
`hitch` lines (a frame over `gsa1_log_hitch_ms`, 50 ms, with G-SA1's sections, the time outside G-SA1, the Lua heap
and how much the collector freed in that frame, the character's mode / action, its triangles, batches, sprites and
how much of the screen its effects covered); `stutter` lines (a frame of 25 ms or more, about twice the median of the
second before it: one missed vsync); `jump` lines (since 0.8.0: the drawn character moving further in one frame
than the game's own speed explains - more than 24 units and more than 1.5 x the largest speed of the last 4 ticks x
that frame's time + 8; the line names the frame that moved, its time, the speed, the pairs and alpha; 0.6.0 used a
fixed 40 units, which Sonic's roll passes every frame, and named the frame after a long one: `gsa1_060_pops.md`);
`pause` lines (0.8.0: the game paused - single player's escape menu or console - or in the background for a second
or more; such a frame is not a hitch and stays out of the statistics, and the character's first tick after it runs
no time instead of 0.25 s); `slow` seconds; `perf` lines every 10 s (frame rate, G-SA1's time per frame by section,
the mode / action, the ticks that ran 2 or more game pairs, the mesh calls per frame and how many were saved, the Lua
heap, and since 0.8.0 how many views drew the character per frame); a `views` line once per session when the
character is drawn in more than one view in a frame (each view's origin, render target and Lua caller: 0.6.0's mesh
calls were exactly twice one view's); `material`, `texture` and `paint` lines (a material or render
target made at its first use, the texture painting, with their times); `warm` lines (the pre-warm's totals and any
item that took 4 ms or more); `spawn` lines (spawns, switches, respawns, re-creations with the time of each step);
`capacity` lines; Lua errors in G-SA1's hooks (`error`: the hooks keep running); `mark` lines (`gsa1_log_mark
<text>`, or the menu button); and a `summary` when the session ends (frame-time histogram, hitches, stutters, the
sections, the pre-warm, the module's counters, the sound's). It is written every 2 seconds in one `file.Append`.
It holds no paths or names (any server's Lua can read `garrysmod/data`). **Q -> Options -> G-SA1 -> Disc and
status -> Diagnostics**: "Keep a session log (for bug reports)" (`gsa1_log`, on by default), "Slow frame threshold for
the log (ms)" (`gsa1_log_hitch_ms`), "Mark this moment in the log"; `gsa1_log_where` prints where it is.
`log_test` checks it in Garry's Mod's own LuaJIT (62 checks: the header, the module's build, repeats, hitches with
the collector, stutters, jumps, performance lines, slow seconds, guarded hooks, material and render-target lines,
the pre-warm's summary, rotation at the size cap, the line cap with the summary, `gsa1_log 0`; since 0.8.0 the jump
detector's cases from the owner's log - a roll at 2430 units/s, a long frame, the lurch after one, a move across an
alt-tab - pauses with and without the escape menu against a real 389 ms freeze, and the views per frame).

**Round 4c F6.** With "Vertex colours on effects and models" off (`gsa1_vertexcolor 0`) only textured draws turn
white; an untextured draw keeps its colour (the Light Speed aura, the ribbons and lines are nothing but their vertex
colour). `core_test` checks it on a hand-made batch set.

**Offline tests in Garry's Mod's own LuaJIT.** `build.py --test` builds `tests/lua_host.c`, which loads the install's
`bin/win64/lua_shared.dll` read-only (`GMOD_LUA_SHARED` overrides the path; skipped with a message without it), and
runs `log_test.lua`, `warm_test.lua` and `frame_test.lua` against `tests/lua_mock.lua`, a mock of the GMod client and
of the module. `frame_test` runs the whole addon frame (Think, CreateMove, CalcView, the character's two draw passes,
PostRender) for 600 frames of a Light Speed charge: no Lua error, a draw every frame, the spawn and the pre-warm in the
log. `tests/gc_bench.lua` (a tool, on a 200 MB live heap in Garry's Mod's LuaJIT): 3 KB of garbage per frame costs
0.002 ms per frame and starts no collection of its own in 1200 frames (LuaJIT's next cycle starts when the heap has
grown by its pause factor); 30 KB: 0.016 ms; 300 KB: 0.22 ms with the collector's incremental steps, the slowest frame
11 ms; one full `collectgarbage("collect")` takes 216 ms on 200 MB and 655 ms on 600 MB. So the collector could only
freeze a frame with a full collection (which G-SA1 never asks for); the log's hitch lines say when it ran.

**Module API** (6, unchanged: everything new is optional). `PrepareView` takes `lit` (the lighting setting) and the
screen (`fov, width, height`); `GetState` adds `draws, sprites, lines, blended, sprite_batches, vertices, mesh_calls,
sprite_max, blend_layers, sprite_layers, render_flags, drawn_root`; `Status` adds `build` and `mesh_saved`;
`PollEvents(out)` refills the caller's table and its event tables; `Render`'s `movedWithRoot` is libsa1's
`SA1_RENDER_MOVED_WITH_ROOT` with nothing interpolated (it is only reported).

## What 0.5.1 changes (nothing slow on the game's thread)

0.5.0's own measurements (round 4b's verifier) still found long frames G-SA1 caused itself, all on Garry's Mod's
game thread: the first character after a map's collision was applied ran libsa1's GRID synthesis there (125 ms on
gm_construct, 202 on gm_freespace_13, 253 on gm_driversheaven_tdm), the first character of each kind composed that
kind's world image (30-60 ms: `1ST_READ.BIN` and the overlays read, checked and unpacked), `gsa1.Init` loaded the
disc (about 57 ms) and `gsa1.AudioOpen` opened the sound banks (19-31 ms warm; 85 reads of the disc image, seconds
from a slow disc). libsa1 added a preparation API for this (its request 11, `libsa1.h` "Preparation on host
threads"); 0.5.1 uses it and moves the rest off the game's thread too:

| What | 0.5.0 | 0.5.1 |
|---|---|---|
| libsa1's GRID synthesis of the map (cells, land objects, well-shaped pieces) | in the first `gsa1.Create` after `MapApply`, on the game's thread | in the map job's worker, a new last stage **preparing** (`sa1_collision_prepare_tris` on a private libsa1 context, also after a cache hit: the prepared form is not cached on disk); `gsa1.MapApply` installs it with `sa1_collision_set_prepared` in O(1) (0.5-1.6 ms with the moving objects' shapes); every character, respawn, switch and re-creation shares it by reference |
| A map reload (`gsa1_reload_world`, a Collision setting changed, "Delete the cached maps") | built in the background, then the first character synthesized it | built **and prepared** in the background while the character keeps playing on the old collision; swapped in when ready (the character is re-created where it stands, about 3 ms); a job that is replaced while its worker runs is dropped without waiting for it |
| The world images of the six characters | composed by the first world of each kind (30-60 ms each) | composed while the disc loads (`SA1_LOAD_WORLD_IMAGES`, on the worker below) |
| `gsa1.Init` (the disc) | about 57 ms, synchronous | returns at once; `sa1_init` + `sa1_load_disc` (with the world images, about 250 ms) on a worker thread; `gsa1.InitPoll` installs the loaded disc; a spawn waits for it like for the map ("loading your disc"); `gsa1_preload` (on by default) now starts the disc together with the map's collision when the map starts |
| `gsa1.AudioOpen` (the sound banks) | 19-31 ms warm, synchronous | returns at once; `sa1_audio_open` and the mixer on a worker thread with a libsa1 context of their own; `gsa1.AudioPoll` / `AudioUpdate` install them; closing old banks (a language switch, sound off) happens on a worker too. Sounds just start a little later |
| A character's texture list (`GSA1.Tex.Prepare`) | every texture's info (`gsa1.Texture`) and render target in the frame of the spawn | listed in that frame; the infos and render targets are made by the texture painter, at most about 3 ms per frame (the textures the batches draw first, as before) |
| The thin-wall threshold (`BspWorldOptions::thin_wall_max`) | fixed 16 units | **Q -> Options -> G-SA1 -> Collision -> "Thin walls up to (units thick)"** (`gsa1_thin_walls`, 0 = off, default 16); it applies to the map, its brush entities and the physics props' shapes; changing it reloads the map's collision |

Measured offline (`binding_test`, "the game's thread": the addon's frames through the module - the disc and the map
loading in the background, the first spawn, 3 respawns, 6 character switches, a map reload while playing, an upgrade
re-creation; every module call timed; x64, this machine):

| call (ms) | gm_construct p50 / p90 / max | gm_freespace_13 p50 / p90 / max | 0.5.0 |
|---|---|---|---|
| `Init` + `InitPoll` (17-28 polls) | 0.21; 0.012 / 0.015 / 0.021 | 0.39; 0.012 / 0.022 / 0.16 | `Init` about 57 |
| `MapStartData`, `MapPoll`, `MapFeed` (1 MB) | 0.07; 0.018 / 0.069 / 0.12; 0.09 / 0.24 / 0.72 | 0.07; 0.017 / 0.054 / 0.18; 0.17 / 0.65 / 1.39 | the same |
| `MapApply` | 1.47 | 1.07 | 1-13 (set_static) |
| `AudioOpen`, `AudioPoll` | 0.04; 0.007 / 0.14 / 0.14 | 0.06; 0.010 / 0.010 / 0.010 | `AudioOpen` 19-31 |
| `Create` (12: first spawn, respawns, switches, reload, upgrades) | 2.93 / 3.57 / 3.77 | 3.16 / 4.21 / 4.36 | first 125-253, first of a kind 30-60, then 5-6 |
| `Destroy` | 1.20 / 1.61 / 1.66 | 1.22 / 1.89 / 2.01 | |
| `Tick` (the first one after a create: the land cache) | 0.12 / 0.36 / 1.97 | 0.11 / 0.26 / 1.91 | |
| `Render`, `Batches`, `PrepareView` | 0.07 / 0.19 / 0.65; 0.03 / 0.07 / 0.10; 0.01 / 0.02 / 0.20 | 0.09 / 0.22 / 0.73; 0.03 / 0.07 / 0.08; 0.01 / 0.02 / 1.27 | |
| `EmitBatch` (through the mock `mesh` library) | 0.04 / 0.29 / 3.80 | 0.04 / 0.29 / 3.86 | |
| `Texture` (1210 infos, at most 3 ms per frame) | 0.011 / 0.038 / 0.20 | 0.012 / 0.039 / 0.20 | all of a kind's in one frame |
| `AudioUpdate`, `GetState`, `MoverCommit`, `PollEvents` | under 0.4 | under 0.4 | |
| **slowest call** | **3.80 (EmitBatch)** | **4.36 (Create)** | 253 |
| most module time in one frame | 9.2 (a character switch: Destroy + Create + its first frame + 3 ms of texture infos) | 8.5 (a switch) | |

The disc and the map were ready after 17 frames (gm_construct, the map built without the cache) and 39 frames
(gm_freespace_13) of the test's 2-ms frames; a map reload took 21 / 39 frames while the character kept playing.
`map_test` adds: the prepared gm_construct (90-100 ms on the worker: 32,902 triangles -> 158,213 GRID pieces in
5,305 land objects, 489 undersides left out) installed in 0.002 ms; Sonic, Knuckles, Tails and Big run, turn, jump and
use their actions for 360 frames each on the prepared world and on `set_static`'s with **identical positions and
actions in every frame**; a creation on the prepared world takes at most 2.7 ms (on set_static's the first one 96 ms);
a job dropped while it prepares is let go in 0.000 ms and deleted 96 ms later without waiting.

`diag_maps` (the real pipeline, now with the prepared world and the world images, `build/diag_maps/r051_*.txt`):
gm_freespace_13 prepared in 212-226 ms on the worker (51,310 triangles -> 312,995 GRID pieces in 12,758 land objects,
31,323 undersides within reach left out), `set_prepared` 0.002 ms, every character created in 2-6 ms; its 30 ramps 0
falls in 240 runs; random play 3 / 4 / 2 of 400 runs of 20 s (seeds 1 / 2 / 3) crossing a floor - the same as with
round 4b2's libsa1 alone, shallow dips that recover (see "Not done yet"); gm_construct prepared in 90 ms, ramps 0 of
200, random play 0 of 200. No tick over 16 ms in 1.5 million (the longest 8.0 ms, while other tests ran). `--replay`
of a fall now prints libsa1's own NEAR list (`the list at 980000A0: libsa1's raised list, capacity 256, 31 entries`).

The hitch logger (`gsa1_hitch_log`) has the new sections `Init`, `Sound`, `Textures` and `Texture info`, so a slow
frame in any of these steps would name it.

libsa1's GRID now also leaves out **undersides within reach** by default (libsa1 `sa1_collision_grid.under_reach`,
12 SA1 units = 48 Hammer units; sadc `docs/research/gsa1_ramp_freeze.md` 8: the cause of the remaining plank falls,
mechanism B). G-SA1 uses that default, on the old path (`WorldLoad`) and on the prepared one alike: on top of G-SA1's
own one-way thin platforms (24 units), a slab up to 48 units thick is now one-way too - a character can jump up
through it from below and lands on its top. The real-map measurements of that round were made with this default.

Also: `build.py` refuses to snapshot a libsa1 archive that is older than libsa1's sources (0.5.0's Linux module had
been linked against a libsa1.a of the day before) and `--lib-build` builds libsa1 for every target first;
`tests/diag_maps.cpp` uses the prepared path and the world images like the module, and its `--trace` / `--replay` read
the NEAR-poly list through libsa1's `sa1_debug_near_polys` (request 12: the list the last query filled, in host
space, instead of a scan of the world's memory for the raised list's block).

## What 0.5.0 changes (the owner's test of 0.3.0)

Research: `sadc/docs/research/gsa1_ramp_freeze.md` (the measurements behind every fix below; its fix numbers are
used here). libsa1's part (GRID cutting, the NEAR-poly capacity, the matrix stack, transform interpolation, the audio
loader) was done in the same round; G-SA1 builds on it.

| Reported | Cause | Fix |
|---|---|---|
| "The ball animations are weird, they flatten and widen randomly" | `sa1_character_render` lerped every vertex between the two pairs: a spinning ball's vertices move on circles, and their straight-line midpoints lie inside it (a ball half a turn on was drawn at half its size) | libsa1 now interpolates each drawn model's **transform** (rotation slerped, stretch and position lerped, welded seams kept closed), draw by draw; turns of more than half a turn per pair follow the game's own motion rule. Measured: the ball's size stays within 0.998..1.002 between pairs (0.52 before). G-SA1's own "move with the root" path now only matters when nothing matched |
| "Going up a ramp too fast makes you fall through it" (gm_freespace_13) | (A) libsa1's GRID cut long faces into needles that filled the game's 96-entry NEAR-poly list, so the ramp's own top was never tested; (B) at speed the first step onto a slope dips 5-10 units into it, and a plank's underside within the sphere's reach then pushed the character out BELOW the plank | (A) libsa1: well-shaped cutting, faces joined before cutting (G-SA1 emits each face's triangles together with one surface word), a 256-entry list. (B) `bsp.cpp`: **one-way thin platforms**: the underside of a solid whose walkable top is at most 24 units above it is left out (it replaces 0.4's thickening), also across solids and displacements, plus down faces at most 32 units above a walkable surface (low ceilings no character fits under). Measured on gm_freespace_13's 30 ramps (240 runs of Sonic / Knuckles / Tails at top speed, dash-panel speeds 10 and 16, spin dash): **48 falls in 0.3, 0 now**; gm_bigcity_improved_rp 19 -> 0, gm_goldencity_v2_day 14 -> 0, gm_driversheaven_tdm 28 -> 0, gm_construct 1 -> 0 (200 runs each) |
| (found while measuring) characters going through thin walls, fences, panes and doors | SA1 touches a single-sided polygon from behind within the sphere's radius: a character that steps into one side of a wall deeper than the wall is thick touches the other side too, and the two pushbacks cancel (the game averages a land object's pushbacks) | `bsp.cpp`: **thin walls**: two opposite steep faces of a solid at most 16 units apart become one double-sided face halfway between them, which pushes the sphere out to whichever side its centre is on. `map_test`: 4- and 8-unit walls let 15 of 15 and 3 of 15 runs and spin dashes through without it, 0 with it. Random play on gm_freespace_13 (400 runs of 20 s, every character): 57 runs fell through somewhere in 0.3, 11 with the ramp fixes, **3** now; gm_driversheaven_tdm (400 x 8 s) 14 -> 5. The character stops at most half the wall's thickness inside the drawn wall |
| (found while measuring) bobbing into floors with terrain under them | gm_freespace_13 has displacement terrain 8 units under its brush floors; displacements are not cut by brushes | `bsp.cpp`: displacement triangles buried inside a solid brush are left out like hidden faces (868 on gm_freespace_13) |
| "The game is randomly freezing up" | Not reproduced in libsa1 or the core (ticks under 9 ms on 13 maps, 1.5 million ticks). Suspects: sound files (27-430 ms per music file read from the disc image on the game's thread), the whole BSP read into a Lua string on the first spawn on a workshop map (gm_freespace_13: 115 MB), a GPU readback every 2 seconds (the texture canary) | **Sound**: libsa1 reads and decodes on its own loader thread; jingles and every tone are preloaded (the status says `disc reads on libsa1's loader thread`). **Map**: loaded by a background job in the module (below); a workshop map is read through Garry's Mod's file system **range by range** - only the lumps used (gm_freespace_13: 4.1 MB of 110 MB; awm_bigcity 10 MB of 459 MB), in 1 MB pieces, about 4 ms per frame - and the cleaning runs on a worker thread; a spawn before it is ready waits for it on screen ("loading the map's collision ... 40%") and happens by itself. **Canary**: read back only after a device-reset signal (the window regained the focus, a resolution change). **Hitch logger**: any frame over 100 ms prints which part of G-SA1 took the time - `hitch: a frame took 312 ms; G-SA1 297.0 ms: Create 290.1, Tick 4.2, ... (15 ms elsewhere: Garry's Mod, other addons)` - so the next report names the freeze. The game's capacity reports (NEAR-poly list full, matrix stack restored, polygon budget) are printed with the position |
| "I think the collision should be generated in the same way G64 is" | G64 builds its world from the engine's physics hulls plus static props and displacements, cached per map. Those raw hull triangles are worse for SA1's sphere collision (undersides within reach, stacked layers: 48 -> 80 ramp falls when emulated) | G64's **sources and architecture** with SA1's cleaning: world brushes and displacements as before, **static props** from the map's `sprp` lump with their physics models (`.phy` through Garry's Mod's file system, parsed in the module: convex pieces placed, scaled and cleaned with the brushes), **brush entities** (func_door, func_movelinear, func_tracktrain, func_brush, func_breakable, func_rotating, ...: their brush models built and cleaned with the map) and **physics props and vehicles** as libsa1 moving collision objects (their `.phy`, or their box), updated every frame with a rotation **matrix** (G64 passed Euler angles); a **per-map cache** (`garrysmod/data/gsa1/cache/<map>.dat`: map-derived only, versioned, keyed by the CRC of the map's lump directory and its size): a second visit loads in milliseconds. New Options page **Collision** (below) |

### The map's collision (0.5)

`gsa1.MapStart` / `MapStartData` start a job (`src/core/mapjob.*`); `cl_module.lua` drives it once per frame
(`gsa1.MapPoll`) and applies the result (`gsa1.MapApply`, the only libsa1 call, on the game's thread):

| Stage | Where | What |
|---|---|---|
| cache | worker | `garrysmod/data/gsa1/cache/<map>.dat`: used when its format, the pipeline version and settings, and the map's lump directory and size match (a damaged or foreign file is refused and rebuilt) |
| reading | addon, 1 MB pieces, about 4 ms per frame | workshop / mounted maps only: `file.Open("maps/<map>.bsp", "rb", "GAME")`, `Seek` / `Read` of the byte ranges the module lists (`needs`), `gsa1.MapFeed`. Maps in `garrysmod/maps` or `addons/*/maps` are read by the worker itself |
| parsing | worker | lumps, entities (the solid brush entities' models), the static prop list |
| files | addon, within 4 ms per frame | the static props' `.phy` files (or the first 136 bytes of the `.mdl` for box props) through Garry's Mod's file system (VPKs, GMAs, the map's pak), `gsa1.MapFeedFile` |
| building | worker | props placed and cleaned with the brushes (`Bsp::build_world` with extra convex solids), brush models as moving-object shapes, the cache file written |
| preparing (0.5.1) | worker | libsa1's GRID synthesis of the world (`src/core/prepare.*`: `sa1_collision_prepare_tris` on a private libsa1 context; 90-100 ms for gm_construct, about 0.2 s for gm_freespace_13); also after a cache hit |
| apply | game thread | `sa1_collision_set_prepared` (O(1)) and the brush models' shapes to the moving objects (0.5-1.6 ms in all). The current character is re-created where it stands (characters keep the world they were created with; about 3 ms). Without a preparation (it failed, or `prepare = false`) the triangles go to `sa1_collision_set_static` and the first character synthesizes them, as in 0.5.0 |

Offline (this machine): gm_construct 42-53 ms, gm_freespace_13 75-96 ms, gm_driversheaven_tdm (1638 static props)
380-450 ms in the worker; gm_construct's cache file is read in 3 ms. The cleaning, by map (`diag_maps`): gm_freespace_13
1286 one-way solids, 1733 thin walls, 868 buried terrain triangles; gm_construct 627 / 916 / 545; gm_bigcity_improved_rp
480 static props placed (2357 physics pieces).

**Moving objects** (`cl_collision.lua`, `src/core/movers.*`, `shape.*`): five times a second the entities within
2600 units of the character are looked at (`ents.FindInSphere`); a brush entity's shape is its model built with the
map (`b<N>`), a physics prop's or vehicle's its `.phy` (read once per model, cleaned like brushes: `m:<model>`), a
box entity's its collision box (`x:...`). Every frame each one goes to the module with its position, angles and
whether it is solid now (`gsa1.MoverUpdate`), and `gsa1.MoverCommit` puts the nearest into libsa1 (at most 40 objects
and 2048 triangles within 2400 units; a shape is split into chunks of at most 1024 triangles within 1500 units); an
object that drops out of that set or stops being solid (a func_brush switched off, a door set non-solid, a broken
window) is **parked** far below the map with its libsa1 object kept (switched on again: one move, no reallocation),
and freed only when more than 16 are parked. Not collided with: the player, NPCs, weapons, ragdolls, the player's own
vehicle, entities in collision groups that do not collide with players (debris, passable doors, ...), triggers.

## What 0.2.0 changes (the owner's first in-game test)

| Reported | Cause | Fix |
|---|---|---|
| No animation interpolation, whether `gsa1_interpolate` is 0 or 1 | 0.1.0 rebuilt the character's mesh only when a 30 Hz game pair ran and interpolated the position alone | Every frame the module asks libsa1 for the draws at the accumulator's fraction (`sa1_character_render`, alpha -1): every vertex, the root and the effects are interpolated between the last two pairs, so animation and movement are smooth at any frame rate (one pair, 33 ms, behind the game). The addon streams them into a dynamic mesh per batch per frame. `gsa1_interpolate 0` shows the game's own 30 Hz frames (one static IMesh per batch per pair, cheaper) |
| Falling into the garage from its roof (a floor above a floor) | Faces buried between touching brushes filled the game's 96-entry near-polygon list, so the roof's own top was never tested | `src/core/bsp.cpp` (collision round): hidden brush faces removed, floors thinner than 12 units thickened, runs of steps turned into ramps flagged as stairs; `tests/collision_test.cpp` (landing on the garage roof, 42 runs across it, every stacked floor of gm_construct) |
| Corrupted textures (chest, gloves, shoe soles, Tails' tails white) | libsa1's PVR decoder read every mipmapped 16-bit twiddled texture 2 texels off (a padding error) | Fixed in libsa1. G-SA1's transfer to Lua (run-length strings painted into render targets) is checked texel for texel against libsa1's decoded RGBA for all 382 textures of the 15 archives of the six characters (`core_test`); in game `gsa1_texcheck` reads painted render targets back and compares them with the module's texels |
| Sonic has no eyes | The game's character renderer ignores the material colour (the irises' is black) and many materials ask for alpha with nothing translucent (the irises lie 0.05 units in front of the eye whites but are drawn first) | Batches follow libsa1's classification: palette-lit draws get white vertex RGB (texture x the map's lighting), `USE_ALPHA` draws are opaque with depth writes |
| Sonic's arms blue | The material colour was used as a vertex colour | As above: the character's body is texture x lighting |
| Tails' tails do not layer | Translucent draws were mixed with opaque ones and not in the game's order | Opaque batches in `ENT:Draw`; blended batches (the tails' fading copies, effects) in `ENT:DrawTranslucent` afterwards, in the game's draw order, depth-tested without depth writes, with the game's blend factors |
| No spin dash trail, targeting beam, punches, fishing target | Only the model's own texture archive was drawn; sprites and lines were not captured | Every draw of every texture archive (SON_EFF, KNU_EFF, E102BEAM, ...): effect models, 3D polygons (Tails' tail trail), camera-facing sprites (Knuckles' punch), line segments as thin camera-facing ribbons (E-102's targeting), sphere-mapped materials. Not drawn because libsa1 does not run their game code yet: the particle manager (dust, spin dash sparks, splashes) and Big's fishing rod, line, lure and target |
| No sound at all | Sound events arrived and were dropped | libsa1's audio layer decodes the sound banks, voices and music from the disc in memory and mixes them (positional, the game's keep-alive / stop rules); the module plays the mix through Garry's Mod's own BASS library |
| Options only in the console | | Every option is in the spawn menu: Q -> Options -> G-SA1 (Character, Camera, Rendering, Sound, Disc and status); the console commands and ConVars stay |

## What 0.4.0 changes (the owner's test of 0.2.0)

The owner's report on 0.2.0: "The character bug slightly at high speed, going forward and backward every frame,
causing a position flickering kind of thing. Sonic has his eyes, Tails' tails look as they should. Knuckles'
climbing particles have no alpha when they should. The upgrades should be toggleable. The characters don't react to
damage and don't do damage. Gamma can't lock on to bad guys and vehicles."

| Reported | Cause | Fix |
|---|---|---|
| At high speed the character goes forward and backward every frame | Reproduced offline (`core_test`, "frame loop": the module's frame loop at 60 / 144 / 240 fps and uneven frame times on a flat floor). Running is fine; in a spin dash libsa1 interpolates no frame at all: the draws change every pair (the trail grows, the blur copies change texture), so `sa1_character_render` shows the last pair as drawn while the root - which the chase camera follows - is interpolated. The body stood still against the moving camera and jumped forward at the next pair: up to 64 HU back and forth per frame at 144 fps | `Session::follow_root` (`src/core/session.cpp`): a frame libsa1 did not interpolate is moved along with the interpolated root (by the root minus the last pair's root, taken from `sa1_character_render(1.0)` after every tick that ran a pair). The body now keeps its place against the camera (0.00 HU within a pair, 0.63 HU at a new pair: the rolling ball's own change); the effects of such a frame (spin dash trail) are carried along by less than one pair. Regression test: `core_test` "frame loop" (fails without the fix at every frame rate). The debug overlay says "moved with the root" for such frames |
| Knuckles' climbing particles have no alpha | The climbing dust is a sprite of KNU_EFF's `tsuchi_yama` (32x32 ARGB4444: 312 clear, 125 graded, 587 opaque texels), blended SRC_ALPHA / INV_SRC_ALPHA: libsa1's draw (`SA1_DRAW_BLEND`, factors 4 / 5, sprite alpha 255) and the module's texture runs are right (`core_test` "Knuckles climbs a wall" checks both). The alpha was lost in Garry's Mod's render targets, by one of two things in 0.2.0's painting: the format `IMAGE_FORMAT_RGBA8888`, which Direct3D 9 drivers do not offer for render targets (Source substitutes a format of its choice), and the clear ran before the alpha writes were enabled (the clear is what makes the never-painted transparent texels transparent) | Render targets are `IMAGE_FORMAT_BGRA8888` (D3DFMT_A8R8G8B8, the render-target format with alpha every driver has; new names, so 0.2's render targets are not reused), alpha writes are enabled before the clear. A probe paints alpha 96 into a 4x4 render target of each format once and reads it back: `gsa1_status` / the status read-out show `render targets: BGRA8888, alpha kept (probe 96 -> 96, 0 -> 0)`; if only the other format keeps the alpha, later textures use it; if none does, a console line asks for a report. `gsa1_texcheck` compares the alpha separately. **Not verified in game** (no Garry's Mod offline): the probe line is the evidence to report |
| The upgrades should be toggleable | libsa1 starts every character without upgrades | Options -> G-SA1 -> Character -> Upgrades: a checkbox per upgrade (ConVars `gsa1_upgrade_<name>`), "All upgrades", "No upgrades", "Re-create the character here". A character gets its ticked upgrades when created; ticking or unticking one of the current character's re-creates it where it stands (same place and facing, standing still; its spawn point for deaths stays). See "Upgrades" below |
| Damage, Gamma's lock-on | Not part of this round (no enemies, no hurt or attack collision with Garry's Mod entities yet) | Design work (a separate document); unchanged here |

### Upgrades

In the game an upgrade is an event flag (one byte of `B_8C799920`, set by the story); PInitialize (8C06C350,
`sadc/src/1st_read/code_8C06C300.c`) reads the character's flags when the character starts and sets
`playerwk.equipment` bits, which the character code tests (the files each bit was checked in are listed in
`session.cpp`). Big's lures have no bit: the fishing code counts their flags (8C0E6E80) whenever it needs the lure.

| Character | Upgrade (`gsa1_upgrade_<name>`) | Event flag | equipment | What changes |
|---|---|---|---|---|
| Sonic | Light Speed Shoes (`light_speed_shoes`) | 0x8D | 0x0002 | hold action: the light speed dash charges (210 frames) |
| Sonic | Crystal Ring (`crystal_ring`) | 0x8E | 0x0001 | with the shoes: charged in 120 frames |
| Sonic | Ancient Light (`ancient_light`) | 0x9F | 0x0004 | with the shoes: the charged dash attacks a target |
| Tails | Jet Anklet (`jet_anklet`) | 0xCD | 0x0008 | anklets drawn, stronger steering in the air |
| Tails | Rhythm Badge (`rhythm_badge`) | 0xDB | 0x0010 | hold action: the tail attack chain |
| Knuckles | Shovel Claw (`shovel_claw`) | 0x119 | 0x0040 | claws drawn; digging (hold action, press jump) where the ground is diggable (0.8: grass, dirt, mud, sand, gravel, snow by default - "Ground types" below) |
| Knuckles | Fighting Gloves (`fighting_gloves`) | 0x11A | 0x0020 | gloves drawn; hold action on the ground: Maximum Heat |
| Amy | Warrior Feather (`warrior_feather`) | 0x152 | 0x0100 | feather drawn; its jumping hammer attack |
| Amy | Long Hammer (`long_hammer`) | 0x15E | 0x0080 | the longer hammer |
| E-102 | Jet Booster (`jet_booster`) | 0x189 | 0x0400 | hold jump in the air: hover |
| E-102 | Laser Blaster (`laser_blaster`) | 0x18A | 0x0200 | the laser blaster parts and their shots |
| Big | Life Belt (`life_belt`) | 0x1D0 | 0x1000 | stays afloat in water |
| Big | Power Rod (`power_rod`) | 0x1D1 | 0x0800 | the power rod |
| Big | Lure upgrades 1-4 (`lure_1` .. `lure_4`) | 0x1DE-0x1E1 | - | the fishing code counts them |

Super Sonic (equipment 0x8000, the story's last stage) is not offered. PInitialize's own quirk is kept: its Sonic
case falls through into Tails' flags and E-102's into Big's; G-SA1 only sets the character's own flags.

How they get into the game: `sa1_character_desc.upgrades` (`SA1_CREATE_UPGRADES`) carries event flags 0..127 only,
and every upgrade flag is above 127 (141..481). The module therefore writes those flag bytes into the character's
world after `sa1_character_create_ex(SA1_CREATE_WORLD)` and before its first step, through three internal libsa1
functions (`sa1_character_world`, `sa1g_world_rd32` / `_wr32`, bounded to the world's arena; declared in
`src/core/libsa1_internal_api.hpp`; only flags from the module's own table, Lua passes upgrade names), and checks
after the first step that the game derived the expected equipment (`GetState().equipment`, `upgrades_ok`; a log line
otherwise). `core_test` gives every character all of its upgrades and none: the flags are in the world, the
equipment is exactly the table's, and the upgrades the game draws change the model (Tails 1237 -> 1355 triangles,
Knuckles 980 -> 1016, Amy 932 -> 986, E-102 1013 -> 1097, Big 1132 -> 1164, Sonic 1001 -> 1049). A public libsa1 API
is requested (below).

Changing an upgrade of the current character re-creates it where it stands: libsa1 has no way to change a running
character's equipment (the game derives it from the flags once, in PInitialize), so the new character starts in its
standing action at the old place and facing; speed and action are not carried over. The other characters' upgrades
apply when they are spawned next.

## What 0.3.0 adds: controller (XInput)

An Xbox-style controller (Xbox 360 / One / Series pads and everything that speaks XInput) works without Garry's
Mod's own joystick setup: the module reads it itself through Windows XInput and maps it (`src/core/pad.*`):

| Controller | SA1 / G-SA1 |
|---|---|
| left stick | the analog stick at full resolution, relative to the camera: a radial dead zone (0.20), outside it the stroke starts at 0, so a partial deflection walks and a full one runs |
| right stick | camera orbit: yaw and pitch, its own dead zone, speed (180 degrees per second), response curve, invert Y |
| A | jump (SA1 A) |
| B, X | action (SA1 B: spin dash, punch, ...) |
| Y | SA1 Y |
| LB / RB | SA1 L / R |
| LT / RT | turn the camera left / right (look around; by how far the trigger is pulled) |
| Back / View | camera reset: the view swings behind the character |
| Start, stick clicks | nothing |
| D-pad | nothing (option: moves the character) |

Every button and trigger can be given any of: nothing, jump, action, SA1 Y, SA1 L, SA1 R, camera left, camera right,
camera reset. While the controller is used (any input beyond the dead zones, and for one second after) it has
priority: its stick replaces the keyboard's and its buttons add to the keyboard's; otherwise the keyboard and mouse
play as before, and the mouse always turns the view (neither turns it while a menu shows the cursor). Rumble: the game's own vibration calls (`SA1_EVENT_RUMBLE`:
Knuckles' punches, hits, ...; power 1..7 and a duration) drive the two motors while the controller is in use. Linux:
not available (the module says so); under Proton the Windows module and Wine's XInput apply.

## Ground types: where Knuckles digs (0.8)

In Sonic Adventure the ground says what a character can do on it: Knuckles digs only where the land is marked
diggable (the game's `8C0C8330`, COL bit `0x100`), Ice Cap's ice is slippery (`0x4`), Sand Hill's sand slows a
character down (`0x10`). Until 0.7 G-SA1 made every Garry's Mod surface plain land, so Knuckles played the game's own
"can't dig here" everywhere. 0.8 reads what the map's ground is made of (sadc `docs/research/gsa1_060_dig.md` with its
review; `src/core/surfaces.*`, the map job, `src/module/bind_surfaces.cpp`, `addon/lua/gsa1/feat/*_surfaces.lua`):

* every brush side's and displacement's material (the BSP's TEXDATA lumps), the material's `.vmt` (`$surfaceprop`; a
  blended displacement's `$surfaceprop2` where the corners' alphas add up to more than 382.5; patch materials - the
  map-specific cubemap copies - followed to the material they include) and `scripts/surfaceproperties.txt` (the base
  chain - grass is a kind of dirt - and the game-material letter), read through Garry's Mod's own file system (the map's
  pak, workshop `.gma`, the VPKs) the way the props' `.phy` files are; a material missing from `GAME` is looked for in
  the map's pak (`BSP`);
* static props' surface types from their `.phy` (each solid's `"surfaceprop"`);
* a class table. By default `dirt grass mud sand gravel snow quicksand antlionsand` - and a type nobody lists whose
  letter is D, N, U or J - are **diggable**, `ice gmod_ice slipperyslime slipperymetal friction_00 friction_10
  frictionm_00 frictionm_10` are **slippery**, everything else is normal ground; `carpet plaster cardboard paper papercup
  ceiling_tile rubber floatingstandable foliage rock` are listed as normal so that "derives from dirt" never makes a
  carpet or a tar-paper roof diggable. A type takes its own entry, else the first listed type along its base chain, else
  its letter's. The owner can give any type: normal, diggable, slippery, sand (Sand Hill's slow sand; diggable or not),
  hurts, no climbing. Water stays what the brush contents say. Where two coplanar brushes overlap, the lower brush keeps
  the overlap with its material (as the hidden-face rule always did); a thin wall takes the type of its side that faces
  more upward, plus the other side's hurts / no climbing; a stair ramp takes the type of the treads it replaces.

Moving objects (doors, func_brush, trains, physics props) never become diggable - the game cannot dig a moving object
(`0x08000000`) - and brush entities keep plain land; a physics prop takes slippery / hurts / no climbing from its
`.phy`, at most 4 kinds of ground per piece (libsa1's limit; more drop the kinds first).

**Options > G-SA1 > Surfaces**: "Ground types from Garry's Mod materials" (`gsa1_surfaces`, 1; 0 = every ground normal,
as 0.7), "Knuckles can dig anywhere (not the game's rule)" (`gsa1_dig_anywhere`, 0), a live line ("Under the character:
grass (diggable); the game: diggable": the surface Garry's Mod's own trace finds under the character, and what the game
makes of the ground it stands on), the map's surface types by the share of the walkable ground they cover with their
kind (select one, choose its kind in the box below the list; `*` marks your changes), Apply and "Reset to the built-in
table". The changes are kept in `garrysmod/data/gsa1/surfaces.txt` ("type = kinds" lines; a read-only copy for the session
log in `gsa1_surface_overrides`). Console extras: `gsa1_surfaces_apply`, `gsa1_surfaces_reset`, `gsa1_surfaces_list`.

The map's cache file keeps each triangle's surface type, never the kinds: a change of the table or of the two switches
loads the map's collision from the cache, applies the kinds and prepares it again on a worker (about a second, no
rebuild), and the character is re-created where it stands. The cache does not notice a workshop update of a map's
materials: `gsa1_cache_purge` then. The first visit of every map with 0.8 rebuilds its cache (pipeline 4, cache format 3).

**How to dig**: Knuckles with the Shovel Claw (Options > G-SA1 > Character > Upgrades), standing or walking slowly
(faster, the same buttons do something else): hold attack or crouch (the game's action button) and press jump - both
together, or keep action held through the punch it starts and then press jump.

The session log gets one line per map: `surfaces: 270 materials (0 without a .vmt, 38 patch), 12 surface types on the
map, walkable ground 8.2% diggable, - slippery; overrides: none`. Measured on the collision (`tests/map_test.cpp`):
gm_construct 95% of the walkable ground diggable (grass, sand), gm_flatgrass 99.6% of the ground with a surface type,
gm_bigcity 8.2% (concrete 57%, tar-paper roofs 27%, the lawns 8%).

Not yet: the "snow board" (COL `0x8`) and "footprints" (`0x100000`) kinds wait for libsa1 (the board-mode round); a static
prop with only a collision box (SOLID_BBOX) keeps plain ground (its model's `$surfaceprop` is not read); whether Source's
own trace reports the lower or the upper of two overlapping coplanar materials is unverified.

## Shadows, see-through textures and precise drawing (0.8)

The owner's test of 0.6.0 on gm_bigcity: "Knuckles' particles have inverted alphas", "characters have no shadows", "Big's
eye textures have Z-fighting", "Tails' motion-blur tails don't disappear when spinning" (sadc
`docs/research/gsa1_060_alpha.md`, `gsa1_060_shadow.md`, `gsa1_060_render.md`, each with its adversarial review).

* **See-through parts of textures** (`cl_textures.lua`). Every texel that is transparent in the game came out opaque
  black since 0.4, on every Windows Direct3D 9 setup measured (native and Garry's Mod's DXVK): Source creates each
  render target opaque black, G-SA1 cleared its texture render targets with `render.Clear(0, 0, 0, 0, true, true)` -
  they have no depth buffer, so Direct3D 9 refused the whole clear (`D3DERR_INVALIDCALL`) - and vgui never draws a
  rectangle of alpha 0. Knuckles' climbing and digging clods got dark frames and his punch dust became black squares
  with the puff as the only see-through part ("inverted"); Amy's dizzy stars, Big's belt ring and cast mark had black
  patches. 0.8 clears colour only; paints an alpha-0 texel that carries colour (soft edges under filtering) with its
  colour and alpha 0 through the separate alpha blend (or with alpha 1 where a host ignores it); sets the surface alpha
  multiplier other addons may leave to 1 while painting; and its startup probe runs the painter itself and then draws
  the result the way batches draw, so the session log's line now reads `render targets: BGRA8888, alpha kept (painted 96
  -> 96, alpha 0 -> 0, unpainted -> 0; seen through a translucent material: 234 197 178 / 255 / 255)` (0.6.0 on the
  owner's machine: `alpha LOST (probe 96 -> 96, 0 -> 255)`). A host where even a colour clear fails gets its textures
  cleared by drawing. Offline, `tests/texture_alpha_test.lua` checks all of it against a render-target pixel model of
  Garry's Mod (`tests/lua_mock_rt.lua`: the opaque creation clear, the dropped clear, vgui's skipped rectangles, the
  multiplier); on 0.7.0's addon it reproduces the owner's log line exactly and fails 9 of 10 checks.
* **Shadows** (libsa1 + `session.cpp`, `cl_render.lua`, `cl_textures.lua`). The game's own blob shadow: libsa1 now
  draws what the game's shadow code (`8C0925A0` / `8C09247E`, E-102's `8C09222C`) draws - a flat oval on the ground the
  game finds under the character, tilted to it, turned with the character, smaller the higher the character is, gone
  when the ground is out of the game's reach (roughly 30-70 game units, 120-280 Hammer units, above it) - with
  OBJ_REGULAR's `shadow` texture from your disc. G-SA1 draws it as a darkening mask (the texture is black with the
  shape in its alpha: the module paints its render target with the alpha as colour and draws it with ZERO /
  ONE_MINUS_SRC_COLOR and the game's 80 % darkness - the game's result, needing no alpha in the render target) under a
  tone-mapping scale of 1. **Options > G-SA1 > Rendering > "Character shadows (the game's blob)"** (`gsa1_shadow`, 1)
  switches it, whatever "Effects" says; not in first person. The session log's context lines say `shadow draws N`.
  OBJ_REGULAR's other 95 textures are never painted (the shadow's render target is made at its first use).
  Differences from the Dreamcast that stay: the blob lies on the collision, which can differ from the drawn ground
  (stairs are ramps in the collision; static props' physics hulls); it floats over edges and steps like the game's
  (no "hug the ground" option yet).
* **Precise drawing far from the map's centre** (the module's feature `render`, `cl_render.lua`). 0.7 handed Garry's Mod
  absolute positions; around x 5400, y 9000 on gm_bigcity the GPU's 32-bit vertex arithmetic rounds them by about a
  thousandth of a unit - more than the 0.016-0.043 units between Big's (and Tails', Sonic's) eye layers - so Big's
  eyes z-fought even standing still. Now the module writes each position minus the character's drawn root (in double
  precision) and the character is drawn under `cam.Start3D(EyePos() - root, EyeAngles())`: the same picture, computed on
  small numbers (`tests/feat_render_test.cpp` emulates the float32 transform and the 24-bit depth buffer: the eye-like
  layers lose at (5400, 9000, -11136) with absolute positions and never with relative ones). **Rendering >
  Troubleshooting > "Precise drawing far from the map's centre"** (`gsa1_relative`, 1): off draws absolute positions as
  before - turn it off and report it if a character is drawn in the wrong place, missing in water reflections or
  oddly fogged. Under water (the eye in water) the absolute positions are used (Source's water fog uses heights).
  libsa1's part of the eye fix (each eye, iris and pupil interpolated relative to the head it sits on, between the
  game's 30 Hz frames) needs nothing from G-SA1.
* **Tails' "blur tails"** could not be reproduced offline (the jump, the roll, the tail attack and flight all draw what
  the game draws; sadc `docs/research/gsa1_060_render.md` 4). `gsa1_logdraws` writes the draw list of the current frame
  into the session log - every draw with its texture, flags (`AFTERIMAGE` marks the fading copies), alpha range, batch
  and pass - so a test settles it: press it while you see the tails (and say whether Tails was rolling, rolled up after
  a jump, doing the tail spin or flying). With `gsa1_debug 1` a line at the bottom left counts the shadow and
  afterimage batches. libsa1 now also draws both of the game's translucent copies in the jump ball (92 afterimage draws
  instead of 46), and a frame that runs several game steps no longer pops.

## Interaction: enemies, damage, props, balloons, doors (round 5)

The owner's 0.2 test: "The characters don't react to damage and don't do damage. Gamma can't lock on to bad guys and
vehicles." Since round 5 Garry's Mod's world near the character is made of **the game's own objects** (libsa1's host
objects, API 0.3: sadc `docs/libsa1_interaction.md` and its addendum, section 6; plan `docs/research/gsa1_rounds_plan.md`
9.3 with the owner's additions): an NPC is an SA1 enemy inside the character's game, so the jump, the roll, the homing
attack, the Light Speed Attack, Knuckles' punches and Maximum Heat, Amy's hammer, E-102's lock-on and laser and Big's lure
hit it with the game's own code - the bounce off an enemy, homing chains, the score - and touching a hostile one hurts
the character the game's way: knock-back, the rings scattered (and collectable again), the blinking, death at no rings.
Feature `interact` 1: the module's `src/module/bind_interact.cpp` and `src/core/interact.*`, the addon's
`feat/sh_interact.lua` (the rules and settings, both realms), `feat/cl_interact.lua` (the client and the Q-menu page
**Options > G-SA1 > Interaction**), `feat/sv_interact.lua` (the server: plain Lua, no module) and `feat/cl_hud.lua` (the
ring counter). The owner's decisions (2026-10-20) are the defaults:

| What | Default (owner decision) | On the Interaction page |
|---|---|---|
| Hits on the character | cost rings by the game's rules; Garry's Mod health untouched (1) | server: damage mode rings / health / both; "the character can die", "hits scatter rings", "knocked back away from the attacker" |
| The character's attacks | scaled Garry's Mod damage per attack kind (2): jump / roll 50, spin dash 75, homing 60, Light Speed Attack and Maximum Heat 150, punch and hammer 90, Big 80, lure 50, laser 80, laser blast 30, sparkles 20, invincibility / Super 200, others 40 | server: a slider per attack, a scale, "Reset the damage to the defaults" |
| Touching NPCs | hostile ones hurt, neutral ones do not (3) | a "touching them hurts" switch per kind |
| Other players | PvP on: a hit knocks the other character back in their own game and costs rings (4) | server: PvP, PvP knock-back |
| Props | a prop a player could carry with E is carried by the characters (5): the game's lift, carry, put down and throw | "pick up props"; server: allowed, heaviest (35 kg), largest (128 units) |
| Each kind of target | its own switches (6): attack (its hits do damage), targeting (off / E-102's lock-on only / homing and lock-on), touch harm | one row per kind: hostile, neutral, friendly NPCs, vehicles, players, props and breakables, hazards |
| Balloons | homing targets that pop and launch the character up (7) | on / off, launch like a spring or like an enemy bounce (homing chains), launch speed, pop on touch |
| Pushing props (owner, 0.5.0 test) | on, strength 1, rolling x2 | push on / off (in the props row), strength, rolling factor; server: allowed, cap |
| The interact key (owner, 0.7.0 test) | the key of +use (E) | key binder, "also lifts props", "enters vehicles", "back as the character after the vehicle" |
| Ring counter | on (score, lives off) | HUD section (one switch) |

Kinds of target (`feat/sh_interact.lua` `I.Category` / `I.Describe`): hostile NPCs and NextBots (by the server's
relation messages every 0.5 s, before that by class) are ENEMYs (solid, touch 1); neutral ones ENEMYs without touch
harm; friendly ones (citizens, Alyx, Barney, ...) are left alone by default (TARGETs when switched on); vehicles (also
LVS, simfphys and WAC by class) TARGETs, no E-102 time bonus; other players ENEMYs without touch harm (only with the
server's PvP); props with health (`func_breakable`, `func_physbox`, `prop_physics` with health) E-102's targets;
liftable props (the server's tag) HOLDABLE; `gmod_balloon` BALLOON; fire, grenades, rockets, combine balls and crossbow
bolts HAZARDs (touch 2: only a spin dash, the Light Speed Attack or invincibility protect). Shapes come from the entity's
collision bounds: a vertical cylinder for NPCs and players (a sphere for flying NPCs), a box turned with the entity for
props and vehicles, a sphere for balloons and hazards. Up to 512 entities within 2400 units are registered (kept until
2800), libsa1 puts the 64 nearest into the character's game.

**Your attacks** (`gsa1_hit`): the server checks that you are a character, that the target is within the attack's reach
of the character (240 units, the lure 800, the laser 1100, plus a latency allowance), one hit per target per 0.15 s,
and the `GSA1CanDamage(ply, ent, attack)` hook (return false to refuse), then applies a `DamageInfo` with you as the
attacker (the force flings ragdolls the way SA1 enemies fly). An NPC that dies from it tells your client, which removes
it as killed (E-102's time bonus).

**Getting hit**: damage your (invisible) player entity takes on the server - bullets, zombies, explosions - hits the
character (`gsa1_hurt` -> `gsa1.Damage`); in the default rings mode Garry's Mod's damage is blocked. The game's 2 seconds
of invulnerability absorb a stream of bullets (one ring loss per 2 s). Falling does nothing; drowning is the game's own;
damage of 1000 or more (a `trigger_hurt` pit) kills at once; "the character's death kills the player" is a server option.

**Pushing props** (owner, the 0.5.0 test): libsa1 reports the character's contacts with the moving objects every 60 Hz
step (`sa1_character_contacts`); the client folds them per entity (`gsa1.Contacts`) and the server gives the physics
prop an impulse as a small 1-D collision: the prop gains `1.25 x m_char / (m_char + m_prop) x (approach - prop speed)`
along the push (the characters weigh 45-75 kg, E-102 250, Big 200; at most 3000 units/s per push), times your strength
(and the rolling factor when the character is in the ball or spin-dashing; the server caps it). Running at a 10 kg crate
kicks it away at about the run's speed, a 500 kg container hardly moves; leaning on a prop pushes it slowly along (the
game's own push-back makes each contact about 40 units/s); standing on a prop never pushes it (landing contacts are
left out). The game stops a fast ball short of a wall without touching it (measured: a spin dash at 2400 units/s stops 37
units before a crate), so a ball whose speed drops below 40% within a frame with a physics prop just ahead (Garry's Mod's
own trace) counts as an impact too. The `GSA1CanPush(ply, ent)` hook can refuse.

**Carrying props**: the server tags the props a player could carry with E (`prop_physics*`, motion enabled, the mass
and size limits) and the client registers them as HOLDABLE. Stand at one, facing it, and press the game's action button
(crouch / attack / attack2, B or X) - or the interact key: the game lifts it (every character; Big too), carries it,
puts it down when standing still and throws it when running (aimed at a target in front when there is one). The
server freezes the prop while it is carried (it does not shove NPCs or players), places it at the character's hands for
everyone (your own client draws it there every frame, without network delay) and gives it the game's throw speed when it
is let go, credited to you. It is refused (and the character drops it) when the prop is too heavy, held by someone else,
or `AllowPlayerPickup` / `GSA1CanHold(ply, ent)` say no; a physics gun taking it, its removal or the character going
drops it.

**Balloons**: the homing attack aims at them; a hit pops them through their own `OnTakeDamage` (the pop, an explosive
balloon explodes, an indestructible one stays a bounce pad) and launches the character up like the game's spring (no
homing until landing) or, with "like an enemy bounce", keeps the ball so homing chains go on from balloon to balloon.

### The keys

| Key | What |
|---|---|
| movement, jump (Space) | the stick and the jump, as before |
| crouch, attack, attack2 (Ctrl, mouse) / B, X | the game's action button: spin dash, punches, the hammer, ... and **lift, put down, throw** |
| (optional) the lift key on the page (`gsa1_lift_key`) | the action button for a moment: lift, put down, throw only |
| **E** (the key bound to `+use`; the page's binder, or bind any key to `+gsa1_interact`) | **interact**: the door, button or other usable thing in front of the character, a vehicle; with a liftable prop in front or one carried: the action button for a moment (lift / put down / throw) |

The interact key (owner, the 0.7.0 test: "Right now they can't open a door"): the server looks from the character's
middle along its facing - straight, and tilted up (25, 45, 60 degrees: the characters are short, a player's buttons are at
a player's eye height) and down, then around within 96 units (`gsa1_sv_interact_reach`; a player's is 80) - for something
a player could use: a `func_door` / `func_door_rotating` with "Use Opens", a `prop_door_rotating` unless it ignores
+use, a `func_button` / `func_rot_button` unless it is touch-only, a `momentary_rot_button` (turned every tick while the
key is held), any scripted entity with a `Use` function (the Button tool's `gmod_button`, Wire buttons, keypads), the
parent of a part. The `PlayerUse` hook is asked first (prop protection works), then the entity is used as a player's E
uses it (`Entity:Use`, activator and caller the player). While the key is held after a use, `Player:KeyDown(IN_USE)` is
true for that player, so a non-toggle `gmod_button` stays on as long as you hold E. A door the map opens only by a button
stays shut, as for a player. **A vehicle**: the character steps out (it is removed), you are put into the vehicle
(`CanPlayerEnterVehicle` is asked; LVS and simfphys seat you themselves), and leaving it makes you the same character
again (`gsa1_vehicle_return`). Keypads take the key you aim at with the camera (they read the player's own aim).

**HUD**: 0.9.1 replaces round 5's ring counter with the game's own HUD (`feat/cl_hud.lua`, the feature `hud`; "The HUD
(0.9.1)" below). This page keeps its on / off switch.

Commands: `+gsa1_interact` (the interact key), `gsa1_interact_status`, `gsa1_interact_damage_defaults`. ConVars (client):
`gsa1_interact` 1; per kind `gsa1_hostile_attack` 1 / `_target` 2 / `_touch` 1, `gsa1_neutral_*` 1 / 2 / 0,
`gsa1_friendly_attack` 0 / `_target` 0, `gsa1_vehicle_*` 1 / 2, `gsa1_player_*` 1 / 2, `gsa1_prop_attack` 1 /
`_target` 1, `gsa1_hazard_touch` 1; `gsa1_prop_push` 1, `gsa1_push_strength` 1 (0-4), `gsa1_push_roll` 2 (1-4),
`gsa1_hold` 1, `gsa1_balloon` 1, `gsa1_balloon_launch` 0 (spring) / 1 (bounce), `gsa1_balloon_speed` 0 (the game's 1200),
`gsa1_balloon_touch` 0, `gsa1_can_die` 1, `gsa1_lose_rings` 1, `gsa1_knockback_from_source` 0, `gsa1_solid_npcs` 1,
`gsa1_obj_window` 64, `gsa1_obj_debug` 0 (draws the shapes), `gsa1_interact_key` 0 (= +use), `gsa1_interact_lift` 1,
`gsa1_interact_vehicles` 1, `gsa1_vehicle_return` 1, `gsa1_lift_key` 0 (none); the HUD's: "The HUD (0.9.1)". Server
(replicated): `gsa1_sv_damage` 1, `gsa1_sv_damage_mode` 0, `gsa1_sv_pvp` 1, `gsa1_sv_pvp_knockback` 1,
`gsa1_sv_dmg_scale` 1, `gsa1_sv_dmg_<attack>` (other spin spindash homing lsa tail flight punch maxheat dig hammer laser
blast lure big sparkle invincible super), `gsa1_sv_hold` 1, `gsa1_sv_hold_mass` 35, `gsa1_sv_hold_size` 128,
`gsa1_sv_balloon_pop` 1, `gsa1_sv_push` 1, `gsa1_sv_push_max` 4, `gsa1_sv_interact` 1, `gsa1_sv_interact_vehicles` 1,
`gsa1_sv_interact_reach` 96, `gsa1_sv_min_damage` 1, `gsa1_sv_kill_damage` 1000, `gsa1_sv_kill_on_death` 0. Hooks for
other addons and gamemodes: `GSA1CanDamage(ply, ent, attack)`, `GSA1CanHold(ply, ent)`, `GSA1CanPush(ply, ent)`
(return false to refuse); `PlayerUse`, `AllowPlayerPickup` and `CanPlayerEnterVehicle` are asked as for a player.
Network messages (`I.NET`): `gsa1_hit`, `gsa1_kill`, `gsa1_hurt`, `gsa1_rel`, `gsa1_hold`, `gsa1_hold_pose`,
`gsa1_hold_drop`, `gsa1_hold_deny`, `gsa1_push`, `gsa1_use`, `gsa1_use_result`, `gsa1_use_vehicle`,
`gsa1_enter_vehicle`, `gsa1_vehicle_left`, `gsa1_dead`.

Module functions (feature `interact` 1; Hammer units and degrees, flat numbers on the hot path): `ObjAdd` / `ObjUpdate`
(entity index, kind, flags, position, yaw, armor, touch, cooldown, the shapes; an unchanged description is not sent
again), `ObjMove`, `ObjRemove`, `ObjClear`, `ObjEvents` (HIT, LOCKED, TARGETED, UNLOCKED, LIFTED, RELEASED - each names
the entity), `ObjConfig`, `ObjHeld`, `ObjRelease`, `ObjWorldMask`, `ObjInfo`, `Damage`, `SetCharOption`, `AddRings`,
`StateEx` (rings, lives, score, invulnerability, the held entity, ...), `Contacts`, and `gsa1.INTERACT` (libsa1's
numbers). Small patches outside the feature's files: `cl_character.lua` asks `GSA1.ExtraButtons(C)` for buttons a
feature presses (the interact key's lift), `cl_collision.lua` leaves a carried prop (`ent.GSA1NoCollide`) out of the
moving collision, `src/core/movers.*` maps a libsa1 collision object back to its entity (`Movers::entity_of`).

Tests: `tests/feat_interact_test.cpp` (descriptions and their limits; contacts folded per entity; through the module's
core on a flat floor: Sonic jumps on a "zombie" -> HIT SPIN BOUNCED naming the entity, lifts a box prop registered the
addon's way and throws it at the game's 517 units/s, homes onto a balloon -> HIT HOMING LAUNCHED; a crate as a moving
object: side contacts at the run's 473 units/s, pushing on, landing only when standing on it, a spin dash stopped 37
units short of it), `tests/feat_interact_binding_test.cpp` (the functions through the mock Lua stack; on gm_construct
through the module: the zombie HIT, `Contacts` naming a crate, `Damage` -> a HURT event and the rings gone),
`tests/feat_interact_test.lua` (both realms in Garry's Mod's LuaJIT: the settings and the page, the rules on a synthetic
entity list, the push model, Source's use rules and the target search, a client frame with the server's answers -
damage, pushes, holding, the interact key, vehicles, getting hit, PvP, kills -, the HUD switch).

Not yet / unverified: Source's spawn-flag numbers for doors and buttons are from Source's own rules as documented, not
read from Garry's Mod's binaries (UNVERIFIED); heavy props (only Big lifts the game's class-5 objects) are not offered; the
controller has no interact button yet (bind a keyboard key); followers (round 6b) mirror only enemies and hazards;
multiplayer puppets and other players' carried props are drawn where the server puts them (no prediction); a
"game-style" NPC death (explosion, animals) needs more decompiling.

## The HUD (0.9.1): the game's own

While you are a character, G-SA1 shows Sonic Adventure's own HUD (owner request on 0.7.0: "Add in the HUD"; sadc
docs/research/gsa1_070_hud.md F8 with its review). It replaces round 5's "RINGS / SCORE / SONIC x 4" counter, which was
drawn with a Garry's Mod font. The game's code draws it in the character's world, with the textures from your disc:

* **Every character except Big:** the time (top left; E-102: his countdown, which turns yellow and red near the end), the
  TIME label with the ring icon and the ring count (red blink at no rings), and the character's life icon with the lives
  (bottom left).
* **The characters' own displays:** Big's HUD (WEIGHT, rings, lives) and, while he fishes, the reel, the line-tension
  gauge and the line length (right); E-102's "+N" time bonus and his last-seconds digits; the drowning countdown 5..1,
  drawn above the character as Garry's Mod's camera sees it; Knuckles' emerald radar where its task runs (the emerald
  shards come with the 1.0 collectables). E-102's lock-on cursor is drawn in the world, like before.

How it is drawn:

* libsa1 runs the game's HUD functions where the game's frame step calls them (`8C08A4BA` rings and lives, `8C08A724`
  the time) and hands every 2D draw of the pair to the module (`sa1_character_screen`, libsa1 API 0.4 draft). The module
  copies it into flat Lua arrays (`gsa1.HudScreen`), only when a new pair changed it.
* `feat/cl_hud.lua` draws it in `HUDPaint` with the mesh builder: the game's UVs, colours, blend and order (opaque
  first, then by the game's 2D priority). The textures are the render targets of `cl_textures.lua` (the alpha fix
  applies); CON_REGULAR (the HUD's archive) is painted at its first use, not at a spawn. A draw waits until its texture
  is painted, so you never see a black box.
* **Layout.** The game's 640 x 480 screen is scaled by min(W / 640, H / 480) x the size option (3 at 3440 x 1440). On a
  wider (or taller) screen each element is anchored to the edge it belongs to. An element is the draws of one part, or
  of one drawing task, in the upper or the lower half of the screen. Its centre `xc` gives
  `t = clamp((xc - 160) / 320, 0, 1)` and `X = x s + (W - 640 s) t + edge W (1 - 2 t)`; the same holds vertically with
  120 / 240 and 480. Left-quarter elements stay at the left edge, centred ones in the middle and right-quarter ones at
  the right edge; a moving one (E-102's "+N" flying to the timer) moves smoothly. At 3440 x 1440 that is offsets 0 /
  1520 / 760. The "centred 4:3 box" layout puts all of it in the middle (offset 760).
* Hidden without a character, with the HUD switched off, while you look through a camera (the Camera tool) and with
  `cl_drawhud 0`. Garry's Mod's health and suit display is hidden while the HUD shows and the rings are the damage (the
  server's damage mode "rings").
* The game clock runs (worlds used to boot with it stopped, so the time stayed at 00:00:00). E-102's 3-minute limit is
  off by default: his clock stays at 3:00 plus any time bonus and the time never runs out (owner default 14.1h; tick it
  for the game's rule: he dies at 0:00). A respawn or a re-creation (an upgrade change) of the same character keeps the
  time. The lives go with the Character page's lives setting (`feat/cl_charopt.lua`).

Q menu > Options > G-SA1 > **HUD**: show the HUD; the parts (rings, lives, time, the characters' own displays, the
score); the size (0.5-3), wide screens (the corners / a centred 4:3 box), the distance from the edges (0-10 %), the
textures (smooth / sharp), hide Garry's Mod's health; the game clock runs, E-102's time limit, keep the time after a
respawn. The Interaction page keeps the on / off switch. ConVars (client): `gsa1_hud` 1, `gsa1_hud_rings` 1,
`gsa1_hud_lives` 1, `gsa1_hud_time` 1, `gsa1_hud_character` 1, `gsa1_hud_score` 0, `gsa1_hud_scale` 1,
`gsa1_hud_layout` 0 (corners) / 1 (box), `gsa1_hud_safe` 0, `gsa1_hud_filter` 0 (smooth) / 1 (sharp),
`gsa1_hud_hide_gmod` 1, `gsa1_hud_keep_time` 1, `gsa1_clock` 1, `gsa1_e102_time_limit` 0. Round 5's switch names are
kept: `gsa1_hud_rings` (the ring count) and `gsa1_hud_score` (the score: not part of the game's action-stage HUD, so
G-SA1 draws it under the ring icon with the game's digits). `gsa1_hud_lives` now means the game's lives part, and it is
on by default (in 0.9.0 it was the "SONIC x 4" line, off by default).

Module functions (feature `hud` 1, `src/module/bind_hud.cpp`): `HudSettings(id, parts, clock, e102_no_limit)`,
`HudSetTime(id, minutes, seconds, frames)`, `HudCounters(id)` (time, clock running, score, rings, lives),
`HudScreen(id, out [, force])` (generation, changed; `out.d` / `out.s` / `out.v` flat arrays) and `gsa1.HUD` (the parts,
the strides). The addon uses `cl_character.lua`'s hooks `GSA1CharacterCreated` / `GSA1CharacterLeaving`, so the settings
and the kept time reach a new world before its first tick (without them, at the next frame).

Tests: `tests/feat_hud_binding_test.cpp` (the functions through the mock Lua stack; with the disc, through the module:
Sonic's 15 HUD sprites at the game's places with CON_REGULAR textures, the parts masks 7 / 11 / 12 / 8 / 0, the time
running and set, E-102's clock held and counting down, 00:00:00 giving 3:00:00, Big's own HUD task, Tails', Knuckles' and
Amy's life icons) and `tests/feat_hud_test.lua` (Garry's Mod's LuaJIT with the mock: the settings and the page, the
layout maths at 640 x 480, 3440 x 1440, 1920 x 1080, 4:3 and 5:4 with the size and edge options, a drawn frame - corners,
the turned reel, E-102's "+N", the countdown above the character, UVs, colours, blend, nothing before the textures are
painted -, hidden cases, Garry's Mod's health, the time kept across a respawn, the score row, the session log).

Not yet / unverified: the Dreamcast's texture filter for HUD sprites (smooth by default, sharp on the page); whether
SA1's translucent 2D list is depth-sorted (libsa1 sorts by the game's priority); the underwater screen tint (the game's
camera task, which libsa1 worlds do not run) and Tails' race bar (no race opponent) are not drawn; Knuckles' radar needs
emerald shards (1.0); the cost of the HUD pass is not measured in Garry's Mod (offline, 200 pairs of three characters, disc loading
included, took under a second);
followers (6b) and other players' characters draw no HUD.

## The 0.9.2a fixes (in 0.9.3): sound drop-outs, stale events, teleporters, the map line, rings

From the owner's 0.9.1a / 0.9.2 tests (sadc `docs/research/gsa1_rounds_plan.md` 14.1l / 14.1m; research
`gsa1_091a_perf.md`, `gsa1_091b_itembox.md`, `gsa1_091a_teleport.md`, each with its review):

* **Sound drop-outs** (the owner hears crackles; A0 + A2): the game sound's queue in Garry's Mod's BASS is now the push
  queue alone (`bass.cpp` `bass_queued_frames`). Until 0.9.2 it also counted BASS's playback buffer - 41-49 ms on the
  owner's 192 kHz device, already gone to the device - so only about 25 ms were really queued and every frame over 20-30
  ms ran the sound dry (109 drop-outs a minute in the owner's log). The lead (`audio.hpp` `OutputLead`) is two frames +
  30 ms as before and, after a slow frame, the slowest frame of the last 4 s x 1.25 + 20 ms (60-250 ms), so the hitches
  that follow a hitch are covered while smooth play keeps 0.9.1's latency. Measured with Garry's Mod's own `bass.dll` on
  the owner's PC (G-SA1's `AudioOut` in a scratch driver, the research's frame scripts): his session-2 frame mix 102 ->
  3 drop-outs a minute (1.5 s -> 0.26 s of missing sound), session 1's mix 220 -> 6, the hitch ladder 48 -> 2.
  `gsa1.AudioStatus()` adds `lead_ms` and `playback_ms`; the session log's sound line shows them.
* **See-through check** (T3b): the startup check of lit see-through materials knows that the owner's Garry's Mod blends
  in linear light (sRGB-correct: `$alpha` 0.5 reads 188 of 255, 0.74 of the control) and says "ok (this Garry's Mod
  blends in linear light)" instead of "not measured" (`cl_textures.lua` `T.LitVerdict`). Nothing is drawn differently.
* **A removed or restarted character's events** (E2): `Session::destroy` drops the destroyed character's events still
  queued for `gsa1.PollEvents`, so a fault, a death or the sounds of a character that was removed or restarted in the
  frame its tick failed never reach the next character (the owner's "Tails's game code faulted (address 8C05D930)" was
  Knuckles' fault 104 s late).
* **Teleporters** (T0, the owner's "Teleports don't work. They snap the camera to a side view, and the player remains in
  the original place"): G-SA1 is the only thing that moves a character's hidden player, so a move it did not make is a
  teleport - a map's `trigger_teleport`, a `point_teleport` or another addon's `SetPos` (feature `teleport`:
  `feat/sh_teleport.lua`, `sv_teleport.lua`, `cl_teleport.lua`). The server finds it after each user command and before
  each state packet, holds the player at the destination, tells the client and drops the client's older packets until it
  confirms (1 s without: the old follow, counted). The character is re-created at the destination facing the
  teleporter's direction - the camera turns with it, as Garry's Mod turns a player's view - with its rings and lives. It
  arrives standing: keeping the running speed needs libsa1's warp ("libsa1 API requests" 21). A dying character only
  confirms (the death plays where it is, the respawn goes to the spawn point); a loop of teleporters is followed at most
  4 times in 2 s and logged once. The session log gets a `teleport` line per teleport (from, to, facing, method, the
  cause: "trigger_teleport -> genesis_acf_teleport_dest") and the summary a count. Character page: "Map teleporters move
  my character" (`gsa1_sv_teleports` 1; off: a character's hidden player is never put into a map teleporter, so it
  walks through) and "Keep running through teleporters" (`gsa1_teleport_keep_speed` 1; with the warp). Console:
  `gsa1_teleport_status` (the server's counts).
* **The map line** (0.9.2's verifier): `gsa1.MapApply`'s info has 0.9.2's collision clean-up counters (`tris_outside`,
  `frags_outside`, `props_outside`, `displacements_nohull`, `thin_stacks`, `thin_wall_kept`, `prepare_retried`,
  `prepare_left_out`, `too_big`) and the map line and the Collision page show them. A map too big for the game's
  collision memory is no longer handed to the first character (which ran the same failing GRID synthesis on the game's
  thread): the map gets no collision, one chat line says why, and a spawn there says the same words at once.
* **Rings by hand** (0.9.2's verifier): "Give 10 / 50 / 100 rings" (`gsa1_give_rings`) and `gsa1_rings` /
  `gsa1_rings_add` follow one rule - single player, `sv_cheats 1`, an admin or the listen server's host
  (`feat/sh_giverings.lua`) - and in multiplayer the server checks it too before the client changes the rings.
* **Power-up models** (libsa1, 092a-lib-fx3): the barrier's sparkles, the invincibility's star ball and sparks and the
  magnetic barrier's sparks are drawn (libsa1's `8C621574` model draw); they are effects, so "effects" off hides them.

Tests: `tests/feat_perf_audio_test.cpp` (FakeBass with its playback buffer model and a manual clock: 0.9.1's feed stalls
on a 28 ms frame, 0.9.2a's on none up to 65 ms, the adaptive lead, a minute of the owner's frame mix 84 -> 4 a minute),
`texture_alpha_test.lua` part 10b (a linear-light framebuffer in `tests/lua_mock_rt.lua`), `core_test` "a destroyed
character's events" (with the disc), `tests/feat_teleport_test.lua` (the research's stricter model with the real files:
one teleport and one FIXANGLE at 0 / 60 / 150 ms, the arrival at the platform, a chain, a loop, the option off, a dying
character, the moves that are not teleports, a client that never confirms), `tests/feat_mapline_test.lua`,
`tests/feat_giverings_test.lua`, `binding_test`'s map info fields.

## Super Sonic (0.9.3a): Vs. Perfect Chaos and General Gameplay

The owner's answer (sadc `docs/research/gsa1_rounds_plan.md` 14.1a): "add him as a separate character, as well as a
transformation"; and for 0.9.3a (14.1o): two versions. Both come from libsa1's API 0.4 (`libsa1.h` "Super Sonic (API
0.4)" and "THE GENERAL FORM"; research sadc `docs/research/super_sonic.md`, `super_general_design.md`, each with its
review):

* **Super Sonic (Vs. Perfect Chaos)** (`gsa1_spawn supersonic`, or `super`; kind 8): the game's own Super Sonic, as in
  0.9.3. His world is a Sonic world on the Perfect Chaos stage (level 19 act 0: only there does the game switch on Super
  Sonic's 12 welds). The game turns him Super itself in his second game pair - the stage's own trigger sends the game's
  request 46, and Sonic's request handler does the rest: the golden body, the aura, the faster physics, the game's Super
  modes (run, jump, homing in every direction, the air stop with the action button; no spin dash, no Light Speed Dash).
  He starts with 50 rings and loses one every second (the game's drain). At 0 rings he turns back into normal Sonic where
  he is and keeps running (libsa1's revert fix; the Dreamcast's own revert leaves Sonic slower, a game bug kept behind an
  option). He runs on Garry's Mod's water as on the Perfect Chaos sea (`SA1_CREATE_WATER_FLOOR`). New in 0.9.3a (each an
  owner note): he has Sonic's ticked upgrades (`find_upgrade` maps kind 8 to Sonic's rows: equipment 0x8007 while Super,
  0x0007 after the revert; measured: one 600-pair script plays the same with and without them); after the revert he
  says Sonic's own idle lines; the calmer aura animation; he turns Super again (50 rings) only in a jump - the action
  button in the air or the key - with the "Hm!"; re-created after he turned back (an upgrade ticked, a teleport, a fault
  restart) he stays normal Sonic (libsa1's `SA1_SUPER_START_NORMAL`).
* **Super Sonic (General Gameplay)** (`gsa1_spawn supersonic_general`, or `ssg`; kind 0 with the form "general"): a Sonic
  world in libsa1's General form (`SA1_SUPER_GENERAL`). It is the map's own stage (level 1), never level 19; the 12 Super
  welds are set up by the game's own weld code after the first pair, and the transformation is the body of the game's
  request 46 without its change of mode: the Super bit, the aura task, the physics task, and the look (Sonic's actions
  drawn with the Super body and ball and the SUPERSONIC textures). So he keeps Sonic's whole mode machine: spin dash,
  homing attack (the game's Super homing: the air dash reaches 6.6 units a step without a target, 3.3 for Sonic), Light
  Speed Dash and Attack with the shoes, carrying, springs; the bit's rules apply (a hit only halves his speed; attack and
  defence 3: the interaction layer counts his hits as "super"). He is golden right after his first pair
  (`SA1_SUPER_START`), with 50 rings (`gsa1_super_general_rings`) and the drain on; at 0 rings he turns back into Sonic
  and can turn Super again in a jump. Speed (`gsa1_super_general_speed`): **Super run** (default) keeps the game's Super
  ground drag with Sonic's air values - he picks up speed like Sonic, jumps exactly like Sonic, and keeps getting faster
  on long straights (measured on a flat floor: 5.9 units a step after 150 pairs, 9.4 after 300, 12.4 after 550; Sonic
  stays at 4.31), and a spin dash rolls about 1.6 times as far; "The game's Super Sonic" adds the floaty jumps; "Half-way";
  "Sonic's speed". The aura can be switched off, and the game's golden trail and ball after-images replace Sonic's blue
  ones (`gsa1_super_general_effects`; the spin dash's dust and the Light Speed effects have no golden version in the game
  and stay Sonic's). He runs on water while Super (`SA1_SUPER_WATER_WHILE_SUPER`: water below him is a floor; water he is
  inside stays water; turning back on it drops him in).
* **The transformation for normal Sonic** (`gsa1_super_transform`, on): Sonic is created in the General form (no START)
  and turns Super where he is - position, facing, speed, the jump itself and his rings carry over - with at least
  `gsa1_super_transform_rings` (50) rings by **jumping and pressing the action (spin dash) button in the air**
  (`gsa1_super_gesture`), or with the key (`gsa1_super_key`, G; the controller's right stick click `gsa1_super_pad`; the
  command `gsa1_super`) in the jump. The press that transforms is kept from the game until the button is released (no air
  action, no spin dash when he lands with it held), and one jump changes the form at most once (precisely: one change per
  stretch of the jump state, mode 8; a homing attack in between starts a new one). The same gesture in a later jump turns
  him back (`gsa1_super_gesture_back`); the key turns him back anywhere. With too few rings the button is Sonic's own air
  action and nothing is said in the chat; standing, it is always his crouch / spin dash. Only the player's own keyboard
  and controller buttons count: the interact key's momentary action press never transforms him. He uses the General
  Gameplay page settings (drain, "stay Super", speed, aura, effects, water).
* **The voice** (`gsa1_super_voice`; 0.9.3b default 4492 = Super Sonic's voice clip 396, his "Hm!"; also clip 388, the
  tones 1116, 1126, 1121, 1114 or none): at every transformation the player makes, never at the game's own trigger, a
  START or a re-creation. A clip is played by G-SA1 when the SUPER order goes out (`gsa1.SuperVoiceClip`; only when he is
  not Super yet); a tone is played by libsa1 with the game's sound call - at once in the General form, when the game takes
  the request for Vs. Perfect Chaos. Clips are voice lines, so "Character voices" off mutes them (the tones are sound
  effects and keep playing). The Preview button (`gsa1_super_voice_preview`) plays it without transforming.
* **Idle voices by form** (`gsa1_super_idle_by_form`, on): an SA1_GA switch in the game's own voice choice (8C07DCE0):
  Super Sonic's lines (level 19's) while Super, Sonic's own while normal; CurrentLevel itself is never changed. (The game's
  Super modes play no idle lines at all, so Super Sonic (Vs. Perfect Chaos) is silent while Super, as in the game.)
* **The aura animation** (`gsa1_super_aura_anim`): an SA1_GA switch in the aura's display (0C91D222). Calm (default):
  the standing aura shows all 8 frames in order, a new one every game pair (30 a second); Dreamcast: the game's 4 of 8
  frames, 30 a second; Slow: each frame for two pairs (15 a second). Measured through G-SA1's own drawing at 60 and 144
  fps (`tests/feat_super_test.cpp`): exactly those rates, so G-SA1 adds no extra changes.
* **What the game gives him** (both): the aura (additive, double-sided), attack level 3 (200 Garry's Mod damage), homing in
  every direction, a hit only halves his speed (no ring lost, no knock-back, no death; blinking for two seconds). Pits,
  crushing and drowning still kill him (the game). The game's HUD shows the rings as they drain.
* **Music while Super** (off by default): "Theme of Super Sonic" (SPRSONIC.ADX, 86), Perfect Chaos 1 / 2 (CHAOS_P1 22 /
  CHAOS_P2 23) or any jukebox track, from your disc through the jukebox engine on a channel of its own (2) while he is
  Super. Your personal jukebox pauses meanwhile and goes on afterwards; starting it yourself ends the Super music until
  the next transformation. It steps aside for the game's jingles like the jukebox does, and the jukebox page's volume
  applies.
* **The aura's whoosh** (tones 1035 / 1036 above running speed 7 / 13) belongs to the Perfect Chaos stage's sound bank
  (CHAOS7B.MLT). The module's sound banks are Emerald Coast's, whose bank holds other sounds there, so those two tones
  (the stage range 1027-1038 of a Super world) are kept silent instead of playing wrong sounds ("libsa1 API requests" 17).
* **The pre-warm** (`cl_warm.lua`): Super Sonic's census (the Vs. Perfect Chaos scenario, and the General form's: the
  transformation in a jump, both dash auras, the Super ball and homing, his air action, a spin dash and its roll with the
  golden after-images, the Light Speed charge, the revert; `tests/feat_super_test.cpp --census-lua`), normal Sonic's core
  census moved to Super Sonic's SONIC / SON_EFF archives, and every SUPERSONIC effect state on all of its effect
  textures. The General entry and a Sonic with the transformation on get the SUPERSONIC states.

Q menu > Options > G-SA1 > **Super Sonic**: *Super Sonic (Vs. Perfect Chaos)*: spawn; start with N rings
(`gsa1_super_rings` 50); lose a ring every second (`gsa1_super_drain` 1); stay Super when the rings run out
(`gsa1_super_keep` 0); keep the game's physics bug after turning back (`gsa1_super_faithful_revert` 0); run on water
(`gsa1_super_water` 1). *Super Sonic (General Gameplay)*: spawn; start with N rings (`gsa1_super_general_rings` 50); lose
a ring every second (`gsa1_super_general_drain` 1); stay Super (`gsa1_super_general_keep` 0); speed
(`gsa1_super_general_speed` 1 Super run / 0 the game's / 2 half-way / 3 Sonic's); aura (`gsa1_super_general_aura` 1);
golden trail and after-images (`gsa1_super_general_effects` 1); run on water while Super (`gsa1_super_general_water` 1).
*Turning Super*: the transformation (`gsa1_super_transform` 1), rings needed (`gsa1_super_transform_rings` 50), the
gesture (`gsa1_super_gesture` 1), the gesture back (`gsa1_super_gesture_back` 1), the key (`gsa1_super_key` 17 = G; a
binder) and the controller button (`gsa1_super_pad` 128). *Both*: the voice (`gsa1_super_voice` 4492) with Preview, the
aura animation (`gsa1_super_aura_anim` 1 calm / 0 Dreamcast / 2 slow), Super Sonic's own idle lines
(`gsa1_super_idle_by_form` 1), music while Super (`gsa1_super_music` 0, `gsa1_super_music_track` 86); a live status
(the form, the rings against the need, the speed set, the key). The speed, aura, effects, voice, aura animation and idle
lines apply at once; the drain, "stay Super", the physics bug and water re-create the character where he stands (his
rings and his form kept); the transformation switch re-creates Sonic. The session log gets "super" lines: the worlds
made, every change of form with the form and its cause (the start, the game's trigger, the action button in the jump,
the key, the rings ran out, the death, a re-creation), refusals (at most one line every 2 s), the options.

Module functions (feature `super` 2, `src/module/bind_super.cpp`): `SuperOrder(id, order)`, `SuperState(id [, out])`
(super, capable, general, start, rings, mode, speed, form changes, the create flags), `SuperInfo([out])`,
`SuperOption(id, option, value)` (libsa1's `sa1_character_set_super_option`: speed set, no aura, voice, golden effects),
`SuperGameOption(id, option, value)` (idle voices by form, the aura animation), `SuperVoicePreview(tone [, id])` and
`gsa1.SUPER` (libsa1's numbers); `gsa1.Create(kind, pos, yaw, upgrades, startRings, extras)` takes `extras =
{create_flags, super_flags, start_rings}` (super flags NO_DRAIN / KEEP_AT_ZERO / FAITHFUL_REVERT / GENERAL / START /
WATER_WHILE_SUPER / START_NORMAL; the sea plane is refused). `ObjHeld` (feature `interact` 2) also returns the carried
prop at the drawn steps. `cl_character.lua`'s seams: `GSA1.CreateExtras(kind, how, rings, def, old)` (characters are made
by their list entry, `C.def`) and `GSA1.FilterButtons(C, buttons)` (the player's own buttons before every tick; the
interact key's are added after it).

Tests: `tests/feat_super_test.cpp` (the core with the disc: kind 8 as in 0.9.3; the General entry Super after its first
pair in Sonic's own modes, staying normal without START; the transformation in a jump keeping mode 8 and the speed with
one voice; Super run faster than Sonic; back by order; the body anchored like kind 8's at 144 fps; upgrades kept both
ways; kind 8 identical with and without Sonic's upgrades over 600 pairs; START_NORMAL and one voice for two orders; the
aura's changes per second through the render at 60 / 144 fps; the voice Preview; the census),
`tests/feat_super_binding_test.cpp` (the functions, the constants, the extras and the options through the mock Lua
stack, with the disc and gm_construct), `tests/feat_super_test.lua` (Garry's Mod's LuaJIT: the two entries and their
aliases, the 23 settings and the page, the Character page's upgrade blocks, the "Debug" page, the create extras with the
form kept across re-creations, the gesture's state machine with the interact key's press and other characters bit for
bit, the key's air rule without chat lines, the options at once, the voice Preview, the music, the census coverage, a
failing seam), `tests/feat_interact_test.cpp` (a carried prop at a run: 0.0000 HU within a pair at the drawn steps
against 2.6 HU at the last pair's own steps) and `tests/feat_interact_test.lua` (DrawHeld's drawn steps and shortest-arc
yaw; the vehicle return keeps the entry).

Known looks and limits: the upgrades' parts are not drawn while he is Super (the Super body has none; their abilities
stay). In the first two pairs of the game's own trigger, Super Sonic (Vs. Perfect Chaos) is still drawn as Sonic (with
the upgrades' parts), as on the Dreamcast. Sonic's motions of type 7 (actions 19, 27, 47, 58, 59, 61, 66-68) give the
Super body Sonic's limb lengths, so the arms look shorter in those moves (the game's own action 138 does the same).
`sa1_geometry.object_addr` names Sonic's body while the General body is drawn. There is no transformation flash or pose
(the game's is a cutscene). A General Super Sonic's death plays golden (the game keeps the bit; design 4.4, not checked in a run); the General
Gameplay entry respawns Super, a transformed Sonic respawns as Sonic. Others in multiplayer do not see the General form yet (puppets need a "form" in the pose stream, 1.0.x).
None of this is tested in Garry's Mod yet.
## Layout

```
build.py                    builds both targets, snapshots libsa1 under its build lock, checks exports, runs the tests
src/core/                   the module's core, no GMod dependency (also linked into the tests)
  util.*                    UTF-8 paths, files, timing
  config.*                  the module-owned config file (disc path), strict parser, path validation
  paths.*                   the module's own location, garrysmod directory, map lookup by bare name
  bsp.*                     Source BSP -> sa1_collision_tri (brushes, hidden faces, one-way platforms, thin walls,
                            stairs, displacements, water, ...), static prop list, brush models; ByteSource readers;
                            material names (TEXDATA) and every triangle's surface-type tag (0.8)
  surfaces.*                ground types (0.8): KeyValues, .vmt / patch, surfaceproperties chains and letters, the class
                            table, the classes on the tagged world, moving objects' COL-word cap, classed prop shapes
  mapjob.*                  the map's collision in the background: worker thread, fed byte ranges, model files, cache,
                            libsa1's preparation (0.5.1)
  prepare.*                 libsa1's GRID synthesis on the job's worker (sa1_collision_prepare_tris, a private context),
                            PreparedRef (retain / release)
  phy.*                     Source physics models (.phy, IVP compact surfaces) -> convex hulls; .mdl hull box
  shape.*                   moving objects' shapes: cleaned like brushes, cut into chunks
  movers.*                  moving objects in libsa1: nearest first, matrices, parking, budget
  session.*                 libsa1 context (the disc loaded on a worker), characters, tick, render batches and their
                            vertices, texture runs, events, the prepared world
  audio.*                   libsa1's sound mixer (its banks opened and closed on workers); the output on Garry's Mod's BASS
  pad.*                     the controller: XInput loaded at run time, dead zones, button map, camera, rumble
  libsa1_internal_api.hpp   libsa1.h (SA1_STATIC) + the two internal path-rule functions G-SA1 uses
src/module/gsa1_module.cpp  the Lua binding (gmod-module-base), require("gsa1")
src/module/gsa1_feature.*   the feature seam: GSA1_FEATURE registry, gsa1.FEATURES, open / shutdown / close hooks
src/module/gsa1_module_internal.hpp  what a feature's bindings share with the module (GSA1_FN, argument and table
                            helpers, session(), audio_out(), gmod_dir(), scrubbed(): namespace gsa1::mod)
src/module/bind_<feature>.cpp  a feature's Lua functions (see "Features")
src/module/bind_surfaces.cpp  ground types: SetSurfaceTable, SurfaceDefaults, SurfaceKind, SurfaceInfo (0.8)
src/module/bind_super.cpp   Super Sonic: SuperOrder, SuperState, SuperInfo, gsa1.SUPER (0.9.3); SuperOption,
                            SuperGameOption, SuperVoicePreview, the General form's constants (0.9.3a, feature 2)
tests/core_test.cpp         offline: config, paths, BSP of a real map, fuzzing, Sonic on gm_construct, render batches,
                            effects of every character, interpolation, texture transfer, sound, all characters,
                            upgrades; the frame loop at 60 / 144 / 240 fps (flat floor), the frame loop against the
                            camera in jumps, falls, stairs and the Light Speed release (0.6.0), prepare_view's rules,
                            Knuckles climbing (a wall), the material census (material_census.txt)
tests/binding_test.cpp      offline: every Lua function through a mock ILuaBase and a mock `mesh` library; "the game's
                            thread": the addon's frames of a first spawn, respawns, switches and a map reload, every
                            call timed (p50 / p90 / max), none may take more than 8 ms (--timing-bsp: another map);
                            the feature seam (two dummy features: FEATURES, a refused clash, hook order)
tests/mock_lua.hpp          the mock ILuaBase and `mesh` library of binding_test and the features' binding tests
tests/feat_seam_test.cpp, feat_seam_binding_test.cpp  the seam's own feature tests (templates of a feature's tests)
tests/collision_test.cpp    offline: the collision built from gm_construct, stacked floors, stairs (collision round)
tests/map_test.cpp          offline: physics models from the game's VPKs, the map job (file and fed mode, cache, cancel),
                            the prepared world (bit for bit as set_static's), static props, brush models, moving objects
                            (lift, wall, crates), thin walls; surface types (0.8): material names, tags, the cache keeping
                            them, grass diggable and concrete not on gm_construct and gm_bigcity (Garry's Mod's own copy
                            of the workshop file), Knuckles digging there with the disc
tests/feat_surfaces_test.cpp, feat_surfaces_binding_test.cpp, feat_surfaces_test.lua  the ground types: parsers, the
                            class table, moving objects; the Lua functions on a fed gm_construct; the page, settings and
                            log line against a mock module
tests/feat_super_test.cpp, feat_super_binding_test.cpp, feat_super_test.lua  Super Sonic: the character, the options,
                            the transformation, hits, the HUD, water, the census (material_census_super.txt); the Lua
                            functions and Create's extras; the page, the key, the music, the pre-warm (0.9.3); the two
                            Super Sonics, the General form, the gesture, the aura's rate through the render, kind 8 with
                            upgrades, the options at once (0.9.3a)
tests/diag_maps.cpp         offline measurements on real maps (not pass / fail): ramps at speed, random play, ticks,
                            --replay of a fall, --dump of the geometry at a point (tests/build_diag_maps.py)
tests/gamefs.hpp, mapdrive.hpp  Garry's Mod's file system stand-in (VPKs, GMAs, the map's pak) and the addon's loop
tests/pad_test.cpp          offline, no disc: the controller mapping through a fake XInput, the real XInput provider
tests/lua_host.c            runs a Lua test in Garry's Mod's own LuaJIT (the install's lua_shared.dll, read-only)
tests/lua_mock.lua          a mock of the GMod client and of the module for the Lua tests
tests/feat_jukebox_test.lua the jukebox's Lua (pure functions, player, commands, page) against a mock module jukebox
tests/weapon_test.lua       the weapon while a character: both realms of single player against a model of Garry's
                            Mod's weapon rules (holster, gate, glow, tool gun, camera, Gravity Gun, flashlight,
                            respawn, deferred Entity:Remove, character switches)
tests/log_test.lua          the session log; tests/warm_test.lua: the material pre-warm against core_test's material
                            census (every state's exact material); tests/frame_test.lua: the whole addon frame through
                            its autorun (600 frames of a Light Speed charge); tests/seam_test.lua: the feature files,
                            pages, ConVar helper and HasFeature; tests/gc_bench.lua: the LuaJIT collector's cost (a tool)
tools/lua_check.py          offline Lua 5.1 syntax / accidental-global / escape checker for the addon (and the names
                            of the feature files)
tools/gen_warm_census.py    core_test's material census -> addon/lua/gsa1/cl_warm_census.lua (--check)
addon/                      the Lua addon (a legacy folder addon; addon.json for gmad later)
  lua/autorun/gsa1_autorun.lua
  lua/gsa1/sh_config.lua    constants, characters, ConVars
  lua/gsa1/sh_net.lua       state packet; the multiplayer design hook; the networked character flag
                            (GSA1.IsCharacter), the empty hands gsa1_hands and the weapon-switch gate (both realms)
  lua/gsa1/sv_gsa1.lua      server: moves the player entity along with the character, puts the weapon away while a
                            character and gives it back (pure Lua)
  lua/gsa1/cl_log.lua       the session log (garrysmod/data/gsa1/log.txt), GSA1.Guard for the hooks
  lua/gsa1/cl_hitch.lua     the hitch logger: per-section frame times, a breakdown of every frame over gsa1_hitch_ms
  lua/gsa1/cl_module.lua    module loading, disc, sound, the map loader (ranges, model files, apply), status lines,
                            gsa1_init / gsa1_status / gsa1_cache_purge / ...
  lua/gsa1/cl_collision.lua moving objects: brush entities, physics props, vehicles near the character
  lua/gsa1/cl_pad.lua       the controller: settings to the module, per-frame poll, view turning, camera reset
  lua/gsa1/cl_textures.lua  render-target textures (every archive, per address mode), batch materials, gsa1_texcheck
  lua/gsa1/cl_warm.lua      the material pre-warm (every material a character can use, drawn once when it appears)
  lua/gsa1/cl_warm_census.lua  the material census as data for the pre-warm (generated: tools/gen_warm_census.py)
  lua/gsa1/cl_render.lua    the gsa1_render clientside entity (opaque and blended batches, lighting)
  lua/gsa1/cl_character.lua input, tick, render, sound pump, camera, events, gsa1_spawn / gsa1_remove / ...
  lua/gsa1/cl_menu.lua      spawn menu: Options -> G-SA1 (Character, Camera, Controller, Rendering, Sound, Collision,
                            Disc and status; then the features' pages: GSA1.AddMenuPage)
  lua/gsa1/feat/            the features' Lua: sh_<feature>.lua, cl_<feature>.lua, sv_<feature>.lua
  lua/gsa1/feat/sh_jukebox.lua  the jukebox's pure functions (groups, next / previous, shuffle, plans, times, search)
  lua/gsa1/feat/cl_jukebox.lua  the personal jukebox: player, duck, Think hook, gsa1_jukebox_* commands, its page
  lua/gsa1/feat/sh_surfaces.lua, cl_surfaces.lua  ground types: kinds, the overrides file, the table to the module with
                            every map load, the Surfaces page and its live line, the session log line
  lua/gsa1/feat/sh_super.lua, cl_super.lua  Super Sonic: the Super flags and create extras, the key's rule, the music,
                            the census rows; the seam GSA1.CreateExtras, the key / button / command, the form log, the
                            Super music, the pre-warm census, the Super Sonic page (0.9.3); the General form's extras with
                            the form kept across re-creations, the gesture (GSA1.FilterButtons), the options at once, the
                            voice Preview (0.9.3a)
  lua/gsa1/feat/cl_tools.lua  the Debug page (0.9.3a; "Notes and tools" before): session-log notes, rings
third_party/gmod-module-base  Facepunch's module headers (git clone, see "Provenance")
```

## Building

Needs: libsa1 built for the targets (`LIB: py -3.12 build.py`), Python 3.12 with `ziglang==0.16.0` (the version
libsa1 pins), and the module headers:

```
git clone --depth 1 --branch development https://github.com/Facepunch/gmod-module-base third_party/gmod-module-base
```

```
py -3.12 build.py                      # x86_64-windows and x86_64-linux
py -3.12 build.py --test --gdi "<your .gdi>"        # + pad_test, core_test, binding_test, collision_test, map_test
py -3.12 tests/build_diag_maps.py      # diag_maps (then build/diag_maps/diag_maps.exe --gdi GAME.gdi [options] MAP.bsp)
py -3.12 build.py --target x86_64-windows --no-snapshot   # reuse build/deps, do not wait for libsa1's lock
py -3.12 build.py --clean --lib-build --test --gdi "<your .gdi>" --maps <dir with gm_freespace_13.bsp ...>   # the gate
py -3.12 tools/lua_check.py            # syntax-check the addon (and --selftest)
```

`build.py` copies `LIB/build/<target>/libsa1.a`, `LIB/include/libsa1.h` and `LIB/include/libsa1_audio.h` into
`build/deps/` while holding libsa1's own build lock (`LIB/build/.build.lock`), so a libsa1 build running at the same
time never hands over a half-written archive. Since 0.5.1 it refuses an archive older than libsa1's sources (headers,
`LIB/src`, the lowered game code, the generated stubs; `--allow-stale` overrides) and `--lib-build` runs libsa1's own
build for each target first; `build/BUILD_INFO.txt` records both archives' freshness. Compiler: zig's clang (C++17, `-O2`, static libc++), MinGW ABI on
Windows, glibc 2.17 symbols on Linux. Outputs in `build/<target>/`: `gmcl_gsa1_win64.dll` / `gmcl_gsa1_linux64.dll`,
`core_test`, `binding_test`, `collision_test`, `pad_test`, `map_test`; `build/BUILD_INFO.txt` records the libsa1 snapshot hashes, the
gmod-module-base commit, the module's exports (exactly `gmod13_open`, `gmod13_close`; the build fails otherwise) and
imports (Windows: KERNEL32, USER32, comdlg32 and the Universal CRT that ships with Windows 10+; Linux: glibc only).
XInput is not among them: the module loads it at run time (see "Security").
The first link per target compiles zig's libc++ (tens of thousands of header warnings, hidden by build.py).

`--test` runs `pad_test` (no disc, no map: the controller mapping), `core_test --fuzz 60`, `binding_test`,
`collision_test`, `map_test`, every feature's `tests/feat_*_test` and `tests/feat_*_binding_test` (with `--gdi`), and
on Windows the Lua tests in Garry's Mod's LuaJIT (`log_test`, `warm_test`, `frame_test`, `seam_test`, every
`tests/feat_*_test.lua`); it lists the features it found at the start and the failed test programs at the end. A
lock on `build/.build.lock` serialises whole runs of `build.py` (a second one waits, `--lock-timeout`). (`map_test` reads the game's VPKs and gm_construct for the model files; `--maps DIR`
adds the static prop checks of gm_bigcity_improved_rp / gm_driversheaven_tdm; the others read
`<GarrysMod>\garrysmod\maps\gm_construct.bsp` read-only; `--bsp` for another map)
with `--gdi` or `$SA1_TEST_GDI`. The Linux binaries are built, not run here. Offline results (this machine, x64):
gm_construct's map job (brushes, displacements, 4 static props, 8 brush entity models, cleaned) takes about 45 ms and
gives about 33,000 collision triangles, which the job's worker prepares for libsa1 in 90-100 ms (158,000 GRID pieces in
5,300 land objects); a character is created in 2-4 ms (0.5.0: the first one 135 ms with the GRID synthesis, then 5-35
ms); a tick costs about 0.05 ms, a render 0.01-0.03 ms; Sonic draws about 1,000
triangles in 17 batches (16 opaque, 1 blended: the shoe buckle), Tails 1,237 in 26 (12 blended: the tails' fading
copies); the disc loads in about 250 ms and the sound banks open in about 20 ms, both on worker threads.

## Versioning

* `GSA1_MODULE_VERSION` (module, `gsa1_module.cpp`) and `GSA1.VERSION` (addon, `sh_config.lua`) are raised together,
  once per release, by the release step (sadc `docs/research/gsa1_rounds_plan.md` 2.5), with a "What x.y changes"
  section here.
* The base `gsa1.API_VERSION` (module) and `GSA1.REQUIRED_API` (addon) change **only for a breaking change** of the
  built-in functions (a function removed, an argument or a result changed incompatibly), and **always together in one
  edit**: the addon refuses a module whose API is not exactly its own (`cl_module.lua`), so they are installed as a pair.
* **New functions arrive as features** (below), never as new base API: `gsa1.FEATURES = { name = version }`, and the
  addon's files check `GSA1.HasFeature(name, min_version)`. A feature's version rises when its own functions grow; an
  addon whose module lacks a feature keeps working and its page says which module it needs.

## Features (adding a part of G-SA1)

Since G0 (the feature seam), a later part of G-SA1 (the interaction layer, Super Sonic, followers, the jukebox) lives in
its own files and never edits the shared ones (`gsa1_module.cpp`, `session.cpp`, `cl_menu.lua`, `sh_config.lua`, the
autorun) beyond a small patch its task names:

| What | Where | How it is found |
|---|---|---|
| Its Lua functions in the module | `src/module/bind_<feature>.cpp` | `GSA1_FEATURE(name, version, fns, open_fn, close_fn, close_priority)` (`src/module/gsa1_feature.hpp`) registers it at static-initialisation time; `build.py` compiles every `src/module/*.cpp` |
| Its core | `src/core/<feature>.{hpp,cpp}` | `build.py` compiles every `src/core/*.cpp` |
| Its Lua | `addon/lua/gsa1/feat/sh_<feature>.lua`, `cl_<feature>.lua`, `sv_<feature>.lua` | the autorun, after the built-in files: `sh_` in both realms first, then `cl_` on the client and `sv_` on the server, each alphabetically (the server sends `sh_` and `cl_` to the clients) |
| Its Q-menu page | its `cl_` file | `GSA1.AddMenuPage(order, id, title, builder [, needs])` (`cl_menu.lua`): after the built-in pages, by `order` |
| Its settings | its `sh_` / `cl_` file | `GSA1.ConVar(name, default, help, min, max [, flags])` (`sh_config.lua`): a client setting, or with `{ server = true }` a replicated, archived server setting; each gets a control on its page |
| Its tests | `tests/feat_<feature>_test.cpp` (core), `tests/feat_<feature>_binding_test.cpp` (module + `tests/mock_lua.hpp`), `tests/feat_<feature>_test.lua` (GMod's LuaJIT + `tests/lua_mock.lua`) | `build.py --test` builds and runs them all |

The module (`gsa1_module.cpp`): at `gmod13_open`, after the built-in functions and constants, every feature's
functions go into the `gsa1` table - a name that is taken (a built-in, another feature's) is not replaced and the clash
is listed in `gsa1.FEATURE_ERRORS` (the addon prints it) - `gsa1.FEATURES` lists the features, and their open hooks
run (by name). `gsa1.Shutdown()` runs their shutdown hooks (`GSA1_FEATURE_ON_SHUTDOWN`) before the session's
characters go. `gmod13_close` runs their close hooks, lowest `close_priority` first (the jukebox: `gsa1::kCloseFirst`),
before the session, the sound output, the controller and the map workers are destroyed. A feature's functions follow
the module's binding rules (no Lua error is ever raised, `nil, message[, code]` for a bad argument, raw table writes,
no paths in or out): `GSA1_FN` and the shared helpers (`arg_*`, `push_nil_msg`, `raw_*`, `ready_or`, `session()`,
`audio_out()`, `gmod_dir()`, `scrubbed()`) are in `src/module/gsa1_module_internal.hpp`, namespace `gsa1::mod`.
The addon: `GSA1.HasFeature(name, min_version)` (`cl_module.lua`); a page registered with `needs = { feature =
"jukebox", version = 1, module = "0.7.0" }` says "This page needs G-SA1 module 0.7.0 or newer ..." when the loaded
module lacks it; a feature file or a page that raises a Lua error is reported (console, session log) and the rest of
G-SA1 carries on; the status lines and the session log list the module's features and the loaded feature files.
`tools/lua_check.py` checks the `feat/` files and refuses names the autorun would not load. The seam's own tests:
`binding_test` (two dummy features: `gsa1.FEATURES`, a refused clash with `Status`, the open hook once, shutdown hooks,
close hooks in close order with the session alive), `tests/feat_seam_test.cpp` and `tests/feat_seam_binding_test.cpp`
(the templates of a feature's tests, run by the feature-test plumbing) and `tests/seam_test.lua` (the autorun's
feature loading in both realms, a broken feature file, the pages, the ConVar helper, `HasFeature`).

Features of 0.8: `surfaces` 1 (the ground types), `render` 1 (`src/module/bind_render.cpp`: `gsa1.DrawList(id, out)` -
one frame's draw list for `gsa1_logdraws`; and the promise that `gsa1.PrepareView`'s 12th argument, an origin, makes
`EmitBatch` write positions relative to it - the addon's camera-relative drawing asks `GSA1.HasFeature("render")`
before it uses it). Its tests: `tests/feat_render_test.cpp` (the shadow batch of all six characters, relative
positions, the emulated float32 / D24 depth path) and `tests/feat_render_binding_test.cpp`.
Round 5 adds `interact` 1 (`src/module/bind_interact.cpp`, `src/core/interact.*`, `feat/{sh,cl,sv}_interact.lua`,
`feat/cl_hud.lua`; "Interaction" above) with `tests/feat_interact_test.cpp`, `tests/feat_interact_binding_test.cpp`
and `tests/feat_interact_test.lua`. Round 0.9.1 adds `hud` 1 (`src/module/bind_hud.cpp`; `feat/cl_hud.lua` now belongs
to it: "The HUD (0.9.1)") with `tests/feat_hud_binding_test.cpp` and `tests/feat_hud_test.lua`.

## Installing (Windows, the owner's machine)

Garry's Mod must run as the **64-bit** build (`gsa1_status` / `lua_run_cl print(jit.arch)` says `x64`). Close
Garry's Mod first, then in PowerShell:

```powershell
$gm = '<GarrysMod>\garrysmod'
$gs = '<project>\g-sa1'
# 1. the module: garrysmod\lua\bin\gmcl_gsa1_win64.dll
Copy-Item "$gs\build\x86_64-windows\gmcl_gsa1_win64.dll" "$gm\lua\bin\gmcl_gsa1_win64.dll"
# 2. the addon: garrysmod\addons\gsa1\lua\... (an older copy is replaced)
if (Test-Path "$gm\addons\gsa1") { Remove-Item -Recurse "$gm\addons\gsa1" }
Copy-Item -Recurse "$gs\addon" "$gm\addons\gsa1"
# 3. the disc path, in the module's own config file (outside the game directory; Lua cannot read or write it)
New-Item -ItemType Directory -Force "$env:APPDATA\gsa1" | Out-Null
Set-Content -Encoding utf8 "$env:APPDATA\gsa1\config.txt" 'disc = <project>\Sonic Adventure v1.005 (1999)(Sega)(US)(M5)[!][%51000-A].gdi'
```

The module and the addon must be updated together (the addon checks the module's API version, now 6). Afterwards
these three exist: `garrysmod\lua\bin\gmcl_gsa1_win64.dll`, `garrysmod\addons\gsa1\lua\autorun\gsa1_autorun.lua`,
`%APPDATA%\gsa1\config.txt`. Instead of step 3 you can press "Choose disc" in Q -> Options -> G-SA1 -> Disc and
status, or run `gsa1_choose_disc` (a Windows file dialog; it writes the same file; use windowed or borderless mode
for it).

The config file: UTF-8, one line `disc = <absolute path of the .gdi>` (optional quotes, `#` comments; any other
key, a relative / UNC / device path or a non-.gdi file is refused with a message). The disc must be Sonic Adventure
(US) v1.005: libsa1 checks the SHA-1 of `1ST_READ.BIN` (`e74c849806db103aa87f84e41a382873bc96b6df`) and of every
file it reads.

Linux (64-bit client): `gmcl_gsa1_linux64.dll` into `garrysmod/lua/bin/`, the addon as above, the config in
`~/.config/gsa1/config.txt` (or `$XDG_CONFIG_HOME/gsa1/config.txt`). Under Proton the Windows files apply.

Uninstall: take those three files / folders out again.

## Using it

Start a **Single Player** game on gm_construct. Open the spawn menu (Q), the **Options** tab on the right, category
**G-SA1**:

| Page | Contents |
|---|---|
| Character | character choice, Spawn / switch, Remove, Respawn, a quick-spawn button per character, **upgrades** (a checkbox per upgrade of every character, All upgrades, No upgrades, Re-create the character here), controls, "server moves my player along", raw Dreamcast stick, a short status (with the upgrades and the game's equipment) |
| Camera | distance (0 = first person), height |
| Controller | use the controller, which one (automatic / 1-4), live status (connected, sticks before and after the dead zones, triggers, buttons held and the SA1 buttons they give, rumble), dead zones, full deflection, trigger threshold, D-pad moves, camera speed, response curve, invert Y, what each button and trigger does, default buttons, rumble on / off, strength, test rumble |
| Rendering | interpolation, map lighting, effects, line effect width, vertex colours of effects, reverse winding, both sides, texture painting speed, prepare the materials when a character appears (the pre-warm), "Check the painted textures", "Repaint the textures", debug overlay |
| Sound | sound on / off, volume, sound effects, voices, music and jingles (0..4), character voices, jingles, background music, other players' voices from their position, voice language (English / Japanese), "Reopen the sound banks and the output", sound status |
| Collision | static props collide, thin walls up to N units thick (0 = off, default 16), keep each map's collision in a cache, load the disc and the map's collision when the map starts, "Reload the map's collision", "Delete the cached maps", brush entities, physics props and vehicles, the live map status (triangles, static props, brush entities, one-way platforms, moving objects, the cache) |
| Disc and status | choose disc (Windows file dialog), load now, load when the map starts, reload the map's collision, print the status, the session log (on / off, its slow-frame threshold, "Mark this moment in the log"), log slow frames (hitches) to the console and their threshold, the live status of the module, disc (loading on a worker / loaded / why it failed), world (loading stage, prepared), sound (opening / open), the session log, the pre-warm and the character |
| Interaction (module with the feature `interact`) | interaction on / off; the keys (the layout, the interact key's binder, "also lifts props", "enters vehicles", "back as the character after the vehicle"); getting hit (can die, rings scattered, knock-back away from the attacker); per kind of target (hostile, neutral, friendly NPCs, vehicles, players, props, hazards): attack, targeting, touch harm, and for props pushing with its strength and rolling factor; carrying props; balloons (on, launch kind, speed, pop on touch); NPCs solid, objects the game sees at once, draw the shapes; the HUD switch; the server's section (damage, damage mode, PvP, carrying limits, pushing, balloons, the interact key, damage per attack); a live status |
| HUD (module 0.9.1, feature `hud`) | show the Sonic Adventure HUD; the parts (rings, lives, time, the characters' own displays, the score); size, wide screens (the corners / a centred 4:3 box), distance from the edges, smooth / sharp textures, hide Garry's Mod's health; the game clock runs, E-102's 3-minute time limit, keep the time after a respawn |
| Jukebox (module 0.7.0) | now playing (title (file), time / length, "loops from m:ss", state and plan), Previous / Play / Pause / Stop / Next, the position slider, the group (all, the sound test's six pages, not in the sound test), the track list (number, title, length, loop start; double-click plays, hover for notes), play mode (repeat the track / play the list / shuffle), loops before the next track (1..10), fade-out (0..10 s), include jingles and title cards, show the tracks that are not in the sound test, jukebox volume, follow Garry's Mod's music volume, silence the game's music while it plays (and, ticked separately, its jingles), keep playing while paused or in the background, the engine's status |

Or the console: `gsa1_spawn sonic` (or `tails`, `knuckles`, `amy`, `gamma`, `big`). The disc (about 0.25 s), the
sound banks (about 20 ms) and the map's collision load in the background, on the module's worker threads - when the map
starts (`gsa1_preload`) or at the first spawn; a spawn before they are ready says so ("loading your disc; loading the
map's collision: preparing it for the game 93%") and happens by itself when they are; the character appears where you
stand, facing your view direction. Sounds start as soon as the sound banks are open.

| Input | SA1 |
|---|---|
| movement keys / GMod joystick | analog stick, relative to the camera (mouse yaw) |
| jump | A (jump) |
| crouch, attack, attack2 | B (action: spin dash, punch, ...; lift, put down and throw a prop) |
| use (E) | interact: doors, buttons, vehicles; lifts props too (the Interaction page; round 5) |
| reload | Y |
| walk | half stick |
| mouse wheel | camera distance (0 = first person) |
| controller | see "What 0.3.0 adds" (left stick, right-stick camera, A jump, B / X action, Y, LB / RB, LT / RT camera, Back camera reset) |

`gsa1_remove` ends it (the player is put back on its feet at the character), `gsa1_toggle` spawns / removes (bind
a key: `bind g gsa1_toggle`), `gsa1_respawn` returns to the spawn point. The character respawns by itself when it
dies (kill plane below the map, the game's death sequence) or falls out of the world.

**Weapons while a character (0.8.0).** The character is your body, so the weapon you hold is put away when it
appears and given back when it goes (`gsa1_060_weapon.md`; 0.6.0 left the Physics Gun's glow on screen). Putting it
away is an ordinary switch to empty hands (`gsa1_hands`, never drawn), so the weapon's own holster runs: no Physics
Gun beam or glow, no tool gun ghost or help panel, the camera's zoom and hidden HUD end (G-SA1's overlay stays
visible), a Gravity Gun lets go of what it holds. While a character no weapon can be taken into the hands (number
keys and last weapon do nothing; a weapon from the spawn menu or picked up goes into your inventory only), the
flashlight is off and cannot be switched on, and other players see no weapon (multiplayer). A weapon that refuses to be
put away is retried and, after a second, replaced anyway. Switching characters keeps the weapon put away; `gsa1_remove`
gives back the weapon you held (or the default one if it is gone). There is no option for it (owner default). Other
addons can ask `GSA1.IsCharacter(ply)` (both realms; a networked flag).

Commands: `gsa1_spawn`, `gsa1_remove`, `gsa1_toggle`, `gsa1_respawn`, `gsa1_init`, `gsa1_choose_disc`,
`gsa1_reload_world`, `gsa1_cache_purge`, `gsa1_status`, `gsa1_sound_reopen`, `gsa1_texcheck [n]`, `gsa1_texrepaint`,
`gsa1_log_mark [text]`, `gsa1_log_where`, `gsa1_pad_status`,
`gsa1_pad_defaults`, `gsa1_pad_test_rumble`, `gsa1_upgrades_apply` (re-create the character here with its ticked
upgrades), `gsa1_upgrades_all 1|0 [character]`; the jukebox: `gsa1_jukebox_play <number | file | words of the
title>` (no argument: the selected or last track, or resume), `gsa1_jukebox_pause [1|0]`, `gsa1_jukebox_stop`,
`gsa1_jukebox_next`, `gsa1_jukebox_prev`, `gsa1_jukebox_list [words]`.
ConVars (client, archived; every one is also on the Options pages): `gsa1_character` sonic, `gsa1_stick_raw` 0,
`gsa1_follow_player` 1, `gsa1_cam_distance` 150, `gsa1_cam_height` 20, `gsa1_interpolate` 1, `gsa1_lighting` 1,
`gsa1_vertexcolor` 1, `gsa1_effects` 1, `gsa1_line_width` 2, `gsa1_flip_winding` 0, `gsa1_nocull` 0,
`gsa1_texture_runs_per_frame` 6000, `gsa1_prewarm` 1, `gsa1_sound` 1, `gsa1_sound_volume` 1, `gsa1_sound_sfx` 1, `gsa1_sound_voice` 1,
`gsa1_sound_music` 1, `gsa1_sound_voices` 1, `gsa1_sound_jingles` 1, `gsa1_sound_bgm` 0, `gsa1_sound_3d_voices` 1,
`gsa1_sound_japanese` 0, `gsa1_debug` 0; collision: `gsa1_static_props` 1, `gsa1_brush_entities` 1,
`gsa1_physics_props` 1, `gsa1_map_cache` 1, `gsa1_thin_walls` 16 (0 = off), `gsa1_preload` 1 (the disc and the map's
collision); hitches: `gsa1_hitch_log` 1, `gsa1_hitch_ms` 100; the session log: `gsa1_log` 1, `gsa1_log_hitch_ms` 50;
controller: `gsa1_pad` 1, `gsa1_pad_index` 0 (automatic, 1-4),
`gsa1_pad_deadzone` 0.2, `gsa1_pad_deadzone_right` 0.2, `gsa1_pad_outer` 0.95, `gsa1_pad_trigger` 0.12,
`gsa1_pad_cam_speed` 180, `gsa1_pad_cam_curve` 1.5, `gsa1_pad_invert_y` 0, `gsa1_pad_dpad` 0, `gsa1_pad_rumble` 1,
`gsa1_pad_rumble_strength` 1, and per input `gsa1_pad_a` 1, `_b` 2, `_x` 2, `_y` 3, `_lb` 4, `_rb` 5, `_lt` 6, `_rt` 7,
`_start` 0, `_back` 8, `_ls` 0, `_rs` 0 (0 nothing, 1 jump, 2 action, 3 SA1 Y, 4 SA1 L, 5 SA1 R, 6 camera left,
7 camera right, 8 camera reset); upgrades (all 0 by default, the game's start): `gsa1_upgrade_light_speed_shoes`,
`_crystal_ring`, `_ancient_light`, `_jet_anklet`, `_rhythm_badge`, `_shovel_claw`, `_fighting_gloves`,
`_warrior_feather`, `_long_hammer`, `_jet_booster`, `_laser_blaster`, `_life_belt`, `_power_rod`, `_lure_1` ..
`_lure_4`; the jukebox: `gsa1_jukebox_mode` 0 (0 repeat the track, 1 play the list, 2 shuffle), `gsa1_jukebox_loops` 2
(1..10), `gsa1_jukebox_fade` 4 (0..10 s), `gsa1_jukebox_jingles` 0, `gsa1_jukebox_hidden` 1 (show the 5 tracks that
are not in the sound test), `gsa1_jukebox_volume` 1 (0..1), `gsa1_jukebox_duck` 1, `gsa1_jukebox_duck_jingles` 0,
`gsa1_jukebox_gmod_music` 1, `gsa1_jukebox_background` 0, `gsa1_jukebox_group` 0 (0 all, 1-6 the sound test's pages,
7 not in the sound test). Server: `gsa1_sv_follow` 1.

## In-game test checklist

Since 0.6.0 nothing needs copying: every `[G-SA1]` line, every slow frame and a summary go into
`garrysmod/data/gsa1/log.txt`, which Claude reads after the test - just say when you played and what you saw (press
"Mark this moment in the log" on the Disc and status page, or a key bound to `gsa1_log_mark`, when something
happens). `gsa1_debug 1` shows the overlay with the timings.

1. **Module.** `gsa1_status` prints `module 0.6.0 (API 6, libsa1 0.2.0); addon 0.6.0` and a line `render targets:
   BGRA8888, alpha kept (painted 96 -> 96, alpha 0 -> 0, unpainted -> 0; seen through a translucent material: 234 197
   178 / 255 / 255)` (0.8's probe; report it if it says `LOST`, `not readable`, `alpha 1`, `cleared by drawing` or
   another format).
   If it says the module is not installed, needs 64-bit or has an older API, check the file name / location (module
   and addon must both be 0.6.0) and `lua_run_cl print(jit.arch)`.
2. **Disc, sound and map.** About a second after the map starts (or after `gsa1_init`) the console prints `disc loaded
   in N ms on a worker thread`, `sound: sound banks opened in N ms on a worker thread (English voices); output: BASS
   2.4.18.x (Garry's Mod)` and `world gm_construct: N collision triangles (4 static props placed, 8 brush entity models,
   ... one-way platforms, ... thin walls) built, cached, prepared for the game in N ms on a worker (... pieces), in 0.x
   s` (or `from the cache`). If a line names an error instead, report it (sound needs Garry's Mod's own audio
   library).
3. **Options menu.** Q -> Options -> G-SA1 shows the seven pages; the status on "Disc and status" updates by itself;
   every checkbox / slider changes its ConVar (and back). The old Utilities -> G-SA1 entry is gone.
4. **Spawn.** "Spawn / switch" (or `gsa1_spawn sonic`): Sonic stands at your feet, chase camera, the player model
   hidden and the weapon put away (no Physics Gun glow anywhere; given back on remove: items W1-W7 below),
   `Sonic spawned at (...); N textures loading`.
5. **Textures and eyes (fixed in 0.2.0).** Within about a second: clean textures (no noise on the chest, gloves,
   shoes, soles), **eyes with pupils**, **peach arms**, the shoe buckle. Then `gsa1_texcheck`: `texture check: N
   render targets, M samples, 0 differ by more than 2` (report the lines it prints otherwise).
6. **Tails (fixed in 0.2.0).** `gsa1_spawn tails`: orange tails with white tips; the fading copies of the tails
   behind them when they move, layered over (not under or through) the body; eyes fine.
7. **Interpolation (fixed in 0.2.0).** At a high frame rate (`fps_max 0` or 144+), running and turning look smooth
   with `gsa1_interpolate 1` (limbs too, not only the position); `gsa1_interpolate 0` visibly steps at 30 Hz. Note
   the "drawn in N ms" figure of the debug overlay for both settings and the FPS with and without a character.
8. **Effects (fixed in 0.2.0).** Sonic: spin dash (hold crouch on the ground, release): the blue ball / trail;
   Knuckles: attack = punch flash; E-102: hold attack = the targeting lines; Amy: hammer. Untick "Effects": they
   go. (Dust, sparks, splashes and Big's fishing target are not drawn yet.)
9. **Sound (new in 0.2.0).** Jump, spin dash, landing, voices on actions; volume sliders
   and the checkboxes act immediately; Garry's Mod's own volume applies; the escape menu pauses the sound; voice
   language Japanese reopens the banks. Report any crackle (and the "queued" figure of the sound status).
10. **Collision (fixed in 0.2.0).** Land on the garage roof (and jump around on it): no falling into the garage; the
    building west of the spawn and its upper floor; the stairs of the main building (up and down).
11. **Running.** Hold W: Sonic accelerates along the camera direction, straight; A / D / S and diagonals relative to
    the mouse; walk (Alt) is slower; release: he slows and stops.
12. **Terrain.** The grassy displacement hills, the pool (water: Sonic sinks / swims, breath timer in `gsa1_debug
    1`), walls (stopped, not through), ceilings, glass.
13. **Falling.** Leave the map's walkable area or fall into a hole: death sequence or respawn at the spawn point.
14. **Others.** `knuckles` (glide, climb a wall; glass and the sky must not be climbable), `amy`, `gamma`, `big`:
    each spawns, runs, jumps, has textures and sounds.
15. **Camera.** Mouse orbit, wheel zoom, distance 0 = first person (the character hidden), the camera stops at walls.
16. **Device reset.** Alt-tab out of exclusive fullscreen and back: the textures come back within about a second.
17. **Lifetime.** Remove (you stand at the character's place and walk normally again); spawn again; `changelevel
    gm_construct` and spawn again; quit to the menu: no crash, no sound left playing.
18. **Pause.** Escape menu in single player: the character and its sounds freeze and continue.
19. **Safety spot checks** (expected refusals): `lua_run_cl print(gsa1.WorldLoad("../../cfg/config"))` prints
    `false ... bad_name`; `lua_run_cl print(gsa1.Init("C:\\x"))` ignores the argument.

Controller (new in 0.3.0; an Xbox-style pad plugged in or paired before starting, Garry's Mod's own `joystick 0`):

20. **Found.** Q -> Options -> G-SA1 -> Controller: the live status says `controller: 1 in use (XInput:
    xinput1_4.dll)` (or the slot it is in) and the stick and trigger figures follow the pad without a character;
    `gsa1_status` has the same `controller:` line. Unplug it: `none connected`; plug it in again: found within about
    a second. Report the line if it says `not available` or the pad is not found.
21. **Moving.** With a character: the left stick runs relative to the camera; a small push walks, a full push runs,
    the direction follows the stick smoothly (no 8-way snapping); released, the character stops and does not creep
    (raise "Left stick dead zone" if it does, and report the value that works).
22. **Buttons.** A jumps, B and X spin dash / punch / attack, Y does Y's action; holding B on the ground with Sonic
    charges the spin dash. Start does nothing.
23. **Camera.** The right stick orbits the camera (right = turn right, up = look up; "Invert Y" reverses up / down),
    LT / RT turn it left / right by how far they are pulled, Back swings it behind the character; "Camera speed" and
    "Response curve" change how fast it turns; the mouse still turns it too.
24. **Priority.** Play with the pad, then let go and use the keyboard: about a second later the keyboard moves the
    character again; touch the pad and it takes over at once. Holding a keyboard key while using the pad does not
    pull the character sideways.
25. **Mapping.** Set "Start / Menu" to "Jump (SA1 A)": Start jumps; "Default buttons" restores everything. Set
    "Controller" to a fixed index: only that pad is read (with two pads, automatic follows the one you use).
26. **Rumble.** "Test rumble" shakes the pad for 0.6 s. Knuckles' punches (B) and other vibration moments of the game
    shake it briefly; untick "Rumble" or lower "Rumble strength": quieter / still. The escape menu stops it at once;
    no rumble keeps going after `gsa1_remove`, a map change or quitting.
27. **Off.** Untick "Use the controller": the pad does nothing, the status says `off`.

New in 0.4.0 (the owner's test of 0.2.0):

28. **High speed (fixed).** Sonic: spin dash (hold crouch, release) and roll at full speed, and run at top speed, at
    a high frame rate (`fps_max 0` or 144+) and at 60: the character stays put in the camera (no forward-backward
    flicker). With `gsa1_debug 1` the overlay says "moved with the root" while rolling. Also try Knuckles gliding,
    Tails flying, E-102 hovering (Jet Booster).
29. **Alpha (fixed, untested in game).** Knuckles: glide into a wall and climb (hold forward): the dust clumps have
    soft, see-through edges (no squares). Sonic's spin dash ball / trail and Knuckles' punch flash too. `gsa1_texcheck`
    prints a second line `texture check, alpha: N samples (M not opaque), 0 differ ...`; report both lines and the
    `render targets:` line of `gsa1_status`.
30. **Upgrades.** Q -> Options -> G-SA1 -> Character -> Upgrades: tick Knuckles' Shovel Claw and Fighting Gloves
    while playing Knuckles: he is re-created where he stands with the claws / gloves drawn, the console says
    `Knuckles re-created where it stood (upgrades changed); upgrades: Shovel Claw, Fighting Gloves`, and the status
    shows `upgrades: Shovel Claw, Fighting Gloves (the game's equipment 0x0060)`; hold attack on the ground to charge
    Maximum Heat. Untick them: the plain hands again. Sonic with Light Speed Shoes (hold attack to charge the light
    speed dash), E-102 with Jet Booster (hold jump in the air: he hovers), Amy with Long Hammer (a longer hammer),
    Tails with Jet Anklet (anklets), Big with Life Belt / Power Rod. "All upgrades" / "No upgrades" re-create once.
    Report any `upgrades: ... NOT what the upgrades ask for` line.

New in 0.5.0 (the owner's test of 0.3.0; `gsa1_debug 1` shows the timings, report every `[G-SA1] hitch:` and
`[G-SA1] capacity at (...)` line):

31. **Ball (fixed in libsa1).** Sonic: jump, spin dash, roll down a slope, at 144+ fps and at 60: the ball stays round
    and the same size (no flattening or widening between frames); the other characters' moves look as smooth as before.
32. **Ramps (fixed).** gm_freespace_13 (the workshop map): run, spin dash and boost up the big stunt ramps and the
    smaller ones, from the side and at an angle: no falling through. Also the long road strips of a city map
    (gm_bigcity_improved_rp, gm_goldencity_v2_day) right after spawning.
33. **Thin walls (new).** Run and spin dash into fences, glass panes, thin walls and closed doors with every character
    (Big and E-102 especially): they stop the character (it may look up to half the wall's thickness inside a wall of
    16 units or less); none lets it through.
34. **Map loading (new).** On a workshop map you have not played with G-SA1 yet: spawn at once after the map starts -
    `G-SA1: loading the map's collision: reading the map 40%` on screen, no freeze, and the character appears by itself
    when it is ready; the console says `world <map>: N collision triangles (...) built, cached in N s`. `changelevel`
    to it again: `... from the cache in 0.x s`. Note the times for the report.
35. **Static props (new).** gm_construct / a city map: land on and run against static props (benches, cars, crates,
    rocks): they collide. Untick Q -> Options -> G-SA1 -> Collision -> "Static props collide": the map's collision
    reloads (the character is re-created where it stands) and the props are passed through.
36. **Moving objects (new).** Doors, lifts, trains, func_brush (gm_construct has some) and physics props (spawn a few
    from the Q menu: a crate, a car, a plank on two crates): the character is stopped by them, stands on them and is
    carried along (a prop pushed with the physics gun, a moving lift); a door that opens lets it through; frozen and
    unfrozen props; the Collision page's status counts them (`moving objects (...): N near, M in the game`).
    "Brush entities" / "Physics props and vehicles" off: they are passed through.
37. **Cache.** Collision page: "Delete the cached maps" -> `map cache: N file(s) deleted`; the next load builds again.
    `garrysmod/data/gsa1/cache/<map>.dat` holds only the collision built from the map.
38. **Freezes (fixed where found).** Play for a while on the maps where it froze (music and jingles, the drowning
    countdown under water, voices): no stalls; `gsa1_status` says `disc reads on libsa1's loader thread: preloaded`.
    If a frame still freezes, the console prints `hitch: a frame took N ms; G-SA1 ... ms: <section> ...` - report the
    line (it says whether G-SA1 took the time, and which part). Q -> Options -> G-SA1 -> Disc and status: "Log slow
    frames" and the threshold.
39. **Device reset canary.** No periodic hitch every 2 seconds any more (0.4 read a pixel back from the GPU every
    2 s); alt-tab still restores the textures (item 16).

New in 0.5.1 (nothing slow on the game's thread; report every `[G-SA1] hitch:` line, `gsa1_hitch_ms 50` makes the
logger stricter):

40. **First spawn without a hitch.** Start a map you have not used with G-SA1 since starting Garry's Mod and spawn
    at once (`gsa1_spawn sonic` within a second): `G-SA1: loading your disc; loading the map's collision: ...` on
    screen, the game keeps running, the character appears by itself; no `hitch:` line names `Init`, `Sound`, `Apply`,
    `Create`, `Textures` or `Texture info`. With `gsa1_preload 1` (the default) the disc and the map are usually ready
    before you spawn.
41. **Respawn and switching.** Fall off the map / `gsa1_respawn`, and switch through every character from the
    Character page several times: no stall when a character appears (each one about 3 ms in the module).
42. **Sounds.** After a fresh start the first jump may be silent if the sound banks are still opening (well under a
    second); after that every sound plays. Switch the voice language on the Sound page: no stall, the voices change a
    moment later.
43. **Thin walls (new setting).** Q -> Options -> G-SA1 -> Collision -> "Thin walls up to (units thick)": 0 lets the
    character slip through thin fences, panes and doors at speed again, 16 (the default) stops it, 32 also catches
    thicker walls. Each change reloads the map's collision in the background (the character keeps playing, then is
    re-created where it stands); the Collision status shows `thin walls: N (up to M units)`.
44. **Reload and cache.** "Reload the map's collision" and "Delete the cached maps" while playing: the character keeps
    running on the old collision until the new one is ready (`world ...: ... prepared for the game ...`), then is
    re-created where it stands - no freeze in between.
45. **One-way slabs (libsa1 change).** Slabs, planks and thin floors up to 48 units thick can be jumped through from
    below and landed on (the price of the ramp fix in libsa1); report a floor you fall through from above.

New in 0.6.0 (round 4c; nothing to copy - the session log is read from disk):

46. **Session log.** Q -> Options -> G-SA1 -> Disc and status -> Diagnostics: "Keep a session log" is ticked; press
    "Mark this moment in the log" once. `gsa1_log_where` prints `session log: garrysmod/data/gsa1/log.txt (N bytes ...)`.
47. **Light Speed charge (fixed in libsa1).** Sonic with the Light Speed Shoes (and the Crystal Ring), hold the action
    button for about 4 s: small blue sparkles (green with the Crystal Ring) fly in and shrink, trailing thin streaks;
    once charged Sonic glows a translucent, pulsing blue added on top of him. Watch for flicker where the glow lies on
    the body (depth artefacts, UNVERIFIED). Release: the dash, and the camera and Sonic move together (no lurch).
48. **The freeze.** Charge right after spawning, and again a minute later. Does the game still freeze? Say which: the
    first charge only, every charge, or not at all - and press "Mark this moment in the log" (or the bound key) right
    after a freeze. With "Prepare the materials when a character appears" (Rendering page) off, the first charge after
    a spawn shows what the pre-warm saves; say whether it froze then.
49. **Vertical flicker (fixed).** Knuckles: jump standing and running, jump off something high and fall; Sonic and
    Tails: jump, land, fall from a height; Amy and E-102: walk up stairs, onto curbs and ledges - at 60 fps and at a
    high frame rate. The character stays put against the camera: no shaking up and down every frame. Knuckles' rise
    still alternates between the ball and the curled body (the game draws it that way). With `gsa1_debug 1` the
    overlay says "moved with the root by libsa1" during Knuckles' jump: that is expected now.
50. **Other effects (libsa1 round 4c).** Big's fishing line is one continuous line; Knuckles' Maximum Heat (Fighting
    Gloves, hold action on the ground) and the barrier ribbons show as bands; sprites everywhere have their game size.
51. **Vertex colours off.** Rendering -> untick "Vertex colours on effects and models": the Light Speed glow keeps its
    blue (only textured effects turn white).

The jukebox (round 6c; module and addon 0.7.0; it needs no character, and the Sound page's "Sound" may be off):

52. **The page.** Q -> Options -> G-SA1 -> Jukebox: "Reading the track list from your disc ..." becomes the list
    within a second or two, and the status says `engine ready: 109 tracks, ...`. "All tracks" shows 109 lines; each
    "Sound test N" group shows 11 / 40 / 11 / 12 / 10 / 20 tracks under the game's own titles (66 "Open Your Heart",
    28 "Emerald Coast:  Type 1", 61 "Jingle#E"); "Not in the sound test (file names)" shows NIGHTS_A, NIGHTS_S,
    SONIC_CD, SSRACING and TITLE2. Untick "Show the tracks that are not in the game's sound test": "All tracks" shows
    104. Hover a track: its loop and notes.
53. **Playing.** Double-click 28: it starts within about a second; "now playing" shows the title (file), `0:00 /
    1:52, loops from 0:42` counting up and `playing - repeat: ...`; at 1:52 the music goes on from 0:42 without a gap
    or a click (the game's own loop). A track without a loop (66) starts again at its end. Pause / Resume, Stop, Next,
    Previous (later than 3 s into a track it starts the track again), and the position slider (the music jumps there
    when you let go) all work; the "> " mark in the list follows the playing track.
54. **Play modes.** "Play the list" with loops 1 and fade-out 2: a looping track goes once more through its loop,
    fades out over 2 s, and the next track of the group starts; the jingles and title cards are skipped unless
    "Include jingles and title cards" is ticked. Switching the mode while a track plays keeps it playing from where it
    is. "Shuffle": every track of the group once, in a random order. Report any gap between tracks.
55. **Volume.** The jukebox volume slider acts at once; Garry's Mod's own volume applies; with "Follow Garry's Mod's
    music volume" ticked its music volume (Options -> Audio) scales the jukebox, unticked it does not.
56. **The game's jingles kept or silenced.** Sonic under water (gm_construct's pool) until the drowning countdown
    plays, with the jukebox playing: the countdown stays audible ("Silence the game's music" ticked, the default).
    Tick "... and the game's jingles (the drowning countdown too)": the countdown is silent while the jukebox plays and
    comes back when you press Stop. With "Background music" on (Sound page) and any game music playing, that music
    fades out while the jukebox plays and back in when it stops.
57. **Stutters.** While a track plays, run `lua_run_cl local t = SysTime() while SysTime() - t < 1 do end`: the game
    freezes for a second, the music does not stop or skip (the module plays it from its own thread). Report the
    `underruns` figure of the page's status if it is not 0.
58. **Pause.** The escape menu (single player) pauses the jukebox and resumes it; alt-tab pauses it when Garry's Mod
    mutes out of focus (`snd_mute_losefocus 1`); with "Keep playing while the game is paused or in the background"
    ticked it plays on.
59. **Console.** `gsa1_jukebox_list`, `gsa1_jukebox_list emerald`, `gsa1_jukebox_play 66`, `gsa1_jukebox_play
    ecoast2`, `gsa1_jukebox_play twinkle park`, `gsa1_jukebox_next`, `gsa1_jukebox_prev`, `gsa1_jukebox_pause`,
    `gsa1_jukebox_stop`.
60. **Lifetime.** Change the map or quit to the menu while a track plays: the music stops, no crash. The session log
    has `jukebox` lines (music numbers and file names only).

Weapons and the session log (the 0.6.0 report's fixes; addon only; sandbox, single player):

W1. **Physics Gun.** Physics Gun out, then `gsa1_spawn sonic`: no glow anywhere (screen corner, at the character, on
    walls); the number keys and last weapon do nothing; a weapon picked from the Q menu goes into the inventory only.
    The session log's spawn line ends `weapon put away: weapon_physgun`. `gsa1_remove`: the Physics Gun is back in your
    hands and glowing.
W2. **Tool gun.** Tool gun with the thruster tool (it has a ghost): spawn - no ghost, no help panel; remove - the tool
    gun is back.
W3. **Camera.** Camera out: spawn - the HUD and the `gsa1_debug 1` overlay are visible and the zoom is normal;
    remove - the camera is back.
W4. **Gravity Gun.** Holding a barrel: spawn - the barrel drops and the hum stops; remove - the Gravity Gun is back.
W5. **Flashlight.** Flashlight on, then spawn: it goes off and F does nothing; after remove, F works.
W6. **Switch.** Sonic, then "Spawn / switch" to Knuckles: still no weapon, no glow; then remove: the weapon you held
    before Sonic is back. `lua_run print(Entity(1):GetActiveWeapon())` while a character prints `gsa1_hands`.
W7. **Pauses.** Open the escape menu for 10 s while running, then close it: the character goes on from where it was
    (no jump forward); the session log has a `pause` line, not a `hitch` line. `jump` lines should now be rare; report
    any, with what the character was doing. The `perf` lines say how many views drew the character per frame, and one
    `views` line says which (try `r_waterforceexpensive 0` and see whether it drops to 1).

### Ground types (0.8)

* gm_bigcity, the lawn by the start (-441 -3450 -11136, 8 units above the street): Knuckles with the Shovel Claw, standing,
  hold attack and press jump: he digs in and comes out again. Options > G-SA1 > Surfaces, the live line: `Under the
  character: dirt (diggable); the game: diggable`.
* gm_bigcity, the concrete beside it (-425 -3645 -11144): the game's "can't dig here"; the live line: `concrete (normal
  ground); the game: normal ground`.
* gm_construct: the grass digs, the concrete paths and floors do not.
* The Surfaces page: select concrete, choose "Diggable", Apply: the map's collision loads again in about a second (from
  the cache), the concrete digs; "Reset to the built-in table" undoes it. `gsa1_surfaces 0`: nothing digs (0.7's ground).
* The session log (`garrysmod/data/gsa1/log.txt`) has one `surfaces:` line per map.

### Shadows, see-through textures, precise drawing (0.8)

* **Alpha.** The session log's `render targets:` line says `alpha kept (painted 96 -> 96, alpha 0 -> 0, unpainted -> 0;
  seen through a translucent material: 234 197 178 / 255 / 255)`; `gsa1_texcheck`: `texture check, alpha: N samples (M
  not opaque), 0 differ by more than 2`. Knuckles: climb a wall and glide into one - soft brown clods, no dark frames;
  punch along the ground - faint white puffs, no squares; dig where digging works. Big: the belt ring and the cast mark
  without black patches. Amy: the stars over her head when she is dizzy (after the hammer spin) without squares.
* **Shadows.** Each of the six characters has a dark, soft oval under the feet: not a square, not grey; longer along the
  facing; smaller while jumping, tilted on ramps; gone high above the ground (after a spring or a long drop) and back on
  landing; Rendering -> "Character shadows" switches it independently of "Effects"; none in first person. Watch for
  flicker of the shadow on the ground at a distance (report the map and spot).
* **Big's eyes.** gm_bigcity around x 5400, y 7000-9000: Big standing still, orbit the camera - no specks or
  flickering edges on the eyes; turning and running circles - the eyes stay steady at 60 fps and at 144+. Then Rendering
  -> untick "Precise drawing far from the map's centre": the specks may come back (that confirms the cause); tick it
  again. Report anything drawn in the wrong place, missing in water reflections or oddly fogged with it ticked.
* **Tails.** When the see-through tails appear, run `gsa1_logdraws` (bind it to a key) and say what Tails was doing.

### Interaction (round 5): enemies, pushing, the interact key, carrying, balloons, the switches

Everything below is on Options > G-SA1 > **Interaction**; `gsa1_interact_status` prints what the interaction is doing,
and `gsa1_obj_debug 1` draws the shapes the game sees (red hostile, yellow neutral, green friendly, blue vehicles, white
liftable props, pink balloons, orange hazards).

1. **Enemies.** gm_construct, Sonic, spawn a zombie (NPCs > Zombies + Enemy Aliens): jump on it - it takes damage, Sonic
   bounces off; let it hit Sonic - the rings scatter, he blinks, you can pick them up again; the HUD's ring count (top
   left) counts; your health bar is hidden. With no rings a hit kills Sonic (he respawns); untick "The character can die": only
   knocked back. Three headcrabs in a row: jump, then press jump in the air again and again - a homing chain. A Combine
   soldier shooting at Sonic: one ring loss per 2 seconds. Knuckles punches an antlion; Amy's hammer on a manhack; Big's
   lure on a headcrab; E-102 locks on to two zombies and a jeep and fires: the zombies die (time bonus), the jeep is
   pushed. A citizen (friendly) is left alone; tick "Attack friendly NPCs" and set its targeting: now he can be hit.
2. **Pushing.** Spawn a wooden crate (Props > Construction, the small one) and run into it with Sonic: it slides away;
   keep pushing: it moves along slowly; spin-dash into it: it flies; a big container or a car hardly moves; stand on the
   crate: it stays where it is. The "Push strength" slider makes it weaker / stronger; untick pushing: the crate is a wall
   again.
3. **The interact key.** The Button tool: place a button that presses a lamp's numpad key; walk Sonic up to it, facing
   it, press E: the button is pressed and the lamp switches; a button with "Toggle" unticked stays pressed while you hold
   E, a toggle button switches with each press. A map with doors
   (gm_bigcity's buildings, any rp_ map): E in front of a door opens it as your player would (a locked door rattles, a
   door that only opens by its button stays shut). E in front of a jeep: Sonic disappears and you drive; get out: you are
   Sonic again. Bind another key on the page (or `bind f +gsa1_interact`) and try it.
4. **Carrying.** Spawn a watermelon, a small crate and a chair. Stand at one facing it and press attack (or E): Sonic
   lifts it over his head, it follows his hands as he runs; press again while running: he throws it (it flies at the
   game's speed and can knock a zombie over); standing: he puts it down. Tails, Knuckles, Amy, E-102 and Big lift the same
   props. A fridge (heavier than 35 kg): nothing happens (the server's limit is on the page).
5. **Balloons.** The Balloon tool: a few balloons at jump height in a row. Jump towards them and press jump in the air:
   Sonic homes onto one, it pops and he is launched up. Choose "Launch: like an enemy bounce": the homing attack goes on
   from balloon to balloon.
6. **The switches.** Hostile NPCs targeting "Off": the homing attack ignores zombies (E-102 too); "E-102's lock-on only":
   E-102 locks on, Sonic's homing does not. Vehicles attack off: the jeep takes no damage. "Touching them hurts" off for
   hostile NPCs: walking into a zombie no longer costs rings (jumping on it still hits it). Every switch should act at
   once (within a tenth of a second).
7. **Multiplayer (if you can test with a friend):** both as characters: a homing attack on the other knocks him back and
   scatters his rings; the server's PvP switch off stops it.

Report anything that feels wrong with the session log's time; for the interact key, say what you pressed it at (and
`gsa1_interact_status`'s last line).

### The HUD (0.9.1)

Everything below is on Options > G-SA1 > **HUD**; the session log gets a "hud" line per character (its parts, size and
screen) and one for each settings change.

1. **Sonic on your wide screen.** Top left: the time counting up from 00:00:00 with the TIME label, the ring icon and
   "000" blinking red; bottom left: Sonic's life icon and "04". Both sit in the screen's corners at the size the game's
   HUD has on a 4:3 screen of your height. Collect rings (or let a zombie hit Sonic): the count changes. Garry's Mod's
   health and suit display is gone while the rings are the damage.
2. **The page.** Size 0.5: smaller, still in the corners; "In a centred 4:3 box": the HUD moves to the middle 4:3 area;
   distance from the edges 5 %: it moves in; textures "Sharp": crisp pixels. Untick Time: the timer goes, and the ring
   icon stays without a lone "TIME"; untick Rings / Lives: they go; untick "Show the Sonic Adventure HUD": nothing, and
   Garry's Mod's health is back. Tick Score: "SCORE" with 7 digits under the ring icon.
3. **Each character.** Tails, Knuckles, Amy and E-102 show their own life icons. E-102: the time stays at 03:00:00; tick
   "E-102's 3-minute time limit": it counts down, turns yellow / red near the end, shows big last-seconds digits in the
   middle, and at 0:00 he dies and respawns at 03:00:00 (not 00:00:00). Lock-on kills (a few zombies) show the "+N"
   bonus flying from the right towards the timer.
4. **Big.** WEIGHT and the ring count top left, lives bottom left (his own HUD); cast the lure: the reel (it turns as you
   reel in) and the line-tension gauge appear on the right edge.
5. **Drowning.** Walk a character into deep water (gm_genesis' sea) and wait for the countdown music: the numbers 5..1
   appear above its head, where the camera sees it.
6. **Respawns.** Fall off the map (or drown): the new character's time goes on from where it was; switching to another
   character starts at 00:00:00. Untick "Keep the time": a respawn starts at 00:00:00.
7. **Hidden.** Look through a camera (the Camera tool's numpad key): no HUD; `cl_drawhud 0`: no HUD.

### The 0.9.2a fixes (0.9.3)

1. **Sound.** Play a while with continuous sounds (the spin dash charge, Tails flying, the music with "background music"
   on), also while the game stutters: no crackles or short drop-outs (the session log's sound line: a few underruns, not
   about 100 a minute).
2. **Teleporters.** gm_genesis, the spawn room: walk into the booth with the red column (the room's east side): the
   character appears once in the ACF area facing north, the camera behind it (it arrives standing); walk into the return
   column there: back in the spawn room. rp_nycity (or another map with doors that teleport): walking through keeps the
   facing. The session log has one `teleport` line per use and no "teleport loop". Untick "Map teleporters move my
   character": the character walks through the column.
3. **Restarts.** After a game code fault the character restarts with one short chat line, and a character spawned later
   is never reported as faulted.
4. **Power-ups.** Break an item box with the barrier: the blue sparkles show around the character; invincibility: the
   sparkling star ball and its sparks for about 21 seconds; the magnetic barrier: electric sparks that flicker and fade.
   With "effects" off they are hidden like the other effects.
5. **Rings.** In single player "Give 50 rings" and `gsa1_rings 50` both work; on a server only an admin, the host or
   `sv_cheats 1` may.

### Super Sonic (0.9.3a)

Everything below is on Options > G-SA1 > **Super Sonic**; the session log gets "super" lines.

1. **The two Super Sonics.** Pick "Super Sonic (General Gameplay)" (the Character page's list or the page's button):
   for a moment normal Sonic, then golden with 50 rings. Run, jump, **spin dash**, home in on an NPC, tick the Light
   Speed Shoes on the Character page and hold the action button, then release (Light Speed Dash), pick up a prop.
   Compare his top speed with Sonic's on a long straight. Then pick "Super Sonic (Vs. Perfect Chaos)": as in 0.9.3 (the
   action button in the air stops him; no spin dash).
2. **Turning Super as Sonic.** Give 50 rings (Character page). Standing, press the action button: he crouches or spin
   dashes as usual, with no chat line. Jump and press it in the air: "Hm!" and he turns Super mid-jump without stopping.
   In a later jump press it again: back to Sonic. With 12 rings, in the air: Sonic's own air action and **no chat line**.
   Press G standing: nothing; G in a jump: Super.
3. **Voices.** As normal Sonic, stand still and wait for his idle lines: Sonic's own. As General Super Sonic: Super
   Sonic's (the switch on the page). After turning back: Sonic's again. Try the voice Preview and pick the right "Hm!".
4. **Upgrades.** As Super Sonic (Vs. Perfect Chaos) with the Light Speed Shoes ticked, let the rings run out: normal
   Sonic can charge the Light Speed Dash. The same after turning back from the General form.
5. **The aura.** Stand still as either Super Sonic and watch the glow; try Calm, Dreamcast and Slow. Untick "Aura" for
   the General form. Home in and roll as the General form: the trail and after-images are golden (untick "Golden trail
   and after-images" for Sonic's blue ones).
6. **Water.** Run onto a lake as the General form: he runs on top. Turn back on the water: he falls in and swims.
7. **Carrying.** Pick up a prop and run as any character: the prop stays steady in the hands.
8. **Re-creations.** As Super Sonic (Vs. Perfect Chaos) who turned back at 0 rings, tick an upgrade or walk through a
   teleporter: he stays normal Sonic (no free transformation). As a Super General Gameplay Super Sonic: he stays Super.
9. **The Debug page.** "Notes and tools" is now "Debug".

Report what feels wrong with the session log's time (a note: chat `!note <text>`).

### Spawn-menu pictures (0.9.4d)

1. **Re-made.** Start Garry's Mod with the disc and open the spawn menu: the session log says the old pictures' files were
   deleted and the pictures drawn again; `garrysmod/data/gsa1/icons/` holds only files with the new key.
2. **The colour.** In the G-SA1 tab and Entities > G-SA1, the Ring is the game's bright gold, not pale, and not
   see-through over the menu's background. The Item Boxes look as before, or slightly stronger.
3. **The framing.** The Ring fills its picture in a three-quarter view (not edge-on). The Ring line shows 5 large rings on
   a diagonal. The Ring circle reads as a circle of 7 seen from above. All five pictures exist; none is G-SA1's drawing.
4. **The log.** Each "spawn-menu picture of ... made" line names the coverage (opaque / clear %) and the camera (degrees,
   HU). A "did not pass" line names the coverage it measured.
5. **Redraw.** "Redraw the spawn-menu pictures" (Objects page) draws them again; the ring may show another moment of its
   turn, always about three-quarter.

Report what looks wrong with the session log's time (a note: chat `!note <text>`).
## Design

**Module API** (`require("gsa1")`, API 6; Hammer units and degrees; errors are returned, never raised):

| Function | Returns |
|---|---|
| `Init()` | true, "loading" / true, "already initialised" / false, msg, code (`no_config`, `disc`). Reads the module's config file and starts loading the disc (the playable characters and their world images) on a worker thread (0.5.1) |
| `InitPoll()` | state (`idle` / `loading` / `ready` / `failed`), message, ms, changed: installs the loaded disc (call it once per frame while it loads) |
| `Shutdown()`, `IsReady()`, `Status()` | -, bool, table (module, build (0.6.0: when it was compiled, against which libsa1), disc: disc_state / disc_error / disc_wait_ms, world: world_prepared, map job, retired_jobs, sound output and audio_opening, mesh-call counters: mesh_calls, mesh_errors, mesh_saved (0.6.0: calls left out because the material ignores them), vector_mode) |
| `ChooseDisc()` | Windows file dialog; validates and writes the config file |
| `Characters()`, `CharacterInfo(kind)` | list; radius / height / eyes / center in Hammer units, texture and archive counts |
| `WorldLoad(mapName)` | true, info / false, msg, code (`bad_name`, `not_found`, `bad_map`, `error`). Looks for `<name>.bsp` in `garrysmod/maps`, `download/maps`, `addons/*/maps` below the module's own directory |
| `WorldLoadData(bspBytes, mapName)` | the same for maps inside .gma / workshop / mounted games (kept for tools; the addon uses `MapStartData`) |
| `WorldInfo()` | table of the applied map: triangles, brushes, displacements, one-way solids, thin_walls, thin_wall_max, static props (placed, missing, hulls, triangles), brush models, from_cache, cache_note, build_ms, apply_ms, bytes_fed, prepared, prepare_ms, grid_triangles, grid_objects, grid_undersides, prepare_note, ... / nil |
| `MapStart(mapName [, options])` | true, "file" / false, msg, code (`not_found`: a workshop or mounted map). Starts the background job on a map the module finds itself (a job before is dropped without waiting). options: {static_props, brush_models, cache, prop_min_size, thin_wall_max (0..64 Hammer units, 0 = off), prepare (libsa1's GRID synthesis on the worker, default true)} |
| `MapStartData(mapName, header, size [, options])` | true, "fed": the addon opened the map through Garry's Mod's file system (its first 1036 bytes and its size) and feeds what the job asks for |
| `MapPoll([out])` | out: map, state (`cache` / `reading` / `parsing` / `files` / `building` / `preparing` / `ready` / `failed`), progress, error, ms, fed, bytes_fed, bytes_needed, files_total, files_done, needs = {{ofs, len}, ...} (up to 32 ranges of 1 MB), files = {{path, max}, ...} (up to 64 model files) / nil |
| `MapFeed(ofs, bytes)`, `MapFeedFile(path, bytes or nil)` | true / false, msg (at most 16 MB per call; nil: the model file is missing) |
| `MapApply()`, `MapCancel()` | true, WorldInfo() / false, msg, code (`busy`, `failed`, `not_ready`, `idle`); - |
| `ShapeKnown(key)`, `ShapePhy("m:<model>", phyBytes)`, `ShapeBox("x:<name>", mins, maxs)` | bool; true, triangles, chunks / false, msg; true, triangles / false, msg |
| `MoverUpdate(entIndex, key, pos, ang, solid)`, `MoverForget(entIndex)`, `MoverCommit()` | bool; -; active, parked (once per frame before `Tick`) |
| `MoverStatus()`, `MoverOptions({range, max_active, max_tris, max_parked})` | {entities, solid, unknown_shape, shapes, active, active_tris, parked, candidates, over_budget, adds, removes, moves, parks, unparks, failures, error}; true |
| `Upgrades([kind])` | {kind, name, title, flag (the game's event flag), bit (playerwk.equipment; 0 for Big's lures)} per upgrade (of `kind`) |
| `Create(kind, pos, yawDeg [, upgrades])`, `Destroy(id)` | id / nil, msg (code `bad_upgrade`). upgrades: a table of at most 32 upgrade names of the character (`Upgrades(kind)`) |
| `Tick(id, stickX, stickY, cameraYawDeg, buttons, dt [, rawStick])` | pairs run / nil, msg, code |
| `GetState(id, out)` | out: x y z, px py pz, vx vy vz, yaw, action, frame, ground, surface, mode, smode, step, alpha, pairs, tick_ms, render_ms, view_ms, batches, triangles, equipment (the game's playerwk.equipment), upgrade_bits, upgrades, upgrades_ok, shifted, shifted_count; 0.6.0: render_flags (`SA1_RENDER_*`), drawn_root, draws, sprites, lines, blended, sprite_batches, vertices, mesh_calls, sprite_max (the widest sprite, units), blend_layers / sprite_layers (the screen the blended batches / their sprites covered at the last `PrepareView` with a screen) |
| `Render(id, alpha)` | gen, batchGen, x, y, z, yawDeg, interpolated, alpha, triangles, movedWithRoot. alpha -1: libsa1's accumulator (interpolated); 1: the last pair. x y z yaw: the root of the step the game drew (the camera follows it). movedWithRoot: no draw of the last pair matched the previous pair, so libsa1 drew the last pair moved along with the root (`SA1_RENDER_MOVED_WITH_ROOT`; only reported since 0.6.0) |
| `Batches(id, out)` | count; out[i] = {key, pass (0 opaque / 1 blended), archive, tex, flags (SA1_DRAW_*), all, src, dst, mat, wrap, tris, order, source, prims} |
| `PrepareView(id, eyePos, right, up [, flip, vertexColor, linePixels, lit, fov, width, height])` | true: the batches' vertices for this camera. lit (default true): the materials are lit (`EmitBatch` then leaves `mesh.Normal` out only for unlit batches); fov (CalcView's), width, height: measure the screen the blended batches cover (`GetState` blend_layers) |
| `EmitBatch(id, i)` | vertices / nil, msg: between `mesh.Begin(MATERIAL_TRIANGLES, tris)` and `mesh.End()` |
| `TextureArchives(kind)`, `TextureCount(kind [, archive])` | {name, count} per archive; n |
| `Texture(kind, index [, archive])` | {w, h, fmt, dfmt, alpha, name, runs (10 bytes per run), nruns, canary pixel} |
| `TexturePixel(kind, archive, index, x, y)` | r, g, b, a (for `gsa1_texcheck`) |
| `AudioOpen([japanese])`, `AudioClose()` | true, msg / false, msg: starts opening the sound banks on a worker thread (0.5.1); closing never waits |
| `AudioPoll()` | nil while they open; then once true, msg ("sound banks opened in N ms ...; output: ...") / false, why |
| `AudioSettings(master, sfx, voice, music, voices, jingles, bgm, voices3d)` | true |
| `AudioUpdate(eyePos, forward, up, gameVolume, paused, frameTime)` | sounds playing |
| `AudioStatus()` | {open, opening, opening_ms, open_error, japanese, output, backend, error, paused, active, queued_ms, global_volume, events, seconds, underruns, open_ms, loader_thread, preload_done, tones_decoded, clips_cached, clips_waiting, cache_mb, clip_reads, clip_hits, read_errors, caller_reads, cues_deferred, cues_dropped, max_read_ms} |
| `PollEvents([out])`, `PollLog()` | event tables (type, id, bank, x y z, arg, step, character) and `count` (0.6.0: the caller's table and its event tables are reused; `out[count + 1]` is nil), log lines; a local character's rumble events also go to the controller's motors |
| `PadSettings(t)` | true / false, msg. t: enabled, index (0 automatic, 1-4), dead_left, dead_right, outer, trigger, cam_speed, cam_curve, invert_y, dpad, rumble, rumble_strength, map = {a, b, x, y, lb, rb, lt, rt, start, back, ls, rs} (`gsa1.PAD_ACT_*`); fields left out keep their value, numbers are clamped |
| `PadPoll(dt, paused [, out])` | out: available, enabled, connected, index, input, active (priority), lx ly rx ry, lt rt, raw / pressed (`gsa1.PAD_*` bits), sx sy (the SA1 stick), cx cy (camera stick), buttons (`gsa1.BUTTON_*`), yaw / pitch (degrees to add to the view this frame), reset, rumble, rumble_high |
| `PadRumble(low, high, seconds)`, `PadStatus()` | true / false, msg; {enabled, available, backend (the XInput DLL or why not), connected, index, slots, active, rumble, rumble_low, rumble_high, polls} |
| `CreatePuppet(kind)`, `Pose(id, action, frame, pos, yawDeg)` | the remote-player path (not used by the addon yet) |
| `FEATURES`, `FEATURE_ERRORS` (tables) | the features registered by the module's feature files (`{name = version}`; empty until a feature lands) and why a feature or one of its functions was refused (a name clash: the built-in stays); see "Features". `Status().vector_mode` is decided when the module opens (0 / 1) |

**Security** (sadc `docs/research/critique.md` 5.2; any server's clientside Lua can call the module):
* No function takes a filesystem path. The disc path lives in `%APPDATA%\gsa1\config.txt`, outside the game
  directory, so no server's Lua can read it (it would reveal the user's directories) or redirect it (`file.Write`
  reaches `garrysmod/data` only); it is parsed strictly and checked by libsa1's own rules (`sa1_path_check_host`:
  no UNC, `\\?\`, `\\.\`, `\??\`, alternate data streams or DOS device names) before libsa1 checks it again.
  (The brief suggested `garrysmod/data/gsa1/config.txt`; that directory is writable and readable by every server's
  Lua, which critique.md 5.2 rules out.)
* Maps are found by a bare name (`[A-Za-z0-9_.+-]`, 64 characters, libsa1's bare-file-name rules) in fixed
  directories below the module's own location (`garrysmod/lua/bin/..`), never by a path. G64's path traversal
  (`LoadMapCache` with `..\`) cannot happen.
* Every BSP is untrusted input: all lump offsets, sizes, counts and indices are checked, coordinates must be
  finite and within +-65536, the tree walk is iterative with a visited set; `core_test` fuzzes mutated and
  truncated copies of gm_construct per run.
* Messages handed to Lua never contain the disc's or the config's directory (`<disc>`, `<config>`).
* No Lua error is ever raised from C++ (no `ThrowError`/`ArgError`/`Check*`, every binding wrapped in try/catch),
  caller tables are written with rawset and read with rawget, numbers are checked for finiteness; the calls into
  GMod's `mesh` library are protected calls (`PCall`), so a replaced or failing `mesh.*` cannot unwind through the
  module; `binding_test` aborts if the module calls a raising function or an unprotected `Call`.
* The sound output only uses a BASS library Garry's Mod has already loaded into the process (`GetModuleHandle` /
  `dlopen(RTLD_NOLOAD)`): the module loads no library for it and never writes a file.
* The one library the module loads itself is XInput, on Windows, the first time an enabled controller is polled:
  `xinput1_4.dll`, else `xinput9_1_0.dll`, else `xinput1_3.dll`, each by its full path in the Windows system
  directory (`GetSystemDirectoryW`), never through the DLL search path, so a DLL of that name in the game's or the
  map's directory is never picked up; only `XInputGetState` / `XInputSetState` are used; it is freed when the module
  unloads (motors off first). Nothing is linked (the import list is unchanged). Lua can only pass numbers to the
  controller functions; an empty XInput slot (a slow query) is probed at most once a second, one slot per frame.
* The map job (0.5): the bytes the addon feeds (`MapFeed`: only within the map's size and only while reading, at most
  512 MB per map; `MapFeedFile`: only the model files it asked for, by the name it gave, at most 16 MB each; `ShapePhy`) are
  untrusted like the map itself - every `.phy` offset, count and index is checked (`map_test` parses 3000 damaged
  copies), and a damaged map cannot keep the worker busy (`core_test` fuzzing: every mutated copy within 5 s; a
  displacement with far-out vertices once made the one-way index loop for minutes). The cache file
  (`garrysmod/data/gsa1/cache/<bare map name>.dat`, below the module's own garrysmod directory, never a path from
  Lua) is untrusted too, since any server's Lua can write into `garrysmod/data`: magic, format, settings hash, the
  map's CRC and size, a payload CRC, every count and coordinate are checked before it is used; it holds only geometry
  built from the map. Workers never call Lua. Since 0.5.1 they call libsa1 only on contexts of their own: the map
  job's preparation (`sa1_collision_prepare_tris` on a private context with the default allocator, no log), the disc
  load (the session's context before it is installed) and the sound banks (a private context); the log callback they
  may reach is thread-safe. `MapApply` installs the prepared result on the game's thread.
* Known exposure: the texture runs and texels (decoded RGBA of the character's textures) are handed to Lua to paint
  render targets, so a server's Lua could read them; keeping textures native needs the Source SDK path (later option).

**Units and space.** libsa1's Source preset: 4.0 Hammer units per SA1 unit, `host = 4 * (x, -z, y)` (a proper
rotation), yaw counter-clockwise like a Source yaw. Collision triangles are counter-clockwise from the front;
libsa1 draws counter-clockwise fronts, the module reverses them to Source's clockwise fronts (`gsa1_flip_winding` if
that is wrong in game; `core_test` checks that the body's triangles come out clockwise seen from outside).

**Collision from the map** (`src/core/bsp.*`, `mapjob.*`; see "The map's collision (0.5)" for the stages). Brushes
reachable from model 0's BSP tree (func_detail included, brush entities and triggers not): SOLID / WINDOW / GRATE /
MOVEABLE / PLAYERCLIP contents become land (glass, grates, clips and sky-textured sides are NO_CLIMB), WATER / SLIME
brushes become water surfaces, each brush clipped by its side planes into polygons; static props with a physics model
(`sprp` lump, solid 6: the `.phy`'s convex pieces, placed by origin, angles and scale) or a box (solid 2: the `.mdl`'s
hull box) join them as convex solids. Then, for SA1's sphere collision (sadc `docs/research/gsa1_ramp_freeze.md`):
* faces inside or between solids are cut away (the game copies the polygons near the character into its NEAR-poly
  list, which buried faces filled), and displacement triangles buried in a solid brush are left out;
* **one-way thin platforms**: the underside of a solid whose walkable top lies at most 24 units above it, or with any
  walkable surface that close above it (planks of several brushes, props on brushes), is left out, as are down faces
  at most 32 units above a walkable surface (low ceilings); the few solids that are not one-way and thinner than 12
  units are thickened as in 0.4;
* **thin walls**: two opposite steep faces at most 16 units apart become one double-sided face halfway between them;
* runs of 3 or more steps become ramps flagged as stairs (SA1's own stairs are built that way);
* each face's pieces are merged where their union stays convex and emitted together, as a fan with one surface word,
  so libsa1 can join them back into the face before its own well-shaped cutting.
Displacements are triangulated in Valve's corner order (169 of 169 shared displacement edges of gm_construct meet
within 0.16 units), wound along their base face's plane normal and checked against the map's own walkable tags, and
the brushes carrying them are dropped; a kill plane lies 32 units below the world model. The triangles go to libsa1's
GRID, which partitions them into cells for the game's own land collision - since 0.5.1 on the map job's worker
(`sa1_collision_prepare_tris`, `src/core/prepare.*`; libsa1's default `under_reach` leaves out undersides within 48
units of an upward face), installed by `MapApply` with `sa1_collision_set_prepared`. The solid
brush entities' models are cleaned the same way (cut into pieces of at most 512 units, as libsa1 does not split a
moving object's triangles) and become moving objects. See `BspWorldOptions` in `src/core/bsp.hpp`,
`tests/collision_test.cpp`, `tests/map_test.cpp`; any change of the cleaning bumps `kPipelineVersion` in `mapjob.cpp`,
which rebuilds every cache file.

**Timing.** The addon passes the real frame time (SysTime, times `host_timescale`, 0 while paused, at most 0.25 s);
libsa1 runs whole 1/30 s pairs of 60 Hz steps from its accumulator (at most 8 per call), and draws at the
accumulator's fraction between the last two pairs (one pair of latency, as any fixed-step interpolation).

**Controller.** `src/core/pad.cpp` (`gsa1::Controller`, the code `pad_test` drives through a fake XInput): per frame
the controller in use (automatic: the one with input, kept while it is used; or a fixed slot) is read; the left
stick goes through a radial dead zone that keeps the direction exactly and rescales the stroke from the dead zone's
edge (0) to the outer edge (1), then through the same inverse of the game's own pad dead zone as the keyboard
(below), so the game sees the stroke and direction the stick gives (a deflection just outside the dead zone still
creeps; `pad_test` checks the game's decoded stroke and angle); the right stick gets its own dead zone and a response
curve and becomes view-angle deltas (speed x dt; the addon applies them with `CUserCmd:SetViewAngles` in
CreateMove); buttons and triggers (beyond a threshold) go through the action map. Rumble events: power 1..7 ->
0.25..1 on the low motor (half on the high one), duration = the game's frames / 60 (0.08..2 s), overlapping requests
keep the stronger level and the later end, only while the controller had input within 30 s, stopped by pause,
disabling, switching controllers and unloading.

**Input.** The game's analog conversion (8C05117E) removes a 12-unit dead zone from each pad axis and treats 0 as
positive, so a stick exactly on an axis (every keyboard direction) runs about 6 degrees off (measured: forward,
back, left and right +-6.0, diagonals 0). The module maps host input through the inverse of that dead zone, so the
game decodes the intended direction exactly (measured error 0.00 degrees in all 8 directions); the game code is not
changed. `gsa1_stick_raw 1` passes the stick as a Dreamcast pad would.

**Rendering.** libsa1 captures what the game draws each pair (its display pass) and hands it over as draws in the
game's order (`sa1_character_render`, libsa1 API 0.2 render draft): triangles of the character's renderer and of
effect models, 3D polygons, sprites and line segments, each with its texture (archive and index), the Ninja material
word, the blend factors and the SA1_DRAW_* classification. Every frame the module (`src/core/session.cpp`):
1. renders at libsa1's accumulator fraction (`gsa1_interpolate 1`) or the last pair (`0`) and copies the result
   exactly as libsa1 returns it: libsa1 interpolates each drawn model as a transform, matched draw by draw (the n-th
   draw of a model with the n-th draw of the same model), moves the draws that exist only in the last pair with the
   root - when nothing matched, the whole last pair (`SA1_RENDER_MOVED_WITH_ROOT`) - and places the root at the step
   the game drew (`SA1_RENDER_DRAWN_ROOT`), so the body keeps its place against the chase camera, which follows that
   root (0.4-0.5.1 moved an unmatched frame a second time here: the 0.5.0 "forward and backward" flicker);
2. sorts the draws into batches by render state (texture archive / index / address mode, the material flags, the
   blend factors): opaque batches merge every draw of a state, blended batches keep the game's order (consecutive
   draws of one state merge); the batch structure has a generation number, so the addon re-reads it (and resolves
   materials) only when it changes;
3. for the current camera (`PrepareView`) writes each batch's vertices in Source's winding: triangles as drawn,
   sprites as camera-facing quads (rect, rotation, UVs and colour as the game set them), line segments as
   camera-facing ribbons about 2 pixels wide, sphere-mapped draws with UVs from the view-space normal; palette-lit
   draws keep white vertex RGB and the material alpha (the game lights them from its light palette and ignores the
   material colour), the others their vertex colours (`gsa1_vertexcolor 0`: white for textured draws; untextured ones
   are their vertex colour and keep it);
4. streams a batch into GMod's mesh builder from C (`EmitBatch`: `mesh.Position` / `Normal` / `TexCoord` / `Color`
   / `AdvanceVertex` per vertex as protected calls, two scratch Vectors written in place - no Lua tables, no
   per-vertex garbage; `Normal` only where the material is lit, `TexCoord` only where it is textured or sphere-mapped).

The addon (`cl_render.lua`) draws the opaque batches in `ENT:Draw` and the blended ones in `ENT:DrawTranslucent`
after them, in order, with `render.OverrideBlend` set to the game's factors (PowerVR's OTHER_COLOR is the destination
colour as a source factor, the source colour as a destination factor). Materials (`cl_textures.lua`): VertexLitGeneric
(UnlitGeneric for SA1_DRAW_UNLIT, sprites, lines and with `gsa1_lighting 0`) on the texture's render target
(`IMAGE_FORMAT_BGRA8888`, which keeps the alpha channel; checked by a probe at start, see "What 0.4.0 changes"),
`$vertexcolor`, `$vertexalpha` + `$translucent` (or `$additive`) for blended batches, `$alphatest` 0.5 for 1-bit
alpha, `$nocull` for double-sided draws, `$halflambert` for palette-lit ones (the game's palette wraps the light
around the model); lighting is an ambient cube from `render.ComputeLighting` around the character. Since 0.6.0 a
material is named by what it is (its render target or vgui/white, blend mode, lighting, culling, half-Lambert), so
batches that differ only in their blend factors share one, and `cl_warm.lua` makes and draws once, while a character
appears, every material state it can use, the exact material of every render state of its kind in core_test's
material census (`cl_warm_census.lua`) and every texture of its archives in the usual states (see "Since 0.6.0" and
"What 0.6.0 changes"). Textures:
every texture of every archive of the character is painted into a render target of its size (run-length strings,
`surface.DrawRect` per run with blending off, a few thousand runs per frame, the ones a batch needs first); the
render target's sampler state (clamp U / V, point sampling) comes from the material, so a texture used with two
address modes has two render targets. While interpolating, every batch is a dynamic mesh built every frame; with
`gsa1_interpolate 0` one static IMesh per batch is rebuilt only when a new pair was drawn.

**Sound.** libsa1's audio layer (`libsa1_audio.h`; since 0.5.1 opened and closed on a worker thread of the module,
on a libsa1 context of its own, and installed by `gsa1.AudioPoll` / `AudioUpdate`) opens the disc a second time and
reads the game's sound tables
from `1ST_READ.BIN`, the stage MLT of Emerald Coast (the common sounds) and every character's player and voice banks,
and indexes the voice archive; samples (AICA ADPCM / PCM) and ADX voices and jingles are decoded in memory. Since the
0.5 round every disc read and decode happens on libsa1's own loader thread (a clip that is not read yet starts a few
milliseconds late; the jingles and every tone are preloaded when the sound opens), so no sound event stalls a frame. The module hands every sound event of the game (`SA1_EVENT_SOUND`, `_STOP`, `_VOICE`, `_JINGLE`) to libsa1's
mixer as it polls the events after each tick, tells it where each character is (local: its non-positional sounds
play 2D as in the game) and, every frame (`AudioUpdate`), where the listener is (the chase camera), then mixes
enough 44.1 kHz stereo to keep about two frames (at least 60 ms) queued in a push stream on Garry's Mod's own BASS
(`bass.dll` / `libbass.so`, already loaded by GMod's audio system; playback buffering off, so the queue is the
latency). Garry's Mod's volume applies (the `volume` ConVar, unless GMod already scales BASS's streams itself), the
escape menu and `snd_mute_losefocus` pause it. Options: volumes per kind (0..4), voices, jingles, background music
(off by default: the character's world has no music of its own), other players' voices from their position, English
or Japanese voices (the banks are reopened). Not reproduced (libsa1): LFO, filter and reverb; the per-call volume
offsets of a few game calls.

**Upgrades.** See "What 0.4.0 changes" -> "Upgrades": the module's table (`session.cpp` `kUpgrades`, `gsa1.Upgrades`)
and the addon's (`sh_config.lua` `GSA1.UPGRADES`, the ConVars and the menu) have the same names; the addon compares
them when the module loads.

**Settings.** Every option is a ConVar (archived) and is on the spawn menu's Options tab (`cl_menu.lua`:
`spawnmenu.AddToolMenuOption("Options", "G-SA1", ...)`); the status read-out there refreshes twice a second from
`GSA1.StatusLines()`, the same lines `gsa1_status` prints.

**Player integration** (single player). CreateMove reads and clears the user command; the server keeps the
invisible, noclipped player entity at the character's reported position (20 Hz, validated, rate limited) so PVS,
sounds and other addons see the player there; no fall damage and no noclip toggling while active.

**Multiplayer hook.** Owner-authoritative: the state packet (`sh_net.lua`: position, yaw, kind, action, frame,
ground) already goes to the server, which keeps it in `ply.GSA1State`. Next: relay it to the PVS; other clients
create `gsa1.CreatePuppet(kind)` and call `gsa1.Pose(...)` per packet (each client poses from its own disc;
nothing ripped is ever sent), clients without the module keep the player model. Sound events would be relayed the
same way ({type, id, arg, character, position}) and played by each client's own mixer (`sa1_audio_mixer_event`).

**Lifetime.** `gmod13_close` (map change, disconnect, quit) stops the sound stream, joins every worker thread (the
map jobs, also the ones that were dropped, the disc load, the sound banks' open and close), destroys every character,
the audio object and the libsa1 context; libsa1 releases its process-wide fault handler (Windows VEH / Linux SIGSEGV)
when its last world goes away, so nothing of the module stays registered if GMod unloads the DLL. A disc load or a
libsa1 preparation cannot be interrupted: `gsa1.Shutdown` (the ShutDown hook) waits for a disc load still running (at
most its 0.25 s); a dropped map job finishes its preparation in the background.

## Not done yet

Controllers on Linux (evdev / SDL; Windows only through XInput now), DirectInput-only pads (they need Steam Input
or a wrapper that presents them as XInput), LZMA-compressed lumps (such maps are refused with a message), static
props without a physics model or box in the game's files (counted in the status), ragdolls as moving collision, a
shadow that hugs the drawn ground over steps and edges (the game's blob is drawn since 0.8, flat as in the game),
multiplayer relay and puppets, a native texture path (no RGBA in Lua),
the interaction's leftovers (an interact button on the controller, heavy props for Big, game-style NPC deaths, followers'
targets: "Interaction" above; the round-5 interaction is written and tested offline, not yet in the game),
effects whose game code libsa1 does not run yet, the stage's light palette
(palette-lit draws use the map's lighting), a measured in-game cost of the per-frame mesh streaming, a native mesh path
(no Lua call per vertex: sadc `docs/research/gsa1_lsd_lag.md` E3), in-game figures for `CreateMaterial`, Source's
shader loading and DXVK's pipelines (the session log of the next test will have them: the pre-warm's "warm" lines and
the hitches), the exact materials of render states outside core_test's material census (13 s of scripted play per
character on a flat floor: no climbing, water or EFF_REGULAR particles; all 346 census states are warmed exactly) -
their shader states are pre-warmed, their materials are made at the first use and logged.
The jukebox: the world jukebox (a placeable radio that everyone with G-SA1 and the disc hears in sync; sadc
`docs/research/jukebox.md` 6.6, J3: the owner chose the personal jukebox only for now), going on with the personal
jukebox's track after a map change (the module closes with the map; review G16), and official titles for the 5 tracks
the sound test does not list (they keep their file names).
Collision leftovers measured offline: random play still finds 3 of 400 runs (20 s each) on gm_freespace_13 and 5 of
400 (8 s) on gm_driversheaven_tdm that dip through a floor somewhere - mostly Knuckles landing from a glide 8 units
into the floor, and a curb under a fence (`tests/diag_maps.cpp --replay` reproduces each one). 0.5.1 (libsa1's
round 4b2): gm_freespace_13's random play still finds 3 / 4 / 2 of 400 runs (seeds 1 / 2 / 3) with shallow dips of a
few units on G-SA1 geometry that recover; gm_driversheaven_tdm's down-facing displacement (sadc
`docs/research/gsa1_ramp_freeze.md` 3.6) is not re-measured. `ShapePhy` still cleans a prop's physics model on the
game's thread when the prop first comes near (0.14-0.17 ms for the couch, table, shelf and car of `map_test`; a
model with many convex pieces takes longer; at most two new models per look-around).

## libsa1 API requests

1. A public path check (`sa1_path_check(path, kind)`): G-SA1 calls the internal `sa1_path_check_host` /
   `sa1_path_check_bare` (declared in `src/core/libsa1_internal_api.hpp`), which only works with static linking.
2. ~~The accumulator residual and the start position of the last pair~~: done by the render API
   (`sa1_character_render` with alpha -1). G-SA1 still mirrors the accumulator for `GetState`'s `alpha` / `px py pz`.
3. An `sa1_input` flag for the inverse dead-zone mapping (`exact_stick` in `src/core/session.cpp`), so every host
   gets straight keyboard directions the same way.
4. On Linux, libsa1 restores the SIGSEGV handler it saved when the last world goes away; a handler installed by
   someone else in between would be overwritten. Worth a note or a check.
5. Per-node matrices of the captured draw (for GPU skinning) would let the host stop streaming every vertex every
   frame; the address mode per material is in the render API now.
6. ~~Sound~~: done (`libsa1_audio.h`, mixer included).
7. The stage's light palette as data (colour per N.L), so a host could light palette-lit draws like the game.
8. **Upgrades:** `sa1_character_desc.upgrades` covers event flags 0..127, but every upgrade flag PInitialize reads is
   above 127 (0x8D..0x1D1, Big's lures 0x1DE..0x1E1), so `SA1_CREATE_UPGRADES` cannot give any upgrade. G-SA1 writes
   the flags itself through internal functions (`sa1_character_world`, `sa1g_world_rd32` / `_wr32`; see "Upgrades").
   Wanted: event flags 0..511 at create (e.g. `uint32_t event_flags[16]` behind a new flag, the world boot's loop in
   `sa1_world_boot.c` widened to 512), or better an upgrade-level field (`SA1_CREATE_EQUIPMENT` with SA1_UPGRADE_*
   bits that libsa1 maps to the flags), and `sa1_character_set_equipment` to change a running character's
   playerwk.equipment without re-creating it.
9. ~~Interpolation across topology changes~~: done in the 0.5 round (draws matched one by one, transforms
   interpolated, the others moved with the root).
10. ~~The root and the body are one 60 Hz step apart~~: done in libsa1's round 4c (`SA1_RENDER_DRAWN_ROOT`). Before: the body is captured in a pair's first step, `sa1_render.position`
   (and `sa1_state.position`) is the root after its second, so the drawn body trails the reported root - and a camera
   that follows it - by one step (`core_test`: 15.7 HU at 1030 HU/s, 39.6 HU at 2379 HU/s), and when the speed jumps
   (the spin dash's release) the body jumps against the camera once. Wanted: the root at the capture's step in
   `sa1_render` (e.g. `position` = the capture step's, plus the current state's for physics).

11. ~~The GRID synthesis off the game's thread~~: done (libsa1 `SA1_API_PREPARE`). G-SA1 0.5.1 prepares the world in
   the map job's worker (`sa1_collision_prepare_tris`, `src/core/prepare.*`), installs it with
   `sa1_collision_set_prepared` and loads the disc with `SA1_LOAD_WORLD_IMAGES` on a worker; see "What 0.5.1 changes".
12. ~~Diagnostics~~: done (`sa1_debug_near_polys`); `tests/diag_maps.cpp --trace` / `--replay` print the list the last
   query filled (the raised 256-entry list in GRID worlds) in host space.
13. **Cancellation:** `sa1_load_disc` and `sa1_collision_prepare[_tris]` cannot be interrupted, so a map change during a
   first disc load waits for it (at most about 0.25 s) and a dropped map job keeps a worker busy until its preparation
   ends. A cancel flag (or a callback polled between steps) would let G-SA1 drop both at once.
14. **sa1_audio_open on a worker:** G-SA1 runs it on its own thread with a private context (it calls the context's log
   and `sa1_fail`, so it cannot share the context the game's thread ticks). A note in `libsa1_audio.h` that this is
   the supported way, or an open that never touches the context's error text, would make it official.
15. **Contacts of a fast ball (round 5, pushing props):** `sa1_character_contacts` reports what the character's
   collision sphere touches after the game's step, but the game stops a fast ball short of a wall (a spin dash at about
   2400 units/s stops 37 units before a moving object's face, `tests/feat_interact_test.cpp`), so the impact itself is
   never reported. G-SA1 detects it from the speed collapse and its own trace (`cl_interact.lua` `I.RollImpact`). Wanted:
   a contact type for "the step's movement was cut by this object" (the object the game's sweep found), with the
   velocity before the cut.
16. **The host-object section of `libsa1.h`** is in the header while `SA1_VERSION_MINOR` is still 2 (the release step
   raises it to 3); G-SA1 asks for the functions directly (static linking), so nothing breaks, but a host checking the
   version would not find them.
17. **Super Sonic's whoosh (module, 0.9.3):** the aura's tones 1035 / 1036 need the Perfect Chaos stage bank
   (`sa1_audio_set_stage(audio, 19)`, CHAOS7B.MLT) while the local character is Super. `src/core/audio.*` has no way to
   switch the stage bank yet (an `Audio::set_stage`, then `Session::set_stage_tones(false)` while it is 19); until then
   `Session::take_events` keeps the stage range 1027-1038 of Super worlds out of the mixer. Note: the stage banks are the
   mixer's for every sound, and `sa1_audio_set_stage` reads the MLT on the calling thread.
18. ~~Water floor while Super (libsa1)~~: done in round 0.9.3a (`SA1_SUPER_WATER_WHILE_SUPER`: the floor copy only while
   player 0 is Super and only for water at most `SA1_SUPER_WATER_TOLERANCE` collision radii above him; G-SA1's
   General Gameplay page "Run on water while Super").
19. **The body at a transformation (libsa1):** for the pair in which reqaction is already Super Sonic's (130) but the drawn
   action is still normal Sonic's (or the other way), `sa1_character_render` classes the body draws of the other texlist as
   `SA1_DRAW_EFFECT` (`tests/feat_super_test.cpp --verbose` shows Super Sonic's census states `4 n 0x60` at step 5), so a
   host that hides effects hides the body for that frame.
20. **`SA1_DAMAGE_FACE_SOURCE` and Super Sonic (libsa1):** the game's hit on Super Sonic only halves his speed (no
   knock-back), but the flag still turns him toward the source; G-SA1 passes it with the knock-back options (PvP's is on
   by default). Wanted: no turn while the player is Super.
21. **A warp (libsa1, 0.9.2a):** teleporters re-create the character at the destination, so it arrives standing and
   without the game's item state (barrier, invincibility, speed shoes, a held object). Wanted: `sa1_character_warp(ctx,
   id, position, yaw, velocity, flags)` as the game's own player warps do it (sadc `docs/research/gsa1_091a_teleport.md`
   6.4, T1: the position and the whole position history, the facing, the speed kept / set / cleared, the stood-on objects
   cleared, request 24, the collision window rebuilt at once, the render pairs moved). `feat/cl_teleport.lua` already
   uses a module `gsa1.Warp(id, pos, yaw, vel, flags)` (flag 1 = keep the speed) when there is one. 0.9.3a (sadc
   `super_general_design.md` review R.3.13): the warp must not move Sonic through a request that enters mode 20 (requests
   9, 10, 12-17, 19-23): a General Super Sonic released from mode 20 with request 24 would land in the game's Super modes
   (libsa1 logs and counts it).
22. **The game sound pulled by BASS (module, 0.9.3):** the 0.9.2a feed still mixes on the Lua thread and pushes, so a
   hitch longer than the lead (60-250 ms) still cuts the sound. `gsa1_091a_perf.md` A1 (a `STREAMPROC` stream, the mixer
   under one lock, a heartbeat for pauses; its review RC4-RC7: never free the stream under the mixer's lock) removes the
   drop-outs entirely (0 in every measured frame mix).

## Provenance and licences

* G-SA1's own code (this directory except `third_party/`) contains no SEGA data and no third-party code. Licence: not
  chosen yet (owner's decision, as for libsa1).
* `third_party/gmod-module-base`: Facepunch's module headers, `git clone --depth 1 --branch development`,
  commit `e0156e5f96cd0bad8eed738f0d20e2c9a14b2a0d` (2023-10-27). The task brief named the default branch
  (`master`, commit `4fdafe7d762fe63f0360c67d9e119a129292712e`), but master's `lua_State` has a fixed 69-byte header,
  which puts `luabase` at offset 72 on 64-bit builds instead of 120 (a crash in 64-bit GMod), and lacks
  `LUA_FUNCTION`'s `SetState`; the development branch is the one the research (gmod.md 2.3) recommends. The module
  defines `_M_X64` for clang's MinGW mode (the header keys its Win64 layout on MSVC's macro) and `static_assert`s
  the offset. The repository has **no LICENSE file** (the brief assumed MIT); the headers are only used to compile
  the binding. Check the terms before distributing binaries.
* BASS (un4seen) is not part of G-SA1: the module calls the copy Garry's Mod ships and has already loaded.
* libsa1 is linked statically; see its README for what it contains (decompiled game code, reimplemented SDK,
  no game data).
