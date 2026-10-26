class_name AbilityIndicator
extends MeshInstance3D
## League-style ground indicators for the ability being aimed: the range ring,
## then the ability's shape (line, cone, circle, dash arrow or target ring).
## Timber! shows where the yew will be planted, or, while the cursor is on one
## of your yews, the path it will fall along: toward the cursor's side of the
## trunk, with the spot you will walk to.
## Abilities that drop something at a spot are drawn on the cursor even past
## their range (the range ring stays): you walk into range, then it goes off.
## Redrawn every frame by PlayerController while aiming.

const Y := 0.12
const RANGE := Color(0.88, 0.94, 1.0, 0.5)
const FILL := Color(0.35, 0.65, 1.0, 0.2)
const EDGE := Color(0.6, 0.82, 1.0, 0.9)
const FALL_FILL := Color(1.0, 0.72, 0.2, 0.28)
const FALL_EDGE := Color(1.0, 0.85, 0.35, 0.95)
const PLANT_FILL := Color(0.35, 0.9, 0.35, 0.3)
const PLANT_EDGE := Color(0.45, 1.0, 0.45, 0.9)
const TREE_MARK := Color(1.0, 0.85, 0.35, 0.45)
const WARN := Color(1.0, 0.35, 0.25, 0.9)
const ENEMY := Color(1.0, 0.3, 0.25, 0.95)
const ALLY := Color(0.35, 1.0, 0.45, 0.95)
const MAX_DRAW_LENGTH := 30.0
const STAND := Color(0.55, 1.0, 0.6, 0.95)

## What is shown right now: "", "plant", "chop", "point", "target" (for tests and the HUD).
var mode := ""
var chop_tree: PlantedTree
var fall_dir := Vector3.ZERO

var _im: ImmediateMesh
var _verts := PackedVector3Array()
var _colors := PackedColorArray()


func _ready() -> void:
	top_level = true
	_im = ImmediateMesh.new()
	mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = 1
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func clear() -> void:
	mode = ""
	chop_tree = null
	if _im != null:
		_im.clear_surfaces()
	visible = false


## Draws the indicator for `key` ("q".."r" or "item:<id>") with the cursor at
## `cursor`, `hovered` the unit under it and `tree` the caster's yew under it.
## `fall` is the direction chosen for a chop (ZERO: away from the caster).
func update_for(c: Champion, key: String, cursor: Vector3, hovered: Unit, tree: PlantedTree, fall: Vector3 = Vector3.ZERO) -> void:
	_verts.clear()
	_colors.clear()
	mode = ""
	chop_tree = null
	var ab := c.get_action(key)
	if not ab.is_empty():
		if ab.has("planter"):
			_planter(c, ab, cursor, tree, fall)
		else:
			match str(ab.get("cast", "self")):
				"target_unit":
					_target_unit(c, ab, hovered)
				"point":
					_point(c, ab, cursor, hovered)
	_flush()


