# Primal Instinct (working title) — dinosaur roguelike deckbuilder prototype

Godot **4.7.2** · GDScript (typed) · GL Compatibility renderer · **640×360 native pixel canvas** (viewport stretch, integer scale + bars, nearest filtering; see Display scaling) · **isometric 2:1 battle camera**.
You hatch as a **Velociraptor** and grow BABY → JUVENILE → ADULT → PRIME over a run. Combat is a
turn-based tactics grid with Slay-the-Spire style cards. Strike unseen, bleed prey, hide in tall
grass, and don't starve.

## Main menu (first screen on launch)
Flow: **main menu** -> egg selection -> customize -> intro cutscene -> stage intro -> board. `scripts/ui/screens/MenuScreen.gd`:
* The title (**`Game.title()`** from `data/game.json`, drawn big in the pixel font with a stepped shadow, outline and a lighter top band) plus the tagline, over the forest scene below.
* Stone-wood buttons (the same sprite as every button): **Play** (-> egg selection), **Settings** (opens the settings overlay: Pixel Perfect, fullscreen, volume, intro cutscene toggle) and **Quit** (hidden on the Web build, `MenuScreen.quit_available`). There is **no Continue** button: the game has no mid-run save, so nothing can be resumed.
* **Forest background** (`scripts/ui/MenuForest.gd`, data in **`data/menu_scene.json`**): built only from the supplied jungle art, as depth layers (back to front): the dense canopy backdrop (`bg_jungle_0`, mirrored at its edges), a **dense far tree line**, a mid tree line and mid bushes that **frame the sides** (the centre stays open behind the title), the **iso grass floor** (`tile_jungle_ground_*`, hazed toward the horizon), rocks / logs / stumps, big **foliage framing the sides** (bushes, a tree) and ferns along the bottom. A dark edge **vignette**, a soft darkening behind the title and a translucent panel behind the buttons keep everything readable.
* **Motion**: **slow falling leaves** (14 of them, a few sizes, 12-26 px/s fall, a gentle sideways sway and a slow drift, mostly green with the occasional golden one, drawn procedurally from tiny 2-tone bitmaps with a dark outline), **parallax** (a very slow automatic drift plus a slight mouse parallax; far layers move less than near ones, whole pixels only) and a slight sway on the bushes and ferns. Calm, no flashing.
* **Any window size**: the layout is generated per slot from hashes (not a stretched picture), so the scenery simply continues on wide / tall windows (1280x720 .. 4K and ultrawide); everything is drawn at whole-number scales (canopy 1x, trees / bushes / floor 2x-4x, leaves 3x-5x) with nearest filtering; front foliage is anchored to the real bottom edge.
* **Designer art** (all optional, `assets/sprites/`): `menu_bg_back.png` (the backdrop, tiled / mirrored), `menu_bg_floor.png` (one 32x16 iso floor tile, replaces the tile pool), and `menu_bg_<category>_<n>.png` with n = 1..12 for the categories `tree`, `bush`, `fern`, `rock`, `log` (if any exist they replace that whole category) and `menu_bg_leaf_<n>.png` (replaces the procedural leaves, drawn untinted). Layers, spacing, parallax, tints and leaf settings are in `data/menu_scene.json`.
* **Keyboard**: Up/Down (or W/S) select, Enter/Space activate, **Esc opens Settings** (Esc again closes it; menu keys are ignored while it is open). Mouse hover selects, click activates.
* A **version label** (`data/game.json` `version`, synced to `config/version` in `project.godot` by `tools/apply_title.py`) sits in the real bottom-right corner at every window size. The menu is laid out on the 640x360 canvas like every screen (1280x720 = 2x ... 4K = 6x).
* The egg screen has a **Main menu** button (top-left); the **run-end screen** (death / victory) has **Return to the egg** (unchanged behaviour) and **Main menu**.
* **Bypass**: `Game.bypass_menu = true` (set by the headless tests; the bot sim never uses screens) makes `Game.first_screen_name()` return `egg`.
* Tests (`test_main_menu`): menu is the first screen, title / tagline / version from the central entry, buttons present and on screen, stone-wood style, Quit hidden on web, no Continue, keyboard + hover navigation, Settings overlay (Pixel Perfect + intro toggle), Esc, Play -> egg, Main menu buttons, the full flow menu -> egg -> customize -> cutscene -> stage intro, run-end buttons. Forest scene: every sprite exists, depth layers + whole-number scales, slot layout fills the 640x360 canvas and is deterministic, centre open behind the buttons, vignette / panel, leaf density / speed / sway / golden mix, parallax, override names documented, draws at the 640x360 canvas. Gallery: `--cases=menu --sizes=1280x720,3840x2160`. Tour shots: `main_menu_1280x720`, `main_menu_3840x2160` (native pixels), `main_menu_settings_selected`, `main_menu_settings_open`.

## Game name (placeholder)
The name **Primal Instinct** is a placeholder. It lives in one place, **`data/game.json`** (`title`, `tagline`, `slug` = exe name, `zip_slug`); the first screen (`EggScreen`), the window title (`Main`) and `Game.title()` read it at runtime. `project.godot` (project / window name), `export_presets.cfg` (preset names, `PrimalInstinct.x86_64` / `PrimalInstinct.exe`, product name) and this README are synced from it by **`python3 tools/apply_title.py`**: edit `data/game.json`, run the script, re-export. Release zips: `PrimalInstinct-windows.zip`, `primal-instinct-linux-x86_64.zip`. Export presets: `<title> - Linux`, `<title> - Web`, `<title> - Windows` (e.g. `godot --headless --export-release "Primal Instinct - Windows" builds/windows/PrimalInstinct.exe`). Note: Godot derives the per-user data folder (settings / save) from the project name, so renaming starts with fresh settings and saves.

## Run it

| How | Command |
|---|---|
| Editor | `godot --path . ` (or open `project.godot`) |
| Linux build | `unzip primal-instinct-linux-x86_64.zip && ./PrimalInstinct.x86_64` |
| Web build | serve the `web/` folder (`python3 -m http.server`) and open `index.html` (no threads variant, works on any static host, itch.io etc.) |
| Tests | `tools/run_tests.sh` (headless, ~50 s incl. the archetype bot runs) |
| Balance sim | `godot --headless --script res://tests/sim.gd -- seeds=100 smart=1 eat=fit archetype=bleed difficulty=hard` (win rate, deaths, forms; `smart=0` = naive bot) |
| Compile check | `tools/check.sh` |
| UI screenshot tour | `tools/run_tour.sh` (needs `xvfb-run`; writes `screenshots/`) |
| Exported-build selftest | `./PrimalInstinct.x86_64 --headless -- --selftest` (bot plays 25 full runs from the exported pack) |

Godot 4.7.2 binary + export templates come from the `4.7.2-stable` GitHub release.

**Controls (mouse-first):**
* **Click a tile (normal mode)** → your dino only **turns to face** that tile. Turning is **free** and unlimited.
* **Move button / `M`** → enters *move mode* (reachable tiles light up); click a highlighted tile to walk there
  (limited by Move Points, shown as "Moves Left x/y"). Click the button/`M`/`Esc`/right-click to leave move mode.
* **Card**: click it (or `1`-`9`), then click a highlighted enemy/tile. Right-click / `Esc` cancels.
* **Move mode leaves by itself** once you have 0 Moves Left or there is no tile you can still afford (a "Out of moves" popup shows);
  you can also leave it manually at any time.
* **Hover a hand card** → a big copy (text 20 px, 2x art) pops up above it; unplayable cards say why ("Can't play: enemy adjacent").
* `Space`/`E` end turn. Hover enemies for stats, facing, damage preview (FRONT/SIDE/BACK ×n) and sight range.
  `Deck` shows the piles.

## Game summary

* **Egg screen** – choose a species. Only the Velociraptor is playable; three locked eggs are placeholders
  (add a species by dropping an entry into `data/species.json`).
* **Run** – one *stage* = a floor of rooms (`data/stages.json`). Prototype ships stage 1 (jungle tutorial,
  7 steps, "Hatchling Hollow") and stage 2 (tundra, 6 steps, "The Frozen Verge"). There is **no map screen**: after a room
  you stay on its battlefield and choose the next room by walking to / clicking one of its **exit gates** (see *Exits*).
  Types: battle, puzzle, event, forage, elite, boss, plus the rare secret cave. The floor guarantees an elite, a
  puzzle, an event and a forage room, a forced tutorial opener, and a boss at the end.
* **Growth** – XP → levels 1-7 (`data/growth.json`); forms at level 1/3/5/7. Evolving changes stats +
  sprite and opens a draft of stronger cards. HP/hunger cost/stamina/speed scale per form.
* **Death** returns to the egg screen; the run (deck, level, hunger, seed) is discarded.
* **Win** – kill the stage-2 boss (infected mammoth). Stage 1 boss is a spore-queen husk (the first
  taste of the alien infection).

### Combat
* **Isometric** 12×7 tile grid (2:1 diamonds, 76×38 px; see *Isometric camera*). Tiles (`data/tiles.json`): **ground**, **tall grass** (cover; halves enemy
  sight, lets you hide), **water** (move cost 2, slightly more visible, washes off spores), **obstacle**
  (blocks movement and line of sight). Layout is generated per room from the seed with a theme (jungle / tundra).
* **Cards cost STAMINA**, fully refilled every turn. Hand of 5 drawn from your deck; discard reshuffles into draw.
* **Speed / turn order** – a turn-meter: each unit's meter fills by `speed × weather × hunger factor`
  and acts at 100. Very fast units get several turns in a row; the turn-order bar previews the next
  actions. "Extra turn" cards inject meter.
* **Movement** is part of combat (design choice): each turn you get free **Move Points** (MP, base from species,
  water costs 2, obstacles block). Some cards add MP, dash or retreat. Movement is free of stamina so cards remain
  the "resource" decision while positioning (grass, flanking, hit-and-run) stays tactical.
* **Status** – bleed (damage = stacks at turn start, then -1), weak, expose (+damage taken), stun, spores.

### Facing (new)
Every unit faces one of **4 directions on the grid axes** (SE `(1,0)`, SW `(0,1)`, NW `(-1,0)`, NE `(0,-1)`; on screen these are the
four diagonals). An attacker is **FRONT** if it is within 45° of the target's facing, **BACK** if within 45° of the opposite,
otherwise **SIDE** (exact diagonals count as side). Rules (all numbers in `data/facing.json`, `cards.json`, `enemies.json`, `species.json`):
* **Damage**: global defaults front ×1.0 / side ×1.25 / back ×1.5. A card's damage effect may override with `"facing": {front,side,back}`
  (*Backstab*: back ×3; *Hamstring*: back ×2 + 4 extra bleed + Weaken). An enemy def may carry `"facing": {front,side,back,turn,vision}`
  trait multipliers (armoured *beetle* front ×0.6 / rear ×1.6, *glyptodon* front ×0.5 + slow turner, *husk queen* soft rear + slow turner, …).
  Attacks on **you** use the species table (raptor: ×1/×1.15/×1.3).
* **Turning is free for you** (no stamina/MP). Walking faces your direction of travel; attacking turns you to the target.
  **Facing persists between turns** – you and the enemies keep facing until someone turns or moves.
* **Slow turners** (`"turn": "slow"`) may rotate only one quarter-turn per turn.
* **Vision cones**: enemies see you at full range in front (×1.0), ×0.6 to the sides and **not at all from behind** (even adjacent);
  insect eyes / noses override this per enemy (`vision`). So you can sneak up behind an enemy that looks away.
