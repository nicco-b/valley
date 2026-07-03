class_name PathCursor
extends RefCounted
## Walks a Nav path one waypoint at a time, repathing when the goal moves
## or the route grows stale. Presentation-tier only — data agents move as
## straight math; a body owns one cursor and asks it where to step next.

const REPATH_SECONDS := 3.0
const WAYPOINT_REACHED := 1.6
const GOAL_MOVED := 2.0

var _path := PackedVector3Array()
var _index := 0
var _goal := Vector3.INF
var _accum := 99.0  # forces a path on the first ask


## The point to walk toward right now, given where we stand and where
## the mind wants to end up.
func waypoint(delta: float, from: Vector3, goal: Vector3) -> Vector3:
	_accum += delta
	if _accum >= REPATH_SECONDS or _goal.distance_to(goal) > GOAL_MOVED:
		_accum = 0.0
		_goal = goal
		_path = Nav.path(from, goal)
		_index = 0
	while _index < _path.size() - 1 and Vector2(
			_path[_index].x - from.x, _path[_index].z - from.z).length() < WAYPOINT_REACHED:
		_index += 1
	return _path[_index] if _index < _path.size() else goal
