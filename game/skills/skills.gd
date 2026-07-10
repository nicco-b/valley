extends Node
## Skills (autoload): use-based progression, Skyrim-philosophy — you get
## better at what you do. A skill is a record (data/skills/): a name, a
## WorldState stat it reads, and level thresholds. No XP system exists
## apart from the world's own counters; levels are derived, so they save
## for free and can never desync.

const NUMERALS := ["", "I", "II", "III", "IV", "V"]

var _defs: Array = []  # records, sorted by filename


# --- Contour routing (PLAN_ENGINE E2, Mission D1b: the P1 RULES TRIO) ----------
## The progression RULES (_level_for/progress — the derived level and its 0..1
## progress from a WorldState stat value + the skill record) are ported to the
## Contour language (game/skills/skills.ct — byte-identical to datum's
## Plumb-certified port). When STRATA_CONTOUR=1 (a boot-time sim flag, read once,
## DevMode-independent, default OFF) each derivation routes through the native VM
## (Contour.call_fn) instead of the GDScript twin. Flag OFF is byte-identical
## GDScript. NO SILENT FALLBACK: flag ON with the kernel absent / uncompilable /
## a refused call is a LOUD push_error, never a quiet twin. The routed calls carry
## a counter (contour_status). Levels are pure DERIVATIONS (not a clock-ticked
## RMW), so they route as call_fn functions — NOT a forced §6 system; the
## `changed` signal handler + its HUD.notify toast STAY GDScript glue.
const _CONTOUR_MODULE := "res://game/skills/skills.ct"
## 0 unresolved · 1 off (flag unset) · 2 engaged (VM live) · -1 refused.
var _contour_mode := 0
var _contour: Contour = null
var _contour_calls := 0


func _ready() -> void:
	var records := Records.load_dir("res://data/skills", {
		"id": TYPE_STRING, "name": TYPE_STRING,
		"stat": TYPE_STRING, "thresholds": TYPE_ARRAY,
	})
	var keys := records.keys()
	keys.sort()
	for k in keys:
		_defs.append(records[k])
	WorldState.changed.connect(_on_state_changed)


func defs() -> Array:
	return _defs


func level(id: String) -> int:
	for def in _defs:
		if def.id == id:
			return _level_for(def)
	return 0


func _level_for(def: Dictionary) -> int:
	var vm := _route_contour()
	if vm != null:
		var r: Variant = vm.call_fn("_level_for", [{def.stat: WorldState.get_value(def.stat, 0)}, def])
		if r == null:
			_refuse("_level_for")
			return 0
		_contour_calls += 1
		return int(r)
	var value := float(WorldState.get_value(def.stat, 0))
	var lvl := 0
	for t in def.thresholds:
		if value >= float(t):
			lvl += 1
	return lvl


## Progress toward the next level, 0..1 (1.0 when maxed).
func progress(def: Dictionary) -> float:
	var vm := _route_contour()
	if vm != null:
		var r: Variant = vm.call_fn("progress", [{def.stat: WorldState.get_value(def.stat, 0)}, def])
		if r == null:
			_refuse("progress")
			return 0.0
		_contour_calls += 1
		return float(r)
	var lvl := _level_for(def)
	if lvl >= def.thresholds.size():
		return 1.0
	var prev := 0.0 if lvl == 0 else float(def.thresholds[lvl - 1])
	var next := float(def.thresholds[lvl])
	var value := float(WorldState.get_value(def.stat, 0))
	return clampf((value - prev) / (next - prev), 0.0, 1.0)


func _on_state_changed(key: String, _value: Variant) -> void:
	for def in _defs:
		if def.stat != key:
			continue
		var lvl := _level_for(def)
		var notified_key := "skill.%s.notified" % def.id
		if lvl > int(WorldState.get_value(notified_key, 0)):
			WorldState.set_value(notified_key, lvl)
			HUD.notify("%s deepens — %s" % [def.name, NUMERALS[lvl]])


## The live VM when routing is engaged, else null (flag off, or a loud refusal).
func _route_contour() -> Contour:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour


func _contour_resolve() -> void:
	if OS.get_environment("STRATA_CONTOUR") != "1":
		_contour_mode = 1
		return
	if not Contour.available():
		push_error("[skills] STRATA_CONTOUR=1 but the Contour kernel is unavailable "
			+ "(not macOS / dylib absent) — refusing to silently run the GDScript twin")
		_contour_mode = -1
		return
	var vm := Contour.new()
	var err := vm.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[skills] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour = vm
	_contour_mode = 2


func _refuse(fn: String) -> void:
	push_error("[skills] STRATA_CONTOUR=1 but the '%s' rule was refused by the VM — " % fn
		+ "refusing to silently run the GDScript twin")


func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls}
