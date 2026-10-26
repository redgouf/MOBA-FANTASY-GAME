extends Node3D
## Match orchestrator: builds the map, spawns champions, structures, camps and
## waves, pays out gold and XP, and decides the winner.
##
## Two modes, both 5v5:
##   play      you control one champion; 4 bot allies vs 5 bots
##   spectate  NPC vs NPC: all 10 champions are bots and you watch
##
## Command-line options (after a bare `--`):
##   --champion=<id>     skip champion select and play that build
##   --spectate          skip champion select and watch NPC vs NPC
##   --smoke-test        headless all-bot run for CI; exits with a summary
##   --smoke-seconds=N   game seconds to simulate in smoke-test mode (default 150)
##   --screenshot=PATH   save a PNG of the game at --screenshot-at=SECONDS, then quit
##   --no-osrs           ignore the private OSRS model pack (whitebox shapes)
##   --shot-ui=NAME      before the screenshot: target | menu | settings | controls | shop | kit | skills | aim-chop | aim-plant | scoreboard | tooltip | teleport (--shot-tele-at=S) | look (--shot-pos=X,Z)
##   --demo-level=N      raise the viewed champion to level N with items (for screenshots)

const ASSIST_WINDOW_SEC := 10.0
const BOT_LANES: Array[String] = ["top", "mid", "bot", "bot", "top"]

var map: MapBuilder
var units_root: Node3D
var camera_rig: CameraRig
var controller: PlayerController
var spectator_controller: SpectatorController
var hud: Hud
var pause_menu: PauseMenu
var spawner: WaveSpawner
var selection_ring: SelectionRing
var fog: FogOfWar
var player: Champion            # the champion you control (null when spectating)
var focused: Champion           # whose perspective the HUD shows
var selected: Unit              # left-clicked unit shown in the inspect panel
var spectating := false
var champions: Array[Champion] = []
var flags: Dictionary = {}
var team_kills: Array[int] = [0, 0]
var game_time := 0.0
var match_started := false
var game_over := false
var winner := -1

var _camps: Dictionary = {}          # camp id -> layout dict
var _camp_alive: Dictionary = {}     # camp id -> Array[Monster]
var _camp_next: Dictionary = {}      # camp id -> game time of next spawn (-1 = none)
var _camp_kills: Dictionary = {}     # camp id -> how many times its monsters have been cleared
var _altars: Dictionary = {}         # team -> {lane: Structure}
var _first_turret_taken := false
var _args: Dictionary = {}
var unit_bars: UnitBars
var _smoke := false
var _smoke_seconds := 150.0
var _shot_path := ""
var _shot_at := 0.0
var _shot_taken := false
var _stuck_probe := {}          # smoke test: champion -> [position, game time it was last seen moving]
var _stuck_reports: Array[String] = []
var _stats := {"minions_killed": 0, "structures_destroyed": 0, "champion_kills": 0, "monsters_killed": 0, "casts": 0}


func _ready() -> void:
	Combat.clock = 0.0
	UiStyle.install_tooltip_theme()
	_args = _parse_args()
	_smoke = _args.has("smoke-test")
	if _args.has("no-osrs"):
		OsrsModels.enabled = false     # whitebox shapes even with the private pack installed
	OsrsFont.apply()                   # the OSRS fonts, with the private pack
	_smoke_seconds = float(_args.get("smoke-seconds", 150))
	_shot_path = str(_args.get("screenshot", ""))
	_shot_at = float(_args.get("screenshot-at", 20))

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

	selection_ring = SelectionRing.new()
	add_child(selection_ring)

	var mode := Settings.pending_mode
	var pending := Settings.pending_champion
	var pending_prayer := Settings.pending_prayer
	Settings.pending_mode = ""
	Settings.pending_champion = ""
	if _smoke or _args.has("spectate") or mode == "spectate":
		start_spectate()
	elif _args.has("champion") or (mode == "play" and pending != ""):
		start_match(str(_args.get("champion", pending)), str(_args.get("prayer", pending_prayer)))
	elif not Settings.splash_seen and (_shot_path == "" or _args.has("splash")):
		_show_splash()
	else:
		_show_champion_select()
		if _shot_path != "":
			get_tree().create_timer(float(_args.get("screenshot-at", 1.5))).timeout.connect(_take_screenshot)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


## The splash screen (once per session): version, Play, Check for updates.
func _show_splash() -> void:
	Settings.splash_seen = true
	var splash := SplashScreen.new()
	splash.auto_check = _shot_path == ""   # (screenshots stay offline)
	add_child(splash)
	splash.play_pressed.connect(func() -> void:
		splash.queue_free()
		_show_champion_select())
	if _shot_path != "":
		get_tree().create_timer(float(_args.get("screenshot-at", 1.5))).timeout.connect(_take_screenshot)


