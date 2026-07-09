extends Node
## The placeable object kit (autoload). Place mode's palette reads this;
## cell records reference entries by id. Grows as her kit grows.

## Legacy id->scene entries retired (cards, not ENTRIES, are the only
## catalog now) — kept as [] so scene_for()'s fallback lookup stays valid
## for any record still holding a bare id instead of a res:// path.
const ENTRIES := []

var _by_id: Dictionary = {}


func _ready() -> void:
	for e in ENTRIES:
		if ResourceLoader.exists(e.path):
			_by_id[e.id] = load(e.path)


## Resolve a cell record's `kit` field to a scene. Card-driven placements
## store a res:// file (a .glb the Cards catalog resolved, or a .tscn); legacy
## records store a Kit.ENTRIES id. This handles both, so retiring a placeholder
## (new file in the same slot) is transparent and old placements keep working.
func scene_for(kit_ref: String) -> PackedScene:
	if kit_ref.begins_with("res://"):
		var res = load(kit_ref)
		return res if res is PackedScene else null
	return _by_id.get(kit_ref)
