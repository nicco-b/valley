extends CanvasLayer
## The map (autoload). M toggles. Rendered from Terrain.height over the
## valley area — the functional map that her illustrated map will one day
## be traced from. Re-renders after god-mode terrain edits.

const WORLD := Rect2(-250, -800, 620, 1060)  # world-space area shown (x, z)
const IMG_W := 372
const IMG_H := 636
const COLOR_LOW := Color(0.92, 0.88, 0.80)
const COLOR_HIGH := Color(0.66, 0.49, 0.30)
const COLOR_WATER := Color(0.93, 0.62, 0.66)
const MARKS := [["Shrine", Vector2(120, -620)], ["Pond", Vector2(70, -310)]]

var _dirty := true
var _map_rect: TextureRect
var _markers: Control


func _ready() -> void:
	layer = 10
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.08, 0.10, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_map_rect = TextureRect.new()
	_map_rect.set_anchors_preset(Control.PRESET_CENTER)
	_map_rect.custom_minimum_size = Vector2(IMG_W, IMG_H) * 0.92
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_map_rect)

	_markers = Control.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_rect.add_child(_markers)
	_markers.draw.connect(_draw_markers)

	Terrain.edited.connect(func(_r: Rect2) -> void: _dirty = true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		visible = not visible
		if visible and _dirty:
			_render()


func _process(_delta: float) -> void:
	if visible:
		_markers.queue_redraw()


func _render() -> void:
	var img := Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGB8)
	for py in IMG_H:
		var wz := WORLD.position.y + (py + 0.5) / float(IMG_H) * WORLD.size.y
		for px in IMG_W:
			var wx := WORLD.position.x + (px + 0.5) / float(IMG_W) * WORLD.size.x
			var h: float = Terrain.height(wx, wz)
			var col: Color
			if h < -0.85:
				col = COLOR_WATER
			else:
				col = COLOR_LOW.lerp(COLOR_HIGH, clampf((h + 4.0) / 55.0, 0.0, 1.0))
				var west: float = Terrain.height(wx - 4.0, wz)
				col = col.lightened(clampf((h - west) * 0.03, -0.12, 0.12))
			img.set_pixel(px, py, col)
	_map_rect.texture = ImageTexture.create_from_image(img)
	_dirty = false


func _map_point(world_xz: Vector2) -> Vector2:
	var size := _map_rect.size
	return Vector2(
		(world_xz.x - WORLD.position.x) / WORLD.size.x * size.x,
		(world_xz.y - WORLD.position.y) / WORLD.size.y * size.y
	)


func _draw_markers() -> void:
	var font := _markers.get_theme_default_font()
	for m in MARKS:
		var p: Vector2 = _map_point(m[1])
		_markers.draw_circle(p, 4.0, Color(0.55, 0.16, 0.30))
		_markers.draw_string(font, p + Vector2(8, 4), m[0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.2, 0.12, 0.14))
	var npc := _markers.get_tree().get_first_node_in_group("npc")
	if npc:
		var p := _map_point(Vector2(npc.global_position.x, npc.global_position.z))
		_markers.draw_circle(p, 4.0, Color(0.13, 0.35, 0.37))
	var player := _markers.get_tree().get_first_node_in_group("player")
	if player:
		var p := _map_point(Vector2(player.global_position.x, player.global_position.z))
		_markers.draw_circle(p, 5.0, Color.WHITE)
		_markers.draw_circle(p, 5.0, Color(0.2, 0.2, 0.2), false, 1.5)
