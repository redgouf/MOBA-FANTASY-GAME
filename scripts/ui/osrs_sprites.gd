class_name OsrsSprites
extends RefCounted
## Real OSRS interface sprites from the private model pack
## (private_assets/osrs/ui/sprites, made by tools/osrs_extract's "ui" step):
## the stone side-panel background, the equipment slot frame and skill /
## combat icons. Each returns null without the pack, and the HUD keeps its
## own drawn look.

const DIR := "res://private_assets/osrs/ui/sprites/"

static var _cache: Dictionary = {}


static func get_sprite(sprite_name: String) -> Texture2D:
	if not _cache.has(sprite_name):
		var path := DIR + sprite_name + ".png"
		_cache[sprite_name] = load(path) if OsrsModels.available() and ResourceLoader.exists(path) else null
	return _cache[sprite_name]


static func available() -> bool:
	return get_sprite("side_background") != null


## The OSRS stone panel: the side-panel texture tiled, with a dark outer and
## a lighter inner edge like the game's interface frames.
static func stone_panel(target: Control) -> void:
	var sb := StyleBoxTexture.new()
	sb.texture = get_sprite("side_background")
	# Stretched, not tiled: the texture's own edges would show as seams.
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	target.add_theme_stylebox_override("panel", sb)
	var edge := Panel.new()
	edge.name = "StoneEdge"
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	var e := StyleBoxFlat.new()
	e.draw_center = false
	e.border_color = Color(0.09, 0.075, 0.055)
	e.set_border_width_all(3)
	e.set_corner_radius_all(3)
	e.shadow_color = Color(0.45, 0.4, 0.3, 0.6)
	edge.add_theme_stylebox_override("panel", e)
	target.add_child(edge)


## The OSRS equipment slot frame as a stylebox.
static func slot_box() -> StyleBox:
	var t := get_sprite("slot")
	if t == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = 4
	sb.texture_margin_right = 4
	sb.texture_margin_top = 4
	sb.texture_margin_bottom = 4
	return sb
