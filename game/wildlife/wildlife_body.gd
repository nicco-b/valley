extends CharacterBody3D
## A wildlife body: presentation plus PERCEPTION over an AgentSim owned
## by WildlifeManager. The mind decides where to go; the body walks
## there, snaps to terrain, animates — and notices the player (SIM_
## ROADMAP P3): sight scaled by real light (day / dark night / moonlit
## night), hearing up close, an attention ladder of calm → alert (freeze,
## face you) → fleeing (pressed too close) → resume. Indifferent until
## provoked, but never oblivious. Data-tier animals don't perceive —
## nobody is there to be seen.
## Placeholder: the model is the star hound glb until canon names the
## valley's creatures.

const SPEED := 2.2
const FLEE_SPEED := 3.6
const ACCEL := 6.0
const ARRIVE := 4.0
const HEARING_RANGE := 6.0  # behind it, you're heard, not seen
const PRESS_RANGE := 9.0  # alert + this close = flee
const FLEE_DISTANCE := 20.0
const CALM_SECONDS := 3.0  # unseen this long -> back to its day
const RING_SIZE := 0.7  # body scale vs the player's 1.0: hound-sized rings
const RIDE_HEIGHT := 0.5  # body origin sits about this far above its feet
const SPLASH_DEPTH := 0.55  # dipping past this throws the one big entry ring

enum Attention { CALM, ALERT, FLEEING }

var species := "creature"
var sim: AgentSim = null  # the live mind (shared reference with the manager)
var fabric_chains: Array[Dictionary] = []  # this creature's dangle config (its record's "fabric")
var attention := Attention.CALM

var _sim_target := Vector3.ZERO
var _flee_target := Vector3.ZERO
var _calm_accum := 0.0
var _step_accum := 0.0
var _wading_deep := false  # deep-water edge: crossing it splashes once
var _nav := PathCursor.new()  # embodied walking follows the baked navmesh

@onready var _anim: AnimationPlayer = $Body/Model/AnimationPlayer
@onready var _body: Node3D = $Body


func _ready() -> void:
	for n in ["Idle", "Walking"]:
		if _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if _anim.has_animation("Idle"):
		_anim.play("Idle")
	CharacterPaint.apply($Body/Model)
	# F2 fabric: dangle config rides the record (WildlifeManager sets
	# fabric_chains before add_child, same pattern as species). Spring
	# bones stream it in wind and lag it through turns. Presentation
	# only; headless runs never construct the simulator (PLAN_FABRIC
	# determinism stance).
	FabricSpring.adopt($Body/Model, fabric_chains)


func set_target(t: Vector2) -> void:
	_sim_target = Vector3(t.x, 0.0, t.y)


## How far it can see, from the real sky: generous by day, short on a
## black night, a little back under a bright moon. Pure for testability.
static func sense_range_for(solar_h: float, moonlight: float) -> float:
	var elevation := sin((solar_h - 6.0) / 24.0 * TAU)
	var light := clampf(elevation * 1.5, 0.0, 1.0)
	light = maxf(light, 0.25 * moonlight)
	return 10.0 + 16.0 * light


