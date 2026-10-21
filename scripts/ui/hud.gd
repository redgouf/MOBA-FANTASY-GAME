class_name Hud
extends CanvasLayer
## In-game HUD, laid out like League of Legends:
##   top-left      target inspect panel (left-click a unit)
##   top-right     team score, game clock, K/D/A, CS, FPS
##   left          kill feed
##   bottom-left   portrait, level/XP, stats, 6 item slots, food belt, gold
##   bottom-centre passive, Q W E R (ranks, cooldowns, level-up), prayers, bars
##   bottom-right  minimap
## In spectator (NPC vs NPC) mode it also shows both team rosters, a banner,
## and the focused bot's "mouse" (GhostCursor); set_champion() switches whose
## perspective the HUD shows.

var main: Node
var champ: Champion
var spectator := false
var ghost_cursor: GhostCursor

var target_frame: TargetFrame
var minimap: Minimap

var _score: Label
var _feed: VBoxContainer
var _feed_entries: Array[Dictionary] = []
var _message: Label
var _channel: Label
var _hint: Label
var _status: Label

# bottom-left
var _portrait_style: StyleBoxFlat
var _portrait_initial: Label
var _level_badge: Label
var _name: Label
var _xp: StatBar
var _stats: Dictionary = {}
var _item_slots: Array[ItemSlot] = []
var _belt_slots: Array[ItemSlot] = []
var _gold: Label

# bottom-centre
var _passive: Panel
var _passive_label: Label
var _ability_slots: Dictionary = {}
var _offensive: Panel
var _offensive_name: Label
var _offensive_shade: ColorRect
var _overheads: Array[Button] = []
var _overhead_col: VBoxContainer
var _banner: Label
var _root: Control
var _portrait_panel: Panel
var _skills_popup: SkillsPanel
var _target_skills_popup: SkillsPanel
var _skills_shown_for: Champion
var _target_skills_shown_for: Unit
var force_skills_popups := false     # screenshots/debug: keep both popups open
var _roster_cards: Array[Dictionary] = []
var _hp: StatBar
var _prayer: StatBar
var _spec: StatBar

var _shop: Panel
var _shop_list: VBoxContainer
var _shop_gold: Label
var _shop_refresh := 0.0
var _game_over: Label
var _message_timer := 0.0


func setup(p_main: Node, p_champ: Champion, p_spectator: bool = false) -> void:
	main = p_main
	champ = p_champ
	spectator = p_spectator


## Show the HUD from another champion's point of view (spectator lock-on).
func set_champion(c: Champion) -> void:
	champ = c
	if _portrait_style != null:
		_portrait_style.bg_color = Unit.team_color(c.team).darkened(0.45)
	if minimap != null:
		minimap.player = c
	if ghost_cursor != null:
		ghost_cursor.watch(c)
	if _overhead_col != null:
		_overhead_col.visible = c.has_overheads


