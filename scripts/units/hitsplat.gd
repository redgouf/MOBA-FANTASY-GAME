class_name Hitsplat
extends Node3D
## OSRS-style hitsplats: a red splat with the damage, a blue one for 0, a
## gold-trimmed "max hit" splat for critical hits, and green / teal / orange
## for poison, venom and burn. Like OSRS, splats from hits that don't
## involve you (not dealt by you, not taken by you) are tinted darker.
## A splat stays up for about two game ticks without drifting; a unit shows
## up to four at once (centre, above, lower left, lower right), then the
## oldest is replaced. Sprites: assets/hitsplats (tools/make_hitsplats.py).

const LIFETIME := 1.2              # seconds, about 2 OSRS ticks
const SIZE_PX := 96.0
const PIXEL := 0.0062              # world metres per sprite pixel
## Splat positions around the anchor, in splat widths (x right, y up).
const SLOTS: Array[Vector2] = [Vector2(0, 0), Vector2(0, 0.9), Vector2(-0.82, -0.5), Vector2(0.82, -0.5)]

## The unit whose hits are shown bright (the player, or the spectated champion).
static var viewer: Node = null
## The screen overlay splats are drawn on (the health-bar layer: splats added
## after the bars draw on top of every bar, your own included). Main sets it;
## without it (tests) splats are 3D sprites.
static var overlay: Node = null
static var camera: Camera3D = null
const SCREEN_SPLAT_PX := 46.0     # a splat's width on screen (OSRS sprites drawn 2x)
static var _textures: Dictionary = {}

var slot := 0
var follow: WeakRef               # the unit the splat sits on
var height := 2.0
var _age := 0.0
var _sprite: Sprite3D
var _label: Label3D


## Which sprite a hit uses: "damage", "zero", "max", "poison", "venom" or "burn".
static func kind_for(amount: float, info: DamageInfo) -> String:
	if amount <= 0.0:
		return "zero"
	if info != null:
		match info.label:
			"poison", "venom", "burn":
				return info.label
		if info.crit_mult > 1.0:
			return "max"
	return "damage"


## Bright when the viewer dealt or took the hit; tinted otherwise.
static func is_tinted(target: Node, info: DamageInfo) -> bool:
	if viewer == null or not is_instance_valid(viewer):
		return false
	if target == viewer:
		return false
	return info == null or info.source != viewer


static func texture(kind: String, tinted: bool) -> Texture2D:
	var key := kind + ("_tinted" if tinted else "")
	if not _textures.has(key):
		# The real OSRS hitsplats from the private pack, else our drawn ones.
		var osrs := "res://private_assets/osrs/ui/hitsplats/%s.png" % key
		var path := "res://assets/hitsplats/%s.png" % key
		if OsrsModels.available() and ResourceLoader.exists(osrs):
			_textures[key] = load(osrs)
		else:
			_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _textures[key]


static func spawn(parent: Node, at: Vector3, amount: float, kind: String, tinted: bool, p_slot: int = 0) -> Hitsplat:
	var h := Hitsplat.new()
	h.slot = p_slot
	parent.add_child(h)
	h.global_position = at
	h._build(amount, kind, tinted)
	return h


var _view: Control              # the splat on the screen overlay


