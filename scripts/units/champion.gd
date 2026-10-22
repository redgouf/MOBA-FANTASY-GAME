class_name Champion
extends Unit
## A playable OSRS build: stats, prayer, special attack energy, items,
## a data-driven kit (Q/W/E/R) and a passive. Bots reuse the same class.

signal leveled_up(champion: Champion)
signal respawned(champion: Champion)
signal ability_cast(champion: Champion, slot: String)
signal ranks_changed(champion: Champion)
## Fired for every order the champion is given, human or bot: kind is
## "move", "attack" or "cast"; label is the ability key or item name.
## The spectator's ghost cursor follows these.
signal command_issued(champion: Champion, kind: String, point: Vector3, label: String)

const SLOTS: Array[String] = ["q", "w", "e", "r"]

## Combat skills every build defines (combat level comes from these).
const SKILLS: Array[String] = ["attack", "hitpoints", "strength", "defence", "ranged", "prayer", "magic"]
## Every OSRS skill (2026, incl. Sailing). Builds may set any of them; unset = 1 (Hitpoints 10).
const ALL_SKILLS: Array[String] = ["attack", "hitpoints", "mining", "strength", "agility", "smithing",
	"defence", "herblore", "fishing", "ranged", "thieving", "cooking", "prayer", "crafting", "firemaking",
	"magic", "fletching", "woodcutting", "runecraft", "slayer", "farming", "construction", "hunter", "sailing"]

var champ_id := ""
var def: Dictionary = {}
var passive: Dictionary = {}
## OSRS skill levels of this build; items check them as requirements.
var skills: Dictionary = {}
## Only tank and main-account builds can use protection prayers (overheads).
var has_overheads := false

var level := 1
var xp := 0.0
var gold := 0.0
var kills := 0
var deaths := 0
var assists := 0

var prayer := 99.0
var prayer_max := 99.0
var protect_style := -1
var offensive_prayer_cd := 0.0
var spec := 100.0
## Skill power: what skilling actions (the Skiller's kit) scale with, like magic power for mages.
var skill_power := 0.0
var cooldowns := {"q": 0.0, "w": 0.0, "e": 0.0, "r": 0.0}
## League-style ability ranks: everything starts unlearned with one point to spend.
var ranks := {"q": 0, "w": 0, "e": 0, "r": 0}
var skill_points := 1
var creep_score := 0
var inventory: Array[String] = []
var consumables: Array[String] = []

var is_bot := false
var bot_lane := "mid"
var spawn_point := Vector3.ZERO
var respawn_timer := 0.0
var recall_timer := -1.0
## Time (seconds) this champion last damaged an enemy champion. Towers use it for aggro.
var last_champion_aggro := -100.0
## Where the allied champion it hit was standing (turrets only react nearby).
var last_aggro_victim_pos := Vector3(INF, 0.0, INF)

var forms: Array = []
var form_index := 0

var _switch_bonus_ready := false
var _hit_counter := 0
var _stacks := 0
var _stack_timer := 0.0
var _item_stats: Dictionary = {}
var _nav: NavigationAgent3D
var _has_move_target := false
var _move_point := Vector3.ZERO
var _queued_cast: Dictionary = {}
var _repath_timer := 0.0
var _path_iteration := -1       # navigation map iteration our current path was computed on
var _bot_think := 0.0
var _last_cmd_point := Vector3(INF, 0.0, INF)
var _bot_waypoint := 1
var _skill_casts := 0
## Timber! yews this champion has standing, oldest first.
var planted_trees: Array[PlantedTree] = []


## Call before adding to the tree (team decides groups and colours).
func setup(id: String, p_team: int, spawn: Vector3, bot: bool) -> void:
	champ_id = id
	def = GameData.champion(id)
	if def.is_empty():
		push_error("Champion: unknown champion id '%s'" % id)
	team = p_team
	is_bot = bot
	spawn_point = spawn
	passive = def.get("passive", {})
	skills = def.get("skills", {})
	has_overheads = bool(def.get("overheads", false))
	forms = def.get("forms", [])
	configure_from_def(def.get("base", {}))
	attack_style = Combat.style_from_string(str(def.get("style", "melee")))
	attack_fx = def.get("attack_fx", {})
	display_name = str(def.get("name", id))
	gold = float(GameData.rule("starting_gold", 500))
	prayer_max = float(GameData.rule("prayer_points_max", 99))
	prayer = prayer_max
	if not forms.is_empty():
		_apply_form(0)
		_switch_bonus_ready = false
	skill_points = int(GameData.rule("starting_skill_points", 1))
	recompute_stats(true)
	if is_bot:
		bot_spend_skill_points()


func _ready() -> void:
	super()
	add_to_group("champions")
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.6
	_nav.target_desired_distance = 0.4
	_nav.radius = radius
	_nav.height = 2.0
	add_child(_nav)
	var body_color := Unit.team_color(team).lerp(Color.WHITE, 0.15)
	setup_visuals(body_color, 2.2, _label_text())
	_setup_osrs_model()
	_add_body_tags(str(def.get("tag", display_name.substr(0, 2).to_upper())), 2.2)
	damaged.connect(_on_damaged)


## The build's OSRS model (private pack installed): fixed gear for the whole
## match; only specs swap the weapon briefly (and the Hybrid's form).
func _setup_osrs_model() -> void:
	if not OsrsModels.available():
		return
	var cfg := OsrsModels.champion_config(champ_id)
	if cfg.is_empty():
		return
	var actor := OsrsActor.player(cfg)
	if actor == null:
		return
	actor.scale = Vector3.ONE * float(OsrsModels.config().get("player_scale", 1.4))
	attach_osrs(actor)
	if not forms.is_empty():
		_osrs_form()


