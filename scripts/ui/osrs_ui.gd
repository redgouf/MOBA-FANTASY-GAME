class_name OsrsUi
extends RefCounted
## OSRS-style interface pieces drawn in code: brown stone panels with a dark
## rim and a light bevel, recessed slots, stone buttons, and the interface's
## text colours (orange titles, yellow values, white text with a black
## shadow). Textures are generated once (no Jagex art), so they match the
## OSRS look without copying its sprites.

const ORANGE := Color(1.0, 0.596, 0.122)       # #ff981f, OSRS interface titles
const YELLOW := Color(1.0, 1.0, 0.0)
const WHITE := Color(1.0, 1.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0)
const RED := Color(1.0, 0.0, 0.0)
const MUTED := Color(0.75, 0.68, 0.55)

const STONE := Color(0.243, 0.208, 0.161)       # #3e3529, panel face
const STONE_DARK := Color(0.16, 0.135, 0.1)
const STONE_DEEP := Color(0.1, 0.085, 0.065)
const RIM := Color(0.05, 0.04, 0.03)
const BEVEL_HI := Color(0.42, 0.36, 0.27)
const BEVEL_LO := Color(0.13, 0.11, 0.08)

static var _cache: Dictionary = {}


## A 9-slice panel: black rim, light top-left bevel, dark bottom-right
## bevel, and a speckled stone face that tiles.
static func panel_box(face: Color = STONE, rim_px: int = 3) -> StyleBoxTexture:
	var key := "panel:%s:%d" % [face.to_html(), rim_px]
	if not _cache.has(key):
		var n := 48
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for y in n:
			for x in n:
				var c := face
				var v := rng.randf_range(-0.035, 0.035)
				c = Color(c.r + v, c.g + v * 0.9, c.b + v * 0.7, 1.0)
				var edge := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
				if edge == 0:
					c = RIM
				elif edge < rim_px:
					# Light on the top and left edges, dark on the bottom and right.
					var top_left := (x < rim_px and y < n - 1 - x) or (y < rim_px and x < n - 1 - y)
					c = BEVEL_HI if top_left else BEVEL_LO
				img.set_pixel(x, y, c)
		var sb := StyleBoxTexture.new()
		sb.texture = ImageTexture.create_from_image(img)
		sb.set_texture_margin_all(rim_px + 1)
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.set_content_margin_all(rim_px + 6)
		_cache[key] = sb
	return _cache[key]


## A recessed slot (equipment slots, portrait frames): dark inside, shadow on
## the top-left edge, light on the bottom-right.
static func slot_box(face: Color = STONE_DEEP, hover: bool = false, picked: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = face
	sb.border_color = Color(0.85, 0.72, 0.36) if picked else (BEVEL_HI.lightened(0.25) if hover else Color(0.3, 0.26, 0.19))
	sb.set_border_width_all(2 if picked else 1)
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 2 if not picked else 6
	sb.set_content_margin_all(2)
	return sb


## OSRS stone button faces (normal / hover / pressed / disabled).
static func button_box(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match state:
		"hover":
			sb.bg_color = Color(0.36, 0.3, 0.22)
		"pressed":
			sb.bg_color = Color(0.2, 0.17, 0.12)
		"disabled":
			sb.bg_color = Color(0.2, 0.18, 0.15)
		_:
			sb.bg_color = Color(0.3, 0.255, 0.19)
	sb.border_color = RIM
	sb.set_border_width_all(2)
	sb.border_width_top = 2
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 3 if state != "pressed" else 1
	sb.set_content_margin_all(6)
	return sb


static func style_button(b: Button, font_size: int = 16, color: Color = ORANGE) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, button_box("normal" if st == "focus" else st))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color.lightened(0.25))
	b.add_theme_color_override("font_pressed_color", color.darkened(0.15))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.45, 0.38))
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 4)
	b.focus_mode = Control.FOCUS_NONE


## A panel placed at a fixed rect (the select screen never reflows).
static func panel(parent: Control, rect: Rect2, face: Color = STONE) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", panel_box(face))
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	return p


## Text with the OSRS black drop shadow.
static func text(parent: Node, s: String, size: int = 14, color: Color = WHITE, rect: Rect2 = Rect2()) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	if size >= 18 and OsrsFont.heading(size) != null:
		l.add_theme_font_override("font", OsrsFont.heading(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rect.size != Vector2.ZERO:
		l.position = rect.position
		l.size = rect.size
		l.clip_text = true
	parent.add_child(l)
	return l


## An orange panel title, centred along the top of a panel.
static func title(parent: Control, s: String, size: int = 16) -> Label:
	var l := text(parent, s, size, ORANGE, Rect2(8, 6, parent.size.x - 16, size + 8))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A thin dark divider line inside a panel.
static func divider(parent: Control, y: float, inset: float = 10.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.08, 0.065, 0.05, 0.9)
	r.position = Vector2(inset, y)
	r.size = Vector2(parent.size.x - inset * 2.0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	var hi := ColorRect.new()
	hi.color = Color(0.4, 0.34, 0.25, 0.6)
	hi.position = Vector2(inset, y + 2)
	hi.size = Vector2(parent.size.x - inset * 2.0, 1)
	hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hi)
	return r
