extends CanvasLayer
## The map (autoload). A REAL 3D view of the world, the orbit rig's hand
## (2026-07-08, Nicco: "a real 3d view of the map, sort of like the
## orbit"): M borrows the view — a perspective camera framing the whole
## world tile, LMB-drag orbits, wheel zooms, WASD pans the target — over
## the ACTUAL terrain, water, and placed things. The chart air (OrbitRig
## recipe) exempts the view from fog/murk so weather never obscures it
## (rendering only — the sim's weather is untouched; the sky still says
## storm), and a solar-scaled ambient floor keeps midnight readable.
## Esc/M closes; the player's body holds still underneath. The streamer
## follows the map focus (widened radius) only when zoomed in close
## enough for full-res cells to matter — zoomed out, the far-terrain
## quadtree IS the renderer.

const MARKS := []  # authored place marks (old valley retired; Strata places TBD)
const COLOR_INK := Color(0.30, 0.17, 0.16)
# Past this orbit distance the map stops driving the cell streamer —
# the far-terrain quadtree (which follows the map focus and caches its
# tiles) carries the view at region scale. Panning a zoomed-out map
# costs one cheap cached tile at a time instead of 81 full cells with
# collision and navmesh (the old map hitching).
const STREAM_DIST := 900.0
const DIST_MIN := 120.0
const DIST_MAX := 40000.0
const PAINT_RATE_M := 150.0  # meters of override/sec at the brush center

var active := false

var _from_toolkit := false  # opened from the free-fly cam, not the player
var _cam: Camera3D
var _env: Environment
var _rig := OrbitRig.new()  # the same rig the Toolkit's viewer rides
var _markers: Control
var _hint: Label

# Elevation painting (Toolkit build-out item 2; re-scoped by the P0 seam
# fix, ONE_APP.md 2026-07-07): brush the whole-world OVERRIDE layer on the
# live map — the blessed Strata tile underneath is read-only and never
# re-eroded. B commits (scoped recomposite reshapes the ground) and
# persists the override EXR. Toolkit-gated.
var _paint := false
var _paint_bbox := Rect2()  # strokes awaiting commit (scoped rebuild)
var _brush_m := 300.0  # brush radius in world meters (the map scale is huge)
var _mouse := Vector2.ZERO

# River pen (Toolkit build-out item 2c): draw a river's course on the
# map — LMB drops points, Enter carves. The clicked polyline is
# densified and each node takes its surface from the baked terrain,
# clamped monotonically downhill, then Terrain.add_river writes it into
# the height function live: the basin carves, the ribbon renders, the
# region hydrology breathes it — all from one record, no restart.
var _river_mode := false
var _river_nodes: Array[Vector2] = []  # clicked course, world XZ

# Biome pen (Toolkit build-out item 2, second half): paint the whole-world
# biome map on the live map. LMB paints the selected biome — the ground
# TINT changes instantly (the shader samples the index texture); B commits
# so flora re-composes to the new biomes and the PNG persists. Number keys
# pick the biome. Completes item 2 (paint elevation + biome in-game).
var _biome_paint := false
var _biome_index := 4  # default: a mid palette entry (placeholder oasis_green)
var _biome_dirty := Rect2()  # painted region awaiting a flora rescatter


func _ready() -> void:
	layer = 10
	visible = false
	_rig.min_distance = DIST_MIN
	_rig.max_distance = DIST_MAX
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
	return _rig.target


