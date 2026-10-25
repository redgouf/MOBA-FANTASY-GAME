class_name PrayerAltar
extends StaticBody3D
## A neutral prayer altar beside a jungle buff camp. Anyone can pray at it
## (right-click it): a short channel, broken by damage, that restores prayer
## points to full. Each champion then waits a while before praying again
## (rules.json "prayer_altar"). Not to be confused with the team "altars"
## (the Saradomin / Chaos altars that work like League inhibitors).

const STONE := Color(0.55, 0.53, 0.5)
const CLOTH := Color(0.92, 0.9, 0.84)
const TRIM := Color(0.85, 0.68, 0.25)

## Every altar on the map, for bots and picking.
static var active: Array[PrayerAltar] = []
## Prayers completed at any altar this match (smoke-test report).
static var uses := 0

var radius := 1.0
var side := ""          # "blue" or "red": the buff camp it stands beside

var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _pulse := 0.0


## The closest altar to `pos` within `max_dist` metres, or null.
static func nearest(pos: Vector3, max_dist: float = INF) -> PrayerAltar:
	var best: PrayerAltar = null
	var best_d := max_dist
	for a in active:
		if not is_instance_valid(a):
			continue
		var d := Unit.flat_distance(pos, a.global_position)
		if d <= best_d:
			best_d = d
			best = a
	return best


func _ready() -> void:
	if active.is_empty():
		uses = 0
	add_to_group("prayer_altars")
	collision_layer = Unit.LAYER_WALLS
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 1.2
	shape.shape = cyl
	shape.position = Vector3(0, 0.6, 0)
	add_child(shape)
	_build_visual()
	active.append(self)


func _exit_tree() -> void:
	active.erase(self)


func _build_visual() -> void:
	var osrs := OsrsProps.prop("prayer_altar", 0.0, 2.3)
	if osrs != null:
		add_child(osrs)       # the OSRS altar (private pack), with the same star and ring
	else:
		_build_whitebox_altar()
	_build_glow()


## A stone altar with a white cloth and two candles.
func _build_whitebox_altar() -> void:
	_mesh(_box(Vector3(1.9, 0.9, 1.1)), STONE, Vector3(0, 0.45, 0))
	_mesh(_box(Vector3(2.05, 0.08, 1.25)), STONE.lightened(0.15), Vector3(0, 0.94, 0))
	_mesh(_box(Vector3(1.4, 0.03, 1.27)), CLOTH, Vector3(0, 0.99, 0))
	_mesh(_box(Vector3(0.5, 0.62, 0.02)), CLOTH, Vector3(0, 0.68, 0.566))
	_mesh(_box(Vector3(0.18, 0.18, 0.025)), TRIM, Vector3(0, 0.7, 0.58))
	for x in [-0.75, 0.75]:
		var candle := CylinderMesh.new()
		candle.top_radius = 0.06
		candle.bottom_radius = 0.06
		candle.height = 0.32
		_mesh(candle, Color(0.95, 0.93, 0.85), Vector3(x, 1.16, -0.25))
		var flame := SphereMesh.new()
		flame.radius = 0.06
		flame.height = 0.16
		_mesh(flame, Color(1.0, 0.75, 0.3), Vector3(x, 1.38, -0.25), true)


## The glowing prayer star above the altar, the reach ring and the label.
func _build_glow() -> void:
	var star := PrismMesh.new()
	star.size = Vector3(0.45, 0.45, 0.06)
	_glow = _mesh(star, Color(0.75, 0.9, 1.0), Vector3(0, 1.75, 0), true)
	_glow_mat = _glow.material_override as StandardMaterial3D
	var flipped := _mesh(star, Color(0.75, 0.9, 1.0), Vector3(0, -0.12, 0), true)
	flipped.rotation_degrees = Vector3(0, 0, 180)
	remove_child(flipped)
	_glow.add_child(flipped)
	# The range you can pray from, as a faint ring on the ground.
	var ring := TorusMesh.new()
	var reach := radius + float(GameData.rule("prayer_altar", {}).get("range", 2.6))
	ring.inner_radius = reach - 0.08
	ring.outer_radius = reach
	ring.rings = 48
	var r := _mesh(ring, Color(0.7, 0.85, 1.0, 0.35), Vector3(0, 0.03, 0), true)
	(r.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r.scale = Vector3(1, 0.05, 1)
	var label := Label3D.new()
	label.text = "Prayer altar"
	label.font_size = 40
	label.pixel_size = 0.01
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.85, 0.92, 1.0)
	label.position = Vector3(0, 2.45, 0)
	label.no_depth_test = false
	add_child(label)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _mesh(mesh: Mesh, c: Color, pos: Vector3, glow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.4
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	if _glow == null:
		return
	_pulse += delta
	_glow.rotation.y += delta * 1.2
	_glow.position.y = 1.75 + sin(_pulse * 2.0) * 0.08
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 1.2 + 0.5 * sin(_pulse * 3.0)


## Called by a champion who just finished praying here.
func on_prayed(by: Champion) -> void:
	uses += 1
	if not is_inside_tree():
		return
	CombatFx.glow(by, Color(0.75, 0.9, 1.0), 0.9)
	CombatFx.ring(get_parent(), global_position, radius + 1.2, Color(0.75, 0.9, 1.0), 0.6)
