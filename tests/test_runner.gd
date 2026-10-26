extends Node
## Headless test suite. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 when every check passes, 1 otherwise.

const KNOWN_EFFECTS := ["damage", "heal", "self_cost", "status", "dash", "knockback",
	"spec_transfer", "summon", "toggle_form", "taunt", "pull", "prop", "max_stacks", "stance"]
const KNOWN_CASTS := ["self", "target_unit", "point"]

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	# Everything runs on the whitebox shapes first; test_osrs_models() then
	# checks the private OSRS pack when it's installed.
	OsrsModels.enabled = false
	# Most tests check League-sized numbers; test_hp_scale() checks the
	# shrunk, OSRS-sized ones the game actually plays with.
	GameData.load_all(1.0)
	test_data_integrity()
	test_combat_math()
	test_requirements()
	test_prayers()
	await test_game_tick()
	test_signature_specs()
	test_v07_feedback()
	test_skill_rolls()
	await test_champion_select()
	test_item_build_paths()
	test_skill_leveling()
	test_lol_minions_and_waves()
	await test_lol_turrets()
	test_lol_monsters()
	await test_skiller()
	await test_timber()
	test_ability_indicator()
	await test_v05_ui()
	await test_item_specs()
	await test_every_ability()
	await test_osrs_models()
	await test_combat_fx()
	await test_v09()
	await test_v010()
	await test_updates()
	await test_v013()
	await test_right_click_cancels_aim()
	await test_v015_ui()
	test_v016()
	test_v021()
	test_potions()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)


# --- Data --------------------------------------------------------------------

func test_data_integrity() -> void:
	check(GameData.champions.size() == 11, "11 champions load (got %d)" % GameData.champions.size())
	check(GameData.items.size() >= 40, "at least 40 items load (got %d)" % GameData.items.size())
	for id in GameData.champion_order:
		var c := GameData.champion(id)
		for s in Champion.SKILLS:
			check(c.get("skills", {}).has(s), "%s has %s level" % [id, s])
		for slot in Champion.SLOTS:
			var ab: Dictionary = c.get("abilities", {}).get(slot, {})
			check(not ab.is_empty(), "%s has ability %s" % [id, slot])
			var variants: Array = [ab]
			if ab.has("forms"):
				variants = ab["forms"].values()
			for v in variants:
				check(KNOWN_CASTS.has(str(v.get("cast", ""))), "%s %s has a known cast type" % [id, slot])
				for e in v.get("effects", []):
					check(KNOWN_EFFECTS.has(str(e.get("type", ""))), "%s %s effect '%s' is known" % [id, slot, e.get("type", "")])
	for id in GameData.item_order:
		var it := GameData.item(id)
		for s in it.get("requirements", {}):
			check(Champion.ALL_SKILLS.has(str(s)), "%s requirement '%s' is a real skill" % [id, s])
		for comp in it.get("builds_from", []):
			check(GameData.items.has(comp), "%s builds from existing item %s" % [id, comp])
		if it.has("spec_active"):
			var sa: Dictionary = it["spec_active"]
			check(float(sa.get("spec_cost", 0)) > 0.0, "%s spec active costs spec energy" % id)
			check(float(sa.get("cooldown", 0)) > 0.0, "%s spec active has a cooldown" % id)
	for cat in ["minions", "structures", "monsters", "summons"]:
		check(not GameData.units.get(cat, {}).is_empty(), "units.json has %s" % cat)
	for c in MapLayout.all_camps():
		for member in c["members"]:
			check(not GameData.unit_def("monsters", member[0]).is_empty(), "camp monster %s exists" % member[0])


# --- Combat ------------------------------------------------------------------

func test_combat_math() -> void:
	check(Combat.counters(Combat.Style.MELEE, Combat.Style.RANGED), "melee beats ranged")
	check(Combat.counters(Combat.Style.RANGED, Combat.Style.MAGIC), "ranged beats magic")
	check(Combat.counters(Combat.Style.MAGIC, Combat.Style.MELEE), "magic beats melee")
	check(not Combat.counters(Combat.Style.MELEE, Combat.Style.MAGIC), "melee does not beat magic")
	check(is_equal_approx(Combat.resist_multiplier(100.0), 0.5), "100 resist halves damage")
	check(is_equal_approx(Combat.ticks_to_seconds(4), 2.4), "4 ticks is 2.4 seconds (an OSRS whip)")
	var plain := Combat.mitigate(100.0, Combat.Style.MELEE, Combat.Style.MELEE, 0.0, 0.0, -1, false, false)
	check(is_equal_approx(plain, 100.0), "no resist, no prayer: full damage")
	var triangle := Combat.mitigate(100.0, Combat.Style.MELEE, Combat.Style.RANGED, 0.0, 0.0, -1, false, false)
	check(is_equal_approx(triangle, 115.0), "counter style deals +15%")
	var prayed := Combat.mitigate(100.0, Combat.Style.MELEE, Combat.Style.MELEE, 0.0, 0.0, Combat.Style.MELEE, false, false)
	check(is_equal_approx(prayed, 60.0), "protect from melee blocks 40%")
	var true_dmg := Combat.mitigate(100.0, Combat.Style.MELEE, Combat.Style.RANGED, 500.0, 0.0, Combat.Style.MELEE, false, true)
	check(is_equal_approx(true_dmg, 100.0), "true damage ignores everything")
	var maxed := {"attack": 99, "hitpoints": 99, "strength": 99, "defence": 99, "ranged": 99, "prayer": 99, "magic": 99}
	check(Combat.osrs_combat_level(maxed) == 126, "maxed skills are combat 126")
	check(Combat.osrs_combat_level({"hitpoints": 10}) == 3, "a fresh account is combat 3")
	check(Combat.osrs_combat_level(GameData.champion("pure")["skills"]) == 85, "the Pure build is combat 85")


func _make(id: String, team: int, pos: Vector3) -> Champion:
	var c := Champion.new()
	c.setup(id, team, pos, false)
	add_child(c)
	c.global_position = pos
	return c


func test_requirements() -> void:
	var pure := _make("pure", Combat.Team.SARADOMIN, Vector3(-82, 0, 82))
	var tank := _make("justiciar", Combat.Team.SARADOMIN, Vector3(-82, 0, 82))
	pure.gold = 99999
	tank.gold = 99999
	check(not pure.meets_requirements("bandos_chestplate"), "1 Defence Pure can't wear Bandos")
	check(pure.missing_requirements("bandos_chestplate") == ["65 Defence"], "Pure is told it needs 65 Defence")
	check(not pure.can_buy("dragon_boots"), "Pure can't buy dragon boots (60 Defence)")
	check(pure.can_buy("climbing_boots"), "Pure can buy climbing boots")
	check(pure.can_buy("abyssal_whip"), "Pure can buy a whip (70 Attack)")
	check(tank.can_buy("bandos_chestplate"), "Justiciar Tank can wear Bandos")
	check(tank.can_buy("elysian_spirit_shield"), "99 Defence, 99 Prayer tank can hold an Elysian")
	var lunar := _make("lunar", Combat.Team.SARADOMIN, Vector3(-82, 0, 82))
	lunar.skills["defence"] = 40   # (a lucky roll could reach the Elysian's 75)
	lunar.skills["smithing"] = 1   # (or 85 Smithing, to make it yourself)
	check(not lunar.meets_requirements("elysian_spirit_shield"), "40 Defence Lunar can't hold an Elysian")
	var zerker := _make("zerker", Combat.Team.SARADOMIN, Vector3(-82, 0, 82))
	check(zerker.meets_requirements("berserker_helm") and not zerker.meets_requirements("obsidian_platebody"),
		"45 Defence Zerker wears a berserker helm but not obsidian armour")
	for c in [pure, tank, lunar, zerker]:
		c.queue_free()


func test_prayers() -> void:
	var pure := _make("pure", Combat.Team.SARADOMIN, Vector3.ZERO)
	var tank := _make("justiciar", Combat.Team.SARADOMIN, Vector3.ZERO)
	var mage := _make("ancient_mage", Combat.Team.SARADOMIN, Vector3.ZERO)
	var pipe := _make("blowpiper", Combat.Team.SARADOMIN, Vector3.ZERO)
	var foe := _make("dharok", Combat.Team.ZAMORAK, Vector3(3, 0, 0))
	# The book: 32 OSRS prayers, each with an icon.
	check(PrayerBook.all().size() == 32, "the prayer book has all 32 prayers (got %d)" % PrayerBook.all().size())
	var no_icon: Array[String] = []
	for p in PrayerBook.all():
		if Icons.prayer(str(p["name"])) == null:
			no_icon.append(str(p["name"]))
	check(no_icon.is_empty(), "every prayer has an icon (missing: %s)" % ", ".join(no_icon))
	# OSRS drain: 0.6s x (60 + 2 x bonus) / drain effect.
	# (rules.prayer_drain.rate_mult: 3x the OSRS rate in this version)
	check(is_equal_approx(PrayerBook.seconds_per_point(24.0), 0.5), "Piety drains a point every 0.5s (OSRS 1.5s, 3x)")
	check(is_equal_approx(PrayerBook.seconds_per_point(1.0), 12.0), "Thick Skin drains a point every 12s (OSRS 36s, 3x)")
	check(is_equal_approx(PrayerBook.seconds_per_point(12.0, 10.0), 4.0 / 3.0), "+10 prayer bonus: drain 12 takes 4/3s a point")
	check(is_equal_approx(PrayerBook.seconds_per_point(36.0), 1.0 / 3.0), "drains add up (Piety + a protect prayer)")
	# Default picks by level and style.
	check(pure.chosen_prayer == "ultimate_strength", "52 Prayer Pure defaults to Ultimate Strength (got %s)" % pure.chosen_prayer)
	check(tank.chosen_prayer == "zeal", "99 Prayer tank defaults to Zeal (got %s)" % tank.chosen_prayer)
	check(mage.chosen_prayer == "augury", "77 Prayer mage defaults to Augury")
	check(pipe.chosen_prayer == "eagle_eye", "52 Prayer ranger defaults to Eagle Eye")
	# Picking: level-gated; overhead builds don't get protect prayers as their pick.
	check(not PrayerBook.can_pick(pure.def, "piety"), "a 52 Prayer Pure can't pick Piety")
	check(PrayerBook.can_pick(pure.def, "smite") and PrayerBook.can_pick(pure.def, "protect_from_melee"), "the Pure can pick Smite or Protect from Melee")
	check(not PrayerBook.can_pick(tank.def, "protect_from_melee"), "overhead builds don't pick protect prayers")
	pure.set_chosen_prayer("piety")
	check(pure.chosen_prayer == "ultimate_strength", "an illegal pick falls back to the default")
	# Overheads.
	pure.toggle_protect(Combat.Style.MELEE)
	check(pure.protect_style == -1, "Pure has no overheads")
	tank.toggle_protect(Combat.Style.MAGIC)
	check(tank.protect_style == Combat.Style.MAGIC and tank.get_protected_style() == Combat.Style.MAGIC, "Justiciar Tank can pray magic")
	tank.toggle_protect(Combat.Style.MELEE)
	check(tank.protect_style == Combat.Style.MELEE and tank.active_prayers.size() == 1, "one protection prayer at a time")
	check(tank.toggle_chosen_prayer() and tank.active_prayers.size() == 2, "overhead + own prayer together")
	var p0 := tank.prayer
	tank._tick_prayer(3.0)
	check(tank.prayer == p0, "prayers don't drain on their first tick")
	GameTick.current_tick += 2   # switched on between ticks: the next tick is free
	tank._tick_prayer(3.0)
	check(is_equal_approx(p0 - tank.prayer, 3.0 / PrayerBook.seconds_per_point(36.0, tank.prayer_bonus())), "both prayers drain together")
	tank.add_status("sever", "disable_prayer", 0.0, 5.0)
	tank._tick_prayer(0.1)
	check(tank.get_protected_style() == -1 and tank.active_prayers.is_empty(), "Sever switches prayers off")
	check(not tank.toggle_chosen_prayer(), "Sever blocks prayers")
	# A pure picking Protect from Melee can use it with V.
	pure.set_chosen_prayer("protect_from_melee")
	check(pure.toggle_chosen_prayer() and pure.get_protected_style() == Combat.Style.MELEE, "a picked protect prayer works")
	pure.deactivate_prayers()
	# Effects.
	pure.set_chosen_prayer("ultimate_strength")
	var info := DamageInfo.make(100.0, Combat.Style.MELEE, pure)
	pure.modify_outgoing(info, foe)
	var base := info.amount
	pure.toggle_chosen_prayer()
	info = DamageInfo.make(100.0, Combat.Style.MELEE, pure)
	pure.modify_outgoing(info, foe)
	check(is_equal_approx(info.amount, base * 1.09), "Ultimate Strength: +9% melee damage")
	info = DamageInfo.make(100.0, Combat.Style.MAGIC, pure)
	pure.modify_outgoing(info, foe)
	check(info.amount < base * 1.05, "Ultimate Strength doesn't boost magic")
	pure.prayer = 0.01
	GameTick.current_tick += 2
	pure._tick_prayer(1.0)
	check(pure.prayer == 0.0 and pure.active_prayers.is_empty(), "prayers switch off at 0 points")
	# Smite drains the target's prayer.
	pure.prayer = 99.0
	pure.set_chosen_prayer("smite")
	pure.toggle_chosen_prayer()
	foe.prayer = 99.0
	pure.on_damage_dealt(foe, foe.max_health * 0.2, DamageInfo.make(1.0, Combat.Style.MELEE, pure))
	check(absf(foe.prayer - 99.0 * 0.95) < 0.01, "Smite: a hit for 20%% health drains 5%% prayer (got %.2f)" % foe.prayer)
	# Redemption heals once under 10% and empties prayer.
	mage.set_chosen_prayer("redemption")
	mage.toggle_chosen_prayer()
	mage.health = mage.max_health * 0.05
	mage._on_damaged(mage, 10.0, null)
	check(mage.health > mage.max_health * 0.25 and mage.prayer == 0.0, "Redemption heals 25% and drains prayer")
	# Tele Block is halved by Protect from Magic.
	tank.remove_status("sever")
	tank.toggle_protect(Combat.Style.MAGIC)
	tank.add_status("tb", "tele_block", 0.0, 4.0, foe)
	check(is_equal_approx(float(tank.statuses["tb"]["remaining"]), 2.0), "Protect from Magic halves Tele Block")
	# Rapid Restore: enemy debuffs fade faster.
	pipe.set_chosen_prayer("hawk_eye")
	check(is_equal_approx(pipe.debuff_decay_mult(), 1.0), "no Rapid Restore: normal debuffs")
	pipe.chosen_prayer = "rapid_restore"
	pipe.toggle_chosen_prayer()
	check(pipe.debuff_decay_mult() > 1.2, "Rapid Restore speeds up debuff decay")
	for c in [pure, tank, mage, pipe, foe]:
		c.queue_free()


## Champion abilities built on a shop spec weapon must beat the item (option A)
## or do something different (option B), so buying the item never matches them.
# --- Game tick ---------------------------------------------------------------

## Logs its own game ticks (an NPC: not a Champion).
class TickProbeNpc extends Unit:
	var log: Array = []
	func _unit_tick(_dt: float) -> void:
		log.append("npc")


## Logs its own game ticks (a champion).
class TickProbeChampion extends Champion:
	var log: Array = []
	func _unit_tick(dt: float) -> void:
		log.append("champion")
		super(dt)


