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
# OVERRIDE layer over the blessed Strata tile (P0 seam fix, ONE_APP.md
# 2026-07-07 — the tile is read-only, no erosion rebake ever) and
# commits on stroke-quiet (a cheap region recomposite reshapes the
# ground under the camera), BIOME retints instantly and re-floras on
# stroke release, RIVER drops points on the terrain and carves on
# Enter. The map keeps its pens for whole-world strokes — both ride
# the same shared cores (Terrain.paint_tile_override, RiverPen).
const PEN_RATE_M := 90.0  # meters of override per second at brush center
const PEN_QUIET_COMMIT := 0.25  # seconds of stroke-quiet before commit
# Crash-safety flush (audit 2026-07-08): hand edits used to live only in
# memory until F5/exit — a crash lost the session. A few seconds after
# the last stroke the dirty layers write through the SAME F5 path,
# automatically. Long enough after PEN_QUIET_COMMIT that the recomposite
# has already landed; never while the button is down.
const FLUSH_QUIET := 3.0  # seconds of hand-quiet before the disk flush
const MACRO_MIN := 24.0
const MACRO_MAX := 1200.0
const BRUSH_MIN := 3.0  # sculpt brush range (the [ ] keys and the link)
const BRUSH_MAX := 64.0

# PLACE selection (placement v2, audit #1): the hand can pick what it
# placed and edit IT — move, rotate, scale, targeted delete. RMB picks
# the nearest record within reach of the ground hit; the edit keys ride
# the InputMap (place_* actions) so `toolkit keys` reports them live.
const SEL_PICK_M := 4.0  # pick radius around the RMB ground hit
const SEL_YAW_STEP := TAU / 24.0  # 15 degrees per rotate tap
const SEL_SCALE_STEP := 1.08  # per scale tap ( , shrinks · . grows )
const SEL_SCALE_MIN := 0.25
const SEL_SCALE_MAX := 4.0

enum Tool { SCULPT, PLACE, TERRAIN, BIOME, RIVER }
const TOOL_NAMES: Array[String] = ["sculpt", "place", "terrain", "biome", "river"]

var active := false
var hud_on := true  # the text-overlay switch (StrataLink `hud`; the viewer boots dark)

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
var _palette: Array = []  # Cards.placeable(), cached at _ready
var _place_index := 0     # flat index into _palette
var _world_panel: Label
var _panel_accum := 0.0
var _sculpt_undo: Image = null
var _sculpt_unsaved := false  # sculpt strokes newer than the disk layer
var _flush_quiet := 0.0  # seconds since the last hand edit (the flush clock)
var _flatten_target := 0.0
var _flattening := false
var _stroke_live := false

# PLACE selection state: identity is the record's stable id plus the
# cell it lives in (the Chronicle is the truth — the marker and HUD read
# the record back every frame, so a deletion under us deselects instead
# of showing a ghost). _place_undo is the one-deep memento, shaped
# {op, cell, id, before} so undo v2 can deepen it into a stack later.
var _sel_cell := Vector2i.ZERO
var _sel_id := ""
var _sel_marker: MeshInstance3D
var _place_undo: Dictionary = {}

# TERRAIN pen state (paints Terrain's tile override layer).
var _pen_undo: Image = null
var _pen_dirty := false
var _pen_quiet := 0.0
var _pen_bbox := Rect2()  # painted world region (scoped rebuild on commit)
var _terrain_unsaved := false

# BIOME pen state.
var _biome_index := 4
var _biome_dirty := Rect2()
var _biome_stroke := false
var _biome_unsaved := false
var _biome_undo: Image = null  # one-deep pre-stroke memento (Z)
var _biome_undo_rect := Rect2()  # region painted since that memento

# RIVER pen state.
var _river_nodes: Array[Vector2] = []
var _river_preview: MeshInstance3D

# ORBIT view (the generator's viewport, P8): the camera rides spherical
# coords around a target instead of flying — drag orbits, wheel zooms,
# visible cursor (no capture), tools inert. Mirrors Strata's Metal-view
# feel so swapping the renderer doesn't change the hand. The math and
# input live in OrbitRig — the map screen rides the same rig.
var orbit := false
var _orbit := OrbitRig.new()


## Boot posture (DECISIONS 2026-07-05, build-out item 1): launched with
## `--toolkit`, the game skips the title and drops straight into the editor
## — the fly camera live over the world the moment the player streams in.
## Dev-only, like the F1 toggle it shares. One truth for title + toolkit.
static func launch_requested() -> bool:
	return OS.is_debug_build() and (
		OS.get_cmdline_user_args().has("--toolkit")
		or OS.get_cmdline_args().has("--toolkit")) or viewer_requested()


## The VIEWER posture (ONE_APP P8: the terrain generator's own viewport,
## engine-rendered): `--viewer` boots the toolkit posture but lands in
## ORBIT view framing the whole world tile — Strata's generator preview
## with the game's shaders, sky, sea, and hours. HUD starts hidden.
static func viewer_requested() -> bool:
	return OS.is_debug_build() and (
		OS.get_cmdline_user_args().has("--viewer")
		or OS.get_cmdline_args().has("--viewer"))


