extends Node
## Headless test suite. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 when every check passes, 1 otherwise.

const KNOWN_EFFECTS := ["damage", "heal", "self_cost", "status", "dash", "knockback",
	"spec_transfer", "summon", "toggle_form", "taunt"]
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
	check(GameData.champions.size() == 10, "10 champions load (got %d)" % GameData.champions.size())
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
			check(Champion.SKILLS.has(str(s)), "%s requirement '%s' is a real skill" % [id, s])
		for comp in it.get("builds_from", []):
			check(GameData.items.has(comp), "%s builds from existing item %s" % [id, comp])
		if it.has("spec_active"):
			var sa: Dictionary = it["spec_active"]
			check(float(sa.get("spec_cost", 0)) > 0.0, "%s spec active costs spec energy" % id)
			check(float(sa.get("cooldown", 0)) > 0.0, "%s spec active has a cooldown" % id)
	for cat in ["minions", "structures", "monsters", "summons"]:
		check(not GameData.units.get(cat, {}).is_empty(), "units.json has %s" % cat)
	for c in MapLayout.all_camps():
		check(not GameData.unit_def("monsters", c["monster"]).is_empty(), "camp monster %s exists" % c["monster"])


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
	check(Combat.combat_level(1) == 3 and Combat.combat_level(18) == 126, "levels 1-18 show combat 3-126")


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
