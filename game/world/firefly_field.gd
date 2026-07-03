extends Node3D
## Spawns wild fireflies near the player at night; they thin out at dawn
## and never stray far. The catchable counterpart of the glow motes.

const MAX_WILD := 8
const SPAWN_INTERVAL := 1.4

var _timer := 0.0


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var h: float = GameClock.solar_hours()  # fireflies follow the sun, not the clock
	var night := h >= 19.5 or h < 5.0

	for fly in get_children():
		if not night or fly.global_position.distance_to(player.global_position) > 70.0:
			fly.queue_free()

	# Dark nights teem; full-moon nights thin out (real lunar phase).
	var max_wild := int(round(MAX_WILD * (0.5 + 0.7 * (1.0 - GameClock.moon_light()))))
	if night and get_child_count() < max_wild:
		_timer += delta
		if _timer >= SPAWN_INTERVAL:
			_timer = 0.0
			var ang := randf() * TAU
			var dist := randf_range(8.0, 32.0)
			var x: float = player.global_position.x + cos(ang) * dist
			var z: float = player.global_position.z + sin(ang) * dist
			var fly := WildFirefly.new()
			add_child(fly)
			fly.global_position = Vector3(
				x, Terrain.height(x, z) + randf_range(0.5, 1.9), z
			)
