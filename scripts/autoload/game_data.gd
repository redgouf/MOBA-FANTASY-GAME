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


func _ready() -> void:
	load_all()


func load_all() -> void:
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


func rule(key: String, default: Variant = null) -> Variant:
	return rules.get(key, default)


func champion(id: String) -> Dictionary:
	return champions.get(id, {})


func item(id: String) -> Dictionary:
	return items.get(id, {})


func unit_def(category: String, id: String) -> Dictionary:
	return units.get(category, {}).get(id, {})
