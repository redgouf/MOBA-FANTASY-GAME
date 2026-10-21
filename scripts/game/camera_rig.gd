class_name CameraRig
extends Node3D
## Classic MOBA camera: angled top-down view, edge and arrow-key panning,
## scroll to zoom, Space to snap to your champion, Y to lock onto it.

const MIN_ZOOM := 16.0
const MAX_ZOOM := 50.0
const PAN_SPEED := 45.0
const EDGE_MARGIN := 14.0
const PITCH_DEG := 58.0

var camera: Camera3D
var follow: Node3D
var locked := false
var zoom := 30.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 600.0
	add_child(camera)
	camera.current = true
	_apply_zoom()


func center_on(p: Vector3) -> void:
	var half := MapLayout.MAP_SIZE * 0.5
	global_position = Vector3(clampf(p.x, -half, half), 0.0, clampf(p.z, -half, half))


func _apply_zoom() -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	camera.position = Vector3(0.0, zoom * sin(pitch), zoom * cos(pitch))
	camera.rotation = Vector3(-pitch, 0.0, 0.0)


func _process(delta: float) -> void:
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
		var step := pan.normalized() * PAN_SPEED * delta * (zoom / 30.0)
		center_on(global_position + Vector3(step.x, 0.0, step.y))


func _edge_pan_allowed() -> bool:
	return DisplayServer.get_name() != "headless" and DisplayServer.window_is_focused()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		zoom = maxf(MIN_ZOOM, zoom - 2.0)
		_apply_zoom()
	elif event.is_action_pressed("camera_zoom_out"):
		zoom = minf(MAX_ZOOM, zoom + 2.0)
		_apply_zoom()
	elif event.is_action_pressed("camera_lock"):
		locked = not locked
