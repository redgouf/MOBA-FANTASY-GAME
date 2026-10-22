class_name WaveSpawner
extends Node
## Sends minion waves down all three lanes, on the League of Legends
## Summoner's Rift schedule:
## - first wave at 0:30; a wave every 30 s, every 25 s from 14:00, every 20 s from 30:00
## - each wave: 3 melee, (siege), 3 casters; minions spawn 0.792 s apart
## - siege minion on the 3rd wave, then every 3rd wave until 14:00, every 2nd
##   until 25:00, every wave after; from 14:00 a siege wave has one fewer melee
## - casters drop to 2 per wave from 30:00
## - while an enemy altar (inhibitor) is down, that lane gets a super minion
##   (Knight) instead of the siege; with all three down, 2 Knights per lane
## - minions "upgrade" at 0:30 and every 90 s after, raising their stats

signal minion_spawned(minion: Minion)

var units_root: Node3D
var wave := 0
var running := false
## Callable(team: int, lane: String) -> bool : is this team's altar in that lane destroyed?
var altar_down: Callable

var _timer := 0.0
var _queue: Array[Dictionary] = []
var _waves_since_siege := 0


func start(root: Node3D) -> void:
	units_root = root
	_timer = float(GameData.rule("first_wave_sec", 30))
	running = true


func stop() -> void:
	running = false
	_queue.clear()


static func upgrades_at(t: float) -> int:
	var first := float(GameData.rule("first_wave_sec", 30))
	if t < first:
		return 0
	return 1 + int(floor((t - first) / float(GameData.rule("minion_upgrade_interval_sec", 90))))


static func wave_interval_at(t: float) -> float:
	if t >= 1800.0:
		return 20.0
	if t >= 840.0:
		return 25.0
	return float(GameData.rule("wave_interval_sec", 30))


static func siege_every_at(t: float) -> int:
	if t >= 1500.0:
		return 1
	if t >= 840.0:
		return 2
	return 3


func _ready() -> void:
	GameTick.register_world(self)


## Waves come due and minions spawn on game ticks.
func game_tick(delta: float) -> void:
	if not running:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer += wave_interval_at(Combat.clock)
		_queue_wave(Combat.clock)
	for entry in _queue:
		entry["t"] -= delta
	while not _queue.is_empty() and _queue[0]["t"] <= 0.0:
		_spawn(_queue.pop_front())


## Composition of one lane's wave for a team, in spawn order.
func wave_composition(t: float, team: int, lane: String, siege_wave: bool) -> Array[String]:
	var supers := 0
	if altar_down.is_valid():
		var enemy := 1 - team
		var all_down := true
		for l in MapLayout.LANES:
			if not altar_down.call(enemy, l):
				all_down = false
		if all_down:
			supers = 2
		elif altar_down.call(enemy, lane):
			supers = 1
	var ids: Array[String] = []
	var melee := 3
	if siege_wave and supers == 0 and t >= 840.0:
		melee -= 1
	for i in melee:
		ids.append("goblin")
	if supers > 0:
		for i in supers:
			ids.append("knight")
	elif siege_wave:
		ids.append("cannon_cart")
	for i in (2 if t >= 1800.0 else 3):
		ids.append("dark_wizard")
	return ids


func _queue_wave(t: float) -> void:
	wave += 1
	_waves_since_siege += 1
	var siege_wave := wave >= 3 and _waves_since_siege >= siege_every_at(t)
	if siege_wave:
		_waves_since_siege = 0
	var upgrades := upgrades_at(t)
	var spacing := float(GameData.rule("minion_spawn_spacing_sec", 0.792))
	for team in [Combat.Team.SARADOMIN, Combat.Team.ZAMORAK]:
		for lane in MapLayout.LANES:
			var ids := wave_composition(t, team, lane, siege_wave)
			for i in ids.size():
				_queue.append({"t": i * spacing, "id": ids[i], "team": team, "lane": lane, "upgrades": upgrades})
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])


func _spawn(entry: Dictionary) -> void:
	var id: String = entry["id"]
	var team: int = entry["team"]
	var lane: String = entry["lane"]
	var path := MapLayout.lane_path(lane, team)
	var m := Minion.new()
	m.init_minion(id, GameData.unit_def("minions", id), team, lane, path, int(entry["upgrades"]))
	units_root.add_child(m)
	m.global_position = MapLayout.point_along(path, 12.0) + m.offset
	minion_spawned.emit(m)