* **AI**: enemies turn to face you when they spot you or attack; melee enemies prefer attack tiles on your **side/back** (flanking, tuned by `_approach_key`). Your ambush/pounce landing tile prefers the target's back, then side.
* **UI**: a small arrow on each tile shows where a unit looks; hovering an enemy or targeting a card shows `FRONT/SIDE/BACK ×n`
  (computed from where you would actually strike from, incl. pounce landing tiles). Sprites are directional (front/back variants, mirrored for SW/NW).
* A first-time hint ("Facing") explains it.

### Enemy awareness & search AI
Each enemy is in one of three states (`BUnit.state`; `aware` is simply `state == "spotted"`):
* **idle** – *roams*: every turn it either pauses, glances around (turns), or walks up to 2 movement points toward a random waypoint within
  3 tiles of its *home* (never into water/obstacles). After a search it walks back to its post. Idle enemies show a dim eye icon.
* **spotted** – hunts you. It keeps tracking only while `tracks_player()`: distance ≤ `perception × weather × cover × 1.5` **and** line of sight
  (adjacent always; `scent` enemies keep you within 8 tiles regardless of cover). Tall grass, fog/rain etc. therefore shorten how far you can be followed.
  Every time it can follow you it records `last_seen` (your tile).
* **searching** – entered when a hunter loses you (out of range/cover/LOS, or you hide with Crouch/Grass Dive). A yellow bobbing **?** is shown and
  the last seen tile is marked. On each turn it (1) *goes*: walks the cheapest path toward `last_seen` within its movement allowance, (2) on arrival
  *scans*: turns a quarter-turn per turn (alternating direction) for `SEARCH_SCAN_TURNS` = 2 turns, checking its **facing / vision cone** (plus weather and
  cover) after every step and turn, and (3) gives up → **idle** again ("Hm.") if it did not find you. If it finds you it becomes spotted
  again, **without alerting anyone else** (searchers act alone; only idle→spotted raises the alarm to enemies within 3 tiles). Searching enemies count as
  *unaware* for ambush/"unspotted" bonuses and `is_hidden()`.
* Tunables are constants at the top of `Battle.gd` (`SEARCH_SCAN_TURNS`, `TRACK_MULT`, `SCENT_RANGE`, `ROAM_RADIUS`, `ROAM_STEP`).

### Arriving in an area: unseen vs spotted (no encounter screen)
Choosing an exit goes straight to the new area. Enemies that have **not** spotted you stay idle (phase `ambush`): use **Move** to walk up to them and click an enemy for the **ambush strike** (free first hit),
or walk onto an exit tile while still unseen to **sneak out** (no fight, no rewards, as before: the sneak-past outcome). Being spotted while moving ends the ambush phase and combat proceeds normally.
Enemies that already **have** spotted you on arrival show a red **"!"** above them that fades after ~3.5 s and combat starts as spotted; the same "!" appears when an enemy spots you mid-fight (`spot` event, `BUnit.vis_alert`).
The bot sim (`tests/sim.gd`, `RunSimulator`) never used screens and keeps its roll-based ambush/sneak model.

### Stealth (raptor identity)
* Each room's data says whether you start **unspotted** (`unspotted_chance` per stage, forced for the tutorial opener) – traps and
  bosses always start spotted. Each enemy is *unaware* or *aware*; you are "hidden" while no enemy is aware.
* **Detection** each time you act/move: enemy `perception × weather multiplier × tile modifier` (grass 0.5,
  water 1.25, min range 1) with line of sight. Adjacent always spots you.
* **Ambush phase**: if you start unspotted you may take a **free first strike** with any ambush card on any
  enemy (pounce leap), or choose to skip and sneak. Damage vs unaware targets is doubled
  (base `4 + 2·(tier-1)`, then ×2). Killing an unaware enemy is **silent**; any other hit makes noise
  (radius 3) and alerts neighbours.
* **Hide** cards in tall grass make enemies ≥2 tiles away lose track of you. Hit-and-run cards strike then retreat.

### Hunger
Meter 0-100 on the HUD. Each room costs 6/8/10/12 hunger by form (+ weather extra). Refill by **devouring**
defeated enemies (infected flesh gives spores!), **foraging** rooms and events. Below the `low_threshold` in `data/growth.json`: -1 stamina and
slower speed; at 0: HP damage on every room.

### Weather
Rolled **once per stage** (from the seed), hidden until the stage intro, persists for every room. Data in
`data/weather.json`: `global` modifiers (perception, speed, stamina, hunger…) plus `by_tag` modifiers that
apply to species/enemy tags (e.g. fog shrinks sight but scent hunters ignore it, rain slows flyers/insects, cold slows reptiles and insects but suits ice-age beasts, heat boosts reptiles and drains hunger faster). The HUD shows the icon, hover for details.

### Infection (late villain faction)
Asteroid spores infect creatures: infected enemies get ×1.3 HP, +2 damage, a new "Spore Lash" ability and a
purple/glowing sprite variant. Infection **spreads** every 3 turns to a nearby non-immune enemy. Spores on
the player do 1 damage/turn (decaying) and are cleansed by standing in water. Elites/bosses on later floors
can be infected (`infected_chance` per enemy); stage-1's spore drones/husk queen introduce it.

### Enemies (`data/enemies.json`, tiered pools per stage; spiders min_range / ranged web, nutrition profiles)
Tier 1 (beetle, dragonfly, skink, shrew, spore drone, ranged *Frill Spitter*), elite *meganeura* (giant dragonfly), boss
*husk queen*; stage 2: compy, dire pup, glyptodon, elite *smilodon*, boss *infected mammoth*.

### Seed
Every run gets a fresh random seed (type your own on the egg screen). The seed drives stage layout,
weather, rooms, shuffles, enemy spawns and rewards through hashed sub-seeds, so a run is reproducible.
Last seed is saved.


### Exits (room choice on the battlefield, Hades-style): paths OUTSIDE the board, drawn as negative space
`scripts/combat/ExitGen.gd` + `StageGen`. **1-3 exits per room** (`stages.json` -> `doors` is a fixed count or `[min,max]`, rolled with the seeded
stage rng, hard cap `StageGen.MAX_EXITS = 3`). Each exit is a **path that leaves the arena through the surrounding tree line**: nothing is drawn on the
tile mesh. There are **no exit / gate sprites** (`exit_<theme>*.png`, `gate_<theme>.png` were removed; nothing to override).
* **Placement** - every exit has a trigger tile on an **edge tile** of the arena (never a corner), on a different side each (NE y=0, NW x=0, SE x=w-1,
  SW y=h-1). **Door 0 is the main path forward and always leaves through an up-screen side (NE / NW)**; the other doors use the remaining sides as
  alternative side paths. The trigger tile (and its inner neighbour) is carved walkable and reachable from the player's start.
* **The corridor** - from the trigger tile a corridor **3 tiles wide and 6 tiles long** (`ExitGen.corridor`, `visibility.json` -> `exit_path.width / length`)
  runs outward through the border. When the border props are generated (`BattleBoard._draw_outer_ground`) the props / decoration on the corridor tiles
  are flagged: they look exactly like the rest of the dense border while the exits are hidden.
* **Hidden during combat** - while enemies know about you (spotted fights) the corridor is full of trees / rocks / ice like everywhere else, no badge, no
  reward info, no highlight; the trigger tile is plain ground (no seal, units walk over it).
* **Revealed after the clear** - in the explore phase the props in the corridor fade out (`exit_path.fade_time` 0.9 s) and **plain floor** is left
  (jungle: a few dirt tile variants, `dirt_variants`/`dirt_chance`; tundra: snow floor; cave: cave floor, no rocks), with a faint light strip along the path and a soft
  glow on the ground at `exit_path.glow_at` (3 tiles out) in the reward colour. The **reward badge** (Cards & XP, Rare cards & big XP, XP/food/healing,
  Food, Unknown boon or risk, BOSS lair: `RoomInfo.REWARD_HINT`, never the encounter) appears over the end of the path only now.
* **Taking a path** - click anywhere on the open corridor (`BattleBoard.pick` maps it to the trigger tile), or walk onto the edge tile in move mode
  (12 Move Points in explore; pathfinding goes to the trigger tile like to any tile). A short fade leads straight into the new area (no encounter screen).
* **Sneak-past rule (chosen design)** - unspotted players see the paths (the ambush phase: the corridors are open from the start, neutral glow, no reward
  badge) and may walk onto a trigger tile to slip out (no fight, no spoils; the next explore field reveals the paths with their rewards). **Once an enemy
  spots you the corridors fill back in (fade) until the fight is cleared.**
* Same seed = same exits and rooms; entering still costs hunger and weather / boss gating is unchanged. Hover a trigger tile or a path for its tooltip.
* Tests: `test_exit_paths` (40 seeded arenas: count, distinct sides, forward door 0, edge-only triggers, every corridor tile outside the grid, corridors never overlap,
  hidden / ambush / explore visibility, reveal state machine and `pick()` on jungle / tundra / cave, no sprite code). Tour: `_exit_paths_demo`.

### Secret cave (rare, optional)
`stages.json` → `secret` (per stage; `chance` 0.12 per fought room, own rng stream so layouts do not shift). Before the room is cleared a **faint cracked rock
tile** (`secret_crack.png`, no UI marker) is the only hint, and only if you look. When the area is cleared the screen plays a short
animation: a rock (`secret_rock.png`) falls away and the opening (`secret_hole.png`) starts to glow softly; the glow persists until you leave.
Entering is a normal path node: it **costs hunger like any room** but does **not** use up a step (you return to the gates of the same room).
It is **harder** (higher-tier spiders: Cave Spider, Web Spitter (ranged, **web** slows you), Tomb Widow, **poison**), uses a dark cave theme
(`themes.json`, `bg_/fg_cave`) and pays **better rewards**: 4 unique cave cards (`venom_fang`, `silk_snare`, `chitin_plating`, `widow_kiss`)
+ an `elite` draft, bonus food (`reward.hunger` 25 / 30) and an **item choice of 3** with better rarity odds (`items.json` source `cave`).
Respects facing/stealth/search like any fight (ambush it, or sneak out through an exit while unseen).

### Terrain move cost & traits
`data/tiles.json`: every tile has `move_cost` (ground/grass 1, **water 2**, obstacle blocked; add mud/deep snow with 2+). Costs drive pathfinding,
the move-mode highlights, the cost number on the hovered tile, enemy AI paths and the "Moves Left" counter. `traits` maps a **tag** to cost overrides
(`aquatic` / `semi_aquatic` / `flying`: water 1); any species or enemy def may also carry its own `terrain_cost: {tile_id: cost}` which wins.
Items can change it too (Marsh-Walker Pads: water costs 1).

### Statuses added
**Poison** (`POISON_DMG` 2 per turn, counts turns), **web** (`WEB_SLOW` 2 Move Points lost, never below 1), plus bleed / weak / expose / stun / spores.

### Jump / leap rule (`min_range`)
Jump-type cards are data-driven: `min_range` (Pounce, Leaping Rake, Shadow Rush, Apex Ambush: 2) means the **target must be at least that far away**
(not usable adjacent); `min_enemy_dist` (Grass Dive: 2) means no enemy may be within that distance. Unplayable cards are greyed and the hover
card shows the reason ("Can't play: ..."). The enemy AI respects `min_range` on its own leaps.

