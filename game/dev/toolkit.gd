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

# The world pens live HERE in the flyover (2026-07-06, Nicco's call —
# in map mode you couldn't watch the ground change): TERRAIN paints the
# elevation guide on the ground you're looking at and AUTO-BAKES on
# stroke-quiet (~0.4s kernel bake on a worker; HotReload reshapes the
# world under the camera), BIOME retints instantly and re-floras on
# stroke release, RIVER drops points on the terrain and carves on
# Enter. The map keeps its pens for whole-world strokes — both ride
# the same shared cores (WorldBake.paint_disc, RiverPen).
const GUIDE_PAINT_RATE := 0.35  # normalized guide units/sec at brush center
const GUIDE_QUIET_BAKE := 0.25  # seconds of stroke-quiet before auto-bake
const MACRO_MIN := 24.0
const MACRO_MAX := 1200.0

enum Tool { SCULPT, PLACE, TERRAIN, BIOME, RIVER }

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
var _macro_radius := 160.0  # TERRAIN/BIOME brush (guide texels are 16m)
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

# TERRAIN pen state.
var _guide: Image = null
var _guide_meta: Dictionary
var _guide_undo: Image = null
var _guide_dirty := false
var _guide_quiet := 0.0
var _guide_bbox := Rect2()  # painted world region (scoped rebuild)
var _baked_img: Image = null  # last bake result (applied live, saved on F5)
var _bake_task := -1
var _bake_pending := false
var _terrain_unsaved := false

# BIOME pen state.
var _biome_index := 4
var _biome_dirty := Rect2()
var _biome_stroke := false
var _biome_unsaved := false

# RIVER pen state.
var _river_nodes: Array[Vector2] = []
var _river_preview: MeshInstance3D


## Boot posture (DECISIONS 2026-07-05, build-out item 1): launched with
## `--toolkit`, the game skips the title and drops straight into the editor
## — the fly camera live over the world the moment the player streams in.
## Dev-only, like the F1 toggle it shares. One truth for title + toolkit.
static func launch_requested() -> bool:
	return OS.is_debug_build() and (
		OS.get_cmdline_user_args().has("--toolkit")
		or OS.get_cmdline_args().has("--toolkit"))


func _ready() -> void:
	if launch_requested():
		get_tree().node_added.connect(_boot_watch)


