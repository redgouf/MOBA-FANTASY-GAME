class_name TeleportFx
extends Node3D
## The home teleport (recall), played over the 8 s channel: the champion
## spends most of it looking around sneakily (OSRS "sneaky look around",
## glancing left and right), then for the last moments casts the normal OSRS
## teleport (animation 714 with its teleport graphics), and arrives at the
## fountain with the landing animation (715). models.json "teleport" names
## the clips and the graphic; without the pack a swirl of light and two
## stand-in arms play instead.
## Purely visual: Champion's recall timer decides when the teleport happens.

const CAST_TIME := 1.8           # the teleport cast at the end of the channel
const GLANCE_PERIOD := 2.6       # one look left and right
const LOOK_ANGLE := deg_to_rad(50.0)
const CAST_CLIP := "a714"
const ARRIVE_CLIP := "a715"
const LOOK_CLIP := "a10684"
const SWIRL := Color(0.78, 0.88, 1.0)

var champ: Champion
var elapsed := 0.0
var look_end := 1.5              # when the looking around stops and the cast starts
var _base_yaw := 0.0
var _cast_started := false
var _arms: Array[MeshInstance3D] = []
var _swirl: CPUParticles3D
var _circle: MeshInstance3D


## Starts the effect on a champion (replacing any running one).
static func begin(c: Champion) -> TeleportFx:
	stop(c)
	if not c.is_inside_tree():
		return null
	var fx := TeleportFx.new()
	fx.name = "TeleportFx"
	fx.champ = c
	c.add_child(fx)
	return fx


## Cancels the effect (recall interrupted) and puts the champion back as it was.
static func stop(c: Champion) -> void:
	var old := c.get_node_or_null("TeleportFx") as TeleportFx
	if old != null:
		old._restore()
		old.queue_free()


## The teleport went off: a flash where the champion stood and the landing
## animation at `to`.
static func finish(c: Champion, from: Vector3) -> void:
	var fx := c.get_node_or_null("TeleportFx") as TeleportFx
	if fx != null:
		fx._restore()
		fx.queue_free()
	if not c.is_inside_tree():
		return
	var parent := c.get_parent()
	CombatFx.burst(parent, from + Vector3.UP * 0.2, 1.2, SWIRL, "air")
	CombatFx.sparks(parent, from + Vector3.UP * 1.2, SWIRL, 12, 0.5)
	CombatFx.ring(parent, c.global_position, 1.6, Color(SWIRL.r, SWIRL.g, SWIRL.b, 0.7), 0.6, 0.1)
	CombatFx.glow(c, SWIRL, 0.8)
	if c.osrs != null:
		c.osrs.play(_clip("arrive_clip", ARRIVE_CLIP), 1.2)


func _ready() -> void:
	_base_yaw = champ.rotation.y
	look_end = maxf(0.5, champ.recall_timer - CAST_TIME) if champ.recall_timer > 0.0 else 1.5
	if champ.osrs == null:
		_build_arms()


func _process(delta: float) -> void:
	if not is_instance_valid(champ) or champ.is_dead or not champ.is_recalling():
		_restore()
		queue_free()
		return
	elapsed += delta
	if elapsed < look_end:
		# Sneak a look around: glance left, then right, again and again.
		if champ.osrs != null and not champ.osrs.is_busy():
			champ.osrs.play(_clip("look_clip", LOOK_CLIP), minf(2.0, look_end - elapsed))
		var t := fmod(elapsed, GLANCE_PERIOD) / GLANCE_PERIOD
		var yaw := 0.0
		if t < 0.3:
			yaw = LOOK_ANGLE * _ease(t / 0.3)
		elif t < 0.7:
			yaw = LOOK_ANGLE * (1.0 - 2.0 * _ease((t - 0.3) / 0.4))
		else:
			yaw = -LOOK_ANGLE * (1.0 - _ease((t - 0.7) / 0.3))
		champ.rotation.y = _base_yaw + yaw
		return
	champ.rotation.y = _base_yaw
	if not _cast_started:
		_start_cast()
	# Arms out (whitebox stand-in for the OSRS cast pose).
	var k := clampf((elapsed - look_end) / 0.35, 0.0, 1.0)
	for i in _arms.size():
		var side := -1.0 if i == 0 else 1.0
		_arms[i].rotation = Vector3(0.0, 0.0, side * lerpf(0.15, 1.9, _ease(k)))
	if _circle != null:
		_circle.rotate_y(delta * 2.2)


