extends Node
## The Threshold (autoload; PLAN_INTERIORS §3) — doors, interior pockets,
## and the records that furnish them. Part of the Chronicle's content
## layer: a door is an ordinary placement row that learned one key
## (`"door": {"interior": "<id>"}`), and interacting with it instantiates
## `data/interiors/<id>.json` as a POCKET in the same running world,
## hovering POCKET_ALT above the door's own XZ, crossed through a fade —
## no scene change, no load screen. Every autoload keeps ticking (the sim
## is never told), streaming stays warm at the door's cell (the focus XZ
## never moves), and the 1:1 clock holds: sit in a cellar an hour, come
## out to a later sky.
##
## Interior placements are the CellRecords row shape VERBATIM ({id, kit,
## x, y, z, yaw, scale} — stable ids and all), with two deliberate
## differences: coordinates are local to the pocket origin, and `y` is
## absolute — no ground_dy, no seat_y, because there is no terrain to
## seat on; the interior's own floor pieces are the ground. The exit is
## a door row INSIDE the record with `"door": {"exit": true}` — the same
## mechanism pointing home.
##
## `inside` is the ONE presentation flag. Readers: weather FX (dust/rain
## particles off), ambience (wind bed ducked), day_night (fog stands
## down) — the map's chart-exemption precedent, extended. The Weather
## SIM never hears about any of this: it is still rightly raining when
## you step back out. Nothing here touches height(), hydrology, climate,
## or WorldState canon — interiors are structurally unable to move the
## soak fingerprint.

## The player crossed a threshold (true = now inside). Presentation
## readers poll `inside`; this is for probes and one-shot listeners.
signal crossed(now_inside: bool)

const DIR := "res://data/interiors"
## Pocket altitude above the door's XZ: above any tile's height_max,
## above the ranges' 320m, above every water surface — the player swim
## gate (y < water_surface + 0.2) clears itself, no special case.
const POCKET_ALT := 1500.0
## Fell-out-of-the-world guard: a pocket has edges, and a fall from
## +1500m must end at the door, not in the terrain 1.5km below.
const FALL_MARGIN := 80.0
## The sun stays outside (PLAN_INTERIORS §3: enclosure + cull layer —
## the I1 light-leak probe SHOWED leakage through kit seams, so the cull
## layer ships): pocket meshes render on this VisualInstance3D layer
## alone, and the Sun's light_cull_mask drops the bit while a pocket
## stands. The interior's own lamp lights every layer, so the room keeps
## its `light` header and loses only the storm-slit sun shafts.
const POCKET_LAYER_BIT := 1 << 10  # render layer 11

## The fade is the whole ceremony (PLAN_INTERIORS §7). Tests shrink this
## so a crossing costs frames, not wall-clock.
var fade_seconds := 0.35

var inside := false
var interior_id := ""
## The exterior door's world position and yaw — the exit's landing spot
## and the save's honest {x, z} anchor while inside.
var door_position := Vector3.ZERO
var door_yaw := 0.0

var _pocket: Node3D = null
var _spawn_local := Vector3.ZERO  # exit-door row, pocket-local
var _spawn_yaw := 0.0
var _busy := false  # a crossing in flight; interact spam waits
var _fade_rect: ColorRect


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 80  # above the underwater veil (50), below nothing that matters
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	layer.add_child(_fade_rect)
	add_child(layer)
	# The hand edits the interior's book (InteriorRecords) while inside; a
	# changed book re-dresses the live pocket so the room the player sees IS
	# the records on disk (PLAN_INTERIORS §4, the I2 done-means).
	InteriorRecords.changed.connect(_on_book_changed)


func _physics_process(_delta: float) -> void:
	# The guard rail: walked off the pocket's edge → arrive at the door,
	# honestly, instead of falling 1.5km onto the terrain below.
	if not inside or _busy:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D and (player as Node3D).global_position.y < POCKET_ALT - FALL_MARGIN:
		exit(player)


## The interior record for an id: {id, name, light, ambience, placements},
## or {} when the file is missing/malformed (callers stay honest about it).
func definition(id: String) -> Dictionary:
	var path := "%s/%s.json" % [DIR, id]
	if not FileAccess.file_exists(path):
		return {}  # callers say so where a human can hear (enter's notify)
	var parsed: Variant = Records.load_json(path)
	if not (parsed is Dictionary):
		return {}
	if not Records.validate(parsed, {
		"id": TYPE_STRING, "placements": TYPE_ARRAY,
	}, path):
		return {}
	return parsed


## Every interior id on disk (the Toolkit line; I2's book list).
func interior_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out