func _osrs_form() -> void:
	var f: Dictionary = OsrsModels.champion_config(champ_id).get("forms", {}).get(form_name(), {})
	if osrs != null and not f.is_empty():
		osrs.set_base_weapon(int(f.get("weapon", 0)), str(f.get("attack", "slash")))


## Animation and effects for an ability or item spec as it goes off.
func _cast_visuals(slot: String, target: Unit = null, point: Vector3 = Vector3.ZERO) -> void:
	CombatFx.ability(self, get_action(slot), target, point)
	if osrs == null:
		return
	if slot.begins_with("item:"):
		var spec := OsrsModels.spec_config(slot.substr(5))
		if not spec.is_empty():
			osrs.spec(int(spec.get("weapon", 0)), str(spec.get("clip", "")), bool(spec.get("two_handed", false)))
		return
	var a: Dictionary = OsrsModels.champion_config(champ_id).get("abilities", {}).get(slot, {})
	if a.has("spec"):
		var spec2 := OsrsModels.spec_config(str(a["spec"]))
		osrs.spec(int(spec2.get("weapon", 0)), str(spec2.get("clip", "")), bool(spec2.get("two_handed", false)))
	elif a.has("clip"):
		osrs.play(str(a["clip"]), 1.2)
	else:
		osrs.play_attack(0.8, attack_style)


## The champion's two-letter tag ("DH", "SK") printed on its chest and back,
## like a jersey, so builds are easy to tell apart. With an OSRS model they
## sit smaller, just off its (slimmer) chest and back.
func _add_body_tags(tag: String, height: float) -> void:
	for back in [false, true]:
		var l := Label3D.new()
		l.name = "BackTag" if back else "ChestTag"
		l.text = tag
		l.font_size = 64
		l.pixel_size = 0.011
		l.outline_size = 16
		l.modulate = Color(1, 1, 1)
		l.outline_modulate = Color(0.05, 0.04, 0.03)
		l.double_sided = false
		l.position = Vector3(0.0, height * 0.6, (radius + 0.02) * (-1.0 if back else 1.0))
		l.rotation.y = PI if back else 0.0
		if osrs != null:
			l.pixel_size = 0.0062
			l.outline_size = 12
			l.position = Vector3(0.0, 1.45, 0.3 * (-1.0 if back else 1.0))
		add_child(l)


func _label_text() -> String:
	return "%s (level-%d)" % [display_name, combat_level()]


# --- Stats -------------------------------------------------------------------

func recompute_stats(full_heal: bool = false) -> void:
	var base: Dictionary = def.get("base", {})
	var growth: Dictionary = def.get("growth", {})
	var lv := float(level - 1)
	var old_ratio := health_ratio()
	max_health = float(base.get("max_health", 500.0)) + float(growth.get("max_health", 0.0)) * lv + _item_stat("health")
	base_damage = float(base.get("damage", 0.0)) + float(growth.get("damage", 0.0)) * lv + _item_stat("damage")
	base_magic_power = float(base.get("magic_power", 0.0)) + float(growth.get("magic_power", 0.0)) * lv + _item_stat("magic_power")
	var bd: Dictionary = base.get("defence", {})
	var gd: Dictionary = growth.get("defence", {})
	for i in 3:
		var key: String = Combat.STYLE_NAMES[i]
		base_defence[i] = float(bd.get(key, 0.0)) + float(gd.get(key, 0.0)) * lv + _item_stat("defence_" + key) + _item_stat("defence_all")
	bonus_attack_speed = float(growth.get("attack_speed", 0.0)) * lv + _item_stat("attack_speed")
	base_move_speed = float(base.get("move_speed", 6.0)) + _item_stat("move_speed")
	armor_pen = _item_stat("armor_pen")
	skill_power = float(base.get("skill_power", 0.0)) + float(growth.get("skill_power", 0.0)) * lv + _item_stat("skill_power")
	health = max_health if full_heal else max_health * old_ratio


func _item_stat(key: String) -> float:
	return float(_item_stats.get(key, 0.0))


func _rebuild_item_stats() -> void:
	_item_stats = {}
	for id in inventory:
		var stats: Dictionary = GameData.item(id).get("stats", {})
		for k in stats:
			if k == "defence":
				for style_key in stats[k]:
					var dk: String = "defence_" + str(style_key)
					_item_stats[dk] = float(_item_stats.get(dk, 0.0)) + float(stats[k][style_key])
			else:
				_item_stats[k] = float(_item_stats.get(k, 0.0)) + float(stats[k])


## The build's real OSRS combat level (from its skills; doesn't change in a match).
func combat_level() -> int:
	return Combat.osrs_combat_level(skills)


func spec_regen_mult() -> float:
	var m := 1.0 + status_sum("spec_regen_mult") + _item_stat("spec_regen")
	if passive.get("type", "") == "glass_cannon":
		m += float(passive.get("spec_regen_bonus", 0.0))
	return m


func get_protected_style() -> int:
	return -1 if has_status("disable_prayer") else protect_style


func skill(name: String) -> int:
	return int(skills.get(name, 10 if name == "hitpoints" else 1))


func get_skill_power() -> float:
	return skill_power * maxf(0.0, 1.0 + status_sum("skill_power_mult"))


## The strongest offensive prayer this build's Prayer level unlocks for its
## current style, e.g. Piety at 70, Chivalry at 60. Empty if none qualifies.
func offensive_prayer() -> Dictionary:
	var table: Dictionary = GameData.rule("offensive_prayers", {})
	for p in table.get(Combat.style_name(attack_style), []):
		if skill("prayer") >= int(p.get("level", 99)):
			return p
	return {}


func offensive_prayer_name() -> String:
	return str(offensive_prayer().get("name", "None"))


## What the prayer does, for tooltips and the scoreboard ("+12% damage").
static func prayer_effect_text(p: Dictionary) -> String:
	if p.is_empty():
		return "no prayer"
	if p.has("text"):
		return str(p["text"])
	return "+%d%% damage" % int(round(float(p.get("bonus", 0.0)) * 100.0))


