class_name StatBar
extends Control
## A filled bar with centred text, e.g. "1693 / 1802".

var _fill: StyleBoxFlat
var _bar: ProgressBar
var _text: Label


static func create(parent: Control, color: Color, size: Vector2, font_size: int = 12) -> StatBar:
	var b := StatBar.new()
	b.custom_minimum_size = size
	b.size = size
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	b._build(color, font_size)
	return b


func _build(color: Color, font_size: int) -> void:
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	UiStyle.fill(_bar)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill = StyleBoxFlat.new()
	_fill.bg_color = color
	_fill.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("fill", _fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.03, 0.95)
	bg.border_color = Color(0, 0, 0, 0.9)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("background", bg)
	add_child(_bar)
	_text = UiStyle.label(self, "", font_size, Color.WHITE)
	UiStyle.fill(_text)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func set_values(current: float, maximum: float, text: String = "") -> void:
	_bar.max_value = maxf(maximum, 0.001)
	_bar.value = clampf(current, 0.0, maximum)
	_text.text = text if text != "" else "%d / %d" % [int(ceil(current)), int(maximum)]


func set_color(color: Color) -> void:
	_fill.bg_color = color
