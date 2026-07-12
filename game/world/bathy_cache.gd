class_name BathyCache
extends RefCounted
## The bathymetry disk cache (boot-attack #2, 2026-07 forensics). Every
## cold boot re-baked the sea tiers' and every lake's seabed CUSTOM0
## (depth + ∇depth per vertex) from scratch through the kernel — up to
## ~2 min of the slow-boot cluster on big worlds, scaling with catchment
## count. The buffers are pure functions of the blessed terrain, the edit
## layers, the water records, and the tier's own grid — so the FIRST bake
## of each tier per world is written to disk and the next boot loads it
## instead of re-sampling the seabed.
##
## THE LAW: this cache is an ACCELERATOR, never a truth source. Every
## entry is keyed on a sha256 of the actual bake inputs — the import
## stamp's height sha + sea level, the edit-layer EXRs, and every
## data/water record — plus the tier's exact grid (anchor, dims, step,
## offsets, level). ANY mismatch (world re-blessed, sculpt flushed, lake
## record changed, tier registered differently, blob corrupt) refuses the
## load and the tier re-bakes off the live kernel exactly as before. A
## refused load costs what boot always cost; a wrong load would break the
## surf on a reef that is not there — so refusal is always the tie-break.
##
## Presentation-side only: the buffers feed the water shader's shoaling
## (CUSTOM0); nothing simulated reads them (Hydrology/soak never touch
## _bathy), so the cache is fingerprint-neutral. The blobs are still
## stored EXACTLY (raw f32 LE, deflate — the overrides "deflate_f32le"
## precedent), so a cache-hit boot is bit-identical to a rebuild, not
## merely visually equivalent — provable byte-for-byte.
##
## Lives beside its siblings: data/water/ holds the hyd_*.json import
## caches; the bathy blobs are the same regenerable-cache class and sit
## in data/water/bathy/. Delete the directory at any time — the only
## cost is one warm rebake.

const DIR := "res://data/water/bathy"
const MANIFEST := DIR + "/bathy_cache.json"
const FORMAT := 1

## Every file the seabed bake's inputs live in, beyond data/water/ itself:
## the import stamp (blessed tile identity + sea level) and the hand-edit
## layers Terrain composes into height_block. Absent files hash as absent —
## a layer APPEARING is an input change like any other.
const STAMP_PATH := "res://data/strata_import.json"
const _EDIT_SOURCES: Array[String] = [
	"res://data/terrain/tile_override.exr",
	"res://data/terrain/tile_override.json",
	"res://data/terrain/edit_layer.exr",
]

static var _world_key := ""  # "" = not yet computed; "off" = cache disabled
static var _dirty := false  # a live terrain edit moved the ground: stand down
static var _manifest: Dictionary = {}


## A live terrain edit (sculpt stroke, whole-frame bless) changed the seabed
## out from under the boot-time key: the session's cache is a lie from here
## on. Stand the cache down (no loads, no stores) and wipe the entries — the
## next clean boot re-keys off the flushed inputs and re-stores fresh.
static func mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_wipe()


## A whole-water reload (reload_world / import) rewrote the records on disk:
## recompute the key from the fresh state on next use. Old entries refuse
## against the new key naturally; a bless mid-session also dirties via
## Terrain.edited, so this alone never resurrects a stale entry.
static func invalidate_key() -> void:
	_world_key = ""
	_manifest = {}


## Try the disk for one tier's first bake: the exact CUSTOM0 buffer, or an
## empty array on ANY mismatch (key, grid, anchor, sha, size). `st` is the
## _bathy tier state from water_bodies (nx/nz/step/ox/oz/level).
static func fetch(tier: String, goal: Vector2, st: Dictionary) -> PackedFloat32Array:
	var none := PackedFloat32Array()
	if _dirty or _key() == "off":
		return none
	var entry: Dictionary = _entries().get(tier, {})
	if entry.is_empty():
		return none
	if not _grid_matches(entry, goal, st):
		return none
	var path: String = DIR + "/" + String(entry.get("file", ""))
	if not FileAccess.file_exists(path):
		return none
	if FileAccess.get_sha256(path) != String(entry.get("sha256", "")):
		push_warning("[bathy_cache] %s: blob sha mismatch — refusing, rebaking" % tier)
		return none
	var raw_size: int = int(st.nx) * int(st.nz) * 3 * 4
	var bytes := FileAccess.get_file_as_bytes(path) \
		.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if bytes.size() != raw_size:
		push_warning("[bathy_cache] %s: blob size mismatch — refusing, rebaking" % tier)
		return none
	return bytes.to_float32_array()


