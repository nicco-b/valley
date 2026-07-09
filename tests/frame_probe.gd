extends Node
## Frame-time probe (dev-only, the Toolkit): boots the valley, settles
## streaming, then WRAPS every scripted per-frame handler in the tree —
## set_process(false) on each, the probe re-dispatches them itself with a
## stopwatch around every call (same order: autoloads first, then tree
## order) — so one run prints where the frame's script milliseconds go.
## While measuring, the player is walked in a wide circle at WALK_SPEED
## so the streamer/scatter/water paths run at their steady-state load.
##   godot --headless res://tests/frame_probe.tscn
##   PROBE_STORM=1 forces a storm first; PROBE_FRAMES=N sets the window.

const SETTLE := 400
const DEFAULT_FRAMES := 600
const WALK_SPEED := 4.0

var _w: Node
var _t := 0
var _frames := DEFAULT_FRAMES
var _measuring := false
var _proc_nodes: Array[Node] = []
var _phys_nodes: Array[Node] = []
var _cost_usec := {}  # script path -> accumulated usec
var _calls := {}
var _frame_usec := PackedFloat64Array()
var _frame_t0 := 0
var _walk_ang := 0.0
var _player: CharacterBody3D
var _mon_process := 0.0
var _mon_physics := 0.0
var _mon_nav := 0.0
# PROBE_SWEEP=1: within one run, cumulatively disable internal processing
# per class, 150 frames a segment — the segment deltas attribute the
# engine-side (non-script) process time to classes, immune to the
# run-to-run machine-load noise.
const SWEEP_SEGMENT := 150
var _sweep_classes: Array[String] = ["baseline", "GPUParticles3D",
	"AudioStreamPlayer", "MultiMeshInstance3D", "MeshInstance3D",
	"Area3D", "StaticBody3D", "Node3D", "FogVolume", "Decal"]
var _sweep := false
var _sweep_seg := 0
var _sweep_frames := 0
var _sweep_proc := 0.0
var _sweep_phys := 0.0


func _sweep_disable(cls: String) -> int:
	var count := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		match cls:
			"player-physoff":
				if n.is_in_group("player"):
					n.set_physics_process(false)
					count += 1
			"areas-monitoring-off":
				if n is Area3D:
					(n as Area3D).monitoring = false
					(n as Area3D).monitorable = false
					count += 1
			"scripts-physoff":
				if n.get_script() != null and n.is_physics_processing():
					n.set_physics_process(false)
					count += 1
			_:
				if n.get_class() == cls:
					n.set_process_internal(false)
					n.set_physics_process_internal(false)
					count += 1
		for c in n.get_children():
			stack.push_back(c)
	return count


func _sweep_tick() -> void:
	_sweep_frames += 1
	_sweep_proc += Performance.get_monitor(Performance.TIME_PROCESS)
	_sweep_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	if _sweep_frames < SWEEP_SEGMENT:
		return
	print("[frame_probe] sweep seg=%-18s process=%.3fms physics=%.3fms"
			% [_sweep_classes[_sweep_seg], _sweep_proc / _sweep_frames * 1000.0,
			_sweep_phys / _sweep_frames * 1000.0])
	_sweep_frames = 0
	_sweep_proc = 0.0
	_sweep_phys = 0.0
	_sweep_seg += 1
	if _sweep_seg >= _sweep_classes.size():
		get_tree().quit()
		return
	var n := _sweep_disable(_sweep_classes[_sweep_seg])
	print("[frame_probe] sweep: disabled internal on %d %s" % [n, _sweep_classes[_sweep_seg]])


func _ready() -> void:
	process_priority = -1000  # frame stopwatch starts before wrapped calls
	process_physics_priority = -1000
	_frames = int(OS.get_environment("PROBE_FRAMES")) if OS.get_environment("PROBE_FRAMES") != "" else DEFAULT_FRAMES
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _key(n: Node) -> String:
	var s := n.get_script() as Script
	return s.resource_path.get_file() if s else str(n)


func _script_has(n: Node, m: String) -> bool:
	var s := n.get_script() as Script
	while s:
		if m in s.get_script_method_list().map(func(d: Dictionary) -> String: return String(d.name)):
			return true
		s = s.get_base_script()
	return false


