class_name Prebake
extends RefCounted
## THE ADOPT PREBAKE POSTURE (adopt-time hydrology rebuild, 2026-07-13): the
## ONE place the runtime reads STRATA_PREBAKE — the DevWorld shape exactly
## (read once, cached, default OFF so shipping, the soak, and every gate are
## untouched unless a bless-time prebake run opts in).
##
## THE LAW (boot loads, never computes — extended to ADOPT): everything the
## in-session adopt rebuilds that is derivable from the blessed bake gets
## computed at BLESS time by the game's OWN headless boot (bit-identical by
## construction — no reimplementation of the kernel math anywhere), stored
## through the exact same cache classes the live boot loads from (BathyCache /
## CatchmentCache / WaterFieldCache, all content-keyed, all refuse-loudly).
## import_and_bake.sh drives this run right after the import, under an
## isolated HOME, with this flag set; the run quits ITSELF the moment every
## bake has landed on disk (see maybe_finish), so the bless pays the compute
## once, headless, while the pane stays live — and the adopt that follows
## LOADS.
##
## Bathy note: _bathy_follow deliberately skips baking on a headless display
## (presentation economy — the soak and the gates never pay the seabed
## sample). This flag is the one exception: a prebake run IS headless and
## exists precisely to pay that sample early, so the skip stands down for it.

static var _cached := -1  # -1 = not yet read, 0 = off, 1 = on
static var _done: Dictionary = {}  # phase name -> true once its bake is on disk
static var _quit_called := false
static var _t0 := -1  # first-poll tick (msec) — the wall-clock backstop's zero

## Wall-clock backstop: a prebake that hasn't finished in this long is stuck
## (a phase never marked), and the run must fail LOUDLY rather than hang the
## bless. Generous — a 16k world's full seabed sample is minutes, not tens.
const BUDGET_S := 600.0

## Every bake the prebake run waits for before quitting. water_field and
## bathy mark themselves "done" even when there is nothing to bake (a dry
## world has no sea/lakes; a kernel-less checkout can't sample) — done means
## "nothing left that this run could store", never "everything succeeded".
const PHASES: Array[String] = ["bathy", "catchments", "water_field"]


## Is STRATA_PREBAKE=1 active this process? Cached after the first call.
static func active() -> bool:
	if _cached == -1:
		_cached = 1 if OS.get_environment("STRATA_PREBAKE") == "1" else 0
	return _cached == 1


## One bake landed (or proved it has nothing to land). Callable from worker
## threads (catchments builds on the WorkerThreadPool) — it only writes the
## flag; the quit happens on the main thread via maybe_finish's poll.
static func mark(phase: String) -> void:
	if not active() or _done.has(phase):
		return
	_done[phase] = true
	print("[prebake] %s done (%d/%d)" % [phase, _done.size(), PHASES.size()])


## Main-thread poll (water_bodies._process): quit the run once every phase
## has landed. Idempotent past the first fire.
static func maybe_finish(tree: SceneTree) -> void:
	if not active() or _quit_called:
		return
	if _t0 < 0:
		_t0 = Time.get_ticks_msec()
	if Time.get_ticks_msec() - _t0 > BUDGET_S * 1000.0:
		_quit_called = true
		var missing: Array[String] = []
		for p in PHASES:
			if not _done.has(p):
				missing.append(p)
		push_error("[prebake] budget exceeded (%.0fs) — never finished: %s" % [
			BUDGET_S, ", ".join(missing)])
		tree.quit(1)
		return
	for p in PHASES:
		if not _done.has(p):
			return
	_quit_called = true
	print("[prebake] complete — adopt caches written; quitting")
	tree.quit()