## Persist one tier's freshly-landed FIRST bake (water_bodies stores only
## the boot bake per tier — the sea tiers' later follow rebakes are player
## -position-transient and never touch disk). Atomic (temp + rename, the
## overrides pattern); a crash mid-write leaves the old entry intact and
## the sha check refuses a torn blob.
static func store(tier: String, st: Dictionary) -> void:
	if _dirty or _key() == "off":
		return
	var out: PackedFloat32Array = st.out
	if out.size() != int(st.nx) * int(st.nz) * 3:
		return  # never persist a buffer that disagrees with its own grid
	var err := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(DIR))
	if err != OK:
		return
	var fname := _slug(tier) + ".f32z"
	var blob := out.to_byte_array().compress(FileAccess.COMPRESSION_DEFLATE)
	if not _write_atomic(DIR + "/" + fname, blob):
		return
	var goal: Vector2 = st.goal
	_entries()[tier] = {
		"file": fname,
		"sha256": FileAccess.get_sha256(DIR + "/" + fname),
		"anchor": [goal.x, goal.y],
		"nx": int(st.nx), "nz": int(st.nz),
		"step": float(st.step), "ox": float(st.ox), "oz": float(st.oz),
		"level": float(st.level),
	}
	_manifest = {"format": FORMAT, "world_key": _key(), "tiers": _entries()}
	_write_atomic(MANIFEST,
		(JSON.stringify(_manifest, "\t", true) + "\n").to_utf8_buffer())


# --- internals ---------------------------------------------------------------


## The world key: sha256 over every input the seabed bake reads. The import
## stamp already carries the blessed tile's height sha (no re-hash of the
## EXR itself) and the sea level; the edit layers and every water record
## hash by content. No stamp ⇒ no adopted world ⇒ cache off.
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
	ctx.update(("bathy:%d\n" % FORMAT).to_utf8_buffer())
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


## The manifest's tier table, loaded once per key — and only trusted when
## the recorded world_key matches the live one exactly.
static func _entries() -> Dictionary:
	if not _manifest.is_empty():
		return _manifest.get("tiers", {})
	_manifest = {"format": FORMAT, "world_key": _key(), "tiers": {}}
	if FileAccess.file_exists(MANIFEST):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary and int(parsed.get("format", -1)) == FORMAT \
				and String(parsed.get("world_key", "")) == _key() \
				and parsed.get("tiers") is Dictionary:
			_manifest = parsed
	return _manifest.get("tiers", {})


## The entry's grid must equal the LIVE registration exactly — a lake that
## re-registered with a different step, a sea tier whose boot anchor landed
## on a different snap cell, a changed level: all refuse. Anchor/step/level
## values are snapped multiples or record-sourced floats, so the JSON
## round-trip is exact; any drift fails closed into a rebake.
static func _grid_matches(entry: Dictionary, goal: Vector2, st: Dictionary) -> bool:
	var anchor: Variant = entry.get("anchor")
	if not (anchor is Array and (anchor as Array).size() == 2):
		return false
	return float(anchor[0]) == goal.x and float(anchor[1]) == goal.y \
		and int(entry.get("nx", -1)) == int(st.nx) \
		and int(entry.get("nz", -1)) == int(st.nz) \
		and float(entry.get("step", -1.0)) == float(st.step) \
		and float(entry.get("ox", 1e30)) == float(st.ox) \
		and float(entry.get("oz", 1e30)) == float(st.oz) \
		and float(entry.get("level", 1e30)) == float(st.level)


static func _slug(tier: String) -> String:
	var out := ""
	for c in tier:
		out += c if c.is_valid_identifier() or c.is_valid_int() else "_"
	return out


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
