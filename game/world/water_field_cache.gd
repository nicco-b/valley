class_name WaterFieldCache
extends RefCounted
## The tier-2 water-field BASE disk cache (adopt-time hydrology rebuild,
## 2026-07-13 — the BathyCache shape, held exactly). WaterField's first base
## bake samples a 1024² height_block + water_base_block through the kernel
## on a worker at every boot and every adopt — a pure function of the
## blessed terrain, the edit layers, and the water records, at a
## deterministic spawn-snapped anchor. The bless-time prebake run (Prebake)
## computes it headless ONCE and this class persists it; the next boot (and
## the in-session adopt, once the player stands where the window anchors)
## loads instead of re-sampling.
##
## THE LAW (BathyCache's, verbatim in spirit): this cache is an ACCELERATOR,
## never a truth source. The entry is keyed on a sha256 of the actual bake
## inputs — the import stamp's height sha + sea level, the edit-layer EXRs,
## and every water/river record (water_base_block reads them all) — plus the
## window geometry (GRID, WINDOW) and the exact anchor center. ANY mismatch
## refuses the load and the field bakes off the live kernel exactly as
## before. Only the fill_channels=OFF base is ever cached (the debug A/B's
## source/prefill fields are session-transient by design).
##
## Presentation-side only: the field is "never saved, never fingerprinted"
## (water_field.gd's own law) — but the blobs are still stored EXACTLY
## (raw f32 LE, deflate), so a cache-hit base is bit-identical to a rebake,
## provable byte-for-byte, never merely close.
##
## Lives beside its siblings: data/water/bathy/ (seabed), catchments/
## (routing), field/ (this). get_files() over WATER_DIR is non-recursive,
## so the key-fold never sees this subdir — no self-invalidation. Delete
## the directory at any time — the only cost is one warm rebake.

const DIR := "res://data/water/field"
const MANIFEST := DIR + "/field_cache.json"
const HEIGHTS_BLOB := "base_heights.f32z"
const SINKS_BLOB := "base_sinks.f32z"
const FORMAT := 1

const STAMP_PATH := "res://data/strata_import.json"
const _EDIT_SOURCES: Array[String] = [
	"res://data/terrain/tile_override.exr",
	"res://data/terrain/tile_override.json",
	"res://data/terrain/edit_layer.exr",
]

static var _world_key := ""  # "" = not yet computed; "off" = cache disabled
static var _dirty := false  # a live terrain edit moved the ground: stand down
static var _manifest: Dictionary = {}


## A live terrain edit changed the ground under the window: stand the cache
## down (no loads, no stores) and wipe — the next clean boot re-keys fresh.
static func mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_wipe()


## A whole-water reload (reload_world / import) rewrote the records on disk:
## recompute the key from the fresh state on next use. Old entries refuse
## against the new key naturally.
static func invalidate_key() -> void:
	_world_key = ""
	_manifest = {}


## Try the disk for the base bake at this exact anchor: {heights, sinks} on
## a full match, {} on ANY mismatch (key, grid, center, sha, size).
static func fetch(center: Vector2, grid: int, window: float) -> Dictionary:
	if _dirty or _key() == "off":
		return {}
	var m := _load_manifest()
	if m.is_empty():
		return {}
	if not _grid_matches(m, center, grid, window):
		return {}
	var heights := _read_blob(HEIGHTS_BLOB, String(m.get("heights_sha256", "")), grid)
	if heights.is_empty():
		return {}
	var sinks := _read_blob(SINKS_BLOB, String(m.get("sinks_sha256", "")), grid)
	if sinks.is_empty():
		return {}
	return {"heights": heights, "sinks": sinks}


