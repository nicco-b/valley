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


## The keyword law in the pack (DESIGN_QUESTS B15): things held whose
## records carry the tag — {"item_tag": ["food", 2]} is "any 2 things
## tagged food", identity-free like every radiant gate.
func count_tag(tag: String) -> int:
	var total := 0
	var inv := inventory()
	for id: String in inv:
		var tags: Array = (_defs.get(id, {}) as Dictionary).get("tags", [])
		if tags.has(tag):
			total += int(inv[id])
	return total


func inventory() -> Dictionary:
	return WorldState.get_value("player.inventory", {})
