class_name ChampionSelect
extends CanvasLayer
## Pick a build to play. Hover a card to read its kit.

signal champion_selected(id: String)

var _detail: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.04, 0.93)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var title := Label.new()
	title.text = "Gielinor Legends"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.92, 0.78, 0.4))
	col.add_child(title)

	var sub := Label.new()
	sub.text = "Choose your build"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	col.add_child(sub)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for id in GameData.champion_order:
		var c := GameData.champion(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 96)
		b.text = "%s\n%s\n%s" % [c.get("name", id), c.get("role", ""), str(c.get("style", "")).capitalize()]
		b.pressed.connect(func() -> void: champion_selected.emit(id))
		b.mouse_entered.connect(_show_detail.bind(id))
		grid.add_child(b)

	_detail = Label.new()
	_detail.custom_minimum_size = Vector2(1300, 190)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 16)
	col.add_child(_detail)

	var credit := Label.new()
	credit.text = "A free, non-commercial fan project. Old School RuneScape and RuneScape are trademarks of Jagex Ltd."
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.add_theme_font_size_override("font_size", 13)
	credit.modulate = Color(1, 1, 1, 0.6)
	col.add_child(credit)


func _show_detail(id: String) -> void:
	var c := GameData.champion(id)
	var lines: Array[String] = []
	lines.append("%s — %s   |   %s" % [c.get("name", id), c.get("title", ""), c.get("build", "")])
	var sk: Dictionary = c.get("skills", {})
	lines.append("Attack %s · Strength %s · Defence %s · Ranged %s · Magic %s · Prayer %s%s" % [
		sk.get("attack", 1), sk.get("strength", 1), sk.get("defence", 1), sk.get("ranged", 1),
		sk.get("magic", 1), sk.get("prayer", 1), "   ·   Overheads" if c.get("overheads", false) else ""])
	var p: Dictionary = c.get("passive", {})
	lines.append("Passive — %s: %s" % [p.get("name", ""), p.get("text", "")])
	for slot in Champion.SLOTS:
		var ab: Dictionary = c.get("abilities", {}).get(slot, {})
		lines.append("%s — %s: %s" % [slot.to_upper(), ab.get("name", ""), ab.get("text", "")])
	_detail.text = "\n".join(lines)