func _ready() -> void:
	var root := Control.new()
	UiStyle.fill(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root

	target_frame = TargetFrame.create(root)
	_build_scoreboard(root)
	_build_feed(root)
	_build_bottom_left(root)
	_build_bottom_center(root)
	_build_minimap(root)
	_build_shop(root)

	_message = UiStyle.label(root, "", 28, UiStyle.TITLE)
	UiStyle.place(_message, Control.PRESET_CENTER_TOP, Vector2(-450, 64 if not spectator else 52), Vector2(900, 40))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_game_over = UiStyle.label(root, "", 56, UiStyle.TITLE)
	UiStyle.place(_game_over, Control.PRESET_CENTER, Vector2(-500, -60), Vector2(1000, 80))
	_game_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.visible = false
	if spectator:
		_build_spectator(root)
	# OSRS Skills tab popups: hover your portrait, or the inspect panel's portrait.
	var sz := SkillsPanel.panel_size()
	_skills_popup = SkillsPanel.create(root)
	UiStyle.place(_skills_popup, Control.PRESET_BOTTOM_LEFT, Vector2(8, -206 - sz.y), sz)
	_skills_popup.visible = false
	_target_skills_popup = SkillsPanel.create(root)
	UiStyle.place(_target_skills_popup, Control.PRESET_TOP_LEFT, Vector2(8, 182), sz)
	_target_skills_popup.visible = false


# --- Layout ------------------------------------------------------------------

func _build_scoreboard(root: Control) -> void:
	var p := UiStyle.panel(root, Control.PRESET_TOP_RIGHT, Vector2(-448, 8), Vector2(440, 36))
	_score = UiStyle.label(p, "", 14)
	UiStyle.fill(_score)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_feed(root: Control) -> void:
	_feed = VBoxContainer.new()
	UiStyle.place(_feed, Control.PRESET_BOTTOM_LEFT, Vector2(12, -420), Vector2(520, 200))
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", 2)
	root.add_child(_feed)


func _build_bottom_left(root: Control) -> void:
	var p := UiStyle.panel(root, Control.PRESET_BOTTOM_LEFT, Vector2(8, -200), Vector2(470, 192))
	p.mouse_filter = Control.MOUSE_FILTER_STOP

	var portrait := Panel.new()
	_portrait_style = UiStyle.box(Unit.team_color(champ.team).darkened(0.45), UiStyle.BORDER_HI, 2, 4)
	portrait.add_theme_stylebox_override("panel", _portrait_style)
	portrait.position = Vector2(10, 10)
	portrait.size = Vector2(96, 96)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(portrait)
	_portrait_panel = portrait
	_portrait_initial = UiStyle.label(portrait, "", 44, Color.WHITE)
	UiStyle.fill(_portrait_initial)
	_portrait_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var badge := Panel.new()
	badge.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BG_DARK, UiStyle.GOLD, 2, 12))
	badge.position = Vector2(70, 70)
	badge.size = Vector2(32, 32)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(badge)
	_level_badge = UiStyle.label(badge, "1", 15, UiStyle.GOLD)
	UiStyle.fill(_level_badge)
	_level_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_name = UiStyle.label(p, "", 13, UiStyle.TITLE)
	_name.position = Vector2(10, 110)
	_name.size = Vector2(100, 36)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xp = StatBar.create(p, UiStyle.XP, Vector2(96, 12), 9)
	_xp.position = Vector2(10, 168)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	grid.position = Vector2(118, 10)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(grid)
	for key in ["damage", "magic", "attack_speed", "range", "move", "melee_def", "ranged_def", "magic_def", "armor_pen", "combat"]:
		var l := UiStyle.label(grid, "", 13)
		l.custom_minimum_size = Vector2(80, 0)
		_stats[key] = l

	var items := GridContainer.new()
	items.columns = 3
	items.add_theme_constant_override("h_separation", 4)
	items.add_theme_constant_override("v_separation", 4)
	items.position = Vector2(296, 10)
	p.add_child(items)
	for i in 6:
		_item_slots.append(ItemSlot.create(items, 52, str(i + 1)))

	var belt := HBoxContainer.new()
	belt.add_theme_constant_override("separation", 4)
	belt.position = Vector2(296, 124)
	p.add_child(belt)
	for i in 4:
		_belt_slots.append(ItemSlot.create(belt, 38, str((i + 7) % 10), true))

	_gold = UiStyle.label(p, "", 15, UiStyle.GOLD)
	_gold.position = Vector2(296, 166)
	_gold.size = Vector2(164, 20)


