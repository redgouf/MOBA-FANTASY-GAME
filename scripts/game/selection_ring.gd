class_name SelectionRing
extends MeshInstance3D
## Ring drawn on the ground under the selected unit.
## Red for enemies, green for allies, yellow for neutral monsters.

const ENEMY := Color(1.0, 0.25, 0.2)
const ALLY := Color(0.3, 1.0, 0.4)
const NEUTRAL := Color(1.0, 0.85, 0.25)

var target: Unit
var viewer_team := 0

var _mat: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86
	ring.outer_radius = 1.0
	ring.rings = 48
	ring.ring_segments = 6
	mesh = ring
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Depth-tested: the part of the ring behind the unit is hidden by its body.
	_mat.no_depth_test = false
	_mat.render_priority = 2
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(delta: float) -> void:
	if not is_instance_valid(target) or target.is_dead or not target.visible or target.fog_hidden:
		visible = false
		return
	_time += delta
	visible = true
	var r := target.radius + 0.35
	scale = Vector3(r, 0.04, r)
	global_position = Vector3(target.global_position.x, 0.08, target.global_position.z)
	var c := NEUTRAL
	if target.team == viewer_team:
		c = ALLY
	elif target.team != Combat.Team.NEUTRAL:
		c = ENEMY
	c.a = 0.75 + 0.2 * sin(_time * 5.0)
	_mat.albedo_color = c
