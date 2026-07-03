extends Node
## Rng (autoload): seeded random streams, one per simulation system —
## determinism as a discipline (SIM_ROADMAP extreme tier). Given the same
## save and the same span of time, the world replays identically: every
## sim system draws from its own named stream seeded from the world seed,
## so no system's draws can perturb another's, and stream states persist
## through WorldState so a save/load doesn't fork history.
##
## The law: SIMULATION randomness comes from Rng.stream("<system>").
## Cosmetic randomness (particles, animation phase, placement tools) may
## keep using global randf() — it can't touch world state.

var _streams: Dictionary = {}  # name -> RandomNumberGenerator
var _world_seed: int = 0


func _ready() -> void:
	add_to_group("world_state_reader")
	load_state()
	GameClock.hour_tick.connect(func(_h: int) -> void: _save_state())


func load_state() -> void:
	var saved: Variant = WorldState.get_value("world.seed")
	if saved == null:
		_world_seed = randi()  # rolled once per new world, saved forever
		WorldState.set_value("world.seed", _world_seed)
	else:
		_world_seed = int(saved)
	_streams.clear()


## The named stream for a sim system, created (or restored from the
## save) on first use.
func stream(stream_name: String) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		var r := RandomNumberGenerator.new()
		var saved_state := str(WorldState.get_value("rng.%s" % stream_name, ""))
		if saved_state != "":
			r.state = saved_state.to_int()
		else:
			r.seed = hash("%d:%s" % [_world_seed, stream_name])
		_streams[stream_name] = r
	return _streams[stream_name]


func _save_state() -> void:
	# u64 state as String: JSON numbers are doubles and would corrupt it.
	for stream_name in _streams:
		WorldState.set_value("rng.%s" % stream_name, str(_streams[stream_name].state))