func _tick_dummy(team: int, pos: Vector3) -> Champion:
	var d := _make("justiciar", team, pos)
	d.spawn_point = Vector3(500, 0, 500)
	d.max_health = 1.0e6
	d.health = 1.0e6
	return d


func _ticks(n: int) -> void:
	for i in n:
		GameTick.run_tick()


func test_game_tick() -> void:
	# Drive the clock by hand so every check lands on an exact tick.
	GameTick.set_physics_process(false)
	GameTick.reset()
	check(is_equal_approx(GameTick.length(), 0.6), "a game tick is 0.6 s")
	check(GameTick.seconds_to_ticks(1.2) == 2 and GameTick.seconds_to_ticks(45.0) == 75 \
		and GameTick.seconds_to_ticks(5.0) == 9 and GameTick.seconds_to_ticks(4.0) == 7, "durations round up to whole ticks")
	check(GameTick.nearest_ticks(0.1) == 0 and GameTick.nearest_ticks(0.3) == 1 and GameTick.nearest_ticks(0.8) == 1,
		"short delays round to the nearest tick")
	var order: Array = []
	GameTick.queue_input(func() -> void: order.append("a"))
	GameTick.queue_input(func() -> void:
		order.append("b")
		GameTick.queue_input(func() -> void: order.append("late")))
	check(order.is_empty(), "input waits for the next tick")
	_ticks(1)
	check(order == ["a", "b"], "input runs in click order on the tick (got %s)" % str(order))
	_ticks(1)
	check(order == ["a", "b", "late"], "input given during a tick waits for the next one")
	var fired: Array = []
	var t0 := GameTick.current_tick
	GameTick.schedule(2, func() -> void: fired.append(GameTick.current_tick))
	GameTick.schedule_seconds(1.2, func() -> void: fired.append(GameTick.current_tick))
	_ticks(3)
	check(fired == [t0 + 2, t0 + 2], "scheduled actions run on their tick (got %s)" % str(fired))
	var seen: Array = []
	GameTick.queue_input(func() -> void: seen.append("input"))
	GameTick.schedule(1, func() -> void: seen.append("scheduled"))
	_ticks(1)
	check(seen == ["input", "scheduled"], "input runs before scheduled actions")

	# NPCs act before champions.
	var champ := TickProbeChampion.new()
	champ.setup("pure", Combat.Team.SARADOMIN, Vector3(300, 0, 300), false)
	add_child(champ)
	var npc := TickProbeNpc.new()
	add_child(npc)
	_ticks(1)
	check(npc.log == ["npc"] and champ.log == ["champion"], "NPCs and champions tick once each")
	var both: Array = []
	npc.log = both
	champ.log = both
	_ticks(1)
	check(both == ["npc", "champion"], "NPCs tick before champions (got %s)" % str(both))
	champ.queue_free()
	npc.queue_free()

	# Attacks land on ticks: a 4-tick weapon hits on ticks 1, 5, 9.
	var a := _tick_dummy(Combat.Team.SARADOMIN, Vector3(200, 0, 200))
	var b := _tick_dummy(Combat.Team.ZAMORAK, Vector3(201.2, 0, 200))
	a.attack_style = Combat.Style.MELEE
	a.base_attack_range = 1.5
	a.attack_ticks = 4.0
	a.bonus_attack_speed = 0.0
	var hits: Array = []
	b.damaged.connect(func(_u: Unit, _amt: float, _src: Unit) -> void: hits.append(GameTick.current_tick))
	var start := GameTick.current_tick
	a.command_attack(b)
	_ticks(9)
	var rel: Array = []
	for h in hits:
		rel.append(int(h) - start)
	check(rel == [1, 5, 9], "a 4-tick weapon hits on ticks 1, 5, 9 (got %s)" % str(rel))
	# +25% attack speed: the leftover carries over, 3.2 ticks on average.
	a.attack_target = null
	_ticks(6)
	hits.clear()
	a.bonus_attack_speed = 0.25
	start = GameTick.current_tick
	a.command_attack(b)
	_ticks(17)
	rel.clear()
	for h in hits:
		rel.append(int(h) - start)
	check(rel == [1, 5, 8, 11, 14, 17], "+25%% speed on 4 ticks: swings 3.2 ticks apart on average (got %s)" % str(rel))
	a.attack_target = null
	a.bonus_attack_speed = 0.0

	# Ranged: the hit lands projectile_hit_ticks() after the swing.
	_ticks(6)
	hits.clear()
	a.attack_style = Combat.Style.RANGED
	a.base_attack_range = 12.0
	a.global_position = b.global_position + Vector3(-11.0, 0, 0)
	var delay := a.projectile_hit_ticks(b)
	start = GameTick.current_tick
	a.command_attack(b)
	_ticks(delay + 1)
	check(delay >= 1 and hits.size() == 1 and int(hits[0]) - start == 1 + delay,
		"a ranged hit lands %d tick(s) after the swing (got %s)" % [delay, str(hits)])
	a.attack_target = null
	a.attack_style = Combat.Style.MELEE
	a.global_position = Vector3(200, 0, 200)

	# Spells are real time: they hit on cast, multi-hits follow hit_interval
	# seconds apart (not on ticks).
	_ticks(8)
	hits.clear()
	var claws := {"effects": [{"type": "damage", "base": 5.0, "hits": 4, "hit_interval": 0.15}]}
	AbilityRunner.execute(a, claws, b, b.global_position, 1)
	check(hits.size() == 1, "a spell hits the moment it's cast (got %d hits)" % hits.size())
	await get_tree().create_timer(0.7).timeout
	check(hits.size() == 4, "and its multi-hits follow in real time, no tick needed (got %d)" % hits.size())
	# Orders don't wait for a tick: moving and casting happen right away.
	a.command_move(a.global_position + Vector3(5, 0, 0))
	check(a._has_move_target, "a move order starts at once")
	a.command_stop()
	# Cooldowns and spell effects (statuses) count down in real time.
	a.cooldowns["q"] = 5.0
	a._frame_timers(4.9)
	check(a.cooldowns["q"] > 0.0, "a 5 s cooldown isn't ready after 4.9 s")
	a._frame_timers(0.1)
	check(a.cooldowns["q"] == 0.0, "and is ready at exactly 5 s")
	b.add_status("probe", "slow", 0.1, 5.0)
	b._tick_statuses(4.95)
	check(b.statuses.has("probe"), "a 5 s slow is still on after 4.95 s")
	b._tick_statuses(0.1)
	check(not b.statuses.has("probe"), "and gone at 5 s")
	# Eating and drinking still wait for the tick (PlayerController.order_on_tick).
	var pc := PlayerController.new()
	pc.champion = a
	var ate: Array = []
	pc.order_on_tick(func() -> void: ate.append(1))
	check(ate.is_empty(), "eating waits for the next tick")
	_ticks(1)
	check(ate.size() == 1, "and happens on it")
	pc.free()
	# Recall: 8 s = 14 ticks.
	a.spawn_point = Vector3(260, 0, 200)
	GameTick.queue_input(func() -> void: a.start_recall())
	start = GameTick.current_tick + 1
	var home_at := -1
	for k in 18:
		_ticks(1)
		if home_at < 0 and a.global_position.distance_to(a.spawn_point) < 0.1:
			home_at = GameTick.current_tick
	check(home_at - start == 14, "recall takes 14 ticks (got %d)" % (home_at - start))
	a.global_position = Vector3(200, 0, 200)
	a.spawn_point = Vector3(500, 0, 500)

	# Prayer: clicks work at once; the next tick is free, so flicking every
	# tick costs nothing.
	a.set_chosen_prayer("piety")
	a.prayer = 50.0
	a.toggle_chosen_prayer()
	check(a.is_praying(a.chosen_prayer), "a prayer comes on the moment it's clicked")
	_ticks(1)
	check(a.prayer == 50.0, "the first tick it's on is free")
	_ticks(1)
	check(a.prayer < 50.0, "and it drains from the tick after")
	a.toggle_chosen_prayer()
	var flick_from := a.prayer
	for k in 10:
		a.toggle_chosen_prayer()
		_ticks(1)
		a.toggle_chosen_prayer()
	check(a.prayer == flick_from, "flicking every tick costs no prayer")
	a.deactivate_prayers()
	b.has_overheads = true
	b.toggle_protect(Combat.Style.MAGIC)
	check(b.get_protected_style() == Combat.Style.MAGIC, "an overhead is up the moment it's clicked")
	a.queue_free()
	b.queue_free()
	GameTick.reset()
	GameTick.set_physics_process(true)


func test_signature_specs() -> void:
	for pair in [["pure", "r", "dragon_dagger"], ["zerker", "r", "dragon_claws"], ["slayer", "r", "dragon_warhammer"],
			["ancient_mage", "r", "volatile_nightmare_staff"], ["hybrid", "r", "armadyl_crossbow"]]:
		var ab: Dictionary = GameData.champion(pair[0])["abilities"][pair[1]]
		var it: Dictionary = GameData.item(pair[2])["spec_active"]
		var a: Dictionary = ab["effects"].filter(func(e: Dictionary) -> bool: return e.get("type") == "damage")[0]
		var b: Dictionary = it["effects"].filter(func(e: Dictionary) -> bool: return e.get("type") == "damage")[0]
		var ratio_a := 0.0
		var ratio_b := 0.0
		for k in a.get("ratio", {}):
			ratio_a += float(a["ratio"][k])
		for k in b.get("ratio", {}):
			ratio_b += float(b["ratio"][k])
		check(float(a.get("base", 0)) >= float(b.get("base", 0)) and ratio_a >= ratio_b and a.has("base_per_rank"),
			"%s %s hits at least as hard as the %s spec and scales with rank" % [pair[0], pair[1], pair[2]])
		check(float(ab.get("cooldown", 0)) < float(it.get("cooldown", 0)), "%s %s has a shorter cooldown than the item" % [pair[0], pair[1]])
	# Option B: retooled, so not the same move as the item.
	check(GameData.champion("dharok")["abilities"]["r"]["name"] != GameData.item("granite_maul")["spec_active"]["name"], "Dharok's R is no longer the granite maul spec")
	check(GameData.champion("justiciar")["abilities"]["r"]["name"] != GameData.item("bandos_godsword")["spec_active"]["name"], "Justiciar's R is no longer the BGS spec")
	# Slayer's smashes stack (OSRS DWH), the item's don't.
	var sl := _make("slayer", Combat.Team.SARADOMIN, Vector3(50, 0, 50))
	var dummy := _make("dharok", Combat.Team.ZAMORAK, Vector3(51.5, 0, 50))
	sl.ranks["r"] = 1
	for k in 2:
		AbilityRunner.execute(sl, sl.get_ability("r"), dummy, dummy.global_position, 1)
	check(dummy.status_sum("armor_mult") < -0.45, "two DWH smashes stack (%.2f)" % dummy.status_sum("armor_mult"))
	var zk := _make("zerker", Combat.Team.SARADOMIN, Vector3(50, 0, 52))
	AbilityRunner.execute(zk, zk.get_ability("r"), dummy, dummy.global_position, 1)
	check(zk.passive_stacks() == 5, "Zerker's claws fill the Berserker Necklace")
	for c in [sl, dummy, zk]:
		c.queue_free()


## v0.7 feedback: OSRS hitsplats, unit spacing, the cannon model, prayer altars.
func test_v07_feedback() -> void:
	# Hitsplats: kinds and tints.
	var hit := DamageInfo.make(50.0, Combat.Style.MELEE, null)
	check(Hitsplat.kind_for(0.0, hit) == "zero" and Hitsplat.kind_for(12.0, hit) == "damage", "blue 0, red damage")
	var crit := DamageInfo.make(50.0, Combat.Style.RANGED, null)
	crit.crit_mult = 1.5
	check(Hitsplat.kind_for(40.0, crit) == "max", "critical hits use the max-hit splat")
	var pois := DamageInfo.make(8.0, Combat.Style.MAGIC, null)
	pois.label = "poison"
	check(Hitsplat.kind_for(8.0, pois) == "poison", "poison has its own splat")
	for k in ["damage", "zero", "max", "poison", "venom", "burn"]:
		check(Hitsplat.texture(k, false) != null and Hitsplat.texture(k, true) != null, "%s splat (and tinted) loads" % k)
	var me := _make("pure", Combat.Team.SARADOMIN, Vector3(60, 0, -60))
	var other := _make("dharok", Combat.Team.ZAMORAK, Vector3(62, 0, -60))
	var third := _make("lunar", Combat.Team.ZAMORAK, Vector3(64, 0, -60))
	Hitsplat.viewer = me
	check(not Hitsplat.is_tinted(other, DamageInfo.make(1.0, Combat.Style.MELEE, me)), "your hits are bright")
	check(not Hitsplat.is_tinted(me, DamageInfo.make(1.0, Combat.Style.MELEE, other)), "hits on you are bright")
	check(Hitsplat.is_tinted(other, DamageInfo.make(1.0, Combat.Style.MAGIC, third)), "everyone else's hits are tinted")
	for n in 6:
		other._spawn_hitsplat(10.0, DamageInfo.make(10.0, Combat.Style.MELEE, me))
	var live := 0
	for h in other._splats:
		if h != null and is_instance_valid(h) and not (h as Node).is_queued_for_deletion():
			live += 1
	check(live == 4, "at most four splats on a unit at once (got %d)" % live)
	Hitsplat.viewer = null
	# Crowd: overlapping units are pushed apart; minions give way to champions.
	var mn := Minion.new()
	mn.init_minion("goblin", GameData.unit_def("minions", "goblin"), Combat.Team.SARADOMIN, "mid", MapLayout.lane_path("mid", 0), 1)
	add_child(mn)
	mn.global_position = me.global_position + Vector3(0.2, 0, 0)
	await get_tree().physics_frame
	Crowd.solve(get_tree(), 1.0 / 60.0)
	check(mn.crowd_push.length() > 0.0 and mn.crowd_push.length() > me.crowd_push.length() * 2.0, "a minion overlapping a champion is pushed (more than the champion)")
	check(mn.crowd_push.x > 0.0, "...away from the champion")
	var start := Unit.flat_distance(mn.global_position, me.global_position)
	for f in 40:
		Crowd.solve(get_tree(), 1.0 / 60.0)
		await get_tree().physics_frame
	check(Unit.flat_distance(mn.global_position, me.global_position) > start + 0.3, "they separate over a few frames")
	# Cannon: a built model, not a block.
	var cannon := CannonModel.build(Color.BLUE)
	check(cannon.head != null and cannon.barrel != null and cannon.find_children("*", "MeshInstance3D", true, false).size() > 12, "the multicannon is a built model")
	cannon.free()
	# Prayer altars: four, one beside each buff camp.
	check(MapLayout.all_prayer_altars().size() == 4, "four prayer altars (one per buff camp)")
	for c in [me, other, third, mn]:
		c.queue_free()


