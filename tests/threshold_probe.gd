extends Node
## Threshold probe (dev-only, not in test.sh): boots the real valley,
## places a doored record against the ground, crosses it, and STANDS in
## the smugglers' cellar — real physics on the kit floor, +1500m over the
## door — then forces a storm outside to watch the presentation gates
## hold, crosses back, and proves the world is exactly as left (height()
## bit-identical, the storm still rightly raining, the clock never
## paused). Screenshots when a rendering driver exists (the light-leak
## probe: the sealed room at full afternoon sun):
##   godot --rendering-driver opengl3 res://tests/threshold_probe.tscn
## Writes /tmp/threshold_*.png; quits nonzero on any failed check.

const OUT := "/tmp/threshold"
const DOOR_X := 33.0
const DOOR_Z := -80.0

var _failures := 0
var _world: Node
var _cam: Camera3D


func _ready() -> void:
	_world = load("res://game/world/valley.tscn").instantiate()
	add_child(_world)
	_run.call_deferred()


func _check(condition: bool, name: String) -> void:
	if condition:
		print("  ok: ", name)
	else:
		_failures += 1
		print("  THRESHOLD FAIL: ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _frames(2)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	FocusThrottle.queue_free()
	# The probe drives the player itself; the autosave must not write
	# probe state over the human's save while we're at it.
	SaveGame.set_process(false)
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player")
	await _frames(10)  # let the real save land first, then take the wheel
	GameClock.hours = 15.0
	Weather.force_kind("calm")
	player.global_position = Vector3(30.0, Terrain.height(30.0, -80.0) + 1.0, -80.0)
	player.velocity = Vector3.ZERO
	await _frames(90)  # dense ring builds under the new spot

	# The door: an ordinary placement row that learned one key.
	var dpos := Vector3(DOOR_X, Terrain.height(DOOR_X, DOOR_Z), DOOR_Z)
	var cell: Vector2i = CellRecords.cell_of(dpos)
	var pre_count: int = CellRecords.records(cell).size()
	var rec: Dictionary = CellRecords.add(dpos,
		"res://assets/models/arch/village/door_01.glb", PI * 0.5, 1.0)
	CellRecords.update(cell, String(rec["id"]),
		{"door": {"interior": "smugglers_cellar"}})
	await _frames(10)  # the records container rebuilds, the door grows its verb
	var door_it: Interactable = null
	var exit_it: Interactable = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Interactable and (n as Interactable).prompt == "Enter":
			door_it = n
	_check(door_it != null, "the doored record grew its Enter interactable")

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.global_position = dpos + Vector3(-3.0, 2.0, 3.0)
	_cam.look_at(dpos + Vector3(0.0, 1.0, 0.0))
	_cam.make_current()
	await _frames(5)
	_shot("door")

	# The world's truth before the crossing.
	var h0: float = Terrain.height(DOOR_X, DOOR_Z)
	var hours0: float = GameClock.hours
	var wet0: float = Climate.wetness
	if door_it == null:
		_finish(cell, pre_count)
		return

	# Cross. The interact wiring is the whole point — no direct enter().
	door_it.interact(player)
	var waited := 0
	while (not Interiors.inside or Interiors._busy) and waited < 600:
		waited += 1
		await get_tree().process_frame
	_check(Interiors.inside, "the crossing lands (enter)")
	await _frames(45)  # fall the 0.9m onto the kit floor
	_check(player.global_position.y > Interiors.POCKET_ALT - 10.0,
		"the pocket hovers at altitude (y=%.0f)" % player.global_position.y)
	_check(player.is_on_floor(),
		"the player STANDS on interior placements (is_on_floor)")
	_check(not player._submerged, "no false water at +1500m (swim gate clear)")
	var def: Dictionary = Interiors.definition("smugglers_cellar")
	var resolvable := 0
	for row: Dictionary in def.get("placements", []):
		if Kit.scene_for(str(row.get("kit", ""))) != null:
			resolvable += 1
	_check(is_instance_valid(Interiors._pocket)
		and Interiors._pocket.get_child_count() == resolvable + 1,
		"interior placements exist (%d rows + the lamp)" % resolvable)
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Interactable and (n as Interactable).prompt == "Leave":
			exit_it = n
	_check(exit_it != null, "the exit-door row grew its Leave interactable")

	# The storm outside: the SIM rages on, the gates keep it presentation-
	# outside — dust off, atmosphere hidden, fog stood down, sky its hour.
	Weather.force_kind("storm")
	await _frames(10)
	_check(Weather.state == "storm", "the weather SIM was never told (it storms)")
	_check(not (_world.get_node("Dust") as GPUParticles3D).emitting,
		"weather FX gate: dust holds its breath inside")
	_check(not (_world.get_node("Atmosphere") as Node3D).visible,
		"atmosphere gate: rain/curtains/bolts hidden inside")
	var env: Environment = (_world.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(env.fog_density == 0.0 and not env.volumetric_fog_enabled,
		"sky gate: the room is never fog-flooded or storm-washed")
	var sun := _world.get_node("Sun") as DirectionalLight3D
	_check((sun.light_cull_mask & Interiors.POCKET_LAYER_BIT) == 0,
		"the sun's cull mask dropped the pocket layer (light-leak answer)")
	var on_layer := 0
	for mi: MeshInstance3D in Interiors._pocket.find_children(
			"*", "MeshInstance3D", true, false):
		if mi.layers == Interiors.POCKET_LAYER_BIT:
			on_layer += 1
	_check(on_layer > 0, "pocket meshes render on the interior layer (%d)" % on_layer)

	# The light-leak probe: full afternoon sun outside, a sealed room —
	# the shots answer whether enclosure alone holds the sun out (the
	# cull-layer fallback stays in the plan's pocket if it doesn't).
	var center: Vector3 = Interiors._pocket.position + Vector3(0.0, 1.2, 0.0)
	_cam.global_position = Interiors._pocket.position + Vector3(2.2, 1.7, 4.4)
	_cam.look_at(center)
	await _frames(5)
	_shot("inside")
	_cam.global_position = center + Vector3(-3.4, 0.4, -3.2)
	_cam.look_at(center + Vector3(2.0, 1.6, 2.0))
	await _frames(5)
	_shot("inside_far")

	# Cross back: the world is exactly as left — just later.
	if exit_it != null:
		exit_it.interact(player)
	waited = 0
	while (Interiors.inside or Interiors._busy) and waited < 600:
		waited += 1
		await get_tree().process_frame
	_check(not Interiors.inside, "the crossing home lands (exit)")
	_check(Interiors._pocket == null, "the pocket is freed on exit")
	_check(Vector2(player.global_position.x - DOOR_X,
		player.global_position.z - DOOR_Z).length() < 3.0,
		"exit stands the player at the door")
	_check(Terrain.height(DOOR_X, DOOR_Z) == h0,
		"height() is bit-identical — the pocket never touched terrain")
	_check(Weather.state == "storm",
		"it was rightly raining the whole time (the sim never forked)")
	_check((( _world.get_node("Sun") as DirectionalLight3D).light_cull_mask
		& Interiors.POCKET_LAYER_BIT) != 0,
		"the sun's cull mask is restored on exit")
	_check(GameClock.hours > hours0,
		"the 1:1 clock never paused (%.4fh -> %.4fh)" % [hours0, GameClock.hours])
	_check(is_finite(wet0) and Climate.wetness >= wet0 - 0.001,
		"climate kept its own counsel (wetness %.3f -> %.3f)" % [wet0, Climate.wetness])
	_cam.global_position = dpos + Vector3(-4.0, 2.4, 4.0)
	_cam.look_at(dpos + Vector3(0.0, 1.0, 0.0))
	await _frames(10)
	_shot("outside_again")
	_finish(cell, pre_count)


## Leave no trace (the door record and, if we created it, the cell file),
## then report.
func _finish(cell: Vector2i, pre_count: int) -> void:
	while CellRecords.records(cell).size() > pre_count:
		CellRecords.remove_last(cell)
	if pre_count == 0:
		var path := "%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures > 0:
		print("THRESHOLD PROBE FAIL: %d check(s) failed" % _failures)
	else:
		print("THRESHOLD PROBE PASS")
	get_tree().quit(1 if _failures > 0 else 0)


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return  # asserts still run; the pictures need a driver
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [OUT, label])
	print("[probe] wrote %s_%s.png" % [OUT, label])
