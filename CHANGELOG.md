# Changelog

The game's **Check for updates** button reads the newest [GitHub release](https://github.com/redgouf/MOBA-FANTASY-GAME/releases); each release's notes are the matching section below.

## 0.24.0

- New shop, styled after the OSRS Grand Exchange and laid out like League's shop:
  - A search bar across the top in the GE's chatbox style, "What would you like to buy? *". Click it and type to search every tab by name; Enter picks the first match.
  - Category tabs are now OSRS icons: crossed swords (Weapons), a rune kiteshield (Defence, which was Armour), a lobster with a prayer potion (Consumables), leather boots (Boots), a pickaxe and axe (Skilling), and logs with iron ore (Materials). Hover a tab for its name.
  - Clicking an item opens it in a separate window on the right: "Builds into" along the top (click one to jump to it), then the item's recipe tree with the item at the top and its parts below, joined by lines. Parts you own are green and marked "Owned", and come off the price. Then its stats, effects and the Buy button.
  - Double-click an item to buy it, as before.
- With the OSRS pack, the shop uses the Grand Exchange's own interface art: the riveted steel border and dark trade backing, item boxes that glow when picked, GE buttons, the chatbox parchment and search icon, and the big bevelled button for Buy.

## 0.23.1

- Siege minion: the ballista now points the way the minion travels (the cart was turned the wrong way round).
- Textures flickering (z-fighting) fixed. The camera's near plane was 0.05 m, which left almost no depth precision for distant ground, so flat tiles, pebbles and rock bases flickered; it's now 3 m. Pebbles and other ground clutter are also lifted 3 cm off the terrain they sat flush on.
- The Zamorak and Saradomin standards no longer receive shadows, so the cloth and its pole stop shading themselves in stripes. They still cast shadows on the ground and the rest of the map.

## 0.23.0

- Everything moves at half speed (champions, minions and monsters) to suit the map's size. `rules.move_speed_scale` sets it.
- Towers never turn or get pushed. A beam in the tower's team colour shows what it's attacking.
- Teleport Home: the purple teleport graphic starts at the champion's chest. Purple rings build outward on the ground, up to four over the channel, so everyone nearby can see someone is teleporting.
- Health bars sit higher above champions, with the name further above the bar. The champion level (1–18) is bold, on the bar and in your portrait.
- Hitsplats always draw on top of every health bar, your own included. They're bigger, with the number in OSRS's small font sitting inside the splat, like in OSRS.
- The stats panel uses bigger text and icons, filling the panel.
- A sword cursor shows when you hover anything you can attack.
- Camera: players can zoom out 5 wheel steps from fully zoomed in. Spectators can zoom out until the whole map is on screen.
- With the OSRS pack:
  - Dark wizards stand as tall as champions, goblins are bigger, and knights are to scale.
  - Dark wizards finish their casting wind-up before their spell leaves their hands. The hit still lands on time.
  - The siege minion is the gnome ballista from the Tree Gnome Village instead of the cannon cart.

## 0.22.1

- Teleport Home: the champion now teleports at the moment the OSRS teleport animation has shrunk them away. It no longer grows back to full size first. The cast is timed to the teleport, holds the smallest pose until the champion lands, and the landing animation grows them back at home.
- The "Teleporting home" and "Praying at the altar" text is bigger and bold, and the stray symbol after "home" is gone.
- The splash screen text is bold (with the OSRS pack).

## 0.22.0

