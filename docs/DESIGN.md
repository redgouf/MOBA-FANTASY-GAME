# Design summary

The living design doc (full kits, item tables, map breakdown, open questions) is kept in Claude Docs: *Gielinor Legends — OSRS × MOBA Design Doc*. This file records the decisions the code is built on.

## Scope

- 100% free, non-commercial fan project. Keeps every OSRS name and reference and credits Jagex.
- 5v5, three lanes, 25–35 minute matches (the prototype currently runs 2v2 with bots).

## Core rules

| System | Decision |
| --- | --- |
| Combat triangle | Melee > Ranged > Magic > Melee. Countering style deals +15%. Three resists: melee, ranged, magic defence. |
| Ticks | 1 tick = 0.6s, as in OSRS. Attack speed is defined in ticks (whip 4 = 2.4s, godsword 6, Dharok's greataxe 7 = 4.2s). Units balanced on LoL attack speeds hit harder per swing so their basic-attack damage per second is 70% of what it was (`basic_attack_dps_scale`). |
| Special attack energy | One 0–100% bar, +1%/s. Pays for every ultimate **and** every spec-weapon item active. |
| Skill levels | Every build has all 24 OSRS skills. Combat skills (Attack, Hitpoints, Strength, Defence, Ranged, Prayer, Magic) are fixed per build; every other skill is rolled 20–75 each game (`rules.skill_roll`; the Skiller's 99s are fixed, and a build can set its own range in `roll_ranges`, like the Slayer's 60–85 Slayer; one random other skill per build is its lucky skill and rolls `rules.lucky_roll`, 20–99). Items keep real OSRS requirements, so the rolls decide which skilling items a build can buy this game; anything above 75 is Skiller-only unless a lucky roll reaches it. Food and potions have no requirement: the Cooking/Herblore level makes them 'perfect' (+15%; none under level 20), and potions boost their own skill as in OSRS. The level to make an item yourself (`artisan`) waives its combat requirements. Name tags show the build's real OSRS combat level. |
| Champion select | Fixed 1600x900 layout in the OSRS interface style: portrait cards, Equipment Stats (gear slots, turning figure, bonuses), abilities, Skills/Prayer tabs, LOCK IN with a 5 s countdown. |
| Mobs and structures | League of Legends Summoner's Rift values for minions, turrets, inhibitors, nexus and jungle (see LOL_VALUES.md). |
| Protection prayers | Overheads on Z/X/C only for tank and main-account builds (Justiciar Tank and Slayer): −40% from one style, switchable at will. Other builds with 37+ Prayer may pick one protection prayer as their prayer. |
| Prayers | Every build picks one of the 32 OSRS prayers at champion select (by Prayer level) and toggles it with V. Prayers drain at OSRS rates (0.6s × (60 + 2 × prayer bonus) ÷ drain per point); refill at the fountain, with potions, or at the four prayer altars beside the buff camps. See PRAYER.md. |
| Signature specs | A champion ability built on a shop spec weapon must beat the item at every rank (option A) or be retooled into a different move (option B). See PRAYER.md. |
| Health and damage scale | `rules.hp_scale` (0.2) multiplies every health pool, damage and healing amount as the data loads (data files keep League-sized numbers). Percentages, defences and durations are untouched. Overkill is capped. |
| Fog of war | Team-shared vision with League sight radii (75 units = 1 m), blocked by walls; enemy structures always visible. Spectators toggle it with F; players can't. |
| Ability ranks | Basic abilities lose 6% cooldown per rank and every ability has at least one other per-rank gain (`*_per_rank` keys in the data). |
| Hitsplats | OSRS style: red damage, blue 0, gold-trimmed max hit for crits, green/teal/orange poison/venom/burn. Up to 4 per unit, ~2 ticks each, no drifting. Hits not dealt by or to you are tinted darker, smaller and see-through; yours are bigger. |
| Unit spacing | Units never overlap. Each frame `Crowd` eases overlapping pairs apart, lighter units giving way (minion 1, champion 4, monster 6; structures, summons and epics never move), using `move_and_collide` so walls still block. |
| Casting | League-style: quick cast with indicator by default (hold to aim, release to cast), or normal cast / quick cast in Settings. |
| Scoreboard | Hold Tab. Enemy items are the last ones your team saw. |
| Visuals | Whitebox shapes by default; real OSRS models from a private pack in personal builds only (fixed look per champion, weapon swaps on specs, Hybrid's form shows its weapon). Melee swipes, weapon-matched projectiles and per-ability effects in both. |
| Champion tags | Two letters on each champion's chest and back (DH, PU, AM, HY, MR, BP, SL, ZK, JT, LU, SK). |
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
| Dragon | Green, blue, red or black dragon (random, looks only); from the second dragon on, 30% of the time it is the King Black Dragon (+60% health, +40% damage, +75% gold). Vorkath as the elder |
| Blue / red buff | Abyssal demon (spec regen) / Fire giant (burn) |

## Champions (11)

| Champion | Role | Overheads | Signature |
| --- | --- | --- | --- |
| Dharok | Top juggernaut | No | Damage rises as health falls; rock cakes (2s cooldown, stacking) lower his own health on purpose; granite maul double spec |
| The Pure | Jungle assassin | No | 1 Defence; Sever; four DDS specs |
| Ancient Mage | Mid control mage | No | Ice/Blood/Shadow Barrage; Volatile staff |
| Hybrid | Bot/mid skirmisher | No | Range/Mage form switching; Freeze & Spec |
| Max Ranger | Bot marksman | No | Twisted bow scaling vs magic. Q/E switch between the Rapid (faster, less damage) and Longrange (range and defence, slower) attack styles, which stay on |
| Blowpiper | Bot hyper-carry | No | Escalating venom; Toxic Siphon |
| Slayer | Jungle bruiser | Yes | Monster bonus; dwarf multicannon; DWH |
| Zerker | Top/jungle diver | No | Berserker stacks; dragon claws |
| Justiciar Tank | Support/top tank | Yes | Flat damage reduction; shove; BGS |
| Lunar | Support enchanter | No | Heal Other, Vengeance Other, Energy Transfer |
| Skiller | Mid/support zone control | No | Level 3 (1 combat, 99 skilling). Damage only from skilling actions: Timber! (plant up to 3 solid yews, then chop one so it falls away from you: Farming + Woodcutting), Bonfire (Firemaking + Cooking), Harpoon (Fishing), Anvil Drop (Smithing), gem-toss basic attacks (Crafting), Level up! fireworks. Scales with **skill power** from skilling tools. |
