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

# Rain curtains (phase C): one wall per rainy front within sight,
# hung under its leading edge — the approaching storm has a body.
const CURTAIN_SIGHT := 9000.0
var _curtains: Array[MeshInstance3D] = []
var _curtain_mats: Array[ShaderMaterial] = []

# Lightning (phase C): brief double-pulse flashes when heavy rain is
# near. Presentation-only randomness (never fingerprinted). Thunder
# audio is a named placeholder → his recordings (ASSETS_NEEDED).
var _bolt: OmniLight3D
var _bolt_t := 0.0
var _next_bolt := 8.0


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
	var curtain_shader := load("res://game/shaders/rain_curtain.gdshader")
	for i in 2:
		var quad := QuadMesh.new()
		quad.size = Vector2(14000.0, 480.0)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = curtain_shader
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2000.0
		mi.visible = false
		add_child(mi)
		_curtains.append(mi)
		_curtain_mats.append(mat)
	_bolt = OmniLight3D.new()
	_bolt.omni_range = 900.0
	_bolt.light_energy = 0.0
	_bolt.light_color = Color(0.92, 0.93, 1.0)
	_bolt.shadow_enabled = false
	add_child(_bolt)
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
	_update_curtains()
	_update_lightning(delta)
	_motes.emitting = true
	_motes.speed_scale = 0.4 + Weather.wind * 1.6
	# Motes drift the way the wind actually blows; gales thicken them.
	_motes.amount_ratio = clampf(0.5 + Weather.dust * 0.8, 0.5, 1.0)
	var mat := _motes.process_material as ParticleProcessMaterial
	mat.direction = Vector3(Weather.wind_dir.x, 0.05, Weather.wind_dir.y)
	_glow.emitting = h >= 19.5 or h < 5.0
	# The phenomenon prefers dark skies: sparse under a full moon.
	_glow.amount_ratio = 0.4 + 0.6 * (1.0 - GameClock.moon_light())
	_moths.emitting = h >= 16.5 and h < 23.0 and Weather.storminess < 0.4


## Hang a translucent rain wall under each rainy front's leading edge
## within sight — from the rim you SEE the storm's body coming.
func _update_curtains() -> void:
	var fp := Vector2(global_position.x, global_position.z)
	var ci := 0
	for f in Weather.fronts:
		if ci >= _curtains.size():
			break
		var k: Dictionary = Weather.KINDS[f.kind]
		if float(k.rain) < 0.2:
			continue
		var dir := Vector2(f.dx, f.dz)
		var to_edge: float = float(f.edge) - fp.dot(dir)
		if to_edge < -200.0 or to_edge > CURTAIN_SIGHT:
			continue  # already past us, or beyond sight
		var mi := _curtains[ci]
		var closest := fp + dir * to_edge
		mi.visible = true
		mi.global_position = Vector3(closest.x, 190.0, closest.y)
		# The wall runs along the front line (perpendicular to travel).
		mi.rotation.y = atan2(dir.x, dir.y)
		_curtain_mats[ci].set_shader_parameter("intensity",
			float(k.rain) * clampf(1.0 - to_edge / CURTAIN_SIGHT, 0.25, 1.0))
		ci += 1
	for i in range(ci, _curtains.size()):
		_curtains[i].visible = false


## Flashes when heavy rain is nearby: a double pulse from a random
## bearing, more frequent the heavier the rain.
func _update_lightning(delta: float) -> void:
	var menace: float = maxf(Weather.rain, Weather.storminess)
	if _bolt_t > 0.0:
		_bolt_t -= delta
		# Double pulse: bright, dip, brighter, out.
		var t := 0.45 - _bolt_t
		var e := 0.0
		if t < 0.08:
			e = 26.0 * (t / 0.08)
		elif t < 0.16:
			e = 8.0
		elif t < 0.3:
			e = 42.0 * (1.0 - (t - 0.16) / 0.14)
		_bolt.light_energy = maxf(e, 0.0)
		return
	_bolt.light_energy = 0.0
	if menace < 0.55:
		return
	_next_bolt -= delta
	if _next_bolt <= 0.0:
		var ang := randf() * TAU  # presentation-only randomness
		var d := 250.0 + randf() * 1100.0
		_bolt.global_position = global_position \
			+ Vector3(cos(ang) * d, 260.0 + randf() * 140.0, sin(ang) * d)
		_bolt_t = 0.45
		_next_bolt = 3.0 + randf() * 14.0 * (1.6 - menace)


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
