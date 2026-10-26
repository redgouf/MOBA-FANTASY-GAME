class_name SkillIcons
extends RefCounted
## Simple vector icons for the combat skills, drawn in the spirit of the
## OSRS Skills tab (sword, heart, fist, shield, bow, prayer star, wizard hat).
## Drawn from shapes rather than copied sprites.

const STEEL := Color(0.78, 0.8, 0.84)
const OUTLINE := Color(0.05, 0.04, 0.03)

## Every skill that has an OSRS icon (ui/sprites/<skill>.png).
const SKILLS: Array[String] = [
	"attack", "strength", "defence", "ranged", "prayer", "magic", "hitpoints", "agility", "herblore",
	"thieving", "crafting", "fletching", "mining", "smithing", "fishing", "cooking", "firemaking",
	"woodcutting", "runecraft", "slayer", "farming", "construction", "hunter", "sailing",
]
const TEXT_ICON_PX := 18


## Item text names a skill as {strength}, {ranged}...: shown as the OSRS icon
## where text can show pictures (tooltips, the shop), as the plain name where
## it can't, and as the name when the model pack isn't installed.
static func has_icon(skill: String) -> bool:
	return OsrsSprites.get_sprite(skill) != null


## BBCode for a skill: its icon, or its capitalised name without the pack.
static func tag(skill: String, px: int = TEXT_ICON_PX) -> String:
	if not has_icon(skill):
		return skill.capitalize()
	return "[img=%dx%d]%s%s.png[/img]" % [px, px, OsrsSprites.DIR, skill]


## Turns {skill} markers into BBCode icons. `escape` first makes any "[" in
## plain text literal (skip it when the text is already BBCode).
static func markup(text: String, escape: bool = true, px: int = TEXT_ICON_PX) -> String:
	if escape:
		text = text.replace("[", "[lb]")
	for skill in SKILLS:
		text = text.replace("{%s}" % skill, tag(skill, px))
	return text


## The same text with the plain skill names ("{strength}" becomes "Strength").
static func plain(text: String) -> String:
	for skill in SKILLS:
		text = text.replace("{%s}" % skill, skill.capitalize())
	return text


## The hover tooltip for item text: coloured, with skill icons. Controls that
## show item text return this from _make_custom_tooltip.
static func make_tooltip(for_text: String) -> Control:
	var font := ThemeDB.fallback_font
	var widest := 0.0
	for line in plain(for_text).split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var r := UiStyle.rich_tooltip(markup(for_text), clampf(widest + 26.0, 150.0, 400.0))
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


static func draw_icon(c: CanvasItem, skill: String, center: Vector2, s: float) -> void:
	match skill:
		"attack":
			_attack(c, center, s)
		"hitpoints":
			_heart(c, center, s)
		"strength":
			_fist(c, center, s)
		"defence":
			_shield(c, center, s)
		"ranged":
			_bow(c, center, s)
		"prayer":
			_prayer(c, center, s)
		"magic":
			_hat(c, center, s)
		"mining":
			_pickaxe(c, center, s)
		"agility":
			_runner(c, center, s)
		"smithing":
			_anvil(c, center, s)
		"herblore":
			_herb(c, center, s)
		"fishing":
			_fish(c, center, s)
		"thieving":
			_mask(c, center, s)
		"cooking":
			_chef_hat(c, center, s)
		"crafting":
			_chisel(c, center, s)
		"firemaking":
			_flame(c, center, s)
		"fletching":
			_arrows(c, center, s)
		"woodcutting":
			_tree(c, center, s)
		"runecraft":
			_rune(c, center, s)
		"slayer":
			_skull(c, center, s)
		"farming":
			_watering_can(c, center, s)
		"construction":
			_house(c, center, s)
		"hunter":
			_paw(c, center, s)
		"sailing":
			_anchor(c, center, s)