func _show_champion_select() -> void:
	var select := ChampionSelect.new()
	add_child(select)
	if _args.has("shot-select"):
		select.call_deferred("select_build", str(_args["shot-select"]), str(_args.get("prayer", "")))
	if _args.has("shot-tab"):
		select.call_deferred("show_tab", str(_args["shot-tab"]))
	if _args.has("shot-lock"):
		var at := float(_args["shot-lock"]) if str(_args["shot-lock"]).is_valid_float() else 1.0
		get_tree().create_timer(at).timeout.connect(select.lock_in)
	select.champion_selected.connect(func(id: String, prayer_id: String) -> void:
		select.queue_free()
		Settings.pending_prayer = prayer_id
		start_match(id, prayer_id))
	select.spectate_selected.connect(func() -> void:
		select.queue_free()
		start_spectate())


# --- Starting a match --------------------------------------------------------

## Play: you + 4 bot allies (Saradomin) vs 5 bots (Zamorak), one of each build.
func start_match(champion_id: String, prayer_id: String = "") -> void:
	if not GameData.champions.has(champion_id):
		push_warning("Unknown champion '%s', defaulting to dharok" % champion_id)
		champion_id = "dharok"
	GameData.ensure_match_rolls()
	_spawn_world()
	var pool: Array[String] = GameData.champion_order.duplicate()
	pool.erase(champion_id)
	pool.shuffle()
	player = _spawn_champion(champion_id, Combat.Team.SARADOMIN, false, "mid")
	player.set_chosen_prayer(prayer_id)
	var ally_lanes: Array[String] = ["top", "bot", "bot", "top"]
	var size := team_size()
	for i in mini(size - 1, ally_lanes.size()):
		_spawn_champion(pool.pop_back(), Combat.Team.SARADOMIN, true, ally_lanes[i])
	for i in mini(size, pool.size()):
		_spawn_champion(pool.pop_back(), Combat.Team.ZAMORAK, true, BOT_LANES[i % BOT_LANES.size()])

	controller = PlayerController.new()
	controller.name = "PlayerController"
	controller.setup(self, player, camera_rig)
	add_child(controller)
	_begin(player, "Welcome to the Wilderness Rift. Destroy the Zamorak standard!")


## Spectate: 5 bots vs 5 bots, watched from a free camera.
func start_spectate() -> void:
	spectating = true
	GameData.ensure_match_rolls()
	_spawn_world()
	var pool: Array[String] = GameData.champion_order.duplicate()
	pool.shuffle()
	if _args.has("champion") and pool.has(str(_args["champion"])):
		# Make sure a requested build is in the match (picked first).
		pool.erase(str(_args["champion"]))
		pool.append(str(_args["champion"]))
	var size := mini(team_size(), int(pool.size() / 2.0))
	for team in [Combat.Team.SARADOMIN, Combat.Team.ZAMORAK]:
		for i in size:
			_spawn_champion(pool.pop_back(), team, true, BOT_LANES[i % BOT_LANES.size()])
	spectator_controller = SpectatorController.new()
	spectator_controller.name = "SpectatorController"
	spectator_controller.setup(self, camera_rig)
	add_child(spectator_controller)
	_begin(champions[0], "NPC vs NPC — click a champion or press 1-5 / 6-0 to lock on")


func team_size() -> int:
	return int(_args.get("team-size", GameData.rule("team_size", 5)))


func _spawn_world() -> void:
	_spawn_structures(Combat.Team.SARADOMIN)
	_spawn_structures(Combat.Team.ZAMORAK)
	for c in MapLayout.all_camps():
		_camps[c["id"]] = c
		_camp_alive[c["id"]] = []
		_camp_next[c["id"]] = float(c.get("first", 0))


func _begin(view: Champion, welcome: String) -> void:
	# The OSRS game tick starts over with the match; Main ticks camps and gold.
	GameTick.reset()
	GameTick.register_world(self)
	spawner = WaveSpawner.new()
	spawner.name = "WaveSpawner"
	add_child(spawner)
	spawner.minion_spawned.connect(func(m: Minion) -> void: m.died.connect(_on_unit_died))
	spawner.altar_down = is_altar_down
	spawner.start(units_root)

	focused = view
	Hitsplat.viewer = view
	# Fog of war for the viewer's team (players can't turn it off).
	# Screen-space health bars, names and prayer bars over every unit.
	var bars_layer := CanvasLayer.new()
	bars_layer.name = "UnitBarsLayer"
	bars_layer.layer = -1
	add_child(bars_layer)
	unit_bars = UnitBars.new()
	unit_bars.viewer = view
	unit_bars.camera = camera_rig.camera
	bars_layer.add_child(unit_bars)
	# Hitsplats draw on the same layer after the bars: always on top of them.
	var splat_layer := Control.new()
	splat_layer.name = "Hitsplats"
	splat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splat_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars_layer.add_child(splat_layer)
	Hitsplat.overlay = splat_layer
	Hitsplat.camera = camera_rig.camera
	fog = FogOfWar.new()
	fog.name = "FogOfWar"
	add_child(fog)
	fog.set_team(view.team)
	camera_rig.camera.cull_mask &= ~FogOfWar.FOG_LAYER
	camera_rig.follow = view
	camera_rig.locked = spectating
	camera_rig.set_spectator(spectating)
	camera_rig.center_on(view.global_position)
	selection_ring.viewer_team = view.team

	hud = Hud.new()
	hud.setup(self, view, spectating)
	add_child(hud)
	pause_menu = PauseMenu.new()
	pause_menu.spectating = spectating
	pause_menu.hud = hud
	add_child(pause_menu)
	pause_menu.restart_requested.connect(restart_match)
	pause_menu.change_champion_requested.connect(change_champion)
	pause_menu.spectate_requested.connect(watch_bots)

	hud.announce(welcome, true)
	match_started = true
	var names: Array[String] = []
	for c in champions:
		names.append("%s%s" % [c.display_name, " (you)" if c == player else ""])
	print("[match] %s: %s" % ["spectate" if spectating else "play", ", ".join(names)])
	if _args.has("demo-level"):
		_apply_demo(view, int(_args["demo-level"]))


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


