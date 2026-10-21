# Architecture

## Flow

1. `GameData` (autoload) loads `data/*.json` and configures `Combat`.
2. `scenes/main.tscn` runs `scripts/game/main.gd`, which builds the map (`MapBuilder`), shows `ChampionSelect`, then `start_match()` (you + 4 bots vs 5 bots, `PlayerController`) or `start_spectate()` (10 bots, `SpectatorController`) spawns structures, camps, champions, the `WaveSpawner`, camera, HUD and `PauseMenu`.
3. Every fighter is a `Unit` (`CharacterBody3D`). Subclasses add behaviour in `_unit_process()`:
   - `Champion`: player input or bot AI, navmesh pathing, abilities, items, prayer, spec energy, leveling
   - `Minion`: walks its lane, fights the nearest enemy
   - `Structure`: towers (LoL-style targeting), altars, flags, and timed summons (dwarf multicannon)
   - `Monster`: neutral camps and epics with leash and reset
4. Damage always goes through `Unit.take_damage(DamageInfo)` → `Combat.mitigate()` (triangle, resists, protection prayer) → status modifiers → passive hooks.
5. `Main` listens to every `died` signal and pays gold, XP, buffs, and checks the win condition.

## UI

- `Hud` lays everything out with `UiStyle.place()` (anchor preset + offset), so it holds at any window size; the project uses `canvas_items` stretch from a 1600x900 base.
- `Hud.set_champion()` switches whose perspective is shown; spectator mode uses it to lock onto bots.
- Champions emit `command_issued(kind, point, label)` for every order; `GhostCursor` draws it.
- `Settings` (autoload) saves to `user://settings.cfg`; `Combat.clock` is the pausable game clock.
- Visual checks: `--screenshot=PATH --screenshot-at=SECONDS [--shot-ui=target|menu|settings|controls|shop] [--demo-level=N]` renders a PNG and quits (works under Xvfb with `--rendering-method gl_compatibility`).

## Conventions

- Map units are metres; screen-up is −Z. Saradomin is team 0 (bottom-left), Zamorak team 1.
- Physics layers: 1 walls, 2 units, 3 ground. Units collide only with walls.
- Everything visual is primitive meshes for now; swapping in models means replacing `Unit.setup_visuals()`.
- New content should be data first (JSON) and code only for genuinely new mechanics.

## Roadmap

**v0.3 — feel**
- Low-poly OSRS-style models and animations, hitsplat polish, ability VFX
- Fog of war, brush (evergreen tree clusters)
- Smarter bots: jungling, tower-dive avoidance, objective fights
- Armour set bonuses and the "planned" item effects (scythe arcs, recoil, venator bounces)
- Bots that jungle and contest Jad/dragons; dragon souls and Vorkath

**v0.4 — depth**
- Role-based bots; spellbook (summoner) spells
- Giant Mole tower-burrow behaviour; Fire cape empowered minions
- Prayer drain from Smite, Rune pouch for the Lunar

**v0.5 — multiplayer**
- Server-authoritative netcode with Godot's high-level multiplayer (ENet), lobby and champion draft

**Later**
- More builds (Guthan's, Verac's, Karil's, Void Knight, F2P Rune PKer, Skiller)
- Map skins (Lumbridge, Varrock, Ardougne), Castle Wars 3v3, Last Man Standing
