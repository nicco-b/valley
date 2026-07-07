class_name WorldBake
extends RefCounted
## The Loom / the Toolkit — the paint→bake step as ONE reusable path. The
## headless CLI (tests/bake_world.gd) and the in-game map painter both bake
## through here, so the terrain you sculpt on the live map is bit-for-bit
## the terrain the offline bake makes. Loads the normalized elevation
## guide, runs the kernel's fractal relief + thermal talus + hydraulic
## droplet erosion, and writes the baked tile (the gitignored cache
## HotReload swaps live) plus its F3 region record.

const GUIDE_EXR := "res://data/world/elevation_guide.exr"
const GUIDE_JSON := "res://data/world/guide.json"
const TILE_EXR := "res://data/terrain/tiles/baked_world.exr"
const TILE_REC := "res://data/regions/baked_world.json"


## The bake settings (origin, world_size, out_res, meter range, erosion
## params) — the guide's companion JSON.
static func meta() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GUIDE_JSON))


## The guide as a paintable normalized 0..1 grayscale image (FORMAT_RF).
static func load_guide() -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(GUIDE_EXR))
	img.convert(Image.FORMAT_RF)
	return img


## World XZ → guide texel (float; caller clamps/rounds). The guide covers
## the whole world frame from `origin` spanning `world_size`.
static func world_to_texel(x: float, z: float, m: Dictionary, res: int) -> Vector2:
	var org: Dictionary = m["origin"]
	var s := float(m["world_size"])
	return Vector2((x - float(org["x"])) / s * res, (z - float(org["z"])) / s * res)


## Run the bake: the normalized guide + a TerrainKernel → the baked
## heightfield as a FORMAT_RF Image (out_res², meters). Pure — no disk.
## The guide's 0..1 gamma-curve is inverted back to meters here (the same
## mapping derive_guide.gd stored), then handed to the native erosion.
static func bake(guide_img: Image, m: Dictionary, kernel: Object) -> Image:
	var gmin := float(m.get("guide_min", -60.0))
	var gspan := float(m.get("guide_max", 1000.0)) - gmin
	var inv_gamma := 1.0 / float(m.get("guide_gamma", 1.0))
	var guide := guide_img.get_data().to_float32_array()
	for i in guide.size():
		guide[i] = gmin + pow(clampf(guide[i], 0.0, 1.0), inv_gamma) * gspan
	var result: Dictionary = kernel.bake_terrain(
		guide, guide_img.get_width(), float(m["world_size"]),
		int(m["out_res"]), int(m["seed"]), m["params"])
	var res := int(m["out_res"])
	var baked: PackedFloat32Array = result["height"]
	# Pack the float buffer straight into the image (FORMAT_RF is native
	# little-endian float32, row-major — same layout as the array), a
	# beat faster than 4.2M set_pixel calls at 2048².
	return Image.create_from_data(res, res, false, Image.FORMAT_RF,
		baked.to_byte_array())


## Persist the painted guide back to its source EXR (the guide is the
## source of truth; it is committed, unlike the baked cache).
static func save_guide(guide_img: Image) -> void:
	guide_img.save_exr(ProjectSettings.globalize_path(GUIDE_EXR), true)


## Raise (or lower) the guide within a world-space disc, linear falloff
## to the rim, clamped to the paintable 0..1 range — the ONE brush both
## pens share (map top-down and flyover ground-painting).
static func paint_disc(guide_img: Image, m: Dictionary, world_xz: Vector2,
		radius_m: float, amount: float) -> void:
	var res := guide_img.get_width()
	var c := world_to_texel(world_xz.x, world_xz.y, m, res)
	var rad := radius_m / float(m["world_size"]) * res
	if rad < 0.5:
		return
	for pz in range(maxi(0, int(c.y - rad)), mini(res, int(c.y + rad) + 1)):
		for px in range(maxi(0, int(c.x - rad)), mini(res, int(c.x + rad) + 1)):
			var d := Vector2(px + 0.5, pz + 0.5).distance_to(c)
			if d > rad:
				continue
			var v := guide_img.get_pixel(px, pz).r + amount * (1.0 - d / rad)
			guide_img.set_pixel(px, pz, Color(clampf(v, 0.0, 1.0), 0.0, 0.0))


## Write the baked heightfield to the tiles cache + its region record.
## HotReload watches the tiles dir and calls Terrain.reload_tile, so the
## live world reshapes within a second of this landing.
static func write_tile(baked: Image, m: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		"res://data/terrain/tiles"))
	baked.save_exr(ProjectSettings.globalize_path(TILE_EXR))
	var rec := {"id": "baked_world", "layer": "surface", "kind": "tile",
		"origin": m["origin"], "size": m["world_size"], "feather": 600,
		"heightmap": TILE_EXR, "height_min": 0.0, "height_max": 1.0}
	var f := FileAccess.open(TILE_REC, FileAccess.WRITE)
	f.store_string(JSON.stringify(rec, "\t") + "\n")
	f.close()
