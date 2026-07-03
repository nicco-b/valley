extends Node
## SandField (autoload): the REAL deformation layer — a 4.7cm/px pressure
## field in a 24m window that follows the player, stamped with SHAPED
## foot/paw masks rotated to heading. The dense SandPatch mesh displaces
## by this field, so a footstep is an actual heel-and-toe pit with walls,
## not a round blob. (The coarse 80m InteractionField stays: it carries
## permanent desire-path wear and far prints; this field carries the
## close-up truth.)
##
## Published globals: deform_map, deform_center, deform_size. The terrain
## shader opens a hole under the patch (deform_center + DEFORM_HOLE);
## sand_patch.gd renders the dented ground there.

const REGION := 24.0  # meters covered by the field
const TEX := 512  # 4.7cm per pixel
const REANCHOR := 6.0  # re-center this often (snapped, so prints don't swim)
const LIFETIME := 150.0  # seconds until a print fades (wind-scaled aging)
const FADE_IN := 0.2
const MAX_STAMPS := 700
const AGING_INTERVAL := 0.3
const HOLE_RADIUS := 10.0  # where the patch replaces terrain (shader const too)

var _stamps: Array = []  # [Vector2 xz, clock, yaw, mask index, strength]
var _clock := 0.0
var _aging := 0.0
var _anchor := Vector2.INF
var _dirty := true
var _image: Image
var _texture: ImageTexture
var _masks: Array[Image] = []  # FOOT_L, FOOT_R, PAW, BOOT

enum Mask { FOOT_L, FOOT_R, PAW, BOOT }


func _ready() -> void:
	_image = Image.create(TEX, TEX, false, Image.FORMAT_RF)
	_texture = ImageTexture.create_from_image(_image)
	RenderingServer.global_shader_parameter_set("deform_map", _texture)
	RenderingServer.global_shader_parameter_set("deform_size", REGION)
	_masks = [
		_make_foot(false), _make_foot(true),
		_make_paw(), _make_boot(),
	]


## A soft heel + toe pad, the fox's bare foot. ~34cm long, mirrored for
## left/right so a walk line alternates naturally.
func _make_foot(mirror: bool) -> Image:
	var w := 5
	var h := 8
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	for y in h:
		for x in w:
			var p := Vector2((float(x) + 0.5) / w - 0.5, (float(y) + 0.5) / h - 0.5)
			if mirror:
				p.x = -p.x
			# Toe pad (front, slightly outward) + heel (rear, center).
			var toe := 1.0 - clampf(p.distance_to(Vector2(0.06, 0.22)) / 0.3, 0.0, 1.0)
			var heel := 1.0 - clampf(p.distance_to(Vector2(-0.03, -0.2)) / 0.26, 0.0, 1.0)
			var v := maxf(toe * 1.15, heel)
			img.set_pixel(x, y, Color(clampf(v, 0.0, 1.0), 0, 0))
	return img


## Four-toed paw for the hounds: smaller, rounder.
func _make_paw() -> Image:
	var s := 5
	var img := Image.create(s, s, false, Image.FORMAT_RF)
	for y in s:
		for x in s:
			var p := Vector2((float(x) + 0.5) / s - 0.5, (float(y) + 0.5) / s - 0.5)
			var pad := 1.0 - clampf(p.distance_to(Vector2(0.0, 0.08)) / 0.34, 0.0, 1.0)
			var toes := 1.0 - clampf(absf(p.y - 0.28) / 0.14 + absf(fposmod(p.x * 3.4 + 0.5, 1.0) - 0.5) * 0.8, 0.0, 1.0)
			img.set_pixel(x, y, Color(clampf(maxf(pad, toes * 0.8), 0.0, 1.0), 0, 0))
	return img


## The robot placeholders wear boots: a plain oval.
func _make_boot() -> Image:
	var w := 5
	var h := 7
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	for y in h:
		for x in w:
			var p := Vector2((float(x) + 0.5) / w - 0.5, (float(y) + 0.5) / h - 0.5)
			var v := 1.0 - clampf(p.length() / 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(smoothstep(0.0, 0.7, v), 0, 0))
	return img


## A shaped print: position, heading (the mask rotates to it), which
## mask, how hard. Crowding-guarded like the coarse field.
func stamp(world_xz: Vector2, yaw: float, mask: Mask, strength := 1.0) -> void:
	for s in _stamps:
		if _clock - s[1] < 15.0 and s[0].distance_squared_to(world_xz) < 0.05:
			return
	_stamps.append([world_xz, _clock, yaw, mask, minf(strength, 1.0)])
	if _stamps.size() > MAX_STAMPS:
		_stamps.pop_front()
	_dirty = true


func _process(delta: float) -> void:
	# The wind erases here too.
	_clock += delta * (0.5 + 2.0 * Weather.wind)
	_aging += delta
	if _aging >= AGING_INTERVAL:
		_aging = 0.0
		_dirty = true
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	if _anchor == Vector2.INF or p.distance_to(_anchor) > REANCHOR:
		_anchor = p.snappedf(REGION / TEX * 8.0)  # texel-aligned: no swimming
		_dirty = true
	RenderingServer.global_shader_parameter_set("deform_center", _anchor)
	if _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	_image.fill(Color(0, 0, 0))
	var px_per_m := TEX / REGION
	var alive: Array = []
	for s in _stamps:
		var age: float = _clock - s[1]
		if age > LIFETIME:
			continue
		alive.append(s)
		var strength: float = minf(age / FADE_IN, 1.0) * (1.0 - age / LIFETIME) * s[4]
		var uv: Vector2 = (s[0] - _anchor) * px_per_m + Vector2.ONE * (TEX * 0.5)
		_blit_mask(_masks[s[3]], int(uv.x), int(uv.y), s[2], strength)
	_stamps = alive
	_texture.update(_image)


## Rotate-blit a mask into the field with max blending — a real footprint
## shape pressed at the walker's heading. Masks are ~5x8px; the rotation
## loop touches ~120px per stamp.
func _blit_mask(mask: Image, cx: int, cy: int, yaw: float, strength: float) -> void:
	var mw := mask.get_width()
	var mh := mask.get_height()
	var half := maxi(mw, mh)  # rotated bounds
	var c := cos(-yaw)
	var s := sin(-yaw)
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= TEX or y >= TEX:
				continue
			# Inverse-rotate into mask space.
			var mx := c * dx - s * dy + mw * 0.5
			var my := s * dx + c * dy + mh * 0.5
			if mx < 0.0 or my < 0.0 or mx >= mw or my >= mh:
				continue
			var v: float = mask.get_pixel(int(mx), int(my)).r * strength
			if v <= 0.0:
				continue
			var prev := _image.get_pixel(x, y).r
			if v > prev:
				_image.set_pixel(x, y, Color(v, 0, 0))
