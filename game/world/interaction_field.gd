extends Node
## InteractionField (autoload): the world-remembers-you layer. Characters
## stamp disturbances (footsteps); the field renders them into a texture
## anchored to a FIXED world position (re-anchored only when the player
## strays far from it — a moving anchor makes prints swim). Published as
## global shader params trace_map/trace_center/trace_size.

const REGION_SIZE := 80.0  # meters covered by the texture
const TEX_SIZE := 512
const REANCHOR_DISTANCE := 22.0
const LIFETIME := 150.0  # seconds until a stamp fades out
const FADE_IN := 0.25
const MAX_STAMPS := 400
const AGING_INTERVAL := 0.35  # rebuild cadence when nothing new happened

# Desire paths (IDEAS ★): every footstep also leaves a trace in a
# long-memory wear layer — repeated walking wears visible trails that
# outlive the fresh prints. Wear decays over game-months, not seconds
# (selective memory: paths outlive seasons, not the world), and the map
# is capped — the faintest cells are forgotten first.
const WEAR_PER_STAMP := 0.04
const WEAR_DECAY_PER_HOUR := 0.0006  # ~2 months to fade an unwalked path
const WEAR_MIN := 0.02  # below this a cell is forgotten
const WEAR_RENDER := 0.4  # old paths stay faint so fresh prints keep contrast
const WEAR_MAX_CELLS := 8000

var _stamps: Array = []  # [Vector2 world xz, float time_placed]
var _wear: Dictionary = {}  # Vector2i 1m world cell -> accumulated wear
var _clock := 0.0
var _aging_accum := 0.0
var _anchor := Vector2.INF
var _dirty := true
var _image: Image
var _texture: ImageTexture
# The wear layer is nearly static, so it renders to its own base image
# only when it actually changes (new wear, hourly decay, re-anchor) —
# the frequent stamp rebuild just memcpys it in. Blobbing hundreds of
# wear cells every 0.35s forever was a permanent frame tax near paths.
var _wear_image: Image
var _wear_dirty := true
var _wear_cooldown := 0.0


func _ready() -> void:
	# Mipmapped: the terrain vertex shader reads a blurred level for the
	# ground-sinking displacement (sharp texels would shimmer).
	_image = Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RF)
	_wear_image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RF)
	_texture = ImageTexture.create_from_image(_image)
	RenderingServer.global_shader_parameter_set("trace_map", _texture)
	RenderingServer.global_shader_parameter_set("trace_size", REGION_SIZE)
	GameClock.hour_tick.connect(_age_wear)


## Walkers call this: long-memory wear only. Their visible fresh prints
## live in the granular SandField now — this field keeps what outlasts
## weather: the desire paths.
func wear_only(world_xz: Vector2) -> void:
	var cell := Vector2i(int(floor(world_xz.x)), int(floor(world_xz.y)))
	_wear[cell] = minf(float(_wear.get(cell, 0.0)) + WEAR_PER_STAMP, 1.0)
	_wear_dirty = true
	_dirty = true


## strength caps at 1.0 — a saturated stamp has no gradient, and no
## gradient means no rim, no shading, no depth (flat dark craters, the
## bug this replaces). Pressing harder = a WIDER print (radius), and wet
## ground presses deeper via the shader's displacement (ground_wetness),
## never by inflating the mask.
##
## Crowding guard: pacing, turning, and test-shuffling land many stamps
## in the same square meter, and overlapping stamps max-blend into a
## saturated PATCH — the flat dark blob again, by another road. Ground
## freshly pressed stays pressed; it doesn't stack.
const STAMP_SPACING := 0.4
const STAMP_FRESH_SECONDS := 20.0

func stamp(world_xz: Vector2, strength := 1.0, radius := 2) -> void:
	for s in _stamps:
		if _clock - s[1] < STAMP_FRESH_SECONDS \
				and s[0].distance_squared_to(world_xz) < STAMP_SPACING * STAMP_SPACING:
			return
	_stamps.append([world_xz, _clock, minf(strength, 1.0), radius])
	if _stamps.size() > MAX_STAMPS:
		_stamps.pop_front()
	var cell := Vector2i(int(floor(world_xz.x)), int(floor(world_xz.y)))
	_wear[cell] = minf(float(_wear.get(cell, 0.0)) + WEAR_PER_STAMP, 1.0)
	_wear_dirty = true  # rendered into the base at most 1/s
	_dirty = true


