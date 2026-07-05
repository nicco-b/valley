extends Node
## Walk probe (dev-only, not in test.sh): boots the real valley and
## walks the player spawn->pond along the brook at ~2x sprint, measuring
## main-thread frame times — the harness that catches streaming/worker
## stutter regressions numerically. Run:
##   godot --headless res://tests/walk_probe.tscn
## Prints median/p95/p99/max and the count of >33ms spikes. Compare
## against a known-good commit when investigating hitches (2026-07-04
## baseline 3a8955b: median ~7ms, ~5 spikes over the 320m walk, plus
## pre-existing threaded-sampler script errors — tracked as follow-up).
var _world: Node
var _player: CharacterBody3D
var _frames := 0
var _last_us := 0
var _deltas: Array[float] = []
func _ready() -> void:
	_world = load("res://game/world/valley.tscn").instantiate()
	add_child(_world)
func _process(_d: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
		GameClock.time_scale = 0.0
		Weather.force_kind("calm")
		_last_us = Time.get_ticks_usec()
		return
	var now := Time.get_ticks_usec()
	_deltas.append((now - _last_us) / 1000.0)
	_last_us = now
	_frames += 1
	# Walk at ~2x sprint along the valley toward the pond, near the brook.
	var t := _frames * 0.15
	_player.global_position = Vector3(
		40.0 + 25.0 * (t / 320.0), 0.0, -t)
	_player.global_position.y = Terrain.height(
		_player.global_position.x, _player.global_position.z) + 1.0
	if t >= 320.0:
		_deltas.sort()
		var n := _deltas.size()
		var spikes := 0
		for d in _deltas:
			if d > 33.0:
				spikes += 1
		print("WALK frames=%d median=%.1fms p95=%.1fms p99=%.1fms max=%.1fms spikes>33ms=%d"
			% [n, _deltas[n / 2], _deltas[int(n * 0.95)], _deltas[int(n * 0.99)],
			_deltas[n - 1], spikes])
		get_tree().quit()
