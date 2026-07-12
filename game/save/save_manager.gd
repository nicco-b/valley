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
## Named playtest snapshots (the playtest desk, CREATION_KIT_REVIEW_V2 gap #2).
## Anchors are save-v2 snapshots parked in named slots — SESSION STATE, not
## content, so they live in the game's save dir beside save.json, never in
## data/. Restoring one loads that exact frozen moment (NO wall-clock replay:
## an anchor is a moment, not a resume); "scrub back" composes restore + a
## forward advance_hours, so quest latches stay monotone (§ Story) — a restore
## never un-latches, it reloads an earlier world and replays forward.
const ANCHORS_DIR := "user://anchors"
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


## Build the save-v2 snapshot dictionary — the ONE serialize door (save_game
## and save_anchor both ride it, so an anchor is byte-shaped exactly like the
## live save). Returns {} when there is no player to anchor to (title screen).
func snapshot_data() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return {}
	# Save v2 (the Threshold, PLAN_INTERIORS §3): the player payload may
	# carry an interior id + pocket-local position. Outside, it is v1's
	# {x, z} exactly; inside, {x, z} anchor at the DOOR so any reader of
	# the old shape still lands somewhere true.
	var pdata: Dictionary = {"x": player.global_position.x, "z": player.global_position.z}
	if Interiors.inside:
		pdata = Interiors.save_player(player)
	return {
		"version": 2,
		"hours": GameClock.hours,
		"day": GameClock.day,
		"wall_time": Time.get_unix_time_from_system(),
		"civil": true,  # clock anchored to real local time (1:1 era)
		"player": pdata,
		"state": _held_sourced_state(),
		"wear": InteractionField.wear_snapshot(),  # desire paths, world-anchored
		"cells": {},  # future: per-cell world-state mutations
	}


## The save-tier world state (the "state" leaf of the save doc). Normally the
## WorldState mirror verbatim — EXCEPT under the substrate Rung 3 flag
## (STRATA_CONTOUR_HELD=1), where each held SINGLETON system's OWNED keys are
## sourced from its HELD WORLD (Contour.world_snapshot, via
## contour_held_source-group members) instead of the mirror the store kept
## (docs/SUBSTRATE.md §3 — "snapshot serializes the held world directly; the
## store IS the world"). The held world is the sim-tier truth those systems
## advance IN PLACE; this makes the SAVE read from it.
##
## BYTE-IDENTICAL to the plain mirror, by construction: a SINGLETON held world is
## kept synced to WorldState every tick by the diff-only apply (WS[owned] ==
## held[owned] by induction — F2's TRUE Rung 2), so every owned key is already in
## the mirror at snapshot time and the overlay only re-sources the SAME bytes
## from their held-world origin — never appending a key, so insertion order (and
## the serialized bytes) is preserved. That equality IS the rung's acceptance,
## proven directly in tests/held_snapshot_gate.gd. Flag-OFF this is EXACTLY
## today's WorldState.snapshot(), byte-for-byte — the copy path stays the floor.
func _held_sourced_state() -> Dictionary:
	var state := WorldState.snapshot()
	# Landing-round flip: the covenant follows the EFFECTIVE posture (resolver).
	if not ContourPosture.held_enabled():
		return state
	for src in get_tree().get_nodes_in_group("contour_held_source"):
		if not src.has_method("held_owned_snapshot"):
			continue
		var owned: Dictionary = src.held_owned_snapshot()
		for k in owned:
			state[k] = owned[k]
	return state


func save_game() -> void:
	var data := snapshot_data()
	if data.is_empty():
		return
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
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		# The save covenant ladder (save_migration.gd): an older save is
		# migrated up to the format this build reads BEFORE apply_snapshot ever
		# sees it; a save from a NEWER build refuses honestly and we tell the
		# player instead of silently starting fresh (PLAN_SHIP §1.7).
		var result := SaveMigration.migrate(parsed)
		if result.ok:
			data = result.data
			if candidate != PATH:
				push_warning("[save] live save unreadable — restored %s" % candidate)
			break
		if result.refused_newer:
			push_warning("[save] %s" % result.error)
			HUD.notify(result.error)
		data = null
	if data == null:
		_spawn_fresh()
		return
	# Live load replays the wall-clock gap (the valley kept living while the
	# app was closed); an anchor restore does NOT (see apply_snapshot).
	apply_snapshot(data, true)


