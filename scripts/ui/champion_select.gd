class_name ChampionSelect
extends CanvasLayer
## Champion select, laid out like an OSRS interface on a fixed 1600x900 grid
## (nothing moves when you switch builds; only text and values change):
##   left    portrait cards for every build (name and role), plus "Watch bots"
##   centre  the Equipment Stats view (gear slots, the figure slowly turning
##           left and right, and its bonuses) and the build's abilities
##   right   a side panel with Skills and Prayer tabs (this game's rolled
##           levels; pick the build's prayer), and LOCK IN
## LOCK IN starts a 5 second countdown, then the match.

signal champion_selected(id: String, prayer_id: String)
signal spectate_selected

const COUNTDOWN := 5.0
const SLOT := 48.0
## The OSRS equipment screen's slot layout: 3 columns, 5 rows.
const SLOT_LAYOUT := [["", "head", ""], ["cape", "neck", "ammo"], ["weapon", "body", "shield"], ["", "legs", ""], ["hands", "feet", "ring"]]
const SLOT_NAMES := {"head": "Head", "cape": "Cape", "neck": "Neck", "ammo": "Ammunition", "weapon": "Weapon",
	"body": "Body", "shield": "Shield", "legs": "Legs", "hands": "Hands", "feet": "Feet", "ring": "Ring"}
const CARD := Vector2(136, 164)

var selected_id := ""
var locked := false

var _root: Control
var _cards: Dictionary = {}           # id -> Button
var _portraits: Dictionary = {}       # id -> TextureRect
var _equip_title: Label
var _slots: Dictionary = {}           # slot -> {"panel", "icon"}
var _figure: FigureView
var _studio: FigureView
var _build_info: Label
var _bonus_values: Dictionary = {}    # key -> Label
var _kit_rows: Array = []             # [{"key", "name", "text"}]
var _skills: SkillsPanel
var _prayers: PrayerBookPanel
var _tabs: Dictionary = {}            # "skills"/"prayer" -> Button
var _hints: Dictionary = {}           # tab -> Label under its page
var _lock: Button
var _lock_summary: Label
var _countdown: Label
var _sub: Label
var _count_left := -1.0


func _ready() -> void:
	GameData.roll_skills(true)          # this game's levels, kept for the match
	_root = Control.new()
	_root.size = Vector2(1600, 900)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.047, 0.036, 0.97)
	bg.size = _root.size
	_root.add_child(bg)

	var title := OsrsUi.text(_root, "Gielinor Legends", 40, OsrsUi.ORANGE, Rect2(0, 8, 1600, 52))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = false
	_sub = OsrsUi.text(_root, "Choose your build   ·   non-combat levels are rolled every game (20–75, one lucky skill up to 99; the Skiller is 99)",
		15, OsrsUi.MUTED, Rect2(0, 56, 1600, 22))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_build_cards(Rect2(16, 84, 452, 730))
	_build_equipment(Rect2(480, 84, 728, 452))
	_build_kit(Rect2(480, 544, 728, 270))
	_build_side_panel(Rect2(1220, 84, 364, 604))
	_build_lock(Rect2(1220, 696, 364, 118))

	var credit := OsrsUi.text(_root, "A free, non-commercial fan project. Old School RuneScape and RuneScape are trademarks of Jagex Ltd.",
		13, Color(1, 1, 1, 0.55), Rect2(0, 868, 1600, 20))
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# A hidden stage that photographs each build's portrait once.
	_studio = FigureView.create(_root, Rect2(-400, -400, 240, 224), true)
	select_build(GameData.champion_order[0])
	_render_portraits()


# --- Left: portrait cards ----------------------------------------------------------

