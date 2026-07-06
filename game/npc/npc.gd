extends CharacterBody3D
## A needs-driven inhabitant (the Understory). The record defines who
## they are — needs with drain weights, and activities that satisfy them
## at places. Since the AgentSim port (SIM_ROADMAP P1, 2026-07-05) the
## MIND lives in the shared sim core — the same needs/utility/advance
## logic wildlife runs — and this node is presentation + person: physics
## and animation when embodied, dialogue, rumors, produced-goods stock.
## Needs persist via WorldState (same keys as before the port).

const SPEED := 3.0
const ACCEL := 8.0
const ARRIVE_DISTANCE := 3.0
const DRAIN_SCALE := 6.0  # need points lost per game-hour at weight 1.0
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

## The mind (AgentSim): needs, utilities, current activity, coarse
## position. `needs` is a shared reference to sim.needs — the soak
## fingerprint and inspector read it exactly as before the port.
var sim := AgentSim.new()
var needs: Dictionary = {}  # alias of sim.needs (set in _ready)
## What this NPC knows, oldest first. Each fact mirrors to a WorldState
## flag npc.<id>.knows.<fact> so dialogue/quests condition on it.
var rumors: Array = []

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

	# The mind boots here: same knobs the pre-port NPC had, so behavior
	# (and the soak fingerprint) carries over move-for-move.
	sim.setup(npc_id, home, activities, needs_def)
	sim.drain_scale = DRAIN_SCALE
	sim.speed = SPEED
	sim.arrive = ARRIVE_DISTANCE
	sim.keep_bias = KEEP_CURRENT_BIAS
	sim.rng_stream = "npc"
	needs = sim.needs  # shared dict: soak + inspector read through it
	load_state()  # no-op on a fresh world; SaveGame calls it again post-restore
	GameClock.hour_tick.connect(func(_h: int) -> void:
		_observe_world()
		_save_state())
	sim.decide()
	_sync_target()


## The node walks toward the mind's target (XZ; y is presentation).
func _sync_target() -> void:
	_target = Vector3(sim.target.x, global_position.y, sim.target.y)


## Hourly snapshot to WorldState: needs, position, current activity — so a
## returning player finds everyone where the simulation left them, not
## respawned at home.
func _save_state() -> void:
	WorldState.set_value("npc.%s.needs" % npc_id, needs.duplicate())
	WorldState.set_value("npc.%s.pos" % npc_id,
		{"x": global_position.x, "z": global_position.z})
	WorldState.set_value("npc.%s.activity" % npc_id, sim.current.get("id", ""))
	WorldState.set_value("npc.%s.rumors" % npc_id, rumors.duplicate())
	# Goods the mind produced while working, flushed to the pantry.
	for item in sim.produced:
		var key := "npc.%s.stock.%s" % [npc_id, item]
		var stock: float = float(WorldState.get_value(key, 0.0))
		WorldState.set_value(key,
			snappedf(minf(stock + sim.produced[item], STOCK_CAP), 0.01))
	sim.produced.clear()


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
	sim.pos = Vector2(global_position.x, global_position.z)
	var act_id: String = str(WorldState.get_value("npc.%s.activity" % npc_id, ""))
	for a in activities:
		if a.id == act_id:
			sim.current = a
			sim.target = sim.resolve_at(a)
			_sync_target()
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
## The MIND advances (drain, travel, satisfy, decide — AgentSim.advance);
## the node re-seats on wherever the mind ended up.
func sim_advance_hours(dt_hours: float) -> void:
	sim.pos = Vector2(global_position.x, global_position.z)
	sim.advance(dt_hours)
	global_position = Vector3(sim.pos.x,
		Terrain.height(sim.pos.x, sim.pos.y) + 0.5, sim.pos.y)
	_sync_target()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Embodied: the body owns position; the mind keeps drives + decisions
	# (the wildlife pattern). Sync the mind's pos so its decisions and the
	# saved state see where the body actually stands.
	var dt_hours: float = GameClock.hours_delta(delta)
	sim.pos = Vector2(global_position.x, global_position.z)
	sim.drain(dt_hours)

	var to := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	var arrived := to.length() < ARRIVE_DISTANCE

	if arrived and not sim.current.is_empty():
		sim.satisfy(dt_hours)
		# Foragers drift around their spot (presentation wander: the
		# node's walking target, never the mind's).
		if sim.current.has("wander"):
			_wander_accum += delta
			if _wander_accum > 20.0:
				_wander_accum = 0.0
				var rng := Rng.stream("npc")
				var base := sim.resolve_at(sim.current)
				_target = Vector3(
					base.x + rng.randf_range(-1.0, 1.0) * float(sim.current.wander),
					global_position.y,
					base.y + rng.randf_range(-1.0, 1.0) * float(sim.current.wander)
				)

	_decide_accum += delta
	if _decide_accum >= DECIDE_INTERVAL:
		_decide_accum = 0.0
		var before: Dictionary = sim.current
		sim.decide()
		if sim.current != before:
			_sync_target()

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
			InteractionField.wear_only(Vector2(global_position.x, global_position.z))
			SandField.stamp(Vector2(global_position.x, global_position.z),
				_body.rotation.y, SandField.Mask.BOOT, 0.9)

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.3:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(flat.x, flat.z), blend)

	var target_anim := "Walking"
	if talking:
		target_anim = "Idle"
	elif arrived:
		target_anim = "Sitting" if sim.current.get("pose", "stand") == "sit" else "Idle"
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


## One-line-per-fact debug dump for the god-mode sim inspector: the
## mind's own dump (activity/needs/utilities) plus the person around it.
func sim_debug() -> String:
	var lines: Array[String] = [display_name, ""]
	lines.append("mode: %s" % ("coarse (far)" if far_mode else "embodied"))
	lines.append("pose: %s" % sim.current.get("pose", "stand"))
	lines.append(sim.debug_text())
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
