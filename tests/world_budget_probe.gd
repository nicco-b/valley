extends Node
## World-budget stress probe (dev-only, the Toolkit's bench): synthetically
## loads the live valley along three axes and charts where the frame BENDS —
## the measured cliffs behind data/world/budget.json's default thresholds.
## Built on frame_probe's discipline (boot valley.tscn, settle streaming, then
## measure with a stopwatch + the Performance monitors), but instead of
## attributing a fixed frame it SWEEPS synthetic load and prints one row per
## step so the knee (where a metric roughly doubles) is read straight off the
## table. Not shipped behaviour — a test/ tool like frame_probe.
##
##   godot --headless res://tests/world_budget_probe.tscn
##   BUDGET_PHASE=place|agents|records runs one axis (default: all three)
##   BUDGET_SETTLE=N / BUDGET_MEASURE=N override the windows
##
## Headless caveat: the dummy renderer draws nothing, so the PLACE rows are the
## CPU-side cost — scene-tree _process + the physics broadphase/collision the
## meter actually guards ("physics cost near it"). A GPU draw-call cliff needs
## an in-app pass; the default thresholds carry that as extra safety margin.
##
## What each axis fills:
##   place   — one focus cell filled with N kit instances through CellRecords
##             (the real placement path: records + streamer rebuild), the
##             player parked in the cell so the broadphase pairs are live.
##   agents  — H synthetic herds spawned through WildlifeManager.spawn_herd
##             (content-empty-safe records, homed far away so no body embodies:
##             pure AgentSim mind cost), steady frame + the advance_hours(12)
##             catch-up each step.
##   records — bulk parse+validate of 1k/10k/50k synthetic cell rows, the boot
##             cost CellRecords._ready pays over data/cells.

const DEFAULT_SETTLE := 240
const DEFAULT_MEASURE := 120
const BUILD_SETTLE := 40   # frames after a cell rebuild before we trust physics
const COUNT_PER_HERD := 8

const PLACE_STEPS := [0, 50, 200, 800, 3200]
const HERD_STEPS := [0, 5, 20, 80, 320]
const RECORD_STEPS := [1000, 10000, 50000]

enum Phase { BOOT, PLACE, AGENTS, RECORDS, DONE }

var _w: Node
var _phase: int = Phase.BOOT
var _t := 0                 # global frame counter
var _settle := DEFAULT_SETTLE
var _measure := DEFAULT_MEASURE

# measurement window
var _win_open := false
var _win_left := 0
var _frame_t0 := 0
var _sum_frame_us := 0.0
var _sum_proc := 0.0
var _sum_phys := 0.0
var _peak_frame_us := 0.0

# place axis
var _place_i := 0
var _place_cell := Vector2i.ZERO
var _kit_ref := ""          # resolved kit path, "" -> synthetic fallback
var _synth_root: Node3D = null
var _place_wait := 0
var _build_ms := 0.0        # last cell (re)build hitch — the streaming spike

# agents axis
var _wildlife: Node = null
var _agent_i := 0
var _agents_added := 0

# records axis printed inline (synchronous), no per-frame window


func _ready() -> void:
	process_priority = -1000
	process_physics_priority = -1000
	if OS.get_environment("BUDGET_SETTLE") != "":
		_settle = int(OS.get_environment("BUDGET_SETTLE"))
	if OS.get_environment("BUDGET_MEASURE") != "":
		_measure = int(OS.get_environment("BUDGET_MEASURE"))
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _selected_phase(p: String) -> bool:
	var want := OS.get_environment("BUDGET_PHASE")
	return want == "" or want == p


# ---- measurement window plumbing -------------------------------------------

func _win_start(frames: int) -> void:
	_win_open = true
	_win_left = frames
	_sum_frame_us = 0.0
	_sum_proc = 0.0
	_sum_phys = 0.0
	_peak_frame_us = 0.0
	_frame_t0 = Time.get_ticks_usec()