func _build_cards(rect: Rect2) -> void:
	var p := OsrsUi.panel(_root, rect)
	OsrsUi.title(p, "Builds")
	var ids: Array = GameData.champion_order.duplicate()
	ids.append("")        # the last card: watch bots (spectator mode)
	for i in ids.size():
		var id: String = ids[i]
		var col := i % 3
		var row := floori(i / 3.0)
		var b := Button.new()
		b.position = Vector2(14 + col * (CARD.x + 8), 34 + row * (CARD.y + 6))
		b.size = CARD
		b.toggle_mode = id != ""
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", OsrsUi.slot_box(OsrsUi.STONE_DARK))
		b.add_theme_stylebox_override("hover", OsrsUi.slot_box(OsrsUi.STONE_DARK.lightened(0.06), true))
		b.add_theme_stylebox_override("pressed", OsrsUi.slot_box(OsrsUi.STONE_DARK.lightened(0.1), false, true))
		b.add_theme_stylebox_override("hover_pressed", OsrsUi.slot_box(OsrsUi.STONE_DARK.lightened(0.12), true, true))
		b.add_theme_stylebox_override("disabled", OsrsUi.slot_box(OsrsUi.STONE_DARK))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		p.add_child(b)
		var frame := Panel.new()
		frame.add_theme_stylebox_override("panel", OsrsUi.slot_box(Color(0.13, 0.11, 0.085)))
		frame.position = Vector2(8, 6)
		frame.size = Vector2(CARD.x - 16, 110)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(frame)
		var pic := Icons.rect(frame, null, Vector2(CARD.x - 20, 106))
		pic.position = Vector2(2, 2)
		pic.size = Vector2(CARD.x - 20, 106)
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if id == "":
			var eye := OsrsUi.text(frame, "5v5", 40, Color(0.75, 0.6, 0.35), Rect2(0, 24, CARD.x - 16, 60))
			eye.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var n := OsrsUi.text(b, "Watch bots", 15, OsrsUi.ORANGE, Rect2(4, 118, CARD.x - 8, 20))
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var r := OsrsUi.text(b, "5v5 NPC vs NPC", 12, OsrsUi.MUTED, Rect2(4, 138, CARD.x - 8, 18))
			r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.pressed.connect(func() -> void:
				if not locked:
					spectate_selected.emit())
			b.tooltip_text = "Watch a 5v5 match of bots (spectator mode)"
			continue
		var c := GameData.champion(id)
		# Until its portrait is photographed, a card shows the build's weapon.
		pic.texture = Icons.gear(str(c.get("equipment", {}).get("weapon", {}).get("icon", "")))
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var tag := OsrsUi.text(frame, str(c.get("tag", "")), 13, OsrsUi.YELLOW, Rect2(5, 3, 40, 18))
		tag.clip_text = false
		var name_l := OsrsUi.text(b, str(c.get("name", id)), 15, OsrsUi.ORANGE, Rect2(4, 115, CARD.x - 8, 20))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var role := OsrsUi.text(b, str(c.get("role", "")).replace(" · ", "\n"), 11, OsrsUi.WHITE, Rect2(4, 133, CARD.x - 8, 28))
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.add_theme_constant_override("line_spacing", -3)
		b.pressed.connect(select_build.bind(id))
		_cards[id] = b
		_portraits[id] = pic


## Photographs every build's figure for its card, one per frame.
func _render_portraits() -> void:
	for id in GameData.champion_order:
		if not is_inside_tree():
			return
		var tex: Texture2D = await _studio.snapshot(id)
		if tex != null and _portraits.has(id):
			(_portraits[id] as TextureRect).texture = tex
			(_portraits[id] as TextureRect).texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if is_instance_valid(_studio):
		_studio.show_champion("")
		_studio.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


# --- Centre: Equipment Stats -----------------------------------------------------

