class_name OsrsActor
extends Node3D
## A unit's OSRS model from the private asset pack, animated by game events:
## idle/run follow movement, attacks and abilities play one-shot clips, specs
## swap the weapon in the hand for the length of their clip, death holds.
## Champions are built from the bare player body plus gear (OsrsActor.player);
## bosses use their own model and clips (OsrsActor.creature).

var skeleton: Skeleton3D
var anim: AnimationPlayer
var is_player := false
var moving := false
var weapon_id := 0            # the weapon shown right now
var base_weapon := 0          # the champion's own weapon (restored after a spec)

var _anims: Dictionary = {}   # role -> clip name
var _attack_kind := "slash"   # stab / slash / crush, or "cast"
var _cast_clip := ""
var _weapons: Dictionary = {} # item id -> MeshInstance3D (cached, hidden when not held)
var _shield: MeshInstance3D
var _oneshot_left := 0.0
## Keep the last frame of the current clip until released (the teleport's
## shrunk-away pose holds until the champion actually lands at home).
var hold_end := false
var _restore_after := false
var _dead := false
var _loco := ""
var _clip_names: PackedStringArray = []
var _gem_holder: Node3D       # the hand that holds the Skiller's next gem
var _hanging: Array[Node3D] = []   # props that hang straight down from a hand (the gem bag)
var _gem_size := 0.1


## A champion: the bare player body, its gear and its weapon.
static func player(cfg: Dictionary) -> OsrsActor:
	var ps := OsrsModels.scene("player/player_base.glb")
	if ps == null:
		return null
	var a := OsrsActor.new()
	a.is_player = true
	var root := ps.instantiate()
	a.add_child(root)
	a.skeleton = root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	a.anim = root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	OsrsModels.apply_material(root)
	a.anim.add_animation_library(OsrsModels.LIBRARY, OsrsModels.clips())
	for id in cfg.get("gear", []):
		var it := OsrsModels.item(int(id))
		for part in it.get("hides_body_parts", []):
			var body := a.skeleton.get_node_or_null("body_" + (str(int(part)) if part is float or part is int else str(part)))
			if body != null:
				body.visible = false
		var mi := OsrsModels.gear_mesh(int(id))
		if mi == null:
			continue
		a.skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		if str(it.get("slot", "")) == "shield":
			a._shield = mi
	for prop in cfg.get("props", []):
		var holder := a._attach_prop(str(prop.get("bone", "")), str(prop.get("prop", "")), prop.get("offset", [0, 0, 0]), prop.get("rotation", [0, 0, 0]))
		if holder == null:
			continue
		if prop.has("item"):
			# An inventory item held in the hand (the Skiller's gem bag).
			var hang := bool(prop.get("hang", false))
			var model := OsrsModels.item_model(int(prop["item"]), float(prop.get("size", 0.2)), hang)
			if model != null:
				holder.add_child(model)
				if hang:
					a._hanging.append(holder)
		elif bool(prop.get("gem", false)):
			a._gem_holder = holder
			a._gem_size = float(prop.get("size", 0.1))
	a._cast_clip = str(OsrsModels.config().get("default_cast_clip", "magic_cast_1162"))
	a.set_base_weapon(int(cfg.get("weapon", 0)), str(cfg.get("attack", "slash")))
	return a


## A boss or monster with its own model and clips; scaled so its footprint is
## about `width` metres across.
static func creature(model: String, width: float) -> OsrsActor:
	var ps := OsrsModels.scene("bosses/%s.glb" % model)
	if ps == null:
		return null
	var a := OsrsActor.new()
	var root := ps.instantiate()
	a.add_child(root)
	a.anim = root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	OsrsModels.apply_material(root)
	for n in ["idle", "walk"]:
		if a.anim.has_animation(n):
			a.anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	a._anims = {"stand": "idle", "run": "walk"}
	var size: Array = OsrsModels.manifest().get("bosses", {}).get(model, {}).get("size", [2.0, 2.0, 2.0])
	var footprint := maxf(float(size[0]), float(size[2]))
	a.scale = Vector3.ONE * (width / maxf(footprint, 0.1))
	return a


