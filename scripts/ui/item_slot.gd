class_name ItemSlot
extends Panel
## One inventory square: the item's OSRS icon (or its name), hotkey,
## and a cooldown shade for spec weapons. Hover for the full description.

## Right-click (the HUD sells the item while the shop is open).
signal secondary_pressed
## Another inventory slot's item was dragged onto this one: (from slot, to slot).
signal item_dropped(from_slot: int, to_slot: int)

## Which inventory slot this is (0-5); -1 for the potion belt, which isn't draggable.
var slot_index := -1

var item_id := ""
## Extra last line of the tooltip ("Right-click to sell: 840 gp"), set by the HUD.
var sell_line := ""
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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		secondary_pressed.emit()
		accept_event()


## Drag an item to another slot to move it there (or swap with what's there).
func _get_drag_data(_at_position: Vector2) -> Variant:
	if slot_index < 0 or item_id == "":
		return null
	var preview := Control.new()
	var icon := Icons.rect(preview, Icons.item(item_id), Vector2(40, 40))
	icon.position = Vector2(-20, -20)
	icon.size = Vector2(40, 40)
	icon.modulate = Color(1, 1, 1, 0.85)
	if icon.texture == null:
		var l := UiStyle.label(preview, str(GameData.item(item_id).get("name", item_id)), 12)
		l.position = Vector2(-30, -8)
	set_drag_preview(preview)
	return {"inventory_slot": slot_index, "id": item_id}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return slot_index >= 0 and data is Dictionary and (data as Dictionary).has("inventory_slot") and int(data["inventory_slot"]) != slot_index


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(int(data["inventory_slot"]), slot_index)


func set_key_text(t: String) -> void:
	_key.text = t


func _get_tooltip(_at_position: Vector2) -> String:
	if sell_line == "" or tooltip_text == "":
		return tooltip_text
	return tooltip_text + "\n\n" + sell_line


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
static func use_text(use: Dictionary, mult: float = 1.0, champ: Champion = null) -> String:
	var parts := use_parts(use, mult, champ)
	return ("Use: " + ", ".join(parts)) if not parts.is_empty() else "Consumable"


## The effects of a food or potion, scaled by `mult`. With a champion,
## skill boosts show its real levels ("Strength +14"); without, the OSRS
## formula ("Strength +5 +15%").
static func use_parts(use: Dictionary, mult: float = 1.0, champ: Champion = null) -> Array[String]:
	var parts: Array[String] = []
	if use.has("heal"):
		parts.append("Heals %d" % roundi(float(use["heal"]) * mult))
	if use.has("heal_over_time"):
		parts.append("Heals %d over %ds" % [roundi(float(use["heal_over_time"]) * mult), int(use.get("duration", 5))])
	if use.has("heal_pct_max"):
		parts.append("Heals %d%% of max health" % roundi(float(use["heal_pct_max"]) * 100.0 * mult))
	if use.has("prayer"):
		parts.append("Restores %d prayer" % roundi(float(use["prayer"]) * mult))
	var levels: Array[String] = []
	for st in use.get("statuses", []):
		var kind := str(st["kind"])
		if kind == "skill_boost":
			# Flavour: the OSRS skill levels it boosts (the skills panel shows them).
			var sk := str(st.get("skill", "")).capitalize()
			var lv := champ.potion_levels(st, mult) if champ != null else int(st.get("flat", 0))
			levels.append("%s %s%d" % [sk, "+" if lv >= 0 else "", lv])
			continue
		var raw := float(st.get("amount", 0.0))
		var amt := raw * mult if raw > 0.0 else raw
		var what: String = {"damage_mult": "damage", "attack_damage_mult": "Attack Damage", "magic_damage_mult": "Magic Damage",
			"crit_chance": "crit chance", "crit_damage_mult": "Crit Damage", "armor_mult": "Defence", "haste": "move speed"}.get(kind, "")
		var only := str((st.get("data", {}) as Dictionary).get("style", ""))
		if what != "" and only != "":
			what = "%s %s" % [only.capitalize(), what if what != "Attack Damage" else "Damage"]
		if what != "":
			parts.append("%s%d%% %s for %ds" % ["+" if amt >= 0.0 else "", roundi(amt * 100.0), what, int(st.get("duration", 0))])
		elif kind == "antipoison":
			parts.append("poison immunity for %ds" % roundi(float(st.get("duration", 0)) * mult))
	if not levels.is_empty():
		var lv_text := "(%s levels)" % ", ".join(levels)
		if parts.is_empty():
			parts.append(lv_text)
		else:
			parts[parts.size() - 1] += " " + lv_text
	if bool(use.get("restore_skills", false)):
		parts.append("restores lowered levels")
	return parts


## The 'perfect' line under a consumable's normal effect.
static func perfect_text(it: Dictionary, champ: Champion = null) -> String:
	var pot: Dictionary = it.get("potency", {})
	if pot.is_empty() or not it.has("use"):
		return ""
	var bonus := float(GameData.rule("potency_bonus", 0.15))
	var base := 1.0 + (champ._item_stat("consumable_bonus") if champ != null else 0.0)
	var parts := use_parts(it["use"], base + bonus, champ)
	var yours := champ != null and champ.is_perfect(str(it.get("id", "")))
	return "'perfect' (%s): %s%s" % [_levels(pot), ", ".join(parts), "  (yours)" if yours else ""]


static func _tooltip(it: Dictionary, champ: Champion = null) -> String:
	var lines: Array[String] = [str(it.get("name", ""))]
	var id := str(it.get("id", ""))
	var reqs: Dictionary = it.get("requirements", {})
	if not reqs.is_empty():
		var parts: Array[String] = []
		for s in reqs:
			parts.append("%d %s" % [int(reqs[s]), str(s).capitalize()])
		lines.append("Requires " + ", ".join(parts))
	var art: Dictionary = it.get("artisan", {})
	if not art.is_empty():
		lines.append("Make your own: %s waives the combat requirements" % _levels(art))
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
		# The normal effect, then the 'perfect' one on the next line.
		var normal := 1.0 + (champ._item_stat("consumable_bonus") if champ != null else 0.0)
		lines.append(use_text(it["use"], normal, champ))
		var perfect := perfect_text(it, champ)
		if perfect != "":
			lines.append(perfect)
	if it.has("text"):
		lines.append(str(it["text"]))
	return "\n".join(lines)
