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
var scoreboard: MatchScoreboard
var force_scoreboard := false        # screenshots: keep the TAB scoreboard open
var ghost_cursor: GhostCursor

var target_frame: TargetFrame
var minimap: Minimap

var _score: Label
var _feed: VBoxContainer
var _feed_entries: Array[Dictionary] = []
var _message: Label
var _channel: Label
var _hint: Label
var _buffs: BuffBar
var _death: ColorRect
var _death_title: Label
var _death_by: Label
var _death_timer: Label

# bottom-left
var _portrait_style: StyleBoxFlat
var _portrait_initial: Label
var _portrait_view: FigureView     # the champion's head and shoulders, looking right
var _portrait_id := ""
var _stat_icons: Dictionary = {}
const STAT_NAMES := {"damage": "Damage", "magic": "Magic power", "attack_speed": "Time between attacks", "range": "Attack range",
	"move": "Move speed", "melee_def": "Melee defence", "ranged_def": "Ranged defence", "magic_def": "Magic defence",
	"armor_pen": "Armour penetration (Skill power for the Skiller)", "combat": "Combat level"}
## OSRS icons for the stats panel (private pack): skill icons and the combat tab's swords.
const STAT_ICONS := {"damage": "strength", "magic": "magic", "attack_speed": "attack", "range": "range", "move": "agility",
	"melee_def": "defence", "ranged_def": "defence", "magic_def": "defence", "armor_pen": "pierce", "combat": "combat"}
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
var _passive_icon: TextureRect
var _ability_slots: Dictionary = {}
var _offensive: Panel
var _offensive_icon: TextureRect
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

var _shop: GrandExchange
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
	scoreboard = MatchScoreboard.create(root, main)

	_message = UiStyle.label(root, "", 28, UiStyle.TITLE)
	UiStyle.place(_message, Control.PRESET_CENTER_TOP, Vector2(-450, 64 if not spectator else 52), Vector2(900, 40))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_build_death_screen(root)

	_game_over = UiStyle.label(root, "", 56, UiStyle.TITLE)
	UiStyle.place(_game_over, Control.PRESET_CENTER, Vector2(-500, -60), Vector2(1000, 80))
	_game_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.visible = false
	if spectator:
		_build_spectator(root)
	# OSRS Skills tab popups: hover your portrait, or the inspect panel's portrait.
	var sz := SkillsPanel.panel_size(true)
	_skills_popup = SkillsPanel.create(root)
	UiStyle.place(_skills_popup, Control.PRESET_BOTTOM_LEFT, Vector2(8, -166 - sz.y), sz)
	_skills_popup.visible = false
	_target_skills_popup = SkillsPanel.create(root)
	UiStyle.place(_target_skills_popup, Control.PRESET_TOP_LEFT, Vector2(8, 182), sz)
	_target_skills_popup.visible = false


# --- Layout ------------------------------------------------------------------

