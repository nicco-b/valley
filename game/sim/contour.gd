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

## Call `fn` with `args` (int/float/bool/Vector2/Vector3/Array/Dictionary/Basis
## in, the same kinds out); returns the result Variant, or null when the VM
## isn't ready or the call errors. HOT path — the VM runs in-process on the
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
