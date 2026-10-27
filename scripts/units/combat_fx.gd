class_name CombatFx
extends RefCounted
## Attack and ability effects (purely visual; damage comes from the game
## rules). Melee attacks draw a swipe arc (slash), an overhead arc and ground
## impact (crush) or a thrust streak (stab); ranged and magic attacks fire a
## Projectile shaped like the weapon's ammo or spell. Abilities and item specs
## list their own effects under "fx" in the data (see docs/ABILITIES.md).

const ELEMENTS := {
	"ice": Color(0.6, 0.9, 1.0), "blood": Color(0.85, 0.08, 0.12), "shadow": Color(0.55, 0.25, 0.85),
	"smoke": Color(0.6, 0.6, 0.62), "fire": Color(1.0, 0.5, 0.12), "water": Color(0.25, 0.5, 1.0),
	"earth": Color(0.45, 0.7, 0.25), "air": Color(0.92, 0.95, 1.0), "venom": Color(0.35, 0.85, 0.25),
	"gold": Color(1.0, 0.82, 0.3), "holy": Color(1.0, 0.95, 0.7), "heal": Color(0.45, 1.0, 0.5),
	"lunar": Color(0.7, 0.8, 1.0), "dark": Color(0.25, 0.22, 0.28), "white": Color(1, 1, 1),
}

static var _materials: Dictionary = {}


## "#rrggbb", an element name ("ice", "blood"...), [r, g, b] or a Color.
static func color(v: Variant, fallback: Color = Color.WHITE) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	var s := str(v)
	if ELEMENTS.has(s):
		return ELEMENTS[s]
	if s.begins_with("#"):
		return Color.html(s)
	return fallback


static func material(c: Color, glow: bool = true) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), glow]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = m
	return m


