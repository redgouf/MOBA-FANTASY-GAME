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
	# Every build: the best offensive prayer its Prayer level allows.
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
