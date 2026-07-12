extends Node
class_name WaterAudio
## W10a — the sensory layer's positional water beds (STUDY_WATER_TERRAIN.md
## §W10). Ambience.gd's beds are biome-wide (one player, crossfades in/out
## of a biome); river reach + waterfall roar need to sound FROM a place —
## a brook's gurgle should come from the brook, a cataract's roar from the
## lip, and each should get louder with real discharge/drop, not a biome
## flag. This node is the ONE emitter type both rows share: it reads two
## data/audio/water/*.json rows (kind "audio_water_emitter", the same
## Records-desk idiom as audio_ambience — schema + dir + reloader, LAW A3)
## and plants one looping AudioStreamPlayer3D per site:
##   - river_bed: one per Terrain river, at the reach's midpoint node.
##     Gain = gain_ref * flow_norm(river.id) (discharge-scaled, 4b-ii).
##   - falls_roar: one per fall site (river.falls[]), at the bake's plunge
##     base. Gain = gain_ref * clamp(drop/drop_ref) * flow_norm(river.id) —
##     the drop-scaled, flow_norm-loudness roar §W10(a) asks for.
## Presentation only (LAW A1): reads Terrain/Hydrology every frame, never
## writes them, never touches a seeded stream, never moves the soak
## fingerprint. Shore lap needs none of this — "strand" is already a real
## biome id, so it ships as a plain Ambience row (biomes: ["strand"]),
## zero new code.
const WATER_AUDIO_KIND := "audio_water_emitter"
const WATER_AUDIO_DIR := "res://data/audio/water"
const WATER_AUDIO_SCHEMA := {
	"id": TYPE_STRING, "file": TYPE_STRING, "bus": TYPE_STRING,
}

var _river_rec: Dictionary = {}
var _falls_rec: Dictionary = {}
var _river_emitters: Array[Dictionary] = []  # {river_idx, player}
var _falls_emitters: Array[Dictionary] = []  # {river_idx, fall_idx, player}


func _ready() -> void:
	Records.register_schema(WATER_AUDIO_KIND, WATER_AUDIO_SCHEMA)
	Records.register_dir(WATER_AUDIO_KIND, WATER_AUDIO_DIR)
	Records.register_reloader(WATER_AUDIO_KIND, reload)
	Terrain.water_reloaded.connect(_rebuild)
	Terrain.river_added.connect(func(_r): _rebuild())
	_rebuild.call_deferred()


func reload() -> void:
	_rebuild()


## Read the two rows and (re)plant an emitter per site. Content-empty (no
## dir / no rows) tears everything down and stays silent — the FW4 neutral
## fallback, same as Ambience.
func _rebuild() -> void:
	_teardown()
	_river_rec = _read_row("river_bed.json")
	_falls_rec = _read_row("falls_roar.json")
	if not _river_rec.is_empty():
		for r in Terrain.rivers:
			var nodes: Array = r.get("nodes", [])
			if nodes.is_empty():
				continue
			var mid: Dictionary = nodes[nodes.size() / 2]
			var pos: Vector2 = mid.pos
			var player := _spawn(_river_rec, Vector3(pos.x, float(mid.surface), pos.y))
			_river_emitters.append({"river_idx": r.idx, "player": player})
	if not _falls_rec.is_empty():
		for r in Terrain.rivers:
			var falls: Array = r.get("falls", [])
			for fi in falls.size():
				var fl: Dictionary = falls[fi]
				var base: Vector2 = fl.get("base", fl.get("pos", Vector2.ZERO))
				var y := Terrain.height(base.x, base.y)
				var player := _spawn(_falls_rec, Vector3(base.x, y, base.y))
				_falls_emitters.append({"river_idx": r.idx, "fall_idx": fi, "player": player})


func _teardown() -> void:
	for e in _river_emitters:
		if is_instance_valid(e.player):
			e.player.queue_free()
	for e in _falls_emitters:
		if is_instance_valid(e.player):
			e.player.queue_free()
	_river_emitters.clear()
	_falls_emitters.clear()


## Read+validate one row through the same desk validator the ambience
## beds use, plus the honest bus/file checks. {} on any failure — content
## missing/broken never errors, it just stays silent (FW4).
func _read_row(file: String) -> Dictionary:
	var path := WATER_AUDIO_DIR + "/" + file
	var rec = Records.load_json(path)
	if not (rec is Dictionary) or not Records.validate(rec, WATER_AUDIO_SCHEMA, path):
		return {}
	var bus := String(rec["bus"])
	if AudioServer.get_bus_index(bus) < 0:
		push_error("[water_audio] %s: bus '%s' is not a house bus" % [path, bus])
		return {}
	var file_path := String(rec["file"])
	if not ResourceLoader.exists(file_path):
		push_error("[water_audio] %s: missing file '%s'" % [path, file_path])
		return {}
	return rec


func _spawn(rec: Dictionary, pos: Vector3) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = String(rec["bus"])
	player.stream = load(String(rec["file"]))
	player.max_distance = float(rec.get("max_distance", 60.0))
	player.unit_size = float(rec.get("unit_size", 6.0))
	player.volume_db = -80.0
	player.position = pos
	add_child(player)
	player.play()
	return player


func _process(_delta: float) -> void:
	for e in _river_emitters:
		if not is_instance_valid(e.player):
			continue
		var river: Dictionary = Terrain.rivers[e.river_idx]
		var lin := river_gain(_river_rec, Hydrology.flow_norm(String(river.id)))
		e.player.volume_db = linear_to_db(clampf(lin, 0.0001, 1.0))
	for e in _falls_emitters:
		if not is_instance_valid(e.player):
			continue
		var river: Dictionary = Terrain.rivers[e.river_idx]
		var fl: Dictionary = river.falls[e.fall_idx]
		var lin := falls_gain(_falls_rec, Hydrology.flow_norm(String(river.id)), float(fl.get("drop", 0.0)))
		e.player.volume_db = linear_to_db(clampf(lin, 0.0001, 1.0))


## --- pure evaluation (unit-testable, no engine/sim state) ---------------

## River reach bed gain: discharge-scaled off Hydrology's flow_norm (0..1ish).
static func river_gain(rec: Dictionary, flow_norm: float) -> float:
	return float(rec.get("gain_ref", 0.0)) * maxf(flow_norm, 0.0)


## Waterfall roar gain: drop-scaled (a trickle vs. a cataract) times the
## same flow_norm loudness value the river bed reads — a flooded river's
## fall roars harder than the same drop idling low.
static func falls_gain(rec: Dictionary, flow_norm: float, drop_m: float) -> float:
	var drop_n := clampf(drop_m / maxf(float(rec.get("drop_ref", 12.0)), 0.01), 0.0, 1.0)
	return float(rec.get("gain_ref", 0.0)) * drop_n * maxf(flow_norm, 0.0)