## v0.8: every build has all 24 skills; non-combat ones roll 20-75 each game (v0.10)
## (the Skiller keeps 99s), and skilling-gated items follow them.
func test_skill_rolls() -> void:
	GameData.roll_skills()
	var ok := true
	for id in GameData.champion_order:
		var sk := GameData.skills_for(id)
		if sk.size() != 24:
			ok = false
		for s in GameData.ALL_SKILLS:
			if GameData.COMBAT_SKILLS.has(s):
				continue
			var lvl := int(sk[s])
			if id == "skiller":
				if s != "slayer" and lvl != 99:
					ok = false
			elif lvl < 20 or lvl > (99 if s == GameData.lucky_skill(id) else (85 if id == "slayer" and s == "slayer" else 75)):
				ok = false
	check(ok, "every build has 24 skills; non-combat 20-75 (one lucky skill up to 99), the Skiller 99")
	var slayer_lvl := int(GameData.skills_for("slayer")["slayer"])
	check(slayer_lvl >= 60 and slayer_lvl <= 85, "the Slayer rolls 60-85 Slayer")
	var lucky_ok := GameData.lucky_skill("skiller") == ""
	for id in GameData.champion_order:
		if id != "skiller":
			var ls := GameData.lucky_skill(id)
			lucky_ok = lucky_ok and ls != "" and not GameData.COMBAT_SKILLS.has(ls) and not (id == "slayer" and ls == "slayer")
	check(lucky_ok, "every build but the Skiller gets one lucky non-combat skill")
	var highs := 0
	for k in 40:
		GameData.roll_skills()
		for id in GameData.champion_order:
			var ls := GameData.lucky_skill(id)
			if ls != "" and int(GameData.skills_for(id)[ls]) > 75:
				highs += 1
	check(highs > 0, "lucky skills sometimes roll above 75 (%d times in 400)" % highs)
	GameData.roll_skills()
	check(int(GameData.skills_for("dharok")["strength"]) == 99, "combat levels stay fixed")
	var first := GameData.skills_for("pure").duplicate()
	check(GameData.skills_for("pure") == first, "rolls hold for the whole game")
	GameData.roll_skills(true)
	var shown := GameData.skills_for("pure").duplicate()
	GameData.ensure_match_rolls()
	check(GameData.skills_for("pure") == shown, "the match keeps the levels champion select showed")
	# Over-75 skilling items: Skiller only.
	var over60: Array[String] = []
	for id in GameData.item_order:
		var reqs: Dictionary = GameData.item(id).get("requirements", {})
		for s in reqs:
			if not GameData.COMBAT_SKILLS.has(str(s)) and int(reqs[s]) > 75:
				over60.append(id)
				break
	var sk := _make("skiller", Combat.Team.SARADOMIN, Vector3(70, 0, -70))
	var pu := _make("pure", Combat.Team.SARADOMIN, Vector3(72, 0, -70))
	var skiller_all := true
	var others_none := true
	for s in pu.skills.keys():
		if not GameData.COMBAT_SKILLS.has(str(s)):
			pu.skills[s] = mini(int(pu.skills[s]), 75)   # (a lucky roll could pass 75)
	for id in over60:
		var reqs: Dictionary = GameData.item(id).get("requirements", {})
		var combat_req := false
		for s in reqs:
			combat_req = combat_req or GameData.COMBAT_SKILLS.has(str(s))
		if not combat_req and not sk.meets_requirements(id):
			skiller_all = false
		if pu.meets_requirements(id):
			others_none = false
	check(over60.size() >= 1 and skiller_all and others_none, "%d item(s) need a skill above 75: only the Skiller can use them" % over60.size())
	pu.gold = 5000
	check(pu.best_food() != "", "bots buy the best food for them (%s)" % pu.best_food())
	# New item effects.
	pu.gold = 99999
	pu.skills["slayer"] = 60
	pu.skills["firemaking"] = 60
	check(pu.buy_item("leaf_bladed_sword"), "Slayer 55 buys a leaf-bladed sword")
	var crab := Monster.new()
	crab.init_monster("rock_crab", GameData.unit_def("monsters", "rock_crab"), Vector3(74, 0, -70), "test", 1)
	add_child(crab)
	var to_monster := DamageInfo.make(100.0, Combat.Style.MELEE, pu)
	pu.modify_outgoing(to_monster, crab)
	var to_champ := DamageInfo.make(100.0, Combat.Style.MELEE, pu)
	pu.modify_outgoing(to_champ, sk)
	check(to_monster.amount > to_champ.amount * 1.1, "leaf-bladed sword hits monsters harder")
	check(pu.buy_item("bruma_torch"), "Firemaking 50 buys a bruma torch")
	pu.on_attack_landed(crab, 10.0)
	check(crab.has_status("burn"), "bruma torch attacks burn")
	pu.skills["herblore"] = 60
	pu.add_status("p", "poison", 5.0, 5.0, crab)
	check(pu.buy_item("superantipoison") and pu.use_consumable(pu.consumables.find("superantipoison")) and not pu.has_status("poison"), "superantipoison cures poison")
	pu.add_status("p2", "venom", 5.0, 5.0, crab)
	check(not pu.has_status("venom"), "...and blocks venom for a while")
	pu.skills["thieving"] = 60
	pu.skills["agility"] = 60
	check(pu.buy_item("rogue_outfit") and is_equal_approx(pu.gold_bonus(), 0.25), "rogue outfit: +25% last-hit gold")
	for n in [sk, pu, crab]:
		n.queue_free()


## v0.8 champion select: portrait cards, Equipment view, tabs, LOCK IN countdown.
func test_champion_select() -> void:
	var sel := ChampionSelect.new()
	add_child(sel)
	await get_tree().process_frame
	check(sel._cards.size() == GameData.champion_order.size(), "a portrait card for every build")
	sel.select_build("hybrid")
	check(sel.selected_id == "hybrid" and (sel._cards["hybrid"] as Button).button_pressed, "clicking a card selects it")
	check((sel._slots["weapon"]["icon"] as TextureRect).texture != null and (sel._slots["shield"]["icon"] as TextureRect).texture != null,
		"the Equipment view shows the build's gear")
	check(sel._figure.figure != null and sel._figure.figure.champion_id == "hybrid", "the figure shows the selected build")
	var pos := sel._skills.position
	sel.select_build("skiller")
	check(sel._skills.position == pos and sel._skills.size == SkillsPanel.panel_size(true), "the Skills tab stays put between builds")
	check(sel._skills._tiles.size() == 24, "every build shows all 24 skills")
	sel.show_tab("prayer")
	check(sel._prayers.visible and not sel._skills.visible, "Prayer tab")
	var started := []
	sel.champion_selected.connect(func(id: String, prayer_id: String) -> void: started.append([id, prayer_id]))
	sel.lock_in()
	sel.select_build("dharok")
	check(sel.locked and sel.selected_id == "skiller", "after LOCK IN the build can't change")
	sel._process(2.0)
	check(started.is_empty() and sel._lock.text.ends_with("3"), "countdown runs (%s)" % sel._lock.text)
	sel._process(3.1)
	check(started.size() == 1 and started[0][0] == "skiller" and started[0][1] == "thick_skin", "the match starts after 5 seconds")
	sel.queue_free()
	await get_tree().process_frame


## v0.9 feedback: OSRS-sized numbers, overkill, prayer, casting, ranks,
## tooltips, Grand Exchange, buffs, fog of war, Skiller gems, cannon carts.
func test_v09() -> void:
	# Smaller (OSRS-sized) health and damage: everything scaled by rules.hp_scale.
	GameData.load_all()
	var hs := float(GameData.rule("hp_scale", 1.0))
	check(hs < 0.5, "health and damage are scaled down (hp_scale %.2f)" % hs)
	check(is_equal_approx(float(GameData.champion("dharok")["base"]["max_health"]), 680.0 * hs), "champion health scales")
	check(is_equal_approx(float(GameData.unit_def("structures", "tower_outer")["max_health"]), 9000.0 * hs), "turret health scales")
	check(is_equal_approx(float(GameData.item("shark")["use"]["heal_over_time"]), 200.0 * hs), "food heals scale")
	var dk := _make("dharok", Combat.Team.SARADOMIN, Vector3(40, 0, -40))
	var foe := _make("pure", Combat.Team.ZAMORAK, Vector3(41.5, 0, -40))
	await get_tree().physics_frame
	check(dk.max_health < 200.0, "a level-1 champion has OSRS-sized health (%d)" % int(dk.max_health))
	# Overkill: the killing blow takes exactly the health left, and the bar shows 0.
	foe.health = 7.0
	var dealt := foe.take_damage(DamageInfo.make(500.0, Combat.Style.MELEE, dk))
	check(is_equal_approx(dealt, 7.0) and foe.is_dead and foe.health == 0.0, "overkill is capped at the health left (%.1f)" % dealt)
	check(is_equal_approx(foe._health_bar._ratio, 0.0), "the health bar empties on death")
	# Prayer: overhead icons and 3x drain.
	var tank := _make("justiciar", Combat.Team.SARADOMIN, Vector3(44, 0, -40))
	await get_tree().physics_frame
	tank.toggle_protect(Combat.Style.MELEE)
	check(tank.overhead_prayer() == "protect_from_melee" and Icons.overhead(tank.overhead_prayer()) != null, "Protect from Melee shows its overhead icon")
	tank.toggle_protect(Combat.Style.MELEE)
	check(tank.overhead_prayer() == "", "and hides it when switched off")
	# Ranks: every basic ability improves per rank.
	var flat: Array[String] = []
	for id in GameData.champion_order:
		for slot in ["q", "w", "e"]:
			var ab: Dictionary = GameData.champion(id)["abilities"][slot]
			if AbilityInfo.per_rank_text(ab, slot).replace("-6% cooldown", "").strip_edges(true, true).trim_suffix(",") == "":
				flat.append("%s %s" % [id, slot])
	check(flat.is_empty(), "every Q/W/E has a per-rank upgrade beyond cooldown (missing: %s)" % ", ".join(flat))
	var tb: Dictionary = GameData.champion("hybrid")["abilities"]["w"]
	check(is_equal_approx(float(AbilityRunner.ranked(tb, 3)["effects"][0]["duration"]), 5.0), "Tele Block lasts longer at rank 3 (4s + 2 x 0.5s)")
	# Coloured tooltips.
	var rich := AbilityInfo.tooltip_rich(dk, "q")
	check(rich.contains(AbilityInfo.C_MELEE) and rich.contains("[i]") and rich.contains(AbilityInfo.C_STATS), "ability tooltips are coloured (melee red, your stats light blue, italic cooldown)")
	# Normal cast is the default.
	check(Settings.cast_mode == Settings.CAST_NORMAL or Settings.CAST_MODE_NAMES.size() == 3, "normal cast (press, then left-click) is the default")
	# Grand Exchange tabs.
	var cats := {}
	for id in GameData.item_order:
		cats[GrandExchange.category(GameData.item(id))] = true
	check(cats.size() == 6 and cats.has("Consumables") and cats.has("Skilling") and cats.has("Materials"), "the Grand Exchange sorts items into 6 tabs (%s)" % str(cats.keys()))
	check(GrandExchange.category(GameData.item("shark")) == "Consumables" and GrandExchange.category(GameData.item("dragon_boots")) == "Boots"
		and GrandExchange.category(GameData.item("abyssal_whip")) == "Weapons" and GrandExchange.category(GameData.item("bandos_chestplate")) == "Defence", "items land in the right tab")
	check(GrandExchange.matches(GameData.item("dragon_boots"), "drag BOOTS") and not GrandExchange.matches(GameData.item("dragon_boots"), "rune"),
		"the shop search matches every word of an item's name")
	check("dragon_boots" in GrandExchange.builds_into("rune_boots") and GrandExchange.builds_into("primordial_boots").is_empty(), "the shop knows what an item builds into")
	for t in GrandExchange.TABS:
		check(Icons.shop_tab(GrandExchange.TAB_ICONS[t]) != null, "the %s tab has an icon" % t)
	var ge_holder := Control.new()
	add_child(ge_holder)
	var shopper := _make("slayer", Combat.Team.SARADOMIN, Vector3(150, 0, -150))
	shopper.inventory.append("leather_boots")
	var ge := GrandExchange.create(ge_holder, shopper)
	ge.set_query("rune boots")
	check(ge._tiles.size() == 1 and ge._tiles.has("rune_boots"), "searching 'rune boots' finds only rune boots")
	ge.select("dragon_boots")
	ge.refresh()
	var owned_nodes := ge._tree.nodes.filter(func(n: Dictionary) -> bool: return n["owned"])
	check(ge._tree.nodes[0]["id"] == "dragon_boots" and owned_nodes.size() == 1 and owned_nodes[0]["id"] == "leather_boots",
		"the recipe tree puts the item at the top and marks the leather boots you own")
	check(ge._into[0]["id"] == "primordial_boots", "dragon boots build into primordial boots")
	ge_holder.queue_free()
	shopper.queue_free()
	# Buff icons.
	check(BuffBar.describe({"kind": "root", "amount": 0.0})["debuff"] and not BuffBar.describe({"kind": "haste", "amount": 0.2})["debuff"], "roots are debuffs, haste a buff")
	check(BuffBar.describe({"kind": "tele_block"})["title"] == "Teleblocked", "teleblock has its own icon and name")
	# Fog of war.
	var fog := FogOfWar.new()
	add_child(fog)
	fog.set_team(Combat.Team.SARADOMIN)
	var far := _make("lunar", Combat.Team.ZAMORAK, Vector3(-60, 0, 60))
	await get_tree().physics_frame
	fog.update_vision()
	check(far.fog_hidden, "an enemy far from your team is hidden by the fog")
	far.global_position = dk.global_position + Vector3(6, 0, 0)
	fog.update_vision()
	check(not far.fog_hidden, "...and seen once an ally is near")
	fog.set_enabled(false)
	far.global_position = Vector3(-60, 0, 60)
	check(not far.fog_hidden, "spectators can switch the fog off")
	fog.queue_free()
	# Skiller gems, cannon carts.
	var gem := Projectile.launch(dk, tank, {"kind": "projectile", "shape": "gem"}, Callable())
	check(str(gem.fx.get("gem", "")) != "", "the Skiller throws gems (%s)" % gem.fx.get("gem", ""))
	gem.queue_free()
	var cart := CannonModel.build(Color.RED, true)
	check(is_equal_approx(cart.rotation.y, PI), "a cannon cart's barrel points the way it travels")
	cart.free()
	for n in [dk, foe, tank, far]:
		if is_instance_valid(n):
			n.queue_free()
	GameData.load_all(1.0)


func test_item_build_paths() -> void:
	var pure := _make("pure", Combat.Team.SARADOMIN, Vector3(-82, 0, 82))
	pure.gold = 5000
	check(pure.buy_item("rune_scimitar"), "buy rune scimitar")
	check(pure.item_cost("dragon_scimitar") == 600, "dragon scimitar costs 600 with a rune scimitar")
	check(pure.buy_item("dragon_scimitar"), "upgrade to dragon scimitar")
	check(pure.inventory == ["dragon_scimitar"], "component is consumed by the upgrade")
	var before := pure.base_damage
	check(pure.buy_item("abyssal_whip"), "upgrade to abyssal whip")
	check(pure.base_damage > before, "whip raises damage")
	check(pure.can_buy("shark") and not pure.is_perfect("shark"), "anyone can buy sharks; under 80 Cooking they aren't Perfect")
	check(pure.buy_item("shrimps") and pure.consumables == ["shrimps"], "food goes on the belt")
	pure.health = 100.0
	check(pure.use_consumable(0) and pure.consumables.is_empty(), "eating removes the shrimps")
	pure.queue_free()


