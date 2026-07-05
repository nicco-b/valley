extends SceneTree
## Dev scratch (headless, NO window): renders a hillshade overview map
## of the archipelago draft straight from Terrain.height, and prints
## the rim→mesa horizon profile (the landmark-law check) as numbers.
## Run: godot --headless --path . -s res://tests/region_map.gd
const HALF := 6000.0  # meters from origin to map edge (12km square)
const RES := 720


func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()

	# Landmark law: angular elevation along the rim→mesa sightline.
	var cam := Vector3(440.0, t.height(440.0, -660.0) + 14.0, -660.0)
	var dir := (Vector2(1200, -3000) - Vector2(cam.x, cam.z)).normalized()
	var best := -90.0
	var best_at := 0.0
	var dune_best := -90.0
	for i in range(2, 320):
		var d := i * 10.0
		var p := Vector2(cam.x, cam.z) + dir * d
		var ang := rad_to_deg(atan((t.height(p.x, p.y) - cam.y) / d))
		if d < 2000.0 and ang > dune_best:
			dune_best = ang
		if ang > best:
			best = ang
			best_at = d
	print("rim sightline: peak %.2f deg at %.0fm (dune band max %.2f deg)"
		% [best, best_at, dune_best])
	print("mesa clears the near horizon by %.2f deg" % (best - dune_best))

	# Hillshade overview.
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	var step := HALF * 2.0 / RES
	var light := Vector3(-0.5, 0.8, -0.33).normalized()
	for py in RES:
		for px in RES:
			var x := -HALF + px * step
			var z := -HALF + py * step
			var h: float = t.height(x, z)
			var hx: float = t.height(x + step, z)
			var hz: float = t.height(x, z + step)
			var n := Vector3(h - hx, step, h - hz).normalized()
			var shade := clampf(n.dot(light), 0.0, 1.0)
			var tint := clampf(h / 400.0, 0.0, 1.0)
			var c := Color(0.25 + 0.6 * shade, 0.2 + 0.5 * shade,
				0.15 + 0.4 * shade).lerp(Color(1.0, 0.95, 0.85), tint * 0.5)
			if t.water_surface_base(x, z) > h:
				c = Color(0.3, 0.5, 0.7)
			img.set_pixel(px, py, c)
	img.save_png("/tmp/region_map.png")
	print("MAP WRITTEN /tmp/region_map.png")
	quit()