func team_roster(team: int) -> Array[Champion]:
	var out: Array[Champion] = []
	for c in champions:
		if c.team == team:
			out.append(c)
	return out


func _spawn_structures(team: int) -> void:
	var by_lane := {}
	var altars: Array[Structure] = []
	var flag_towers: Array[Structure] = []
	var flag: Structure = null
	_altars[team] = {}
	const TOWER_DEFS := {"outer": "tower_outer", "inner": "tower_inner", "altar_tower": "tower_inhibitor", "flag_tower": "tower_nexus"}
	for entry in MapLayout.structure_layout(team):
		var kind: String = entry["kind"]
		var def_id: String = TOWER_DEFS.get(entry["tier"], kind) if kind == "tower" else kind
		var def := GameData.unit_def("structures", def_id)
		var label := str(def.get("name_saradomin" if team == Combat.Team.SARADOMIN else "name_zamorak", kind))
		var s := Structure.new()
		s.init_structure(kind, def, team, label, def_id)
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
					_altars[team][s.lane] = s
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


func is_altar_down(team: int, lane: String) -> bool:
	var a: Variant = _altars.get(team, {}).get(lane)
	return is_instance_valid(a) and (a as Structure).is_dead


## Monster level = average champion level when the camp spawns (League rule).
func average_champion_level() -> int:
	if champions.is_empty():
		return 1
	var total := 0
	for c in champions:
		total += c.level
	return int(round(float(total) / float(champions.size())))


func _spawn_camp(camp_id: String) -> void:
	var c: Dictionary = _camps[camp_id]
	var alive: Array = []
	for member in c["members"]:
		var monster_id: String = member[0]
		var m := Monster.new()
		var home: Vector3 = c["pos"] + member[1]
		var def: Dictionary = GameData.unit_def("monsters", monster_id)
		if def.has("variants"):
			# Dragons: a random colour, or (never the first one) the King Black Dragon.
			def = Monster.apply_variant(def, Monster.roll_variant(def, int(_camp_kills.get(camp_id, 0)), randf(), randf()))
		m.init_monster(monster_id, def, home, camp_id, average_champion_level())
		units_root.add_child(m)
		m.global_position = home
		m.died.connect(_on_unit_died)
		alive.append(m)
	_camp_alive[camp_id] = alive
	_camp_next[camp_id] = -1.0
	var first: Monster = alive[0]
	if first.is_epic:
		if first.variant_id == "kbd":
			_announce("The %s has awoken!" % first.display_name, true)
		else:
			_announce("%s has appeared!" % first.display_name, true)


func _update_camps() -> void:
	for id in _camps:
		var c: Dictionary = _camps[id]
		var alive: Array = _camp_alive[id]
		if c.has("despawn") and game_time >= float(c["despawn"]):
			for m in alive:
				if is_instance_valid(m) and not m.is_dead:
					m.queue_free()
			_camp_alive[id] = []
			_camp_next[id] = -1.0
			continue
		if alive.is_empty() and _camp_next[id] >= 0.0 and game_time >= _camp_next[id]:
			_spawn_camp(id)


func _on_camp_member_died(m: Monster) -> void:
	var id := m.camp_id
	if not _camp_alive.has(id):
		return
	var alive: Array = _camp_alive[id]
	alive.erase(m)
	if alive.is_empty():
		_camp_kills[id] = int(_camp_kills.get(id, 0)) + 1
		var c: Dictionary = _camps[id]
		_camp_next[id] = -1.0 if c.get("once", false) else game_time + float(c.get("respawn", 120))


# --- Selection, focus and the ESC menu ---------------------------------------

func select_unit(u: Unit) -> void:
	selected = u
	selection_ring.target = u


## The focus ring (and inspect panel) jumps to whatever you start attacking,
## replacing a unit you had left-clicked; left-click still inspects anything.
var _attack_focus: Unit