func _planter(c: Champion, ab: Dictionary, cursor: Vector3, tree: PlantedTree, fall: Vector3 = Vector3.ZERO) -> void:
	var cfg: Dictionary = ab.get("planter", {})
	var size := c.planter_fall_size(ab)
	var replace: PlantedTree = null
	if tree != null:
		mode = "chop"
		chop_tree = tree
		var at := tree.global_position
		var chosen := fall.length() > 0.01
		fall_dir = fall.normalized() if chosen else PlantedTree.fall_direction(c.global_position, at, c.forward())
		rect(at, fall_dir, size.x, size.y, FALL_FILL, FALL_EDGE)
		arrow(at + fall_dir * (tree.block_radius + 0.4), at + fall_dir * (size.x - 0.3), 0.35, FALL_EDGE)
		ring(at, tree.block_radius + 0.3, 0.14, FALL_EDGE)
		if chosen:
			# You walk to the far side of the trunk, so it falls this way.
			var stand := c.tree_stand_spot(tree, fall_dir, cfg)
			disc(stand, 0.45, STAND)
			ring(stand, 0.7, 0.1, STAND)
			arrow(stand, at - fall_dir * (tree.block_radius + 0.1), 0.3, STAND)
		elif c.flat_distance_to(tree) > c.chop_range(cfg):
			# Out of reach: you'll walk to this ring first, then chop.
			ring(at, c.chop_range(cfg), 0.06, RANGE)
	else:
		mode = "plant"
		ring(c.global_position, c.ability_range(ab), 0.08, RANGE)
		var spot := c.plant_spot(cursor, ab, false)
		_reach_line(c, ab, spot)
		var r := float(cfg.get("block_radius", 0.8))
		disc(spot, r, PLANT_FILL)
		ring(spot, r + 0.15, 0.1, PLANT_EDGE)
		replace = c.tree_to_replace(cfg)
		if replace != null:
			ring(replace.global_position, replace.block_radius + 0.35, 0.16, WARN)
	# Your other yews: hover one to see where it would fall.
	for t in c.standing_trees():
		if t != tree and t != replace:
			ring(t.global_position, t.block_radius + 0.3, 0.07, TREE_MARK)


func _target_unit(c: Champion, ab: Dictionary, hovered: Unit) -> void:
	mode = "target"
	ring(c.global_position, c.ability_range(ab) + c.radius, 0.08, RANGE)
	if hovered == null or hovered.is_dead:
		return
	var want_ally := bool(ab.get("target_ally", false))
	var ok := hovered.team == c.team if want_ally else (hovered.team != c.team and hovered.is_damageable())
	if ok and (hovered != c or bool(ab.get("allow_self", false))):
		ring(hovered.global_position, hovered.radius + 0.4, 0.14, ALLY if want_ally else ENEMY)


func _point(c: Champion, ab: Dictionary, cursor: Vector3, hovered: Unit) -> void:
	mode = "point"
	var origin := c.global_position
	var max_range := c.ability_range(ab)
	if max_range > 0.0 and max_range <= MAX_DRAW_LENGTH:
		ring(origin, max_range, 0.08, RANGE)
	var d := cursor - origin
	d.y = 0.0
	var placed := c.is_placed_ability(ab)
	var p := origin + (d.limit_length(max_range) if max_range > 0.0 and not placed else d)
	if placed:
		_reach_line(c, ab, p)
	var dir := d.normalized() if d.length() > 0.01 else c.forward()
	var drawn := {}
	for e in ab.get("effects", []):
		var area: Dictionary = e.get("area", {})
		if area.is_empty():
			if str(e.get("type", "")) == "dash" and str(e.get("to", "point")) == "point":
				var dist := minf(p.distance_to(origin), float(e.get("distance", 999.0)))
				arrow(origin, origin + dir * dist, 0.5, EDGE)
				drawn["dash"] = true
			continue
		var tag := str(area)
		if drawn.has(tag):
			continue
		drawn[tag] = true
		match str(area.get("shape", "circle")):
			"line":
				var o := p if str(area.get("origin", "self")) == "point" else origin
				rect(o, dir, minf(float(area.get("length", 10.0)), MAX_DRAW_LENGTH), float(area.get("width", 2.0)), FILL, EDGE)
			"cone":
				cone(origin, dir, float(area.get("radius", 4.0)), float(area.get("angle", 90.0)), FILL, EDGE)
			_:
				var center := p
				match str(area.get("center", "point")):
					"self":
						center = origin
					"target":
						center = hovered.global_position if hovered != null and not hovered.is_dead else p
				var r := float(area.get("radius", 3.0))
				disc(center, r, FILL)
				ring(center, r, 0.1, EDGE)
	if drawn.is_empty():
		ring(p, 0.6, 0.1, EDGE)


