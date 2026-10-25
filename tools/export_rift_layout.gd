extends SceneTree
## Writes the Wilderness Rift's layout (MapLayout) to
## tools/osrs_extract/rift_layout.json, for tools/osrs_extract to dress the
## map with OSRS ground, floors and scenery. Re-run after changing MapLayout:
##   godot --headless --path . -s res://tools/export_rift_layout.gd


func _init() -> void:
	var lanes := {}
	for lane in MapLayout.LANES:
		var pts: Array = []
		for p in MapLayout.lane_path(lane, Combat.Team.SARADOMIN):
			pts.append([p.x, p.z])
		lanes[lane] = pts
	var walls: Array = []
	for w in MapLayout.all_walls():
		walls.append({"pos": [w["pos"].x, w["pos"].z], "size": [w["size"].x, w["size"].z]})
	var camps: Array = []
	for c in MapLayout.all_camps():
		camps.append([c["pos"].x, c["pos"].z])
	var keep_clear: Array = []
	for team in [Combat.Team.SARADOMIN, Combat.Team.ZAMORAK]:
		for s in MapLayout.structure_layout(team):
			keep_clear.append([s["pos"].x, s["pos"].z])
	for a in MapLayout.all_prayer_altars():
		keep_clear.append([a["pos"].x, a["pos"].z])
	var out := {
		"_comment": "Written by tools/export_rift_layout.gd from scripts/map/map_layout.gd. Metres; x east, z south (screen-up is -z).",
		"map_size": MapLayout.MAP_SIZE, "lane_width": MapLayout.LANE_WIDTH, "river_width": MapLayout.RIVER_WIDTH,
		"base_radius": MapLayout.BASE_RADIUS, "pit_radius": 7.0,
		"saradomin_base": [MapLayout.SARADOMIN_BASE.x, MapLayout.SARADOMIN_BASE.z],
		"zamorak_base": [MapLayout.ZAMORAK_BASE.x, MapLayout.ZAMORAK_BASE.z],
		"jad_pit": [MapLayout.JAD_PIT.x, MapLayout.JAD_PIT.z], "dragon_pit": [MapLayout.DRAGON_PIT.x, MapLayout.DRAGON_PIT.z],
		"lanes": lanes, "walls": walls, "camps": camps, "keep_clear": keep_clear,
	}
	var f := FileAccess.open("res://tools/osrs_extract/rift_layout.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("rift layout written")
	quit()
