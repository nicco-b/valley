extends CanvasLayer
## The map (autoload). Skyrim-style: M opens a live orthographic camera
## over the actual world. Drag or WASD to pan, wheel to zoom. The
## streamer follows the map focus (with a widened radius) so terrain
## and content exist wherever you look.

const MARKS := [["Shrine", Vector2(120, -620)], ["Pond", Vector2(70, -310)]]
const COLOR_INK := Color(0.30, 0.17, 0.16)
const PITCH := -1.134  # ~65 degrees down
const CAM_DISTANCE := 400.0

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
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position.y -= 34.0
	_hint.add_theme_color_override("font_color", Color(1, 0.95, 0.9))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hint)


func focus_position() -> Vector3:
	return _focus


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
			_ortho = clampf(_ortho * 0.85, 130.0, 1500.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_ortho = clampf(_ortho / 0.85, 130.0, 1500.0)
	elif event is InputEventMagnifyGesture:
		# Trackpad pinch.
		_ortho = clampf(_ortho / event.factor, 130.0, 1500.0)
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
	_cam.global_position = _focus + Vector3(0.0, 0.906, 0.423) * CAM_DISTANCE
	_markers.queue_redraw()


func _open() -> void:
	active = true
	visible = true
	var player := get_tree().get_first_node_in_group("player")
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
