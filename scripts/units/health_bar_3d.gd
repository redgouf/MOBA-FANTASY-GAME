class_name HealthBar3D
extends Node3D
## Billboarded health bar drawn with two quads (no textures needed).

var _width := 1.4
var _height := 0.16
var _fill_mesh: QuadMesh
var _ratio := -1.0


func setup(color: Color, width: float) -> void:
	_width = width
	var back := MeshInstance3D.new()
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(_width + 0.06, _height + 0.06)
	back.mesh = back_mesh
	back.material_override = _make_material(Color(0.05, 0.05, 0.05, 0.85), 0)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)

	var fill := MeshInstance3D.new()
	_fill_mesh = QuadMesh.new()
	_fill_mesh.size = Vector2(_width, _height)
	fill.mesh = _fill_mesh
	fill.material_override = _make_material(color, 1)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fill)
	set_ratio(1.0)


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
