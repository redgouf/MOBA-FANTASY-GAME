class_name GrandExchange
extends Panel
## The shop, dressed like the OSRS Grand Exchange and laid out like League's
## shop. Left: a chatbox-style search bar ("What would you like to buy? *"),
## category tabs as OSRS item icons, and the item grid (icon, name, price in
## yellow, or red when you can't afford it; dimmed when your levels are too
## low). Right, in its own window: "Builds into" along the top, the selected
## item's recipe tree under it (the item at the top, its parts below; parts
## you own are green and come off the price), then its stats, effects and
## the Buy button (and a Sell button for an item you own). Click an item to
## see it, double-click, right-click (or Buy) to buy; click any item in the
## tree or the "Builds into" row to jump to it. Selling is League's: you get
## sell_back_pct of the price back (all of it in the first few seconds), from
## the Sell button or by right-clicking the item in your inventory.
##
## With the private model pack the frames are the real GE sprites (steel
## border, trade backing, item boxes, buttons, chatbox parchment; see
## tools/osrs_extract/osrsx/ui.py). Without it the same layout is drawn in
## code (OsrsUi), so the public build looks close.

const SIZE := Vector2(1000, 700)
## How big the window is drawn (the HUD scales it down so less of the game is covered).
const WINDOW_SCALE := 0.85
const TILE := Vector2(132, 92)
const TABS: Array[String] = ["Weapons", "Defence", "Consumables", "Boots", "Skilling", "Materials"]
const TAB_ICONS := {
	"Weapons": "weapons", "Defence": "defence", "Consumables": "consumables",
	"Boots": "boots", "Skilling": "skilling", "Materials": "materials",
}
const PROMPT := "What would you like to buy?"
const INTO_SLOTS := 7
const RIGHT := Rect2(612, 52, 372, 632)

# 9-slice margins of the GE sprites (the composed ones match ui.py's ge_slices).
const SLICES := {
	"ge_frame": [25, 30, 25, 30], "ge_box": [8, 8, 8, 8], "ge_bevel": [9, 9, 9, 9],
	"ge_bevel_hover": [9, 9, 9, 9], "ge_bevel_pressed": [9, 9, 9, 9],
	"ge_button": [6, 6, 6, 6], "ge_button_hover": [6, 6, 6, 6], "ge_text_box": [4, 0, 4, 0],
	"ge_item_box": [5, 5, 5, 5], "ge_item_box_glow": [5, 5, 5, 5], "chat_background": [6, 6, 6, 6],
}

var champ: Champion
var tab := "Weapons"
var selected := ""
var query := ""

var _tabs: Dictionary = {}          # name -> Button
var _tab_name: Label
var _search: LineEdit
var _search_text: HBoxContainer
var _grid: GridContainer
var _scroll: ScrollContainer
var _empty: Label
var _tiles: Dictionary = {}         # item id -> {"button", "price", "icon", "name"}
var _coins: Label
var _into: Array = []               # [{"button", "icon", "id"}]
var _tree: RecipeTree
var _tree_scroll: ScrollContainer
var _d_icon: TextureRect
var _d_name: Label
var _d_price: Label
var _d_body: RichTextLabel
var _d_buy: Button
var _d_sell: Button
var _d_status: RichTextLabel
var _refresh := 0.0
var _inv_key := ""


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
		return "Defence"
	var stats: Dictionary = it.get("stats", {})
	if tier == "component" and (stats.has("defence") or stats.has("defence_all")) and not stats.has("attack_speed"):
		return "Defence"
	return "Weapons"


## Does an item match a search? Every word has to appear in its name.
static func matches(it: Dictionary, q: String) -> bool:
	var item_name := str(it.get("name", "")).to_lower()
	for word in q.to_lower().split(" ", false):
		if not item_name.contains(word):
			return false
	return true


## The items that use this one in their recipe.
static func builds_into(id: String) -> Array[String]:
	var out: Array[String] = []
	for other in GameData.item_order:
		if id in GameData.item(other).get("builds_from", []):
			out.append(other)
	return out


