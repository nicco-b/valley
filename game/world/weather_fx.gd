extends GPUParticles3D
## Wind-blown dust around the player, driven by Weather.


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		global_position = player.global_position + Vector3(0.0, 4.0, 0.0)
	emitting = Weather.storminess > 0.35
	speed_scale = 0.5 + Weather.wind
