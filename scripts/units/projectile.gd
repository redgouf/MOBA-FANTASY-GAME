class_name Projectile
extends Node3D
## Homing projectile for ranged and magic attacks, shaped by the attacker's
## weapon: arrows, bolts, darts, javelins, thrown rocks, cannonballs or spell
## orbs with a glowing trail. Damage (on_hit) is applied on arrival.
## Visual-only projectiles (abilities) fly to a unit or a point.

const STYLE_COLORS := [Color(0.9, 0.9, 0.9), Color(0.55, 0.85, 0.3), Color(0.45, 0.6, 1.0)]

var target: Unit
var target_point := Vector3.ZERO
var speed := 30.0
var on_hit: Callable
var fx: Dictionary = {}

var _start := Vector3.ZERO
var _total := 1.0
var _arc := 0.0
var _trail_timer := 0.0
var _spin: Node3D
var _color := Color.WHITE


## Default look for an attacker's basic attacks, by style.
static func default_fx(style: int) -> Dictionary:
	match style:
		Combat.Style.RANGED:
			return {"kind": "projectile", "shape": "arrow"}
		Combat.Style.MAGIC:
			return {"kind": "projectile", "shape": "orb", "color": "#7f9cff", "impact": "splash"}
	return {"kind": "swipe", "arc": "slash"}


static func launch(source: Unit, p_target: Unit, p_fx: Variant, p_on_hit: Callable, p_speed: float = 0.0) -> Projectile:
	var f: Dictionary = p_fx if p_fx is Dictionary else default_fx(int(p_fx))
	var p := Projectile.new()
	p.target = p_target
	p.on_hit = p_on_hit
	p._setup(source, f, p_speed)
	return p


## A visual-only projectile flying to a fixed point (ability effects).
static func launch_to_point(source: Node3D, point: Vector3, p_fx: Dictionary, from: Vector3 = Vector3.INF) -> Projectile:
	var p := Projectile.new()
	p.target_point = point + Vector3.UP * 0.6
	p._setup(source, p_fx, 0.0, from)
	return p


func _setup(source: Node3D, f: Dictionary, p_speed: float, from: Vector3 = Vector3.INF) -> void:
	fx = f
	var shape := str(f.get("shape", "orb"))
	_color = CombatFx.color(f.get("color", ""), {"arrow": Color(0.55, 0.4, 0.25), "bolt": Color(0.6, 0.62, 0.66),
		"dart": Color(0.3, 0.8, 0.3), "rock": Color(0.5, 0.48, 0.45), "cannonball": Color(0.15, 0.15, 0.17),
		"javelin": Color(0.7, 0.7, 0.72), "fireball": Color(1.0, 0.5, 0.1)}.get(shape, Color(0.5, 0.65, 1.0)))
	speed = p_speed if p_speed > 0.0 else float(f.get("speed", {"orb": 26.0, "fireball": 22.0, "rock": 18.0,
		"cannonball": 20.0, "dart": 40.0, "bolt": 38.0, "arrow": 34.0}.get(shape, 30.0)))
	_arc = float(f.get("arc", {"rock": 1.6, "cannonball": 1.2}.get(shape, 0.0)))
	source.get_parent().add_child(self)
	_start = from if from != Vector3.INF else source.global_position + Vector3.UP * 1.3
	global_position = _start
	_total = maxf(0.5, _start.distance_to(_aim()))
	_build(shape)
	_face(_aim() - global_position)


func _aim() -> Vector3:
	if target != null:
		return target.global_position + Vector3.UP * minf(1.0, target.visual_height() * 0.5)
	return target_point


