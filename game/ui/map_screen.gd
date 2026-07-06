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
const ZOOM_MAX := 13000.0  # the Big Island + the whole chain in one view
const PAINT_RATE := 0.5  # normalized guide units/sec at the brush center

var active := false

var _from_toolkit := false  # opened from the free-fly cam, not the player
var _cam: Camera3D
var _markers: Control
var _hint: Label
var _focus := Vector3.ZERO
var _ortho := 420.0

# Elevation painting (Toolkit build-out item 2): brush the whole-world
# elevation guide on the live map, bake through WorldBake, let HotReload
# reshape the ground under you — no Blender terrain trip. Toolkit-gated.
var _paint := false
var _guide: Image = null
var _guide_meta: Dictionary
var _brush_m := 300.0  # brush radius in world meters (the map scale is huge)
var _mouse := Vector2.ZERO

# River pen (Toolkit build-out item 2c): draw a river's course on the
# map — LMB drops points, Enter carves. The clicked polyline is
# densified and each node takes its surface from the baked terrain,
# clamped monotonically downhill, then Terrain.add_river writes it into
# the height function live: the basin carves, the ribbon renders, the
# region hydrology breathes it — all from one record, no restart.
const RIVER_NODE_SPACING := 50.0   # densify the clicked course to this
const RIVER_SURFACE_DIP := 0.3     # waterline sits this far below ground
const RIVER_WIDTH_HEAD := 3.0
const RIVER_WIDTH_MOUTH := 11.0
const RIVER_DEPTH := 1.6
const RIVER_FEATHER := 8.0
var _river_mode := false
var _river_nodes: Array[Vector2] = []  # clicked course, world XZ


func _ready() -> void:
	layer = 10
	visible = false
	_markers = Control.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Control's default filter is STOP: full-rect, it silently ate every
	# click and wheel tick over the map (RMB teleport dead, wheel zoom
	# only working via trackpad gestures). Labels are paint, not UI.
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.draw.connect(_draw_markers)
	add_child(_markers)
	_hint = Label.new()
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
	_update_hint()


func focus_position() -> Vector3:
	return _focus


## The streamer only follows the map while zoomed in close enough for
## full-res cells to matter; zoomed out, the quadtree carries the view.
func wants_streaming() -> bool:
	return active and _ortho < STREAM_ZOOM


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		if active:
			_close()
		else:
			_open()
		return
	if not active:
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
	# Elevation painting (Toolkit-gated): P toggles, [ ] size the brush,
	# B bakes the strokes into the world. Handled before pan/zoom so the
	# brush owns LMB while painting.
	if _from_toolkit:
		if event is InputEventKey and event.pressed and not event.echo \
				and event.physical_keycode == KEY_P:
			_toggle_paint()
			return
		if event is InputEventKey and event.pressed and not event.echo \
				and event.physical_keycode == KEY_R:
			_toggle_river()
			return
		if _river_mode and event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_commit_river()
				return
			elif event.keycode == KEY_BACKSPACE:
				if not _river_nodes.is_empty():
					_river_nodes.pop_back()
					_update_hint()
				return
		if _paint:
			if event.is_action_pressed("brush_bigger"):
				_brush_m = minf(_brush_m * 1.3, 2500.0)
				_update_hint()
				return
			elif event.is_action_pressed("brush_smaller"):
				_brush_m = maxf(_brush_m / 1.3, 40.0)
				_update_hint()
				return
			elif event is InputEventKey and event.pressed and not event.echo \
					and event.physical_keycode == KEY_B:
				_bake()
				return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _river_mode:
			var w := _mouse_world()
			if w != Vector2.INF:
				_river_nodes.append(w)
				_update_hint()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and _from_toolkit:
			# Right-click: drop the fly cam there (the 38km2 commute fix).
			var org := _cam.project_ray_origin(event.position)
			var dir := _cam.project_ray_normal(event.position)
			if absf(dir.y) > 0.001:
				var t := -org.y / dir.y
				var hit := org + dir * t
				Toolkit.move_to(Vector2(hit.x, hit.z))
				_focus = Vector3(hit.x, 0.0, hit.z)
				HUD.notify("toolkit cam moved")
			get_viewport().set_input_as_handled()
			return
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
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT \
			and not _paint and not _river_mode:
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
	# Paint stroke: LMB held over the map raises the guide, Shift lowers —
	# dt-scaled so the rate is frame-independent (the Toolkit sculpt idiom).
	if _paint and _guide != null \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var w := _mouse_world()
		if w != Vector2.INF:
			var dir := -1.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
			_paint_guide(w, dir * PAINT_RATE * delta)
	_markers.queue_redraw()


