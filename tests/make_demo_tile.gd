extends SceneTree
## Dev tool: generates the demo painted tile (a crescent atoll) that
## proves the F3 tile pipeline. Stand-in for her actual painted
## heightmaps — same file format, same record, same slot.
## Run: godot --headless --path . -s res://tests/make_demo_tile.gd
const RES := 512


func _init() -> void:
	var img := Image.create(RES, RES, false, Image.FORMAT_RF)
	var c := Vector2(RES / 2.0, RES / 2.0)
	for py in RES:
		for px in RES:
			var p := Vector2(px, py) - c
			var r := p.length()
			var ang := atan2(p.y, p.x)
			# Crescent rim: a gaussian ring, breached toward the west.
			var opening := smoothstep(2.4, 1.6, absf(ang - PI) if ang > 0 \
				else absf(ang + PI))
			opening = 1.0 - opening
			var wobble := sin(ang * 3.0 + 1.3) * 14.0 + sin(ang * 7.0) * 6.0
			var ring := exp(-pow((r - 175.0 + wobble) / 30.0, 2.0))
			var rim_h := ring * (0.62 + 0.38 * sin(ang * 5.0 + 0.7) * 0.5 + 0.19) \
				* opening
			# Lagoon: shallow bowl inside the rim, just under sea level.
			var lagoon := 0.49 * smoothstep(165.0, 120.0, r)
			var v := maxf(maxf(rim_h, lagoon), 0.0)
			img.set_pixel(px, py, Color(v, 0, 0))
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://data/terrain/tiles"))
	img.save_exr(ProjectSettings.globalize_path(
		"res://data/terrain/tiles/demo_atoll.exr"))
	print("TILE WRITTEN data/terrain/tiles/demo_atoll.exr")
	quit()
