class_name GrandExchange
extends Panel
## The shop, laid out like the OSRS Grand Exchange: category tabs across the
## top, an item grid (icon, name, price in yellow, or red when you can't
## afford it; dimmed when your levels are too low), and the selected item's
## details on the right with a Buy button. Click an item to see it,
## double-click (or Buy) to buy. Prices, colours and the Buy button update
## in place, so hover tooltips stay up.

const SIZE := Vector2(840, 600)
const TILE := Vector2(120, 92)
const TABS: Array[String] = ["Weapons", "Armour", "Boots", "Consumables", "Skilling", "Materials"]

var champ: Champion
var tab := "Weapons"
var selected := ""

var _tabs: Dictionary = {}          # name -> Button
var _grid: GridContainer
var _scroll: ScrollContainer
var _tiles: Dictionary = {}         # item id -> {"button", "price", "icon", "name"}
var _coins: Label
var _d_icon: TextureRect
var _d_name: Label
var _d_price: Label
var _d_body: RichTextLabel
var _d_buy: Button
var _d_status: Label
var _refresh := 0.0


static func create(parent: Control, p_champ: Champion) -> GrandExchange:
	var ge := GrandExchange.new()
	ge.champ = p_champ
	parent.add_child(ge)
	return ge


## Which tab an item is listed under (an item's "shop" key overrides).
static func category(it: Dictionary) -> String:
	if it.has("shop"):
		return str(it["shop"])
	if it.get("consumable", false):
		return "Consumables"
	var tier := str(it.get("tier", ""))
	var item_name := str(it.get("name", "")).to_lower()
	if tier == "boots" or item_name.contains("boots") or item_name.contains("cape"):
		return "Boots"
	if tier == "tool":
		return "Skilling"
	if tier in ["armour", "offhand", "neck", "ring"] or item_name.contains("amulet") or item_name.contains("necklace") or item_name.ends_with("ring"):
		return "Armour"
	var stats: Dictionary = it.get("stats", {})
	if tier == "component" and (stats.has("defence") or stats.has("defence_all")) and not stats.has("attack_speed"):
		return "Armour"
	return "Weapons"


func _ready() -> void:
	add_theme_stylebox_override("panel", OsrsUi.panel_box())
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var title := OsrsUi.title(self, "Grand Exchange", 18)
	title.position.y = 4
	var close := OsrsUi.text(self, "P / Esc to close", 12, OsrsUi.MUTED, Rect2(SIZE.x - 140, 8, 128, 18))
	close.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in TABS.size():
		var t := Button.new()
		t.text = TABS[i]
		t.toggle_mode = true
		t.position = Vector2(12 + i * 107, 34)
		t.size = Vector2(103, 30)
		OsrsUi.style_button(t, 13)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := t.get_theme_stylebox(st) as StyleBox
			if sb != null:
				sb.content_margin_left = 2
				sb.content_margin_right = 2
		t.add_theme_stylebox_override("pressed", OsrsUi.slot_box(Color(0.42, 0.18, 0.12), false, true))
		t.add_theme_stylebox_override("hover_pressed", OsrsUi.slot_box(Color(0.46, 0.2, 0.13), true, true))
		t.pressed.connect(show_tab.bind(TABS[i]))
		add_child(t)
		_tabs[TABS[i]] = t
	var well := Panel.new()
	well.add_theme_stylebox_override("panel", OsrsUi.slot_box(Color(0.11, 0.095, 0.07)))
	well.position = Vector2(12, 70)
	well.size = Vector2(532, 486)
	add_child(well)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(6, 6)
	_scroll.size = Vector2(520, 474)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	well.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_scroll.add_child(_grid)
	_build_detail()
	_coins = OsrsUi.text(self, "", 15, OsrsUi.YELLOW, Rect2(14, 564, 520, 24))
	show_tab(tab)


