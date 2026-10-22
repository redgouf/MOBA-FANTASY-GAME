# League of Legends values used for mobs and structures

Minions, turrets, inhibitors, the nexus and jungle monsters use League of Legends **Summoner's Rift (Classic)** numbers, current as of patch 26.x (checked 2026-10-21). They live in `data/units.json`, so they can be updated without code changes.

**Unit scale:** Summoner's Rift is about 14,870 units across, and our map is 200 m, so **75 LoL units = 1 m** (`rules.lol_units_per_meter`). Ranges and minion speed are converted with that. League **armor** maps to our melee and ranged defence, and **magic resist** to magic defence (100 of either halves damage, as in League).

**Attack speed (v0.7):** units now swing at OSRS speeds (`osrs_ticks` × 0.6s: minions, turrets and most monsters 4 ticks, dark wizards and cannon carts 5, ogres and moss giants 6, TzTok-Jad 8). The League `attack_speed` is kept as the reference: each hit is scaled so the unit's damage per second is 70% of its League value (`rules.basic_attack_dps_scale`). Health, armour and damage-per-level numbers below are unchanged.

## OSRS → League mapping

| Ours | League | Notes |
| --- | --- | --- |
| Goblin | Melee minion | |
| Dark wizard | Caster minion | Our wizards hit with magic. In League, caster minion attacks are physical. |
| Dwarf cannon cart | Siege minion | |
| White / Black Knight | Super minion | Spawn while an enemy altar is down |
| Watchtower / Dark Wizard tower | Outer and inner turrets | |
| Altar tower | Inhibitor turret | |
| Standard guard tower | Nexus turret | |
| Saradomin / Chaos altar | Inhibitor | |
| Team standard | Nexus | |
| Abyssal demon | Blue Sentinel | |
| Fire giant | Red Brambleback | |
| Moss giant | Gromp | |
| Big wolf + 2 White wolves | Greater Murk Wolf + 2 Murk Wolves | |
| Rooster + 5 Chickens | Crimson Raptor + 5 Raptors | |
| Ogre chieftain + Ogre | Ancient Krug + Krug | |
| Rock crab | Rift Scuttler | |
| 3 Baby moles | 3 Voidgrubs | |
| Giant Mole | Rift Herald | |
| TzTok-Jad | Baron Nashor | Keeps Jad's melee/ranged/magic attack cycle |
| Chromatic dragon | Elemental Drake | |

## Minions

Minions gain an **upgrade at 0:30 and every 90 s after**. Each stat is `base + per_upgrade × upgrades`, up to a cap. Siege damage grows +4 per upgrade after upgrade 15.

| | Health | Damage | Atk/s | Range | Armor / MR | Gold | XP |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Melee | 430 + 35/upg (cap 1550) | 11 → 80\* | 1.25 | 110 | 0 → 20\* / 0 | 20 | 62 |
| Caster | 275 + 9/upg (cap 600) | 21 → 125\* | 0.667 | 550 | 0 / 0 | 14 | 31 |
| Siege | 750 + 85/upg (cap 5850) | 36 + 1.5/upg, +4 after 15 (cap 126) | 1.0 | 300 | 0 / 0 | 50 + 1/upg | 75 |
| Super | 1600 → 7500\* | 185 → 480\* | 0.85 | 170 | 100 / −30 | 50 + 1/upg | 75 |

**First-wave values match League:** melee 465 HP and 11 damage, caster 284 HP and 21 damage, siege 835 HP and 37.5 damage.

**Damage modifiers:** minions deal 60% damage to champions and structures (siege minions deal 84% to structures). Against other minions, melee minions add 2% and casters add 3.5% of the target's current health.

**Waves:**
- First wave at 0:30. A wave every 30 s, every 25 s from 14:00, and every 20 s from 30:00.
- Minions in a wave spawn 0.792 s apart.
- Each wave is 3 melee and 3 casters.
- A siege minion joins the 3rd wave, then every 3rd wave until 14:00, every 2nd until 25:00, and every wave after.
- From 14:00, siege waves have one fewer melee minion. From 30:00, waves have 2 casters.
- While an enemy altar is down, that lane gets a Knight instead of a siege minion. With all three altars down, every lane gets 2 Knights.