func test_skill_leveling() -> void:
	var c := _make("pure", Combat.Team.SARADOMIN, Vector3(-82, 0, 82))
	check(c.skill_points == 1 and c.ranks == {"q": 0, "w": 0, "e": 0, "r": 0}, "start with nothing learned and 1 point")
	check(not c.try_cast("q", null, Vector3.ZERO), "an unlearned ability can't be cast")
	check(not c.can_rank_up("r"), "R is locked at level 1")
	check(c.rank_up("q") and c.ranks["q"] == 1 and c.skill_points == 0, "spend the first point on Q")
	check(not c.rank_up("w"), "no points left")
	c.add_xp(c.xp_to_next())
	check(c.level == 2 and c.skill_points == 1, "level 2 grants a point")
	check(not c.can_rank_up("q"), "Q rank 2 needs level 3")
	check(c.rank_up("w"), "level 2 can learn W")
	while c.level < 6:
		c.add_xp(c.xp_to_next())
	check(c.can_rank_up("r") and c.rank_up("r"), "R unlocks at level 6")
	check(not c.can_rank_up("r"), "R rank 2 waits for level 11")
	var cd1 := c.ability_cooldown("q", c.get_ability("q"))
	c.ranks["q"] = 5
	check(c.ability_cooldown("q", c.get_ability("q")) < cd1, "higher ranks shorten basic cooldowns")
	var bot := Champion.new()
	bot.setup("dharok", Combat.Team.ZAMORAK, Vector3(82, 0, -82), true)
	check(bot.ranks["q"] == 1 and bot.skill_points == 0, "bots spend their level 1 point")
	for i in 5:
		bot.add_xp(bot.xp_to_next())
	check(bot.level == 6 and bot.ranks["r"] == 1 and bot.skill_points == 0, "bots take R at level 6")
	var e := {"base": 100.0, "base_per_rank": 40.0}
	check(is_equal_approx(AbilityRunner.flat_amount(c, e, {"rank": 3}), 180.0), "rank 3 adds two rank steps")
	bot.free()
	c.queue_free()


# --- League of Legends values ------------------------------------------------

func test_lol_minions_and_waves() -> void:
	var melee := GameData.unit_def("minions", "goblin")
	var caster := GameData.unit_def("minions", "dark_wizard")
	var siege := GameData.unit_def("minions", "cannon_cart")
	check(is_equal_approx(Minion.scaled(melee["health"], 1), 465.0), "first-wave melee minion has 465 health")
	check(is_equal_approx(Minion.scaled(melee["health"], 60), 1550.0), "melee minion health caps at 1550")
	check(is_equal_approx(Minion.scaled(melee["damage"], 1), 11.0), "first-wave melee minion deals 11")
	check(is_equal_approx(Minion.scaled(caster["health"], 1), 284.0), "first-wave caster minion has 284 health")
	check(is_equal_approx(Minion.scaled(caster["damage"], 1), 21.0), "first-wave caster minion deals 21")
	check(is_equal_approx(Minion.scaled(siege["health"], 1), 835.0), "first siege minion has 835 health")
	check(is_equal_approx(Minion.scaled(siege["damage"], 1), 37.5), "first siege minion deals 37.5")
	check(is_equal_approx(Minion.scaled(siege["damage"], 20), 36.0 + 1.5 * 15 + 4.0 * 5), "siege damage grows +4 after upgrade 15")
	check(is_equal_approx(Minion.scaled(siege["damage"], 99), 126.0), "siege damage caps at 126")
	var m := Minion.new()
	m.init_minion("goblin", melee, Combat.Team.SARADOMIN, "mid", MapLayout.lane_path("mid", 0), 1)
	check(is_equal_approx(m.get_attack_interval(), 2.4) and is_equal_approx(m.basic_hit_scale, 0.7 * 2.4 * 1.25), "melee minions swing every 4 ticks, harder per hit (70% of the LoL DPS)")
	check(is_equal_approx(m.get_attack_range(), 110.0 / 75.0), "melee minion range is 110 LoL units")
	m.free()
	check(WaveSpawner.upgrades_at(29.0) == 0 and WaveSpawner.upgrades_at(30.0) == 1, "first upgrade at 0:30")
	check(WaveSpawner.upgrades_at(119.0) == 1 and WaveSpawner.upgrades_at(120.0) == 2, "then one every 90 s")
	check(WaveSpawner.wave_interval_at(60.0) == 30.0 and WaveSpawner.wave_interval_at(900.0) == 25.0 \
		and WaveSpawner.wave_interval_at(1900.0) == 20.0, "waves every 30 / 25 / 20 s")
	var ws := WaveSpawner.new()
	var normal := ws.wave_composition(60.0, 0, "mid", false)
	check(normal.count("goblin") == 3 and normal.count("dark_wizard") == 3 and normal.size() == 6, "normal wave: 3 melee + 3 casters")
	var late := ws.wave_composition(900.0, 0, "mid", true)
	check(late.count("goblin") == 2 and late.has("cannon_cart"), "after 14:00 a siege wave has one fewer melee")
	check(ws.wave_composition(1900.0, 0, "mid", false).count("dark_wizard") == 2, "2 casters per wave after 30:00")
	ws.altar_down = func(team: int, lane: String) -> bool: return team == 1 and lane == "top"
	var top := ws.wave_composition(600.0, 0, "top", true)
	check(top.has("knight") and not top.has("cannon_cart"), "a Knight replaces the siege minion while that altar is down")
	check(not ws.wave_composition(600.0, 0, "mid", false).has("knight"), "other lanes get no Knight")
	ws.altar_down = func(team: int, _lane: String) -> bool: return team == 1
	check(ws.wave_composition(600.0, 0, "mid", false).count("knight") == 2, "two Knights per lane with all altars down")
	ws.altar_down = Callable()
	var siege_waves: Array[int] = []
	for w in 9:
		ws._queue_wave(30.0 + 30.0 * w)
		if ws._waves_since_siege == 0:
			siege_waves.append(ws.wave)
	check(siege_waves == [3, 6, 9], "siege minion on every 3rd wave before 14:00 (got %s)" % str(siege_waves))
	ws.free()


func test_lol_turrets() -> void:
	Combat.clock = 0.0
	var tower := Structure.new()
	tower.init_structure("tower", GameData.unit_def("structures", "tower_outer"), Combat.Team.ZAMORAK, "Test tower", "tower_outer")
	add_child(tower)
	check(is_equal_approx(tower.max_health, 9000.0) and is_equal_approx(tower.get_defence(0), 60.0), "outer turret: 9000 health, 60 armor")
	check(is_equal_approx(tower.get_attack_interval(), 2.4), "turrets fire every 4 ticks")
	check(is_equal_approx(tower.get_attack_range(), 10.0), "turret range is 750 LoL units (10 m)")
	check(is_equal_approx(tower.get_damage(), 182.0), "outer turret starts at 182 damage")
	Combat.clock = 7 * 60.0
	check(is_equal_approx(tower.get_damage(), 266.0), "outer turret damage grows 12 per minute")
	Combat.clock = 30 * 60.0
	check(is_equal_approx(tower.get_damage(), 350.0), "outer turret damage caps at 350")
	Combat.clock = 0.0
	var melee := Minion.new()
	melee.init_minion("goblin", GameData.unit_def("minions", "goblin"), 0, "mid", MapLayout.lane_path("mid", 0), 1)
	add_child(melee)
	var caster := Minion.new()
	caster.init_minion("dark_wizard", GameData.unit_def("minions", "dark_wizard"), 0, "mid", MapLayout.lane_path("mid", 0), 1)
	add_child(caster)
	check(is_equal_approx(tower.build_attack_damage(melee).amount, 0.45 * 465.0), "turret shots deal 45% of a melee minion's max health")
	var shots := 0
	while not melee.is_dead and shots < 10:
		melee.take_damage(tower.build_attack_damage(melee))
		shots += 1
	check(shots == 3, "a turret kills a melee minion in 3 shots (took %d)" % shots)
	shots = 0
	while not caster.is_dead and shots < 10:
		caster.take_damage(tower.build_attack_damage(caster))
		shots += 1
	check(shots == 2, "a turret kills a caster minion in 2 shots (took %d)" % shots)
	var champ := _make("dharok", Combat.Team.SARADOMIN, Vector3(0, 0, 0))
	var amounts: Array[float] = []
	for i in 5:
		amounts.append(tower.build_attack_damage(champ).amount)
	check(is_equal_approx(amounts[1] / amounts[0], 1.5) and is_equal_approx(amounts[3] / amounts[0], 2.5) \
		and is_equal_approx(amounts[4] / amounts[0], 2.5), "Warming Up: +50% per shot on champions, up to +150%")
	Combat.clock = 10.0
	check(is_equal_approx(tower.build_attack_damage(champ).amount, tower.get_damage() * tower.basic_hit_scale), "Warming Up resets 5 s after the last champion hit")
	Combat.clock = 0.0
	var hit := DamageInfo.make(100.0, Combat.Style.MELEE, champ)
	hit.is_attack = true
	check(is_equal_approx(tower.modify_incoming(100.0, hit), 120.0), "melee champions deal 20% more damage to turrets")
	var minion_hit := DamageInfo.make(100.0, Combat.Style.MELEE, null)
	var gob := Minion.new()
	gob.init_minion("goblin", GameData.unit_def("minions", "goblin"), 0, "mid", MapLayout.lane_path("mid", 0), 1)
	var vs_champ := DamageInfo.make(100.0, Combat.Style.MELEE, gob)
	gob.modify_outgoing(vs_champ, champ)
	check(is_equal_approx(vs_champ.amount, 60.0), "minions deal 60% damage to champions")
	gob.free()
	var altar := Structure.new()
	altar.init_structure("altar", GameData.unit_def("structures", "altar"), Combat.Team.ZAMORAK, "Test altar", "altar")
	add_child(altar)
	check(is_equal_approx(altar.max_health, 4000.0), "altars (inhibitors) have 4000 health")
	altar.die(null)
	await get_tree().physics_frame
	check(altar.is_dead and is_equal_approx(altar.respawn_timer, 300.0), "altars respawn after 5 minutes")
	altar._dead_tick(300.0)
	check(not altar.is_dead and is_equal_approx(altar.health, 4000.0), "a respawned altar comes back at full health")
	for n in [tower, champ, altar]:
		n.queue_free()
	await get_tree().process_frame


func test_lol_monsters() -> void:
	check(is_equal_approx(Monster.by_level([2300, 6210], 1, 1), 2300.0), "Blue Sentinel has 2300 health at level 1")
	check(is_equal_approx(Monster.by_level([2300, 6210], 18, 1), 6210.0), "...and 6210 at level 18")
	var blue := Monster.new()
	blue.init_monster("abyssal_demon", GameData.unit_def("monsters", "abyssal_demon"), Vector3.ZERO, "test", 1)
	check(is_equal_approx(blue.max_health, 2300.0) and is_equal_approx(blue.get_defence(2), 42.0), "abyssal demon = Blue Sentinel (2300 HP, 42 MR)")
	check(is_equal_approx(blue.get_attack_interval(), 2.4), "abyssal demon attacks every 4 ticks, as in OSRS")
	blue.free()
	var drake := Monster.new()
	drake.init_monster("chromatic_dragon", GameData.unit_def("monsters", "chromatic_dragon"), Vector3.ZERO, "test", 1)
	check(drake.level == 6 and is_equal_approx(drake.max_health, 5106.25), "drakes start at level 6 with 5106 health")
	drake.free()
	# Dragon variants: four colours that look different, and the King Black Dragon.
	var ddef: Dictionary = GameData.unit_def("monsters", "chromatic_dragon")
	var ids: Array = []
	for pick in [0.0, 0.3, 0.6, 0.99]:
		ids.append(str(Monster.roll_variant(ddef, 0, 0.0, pick).get("id")))
	check(ids == ["green", "blue", "red", "black"], "the dragon rolls green, blue, red or black (%s)" % str(ids))
	check(str(Monster.roll_variant(ddef, 0, 0.0, 0.5).get("id")) != "kbd", "the first dragon is never the King Black Dragon, even on a perfect roll")
	check(str(Monster.roll_variant(ddef, 1, 0.1, 0.5).get("id")) == "kbd", "after a dragon has been killed the King Black Dragon can spawn")
	check(str(Monster.roll_variant(ddef, 5, 0.9, 0.5).get("id")) != "kbd", "...but only on its chance (30%)")
	var plain := Monster.new()
	plain.init_monster("chromatic_dragon", Monster.apply_variant(ddef, Monster.roll_variant(ddef, 0, 0.5, 0.6)), Vector3.ZERO, "test", 6)
	var kbd := Monster.new()
	kbd.init_monster("chromatic_dragon", Monster.apply_variant(ddef, Monster.roll_variant(ddef, 1, 0.0, 0.0)), Vector3.ZERO, "test", 6)
	check(plain.display_name == "Red dragon" and plain.variant_id == "red", "a red dragon is named for its colour")
	check(is_equal_approx(plain.max_health, 5106.25) and is_equal_approx(plain.base_damage, 70.0) and plain.gold_value == 75, "colours are purely visual: same health, damage and gold")
	check(kbd.display_name == "King Black Dragon" and kbd.variant_id == "kbd", "the King Black Dragon is named")
	check(kbd.max_health > plain.max_health * 1.5 and kbd.base_damage > plain.base_damage * 1.3 and kbd.gold_value > plain.gold_value * 1.5,
		"the King Black Dragon has more health, damage and gold")
	check(kbd.radius > plain.radius, "...and is bigger")
	plain.free()
	kbd.free()
	var jad := Monster.new()
	jad.init_monster("tztok_jad", GameData.unit_def("monsters", "tztok_jad"), Vector3.ZERO, "test", 18)
	check(is_equal_approx(jad.max_health, 19190.0) and is_equal_approx(jad.base_damage, 515.0), "Jad = Baron Nashor (19190 HP, 515 damage at level 18)")
	jad.free()
	var timings := {}
	for c in MapLayout.all_camps():
		timings[c["id"]] = c
	check(timings["sara_blue"]["first"] == 55 and timings["sara_blue"]["respawn"] == 300, "blue/red: 0:55, every 5:00")
	check(timings["dragon"]["first"] == 300, "first drake at 5:00")
	check(timings["grubs"]["first"] == 480 and timings["mole"]["first"] == 900 and timings["jad"]["first"] == 1200,
		"Voidgrubs 8:00, Herald 15:00, Baron 20:00")
	check(timings["sara_chickens"]["members"].size() == 6, "the chicken camp is 1 big + 5 small, like Raptors")