func _follow_attack_focus() -> void:
	if player == null:
		return
	var t: Unit = player.attack_target if is_instance_valid(player.attack_target) and not player.attack_target.is_dead else null
	if t != _attack_focus:
		_attack_focus = t
		if t != null:
			select_unit(t)


## Spectator lock-on: show this champion's HUD and follow it with the camera.
func focus(c: Champion) -> void:
	if c == null:
		return
	focused = c
	Hitsplat.viewer = c
	if unit_bars != null:
		unit_bars.viewer = c
	if fog != null:
		fog.set_team(c.team)
	hud.set_champion(c)
	camera_rig.follow = c
	camera_rig.locked = true
	camera_rig.center_on(c.global_position)
	selection_ring.viewer_team = c.team


func restart_match() -> void:
	Settings.pending_mode = "spectate" if spectating else "play"
	Settings.pending_champion = player.champ_id if player != null else ""
	Settings.pending_prayer = player.chosen_prayer if player != null else ""
	_reload()


func change_champion() -> void:
	Settings.pending_mode = ""
	_reload()


func watch_bots() -> void:
	Settings.pending_mode = "spectate"
	_reload()


func _reload() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


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
			_on_structure_destroyed(s, killer_champ)
	elif unit is Minion:
		_stats["minions_killed"] += 1
		if killer_champ != null:
			killer_champ.gold += unit.gold_value * (1.0 + killer_champ.gold_bonus())
			killer_champ.creep_score += 1
	elif unit is Monster:
		if killer_champ != null:
			killer_champ.creep_score += 1
		_on_monster_killed(unit as Monster, killer_champ)
		_on_camp_member_died(unit as Monster)
	if unit == selected and not (unit is Structure and (unit as Structure).respawn_sec > 0.0):
		select_unit(null)
	_share_xp(unit, killer_champ)


## League structure rewards: turrets pay global gold to every enemy champion
## (outer 50, inner 25, inhibitor 25, nexus 50) and the first turret of the
## game gives 300 bonus gold to whoever destroys it; altars (inhibitors) pay
## 50 to the last hitter and respawn after 5 minutes.
func _on_structure_destroyed(s: Structure, killer: Champion) -> void:
	_stats["structures_destroyed"] += 1
	var enemy := 1 - s.team
	if s.global_gold > 0:
		for c in champions:
			if c.team == enemy:
				c.gold += s.global_gold
	if killer != null and s.last_hit_gold > 0:
		killer.gold += s.last_hit_gold
	if s.is_tower() and not _first_turret_taken:
		_first_turret_taken = true
		var bonus := float(GameData.units.get("turret_rules", {}).get("first_turret_bonus_gold", 300))
		if killer != null:
			killer.gold += bonus
		_announce("First turret! %s destroyed a %s" % [killer.display_name if killer != null else Combat.TEAM_NAMES[enemy], s.display_name], true)
	elif s.kind == "altar":
		_announce("%s destroyed the %s — Knights march for %d:00" % [Combat.TEAM_NAMES[enemy], s.display_name, int(s.respawn_sec / 60)], true)
	else:
		_announce("%s destroyed a %s" % [Combat.TEAM_NAMES[enemy], s.display_name])
	if s.kind == "flag":
		_end_game(enemy)


func _on_champion_killed(victim: Champion, killer: Champion, killer_unit: Unit) -> void:
	_stats["champion_kills"] += 1
	if killer != null and killer.team != victim.team:
		killer.kills += 1
		# Protect Item (prayer): the killer gets less gold.
		var kept := float(victim.prayer_special("protect_item").get("amount", 0.0))
		killer.gold += float(GameData.rule("champion_kill_gold", 300)) * (1.0 - kept)
		team_kills[killer.team] += 1
	elif victim.team <= 1:
		team_kills[1 - victim.team] += 1
	var now := Combat.clock
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
	victim.last_killer_name = killer_name
	if victim == player:
		_announce("You were killed by %s" % killer_name)
	else:
		_announce("%s defeated %s" % [killer_name, victim.display_name])


func _on_monster_killed(m: Monster, killer: Champion) -> void:
	_stats["monsters_killed"] += 1
	if killer != null:
		killer.gold += m.gold_value * (1.0 + killer.gold_bonus())
		if m.team_gold > 0:
			for c in champions:
				if c.team == killer.team and c != killer:
					c.gold += m.team_gold
		if not m.buff.is_empty():
			killer.add_status("buff:" + m.unit_id, str(m.buff["kind"]), float(m.buff["amount"]), float(m.buff["duration"]), killer)
		if not m.team_buff.is_empty():
			for c in champions:
				if c.team == killer.team and not c.is_dead:
					var id := "team_buff:%s:%d" % [m.unit_id, int(game_time)]
					c.add_status(id, str(m.team_buff["kind"]), float(m.team_buff["amount"]), float(m.team_buff["duration"]), c)
			_announce("%s slew %s! (%s)" % [Combat.TEAM_NAMES[killer.team], m.display_name, m.team_buff.get("label", "")], true)


