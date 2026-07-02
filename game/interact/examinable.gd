class_name Examinable
extends Interactable
## An Interactable that shows a line of text and optionally sets a
## WorldState flag the first time.

@export_multiline var text := ""
@export var flag := ""


func interact(by: Node) -> void:
	super(by)
	HUD.say("", text)
	if not flag.is_empty():
		WorldState.set_flag(flag)
