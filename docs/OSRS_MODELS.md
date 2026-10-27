# OSRS models (private asset pack)

The game can use real OSRS models and animations from a private model pack. There are two ways to get one:

- **Build it from the game cache** with [tools/osrs_extract](../tools/osrs_extract/README.md) (recommended). It reads the same data RuneMonk and osrs.world show and exports every champion's gear, the camps and bosses, any NPC, map objects, spell graphics, textures and whole map squares.
- **The SkullSlayer pack** (the original one), which still works.

Both hold Jagex models from the OSRS game cache: **private or prototype use only; never ship or publish them**. So:

- The pack lives in `private_assets/osrs/`, which `.gitignore` excludes. Never commit it.
- Without the pack, every unit keeps its whitebox shape. Code, data and tests work either way (`--no-osrs` forces whitebox).
- The normal Windows build (`Windows Desktop` preset) excludes `private_assets/`. The `Windows Desktop (personal, OSRS models)` preset includes the pack, for your own machine only. Don't share that build.
- Don't commit screenshots of the models either.

## Building the pack with osrs_extract

```bash
python tools/osrs_extract/fetch_cache.py     # the current game cache (~250 MB, once per game update)
python tools/osrs_extract/extract.py         # writes private_assets/osrs
```

Then carry on from step 2 below. `extract.py` replaces `manifest.json`; back up a SkullSlayer pack first if you want to keep it.

## Installing the SkullSlayer pack

