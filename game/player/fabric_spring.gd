class_name FabricSpring
extends SpringBoneSimulator3D
## Fabric, bone tier (PLAN_FABRIC F2): secondary motion for the danglable
## chains a rig already carries — the star hound's tail, the fox's ears,
## F3's `cloth.*` cloaks when real bodies land. A thin wrapper over the
## engine's SpringBoneSimulator3D that (a) auto-adopts the chains a
## skeleton actually has, (b) feeds `external_force` from Weather every
## frame — the ONE wind truth; fabric never invents wind — and (c) fades
## its influence out with camera distance so chains die long before the
## Understory dissolves their bodies.
## Presentation only (the water-tier precedent): headless runs never
## construct one, nothing touches WorldState, the soak digest has — by
## construction — nothing of ours to see. Movement coupling is free:
## spring bones live in skeleton space and lag the body naturally.
## Toolkit: summary() is the SPRING line (chain census + feed cost).
## Two solver facts worth not relearning: (1) modifiers only tick while
## the skeleton advances — every creature loops an animation, so this
## is free today; (2) modifier output is NON-destructive — script-side
## bone poses revert after the skin upload, so read results inside
## `skeleton_updated` (see fabric_bones_probe.gd).

## Chain presets, gouache-tuned: damped and chunky, never AAA-jiggly
## (art bible — motion reads painterly; a wag is a brushstroke). A rig
## adopts every preset whose root bone it carries. `wind` scales
## Weather's force per chain class, calibrated against the solver
## (2026-07-08 sweep): a storm leans the hound's ~0.7 m tail ~0.27 m
## downwind while calm barely breathes it (~0.04 m); a gale flicks the
## ears ~17 degrees, calm ~3. Leaf bones (ears) extend a virtual tip so
## a one-bone chain still has a lever to swing.
const PRESETS: Array[Dictionary] = [
	{"root": "tail.1", "end": "tail_star", "stiffness": 2.4, "drag": 0.7,
		"gravity": 0.1, "radius": 0.05, "wind": 0.4},
	{"root": "ear.L", "end": "ear.L", "stiffness": 3.2, "drag": 0.8,
		"gravity": 0.05, "radius": 0.03, "wind": 1.2, "extend": 0.14},
	{"root": "ear.R", "end": "ear.R", "stiffness": 3.2, "drag": 0.8,
		"gravity": 0.05, "radius": 0.03, "wind": 1.2, "extend": 0.14},
]

# Distance fade (plan LOD stance): influence eases to 0 well inside the
# Understory's ~170 m body dissolve, so a chain never outlives its read.
const FADE_NEAR := 45.0
const FADE_FAR := 60.0

static var _live: Array[FabricSpring] = []  # Toolkit census

var wind_scale := 1.0        # max of adopted presets' wind factors
var influence_override := -1.0  # probe/Toolkit knob: >= 0 pins influence

var _phase := 0.0            # positional gust phase, hashed at ready
var _was_faded_out := false  # reset() on re-entry so no stale-state pop
var _feed_us := 0.0          # our per-frame feed cost (not the C++ solve)


## The public door: adopt whatever danglable chains this model's skeleton
## carries. Headless gate first (house pattern, sea_swell.gd) — no
## window, no simulator EXISTS, so soak and tests never meet spring
## state. Returns null when gated or when the rig has nothing to dangle.
static func adopt(model_root: Node) -> FabricSpring:
	if DisplayServer.get_name() == "headless":
		return null
	var skels := model_root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return null
	return build(skels[0])


## Gate-free construction — split out so the scene test can prove the
## windowed path assembles correct chains while itself running headless.
## Only adopt() (gated) and tests should call this.
static func build(skeleton: Skeleton3D) -> FabricSpring:
	var chains: Array[Dictionary] = []
	for p in PRESETS:
		if skeleton.find_bone(String(p.root)) >= 0:
			chains.append(p)
	if chains.is_empty():
		return null
	var fs := FabricSpring.new()
	fs.name = "FabricSpring"
	skeleton.add_child(fs)
	fs.setting_count = chains.size()
	for i in chains.size():
		var c: Dictionary = chains[i]
		fs.set_root_bone_name(i, String(c.root))
		fs.set_end_bone_name(i, String(c.end))
		if c.has("extend"):
			fs.set_extend_end_bone(i, true)
			fs.set_end_bone_direction(i, BONE_DIRECTION_FROM_PARENT)
			fs.set_end_bone_length(i, float(c.extend))
		fs.set_stiffness(i, float(c.stiffness))
		fs.set_drag(i, float(c.drag))
		fs.set_gravity(i, float(c.gravity))
		fs.set_radius(i, float(c.radius))
		fs.wind_scale = maxf(fs.wind_scale, float(c.wind))
	return fs


func _enter_tree() -> void:
	_live.append(self)


func _exit_tree() -> void:
	_live.erase(self)


func _ready() -> void:
	# Gust phase from world position — deterministic hash, no Rng stream
	# (cosmetic-local, the water_waves rule), and neighbors de-sync so a
	# pack's tails don't metronome.
	var origin := global_position
	_phase = origin.x * 0.37 + origin.z * 0.53


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	# Fade by camera distance; snap the chain to its authored pose when
	# out of range and reset() on the way back so re-entry doesn't pop.
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var fade := 1.0
	if cam != null:
		fade = 1.0 - smoothstep(FADE_NEAR, FADE_FAR,
				cam.global_position.distance_to(global_position))
	if influence_override >= 0.0:
		fade = influence_override
	influence = fade
	if fade <= 0.0:
		active = false
		_was_faded_out = true
		return
	if _was_faded_out:
		_was_faded_out = false
		reset()
	active = true
	# The wind feed: one truth, gusted like the flora. Direction is
	# FROM->TO on xz (weather.gd) — fabric streams TOWARD +wind_dir, in
	# agreement with the banners, the dust, and the swell. The gust is
	# two sine octaves phase-offset by world position, the flora_sway
	# recipe on the CPU, so tails and grass answer the same squall.
	var w: float = Weather.wind
	var spd := 0.7 + 1.6 * w
	var t := float(Time.get_ticks_msec()) * 0.001
	var gust := 1.0 + 0.35 * (sin(t * spd + _phase)
			+ 0.4 * sin(t * spd * 2.7 + _phase * 1.7))
	external_force = Vector3(Weather.wind_dir.x, 0.0, Weather.wind_dir.y) \
			* (w * wind_scale * gust)
	_feed_us = float(Time.get_ticks_usec() - t0)


## Toolkit: the SPRING line — live chain census plus what the wind feed
## itself costs (the solve runs in C++ inside the skeleton update; the
## measured GDScript ceiling for thirty dressed characters is 0.19 ms,
## so the budget line watches the feed, not the physics).
static func summary() -> String:
	if _live.is_empty():
		return "no chains embodied"
	var sets := 0
	var joints := 0
	var feed := 0.0
	for fs in _live:
		sets += fs.setting_count
		for i in fs.setting_count:
			joints += fs.get_joint_count(i)
		feed += fs._feed_us
	var f: Vector3 = _live[0].external_force
	return "%d body(ies)  %d chain(s)  %d joints  feed=%.1fus  force=(%.2f, %.2f, %.2f)" % [
		_live.size(), sets, joints, feed, f.x, f.y, f.z]
