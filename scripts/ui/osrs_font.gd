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
## Font properties a Control can override (what has_theme_font_override checks).
const FONT_NAMES := ["font", "normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]

static var _real: Dictionary = {}       # name -> the bitmap FontFile (the "@any" copy scales to any size)
static var _twins: Dictionary = {}      # real FontFile -> its clean vector stand-in (FontVariation of Godot's font)
## Size-override names that go with each font name.
const SIZE_OF := {"font": "font_size", "normal_font": "normal_font_size", "bold_font": "bold_font_size",
	"italics_font": "italics_font_size", "bold_italics_font": "bold_italics_font_size", "mono_font": "mono_font_size"}
## The vector font is much wider than the pixel one at the same size, so it is
## drawn smaller (this fraction of the pixel size) to fit the same layouts.
const VECTOR_SIZE := 0.72

static var _keys: Dictionary = {}       # real FontFile -> its name key
static var _back: Dictionary = {}       # vector stand-in -> real FontFile
static var active := false
static var _whole_scale := true          # the interface is at a whole-number scale: stay pixel-crisp
static var _scale := 1.0
static var _vector: Font                 # Godot's own font, for text at fractional scales
static var _hooked := false
static var _default_size := -1


## Called with how much bigger (or smaller) than 1600x900 the window is. At 1x
## and 2x the OSRS fonts draw as exact pixels. At any other size (1920x1080 is
## 1.2x, 2560x1440 is 1.6x, 1280x720 is 0.8x) a pixel font can't be both whole
## pixels and the right size, and scaling it smears or mangles the glyphs, so
## body text switches to a clean vector font until the window is a whole
## multiple again. (The big quill headings keep their look: they scale fine.)
## Everything already on screen is switched over; new text gets the right one.
static func set_interface_scale(s: float) -> void:
	_scale = s
	var whole := s >= 0.97 and absf(s - roundf(s)) < 0.03
	if whole == _whole_scale:
		return
	_whole_scale = whole
	if not active:
		return
	_set_defaults()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		_restyle(tree.root)


## True when body text is currently drawn with the clean vector font.
static func using_vector() -> bool:
	return active and not _whole_scale


static func _vector_twin(real: FontFile, key: String) -> Font:
	if _vector == null or key.begins_with("q8"):
		return real
	if not _twins.has(real):
		var v := FontVariation.new()
		v.base_font = _vector
		v.variation_embolden = 0.6 if key.begins_with("b12") else 0.0
		_twins[real] = v
		_back[v] = real
	return _twins[real]


## The font to use for this loaded bitmap font right now.
static func _current(real: FontFile, key: String) -> Font:
	return real if _whole_scale else _vector_twin(real, key)


static func _swap(f: Font) -> Font:
	if f == null:
		return null
	if _whole_scale:
		return _back.get(f, f)
	if f is FontFile and _keys.has(f):
		return _vector_twin(f, _keys[f])
	return f


## The size a text of this requested size should have with the vector font, so
## it comes out about as big as the pixel font would draw it (which only grows
## in whole steps of its 12px, unless it is the any-size copy).
static func _vector_size(size: int, real: FontFile, key: String) -> int:
	var base := float(size)
	if not key.ends_with("@any"):
		var fs := maxi(real.fixed_size, 1)
		base = float(fs * maxi(1, int(size / fs)))
	var f := minf(1.0, VECTOR_SIZE / maxf(minf(_scale, 1.0), 0.78)) if _scale < 1.0 else VECTOR_SIZE
	return maxi(6, roundi(base * f))


static func _restyle(n: Node) -> void:
	if n is Control:
		for fname in FONT_NAMES:
			var sname: String = SIZE_OF[fname]
			var meta := "osrs_px_" + sname
			if n.has_theme_font_override(fname):
				var cur: Font = n.get_theme_font(fname)
				var nf := _swap(cur)
				if nf != cur:
					n.add_theme_font_override(fname, nf)
				cur = nf
			if n.has_theme_font_size_override(sname):
				var real: FontFile = _back.get(n.get_theme_font(fname)) if not _whole_scale else null
				if _whole_scale:
					if n.has_meta(meta):
						n.add_theme_font_size_override(sname, int(n.get_meta(meta)))
						n.remove_meta(meta)
				elif real != null:
					var orig: int = int(n.get_meta(meta)) if n.has_meta(meta) else n.get_theme_font_size(sname)
					n.set_meta(meta, orig)
					n.add_theme_font_size_override(sname, _vector_size(orig, real, _keys[real]))
	elif n is Label3D:
		var cur3: Font = n.font
		var nf3 := _swap(cur3)
		if nf3 != cur3:
			n.font = nf3
		var m3 := "osrs_px_size"
		if _whole_scale:
			if n.has_meta(m3):
				n.font_size = int(n.get_meta(m3))
				n.remove_meta(m3)
		elif _back.has(n.font):
			var orig3: int = int(n.get_meta(m3)) if n.has_meta(m3) else n.font_size
			n.set_meta(m3, orig3)
			var r3: FontFile = _back[n.font]
			n.font_size = _vector_size(orig3, r3, _keys[r3])
	for c in n.get_children():
		_restyle(c)


static func _on_node_added(n: Node) -> void:
	if not _whole_scale and (n is Control or n is Label3D):
		_restyle.call_deferred(n)


static func _load(font_name: String, any_size: bool) -> FontFile:
	var key := font_name + ("@any" if any_size else "")
	if not _real.has(key):
		var path := DIR + font_name + ".fnt"
		var f: FontFile = load(path) if ResourceLoader.exists(path) else null
		if f != null:
			if any_size:
				f = f.duplicate()
			f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED if any_size else TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_real[key] = f
		if f != null:
			_keys[f] = key
	return _real[key]


static func _proxy(font_name: String, any_size: bool) -> Font:
	var real := _load(font_name, any_size)
	if real == null:
		return null
	return _current(real, font_name + ("@any" if any_size else ""))


## Loads a font by name ("p12_full", "b12_full", "q8_full", "p11_full"), or null.
static func get_font(font_name: String) -> Font:
	return _proxy(font_name, false)


## A version that scales to any size (not only whole multiples), for text that
## has to be a bit bigger (the stats panel at 1.5x). Draw it with nearest
## filtering to keep the pixels sharp.
static func get_font_any_size(font_name: String) -> Font:
	return _proxy(font_name, true)


static func _set_defaults() -> void:
	var f := get_font("p12_full")
	if f == null:
		return
	ThemeDB.fallback_font = f                      # Label3D and anything without a theme
	var theme := ThemeDB.get_default_theme()
	theme.default_font = f                         # every Control
	if _default_size < 0:
		_default_size = theme.default_font_size
	var real: FontFile = _back.get(f)
	theme.default_font_size = _default_size if real == null else _vector_size(_default_size, real, _keys[real])


## Switches the whole interface to the OSRS font, when the pack has it.
static func apply() -> bool:
	if not OsrsModels.available():
		return false
	if get_font("p12_full") == null:
		return false
	if _vector == null:
		_vector = ThemeDB.fallback_font            # Godot's built-in font (before ours replaces it)
	active = true
	_set_defaults()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not _hooked:
		_hooked = true
		tree.node_added.connect(_on_node_added)
	return true


## The font for a heading of this size: bold for titles, quill for big ones.
static func heading(size: int) -> Font:
	if not active:
		return null
	return get_font("q8_full") if size >= 30 else get_font("b12_full")