func _ready() -> void:
	_palette = Cards.placeable()  # card-driven PLACE palette (the Kit from cards)
	hud_on = not viewer_requested()  # the viewer posture boots dark (P8)
	if launch_requested():
		if get_tree().get_first_node_in_group("player") != null:
			_enter.call_deferred()  # world IS the main scene: player already here
		else:
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
		if orbit:  # orbit view: the target moves, the orbit follows
			_orbit.target = Vector3(xz.x, 0.0, xz.y)


## Switch between the fly camera and the ORBIT view (the generator's
## viewport). Entering orbit frames the whole world tile like Strata's
## Metal view; leaving returns the free fly camera where it stands.
func set_view_mode(p_orbit: bool) -> void:
	orbit = p_orbit
	if orbit:
		_orbit.frame_tile()
		if _cam:
			# The generator view is a CHART with weather (the map-screen
			# lesson): the world's air minus the fogs (OrbitRig has the
			# recipe) so time-of-day and weather read without obscuring.
			var world_env := get_viewport().world_3d.environment
			if world_env and _cam.environment == null:
				_cam.environment = OrbitRig.chart_environment(world_env)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif active:
		if _cam:
			_cam.far = 8000.0
			_cam.environment = null  # back under the world's real air
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	return "\n".join(lines)


## The world panel's sections, [name, text] pairs — ONE builder feeds the
## O overlay and the link's `panel` verb (chrome contract v2: the in-game
## panel and Strata's inspector render the SAME truth, so they cannot
## drift). Text may be multi-line; each renderer flattens it its own way.
## Data, not hand state — answers with or without the hand (the sims are
## always on).
func panel_sections() -> Array:
	var loom := get_tree().get_first_node_in_group("world_streamer")
	return [
		["HERE", _here_summary()],
		["AIR", Weather.summary()],
		["CLIMATE", Climate.summary()],
		["WATER", Hydrology.summary()],
		["FIELD", WaterField.summary()],
		["WAVES", WaterWaves.summary()],
		["SWELL", SeaSwell.summary()],
		["FLORA", FloraLife.summary()],
		["SPRING", FabricSpring.summary()],
		["SAND", SandField.summary()],
		["WEAR", InteractionField.summary()],
		["WAYS", Nav.summary()],
		["LAND", Terrain.regions_summary().split("\n")[0]],
		["FABRIC", loom.fabric_summary() if loom else "no world streaming"],
		["CARDS", Cards.summary()],
		["DOORS", Interiors.summary()],
		["STORY", Story.summary()],
		["LINK", StrataLink.summary()],
	]


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
	# ORBIT view: visible cursor, LMB-drag orbits, wheel zooms — the
	# generator-viewport hand. Tools are inert here (fly mode paints).
	if orbit:
		_orbit.handle_input(event)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.55, 1.55)
	elif event.is_action_pressed("toolkit_save"):
		Terrain.save_edits()
		_sculpt_unsaved = false
		_save_pens()
		CellRecords.flush()  # pending placement edits land with F5 too
		Overrides.emit()  # the seam artifact rides every save (P4)
	elif event.is_action_pressed("toolkit_tool"):
		_tool = ((_tool as int) + 1) % Tool.size() as Tool
		if _tool == Tool.TERRAIN and not Terrain.has_world_tile():
			HUD.notify("no baked tile — import a Strata world first")
		_update_hud()
	elif event.is_action_pressed("toolkit_undo"):
		_undo()
	# The selection's edit keys (placement v2) — PLACE mode only, so G/R
	# stay free for future tools elsewhere. Each tap is its own stroke:
	# one memento, one Z.
	elif _tool == Tool.PLACE and event.is_action_pressed("place_move"):
		_sel_move_to(_ray_to_ground())
	elif _tool == Tool.PLACE and event.is_action_pressed("place_rotate"):
		_sel_rotate(-1.0 if Input.is_action_pressed("sprint") else 1.0)
	elif _tool == Tool.PLACE and event.is_action_pressed("place_grow"):
		_sel_scale(1)
	elif _tool == Tool.PLACE and event.is_action_pressed("place_shrink"):
		_sel_scale(-1)
	elif _tool == Tool.PLACE and event.is_action_pressed("place_delete"):
		_sel_delete()
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
		if _tool == Tool.PLACE:
			_step_palette(1)
		elif _tool == Tool.TERRAIN or _tool == Tool.BIOME:
			_macro_radius = minf(_macro_radius * 1.3, MACRO_MAX)
		else:
			_brush_radius = minf(_brush_radius * 1.3, BRUSH_MAX)
	elif event.is_action_pressed("brush_smaller"):
		if _tool == Tool.PLACE:
			_step_palette(-1)
		elif _tool == Tool.TERRAIN or _tool == Tool.BIOME:
			_macro_radius = maxf(_macro_radius / 1.3, MACRO_MIN)
		else:
			_brush_radius = maxf(_brush_radius / 1.3, BRUSH_MIN)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_O:
		# The world panel: every system's Toolkit summary, live.
		_world_panel.visible = not _world_panel.visible
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_N:
		# Navmesh overlay: see what the world thinks is walkable.
		NavigationServer3D.set_debug_enabled(not NavigationServer3D.get_debug_enabled())
	elif event.is_action_pressed("ui_cancel"):
		# Esc deselects first; a second Esc releases the mouse as before.
		if _tool == Tool.PLACE and _sel_id != "":
			_deselect()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
		# Number keys pick within the active tool's palette.
		if _tool == Tool.BIOME:
			_biome_index = clampi(event.physical_keycode - KEY_1,
				0, Terrain.biomes.size() - 1)
			_update_hud()
		elif _tool == Tool.PLACE:
			# Number keys jump the palette to a category's first slot.
			_jump_category(event.physical_keycode - KEY_1)
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
				_place_at(hit)
		elif event.button_index == MOUSE_BUTTON_LEFT and _tool == Tool.RIVER:
			var hit := _ray_to_ground()
			if hit != Vector3.INF:
				_river_nodes.append(Vector2(hit.x, hit.z))
				_update_hud()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _tool == Tool.PLACE:
			# Pick (placement v2): RMB on a placed thing selects it, on
			# empty ground deselects — the click-away idiom. The sim
			# inspector keeps RMB in every other tool.
			_pick_at(_ray_to_ground())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Sim inspector: right-click an agent (wildlife) to watch its mind.
			var space := _cam.get_world_3d().direct_space_state
			var params := PhysicsRayQueryParameters3D.create(
				_cam.global_position, _cam.global_position - _cam.global_basis.z * 3000.0, 3
			)
			var result := space.intersect_ray(params)
			_inspected = result.collider if result and result.collider.has_method("sim_debug") \
					else null
			_inspector.visible = _inspected != null


