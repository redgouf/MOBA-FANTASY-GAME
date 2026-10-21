class_name PlayerController
extends Node
## Turns mouse and keyboard input into champion commands.
## Left-click: select (inspect) a unit. Right-click: move or attack.
## Q/W/E/R: abilities at the cursor. Ctrl+Q/W/E/R: spend a skill point.
## 1-6: item specs. 7-0: food and potions. Z/X/C: overheads (builds that have them).
## V: offensive prayer. Middle-mouse drag pans the camera (CameraRig).

const PICK_RADIUS_PX := 36.0

var main: Node
var champion: Champion
var rig: CameraRig
var hovered: Unit


func setup(p_main: Node, p_champion: Champion, p_rig: CameraRig) -> void:
	main = p_main
	champion = p_champion
	rig = p_rig


func _process(_delta: float) -> void:
	if rig != null:
		hovered = pick_unit(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if champion == null or rig == null:
		return
	if event.is_action_pressed("select") and event is InputEventMouseButton:
		main.select_unit(pick_unit(event.position))
		get_viewport().set_input_as_handled()
		return
	for slot in Champion.SLOTS:
		if event.is_action_pressed("level_" + slot):
			champion.rank_up(slot)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("move_command") and event is InputEventMouseButton:
		var pos: Vector2 = event.position
		var u := pick_unit(pos)
		if u != null and u.team != champion.team and u.is_damageable():
			champion.command_attack(u)
		else:
			var p: Variant = ground_point(pos)
			if p != null:
				champion.command_move(p)
				_click_marker(p)
		get_viewport().set_input_as_handled()
		return
	for slot in Champion.SLOTS:
		if event.is_action_pressed("ability_" + slot, false, true):
			_cast(slot)
			return
	for i in 6:
		if event.is_action_pressed("item_%d" % (i + 1)):
			var target := _cursor_target()
			champion.use_item(i, target["unit"], target["point"])
			return
	for i in 4:
		if event.is_action_pressed("consume_%d" % (i + 1)):
			champion.use_consumable(i)
			return
	if event.is_action_pressed("prayer_melee"):
		champion.toggle_protect(Combat.Style.MELEE)
	elif event.is_action_pressed("prayer_ranged"):
		champion.toggle_protect(Combat.Style.RANGED)
	elif event.is_action_pressed("prayer_magic"):
		champion.toggle_protect(Combat.Style.MAGIC)
	elif event.is_action_pressed("prayer_offensive"):
		champion.activate_offensive_prayer()
	elif event.is_action_pressed("recall"):
		champion.start_recall()
	elif event.is_action_pressed("stop"):
		champion.command_stop()
	elif event.is_action_pressed("toggle_shop") and main.get("hud") != null:
		main.hud.toggle_shop()


func _cast(slot: String) -> void:
	var target := _cursor_target()
	champion.try_cast(slot, target["unit"], target["point"])


func _cursor_target() -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	var p: Variant = ground_point(mouse)
	return {"unit": pick_unit(mouse), "point": p if p != null else champion.global_position}


func ground_point(screen_pos: Vector2) -> Variant:
	return rig.ground_point(screen_pos)


## Screen-space picking: the unit whose body is closest to the cursor.
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


func _click_marker(p: Vector3) -> void:
	ClickMarker.spawn(main, p, ClickMarker.MOVE)
