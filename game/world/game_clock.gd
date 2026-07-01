extends Node
## Global game clock. Autoloaded as GameClock — the single source of time.
## Everything time-driven (sun, sky, schedules, ambiance) reads from here.

## Real minutes per full in-game day.
@export var day_length_minutes := 15.0

## Time of day in hours, [0, 24).
var hours := 9.0


func _process(delta: float) -> void:
	hours = fmod(hours + delta * 24.0 / (day_length_minutes * 60.0), 24.0)


func _unhandled_input(event: InputEvent) -> void:
	# Debug: skip forward one hour.
	if event.is_action_pressed("debug_time_skip"):
		hours = fmod(hours + 1.0, 24.0)
