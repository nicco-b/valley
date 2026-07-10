extends Node
## Cards (autoload): the asset-card catalog — the Chronicle.
##
## Every asset slot ships a `.card.json` next to its files (the one-asset =
## files + card contract): {slot, class, variants, files, status, gated}. This
## scans assets/**/*.card.json once at boot, validates through Records, and
## becomes the single source of truth for the placeable palette (the Kit) and
## the real-vs-placeholder ledger (the Toolkit dashboard, summary()).
##
## `files` in a card are paths relative to the class root
## (gltf_mesh -> assets/models, billboard_png -> assets/paintings); we resolve
## them to res:// paths on load. Placement stores the RESOLVED file, never the
## slot, so retiring a placeholder (paint the real art into the same file slot,
## flip `status`) never moves anything already placed.
##
## Dev note: .card.json are plain files, not imported resources, so this reads
## them via DirAccess/FileAccess on res:// — fine in the editor and headless
## dev runs (the Toolkit is dev-only). An exported build would need them added
## as export files before the catalog is non-empty there.

const ROOTS := {
	"gltf_mesh": "res://assets/models",
	"billboard_png": "res://assets/paintings",
}

var _slots: Dictionary = {}  # slot id -> entry
var _by_file: Dictionary = {}  # resolved res:// file -> slot id (placement stores files)


func _ready() -> void:
	for base in ROOTS.values():
		_walk(base, base)


