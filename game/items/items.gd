extends Node
## Items (autoload): item definitions from data/items/, and the player's
## inventory — which lives in WorldState ("player.inventory": {id: count})
## so it saves, signals, and participates in consequences for free.

var _defs: Dictionary = {}  # id -> record


func _ready() -> void:
	var records := Records.load_dir("res://data/items", {"id": TYPE_STRING, "name": TYPE_STRING})
	for key in records:
		_defs[records[key].id] = records[key]


func display_name(id: String) -> String:
	return _defs.get(id, {}).get("name", id)


func description(id: String) -> String:
	return _defs.get(id, {}).get("desc", "")


func add(id: String, count: int = 1) -> void:
	var inv: Dictionary = inventory().duplicate()
	inv[id] = int(inv.get(id, 0)) + count
	if inv[id] <= 0:
		inv.erase(id)
	WorldState.set_value("player.inventory", inv)


func count(id: String) -> int:
	return int(inventory().get(id, 0))


func inventory() -> Dictionary:
	return WorldState.get_value("player.inventory", {})
