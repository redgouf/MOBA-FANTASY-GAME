# Writing kits and item specs

Champion abilities (`data/champions.json`) and item spec actives (`data/items.json` → `spec_active`) use the same format and are executed by `scripts/abilities/ability_runner.gd`.

## Ability fields

| Field | Meaning |
| --- | --- |
| `name`, `text` | Display name and tooltip |
| `cast` | `self`, `target_unit` (needs a unit; walks into range first) or `point` (aimed at the cursor, clamped to range) |
| `range` | Cast range in metres |
| `cooldown` | Seconds |
| `spec_cost` | Special attack energy (0–100). Ultimates and item specs use this. |
| `target_ally` / `allow_self` | For `target_unit` support spells |
| `bot_use` | Bot hint: `combat` (default), `low_health`, `high_health`, `never` |
| `forms` | Per-form overrides (used by the Hybrid's Q) |
| `effects` | List of effects, applied in order. Any effect may add `delay` (seconds). |
| `planter` | Plant-and-chop ability (Timber!): `max`, `cooldown` (plant cooldown), `block_radius`, `chop_range`, `hover_radius`, `lifetime` (0 = permanent). Q on open ground plants a solid yew; Q on your own yew chops it and runs `effects` with the point at the yew, aimed from the caster through it. |

## Effect types

| `type` | Key fields |
| --- | --- |
| `damage` | `base`, `base_per_rank` (kit abilities), `base_per_level` (champion level), `ratio` {`damage`, `magic_power`, `skill_power`}, `style`, `hits` + `hit_interval`, `cascade` (dragon claws), `pct_current_health` / `pct_max_health` + `cap`, `missing_health_bonus`, `bonus_below_health` {`threshold`, `mult`}, `low_health_area` {`threshold`, `radius`} (below that much of the caster's health, hit everything around the target), `lifesteal`, `crit_mult`, `armor_pen`, `true`, `ignores_prayer`, `falloff`, `shred_ratio` + `shred_duration`, `target_statuses` [...], `area` |
| `heal` | `base`, `base_per_level`, `ratio.magic_power`, `pct_missing`, `pct_max`, `from_self_cost_mult`, `over_time`, `on` (`self`/`target`), `area` (heals allies) |
| `self_cost` | `pct_current_health` (never drops below 1) |
| `status` | `on` (`self`, `target`, `area_allies`, `area_enemies`), `kind`, `amount`, `duration`, `chance`, `data`, `area` |
| `dash` | `to` (`point`/`target`), `distance`, `speed`, `stop_distance`, `ignore_walls`, `teleport` |
| `knockback` | `distance` (pushes the target away) |
| `spec_transfer` | `amount` (gives an ally spec energy) |
| `max_stacks` | (none) fills a `stacking_damage` passive (Zerker's claws fill the Berserker Necklace) |

**Per-rank values:** any number in an effect (or in one of its `target_statuses`) can have a `<key>_per_rank` partner that is added once per rank past 1, e.g. `"duration": 1.5, "duration_per_rank": 0.1` roots for 1.8s at rank 4. `base_per_rank` works the same way for damage and healing. `AbilityRunner.ranked()` applies them; tooltips list them under "Each rank".

`target_statuses` entries take `kind`, `amount`, `duration`, `chance`, `id`, `data`, plus `stack` (up to that many copies at once, each taking the same share of what's left, OSRS DWH-style) and `monster_mult` (amount multiplier against neutral monsters).
| `summon` | `unit` (from `units.json` → `summons`), `duration` |
| `toggle_form` | Switches champion form (Hybrid) |
| `taunt` | `area`, `duration` |
| `pull` | `distance` (reels the target toward the caster) |
| `prop` | `shape` (`fire`, `anvil`, `harpoon`, `fireworks`), `at` (`self`/`point`/`target`), `duration`. Visual only. |

Any effect can also take `delay` (seconds) and `repeat` + `repeat_interval` (a ground zone that ticks, like Bonfire).

## Effects (`fx`)

Visual only. An ability or item `spec_active` lists effects under `fx`; each plays when it's cast (`CombatFx.ability`).

| `kind` | What it draws | Extra fields |
| --- | --- | --- |
| `swipe` | A glowing arc toward the target or point | `arc` (`slash`, `crush`, `stab`), `size`, `sweep` (degrees) |
| `multi_slash` | Several quick swipes (claws, DDS) | `count` |
| `projectile` | A projectile to the target or point | `shape` (`arrow`, `bolt`, `dart`, `javelin`, `rock`, `cannonball`, `orb`, `fireball`), `impact` (`spark`, `splash`, `dust`), `size`, `arc`, `speed` |
| `volley` | Several projectiles fanned along a line | `count`, `spread`, `shape` |
| `burst` | Spell explosion: dome, ring, sparks (`"color": "ice"` adds ice shards) | `radius` (defaults to the ability's area) |
| `ring` | Expanding ground ring | `radius`, `thickness`, `duration` |
| `glow` | Rising sparkles on a unit (heals, buffs) | `duration` |
| `ice_block` | Ice block around the target (or everyone in the area at a point) | `duration` |
| `slam` | Ground shockwave, dust and debris | `radius` |
| `streak` | A bright line from the caster to the target or point (dashes) | `width` |
| `sparks` | A burst of sparks | `count` |

Every effect takes `at` (`target`, `point`, `self`; defaults to the cast's target), `color` (an element name such as `ice`, `blood`, `shadow`, `fire`, `venom`, `holy`, `heal`, `lunar`, or `"#rrggbb"`) and `delay` (seconds).

Basic attacks use `attack_fx` on the champion (or form, or unit in `units.json`): a `swipe` or a `projectile` entry, optionally keyed by style (`{"melee": ..., "ranged": ..., "magic": ...}`, as TzTok-Jad does). Towers use `"team_color": true`.

## Areas

```json
{ "shape": "circle", "radius": 2.5, "center": "point" }
{ "shape": "cone", "radius": 4.5, "angle": 100, "center": "self" }
{ "shape": "line", "length": 200, "width": 2.5 }
```

`center` is `point` (cursor), `self` or `target`. Add `max_targets` to cap hits. A line can take `"origin": "point"` to start at the point instead of the caster (a felled yew). Lines and cones keep the direction they had at cast time, even if an effect is delayed.

## Status kinds

`slow`, `haste`, `root` (grants 3s root immunity afterwards, like OSRS freeze immunity), `stun`, `planted`, `damage_mult`, `damage_taken_mult`, `melee_damage_taken_mult`, `armor_mult`, `armor_flat`, `attack_speed`, `range_bonus`, `disable_prayer`, `melee_immune`, `tele_block`, `spec_regen_mult`, `burn_on_hit`, `venom` (escalates by `data.step` to `data.max`), `burn`, `poison`, `heal_over_time`, `taunt`, `negate_hit`, `vengeance`, `elysian` (`data.chance`).

## Passive types

Set in a champion's `passive.type`: `missing_health_damage`, `glass_cannon`, `nth_hit_bonus`, `form_switch`, `target_magic_scaling`, `monster_bonus`, `venom`, `stacking_damage`, `flat_reduction`, `skilling_level_up` (every Nth ability runs the passive's own `effects`), `rune_pouch` (placeholder). Implemented in `Champion.modify_outgoing`, `modify_incoming` and `on_attack_landed`.

## Prayers

`rules.json` → `prayers` is the OSRS prayer book in order: `id`, `name`, `level`, `drain` (OSRS drain effect), and what it does here: `style` + `damage` / `attack_speed` (only for that style), `damage_taken`, `protect` (a style), or `special` (`rapid_restore`, `rapid_heal`, `protect_item`, `retribution`, `redemption`, `smite`, `preserve`, with their own numbers and a `text`). `osrs` is the original effect, shown in tooltips. `PrayerBook` reads it; see [PRAYER.md](PRAYER.md).

## Item requirements

```json
"requirements": { "attack": 75, "defence": 65 }
```

Skills: any of the 24 OSRS skills. Combat skills (`attack`, `hitpoints`, `strength`, `defence`, `ranged`, `prayer`, `magic`) are fixed per build; the others are rolled 20–75 each game (see DESIGN.md), so an item gated on, say, `"crafting": 40` is only sometimes buyable, and one above 75 is Skiller-only (or for a build whose lucky skill rolled high: one skill per build rolls up to 99). A champion can only buy an item if every level it has this game meets the requirement.

`"artisan": { "smithing": 99 }` is the OSRS level to make the item; a champion with it ignores the item's **combat** requirements (non-combat ones still apply). Consumables have no `requirements`; `"potency": { "cooking": 80 }` makes them 'perfect' for a champion with that level (`rules.potency_bonus`, +15% to every amount; buffs without an amount last longer instead). Items under level 20 have no `potency`. Ammo (arrows, darts, knives) never requires Fletching or Runecraft.

Potion statuses of kind `skill_boost` (`skill`, `flat`, `pct`, `duration`) boost a skill by flat + pct of the base level, as in OSRS (negative values lower it, like the Saradomin brew); `use.restore_skills` (super restore) removes lowered levels. Each boosted level is worth `rules.potion_level_value`: +0.5% damage for Strength (melee), Ranged and Magic, +0.25% melee damage for Attack, +0.5% defence for Defence.

Item stats beyond the basics: `prayer_bonus` (OSRS prayer bonus), `monster_damage` (vs camps and epics), `gold_bonus` (last-hit gold), `burn_on_hit` (true damage a second for 2s on basic attacks), `structure_damage` (vs towers and other buildings), `consumable_bonus` (food and potions stronger), `skill_power` (also adds `rules.skill_power_attack_ratio` of itself to basic attacks for every build but the Skiller, whose passive does it at a higher ratio), `elysian`. Consumable `use`: `heal`, `heal_over_time` + `duration`, `heal_pct_max`, `prayer`, `spec`, `statuses` (each may carry `data`), `cleanse` (status kinds to remove; an `antipoison` status with `data.blocks` keeps them off).