func _age_wear(_h: int) -> void:
	var doomed: Array = []
	for c in _wear:
		_wear[c] = float(_wear[c]) - WEAR_DECAY_PER_HOUR
		if _wear[c] < WEAR_MIN:
			doomed.append(c)
	for c in doomed:
		_wear.erase(c)
	_wear_dirty = true
	if _wear.size() > WEAR_MAX_CELLS:
		var vals: Array = _wear.values()
		vals.sort()
		var cut: float = vals[_wear.size() - WEAR_MAX_CELLS]
		for c in _wear.keys():
			if float(_wear[c]) <= cut:
				_wear.erase(c)
	_dirty = true


## Persistence (SaveGame carries the wear layer): world-anchored, string
## keyed for JSON.
func wear_snapshot() -> Dictionary:
	var out := {}
	for c in _wear:
		out["%d_%d" % [c.x, c.y]] = snappedf(_wear[c], 0.001)
	return out


func wear_restore(data: Dictionary) -> void:
	_wear.clear()
	for k in data:
		var parts := String(k).split("_")
		if parts.size() == 2:
			_wear[Vector2i(int(parts[0]), int(parts[1]))] = float(data[k])
	_wear_dirty = true
	_dirty = true


func _process(delta: float) -> void:
	# Sand behavior: the wind erases. Prints age with the wind — a storm
	# scrubs them in under a minute, a dead-calm evening keeps them long
	# — and the procedural ripples re-form over the erased ground.
	# (The wear layer is untouched: worn paths outlast weather.)
	_clock += delta * (0.5 + 2.0 * Weather.wind)
	_aging_accum += delta
	if _aging_accum >= AGING_INTERVAL:
		_aging_accum = 0.0
		_dirty = true  # fades advance

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	if _anchor == Vector2.INF or p.distance_to(_anchor) > REANCHOR_DISTANCE:
		_anchor = p
		_wear_dirty = true
		_dirty = true

	_wear_cooldown -= delta
	if _wear_dirty and _wear_cooldown <= 0.0:
		_wear_cooldown = 1.0
		_wear_dirty = false
		_render_wear_base()
		_dirty = true

	if _dirty:
		_dirty = false
		_rebuild()


## Render the permanent wear layer into its base image — called only
## when the wear actually changes, never on the stamp cadence.
func _render_wear_base() -> void:
	_wear_image.fill(Color(0, 0, 0))
	var px_per_m := TEX_SIZE / REGION_SIZE
	for c in _wear:
		var wuv := (Vector2(c) + Vector2(0.5, 0.5) - _anchor) * px_per_m \
				+ Vector2.ONE * (TEX_SIZE * 0.5)
		if wuv.x < -4.0 or wuv.y < -4.0 or wuv.x >= TEX_SIZE + 4.0 or wuv.y >= TEX_SIZE + 4.0:
			continue
		_blob(_wear_image, int(wuv.x), int(wuv.y), float(_wear[c]) * WEAR_RENDER)


func _rebuild() -> void:
	RenderingServer.global_shader_parameter_set("trace_center", _anchor)
	_image.copy_from(_wear_image)  # the static layer lands as one memcpy
	var px_per_m := TEX_SIZE / REGION_SIZE
	var alive: Array = []
	for s in _stamps:
		var age: float = _clock - s[1]
		if age > LIFETIME:
			continue
		alive.append(s)
		var strength: float = minf(age / FADE_IN, 1.0) * (1.0 - age / LIFETIME) * s[2]
		var uv: Vector2 = (s[0] - _anchor) * px_per_m + Vector2.ONE * (TEX_SIZE * 0.5)
		# r2 ≈ 0.3m: at a 0.7m stride, prints separate instead of merging
		# into a trench — a walked line reads as footsteps.
		_blob(_image, int(uv.x), int(uv.y), strength, s[3])
	_stamps = alive
	_image.generate_mipmaps()  # the vertex displacement reads a blurred level
	_texture.update(_image)


func _blob(img: Image, cx: int, cy: int, strength: float, radius := 4) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= TEX_SIZE or y >= TEX_SIZE:
				continue
			var falloff := smoothstep(1.0, 0.25, Vector2(dx, dy).length() / float(radius))
			if falloff <= 0.0:
				continue
			var v := maxf(img.get_pixel(x, y).r, strength * falloff)
			img.set_pixel(x, y, Color(v, 0, 0))
