class_name UnitBars
extends Control
## Health bars and names drawn flat on the screen over each unit, at a fixed
## pixel size however far the camera is zoomed (League style), instead of 3D
## bars in the world:
##   champions  name, then a framed bar: a level badge, health (a tick every
##              chunk of health) and the prayer bar (blue) under it, the
##              overhead prayer icon above the name. The name is coloured by
##              level against yours, like OSRS's right-click menu: green lower,
##              yellow even, orange then red higher
## The health colour tells the teams apart: green you, blue allies, red
## enemies, yellow neutral monsters; dark where health is missing.
##   minions    a thin bar, no name
##   monsters   a bar, and the name for epic monsters
##   structures a wider bar with the name
## Champions draw last, so their bars sit on top of minions'. Units hidden
## by the fog of war, dead ones and ones behind the camera are skipped.

const SELF := Color(0.12, 0.82, 0.12)
const ALLY := Color(0.2, 0.55, 0.95)
const ENEMY := Color(0.86, 0.16, 0.12)
const NEUTRAL := Color(0.92, 0.75, 0.18)
const MISSING := Color(0.1, 0.1, 0.1, 0.9)
## Level difference at which a name is fully green or red.
const LEVEL_SPAN := 5.0
const PRAYER := Color(0.3, 0.72, 0.95)
const FRAME := Color(0.03, 0.03, 0.03, 0.92)
const CHAMP_W := 128.0
const CHAMP_HP_H := 10.0
const CHAMP_PR_H := 4.0
const MINION_W := 58.0
const MINION_H := 5.0

## The viewer's team (their own champion's bar frame is gold).
var viewer: Unit
var camera: Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	if cam == null or not is_inside_tree():
		return
	var champs: Array[Unit] = []
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead or u.fog_hidden or not u.visible or not u.is_inside_tree():
			continue
		if u.is_class_champion():
			champs.append(u)
		else:
			_draw_unit(cam, u)
	for c in champs:
		_draw_champion(cam, c as Champion)


## Where a unit's bar goes: just above its head, in screen pixels.
func _anchor(cam: Camera3D, u: Unit) -> Variant:
	var head := u.global_position + Vector3.UP * (u.visual_height() + 0.35)
	if cam.is_position_behind(head):
		return null
	return cam.unproject_position(head)


func _bar(rect: Rect2, ratio: float, fill: Color, back: Color) -> void:
	draw_rect(rect.grow(1.0), FRAME)
	draw_rect(rect, back)
	var w := rect.size.x * clampf(ratio, 0.0, 1.0)
	if w > 0.0:
		draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), fill)


func _draw_unit(cam: Camera3D, u: Unit) -> void:
	var anchor: Variant = _anchor(cam, u)
	if anchor == null:
		return
	var p: Vector2 = anchor
	var w := MINION_W
	var h := MINION_H
	var label := ""
	if u.is_structure():
		w = 110.0
		h = 8.0
		label = u.display_name
	elif u is Monster:
		w = 96.0 if u.is_epic else 64.0
		h = 7.0 if u.is_epic else 5.0
		label = u.display_name if u.is_epic else ""
	var rect := Rect2(Vector2(p.x - w * 0.5, p.y - h), Vector2(w, h))
	_bar(rect, u.health_ratio(), team_fill(u), MISSING)
	if label != "":
		_text(Vector2(p.x, rect.position.y - 4.0), label, 12, Color(0.95, 0.93, 0.85))


func _draw_champion(cam: Camera3D, c: Champion) -> void:
	var anchor: Variant = _anchor(cam, c)
	if anchor == null:
		return
	var p: Vector2 = anchor
	var badge_r := 10.0
	var w := CHAMP_W
	var x := p.x - (w + badge_r * 2.0) * 0.5 + badge_r * 2.0
	var top := p.y - (CHAMP_HP_H + CHAMP_PR_H + 3.0)
	var frame := Rect2(Vector2(x - 2.0, top - 2.0), Vector2(w + 4.0, CHAMP_HP_H + CHAMP_PR_H + 5.0))
	var own := c == viewer
	draw_rect(frame, FRAME)
	draw_rect(frame, Color(0.95, 0.8, 0.3) if own else Color(0.3, 0.3, 0.3), false, 1.0)
	# Health, with a tick every chunk so big health pools read at a glance.
	var hp := Rect2(Vector2(x, top), Vector2(w, CHAMP_HP_H))
	draw_rect(hp, MISSING)
	draw_rect(Rect2(hp.position, Vector2(w * c.health_ratio(), CHAMP_HP_H)), team_fill(c))
	var chunk := float(GameData.rule("health_bar_tick", 50.0))
	var ticks := int(c.max_health / maxf(chunk, 1.0))
	if ticks > 0 and ticks < 40:
		for i in range(1, ticks + 1):
			var tx := x + w * (float(i) * chunk / c.max_health)
			if tx < x + w - 1.0:
				draw_line(Vector2(tx, top), Vector2(tx, top + CHAMP_HP_H * (0.45 if i % 10 != 0 else 1.0)), Color(0, 0, 0, 0.8), 1.0)
	# Prayer under it.
	var pr := Rect2(Vector2(x, top + CHAMP_HP_H + 1.0), Vector2(w, CHAMP_PR_H))
	draw_rect(pr, Color(0.06, 0.12, 0.18))
	draw_rect(Rect2(pr.position, Vector2(w * clampf(c.prayer / maxf(c.prayer_max, 1.0), 0.0, 1.0), CHAMP_PR_H)), PRAYER)
	# Level badge on the left.
	var bc := Vector2(x - badge_r - 3.0, top + (CHAMP_HP_H + CHAMP_PR_H) * 0.5)
	draw_circle(bc, badge_r + 1.5, Color(0.75, 0.62, 0.3))
	draw_circle(bc, badge_r, Color(0.22, 0.05, 0.04) if c.team != (viewer.team if is_instance_valid(viewer) else c.team) else Color(0.05, 0.1, 0.22))
	_text(bc + Vector2(0, 5.0), str(c.level), 13, Color(1, 1, 1))
	# Name above, and the overhead prayer above that.
	_text(Vector2(p.x, top - 5.0), c.display_name, 13, level_color(c.level, viewer.level if is_instance_valid(viewer) and viewer is Champion else c.level))
	var oh := c.overhead_prayer()
	if oh != "":
		var tex := Icons.overhead(oh)
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2(p.x - 13.0, top - 46.0), Vector2(26, 26)), false)


func _text(center_bottom: Vector2, s: String, size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(center_bottom.x - w * 0.5, center_bottom.y)
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Health colour by side: green for you, blue allies, red enemies, yellow neutral.
func team_fill(u: Unit) -> Color:
	if u == viewer:
		return SELF
	if u.team == Combat.Team.NEUTRAL:
		return NEUTRAL
	var my_team: int = viewer.team if is_instance_valid(viewer) else Combat.Team.SARADOMIN
	return ALLY if u.team == my_team else ENEMY


## OSRS right-click colours by level: green when lower than yours, yellow
## when even, then orange to red as they get higher.
static func level_color(level: int, mine: int) -> Color:
	var t := clampf(float(level - mine) / LEVEL_SPAN, -1.0, 1.0)
	if t < 0.0:
		return Color(1.0, 1.0, 0.0).lerp(Color(0.0, 1.0, 0.0), -t)
	if t < 0.5:
		return Color(1.0, 1.0, 0.0).lerp(Color(1.0, 0.56, 0.0), t * 2.0)
	return Color(1.0, 0.56, 0.0).lerp(Color(1.0, 0.0, 0.0), (t - 0.5) * 2.0)
