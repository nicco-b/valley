extends Node
## InteractionField (autoload): the world-remembers-you layer. Characters
## stamp disturbances (footsteps) as they move; the field renders them
## into a texture region centered on the player and publishes it as
## global shader parameters (trace_map/trace_center/trace_size) that
## terrain — and later snow, grass, water — read. v1 effect: darkened
## sand trails that fade over a couple of minutes.

const REGION_SIZE := 80.0  # meters covered by the texture
const TEX_SIZE := 256
const LIFETIME := 150.0  # seconds until a stamp fades out
const MAX_STAMPS := 600
const REBUILD_INTERVAL := 0.15

var _stamps: Array = []  # [Vector2 world xz, float time_placed]
var _clock := 0.0
var _rebuild_accum := 0.0
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


func _process(delta: float) -> void:
	_clock += delta
	_rebuild_accum += delta
	if _rebuild_accum < REBUILD_INTERVAL:
		return
	_rebuild_accum = 0.0

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var center := Vector2(player.global_position.x, player.global_position.z)
	RenderingServer.global_shader_parameter_set("trace_center", center)

	_image.fill(Color(0, 0, 0))
	var px_per_m := TEX_SIZE / REGION_SIZE
	var alive: Array = []
	for s in _stamps:
		var age: float = _clock - s[1]
		if age > LIFETIME:
			continue
		alive.append(s)
		var strength := 1.0 - age / LIFETIME
		var uv: Vector2 = (s[0] - center) * px_per_m + Vector2.ONE * (TEX_SIZE * 0.5)
		_blob(int(uv.x), int(uv.y), strength)
	_stamps = alive
	_texture.update(_image)


func _blob(cx: int, cy: int, strength: float) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= TEX_SIZE or y >= TEX_SIZE:
				continue
			var falloff := 1.0 - (Vector2(dx, dy).length() / 3.0)
			if falloff <= 0.0:
				continue
			var v := maxf(_image.get_pixel(x, y).r, strength * falloff)
			_image.set_pixel(x, y, Color(v, 0, 0))
