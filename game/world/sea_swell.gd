extends Node
## SeaSwell (autoload): W1 ocean swell — the Watershed's open sea gets
## real waves. This node computes WHERE the wave energy is; the waves
## themselves are four Gerstner components summed in the water shader's
## vertex stage (near-free), displacing the sea meshes only. Amplitude/
## wavelength/direction come from the Elements: the local wind raises a
## base sea, and every traveling front radiates swell from its leading
## edge — full inside the band, decaying exponentially AHEAD of it, so
## heavy rollers reach the strand hours before the rain (the herald:
## free foreshadowing). Presentation only, like WaterWaves: a stateless
## function of (time, wind, fronts) — never saved, never fingerprinted,
## off headless. Physics and sims keep reading the flat
## Terrain.sea_surface(); swimming rides mean water at W1.

const SWELL_MAX := 0.95    # meters of amplitude a full storm earns
const BASE_AMP := 0.05     # a dead-calm sea never goes glassy-flat
const WIND_AMP := 0.30     # the local wind's own sea at wind=1
const LEN_CALM := 24.0     # primary wavelength, calm ripple swell
const LEN_STORM := 60.0    # primary wavelength at full storm energy
const HERALD_M := 5200.0   # e-fold reach of swell AHEAD of a front's edge
const WAKE_M := 2200.0     # swell decay behind a spent front's trailing edge
const EASE := 0.4          # per-second approach (presentation smoothing)

var enabled := false
var force_amp := -1.0      # Toolkit knob: >= 0 pins the amplitude (meters)
var amp := 0.0             # live eased amplitude, meters
var wavelength := LEN_CALM # live eased primary wavelength, meters
var direction := Vector2(1.0, 0.0)  # live eased travel direction
var source := "wind"       # what owns the swell right now (Toolkit line)


func _ready() -> void:
	# Same gate as the GPU water tiers: headless has no swell to show.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	enabled = true


func _process(delta: float) -> void:
	var t := compute(Weather.fronts, _focus_xz(), Weather.wind, Weather.wind_dir)
	source = String(t.source)
	var target_amp := float(t.amp)
	if force_amp >= 0.0:
		target_amp = force_amp
		source = "FORCED"
	var blend := 1.0 - exp(-EASE * delta)
	amp = lerpf(amp, target_amp, blend)
	wavelength = lerpf(wavelength, float(t.len), blend)
	var target_dir: Vector2 = t.dir
	direction = direction.rotated(direction.angle_to(target_dir) * blend).normalized()
	RenderingServer.global_shader_parameter_set("swell_amp", amp)
	RenderingServer.global_shader_parameter_set("swell_len", wavelength)
	RenderingServer.global_shader_parameter_set("swell_dir", direction)


## The energy math, pure + deterministic (scene-tested): swell at `focus`
## given a front list. A front's swell is its wind energy squared (gales
## raise big dry seas; drizzle barely stirs), at full strength inside the
## band, e-folding over HERALD_M ahead of the leading edge — swell
## outruns its weather — and dying over WAKE_M behind the trailing edge.
## The strongest arrival sets the direction (its travel heading); the
## local wind keeps a base sea under everything.
func compute(fronts: Array, focus: Vector2, wind_local: float,
		wind_dir: Vector2) -> Dictionary:
	var best := 0.0
	var best_dir := wind_dir
	var best_src := "wind"
	for f: Dictionary in fronts:
		var kind: Dictionary = Weather.KINDS[String(f.kind)]
		var e := float(kind.wind)
		if e <= 0.2:
			continue  # calm/overcast bands raise no sea worth naming
		var energy := SWELL_MAX * e * e
		var s: float = focus.x * float(f.dx) + focus.y * float(f.dz)
		var reach := 1.0
		if s > float(f.edge):
			reach = exp(-(s - float(f.edge)) / HERALD_M)
		elif s <= float(f.edge) - float(f.width):
			reach = exp(-(float(f.edge) - float(f.width) - s) / WAKE_M)
		var a := energy * reach
		if a > best:
			best = a
			best_dir = Vector2(float(f.dx), float(f.dz)).normalized()
			best_src = String(f.kind)
	var base := BASE_AMP + WIND_AMP * clampf(wind_local, 0.0, 1.0)
	var total := maxf(base, best)
	return {"amp": total,
		"len": lerpf(LEN_CALM, LEN_STORM, clampf(total / SWELL_MAX, 0.0, 1.0)),
		"dir": best_dir if best > base else wind_dir.normalized(),
		"source": best_src if best > base else "wind"}


## Toolkit: the open sea's state in one line.
func summary() -> String:
	if not enabled:
		return "off (headless)"
	return "%s  amp=%.2fm  L=%.0fm  dir=(%.2f, %.2f)%s" % [
		source, amp, wavelength, direction.x, direction.y,
		"" if force_amp < 0.0 else "  (FORCED)"]


func _focus_xz() -> Vector2:
	if Toolkit.active:
		var p := Toolkit.cam_position()
		return Vector2(p.x, p.z)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		return Vector2(player.global_position.x, player.global_position.z)
	return Vector2.ZERO