func _win_tick() -> void:
	var now := Time.get_ticks_usec()
	var d := float(now - _frame_t0)
	_frame_t0 = now
	_sum_frame_us += d
	_peak_frame_us = maxf(_peak_frame_us, d)
	_sum_proc += Performance.get_monitor(Performance.TIME_PROCESS)
	_sum_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_win_left -= 1


func _win_mean_ms() -> float:
	return _sum_frame_us / maxf(1.0, float(_measure)) / 1000.0


func _win_proc_ms() -> float:
	return _sum_proc / maxf(1.0, float(_measure)) / 1000.0 * 1000.0


func _win_phys_ms() -> float:
	return _sum_phys / maxf(1.0, float(_measure)) / 1000.0 * 1000.0


# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_t += 1
	match _phase:
		Phase.BOOT:
			if _t >= _settle:
				_begin()
		Phase.PLACE:
			_tick_place()
		Phase.AGENTS:
			_tick_agents()
		Phase.RECORDS:
			pass  # records axis runs synchronously in _begin_records
		Phase.DONE:
			get_tree().quit()


func _begin() -> void:
	# Unshackle the frame: FocusThrottle caps FPS while unfocused (headless is
	# always unfocused), which floors wall-frame time and hides load. With the
	# cap off, the frame stopwatch reads the real CPU cost again.
	Engine.max_fps = 0
	print("[budget_probe] settled; machine=headless renderer=%s max_fps=%d" % [
		DisplayServer.get_name(), Engine.max_fps])
	_wildlife = _find_wildlife()
	if _selected_phase("place"):
		_start_place()
	elif _selected_phase("agents"):
		_start_agents()
	elif _selected_phase("records"):
		_begin_records()
		_phase = Phase.DONE
	else:
		_phase = Phase.DONE


# ===== PLACE ================================================================

func _start_place() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var fp := player.global_position if player else Vector3.ZERO
	_place_cell = CellRecords.cell_of(fp)
	_kit_ref = _resolve_kit()
	# Park the player dead-centre in the cell so the broadphase pairs with the
	# instances we fill it with are live for the physics reading.
	var cx := float(_place_cell.x) * CellRecords.CELL_SIZE
	var cz := float(_place_cell.y) * CellRecords.CELL_SIZE
	if player and player is CharacterBody3D:
		player.global_position = Vector3(cx, Terrain.height(cx, cz) + 1.5, cz)
		(player as CharacterBody3D).velocity = Vector3.ZERO
	print("[budget_probe] PLACE axis  cell=%s  kit=%s" % [
		_place_cell, _kit_ref if _kit_ref != "" else "<synthetic box+staticbody>"])
	print("[budget_probe] PLACE  N | build_ms | frame_mean_ms | proc_ms phys_ms | pairs | nodes")
	_place_i = 0
	_phase = Phase.PLACE
	_place_apply(PLACE_STEPS[0])
	_place_wait = BUILD_SETTLE


func _tick_place() -> void:
	if _place_wait > 0:
		_place_wait -= 1
		if _place_wait == 0:
			_win_start(_measure)
		return
	if not _win_open:
		return
	_win_tick()
	if _win_left <= 0:
		_win_open = false
		_place_report(PLACE_STEPS[_place_i])
		_place_i += 1
		if _place_i >= PLACE_STEPS.size():
			_place_teardown()
			_after_place()
			return
		_place_apply(PLACE_STEPS[_place_i])
		_place_wait = BUILD_SETTLE


func _place_report(n: int) -> void:
	print("[budget_probe] PLACE  %5d | %8.3f | %13.3f | %7.3f %7.3f | %5d | %d" % [
		n, _build_ms, _win_mean_ms(),
		_win_proc_ms(), _win_phys_ms(),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])


## Fill the focus cell with exactly n instances (clearing any prior fill).
func _place_apply(n: int) -> void:
	if _kit_ref != "":
		_place_apply_records(n)
	else:
		_place_apply_synthetic(n)


