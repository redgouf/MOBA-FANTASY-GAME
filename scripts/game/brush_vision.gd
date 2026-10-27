class_name BrushVision
extends RefCounted
## League's brush rule: a champion or minion standing in a patch of brush
## can't be seen by the other team, unless one of their units stands in the
## same patch, or the unit has just attacked (it is revealed for a moment).
## Structures and neutral monsters aren't hidden, and monsters see everyone.

const REVEAL_SEC := 1.0

static var _frame := -1
static var _present: Array[Dictionary] = [{}, {}, {}]   # team -> {brush patch: true}


## Can `viewer_team` see `target`, as far as brush goes? (Sight range and
## walls are the fog of war's business.)
static func can_see(viewer_team: int, target: Unit) -> bool:
	if viewer_team == target.team or viewer_team == Combat.Team.NEUTRAL or target.team == Combat.Team.NEUTRAL:
		return true
	if target.is_structure():
		return true
	var patch := MapLayout.brush_patch(target.global_position)
	if patch < 0:
		return true
	if target.is_revealed():
		return true
	_refresh(target)
	return _present[viewer_team].has(patch)


## Which patches each team has a unit standing in, recomputed once a physics frame.
static func _refresh(any_unit: Unit) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _frame:
		return
	_frame = frame
	_present = [{}, {}, {}]
	for n in any_unit.get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead or u.is_structure() or u.team == Combat.Team.NEUTRAL:
			continue
		var patch := MapLayout.brush_patch(u.global_position)
		if patch >= 0:
			(_present[u.team] as Dictionary)[patch] = true