### Items (`data/items.json`, `ItemUI`, `ItemScreen`)
Passive and active (`use`, once per battle) items with rarities common/uncommon/rare/legendary. Bonus keys (`RunState.item_bonus`): max_hp, move,
stamina, back_damage, unaware_damage, water_cost, hunger_save, nutrition_pct, weather_resist, kill_heal, turn_block, stealth, poison_bonus.
Sources (`items.json` → `sources`): **battle** (7 % rare drop after a cleared area), **elite** (30 %), **cave** (3 choices, better odds) and **boss**
(always a **choice of 3**, can be legendary). Items marked `only:["cave"|"boss"|"branch"]` only come from there (branch forms are granted by evolution
branches). The inventory is shown in the HUD (rarity frames) with tooltips; active items are clickable in battle (gold dot = ready).
| Item | Rarity | Effect |
|---|---|---|
| Spider-Silk Wrap | common | +8 max HP |
| Chitin Charm | common | +1 move point each turn |
| Chitin Plates | common | start each turn with 2 block |
| Glow-Cap Spore | uncommon | +1 stamina |
| Assassin's Fang | uncommon | +3 damage from behind |
| Shadow Pelt | uncommon | enemy sight -1 |
| Marsh-Walker Pads | uncommon | water costs 1 |
| Thick Pelt | uncommon | immune to weather penalties |
| Bloodlust Charm | uncommon | heal 3 on kill |
| Bandage Moss | uncommon | ACTIVE: heal 8 HP |
| Lean Gut | rare | lose 2 less hunger per room |
| Gut Flora | rare | +40 % nutrition from meals |
| Ambusher's Talisman | rare | +4 damage vs unaware |
| Venom Gland (cave) | rare | poison +2 |
| Adrenal Gland | rare | ACTIVE: +2 stamina |
| Apex Heart (boss) | legendary | +12 max HP, +1 stamina, +1 move |

### Nutrition & evolution branches (`data/nutrition.json`)
After every won fight each fallen creature can be **eaten or skipped** (per kill, optional). Each has a nutrition profile (protein, fat, minerals, fiber,
toxins; infected meat adds toxins + spores). The preview shows *fit for you*, hunger/HP gain, toxin risk and the **growth bonus** the meal would give.
Eating restores hunger (infected meat half) and fills the run's meters (HUD indicator "P F M Fb T" + diet quality; tooltip has details).
* **Diet per species** (`species.json` `diet`: carnivore / herbivore with weights) decides what counts (a carnivore gets nothing from plants).
* **Growth bonus**: diet quality (Poor / Fair / Good / Excellent) multiplies **all XP** by +0 / +10 / +15 / +25 % (`nutrition.json` `xp_bonus`). Shown in the HUD
  XP bar (`+15%`), the DietMeter, the eat preview and the victory line ("diet bonus +n"). Poor eating never reduces XP.
* **No stat penalties for poor eating, ever.** Nutrition only *unlocks* the stronger growth branches: at each evolution (tiers 2-4) the
  Evolution screen offers **Steady Growth** (always) plus 2 diet-gated branches (e.g. Swift Stalker needs 5 protein AND diet score 28; Alpha Raptor needs diet score 48 and toxins <= 8). Locked
  branches are shown with **what they needed and your progress** – requirements are never shown at the start of a run; a one-time hint explains the idea the first time you can eat.
  Branches grant a branch form item (+stats, shown in the HUD) and often an extra rare card pick.
* Toxins hurt immediately (`toxin_hp` per point) and live in their own meter; infection keeps its own spores effect.

### Readability / typography
All text is **pixel-crisp**: fonts are **Jersey 10 / 15 / 20 / 25** (SIL Open Font License, `assets/fonts/OFL.txt`) drawn on the native **640x360** canvas and scaled by whole numbers, so a font pixel is always a whole number of screen pixels.
**Readability rule: no text below 15 px native.** The design type classes `UITheme.SZ_S / SZ_M / SZ_L / SZ_XL` = 15 / 20 / 30 / 40 snap (`UITheme.snap()`) to real sizes **15 / 15 / 20 / 30 px**: small text, card text, tooltips, log, captions and hints = Jersey 15; body, labels and buttons = Jersey 15; headings and numbers = Jersey 20; titles = Jersey 15 at 30 px. Jersey 10 survives only behind the explicit `UITheme.TAG` opt-in for tiny non-essential tags.
A Large set (20 / 20 / 25 / 30 px, Jersey 20 / 25) exists as `UITheme.text_large` (snapping is unit-tested) but is **not exposed in Settings**: every layout is authored for the Normal scale, and a Large option would need a second relayout of every screen.
Fonts are loaded with antialiasing off, hinting off, subpixel positioning off. Contrast: light text on dark panels, a 1 px drop shadow on labels/buttons and a dark outline for text drawn over the art.
Cards: hand cards show art + name (Jersey 15) and **hovering shows the big zoom card** with the full text; draft / reward cards use the big size (Jersey 15, <= 5 lines enforced by a test). Hint boxes size themselves to the text; the first-run nutrition tip is shown inside the Encounter Cleared popup so no floating hint covers it.
`tests/TextAudit.gd` audits every visible text (size >= 15 px, fits its box, on the canvas, inside its panel): `test_text_audit` runs it on the battle screen, menu, draft and item screens, and `tests/Gallery.gd --audit` prints it for every gallery shot.

### Portraits (no background, no shadow)
`portrait_<stage>.png` (43x43) are transparent cut-outs of the raptor head: **no blue backing square, no drop / ground shadow**, only the sprite with its own dark outline (`tools/portrait_cutout.py` rebuilds them from `tools/art/supplied/raptor_a_se.png`). They are drawn straight over the board in the HUD, and `Look.apply` recolours them for every skin / pattern / gender like the body sprites. The customization egg peek uses the same transparent head.

### Combat depth (statuses, telegraphs, phases, intents)
* **Statuses** (all in the glossary): Bleed, Poison, Weaken, Expose, Stun, Web, Slow, **Daze** (half damage + half movement), **Fear** (the enemy flees and cancels its charge; bosses resist),
  **Mark** (your next hit deals +3, consumed), Infection; player buffs **Stalker**, **Calm**, **Evasion**, **Block**, **Momentum** (tiles moved this turn feed cards/items).
* **Payoffs / combos**: Gore (3 + 2 per Bleed, consumes it), Open Vein (doubles Bleed), Death Roll, Flanking Strike (+4 from side/back, +3 vs Bleed), Rending Charge (+1 per tile moved),
  Blood Scent / Feast Bite (diet), Mark Prey → any heavy hit, Dazing Blow → hit-and-run. Cards carry `flank_bonus`, `bleed_bonus`, `per_bleed`, `per_momentum`, `per_diet` keys (`Battle._synergy_damage`).
* **Armour** (glyptodon, beetle): front hits are reduced by `armor` but never by more than half; side/back hits ignore it (and *Expose* strips it).
* **Enemy behaviours** (`data/enemies.json`): *pack* (compy, dire pup: +damage per packmate adjacent), *ambusher/surprise* (skink, spiders: free first hit if you walk past unseen),
  *skirmisher + retreat_hp* (dragonfly, shrew: hit-and-run, break off when hurt), *kiter* (spitters back off then shoot), *tank* (shell up, bash), *summoner* (queen, mammoth, widow).
  Elites and bosses always track you (hiding does not shake them).
* **Telegraphs**: heavy abilities (`"windup": true`) charge for a turn: the **danger tiles turn red** and the blow lands next turn. Step off the tiles and it whiffs ("Sidestepped!"); **Stun** or **Fear** interrupts it.
* **Phases**: elites/bosses have `phases: [{hp_pct, bonus_damage, move, speed, summon, popup}]`, each fired once when HP drops below the threshold (frenzy, extra brood...).
* **Intent display**: every enemy shows what it will do next (`Battle.intent_of`): attack damage, ranged, leap, charge, windup, flee, search, stunned.
* **47 cards** (`data/cards.json`), **33 items** (`data/items.json`, passive and active) and new hints (intent, telegraph, keywords, synergy).

### Archetypes & synergy (`data/archetypes.json`, `scripts/core/Arch.gd`)
Six build styles: **Ambush** (stay unspotted, Stalker/Mark), **Bleed** (stack and cash in), **Flank/Backstab** (facing), **Speed/Tempo** (momentum, extra stamina),
**Hit & Run** (leaps, retreat, Daze) and **Scavenger** (diet, eating, hunger). Every card and item has `tags`. A tag's weight in your build = 1 per deck card + 2 per item;
once it reaches `synergy_threshold` (3), cards/items offered in the **draft, elite/evolution rewards and item screens are highlighted** (gold border, "SYNERGY: Bleed / Hit & Run"), and
every card shows small tag chips. The bot sim can force a build (`archetype=...`); the test suite plays 30 seeds per archetype and requires each to be viable and none to run away.

### Keyword glossary & tooltips (`data/keywords.json`, `scripts/ui/Keywords.gd`)
Status/keyword words (Bleed, Poison, Weaken, Stun, Web, Daze, Fear, Mark, Ambush, Backstab, Flank, Evasion, Momentum, Unspotted, Block...) are **bold and colour-coded** in card text,
item text, hints, evolution-branch text and the zoom card (a synthetic bold pixel font variant, so the glyphs stay crisp). **Hover a keyword for ~0.9 s** (`Keywords.HOVER_DELAY`) to get a tooltip with its numbers and stacking
rules; hovering an item icon or the HUD shows the item text with the same highlighting plus the definitions of the keywords it uses; the hand-card zoom also lists its keywords in a side panel.
Add a keyword = add an entry (`name`, `color`, `aliases`, `text`) to `keywords.json`; `ops` maps card effect ops to keywords. Tests: every glossary entry is complete, every op resolves, **every card's effect op that has a keyword is highlighted in that card's text**, item/hint
keywords exist, highlighting never changes the text, and a real hover (signal + timer) shows and hides the tooltip.

### Difficulty (`data/difficulty.json`, `scripts/core/Difficulty.gd`)
Enemy HP = base × level × stage × (1 + `step_ramp` × room step) × room kind; flat bonus damage; a chance of one extra enemy in normal fights; hunger multiplier.
The **tutorial** (first 2 rooms of stage 1) is softened (HP ×0.7, −1 damage, no extras, normal hunger) and difficulty climbs from stage 1 room 3 on; stage 2 is much harder. **Normal / Hard** is a button on the egg screen
(`save.difficulty`): Hard = +20% HP, +1 damage, more extra enemies, +20% hunger. All of it is data; `tests/sim.gd` reports win rates.

### Display scaling (640x360 native canvas, "Pixel Perfect")
The game renders on a fixed **640x360** canvas (`project.godot`: viewport 640x360, stretch mode `viewport`, aspect `keep`, scale mode `integer`; `Main.apply_display()` keeps `Window.content_scale_size` at 640x360). Every element is drawn at 100% (or an integer multiple for hero art), nothing is fractionally scaled.
* **Settings -> Pixel Perfect** (ON by default, saved as `display/pixel_perfect`): the canvas is scaled by the largest whole number that fits the window and the rest is filled with bars (letterbox / pillarbox). 1280x720 = 2x, 1920x1080 = 3x, 2560x1440 = 4x, **2560x1600 = 4x with 80 px bars top and bottom**, 3840x2160 = 6x. OFF = the canvas fills the window with a fractional scale (nearest filtering, so pixels stay crisp but unequal).
* `Main.scale_for(win, pixel_perfect)` is pure and unit-tested (returns `{s, content, bars}`); the window is created at a whole multiple of 640x360 (minimum 2x). F11 toggles fullscreen. The old HUD-size setting and the 960x540 logic are gone: there is one HUD size.
* Camera zoom is in whole steps `[3, 2, 1]` (`data/arenas.json camera.zoom_steps`); steps snap (no easing) so the pixels never shear, and the zoom-out limit `zoom_out_margin` is evaluated against the 640x360 view band `[20, 14, 600, 280]`.
* `tests/ShotUtil.gd` composes screenshots at any window size (viewport texture is always 640x360, scaled by the Settings rule, bars included), used by `tests/Gallery.gd` and `tests/Tour.gd` (1280x720, 1920x1080, 2560x1600, 3840x2160).

