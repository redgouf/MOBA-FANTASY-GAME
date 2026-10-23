# Prayer

Every build picks **one prayer** at champion select from the OSRS prayer book, limited by its Prayer level. In a match, **V** (or a click on the prayer button) switches it on and off. Builds with overheads (Justiciar Tank, Slayer) also keep Protect from Melee / Missiles / Magic on **Z / X / C**, so protection prayers aren't offered as their pick. Any other build with 37+ Prayer can pick one protection prayer as its prayer, which commits it to one style for the match.

Prayers are free to switch on but drain prayer points (99) while on, at **three times the OSRS rate** (`rules.prayer_drain.rate_mult`):

- Drain resistance = 60 + 2 × prayer bonus (from items: Amulet of glory +3, Amulet of fury +5, Elysian spirit shield +3).
- One point drains every 0.6s × resistance ÷ (the drain effects of every prayer that's on, added up) ÷ 3.
- With no prayer bonus, Piety (drain 24) drains a point every 0.5s, so a full bar lasts 0:49. Piety plus a protection prayer (24 + 12) drains a point every third of a second.
- Overhead prayers (Protect from Melee/Missiles/Magic, Smite, Redemption, Retribution) show their OSRS icon above the champion's head.
- Clicking a prayer switches it on or off at once. Drain is taken once per game tick (0.6s), and a prayer's first tick is free, so **flicking** (on for one tick, off before the next) costs nothing, as in OSRS.
- At 0 points every prayer switches off. Death switches them off too. The Pure's Sever (dragon scimitar) switches them off and blocks them for 5s.

Prayer comes back at:

- **The fountain**: 10 points a second.
- **Prayer potions and super restores**: 30 and 40 points.
- **Prayer altars**: four neutral altars, one beside each red and blue buff camp. Right-click one to walk over and pray: a 1.2s channel that damage interrupts, then your prayer is full. Each champion can pray at an altar once every 45s (any altar). These are not the team "altars" that work like League inhibitors.

Bots pick the strongest prayer for their style, keep cheap prayers (drain 1–2) on all the time, switch the rest on near enemy champions or epic monsters, and walk to a nearby altar when they're under half prayer and out of a fight.

## The prayer book

Drain times are with no prayer bonus. Effects are the MOBA versions; the last column is what the prayer does in OSRS.

| Level | Prayer | Drain | 1 point every (full bar) | In this game | In OSRS |
| --- | --- | --- | --- | --- | --- |
| 1 | Thick Skin | 1 | 12s (19:48) | 3% less damage taken | +5% Defence |
| 4 | Burst of Strength | 1 | 12s (19:48) | +3% melee damage | +5% Strength |
| 7 | Clarity of Thought | 1 | 12s (19:48) | +4% melee attack speed | +5% Attack |
| 8 | Sharp Eye | 1 | 12s (19:48) | +3% ranged damage | +5% Ranged attack and strength |
| 9 | Mystic Will | 1 | 12s (19:48) | +3% magic damage | +5% Magic attack and defence |
| 10 | Rock Skin | 6 | 2s (3:18) | 6% less damage taken | +10% Defence |
| 13 | Superhuman Strength | 6 | 2s (3:18) | +6% melee damage | +10% Strength |
| 16 | Improved Reflexes | 6 | 2s (3:18) | +8% melee attack speed | +10% Attack |
| 19 | Rapid Restore | 1 | 12s (19:48) | Enemy slows, roots, stuns and other debuffs on you wear off 25% faster. | Stats restore twice as fast |
| 22 | Rapid Heal | 2 | 6s (9:54) | Out of combat (4s without taking damage), regenerate 0.6% of max health per second. | Hitpoints restore twice as fast |
| 25 | Protect Item | 2 | 6s (9:54) | If you die, your killer gets 40% less gold. | Keep one extra item on death |
| 26 | Hawk Eye | 6 | 2s (3:18) | +6% ranged damage | +10% Ranged attack and strength |
| 27 | Mystic Lore | 6 | 2s (3:18) | +6% magic damage | +10% Magic attack and defence |
| 28 | Steel Skin | 12 | 1s (1:39) | 9% less damage taken | +15% Defence |
| 31 | Ultimate Strength | 12 | 1s (1:39) | +9% melee damage | +15% Strength |
| 34 | Incredible Reflexes | 12 | 1s (1:39) | +12% melee attack speed | +15% Attack |
| 37 | Protect from Magic | 12 | 1s (1:39) | 40% less magic damage taken | Blocks magic (40% against players) |
| 40 | Protect from Missiles | 12 | 1s (1:39) | 40% less ranged damage taken | Blocks ranged (40% against players) |
| 43 | Protect from Melee | 12 | 1s (1:39) | 40% less melee damage taken | Blocks melee (40% against players) |
| 44 | Eagle Eye | 12 | 1s (1:39) | +9% ranged damage | +15% Ranged attack and strength |
| 45 | Mystic Might | 12 | 1s (1:39) | +9% magic damage | +15% Magic attack and defence |
| 46 | Retribution | 3 | 4s (6:36) | When you die, you explode for 12 (+2.4 per level) true damage to enemies within 4m. | On death, hits nearby foes for up to 25% of your Prayer level |
| 49 | Redemption | 6 | 2s (3:18) | When a hit leaves you under 10% health, heal 25% of your max health. This uses up all your prayer points. | Heals you at low health, draining all prayer |
| 52 | Smite | 18 | 0.67s (1:06) | Your hits drain enemy champions' prayer by 25% of the damage (a hit for 20% of their health drains 5% of their prayer). | Drains the target's prayer by 25% of damage dealt |
| 55 | Preserve | 2 | 6s (9:54) | Potion and food effects last 50% longer. | Boosted stats last 50% longer |
| 60 | Chivalry | 12 | 1s (1:39) | +7% melee damage, +6% melee attack speed, 6% less damage taken | +15% Attack, +18% Strength, +20% Defence |
| 62 | Deadeye | 12 | 1s (1:39) | +11% ranged damage, 2% less damage taken | +18% Ranged attack and strength, +5% Defence |
| 63 | Mystic Vigour | 12 | 1s (1:39) | +11% magic damage, 2% less damage taken | +18% Magic attack and defence, +5% Defence, +3% magic damage |
| 70 | Piety | 24 | 0.5s (0:49) | +10% melee damage, +8% melee attack speed, 8% less damage taken | +20% Attack, +23% Strength, +25% Defence |
| 74 | Rigour | 24 | 0.5s (0:49) | +13% ranged damage, 8% less damage taken | +20% Ranged attack, +23% Ranged strength, +25% Defence |
| 77 | Augury | 24 | 0.5s (0:49) | +13% magic damage, 8% less damage taken | +25% Magic attack and defence, +25% Defence |
| 84 | Zeal | 24 | 0.5s (0:49) | +12% melee damage, +10% melee attack speed, 8% less damage taken | +25% Attack, +28% Strength, +25% Defence |

The Zeal icon is a recoloured Piety icon until the icon set has one. Drain times are at the 3x rate.

## Champion abilities vs shop spec weapons

Several champions' ultimates are built on a spec weapon that anyone can also buy in the shop. So that buying the item never matches the champion, each overlap is handled one of two ways. **A**: the champion's version is always clearly better. **B**: the champion's version is retooled into a different move.

| Champion | Ability | Shop item | Choice | Why and what changed |
| --- | --- | --- | --- | --- |
| The Pure | R Puncture (p++) | Dragon dagger (Puncture) | A | The DDS spec *is* the pure. The champion's version scales with rank, has almost no cooldown (0.5s vs 4s), hits harder and now poisons (p++: 8 true damage a second for 4s). |
| Zerker | R Dragon Claws | Dragon claws (Slice and Dice) | A | Claws are the berserker's signature. Scales with rank, 1s cooldown vs 12s, and now fills the Berserker Necklace to 5 stacks. |
| Slayer | R Warhammer Smash | Dragon warhammer (Smash) | A | DWH is how Slayers boss. The champion's drops now stack as in OSRS (each takes another 30% of what's left, up to 3), and are 1.5x on monsters; the item's just refresh. |
| Ancient Mage | R Immolate | Volatile nightmare staff (Immolate) | A | Scales with rank, reaches further (14 vs 12) and keeps its +50% execute below 30% health, which the item doesn't have. |
| Hybrid | R Freeze & Spec | Armadyl crossbow (Armadyl Eye) | A (already) | The Ice Barrage root before the guaranteed crit, and rank scaling, were already unique. |
| Dharok | R Granite Maul Combo → **Wretched Smash** | Granite maul (Quick Smash) | B | Dharok is about fighting at low health, not about the maul. The R is now a two-handed greataxe smash: his set effect counts twice for it, and below 25% health it hits every enemy within 3m. |
| Justiciar Tank | R Warstrike → **Bandos Rally** | Bandos godsword (Warstrike) | B | A tank's ult should start fights for the team. He still charges in with the BGS, but the slam hits everyone within 3.5m (each loses armour) and gives him and allies within 6m +15% armour for 6s. |
| Justiciar Tank | W Elysian Ward | Elysian spirit shield | A | The shield's passive is now self-only and weaker (12% on a 70% chance); the Ward is 25% and can protect an ally. |
| Hybrid | W Tele Block | (none) | — | No item grants Tele Block, so nothing devalues it. New: Protect from Magic halves it, as in OSRS. |
| Dharok / Zerker | E Saradomin Brew / W Super Combat Potion | Saradomin brew / Super combat potion | A (already) | The abilities are free and come back on a cooldown; the potions cost gold and are used once. |

`test_signature_specs` in `tests/test_runner.gd` checks the A cases (at least the item's base damage and ratio, scales with rank, shorter cooldown) and that the B cases are different moves.
