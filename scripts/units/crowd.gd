class_name Crowd
extends RefCounted
## Unit spacing, roughly how League handles it: every living unit has a
## round footprint (its radius) and nothing ends a frame standing inside
## another. Overlapping pairs are eased apart a little each physics frame,
## the lighter unit giving way: minions shuffle aside for champions and
## monsters, champions shove each other evenly, and structures, summons
## (the cannon) and epic monsters never move. Units apply their push with
## move_and_collide, so nobody is pushed through a wall.

const CELL := 3.0
const RESOLVE_PER_SEC := 12.0      # share of an overlap removed per second (eased)
const MAX_PUSH := 0.25             # metres per frame at most
const PACK := 0.9                  # footprints overlap this much before pushing


## How hard a unit is to push (INF = never moves).
static func mass(u: Unit) -> float:
	if u is Structure or u.is_epic:
		return INF
	if u is Champion:
		return 4.0
	if u is Monster:
		return 6.0
	if u is Minion and str((u as Minion).role) == "super":
		return 3.0
	return 1.0


## Computes this frame's push for every unit (stored in Unit.crowd_push).
static func solve(tree: SceneTree, delta: float) -> int:
	var units: Array[Unit] = []
	var grid: Dictionary = {}
	for n in tree.get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead or not u.visible or u.radius <= 0.0 or u.collision_layer == 0:
			continue
		u.crowd_push = Vector3.ZERO
		units.append(u)
		var key := Vector2i(floori(u.global_position.x / CELL), floori(u.global_position.z / CELL))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(u)
	var pairs := 0
	var k := minf(1.0, RESOLVE_PER_SEC * delta)
	for a in units:
		var ka := Vector2i(floori(a.global_position.x / CELL), floori(a.global_position.z / CELL))
		var ma := mass(a)
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var cell: Variant = grid.get(ka + Vector2i(dx, dz))
				if cell == null:
					continue
				for b in cell:
					var ub := b as Unit
					if ub.get_instance_id() <= a.get_instance_id():
						continue
					var d := ub.global_position - a.global_position
					d.y = 0.0
					var reach := (a.radius + ub.radius) * PACK
					var dist := d.length()
					if dist >= reach:
						continue
					var mb := mass(ub)
					if ma == INF and mb == INF:
						continue
					pairs += 1
					var dir := d / dist if dist > 0.001 else Vector3(cos(float(a.get_instance_id())), 0.0, sin(float(a.get_instance_id())))
					var overlap := (reach - dist) * k
					var share_a := 0.5
					if ma == INF:
						share_a = 0.0
					elif mb == INF:
						share_a = 1.0
					else:
						share_a = mb / (ma + mb)
					a.crowd_push -= dir * overlap * share_a
					ub.crowd_push += dir * overlap * (1.0 - share_a)
	for u in units:
		if u.crowd_push.length() > MAX_PUSH:
			u.crowd_push = u.crowd_push.normalized() * MAX_PUSH
	return pairs
