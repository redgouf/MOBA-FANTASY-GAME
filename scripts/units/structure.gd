class_name Structure
extends Unit
## Towers (turrets), altars (inhibitors), team flags (nexus) and temporary
## summons like the Slayer's dwarf multicannon. Structures never move.
##
## Turrets follow League of Legends Summoner's Rift rules:
## - attack damage grows each minute up to a cap (outer 182 -> 350 by 14:00)
## - Warming Up: +50% damage per consecutive shot on champions, up to +150%,
##   reset 5 s after the last champion hit (not on target switch)
## - shots on minions deal a fixed % of the minion's max health
##   (melee 45%, caster 70%, siege 14/11/8% by tier, super 7%)
## - target priority: a champion hitting an allied champion nearby, else the
##   current target, else siege/super > melee > caster > other > champions
## - melee champions deal 20% more damage to turrets
## Altars respawn after 5 minutes; nexus turrets after 3 minutes at 40% health.

var kind := "tower"            # tower / altar / flag / summon
var lane := ""
var tier := ""
var def_id := ""
## This structure can only be damaged once every structure here is destroyed.
var requires_all: Array[Structure] = []
## ...and at least one of these (used for flag towers needing any altar down).
var requires_any: Array[Structure] = []
var lifetime := -1.0
var targets_neutral := false
var owner_champion: Champion = null

var damage_per_minute := 0.0
var damage_max := 0.0
var minion_damage_pct: Dictionary = {}
var regen := 0.0
var regen_caps: Array = []
var respawn_sec := 0.0
var respawn_health_pct := 1.0
var global_gold := 0
var last_hit_gold := 0
var respawn_timer := 0.0

var _scan := 0.0
var _warm_stacks := 0
var _last_champion_hit := -100.0
var _rules: Dictionary = {}


func init_structure(p_kind: String, def: Dictionary, p_team: int, label: String, p_def_id: String = "") -> void:
	kind = p_kind
	team = p_team
	unit_id = p_kind
	def_id = p_def_id
	configure_from_def(def)
	display_name = label
	damage_per_minute = float(def.get("damage_per_minute", 0.0))
	damage_max = float(def.get("damage_max", base_damage))
	minion_damage_pct = def.get("minion_damage_pct", {})
	regen = float(def.get("regen", 0.0))
	regen_caps = def.get("regen_caps", [])
	respawn_sec = float(def.get("respawn_sec", 0.0))
	respawn_health_pct = float(def.get("respawn_health_pct", 1.0))
	global_gold = int(def.get("global_gold", 0))
	last_hit_gold = int(def.get("last_hit_gold", 0))
	gold_value = global_gold
	_rules = GameData.units.get("turret_rules", {})
	var color := Unit.team_color(team).lerp(Color(0.62, 0.6, 0.56), 0.55)
	match kind:
		"tower":
			setup_visuals(color, 6.0, label, "cylinder")
		"altar":
			setup_visuals(color, 2.4, label, "box")
		"flag":
			setup_visuals(color, 8.0, label, "cylinder")
		_:
			setup_visuals(color, 1.2, label, "box")


func _ready() -> void:
	super()
	if kind != "summon":
		add_to_group("structures")


func is_structure() -> bool:
	return kind != "summon"


func is_tower() -> bool:
	return kind == "tower"


func is_damageable() -> bool:
	if is_dead:
		return false
	for s in requires_all:
		if is_instance_valid(s) and not s.is_dead:
			return false
	if not requires_any.is_empty():
		for s in requires_any:
			if not is_instance_valid(s) or s.is_dead:
				return true
		return false
	return true


## Turret damage grows with game time up to its cap.
func get_damage() -> float:
	if damage_per_minute <= 0.0:
		return super()
	var grown := base_damage + damage_per_minute * Combat.clock / 60.0
	return minf(grown, damage_max) * maxf(0.0, 1.0 + status_sum("damage_mult"))


func build_attack_damage(t: Unit) -> DamageInfo:
	var info := super(t)
	if t is Minion and not minion_damage_pct.is_empty():
		var m := t as Minion
		info.amount = m.max_health * float(minion_damage_pct.get(m.role, 0.1))
		info.ignore_triangle = true
	elif t is Champion and is_tower():
		if Combat.clock - _last_champion_hit > float(_rules.get("warming_up_reset_sec", 5.0)):
			_warm_stacks = 0
		var per := float(_rules.get("warming_up_per_hit", 0.5))
		var bonus := minf(per * float(_warm_stacks), float(_rules.get("warming_up_max", 1.5)))
		info.amount *= 1.0 + bonus
		_warm_stacks += 1
		_last_champion_hit = Combat.clock
	return info


## Get damage() already includes damage_mult; skip the generic bonus for towers.
func modify_outgoing(info: DamageInfo, target: Unit) -> void:
	if damage_per_minute <= 0.0:
		super(info, target)


func modify_incoming(amount: float, info: DamageInfo) -> float:
	if is_tower() and info.is_attack and info.source is Champion \
			and (info.source as Champion).attack_style == Combat.Style.MELEE:
		amount *= float(_rules.get("melee_champion_damage_mult", 1.2))
	return amount


func warming_up_stacks() -> int:
	return _warm_stacks


func _unit_process(delta: float) -> void:
	if lifetime > 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			die(null)
			return
	_regenerate(delta)
	if base_attack_range <= 0.0:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.25
		attack_target = _pick_target()
	process_attack(delta)


func _regenerate(delta: float) -> void:
	if regen <= 0.0 or health >= max_health:
		return
	var cap := 1.0
	if not regen_caps.is_empty():
		var ratio := health_ratio()
		for c in regen_caps:
			if ratio < float(c) - 0.0001:
				cap = float(c)
				break
	health = minf(health + regen * delta, max_health * cap)


func _pick_target() -> Unit:
	var now := Combat.clock
	var aggro_radius := lol_to_meters(float(_rules.get("champion_aggro_radius_lol", 1400)))
	var aggro: Unit = null
	var keep: Unit = null
	var best: Unit = null
	var best_rank := 99
	var best_d := INF
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead or u.team == team or not u.is_damageable():
			continue
		if u.team == Combat.Team.NEUTRAL and not targets_neutral:
			continue
		if not in_attack_range(u):
			continue
		if u is Champion:
			var c := u as Champion
			if now - c.last_champion_aggro < 2.0 and flat_distance(c.last_aggro_victim_pos, global_position) <= aggro_radius:
				aggro = c
		if u == attack_target:
			keep = u
		var rank := _priority(u)
		var d := flat_distance_to(u)
		if rank < best_rank or (rank == best_rank and d < best_d):
			best_rank = rank
			best_d = d
			best = u
	if aggro != null and is_tower():
		return aggro
	if keep != null:
		return keep
	return best


## Lower is attacked first: siege/super, melee, caster, anything else, champions.
func _priority(u: Unit) -> int:
	if u is Minion:
		match (u as Minion).role:
			"siege", "super":
				return 0
			"melee":
				return 1
			"caster":
				return 2
	if u is Champion:
		return 4
	return 3


func _on_death(killer: Unit) -> void:
	if respawn_sec <= 0.0:
		super(killer)
		return
	visible = false
	collision_layer = 0
	attack_target = null
	_warm_stacks = 0
	respawn_timer = respawn_sec


func _dead_process(delta: float) -> void:
	if respawn_sec <= 0.0:
		return
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		is_dead = false
		health = max_health * respawn_health_pct
		visible = true
		collision_layer = LAYER_UNITS
