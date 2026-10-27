class_name GoldPopup
extends Node3D
## "+22 gp": gold you just earned, floating up from where the kill happened
## (a minion, a tower, a jungle monster or an enemy champion). Drawn on the
## same screen overlay as hitsplats; without one (tests) it is a Label3D.

const LIFETIME := 1.5
const RISE := 1.8                  # metres
const COLOR := Color(1.0, 0.92, 0.1)
const BIG := Color(1.0, 0.8, 0.15)

static var _last_msec := 0
static var _stack := 0

var amount := 0
var big := false
var _age := 0.0
var _label: Control
var _label3d: Label3D
var _base := Vector3.ZERO


## Shows `gold` earned at world position `at`. Several in a row (a tower pays
## its killer and the team at once) stack upward instead of overlapping.
static func spawn(parent: Node, at: Vector3, gold: float, p_big: bool = false) -> GoldPopup:
	var n := int(round(gold))
	if n <= 0 or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var now := Time.get_ticks_msec()
	_stack = _stack + 1 if now - _last_msec < 600 else 0
	_last_msec = now
	var p := GoldPopup.new()
	p.amount = n
	p.big = p_big
	parent.add_child(p)
	p._base = at + Vector3.UP * (1.4 + 0.0)
	p.global_position = p._base
	p._build(_stack)
	return p


func _build(stack: int) -> void:
	var text := "+%d gp" % amount
	var overlay: Node = Hitsplat.overlay
	if overlay != null and is_instance_valid(overlay):
		var l := Label.new()
		l.text = text
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var font: Font = OsrsFont.get_font_any_size("b12_full") if OsrsFont.active else null
		if font != null:
			l.add_theme_font_override("font", font)
			l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			l.add_theme_constant_override("outline_size", 0)
			l.add_theme_color_override("font_shadow_color", Color.BLACK)
			l.add_theme_constant_override("shadow_offset_x", 2)
			l.add_theme_constant_override("shadow_offset_y", 2)
		else:
			l.add_theme_constant_override("outline_size", 5)
			l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_font_size_override("font_size", (30 if big else 24) if font != null else (22 if big else 17))
		l.add_theme_color_override("font_color", BIG if big else COLOR)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(160, 36)
		l.pivot_offset = l.size * 0.5
		overlay.add_child(l)
		_label = l
		_base.y += float(stack) * 0.55
		_place(0.0)
		return
	_label3d = Label3D.new()
	_label3d.text = text
	_label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label3d.no_depth_test = true
	_label3d.pixel_size = 0.012
	_label3d.font_size = 40
	_label3d.modulate = BIG if big else COLOR
	_label3d.outline_size = 10
	_base.y += float(stack) * 0.55
	add_child(_label3d)


func _place(t: float) -> void:
	var pos := _base + Vector3.UP * (RISE * ease(t, 0.4))
	global_position = pos
	if _label == null:
		return
	var cam := Hitsplat.camera if is_instance_valid(Hitsplat.camera) else get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(pos):
		_label.visible = false
		return
	_label.visible = true
	_label.position = cam.unproject_position(pos) - _label.size * 0.5


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var t := _age / LIFETIME
	var fade := clampf((LIFETIME - _age) / 0.4, 0.0, 1.0)
	_place(t)
	if _label != null:
		_label.modulate.a = fade
	elif _label3d != null:
		_label3d.modulate.a = fade


func _exit_tree() -> void:
	if _label != null and is_instance_valid(_label):
		_label.queue_free()
