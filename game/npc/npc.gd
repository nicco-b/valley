extends CharacterBody3D
## A needs-driven inhabitant (utility AI). The record defines who they
## are — needs with drain weights, and activities that satisfy them at
## places — and behavior emerges: each need drains over game-time, each
## activity scores by how badly its need wants satisfying (gated softly
## by preferred hours), and the best activity wins with hysteresis so
## they don't dither. Needs persist via WorldState.

const SPEED := 3.0
const ACCEL := 8.0
const ARRIVE_DISTANCE := 3.0
const DRAIN_SCALE := 6.0  # need points lost per game-hour at weight 1.0
const SATISFY_SCALE := 10.0  # need points gained per game-hour at rate 1.0
const OFF_HOURS_GATE := 0.15
const KEEP_CURRENT_BIAS := 1.5
const DECIDE_INTERVAL := 0.5  # real seconds between decisions
# Two-tier simulation: beyond FAR_DISTANCE from the focus the body
# dissolves and the same sim runs coarsely (A-Life style); it re-forms
# inside NEAR_DISTANCE. Hysteresis prevents flapping at the border.
const FAR_DISTANCE := 170.0
const NEAR_DISTANCE := 140.0
const COARSE_INTERVAL := 2.0  # real seconds between coarse ticks

var npc_id := "npc"
var display_name := "???"
var home := Vector2.ZERO
var needs_def: Dictionary = {}  # need -> drain weight
var activities: Array = []
var scarf_color := Color.TRANSPARENT

const MAX_RUMORS := 12  # what one mind holds; the oldest falls out
const STOCK_CAP := 10.0  # a pantry, not a warehouse

var needs: Dictionary = {}  # need -> 0..100 (100 = content)
var current: Dictionary = {}
var last_utilities: Dictionary = {}
## What this NPC knows, oldest first. Each fact mirrors to a WorldState
## flag npc.<id>.knows.<fact> so dialogue/quests condition on it.
var rumors: Array = []
## Goods produced while working (activities with "produces"), buffered
## here and flushed to WorldState npc.<id>.stock.<item> hourly — the
## stocks trading (G4) will read and prices will derive from.
var _stock_accum: Dictionary = {}

var far_mode := false
var talking := false

var _target := Vector3.ZERO
var _nav := PathCursor.new()  # embodied walking follows the baked navmesh
var _decide_accum := 0.0
var _wander_accum := 0.0
var _coarse_accum := 0.0
var _step_accum := 0.0

@onready var _anim: AnimationPlayer = $Body/Model/AnimationPlayer
@onready var _body: Node3D = $Body


func setup(data: Dictionary) -> void:
	npc_id = data.id
	display_name = data.get("name", data.id)
	needs_def = data.needs
	activities = data.activities
	home = Vector2(data.home.x, data.home.z)
	if data.has("color"):
		scarf_color = Color(data.color[0], data.color[1], data.color[2])


func _ready() -> void:
	add_to_group("npc")
	add_to_group("sim_advance")  # steps through skipped time (GameClock.advance_hours)
	for n in ["Idle", "Walking"]:
		_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")
	$Interact.interacted.connect(_on_interacted)
	if scarf_color.a > 0.0:
		var scarf := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.34, 0.09, 0.34)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = scarf_color
		mat.roughness = 1.0
		mesh.material = mat
		scarf.mesh = mesh
		scarf.position = Vector3(0, 0.78, 0)
		_body.add_child(scarf)

	for need in needs_def:
		needs[need] = 70.0
	load_state()  # no-op on a fresh world; SaveGame calls it again post-restore
	GameClock.hour_tick.connect(func(_h: int) -> void:
		_observe_world()
		_save_state())
	_decide()