## Experience goes to nearby champions of the team that earned it: enemies of
## the unit for minions/champions; the killer's team for neutral monsters.
func _share_xp(unit: Unit, killer: Champion = null) -> void:
	var xp := float(unit.xp_value)
	if unit is Champion:
		xp = 100.0 + 40.0 * float((unit as Champion).level)
	if xp <= 0.0:
		return
	var neutral := unit.team == Combat.Team.NEUTRAL
	if neutral and killer == null:
		return
	var radius := float(GameData.rule("monster_xp_share_radius" if neutral else "xp_share_radius", 14))
	var near: Array[Champion] = []
	for c in champions:
		if c.is_dead or c.flat_distance_to(unit) > radius:
			continue
		if (neutral and c.team == killer.team) or (not neutral and c.team != unit.team):
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
		hud.show_game_over(player != null and winning_team == player.team, winning_team)
	print("[match] %s wins at %02d:%02d" % [Combat.TEAM_NAMES[winning_team], int(game_time) / 60, int(game_time) % 60])


# --- Frame update ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not match_started:
		return
	game_time += delta
	Combat.clock = game_time
	_stats["crowd_pairs"] = int(_stats.get("crowd_pairs", 0)) + Crowd.solve(get_tree(), delta)
	_follow_attack_focus()
	if _shot_path != "" and not _shot_taken and game_time >= _shot_at:
		_take_screenshot()
	if game_over:
		if _smoke:
			_finish_smoke()
		return
	if _smoke:
		_probe_stuck()
	if _smoke and game_time >= _smoke_seconds:
		_finish_smoke()


## One game tick (GameTick world tickable): passive gold and camp respawns.
func game_tick(dt: float) -> void:
	if not match_started or game_over:
		return
	if game_time > float(GameData.rule("passive_gold_start", 60)):
		var rate := float(GameData.rule("passive_gold_per_sec", 2.0))
		for c in champions:
			c.gold += rate * dt
	_update_camps()


# --- Screenshots and demo state (for docs and visual checks) -----------------

func _apply_demo(c: Champion, target_level: int) -> void:
	while c.level < target_level - 1:
		c.add_xp(c.xp_to_next())
	c.bot_spend_skill_points()
	if c.level < target_level:
		c.add_xp(c.xp_to_next())     # leave this level's point unspent to show the "+"
	c.gold += 9000.0
	c._bot_shop()
	c.gold = 640.0
	c.spec = 75.0


