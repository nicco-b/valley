extends CanvasLayer
## The map (autoload). Skyrim-style: M opens a live orthographic camera
## over the actual world. Drag or WASD to pan, wheel to zoom. The
## streamer follows the map focus (with a widened radius) so terrain
## and content exist wherever you look.

const MARKS := [["Shrine", Vector2(120, -620)], ["Pond", Vector2(70, -310)]]
const COLOR_INK := Color(0.30, 0.17, 0.16)
const PITCH := -1.134  # ~65 degrees down
const CAM_DISTANCE := 400.0
# Past this zoom the map stops driving the cell streamer entirely —
# the far-terrain quadtree (which follows the map focus and caches
# its tiles) IS the renderer at region scale. Panning a zoomed-out
# map costs one cheap cached tile at a time instead of 81 full cells
# with collision and navmesh (the old map hitching).
const STREAM_ZOOM := 900.0
const ZOOM_MIN := 130.0
const ZOOM_MAX := 9000.0  # the whole archipelago in one view

var active := false

var _cam: Camera3D
var _markers: Control
var _hint: Label
var _focus := Vector3.ZERO
var _ortho := 420.0


func _ready() -> void:
	layer = 10
	visible = false
	_markers = Control.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers.draw.connect(_draw_markers)
	add_child(_markers)
	_hint = Label.new()
	_hint.text = "drag / WASD pan  ·  wheel zoom  ·  M close"
	# Full-rect + bottom alignment (point anchors land off-screen — CLAUDE.md).
	_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.offset_bottom = -24.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(1, 0.95, 0.9))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hint)


func focus_position() -> Vector3:
	return _focus


## The streamer only follows the map while zoomed in close enough for
## full-res cells to matter; zoomed out, the quadtree carries the view.
func wants_streaming() -> bool:
	return active and _ortho < STREAM_ZOOM


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map") and not GodMode.active:
		if active:
			_close()
		else:
			_open()
		return
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_ortho = clampf(_ortho * 0.85, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_ortho = clampf(_ortho / 0.85, ZOOM_MIN, ZOOM_MAX)
	elif event is InputEventMagnifyGesture:
		# Trackpad pinch.
		_ortho = clampf(_ortho / event.factor, ZOOM_MIN, ZOOM_MAX)
	elif event is InputEventPanGesture:
		# Trackpad two-finger pan.
		var scale := _ortho / get_viewport().get_visible_rect().size.y
		_focus.x += event.delta.x * scale * 2.2
		_focus.z += event.delta.y * scale * 2.2
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var scale := _ortho / get_viewport().get_visible_rect().size.y
		_focus.x -= event.relative.x * scale
		_focus.z -= event.relative.y * scale


func _process(delta: float) -> void:
	if not active:
		return
	var pan := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_focus.x += pan.x * _ortho * 0.9 * delta
	_focus.z += pan.y * _ortho * 0.9 * delta
	_cam.size = lerpf(_cam.size, _ortho, 1.0 - exp(-10.0 * delta))
	# Rig scales with zoom so tall islands never clip the frustum.
	var dist := maxf(CAM_DISTANCE, _ortho * 0.55)
	_cam.far = dist * 8.0
	_cam.global_position = _focus + Vector3(0.0, 0.906, 0.423) * dist
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		streamer.load_radius = 4 if wants_streaming() else 2
	_markers.queue_redraw()


func _open() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return  # not in the world (title screen)
	active = true
	visible = true
	_focus = Vector3(player.global_position.x, 0.0, player.global_position.z)
	if _cam == null:
		_cam = Camera3D.new()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.rotation.x = PITCH
		_cam.size = _ortho
		_cam.far = 2500.0
		add_child(_cam)
	_cam.current = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		streamer.load_radius = 4
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	active = false
	visible = false
	var player := get_tree().get_first_node_in_group("player")
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	(player.get_node("CameraRig/SpringArm3D/Camera3D") as Camera3D).current = true
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		streamer.load_radius = 2
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _draw_markers() -> void:
	if _cam == null:
		return
	var font := _markers.get_theme_default_font()
	for m in MARKS:
		var world := Vector3(m[1].x, Terrain.height(m[1].x, m[1].y) + 2.0, m[1].y)
		var p := _cam.unproject_position(world)
		_markers.draw_circle(p, 5.0, Color(0.55, 0.16, 0.30))
		_markers.draw_circle(p, 5.0, Color.WHITE, false, 1.5)
		_draw_label(font, p + Vector2(10, 5), m[0])
	for npc in get_tree().get_nodes_in_group("npc"):
		var p := _cam.unproject_position(npc.global_position + Vector3.UP * 2.0)
		_markers.draw_circle(p, 5.0, Color(0.13, 0.35, 0.37))
		_markers.draw_circle(p, 5.0, Color.WHITE, false, 1.5)
		_draw_label(font, p + Vector2(9, 4), npc.display_name)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var p := _cam.unproject_position(player.global_position + Vector3.UP * 2.0)
		_markers.draw_circle(p, 6.0, Color.WHITE)
		_markers.draw_circle(p, 6.0, COLOR_INK, false, 1.5)

	# Compass north + scale bar.
	var vp := _markers.size
	_markers.draw_string(font, Vector2(vp.x * 0.5 - 5, 34), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.95, 0.9))
	_markers.draw_line(Vector2(vp.x * 0.5, 44), Vector2(vp.x * 0.5, 58),
			Color(1, 0.95, 0.9), 1.5)
	var bar_px := 100.0 / _cam.size * vp.y
	var bar_y := vp.y - 36.0
	_markers.draw_line(Vector2(24, bar_y), Vector2(24 + bar_px, bar_y),
			Color(1, 0.95, 0.9), 2.0)
	_markers.draw_string(font, Vector2(24, bar_y - 8), "100 m",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.95, 0.9))


func _draw_label(font: Font, pos: Vector2, text: String) -> void:
	_markers.draw_string(font, pos + Vector2(1, 1), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.85))
	_markers.draw_string(font, pos, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLOR_INK)
