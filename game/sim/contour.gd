class_name Contour
extends RefCounted
## The Contour VM host (PLAN_ENGINE §3 E2 — "the VM runs the sim tier").
##
## Loads the native ContourKernel GDExtension — the Lattice VM (a Swift static
## archive behind a flat C ABI) linked into THIS process on the game's own tick
## thread — compiles a Contour module once, and answers per-call requests
## bit-identically to the module's GDScript twin (88/88 corpus certified, both
## template_debug and template_release; see native/contour/).
##
## SIM MACHINERY, not dev tooling: no DevMode gate. But it is content-empty-safe
## and an honest NO-OP when the native kernel is absent — exactly the loomkernel
## macOS-gate precedent (game/world/terrain.gd::_init_kernel). On a stock engine,
## a non-macOS platform, or a build without the dylib, available() is false,
## compile() returns a diagnostic, call_fn() returns null, and every consumer
## keeps running its GDScript path. Nothing here touches the sim tick unless a
## game explicitly compiles a module and calls it — so it is soak-inert while
## unused.
##
## Consumer contract (the API another agent's port drives):
##   if Contour.available():                       # macOS + dylib present?
##       var vm := Contour.new()
##       var err := vm.compile_file("res://<module>.ct")   # "" on success
##       if err == "":
##           var r = vm.call_fn("<fn>", [args...])         # HOT, per-tick safe
##   # ... else fall back to the GDScript twin.

## The explicit-load manifest (deliberately .gdext, NOT .gdextension — the
## loomkernel pattern: auto-scan would register the class on every platform and
## error where the dylib isn't built).
const KERNEL_EXT := "res://native/contour/bin/contourkernel.gdext"

var _kernel: RefCounted = null   # the ContourKernel instance once a module compiles

# Ensure the native ContourKernel class is registered. Idempotent; a NO-OP that
# returns false off macOS or without the built dylib (no error spam — matches
# terrain.gd::_init_kernel, which uses class_exists over can_instantiate so the
# smoke test's clean-output gate holds).
static func _ensure_extension() -> bool:
	if ClassDB.class_exists("ContourKernel"):
		return true
	if OS.get_name() != "macOS" or not FileAccess.file_exists(KERNEL_EXT):
		return false
	var status := GDExtensionManager.load_extension(KERNEL_EXT)
	if status != GDExtensionManager.LOAD_STATUS_OK \
			or not ClassDB.class_exists("ContourKernel"):
		push_warning("[contour] native kernel failed to load (%d); GDScript twin only" % status)
		return false
	return true

## Is the native Contour VM loadable at all (macOS + dylib present + registered)?
## Consumers gate their "use Contour or fall back to GDScript" branch on this.
## Loading the extension is a side effect here, but idempotent.
static func available() -> bool:
	return _ensure_extension()


## --- THE DEFAULT (F1, 2026-07-11): STRATA_CONTOUR defaults ON ----------------
## Historically each routed twin read `STRATA_CONTOUR != "1"` and ran its
## GDScript twin unless the operator opted IN. The Contour systems are now
## matrix-proven (the grand matrix, the save-load gate both ways, held routing),
## so the DEFAULT flips: the sim routes THROUGH Contour unless STRATA_CONTOUR=0
## (the escape hatch). This mirrors the Strata app's STRATA_ENGINE_RESTART flip
## exactly — ProjectSwitch.restartEnabled (Sources/StrataCore/Project): unset ==
## on, only the literal "0" opts out.
##
## THE KERNEL-ABSENT POSTURE — three distinct answers, because the framework
## ships EVERYWHERE but the native dylib is macOS-only:
##   • "0"                       -> ROUTE_FALLBACK: the GDScript twin, silent.
##                                  The operator's explicit escape hatch.
##   • ON + kernel live          -> ROUTE_ENGAGE the VM (the milestone path).
##   • ON + kernel ABSENT and the operator DEMANDED it (=1), OR we are on macOS
##     (where the dylib SHIPS, so its absence is a broken dev build)
##                               -> ROUTE_REFUSE, loudly (push_error, mode -1).
##                                  Never a silent GDScript pass under a demand.
##   • ON + kernel ABSENT, UNSET, on a kernel-less (non-macOS) platform
##                               -> ROUTE_FALLBACK to the GDScript twin WITH a
##                                  visible once-per-boot push_warning. A player
##                                  who never asked for Contour, on a platform
##                                  the dylib never targets, must get a WORKING
##                                  game — never a crash. This is a DIFFERENT
##                                  posture than explicit =1: =1 is a demand that
##                                  must fail where it cannot be honored; unset
##                                  is only the default, and the default must
##                                  degrade gracefully off-platform.
const ROUTE_FALLBACK := 1    # run the GDScript twin (the "0" hatch, or a lawful
                             #   kernel-less-platform fallback — see decide())
