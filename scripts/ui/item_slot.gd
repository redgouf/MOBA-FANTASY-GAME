class_name ItemSlot
extends Panel
## One inventory square: the item's OSRS icon (or its name), hotkey,
## and a cooldown shade for spec weapons. Hover for the full description.

var item_id := ""
var compact := false
## Whose item this is (tooltips show Perfect food and make-your-own for them).
var champ: Champion

var _name: Label
var _icon: TextureRect
var _key: Label
var _shade: ColorRect
var _cd: Label
var _empty_style: StyleBoxFlat
var _full_style: StyleBoxFlat
var _spec_style: StyleBoxFlat


static func create(parent: Control, size: float, key_text: String = "", p_compact: bool = false) -> ItemSlot:
	var s := ItemSlot.new()
	s.compact = p_compact
	s.custom_minimum_size = Vector2(size, size)
	s.size = Vector2(size, size)
	parent.add_child(s)
	s._build(key_text)
	return s


func _build(key_text: String) -> void:
	_empty_style = UiStyle.box(UiStyle.BG_DARK, UiStyle.BORDER.darkened(0.35), 1, 3)
	_full_style = UiStyle.box(UiStyle.BG_SLOT, UiStyle.BORDER, 1, 3)
	_spec_style = UiStyle.box(UiStyle.BG_SLOT, UiStyle.SPEC.darkened(0.15), 2, 3)
	add_theme_stylebox_override("panel", _empty_style)
	_name = UiStyle.label(self, "", 12 if compact else 10)
	UiStyle.fill(_name, 2, 0, 2)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.add_theme_constant_override("line_spacing", -3)
	_icon = Icons.rect(self, null, Vector2.ZERO)
	UiStyle.fill(_icon, 3, 3, 3, 3)
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.62)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.visible = false
	add_child(_shade)
	_cd = UiStyle.label(self, "", 16, Color.WHITE)
	UiStyle.fill(_cd)
	_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key = UiStyle.label(self, key_text, 10, UiStyle.MUTED)
	_key.position = Vector2(3, 0)


## cooldown_left/cooldown_total in seconds (0 = ready or no active).
func set_item(id: String, cooldown_left: float = 0.0, cooldown_total: float = 0.0) -> void:
	if id != item_id:
		item_id = id
		var it := GameData.item(id)
		var item_name := str(it.get("name", ""))
		_icon.texture = Icons.item(id)
		# The OSRS icon when there is one; the (short) name otherwise.
		_name.text = "" if _icon.texture != null else (UiStyle.short_name(item_name) if compact else item_name)
		tooltip_text = UiStyle.wrap(_tooltip(it, champ)) if id != "" else ""
		if id == "":
			add_theme_stylebox_override("panel", _empty_style)
		elif it.has("spec_active"):
			add_theme_stylebox_override("panel", _spec_style)
		else:
			add_theme_stylebox_override("panel", _full_style)
	var cooling := cooldown_left > 0.0 and cooldown_total > 0.0
	_shade.visible = cooling
	_cd.text = str(ceili(cooldown_left)) if cooling else ""
	if cooling:
		var h := size.y * clampf(cooldown_left / cooldown_total, 0.0, 1.0)
		_shade.position = Vector2(0, size.y - h)
		_shade.size = Vector2(size.x, h)


## One stat line: "+12% attack speed", "+5 prayer bonus", "+25 damage".
## "Perfect shark" for food, "Super restore (perfect)" for potions.
static func perfect_name(it: Dictionary) -> String:
	var n := str(it.get("name", ""))
	var use: Dictionary = it.get("use", {})
	if use.has("heal") or use.has("heal_over_time") or use.has("heal_pct_max"):
		return "Perfect " + n.to_lower()
	return n + " (perfect)"


static func _levels(d: Dictionary) -> String:
	var parts: Array[String] = []
	for s in d:
		parts.append("%d %s" % [int(d[s]), str(s).capitalize()])
	return ", ".join(parts)


