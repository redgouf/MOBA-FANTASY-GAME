class_name MatchScoreboard
extends PanelContainer
## Hold TAB: every champion in the match, by team, with level, K/D/A, CS,
## special (offensive) prayer and items. Enemy items are the last ones your
## team saw them with: they update only while an enemy is within vision of one
## of your units (champions, minions, towers), like League's scoreboard.

const VISION := 16.0
const ITEM_SLOTS := 6
const ROW_H := 34.0

var main: Node
## The team whose eyes we use; -1 sees everything (spectator mode).
var viewer_team := -1

var _seen: Dictionary = {}        # Champion -> {"items": Array[String], "time": float}
var _scan := 0.0
var _refresh := 0.0
var _team_boxes: Array[VBoxContainer] = []
var _team_titles: Array[Label] = []
var _rows: Dictionary = {}        # Champion -> row widgets


static func create(parent: Control, p_main: Node) -> MatchScoreboard:
	var s := MatchScoreboard.new()
	s.main = p_main
	parent.add_child(s)
	UiStyle.place(s, Control.PRESET_CENTER, Vector2(-450, -250), Vector2(900, 0))
	s._build()
	s.visible = false
	return s


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiStyle.solid_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var title := UiStyle.label(col, "Scoreboard", 20, UiStyle.TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var head := _row_box(col)
	_cell(head, "", 34)
	_cell(head, "Champion", 210, UiStyle.MUTED)
	_cell(head, "K / D / A", 84, UiStyle.MUTED)
	_cell(head, "CS", 46, UiStyle.MUTED)
	_cell(head, "Special prayer", 160, UiStyle.MUTED)
	_cell(head, "Items", 200, UiStyle.MUTED)
	for team in 2:
		var t := UiStyle.label(col, "", 16, Unit.team_color(team).lightened(0.35))
		_team_titles.append(t)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(box)
		_team_boxes.append(box)
	var foot := UiStyle.label(col, "Enemy items are what your team last saw them wearing.", 12, UiStyle.MUTED)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _row_box(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _cell(parent: Control, text: String, width: float, color: Color = UiStyle.TEXT, size: int = 14) -> Label:
	var l := UiStyle.label(parent, text, size, color)
	l.custom_minimum_size = Vector2(width, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	return l


func _make_row(c: Champion) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BG_SLOT.darkened(0.25), Unit.team_color(c.team).darkened(0.3), 1, 3))
	_team_boxes[clampi(c.team, 0, 1)].add_child(panel)
	var r := _row_box(panel)
	r.custom_minimum_size = Vector2(0, ROW_H)
	var tag := _cell(r, str(c.def.get("tag", "")), 34, Color.WHITE, 16)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := {"panel": panel, "tag": tag}
	row["name"] = _cell(r, "", 210)
	row["kda"] = _cell(r, "", 84)
	row["cs"] = _cell(r, "", 46)
	var pray := HBoxContainer.new()
	pray.custom_minimum_size = Vector2(160, 0)
	pray.add_theme_constant_override("separation", 4)
	pray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(pray)
	row["prayer_icon"] = Icons.rect(pray, null, Vector2(30, 30))
	row["prayer"] = _cell(pray, "", 128, UiStyle.PRAYER.lightened(0.3), 13)
	var items: Array[TextureRect] = []
	for i in ITEM_SLOTS:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(34, 34)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BG_DARK, UiStyle.BORDER.darkened(0.3), 1, 2))
		r.add_child(slot)
		var icon := Icons.rect(slot, null, Vector2.ZERO)
		UiStyle.fill(icon, 2, 2, 2, 2)
		items.append(icon)
	row["items"] = items
	row["seen"] = _cell(r, "", 80, UiStyle.MUTED, 12)
	return row


func _champions() -> Array:
	return main.get("champions") if main != null else []


func _process(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.5
		_update_seen()
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		refresh()


## Remember what each enemy was wearing while our team could see them.
func _update_seen() -> void:
	for c in _champions():
		var ch := c as Champion
		if ch == null:
			continue
		if viewer_team < 0 or ch.team == viewer_team or is_seen_by(ch, viewer_team):
			_seen[ch] = {"items": ch.inventory.duplicate(), "time": Combat.clock}
		elif not _seen.has(ch):
			_seen[ch] = {"items": [], "time": -1.0}      # not seen yet


func is_seen_by(c: Champion, team: int) -> bool:
	if c.is_dead:
		return false
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u != null and u.team == team and not u.is_dead and u.flat_distance_to(c) <= VISION:
			return true
	return false


## Items shown for `c`: live for allies (and spectators), last seen for enemies.
func shown_items(c: Champion) -> Array:
	var items: Array = c.inventory if viewer_team < 0 or c.team == viewer_team else _seen.get(c, {}).get("items", [])
	return items.filter(func(id: Variant) -> bool: return str(id) != "")


func refresh() -> void:
	var tk: Array = main.get("team_kills") if main != null else [0, 0]
	for team in 2:
		_team_titles[team].text = "%s  —  %d kills" % [Combat.TEAM_NAMES[team], int(tk[team])]
	for c in _champions():
		var ch := c as Champion
		if ch == null:
			continue
		if not _rows.has(ch):
			_rows[ch] = _make_row(ch)
		var row: Dictionary = _rows[ch]
		var you: bool = main != null and main.get("player") == ch
		var name_text := "%s  Lv %d" % [ch.display_name, ch.level]
		if you:
			name_text += "  (you)"
		if ch.is_dead:
			name_text += "  † %ds" % ceili(ch.respawn_timer)
		(row["name"] as Label).text = name_text
		(row["name"] as Label).modulate = Color(1, 1, 1, 0.55) if ch.is_dead else Color.WHITE
		(row["kda"] as Label).text = "%d / %d / %d" % [ch.kills, ch.deaths, ch.assists]
		(row["cs"] as Label).text = str(ch.creep_score)
		var p := ch.chosen_prayer_data()
		var on := ch.is_praying(ch.chosen_prayer)
		(row["prayer_icon"] as TextureRect).texture = Icons.prayer(str(p.get("name", "")))
		(row["prayer_icon"] as TextureRect).modulate = Color.WHITE if on else Color(0.55, 0.55, 0.55)
		(row["prayer"] as Label).text = str(p.get("name", "None")) + ("  (on)" if on else "")
		(row["prayer"] as Label).tooltip_text = PrayerBook.effect_text(p)
		var items := shown_items(ch)
		var icons: Array = row["items"]
		for i in ITEM_SLOTS:
			(icons[i] as TextureRect).texture = Icons.item(str(items[i])) if i < items.size() else null
		var seen_text := ""
		if viewer_team >= 0 and ch.team != viewer_team and _seen.has(ch):
			var ago := Combat.clock - float(_seen[ch]["time"])
			if float(_seen[ch]["time"]) < 0.0:
				seen_text = "not seen yet"
			elif ago > 1.0:
				seen_text = "seen %d:%02d ago" % [int(ago) / 60, int(ago) % 60]
		(row["seen"] as Label).text = seen_text
