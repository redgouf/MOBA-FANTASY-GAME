# Design summary

The living design doc (full kits, item tables, map breakdown, open questions) is kept in Claude Docs: *Gielinor Legends — OSRS × MOBA Design Doc*. This file records the decisions the code is built on.

## Scope

- 100% free, non-commercial fan project. Keeps every OSRS name and reference and credits Jagex.
- 5v5, three lanes, 25–35 minute matches (the prototype currently runs 2v2 with bots).

## Core rules

| System | Decision |
| --- | --- |
| Combat triangle | Melee > Ranged > Magic > Melee. Countering style deals +15%. Three resists: melee, ranged, magic defence. |
| Ticks | 1 tick = 0.25s. Attack speed is defined in ticks (whip 4, godsword 6, Dharok's greataxe 7). |
| Special attack energy | One 0–100% bar, +1%/s. Pays for every ultimate **and** every spec-weapon item active. |
| Skill levels | Each champion has OSRS levels (Attack, Strength, Defence, Ranged, Magic, Prayer). Items keep real OSRS requirements. |
| Protection prayers | **Not universal.** Only tank and main-account builds (currently Justiciar Tank and Slayer) have overheads: −40% from one style, drains prayer. |
| Offensive prayers | Every build gets the best its Prayer level allows: Piety 70 / Chivalry 60 / Ultimate Strength 31 (melee), Rigour 74 / Eagle Eye 44 (ranged), Augury 77 / Mystic Might 45 (magic). |
| Spec weapons | Active items in the 6 item slots, each with its own cooldown, spending the shared spec bar. Requirements stop builds from using gear their account couldn't wield. |
| Wilderness Ditch | Visual only. Walkable like a normal river; no ditch-jump. |
| Teams | Saradomin (Falador, bottom-left) vs Zamorak (Lava Maze, top-right). |

## Map objects

| MOBA | Gielinor Legends |
| --- | --- |
| Nexus | Team standard (Castle Wars flag) |
| Inhibitor | Saradomin altar / Chaos altar |
| Tower | White Knight watchtower / Dark Wizard tower |
| Minions | Goblins, Dark wizards, Dwarf cannon carts |
| Baron | TzTok-Jad (Giant Mole holds the pit until 14:00) |
| Dragon | Chromatic dragons (Vorkath as the elder) |
| Blue / red buff | Abyssal demon (spec regen) / Fire giant (burn) |

## Champions (launch 10)

| Champion | Role | Overheads | Signature |
| --- | --- | --- | --- |
| Dharok | Top juggernaut | No | Damage rises as health falls; granite maul double spec |
| The Pure | Jungle assassin | No | 1 Defence; Sever; four DDS specs |
| Ancient Mage | Mid control mage | No | Ice/Blood/Shadow Barrage; Volatile staff |
| Hybrid | Bot/mid skirmisher | No | Range/Mage form switching; Freeze & Spec |
| Max Ranger | Bot marksman | No | Twisted bow scaling vs magic |
| Blowpiper | Bot hyper-carry | No | Escalating venom; Toxic Siphon |
| Slayer | Jungle bruiser | Yes | Monster bonus; dwarf multicannon; DWH |
| Zerker | Top/jungle diver | No | Berserker stacks; dragon claws |
| Justiciar Tank | Support/top tank | Yes | Flat damage reduction; shove; BGS |
| Lunar | Support enchanter | No | Heal Other, Vengeance Other, Energy Transfer |
