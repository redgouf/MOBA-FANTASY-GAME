extends Node
## The private OSRS models as a separate file: osrs_models.pck next to the
## game's exe (the personal setup). Loading it here, before anything else,
## makes res://private_assets/osrs/ exist, so OsrsModels finds the models.
## Keeping the models out of the exe means the in-game updater can replace
## the exe with a public release and the models stay: personal setups
## update like everyone else's. The pack is built by tools/pack_osrs_models.gd
## and is never published.

const FILE := "osrs_models.pck"

## True when the models came from osrs_models.pck.
var loaded := false
var path := ""


func _init() -> void:
	if OS.has_feature("editor"):
		return     # the editor reads private_assets/ directly
	path = OS.get_executable_path().get_base_dir().path_join(FILE)
	if FileAccess.file_exists(path):
		loaded = ProjectSettings.load_resource_pack(path, true)
		if not loaded:
			push_warning("ModelPack: couldn't load %s" % path)