## While the champion you're playing (or watching) is dead: the world goes
## grey, with "Oh dear, you are dead!", who killed you and the respawn timer
## centred on the screen.
func _build_death_screen(root: Control) -> void:
	_death = ColorRect.new()
	UiStyle.fill(_death)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g) * 0.75, 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_death.material = mat
	_death.visible = false
	root.add_child(_death)
	root.move_child(_death, 0)        # under every HUD panel
	var col := VBoxContainer.new()
	UiStyle.place(col, Control.PRESET_CENTER, Vector2(-450, -120), Vector2(900, 160))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(col)
	_death_title = OsrsUi.text(col, "Oh dear, you are dead!", 44, OsrsUi.ORANGE)
	_death_by = OsrsUi.text(col, "", 22, OsrsUi.WHITE)
	_death_timer = OsrsUi.text(col, "", 18, OsrsUi.YELLOW)
	for l in [_death_title, _death_by, _death_timer]:
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _update_death_screen() -> void:
	var dead := champ != null and champ.is_dead
	_death.visible = dead
	if not dead:
		return
	var you: bool = main != null and main.get("player") == champ
	_death_title.text = "Oh dear, you are dead!" if you else "%s is dead" % champ.display_name
	_death_by.text = ("Killed by %s" % champ.last_killer_name) if champ.last_killer_name != "" else ""
	_death_timer.text = "Respawning in %d" % ceili(champ.respawn_timer)

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
	# The champion's portrait (rendered once per champion), looking to the right.
	_portrait_view = FigureView.create(portrait, Rect2(3, 3, 90, 90), true)
	_portrait_view.sway = false
	_portrait_view.facing_deg = 62.0
	_portrait_view.portrait_span = 0.22     # head and chest fill the frame
	_portrait_view.portrait_look = 0.8
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
	if OsrsFont.active:
		_level_badge.add_theme_font_override("font", OsrsFont.get_font("b12_full"))
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
	var osrs_ui := OsrsSprites.available()
	if osrs_ui:
		# The OSRS stone panel, and a skill icon in front of each stat.
		OsrsSprites.stone_panel(p)
		grid.add_theme_constant_override("v_separation", 6)
		grid.add_theme_constant_override("h_separation", 8)
		grid.position = Vector2(116, 12)
		p.size.x += 12
	for key in ["damage", "magic", "attack_speed", "range", "move", "melee_def", "ranged_def", "magic_def", "armor_pen", "combat"]:
		var holder: Control = grid
		if osrs_ui:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 3)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(row)
			var icon := TextureRect.new()
			icon.texture = OsrsSprites.get_sprite(STAT_ICONS.get(key, "stats"))
			icon.custom_minimum_size = Vector2(25, 25)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.mouse_filter = Control.MOUSE_FILTER_STOP
			icon.tooltip_text = STAT_NAMES.get(key, key)
			row.add_child(icon)
			_stat_icons[key] = icon
			holder = row
		var l := UiStyle.label(holder, "", 13)
		l.custom_minimum_size = Vector2(80 if not osrs_ui else 62, 0)
		if osrs_ui and OsrsFont.active:
			# Bigger stats, filling the panel: the OSRS font at 1.5x, crisp.
			l.add_theme_font_override("font", OsrsFont.get_font_any_size("p12_full"))
			l.add_theme_font_size_override("font_size", 24)
			l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		l.mouse_filter = Control.MOUSE_FILTER_PASS   # hover: the base value
		_stats[key] = l

	var items := GridContainer.new()
	items.columns = 3
	items.add_theme_constant_override("h_separation", 4)
	items.add_theme_constant_override("v_separation", 4)
	items.position = Vector2(296 if not osrs_ui else 310, 10)
	p.add_child(items)
	for i in 6:
		var slot := ItemSlot.create(items, 52, Controls.key_text("item_%d" % (i + 1)))
		slot.slot_index = i
		slot.secondary_pressed.connect(_sell_slot.bind(i))
		slot.item_dropped.connect(_move_item)
		_item_slots.append(slot)

	var belt := HBoxContainer.new()
	belt.add_theme_constant_override("separation", 4)
	belt.position = Vector2(296 if not osrs_ui else 310, 124)
	p.add_child(belt)
	for i in 4:
		_belt_slots.append(ItemSlot.create(belt, 38, Controls.key_text("consume_%d" % (i + 1)), true))
	Controls.bindings_changed.connect(_update_key_labels)

	_gold = UiStyle.label(p, "", 15, UiStyle.GOLD)
	_gold.position = Vector2(296 if not osrs_ui else 310, 166)
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
	_passive_icon = Icons.rect(_passive, null, Vector2.ZERO)
	_passive_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_passive_icon.offset_left = 8
	_passive_icon.offset_top = 12
	_passive_icon.offset_right = -8
	_passive_icon.offset_bottom = -4
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
	_offensive_icon = Icons.rect(_offensive, null, Vector2(40, 40))
	_offensive_icon.position = Vector2(10, 12)
	_offensive_icon.size = Vector2(40, 40)
	_offensive_name = UiStyle.label(_offensive, "", 9)
	UiStyle.fill(_offensive_name, 0, 36)
	_offensive_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offensive_name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_offensive_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offensive_shade = ColorRect.new()
	_offensive_shade.color = Color(0, 0, 0, 0.45)
	_offensive_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offensive.add_child(_offensive_shade)
	if not spectator:
		_offensive.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				champ.toggle_chosen_prayer())
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
	_channel = UiStyle.label(root, "", 24, UiStyle.TEXT)
	if OsrsFont.active:
		_channel.add_theme_font_override("font", OsrsFont.get_font("b12_full"))
	UiStyle.place(_channel, Control.PRESET_CENTER_BOTTOM, Vector2(-310, -256), Vector2(620, 26))
	_channel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Buffs and debuffs, just above the hotbar (icons with clock-wipe timers).
	var holder := Control.new()
	UiStyle.place(holder, Control.PRESET_CENTER_BOTTOM, Vector2(-310, -204), Vector2(620, 34))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	_buffs = BuffBar.create(holder, Rect2(0, 0, 620, 34))
	_buffs.unit = champ


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
	var bp := UiStyle.panel(root, Control.PRESET_CENTER_TOP, Vector2(-420, 8), Vector2(840, 34))
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
	# The Grand Exchange window, centred on the screen.
	var holder := Control.new()
	UiStyle.place(holder, Control.PRESET_CENTER, -GrandExchange.SIZE * 0.5 + Vector2(0, -40), GrandExchange.SIZE)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.pivot_offset = GrandExchange.SIZE * 0.5
	holder.scale = Vector2.ONE * GrandExchange.WINDOW_SCALE
	root.add_child(holder)
	_shop = GrandExchange.create(holder, champ)
	_shop.visible = false


