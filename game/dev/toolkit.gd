extends Node
## The Toolkit (autoload) — the in-game editor. The game IS the editor
## (DECISIONS 2026-07-05: one app, never a separate binary; "god mode"
## as a name is retired). F1 toggles the free-fly camera with the
## sculpt brush, place mode, sim inspector, and world panel; F1 again
## returns to the player, teleported to the camera. Edits write to
## Terrain's authored edit layer (F5 / exit saves).

const FLY_SPEED := 30.0
const FAST_MULT := 4.0
const BRUSH_RATE := 14.0  # meters of height per second at brush center
const BRUSH_INTERVAL := 0.05  # seconds between brush applications
const MOUSE_SENSITIVITY := 0.003

enum Tool { SCULPT, PLACE }

var active := false

var _cam: Camera3D
var _cursor: MeshInstance3D
var _hud: CanvasLayer
var _hud_label: Label
var _inspector: Label
var _inspected: Node = null
var _yaw := 0.0
var _pitch := -0.9
var _brush_radius := 12.0
var _brush_accum := 0.0
var _speed_mult := 1.0
var _tool := Tool.SCULPT
var _kit_index := 0
var _world_panel: Label
var _panel_accum := 0.0
var _sculpt_undo: Image = null
var _flatten_target := 0.0
var _flattening := false
var _stroke_live := false


func has_camera() -> bool:
	return _cam != null


func cam_position() -> Vector3:
	return _cam.global_position


## Re-assert the free-fly camera (the map borrows CURRENT while open;
## closing it in the Toolkit hands the view back here, not to the player).
func resume_camera() -> void:
	if _cam:
		_cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Drop the fly camera above a world XZ (map right-click teleport).
func move_to(xz: Vector2) -> void:
	if _cam:
		_cam.global_position = Vector3(xz.x,
			Terrain.height(xz.x, xz.y) + 80.0, xz.y)


## The world panel's first block: every per-position number the sim
## knows about the ground under the camera — the substrate, readable
## where you actually stand instead of at the valley thermometer.
func _here_summary() -> String:
	var p := _cam.global_position if _cam \
			else Vector3(Climate.REFERENCE.x, 0.0, Climate.REFERENCE.y)
	var h: float = Terrain.height(p.x, p.z)
	var biome := "-"
	var bi: int = Terrain.biome_at(p.x, p.z)
	if bi >= 0 and bi < Terrain.biomes.size():
		biome = str(Terrain.biomes[bi].id)
	var cell := Vector2i(floori(p.x / FloraLife.CELL_SIZE),
			floori(p.z / FloraLife.CELL_SIZE))
	var vit: float = FloraLife.vitality_at(p.x, p.z)
	var snow_gap: float = Climate.snow_line() - h
	var lines := PackedStringArray()
	lines.append("(%.0f, %.0f)  h=%.0fm  biome=%s  cell %d,%d" % [
		p.x, p.z, h, biome, cell.x, cell.y])
	lines.append("t=%.1f  hum=%.2f  wet=%.2f  moist=%.2f  rain=%.2f" % [
		Climate.temperature(p.x, p.z), Climate.humidity(p.x, p.z),
		Climate.wetness_at(p.x, p.z), Climate.moisture(p.x, p.z),
		Weather.rain_at(p.x, p.z)])
	lines.append("swing=%.2f  aspect=%+.1f  vit=%.2f stage=%s  gathered=%.2f  snowline %s" % [
		Climate._swing(p.x, p.z),
		Climate.aspect_term(Climate._gradient_z(p.x, p.z), GameClock.solar_hours()),
		vit, FloraLife.stage_for(GameClock.season, vit),
		FloraLife.depletion(cell),
		("%.0fm overhead" % snow_gap) if snow_gap > 0.0 else "BELOW YOU"])
	return "\n         ".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toolkit_toggle") and OS.is_debug_build():
		_exit() if active else _enter()
		return
	if not active:
		return
	# The open map owns the mouse (RMB teleport, drag pan): without this
	# guard the recapture branch below eats the first click and pins the
	# cursor, killing the map's right-click teleport.
	if MapScreen.active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.55, 1.55)
	elif event.is_action_pressed("toolkit_save"):
		Terrain.save_edits()
	elif event.is_action_pressed("toolkit_tool"):
		_tool = Tool.PLACE if _tool == Tool.SCULPT else Tool.SCULPT
		_update_hud()
	elif event.is_action_pressed("toolkit_undo"):
		if _tool == Tool.SCULPT:
			# One-deep sculpt undo: revert to the pre-stroke snapshot.
			Terrain.restore_edits(_sculpt_undo)
			_sculpt_undo = null
		else:
			var hit := _ray_to_ground()
			if hit != Vector3.INF:
				CellRecords.remove_last(CellRecords.cell_of(hit))
	elif event.is_action_pressed("brush_bigger"):
		_brush_radius = minf(_brush_radius * 1.3, 64.0)
	elif event.is_action_pressed("brush_smaller"):
		_brush_radius = maxf(_brush_radius / 1.3, 3.0)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_O:
		# The world panel: every system's Toolkit summary, live.
		_world_panel.visible = not _world_panel.visible
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_N:
		# Navmesh overlay: see what the world thinks is walkable.
		NavigationServer3D.set_debug_enabled(not NavigationServer3D.get_debug_enabled())
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
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Sim inspector: right-click an NPC to watch its mind.
			var space := _cam.get_world_3d().direct_space_state
			var params := PhysicsRayQueryParameters3D.create(
				_cam.global_position, _cam.global_position - _cam.global_basis.z * 3000.0, 3
			)
			var result := space.intersect_ray(params)
			_inspected = result.collider if result and result.collider.has_method("sim_debug") \
					else null
			_inspector.visible = _inspected != null


