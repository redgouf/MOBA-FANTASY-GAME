extends Node3D
## Match orchestrator: builds the map, spawns champions, structures, camps and
## waves, pays out gold and XP, and decides the winner.
##
## Command-line options (after a bare `--`):
##   --champion=<id>   skip champion select and play that build
##   --smoke-test      headless self-play for CI; exits with a summary
##   --smoke-seconds=N game seconds to simulate in smoke-test mode (default 150)

const ASSIST_WINDOW_SEC := 10.0

var map: MapBuilder
var units_root: Node3D
var camera_rig: CameraRig
var controller: PlayerController
var hud: Hud
var spawner: WaveSpawner
var player: Champion
var champions: Array[Champion] = []
var flags: Dictionary = {}
var game_time := 0.0
var match_started := false
var game_over := false
var winner := -1

var _camps: Dictionary = {}
var _camp_timers: Dictionary = {}
var _args: Dictionary = {}
var _smoke := false
var _smoke_seconds := 150.0
var _stats := {"minions_killed": 0, "structures_destroyed": 0, "champion_kills": 0, "monsters_killed": 0, "casts": 0}


func _ready() -> void:
	_args = _parse_args()
	_smoke = _args.has("smoke-test")
	_smoke_seconds = float(_args.get("smoke-seconds", 150))

	map = MapBuilder.new()
	map.name = "Map"
	add_child(map)
	map.build()

	units_root = Node3D.new()
	units_root.name = "Units"
	add_child(units_root)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)

	if _smoke or _args.has("champion"):
		start_match(str(_args.get("champion", "dharok")))
	else:
		var select := ChampionSelect.new()
		add_child(select)
		select.champion_selected.connect(func(id: String) -> void:
			select.queue_free()
			start_match(id))


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func start_match(champion_id: String) -> void:
	if not GameData.champions.has(champion_id):
		push_warning("Unknown champion '%s', defaulting to dharok" % champion_id)
		champion_id = "dharok"
	_spawn_structures(Combat.Team.SARADOMIN)
	_spawn_structures(Combat.Team.ZAMORAK)
	for c in MapLayout.all_camps():
		_camps[c["id"]] = c
		_spawn_camp(c["id"])

	var pool: Array[String] = GameData.champion_order.duplicate()
	pool.erase(champion_id)
	pool.shuffle()
	player = _spawn_champion(champion_id, Combat.Team.SARADOMIN, _smoke, "mid")
	_spawn_champion(pool[0], Combat.Team.SARADOMIN, true, "top")
	_spawn_champion(pool[1], Combat.Team.ZAMORAK, true, "mid")
	_spawn_champion(pool[2], Combat.Team.ZAMORAK, true, "top")

	spawner = WaveSpawner.new()
	spawner.name = "WaveSpawner"
	add_child(spawner)
	spawner.minion_spawned.connect(func(m: Minion) -> void: m.died.connect(_on_unit_died))
	spawner.start(units_root)

	camera_rig.follow = player
	camera_rig.center_on(player.global_position)
	controller = PlayerController.new()
	controller.name = "PlayerController"
	controller.setup(self, player, camera_rig)
	add_child(controller)
	hud = Hud.new()
	hud.setup(self, player)
	add_child(hud)
	hud.announce("Welcome to the Wilderness Rift. Destroy the Zamorak standard!", true)
	match_started = true
	print("[match] %s (you) + %s vs %s + %s" % [player.display_name, GameData.champion(pool[0]).get("name"),
		GameData.champion(pool[1]).get("name"), GameData.champion(pool[2]).get("name")])


func _spawn_champion(id: String, team: int, bot: bool, lane: String) -> Champion:
	var c := Champion.new()
	var spawn := MapLayout.base_position(team) + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	c.setup(id, team, spawn, bot)
	c.bot_lane = lane
	units_root.add_child(c)
	c.global_position = spawn
	c.died.connect(_on_unit_died)
	c.ability_cast.connect(func(_c: Champion, _slot: String) -> void: _stats["casts"] += 1)
	champions.append(c)
	return c


