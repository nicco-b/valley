extends Node
## Streaming hitch probe (dev-only, the Toolkit): boots the valley,
## drags the focus fast across the range cells (the Toolkit flight
## complaint), and reports real main-thread frame costs — worst frames
## and the top spikes — so streaming work is measured, not guessed at.
## Movie Maker + minimized (frame TIME is still real work time).
##   godot --path . --write-movie /tmp/x.avi --fixed-fps 15 \
##     res://tests/stream_probe.tscn

const FLY_FROM := Vector2(-1800, -2400)  # valley rim, toward the volcano
const FLY_TO := Vector2(-3400, -3500)  # across the range flank
const FLY_FRAMES := 600.0

var _t := 0
var _w: Node
var _last_usec := 0
var _spikes: Array = []  # [ms, frame]


func _ready() -> void:
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _process(_d: float) -> void:
	_t += 1
	var now := Time.get_ticks_usec()
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	if _t >= 100 and _t < 100 + int(FLY_FRAMES):
		var f := (_t - 100) / FLY_FRAMES
		var p := FLY_FROM.lerp(FLY_TO, f)
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			pl.global_position = Vector3(p.x,
				Terrain.height(p.x, p.y) + 30.0, p.y)
		var ms := (now - _last_usec) / 1000.0
		if _t > 102:
			_spikes.append([ms, _t])
	_last_usec = now
	if _t == 100 + int(FLY_FRAMES) + 30:
		_spikes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var total := 0.0
		for s in _spikes:
			total += s[0]
		print("[stream_probe] frames=%d avg=%.1fms worst10:" % [
			_spikes.size(), total / _spikes.size()])
		for i in mini(10, _spikes.size()):
			print("  %.1f ms (frame %d)" % [_spikes[i][0], _spikes[i][1]])
		get_tree().quit()