func _build_detail() -> void:
	var d := Panel.new()
	d.add_theme_stylebox_override("panel", OsrsUi.slot_box(Color(0.13, 0.11, 0.085)))
	d.position = Vector2(554, 70)
	d.size = Vector2(274, 518)
	add_child(d)
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", OsrsUi.slot_box(Color(0.08, 0.065, 0.05)))
	frame.position = Vector2(12, 12)
	frame.size = Vector2(76, 76)
	d.add_child(frame)
	_d_icon = Icons.rect(frame, null, Vector2(68, 68))
	_d_icon.position = Vector2(4, 4)
	_d_icon.size = Vector2(68, 68)
	_d_name = OsrsUi.text(d, "", 16, OsrsUi.ORANGE, Rect2(98, 14, 168, 40))
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_name.clip_text = false
	_d_price = OsrsUi.text(d, "", 14, OsrsUi.YELLOW, Rect2(98, 62, 168, 22))
	_d_body = RichTextLabel.new()
	_d_body.bbcode_enabled = true
	_d_body.position = Vector2(12, 98)
	_d_body.size = Vector2(250, 312)
	_d_body.scroll_active = true
	_d_body.add_theme_font_size_override("normal_font_size", 13)
	_d_body.add_theme_color_override("default_color", Color.WHITE)
	d.add_child(_d_body)
	_d_status = OsrsUi.text(d, "", 13, OsrsUi.MUTED, Rect2(12, 414, 250, 36))
	_d_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_d_buy = Button.new()
	_d_buy.text = "Buy"
	_d_buy.position = Vector2(12, 456)
	_d_buy.size = Vector2(250, 50)
	OsrsUi.style_button(_d_buy, 22, OsrsUi.GREEN)
	_d_buy.pressed.connect(func() -> void: buy(selected))
	d.add_child(_d_buy)


func show_tab(name_: String) -> void:
	tab = name_
	for k in _tabs:
		(_tabs[k] as Button).set_pressed_no_signal(k == tab)
	for c in _grid.get_children():
		c.queue_free()
	_tiles.clear()
	var first := ""
	for id in GameData.item_order:
		if category(GameData.item(id)) != tab:
			continue
		_add_tile(id)
		if first == "":
			first = id
	_scroll.scroll_vertical = 0
	if selected == "" or not _tiles.has(selected):
		select(first)
	refresh()


func _add_tile(id: String) -> void:
	var it := GameData.item(id)
	var b := Button.new()
	b.custom_minimum_size = TILE
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.add_theme_stylebox_override("normal", OsrsUi.slot_box(OsrsUi.STONE_DARK))
	b.add_theme_stylebox_override("hover", OsrsUi.slot_box(OsrsUi.STONE_DARK.lightened(0.07), true))
	b.add_theme_stylebox_override("pressed", OsrsUi.slot_box(OsrsUi.STONE_DARK.lightened(0.1), false, true))
	b.add_theme_stylebox_override("hover_pressed", OsrsUi.slot_box(OsrsUi.STONE_DARK.lightened(0.12), true, true))
	b.tooltip_text = UiStyle.wrap(ItemSlot._tooltip(it, champ))
	var icon := Icons.rect(b, Icons.item(id), Vector2(40, 40))
	icon.position = Vector2((TILE.x - 40) * 0.5, 4)
	icon.size = Vector2(40, 40)
	var n := OsrsUi.text(b, str(it.get("name", id)), 11, OsrsUi.WHITE, Rect2(3, 44, TILE.x - 6, 28))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.clip_text = false
	n.size = Vector2(TILE.x - 6, 28)
	n.add_theme_constant_override("line_spacing", -4)
	var price := OsrsUi.text(b, "", 12, OsrsUi.YELLOW, Rect2(3, 72, TILE.x - 6, 16))
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.double_click:
			buy(id))
	b.pressed.connect(select.bind(id))
	_grid.add_child(b)
	_tiles[id] = {"button": b, "price": price, "icon": icon, "name": n}


func select(id: String) -> void:
	selected = id
	for k in _tiles:
		(_tiles[k]["button"] as Button).set_pressed_no_signal(k == id)
	if id == "":
		_d_name.text = ""
		_d_body.text = ""
		_d_icon.texture = null
		return
	var it := GameData.item(id)
	_d_icon.texture = Icons.item(id)
	_d_name.text = str(it.get("name", id))
	_d_body.text = details(it)
	refresh()


