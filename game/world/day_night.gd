extends Node
## Drives the sun and sky palette from GameClock. Day/night is a palette
## shift through keyframes, not just darkness — the sky is painted content.

@onready var sun: DirectionalLight3D = $"../Sun"
@onready var world_environment: WorldEnvironment = $"../WorldEnvironment"

# Keyframes: [hour, sky top, sky horizon, sun light color]
# Palette sampled from the style-reference painting (dawn/dusk pinks, red sun).
const KEYS := [
	[0.0, Color(0.08, 0.1, 0.17), Color(0.2, 0.17, 0.25), Color(1.0, 0.5, 0.4)],
	[5.0, Color(0.08, 0.1, 0.17), Color(0.2, 0.17, 0.25), Color(1.0, 0.5, 0.4)],
	[6.5, Color(0.976, 0.812, 0.827), Color(0.988, 0.933, 0.894), Color(1.0, 0.62, 0.5)],
	[9.0, Color(0.70, 0.80, 0.88), Color(0.89, 0.85, 0.78), Color(1.0, 0.878, 0.796)],
	[17.0, Color(0.70, 0.80, 0.88), Color(0.89, 0.85, 0.78), Color(1.0, 0.878, 0.796)],
	[19.5, Color(0.93, 0.62, 0.66), Color(1.0, 0.82, 0.72), Color(1.0, 0.45, 0.35)],
	[21.5, Color(0.08, 0.1, 0.17), Color(0.2, 0.17, 0.25), Color(1.0, 0.5, 0.4)],
	[24.0, Color(0.08, 0.1, 0.17), Color(0.2, 0.17, 0.25), Color(1.0, 0.5, 0.4)],
]


func _process(_delta: float) -> void:
	# Solar hours: seasonally warped so sunrise lands at canonical 6:00 —
	# the whole palette/arc below inherits real seasonal daylight.
	var h: float = GameClock.solar_hours()

	# Sun path: full circle around X; 6:00 rises, 12:00 zenith, 18:00 sets.
	sun.rotation.x = -(h - 6.0) / 24.0 * TAU
	var elevation := sin((h - 6.0) / 24.0 * TAU)
	sun.light_energy = clampf(elevation * 1.2, 0.0, 0.95) \
			* (1.0 - 0.55 * Weather.storminess)

	# Sky palette: lerp between bracketing keyframes.
	var a: Array = KEYS[0]
	var b: Array = KEYS[KEYS.size() - 1]
	for i in KEYS.size() - 1:
		if h >= KEYS[i][0] and h <= KEYS[i + 1][0]:
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var t: float = 0.0 if b[0] == a[0] else (h - a[0]) / (b[0] - a[0])

	var top: Color = a[1].lerp(b[1], t)
	var horizon: Color = a[2].lerp(b[2], t)
	sun.light_color = a[3].lerp(b[3], t)

	var mat: ShaderMaterial = world_environment.environment.sky.sky_material
	mat.set_shader_parameter("top_color", top)
	mat.set_shader_parameter("horizon_color", horizon)
	mat.set_shader_parameter("sun_color", sun.light_color)
	# Direction TO the sun; disc swells and reddens near the horizon.
	mat.set_shader_parameter("sun_dir", sun.global_basis.z)
	mat.set_shader_parameter("sun_size", 0.035 + 0.05 * (1.0 - clampf(absf(elevation) * 3.0, 0.0, 1.0)))
	mat.set_shader_parameter("night", clampf(-elevation * 4.0, 0.0, 1.0))
	mat.set_shader_parameter("moon_light", GameClock.moon_light())
	# The air (the Elements, height-fog pass 2026-07-05). Three layers:
	#  - clear-air distance haze: THIN, so landmarks read at 3km (the
	#    landmark law); storms still shroud everything.
	#  - height fog: the murk lives LOW — dew fog floods the sea, the
	#    strand, and the valley floor, and the mesa tops float clear
	#    above it (fog front + landmark law stop fighting).
	#  - volumetric banks near the player (Atmosphere drifts one along
	#    the wind) so morning fog is something you wade through, not a
	#    uniform tint.
	var env := world_environment.environment
	var fog := Weather.fog_amount()
	env.fog_light_color = horizon.lerp(Color(0.8, 0.7, 0.58), Weather.storminess * 0.6) \
		.lerp(Color(0.92, 0.88, 0.86), fog * 0.5)
	env.fog_density = lerpf(0.00022, 0.0045, Weather.storminess)
	env.fog_sky_affect = 0.3 + 0.5 * Weather.storminess  # sky survives dew fog
	env.fog_height = 8.0 + 18.0 * fog
	# Per-meter extinction INSIDE the layer: ~100m visibility at full
	# dew fog — wadeable murk, not a whiteout.
	env.fog_height_density = 0.004 + 0.03 * fog + 0.012 * Weather.storminess
	env.volumetric_fog_enabled = fog > 0.03
	# Subtle: the height fog carries the distance; volumetric only
	# textures the near murk (0.02+/m here whites out everything past
	# its 320m window — the invisible-mesa bug of the first fog pass).
	env.volumetric_fog_density = 0.001 + 0.006 * fog
	env.volumetric_fog_albedo = env.fog_light_color
	env.volumetric_fog_length = 320.0
