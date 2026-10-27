class_name MapLayout
extends RefCounted
## Coordinates for the Wilderness Rift: a replica of League of Legends
## Classic's Summoner's Rift (the pre-2015 layout, three lanes, no lane
## alcoves), about 197 m across at 75 League units per metre.
##
## The layout lives in data/map.json, traced from the League map's navigation
## grid by tools/rift_classic/extract_navgrid.py: rock-wall outlines, the
## brush and river grids, lane lines, every turret / inhibitor / nexus spot,
## camp and pit spots, and the team-only base gates. This class reads it and
## answers questions about it. Coordinates are metres: x east, z south
## (screen-up is -z). Saradomin holds the bottom-left, Zamorak the top-right,
## and the map is point-symmetric about the origin.

const MAP_SIZE := 200.0
const LANE_WIDTH := 10.0
const BASE_RADIUS := 18.0
const PIT_RADIUS := 7.0
const LANES: Array[String] = ["top", "mid", "bot"]

## The fountain (spawn pool) in each corner. Champions spawn, heal and shop here.
const SARADOMIN_BASE := Vector3(-90.7, 0.0, 90.7)
const ZAMORAK_BASE := Vector3(90.7, 0.0, -90.7)

const DATA_PATH := "res://data/map.json"

static var _data: Dictionary = {}
static var _paths: Dictionary = {}              # lane -> Saradomin-side path
static var _grids: Dictionary = {}              # grid name -> PackedByteArray
static var _brush_labels := PackedInt32Array()  # brush patch id per cell (-1 = no brush)
static var _camps_cache: Array[Dictionary] = []


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("MapLayout: couldn't read %s" % DATA_PATH)
	return _data


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), 0.0, float(a[1]))


static func base_position(team: int) -> Vector3:
	return SARADOMIN_BASE if team == Combat.Team.SARADOMIN else ZAMORAK_BASE


## Point reflection through the map centre: maps Saradomin's half onto Zamorak's.
static func mirror(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, -p.z)


static func opposite_lane(lane: String) -> String:
	return {"top": "bot", "mid": "mid", "bot": "top"}[lane]


# --- Structures ---------------------------------------------------------------

## The nexus (team flag) position.
static func nexus_position(team: int) -> Vector3:
	var p := _v(data()["structures_saradomin"]["nexus"])
	return p if team == Combat.Team.SARADOMIN else mirror(p)


## One lane's structure spots for a team. The map is point-symmetric, so
## Zamorak's "top" lane holds the mirror of Saradomin's "bot" lane.
## {outer, inner, base, inhibitor} -> Vector3.
static func lane_structures(team: int, lane: String) -> Dictionary:
	var src: Dictionary = data()["structures_saradomin"]
	var out := {}
	if team == Combat.Team.SARADOMIN:
		for k in ["outer", "inner", "base", "inhibitor"]:
			out[k] = _v(src[lane][k])
	else:
		for k in ["outer", "inner", "base", "inhibitor"]:
			out[k] = mirror(_v(src[opposite_lane(lane)][k]))
	return out