# --- Shop --------------------------------------------------------------------

## Dragging an item onto another slot moves or swaps them.
func _move_item(from_slot: int, to_slot: int) -> void:
	if not spectator and champ != null:
		champ.move_item(from_slot, to_slot)


## The key shown on each item and potion slot follows your bindings.
func _update_key_labels() -> void:
	for i in _item_slots.size():
		_item_slots[i].set_key_text(Controls.key_text("item_%d" % (i + 1)))
	for i in _belt_slots.size():
		_belt_slots[i].set_key_text(Controls.key_text("consume_%d" % (i + 1)))


## Right-click on an inventory item sells it while the shop is open.
func _sell_slot(index: int) -> void:
	if spectator or not _shop.visible or champ == null or index >= champ.inventory.size():
		return
	if not champ.in_shop_range():
		announce("Return to your base to sell.")
	elif champ.sell_slot(index):
		_shop.refresh()


func is_shop_open() -> bool:
	return _shop.visible


func toggle_shop() -> void:
	if spectator:
		return
	_shop.visible = not _shop.visible
	if _shop.visible:
		_shop.champ = champ
		_shop.refresh()


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

	scoreboard.viewer_team = -1 if spectator else champ.team
	scoreboard.visible = force_scoreboard or Input.is_action_pressed("scoreboard")
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




## One stat in the bottom-left panel: green when buffs raise it above its
## base, red when debuffs lower it (for attack time, lower is better).
func _stat(key: String, fmt: String, value: float, base: float, base_fmt: String, lower_is_better: bool = false) -> void:
	var l: Label = _stats[key]
	if _stat_icons.has(key):
		# With the OSRS icons the stat's name is the icon (and its tooltip):
		# "Dmg 12" becomes [fist] 12; the three defences keep a short tag.
		fmt = fmt.replace("Dmg ", "").replace("Magic def ", "Mag ").replace("Melee def ", "Mel ").replace("Range def ", "Rng ") \
			.replace("Magic ", "").replace("Atk ", "").replace("Range ", "").replace("Move ", "").replace("Skill ", "")
	l.text = fmt % value
	var col := UiStyle.TEXT
	var diff := value - base
	if absf(diff) > maxf(absf(base) * 0.005, 0.01):
		var better := diff < 0.0 if lower_is_better else diff > 0.0
		col = Color(0.4, 1.0, 0.4) if better else Color(1.0, 0.45, 0.4)
	l.add_theme_color_override("font_color", col)
	var tip := ("Base " + base_fmt) % base if col != UiStyle.TEXT else ""
	if l.tooltip_text != tip:
		l.tooltip_text = tip