func _build_equipment(rect: Rect2) -> void:
	var p := OsrsUi.panel(_root, rect)
	_equip_title = OsrsUi.title(p, "Equipment Stats")
	OsrsUi.divider(p, 32)
	# Gear slots, in the OSRS equipment layout.
	var origin := Vector2(18, 46)
	for r in SLOT_LAYOUT.size():
		for c in 3:
			var s: String = SLOT_LAYOUT[r][c]
			if s == "":
				continue
			var slot := Panel.new()
			slot.add_theme_stylebox_override("panel", OsrsUi.slot_box())
			slot.position = origin + Vector2(c * (SLOT + 6), r * (SLOT + 6))
			slot.size = Vector2(SLOT, SLOT)
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			p.add_child(slot)
			var ghost := OsrsUi.text(slot, SLOT_NAMES[s].substr(0, 1), 18, Color(1, 1, 1, 0.1), Rect2(0, 0, SLOT, SLOT))
			ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ghost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var icon := Icons.rect(slot, null, Vector2(SLOT - 8, SLOT - 8))
			icon.position = Vector2(4, 4)
			icon.size = Vector2(SLOT - 8, SLOT - 8)
			_slots[s] = {"panel": slot, "icon": icon, "ghost": ghost}
	_build_info = OsrsUi.text(p, "", 13, OsrsUi.WHITE, Rect2(14, 326, 168, 116))
	_build_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_info.clip_text = false
	_build_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# The figure, slowly turning, on a dark stage.
	var stage := Panel.new()
	stage.add_theme_stylebox_override("panel", OsrsUi.slot_box(Color(0.09, 0.075, 0.058)))
	stage.position = Vector2(196, 42)
	stage.size = Vector2(250, 398)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(stage)
	_figure = FigureView.create(stage, Rect2(2, 2, 246, 394))
	# Bonuses, OSRS-style: name on the left, value in yellow on the right.
	var bx := 460.0
	var y := 42.0
	for section in [["Attack bonuses", [["damage", "Damage"], ["magic", "Magic power"], ["speed", "Attack speed"], ["range", "Range"]]],
			["Defence bonuses", [["health", "Health"], ["def_melee", "Melee defence"], ["def_ranged", "Ranged defence"], ["def_magic", "Magic defence"]]],
			["Other bonuses", [["move", "Move speed"], ["style", "Combat style"], ["level", "Combat level"], ["overheads", "Overheads (Z/X/C)"], ["prayer", "Prayer"]]]]:
		OsrsUi.text(p, section[0], 15, OsrsUi.ORANGE, Rect2(bx, y, 254, 20))
		y += 22.0
		for row in section[1]:
			OsrsUi.text(p, row[1], 13, OsrsUi.WHITE, Rect2(bx + 6, y, 140, 18))
			var v := OsrsUi.text(p, "", 13, OsrsUi.YELLOW, Rect2(bx + 120, y, 136, 18))
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_bonus_values[row[0]] = v
			y += 20.0
		y += 10.0


# --- Centre bottom: abilities ------------------------------------------------------

func _build_kit(rect: Rect2) -> void:
	var p := OsrsUi.panel(_root, rect)
	OsrsUi.title(p, "Abilities")
	OsrsUi.divider(p, 30)
	for i in 5:
		var y := 38.0 + i * 46.0
		var badge := Panel.new()
		badge.add_theme_stylebox_override("panel", OsrsUi.slot_box(Color(0.14, 0.12, 0.09)))
		badge.position = Vector2(14, y + 4)
		badge.size = Vector2(36, 36)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(badge)
		var key := OsrsUi.text(badge, "", 16 if i > 0 else 11, OsrsUi.YELLOW, Rect2(0, 0, 36, 36))
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var name_l := OsrsUi.text(p, "", 14, OsrsUi.ORANGE, Rect2(60, y, 650, 18))
		var text := OsrsUi.text(p, "", 12, OsrsUi.WHITE, Rect2(60, y + 17, 654, 32))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.max_lines_visible = 2
		text.clip_text = false
		text.add_theme_constant_override("line_spacing", -3)
		text.mouse_filter = Control.MOUSE_FILTER_STOP
		_kit_rows.append({"key": key, "name": name_l, "text": text})


# --- Right: side panel with tabs ---------------------------------------------------

