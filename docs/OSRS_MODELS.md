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
- **Stand-ins** (SkullSlayer pack only, which lacks some models): the Skiller's lumberjack outfit and Imcando hammer are missing there, so he shows the bare body holding only his chisel prop. With an osrs_extract pack every champion wears the gear in `champions.json`.
- **Monsters:** every camp has its model in `models.json` (abyssal demon, giants, wolves, rooster and chicken, ogres, rock crab, the moles, TzTok-Jad); the chromatic dragon's variants use the real green, blue, red and black dragons and the King Black Dragon. A model the installed pack doesn't have leaves that monster whitebox (the SkullSlayer pack has Jad, the Giant Mole and the King Black Dragon). Minions and structures stay whitebox for now; osrs_extract already exports Pest Control monsters and portals for them.