func _spawn_structures(team: int) -> void:
	var by_lane := {}
	var altars: Array[Structure] = []
	var flag_towers: Array[Structure] = []
	var flag: Structure = null
	for entry in MapLayout.structure_layout(team):
		var kind: String = entry["kind"]
		var def := GameData.unit_def("structures", kind)
		var label := str(def.get("name_saradomin" if team == Combat.Team.SARADOMIN else "name_zamorak", kind))
		var s := Structure.new()
		s.init_structure(kind, def, team, label)
		s.lane = entry["lane"]
		s.tier = entry["tier"]
		units_root.add_child(s)
		s.global_position = entry["pos"]
		s.died.connect(_on_unit_died)
		match s.tier:
			"flag":
				flag = s
			"flag_tower":
				flag_towers.append(s)
			_:
				if not by_lane.has(s.lane):
					by_lane[s.lane] = {}
				by_lane[s.lane][s.tier] = s
				if s.tier == "altar":
					altars.append(s)
	# Destruction order: outer -> inner -> altar tower -> altar; any altar opens the flag towers.
	for lane in by_lane:
		var t: Dictionary = by_lane[lane]
		(t["inner"] as Structure).requires_all.append(t["outer"])
		(t["altar_tower"] as Structure).requires_all.append(t["inner"])
		(t["altar"] as Structure).requires_all.append(t["altar_tower"])
	for ft in flag_towers:
		ft.requires_any = altars
	flag.requires_all = flag_towers
	flags[team] = flag


func _spawn_camp(camp_id: String) -> void:
	var c: Dictionary = _camps[camp_id]
	var monster_id: String = c["monster"]
	if camp_id == "jad" and game_time < float(GameData.rule("jad_spawn_sec", 840)):
		monster_id = "giant_mole"
	var m := Monster.new()
	m.init_monster(monster_id, GameData.unit_def("monsters", monster_id), c["pos"], camp_id)
	units_root.add_child(m)
	m.global_position = c["pos"]
	m.died.connect(_on_unit_died)


# --- Rewards -----------------------------------------------------------------

func _credit(killer: Unit) -> Champion:
	if killer is Champion:
		return killer
	if killer is Structure and is_instance_valid((killer as Structure).owner_champion):
		return (killer as Structure).owner_champion
	return null


func _on_unit_died(unit: Unit, killer: Unit) -> void:
	var killer_champ := _credit(killer)
	if unit is Champion:
		_on_champion_killed(unit, killer_champ, killer)
	elif unit is Structure:
		var s := unit as Structure
		if s.is_structure():
			_stats["structures_destroyed"] += 1
			for c in champions:
				if c.team != s.team:
					c.gold += s.gold_value
			_announce("%s destroyed a %s" % [Combat.TEAM_NAMES[1 - s.team], s.display_name])
			if s.kind == "flag":
				_end_game(1 - s.team)
	elif unit is Minion:
		_stats["minions_killed"] += 1
		if killer_champ != null:
			killer_champ.gold += unit.gold_value
	elif unit is Monster:
		_on_monster_killed(unit as Monster, killer_champ)
	_share_xp(unit)


func _on_champion_killed(victim: Champion, killer: Champion, killer_unit: Unit) -> void:
	_stats["champion_kills"] += 1
	if killer != null and killer.team != victim.team:
		killer.kills += 1
		killer.gold += float(GameData.rule("champion_kill_gold", 300))
	var now := Time.get_ticks_msec() / 1000.0
	for entry in victim.recent_attackers.values():
		var u: Variant = entry["unit"]
		if is_instance_valid(u) and u is Champion and u != killer and u.team != victim.team \
				and now - float(entry["time"]) <= ASSIST_WINDOW_SEC:
			u.assists += 1
			u.gold += float(GameData.rule("assist_gold", 150))
	victim.recent_attackers.clear()
	var killer_name := "the Wilderness"
	if killer != null:
		killer_name = killer.display_name
	elif is_instance_valid(killer_unit):
		killer_name = "a " + killer_unit.display_name
	if victim == player:
		_announce("Oh dear, you are dead! (%s)" % killer_name, true)
	else:
		_announce("%s defeated %s" % [killer_name, victim.display_name])