static func _poly(c: CanvasItem, pts: PackedVector2Array, fill: Color) -> void:
	c.draw_colored_polygon(pts, fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	c.draw_polyline(outline, OUTLINE, 1.5)


static func _attack(c: CanvasItem, o: Vector2, s: float) -> void:
	# A sword pointing up-right with a gold hilt.
	var tip := o + Vector2(s * 0.85, -s * 0.85)
	var base := o + Vector2(-s * 0.35, s * 0.35)
	c.draw_line(base, tip, OUTLINE, 6.0)
	c.draw_line(base, tip, STEEL, 3.5)
	c.draw_line(o + Vector2(-s * 0.65, 0.0), o + Vector2(0.0, s * 0.65), OUTLINE, 5.0)
	c.draw_line(o + Vector2(-s * 0.6, 0.05 * s), o + Vector2(-0.05 * s, s * 0.6), Color(0.85, 0.65, 0.2), 3.0)
	c.draw_line(base, o + Vector2(-s * 0.8, s * 0.8), Color(0.45, 0.28, 0.12), 4.0)


static func _heart(c: CanvasItem, o: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var t := TAU * float(i) / 32.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(o + Vector2(x, y) * (s / 17.0))
	_poly(c, pts, Color(0.86, 0.1, 0.1))
	c.draw_circle(o + Vector2(-s * 0.35, -s * 0.35), s * 0.12, Color(1, 0.6, 0.6))


static func _fist(c: CanvasItem, o: Vector2, s: float) -> void:
	var skin := Color(0.85, 0.6, 0.42)
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.7, -s * 0.4), o + Vector2(s * 0.6, -s * 0.55),
		o + Vector2(s * 0.75, s * 0.25), o + Vector2(s * 0.2, s * 0.85), o + Vector2(-s * 0.55, s * 0.6)]), skin)
	for i in 3:
		var x := -s * 0.35 + float(i) * s * 0.35
		c.draw_line(o + Vector2(x, -s * 0.45), o + Vector2(x + s * 0.05, s * 0.05), OUTLINE, 1.2)
	c.draw_line(o + Vector2(-s * 0.55, s * 0.1), o + Vector2(s * 0.2, s * 0.2), OUTLINE, 1.2)


static func _shield(c: CanvasItem, o: Vector2, s: float) -> void:
	var pts := PackedVector2Array([o + Vector2(-s * 0.75, -s * 0.85), o + Vector2(s * 0.75, -s * 0.85),
		o + Vector2(s * 0.7, s * 0.1), o + Vector2(0.0, s * 0.95), o + Vector2(-s * 0.7, s * 0.1)])
	_poly(c, pts, Color(0.55, 0.57, 0.62))
	c.draw_line(o + Vector2(0, -s * 0.75), o + Vector2(0, s * 0.8), Color(0.3, 0.3, 0.34), 2.0)
	c.draw_line(o + Vector2(-s * 0.62, -s * 0.2), o + Vector2(s * 0.62, -s * 0.2), Color(0.3, 0.3, 0.34), 2.0)


static func _bow(c: CanvasItem, o: Vector2, s: float) -> void:
	var wood := Color(0.55, 0.36, 0.16)
	c.draw_arc(o + Vector2(s * 0.45, 0), s * 0.95, PI * 0.62, PI * 1.38, 16, OUTLINE, 5.0)
	c.draw_arc(o + Vector2(s * 0.45, 0), s * 0.95, PI * 0.62, PI * 1.38, 16, wood, 3.0)
	var top := o + Vector2(s * 0.45, 0) + Vector2(cos(PI * 0.62), sin(PI * 0.62)) * s * 0.95
	var bot := o + Vector2(s * 0.45, 0) + Vector2(cos(PI * 1.38), sin(PI * 1.38)) * s * 0.95
	c.draw_line(top, bot, Color(0.9, 0.9, 0.85), 1.0)
	c.draw_line(o + Vector2(-s * 0.6, 0), o + Vector2(s * 0.95, 0), Color(0.75, 0.7, 0.6), 1.8)
	_poly(c, PackedVector2Array([o + Vector2(s * 0.95, 0), o + Vector2(s * 0.7, -s * 0.15), o + Vector2(s * 0.7, s * 0.15)]), STEEL)


static func _prayer(c: CanvasItem, o: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0 - PI * 0.5
		var r := s * (0.95 if i % 4 == 0 else (0.5 if i % 2 == 0 else 0.3))
		pts.append(o + Vector2(cos(a), sin(a)) * r)
	_poly(c, pts, Color(0.97, 0.97, 0.92))
	c.draw_circle(o, s * 0.18, Color(0.85, 0.85, 1.0))


static func _hat(c: CanvasItem, o: Vector2, s: float) -> void:
	var blue := Color(0.2, 0.3, 0.85)
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.95, s * 0.6), o + Vector2(s * 0.95, s * 0.6),
		o + Vector2(s * 0.7, s * 0.85), o + Vector2(-s * 0.7, s * 0.85)]), blue.darkened(0.2))
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.55, s * 0.62), o + Vector2(s * 0.55, s * 0.62),
		o + Vector2(s * 0.2, -s * 0.5), o + Vector2(s * 0.55, -s * 0.95), o + Vector2(-s * 0.1, -s * 0.6)]), blue)
	c.draw_circle(o + Vector2(-s * 0.05, s * 0.05), s * 0.12, Color(1.0, 0.9, 0.3))