- Fixed: faces and ears no longer poke through helmets (Dharok's helm, berserker helm and others), and the tree logo shows on the back of the Skiller's woodcutting cape. OSRS draws an item's parts in a set order instead of by depth; the extracted models now make up for that.
- The Skiller grips his gem bag by its drawstring.
- With the OSRS pack, the stats panel uses OSRS parts: the stone interface background and OSRS skill icons for each stat (hover an icon for its name).
- The text on the health, prayer and special attack bars, and the names over champions, use the bold OSRS font, centred on the whole bar.
- The portrait in the stats panel is closer: head and chest fill the frame.

## 0.21.0

- The map walls now run right beside the top and bottom lanes all the way round (the map is 180 m across instead of 200 m). Top and bottom lane towers stand on the outer edge of their lane, against the wall, leaving the lane open.
- Spectating: switching to a champion on the other team flips the fog of war to their team straight away. You no longer have to press F twice.
- Teleport Home takes 8 seconds. The champion spends most of it looking around sneakily (an OSRS animation), then casts the normal OSRS teleport with its graphics.
- The combat level now follows each champion's name ("Dharok (level-112)"), coloured like OSRS's right-click menu: green for lower than yours, yellow for the same, orange to red for higher. The game level (1–18) stays in the circle.
- Your champion's portrait, looking right, is shown in the stats panel.
- The two-letter tags on champions' chests and backs are gone.
- Shadows are softer on thin models like capes and the team standards.
- With the OSRS pack:
  - The whole interface uses the real OSRS fonts, with OSRS-style drop shadows.
  - Hitsplats use the real OSRS sprites: damage, blocked hits, max hits, poison, venom and burn, with darker ones for hits that don't involve you.
  - Spells and specs show their OSRS graphics: Ice, Blood and Shadow Barrage, Ice Blitz, Tele Block, Vengeance Other and the black chinchompa, and the dragon dagger, dragon claws, dragon warhammer, granite maul, godsword, Armadyl crossbow and toxic blowpipe specs.
  - The Skiller holds his gem bag by its drawstring, hanging straight down.

## 0.20.0

- Abilities named for a weapon now show it in the champion's hand for the swing, then their own weapon comes back:
  - The Pure swings an abyssal whip for Energy Drain, and still a dragon dagger for Puncture.
  - The Justiciar shoves with a dragon spear and raises the Elysian spirit shield for Elysian Ward.
  - The Max Ranger throws a black chinchompa.
  - The Skiller swings a dragon axe for Timber!, a dragon harpoon for Harpoon and an Imcando hammer for Anvil Drop.
- Specs use their real weapons: the Bandos, Saradomin and Zamorak godswords (not all the Armadyl godsword), the dragon warhammer, the volatile nightmare staff, the Armadyl crossbow, the magic shortbow (i), the toxic staff of the dead, the dragon axe and Voidwaker.
- Weapons match their descriptions: the Hybrid holds an Armadyl crossbow (it was a dragon crossbow), and the Slayer holds an abyssal tentacle (it was a whip).
- Fixed: the Skiller's gem bag and gems were missing from the personal build, so his hands looked empty.
- Fixed: patterns on some armour (black d'hide chaps) flickered.
- Champions are clean-shaven, so beards no longer poke out through helmets.

## 0.19.0

- Fixed: with the OSRS pack on Windows, most of the map was invisible (the ground, rocks, towers and buildings), leaving only see-through bits like lava edges. The models were drawn in two passes that no longer matched, so the second pass hid them.
- The jungle walls use grey Wilderness boulders only; the gold rock clusters are gone.
- Four champions that wore stand-in gear now wear their real builds:
  - Max Ranger: Masori armour, a twisted bow, Ava's assembler, necklace of anguish, Zaryte vambraces and Pegasian boots.
  - Blowpiper: a serpentine helm, black d'hide, Ava's accumulator and a toxic blowpipe, with the blowpipe's own attack and special animations.
  - Justiciar: Justiciar armour, guardian boots and Dinh's bulwark, which he swings, shoves with (Q) and braces behind (E).
  - Lunar: the full Lunar outfit and Lunar staff, with Lunar spell animations (Vengeance Other, Energy Transfer, group spells).
- The Skiller no longer holds an Imcando hammer. He carries a gem bag in one hand and a gem in the other. He throws that gem, and a new random one, cut or uncut, appears in his hand. Every gem is its real OSRS model, from opal to zenyte.

## 0.18.0

- Fixed: champions' shirts, trousers and hair no longer show through their armour, helmets and capes. Worn items hide the body parts they cover again.
- With the private OSRS pack, the whole match now uses OSRS models instead of whitebox shapes:
  - The map is real OSRS ground: Wilderness earth and ground clutter, dirt lanes, the Wilderness Ditch as water, a cobbled Saradomin base, an obsidian and lava Zamorak base, lava-ringed epic pits, statues of Saradomin and Zamorak, and boulders, lava rocks and dead trees on every jungle wall and around the edge. The colliders and paths are unchanged.
  - Towers, inhibitors, the nexus towers, altars and the team standards are OSRS buildings (castle towers and dark obelisks, Soul Wars obelisks, Saradomin and chaos altars, Castle Wars standards).
  - Minions are goblins, dark wizards, and white or black knights.
  - The Slayer's cannon and the siege carts carry a real dwarf multicannon, prayer altars are real altars, and the Skiller plants real yews.
- Without the pack everything stays the way it was.
- The OSRS models are private and never part of the public build.

## 0.17.0

- New tool, `tools/osrs_extract`: builds the private OSRS model pack straight from the game cache, the same data RuneMonk and osrs.world show. It exports every champion's gear on one shared skeleton with their animations, any NPC with its own animations, map objects, spell and spec graphics, all textures and sprites, and whole OSRS map squares (terrain, floor textures, walls, scenery and roofs, with heights and object lists). See `tools/osrs_extract/README.md`.
- With a pack built by the tool: the Skiller wears his lumberjack outfit and woodcutting cape and swings a real Imcando hammer, every jungle camp shows its OSRS monster (abyssal demon, fire and moss giants, wolves, rooster and chicken, ogres, rock crab, baby moles), and the chromatic dragon is a real green, blue, red or black dragon instead of a tinted King Black Dragon.
- Textured and see-through parts of OSRS models (capes, ghosts, map floors) keep their textures and transparency.
- The OSRS models are private and never part of the public build.

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
