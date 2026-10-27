# G-SA1

**Sonic Adventure's characters in Garry's Mod.** Sonic, Tails, Knuckles, Amy, E-102 Gamma, Big and Super Sonic play in
any Garry's Mod map with their own moves, physics, animations, effects and sounds. The game's original character code
runs, not a remake of it.

G-SA1 is to Sonic Adventure what [G64](https://github.com/ckosmic/g64) is to Super Mario 64. It is a Garry's Mod client
module (`gmcl_gsa1_win64.dll`) plus a Lua addon, built on **libsa1**. libsa1 is a library made from the
[Sonic Adventure (Dreamcast) decompilation](https://github.com/ExtCan/LibSA1): the game's own decompiled engine, physics
and character code, packaged so that a host program can run it. Its sources are in the
[LibSA1](https://github.com/ExtCan/LibSA1) repository.

Version: **0.9.4d** (in development; single player is the main target).

## You need

* **Your own Sonic Adventure disc image.** It must be the Dreamcast release, **US version 1.005** (MK-51000), dumped as a
  `.gdi` with its track files. G-SA1 checks it: `1ST_READ.BIN` must have the SHA-1
  `e74c849806db103aa87f84e41a382873bc96b6df`. G-SA1 and libsa1 contain **no SEGA data**. The models, textures,
  animations, sounds and music are read from your disc image while you play.
* **Garry's Mod, 64-bit.** On Steam, Garry's Mod > Properties > Betas > `x86-64 - Chromium + 64-bit binaries`. To check,
  `lua_run_cl print(jit.arch)` must print `x64`.
* Windows 10 or 11. A Linux 64-bit module (`gmcl_gsa1_linux64.dll`) is built too, but it has not been tested in the game.

## Features

* **Seven playable characters**: Sonic, Tails, Knuckles, Amy, E-102 Gamma and Big, plus Super Sonic in two forms. One is
  the Vs. Perfect Chaos form. The other is "General Gameplay": Sonic turns Super with 50 rings and a button press in the
  air.
* **The game's own gameplay**: moves, physics, the upgrades (each one switchable), Knuckles digging into suitable ground,
  Big's fishing, E-102's lock-on and laser, Tails flying, Amy's bird.
* **Drawn like the game**: the game's textures, materials, effects and blob shadows. Animations are interpolated to any
  frame rate. Characters have event faces, lip sync and an **emote wheel** (hold TAB) with every animation of each character.
* **Collision from the current map**: world brushes, displacements, static props, doors, lifts, trains and physics props.
  The collision is built in the background and cached per map, and it works on Workshop maps.
* **Sound**: the game's sound effects, voices and jingles (English or Japanese voices), played through Garry's Mod's own
  audio. The **jukebox** plays the game's music from your disc.
* **Interaction**: attack NPCs, players, vehicles and props, with a separate switch for each kind. Getting hit scatters
  your rings. You can push, lift and carry props, pop balloons, and use doors and buttons with the interact key.
* **The game's HUD** (rings, lives, time, and each character's own display), sized for wide screens.
* **Spawnable rings and item boxes**: the G-SA1 tab at the top of the spawn menu (also Entities > G-SA1). You can place
  single rings, ring lines, ring circles, item boxes and air item boxes, and they are collected and broken by the game's
  own code.
* **Controllers**: keyboard and mouse, or an Xbox-style controller through XInput, with rumble.
* A **session log** (`garrysmod/data/gsa1/log.txt`) for bug reports, with a key for adding your own notes.

**All options are in the spawn menu: Q > Options > G-SA1.** Each part has its own page: Character, Camera, Controller,
Rendering, Sound, Collision, Disc and status, Interaction, Objects, HUD, Super Sonic, Emote wheel, Faces, Surfaces,
Jukebox and Debug.

## Install a release

1. Close Garry's Mod.
2. Download the latest release from this repository's **Releases** page and unpack it (if none is published yet, build from
   source as described below).
3. Copy `gmcl_gsa1_win64.dll` into `<GarrysMod>\garrysmod\lua\bin\`. Create the `bin` folder if there is none.
4. Copy the `addon` folder to `<GarrysMod>\garrysmod\addons\gsa1`, replacing any older copy.
   The module and the addon must come from the same release.
5. Start a single-player game and open Q > Options > G-SA1 > **Disc and status**. Press **Choose disc** and pick your
   `.gdi`. (Run Garry's Mod windowed or borderless for the file dialog.) This writes `%APPDATA%\gsa1\config.txt`. You
   can also create that file yourself with one line:

   ```
   disc = D:\Games\Sonic Adventure (USA)\Sonic Adventure.gdi
   ```
6. Q > Options > G-SA1 > **Character**: pick a character and press Spawn. You can also use the console:
   `gsa1_spawn sonic` (or `tails`, `knuckles`, `amy`, `gamma`, `big`). Use `gsa1_toggle` to switch between your
   character and your normal player (bind it to a key: `bind g gsa1_toggle`).

To uninstall, delete `lua\bin\gmcl_gsa1_win64.dll`, the `addons\gsa1` folder and `%APPDATA%\gsa1`.

### Controls

| Input | In Sonic Adventure |
|---|---|
| Movement keys | analog stick, relative to the camera |
| Jump | A (jump) |
| Crouch, attack 1 / 2 | B (action: spin dash, punch, ...; pick up and throw) |
| Use (E) | interact with doors, buttons and vehicles; lift props |
| Reload | Y |
| Walk | half stick |
| Mouse wheel | camera distance (0 = first person) |
| TAB (hold) | emote wheel |

To change the controller buttons, go to Q > Options > G-SA1 > Controller.

## Build from source

You need Windows, Python 3.12 with `pip install ziglang==0.16.0` (the compiler: zig's clang), and libsa1 built from
[LibSA1](https://github.com/ExtCan/LibSA1). Building libsa1 also needs your disc, because the decompilation's build
inputs are generated from it. LibSA1's README explains the steps.

```
git clone --recurse-submodules https://github.com/ExtCan/G-SA1.git
git clone https://github.com/ExtCan/LibSA1.git
# build libsa1 first: see LibSA1/README.md
cd G-SA1
py -3.12 build.py                                   # the module for x86_64-windows and x86_64-linux
py -3.12 build.py --test --gdi "<your .gdi>"        # + the offline tests (C++ and Lua)
py -3.12 tools/lua_check.py                         # syntax-check the addon
```

* G-SA1 looks for libsa1 at `--libsa1 DIR` first. Next it tries the `LIBSA1_ROOT` environment variable, then
  `../libsa1`, then `../LibSA1/libsa1` (LibSA1 cloned next to G-SA1, as above).
* The tests read some of Garry's Mod's files, read-only: `maps/gm_construct.bsp`, the VPKs, and `bin/win64/lua_shared.dll`
  for the Lua tests. G-SA1 finds Garry's Mod through Steam's library list. To point it elsewhere, use `--gmod
  <GarrysMod>\garrysmod` or the `GARRYSMOD_DIR` environment variable. `GMOD_LUA_SHARED` names the Lua DLL directly.
  The disc comes from `--gdi` or `SA1_TEST_GDI`. Tests that need the disc or a map are skipped when it is missing.
* `third_party/gmod-module-base` is Facepunch's module header repository, included as a git submodule. If you cloned
  without submodules, run `git submodule update --init`.
* The outputs go to `build/<target>/`: `gmcl_gsa1_win64.dll` / `gmcl_gsa1_linux64.dll` and the test programs.

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) is the full development diary. It has what each version changed, the
design, every setting and console command, the in-game test checklists and the open issues.

## Credits

* **ExtCan**, the project's owner, directed the work, tested it and made its design decisions. **Claude** (Anthropic)
  co-wrote it.
* The [Sonic Adventure (Dreamcast) decompilation and libsa1](https://github.com/ExtCan/LibSA1), which G-SA1 is built on.
* [G64](https://github.com/ckosmic/g64) by ckosmic and [libsm64](https://github.com/libsm64/libsm64) set the model:
  a game's own character code in a library, with Garry's Mod as the host. G-SA1 contains none of their code.
* Facepunch's [gmod-module-base](https://github.com/Facepunch/gmod-module-base) (module headers; a submodule).
* Garry's Mod's own copy of BASS (un4seen) plays the sound. It is not part of G-SA1.

Sonic Adventure, Sonic the Hedgehog and the characters are trademarks of SEGA. This is a fan project. SEGA and Facepunch
are not affiliated with it and do not endorse it. No game data is included. Use your own legally obtained copy of the
game.

## License

G-SA1's own code is licensed under the GNU General Public License version 3 ([LICENSE](LICENSE)). Third-party code
keeps its own terms. See [NOTICE](NOTICE).

> Code comments sometimes cite the project's internal research notes (for example `sadc docs/research/...`); not all of
> them are published. The development history is in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
