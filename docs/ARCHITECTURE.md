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

## Navigation and obstacles

- `MapBuilder` bakes the navmesh on a worker thread from static colliders (walls + ground) under its `NavigationRegion3D`.
- Timber! yews (`PlantedTree`) are `StaticBody3D`s on the walls layer, parented to that region; planting or felling one calls `MapBuilder.request_rebake()` (requests during a bake are merged into one follow-up bake, ~50–100 ms off-thread).
- Champions re-query their path whenever the navigation map's iteration changes (a rebake), and when pressed against something for 0.75 s.
- `MapBuilder` runs a watchdog: if the navigation server ends up with the region but no polygons (rare startup race that left every bot standing still), it resubmits the mesh.
- Minions and monsters walk straight lines; `Unit.steer_around_trees()` bends them around yews, and if they stop making progress they side-step along the wall and follow a short navmesh detour.
- Moving units collide with walls using a body no wider than 0.45 m (`Unit.MAX_WALL_COLLISION_RADIUS`), slimmer than the 0.5 m navmesh agent, so bulky units can't snag on corners the path cuts.
- The smoke test reports `stuck bots` (alive, away from base, not moving 1 m in 45 s).

## Models and effects

- `CombatFx` draws attack and ability effects; `Projectile` carries ranged and magic damage and is shaped by the attacker's `attack_fx`.
- `OsrsModels` and `OsrsActor` add the optional private OSRS models (see [OSRS_MODELS.md](OSRS_MODELS.md)). `Unit.attach_osrs()` hides the whitebox shape; `Unit._attack_visuals()` and `Champion._cast_visuals()` drive animations and effects.

## UI

- `Hud` lays everything out with `UiStyle.place()` (anchor preset + offset), so it holds at any window size; the project uses `canvas_items` stretch from a 1600x900 base.
- `Hud.set_champion()` switches whose perspective is shown; spectator mode uses it to lock onto bots.
- Champions emit `command_issued(kind, point, label)` for every order; `GhostCursor` draws it.
- `Settings` (autoload) saves to `user://settings.cfg`; `Combat.clock` is the pausable game clock.
- `PlayerController` handles cast modes (`Settings.cast_mode`: quick cast with indicator, normal cast, quick cast) and draws `AbilityIndicator` (range ring, line/cone/circle/dash shapes, Timber!'s plant spot or fall path) while aiming.
- `AbilityInfo` builds ability tooltips with the live damage breakdown (spell at its rank + your stats + items = total).
- `MatchScoreboard` (hold Tab) remembers enemies' items from when your team last saw them (within 16 m of any allied unit).
- `UiStyle.install_tooltip_theme()` gives every tooltip a solid panel; `UiStyle.wrap()` breaks tooltip text into short lines.
- `Icons` loads OSRS item and prayer icons from `assets/icons` (from [Dava96/osrs-icons](https://github.com/Dava96/osrs-icons), CC BY-NC-SA 3.0; only the icons the game uses are included, listed in `assets/icons/SOURCE.json`).
- Visual checks: `--screenshot=PATH --screenshot-at=SECONDS [--shot-ui=target|menu|settings|controls|shop|kit|skills|aim-chop|aim-plant|scoreboard|tooltip] [--demo-level=N]` renders a PNG and quits (works under Xvfb with `--rendering-method gl_compatibility`).

## Conventions

- Map units are metres; screen-up is −Z. Saradomin is team 0 (bottom-left), Zamorak team 1.
- Physics layers: 1 walls, 2 units, 3 ground. Units collide only with walls.
- Everything visual is primitive meshes for now; swapping in models means replacing `Unit.setup_visuals()`.
- New content should be data first (JSON) and code only for genuinely new mechanics.

## Roadmap

**Next — feel**
- Low-poly OSRS-style models and animations, hitsplat polish, ability VFX
- Fog of war (the scoreboard already tracks what each team has seen), brush (evergreen tree clusters)
- Smarter bots: jungling, tower-dive avoidance, objective fights
- Armour set bonuses and the "planned" item effects (scythe arcs, recoil, venator bounces)
- Bots that jungle and contest Jad/dragons; dragon souls and Vorkath

**Then — depth**
- Role-based bots; spellbook (summoner) spells
- Giant Mole tower-burrow behaviour; Fire cape empowered minions
- Prayer drain from Smite, Rune pouch for the Lunar

**Then — multiplayer**
- Server-authoritative netcode with Godot's high-level multiplayer (ENet), lobby and champion draft

**Later**
- More builds (Guthan's, Verac's, Karil's, Void Knight, F2P Rune PKer)
- Map skins (Lumbridge, Varrock, Ardougne), Castle Wars 3v3, Last Man Standing