func _open() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return  # not in the world (title screen)
	_from_toolkit = Toolkit.active and Toolkit.has_camera()
	_update_hint()
	# Center on whatever the map is opened over — the fly cam in toolkit
	# mode, the player otherwise.
	var here: Vector3 = Toolkit.cam_position() if _from_toolkit else player.global_position
	active = true
	visible = true
	_focus = Vector3(here.x, 0.0, here.z)
	if _cam == null:
		_cam = Camera3D.new()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.rotation.x = PITCH
		_cam.size = _ortho
		_cam.far = 2500.0
		# The map is a CHART, not a window: its own fog-free environment
		# so weather never obscures it. Strong flat ambient keeps the
		# terrain readable even when a storm has dimmed the real sun;
		# background is sea-toned so unbuilt distance reads as ocean.
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.32, 0.47, 0.60)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1.0, 0.98, 0.94)
		env.ambient_light_energy = 1.15
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		_cam.environment = env
		add_child(_cam)
	_cam.current = true
	RenderingServer.global_shader_parameter_set("map_view", 1.0)
	if not _from_toolkit:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	active = false
	visible = false
	_paint = false
	_river_mode = false
	_river_nodes.clear()
	RenderingServer.global_shader_parameter_set("map_view", 0.0)
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		streamer.load_radius = 2
	if _from_toolkit:
		# Hand the view back to the free-fly camera, not the player.
		Toolkit.resume_camera()
		return
	var player := get_tree().get_first_node_in_group("player")
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	(player.get_node("CameraRig/SpringArm3D/Camera3D") as Camera3D).current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Enter/leave elevation paint mode. The guide loads lazily on first use;
## it stays cached across opens so long paint sessions don't re-read disk.
func _toggle_paint() -> void:
	_paint = not _paint
	if _paint:
		_river_mode = false  # tools are exclusive
		_river_nodes.clear()
		if _guide == null:
			_guide = WorldBake.load_guide()
			_guide_meta = WorldBake.meta()
	_update_hint()


## Enter/leave river-pen mode (tools are exclusive; leaving discards an
## uncommitted course).
func _toggle_river() -> void:
	_river_mode = not _river_mode
	if _river_mode:
		_paint = false
	else:
		_river_nodes.clear()
	_update_hint()


## Commit the drawn course to a river record: densify to node spacing,
## take each surface from the baked terrain (clamped downhill), taper the
## width head→mouth, then Terrain.add_river carves it live and we persist
## the JSON so it survives a restart.
func _commit_river() -> void:
	if _river_nodes.size() < 2:
		HUD.notify("river needs at least 2 points")
		return
	var pts := _densify(_river_nodes, RIVER_NODE_SPACING)
	var out_nodes: Array = []
	var surf := INF
	var length := 0.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		surf = minf(surf, Terrain.height(p.x, p.y) - RIVER_SURFACE_DIP)
		if i > 0:
			length += p.distance_to(pts[i - 1])
		var f := float(i) / maxf(pts.size() - 1, 1)
		out_nodes.append({
			"x": snappedf(p.x, 0.1), "z": snappedf(p.y, 0.1),
			"width": snappedf(lerpf(RIVER_WIDTH_HEAD, RIVER_WIDTH_MOUTH, f), 0.1),
			"surface": snappedf(surf, 0.1)})
	var n := _next_pen_index()
	# Rough catchment for the region tier: a ~200m drainage strip along
	# the course (mood physics; a longer river breathes wider).
	var rec := {"id": "pen_%d" % n, "no_sim": true,
		"depth": RIVER_DEPTH, "feather": RIVER_FEATHER,
		"catchment_m2": snappedf(length * 200.0, 1.0), "nodes": out_nodes}
	Terrain.add_river(rec)
	var fh := FileAccess.open("res://data/water/rivers/pen_%d.json" % n, FileAccess.WRITE)
	fh.store_string(JSON.stringify(rec, "\t") + "\n")
	fh.close()
	_river_nodes.clear()
	_update_hint()
	HUD.notify("river penned (%d nodes, %.0fm) — carving" % [out_nodes.size(), int(length)])


