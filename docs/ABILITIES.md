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

## Effect types

| `type` | Key fields |
| --- | --- |
| `damage` | `base`, `base_per_level`, `ratio` {`damage`, `magic_power`}, `style`, `hits` + `hit_interval`, `cascade` (dragon claws), `pct_current_health` / `pct_max_health` + `cap`, `missing_health_bonus`, `bonus_below_health` {`threshold`, `mult`}, `lifesteal`, `crit_mult`, `armor_pen`, `true`, `ignores_prayer`, `falloff`, `shred_ratio` + `shred_duration`, `target_statuses` [...], `area` |
| `heal` | `base`, `base_per_level`, `ratio.magic_power`, `pct_missing`, `pct_max`, `from_self_cost_mult`, `over_time`, `on` (`self`/`target`), `area` (heals allies) |
| `self_cost` | `pct_current_health` (never drops below 1) |
| `status` | `on` (`self`, `target`, `area_allies`, `area_enemies`), `kind`, `amount`, `duration`, `chance`, `data`, `area` |
| `dash` | `to` (`point`/`target`), `distance`, `speed`, `stop_distance`, `ignore_walls`, `teleport` |
| `knockback` | `distance` (pushes the target away) |
| `spec_transfer` | `amount` (gives an ally spec energy) |
| `summon` | `unit` (from `units.json` → `summons`), `duration` |
| `toggle_form` | Switches champion form (Hybrid) |
| `taunt` | `area`, `duration` |

## Areas

```json
{ "shape": "circle", "radius": 2.5, "center": "point" }
{ "shape": "cone", "radius": 4.5, "angle": 100, "center": "self" }
{ "shape": "line", "length": 200, "width": 2.5 }
```

`center` is `point` (cursor), `self` or `target`. Add `max_targets` to cap hits.

## Status kinds

`slow`, `haste`, `root` (grants 3s root immunity afterwards, like OSRS freeze immunity), `stun`, `planted`, `damage_mult`, `damage_taken_mult`, `melee_damage_taken_mult`, `armor_mult`, `armor_flat`, `attack_speed`, `range_bonus`, `disable_prayer`, `melee_immune`, `tele_block`, `spec_regen_mult`, `burn_on_hit`, `venom` (escalates by `data.step` to `data.max`), `burn`, `poison`, `heal_over_time`, `taunt`, `negate_hit`, `vengeance`, `elysian` (`data.chance`).

## Passive types

Set in a champion's `passive.type`: `missing_health_damage`, `glass_cannon`, `nth_hit_bonus`, `form_switch`, `target_magic_scaling`, `monster_bonus`, `venom`, `stacking_damage`, `flat_reduction`, `rune_pouch` (placeholder). Implemented in `Champion.modify_outgoing`, `modify_incoming` and `on_attack_landed`.

## Item requirements

```json
"requirements": { "attack": 75, "defence": 65 }
```

Skills: `attack`, `strength`, `defence`, `ranged`, `magic`, `prayer`. A champion can only buy an item if every level in its `skills` meets the requirement.