## Every tower, altar and flag for one team: [{kind, lane, tier, pos}].
## The League inhibitor turret is our "altar_tower", the inhibitor our "altar",
## the two nexus turrets "flag_tower" and the nexus the "flag".
static func structure_layout(team: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lane in LANES:
		var s := lane_structures(team, lane)
		out.append({"kind": "tower", "lane": lane, "tier": "outer", "pos": s["outer"]})
		out.append({"kind": "tower", "lane": lane, "tier": "inner", "pos": s["inner"]})
		out.append({"kind": "tower", "lane": lane, "tier": "altar_tower", "pos": s["base"]})
		out.append({"kind": "altar", "lane": lane, "tier": "altar", "pos": s["inhibitor"]})
	for p in data()["structures_saradomin"]["nexus_turrets"]:
		var pos := _v(p)
		out.append({"kind": "tower", "lane": "base", "tier": "flag_tower", "pos": pos if team == Combat.Team.SARADOMIN else mirror(pos)})
	out.append({"kind": "flag", "lane": "base", "tier": "flag", "pos": nexus_position(team)})
	return out


# --- Lanes ---------------------------------------------------------------------

## Lane polyline from this team's nexus, past its inhibitor and along the lane,
## to the enemy inhibitor and nexus.
static func lane_path(lane: String, team: int) -> PackedVector3Array:
	if not _paths.has(lane):
		var pts := PackedVector3Array()
		pts.append(nexus_position(Combat.Team.SARADOMIN))
		for p in data()["lanes"][lane]:
			pts.append(_v(p))
		pts.append(nexus_position(Combat.Team.ZAMORAK))
		_paths[lane] = pts
	var path: PackedVector3Array = _paths[lane]
	if team == Combat.Team.ZAMORAK:
		path = path.duplicate()
		path.reverse()
	return path


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


## The first waypoint ahead of a point `distance` along the path.
static func index_after(path: PackedVector3Array, distance: float) -> int:
	var walked := 0.0
	for i in range(1, path.size()):
		walked += path[i - 1].distance_to(path[i])
		if walked > distance:
			return i
	return path.size() - 1


## How far along a path the point nearest to `p` is.
static func distance_along(path: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	var best_at := 0.0
	var walked := 0.0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var seg := b - a
		var len2 := seg.length_squared()
		var t := clampf((p - a).dot(seg) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
		var d := a.lerp(b, t).distance_to(p)
		if d < best:
			best = d
			best_at = walked + sqrt(len2) * t
		walked += sqrt(len2)
	return best_at


## Where a team's minions appear: just past their own inhibitor on the lane.
static func spawn_distance(lane: String, team: int = Combat.Team.SARADOMIN) -> float:
	var s := lane_structures(team, lane)
	return nexus_position(team).distance_to(s["inhibitor"]) + 4.0


## Where a lane bot waits when it has no minion wave to follow: a little
## behind its own outer tower.
static func hold_distance(lane: String, team: int = Combat.Team.SARADOMIN) -> float:
	var path := lane_path(lane, team)
	var outer: Vector3 = lane_structures(team, lane)["outer"]
	return maxf(distance_along(path, outer) - 6.0, spawn_distance(lane, team) + 4.0)


# --- Terrain -------------------------------------------------------------------

## Rock-wall outlines (and the structure footprints) as polygons of (x, z) metres.
static func wall_polygons() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for poly in data()["walls"]:
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(Vector2(float(p[0]), float(p[1])))
		out.append(pts)
	return out


## Team-only base gates: [{team, pos, size}]. Only their own team can walk
## through; everyone else treats them as wall.
static func gates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for team_name in ["saradomin", "zamorak"]:
		var team := Combat.Team.SARADOMIN if team_name == "saradomin" else Combat.Team.ZAMORAK
		for g in data()["gates"][team_name]:
			out.append({"team": team, "pos": _v(g["pos"]), "size": Vector2(float(g["size"][0]), float(g["size"][1]))})
	return out


## The direction through a gate: across its short side.
static func gate_axis(size: Vector2) -> Vector3:
	return Vector3(1.0, 0.0, 0.0) if size.x <= size.y else Vector3(0.0, 0.0, 1.0)


static func jad_pit() -> Vector3:
	return _v(data()["camps"]["baron"])


static func dragon_pit() -> Vector3:
	return _v(data()["camps"]["dragon"])


static func _grid(name: String) -> PackedByteArray:
	if not _grids.has(name):
		var g: Dictionary = data()["grid"]
		var cols := int(g["cols"])
		var rows := int(g["rows"])
		var out := PackedByteArray()
		out.resize(cols * rows)
		var r := 0
		for row in data()[name]:
			var c := 0
			for run in row:
				if int(run[0]) != 0:
					for i in int(run[1]):
						out[r * cols + c + i] = 1
				c += int(run[1])
			r += 1
		_grids[name] = out
	return _grids[name]


## A terrain grid as one byte per cell (1 = set), row 0 the southern-most row.
static func grid_bytes(name: String) -> PackedByteArray:
	return _grid(name)


static func _cell_value(name: String, p: Vector3) -> bool:
	var g: Dictionary = data()["grid"]
	var cols := int(g["cols"])
	var rows := int(g["rows"])
	var cell := float(data()["cell_m"])
	var col := int(floor((p.x - float(g["origin"][0])) / cell))
	var row := rows - 1 - int(floor((p.z - float(g["origin"][1])) / cell))
	if col < 0 or col >= cols or row < 0 or row >= rows:
		return false
	return _grid(name)[row * cols + col] == 1


## Which patch of brush a point is in (a number), or -1 outside brush.
static func brush_patch(p: Vector3) -> int:
	if _brush_labels.is_empty():
		_label_brush()
	var g: Dictionary = data()["grid"]
	var cols := int(g["cols"])
	var rows := int(g["rows"])
	var cell := float(data()["cell_m"])
	var col := int(floor((p.x - float(g["origin"][0])) / cell))
	var row := rows - 1 - int(floor((p.z - float(g["origin"][1])) / cell))
	if col < 0 or col >= cols or row < 0 or row >= rows:
		return -1
	return _brush_labels[row * cols + col]


## Connected brush cells (diagonals count) are one patch.
static func _label_brush() -> void:
	var g: Dictionary = data()["grid"]
	var cols := int(g["cols"])
	var rows := int(g["rows"])
	var brush := _grid("brush_rle")
	_brush_labels.resize(cols * rows)
	_brush_labels.fill(-1)
	var next := 0
	var stack := PackedInt32Array()
	for start in cols * rows:
		if brush[start] == 0 or _brush_labels[start] != -1:
			continue
		_brush_labels[start] = next
		stack.clear()
		stack.append(start)
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var r := i / cols
			var c := i % cols
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					var rr := r + dr
					var cc := c + dc
					if rr < 0 or rr >= rows or cc < 0 or cc >= cols:
						continue
					var j := rr * cols + cc
					if brush[j] == 1 and _brush_labels[j] == -1:
						_brush_labels[j] = next
						stack.append(j)
		next += 1


## Brush: tall grass that hides units standing in it from the other team.
static func is_brush(p: Vector3) -> bool:
	return _cell_value("brush_rle", p)


static func is_river(p: Vector3) -> bool:
	return _cell_value("river_rle", p)


static func is_wall(p: Vector3) -> bool:
	return _cell_value("wall_rle", p)


## Inside the Baron or Dragon pit.
static func is_pit(p: Vector3) -> bool:
	return _cell_value("pit_rle", p)


# --- Jungle ----------------------------------------------------------------------

## Jungle camps on the Saradomin side. Each camp: id, pos, members
## [[monster, offset]], first spawn and respawn (seconds), after League of
## Legends Classic's Season 3 timings: buffs 1:55 then every 5:00 (each with
## two small companions), the other camps 2:05 then every 0:50.
static func saradomin_camps() -> Array[Dictionary]:
	var c: Dictionary = data()["camps"]
	return [
		{"id": "blue", "pos": _v(c["blue"]), "first": 115, "respawn": 300,
			"members": [["abyssal_demon", Vector3.ZERO], ["abyssal_leech", Vector3(-2.6, 0.0, 1.2)], ["abyssal_leech", Vector3(2.6, 0.0, 1.2)]]},
		{"id": "red", "pos": _v(c["red"]), "first": 115, "respawn": 300,
			"members": [["fire_giant", Vector3.ZERO], ["imp", Vector3(-2.6, 0.0, 1.2)], ["imp", Vector3(2.6, 0.0, 1.2)]]},
		{"id": "moss", "pos": _v(c["gromp"]), "first": 125, "respawn": 50,
			"members": [["moss_giant", Vector3.ZERO]]},
		{"id": "wolves", "pos": _v(c["murkwolves"]), "first": 125, "respawn": 50,
			"members": [["big_wolf", Vector3.ZERO], ["white_wolf", Vector3(2.2, 0.0, 1.6)], ["white_wolf", Vector3(-2.2, 0.0, 1.6)]]},
		{"id": "chickens", "pos": _v(c["raptors"]), "first": 125, "respawn": 50,
			"members": [["rooster", Vector3.ZERO], ["chicken", Vector3(1.8, 0.0, 0.8)], ["chicken", Vector3(-1.8, 0.0, 0.8)], ["chicken", Vector3(0.0, 0.0, 1.9)]]},
		{"id": "ogres", "pos": _v(c["krugs"]), "first": 125, "respawn": 50,
			"members": [["ogre_chieftain", Vector3.ZERO], ["ogre", Vector3(2.4, 0.0, 0.8)]]},
	]


## Neutral prayer altars, one beside each buff camp (Saradomin's two here;
## Zamorak's are mirrored). [{side, pos}]
static func saradomin_prayer_altars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in data()["prayer_altars_saradomin"]:
		out.append({"side": str(a["side"]), "pos": _v(a["pos"])})
	return out


static func all_prayer_altars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in saradomin_prayer_altars():
		out.append(a)
		out.append({"side": a["side"], "pos": mirror(a["pos"])})
	return out


## Every neutral spawn on the map: the mirrored jungle camps and the two epic
## pits. There are no river monsters in Classic. Optional keys: "once" (never
## respawns), "despawn" (removed at this game time if still alive).
static func all_camps() -> Array[Dictionary]:
	if not _camps_cache.is_empty():
		return _camps_cache
	var out: Array[Dictionary] = []
	for c in saradomin_camps():
		var zam: Dictionary = c.duplicate(true)
		var mirrored: Array = []
		for m in c["members"]:
			mirrored.append([m[0], mirror(m[1])])
		zam["members"] = mirrored
		zam["pos"] = mirror(c["pos"])
		zam["id"] = "zam_" + c["id"]
		var sara: Dictionary = c.duplicate(true)
		sara["id"] = "sara_" + c["id"]
		out.append(sara)
		out.append(zam)
	# Baron pit (TzTok-Jad): 15:00, then every 7:00. Dragon pit: 2:30, then every 6:00.
	out.append({"id": "jad", "pos": jad_pit(), "first": 900, "respawn": 420, "members": [["tztok_jad", Vector3.ZERO]]})
	out.append({"id": "dragon", "pos": dragon_pit(), "first": 150, "respawn": 360, "members": [["chromatic_dragon", Vector3.ZERO]]})
	_camps_cache = out
	return out
