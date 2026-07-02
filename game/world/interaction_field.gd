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

var _stamps: Array = []  # [Vector2 world xz, float time_placed]
var _clock := 0.0
var _aging_accum := 0.0
var _anchor := Vector2.INF
var _dirty := true
var _image: Image
var _texture: ImageTexture


func _ready() -> void:
	_image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RF)
	_texture = ImageTexture.create_from_image(_image)
	RenderingServer.global_shader_parameter_set("trace_map", _texture)
	RenderingServer.global_shader_parameter_set("trace_size", REGION_SIZE)


func stamp(world_xz: Vector2) -> void:
	_stamps.append([world_xz, _clock])
	if _stamps.size() > MAX_STAMPS:
		_stamps.pop_front()
	_dirty = true


func _process(delta: float) -> void:
	_clock += delta
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
		_dirty = true

	if _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	RenderingServer.global_shader_parameter_set("trace_center", _anchor)
	_image.fill(Color(0, 0, 0))
	var px_per_m := TEX_SIZE / REGION_SIZE
	var alive: Array = []
	for s in _stamps:
		var age: float = _clock - s[1]
		if age > LIFETIME:
			continue
		alive.append(s)
		var strength := minf(age / FADE_IN, 1.0) * (1.0 - age / LIFETIME)
		var uv: Vector2 = (s[0] - _anchor) * px_per_m + Vector2.ONE * (TEX_SIZE * 0.5)
		_blob(int(uv.x), int(uv.y), strength)
	_stamps = alive
	_texture.update(_image)


func _blob(cx: int, cy: int, strength: float) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= TEX_SIZE or y >= TEX_SIZE:
				continue
			var falloff := smoothstep(1.0, 0.25, Vector2(dx, dy).length() / 4.0)
			if falloff <= 0.0:
				continue
			var v := maxf(_image.get_pixel(x, y).r, strength * falloff)
			_image.set_pixel(x, y, Color(v, 0, 0))
