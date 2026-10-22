class_name HealthBar3D
extends Node3D
## Billboarded OSRS-style health bar: green for health left, red for health
## missing, with a thin black outline. Champions' bars (and names) draw on
## top of everyone else's (higher render priority, no depth test).

const GREEN := Color(0.0, 0.82, 0.0)
const RED := Color(0.78, 0.0, 0.0)

var _width := 1.4
var _height := 0.16
var _fill_mesh: QuadMesh
var _ratio := -1.0


## `layer` lifts the draw order: champions use 2, everything else 0.
func setup(_team_color: Color, width: float, layer: int = 0) -> void:
	_width = width
	var base := layer * 10
	_quad(Vector2(_width + 0.06, _height + 0.06), Color(0, 0, 0, 0.9), base)
	_quad(Vector2(_width, _height), RED, base + 1)
	var fill := _quad(Vector2(_width, _height), GREEN, base + 2)
	_fill_mesh = fill.mesh as QuadMesh
	set_ratio(1.0)


func _quad(sz: Vector2, color: Color, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	mi.material_override = _make_material(color, priority)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func set_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if _fill_mesh == null or is_equal_approx(ratio, _ratio):
		return
	_ratio = ratio
	_fill_mesh.size = Vector2(maxf(_width * ratio, 0.001), _height)
	_fill_mesh.center_offset = Vector3(-_width * (1.0 - ratio) * 0.5, 0.0, 0.0)


func _make_material(color: Color, priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = color
	mat.render_priority = priority
	return mat
