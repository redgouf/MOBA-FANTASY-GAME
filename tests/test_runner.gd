extends Node
## Headless test suite. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 when every check passes, 1 otherwise.

const KNOWN_EFFECTS := ["damage", "heal", "self_cost", "status", "dash", "knockback",
	"spec_transfer", "summon", "toggle_form", "taunt", "pull", "prop"]
const KNOWN_CASTS := ["self", "target_unit", "point"]

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	test_data_integrity()
	test_combat_math()
	test_requirements()
	test_prayers()
	test_item_build_paths()
	test_skill_leveling()
	test_lol_minions_and_waves()
	await test_lol_turrets()
	test_lol_monsters()
	await test_skiller()
	await test_item_specs()
	await test_every_ability()
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
	check(is_equal_approx(Combat.ticks_to_seconds(4), 1.0), "4 ticks is 1 second")
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
	pure.toggle_protect(Combat.Style.MELEE)
	check(pure.protect_style == -1, "Pure has no overheads")
	tank.toggle_protect(Combat.Style.MAGIC)
	check(tank.protect_style == Combat.Style.MAGIC, "Justiciar Tank can pray magic")
	check(tank.get_protected_style() == Combat.Style.MAGIC, "protected style is reported")
	tank.add_status("sever", "disable_prayer", 0.0, 5.0)
	check(tank.get_protected_style() == -1, "Sever disables overheads")
	check(pure.offensive_prayer_name() == "Ultimate Strength", "52 Prayer Pure gets Ultimate Strength (got %s)" % pure.offensive_prayer_name())
	check(tank.offensive_prayer_name() == "Piety", "99 Prayer tank gets Piety")
	check(mage.offensive_prayer_name() == "Augury", "77 Prayer mage gets Augury")
	check(pipe.offensive_prayer_name() == "Eagle Eye", "52 Prayer ranger gets Eagle Eye")
	check(pure.activate_offensive_prayer() and pure.status_sum("damage_mult") > 0.0, "offensive prayer boosts damage")
	check(not tank.activate_offensive_prayer(), "Sever also blocks offensive prayers")
	for c in [pure, tank, mage, pipe]:
		c.queue_free()


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
	check(pure.buy_item("shark") and pure.consumables == ["shark"], "food goes on the belt")
	pure.health = 100.0
	check(pure.use_consumable(0) and pure.consumables.is_empty(), "eating removes the shark")
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
	check(is_equal_approx(1.0 / m.get_attack_interval(), 1.25), "melee minions attack 1.25 times per second")
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
	check(is_equal_approx(1.0 / tower.get_attack_interval(), 0.833), "turrets attack 0.833 times per second")
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
	check(is_equal_approx(tower.build_attack_damage(champ).amount, tower.get_damage()), "Warming Up resets 5 s after the last champion hit")
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
	altar._dead_process(300.0)
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
	check(is_equal_approx(1.0 / blue.get_attack_interval(), 0.493), "Blue Sentinel attacks 0.493 times per second")
	blue.free()
	var drake := Monster.new()
	drake.init_monster("chromatic_dragon", GameData.unit_def("monsters", "chromatic_dragon"), Vector3.ZERO, "test", 1)
	check(drake.level == 6 and is_equal_approx(drake.max_health, 5106.25), "drakes start at level 6 with 5106 health")
	drake.free()
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
	check(not c.can_buy("rune_scimitar") and not c.can_buy("bandos_chestplate"), "the Skiller can't wield combat gear")
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
	foe.global_position = c.global_position + Vector3(5, 0, 0)
	c.cooldowns["q"] = 0.0
	c.try_cast("q", null, foe.global_position)
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
		caster.queue_free()
		ally.queue_free()
		foe.queue_free()
		await get_tree().process_frame