## Item requirements use real OSRS levels: a 1 Defence Pure can't wear Bandos.
func meets_requirements(item_id: String) -> bool:
	return missing_requirements(item_id).is_empty()


func missing_requirements(item_id: String) -> Array[String]:
	var out: Array[String] = []
	var reqs: Dictionary = GameData.item(item_id).get("requirements", {})
	for s in reqs:
		if skill(str(s)) < int(reqs[s]):
			out.append("%d %s" % [int(reqs[s]), str(s).capitalize()])
	return out


# --- Progression -------------------------------------------------------------

func xp_to_next() -> float:
	return float(GameData.rule("xp_base", 280)) + float(GameData.rule("xp_step", 100)) * float(level - 1)


func add_xp(amount: float) -> void:
	var max_level := int(GameData.rule("max_level", 18))
	if level >= max_level:
		return
	xp += amount
	while level < max_level and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		var hp_gain := float(def.get("growth", {}).get("max_health", 0.0))
		recompute_stats(false)
		heal(hp_gain)
		skill_points += 1
		set_label(_label_text())
		if is_bot:
			bot_spend_skill_points()
		leveled_up.emit(self)


# --- Ability ranks -----------------------------------------------------------

func max_rank(slot: String) -> int:
	return int(GameData.rule("ultimate_max_rank", 3)) if slot == "r" else int(GameData.rule("basic_max_rank", 5))


## Champion level needed to put the next point into this ability.
## Basic abilities: rank n needs level 2n-1. Ultimate: levels 6, 11, 16.
func level_needed_for_next_rank(slot: String) -> int:
	var next := int(ranks.get(slot, 0)) + 1
	if slot == "r":
		var gates: Array = GameData.rule("ultimate_rank_levels", [6, 11, 16])
		return int(gates[next - 1]) if next - 1 < gates.size() else 999
	return 2 * next - 1


func can_rank_up(slot: String) -> bool:
	return skill_points > 0 and ranks.has(slot) and int(ranks[slot]) < max_rank(slot) \
		and level >= level_needed_for_next_rank(slot)


func rank_up(slot: String) -> bool:
	if not can_rank_up(slot):
		return false
	ranks[slot] = int(ranks[slot]) + 1
	skill_points -= 1
	ranks_changed.emit(self)
	return true


## Rank of a kit ability, or 1 for an item spec (items don't level).
func ability_rank(key: String) -> int:
	if key.begins_with("item:"):
		return 1
	return int(ranks.get(key, 0))


func ability_cooldown(key: String, ab: Dictionary) -> float:
	var cd := float(ab.get("cooldown", 0.0))
	if key.begins_with("item:") or key == "r":
		return cd
	var per_rank := float(GameData.rule("basic_cooldown_reduction_per_rank", 0.06))
	return cd * maxf(0.2, 1.0 - per_rank * float(ability_rank(key) - 1))


## Bots take Q, W, E at levels 1-3, then always R when possible, then max Q > W > E.
func bot_spend_skill_points() -> void:
	var order: Array = def.get("skill_order", ["q", "w", "e"])
	while skill_points > 0:
		var picked := ""
		for slot in order:
			if int(ranks[slot]) == 0 and can_rank_up(slot):
				picked = slot
				break
		if picked == "" and can_rank_up("r"):
			picked = "r"
		if picked == "":
			for slot in order:
				if can_rank_up(slot):
					picked = slot
					break
		if picked == "" or not rank_up(picked):
			return


# --- Items -------------------------------------------------------------------

func item_cost(item_id: String) -> int:
	var it := GameData.item(item_id)
	var cost := int(it.get("cost", 0))
	var owned := inventory.duplicate()
	for comp in it.get("builds_from", []):
		var idx := owned.find(comp)
		if idx >= 0:
			cost -= int(GameData.item(comp).get("cost", 0))
			owned.remove_at(idx)
	return maxi(cost, 0)


func can_buy(item_id: String) -> bool:
	var it := GameData.item(item_id)
	if it.is_empty() or not meets_requirements(item_id):
		return false
	if bool(it.get("consumable", false)):
		return consumables.size() < int(GameData.rule("consumable_slots", 4)) and gold >= float(it.get("cost", 0))
	var consumed := 0
	var owned := inventory.duplicate()
	for comp in it.get("builds_from", []):
		var idx := owned.find(comp)
		if idx >= 0:
			consumed += 1
			owned.remove_at(idx)
	var slots_after := inventory.size() - consumed + 1
	return gold >= float(item_cost(item_id)) and slots_after <= int(GameData.rule("item_slots", 6))


func buy_item(item_id: String) -> bool:
	if not can_buy(item_id):
		return false
	var it := GameData.item(item_id)
	if bool(it.get("consumable", false)):
		gold -= float(it.get("cost", 0))
		consumables.append(item_id)
		return true
	var cost := item_cost(item_id)
	for comp in it.get("builds_from", []):
		inventory.erase(comp)
	inventory.append(item_id)
	gold -= float(cost)
	_rebuild_item_stats()
	recompute_stats(false)
	return true


func use_consumable(index: int) -> bool:
	if is_dead or index < 0 or index >= consumables.size():
		return false
	var item_id := consumables[index]
	var use: Dictionary = GameData.item(item_id).get("use", {})
	if use.has("heal"):
		heal(float(use["heal"]))
	if use.has("heal_pct_max"):
		heal(max_health * float(use["heal_pct_max"]))
	if use.has("heal_over_time"):
		var dur := float(use.get("duration", 5.0))
		add_status("food:" + item_id, "heal_over_time", float(use["heal_over_time"]) / dur, dur, self)
	if use.has("prayer"):
		prayer = minf(prayer_max, prayer + float(use["prayer"]))
	if use.has("spec"):
		spec = minf(100.0, spec + float(use["spec"]))
	for st in use.get("statuses", []):
		add_status("item:%s:%s" % [item_id, st["kind"]], st["kind"], float(st.get("amount", 0.0)), float(st.get("duration", 5.0)), self)
	consumables.remove_at(index)
	return true


