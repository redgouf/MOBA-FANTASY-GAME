# Gielinor Legends

A free, fan-made 5v5 three-lane MOBA where every champion is an **Old School RuneScape gear build**: Full Dharok's, the 1 Defence Pure, Ahrim's + Ancients, the Range/Mage Hybrid, and more. Items are real OSRS gear with their real skill requirements, every ultimate is a special attack, and the map is a Saradomin-vs-Zamorak battlefield split by the Wilderness Ditch.

> **Fan project.** Gielinor Legends is 100% free and non-commercial, made to celebrate Jagex's work. Old School RuneScape and RuneScape are trademarks of Jagex Ltd. This project is not affiliated with or endorsed by Jagex, and it will never be sold or monetized.

Built with **Godot 4.7.2** (GDScript, Forward+).

## Status: whitebox prototype (v0.4)

![Playing the Pure: stats and items bottom-left, abilities centre, minimap bottom-right, inspected target top-left](docs/screenshots/play.png)

Playable today, with primitive shapes standing in for art:

- **5v5**: play one champion with 4 bot allies, or **watch NPC vs NPC** in spectator mode.
- **League-style HUD**: portrait, stats, 6 item slots and food belt bottom-left; passive, Q/W/E/R with ranks and cooldowns, prayers and bars in the centre; minimap bottom-right; left-click any unit to inspect it top-left (with a ring under its feet).
- **League of Legends mob and structure stats**: minions, turrets, altars (inhibitors), the standard (nexus) and every jungle camp use Summoner's Rift numbers, wave timings and turret rules. See [docs/LOL_VALUES.md](docs/LOL_VALUES.md).
- **OSRS Skills tab** ([screenshot](docs/screenshots/champion_select.png); the Skiller gets the [full 24-skill tab](docs/screenshots/skiller_skills.png)) for every build (Attack, Hitpoints, Strength, Defence, Ranged, Prayer, Magic, total and combat level) on champion select, and on hover over your portrait or the inspect panel's portrait in-game. Hover a skill to see which items that level unlocks.
- **League-style leveling**: start with nothing learned and one point; one point per level; basic abilities rank up to 5 (rank n at level 2n−1), R unlocks at 6/11/16.

