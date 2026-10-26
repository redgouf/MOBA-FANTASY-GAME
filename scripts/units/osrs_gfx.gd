class_name OsrsGfx
extends Node3D
## OSRS spell and spec graphics ("spot anims": Ice Barrage's ice block, the
## teleport swirl, the dragon claws' slashes) from the private model pack,
## played once where a spell is cast, flies or lands. Each one is a model
## with its own animation ("play"), scaled like the champions.
##
## data/models.json gives an ability or spec its graphics:
##   "gfx": {"cast": 252, "travel": 368, "impact": 369, "area": true}
## cast: on the caster as it casts; travel: flies from the caster to the
## target or point; impact: where it lands (on every enemy in the ability's
## area when "area" is set). A form-switching champion can key the gfx by
## form ("magic": {...}, "ranged": {...}).

const TRAVEL_SPEED := 16.0       # metres a second
const DEFAULT_LIFE := 1.4        # seconds, for graphics without an animation

var _life := DEFAULT_LIFE
var _follow: Node3D
var _offset := Vector3.ZERO


static var _glow: StandardMaterial3D


static func glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.vertex_color_use_as_albedo = true
		_glow.vertex_color_is_srgb = true
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glow.albedo_color = Color(1, 1, 1, 0.85)
	return _glow


## True when the pack has this graphic.
static func has(id: int) -> bool:
	return id > 0 and OsrsModels.available() and OsrsModels.manifest().get("spotanims", {}).has(str(id))


## Plays graphic `id` once at `at` (or riding on `follow`); null without it.
static func spawn(parent: Node, id: int, at: Vector3, follow: Node3D = null, loop := false) -> OsrsGfx:
	if not has(id) or parent == null:
		return null
	var info: Dictionary = OsrsModels.manifest()["spotanims"][str(id)]
	var ps := OsrsModels.scene(str(info.get("file", "")))
	if ps == null:
		return null
	var g := OsrsGfx.new()
	g.name = "Gfx%d" % id
	var root := ps.instantiate() as Node3D
	g.add_child(root)
	OsrsModels.apply_material(root)
	# Spell graphics glow: OSRS fades them in and out through their animation
	# (which the pack can't carry), so they're drawn additive and unlit here.
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = glow_material()
	g.scale = Vector3.ONE * float(OsrsModels.config().get("player_scale", 1.4))
	g._follow = follow
	parent.add_child(g)
	g.global_position = at
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var ap := players[0] as AnimationPlayer
		if ap.has_animation("play"):
			var anim := ap.get_animation("play")
			anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			ap.play("play")
			g._life = maxf(0.3, anim.length)
	if loop:
		g._life = INF
	return g


## Plays an ability's graphics: cast on the caster, then the travel graphic
## flies to the target (or point) and the impact plays where it lands.
static func ability(caster: Unit, gfx: Dictionary, target: Unit, point: Vector3, radius: float = 0.0) -> void:
	if caster == null or not caster.is_inside_tree():
		return
	var parent := caster.get_parent()
	var cast_id := int(gfx.get("cast", 0))
	if cast_id > 0:
		spawn(parent, cast_id, caster.global_position, caster)
	var travel_id := int(gfx.get("travel", 0))
	var impact_id := int(gfx.get("impact", 0))
	if travel_id <= 0 and impact_id <= 0:
		return
	var has_target := target != null and is_instance_valid(target) and target != caster and not target.is_dead
	var dest := target.global_position if has_target else point
	if not has_target and point == Vector3.ZERO:
		dest = caster.global_position
	var area := bool(gfx.get("area", false))
	var land := func() -> void:
		if impact_id <= 0 or not is_instance_valid(caster) or not caster.is_inside_tree():
			return
		var spots: Array[Node3D] = []
		var at := target.global_position if has_target and is_instance_valid(target) else dest
		if area and radius > 0.0:
			for n in caster.get_tree().get_nodes_in_group("units"):
				var u := n as Unit
				if u != null and not u.is_dead and u.team != caster.team and u.global_position.distance_to(at) <= radius:
					spots.append(u)
		if spots.is_empty():
			if has_target and is_instance_valid(target):
				spots.append(target)
			else:
				spawn(parent, impact_id, at)
		for s in spots:
			spawn(parent, impact_id, s.global_position, s)
	if travel_id > 0:
		var from := caster.global_position + Vector3.UP * 1.2
		var g := spawn(parent, travel_id, from, null, true)
		if g == null:
			land.call()
			return
		var to := dest + Vector3.UP * 1.0
		g.look_at_from_position(from, to + Vector3(0.001, 0, 0), Vector3.UP)
		var time := maxf(0.15, from.distance_to(to) / TRAVEL_SPEED)
		var tw := g.create_tween()
		tw.tween_property(g, "global_position", to, time)
		tw.tween_callback(func() -> void:
			land.call()
			g.queue_free())
	else:
		land.call()


func _process(delta: float) -> void:
	if _follow != null:
		if not is_instance_valid(_follow) or not _follow.is_inside_tree():
			queue_free()
			return
		global_position = _follow.global_position
	_life -= delta
	if _life <= 0.0:
		queue_free()
