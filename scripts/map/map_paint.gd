class_name MapPaint
extends RefCounted
## Paints the Rift's terrain grids (rock, brush, river, pits) into a picture,
## for the whitebox ground and the minimap.

const GROUND := Color(0.36, 0.33, 0.23)
const ROCK := Color(0.2, 0.19, 0.18)
const BRUSH := Color(0.2, 0.34, 0.16)
const RIVER := Color(0.2, 0.36, 0.5)
const PIT := Color(0.45, 0.2, 0.08)


## The world rectangle (x, z in metres) the grids cover.
static func world_rect() -> Rect2:
	var g: Dictionary = MapLayout.data()["grid"]
	var cell := float(MapLayout.data()["cell_m"])
	return Rect2(float(g["origin"][0]), float(g["origin"][1]), float(g["cols"]) * cell, float(g["rows"]) * cell)


## One pixel per grid cell, north at the top. Layers the caller doesn't want
## (e.g. rock, which the 3D ground doesn't paint) can be skipped by passing
## a transparent colour.
static func image(ground: Color = GROUND, rock: Color = ROCK, brush: Color = BRUSH, river: Color = RIVER, pit: Color = PIT) -> Image:
	var g: Dictionary = MapLayout.data()["grid"]
	var cols := int(g["cols"])
	var rows := int(g["rows"])
	var walls := MapLayout.grid_bytes("wall_rle")
	var brushes := MapLayout.grid_bytes("brush_rle")
	var rivers := MapLayout.grid_bytes("river_rle")
	var pits := MapLayout.grid_bytes("pit_rle")
	var img := Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	img.fill(ground)
	for r in rows:
		var y := rows - 1 - r
		for c in cols:
			var i := r * cols + c
			if walls[i] == 1:
				img.set_pixel(c, y, rock)
			elif pits[i] == 1:
				img.set_pixel(c, y, pit)
			elif rivers[i] == 1:
				img.set_pixel(c, y, river)
			elif brushes[i] == 1:
				img.set_pixel(c, y, brush)
	return img