func _start_cast() -> void:
	_cast_started = true
	if champ.osrs != null:
		var left := maxf(0.6, champ.recall_timer)
		champ.osrs.play(_clip("cast_clip", CAST_CLIP), minf(1.58, left))
	for a in _arms:
		a.visible = true
	# The OSRS teleport graphic, when the pack has it.
	var gfx := int(OsrsModels.config().get("teleport", {}).get("cast_gfx", 0)) if champ.osrs != null else 0
	if OsrsGfx.spawn(champ.get_parent(), gfx, champ.global_position, champ) != null:
		return
	# The swirl of light rising around the caster (OSRS teleport gfx).
	_swirl = CPUParticles3D.new()
	_swirl.amount = 70
	_swirl.lifetime = 1.3
	_swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_swirl.emission_ring_axis = Vector3.UP
	_swirl.emission_ring_height = 0.1
	_swirl.emission_ring_radius = 0.75
	_swirl.emission_ring_inner_radius = 0.55
	_swirl.direction = Vector3.UP
	_swirl.spread = 8.0
	_swirl.gravity = Vector3(0, 1.2, 0)
	_swirl.initial_velocity_min = 1.0
	_swirl.initial_velocity_max = 1.8
	_swirl.orbit_velocity_min = 0.6
	_swirl.orbit_velocity_max = 0.9
	_swirl.scale_amount_min = 0.5
	_swirl.scale_amount_max = 1.0
	var q := SphereMesh.new()
	q.radius = 0.1
	q.height = 0.2
	q.radial_segments = 6
	q.rings = 3
	q.material = CombatFx.material(SWIRL, true)
	_swirl.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_swirl.color_ramp = g
	add_child(_swirl)
	_swirl.position = Vector3(0, 0.15, 0)
	_swirl.emitting = true
	# A glowing rune circle on the ground, slowly turning.
	var t := TorusMesh.new()
	t.inner_radius = 0.86
	t.outer_radius = 1.0
	t.rings = 40
	t.ring_segments = 4
	_circle = MeshInstance3D.new()
	_circle.mesh = t
	_circle.material_override = CombatFx.fade_material(Color(SWIRL.r, SWIRL.g, SWIRL.b, 0.7), true)
	_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_circle.scale = Vector3(1.1, 0.3, 1.1)
	add_child(_circle)
	_circle.position = Vector3(0, 0.1, 0)
	CombatFx.ring(champ.get_parent(), champ.global_position, 1.4, Color(SWIRL.r, SWIRL.g, SWIRL.b, 0.6), 0.5, 0.1)


## Whitebox champions have no arms; two short ones appear for the cast pose.
func _build_arms() -> void:
	var h := champ.visual_height()
	var col := Unit.team_color(champ.team).lerp(Color.WHITE, 0.25)
	for side in [-1.0, 1.0]:
		var pivot := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.16, 0.75, 0.16)
		pivot.mesh = b
		pivot.material_override = CombatFx.material(col, false)
		# Pivot at the shoulder: the box hangs from it.
		var holder := Node3D.new()
		add_child(holder)
		holder.position = Vector3(0.0, h * 0.78, 0.0)
		holder.rotation.y = 0.0
		holder.add_child(pivot)
		pivot.position = Vector3(side * (champ.radius + 0.05), 0.0, 0.0)
		pivot.visible = false
		var arm := MeshInstance3D.new()
		arm.mesh = b
		arm.material_override = pivot.material_override
		pivot.add_child(arm)
		arm.position = Vector3(0.0, -0.36, 0.0)
		pivot.mesh = null
		_arms.append(pivot)


func _restore() -> void:
	if is_instance_valid(champ) and elapsed < look_end:
		champ.rotation.y = _base_yaw
	for a in _arms:
		if is_instance_valid(a):
			a.visible = false
	if _swirl != null:
		_swirl.emitting = false


static func _clip(key: String, fallback: String) -> String:
	return str(OsrsModels.config().get("teleport", {}).get(key, fallback))


static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
