extends Node
## Dev god mode (autoload). F1 toggles a free-fly camera with a terrain
## sculpt brush; F1 again returns to the player, teleported to the camera.
## Edits write to Terrain's authored edit layer (F5 / exit saves).

const FLY_SPEED := 30.0
const FAST_MULT := 4.0
const BRUSH_RATE := 14.0  # meters of height per second at brush center
const MOUSE_SENSITIVITY := 0.003

enum Tool { SCULPT, PLACE }

var active := false

var _cam: Camera3D
var _cursor: MeshInstance3D
var _hud: CanvasLayer
var _hud_label: Label
var _yaw := 0.0
var _pitch := -0.9
var _brush_radius := 12.0
var _speed_mult := 1.0
var _tool := Tool.SCULPT
var _kit_index := 0


func cam_position() -> Vector3:
	return _cam.global_position


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("god_mode") and OS.is_debug_build():
		_exit() if active else _enter()
		return
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.55, 1.55)
	elif event.is_action_pressed("god_save"):
		Terrain.save_edits()
	elif event.is_action_pressed("god_tool"):
		_tool = Tool.PLACE if _tool == Tool.SCULPT else Tool.SCULPT
		_update_hud()
	elif event.is_action_pressed("god_undo"):
		var hit := _ray_to_ground()
		if hit != Vector3.INF:
			CellRecords.remove_last(CellRecords.cell_of(hit))
	elif event.is_action_pressed("brush_bigger"):
		_brush_radius = minf(_brush_radius * 1.3, 64.0)
	elif event.is_action_pressed("brush_smaller"):
		_brush_radius = maxf(_brush_radius / 1.3, 3.0)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode >= KEY_1 \
			and event.physical_keycode < KEY_1 + Kit.ENTRIES.size():
		_kit_index = event.physical_keycode - KEY_1
		_update_hud()
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
				and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed_mult = minf(_speed_mult * 1.2, 8.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed_mult = maxf(_speed_mult / 1.2, 0.2)
		elif event.button_index == MOUSE_BUTTON_LEFT and _tool == Tool.PLACE:
			var hit := _ray_to_ground()
			if hit != Vector3.INF:
				CellRecords.add(hit, Kit.ENTRIES[_kit_index].id,
						randf() * TAU, randf_range(0.85, 1.15))


func _process(delta: float) -> void:
	if not active:
		return
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _cam.global_basis * Vector3(input.x, 0.0, input.y)
	if Input.is_action_pressed("god_up"):
		dir += Vector3.UP
	if Input.is_action_pressed("god_down"):
		dir += Vector3.DOWN
	var speed := FLY_SPEED * _speed_mult
	if Input.is_action_pressed("sprint"):
		speed *= FAST_MULT
	_cam.global_position += dir * speed * delta

	# Brush cursor: ray from screen center to terrain.
	var hit := _ray_to_ground()
	_cursor.visible = hit != Vector3.INF
	if _cursor.visible:
		_cursor.global_position = hit
		var r := _brush_radius if _tool == Tool.SCULPT else 1.5
		_cursor.scale = Vector3(r, 1.0, r)
		if _tool == Tool.SCULPT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var amount := BRUSH_RATE * delta
			if Input.is_action_pressed("sprint"):
				amount = -amount
			Terrain.apply_brush(hit, _brush_radius, amount)


func _ray_to_ground() -> Vector3:
	var space := _cam.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		_cam.global_position, _cam.global_position - _cam.global_basis.z * 3000.0, 1
	)
	var result := space.intersect_ray(params)
	return result.position if result else Vector3.INF


func _enter() -> void:
	active = true
	var player := _player()
	if _cam == null:
		_build_nodes()
	_cam.global_position = player.global_position + Vector3(0, 60, 25)
	_yaw = 0.0
	_pitch = -1.1
	_cam.current = true
	_cursor.visible = true
	_hud.visible = true
	_update_hud()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	set_process(true)


func _exit() -> void:
	active = false
	Terrain.save_edits()
	var player := _player()
	var ground := Terrain.height(_cam.global_position.x, _cam.global_position.z)
	player.global_position = Vector3(_cam.global_position.x, ground + 1.5, _cam.global_position.z)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	(player.get_node("CameraRig/SpringArm3D/Camera3D") as Camera3D).current = true
	_cursor.visible = false
	_hud.visible = false
	set_process(false)


func _player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("player")


func _build_nodes() -> void:
	_cam = Camera3D.new()
	_cam.far = 8000.0
	add_child(_cam)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.25, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.3
	disc.material = mat
	_cursor = MeshInstance3D.new()
	_cursor.mesh = disc
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cursor)

	_hud = CanvasLayer.new()
	_hud_label = Label.new()
	_hud_label.position = Vector2(12, 8)
	_hud_label.add_theme_color_override("font_color", Color(1, 0.9, 0.8))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_hud_label.add_theme_constant_override("shadow_offset_y", 1)
	_hud.add_child(_hud_label)
	add_child(_hud)
	_hud.visible = false


func _update_hud() -> void:
	if _tool == Tool.SCULPT:
		_hud_label.text = "GOD·SCULPT   F1 exit+teleport | LMB raise · Shift+LMB carve | [ ] brush | Tab place mode | E/Q fly | F5 save"
	else:
		var names: Array[String] = []
		for i in Kit.ENTRIES.size():
			var label: String = Kit.ENTRIES[i].label
			names.append(("[%d %s]" if i == _kit_index else "%d %s") % [i + 1, label])
		_hud_label.text = "GOD·PLACE   " + " · ".join(names) \
				+ "   |   LMB place | Z undo | Tab sculpt mode | F1 exit"