func _build_bottom_center(root: Control) -> void:
	var p := UiStyle.panel(root, Control.PRESET_CENTER_BOTTOM, Vector2(-310, -164), Vector2(620, 156))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var x := 52.0

	_passive = Panel.new()
	_passive.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BG_DARK, UiStyle.BORDER, 2, 4))
	_passive.position = Vector2(x, 16)
	_passive.size = Vector2(60, 60)
	p.add_child(_passive)
	var ptag := UiStyle.label(_passive, "Passive", 9, UiStyle.MUTED)
	ptag.position = Vector2(4, 1)
	_passive_label = UiStyle.label(_passive, "", 10)
	UiStyle.fill(_passive_label, 0, 10)
	_passive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_passive_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_passive_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	x += 68.0

	for slot in Champion.SLOTS:
		var a := AbilitySlot.create(p, slot, 72)
		a.position = Vector2(x, 10)
		a.level_up_pressed.connect(func(s: String) -> void: champ.rank_up(s))
		_ability_slots[slot] = a
		x += 80.0

	_offensive = Panel.new()
	_offensive.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.BG_SLOT, UiStyle.PRAYER.darkened(0.2), 2, 4))
	_offensive.position = Vector2(x, 16)
	_offensive.size = Vector2(60, 60)
	p.add_child(_offensive)
	var vkey := UiStyle.label(_offensive, "V", 12, UiStyle.TITLE)
	vkey.position = Vector2(4, 1)
	_offensive_name = UiStyle.label(_offensive, "", 10)
	UiStyle.fill(_offensive_name, 0, 8)
	_offensive_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offensive_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_offensive_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offensive_shade = ColorRect.new()
	_offensive_shade.color = Color(0, 0, 0, 0.6)
	_offensive_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offensive.add_child(_offensive_shade)
	x += 68.0

	_overhead_col = VBoxContainer.new()
	_overhead_col.add_theme_constant_override("separation", 2)
	_overhead_col.position = Vector2(x, 12)
	_overhead_col.visible = champ.has_overheads
	p.add_child(_overhead_col)
	var labels := ["Z Melee", "X Range", "C Magic"]
	for i in 3:
		var b := UiStyle.button(_overhead_col, labels[i], 10)
		b.custom_minimum_size = Vector2(62, 20)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.disabled = spectator
		b.tooltip_text = "Protect from %s" % ["Melee", "Missiles", "Magic"][i]
		b.pressed.connect(func() -> void: champ.toggle_protect(i))
		_overheads.append(b)

	_hp = StatBar.create(p, UiStyle.HP, Vector2(600, 18), 13)
	_hp.position = Vector2(10, 94)
	_prayer = StatBar.create(p, UiStyle.PRAYER, Vector2(600, 13), 10)
	_prayer.position = Vector2(10, 115)
	_spec = StatBar.create(p, UiStyle.SPEC, Vector2(600, 13), 10)
	_spec.position = Vector2(10, 131)

	_hint = UiStyle.label(root, "", 15, UiStyle.GOLD)
	UiStyle.place(_hint, Control.PRESET_CENTER_BOTTOM, Vector2(-310, -228), Vector2(620, 20))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_channel = UiStyle.label(root, "", 20, UiStyle.TEXT)
	UiStyle.place(_channel, Control.PRESET_CENTER_BOTTOM, Vector2(-310, -256), Vector2(620, 26))
	_channel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = UiStyle.label(root, "", 13, UiStyle.MUTED)
	UiStyle.place(_status, Control.PRESET_CENTER_BOTTOM, Vector2(-310, -186), Vector2(620, 18))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_minimap(root: Control) -> void:
	var frame := UiStyle.panel(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-268, -268), Vector2(260, 260), UiStyle.BG_DARK)
	minimap = Minimap.new()
	minimap.position = Vector2(4, 4)
	minimap.size = Vector2(252, 252)
	minimap.player = champ
	minimap.controllable = not spectator
	minimap.rig = main.get("camera_rig")
	frame.add_child(minimap)