1. Unzip the pack and copy `manifest.json`, `player/` and `bosses/` into `private_assets/osrs/` (so `private_assets/osrs/player/player_base.glb` exists).
2. Open the project once (or run `godot --headless --path . --import`) so Godot imports the `.glb` files.
3. Bake the animation clips the game uses (about 3 MB, out of the pack's 49 MB library):

   ```bash
   godot --headless --path . -s tools/bake_osrs_clips.gd
   ```

   Re-run it whenever `data/models.json` names new clips.
4. Build the models pack and put it next to the normal exe:

   ```bash
   godot --headless --path . --export-release "Windows Desktop" build/windows/GielinorLegends.exe
   godot --headless --path . -s res://tools/pack_osrs_models.gd -- build/windows/osrs_models.pck
   ```

   `osrs_models.pck` holds only the model files (and their imported forms), minus the unused ones the personal preset leaves out. At start-up the `ModelPack` autoload loads it from the exe's folder, and the models show. Because the models aren't inside the exe, the in-game updater can swap the exe for a public release and the pack stays: the personal setup updates itself. Never publish the pack. (The old `Windows Desktop (personal, OSRS models)` preset, which builds the models into the exe, still works, but that exe can't update itself.)

## How it fits together

| Piece | What it does |
| --- | --- |
| `data/models.json` | Each champion's fixed gear and base weapon, ability clips, spec weapons, and which bosses use which model. OSRS item ids and clip names come from the pack's `manifest.json`. |
| `OsrsModels` | Finds the pack, loads models, fixes their colours (vertex colours, linear to sRGB; textured and see-through surfaces keep their texture and transparency) and loads the baked clips. A clip `models.json` names that the pack doesn't have is found by the animation id its name ends with (`a829` → 829), so the same `models.json` works with both packs. |
| `OsrsActor` | One unit's model: idle/run follow movement, attacks and abilities play one-shot clips sped up to fit the attack speed, specs swap the weapon, death plays and holds. |
| `Unit.attach_osrs()` | Replaces the whitebox shape. Champions build theirs in `Champion._setup_osrs_model()`, monsters in `Monster.init_monster()` (a variant with a model of its own, like the red dragon, uses it instead of a tint). |
| `OsrsMap` | Loads a map square (`maps/<x>_<y>.glb`, from osrs_extract) at any world tile, and its heights and object list. |

## Rules the models follow

- **Champions never change their look.** Buying items doesn't change the model.
- **Specs swap the weapon.** An item spec (or an ability tied to one in `models.json`, like the Zerker's Dragon claws ult) shows that weapon for the length of its clip, then the base weapon comes back. Two-handed spec weapons also hide the shield.
- **The Hybrid's form switch** swaps crossbow and staff, so other players can see which form it's in.
- **Stand-ins** (SkullSlayer pack only, which lacks some models): the Skiller's lumberjack outfit is missing there. With an osrs_extract pack every champion wears the real gear of their build in `champions.json`: Masori and a twisted bow on the Max Ranger, a serpentine helm and toxic blowpipe on the Blowpiper, Justiciar armour and Dinh's bulwark on the Justiciar, the Lunar outfit and staff on the Lunar.
- **Ability weapons**: an ability in `models.json` with `weapon` shows that item in the main hand for its clip, then the champion's own weapon comes back (Energy Drain swings the Pure's whip, Shove a dragon spear, Elysian Ward raises the Elysian, Timber! a dragon axe). `spec_weapons` do the same for specs and use the real item (Bandos godsword, dragon warhammer, volatile nightmare staff...).
- **Face priorities on worn items**: OSRS paints a model's faces in priority order, so a helmet's shell covers the face modelled inside it and the tree on a woodcutting cape (modelled inside the cape's back) shows over it. The extractor lifts each priority level of a worn item a few millimetres outward, and moves a covered high-priority face out in front of the surface covering it, so a depth buffer shows the same thing.
- **Decals**: OSRS draws coplanar faces (the patterns on d'hide, armour trims) in priority order; the extractor lifts each higher-priority face a few millimetres off the face under it so they don't flicker.
- **Spell graphics**: an ability or spec with `gfx` (`cast`, `travel`, `impact`, `area`) plays those OSRS spot anims instead of the drawn effects (Ice Barrage, Blood and Shadow Barrage, Ice Blitz, Tele Block, Vengeance Other, black chinchompa, the dragon dagger, claws, warhammer, granite maul and godsword specs, the Armadyl crossbow and blowpipe specs). They're drawn glowing (additive), since OSRS fades them through animation the pack can't carry.
- **Teleport Home**: `teleport` names the look-around clip (sneaky look around, 10684), the cast (714) with its graphic (111) and the landing (715).
- **Interface**: the extractor's `ui` step writes the OSRS fonts (p11, p12, b12, q8) as bitmap fonts and the hitsplat sprites; with the pack, `OsrsFont.apply()` makes p12 the font of the whole interface and hitsplats use the real sprites.
- **Held items**: a `props` entry with `item` puts an item's inventory model in a hand (the Skiller's gem bag); one with `gem` marks the hand that holds the gem he throws next, picked from the cut and uncut gem models in `gems`.
- **Depth pre-pass**: `OsrsModels.srgb_colors` rebuilds each mesh and drops its imported shadow mesh, which Forward+ draws in the depth pre-pass; keeping it made the rebuilt opaque surfaces fail the depth test and vanish.
- **Monsters:** every camp has its model in `models.json` (abyssal demon, giants, wolves, rooster and chicken, ogres, rock crab, the moles, TzTok-Jad); the chromatic dragon's variants use the real green, blue, red and black dragons and the King Black Dragon. A model the installed pack doesn't have leaves that monster whitebox (the SkullSlayer pack has Jad, the Giant Mole and the King Black Dragon).

## The map, buildings, minions and props

With a pack built by osrs_extract (v0.18.0), the match itself is dressed in OSRS models; without one, everything keeps its whitebox shape.

- **The Rift:** `rift/rift.glb` is built by the extractor's `rift` step from `tools/osrs_extract/rift_layout.json` (written from `MapLayout`, i.e. `data/map.json`, by `tools/export_rift_layout.gd`; re-run both after changing the layout). It is an OSRS tile terrain at the champions' scale (1.4 m per tile) with real Wilderness ground colours and clutter, dirt lanes, the Ditch as water, cobbles in the Saradomin base, obsidian and lava in the Zamorak base and the pits, brush plants, team gate mats, and boulders, cliffs and dead trees on the jungle walls. `MapBuilder._build_osrs_dressing()` places it and hides the whitebox ground, walls, lanes and labels. Colliders and navigation don't change.
- **Buildings:** `models.json` `structures` lists, per structure and team, the objects that make its look (`object`, and `height` or `width` in metres, optional `offset`, `rotation`, `stack` and `tint`). `OsrsProps.structure()` builds it; `Structure` uses it when it exists.
- **Minions:** `models.json` `minions` names each minion's NPC model (`by_team` for a model per team).
- **Props:** `models.json` `props` names the objects used for the dwarf multicannon (`cannon_yaw` turns it if its barrel doesn't point down -Z), the prayer altars and the Skiller's yews.
- `tools/pack_osrs_models.gd` packs only the objects and NPCs these name, plus `rift/`.


**Regenerating `data/map.json`:** `python3 -I tools/rift_classic/extract_navgrid.py <aipath.aimesh_ngrid> --out data/map.json`. The raw League file stays private (never commit it); only the derived `map.json` is in the repo.
