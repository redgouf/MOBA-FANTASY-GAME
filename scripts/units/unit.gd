class_name Unit
extends CharacterBody3D
## Base class for everything that has health and can fight:
## champions, minions, structures, jungle monsters and summons.

signal died(unit: Unit, killer: Unit)
signal damaged(unit: Unit, amount: float, source: Unit)

const LAYER_WALLS := 1
const LAYER_UNITS := 2
const LAYER_GROUND := 4

var team: int = Combat.Team.NEUTRAL
var unit_id := ""
var display_name := "Unit"

var max_health := 100.0
var health := 100.0
var base_damage := 0.0
var base_magic_power := 0.0
var base_defence: Array[float] = [0.0, 0.0, 0.0]   # indexed by Combat.Style
var attack_style: int = Combat.Style.MELEE
var base_attack_range := 2.0
var attack_ticks := 4.0
var bonus_attack_speed := 0.0
var base_move_speed := 5.0
var armor_pen := 0.0
var radius := 0.5
var gold_value := 0
var xp_value := 0
var is_epic := false
var is_dead := false

var attack_target: Unit = null
## id -> {kind, amount, remaining, permanent, source, data, tick}
var statuses: Dictionary = {}
## instance_id -> {unit, time} — used for assists and tower aggro.
var recent_attackers: Dictionary = {}

var _attack_cooldown := 0.0
var _height := 2.0
var _model: MeshInstance3D
var _health_bar: HealthBar3D
var _name_label: Label3D

var _dashing := false
var _dash_target := Vector3.ZERO
var _dash_speed := 0.0
var _dash_ignore_walls := false


func _ready() -> void:
	collision_layer = LAYER_UNITS
	collision_mask = LAYER_WALLS
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("units")
	add_to_group("team_%d" % team)


# --- Setup -------------------------------------------------------------------

## Reads a unit definition. Accepts both our native fields and League-style ones:
##   max_health | health          (a number, or [start, ...] for scaling units)
##   defence {melee, ranged, magic} | armor + magic_resist (armor covers melee and ranged)
##   attack_ticks | attack_speed  (attacks per second)
##   attack_range | attack_range_lol, move_speed | move_speed_lol  (LoL units)
## Minions and monsters then apply their own upgrade/level scaling on top.
func configure_from_def(def: Dictionary) -> void:
	display_name = str(def.get("name", display_name))
	attack_style = Combat.style_from_string(str(def.get("style", "melee")))
	max_health = float(first_value(def.get("max_health", def.get("health", 100.0))))
	health = max_health
	base_damage = float(first_value(def.get("damage", 0.0)))
	if def.has("magic_power"):
		base_magic_power = float(def["magic_power"])
	else:
		base_magic_power = base_damage if attack_style == Combat.Style.MAGIC else 0.0
	if def.has("defence"):
		var d: Dictionary = def["defence"]
		base_defence = [float(d.get("melee", 0.0)), float(d.get("ranged", 0.0)), float(d.get("magic", 0.0))]
	else:
		var armor := float(first_value(def.get("armor", 0.0)))
		base_defence = [armor, armor, float(first_value(def.get("magic_resist", 0.0)))]
	if def.has("attack_range_lol"):
		base_attack_range = lol_to_meters(float(def["attack_range_lol"]))
	else:
		base_attack_range = float(def.get("attack_range", 2.0))
	if def.has("attack_speed"):
		attack_ticks = 1.0 / (maxf(float(def["attack_speed"]), 0.01) * Combat.tick_seconds)
	else:
		attack_ticks = float(def.get("attack_ticks", 4.0))
	if def.has("move_speed_lol"):
		base_move_speed = lol_to_meters(float(def["move_speed_lol"]))
	else:
		base_move_speed = float(def.get("move_speed", 5.0))
	radius = float(def.get("radius", 0.5))
	gold_value = int(first_value(def.get("gold", 0)))
	xp_value = int(first_value(def.get("xp", 0)))
	is_epic = bool(def.get("epic", false))