## Recolours the whole model (the green / blue / red dragons reuse one model).
## Gives each mesh its own copy of the shared material so other instances
## keep their colours; the tint multiplies the pack's vertex colours.
func tint(color: Color) -> void:
	var mat := OsrsModels.material().duplicate() as StandardMaterial3D
	mat.albedo_color = Color(color.r * 1.9, color.g * 1.9, color.b * 1.9)
	for n in find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = mat


## Tools held in a hand that the asset pack has no model for (the Skiller's
## chisel and Imcando hammer), built from shapes and pinned to a bone.
func _attach_prop(bone: String, prop: String, offset: Array, rot: Array) -> Node3D:
	if skeleton != null and skeleton.find_bone(bone) < 0:
		bone = bone.get_slice("_", 0)     # packs from tools/osrs_extract name bones "L28", not "L28_hand_L"
	if skeleton == null or skeleton.find_bone(bone) < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var holder := Node3D.new()
	holder.position = Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
	holder.rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	att.add_child(holder)
	match prop:
		"imcando_hammer":
			_prop_part(holder, _prop_cyl(0.015, 0.26), Color(0.38, 0.25, 0.14), Vector3(0, 0.1, 0))
			_prop_part(holder, _prop_box(Vector3(0.065, 0.065, 0.14)), Color(0.42, 0.3, 0.2), Vector3(0, 0.23, 0))
			_prop_part(holder, _prop_box(Vector3(0.07, 0.02, 0.1)), Color(0.85, 0.55, 0.2), Vector3(0, 0.23, 0))
		"chisel":
			_prop_part(holder, _prop_cyl(0.018, 0.09), Color(0.42, 0.28, 0.15), Vector3(0, 0.0, 0))
			_prop_part(holder, _prop_box(Vector3(0.016, 0.14, 0.03)), Color(0.72, 0.74, 0.78), Vector3(0, 0.11, 0))
	return holder


## Shows the gem the Skiller throws next in his hand (its real OSRS model).
func hold_gem(index: int, uncut: bool) -> void:
	if _gem_holder == null:
		return
	for c in _gem_holder.get_children():
		c.queue_free()
	var model := OsrsModels.item_model(OsrsModels.gem_item(str(Projectile.GEMS[index][0]), uncut), _gem_size)
	if model != null:
		_gem_holder.add_child(model)


func has_gem_hand() -> bool:
	return _gem_holder != null