func in_shop_range() -> bool:
	return is_dead or flat_distance(global_position, spawn_point) <= float(GameData.rule("shop_radius", 14))


# --- Prayer ------------------------------------------------------------------

func toggle_protect(style: int) -> void:
	if not has_overheads:
		return
	if protect_style == style:
		protect_style = -1
	elif prayer > 0.0 and not is_dead:
		protect_style = style


func activate_offensive_prayer() -> bool:
	var cfg: Dictionary = GameData.rule("offensive_prayer", {})
	var cost := float(cfg.get("cost", 10))
	var p := offensive_prayer()
	if p.is_empty() or is_dead or has_status("disable_prayer") or offensive_prayer_cd > 0.0 or prayer < cost:
		return false
	prayer -= cost
	offensive_prayer_cd = float(cfg.get("cooldown", 60))
	# Most are damage boosts; low-level ones like Thick Skin (the Skiller's,
	# Prayer 1) set their own "kind" (Thick Skin: take 5% less damage).
	add_status("offensive_prayer", str(p.get("kind", "damage_mult")), float(p.get("bonus", 0.1)), float(cfg.get("duration", 6)), self)
	return true


# --- Commands ----------------------------------------------------------------

func command_move(point: Vector3) -> void:
	_cancel_recall()
	attack_target = null
	_queued_cast = {}
	_set_move_target(point)
	if flat_distance(point, _last_cmd_point) > 1.0:
		_last_cmd_point = point
		command_issued.emit(self, "move", point, "")


func command_attack(target: Unit) -> void:
	if target == null or target.team == team:
		return
	_cancel_recall()
	_queued_cast = {}
	if attack_target != target:
		_last_cmd_point = target.global_position
		command_issued.emit(self, "attack", target.global_position, "")
	attack_target = target


func command_stop() -> void:
	attack_target = null
	_queued_cast = {}
	_has_move_target = false
	velocity = Vector3.ZERO


func start_recall() -> void:
	if is_dead or recall_timer >= 0.0 or has_status("tele_block"):
		return
	command_stop()
	recall_timer = float(GameData.rule("recall_channel_sec", 4.0))


func is_recalling() -> bool:
	return recall_timer >= 0.0


func _cancel_recall() -> void:
	recall_timer = -1.0


func _set_move_target(point: Vector3) -> void:
	_move_point = Vector3(point.x, 0.0, point.z)
	_has_move_target = true
	if _nav:
		_nav.target_position = _move_point


func _nav_ready() -> bool:
	if _nav == null:
		return false
	var nav_map := _nav.get_navigation_map()
	return NavigationServer3D.map_get_iteration_id(nav_map) > 0 and not NavigationServer3D.map_get_regions(nav_map).is_empty()


# --- Abilities ---------------------------------------------------------------

func get_ability(slot: String) -> Dictionary:
	var ab: Dictionary = def.get("abilities", {}).get(slot, {})
	if ab.has("forms") and not forms.is_empty():
		var form_name := str(forms[form_index].get("name", ""))
		var merged := ab.duplicate(true)
		merged.erase("forms")
		merged.merge(ab["forms"].get(form_name, {}), true)
		return merged
	return ab


## An action is a kit ability ("q".."r") or an item's spec active ("item:<id>").
## Both share the same casting rules, and both spend the one spec bar.
func get_action(key: String) -> Dictionary:
	if key.begins_with("item:"):
		var id := key.substr(5)
		return GameData.item(id).get("spec_active", {}) if inventory.has(id) else {}
	return get_ability(key)


func item_action_key(index: int) -> String:
	if index < 0 or index >= inventory.size():
		return ""
	return "item:" + inventory[index] if GameData.item(inventory[index]).has("spec_active") else ""


func use_item(index: int, target: Unit, point: Vector3) -> bool:
	var key := item_action_key(index)
	return key != "" and try_cast(key, target, point)


func ability_range(ab: Dictionary) -> float:
	return float(ab.get("range", 0.0))


func try_cast(slot: String, target: Unit, point: Vector3) -> bool:
	if is_dead or not can_act():
		return false
	var ab := get_action(slot)
	if ab.is_empty() or ability_rank(slot) <= 0 or cooldowns.get(slot, 0.0) > 0.0:
		return false
	if spec < float(ab.get("spec_cost", 0.0)):
		return false
	if has_status("tele_block") and _has_effect(ab, "dash"):
		return false
	if ab.has("planter"):
		return _try_planter(slot, ab, point)
	var cast := str(ab.get("cast", "self"))
	if cast == "target_unit":
		var want_ally := bool(ab.get("target_ally", false))
		var valid := target != null and is_instance_valid(target) and not target.is_dead
		if valid:
			if want_ally:
				valid = target.team == team and (target != self or bool(ab.get("allow_self", false)))
			else:
				valid = target.team != team and target.is_damageable()
		if not valid and want_ally and bool(ab.get("allow_self", false)):
			target = self
			valid = true
		if not valid:
			return false
		if target != self and flat_distance_to(target) > ability_range(ab) + radius + target.radius:
			_cancel_recall()
			_queued_cast = {"slot": slot, "target": target}
			return true
	elif cast == "point":
		var d := point - global_position
		d.y = 0.0
		var max_range := ability_range(ab)
		if d.length() > max_range:
			point = global_position + d.normalized() * max_range
	_execute_cast(slot, ab, target, point)
	return true