## The streamer only follows the map while zoomed in close enough for
## full-res cells to matter; zoomed out, the quadtree carries the view.
func wants_streaming() -> bool:
	return active and _rig.distance < STREAM_DIST


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
	# B commits the strokes into the world. Handled before orbit/zoom so
	# the brush owns LMB while painting.
	if _from_toolkit:
		if event is InputEventKey and event.pressed and not event.echo \
				and event.physical_keycode == KEY_P:
			_toggle_paint()
			return
		if event is InputEventKey and event.pressed and not event.echo \
				and event.physical_keycode == KEY_R:
			_toggle_river()
			return
		if event is InputEventKey and event.pressed and not event.echo \
				and event.physical_keycode == KEY_G:
			_toggle_biome()
			return
		if _biome_paint and event is InputEventKey and event.pressed and not event.echo:
			# 1..9 select a biome; B commits (rescatter + persist).
			if event.keycode >= KEY_1 and event.keycode <= KEY_9:
				_biome_index = clampi(event.keycode - KEY_1, 0, Terrain.biomes.size() - 1)
				_update_hint()
				return
			elif event.physical_keycode == KEY_B:
				_commit_biome()
				return
			elif event.is_action_pressed("brush_bigger"):
				_brush_m = minf(_brush_m * 1.3, 2500.0)
				_update_hint()
				return
			elif event.is_action_pressed("brush_smaller"):
				_brush_m = maxf(_brush_m / 1.3, 40.0)
				_update_hint()
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
			# Right-click: drop the fly cam there (the 38km2 commute fix);
			# the orbit recenters with it so the view follows the hand. The
			# target is the terrain SURFACE under the cursor, not the flat
			# y=0 plane (_travel_target) — over the baked 16384m tile the
			# ground stands hundreds of metres up and the pitched orbit made
			# the plane land a kilometre past the click.
			var w := _travel_target(event.position)
			if w != Vector2.INF:
				Toolkit.move_to(w)
				_rig.target = Vector3(w.x, 0.0, w.y)
				HUD.notify("toolkit cam moved")
			get_viewport().set_input_as_handled()
			return
	if event is InputEventPanGesture:
		# Trackpad two-finger pan slides the target in the ground plane.
		var scale := _m_per_px()
		_rig.target.x += event.delta.x * scale * 2.2
		_rig.target.z += event.delta.y * scale * 2.2
		return
	# The orbit hand (shared rig): LMB-drag orbits — unless a pen owns
	# the mouse — wheel and pinch zoom toward the target.
	_rig.handle_input(event, not (_paint or _river_mode or _biome_paint))


