extends Node
## Caravans (autoload; the Understory walking the Ways): tier-3 agents
## carrying presence, goods, and news between places at real walking
## speed on the Almanac's clock. v1 is STATELESS — position is a pure
## function of (day, hour) along the road graph, so catch-up is free by
## construction (sim contract, option a) and the soak can't drift. The
## Chronicle mirrors each caravan (caravan.<id>.place / .news_day) for
## dialogue conditions. EMBODIMENT (2026-07-05, post NPC AgentSim port):
## near the focus a body walks the route — pure presentation seated on
## locate()'s answer every frame (the sim never changes shape), wearing
## the road in and greeting in passing; it dissolves out of sight.
## Toolkit hook: summary() answers where everyone is right now.

const BODY_SCENE := preload("res://game/world/caravan_body.tscn")
const EMBODY_DISTANCE := 140.0
const DISSOLVE_DISTANCE := 170.0  # hysteresis, the NPC/wildlife borders

var routes: Array[Dictionary] = []
var _bodies: Dictionary = {}  # route id -> CaravanBody node


func _ready() -> void:
	var dir := DirAccess.open("res://data/caravans")
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/caravans/" + f))
		if not (parsed is Dictionary and parsed.has("stops")):
			push_error("[caravans] bad record: " + f)
			continue
		var rec: Dictionary = parsed
		var stops: Array = rec["stops"]
		if stops.size() < 2:
			continue
		# Legs ride the road graph; lengths precomputed for the clock math.
		var legs: Array = []
		for i in stops.size():
			var a: Dictionary = stops[i]
			var b: Dictionary = stops[(i + 1) % stops.size()]
			var path := WaypointGraph.route(
				Vector2(float(a["x"]), float(a["z"])),
				Vector2(float(b["x"]), float(b["z"])))
			if path.size() < 2:
				path = PackedVector2Array([
					Vector2(float(a["x"]), float(a["z"])),
					Vector2(float(b["x"]), float(b["z"]))])
			var length := 0.0
			for k in path.size() - 1:
				length += path[k].distance_to(path[k + 1])
			legs.append({"path": path, "length": length,
				"depart": float(a["depart_hour"]), "from": a["place"], "to": b["place"]})
		routes.append({"id": rec.get("id", f.trim_suffix(".json")),
			"speed": float(rec.get("speed_mps", 1.2)), "legs": legs})
	GameClock.hour_tick.connect(_hourly)


## Embodiment tier-switching: locate() is cheap enough to answer every
## frame, so embodied caravans glide on fractional hours instead of
## teleporting hourly.
func _process(_delta: float) -> void:
	var focus := _focus_xz()
	for route in routes:
		var at := locate(route, GameClock.hours)
		var id: String = route.id
		var body: Node3D = _bodies.get(id)
		var d: float = focus.distance_to(at.pos) if focus.is_finite() else 1e12
		if body == null and d < EMBODY_DISTANCE:
			body = BODY_SCENE.instantiate()
			body.route_id = id
			add_child(body)
			_bodies[id] = body
		elif body != null and d > DISSOLVE_DISTANCE:
			body.queue_free()
			_bodies.erase(id)
			continue
		if body != null:
			body.seat(at.pos, at.en_route)


func _focus_xz() -> Vector2:
	if Toolkit.active:
		var c := Toolkit.cam_position()
		return Vector2(c.x, c.z)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		return Vector2(player.global_position.x, player.global_position.z)
	return Vector2.INF


## Where a caravan is at an hour-of-day: {place, pos, en_route}.
## Between depart hours it walks its leg at speed; done walking = at
## the destination. Pure function — no state, no drift.
func locate(route: Dictionary, hour: float) -> Dictionary:
	var legs: Array = route.legs
	var active: Dictionary = legs[legs.size() - 1]
	for leg in legs:
		if hour >= float(leg.depart):
			active = leg
	var since: float = hour - float(active.depart)
	if since < 0.0:
		since += 24.0  # yesterday's leg: pre-dawn means arrived, not waiting
	var walked: float = since * 3600.0 * route.speed
	var path: PackedVector2Array = active.path
	if walked >= float(active.length):
		return {"place": active.to, "pos": path[path.size() - 1], "en_route": false}
	var d := walked
	for k in path.size() - 1:
		var seg := path[k].distance_to(path[k + 1])
		if d <= seg:
			return {"place": "en_route", "en_route": true,
				"pos": path[k].lerp(path[k + 1], d / maxf(seg, 0.01))}
		d -= seg
	return {"place": active.to, "pos": path[path.size() - 1], "en_route": false}


func _hourly(_h: int) -> void:
	for route in routes:
		var at := locate(route, GameClock.hours)
		var key: String = "caravan.%s.place" % route.id
		var prev: String = str(WorldState.get_value(key, ""))
		WorldState.set_value(key, at.place)
		if not at.en_route and prev == "en_route":
			# Arrival: the caravan brings the day's news — a Chronicle
			# flag dialogue can condition on ("heard from the caravan").
			WorldState.set_value("caravan.%s.news_day" % route.id, GameClock.day)


## Toolkit: one line per caravan, right now.
func summary() -> String:
	var lines := PackedStringArray()
	for route in routes:
		var at := locate(route, GameClock.hours)
		lines.append("%s: %s (%.0f, %.0f)" % [route.id, at.place, at.pos.x, at.pos.y])
	return "\n".join(lines)
