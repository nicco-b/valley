extends Node
## The placeable object kit (autoload). Place mode's palette reads this;
## cell records reference entries by id. Grows as her kit grows.

const ENTRIES := [
	{"id": "rock_large", "label": "Rock (large)", "path": "res://game/world/kit/rock_large.tscn"},
	{"id": "rock_med", "label": "Rock (medium)", "path": "res://game/world/kit/rock_med.tscn"},
	{"id": "tree_silly", "label": "Silly tree", "path": "res://game/world/kit/tree_silly.tscn"},
	{"id": "tree_palm", "label": "Bulb palm", "path": "res://game/world/kit/tree_palm.tscn"},
	{"id": "shrub", "label": "Barrel shrub", "path": "res://game/world/kit/shrub.tscn"},
]

var _by_id: Dictionary = {}


func _ready() -> void:
	for e in ENTRIES:
		_by_id[e.id] = load(e.path)


func scene(id: String) -> PackedScene:
	return _by_id.get(id)


## Resolve a cell record's `kit` field to a scene. Card-driven placements
## store a res:// file (a .glb the Cards catalog resolved, or a .tscn); legacy
## records store a Kit.ENTRIES id. This handles both, so retiring a placeholder
## (new file in the same slot) is transparent and old placements keep working.
func scene_for(kit_ref: String) -> PackedScene:
	if kit_ref.begins_with("res://"):
		var res = load(kit_ref)
		return res if res is PackedScene else null
	return _by_id.get(kit_ref)
