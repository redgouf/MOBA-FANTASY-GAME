class_name OsrsProps
extends RefCounted
## OSRS scenery from the private model pack (objects/<id>.glb, written by
## tools/osrs_extract) used as the game's buildings and props: towers,
## altars, team standards, the dwarf multicannon, prayer altars and the
## Skiller's yews. data/models.json says which object is which.
## Without the pack (or the object) every caller keeps its whitebox shape.


static func has_object(id: int) -> bool:
	return OsrsModels.available() and OsrsModels.scene("objects/%d.glb" % id) != null


## An OSRS object, standing on y = 0 and centred, scaled so its height is
## `height` metres (or its widest side `width` metres; or the champions'
## OSRS scale when both are 0). null when the pack doesn't have it.
static func object(id: int, height: float = 0.0, width: float = 0.0, tint: Color = Color.WHITE) -> Node3D:
	if not OsrsModels.available():
		return null
	var ps := OsrsModels.scene("objects/%d.glb" % id)
	if ps == null:
		return null
	var model := ps.instantiate() as Node3D
	OsrsModels.apply_material(model)
	if tint != Color.WHITE:
		_tint(model, tint)
	var box := _bounds(model)
	var s := float(OsrsModels.config().get("player_scale", 1.4))
	if height > 0.0 and box.size.y > 0.01:
		s = height / box.size.y
	elif width > 0.0 and maxf(box.size.x, box.size.z) > 0.01:
		s = width / maxf(box.size.x, box.size.z)
	var holder := Node3D.new()
	holder.name = "OsrsObject%d" % id
	holder.add_child(model)
	model.scale = Vector3.ONE * s
	var c := box.get_center()
	model.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	return holder


## The look of a structure (`def_id` from units.json: tower_outer, altar,
## flag...) for a team: one or more objects stacked as models.json lists.
static func structure(def_id: String, team: int) -> Node3D:
	var cfg: Dictionary = OsrsModels.config().get("structures", {}).get(def_id, {})
	var parts: Array = cfg.get("saradomin" if team == Combat.Team.SARADOMIN else "zamorak", [])
	if parts.is_empty():
		return null
	var root := Node3D.new()
	root.name = "OsrsStructure"
	var y := 0.0
	for p in parts:
		var t: Array = p.get("tint", [1, 1, 1])
		var o := object(int(p.get("object", 0)), float(p.get("height", 0.0)), float(p.get("width", 0.0)), Color(float(t[0]), float(t[1]), float(t[2])))
		if o == null:
			root.free()
			return null
		var off: Array = p.get("offset", [0, 0, 0])
		o.position = Vector3(float(off[0]), float(off[1]) + (y if bool(p.get("stack", false)) else 0.0), float(off[2]))
		o.rotation_degrees.y = float(p.get("rotation", 0.0))
		if not bool(p.get("receive_shadows", true)):
			no_receive_shadows(o)
		root.add_child(o)
		if bool(p.get("stack", false)):
			y += _bounds(o).size.y
	return root


## A named prop from models.json "props" (cannon, prayer_altar, yew...).
static func prop(key: String, height: float = 0.0, width: float = 0.0) -> Node3D:
	var id := int(OsrsModels.config().get("props", {}).get(key, 0))
	return object(id, height, width) if id > 0 else null


## Stops a model's surfaces receiving shadows (it still casts them onto the
## ground and everything else): thin two-faced cloth, like the team standards'
## banners, shadows itself in stripes otherwise. Works on copies of the
## shared materials.
static func no_receive_shadows(root: Node3D) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override is BaseMaterial3D:
			var d := (mi.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
			d.disable_receive_shadows = true
			mi.material_override = d
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			var d := src.duplicate() as BaseMaterial3D
			d.disable_receive_shadows = true
			mi.set_surface_override_material(i, d)


## Multiplies every surface's colour by `tint` (a darker or team-coloured
## variant of a shared object), on copies of the shared materials.
static func _tint(root: Node3D, tint: Color) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			var t := src.duplicate() as BaseMaterial3D
			t.albedo_color = src.albedo_color * tint
			m.set_surface_override_material(i, t)
		m.material_override = null


static func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.get_aabb()
		var xf := n.global_transform.affine_inverse() * m.global_transform if n.is_inside_tree() else _relative(n, m)
		b = xf * b
		out = b if first else out.merge(b)
		first = false
	return out


static func _relative(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