func _place_apply_records(n: int) -> void:
	# Poke the Chronicle directly (the record shape CellRecords.add mints) and
	# fire `changed` so the streamer rebuilds the cell through its real
	# _add_records path — same instances a placed cell holds, minus N disk
	# writes we would only delete again.
	var cx := float(_place_cell.x) * CellRecords.CELL_SIZE
	var cz := float(_place_cell.y) * CellRecords.CELL_SIZE
	var arr: Array = []
	for i in n:
		var ang := float(i) * 2.399963  # golden-angle spread across the cell
		var r := CellRecords.CELL_SIZE * 0.45 * sqrt(float(i) / maxf(1.0, float(n)))
		var x := cx + cos(ang) * r
		var z := cz + sin(ang) * r
		arr.append({
			"id": "budgetprobe_%d" % i, "kit": _kit_ref,
			"x": x, "y": Terrain.height(x, z), "z": z,
			"yaw": ang, "scale": 1.0, "ground_dy": 0.0,
		})
	CellRecords._cells[_place_cell] = arr
	# The build hitch: _add_records instantiates synchronously off `changed`,
	# so the emit blocks for exactly the spike a dense cell causes when it
	# streams in. That main-thread hitch IS the felt placement cost (the
	# dummy renderer hides the steady GPU cost — see the header caveat).
	var t0 := Time.get_ticks_usec()
	CellRecords.changed.emit(_place_cell)
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _place_apply_synthetic(n: int) -> void:
	if _synth_root != null:
		_synth_root.queue_free()
		_synth_root = null
	CellRecords._cells[_place_cell] = []
	CellRecords.changed.emit(_place_cell)
	_build_ms = 0.0
	if n == 0:
		return
	var t0 := Time.get_ticks_usec()
	_synth_root = Node3D.new()
	_w.add_child(_synth_root)
	var cx := float(_place_cell.x) * CellRecords.CELL_SIZE
	var cz := float(_place_cell.y) * CellRecords.CELL_SIZE
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	for i in n:
		var ang := float(i) * 2.399963
		var r := CellRecords.CELL_SIZE * 0.45 * sqrt(float(i) / maxf(1.0, float(n)))
		var x := cx + cos(ang) * r
		var z := cz + sin(ang) * r
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = box
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(mi)
		body.add_child(col)
		body.position = Vector3(x, Terrain.height(x, z), z)
		_synth_root.add_child(body)
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _place_teardown() -> void:
	CellRecords._cells[_place_cell] = []
	CellRecords.changed.emit(_place_cell)
	if _synth_root != null:
		_synth_root.queue_free()
		_synth_root = null


func _after_place() -> void:
	if _selected_phase("agents"):
		_start_agents()
	elif _selected_phase("records"):
		_begin_records()
		_phase = Phase.DONE
	else:
		_phase = Phase.DONE


## First placeable kit whose scene actually loads (assets can be absent in a
## content-empty checkout); "" means fall back to a synthetic box+staticbody so
## the axis measures SOMETHING everywhere. Prefers a kit already in the world's
## records, then the Cards palette.
func _resolve_kit() -> String:
	if OS.get_environment("BUDGET_SYNTH") == "1":
		return ""  # force the collision-bearing box path
	for cell: Vector2i in CellRecords.all_cells():
		for rec: Dictionary in CellRecords.records(cell):
			var k := String(rec.get("kit", ""))
			if k != "" and Kit.scene_for(k) != null:
				return k
	if Engine.has_singleton("Cards") or true:
		for slot in Cards.placeable():
			var file: String = Cards.resolve(String(slot.get("slot", "")), 0)
			if file != "" and Kit.scene_for(file) != null:
				return file
	return ""


# ===== AGENTS ===============================================================