func _build_spectator(root: Control) -> void:
	var bp := UiStyle.panel(root, Control.PRESET_CENTER_TOP, Vector2(-300, 8), Vector2(600, 34))
	_banner = UiStyle.label(bp, "", 14, UiStyle.TEXT)
	UiStyle.fill(_banner)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	for team in [Combat.Team.SARADOMIN, Combat.Team.ZAMORAK]:
		var roster: Array = main.team_roster(team)
		for i in roster.size():
			var c: Champion = roster[i]
			var pos := Vector2(8, 190 + i * 52) if team == Combat.Team.SARADOMIN else Vector2(-228, 60 + i * 52)
			var preset := Control.PRESET_TOP_LEFT if team == Combat.Team.SARADOMIN else Control.PRESET_TOP_RIGHT
			var card := UiStyle.panel(root, preset, pos, Vector2(220, 48))
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			card.tooltip_text = "Lock onto %s (%s)" % [c.display_name, "12345"[i] if team == 0 else "67890"[i]]
			var style := UiStyle.box(UiStyle.BG, UiStyle.BORDER, 2, 4)
			card.add_theme_stylebox_override("panel", style)
			var key := UiStyle.label(card, "12345"[i] if team == 0 else "67890"[i], 11, UiStyle.MUTED)
			key.position = Vector2(6, 3)
			var title := UiStyle.label(card, c.display_name, 13, Unit.team_color(team).lightened(0.35))
			title.position = Vector2(20, 2)
			var lvl := UiStyle.label(card, "", 12, UiStyle.GOLD)
			UiStyle.place(lvl, Control.PRESET_TOP_RIGHT, Vector2(-70, 3), Vector2(62, 16))
			lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var hp := StatBar.create(card, UiStyle.HP, Vector2(204, 14), 10)
			hp.position = Vector2(8, 26)
			card.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					main.focus(c))
			_roster_cards.append({"champ": c, "style": style, "level": lvl, "hp": hp})

	ghost_cursor = GhostCursor.new()
	ghost_cursor.rig = main.get("camera_rig")
	ghost_cursor.markers_parent = main
	root.add_child(ghost_cursor)
	ghost_cursor.watch(champ)


func _build_shop(root: Control) -> void:
	_shop = UiStyle.panel(root, Control.PRESET_TOP_RIGHT, Vector2(-568, 56), Vector2(560, 560))
	_shop.visible = false
	_shop.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.position = Vector2(12, 10)
	col.size = Vector2(536, 540)
	_shop.add_child(col)
	UiStyle.label(col, "Grand Exchange   (P or Esc to close)", 20, UiStyle.TITLE)
	_shop_gold = UiStyle.label(col, "", 15, UiStyle.GOLD)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(536, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_shop_list = VBoxContainer.new()
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shop_list)


# --- Shop --------------------------------------------------------------------

func is_shop_open() -> bool:
	return _shop.visible


func toggle_shop() -> void:
	if spectator:
		return
	_shop.visible = not _shop.visible
	if _shop.visible:
		_rebuild_shop()


