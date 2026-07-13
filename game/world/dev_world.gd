class_name DevWorld
extends RefCounted
## THE DEV-WORLD POSTURE (loop-compression rung 2, docs/BOOT_DEVWORLD.md): the
## ONE place the runtime reads STRATA_DEV_WORLD, read once at streamer _ready
## per the spec ("selected by an env flag ... read ONCE"). Default OFF, so
## shipping, the soak, and every gate are untouched unless a dev boot opts in.
##
## A dev world is NEVER blessworthy (the no-world-preservation law: dev/test
## worlds are disposable, only VALLEY's sim identity is sacred) — so it trades
## the fingerprint-neutral boot levers (tiny frame, shrunk load radius,
## prebake-refuse-on-miss) for boot speed, and refuses to let its coarse ring
## anywhere near a bless decision (tests/soak.gd checks `active()` first and
## refuses to run at all).
##
## Statics, cached on first read (matches the "read once at _ready" contract);
## a test that wants a different posture must set the env before that first
## read, same discipline as ContourPosture's callers snapshot their own value.

static var _cached := -1  # -1 = not yet read, 0 = off, 1 = on
static var _banner_printed := false


## Is STRATA_DEV_WORLD=1 active this process? Cached after the first call.
static func active() -> bool:
	if _cached == -1:
		_cached = 1 if OS.get_environment("STRATA_DEV_WORLD") == "1" else 0
	return _cached == 1


## Print the loud one-line boot banner exactly once per process — callers
## (world_streamer._ready) call this unconditionally; it no-ops when the
## flag is off or the banner already printed this run.
static func announce() -> void:
	if not active() or _banner_printed:
		return
	_banner_printed = true
	print("[dev-world] DEV WORLD — coarse sim ring, not blessworthy, fingerprints invalid")
