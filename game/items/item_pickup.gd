class_name ItemPickup
extends Interactable
## A takeable item in the world. `uid` makes the taking permanent:
## once taken, the flag "taken.<uid>" keeps it gone across saves.

@export var item_id := ""
@export var uid := ""


func _ready() -> void:
	super()
	prompt = "Take"
	if not uid.is_empty() and WorldState.has_flag("taken." + uid):
		queue_free()


func interact(by: Node) -> void:
	super(by)
	Items.add(item_id)
	HUD.notify("+ " + Items.display_name(item_id))
	if not uid.is_empty():
		WorldState.set_flag("taken." + uid)
	queue_free()
