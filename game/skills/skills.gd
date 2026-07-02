extends Node
## Skills (autoload): use-based progression, Skyrim-philosophy — you get
## better at what you do. A skill is a record (data/skills/): a name, a
## WorldState stat it reads, and level thresholds. No XP system exists
## apart from the world's own counters; levels are derived, so they save
## for free and can never desync.

const NUMERALS := ["", "I", "II", "III", "IV", "V"]

var _defs: Array = []  # records, sorted by filename


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
	var value := float(WorldState.get_value(def.stat, 0))
	var lvl := 0
	for t in def.thresholds:
		if value >= float(t):
			lvl += 1
	return lvl


## Progress toward the next level, 0..1 (1.0 when maxed).
func progress(def: Dictionary) -> float:
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
