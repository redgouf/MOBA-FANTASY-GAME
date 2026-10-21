class_name WaveSpawner
extends Node
## Sends minion waves down all three lanes for both teams.
## A wave is 3 goblins + 3 dark wizards, plus a dwarf cannon cart every few waves.

signal minion_spawned(minion: Minion)

const MELEE_WAVE: Array[String] = ["goblin", "goblin", "goblin"]
const CASTER_WAVE: Array[String] = ["dark_wizard", "dark_wizard", "dark_wizard"]

var units_root: Node3D
var wave := 0
var running := false

var _timer := 0.0
var _queue: Array[Dictionary] = []


func start(root: Node3D) -> void:
	units_root = root
	_timer = float(GameData.rule("first_wave_sec", 15))
	running = true


func stop() -> void:
	running = false
	_queue.clear()


func _physics_process(delta: float) -> void:
	if not running:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = float(GameData.rule("wave_interval_sec", 30))
		_queue_wave()
	for entry in _queue:
		entry["t"] -= delta
	while not _queue.is_empty() and _queue[0]["t"] <= 0.0:
		_spawn(_queue.pop_front())


func _queue_wave() -> void:
	wave += 1
	var ids: Array[String] = []
	ids.append_array(MELEE_WAVE)
	if wave % int(GameData.rule("siege_every", 3)) == 0:
		ids.append("cannon_cart")
	ids.append_array(CASTER_WAVE)
	for i in ids.size():
		for team in [Combat.Team.SARADOMIN, Combat.Team.ZAMORAK]:
			for lane in MapLayout.LANES:
				_queue.append({"t": i * 0.7, "id": ids[i], "team": team, "lane": lane})


func _spawn(entry: Dictionary) -> void:
	var id: String = entry["id"]
	var team: int = entry["team"]
	var lane: String = entry["lane"]
	var path := MapLayout.lane_path(lane, team)
	var m := Minion.new()
	m.init_minion(id, GameData.unit_def("minions", id), team, lane, path)
	units_root.add_child(m)
	m.global_position = MapLayout.point_along(path, 12.0) + m.offset
	minion_spawned.emit(m)
