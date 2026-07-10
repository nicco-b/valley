extends Node
## The P1 RULES TRIO four-run determinism matrix (Mission D1b — items/skills/
## budget). scripts/rules_matrix.sh boots THIS scene four times per file (2×
## STRATA_CONTOUR unset + 2× =1) and asserts, PER FILE (so a failure names its
## file): all four FINGERPRINTS identical (the routed Contour rules == the GDScript
## twin, bit-for-bit — items/skills over FINGERPRINTED player state, budget over
## its read-only grade output), and the ENGAGEMENT COUNTER earns it (0 flag-OFF,
## >0 flag-ON — proof the flag-ON runs actually routed, never a silent fallback).
##
## Each file runs a fixed, seeded operation SEQUENCE through the live autoload, so
## the flag toggles the ONLY variable: whether each rule answered from Contour or
## from GDScript. The fingerprint digests floats by their exact IEEE-754 bytes, so
## a one-ULP divergence in a routed rule would move it.
##
## Select the file with the env var D1B_MATRIX_FILE = items | skills | budget.

func _ready() -> void:
	var which := OS.get_environment("D1B_MATRIX_FILE")
	var fp := 0
	var status := {}
	match which:
		"items":
			fp = _run_items()
			status = Items.contour_status()
		"skills":
			fp = _run_skills()
			status = Skills.contour_status()
		"budget":
			fp = _run_budget()
			status = Budget.contour_status()
		_:
			print("D1B-MATRIX FAIL: set D1B_MATRIX_FILE = items | skills | budget (got '%s')" % which)
			get_tree().quit(2)
			return
	# The routing MUST be resolved to a known state (off / engaged / refused), never
	# a silent fallback. A refused mode (-1) is a hard fail — flag-ON with no kernel
	# must be loud, not a green matrix.
	var mode := int(status.get("mode", 0))
	if mode == -1:
		print("D1B-MATRIX FAIL: %s routing REFUSED (mode -1) — loud, not silent" % which)
		get_tree().quit(1)
		return
	print("D1B-MATRIX %s fp=%d mode=%d engaged=%s calls=%d" % [
		which, fp, mode, str(status.get("engaged", false)), int(status.get("calls", 0))])
	get_tree().quit(0)


## The exact IEEE-754 bytes of a float (bit-level, not a rounded print), so the
## fingerprint moves on a one-ULP divergence.
func _fhex(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()


# --- items: drive add() over player.inventory, then count/count_tag ------------

func _run_items() -> int:
	# Content-independent: inject a synthetic def table so count_tag is deterministic
	# regardless of what data/items ships (the RULE is what we prove, not content).
	Items._defs = {
		"apple": {"id": "apple", "name": "Apple", "tags": ["food", "forage"]},
		"berry": {"id": "berry", "name": "Berry", "tags": ["food"]},
		"axe": {"id": "axe", "name": "Axe", "tags": ["tool"]},
		"coin": {"id": "coin", "name": "Coin", "tags": []},
	}
	WorldState.set_value("player.inventory", {})
	# A seeded script exercising every add branch: grow an existing id (keeps slot),
	# add new ids, drive a count to exactly 0 and below 0 (both drop the id).
	var script := [
		["apple", 3], ["axe", 1], ["apple", 2], ["berry", 4],
		["axe", -1], ["coin", 5], ["coin", -10], ["apple", -4], ["berry", 1],
	]
	var parts := PackedStringArray()
	for step: Array in script:
		Items.add(step[0], step[1])
		parts.append("%s+%d=>%s" % [step[0], step[1], JSON.stringify(Items.inventory())])
	for id in ["apple", "berry", "axe", "coin", "ghost"]:
		parts.append("count(%s)=%d" % [id, Items.count(id)])
	for tag in ["food", "forage", "tool", "none"]:
		parts.append("count_tag(%s)=%d" % [tag, Items.count_tag(tag)])
	return hash("|".join(parts))


# --- skills: sweep a synthetic skill's stat, digest level + progress ----------

func _run_skills() -> int:
	var def := {"id": "d1b_probe", "name": "Probe", "stat": "stat.d1b_use",
		"thresholds": [10.0, 40.0, 80.0]}
	var parts := PackedStringArray()
	for v in [0.0, 5.0, 10.0, 25.0, 40.0, 60.0, 79.0, 80.0, 120.0]:
		WorldState.set_value("stat.d1b_use", v)
		parts.append("v=%s lvl=%d prog=%s" % [
			_fhex(v), Skills._level_for(def), _fhex(Skills.progress(def))])
	# level(id) over an injected def table (drives _level_for through the lookup).
	Skills._defs = [def]
	WorldState.set_value("stat.d1b_use", 45.0)
	parts.append("level(d1b_probe)=%d" % Skills.level("d1b_probe"))
	return hash("|".join(parts))


# --- budget: sweep grade over the three axes + worst_grade --------------------

func _run_budget() -> int:
	Budget.thresholds = {
		"cell_placements": {"amber": 250, "red": 600},
		"agents": {"amber": 500, "red": 1200},
		"records": {"amber": 10000, "red": 40000},
		"per_placement_ms": 0.02,
	}
	# grade is the routed atom (the GDScript worst_grade()/snapshot compose it from
	# LIVE counts, so they can't be driven with synthetic values through the
	# autoload — the .ct worst_grade is proven in the scene test's local VM + the
	# datum unit test instead).
	var parts := PackedStringArray()
	for axis in ["cell_placements", "agents", "records", "no_such_axis"]:
		for value in [0, 250, 400, 600, 900, 500, 1200, 45000]:
			parts.append("grade(%d,%s)=%d" % [value, axis, Budget.grade(value, axis)])
	return hash("|".join(parts))
