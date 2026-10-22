extends SceneTree
## Trims the private OSRS pack's 516-clip animation library (49 MB) down to
## the clips data/models.json uses, saved to private_assets/osrs/baked/.
## Run after changing data/models.json:
##   godot --headless --path . -s tools/bake_osrs_clips.gd


func _init() -> void:
	if not OsrsModels.available():
		print("[bake] no OSRS pack in private_assets/osrs; nothing to do")
		quit(0)
		return
	var names := OsrsModels.required_clips()
	var lib := OsrsModels.build_clip_library(names)
	var missing: Array[String] = []
	for n in names:
		if not lib.has_animation(n):
			missing.append(n)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://private_assets/osrs/baked"))
	var err := ResourceSaver.save(lib, OsrsModels.CLIPS_PATH, ResourceSaver.FLAG_COMPRESS)
	print("[bake] %d clips saved to %s (err %d); missing: %s" % [lib.get_animation_list().size(), OsrsModels.CLIPS_PATH, err, str(missing)])
	quit(0 if err == OK and missing.is_empty() else 1)