# --- Skin ----------------------------------------------------------------------

## A StyleBox from one of the pack's GE sprites, or `fallback` without the pack.
static func skin(sprite_name: String, fallback: StyleBox, draw_center: bool = true, tiled: bool = false, content: float = 4.0) -> StyleBox:
	var t := OsrsSprites.get_sprite(sprite_name)
	if t == null:
		return fallback
	var sb := StyleBoxTexture.new()
	sb.texture = t
	var m: Array = SLICES.get(sprite_name, [0, 0, 0, 0])
	sb.texture_margin_left = m[0]
	sb.texture_margin_top = m[1]
	sb.texture_margin_right = m[2]
	sb.texture_margin_bottom = m[3]
	sb.draw_center = draw_center
	if tiled:
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.set_content_margin_all(content)
	return sb


static func _backing(light: bool = false) -> StyleBox:
	var face := Color(0.325, 0.29, 0.243) if light else Color(0.243, 0.208, 0.161)
	return skin("ge_background_light" if light else "ge_background", OsrsUi.panel_box(face, 1), true, true, 0.0)


## A GE window: trade backing with the riveted steel border over it.
static func window(parent: Control, rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	if OsrsSprites.get_sprite("ge_frame") != null:
		p.add_theme_stylebox_override("panel", _backing())
		var frame := Panel.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", skin("ge_frame", null, false, true))
		p.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		p.add_theme_stylebox_override("panel", OsrsUi.panel_box())
	return p


## A recessed box with the GE's thin line round it (like the "Buy offer" boxes).
static func inset(parent: Control, rect: Rect2, light: bool = false) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	if OsrsSprites.get_sprite("ge_box") != null:
		p.add_theme_stylebox_override("panel", _backing(light))
		var line := Panel.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_stylebox_override("panel", skin("ge_box", null, false))
		p.add_child(line)
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		p.add_theme_stylebox_override("panel", OsrsUi.slot_box(Color(0.13, 0.11, 0.085) if light else Color(0.11, 0.095, 0.07)))
	return p


## The GE's riveted divider strip, or a drawn line.
static func divider(parent: Control, y: float, x: float, w: float) -> void:
	var t := OsrsSprites.get_sprite("ge_divider_h")
	if t == null:
		var r := ColorRect.new()
		r.color = Color(0.08, 0.065, 0.05, 0.9)
		r.position = Vector2(x, y)
		r.size = Vector2(w, 2)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(r)
		return
	var tr := TextureRect.new()
	tr.texture = t
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.position = Vector2(x, y - t.get_height() * 0.5)
	tr.size = Vector2(w, t.get_height())
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)


