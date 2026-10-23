class_name BuffBar
extends Control
## A row of buff and debuff icons (above the hotbar, and on the inspect panel
## for allies), each with a radial timer and a hover explanation such as
## "Frozen: you can't move" or "Damage +15%". Enemy statuses are never shown.

const ICON := 32.0
const GAP := 4.0
## Not shown: freeze immunity, and potions' skill levels (flavour: the skills
## panel shows them; the potion's real effects have their own icons).
const HIDDEN: Array[String] = ["root_immune", "skill_boost"]

var unit: Unit
var _slots: Dictionary = {}       # status id -> BuffIcon
var _timer := 0.0


static func create(parent: Control, rect: Rect2) -> BuffBar:
	var b := BuffBar.new()
	b.position = rect.position
	b.size = rect.size
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


## One effect of a stance in words: "+30% attack speed", "-15% damage".
static func stance_part(kind: String, a: float) -> String:
	var sign := "+" if a >= 0.0 else "-"
	match kind:
		"attack_speed":
			return "%s%d%% attack speed" % [sign, roundi(absf(a) * 100.0)]
		"damage_mult":
			return "%s%d%% damage" % [sign, roundi(absf(a) * 100.0)]
		"armor_mult":
			return "%s%d%% defence" % [sign, roundi(absf(a) * 100.0)]
		"range_bonus":
			return "%s%sm attack range" % [sign, str(snappedf(absf(a), 0.01))]
		"haste":
			return "%s%d%% move speed" % [sign, roundi(absf(a) * 100.0)]
	return "%s %s" % [kind.replace("_", " "), str(snappedf(a, 0.01))]


