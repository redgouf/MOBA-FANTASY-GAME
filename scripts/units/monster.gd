class_name Monster
extends Unit
## Neutral jungle monsters and epic objectives (TzTok-Jad, chromatic dragons).
## They fight back when attacked and reset if pulled past their leash.

var home := Vector3.ZERO
var leash := 14.0
var camp_id := ""
var buff: Dictionary = {}        # granted to the killer
var team_buff: Dictionary = {}   # granted to the killer's whole team (epics)
var cycle_styles: Array = []     # Jad switches between melee, ranged and magic

var _cycle := 0
var _resetting := false


func init_monster(id: String, def: Dictionary, p_home: Vector3, p_camp: String) -> void:
	unit_id = id
	team = Combat.Team.NEUTRAL
	camp_id = p_camp
	configure_from_def(def)
	home = p_home
	leash = float(def.get("leash", 14.0))
	buff = def.get("buff", {})
	team_buff = def.get("team_buff", {})
	cycle_styles = def.get("cycle_styles", [])
	var color := Color(0.75, 0.45, 0.15) if is_epic else Color(0.6, 0.55, 0.4)
	setup_visuals(color, 1.2 + radius * 1.2, display_name)


func _ready() -> void:
	super()
	add_to_group("monsters")
	damaged.connect(_on_damaged)


func is_damageable() -> bool:
	return not is_dead and not _resetting


func _on_damaged(_unit: Unit, _amount: float, source: Unit) -> void:
	if source != null and not _resetting and (not is_instance_valid(attack_target) or attack_target.is_dead):
		attack_target = source


func _unit_process(delta: float) -> void:
	if _resetting:
		move_directly_toward(home)
		heal(max_health * 0.5 * delta)
		if flat_distance(global_position, home) < 0.8:
			_resetting = false
			health = max_health
			velocity = Vector3.ZERO
		return
	if is_instance_valid(attack_target) and not attack_target.is_dead:
		if flat_distance(global_position, home) > leash or flat_distance(attack_target.global_position, home) > leash + 4.0:
			_reset()
			return
		if in_attack_range(attack_target):
			velocity = Vector3.ZERO
		else:
			move_directly_toward(attack_target.global_position)
		process_attack(delta)
	else:
		attack_target = null
		if flat_distance(global_position, home) > 0.8:
			_reset()


func perform_attack(t: Unit) -> void:
	if not cycle_styles.is_empty():
		attack_style = Combat.style_from_string(str(cycle_styles[_cycle % cycle_styles.size()]))
		_cycle += 1
		# Telegraph the NEXT attack style so players can switch protection prayers in time.
		var upcoming := str(cycle_styles[_cycle % cycle_styles.size()])
		set_label("%s (next: %s)" % [display_name, upcoming])
	super(t)


func _reset() -> void:
	_resetting = true
	attack_target = null
	statuses.clear()