### Asset pipeline (drop-in art; expected files in `assets/sprites/`)
Any PNG with these names **overrides** the generated art (no code changes; JSON fallbacks in `data/sprites.json` stay for tests). Re-import with `godot --headless --import`.
| File | Size (px) | Notes |
|---|---|---|
| `tile_<theme>_ground_N`, `tile_<theme>_tall_N`, `tile_<theme>_water_0/1` | 32x16 | iso diamond tile (theme = jungle / tundra / cave), N = variant |
| `prop_<theme>_obstacle_N` | 32 wide x 22-73 tall | bottom-anchored on the tile (tall = border trees only); `prop_<theme>_tallgrass` / `_tallgrass_front` 32x24 |
| `bg_<theme>_N`, `fg_<theme>_N` | 640x360 | backdrop / foreground foliage (fg has alpha) |
| `exit_<theme>` | about 40x27 | natural exit opening on a battlefield edge tile (procedural by default; a PNG overrides it). Foot at the tile's lower corner. |
| `exit_<theme>_block` | about 40x27 | the thicket / snow drift / boulders that fill the opening while it is locked; fades away when the exit becomes usable |
| `bd_<theme>_ground` | 96x96 | seamless packed-earth tile behind the menu screens (see *Menu backdrop*) |
| `bd_<theme>_{ammonite,ribs,skull,spine,footprint_l,footprint_r,stone_0..2,root_0,root_1}` | ~8-20 px | fossils / footprints / stones / roots scattered over the backdrop (cave: rock chunks instead of roots) |
| `bd_<theme>_skeleton` | 75x42 | large partly buried creature skeleton at a window edge |
| `bd_leaf_0..2` | 4x2 | falling leaf / snow / dust particles |
| `sky_<weather>_bg` | any (stretched to the canvas) | stage-intro cinematic: full sky backdrop (weather = clear, fog, rain, storm, heat, cold) |
| `sky_<weather>_clouds` | any, tiles horizontally | stage-intro cinematic: cloud strip that drifts across (drawn at 2x) |
| `sky_<weather>_horizon` | any, tiles horizontally | stage-intro cinematic: skyline / tree strip along the bottom edge |
| `secret_crack` / `secret_hole` / `secret_rock` | 32x16 / 32x16 / 32x23 | secret cave tile states |
| `<sprite_id>` and `<sprite_id>_b` (back view) | per creature, e.g. beetle 24x19, spitter 27x21, raptor_baby 28x13 ... prime 40x19, husk_queen 50x41 | facing right/front-left; `_b` is used when facing away. Raptors: `raptor_<stage>[_sw/_b/_nw]` |
| `portrait_<form>` (baby/juvenile/adult/prime/spitter) | 43x43 | HUD portrait |
| `egg_raptor`, `egg_locked` | 22x25 | egg select icons; `egg_raptor_hi` (110x125, drawn 1:1) is the cracking egg on the customize screen |
| `card_<card_id>` | 61x36 | card art (hand crops it to 61x22, big card shows it at 1x) |
| `item_<item_id>` | 13x13 | item icon |
| `icon_<name>` | 11x11 | HUD / status icons |
| `ui_panel*`, `ui_badge` | 21x21 / 15x15 | 9-slice frames |
| `ui_btn`, `ui_btn_hover`, `ui_btn_pressed`, `ui_btn_disabled`, `ui_btn_cyan`, `ui_btn_cyan_hover` | 25x14 (5 px caps) | stone-wood button, nine-patch, see *Designer art* |
| `ui_bar_frame`, `ui_bar_slim`, `ui_bar_fill_{hp,stamina,hunger}` | 73x23 / 68x8 / 16x3 | HUD bars, see *Designer art* |
| `foliage_01..30`, `log_01..04` | ~12-25 px | sliced bush / fern / log sprites used by the props |
| `tree_pine_01..04`, `stump_pine_01..04`, `fallen_pine_01..02` | 22x44 .. 29x53 / 12x8 / 49x21 | the pine sheet (credit @kianamosser): jungle + tundra border trees, board obstacles and fallen-tree decor |
| `bg_customize_hi`, `egg_raptor_hi` | 400x540 / 110x125 | native-pixel customize backdrop and egg, drawn at 1:1 (`tools/hires_backdrops.py`) |
Fonts: `assets/fonts/Jersey10-Regular.ttf`, `Jersey15-Regular.ttf`, `Jersey20-Regular.ttf` (see *Readability / typography* for the size mapping).

### Hints
Short dismissible tooltips (movement, stamina, turn order, drafting, hunger, stealth, weather…) from
`data/hints.json`; "Got it" or "Hide all hints" persist in `user://save.json`
(`hints_seen`, `hints_enabled`). "Replay hints" resets them on the egg screen.

### Isometric camera
`scripts/ui/Iso.gd` is the single projection: `screen = ORIGIN + ((gx-gy)·16, (gx+gy)·8)` (32x16 tile) with the origin fitted to the 640x360 view; tile centre = tile + (.5,.5).
Grid logic (BGrid/Battle) is still **square**; the iso transform is used only for drawing, hover, click picking, highlights and previews.
`BattleBoard` draws back-to-front by `x+y` (props, grass, units interleaved), diamond highlights for move/target/detect, tall-grass
overlays, falling snow/pollen particles. Units are always drawn at `Iso.center(vis_pos)`, and the screen snaps `vis_pos`/`vis_facing`
to the logical state after every replayed action, so there is no tile offset at fight start or after movement (tested, see below).

### Stage themes
`data/themes.json` (generated) has a theme per stage (`stages.json` → `theme`): **jungle** (lush, pollen) and **tundra** (icy: snow tiles, frozen
water, snowy props, falling snow). Each defines tile/prop/backdrop variant counts, grid/highlight colours, particles, flyer lift, ambient tint.
Add a theme by generating new `tile_/prop_/bg_/fg_` PNGs and a `themes.json` entry.

### Art
Sea-of-Stars-*inspired* pixel art produced by a **Python generator** (`tools/gen_art.py` + `tools/art/*.py`, numpy + Pillow):
lit-mask shading with dithered limited ramps (hue-shifted shadows/highlights), selective outlines, layered foliage backdrops, directional
creature sprites, 9-slice navy UI frames, card art and 16 px icons. It writes ~180 PNGs into `assets/sprites/` which **override** the legacy
JSON shape sprites (`data/sprites.json`, still the fallback and used by tests). Re-run `python3 tools/gen_art.py [--only tiles|bg|creatures|ui]`.
Honest ceiling: it is procedural art, not hand-painted – it reads as cohesive, detailed pixel art, but a human pixel artist would still beat
it on creature animation, expressive faces and tile-to-tile variety. Replace any PNG in `assets/sprites/` to upgrade it with no code changes.
Fonts: Jersey 15 + Jersey 20 (OFL, `assets/fonts/`) – see *Readability / typography*.

### Animations
All tween/procedural, quick, and **awaited**: `Battle` is pure logic that emits events; `BattleScreen._play` replays them one at a time and the
battle UI stays `busy` (input locked) until each effect finishes. Presentation state lives in `BUnit.vis_*` (`vis_pos` stays exactly on the tile
grid between tweens; `vis_off`, `vis_lift`, `vis_squash` are pixel offsets that are always 0 at rest). After every replay the screen snaps
`vis_pos/facing/state/offsets` to the logic state, and tests assert sprites end exactly on their tiles.
* **Walking**: per-tile linear tween with a 3 px step hop and a dust puff, landing exactly on the tile centre.
* **Melee**: wind-up → lunge 11 px along the iso diagonal → return; target gets a white hit-flash, a short shake, a spark burst + claw-slash streaks,
  floating damage numbers ("-6", "Blocked", "BACK hit x1.5") and a screen shake on big/player hits.
* **Pounce / leap** (ambush strike, Pounce card, enemy leaps): fast arced leap (sprite lifts, shadow shrinks), landing dust and a shock ring + screen shake.
* **Ranged**: enemies with `range > 1` (new **Frill Spitter**, Husk Queen spores, Spore Cloud, Spore Lash) recoil and fire a projectile sprite
  that travels along the iso line on an arc with a trail and bursts on impact (`projectile` event: `kind` spit/spore).
* **Idle**: breathing bob (1 px rise/settle, staggered per unit; flyers hover), plus board ambience (pollen/snow).
* **Death**: puff of dust, the body collapses (squash + spread) while fading.
* **Status pulses**: bleed ticks and spores flash a red/green pulse ring; infected enemies throb purple every ~2.5 s; infection / healing / block spawn
  expanding rings; bleeding units pulse red.
* **Card play**: the played card pops up, scales and fades while a coloured ring (attack red / skill blue / power purple) pulses under you.
* No speed/skip option (internal `speed` is only used by tests and the screenshot tour).
Frame sequences recorded by the tour are in `screenshots/anim/` (`pounce_*`, `walk_*`, `enemy_turn_*`, plus `.gif` and contact sheets).

## Project layout
```
data/                 all content as JSON (species, growth, tiles, weather, cards, enemies, stages, events, puzzles, hints, sprites, items, nutrition)
scripts/core/         DB (data loader), RunState, StageGen, WeatherSys, SequencePuzzle, RunSimulator, Difficulty, Arch
scripts/combat/       Battle (rules, pure logic emitting an event list), BGrid, BUnit, AutoPlayer (test bot)
scripts/autoload/     Game (run lifecycle, save file, screen routing), Hints
scripts/ui/           code-built UI: screens/, CardView, BattleBoard, Hud, Keywords (glossary + tooltips), SpriteFactory, UITheme...
tests/                run_tests.gd (≈6700 assertions), sim.gd (balance sim), Gallery.gd, compile_all.gd, Tour.gd
tools/                check.sh, run_tests.sh, run_tour.sh, gen_art.py (+ art/ engine), gen_sprites.py (legacy)
```
Logic is separate from UI: `Battle` and `RunState` are `RefCounted`, so they are fully testable headless and the UI just
replays the battle's events with tweens.

### Data format cheat-sheet
* **Cards** (`cards.json`): `{id,name,tier,cost,type,target,range,effects:[{op:"damage",amount:4,...}], text}`; ops include
  damage, bleed, leap, retreat, hide, draw, mp, extra_turn, expose, stun, heal_hunger… (see `Battle._apply_effect`).
  Tier 0 = starter, 1 = baby, 2 = juvenile, 3 = adult, 4 = prime.
* **Enemies**: stats, `tags`, `abilities` cycle (`melee|leap|aoe|summon|infect|block`), `hit_and_run`, `infected_chance`.
* **Stages**: `steps` count, weighted `door_pool` per tier, `required` room types, theme, weather pool.
* **Events**: choices with outcomes (hp/hunger/xp/cards/battle). **Forage** options are in the same file.
* **Weather**: `{global:{}, by_tag:{tag:{}}}` modifiers.

## Verification done
* **Balance (tests/sim.gd, 100 seeds each)**: before this pass the naive bot won ~55-65% (README above) and the competent bot did not exist; now the **competent bot wins ~24% with selective eating (fit) vs ~18% when it eats everything (300 fresh seeds: 71/300 vs 55/300; 1.0 vs 0.6 branches per run)**, gorging 16%, never eating 17%, hungry-only 19%, the **naive bot 3%**, **Hard 11%**. Eat-everything still buys survival (heal + hunger) but junk meals drag the rolling diet score, so the carnivore branches (all gated on diet score as well as nutrients) stay locked and the +10/15/25% growth bonus never arrives. Poor diet never reduces stats. Archetype builds (100 seeds, competent selective bot): Ambush 19%, Bleed 20%, Flank 17%, Speed 21%, Hit & Run 18%, Scavenger 13%.
  Per stage (competent bot, 100 seeds): 80% clear stage 1, of those 25% win stage 2 (`PER-STAGE` line of `tests/sim.gd`); the naive bot dies in stage 1 86% of the time (37% by room 5). Archetype builds (80 seeds, competent bot): Ambush 21%, Bleed 29%, Flank 23%, Speed 20%, Hit & Run 28%, Scavenger 21%.
