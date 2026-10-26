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
	# The OSRS pixel font can't be outlined: it gets OSRS's black drop shadow.
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 0)
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


# --- Tooltips ------------------------------------------------------------------

const TOOLTIP_BG := Color(0.1, 0.085, 0.065, 1.0)
const TOOLTIP_WIDTH := 46          # characters per line before wrapping

static var _tooltips_installed := false


## Gives every hover tooltip in the game a solid OSRS-style background
## (by restyling the default theme's TooltipPanel and TooltipLabel).
static func install_tooltip_theme() -> void:
	if _tooltips_installed:
		return
	_tooltips_installed = true
	var t := ThemeDB.get_default_theme()
	# Dark, teal-edged panels that read at a glance (same look as AbilityTooltip).
	var sb := box(Color(0.02, 0.05, 0.06, 0.96), Color(0.24, 0.5, 0.48), 2, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	t.set_stylebox("panel", "TooltipPanel", sb)
	t.set_color("font_color", "TooltipLabel", Color(0.86, 0.87, 0.84))
	t.set_color("font_outline_color", "TooltipLabel", Color(0, 0, 0, 1))
	t.set_constant("outline_size", "TooltipLabel", 0)
	t.set_font_size("font_size", "TooltipLabel", 14)


## Word-wraps text to `width` characters per line, keeping existing line breaks,
## so tooltips never run off as one long line.
static func wrap(text: String, width: int = TOOLTIP_WIDTH) -> String:
	var out: Array[String] = []
	for para in text.split("\n"):
		# Keep a paragraph's indent (tooltip sub-lines like "  Items: +40").
		var indent := para.substr(0, para.length() - para.lstrip(" ").length())
		var line := ""
		for word in para.split(" ", false):
			if line.is_empty():
				line = indent + word
			elif line.length() + 1 + word.length() <= width:
				line += " " + word
			else:
				out.append(line)
				line = word
		out.append(line)
	return "\n".join(out)


## A solid panel style for custom hover popups (Skills tab, scoreboard rows).
static func solid_box() -> StyleBoxFlat:
	return box(TOOLTIP_BG, BORDER_HI, 2, 4)


## A coloured tooltip body (BBCode), sized to fit, on the solid tooltip panel.
static func rich_tooltip(bbcode: String, width: float = 380.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(width, 0)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	r.add_theme_font_size_override("italics_font_size", 13)
	r.add_theme_color_override("default_color", Color.WHITE)
	r.text = bbcode
	return r
