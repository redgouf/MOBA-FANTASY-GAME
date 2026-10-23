# OSRS models (private asset pack)

The game can use real OSRS models and animations from the SkullSlayer asset pack. The pack holds Jagex models extracted from the OSRS game cache and its own terms say **private or prototype use only; never ship or publish it**. So:

- The pack lives in `private_assets/osrs/`, which `.gitignore` excludes. Never commit it.
- Without the pack, every unit keeps its whitebox shape. Code, data and tests work either way (`--no-osrs` forces whitebox).
- The normal Windows build (`Windows Desktop` preset) excludes `private_assets/`. The `Windows Desktop (personal, OSRS models)` preset includes the pack, for your own machine only. Don't share that build.
- Don't commit screenshots of the models either.

## Installing the pack

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
| `OsrsModels` | Finds the pack, loads models, fixes their colours (vertex colours, linear to sRGB) and loads the baked clips. |
| `OsrsActor` | One unit's model: idle/run follow movement, attacks and abilities play one-shot clips sped up to fit the attack speed, specs swap the weapon, death plays and holds. |
| `Unit.attach_osrs()` | Replaces the whitebox shape. Champions build theirs in `Champion._setup_osrs_model()`, monsters in `Monster.init_monster()`. |

## Rules the models follow

- **Champions never change their look.** Buying items doesn't change the model.
- **Specs swap the weapon.** An item spec (or an ability tied to one in `models.json`, like the Zerker's Dragon claws ult) shows that weapon for the length of its clip, then the base weapon comes back. Two-handed spec weapons also hide the shield.
- **The Hybrid's form switch** swaps crossbow and staff, so other players can see which form it's in.
- **Stand-ins** where the pack has no model: Max Ranger (Karil's, magic shortbow), Blowpiper (d'hide, magic shortbow), Justiciar Tank (Torag's, spirit shield, rune scimitar), Lunar (mystic robes, ancient staff). The other godswords use the AGS model; the Dragon warhammer and Voidwaker specs play their animation with the base weapon.
- **Bosses:** TzTok-Jad, the Giant Mole (and baby moles) and the King Black Dragon standing in for the chromatic dragons. Other camps, minions and structures stay whitebox.
