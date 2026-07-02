extends Node3D
## The deployed swarm: released fireflies orbit the player, and one
## shared light grows with their number — more bugs, more light.
## Deployed count persists via WorldState (satchel count is inventory).

var _flies: Array = []  # [mesh, phase, radius, speed, color]
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	top_level = true
	_light = OmniLight3D.new()
	_light.light_energy = 0.0
	_light.omni_range = 6.0
	add_child(_light)
	# Restore the swarm after the save loads (deployed ≠ satchel).
	await get_tree().process_frame
	await get_tree().process_frame
	for i in int(WorldState.get_value("player.fireflies_deployed", 0)):
		_spawn_fly()


func count() -> int:
	return _flies.size()


func deploy() -> void:
	_spawn_fly()
	WorldState.set_value("player.fireflies_deployed", _flies.size())


func recall_all() -> int:
	var n := _flies.size()
	for f in _flies:
		f[0].queue_free()
	_flies.clear()
	WorldState.set_value("player.fireflies_deployed", 0)
	_update_light()
	return n


func _spawn_fly() -> void:
	var color := WildFirefly.random_color()
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.6
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = _base() + Vector3(0, 1.2, 0)
	_flies.append([mi, randf() * TAU, randf_range(0.7, 1.6), randf_range(0.5, 1.1), color])
	_update_light()


func _update_light() -> void:
	var n := _flies.size()
	_light.light_energy = minf(n, 10.0) * 0.38
	_light.omni_range = 6.0 + minf(n, 10.0) * 2.0
	if n > 0:
		var avg := Color(0, 0, 0)
		for f in _flies:
			avg += f[4]
		_light.light_color = avg * (1.0 / n)


func _base() -> Vector3:
	return (get_parent() as Node3D).global_position


func _process(delta: float) -> void:
	if _flies.is_empty():
		return
	_t += delta
	var base := _base()
	var blend := 1.0 - exp(-6.0 * delta)
	for f in _flies:
		var target := base + Vector3(
			cos(_t * f[3] + f[1]) * f[2],
			1.15 + sin(_t * 1.7 + f[1] * 2.0) * 0.28,
			sin(_t * f[3] + f[1]) * f[2]
		)
		f[0].global_position = f[0].global_position.lerp(target, blend)
	_light.global_position = base + Vector3(0, 1.3, 0)
