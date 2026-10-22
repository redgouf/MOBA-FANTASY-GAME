class_name Monster
extends Unit
## Neutral jungle monsters and epic objectives, using League of Legends
## Summoner's Rift numbers (abyssal demon = Blue Sentinel, fire giant = Red
## Brambleback, moss giant = Gromp, wolves = Murk Wolves, rooster + chickens =
## Raptors, ogres = Krugs, rock crab = Rift Scuttler, baby moles = Voidgrubs,
## Giant Mole = Rift Herald, TzTok-Jad = Baron Nashor, dragon = Elemental Drake).
## Stats given as [at start level, at level 18] are interpolated by the
## monster's level, which is the average champion level when it spawns.
## Monsters fight back when attacked and reset if pulled past their leash.

var home := Vector3.ZERO
var leash := 14.0
var camp_id := ""
var level := 1
var passive := false             # never attacks (rock crab)
var buff: Dictionary = {}        # granted to the killer
var team_buff: Dictionary = {}   # granted to the killer's whole team (epics)
var team_gold := 0               # extra gold for each member of the killer's team
var cycle_styles: Array = []     # Jad switches between melee, ranged and magic

var _cycle := 0
var _resetting := false


func init_monster(id: String, def: Dictionary, p_home: Vector3, p_camp: String, p_level: int = 1) -> void:
	unit_id = id
	team = Combat.Team.NEUTRAL
	camp_id = p_camp
	configure_from_def(def)
	apply_level(def, p_level)
	home = p_home
	leash = float(def.get("leash", 14.0))
	passive = bool(def.get("passive", false))
	buff = def.get("buff", {})
	team_buff = def.get("team_buff", {})
	team_gold = int(def.get("team_gold", 0))
	cycle_styles = def.get("cycle_styles", [])
	var color := Color(0.75, 0.45, 0.15) if is_epic else Color(0.6, 0.55, 0.4)
	setup_visuals(color, 1.2 + radius * 1.2, display_name)
	var model := str(OsrsModels.monster_config(id).get("model", "")) if OsrsModels.available() else ""
	if model != "":
		attach_osrs(OsrsActor.creature(model, radius * 2.4))


## Value of a [start, end] stat at this level (numbers pass through unchanged).
static func by_level(spec: Variant, lvl: int, start_level: int) -> float:
	if not spec is Array:
		return float(spec)
	var a: Array = spec
	if a.size() < 2:
		return float(a[0])
	var t := clampf(float(lvl - start_level) / float(maxi(18 - start_level, 1)), 0.0, 1.0)
	return lerpf(float(a[0]), float(a[1]), t)


func apply_level(def: Dictionary, p_level: int) -> void:
	var start := int(def.get("start_level", 1))
	level = clampi(p_level, start, 18)
	max_health = by_level(def.get("health", max_health), level, start)
	health = max_health
	base_damage = by_level(def.get("damage", base_damage), level, start)
	if attack_style == Combat.Style.MAGIC:
		base_magic_power = base_damage
	var armor := by_level(def.get("armor", 0.0), level, start)
	base_defence = [armor, armor, by_level(def.get("magic_resist", 0.0), level, start)]
	gold_value = int(round(by_level(def.get("gold", gold_value), level, start)))
	xp_value = int(round(by_level(def.get("xp", xp_value), level, start)))


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
		if passive:
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


func get_magic_power() -> float:
	# Jad's ranged and melee hits use the same damage value as his magic.
	return base_magic_power if base_magic_power > 0.0 else base_damage


func _reset() -> void:
	_resetting = true
	attack_target = null
	statuses.clear()
