class_name Icons
extends RefCounted
## OSRS item and prayer icons (the original pixel art, centred on a 32x32
## canvas and enlarged exactly 4x, so every icon shares one scale) from Dava96/osrs-icons
## (https://github.com/Dava96/osrs-icons). Icons are Jagex's, via the OSRS
## Wiki, under CC BY-NC-SA 3.0. Only the icons this game uses are in
## assets/icons (see assets/icons/SOURCE.json).

static var _cache: Dictionary = {}


static func item(id: String) -> Texture2D:
	return _load("res://assets/icons/items/%s.png" % id) if id != "" else null


## Champion equipment (the gear each build wears), by slug: "dharoks_helm".
static func gear(slug: String) -> Texture2D:
	return _load("res://assets/icons/gear/%s.png" % slug) if slug != "" else null


## OSRS overhead prayer icons (protect prayers, Smite, Redemption, Retribution), by prayer id.
static func overhead(prayer_id: String) -> Texture2D:
	return _load("res://assets/icons/overheads/%s.png" % prayer_id) if prayer_id != "" else null


static func prayer(prayer_name: String) -> Texture2D:
	return _load("res://assets/icons/prayers/%s.png" % prayer_name.to_lower().replace(" ", "_"))


static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[path] = tex
	return tex


## A TextureRect for an icon. The 4x source is drawn with mipmapped linear
## filtering: crisp at any size, with no uneven (stretched) pixels.
static func rect(parent: Control, tex: Texture2D, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.custom_minimum_size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r
