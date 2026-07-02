extends Node
## Spawns inhabitants from data/npcs/*.json records. One tier for now
## (everyone embodied); the abstract far-tier arrives with the village.

const NPC_SCENE := preload("res://game/npc/npc.tscn")
const DIR := "res://data/npcs"


func _ready() -> void:
	var records: Dictionary = Records.load_dir(DIR, {"id": TYPE_STRING, "schedule": TYPE_ARRAY})
	for key in records:
		var data: Dictionary = records[key]
		if data.schedule.is_empty():
			continue
		var npc := NPC_SCENE.instantiate()
		npc.schedule = data.schedule
		npc.npc_id = data.id
		npc.display_name = data.get("name", data.id)
		add_child(npc)
		var start: Dictionary = data.schedule.back()
		npc.global_position = Vector3(
			start.x, Terrain.height(start.x, start.z) + 0.5, start.z
		)