func _execute_cast(slot: String, ab: Dictionary, target: Unit, point: Vector3) -> void:
	_cancel_recall()
	cooldowns[slot] = ability_cooldown(slot, ab)
	spec = maxf(0.0, spec - float(ab.get("spec_cost", 0.0)))
	if target != null and target != self:
		face_toward(target.global_position)
	elif str(ab.get("cast", "self")) == "point":
		face_toward(point)
	AbilityRunner.execute(self, ab, target, point, ability_rank(slot))
	_cast_visuals(slot, target, point)
	ability_cast.emit(self, slot)
	_on_ability_used(slot)
	var aim := target.global_position if target != null and target != self else point
	var label := str(GameData.item(slot.substr(5)).get("name", "")) if slot.begins_with("item:") else slot.to_upper()
	_last_cmd_point = aim
	command_issued.emit(self, "cast", aim, label)


func _has_effect(ab: Dictionary, effect_type: String) -> bool:
	for e in ab.get("effects", []):
		if e.get("type", "") == effect_type:
			return true
	return false


func _process_queued_cast() -> void:
	var slot := str(_queued_cast.get("slot", ""))
	if _queued_cast.has("tree"):
		_process_queued_chop(slot)
		return
	var t: Variant = _queued_cast.get("target")
	if not is_instance_valid(t) or t.is_dead:
		_queued_cast = {}
		return
	var ab := get_action(slot)
	if ab.is_empty() or cooldowns.get(slot, 0.0) > 0.0 or spec < float(ab.get("spec_cost", 0.0)):
		_queued_cast = {}
		return
	if flat_distance_to(t) <= ability_range(ab) + radius + t.radius:
		_queued_cast = {}
		_has_move_target = false
		velocity = Vector3.ZERO
		_execute_cast(slot, ab, t, t.global_position)
	else:
		_chase(t.global_position)


# --- Planter abilities (Timber!) -----------------------------------------------
# Q on open ground plants a solid yew; Q on one of your yews chops it, and it
# falls straight away from where you stand.

func planter_config(slot: String) -> Dictionary:
	return get_action(slot).get("planter", {})


## Your standing yew nearest `point`, if the point is on (or close to) one.
func planter_tree_at(point: Vector3, cfg: Dictionary) -> PlantedTree:
	var best: PlantedTree = null
	var best_d := float(cfg.get("hover_radius", 1.8))
	for t in planted_trees:
		if not is_instance_valid(t) or not t.is_standing():
			continue
		var d := flat_distance(point, t.global_position)
		if d <= best_d:
			best_d = d
			best = t
	return best


func chop_range(cfg: Dictionary) -> float:
	return float(cfg.get("chop_range", 3.5))


func standing_trees() -> Array[PlantedTree]:
	var out: Array[PlantedTree] = []
	for t in planted_trees:
		if is_instance_valid(t) and t.is_standing():
			out.append(t)
	return out


## The yew a new plant would replace (the oldest, when at the limit), or null.
func tree_to_replace(cfg: Dictionary) -> PlantedTree:
	var trees := standing_trees()
	return trees[0] if trees.size() >= int(cfg.get("max", 3)) else null


## Where a yew aimed at `point` would actually be planted: within range, on
## walkable ground, and clear of towers and other structures.
func plant_spot(point: Vector3, ab: Dictionary) -> Vector3:
	var cfg: Dictionary = ab.get("planter", {})
	var d := point - global_position
	d.y = 0.0
	var p := global_position + (d.limit_length(ability_range(ab)))
	p.y = 0.0
	if is_inside_tree():
		var nav_map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0 and not NavigationServer3D.map_get_regions(nav_map).is_empty():
			var q := NavigationServer3D.map_get_closest_point(nav_map, p)
			p = Vector3(q.x, 0.0, q.z)
		var r := float(cfg.get("block_radius", 0.8))
		for n in get_tree().get_nodes_in_group("units"):
			var u := n as Unit
			if u == null or u.is_dead or not u.is_structure():
				continue
			var to := p - u.global_position
			to.y = 0.0
			var need := u.radius + r + 0.2
			if to.length() < need:
				p = u.global_position + (to.normalized() if to.length() > 0.05 else Vector3.RIGHT) * need
	return p


func _try_planter(slot: String, ab: Dictionary, point: Vector3) -> bool:
	var cfg: Dictionary = ab.get("planter", {})
	var tree := planter_tree_at(point, cfg)
	if tree == null:
		_execute_plant(slot, ab, plant_spot(point, ab))
	elif flat_distance_to(tree) <= chop_range(cfg):
		_execute_chop(slot, ab, tree)
	else:
		# Walk up to the tree first; the approach decides which way it falls.
		_cancel_recall()
		_queued_cast = {"slot": slot, "tree": tree}
	return true


func _execute_plant(slot: String, ab: Dictionary, point: Vector3) -> void:
	var cfg: Dictionary = ab.get("planter", {})
	_cancel_recall()
	var oldest := tree_to_replace(cfg)
	while oldest != null:
		oldest.wither()
		oldest = tree_to_replace(cfg)
	planted_trees = standing_trees()
	planted_trees.append(PlantedTree.plant(self, point, cfg))
	cooldowns[slot] = float(cfg.get("cooldown", 1.5))
	face_toward(point)
	if osrs != null:
		osrs.play("unarmed_attack_stab_422", 0.5)
	ability_cast.emit(self, slot)
	_last_cmd_point = point
	command_issued.emit(self, "cast", point, slot.to_upper())


func _execute_chop(slot: String, ab: Dictionary, tree: PlantedTree) -> void:
	_cancel_recall()
	cooldowns[slot] = ability_cooldown(slot, ab)
	var at := tree.global_position
	face_toward(at)
	tree.fall(PlantedTree.fall_direction(global_position, at, forward()))
	# The ability's line starts at the tree ("origin": "point") and runs along
	# the chopper -> tree direction, locked now.
	AbilityRunner.execute(self, ab, null, at, ability_rank(slot))
	_cast_visuals(slot, null, at)
	ability_cast.emit(self, slot)
	_on_ability_used(slot)
	_last_cmd_point = at
	command_issued.emit(self, "cast", at, slot.to_upper())