## Persist the freshly-baked base (fill_channels OFF only — the caller
## gates). Atomic (temp + rename); a torn write refuses on its own sha.
static func store(center: Vector2, grid: int, window: float,
		heights: PackedFloat32Array, sinks: PackedFloat32Array) -> void:
	if _dirty or _key() == "off":
		return
	if heights.size() != grid * grid or sinks.size() != grid * grid:
		return  # never persist buffers that disagree with their own grid
	var err := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(DIR))
	if err != OK:
		return
	if not _write_atomic(DIR + "/" + HEIGHTS_BLOB,
			heights.to_byte_array().compress(FileAccess.COMPRESSION_DEFLATE)):
		return
	if not _write_atomic(DIR + "/" + SINKS_BLOB,
			sinks.to_byte_array().compress(FileAccess.COMPRESSION_DEFLATE)):
		return
	_manifest = {
		"format": FORMAT,
		"world_key": _key(),
		"heights_sha256": FileAccess.get_sha256(DIR + "/" + HEIGHTS_BLOB),
		"sinks_sha256": FileAccess.get_sha256(DIR + "/" + SINKS_BLOB),
		"center": [center.x, center.y],
		"grid": grid,
		"window": window,
	}
	_write_atomic(MANIFEST,
		(JSON.stringify(_manifest, "\t", true) + "\n").to_utf8_buffer())


# --- internals ---------------------------------------------------------------


## The world key: sha256 over every input the base bake reads. The import
## stamp carries the blessed tile's height sha + the sea level; the edit
## layers and every water/river record hash by content (water_base_block
## answers off all of them). No stamp ⇒ no adopted world ⇒ cache off.
static func _key() -> String:
	if _world_key != "":
		return _world_key
	if not FileAccess.file_exists(STAMP_PATH):
		_world_key = "off"
		return _world_key
	var stamp: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAMP_PATH))
	if not (stamp is Dictionary and stamp.has("height_sha256")):
		_world_key = "off"
		return _world_key
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("field:%d\n" % FORMAT).to_utf8_buffer())
	ctx.update((String(stamp.height_sha256) + "\n").to_utf8_buffer())
	ctx.update((str(float(stamp.get("sea_level_m", 0.0))) + "\n").to_utf8_buffer())
	for path in _EDIT_SOURCES:
		_fold_file(ctx, path)
	for dir_path in [Terrain.WATER_DIR, Terrain.RIVER_DIR]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var files := dir.get_files()
		files.sort()
		for f in files:
			if f.ends_with(".json"):
				_fold_file(ctx, dir_path + "/" + f)
	_world_key = ctx.finish().hex_encode()
	return _world_key


static func _fold_file(ctx: HashingContext, path: String) -> void:
	if FileAccess.file_exists(path):
		ctx.update((path + ":" + FileAccess.get_sha256(path) + "\n").to_utf8_buffer())
	else:
		ctx.update((path + ":absent\n").to_utf8_buffer())


## The manifest, loaded once per key — trusted only when the recorded
## world_key matches the live one exactly.
static func _load_manifest() -> Dictionary:
	if not _manifest.is_empty():
		return _manifest
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary and int(parsed.get("format", -1)) == FORMAT \
			and String(parsed.get("world_key", "")) == _key():
		_manifest = parsed
		return _manifest
	return {}


## The entry's window must equal the LIVE one exactly — a moved anchor, a
## changed GRID or WINDOW: all refuse. Centers are ANCHOR_SNAP-snapped
## floats, so the JSON round-trip is exact; drift fails closed to a rebake.
static func _grid_matches(m: Dictionary, center: Vector2, grid: int, window: float) -> bool:
	var c: Variant = m.get("center")
	if not (c is Array and (c as Array).size() == 2):
		return false
	return float(c[0]) == center.x and float(c[1]) == center.y \
		and int(m.get("grid", -1)) == grid \
		and float(m.get("window", -1.0)) == window


## One blob off disk: sha-verified, size-verified, or empty (refuse).
static func _read_blob(fname: String, want_sha: String, grid: int) -> PackedFloat32Array:
	var none := PackedFloat32Array()
	var path := DIR + "/" + fname
	if not FileAccess.file_exists(path):
		return none
	if FileAccess.get_sha256(path) != want_sha:
		push_warning("[water_field_cache] %s: blob sha mismatch — refusing, rebaking" % fname)
		return none
	var raw_size := grid * grid * 4
	var bytes := FileAccess.get_file_as_bytes(path) \
		.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if bytes.size() != raw_size:
		push_warning("[water_field_cache] %s: blob size mismatch — refusing, rebaking" % fname)
		return none
	return bytes.to_float32_array()


static func _write_atomic(path: String, bytes: PackedByteArray) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	var wrote := f.store_buffer(bytes)
	f.close()
	if not wrote:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path)) == OK


static func _wipe() -> void:
	_manifest = {}
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
