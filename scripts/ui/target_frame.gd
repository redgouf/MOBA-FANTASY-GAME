class_name TargetFrame
extends Panel
## Top-left "inspect" panel for the unit you left-clicked: name, level,
## health, prayer (its resource), stats, overhead prayer and items.
## Cooldowns and special attack energy are deliberately hidden.

const WIDTH := 400.0

var target: Unit

var _portrait: Panel
var _portrait_style: StyleBoxFlat
var _initial: Label
var _level: Label
var _title: Label
var _sub: Label
var _caption: Label
var _hp: StatBar
var _prayer: StatBar
var _stats: Label
var _info: Label
var _items_row: HBoxContainer
var _items: Array[ItemSlot] = []
var _buffs: BuffBar


static func create(parent: Control) -> TargetFrame:
	var f := TargetFrame.new()
	f.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BG))
	parent.add_child(f)
	UiStyle.place(f, Control.PRESET_TOP_LEFT, Vector2(8, 8), Vector2(WIDTH, 168))
	f.mouse_filter = Control.MOUSE_FILTER_STOP
	f._build()
	# Buffs/debuffs under the frame: allies (and yourself) only, never enemies.
	f._buffs = BuffBar.create(f, Rect2(0, 172, WIDTH, 34))
	f.visible = false
	return f


func _build() -> void:
	_portrait = Panel.new()
	_portrait_style = UiStyle.box(UiStyle.BG_SLOT, UiStyle.BORDER_HI, 2, 4)
	_portrait.add_theme_stylebox_override("panel", _portrait_style)
	_portrait.position = Vector2(10, 10)
	_portrait.size = Vector2(64, 64)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_initial = UiStyle.label(_portrait, "", 28, Color.WHITE)
	UiStyle.fill(_initial)
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level = UiStyle.label(self, "", 12, UiStyle.GOLD)
	_level.position = Vector2(10, 76)
	_level.size = Vector2(64, 16)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_caption = UiStyle.label(self, "", 11, UiStyle.MUTED)
	UiStyle.place(_caption, Control.PRESET_TOP_RIGHT, Vector2(-190, 6), Vector2(180, 14))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title = UiStyle.label(self, "", 17, UiStyle.TITLE)
	_title.position = Vector2(84, 6)
	_sub = UiStyle.label(self, "", 12, UiStyle.MUTED)
	_sub.position = Vector2(84, 28)
	_hp = StatBar.create(self, UiStyle.HP, Vector2(WIDTH - 96, 16), 12)
	_hp.position = Vector2(84, 48)
	_prayer = StatBar.create(self, UiStyle.PRAYER, Vector2(WIDTH - 96, 13), 11)
	_prayer.position = Vector2(84, 67)

	_stats = UiStyle.label(self, "", 12)
	_stats.position = Vector2(10, 96)
	_stats.size = Vector2(WIDTH - 20, 16)
	_info = UiStyle.label(self, "", 12, UiStyle.GOLD)
	_info.position = Vector2(10, 113)
	_info.size = Vector2(WIDTH - 20, 16)
	_info.clip_text = true

	_items_row = HBoxContainer.new()
	_items_row.add_theme_constant_override("separation", 4)
	_items_row.position = Vector2(10, 132)
	add_child(_items_row)
	for i in 6:
		_items.append(ItemSlot.create(_items_row, 30, "", true))


func portrait_rect() -> Rect2:
	return _portrait.get_global_rect()


func show_unit(u: Unit, viewer_team: int, caption: String = "") -> void:
	target = u
	_caption.text = caption
	if not is_instance_valid(u) or u.fog_hidden:
		visible = false
		return
	visible = true
	var enemy := u.team != viewer_team and u.team != Combat.Team.NEUTRAL
	var team_color := Unit.team_color(u.team)
	_portrait_style.bg_color = team_color.darkened(0.45)
	_portrait_style.border_color = UiStyle.HP_ENEMY if enemy else (UiStyle.HP if u.team == viewer_team else UiStyle.GOLD)
	_hp.set_color(UiStyle.HP_ENEMY if enemy else UiStyle.HP)
	_title.text = u.display_name
	var initial := u.display_name.substr(4, 1) if u.display_name.begins_with("The ") else u.display_name.substr(0, 1)
	if u is Champion:
		initial = str((u as Champion).def.get("tag", initial))
	_initial.text = initial

	var team_name: String = Combat.TEAM_NAMES[clampi(u.team, 0, 2)]
	var is_champ := u is Champion
	_items_row.visible = is_champ
	_prayer.visible = is_champ
	size.y = 168.0 if is_champ else 132.0

	var info: Array[String] = []
	if is_champ:
		var c := u as Champion
		_level.text = "Lvl %d" % c.level
		_sub.text = "%s · %s · combat %d" % [team_name, c.def.get("role", ""), c.combat_level()]
		_prayer.set_values(c.prayer, c.prayer_max, "Prayer %d / %d" % [int(c.prayer), int(c.prayer_max)])
		for i in 6:
			_items[i].set_item(c.inventory[i] if i < c.inventory.size() else "")
		if c.get_protected_style() >= 0:
			info.append("Protect from %s" % Combat.style_name(c.get_protected_style()).capitalize())
		if c.has_status("disable_prayer"):
			info.append("Prayers severed")
		if not c.forms.is_empty():
			info.append("%s form" % c.form_name().capitalize())
		if c.is_dead:
			info.append("Dead — respawns in %ds" % ceili(c.respawn_timer))
	else:
		_level.text = ""
		var kind := "minion"
		if u is Structure:
			kind = (u as Structure).kind
			if not u.is_damageable():
				info.append("Invulnerable until the structures in front of it fall")
		elif u is Monster:
			kind = "epic monster" if u.is_epic else "monster"
			var m := u as Monster
			if not m.cycle_styles.is_empty():
				info.append("Next attack: %s" % str(m.cycle_styles[m._cycle % m.cycle_styles.size()]))
		_sub.text = "%s %s" % [team_name, kind]
	_hp.set_values(u.health, u.max_health)
	_buffs.unit = u if u.team == viewer_team else null

	var style_name := Combat.style_name(u.attack_style).capitalize()
	var dmg := u.get_magic_power() if u.attack_style == Combat.Style.MAGIC else u.get_damage()
	_stats.text = "%s %d   Def %d / %d / %d   Atk %s   Move %.1f   Range %.1f" % [
		style_name, int(dmg), int(u.get_defence(0)), int(u.get_defence(1)), int(u.get_defence(2)),
		"%.1fs (%d ticks)" % [u.get_attack_interval(), roundi(u.attack_ticks)] if u.base_attack_range > 0.0 else "-",
		u.get_move_speed(), u.get_attack_range()]
	_info.text = "   ".join(info)