static func _pickaxe(c: CanvasItem, o: Vector2, s: float) -> void:
	c.draw_line(o + Vector2(-s * 0.6, s * 0.85), o + Vector2(s * 0.35, -s * 0.4), Color(0.5, 0.32, 0.15), 4.0)
	var head := PackedVector2Array([o + Vector2(-s * 0.55, -s * 0.75), o + Vector2(s * 0.1, -s * 0.55),
		o + Vector2(s * 0.85, s * 0.15), o + Vector2(s * 0.3, -s * 0.25), o + Vector2(-s * 0.1, -s * 0.35)])
	_poly(c, head, STEEL)


static func _runner(c: CanvasItem, o: Vector2, s: float) -> void:
	var col := Color(0.95, 0.95, 0.9)
	c.draw_circle(o + Vector2(s * 0.3, -s * 0.7), s * 0.22, col)
	c.draw_line(o + Vector2(s * 0.2, -s * 0.45), o + Vector2(-s * 0.1, s * 0.2), col, 3.0)
	c.draw_line(o + Vector2(-s * 0.1, s * 0.2), o + Vector2(s * 0.45, s * 0.85), col, 3.0)
	c.draw_line(o + Vector2(-s * 0.1, s * 0.2), o + Vector2(-s * 0.7, s * 0.6), col, 3.0)
	c.draw_line(o + Vector2(s * 0.12, -s * 0.25), o + Vector2(s * 0.7, -s * 0.05), col, 3.0)
	c.draw_line(o + Vector2(s * 0.12, -s * 0.25), o + Vector2(-s * 0.55, -s * 0.3), col, 3.0)


static func _anvil(c: CanvasItem, o: Vector2, s: float) -> void:
	var iron := Color(0.45, 0.46, 0.5)
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.95, -s * 0.2), o + Vector2(s * 0.8, -s * 0.2),
		o + Vector2(s * 0.6, s * 0.15), o + Vector2(-s * 0.55, s * 0.15)]), iron)
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.25, s * 0.15), o + Vector2(s * 0.25, s * 0.15),
		o + Vector2(s * 0.5, s * 0.75), o + Vector2(-s * 0.5, s * 0.75)]), iron.darkened(0.2))
	c.draw_line(o + Vector2(s * 0.1, -s * 0.95), o + Vector2(s * 0.6, -s * 0.45), Color(0.5, 0.32, 0.15), 3.0)
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.05, -s * 0.85), o + Vector2(s * 0.25, -s * 1.0),
		o + Vector2(s * 0.4, -s * 0.75), o + Vector2(s * 0.1, -s * 0.6)]), STEEL)


static func _herb(c: CanvasItem, o: Vector2, s: float) -> void:
	var green := Color(0.25, 0.7, 0.25)
	c.draw_line(o + Vector2(0, s * 0.9), o + Vector2(0, -s * 0.5), Color(0.2, 0.5, 0.2), 2.0)
	for side in [-1.0, 1.0]:
		for k in 2:
			var y := -s * 0.3 + float(k) * s * 0.5
			_poly(c, PackedVector2Array([o + Vector2(0, y), o + Vector2(side * s * 0.75, y - s * 0.35),
				o + Vector2(side * s * 0.35, y + s * 0.1)]), green)
	_poly(c, PackedVector2Array([o + Vector2(0, -s * 0.95), o + Vector2(s * 0.25, -s * 0.45), o + Vector2(-s * 0.25, -s * 0.45)]), green.lightened(0.2))


static func _fish(c: CanvasItem, o: Vector2, s: float) -> void:
	var body := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		body.append(o + Vector2(cos(a) * s * 0.7 - s * 0.1, sin(a) * s * 0.38))
	_poly(c, body, Color(0.45, 0.65, 0.85))
	_poly(c, PackedVector2Array([o + Vector2(s * 0.55, 0), o + Vector2(s * 0.98, -s * 0.4), o + Vector2(s * 0.98, s * 0.4)]), Color(0.35, 0.55, 0.8))
	c.draw_circle(o + Vector2(-s * 0.5, -s * 0.08), s * 0.08, OUTLINE)


