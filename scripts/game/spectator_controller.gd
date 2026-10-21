class_name SpectatorController
extends Node
## Input for NPC vs NPC (spectator) mode.
## Left-click a champion: lock onto it (its HUD, camera and cursor).
## Left-click anything else: inspect it. 1-5 / 6-0: lock onto Saradomin /
## Zamorak champions. Y: toggle camera lock. Camera drag, edge pan and the
## minimap work as normal (CameraRig, Minimap).

const PICK_RADIUS_PX := 36.0
const TEAM_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const ENEMY_KEYS := [KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]

var main: Node
var rig: CameraRig


func setup(p_main: Node, p_rig: CameraRig) -> void:
	main = p_main
	rig = p_rig


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var u := pick_unit(event.position)
		if u is Champion:
			main.focus(u)
			main.select_unit(null)
		else:
			main.select_unit(u)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		var idx := TEAM_KEYS.find(key)
		var team := Combat.Team.SARADOMIN
		if idx < 0:
			idx = ENEMY_KEYS.find(key)
			team = Combat.Team.ZAMORAK
		if idx >= 0:
			var roster: Array = main.team_roster(team)
			if idx < roster.size():
				main.focus(roster[idx])
			get_viewport().set_input_as_handled()


func pick_unit(screen_pos: Vector2) -> Unit:
	var cam := rig.camera
	var best: Unit = null
	var best_d := PICK_RADIUS_PX
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead or not u.visible:
			continue
		var world := u.global_position + Vector3.UP * u.visual_height() * 0.5
		if cam.is_position_behind(world):
			continue
		var d := cam.unproject_position(world).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = u
	return best
