extends Node
## Loads all JSON game data (champions, items, units, rules) once at startup.
## Data lives in res://data so designers can tune numbers without touching code.

const DATA_DIR := "res://data/"

var rules: Dictionary = {}
var champions: Dictionary = {}       # id -> champion definition
var champion_order: Array[String] = []
var items: Dictionary = {}           # id -> item definition
var item_order: Array[String] = []
var units: Dictionary = {}           # "minions" / "structures" / "monsters" / "summons" -> {id: def}
## This game's rolled non-combat skill levels: champion id -> {skill: level}.
var skill_rolls: Dictionary = {}
## True when champion select rolled the levels it is showing, so the match
## that follows keeps them (a restart rolls new ones).
var rolls_from_select := false

## Combat skills: fixed per build. Every other OSRS skill is rolled each game.
const COMBAT_SKILLS: Array[String] = ["attack", "hitpoints", "strength", "defence", "ranged", "prayer", "magic"]
const ALL_SKILLS: Array[String] = ["attack", "hitpoints", "mining", "strength", "agility", "smithing",
	"defence", "herblore", "fishing", "ranged", "thieving", "cooking", "prayer", "crafting", "firemaking",
	"magic", "fletching", "woodcutting", "runecraft", "slayer", "farming", "construction", "hunter", "sailing"]


func _ready() -> void:
	load_all()


## hp_scale_override >= 0 replaces rules.hp_scale (tests check League values at 1.0).
func load_all(hp_scale_override: float = -1.0) -> void:
	rules = load_json("rules.json")
	Combat.configure(rules)

	champions.clear()
	champion_order.clear()
	for c in load_json("champions.json").get("champions", []):
		champions[c["id"]] = c
		champion_order.append(c["id"])

	items.clear()
	item_order.clear()
	for it in load_json("items.json").get("items", []):
		items[it["id"]] = it
		item_order.append(it["id"])

	units = load_json("units.json")
	var hs := hp_scale_override if hp_scale_override >= 0.0 else float(rules.get("hp_scale", 1.0))
	rules["hp_scale"] = hs
	apply_hp_scale(hs)


# --- Health and damage scale ---------------------------------------------------
## The data files keep League-sized numbers (minions, turrets, camps use real
## Summoner's Rift values). rules.hp_scale shrinks every health pool and every
## damage and healing amount by the same factor when the data loads, so
## hitsplats stay OSRS-sized (under ~256) while fights play out exactly the
## same. Ratios, percentages, defences and durations are untouched.

## Status kinds whose amount is health per second (not a percentage).
const ABSOLUTE_STATUS_KINDS: Array[String] = ["heal_over_time", "venom", "burn", "poison"]


func apply_hp_scale(s: float) -> void:
	if is_equal_approx(s, 1.0):
		return
	for id in champions:
		var c: Dictionary = champions[id]
		for block in ["base", "growth"]:
			_scale_keys(c.get(block, {}), ["max_health", "damage", "magic_power", "skill_power"], s)
		var p: Dictionary = c.get("passive", {})
		match str(p.get("type", "")):
			"venom":
				_scale_keys(p, ["start", "step", "max"], s)
			"flat_reduction":
				_scale_keys(p, ["factor"], s)
			"target_magic_scaling":
				p["per_magic_power"] = float(p.get("per_magic_power", 0.004)) / s
		_scale_effects(c, s)
	for id in items:
		var it: Dictionary = items[id]
		_scale_keys(it.get("stats", {}), ["health", "damage", "magic_power", "skill_power", "burn_on_hit"], s)
		var use: Dictionary = it.get("use", {})
		_scale_keys(use, ["heal", "heal_over_time"], s)
		for st in use.get("statuses", []):
			if ABSOLUTE_STATUS_KINDS.has(str(st.get("kind", ""))):
				_scale_keys(st, ["amount"], s)
		_scale_effects(it, s)
	for id in units.get("minions", {}):
		var m: Dictionary = units["minions"][id]
		for k in ["health", "damage"]:
			if m.get(k) is Array:
				var a: Array = m[k]
				for i in mini(4, a.size()):
					a[i] = float(a[i]) * s
	for cat in ["structures", "monsters", "summons"]:
		for id in units.get(cat, {}):
			var u: Dictionary = units[cat][id]
			for k in ["health", "max_health", "damage", "damage_per_minute", "damage_max", "regen"]:
				if not u.has(k):
					continue
				if u[k] is Array:
					var arr: Array = u[k]
					for i in arr.size():
						arr[i] = float(arr[i]) * s
				else:
					u[k] = float(u[k]) * s
	for p in rules.get("prayers", []):
		if str(p.get("special", "")) == "retribution":
			_scale_keys(p, ["amount", "per_level"], s)


