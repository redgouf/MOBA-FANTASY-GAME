class_name SkillIcons
extends RefCounted
## Simple vector icons for the combat skills, drawn in the spirit of the
## OSRS Skills tab (sword, heart, fist, shield, bow, prayer star, wizard hat).
## Drawn from shapes rather than copied sprites.

const STEEL := Color(0.78, 0.8, 0.84)
const OUTLINE := Color(0.05, 0.04, 0.03)


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
