class_name PlayerController
extends Node
## Turns mouse and keyboard input into champion commands.
## Left-click: select (inspect) a unit. Right-click: move or attack.
## Q/W/E/R: abilities at the cursor. Ctrl+Q/W/E/R: spend a skill point.
## Casting follows Settings.cast_mode: normal cast (the default: press to show
## the indicator, left-click to cast; a right-click cancels it and moves, but
## you can bring it up while already walking; Esc cancels too), quick cast
## with indicator (hold to aim, release to cast; right-click cancels) or
## quick cast.
## 1-6: item specs. 7-0: food and potions. Z/X/C: overheads (builds that have them).
## V: offensive prayer. Middle-mouse drag pans the camera (CameraRig).
## Orders happen right away (moving, attacking, casting, prayers); only
## eating and drinking wait for the next game tick (order_on_tick).

const PICK_RADIUS_PX := 36.0
const TREE_PICK_RADIUS_PX := 70.0     # generous: Timber! yews are easy to mean to chop
const FALL_DEAD_ZONE := 0.5       # cursor this close to a trunk: default fall
const FALL_MAX_REACH := 7.0

var main: Node
var champion: Champion
var rig: CameraRig
var hovered: Unit
var hovered_tree: PlantedTree
var fall_dir := Vector3.ZERO      # the way the aimed yew would fall (cursor side of the trunk)
var indicator: AbilityIndicator

## The action being aimed ("q".."r" or "item:<id>"), "" when not aiming.
var aiming := ""
var _aim_input := ""        # the input action that started aiming


func setup(p_main: Node, p_champion: Champion, p_rig: CameraRig) -> void:
	main = p_main
	champion = p_champion
	rig = p_rig


func _ready() -> void:
	add_to_group("player_controller")
	indicator = AbilityIndicator.new()
	indicator.name = "AbilityIndicator"
	add_child(indicator)


func _process(_delta: float) -> void:
	if rig != null:
		hovered = pick_unit(get_viewport().get_mouse_position())
	_update_aim()
	_update_pending()
	_update_cursor()


# --- Attack cursor -------------------------------------------------------------
static var _sword: Texture2D
var _sword_on := false


## A sword cursor over anything you can attack (an enemy unit or monster).
func _update_cursor() -> void:
	var attackable := hovered != null and champion != null and is_instance_valid(hovered) and not hovered.is_dead \
		and hovered.team != champion.team and aiming == ""
	if attackable == _sword_on:
		return
	_sword_on = attackable
	if attackable:
		Input.set_custom_mouse_cursor(sword_cursor(), Input.CURSOR_ARROW, Vector2(2, 2))
	else:
		Input.set_custom_mouse_cursor(null)


## The cursor image: OSRS's Attack sword (private pack), else a scimitar icon.
static func sword_cursor() -> Texture2D:
	if _sword == null:
		var tex: Texture2D = OsrsSprites.get_sprite("attack")
		if tex == null:
			tex = Icons.item("rune_scimitar")
		if tex == null:
			return null
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		var target := 32
		if img.get_width() != target:
			img.resize(target, target, Image.INTERPOLATE_NEAREST)
		img.flip_x()     # the blade's tip at the top left, where the cursor points
		_sword = ImageTexture.create_from_image(img)
	return _sword


func _exit_tree() -> void:
	if _sword_on:
		Input.set_custom_mouse_cursor(null)


# --- Aiming --------------------------------------------------------------------

func is_aiming() -> bool:
	return aiming != ""


## Starts aiming `key`, or casts at once for quick cast and self-cast abilities.
func begin_action(key: String, input_action: String = "") -> void:
	if key == "" or champion == null:
		return
	var ab := champion.get_action(key)
	if ab.is_empty():
		return
	if Settings.cast_mode == Settings.CAST_QUICK or str(ab.get("cast", "self")) == "self":
		cancel_aim()
		cast_at_cursor(key)
		return
	if not _ready_to_cast(key, ab):
		return
	if aiming == key and Settings.cast_mode == Settings.CAST_NORMAL:
		confirm_aim()       # pressing the key again casts
		return
	aiming = key
	_aim_input = input_action
	_update_aim()


func confirm_aim() -> void:
	if aiming == "":
		return
	var key := aiming
	cancel_aim()
	cast_at_cursor(key)