func _scale_keys(d: Dictionary, keys: Array, s: float) -> void:
	for k in keys:
		if d.has(k) and (d[k] is float or d[k] is int):
			d[k] = float(d[k]) * s


## Every "effects" list in a definition (abilities, forms, spec actives,
## passives): flat damage and healing, and per-second status amounts.
func _scale_effects(node: Variant, s: float) -> void:
	if node is Dictionary:
		var d: Dictionary = node
		if d.get("effects") is Array:
			for e in d["effects"]:
				if not e is Dictionary:
					continue
				var t := str(e.get("type", ""))
				if t == "damage" or t == "heal":
					_scale_keys(e, ["base", "base_per_rank", "base_per_level", "cap"], s)
				if t == "status" and ABSOLUTE_STATUS_KINDS.has(str(e.get("kind", ""))):
					_scale_keys(e, ["amount"], s)
				for st in e.get("target_statuses", []):
					if ABSOLUTE_STATUS_KINDS.has(str(st.get("kind", ""))):
						_scale_keys(st, ["amount"], s)
		for k in d:
			if k != "effects":
				_scale_effects(d[k], s)
	elif node is Array:
		for v in node:
			_scale_effects(v, s)


static func load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("GameData: missing data file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: %s is not a JSON object" % path)
		return {}
	return parsed


## Rolls every champion's non-combat skills for a new game: each one
## rules.skill_roll [min, max] (20-60), unless the build fixes it (the
## Skiller's 99s) or sets its own range in "roll_ranges".
func roll_skills(from_select: bool = false) -> void:
	var span: Array = rule("skill_roll", [20, 60])
	skill_rolls.clear()
	for id in champion_order:
		var def: Dictionary = champions[id]
		var fixed: Dictionary = def.get("skills", {})
		var ranges: Dictionary = def.get("roll_ranges", {})
		var rolled := {}
		for s in ALL_SKILLS:
			if COMBAT_SKILLS.has(s) or fixed.has(s):
				continue
			var r: Array = ranges.get(s, span)
			rolled[s] = randi_range(int(r[0]), int(r[1]))
		skill_rolls[id] = rolled
	rolls_from_select = from_select


## Called when a match starts: keeps champion select's rolls, else rolls anew.
func ensure_match_rolls() -> void:
	if not rolls_from_select or skill_rolls.is_empty():
		roll_skills()
	rolls_from_select = false


## A build's full 24 skills this game: its fixed levels plus the rolled ones.
func skills_for(id: String) -> Dictionary:
	if skill_rolls.is_empty():
		roll_skills()
	var out: Dictionary = champion(id).get("skills", {}).duplicate()
	out.merge(skill_rolls.get(id, {}), false)
	for s in ALL_SKILLS:
		if not out.has(s):
			out[s] = 10 if s == "hitpoints" else 1
	return out


## The champion definition with this game's skills filled in (for UI panels).
func champion_with_skills(id: String) -> Dictionary:
	var d := champion(id).duplicate()
	d["skills"] = skills_for(id)
	return d


func rule(key: String, default: Variant = null) -> Variant:
	return rules.get(key, default)


func champion(id: String) -> Dictionary:
	return champions.get(id, {})


func item(id: String) -> Dictionary:
	return items.get(id, {})


func unit_def(category: String, id: String) -> Dictionary:
	return units.get(category, {}).get(id, {})
