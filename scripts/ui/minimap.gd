class_name Minimap
extends Control
## Bottom-right overview of the Wilderness Rift.
## Left-click or drag: move the camera there. Right-click: walk there.
## Shows lanes, the Ditch, walls, structures, minions, camps, champions
## and the camera's current view. (No fog of war yet: everything is visible.)

const GROUND := Color(0.2, 0.22, 0.13)
const LANE := Color(0.45, 0.39, 0.27)
const RIVER := Color(0.2, 0.36, 0.52)
const WALL := Color(0.12, 0.11, 0.1)
const MONSTER := Color(1.0, 0.85, 0.3)
const EPIC := Color(1.0, 0.5, 0.15)

var player: Champion          # highlighted champion (you, or the spectated bot)
var rig: CameraRig
var controllable := true      # false in spectator mode: right-click doesn't move anyone

var _dragging := false
var _redraw := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	tooltip_text = ""


func _process(delta: float) -> void:
	_redraw -= delta
	if _redraw <= 0.0:
		_redraw = 0.05
		queue_redraw()


## World (x, z) in metres -> minimap pixels. Screen-up on the map is -Z.
func to_map(p: Vector3) -> Vector2:
	var half := MapLayout.MAP_SIZE * 0.5
	return Vector2((p.x + half) / MapLayout.MAP_SIZE * size.x, (p.z + half) / MapLayout.MAP_SIZE * size.y)


func to_world(m: Vector2) -> Vector3:
	var half := MapLayout.MAP_SIZE * 0.5
	return Vector3(m.x / size.x * MapLayout.MAP_SIZE - half, 0.0, m.y / size.y * MapLayout.MAP_SIZE - half)


func _scale() -> float:
	return size.x / MapLayout.MAP_SIZE


func _draw() -> void:
	var k := _scale()
	draw_rect(Rect2(Vector2.ZERO, size), GROUND)
	# Wilderness Ditch (visual only, like in the game world)
	draw_line(Vector2.ZERO, size, RIVER, MapLayout.RIVER_WIDTH * k)
	# Lanes
	for lane in MapLayout.LANES:
		var path := MapLayout.lane_path(lane, Combat.Team.SARADOMIN)
		for i in range(1, path.size()):
			draw_line(to_map(path[i - 1]), to_map(path[i]), LANE, MapLayout.LANE_WIDTH * k * 0.8)
	# Rock walls
	for w in MapLayout.all_walls():
		var sz: Vector3 = w["size"]
		var center := to_map(w["pos"])
		var r := Vector2(sz.x, sz.z) * k
		draw_rect(Rect2(center - r * 0.5, r), WALL)
	# Bases and pits
	draw_circle(to_map(MapLayout.SARADOMIN_BASE), MapLayout.BASE_RADIUS * k, Unit.team_color(Combat.Team.SARADOMIN).darkened(0.55))
	draw_circle(to_map(MapLayout.ZAMORAK_BASE), MapLayout.BASE_RADIUS * k, Unit.team_color(Combat.Team.ZAMORAK).darkened(0.55))
	draw_circle(to_map(MapLayout.JAD_PIT), 7.0 * k, Color(0.4, 0.18, 0.08))
	draw_circle(to_map(MapLayout.DRAGON_PIT), 7.0 * k, Color(0.4, 0.18, 0.08))

	# Fog of war: darken what your team can't see.
	if FogOfWar.current != null and FogOfWar.current.enabled:
		draw_texture_rect(FogOfWar.current.minimap_texture, Rect2(Vector2.ZERO, size), false)
	# Prayer altars: a small white-blue prayer star.
	for a in PrayerAltar.active:
		if is_instance_valid(a):
			_draw_prayer_altar(to_map(a.global_position))

	var champs: Array[Champion] = []
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead or u.fog_hidden:
			continue
		var m := to_map(u.global_position)
		if u is Champion:
			champs.append(u)
		elif u is Structure:
			_draw_structure(u as Structure, m)
		elif u is Minion:
			draw_rect(Rect2(m - Vector2(1.5, 1.5), Vector2(3, 3)), Unit.team_color(u.team).lightened(0.15))
		elif u is Monster:
			var r := 4.5 if u.is_epic else 2.5
			draw_circle(m, r, EPIC if u.is_epic else MONSTER)
			draw_arc(m, r, 0, TAU, 12, Color.BLACK, 1.0)
	# Champions on top; the player last so it's never hidden.
	for c in champs:
		if c != player:
			_draw_champion(c)
	if is_instance_valid(player) and not player.is_dead:
		_draw_champion(player)
	# Camera view
	if rig != null:
		var corners := rig.view_corners()
		if corners.size() == 4:
			var pts := PackedVector2Array()
			for p in corners:
				pts.append(to_map(p))
			pts.append(pts[0])
			draw_polyline(pts, Color(1, 1, 1, 0.85), 1.5)
	draw_rect(Rect2(Vector2.ZERO, size), UiStyle.BORDER, false, 2.0)


func _draw_structure(s: Structure, m: Vector2) -> void:
	var c := Unit.team_color(s.team)
	if not s.is_damageable():
		c = c.darkened(0.35)
	match s.kind:
		"tower":
			draw_rect(Rect2(m - Vector2(3.5, 3.5), Vector2(7, 7)), c)
			draw_rect(Rect2(m - Vector2(3.5, 3.5), Vector2(7, 7)), Color.BLACK, false, 1.0)
		"altar":
			var pts := PackedVector2Array([m + Vector2(0, -5), m + Vector2(5, 0), m + Vector2(0, 5), m + Vector2(-5, 0)])
			draw_colored_polygon(pts, c)
		"flag":
			draw_circle(m, 6.0, c)
			draw_arc(m, 6.0, 0, TAU, 16, Color.WHITE, 1.5)


func _draw_prayer_altar(m: Vector2) -> void:
	var col := Color(0.8, 0.92, 1.0)
	var up := PackedVector2Array([m + Vector2(0, -5), m + Vector2(4.4, 2.6), m + Vector2(-4.4, 2.6)])
	var down := PackedVector2Array([m + Vector2(0, 5), m + Vector2(4.4, -2.6), m + Vector2(-4.4, -2.6)])
	draw_circle(m, 6.0, Color(0.08, 0.1, 0.16, 0.85))
	draw_colored_polygon(up, col)
	draw_colored_polygon(down, col)


func _draw_champion(c: Champion) -> void:
	var m := to_map(c.global_position)
	var is_player := c == player
	var r := 7.0 if is_player else 6.0
	draw_circle(m, r, Unit.team_color(c.team))
	draw_arc(m, r, 0, TAU, 20, Color.WHITE if is_player else Color(0, 0, 0, 0.9), 2.0 if is_player else 1.2)
	var font := get_theme_default_font()
	var letter := c.display_name.substr(0, 1) if not c.display_name.begins_with("The ") else c.display_name.substr(4, 1)
	draw_string(font, m + Vector2(-4, 4), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				_look_at(event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if controllable and is_instance_valid(player):
				var to := to_world(event.position)
				var who := player
				GameTick.queue_input(func() -> void:
					if is_instance_valid(who):
						who.command_move(to))
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_look_at(event.position)
		accept_event()


func _look_at(m: Vector2) -> void:
	if rig == null:
		return
	rig.locked = false
	m = Vector2(clampf(m.x, 0.0, size.x), clampf(m.y, 0.0, size.y))
	rig.center_on(to_world(m))