* `tools/run_tests.sh`: **6666 passed, 0 failed** — data validation, grid/LOS/pathing, seeds & stages, turn order, weather, stealth, every card,
  infection, hunger/growth, puzzle, hints, **iso projection round-trips, unit/tile alignment at fight start and after moves, facing geometry,
  free turning & persistence, card/enemy facing modifiers, previews, vision cones, themes, enemy search AI (lose sight → walk to last seen → scan → give up → roam, alone, cone/weather/cover), ranged projectile events, and a real `BattleScreen` replay that checks sprites end on their tile**, plus bot simulations of combat and full runs.
* `tools/run_tour.sh`: real UI clicked through under xvfb → ~59 screenshots + animation frames in `screenshots/` (egg → jungle battles incl. facing preview,
  free turn, move mode → tundra boss → game over); also asserts every unit is drawn on its tile whenever the screen is idle.
* Linux export `--selftest` (25 bot runs from the exported pack); Web build boots in headless Chrome; Windows build exported (not run here).

## Assumptions / design decisions
* Movement is free but MP-limited (see above) so that stamina stays a pure card resource.
* "Ambush range" is the whole board for the free strike (simple to understand; pounce leaps in).
* Weather multipliers compose multiplicatively; hunger below 30% is "low".
* Difficulty target: a competent bot wins ~15-30% of runs, a naive bot < 10% (see Difficulty and the final numbers below); numbers live in `data/difficulty.json`.
* Save file only stores meta flags/last seed – a run is **not** resumable after quitting (roguelike, short runs).
* Audio is not included.

## Known gaps / next steps
* Only 1 playable species; locked eggs are placeholders. No audio; art is procedural (see Art) and there are no multi-frame sprite animations: motion is tweened/procedural (hop, lunge, squash, rings), not hand-drawn frames.
* Only 2 stages, one puzzle, five events; more enemies for later tiers (mammoth/dire wolf as normal elites, aliens).
* Balance pass; card upgrade/shop systems; run-end meta-progression; controller + touch support for the web build.
* The secret cave is not offered after you *sneak past* a room (no fight = nothing to clear); evolution branches grant stat items but have no unique sprites; the smallest text (Jersey 10) is crisp but small: 1920x1080 (3x) or larger is the comfortable size.
* Accessibility options (text size, colour-blind safe detection overlay); keyword tooltips need a mouse (no touch/controller equivalent).
* Search AI: enemies search one at a time on a simple "last seen tile + 2 scans" rule (no multi-tile sweeps/patrol routes between rooms); roaming is a random walk around the home tile. Animations are quick procedural tweens rather than hand-drawn sprite frames.

## Settings (gear button / Esc)
* **Gear button** on the egg screen (top-right) and in battle (next to the weather strip, top-centre); **Esc** opens the panel anywhere (in battle Esc first cancels a selected card / move mode). Close with Close, Esc or the gear.
* **Pixel Perfect** (default ON, applies live): the 640x360 canvas is scaled by a whole number and bars fill the rest of the window; OFF fills the window with a fractional scale. There is no HUD-size option any more: the whole UI is authored at native pixels and everything scales together (player card, turn order, buttons, hand, log, tooltips). The corner layout is kept: player info top-right, turn order top-left, Move/End Turn bottom-right, cards bottom-centre.
* **Fullscreen** toggle (same as F11) and **master volume** (drives the Master audio bus; 0 mutes). 
* Persisted in a user config file (`user://settings.cfg`, ConfigFile; Linux: `~/.local/share/godot/app_userdata/Primal Instinct/settings.cfg`, Windows: `%APPDATA%\Godot\app_userdata\Primal Instinct\settings.cfg`), separate from the run save. Code: `scripts/core/Settings.gd`, `scripts/ui/SettingsOverlay.gd`, `Main.scale_for(win, pixel_perfect)`.
* Tests: `scale_for` for every window size with Pixel Perfect on / off, persistence round-trip, overlay controls (Pixel Perfect toggle), live re-scale, Esc, and the 640x360 battle layout (corners kept, no overlaps, all on screen). Screenshots: `screenshots/tour/` at 1280x720, 1920x1080, 2560x1600 and 3840x2160.

## Character customization (egg screen -> crack -> customize -> hatch)
* Press **HATCH!** on the egg screen: the egg wobbles, then the **customize screen** opens (`CustomizeScreen.gd`): the egg cracks open in the centre of the screen and the creature's **eye peeks out** (blinks), drawn in code (`EggView`).
* Options (all in **`data/customization.json`, per species**): **skin colour** (10 palettes incl. Classic = the original art), **skin pattern** (Solid / Stripes / Spots / Mottled) with a **pattern colour** (8), **gender** (Male / Female - **cosmetic only**: a small difference in crest colour; flagged `cosmetic`, no stat, deck, RNG or gameplay effect).
* **Live preview**: the head in the egg and a **Growth preview** strip (baby, juvenile, adult, prime) update on every click. **Random all** rolls a new look; **Back** returns to the egg screen; **HATCH!** (Confirm) cracks the egg fully and starts the run wearing the look.
* **Carries through every stage**: `Look.apply()` (scripts/core/Look.gd) palette-swaps the existing art at runtime: skin pixels (found by per-sprite hue window in the data) keep their original shading but take the chosen colour (small per-stage tone offset), the pattern is painted on skin pixels only, crest pixels get the gender tint, portrait backgrounds are left alone (reference mask `portrait_bg_raptor.png`). `SpriteFactory.get_texture/png` apply the run's look to the 12 listed sprites (raptor_{baby,juvenile,adult,prime}[_b], portrait_*), so the board, turn-order bar, HUD portrait and deck views all wear it; the infected tint still stacks on top. Tile alignment is untouched (size/alpha preserved).
* **Designer art later**: swap in new PNGs under the same ids (and edit `sprites.<id>.skin_hue` / add sprites to the list); the option ids (`skin`, `pattern`, `pcolor`, `gender`) stay stable, so a layered-art pipeline can map layers to them. Persists for the run (`RunState.look`) and **resets every run** (new runs start from Classic/Solid/Male unless chosen).
* Tests: palette/pattern recolouring on all 12 sprites, default look pixel-identical, cosmetic-only stats/RNG, runtime texture swap, egg -> customize -> run flow. Tour shots: `customize_*`.

## Large displays (2560x1600 / 4K) and the 640x360 HUD
* Every screen is laid out once, on the 640x360 canvas, and scaled by the display rule (see *Display scaling*): there is no separate "big window" HUD any more. 2560x1600 = 4x with 80 px bars top and bottom, 4K = 6x.
* **Battle HUD** (anchored to the canvas corners, never overlapping): turn order top-left (with items and the diet meter below it); player card top-right (portrait, HP / stamina / hunger bars, Deck button + draw / discard counts, hover info panel under it); weather + stage strip top-centre; log bottom-left; Move / End Turn bottom-right; card hand bottom-centre (hover a card for the 144x184 zoom).
* **World camera** zoom steps are `[3, 2, 1]` (whole multiples of the 32x16 tile art), with the view band `[20, 14, 600, 280]`.
* Gallery: `--gallery --sizes=2560x1600,1920x1080,1280x720,3840x2160 --cases=jungle_battle,tundra,cave,boss,egg,draft,menu,customize,settings,deck,gameover,branch,event,puzzle`.

## Menu backdrop (prehistoric ground)
`scripts/ui/Backdrop.gd` replaces the old tile background behind every menu screen (`ScreenBase.add_bg`). It covers the whole window at every size, is low contrast and is drawn at an integer pixel size (`px`, so it is crisp at every scale).
* Layers: packed-earth ground tile (`bd_<theme>_ground`, seamless 192x192) -> hashed, deterministic scatter of fossils (ammonite, ribs, skull, spine), dinosaur **footprint trails**, stones and roots (cave: rock chunks) -> a **large partly buried animal skeleton** anchored to one window edge (never human remains) -> tint + dim -> sparse drifting leaves (jungle) / snow (tundra) / dust (cave).
* Theme-aware (jungle / tundra / cave) and fully data-driven: `data/backdrops.json` (`px`, `cell`, `trail_cell`, `density`, `decor_alpha`, per-theme `ground`, `tint`, `dim_scale`, `decor[]` weights, `trail`, `skeleton` {sprite, edge, x, bleed, visible}, `particles`). The `_doc` key explains every field.
* Art: `tools/art/art_backdrop.py` (regenerates `assets/sprites/bd_*.png`, e.g. `bd_jungle_ground`, `bd_tundra_skeleton`, `bd_cave_footprint_l`). Any PNG with the same name overrides it (sizes in the asset table).
* Tests: layer/stat checks per theme and window size (1280x720 .. 4K), determinism, footprints/skeleton kept apart, particles, README. Gallery cases `bd_jungle`, `bd_tundra`, `bd_cave`.

## Stage-intro cinematic (start of the run and between stages)
`scripts/ui/screens/StageIntroScreen.gd` + `scripts/ui/SkyView.gd` replace the old weather list screen:
1. an animated **sky shot** themed to the rolled weather (gradient, sun, drifting clouds, fog, heat shimmer, rain / snow, lightning flashes; data in `data/weather.json` -> `sky`),
2. the **stage name** and then the **weather name + effects** fade in slowly, 3. hold, then fade out,
4. the camera **tilts down** from the sky onto the real battlefield (the actual `BattleScreen` is built underneath and handed over by `Main.adopt_screen`), ending *exactly* in the normal gameplay framing, no rebuild or flicker.
* **Any key or mouse click skips** straight to the board. Timings are constants at the top of the script (`T_BLACK`, `T_TITLE_IN`, `T_WEATHER_IN`, `T_OUT`, `T_PAN`, `PAN_DUR`; about 9 s in total). Tutorial hints are held back until the cinematic ends.
* Scales with the display rule (the sky is drawn at 2x pixel size on the 640x360 canvas).
* **Designer PNGs** replace the procedural layers: `sky_<weather>_bg`, `sky_<weather>_clouds`, `sky_<weather>_horizon` (see the asset table). Missing layers stay procedural.
* Tests: effects text per weather, timeline (text fade in/out, pan start/end offsets, final framing equals the normal board), skip by key/click, adoption of the BattleScreen, every weather. Gallery: `--cases=seq_clear,seq_rain,...` writes frames `f0..f5` + the skip result. Tour shots: `stage_intro_1_sky` ... `stage_intro_5_tilt_end`.

