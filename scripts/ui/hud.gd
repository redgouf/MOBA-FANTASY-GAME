class_name Hud
extends CanvasLayer
## Whitebox HUD built in code: resources, kit, item specs, shop, kill feed.

const HP_COLOR := Color(0.25, 0.75, 0.25)
const PRAYER_COLOR := Color(0.3, 0.75, 0.95)
const SPEC_COLOR := Color(0.95, 0.8, 0.2)

var main: Node
var champ: Champion

var _info: Label
var _target: Label
var _feed: Label
var _message: Label
var _name: Label
var _hp_label: Label
var _hp_bar: ProgressBar
var _prayer_label: Label
var _prayer_bar: ProgressBar
var _spec_label: Label
var _spec_bar: ProgressBar
var _ability_labels: Dictionary = {}
var _items_label: Label
var _status_label: Label
var _shop: PanelContainer
var _shop_list: VBoxContainer
var _shop_gold: Label
var _game_over: Label

var _feed_lines: Array[String] = []
var _message_timer := 0.0
var _shop_refresh := 0.0


func setup(p_main: Node, p_champ: Champion) -> void:
	main = p_main
	champ = p_champ


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_info = _label(root, 16)
	_info.position = Vector2(16, 12)

	_target = _label(root, 18)
	_target.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target.position = Vector2(-200, 12)
	_target.size = Vector2(400, 30)

	_feed = _label(root, 15)
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.position = Vector2(-440, 12)
	_feed.size = Vector2(424, 200)

	_message = _label(root, 34)
	_message.set_anchors_preset(Control.PRESET_CENTER)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.position = Vector2(-400, -160)
	_message.size = Vector2(800, 60)

	_build_bottom_panel(root)
	_build_shop(root)

	_game_over = _label(root, 56)
	_game_over.set_anchors_preset(Control.PRESET_CENTER)
	_game_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.position = Vector2(-500, -40)
	_game_over.size = Vector2(1000, 80)
	_game_over.visible = false


func _build_bottom_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-560, -150)
	panel.size = Vector2(1120, 140)
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var bars := VBoxContainer.new()
	bars.custom_minimum_size = Vector2(300, 0)
	row.add_child(bars)
	_name = _label(bars, 17)
	_hp_label = _label(bars, 13)
	_hp_bar = _bar(bars, HP_COLOR)
	_prayer_label = _label(bars, 13)
	_prayer_bar = _bar(bars, PRAYER_COLOR)
	_spec_label = _label(bars, 13)
	_spec_bar = _bar(bars, SPEC_COLOR)

	for slot in Champion.SLOTS:
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(130, 120)
		row.add_child(box)
		var l := _label(box, 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ability_labels[slot] = l

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(240, 0)
	row.add_child(side)
	_items_label = _label(side, 13)
	_items_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label = _label(side, 13)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_shop(root: Control) -> void:
	_shop = PanelContainer.new()
	_shop.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_shop.position = Vector2(-560, -330)
	_shop.size = Vector2(540, 560)
	_shop.visible = false
	root.add_child(_shop)
	var col := VBoxContainer.new()
	_shop.add_child(col)
	var title := _label(col, 20)
	title.text = "Grand Exchange (P to close)"
	_shop_gold = _label(col, 15)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_shop_list = VBoxContainer.new()
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shop_list)


func toggle_shop() -> void:
	_shop.visible = not _shop.visible
	if _shop.visible:
		_rebuild_shop()


func _rebuild_shop() -> void:
	for c in _shop_list.get_children():
		c.queue_free()
	for id in GameData.item_order:
		var it := GameData.item(id)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var missing := champ.missing_requirements(id)
		var line := "%s  —  %d GP" % [it.get("name", id), champ.item_cost(id)]
		if not missing.is_empty():
			line += "   [requires %s]" % ", ".join(missing)
		line += "\n" + _describe_item(it)
		b.text = line
		b.disabled = not champ.in_shop_range() or not champ.can_buy(id)
		b.pressed.connect(_on_buy.bind(id))
		_shop_list.add_child(b)


func _describe_item(it: Dictionary) -> String:
	var parts: Array[String] = []
	var stats: Dictionary = it.get("stats", {})
	for k in stats:
		if k == "defence":
			for s in stats[k]:
				parts.append("+%s %s def" % [stats[k][s], s])
		else:
			parts.append("+%s %s" % [stats[k], str(k).replace("_", " ")])
	if it.has("spec_active"):
		var sa: Dictionary = it["spec_active"]
		parts.append("Spec: %s (%d%%, %ds)" % [sa.get("name", "?"), int(sa.get("spec_cost", 0)), int(sa.get("cooldown", 0))])
	if it.has("text"):
		parts.append(str(it["text"]))
	return ", ".join(parts)