## The detail panel text: requirements (green met / red not), stats, effects.
func details(it: Dictionary) -> String:
	var lines: Array[String] = []
	var reqs: Dictionary = it.get("requirements", {})
	var id := str(it.get("id", ""))
	var made := champ != null and champ.can_make(id)
	if not reqs.is_empty():
		var parts: Array[String] = []
		for s in reqs:
			var ok := champ != null and (champ.skill(str(s)) >= int(reqs[s]) or (made and GameData.COMBAT_SKILLS.has(str(s))))
			parts.append("[color=%s]%d %s[/color]" % ["#4fd65a" if ok else "#ff5a4a", int(reqs[s]), str(s).capitalize()])
		lines.append("[color=#ff981f]Requires[/color] " + ", ".join(parts))
	var art: Dictionary = it.get("artisan", {})
	if not art.is_empty():
		lines.append("[color=#ff981f]Make your own[/color] [color=%s]%s[/color]: waives the combat requirements%s" % [
			"#4fd65a" if made else "#a8a39a", ItemSlot._levels(art), " (you can)" if made else ""])
	var tip := ItemSlot._tooltip(it, champ).split("\n")
	for i in range(1, tip.size()):
		if tip[i].begins_with("Requires") or tip[i].begins_with("Make your own"):
			continue
		if tip[i].begins_with("'perfect'"):
			# The 'perfect' version on its own line: green when yours are.
			var yours := champ != null and champ.is_perfect(id)
			lines.append("[color=%s]%s[/color]" % ["#4fd65a" if yours else "#a8a39a", tip[i]])
			continue
		lines.append(tip[i])
	if it.has("builds_from"):
		var names: Array[String] = []
		for b in it["builds_from"]:
			names.append(str(GameData.item(str(b)).get("name", b)))
		lines.append("[color=#a8a39a]Builds from %s (owning it lowers the price).[/color]" % ", ".join(names))
	var into: Array[String] = []
	for other_id in GameData.item_order:
		if id in GameData.item(other_id).get("builds_from", []):
			into.append(str(GameData.item(other_id).get("name", other_id)))
	if not into.is_empty():
		lines.append("[color=#a8a39a]Builds into %s.[/color]" % ", ".join(into))
	return "\n".join(lines)


func buy(id: String) -> void:
	if champ == null or id == "" or not champ.in_shop_range():
		return
	if champ.buy_item(id):
		refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		refresh()


## Updates prices, colours and the Buy button in place (nothing is rebuilt).
func refresh() -> void:
	if champ == null:
		return
	_coins.text = "Coins: %s gp%s" % [_commas(int(champ.gold)), "" if champ.in_shop_range() else "   ·   return to base to buy"]
	for id in _tiles:
		var t: Dictionary = _tiles[id]
		var cost := champ.item_cost(id)
		var usable := champ.meets_requirements(id)
		(t["price"] as Label).text = "%s gp" % _commas(cost)
		(t["price"] as Label).add_theme_color_override("font_color", OsrsUi.YELLOW if champ.gold >= cost else OsrsUi.RED)
		var dim := Color.WHITE if usable else Color(0.5, 0.5, 0.5, 0.75)
		(t["icon"] as TextureRect).modulate = dim
		(t["name"] as Label).modulate = dim
	if selected == "":
		_d_buy.disabled = true
		return
	var cost := champ.item_cost(selected)
	_d_price.text = "Price: %s gp" % _commas(cost)
	var status := ""
	if not champ.in_shop_range():
		status = "Return to your base to buy."
	elif not champ.meets_requirements(selected):
		status = "Your levels are too low: %s." % ", ".join(champ.missing_requirements(selected))
	elif champ.gold < cost:
		status = "You need %s more gp." % _commas(cost - int(champ.gold))
	elif not champ.can_buy(selected):
		status = "Your inventory is full."
	_d_status.text = status
	_d_buy.disabled = status != ""


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
