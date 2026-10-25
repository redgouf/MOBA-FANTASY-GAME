class_name OsrsMap
extends RefCounted
## OSRS map squares from the private model pack (private_assets/osrs/maps,
## written by tools/osrs_extract). Each square is 64x64 tiles: a GLB with
## terrain, floor textures, walls, scenery and roofs per level, plus a JSON
## file with corner heights, tile flags and every placed object.
##
## World space matches the pack: 1 tile = 1 m, east = +X, north = -Z. A square
## is placed so that `origin_tile` (an OSRS world tile) sits at (0, 0, 0).
## Like the rest of the pack: private, never committed or published.

const DIR := "maps/"


static func has_region(rx: int, ry: int) -> bool:
	return ResourceLoader.exists(OsrsModels.ROOT + DIR + "%d_%d.glb" % [rx, ry])


## The square (rx, ry), placed relative to `origin_tile`. `max_level` hides
## upper floors (0 = ground only); `roofs` hides roofs when false.
static func region(rx: int, ry: int, origin_tile: Vector2i, max_level: int = 3, roofs: bool = true) -> Node3D:
	var ps := OsrsModels.scene(DIR + "%d_%d.glb" % [rx, ry])
	if ps == null:
		return null
	var root := ps.instantiate() as Node3D
	OsrsModels.apply_material(root)
	for n in root.find_children("level_*", "", true, false):
		n.visible = int(str(n.name).substr(6)) <= max_level
	if not roofs:
		for n in root.find_children("roofs_*", "", true, false):
			n.visible = false
	root.position = Vector3(rx * 64 - origin_tile.x, 0.0, -(ry * 64 - origin_tile.y))
	return root


## Heights, flags and objects of the square ({} when missing).
static func data(rx: int, ry: int) -> Dictionary:
	var path := OsrsModels.ROOT + DIR + "%d_%d.json" % [rx, ry]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Ground height in metres at a point inside the square, in tiles from its
## south-west corner (x east, y north), on `level`.
static func height_at(d: Dictionary, level: int, x: float, y: float) -> float:
	var h: Array = d.get("heights", [])
	if h.size() <= level:
		return 0.0
	var grid: Array = h[level]
	var n := grid.size() - 1
	var tx := clampi(int(floor(x)), 0, n - 1)
	var ty := clampi(int(floor(y)), 0, n - 1)
	var fx := clampf(x - tx, 0.0, 1.0)
	var fy := clampf(y - ty, 0.0, 1.0)
	var a := lerpf(float(grid[tx][ty]), float(grid[tx + 1][ty]), fx)
	var b := lerpf(float(grid[tx][ty + 1]), float(grid[tx + 1][ty + 1]), fx)
	return lerpf(a, b, fy)
