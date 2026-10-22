class_name PauseMenu
extends CanvasLayer
## ESC menu. Pauses the match (single-player vs bots) and offers
## Resume, Settings, Controls, Restart match, Change champion and Quit.
## ESC closes the shop first if it's open, like League.

signal restart_requested
signal change_champion_requested
signal spectate_requested

var spectating := false

const CONTROLS_TEXT := """Right-click — move, or attack the unit under the cursor
Left-click — select a unit to inspect it (top-left)
Q W E R — abilities (R is your special attack): hold to aim, release to cast
   (Settings > Ability casting: normal cast = press, then left-click; right-click or Esc cancels)
Ctrl + Q W E R — spend a skill point (R unlocks at level 6)
1 – 6 — item special attacks
7 8 9 0 — food and potions
Z X C — Protect from Melee / Missiles / Magic (tank and main builds)
V — offensive prayer (best your Prayer level allows)
B — teleport home      P — shop      S — stop      Tab (hold) — scoreboard
Middle-mouse drag — grab and pan the map
Minimap — left-click to look, right-click to walk
Space — centre on your champion      Y — lock camera
Arrow keys / screen edge / mouse wheel — pan and zoom
Esc — close the shop, or open this menu

Spectator (NPC vs NPC) mode:
Left-click a champion or its roster card — lock onto it (its HUD, camera and cursor)
1 – 5 / 6 – 0 — lock onto a Saradomin / Zamorak champion
Y — toggle the camera lock      Left-click anything else — inspect it"""

var hud: Hud

var _dim: ColorRect
var _panel: PanelContainer
var _pages: Dictionary = {}
var _title: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	UiStyle.fill(_dim)
	add_child(_dim)

	var center := CenterContainer.new()
	UiStyle.fill(center)
	_dim.add_child(center)
	_panel = PanelContainer.new()
	var sb := UiStyle.box(UiStyle.BG, UiStyle.BORDER_HI, 3, 6)
	sb.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)
	_title = UiStyle.label(col, "Paused", 26, UiStyle.TITLE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_pages["main"] = _build_main(col)
	_pages["settings"] = _build_settings(col)
	_pages["controls"] = _build_controls(col)
	_show_page("main")
	visible = false


func _build_main(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.custom_minimum_size = Vector2(320, 0)
	parent.add_child(page)
	_menu_button(page, "Resume", close)
	_menu_button(page, "Settings", _show_page.bind("settings"))
	_menu_button(page, "Controls", _show_page.bind("controls"))
	_menu_button(page, "Restart match", func() -> void: restart_requested.emit())
	if spectating:
		_menu_button(page, "Play a match", func() -> void: change_champion_requested.emit())
	else:
		_menu_button(page, "Watch bots (NPC vs NPC)", func() -> void: spectate_requested.emit())
		_menu_button(page, "Change champion", func() -> void: change_champion_requested.emit())
	_menu_button(page, "Quit game", func() -> void: get_tree().quit())
	return page


func _build_settings(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.custom_minimum_size = Vector2(420, 0)
	parent.add_child(page)
	_choice(page, "Ability casting", Settings.CAST_MODE_NAMES, Settings.cast_mode, "cast_mode")
	_check(page, "Pan the camera at the screen edge", Settings.edge_pan, "edge_pan")
	_slider(page, "Edge and arrow-key pan speed", Settings.pan_speed, "pan_speed")
	_slider(page, "Middle-mouse drag speed", Settings.drag_pan_speed, "drag_pan_speed")
	_check(page, "Fullscreen", Settings.fullscreen, "fullscreen")
	_check(page, "Show FPS", Settings.show_fps, "show_fps")
	_menu_button(page, "Back", _show_page.bind("main"))
	return page


func _build_controls(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	parent.add_child(page)
	var l := UiStyle.label(page, CONTROLS_TEXT, 15)
	l.custom_minimum_size = Vector2(560, 0)
	_menu_button(page, "Back", _show_page.bind("main"))
	return page


func _menu_button(parent: Control, text: String, action: Callable) -> Button:
	var b := UiStyle.button(parent, text, 18)
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(action)
	return b


func _check(parent: Control, text: String, value: bool, key: String) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 16)
	c.add_theme_color_override("font_color", UiStyle.TEXT)
	c.add_theme_color_override("font_pressed_color", UiStyle.TEXT)
	c.add_theme_color_override("font_hover_color", UiStyle.TITLE)
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	parent.add_child(c)


func _choice(parent: Control, text: String, options: Array, value: int, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := UiStyle.label(row, text, 15)
	l.custom_minimum_size = Vector2(130, 0)
	var o := OptionButton.new()
	for opt in options:
		o.add_item(str(opt))
	o.select(value)
	o.add_theme_font_size_override("font_size", 15)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, i))
	row.add_child(o)


func _slider(parent: Control, text: String, value: float, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := UiStyle.label(row, text, 15)
	l.custom_minimum_size = Vector2(230, 0)
	var s := HSlider.new()
	s.min_value = 0.25
	s.max_value = 2.5
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(120, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var v := UiStyle.label(row, "%.2fx" % value, 15, UiStyle.GOLD)
	v.custom_minimum_size = Vector2(50, 0)
	s.value_changed.connect(func(x: float) -> void:
		v.text = "%.2fx" % x
		Settings.set_value(key, x))


func _show_page(page_name: String) -> void:
	for k in _pages:
		_pages[k].visible = k == page_name
	_title.text = {"main": "Paused", "settings": "Settings", "controls": "Controls"}[page_name]


func open() -> void:
	var pc := get_tree().get_first_node_in_group("player_controller") as PlayerController
	if pc != null:
		pc.cancel_aim()
	_show_page("main")
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("menu"):
		return
	get_viewport().set_input_as_handled()
	var pc := get_tree().get_first_node_in_group("player_controller") as PlayerController
	if not visible and pc != null and pc.cancel_aim():
		return     # Esc first cancels an ability being aimed
	if visible:
		if _pages["main"].visible:
			close()
		else:
			_show_page("main")
	elif hud != null and hud.is_shop_open():
		hud.toggle_shop()
	else:
		open()