func _process_queued_chop(slot: String) -> void:
	var tree: Variant = _queued_cast.get("tree")
	var ab := get_action(slot)
	if not is_instance_valid(tree) or not (tree as PlantedTree).is_standing() \
			or ab.is_empty() or cooldowns.get(slot, 0.0) > 0.0 or not can_act():
		_queued_cast = {}
		return
	var t := tree as PlantedTree
	if flat_distance_to(t) <= chop_range(ab.get("planter", {})):
		_queued_cast = {}
		_has_move_target = false
		velocity = Vector3.ZERO
		_execute_chop(slot, ab, t)
	else:
		_chase(t.global_position)


## Length and width of a planter ability's fall line (for bots and indicators).
func planter_fall_size(ab: Dictionary) -> Vector2:
	for e in ab.get("effects", []):
		var area: Dictionary = e.get("area", {})
		if str(area.get("shape", "")) == "line":
			return Vector2(float(area.get("length", 8.0)), float(area.get("width", 2.0)))
	return Vector2(8.0, 2.0)


func toggle_form() -> void:
	if forms.size() < 2:
		return
	_apply_form((form_index + 1) % forms.size())
	_switch_bonus_ready = true
	_osrs_form()


func _apply_form(index: int) -> void:
	form_index = index
	var f: Dictionary = forms[index]
	attack_style = Combat.style_from_string(str(f.get("style", "melee")))
	base_attack_range = float(f.get("attack_range", base_attack_range))
	if f.has("attack_fx"):
		attack_fx = f["attack_fx"]


func form_name() -> String:
	return str(forms[form_index].get("name", "")) if not forms.is_empty() else ""


# --- Passives ----------------------------------------------------------------

## "Level up!" (Skiller): every Nth kit ability sets off OSRS level-up fireworks.
func _on_ability_used(slot: String) -> void:
	if str(passive.get("type", "")) != "skilling_level_up" or slot.begins_with("item:"):
		return
	_skill_casts += 1
	if _skill_casts % maxi(1, int(passive.get("every", 4))) == 0:
		AbilityRunner.execute(self, {"effects": passive.get("effects", [])}, null, global_position, 1)


func skilling_casts_until_level_up() -> int:
	var every := maxi(1, int(passive.get("every", 4)))
	return every - (_skill_casts % every)


func modify_outgoing(info: DamageInfo, target: Unit) -> void:
	super(info, target)
	match str(passive.get("type", "")):
		"missing_health_damage":
			info.amount *= 1.0 + (1.0 - health_ratio()) * float(passive.get("pct_per_pct", 1.0))
		"glass_cannon":
			info.amount *= 1.0 + float(passive.get("damage_dealt", 0.15))
		"skilling_level_up":
			if info.is_attack:
				info.amount += skill_power * float(passive.get("attack_skill_ratio", 0.3))
		"nth_hit_bonus":
			_hit_counter += 1
			if _hit_counter % maxi(1, int(passive.get("n", 4))) == 0:
				info.amount *= 1.0 + float(passive.get("bonus", 0.3))
		"form_switch":
			if _switch_bonus_ready and info.is_attack:
				info.amount *= 1.0 + float(passive.get("switch_bonus", 0.2))
				_switch_bonus_ready = false
			if target is Champion and target.get_protected_style() != info.style:
				info.amount *= 1.0 + float(passive.get("off_prayer_bonus", 0.1))
		"target_magic_scaling":
			if target != null:
				info.amount *= 1.0 + minf(target.get_magic_power() * float(passive.get("per_magic_power", 0.004)), float(passive.get("cap", 0.6)))
				if target.is_epic:
					info.amount *= 1.0 + float(passive.get("epic_bonus", 0.2))
		"monster_bonus":
			if target != null and target.team == Combat.Team.NEUTRAL:
				info.amount *= 1.0 + float(passive.get("bonus", 0.167))
		"stacking_damage":
			info.amount *= 1.0 + float(_stacks) * float(passive.get("per_stack", 0.03))


func modify_incoming(amount: float, info: DamageInfo) -> float:
	match str(passive.get("type", "")):
		"glass_cannon":
			amount *= 1.0 + float(passive.get("damage_taken", 0.15))
		"flat_reduction":
			if not info.is_true:
				var avg := (get_defence(0) + get_defence(1) + get_defence(2)) / 3.0
				amount = maxf(amount * 0.3, amount - avg * float(passive.get("factor", 0.25)))
	return amount


func on_attack_landed(target: Unit, dealt: float) -> void:
	super(target, dealt)
	match str(passive.get("type", "")):
		"venom":
			if is_instance_valid(target) and not target.is_dead:
				target.add_status("venom", "venom", float(passive.get("start", 4.0)), float(passive.get("duration", 6.0)), self,
					{"step": float(passive.get("step", 2.0)), "max": float(passive.get("max", 20.0))})
		"stacking_damage":
			_stacks = mini(_stacks + 1, int(passive.get("max_stacks", 5)))
			_stack_timer = float(passive.get("window", 3.0))


func passive_stacks() -> int:
	return _stacks


func _on_damaged(_unit: Unit, amount: float, source: Unit) -> void:
	if amount > 0.0:
		_cancel_recall()
	if source is Champion and source.team != team:
		source.last_champion_aggro = Combat.clock
		source.last_aggro_victim_pos = global_position


# --- Frame update ------------------------------------------------------------

