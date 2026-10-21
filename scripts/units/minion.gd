class_name Minion
extends Unit
## Lane minions, using League of Legends Summoner's Rift numbers:
##   goblin = melee minion, dark wizard = caster minion,
##   dwarf cannon cart = siege minion, knight = super minion.
## Stats come from the minion "upgrade" count (one at 0:30, then one every
## 90 s), as [base, per_upgrade, cap] (damage adds [late_per_upgrade, from]).

const AGGRO_RANGE := 8.0
const LEASH_RANGE := 11.0

var lane := ""
var role := "melee"              # melee / caster / siege / super
var upgrades := 0
var path: PackedVector3Array = PackedVector3Array()
var waypoint := 1
var offset := Vector3.ZERO
var bonus_vs_minions := 0.0

var _scan := 0.0


func init_minion(id: String, def: Dictionary, p_team: int, p_lane: String, p_path: PackedVector3Array, p_upgrades: int = 0) -> void:
	unit_id = id
	team = p_team
	lane = p_lane
	path = p_path
	role = str(def.get("role", "melee"))
	configure_from_def(def)
	var team_names: Array = def.get("names_by_team", [])
	if p_team < team_names.size():
		display_name = str(team_names[p_team])
	apply_upgrades(def, p_upgrades)
	bonus_vs_minions = float(def.get("bonus_vs_minions_pct_current", 0.0))
	offset = Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	var color := Unit.team_color(team).darkened(0.25)
	match role:
		"siege":
			setup_visuals(color, 1.4, "", "box")
		"caster":
			setup_visuals(color.lightened(0.2), 1.6, "")
		"super":
			setup_visuals(color.lightened(0.35), 2.2, "")
		_:
			setup_visuals(color, 1.2, "")


## Stat value after n upgrades from [base, per_upgrade, cap, late_per_upgrade?, late_from?].
static func scaled(spec: Variant, n: int) -> float:
	if not spec is Array:
		return float(spec)
	var a: Array = spec
	var base := float(a[0])
	var per := float(a[1]) if a.size() > 1 else 0.0
	var cap := float(a[2]) if a.size() > 2 else INF
	var value := base + per * float(n)
	if a.size() > 4:
		var late_from := int(a[4])
		if n > late_from:
			value = base + per * float(late_from) + float(a[3]) * float(n - late_from)
	return minf(value, cap)


func apply_upgrades(def: Dictionary, n: int) -> void:
	upgrades = n
	max_health = scaled(def.get("health", max_health), n)
	health = max_health
	base_damage = scaled(def.get("damage", base_damage), n)
	if attack_style == Combat.Style.MAGIC:
		base_magic_power = base_damage
	var armor := scaled(def.get("armor", 0.0), n)
	base_defence = [armor, armor, scaled(def.get("magic_resist", 0.0), n)]
	gold_value = int(scaled(def.get("gold", gold_value), n))


func _ready() -> void:
	super()
	add_to_group("minions")


## Minions deal 60% damage to champions and structures (siege: 84% to structures),
## and bonus damage to other minions based on their current health.
func modify_outgoing(info: DamageInfo, target: Unit) -> void:
	super(info, target)
	var rules: Dictionary = GameData.units.get("minion_rules", {})
	if target is Champion:
		info.amount *= float(rules.get("damage_to_champions_mult", 0.6))
	elif target is Structure and (target as Structure).is_structure():
		var key := "siege_damage_to_structures_mult" if role == "siege" else "damage_to_structures_mult"
		info.amount *= float(rules.get(key, 0.6))
	elif target is Minion and bonus_vs_minions > 0.0:
		info.amount += target.health * bonus_vs_minions


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