## Z — the one-deep per-tool memento. Every tool answers for ITSELF, by
## name: a mode with nothing to undo is a no-op with a HUD notice, NEVER
## a cross-tool action (the audit's Z footgun: the old default branch
## fell through to CellRecords.remove_last, so Z in biome mode silently
## deleted a placed object). PLACE rides its {op, cell, id, before}
## memento (placement v2): place/edit/delete each revert targeted, by
## record id; the LIFO remove_last survives only as the no-memento
## fallback over placements from an earlier session.
func _undo() -> void:
	match _tool:
		Tool.SCULPT:
			if _sculpt_undo != null:
				# Revert to the pre-stroke snapshot of the edit layer.
				Terrain.restore_edits(_sculpt_undo)
				_sculpt_undo = null
				_sculpt_unsaved = true  # the revert itself needs the flush
			else:
				HUD.notify("sculpt: nothing to undo")
		Tool.TERRAIN:
			if _pen_undo != null:
				# Restore the pre-stroke override (recomposites + reshapes
				# immediately).
				Terrain.restore_tile_override(_pen_undo.duplicate())
				_pen_dirty = false
				_pen_bbox = Rect2()
				_terrain_unsaved = true
			else:
				HUD.notify("terrain: nothing to undo")
		Tool.BIOME:
			if _biome_undo != null:
				# The pre-stroke index map returns: tint instantly, flora
				# re-composed over the undone region only.
				Terrain.restore_biome_map(_biome_undo, _biome_undo_rect)
				_biome_undo = null
				_biome_undo_rect = Rect2()
				_biome_dirty = Rect2()
				_biome_stroke = false
				_biome_unsaved = true  # the revert itself needs the flush
			else:
				HUD.notify("biome: nothing to undo")
		Tool.RIVER:
			if not _river_nodes.is_empty():
				_river_nodes.pop_back()
				_update_hud()
			else:
				HUD.notify("river: nothing to undo")
		Tool.PLACE:
			if not _place_undo.is_empty():
				_undo_place_op()
			else:
				# No memento this session: the old LIFO fallback under
				# the cursor keeps Z useful over yesterday's placements.
				var hit := _ray_to_ground()
				if hit == Vector3.INF \
						or not CellRecords.remove_last(CellRecords.cell_of(hit)):
					HUD.notify("place: nothing to undo here")


# --- PLACE selection (placement v2, audit #1): the Creation Kit edits
# what it placed. RMB picks a record, G moves it to the cursor, R turns
# it (Shift reverses), , . scale it, X deletes THAT one, Z reverts the
# last of any of these through the one-deep memento. Yaw/scale stay
# randomized at placement — but as DATA in the record, editable after.