func _on_monster_killed(m: Monster, killer: Champion) -> void:
	_stats["monsters_killed"] += 1
	if killer != null:
		killer.gold += m.gold_value
		if not m.buff.is_empty():
			killer.add_status("buff:" + m.unit_id, str(m.buff["kind"]), float(m.buff["amount"]), float(m.buff["duration"]), killer)
		if not m.team_buff.is_empty():
			for c in champions:
				if c.team == killer.team and not c.is_dead:
					var id := "team_buff:%s:%d" % [m.unit_id, int(game_time)]
					c.add_status(id, str(m.team_buff["kind"]), float(m.team_buff["amount"]), float(m.team_buff["duration"]), c)
			_announce("%s slew %s! (%s)" % [Combat.TEAM_NAMES[killer.team], m.display_name, m.team_buff.get("label", "")], true)
	var respawn_key := "epic_respawn_sec" if m.is_epic else "monster_respawn_sec"
	_camp_timers[m.camp_id] = float(GameData.rule(respawn_key, 120))


func _share_xp(unit: Unit) -> void:
	var xp := float(unit.xp_value)
	if unit is Champion:
		xp = 100.0 + 40.0 * float((unit as Champion).level)
	if xp <= 0.0:
		return
	var radius := float(GameData.rule("xp_share_radius", 14))
	var near: Array[Champion] = []
	for c in champions:
		if not c.is_dead and c.team != unit.team and c.flat_distance_to(unit) <= radius:
			near.append(c)
	if near.is_empty():
		return
	var each := xp / float(near.size()) * (1.0 + 0.3 * float(near.size() - 1))
	for c in near:
		c.add_xp(each)


func _announce(text: String, big: bool = false) -> void:
	if hud != null:
		hud.announce(text, big)
	if _smoke:
		print("[%05.1f] %s" % [game_time, text])


func _end_game(winning_team: int) -> void:
	if game_over:
		return
	game_over = true
	winner = winning_team
	spawner.stop()
	if hud != null:
		hud.show_game_over(winning_team == player.team)
	print("[match] %s wins at %02d:%02d" % [Combat.TEAM_NAMES[winning_team], int(game_time) / 60, int(game_time) % 60])


# --- Frame update ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not match_started:
		return
	game_time += delta
	if game_over:
		if _smoke:
			_finish_smoke()
		return
	if game_time > float(GameData.rule("passive_gold_start", 60)):
		var rate := float(GameData.rule("passive_gold_per_sec", 2.0))
		for c in champions:
			c.gold += rate * delta
	for id in _camp_timers.keys():
		_camp_timers[id] -= delta
		if _camp_timers[id] <= 0.0:
			_camp_timers.erase(id)
			_spawn_camp(id)
	if _smoke:
		_smoke_step()


# --- Smoke test --------------------------------------------------------------

func _smoke_step() -> void:
	if game_time >= _smoke_seconds:
		_finish_smoke()
		return
	# In smoke-test mode the "player" is a bot too, so it shops and fights on its own.


func _finish_smoke() -> void:
	var lines: Array[String] = []
	lines.append("[smoke] simulated %.0fs of game time" % game_time)
	lines.append("[smoke] navigation baked: %s" % map.is_navigation_ready)
	lines.append("[smoke] waves: %d, %s" % [spawner.wave, str(_stats)])
	for c in champions:
		lines.append("[smoke] %-8s %-15s lvl %2d  K/D/A %d/%d/%d  gold %4d  items %s" % [
			Combat.TEAM_NAMES[c.team], c.display_name, c.level, c.kills, c.deaths, c.assists, int(c.gold), str(c.inventory)])
	for line in lines:
		print(line)
	get_tree().quit(0 if map.is_navigation_ready and spawner.wave > 0 else 1)