## Class census of the live tree + optional engine-side ablations via
## PROBE_ABLATE=anim,particles,wildlife,timers (comma list).
func _census_and_ablate() -> void:
	var ablate := OS.get_environment("PROBE_ABLATE").split(",")
	var by_class := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		by_class[n.get_class()] = int(by_class.get(n.get_class(), 0)) + 1
		if "anim" in ablate:
			if n is AnimationTree:
				(n as AnimationTree).active = false
			elif n is AnimationPlayer:
				(n as AnimationPlayer).callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if "particles" in ablate and (n is GPUParticles3D or n is CPUParticles3D):
			n.set("emitting", false)
			n.set_process_internal(false)
		if "wildlife" in ablate and n.get_script() != null \
				and String((n.get_script() as Script).resource_path).contains("wildlife"):
			n.set_process(false)
			n.set_physics_process(false)
		if "timers" in ablate and n is Timer:
			(n as Timer).paused = true
		if "areas" in ablate and n is Area3D:
			(n as Area3D).monitoring = false
			(n as Area3D).monitorable = false
		if "meshes" in ablate and n is MeshInstance3D:
			(n as MeshInstance3D).visible = false
		if "internal" in ablate and n.get_script() == null:
			n.set_process_internal(false)
			n.set_physics_process_internal(false)
		for c in n.get_children():
			stack.push_back(c)
	var ck := by_class.keys()
	ck.sort_custom(func(a: String, b: String) -> bool:
		return int(by_class[a]) > int(by_class[b]))
	var top := ""
	for i in mini(18, ck.size()):
		top += "%s=%d " % [ck[i], int(by_class[ck[i]])]
	print("[frame_probe] census: ", top)
	if ablate.size() > 0 and ablate[0] != "":
		print("[frame_probe] ABLATED: ", ablate)


func _wrap_tree() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != self and n.get_script() != null:
			if n.is_processing() and _script_has(n, "_process"):
				n.set_process(false)
				_proc_nodes.append(n)
			if n.is_physics_processing() and _script_has(n, "_physics_process"):
				n.set_physics_process(false)
				_phys_nodes.append(n)
		for c in n.get_children():
			stack.push_back(c)


func _dispatch(nodes: Array[Node], method: String, delta: float) -> void:
	for n in nodes:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var t0 := Time.get_ticks_usec()
		n.call(method, delta)
		var us := Time.get_ticks_usec() - t0
		var k := _key(n)
		_cost_usec[k] = int(_cost_usec.get(k, 0)) + us
		_calls[k] = int(_calls.get(k, 0)) + 1


func _process(delta: float) -> void:
	_t += 1
	if _t == 2 and OS.get_environment("PROBE_STORM") == "1":
		Weather.force_kind("storm")
	if _t == SETTLE:
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		_census_and_ablate()
		if OS.get_environment("PROBE_SWEEP") != "":
			if OS.get_environment("PROBE_SWEEP") != "1":
				var l: Array[String] = ["baseline"]
				for c in OS.get_environment("PROBE_SWEEP").split(","):
					l.append(c)
				_sweep_classes = l
			_sweep = true
			return
		_wrap_tree()
		_measuring = true
		print("[frame_probe] wrapped %d process / %d physics handlers; measuring %d frames"
				% [_proc_nodes.size(), _phys_nodes.size(), _frames])
		_frame_t0 = Time.get_ticks_usec()
		return
	if _sweep:
		_sweep_tick()
		return
	if not _measuring:
		return
	# frame stopwatch: priority -1000 runs first each idle frame
	var now := Time.get_ticks_usec()
	_frame_usec.append(float(now - _frame_t0))
	_frame_t0 = now
	_mon_process += Performance.get_monitor(Performance.TIME_PROCESS)
	_mon_physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_mon_nav += Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)
	if _player and OS.get_environment("PROBE_WALK") != "0":
		_walk_ang += delta * WALK_SPEED / 60.0  # 60 m circle radius
		var dir := Vector2(cos(_walk_ang), sin(_walk_ang))
		_player.velocity = Vector3(dir.x, 0.0, dir.y) * WALK_SPEED
		_player.global_position += Vector3(dir.x, 0.0, dir.y) * WALK_SPEED * delta
	_dispatch(_proc_nodes, "_process", delta)
	if _frame_usec.size() >= _frames:
		_report()
		get_tree().quit()


func _physics_process(delta: float) -> void:
	if _measuring:
		_dispatch(_phys_nodes, "_physics_process", delta)


func _report() -> void:
	var frames := _frame_usec.size()
	var sorted := _frame_usec.duplicate()
	sorted.sort()
	var total := 0.0
	for v in _frame_usec:
		total += v
	print("[frame_probe] frames=%d mean=%.3fms median=%.3fms p95=%.3fms p99=%.3fms"
			% [frames, total / frames / 1000.0,
			sorted[frames / 2] / 1000.0,
			sorted[int(frames * 0.95)] / 1000.0,
			sorted[int(frames * 0.99)] / 1000.0])
	print("[frame_probe] monitors(avg): process=%.3fms physics=%.3fms nav=%.3fms objects=%d nodes=%d orphans=%d islands=%d active_obj=%d pairs=%d"
			% [_mon_process / frames * 1000.0,
			_mon_physics / frames * 1000.0,
			_mon_nav / frames * 1000.0,
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	var keys := _cost_usec.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(_cost_usec[a]) > int(_cost_usec[b]))
	var accounted := 0
	print("[frame_probe] per-script (ms/frame over %d frames):" % frames)
	for k in keys:
		var us: int = _cost_usec[k]
		accounted += us
		if us / float(frames) < 1.0:  # below 1 usec/frame: noise
			continue
		print("  %-28s %8.4f ms/f  (%d calls)" % [k, us / float(frames) / 1000.0, int(_calls[k])])
	print("[frame_probe] scripts account for %.3f ms/f of %.3f ms/f frame mean"
			% [accounted / float(frames) / 1000.0, total / frames / 1000.0])
