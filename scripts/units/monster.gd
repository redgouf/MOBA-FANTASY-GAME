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

var variant_id := ""             # dragon colour or "kbd" (see roll_variant)

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
	variant_id = str(def.get("variant_id", ""))
	var color := Color(0.75, 0.45, 0.15) if is_epic else Color(0.6, 0.55, 0.4)
	if def.has("color"):
		color = Color(str(def["color"]))
	setup_visuals(color, 1.2 + radius * 1.2, display_name)
	var cfg := OsrsModels.monster_config(id) if OsrsModels.available() else {}
	var model := str(cfg.get("model", ""))
	var own_model := str(cfg.get("variants", {}).get(variant_id, ""))
	var variant_model := own_model != "" and OsrsModels.scene("bosses/%s.glb" % own_model) != null
	if variant_model:
		model = own_model     # the variant has a model of its own (the real red dragon, not a tinted one)
	elif model != "" and OsrsModels.scene("bosses/%s.glb" % model) == null:
		model = str(cfg.get("fallback", ""))
	if model != "":
		var actor := OsrsActor.creature(model, radius * 2.4)
		if actor != null and not variant_model and bool(def.get("tint", false)) and def.has("color"):
			actor.tint(Color(str(def["color"])))
		attach_osrs(actor)


## Which look a spawning monster takes, when its def lists `variants`: one of
## the plain colours (looks only), or the special variant (the King Black
## Dragon) which is only possible once `kills` of this camp have reached its
## `after_kills`, so the first dragon is always an ordinary one. `roll` and
## `pick` are 0-1 randoms (passed in so tests are deterministic).
## Returns {} for a def without variants.
static func roll_variant(def: Dictionary, kills: int, roll: float, pick: float) -> Dictionary:
	var v: Dictionary = def.get("variants", {})
	if v.is_empty():
		return {}
	var special: Dictionary = v.get("special", {})
	if not special.is_empty() and kills >= int(special.get("after_kills", 1)) and roll < float(special.get("chance", 0.0)):
		return special
	var colors: Array = v.get("colors", [])
	if colors.is_empty():
		return special if kills >= int(special.get("after_kills", 1)) else {}
	return colors[mini(int(pick * colors.size()), colors.size() - 1)]


## The def a monster is built from once a variant is picked: the base def with
## the variant's name, colour and any health / damage / gold / xp / size
## multipliers applied.
static func apply_variant(def: Dictionary, variant: Dictionary) -> Dictionary:
	if variant.is_empty():
		return def
	var out: Dictionary = def.duplicate(true)
	out.erase("variants")
	out["variant_id"] = str(variant.get("id", ""))
	for k in ["name", "color", "tint"]:
		if variant.has(k):
			out[k] = variant[k]
	_scale_stat(out, "health", float(variant.get("health_mult", 1.0)))
	_scale_stat(out, "damage", float(variant.get("damage_mult", 1.0)))
	_scale_stat(out, "gold", float(variant.get("gold_mult", 1.0)))
	_scale_stat(out, "xp", float(variant.get("xp_mult", 1.0)))
	if variant.has("radius_mult"):
		out["radius"] = float(out.get("radius", 1.0)) * float(variant["radius_mult"])
	return out


static func _scale_stat(def: Dictionary, key: String, mult: float) -> void:
	if mult == 1.0 or not def.has(key):
		return
	var v: Variant = def[key]
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(float(x) * mult)
		def[key] = arr
	else:
		def[key] = float(v) * mult


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


## Per frame: walk home while resetting, or toward the target.
func _unit_process(_delta: float) -> void:
	if _resetting:
		move_directly_toward(home)
		return
	if is_instance_valid(attack_target) and not attack_target.is_dead and not passive:
		if in_attack_range(attack_target):
			velocity = Vector3.ZERO
		else:
			move_directly_toward(attack_target.global_position)


## Per tick: leash, reset healing, attacks.
func _unit_tick(dt: float) -> void:
	if _resetting:
		heal(max_health * 0.5 * dt)
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
		process_attack(dt)
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