func test_skiller() -> void:
	var c := _make("skiller", Combat.Team.SARADOMIN, Vector3(-82, 0, 82))
	var foe := _make("dharok", Combat.Team.ZAMORAK, Vector3(-80, 0, 82))
	foe.spawn_point = MapLayout.ZAMORAK_BASE   # keep it away from a healing fountain
	await get_tree().physics_frame
	check(c.combat_level() == 3, "the Skiller is combat level 3 (got %d)" % c.combat_level())
	check(c.skill("woodcutting") == 99 and c.skill("attack") == 1 and c.skill("hitpoints") == 10, "1 combat, 99 skilling, 10 Hitpoints")
	check(SkillsPanel.wants_full(c.def) and not SkillsPanel.wants_full(GameData.champion("dharok")), "only skilling builds get the full Skills grid")
	c.gold = 99999
	check(c.can_buy("rune_scimitar") and not c.can_buy("bandos_chestplate"), "the Skiller makes his own rune scimitar (90 Smithing) but can't wear Bandos")
	check(c.buy_item("bronze_axe") and c.buy_item("rune_axe") and c.buy_item("dragon_axe"), "but can work up to a Dragon axe")
	check(c.buy_item("dragon_pickaxe") and c.buy_item("dragon_harpoon"), "and buy a Dragon pickaxe and harpoon")
	check(is_equal_approx(c.get_skill_power(), 40.0 + 40.0 + 35.0 + 35.0), "tools add skill power")
	c.spec = 100.0
	var sp := c.get_skill_power()
	check(c.use_item(0, null, c.global_position) and c.get_skill_power() > sp, "Dragon axe spec (Lumber Up) boosts skill power")
	c.remove_status(c.find_status_id("skill_power_mult"))
	for slot in Champion.SLOTS:
		c.ranks[slot] = 1
	foe.global_position = Vector3(-76, 0, 82)
	var before := c.flat_distance_to(foe)
	c.try_cast("e", foe, foe.global_position)
	for i in 30:
		await get_tree().physics_frame
	check(c.flat_distance_to(foe) < before - 2.0, "Harpoon reels the target in (%.1f -> %.1f m)" % [before, c.flat_distance_to(foe)])
	foe.health = foe.max_health
	foe.global_position = c.global_position + Vector3(6, 0, 0)
	c.cooldowns["q"] = 0.0
	c.try_cast("q", null, c.global_position + Vector3(2.5, 0, 0))     # plant between us
	check(c.standing_trees().size() == 1, "Timber! plants a yew")
	c.cooldowns["q"] = 0.0
	c.try_cast("q", null, c.standing_trees()[0].global_position)      # chop it onto the foe
	var hp := foe.health
	await get_tree().create_timer(0.8).timeout
	check(foe.health < hp and foe.has_status("slow"), "Timber! hits and slows enemies the tree falls on")
	foe.health = foe.max_health
	c.cooldowns["w"] = 0.0
	c.try_cast("w", null, foe.global_position)
	await get_tree().create_timer(0.3).timeout
	var after_first := foe.health
	await get_tree().create_timer(1.6).timeout
	check(foe.health < after_first, "Bonfire keeps burning enemies inside")
	c.health = c.max_health * 0.5
	foe.health = foe.max_health
	foe.global_position = c.global_position + Vector3(2, 0, 0)
	var foe_hp := foe.health
	var my_hp := c.health
	c.spec = 100.0
	c.cooldowns["r"] = 0.0
	check(c.skilling_casts_until_level_up() == 1, "the 4th ability triggers Level up!")
	c.try_cast("r", null, Vector3(-60, 0, 60))
	await get_tree().physics_frame
	check(c.health > my_hp and foe.health < foe_hp, "Level up! fireworks heal the Skiller and hit nearby enemies")
	check(c.skilling_casts_until_level_up() == 4, "the Level up! counter resets")
	c.queue_free()
	foe.queue_free()
	await get_tree().process_frame


## Timber!: planting, blocking, the 3-tree limit, chopping direction and bots.
func test_timber() -> void:
	var p := Vector3(40, 0, -40)
	var c := _make("skiller", Combat.Team.SARADOMIN, p)
	var walker := _make("dharok", Combat.Team.ZAMORAK, p + Vector3(0, 0, 20))
	var ahead := _make("dharok", Combat.Team.ZAMORAK, p + Vector3(-9, 0, 0))
	var behind := _make("dharok", Combat.Team.ZAMORAK, p + Vector3(4, 0, 0))
	for u in [walker, ahead, behind]:
		u.spawn_point = MapLayout.ZAMORAK_BASE
	await get_tree().physics_frame
	c.ranks["q"] = 1
	var ab := c.get_ability("q")
	var cfg: Dictionary = ab["planter"]
	var counter := c.skilling_casts_until_level_up()

	check(c.try_cast("q", null, p + Vector3(0, 0, 4)), "Q on open ground plants a yew")
	var first := c.standing_trees()[0]
	check(Unit.flat_distance(first.global_position, p + Vector3(0, 0, 4)) < 0.05, "the yew is planted where the cursor was")
	check(first.collision_layer == Unit.LAYER_WALLS and PlantedTree.active.has(first), "the yew is a solid obstacle")
	check(is_equal_approx(c.cooldowns["q"], float(cfg["cooldown"])), "planting has the short plant cooldown")
	check(c.skilling_casts_until_level_up() == counter, "planting doesn't count toward Level up!")
	c.cooldowns["q"] = 0.0
	c.try_cast("q", null, p + Vector3(0, 0, 30))
	check(Unit.flat_distance(c.standing_trees()[1].global_position, p) <= float(ab["range"]) + 0.05, "planting is clamped to the ability range")
	c.cooldowns["q"] = 0.0
	c.try_cast("q", null, p + Vector3(-4, 0, 0))
	check(c.standing_trees().size() == 3, "three yews can stand at once")
	check(c.tree_to_replace(cfg) == first, "the oldest yew is next to be replaced")
	c.cooldowns["q"] = 0.0
	c.try_cast("q", null, p + Vector3(0, 0, -4))
	await get_tree().physics_frame
	check(c.standing_trees().size() == 3 and (not is_instance_valid(first) or not first.is_standing()), "a 4th yew replaces the oldest")

	# Blocking: walking straight at a yew goes around it; a dash stops at it.
	var block: PlantedTree = c.standing_trees()[0]     # at p + (0, 0, 30) clamped -> (0, 0, 8)
	var bp := block.global_position
	walker.global_position = bp + Vector3(-4, 0, 0)
	walker.command_move(bp + Vector3(4, 0, 0))
	var closest := INF
	for i in 150:
		await get_tree().physics_frame
		closest = minf(closest, walker.flat_distance_to(block))
	check(closest >= block.block_radius + walker.radius - 0.1, "units can't walk through a yew (closest %.2f m)" % closest)
	check(walker.global_position.x > bp.x + 2.0, "units walk around a yew to reach the far side")
	walker.global_position = bp + Vector3(-3, 0, 0)
	walker.start_dash(bp + Vector3(3, 0, 0), 24.0)
	for i in 30:
		await get_tree().physics_frame
	check(walker.global_position.x < bp.x, "dashes are stopped by a yew")
	walker.global_position = p + Vector3(0, 0, 25)

	# Chopping: the yew at p + (-4, 0, 0) is out of reach, so the Skiller walks
	# over; it then falls away from the Skiller (toward -x), onto `ahead`.
	var chop: PlantedTree = c.standing_trees()[1]
	c.cooldowns["q"] = 0.0
	var hp_ahead := ahead.health
	var hp_behind := behind.health
	check(c.try_cast("q", null, chop.global_position) and c._queued_cast.has("tree"), "Q on a far yew walks over to chop it")
	for i in 90:
		await get_tree().physics_frame
		if not chop.is_standing():
			break
	check(not chop.is_standing(), "the yew is chopped once in reach")
	check(c.cooldowns["q"] > float(cfg["cooldown"]) + 1.0, "chopping uses the full cooldown")
	await get_tree().create_timer(0.7).timeout
	check(ahead.health < hp_ahead and ahead.has_status("slow"), "the falling yew hits and slows enemies in its path")
	check(is_equal_approx(behind.health, hp_behind), "it falls away from the Skiller, not onto enemies behind them")
	check(c.skilling_casts_until_level_up() == counter - 1, "chopping counts toward Level up!")
	check(c.standing_trees().size() == 2, "a chopped yew is gone")

	# Bots plant between themselves and a target, then fell it onto them.
	for t in c.standing_trees():
		t.wither()
	await get_tree().physics_frame
	c.global_position = p
	ahead.global_position = p + Vector3(6, 0, 0)
	ahead.health = ahead.max_health
	ahead.remove_status(ahead.find_status_id("slow"))
	c.cooldowns["q"] = 0.0
	check(c._bot_timber("q", ab, ahead) and c.standing_trees().size() == 1, "a bot plants a yew toward its target")
	c.cooldowns["q"] = 0.0
	var hp2 := ahead.health
	check(c._bot_timber("q", ab, ahead) and c.standing_trees().is_empty(), "then chops it when the target is in the fall path")
	await get_tree().create_timer(0.7).timeout
	check(ahead.health < hp2, "the bot's yew lands on the target")

	# Expiry
	c.cooldowns["q"] = 0.0
	c.try_cast("q", null, p + Vector3(0, 0, 3))
	var short := c.standing_trees()[0]
	short.lifetime = 0.05
	await get_tree().create_timer(0.7).timeout   # the next game tick
	check(not is_instance_valid(short) or not short.is_standing(), "yews wither when their lifetime ends")
	for u in [c, walker, ahead, behind]:
		u.queue_free()
	await get_tree().create_timer(0.5).timeout


func test_ability_indicator() -> void:
	var c := _make("skiller", Combat.Team.SARADOMIN, Vector3(-40, 0, 40))
	var ind := AbilityIndicator.new()
	add_child(ind)
	c.ranks["q"] = 1
	ind.update_for(c, "q", c.global_position + Vector3(3, 0, 0), null, null)
	check(ind.mode == "plant" and ind.visible, "Timber! indicator shows the planting spot")
	c.try_cast("q", null, c.global_position + Vector3(3, 0, 3))
	var tree := c.standing_trees()[0]
	ind.update_for(c, "q", tree.global_position, null, tree)
	var expect := (tree.global_position - c.global_position).normalized()
	check(ind.mode == "chop" and ind.chop_tree == tree and ind.fall_dir.distance_to(expect) < 0.01,
		"hovering a yew shows its fall path, away from the Skiller")
	var mage := _make("ancient_mage", Combat.Team.SARADOMIN, Vector3(-40, 0, 30))
	for slot in Champion.SLOTS:
		var ab := mage.get_ability(slot)
		ind.update_for(mage, slot, mage.global_position + Vector3(4, 0, 0), null, null)
		var want: String = {"point": "point", "target_unit": "target", "self": ""}[str(ab.get("cast", "self"))]
		check(ind.mode == want, "indicator for %s %s (%s)" % [mage.champ_id, slot, ab.get("name", "")])
	ind.clear()
	check(not ind.visible, "indicator clears")
	tree.wither()
	for n in [c, mage, ind]:
		n.queue_free()


## v0.5: damage breakdowns, Thick Skin, tags, icons, scoreboard, tooltips.
func test_v05_ui() -> void:
	var c := _make("skiller", Combat.Team.SARADOMIN, Vector3(-30, 0, -60))
	await get_tree().physics_frame
	c.ranks["q"] = 2
	var rows := AbilityInfo.breakdown(c, c.get_ability("q"), 2)
	check(rows.size() == 1, "Timber! has one damage line in its tooltip")
	var r: Dictionary = rows[0]
	check(is_equal_approx(r["spell"], 70.0 + 40.0), "spell part uses the rank (70 + 40 at rank 2)")
	check(is_equal_approx(r["items"], 0.0) and r["stats"] > 0.0, "no items yet: all ratio damage is from stats")
	check(is_equal_approx(r["total"], r["spell"] + r["stats"] + r["items"]), "total = spell + stats + items")
	c.gold = 99999
	c.buy_item("bronze_axe")
	c.buy_item("rune_axe")
	var r2: Dictionary = AbilityInfo.breakdown(c, c.get_ability("q"), 2)[0]
	check(r2["items"] > 0.0 and is_equal_approx(r2["stats"], r["stats"]), "buying an axe shows up as item damage")
	var tip := AbilityInfo.tooltip(c, "q")
	check(tip.contains("Total:") and tip.contains("Items:"), "ability tooltip shows the breakdown and total")
	var longest := 0
	for line in tip.split("\n"):
		longest = maxi(longest, line.length())
	check(longest <= UiStyle.TOOLTIP_WIDTH, "tooltips wrap to %d characters (longest %d)" % [UiStyle.TOOLTIP_WIDTH, longest])
	var dh := _make("dharok", Combat.Team.ZAMORAK, Vector3(-30, 0, -50))
	await get_tree().physics_frame
	for slot in Champion.SLOTS:
		check(AbilityInfo.tooltip(dh, slot) != "", "Dharok %s tooltip builds" % slot)

	check(c.chosen_prayer == "thick_skin", "the Skiller's prayer is Thick Skin (Prayer 1)")
	check(c.toggle_chosen_prayer() and c.prayer_effect("damage_taken") < 0.0, "Thick Skin reduces damage taken")
	check(PrayerBook.effect_text(dh.chosen_prayer_data()).begins_with("+"), "prayer effect text")
	check(c.find_child("ChestTag", true, false) == null, "no two-letter tags on champions any more")
	var missing: Array[String] = []
	for id in GameData.item_order:
		if Icons.item(id) == null:
			missing.append(id)
	check(missing.is_empty(), "every item has an OSRS icon (missing: %s)" % ", ".join(missing))
	check(Icons.prayer("Thick Skin") != null and Icons.prayer("Piety") != null, "prayer icons load")

	# Scoreboard: enemy items are only updated while seen.
	var fake_main := Node.new()
	fake_main.set_script(_ScoreMain)
	add_child(fake_main)
	fake_main.set("champions", [c, dh])
	var holder := Control.new()
	add_child(holder)
	var sb := MatchScoreboard.create(holder, fake_main)
	sb.viewer_team = c.team
	sb._update_seen()
	check(sb.shown_items(dh).is_empty(), "scoreboard starts with what was seen (nothing)")
	dh.global_position = Vector3(-900, 0, -900)       # far from every Saradomin unit
	dh.gold = 99999
	dh.buy_item("rune_platebody")
	sb._update_seen()
	check(sb.shown_items(dh).is_empty(), "items bought out of sight aren't shown")
	dh.global_position = c.global_position + Vector3(4, 0, 0)
	sb._update_seen()
	check(sb.shown_items(dh).has("rune_platebody"), "items show once the enemy is seen")
	check(sb.shown_items(c).has("rune_axe"), "your own team's items are always current")
	sb.refresh()
	for n in [c, dh, fake_main, holder]:
		n.queue_free()
	await get_tree().process_frame


const _ScoreMain := preload("res://tests/score_main_stub.gd")


## Attack and ability effects: data is valid and every effect plays without errors.
func test_combat_fx() -> void:
	const KINDS := ["swipe", "multi_slash", "projectile", "volley", "burst", "ring", "glow", "ice_block", "slam", "streak", "sparks"]
	var bad: Array[String] = []
	var fx_lists: Array = []
	for id in GameData.champion_order:
		var c: Dictionary = GameData.champion(id)
		check(c.has("attack_fx"), "%s has an attack look" % id)
		for slot in c.get("abilities", {}):
			var ab: Dictionary = c["abilities"][slot]
			fx_lists.append([id + ":" + slot, ab.get("fx", [])])
			for form in ab.get("forms", {}).values():
				fx_lists.append([id + ":" + slot, form.get("fx", [])])
	for item_id in GameData.item_order:
		fx_lists.append([item_id, GameData.item(item_id).get("spec_active", {}).get("fx", [])])
	for pair in fx_lists:
		for e in pair[1]:
			if not KINDS.has(str(e.get("kind", ""))):
				bad.append("%s: %s" % [pair[0], e.get("kind", "?")])
	check(bad.is_empty(), "every fx entry has a known kind %s" % str(bad))
	check(CombatFx.color("ice") == CombatFx.ELEMENTS["ice"] and CombatFx.color("#ff0000") == Color(1, 0, 0), "fx colours parse")
	# Play every ability and spec effect once between two champions.
	var a := _make("zerker", Combat.Team.SARADOMIN, Vector3(80, 0, -80))
	var b := _make("dharok", Combat.Team.ZAMORAK, Vector3(84, 0, -80))
	b.spawn_point = MapLayout.ZAMORAK_BASE
	await get_tree().physics_frame
	var before := get_child_count()
	for pair in fx_lists:
		if not (pair[1] as Array).is_empty():
			CombatFx.ability(a, {"fx": pair[1], "cast": "target_unit"}, b, b.global_position)
	for style in [Combat.Style.MELEE, Combat.Style.RANGED, Combat.Style.MAGIC]:
		a.attack_style = style
		a._attack_visuals(b)
		Projectile.launch(a, b, a.get_attack_fx(), Callable())
	await get_tree().physics_frame
	check(get_child_count() > before, "effects spawn into the world")
	await get_tree().create_timer(2.5).timeout
	check(get_child_count() <= before + 2, "and clean themselves up (%d left)" % (get_child_count() - before))
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame


