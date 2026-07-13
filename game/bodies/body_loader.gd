class_name BodyLoader
extends Node3D
## The Body node's script (FW4): reads a body record and instances its
## mesh as a child named "Model", the job the scene's ext_resource embed
## used to do. Attached to the "Body" node of a character scene
## (player.tscn, villager_body.tscn); the `record` property names which
## body record to wear.
##
## ORDERING: Godot readies children before parents, so this node's _ready
## runs — and adds Model — BEFORE the character root's _ready, where the
## `@onready var _anim := $Body/Model/AnimationPlayer` lines resolve. The
## model is in the tree by the time anyone reaches for it, exactly as the
## embedded instance was. A record that fails to load leaves Body empty
## and logs loudly (BodyData) rather than crashing the boot.

## The body record this Body wears — a res://data/bodies/*.json path. Set
## per-scene in the .tscn (player.tscn -> player.json, villager_body.tscn
## -> villager.json), so one generic loader serves every body.
@export var record: String = ""


func _ready() -> void:
	if record.is_empty():
		push_error("[body_loader] no record set on %s" % get_path())
		return
	var model := BodyData.instantiate_model(BodyData.load(record))
	if model != null:
		add_child(model)