## Hourly snapshot to WorldState: needs, position, current activity — so a
## returning player finds everyone where the simulation left them, not
## respawned at home.
func _save_state() -> void:
	WorldState.set_value("npc.%s.needs" % npc_id, needs.duplicate())
	WorldState.set_value("npc.%s.pos" % npc_id,
		{"x": global_position.x, "z": global_position.z})
	WorldState.set_value("npc.%s.activity" % npc_id, current.get("id", ""))
	WorldState.set_value("npc.%s.rumors" % npc_id, rumors.duplicate())
	for item in _stock_accum:
		var key := "npc.%s.stock.%s" % [npc_id, item]
		var stock: float = float(WorldState.get_value(key, 0.0))
		WorldState.set_value(key,
			snappedf(minf(stock + _stock_accum[item], STOCK_CAP), 0.01))
	_stock_accum.clear()


func knows(fact: String) -> bool:
	return rumors.has(fact)


## Learn a fact — from the world or from someone. Selective memory: a mind
## holds MAX_RUMORS and forgets the oldest (its flag clears) — a world
## that remembers everything loses the meaning of memory.
func learn(fact: String, from_whom := "") -> void:
	if rumors.has(fact):
		return
	rumors.append(fact)
	WorldState.set_flag("npc.%s.knows.%s" % [npc_id, fact])
	if rumors.size() > MAX_RUMORS:
		var old: String = rumors.pop_front()
		WorldState.set_value("npc.%s.knows.%s" % [npc_id, old], false)
	if from_whom != "":
		print("[rumor] %s heard '%s' from %s" % [npc_id, fact, from_whom])


## Valley-scale states are hard to miss — inhabitants notice them as they
## live through them; person-scale facts only travel by telling.
func _observe_world() -> void:
	if WorldState.has_flag("valley.bloom"):
		learn("valley_bloomed")
	if WorldState.has_flag("valley.parched"):
		learn("valley_parched")
	if Weather.state == "storm":
		learn("weathered_storm")
	if WorldState.has_flag("npc.%s.met" % npc_id):
		learn("met_player")


## Re-read persisted state from WorldState. Called from _ready (fresh boot)
## and again by SaveGame after the save restores WorldState — spawn-time
## _ready runs a frame before the load, so it only ever sees defaults.
func load_state() -> void:
	var saved: Dictionary = WorldState.get_value("npc.%s.needs" % npc_id, {})
	for need in needs_def:
		needs[need] = float(saved.get(need, needs[need]))
	var pos: Dictionary = WorldState.get_value("npc.%s.pos" % npc_id, {})
	if not pos.is_empty():
		var x: float = pos.x
		var z: float = pos.z
		global_position = Vector3(x, Terrain.height(x, z) + 0.5, z)
	var act_id: String = str(WorldState.get_value("npc.%s.activity" % npc_id, ""))
	for a in activities:
		if a.id == act_id:
			current = a
			_target = _resolve_at(a)
			break
	var saved_rumors: Array = WorldState.get_value("npc.%s.rumors" % npc_id, [])
	rumors = saved_rumors.duplicate()


func _process(delta: float) -> void:
	# Tier switching runs regardless of mode; the focus is whatever the
	# streamer follows (player, god camera, or map).
	var focus := global_position
	var player := get_tree().get_first_node_in_group("player")
	if GodMode.active:
		focus = GodMode.cam_position()
	elif MapScreen.active:
		focus = MapScreen.focus_position()
	elif player:
		focus = player.global_position
	var d := global_position.distance_to(focus)
	if far_mode and d < NEAR_DISTANCE:
		_embody()
	elif not far_mode and d > FAR_DISTANCE:
		_dissolve()
	if far_mode:
		_coarse_accum += delta
		if _coarse_accum >= COARSE_INTERVAL:
			_coarse_tick(_coarse_accum)
			_coarse_accum = 0.0


func _dissolve() -> void:
	far_mode = true
	visible = false
	set_physics_process(false)
	$Collision.set_deferred("disabled", true)


func _embody() -> void:
	far_mode = false
	visible = true
	set_physics_process(true)
	$Collision.set_deferred("disabled", false)
	global_position.y = Terrain.height(global_position.x, global_position.z) + 0.5
	velocity = Vector3.ZERO


