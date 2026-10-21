class_name Minion
extends Unit
## Lane minions (goblins, dark wizards, dwarf cannon carts) that walk a lane
## and fight whatever enemy is nearest.

const AGGRO_RANGE := 8.0
const LEASH_RANGE := 11.0

var lane := ""
var path: PackedVector3Array = PackedVector3Array()
var waypoint := 1
var offset := Vector3.ZERO

var _scan := 0.0


func init_minion(id: String, def: Dictionary, p_team: int, p_lane: String, p_path: PackedVector3Array) -> void:
	unit_id = id
	team = p_team
	lane = p_lane
	path = p_path
	configure_from_def(def)
	offset = Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	var color := Unit.team_color(team).darkened(0.25)
	match id:
		"cannon_cart":
			setup_visuals(color, 1.4, "", "box")
		"dark_wizard":
			setup_visuals(color.lightened(0.2), 1.6, "")
		_:
			setup_visuals(color, 1.2, "")


func _ready() -> void:
	super()
	add_to_group("minions")


func _unit_process(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.3
		_acquire_target()
	if is_instance_valid(attack_target) and not attack_target.is_dead:
		if in_attack_range(attack_target):
			velocity = Vector3.ZERO
		else:
			move_directly_toward(attack_target.global_position)
	else:
		_walk_lane()
	process_attack(delta)


func _acquire_target() -> void:
	if is_instance_valid(attack_target) and not attack_target.is_dead and attack_target.is_damageable() \
			and flat_distance_to(attack_target) < LEASH_RANGE:
		return
	attack_target = find_nearest_enemy(AGGRO_RANGE, true, false)


func _walk_lane() -> void:
	if waypoint >= path.size():
		velocity = Vector3.ZERO
		return
	var p := path[waypoint] + offset
	if flat_distance(global_position, p) < 2.0:
		waypoint += 1
		return
	move_directly_toward(p)