## Uniform arc-length resample of a clicked polyline (endpoints kept), so
## the carve's node-lerped bed follows the terrain instead of bridging
## between far-apart clicks.
func _densify(pts: Array, spacing: float) -> Array:
	var out: Array = [pts[0]]
	var carry := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var ab: Vector2 = pts[i + 1] - a
		var seg := ab.length()
		if seg < 1e-4:
			continue
		var s := spacing - carry
		while s < seg:
			out.append(a + ab * (s / seg))
			s += spacing
		carry = seg - (s - spacing)
	out.append(pts[pts.size() - 1])
	return out


func _next_pen_index() -> int:
	var n := 0
	var dir := DirAccess.open("res://data/water/rivers")
	if dir:
		for f in dir.get_files():
			if f.begins_with("pen_") and f.ends_with(".json"):
				n = maxi(n, f.trim_prefix("pen_").trim_suffix(".json").to_int() + 1)
	return n


## Screen mouse → world XZ on the y=0 plane. The map cam is pitched, so
## this carries a little parallax over tall terrain (good enough for a
## whole-world guide brush; the same approximation the RMB teleport uses).
func _mouse_world() -> Vector2:
	if _cam == null:
		return Vector2.INF
	var org := _cam.project_ray_origin(_mouse)
	var dir := _cam.project_ray_normal(_mouse)
	if absf(dir.y) < 0.001:
		return Vector2.INF
	var hit := org + dir * (-org.y / dir.y)
	return Vector2(hit.x, hit.z)


## Raise (or lower) the guide within the brush disc, linear falloff to the
## rim, clamped to the paintable 0..1 range.
func _paint_guide(world_xz: Vector2, amount: float) -> void:
	var res := _guide.get_width()
	var c := WorldBake.world_to_texel(world_xz.x, world_xz.y, _guide_meta, res)
	var rad := _brush_m / float(_guide_meta["world_size"]) * res
	if rad < 0.5:
		return
	for pz in range(maxi(0, int(c.y - rad)), mini(res, int(c.y + rad) + 1)):
		for px in range(maxi(0, int(c.x - rad)), mini(res, int(c.x + rad) + 1)):
			var d := Vector2(px + 0.5, pz + 0.5).distance_to(c)
			if d > rad:
				continue
			var v := _guide.get_pixel(px, pz).r + amount * (1.0 - d / rad)
			_guide.set_pixel(px, pz, Color(clampf(v, 0.0, 1.0), 0.0, 0.0))


## Commit the painted guide: persist it, bake through the kernel (the same
## WorldBake the headless CLI runs), write the tile cache. HotReload sees
## the fresh EXR within a second and reshapes the ground under you. The
## bake is sub-second but synchronous — the static map holds one beat.
func _bake() -> void:
	if _guide == null or Terrain.kernel == null:
		HUD.notify("bake needs the native kernel")
		return
	HUD.notify("baking terrain…")
	WorldBake.save_guide(_guide)
	var baked := WorldBake.bake(_guide, _guide_meta, Terrain.kernel)
	WorldBake.write_tile(baked, _guide_meta)
	HUD.notify("terrain baked — reshaping")


func _update_hint() -> void:
	if _river_mode:
		_hint.text = "RIVER pen  ·  LMB add point (%d)  ·  Enter carve  ·  Backspace undo  ·  R exit" % _river_nodes.size()
	elif _paint:
		_hint.text = "PAINT elevation  ·  LMB raise · Shift lower  ·  [ ] brush %dm  ·  B bake  ·  P exit" % int(_brush_m)
	elif _from_toolkit:
		_hint.text = "drag / WASD pan  ·  wheel zoom  ·  P paint elevation  ·  R river pen  ·  RMB teleport  ·  M close"
	else:
		_hint.text = "drag / WASD pan  ·  wheel zoom  ·  M close"


