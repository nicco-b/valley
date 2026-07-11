extends Node
## Items (autoload): item definitions from data/items/, and the player's
## inventory — which lives in WorldState ("player.inventory": {id: count})
## so it saves, signals, and participates in consequences for free.

var _defs: Dictionary = {}  # id -> record


# --- Contour routing (PLAN_ENGINE E2, Mission D1b: the P1 RULES TRIO) ----------
## The inventory RULES (count/count_tag over the player.inventory dict + def table,
## and add's order-faithful transform of it) are ported to the Contour language
## (game/items/items.ct — byte-identical to datum's Plumb-certified port). When
## STRATA_CONTOUR=1 — a boot-time sim flag, read once,
## DevMode-independent, default OFF — each rule routes through the native VM
## (Contour.call_fn) instead of the GDScript twin below. Flag OFF is byte-identical
## GDScript (the shipping path). NO SILENT FALLBACK (the honesty law): flag ON with
## the kernel absent / the module uncompilable / a refused call is a LOUD
## push_error, never a quiet twin. Routed calls carry a counter (contour_status) so
## the scene test / four-run determinism matrix can prove the rules actually ran.
## These are pure QUERIES + an event-driven mutation, not a clock-ticked
## read-modify-write, so they route as call_fn functions — NOT a forced §6 system.
const _CONTOUR_MODULE := "res://game/items/items.ct"
## 0 unresolved · 1 off (flag unset) · 2 engaged (VM live) · -1 refused.
var _contour_mode := 0
var _contour: Contour = null
var _contour_calls := 0   # rule calls answered by Contour (the engaged-path probe)


func _ready() -> void:
	var records := Records.load_dir("res://data/items", {"id": TYPE_STRING, "name": TYPE_STRING})
	for key in records:
		_defs[records[key].id] = records[key]


## display_name's RULE is Plumb-certified (datum items.ct), but its in-game routing
## is DEFERRED: it returns a bare String, and a top-level string RESULT is not yet
## marshalable across the Contour C ABI (LatticeEmbed's `marshalableAsComposite`
## omits `.str`; strings INSIDE composites — add's dict, count_tag's tags — cross
## fine). It routes the day that one-line kernel increment + a dylib rebuild land.
func display_name(id: String) -> String:
	return _defs.get(id, {}).get("name", id)


func description(id: String) -> String:
	return _defs.get(id, {}).get("desc", "")


func add(id: String, count: int = 1) -> void:
	var inv: Dictionary = inventory()
	var vm := _route_contour()
	var out: Dictionary
	if vm != null:
		var r: Variant = vm.call_fn("add", [inv, id, count])
		if r == null:
			_refuse("add")
			return
		_contour_calls += 1
		out = r
	else:
		out = inv.duplicate()
		out[id] = int(out.get(id, 0)) + count
		if out[id] <= 0:
			out.erase(id)
	WorldState.set_value("player.inventory", out)


func count(id: String) -> int:
	var vm := _route_contour()
	if vm != null:
		var r: Variant = vm.call_fn("count", [inventory(), id])
		if r == null:
			_refuse("count")
			return 0
		_contour_calls += 1
		return int(r)
	return int(inventory().get(id, 0))


## The keyword law in the pack (DESIGN_QUESTS B15): things held whose
## records carry the tag — {"item_tag": ["food", 2]} is "any 2 things
## tagged food", identity-free like every radiant gate.
func count_tag(tag: String) -> int:
	var vm := _route_contour()
	if vm != null:
		var r: Variant = vm.call_fn("count_tag", [inventory(), _defs, tag])
		if r == null:
			_refuse("count_tag")
			return 0
		_contour_calls += 1
		return int(r)
	var total := 0
	var inv := inventory()
	for id: String in inv:
		var tags: Array = (_defs.get(id, {}) as Dictionary).get("tags", [])
		if tags.has(tag):
			total += int(inv[id])
	return total


func inventory() -> Dictionary:
	return WorldState.get_value("player.inventory", {})


## The live VM when routing is engaged, else null (flag off, or a loud refusal).
## Resolves once at first use (boot); flag-off is pure GDScript, forever identical.
func _route_contour() -> Contour:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour


func _contour_resolve() -> void:
	var verdict := Contour.decide("items")
	if verdict != Contour.ROUTE_ENGAGE:
		_contour_mode = verdict   # ROUTE_FALLBACK (GDScript twin) or ROUTE_REFUSE (loud, mode -1)
		return
	# Routing engaged — compile the module (a compile failure still refuses loudly).
	var vm := Contour.new()
	var err := vm.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[items] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour = vm
	_contour_mode = 2


func _refuse(fn: String) -> void:
	push_error("[items] STRATA_CONTOUR=1 but the '%s' rule was refused by the VM — " % fn
		+ "refusing to silently run the GDScript twin")


## Routing introspection for the scene test / matrix (proves the rules ran, not a
## silent fallback): the resolved mode, whether it engaged, and the call count.
func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls}
