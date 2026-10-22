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
var _restore_after := false
var _dead := false
var _loco := ""
var _clip_names: PackedStringArray = []


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
			var body := a.skeleton.get_node_or_null("body_" + str(part))
			if body != null:
				body.visible = false
		var mi := OsrsModels.gear_mesh(int(id))
		if mi == null:
			continue
		a.skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		if str(it.get("slot", "")) == "shield":
			a._shield = mi
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
	if _dead or anim == null:
		return
	if _oneshot_left > 0.0:
		_oneshot_left -= delta
		if _oneshot_left > 0.0:
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
	anim.play(_full(want), 0.15)