static func _mask(c: CanvasItem, o: Vector2, s: float) -> void:
	var pts := PackedVector2Array([o + Vector2(-s * 0.95, -s * 0.35), o + Vector2(s * 0.95, -s * 0.35),
		o + Vector2(s * 0.8, s * 0.3), o + Vector2(s * 0.15, s * 0.2), o + Vector2(0, s * 0.35),
		o + Vector2(-s * 0.15, s * 0.2), o + Vector2(-s * 0.8, s * 0.3)])
	_poly(c, pts, Color(0.12, 0.12, 0.14))
	c.draw_circle(o + Vector2(-s * 0.42, -s * 0.03), s * 0.17, Color(0.85, 0.85, 0.8))
	c.draw_circle(o + Vector2(s * 0.42, -s * 0.03), s * 0.17, Color(0.85, 0.85, 0.8))


static func _chef_hat(c: CanvasItem, o: Vector2, s: float) -> void:
	var white := Color(0.97, 0.97, 0.95)
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.5, s * 0.2), o + Vector2(s * 0.5, s * 0.2),
		o + Vector2(s * 0.5, s * 0.85), o + Vector2(-s * 0.5, s * 0.85)]), white)
	for x in [-0.45, 0.0, 0.45]:
		c.draw_circle(o + Vector2(x * s, -s * 0.2), s * 0.42, OUTLINE)
	for x in [-0.45, 0.0, 0.45]:
		c.draw_circle(o + Vector2(x * s, -s * 0.2), s * 0.38, white)


static func _chisel(c: CanvasItem, o: Vector2, s: float) -> void:
	c.draw_line(o + Vector2(-s * 0.85, s * 0.85), o + Vector2(-s * 0.05, s * 0.05), Color(0.5, 0.32, 0.15), 5.0)
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.15, s * 0.0), o + Vector2(s * 0.05, -s * 0.2),
		o + Vector2(s * 0.9, -s * 0.85), o + Vector2(s * 0.75, -s * 0.6)]), STEEL)
	c.draw_circle(o + Vector2(s * 0.45, s * 0.5), s * 0.28, Color(0.3, 0.75, 0.9))


static func _flame(c: CanvasItem, o: Vector2, s: float) -> void:
	_poly(c, PackedVector2Array([o + Vector2(0, -s), o + Vector2(s * 0.55, -s * 0.1), o + Vector2(s * 0.5, s * 0.55),
		o + Vector2(0, s * 0.9), o + Vector2(-s * 0.5, s * 0.55), o + Vector2(-s * 0.55, -s * 0.1), o + Vector2(-s * 0.2, -s * 0.35)]),
		Color(1.0, 0.45, 0.08))
	_poly(c, PackedVector2Array([o + Vector2(0, -s * 0.3), o + Vector2(s * 0.28, s * 0.3), o + Vector2(0, s * 0.7),
		o + Vector2(-s * 0.28, s * 0.3)]), Color(1.0, 0.85, 0.25))


static func _arrows(c: CanvasItem, o: Vector2, s: float) -> void:
	for k in 2:
		var off := Vector2(float(k) * s * 0.35, float(k) * s * 0.1)
		c.draw_line(o + off + Vector2(-s * 0.8, s * 0.8), o + off + Vector2(s * 0.6, -s * 0.6), Color(0.6, 0.45, 0.25), 2.5)
		_poly(c, PackedVector2Array([o + off + Vector2(s * 0.75, -s * 0.75), o + off + Vector2(s * 0.42, -s * 0.62),
			o + off + Vector2(s * 0.62, -s * 0.42)]), STEEL)
		_poly(c, PackedVector2Array([o + off + Vector2(-s * 0.8, s * 0.8), o + off + Vector2(-s * 0.85, s * 0.45),
			o + off + Vector2(-s * 0.55, s * 0.55)]), Color(0.9, 0.9, 0.9))


static func _tree(c: CanvasItem, o: Vector2, s: float) -> void:
	c.draw_rect(Rect2(o + Vector2(-s * 0.15, s * 0.2), Vector2(s * 0.3, s * 0.75)), Color(0.45, 0.28, 0.13))
	c.draw_circle(o + Vector2(0, -s * 0.25), s * 0.65, OUTLINE)
	c.draw_circle(o + Vector2(0, -s * 0.25), s * 0.6, Color(0.2, 0.55, 0.2))
	c.draw_circle(o + Vector2(-s * 0.2, -s * 0.4), s * 0.2, Color(0.3, 0.68, 0.28))