func _unit_process(delta: float) -> void:
	_tick_resources(delta)
	if is_dead:
		return
	if is_bot:
		_bot_update(delta)
	if not _queued_cast.is_empty():
		_process_queued_cast()
	elif is_instance_valid(attack_target) and not attack_target.is_dead:
		if in_attack_range(attack_target):
			_has_move_target = false
			velocity = Vector3.ZERO
		else:
			_chase(attack_target.global_position)
	if _has_move_target:
		_follow_path()
	process_attack(delta)


func _tick_resources(delta: float) -> void:
	for k in cooldowns:
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
	offensive_prayer_cd = maxf(0.0, offensive_prayer_cd - delta)
	if protect_style >= 0:
		var drain := float(GameData.rule("protect_prayer_drain_per_sec", 1.0)) * maxf(0.0, 1.0 - _item_stat("prayer_bonus"))
		prayer -= drain * delta
		if prayer <= 0.0:
			prayer = 0.0
			protect_style = -1
	spec = minf(100.0, spec + float(GameData.rule("spec_regen_per_sec", 1.0)) * spec_regen_mult() * delta)
	if _stack_timer > 0.0:
		_stack_timer -= delta
		if _stack_timer <= 0.0:
			_stacks = 0
	if recall_timer >= 0.0:
		recall_timer -= delta
		if recall_timer <= 0.0:
			recall_timer = -1.0
			global_position = spawn_point
			_has_move_target = false
	if flat_distance(global_position, spawn_point) <= float(GameData.rule("fountain_radius", 12)):
		heal(max_health * float(GameData.rule("fountain_heal_pct_per_sec", 0.1)) * delta)
		prayer = minf(prayer_max, prayer + 10.0 * delta)


func _chase(point: Vector3) -> void:
	_repath_timer -= get_physics_process_delta_time()
	if _repath_timer <= 0.0 or not _has_move_target:
		_repath_timer = 0.25
		_set_move_target(point)


func _follow_path() -> void:
	if not can_move():
		velocity = Vector3.ZERO
		return
	var next_point := _move_point
	if _nav_ready():
		# Re-query the path whenever the navmesh changed (the first bake landing,
		# or a rebake after a Timber! yew is planted or felled).
		var iteration := NavigationServer3D.map_get_iteration_id(_nav.get_navigation_map())
		if iteration != _path_iteration:
			_path_iteration = iteration
			_nav.target_position = _move_point
		if _nav.is_navigation_finished():
			_has_move_target = false
			velocity = Vector3.ZERO
			return
		next_point = _nav.get_next_path_position()
	elif flat_distance(global_position, _move_point) < 0.4:
		_has_move_target = false
		velocity = Vector3.ZERO
		return
	var d := next_point - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	velocity = steer_around_trees(d.normalized()) * get_move_speed()
	move_and_slide()
	face_toward(next_point)
	# Pressed against something for a while: ask for a fresh path.
	if get_real_velocity().length() < get_move_speed() * 0.25:
		_blocked_time += get_physics_process_delta_time()
		if _blocked_time > 0.75:
			_blocked_time = 0.0
			if _nav_ready():
				_nav.target_position = _move_point
	else:
		_blocked_time = 0.0


# --- Death -------------------------------------------------------------------

func _on_death(_killer: Unit) -> void:
	deaths += 1
	protect_style = -1
	_queued_cast = {}
	_has_move_target = false
	recall_timer = -1.0
	_stacks = 0
	respawn_timer = float(GameData.rule("respawn_base_sec", 6)) + float(GameData.rule("respawn_per_level", 2)) * level
	collision_layer = 0
	if osrs != null and is_inside_tree():
		# Play the death animation, then vanish until respawn.
		osrs.die()
		get_tree().create_timer(1.6, false).timeout.connect(func() -> void:
			if is_dead:
				visible = false)
	else:
		visible = false


func _dead_process(delta: float) -> void:
	for k in cooldowns:
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		respawn()


func respawn() -> void:
	is_dead = false
	health = max_health
	prayer = prayer_max
	global_position = spawn_point
	visible = true
	collision_layer = LAYER_UNITS
	if osrs != null:
		osrs.revive()
	_bot_waypoint = 1
	respawned.emit(self)


# --- Bot AI --------------------------------------------------------------------
## A deliberately simple lane bot so the prototype has someone to fight.

func _bot_update(delta: float) -> void:
	_bot_think -= delta
	if _bot_think > 0.0 or is_recalling():
		return
	_bot_think = 0.25
	var home_d := flat_distance(global_position, spawn_point)

	if health_ratio() < 0.3 and home_d > 12.0:
		if find_nearest_enemy(7.0, false, false) == null and not has_status("tele_block"):
			start_recall()
		else:
			command_move(spawn_point)
		return
	if in_shop_range():
		_bot_shop()
	elif gold >= 1400.0 and home_d > 30.0 and _nearest_enemy_champion(14.0) == null \
			and not has_status("tele_block") and _next_affordable_item() != "":
		start_recall()   # go home to spend gold, like a real player would
		return
	if home_d < 12.0 and health_ratio() < 0.95:
		command_stop()
		return
	if health_ratio() < 0.5 and not consumables.is_empty() and not has_status("heal_over_time"):
		use_consumable(0)

	var foe := _nearest_enemy_champion(12.0)
	if foe != null and prayer > 15.0:
		if protect_style != foe.attack_style:
			toggle_protect(foe.attack_style)
	elif foe == null and protect_style >= 0:
		toggle_protect(protect_style)

	_bot_support_allies()

	var target: Unit = foe if foe != null and flat_distance_to(foe) < 9.0 else null
	if target == null:
		target = find_nearest_enemy(9.0, _allied_minions_near(10.0) >= 2, false)
	if target != null:
		if target == foe:
			activate_offensive_prayer()
		var acted := false
		for slot in ["r", "q", "w", "e"]:
			if _bot_try_ability(slot, target):
				acted = true
				break
		if not acted and target is Champion and flat_distance_to(target) <= get_attack_range() + 2.0:
			for i in inventory.size():
				if use_item(i, target, target.global_position):
					break
		if _queued_cast.is_empty() and attack_target != target:
			command_attack(target)
		return

	var path := MapLayout.lane_path(bot_lane, team)
	var minion := _front_allied_minion(45.0)
	if minion != null:
		var behind := minion.global_position - (path[path.size() - 1] - minion.global_position).normalized() * 3.0
		if flat_distance(global_position, behind) > 2.0:
			command_move(behind)
	else:
		var hold := MapLayout.point_along(path, MapLayout.hold_distance(bot_lane))
		if flat_distance(global_position, hold) > 3.0:
			command_move(hold)