static func stat_text(k: String, v: float) -> String:
	match k:
		"attack_speed", "spec_regen", "armor_pen":
			return "+%d%% %s" % [roundi(v * 100.0), {"attack_speed": "attack speed", "spec_regen": "spec energy regen", "armor_pen": "armour penetration"}[k]]
		"gold_bonus":
			return "+%d%% gold from last hits" % roundi(v * 100.0)
		"monster_damage":
			return "+%d%% damage to monsters" % roundi(v * 100.0)
		"structure_damage":
			return "+%d%% damage to towers and buildings" % roundi(v * 100.0)
		"consumable_bonus":
			return "Food and potions +%d%% stronger" % roundi(v * 100.0)
		"skill_power":
			return "+%s skill power (adds to basic attacks)" % str(v).trim_suffix(".0")
		"burn_on_hit":
			return "Attacks burn: %d a second for 2s" % roundi(v)
		"defence_all":
			return "+%s defence (all styles)" % str(v).trim_suffix(".0")
	return "+%s %s" % [str(snappedf(v, 0.01)).trim_suffix(".0"), k.replace("_", " ")]


## What a food or potion does: "Heals 160 over 5s", "+5% damage for 60s".
## `mult` scales the amounts (a Perfect item for you shows its real numbers).
static func use_text(use: Dictionary, mult: float = 1.0) -> String:
	var parts: Array[String] = []
	if use.has("heal"):
		parts.append("Heals %d" % roundi(float(use["heal"]) * mult))
	if use.has("heal_over_time"):
		parts.append("Heals %d over %ds" % [roundi(float(use["heal_over_time"]) * mult), int(use.get("duration", 5))])
	if use.has("heal_pct_max"):
		parts.append("Heals %d%% of max health" % roundi(float(use["heal_pct_max"]) * 100.0 * mult))
	if use.has("prayer"):
		parts.append("Restores %d prayer" % roundi(float(use["prayer"]) * mult))
	for st in use.get("statuses", []):
		var amt := float(st.get("amount", 0.0)) * mult
		var what: String = {"damage_mult": "damage", "armor_mult": "armour", "haste": "move speed"}.get(str(st["kind"]), "")
		if what != "":
			parts.append("%s%d%% %s for %ds" % ["+" if amt >= 0.0 else "", roundi(amt * 100.0), what, int(st.get("duration", 0))])
	return ("Use: " + ", ".join(parts)) if not parts.is_empty() else "Consumable"


static func _tooltip(it: Dictionary, champ: Champion = null) -> String:
	var lines: Array[String] = [str(it.get("name", ""))]
	var id := str(it.get("id", ""))
	if champ != null and champ.is_perfect(id):
		lines[0] = perfect_name(it)
	var reqs: Dictionary = it.get("requirements", {})
	if not reqs.is_empty():
		var parts: Array[String] = []
		for s in reqs:
			parts.append("%d %s" % [int(reqs[s]), str(s).capitalize()])
		lines.append("Requires " + ", ".join(parts))
	var art: Dictionary = it.get("artisan", {})
	if not art.is_empty():
		lines.append("Make your own: %s waives the combat requirements" % _levels(art))
	var pot: Dictionary = it.get("potency", {})
	if not pot.is_empty():
		lines.append("Anyone can use it. Perfect with %s: +%d%% stronger" % [_levels(pot), roundi(float(GameData.rule("potency_bonus", 0.15)) * 100.0)])
	var stats: Dictionary = it.get("stats", {})
	for k in stats:
		if k == "elysian":
			continue   # described by the item's text
		if k == "defence":
			for s in stats[k]:
				lines.append("+%s %s defence" % [stats[k][s], s])
		else:
			lines.append(stat_text(str(k), float(stats[k])))
	if it.has("spec_active"):
		var sa: Dictionary = it["spec_active"]
		lines.append("Spec: %s (%d%% energy, %ds cooldown)" % [sa.get("name", ""), int(sa.get("spec_cost", 0)), int(sa.get("cooldown", 0))])
	if it.has("use"):
		lines.append(use_text(it["use"], champ.consumable_mult(id) if champ != null else 1.0))
	if it.has("text"):
		lines.append(str(it["text"]))
	return "\n".join(lines)
