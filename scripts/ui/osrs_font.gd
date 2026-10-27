class_name OsrsFont
extends RefCounted
## The real OSRS interface fonts, from the private model pack
## (private_assets/osrs/ui/fonts, made by tools/osrs_extract's "ui" step):
## p12 ("plain 12") for all text, b12 (bold) for titles and q8 (the quill
## font) for big headings. apply() makes p12 the default font for every
## Control and Label3D; without the pack the game keeps Godot's font.
## They're pixel fonts: drawn at their own size (or whole multiples of it),
## so they stay crisp like in OSRS.

const DIR := "res://private_assets/osrs/ui/fonts/"

static var _fonts: Dictionary = {}
static var active := false
static var _whole_scale := true      # the interface is at a whole-number scale: stay pixel-crisp
static var _small_window := false
static var _scale := 1.0
static var _default_fallback: Font
static var _default_theme_font: Font


## Called with how much bigger (or smaller) than 1600x900 the window is. At 1x,
## 2x... the fonts draw as exact pixels; at any other size (1920x1080 is 1.2x,
## 1280x720 is 0.8x) forcing whole multiples garbles the glyphs, so they scale smoothly.
static func set_interface_scale(s: float) -> void:
	_scale = s
	var whole := s >= 0.97 and absf(s - roundf(s)) < 0.03
	# Smaller than 1600x900 a 12 px pixel font can't be shrunk and stay legible:
	# body text falls back to Godot's own font until the window is big enough.
	var small := s < 0.97
	if active and small != _small_window:
		_small_window = small
		ThemeDB.fallback_font = _default_fallback if small else get_font("p12_full")
		ThemeDB.get_default_theme().default_font = _default_theme_font if small else get_font("p12_full")
	if whole == _whole_scale:
		return
	_whole_scale = whole
	for k in _fonts:
		var f: FontFile = _fonts[k]
		if f != null and not str(k).ends_with("@any"):
			f.fixed_size_scale_mode = _scale_mode()


static func _scale_mode() -> int:
	return TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY if _whole_scale else TextServer.FIXED_SIZE_SCALE_ENABLED


## Loads a font by name ("p12_full", "b12_full", "q8_full", "p11_full"), or null.
static func get_font(font_name: String) -> FontFile:
	if not _fonts.has(font_name):
		var path := DIR + font_name + ".fnt"
		var f: FontFile = load(path) if ResourceLoader.exists(path) else null
		if f != null:
			f.fixed_size_scale_mode = _scale_mode()
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_fonts[font_name] = f
	return _fonts[font_name]


## A copy of a font that scales to any size (not only whole multiples), for
## text that has to be a bit bigger (the stats panel at 1.5x). Draw it with
## nearest filtering to keep the pixels sharp.
static func get_font_any_size(font_name: String) -> FontFile:
	var key := font_name + "@any"
	if not _fonts.has(key):
		var f := get_font(font_name)
		var copy: FontFile = f.duplicate() if f != null else null
		if copy != null:
			copy.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		_fonts[key] = copy
	return _fonts[key]


## Switches the whole interface to the OSRS font, when the pack has it.
static func apply() -> bool:
	if not OsrsModels.available():
		return false
	var f := get_font("p12_full")
	if f == null:
		return false
	_default_fallback = ThemeDB.fallback_font
	_default_theme_font = ThemeDB.get_default_theme().default_font
	ThemeDB.fallback_font = f                      # Label3D and anything without a theme
	ThemeDB.get_default_theme().default_font = f   # every Control
	active = true
	set_interface_scale(_scale)     # the window may have been small before the fonts loaded
	return true


## The font for a heading of this size: bold for titles, quill for big ones.
static func heading(size: int) -> Font:
	if not active:
		return null
	return get_font("q8_full") if size >= 30 else get_font("b12_full")