const ROUTE_ENGAGE   := 2    # kernel live + routing on — proceed to compile
const ROUTE_REFUSE   := -1   # loud refusal: a demand (=1), or a macOS build
                             #   whose shipped dylib is missing. Stored as mode -1.

static var _kernel_less_noted := false   # the once-per-boot fallback-note guard
static var _engaged_noted := false       # the once-per-boot engage-note guard

## The routing verdict a twin stores as its `_contour_mode`, decided from the
## boot flag + platform + kernel availability BEFORE it compiles its module.
## `tag` names the system for the diagnostic. Pure but for available()'s idempotent
## load and the once-per-boot warning. The returned int IS the stored mode, so the
## old magic numbers are preserved: ROUTE_ENGAGE(2)=engaged, ROUTE_FALLBACK(1)=
## GDScript twin, ROUTE_REFUSE(-1)=loud refusal (contour_status().engaged == mode 2
## still holds). A consumer routes only on ROUTE_ENGAGE, then compiles its module.
static func decide(tag: String) -> int:
	var flag := OS.get_environment("STRATA_CONTOUR")
	if flag == "0":
		return ROUTE_FALLBACK                # explicit escape hatch — GDScript twin
	if available():
		# Default-on engagement — announce it ONCE per boot (informational, not a
		# warning): the milestone default is live and the native kernel answered.
		# Bracket-prefixed so the smoke gate reads it as intentional logging; each
		# routed twin still carries its own `contour_status` for per-system proof.
		if not _engaged_noted:
			_engaged_noted = true
			print("[contour] routing ENGAGED (%s, native Lattice kernel live) — "
					% ("=1" if flag == "1" else "STRATA_CONTOUR default-on")
				+ "the sim tier runs through Contour; set STRATA_CONTOUR=0 to opt out")
		return ROUTE_ENGAGE                  # default-on (or =1) + kernel live
	# Routing is ON (unset default, or =1) but the native kernel is absent.
	if flag == "1" or OS.get_name() == "macOS":
		push_error("[%s] STRATA_CONTOUR routing is on (%s) but the Contour kernel "
				% [tag, "=1" if flag == "1" else "default-on"]
			+ "is unavailable (macOS dylib missing, or demanded off-platform) — "
			+ "refusing to silently run the GDScript twin")
		return ROUTE_REFUSE
	# Unset default on a kernel-less platform: the framework ships here, the
	# dylib does not. Fall back to the GDScript twin — but SAY SO, once per boot.
	if not _kernel_less_noted:
		_kernel_less_noted = true
		push_warning("[contour] no native kernel on %s (the dylib is macOS-only) — "
				% OS.get_name()
			+ "STRATA_CONTOUR defaults ON but falls back to the GDScript twin here. "
			+ "Set STRATA_CONTOUR=0 to opt out silently, or =1 to demand the kernel "
			+ "(which refuses when it is absent).")
	return ROUTE_FALLBACK

## Compile a Contour module from source text. Returns "" on success (the VM is
## live for call_fn), else a diagnostic (kernel unavailable, or a compile error).
## COLD path — call once at load, never on the tick.
func compile(src: String) -> String:
	if not _ensure_extension():
		return "contour: kernel unavailable (not macOS / dylib absent)"
	_kernel = ClassDB.instantiate("ContourKernel")
	if _kernel == null:
		return "contour: ContourKernel.instantiate failed"
	var err: String = _kernel.load_module(src)
	if err != "":
		_kernel = null
		return err
	return ""

## Compile a module from a res:// .ct file. Same return contract as compile();
## a missing file is a diagnostic, not a crash (content-empty-safe).
func compile_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "contour: no such module " + path
	return compile(FileAccess.get_file_as_string(path))

## True once a module is compiled and the VM is live.
func is_ready() -> bool:
	return _kernel != null and _kernel.is_loaded()

## Call `fn` with `args` (int/float/bool/String/Vector2/Vector3/Array/
## Dictionary/Basis in, the same kinds out — a bare String result crosses
## directly via the ABI's LAT_STR kind); returns the result Variant, or null
## when the VM isn't ready or the call errors. HOT path — the VM runs in-process on the
## caller's thread (one handle per thread; the valley sim tick is single-
## threaded, so one Contour per tick consumer is the model).
func call_fn(fn: String, args: Array) -> Variant:
	if _kernel == null:
		return null
	return _kernel.contour_call(fn, args)