## Place the palette's current slot at a ground hit — the LMB path,
## split out so the scene tests can drive it headless (the
## _biome_paint_at pattern). Records the {op place} memento: Z removes
## THIS record by id, never someone else's LIFO tail.
func _place_at(hit: Vector3) -> void:
	if _palette.is_empty():
		return
	var slot: Dictionary = _palette[_place_index % _palette.size()]
	# Store the RESOLVED file (deterministic variant by position),
	# never the slot — retiring a placeholder can't move it.
	var file: String = Cards.resolve(slot["slot"],
			Cards.variant_for(slot["slot"], hit))
	if file == "":
		return
	var rec: Dictionary = CellRecords.add(hit, file,
			randf() * TAU, randf_range(0.85, 1.15))
	_place_undo = {"op": "place", "cell": CellRecords.cell_of(hit),
			"id": String(rec["id"]), "before": {}}


## The selected record, straight from the Chronicle ({} when nothing is
## selected or the record has since been removed — the marker and HUD
## read through this so they can never show a ghost).
func _selected() -> Dictionary:
	if _sel_id == "":
		return {}
	return CellRecords.record(_sel_cell, _sel_id)


## RMB in PLACE mode: nearest placed record within reach of the ground
## hit selects it; empty ground deselects. A legacy record (pre-id row)
## is named on the spot — selection needs identity.
func _pick_at(hit: Vector3) -> void:
	if hit == Vector3.INF:
		return
	var found: Dictionary = CellRecords.find_at(hit, SEL_PICK_M)
	if found.is_empty():
		_deselect()
		return
	_sel_cell = found["cell"]
	_sel_id = CellRecords.ensure_id(_sel_cell, found["rec"])
	_update_hud()


func _deselect() -> void:
	_sel_id = ""
	if _sel_marker:
		_sel_marker.visible = false
	_update_hud()


## G — move the selection to the cursor's ground hit: grab-and-place-
## again as one keystroke. The ground-relative law holds: the record
## keeps its height offset, so it seats at the NEW ground plus the same
## dy (a bench moved uphill stays ON the hill, not at its old altitude).
func _sel_move_to(hit: Vector3) -> void:
	var rec := _selected()
	if rec.is_empty():
		HUD.notify("place: nothing selected (RMB picks)")
		return
	if hit == Vector3.INF:
		return
	_memento_edit(rec)
	# The effective offset covers every record vintage — snap (0),
	# ground_dy, legacy absolute-Y: seat_y is the one truth for where
	# it rides today.
	var dy: float = CellRecords.seat_y(rec) \
			- Terrain.height(float(rec.x), float(rec.z))
	_sel_cell = CellRecords.update(_sel_cell, _sel_id, {
		"x": hit.x, "z": hit.z,
		"y": Terrain.height(hit.x, hit.z) + dy,
		"ground_dy": dy,
	})
	_place_undo["cell"] = _sel_cell  # revert must find it where it lives NOW
	_flush_quiet = 0.0
	_update_hud()


## R — turn the selection one yaw step (Shift reverses, the carve idiom).
func _sel_rotate(dir: float) -> void:
	var rec := _selected()
	if rec.is_empty():
		HUD.notify("place: nothing selected (RMB picks)")
		return
	_memento_edit(rec)
	_sel_cell = CellRecords.update(_sel_cell, _sel_id, {
		"yaw": wrapf(float(rec.yaw) + dir * SEL_YAW_STEP, 0.0, TAU)})
	_flush_quiet = 0.0
	_update_hud()


## , . — scale the selection one step, clamped sane.
func _sel_scale(dir: int) -> void:
	var rec := _selected()
	if rec.is_empty():
		HUD.notify("place: nothing selected (RMB picks)")
		return
	_memento_edit(rec)
	var s: float = float(rec.get("scale", 1.0))
	s = clampf((s * SEL_SCALE_STEP) if dir > 0 else (s / SEL_SCALE_STEP),
			SEL_SCALE_MIN, SEL_SCALE_MAX)
	_sel_cell = CellRecords.update(_sel_cell, _sel_id, {"scale": s})
	_flush_quiet = 0.0
	_update_hud()


## X — delete the SELECTED object. With nothing selected, the old LIFO
## remove_last under the cursor survives as the fallback.
func _sel_delete() -> void:
	var rec := _selected()
	if rec.is_empty():
		var hit := _ray_to_ground()
		if hit == Vector3.INF \
				or not CellRecords.remove_last(CellRecords.cell_of(hit)):
			HUD.notify("place: nothing selected, nothing here to remove")
		return
	var gone: Dictionary = CellRecords.remove(_sel_cell, _sel_id)
	_place_undo = {"op": "delete", "cell": _sel_cell, "id": _sel_id,
			"before": gone}
	_deselect()
	HUD.notify("deleted — Z brings it back")


## Take the one-deep edit memento BEFORE a field lands: the whole record
## as it stood, so Z restores it bit-exact (unknown keys included) even
## across a cell migration. {record-id, before-state} — undo v2 stacks
## these without reshaping them.
func _memento_edit(rec: Dictionary) -> void:
	_place_undo = {"op": "edit", "cell": _sel_cell, "id": _sel_id,
			"before": rec.duplicate()}


