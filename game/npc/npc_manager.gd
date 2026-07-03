extends Node
## Spawns inhabitants from data/npcs/*.json records. One tier for now
## (everyone embodied); the abstract far-tier arrives with the village.
## Also the social seam: rumors travel when two inhabitants share a place
## for an hour — what one saw, soon the other knows.

const NPC_SCENE := preload("res://game/npc/npc.tscn")
const DIR := "res://data/npcs"
const CHAT_DISTANCE := 12.0  # close enough to talk for an hour


func _ready() -> void:
	GameClock.hour_tick.connect(_exchange_rumors)
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


func _exchange_rumors(_h: int) -> void:
	var npcs := get_children()
	for i in npcs.size():
		for j in range(i + 1, npcs.size()):
			var a: Node3D = npcs[i]
			var b: Node3D = npcs[j]
			if a.global_position.distance_to(b.global_position) > CHAT_DISTANCE:
				continue
			_tell_one(a, b)
			_tell_one(b, a)


## Pass one piece of news the listener lacks. "met_player" stays personal
## — meeting someone is not a rumor you can catch.
func _tell_one(teller: Node, listener: Node) -> void:
	for fact in teller.rumors:
		if str(fact) != "met_player" and not listener.knows(str(fact)):
			listener.learn(str(fact), teller.npc_id)
			return