func _on_buy(id: String) -> void:
	if champ.in_shop_range() and champ.buy_item(id):
		_rebuild_shop()


func announce(text: String, big: bool = false) -> void:
	_feed_lines.push_front(text)
	if _feed_lines.size() > 8:
		_feed_lines.resize(8)
	_feed.text = "\n".join(_feed_lines)
	if big:
		_message.text = text
		_message_timer = 3.0


func show_game_over(victory: bool) -> void:
	_game_over.text = "Victory!" if victory else "Defeat — Oh dear, you are dead!"
	_game_over.visible = true


func _process(delta: float) -> void:
	if champ == null:
		return
	_message_timer -= delta
	if _message_timer <= 0.0:
		_message.text = ""
	var t := int(main.get("game_time"))
	_info.text = "%02d:%02d   |   %d GP   |   K/D/A %d/%d/%d   |   Level %d (combat %d)" % [
		t / 60, t % 60, int(champ.gold), champ.kills, champ.deaths, champ.assists, champ.level, champ.combat_level()]

	var name_line := "%s — %s" % [champ.display_name, champ.def.get("title", "")]
	if champ.is_dead:
		name_line += "   (respawn in %ds)" % ceili(champ.respawn_timer)
	elif champ.is_recalling():
		name_line += "   (teleporting %.1fs)" % champ.recall_timer
	_name.text = name_line
	_hp_label.text = "Hitpoints %d / %d" % [int(champ.health), int(champ.max_health)]
	_hp_bar.value = champ.health_ratio() * 100.0
	var overhead := "no overheads"
	if champ.has_overheads:
		overhead = "Protect from %s" % Combat.style_name(champ.protect_style) if champ.protect_style >= 0 else "overheads off (Z/X/C)"
	_prayer_label.text = "Prayer %d / %d   %s   |   V: %s" % [int(champ.prayer), int(champ.prayer_max), overhead, champ.offensive_prayer_name()]
	_prayer_bar.value = champ.prayer / champ.prayer_max * 100.0
	_spec_label.text = "Special attack %d%%" % int(champ.spec)
	_spec_bar.value = champ.spec

	for slot in Champion.SLOTS:
		var ab := champ.get_ability(slot)
		var state := "Ready"
		var cd: float = champ.cooldowns.get(slot, 0.0)
		var cost := float(ab.get("spec_cost", 0.0))
		if cd > 0.0:
			state = "%.1fs" % cd
		elif cost > 0.0 and champ.spec < cost:
			state = "Needs %d%% spec" % int(cost)
		elif cost > 0.0:
			state = "Spec %d%%" % int(cost)
		_ability_labels[slot].text = "[%s]\n%s\n%s" % [slot.to_upper(), ab.get("name", "-"), state]

	var item_lines: Array[String] = []
	for i in champ.inventory.size():
		var id := champ.inventory[i]
		var line := "%d: %s" % [i + 1, GameData.item(id).get("name", id)]
		var key := champ.item_action_key(i)
		if key != "":
			var cd: float = champ.cooldowns.get(key, 0.0)
			line += " (spec %s)" % ("%.0fs" % cd if cd > 0.0 else "ready")
		item_lines.append(line)
	var belt: Array[String] = []
	for i in champ.consumables.size():
		belt.append("%d: %s" % [(i + 7) % 10, GameData.item(champ.consumables[i]).get("name", "")])
	_items_label.text = "Items: " + (", ".join(item_lines) if not item_lines.is_empty() else "none (P for shop)") \
		+ "\nBelt: " + (", ".join(belt) if not belt.is_empty() else "empty")

	var st_names: Array[String] = []
	for id in champ.statuses:
		var kind: String = champ.statuses[id]["kind"]
		if kind != "root_immune" and not st_names.has(kind):
			st_names.append(kind)
	_status_label.text = "Status: " + (", ".join(st_names) if not st_names.is_empty() else "-")
	if champ.passive_stacks() > 0:
		_status_label.text += "   stacks %d" % champ.passive_stacks()
	if not champ.forms.is_empty():
		_status_label.text += "   form: %s" % champ.form_name()

	var ctrl: Variant = main.get("controller")
	var hov: Unit = ctrl.hovered if ctrl != null else null
	if is_instance_valid(hov):
		_target.text = "%s  %d / %d" % [hov.display_name, int(hov.health), int(hov.max_health)]
	else:
		_target.text = ""

	if _shop.visible:
		_shop_gold.text = "Gold: %d GP%s" % [int(champ.gold), "" if champ.in_shop_range() else "   (return to base to buy)"]
		_shop_refresh -= delta
		if _shop_refresh <= 0.0:
			_shop_refresh = 1.0
			_rebuild_shop()


func _label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(280, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1)
	bar.add_theme_stylebox_override("background", bg)
	parent.add_child(bar)
	return bar
