class_name MapBuilder
extends Node3D
## Builds the whitebox Wilderness Rift from MapLayout: the painted ground
## (brush, river, pits), the rock walls traced from the League map, team-only
## base gates, lanes, and a navigation mesh baked at runtime.

signal navigation_ready

## How far ground clutter is lifted off the terrain (metres).
const CLUTTER_LIFT := 0.03
const GROUND_COLOR := Color(0.33, 0.31, 0.22)
const LANE_COLOR := Color(0.56, 0.48, 0.34)
const RIVER_COLOR := Color(0.2, 0.36, 0.5)
const ROCK_COLOR := Color(0.38, 0.36, 0.34)
const PIT_COLOR := Color(0.45, 0.2, 0.08)
const WALL_HEIGHT := 3.0
## Navigation layer bits: everyone walks layer 1; the team-gate links use one
## each so only their own team's pathfinding goes through a gate.
const NAV_LAYER_ALL := 1
const NAV_LAYER_SARADOMIN := 2
const NAV_LAYER_ZAMORAK := 4

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
var wall_shapes := 0        # convex collider pieces the rock walls were cut into
var wall_polygons_skipped := 0   # outlines the engine couldn't cut (should stay 0)


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
	# Pebbles and ground clutter sit exactly flush with the terrain: lift them a
	# hair so they stop z-fighting with it (flickering dark specks).
	for n in rift.find_children("clutter*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).position.y += CLUTTER_LIFT / tile
	rift.position = Vector3(float(origin[0]), 0.0, float(origin[1]))
	add_child(rift)
	osrs_dressed = true
	for n in _whitebox_visuals:
		n.visible = false
	if not Settings.changed.is_connected(apply_foliage):
		Settings.changed.connect(apply_foliage)
	apply_foliage()


## The foliage setting: Low hides the (heavy) ground clutter, Medium keeps it
## but stops it casting shadows, High is everything.
func apply_foliage() -> void:
	var rift := get_node_or_null("OsrsRift")
	if rift == null:
		return
	for n in rift.find_children("clutter*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.visible = Settings.foliage > 0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Settings.foliage >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
	sun.add_to_group("sun")
	add_child(sun)
	Settings.apply_shadows()


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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "RockWalls"
	body.collision_layer = Unit.LAYER_WALLS
	body.collision_mask = 0
	nav_region.add_child(body)
	for poly in MapLayout.wall_polygons():
		var pts := _clean_polygon(poly)
		if pts.size() < 3:
			continue
		var pieces := Geometry2D.decompose_polygon_in_convex(pts)
		if pieces.is_empty():
			var flipped := pts.duplicate()
			flipped.reverse()
			pieces = Geometry2D.decompose_polygon_in_convex(flipped)
		if pieces.is_empty():
			wall_polygons_skipped += 1
			continue
		for piece in pieces:
			var shape := ConvexPolygonShape3D.new()
			var pts3 := PackedVector3Array()
			for p in piece:
				pts3.append(Vector3(p.x, 0.0, p.y))
				pts3.append(Vector3(p.x, WALL_HEIGHT, p.y))
			shape.points = pts3
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			wall_shapes += 1
		_extrude(st, pts)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "RockWallMesh"
	mesh.mesh = st.commit()
	var mat := _material(ROCK_COLOR)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	body.add_child(mesh)
	_whitebox_visuals.append(mesh)
	# Everything past the traced outer rim is solid too.
	var half := MapLayout.MAP_SIZE * 0.5
	var span := MapLayout.MAP_SIZE + 8.0
	_add_wall(Vector3(0.0, 0.0, -half - 2.0), Vector3(span, WALL_HEIGHT, 4.0))
	_add_wall(Vector3(0.0, 0.0, half + 2.0), Vector3(span, WALL_HEIGHT, 4.0))
	_add_wall(Vector3(-half - 2.0, 0.0, 0.0), Vector3(4.0, WALL_HEIGHT, span))
	_add_wall(Vector3(half + 2.0, 0.0, 0.0), Vector3(4.0, WALL_HEIGHT, span))
	_build_gates()


## A polygon without repeated or collinear-duplicate points.
func _clean_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.01:
			out.append(p)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 0.01:
		out.remove_at(out.size() - 1)
	return out


## A rock-wall prism for the whitebox look: a triangulated top and the sides.
func _extrude(st: SurfaceTool, pts: PackedVector2Array) -> void:
	var tri := Geometry2D.triangulate_polygon(pts)
	for i in tri.size():
		var p := pts[tri[i]]
		st.add_vertex(Vector3(p.x, WALL_HEIGHT, p.y))
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var a0 := Vector3(a.x, 0.0, a.y)
		var a1 := Vector3(a.x, WALL_HEIGHT, a.y)
		var b0 := Vector3(b.x, 0.0, b.y)
		var b1 := Vector3(b.x, WALL_HEIGHT, b.y)
		for v in [a0, b0, b1, a0, b1, a1]:
			st.add_vertex(v)


## Team-only base gates: solid to every other team (their own collision
## layer, which only the other teams' units collide with, and which the
## navmesh bake treats as wall), with a navigation link across each gate on
## the owning team's layer, so only their pathfinding goes through.
func _build_gates() -> void:
	for g in MapLayout.gates():
		var team: int = g["team"]
		var size: Vector2 = g["size"]
		var pos: Vector3 = g["pos"]
		var body := StaticBody3D.new()
		body.name = "Gate_%s" % ("saradomin" if team == Combat.Team.SARADOMIN else "zamorak")
		body.collision_layer = Unit.gate_layer(team)
		body.collision_mask = 0
		body.position = pos + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, WALL_HEIGHT, size.y)
		cs.shape = box
		body.add_child(cs)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x, 0.4, size.y)
		mesh.mesh = bm
		var mat := _material(Unit.team_color(team).darkened(0.3))
		mat.albedo_color.a = 0.55
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = mat
		mesh.position.y = -WALL_HEIGHT * 0.5 + 0.2
		body.add_child(mesh)
		_whitebox_visuals.append(mesh)
		nav_region.add_child(body)
		# The way through is across the gate's short side.
		var along := MapLayout.gate_axis(size)
		var reach := minf(size.x, size.y) * 0.5 + 0.9
		var link := NavigationLink3D.new()
		link.name = body.name + "_link"
		link.bidirectional = true
		link.navigation_layers = NAV_LAYER_SARADOMIN if team == Combat.Team.SARADOMIN else NAV_LAYER_ZAMORAK
		link.start_position = pos - along * reach
		link.end_position = pos + along * reach
		add_child(link)


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
	# The ground picture: river, brush and the two pits painted from the grids.
	var rect := MapPaint.world_rect()
	var img := MapPaint.image(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.2, 0.3, 0.14), RIVER_COLOR, PIT_COLOR)
	var paint := MeshInstance3D.new()
	paint.name = "TerrainPaint"
	var plane := PlaneMesh.new()
	plane.size = rect.size
	paint.mesh = plane
	var pmat := StandardMaterial3D.new()
	pmat.albedo_texture = ImageTexture.create_from_image(img)
	pmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.roughness = 0.95
	paint.material_override = pmat
	paint.position = Vector3(rect.get_center().x, 0.012, rect.get_center().y)
	add_child(paint)
	_whitebox_visuals.append(paint)
	for lane in MapLayout.LANES:
		var path := MapLayout.lane_path(lane, Combat.Team.SARADOMIN)
		for i in range(1, path.size() - 2):
			_strip(path[i], path[i + 1], MapLayout.LANE_WIDTH * 0.7, LANE_COLOR, 0.02)
	var fountain_r := float(GameData.rule("fountain_radius", 12))
	_disc(MapLayout.SARADOMIN_BASE, fountain_r, Unit.team_color(Combat.Team.SARADOMIN).darkened(0.45), 0.04)
	_disc(MapLayout.ZAMORAK_BASE, fountain_r, Unit.team_color(Combat.Team.ZAMORAK).darkened(0.45), 0.04)
	_ground_label("Saradomin", MapLayout.nexus_position(Combat.Team.SARADOMIN) + Vector3(0.0, 0.0, -9.0))
	_ground_label("Zamorak", MapLayout.nexus_position(Combat.Team.ZAMORAK) + Vector3(0.0, 0.0, 9.0))
	_ground_label("TzTok-Jad", MapLayout.jad_pit() + Vector3(0.0, 0.0, 9.0))
	_ground_label("Dragon pit", MapLayout.dragon_pit() + Vector3(0.0, 0.0, -9.0))


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
	nm.geometry_collision_mask = Unit.LAYER_WALLS | Unit.LAYER_GROUND | Unit.LAYER_GATE_SARADOMIN | Unit.LAYER_GATE_ZAMORAK
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