## Boot posture: open the Toolkit as soon as the world's player enters the
## tree. Scene-declared groups are set before node_added fires, so the
## group check is reliable; the enter defers one idle frame to let the rest
## of the world scene finish assembling around the player.
func _boot_watch(node: Node) -> void:
	if node is CharacterBody3D and node.is_in_group("player"):
		get_tree().node_added.disconnect(_boot_watch)
		_enter.call_deferred()


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
		_save_pens()
	elif event.is_action_pressed("toolkit_tool"):
		_tool = ((_tool as int) + 1) % Tool.size() as Tool
		if _tool == Tool.TERRAIN and _guide == null:
			_guide = WorldBake.load_guide()
			_guide_meta = WorldBake.meta()
		_update_hud()
	elif event.is_action_pressed("toolkit_undo"):
		match _tool:
			Tool.SCULPT:
				# One-deep sculpt undo: revert to the pre-stroke snapshot.
				Terrain.restore_edits(_sculpt_undo)
				_sculpt_undo = null
			Tool.TERRAIN:
				if _guide_undo != null:
					_guide = _guide_undo.duplicate()
					_guide_dirty = true
					_guide_quiet = 0.0  # rebake shortly
			Tool.RIVER:
				if not _river_nodes.is_empty():
					_river_nodes.pop_back()
					_update_hud()
			_:
				var hit := _ray_to_ground()
				if hit != Vector3.INF:
					CellRecords.remove_last(CellRecords.cell_of(hit))
	elif event is InputEventKey and event.pressed and not event.echo \
			and _tool == Tool.RIVER \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		if _river_nodes.size() >= 2:
			RiverPen.commit(_river_nodes)
			_river_nodes.clear()
			_update_hud()
		else:
			HUD.notify("river needs at least 2 points")
	elif event.is_action_pressed("brush_bigger"):
		if _tool == Tool.TERRAIN or _tool == Tool.BIOME:
			_macro_radius = minf(_macro_radius * 1.3, MACRO_MAX)
		else:
			_brush_radius = minf(_brush_radius * 1.3, 64.0)
	elif event.is_action_pressed("brush_smaller"):
		if _tool == Tool.TERRAIN or _tool == Tool.BIOME:
			_macro_radius = maxf(_macro_radius / 1.3, MACRO_MIN)
		else:
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
			and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
		# Number keys pick within the active tool's palette.
		if _tool == Tool.BIOME:
			_biome_index = clampi(event.physical_keycode - KEY_1,
				0, Terrain.biomes.size() - 1)
			_update_hud()
		elif _tool == Tool.PLACE \
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
		elif event.button_index == MOUSE_BUTTON_LEFT and _tool == Tool.RIVER:
			var hit := _ray_to_ground()
			if hit != Vector3.INF:
				_river_nodes.append(Vector2(hit.x, hit.z))
				_update_hud()
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
		var r := 1.5
		match _tool:
			Tool.SCULPT: r = _brush_radius
			Tool.TERRAIN, Tool.BIOME: r = _macro_radius
		_cursor.scale = Vector3(r, 1.0, r)
		var painting := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		# TERRAIN pen: paint the guide on the ground; auto-bake on quiet.
		if _tool == Tool.TERRAIN and painting and _guide != null:
			if not _stroke_live:
				_stroke_live = true
				_guide_undo = _guide.duplicate()  # Z reverts the stroke
			var dir_g := -1.0 if Input.is_action_pressed("sprint") else 1.0
			WorldBake.paint_disc(_guide, _guide_meta, Vector2(hit.x, hit.z),
				_macro_radius, dir_g * GUIDE_PAINT_RATE * delta)
			_guide_dirty = true
			_guide_quiet = 0.0
			# Accumulate the painted world region so the bake rebuilds only
			# these cells (grown a cell so the feathered edge lands too).
			var pr := Rect2(hit.x, hit.z, 0, 0).grow(_macro_radius + 128.0)
			_guide_bbox = pr if _guide_bbox.size == Vector2.ZERO \
					else _guide_bbox.merge(pr)
		# BIOME pen: instant tint; flora re-composes on stroke release.
		elif _tool == Tool.BIOME and painting:
			_biome_stroke = true
			var painted: Rect2 = Terrain.paint_biome_index(
				hit.x, hit.z, _macro_radius, _biome_index)
			_biome_dirty = painted if _biome_dirty.size == Vector2.ZERO \
					else _biome_dirty.merge(painted)
			_biome_unsaved = true
		if _tool == Tool.SCULPT and painting:
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

	# TERRAIN pen: auto-bake on stroke-quiet — the guide bakes on a
	# worker (~0.4s) and HotReload reshapes the ground you're watching.
	if _guide_dirty and not _bake_pending:
		_guide_quiet += delta
		if _guide_quiet >= GUIDE_QUIET_BAKE and Terrain.kernel != null \
				and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_guide_dirty = false
			_bake_pending = true
			_bake_task = WorkerThreadPool.add_task(
				_bake_guide_task.bind(_guide.duplicate(), _guide_meta))
	if _bake_pending and WorkerThreadPool.is_task_completed(_bake_task):
		WorkerThreadPool.wait_for_task_completion(_bake_task)
		_bake_pending = false
		# Swap the baked heightfield in-memory and rebuild ONLY the
		# painted cells (no disk write, no whole-tile HotReload churn).
		if _baked_img != null:
			Terrain.apply_baked_tile("baked_world", _baked_img, _guide_bbox)
			_guide_bbox = Rect2()
			_terrain_unsaved = true

	# BIOME pen: the tint was live per-stroke; flora re-composes once,
	# on release (cell rebuilds ride the streamer's finish budget).
	if _biome_stroke and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_biome_stroke = false
		if _biome_dirty.size != Vector2.ZERO:
			Terrain.commit_biome_paint(_biome_dirty)
			_biome_dirty = Rect2()

	_update_river_preview()


# Just the erosion bake, off the main thread (the image is a duplicate —
# the live one keeps painting while this runs). Result applied in-memory
# by _process; disk persistence waits for save.
func _bake_guide_task(guide: Image, _meta: Dictionary) -> void:
	_baked_img = WorldBake.bake(guide, _meta, Terrain.kernel)


