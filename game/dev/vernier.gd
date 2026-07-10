class_name Vernier
## Vernier (P4 — the cvar half of PLAN_ENGINE law 9, built valley-side so
## Datum inherits a working contract). CONTEXT: today's live tunables are
## ad-hoc — a shader global poked from scattered code, a debug key's
## toggle (WaterField's K), a per-system constant nobody can see without
## reading source. Vernier is ONE door onto all of it: register(name,
## type, default, setter, getter, doc) once, from the tunable's OWN file,
## and from then on anyone — a scene test, the link, a future Strata
## inspector — can list/get/set it by NAME instead of source-diving.
##
## Static-only — no autoload, no node, no scene tree dependency
## (dev_mode.gd's shape): a static Dictionary is the whole registry,
## name -> Entry. Nothing here runs on its own; every entry's setter/
## getter is a Callable the OWNING file supplied, so Vernier never
## touches engine state it doesn't already have a hand offered for.
##
## REGISTRATION IS PASSIVE: register() reads the tunable's CURRENT value
## once (through the getter, if one was given) and stores it — it never
## calls the setter. A game that registers a dozen tunables and never
## calls Vernier.set_value again behaves byte-identically to one that
## never loaded this file: nothing here can change a tunable on its own,
## only a caller naming it explicitly can. This is also why registration
## is safe to run from any `_ready()`, headless or not, before any other
## gate in that file — it has no order dependency on anything (LAZY: the
## registry only grows when an owning file's own boot reaches its own
## register() call; Vernier itself starts empty and inert).
##
## PROVENANCE (the ledger's ask): every Entry remembers who last set it
## and when. "boot" is the stamp register() itself lands (the initial
## snapshot); "link" is what a `vernier set` over StrataLink stamps;
## anything else is whatever tag a caller passes — the debug-key pattern
## (see WaterField._unhandled_input) calls Vernier.stamp() AFTER its own
## direct mutation, bookkeeping only, so the registry stays honest about
## a value it doesn't own the only door to without routing that mutation
## through Vernier's setter (the tunable's own setter/var stays the one
## behavioral truth either way).
##
## NO PERSISTENCE this rung — a committed-tunables story (surviving a
## save/reload) is a records/WorldState question for later; this registry
## is live-session only, by design, and says so rather than half-doing it.
##
## CALLABLE CAUTION (earned empirically this rung, worth inheriting):
## every register() call in this codebase binds a real named method —
## `Callable(self, "method_name")` — NEVER a GDScript lambda
## (`func(v): ...`). A lambda Callable stored in THIS file's static
## (process-lifetime) registry reliably crashed the engine at shutdown
## (`recursive_mutex lock failed: Invalid argument`, reproduced by
## bisection: a captureless lambda crashed identically to a self-
## capturing one, while an empty Callable() and a bound-method Callable
## both tore down clean) — a GDScript lambda apparently carries binding
## state that does not survive to the engine's own end-of-process static-
## var finalization the way a plain bound-method Callable does. Cheap to
## avoid (every tunable's setter/getter is a two/zero-line named method
## anyway) and worth stating loudly so Datum's host inherits the shape,
## not just the crash.
##
## THE DATUM CONTRACT (inherit verbatim — this is the whole wire, on
## purpose small enough to port to a Rust/Swift host without translation
## loss):
##   register(name: String, type: Variant.Type, default: Variant,
##            setter: Callable, getter: Callable = Callable(),
##            doc: String = "") -> void
##     `type` is one of TYPE_BOOL/TYPE_FLOAT/TYPE_INT/TYPE_STRING (the
##     Variant type constants already in every engine binding — no
##     parallel enum to keep in lockstep). `setter` takes exactly the
##     coerced value; `getter` (optional) takes nothing and returns the
##     live value — omit it only when the tunable has no live mirror to
##     read back (current then just tracks the last-known value Vernier
##     itself was told about). Duplicate names are a programmer error:
##     register() refuses the second registration and push_errors loud
##     rather than silently replacing a live setter underneath the first
##     caller.
##   list() -> Array[Entry], sorted by name (deterministic wire order).
##   get_value(name) -> Variant, refreshed through the getter if one
##     exists; null on an unknown name (has(name) disambiguates a
##     legitimately-null current value from "no such tunable").
##   set_value(name, raw: Variant, provenance: String) -> Variant
##     the ONE mutating door. `raw` may be wire text (a String — "true"/
##     "1.5"/"on") or an already-typed Variant a direct GDScript caller
##     supplies; either way it is coerced to the Entry's declared type
##     BEFORE the setter ever sees it, so no setter has to guard against
##     "on" vs 1 vs true meaning the same bool. Returns the value that
##     LANDED (read back through the getter when one exists, so a caller
##     never has to trust its own echo); null on an unknown name.
##   has(name) -> bool ; stamp(name, provenance) -> void (bookkeeping-only,
##     see PROVENANCE above) ; type_name(type) -> String ("bool"/"float"/
##     "int"/"string") for a human/wire-friendly render.
##
## Wired today (the proof, all passive until someone calls `set`):
##   water.fill_channels   bool   WaterField.fill_channels / set_fill()
##   sea.force_amp         float  SeaSwell.force_amp (>=0 pins amplitude)
##   sea.force_surf        float  SeaSwell.force_surf (>=0 pins surf boost)
##   weather.fog_override  float  Weather.fog_override (>=0 pins fog 0..1)


