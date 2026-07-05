extends Node
## Fall probe (dev-only): reproduces the mesa-descent crash (2026-07-04,
## SIGSEGV 0x70 on a worker thread while falling down the mountain into
## the sea). Boots the valley headless, parks the player on the mesa
## summit, then drags the focus down the flank and out over the water at
## fall speed — maximum cell/navmesh/sand churn. Clean exit prints
## FALL PROBE CLEAN; a crash speaks for itself.
## Run: godot --headless --path . res://tests/fall_probe.tscn
var _t := 0
var _player: CharacterBody3D
var _w: Node


func _ready() -> void:
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _strip(keep: PackedStringArray) -> void:
	## BISECT helper: free every direct child of the world except `keep`
	## and the player (the streamer needs a focus).
	for child in _w.get_children():
		var n := String(child.name)
		if n in keep or child.is_in_group("player"):
			continue
		child.queue_free()
	print("[fall_probe] stripped to ", keep)


func _process(_d: float) -> void:
	_t += 1
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		return
	if _t == 10:
		GameClock.time_scale = 0.0
		Weather.state = "storm"  # rain feeds the water field too
		var keep := OS.get_environment("FALL_KEEP")
		if keep != "":
			_strip(keep.split(","))
		if OS.get_environment("FALL_NO_PHYSICS") != "":
			_player.process_mode = Node.PROCESS_MODE_DISABLED
			print("[fall_probe] player physics disabled")
	if _t >= 20 and _t < 620:
		# Three summit->sea passes (~50m/s): descent churn, repeated.
		var f := fmod((_t - 20) / 200.0, 1.0)
		var x := lerpf(1200.0, 400.0, f)
		var z := lerpf(-3000.0, -2100.0, f)
		var ground: float = Terrain.height(x, z)
		_player.global_position = Vector3(x, maxf(ground + 1.5, -1.5), z)
	if _t == 660:
		print("FALL PROBE CLEAN")
		get_tree().quit()