## League of Legends distance units -> metres (our map is ~200 m, Summoner's Rift ~14,870 units).
static func lol_to_meters(units: float) -> float:
	return units / float(GameData.rule("lol_units_per_meter", 75.0))


static func first_value(v: Variant) -> Variant:
	return v[0] if v is Array and not (v as Array).is_empty() else v


static func team_color(p_team: int) -> Color:
	match p_team:
		Combat.Team.SARADOMIN:
			return Color(0.32, 0.56, 1.0)
		Combat.Team.ZAMORAK:
			return Color(0.92, 0.26, 0.2)
	return Color(0.86, 0.74, 0.3)


## Whitebox visuals: a primitive mesh, a floating health bar and a name tag.
func setup_visuals(color: Color, height: float, label: String, mesh_kind: String = "capsule") -> void:
	_height = height
	var col := CollisionShape3D.new()
	var mesh: PrimitiveMesh
	match mesh_kind:
		"box":
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(radius * 2.0, height, radius * 2.0)
			col.shape = box_shape
			var box := BoxMesh.new()
			box.size = box_shape.size
			mesh = box
		"cylinder":
			var cyl_shape := CylinderShape3D.new()
			cyl_shape.radius = radius
			cyl_shape.height = height
			col.shape = cyl_shape
			var cyl := CylinderMesh.new()
			cyl.top_radius = radius * 0.6
			cyl.bottom_radius = radius
			cyl.height = height
			mesh = cyl
		_:
			var cap_shape := CapsuleShape3D.new()
			cap_shape.radius = radius
			cap_shape.height = maxf(height, radius * 2.0 + 0.01)
			col.shape = cap_shape
			var cap := CapsuleMesh.new()
			cap.radius = radius
			cap.height = cap_shape.height
			mesh = cap
	col.position.y = height * 0.5
	add_child(col)

	_model = MeshInstance3D.new()
	_model.mesh = mesh
	_model.position.y = height * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_model.material_override = mat
	add_child(_model)

	_health_bar = HealthBar3D.new()
	_health_bar.position.y = height + 0.5
	add_child(_health_bar)
	_health_bar.setup(team_color(team), clampf(radius * 2.4, 1.0, 4.0))

	if label != "":
		_name_label = Label3D.new()
		_name_label.text = label
		_name_label.position.y = height + 0.95
		_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_name_label.no_depth_test = true
		_name_label.font_size = 28
		_name_label.pixel_size = 0.01
		_name_label.outline_size = 8
		add_child(_name_label)


func visual_height() -> float:
	return _height


func set_label(text: String) -> void:
	if _name_label:
		_name_label.text = text


# --- Stats -------------------------------------------------------------------

func get_damage() -> float:
	return base_damage


func get_magic_power() -> float:
	return base_magic_power


func get_defence(style: int) -> float:
	return base_defence[style] * maxf(0.0, 1.0 + status_sum("armor_mult")) + status_sum("armor_flat")


func get_attack_range() -> float:
	return base_attack_range + status_sum("range_bonus")


func get_attack_interval() -> float:
	var speed := maxf(0.2, 1.0 + bonus_attack_speed + status_sum("attack_speed"))
	return Combat.ticks_to_seconds(attack_ticks) / speed


func get_move_speed() -> float:
	if not can_move():
		return 0.0
	var slow := minf(status_sum("slow"), 0.9)
	return base_move_speed * maxf(0.1, 1.0 + status_sum("haste") - slow)


func can_act() -> bool:
	return not is_dead and not has_status("stun")


func can_move() -> bool:
	return can_act() and not has_status("root") and not has_status("planted")


func is_damageable() -> bool:
	return not is_dead


func is_structure() -> bool:
	return false


func is_enemy_of(other: Unit) -> bool:
	return other != null and other.team != team