func _prop_part(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	mi.material_override = m
	parent.add_child(mi)


func _prop_cyl(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


func _prop_box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


func _ready() -> void:
	_clip_names = anim.get_animation_list()
	_update_locomotion(true)


func _full(clip: String) -> String:
	return "%s/%s" % [OsrsModels.LIBRARY, clip] if is_player else clip


func has_clip(clip: String) -> bool:
	return clip != "" and anim != null and anim.has_animation(_full(clip))


## Plays a one-shot clip, sped up to fit `max_duration` seconds when given.
## Returns false when the clip doesn't exist.
func play(clip: String, max_duration: float = 0.0) -> bool:
	if _dead or not has_clip(clip):
		return false
	var full := _full(clip)
	var length := anim.get_animation(full).length
	var speed := 1.0
	if max_duration > 0.0 and length > max_duration:
		speed = length / max_duration
	anim.play(full, 0.04, speed)
	anim.seek(0.0, true)
	_oneshot_left = length / speed
	_loco = ""
	return true


## Plays a clip up to `stop_at` seconds and freezes there until hold_end is
## cleared (the teleport freezes at its smallest, shrunk-away pose).
func play_and_hold(clip: String, stop_at: float) -> bool:
	if not play(clip):
		return false
	_oneshot_left = minf(_oneshot_left, maxf(0.05, stop_at))
	hold_end = true
	return true


## A clip's length in seconds (0 when the pack doesn't have it).
func clip_length(clip: String) -> float:
	return anim.get_animation(_full(clip)).length if has_clip(clip) else 0.0


func is_busy() -> bool:
	return _oneshot_left > 0.0


## Basic attack: the weapon's stab/slash/crush clip, or the spell cast clip.
func play_attack(interval: float, style: int = -1) -> void:
	if is_player:
		var clip := _cast_clip if _attack_kind == "cast" else str(_anims.get(_attack_kind, _anims.get("slash", "")))
		play(clip, interval * 0.9)
		return
	var choices: Array[String] = ["attack"]
	if style == Combat.Style.MAGIC:
		choices = ["attack_magic", "attack_ranged", "attack"]
	elif style == Combat.Style.RANGED:
		choices = ["attack_ranged", "attack_magic", "attack"]
	for c in choices:
		if play(c, interval * 0.9):
			return


## The champion's own weapon and attack type (Hybrid switches it with its form).
func set_base_weapon(id: int, attack: String) -> void:
	base_weapon = id
	_attack_kind = attack
	_show_weapon(id)
	_anims = OsrsModels.weapon_anims(id)
	_loco = ""


## Spec from an item (or an ability): the spec weapon replaces the held one
## (and a two-handed one hides the shield) until its clip ends.
func spec(id: int, clip: String, two_handed: bool) -> void:
	if _dead:
		return
	if id > 0:
		_show_weapon(id)
		if two_handed and _shield != null:
			_shield.visible = false
		_restore_after = true
	if not play(clip, 2.0):
		_restore_weapon()


func _show_weapon(id: int) -> void:
	for w in _weapons.values():
		(w as MeshInstance3D).visible = false
	weapon_id = id
	if _gem_holder != null:
		_gem_holder.visible = id <= 0      # the Skiller's gem hand is busy with a tool
	if id <= 0 or skeleton == null:
		return
	if not _weapons.has(id):
		var mi := OsrsModels.gear_mesh(id)
		if mi == null:
			return
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		_weapons[id] = mi
	(_weapons[id] as MeshInstance3D).visible = true


func _restore_weapon() -> void:
	_restore_after = false
	_show_weapon(base_weapon)
	if _shield != null:
		_shield.visible = true


func die() -> void:
	if _dead:
		return
	_oneshot_left = 0.0
	if _restore_after:
		_restore_weapon()
	var clip := str(OsrsModels.config().get("death_clip", "death_836")) if is_player else "death"
	if has_clip(clip):
		anim.play(_full(clip), 0.05)
	_dead = true


func revive() -> void:
	_dead = false
	_oneshot_left = 0.0
	_update_locomotion(true)


func _process(delta: float) -> void:
	# Hanging props keep upright whatever the hand does (a sack hangs by its cinch).
	for h in _hanging:
		if is_instance_valid(h) and h.is_inside_tree():
			h.global_basis = Basis(global_basis.get_rotation_quaternion()).scaled(h.global_basis.get_scale())
	if _dead or anim == null:
		return
	if _oneshot_left > 0.0:
		_oneshot_left -= delta
		if _oneshot_left > 0.0:
			return
		if hold_end:
			# Freeze on this frame (the teleport's smallest pose) until released.
			if anim.is_playing():
				anim.pause()
			_oneshot_left = 0.0001
			return
		if _restore_after:
			_restore_weapon()
	_update_locomotion(false)


func _update_locomotion(force: bool) -> void:
	var want := str(_anims.get("run" if moving else "stand", "idle"))
	if not has_clip(want):
		want = "idle" if has_clip("idle") else ""
	if want == "" or (want == _loco and not force):
		return
	_loco = want
	# Locomotion always loops (the pack marks some weapon stand/run clips,
	# like Dharok's greataxe ones, as one-shots, which froze them mid-stride).
	var a := anim.get_animation(_full(want))
	if a.loop_mode == Animation.LOOP_NONE:
		a.loop_mode = Animation.LOOP_LINEAR
	anim.play(_full(want), 0.15)