static func _rune(c: CanvasItem, o: Vector2, s: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * float(i) / 10.0
		pts.append(o + Vector2(cos(a) * s * 0.85, sin(a) * s * 0.75))
	_poly(c, pts, Color(0.6, 0.6, 0.62))
	c.draw_line(o + Vector2(-s * 0.3, -s * 0.35), o + Vector2(s * 0.3, s * 0.35), Color(0.2, 0.45, 0.9), 3.0)
	c.draw_line(o + Vector2(s * 0.3, -s * 0.35), o + Vector2(-s * 0.3, s * 0.35), Color(0.2, 0.45, 0.9), 3.0)


static func _skull(c: CanvasItem, o: Vector2, s: float) -> void:
	var bone := Color(0.93, 0.92, 0.85)
	c.draw_circle(o + Vector2(0, -s * 0.15), s * 0.7, OUTLINE)
	c.draw_circle(o + Vector2(0, -s * 0.15), s * 0.66, bone)
	c.draw_rect(Rect2(o + Vector2(-s * 0.4, s * 0.3), Vector2(s * 0.8, s * 0.45)), bone)
	c.draw_circle(o + Vector2(-s * 0.27, -s * 0.15), s * 0.18, OUTLINE)
	c.draw_circle(o + Vector2(s * 0.27, -s * 0.15), s * 0.18, OUTLINE)
	for x in [-0.2, 0.0, 0.2]:
		c.draw_line(o + Vector2(x * s, s * 0.45), o + Vector2(x * s, s * 0.75), OUTLINE, 1.2)


static func _watering_can(c: CanvasItem, o: Vector2, s: float) -> void:
	var tin := Color(0.6, 0.62, 0.66)
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.55, -s * 0.3), o + Vector2(s * 0.3, -s * 0.3),
		o + Vector2(s * 0.3, s * 0.7), o + Vector2(-s * 0.55, s * 0.7)]), tin)
	c.draw_line(o + Vector2(s * 0.3, s * 0.3), o + Vector2(s * 0.95, -s * 0.45), tin.darkened(0.2), 3.5)
	c.draw_arc(o + Vector2(-s * 0.12, -s * 0.3), s * 0.35, PI, TAU, 10, tin.darkened(0.3), 2.5)
	c.draw_circle(o + Vector2(s * 0.95, -s * 0.5), s * 0.12, Color(0.4, 0.7, 1.0))


static func _house(c: CanvasItem, o: Vector2, s: float) -> void:
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.95, -s * 0.05), o + Vector2(0, -s * 0.9), o + Vector2(s * 0.95, -s * 0.05)]), Color(0.65, 0.25, 0.18))
	_poly(c, PackedVector2Array([o + Vector2(-s * 0.7, -s * 0.05), o + Vector2(s * 0.7, -s * 0.05),
		o + Vector2(s * 0.7, s * 0.85), o + Vector2(-s * 0.7, s * 0.85)]), Color(0.8, 0.7, 0.5))
	c.draw_rect(Rect2(o + Vector2(-s * 0.15, s * 0.35), Vector2(s * 0.3, s * 0.5)), Color(0.4, 0.25, 0.12))


static func _paw(c: CanvasItem, o: Vector2, s: float) -> void:
	var brown := Color(0.55, 0.38, 0.22)
	c.draw_circle(o + Vector2(0, s * 0.3), s * 0.42, OUTLINE)
	c.draw_circle(o + Vector2(0, s * 0.3), s * 0.38, brown)
	for p in [Vector2(-0.6, -0.15), Vector2(-0.22, -0.6), Vector2(0.22, -0.6), Vector2(0.6, -0.15)]:
		c.draw_circle(o + p * s, s * 0.2, OUTLINE)
		c.draw_circle(o + p * s, s * 0.17, brown)


static func _anchor(c: CanvasItem, o: Vector2, s: float) -> void:
	var iron := Color(0.55, 0.57, 0.62)
	c.draw_arc(o + Vector2(0, -s * 0.72), s * 0.18, 0, TAU, 12, iron, 2.5)
	c.draw_line(o + Vector2(0, -s * 0.55), o + Vector2(0, s * 0.8), iron, 3.0)
	c.draw_line(o + Vector2(-s * 0.4, -s * 0.3), o + Vector2(s * 0.4, -s * 0.3), iron, 3.0)
	c.draw_arc(o + Vector2(0, s * 0.2), s * 0.65, PI * 0.15, PI * 0.85, 12, iron, 3.0)
