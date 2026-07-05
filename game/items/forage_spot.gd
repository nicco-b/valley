class_name ForageSpot
extends Interactable
## A gatherable plant (the Elements meeting the satchel): spawned by the
## world streamer from flora species records that carry a `yields` item.
## Gathering adds the item, feeds the Foraging skill's counter, and
## wounds the cell's flora state (FloraLife.harvest_at) — fewer spots
## and thinner cover until the sim regrows it. Honest harvest: the spot
## returns because the land healed, never because the cell reset.

var item_id := ""


func _ready() -> void:
	super()
	prompt = "Gather"


func interact(by: Node) -> void:
	super(by)
	Items.add(item_id)
	WorldState.increment("player.items_taken")
	HUD.notify("+ " + Items.display_name(item_id))
	FloraLife.harvest_at(global_position.x, global_position.z)
	queue_free()
