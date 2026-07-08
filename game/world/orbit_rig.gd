class_name OrbitRig
extends RefCounted
## The shared orbit camera (the Toolkit's viewer posture + the map): the
## camera rides spherical coords around a target — LMB-drag orbits, wheel
## or pinch zooms, WASD pans the target in the camera's ground plane.
## One rig, two hands (Toolkit orbit view, the map screen), so the feel
## can never drift between Strata's preview and the in-game map.

var target := Vector3.ZERO
var azimuth := 0.7
var elevation := 0.55
var distance := 19000.0
var min_distance := 60.0
var max_distance := 40000.0


## Frame the whole world tile — the boot posture of the viewer and the
## opening posture of the map: the island chain in one steady look.
func frame_tile() -> void:
	var size := Terrain.world_tile_size()
	if size <= 0.0:
		size = 16384.0
	target = Vector3.ZERO
	azimuth = 0.7
	elevation = 0.85  # steep chart angle: the tile fills the frame
	distance = clampf(size * 1.05, min_distance, max_distance)


## Offer an input event to the rig. Drag orbits (gated by allow_drag so a
## pen can own LMB), wheel/pinch zooms. Returns true when consumed.
func handle_input(event: InputEvent, allow_drag := true) -> bool:
	if allow_drag and event is InputEventMouseMotion \
			and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		azimuth -= event.relative.x * 0.008
		elevation = clampf(elevation + event.relative.y * 0.008, 0.05, 1.5)
		return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance * 0.85, min_distance)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance / 0.85, max_distance)
			return true
	elif event is InputEventMagnifyGesture:
		distance = clampf(distance / event.factor, min_distance, max_distance)
		return true
	return false


## WASD: pan the target in the camera's ground plane, zoom-scaled.
func pan(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		return
	var fwd := Vector3(-sin(azimuth), 0.0, -cos(azimuth))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	target += (right * dir.x + fwd * -dir.y) * distance * 0.4 * delta


## Seat the camera on the spherical ride (call each frame while active).
func apply(cam: Camera3D) -> void:
	cam.far = maxf(8000.0, distance * 4.0)
	var off := Vector3(
		distance * cos(elevation) * sin(azimuth),
		distance * sin(elevation),
		distance * cos(elevation) * cos(azimuth))
	cam.global_position = target + off
	cam.look_at(target, Vector3.UP)


## The chart air (the map-screen lesson): the world's own environment
## minus the fogs — at tile-framing distance the honest haze whites out
## the whole view. Sky, sun, tonemap survive, so time-of-day and weather
## still READ without ever obscuring the ground. Faint LONG-range fog
## only: the tile stays crisp, while the raw beyond-the-world (far-LOD
## seabed past the sea disc) fades out instead of reading as beige slabs.
static func chart_environment(world_env: Environment) -> Environment:
	var chart := Environment.new() if world_env == null \
			else world_env.duplicate() as Environment
	chart.fog_enabled = true
	chart.fog_density = 0.000025
	chart.fog_height_density = 0.0
	chart.fog_aerial_perspective = 0.0
	chart.fog_sky_affect = 0.0
	chart.volumetric_fog_enabled = false
	return chart