## Intro story cutscene (after the egg customization, before the weather intro)
Flow: egg screen -> customize -> **HATCH!** -> **intro story cutscene** -> stage-intro cinematic (weather) -> board. About **48 s**, no voice, six short pixel-art shots with letterbox bars, fades through black, parallax camera pans, screen shake / flashes and soft **Jersey captions**:
1. **Inside the egg** - first-person view from the nest through the cracked shell (`bg_customize` nest scene, the shell opening as the baby blinks awake). *"A quiet morning in the nest."* The mother returns across the clearing.
2. **Mother feeds the baby** - the hatchling (wearing **your chosen look**) trots to its mother (the adult raptor sprite at 4x in the original, unrecoloured look), she hands over meat, the baby hops, hearts float up. *"Mother always returned with food."*
3. **The sky breaks** - the camera tilts down as a small procedural meteor (bright head + fading trail) streaks across the sky and crashes: white flash, screen shake, an orange glow and a smoke plume rising on the horizon. *"Then the sky broke."*
4. **Something crawled out of the fire** - dark silhouettes of the existing alien enemies (`husk_queen`, `spore_drone`) rise from the crater against the fire glow while a purple infection creeps over the ground and spores drift (no gore). *"Something crawled out of the fire."*
5. **Mother fights** - the aliens close in, the mother lunges, purple flashes and shakes; she is infected (the existing infected tint crossfades in, then she fades to a dark silhouette). The baby backs away. *"Mother fought. It wasn't enough."*
6. **Run** - the baby, trembling, bolts off-screen (left) while the infected mother and the creatures stand in the purple dusk; slow fade to black. *"Run."* -> the normal stage intro starts.
* **Skippable at any time, even on the first play**: **Esc / Space / Enter** skip at once (Esc is consumed, it does not open Settings over the cutscene); **hold any other key or the mouse button** for ~0.6 s (a progress bar fills next to the prompt); or press the stone-wood **Skip** button in the bottom-right letterbox bar. A skip fades to black in 0.25 s and continues to the stage intro.
* **Settings -> Intro story cutscene**: *Always* (default: plays at the start of every new run, runs restart from the egg) / *First time only* / *Off*. `Settings.intro_mode` + `intro_seen` are persisted in `settings.cfg` (section `story`); starting it marks it as seen.
* **Data-driven**: everything is in **`data/cutscene_intro.json`** (`tools/gen_cutscene_json.py` regenerates it; after that the JSON is the source of truth and can be edited by hand). Per shot: `dur`, `fade_in/out`, `camera` (from/to pan, integer pixels), `shake` / `flash` cues, `captions` (`text`, `t`, `dur`), `sfx` placeholder cues (`[{t, id}]`, emitted as `CutsceneView.sfx` and logged in `sfx_log`; there is no audio system yet) and ordered `layers`. World coordinates are the 640x360 frame (`"frame":[640,360]`, converted once from the old 960x540 layout by `tools/rebase_cutscene.py`, idempotent); every layer has a parallax factor `par` and optional `keys` = per-property keyframes (`x`, `y`, `alpha`, `tint`, `mix`, `open`, `grow`, ...). Layer kinds: `sky`, `ground`, `scene`, `image`, `shell`, `eyelid`, `meteor`, `plume`, `glow`, `particles` (motes / spores / embers), `overlay` (tint / vignette), `creep` (infection spreading on the ground). The meteor, fire, smoke, spores and shell are procedural; sprites are the existing game sprites.
* **Designer art**: drop `assets/sprites/cutscene_<layer id>.png` (all shots) or `cutscene_<shot id>_<layer id>.png` (one shot) to replace an `image` / `scene` layer's sprite, e.g. `cutscene_mother.png`, `cutscene_meteor_plume.png`. Layer ids are in the JSON (`mother`, `baby`, `queen`, `drone_a`, `nest`, ...). Sprites are drawn at **whole-number scales with nearest filtering**; the validator rejects fractional scales.
* **Resolutions**: the cutscene is drawn on the 640x360 canvas like every screen (`CutsceneView.FRAME`); the letterbox bar height keeps the picture at about 2.2:1 (`CutsceneView.bar_height`, minimum bar 35 px), captions and the Skip button (48x16) live in the bottom bar. Sprites are drawn at scale `max(1, round(old*0.75))`; the scene layer uses the native-pixel `bg_customize_hi` at scale 1.
* **Bypass**: `Game.bypass_cutscene = true` (bot sim, scripted tests) or Settings Off makes `Game.intro_screen_name()` return `stage_intro`; `RunSimulator` never uses screens. Code: `scripts/ui/screens/CutsceneScreen.gd` (clock, skip), `scripts/ui/CutsceneView.gd` (drawing, timeline validation), `CustomizeScreen._finish`, `Main.SCREENS["intro_cutscene"]`.
* Tests (`test_cutscene`): timeline validates (6 shots, 35-50 s, captions, SFX cues, meteor shake + flash), the validator rejects bad data, keyframes, letterbox, SFX cues fire once, draws on the 640x360 canvas, customization -> cutscene -> stage intro order, skip by Esc / Space / Enter / hold / Skip button, hold cancels on release, natural end, Settings modes (Always / First time only / Off), bypass. Gallery: `--cases=cutscene --sizes=1280x720,3840x2160` writes 13 frames per size (shots composed with bars). Tour shots: `cutscene_<n>_<shot>_<m>` (4-5 frames per shot).

## Encounter Cleared popup (replaces the victory screen)
After the last enemy falls a centred **"Encounter Cleared"** popup is shown over the (still visible, dimmed) board. It contains the creature rows (eat / just fill up / skip, with the nutrition preview, growth boost and diet quality) and any loot. Card, item and evolution-branch picks follow as **popups in the same style**
(`ScreenBase.popup`, `Main.show_popup`, `Game.goto` routes reward / draft / item / branch to a popup while the board is a won battle). When the last popup is resolved the board is shown again with the exits usable.
The popups are laid out on the 640x360 canvas (popup rect 592x336) and sized to fit without overlapping each other or the canvas edge. Tests: `test_victory_popup`; the bot sim never used the screens and is unchanged. Gallery cases: `victory`, `victory_draft`, `victory_item`, `victory_branch`.

## Designer art (buttons, HUD bars, bushes / ferns, logs)

Sprites supplied by the designer, imported by `python3 tools/import_supplied.py` from the sheets in `tools/art/supplied/`
(`buttons_sheet.jpg`, `hpbar_sheet.jpg`, `foliage_sheet.jpg`, `logs_sheet.jpg`). The importer samples the upscaled JPG back to its real pixel grid,
removes the background, snaps colours and writes PNGs to `assets/sprites/`. The names it writes are listed in `tools/art/supplied/owned.txt`;
`tools/gen_art.py` never overwrites those, so **a designer can simply replace any PNG listed there** (same name and size) and it is picked up.
(Re-run `gen_art.py` first, then `import_supplied.py`, if you regenerate everything.)

### Buttons (every `Button` in the game)
`UITheme.build_theme()` gives all Buttons the stone-wood look; the label is Jersey 20/15, white with a dark-brown outline, centred in the tan face
(not on the red edge / lavender plate). Toggle / selected state (Move mode on, chosen customization option or Pixel Perfect) = teal face via `UITheme.set_selected(btn, on)`.

| file | meaning | size | nine-patch margins L,T,R,B | label padding L,T,R,B |
|---|---|---|---|---|
| `ui_btn` | normal | 25x14 | 5, 2, 5, 7 | 4, 1, 4, 5 |
| `ui_btn_hover` | lighter | 25x14 | 5, 2, 5, 7 | 4, 1, 4, 5 |
| `ui_btn_pressed` | darker, face sunk 2 px | 25x14 | 5, 3, 5, 5 | 4, 3, 4, 3 (label sinks 2 px) |
| `ui_btn_disabled` | desaturated | 25x14 | 5, 2, 5, 7 | 4, 1, 4, 5 |
| `ui_btn_cyan`, `ui_btn_cyan_hover` | selected / toggled | 25x14 | 5, 2, 5, 7 | 4, 1, 4, 5 |

The middle of the sprite is flat (1 px column stretches), so any size works; minimum height about 16 px for a 10 px label. Margins live in `UITheme.BTN_MARGINS`.
Sprites are drawn with nearest filtering at whole-number scales, so they are crisp from 1280x720 to 4K (the canvas is 640x360, scaled by whole numbers).

### HUD bars (top-right player card, `scripts/ui/BarSprite.gd`)
Top to bottom: **Health** (`ui_bar_frame`, 73x23 with the wing ornament and number tab), **Stamina**, **Hunger** (`ui_bar_slim`, 68x8 = the same frame without
ornament/tab, icon on the left, number on the right). Numbers are current/max, drawn live in Jersey (tab text of the sprite was removed).
* Frame: nine-patch, left/right margins **39 / 33** (full) and **34 / 33** (slim), top/bottom 0; the 1 px column in the middle stretches, so the bar can be any width.
* Fill window (transparent hole in the frame, native px): full `x=9, y=7, h=3, right inset 5`; slim `x=4, y=2, h=3, right inset 5`. The fill
  (`ui_bar_fill_hp` red, `ui_bar_fill_stamina` green, `ui_bar_fill_hunger` amber, 16x3 tileable) is **clipped** to `value / max` of that window, with a 1 px bright leading edge.
  Hunger tints the fill orange-red when low / starving.
* Drain animation: the shown value eases toward the real one and damage leaves a pale chip that follows a moment later (`BarSprite.settle()` skips it for tests).
* Number tab (full frame): `x=9, y=12, 29x8`.
* Enemy / unit overhead bars keep the simple 3 px bars: the sprite frame is 12 px tall and does not read at that size.

### Foliage and logs (`foliage_01..30`, `log_01..04`)
`foliage_01..20` round bushes / leafy shrubs, `foliage_21..30` ferns; `log_01/02` bare, `log_03/04` mossy (drop shadow kept as semi-transparent pixels).
Used by the battle props (obstacles, arena border foliage, tall grass); blocking and depth sorting are unchanged:
* **Jungle**: obstacles 2,3 = mossy logs (`log_03/04`), 6,7 = round bushes, appended 9-15 = more bushes + the two bare logs; **tall grass** (`prop_jungle_tallgrass_*` and `_front_*`) is built from ferns (3 per tile, the front layer only the lowest leaves so a hidden unit stays readable).
* **Tundra**: obstacles 2,3 = bare logs with a snow cap, appended 10-12 = frosted bushes (desaturated, snow-capped). Its own pines / ice stay.
* **Cave**: two dark bare logs appended (11, 12); cave keeps its generated rocks / stalagmites (no green plants).
`data/themes.json` `obstacle_variants` matches the number of `prop_<theme>_obstacle_N.png` files (tested). Replace `prop_*` directly or the `foliage_*` / `log_*` sources.
Tree / stump sprites: the pine sheet (@kianamosser) is integrated, see "Jungle iso sheet" above; the generated cave / tundra rocks and the tree-gap exits are unchanged.

### Jungle iso sheet (floor tiles, trees, bushes, rocks, props)
Source `tools/art/supplied/jungle_iso_sheet.jpg` (white background, ~79 px ground tiles). `import_supplied.py` flood-fills the white to transparency,
turns the grey drop shadows into semi-transparent pixels, scales **the whole sheet by 76/79** so its ground tile equals the game tile, and snaps colours.
It **takes priority over the older foliage / log sheets for the jungle** (those stay in use as extra variants).
* `tile_grass_01..32` (32x16 diamonds, row-major from the sheet: plain grass, dirt patches, flowers, pebbles). They are cropped to an exact 2:1 diamond so neighbours
  tile without gaps. They are also written as **`tile_jungle_ground_0..31`** (the files the game loads) and `themes.json` has `ground_variants 32` plus a weighted
  `ground_pool` (the 8 plainest tiles x6 each, flower / pebble tiles x1, dirt x1 => mostly plain grass, sparse variation; seeded per tile). Water, exits, the secret tile and the move / target highlights are unchanged
  and drawn on top, so terrain stays readable. `tile_jungle_tall_0..2` (tall-grass base) = three plain tiles tinted darker/greener.
* `deco_tree_01..12` (oak, teal, autumn, bonsai, pine, willow, palm, big oak, blossom, apple, flowering, blue-green), `deco_bush_01..09`, `deco_tuft_01..09`, `deco_rock_01..07`,
  `deco_stump_01`, `deco_hollowlog_01`, `deco_log_01`, `deco_branch_01`, `deco_pebbles_01`, `deco_leafpile_01`, `deco_woodpile_01`, `deco_fence_01/02`, `deco_small_01..09` (pebbles, plants, mushrooms).
