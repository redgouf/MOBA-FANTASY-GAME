class_name SkillsPanel
extends Panel
## An OSRS-style Skills tab for a build. Combat builds show the combat skills
## where OSRS puts them (Attack, Strength, Defence, Ranged, Prayer, Magic down
## the first column; Hitpoints top of the second) plus combat level. Builds
## with skilling levels (the Skiller) get the full 24-skill OSRS grid.
## Levels show as "current / base" in yellow, with total level at the bottom. Hover a tile to see which shop items
## that level lets the build use, and which it's too low for.
## In a match, Hitpoints and Prayer show live values, like in OSRS.

const TILE := Vector2(104, 46)
const GAP := 4.0
const PAD := 8.0
const COLUMN_1: Array[String] = ["attack", "strength", "defence", "ranged", "prayer", "magic"]
## The OSRS Skills tab, row by row (3 columns, 8 rows, Sailing included).
const FULL_LAYOUT := [["attack", "hitpoints", "mining"], ["strength", "agility", "smithing"],
	["defence", "herblore", "fishing"], ["ranged", "thieving", "cooking"], ["prayer", "crafting", "firemaking"],
	["magic", "fletching", "woodcutting"], ["runecraft", "slayer", "farming"], ["construction", "hunter", "sailing"]]

const STONE := Color(0.24, 0.215, 0.18)
const STONE_LIGHT := Color(0.36, 0.33, 0.28)
const STONE_DARK := Color(0.11, 0.1, 0.085)
const PANEL_BG := Color(0.17, 0.15, 0.12, 0.97)
const YELLOW := Color(1.0, 1.0, 0.0)

var build: Dictionary = {}
var champ: Champion

var full := false

var _tiles: Dictionary = {}
var _title: Label
var _combat: Label
var _total: Label
var _parts: Array[Node] = []
var _refresh := 0.0


static func create(parent: Control) -> SkillsPanel:
	var p := SkillsPanel.new()
	parent.add_child(p)
	p._build()
	return p


static func panel_size(p_full: bool = false) -> Vector2:
	if p_full:
		return Vector2(PAD * 2 + TILE.x * 3 + GAP * 2, PAD * 2 + 26 + 8 * (TILE.y + GAP) + 30)
	return Vector2(PAD * 2 + TILE.x * 2 + GAP, PAD * 2 + 26 + 6 * (TILE.y + GAP) + 30)


## True if the build has skilling levels, so it gets the full OSRS grid.
static func wants_full(def: Dictionary) -> bool:
	for s in def.get("skills", {}):
		if not Champion.SKILLS.has(str(s)):
			return true
	return false


func _build() -> void:
	var sb := UiStyle.box(PANEL_BG, Color(0.07, 0.06, 0.05), 3, 4)
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout(false)


func _layout(p_full: bool) -> void:
	full = p_full
	for n in _parts:
		n.queue_free()
	_parts.clear()
	_tiles.clear()
	custom_minimum_size = panel_size(full)
	size = panel_size(full)
	_title = UiStyle.label(self, "Skills", 15, UiStyle.TITLE)
	_title.position = Vector2(PAD, 4)
	_title.size = Vector2(size.x - PAD * 2, 20)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_parts.append(_title)
	var y0 := PAD + 22.0
	var rows := 6
	if full:
		rows = FULL_LAYOUT.size()
		for r in FULL_LAYOUT.size():
			for c in 3:
				_add_tile(FULL_LAYOUT[r][c], Vector2(PAD + c * (TILE.x + GAP), y0 + r * (TILE.y + GAP)))
		_combat = null
	else:
		for i in COLUMN_1.size():
			_add_tile(COLUMN_1[i], Vector2(PAD, y0 + i * (TILE.y + GAP)))
		_add_tile("hitpoints", Vector2(PAD + TILE.x + GAP, y0))
		_build_combat_box(y0)
	var footer := Panel.new()
	footer.add_theme_stylebox_override("panel", UiStyle.box(STONE_DARK, STONE_LIGHT.darkened(0.3), 1, 2))
	footer.position = Vector2(PAD, y0 + rows * (TILE.y + GAP))
	footer.size = Vector2(size.x - PAD * 2, 26)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)
	_parts.append(footer)
	_total = UiStyle.label(footer, "", 14, YELLOW)
	UiStyle.fill(_total)
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_combat_box(y0: float) -> void:
	# Second column under Hitpoints: the build's combat level, OSRS-style.
	var info := Panel.new()
	info.add_theme_stylebox_override("panel", UiStyle.box(STONE_DARK, STONE_LIGHT.darkened(0.3), 1, 2))
	info.position = Vector2(PAD + TILE.x + GAP, y0 + TILE.y + GAP)
	info.size = Vector2(TILE.x, 5 * (TILE.y + GAP) - GAP)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	_parts.append(info)
	var cl := UiStyle.label(info, "Combat\nlevel", 13, UiStyle.TITLE)
	cl.position = Vector2(0, 40)
	cl.size = Vector2(TILE.x, 40)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combat = UiStyle.label(info, "", 30, YELLOW)
	_combat.position = Vector2(0, 84)
	_combat.size = Vector2(TILE.x, 40)
	_combat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _add_tile(skill: String, pos: Vector2) -> void:
	var t := SkillTile.new()
	t.skill = skill
	t.position = pos
	t.size = TILE
	add_child(t)
	_tiles[skill] = t
	_parts.append(t)


