class_name PlacementRecords
extends RefCounted
## Placement records (E-track, the ESP-shaped core): "where things are in a
## world" as DATA, not .tscn node trees — the family-generic envelope the
## native host will consume when it stands a world without Godot's scene
## format. Shaped like LookData's Look records ({look_family, params}): one
## envelope, `placement_family` selects which arm reads `params`, an unknown
## family fails LOUDLY — never a silent fallback.
##
## TWO FAMILIES (Nicco's hybrid ruling, 2026-07-12):
##
##   placement_gen — GENERATOR placements. The world's identity today is
##     procedural: world_streamer.gd rebuilds a cell's flora and forage from a
##     seeded formula (same cell -> same layout, forever). A placement_gen
##     record carries the RULE'S CONSTANTS — seed law, count law, draw ranges —
##     and `gen_candidates` replays the exact RNG draw stream the streamer
##     draws, so record-driven generation reproduces the streamer's seeded
##     candidate output bit-for-bit (the reproduction proof in
##     tests/run_tests.gd). World-state inputs the formula reads at build time
##     (valley factor, biome density, vitality, the yielding species list) are
##     the ENV the host supplies; the record owns only the law's numbers.
##
##   placement_set — FROZEN per-instance records: rows of
##     {what, x, y, z, yaw, ...params} keyed per cell ("x_y", the Ambit grid:
##     Vector2i(round(pos.x/128), round(pos.z/128)), cell_size PIN 128.0 —
##     ambit.h / cell_records.gd agree). A SUPERSET of the shapes already
##     shipping: a Chronicle row ({kit,x,y,z,yaw,scale,ground_dy,id,group,
##     enabled} — cell_records.gd) maps kit->what and rides the rest as
##     preserved params (row_from_chronicle); a baked-scatter row
##     ({id,cat,x,y,z,yaw,scale,pick} — scatter_bake.gd) maps the same way
##     (row_from_baked). Those stores are NOT migrated this round — the
##     mapping proves expressibility; migration is a later rung
##     (docs/PLACEMENTS.md).
##
## VALIDATION mirrors records.gd's validate_message judgement (first
## missing/mistyped declared field, int-accepted-where-float) with the SAME
## sentence wording, self-contained here because this class must load under
## `godot -s` before autoloads register (run_tests.gd's law). The Swift twin
## (ledger/Sources/Ledger/PlacementStore.swift) byte-matches every refusal
## sentence — Strata can never write a placement the game can't read.
##
## NATIVE SEAM (the swap's integration round): the host loads the record
## (GodotJSON — lexical int/float, insertion order preserved, tab stringify),
## keys cells by AmbitCell, calls the gen arm per newly-resident cell with env
## from its own world services, and instantiates set rows by resolving `what`
## (res:// path or catalog id — Kit.scene_for's contract) through its own
## catalog. Terrain seating and water/flatten filters stay HOST-side: the
## candidate stream is pure, the filters read world state.

const FORMAT := 1
const FAMILY_GEN := "placement_gen"
const FAMILY_SET := "placement_set"
## Metres per cell side — the Ambit PIN (ambit.h: cell_size=128, and
## cell_records.gd CELL_SIZE). A record carries its own cell_size so the
## envelope stays world-generic; this constant is only the shipped default.
const CELL_SIZE := 128.0

## The envelope's declared fields (records.gd type spelling; everything else
## rides through preserved). `format` is declared FLOAT so a lexical int
## passes — the one coercion records.gd allows.
const ENVELOPE := {
	"placement_family": TYPE_STRING,
	"format": TYPE_FLOAT,
	"cell_size": TYPE_FLOAT,
	"params": TYPE_DICTIONARY,
}

## A frozen instance row's declared fields. yaw radians, x/y/z world metres
## (y may be re-seated by the host — ground_dy rides in params when present).
const SET_ROW := {
	"what": TYPE_STRING,
	"x": TYPE_FLOAT,
	"y": TYPE_FLOAT,
	"z": TYPE_FLOAT,
	"yaw": TYPE_FLOAT,
}


## records.gd validate_message, verbatim wording — the first failure sentence,
## or "" when the record passes. Local copy (no autoload names in this file).
static func validate_message(record: Dictionary, required: Dictionary) -> String:
	for field in required:
		if not record.has(field):
			return "missing field '%s'" % field
		var want: int = required[field]
		var got := typeof(record[field])
		if got != want and not (want == TYPE_FLOAT and got == TYPE_INT):
			return "field '%s' should be %s, got %s" % [
				field, type_string(want), type_string(got)]
	return ""


## The envelope judgement: declared fields, then family match, then the
## format ceiling. "" on ok, else the refusal sentence (byte-matched by the
## Swift twin's envelopeMessage).
static func envelope_message(record: Dictionary, family: String) -> String:
	var msg := validate_message(record, ENVELOPE)
	if msg != "":
		return msg
	var got_family := String(record["placement_family"])
	if got_family != family:
		return "declares placement_family '%s', expected '%s'" % [got_family, family]
	var f := int(record["format"])
	if f > FORMAT:
		return "format %d is newer than this build understands (max %d)" % [f, FORMAT]
	return ""


