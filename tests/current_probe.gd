extends Node
## Current probe (dev-only, not in test.sh): boots the real valley, drops
## the player into the brook with NO input, and measures how far the
## river current carries them downstream over a few seconds — the
## end-to-end check that WaterField.current_at + the player's wading push
## actually move a body (the river-flow fallback path, so it runs
## headless without a GPU). Run:
##   godot --headless res://tests/current_probe.tscn
## Prints start/end position and drift speed toward the pond.

var _world: Node
var _player: CharacterBody3D
var _start := Vector3.ZERO
var _t := 0
var _settle := 60

func _ready() -> void:
	_world = load("res://game/world/valley.tscn").instantiate()
	add_child(_world)

func _physics_process(_d: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		return
	if _settle > 0:
		# Park the player mid-brook and let them settle onto the bed.
		_player.global_position = Vector3(63.0, Terrain.height(63.0, -256.0) + 0.6, -256.0)
		_player.velocity = Vector3.ZERO
		_settle -= 1
		if _settle == 0:
			_start = _player.global_position
		return
	_t += 1
	if _t >= 180:  # 3 s at 60 Hz
		var d := _player.global_position - _start
		var wsurf := Terrain.water_surface(_player.global_position.x, _player.global_position.z)
		var depth := wsurf - Terrain.height(_player.global_position.x, _player.global_position.z)
		print("CURRENT start=(%.1f,%.1f) end=(%.1f,%.1f) drift=%.2fm dz=%.2f speed=%.2fm/s depth=%.2f" % [
			_start.x, _start.z, _player.global_position.x, _player.global_position.z,
			d.length(), d.z, d.length() / 3.0, depth])
		get_tree().quit()
