# Changelog

The game's **Check for updates** button reads the newest [GitHub release](https://github.com/redgouf/MOBA-FANTASY-GAME/releases); each release's notes are the matching section below.

## 0.16.0

- Champion names over the health bars are coloured by level against yours, like OSRS's right-click menu: green when lower, yellow when even, then orange and red the higher they are. The health bar colour now tells the teams apart: green for you, blue for allies, red for enemies and yellow for neutral monsters.
- New base items that build into the big ones: Leather boots, Leather chaps, Coif, Gold ring, Wizard robe and Priest gown. A new Materials tab sells the resources they're made from: Cowhide, Ball of wool, Logs, Feathers, Iron ore and Gold ore.
- Every pair of boots starts from Leather boots: Bronze → Rune → Dragon → Primordial boots, Climbing → Spiked boots, Ranger → Pegasian boots, Infinity → Eternal boots, and Boots of lightness.
- More upgrade paths: Gold ring → recoil, seers', archers', berserker ring and Lightbearer (recoil → suffering); Wizard robe → Mystic → Ahrim's or Ancestral; Leather chaps → hardleather → green d'hide → Karil's, and snakeskin → Masori; Coif → Archer helm; Priest gown → Proselyte hauberk → Justiciar.
- Parts count anywhere down a recipe: owning Leather boots makes Dragon boots 300 gp cheaper. The shop lists what an item builds into, and bots buy the parts of an item they're saving for.
- Potions: Attack and Super attack give melee Attack Damage, Strength and Super strength give melee crit chance and Crit Damage, and the Ranging potion gives ranged Attack Damage only. Combat potions mix the melee ones.
- Every champion spell and passive has an icon (OSRS items and spells: Rapid is dragon arrows, Longrange the twisted bow, Ice Barrage, Vengeance Other...), on the hotbar and in the tooltips.

## 0.15.0

- Ability tooltips are laid out like League's, for reading at a glance: the icon, "[Q] Name" and rank on the left, the cooldown and spec cost on the right, the description with each damage or heal written out ("61 = (31 +100% Damage) melee damage", coloured by type), and a rank table ("Damage [ 12 / 22 / 31 / 41 / 50 ]", "Cooldown [ ... ]") with your current rank highlighted. All tooltips use the same dark, teal-edged panel.
- Health bars and names are drawn flat on the screen at a fixed size, League style. Champions get a framed bar with their level in a badge, a tick every 50 health, the prayer bar underneath and the overhead prayer above the name, drawn on top of everything else. Minions get thin bars and no names; epic monsters and buildings show their names.
- Potions say what they do in damage terms. Strength and ranging potions give Attack Damage, magic potions Magic Damage, and attack potions crit chance and Crit Damage (crits hit for 150%, with a gold max-hit splat). Defence potions give Defence, combat potions mix these, and the Saradomin brew gives Defence but costs Attack and Magic Damage. Each has a line of flavour text, and the skill levels they boost are now just flavour, shown in the skills panel.

## 0.14.0

- Updates install themselves: the splash screen checks for a new version as it opens and, if there is one, downloads it, closes the game and reopens on the new version. Check for updates does the same in one click. An "Update automatically" box turns the automatic part off.
- The OSRS models now live in `osrs_models.pck` beside the exe instead of inside it, so a personal setup updates like everyone else's and keeps its models.

## 0.13.1

- Normal cast: right-clicking to move cancels the spell indicator again (and still moves). You can still bring an indicator up while you're walking.

## 0.13.0

- The stats panel (bottom left) shows live values: buffs and debuffs from spells, items, prayers and potions change Dmg, Magic, Atk, Range, Move and the defences at once. Raised stats turn green and lowered ones red; hover for the base value.
- Max Ranger: Rapid and Longrange are attack styles that stay on until you change them. Rapid: +30% attack speed, 15% less damage. Longrange: +2m range and +15% defence, attacks 15% slower. Cast the active one again to go back to Accurate. Each has its own buff icon (arrows and the twisted bow) and ring colour (orange and green), and no more potion-drinking animation.
- Dharok: Rock Cake has a 2s cooldown. Cakes eaten within 5s stack on the buff bar (Rock cake x1, x2, x3...), and only the first cake of a run gives the speed boost.

## 0.12.0

- Movement and orders are instant again: right-click moves the moment you click, so you can dodge.
- Spells hit the moment they're cast; their delays, multi-hits, cooldowns and effects (roots, slows, buffs) run in real time.
- Only auto attacks and food and potions stay on the 0.6s OSRS tick. Prayers switch instantly, and flicking every tick is still free.

## 0.11.2

- Potions boost their own skill, as in OSRS: attack, strength, defence, ranging and magic potions (and the super and combat versions) raise that level, shown in green in the skills panel. Each boosted level adds damage for that style, or defence. The Saradomin brew boosts Defence and lowers Attack, Strength, Ranged and Magic; a super restore restores them.
- Food and potions under level 20 (shrimps, trout, attack and strength potions, antipoison) have no 'perfect' version.
- The shop and tooltips show a consumable's normal effect, then its 'perfect' version on the next line.
- Darts (and any future arrows or knives) no longer need Fletching.

## 0.11.1

- First version published as a GitHub release, so **Check for updates** on the splash screen can find and install new versions.
- The dragon camp spawns a green, blue, red or black dragon, and from the second dragon on, 30% of the time the King Black Dragon (+60% health, +40% damage, +75% gold). Item fixes from the OSRS audit.
- Added this changelog.

## 0.11.0

- Splash screen with the version, Play, Check for updates and Quit.
- One lucky skill per build rolls up to 99 (gold star in the skills panel); the Slayer rolls 60–85 Slayer.

## 0.10.0

- Home teleport animation: look left, look right, then the OSRS teleport cast with a swirl, landing with the arrival animation. Eating, drinking and level-up effects.
- Food and potions need no level; the Cooking/Herblore level makes them Perfect (+15%).
- Non-combat skills roll 20–75.
- Skilling tools help every build; "make your own" levels let the Skiller wear combat gear.

## 0.9.1

- The OSRS 0.6s game tick for all gameplay.

## 0.9.0

- OSRS-sized damage and health, fog of war, Grand Exchange shop, buff and debuff icons, coloured tooltips, per-rank ability upgrades.