func _draw_markers() -> void:
	if _cam == null:
		return
	# The paint brush footprint (world-meters → screen px via the ortho scale).
	if _paint:
		var r_px := _brush_m * _markers.size.y / _cam.size
		_markers.draw_circle(_mouse, r_px, Color(0.95, 0.55, 0.25, 0.12))
		_markers.draw_arc(_mouse, r_px, 0.0, TAU, 48, Color(1, 0.6, 0.25, 0.9), 1.5)
	# The river-pen course: dropped points + a rubber band to the cursor.
	if _river_mode:
		var rprev := Vector2.INF
		for wp in _river_nodes:
			var sp := _cam.unproject_position(
				Vector3(wp.x, Terrain.height(wp.x, wp.y) + 1.0, wp.y))
			if rprev != Vector2.INF:
				_markers.draw_line(rprev, sp, Color(0.30, 0.80, 0.95, 0.95), 2.0)
			_markers.draw_circle(sp, 4.0, Color(0.30, 0.80, 0.95))
			rprev = sp
		if rprev != Vector2.INF:
			_markers.draw_line(rprev, _mouse, Color(0.30, 0.80, 0.95, 0.4), 1.5)
	var font := _markers.get_theme_default_font()
	# The archipelago's islands, straight from the region records — a
	# new landform on the map is a new JSON, nothing hand-listed here.
	for r in Terrain.regions:
		var c: Vector2 = r.center
		if r.kind == "ridge" and not r.nodes.is_empty():
			var nodes: PackedVector2Array = r.nodes
			c = nodes[nodes.size() / 2]
		_draw_place(font, c, _label_for(String(r.id)), Color(0.42, 0.30, 0.22))
	for t in Terrain._tiles:
		_draw_place(font, Vector2(t.x0 + t.size * 0.5, t.z0 + t.size * 0.5),
			_label_for(String(t.id)), Color(0.30, 0.34, 0.5))
	for m in MARKS:
		_draw_place(font, m[1], m[0], Color(0.55, 0.16, 0.30))
	# Rivers (authored + proposed) as blue polylines along their nodes.
	for r in Terrain.rivers:
		var nodes: Array = r.nodes
		var prev := Vector2.INF
		for n in nodes:
			var wp: Vector2 = n.pos
			var p := _cam.unproject_position(
				Vector3(wp.x, Terrain.height(wp.x, wp.y) + 1.0, wp.y))
			if prev != Vector2.INF:
				_markers.draw_line(prev, p, Color(0.30, 0.48, 0.62, 0.9), 1.5)
			prev = p
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
	# Adaptive scale: pick the nicest round distance that draws ~120px
	# wide (a fixed 100m bar vanishes at 9km zoom).
	var m_per_px := _cam.size / vp.y
	var target_m := 120.0 * m_per_px
	var nice := 100.0
	for step in [50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0]:
		if step >= target_m:
			nice = step
			break
		nice = step
	var bar_px := nice / m_per_px
	var bar_y := vp.y - 36.0
	_markers.draw_line(Vector2(24, bar_y), Vector2(24 + bar_px, bar_y),
			Color(1, 0.95, 0.9), 2.0)
	var label := "%.0f m" % nice if nice < 1000.0 else "%.1f km" % (nice / 1000.0)
	_markers.draw_string(font, Vector2(24, bar_y - 8), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.95, 0.9))


## A named island dot, hidden when tiny/off-screen. Labels only when
## the map is zoomed in enough that they won't pile up.
func _draw_place(font: Font, xz: Vector2, text: String, col: Color) -> void:
	var world := Vector3(xz.x, Terrain.height(xz.x, xz.y) + 2.0, xz.y)
	var p := _cam.unproject_position(world)
	if p.x < -40 or p.y < -40 or p.x > _markers.size.x + 40 or p.y > _markers.size.y + 40:
		return
	_markers.draw_circle(p, 5.0, col)
	_markers.draw_circle(p, 5.0, Color.WHITE, false, 1.5)
	if _ortho < 4000.0:
		_draw_label(font, p + Vector2(10, 5), text)


## region/tile id -> a readable place name (title-cased, "_" → space).
func _label_for(id: String) -> String:
	return id.replace("_", " ").capitalize()


func _draw_label(font: Font, pos: Vector2, text: String) -> void:
	_markers.draw_string(font, pos + Vector2(1, 1), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.85))
	_markers.draw_string(font, pos, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLOR_INK)
