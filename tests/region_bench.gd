extends SceneTree
## Dev scratch: height() throughput in the archipelago (worst case,
## inside the mesa bbox) vs the home valley, plus the mesa flank's
## steepest grade (cliff-verticality check).
func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	for label_center in [["valley", Vector2(70, -310)], ["mesa", Vector2(1400, -3200)]]:
		var c: Vector2 = label_center[1]
		var t0 := Time.get_ticks_usec()
		var acc := 0.0
		for i in 100000:
			acc += t.height(c.x + (i % 320) * 0.075, c.y + (i / 320) * 0.075)
		var us := Time.get_ticks_usec() - t0
		print("%s: 100k samples in %d ms (%.2f us/sample)  [acc %.1f]"
			% [label_center[0], us / 1000, us / 100000.0, acc])
	var worst := 0.0
	var prev: float = t.height(1400.0, -2570.0)
	for i in range(1, 1030):
		var h: float = t.height(1400.0, -2570.0 - i * 1.0)
		worst = maxf(worst, absf(h - prev))
		prev = h
	print("mesa flank steepest grade: %.0f%% (%.1f deg)"
		% [worst * 100.0, rad_to_deg(atan(worst))])
	quit()