func _process(delta: float) -> void:
	if not active:
		return
	_rig.pan(Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"), delta)
	_rig.apply(_cam)
	# Readability floor: solar- AND weather-scaled ambient — full lantern
	# at midnight, a whisper at clear noon, and most of a lantern when a
	# storm has dimmed the sun (the dimming stays as the subtle weather
	# hint; the whiteout doesn't). Rendering only — the world outside the
	# map keeps its honest dark.
	var sun_up := clampf(
		sin((GameClock.solar_hours() - 6.0) / 24.0 * TAU) * 1.6, 0.0, 1.0)
	sun_up *= clampf(1.0 - 0.4 * Weather.storminess - 0.3 * Weather.cloud, 0.0, 1.0)
	_env.ambient_light_energy = lerpf(1.05, 0.25, sun_up)
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		streamer.load_radius = 4 if wants_streaming() else 2
	# Paint stroke: LMB held over the map raises the override, Shift lowers
	# — dt-scaled so the rate is frame-independent (the Toolkit sculpt idiom).
	if _paint and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var w := _mouse_world()
		if w != Vector2.INF:
			var dir := -1.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
			var painted: Rect2 = Terrain.paint_tile_override(
				w, _brush_m, dir * PAINT_RATE_M * delta)
			if painted.size != Vector2.ZERO:
				_paint_bbox = painted if _paint_bbox.size == Vector2.ZERO \
						else _paint_bbox.merge(painted)
	# Biome stroke: LMB stamps the selected biome into the live index map
	# (ground tint updates instantly); the painted region accumulates for
	# the flora rescatter on commit.
	if _biome_paint and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var w := _mouse_world()
		if w != Vector2.INF:
			var painted := Terrain.paint_biome_index(w.x, w.y, _brush_m, _biome_index)
			_biome_dirty = painted if _biome_dirty.size == Vector2.ZERO \
				else _biome_dirty.merge(painted)
	_markers.queue_redraw()


func _open() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return  # not in the world (title screen)
	_from_toolkit = Toolkit.active and Toolkit.has_camera()
	_update_hint()
	active = true
	visible = true
	if _cam == null:
		_cam = Camera3D.new()
		add_child(_cam)
	if _env == null:
		# The chart air (OrbitRig recipe, shared with the viewer): the
		# world's environment minus the fogs — the weather EXEMPTION.
		# Rendering only: Weather/Climate never hear about it, and the
		# surviving sky/sun still hint the hour and the storm.
		_env = OrbitRig.chart_environment(get_viewport().world_3d.environment)
		# No haze at all on the map (the viewer keeps a faint one): from
		# an orbit camera EVERYTHING is >12km out, so even whisper fog is
		# a full-frame veil in whatever color the weather painted at open
		# — and the stretched far sea disc (water_bodies) now covers the
		# beyond-the-tile seabed the viewer's haze was hired to hide.
		_env.fog_enabled = false
		# The exemption's second half: a flat ambient floor (solar- and
		# weather-scaled each frame in _process) so a storm-dimmed sun or
		# plain midnight never turns the chart illegible.
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(1.0, 0.98, 0.94)
		_env.ambient_light_energy = 0.6
		_cam.environment = _env
	# Open framing the whole tile — the orbit's opening look. The player
	# marker (and WASD/zoom) take it from there.
	_rig.frame_tile()
	_rig.apply(_cam)
	_cam.current = true
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
	_biome_paint = false
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


## Enter/leave elevation paint mode (the override pen rides the world
## tile's frame, so it needs a baked tile to exist).
func _toggle_paint() -> void:
	_paint = not _paint
	if _paint:
		_river_mode = false  # tools are exclusive
		_river_nodes.clear()
		_biome_paint = false
		if not Terrain.has_world_tile():
			HUD.notify("no baked tile — import a Strata world first")
			_paint = false
	_update_hint()


## Enter/leave biome-paint mode (exclusive with the other pens).
func _toggle_biome() -> void:
	_biome_paint = not _biome_paint
	if _biome_paint:
		_paint = false
		_river_mode = false
		_river_nodes.clear()
		_biome_dirty = Rect2()
		if Terrain.biomes.is_empty():
			HUD.notify("no biome palette loaded")
			_biome_paint = false
	_update_hint()


## Commit the painted biomes: persist the PNG and rescatter flora over the
## painted region (the ground tint was already live).
func _commit_biome() -> void:
	if _biome_dirty.size == Vector2.ZERO:
		HUD.notify("paint some biome first")
		return
	Terrain.save_biome_map()
	Terrain.commit_biome_paint(_biome_dirty)
	_biome_dirty = Rect2()
	HUD.notify("biomes committed — flora re-composing")


## Enter/leave river-pen mode (tools are exclusive; leaving discards an
## uncommitted course).
func _toggle_river() -> void:
	_river_mode = not _river_mode
	if _river_mode:
		_paint = false
		_biome_paint = false
	else:
		_river_nodes.clear()
	_update_hint()


## Commit the drawn course through the shared pen core (RiverPen —
## the flyover pen uses the same densify/surface/clamp rules).
func _commit_river() -> void:
	if _river_nodes.size() < 2:
		HUD.notify("river needs at least 2 points")
		return
	RiverPen.commit(_river_nodes)
	_river_nodes.clear()
	_update_hint()


## The RMB travel target: the terrain SURFACE under a screen pixel, in
## world XZ (Vector2.INF when the ray leaves the world). This is the HONEST
## landing the map's fast-travel needs — a ray-march down the height field,
## not the flat y=0 plane _mouse_world uses. Over the baked 16384m tile the
## ground rises hundreds of metres and the orbit camera is steeply pitched,
## so the y=0 intersection drifted the drop as much as a kilometre past the
## click ("RMB doesn't land where I clicked"). Falls back to the y=0 plane
## only when the ray finds no ground (a click on the open sea past the
## coastline), so a travel out to water still answers.
func _travel_target(screen_pos: Vector2) -> Vector2:
	if _cam == null:
		return Vector2.INF
	var org := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	var hit := ray_to_terrain(org, dir, Callable(Terrain, "height"))
	if hit == Vector3.INF:
		if absf(dir.y) < 0.001:
			return Vector2.INF
		hit = org + dir * (-org.y / dir.y)
	return Vector2(hit.x, hit.z)


## March a camera ray onto the terrain surface `sampler` describes — the
## pure heart of _travel_target, testable with a synthetic height field (no
## Camera3D, no Terrain). `sampler.call(x, z) -> float` is the ground height
## at a world XZ (Terrain.height live). Walks `step`-metre strides from the
## origin until the ray first dips to or below the ground, then binary-
## refines the crossing to sub-metre. Returns the world hit, or Vector3.INF
## when the ray points up out of the world, starts under the ground, or
## never meets it within `far`. Coarse-step then refine is robust for the
## whole-tile view (a discrete click, not a per-frame cost); a spike thinner
## than one stride between samples is the only thing it can step over, and
## the map has none at this scale.
static func ray_to_terrain(origin: Vector3, dir: Vector3, sampler: Callable,
		far := 80000.0, step := 40.0) -> Vector3:
	if dir.length_squared() < 1e-12:
		return Vector3.INF
	dir = dir.normalized()
	# Starting under the ground (camera below the surface) has no honest
	# forward hit — the plane fallback in _travel_target owns that case.
	if origin.y - float(sampler.call(origin.x, origin.z)) < 0.0:
		return Vector3.INF
	var prev_t := 0.0
	var t := 0.0
	while t < far:
		t = minf(t + step, far)
		var p := origin + dir * t
		if p.y - float(sampler.call(p.x, p.z)) <= 0.0:
			# Crossing lies in (prev_t, t]: last sample above, this one below.
			var lo := prev_t
			var hi := t
			for _i in 24:
				var mid := (lo + hi) * 0.5
				var pm := origin + dir * mid
				if pm.y - float(sampler.call(pm.x, pm.z)) <= 0.0:
					hi = mid
				else:
					lo = mid
			return origin + dir * hi
		prev_t = t
		if t >= far:
			break
	return Vector3.INF


## Screen mouse → world XZ on the y=0 plane. The map cam is pitched, so
## this carries a little parallax over tall terrain (good enough for a
## whole-world guide brush; the RMB teleport rides _travel_target, which
## ray-marches the surface so its landing is exact).
func _mouse_world() -> Vector2:
	if _cam == null:
		return Vector2.INF
	var org := _cam.project_ray_origin(_mouse)
	var dir := _cam.project_ray_normal(_mouse)
	if absf(dir.y) < 0.001:
		return Vector2.INF
	var hit := org + dir * (-org.y / dir.y)
	return Vector2(hit.x, hit.z)


## Meters per screen pixel at the orbit target — the perspective cousin
## of the old ortho size/viewport ratio, for brush circles + scale bar.
func _m_per_px() -> float:
	var vp_h := maxf(_markers.size.y, 1.0)
	return 2.0 * _rig.distance * tan(deg_to_rad(_cam.fov) * 0.5) / vp_h


## Commit the painted override: recomposite the strokes over the blessed
## tile (scoped — only the painted cells rebuild) and persist the override
## EXR. The tile itself is never written; Strata owns it (P0 seam fix).
func _bake() -> void:
	if _paint_bbox.size == Vector2.ZERO:
		HUD.notify("paint some elevation first")
		return
	Terrain.commit_tile_override(_paint_bbox.grow(128.0))
	Terrain.save_tile_override()
	_paint_bbox = Rect2()
	HUD.notify("override committed — reshaping")


func _update_hint() -> void:
	if _biome_paint:
		var name := "?"
		if _biome_index < Terrain.biomes.size():
			name = String(Terrain.biomes[_biome_index].id)
		_hint.text = "BIOME pen  ·  LMB paint [%d:%s]  ·  1-9 pick · [ ] brush %dm  ·  B commit  ·  G exit" % [
			_biome_index + 1, name, int(_brush_m)]
	elif _river_mode:
		_hint.text = "RIVER pen  ·  LMB add point (%d)  ·  Enter carve  ·  Backspace undo  ·  R exit" % _river_nodes.size()
	elif _paint:
		_hint.text = "PAINT override  ·  LMB raise · Shift lower  ·  [ ] brush %dm  ·  B commit  ·  P exit" % int(_brush_m)
	elif _from_toolkit:
		_hint.text = "drag orbit / WASD pan  ·  wheel zoom  ·  P elevation · R river · G biome  ·  RMB teleport  ·  M close"
	else:
		_hint.text = "drag orbit / WASD pan  ·  wheel zoom  ·  M or Esc close"


## World point → screen, or Vector2.INF when it's behind the camera (an
## orbit view can turn markers around behind you; the old top-down ortho
## never could).
func _screen_point(world: Vector3) -> Vector2:
	if _cam.is_position_behind(world):
		return Vector2.INF
	return _cam.unproject_position(world)


func _draw_markers() -> void:
	if _cam == null:
		return
	var m_per_px := _m_per_px()
	# The paint brush footprint (world-meters → screen px at the target).
	if _paint:
		var r_px := _brush_m / m_per_px
		_markers.draw_circle(_mouse, r_px, Color(0.95, 0.55, 0.25, 0.12))
		_markers.draw_arc(_mouse, r_px, 0.0, TAU, 48, Color(1, 0.6, 0.25, 0.9), 1.5)
	# The biome brush footprint, filled with the selected biome's ink.
	if _biome_paint:
		var r_px := _brush_m / m_per_px
		var ink := Color(0.9, 0.6, 0.3)
		if _biome_index < Terrain.biomes.size():
			ink = Terrain.biomes[_biome_index].ink
		_markers.draw_circle(_mouse, r_px, Color(ink.r, ink.g, ink.b, 0.30))
		_markers.draw_arc(_mouse, r_px, 0.0, TAU, 48, Color(ink.r, ink.g, ink.b, 0.95), 2.0)
	# The river-pen course: dropped points + a rubber band to the cursor.
	if _river_mode:
		var rprev := Vector2.INF
		for wp in _river_nodes:
			var sp := _screen_point(
				Vector3(wp.x, Terrain.height(wp.x, wp.y) + 1.0, wp.y))
			if sp == Vector2.INF:
				continue
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
			var p := _screen_point(
				Vector3(wp.x, Terrain.height(wp.x, wp.y) + 1.0, wp.y))
			if p == Vector2.INF:
				prev = Vector2.INF
				continue
			if prev != Vector2.INF:
				_markers.draw_line(prev, p, Color(0.30, 0.48, 0.62, 0.9), 1.5)
			prev = p
	_draw_player(m_per_px)
	_draw_compass(font)
	_draw_scale_bar(font, m_per_px)


## The player: a dot with a HEADING wedge (what makes a map a map — you,
## and which way you're facing). The body child carries the yaw; the
## characters-face-+Z convention gives the forward vector.
func _draw_player(m_per_px: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var pos: Vector3 = player.global_position + Vector3.UP * 2.0
	var p := _screen_point(pos)
	if p == Vector2.INF:
		return
	var body := player.get_node_or_null("Body") as Node3D
	var yaw: float = body.rotation.y if body else 0.0
	var ahead := pos + Vector3(sin(yaw), 0.0, cos(yaw)) * maxf(m_per_px * 20.0, 4.0)
	var pa := _screen_point(ahead)
	if pa != Vector2.INF and pa != p:
		# A filled wedge pointing where the player faces.
		var dir := (pa - p).normalized()
		var side := Vector2(-dir.y, dir.x)
		_markers.draw_colored_polygon(PackedVector2Array([
			p + dir * 16.0, p + side * 6.0 - dir * 2.0, p - side * 6.0 - dir * 2.0,
		]), Color(1.0, 0.35, 0.45, 0.9))
	_markers.draw_circle(p, 6.0, Color.WHITE)
	_markers.draw_circle(p, 6.0, COLOR_INK, false, 1.5)


## Compass north: the orbit rotates the world under you, so N is a
## needle now, not a fixed top-of-screen letter. North is -Z (the old
## top-down map looked down -Z with north up).
func _draw_compass(font: Font) -> void:
	var anchor := Vector2(_markers.size.x - 46.0, 46.0)
	var pt := _screen_point(_rig.target)
	var pn := _screen_point(_rig.target + Vector3(0.0, 0.0, -_rig.distance * 0.02))
	var dir := Vector2(0, -1)
	if pt != Vector2.INF and pn != Vector2.INF and pn != pt:
		dir = (pn - pt).normalized()
	_markers.draw_circle(anchor, 17.0, Color(0, 0, 0, 0.25))
	_markers.draw_line(anchor - dir * 12.0, anchor + dir * 12.0,
			Color(1, 0.95, 0.9), 1.5)
	_markers.draw_string(font, anchor + dir * 15.0 + Vector2(-5, 5), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.9))


## Adaptive scale bar: the nicest round distance that draws ~120px wide
## (a fixed 100m bar vanishes at 13km zoom).
func _draw_scale_bar(font: Font, m_per_px: float) -> void:
	var vp := _markers.size
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
	var p := _screen_point(world)
	if p == Vector2.INF:
		return
	if p.x < -40 or p.y < -40 or p.x > _markers.size.x + 40 or p.y > _markers.size.y + 40:
		return
	_markers.draw_circle(p, 5.0, col)
	_markers.draw_circle(p, 5.0, Color.WHITE, false, 1.5)
	if _rig.distance < 6000.0:
		_draw_label(font, p + Vector2(10, 5), text)


## region/tile id -> a readable place name (title-cased, "_" → space).
## A place's map label: the gazetteer's name when it has one, else the
## id prettified (the honest floor — a landform with no name still reads).
func _label_for(id: String) -> String:
	if Names.has_name(id):
		return Names.resolve(id)
	return id.replace("_", " ").capitalize()


func _draw_label(font: Font, pos: Vector2, text: String) -> void:
	_markers.draw_string(font, pos + Vector2(1, 1), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.85))
	_markers.draw_string(font, pos, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLOR_INK)
