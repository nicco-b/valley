extends Node
## Stream-deadlock probe (regression for the 2026-07-08 map-zoom freeze).
##
## The freeze: a zoom-in burst spawns a ring of LOW-priority terrain tasks;
## the pool's low-priority lane (threads * low_priority_thread_ratio) fills
## with workers that — pre-fix — parked inside mesh.create_trimesh_shape():
## Mesh.generate_triangle_mesh() re-fetches vertex arrays through
## RenderingServer.mesh_surface_get_arrays, a cross-thread push_and_ret that
## waits for the MAIN thread to flush the RS command queue. If the main
## thread then hard-waits on a QUEUED low-priority task before it reaches
## the frame's RS sync (in the frozen build: freeing a streamed-out
## material -> PipelineHashMapRD::_wait_for_all_pipelines waiting on a
## pipeline-compile task starved behind the saturated lane), nobody can
## make progress: engine deadlock.
##
## This probe drives the REAL streamer through that exact shape headless:
## teleport the focus to fresh cells, spawn the burst, then have the main
## thread wait mid-frame on a freshly queued low-priority no-op (standing
## in for the pipeline-compile wait, which the Dummy renderer can't reach).
## Pre-fix: the no-op never gets a lane slot (all held by RS-blocked
## builders) -> permanent hang (run under an outer watchdog; the hang IS
## the failure). Post-fix: builders never touch RS, the lane drains, the
## no-op runs, and this prints STREAM-DEADLOCK PASS.
##
##   godot --headless res://tests/stream_deadlock_probe.tscn
var _w: Node
var _t := 0
var _passed := false
var _streamer: Node


func _ready() -> void:
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _process(_d: float) -> void:
	_t += 1
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
	if _passed:
		# Quit hygiene: in-flight builders own streamer state; let the
		# burst finish through the normal drain before tearing the tree
		# down (quitting mid-flight is a separate, pre-existing noise).
		if _streamer._terrain_pending.is_empty():
			get_tree().quit()
		return
	if _t != 30:
		return
	_streamer = get_tree().get_first_node_in_group("world_streamer")
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if _streamer == null or player == null:
		print("STREAM-DEADLOCK FAIL: no streamer/player")
		get_tree().quit(1)
		return
	# The map-zoom shape: focus lands on untouched cells, ring widened as
	# MapScreen does when it starts driving the streamer (it uses 4; a 3x3
	# ring of fresh builds already exceeds the low-priority lane on any
	# core count, and keeps the probe's tail short).
	_streamer.load_radius = 1
	player.global_position = Vector3(4321.0, 4.0, -4321.0)
	_streamer._update_cells(false)
	var pending: int = _streamer._terrain_pending.size()
	# Let the lane's slot-holders run into their build (and, pre-fix, park
	# inside the create_trimesh_shape RS round-trip). A BUSY wait: the main
	# thread must not reach end-of-frame, where the RS queue would flush —
	# the frozen build blocked mid-frame too (SceneTree delete-queue flush).
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		pass
	# Stand-in for the pipeline-compile wait: a queued low-priority task
	# the main thread hard-waits on, mid-frame.
	var tid := WorkerThreadPool.add_task(func() -> void: pass)
	WorkerThreadPool.wait_for_task_completion(tid)
	print("STREAM-DEADLOCK PASS (burst=%d)" % pending)
	_passed = true
