extends Node
## Save system skeleton (autoload). Autosaves every 30s and on window
## close; loads on startup. Carries player position, clock time, a
## wall-clock timestamp (time is 1:1 with the real world — the valley
## keeps living while the app is closed; on load the elapsed real time is
## replayed through GameClock.advance_hours), and a versioned scaffold for
## per-cell world state (consequences live there later). Placed records
## (data/cells) are authored content, not save data — they stay separate.
## Save v2 (the Threshold): player may carry an interior id + pocket-local
## position; restore routes through Interiors, falling back to the door.

const PATH := "user://save.json"
const AUTOSAVE_SECONDS := 30.0
# Keep two generations behind the live file, refreshed at most every
# BACKUP_MINUTES so the 30s autosave can't churn both backups into
# copies of the same bad minute.
const BACKUP_MINUTES := 10.0

var _last_backup_unix := 0.0

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
	# Save v2 (the Threshold, PLAN_INTERIORS §3): the player payload may
	# carry an interior id + pocket-local position. Outside, it is v1's
	# {x, z} exactly; inside, {x, z} anchor at the DOOR so any reader of
	# the old shape still lands somewhere true.
	var pdata: Dictionary = {"x": player.global_position.x, "z": player.global_position.z}
	if Interiors.inside:
		pdata = Interiors.save_player(player)
	var data := {
		"version": 2,
		"hours": GameClock.hours,
		"day": GameClock.day,
		"wall_time": Time.get_unix_time_from_system(),
		"civil": true,  # clock anchored to real local time (1:1 era)
		"player": pdata,
		"state": WorldState.snapshot(),
		"wear": InteractionField.wear_snapshot(),  # desire paths, world-anchored
		"cells": {},  # future: per-cell world-state mutations
	}
	# Atomic write: never truncate the only copy of months of world
	# time. Write beside, fsync, then rename over — a crash mid-write
	# leaves the previous save intact.
	var tmp := PATH + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("[save] cannot open %s for writing" % tmp)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	_rotate_backups()
	var err := DirAccess.rename_absolute(tmp, PATH)
	if err != OK:
		push_warning("[save] atomic rename failed (%d)" % err)



func _rotate_backups() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var now := Time.get_unix_time_from_system()
	if now - _last_backup_unix < BACKUP_MINUTES * 60.0:
		return
	_last_backup_unix = now
	if FileAccess.file_exists(PATH + ".bak1"):
		DirAccess.copy_absolute(PATH + ".bak1", PATH + ".bak2")
	DirAccess.copy_absolute(PATH, PATH + ".bak1")


## Called (deferred) by the player when the world scene starts.
func load_into_world() -> void:
	await get_tree().process_frame
	var data = null
	# Live file first, then the rotated backups — a torn or corrupt
	# save falls back to a slightly older world, never to nothing.
	for candidate in [PATH, PATH + ".bak1", PATH + ".bak2"]:
		if not FileAccess.file_exists(candidate):
			continue
		data = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		# v1 saves (pre-interiors) load unchanged — v2 only ADDS optional
		# player.interior fields; nothing was moved or renamed.
		if data != null and int(data.get("version", 0)) in [1, 2]:
			if candidate != PATH:
				push_warning("[save] live save unreadable — restored %s" % candidate)
			break
		data = null
	if data == null:
		_spawn_fresh()
		return
	GameClock.hours = data.hours
	GameClock.day = int(data.get("day", 0))
	WorldState.restore(data.get("state", {}))
	# Every system that mirrors WorldState re-reads it here — autoload
	# _ready runs before the save loads, so boot-time reads see defaults.
	get_tree().call_group("world_state_reader", "load_state")
	get_tree().call_group("npc", "load_state")
	InteractionField.wear_restore(data.get("wear", {}))
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
		# Saved inside a pocket interior (save v2): restore routes through
		# the Threshold — rebuild the pocket over the door and stand the
		# player where they stood. The seat above is already the DOOR (the
		# v2 anchor), so a gone interior record falls back there, honestly.
		var pd: Dictionary = data.player
		if pd.has("interior"):
			var seated: bool = Interiors.restore(String(pd.interior),
				Vector3(x, Terrain.height(x, z), z), float(pd.get("door_yaw", 0.0)),
				Vector3(float(pd.get("ix", 0.0)), float(pd.get("iy", 0.5)),
					float(pd.get("iz", 0.0))), player)
			if not seated:
				HUD.notify("the %s is gone — you wake at its door" % String(pd.interior))
	print("[save] loaded (%.1f hours passed while away)" % away_hours)
	if away_hours >= 1.0:
		HUD.notify("day %d — the valley kept its own time while you were away" % GameClock.day)
	else:
		HUD.notify("journey resumed — day %d" % GameClock.day)


## A fresh journey (no save on disk yet): begin at the world's recorded
## landing spot instead of the scene's authored Player transform. An
## imported Strata world has no reason to honour that transform — the
## importer picks a dry spot on the largest island and records it
## (Terrain.recorded_spawn(), off data/world/spawn.json), and the walker
## starts there, force-streaming the cell so it stands on real collision.
## No recorded spawn (content-empty, the authored home valley, a pre-spawn
## tile) leaves the authored transform exactly as it was — today's
## behaviour, byte for byte.
func _spawn_fresh() -> void:
	var sp: Variant = Terrain.recorded_spawn()
	if not (sp is Vector2):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p: Vector2 = sp
	player.global_position = Vector3(p.x, Terrain.height(p.x, p.y) + 1.2, p.y)
	player.velocity = Vector3.ZERO
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		streamer._update_cells(true)
	print("[save] new journey — landed at (%.0f, %.0f)" % [p.x, p.y])
