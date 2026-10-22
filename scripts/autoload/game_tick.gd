extends Node
## The OSRS game tick (autoload "GameTick"). Every 0.6s of game time
## (Combat.tick_seconds) one tick runs, and all gameplay happens inside ticks:
## attacks, casts, prayer, statuses, regen, respawns, bot decisions, spawns.
## Only movement, visuals and UI run per frame.
##
## Order within a tick, as on an OSRS server:
##   1. Input queued since the last tick (queue_input), in the order it came in
##   2. Actions scheduled for this tick (schedule / schedule_seconds), e.g. projectile hits
##   3. NPCs: every Unit that isn't a Champion (minions, monsters, structures, summons)
##   4. Champions (human and bot)
##   5. World tickables (register_world): wave spawner, Timber! yews, camps, passive gold
## A click made between ticks therefore takes effect on the next tick.
##
## Pauses with the tree (pause menu), like the rest of the match.

signal tick_started(tick: int)
signal tick_completed(tick: int)

## Most ticks run in one frame after a hitch; the rest are dropped, the way a
## lagging OSRS server skips ticks instead of fast-forwarding.
const MAX_CATCH_UP := 5

## The last tick processed (0 before the first).
var current_tick := 0
var processing := false

## 0..1 progress toward the next tick, for interpolating visuals.
var progress: float:
	get:
		return clampf(_accumulator / length(), 0.0, 1.0)

var _accumulator := 0.0
var _inputs: Array[Callable] = []
var _scheduled := {}            # tick -> Array[Callable]
var _world: Array = []          # objects with game_tick(dt)


static func length() -> float:
	return Combat.tick_seconds


func _physics_process(delta: float) -> void:
	advance(delta)


## Advances game time by `seconds`, running every tick that falls due.
func advance(seconds: float) -> void:
	_accumulator += seconds
	var ran := 0
	var tick_len := length()
	while _accumulator >= tick_len:
		if ran >= MAX_CATCH_UP:
			_accumulator = fmod(_accumulator, tick_len)
			break
		_accumulator -= tick_len
		run_tick()
		ran += 1


## Starts the clock over (a new match).
func reset() -> void:
	current_tick = 0
	_accumulator = 0.0
	_inputs.clear()
	_scheduled.clear()
	_world.clear()


# --- Scheduling ----------------------------------------------------------------

## A player action (click, key press). Runs at the start of the next tick.
func queue_input(action: Callable) -> void:
	_inputs.append(action)


## Runs `action` `ticks` ticks from now (at least 1: the next tick).
func schedule(ticks: int, action: Callable) -> void:
	var due := current_tick + maxi(1, ticks)
	if not _scheduled.has(due):
		_scheduled[due] = []
	_scheduled[due].append(action)


## Runs `action` on the first tick at least `seconds` from now (0 = the next tick).
func schedule_seconds(seconds: float, action: Callable) -> void:
	schedule(seconds_to_ticks(seconds), action)


## Whole ticks nearest to a short delay (0.1s -> 0, 0.3s -> 1, 0.8s -> 1).
## Used for ability wind-ups and multi-hit spacing authored in seconds.
static func nearest_ticks(seconds: float) -> int:
	return maxi(0, roundi(seconds / length()))


## Seconds of game time until the tick `ticks` from now runs (for timing visuals).
func seconds_until_tick(ticks: int) -> float:
	return maxf(0.0, float(maxi(1, ticks)) * length() - _accumulator)


## Runs `action` now if `ticks` <= 0 (we're already inside a tick), else schedules it.
func run_in(ticks: int, action: Callable) -> void:
	if ticks <= 0:
		_call(action)
	else:
		schedule(ticks, action)


## Whole ticks for a duration, rounding up (1.2s -> 2, 5s -> 9).
static func seconds_to_ticks(seconds: float) -> int:
	return maxi(1, ceili(snappedf(seconds / length(), 0.0001)))


## World objects with a game_tick(dt: float) method, ticked after every unit.
## They drop out automatically once freed.
func register_world(obj: Object) -> void:
	if not _world.has(obj):
		_world.append(obj)


func unregister_world(obj: Object) -> void:
	_world.erase(obj)


# --- The tick ------------------------------------------------------------------

func run_tick() -> void:
	current_tick += 1
	processing = true
	var dt := length()
	tick_started.emit(current_tick)

	# 1. Input. Anything queued while this tick runs waits for the next one.
	var inputs := _inputs
	_inputs = []
	for action in inputs:
		_call(action)

	# 2. Scheduled actions due now.
	var due: Array = _scheduled.get(current_tick, [])
	_scheduled.erase(current_tick)
	for action in due:
		_call(action)

	# 3-4. NPCs, then champions.
	var tree := get_tree()
	if tree != null:
		var units := tree.get_nodes_in_group("units")
		for n in units:
			if not (n is Champion):
				_tick_unit(n, dt)
		for n in units:
			if n is Champion:
				_tick_unit(n, dt)

	# 5. World.
	for obj in _world.duplicate():
		if is_instance_valid(obj):
			obj.game_tick(dt)
		else:
			_world.erase(obj)

	processing = false
	tick_completed.emit(current_tick)


func _tick_unit(n: Node, dt: float) -> void:
	var u := n as Unit
	# Units frozen with set_physics_process(false) (screenshot demos) stay frozen.
	if u != null and is_instance_valid(u) and u.is_inside_tree() and u.is_physics_processing():
		u.game_tick(dt)


func _call(action: Callable) -> void:
	if action.is_valid():
		action.call()
