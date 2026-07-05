extends SceneTree
## Dev scratch: minimal repro hunt for the worker-thread SIGSEGV.
## Mode via env THREAD_PROBE: "height" hammers Terrain.height from 8
## threads; "noise" hammers one shared FastNoiseLite; "noise_own" gives
## each thread its own FastNoiseLite. Prints CLEAN or dies.
func _init() -> void:
	var mode := OS.get_environment("THREAD_PROBE")
	var t: Node = null
	var shared := FastNoiseLite.new()
	shared.fractal_octaves = 4
	if mode == "height" or mode == "":
		t = load("res://game/world/terrain.gd").new()
		t._ready()
	if mode == "poolmain":
		# Pool GDScript AND main-thread GDScript running concurrently —
		# the in-game shape (streamer builds + main _process scripts).
		t = load("res://game/world/terrain.gd").new()
		t._ready()
		var tasks: Array[int] = []
		for i in 12:
			tasks.append(WorkerThreadPool.add_task(func() -> void:
				var acc := 0.0
				for k in 400000:
					acc += t.height(1200.0 + (k % 700), -3000.0 + (k % 900))
				print("task done ", acc)))
		var macc := 0.0
		var waiting := true
		while waiting:
			for k in 5000:  # main-thread GDScript churning concurrently
				macc += t.height(400.0 + (k % 300), -2000.0 + (k % 400))
			waiting = false
			for id in tasks:
				if not WorkerThreadPool.is_task_completed(id):
					waiting = true
					break
		for id in tasks:
			WorkerThreadPool.wait_for_task_completion(id)
		print("PROBE CLEAN mode=poolmain ", macc)
		quit()
		return
	if mode == "mesh":
		t = load("res://game/world/terrain.gd").new()
		t._ready()
		for round_i in 6:
			var tasks: Array[int] = []
			for i in 16:
				var ci := i
				tasks.append(WorkerThreadPool.add_task(func() -> void:
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					st.set_smooth_group(0)
					var res := 49
					for iz in res:
						for ix in res:
							var wx := ci * 128.0 + ix * 2.7 + 800.0
							var wz := -2600.0 - iz * 2.7
							st.add_vertex(Vector3(wx, t.height(wx, wz), wz))
					for iz in res - 1:
						for ix in res - 1:
							var a := iz * res + ix
							for idx in [a, a + 1, a + res, a + 1, a + res + 1, a + res]:
								st.add_index(idx)
					st.generate_normals()
					var mesh := st.commit()
					var shape := mesh.create_trimesh_shape()
					if shape == null:
						print("null shape")))
			for id in tasks:
				WorkerThreadPool.wait_for_task_completion(id)
			print("mesh round ", round_i, " done")
		print("PROBE CLEAN mode=mesh")
		quit()
		return
	if mode == "pool":
		t = load("res://game/world/terrain.gd").new()
		t._ready()
		var tasks: Array[int] = []
		for i in 16:
			tasks.append(WorkerThreadPool.add_task(func() -> void:
				var acc := 0.0
				for k in 500000:
					acc += t.height(1200.0 + (k % 700), -3000.0 + (k % 900))
				print("pool task done ", acc)))
		for id in tasks:
			WorkerThreadPool.wait_for_task_completion(id)
		print("PROBE CLEAN mode=pool")
		quit()
		return
	var threads: Array[Thread] = []
	for i in 8:
		var th := Thread.new()
		match mode:
			"noise":
				th.start(func() -> void:
					var acc := 0.0
					for k in 2000000:
						acc += shared.get_noise_2d(k * 0.37, k * 0.11)
					print("noise thread done ", acc))
			"noise_own":
				th.start(func() -> void:
					var own := FastNoiseLite.new()
					own.fractal_octaves = 4
					var acc := 0.0
					for k in 2000000:
						acc += own.get_noise_2d(k * 0.37, k * 0.11)
					print("own thread done ", acc))
			_:
				th.start(func() -> void:
					var acc := 0.0
					for k in 500000:
						acc += t.height(1200.0 + (k % 700), -3000.0 + (k % 900))
					print("height thread done ", acc))
		threads.append(th)
	for th in threads:
		th.wait_to_finish()
	print("PROBE CLEAN mode=", mode)
	quit()