## The streamer calls this for any placed record carrying a `door` key:
## the record stays ordinary, the key grows the Interactable (F1.3 layer).
## Exit-door rows ({"exit": true}) mean nothing on the surface — they are
## the pocket host's business.
func attach_door(node: Node3D, rec: Dictionary) -> void:
	var door: Dictionary = rec.get("door", {})
	var id := String(door.get("interior", ""))
	if id.is_empty():
		return
	var it := Interactable.new()
	it.prompt = "Enter"
	it.position = Vector3(0.0, 1.0, 0.0)  # chest height on the door piece
	it.interacted.connect(func(by: Node) -> void:
		enter(id, node.global_position, node.rotation.y, by))
	node.add_child(it)


## Cross the threshold: fade out, build the pocket at the door's XZ at
## altitude, stand the player at the exit door inside, fade in. The sim
## is never paused, never told.
func enter(id: String, door_pos: Vector3, yaw: float, by: Node) -> void:
	if _busy or inside:
		return
	var def := definition(id)
	if def.is_empty():
		HUD.notify("the door leads nowhere — no interior record '%s'" % id)
		return
	_busy = true
	await _fade_to(1.0)
	door_position = door_pos
	door_yaw = yaw
	_build_pocket(def, id, Vector3(door_pos.x, POCKET_ALT, door_pos.z))
	inside = true
	interior_id = id
	_place(by, _pocket.position + _spawn_local
		+ Vector3(sin(_spawn_yaw), 0.0, cos(_spawn_yaw)) * 1.1
		+ Vector3(0.0, 0.9, 0.0))
	crossed.emit(true)
	await _fade_to(0.0)
	_busy = false


## Cross back: fade out, free the pocket, stand the player at the door.
## The world outside was never suspended — it is simply later.
func exit(by: Node) -> void:
	if _busy or not inside:
		return
	_busy = true
	await _fade_to(1.0)
	_free_pocket()
	_place(by, door_position
		+ Vector3(sin(door_yaw), 0.0, cos(door_yaw)) * 1.2
		+ Vector3(0.0, 0.4, 0.0))
	crossed.emit(false)
	await _fade_to(0.0)
	_busy = false


## The save's player payload while inside (SaveGame, save v2): the door's
## {x, z} stays the world anchor — a loader that has never heard of
## interiors still seats you somewhere true — plus the interior id and
## the pocket-local position for the ones that have.
func save_player(player: Node3D) -> Dictionary:
	var local := player.global_position - _pocket.position
	return {
		"x": door_position.x, "z": door_position.z,
		"interior": interior_id, "door_yaw": door_yaw,
		"ix": local.x, "iy": local.y, "iz": local.z,
	}


## Save-restore routing (SaveGame): rebuild the pocket over the door and
## seat the player at the saved local position — no fade, the load IS
## the ceremony. Returns false when the interior record is gone (the
## caller already seated the player at the door: the honest fallback).
func restore(id: String, door_pos: Vector3, yaw: float, local_pos: Vector3,
		player: Node3D) -> bool:
	if inside:
		return false
	var def := definition(id)
	if def.is_empty():
		return false
	door_position = door_pos
	door_yaw = yaw
	_build_pocket(def, id, Vector3(door_pos.x, POCKET_ALT, door_pos.z))
	inside = true
	interior_id = id
	_place(player, _pocket.position + local_pos)
	crossed.emit(true)
	return true


## Toolkit world-panel line.
func summary() -> String:
	var stock := "%d interior(s) on disk" % interior_ids().size()
	if not inside:
		return "outside · " + stock
	return "inside %s · door (%.0f, %.0f) · %s" % [
		interior_id, door_position.x, door_position.z, stock]


func _place(by: Node, pos: Vector3) -> void:
	if by is Node3D:
		(by as Node3D).global_position = pos
	if by is CharacterBody3D:
		(by as CharacterBody3D).velocity = Vector3.ZERO


## Stand a fresh pocket at `origin` and point the interior book (I2's
## InteriorRecords) at it — the book becomes the pocket's live truth, in
## WORLD coordinates (local + origin), so the Toolkit's world-space hand
## edits it in place. Then dress the room from the book. `def` carries the
## header (light/ambience) the book does not own.
func _build_pocket(def: Dictionary, id: String, origin: Vector3) -> void:
	_free_pocket()
	_pocket = Node3D.new()
	_pocket.name = "InteriorPocket"
	_pocket.position = origin
	add_child(_pocket)
	InteriorRecords.focus(id, origin)  # the book now speaks this pocket
	_populate_pocket(def)
	_gate_sun(true)


