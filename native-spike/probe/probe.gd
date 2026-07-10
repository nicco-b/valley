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

func _decode(arg: Dictionary) -> Variant:
	if arg.has("int"): return int(arg["int"])
	if arg.has("float"): return float(arg["float"])
	if arg.has("fhex"): return _fhex_to_float(str(arg["fhex"]))
	if arg.has("vec3"):
		var c: Array = arg["vec3"]
		return Vector3(float(c[0]), float(c[1]), float(c[2]))
	return null

# Canonical serialization for parity: floats and vector components as IEEE-754
# hex, so the comparison is bit-level (matches Value.canonical / gd_driver).
func _canon(v: Variant) -> String:
	match typeof(v):
		TYPE_FLOAT: return "f:" + _hexle(v)
		TYPE_VECTOR3: return "v3:%s:%s:%s" % [_hexle(v.x), _hexle(v.y), _hexle(v.z)]
		TYPE_VECTOR2: return "v2:%s:%s" % [_hexle(v.x), _hexle(v.y)]
		TYPE_INT: return "i:%d" % v
		TYPE_BOOL: return "b:%s" % v
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

	# --- 3. PARITY: three real ports, full corpora, bit-for-bit --------------
	var manifest := [
		["cycle_grid_step", "res://cycle_grid_step.jsonl"],  # scalar in/out, small
		["snap_to_grid",    "res://snap_to_grid.jsonl"],     # vec3+float -> vec3 (snappedf)
		["ground_normal",   "res://ground_normal.jsonl"],    # 4 floats -> vec3 (cross+normalized)
	]
	var total := 0
	for row in manifest:
		var r := _parity(kernel, TS, row[0], row[1])
		if r[0] == 0: _fail("no corpus cases for " + row[0]); return
		if r[1] != 0: _fail("PARITY %s: %d/%d MISMATCH" % [row[0], r[1], r[0]]); return
		print("[probe] PARITY %-16s %3d/%d BIT-IDENTICAL to ToolkitSnap.gd" % [row[0], r[0], r[0]])
		total += r[0]
	print("[probe] PARITY total: %d cases bit-identical" % total)

	# --- 4. OVERHEAD (per-call µs, amortized over N calls) -------------------
	# Bench a SMALL function (cycle_grid_step) and a HEAVIER vector one
	# (ground_normal: two vec3 builds, cross, normalized), so the verdict sees
	# how VM cost scales with real work.
	print("[probe] OVERHEAD per call (µs), N=%d:" % N)
	_bench_row(kernel, TS, "cycle_grid_step", [3.0, 1])
	_bench_row(kernel, TS, "ground_normal", [0.0, 1.0, 2.0, 0.5])
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