## Item box styles: the GE item backdrop, glowing when picked.
static func style_item_box(b: Button) -> void:
	b.add_theme_stylebox_override("normal", skin("ge_item_box", OsrsUi.slot_box(OsrsUi.STONE_DARK)))
	b.add_theme_stylebox_override("disabled", skin("ge_item_box", OsrsUi.slot_box(OsrsUi.STONE_DARK)))
	b.add_theme_stylebox_override("hover", skin("ge_button_hover", OsrsUi.slot_box(OsrsUi.STONE_DARK.lightened(0.07), true)))
	b.add_theme_stylebox_override("pressed", skin("ge_item_box_glow", OsrsUi.slot_box(OsrsUi.STONE_DARK.lightened(0.1), false, true)))
	b.add_theme_stylebox_override("hover_pressed", skin("ge_item_box_glow", OsrsUi.slot_box(OsrsUi.STONE_DARK.lightened(0.12), true, true)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE


## The GE's bevelled button (its big confirm button).
static func style_bevel(b: Button, font_size: int, color: Color) -> void:
	OsrsUi.style_button(b, font_size, color)
	if OsrsSprites.get_sprite("ge_bevel") != null:
		for st in ["normal", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, skin("ge_bevel", null))
		b.add_theme_stylebox_override("hover", skin("ge_bevel_hover", null))
		b.add_theme_stylebox_override("pressed", skin("ge_bevel_pressed", null))


## OSRS pixel fonts only draw at whole multiples of 12 px; the shop's bigger
## text uses the scalable copy (1.5x at 18 px), kept sharp by nearest filtering.
static func big_font(c: Control, bold: bool = false, rich: bool = false) -> void:
	if not OsrsFont.active:
		return
	var f := OsrsFont.get_font_any_size("b12_full" if bold else "p12_full")
	if f == null:
		return
	c.add_theme_font_override("normal_font" if rich else "font", f)
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func _plain_tex(sprite_name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = OsrsSprites.get_sprite(sprite_name)
	return sb


# --- Build ---------------------------------------------------------------------

func _ready() -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST      # the pixel-art frames stay crisp
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var main := window(self, Rect2(Vector2.ZERO, SIZE))
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := OsrsUi.title(self, "Grand Exchange: Buy offer", 18)
	title.position.y = 10
	big_font(title, true)
	divider(self, 42, 8, SIZE.x - 16)
	_build_close()
	_build_search()
	_build_tabs()
	_build_grid()
	_build_detail()
	visibility_changed.connect(func() -> void:
		if not visible and _search != null:
			_search.release_focus())
	show_tab(tab)


func _build_close() -> void:
	var b := Button.new()
	b.position = Vector2(SIZE.x - 44, 9)
	b.size = Vector2(28, 28)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Close (P / Esc)"
	if OsrsSprites.get_sprite("ge_close") != null:
		for st in ["normal", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, _plain_tex("ge_close"))
		b.add_theme_stylebox_override("hover", _plain_tex("ge_close_hover"))
		b.add_theme_stylebox_override("pressed", _plain_tex("ge_close_hover"))
	else:
		b.text = "X"
		OsrsUi.style_button(b, 14)
	b.pressed.connect(func() -> void: visible = false)
	add_child(b)


func _build_search() -> void:
	# The chatbox prompt the GE opens: black text on parchment, a blue
	# asterisk where you type. Click it to search every tab by name.
	var bar := Panel.new()
	bar.position = Vector2(16, 52)
	bar.size = Vector2(584, 42)
	var parch := StyleBoxFlat.new()
	parch.bg_color = Color(0.70, 0.63, 0.5)
	parch.border_color = Color(0.29, 0.25, 0.19)
	parch.set_border_width_all(2)
	parch.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("panel", skin("chat_background", parch))
	add_child(bar)
	var glass := TextureRect.new()
	glass.texture = OsrsSprites.get_sprite("ge_search")
	glass.position = Vector2(8, 7)
	glass.size = Vector2(28, 28)
	glass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glass.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(glass)
	var x0 := 42.0 if glass.texture != null else 12.0
	# Prompt and typed text in black, the asterisk in blue, a hint after it.
	_search_text = HBoxContainer.new()
	_search_text.add_theme_constant_override("separation", 0)
	_search_text.position = Vector2(x0, 8)
	_search_text.size = Vector2(bar.size.x - x0 - 10, 26)
	_search_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_search_text)
	for part in [["typed", Color.BLACK], ["star", Color(0, 0, 1)], ["hint", Color(0.42, 0.34, 0.22)]]:
		var l := Label.new()
		l.name = part[0]
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", part[1])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		big_font(l, part[0] != "hint")      # the GE's chatbox prompt is bold
		_search_text.add_child(l)
	# The real input sits on top, invisible: the label draws the text.
	_search = LineEdit.new()
	_search.flat = true
	_search.caret_blink = false
	_search.max_length = 40
	_search.context_menu_enabled = false
	_search.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_search.add_theme_color_override("caret_color", Color(0, 0, 0, 0))
	_search.add_theme_color_override("selection_color", Color(0, 0, 0, 0))
	_search.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_search.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_search.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_search.tooltip_text = "Type an item's name to search every tab. Enter picks the first match."
	_search.text_changed.connect(set_query)
	_search.text_submitted.connect(func(_t: String) -> void:
		for id in _tiles:
			select(id)
			break
		_search.release_focus())
	_search.focus_entered.connect(_update_search_text)
	_search.focus_exited.connect(_update_search_text)
	bar.add_child(_search)
	_search.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_search_text()


func _update_search_text() -> void:
	(_search_text.get_node("typed") as Label).text = "%s %s" % [PROMPT, query]
	(_search_text.get_node("star") as Label).text = "*"
	var hint := query == "" and (_search == null or not _search.has_focus())
	(_search_text.get_node("hint") as Label).text = "   (click to search)" if hint else ""


func _build_tabs() -> void:
	for i in TABS.size():
		var t := Button.new()
		t.toggle_mode = true
		t.focus_mode = Control.FOCUS_NONE
		t.position = Vector2(16 + i * 66, 104)
		t.size = Vector2(60, 48)
		t.tooltip_text = TABS[i]
		t.add_theme_stylebox_override("normal", skin("ge_button", OsrsUi.button_box("normal")))
		t.add_theme_stylebox_override("hover", skin("ge_button_hover", OsrsUi.button_box("hover")))
		t.add_theme_stylebox_override("pressed", skin("ge_item_box_glow", OsrsUi.slot_box(Color(0.42, 0.18, 0.12), false, true)))
		t.add_theme_stylebox_override("hover_pressed", skin("ge_item_box_glow", OsrsUi.slot_box(Color(0.46, 0.2, 0.13), true, true)))
		t.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var icon := Icons.rect(t, Icons.shop_tab(TAB_ICONS[TABS[i]]), Vector2(38, 38))
		icon.position = Vector2(11, 5)
		icon.size = Vector2(38, 38)
		t.pressed.connect(show_tab.bind(TABS[i]))
		add_child(t)
		_tabs[TABS[i]] = t
	var x := 16.0 + TABS.size() * 66 + 6
	_tab_name = OsrsUi.text(self, "", 18, OsrsUi.ORANGE, Rect2(x, 116, 600 - x, 26))
	big_font(_tab_name, true)


func _build_grid() -> void:
	var well := inset(self, Rect2(16, 160, 584, 490))
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(8, 8)
	_scroll.size = Vector2(568, 474)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	well.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_scroll.add_child(_grid)
	_empty = OsrsUi.text(well, "No items match your search.", 15, OsrsUi.MUTED, Rect2(0, 40, 584, 24))
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.visible = false
	var coin := TextureRect.new()
	coin.texture = OsrsSprites.get_sprite("ge_coins")
	coin.position = Vector2(16, 658)
	coin.size = Vector2(24, 24)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(coin)
	_coins = OsrsUi.text(self, "", 18, OsrsUi.YELLOW, Rect2(46 if coin.texture != null else 18, 659, 554, 24))
	big_font(_coins)


func _build_detail() -> void:
	var d := window(self, RIGHT)
	var w := RIGHT.size.x
	# Builds into: the items this one is part of.
	big_font(OsrsUi.text(d, "Builds into", 18, OsrsUi.ORANGE, Rect2(16, 10, 200, 22)), true)
	var step := 48.0
	var x0 := (w - (INTO_SLOTS * step - 6)) * 0.5
	for i in INTO_SLOTS:
		var b := TipButton.new()
		b.position = Vector2(x0 + i * step, 36)
		b.size = Vector2(42, 38)
		style_item_box(b)
		var icon := Icons.rect(b, null, Vector2(30, 30))
		icon.position = Vector2(6, 4)
		icon.size = Vector2(30, 30)
		b.pressed.connect(_pick_into.bind(i))
		b.gui_input.connect(_right_click_buy.bind(func() -> String: return str(_into[i]["id"])))
		d.add_child(b)
		_into.append({"button": b, "icon": icon, "id": ""})
	divider(d, 86, 8, w - 16)
	# The recipe, the selected item at the top.
	big_font(OsrsUi.text(d, "Recipe", 18, OsrsUi.ORANGE, Rect2(16, 92, 200, 22)), true)
	_tree_scroll = ScrollContainer.new()
	_tree_scroll.position = Vector2(14, 116)
	_tree_scroll.size = Vector2(w - 28, 252)
	_tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	d.add_child(_tree_scroll)
	_tree = RecipeTree.new()
	_tree.ge = self
	_tree.view = _tree_scroll.size - Vector2(12, 0)
	_tree.custom_minimum_size = _tree.view
	_tree_scroll.add_child(_tree)
	divider(d, 376, 8, w - 16)
	# Stats and effects.
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", skin("ge_item_box", OsrsUi.slot_box(Color(0.08, 0.065, 0.05))))
	frame.position = Vector2(16, 388)
	frame.size = Vector2(52, 48)
	d.add_child(frame)
	_d_icon = Icons.rect(frame, null, Vector2(40, 40))
	_d_icon.position = Vector2(6, 4)
	_d_icon.size = Vector2(40, 40)
	_d_name = OsrsUi.text(d, "", 18, OsrsUi.ORANGE, Rect2(78, 388, w - 92, 24))
	big_font(_d_name, true)
	_d_price = OsrsUi.text(d, "", 14, OsrsUi.YELLOW, Rect2(78, 414, w - 92, 20))
	_d_body = RichTextLabel.new()
	_d_body.bbcode_enabled = true
	_d_body.position = Vector2(16, 444)
	_d_body.size = Vector2(w - 32, 106)
	_d_body.scroll_active = true
	_d_body.add_theme_font_size_override("normal_font_size", 13)
	_d_body.add_theme_color_override("default_color", Color.WHITE)
	d.add_child(_d_body)
	_d_status = RichTextLabel.new()
	_d_status.bbcode_enabled = true
	_d_status.scroll_active = false
	_d_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d_status.position = Vector2(16, 552)
	_d_status.size = Vector2(w - 32, 30)
	_d_status.add_theme_font_size_override("normal_font_size", 13)
	_d_status.add_theme_color_override("default_color", OsrsUi.MUTED)
	_d_status.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	d.add_child(_d_status)
	_d_buy = Button.new()
	_d_buy.text = "Buy"
	_d_buy.position = Vector2(16, 582)
	_d_buy.size = Vector2(w - 32, 38)
	style_bevel(_d_buy, 18, OsrsUi.GREEN)
	big_font(_d_buy, true)
	_d_buy.pressed.connect(func() -> void: buy(selected))
	d.add_child(_d_buy)
	_d_sell = Button.new()
	_d_sell.position = Vector2(16, 582)
	_d_sell.size = Vector2(w - 32, 38)
	style_bevel(_d_sell, 18, OsrsUi.ORANGE)
	big_font(_d_sell, true)
	_d_sell.visible = false
	_d_sell.pressed.connect(func() -> void: sell(selected))
	d.add_child(_d_sell)


# --- Browsing ------------------------------------------------------------------

func show_tab(name_: String) -> void:
	tab = name_
	if query != "":
		query = ""
		if _search != null:
			_search.text = ""
		_update_search_text()
	_fill_grid()


## Filters the grid by name across every tab ("" goes back to the tab).
func set_query(q: String) -> void:
	query = q.strip_edges()
	_update_search_text()
	_fill_grid()


func _fill_grid() -> void:
	for k in _tabs:
		(_tabs[k] as Button).set_pressed_no_signal(query == "" and k == tab)
	_tab_name.text = tab if query == "" else "Search results"
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_tiles.clear()
	var first := ""
	for id in GameData.item_order:
		var it := GameData.item(id)
		if query != "" and not matches(it, query):
			continue
		if query == "" and category(it) != tab:
			continue
		_add_tile(id)
		if first == "":
			first = id
	_empty.visible = _tiles.is_empty()
	_scroll.scroll_vertical = 0
	if query == "" and (selected == "" or not _tiles.has(selected)):
		select(first)
	else:
		_mark_selected()
	refresh()


func _add_tile(id: String) -> void:
	var it := GameData.item(id)
	var b := TipButton.new()
	b.custom_minimum_size = TILE
	b.toggle_mode = true
	style_item_box(b)
	b.tooltip_text = ItemSlot._tooltip(it, champ)
	var icon := Icons.rect(b, Icons.item(id), Vector2(40, 40))
	icon.position = Vector2((TILE.x - 40) * 0.5, 5)
	icon.size = Vector2(40, 40)
	var n := OsrsUi.text(b, str(it.get("name", id)), 11, OsrsUi.WHITE, Rect2(3, 45, TILE.x - 6, 28))
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
	b.gui_input.connect(_right_click_buy.bind(func() -> String: return id))
	b.pressed.connect(select.bind(id))
	_grid.add_child(b)
	_tiles[id] = {"button": b, "price": price, "icon": icon, "name": n}


func _mark_selected() -> void:
	for k in _tiles:
		(_tiles[k]["button"] as Button).set_pressed_no_signal(k == selected)


func _pick_into(i: int) -> void:
	var id := str(_into[i]["id"])
	if id != "":
		select(id)


func select(id: String) -> void:
	selected = id
	_mark_selected()
	var into: Array[String] = []
	if id != "":
		into = builds_into(id)
	for i in INTO_SLOTS:
		var slot: Dictionary = _into[i]
		var other: String = into[i] if i < into.size() else ""
		slot["id"] = other
		(slot["icon"] as TextureRect).texture = Icons.item(other) if other != "" else null
		var b := slot["button"] as Button
		b.disabled = other == ""
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if other != "" else Control.CURSOR_ARROW
		b.tooltip_text = "" if other == "" else "%s (%s gp)" % [GameData.item(other).get("name", other), _commas(_price_for(other))]
	if into.size() > INTO_SLOTS:
		(_into[INTO_SLOTS - 1]["button"] as Button).tooltip_text += "\n…and %d more" % (into.size() - INTO_SLOTS + 1)
	_inv_key = ""
	if id == "":
		_d_name.text = ""
		_d_body.text = ""
		_d_price.text = ""
		_d_icon.texture = null
		_tree.show_item("")
		return
	var it := GameData.item(id)
	_d_icon.texture = Icons.item(id)
	_d_name.text = str(it.get("name", id))
	_d_body.text = details(it)
	refresh()


func _price_for(id: String) -> int:
	return champ.item_cost(id) if champ != null else int(GameData.item(id).get("cost", 0))


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
			parts.append("[color=%s]%d[/color] {%s}" % ["#4fd65a" if ok else "#ff5a4a", int(reqs[s]), str(s)])
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
		lines.append("[color=#a8a39a]Parts of the recipe you own come off the price.[/color]")
	return SkillIcons.markup("\n".join(lines), false)


func buy(id: String) -> void:
	if champ == null or id == "" or not champ.in_shop_range():
		return
	if champ.buy_item(id):
		refresh()


## Right-click on an item anywhere in the shop buys it (like League).
func _right_click_buy(e: InputEvent, id_of: Callable) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		var id: String = id_of.call()
		if id != "":
			if id != selected:
				select(id)
			buy(id)


## Sells your copy of an item (the Sell button).
func sell(id: String) -> void:
	if champ == null or id == "" or not champ.in_shop_range():
		return
	if champ.sell_item(id):
		refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		refresh()


## Updates prices, colours and the Buy button in place. The recipe tree is
## rebuilt only when the selection or your inventory changes (what you own
## changes prices).
func refresh() -> void:
	if champ == null:
		return
	_coins.text = "%s gp%s" % [_commas(int(champ.gold)), "" if champ.in_shop_range() else "   ·   return to base to buy"]
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
		_d_sell.visible = false
		_d_status.text = ""
		return
	var key := "%s|%s" % [selected, ",".join(champ.inventory)]
	if key != _inv_key:
		_inv_key = key
		_tree.show_item(selected)
		_tree_scroll.scroll_vertical = 0
	_tree.update_colours()
	var cost := champ.item_cost(selected)
	var full := int(GameData.item(selected).get("cost", 0))
	_d_price.text = "Price: %s gp%s" % [_commas(cost), "" if cost == full else "  (full price %s gp)" % _commas(full)]
	_d_price.add_theme_color_override("font_color", OsrsUi.YELLOW if champ.gold >= cost else OsrsUi.RED)
	var status := ""
	if not champ.in_shop_range():
		status = "Return to your base to buy."
	elif not champ.meets_requirements(selected):
		var need: Array[String] = []
		for r in champ.missing_requirement_levels(selected):
			need.append("%d {%s}" % [int(r[1]), str(r[0])])
		status = "Your levels are too low: %s." % ", ".join(need)
	elif champ.gold < cost:
		status = "You need %s more gp." % _commas(cost - int(champ.gold))
	elif not champ.can_buy(selected):
		status = "Your inventory is full."
	var shown := "[center]%s[/center]" % SkillIcons.markup(status) if status != "" else ""
	if _d_status.text != shown:
		_d_status.text = shown
	_d_buy.disabled = status != ""
	_refresh_sell()


## The Sell button, shown beside Buy when you own the selected item.
func _refresh_sell() -> void:
	var w := RIGHT.size.x - 32.0
	var idx := champ.inventory.find(selected) if selected != "" else -1
	_d_sell.visible = idx >= 0
	if idx < 0:
		_d_buy.size.x = w
		return
	var half := floorf((w - 8.0) * 0.5)
	_d_buy.size.x = half
	_d_sell.position.x = 16.0 + half + 8.0
	_d_sell.size.x = w - half - 8.0
	var price := champ.sell_price(selected)
	_d_sell.text = "Sell: %s gp" % _commas(price)
	_d_sell.disabled = not champ.can_sell(idx)
	var pct := roundi(float(GameData.rule("sell_back_pct", 0.7)) * 100.0)
	_d_sell.tooltip_text = UiStyle.wrap("Sell for %d%% of its full price (%s gp). Bought in the last %d seconds, it sells back in full. You can also right-click an item in your inventory to sell it." % [
		pct, _commas(int(GameData.item(selected).get("cost", 0))), int(GameData.rule("sell_full_refund_sec", 10.0))])


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# --- Recipe tree ---------------------------------------------------------------

## League-style recipe: the item at the top, the items it builds from in the
## row below, theirs below that, joined by elbow lines. Parts you own (the
## ones the price already takes off) are outlined green and marked "Owned";
## what's under an owned part is greyed out. Click a part to select it.
## Deep recipes (dragon boots and up) scroll.
class RecipeTree extends Control:
	const ROW_MIN := 60.0
	const ROW_MAX := 74.0

	var ge: GrandExchange
	var view := Vector2(330, 252)
	var nodes: Array = []        # {"id", "parent", "owned", "covered", "pos", "button", "price"}
	var _row_h := 0.0
	var _box := Vector2.ZERO

	func show_item(id: String) -> void:
		for c in get_children():
			remove_child(c)
			c.queue_free()
		nodes.clear()
		custom_minimum_size = view
		if id == "":
			queue_redraw()
			return
		var depth := _depth(id)
		_row_h = clampf(view.y / depth, ROW_MIN, ROW_MAX)
		custom_minimum_size = Vector2(view.x, maxf(view.y, _row_h * depth))
		size = custom_minimum_size
		var icon_px := clampf(_row_h - 36.0, 28.0, 38.0)
		_box = Vector2(icon_px + 10, icon_px + 6)
		var leaves := _leaves(id)
		var slot := minf(view.x / leaves, 120.0)
		var x0 := (view.x - slot * leaves) * 0.5
		var owned: Array = []
		if ge.champ != null:
			owned = ge.champ.owned_parts(id)
		_place(id, 0, x0, slot, -1, owned, false)
		queue_redraw()

	func _depth(id: String) -> int:
		var best := 0
		for c in GameData.item(id).get("builds_from", []):
			best = maxi(best, _depth(str(c)))
		return best + 1

	func _leaves(id: String) -> int:
		var n := 0
		for c in GameData.item(id).get("builds_from", []):
			n += _leaves(str(c))
		return maxi(n, 1)

	## Lays out one node and its parts; returns the node's centre x.
	func _place(id: String, row: int, x: float, slot: float, parent: int, owned: Array, covered: bool) -> float:
		var idx := nodes.size()
		var is_owned := row > 0 and not covered and owned.has(id)
		if is_owned:
			owned.erase(id)        # each owned item counts once, as in owned_parts
		nodes.append({"id": id, "parent": parent, "owned": is_owned, "covered": covered})
		var parts: Array = GameData.item(id).get("builds_from", [])
		var cx := x + slot * 0.5
		if not parts.is_empty():
			var xs: Array[float] = []
			var cur := x
			for p in parts:
				xs.append(_place(str(p), row + 1, cur, slot, idx, owned, covered or is_owned))
				cur += slot * _leaves(str(p))
			cx = (xs[0] + xs[xs.size() - 1]) * 0.5
		var top := row * _row_h
		nodes[idx]["pos"] = Vector2(cx, top)
		var b := TipButton.new()
		b.position = Vector2(cx - _box.x * 0.5, top)
		b.size = _box
		b.toggle_mode = true
		GrandExchange.style_item_box(b)
		b.set_pressed_no_signal(row == 0)
		if is_owned:
			var g := StyleBoxFlat.new()
			g.bg_color = Color(0.1, 0.22, 0.08)
			g.border_color = Color(0.3, 0.9, 0.3)
			g.set_border_width_all(2)
			g.set_corner_radius_all(3)
			b.add_theme_stylebox_override("normal", g)
		b.tooltip_text = ItemSlot._tooltip(GameData.item(id), ge.champ)
		b.gui_input.connect(ge._right_click_buy.bind(func() -> String: return id))
		if row > 0:
			b.pressed.connect(ge.select.bind(id))
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var ipx := _box.y - 6
		var icon := Icons.rect(b, Icons.item(id), Vector2(ipx, ipx))
		icon.position = (_box - Vector2(ipx, ipx)) * 0.5
		icon.size = Vector2(ipx, ipx)
		if covered:
			icon.modulate = Color(0.55, 0.55, 0.55, 0.7)
		add_child(b)
		var price := OsrsUi.text(self, "", 12, OsrsUi.YELLOW, Rect2(cx - 50, top + _box.y + 1, 100, 16))
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nodes[idx]["button"] = b
		nodes[idx]["price"] = price
		return cx

	func update_colours() -> void:
		var c := ge.champ
		for n in nodes:
			var price := n["price"] as Label
			if n["owned"]:
				price.text = "Owned"
				price.add_theme_color_override("font_color", OsrsUi.GREEN)
				continue
			if n["covered"]:
				price.text = ""
				continue
			var cost := ge._price_for(str(n["id"]))
			price.text = GrandExchange._commas(cost)
			price.add_theme_color_override("font_color", OsrsUi.YELLOW if c == null or c.gold >= cost else OsrsUi.RED)

	func _draw() -> void:
		var line := Color(0.62, 0.55, 0.42)
		for n in nodes:
			if int(n["parent"]) < 0:
				continue
			var p: Dictionary = nodes[int(n["parent"])]
			var pp: Vector2 = p["pos"]
			var np: Vector2 = n["pos"]
			var from := Vector2(pp.x, pp.y + _box.y + 17)
			var mid := (from.y + np.y) * 0.5
			draw_line(from, Vector2(from.x, mid), line, 2.0)
			draw_line(Vector2(from.x, mid), Vector2(np.x, mid), line, 2.0)
			draw_line(Vector2(np.x, mid), np, line, 2.0)