## Icon, title and explanation for a status: {icon, title, text, debuff}.
static func describe(st: Dictionary) -> Dictionary:
	var kind := str(st.get("kind", ""))
	var a := float(st.get("amount", 0.0))
	var pct := "%d%%" % roundi(absf(a) * 100.0)
	var data: Dictionary = st.get("data", {})
	if str(data.get("stance", "")) != "":
		# An attack style (Rapid, Longrange): one icon for the whole stance.
		return {"icon": str(data.get("icon", "")), "title": str(data.get("title", "")), "text": str(data.get("text", "")), "debuff": false}
	match kind:
		"attack_damage_mult":
			return {"icon": "damage_up" if a >= 0.0 else "damage_down", "title": "Attack Damage %s%s" % ["+" if a >= 0.0 else "−", pct],
				"text": "Melee and ranged hits deal %s %s damage." % [pct, "more" if a >= 0.0 else "less"], "debuff": a < 0.0}
		"magic_damage_mult":
			return {"icon": "damage_up" if a >= 0.0 else "damage_down", "title": "Magic Damage %s%s" % ["+" if a >= 0.0 else "−", pct],
				"text": "Magic hits deal %s %s damage." % [pct, "more" if a >= 0.0 else "less"], "debuff": a < 0.0}
		"crit_chance":
			return {"icon": "crit", "title": "Crit chance +%s" % pct,
				"text": "%s of your hits crit for %d%% damage (a gold max-hit splat)." % [pct, roundi(float(GameData.rule("crit_mult", 1.5)) * 100.0)], "debuff": false}
		"crit_damage_mult":
			return {"icon": "crit", "title": "Crit Damage +%s" % pct, "text": "Your crits deal %s more damage." % pct, "debuff": false}
		"rock_cake":
			return {"icon": "rock_cake", "title": "Rock cake x%d" % roundi(a), "count": roundi(a),
				"text": "Rock cakes eaten in the last 5s. Only the first one of a run gives the speed boost.", "debuff": false}
		"damage_mult":
			return {"icon": "damage_up" if a >= 0.0 else "damage_down", "title": "Damage %s%s" % ["+" if a >= 0.0 else "−", pct],
				"text": "Deals %s %s damage." % [pct, "more" if a >= 0.0 else "less"], "debuff": a < 0.0}
		"armor_mult":
			return {"icon": "armor_up" if a >= 0.0 else "armor_down", "title": "Defence %s%s" % ["+" if a >= 0.0 else "−", pct],
				"text": "Defence %s by %s." % ["raised" if a >= 0.0 else "lowered", pct], "debuff": a < 0.0}
		"armor_flat":
			return {"icon": "armor_down" if a < 0.0 else "armor_up", "title": "Defence %s%d" % ["+" if a >= 0.0 else "−", roundi(absf(a))],
				"text": "Defence %s by %d (Warstrike)." % ["raised" if a >= 0.0 else "stripped", roundi(absf(a))], "debuff": a < 0.0}
		"attack_speed":
			return {"icon": "attack_speed", "title": "Attack speed +%s" % pct, "text": "Attacks %s faster." % pct, "debuff": false}
		"haste":
			return {"icon": "haste", "title": "Speed +%s" % pct, "text": "Moves %s faster." % pct, "debuff": false}
		"slow":
			return {"icon": "slow", "title": "Slowed %s" % pct, "text": "Moves %s slower." % pct, "debuff": true}
		"root":
			return {"icon": "root", "title": "Frozen", "text": "Can't move (can still attack and cast). A few seconds of freeze immunity follow.", "debuff": true}
		"stun":
			return {"icon": "stun", "title": "Stunned", "text": "Can't move, attack or cast.", "debuff": true}
		"tele_block":
			return {"icon": "tele_block", "title": "Teleblocked", "text": "Can't teleport home, recall or dash.", "debuff": true}
		"disable_prayer":
			return {"icon": "disable_prayer", "title": "Prayers disabled", "text": "Sever: prayers are off and can't be switched on.", "debuff": true}
		"melee_immune":
			return {"icon": "melee_immune", "title": "Untouchable", "text": "Melee attacks can't hit.", "debuff": false}
		"elysian":
			return {"icon": "elysian", "title": "Elysian ward", "text": "70%% chance to take %s less from each hit." % pct, "debuff": false}
		"vengeance":
			return {"icon": "vengeance", "title": "Vengeance", "text": "The next hit taken is %s reflected back." % pct, "debuff": false}
		"negate_hit":
			return {"icon": "negate_hit", "title": "Disruption", "text": "The next hit is blocked completely.", "debuff": false}
		"heal_over_time":
			return {"icon": "heal_over_time", "title": "Healing", "text": "Healing %s a second." % str(snappedf(a, 0.1)), "debuff": false}
		"poison":
			return {"icon": "poison", "title": "Poisoned", "text": "Takes %s damage a second." % str(snappedf(a, 0.1)), "debuff": true}
		"venom":
			return {"icon": "venom", "title": "Envenomed", "text": "Takes %s damage a second, rising each tick." % str(snappedf(a, 0.1)), "debuff": true}
		"burn":
			return {"icon": "burn", "title": "Burning", "text": "Takes %s damage a second." % str(snappedf(a, 0.1)), "debuff": true}
		"taunt":
			return {"icon": "taunt", "title": "Taunted", "text": "Forced to attack the taunter.", "debuff": true}
		"planted":
			return {"icon": "planted", "title": "Planted", "text": "Holding position.", "debuff": false}
		"damage_taken_mult":
			return {"icon": "guard" if a < 0.0 else "exposed", "title": "Damage taken %s%s" % ["−" if a < 0.0 else "+", pct],
				"text": "Takes %s %s damage." % [pct, "less" if a < 0.0 else "more"], "debuff": a > 0.0}
		"melee_damage_taken_mult":
			return {"icon": "melee_immune", "title": "Melee guard", "text": "Takes %s less melee damage." % pct, "debuff": false}
		"range_bonus":
			return {"icon": "range_bonus", "title": "Longrange", "text": "+%sm attack range." % str(snappedf(a, 0.1)), "debuff": false}
		"crest_of_cinders":
			return {"icon": "crest_of_cinders", "title": "Giant's ember", "text": "Attacks burn and slow (red buff).", "debuff": false}
		"spec_regen_mult":
			return {"icon": "spec_regen_mult", "title": "Abyssal surge", "text": "Special attack energy regenerates %s faster (blue buff)." % pct, "debuff": false}
		"skill_power_mult":
			return {"icon": "skill_power_mult", "title": "Skill power +%s" % pct, "text": "Skilling abilities hit %s harder." % pct, "debuff": false}
		"skill_boost":
			# (hidden from the bar; kept for the inspect panel and tests)
			var sk := str((st.get("data", {}) as Dictionary).get("skill", ""))
			var lv := roundi(a)
			var up := lv >= 0
			return {"icon": ("armor_up" if up else "armor_down") if sk == "defence" else ("damage_up" if up else "damage_down"),
				"title": "%s %s%d" % [sk.capitalize(), "+" if up else "−", absi(lv)],
				"text": "%s level %s by %d." % [sk.capitalize(), "boosted" if up else "lowered", absi(lv)], "debuff": not up}
		"antipoison":
			return {"icon": "antipoison", "title": "Antipoison", "text": "Immune to poison for now.", "debuff": false}
	return {"icon": "", "title": kind.replace("_", " ").capitalize(), "text": "", "debuff": false}


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	refresh()


