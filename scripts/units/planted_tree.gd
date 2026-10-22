class_name PlantedTree
extends StaticBody3D
## A yew planted by the Skiller's Timber! (Q). It is solid: it sits on the
## walls physics layer, so units and dashes are blocked, and the navigation
## mesh is rebaked around it so champions path around it. Chopping it
## (Champion._execute_chop) makes it fall away from the chopper.

const BARK := Color(0.42, 0.27, 0.13)
const LEAVES := Color(0.16, 0.42, 0.15)
const WILT := Color(0.45, 0.4, 0.18)

## Every standing tree, for cheap obstacle checks by moving units.
static var active: Array[PlantedTree] = []

var owner_champion: Champion
var block_radius := 0.8
var lifetime := 0.0          # seconds left; 0 = permanent
var planted_at := 0.0        # Combat.clock when planted (oldest is replaced first)
var falling := false

var _pivot: Node3D
var _shape: CollisionShape3D
var _crown_mat: StandardMaterial3D


## Plants a tree at `at` for `caster`. The tree is parented to the map's
## navigation region (when there is one) so a rebake carves it out.
static func plant(caster: Champion, at: Vector3, cfg: Dictionary) -> PlantedTree:
	var t := PlantedTree.new()
	t.owner_champion = caster
	t.block_radius = float(cfg.get("block_radius", 0.8))
	t.lifetime = float(cfg.get("lifetime", 0.0))
	t.planted_at = Combat.clock
	var map := caster.get_tree().get_first_node_in_group("map_builder") as MapBuilder
	var parent: Node = map.nav_region if map != null and map.nav_region != null else caster.get_parent()
	parent.add_child(t)
	t.global_position = Vector3(at.x, 0.0, at.z)
	t._push_units_out()
	if map != null:
		map.request_rebake()
	return t


## The direction a tree falls when chopped by `chopper`: straight away from them.
static func fall_direction(chopper_pos: Vector3, tree_pos: Vector3, fallback: Vector3) -> Vector3:
	var d := tree_pos - chopper_pos
	d.y = 0.0
	return d.normalized() if d.length() > 0.05 else fallback


func _ready() -> void:
	add_to_group("planted_trees")
	collision_layer = Unit.LAYER_WALLS
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = block_radius
	cyl.height = 4.0
	_shape.shape = cyl
	_shape.position = Vector3(0, 2.0, 0)
	add_child(_shape)
	_build_visual()
	active.append(self)
	# Grow in.
	_pivot.scale = Vector3(0.2, 0.2, 0.2)
	create_tween().tween_property(_pivot, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _exit_tree() -> void:
	active.erase(self)


func _build_visual() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.38
	trunk.height = 5.0
	_add_mesh(trunk, _mat(BARK), Vector3(0, 2.5, 0))
	var crown := SphereMesh.new()
	crown.radius = 1.6
	crown.height = 3.0
	_crown_mat = _mat(LEAVES)
	_add_mesh(crown, _crown_mat, Vector3(0, 5.6, 0))
	var stump_ring := CylinderMesh.new()
	stump_ring.top_radius = block_radius
	stump_ring.bottom_radius = block_radius
	stump_ring.height = 0.08
	_add_mesh(stump_ring, _mat(BARK.darkened(0.35)), Vector3(0, 0.04, 0), self)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else _pivot).add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	if falling or lifetime <= 0.0:
		return
	lifetime -= delta
	if lifetime <= 3.0 and _crown_mat != null:
		_crown_mat.albedo_color = LEAVES.lerp(WILT, clampf(1.0 - lifetime / 3.0, 0.0, 1.0))
	if lifetime <= 0.0:
		wither()


func is_standing() -> bool:
	return not falling and not is_queued_for_deletion()


## Units standing where the tree sprouts are shoved to its edge.
func _push_units_out() -> void:
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead or u.is_structure():
			continue
		var to := u.global_position - global_position
		to.y = 0.0
		var need := block_radius + u.radius + 0.1
		if to.length() < need:
			var dir := to.normalized() if to.length() > 0.05 else Vector3.RIGHT
			u.start_dash(global_position + dir * need, 18.0, true)


## Removes the tree's collision right away and plays the fall along `dir`.
func fall(dir: Vector3) -> void:
	if falling:
		return
	falling = true
	_release()
	_pivot.rotation.y = atan2(dir.x, dir.z)
	var tween := create_tween()
	tween.tween_property(_pivot, "rotation:x", PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.7)
	tween.tween_property(_pivot, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tween.tween_callback(queue_free)


## Expired or replaced: shrinks away without dealing damage.
func wither() -> void:
	if falling:
		return
	falling = true
	_release()
	var tween := create_tween()
	tween.tween_property(_pivot, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tween.tween_callback(queue_free)


func _release() -> void:
	active.erase(self)
	remove_from_group("planted_trees")
	if is_instance_valid(owner_champion):
		owner_champion.planted_trees.erase(self)
	_shape.set_deferred("disabled", true)
	collision_layer = 0
	var map := get_tree().get_first_node_in_group("map_builder") as MapBuilder
	if map != null:
		map.request_rebake.call_deferred()