func _take_screenshot() -> void:
	_shot_taken = true
	match str(_args.get("shot-ui", "")):
		"kit":
			# Cast Q, W and R in front of the camera, then capture mid-animation.
			var p := focused.global_position
			for slot in Champion.SLOTS:
				focused.ranks[slot] = maxi(1, int(focused.ranks[slot]))
				focused.cooldowns[slot] = 0.0
			focused.spec = 100.0
			focused.try_cast("w", null, p + Vector3(-5.0, 0.0, -4.0))
			focused.try_cast("r", null, p + Vector3(5.5, 0.0, 2.0))
			focused.try_cast("q", null, p + Vector3(2.4, 0.0, -1.8))
			if focused.get_ability("q").has("planter"):
				# Timber!: plant, then chop the yew so it is mid-fall in the shot.
				focused.cooldowns["q"] = 0.0
				focused.try_cast("q", null, focused.standing_trees()[0].global_position)
			hud.force_skills_popups = true
		"aim-chop", "aim-plant":
			# Timber!'s indicator: three yews planted, the cursor on one (chop:
			# its fall path) or on open ground (plant: the oldest will be replaced).
			focused.global_position = Vector3(-37.0, 0.0, 37.0)     # mid lane, in the open
			camera_rig.center_on(focused.global_position)
			await get_tree().process_frame
			var p := focused.global_position
			focused.ranks["q"] = maxi(1, int(focused.ranks["q"]))
			for off in [Vector3(3.0, 0, -2.0), Vector3(-3.5, 0, -1.0), Vector3(-0.5, 0, -4.5)]:
				focused.cooldowns["q"] = 0.0
				focused.try_cast("q", null, p + off)
			focused.cooldowns["q"] = 0.0
			var aim_at := focused.standing_trees()[0].global_position if _args["shot-ui"] == "aim-chop" else p + Vector3(-1.0, 0, -5.5)
			get_viewport().warp_mouse(camera_rig.camera.unproject_position(aim_at + Vector3.UP * (2.0 if _args["shot-ui"] == "aim-chop" else 0.0)))
			await get_tree().process_frame
			controller.begin_action("q", "ability_q")
			await get_tree().process_frame
		"splats":
			# Hitsplats: yours bright (dealt by you / taken by you), everyone else's tinted.
			var origin := Vector3(-37.0, 0.0, 37.0)
			focused.global_position = origin
			var foes: Array[Unit] = []
			for i in 2:
				var m := Minion.new()
				m.init_minion("goblin", GameData.unit_def("minions", "goblin"), 1 - focused.team, "mid", MapLayout.lane_path("mid", 1 - focused.team), 1)
				units_root.add_child(m)
				m.global_position = origin + Vector3(3.5 + 3.0 * i, 0, -1.5)
				m.set_physics_process(false)
				foes.append(m)
			var ally := Minion.new()
			ally.init_minion("dark_wizard", GameData.unit_def("minions", "dark_wizard"), focused.team, "mid", MapLayout.lane_path("mid", focused.team), 1)
			units_root.add_child(ally)
			ally.global_position = origin + Vector3(5.0, 0, 2.0)
			ally.set_physics_process(false)
			camera_rig.zoom = float(_args.get("shot-zoom", 13))
			camera_rig._apply_zoom()
			camera_rig.center_on(origin + Vector3(3.5, 0, 0))
			await get_tree().process_frame
			var mine := func(amount: float, crit: float, label: String) -> DamageInfo:
				var d := DamageInfo.make(amount, Combat.Style.MELEE, focused)
				d.crit_mult = crit
				d.label = label
				return d
			foes[0]._spawn_hitsplat(23.0, mine.call(23.0, 1.0, ""))
			foes[0]._spawn_hitsplat(0.0, mine.call(0.0, 1.0, ""))
			foes[0]._spawn_hitsplat(61.0, mine.call(61.0, 1.5, ""))
			foes[0]._spawn_hitsplat(8.0, mine.call(8.0, 1.0, "poison"))
			var theirs := DamageInfo.make(17.0, Combat.Style.MAGIC, ally)
			foes[1]._spawn_hitsplat(17.0, theirs)
			foes[1]._spawn_hitsplat(0.0, theirs)
			var crit2 := DamageInfo.make(44.0, Combat.Style.MAGIC, ally)
			crit2.crit_mult = 1.5
			foes[1]._spawn_hitsplat(44.0, crit2)
			focused._spawn_hitsplat(12.0, DamageInfo.make(12.0, Combat.Style.MELEE, foes[0]))
			focused._spawn_hitsplat(0.0, DamageInfo.make(0.0, Combat.Style.MELEE, foes[0]))
			ally._spawn_hitsplat(9.0, DamageInfo.make(9.0, Combat.Style.MELEE, foes[1]))
			await get_tree().create_timer(0.1).timeout
		"cannon":
			# The Slayer's multicannon and a siege minion's cannon cart, close up, firing.
			var origin := Vector3(-37.0, 0.0, 37.0)
			focused.global_position = origin + Vector3(-3.0, 0, 2.0)
			var s := Structure.new()
			s.init_structure("summon", GameData.unit_def("summons", "dwarf_multicannon"), focused.team, "Dwarf multicannon")
			s.lifetime = 30.0
			units_root.add_child(s)
			s.global_position = origin
			var cart := Minion.new()
			cart.init_minion("cannon_cart", GameData.unit_def("minions", "cannon_cart"), focused.team, "mid", MapLayout.lane_path("mid", focused.team), 1)
			units_root.add_child(cart)
			cart.global_position = origin + Vector3(3.0, 0, 1.0)
			cart.set_physics_process(false)
			cart.face_toward(origin + Vector3(6.0, 0, -3.0))
			camera_rig.zoom = float(_args.get("shot-zoom", 10))
			camera_rig._apply_zoom()
			camera_rig.center_on(origin + Vector3(1.0, 0, 0.5))
			await get_tree().process_frame
			(s.custom_model as CannonModel).fire(origin + Vector3(-4.0, 0, -6.0))
			(cart.custom_model as CannonModel).fire(origin + Vector3(8.0, 0, -4.0))
			await get_tree().create_timer(0.08).timeout
		"teleport":
			# Home teleport mid-cast (--shot-tele-at=S seconds into the channel).
			var spot := MapLayout.point_along(MapLayout.lane_path("mid", focused.team), 40.0)
			focused.global_position = spot
			camera_rig.center_on(spot)
			await get_tree().create_timer(0.3).timeout
			focused.start_recall()
			await get_tree().create_timer(float(_args.get("shot-tele-at", 2.4))).timeout
		"altar":
			# Praying at the Saradomin blue-side prayer altar, prayer switched on.
			var altar := PrayerAltar.nearest(MapLayout.saradomin_prayer_altars()[0]["pos"])
			focused.global_position = altar.global_position + Vector3(0.0, 0.0, 3.2)
			focused.prayer = 30.0
			camera_rig.center_on(altar.global_position)
			focused.toggle_chosen_prayer()
			focused.command_pray(altar)
			await get_tree().create_timer(0.5).timeout
		"skills":
			for c in champions:
				if c.team != focused.team:
					select_unit(c)
					break
			hud.force_skills_popups = true
		"target":
			var foe: Unit = focused.find_nearest_enemy(60.0, false, false)
			if foe == null:
				for c in champions:
					if c.team != focused.team:
						foe = c
						break
			select_unit(foe)
		"menu":
			pause_menu.open()
		"settings":
			pause_menu.open()
			pause_menu._show_page("settings")
		"controls":
			pause_menu.open()
			pause_menu._show_page("controls")
		"shop":
			focused.gold = 2600.0
			hud.toggle_shop()
			if _args.has("shot-tab"):
				hud._shop.show_tab(str(_args["shot-tab"]))
			if _args.has("shot-item"):
				hud._shop.select(str(_args["shot-item"]))
			await get_tree().process_frame
		"death":
			# The death screen, after a few buffs and debuffs went up.
			var killer: Champion = null
			for c in champions:
				if c.team != focused.team:
					killer = c
					break
			focused.take_damage(DamageInfo.make(99999.0, Combat.Style.MELEE, killer))
			await get_tree().create_timer(0.3).timeout
		"fog":
			# Fog of war from mid lane, zoomed out: enemies outside your team's
			# sight are hidden and the ground beyond it is darkened.
			focused.global_position = Vector3(-14.0, 0.0, 14.0)
			for c in champions:
				if c.team != focused.team:
					c.global_position = Vector3(randf_range(-10.0, 30.0), 0.0, randf_range(-30.0, 10.0))
			camera_rig.zoom = float(_args.get("shot-zoom", 46))
			camera_rig._apply_zoom()
			camera_rig.center_on(Vector3(0, 0, 0))
			fog.update_vision()
			await get_tree().create_timer(0.3).timeout
		"buffs":
			# Buff and debuff icons over the hotbar, part-way through their timers.
			focused.add_status("t1", "damage_mult", 0.15, 8.0, focused)
			focused.add_status("t2", "haste", 0.2, 6.0, focused)
			focused.add_status("t3", "root", 0.0, 2.0, null)
			focused.add_status("t4", "tele_block", 0.0, 6.0, null)
			focused.add_status("t5", "poison", 2.0, 6.0, null)
			focused.toggle_chosen_prayer()
			for slot in Champion.SLOTS:
				for e in focused.get_ability(slot).get("effects", []):
					if str(e.get("type", "")) == "stance" and focused.stance == "":
						focused.set_stance(e, 1)   # an attack style (Max Ranger)
				if focused.get_ability(slot).get("name", "") == "Rock Cake":
					for k in 3:
						AbilityRunner.execute(focused, focused.get_ability(slot), null, focused.global_position, 1)
			await get_tree().create_timer(1.5).timeout
		"look":
			# The camera over any spot of the map (--shot-pos=x,z), no fog: map checks.
			var v := str(_args.get("shot-pos", "0,0")).split(",")
			var at := Vector3(float(v[0]), 0.0, float(v[1]))
			if fog != null:
				fog.set_enabled(false)
			camera_rig.locked = false
			camera_rig.follow = null
			camera_rig.zoom = float(_args.get("shot-zoom", 30))
			camera_rig._apply_zoom()
			camera_rig.center_on(at)
			await get_tree().create_timer(0.4).timeout
		"lineup":
			# Every champion in a row in mid lane, close up (model checks).
			var origin := Vector3(-30.0, 0.0, 30.0)
			var i := 0
			for c in champions:
				c.is_bot = false
				c.command_stop()
				c.global_position = origin + Vector3(1.0, 0.0, 0.0) * (float(i) - 4.5) * 1.6
				c.rotation.y = float(_args.get("shot-rot", 0.0))
				i += 1
			camera_rig.zoom = float(_args.get("shot-zoom", 16))
			camera_rig._apply_zoom()
			# --shot-at-champ=N centres on the Nth champion of the row (close-ups).
			var focus_i := int(_args.get("shot-at-champ", -1))
			for k in champions.size():
				if champions[k].champ_id == str(_args.get("shot-champ", "")):
					focus_i = k
			camera_rig.center_on(origin + Vector3(1.0, 0.0, 0.0) * (float(focus_i) - 4.5) * 1.6 if focus_i >= 0 else origin)
			await get_tree().create_timer(0.3).timeout
		"fx":
			# Two rows facing each other; everyone attacks and casts at once.
			var origin := Vector3(-30.0, 0.0, 30.0)
			var rows := [[], []]
			for c in champions:
				c.is_bot = false
				c.command_stop()
				rows[c.team].append(c)
			for team in 2:
				for i in rows[team].size():
					var c: Champion = rows[team][i]
					c.global_position = origin + Vector3((float(i) - 2.0) * 3.2, 0.0, -4.5 if team == 0 else 4.5)
			camera_rig.zoom = float(_args.get("shot-zoom", 18))
			camera_rig._apply_zoom()
			camera_rig.center_on(origin)
			await get_tree().create_timer(0.3).timeout
			var slot := str(_args.get("shot-slot", "attack"))
			Engine.time_scale = 0.1      # slow motion, so effects are mid-flight in the shot
			for team in 2:
				for i in rows[team].size():
					var c: Champion = rows[team][i]
					var foe: Champion = rows[1 - team][i]
					c.face_toward(foe.global_position)
					c.health = c.max_health
					if slot == "attack":
						c.perform_attack(foe)
					else:
						for s2 in Champion.SLOTS:
							c.ranks[s2] = 1
						c.spec = 100.0
						c.cooldowns[slot] = 0.0
						c.try_cast(slot, foe, foe.global_position)
			await get_tree().create_timer(float(_args.get("shot-delay", 0.15))).timeout
			Engine.time_scale = 0.0001
		"bosses":
			# TzTok-Jad, the Giant Mole and a dragon side by side.
			var origin := Vector3(-30.0, 0.0, 30.0)
			var i := 0
			for id in ["tztok_jad", "giant_mole", "chromatic_dragon", "baby_mole"]:
				var m := Monster.new()
				m.init_monster(id, GameData.unit_def("monsters", id), origin + Vector3(-9.0 + 6.0 * i, 0, 0), "shot", 12)
				units_root.add_child(m)
				m.global_position = origin + Vector3(-9.0 + 6.0 * i, 0, 0)
				m.rotation.y = 0.4
				i += 1
			camera_rig.zoom = float(_args.get("shot-zoom", 20))
			camera_rig._apply_zoom()
			camera_rig.center_on(origin)
			await get_tree().create_timer(0.4).timeout
		"scoreboard":
			hud.force_scoreboard = true
			hud.scoreboard.refresh()
		"tooltip":
			# Hover the Q slot so its damage-breakdown tooltip shows.
			var slot: Control = hud._ability_slots[str(_args.get("shot-slot", "q"))]
			get_viewport().warp_mouse(slot.get_global_rect().get_center())
			for i in 90:
				await get_tree().process_frame
			get_viewport().warp_mouse(slot.get_global_rect().get_center() + Vector2(1, 0))
			await get_tree().create_timer(1.0).timeout
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("[shot] saved %s (%dx%d) err=%d" % [_shot_path, img.get_width(), img.get_height(), err])
	get_tree().quit()