## Load a placement record from `path` IF it declares `family`. Returns {}
## and push_errors on: missing file, bad JSON, a failed envelope judgement —
## callers must treat {} as "something is wrong, look at the log" (LookData's
## contract), never as "use defaults".
static func load_record(path: String, family: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[placements] missing placement record: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[placements] %s did not parse as an object" % path)
		return {}
	var record: Dictionary = parsed
	var msg := envelope_message(record, family)
	if msg != "":
		push_error("[placements] %s: %s" % [path, msg])
		return {}
	return record


## The one stringify convention (the byte-round-trip law): tab-indented,
## sorted keys (Godot's stringify default — the same call cell_records/
## interior_records save with), the fixed point the transcriber emits:
## extract -> load -> stringify is byte-identical; run_tests.gd proves it on
## the shipped fixtures.
static func stringify(record: Dictionary) -> String:
	return JSON.stringify(record, "\t")


# --- placement_set: frozen instances -----------------------------------------

## The rows of `cell` from a validated placement_set record ([] when none).
## Cells key as "x_y" on the Ambit grid.
static func set_rows(record: Dictionary, cell: Vector2i) -> Array:
	var cells: Dictionary = (record.get("params", {}) as Dictionary).get("cells", {})
	return cells.get("%d_%d" % [cell.x, cell.y], [])


## Judge one frozen row. "" on ok, else the records.gd-worded refusal.
static func set_row_message(row: Dictionary) -> String:
	return validate_message(row, SET_ROW)


## Expressibility, not migration: a Chronicle row (cell_records.gd) as a
## placement_set row. kit -> what; x/y/z/yaw carry over; every other key
## (scale, ground_dy, id, group, enabled, ...) rides in insertion order —
## nothing is dropped, so the mapping is invertible.
static func row_from_chronicle(rec: Dictionary) -> Dictionary:
	return _row_from(rec, "kit")


## A baked-scatter row (scatter_bake.gd) as a placement_set row. `what` is the
## category (`cat` — the streamer resolves it to a slot via `pick`, which
## rides through preserved with the stable id and scale).
static func row_from_baked(rec: Dictionary) -> Dictionary:
	return _row_from(rec, "cat")


static func _row_from(rec: Dictionary, what_field: String) -> Dictionary:
	var out := {}
	var wf := what_field
	out["what"] = String(rec.get(wf, ""))
	for k in ["x", "y", "z", "yaw"]:
		out[k] = float(rec.get(k, 0.0))
	for k in rec:
		if k == wf or out.has(k):
			continue
		out[k] = rec[k]
	return out


# --- placement_gen: generator placements --------------------------------------

## Replay a generator rule's seeded candidate stream for `cell`. The record
## owns the law's constants; `env` supplies the world-state inputs the
## streamer reads at build time. Rows are the PURE candidate draws — exactly
## the values world_streamer draws, in its draw order, BEFORE the host-side
## filters (flattens, water line, species pick) that read world state.
## Unknown rule: loud + [].
static func gen_candidates(record: Dictionary, cell: Vector2i, env: Dictionary) -> Array:
	var p: Dictionary = record.get("params", {})
	match String(p.get("rule", "")):
		"flora_scatter":
			return _gen_flora(record, p, cell, env)
		"forage_slots":
			return _gen_forage(record, p, cell, env)
		_:
			push_error("[placements] unknown placement_gen rule '%s'" % p.get("rule", ""))
			return []


## world_streamer.gd _add_scatter's candidate stream (the deterministic half):
## seed = hash(cell) (seed_mul 1, seed_add 0); count = round(lerp(base_hi,
## base_lo, valley_factor) * biome_mult * lerp(vit_lo, vit_hi, vitality)),
## then randi_range(count, count+extra) draws the loop bound FIRST; each
## iteration draws lx, lz, roll, scale IN THAT ORDER (draws precede every
## filter, so acceptance never shifts the layout — the streamer's own law).
static func _gen_flora(record: Dictionary, p: Dictionary, cell: Vector2i, env: Dictionary) -> Array:
	var cs := float(record.get("cell_size", CELL_SIZE))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell) * int(p.get("seed_mul", 1)) + int(p.get("seed_add", 0))
	var base_count := int(round(
			lerpf(float(p["count_base_hi"]), float(p["count_base_lo"]),
					float(env["valley_factor"]))
			* float(env["biome_mult"])
			* lerpf(float(p["count_vit_lo"]), float(p["count_vit_hi"]),
					float(env["vitality"]))))
	var out: Array = []
	for i in rng.randi_range(base_count, base_count + int(p["count_extra"])):
		out.append({
			"lx": rng.randf() * cs,
			"lz": rng.randf() * cs,
			"roll": rng.randf(),
			"scale": rng.randf_range(float(p["scale_min"]), float(p["scale_max"])),
		})
	return out


## world_streamer.gd _add_forage's slot stream: seed = hash(cell)*13+5
## (seed_mul/seed_add in the record); for each yielding item (env, in
## FloraLife.species order) each of `candidates` slots draws lx, lz, yaw —
## ALWAYS, even for slots depletion currently hides, so the layout never
## shifts as spots are gathered (the streamer draws before its `continue`).
static func _gen_forage(record: Dictionary, p: Dictionary, cell: Vector2i, env: Dictionary) -> Array:
	var cs := float(record.get("cell_size", CELL_SIZE))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell) * int(p.get("seed_mul", 1)) + int(p.get("seed_add", 0))
	var out: Array = []
	for item in env.get("yield_items", []):
		for i in int(p["candidates"]):
			out.append({
				"item": item,
				"slot": i,
				"lx": rng.randf() * cs,
				"lz": rng.randf() * cs,
				"yaw": rng.randf() * TAU,
			})
	return out