## (Re)dress the live pocket from the interior book. Called on build and on
## every book `changed` (the hand placed / moved / deleted a piece), so the
## room the player stands in always mirrors the records. Rows are
## CellRecords-shaped in WORLD coords; kit resolves through the same Kit
## door the streamer uses; y is absolute-local, seated by subtracting the
## pocket origin (no terrain, no seat_y).
func _populate_pocket(def: Dictionary) -> void:
	if _pocket == null or not is_instance_valid(_pocket):
		return
	for child in _pocket.get_children():
		child.queue_free()
	_spawn_local = Vector3(0.0, 0.5, 0.0)  # fallback: pocket origin
	_spawn_yaw = 0.0
	for rec: Dictionary in InteriorRecords.active_rows():
		var scene: PackedScene = Kit.scene_for(str(rec.get("kit", "")))
		if scene == null:
			continue
		var node: Node3D = scene.instantiate()
		_dress(node)
		_pocket.add_child(node)
		node.position = Vector3(float(rec.get("x", 0.0)),
			float(rec.get("y", 0.0)), float(rec.get("z", 0.0))) - _pocket.position
		node.rotation.y = float(rec.get("yaw", 0.0))
		node.scale = Vector3.ONE * float(rec.get("scale", 1.0))
		var door: Dictionary = rec.get("door", {})
		if bool(door.get("exit", false)):
			# The way home: same mechanism as the surface door.
			_spawn_local = node.position
			_spawn_yaw = node.rotation.y
			var it := Interactable.new()
			it.prompt = "Leave"
			it.position = Vector3(0.0, 1.0, 0.0)
			it.interacted.connect(func(by: Node) -> void: exit(by))
			node.add_child(it)
	# Minimal I1 light: one warm lamp from the `light` header so the room
	# reads at all — I3 builds the real rig (and the ambience bed).
	var lamp := OmniLight3D.new()
	lamp.position = _spawn_local + Vector3(0.0, 1.8, 0.0)
	lamp.omni_range = 14.0
	lamp.light_energy = 1.6
	lamp.light_color = Color(1.0, 0.82, 0.6) \
		if str(def.get("light", "dark_warm")) == "dark_warm" else Color(0.85, 0.9, 1.0)
	lamp.shadow_enabled = true
	_pocket.add_child(lamp)
	# Every pocket mesh moves to the interior render layer; the sun's
	# cull mask drops it below. Cameras see all layers by default.
	for mi: MeshInstance3D in _pocket.find_children("*", "MeshInstance3D", true, false):
		mi.layers = POCKET_LAYER_BIT


## The interior book changed under the hand — re-dress the live pocket so
## the room follows the records (only when this IS the standing pocket).
func _on_book_changed(id: String) -> void:
	if not inside or _busy or id != interior_id:
		return
	if _pocket == null or not is_instance_valid(_pocket):
		return
	_populate_pocket(definition(id))


func _free_pocket() -> void:
	# Persist any pending book edits before the pocket goes (a nudge stream
	# that never reached the stroke-quiet flush must not vanish at the door).
	InteriorRecords.flush()
	if _pocket != null and is_instance_valid(_pocket):
		_pocket.queue_free()
	_pocket = null
	inside = false
	interior_id = ""
	_gate_sun(false)


## Drop (or restore) the pocket layer in every directional light's cull
## mask — the sun and any sibling sky light stay outside the walls.
func _gate_sun(gated: bool) -> void:
	for sun: DirectionalLight3D in get_tree().root.find_children(
			"*", "DirectionalLight3D", true, false):
		if gated:
			sun.light_cull_mask &= ~POCKET_LAYER_BIT
		else:
			sun.light_cull_mask |= POCKET_LAYER_BIT


## Placeholder-synth dressing, the streamer's recipe (vertex colors on,
## `-col` hulls hidden). No fabric-wind pass: there is no wind indoors.
func _dress(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name.ends_with("-col"):
			mi.visible = false
			continue
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat is StandardMaterial3D and not mat.vertex_color_use_as_albedo:
				mat.vertex_color_use_as_albedo = true


## Fade the crossing veil to `alpha` and wait for it — the whole
## transition ceremony (PLAN_INTERIORS §7: no load screens, no scene swaps).
func _fade_to(alpha: float) -> void:
	_fade_rect.visible = true
	if fade_seconds > 0.0:
		var tw := create_tween()
		tw.tween_property(_fade_rect, "color:a", alpha, fade_seconds)
		await tw.finished
	_fade_rect.color.a = alpha
	_fade_rect.visible = alpha > 0.001
