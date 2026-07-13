class_name CatchmentCache
extends RefCounted
## The catchment disk cache (boot→bake, 2026-07-12 boot forensics). Every
## cold boot re-ran Hydrology._build_catchments from scratch: a 256² height
## block sampled through the kernel, a priority-flood fill, then D8 steepest
## -descent path-compressed to tag every cell's drain basin — the top
## remaining pure-compute world-gen phase on the headless boot table
## ([boot] catchments_done, ~0.8s on the home valley, scaling with the grid
## and the basin count). Its own docstring named the shape: "Pure function
## of Terrain + records: deterministic, rebuilt lazily each boot, never
## saved." This makes it saved — the FIRST build per world is written to
## disk and the next boot loads it instead of re-routing the flow.
##
## THE LAW (the BathyCache law, held identically): this cache is an
## ACCELERATOR, never a truth source. The entry is keyed on a sha256 of the
## actual build inputs — the import stamp's height sha + sea level, the
## edit-layer EXRs, the watershed record (center/domain that set the grid),
## and every water-body + river record that defines a basin — plus the grid
## resolution itself. ANY mismatch (world re-blessed, sculpt flushed, a lake
## or river record changed, the watershed moved, the blob corrupt or
## wrong-sized) refuses the load and the phase recomputes off the live
## kernel exactly as before, then rewrites. A refused load costs what boot
## always cost; a wrong load would drain a river into the wrong basin and
## move discharge — so refusal is always the tie-break. NEVER a silent stale
## serve (no-silent-fallback law).
##
## Sim-visible, unlike bathy: catchment_area feeds discharge/baseflow and
## basin_grid answers rain routing, so both are simulation inputs. The bake
## is therefore stored EXACTLY — basin_grid as raw i32 LE + deflate (the
## overrides "deflate" precedent), catchment_area/basin_names verbatim in
## the manifest — so a cache-hit boot is bit-identical to a rebuild, not
## merely equivalent. The soak fingerprint cannot move across a hit: the
## loaded basin_grid indices, basin ordering, and areas are the same bytes
## the rebuild would have produced, or the load is refused.
##
## Lives beside its siblings under data/water/: bathy/ holds the seabed
## blobs, catchments/ holds this one. get_files() over WATER_DIR is
## non-recursive, so the key-fold that walks WATER_DIR's records never sees
## this subdir's files — no self-invalidation. Delete the directory at any
## time — the only cost is one warm rebuild.

const DIR := "res://data/water/catchments"
const MANIFEST := DIR + "/catchment_cache.json"
const BLOB := "basin_grid.i32z"
const FORMAT := 1

## Every file the catchment build's inputs live in, beyond the water records
## themselves: the import stamp (blessed tile identity + sea level) and the
## hand-edit layers Terrain composes into height_block — identical to the
## bathy bake's terrain inputs, because both sample the same blessed ground.
const STAMP_PATH := "res://data/strata_import.json"
const _EDIT_SOURCES: Array[String] = [
	"res://data/terrain/tile_override.exr",
	"res://data/terrain/tile_override.json",
	"res://data/terrain/edit_layer.exr",
]
const _WATERSHED_DIR := "res://data/water/watersheds"

static var _world_key := ""  # "" = not yet computed; "off" = cache disabled
static var _dirty := false  # a live terrain edit moved the ground: stand down
static var _manifest: Dictionary = {}


## A live terrain edit (sculpt stroke, whole-frame bless) changed the ground
## the flow routes over: the session's cache is a lie from here on. Stand the
## cache down (no loads, no stores) and wipe the entries — the next clean
## boot re-keys off the flushed inputs and re-stores fresh.
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


