extends Node
## Determinism-trap probe (fork engine only — a no-op on stock Godot).
##
## Plants fingerprint crimes INSIDE the sim-tick door — a "sim_advance"
## handler driven by GameClock.advance_hours, which arms the fork's
## Engine.set_deterministic_section — and lets the trap name them:
##   * a bare unseeded global randf()  (the global RNG cannot be reproduced)
##   * a raw Time.get_unix_time_from_system() wall-clock read
## The SAME handler first draws from a SEEDED RandomNumberGenerator — the
## lawful path — which must stay silent.
##
## The assertion is at the harness level: test.sh runs this probe, captures
## stderr (2>&1), and greps for the trap's message + a GDScript backtrace,
## exactly like valley's other negative tests. The innocence half — the WHOLE
## sim running clean with the trap armed — is proven by test.sh + soak.sh
## going green (game_clock.gd exempts only GameClock's own sanctioned clock
## reads; every other tick draw must be seeded).
##
## On a stock engine (no fork method) the probe prints SKIP and exits 0.


class _Crime:
	extends Node
	## A sim member: its sim_advance_hours() runs under advance_hours' armed
	## section. mode picks which crime it commits after the lawful draw.
	var mode := "rng"
	var _seeded := RandomNumberGenerator.new()

	func sim_advance_hours(_dt: float) -> void:
		_seeded.seed = 20260709
		var _lawful := _seeded.randf()  # seeded instance — the trap allows it
		if mode == "rng":
			var _crime := randf()  # bare global draw — the trap must name this
		else:
			var _crime := Time.get_unix_time_from_system()  # wall clock — named too


func _plant(mode: String, label: String) -> void:
	var c := _Crime.new()
	c.mode = mode
	add_child(c)
	c.add_to_group("sim_advance")
	print("DET-TRAP: ", label)
	GameClock.advance_hours(1.0)  # arms the trap, then fires the sim group
	remove_child(c)  # out of the tree → out of call_group's reach
	c.free()


func _ready() -> void:
	if not Engine.has_method(&"set_deterministic_section"):
		print("DET-TRAP SKIP: engine has no determinism trap (stock Godot)")
		get_tree().quit(0)
		return

	print("DET-TRAP: planting crimes inside GameClock.advance_hours (the sim-tick door)")
	_plant("rng", "crime 1 — bare randf() in a sim_advance handler")
	_plant("clock", "crime 2 — Time.get_unix_time_from_system() in a sim_advance handler")

	# Innocence sanity: once advance_hours returns the section is DISARMED,
	# so a bare randf() here must be silent (no further ERROR at the harness).
	var _quiet := randf()

	print("DET-TRAP PASS: crimes planted — the trap's ERROR + backtrace are above")
	get_tree().quit(0)