func _walk(dir_path: String, base: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_walk(dir_path + "/" + sub, base)
	for f in dir.get_files():
		if f.ends_with(".card.json"):
			_load_card(dir_path + "/" + f, base)


func _load_card(path: String, base: String) -> void:
	var rec = Records.load_json(path)
	if not (rec is Dictionary):
		return
	if not Records.validate(rec, {
		"slot": TYPE_STRING, "class": TYPE_STRING, "variants": TYPE_FLOAT,
		"files": TYPE_ARRAY, "status": TYPE_STRING,
	}, path):
		return
	var slot: String = rec["slot"]
	var files: Array = []
	for f in rec["files"]:
		files.append(base + "/" + str(f))
	_slots[slot] = {
		"slot": slot,
		"class": rec["class"],
		"category": slot.split("/")[0],
		"variants": int(rec["variants"]),
		"files": files,
		"status": rec["status"],
		"gated": bool(rec.get("gated", false)),
		"collision": rec.get("collision", ""),
		"clips": rec.get("clips", ""),
		# PLAN_FABRIC F1: "fabric" flags the slot for the fabric_wind
		# material override at placement; wind_hang = cloth meters at
		# freedom 1 (the shader's `hang` uniform).
		"wind": str(rec.get("wind", "")),
		"wind_hang": float(rec.get("wind_hang", 1.0)),
		# The marker vocabulary (PLAN_CREATION_LIBRARY §4c: "a marker is a
		# card with a keyword") — idle/furniture markers AI packages target
		# ("something tends here"). "" for ordinary props; "marker" flags a
		# placeable point a schedule can name (CREATION_KIT_REVIEW_V2 #3).
		"keyword": str(rec.get("keyword", "")),
		# Kit-bashing sockets (PLAN_CREATION_LIBRARY §4b / L11): the points
		# where this piece CLICKS onto another, as plain card data — each a
		# {name, type, pos:[x,y,z], yaw} in the mesh's local frame. The
		# Toolkit reads these, transforms them to world (ToolkitSnap), and
		# mates a dropped piece to a compatible one. [] for ordinary props
		# (the zero-regression floor — no sockets, no snap).
		"sockets": rec.get("sockets", []),
		# Buoyancy opt-in (PLAN_SUBSTANCES S3): a card carrying a `float`
		# block ({footprint, tether, swell}) rides the water — world_streamer
		# attaches a FloatBody to a placed record when it finds this. {} for
		# ordinary props (they seat on the ground; no bob).
		"float": rec["float"] if rec.get("float") is Dictionary else {},
	}
	for f in files:
		_by_file[f] = slot


## The full entry for a slot, or {} if unknown.
func slot(id: String) -> Dictionary:
	return _slots.get(id, {})


func has(id: String) -> bool:
	return _slots.has(id)


## The entry that owns a resolved res:// file, or {}. Placement (records
## and scatter alike) stores files, never slots — this is how a placed
## object finds its card again (the fabric override needs its flags).
func entry_for_file(path: String) -> Dictionary:
	return _slots.get(_by_file.get(path, ""), {})


## The keyword a placed file's card carries ("" when none) — the marker
## vocabulary (§4c). Placement stores resolved files, so a placed record
## finds its card's keyword through the same door the fabric flags use.
func keyword_for_file(path: String) -> String:
	return str(entry_for_file(path).get("keyword", ""))


## The kit-bashing sockets a placed file's card declares (the L11 snap
## points), or [] when the card has none / the file is unknown. Placement
## stores resolved files, so a placed piece finds its sockets through the
## same door the fabric flags and keyword ride — the Toolkit transforms
## them to world and mates a dropped piece to a compatible one.
func sockets_for_file(path: String) -> Array:
	return entry_for_file(path).get("sockets", [])


## The buoyancy config a placed file's card declares (PLAN_SUBSTANCES S3),
## or {} when the card doesn't float / the file is unknown. Placement stores
## resolved files, so a placed raft finds its `float` block through the same
## door the fabric flags, keyword, and sockets ride — world_streamer reads
## it to attach a FloatBody at the record's mooring.
func float_for_file(path: String) -> Dictionary:
	return entry_for_file(path).get("float", {})


## Is the card that owns this placed file a marker (a schedule target)?
## The palette/desk filter for "which cards are markers", and the honest
## check behind a schedule pointing at a placed record.
func is_marker(path: String) -> bool:
	return keyword_for_file(path) == "marker"


## Slots whose card flags them for the wind-fabric override (F1).
func fabric_slots() -> Array:
	var out: Array = []
	for e in _slots.values():
		if e["wind"] == "fabric":
			out.append(e["slot"])
	out.sort()
	return out


func count() -> int:
	return _slots.size()


## Placeable palette: non-gated static meshes, sorted category then slot.
func placeable() -> Array:
	var out: Array = []
	for e in _slots.values():
		if e["class"] == "gltf_mesh" and not e["gated"]:
			out.append(e)
	out.sort_custom(func(a, b): return a["slot"] < b["slot"])
	return out


## Ordered category names present in the placeable palette.
func placeable_categories() -> Array:
	var seen: Array = []
	for e in placeable():
		if not seen.has(e["category"]):
			seen.append(e["category"])
	return seen


## Resolve a slot to one of its files. `variant` < 0 picks the first; any
## index wraps modulo the variant count. Returns "" for an unknown/empty slot.
func resolve(slot_id: String, variant := -1) -> String:
	var e: Dictionary = _slots.get(slot_id, {})
	if e.is_empty() or (e["files"] as Array).is_empty():
		return ""
	var files: Array = e["files"]
	if variant < 0:
		return files[0]
	return files[variant % files.size()]


## Deterministic variant index for a world position — same spot always
## resolves the same file, so scatter and re-placement are stable, but nearby
## objects vary. Quantized to 0.25m.
func variant_for(slot_id: String, pos: Vector3) -> int:
	var e: Dictionary = _slots.get(slot_id, {})
	if e.is_empty():
		return 0
	var n: int = (e["files"] as Array).size()
	if n <= 1:
		return 0
	var key := "%s@%d,%d" % [slot_id, roundi(pos.x * 4.0), roundi(pos.z * 4.0)]
	return abs(hash(key)) % n


## Toolkit dashboard: real vs placeholder-synth per category (the
## PLACEHOLDERS.md contract — flip a card's `status` when its art lands and
## this counts it as real).
func summary() -> String:
	if _slots.is_empty():
		return "no cards"
	var cats: Dictionary = {}  # category -> [real, synth, gated]
	var real := 0
	var synth := 0
	for e in _slots.values():
		var c: String = e["category"]
		if not cats.has(c):
			cats[c] = [0, 0, 0]
		if e["gated"]:
			cats[c][2] += 1
		elif e["status"] == "placeholder-synth":
			cats[c][1] += 1
			synth += 1
		else:
			cats[c][0] += 1
			real += 1
	var keys: Array = cats.keys()
	keys.sort()
	var lines: Array = ["%d slots · %d real / %d synth" % [_slots.size(), real, synth]]
	for c in keys:
		var t: Array = cats[c]
		var g: String = "" if t[2] == 0 else " +%d gated" % t[2]
		lines.append("  %-10s %d real / %d synth%s" % [c, t[0], t[1], g])
	return "\n".join(lines)
