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
	[9.0, Color(0.78, 0.86, 0.92), Color(0.95, 0.93, 0.89), Color(1.0, 0.878, 0.796)],
	[17.0, Color(0.78, 0.86, 0.92), Color(0.95, 0.93, 0.89), Color(1.0, 0.878, 0.796)],
	[19.5, Color(0.93, 0.62, 0.66), Color(1.0, 0.82, 0.72), Color(1.0, 0.45, 0.35)],
	[21.5, Color(0.08, 0.1, 0.17), Color(0.2, 0.17, 0.25), Color(1.0, 0.5, 0.4)],
	[24.0, Color(0.08, 0.1, 0.17), Color(0.2, 0.17, 0.25), Color(1.0, 0.5, 0.4)],
]


func _process(_delta: float) -> void:
	var h: float = GameClock.hours

	# Sun path: full circle around X; 6:00 rises, 12:00 zenith, 18:00 sets.
	sun.rotation.x = -(h - 6.0) / 24.0 * TAU
	var elevation := sin((h - 6.0) / 24.0 * TAU)
	sun.light_energy = clampf(elevation * 1.4, 0.0, 1.2)

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

	var mat: ProceduralSkyMaterial = world_environment.environment.sky.sky_material
	mat.sky_top_color = top
	mat.sky_horizon_color = horizon
	mat.ground_horizon_color = horizon
	mat.ground_bottom_color = horizon.darkened(0.15)
	world_environment.environment.fog_light_color = horizon