## Advance the whole §6/§7 SYSTEM schedule one clock step of `dt` seconds over
## `world` (a Dictionary of dotted resource -> value); returns the resulting
## world Dictionary. The reserved clock keys (time.elapsed / time.dt) and each
## timed system's continuation (<System>.__time) ride IN the returned world, so
## feeding a returned world straight back in resumes every suspended timeline
## bit-identically (the replay law). Empty Dictionary when the VM isn't ready.
## HOT path — the sim-tick surface (call_fn is the ported-function surface).
func tick(world: Dictionary, dt: float) -> Dictionary:
	if _kernel == null:
		return {}
	return _kernel.contour_tick(world, dt)

## The module's SYSTEM manifest: an Array (declaration order) of
## {name, reads, writes, timed} dictionaries — the declared reads/writes a host
## seeds and applies honestly. Empty Array when the VM isn't ready. COLD path.
func systems() -> Array:
	if _kernel == null:
		return []
	return _kernel.contour_systems()


## --- the PERSISTENT HELD WORLD (substrate ladder Rung 2) ---------------------
## The held-world surface over the same compiled module: the VM keeps the world
## across ticks and world_tick crosses only the write-diff (O(writes)), where
## tick() re-marshals the whole world every call (O(world size)). One held world
## per host (the one-handle rule). See docs/SUBSTRATE.md §2 Rung 2.

## Create the held world, seeding it ONCE with `seed` (a dotted resource -> value
## Dictionary — seed every declared read the host will inject each tick). Returns
## true on success. COLD path — once at engage / on a save restore.
func world_create(seed: Dictionary) -> bool:
	if _kernel == null:
		return false
	return _kernel.contour_world_create(seed)


## True once a held world is live (created and not destroyed).
func world_ready() -> bool:
	return _kernel != null and _kernel.contour_world_ready()


## Advance the held world ONE clock step of `dt` seconds IN PLACE, first injecting
## `reads` (the declared reads the host computed fresh this tick; an empty
## Dictionary means no injection). Returns the WRITE-DIFF Dictionary — only the
## keys whose value moved (declared writes + reserved time.*/<System>.__time) —
## or an EMPTY Dictionary on error. HOT path — the sim-tick surface, held mode.
func world_tick(reads: Dictionary, dt: float) -> Dictionary:
	if _kernel == null:
		return {}
	return _kernel.contour_world_tick(reads, dt)


## The full held world (save/reconcile + the parity oracle). Empty Dictionary
## when no held world is live.
func world_snapshot() -> Dictionary:
	if _kernel == null:
		return {}
	return _kernel.contour_world_snapshot()


## Release the held world (a no-op if none live). The compiled module is untouched.
func world_destroy() -> void:
	if _kernel != null:
		_kernel.contour_world_destroy()


## ONE key of the held world — the O(1) READ-THROUGH (substrate Rung 3, the
## mirror-retirement move; docs/SUBSTRATE.md §2a). Returns a {key: value}
## Dictionary when the key is held, an EMPTY Dictionary {} when it is not — the
## same envelope world_tick/world_snapshot speak, so the present/absent
## distinction survives (a held `null` crosses as {key: null}, distinct from
## the unheld {}). Where world_snapshot copies the WHOLE world (O(world) — once
## per save/reconcile), this crosses O(1): a store that no longer keeps a SECOND
## copy of a held-owned key answers get_value HERE. Pure read, no advance. Empty
## when no held world is live (kernel absent / never engaged).
func world_read(key: String) -> Dictionary:
	if _kernel == null:
		return {}
	return _kernel.contour_world_read(key)


## Write ONE key of the held world IN PLACE — the O(1) WRITE-THROUGH (substrate
## Rung 3, the forcing-door move; docs/SUBSTRATE.md §2a). The next world_tick
## resumes from the written value, so a forcing door (`state set weather.state
## storm`) that targets a held-owned key writes the sim-tier truth HERE instead
## of the mirror — the forced value survives the next tick's read-through instead
## of being clobbered by held truth. Returns true on success, false when no held
## world is live (kernel absent / never engaged — the caller falls back to the
## plain mirror write for an unowned key).
func world_write(key: String, value: Variant) -> bool:
	if _kernel == null:
		return false
	return _kernel.contour_world_write(key, value)
