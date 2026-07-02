extends CanvasLayer
## The map (autoload). M toggles. Rendered from Terrain.height over the
## valley area — the functional map that her illustrated map will one day
## be traced from. Re-renders after god-mode terrain edits.

const WORLD := Rect2(-260, -800, 640, 1080)  # world-space area shown (x, z)
const IMG_W := 480
const IMG_H := 810
const DISPLAY_H := 560.0

const COLOR_FLOOR := Color(0.945, 0.905, 0.83)
const COLOR_MID := Color(0.875, 0.76, 0.585)
const COLOR_HIGH := Color(0.62, 0.46, 0.30)
const COLOR_WATER := Color(0.92, 0.60, 0.64)
const COLOR_CONTOUR := Color(0.52, 0.40, 0.28)
const COLOR_INK := Color(0.30, 0.17, 0.16)
const MARKS := [["Shrine", Vector2(120, -620)], ["Pond", Vector2(70, -310)]]

var _dirty := true
var _map_rect: TextureRect
var _markers: Control


func _ready() -> void:
	layer = 10
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.08, 0.10, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.93, 0.865)
	style.border_color = Color(0.45, 0.32, 0.24)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "The Valley"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_map_rect = TextureRect.new()
	_map_rect.custom_minimum_size = Vector2(DISPLAY_H * IMG_W / IMG_H, DISPLAY_H)
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	vbox.add_child(_map_rect)

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


func _is_water(wx: float, wz: float, h: float) -> bool:
	if h > -0.95:
		return false
	for b in Terrain.BASINS:
		if Vector2(wx - b[0], wz - b[1]).length() < b[2]:
			return true
	return false


func _render() -> void:
	var img := Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGB8)
	for py in IMG_H:
		var wz := WORLD.position.y + (py + 0.5) / float(IMG_H) * WORLD.size.y
		for px in IMG_W:
			var wx := WORLD.position.x + (px + 0.5) / float(IMG_W) * WORLD.size.x
			var h: float = Terrain.height(wx, wz)
			var col: Color
			if _is_water(wx, wz, h):
				col = COLOR_WATER
			else:
				var t := clampf((h + 3.0) / 58.0, 0.0, 1.0)
				if t < 0.35:
					col = COLOR_FLOOR.lerp(COLOR_MID, t / 0.35)
				else:
					col = COLOR_MID.lerp(COLOR_HIGH, (t - 0.35) / 0.65)
				# Hillshade lit from the west.
				var west: float = Terrain.height(wx - 5.0, wz)
				col = col.lightened(clampf((h - west) * 0.05, -0.18, 0.18))
				# Contour lines every 10m above the floor.
				if h > 4.0 and fposmod(h, 10.0) < 0.5:
					col = col.lerp(COLOR_CONTOUR, 0.45)
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
		_markers.draw_circle(p, 5.0, Color(0.55, 0.16, 0.30))
		_markers.draw_circle(p, 5.0, COLOR_INK, false, 1.2)
		_markers.draw_string(font, p + Vector2(10, 5), m[0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_INK)
	var npc := _markers.get_tree().get_first_node_in_group("npc")
	if npc:
		var p := _map_point(Vector2(npc.global_position.x, npc.global_position.z))
		_markers.draw_circle(p, 5.0, Color(0.13, 0.35, 0.37))
		_markers.draw_circle(p, 5.0, COLOR_INK, false, 1.2)
	var player := _markers.get_tree().get_first_node_in_group("player")
	if player:
		var p := _map_point(Vector2(player.global_position.x, player.global_position.z))
		_markers.draw_circle(p, 6.0, Color.WHITE)
		_markers.draw_circle(p, 6.0, COLOR_INK, false, 1.5)
