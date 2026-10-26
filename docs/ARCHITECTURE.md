# Architecture

## Flow

1. `GameData` (autoload) loads `data/*.json` and configures `Combat`.
2. `scenes/main.tscn` runs `scripts/game/main.gd`, which builds the map (`MapBuilder`), shows `ChampionSelect`, then `start_match()` (you + 4 bots vs 5 bots, `PlayerController`) or `start_spectate()` (10 bots, `SpectatorController`) spawns structures, camps, champions, the `WaveSpawner`, camera, HUD and `PauseMenu`.
3. Every fighter is a `Unit` (`CharacterBody3D`). Subclasses add per-tick behaviour in `_unit_tick()` and per-frame movement in `_unit_process()` (see [Game ticks](#game-ticks)):
   - `Champion`: player input or bot AI, navmesh pathing, abilities, items, prayer, spec energy, leveling
   - `Minion`: walks its lane, fights the nearest enemy
   - `Structure`: towers (LoL-style targeting), altars, flags, and timed summons (dwarf multicannon, drawn by `CannonModel`)
   - `Monster`: neutral camps and epics with leash and reset
4. Damage always goes through `Unit.take_damage(DamageInfo)` → `Combat.mitigate()` (triangle, resists, protection prayer) → status modifiers → passive and prayer hooks (`modify_incoming`), then `on_damage_dealt` on the attacker (Smite) and a `Hitsplat`.
   Basic attacks swing every `attack_ticks` × 0.6s and deal `damage × basic_hit_scale`.
5. `Main` listens to every `died` signal and pays gold, XP, buffs, and checks the win condition.

## Game ticks

The OSRS game tick (0.6 s, `data/rules.json` → `tick_seconds`) runs **auto attacks, eating and drinking**, plus the game's own clockwork: regen and prayer drain, respawns, the recall and altar channels, bot decisions, waves and camps. Everything the player does directly is real time: movement, attack and move orders, casting (spells hit the moment they're cast), ability cooldowns, status effects, prayers and level-ups.

- `scripts/autoload/game_tick.gd` is the `GameTick` autoload, the clock. It pauses with the game; `Main._begin()` resets it at match start. After a hitch it runs at most 5 ticks in one frame and drops the rest.
- `Unit.game_tick()` → `_unit_tick()` / `_dead_tick()` hold per-tick gameplay. `_physics_process()` runs every frame: `_frame_timers()` (ability cooldowns), `_tick_statuses()` (status durations, damage over time once a second) and `_unit_process()` (movement, and queued casts that go off as soon as the caster is in range).
- `PlayerController.order()` carries out orders at once; `order_on_tick()` (`GameTick.queue_input()`) is only used for food and potions.
- `GameTick.schedule(ticks, fn)` handles ranged auto-attack hit delays. Ability `delay`, `repeat_interval` and `hit_interval` are real seconds (`create_timer`).
- `GameTick.register_world(obj)` registers world tickables (objects with `game_tick(dt)`): `WaveSpawner`, `PlantedTree`, and `Main` (camp respawns and passive gold).

Order within one tick: queued input (food and potions), then scheduled actions (ranged hits), then NPCs (every `Unit` that isn't a `Champion`), then champions, then world tickables.

Rules:

- **Auto attacks**: the attack timer counts down 0.6 s per tick and swings land on ticks. A 4-tick whip hits on ticks 1, 5, 9. Attack-speed bonuses carry the leftover of a tick into the next swing, so +25% on a 4-tick weapon averages 3.2 ticks.
- **Ranged/magic auto attacks**: the hit lands `projectile_hit_ticks()` ticks after the swing: the flight time rounded up, at least 1 tick. The projectile (`Projectile.arrive_in()`) is timed to arrive on that tick.
- **Channels and respawns** count from the tick after they start: 1.2 s altar channel = 2 ticks, 8 s recall = 14, 45 s altar cooldown = 75.
- **Prayer**: switching on or off is instant. A prayer's first tick is free (the tick it came on, or the next one if it was clicked between ticks), so flicking every tick costs nothing. Drain is taken once per tick.
- **Bots** decide once per tick (every 0.6 s).

`test_game_tick()` in `tests/test_runner.gd` drives the clock by hand (`GameTick.run_tick()`) and checks input order, scheduling, NPC-before-champion order, attack ticks and speed carry-over, ranged hit delay, spells hitting on cast, real-time cooldowns and statuses, food on the tick, recall ticks, and prayer activation, drain and flicking.

## Navigation and obstacles

- `MapBuilder` bakes the navmesh on a worker thread from static colliders (walls + ground) under its `NavigationRegion3D`.
- Timber! yews (`PlantedTree`) are `StaticBody3D`s on the walls layer, parented to that region; planting or felling one calls `MapBuilder.request_rebake()` (requests during a bake are merged into one follow-up bake, ~50–100 ms off-thread).
- Champions re-query their path whenever the navigation map's iteration changes (a rebake), and when pressed against something for 0.75 s.
- `MapBuilder` runs a watchdog: if the navigation server ends up with the region but no polygons (rare startup race that left every bot standing still), it resubmits the mesh.
- Minions and monsters walk straight lines; `Unit.steer_around_trees()` bends them around yews, and if they stop making progress they side-step along the wall and follow a short navmesh detour.
- Moving units collide with walls using a body no wider than 0.45 m (`Unit.MAX_WALL_COLLISION_RADIUS`), slimmer than the 0.5 m navmesh agent, so bulky units can't snag on corners the path cuts.
- The smoke test reports `stuck bots` (alive, away from base, not moving 1 m in 45 s).

## Prayer

- `PrayerBook` (static) reads `rules.json` → `prayers`: default picks, what each one does, OSRS drain math, tooltip text.
- `Champion` holds `chosen_prayer`, `active_prayers` and the summed effects; `_tick_prayer()` drains points. Effects hook into `modify_outgoing` / `modify_incoming`, `extra_attack_speed()`, `debuff_decay_mult()` (Rapid Restore), `on_damage_dealt()` (Smite), `_on_damaged` (Redemption) and `_on_death` (Retribution).
- `PrayerAltar` (map, walls layer, baked into the navmesh) is prayed at through `Champion.command_pray()`; `PrayerBookPanel` is the champion-select picker.

## Fog of war

- `FogOfWar` (created by `Main` for the viewer's team) recomputes vision 10 times a second: allied units with a sight radius reveal enemies within it and in line of sight (a ray against the walls layer). Hidden units get `Unit.set_fog_hidden(true)`, which moves every visual child to a render layer the main camera skips; picking, the minimap, hitsplats, the selection ring and the inspect panel skip them. A 64x64 vision image drives a darkening plane over the ground and the minimap overlay.

## Crowd spacing

- `Crowd.solve()` runs once per physics frame from `Main`: a 3 m grid finds overlapping units, and each gets a `crowd_push` that `Unit` applies with `move_and_collide()` (walls still block).

## Models and effects

- `CombatFx` draws attack and ability effects; `Projectile` carries ranged and magic damage and is shaped by the attacker's `attack_fx`.
- `OsrsModels` and `OsrsActor` add the optional private OSRS models (see [OSRS_MODELS.md](OSRS_MODELS.md)); `OsrsMap` loads OSRS map squares from the same pack, `OsrsProps` builds buildings and props from its objects, and `MapBuilder` lays the OSRS-dressed Rift over the whitebox map. `tools/osrs_extract` builds the pack from the game cache. `Unit.attach_osrs()` hides the whitebox shape; `Unit._attack_visuals()` and `Champion._cast_visuals()` drive animations and effects.

## UI

- `UnitBars` (a CanvasLayer under the HUD, made in `Main._begin`) draws every unit's health bar and name flat on the screen at a fixed pixel size: champions get a framed bar with a level badge, health ticks every `rules.health_bar_tick` (50), the prayer bar and the overhead prayer icon; minions get a thin bar. The old 3D `HealthBar3D` and name `Label3D` still exist on each unit (hidden) so tests and code can read them.
- `AbilityTooltip` builds the hotbar tooltip from `AbilityInfo.tooltip_data()`: header (icon, [KEY] name, rank, cooldown, spec cost), body (description and each damage or heal written out), rank table. `UiStyle.install_tooltip_theme()` gives every other tooltip the same dark teal panel.
- `GrandExchange` is the shop (tabs, item grid, detail panel); it updates prices and colours in place every 0.25 s instead of rebuilding, so tooltips stay up. `BuffBar` shows statuses as icons with clock-wipe timers. `AbilityInfo.tooltip_rich()` (coloured BBCode) is the hotbar's tooltip text; `AbilitySlot._make_custom_tooltip()` shows the structured `AbilityTooltip` instead.

- `ChampionSelect` is a fixed 1600x900 layout built from `OsrsUi` pieces (generated stone panels, recessed slots, stone buttons, OSRS text colours). `FigureView` is a small 3D stage (its own world, camera and lights) showing a `ChampionFigure`: the champion's OSRS model when the private pack is installed, otherwise a stand-in figure coloured from its equipment icons. One hidden `FigureView` photographs every portrait at startup; another shows the selected build turning left and right. LOCK IN emits `champion_selected(id, prayer)` after 5 s.
- `GameData.roll_skills()` rolls every build's non-combat levels; champion select rolls them when it opens, and `GameData.ensure_match_rolls()` keeps those for the match (a restart rolls new ones). `Champion.skills` comes from `GameData.skills_for()`.

- `Hud` lays everything out with `UiStyle.place()` (anchor preset + offset), so it holds at any window size; the project uses `canvas_items` stretch from a 1600x900 base.
- `Hud.set_champion()` switches whose perspective is shown; spectator mode uses it to lock onto bots.
- Champions emit `command_issued(kind, point, label)` for every order; `GhostCursor` draws it.
- `Settings` (autoload) saves to `user://settings.cfg`; `Combat.clock` is the pausable game clock.
- `PlayerController` handles cast modes (`Settings.cast_mode`: quick cast with indicator, normal cast, quick cast) and draws `AbilityIndicator` (range ring, line/cone/circle/dash shapes, Timber!'s plant spot or fall path) while aiming.
- `AbilityInfo` builds ability tooltips with the live damage breakdown (spell at its rank + your stats + items = total).
- `MatchScoreboard` (hold Tab) remembers enemies' items from when your team last saw them (within 16 m of any allied unit).
- `UiStyle.install_tooltip_theme()` gives every tooltip a solid panel; `UiStyle.wrap()` breaks tooltip text into short lines.
- `Icons` loads OSRS item and prayer icons from `assets/icons` (from [Dava96/osrs-icons](https://github.com/Dava96/osrs-icons), CC BY-NC-SA 3.0; only the icons the game uses are included, listed in `assets/icons/SOURCE.json`).
- Visual checks: `--screenshot=PATH --screenshot-at=SECONDS [--shot-ui=target|menu|settings|controls|shop|kit|skills|aim-chop|aim-plant|scoreboard|tooltip|altar|cannon|splats] [--demo-level=N]` (champion select: no `--champion`, with `--shot-select=ID [--prayer=ID]`) renders a PNG and quits (works under Xvfb with `--rendering-method gl_compatibility`).

## Conventions

- Map units are metres; screen-up is −Z. Saradomin is team 0 (bottom-left), Zamorak team 1.
- Physics layers: 1 walls, 2 units, 3 ground. Units' bodies collide only with walls; `Crowd` keeps them apart.
- Everything visual is primitive meshes for now; swapping in models means replacing `Unit.setup_visuals()`.
- New content should be data first (JSON) and code only for genuinely new mechanics.

## Roadmap

**Next — feel**
- Low-poly OSRS-style models and animations, ability VFX
- Fog of war (the scoreboard already tracks what each team has seen), brush (evergreen tree clusters)
- Smarter bots: jungling, tower-dive avoidance, objective fights
- Armour set bonuses and the "planned" item effects (scythe arcs, recoil, venator bounces)
- Bots that jungle and contest Jad/dragons; dragon souls and Vorkath

**Then — depth**
- Role-based bots; spellbook (summoner) spells
- Giant Mole tower-burrow behaviour; Fire cape empowered minions
- Rune pouch for the Lunar

**Then — multiplayer**
- Server-authoritative netcode with Godot's high-level multiplayer (ENet), lobby and champion draft

**Later**
- More builds (Guthan's, Verac's, Karil's, Void Knight, F2P Rune PKer)
- Map skins (Lumbridge, Varrock, Ardougne), Castle Wars 3v3, Last Man Standing