## Past the range: a thin line from the range edge to the spot, a marker at the
## edge where you will stop to cast (shown only when the spot is out of reach).
func _reach_line(c: Champion, ab: Dictionary, spot: Vector3) -> void:
	var from := c.global_position
	var d := spot - from
	d.y = 0.0
	var reach := c.ability_range(ab)
	if d.length() <= reach + 0.05:
		return
	var dir := d.normalized()
	var edge := from + dir * reach
	rect(edge, dir, d.length() - reach, 0.12, RANGE, RANGE)
	disc(edge, 0.3, STAND)


# --- Primitives (flat on the ground) ----------------------------------------

func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for v in [a, b, c]:
		_verts.append(Vector3(v.x, Y, v.z))
		_colors.append(col)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(a, b, c, col)
	_tri(a, c, d, col)


func ring(center: Vector3, r: float, width: float, col: Color, segments: int = 64) -> void:
	var inner := maxf(0.0, r - width * 0.5)
	var outer := r + width * 0.5
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		quad(center + d0 * inner, center + d0 * outer, center + d1 * outer, center + d1 * inner, col)


func disc(center: Vector3, r: float, col: Color, segments: int = 40) -> void:
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		_tri(center, center + Vector3(cos(a0), 0.0, sin(a0)) * r, center + Vector3(cos(a1), 0.0, sin(a1)) * r, col)


## A filled rectangle `length` long and `width` wide from `origin` along `dir`, outlined.
func rect(origin: Vector3, dir: Vector3, length: float, width: float, fill: Color, edge: Color) -> void:
	var side := dir.cross(Vector3.UP).normalized() * width * 0.5
	var end := origin + dir * length
	quad(origin - side, origin + side, end + side, end - side, fill)
	var e := 0.08
	var s := side.normalized() * e
	quad(origin - side, origin - side + s, end - side + s, end - side, edge)
	quad(origin + side - s, origin + side, end + side, end + side - s, edge)
	quad(end - side, end + side, end + side - dir * e, end - side - dir * e, edge)
	quad(origin - side, origin + side, origin + side + dir * e, origin - side + dir * e, edge)


func cone(origin: Vector3, dir: Vector3, r: float, angle_deg: float, fill: Color, edge: Color, segments: int = 24) -> void:
	var half := deg_to_rad(angle_deg) * 0.5
	var base := atan2(dir.z, dir.x)
	var prev := Vector3.ZERO
	for i in segments + 1:
		var a := base - half + 2.0 * half * float(i) / float(segments)
		var p := origin + Vector3(cos(a), 0.0, sin(a)) * r
		if i > 0:
			_tri(origin, prev, p, fill)
			var pin := origin + (prev - origin) * (1.0 - 0.1 / r)
			var qin := origin + (p - origin) * (1.0 - 0.1 / r)
			quad(pin, prev, p, qin, edge)
		prev = p
	for a in [base - half, base + half]:
		var tip := origin + Vector3(cos(a), 0.0, sin(a)) * r
		var side := (tip - origin).cross(Vector3.UP).normalized() * 0.04
		quad(origin - side, origin + side, tip + side, tip - side, edge)


func arrow(from: Vector3, to: Vector3, width: float, col: Color) -> void:
	var d := to - from
	d.y = 0.0
	if d.length() < 0.1:
		return
	var dir := d.normalized()
	var head := minf(1.0, d.length() * 0.4)
	var side := dir.cross(Vector3.UP).normalized()
	var neck := to - dir * head
	quad(from - side * width * 0.25, from + side * width * 0.25, neck + side * width * 0.25, neck - side * width * 0.25, col)
	_tri(neck - side * width, neck + side * width, to, col)


func _flush() -> void:
	_im.clear_surfaces()
	if _verts.is_empty():
		visible = false
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _verts.size():
		_im.surface_set_color(_colors[i])
		_im.surface_add_vertex(_verts[i])
	_im.surface_end()
	visible = true