func _update_bottom_left() -> void:
	if _portrait_id != champ.champ_id:
		_portrait_id = champ.champ_id
		_portrait_view.show_champion(_portrait_id)
		_portrait_view.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# The tag only shows if no portrait can be drawn.
	_portrait_initial.text = "" if _portrait_view.figure != null else str(champ.def.get("tag", champ.display_name.substr(0, 1)))
	_level_badge.text = str(champ.level)
	_name.text = champ.display_name
	var max_level := int(GameData.rule("max_level", 18))
	if champ.level >= max_level:
		_xp.set_values(1, 1, "MAX")
	else:
		_xp.set_values(champ.xp, champ.xp_to_next(), "XP")
	# Live values with every buff and debuff: green when raised, red when lowered.
	_stat("damage", "Dmg %d", champ.effective_damage(false), champ.base_damage, "%d")
	_stat("magic", "Magic %d", champ.effective_damage(true), champ.base_magic_power, "%d")
	_stat("attack_speed", "Atk %.1fs", champ.get_attack_interval(), champ.base_attack_interval(), "%.1fs", true)
	_stat("range", "Range %.1f", champ.get_attack_range(), champ.base_attack_range, "%.1f")
	_stat("move", "Move %.1f", champ.get_move_speed(), champ.base_move_speed * float(GameData.rule("move_speed_scale", 1.0)), "%.1f")
	_stat("melee_def", "Melee def %d", champ.get_defence(0), champ.base_defence[0], "%d")
	_stat("ranged_def", "Range def %d", champ.get_defence(1), champ.base_defence[1], "%d")
	_stat("magic_def", "Magic def %d", champ.get_defence(2), champ.base_defence[2], "%d")
	if champ.get_skill_power() > 0.0:
		_stat("armor_pen", "Skill %d", champ.get_skill_power(), champ.skill_power, "%d")
		if _stat_icons.has("armor_pen"):
			(_stat_icons["armor_pen"] as TextureRect).texture = OsrsSprites.get_sprite("stats")
	else:
		_stats["armor_pen"].text = ("%d%%" if _stat_icons.has("armor_pen") else "Pen %d%%") % int(champ.armor_pen * 100.0)
		_stats["armor_pen"].add_theme_color_override("font_color", UiStyle.TEXT)
	_stats["combat"].text = ("%d" if _stat_icons.has("combat") else "Combat %d") % champ.combat_level()
	for i in 6:
		var id := champ.inventory[i] if i < champ.inventory.size() else ""
		var key := champ.item_action_key(i)
		var left: float = champ.cooldowns.get(key, 0.0) if key != "" else 0.0
		var total := float(GameData.item(id).get("spec_active", {}).get("cooldown", 0.0)) if key != "" else 0.0
		_item_slots[i].champ = champ
		_item_slots[i].set_item(id, left, total)
		_item_slots[i].sell_line = ""
		if id != "" and _shop.visible and champ.can_sell(i):
			_item_slots[i].sell_line = "Right-click to sell: %s gp" % GrandExchange._commas(champ.sell_price(id))
		if key != "" and Engine.get_process_frames() % 15 == i:
			# Spec weapons: add the live damage breakdown of their special attack.
			var spec_tip := AbilityInfo.tooltip(champ, key)
			_item_slots[i].tooltip_text = ItemSlot._tooltip(GameData.item(id), champ) + "\n\nSpecial attack:\n" + spec_tip
	for i in 4:
		_belt_slots[i].champ = champ
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
		UiStyle.place(_skills_popup, Control.PRESET_BOTTOM_LEFT, Vector2(8, -166 - sz.y), sz)
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
	var fog := FogOfWar.current
	_banner.text = "SPECTATING  %s (%s)   ·   Y: camera %s   ·   F: fog of war %s   ·   1-5 / 6-0 or click: switch" % [
		champ.display_name, Combat.TEAM_NAMES[champ.team], "locked" if rig.locked else "free",
		("on (%s's view)" % Combat.TEAM_NAMES[fog.team]) if fog != null and fog.enabled else "off"]
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
	var ptex := Icons.ability(champ.champ_id, "passive")
	if _passive_icon.texture != ptex:
		_passive_icon.texture = ptex
	# With an icon, only the live counter shows (stacks, casts to level up, form).
	var lines := ptext.split("\n")
	_passive_label.text = (lines[1] if lines.size() > 1 else "") if ptex != null else ptext
	_passive_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if ptex != null else VERTICAL_ALIGNMENT_CENTER
	_passive.tooltip_text = UiStyle.wrap("%s\n%s" % [p.get("name", ""), p.get("text", "")])

	for slot in Champion.SLOTS:
		(_ability_slots[slot] as AbilitySlot).refresh(champ, not spectator)

	# Your prayer (V): lit while on, with the time left at the current drain.
	var pray := champ.chosen_prayer_data()
	var on := champ.is_praying(champ.chosen_prayer)
	var left := champ.prayer_time_left()
	_offensive_name.text = ""      # name and time are in the tooltip
	_offensive_icon.texture = Icons.prayer(str(pray.get("name", "")))
	_offensive_icon.modulate = Color.WHITE if on else Color(0.6, 0.6, 0.6)
	_offensive_shade.position = Vector2.ZERO
	_offensive_shade.size = Vector2(60, 60) if not on else Vector2.ZERO
	var ob := _offensive.get_theme_stylebox("panel") as StyleBoxFlat
	ob.bg_color = Color(0.55, 0.52, 0.4) if on else UiStyle.BG_SLOT
	ob.border_color = Color(0.95, 0.9, 0.65) if on else UiStyle.PRAYER.darkened(0.2)
	if Engine.get_process_frames() % 15 == 0:
		_offensive.tooltip_text = UiStyle.wrap("%s\n%s (V or click). Picked at champion select." % [
			PrayerBook.tooltip(pray, champ.prayer_bonus()), ("On: %s left" % PrayerBook.clock_text(left)) if on else "Off"])
	for i in _overheads.size():
		_overheads[i].set_pressed_no_signal(champ.protect_style == i and champ.has_overheads)

	_hp.set_values(champ.health, champ.max_health)
	var pbar := "Prayer %d / %d" % [ceili(champ.prayer), int(champ.prayer_max)]
	if not champ.active_prayers.is_empty():
		pbar += "   ·   %d on, %s left" % [champ.active_prayers.size(), PrayerBook.clock_text(left)]
	if champ.altar_cooldown > 0.0:
		pbar += "   ·   altar in %ds" % ceili(champ.altar_cooldown)
	_prayer.set_values(champ.prayer, champ.prayer_max, pbar)
	_spec.set_values(champ.spec, 100.0, "Special attack %d%%" % int(champ.spec))

	if champ.skill_points > 0 and not spectator:
		_hint.text = "%d skill point%s — click + or press Ctrl+Q/W/E%s" % [
			champ.skill_points, "s" if champ.skill_points > 1 else "", "/R" if champ.can_rank_up("r") else ""]
	else:
		_hint.text = ""
	_update_death_screen()
	if champ.is_dead:
		_channel.text = ""
	elif champ.is_recalling():
		_channel.text = "Teleporting home... %.1f" % champ.recall_timer
	elif champ.is_praying_at_altar():
		_channel.text = "Praying at the altar... %.1f" % champ.pray_timer
	else:
		_channel.text = ""
	_buffs.unit = champ