func _build_side_panel(rect: Rect2) -> void:
	var p := OsrsUi.panel(_root, rect)
	var tab_names := [["skills", "Skills"], ["prayer", "Prayer"]]
	for i in tab_names.size():
		var t := Button.new()
		t.text = tab_names[i][1]
		t.toggle_mode = true
		t.position = Vector2(10 + i * 174, 8)
		t.size = Vector2(170, 34)
		OsrsUi.style_button(t, 15)
		t.add_theme_stylebox_override("pressed", OsrsUi.slot_box(Color(0.42, 0.18, 0.12), false, true))
		t.add_theme_stylebox_override("hover_pressed", OsrsUi.slot_box(Color(0.46, 0.2, 0.13), true, true))
		t.icon = Icons.prayer("Piety") if tab_names[i][0] == "prayer" else null
		t.expand_icon = false
		t.add_theme_constant_override("icon_max_width", 22)
		t.pressed.connect(show_tab.bind(tab_names[i][0]))
		p.add_child(t)
		_tabs[tab_names[i][0]] = t
	_skills = SkillsPanel.create(p)
	_skills.position = Vector2((rect.size.x - _skills.size.x) * 0.5, 52)
	_prayers = PrayerBookPanel.create(p)
	_prayers.position = Vector2(24, 52)
	_prayers.custom_minimum_size = Vector2(rect.size.x - 48, 0)
	_prayers.prayer_picked.connect(func(_id: String) -> void: _update_lock())
	var hint := OsrsUi.text(p, "Non-combat levels are rolled 20–75 every game, and the starred lucky skill up to 99 (the Skiller is 99), so which items you can buy changes. Hover a skill to see them.",
		12, OsrsUi.MUTED, Rect2(16, 542, rect.size.x - 32, 56))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.clip_text = false
	hint.size = Vector2(rect.size.x - 32, 56)     # (it grew to one line before wrapping was on)
	_hints["skills"] = hint
	show_tab("skills")


func show_tab(tab: String) -> void:
	for k in _tabs:
		(_tabs[k] as Button).set_pressed_no_signal(k == tab)
	_skills.visible = tab == "skills"
	_prayers.visible = tab == "prayer"
	for k in _hints:
		(_hints[k] as Label).visible = k == tab


# --- LOCK IN --------------------------------------------------------------------

func _build_lock(rect: Rect2) -> void:
	var p := OsrsUi.panel(_root, rect)
	_lock_summary = OsrsUi.text(p, "", 14, OsrsUi.YELLOW, Rect2(12, 10, rect.size.x - 24, 20))
	_lock_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock = Button.new()
	_lock.text = "LOCK IN"
	_lock.position = Vector2(12, 36)
	_lock.size = Vector2(rect.size.x - 24, 70)
	OsrsUi.style_button(_lock, 30, OsrsUi.ORANGE)
	_lock.pressed.connect(lock_in)
	p.add_child(_lock)
	_countdown = OsrsUi.text(_root, "", 20, OsrsUi.YELLOW, Rect2(0, 54, 1600, 26))
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Locks the build and prayer; the match starts after the countdown.
func lock_in() -> void:
	if locked or selected_id == "":
		return
	locked = true
	_count_left = COUNTDOWN
	for id in _cards:
		(_cards[id] as Button).disabled = id != selected_id
	_prayers.locked = true
	_lock.disabled = true
	_sub.visible = false
	_update_countdown()


func _process(delta: float) -> void:
	if _count_left < 0.0:
		return
	_count_left -= delta
	if _count_left <= 0.0:
		_count_left = -1.0
		champion_selected.emit(selected_id, _prayers.selected)
		return
	_update_countdown()


func _update_countdown() -> void:
	var secs := ceili(_count_left)
	_lock.text = "LOCKED IN — %d" % secs
	_countdown.text = "%s locked in — the game starts in %d" % [GameData.champion(selected_id).get("name", ""), secs]