## The defender's active protection prayer (Combat.Style) or -1.
func get_protected_style() -> int:
	return -1


func health_ratio() -> float:
	return health / max_health if max_health > 0.0 else 0.0


# --- Status effects ------------------------------------------------------------

func add_status(id: String, kind: String, amount: float, duration: float,
		source: Unit = null, data: Dictionary = {}) -> void:
	if is_dead:
		return
	if kind == "root":
		# OSRS freeze immunity: a root grants a few seconds of root immunity after it.
		if has_status("root_immune"):
			return
		add_status("root_immune", "root_immune", 0.0, duration + 3.0)
	var st := {
		"kind": kind, "amount": amount, "remaining": duration, "permanent": duration < 0.0,
		"source": source, "data": data, "tick": 1.0,
	}
	if kind == "venom" and statuses.has(id):
		st["amount"] = statuses[id]["amount"]   # re-applying venom keeps its escalation
	statuses[id] = st


func remove_status(id: String) -> void:
	statuses.erase(id)


func has_status(kind: String) -> bool:
	for st in statuses.values():
		if st["kind"] == kind:
			return true
	return false


func find_status_id(kind: String) -> String:
	for id in statuses:
		if statuses[id]["kind"] == kind:
			return id
	return ""


func status_sum(kind: String) -> float:
	var total := 0.0
	for st in statuses.values():
		if st["kind"] == kind:
			total += float(st["amount"])
	return total


func _tick_statuses(delta: float) -> void:
	var expired: Array[String] = []
	var dots: Array[DamageInfo] = []
	for id in statuses:
		var st: Dictionary = statuses[id]
		match st["kind"]:
			"venom", "burn", "poison":
				st["tick"] -= delta
				if st["tick"] <= 0.0:
					st["tick"] += 1.0
					var src: Node = st["source"] if is_instance_valid(st["source"]) else null
					var dot := DamageInfo.make(float(st["amount"]), Combat.Style.MAGIC, src)
					dot.is_true = true
					dot.label = st["kind"]
					dots.append(dot)
					if st["kind"] == "venom":
						var data: Dictionary = st["data"]
						st["amount"] = minf(float(st["amount"]) + float(data.get("step", 2.0)), float(data.get("max", 20.0)))
			"heal_over_time":
				heal(float(st["amount"]) * delta)
			"taunt":
				var taunter: Variant = st["source"]
				if is_instance_valid(taunter) and not taunter.is_dead:
					attack_target = taunter
		if not st["permanent"]:
			st["remaining"] -= delta
			if st["remaining"] <= 0.0:
				expired.append(id)
	for id in expired:
		statuses.erase(id)
	for dot in dots:
		if is_dead:
			break
		take_damage(dot)


# --- Damage ------------------------------------------------------------------

func take_damage(info: DamageInfo) -> float:
	if not is_damageable():
		return 0.0
	var src: Unit = null
	if is_instance_valid(info.source) and info.source is Unit:
		src = info.source
	if not info.is_true:
		if info.style == Combat.Style.MELEE and has_status("melee_immune"):
			_spawn_hitsplat(0.0, info)
			return 0.0
		var negate := find_status_id("negate_hit")
		if negate != "":
			statuses.erase(negate)
			_spawn_hitsplat(0.0, info)
			return 0.0

	var def_style := -1 if info.ignore_triangle else attack_style
	var amt := Combat.mitigate(info.amount * info.crit_mult, info.style, def_style,
		get_defence(info.style), info.armor_pen, get_protected_style(), info.ignores_prayer, info.is_true)
	amt *= maxf(0.0, 1.0 + status_sum("damage_taken_mult"))
	if info.style == Combat.Style.MELEE and not info.is_true:
		amt *= maxf(0.0, 1.0 + status_sum("melee_damage_taken_mult"))   # e.g. Toxic staff Lightness
	var ely := find_status_id("elysian")
	if ely != "" and not info.is_true:
		var ely_st: Dictionary = statuses[ely]
		if randf() < float(ely_st["data"].get("chance", 0.7)):
			amt *= 1.0 - float(ely_st["amount"])
	amt = maxf(modify_incoming(amt, info), 0.0)

	health -= amt
	if src:
		recent_attackers[src.get_instance_id()] = {"unit": src, "time": Combat.clock}

	var veng := find_status_id("vengeance")
	if veng != "" and src and amt > 0.0 and not info.is_true:
		var reflect := DamageInfo.make(amt * float(statuses[veng]["amount"]), Combat.Style.MAGIC, self)
		reflect.is_true = true
		reflect.label = "vengeance"
		statuses.erase(veng)
		src.take_damage(reflect)

	_spawn_hitsplat(amt, info)
	damaged.emit(self, amt, src)
	if health <= 0.0:
		die(src)
	return amt


