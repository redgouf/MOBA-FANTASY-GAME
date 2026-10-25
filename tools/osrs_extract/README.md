# osrs_extract: OSRS models, animations, textures and maps from the game cache

Builds the private model pack the game reads (`private_assets/osrs/`) straight from the Old School RuneScape game cache, the same data [RuneMonk](https://runemonk.com) and [osrs.world](https://osrs.world) show. Python 3.9 or newer, standard library only (previews need numpy and Pillow).

**Everything it writes is Jagex's material.** It stays on your machine, like the SkullSlayer pack: never commit it, never put it in a public build or release. `private_assets/` and `tools/osrs_extract/cache/` are for your own use only.

## Use

```bash
python tools/osrs_extract/fetch_cache.py          # once per game update: ~250 MB into tools/osrs_extract/cache/
python tools/osrs_extract/extract.py              # everything in recipe.json + what data/models.json uses
godot --headless --path . --import                # Godot imports the new .glb files
godot --headless --path . -s tools/bake_osrs_clips.gd
```

Then build `osrs_models.pck` as in [docs/OSRS_MODELS.md](../../docs/OSRS_MODELS.md).

`fetch_cache.py --source github` clones [abextm/osrs-cache](https://github.com/abextm/osrs-cache) instead (a flat cache, updated every game update; needs git). Any client cache folder works too: `extract.py --cache PATH` takes a folder with `main_file_cache.dat2` and `.idx` files, or a flat cache.

Useful options:

| Option | What it does |
| --- | --- |
| `--only player,npcs` | Run some steps: `player`, `npcs`, `objects`, `spotanims`, `items`, `textures`, `maps`, and `sprites` (only when named) |
| `--npc slug=id` | One more NPC, saved as `bosses/<slug>.glb` |
| `--object id`, `--item id` | One more map object, or worn item |
| `--region 50_50` or `--region 12850` | One more map square (64x64 tiles; region id = x*256 + y) |
| `--all-wearables` | Every worn item in the game (about 6,000; large) |
| `--out DIR` | Write somewhere other than `private_assets/osrs` |

## What it makes

| Path | What |
| --- | --- |
| `manifest.json` | Items (file, slot, which body parts they hide, weapon stance and attack clips), clips, `clip_ids` (animation id → clip name), bosses (size, clips), objects, spot anims, maps |
| `player/player_base.glb` | The default male body, one `body_<part>` mesh per kit (0 hair, 1 jaw, 2 torso, 3 arms, 4 hands, 5 legs, 6 feet), on a 119-bone skeleton |
| `player/player_animations.glb` | Every player clip, named `<game name>_<animation id>` (`slayer_abyssal_whip_attack_1658`), plus `idle`, `walk`, `run` |
| `player/items/<id>.glb` | A worn item on the same skeleton (node `gear_<id>`) |
| `bosses/<slug>.glb` | An NPC with its own skeleton: `idle`, `walk`, `run`, `attack`, `attack_magic`, `attack_ranged`, `block`, `death` where they exist, plus the animations named after it |
| `objects/<id>.glb` | A map object (scenery), animated if it has an animation |
| `spotanims/<id>.glb` | A spell or spec graphic with its animation (`play`) |
| `items/<id>.glb` | An item's ground / inventory model (`inventory_items` in the recipe) |
| `textures/<id>.png` | All 215 ground and model textures |
| `sprites/<id>.png` | Every UI sprite (with `--only sprites`) |
| `maps/<x>_<y>.glb` + `.json` | A map square: terrain with blended ground colours, tile shapes and floor textures, walls, decorations, scenery and roofs, one `level_N` node per floor (`terrain_N`, `objects_N`, `roofs_N`). The JSON has corner heights in metres, tile flags and every object placed (id, tile, level, shape, rotation, name) |

Units: 1 tile = 1 metre, y up; on maps east = +X and north = -Z, the square's south-west corner at the origin. `OsrsMap` (scripts/map/osrs_map.gd) places squares relative to any world tile.

## The recipe

`recipe.json` lists what to export besides what `data/models.json` needs. Ids are OSRS ids; strings can be `gv:<internal name>` (the game's own name for it, like `gv:yewtree`), `name:<Display name>`, or `re:<regex>` over internal names (every match). An NPC can name its clips by animation id: `"torag": {"id": 1676, "attack": 2068}`. Weapon stances and attacks come from `osrsx/weapons.py` (the server picks them in OSRS, so the cache doesn't say which weapon uses which).

## How it works

`osrsx/` reads the cache (`cache.py`), decodes NPCs, items, objects, kits, animations, spot anims and floors (`defs.py`), models (`model.py`), textures and sprites (`textures.py`), and writes glTF (`gltf.py`, `export.py`). OSRS animates a model by moving groups of vertices ("labels"); each label becomes a bone, and every frame's transform of each label becomes that bone's keyframe (`anim.py`), so clips play on a normal skeleton in Godot. Map squares (`mapexport.py`) follow the client's scene builder: height noise, underlay blending, the 13 tile shapes, and object placement by shape and rotation, including wall decorations and ground contouring.

Decoders are ported from [rs-map-viewer](https://github.com/dennisdev/rs-map-viewer) (osrs.world) and [osrscachereader](https://github.com/Dezinater/osrscachereader) (RuneMonk), both BSD-2-Clause. Game data © Jagex.

## Limits

- Newer "skeletal" animations (about 7% of them, mostly recent bosses) are skipped for now; classic frame animations all work.
- Interpolation between frames is linear; the client steps. Faces that animate their colour or transparency keep their first look.
- Map lighting is left to Godot (the client bakes it into colours), and animated textures (water, lava) don't scroll yet.
- `player_base` is the default male body; female bodies and other kits aren't exported yet.