# --- Smoke test --------------------------------------------------------------

## Smoke test: flags a living bot that hasn't moved 1 m in 45 s while away
## from its fountain (stuck on terrain, a Timber! yew or a bad path).
func _probe_stuck() -> void:
	for c in champions:
		var probe: Array = _stuck_probe.get(c, [c.global_position, game_time])
		if c.is_dead or c.is_recalling() or (Unit.flat_distance(c.global_position, c.spawn_point) < 14.0 and c.health_ratio() < 0.99) \
				or Unit.flat_distance(c.global_position, probe[0]) > 1.0:
			probe = [c.global_position, game_time]
		elif game_time - float(probe[1]) > 45.0:
			_stuck_reports.append("%s stuck at %s around %.0fs (%s)" % [c.display_name, c.global_position, game_time, c.debug_state()])
			probe = [c.global_position, game_time]
		_stuck_probe[c] = probe


func _finish_smoke() -> void:
	var lines: Array[String] = []
	lines.append("[smoke] simulated %.0fs of game time" % game_time)
	lines.append("[smoke] navigation baked: %s (%d rebakes for Timber! yews, %d navmesh reloads)" % [map.is_navigation_ready, map.rebake_count, map.resubmits])
	lines.append("[smoke] waves: %d, %s" % [spawner.wave, str(_stats)])
	for c in champions:
		lines.append("[smoke] %-8s %-15s lvl %2d  ranks %s  K/D/A %d/%d/%d  CS %3d  gold %4d  items %s" % [
			Combat.TEAM_NAMES[c.team], c.display_name, c.level, _ranks_text(c), c.kills, c.deaths, c.assists,
			c.creep_score, int(c.gold), str(c.inventory)])
	var praying := 0
	for c in champions:
		if not c.active_prayers.is_empty():
			praying += 1
	lines.append("[smoke] prayer: %d altar prayers, %d of %d champions praying at the end" % [PrayerAltar.uses, praying, champions.size()])
	lines.append("[smoke] hits: %d, biggest %d (%s), %d of 256+" % [Unit.hits_dealt, int(Unit.max_hit_seen), Unit.max_hit_by, Unit.hits_over_255])
	lines.append("[smoke] OSRS models: %s" % ("on" if OsrsModels.available() else "off (whitebox)"))
	lines.append("[smoke] stuck bots: %s" % ("none" if _stuck_reports.is_empty() else "; ".join(_stuck_reports)))
	for line in lines:
		print(line)
	get_tree().quit(0 if map.is_navigation_ready and spawner.wave > 0 else 1)


func _ranks_text(c: Champion) -> String:
	return "%d%d%d%d" % [c.ranks["q"], c.ranks["w"], c.ranks["e"], c.ranks["r"]]