func refresh() -> void:
	var live: Dictionary = {}
	if is_instance_valid(unit) and not unit.is_dead:
		for id in unit.statuses:
			var st: Dictionary = unit.statuses[id]
			if HIDDEN.has(str(st["kind"])):
				continue
			var d: Dictionary = st.get("data", {})
			if str(d.get("stance", "")) != "" and not bool(d.get("primary", false)):
				continue     # one icon per stance
			live[id] = st
	for id in _slots.keys():
		if not live.has(id):
			(_slots[id] as BuffIcon).queue_free()
			_slots.erase(id)
	var i := 0
	for id in live:
		var st: Dictionary = live[id]
		var icon: BuffIcon = _slots.get(id)
		if icon == null:
			icon = BuffIcon.new()
			icon.size = Vector2(ICON, ICON)
			add_child(icon)
			_slots[id] = icon
		var info := describe(st)
		icon.setup(info, st)
		icon.position = Vector2(i * (ICON + GAP), 0)
		i += 1


## One status: icon, buff/debuff border, a clock-wipe for the time left.
class BuffIcon extends Control:
	var tex: Texture2D
	var debuff := false
	var left := 0.0
	var total := 1.0
	var permanent := false
	var count := 0              # stacks shown in the corner ("x3")
	var _tip := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func setup(info: Dictionary, st: Dictionary) -> void:
		var key := str(info.get("icon", ""))
		tex = load("res://assets/icons/status/%s.png" % key) if key != "" and ResourceLoader.exists("res://assets/icons/status/%s.png" % key) else null
		debuff = bool(info.get("debuff", false))
		permanent = bool(st.get("permanent", false))
		count = int(info.get("count", 0))
		left = float(st.get("remaining", 0.0))
		total = maxf(float(st.get("total", left)), 0.01)
		var tip := "%s\n%s%s" % [info.get("title", ""), info.get("text", ""), "" if permanent else "\n%.1fs left" % left]
		if tip != _tip:
			_tip = tip
			tooltip_text = tip
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.08, 0.065, 0.05, 0.9))
		if tex != null:
			draw_texture_rect(tex, r.grow(-3), false)
		if not permanent:
			# Clock wipe: the used-up part is shaded, sweeping clockwise from 12.
			var used := clampf(1.0 - left / total, 0.0, 1.0)
			if used > 0.001:
				var c := size * 0.5
				var pts := PackedVector2Array([c])
				var steps := 24
				for k in steps + 1:
					var ang := -PI * 0.5 + TAU * used * float(k) / float(steps)
					pts.append(c + Vector2(cos(ang), sin(ang)) * size.x)
				draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
		draw_rect(r, Color(0.85, 0.2, 0.15) if debuff else Color(0.3, 0.85, 0.35), false, 2.0)
		if count > 0:
			var font := get_theme_default_font()
			var txt := "x%d" % count
			var pos := Vector2(size.x - 4.0 - font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, size.y - 4.0)
			draw_string(font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
			draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.9, 0.3))
