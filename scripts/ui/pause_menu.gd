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
Q W E R — abilities (R is your special attack): press to show the indicator, left-click to cast
   (right-click cancels it and walks, and it can be brought up while walking; Esc cancels; other modes in Settings > Ability casting)
Ctrl + Q W E R — spend a skill point (R unlocks at level 6)
1 – 6 — item special attacks
7 8 9 0 — food and potions   (rebind them in Inventory hotkeys; drag items between slots to rearrange them)
V — switch your prayer on/off (picked at champion select; drains prayer points)
Z X C — Protect from Melee / Missiles / Magic (tank and main builds)
Right-click a prayer altar (beside each red and blue buff) — pray to restore prayer to full
B — teleport home      P — shop      S — stop      Tab (hold) — scoreboard
Middle-mouse drag — grab and pan the map
Minimap — left-click to look, right-click to walk
Space — centre on your champion      Y — lock camera
Arrow keys / screen edge / mouse wheel — pan and zoom
Esc — close the shop, or open this menu

Spectator (NPC vs NPC) mode:
Left-click a champion or its roster card — lock onto it (its HUD, camera and cursor)
1 – 5 / 6 – 0 — lock onto a Saradomin / Zamorak champion
Y — toggle the camera lock      F — fog of war on/off (the watched team's view)
Left-click anything else — inspect it"""

var hud: Hud

var _dim: ColorRect
var _panel: PanelContainer
var _pages: Dictionary = {}
var _title: Label
var _video_opts: Dictionary = {}
var _hotkey_rows: Dictionary = {}
var _hotkey_note: Label
var _reset_all: Button
var _reset_armed := false
var _reset_token := 0
var _listening := ""


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
	_pages["video"] = _build_video(col)
	_pages["controls"] = _build_controls(col)
	_pages["hotkeys"] = _build_hotkeys(col)
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
	_menu_button(page, "Inventory hotkeys", _show_page.bind("hotkeys"))
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
	_check(page, "Show FPS", Settings.show_fps, "show_fps")
	_menu_button(page, "Video settings...", _show_page.bind("video"))
	_menu_button(page, "Back", _show_page.bind("main"))
	return page


## Video: window size, fullscreen, vsync and a quality preset with the pieces
## it sets (3D resolution, anti-aliasing, shadows, foliage, particles).
func _build_video(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.custom_minimum_size = Vector2(460, 0)
	parent.add_child(page)
	_video_opts.clear()
	var sizes := Settings.available_resolutions()
	var size_names: Array = []
	for i in sizes:
		size_names.append("%d x %d" % [Settings.RESOLUTIONS[i].x, Settings.RESOLUTIONS[i].y])
	_video_option(page, "Window size", size_names, "resolution", sizes)
	_check(page, "Fullscreen", Settings.fullscreen, "fullscreen")
	_check(page, "Vertical sync", Settings.vsync, "vsync")
	UiStyle.label(page, "Graphics", 16, UiStyle.TITLE)
	_video_option(page, "Quality", Settings.QUALITY_NAMES, "quality")
	var scales: Array = []
	for s in Settings.RENDER_SCALES:
		scales.append("%d%%" % s)
	_video_option(page, "3D resolution", scales, "render_scale", Settings.RENDER_SCALES)
	_video_option(page, "Anti-aliasing", Settings.MSAA_NAMES, "msaa")
	_video_option(page, "Shadows", Settings.SHADOW_NAMES, "shadows")
	_video_option(page, "Foliage", Settings.FOLIAGE_NAMES, "foliage")
	_video_option(page, "Particles", Settings.PARTICLE_NAMES, "particles")
	var note := UiStyle.label(page, "Quality sets the options below it; change any of them and it reads Custom. Window size applies in windowed mode. Lower the 3D resolution for more frames; the interface stays sharp.", 12, UiStyle.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(440, 0)
	_menu_button(page, "Back", _show_page.bind("settings"))
	if not Settings.changed.is_connected(_refresh_video):
		Settings.changed.connect(_refresh_video)
	return page


## A dropdown for a Settings value. `values` maps list positions to stored
## values (default: the position itself).
func _video_option(parent: Control, text: String, names: Array, key: String, values: Array = []) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := UiStyle.label(row, text, 15)
	l.custom_minimum_size = Vector2(150, 0)
	var o := OptionButton.new()
	for n in names:
		o.add_item(str(n))
	o.add_theme_font_size_override("font_size", 15)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i: int) -> void:
		if key == "quality" and i >= Settings.PRESETS.size():
			return                     # "Custom" is only a label for a mix
		Settings.set_value(key, values[i] if not values.is_empty() else i))
	row.add_child(o)
	_video_opts[key] = {"button": o, "values": values}
	_select_video(key)


func _select_video(key: String) -> void:
	var d: Dictionary = _video_opts[key]
	var o: OptionButton = d["button"]
	var values: Array = d["values"]
	var v: int = int(Settings.get(key))
	var at := values.find(v) if not values.is_empty() else v
	o.select(at if at >= 0 else o.item_count - 1)


func _refresh_video() -> void:
	for k in _video_opts:
		if is_instance_valid((_video_opts[k]["button"] as OptionButton)):
			_select_video(k)


func _build_controls(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	parent.add_child(page)
	var l := UiStyle.label(page, CONTROLS_TEXT, 15)
	l.custom_minimum_size = Vector2(560, 0)
	_menu_button(page, "Back", _show_page.bind("main"))
	return page


# --- Inventory hotkeys ---------------------------------------------------------

## The six item slots and four potion slots, each with its key and Reset and
## Unbind buttons, then Reset all (which asks you to click twice).
func _build_hotkeys(parent: Control) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 5)
	page.custom_minimum_size = Vector2(620, 0)
	parent.add_child(page)
	var hint := UiStyle.label(page, "Click a key, then press the key (or a side mouse button) you want. Esc cancels. Any key works.", 14, UiStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(620, 0)
	for action in Controls.REBINDABLE:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		page.add_child(row)
		var name_label := UiStyle.label(row, Controls.action_title(action), 15)
		name_label.custom_minimum_size = Vector2(120, 0)
		var key := UiStyle.button(row, "", 15)
		key.custom_minimum_size = Vector2(150, 30)
		key.pressed.connect(_start_listening.bind(action))
		var reset := UiStyle.button(row, "Reset", 14)
		reset.custom_minimum_size = Vector2(70, 30)
		reset.tooltip_text = "Back to the default key"
		reset.pressed.connect(func() -> void: Controls.reset(action))
		var unbind := UiStyle.button(row, "Unbind", 14)
		unbind.custom_minimum_size = Vector2(80, 30)
		unbind.tooltip_text = "No key for this slot"
		unbind.pressed.connect(func() -> void: Controls.unbind(action))
		var warn := UiStyle.label(row, "", 13, UiStyle.GOLD)
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_hotkey_rows[action] = {"key": key, "reset": reset, "unbind": unbind, "warn": warn}
	_hotkey_note = UiStyle.label(page, "", 14, UiStyle.GOLD)
	_hotkey_note.custom_minimum_size = Vector2(0, 20)
	_reset_all = UiStyle.button(page, "Reset all", 16)
	_reset_all.custom_minimum_size = Vector2(0, 36)
	_reset_all.pressed.connect(_on_reset_all)
	_menu_button(page, "Back", _show_page.bind("main"))
	Controls.bindings_changed.connect(_refresh_hotkeys)
	return page


func _refresh_hotkeys() -> void:
	for action in _hotkey_rows:
		var r: Dictionary = _hotkey_rows[action]
		var listening: bool = _listening == action
		(r["key"] as Button).text = "Press a key..." if listening else (Controls.key_text(action) if Controls.is_bound(action) else "Unbound")
		(r["reset"] as Button).disabled = Controls.is_default(action)
		(r["unbind"] as Button).disabled = not Controls.is_bound(action)
		var others: Array[String] = Controls.conflicts(action)
		(r["warn"] as Label).text = "" if others.is_empty() else "also: " + ", ".join(others.map(func(a: String) -> String: return Controls.action_name(a)))


func _start_listening(action: String) -> void:
	_listening = action
	_hotkey_note.text = ""
	_disarm_reset_all()
	_refresh_hotkeys()


func _stop_listening() -> void:
	_listening = ""


func _disarm_reset_all() -> void:
	_reset_armed = false
	_reset_token += 1
	if _reset_all != null:
		_reset_all.text = "Reset all"


## Reset all asks for a second click (within a few seconds) before it does anything.
func _on_reset_all() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_token += 1
		var token := _reset_token
		_reset_all.text = "Click again to reset every hotkey"
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if token == _reset_token:
				_disarm_reset_all())
		return
	_disarm_reset_all()
	Controls.reset_all()
	_hotkey_note.text = "All hotkeys are back to their defaults."


## Takes the next key press while a slot is waiting for its key.
func _capture_key(event: InputEvent) -> void:
	var pressed_key := event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo
	var pressed_btn := event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index in Controls.BINDABLE_MOUSE
	if not pressed_key and not pressed_btn:
		return
	get_viewport().set_input_as_handled()
	var action := _listening
	_listening = ""
	if pressed_key and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_refresh_hotkeys()
		return
	var taken := Controls.bind(action, event)
	_hotkey_note.text = "%s is now %s%s." % [Controls.action_title(action), Controls.key_text(action),
		"" if taken == "" else " (taken from %s, which is now unbound)" % taken]
	_refresh_hotkeys()


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
	_title.text = {"main": "Paused", "settings": "Settings", "video": "Video settings", "controls": "Controls", "hotkeys": "Inventory hotkeys"}[page_name]
	_stop_listening()
	_disarm_reset_all()
	_refresh_hotkeys()


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
	if _listening != "" and visible:
		_capture_key(event)
		return
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
