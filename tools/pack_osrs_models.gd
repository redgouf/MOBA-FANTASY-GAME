extends SceneTree
## Builds osrs_models.pck: only the private OSRS model files (and their
## imported forms), for the personal setup (ModelPack loads it next to the
## exe). Run after an import, from the project folder:
##   godot --headless --path . -s res://tools/pack_osrs_models.gd -- OUT.pck
## Files the personal export preset leaves out (unused models) stay out.
## Never publish the result.

const ROOT := "res://private_assets/osrs"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := str(args[0]) if args.size() > 0 else "osrs_models.pck"
	var skip := _excluded_patterns()
	var packer := PCKPacker.new()
	if packer.pck_start(out) != OK:
		printerr("pack_osrs_models: can't write %s" % out)
		quit(1)
		return
	var files := 0
	for f in _walk(ROOT):
		var rel := f.trim_prefix("res://")
		var src_rel := rel.trim_suffix(".import")
		var excluded := false
		for p in skip:
			if src_rel.match(p):
				excluded = true
		if excluded or f.get_file() == "README.md":
			continue
		if f.ends_with(".import"):
			# The remap file plus whatever it was imported to (.godot/imported).
			var cfg := ConfigFile.new()
			if cfg.load(f) != OK:
				continue
			packer.add_file(f, ProjectSettings.globalize_path(f))
			files += 1
			for dest in cfg.get_value("deps", "dest_files", []):
				packer.add_file(str(dest), ProjectSettings.globalize_path(str(dest)))
				files += 1
		elif not FileAccess.file_exists(f + ".import"):
			packer.add_file(f, ProjectSettings.globalize_path(f))   # plain files: manifest, baked clips
			files += 1
	packer.flush()
	print("pack_osrs_models: %d files -> %s" % [files, out])
	quit(0)


func _walk(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		out.append(dir.path_join(name))
	for sub in d.get_directories():
		out.append_array(_walk(dir.path_join(sub)))
	return out


## The personal export preset's exclude_filter (unused models).
func _excluded_patterns() -> Array[String]:
	var out: Array[String] = []
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return out
	for section in cfg.get_sections():
		if str(cfg.get_value(section, "name", "")).contains("personal"):
			for p in str(cfg.get_value(section, "exclude_filter", "")).split(","):
				var pat := p.strip_edges()
				if pat.begins_with("private_assets"):
					out.append(pat)
	return out
