class_name ItemSlot
extends Panel
## One inventory square: item name (full or abbreviated), hotkey,
## and a cooldown shade for spec weapons. Hover for the full description.

var item_id := ""
var compact := false

var _name: Label
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
		_name.text = UiStyle.short_name(item_name) if compact else item_name
		tooltip_text = _tooltip(it) if id != "" else ""
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


static func _tooltip(it: Dictionary) -> String:
	var lines: Array[String] = [str(it.get("name", ""))]
	var reqs: Dictionary = it.get("requirements", {})
	if not reqs.is_empty():
		var parts: Array[String] = []
		for s in reqs:
			parts.append("%d %s" % [int(reqs[s]), str(s).capitalize()])
		lines.append("Requires " + ", ".join(parts))
	var stats: Dictionary = it.get("stats", {})
	for k in stats:
		if k == "defence":
			for s in stats[k]:
				lines.append("+%s %s defence" % [stats[k][s], s])
		else:
			lines.append("+%s %s" % [stats[k], str(k).replace("_", " ")])
	if it.has("spec_active"):
		var sa: Dictionary = it["spec_active"]
		lines.append("Spec: %s (%d%% energy, %ds cooldown)" % [sa.get("name", ""), int(sa.get("spec_cost", 0)), int(sa.get("cooldown", 0))])
	if it.has("use"):
		lines.append("Consumable")
	if it.has("text"):
		lines.append(str(it["text"]))
	return "\n".join(lines)
