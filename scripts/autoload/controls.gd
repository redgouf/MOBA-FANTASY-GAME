extends Node
## Registers default input actions at startup so bindings live in one readable place.
## Actions already defined in Project Settings > Input Map are left untouched,
## so players (and designers) can remap them in the editor.

const KEY_BINDINGS := {
	"ability_q": KEY_Q,
	"ability_w": KEY_W,
	"ability_e": KEY_E,
	"ability_r": KEY_R,
	# Item actives (spec weapons) live in the six item slots.
	"item_1": KEY_1,
	"item_2": KEY_2,
	"item_3": KEY_3,
	"item_4": KEY_4,
	"item_5": KEY_5,
	"item_6": KEY_6,
	# Consumable belt (food and potions).
	"consume_1": KEY_7,
	"consume_2": KEY_8,
	"consume_3": KEY_9,
	"consume_4": KEY_0,
	# Overheads only work for builds that have them (tanks, main accounts).
	"prayer_melee": KEY_Z,
	"prayer_ranged": KEY_X,
	"prayer_magic": KEY_C,
	# Every build: toggle the prayer picked at champion select.
	"prayer_offensive": KEY_V,
	"recall": KEY_B,
	"stop": KEY_S,
	"toggle_shop": KEY_P,
	"scoreboard": KEY_TAB,
	"camera_center": KEY_SPACE,
	"camera_lock": KEY_Y,
	"camera_left": KEY_LEFT,
	"camera_right": KEY_RIGHT,
	"camera_up": KEY_UP,
	"camera_down": KEY_DOWN,
	"menu": KEY_ESCAPE,
}

## Ctrl + key bindings (League-style ability level-up).
const CTRL_BINDINGS := {
	"level_q": KEY_Q,
	"level_w": KEY_W,
	"level_e": KEY_E,
	"level_r": KEY_R,
}

const MOUSE_BINDINGS := {
	"move_command": MOUSE_BUTTON_RIGHT,
	"select": MOUSE_BUTTON_LEFT,
	"camera_drag": MOUSE_BUTTON_MIDDLE,
	"camera_zoom_in": MOUSE_BUTTON_WHEEL_UP,
	"camera_zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
}


## Player-rebindable actions: the six item slots and the four food and potion
## slots. A binding is a key or a side mouse button, or nothing (unbound).
const REBINDABLE: Array[String] = [
	"item_1", "item_2", "item_3", "item_4", "item_5", "item_6",
	"consume_1", "consume_2", "consume_3", "consume_4",
]
const KEYBINDS_PATH := "user://keybinds.cfg"
## Mouse buttons a binding may use (left, right and middle stay for the game).
const BINDABLE_MOUSE := [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]

signal bindings_changed

## Saves changes to user://keybinds.cfg (off in tests).
var persist := true


## Human name of a rebindable action ("Item slot 1", "Potion slot 3").
static func action_title(action: String) -> String:
	var n := action.get_slice("_", 1)
	return ("Item slot " if action.begins_with("item_") else "Potion slot ") + n


## The binding an action starts with: a key code, or 0 for none.
static func default_key(action: String) -> int:
	return int(KEY_BINDINGS.get(action, 0))


## The event bound to an action (key or mouse button), null when unbound.
func binding(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	return events[0] if not events.is_empty() else null


func is_bound(action: String) -> bool:
	return binding(action) != null


func is_default(action: String) -> bool:
	var ev := binding(action)
	var d := default_key(action)
	if ev == null:
		return d == 0
	return ev is InputEventKey and int((ev as InputEventKey).physical_keycode) == d


## What to show for an action's key: "1", "Q", "Mouse 4", or "" when unbound.
func key_text(action: String) -> String:
	var ev := binding(action)
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: Key = DisplayServer.keyboard_get_label_from_physical(k.physical_keycode) if DisplayServer.get_name() != "headless" else k.physical_keycode
		var t := OS.get_keycode_string(code)
		return t if t != "" else OS.get_keycode_string(k.physical_keycode)
	if ev is InputEventMouseButton:
		return "Mouse %d" % (int((ev as InputEventMouseButton).button_index) - 4)
	return ""


## Binds an action to a key press (`ev` a pressed InputEventKey or an allowed
## mouse button). Another rebindable action using the same key loses it.
## Returns the title of the action it was taken from ("" if none).
func bind(action: String, ev: InputEvent) -> String:
	if not (action in REBINDABLE) or not _bindable(ev):
		return ""
	var taken := ""
	for other in REBINDABLE:
		if other != action and _same_binding(binding(other), ev):
			InputMap.action_erase_events(other)
			taken = action_title(other)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, _clean(ev))
	_changed()
	return taken


