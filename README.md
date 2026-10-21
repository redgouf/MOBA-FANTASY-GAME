# Gielinor Legends

A free, fan-made 5v5 three-lane MOBA where every champion is an **Old School RuneScape gear build**: Full Dharok's, the 1 Defence Pure, Ahrim's + Ancients, the Range/Mage Hybrid, and more. Items are real OSRS gear with their real skill requirements, every ultimate is a special attack, and the map is a Saradomin-vs-Zamorak battlefield split by the Wilderness Ditch.

> **Fan project.** Gielinor Legends is 100% free and non-commercial, made to celebrate Jagex's work. Old School RuneScape and RuneScape are trademarks of Jagex Ltd. This project is not affiliated with or endorsed by Jagex, and it will never be sold or monetized.

Built with **Godot 4.7.2** (GDScript, Forward+).

## Status: whitebox prototype (v0.1)

Playable today, with primitive shapes standing in for art:

- **The Wilderness Rift**: three lanes, the Ditch (visual only), four jungle quadrants, Jad and dragon pits, towers, altars and team flags with LoL-style destruction order, and a runtime-baked navmesh.
- **10 champions** with full data-driven kits (passive + Q/W/E/R), OSRS skill levels, and lane bots.
- **Combat**: melee/ranged/magic triangle, three resists, tick-based attack speed, special attack energy powering ultimates *and* spec-weapon items, overheads only on tank/main builds, offensive prayers set by Prayer level (Piety at 70, Chivalry at 60, ...).
- **Shop**: 70+ OSRS items with real requirements (a 1 Defence Pure can't wear Bandos), build paths, spec actives (Dragon claws, AGS, Voidwaker...), and a food/potion belt.
- **Minion waves** (goblins, dark wizards, dwarf cannon carts), jungle camps with buffs, TzTok-Jad (telegraphs his next style), and the Giant Mole before 14:00.

## Running it

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
| Q W E R | Abilities, aimed at the cursor (R is your special attack) |
| 1 – 6 | Item spec actives (Dragon claws, AGS, ...) |
| 7 8 9 0 | Food and potions |
| Z X C | Protect from Melee / Missiles / Magic (tank and main builds only) |
| V | Best offensive prayer your Prayer level allows |
| B | Teleport home |
| P | Grand Exchange (shop; buy at base) |
| S | Stop |
| Space / Y | Centre camera / lock camera |
| Arrows, screen edge, wheel | Pan and zoom |

Bindings are registered in `scripts/autoload/controls.gd` and can be overridden in Project Settings > Input Map.

## Tests

```bash
# Unit and kit tests (combat math, requirements, prayers, every ability of every champion)
godot --headless --path . res://tests/test_runner.tscn

# Self-play smoke test: four bots, waves, towers and camps for 4 game minutes
godot --headless --path . --fixed-fps 60 -- --smoke-test --smoke-seconds=240
```

CI runs both on every push (`.github/workflows/ci.yml`).

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

## Contributing

Most balance and content work is JSON-only: add a champion to `data/champions.json` or an item to `data/items.json`, then run the tests. Please verify item requirements against the [OSRS Wiki](https://oldschool.runescape.wiki/) and mark unverified ones with `"verify": true`.
