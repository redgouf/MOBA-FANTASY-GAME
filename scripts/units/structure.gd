class_name Structure
extends Unit
## Towers, altars (inhibitors), team flags (nexus) and temporary summons like
## the Slayer's dwarf multicannon. Structures never move.

var kind := "tower"            # tower / altar / flag / summon
var lane := ""
var tier := ""
## This structure can only be damaged once every structure here is destroyed.
var requires_all: Array[Structure] = []
## ...and at least one of these (used for flag towers needing any altar down).
var requires_any: Array[Structure] = []
var lifetime := -1.0
var targets_neutral := false
var owner_champion: Champion = null

var _scan := 0.0


func init_structure(p_kind: String, def: Dictionary, p_team: int, label: String) -> void:
	kind = p_kind
	team = p_team
	unit_id = p_kind
	configure_from_def(def)
	display_name = label
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


func _unit_process(delta: float) -> void:
	if lifetime > 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			die(null)
			return
	if base_attack_range <= 0.0:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.25
		attack_target = _pick_target()
	process_attack(delta)


## Tower targeting: an enemy champion who just hit an allied champion first,
## then the current target, then the nearest minion, then the nearest champion.
func _pick_target() -> Unit:
	var now := Time.get_ticks_msec() / 1000.0
	var aggro: Unit = null
	var nearest_minion: Unit = null
	var nearest_champ: Unit = null
	var dm := INF
	var dc := INF
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead or u.team == team or not u.is_damageable():
			continue
		if u.team == Combat.Team.NEUTRAL and not targets_neutral:
			continue
		if not in_attack_range(u):
			continue
		var d := flat_distance_to(u)
		if u is Champion:
			if now - (u as Champion).last_champion_aggro < 2.5:
				aggro = u
			if d < dc:
				dc = d
				nearest_champ = u
		elif not u.is_structure() and d < dm:
			dm = d
			nearest_minion = u
	if aggro != null and kind == "tower":
		return aggro
	if is_instance_valid(attack_target) and not attack_target.is_dead and in_attack_range(attack_target):
		return attack_target
	return nearest_minion if nearest_minion != null else nearest_champ
