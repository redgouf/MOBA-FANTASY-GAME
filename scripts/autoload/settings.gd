extends Node
## Player settings, saved to user://settings.cfg and applied at startup.

signal changed

const PATH := "user://settings.cfg"

var edge_pan := true
var pan_speed := 1.0           # multiplier for keyboard and edge panning
var drag_pan_speed := 1.0      # multiplier for middle-mouse drag panning
var fullscreen := false
var show_fps := true

## How Q/W/E/R and item actives cast (League of Legends' three modes):
const CAST_QUICK_INDICATOR := 0   # hold the key to aim with an indicator, release to cast
const CAST_NORMAL := 1            # press the key to aim, left-click to cast; right-click cancels and moves (Esc cancels)
const CAST_QUICK := 2             # cast at the cursor the moment the key is pressed
const CAST_MODE_NAMES := ["Quick cast with indicator (hold, release)", "Normal cast (press, then left-click)", "Quick cast (no indicator)"]
var cast_mode := CAST_NORMAL

## What the next scene load should start (set by the ESC menu):
## pending_mode "" = champion select, "play" = play pending_champion,
## "spectate" = NPC vs NPC.
## The splash screen shows once per session (not again on restart).
var splash_seen := false
var pending_mode := ""
var pending_champion := ""
var pending_prayer := ""        # prayer id picked at champion select ("" = the build's default)


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	edge_pan = bool(cfg.get_value("camera", "edge_pan", edge_pan))
	pan_speed = float(cfg.get_value("camera", "pan_speed", pan_speed))
	drag_pan_speed = float(cfg.get_value("camera", "drag_pan_speed", drag_pan_speed))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	show_fps = bool(cfg.get_value("video", "show_fps", show_fps))
	# (v0.9 made normal cast the default; the key changed so older saves pick it up)
	cast_mode = clampi(int(cfg.get_value("controls", "cast_mode_v2", cast_mode)), 0, CAST_MODE_NAMES.size() - 1)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("camera", "edge_pan", edge_pan)
	cfg.set_value("camera", "pan_speed", pan_speed)
	cfg.set_value("camera", "drag_pan_speed", drag_pan_speed)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("controls", "cast_mode_v2", cast_mode)
	cfg.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	changed.emit()


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save_settings()
