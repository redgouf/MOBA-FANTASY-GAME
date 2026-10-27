extends Node
## Player settings, saved to user://settings.cfg and applied at startup.

signal changed

const PATH := "user://settings.cfg"

var edge_pan := true
var pan_speed := 1.0           # multiplier for keyboard and edge panning
var drag_pan_speed := 1.0      # multiplier for middle-mouse drag panning
var fullscreen := false
var show_fps := true

## Video. The window sizes offered for windowed play (only those that fit the screen).
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
## The dropdown's last entry is the screen's own size: RESOLUTIONS.size() in `resolution`.
const NATIVE := 6
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]
const MSAA_NAMES := ["Off", "2x", "4x", "8x"]
const SHADOW_NAMES := ["Off", "Low", "Medium", "High"]
const FOLIAGE_NAMES := ["Low", "Medium", "High"]
const PARTICLE_NAMES := ["Off", "Low", "Medium", "High"]
const RENDER_SCALES := [50, 60, 75, 85, 100]
## Quality presets: render scale (%), anti-aliasing, shadows, foliage, particles.
const PRESETS := [
	{"render_scale": 75, "msaa": 0, "shadows": 1, "foliage": 0, "particles": 1},
	{"render_scale": 100, "msaa": 1, "shadows": 2, "foliage": 1, "particles": 2},
	{"render_scale": 100, "msaa": 1, "shadows": 2, "foliage": 2, "particles": 3},
	{"render_scale": 100, "msaa": 2, "shadows": 3, "foliage": 2, "particles": 3},
]
const GRAPHICS_KEYS := ["render_scale", "msaa", "shadows", "foliage", "particles"]
const PARTICLE_FRACTION := [0.0, 0.35, 0.65, 1.0]
const SHADOW_ATLAS := [0, 2048, 4096, 8192]
var resolution := NATIVE       # index into RESOLUTIONS, or NATIVE (the screen's size)
var vsync := true
var quality := 2               # QUALITY_NAMES index (4 = custom mix)
var render_scale := 100        # 3D resolution, percent (the interface is always sharp)
var msaa := 1                  # MSAA_NAMES index
var shadows := 2
var foliage := 2               # Low hides ground clutter, Medium stops it casting shadows
var particles := 3
var _window_dirty := true

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
## The splash screen checks for a new version and installs it by itself.
var auto_update := true
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
	# (resolution_v2: v0.32 saved a plain window size under "resolution", which in
	# fullscreen would have rendered everything at 1600x900)
	resolution = clampi(int(cfg.get_value("video", "resolution_v2", resolution)), 0, NATIVE)
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	render_scale = int(cfg.get_value("video", "render_scale", render_scale))
	msaa = clampi(int(cfg.get_value("video", "msaa", msaa)), 0, MSAA_NAMES.size() - 1)
	shadows = clampi(int(cfg.get_value("video", "shadows", shadows)), 0, SHADOW_NAMES.size() - 1)
	foliage = clampi(int(cfg.get_value("video", "foliage", foliage)), 0, FOLIAGE_NAMES.size() - 1)
	particles = clampi(int(cfg.get_value("video", "particles", particles)), 0, PARTICLE_NAMES.size() - 1)
	quality = detect_quality()
	# (v0.9 made normal cast the default; the key changed so older saves pick it up)
	cast_mode = clampi(int(cfg.get_value("controls", "cast_mode_v2", cast_mode)), 0, CAST_MODE_NAMES.size() - 1)
	auto_update = bool(cfg.get_value("updates", "auto_update", auto_update))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("camera", "edge_pan", edge_pan)
	cfg.set_value("camera", "pan_speed", pan_speed)
	cfg.set_value("camera", "drag_pan_speed", drag_pan_speed)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "resolution_v2", resolution)
	cfg.set_value("video", "vsync", vsync)
	for k in GRAPHICS_KEYS:
		cfg.set_value("video", k, get(k))
	cfg.set_value("controls", "cast_mode_v2", cast_mode)
	cfg.set_value("updates", "auto_update", auto_update)
	cfg.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
			_window_dirty = true
		if not fullscreen and _window_dirty:
			_apply_window_size()
		_window_dirty = false
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if is_inside_tree():
		var root := get_tree().root
		root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(msaa, 0, 3)]
		root.scaling_3d_scale = clampf(float(render_scale) / 100.0 * fullscreen_scale(), 0.25, 1.0)
		if not root.size_changed.is_connected(_on_window_resized):
			root.size_changed.connect(_on_window_resized)
		_on_window_resized()
		apply_shadows()
	changed.emit()


