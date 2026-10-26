class_name SkillsPanel
extends Panel
## An OSRS-style Skills tab for a build: the full 24-skill OSRS grid (every
## build has every skill since v0.8; non-combat levels are rolled each game).
## A definition with only combat skills gets the short combat-only layout.
## Levels show as "current / base" in yellow, with total level at the bottom. Hover a tile to see which shop items
## that level lets the build use, and which it's too low for.
## In a match, Hitpoints and Prayer show live values, like in OSRS.

const TILE := Vector2(112, 50)
const GAP := 2.0
const PAD := 6.0
const HEADER := 26.0
const FOOTER := 30.0
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
var _combat_head: Label
var _total: Label
var _parts: Array[Node] = []
var _refresh := 0.0


static func create(parent: Control) -> SkillsPanel:
	var p := SkillsPanel.new()
	parent.add_child(p)
	p._build()
	return p


static func panel_size(p_full: bool = false) -> Vector2:
	var rows := 8 if p_full else 6
	var cols := 3 if p_full else 2
	return Vector2(PAD * 2 + TILE.x * cols + GAP * (cols - 1), PAD * 2 + HEADER + rows * (TILE.y + GAP) + FOOTER)


## True when the real OSRS skill icons, fonts and stone are available.
static func osrs_look() -> bool:
	return OsrsFont.active and SkillIcons.has_icon("attack")


## True if the build has skilling levels, so it gets the full OSRS grid.
static func wants_full(def: Dictionary) -> bool:
	for s in def.get("skills", {}):
		if not Champion.SKILLS.has(str(s)):
			return true
	return false


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if OsrsSprites.available():
		OsrsSprites.stone_panel(self)     # the Skills tab's stone, edged like the game's interface
	else:
		add_theme_stylebox_override("panel", UiStyle.box(PANEL_BG, Color(0.07, 0.06, 0.05), 3, 4))
	_layout(true)


