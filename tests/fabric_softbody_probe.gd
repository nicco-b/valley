extends Node3D
## Fabric planning probe (dev-only, plan/fabric-physics — the Elements).
## Prices Godot's built-in SoftBody3D at clothing-ish resolutions under
## the project's physics engine. Prints three verdict lines:
##   ENGINE  — which physics server actually ran
##   SIM     — did the cloth move at all (Jolt does not implement soft
##             bodies; this line is the dead-on-arrival check)
##   COST    — avg physics ms/frame after warmup, at FABRIC_N bodies
##   FP      — bounds fingerprint (%.9f) for two-run determinism A/B
## Run: FABRIC_N=8 FABRIC_RES=16 godot --headless res://tests/fabric_softbody_probe.tscn
## (self-quits; --quit-after 600 as backstop)

var _bodies: Array[SoftBody3D] = []
var _t := 0
var _n := 4
var _res := 16
var _accum := 0.0
var _samples := 0
var _y_start := 0.0


func _ready() -> void:
	if OS.get_environment("FABRIC_N") != "":
		_n = int(OS.get_environment("FABRIC_N"))
	if OS.get_environment("FABRIC_RES") != "":
		_res = int(OS.get_environment("FABRIC_RES"))
	for i in _n:
		var sb := SoftBody3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.6)  # cloak-ish panel
		pm.subdivide_width = _res - 2
		pm.subdivide_depth = _res - 2
		sb.mesh = pm
		sb.simulation_precision = 5
		sb.total_mass = 1.0
		add_child(sb)
		sb.position = Vector3(float(i) * 2.0, 2.0, 0.0)
		# Pin the first vertex row (the "shoulder seam") so it drapes.
		for c in _res:
			sb.set_point_pinned(c, true)
		_bodies.append(sb)


func _physics_process(_d: float) -> void:
	_t += 1
	if _t == 5:
		_y_start = _mean_center_y()
	if _t > 60 and _t <= 360:  # 300 measured frames after warmup
		_accum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_samples += 1
	if _t == 361:
		var y_end := _mean_center_y()
		var verts := (_res) * (_res)
		print("ENGINE %s" % ProjectSettings.get_setting("physics/3d/physics_engine"))
		print("SIM moved=%s (center y %.3f -> %.3f)  n=%d res=%dx%d (~%d verts/body)"
			% ["YES" if absf(y_end - _y_start) > 0.05 else "NO",
			_y_start, y_end, _n, _res, _res, verts])
		print("COST physics %.3f ms/frame avg over %d frames (%d bodies)"
			% [_accum / float(_samples) * 1000.0, _samples, _n])
		print("FP %s" % _fingerprint())
		get_tree().quit()


func _mean_center_y() -> float:
	var acc := 0.0
	for sb in _bodies:
		acc += PhysicsServer3D.soft_body_get_bounds(sb.get_physics_rid()).get_center().y
	return acc / maxf(float(_bodies.size()), 1.0)


func _fingerprint() -> String:
	if _bodies.is_empty():
		return "(no bodies — baseline run)"
	var b := PhysicsServer3D.soft_body_get_bounds(_bodies[0].get_physics_rid())
	return "%.9f %.9f %.9f | %.9f %.9f %.9f" % [b.position.x, b.position.y,
		b.position.z, b.size.x, b.size.y, b.size.z]