## Revert the one-deep placement memento: a place comes OUT (targeted,
## by id), a delete comes BACK bit-exact and selected again, an edit
## returns to its before-state (cell migration and all). Consumed on use.
func _undo_place_op() -> void:
	var m: Dictionary = _place_undo
	_place_undo = {}
	var cell: Vector2i = m["cell"]
	var id := String(m["id"])
	match String(m["op"]):
		"place":
			CellRecords.remove(cell, id)
			if _sel_id == id:
				_deselect()
			HUD.notify("place undone")
		"delete":
			_sel_cell = CellRecords.insert(m["before"])
			_sel_id = id  # the returned object is the selection again
			HUD.notify("delete undone")
		"edit":
			if CellRecords.remove(cell, id).is_empty():
				HUD.notify("place: that object is gone — nothing to undo")
				return
			var back: Vector2i = CellRecords.insert(m["before"])
			if _sel_id == id:
				_sel_cell = back
			HUD.notify("edit undone")
	_update_hud()


func _process(delta: float) -> void:
	if not active:
		return
	if orbit:
		# Spherical ride around the target; WASD pans the target in the
		# camera's ground plane (the Strata-viewport hand, in-engine).
		_orbit.pan(Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"), delta)
		_orbit.apply(_cam)
		_cursor.visible = false
		_sel_marker.visible = false  # tools are inert here; so is the pick
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
			# The sections come from the ONE builder the link's `panel`
			# verb reads too; only the indentation is the overlay's own.
			var rows := PackedStringArray()
			for s: Array in panel_sections():
				rows.append("%-9s%s" % [s[0],
					String(s[1]).replace("\n", "\n         ")])
			_world_panel.text = "\n".join(rows)

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
		# TERRAIN pen: paint the override on the ground; commit on quiet.
		if _tool == Tool.TERRAIN and painting and Terrain.has_world_tile():
			if not _stroke_live:
				_stroke_live = true
				_pen_undo = Terrain.snapshot_tile_override()  # Z reverts
			var dir_g := -1.0 if Input.is_action_pressed("sprint") else 1.0
			var painted: Rect2 = Terrain.paint_tile_override(
				Vector2(hit.x, hit.z), _macro_radius,
				dir_g * PEN_RATE_M * delta)
			if painted.size != Vector2.ZERO:
				_pen_dirty = true
				_pen_quiet = 0.0
				# Accumulate the painted world region so the commit rebuilds
				# only these cells (grown so the bilinear skirt lands too).
				var pr := painted.grow(128.0)
				_pen_bbox = pr if _pen_bbox.size == Vector2.ZERO \
						else _pen_bbox.merge(pr)
		# BIOME pen: instant tint; flora re-composes on stroke release.
		elif _tool == Tool.BIOME and painting:
			_biome_paint_at(hit)
		if _tool == Tool.SCULPT and painting:
			if not _stroke_live:
				# Stroke begins: snapshot for Z-undo.
				_stroke_live = true
				_sculpt_undo = Terrain.snapshot_edits()
				_sculpt_unsaved = true
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

	# TERRAIN pen: commit on stroke-quiet — a scoped recomposite (blessed
	# tile + override, painted rect only) reshapes the ground you're
	# watching. No erosion, no disk write; persistence waits for F5/exit.
	if _pen_dirty:
		_pen_quiet += delta
		if _pen_quiet >= PEN_QUIET_COMMIT \
				and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_pen_dirty = false
			Terrain.commit_tile_override(_pen_bbox)
			_pen_bbox = Rect2()
			_terrain_unsaved = true

	# BIOME pen: the tint was live per-stroke; flora re-composes once,
	# on release (cell rebuilds ride the streamer's finish budget).
	if _biome_stroke and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_biome_stroke = false
		if _biome_dirty.size != Vector2.ZERO:
			Terrain.commit_biome_paint(_biome_dirty)
			_biome_dirty = Rect2()

	# The selection ring rides its record every frame — records re-seat
	# when the ground changes, and a marker that lagged that would lie.
	# A record removed out from under us (remove_last, another Z)
	# deselects instead of haunting.
	if _tool == Tool.PLACE and _sel_id != "":
		var sel := _selected()
		if sel.is_empty():
			_deselect()
		else:
			var sc: float = float(sel.get("scale", 1.0))
			_sel_marker.visible = true
			_sel_marker.scale = Vector3.ONE * (2.0 * sc)
			_sel_marker.global_position = Vector3(float(sel.x),
				CellRecords.seat_y(sel) + 0.4, float(sel.z))
	elif _sel_marker.visible:
		_sel_marker.visible = false

	# The crash-safety flush: while any hand-edited layer is newer than
	# disk and the hand is quiet, the clock runs; at FLUSH_QUIET the dirty
	# layers write through the SAME path F5 uses. Editor-only by
	# construction (_process is gated on `active`), so the sim and the
	# soak digest never see it. Placement EDITS ride the same clock
	# (CellRecords.update defers its disk write to flush); place/delete
	# stay write-through per click, as they always were.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			or not (_sculpt_unsaved or _terrain_unsaved
				or _biome_unsaved or _pen_dirty or CellRecords.has_dirty()
				or Overrides.pending):
		_flush_quiet = 0.0
	else:
		_flush_quiet += delta
		if _flush_quiet >= FLUSH_QUIET:
			_flush_hand_edits()  # leaves every flag clean

	_update_river_preview()