## OSRS text: the interface font at 2x (24 px), bold for the heading.
static func osrs_label(parent: Control, text: String, color: Color, bold: bool = false, px: int = 24) -> Label:
	var l := UiStyle.label(parent, text, px, color)
	var f := OsrsFont.get_font_any_size("b12_full" if bold else "p12_full") if OsrsFont.active else null
	if f != null:
		l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", px)
		l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		l.add_theme_constant_override("outline_size", 0)
		l.add_theme_color_override("font_shadow_color", Color.BLACK)
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _layout(p_full: bool) -> void:
	full = p_full
	for n in _parts:
		n.queue_free()
	_parts.clear()
	_tiles.clear()
	custom_minimum_size = panel_size(full)
	size = panel_size(full)
	var osrs := osrs_look()
	_title = osrs_label(self, "Skills", UiStyle.TITLE if not osrs else OsrsUi.ORANGE, true) if osrs else UiStyle.label(self, "Skills", 15, UiStyle.TITLE)
	_title.position = Vector2(PAD + 2, 2 if osrs else 4)
	_title.size = Vector2(size.x - PAD * 2 - 80, HEADER - 2)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_parts.append(_title)
	# The combat level, top right, beside the OSRS combat icon.
	var combat_icon := SkillIcons.has_icon("attack") and OsrsSprites.get_sprite("combat") != null
	if combat_icon:
		var ci := TextureRect.new()
		ci.texture = OsrsSprites.get_sprite("combat")
		ci.position = Vector2(size.x - PAD - 76, 3)
		ci.size = Vector2(25, 25)
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ci)
		_parts.append(ci)
	_combat_head = osrs_label(self, "", YELLOW) if osrs else UiStyle.label(self, "", 14, YELLOW)
	_combat_head.position = Vector2(size.x - PAD - 48, 2)
	_combat_head.size = Vector2(46, HEADER - 2)
	_combat_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combat_head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combat_head.tooltip_text = "Combat level"
	_combat_head.mouse_filter = Control.MOUSE_FILTER_STOP
	_parts.append(_combat_head)
	var y0 := PAD + HEADER
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
	# Footer: the total level beside the OSRS stats icon.
	var footer := Panel.new()
	footer.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.28), Color(0.05, 0.04, 0.03, 0.9), 1, 2))
	footer.position = Vector2(PAD, y0 + rows * (TILE.y + GAP) + 2)
	footer.size = Vector2(size.x - PAD * 2, FOOTER - 4)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)
	_parts.append(footer)
	var x_text := 8.0
	if OsrsSprites.get_sprite("stats") != null:
		var ti := TextureRect.new()
		ti.texture = OsrsSprites.get_sprite("stats")
		ti.position = Vector2(8, (footer.size.y - 25.0) * 0.5)
		ti.size = Vector2(25, 25)
		ti.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_child(ti)
		x_text = 40.0
	_total = osrs_label(footer, "", YELLOW) if osrs else UiStyle.label(footer, "", 14, YELLOW)
	_total.position = Vector2(x_text, 0)
	_total.size = Vector2(footer.size.x - x_text - 6, footer.size.y)
	_total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_combat_box(y0: float) -> void:
	# Second column under Hitpoints: the build's combat level, OSRS-style.
	var info := Panel.new()
	info.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.22), Color(0.05, 0.04, 0.03, 0.9), 1, 2))
	info.position = Vector2(PAD + TILE.x + GAP, y0 + TILE.y + GAP)
	info.size = Vector2(TILE.x, 5 * (TILE.y + GAP) - GAP)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	_parts.append(info)
	var osrs := osrs_look()
	if OsrsSprites.get_sprite("combat") != null:
		var ci := TextureRect.new()
		ci.texture = OsrsSprites.get_sprite("combat")
		ci.position = Vector2((TILE.x - 50.0) * 0.5, 14)
		ci.size = Vector2(50, 50)
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(ci)
	var cl := osrs_label(info, "Combat\nlevel", OsrsUi.ORANGE) if osrs else UiStyle.label(info, "Combat\nlevel", 13, UiStyle.TITLE)
	cl.position = Vector2(0, 74)
	cl.size = Vector2(TILE.x, 60)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combat = osrs_label(info, "", YELLOW, false, 48) if osrs else UiStyle.label(info, "", 30, YELLOW)
	_combat.position = Vector2(0, 140)
	_combat.size = Vector2(TILE.x, 56)
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
	if p_champ != null:
		def = def.duplicate()
		def["skills"] = p_champ.skills     # this game's rolled levels
	build = def
	champ = p_champ
	if wants_full(def) != full:
		_layout(wants_full(def))
	var skills: Dictionary = def.get("skills", {})
	_title.text = "%s" % def.get("name", "") if osrs_look() else "%s — Skills" % def.get("name", "")
	var combat := Combat.osrs_combat_level(skills)
	if _combat != null:
		_combat.text = str(combat)
	_combat_head.text = str(combat) if full else ""
	var total := 0
	for s in _tiles:
		total += level_of(skills, s)
	_total.text = "Total level: %d" % total
	var lucky := GameData.lucky_skill(str(def.get("id", "")))
	for s in _tiles:
		var t: SkillTile = _tiles[s]
		t.base = level_of(skills, s)
		t.current = t.base
		t.lucky = s == lucky
		var tip := skill_tooltip(def, s)
		if t.lucky:
			var parts := tip.split("\n")
			parts.insert(1, "Lucky roll! This game this skill could roll up to 99.")
			tip = "\n".join(parts)
		t.tooltip_text = "{%s} %s" % [s, tip] if SkillIcons.has_icon(s) else UiStyle.wrap(tip)
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
	# Potion boosts and drains: current / base, like OSRS.
	for s in _tiles:
		if s == "hitpoints" or s == "prayer":
			continue
		var t: SkillTile = _tiles[s]
		var now := champ.boosted_skill(s)
		if now != t.current:
			t.current = now
			t.queue_redraw()


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
			var unlocked := 0
			for p in PrayerBook.all():
				if lvl >= int(p.get("level", 99)):
					unlocked += 1
			lines.append("Prayers unlocked: %d of %d (pick one at champion select)" % [unlocked, PrayerBook.all().size()])
			lines.append("Default pick: %s" % PrayerBook.find(PrayerBook.default_for(def)).get("name", "none"))
			lines.append("Protection prayers on Z/X/C: %s" % ("yes" if def.get("overheads", false) else "no (but can pick one as its prayer at 37+)"))
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
	# Food and potions made Perfect (+15%) by this skill, and gear you can make.
	var perfect: Array[String] = []
	var make: Array[String] = []
	for id in GameData.item_order:
		var it := GameData.item(id)
		var pot: Dictionary = it.get("potency", {})
		if pot.has(skill) and lvl >= int(pot[skill]):
			perfect.append(str(it.get("name", id)))
		var art: Dictionary = it.get("artisan", {})
		if art.has(skill) and lvl >= int(art[skill]):
			make.append(str(it.get("name", id)))
	if not perfect.is_empty():
		lines.append("'perfect' (+%d%%): %s" % [roundi(float(GameData.rule("potency_bonus", 0.15)) * 100.0), ", ".join(perfect)])
	if not make.is_empty():
		lines.append("Make your own (no combat requirements): " + ", ".join(make))
	if usable.is_empty() and locked.is_empty() and perfect.is_empty() and make.is_empty() and skill != "hitpoints" and skill != "prayer" and lines.size() == 1:
		lines.append("No shop items or abilities use %s yet." % skill.capitalize())
	return "\n".join(lines)


