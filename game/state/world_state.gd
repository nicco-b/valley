extends Node
## WorldState (autoload): the single store for everything the world
## remembers about itself — flags, counters, values. The consequence
## backbone: dialogue conditions, NPC opinions, quest state, and the
## simulation all read and write here, nowhere else.
##
## Keys are dot-namespaced strings, lowercase:
##   npc.wanderer.met = true
##   npc.wanderer.encounters = 3
##   valley.bridge.repaired = true
##   time.day = 12
## Values are JSON-compatible (bool/int/float/String/Array/Dictionary).
## Everything here is saved and restored verbatim by SaveGame.

signal changed(key: String, value: Variant)

var _state: Dictionary = {}


func set_value(key: String, value: Variant) -> void:
	if _state.get(key) == value:
		return
	_state[key] = value
	changed.emit(key, value)


func get_value(key: String, default: Variant = null) -> Variant:
	return _state.get(key, default)


func set_flag(key: String) -> void:
	set_value(key, true)


func has_flag(key: String) -> bool:
	return _state.get(key, false) == true


func increment(key: String, by: int = 1) -> int:
	var value: int = int(_state.get(key, 0)) + by
	set_value(key, value)
	return value


## Full snapshot for the save system.
func snapshot() -> Dictionary:
	return _state.duplicate(true)


## Restore from a save. Replaces everything; emits no signals (loading is
## not a world event).
func restore(data: Dictionary) -> void:
	_state = data.duplicate(true)