# Persist what the pens changed (F5 and exit, beside the sculpt layer).
# Only the OVERRIDE layer is written — the blessed tile never is.
func _save_pens() -> void:
	if _biome_unsaved:
		Terrain.save_biome_map()
		_biome_unsaved = false
	if _pen_dirty:
		# A stroke still waiting on quiet: commit before persisting.
		_pen_dirty = false
		Terrain.commit_tile_override(_pen_bbox)
		_pen_bbox = Rect2()
		_terrain_unsaved = true
	if _terrain_unsaved:
		Terrain.save_tile_override()
		_terrain_unsaved = false
		HUD.notify("terrain override saved")


## One biome-pen application under the cursor (the _process stroke path,
## split out so the scene test can drive a stroke headless). The first
## touch of a stroke takes the one-deep Z memento — the sculpt pattern.
func _biome_paint_at(hit: Vector3) -> void:
	if not _biome_stroke:
		_biome_stroke = true
		_biome_undo = Terrain.snapshot_biome_map()
		_biome_undo_rect = Rect2()
	var painted: Rect2 = Terrain.paint_biome_index(
		hit.x, hit.z, _macro_radius, _biome_index)
	if painted.size == Vector2.ZERO:
		return
	_biome_dirty = painted if _biome_dirty.size == Vector2.ZERO \
			else _biome_dirty.merge(painted)
	_biome_undo_rect = painted if _biome_undo_rect.size == Vector2.ZERO \
			else _biome_undo_rect.merge(painted)
	_biome_unsaved = true
	_flush_quiet = 0.0


## The stroke-quiet disk flush (crash-safety): exactly the writes F5
## makes, fired automatically once the hand has been quiet FLUSH_QUIET
## seconds with unsaved layers. Reuses the manual-save path wholesale —
## the flush IS the save, just unprompted.
func _flush_hand_edits() -> void:
	if _sculpt_unsaved:
		Terrain.save_edits()
		_sculpt_unsaved = false
	if _pen_dirty or _terrain_unsaved or _biome_unsaved:
		_save_pens()
	if CellRecords.has_dirty():
		CellRecords.flush()  # deferred placement edits (move/rotate/scale)
	Overrides.emit()  # the P4 seam artifact: overrides.json tracks the flush
	_flush_quiet = 0.0


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
	_hud.visible = hud_on
	_update_hud()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	set_process(true)
	# The VIEWER posture: land in orbit framing the whole tile, HUD dark
	# (hud_on defaulted false in _ready) — the generator's viewport,
	# engine-rendered (Strata boots the pane so).
	if Toolkit.viewer_requested():
		set_view_mode(true)


