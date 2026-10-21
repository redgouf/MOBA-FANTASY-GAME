class_name Projectile
extends MeshInstance3D
## Homing projectile for ranged and magic attacks. Damage is applied on arrival.

const STYLE_COLORS := [Color(0.9, 0.9, 0.9), Color(0.55, 0.85, 0.3), Color(0.45, 0.6, 1.0)]

var target: Unit
var speed := 30.0
var on_hit: Callable


static func launch(source: Unit, p_target: Unit, style: int, p_on_hit: Callable, p_speed: float = 30.0) -> void:
	var p := Projectile.new()
	p.target = p_target
	p.speed = p_speed
	p.on_hit = p_on_hit
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	p.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = STYLE_COLORS[clampi(style, 0, 2)]
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	source.get_parent().add_child(p)
	p.global_position = source.global_position + Vector3.UP * 1.4


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or target.is_dead:
		queue_free()
		return
	var aim := target.global_position + Vector3.UP * 1.0
	var to := aim - global_position
	var step := speed * delta
	if to.length() <= step + 0.2:
		if on_hit.is_valid():
			on_hit.call()
		queue_free()
		return
	global_position += to.normalized() * step
