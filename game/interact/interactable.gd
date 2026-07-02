class_name Interactable
extends Area3D
## Something the player can target and use with E. The player finds these
## by proximity + facing (group "interactable"); the Area3D body is kept
## for future overlap-based detection and triggers.

@export var prompt := "Interact"

signal interacted(by: Node)


func _ready() -> void:
	add_to_group("interactable")


func interact(by: Node) -> void:
	interacted.emit(by)