func _exit() -> void:
	active = false
	Terrain.save_edits()
	_sculpt_unsaved = false
	_save_pens()
	CellRecords.flush()
	Overrides.emit()
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

	# The selection ring (placement v2): an unshaded cyan torus seated on
	# the picked record — cheap, readable from the air, no per-mesh
	# outline machinery. Scales with the record so a grown crate keeps
	# its halo.
	var sel_mat := StandardMaterial3D.new()
	sel_mat.albedo_color = Color(0.25, 0.95, 1.0)
	sel_mat.emission_enabled = true
	sel_mat.emission = Color(0.25, 0.95, 1.0)
	sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring := TorusMesh.new()
	ring.inner_radius = 0.85
	ring.outer_radius = 1.0
	ring.material = sel_mat
	_sel_marker = MeshInstance3D.new()
	_sel_marker.mesh = ring
	_sel_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sel_marker.visible = false
	add_child(_sel_marker)

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
			if _palette.is_empty():
				_hud_label.text = "TOOLKIT·PLACE   (no cards) | Tab next tool | F1 exit"
			else:
				var slot: Dictionary = _palette[_place_index % _palette.size()]
				var nm: String = String(slot["slot"]).trim_prefix(String(slot["category"]) + "/")
				var syn := " ~synth" if slot["status"] == "placeholder-synth" else ""
				# 1-9 jump categories; the numbered list shows which is where.
				var cats: Array = Cards.placeable_categories()
				var tabs: Array[String] = []
				for i in mini(cats.size(), 9):
					var mark := "[%d %s]" if cats[i] == slot["category"] else "%d %s"
					tabs.append(mark % [i + 1, cats[i]])
				_hud_label.text = "TOOLKIT·PLACE   %s › %s (%dv%s) %d/%d   %s   |   LMB place · RMB pick · [ ] item · 1-9 category · Z undo · X remove · Tab tool · F1 exit" % [
					slot["category"], nm, int(slot["variants"]), syn,
					_place_index + 1, _palette.size(), " ".join(tabs)]
			# The selection's own line: what is picked, exactly as data
			# (id, yaw, scale), and the keys that edit it.
			var sel := _selected()
			if not sel.is_empty():
				_hud_label.text += "\nSEL %s #%s  yaw %.0f°  ×%.2f   |   G move here · R rotate (Shift back) · , . scale · X delete · Z undo · Esc deselect" % [
					String(sel.kit).get_file().get_basename(),
					String(sel.get("id", "?")), rad_to_deg(float(sel.yaw)),
					float(sel.get("scale", 1.0))]
		Tool.TERRAIN:
			_hud_label.text = "TOOLKIT·TERRAIN (override)   LMB raise · Shift lower — lands when you pause | [ ] brush %dm | Z undo stroke | Tab next tool | F1 exit" % int(_macro_radius)
		Tool.BIOME:
			var bnames: Array[String] = []
			for i in mini(Terrain.biomes.size(), 9):
				var bid := String(Terrain.biomes[i].id)
				bnames.append(("[%d %s]" if i == _biome_index else "%d %s") % [i + 1, bid])
			_hud_label.text = "TOOLKIT·BIOME   " + " · ".join(bnames) \
					+ "   |   LMB paint (re-flora on release) | Z undo stroke | [ ] brush %dm | Tab next tool" % int(_macro_radius)
		Tool.RIVER:
			_hud_label.text = "TOOLKIT·RIVER   LMB drop point (%d) | Enter carve | Z undo point | Tab next tool | F1 exit" % _river_nodes.size()


## Step the PLACE palette by ±1 slot (wraps).
func _step_palette(d: int) -> void:
	if _palette.is_empty():
		return
	_place_index = wrapi(_place_index + d, 0, _palette.size())
	_update_hud()


## Jump the PLACE palette to the first slot of the n-th category.
func _jump_category(n: int) -> void:
	var cats: Array = Cards.placeable_categories()
	if n < 0 or n >= cats.size():
		return
	var target = cats[n]
	for i in _palette.size():
		if _palette[i]["category"] == target:
			_place_index = i
			_update_hud()
			return


# --- StrataLink hooks (ONE_APP P9·C: the Toolkit in Strata's toolbar).
# Strata's native chrome drives the hand through these — they read and
# write the SAME state the keyboard uses (never a parallel store), so
# the toolbar mirror and the keys cannot drift. The link gates them on
# `active` (no hand, honest error), so _update_hud always has its label.


## Everything Strata's toolbar mirror needs in one read (the link's
## `toolkit status`, polled on pane focus so the mirror never lies).
func link_state() -> Dictionary:
	var count := _palette.size()
	var idx := (_place_index % count) + 1 if count > 0 else 0
	var biome := ""
	if _biome_index >= 0 and _biome_index < Terrain.biomes.size():
		biome = String(Terrain.biomes[_biome_index].id)
	# The selection rides along (placement v2) so Strata's mirror can
	# grow an inspector without a new verb — empty strings mean none.
	var sel := _selected()
	# The tools' text options, data-driven (chrome contract v2): every
	# name a tool shows as in-game text rides the state so Strata can
	# render real pickers — the biome/macro-terrain names from the
	# profile's own table (never hardcoded), the PLACE categories from
	# the card catalog, the river pen's pending point count.
	var biome_ids: Array[String] = []
	for b in Terrain.biomes:
		biome_ids.append(String(b.id).replace(",", "_").replace(" ", "_"))
	var cats: Array[String] = []
	for c in Cards.placeable_categories():
		cats.append(String(c).replace(",", "_").replace(" ", "_"))
	return {
		"tool": TOOL_NAMES[_tool],
		"view": "orbit" if orbit else "fly",
		"brush_m": brush_m(),
		"biome": _biome_index + 1, "biome_id": biome,
		"biome_ids": biome_ids, "cats": cats,
		"river": _river_nodes.size(),
		"place": idx, "place_count": count,
		"place_slot": String(_palette[idx - 1]["slot"]) if count > 0 else "",
		"hud": hud_on,
		"sel_id": String(sel.get("id", "")),
		"sel_kit": String(sel.get("kit", "")),
		"sel_yaw": float(sel.get("yaw", 0.0)),
		"sel_scale": float(sel.get("scale", 1.0)),
	}


