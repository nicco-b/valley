extends SceneTree
## Kernel parity gate (headless): the native TerrainKernel must track
## the GDScript reference within float tolerance — a porting-bug
## detector, not a bit-equality check. Bit-parity with the engine's
## GDScript path is impossible (the official binary's fma association
## in Vector2 math is compiler-specific); the determinism contract is
## that the kernel is bit-stable WITH ITSELF and every worker-path
## consumer reads the kernel (see native/CMakeLists.txt).
## Tolerances: 1e-4 on the home watershed grid, 1e-3 across the world
## (region noise amplifies ulps on the mesas).
## Run: godot --headless --path . -s res://tests/kernel_parity.gd
func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	if t.kernel == null:
		print("PARITY SKIP: no native kernel on this platform")
		quit()
		return
	# Home watershed grid (what the Hydrology fingerprint hangs off).
	var ws: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/water/watersheds/home.json"))
	var c := Vector2(float(ws.center.x), float(ws.center.z))
	var size := float(ws.size)
	var n := 256
	var gm := size / n
	var block: PackedFloat32Array = t.kernel.height_block(
		c.x - size * 0.5, c.y - size * 0.5, gm, n, n)
	var worst := 0.0
	for iz in n:
		for ix in n:
			var ref := float(t.height(c.x - size * 0.5 + ix * gm,
				c.y - size * 0.5 + iz * gm))
			worst = maxf(worst, absf(block[iz * n + ix] - ref))
	print("watershed grid worst |diff|: %.9f m" % worst)
	var ok := worst < 1e-4
	# Wide world: coarse sweep across the whole archipelago.
	var wn := 128
	var wstep := 12000.0 / wn
	var wblock: PackedFloat32Array = t.kernel.height_block(
		-6000.0, -6000.0, wstep, wn, wn)
	var wworst := 0.0
	for iz in wn:
		for ix in wn:
			var ref := float(t.height(-6000.0 + ix * wstep, -6000.0 + iz * wstep))
			wworst = maxf(wworst, absf(wblock[iz * wn + ix] - ref))
	print("world sweep worst |diff|: %.9f m" % wworst)
	ok = ok and wworst < 1e-3
	# Water surfaces: pond, brook, sea, dry ground.
	for s in [Vector2(70, -310), Vector2(30, -160), Vector2(900, -2000),
			Vector2(120, -620)]:
		var a := float(t.kernel.water_surface_base(s.x, s.y))
		var b := float(t.water_surface_base(s.x, s.y))
		if absf(a - b) > 1e-4 and not (a < -1e11 and b < -1e11):
			ok = false
			print("  water mismatch at ", s, ": ", a, " vs ", b)
	print("PARITY PASS" if ok else "PARITY FAIL")
	quit()
