class_name CannonModel
extends Node3D
## A dwarf multicannon built from simple shapes (the asset pack has no cannon
## model): a four-legged iron stand, a round base, and a black barrel with
## brass bands on a turning head. The Slayer's cannon stands on its legs; the
## siege minion's sits on a wooden cart with two wheels. The head turns to
## its target and the barrel kicks back on each shot.

const IRON := Color(0.16, 0.16, 0.17)
const IRON_LIGHT := Color(0.3, 0.3, 0.32)
const BRASS := Color(0.78, 0.6, 0.22)
const WOOD := Color(0.42, 0.28, 0.15)

var head: Node3D
var barrel: Node3D
var _barrel_rest := Vector3.ZERO
var _on_cart := false
var _since_fire := 99.0


static func build(accent: Color, on_cart: bool = false, size: float = 1.0) -> CannonModel:
	var m := CannonModel.new()
	m._on_cart = on_cart
	m._build(accent, on_cart)
	m.scale = Vector3.ONE * size
	return m


func _build(accent: Color, on_cart: bool) -> void:
	var base_y := 0.0
	var osrs := OsrsProps.prop("cannon", 0.0, 1.5)
	if on_cart:
		# The siege minion: the gnome ballista from the Tree Gnome Village
		# (object 2181) when the pack has it, on its own wooden frame.
		var ballista := OsrsProps.prop("ballista", 0.0, 2.4)
		if ballista != null:
			if osrs != null:
				osrs.queue_free()
			head = Node3D.new()
			add_child(head)
			barrel = Node3D.new()
			head.add_child(barrel)
			ballista.rotation_degrees.y = float(OsrsModels.config().get("ballista_yaw", 0.0))
			barrel.add_child(ballista)
			# The barrel points along -Z and the minion walks along +Z, so the
			# whole cart is turned round: the ballista leads the way it travels.
			rotation.y = PI
			_barrel_rest = barrel.position
			return
	if on_cart:
		# Cart bed and two big wheels; the tow bar trails behind (-Z is the
		# way the barrel points, +Z the way the unit faces: see _process).
		_part(_box(Vector3(1.3, 0.14, 1.6)), WOOD, Vector3(0, 0.5, 0))
		_part(_box(Vector3(0.12, 0.12, 1.0)), WOOD.darkened(0.2), Vector3(0, 0.38, 1.1))
		rotation.y = PI
		for x in [-0.72, 0.72]:
			var wheel := _part(_cyl(0.42, 0.42, 0.12, 14), WOOD.darkened(0.15), Vector3(x, 0.42, 0.0))
			wheel.rotation_degrees = Vector3(0, 0, 90)
			var hub := _part(_cyl(0.1, 0.1, 0.16, 8), IRON_LIGHT, Vector3(x, 0.42, 0.0))
			hub.rotation_degrees = Vector3(0, 0, 90)
		base_y = 0.57
	elif osrs == null:
		# Four splayed iron legs.
		for k in 4:
			var ang := PI * 0.25 + PI * 0.5 * k
			var top := Vector3(cos(ang) * 0.22, 0.5, sin(ang) * 0.22)
			var foot := Vector3(cos(ang) * 0.58, 0.02, sin(ang) * 0.58)
			var leg := _part(_box(Vector3(0.09, (top - foot).length(), 0.09)), IRON, (top + foot) * 0.5)
			leg.basis = Basis(Quaternion(Vector3.UP, (top - foot).normalized()))
			_part(_box(Vector3(0.16, 0.05, 0.16)), IRON_LIGHT, foot)
		base_y = 0.48
	if osrs != null:
		# The real dwarf multicannon from the private pack, on its own legs
		# (or the cart): the whole model turns to aim.
		head = Node3D.new()
		head.position.y = base_y - 0.1 if on_cart else 0.0
		add_child(head)
		barrel = Node3D.new()
		head.add_child(barrel)
		osrs.rotation_degrees.y = float(OsrsModels.config().get("cannon_yaw", 0.0))
		barrel.add_child(osrs)
		_barrel_rest = barrel.position
		return
	# Round base (the furnace drum) with a brass ring and a team-coloured band.
	_part(_cyl(0.34, 0.4, 0.3, 16), IRON, Vector3(0, base_y + 0.15, 0))
	_part(_cyl(0.42, 0.42, 0.05, 16), BRASS, Vector3(0, base_y + 0.3, 0))
	_part(_cyl(0.405, 0.405, 0.06, 16), accent, Vector3(0, base_y + 0.06, 0))
	# Turning head: a cradle and the barrel.
	head = Node3D.new()
	head.position = Vector3(0, base_y + 0.48, 0)
	add_child(head)
	_part(_box(Vector3(0.46, 0.22, 0.42)), IRON_LIGHT, Vector3(0, -0.06, 0), head)
	for x in [-0.25, 0.25]:
		_part(_box(Vector3(0.05, 0.3, 0.2)), BRASS, Vector3(x, 0.02, 0), head)
	barrel = Node3D.new()
	barrel.rotation_degrees = Vector3(8, 0, 0)     # tilted up a little
	head.add_child(barrel)
	var tube := _part(_cyl(0.13, 0.17, 1.15, 14), IRON, Vector3(0, 0, -0.32), barrel)
	tube.rotation_degrees = Vector3(-90, 0, 0)
	var breech := _part(SphereMesh.new(), IRON, Vector3(0, 0, 0.26), barrel)
	breech.scale = Vector3(0.36, 0.36, 0.36)
	for z in [0.12, -0.3, -0.78]:
		var band := _part(_cyl(0.18, 0.18, 0.06, 14), BRASS, Vector3(0, 0, z), barrel)
		band.rotation_degrees = Vector3(-90, 0, 0)
	var muzzle := _part(_cyl(0.19, 0.15, 0.12, 14), IRON_LIGHT, Vector3(0, 0, -0.92), barrel)
	muzzle.rotation_degrees = Vector3(-90, 0, 0)
	_barrel_rest = barrel.position


## Points the head (and barrel) at a world position.
func aim_at(world: Vector3) -> void:
	if head == null or not head.is_inside_tree():
		return
	var to := world - head.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	head.global_rotation.y = atan2(-to.x, -to.z)


## Shot: the barrel kicks back and smoke puffs from the muzzle.
func fire(at: Vector3) -> void:
	_since_fire = 0.0
	aim_at(at)
	if barrel == null or not is_inside_tree():
		return
	var t := create_tween()
	barrel.position = _barrel_rest + Vector3(0, 0, 0.18)
	t.tween_property(barrel, "position", _barrel_rest, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var muzzle_world := barrel.global_transform * Vector3(0, 0, -1.05)
	var host := get_parent().get_parent() if get_parent() != null else null
	if host != null:
		CombatFx.puff(host, muzzle_world, Color(0.75, 0.73, 0.7), 0.28, 0.45)


## On the move, a cart's barrel swings back to point the way it is going
## (shortly after its last shot).
func _process(delta: float) -> void:
	_since_fire += delta
	if not _on_cart or head == null or _since_fire < 1.2:
		return
	head.rotation.y = lerp_angle(head.rotation.y, 0.0, minf(1.0, delta * 4.0))


func _part(mesh: Mesh, c: Color, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.55 if c == BRASS else 0.8
	mat.metallic = 0.6 if c == BRASS or c == IRON or c == IRON_LIGHT else 0.0
	mi.material_override = mat
	(parent if parent != null else self).add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c