## Returns true if an aim was cancelled.
func cancel_aim() -> bool:
	var was := aiming != ""
	aiming = ""
	_aim_input = ""
	hovered_tree = null
	fall_dir = Vector3.ZERO
	if indicator != null:
		indicator.clear()
	return was


func _ready_to_cast(key: String, ab: Dictionary) -> bool:
	return not champion.is_dead and champion.ability_rank(key) > 0 \
		and champion.cooldowns.get(key, 0.0) <= 0.0 and champion.spec >= float(ab.get("spec_cost", 0.0))


func _update_aim() -> void:
	if aiming == "":
		return
	if champion == null or champion.is_dead or champion.get_action(aiming).is_empty():
		cancel_aim()
		return
	var t := _cursor_target()
	hovered_tree = tree_under_cursor(aiming)
	fall_dir = fall_direction_at_cursor(hovered_tree)
	indicator.update_for(champion, aiming, t["point"], t["unit"], hovered_tree, fall_dir)


## While a walk-and-cast is under way (a spot cast past its range, or a chop
## on the way to its far side), its target stays drawn on the ground until the
## cast goes off. Any click cancels it.
func _update_pending() -> void:
	if aiming != "" or champion == null:
		return
	var pend := champion.pending_cast()
	if pend.is_empty():
		if indicator.visible:
			indicator.clear()
		return
	var slot := str(pend["slot"])
	if pend.has("tree"):
		var tree: PlantedTree = pend["tree"]
		if is_instance_valid(tree):
			indicator.update_for(champion, slot, tree.global_position, null, tree, pend.get("dir", Vector3.ZERO))
	else:
		indicator.update_for(champion, slot, pend["point"], null, null)


## Chop direction from the cursor: the yew falls toward the cursor's side of
## its trunk, so circling the cursor round it turns the fall line. On the trunk
## itself (or far off) it falls away from you as before (ZERO).
func fall_direction_at_cursor(tree: PlantedTree) -> Vector3:
	if tree == null or rig == null:
		return Vector3.ZERO
	var ground: Variant = ground_point(get_viewport().get_mouse_position())
	if ground == null:
		return Vector3.ZERO
	var d: Vector3 = (ground as Vector3) - tree.global_position
	d.y = 0.0
	if d.length() < FALL_DEAD_ZONE or d.length() > FALL_MAX_REACH:
		return Vector3.ZERO
	return d.normalized()


## Casts `key` at the cursor. A planter ability (Timber!) aimed at one of your
## yews targets that yew exactly, so it is chopped.
func cast_at_cursor(key: String) -> bool:
	var t := _cursor_target()
	var point: Vector3 = t["point"]
	var tree := tree_under_cursor(key)
	var dir := Vector3.ZERO
	if tree != null:
		point = tree.global_position
		dir = fall_direction_at_cursor(tree)
	var target: Unit = t["unit"]
	order(func() -> void: champion.try_cast(key, target, point, true, dir))
	return true


## Carries out an order right away: moving, attacking, casting and prayers
## don't wait for the game tick.
func order(action: Callable) -> void:
	if is_instance_valid(champion):
		action.call()


## Queues an order for the next game tick (eating and drinking, as in OSRS).
func order_on_tick(action: Callable) -> void:
	var c := champion
	GameTick.queue_input(func() -> void:
		if is_instance_valid(c):
			action.call())


## Your Timber! yew under the cursor: picked on screen (its trunk) or by the
## ground point being within the ability's hover radius.
func tree_under_cursor(key: String) -> PlantedTree:
	if champion == null or rig == null:
		return null
	var ab := champion.get_action(key)
	if not ab.has("planter"):
		return null
	var mouse := get_viewport().get_mouse_position()
	var ground: Variant = ground_point(mouse)
	var hover := float(ab["planter"].get("hover_radius", 1.8))
	var best: PlantedTree = null
	var best_score := INF
	for tree in champion.standing_trees():
		var score := INF
		if ground != null:
			var gd := Unit.flat_distance(ground, tree.global_position)
			if gd <= hover:
				score = gd / hover
		var cam := rig.camera
		for h in [0.5, 2.5, 5.0]:
			var w: Vector3 = tree.global_position + Vector3.UP * float(h)
			if not cam.is_position_behind(w):
				var sd := cam.unproject_position(w).distance_to(mouse)
				if sd <= TREE_PICK_RADIUS_PX:
					score = minf(score, sd / TREE_PICK_RADIUS_PX)
		if score < best_score:
			best_score = score
			best = tree
	return best


