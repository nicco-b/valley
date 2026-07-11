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
##
## THE ONE DOOR. Both save-load call sites (save_manager.load_into_world and
## restore_anchor via _read_anchor) ride this, so routing it once routes the
## whole covenant. When STRATA_CONTOUR=1 the ladder runs on the native Contour
## VM (game/save/save_migration.ct — the datum-certified §5 twin); flag OFF it
## is the byte-identical GDScript twin _migrate_gd below (see the routing block
## and its covenant note at the foot of this file for WHY this gate exists).
static func migrate(raw: Variant) -> Dictionary:
	var vm := _route()
	if vm != null:
		# Routed: the native VM computes the whole result dict. NO silent
		# fallback — a null here (a VM/marshalling break) surfaces loudly at the
		# caller rather than quietly reverting to GDScript, which would hide a
		# covenant regression at the one moment the law is absolute.
		_contour_calls += 1
		return vm.call_fn("migrate", [raw])
	return _migrate_gd(raw)


## The GDScript twin of the ladder — the forever-byte-identical flag-OFF path,
## and the oracle the save-load gate compares the VM against (SaveMigration.ct
## flag-on == this flag-off, byte-for-byte over every real fixture). This body
## is unchanged from the pre-routing SaveMigration.migrate; the routing above is
## a pure prepend, so flag-off is bit-for-bit what shipped.
static func _migrate_gd(raw: Variant) -> Dictionary:
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


# --- Contour routing (PLAN_ENGINE E2, the conditions/names/hydrology precedent) --
## WHY THIS GATE EXISTS — the covenant stance, in one paragraph:
## migrate() runs at LOAD (save_manager.load_into_world / restore_anchor), ONCE,
## before the world exists — NEVER on the sim tick. The standing determinism gate
## is the soak, which starts a FRESH seeded world and advances 30 game-days; it
## NEVER loads a save from disk. So the soak is structurally blind to this path:
## routing migrate behind STRATA_CONTOUR and claiming the soak proves flag-on
## inert would be a lie — the fingerprint cannot see load-time work. And this is
## the single most fragile covenant moment (opening a player's save, where "never
## a crash / never a silent reset" is the whole law), so a VM dependency here
## demands a STANDING byte-identity proof of its own. That proof is the dedicated
## save-load gate (tests/save_load_gate.tscn), a DIFFERENT harness from the soak:
## it loads every real fixture through the real save path and asserts _migrate_gd
## (flag-off) == the VM (flag-on) byte-for-byte on the result dict AND the refusal
## sentences verbatim, plus this call counter to prove the VM actually answered.
## test.sh runs that gate BOTH ways every gate — so the load-time path the soak
## can't watch is watched here instead. Flag OFF (the shipping default) is the
## byte-identical GDScript twin: the covenant moment is untouched in production.
##
## The whole result is a `dict` (composite ABI, LAT_BUF); the arg `raw` may be a
## Dictionary, a bare String/int (adversarial), or null (a torn parse) — all cross
## the kernel arg codec (LAT_STR/LAT_INT/LAT_NULL/composite). NO SILENT FALLBACK
## (the honesty law): flag ON with the kernel absent or a module that will not
## compile is a LOUD refusal (push_error, mode -1), never a quiet GDScript pass.
const _CONTOUR_MODULE := "res://game/save/save_migration.ct"

## 0 unresolved · 1 off (flag unset) · 2 engaged (VM live) · -1 refused (flag set
## but kernel/module unavailable — loud, not silent).
static var _contour_mode := 0
static var _contour_vm: Contour = null
static var _contour_calls := 0   # VM-answered migrate() calls (the engaged-path probe)

## The live VM when routing is engaged, else null (flag off, or refused). Resolves
## once at first migrate (load time); pure — no side effects, so flag-off is byte-
## identical to the un-routed ladder.
static func _route() -> Contour:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour_vm


static func _contour_resolve() -> void:
	var verdict := Contour.decide("save_migration")
	if verdict != Contour.ROUTE_ENGAGE:
		_contour_mode = verdict   # ROUTE_FALLBACK (GDScript twin) or ROUTE_REFUSE (loud, mode -1)
		return
	# Routing engaged — compile the module (a compile failure still refuses loudly).
	var vm := Contour.new()
	var err := vm.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[save_migration] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour_vm = vm
	_contour_mode = 2


## Routing introspection for the save-load gate (proves the VM answered, not a
## silent fallback): the resolved mode, whether it engaged, and the answered-call
## count. Resolves the flag on first call so the gate can read it before any load.
static func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls}
