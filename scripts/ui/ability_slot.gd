class_name AbilitySlot
extends Panel
## One ability square on the action bar: hotkey, name, rank pips,
## cooldown shade, spec cost, and a "+" level-up button above it.

signal level_up_pressed(slot: String)

var slot := ""

var _key: Label
var _name: Label
var _cd: Label
var _cost: Label
var _locked: Label
var _shade: ColorRect
var _pips: HBoxContainer
var _plus: Button
var _ready_style: StyleBoxFlat
var _locked_style: StyleBoxFlat
var _pip_count := -1
var _tip_timer := 0.0


static func create(parent: Control, p_slot: String, size: float) -> AbilitySlot:
	var a := AbilitySlot.new()
	a.slot = p_slot
	a.custom_minimum_size = Vector2(size, size)
	a.size = Vector2(size, size)
	parent.add_child(a)
	a._build()
	return a


func _build() -> void:
	_ready_style = UiStyle.box(UiStyle.BG_SLOT, UiStyle.BORDER_HI, 2, 4)
	_locked_style = UiStyle.box(UiStyle.BG_DARK, UiStyle.BORDER.darkened(0.4), 2, 4)
	add_theme_stylebox_override("panel", _ready_style)
	_name = UiStyle.label(self, "", 12)
	UiStyle.fill(_name, 3, 0, 3, 10)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.65)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_locked = UiStyle.label(self, "", 11, UiStyle.MUTED)
	UiStyle.fill(_locked)
	_locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locked.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_locked.offset_bottom = -12
	_cd = UiStyle.label(self, "", 22, Color.WHITE)
	UiStyle.fill(_cd)
	_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key = UiStyle.label(self, slot.to_upper(), 13, UiStyle.TITLE)
	_key.position = Vector2(5, 1)
	_cost = UiStyle.label(self, "", 10, UiStyle.SPEC)
	UiStyle.place(_cost, Control.PRESET_TOP_RIGHT, Vector2(-34, 2), Vector2(30, 14))
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 3)
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pips)
	_plus = UiStyle.button(self, "+", 16)
	_plus.add_theme_color_override("font_color", UiStyle.GOLD)
	_plus.position = Vector2(size.x * 0.5 - 14, -30)
	_plus.size = Vector2(28, 24)
	_plus.custom_minimum_size = Vector2(28, 24)
	_plus.focus_mode = Control.FOCUS_NONE
	_plus.tooltip_text = "Level up (Ctrl+%s)" % slot.to_upper()
	_plus.pressed.connect(func() -> void: level_up_pressed.emit(slot))


func refresh(champ: Champion, allow_level_up: bool = true) -> void:
	var ab := champ.get_ability(slot)
	var rank := champ.ability_rank(slot)
	var max_rank := champ.max_rank(slot)
	_name.text = str(ab.get("name", ""))
	var cost := float(ab.get("spec_cost", 0.0))
	_cost.text = "%d%%" % int(cost) if cost > 0.0 else ""

	if _pip_count != max_rank:
		_pip_count = max_rank
		for c in _pips.get_children():
			c.queue_free()
		for i in max_rank:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(9, 5)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_pips.add_child(pip)
		var w := max_rank * 9 + (max_rank - 1) * 3
		_pips.position = Vector2((size.x - w) * 0.5, size.y - 9)
	var i := 0
	for pip in _pips.get_children():
		(pip as ColorRect).color = UiStyle.GOLD if i < rank else Color(0.42, 0.37, 0.3)
		i += 1

	var cd: float = champ.cooldowns.get(slot, 0.0)
	var total := champ.ability_cooldown(slot, ab)
	var locked := rank <= 0
	add_theme_stylebox_override("panel", _locked_style if locked else _ready_style)
	_name.modulate = Color(1, 1, 1, 0.45) if locked else Color.WHITE
	if locked:
		_locked.text = "Level %d" % champ.level_needed_for_next_rank(slot) if slot == "r" else "Not learned"
	else:
		_locked.text = ""
	var no_spec := not locked and cost > 0.0 and champ.spec < cost
	if cd > 0.0 and total > 0.0:
		var h := size.y * clampf(cd / total, 0.0, 1.0)
		_shade.position = Vector2(0, size.y - h)
		_shade.size = Vector2(size.x, h)
		_shade.visible = true
		_cd.text = "%.1f" % cd if cd < 1.0 else str(ceili(cd))
	else:
		_shade.visible = no_spec
		_shade.position = Vector2.ZERO
		_shade.size = size
		_cd.text = ""
	_plus.visible = allow_level_up and champ.can_rank_up(slot)

	# Rebuilt a few times a second, not every frame (it does the damage maths).
	_tip_timer -= get_process_delta_time()
	if _tip_timer <= 0.0:
		_tip_timer = 0.25
		tooltip_text = AbilityInfo.tooltip(champ, slot)
