class_name CameraRig
extends Node3D
## Classic MOBA camera: angled top-down view.
## Hold the middle mouse button and drag to grab the map and pan freely.
## Also: screen-edge and arrow-key panning, wheel zoom, Space to snap to your
## champion, Y to lock onto it. Edge panning and speeds come from Settings.

const MIN_ZOOM := 16.0
const MAX_ZOOM := 50.0
const ZOOM_STEP := 2.0
## Players can zoom out 5 wheel steps from fully in; spectators out to the whole map.
const PLAYER_ZOOM_STEPS := 5
const SPECTATOR_MAX_ZOOM := 230.0
const PAN_SPEED := 45.0
const EDGE_MARGIN := 14.0
const PITCH_DEG := 58.0

var camera: Camera3D
var follow: Node3D
var locked := false
var zoom := 26.0
var max_zoom := MIN_ZOOM + ZOOM_STEP * PLAYER_ZOOM_STEPS


## Players: 5 steps out from fully zoomed in. Spectators: out to the whole map.
func set_spectator(on: bool) -> void:
	max_zoom = SPECTATOR_MAX_ZOOM if on else MIN_ZOOM + ZOOM_STEP * PLAYER_ZOOM_STEPS
	zoom = minf(zoom, max_zoom)
	_apply_zoom()
var dragging := false

var _drag_anchor := Vector3.ZERO


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	# The nearest thing it ever shows is metres away: a near plane of 0.05 m
	# spent most of the depth buffer on empty space, so flat ground, pebbles
	# and rock bases z-fought (flickered) at distance.
	camera.near = 3.0
	camera.far = 600.0
	add_child(camera)
	camera.current = true
	_apply_zoom()


func center_on(p: Vector3) -> void:
	var half := MapLayout.MAP_SIZE * 0.5
	global_position = Vector3(clampf(p.x, -half, half), 0.0, clampf(p.z, -half, half))


## Where a screen point lands on the ground plane (y = 0), or null.
func ground_point(screen_pos: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


## The ground area the camera currently shows, as four corners (for the minimap).
func view_corners() -> PackedVector3Array:
	var out := PackedVector3Array()
	var size := get_viewport().get_visible_rect().size
	for c in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		var p: Variant = ground_point(c)
		if p != null:
			out.append(p)
	return out


func _apply_zoom() -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	camera.position = Vector3(0.0, zoom * sin(pitch), zoom * cos(pitch))
	camera.rotation = Vector3(-pitch, 0.0, 0.0)


func _process(delta: float) -> void:
	if dragging:
		return
	if locked and is_instance_valid(follow):
		center_on(follow.global_position)
		return
	if Input.is_action_pressed("camera_center") and is_instance_valid(follow):
		center_on(follow.global_position)
		return
	var pan := Vector2.ZERO
	if Input.is_action_pressed("camera_left"):
		pan.x -= 1.0
	if Input.is_action_pressed("camera_right"):
		pan.x += 1.0
	if Input.is_action_pressed("camera_up"):
		pan.y -= 1.0
	if Input.is_action_pressed("camera_down"):
		pan.y += 1.0
	if _edge_pan_allowed():
		var vp := get_viewport()
		var mouse := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		if mouse.x <= EDGE_MARGIN:
			pan.x -= 1.0
		elif mouse.x >= size.x - EDGE_MARGIN:
			pan.x += 1.0
		if mouse.y <= EDGE_MARGIN:
			pan.y -= 1.0
		elif mouse.y >= size.y - EDGE_MARGIN:
			pan.y += 1.0
	if pan != Vector2.ZERO:
		var step := pan.normalized() * PAN_SPEED * Settings.pan_speed * delta * (zoom / 30.0)
		center_on(global_position + Vector3(step.x, 0.0, step.y))


func _edge_pan_allowed() -> bool:
	return Settings.edge_pan and DisplayServer.get_name() != "headless" and DisplayServer.window_is_focused()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_action("camera_drag"):
		if event.pressed:
			var p: Variant = ground_point(event.position)
			if p != null:
				dragging = true
				locked = false
				_drag_anchor = p
		else:
			dragging = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and dragging:
		# Grab-and-drag: keep the grabbed ground point under the cursor.
		var p: Variant = ground_point(event.position)
		if p != null:
			var offset: Vector3 = (_drag_anchor - p) * Settings.drag_pan_speed
			center_on(global_position + Vector3(offset.x, 0.0, offset.z))
			# At 1x the anchor stays exactly under the cursor. At other speeds,
			# re-anchor so the map keeps moving proportionally to the mouse.
			if not is_equal_approx(Settings.drag_pan_speed, 1.0):
				var now: Variant = ground_point(event.position)
				if now != null:
					_drag_anchor = now
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("camera_zoom_in"):
		zoom = maxf(MIN_ZOOM, zoom - (ZOOM_STEP if zoom <= MAX_ZOOM else zoom * 0.15))
		_apply_zoom()
	elif event.is_action_pressed("camera_zoom_out"):
		zoom = minf(max_zoom, zoom + (ZOOM_STEP if zoom < MAX_ZOOM else zoom * 0.15))
		_apply_zoom()
	elif event.is_action_pressed("camera_lock"):
		locked = not locked