\* **Inferred.** League publishes the start and cap but not the per-upgrade step. Melee and caster damage use the siege pattern: +1.5 per upgrade, then +4 after upgrade 15. Melee armor rises evenly to its cap, and Knights use +200 health and +10 damage per upgrade.

## Turrets and structures

| | Health | Damage (grows +12/min) | Atk/s | Range | Armor / MR | Gold to each enemy |
| --- | --- | --- | --- | --- | --- | --- |
| Outer | 9000 | 182 → 350 (at 14:00) | 0.833 | 750 | 60 / 60 | 50 |
| Inner | 5000 | 187 → 427\* | 0.833 | 750 | 60 / 60 | 25 |
| Inhibitor turret | 4750, regen 3/s (caps 30/75/100%) | 187 → 427\* | 0.833 | 750 | 60 / 60 | 25 |
| Nexus turret | 3500, regen 6/s (caps 40/70/100%), respawns after 3:00 at 40% | 165 → 405\* | 0.833 | 750 | 60 / 60 | 50 |
| Altar (inhibitor) | 4000, regen 15/s, respawns after 5:00 | — | — | — | 20 / 0 | 50 to last hitter |
| Standard (nexus) | 5500\*\* | — | — | — | — | Win |

**Turret rules:**
- **Warming Up:** +50% damage per consecutive shot on champions, up to +150%. It resets 5 s after the last champion hit, not when the turret switches targets.
- **Shots on minions** deal a fixed share of the minion's max health: melee 45%, caster 70%, siege 14% (outer) / 11% (inner) / 8% (inhibitor and nexus), super 7%. A turret kills a melee minion in 3 shots and a caster in 2.
- **Targeting:** a champion that hits an allied champion within 1400 units comes first. Otherwise the turret keeps its current target, then picks siege/super, then melee, then caster, then champions.
- Melee champions deal 20% more damage to turrets.
- The first turret of the game gives 300 bonus gold to whoever destroys it.

\* **Inferred.** League gives start and max damage "based on minutes". We use the outer turret's published growth (12 per minute, reaching 350 at 14:00) for all tiers.
\*\* From earlier patches. The current wiki page doesn't list Nexus health.

## Jungle

Monster level is the average champion level when the camp spawns. Stats shown as low → high scale from the monster's starting level up to level 18.

| Camp | First / respawn | Health | Damage | Atk/s | Armor / MR | Gold | XP |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Abyssal demon (Blue Sentinel) | 0:55 / 5:00 | 2300 → 6210 | 66 → 198 | 0.493 | 42 / 42 | 90 | 95 → 142.5 |
| Fire giant (Red Brambleback) | 0:55 / 5:00 | 2300 → 6210 | 66 → 198 | 0.493 | 42 / 42 | 90 | 95 → 142.5 |
| Moss giant (Gromp) | 1:07 / 2:15 | 2050 → 4817.5 | 70 → 210 | 0.425 | 42 / 42 | 80 | 120 → 180 |
| Big wolf (Greater Murk Wolf) | 0:55 / 2:15 | 1600 → 3760 | 30 → 90 | 0.625 | 42 / 42 | 55 | 50 → 75 |
| White wolf ×2 (Murk Wolf) | | 630 → 1480.5 | 10 → 30 | 0.625 | 20 / 20 | 15 | 15 → 22.5 |
| Rooster (Crimson Raptor) | 0:55 / 2:15 | 1200 → 2820 | 17 → 51 | 0.667 | 42 / 42 | 35 | 20 → 30 |
| Chicken ×5 (Raptor) | | 500 → 1175 | 7 → 21 | 1.0 | 20 / 20 | 8 | 10 → 15 |
| Ogre chieftain (Ancient Krug) | 1:07 / 2:15 | 1350 → 3172.5 | 57 → 171 | 0.613 | 42 / 42 | 15 | 15 → 22.5 |
| Ogre (Krug) | | 650 → 1527.5 | 20 → 60 | 0.613 | 20 / 20 | 10 | 10 → 15 |
| Rock crab (Rift Scuttler) | 2:55 / 2:30 | 1550 → 5270 | doesn't attack | — | 42 / 42 | 55 → 121 | 100 → 150 |
| Baby mole ×3 (Voidgrub), lvl 7+ | 8:00, once; leaves at 14:45 | 2269 → 4700 | 21.69 → 46 | 0.5 | 72.76→170 / 51.38→100 | 30 | 65 |
| Giant Mole (Rift Herald), lvl 9+ | 15:00, once; leaves at 19:45 | 11718 → 18900 | 99.5 → 250 | 0.4 | 87.92→170 / 58.96→100 | 100 | 240 |
| TzTok-Jad (Baron Nashor), lvl 12+ | 20:00 / 6:00 | 17791.75 → 19190 | 350.5 → 515 | 0.625 | 104.2→170 / 67.1→100 | 150 + 100 to each teammate | 650 |
| Chromatic dragon (Drake), lvl 6+ | 5:00 / 5:00 | 5106.25 → 10000 | 70 | 0.5 | 65.6→170 / 47.8→100 | 75 | 160 → 400 |

