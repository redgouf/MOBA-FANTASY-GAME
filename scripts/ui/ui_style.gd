class_name UiStyle
extends RefCounted
## Shared colours and widget factories for the HUD, loosely based on the
## OSRS interface: dark brown stone panels, tan borders, orange titles.

const BG := Color(0.16, 0.135, 0.105, 0.94)
const BG_DARK := Color(0.08, 0.068, 0.055, 0.96)
const BG_SLOT := Color(0.24, 0.205, 0.16, 1.0)
const BORDER := Color(0.47, 0.4, 0.28)
const BORDER_HI := Color(0.85, 0.7, 0.35)
const TITLE := Color(1.0, 0.6, 0.12)
const TEXT := Color(0.96, 0.91, 0.78)
const MUTED := Color(0.7, 0.64, 0.53)
const GOLD := Color(1.0, 0.86, 0.3)
const HP := Color(0.2, 0.72, 0.22)
const HP_ENEMY := Color(0.86, 0.22, 0.16)
const PRAYER := Color(0.3, 0.72, 0.95)
const SPEC := Color(0.95, 0.78, 0.15)
const XP := Color(0.62, 0.42, 0.95)


static func box(bg: Color, border: Color = BORDER, width: int = 2, radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Anchors a control to a corner/edge preset and places it at an offset
## from that anchor point (e.g. BOTTOM_LEFT + (8, -200) = 8 px from the left,
## 200 px above the bottom). Works at any window size.
static func place(c: Control, preset: int, offset: Vector2, size: Vector2) -> void:
	c.set_anchors_preset(preset, false)
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y


## Makes a control fill its parent, with optional insets.
static func fill(c: Control, left: float = 0.0, top: float = 0.0, right: float = 0.0, bottom: float = 0.0) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = -right
	c.offset_bottom = -bottom


## A plain Panel positioned by anchors (children are placed by hand).
static func panel(parent: Control, preset: int, pos: Vector2, size: Vector2, bg: Color = BG) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(bg))
	parent.add_child(p)
	place(p, preset, pos, size)
	return p


static func label(parent: Node, text: String, font_size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func button(parent: Node, text: String, font_size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TITLE)
	b.add_theme_stylebox_override("normal", box(BG_SLOT, BORDER))
	b.add_theme_stylebox_override("hover", box(BG_SLOT.lightened(0.1), BORDER_HI))
	b.add_theme_stylebox_override("pressed", box(BG_DARK, BORDER_HI))
	b.add_theme_stylebox_override("disabled", box(BG_DARK, BORDER.darkened(0.3)))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), BORDER_HI))
	parent.add_child(b)
	return b


## Two-letter abbreviation for small item slots ("Dragon claws" -> "DC").
static func short_name(item_name: String) -> String:
	var words := item_name.replace("'", "").replace("(", "").replace(")", "").split(" ", false)
	if words.size() == 1:
		return words[0].substr(0, 5).capitalize()
	var out := ""
	for w in words:
		if out.length() < 3:
			out += w.substr(0, 1).to_upper()
	return out
