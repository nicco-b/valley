extends Node
## Global game clock. Autoloaded as GameClock — the single source of time.
## Everything time-driven (sun, sky, schedules, ambiance) reads from here.
##
## Time is 1:1 with the real world (DECISIONS 2026-07-02, the ambient
## machine): a game day lasts a real day. The clock is driven by wall-clock
## deltas, not frame deltas, so fps throttling and App Nap can't drift it.
## Skipped stretches — laptop sleep, app closed (via SaveGame) — are
## replayed through advance_hours(), which steps the whole simulation in
## hour chunks, never one giant leap.

## Real minutes per full in-game day. 1440 = 1:1 with the real world.
@export var day_length_minutes := 1440.0

## Time of day in hours, [0, 24).
var hours := 9.0

## Days elapsed since the world began. Mirrored to WorldState "time.day".
var day := 0

## Time flows faster while deep sitters sit (Stillness skill). A live-play
## effect only — catch-up after sleep/close always runs 1:1.
var time_scale := 1.0

## Tick bus: simulation systems subscribe at the rate they need.
signal hour_tick(hour: int)

## Wall-clock gaps beyond this many seconds (laptop sleep, suspend, a long
## pause) are replayed as chunked catch-up instead of one smooth delta.
const GAP_SECONDS := 10.0

var _last_hour := -1
var _last_unix := 0.0


func _process(_delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	if _last_unix == 0.0:
		_last_unix = now
	var wall_delta := maxf(0.0, now - _last_unix)  # clock set backwards: hold
	_last_unix = now
	if wall_delta > GAP_SECONDS:
		advance_hours(wall_delta / 3600.0)  # 1:1 — the machine slept, the valley didn't
	else:
		_advance(hours_delta(wall_delta))


## Game-hours elapsed for a real-time delta — the conversion every
## continuous simulation uses.
func hours_delta(delta: float) -> float:
	return delta * time_scale * 24.0 / (day_length_minutes * 60.0)


## Advance the whole simulation by N game-hours in ≤1h chunks — the one
## shared path for every skipped stretch of time (load catch-up, laptop
## sleep, debug skip). Each chunk moves the clock (hour_tick fires: weather
## rolls transitions, NPCs snapshot state) and then steps every member of
## the "sim_advance" group, so agents live the skipped hours instead of
## waking up stale.
func advance_hours(total: float) -> void:
	while total > 0.0:
		var chunk := minf(total, 1.0)
		total -= chunk
		_advance(chunk)
		get_tree().call_group("sim_advance", "sim_advance_hours", chunk)


func _advance(dh: float) -> void:
	var advanced := hours + dh
	if advanced >= 24.0:
		day += 1
		WorldState.set_value("time.day", day)
	hours = fmod(advanced, 24.0)
	var h := int(hours)
	if h != _last_hour:
		_last_hour = h
		hour_tick.emit(h)


func _unhandled_input(event: InputEvent) -> void:
	# Debug: skip forward one hour — through the shared path, so weather
	# and NPCs live the skipped hour instead of ignoring it.
	if event.is_action_pressed("debug_time_skip"):
		advance_hours(1.0)