func _unhandled_input(event: InputEvent) -> void:
	if champion == null or rig == null:
		return
	# A click over an open window (the shop) is never an order.
	if event is InputEventMouseButton and event.pressed and UiStyle.mouse_blocked(get_tree(), event.position):
		return
	# Any left or right click cancels a walk-and-cast that is under way
	# (a confirming left click below replaces it with the new cast).
	if event is InputEventMouseButton and event.pressed and aiming == "" \
			and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		champion.cancel_pending_cast()
	if aiming != "" and event is InputEventMouseButton and event.pressed:
		if event.is_action_pressed("select"):
			confirm_aim()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("move_command"):
			cancel_aim()
			if Settings.cast_mode != Settings.CAST_NORMAL:
				get_viewport().set_input_as_handled()
				return
			# Normal cast: the right-click still moves (or attacks) below.
	if aiming != "" and _aim_input != "" and event.is_action_released(_aim_input) \
			and Settings.cast_mode == Settings.CAST_QUICK_INDICATOR:
		confirm_aim()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select") and event is InputEventMouseButton:
		main.select_unit(pick_unit(event.position))
		get_viewport().set_input_as_handled()
		return
	for slot in Champion.SLOTS:
		if event.is_action_pressed("level_" + slot):
			order(func() -> void: champion.rank_up(slot))
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("move_command") and event is InputEventMouseButton:
		var pos: Vector2 = event.position
		var u := pick_unit(pos)
		var altar := altar_under_cursor(pos)
		if u != null and u.team != champion.team and u.is_damageable():
			order(func() -> void:
				if is_instance_valid(u):
					champion.command_attack(u))
		elif altar != null:
			order(func() -> void: champion.command_pray(altar))
			_click_marker(altar.global_position)
		else:
			var p: Variant = ground_point(pos)
			if p != null:
				var to: Vector3 = p
				order(func() -> void: champion.command_move(to))
				_click_marker(p)
		get_viewport().set_input_as_handled()
		return
	for slot in Champion.SLOTS:
		if event.is_action_pressed("ability_" + slot, false, true):
			begin_action(slot, "ability_" + slot)
			get_viewport().set_input_as_handled()
			return
	for i in 6:
		if event.is_action_pressed("item_%d" % (i + 1)):
			begin_action(champion.item_action_key(i), "item_%d" % (i + 1))
			get_viewport().set_input_as_handled()
			return
	for i in 4:
		if event.is_action_pressed("consume_%d" % (i + 1)):
			order_on_tick(func() -> void: champion.use_consumable(i))
			return
	if event.is_action_pressed("prayer_melee"):
		order(func() -> void: champion.toggle_protect(Combat.Style.MELEE))
	elif event.is_action_pressed("prayer_ranged"):
		order(func() -> void: champion.toggle_protect(Combat.Style.RANGED))
	elif event.is_action_pressed("prayer_magic"):
		order(func() -> void: champion.toggle_protect(Combat.Style.MAGIC))
	elif event.is_action_pressed("prayer_offensive"):
		order(func() -> void: champion.toggle_chosen_prayer())
	elif event.is_action_pressed("recall"):
		order(func() -> void: champion.start_recall())
	elif event.is_action_pressed("stop"):
		order(func() -> void: champion.command_stop())
	elif event.is_action_pressed("toggle_shop") and main.get("hud") != null:
		main.hud.toggle_shop()


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
		if u == null or u.is_dead or not u.visible or u.fog_hidden:
			continue
		var world := u.global_position + Vector3.UP * u.visual_height() * 0.5
		if cam.is_position_behind(world):
			continue
		var d := cam.unproject_position(world).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = u
	return best


## A prayer altar under the cursor (its body on screen, or the ground right next to it).
func altar_under_cursor(screen_pos: Vector2) -> PrayerAltar:
	var cam := rig.camera
	var ground: Variant = ground_point(screen_pos)
	for a in PrayerAltar.active:
		if not is_instance_valid(a):
			continue
		if ground != null and Unit.flat_distance(ground, a.global_position) <= a.radius + 0.6:
			return a
		var w: Vector3 = a.global_position + Vector3.UP * 1.0
		if not cam.is_position_behind(w) and cam.unproject_position(w).distance_to(screen_pos) <= PICK_RADIUS_PX:
			return a
	return null


func _click_marker(p: Vector3) -> void:
	ClickMarker.spawn(main, p, ClickMarker.MOVE)