# Persist what the pens changed (F5 and exit, beside the sculpt layer).
func _save_pens() -> void:
	if _biome_unsaved:
		Terrain.save_biome_map()
		_biome_unsaved = false
	if _terrain_unsaved and _baked_img != null:
		WorldBake.save_guide(_guide)       # the source of truth
		WorldBake.write_tile(_baked_img, _guide_meta)  # the cache
		_terrain_unsaved = false
		HUD.notify("terrain saved")


# The drawn river course: a floating line strip PLUS a filled marker
# quad at each dropped node (bare 1px lines vanish over big terrain).
# Lifted above the ground so it reads over relief; rubber-bands to the
# cursor.
const RIVER_MARK := 3.0  # marker quad half-size, meters
func _update_river_preview() -> void:
	if _river_preview == null:
		return
	var mesh := _river_preview.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _tool != Tool.RIVER or _river_nodes.is_empty():
		return
	# The course line (+ rubber band to the cursor).
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for wp in _river_nodes:
		mesh.surface_add_vertex(Vector3(wp.x,
			Terrain.height(wp.x, wp.y) + 1.5, wp.y))
	var hit := _ray_to_ground()
	if hit != Vector3.INF:
		mesh.surface_add_vertex(hit + Vector3.UP * 1.5)
	mesh.surface_end()
	# A flat marker quad at each node — clearly visible from the air.
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for wp in _river_nodes:
		var c := Vector3(wp.x, Terrain.height(wp.x, wp.y) + 1.5, wp.y)
		var a := c + Vector3(-RIVER_MARK, 0, -RIVER_MARK)
		var b := c + Vector3(RIVER_MARK, 0, -RIVER_MARK)
		var d := c + Vector3(RIVER_MARK, 0, RIVER_MARK)
		var e := c + Vector3(-RIVER_MARK, 0, RIVER_MARK)
		mesh.surface_add_vertex(a); mesh.surface_add_vertex(b); mesh.surface_add_vertex(d)
		mesh.surface_add_vertex(a); mesh.surface_add_vertex(d); mesh.surface_add_vertex(e)
	mesh.surface_end()


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
	_save_pens()
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

	# The river pen's course preview (line strip, rebuilt per frame).
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.30, 0.80, 0.95)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_river_preview = MeshInstance3D.new()
	_river_preview.mesh = ImmediateMesh.new()
	_river_preview.material_override = line_mat
	_river_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_river_preview)

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
	match _tool:
		Tool.SCULPT:
			_hud_label.text = "TOOLKIT·SCULPT   F1 exit | LMB raise · Shift carve · Ctrl flatten | Z undo stroke | [ ] brush | Tab next tool | O world panel | M map | F5 save"
		Tool.PLACE:
			var names: Array[String] = []
			for i in Kit.ENTRIES.size():
				var label: String = Kit.ENTRIES[i].label
				names.append(("[%d %s]" if i == _kit_index else "%d %s") % [i + 1, label])
			_hud_label.text = "TOOLKIT·PLACE   " + " · ".join(names) \
					+ "   |   LMB place | Z undo | Tab next tool | F1 exit"
		Tool.TERRAIN:
			_hud_label.text = "TOOLKIT·TERRAIN   LMB raise · Shift lower — bakes when you pause | [ ] brush %dm | Z undo stroke | Tab next tool | F1 exit" % int(_macro_radius)
		Tool.BIOME:
			var bnames: Array[String] = []
			for i in mini(Terrain.biomes.size(), 9):
				var bid := String(Terrain.biomes[i].id)
				bnames.append(("[%d %s]" if i == _biome_index else "%d %s") % [i + 1, bid])
			_hud_label.text = "TOOLKIT·BIOME   " + " · ".join(bnames) \
					+ "   |   LMB paint (re-flora on release) | [ ] brush %dm | Tab next tool" % int(_macro_radius)
		Tool.RIVER:
			_hud_label.text = "TOOLKIT·RIVER   LMB drop point (%d) | Enter carve | Z undo point | Tab next tool | F1 exit" % _river_nodes.size()