- **The Wilderness Rift**: three lanes, the Ditch (visual only), four jungle quadrants, Jad and dragon pits, towers, altars and team flags with LoL-style destruction order, and a runtime-baked navmesh.
- **11 champions** with full data-driven kits (passive + Q/W/E/R), OSRS skill levels, and lane bots, including the **level-3 Skiller** ([in action](docs/screenshots/skiller_kit.png)), who never swings a weapon: a felled yew (Timber!), a Bonfire, a Harpoon and an Anvil Drop do the damage, and every 4th ability sets off level-up fireworks.
- **Combat**: melee/ranged/magic triangle, three resists, tick-based attack speed, special attack energy powering ultimates *and* spec-weapon items, overheads only on tank/main builds, offensive prayers set by Prayer level (Piety at 70, Chivalry at 60, ...).
- **Shop**: 70+ OSRS items with real requirements (a 1 Defence Pure can't wear Bandos), build paths, spec actives (Dragon claws, AGS, Voidwaker...), and a food/potion belt.
- **Minion waves** (goblins, dark wizards, dwarf cannon carts), jungle camps with buffs, TzTok-Jad (telegraphs his next style), and the Giant Mole before 14:00.

## Running it

**Without Godot:** run a Windows build (`GielinorLegends.exe`, everything embedded). Windows SmartScreen may warn because the file isn't code-signed: choose *More info* > *Run anyway*.

**From source:**

1. Install [Godot 4.7.2](https://godotengine.org/download/) (standard build, not .NET).
2. Open this folder as a project and press **F5**.
3. Pick a build on the champion select screen.

Skip champion select from the command line:

```bash
godot --path . -- --champion=pure
```

### Controls

| Key | Action |
| --- | --- |
| Right-click | Move, or attack the unit under the cursor |
| Left-click | Select a unit to inspect it (top-left panel + ring under its feet) |
| Q W E R | Abilities, aimed at the cursor (R is your special attack) |
| Ctrl + Q W E R / the + buttons | Spend a skill point |
| 1 – 6 | Item spec actives (Dragon claws, AGS, ...) |
| 7 8 9 0 | Food and potions |
| Z X C | Protect from Melee / Missiles / Magic (tank and main builds only) |
| V | Best offensive prayer your Prayer level allows |
| B | Teleport home |
| P | Grand Exchange (shop; buy at base) |
| S | Stop |
| Middle-mouse drag | Grab the map and pan freely |
| Minimap | Left-click/drag to look, right-click to walk |
| Space / Y | Centre camera / lock camera |
| Arrows, screen edge, wheel | Pan and zoom |
| Esc | Close the shop, or open the menu (Resume, Settings, Controls, Restart, Watch bots, Change champion, Quit) |

### Spectator mode (NPC vs NPC)

Pick **Watch NPC vs NPC** on champion select or in the Esc menu (or run `godot --path . -- --spectate`). All 10 champions are bots.

![Spectating Dharok: rosters on both sides, his cooldowns and items, and his ghost cursor attacking a minion](docs/screenshots/spectate.png)

| Input | Action |
| --- | --- |
| Left-click a champion, its roster card, or press 1–5 / 6–0 | Lock onto it: the HUD shows its abilities, cooldowns, items and stats, the camera follows it, and the top-left panel shows its current target |
| Ghost cursor | Shows where the locked-on bot is clicking: green = move, red = attack, blue = ability (labelled Q/W/E/R or the item) |
| Y | Toggle the camera lock (pan freely with middle-mouse, edges or the minimap) |
| Left-click anything else | Inspect it |

Bindings are registered in `scripts/autoload/controls.gd` and can be overridden in Project Settings > Input Map.

## Tests

```bash
# Unit and kit tests (combat math, requirements, prayers, every ability of every champion)
godot --headless --path . res://tests/test_runner.tscn

# Self-play smoke test: 5v5 bots, waves, towers and camps for 4 game minutes
godot --headless --path . --fixed-fps 60 -- --smoke-test --smoke-seconds=240
```

CI runs both on every push (`.github/workflows/ci.yml`).

## Building the Windows .exe

With Godot 4.7.2 and its export templates installed (Editor > Manage Export Templates):

```bash
godot --headless --path . --export-release "Windows Desktop" build/windows/GielinorLegends.exe
```

The preset in `export_presets.cfg` embeds the game into the .exe, packs `data/*.json` and leaves out `tests/`. The `build/` folder is git-ignored.

## Project layout

```
data/            All tunable game data (JSON) — champions, items, units, rules
scenes/          main.tscn (everything else is built in code for now)
scripts/
  autoload/      GameData (loads JSON), Controls (input map)
  core/          Combat math, DamageInfo
  units/         Unit base class, Champion, Minion, Structure, Monster, visuals
  abilities/     AbilityRunner: executes data-driven ability effects
  map/           MapLayout (coordinates), MapBuilder (geometry + navmesh)
  game/          Main (match flow), WaveSpawner, CameraRig, PlayerController
  ui/            Hud, ChampionSelect
tests/           Headless test runner
docs/            Design and developer docs
```

## Docs

- [docs/DESIGN.md](docs/DESIGN.md): game design summary and key decisions
- [docs/ABILITIES.md](docs/ABILITIES.md): how to write champion kits and item specs in JSON
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the code fits together, and the roadmap
- [docs/LOL_VALUES.md](docs/LOL_VALUES.md): the League of Legends numbers used for minions, turrets and jungle, with sources

## Contributing

Most balance and content work is JSON-only: add a champion to `data/champions.json` or an item to `data/items.json`, then run the tests. Please verify item requirements against the [OSRS Wiki](https://oldschool.runescape.wiki/) and mark unverified ones with `"verify": true`.