func _process(delta: float) -> void:
	if not active:
		return
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _cam.global_basis * Vector3(input.x, 0.0, input.y)
	if Input.is_action_pressed("toolkit_up"):
		dir += Vector3.UP
	if Input.is_action_pressed("toolkit_down"):
		dir += Vector3.DOWN
	var speed := FLY_SPEED * _speed_mult
	if Input.is_action_pressed("sprint"):
		speed *= FAST_MULT
	_cam.global_position += dir * speed * delta

	if _inspected and is_instance_valid(_inspected):
		_inspector.text = _inspected.sim_debug()
	elif _inspector.visible:
		_inspector.visible = false

	if _world_panel.visible:
		_panel_accum += delta
		if _panel_accum >= 0.5:
			_panel_accum = 0.0
			_world_panel.text = "\n".join([
				"HERE     " + _here_summary(),
				"AIR      " + Weather.summary(),
				"CLIMATE  " + Climate.summary(),
				"WATER    " + Hydrology.summary().replace("\n", "\n         "),
				"FIELD    " + WaterField.summary(),
				"FLORA    " + FloraLife.summary(),
				"SAND     " + SandField.summary(),
				"WEAR     " + InteractionField.summary(),
				"WAYS     " + Nav.summary(),
				"CARAVANS " + Caravans.summary().replace("\n", "\n         "),
				"LAND     " + Terrain.regions_summary().split("\n")[0],
			])

	# Brush cursor: ray from screen center to terrain.
	var hit := _ray_to_ground()
	_cursor.visible = hit != Vector3.INF
	if _cursor.visible:
		_cursor.global_position = hit
		var r := _brush_radius if _tool == Tool.SCULPT else 1.5
		_cursor.scale = Vector3(r, 1.0, r)
		if _tool == Tool.SCULPT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if not _stroke_live:
				# Stroke begins: snapshot for Z-undo.
				_stroke_live = true
				_sculpt_undo = Terrain.snapshot_edits()
				_flattening = Input.is_key_pressed(KEY_CTRL)
				_flatten_target = hit.y  # flatten to first-touched height
			# Fixed brush cadence, dt-scaled strength: the pixel loop is
			# GDScript — at frame rate it ate the frame rate. Same sculpt
			# speed, a fraction of the applications.
			_brush_accum += delta
			if _brush_accum >= BRUSH_INTERVAL:
				var amount := BRUSH_RATE * _brush_accum
				_brush_accum = 0.0
				if _flattening:
					Terrain.flatten_brush(hit, _brush_radius,
						_flatten_target, minf(amount * 0.25, 1.0))
				elif Input.is_action_pressed("sprint"):
					Terrain.apply_brush(hit, _brush_radius, -amount)
				else:
					Terrain.apply_brush(hit, _brush_radius, amount)
		elif not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_stroke_live = false  # stroke ended; snapshot stays for Z


func _ray_to_ground() -> Vector3:
	var space := _cam.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		_cam.global_position, _cam.global_position - _cam.global_basis.z * 3000.0, 1
	)
	var result := space.intersect_ray(params)
	return result.position if result else Vector3.INF


func _enter() -> void:
	var player := _player()
	if player == null:
		return  # not in the world (title screen)
	active = true
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

	_inspector = Label.new()
	_inspector.visible = false
	_inspector.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspector.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inspector.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_inspector.offset_right = -14.0
	_inspector.offset_top = 40.0
	_inspector.add_theme_font_size_override("font_size", 13)
	_inspector.add_theme_color_override("font_color", Color(0.85, 1.0, 0.95))
	_inspector.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_inspector.add_theme_constant_override("shadow_offset_y", 1)
	_hud.add_child(_inspector)

	# The world panel (O): every system's summary, the sim cockpit.
	_world_panel = Label.new()
	_world_panel.visible = false
	_world_panel.position = Vector2(12, 96)
	_world_panel.add_theme_font_size_override("font_size", 13)
	_world_panel.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_world_panel.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_world_panel.add_theme_constant_override("shadow_offset_y", 1)
	_hud.add_child(_world_panel)

	add_child(_hud)
	_hud.visible = false


func _update_hud() -> void:
	if _tool == Tool.SCULPT:
		_hud_label.text = "TOOLKIT·SCULPT   F1 exit | LMB raise · Shift carve · Ctrl flatten | Z undo stroke | [ ] brush | Tab place | O world panel | M map | F5 save"
	else:
		var names: Array[String] = []
		for i in Kit.ENTRIES.size():
			var label: String = Kit.ENTRIES[i].label
			names.append(("[%d %s]" if i == _kit_index else "%d %s") % [i + 1, label])
		_hud_label.text = "TOOLKIT·PLACE   " + " · ".join(names) \
				+ "   |   LMB place | Z undo | Tab sculpt mode | F1 exit"
