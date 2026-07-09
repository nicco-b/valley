extends Node
## Drives the sun and sky palette from GameClock. Day/night is a palette
## shift through keyframes, not just darkness — the sky is painted content.

@onready var sun: DirectionalLight3D = $"../Sun"
@onready var world_environment: WorldEnvironment = $"../WorldEnvironment"

const PALETTE_PATH := "res://data/sky/day_night.json"

# Keyframes: [hour, sky top, sky horizon, sun light color]. The real palette
# (painting-sampled, dawn/dusk pinks, red sun) is valley content at
# PALETTE_PATH (FW4); this is the neutral fallback a content-empty game
# boots with when that record is absent — an honest lit day (pale blue sky,
# warm white noon sun) falling to a dark but non-black night, no painting
# art baked in here. A flat two-key grey-both-ends curve makes noon look
# identical to midnight (the bug this replaces); a content-empty game must
# still boot with a sky that visibly lights the world.
const DEFAULT_KEYS := [
	[0.0, Color(0.04, 0.05, 0.08), Color(0.07, 0.08, 0.12), Color(0.2, 0.22, 0.3)],
	[5.5, Color(0.04, 0.05, 0.08), Color(0.07, 0.08, 0.12), Color(0.2, 0.22, 0.3)],
	[7.0, Color(0.55, 0.62, 0.78), Color(0.85, 0.78, 0.7), Color(1.0, 0.85, 0.72)],
	[12.0, Color(0.45, 0.68, 0.9), Color(0.78, 0.85, 0.9), Color(1.0, 0.97, 0.9)],
	[17.0, Color(0.45, 0.68, 0.9), Color(0.78, 0.85, 0.9), Color(1.0, 0.97, 0.9)],
	[19.0, Color(0.5, 0.5, 0.65), Color(0.88, 0.72, 0.6), Color(1.0, 0.7, 0.55)],
	[21.0, Color(0.04, 0.05, 0.08), Color(0.07, 0.08, 0.12), Color(0.2, 0.22, 0.3)],
	[24.0, Color(0.04, 0.05, 0.08), Color(0.07, 0.08, 0.12), Color(0.2, 0.22, 0.3)],
]

var keys: Array = DEFAULT_KEYS


func _ready() -> void:
	if FileAccess.file_exists(PALETTE_PATH):
		var rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
		if rec is Dictionary and rec.get("keys") is Array and rec["keys"].size() >= 2:
			var parsed: Array = []
			for k: Array in rec["keys"]:
				parsed.append([
					float(k[0]),
					Color(k[1][0], k[1][1], k[1][2]),
					Color(k[2][0], k[2][1], k[2][2]),
					Color(k[3][0], k[3][1], k[3][2]),
				])
			keys = parsed


func _process(_delta: float) -> void:
	# Solar hours: seasonally warped so sunrise lands at canonical 6:00 —
	# the whole palette/arc below inherits real seasonal daylight.
	var h: float = GameClock.solar_hours()

	# Sun path: full circle around X; 6:00 rises, 12:00 zenith, 18:00 sets.
	sun.rotation.x = -(h - 6.0) / 24.0 * TAU
	var elevation := sin((h - 6.0) / 24.0 * TAU)
	sun.light_energy = clampf(elevation * 1.2, 0.0, 0.95) \
			* (1.0 - 0.4 * Weather.storminess - 0.3 * Weather.cloud)

	# Sky palette: lerp between bracketing keyframes.
	var a: Array = keys[0]
	var b: Array = keys[keys.size() - 1]
	for i in keys.size() - 1:
		if h >= keys[i][0] and h <= keys[i + 1][0]:
			a = keys[i]
			b = keys[i + 1]
			break
	var t: float = 0.0 if b[0] == a[0] else (h - a[0]) / (b[0] - a[0])

	var top: Color = a[1].lerp(b[1], t)
	var horizon: Color = a[2].lerp(b[2], t)
	sun.light_color = a[3].lerp(b[3], t)

	var mat: ShaderMaterial = world_environment.environment.sky.sky_material
	mat.set_shader_parameter("top_color", top)
	mat.set_shader_parameter("horizon_color", horizon)
	mat.set_shader_parameter("sun_color", sun.light_color)

	# The water's hours (2026-07-05, Nicco's call: "pink only at golden
	# hours"): the pool's pink is the low sun's gift now — a bell around
	# sunrise and sunset in solar space; day water runs a quieter teal,
	# night a dark slate. The water shader mixes its palettes by these.
	var gold := maxf(1.0 - absf(h - 6.0) / 1.6, 0.0)
	gold = maxf(gold, 1.0 - absf(h - 18.0) / 1.6)
	gold = smoothstep(0.0, 1.0, gold)
	var night := 1.0 - smoothstep(-0.12, 0.05, elevation)
	RenderingServer.global_shader_parameter_set("water_gold", gold)
	RenderingServer.global_shader_parameter_set("water_night", night)
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
	env.fog_density = lerpf(0.00022, 0.0045, maxf(Weather.storminess, Weather.dust * 0.85))
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
	# Inside a pocket interior (the Threshold): the air of the room, not
	# the storm's — depth fog and volumetrics stand down so the pocket is
	# never fog-flooded or storm-washed. Presentation only: the sun keeps
	# its hour, Weather keeps its storm, and both are waiting outside.
	if Interiors.inside:
		env.fog_density = 0.0
		env.fog_height_density = 0.0
		env.volumetric_fog_enabled = false
