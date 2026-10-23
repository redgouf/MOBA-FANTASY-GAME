class_name AbilityTooltip
extends PanelContainer
## The ability tooltip, laid out for reading at a glance (League style):
##   header   icon, "[W] Name" and the rank on the left; cooldown and
##            special-attack cost on the right
##   ------   a thin teal line
##   body     what it does, with each damage or heal written out:
##            "172 = (140 +90% Damage) melee damage", coloured by type
##   ------
##   table    every value that grows with rank, one row each:
##            "Damage   [ 60 / 108 / 156 / 204 / 252 ]", current rank bright
## Built by AbilitySlot._make_custom_tooltip from AbilityInfo.tooltip_data().

const BG := Color(0.02, 0.05, 0.06, 0.96)
const EDGE := Color(0.24, 0.5, 0.48)
const LINE := Color(0.24, 0.5, 0.48, 0.9)
const TEXT := Color(0.86, 0.87, 0.84)
const MUTED := Color(0.55, 0.57, 0.55)
const BRIGHT := Color(1.0, 1.0, 1.0)
const CD := Color(0.86, 0.8, 0.62)
const WIDTH := 460.0


static func build(data: Dictionary) -> AbilityTooltip:
	var t := AbilityTooltip.new()
	t._build(data)
	return t


static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	return sb


func _build(data: Dictionary) -> void:
	# The tooltip popup itself draws the dark teal panel (UiStyle's tooltip theme).
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	custom_minimum_size = Vector2(WIDTH, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	# Header: icon, [KEY] name, rank | cooldown, cost.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var tex: Texture2D = data.get("icon")
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.custom_minimum_size = Vector2(52, 52)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		head.add_child(icon)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	head.add_child(left)
	_label(left, str(data.get("title", "")), 19, BRIGHT)
	if str(data.get("subtitle", "")) != "":
		_label(left, str(data.get("subtitle", "")), 13, MUTED)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	head.add_child(right)
	if str(data.get("cooldown", "")) != "":
		_label(right, str(data["cooldown"]), 17, CD).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if str(data.get("cost", "")) != "":
		_label(right, str(data["cost"]), 14, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_line(col)
	var body := RichTextLabel.new()
	body.name = "Body"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	body.add_theme_font_size_override("normal_font_size", 15)
	body.add_theme_font_size_override("bold_font_size", 15)
	body.add_theme_font_size_override("italics_font_size", 14)
	body.add_theme_color_override("default_color", TEXT)
	body.text = str(data.get("body", ""))
	col.add_child(body)

	var rows: Array = data.get("rows", [])
	if not rows.is_empty():
		_line(col)
		var grid := GridContainer.new()
		grid.name = "Ranks"
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 2)
		col.add_child(grid)
		for row in rows:
			_label(grid, str(row["label"]), 15, TEXT)
			var vals := RichTextLabel.new()
			vals.bbcode_enabled = true
			vals.fit_content = true
			vals.scroll_active = false
			vals.autowrap_mode = TextServer.AUTOWRAP_OFF
			vals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vals.add_theme_font_size_override("normal_font_size", 15)
			vals.add_theme_font_size_override("bold_font_size", 15)
			vals.add_theme_color_override("default_color", MUTED)
			vals.text = "[right]%s[/right]" % rank_values(row["values"], int(data.get("rank", 0)))
			grid.add_child(vals)
	if str(data.get("footer", "")) != "":
		_label(col, str(data["footer"]), 13, MUTED)


## "[ 60 / 108 / [b]156[/b] / 204 / 252 ]" with the current rank bright.
static func rank_values(values: Array, rank: int) -> String:
	var parts: Array[String] = []
	for i in values.size():
		var v := str(values[i])
		parts.append("[color=#ffffff][b]%s[/b][/color]" % v if i + 1 == rank else v)
	return "[ %s ]" % " / ".join(parts)


func _label(parent: Node, s: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _line(parent: Node) -> void:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size = Vector2(0, 1)
	parent.add_child(r)
