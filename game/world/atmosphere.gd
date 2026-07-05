extends Node3D
## Ambient particle life around the player, all driven by clock + weather:
## - sand motes: always, drifting with the wind
## - glow motes: sparse pink lights after dark (the phenomenon, teasing)
## - moths: her moth painting fluttering among the trees at dusk

var _motes: GPUParticles3D
var _glow: GPUParticles3D
var _moths: GPUParticles3D

# The fog bank (the Elements): one broad FogVolume of 3D noise that
# DRIFTS along the wind through the player's area — morning dew fog is
# patchy and something you wade through, not a uniform tint. Density
# from Weather.fog_amount(); the global height fog carries the
# distance. Anchored LOW in world space (sea/valley floor), so on a
# mesa top you stand above it and watch it pool below.
var _fog_bank: FogVolume
var _fog_mat: FogMaterial
var _bank_drift := Vector2.ZERO


func _ready() -> void:
	_fog_bank = FogVolume.new()
	_fog_bank.size = Vector3(1500.0, 44.0, 1500.0)
	_fog_mat = FogMaterial.new()
	_fog_mat.density = 0.0
	var fnoise := FastNoiseLite.new()
	fnoise.seed = 77
	fnoise.frequency = 0.05
	var ntex := NoiseTexture3D.new()
	ntex.width = 48
	ntex.height = 48
	ntex.depth = 48
	ntex.seamless = true
	ntex.noise = fnoise
	_fog_mat.density_texture = ntex
	_fog_bank.material = _fog_mat
	add_child(_fog_bank)
	_motes = _make_particles(150, 6.0, 0.05, Color(0.9, 0.82, 0.68, 0.16), 0.6, 2.0)
	_glow = _make_particles(26, 9.0, 0.07, Color(0.95, 0.42, 0.56, 0.85), 0.15, 0.6)
	var glow_mat: StandardMaterial3D = _glow.draw_pass_1.surface_get_material(0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.91, 0.33, 0.48)
	glow_mat.emission_energy_multiplier = 2.2
	_moths = _make_particles(10, 9.0, 0.5, Color(1, 1, 1, 1), 0.8, 2.2,
			load("res://assets/paintings/moth.png"))


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		global_position = player.global_position
	var h: float = GameClock.solar_hours()  # creatures follow the sun, not the clock
	# The fog bank rides the wind; wrapped drift keeps it near the
	# player while the noise pattern visibly travels.
	var fog: float = Weather.fog_amount()
	_fog_mat.density = fog * 0.055
	if fog > 0.01:
		_bank_drift += Weather.wind_dir * (2.0 + 14.0 * Weather.wind) * delta
		_bank_drift = Vector2(wrapf(_bank_drift.x, -400.0, 400.0),
			wrapf(_bank_drift.y, -400.0, 400.0))
	_fog_bank.global_position = Vector3(
		global_position.x + _bank_drift.x, 11.0,
		global_position.z + _bank_drift.y)
	_motes.emitting = true
	_motes.speed_scale = 0.4 + Weather.wind * 1.6
	# Motes drift the way the wind actually blows.
	var mat := _motes.process_material as ParticleProcessMaterial
	mat.direction = Vector3(Weather.wind_dir.x, 0.05, Weather.wind_dir.y)
	_glow.emitting = h >= 19.5 or h < 5.0
	# The phenomenon prefers dark skies: sparse under a full moon.
	_glow.amount_ratio = 0.4 + 0.6 * (1.0 - GameClock.moon_light())
	_moths.emitting = h >= 16.5 and h < 23.0 and Weather.storminess < 0.4


func _make_particles(amount: int, lifetime: float, size: float, color: Color,
		vel_min: float, vel_max: float, tex: Texture2D = null) -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(35, 8, 35)
	mat.direction = Vector3(1, 0.05, 0.25)
	mat.spread = 60.0
	mat.initial_velocity_min = vel_min
	mat.initial_velocity_max = vel_max
	mat.gravity = Vector3.ZERO
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.6
	mat.turbulence_noise_scale = 4.0
	mat.scale_min = 0.7
	mat.scale_max = 1.3
	mat.color = color

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * (1.25 if tex else 1.0))
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if tex:
		draw_mat.albedo_texture = tex
	quad.material = draw_mat

	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.process_material = mat
	particles.draw_pass_1 = quad
	particles.visibility_aabb = AABB(Vector3(-50, -20, -50), Vector3(100, 40, 100))
	add_child(particles)
	return particles
