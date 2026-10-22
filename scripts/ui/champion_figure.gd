class_name ChampionFigure
extends Node3D
## A champion's full-body figure for menus (champion select's portraits and
## Equipment view). With the private OSRS pack it is the champion's real OSRS
## model in its gear, idling. Without it, a blocky stand-in figure built from
## shapes, each part coloured from the build's real equipment icon (helm,
## body, legs, cape, gloves, boots), holding a weapon shaped like its own.

const SKIN := Color(0.78, 0.6, 0.45)

var champion_id := ""
var height := 1.9                  # metres, for framing the camera
var is_osrs := false

static var _icon_colors: Dictionary = {}


static func build(id: String) -> ChampionFigure:
	var f := ChampionFigure.new()
	f.champion_id = id
	f.name = "Figure_" + id
	if OsrsModels.available():
		var cfg := OsrsModels.champion_config(id)
		var actor := OsrsActor.player(cfg) if not cfg.is_empty() else null
		if actor != null:
			actor.scale = Vector3.ONE * float(OsrsModels.config().get("player_scale", 1.4))
			f.add_child(actor)
			f.is_osrs = true
			f.height = f._measure_height()
			return f
	f._build_stand_in(GameData.champion(id))
	return f


func _measure_height() -> float:
	var top := 0.0
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var aabb := mi.get_aabb()
		var s := mi.scale.y
		var p: Node = mi.get_parent()
		while p != null and p != self:
			if p is Node3D:
				s *= (p as Node3D).scale.y
			p = p.get_parent()
		top = maxf(top, (aabb.position.y + aabb.size.y) * s)
	return clampf(top, 1.2, 4.0) if top > 0.0 else 2.4


# --- Stand-in figure -------------------------------------------------------------

## The average colour of an equipment icon (its opaque pixels).
static func icon_color(slug: String, fallback: Color) -> Color:
	if slug == "":
		return fallback
	if _icon_colors.has(slug):
		return _icon_colors[slug]
	var tex := Icons.gear(slug)
	var col := fallback
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img = img.duplicate()
			img.resize(16, 16, Image.INTERPOLATE_NEAREST)
			var sum := Vector3.ZERO
			var count := 0
			for y in 16:
				for x in 16:
					var c := img.get_pixel(x, y)
					if c.a > 0.5 and c.get_luminance() > 0.04:
						sum += Vector3(c.r, c.g, c.b)
						count += 1
			if count > 0:
				sum /= float(count)
				col = Color(sum.x, sum.y, sum.z)
	_icon_colors[slug] = col
	return col


func _build_stand_in(def: Dictionary) -> void:
	var eq: Dictionary = def.get("equipment", {})
	var slot := func(s: String, fallback: Color) -> Color:
		return ChampionFigure.icon_color(str(eq.get(s, {}).get("icon", "")), fallback)
	var body: Color = slot.call("body", Color(0.45, 0.42, 0.38))
	var legs: Color = slot.call("legs", body.darkened(0.2))
	var feet: Color = slot.call("feet", Color(0.3, 0.22, 0.15))
	var hands: Color = slot.call("hands", SKIN)
	height = 1.95
	for side in [-1.0, 1.0]:
		_box(Vector3(0.17, 0.1, 0.3), feet, Vector3(0.12 * side, 0.05, 0.04))
		_box(Vector3(0.18, 0.82, 0.21), legs, Vector3(0.12 * side, 0.5, 0.0))
		_box(Vector3(0.14, 0.58, 0.16), body, Vector3(0.34 * side, 1.18, 0.0))
		_box(Vector3(0.13, 0.13, 0.14), hands, Vector3(0.34 * side, 0.83, 0.02))
	_box(Vector3(0.52, 0.64, 0.3), body, Vector3(0, 1.22, 0))
	_box(Vector3(0.54, 0.07, 0.32), body.darkened(0.35), Vector3(0, 0.93, 0))
	_box(Vector3(0.14, 0.08, 0.14), SKIN, Vector3(0, 1.57, 0))
	_box(Vector3(0.3, 0.3, 0.28), SKIN, Vector3(0, 1.75, 0))
	_box(Vector3(0.05, 0.03, 0.01), Color(0.1, 0.08, 0.06), Vector3(-0.07, 1.78, 0.141))
	_box(Vector3(0.05, 0.03, 0.01), Color(0.1, 0.08, 0.06), Vector3(0.07, 1.78, 0.141))
	if eq.has("head"):
		var helm: Color = slot.call("head", body)
		_box(Vector3(0.34, 0.2, 0.32), helm, Vector3(0, 1.86, -0.01))
		_box(Vector3(0.34, 0.24, 0.06), helm, Vector3(0, 1.72, -0.15))
	if eq.has("neck"):
		_box(Vector3(0.12, 0.12, 0.02), slot.call("neck", Color.GOLD), Vector3(0, 1.38, 0.16))
	if eq.has("cape"):
		_box(Vector3(0.48, 0.92, 0.04), slot.call("cape", Color.DARK_RED), Vector3(0, 1.08, -0.18))
	if eq.has("shield"):
		if str(eq["shield"].get("icon", "")) == "chisel":
			_box(Vector3(0.03, 0.22, 0.03), Color(0.72, 0.74, 0.78), Vector3(-0.34, 0.86, 0.1))
		else:
			_box(Vector3(0.06, 0.46, 0.36), slot.call("shield", Color.GRAY), Vector3(-0.44, 1.05, 0.04))
	if eq.has("weapon"):
		_weapon(str(eq["weapon"].get("icon", "")), slot.call("weapon", Color(0.7, 0.7, 0.72)))


func _weapon(slug: String, c: Color) -> void:
	var hand := Vector3(0.34, 0.83, 0.1)
	var grip := Color(0.35, 0.25, 0.15)
	if slug.contains("crossbow"):
		_box(Vector3(0.06, 0.06, 0.55), grip, hand + Vector3(0, 0.05, 0.15))
		_box(Vector3(0.5, 0.05, 0.05), c, hand + Vector3(0, 0.07, 0.38))
	elif slug.contains("bow"):
		_box(Vector3(0.04, 1.0, 0.05), c, hand + Vector3(0.02, 0.1, 0.06))
	elif slug.contains("staff"):
		_box(Vector3(0.05, 1.5, 0.05), c, hand + Vector3(0, 0.25, 0.0))
		_box(Vector3(0.12, 0.12, 0.12), c.lightened(0.3), hand + Vector3(0, 1.02, 0.0))
	elif slug.contains("axe") or slug.contains("ket_om") or slug.contains("maul") or slug.contains("hammer"):
		_box(Vector3(0.05, 1.0, 0.05), grip, hand + Vector3(0, 0.25, 0.0))
		_box(Vector3(0.1, 0.28, 0.36) if not slug.contains("ket_om") else Vector3(0.24, 0.24, 0.38), c, hand + Vector3(0, 0.66, 0.1))
	elif slug.contains("whip"):
		_box(Vector3(0.05, 0.2, 0.05), grip, hand)
		_box(Vector3(0.03, 0.7, 0.03), c, hand + Vector3(0, -0.4, 0.06))
	else:
		_box(Vector3(0.04, 0.16, 0.05), grip, hand)
		_box(Vector3(0.02, 0.72, 0.08), c, hand + Vector3(0, 0.44, 0.0))
		_box(Vector3(0.05, 0.03, 0.2), c.darkened(0.3), hand + Vector3(0, 0.09, 0.0))


func _box(size: Vector3, c: Color, pos: Vector3) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.85
	mi.material_override = mat
	add_child(mi)
	return mi
