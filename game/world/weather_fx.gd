extends GPUParticles3D
## Wind-blown dust around the player, driven by Weather.


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		global_position = player.global_position + Vector3(0.0, 4.0, 0.0)
	# The map is weather-exempt (a chart, not a window) — a gale's dust
	# column at the player marker would be the one FX left floating on it.
	# A pocket interior is exempt the same way (the Threshold): the storm
	# stays outside the walls, and Weather itself is never told.
	emitting = (Weather.dust > 0.25 or Weather.storminess > 0.35) \
			and not MapScreen.active and not Interiors.inside
	speed_scale = 0.5 + Weather.wind
