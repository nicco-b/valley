extends Node
## Clock probe (dev-only, the Toolkit): boots the valley windowed (Movie
## Maker, minimized — the sims that matter here are off headless), lets
## streaming settle, then times dev time-travel: single advance_hours
## chunks and an anchor skip, with a per-hour_tick-consumer breakdown so
## a laggy T key names its culprit instead of being guessed at.
##   godot --path . --write-movie /tmp/x.avi --fixed-fps 15 \
##     res://tests/clock_probe.tscn

var _w: Node
var _t := 0


func _ready() -> void:
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _process(_d: float) -> void:
	_t += 1
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	if _t == 500:  # streaming settled
		for round in 3:
			var t0 := Time.get_ticks_usec()
			GameClock.advance_hours(1.0)
			print("[clock_probe] 1h chunk: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
		# Per-consumer: reroute hour_tick through a timing dispatcher
		# (same call order), then advance for real — consumers no-op on
		# repeated hours, so timing manual re-calls measures nothing.
		var cbs: Array[Callable] = []
		for c in GameClock.hour_tick.get_connections():
			cbs.append(c["callable"])
		for cb in cbs:
			GameClock.hour_tick.disconnect(cb)
		GameClock.hour_tick.connect(func(h: int) -> void:
			for cb in cbs:
				var t0 := Time.get_ticks_usec()
				cb.call(h)
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				if ms > 1.0:
					print("  %s.%s: %.1f ms" % [cb.get_object(), cb.get_method(), ms]))
		print("[clock_probe] timed tick:")
		var t2 := Time.get_ticks_usec()
		GameClock.advance_hours(1.0)
		print("[clock_probe] timed 1h total: %.1f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))
	if _t == 510:
		# The region hydrology breathing: idle flow, then a forced storm.
		print("[clock_probe] hydrology idle:\n", Hydrology.summary())
		Weather.force_kind("storm")
		GameClock.advance_hours(6.0)
		print("[clock_probe] hydrology after 6 storm hours:\n", Hydrology.summary())
	if _t == 520:
		get_tree().quit()