func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(max_health, health + amount)


func die(killer: Unit) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	statuses.clear()
	attack_target = null
	velocity = Vector3.ZERO
	_dashing = false
	died.emit(self, killer)
	_on_death(killer)


## Default death: vanish and free. Champions override this to respawn.
func _on_death(_killer: Unit) -> void:
	visible = false
	collision_layer = 0
	if is_inside_tree():
		get_tree().create_timer(0.5, false).timeout.connect(queue_free)


## Hook for passives that change outgoing damage (champions extend this).
func modify_outgoing(info: DamageInfo, _target: Unit) -> void:
	info.amount *= maxf(0.0, 1.0 + status_sum("damage_mult"))


## Hook for passives that change incoming damage after mitigation.
func modify_incoming(amount: float, _info: DamageInfo) -> float:
	return amount


func on_attack_landed(target: Unit, _dealt: float) -> void:
	if not has_status("crest_of_cinders") or not is_instance_valid(target) or target.is_dead:
		return
	# Red buff (League's Crest of Cinders): 3 instances of 5-20 true damage
	# (on hit, then each second for 2 s) and a 3 s slow: melee 10/15/25%,
	# ranged 5/7.5/12.5% at levels 1/6/11.
	var lvl: int = self.level if self is Champion else 1
	var per := 5.0 + 15.0 * float(lvl - 1) / 17.0
	var hit := DamageInfo.make(per, Combat.Style.MAGIC, self)
	hit.is_true = true
	hit.label = "burn"
	target.take_damage(hit)
	if target.is_dead:
		return
	target.add_status("cinders_burn", "burn", per, 2.0, self)
	var tier := 0 if lvl < 6 else (1 if lvl < 11 else 2)
	var slows: Array = [0.10, 0.15, 0.25] if attack_style == Combat.Style.MELEE else [0.05, 0.075, 0.125]
	target.add_status("cinders_slow", "slow", float(slows[tier]), 3.0, self)


# --- Auto attacks --------------------------------------------------------------

