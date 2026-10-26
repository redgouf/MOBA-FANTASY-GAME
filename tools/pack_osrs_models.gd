extends SceneTree
## Builds osrs_models.pck: only the private OSRS model files (and their
## imported forms), for the personal setup (ModelPack loads it next to the
## exe). Run after an import, from the project folder:
##   godot --headless --path . -s res://tools/pack_osrs_models.gd -- OUT.pck [--all]
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


## The personal export preset's exclude_filter (unused models), plus, for
## packs built by tools/osrs_extract, everything the game doesn't load yet:
## map squares, spell graphics, inventory models, loose textures and sprites,
## and the worn items, NPCs and objects data/models.json doesn't name. The
## dressed Rift (rift/) is always packed.
## Pass --all after the output path to keep everything.
func _excluded_patterns() -> Array[String]:
	var out: Array[String] = []
	if not OS.get_cmdline_user_args().has("--all") and str(OsrsModels.manifest().get("source", "")) == "osrs_extract":
		var cfg_m := OsrsModels.config()
		for d in ["maps", "textures", "sprites"]:
			out.append("private_assets/osrs/%s/*" % d)
		# Spell graphics: only the ones models.json uses.
		var used_gfx := {str(int(cfg_m.get("teleport", {}).get("cast_gfx", 0))): true}
		var gfx_lists: Array = []
		for c in cfg_m.get("champions", {}).values():
			for ab in c.get("abilities", {}).values():
				gfx_lists.append(ab.get("gfx", {}))
		for s in cfg_m.get("spec_weapons", {}).values():
			gfx_lists.append(s.get("gfx", {}))
		while not gfx_lists.is_empty():
			var g: Dictionary = gfx_lists.pop_back()
			for k in g:
				if g[k] is Dictionary:
					gfx_lists.append(g[k])
				elif k in ["cast", "travel", "impact"]:
					used_gfx[str(int(g[k]))] = true
		for f in DirAccess.get_files_at("res://private_assets/osrs/spotanims"):
			if not used_gfx.has(f.get_slice(".", 0)):
				out.append("private_assets/osrs/spotanims/%s" % f)
		var used_items := {}
		for c in cfg_m.get("champions", {}).values():
			for id in c.get("gear", []):
				used_items[str(int(id))] = true
			used_items[str(int(c.get("weapon", 0)))] = true
			for f in c.get("forms", {}).values():
				used_items[str(int(f.get("weapon", 0)))] = true
		for s in cfg_m.get("spec_weapons", {}).values():
			used_items[str(int(s.get("weapon", 0)))] = true
		for c in cfg_m.get("champions", {}).values():
			for ab in c.get("abilities", {}).values():
				used_items[str(int(ab.get("weapon", 0)))] = true
		# Inventory models (items/<id>.glb): only the ones held as props and the Skiller's gems.
		var held := {}
		for c in cfg_m.get("champions", {}).values():
			for prop in c.get("props", []):
				if prop.has("item"):
					held[str(int(prop["item"]))] = true
		for ids in cfg_m.get("gems", {}).values():
			if ids is Array:
				for id in ids:
					held[str(int(id))] = true
		for f in DirAccess.get_files_at("res://private_assets/osrs/items"):
			if not held.has(f.get_slice(".", 0)):
				out.append("private_assets/osrs/items/%s" % f)
		for id in OsrsModels.manifest().get("items", {}):
			if not used_items.has(str(id)):
				out.append("private_assets/osrs/player/items/%s.glb" % id)
		var used_bosses := {}
		for m in cfg_m.get("minions", {}).values():
			used_bosses[str(m.get("model", ""))] = true
			for v in m.get("by_team", []):
				used_bosses[str(v)] = true
		for m in cfg_m.get("monsters", {}).values():
			used_bosses[str(m.get("model", ""))] = true
			used_bosses[str(m.get("fallback", ""))] = true
			for v in m.get("variants", {}).values():
				used_bosses[str(v)] = true
		for b in OsrsModels.manifest().get("bosses", {}):
			if not used_bosses.has(str(b)):
				out.append("private_assets/osrs/bosses/%s.glb" % b)
		var used_objects := {}
		for st in cfg_m.get("structures", {}).values():
			for side in st.values():
				for part in side:
					used_objects[str(int(part.get("object", 0)))] = true
		for id in cfg_m.get("props", {}).values():
			used_objects[str(int(id))] = true
		for o in OsrsModels.manifest().get("objects", {}):
			if not used_objects.has(str(o)):
				out.append("private_assets/osrs/objects/%s.*" % o)
				out.append("private_assets/osrs/objects/%s_*" % o)
		out.append("private_assets/osrs/player/player_animations.glb")
		return out
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