## The private OSRS model pack (skipped when it isn't installed).
func test_osrs_models() -> void:
	OsrsModels.enabled = true
	if not OsrsModels.available():
		print("SKIP: OSRS model pack not installed (private_assets/osrs)")
		OsrsModels.enabled = false
		return
	check(OsrsModels.clips().has_animation("special_attack_7514"), "baked OSRS clip library has the claws special")
	var z := _make("zerker", Combat.Team.SARADOMIN, Vector3(60, 0, 60))
	var dummy := _make("dharok", Combat.Team.ZAMORAK, Vector3(61.5, 0, 60))
	dummy.spawn_point = MapLayout.ZAMORAK_BASE
	await get_tree().physics_frame
	check(z.osrs != null and z.osrs.is_player and not z._model.visible, "champions wear their OSRS model instead of the whitebox capsule")
	check(z.osrs.weapon_id == 6528 and z.osrs._shield == null, "the Zerker holds a Tzhaar-ket-om, no shield")
	z.gold = 99999
	z.buy_item("dragon_claws")
	z.spec = 100.0
	check(z.use_item(z.inventory.find("dragon_claws"), dummy, dummy.global_position), "Dragon claws spec fires")
	check(z.osrs.weapon_id == 13652 and z.osrs.is_busy(), "the spec swaps the claws into the Zerker's hand")
	await get_tree().create_timer(2.2).timeout
	check(z.osrs.weapon_id == 6528 and not z.osrs.is_busy(), "after the spec the Tzhaar-ket-om is back")
	var j := _make("justiciar", Combat.Team.SARADOMIN, Vector3(64, 0, 60))
	await get_tree().physics_frame
	j._cast_visuals("r")
	check(j.osrs.weapon_id == 11804, "Bandos Rally swaps in the Bandos godsword")
	await get_tree().create_timer(2.2).timeout
	check(j.osrs.weapon_id == 21015, "then Dinh's bulwark comes back")
	# Real build gear on the former stand-ins.
	for pair in [["max_ranger", 20997], ["blowpiper", 12926], ["lunar", 9084]]:
		var c := _make(str(pair[0]), Combat.Team.SARADOMIN, Vector3(68, 0, 60))
		await get_tree().physics_frame
		check(c.osrs.weapon_id == int(pair[1]), "%s holds item %d" % pair)
		c.queue_free()
	# The Skiller: no hammer, a gem bag in one hand and the gem he throws next in the other.
	var sk := _make("skiller", Combat.Team.SARADOMIN, Vector3(70, 0, 60))
	await get_tree().physics_frame
	check(sk.osrs.weapon_id == 0 and sk.osrs.has_gem_hand() and sk.osrs._gem_holder.get_child_count() == 1, "the Skiller holds a gem, no weapon")
	sk._cast_visuals("q")
	check(sk.osrs.weapon_id == 6739 and not sk.osrs._gem_holder.visible, "Timber! puts a dragon axe in his hand instead of the gem")
	# Abilities named for a weapon show it: the Pure's whip for Energy Drain.
	var pu := _make("pure", Combat.Team.SARADOMIN, Vector3(74, 0, 60))
	await get_tree().physics_frame
	pu._cast_visuals("q")
	check(pu.osrs.weapon_id == 4151, "Energy Drain swings an abyssal whip")
	await get_tree().create_timer(2.2).timeout
	check(pu.osrs.weapon_id == 4587 and sk.osrs.weapon_id == 0 and sk.osrs._gem_holder.visible, "then the dragon scimitar (and the Skiller's gem) come back")
	pu.queue_free()
	# Every weapon an ability or spec shows exists in the pack.
	var cfg := OsrsModels.config()
	for c in cfg["champions"].values():
		for ab in c.get("abilities", {}).values():
			if ab.has("weapon"):
				check(not OsrsModels.item(int(ab["weapon"])).is_empty(), "ability weapon %d is in the pack" % int(ab["weapon"]))
	for sname in cfg["spec_weapons"]:
		var w := int(cfg["spec_weapons"][sname].get("weapon", 0))
		check(w == 0 or not OsrsModels.item(w).is_empty(), "%s's weapon %d is in the pack" % [sname, w])
	check(OsrsModels.gem_item("Red topaz", true) == 1629 and OsrsModels.scene("items/1629.glb") != null, "gems are the OSRS models (uncut red topaz)")
	var held: Array = sk.next_gem.duplicate()
	var foe := _make("pure", Combat.Team.ZAMORAK, Vector3(72, 0, 60))
	sk.perform_attack(foe)
	var gems := sk.get_parent().find_children("*", "Projectile", false, false)
	var thrown: Projectile = null
	for g in gems:
		if (g as Projectile).fx.get("shape", "") == "gem":
			thrown = g
	check(thrown != null and thrown._gem_index == int(held[0]) and thrown._uncut == bool(held[1]), "he throws the gem he was holding")
	sk.queue_free()
	foe.queue_free()
	var h := _make("hybrid", Combat.Team.SARADOMIN, Vector3(66, 0, 60))
	await get_tree().physics_frame
	var before := h.osrs.weapon_id
	h.toggle_form()
	check(before == 11785 and h.osrs.weapon_id == 4675, "the Hybrid's form switch swaps the Armadyl crossbow for the staff")
	h.toggle_form()
	check(h.osrs.weapon_id == 11785, "and back")
	z.die(null)
	check(z.osrs._dead and z.visible, "a dying champion plays its death animation before vanishing")
	z.respawn()
	check(not z.osrs._dead, "and stands back up on respawn")
	var jad := Monster.new()
	jad.init_monster("tztok_jad", GameData.unit_def("monsters", "tztok_jad"), Vector3(70, 0, 70), "test", 12)
	add_child(jad)
	check(jad.osrs != null and jad.osrs.has_clip("attack_magic"), "TzTok-Jad uses his OSRS model and clips")
	var dk := _make("dharok", Combat.Team.SARADOMIN, Vector3(72, 0, 64))
	await get_tree().physics_frame
	dk.osrs.moving = true
	dk.osrs._update_locomotion(true)
	var cur := dk.osrs.anim.current_animation
	check(cur.ends_with("_11466") and dk.osrs.anim.get_animation(cur).loop_mode != Animation.LOOP_NONE, "Dharok's greataxe run loops (got %s)" % cur)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not dk.osrs.moving, "a unit standing still goes back to idle")
	dk.queue_free()
	await test_osrs_extract_pack()
	OsrsModels.enabled = false
	var plain := _make("dharok", Combat.Team.SARADOMIN, Vector3(70, 0, 60))
	check(plain.osrs == null and plain._model.visible, "without the pack champions keep the whitebox shape")
	for n in [z, dummy, j, h, jad, plain]:
		n.queue_free()
	await get_tree().process_frame


## Extras that only packs built by tools/osrs_extract have (skipped otherwise).
func test_osrs_extract_pack() -> void:
	if str(OsrsModels.manifest().get("source", "")) != "osrs_extract":
		print("SKIP: the installed OSRS pack wasn't built by tools/osrs_extract")
		return
	check(OsrsModels.clip_by_id("whip_attack_1658") != "", "a clip is found by the animation id its name ends with")
	check(OsrsModels.clip_by_id("no_digits") == "", "and a name without an id finds nothing")
	var sk := _make("skiller", Combat.Team.SARADOMIN, Vector3(76, 0, 60))
	await get_tree().physics_frame
	check(sk.osrs != null and sk.osrs.weapon_id == 0, "the Skiller holds no weapon")
	check(sk.osrs.skeleton.find_children("*", "BoneAttachment3D", true, false).size() == 2, "a gem bag in one hand, a gem in the other")
	var crab := Monster.new()
	crab.init_monster("rock_crab", GameData.unit_def("monsters", "rock_crab"), Vector3(80, 0, 70), "test", 1)
	add_child(crab)
	check(crab.osrs != null, "camps use their own OSRS models (rock crab)")
	var base_drake: Dictionary = GameData.unit_def("monsters", "chromatic_dragon")
	var red := Monster.new()
	red.init_monster("chromatic_dragon", Monster.apply_variant(base_drake, base_drake["variants"]["colors"][2]), Vector3(84, 0, 70), "test", 6)
	add_child(red)
	check(red.osrs != null and red.osrs.get_child(0).scene_file_path.ends_with("red_dragon.glb"), "a red dragon variant uses the real red dragon model")
	if OsrsMap.has_region(50, 50):
		var lumb := OsrsMap.region(50, 50, Vector2i(3200, 3200), 0, false)
		check(lumb != null and lumb.position == Vector3.ZERO, "a map square loads at its origin tile")
		var d := OsrsMap.data(50, 50)
		check(d.get("objects", []).size() > 1000 and d.get("heights", []).size() == 4, "and its heights and objects load")
		check(is_finite(OsrsMap.height_at(d, 0, 10.5, 10.5)), "ground height can be sampled")
		lumb.free()
	# Worn armour hides the body parts it covers (models.json lists parts as
	# JSON numbers, which used to miss the body_N nodes: shirt through plate).
	var dh := OsrsActor.player(OsrsModels.champion_config("dharok"))
	var torso := dh.skeleton.get_node_or_null("body_2") as Node3D
	var legs := dh.skeleton.get_node_or_null("body_5") as Node3D
	check(torso != null and not torso.visible and legs != null and not legs.visible, "Dharok's armour hides the base shirt and legs")
	dh.free()
	# The game's own buildings and props.
	var zt := OsrsProps.structure("tower_outer", Combat.Team.ZAMORAK)
	check(zt != null and zt.get_child_count() == 1, "towers are OSRS objects")
	var tinted := false
	if zt != null:
		for mi in zt.find_children("*", "MeshInstance3D", true, false):
			var mat := (mi as MeshInstance3D).get_active_material(0) as BaseMaterial3D
			tinted = tinted or (mat != null and mat.albedo_color.r < 0.6)
		zt.free()
	check(tinted, "and Zamorak's tower takes its darker tint")
	for key in ["cannon", "prayer_altar", "yew"]:
		var p := OsrsProps.prop(key)
		check(p != null, "the %s prop loads" % key)
		if p != null:
			p.free()
	check(OsrsProps.prop("no_such_prop") == null, "an unknown prop is null (whitebox stays)")
	var tw := Structure.new()
	tw.init_structure("tower", GameData.unit_def("structures", "tower_outer"), Combat.Team.SARADOMIN, "Test tower", "tower_outer")
	add_child(tw)
	tw.global_position = Vector3(88, 0, 88)
	check(tw.custom_model != null, "a tower wears its OSRS look")
	var gob := Minion.new()
	gob.init_minion("goblin", GameData.unit_def("minions", "goblin"), Combat.Team.SARADOMIN, "mid", MapLayout.lane_path("mid", 0), 1)
	add_child(gob)
	check(gob.osrs != null, "melee minions are OSRS goblins")
	var kn := Minion.new()
	kn.init_minion("knight", GameData.unit_def("minions", "knight"), Combat.Team.ZAMORAK, "mid", MapLayout.lane_path("mid", 1), 1)
	add_child(kn)
	check(kn.osrs != null and kn.osrs.get_child(0).scene_file_path.ends_with("black_knight.glb"), "Zamorak's super minions are black knights")
	if OsrsModels.manifest().has("rift"):
		var mb := MapBuilder.new()
		mb.nav_region = NavigationRegion3D.new()
		mb.add_child(mb.nav_region)
		add_child(mb)
		mb._build_ground()
		mb._build_markings()
		mb._build_osrs_dressing()
		check(mb.osrs_dressed and mb.get_node_or_null("OsrsRift") != null, "the Rift is dressed with OSRS ground and scenery")
		var hidden := true
		for v in mb._whitebox_visuals:
			hidden = hidden and not v.visible
		check(hidden, "and the whitebox ground, lanes and labels are hidden")
		mb.queue_free()
	for n in [sk, crab, red, tw, gob, kn]:
		n.queue_free()
	await get_tree().process_frame


func test_item_specs() -> void:
	var tank := _make("justiciar", Combat.Team.SARADOMIN, Vector3(0, 0, 0))
	var foe := _make("dharok", Combat.Team.ZAMORAK, Vector3(1.5, 0, 0))
	await get_tree().physics_frame
	tank.gold = 99999
	check(tank.buy_item("armadyl_godsword"), "tank buys an Armadyl godsword")
	check(tank.item_action_key(0) == "item:armadyl_godsword", "AGS shows up as an item action")
	tank.spec = 100.0
	var hp := foe.health
	check(tank.use_item(0, foe, foe.global_position), "AGS spec fires")
	check(is_equal_approx(tank.spec, 50.0), "AGS spec spends 50% of the shared bar")
	check(foe.health < hp, "AGS spec deals damage")
	check(not tank.use_item(0, foe, foe.global_position), "AGS spec respects its cooldown")
	tank.queue_free()
	foe.queue_free()


## Casts every ability of every champion against a nearby enemy and an ally.
func test_every_ability() -> void:
	for id in GameData.champion_order:
		var caster := _make(id, Combat.Team.SARADOMIN, Vector3(0, 0, 0))
		var ally := _make("justiciar", Combat.Team.SARADOMIN, Vector3(-1.5, 0, 0))
		var foe := _make("dharok", Combat.Team.ZAMORAK, Vector3(1.8, 0, 0))
		await get_tree().physics_frame
		for slot in Champion.SLOTS:
			caster.ranks[slot] = 1
		for slot in Champion.SLOTS:
			caster.spec = 100.0
			caster.cooldowns[slot] = 0.0
			ally.health = ally.max_health * 0.5
			var ab := caster.get_ability(slot)
			var target: Unit = ally if bool(ab.get("target_ally", false)) else foe
			var ok := caster.try_cast(slot, target, foe.global_position)
			check(ok, "%s can cast %s (%s)" % [id, slot, ab.get("name", "")])
			check(caster.cooldowns[slot] > 0.0 or float(ab.get("cooldown", 0)) == 0.0, "%s %s goes on cooldown" % [id, slot])
			for i in 3:
				await get_tree().physics_frame
			if foe.is_dead:
				foe.respawn()
				foe.global_position = Vector3(1.8, 0, 0)
			caster.global_position = Vector3.ZERO
		await get_tree().create_timer(0.6).timeout
		for t in caster.standing_trees():
			t.wither()
		caster.queue_free()
		ally.queue_free()
		foe.queue_free()
		await get_tree().process_frame


