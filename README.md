# Primal Instinct — Unity project

Playable C# port of the Godot roguelike deckbuilder. You hatch as a Velociraptor, grow from hatchling to prime, and fight on an isometric board with stamina cards, facing, hunger, and weather.

This repository is the Unity project. Open the folder that contains `Assets`, `Packages`, and `ProjectSettings`.

The original Godot 4.7 project is kept, unchanged, in `reference-source/` (scripts, data, art, tools, and tests). Screenshot captures from that project are not in git; they are generated images, not source.

## Editor

| | |
|---|---|
| Line | **Unity 6.3 LTS** |
| Exact editor | **6000.3.28f1** |
| Pinned in | `ProjectSettings/ProjectVersion.txt` |
| Template | 2D |
| Scripting | C# (Mono backend for players) |
| Render | Built-in, gamma, 2D sprites |
| Paid packages | None |
| Secrets | None |

Support for 6.3 LTS runs through December 2027. 6.0 LTS left active support in October 2026, so this project is pinned to the current supported 6 LTS line.

### Install with Unity Hub

1. Install [Unity Hub](https://unity.com/download).
2. In Hub, **Installs → Install Editor**.
3. Choose **6000.3.28f1** (Unity 6.3 LTS). If Hub shows the line as "Unity 6.3 LTS", pick the patch **6000.3.28f1** specifically so the project version matches.
4. On the modules screen, add the build support you will actually use:
   - **Windows Build Support (Mono)** if you will make a Windows player
   - **Linux Build Support (Mono)** if you will make a Linux player
   - **Mac Build Support (Mono)** if you will make a Mac player
5. You do **not** need Android, iOS, WebGL, or Visual Studio unless you want them. The editor itself includes the 2D tools. No paid modules.
6. **Open → Add project from disk** and select this folder (the one with `Assets` next to `ProjectSettings`). Do not open `reference-source`.
7. The first open downloads the packages in `Packages/manifest.json` (uGUI, the 2D feature set, Unity Test Framework). If Package Manager says `com.unity.feature.2d` 2.0.1 is missing on this patch, remove that one line and use **Window → Package Manager → Unity Registry → 2D** to add the 2D feature set this editor offers. Then let Unity rewrite `packages-lock.json`.
8. If Unity offers to upgrade the project or refresh missing Project Settings, accept it. The editor version pin stays in `ProjectVersion.txt`.

### Play

1. Open `Assets/Scenes/Main.unity` (also the scene in **File → Build Settings**).
2. Press **Play**.
3. Flow: **Main menu → Play → egg → customize → intro (skippable) → stage title → board**.
4. On the board:
   - Click a tile to **turn** (free).
   - **Move** (or `M`) highlights tiles you can afford. Water costs 2 move points. Move mode turns itself off when you are out of moves.
   - Click a card (or `1`–`9`), then click a highlighted enemy or tile. Esc cancels.
   - **End turn** or Space / E.
   - While unseen you can strike an enemy for a free ambush, or walk out an open corridor to sneak past.
   - After a clear, eat or skip each body, then take card, item, and growth choices.
   - Exits are corridors **outside** the tile grid, not gate sprites. Door 0 leaves up-screen.
5. The game window is a 640×360 canvas, integer-scaled with bars when **Pixel Perfect** is on (the default). Sprites use point filtering.

### Build a player

**File → Build Settings → Main → Build**. Use the Mono backend. The data files are in `Assets/StreamingAssets/data` and are copied next to the player. Do not strip StreamingAssets.

## What you can edit

| Want to change | Where |
|---|---|
| Cards, enemies, items, stages, weather, nutrition, puzzles, events, hints, difficulty | `Assets/StreamingAssets/data/*.json` (same files as the Godot `data/` folder). Restart Play after saving. |
| Art | `Assets/Resources/Sprites/`. Replace a PNG with the **same file name**. Unity reimports it. Filtering is point, 1 pixel per unit. |
| Quick art override without touching the imported file | Drop `name.png` into `Assets/StreamingAssets/sprite_overrides/`. Play loads it instead. |
| Fonts | `Assets/Resources/Fonts/`. Jersey 10/15/20/25, SIL Open Font License (`OFL.txt`). Body text is at least 15 px on the 640×360 canvas. |
| Buttons | Prefab `Assets/Resources/Prefabs/UiButton.prefab`. The game instantiates it for every button. |
| Starting scene | `Assets/Scenes/Main.unity`. The **Main** object runs `GameHost`. The camera is orthographic, size 180. |
| Rules (combat, hunger, drafts, stages) | `Assets/Scripts/Rules/` — plain C#, no `UnityEngine`. |
| Screens, board drawing, input | `Assets/Scripts/Game/GameHost.cs`, `IsoMath.cs`, `SpriteBank.cs`, `LookPaint.cs`. |
| Credits | Menu footer and this file. Pine sheet art is **@kianamosser** (`tree_pine_*`, `stump_pine_*`, `fallen_pine_*`). |

Customization (skin, pattern, pattern colour, cosmetic gender) is data in `customization.json` and recolours the raptor at runtime in `LookPaint`. Classic + Solid + Male leaves the original pixels alone. Gender does not change stats.

There are no human characters and no human bones. Backdrop skeletons are animal fossils.

## Architecture

```
Assets/StreamingAssets/data   JSON content
Assets/Scripts/Rules          C# rules (Db, grid, battle, run, stages, nutrition)
Assets/Scripts/Game           Unity presentation (canvas, isometric board, sprites)
Assets/Tests/EditMode         NUnit tests the Unity Test Runner can execute
tools/RulesTests              Same tests, runnable with dotnet without the editor
reference-source              Original Godot project
```

`RunDirector` is the screen flow (menu is outside it; egg onward goes through it). `Battle` is the fight: turn meter, cards, facing, vision cones, idle / spotted / searching AI, ambush, exits, secret cave. `GameHost` draws that state. It does not reimplement the rules.

The logical grid is square. The board is drawn as 2:1 diamonds (`IsoMath`, 32×16 at zoom 1). Zoom steps come from `arenas.json`. You cannot zoom out past the step that still fits the encounter plus the margin in that file.

## Tests

Without Unity, from this folder:

```bash
bash tools/run_rules_tests.sh
```

That needs the .NET 8 SDK. It compiles `Assets/Scripts/Rules` and `Assets/Tests/EditMode` and runs them.

Inside Unity, after packages import: **Window → General → Test Runner → EditMode → Run All**. The test assembly is `PrimalInstinct.Tests`.

This environment does **not** have the Unity editor installed. Results below are from `dotnet test` only. They are not a Unity import, script compile inside the editor, or PlayMode run.

Last run here: **15 passed, 0 failed** (`tools/RulesTests`, net8.0).

Covered: data load, seeded RNG stability, facing front/side/back, water cost 2 (aquatic 1), line of sight, deterministic stages with elite and boss, hunger and starvation, Pounce refusing melee, the turn meter, eating and diet bonus never going negative, the stone puzzle, exit corridors outside the grid with door 0 up-screen, tall-grass evasion on single-target hits only, a bot fight, and three short seeded runs through the director.

The original Godot suite (`reference-source/tests/run_tests.gd`, gallery, text audit, screenshot tour) was **not** executed. Those tests need Godot.

## Parity

The rules layer is a direct port of the Godot combat and run scripts (`Battle.gd`, `BGrid.gd`, `RunState.gd`, `StageGen.gd`, `ExitGen.gd`, and the related files), driven by the same JSON. A seeded run inside this project is deterministic. The random generator is Godot 4's PCG32, so the streams that the port uses are meant to match Godot for the same seed. Treat a mismatch as a bug in the port, not as a new design.

| Area | In this Unity project |
|---|---|
| Menu, egg (one playable species, three locked), seed, difficulty | Yes |
| Skin / pattern / pattern colour / cosmetic gender | Yes, runtime recolour |
| Intro cutscene | Captions and a key image per shot from `cutscene_intro.json`, skippable. Not the full keyframed multi-layer compositor |
| Stage intro with weather | Yes, shorter than the Godot camera tilt |
| Isometric board, varied arena size and shape, themes | Yes |
| Stamina cards, speed turn meter, move points, water cost 2 | Yes |
| Free facing, front/side/back damage, vision cones | Yes |
| Idle roam, search last-seen, spotted hunt, intent label | Yes |
| Ambush first strike, sneak out while unseen | Yes |
| Exit corridors outside the grid, reward type on the door, secret cave | Yes |
| Tall grass 25% evasion, single-target only | Yes |
| Hunger per room, eat or skip with a fit preview, diet XP bonus, evolution branches | Yes |
| Items (drop or a choice), card drafts, events, forage, singing-stones puzzle | Yes |
| Infection, poison, web, bleed, windups | Yes |
| Weather for the whole stage | Yes, icon and text. No full-screen rain or lightning layer |
| Pixel-perfect 640×360, integer scale, bars, point filtering, 15 px body text | Yes. Pixel Perfect defaults on |
| HUD: player top-right, turn order top-left, actions bottom-right, cards bottom-center, portrait with no blue panel | Yes |
| Border plants fade when they cover a unit | Simplified: nearby border sprites drop to the alpha in `visibility.json` |
| Zoom limited to the encounter plus a margin | Yes |
| Designer PNG replace / override, pine credit | Yes |
| Settings: pixel perfect, fullscreen, intro always / first / off | Yes |
| Main-menu forest (parallax layers, falling leaves, mouse drift) | No. The menu uses the jungle backdrop |
| Battle hop, lunge, projectile, and screen-shake animation | No. The board updates to the new tile. The log and intent text still update |
| Deck overlay piles with the full Godot card frame | A count list of the deck, not the animated pile viewer |
| Hint queue for every hint id | The first unseen of welcome / ambush / exits. The rest of `hints.json` is loaded and can be wired the same way |
| Audio and volume playback | No clips were in the Godot tree. The settings screen says so. Nothing is played |
| Mid-run save | Same as Godot: there is no continue. Last seed, difficulty, and intro preference are stored |
| Godot screenshot / text-audit / web-export suite | Not ported |
| WebGL player | Not set up |

This is a full rules-and-flow migration with a real scene, not a Godot player embedded in Unity, and not a one-room demo. It is not a claim that every Godot pixel and tween matches.

## License notes

- Jersey fonts: SIL Open Font License, `Assets/Resources/Fonts/OFL.txt`.
- Pine sheet sprites: credit **@kianamosser**.
- Game code and data in this repository are the project source for Primal Instinct. Do not add paid Asset Store packages.
