extends Node
## Spawns inhabitants from data/npcs/*.json records. One tier for now
## (everyone embodied); the abstract far-tier arrives with the village.

const NPC_SCENE := preload("res://game/npc/npc.tscn")
const DIR := "res://data/npcs"


func _ready() -> void:
	var records: Dictionary = Records.load_dir(DIR, {
		"id": TYPE_STRING, "home": TYPE_DICTIONARY,
		"needs": TYPE_DICTIONARY, "activities": TYPE_ARRAY,
	})
	for key in records:
		var data: Dictionary = records[key]
		if data.activities.is_empty():
			continue
		var npc := NPC_SCENE.instantiate()
		npc.setup(data)
		add_child(npc)
		npc.global_position = Vector3(
			data.home.x, Terrain.height(data.home.x, data.home.z) + 0.5, data.home.z
		)
