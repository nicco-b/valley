extends SceneTree
## Map pipeline stage B: derive a believable STARTING biome map from the
## terrain — height, slope, and distance-to-water rules paint each pixel
## with the nearest palette ink (biomes.json). Output is a colored,
## paintable image (data/world/biome_map.png): repaint any region and
## the game hot-reloads the ground palette + flora density. This is the
## seed you edit, not the final word.
## Run: godot --headless --path . -s res://tests/derive_biomes.gd
const RES := 1024
const HALF := 8192.0


func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	var pal: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/world/biomes.json"))
	var inks: Array = []
	for b in pal["biomes"]:
		var c: Array = b["ink"]
		inks.append(Color(c[0], c[1], c[2]))
	# palette order: 0 deep_sea 1 strand 2 dune 3 scrub 4 oasis 5 wetland
	#                6 volcanic_rock 7 bare_peak
	var sea: float = t.sea_level
	var step := HALF * 2.0 / RES
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	# One height block + neighbor blocks would be ideal; sample per-pixel
	# with a small offset for slope (cold path, runs once).
	var hb: PackedFloat32Array = t.height_block(-HALF, -HALF, step, RES, RES)
	for pz in RES:
		for px in RES:
			var wx := -HALF + px * step
			var wz := -HALF + pz * step
			var h := hb[pz * RES + px]
			var idx := 3  # scrub default
			if h <= sea:
				idx = 0
			elif h < sea + 2.5:
				idx = 1  # strand
			else:
				# slope from the block neighbors
				var hx := hb[pz * RES + mini(px + 1, RES - 1)]
				var hz := hb[mini(pz + 1, RES - 1) * RES + px]
				var slope := (absf(h - hx) + absf(h - hz)) / step
				var wet: float = t.moisture_static(wx, wz)  # water-proximity, no sim
				if h > 520.0:
					idx = 7  # bare peak
				elif slope > 0.7 and h > 120.0:
					idx = 6  # volcanic rock on steep upland
				elif wet > 0.55 and h < sea + 8.0:
					idx = 5  # wetland: wet + low
				elif wet > 0.4:
					idx = 4  # oasis green near water
				elif h < 30.0:
					idx = 2  # low dry lowland = dune desert
				else:
					idx = 3  # scrub
			img.set_pixel(px, pz, inks[idx])
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://data/world"))
	img.save_png(ProjectSettings.globalize_path("res://data/world/biome_map.png"))
	print("BIOME MAP WRITTEN data/world/biome_map.png (%dpx)" % RES)
	quit()