**Buffs:**
- **Blue:** doubled spec-energy regeneration for 120 s, our stand-in for Crest of Insight.
- **Red:** Crest of Cinders, 120 s. Attacks deal 3 hits of 5–20 true damage over 2 s and slow the target 10/15/25% (melee) or 5/7.5/12.5% (ranged) for 3 s.
- **Baron and drakes:** keep our current team buffs.
- **Experience** from monsters goes only to the killing team's champions nearby.

## Not modelled yet

- Turret plating, Bulwark, Crystalline Overgrowth and outer-turret decay.
- Krugs splitting into smaller krugs.
- Scuttle crab's speed shrine (approximated as a 20 s haste on the killer).
- Voidgrub stacks, Eye of the Herald, the exact effects of Hand of Baron and dragon souls, and the Elder Dragon.
- Minion movement speed growth (350 → 450 over the game).
- League champion movement speed. Our champions keep their own speeds (about 6.5 m/s, faster than League's 335 units/s, about 4.5 m/s).

## Sources

- [Minion (League of Legends)](https://wiki.leagueoflegends.com/en-us/Minion_(League_of_Legends)), [Melee minion](https://wiki.leagueoflegends.com/en-us/Melee_Minion), [Caster minion](https://wiki.leagueoflegends.com/en-us/Caster_Minion), [Siege minion](https://wiki.leagueoflegends.com/en-us/Siege_Minion), [Super minion](https://wiki.leagueoflegends.com/en-us/Super_Minion)
- [Melee](https://www.riftpatchnotes.com/lol/unit/melee-minion), [caster](https://www.riftpatchnotes.com/lol/unit/caster-minion) and [cannon](https://www.riftpatchnotes.com/lol/unit/cannon-minion) minion stats and patch history (riftpatchnotes.com)
- [Turrets](https://wiki.leagueoflegends.com/en-us/Turrets), [Turret (fandom)](https://leagueoflegends.fandom.com/wiki/Turret), [turret patch history](https://www.riftpatchnotes.com/lol/system/turrets), [Inhibitor](https://wiki.leagueoflegends.com/en-us/Inhibitor)
- [Monster](https://wiki.leagueoflegends.com/en-us/Monster), [Blue Sentinel](https://wiki.leagueoflegends.com/en-us/Blue_Sentinel), [Red Brambleback](https://wiki.leagueoflegends.com/en-us/Red_Brambleback), [Gromp](https://wiki.leagueoflegends.com/en-us/Gromp), [Greater Murk Wolf](https://wiki.leagueoflegends.com/en-us/Greater_Murk_Wolf), [Crimson Raptor](https://wiki.leagueoflegends.com/en-us/Crimson_Raptor), [Ancient Krug](https://wiki.leagueoflegends.com/en-us/Ancient_Krug), [Rift Scuttler](https://wiki.leagueoflegends.com/en-us/Rift_Scuttler), [Voidgrub](https://wiki.leagueoflegends.com/en-us/Voidgrub), [Rift Herald](https://wiki.leagueoflegends.com/en-us/Rift_Herald), [Baron Nashor](https://wiki.leagueoflegends.com/en-us/Baron_Nashor), [Infernal Drake](https://wiki.leagueoflegends.com/en-us/Infernal_Drake), [Elder Dragon](https://wiki.leagueoflegends.com/en-us/Elder_Dragon), [Crest of Cinders](https://wiki.leagueoflegends.com/en-us/Crest_of_Cinders), [jungle patch history](https://www.riftpatchnotes.com/lol/system/jungle)