func _update_lock() -> void:
	var c := GameData.champion(selected_id)
	var p := PrayerBook.find(_prayers.selected)
	_lock_summary.text = "%s   ·   %s" % [c.get("name", selected_id), p.get("name", "no prayer")]
	_bonus_values["prayer"].text = str(p.get("name", "none"))


# --- Selecting a build ------------------------------------------------------------------

## Shows a build everywhere: equipment, figure, bonuses, kit, skills, prayers.
func select_build(id: String, prayer_id: String = "") -> void:
	if locked or id == "":
		return
	selected_id = id
	for k in _cards:
		(_cards[k] as Button).set_pressed_no_signal(k == id)
	var c := GameData.champion_with_skills(id)
	_equip_title.text = "Equipment Stats — %s, %s" % [c.get("name", id), c.get("title", "")]
	var eq: Dictionary = c.get("equipment", {})
	for s in _slots:
		var e: Dictionary = eq.get(s, {})
		var icon: TextureRect = _slots[s]["icon"]
		icon.texture = Icons.gear(str(e.get("icon", "")))
		(_slots[s]["ghost"] as Label).visible = e.is_empty()
		(_slots[s]["panel"] as Panel).tooltip_text = "%s: %s" % [SLOT_NAMES[s], e.get("name", "empty")]
	_build_info.text = "%s\n\n%s\n%s" % [c.get("build", ""), str(c.get("style", "")).capitalize(), c.get("role", "")]
	_figure.show_champion(id)
	_show_bonuses(c)
	_show_kit(c)
	_skills.show_build(c)
	_prayers.show_build(c, prayer_id)
	_update_lock()


func _show_bonuses(c: Dictionary) -> void:
	var b: Dictionary = c.get("base", {})
	var d: Dictionary = b.get("defence", {})
	var ticks := int(b.get("attack_ticks", 4))
	_bonus_values["damage"].text = str(int(b.get("damage", 0)))
	_bonus_values["magic"].text = str(int(b.get("magic_power", 0)))
	_bonus_values["speed"].text = "%d ticks (%.1fs)" % [ticks, Combat.ticks_to_seconds(ticks)]
	_bonus_values["range"].text = "%.1f m" % float(b.get("attack_range", 2.0))
	_bonus_values["health"].text = str(int(b.get("max_health", 0)))
	_bonus_values["def_melee"].text = str(int(d.get("melee", 0)))
	_bonus_values["def_ranged"].text = str(int(d.get("ranged", 0)))
	_bonus_values["def_magic"].text = str(int(d.get("magic", 0)))
	_bonus_values["move"].text = "%.1f" % float(b.get("move_speed", 5.0))
	_bonus_values["style"].text = str(c.get("style", "")).capitalize()
	_bonus_values["level"].text = str(Combat.osrs_combat_level(c.get("skills", {})))
	_bonus_values["overheads"].text = "Yes" if c.get("overheads", false) else "No"


func _show_kit(c: Dictionary) -> void:
	var p: Dictionary = c.get("passive", {})
	var entries := [["Passive", p.get("name", ""), p.get("text", "")]]
	for slot in Champion.SLOTS:
		var ab: Dictionary = c.get("abilities", {}).get(slot, {})
		var name_text := str(ab.get("name", ""))
		if ab.has("forms") and name_text == "":
			var names: Array[String] = []
			for f in ab["forms"]:
				names.append(str(ab["forms"][f].get("name", "")))
			name_text = " / ".join(names)
		entries.append([slot.to_upper(), name_text, ab.get("text", "")])
	for i in _kit_rows.size():
		var row: Dictionary = _kit_rows[i]
		(row["key"] as Label).text = entries[i][0]
		(row["name"] as Label).text = str(entries[i][1])
		(row["text"] as Label).text = str(entries[i][2])
		(row["text"] as Label).tooltip_text = UiStyle.wrap(str(entries[i][2]))
