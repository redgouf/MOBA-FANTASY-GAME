extends SceneTree
## Writes the Wilderness Rift's layout (MapLayout, i.e. data/map.json) to
## tools/osrs_extract/rift_layout.json, for tools/osrs_extract to dress the
## map with OSRS ground, floors and scenery. Re-run after changing the map:
##   godot --headless --path . -s res://tools/export_rift_layout.gd


func _init() -> void:
	var data := MapLayout.data()
	var lanes := {}
	for lane in MapLayout.LANES:
		var pts: Array = []
		for p in MapLayout.lane_path(lane, Combat.Team.SARADOMIN):
			pts.append([p.x, p.z])
		lanes[lane] = pts
	var camps: Array = []
	for c in MapLayout.all_camps():
		camps.append([c["pos"].x, c["pos"].z])
	var keep_clear: Array = []
	var structures: Array = []
	for team in [Combat.Team.SARADOMIN, Combat.Team.ZAMORAK]:
		for s in MapLayout.structure_layout(team):
			keep_clear.append([s["pos"].x, s["pos"].z])
			structures.append({"team": team, "kind": s["kind"], "tier": s["tier"], "pos": [s["pos"].x, s["pos"].z]})
	for a in MapLayout.all_prayer_altars():
		keep_clear.append([a["pos"].x, a["pos"].z])
	var gates: Array = []
	for g in MapLayout.gates():
		gates.append({"team": g["team"], "pos": [g["pos"].x, g["pos"].z], "size": [g["size"].x, g["size"].y]})
	var out := {
		"_comment": "Written by tools/export_rift_layout.gd from data/map.json (MapLayout). Metres; x east, z south (screen-up is -z). Grids are run-length encoded, row 0 the southern-most row (see data/map.json 'grid').",
		"map_size": MapLayout.MAP_SIZE, "lane_width": MapLayout.LANE_WIDTH, "pit_radius": MapLayout.PIT_RADIUS,
		"saradomin_base": [MapLayout.SARADOMIN_BASE.x, MapLayout.SARADOMIN_BASE.z],
		"zamorak_base": [MapLayout.ZAMORAK_BASE.x, MapLayout.ZAMORAK_BASE.z],
		"saradomin_nexus": [MapLayout.nexus_position(Combat.Team.SARADOMIN).x, MapLayout.nexus_position(Combat.Team.SARADOMIN).z],
		"zamorak_nexus": [MapLayout.nexus_position(Combat.Team.ZAMORAK).x, MapLayout.nexus_position(Combat.Team.ZAMORAK).z],
		"jad_pit": [MapLayout.jad_pit().x, MapLayout.jad_pit().z], "dragon_pit": [MapLayout.dragon_pit().x, MapLayout.dragon_pit().z],
		"cell_m": data["cell_m"], "grid": data["grid"],
		"wall_rle": data["wall_rle"], "brush_rle": data["brush_rle"], "river_rle": data["river_rle"],
		"pit_rle": data["pit_rle"], "base_rle": data["base_rle"],
		"lanes": lanes, "camps": camps, "keep_clear": keep_clear, "structures": structures, "gates": gates,
	}
	var f := FileAccess.open("res://tools/osrs_extract/rift_layout.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("rift layout written")
	quit()
