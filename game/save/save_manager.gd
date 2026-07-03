extends Node
## Save system skeleton (autoload). Autosaves every 30s and on window
## close; loads on startup. Carries player position, clock time, a
## wall-clock timestamp (time is 1:1 with the real world — the valley
## keeps living while the app is closed; on load the elapsed real time is
## replayed through GameClock.advance_hours), and a versioned scaffold for
## per-cell world state (consequences live there later). Placed records
## (data/cells) are authored content, not save data — they stay separate.

const PATH := "user://save.json"
const AUTOSAVE_SECONDS := 30.0

var _accum := 0.0


func _ready() -> void:
	pass  # loading happens when the world scene's player calls load_into_world


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= AUTOSAVE_SECONDS:
		_accum = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func save_game() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var data := {
		"version": 1,
		"hours": GameClock.hours,
		"day": GameClock.day,
		"wall_time": Time.get_unix_time_from_system(),
		"civil": true,  # clock anchored to real local time (1:1 era)
		"player": {"x": player.global_position.x, "z": player.global_position.z},
		"state": WorldState.snapshot(),
		"cells": {},  # future: per-cell world-state mutations
	}
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))


## Called (deferred) by the player when the world scene starts.
func load_into_world() -> void:
	await get_tree().process_frame
	if not FileAccess.file_exists(PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data == null or data.get("version") != 1:
		return
	GameClock.hours = data.hours
	GameClock.day = int(data.get("day", 0))
	WorldState.restore(data.get("state", {}))
	get_tree().call_group("npc", "load_state")
	# The world ran 1:1 while the app was closed — live the missed hours.
	var away_hours := 0.0
	if data.has("wall_time"):
		var elapsed: float = Time.get_unix_time_from_system() - float(data.wall_time)
		away_hours = maxf(0.0, elapsed / 3600.0)
	if away_hours > 0.01:
		GameClock.advance_hours(away_hours)
	# One-time migration: saves from before the civil anchor carry an
	# arbitrary clock offset — re-anchor to real local time (the sim above
	# already lived the away hours; this only moves the dial).
	if not data.get("civil", false):
		GameClock.hours = GameClock.civil_now()
	var player := get_tree().get_first_node_in_group("player")
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if player:
		var x: float = data.player.x
		var z: float = data.player.z
		player.global_position = Vector3(x, Terrain.height(x, z) + 1.2, z)
		player.velocity = Vector3.ZERO
		if streamer:
			streamer._update_cells(true)
	print("[save] loaded (%.1f hours passed while away)" % away_hours)
	if away_hours >= 1.0:
		HUD.notify("day %d — the valley kept its own time while you were away" % GameClock.day)
	else:
		HUD.notify("journey resumed — day %d" % GameClock.day)