func _start_agents() -> void:
	if _wildlife == null:
		print("[budget_probe] AGENTS axis SKIP — no WildlifeManager in tree (content-empty)")
		_after_agents()
		return
	print("[budget_probe] AGENTS axis  herd_size=%d  (homed far — no bodies embody)" % COUNT_PER_HERD)
	print("[budget_probe] AGENTS  herds indiv | steady_frame_ms proc_ms | advance12h_ms")
	_agent_i = 0
	_agents_added = 0
	_phase = Phase.AGENTS
	_agents_apply(HERD_STEPS[0])
	_win_start(_measure)


func _tick_agents() -> void:
	if not _win_open:
		return
	_win_tick()
	if _win_left <= 0:
		_win_open = false
		# The catch-up cost: one 12h skip through GameClock's one door.
		var t0 := Time.get_ticks_usec()
		GameClock.advance_hours(12.0)
		var adv_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		_agents_report(HERD_STEPS[_agent_i], adv_ms)
		_agent_i += 1
		if _agent_i >= HERD_STEPS.size():
			_after_agents()
			return
		_agents_apply(HERD_STEPS[_agent_i])
		_win_start(_measure)


func _agents_report(herds: int, adv_ms: float) -> void:
	print("[budget_probe] AGENTS %5d %5d | %15.3f %7.3f | %13.3f" % [
		herds, herds * COUNT_PER_HERD, _win_mean_ms(), _win_proc_ms(), adv_ms])


## Grow the herd population to `target_herds` total added by the probe.
func _agents_apply(target_herds: int) -> void:
	while _agents_added < target_herds:
		var i := _agents_added
		var hx := 10000.0 + float(i) * 40.0  # far from focus: no embodiment
		var hz := 10000.0
		_wildlife.spawn_herd({
			"id": "budgetprobe_herd_%d" % i,
			"count": COUNT_PER_HERD,
			"home": {"x": hx, "z": hz},
			"range": 120.0,
			"body_scene": "res://tests/world_budget_probe.tscn",  # never loaded
			"activities": [
				{"id": "roam", "at": "roam", "satisfies": "wander", "rate": 5},
			],
		})
		_agents_added += 1


func _after_agents() -> void:
	if _selected_phase("records"):
		_begin_records()
	_phase = Phase.DONE


# ===== RECORDS ==============================================================

func _begin_records() -> void:
	print("[budget_probe] RECORDS axis  (boot parse+validate cost over N synthetic rows)")
	print("[budget_probe] RECORDS  rows | read_ms parse_ms validate_ms total_ms | bytes")
	var schema := {
		"kit": TYPE_STRING, "x": TYPE_FLOAT, "y": TYPE_FLOAT,
		"z": TYPE_FLOAT, "yaw": TYPE_FLOAT,
	}
	for n: int in RECORD_STEPS:
		var rows: Array = []
		for i in n:
			rows.append({
				"id": "p%x_%d" % [i, i], "kit": "res://x.glb",
				"x": float(i), "y": 1.0, "z": float(-i), "yaw": 0.5,
				"scale": 1.0, "ground_dy": 0.0, "day": 1,
			})
		var text := JSON.stringify(rows)
		var path := "user://budget_probe_rows.json"
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()

		var t0 := Time.get_ticks_usec()
		var got := FileAccess.get_file_as_string(path)
		var t1 := Time.get_ticks_usec()
		var parsed: Variant = JSON.parse_string(got)
		var t2 := Time.get_ticks_usec()
		var ok := 0
		if parsed is Array:
			for rec in parsed:
				if rec is Dictionary and Records.validate_message(rec, schema) == "":
					ok += 1
		var t3 := Time.get_ticks_usec()
		print("[budget_probe] RECORDS %6d | %7.2f %8.2f %11.2f %8.2f | %d  (%d ok)" % [
			n, float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0,
			float(t3 - t2) / 1000.0, float(t3 - t0) / 1000.0,
			text.length(), ok])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("[budget_probe] RECORDS axis done")


# ---------------------------------------------------------------------------

func _find_wildlife() -> Node:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var s := n.get_script() as Script
		if s != null and String(s.resource_path).ends_with("wildlife_manager.gd"):
			return n
		for c in n.get_children():
			stack.push_back(c)
	return null
