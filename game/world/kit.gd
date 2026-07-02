extends Node
## The placeable object kit (autoload). Place mode's palette reads this;
## cell records reference entries by id. Grows as her kit grows.

const ENTRIES := [
	{"id": "rock_large", "label": "Rock (large)", "path": "res://game/world/kit/rock_large.tscn"},
	{"id": "rock_med", "label": "Rock (medium)", "path": "res://game/world/kit/rock_med.tscn"},
	{"id": "tree_silly", "label": "Silly tree", "path": "res://game/world/kit/tree_silly.tscn"},
	{"id": "tree_palm", "label": "Bulb palm", "path": "res://game/world/kit/tree_palm.tscn"},
	{"id": "shrub", "label": "Barrel shrub", "path": "res://game/world/kit/shrub.tscn"},
	{"id": "stall_pink", "label": "Stall (pink)", "path": "res://game/world/kit/stall_pink.tscn"},
	{"id": "stall_teal", "label": "Stall (teal)", "path": "res://game/world/kit/stall_teal.tscn"},
	{"id": "crate", "label": "Crate", "path": "res://game/world/kit/crate.tscn"},
	{"id": "rug", "label": "Rug", "path": "res://game/world/kit/rug.tscn"},
]

var _by_id: Dictionary = {}


func _ready() -> void:
	for e in ENTRIES:
		_by_id[e.id] = load(e.path)


func scene(id: String) -> PackedScene:
	return _by_id.get(id)
