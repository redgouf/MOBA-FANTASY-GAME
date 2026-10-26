class_name FogOfWar
extends Node3D
## League-style fog of war for one team (the player's, or the champion a
## spectator is locked onto). The whole team shares one vision: every allied
## champion, minion, structure and summon reveals a circle around it (League
## sight radii, converted at 75 units = 1 m), and walls block sight. Enemy
## champions, minions and neutral monsters outside it disappear (their
## models, bars and names move to a render layer the camera skips), can't be
## clicked, and vanish from the minimap. Enemy structures stay visible, as in
## League. Outside vision the ground is darkened.

const FOG_LAYER := 1 << 9          # render layer the main camera doesn't draw
const GRID := 64                   # fog texture cells across the map
const SIGHT_LOL := {"champion": 1350.0, "super": 1350.0, "minion": 1200.0, "structure": 1350.0, "summon": 900.0}
const FOG_ALPHA := 0.55

static var current: FogOfWar

var team := 0
var enabled := true
var texture: ImageTexture          # GRID x GRID, white = in vision (the ground shader)
var minimap_texture: ImageTexture  # the same, as a dark see-through overlay

var _img: Image
var _mini: Image
var _plane: MeshInstance3D
var _timer := 0.0
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	current = self
	_img = Image.create(GRID, GRID, false, Image.FORMAT_L8)
	_img.fill(Color.BLACK)
	texture = ImageTexture.create_from_image(_img)
	_mini = Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)
	_mini.fill(Color(0, 0, 0, 0.6))
	minimap_texture = ImageTexture.create_from_image(_mini)
	_build_plane()


func _exit_tree() -> void:
	if current == self:
		current = null


static func sight_of(u: Unit) -> float:
	var lol := 0.0
	if u is Champion:
		lol = SIGHT_LOL["champion"]
	elif u is Minion:
		lol = SIGHT_LOL["super"] if str((u as Minion).role) == "super" else SIGHT_LOL["minion"]
	elif u is Structure:
		lol = SIGHT_LOL["summon"] if not (u as Structure).is_structure() else SIGHT_LOL["structure"]
	return lol / float(GameData.rule("lol_units_per_meter", 75))


func set_team(t: int) -> void:
	team = t
	_timer = 0.0
	if enabled and is_inside_tree():
		update_vision()      # flip to the new team's view at once


func set_enabled(on: bool) -> void:
	enabled = on
	_plane.visible = on
	if not on:
		for n in get_tree().get_nodes_in_group("units"):
			(n as Unit).set_fog_hidden(false)
	_timer = 0.0


func _build_plane() -> void:
	_plane = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(MapLayout.MAP_SIZE, MapLayout.MAP_SIZE)
	_plane.mesh = q
	_plane.position = Vector3(0, 0.06, 0)
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D vision : filter_linear, repeat_disable;
uniform float fog_alpha = 0.55;
void fragment() {
	float v = texture(vision, UV).r;
	ALBEDO = vec3(0.02, 0.025, 0.05);
	ALPHA = (1.0 - v) * fog_alpha;
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("vision", texture)
	m.set_shader_parameter("fog_alpha", FOG_ALPHA)
	_plane.material_override = m
	add_child(_plane)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	update_vision()


## Recomputes what `team` can see.
func update_vision() -> void:
	_space = get_world_3d().direct_space_state
	var sources: Array[Unit] = []
	var others: Array[Unit] = []
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead:
			continue
		if u.team == team:
			# Our own units are never fogged (after a spectator switches teams,
			# the old enemies hidden a moment ago are now allies).
			u.set_fog_hidden(false)
			if sight_of(u) > 0.0:
				sources.append(u)
		else:
			others.append(u)
	_stamp(sources)
	for u in others:
		if u is Structure and (u as Structure).is_structure():
			u.set_fog_hidden(false)           # enemy structures are always visible
			continue
		u.set_fog_hidden(not can_see(u, sources))


func can_see(target: Unit, sources: Array[Unit]) -> bool:
	for s in sources:
		var r := sight_of(s)
		var d := Unit.flat_distance(s.global_position, target.global_position)
		if d > r:
			continue
		if d < 3.0 or _clear_line(s.global_position, target.global_position):
			return true
	return false


## Walls (and Timber! yews) block sight.
func _clear_line(a: Vector3, b: Vector3) -> bool:
	if _space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 1.2, b + Vector3.UP * 1.2, Unit.LAYER_WALLS)
	return _space.intersect_ray(q).is_empty()


## The fog texture: every source's sight circle stamped in (walls ignored here).
func _stamp(sources: Array[Unit]) -> void:
	_img.fill(Color.BLACK)
	_mini.fill(Color(0, 0, 0, 0.6))
	var cell := MapLayout.MAP_SIZE / float(GRID)
	var half := MapLayout.MAP_SIZE * 0.5
	for s in sources:
		var r := sight_of(s)
		var cx := (s.global_position.x + half) / cell
		var cz := (s.global_position.z + half) / cell
		var rc := r / cell
		for y in range(maxi(0, floori(cz - rc)), mini(GRID, ceili(cz + rc) + 1)):
			for x in range(maxi(0, floori(cx - rc)), mini(GRID, ceili(cx + rc) + 1)):
				var dx := float(x) + 0.5 - cx
				var dz := float(y) + 0.5 - cz
				if dx * dx + dz * dz <= rc * rc:
					_img.set_pixel(x, y, Color.WHITE)
					_mini.set_pixel(x, y, Color(0, 0, 0, 0))
	texture.update(_img)
	minimap_texture.update(_mini)
