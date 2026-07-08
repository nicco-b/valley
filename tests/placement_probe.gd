extends Node
## Placement-editing probe (dev-only, the Toolkit): places boulders the
## way LMB does, RMB-picks one (the cyan selection ring + the HUD SEL
## line), then moves/rotates/scales it and screenshots before and after
## — the eye check for placement v2. Cleans its records up and quits.
## Movie Maker + minimized:
##   godot --path . --write-movie /tmp/x.avi --fixed-fps 15 \
##     res://tests/placement_probe.tscn

const SPOT := Vector2(60, -300)  # valley floor near the pond

var _w: Node
var _t := 0
var _cells: Array[Vector2i] = []  # cells the probe placed into
var _had_file: Dictionary = {}  # cell file path -> existed before us


func _ready() -> void:
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _process(_d: float) -> void:
	_t += 1
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		if OS.has_feature("movie"):
			# Movie Maker renders every frame regardless; hide the window.
			# (A plain windowed run must stay visible — unfocused/minimized
			# windows are throttled and the screenshots would stall.)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	if _t == 20:
		GameClock.hours = 12.0
		GameClock.time_scale = 0.0
		Weather.force_kind("calm")
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			pl.global_position = Vector3(SPOT.x,
				Terrain.height(SPOT.x, SPOT.y) + 2.0, SPOT.y)
	if _t == 120:
		Toolkit._enter()
		Toolkit.set_tool("place")
		Toolkit.set_place_slot("rocks/coastal_boulder")
	if _t == 260:
		# Three placements (the LMB path), then pick the middle one.
		# The spread can cross a cell seam — remember every touched cell
		# (and whether its file predates us) for the cleanup.
		for dx: float in [-6.0, 0.0, 6.0]:
			var px := SPOT.x + dx
			var cell: Vector2i = CellRecords.cell_of(Vector3(px, 0.0, SPOT.y))
			if not _cells.has(cell):
				_cells.append(cell)
				var f := "%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y]
				_had_file[f] = FileAccess.file_exists(f)
			Toolkit._place_at(Vector3(px, Terrain.height(px, SPOT.y), SPOT.y))
		Toolkit._pick_at(Vector3(SPOT.x, 0.0, SPOT.y))
		print("[placement_probe] placed 3, selected id=%s" % Toolkit._sel_id)
	if _t == 320:
		var cam := Camera3D.new()
		add_child(cam)
		cam.far = 4000.0
		cam.make_current()
		cam.global_position = Vector3(SPOT.x - 10.0,
			Terrain.height(SPOT.x, SPOT.y) + 7.0, SPOT.y + 12.0)
		cam.look_at(Vector3(SPOT.x, Terrain.height(SPOT.x, SPOT.y) + 1.0, SPOT.y))
	if _t == 360:
		get_viewport().get_texture().get_image().save_png("/tmp/placement_sel.png")
		print("SHOT WRITTEN /tmp/placement_sel.png")
	if _t == 380:
		# Edit the selection: move 4m toward the camera, turn, grow.
		Toolkit._sel_move_to(Vector3(SPOT.x - 2.0,
			Terrain.height(SPOT.x - 2.0, SPOT.y + 4.0), SPOT.y + 4.0))
		for i in 3:
			Toolkit._sel_rotate(1.0)
		for i in 5:
			Toolkit._sel_scale(1)
		var rec: Dictionary = Toolkit._selected()
		print("[placement_probe] edited: yaw=%.2f scale=%.2f ground_dy=%.2f" % [
			float(rec.yaw), float(rec.scale), float(rec.ground_dy)])
	if _t == 440:
		get_viewport().get_texture().get_image().save_png("/tmp/placement_edit.png")
		print("SHOT WRITTEN /tmp/placement_edit.png")
	if _t == 460:
		# Leave no trace: pop the probe's records from every cell it
		# touched; a cell file only goes if the probe created it.
		Toolkit._deselect()
		Toolkit._place_undo = {}
		CellRecords.flush()
		for cell: Vector2i in _cells:
			while CellRecords.remove_last(cell):
				pass
		for f: String in _had_file:
			if not bool(_had_file[f]) and FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		print("[placement_probe] records cleaned (cells %s)" % str(_cells))
		get_tree().quit()