## The splat drawn flat on the screen, OSRS-style: the sprite at whole-pixel
## scale and the number in OSRS's small font with a black drop shadow, sized
## to sit inside the splat.
func _build_screen(amount: float, kind: String, tinted: bool) -> void:
	var tex := texture(kind, tinted)
	var w := float(tex.get_width()) if tex != null else 24.0
	var scale_px := maxf(1.0, round(SCREEN_SPLAT_PX / w)) if w < 64.0 else SCREEN_SPLAT_PX / w
	var size := Vector2(w, float(tex.get_height()) if tex != null else 24.0) * scale_px
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.size = size
	_view.pivot_offset = size * 0.5
	var pic := TextureRect.new()
	pic.texture = tex
	pic.size = size
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(pic)
	var font: Font = OsrsFont.get_font("p11_full") if OsrsFont.active else null
	var font_size := 24 if OsrsFont.active else (17 if amount < 100.0 else 15)
	for shadow in [true, false]:
		var l := Label.new()
		l.text = str(int(round(amount)))
		if font != null:
			l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", Color(0, 0, 0) if shadow else (Color.WHITE if not tinted else Color(0.85, 0.85, 0.85)))
		if font == null:
			l.add_theme_constant_override("outline_size", 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = size
		l.position = Vector2(2, 2) if shadow else Vector2.ZERO
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_view.add_child(l)
	_view.modulate.a = 0.85 if tinted else 1.0
	_alpha = _view.modulate.a
	overlay.add_child(_view)
	_place_view()


func _place_view() -> void:
	var cam := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	if cam == null or _view == null:
		return
	if cam.is_position_behind(global_position):
		_view.visible = false
		return
	_view.visible = true
	var p := cam.unproject_position(global_position)
	var off := SLOTS[clampi(slot, 0, SLOTS.size() - 1)] * _view.size.x * 0.9
	_view.position = p - _view.size * 0.5 + Vector2(off.x, -off.y)


func _exit_tree() -> void:
	if _view != null and is_instance_valid(_view):
		_view.queue_free()


func _build(amount: float, kind: String, tinted: bool) -> void:
	if overlay != null and is_instance_valid(overlay):
		_build_screen(amount, kind, tinted)
		return
	var off := SLOTS[clampi(slot, 0, SLOTS.size() - 1)] * SIZE_PX * 0.92
	_sprite = Sprite3D.new()
	_sprite.texture = texture(kind, tinted)
	# Same size on screen whatever the sprite's resolution (OSRS sprites are ~24 px).
	var px_scale := SIZE_PX * 0.62 / float(_sprite.texture.get_width()) if _sprite.texture != null and _sprite.texture.get_width() < 64 else 1.0
	_sprite.pixel_size = PIXEL * px_scale
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.no_depth_test = true
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.render_priority = 10
	_sprite.offset = off / px_scale
	add_child(_sprite)
	_label = Label3D.new()
	_label.text = str(int(round(amount)))
	_label.font_size = 40 if amount < 100.0 else 34
	_label.pixel_size = PIXEL
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = 11
	_label.outline_render_priority = 10
	_label.modulate = Color.WHITE if not tinted else Color(0.72, 0.72, 0.72, 0.85)
	_label.outline_modulate = Color(0, 0, 0, 1)
	_label.outline_size = 8
	_label.offset = off + Vector2(0, 2)
	add_child(_label)
	if OsrsFont.active:
		# The OSRS pixel font has no outline: a black drop shadow, as in OSRS.
		_shadow = _label.duplicate() as Label3D
		_shadow.modulate = Color(0, 0, 0, 1)
		_shadow.offset = _label.offset + Vector2(3, -3)
		_shadow.render_priority = _label.render_priority - 1
		add_child(_shadow)
	# Your own hits stand out: bigger and fully bright; everyone else's are
	# smaller, darker and slightly see-through.
	scale = Vector3.ONE * (1.12 if not tinted else 0.82)
	if tinted:
		_sprite.modulate = Color(1, 1, 1, 0.8)
		_sprite.render_priority = 8
		_label.render_priority = 9
		_label.outline_render_priority = 8
	else:
		_sprite.render_priority = 30
		_label.render_priority = 31
		_label.outline_render_priority = 30
	_alpha = 0.8 if tinted else 1.0


var _alpha := 1.0
var _shadow: Label3D


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	var u: Node3D = follow.get_ref() if follow != null else null
	if u != null and u.is_inside_tree():
		global_position = u.global_position + Vector3.UP * height
	var fade := clampf((LIFETIME - _age) / 0.15, 0.0, 1.0) * _alpha
	if _view != null:
		_place_view()
		_view.modulate.a = fade
		return
	_sprite.modulate.a = fade
	_label.modulate.a = fade
	_label.outline_modulate.a = fade
	if _shadow != null:
		_shadow.modulate.a = fade
