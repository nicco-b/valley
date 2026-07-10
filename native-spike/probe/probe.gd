extends SceneTree
# The embed spike probe (Mission Z2 / PLAN_ENGINE §3 E2).
#
# Boots headless, loads the ContourKernel GDExtension (Swift Lattice VM linked
# into this godot process), compiles the REAL vendored port (toolkit_snap.ct),
# and:
#   1. PARITY — for every corpus line, compares the Swift VM's cycle_grid_step
#      to Godot's OWN ToolkitSnap.cycle_grid_step, bit-for-bit (IEEE-754 hex).
#   2. OVERHEAD — measures per-call cost four ways over 10k calls each and lays
#      them against a sim-tick budget.
#
# Run: godot --headless --path <this dir> -s res://probe.gd

const N := 10000

func _hexle(x: float) -> String:
	var b := PackedFloat64Array([x]).to_byte_array()
	var s := ""
	for by in b: s += "%02x" % by
	return s

func _fhex_to_float(hex: String) -> float:
	var bytes := PackedByteArray()
	var k := 0
	while k < hex.length():
		bytes.append(("0x" + hex.substr(k, 2)).hex_to_int())
		k += 2
	return bytes.decode_double(0)

# Full recursive tagged-arg decoder — a copy of Plumb's certified gd_driver.gd
# so the GDScript-side argv is byte-identical to what the corpus pins (vectors
# narrow to real_t/float32; list/dict recurse — the socket-list shape).
func _decode(arg: Dictionary) -> Variant:
	if arg.has("int"): return int(arg["int"])
	if arg.has("float"): return float(arg["float"])
	if arg.has("fhex"): return _fhex_to_float(str(arg["fhex"]))
	if arg.has("bool"): return bool(arg["bool"])
	if arg.has("str"): return str(arg["str"])
	if arg.has("strarray"):
		var p := PackedStringArray()
		for e in arg["strarray"]: p.append(str(e))
		return p
	if arg.has("intarray"):
		var ai: Array = []
		for e in arg["intarray"]: ai.append(int(e))
		return ai
	if arg.has("floatarray"):
		var af: Array = []
		for e in arg["floatarray"]: af.append(float(e))
		return af
	if arg.has("f32array"):
		var pf := PackedFloat32Array()
		for e in arg["f32array"]: pf.append(float(e))
		return pf
	if arg.has("vec2"):
		var c2: Array = arg["vec2"]
		return Vector2(float(c2[0]), float(c2[1]))
	if arg.has("vec3"):
		var c3: Array = arg["vec3"]
		return Vector3(float(c3[0]), float(c3[1]), float(c3[2]))
	if arg.has("list"):
		var al: Array = []
		for e in arg["list"]: al.append(_decode(e))
		return al
	if arg.has("dict"):
		var d: Dictionary = {}
		for k in arg["dict"]: d[k] = _decode(arg["dict"][k])
		return d
	return null

# Canonical serialization for parity: floats and vector components as IEEE-754
# hex, so the comparison is bit-level (matches Value.canonical / gd_driver).
# Now covers the COMPOSITE result kinds (dict/basis/array) the embed ABI carries.
func _canon(v: Variant) -> String:
	match typeof(v):
		TYPE_BOOL: return "b:%s" % ("true" if v else "false")
		TYPE_INT: return "i:%d" % v
		TYPE_FLOAT: return "f:" + _hexle(v)
		TYPE_STRING, TYPE_STRING_NAME: return "s:%s" % str(v)
		TYPE_VECTOR2: return "v2:%s:%s" % [_hexle(v.x), _hexle(v.y)]
		TYPE_VECTOR3: return "v3:%s:%s:%s" % [_hexle(v.x), _hexle(v.y), _hexle(v.z)]
		TYPE_BASIS:
			# The three COLUMNS (v.x/v.y/v.z), matching Value.basis's order.
			var s := "m3:"
			for col in [v.x, v.y, v.z]:
				s += "%s:%s:%s:" % [_hexle(col.x), _hexle(col.y), _hexle(col.z)]
			return s.substr(0, s.length() - 1)
		TYPE_DICTIONARY:
			var dp := PackedStringArray()
			for k in v: dp.append("%s=%s" % [_canon(k), _canon(v[k])])
			return "{" + ",".join(dp) + "}"
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_ARRAY:
			var ap := PackedStringArray()
			for e in v: ap.append(_canon(e))
			return "[" + ",".join(ap) + "]"
		_: return "?:" + str(v)

# Compare the Swift VM vs Godot's own ToolkitSnap over one corpus. Returns
# [checked, mismatches].
func _parity(kernel: Object, TS: GDScript, fn: String, corpus: String) -> Array:
	var text := FileAccess.get_file_as_string(corpus)
	var checked := 0
	var mism := 0
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"): continue
		var parsed = JSON.parse_string(line)
		if typeof(parsed) != TYPE_ARRAY: continue
		var argv: Array = []
		for a in parsed: argv.append(_decode(a))
		var gd_ans: Variant = TS.callv(fn, argv)
		var em_ans: Variant = kernel.contour_call(fn, argv)
		if _canon(em_ans) != _canon(gd_ans):
			mism += 1
			if mism <= 4:
				printerr("  %s MISMATCH args=%s gd=%s embed=%s" % [fn, str(argv), _canon(gd_ans), _canon(em_ans)])
		checked += 1
	return [checked, mism]

func _fail(msg: String) -> void:
	printerr("PROBE FAIL: ", msg)
	quit(1)