## The hand's key bindings in one machine-readable line (the link's
## `toolkit keys` — Strata renders honest help from THIS instead of
## hardcoding a copy). Space-separated `<binding>=<meaning>` tokens;
## action-backed bindings read the live InputMap, so a project.godot
## rebind changes the reply, not just the behavior. Binding names are
## Godot key names (OS.get_keycode_string: BracketLeft is the [ key),
## spaces stripped; LMB/RMB/Wheel name the mouse. Static data, not
## state — answers with or without the hand.
func link_keys() -> String:
	var fly := _key_of("move_forward") + _key_of("move_left") \
			+ _key_of("move_back") + _key_of("move_right")
	var pairs: Array[String] = [
		_key_of("toolkit_toggle") + "=toolkit",
		_key_of("toolkit_tool") + "=tool",
		_key_of("toolkit_undo") + "=undo",
		_key_of("toolkit_save") + "=save",
		_key_of("brush_smaller") + "=smaller",
		_key_of("brush_bigger") + "=bigger",
		"1-9=pick",
		# The selection's edit keys (placement v2, PLACE mode).
		_key_of("place_move") + "=move",
		_key_of("place_rotate") + "=rotate",
		_key_of("place_shrink") + "=shrink",
		_key_of("place_grow") + "=grow",
		_key_of("place_delete") + "=delete",
		"O=panel",
		"N=navmesh",
		_key_of("map") + "=map",
		"Enter=carve",
		_key_of("ui_cancel") + "=release",
		fly + "=fly",
		_key_of("toolkit_up") + "=up",
		_key_of("toolkit_down") + "=down",
		_key_of("sprint") + "=fast",
		"Ctrl=flatten",
		"LMB=apply",
		"RMB=pick/inspect",
		"Wheel=speed",
	]
	return " ".join(pairs)


## The first keyboard key bound to an action, as a spaceless token
## ("?" when the action has no key — the reply stays parseable).
func _key_of(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k != null:
			var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
			return OS.get_keycode_string(code).replace(" ", "")
	return "?"


## Enter/exit the hand remotely (the link's `toolkit on|off` — what F1
## does, minus the key; chrome contract v2: the flyover one click away).
## Returns the state that RESULTED: entering without a player (title
## screen) stays off, and the link errs honestly on the mismatch.
func set_active(on: bool) -> bool:
	if on and not active:
		_enter()
	elif not on and active:
		_exit()
	return active


## One Z, remotely (the link's `toolkit undo` — Strata's Undo In Game
## menu item). The SAME per-tool memento dispatch as the key; a mode
## with nothing to undo notices instead of acting (and while the chrome
## drives, that notice rides the `notices` drain).
func undo_last() -> void:
	_undo()


## The last RMB-inspected agent (the link's `inspect` verb) — read back
## through validity every call, so a despawned animal reads as nothing
## instead of a freed-object crash. Same honesty as the on-screen label.
func inspected() -> Node:
	if _inspected != null and is_instance_valid(_inspected) \
			and _inspected.has_method("sim_debug"):
		return _inspected
	return null


## Switch the active tool by name; false on an unknown name.
func set_tool(p_tool: String) -> bool:
	var i := TOOL_NAMES.find(p_tool)
	if i < 0:
		return false
	_tool = i as Tool
	if _tool == Tool.TERRAIN and not Terrain.has_world_tile():
		HUD.notify("no baked tile — import a Strata world first")
	_update_hud()
	return true


## The active tool's brush radius in meters (TERRAIN/BIOME ride the
## macro brush, everything else the sculpt brush — the same split as [ ]).
func brush_m() -> float:
	if _tool == Tool.TERRAIN or _tool == Tool.BIOME:
		return _macro_radius
	return _brush_radius


## Set the active tool's brush, clamped to its keyboard range; returns
## the radius that actually landed (the link replies with it).
func set_brush_m(m: float) -> float:
	if _tool == Tool.TERRAIN or _tool == Tool.BIOME:
		_macro_radius = clampf(m, MACRO_MIN, MACRO_MAX)
		return _macro_radius
	_brush_radius = clampf(m, BRUSH_MIN, BRUSH_MAX)
	return _brush_radius


## Pick the biome by its 1-9 key number; false when out of range.
func set_biome(n: int) -> bool:
	if n < 1 or n > mini(9, Terrain.biomes.size()):
		return false
	_biome_index = n - 1
	_update_hud()
	return true


## Select the PLACE palette slot by 1-based index or card slot name;
## returns the landed 1-based index, 0 when not found / no cards.
func set_place_slot(arg: String) -> int:
	if _palette.is_empty():
		return 0
	if arg.is_valid_int():
		var n := int(arg)
		if n < 1 or n > _palette.size():
			return 0
		_place_index = n - 1
	else:
		var found := -1
		for i in _palette.size():
			if _palette[i]["slot"] == arg:
				found = i
				break
		if found < 0:
			return 0
		_place_index = found
	_update_hud()
	return _place_index + 1


## Hide/show the Toolkit's text overlay (the link's `hud` verb — the
## embedded pane goes chrome-less when Strata's toolbar is driving).
## The switch persists across enter/exit; the HUD autoload rides along
## in strata_link so ALL on-screen text goes dark together.
func set_hud_visible(on: bool) -> void:
	hud_on = on
	if _hud:
		_hud.visible = on and active