## One skill: its OSRS icon on the left, "current" over "base" on the right
## (drawn like the Skills tab; the vector icons and stone tile without the pack).
class SkillTile extends Control:
	var skill := ""
	var base := 1
	var current := 1
	var lucky := false             # this game's lucky roll (up to 99): a gold star
	var _hover := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())

	func _make_custom_tooltip(for_text: String) -> Object:
		return SkillIcons.make_tooltip(for_text) if for_text.contains("{") else null

	func _draw() -> void:
		var tex := OsrsSprites.get_sprite(skill)
		var font: Font = OsrsFont.get_font_any_size("p12_full") if OsrsFont.active else null
		var col := Color(0.2, 1.0, 0.2) if current > base else (SkillsPanel.YELLOW if current == base else Color(1.0, 0.55, 0.1))
		if tex != null and font != null:
			# Faint recess behind each skill, lighter under the mouse.
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.1) if _hover else Color(0, 0, 0, 0.14))
			draw_texture_rect(tex, Rect2(Vector2(2, (size.y - 50.0) * 0.5), Vector2(50, 50)), false)
			if lucky:
				_star(Vector2(size.x - 9.0, 9.0), 6.0)
			_shadow_text(font, Vector2(56, 22), str(current), 24, col, 2)
			draw_line(Vector2(84, 40), Vector2(96, 14), Color(0.05, 0.05, 0.05), 3.0)
			draw_line(Vector2(83, 39), Vector2(95, 13), SkillsPanel.YELLOW, 1.0)
			_shadow_text(font, Vector2(80, 44), str(base), 24, SkillsPanel.YELLOW, 2)
			return
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, SkillsPanel.STONE)
		# Bevel like the OSRS stone tiles.
		draw_line(Vector2(0, 0), Vector2(size.x, 0), SkillsPanel.STONE_LIGHT, 2.0)
		draw_line(Vector2(0, 0), Vector2(0, size.y), SkillsPanel.STONE_LIGHT, 2.0)
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), SkillsPanel.STONE_DARK, 2.0)
		draw_line(Vector2(size.x - 1, 0), Vector2(size.x - 1, size.y), SkillsPanel.STONE_DARK, 2.0)
		SkillIcons.draw_icon(self, skill, Vector2(22, size.y * 0.5), 15.0)
		if lucky:
			_star(Vector2(size.x - 9.0, 9.0), 6.0)
		var f := get_theme_default_font()
		_shadow_text(f, Vector2(46, 22), str(current), 17, col, 1)
		draw_line(Vector2(62, 34), Vector2(74, 14), Color(0.05, 0.05, 0.05), 3.0)
		draw_line(Vector2(61, 33), Vector2(73, 13), SkillsPanel.YELLOW, 1.5)
		_shadow_text(f, Vector2(70, 40), str(base), 17, SkillsPanel.YELLOW, 1)

	func _star(c: Vector2, r: float) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var ang := -PI * 0.5 + PI * float(i) / 5.0
			pts.append(c + Vector2(cos(ang), sin(ang)) * (r if i % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, Color(1.0, 0.84, 0.2))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.25, 0.15, 0.0), 1.0)

	func _shadow_text(font: Font, pos: Vector2, text: String, fsize: int, col: Color, shadow: int) -> void:
		draw_string(font, pos + Vector2(shadow, shadow), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.BLACK)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
