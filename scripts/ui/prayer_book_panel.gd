class_name PrayerBookPanel
extends PanelContainer
## The OSRS prayer book for champion select: all 32 prayers in book order,
## five to a row. Prayers above the build's Prayer level are dimmed and
## can't be picked; click an unlocked one to make it the build's prayer.
## Hover any prayer for what it does and how fast it drains.

signal prayer_picked(id: String)

const CELL := Vector2(42, 42)
const COLUMNS := 5

var selected := ""
var locked := false              # champion select's LOCK IN freezes the pick
var _def: Dictionary = {}
var _cells: Dictionary = {}     # id -> Button
var _title: Label
var _info: Label


static func create(parent: Control) -> PrayerBookPanel:
	var p := PrayerBookPanel.new()
	parent.add_child(p)
	return p


func _ready() -> void:
	add_theme_stylebox_override("panel", OsrsUi.panel_box(OsrsUi.STONE_DARK, 2))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_title = UiStyle.label(col, "Prayer", 15, UiStyle.TITLE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	col.add_child(grid)
	for p in PrayerBook.all():
		var id := str(p["id"])
		var b := Button.new()
		b.custom_minimum_size = CELL
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", _cell_box(false))
		b.add_theme_stylebox_override("hover", _cell_box(false, true))
		b.add_theme_stylebox_override("pressed", _cell_box(true))
		b.add_theme_stylebox_override("hover_pressed", _cell_box(true, true))
		b.add_theme_stylebox_override("disabled", _cell_box(false))
		var icon := Icons.rect(b, Icons.prayer(str(p["name"])), CELL - Vector2(10, 10))
		icon.position = Vector2(5, 5)
		icon.size = CELL - Vector2(10, 10)
		b.pressed.connect(_on_cell.bind(id))
		grid.add_child(b)
		_cells[id] = b
	_info = UiStyle.label(col, "", 13)
	_info.custom_minimum_size = Vector2(COLUMNS * (CELL.x + 3), 92)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.max_lines_visible = 6
	_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if not _def.is_empty():
		show_build(_def, selected)


## The OSRS "active prayer" look: a pale disc behind the icon.
func _cell_box(on: bool, hover: bool = false) -> StyleBoxFlat:
	var sb := UiStyle.box(Color(0.78, 0.74, 0.58, 0.55) if on else Color(0, 0, 0, 0), \
		UiStyle.BORDER_HI if hover else (Color(0.9, 0.85, 0.6) if on else Color(0, 0, 0, 0)), 1, 21)
	sb.set_content_margin_all(0)
	return sb


## Shows the book for a build and selects `pick` (or the build's default).
func show_build(def: Dictionary, pick: String = "") -> void:
	_def = def
	if pick == "" or not PrayerBook.can_pick(def, pick):
		pick = PrayerBook.default_for(def)
	selected = pick
	if _title == null:
		return
	var lvl := int(def.get("skills", {}).get("prayer", 1))
	_title.text = "%s — Prayer %d" % [def.get("name", ""), lvl]
	for p in PrayerBook.all():
		var id := str(p["id"])
		var b: Button = _cells[id]
		var ok := PrayerBook.can_pick(def, id)
		b.disabled = not ok
		b.set_pressed_no_signal(id == selected)
		b.modulate = Color.WHITE if ok else Color(0.35, 0.33, 0.3, 0.8)
		var tip := PrayerBook.tooltip(p)
		if int(p["level"]) > lvl:
			tip += "\nNeeds Prayer %d (this build has %d)." % [int(p["level"]), lvl]
		elif not ok:
			tip += "\nThis build already has all three protection prayers (Z/X/C)."
		b.tooltip_text = UiStyle.wrap(tip)
	_update_info()


func _on_cell(id: String) -> void:
	if locked or not PrayerBook.can_pick(_def, id):
		for k in _cells:
			(_cells[k] as Button).set_pressed_no_signal(k == selected)
		return
	selected = id
	for k in _cells:
		(_cells[k] as Button).set_pressed_no_signal(k == selected)
	_update_info()
	prayer_picked.emit(id)


func _update_info() -> void:
	var p := PrayerBook.find(selected)
	if p.is_empty():
		_info.text = "No prayer"
		return
	_info.text = "%s (V in game)\n%s\nDrains %s" % [p["name"], PrayerBook.effect_text(p),
		PrayerBook.drain_text(float(p["drain"]))]