* Jungle props: obstacles `prop_jungle_obstacle_0..55` (0,1 rocks, 6,7 flowering bushes, 16-27 the 12 trees, then bushes, rocks, stump / logs / woodpile / fences / branch; 2-5, 8-15 are the generated pine / ruins and the
  older foliage / log sheets). `themes.json`: `obstacle_pool` (arena border: includes the big trees, so the border reads as a tree line) and `obstacle_pool_interior` (obstacles standing on the board: **no tall trees**, so units are not hidden), chosen by seed.
  Tall grass `prop_jungle_tallgrass_*` (+ `_front_*`) = 4-6 grass tufts per tile on top of the darker grass tile (the front layer is only the lowest tufts, drawn over a hidden unit); the 25% evasion cover is unchanged.
* Ground decoration (`themes.json` `decor_ring`, `decor_interior`): mushrooms, pebbles, small plants, flowers, leaf piles. About 14% of empty border tiles, and about 6% of plain floor tiles
  (never on / next to exits, the secret tile or a unit). Purely visual, non-blocking.
* The ground still extends beyond the grid (border ring tiles use the same pool) with trees / bushes / rocks overlapping the edge. **Tundra and cave keep their own generated ground and props.**
* **Pine sheet (artist credit: @kianamosser)**: `tools/art/supplied/pine_sheet.jpg` holds 4 pines, 4 stumps and 2 fallen pines (the "@KIANAMOSSER" watermark is excluded). `tools/import_supplied.py --pines` slices them (grey background -> transparent, halo-peeled) into `tree_pine_01..04`, `stump_pine_01..04`, `fallen_pine_01..02`, and appends 12 `prop_<theme>_obstacle_N` variants for **jungle (`pine_base` 44) and tundra (frosted, `pine_base` 13)** in `themes.json`: the tall pines (02, 04) are **border trees only**, the short pines, stumps and fallen pines are border and board obstacles, and 0.8x saplings plus stumps / fallen pines are the interior pool (never tall trees on the board). The foliage see-through and exit-corridor rules are position-based, so they apply to the pines unchanged. Test: `test_pine_art`.

### Egg, nest and the customization background (`egg_raptor`, `egg_locked`, `bg_egg_nest`, `bg_customize`)
Source: the portrait jungle picture `tools/art/supplied/egg_nest_scene.jpg` (cream egg with brown spots in a twig / fern nest). `tools/import_supplied.py` (`egg_scene()`) resamples it to
a 120x162 pixel grid, snaps it to 48 colours, and `tools/rebase_640.py` bakes the 640x360 sizes. Assets (all listed in `owned.txt`, so `gen_art.py` never overwrites them):
* `egg_raptor.png` (22x25): the egg alone (transparent background, 1px dark outline, brown spots kept). Used by the egg-select icons. The **cracking animation** (`EggView` in `CustomizeScreen.gd`) uses `egg_raptor_hi.png` (110x125, drawn 1:1) when present: `tools/hires_backdrops.py` upscales the pixel art 5x (bicubic + unsharp) and median-cut quantizes it (20 colours), so the egg has native-density detail instead of 5x5 blocks.
  `egg_locked.png` (22x25) is the same egg shape and spot pattern as a cool grey silhouette for the locked eggs. Another playable egg can use its own PNG with the same size (vary the spot colours / pattern, keep the shape) and `sprites.egg` in `data/species.json`.
* `bg_egg_nest.png` (79x57): the nest on its own (egg painted out, dithered oval edge), drawn at 1x under every egg-select icon (the egg icon is drawn at 1x).
* `bg_customize.png` (80x108) / `bg_customize_hi.png` (400x540): the whole scene **without the egg** (the hollow is painted dark) because the egg is a separate sprite that wobbles, cracks and bursts. `NestBackdrop` (in `CustomizeScreen.gd`) draws `bg_customize_hi` at **1:1** (40 colours, native-pixel look; falls back to `bg_customize` at 5x)
  with nearest filtering, puts the hollow's bottom-centre (`ANCHOR` (200, 385) in the hi-res picture, `EGG_AT` (160, 196) on the canvas) under the egg, and mirrors the picture sideways and up / down so the canvas is always filled.
  A dark band behind the title and a light dim keep the text readable; the option panels are drawn semi-transparent (86%). If you replace `bg_customize_hi.png`, keep the egg's hollow at the same position (or change `ANCHOR`).

### Velociraptor sprites (4 facings, all growth stages) - `tools/import_raptors.py`
The player raptor uses the designer's four poses (`tools/art/supplied/raptor_{a_se,c_sw,d_ne,b_nw}.png`). Facing mapping (grid facings from `data/facing.json`):
| facing | file | source pose |
|---|---|---|
| SE (1,0) | `raptor_<stage>.png` | A: faces right, toward the camera |
| SW (0,1) | `raptor_<stage>_sw.png` | C: faces left, toward the camera (drawn larger so its smaller source matches the others) |
| NE (0,-1) | `raptor_<stage>_b.png` | D: long side pose, faces right |
| NW (-1,0) | `raptor_<stage>_nw.png` | B: long side pose, faces left |
`<stage>` = baby / juvenile / adult / prime: the SAME art scaled by stage on the 640x360 canvas (`tools/rebase_640.py` `RAPTOR_W`: baby 28, juvenile 33, adult 37, prime 40 px wide; the baby is a touch larger than true scale so it stays legible). `tools/raptor_details.py` then restores the 1 px orange eye and the light belly pixels that area resampling averages away, so `Look.region_of` still finds the eye / belly regions at 37x17 px. The importer box-downsamples with a hard alpha (no halo), snaps to one shared 30-colour palette, trims,
and pads so the **feet centroid is the canvas centre column** (the board puts bottom-centre on the tile, the ground shadow is drawn under it). `SpriteFactory.has_facing_art()` tells `BattleBoard` not to mirror a pose that has its own file;
other creatures keep the mirrored front / back sprites (pre-flipped texture cache). `portrait_<stage>.png` (HUD card, egg-peek head) are cut from pose A's head on the existing portrait background.
Customization (`Look.gd`, `data/customization.json` sprites with `"mode": "brown"`): pixels are classified into regions by colour - **body** (brown), **stripe** (navy dorsal stripe = the "crest": male dark, female paler),
**belly** (tan), and untouched **eye / outline / claws**. Skin colours re-hue body, stripe and belly keeping the art's shading; patterns are overlays masked to the body only; "Classic" keeps the original brown.
Replace any of these PNGs with your own (same names); keep the feet on the bottom row and centred.

### Ability cards (layered, from the designer card design)
`tools/art/supplied/card_sheet.jpg` is the reference (dark blue "night" card + light cream/orange "desert" card). `tools/art/art_card.py` redraws every layer as its own PNG (dark + light), so any one can be replaced
(same name and size): `card_frame_<v>` 27x27 (9-slice), `card_crest_<v>` 16x6 (top tab; the rarity gem is drawn live), `card_artwin_<v>` 11x11 (9-slice, border drawn over the illustration),
`card_banner_<v>` 32x13 (9-slice, the NAME scroll), `card_ribbon_<v>` 21x7 (9-slice, the thin TYPE ribbon), `card_textbox_<v>` 13x13 (9-slice, description), `card_tile_<v>` 9x9 and `card_slot_<v>` 9x9 (9-slice).
`CardView.gd` composes them (`CardView.layout()` has every rectangle for the 88x101 hand card with the illustration and the 144x184 big card) and renders everything variable **live in the Jersey font**:
name (on the banner), description (in the box, keyword colours darkened on the light frame), stamina cost (top number tile), card type (ribbon text on the big card, type-coloured bar + glyph tile on the hand card),
rarity (gem in the crest + gem tile), archetype tags (the two icon slots, tag colour pips, gold edge for a synergy). Attacks use the light frame, skills and powers the dark one; add `"frame": "dark"|"light"` to a card in `data/cards.json` to override.
The illustration is `assets/sprites/card_<id>.png` (61x36, one per ability, generated by `tools/art/art_ui.py` and baked by `tools/rebase_640.py`; drop in your own). Hand cards show its middle rows, big cards the whole picture at 1x.