## Try the disk for the world's catchment build: {area, grid, names} on an
## exact match, or an empty Dictionary on ANY mismatch (key, grid meta, blob
## size). `meta` is {n, center, domain, grid_m} from the live Hydrology.
static func fetch(meta: Dictionary) -> Dictionary:
	if _dirty or _key() == "off":
		return {}
	var m := _load_manifest()
	if m.is_empty():
		return {}
	if not _grid_matches(m, meta):
		return {}
	var names_v: Variant = m.get("names")
	var area_v: Variant = m.get("area")
	if not (names_v is Array and area_v is Dictionary):
		return {}
	var path := DIR + "/" + BLOB
	if not FileAccess.file_exists(path):
		return {}
	if FileAccess.get_sha256(path) != String(m.get("blob_sha256", "")):
		push_warning("[catchment_cache] blob sha mismatch — refusing, rebuilding")
		return {}
	var n: int = int(meta.n)
	var raw_size := n * n * 4
	var bytes := FileAccess.get_file_as_bytes(path) \
		.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if bytes.size() != raw_size:
		push_warning("[catchment_cache] blob size mismatch — refusing, rebuilding")
		return {}
	var names: Array[String] = []
	for v in (names_v as Array):
		names.append(String(v))
	var area: Dictionary = {}
	for k in (area_v as Dictionary):
		area[String(k)] = float((area_v as Dictionary)[k])
	return {
		"grid": bytes.to_int32_array(),
		"names": names,
		"area": area,
	}


## Persist the freshly-built catchment: the basin_grid blob (exact i32),
## catchment_area, and basin_names (the ordering the grid indices point
## into). Atomic (temp + rename); a crash mid-write leaves the old entry
## intact and the sha check refuses a torn blob.
static func store(grid: PackedInt32Array, names: Array[String],
		area: Dictionary, meta: Dictionary) -> void:
	if _dirty or _key() == "off":
		return
	var n: int = int(meta.n)
	if grid.size() != n * n:
		return  # never persist a grid that disagrees with its own resolution
	var err := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(DIR))
	if err != OK:
		return
	var blob := grid.to_byte_array().compress(FileAccess.COMPRESSION_DEFLATE)
	if not _write_atomic(DIR + "/" + BLOB, blob):
		return
	var center: Vector2 = meta.center
	_manifest = {
		"format": FORMAT,
		"world_key": _key(),
		"blob_sha256": FileAccess.get_sha256(DIR + "/" + BLOB),
		"n": n,
		"center": [center.x, center.y],
		"domain": float(meta.domain),
		"grid_m": float(meta.grid_m),
		"names": names,
		"area": area,
	}
	_write_atomic(MANIFEST,
		(JSON.stringify(_manifest, "\t", true) + "\n").to_utf8_buffer())


# --- internals ---------------------------------------------------------------


## The world key: sha256 over every input the catchment build reads. The
## import stamp carries the blessed tile's height sha (no re-hash of the EXR)
## and the sea level; the edit layers, the watershed record, and every water
## /river record hash by content; the grid resolution is folded as a literal.
## No stamp ⇒ no adopted world ⇒ cache off.
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
	ctx.update(("catchment:%d\n" % FORMAT).to_utf8_buffer())
	ctx.update((String(stamp.height_sha256) + "\n").to_utf8_buffer())
	ctx.update((str(float(stamp.get("sea_level_m", 0.0))) + "\n").to_utf8_buffer())
	ctx.update(("grid_n:%d\n" % Hydrology.GRID_N).to_utf8_buffer())
	for path in _EDIT_SOURCES:
		_fold_file(ctx, path)
	for dir_path in [_WATERSHED_DIR, Terrain.WATER_DIR, Terrain.RIVER_DIR]:
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


## The manifest, loaded once per key — and only trusted when the recorded
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


## The entry's grid meta must equal the LIVE Hydrology exactly — a watershed
## that moved its center, resized its domain, or a changed GRID_N: all refuse.
## Center/domain are record-sourced floats and grid_m = domain/n, so the JSON
## round-trip is exact; any drift fails closed into a rebuild.
static func _grid_matches(m: Dictionary, meta: Dictionary) -> bool:
	var center: Variant = m.get("center")
	if not (center is Array and (center as Array).size() == 2):
		return false
	var live_center: Vector2 = meta.center
	return int(m.get("n", -1)) == int(meta.n) \
		and float(center[0]) == live_center.x and float(center[1]) == live_center.y \
		and float(m.get("domain", 1e30)) == float(meta.domain) \
		and float(m.get("grid_m", 1e30)) == float(meta.grid_m)


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
