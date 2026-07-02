extends Node
## Global game clock. Autoloaded as GameClock — the single source of time.
## Everything time-driven (sun, sky, schedules, ambiance) reads from here.

## Real minutes per full in-game day.
@export var day_length_minutes := 15.0

## Time of day in hours, [0, 24).
var hours := 9.0

## Days elapsed since the world began. Mirrored to WorldState "time.day".
var day := 0

## Tick bus: simulation systems subscribe at the rate they need.
signal hour_tick(hour: int)

var _last_hour := -1


func _process(delta: float) -> void:
	var advanced := hours + delta * 24.0 / (day_length_minutes * 60.0)
	if advanced >= 24.0:
		day += 1
		WorldState.set_value("time.day", day)
	hours = fmod(advanced, 24.0)
	var h := int(hours)
	if h != _last_hour:
		_last_hour = h
		hour_tick.emit(h)


## Game-hours elapsed for a real-time delta — the conversion every
## continuous simulation uses.
func hours_delta(delta: float) -> float:
	return delta * 24.0 / (day_length_minutes * 60.0)


func _unhandled_input(event: InputEvent) -> void:
	# Debug: skip forward one hour.
	if event.is_action_pressed("debug_time_skip"):
		hours = fmod(hours + 1.0, 24.0)
