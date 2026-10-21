class_name GhostCursor
extends Control
## Spectator view of a bot's "mouse": an arrow cursor that glides to wherever
## the focused champion last clicked, coloured by the order (green move,
## red attack, blue cast) and labelled with the ability key it used.
## Each order also drops a click ring on the ground.

var rig: CameraRig
var champ: Champion
var markers_parent: Node

var _world := Vector3.ZERO
var _screen := Vector2.ZERO
var _color := ClickMarker.MOVE
var _label := ""
var _pulse := 0.0
var _has := false


func _ready() -> void:
	UiStyle.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func watch(c: Champion) -> void:
	if is_instance_valid(champ) and champ.command_issued.is_connected(_on_command):
		champ.command_issued.disconnect(_on_command)
	champ = c
	_has = false
	if is_instance_valid(c):
		c.command_issued.connect(_on_command)


func _on_command(_c: Champion, kind: String, point: Vector3, label: String) -> void:
	_world = point
	_color = ClickMarker.color_for(kind)
	_label = label
	_pulse = 1.0
	if not _has and rig != null:
		_screen = rig.camera.unproject_position(point)
	_has = true
	if markers_parent != null:
		ClickMarker.spawn(markers_parent, point, _color)


func _process(delta: float) -> void:
	if not _has or rig == null or not is_instance_valid(champ) or champ.is_dead:
		visible = false
		return
	if rig.camera.is_position_behind(_world):
		visible = false
		return
	visible = true
	var target := rig.camera.unproject_position(_world)
	_screen = _screen.lerp(target, 1.0 - exp(-delta * 10.0))
	_pulse = maxf(0.0, _pulse - delta * 2.0)
	queue_redraw()


func _draw() -> void:
	var p := _screen
	if _pulse > 0.0:
		draw_arc(p, 8.0 + (1.0 - _pulse) * 22.0, 0, TAU, 24, Color(_color, _pulse), 2.0)
	# A classic arrow pointer, tip at p.
	var arrow := PackedVector2Array([
		p, p + Vector2(0, 20), p + Vector2(5, 15), p + Vector2(9, 24),
		p + Vector2(12, 22.5), p + Vector2(8, 13.5), p + Vector2(14, 13.5)])
	draw_colored_polygon(arrow, _color)
	var outline := arrow.duplicate()
	outline.append(p)
	draw_polyline(outline, Color.BLACK, 1.5)
	if _label != "":
		draw_string(get_theme_default_font(), p + Vector2(16, 30), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