## v0.10: Perfect food and potions, make-your-own gear, skilling tools for
## fighters, the home teleport animation.
func test_v010() -> void:
	GameData.load_all(1.0)
	var sk := _make("skiller", Combat.Team.SARADOMIN, Vector3(80, 0, -80))
	var pu := _make("pure", Combat.Team.SARADOMIN, Vector3(84, 0, -80))
	for c in [sk, pu]:
		c.spawn_point = Vector3(500, 0, 500)
	# Consumables: no requirement; Perfect with the level.
	for id in GameData.item_order:
		var it := GameData.item(id)
		if it.get("consumable", false):
			var lowest := 99
			for sk_name in it.get("potency", {}):
				lowest = mini(lowest, int(it["potency"][sk_name]))
			check(not it.has("requirements") and (it.has("potency") == (lowest >= 20 and lowest < 99)) and (not it.has("potency") or lowest >= 20),
				"%s has no requirement, and a 'perfect' level only from 20 up" % id)
	pu.skills["cooking"] = 20
	sk.gold = 9999
	pu.gold = 9999
	check(pu.buy_item("shark") and sk.buy_item("shark"), "anyone can buy sharks")
	check(sk.is_perfect("shark") and not pu.is_perfect("shark"), "99 Cooking makes them Perfect, 20 doesn't")
	sk.health = 1.0
	pu.health = 1.0
	sk.use_consumable(0)
	pu.use_consumable(0)
	var hs := sk.status_sum("heal_over_time")
	var hp := pu.status_sum("heal_over_time")
	check(is_equal_approx(hs, hp * 1.15), "a Perfect shark heals 15%% more (%.1f vs %.1f a second)" % [hs, hp])
	var tip := ItemSlot._tooltip(GameData.item("shark"), sk).split("\n")
	var use_i := -1
	for i in tip.size():
		if tip[i].begins_with("Use: "):
			use_i = i
	check(use_i >= 0 and tip[use_i].contains("Heals 200") and use_i + 1 < tip.size() and tip[use_i + 1].begins_with("'perfect' (80 Cooking): Heals 230"),
		"the tooltip shows the normal effect, then the 'perfect' one on the next line (%s)" % str(tip))
	check(not ItemSlot._tooltip(GameData.item("shrimps"), sk).contains("'perfect'") and not sk.is_perfect("trout") and not sk.is_perfect("attack_potion"),
		"nothing under level 20 has a 'perfect' version")
	pu.skills["herblore"] = 20
	check(pu.buy_item("super_restore"), "anyone can buy a super restore")
	pu.prayer = 0.0
	pu.use_consumable(0)
	check(is_equal_approx(pu.prayer, 40.0), "an ordinary super restore gives 40 prayer")
	# Make your own: artisan levels waive combat requirements.
	check(sk.can_make("rune_platebody") and sk.meets_requirements("rune_platebody"), "99 Smithing: the Skiller makes and wears a rune platebody")
	check(sk.meets_requirements("amulet_of_torture") and sk.meets_requirements("armadyl_godsword"), "...and a torture and a godsword")
	check(not sk.meets_requirements("abyssal_whip"), "a whip can't be made, so the Skiller can't wield it")
	pu.skills["smithing"] = 75
	check(not pu.can_make("rune_platebody") and pu.missing_requirements("bandos_chestplate") == ["65 Defence"], "rolled levels don't reach 99 Smithing")
	pu.skills["crafting"] = 63
	pu.skills["defence"] = 1
	check(pu.meets_requirements("green_dhide_body"), "63 Crafting: a 1 Defence Pure makes its own green d'hide body")
	# Skilling tools help fighters.
	var tower := Structure.new()
	tower.init_structure("tower", GameData.unit_def("structures", "tower_outer"), Combat.Team.ZAMORAK, "Test tower", "tower_outer")
	pu.skills["woodcutting"] = 61
	pu.inventory.clear()
	pu._rebuild_item_stats()
	pu.recompute_stats()
	var plain := DamageInfo.make(100.0, Combat.Style.MELEE, pu)
	plain.is_attack = true
	pu.modify_outgoing(plain, sk)
	check(pu.buy_item("dragon_axe"), "a Pure with 61 Woodcutting buys a dragon axe")
	var with_axe := DamageInfo.make(100.0, Combat.Style.MELEE, pu)
	with_axe.is_attack = true
	pu.modify_outgoing(with_axe, sk)
	check(with_axe.amount > plain.amount, "its skill power adds to the Pure's basic attacks")
	add_child(tower)
	tower.global_position = Vector3(-150, 0, 150)
	var vs_tower := DamageInfo.make(100.0, Combat.Style.MELEE, pu)
	pu.modify_outgoing(vs_tower, tower)
	var vs_champ := DamageInfo.make(100.0, Combat.Style.MELEE, pu)
	pu.modify_outgoing(vs_champ, sk)
	check(is_equal_approx(vs_tower.amount, vs_champ.amount * 1.15), "axes hit towers 15% harder")
	tower.queue_free()
	pu.skills["fishing"] = 61
	check(pu.buy_item("dragon_harpoon") and is_equal_approx(pu.consumable_mult("shark"), 1.15), "a dragon harpoon makes food and potions 15% stronger")
	# Home teleport: look around, then cast with the arms out.
	sk.global_position = Vector3(80, 0, -80)
	sk.start_recall()
	var fx := sk.get_node_or_null("TeleportFx") as TeleportFx
	check(fx != null, "recalling starts the teleport animation")
	var yaw0 := sk.rotation.y
	await get_tree().create_timer(0.4).timeout
	check(absf(sk.rotation.y - yaw0) > 0.3, "the champion looks to the side first")
	check(not fx._cast_started, "and keeps looking around for most of the 8 s channel")
	await get_tree().create_timer(6.6).timeout
	check(is_instance_valid(fx) and fx._cast_started and fx._arms.size() == 2 and fx._arms[0].visible, "then casts with its arms out")
	check(absf(fx.look_end + TeleportFx.CAST_TIME - 8.4) < 0.7, "the cast ends as the teleport lands (%.2f s)" % (fx.look_end + TeleportFx.CAST_TIME))
	await get_tree().create_timer(2.0).timeout
	check(not sk.is_recalling() and sk.global_position.distance_to(sk.spawn_point) < 0.5, "and arrives home")
	check(sk.get_node_or_null("TeleportFx") == null, "the animation cleans up")
	pu.start_recall()
	pu.command_move(pu.global_position + Vector3(3, 0, 0))
	await get_tree().process_frame
	check(pu.get_node_or_null("TeleportFx") == null or pu.get_node("TeleportFx").is_queued_for_deletion(), "moving cancels it")
	for c in [sk, pu]:
		c.queue_free()


## Splash screen and the GitHub-release updater (no network: replies are made up).
func test_updates() -> void:
	check(Updater.current_version() == str(ProjectSettings.get_setting("application/config/version")), "the version comes from project.godot")
	check(Updater.parse_version("v0.10.2") == [0, 10, 2] and Updater.parse_version("1.2") == [1, 2, 0], "versions parse")
	check(Updater.is_newer("v0.10.1", "0.10.0") and Updater.is_newer("0.11", "0.10.9") and not Updater.is_newer("v0.9.1", "0.10.0") \
		and not Updater.is_newer("0.10.0", "0.10.0"), "0.10 is newer than 0.9.1 (numbers, not text)")
	check(Updater.repo() == "redgouf/MOBA-FANTASY-GAME", "updates come from the game's GitHub repo")
	var reply := {"tag_name": "v9.0.0", "body": "## New\n- **Faster** ticks\n- More items", "html_url": "https://github.com/x/y/releases/tag/v9.0.0",
		"assets": [{"name": "GielinorLegends-v9.0.0-personal-OSRS-models.zip", "browser_download_url": "p", "size": 5},
			{"name": "GielinorLegends-v9.0.0-windows.zip", "browser_download_url": "https://example/w.zip", "size": 40000000}]}
	var r := Updater.read_release(reply, "0.10.0")
	check(r["newer"] and r["version"] == "9.0.0" and r["download"] == "https://example/w.zip", "a newer release offers the Windows zip, never the personal one")
	check(not Updater.read_release({"tag_name": "v0.1.0"}, "0.10.0")["newer"], "an older release isn't offered")
	var bat := Updater.install_script("C:\\G\\updates\\update.zip", "C:\\G\\GielinorLegends.exe", 1234)
	check(bat.contains("PID eq 1234") and bat.contains("Expand-Archive -LiteralPath 'C:\\G\\updates\\update.zip' -DestinationPath 'C:\\G'")
		and bat.contains("start \"\" \"C:\\G\\GielinorLegends.exe\""), "the installer waits, unzips over the game folder and restarts it")
	var splash := SplashScreen.new()
	add_child(splash)
	await get_tree().process_frame
	var ver := splash.find_child("Version", true, false) as Label
	check(ver != null and ver.text.contains(Updater.current_version()), "the splash shows this build's version")
	check(splash.find_child("Play", true, false) != null and splash.find_child("CheckUpdates", true, false) != null, "Play and Check for updates buttons")
	var old_auto := Settings.auto_update
	Settings.auto_update = false
	splash._manual = false
	splash._on_checked(r)
	var install := splash.find_child("Install", true, false) as Button
	check(install.visible and splash._notes.visible and splash._notes.text.contains("Faster ticks"),
		"with automatic updates off, a newer version lists its changes and offers Update now")
	check(Updater.can_install() and not ModelPack.loaded, "a normal build can install releases")
	check(splash.find_child("AutoUpdate", true, false) != null and not splash.auto_check, "an 'Update automatically' box; tests never auto-check")
	Settings.auto_update = old_auto
	splash._on_checked(Updater.read_release({"tag_name": "v" + Updater.current_version()}, Updater.current_version()))
	check(not install.visible and (splash.find_child("Status", true, false) as Label).text.contains("latest"), "up to date says so")
	splash._on_failed("No published release was found.")
	check((splash.find_child("Status", true, false) as Label).text.contains("No published release"), "failures are explained")
	splash.queue_free()


## Potions boost their own skill; ammo needs no Fletching.
func test_potions() -> void:
	GameData.load_all(1.0)
	check(not GameData.item("mithril_darts").get("requirements", {}).has("fletching"), "darts need no Fletching")
	var c := _make("max_ranger", Combat.Team.SARADOMIN, Vector3(90, 0, 90))
	c.spawn_point = Vector3(500, 0, 500)
	c.skills["herblore"] = 50
	var base_r := c.skill("ranged")
	var r_info := DamageInfo.make(100.0, Combat.Style.RANGED, c)
	c.modify_outgoing(r_info, null)
	var m_info := DamageInfo.make(100.0, Combat.Style.MELEE, c)
	c.modify_outgoing(m_info, null)
	c.gold = 9999
	check(c.buy_item("ranging_potion") and c.use_consumable(0), "drink a ranging potion")
	var want := 4 + int(floor(0.1 * base_r))
	check(c.boosted_skill("ranged") == base_r + want and c.skill("ranged") == base_r, "Ranged %d -> %d (+4 +10%%), base unchanged" % [base_r, c.boosted_skill("ranged")])
	var r2 := DamageInfo.make(100.0, Combat.Style.RANGED, c)
	c.modify_outgoing(r2, null)
	var g2 := DamageInfo.make(100.0, Combat.Style.MAGIC, c)
	c.modify_outgoing(g2, null)
	check(is_equal_approx(r2.amount, r_info.amount * 1.08) and c.status_sum("magic_damage_mult") == 0.0,
		"a ranging potion: +8%% Attack Damage (%.1f -> %.1f), no Magic Damage" % [r_info.amount, r2.amount])
	c.skills["herblore"] = 99
	check(c.buy_item("ranging_potion") and c.use_consumable(0) and is_equal_approx(c.status_sum("attack_damage_mult"), 0.08 * 1.15),
		"a 'perfect' ranging potion gives 15% more (+9.2% Attack Damage)")
	check(c.buy_item("magic_potion") and c.use_consumable(0) and c.status_sum("magic_damage_mult") > 0.09, "a magic potion: Magic Damage")
	var m3 := DamageInfo.make(100.0, Combat.Style.MAGIC, c)
	c.modify_outgoing(m3, null)
	check(m3.amount > 109.0, "and magic hits deal more")
	var d0 := c.get_defence(0)
	check(c.buy_item("saradomin_brew") and c.use_consumable(0), "drink a Saradomin brew")
	check(c.get_defence(0) > d0 * 1.19 and c.status_sum("attack_damage_mult") < 0.0 and c.status_sum("magic_damage_mult") < 0.0,
		"a brew: +20% Defence, -10% Attack and Magic Damage")
	check(c.skill_boost("defence") > 0 and c.skill_boost("attack") < 0, "(its skill levels change too, as flavour)")
	check(c.buy_item("super_restore") and c.use_consumable(0) and c.status_sum("attack_damage_mult") >= 0.0 and c.get_defence(0) > d0 * 1.19,
		"a super restore undoes the brew's penalties and keeps its Defence")
	var tip := ItemSlot._tooltip(GameData.item("super_strength"), c)
	check(tip.contains("Use: +10% Melee crit chance for 60s, +30% Melee Crit Damage for 60s (Strength +") and tip.contains("'perfect' (55 Herblore): +12% Melee crit chance"),
		"potion tooltips say what they do to damage, levels as flavour (%s)" % tip)
	check(str(GameData.item("super_strength").get("text", "")) != "", "potions have flavour text")
	# Strength potions: melee crits.
	c.statuses.clear()
	check(c.buy_item("super_strength") and c.use_consumable(0) and c.crit_chance() > 0.11, "a super strength: melee crit chance (+10%, 'perfect' +11.5%)")
	c.add_status("probe", "crit_chance", 1.0, 5.0)
	var ci := DamageInfo.make(100.0, Combat.Style.MELEE, c)
	c.modify_outgoing(ci, null)
	check(is_equal_approx(ci.crit_mult, 1.5 * (1.0 + c.styled_sum("crit_damage_mult", Combat.Style.MELEE))) and ci.crit_mult > 1.5,
		"a crit hits for 150%%, more with Crit Damage (x%.2f)" % ci.crit_mult)
	check(BuffBar.describe({"kind": "crit_chance", "amount": 0.1})["icon"] == "crit", "crit buffs have their own icon")
	c.queue_free()