## Hard re-seat after a time catch-up: the data lived the hours; the
## body teleports to wherever that put it.
func seat(pos: Vector2, target: Vector2) -> void:
	global_position = Vector3(pos.x, Terrain.height(pos.x, pos.y) + 0.4, pos.y)
	velocity = Vector3.ZERO
	set_target(target)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	_perceive(delta)

	var target := _sim_target
	var speed := SPEED
	var hold := false
	match attention:
		Attention.ALERT:
			hold = true  # freeze, watch
		Attention.FLEEING:
			target = _flee_target
			speed = FLEE_SPEED

	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var arrived := hold or to.length() < ARRIVE
	var blend := 1.0 - exp(-ACCEL * delta)
	var target_velocity := Vector3.ZERO
	if not arrived:
		var wp := _nav.waypoint(delta, global_position,
			Vector3(target.x, global_position.y, target.z))
		var to_wp := Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
		if to_wp.length() > 0.1:
			target_velocity = to_wp.normalized() * speed
	velocity.x = lerpf(velocity.x, target_velocity.x, blend)
	velocity.z = lerpf(velocity.z, target_velocity.z, blend)
	move_and_slide()

	# Hooves press the sand too — herd routes wear into desire paths.
	if is_on_floor():
		_step_accum += Vector2(velocity.x, velocity.z).length() * delta
		if _step_accum >= 0.7:
			_step_accum = 0.0
			var pxz := Vector2(global_position.x, global_position.z)
			InteractionField.wear_only(pxz)
			SandField.stamp(pxz, _body.rotation.y, SandField.Mask.PAW, 0.8)
			# ...and the same stride rings the water (PLAN_SUBSTANCES S1):
			# speed scales the dent, body size scales the ring, and a
			# standing animal lets the pool go still for free — the
			# accumulator only advances while it moves. One water query
			# per stride, never per frame; wading past its depth throws
			# the one big entry splash (the crown of spray is S6's).
			var wsurf := Terrain.water_surface(
				global_position.x, global_position.z)
			var dip := wsurf + RIDE_HEIGHT - global_position.y \
					if wsurf > -1e11 else -1.0
			var ring := WaterWaves.wade_ring(dip,
				Vector2(velocity.x, velocity.z).length(), RING_SIZE)
			if ring != Vector2.ZERO:
				WaterWaves.disturb(pxz, ring.x, ring.y)
			var deep := dip > SPLASH_DEPTH
			if deep and not _wading_deep:
				var splash := WaterWaves.splash_ring(
					Vector2(velocity.x, velocity.z).length(), RING_SIZE)
				WaterWaves.disturb(pxz, splash.x, splash.y)
			_wading_deep = deep

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.3:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(flat.x, flat.z), blend)
	elif attention == Attention.ALERT:
		# Frozen, but its head is on you.
		var player := get_tree().get_first_node_in_group("player")
		if player:
			var to_p: Vector3 = player.global_position - global_position
			_body.rotation.y = lerp_angle(_body.rotation.y, atan2(to_p.x, to_p.z), blend)

	var target_anim := "Idle" if arrived else "Walking"
	if _anim.has_animation(target_anim) and _anim.assigned_animation != target_anim:
		_anim.play(target_anim, 0.3)


func _perceive(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		attention = Attention.CALM
		return
	var to_p: Vector3 = player.global_position - global_position
	var d := to_p.length()
	var sense := sense_range_for(GameClock.solar_hours(), GameClock.moon_light())
	var facing := Vector3(sin(_body.rotation.y), 0.0, cos(_body.rotation.y))
	var noticed := d < HEARING_RANGE \
			or (d < sense and to_p.normalized().dot(facing) > 0.1)
	match attention:
		Attention.CALM:
			if noticed:
				attention = Attention.ALERT
				_calm_accum = 0.0
		Attention.ALERT:
			if d < PRESS_RANGE:
				attention = Attention.FLEEING
				var away := -to_p.normalized() * FLEE_DISTANCE
				_flee_target = global_position + Vector3(away.x, 0.0, away.z)
			elif not noticed:
				_calm_accum += delta
				if _calm_accum > CALM_SECONDS:
					attention = Attention.CALM
			else:
				_calm_accum = 0.0
		Attention.FLEEING:
			if d > sense * 1.4:
				attention = Attention.CALM
			elif d < PRESS_RANGE:  # still pressed: keep choosing away
				var away := -to_p.normalized() * FLEE_DISTANCE
				_flee_target = global_position + Vector3(away.x, 0.0, away.z)


## One-line-per-fact dump for the Toolkit sim inspector.
func sim_debug() -> String:
	var state: String = ["calm", "alert", "fleeing"][attention]
	if sim == null:
		return "%s (wild) — %s" % [species, state]
	return "%s (wild)\nattention: %s\n\n%s" % [species, state, sim.debug_text()]