## Apply a save-v2 snapshot to the live world — the ONE deserialize door
## (load_into_world and restore_anchor both ride it). `replay_away` decides
## whether the wall-clock gap since the snapshot is lived forward: TRUE for a
## real load (the world ran 1:1 while away), FALSE for a playtest anchor (a
## frozen moment, restored exactly — the forward motion is the caller's own
## advance/scrub). No advance_hours fires when replay_away is false, so a
## restore never arms the determinism trap or un-latches a quest: it reloads
## an earlier WorldState wholesale, and Story re-settles forward from there.
## Returns true when a player was in the world to receive it.
func apply_snapshot(data: Dictionary, replay_away: bool) -> bool:
	GameClock.hours = data.hours
	GameClock.day = int(data.get("day", 0))
	WorldState.restore(data.get("state", {}))
	# The clock LOCK is world state too (2026-07-09). GameClock isn't a
	# world_state_reader (its _ready seeds the live clock from the wall), so
	# the restore reloads its lock explicitly — a snapshot saved while locked
	# comes back locked, and Strata's status mirror reflects the restored
	# truth. (Weather's lock rides the world_state_reader load_state below.)
	GameClock.held = bool(WorldState.get_value("time.hold", false))
	# Every system that mirrors WorldState re-reads it here — autoload
	# _ready runs before the save loads, so boot-time reads see defaults.
	get_tree().call_group("world_state_reader", "load_state")
	get_tree().call_group("npc", "load_state")
	# RESTORE-INTO-HELD (substrate Rung 3's other half — docs/SUBSTRATE.md §2). Under
	# the held flag the sim-tier truth is each SINGLETON's PERSISTENT HELD WORLD, not
	# the WorldState mirror the restore above replaced. So the load must restore the
	# save INTO those held worlds too: reset each (ContourBridge.reset_held), and the
	# next tick re-creates it via world_create seeded from the RESTORED mirror + that
	# tick's fresh reads — so every timeline resumes from the loaded snapshot, not the
	# pre-load trajectory. For a live load the advance_hours replay below drives those
	# re-creating ticks (each replayed hour hits the held path); for an anchor restore
	# (replay_away=false) there is no replay, so the held world stays absent until the
	# next natural tick and the save meanwhile sources the restored mirror (correct —
	# held_owned_snapshot returns {} with no live held world). Byte-inert with the flag
	# unset (no held world exists, so reset_held is a no-op).
	# Landing-round flip: the covenant follows the EFFECTIVE posture (resolver).
	if ContourPosture.held_enabled():
		get_tree().call_group("contour_held_source", "reset_held_world")
	InteractionField.wear_restore(data.get("wear", {}))
	# The world ran 1:1 while the app was closed — live the missed hours.
	# UNLESS the clock was LOCKED at save time: a held clock did not live the
	# away hours (the lock is a real hold, honest across an app close), so the
	# replay is skipped and the valley resumes frozen where it stood.
	var away_hours := 0.0
	if replay_away and not GameClock.held and data.has("wall_time"):
		var elapsed: float = Time.get_unix_time_from_system() - float(data.wall_time)
		away_hours = maxf(0.0, elapsed / 3600.0)
	if away_hours > 0.01:
		GameClock.advance_hours(away_hours)
	# One-time migration: saves from before the civil anchor carry an
	# arbitrary clock offset — re-anchor to real local time (the sim above
	# already lived the away hours; this only moves the dial).
	if replay_away and not data.get("civil", false):
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
	if not replay_away:
		return player != null
	print("[save] loaded (%.1f hours passed while away)" % away_hours)
	if away_hours >= 1.0:
		HUD.notify("day %d — the valley kept its own time while you were away" % GameClock.day)
	else:
		HUD.notify("journey resumed — day %d" % GameClock.day)
	return player != null


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


# --- playtest anchors (the desk's named save slots) ------------------------

## Sanitise a slot name to a filesystem-safe token: lowercase, [a-z0-9_-],
## other runs collapse to '-'. Empty (or all-punctuation) names are refused
## upstream — an anchor's name is its identity in the Strata list.
static func _slug(raw: String) -> String:
	var out := ""
	for c in raw.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			out += c
		elif out.length() > 0 and not out.ends_with("-"):
			out += "-"
	return out.trim_suffix("-")


func _anchor_path(name: String) -> String:
	return ANCHORS_DIR.path_join(name + ".json")


## Save the live world to a named anchor slot. Returns {ok, name, day, hours}
## or {ok=false, error}. Same atomic write as save_game — the slot is never
## a half-written file.
func save_anchor(raw_name: String) -> Dictionary:
	var name := _slug(raw_name)
	if name.is_empty():
		return {"ok": false, "error": "anchor name is empty after sanitising"}
	var data := snapshot_data()
	if data.is_empty():
		return {"ok": false, "error": "no player in the world to anchor"}
	DirAccess.make_dir_recursive_absolute(ANCHORS_DIR)
	var path := _anchor_path(name)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot open %s" % tmp}
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return {"ok": false, "error": "atomic rename failed (%d)" % err}
	return {"ok": true, "name": name, "day": int(data.day), "hours": float(data.hours)}


## Read one anchor slot's snapshot dict, or {} when missing/corrupt.
func _read_anchor(name: String) -> Dictionary:
	var path := _anchor_path(name)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	# Anchors ride the same covenant ladder as the live save (an anchor is a
	# byte-shaped save v2 snapshot); a newer-format or foreign file yields {}.
	var result := SaveMigration.migrate(parsed)
	if result.ok:
		return result.data
	return {}


## Restore a named anchor into the live world — the frozen moment exactly,
## no wall-clock replay (replay_away=false). Monotone by construction: the
## restore reloads an earlier WorldState and Story re-settles forward; it
## cannot un-happen a latch, only reload a world where it hadn't happened yet.
func restore_anchor(raw_name: String) -> Dictionary:
	var name := _slug(raw_name)
	var data := _read_anchor(name)
	if data.is_empty():
		return {"ok": false, "error": "no anchor '%s'" % name}
	if get_tree().get_first_node_in_group("player") == null:
		return {"ok": false, "error": "no player in the world to restore into"}
	apply_snapshot(data, false)
	HUD.notify("restored anchor '%s' — day %d, %s" % [name, GameClock.day,
		GameClock.clock_text()])
	return {"ok": true, "name": name, "day": int(data.get("day", 0)),
		"hours": float(data.get("hours", 0.0))}


## Every anchor slot with its stamped moment, sorted by absolute game-time
## (day*24 + hours) — the order the Strata scrubber walks. Corrupt/foreign
## files are skipped silently (the list is a convenience, not a contract).
func anchors_info() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(ANCHORS_DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var name := fname.trim_suffix(".json")
		var data := _read_anchor(name)
		if data.is_empty():
			continue
		var day := int(data.get("day", 0))
		var hours := float(data.get("hours", 0.0))
		out.append({"name": name, "day": day, "hours": hours,
			"abs": float(day) * 24.0 + hours})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.abs) < float(b.abs))
	return out