func bind_key(action: String, keycode: int) -> String:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode as Key
	return bind(action, ev)


func unbind(action: String) -> void:
	if action in REBINDABLE:
		InputMap.action_erase_events(action)
		_changed()


func reset(action: String) -> void:
	if action in REBINDABLE:
		_set_default(action)
		_changed()


func reset_all() -> void:
	for action in REBINDABLE:
		_set_default(action)
	_changed()


## Other actions (abilities, prayers, camera...) already on the same key, for a warning.
func conflicts(action: String) -> Array[String]:
	var out: Array[String] = []
	var ev := binding(action)
	if ev == null:
		return out
	for other in KEY_BINDINGS:
		if other == action or other in REBINDABLE:
			continue
		for e in InputMap.action_get_events(other):
			if _same_binding(e, ev) and not out.has(other):
				out.append(other)
	return out


## What a key does besides its slot, for the warning ("Ability Q", "Recall").
static func action_name(action: String) -> String:
	if action.begins_with("ability_"):
		return "Ability " + action.get_slice("_", 1).to_upper()
	if action.begins_with("prayer_"):
		return "Prayer " + action.get_slice("_", 1)
	return action.replace("_", " ").capitalize()


func _bindable(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return k.physical_keycode != KEY_NONE and k.physical_keycode != KEY_ESCAPE
	if ev is InputEventMouseButton:
		return (ev as InputEventMouseButton).button_index in BINDABLE_MOUSE
	return false


func _same_binding(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


## A fresh event holding just the key or button (no modifiers or press state).
func _clean(ev: InputEvent) -> InputEvent:
	if ev is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = (ev as InputEventKey).physical_keycode
		return k
	var m := InputEventMouseButton.new()
	m.button_index = (ev as InputEventMouseButton).button_index
	return m


func _set_default(action: String) -> void:
	InputMap.action_erase_events(action)
	var d := default_key(action)
	if d != 0:
		var ev := InputEventKey.new()
		ev.physical_keycode = d as Key
		InputMap.action_add_event(action, ev)


func _changed() -> void:
	if persist:
		save_to(KEYBINDS_PATH)
	bindings_changed.emit()


## Writes every rebindable action: "key:<code>", "mouse:<button>" or "none".
func save_to(path: String) -> void:
	var cfg := ConfigFile.new()
	for action in REBINDABLE:
		var ev := binding(action)
		var v := "none"
		if ev is InputEventKey:
			v = "key:%d" % int((ev as InputEventKey).physical_keycode)
		elif ev is InputEventMouseButton:
			v = "mouse:%d" % int((ev as InputEventMouseButton).button_index)
		cfg.set_value("keys", action, v)
	cfg.save(path)


func load_from(path: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for action in REBINDABLE:
		if not cfg.has_section_key("keys", action):
			continue
		var v := str(cfg.get_value("keys", action))
		InputMap.action_erase_events(action)
		if v.begins_with("key:"):
			var k := InputEventKey.new()
			k.physical_keycode = int(v.substr(4)) as Key
			InputMap.action_add_event(action, k)
		elif v.begins_with("mouse:"):
			var m := InputEventMouseButton.new()
			m.button_index = int(v.substr(6)) as MouseButton
			InputMap.action_add_event(action, m)
	bindings_changed.emit()


func _ready() -> void:
	for action in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_BINDINGS[action]
		InputMap.action_add_event(action, ev)
	for action in CTRL_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ctrl_ev := InputEventKey.new()
		ctrl_ev.physical_keycode = CTRL_BINDINGS[action]
		ctrl_ev.ctrl_pressed = true
		InputMap.action_add_event(action, ctrl_ev)
	for action in MOUSE_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BINDINGS[action]
		InputMap.action_add_event(action, mb)
	load_from(KEYBINDS_PATH)
