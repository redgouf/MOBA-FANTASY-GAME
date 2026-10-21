# Architecture

## Flow

1. `GameData` (autoload) loads `data/*.json` and configures `Combat`.
2. `scenes/main.tscn` runs `scripts/game/main.gd`, which builds the map (`MapBuilder`), shows `ChampionSelect`, then `start_match()` spawns structures, camps, champions, the `WaveSpawner`, camera, input and HUD.
3. Every fighter is a `Unit` (`CharacterBody3D`). Subclasses add behaviour in `_unit_process()`:
   - `Champion`: player input or bot AI, navmesh pathing, abilities, items, prayer, spec energy, leveling
   - `Minion`: walks its lane, fights the nearest enemy
   - `Structure`: towers (LoL-style targeting), altars, flags, and timed summons (dwarf multicannon)
   - `Monster`: neutral camps and epics with leash and reset
4. Damage always goes through `Unit.take_damage(DamageInfo)` → `Combat.mitigate()` (triangle, resists, protection prayer) → status modifiers → passive hooks.
5. `Main` listens to every `died` signal and pays gold, XP, buffs, and checks the win condition.

## Conventions

- Map units are metres; screen-up is −Z. Saradomin is team 0 (bottom-left), Zamorak team 1.
- Physics layers: 1 walls, 2 units, 3 ground. Units collide only with walls.
- Everything visual is primitive meshes for now; swapping in models means replacing `Unit.setup_visuals()`.
- New content should be data first (JSON) and code only for genuinely new mechanics.

## Roadmap

**v0.2 — feel**
- Low-poly OSRS-style models and animations, hitsplat polish, ability VFX
- Minimap, fog of war, brush (evergreen tree clusters)
- Armour set bonuses and the "planned" item effects (scythe arcs, recoil, venator bounces)
- Bots that jungle and contest Jad/dragons; dragon souls and Vorkath

**v0.3 — 5v5**
- Full 5v5 with role-based bots; spellbook (summoner) spells
- Giant Mole tower-burrow behaviour; Fire cape empowered minions
- Prayer drain from Smite, Rune pouch for the Lunar

**v0.4 — multiplayer**
- Server-authoritative netcode with Godot's high-level multiplayer (ENet), lobby and champion draft

**Later**
- More builds (Guthan's, Verac's, Karil's, Void Knight, F2P Rune PKer, Skiller)
- Map skins (Lumbridge, Varrock, Ardougne), Castle Wars 3v3, Last Man Standing