func _init() -> void:
	# --- 1. load the extension (the whole point: Swift VM in-process) ----------
	if not ClassDB.class_exists("ContourKernel"):
		var status := GDExtensionManager.load_extension("res://contourspike.gdext")
		if status != GDExtensionManager.LOAD_STATUS_OK:
			_fail("GDExtensionManager.load_extension status=%d" % status); return
	if not ClassDB.class_exists("ContourKernel"):
		_fail("ContourKernel class not registered after load"); return
	print("[probe] extension loaded; ContourKernel registered")

	var kernel: Object = ClassDB.instantiate("ContourKernel")

	# --- 2. compile the REAL port --------------------------------------------
	var src := FileAccess.get_file_as_string("res://toolkit_snap.ct")
	if src == "": _fail("could not read toolkit_snap.ct"); return
	var err: String = kernel.load_module(src)
	if err != "": _fail("load_module: " + err); return
	print("[probe] module compiled (toolkit_snap.ct)")

	# Godot's OWN implementation, loaded live in this process.
	var TS: GDScript = load("res://toolkit_snap.gd")
	if TS == null: _fail("could not load toolkit_snap.gd"); return

	# --- 3. PARITY: real ports, full corpora, bit-for-bit --------------------
	# The scalar rung proved cycle_grid_step/snap_to_grid/ground_normal. This
	# rung adds the THREE the scalar ABI could not carry — composite RESULTS
	# (aligned_basis -> basis; socket_world -> dict) and composite ARGS+result
	# (best_socket_snap: arrays of dicts in, dict out) — plus the scalar three so
	# nothing regressed.
	var manifest := [
		["cycle_grid_step", "res://cycle_grid_step.jsonl"],  # scalar in/out
		["snap_to_grid",    "res://snap_to_grid.jsonl"],     # vec3+float -> vec3
		["ground_normal",   "res://ground_normal.jsonl"],    # 4 floats -> vec3
		["aligned_basis",   "res://aligned_basis.jsonl"],    # vec3+float -> BASIS  (was LAT_ERR)
		["socket_world",    "res://socket_world.jsonl"],     # -> DICT {pos:vec3,yaw:float}  (was LAT_ERR)
		["best_socket_snap","res://best_socket_snap.jsonl"], # array<dict> args -> DICT  (was LAT_ERR)
	]
	var total := 0
	for row in manifest:
		var r := _parity(kernel, TS, row[0], row[1])
		if r[0] == 0: _fail("no corpus cases for " + row[0]); return
		if r[1] != 0: _fail("PARITY %s: %d/%d MISMATCH" % [row[0], r[1], r[0]]); return
		print("[probe] PARITY %-16s %3d/%d BIT-IDENTICAL to ToolkitSnap.gd" % [row[0], r[0], r[0]])
		total += r[0]
	print("[probe] PARITY total: %d cases bit-identical (composite results + args included)" % total)

	# --- 4. OVERHEAD (per-call µs, amortized over N calls) -------------------
	# Scalar baseline first (cycle_grid_step small; ground_normal heavier vec3),
	# then the COMPOSITE-carrying calls this rung unlocked, so the verdict can
	# read composite marshalling cost against the scalar 0.85-3.5µs baseline.
	print("[probe] OVERHEAD per call (µs), N=%d:" % N)
	print("[probe]   -- scalar baseline --")
	_bench_row(kernel, TS, "cycle_grid_step", [3.0, 1])
	_bench_row(kernel, TS, "ground_normal", [0.0, 1.0, 2.0, 0.5])
	print("[probe]   -- composite-carrying (LAT_BUF) --")
	# aligned_basis: vec3 arg in (scalar field), BASIS result out (result buffer).
	_bench_row(kernel, TS, "aligned_basis", [Vector3(0.2, 0.9, 0.3), 0.7])
	# socket_world: vec3+float scalar args, DICT result out (result buffer).
	_bench_row(kernel, TS, "socket_world", [Vector3(1, 0, 2), 0.5, 2.0, Vector3(1, 0, 0), 0.25])
	# best_socket_snap: composite ARGS in (two arrays of dicts -> arg buffers) AND
	# a DICT result out — the fully composite-on-both-sides case.
	var isock := [{"type": "a", "pos": Vector3(0, 0, 0), "yaw": 0.0}]
	var cands := [{"type": "a", "pos": Vector3(1, 0, 0), "yaw": 0.0}]
	_bench_row(kernel, TS, "best_socket_snap", [Vector3(0, 0, 0), isock, cands, 5.0, 1.0])
	print("PROBE PASS")
	kernel = null   # drop the RefCounted before teardown (tidy StringName pool)
	quit(0)

func _bench_row(kernel: Object, TS: GDScript, fn: String, args: Array) -> void:
	var b_pure: Dictionary = kernel.bench(fn, args, N)          # VM+ABI, pre-marshalled
	var b_marsh: Dictionary = kernel.bench_marshal(fn, args, N) # + Variant re-marshal
	var t0 := Time.get_ticks_usec()
	for i in N: kernel.contour_call(fn, args)
	var us_c := float(Time.get_ticks_usec() - t0) / float(N)   # from GDScript
	t0 = Time.get_ticks_usec()
	for i in N: TS.callv(fn, args)
	var us_d := float(Time.get_ticks_usec() - t0) / float(N)   # GDScript-native
	print("  %-16s (a)VM+ABI %.3f  (b)+marshal %.3f  (c)from-GDScript %.3f  (d)GDScript-native %.3f  [ratio c/d %.1fx]"
		% [fn, float(b_pure["per_call_us"]), float(b_marsh["per_call_us"]), us_c, us_d, us_c / maxf(us_d, 0.0001)])