## Unit readability: foliage fade + unit outline (`data/visibility.json`)
Background / border trees, bushes, foliage and ground decoration (the outer ring that frames the arena) used to hide the player and enemies. Now:
* **Border foliage over the board** - any ring sprite whose screen rect (shrunk by `overlap.shrink_*` so empty corners don't count) covers the core of a playable tile is drawn at `border_alpha` (0.42). It fades to `border_behind_alpha` (0.28) while a unit is behind it (the sprite sorts after the unit and their rects overlap). Sprites completely outside the arena stay opaque, so the environment still looks continuous. The overlap test is cached per sprite and rebuilt when the zoom changes; it works for every theme (jungle, tundra, cave), arena size and window size.
* **Obstacles on the board** (trees, rocks, logs that block tiles) keep their depth sorting and stay solid; only while a unit is directly behind one it fades to `obstacle_behind_alpha` (0.5). On-board decoration fades to `decor_behind_alpha` (0.45) the same way. Tall grass cover is untouched.
* **Tween** - alphas ease toward their target with `fade_speed` (exponential, about 0.12 s); a sprite starts at its target when the encounter loads, so there is no pop-in.
* **Unit contrast** - a 1px light outline (`unit_outline`: cream for the player, salmon for enemies, drawn as a cached silhouette behind the sprite; skipped for the death collapse) and a flat team-coloured foot ring (`unit_ring`: teal / red).
* All values (alphas, speed, margins, colours, on/off switches) are in `data/visibility.json`.
* Tests: `test_foliage_visibility` (3 themes x 3 arena sizes: overlap, alphas, unit behind / in front / beside, caching, tween, outline silhouette, README). Tour: `_foliage_demo` saves `screenshots/foliage/after_{jungle,tundra,cave}_{2560x1600,1280x720}.png` right after the arena loads; the matching `before_*.png` files show the old look.

## Art spec for designers: the 640x360 "Sea of Stars" pixel format (shipped re-base + final assessment)
**Status: DONE. The game now runs on a native 640x360 canvas** (see "Display scaling"): engine, board (32x16 tile), HUD and every screen are re-based; the supplied art was re-sampled with area resampling + cleanup (`tools/rebase_640.py`) and redrawn procedurally where it was marginal (small enemies, baby raptor, icons, card frames). The old-density sources are kept in `tools/art_src_960/` (git-ignored by Godot with a `.gdignore`), so the bake can be re-run: `python3 tools/rebase_640.py` (use `--snapshot` once to capture the sources), then `python3 tools/raptor_details.py` (eye / belly pixels), `python3 tools/hires_backdrops.py` (customize backdrop and egg at 1:1) and `python3 tools/rebase_cutscene.py` (cutscene JSON); `python3 tools/art_final_table.py` prints the table below.

**Canvas rules**
* Native canvas **640x360**, integer scale only: 720p = 2x, 1080p = 3x, 1440p = 4x (2560x1440; 2560x1600 = 4x with 80 px bars top and bottom), 4K = 6x. Bars (letterbox / pillarbox) fill the rest, pixels stay square. Settings: **Pixel Perfect** ON (default) = integer scale + bars, OFF = fill the window with fractional scaling.
* One pixel density: every element is drawn at 100% (or an integer multiple for hero art such as the title), never 150% or 66%. No rotated or fractionally scaled sprites; shadows / lighting are painted into the art or drawn as 1 px steps.
* Text: pixel font at native size, **Jersey 10** (body / cards), **Jersey 15** (headings), **Jersey 20** (titles); all three are in `assets/fonts/` (SIL OFL).
* Isometric tile **32x16** (2:1 diamond). A 14x14 arena is 448x224 px, leaving room for the HUD and the hand. Camera zoom snaps to whole levels 1x / 2x / 3x.

**HUD layout at 640x360** (native px): turn order top-left, character card top-right (portrait 43x43, HP bar 73x23, stamina / hunger bars 68x8), Move / End Turn bottom-right (86x20 stone-wood buttons), hand bottom-centre (5 cards of 88x101 = 440 px wide), pile counts and Deck button under the card.

**Target pixel sizes per asset (what is shipped now; author new art at these sizes)**
| asset | was (960x540 frame) | now / target (native px) | rule |
|---|---|---|---|
| ground tile | 76x38 | 32x16 | 5-8 colours, 1-2 px detail |
| tall grass / low props | 76x52..56 | 32x24 | 2 px blades |
| obstacle (tree, rock, log) | 51..99 x 48..160 | 32 wide x 22-48 tall (trees up to 43x73 on the border) | foot on the tile's lower corner |
| border trees / bushes / foliage | 50..103 x 50..153 | 21..43 wide | 3-4 value steps |
| pine sheet (@kianamosser) | 57-71 x 116-138 (sheet crop) | trees 22x44 / 29x53, stumps 12x8, fallen 49x21 | border trees (tall), board obstacles (short, stumps, fallen) |
| characters (raptor, 4 facings) | baby 48x22, adult 80x37, prime 86x41 | baby 28x13, juvenile 33x15, adult 37x17, prime 40x19 | same canvas for all 4 facings |
| small enemies | beetle 36x28, shrew 38x26, skink 50x24 | 24 px minimum width | min 12 px tall |
| medium / large enemies | 60x46 .. 112x92 | 27x21 .. 50x41 | |
| buttons (9-slice) | 37x21 | 25x14, 5 px caps | author 24x14 with 3 px corners |
| panels (9-slice) | 32x32 | 21x21 | author 24x24 with 3 px borders |
| HP bar frame / slim bars / fill | 110x34 / 102x12 / 24x5 | 73x23 / 68x8 / 16x3 | |
| cards (whole card) | 132x152 | 88x101 (zoom 144x184) | text Jersey 10 |
| card art | 92x54 | 61x36 | 56-colour palette |
| icons / item icons | 16x16 / 20x20 | 11x11 / 13x13 | drawn at 100% |
| portraits | 64x64 | 43x43 (HUD) | author 32x32 / 48x48 for a native look |
| egg / nest | 33x38 / 118x86 | 22x25 / 79x57 (hi-res scene 400x540 at 1:1) | |
| backgrounds, menu forest | 960x540 | 640x360, <= 48 colours | posterized; repaint natively to improve |

**Final sprite assessment** (generated by `python3 tools/art_final_table.py`: `native` = the old-density source (pines: the crop of the supplied sheet), `now` = the baked game sprite; soft-edge px = the semi-transparent shadow pixels).
* **Works:** ground / grass tiles, tall grass, obstacles, bushes, rocks, trees, the **pine sheet** (trees, stumps, fallen pines: clean at 22x44 .. 29x53, ideal for 640x360), adult / baby / juvenile / prime raptors (SE), mid and large enemies, small enemies at the 24 px minimum, card art and frames, bars, egg, nest, portraits, icons.
* **Marginal (usable, a native redraw is recommended):** logs (18x10), compy (face lost), raptor SW / NE / NW poses (thin tail and legs merge at 15 px), 9-slice panel corners.
* **Not pixel art (posterized, repaint recommended):** the 640x360 jungle / tundra / cave backdrops and the menu forest layers, and the 43x43 portraits.
* **Pines: native 61x116 (short) / 71x138 (tall) in the sheet -> 22x44 / 29x53 on the board, so they work for 640x360** (tall pines are border trees only; short pines, stumps and fallen pines stand on the board). Artist credit: **@kianamosser**.


| asset | file | native (old density) | now (native px) | designer target | colours now | soft-edge px | verdict at 640x360 | designer note |
|---|---|---|---|---|---|---|---|---|
| ground tile (jungle) | tile_jungle_ground_0 | 76x38 | 32x16 | 32x16 | 22 | 0% | Works | Clean diamond; keep 5-8 colours and 1-2 px detail. |
| ground tile (tundra) | tile_tundra_ground_0 | 76x38 | 32x16 | 32x16 | 23 | 0% | Works | Low contrast: add 2-3 darker ice-crack pixels per tile. |
| ground tile (cave) | tile_cave_ground_0 | 76x38 | 32x16 | 32x16 | 25 | 0% | Works | 1 px teal sparkles survive. |
| tall grass (jungle) | prop_jungle_tallgrass_0 | 76x56 | 32x24 | 32x24 | 38 | 3% | Works | Leaf shapes survive; a redraw with 2 px blades would be crisper. |
| obstacle (rock + ferns) | prop_jungle_obstacle_0 | 81x89 | 34x37 | 32x32 | 32 | 7% | Works | Reads well. |
| obstacle (tundra) | prop_tundra_obstacle_0 | 76x64 | 32x27 | 32x27 | 27 | 0% | Works | Needs a 1 px lighter rim on the dark underside. |
| obstacle (cave) | prop_cave_obstacle_0 | 76x64 | 32x27 | 32x27 | 35 | 0% | Works | Teal veins become 1 px lines, fine. |
| border tree | deco_tree_01 | 103x153 | 43x64 | 43x64 | 40 | 7% | Works | Border only: too tall to stand on the board. |
| bush / foliage | foliage_05 | 50x50 | 21x21 | 21x21 | 15 | 0% | Works | Good border bush size. |
| log | log_01 | 43x23 | 18x10 | 20x10 | 13 | 0% | Marginal | Loses bark detail at 18x10: redraw with 3 colours. |
| pine tree (short, @kianamosser) | tree_pine_01 | 61x116 (sheet crop) | 22x44 | 22x44 | 27 | 2% | Works | Downscaled ~2.6x from the sheet and still clean: a ready-made jungle / tundra border tree; a native redraw would be crisper. |
| pine tree (tall, @kianamosser) | tree_pine_02 | 71x138 (sheet crop) | 29x53 | 29x53 | 34 | 1% | Works | Border only (tall); the tallest at 53 px is 15% of the screen height. |
| pine tree (short, @kianamosser) | tree_pine_03 | 57x116 (sheet crop) | 23x44 | 23x44 | 37 | 2% | Works | Also used 0.8x as a board sapling (18x41). |
| pine tree (tall, @kianamosser) | tree_pine_04 | 72x138 (sheet crop) | 28x53 | 28x53 | 38 | 1% | Works | Border only. |
| pine stump (@kianamosser) | stump_pine_01 | 37x30 (sheet crop) | 12x8 | 12x8 | 10 | 8% | Works | Tiny but readable as a 12x8 obstacle; fine on the board. |
| fallen pine (@kianamosser) | fallen_pine_01 | 124x60 (sheet crop) | 49x21 | 49x21 | 31 | 0% | Works | Reads as a log across 1.5 tiles; board obstacle and decor. |
| raptor adult SE | raptor_adult | 80x37 | 37x17 | 37x17 | 36 | 0% | Works | Eye + belly pixels restored by tools/raptor_details.py so recolouring still works. |
| raptor adult SW | raptor_adult_sw | 68x32 | 31x15 | 32x15 | 29 | 0% | Marginal | Legs and tail merge a little; redraw recommended. |
| raptor adult NE | raptor_adult_b | 80x35 | 37x16 | 34x15 | 35 | 0% | Marginal | Back view loses the crest; redraw recommended. |
| raptor adult NW | raptor_adult_nw | 78x36 | 36x17 | 33x15 | 30 | 0% | Marginal | As NE. |
| raptor baby SE | raptor_baby | 48x22 | 28x13 | 28x13 | 26 | 0% | Works | Enlarged from true scale (20x9 was a smudge); bigger head. |
| raptor juvenile SE | raptor_juvenile | 64x30 | 33x15 | 33x15 | 34 | 0% | Works |  |
| raptor prime SE | raptor_prime | 86x41 | 40x19 | 40x19 | 33 | 0% | Works |  |
| beetle | beetle | 36x28 | 24x19 | 24x19 | 15 | 0% | Works | Enlarged to a 24 px minimum so it stays a beetle, not a blob. |
| compy | compy | 60x46 | 27x21 | 30x23 | 27 | 0% | Marginal | Reads as a dino; the face is lost, redraw recommended. |
| smilodon | smilodon | 80x58 | 36x26 | 34x24 | 33 | 0% | Works | Stripes survive. |
| husk queen | husk_queen | 112x92 | 50x41 | 50x41 | 34 | 0% | Works | Glow spots stay as clean 2 px dots. |
| infected mammoth | infected_mammoth | 104x88 | 47x40 | 44x37 | 34 | 0% | Works |  |
| button (9-slice) | ui_btn | 37x21 | 25x14 | 25x14, 5 px caps | 43 | 0% | Works | Authored size would be 24x14 with 3 px corners. |
| panel (9-slice) | ui_panel | 32x32 | 21x21 | 24x24 | 47 | 0% | Works with care | Non-integer corner widths. |
| HP bar frame | ui_bar_frame | 110x34 | 73x23 | 72x22 | 48 | 0% | Works |  |
| slim bar | ui_bar_slim | 102x12 | 68x8 | 68x8 | 38 | 0% | Works | Fill 16x3. |
| card art | card_claw_slash | 92x54 | 61x36 | 61x36 | 32 | 0% | Works | Painterly; survives a 56-colour palette. |
| card frame (9-slice) | card_frame_dark | 40x40 | 27x27 | 24x24, 3 px | 6 | 0% | Works |  |
| icon | icon_move | 16x16 | 11x11 | 11x11 (10x10) | 7 | 0% | Works | Redrawn at 11x11, drawn at 100%. |
| item icon | item_apex_heart | 20x20 | 13x13 | 13x13 | 10 | 0% | Works | Redrawn at 13x13. |
| portrait | portrait_adult | 64x64 | 43x43 | 43x43 | 353 | 0% | Works | Hi-res: author 32x32 (HUD) and 48x48 (customize) for a native look. |
| egg | egg_raptor | 33x38 | 22x25 | 22x25 | 46 | 0% | Works | Customize screen uses the hi-res egg_raptor_hi (1:1). |
| nest | bg_egg_nest | 118x86 | 79x57 | 79x57 | 48 | 14% | Works |  |
| backdrop | bg_jungle_0 | 960x540 | 640x360 | 640x360 | 48 | 0% | Works, not pixel art | Posterized to 48 colours; a native repaint would be better. |


## Camera zoom-out limit (`data/arenas.json` -> `camera.zoom_out_margin`)
The mouse wheel / zoom keys can no longer zoom out past the size at which the **whole tile board plus a margin of `zoom_out_margin` (0.12 = 12%)** fits the view.
`Iso.min_zoom(w, h)` takes the largest zoom step whose board (w x h diamond, scaled by 1 + margin) fits the camera view band (`camera.view` = `[20, 14, 600, 280]` on the 640x360 canvas),
so it is computed **per arena** and recomputed on every refit (`BattleBoard.refit`). Zoom steps are whole numbers (`[3, 2, 1]`) so the pixel art never shears; a zoom below the minimum snaps straight to it
(`ZOOM_EASE` is 0: there is no easing between whole-number zooms). The canvas is fixed at 640x360, so the limit does not depend on the window size. Test: `test_zoom_limit` (every arena, wheel clamping, snap).


## Battle HUD without backing panels
The player stats (top right: portrait, health / stamina / hunger bars) and the Move / End Turn buttons (bottom right) no longer have a blue frame behind them: the bars and
the stone-wood buttons sit straight over the board. `PlayerCard` is an invisible layout box; their text (name, status, level, draw/discard counts, Moves Left, "Click tile = turn")
uses a soft drop shadow + hairline outline (`UITheme.shadow`). The hover-info box under the card, the turn-order strip and the log keep their dark panels (they hold running text).
Layout / overlap checks run on the 640x360 canvas (the HUD-layout loop in `test_settings`, `test_hud_no_panels`); the tour and gallery screenshots are composed at 1280x720, 1920x1080, 2560x1600 and 3840x2160.