## One registered tunable. Plain data + two Callables — never serialized
## whole (the link renders a text line from its fields; see
## StrataLink._vernier), so field order/naming is free to evolve.
class Entry:
	var name: String
	var type: int          # a Variant.Type constant (TYPE_BOOL, ...)
	var default: Variant
	var current: Variant
	var setter: Callable
	var getter: Callable   # Callable() (not valid) when the tunable has
	                        # no live read-back; current is then the cache.
	var doc: String
	var provenance: String # "boot" | "link" | "debug_key" | caller's tag
	var set_at: float       # Time.get_unix_time_from_system() of the stamp


static var _registry: Dictionary = {}  # String name -> Entry


## Register a tunable. Passive (see file doc): reads the current value
## once through `getter` (or falls back to `default` when no getter was
## given) and stamps provenance "boot" — it never calls `setter`. Refuses
## a duplicate name loudly rather than silently replacing a live setter.
static func register(name: String, type: int, default: Variant,
		setter: Callable, getter: Callable = Callable(), doc: String = "") -> void:
	if _registry.has(name):
		push_error("Vernier.register: '%s' is already registered (programmer error — names are one door each)" % name)
		return
	var e := Entry.new()
	e.name = name
	e.type = type
	e.default = default
	e.current = getter.call() if getter.is_valid() else default
	e.setter = setter
	e.getter = getter
	e.doc = doc
	e.provenance = "boot"
	e.set_at = Time.get_unix_time_from_system()
	_registry[name] = e


## Every registered tunable, sorted by name — deterministic so a wire
## reply (or a test) never has to sort itself.
static func list() -> Array[Entry]:
	var names := _registry.keys()
	names.sort()
	var out: Array[Entry] = []
	for n: String in names:
		out.append(_registry[n])
	return out


static func has(name: String) -> bool:
	return _registry.has(name)


static func get_entry(name: String) -> Entry:
	return _registry.get(name)


## The live value, refreshed through the getter (if the tunable has one)
## so a read never lies even when something changed it outside Vernier.
## null on an unknown name — use has() to tell that apart from a
## legitimately-null tunable value.
static func get_value(name: String) -> Variant:
	var e: Entry = _registry.get(name)
	if e == null:
		return null
	if e.getter.is_valid():
		e.current = e.getter.call()
	return e.current


## Wire text (or an already-typed Variant) -> the Entry's declared type.
## Boolean wire text accepts the usual honest spellings; everything else
## is Godot's own float()/int()/String() coercion.
static func _coerce(type: int, raw: Variant) -> Variant:
	match type:
		TYPE_BOOL:
			if raw is String:
				return String(raw).to_lower() in ["1", "true", "on", "yes"]
			return bool(raw)
		TYPE_FLOAT:
			return float(raw)
		TYPE_INT:
			return int(raw)
		TYPE_STRING:
			return String(raw)
		_:
			return raw


## The ONE mutating door. Coerces `raw` to the Entry's declared type,
## calls its setter, stamps `provenance` + the wall time, and returns the
## value that LANDED (read back through the getter when one exists — the
## setter is free to clamp/reject, so the echo is never assumed). null on
## an unknown name; has(name) disambiguates that from a null landing.
static func set_value(name: String, raw: Variant, provenance: String) -> Variant:
	var e: Entry = _registry.get(name)
	if e == null:
		return null
	var value: Variant = _coerce(e.type, raw)
	e.setter.call(value)
	e.current = e.getter.call() if e.getter.is_valid() else value
	e.provenance = provenance
	e.set_at = Time.get_unix_time_from_system()
	return e.current


## Bookkeeping-only provenance stamp for a mutation that already happened
## through the tunable's OWN door (a debug key, a record load) rather
## than through set_value — refreshes `current` from the getter (so a
## later `vernier get` reads the truth) and records who did it, without
## ever calling a setter itself. A no-op on an unknown name.
static func stamp(name: String, provenance: String) -> void:
	var e: Entry = _registry.get(name)
	if e == null:
		return
	if e.getter.is_valid():
		e.current = e.getter.call()
	e.provenance = provenance
	e.set_at = Time.get_unix_time_from_system()


static func type_name(type: int) -> String:
	match type:
		TYPE_BOOL: return "bool"
		TYPE_FLOAT: return "float"
		TYPE_INT: return "int"
		TYPE_STRING: return "string"
		_: return "?"


## Test-only door (tests/run_tests.gd + scene_tests.gd load real game
## files that register real tunables into this SAME static registry —
## a fresh registry per test run would be nicer, but Vernier follows
## dev_mode.gd's precedent of static state tests reset explicitly rather
## than a construction-time wipe nobody else asked for). Clears
## everything; only ever called from tests.
static func _reset_for_test() -> void:
	_registry.clear()