## The same simulation, coarse: needs drain, decisions happen, position
## advances in straight lines. No physics, no animation, ~nothing per tick.
func _coarse_tick(dt_real: float) -> void:
	sim_advance_hours(GameClock.hours_delta(dt_real))


## One coarse step, parameterized by game-hours — shared by the live far
## tier and time catch-up (GameClock.advance_hours "sim_advance" group).
## During catch-up an hour chunk covers kilometers, so journeys complete
## and activities cycle hour by hour while the player is away.
func sim_advance_hours(dt_hours: float) -> void:
	_drain(dt_hours)
	var dt_real := dt_hours * GameClock.day_length_minutes * 60.0 / 24.0
	var to := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	if to.length() < ARRIVE_DISTANCE:
		_satisfy(dt_hours)
	else:
		global_position += to.normalized() * minf(SPEED * dt_real, to.length())
	global_position.y = Terrain.height(global_position.x, global_position.z) + 0.5
	_decide()


func _drain(dt_hours: float) -> void:
	for need in needs:
		needs[need] = clampf(
			needs[need] - needs_def[need] * DRAIN_SCALE * dt_hours, 0.0, 100.0
		)


func _satisfy(dt_hours: float) -> void:
	if current.is_empty():
		return
	var need: String = current.satisfies
	needs[need] = clampf(
		needs[need] + float(current.get("rate", 6.0)) * SATISFY_SCALE * dt_hours,
		0.0, 100.0
	)
	# Work makes goods: time spent at a producing activity accrues stock.
	var produces: Dictionary = current.get("produces", {})
	for item in produces:
		_stock_accum[item] = float(_stock_accum.get(item, 0.0)) \
				+ float(produces[item]) * dt_hours


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var dt_hours: float = GameClock.hours_delta(delta)
	_drain(dt_hours)

	var to := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	var arrived := to.length() < ARRIVE_DISTANCE

	if arrived and not current.is_empty():
		_satisfy(dt_hours)
		# Foragers drift around their spot.
		if current.has("wander"):
			_wander_accum += delta
			if _wander_accum > 20.0:
				_wander_accum = 0.0
				var rng := Rng.stream("npc")
				_target = _resolve_at(current) + Vector3(
					rng.randf_range(-1.0, 1.0) * float(current.wander), 0.0,
					rng.randf_range(-1.0, 1.0) * float(current.wander)
				)

	_decide_accum += delta
	if _decide_accum >= DECIDE_INTERVAL:
		_decide_accum = 0.0
		_decide()

	var blend := 1.0 - exp(-ACCEL * delta)
	var target_velocity := Vector3.ZERO
	if not arrived and not talking:
		# Walk the navmesh route waypoint by waypoint; whiskers still
		# handle placed objects the bake doesn't know about.
		var wp := _nav.waypoint(delta, global_position,
			Vector3(_target.x, global_position.y, _target.z))
		var to_wp := Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
		if to_wp.length() > 0.1:
			target_velocity = _avoid(to_wp.normalized()) * SPEED
	velocity.x = lerpf(velocity.x, target_velocity.x, blend)
	velocity.z = lerpf(velocity.z, target_velocity.z, blend)
	move_and_slide()

	if is_on_floor():
		_step_accum += Vector2(velocity.x, velocity.z).length() * delta
		if _step_accum >= 0.7:
			_step_accum = 0.0
			InteractionField.stamp(Vector2(global_position.x, global_position.z), 0.9)
			SandField.stamp(Vector2(global_position.x, global_position.z),
				_body.rotation.y, SandField.Mask.BOOT, 0.9)

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.3:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(flat.x, flat.z), blend)

	var target_anim := "Walking"
	if talking:
		target_anim = "Idle"
	elif arrived:
		target_anim = "Sitting" if current.get("pose", "stand") == "sit" else "Idle"
	if _anim.assigned_animation != target_anim:
		_anim.play(target_anim, 0.3)