## A fresh (unshared) material for an effect that fades out.
static func fade_material(c: Color, additive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func _mesh_node(parent: Node, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	return mi


static func _fade_free(node: Node3D, mat: StandardMaterial3D, duration: float, grow: Vector3 = Vector3.ONE) -> void:
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	if grow != Vector3.ONE:
		tw.tween_property(node, "scale", grow, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(node.queue_free)


# --- Basic attacks ---------------------------------------------------------------

## The visual for one basic attack. Ranged and magic projectiles are launched
## by Unit.perform_attack (they carry the damage); this draws melee swipes.
static func melee(attacker: Unit, t: Unit, fx: Dictionary) -> void:
	if not attacker.is_inside_tree() or not is_instance_valid(t):
		return
	var to := t.global_position - attacker.global_position
	to.y = 0.0
	var reach := clampf(to.length() - t.radius * 0.5, 0.9, 3.2) * float(fx.get("size", 1.0))
	var c := color(fx.get("color", ""), Color(1, 1, 1, 0.85))
	FxArc.spawn(attacker.get_parent(), attacker.global_position, to, str(fx.get("arc", "slash")), reach,
		Color(c.r, c.g, c.b, 0.85), float(fx.get("duration", 0.22)), bool(fx.get("flip", randf() < 0.5)))
	if str(fx.get("arc", "slash")) == "crush":
		ring(attacker.get_parent(), t.global_position, t.radius + 0.6, Color(c.r, c.g, c.b, 0.6), 0.25, 0.12)


# --- Building blocks -------------------------------------------------------------

## A short-lived glowing ball (spell trails, sparks).
static func puff(parent: Node, pos: Vector3, c: Color, size: float, life: float) -> void:
	if not Settings.particles_on():
		return
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2.0
	s.radial_segments = 8
	s.rings = 4
	var mat := fade_material(Color(c.r, c.g, c.b, 0.55), true)
	var mi := _mesh_node(parent, s, pos, mat)
	_fade_free(mi, mat, life, Vector3(0.2, 0.2, 0.2))


static func impact(parent: Node, pos: Vector3, kind: String, c: Color) -> void:
	match kind:
		"splash":
			var s := SphereMesh.new()
			s.radius = 0.35
			s.height = 0.7
			var mat := fade_material(Color(c.r, c.g, c.b, 0.7), true)
			_fade_free(_mesh_node(parent, s, pos, mat), mat, 0.3, Vector3(2.4, 2.4, 2.4))
		"dust":
			for i in 5:
				var p := pos + Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.3), randf_range(-0.4, 0.4))
				puff(parent, p, Color(0.62, 0.56, 0.48), 0.18, 0.45)
		_:
			sparks(parent, pos, c, 7, 0.3)


static func sparks(parent: Node, pos: Vector3, c: Color, count: int, life: float) -> void:
	for i in Settings.particle_count(count):
		var b := BoxMesh.new()
		b.size = Vector3(0.07, 0.07, 0.07)
		var mat := fade_material(Color(c.r, c.g, c.b, 1.0), true)
		var mi := _mesh_node(parent, b, pos, mat)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized()
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", pos + dir * randf_range(0.5, 1.1), life).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, life)
		tw.chain().tween_callback(mi.queue_free)


## An expanding ring flat on the ground.
static func ring(parent: Node, pos: Vector3, radius: float, c: Color, duration: float, thickness: float = 0.15) -> void:
	var t := TorusMesh.new()
	t.inner_radius = maxf(0.01, 1.0 - thickness)
	t.outer_radius = 1.0
	t.rings = 40
	t.ring_segments = 4
	var mat := fade_material(Color(c.r, c.g, c.b, c.a if c.a < 1.0 else 0.8), true)
	var mi := _mesh_node(parent, t, Vector3(pos.x, 0.12, pos.z), mat)
	mi.scale = Vector3(radius * 0.35, 0.3, radius * 0.35)
	_fade_free(mi, mat, duration, Vector3(radius, 0.3, radius))


## A spell explosion over an area: dome, ground ring and sparks. Ice adds
## shards, fire adds embers.
static func burst(parent: Node, pos: Vector3, radius: float, c: Color, element: String = "") -> void:
	var d := SphereMesh.new()
	d.radius = 1.0
	d.height = 1.0
	d.is_hemisphere = true
	var mat := fade_material(Color(c.r, c.g, c.b, 0.45), true)
	var dome := _mesh_node(parent, d, Vector3(pos.x, 0.05, pos.z), mat)
	dome.scale = Vector3.ONE * radius * 0.3
	_fade_free(dome, mat, 0.45, Vector3.ONE * radius)
	ring(parent, pos, radius, c, 0.5, 0.1)
	sparks(parent, pos + Vector3.UP * 0.6, c, 10, 0.45)
	if element == "ice":
		for i in 8:
			var a := TAU * float(i) / 8.0 + randf() * 0.4
			var shard := PrismMesh.new()
			shard.size = Vector3(0.35, randf_range(0.7, 1.4), 0.35)
			var smat := fade_material(Color(0.75, 0.95, 1.0, 0.85))
			var at := pos + Vector3(cos(a), 0.0, sin(a)) * radius * randf_range(0.3, 0.8)
			var m := _mesh_node(parent, shard, Vector3(at.x, 0.4, at.z), smat)
			m.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
			m.scale = Vector3(1, 0.1, 1)
			var tw := m.create_tween()
			tw.tween_property(m, "scale", Vector3.ONE, 0.12)
			tw.tween_interval(0.45)
			tw.tween_property(smat, "albedo_color:a", 0.0, 0.3)
			tw.tween_callback(m.queue_free)


## Rising sparkles around a unit (heals, buffs, potions), following it.
static func glow(unit: Node3D, c: Color, duration: float = 0.9) -> void:
	if not is_instance_valid(unit) or not unit.is_inside_tree():
		return
	if not Settings.particles_on():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = Settings.particle_count(18)
	p.lifetime = duration
	p.explosiveness = 0.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 0.1
	p.emission_ring_radius = 0.7
	p.emission_ring_inner_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 10.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var q := SphereMesh.new()
	q.radius = 0.07
	q.height = 0.14
	q.radial_segments = 6
	q.rings = 3
	q.material = material(c, true)
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	unit.add_child(p)
	p.position = Vector3(0, 0.3, 0)
	p.emitting = true
	unit.get_tree().create_timer(duration + 0.3, false).timeout.connect(p.queue_free)
	ring(unit.get_parent(), unit.global_position, 1.1, Color(c.r, c.g, c.b, 0.6), duration * 0.6, 0.08)


## A translucent ice block around a frozen unit (barrages, blitz, freezes).
static func ice_block(unit: Node3D, duration: float) -> void:
	if not is_instance_valid(unit) or not unit.is_inside_tree():
		return
	var h := 2.0
	if unit is Unit:
		h = (unit as Unit).visual_height() * 0.9
	var b := BoxMesh.new()
	b.size = Vector3(1.2, h, 1.2)
	var mat := fade_material(Color(0.7, 0.92, 1.0, 0.4))
	mat.vertex_color_use_as_albedo = false
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = Vector3(0, h * 0.5, 0)
	mi.rotation.y = randf() * TAU
	unit.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_interval(maxf(0.2, duration - 0.3))
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(mi.queue_free)


## A heavy ground impact: shockwave, dust and debris.
static func slam(parent: Node, pos: Vector3, radius: float, c: Color) -> void:
	ring(parent, pos, radius, Color(c.r, c.g, c.b, 0.85), 0.35, 0.22)
	ring(parent, pos, radius * 0.6, Color(1, 1, 1, 0.5), 0.25, 0.1)
	impact(parent, pos + Vector3.UP * 0.2, "dust", c)
	sparks(parent, pos + Vector3.UP * 0.3, c, 8, 0.35)


## A bright streak between two points (dashes, lightning, beams).
static func streak(parent: Node, from: Vector3, to: Vector3, c: Color, width: float = 0.35, duration: float = 0.3) -> void:
	var d := to - from
	d.y = 0.0
	if d.length() < 0.1:
		return
	var q := BoxMesh.new()
	q.size = Vector3(width, 0.05, d.length())
	var mat := fade_material(Color(c.r, c.g, c.b, 0.65), true)
	var mi := _mesh_node(parent, q, (from + to) * 0.5 + Vector3.UP * 0.9, mat)
	mi.look_at(Vector3(to.x, mi.global_position.y, to.z), Vector3.UP)
	_fade_free(mi, mat, duration, Vector3(0.2, 1.0, 1.0))


# --- Ability effects ---------------------------------------------------------------

## Plays an ability's (or item spec's) "fx" list. Each entry:
##   kind     swipe | multi_slash | projectile | volley | burst | ring | glow |
##            ice_block | slam | streak
##   at       target (default for target_unit casts) | point | self
##   color    element name or "#rrggbb"; radius/size/count/delay as needed
static func ability(caster: Unit, ab: Dictionary, target: Unit, point: Vector3) -> void:
	if not caster.is_inside_tree():
		return
	for f in ab.get("fx", []):
		var e: Dictionary = f
		var delay := float(e.get("delay", 0.0))
		if delay > 0.0:
			var c_ref: WeakRef = weakref(caster)
			var t_ref: WeakRef = weakref(target) if target != null else null
			caster.get_tree().create_timer(delay, false).timeout.connect(func() -> void:
				var c: Unit = c_ref.get_ref()
				var t: Unit = t_ref.get_ref() if t_ref != null else null
				if c != null and c.is_inside_tree():
					_one(c, ab, e, t, point))
		else:
			_one(caster, ab, e, target, point)


static func _area_radius(ab: Dictionary, fallback: float) -> float:
	for e in ab.get("effects", []):
		var a: Dictionary = e.get("area", {})
		if a.has("radius"):
			return float(a["radius"])
	return fallback


static func _one(caster: Unit, ab: Dictionary, e: Dictionary, target: Unit, point: Vector3) -> void:
	var parent := caster.get_parent()
	var valid_target := target != null and is_instance_valid(target) and not target.is_dead and target != caster
	var default_at := "target" if valid_target else ("point" if str(ab.get("cast", "")) == "point" else "self")
	var at_kind := str(e.get("at", default_at))
	var at := caster.global_position
	var at_unit: Node3D = caster
	if at_kind == "target" and valid_target:
		at = target.global_position
		at_unit = target
	elif at_kind == "point" or (at_kind == "target" and not valid_target and str(ab.get("cast", "")) == "point"):
		at = point
		at_unit = null
	var c := color(e.get("color", "white"))
	var radius := float(e.get("radius", _area_radius(ab, 2.0)))
	match str(e.get("kind", "")):
		"swipe":
			var dir := (at if at_unit != caster else caster.global_position + caster.forward()) - caster.global_position
			dir.y = 0.0
			if dir.length() < 0.1:
				dir = caster.forward()
			FxArc.spawn(parent, caster.global_position, dir, str(e.get("arc", "slash")), float(e.get("size", radius)),
				Color(c.r, c.g, c.b, 0.9), float(e.get("duration", 0.3)), bool(e.get("flip", false)), float(e.get("sweep", 150.0)))
		"multi_slash":
			var n := int(e.get("count", 3))
			for i in n:
				var dir2 := at - caster.global_position
				dir2.y = 0.0
				if dir2.length() < 0.1:
					dir2 = caster.forward()
				var arc := "stab" if i % 3 == 2 else "slash"
				var cr: WeakRef = weakref(caster)
				var col := Color(c.r, c.g, c.b, 0.9)
				var reach := clampf(dir2.length(), 1.0, 2.6)
				caster.get_tree().create_timer(0.09 * i, false).timeout.connect(func() -> void:
					var cc: Unit = cr.get_ref()
					if cc != null and cc.is_inside_tree():
						FxArc.spawn(cc.get_parent(), cc.global_position, dir2, arc, reach, col, 0.2, i % 2 == 1))
		"projectile":
			var pf := e.duplicate()
			pf.erase("kind")
			if not pf.has("color"):
				pf.erase("color")
			if at_unit != null and at_unit != caster and at_unit is Unit:
				Projectile.launch(caster, at_unit as Unit, pf, Callable())
			else:
				Projectile.launch_to_point(caster, at, pf)
		"volley":
			var n2 := int(e.get("count", 5))
			var dir3 := point - caster.global_position
			dir3.y = 0.0
			var length := float(e.get("length", dir3.length()))
			var side := dir3.normalized().cross(Vector3.UP)
			for i in n2:
				var spread := (float(i) - (n2 - 1) * 0.5) * float(e.get("spread", 0.5))
				var dest := caster.global_position + dir3.normalized() * length + side * spread
				var pf2 := {"shape": str(e.get("shape", "arrow"))}
				if e.has("color"):
					pf2["color"] = e["color"]
				Projectile.launch_to_point(caster, dest, pf2, caster.global_position + Vector3.UP * 1.3 + side * spread * 0.3)
		"burst":
			burst(parent, at, radius, c, str(e.get("color", "")))
		"ring":
			ring(parent, at, radius, Color(c.r, c.g, c.b, 0.8), float(e.get("duration", 0.6)), float(e.get("thickness", 0.12)))
		"glow":
			glow(at_unit if at_unit != null else caster, c, float(e.get("duration", 0.9)))
		"ice_block":
			if at_unit != null:
				ice_block(at_unit, float(e.get("duration", 1.5)))
			elif at_kind == "point":
				for u in AbilityRunner.collect_area(caster, {"shape": "circle", "radius": radius, "center": "point"}, null, point, false):
					ice_block(u, float(e.get("duration", 1.5)))
		"slam":
			slam(parent, at, radius, c)
		"streak":
			streak(parent, caster.global_position, at, c, float(e.get("width", 0.35)), float(e.get("duration", 0.35)))
		"sparks":
			sparks(parent, at + Vector3.UP, c, int(e.get("count", 10)), 0.4)


## A swipe arc drawn as a glowing ribbon that sweeps and fades.
class FxArc extends MeshInstance3D:
	var origin := Vector3.ZERO
	var fwd := Vector3.FORWARD
	var mode := "slash"
	var reach := 1.5
	var col := Color.WHITE
	var duration := 0.22
	var flip := false
	var sweep_deg := 140.0
	var _t := 0.0
	var _im := ImmediateMesh.new()

	static func spawn(parent: Node, at: Vector3, dir: Vector3, p_mode: String, p_reach: float, c: Color,
			p_duration: float, p_flip: bool, p_sweep: float = 140.0) -> void:
		var a := FxArc.new()
		a.origin = at
		a.fwd = dir.normalized()
		a.mode = p_mode
		a.reach = p_reach
		a.col = c
		a.duration = p_duration
		a.flip = p_flip
		a.sweep_deg = p_sweep
		a.top_level = true
		a.mesh = a._im
		a.material_override = CombatFx.fade_material(Color(1, 1, 1, 1), true)
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(a)
		a.global_transform = Transform3D.IDENTITY
		a._draw(0.0)

	func _process(delta: float) -> void:
		_t += delta
		if _t >= duration:
			queue_free()
			return
		_draw(_t / duration)

	func _point(u: float, r: float) -> Vector3:
		var side := fwd.cross(Vector3.UP).normalized() * (-1.0 if flip else 1.0)
		var sweep := deg_to_rad(sweep_deg)
		match mode:
			"crush":
				# Overhead: from above and behind the shoulder down to the ground in front.
				var a := lerpf(-0.3, PI * 0.62, u)
				return origin + Vector3.UP * 0.4 + (fwd * sin(a) + Vector3.UP * cos(a)) * r * 1.1 + side * 0.15
			"stab":
				return origin + Vector3.UP * 1.1 + fwd * lerpf(0.3, r + 0.4, u) + side * (r - reach) * 0.15
		var b := lerpf(-sweep * 0.5, sweep * 0.5, u)
		return origin + Vector3.UP * (1.1 + 0.25 * lerpf(1.0, -1.0, u)) + (fwd * cos(b) + side * sin(b)) * r

	func _draw(progress: float) -> void:
		_im.clear_surfaces()
		var head := clampf(progress * 1.6, 0.0, 1.0)
		var tail := clampf(progress * 1.6 - 0.55, 0.0, 1.0)
		if head - tail < 0.01:
			return
		var fade := 1.0 - clampf((progress - 0.6) / 0.4, 0.0, 1.0)
		var width := 0.3 if mode != "stab" else 0.12
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var steps := 18
		for i in steps + 1:
			var u := lerpf(tail, head, float(i) / float(steps))
			var k := float(i) / float(steps)        # 0 at the tail, 1 at the leading edge
			var c := Color(col.r, col.g, col.b, col.a * k * fade)
			var w := width * (0.3 + 0.7 * k)
			_im.surface_set_color(c)
			_im.surface_add_vertex(_point(u, reach))
			_im.surface_set_color(c)
			if mode == "stab":
				_im.surface_add_vertex(_point(u, reach) + Vector3.UP * w)
			else:
				_im.surface_add_vertex(_point(u, reach - w))
		_im.surface_end()
