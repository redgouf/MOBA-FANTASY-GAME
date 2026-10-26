class_name MapBuilder
extends Node3D
## Builds the whitebox Wilderness Rift from MapLayout: ground, lanes, the
## Wilderness Ditch (visual only, walkable like any river), rock walls, base
## platforms, objective pits, and a navigation mesh baked at runtime.

signal navigation_ready

const GROUND_COLOR := Color(0.33, 0.31, 0.22)
const LANE_COLOR := Color(0.56, 0.48, 0.34)
const RIVER_COLOR := Color(0.2, 0.36, 0.5)
const ROCK_COLOR := Color(0.38, 0.36, 0.34)
const PIT_COLOR := Color(0.45, 0.2, 0.08)

var nav_region: NavigationRegion3D
var is_navigation_ready := false
var rebake_count := 0

var _baking := false
var _rebake_pending := false
var _bake_started_ms := 0
var _watchdog := 0.0
var resubmits := 0          # times the watchdog reloaded an empty navmesh
var osrs_dressed := false   # the OSRS Rift from the private pack replaced the whitebox look
var _whitebox_visuals: Array[Node3D] = []


func build() -> void:
	add_to_group("map_builder")
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)
	_build_ground()
	_build_walls()
	_build_prayer_altars()
	_build_markings()
	_build_osrs_dressing()
	_bake_navigation()


## With the private model pack: the OSRS-dressed Rift (rift/rift.glb from
## tools/osrs_extract: Wilderness ground, dirt lanes, the Ditch, the two bases
## and pits, rocks and dead trees on every wall) replaces the whitebox
## surfaces. Colliders and navigation stay exactly the same.
func _build_osrs_dressing() -> void:
	if not OsrsModels.available():
		return
	var info: Dictionary = OsrsModels.manifest().get("rift", {})
	var ps := OsrsModels.scene(str(info.get("file", "rift/rift.glb")))
	if ps == null:
		return
	var rift := ps.instantiate() as Node3D
	rift.name = "OsrsRift"
	OsrsModels.apply_material(rift)
	for mi in rift.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if str(mi.name).begins_with("terrain") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var tile := float(info.get("tile", 1.4))
	var origin: Array = info.get("origin", [-110.6, 110.6])
	rift.scale = Vector3.ONE * tile
	rift.position = Vector3(float(origin[0]), 0.0, float(origin[1]))
	add_child(rift)
	osrs_dressed = true
	for n in _whitebox_visuals:
		n.visible = false


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.09, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.57, 0.52)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	# OSRS capes and flags are thin, two-faced models: with the default bias
	# they shadow themselves in stripes ("shadow acne").
	sun.shadow_bias = 0.35
	sun.shadow_normal_bias = 2.6
	add_child(sun)


func _build_ground() -> void:
	var size := MapLayout.MAP_SIZE + 20.0
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Unit.LAYER_GROUND
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mesh.mesh = plane
	mesh.material_override = _material(GROUND_COLOR)
	body.add_child(mesh)
	_whitebox_visuals.append(mesh)
	nav_region.add_child(body)


func _build_walls() -> void:
	for w in MapLayout.all_walls():
		_add_wall(w["pos"], w["size"])
	var half := MapLayout.MAP_SIZE * 0.5
	var span := MapLayout.MAP_SIZE + 4.0
	_add_wall(Vector3(0.0, 0.0, -half - 1.0), Vector3(span, 3.0, 2.0))
	_add_wall(Vector3(0.0, 0.0, half + 1.0), Vector3(span, 3.0, 2.0))
	_add_wall(Vector3(-half - 1.0, 0.0, 0.0), Vector3(2.0, 3.0, span))
	_add_wall(Vector3(half + 1.0, 0.0, 0.0), Vector3(2.0, 3.0, span))


## Prayer altars are solid (walls layer), so the navmesh is baked around them.
func _build_prayer_altars() -> void:
	for a in MapLayout.all_prayer_altars():
		var altar := PrayerAltar.new()
		altar.side = str(a["side"])
		altar.name = "PrayerAltar_%s_%d" % [altar.side, nav_region.get_child_count()]
		altar.position = a["pos"]
		# Face the open side: towards the map centre line.
		altar.rotation.y = atan2(-float(a["pos"].x), -float(a["pos"].z))
		nav_region.add_child(altar)


