class_name OsrsModels
extends RefCounted
## Optional OSRS models from the private SkullSlayer asset pack.
##
## The pack holds Jagex models extracted from the OSRS cache, for personal
## prototype use only: it lives in private_assets/osrs (git-ignored) and only
## the "personal" Windows build includes it. Without it, every unit keeps its
## whitebox shape, so the game, its data and its tests work either way.
## data/models.json says which gear, weapon and clips each unit uses.

const ROOT := "res://private_assets/osrs/"
const CLIPS_PATH := "res://private_assets/osrs/baked/osrs_clips.res"
const LIBRARY := "osrs"

## Tests and the --no-osrs flag turn the pack off without removing it.
static var enabled := true

static var _available: int = -1
static var _manifest: Dictionary = {}
static var _config: Dictionary = {}
static var _scenes: Dictionary = {}
static var _clips: AnimationLibrary
static var _material: StandardMaterial3D


static func available() -> bool:
	if not enabled:
		return false
	if _available < 0:
		_available = 1 if ResourceLoader.exists(ROOT + "player/player_base.glb") \
			and FileAccess.file_exists(ROOT + "manifest.json") else 0
	return _available == 1


static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(ROOT + "manifest.json"):
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	return _manifest


static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/models.json"))
		_config = parsed if parsed is Dictionary else {}
	return _config


static func champion_config(id: String) -> Dictionary:
	return config().get("champions", {}).get(id, {})


static func monster_config(id: String) -> Dictionary:
	return config().get("monsters", {}).get(id, {})


static func spec_config(item_id: String) -> Dictionary:
	return config().get("spec_weapons", {}).get(item_id, {})


static func item(id: int) -> Dictionary:
	return manifest().get("items", {}).get(str(id), {})


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(ROOT + path) if ResourceLoader.exists(ROOT + path) else null
	return _scenes[path]


## One plain material that shows the pack's per-face vertex colours (as
## imported, Godot leaves vertex colours off and every model renders white).
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		# The pack's colours are linear; srgb_colors() re-encodes each mesh's
		# colours as sRGB once, and this flag decodes them again. That renders
		# correctly in Forward+ and in the Compatibility renderer (which would
		# otherwise show the linear values far too dark).
		_material.vertex_color_is_srgb = true
		_material.roughness = 1.0
		_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _material


static func apply_material(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		srgb_colors(mi.mesh)
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static var _srgb_done: Dictionary = {}


## Re-encodes a mesh's linear vertex colours as sRGB (once per mesh resource;
## instances of the same model share it).
static func srgb_colors(mesh: Mesh) -> void:
	var am := mesh as ArrayMesh
	if am == null or _srgb_done.has(am.get_instance_id()):
		return
	_srgb_done[am.get_instance_id()] = true
	var surfaces: Array = []
	for i in am.get_surface_count():
		var arrays := am.surface_get_arrays(i)
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for k in cols.size():
			cols[k] = cols[k].linear_to_srgb()
		arrays[Mesh.ARRAY_COLOR] = cols
		surfaces.append([am.surface_get_primitive_type(i), arrays, am.surface_get_format(i),
			am.surface_get_material(i), am.surface_get_name(i)])
	am.clear_surfaces()
	for sf in surfaces:
		var flags: int = int(sf[2]) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		am.add_surface_from_arrays(sf[0], sf[1], [], {}, flags)
		var idx := am.get_surface_count() - 1
		am.surface_set_material(idx, sf[3])
		am.surface_set_name(idx, sf[4])


## A fresh weapon / gear mesh for item `id`, unparented (bind it to a skeleton).
static func gear_mesh(id: int) -> MeshInstance3D:
	var it := item(id)
	if it.is_empty():
		return null
	var ps := scene(str(it.get("file", "")))
	if ps == null:
		return null
	var root := ps.instantiate()
	var meshes := root.find_children(str(it.get("node", "gear_*")), "MeshInstance3D", true, false)
	if meshes.is_empty():
		root.free()
		return null
	var mi := meshes[0] as MeshInstance3D
	mi.get_parent().remove_child(mi)
	mi.owner = null
	root.free()
	srgb_colors(mi.mesh)
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


## The animation clips the game uses, trimmed from the pack's 516-clip
## library by tools/bake_osrs_clips.gd. Falls back to loading the full
## library (slow, development only) when the baked file is missing.
static func clips() -> AnimationLibrary:
	if _clips != null:
		return _clips
	if ResourceLoader.exists(CLIPS_PATH):
		_clips = load(CLIPS_PATH)
	else:
		_clips = build_clip_library(required_clips())
	return _clips


static func build_clip_library(names: Array[String]) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var ps := scene("player/player_animations.glb")
	if ps == null:
		return lib
	var root := ps.instantiate()
	var ap := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var info: Dictionary = manifest().get("clips", {})
	for n in names:
		if not ap.has_animation(n) or lib.has_animation(n):
			continue
		var a := ap.get_animation(n).duplicate(true) as Animation
		a.loop_mode = Animation.LOOP_LINEAR if bool(info.get(n, {}).get("loop", false)) else Animation.LOOP_NONE
		lib.add_animation(n, a)
	root.free()
	return lib


## Every clip named by data/models.json and the weapons it uses.
static func required_clips() -> Array[String]:
	var out: Array[String] = ["idle", "walk", "run"]
	var cfg := config()
	for k in ["default_cast_clip", "eat_clip", "death_clip"]:
		out.append(str(cfg.get(k, "")))
	var weapons: Array[int] = []
	for id in cfg.get("champions", {}):
		var c: Dictionary = cfg["champions"][id]
		weapons.append(int(c.get("weapon", 0)))
		for f in c.get("forms", {}).values():
			weapons.append(int(f.get("weapon", 0)))
		for ab in c.get("abilities", {}).values():
			if ab.has("clip"):
				out.append(str(ab["clip"]))
		if c.has("passive_clip"):
			out.append(str(c["passive_clip"]))
	for s in cfg.get("spec_weapons", {}).values():
		out.append(str(s.get("clip", "")))
		weapons.append(int(s.get("weapon", 0)))
	for w in weapons:
		for clip in weapon_anims(w).values():
			if clip is String:
				out.append(clip)
			elif clip is Array:
				for c2 in clip:
					out.append(str(c2))
	var unique: Array[String] = []
	for n in out:
		if n != "" and not unique.has(n):
			unique.append(n)
	return unique


## stand/walk/run/stab/slash/crush/block/special clips for a weapon (0 = unarmed).
static func weapon_anims(id: int) -> Dictionary:
	var a: Dictionary = {"stand": "idle", "walk": "walk", "run": "run", "stab": "unarmed_attack_stab_422",
		"slash": "unarmed_attack_stab_422", "crush": "unarmed_attack_crush_423", "block": "unarmed_block_424"}
	if id > 0:
		a.merge(item(id).get("animations", {}), true)
	a.merge(config().get("anim_overrides", {}).get(str(id), {}), true)
	return a