## Whisker steering around obstacles (layer 4: rocks, trees, structures —
## never terrain, so slopes don't read as walls).
func _avoid(desired: Vector3) -> Vector3:
	if not _blocked(desired):
		return desired
	for angle in [0.7, -0.7, 1.3, -1.3]:
		var alt := desired.rotated(Vector3.UP, angle)
		if not _blocked(alt):
			return alt
	return desired


func _blocked(dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 2.5, 4)
	params.exclude = [get_rid()]
	return not space.intersect_ray(params).is_empty()


func _decide() -> void:
	var best: Dictionary = {}
	var best_u := -1.0
	var current_u := 0.0
	last_utilities = {}
	for a in activities:
		var u: float = (100.0 - needs.get(a.satisfies, 50.0)) * _hours_gate(a)
		# Weather changes minds: storm_boost activities spike in bad weather.
		u *= 1.0 + Weather.storminess * float(a.get("storm_boost", 0.0))
		last_utilities[a.id] = u
		if a == current:
			current_u = u
		if u > best_u:
			best_u = u
			best = a
	# Hysteresis: stay with the current activity unless it's satisfied or
	# clearly beaten.
	if not current.is_empty() and needs.get(current.satisfies, 0.0) < 85.0 \
			and current_u * KEEP_CURRENT_BIAS >= best_u:
		return
	if best != current:
		current = best
		_target = _resolve_at(current)


func _hours_gate(a: Dictionary) -> float:
	if not a.has("hours"):
		return 1.0
	var start: float = a.hours[0]
	var end: float = a.hours[1]
	var h: float = GameClock.hours
	var inside := (h >= start and h < end) if start <= end \
			else (h >= start or h < end)  # window wraps midnight
	return 1.0 if inside else OFF_HOURS_GATE


func _resolve_at(a: Dictionary) -> Vector3:
	var xz := home
	if a.get("at") is Dictionary:
		xz = Vector2(a.at.x, a.at.z)
	return Vector3(xz.x, global_position.y, xz.y)


## One-line-per-fact debug dump for the god-mode sim inspector.
func sim_debug() -> String:
	var lines: Array[String] = [display_name, ""]
	lines.append("mode: %s" % ("coarse (far)" if far_mode else "embodied"))
	lines.append("activity: %s%s" % [
		current.get("id", "—"), " (%s)" % current.get("pose", "stand")
	])
	lines.append("")
	for need in needs:
		var v: float = needs[need]
		var bar := "".rpad(int(v / 10.0), "█").rpad(10, "░")
		lines.append("%-8s %s %3d" % [need, bar, int(v)])
	lines.append("")
	lines.append("utilities:")
	for id in last_utilities:
		lines.append("  %-10s %5.1f" % [id, last_utilities[id]])
	lines.append("")
	lines.append("knows:")
	for fact in rumors:
		lines.append("  " + str(fact))
	lines.append("")
	lines.append("stock:")
	for a in activities:
		for item in a.get("produces", {}):
			lines.append("  %-14s %5.2f" % [item, float(WorldState.get_value(
				"npc.%s.stock.%s" % [npc_id, item], 0.0))])
	return "\n".join(lines)


func _on_interacted(by: Node) -> void:
	if by is Node3D:
		var to: Vector3 = (by as Node3D).global_position - global_position
		_body.rotation.y = atan2(to.x, to.z)
	if Dialogue.has_dialogue(npc_id):
		talking = true
		Dialogue.ended.connect(func() -> void: talking = false, CONNECT_ONE_SHOT)
		Dialogue.start(npc_id, by)
		return
	# Fallback greeting for NPCs without a dialogue record yet.
	WorldState.set_flag("npc.%s.met" % npc_id)
	var n: int = WorldState.increment("npc.%s.encounters" % npc_id)
	var text := "%s studies you for a moment, then nods once." % display_name
	if n > 1:
		text = "%s nods. You again." % display_name
	HUD.say(display_name, text)