func _add_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Unit.LAYER_WALLS
	body.collision_mask = 0
	body.position = pos + Vector3(0.0, size.y * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(ROCK_COLOR)
	body.add_child(mesh)
	_whitebox_visuals.append(mesh)
	nav_region.add_child(body)


func _build_markings() -> void:
	# The Wilderness Ditch is purely visual: units walk straight across it.
	var corner := MapLayout.MAP_SIZE * 0.5
	_strip(Vector3(-corner, 0.0, -corner), Vector3(corner, 0.0, corner), MapLayout.RIVER_WIDTH, RIVER_COLOR, 0.015)
	for lane in MapLayout.LANES:
		var path := MapLayout.lane_path(lane, Combat.Team.SARADOMIN)
		for i in range(1, path.size()):
			_strip(path[i - 1], path[i], MapLayout.LANE_WIDTH, LANE_COLOR, 0.03)
	_disc(MapLayout.SARADOMIN_BASE, MapLayout.BASE_RADIUS, Unit.team_color(Combat.Team.SARADOMIN).darkened(0.45), 0.04)
	_disc(MapLayout.ZAMORAK_BASE, MapLayout.BASE_RADIUS, Unit.team_color(Combat.Team.ZAMORAK).darkened(0.45), 0.04)
	_disc(MapLayout.JAD_PIT, 7.0, PIT_COLOR, 0.045)
	_disc(MapLayout.DRAGON_PIT, 7.0, PIT_COLOR, 0.045)
	_ground_label("Saradomin", MapLayout.SARADOMIN_BASE + Vector3(0.0, 0.0, -13.0))
	_ground_label("Zamorak", MapLayout.ZAMORAK_BASE + Vector3(0.0, 0.0, 13.0))
	_ground_label("TzTok-Jad", MapLayout.JAD_PIT + Vector3(0.0, 0.0, 9.0))
	_ground_label("Dragon pit", MapLayout.DRAGON_PIT + Vector3(0.0, 0.0, -9.0))
	_ground_label("Wilderness Ditch", Vector3(-62.0, 0.0, -56.0))


func _strip(a: Vector3, b: Vector3, width: float, color: Color, y: float) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.02, a.distance_to(b) + width)
	mi.mesh = box
	mi.material_override = _material(color)
	mi.position = (a + b) * 0.5 + Vector3(0.0, y, 0.0)
	mi.rotation.y = atan2(b.x - a.x, b.z - a.z)
	add_child(mi)
	_whitebox_visuals.append(mi)


func _disc(pos: Vector3, radius: float, color: Color, y: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	mi.mesh = cyl
	mi.material_override = _material(color)
	mi.position = pos + Vector3(0.0, y, 0.0)
	add_child(mi)
	_whitebox_visuals.append(mi)


func _ground_label(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 160
	label.pixel_size = 0.02
	label.modulate = Color(1, 1, 1, 0.35)
	label.outline_size = 0
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.position = pos + Vector3(0.0, 0.06, 0.0)
	add_child(label)
	_whitebox_visuals.append(label)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	return mat


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.5
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Unit.LAYER_WALLS | Unit.LAYER_GROUND
	nav_region.navigation_mesh = nm
	nav_region.bake_finished.connect(_on_bake_finished)
	_baking = true
	nav_region.bake_navigation_mesh(true)
	_bake_started_ms = Time.get_ticks_msec()


## Rebakes the navmesh on a worker thread, e.g. after a Timber! yew is planted
## or felled (trees are static colliders under nav_region). Requests made while
## a bake is running are merged into one follow-up bake.
func request_rebake() -> void:
	if nav_region == null or nav_region.navigation_mesh == null:
		return
	if _baking:
		_rebake_pending = true
		return
	_baking = true
	_bake_started_ms = Time.get_ticks_msec()
	nav_region.bake_navigation_mesh(true)


## Watchdog: now and then the navigation server ends up with the region but
## none of its polygons (closest-point queries return nothing), which leaves
## every champion with an empty path. Resubmitting the baked mesh fixes it.
func _physics_process(delta: float) -> void:
	if not is_navigation_ready or _baking:
		return
	_watchdog -= delta
	if _watchdog > 0.0:
		return
	_watchdog = 0.5
	var nav_map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_closest_point_owner(nav_map, MapLayout.SARADOMIN_BASE) == RID():
		resubmits += 1
		NavigationServer3D.region_set_navigation_mesh(nav_region.get_rid(), nav_region.navigation_mesh)


func _on_bake_finished() -> void:
	_baking = false
	_watchdog = 1.0      # give the server a moment to sync before checking
	if is_navigation_ready:
		rebake_count += 1
	else:
		is_navigation_ready = true
		navigation_ready.emit()
	if _rebake_pending:
		_rebake_pending = false
		request_rebake()