## Bots follow the build's recommended item path, skipping items they can't
## wear (requirements) and components they've already upgraded.
func _bot_shop() -> void:
	for id in def.get("recommended_items", []):
		if inventory.has(id) or _owns_upgrade_of(str(id)):
			continue
		if can_buy(str(id)):
			buy_item(str(id))
	while consumables.size() < 2 and can_buy("shark"):
		buy_item("shark")


## First item on the build path this bot could buy right now (ignoring shop range).
func _next_affordable_item() -> String:
	for id in def.get("recommended_items", []):
		var item_id := str(id)
		if inventory.has(item_id) or _owns_upgrade_of(item_id) or not meets_requirements(item_id):
			continue
		if gold >= float(item_cost(item_id)):
			return item_id
	return ""


func _owns_upgrade_of(item_id: String) -> bool:
	for owned in inventory:
		if _builds_into(item_id, owned):
			return true
	return false


func _builds_into(component: String, item_id: String) -> bool:
	for c in GameData.item(item_id).get("builds_from", []):
		if c == component or _builds_into(component, str(c)):
			return true
	return false


func _bot_try_ability(slot: String, target: Unit) -> bool:
	var ab := get_ability(slot)
	if ab.is_empty() or ranks[slot] <= 0 or cooldowns[slot] > 0.0 or spec < float(ab.get("spec_cost", 0.0)):
		return false
	if slot == "r" and not (target is Champion or target.is_epic):
		return false
	var use := str(ab.get("bot_use", "combat"))
	if use == "never" or (use == "low_health" and health_ratio() > 0.5) or (use == "high_health" and health_ratio() < 0.7):
		return false
	if ab.has("planter"):
		return _bot_timber(slot, ab, target)
	var dist := flat_distance_to(target)
	match str(ab.get("cast", "self")):
		"self":
			if dist > get_attack_range() + 2.0:
				return false
			return try_cast(slot, null, global_position)
		"target_unit":
			if bool(ab.get("target_ally", false)):
				return false
			if dist > ability_range(ab) + 1.0:
				return false
			return try_cast(slot, target, target.global_position)
		"point":
			if dist > ability_range(ab):
				return false
			return try_cast(slot, target, target.global_position)
	return false


## Timber! for bots: chop a yew whose fall line covers the target; otherwise
## plant one between itself and the target so the next cast fells it onto them.
func _bot_timber(slot: String, ab: Dictionary, target: Unit) -> bool:
	var cfg: Dictionary = ab.get("planter", {})
	var size := planter_fall_size(ab)
	for t in standing_trees():
		if flat_distance_to(t) > chop_range(cfg):
			continue
		var dir := PlantedTree.fall_direction(global_position, t.global_position, forward())
		var to := target.global_position - t.global_position
		to.y = 0.0
		var along := to.dot(dir)
		if along > 0.0 and along <= size.x and (to - dir * along).length() <= size.y * 0.5 + target.radius:
			return try_cast(slot, target, t.global_position)
	var dist := flat_distance_to(target)
	if dist < 3.0 or dist > size.x:
		return false
	var toward := target.global_position - global_position
	toward.y = 0.0
	var spot := global_position + toward.normalized() * 1.9
	if planter_tree_at(spot, cfg) != null:
		return false     # a yew is already there; wait to line it up
	return try_cast(slot, target, spot)


func _bot_support_allies() -> void:
	for slot in SLOTS:
		var ab := get_ability(slot)
		if not bool(ab.get("target_ally", false)) or ranks[slot] <= 0 or cooldowns[slot] > 0.0:
			continue
		var weakest: Champion = null
		for n in get_tree().get_nodes_in_group("champions"):
			var c := n as Champion
			if c == null or c.is_dead or c.team != team:
				continue
			if c == self and not bool(ab.get("allow_self", false)):
				continue
			if flat_distance_to(c) > ability_range(ab) + 2.0 or c.health_ratio() > 0.6:
				continue
			if weakest == null or c.health_ratio() < weakest.health_ratio():
				weakest = c
		if weakest != null and try_cast(slot, weakest, weakest.global_position):
			return


func _nearest_enemy_champion(max_range: float) -> Champion:
	var best: Champion = null
	var best_d := max_range
	for n in get_tree().get_nodes_in_group("champions"):
		var c := n as Champion
		if c == null or c.is_dead or c.team == team:
			continue
		var d := flat_distance_to(c)
		if d < best_d:
			best_d = d
			best = c
	return best


func _allied_minions_near(r: float) -> int:
	var count := 0
	for n in get_tree().get_nodes_in_group("minions"):
		var m := n as Unit
		if m != null and not m.is_dead and m.team == team and flat_distance_to(m) <= r:
			count += 1
	return count


func _front_allied_minion(max_range: float) -> Unit:
	var enemy_base := MapLayout.base_position(1 - team)
	var best: Unit = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("minions"):
		var m := n as Minion
		if m == null or m.is_dead or m.team != team or m.lane != bot_lane or flat_distance_to(m) > max_range:
			continue
		var d := flat_distance(m.global_position, enemy_base)
		if d < best_d:
			best_d = d
			best = m
	return best
