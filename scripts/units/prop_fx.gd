class_name PropFx
extends Node3D
## Short-lived whitebox props for skilling actions (the Skiller's kit):
##   tree      a yew planted ahead of the caster that falls toward the cursor
##   fire      logs and flickering flames for the bonfire's duration
##   anvil     an anvil dropping from the sky, with a shadow telegraph
##   harpoon   a line from the caster to the target
##   fireworks an OSRS-style level-up burst
## Purely visual: damage comes from the ability's own effects.

const BARK := Color(0.42, 0.27, 0.13)
const LEAVES := Color(0.18, 0.45, 0.16)
const IRON := Color(0.3, 0.31, 0.34)


static func spawn(parent: Node, shape: String, at: Vector3, dir: Vector3, duration: float, from: Vector3) -> void:
	if parent == null:
		return
	var fx := PropFx.new()
	parent.add_child(fx)
	fx.global_position = Vector3(at.x, 0.0, at.z)
	match shape:
		"tree":
			fx._tree(dir, from)
		"fire":
			fx._fire(duration)
		"anvil":
			fx._anvil(duration)
		"harpoon":
			fx._harpoon(from)
		"fireworks":
			fx._fireworks()
		_:
			fx.queue_free()


func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _mesh(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D = null, glow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, glow)
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _free_after(t: float) -> void:
	get_tree().create_timer(t, false).timeout.connect(queue_free)


## Planted 1.5 m ahead of the caster; tips over along the aim direction.
func _tree(dir: Vector3, from: Vector3) -> void:
	global_position = Vector3(from.x, 0.0, from.z) + dir * 1.5
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.rotation.y = atan2(dir.x, dir.z)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 5.0
	_mesh(trunk, BARK, Vector3(0, 2.5, 0), pivot)
	var crown := SphereMesh.new()
	crown.radius = 1.6
	crown.height = 3.0
	_mesh(crown, LEAVES, Vector3(0, 5.6, 0), pivot)
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_property(pivot, "rotation:x", PI * 0.5, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.6)
	tween.tween_property(pivot, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	_free_after(1.7)


func _fire(duration: float) -> void:
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.15
	log_mesh.bottom_radius = 0.15
	log_mesh.height = 1.4
	for i in 3:
		var l := _mesh(log_mesh, BARK, Vector3(0, 0.15, 0))
		l.rotation = Vector3(PI * 0.5, float(i) * PI / 3.0, 0)
	var ring := CylinderMesh.new()
	ring.top_radius = 2.5
	ring.bottom_radius = 2.5
	ring.height = 0.02
	var glow := _mesh(ring, Color(1.0, 0.45, 0.1, 0.35), Vector3(0, 0.05, 0), null, true)
	(glow.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 3:
		var flame := CylinderMesh.new()
		flame.top_radius = 0.0
		flame.bottom_radius = 0.35 - i * 0.08
		flame.height = 1.2 + i * 0.3
		var f := _mesh(flame, [Color(1.0, 0.35, 0.05), Color(1.0, 0.6, 0.1), Color(1.0, 0.9, 0.3)][i], Vector3(0, 0.6 + i * 0.15, 0), null, true)
		var tw := f.create_tween().set_loops(int(ceil(duration / 0.4)))
		tw.tween_property(f, "scale", Vector3(1.0, 1.3, 1.0), 0.2)
		tw.tween_property(f, "scale", Vector3(0.9, 0.8, 0.9), 0.2)
	_free_after(duration)


## The shadow grows while the anvil falls; it lands after `duration` seconds.
func _anvil(duration: float) -> void:
	var shadow := CylinderMesh.new()
	shadow.top_radius = 3.0
	shadow.bottom_radius = 3.0
	shadow.height = 0.02
	var s := _mesh(shadow, Color(0, 0, 0, 0.45), Vector3(0, 0.06, 0), null, true)
	(s.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.scale = Vector3(0.2, 1, 0.2)
	var body := Node3D.new()
	body.position = Vector3(0, 14, 0)
	add_child(body)
	var top := BoxMesh.new()
	top.size = Vector3(2.6, 0.6, 1.1)
	_mesh(top, IRON, Vector3(0, 1.3, 0), body)
	var waist := BoxMesh.new()
	waist.size = Vector3(1.0, 0.8, 0.8)
	_mesh(waist, IRON.darkened(0.2), Vector3(0, 0.6, 0), body)
	var foot := BoxMesh.new()
	foot.size = Vector3(1.8, 0.4, 1.1)
	_mesh(foot, IRON, Vector3(0, 0.2, 0), body)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(body, "position:y", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(s, "scale", Vector3(1, 1, 1), duration)
	tween.chain().tween_interval(0.8)
	tween.chain().tween_property(body, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
	_free_after(duration + 1.2)


## A line from the caster to the hooked target.
func _harpoon(from: Vector3) -> void:
	var a := Vector3(from.x, 1.2, from.z)
	var b := global_position + Vector3(0, 1.0, 0)
	global_position = Vector3.ZERO
	var line := CylinderMesh.new()
	line.top_radius = 0.04
	line.bottom_radius = 0.04
	line.height = maxf(a.distance_to(b), 0.1)
	var mi := _mesh(line, Color(0.85, 0.85, 0.8), (a + b) * 0.5, null, true)
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var tip := SphereMesh.new()
	tip.radius = 0.15
	tip.height = 0.3
	_mesh(tip, Color(0.75, 0.78, 0.82), b)
	_free_after(0.45)


## OSRS level-up fireworks: coloured sparks bursting outward and up.
func _fireworks() -> void:
	var colors := [Color(1, 0.2, 0.2), Color(1, 0.85, 0.2), Color(0.3, 0.9, 0.3), Color(0.3, 0.6, 1), Color(0.9, 0.4, 1)]
	for i in 18:
		var spark := SphereMesh.new()
		spark.radius = 0.16
		spark.height = 0.32
		var m := _mesh(spark, colors[i % colors.size()], Vector3(0, 2.4, 0), null, true)
		var a := TAU * float(i) / 18.0
		var dest := Vector3(cos(a) * 3.6, 2.4 + sin(float(i) * 1.7) * 1.4 + 1.0, sin(a) * 3.6)
		var tw := m.create_tween().set_parallel(true)
		tw.tween_property(m, "position", dest, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(m, "scale", Vector3(0.2, 0.2, 0.2), 0.55)
	_free_after(0.6)
