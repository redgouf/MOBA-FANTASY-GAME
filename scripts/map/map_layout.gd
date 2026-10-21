class_name MapLayout
extends RefCounted
## Coordinates for the Wilderness Rift: a 200 x 200 m three-lane map.
## Screen-up is -Z. Saradomin (Falador) holds the bottom-left, Zamorak (Lava Maze)
## the top-right, and the Wilderness Ditch runs diagonally along z = x.

const MAP_SIZE := 200.0
const LANE_WIDTH := 10.0
const RIVER_WIDTH := 14.0
const BASE_RADIUS := 18.0
const LANES: Array[String] = ["top", "mid", "bot"]

const SARADOMIN_BASE := Vector3(-82.0, 0.0, 82.0)
const ZAMORAK_BASE := Vector3(82.0, 0.0, -82.0)
const TOP_CORNER := Vector3(-82.0, 0.0, -82.0)
const BOT_CORNER := Vector3(82.0, 0.0, 82.0)

const JAD_PIT := Vector3(-38.0, 0.0, -38.0)       # Baron equivalent (Giant Mole before 14:00)
const DRAGON_PIT := Vector3(38.0, 0.0, 38.0)      # Dragon equivalent

## Distances from a team's own base along a lane, outermost last.
const SIDE_LANE_STRUCTURES := {"altar": 20.0, "altar_tower": 30.0, "inner": 78.0, "outer": 122.0}
const MID_LANE_STRUCTURES := {"altar": 20.0, "altar_tower": 30.0, "inner": 52.0, "outer": 76.0}


static func base_position(team: int) -> Vector3:
	return SARADOMIN_BASE if team == Combat.Team.SARADOMIN else ZAMORAK_BASE


## Point reflection through the map centre: maps Saradomin's half onto Zamorak's.
static func mirror(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, -p.z)


## Lane polyline from this team's base to the enemy base.
static func lane_path(lane: String, team: int) -> PackedVector3Array:
	var pts: PackedVector3Array
	match lane:
		"top":
			pts = PackedVector3Array([SARADOMIN_BASE, TOP_CORNER, ZAMORAK_BASE])
		"bot":
			pts = PackedVector3Array([SARADOMIN_BASE, BOT_CORNER, ZAMORAK_BASE])
		_:
			pts = PackedVector3Array([SARADOMIN_BASE, ZAMORAK_BASE])
	if team == Combat.Team.ZAMORAK:
		pts.reverse()
	return pts


static func path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


static func point_along(path: PackedVector3Array, distance: float) -> Vector3:
	var remaining := maxf(distance, 0.0)
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if remaining <= seg:
			return path[i - 1].lerp(path[i], remaining / seg if seg > 0.0 else 0.0)
		remaining -= seg
	return path[path.size() - 1]


## Where a lane bot waits when it has no minion wave to follow.
static func hold_distance(lane: String) -> float:
	return 70.0 if lane == "mid" else 110.0


## Every tower, altar and flag for one team: [{kind, lane, tier, pos}].
static func structure_layout(team: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lane in LANES:
		var path := lane_path(lane, team)
		var table: Dictionary = MID_LANE_STRUCTURES if lane == "mid" else SIDE_LANE_STRUCTURES
		for tier in ["outer", "inner", "altar_tower"]:
			out.append({"kind": "tower", "lane": lane, "tier": tier, "pos": point_along(path, table[tier])})
		out.append({"kind": "altar", "lane": lane, "tier": "altar", "pos": point_along(path, table["altar"])})
	var base := base_position(team)
	var toward_center := (Vector3.ZERO - base).normalized()
	var side := Vector3(toward_center.z, 0.0, -toward_center.x)
	out.append({"kind": "tower", "lane": "base", "tier": "flag_tower", "pos": base + toward_center * 9.0 + side * 4.0})
	out.append({"kind": "tower", "lane": "base", "tier": "flag_tower", "pos": base + toward_center * 9.0 - side * 4.0})
	out.append({"kind": "flag", "lane": "base", "tier": "flag", "pos": base})
	return out


## Solid rock walls for the Saradomin jungle; Zamorak's are mirrored. [{pos, size}]
static func saradomin_walls() -> Array[Dictionary]:
	return [
		# Top-side jungle (between top lane and mid)
		{"pos": Vector3(-62.0, 0.0, 25.0), "size": Vector3(8.0, 3.0, 20.0)},
		{"pos": Vector3(-45.0, 0.0, -5.0), "size": Vector3(18.0, 3.0, 6.0)},
		{"pos": Vector3(-44.0, 0.0, 22.0), "size": Vector3(6.0, 3.0, 12.0)},
		{"pos": Vector3(-66.0, 0.0, -30.0), "size": Vector3(10.0, 3.0, 8.0)},
		# Bot-side jungle (between mid and bot lane)
		{"pos": Vector3(-25.0, 0.0, 62.0), "size": Vector3(20.0, 3.0, 8.0)},
		{"pos": Vector3(5.0, 0.0, 45.0), "size": Vector3(6.0, 3.0, 18.0)},
		{"pos": Vector3(-15.0, 0.0, 38.0), "size": Vector3(14.0, 3.0, 6.0)},
		{"pos": Vector3(30.0, 0.0, 66.0), "size": Vector3(8.0, 3.0, 10.0)},
	]


static func all_walls() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in saradomin_walls():
		out.append(w)
		out.append({"pos": mirror(w["pos"]), "size": w["size"]})
	return out


## Jungle camps on the Saradomin side; Zamorak's are mirrored. [{id, monster, pos}]
static func saradomin_camps() -> Array[Dictionary]:
	return [
		{"id": "blue", "monster": "abyssal_demon", "pos": Vector3(-52.0, 0.0, 15.0)},
		{"id": "red", "monster": "fire_giant", "pos": Vector3(-10.0, 0.0, 52.0)},
		{"id": "moss", "monster": "moss_giant", "pos": Vector3(-63.0, 0.0, -10.0)},
		{"id": "wolves", "monster": "white_wolf", "pos": Vector3(-40.0, 0.0, -14.0)},
		{"id": "chickens", "monster": "chicken", "pos": Vector3(-28.0, 0.0, 46.0)},
		{"id": "ogres", "monster": "ogre", "pos": Vector3(14.0, 0.0, 60.0)},
	]


## Every neutral spawn on the map, including river crabs and the two epic pits.
static func all_camps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in saradomin_camps():
		out.append({"id": "sara_" + c["id"], "monster": c["monster"], "pos": c["pos"]})
		out.append({"id": "zam_" + c["id"], "monster": c["monster"], "pos": mirror(c["pos"])})
	out.append({"id": "crab_top", "monster": "rock_crab", "pos": Vector3(-20.0, 0.0, -20.0)})
	out.append({"id": "crab_bot", "monster": "rock_crab", "pos": Vector3(20.0, 0.0, 20.0)})
	out.append({"id": "jad", "monster": "tztok_jad", "pos": JAD_PIT})
	out.append({"id": "dragon", "monster": "chromatic_dragon", "pos": DRAGON_PIT})
	return out