func _build(shape: String) -> void:
	var c := _color
	match shape:
		"arrow":
			_part(_cyl(0.022, 0.95), Color(0.5, 0.36, 0.22), Vector3(0, 0, 0.1), true)
			_part(_cone(0.06, 0.18), Color(0.75, 0.75, 0.78), Vector3(0, 0, -0.45), true)
			_part(_box(Vector3(0.14, 0.01, 0.16)), Color(0.9, 0.9, 0.88), Vector3(0, 0, 0.5))
			_part(_box(Vector3(0.01, 0.14, 0.16)), Color(0.9, 0.9, 0.88), Vector3(0, 0, 0.5))
		"bolt":
			_part(_cyl(0.03, 0.5), Color(0.35, 0.3, 0.28), Vector3(0, 0, 0.05), true)
			_part(_cone(0.06, 0.14), c, Vector3(0, 0, -0.26), true, true)
		"dart":
			_part(_cyl(0.018, 0.32), Color(0.75, 0.75, 0.75), Vector3.ZERO, true)
			_part(_cone(0.035, 0.1), c, Vector3(0, 0, -0.2), true, true)
		"javelin":
			_part(_cyl(0.03, 1.3), Color(0.55, 0.45, 0.3), Vector3(0, 0, 0.1), true)
			_part(_cone(0.07, 0.25), c, Vector3(0, 0, -0.7), true)
		"rock":
			_spin = Node3D.new()
			add_child(_spin)
			var r := SphereMesh.new()
			r.radius = float(fx.get("size", 0.16))
			r.height = r.radius * 1.7
			r.radial_segments = 6
			r.rings = 3
			_part(r, c, Vector3.ZERO, false, false, _spin)
		"cannonball":
			var s := SphereMesh.new()
			s.radius = 0.2
			s.height = 0.4
			_part(s, c, Vector3.ZERO)
		_:
			# Spell orb (or fireball): bright core and a soft halo; a trail follows.
			var size := float(fx.get("size", 0.2 if shape == "orb" else 0.3))
			var core := SphereMesh.new()
			core.radius = size
			core.height = size * 2.0
			_part(core, c.lightened(0.35), Vector3.ZERO, false, true)
			var halo := SphereMesh.new()
			halo.radius = size * 1.9
			halo.height = size * 3.8
			var h := _part(halo, Color(c.r, c.g, c.b, 0.35), Vector3.ZERO, false, true)
			(h.material_override as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD


func _cyl(r: float, length: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = length
	m.radial_segments = 6
	m.rings = 1
	return m


func _cone(r: float, length: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = length
	m.radial_segments = 6
	m.rings = 1
	return m


func _box(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Adds a mesh part. `along_z` lays a Y-up mesh (cylinder/cone) along -Z, the
## direction look_at points the node.
func _part(mesh: Mesh, col: Color, pos: Vector3, along_z: bool = false, glow: bool = false, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if along_z:
		mi.rotation.x = -PI * 0.5
	mi.material_override = CombatFx.material(col, glow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	if target != null and (not is_instance_valid(target) or target.is_dead):
		queue_free()
		return
	var aim := _aim()
	var flat := Vector3(aim.x, _start.y, aim.z)
	var to := aim - global_position
	var step := speed * delta
	if to.length() <= step + 0.2:
		_arrive(aim)
		return
	var next := global_position + to.normalized() * step
	if _arc > 0.0:
		# Lob: a parabola on top of the straight path.
		var progress := clampf(1.0 - Vector3(next.x, _start.y, next.z).distance_to(flat) / _total, 0.0, 1.0)
		next.y = lerpf(_start.y, aim.y, progress) + sin(progress * PI) * _arc
	_face(next - global_position)
	global_position = next
	if _spin != null:
		_spin.rotate_x(delta * 14.0)
	var shape := str(fx.get("shape", "orb"))
	if shape == "orb" or shape == "fireball":
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = 0.012
			CombatFx.puff(get_parent(), global_position, _color, float(fx.get("size", 0.2)) * 0.9, 0.2)


## Points the projectile's -Z along `dir` (safe for straight-down shots).
func _face(dir: Vector3) -> void:
	if dir.length() < 0.001:
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.FORWARD
	look_at(global_position + dir, up)


func _arrive(at: Vector3) -> void:
	if on_hit.is_valid():
		on_hit.call()
	var impact := str(fx.get("impact", ""))
	if impact != "":
		CombatFx.impact(get_parent(), at, impact, _color)
	queue_free()