## Show a build's skills. Pass the champion in a match for live HP/Prayer.
func show_build(def: Dictionary, p_champ: Champion = null) -> void:
	build = def
	champ = p_champ
	if wants_full(def) != full:
		_layout(wants_full(def))
	var skills: Dictionary = def.get("skills", {})
	_title.text = "%s — Skills" % def.get("name", "")
	var combat := Combat.osrs_combat_level(skills)
	if _combat != null:
		_combat.text = str(combat)
	var total := 0
	for s in _tiles:
		total += level_of(skills, s)
	_total.text = "Total level: %d%s" % [total, "    ·    Combat level: %d" % combat if full else ""]
	for s in _tiles:
		var t: SkillTile = _tiles[s]
		t.base = level_of(skills, s)
		t.current = t.base
		t.tooltip_text = UiStyle.wrap(skill_tooltip(def, s))
		t.queue_redraw()
	_update_live()


func _process(delta: float) -> void:
	if not visible or not is_instance_valid(champ):
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.2
		_update_live()


func _update_live() -> void:
	if not is_instance_valid(champ):
		return
	var hp: SkillTile = _tiles["hitpoints"]
	hp.current = 0 if champ.is_dead else maxi(1, ceili(float(hp.base) * champ.health_ratio()))
	var pr: SkillTile = _tiles["prayer"]
	pr.current = ceili(float(pr.base) * champ.prayer / maxf(champ.prayer_max, 1.0))
	hp.queue_redraw()
	pr.queue_redraw()


static func level_of(skills: Dictionary, skill: String) -> int:
	return int(skills.get(skill, 10 if skill == "hitpoints" else 1))


## Tooltip: what this level means for the build, and which items it gates.
static func skill_tooltip(def: Dictionary, skill: String) -> String:
	var skills: Dictionary = def.get("skills", {})
	var lvl := level_of(skills, skill)
	var lines: Array[String] = ["%s: %d" % [skill.capitalize(), lvl]]
	var abilities: Dictionary = def.get("abilities", {})
	for slot in abilities:
		var ab: Dictionary = abilities[slot]
		if str(ab.get("skill", "")) == skill:
			lines.append("Powers %s — %s" % [str(slot).to_upper(), ab.get("name", "")])
	match skill:
		"hitpoints":
			lines.append("Shows your health as a Hitpoints level (current / base).")
		"prayer":
			var names: Array[String] = []
			for style in ["melee", "ranged", "magic"]:
				for p in GameData.rule("offensive_prayers", {}).get(style, []):
					if lvl >= int(p.get("level", 99)):
						names.append(str(p["name"]))
						break
			lines.append("Offensive prayers: %s" % (", ".join(names) if not names.is_empty() else "none"))
			lines.append("Protection prayers: %s" % ("yes (Z/X/C)" if def.get("overheads", false) else "no (not this build)"))
	var usable: Array[String] = []
	var locked: Array[String] = []
	for id in GameData.item_order:
		var it := GameData.item(id)
		var reqs: Dictionary = it.get("requirements", {})
		if not reqs.has(skill):
			continue
		var entry := "%s (%d)" % [it.get("name", id), int(reqs[skill])]
		if lvl >= int(reqs[skill]):
			usable.append(entry)
		else:
			locked.append(entry)
	if not usable.is_empty():
		lines.append("Can use: " + ", ".join(usable))
	if not locked.is_empty():
		lines.append("Too low for: " + ", ".join(locked))
	if usable.is_empty() and locked.is_empty() and skill != "hitpoints" and skill != "prayer" and lines.size() == 1:
		lines.append("No shop items or abilities use %s yet." % skill.capitalize())
	return "\n".join(lines)


## One stone tile: skill icon on the left, "current / base" on the right.
class SkillTile extends Control:
	var skill := ""
	var base := 1
	var current := 1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, SkillsPanel.STONE)
		# Bevel like the OSRS stone tiles.
		draw_line(Vector2(0, 0), Vector2(size.x, 0), SkillsPanel.STONE_LIGHT, 2.0)
		draw_line(Vector2(0, 0), Vector2(0, size.y), SkillsPanel.STONE_LIGHT, 2.0)
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), SkillsPanel.STONE_DARK, 2.0)
		draw_line(Vector2(size.x - 1, 0), Vector2(size.x - 1, size.y), SkillsPanel.STONE_DARK, 2.0)
		SkillIcons.draw_icon(self, skill, Vector2(22, size.y * 0.5), 15.0)
		var font := get_theme_default_font()
		var col := SkillsPanel.YELLOW if current >= base else Color(1.0, 0.55, 0.1)
		_shadow_text(font, Vector2(46, 22), str(current), 17, col)
		draw_line(Vector2(62, 34), Vector2(74, 14), Color(0.05, 0.05, 0.05), 3.0)
		draw_line(Vector2(61, 33), Vector2(73, 13), SkillsPanel.YELLOW, 1.5)
		_shadow_text(font, Vector2(70, 40), str(base), 17, SkillsPanel.YELLOW)

	func _shadow_text(font: Font, pos: Vector2, text: String, fsize: int, col: Color) -> void:
		draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.BLACK)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
