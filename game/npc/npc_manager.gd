extends Node
## Spawns inhabitants from data/npcs/*.json records. One tier for now
## (everyone embodied); the abstract far-tier arrives with the village.

const NPC_SCENE := preload("res://game/npc/npc.tscn")
const DIR := "res://data/npcs"


func _ready() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + f))
		if data == null or not data.has("schedule") or data.schedule.is_empty():
			continue
		var npc := NPC_SCENE.instantiate()
		npc.schedule = data.schedule
		add_child(npc)
		var start: Dictionary = data.schedule.back()
		npc.global_position = Vector3(
			start.x, Terrain.height(start.x, start.z) + 0.5, start.z
		)