## v0.13: live stats, Max Ranger's attack-style stances, Dharok's rock cakes.
func test_v013() -> void:
	GameData.load_all(1.0)
	var mr := _make("max_ranger", Combat.Team.SARADOMIN, Vector3(120, 0, -120))
	mr.spawn_point = Vector3(500, 0, 500)
	mr.ranks["q"] = 1
	mr.ranks["e"] = 1
	var base_int := mr.get_attack_interval()
	var base_dmg := mr.effective_damage()
	check(mr.try_cast("q", null, mr.global_position), "Rapid casts")
	check(mr.stance == "rapid" and mr.get_attack_interval() < base_int and mr.effective_damage() < base_dmg,
		"Rapid: faster attacks, less damage")
	var stance_ids := 0
	for id in mr.statuses:
		if str(mr.statuses[id]["data"].get("stance", "")) == "rapid":
			stance_ids += 1
			check(bool(mr.statuses[id]["permanent"]), "the Rapid stance doesn't wear off")
	check(stance_ids == 2, "Rapid is two effects (speed and damage)")
	var holder := Control.new()
	add_child(holder)
	var bar := BuffBar.create(holder, Rect2(0, 0, 300, 34))
	bar.unit = mr
	bar.refresh()
	check(bar._slots.size() == 1, "one buff icon for the stance (got %d)" % bar._slots.size())
	var info := BuffBar.describe(mr.statuses[mr.statuses.keys()[0]])
	check(info["icon"] == "rapid" and info["title"] == "Rapid" and str(info["text"]).contains("+30% attack speed"), "it shows as Rapid with an arrow icon, not a potion")
	holder.queue_free()
	mr.cooldowns["e"] = 0.0
	mr.try_cast("e", null, mr.global_position)
	check(mr.stance == "longrange" and mr.get_attack_range() > mr.base_attack_range + 1.9 and mr.get_attack_interval() > base_int
		and mr.get_defence(1) > mr.base_defence[1], "Longrange replaces Rapid: more range and defence, slower attacks")
	check(not mr.has_status("damage_mult"), "Rapid's damage penalty is gone")
	mr.cooldowns["e"] = 0.0
	mr.try_cast("e", null, mr.global_position)
	check(mr.stance == "" and is_equal_approx(mr.get_attack_range(), mr.base_attack_range), "casting it again goes back to Accurate")
	mr.cooldowns["q"] = 0.0
	mr.try_cast("q", null, mr.global_position)
	mr.level = 3
	mr.skill_points = 1
	var fast := mr.get_attack_interval()
	mr.rank_up("q")
	check(mr.get_attack_interval() < fast, "ranking up Rapid strengthens the stance already on")
	mr.die(null)
	mr.respawn()
	check(mr.stance == "rapid" and mr.has_status("attack_speed"), "the attack style survives death")
	mr.queue_free()

	# Dharok: rock cakes stack; only the first of a run gives speed.
	var dh := _make("dharok", Combat.Team.SARADOMIN, Vector3(124, 0, -120))
	dh.spawn_point = Vector3(500, 0, 500)
	dh.ranks["w"] = 1
	check(float(dh.get_ability("w")["cooldown"]) <= 3.0, "Rock Cake has a short cooldown")
	dh.try_cast("w", null, dh.global_position)
	check(dh.has_status("haste") and is_equal_approx(dh.status_sum("rock_cake"), 1.0), "the first cake gives speed and a x1 stack")
	dh.remove_status(dh.find_status_id("haste"))
	dh.cooldowns["w"] = 0.0
	dh.try_cast("w", null, dh.global_position)
	dh.cooldowns["w"] = 0.0
	dh.try_cast("w", null, dh.global_position)
	check(is_equal_approx(dh.status_sum("rock_cake"), 3.0) and not dh.has_status("haste"), "more cakes stack to x3 with no new speed")
	var cake := BuffBar.describe(dh.statuses["stack:rock_cake"])
	check(cake["title"] == "Rock cake x3" and int(cake["count"]) == 3, "the buff bar shows Rock cake x3")
	dh._tick_statuses(5.1)
	check(not dh.has_status("rock_cake"), "the stack ends 5s after the last cake")
	dh.cooldowns["w"] = 0.0
	dh.try_cast("w", null, dh.global_position)
	check(dh.has_status("haste"), "then the next cake gives speed again")

	# Live stats: buffs show in the bottom-left panel at once.
	var hud := Hud.new()
	hud.setup(self, dh, false)
	add_child(hud)
	hud.set_process(false)   # (no match here: only the panel update is tested)
	hud.scoreboard.set_process(false)
	dh.statuses.clear()
	hud._update_bottom_left()
	var move_before := (hud._stats["move"] as Label).text
	dh.add_status("probe", "haste", 0.5, 3.0)
	hud._update_bottom_left()
	var move_l := hud._stats["move"] as Label
	check(move_l.text != move_before and move_l.get_theme_color("font_color").g > 0.9 and move_l.get_theme_color("font_color").r < 0.5,
		"a speed boost shows at once, in green (%s -> %s)" % [move_before, move_l.text])
	dh.add_status("probe2", "damage_mult", 0.2, 3.0)
	hud._update_bottom_left()
	check((hud._stats["damage"] as Label).text == "Dmg %d" % int(dh.effective_damage()) and dh.effective_damage() > dh.base_damage * 1.19,
		"damage buffs show in Dmg")
	hud.queue_free()
	dh.queue_free()


## Normal cast: a right-click cancels the spell indicator (and still moves).
func test_right_click_cancels_aim() -> void:
	var c := _make("pure", Combat.Team.SARADOMIN, Vector3(140, 0, -140))
	c.ranks["e"] = 1
	var rig := CameraRig.new()
	add_child(rig)
	var pc := PlayerController.new()
	pc.setup(self, c, rig)
	add_child(pc)
	await get_tree().process_frame
	var old_mode := Settings.cast_mode
	Settings.cast_mode = Settings.CAST_NORMAL
	pc.aiming = "e"
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Vector2(800, 450)
	pc._unhandled_input(ev)
	check(pc.aiming == "", "a right-click cancels the spell indicator")
	pc.begin_action("e")
	check(pc.aiming == "e" or c.get_action("e").get("cast", "self") == "self", "the indicator can come back up while walking")
	Settings.cast_mode = old_mode
	pc.queue_free()
	rig.queue_free()
	c.queue_free()


## v0.15: League-style ability tooltips and screen-space unit bars.
func test_v015_ui() -> void:
	GameData.load_all()
	var c := _make("dharok", Combat.Team.SARADOMIN, Vector3(150, 0, -150))
	c.ranks["q"] = 3
	var d := AbilityInfo.tooltip_data(c, "q")
	check(str(d["title"]) == "[Q] Greataxe Cleave" and str(d["subtitle"]) == "Rank 3 / 5" and str(d["cooldown"]).ends_with("s"),
		"tooltip header: [Q] name, rank, cooldown (%s)" % d["cooldown"])
	check(d["icon"] != null, "it has an icon (the champion's weapon)")
	check(str(d["body"]).contains(" = (") and str(d["body"]).contains("melee damage"), "damage written out: N = (base +X% Damage) melee damage")
	var labels: Array = []
	for r in d["rows"]:
		labels.append(r["label"])
		check((r["values"] as Array).size() == 5, "%s has a value for each of 5 ranks" % r["label"])
	check(labels.has("Damage") and labels.has("Cooldown"), "rank table: Damage and Cooldown (%s)" % str(labels))
	check(AbilityTooltip.rank_values(["1", "2", "3"], 2).contains("[b]2[/b]"), "the current rank is highlighted")
	var tip := AbilityTooltip.build(d)
	add_child(tip)
	await get_tree().process_frame
	check(tip.find_child("Ranks", true, false) != null and tip.find_child("Body", true, false) != null, "the tooltip builds")
	tip.queue_free()
	var spec := AbilityInfo.tooltip_data(c, "r")
	check(str(spec["cost"]).contains("special attack") and str(spec["footer"]).contains("levels 6, 11 and 16"), "the R shows its spec cost and unlock levels")
	# Screen-space bars: 3D bars and names are hidden; UnitBars draws them.
	check(not c._health_bar.visible and not c._name_label.visible, "the old 3D bar and name are hidden")
	var bars := UnitBars.new()
	add_child(bars)
	bars.viewer = c
	await get_tree().process_frame
	check(bars.is_inside_tree(), "UnitBars runs without a match camera")
	bars.queue_free()
	c.queue_free()
	GameData.load_all(1.0)


func test_v016() -> void:
	GameData.load_all()
	# Names coloured by level like OSRS's right-click menu.
	check(UnitBars.level_color(100, 100) == Color8(255, 255, 0), "same combat level: yellow")
	check(UnitBars.level_color(80, 100) == Color8(0, 255, 0), "10+ lower: green")
	check(UnitBars.level_color(120, 100) == Color8(255, 0, 0), "10+ higher: red")
	check(UnitBars.level_color(105, 100) == Color8(255, 128, 0), "a few higher: orange (OSRS steps of 3)")
	var me := _make("dharok", Combat.Team.SARADOMIN, Vector3(150, 0, -150))
	var ally := _make("pure", Combat.Team.SARADOMIN, Vector3(152, 0, -150))
	var foe := _make("pure", Combat.Team.ZAMORAK, Vector3(-150, 0, 150))
	var bars := UnitBars.new()
	bars.viewer = me
	check(bars.team_fill(me) == UnitBars.SELF and bars.team_fill(ally) == UnitBars.ALLY and bars.team_fill(foe) == UnitBars.ENEMY,
		"health bars tell the teams apart: green you, blue allies, red enemies")
	bars.free()
	# Items: every pair of boots builds from leather boots; materials build up.
	for id in GameData.item_order:
		var it := GameData.item(id)
		if GrandExchange.category(it) == "Boots" and str(it.get("name", "")).to_lower().contains("boots") and id != "leather_boots":
			check(me._builds_into("leather_boots", id), "%s builds from leather boots" % id)
	for id in ["cowhide", "ball_of_wool", "logs", "feather", "iron_ore", "gold_ore"]:
		check(GrandExchange.category(GameData.item(id)) == "Materials", "%s is a material" % id)
		var used := false
		for other in GameData.item_order:
			used = used or (id in GameData.item(other).get("builds_from", []))
		check(used, "%s builds into something" % id)
	check(me._builds_into("bronze_boots", "dragon_boots") and me._builds_into("climbing_boots", "spiked_boots"), "bronze → rune → dragon boots; climbing → spiked")
	check(me._builds_into("gold_ring", "ring_of_suffering") and me._builds_into("wizard_robe", "ahrims_robetop")
		and me._builds_into("coif", "archer_helm") and me._builds_into("priest_gown", "justiciar_chestguard"), "base items build into the big ones")
	var buyer := _make("justiciar", Combat.Team.SARADOMIN, Vector3(150, 0, -152))
	buyer.gold = 10000.0
	buyer.buy_item("leather_boots")
	var full := int(GameData.item("dragon_boots")["cost"])
	check(buyer.item_cost("dragon_boots") == full - 300, "leather boots count toward dragon boots, two steps down (%d)" % buyer.item_cost("dragon_boots"))
	check(buyer.buy_item("dragon_boots") and buyer.inventory == ["dragon_boots"], "and are used up when you buy them (%s)" % str(buyer.inventory))
	buyer.queue_free()
	for id in GameData.item_order:
		if not GameData.item(id).get("consumable", false):
			check(Icons.item(id) != null, "%s has an icon" % id)
	# Potions: attack = melee damage, strength = melee crits, ranging = ranged damage.
	me.gold = 99999.0
	me.buy_item("super_attack")
	me.use_consumable(0)
	check(me.style_damage_bonus(Combat.Style.MELEE) > 0.09 and is_zero_approx(me.style_damage_bonus(Combat.Style.RANGED)), "super attack: melee damage only")
	check(is_zero_approx(me.crit_chance()), "attack potions give no crits")
	me.buy_item("super_strength")
	me.use_consumable(0)
	check(me.crit_chance(Combat.Style.MELEE) > 0.09 and me.crit_multiplier(Combat.Style.MELEE) > 1.5 and is_zero_approx(me.crit_chance(Combat.Style.RANGED)),
		"super strength: melee crit chance and crit damage")
	ally.gold = 99999.0
	ally.buy_item("ranging_potion")
	ally.use_consumable(0)
	check(ally.style_damage_bonus(Combat.Style.RANGED) > 0.07 and is_zero_approx(ally.style_damage_bonus(Combat.Style.MELEE)), "ranging potion: ranged damage only")
	var txt := ", ".join(ItemSlot.use_parts(GameData.item("ranging_potion")["use"]))
	check(txt.contains("Ranged Damage"), "the ranging potion says Ranged Damage (%s)" % txt)
	# Ability icons: every champion has one for each slot.
	for cid in GameData.champions.keys():
		for slot in ["passive", "q", "w", "e", "r"]:
			check(Icons.ability(str(cid), slot) != null or Icons.ability(str(cid), slot, "ranged") != null, "%s %s has an ability icon" % [cid, slot])
	for c in [me, ally, foe]:
		c.queue_free()


func test_v021() -> void:
	GameData.load_all()
	# Side-lane towers stand on the lane's outer edge, inside the map walls.
	var half := MapLayout.MAP_SIZE * 0.5
	for team in [Combat.Team.SARADOMIN, Combat.Team.ZAMORAK]:
		for s in MapLayout.structure_layout(team):
			if s["kind"] == "tower" and s["lane"] in ["top", "bot"]:
				var p: Vector3 = s["pos"]
				var edge := maxf(absf(p.x), absf(p.z))
				check(edge > 86.0 and edge < half - 1.0, "%s %s tower sits at the lane's outer edge (%.1f, wall at %.0f)" % [s["lane"], s["tier"], edge, half])
	check(half <= 90.0, "the map walls hug the side lanes")
	# Spectator fog: switching to a champion on the other team flips the view at once.
	var a := _make("pure", Combat.Team.SARADOMIN, Vector3(40, 0, 40))
	var b := _make("dharok", Combat.Team.ZAMORAK, Vector3(-60, 0, -60))
	var fog := FogOfWar.new()
	add_child(fog)
	fog.set_team(Combat.Team.SARADOMIN)
	fog.update_vision()
	check(b.fog_hidden and not a.fog_hidden, "fog: the far-off enemy is hidden")
	fog.set_team(Combat.Team.ZAMORAK)
	check(not b.fog_hidden and a.fog_hidden, "switching teams shows your new team and fogs the old one, without toggling F")
	fog.queue_free()
	a.queue_free()
	b.queue_free()
	# The 8 s recall and the OSRS teleport clips.
	check(is_equal_approx(float(GameData.rule("recall_channel_sec", 0)), 8.0), "Teleport Home takes 8 s")
	check(str(OsrsModels.config().get("teleport", {}).get("cast_clip", "")) == "a714", "it casts the normal OSRS teleport (714)")
	# Towers never turn or move; everything moves at half speed; zoom limits.
	var tw := Structure.new()
	tw.init_structure("tower", GameData.unit_def("structures", "tower_outer"), Combat.Team.SARADOMIN, "Test tower")
	add_child(tw)
	tw.rotation.y = 0.3
	tw.face_toward(tw.global_position + Vector3(5, 0, 1))
	tw.start_dash(tw.global_position + Vector3(4, 0, 0), 10.0)
	check(is_equal_approx(tw.rotation.y, 0.3) and not tw._dashing, "towers don't turn to face targets or get knocked around")
	tw.queue_free()
	var walker := _make("pure", Combat.Team.SARADOMIN, Vector3(30, 0, 30))
	check(is_equal_approx(walker.get_move_speed(), walker.base_move_speed * 0.5), "units move at half their listed speed (rules.move_speed_scale)")
	walker.queue_free()
	var rig := CameraRig.new()
	add_child(rig)
	rig.set_spectator(false)
	check(is_equal_approx(rig.max_zoom, CameraRig.MIN_ZOOM + 10.0), "players zoom out 5 steps from fully in")
	rig.set_spectator(true)
	check(rig.max_zoom >= 200.0, "spectators zoom out to the whole map")
	check(rig.camera.near >= 1.0, "the camera's near plane leaves the depth buffer for the far ground (no z-fighting)")
	rig.queue_free()
	# Flags: cloth that casts shadows but doesn't receive its own.
	var cloth := Node3D.new()
	var cloth_mesh := MeshInstance3D.new()
	cloth_mesh.mesh = BoxMesh.new()
	cloth_mesh.material_override = StandardMaterial3D.new()
	cloth.add_child(cloth_mesh)
	OsrsProps.no_receive_shadows(cloth)
	check((cloth_mesh.material_override as BaseMaterial3D).disable_receive_shadows, "a flag's cloth doesn't receive shadows")
	check(cloth_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "...but still casts them")
	cloth.free()
