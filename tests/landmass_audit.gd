extends SceneTree
## Dev scratch: measure usable landmass — samples the world on a 40m
## grid and buckets area by height above the sea (walkable land vs
## strand vs high ground), per island neighborhood.
func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	var sea: float = t.sea_level
	var step := 40.0
	var half := 8200.0
	var n := int(half * 2.0 / step)
	var land := 0
	var high := 0
	var strand := 0
	var cell_km2 := (step * step) / 1e6
	# Per-island tallies: name -> [center, radius, count]
	var islands := {
		"range isle": [Vector2(-3300, -3100), 2600.0, 0],
		"home+bay isle": [Vector2(500, -600), 2900.0, 0],
		"pali isle": [Vector2(4700, -1600), 1100.0, 0],
		"barren isle": [Vector2(4300, 900), 1300.0, 0],
		"terrace hill": [Vector2(5900, -400), 800.0, 0],
		"chain tail": [Vector2(6800, -2200), 1600.0, 0],
		"atoll+skerries": [Vector2(6300, 1400), 1300.0, 0],
	}
	var block: PackedFloat32Array = t.height_block(-half, -half, step, n, n)
	for iz in n:
		for ix in n:
			var h := block[iz * n + ix]
			if h <= sea:
				continue
			land += 1
			if h > sea + 2.5:
				high += 1
			else:
				strand += 1
			var p := Vector2(-half + ix * step, -half + iz * step)
			for k: String in islands:
				if p.distance_to(islands[k][0]) < float(islands[k][1]):
					islands[k][2] += 1
					break
	print("total land above sea: %.2f km2 (dry land %.2f, tidal strand %.2f)" % [
		land * cell_km2, high * cell_km2, strand * cell_km2])
	for k: String in islands:
		print("  %-16s %.2f km2" % [k, islands[k][2] * cell_km2])
	quit()