func process_attack(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if not is_instance_valid(attack_target) or attack_target.is_dead or not attack_target.is_damageable():
		attack_target = null
		return
	if not can_act() or not in_attack_range(attack_target):
		return
	face_toward(attack_target.global_position)
	if _attack_cooldown <= 0.0:
		_attack_cooldown = get_attack_interval()
		perform_attack(attack_target)


func in_attack_range(t: Unit) -> bool:
	return flat_distance_to(t) <= get_attack_range() + radius + t.radius


func perform_attack(t: Unit) -> void:
	var info := build_attack_damage(t)
	if get_attack_range() > 3.0:
		var on_hit := func() -> void:
			if is_instance_valid(t) and not t.is_dead:
				var dealt := t.take_damage(info)
				on_attack_landed(t, dealt)
		Projectile.launch(self, t, attack_style, on_hit)
	else:
		var dealt := t.take_damage(info)
		on_attack_landed(t, dealt)


func build_attack_damage(t: Unit) -> DamageInfo:
	var amount := get_magic_power() if attack_style == Combat.Style.MAGIC else get_damage()
	var info := DamageInfo.make(amount, attack_style, self)
	info.is_attack = true
	info.armor_pen = armor_pen
	modify_outgoing(info, t)
	return info


# --- Movement ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_dead:
		_dead_process(delta)
		return
	_tick_statuses(delta)
	if is_dead:
		return
	if not _process_dash(delta):
		_unit_process(delta)
	global_position.y = 0.0
	if _health_bar:
		_health_bar.set_ratio(health_ratio())


## Per-frame behaviour for subclasses (AI, input-driven movement, ...).
func _unit_process(_delta: float) -> void:
	pass


func _dead_process(_delta: float) -> void:
	pass


func flat_distance_to(other: Node3D) -> float:
	return flat_distance(global_position, other.global_position)


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func face_toward(point: Vector3) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length_squared() > 0.0001:
		rotation.y = atan2(d.x, d.z)


func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


## Straight-line movement (minions and monsters walk open lanes, no pathfinding).
func move_directly_toward(point: Vector3) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length() < 0.05 or not can_move():
		velocity = Vector3.ZERO
		return
	velocity = d.normalized() * get_move_speed()
	move_and_slide()
	face_toward(point)


## Moves the unit quickly toward a point. Used for dashes and knockbacks alike;
## Champion checks Tele Block before starting voluntary dashes.
func start_dash(destination: Vector3, speed: float, ignore_walls: bool = false) -> void:
	_dash_target = Vector3(destination.x, 0.0, destination.z)
	_dash_speed = speed
	_dash_ignore_walls = ignore_walls
	_dashing = true


func _process_dash(delta: float) -> bool:
	if not _dashing:
		return false
	var d := _dash_target - global_position
	d.y = 0.0
	var step := _dash_speed * delta
	if d.length() <= step:
		if _dash_ignore_walls:
			global_position = _dash_target
			snap_to_navmesh()
		else:
			velocity = d / maxf(delta, 0.001)
			move_and_slide()
		_dashing = false
		velocity = Vector3.ZERO
		return true
	if _dash_ignore_walls:
		global_position += d.normalized() * step
	else:
		velocity = d.normalized() * _dash_speed
		move_and_slide()
		if get_slide_collision_count() > 0 and get_real_velocity().length() < 0.5:
			_dashing = false   # dashed into a wall
	face_toward(_dash_target)
	return true


func snap_to_navmesh() -> void:
	var nav_map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		var p := NavigationServer3D.map_get_closest_point(nav_map, global_position)
		global_position = Vector3(p.x, 0.0, p.z)


# --- Queries -------------------------------------------------------------------

func find_nearest_enemy(max_range: float, include_structures: bool = true, include_neutral: bool = false) -> Unit:
	var best: Unit = null
	var best_d := max_range
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u == self or u.is_dead or not u.is_damageable() or u.team == team:
			continue
		if u.team == Combat.Team.NEUTRAL and not include_neutral:
			continue
		if u.is_structure() and not include_structures:
			continue
		var d := flat_distance_to(u) - u.radius
		if d < best_d:
			best_d = d
			best = u
	return best


func _spawn_hitsplat(amount: float, info: DamageInfo) -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var color := Color(0.85, 0.1, 0.1)
	if amount <= 0.0:
		color = Color(0.2, 0.45, 0.95)        # OSRS blue zero-hit splat
	elif info.label == "venom" or info.label == "poison":
		color = Color(0.2, 0.7, 0.25)
	elif info.label == "burn":
		color = Color(0.95, 0.55, 0.1)
	elif info.label == "vengeance":
		color = Color(0.7, 0.3, 0.9)
	Hitsplat.spawn(get_parent(), global_position + Vector3(randf_range(-0.3, 0.3), _height + 0.2, 0.0), amount, color)