## The OSRS pixel fonts are only crisp at whole-number scales: when the window
## isn't a whole multiple of the 1600x900 interface, scale them smoothly instead.
func _on_window_resized() -> void:
	var size := Vector2(get_tree().root.size)
	OsrsFont.set_interface_scale(minf(size.x / 1600.0, size.y / 900.0))


func _apply_window_size() -> void:
	var screen := DisplayServer.screen_get_size()
	if resolution >= NATIVE:
		# The screen's own size: a maximised window.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var want := RESOLUTIONS[clampi(resolution, 0, RESOLUTIONS.size() - 1)]
	if want.x > screen.x or want.y > screen.y:
		want = Vector2i(mini(want.x, screen.x), mini(want.y, screen.y))
	DisplayServer.window_set_size(want)
	var origin := DisplayServer.screen_get_position()
	DisplayServer.window_set_position(origin + (screen - want) / 2)


## Fullscreen always fills the monitor, so the chosen resolution sets how
## sharp the 3D view is: it renders at that size and is stretched to fit (the
## interface stays pixel-sharp at the monitor's own size). 1.0 when windowed or native.
func fullscreen_scale() -> float:
	if not fullscreen or resolution >= NATIVE or DisplayServer.get_name() == "headless":
		return 1.0
	var screen := DisplayServer.screen_get_size()
	if screen.y <= 0:
		return 1.0
	return minf(1.0, float(RESOLUTIONS[resolution].y) / float(screen.y))


## Resolutions that fit this screen (the smallest always), then the screen's own (NATIVE).
func available_resolutions() -> Array[int]:
	var out: Array[int] = []
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(99999, 99999)
	for i in RESOLUTIONS.size():
		if i == 0 or (RESOLUTIONS[i].x < screen.x and RESOLUTIONS[i].y < screen.y):
			out.append(i)
	out.append(NATIVE)
	return out


## "1920 x 1080", or "Native (2560 x 1440)".
func resolution_name(i: int) -> String:
	if i >= NATIVE:
		var s := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(0, 0)
		return "Native (%d x %d)" % [s.x, s.y] if s.x > 0 else "Native"
	return "%d x %d" % [RESOLUTIONS[i].x, RESOLUTIONS[i].y]


## Sun shadows: size and softness of the shadow map, or none (called again by
## the map when it builds its light).
func apply_shadows() -> void:
	if not is_inside_tree():
		return
	var level := clampi(shadows, 0, 3)
	if level > 0:
		RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[level], true)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][level])
	for sun in get_tree().get_nodes_in_group("sun"):
		(sun as Light3D).shadow_enabled = level > 0


## How many particles of a `base` count to spawn (0 = none at all).
func particle_count(base: int) -> int:
	var f: float = PARTICLE_FRACTION[clampi(particles, 0, 3)]
	return 0 if f <= 0.0 else maxi(1, roundi(float(base) * f))


func particles_on() -> bool:
	return particles > 0


## The preset the current graphics choices match, or Custom (4).
func detect_quality() -> int:
	for i in PRESETS.size():
		var same := true
		for k in GRAPHICS_KEYS:
			same = same and int(get(k)) == int(PRESETS[i][k])
		if same:
			return i
	return QUALITY_NAMES.size() - 1


func set_quality(index: int) -> void:
	if index >= 0 and index < PRESETS.size():
		for k in GRAPHICS_KEYS:
			set(k, PRESETS[index][k])
	quality = detect_quality() if index >= PRESETS.size() else index
	apply()
	save_settings()


func set_value(key: String, value: Variant) -> void:
	if key == "quality":
		set_quality(int(value))
		return
	set(key, value)
	if key == "resolution" or key == "fullscreen":
		_window_dirty = true
	if key in GRAPHICS_KEYS:
		quality = detect_quality()
	apply()
	save_settings()