func _rebuild_shop() -> void:
	for c in _shop_list.get_children():
		c.queue_free()
	for id in GameData.item_order:
		var it := GameData.item(id)
		var missing := champ.missing_requirements(id)
		var line := "%s  —  %d GP" % [it.get("name", id), champ.item_cost(id)]
		if not missing.is_empty():
			line += "   [requires %s]" % ", ".join(missing)
		var b := UiStyle.button(_shop_list, line, 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = ItemSlot._tooltip(it)
		b.disabled = not champ.in_shop_range() or not champ.can_buy(id)
		b.pressed.connect(_on_buy.bind(id))


func _on_buy(id: String) -> void:
	if champ.in_shop_range() and champ.buy_item(id):
		_rebuild_shop()


# --- Messages ----------------------------------------------------------------

func announce(text: String, big: bool = false) -> void:
	var l := UiStyle.label(_feed, text, 15)
	_feed_entries.append({"label": l, "time": Combat.clock})
	while _feed_entries.size() > 7:
		_feed_entries.pop_front()["label"].queue_free()
	if big:
		_message.text = text
		_message_timer = 3.0


func show_game_over(victory: bool, winner_team: int = -1) -> void:
	if spectator:
		_game_over.text = "%s wins!" % Combat.TEAM_NAMES[clampi(winner_team, 0, 1)]
	else:
		_game_over.text = "Victory!" if victory else "Defeat — Oh dear, you are dead!"
	_game_over.visible = true


# --- Per-frame update --------------------------------------------------------

func _process(delta: float) -> void:
	if champ == null:
		return
	_message_timer -= delta
	if _message_timer <= 0.0:
		_message.text = ""
	for e in _feed_entries:
		var age := Combat.clock - float(e["time"])
		(e["label"] as Label).modulate.a = clampf(1.0 - (age - 10.0) / 3.0, 0.0, 1.0)

	var t := int(main.get("game_time"))
	var tk: Array = main.get("team_kills")
	var fps := "    %d fps" % Engine.get_frames_per_second() if Settings.show_fps else ""
	_score.text = "Saradomin %d – %d Zamorak    %02d:%02d    KDA %d/%d/%d    CS %d%s" % [
		tk[0], tk[1], t / 60, t % 60, champ.kills, champ.deaths, champ.assists, champ.creep_score, fps]

	_update_bottom_left()
	_update_bottom_center()
	var sel: Variant = main.get("selected")
	if is_instance_valid(sel):
		target_frame.show_unit(sel, champ.team, "Inspecting")
	elif spectator and is_instance_valid(champ.attack_target) and not champ.attack_target.is_dead:
		target_frame.show_unit(champ.attack_target, champ.team, "%s's target" % champ.display_name)
	else:
		target_frame.show_unit(null, champ.team)
	if spectator:
		_update_spectator()
	_update_skills_popups()

	if _shop.visible:
		_shop_gold.text = "Gold: %d GP%s" % [int(champ.gold), "" if champ.in_shop_range() else "   (return to base to buy)"]
		_shop_refresh -= delta
		if _shop_refresh <= 0.0:
			_shop_refresh = 1.0
			_rebuild_shop()


func _update_bottom_left() -> void:
	_portrait_initial.text = champ.display_name.substr(4, 1) if champ.display_name.begins_with("The ") else champ.display_name.substr(0, 1)
	_level_badge.text = str(champ.level)
	_name.text = champ.display_name
	var max_level := int(GameData.rule("max_level", 18))
	if champ.level >= max_level:
		_xp.set_values(1, 1, "MAX")
	else:
		_xp.set_values(champ.xp, champ.xp_to_next(), "XP")
	_stats["damage"].text = "Dmg %d" % int(champ.get_damage())
	_stats["magic"].text = "Magic %d" % int(champ.get_magic_power())
	_stats["attack_speed"].text = "Atk/s %.2f" % (1.0 / champ.get_attack_interval())
	_stats["range"].text = "Range %.1f" % champ.get_attack_range()
	_stats["move"].text = "Move %.1f" % champ.get_move_speed()
	_stats["melee_def"].text = "Melee def %d" % int(champ.get_defence(0))
	_stats["ranged_def"].text = "Range def %d" % int(champ.get_defence(1))
	_stats["magic_def"].text = "Magic def %d" % int(champ.get_defence(2))
	if champ.get_skill_power() > 0.0:
		_stats["armor_pen"].text = "Skill %d" % int(champ.get_skill_power())
	else:
		_stats["armor_pen"].text = "Pen %d%%" % int(champ.armor_pen * 100.0)
	_stats["combat"].text = "Combat %d" % champ.combat_level()
	for i in 6:
		var id := champ.inventory[i] if i < champ.inventory.size() else ""
		var key := champ.item_action_key(i)
		var left: float = champ.cooldowns.get(key, 0.0) if key != "" else 0.0
		var total := float(GameData.item(id).get("spec_active", {}).get("cooldown", 0.0)) if key != "" else 0.0
		_item_slots[i].set_item(id, left, total)
	for i in 4:
		_belt_slots[i].set_item(champ.consumables[i] if i < champ.consumables.size() else "")
	_gold.text = "%d GP" % int(champ.gold)


## Show a Skills popup while the mouse is over its portrait (or the popup itself,
## so its tiles' item tooltips can be read).
func _update_skills_popups() -> void:
	var mouse := _root.get_global_mouse_position()
	var over_own := force_skills_popups or _portrait_panel.get_global_rect().has_point(mouse) \
		or (_skills_popup.visible and _skills_popup.get_global_rect().has_point(mouse))
	if over_own and _skills_shown_for != champ:
		_skills_shown_for = champ
		_skills_popup.show_build(champ.def, champ)
		var sz := SkillsPanel.panel_size(_skills_popup.full)
		UiStyle.place(_skills_popup, Control.PRESET_BOTTOM_LEFT, Vector2(8, -206 - sz.y), sz)
	_skills_popup.visible = over_own
	var t := target_frame.target
	var over_target := target_frame.visible and t is Champion and (force_skills_popups \
		or target_frame.portrait_rect().has_point(mouse) \
		or (_target_skills_popup.visible and _target_skills_popup.get_global_rect().has_point(mouse)))
	if over_target and _target_skills_shown_for != t:
		_target_skills_shown_for = t
		_target_skills_popup.show_build((t as Champion).def, t as Champion)
		UiStyle.place(_target_skills_popup, Control.PRESET_TOP_LEFT, Vector2(8, 182), SkillsPanel.panel_size(_target_skills_popup.full))
	_target_skills_popup.visible = over_target


func _update_spectator() -> void:
	var rig: CameraRig = main.get("camera_rig")
	_banner.text = "SPECTATING  %s (%s)   ·   Y: camera %s   ·   1-5 / 6-0 or click: switch" % [
		champ.display_name, Combat.TEAM_NAMES[champ.team], "locked" if rig.locked else "free"]
	for card in _roster_cards:
		var c: Champion = card["champ"]
		(card["style"] as StyleBoxFlat).border_color = UiStyle.GOLD if c == champ else UiStyle.BORDER
		(card["style"] as StyleBoxFlat).set_border_width_all(3 if c == champ else 2)
		(card["level"] as Label).text = "dead %ds" % ceili(c.respawn_timer) if c.is_dead else "Lvl %d" % c.level
		(card["hp"] as StatBar).set_values(0.0 if c.is_dead else c.health, c.max_health)


func _update_bottom_center() -> void:
	var p: Dictionary = champ.passive
	var ptext := str(p.get("name", ""))
	if champ.passive_stacks() > 0:
		ptext += "\n×%d" % champ.passive_stacks()
	elif str(p.get("type", "")) == "skilling_level_up":
		ptext += "\nin %d" % champ.skilling_casts_until_level_up()
	elif not champ.forms.is_empty():
		ptext += "\n(%s)" % champ.form_name()
	_passive_label.text = ptext
	_passive.tooltip_text = "%s\n%s" % [p.get("name", ""), p.get("text", "")]

	for slot in Champion.SLOTS:
		(_ability_slots[slot] as AbilitySlot).refresh(champ, not spectator)

	var pray := champ.offensive_prayer()
	_offensive_name.text = str(pray.get("name", "None"))
	_offensive.tooltip_text = "%s: +%d%% damage for 6s (V). Set by your Prayer level (%d)." % [
		pray.get("name", "No offensive prayer"), int(float(pray.get("bonus", 0.0)) * 100.0), champ.skill("prayer")]
	var cd_total := float(GameData.rule("offensive_prayer", {}).get("cooldown", 60))
	var h := 60.0 * clampf(champ.offensive_prayer_cd / cd_total, 0.0, 1.0)
	_offensive_shade.position = Vector2(0, 60.0 - h)
	_offensive_shade.size = Vector2(60, h)
	for i in _overheads.size():
		_overheads[i].set_pressed_no_signal(champ.protect_style == i)

	_hp.set_values(champ.health, champ.max_health)
	_prayer.set_values(champ.prayer, champ.prayer_max, "Prayer %d / %d" % [int(champ.prayer), int(champ.prayer_max)])
	_spec.set_values(champ.spec, 100.0, "Special attack %d%%" % int(champ.spec))

	if champ.skill_points > 0 and not spectator:
		_hint.text = "%d skill point%s — click + or press Ctrl+Q/W/E%s" % [
			champ.skill_points, "s" if champ.skill_points > 1 else "", "/R" if champ.can_rank_up("r") else ""]
	else:
		_hint.text = ""
	if champ.is_dead:
		_channel.text = "Respawning in %d" % ceili(champ.respawn_timer)
	elif champ.is_recalling():
		_channel.text = "Teleporting home… %.1f" % champ.recall_timer
	else:
		_channel.text = ""
	var st: Array[String] = []
	for id in champ.statuses:
		var kind: String = champ.statuses[id]["kind"]
		var pretty := kind.replace("_", " ")
		if kind != "root_immune" and not st.has(pretty):
			st.append(pretty)
	_status.text = ", ".join(st)
