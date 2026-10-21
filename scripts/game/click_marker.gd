class_name ClickMarker
extends RefCounted
## Shrinking ring on the ground where a move/attack/cast order was given.

const MOVE := Color(0.4, 1.0, 0.4, 0.9)
const ATTACK := Color(1.0, 0.3, 0.25, 0.9)
const CAST := Color(0.45, 0.75, 1.0, 0.9)


static func color_for(kind: String) -> Color:
	match kind:
		"attack":
			return ATTACK
		"cast":
			return CAST
	return MOVE


static func spawn(parent: Node, point: Vector3, color: Color) -> void:
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.35
	ring.outer_radius = 0.5
	marker.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(marker)
	marker.global_position = Vector3(point.x, 0.08, point.z)
	marker.scale = Vector3(1.6, 1.0, 1.6)
	var tween := marker.create_tween()
	tween.tween_property(marker, "scale", Vector3(0.2, 1.0, 0.2), 0.35)
	tween.tween_callback(marker.queue_free)
