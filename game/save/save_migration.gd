class_name SaveMigration
## The save covenant, as a ladder (PLAN_SHIP §1.7 / S4 groundwork). The
## GDScript twin of Strata's Migration.swift: a save carries its format int
## ("version"), and every later build either LADDERS an older save up to the
## format it knows, or REFUSES honestly on a save from a NEWER build — never a
## crash, never a silent reset. It runs on the raw parsed dict BEFORE
## save_manager.apply_snapshot, so the live deserialize door only ever meets
## today's shape.
##
## Why the raw dict and not the applied fields: a format-N save may not carry
## the keys format N+1 reads at all (a key that was added, a field that split).
## The ladder reshapes the dict first — each rung reads version N and produces
## the shape version N+1 expects — so the apply that follows is guaranteed to
## fit. This mirrors Migration.swift's "reshape the JSON before Codable ever
## sees it" exactly (Sources/StrataCore/Document/Migration.swift).
extends RefCounted

## The format snapshot_data() writes today (save v2 — the Threshold, which
## ADDED optional player.interior fields over v1). Lifting this by one is a
## two-line change: add the rung to _apply_step + list its source in _RUNGS.
const CURRENT := 2

## The source versions that have a migration rung. Must be CONTIGUOUS over
## 1..CURRENT-1 — a gap is a format bump that forgot its migration, and
## migrate() refuses (`no migration from save vN`) rather than half-migrate.
const _RUNGS := [1]


## One rung: read `data` at version `from`, return the shape version `from`+1
## expects. A rung must NOT set "version" — the ladder stamps the counter
## itself (a rung that reshaped but forgot to bump would loop forever; owning
## the counter in migrate() makes that impossible, per Migration.swift's Step).
static func _apply_step(from: int, data: Dictionary) -> Dictionary:
	match from:
		1:
			# v1 → v2 (the Threshold): v2 only ADDED optional keys; nothing was
			# moved or renamed, so an outside-the-interior v1 save is already a
			# valid v2 body. Fill the v2 defaults a v1 save predates so today's
			# reader meets a WHOLE v2 shape: `cells` (per-cell world state) and
			# `civil` (a pre-civil save carries an arbitrary clock offset — false
			# is honest: it triggers apply_snapshot's one-time clock re-anchor).
			var d := data.duplicate(true)
			if not d.has("cells"):
				d["cells"] = {}
			if not d.has("civil"):
				d["civil"] = false
			return d
		_:
			# Unreachable — migrate() only calls _apply_step for `from` in _RUNGS.
			return data


## Migrate a raw parsed save up to CURRENT. Returns a result dict:
##   {ok=true,  data=<migrated v-CURRENT dict>, error="", refused_newer=false}
##   {ok=false, data={}, error=<the honest sentence>, refused_newer=<bool>}
## refused_newer marks the covenant's core case — a save from a future build —
## so the caller can say so to the player instead of silently starting fresh.
static func migrate(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return _refuse("save is not a JSON object")
	var data: Dictionary = raw
	if not data.has("version"):
		# A bare {} (or a foreign file) is not save v1 — refuse to guess a
		# format rather than misread someone else's JSON as a game save.
		return _refuse("save carries no version — refusing to guess its format")
	var version := int(data.get("version", 0))
	if version < 1:
		return _refuse("save version %d is not a known format" % version)
	if version > CURRENT:
		# The covenant's whole point: a save written by a NEWER game refuses
		# honestly, naming the version that could read it — never a crash,
		# never a silent reset to a fresh journey.
		return {
			"ok": false, "data": {}, "refused_newer": true,
			"error": ("this save is from a newer version of the game "
				+ "(save format v%d; this build reads up to v%d) — "
				+ "update the game to open it") % [version, CURRENT],
		}
	var working := data.duplicate(true)
	var at := version
	while at < CURRENT:
		if not (at in _RUNGS):
			return _refuse("no migration from save v%d — this build knows up to v%d"
				% [at, CURRENT])
		working = _apply_step(at, working)
		# The ladder owns the counter, never the rung (see _apply_step).
		working["version"] = at + 1
		at += 1
	return {"ok": true, "data": working, "error": "", "refused_newer": false}


static func _refuse(msg: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": msg, "refused_newer": false}
