extends Node
## BootClock — the boot state machine's phase table, for free (2026-07-12 boot
## forensics). Today the only boot-timing signal is Strata's own "world live
## (Ns)" line, computed pane-side from a wall-clock guess with no visibility
## into what happened between engine start and the near-ring settle. This
## autoload adds no new state machine: it timestamps the phase EDGES the
## streamer/terrain/hydrology/water_bodies already name and print (boot_phase,
## near_ring_settled, first_frame_rendered, the kernel/catchments/bathymetry
## "live" prints), one line per edge, in the house [bracket] print idiom
## (hydrology's "catchments in %dms", terrain's "kernel live") rather than a
## new format.
##
## Cheap and one-shot: mark(phase) no-ops after the first call per boot cycle
## — no per-frame cost, no polling. `engine_up` is a true process-level
## milestone (this autoload's own _ready, the earliest hook the framework
## owns) and fires exactly once per process. Every other phase resets at
## reset_boot(), called from world_streamer._ready() — matching the streamer's
## OWN one-shot booleans (_first_frame_seen, _boot_window), which do NOT reset
## on an in-process reload_world (Terrain re-reads disk under the same
## streamer node; StrataLink's reload_world verb never recreates it). A new
## boot, for this clock exactly as for the streamer, is a fresh world_streamer
## node — leaving to title and re-entering the world, not a bless reload.

var _t0 := 0
var _fired: Dictionary = {}  # phase name -> true, this boot cycle
var _edges: Array = []  # [{phase, ms}] in arrival order, this boot cycle
var _streamers := 0  # world_streamer nodes seen this process

## --- WINDOWED-only boot phases (loop-compression 2026-07-12) ---
## The headless smoke table (BOOT_BAKE.md) strips the GPU present cost with the
## dummy renderer — and that cost IS the bulk of the ~150s INTERACTIVE boot the
## standing pain names. These three edges time the windowed critical path and
## appear ONLY on a real windowed boot (gated on a non-headless display server):
## an absent row on the headless table is honest, exactly like bathymetry_done's
## absence, not a hole. All three are inert until the streamer arms them at the
## first honest frame (arm_windowed), and a no-op under --headless thereafter.
##   near_ring_meshed — the wall moment the LAST near-ring cell's visual mesh
##                      landed on the main thread (the mesh build WAVES have
##                      drained to the near ring). Counted per near-cell land via
##                      note_wave; the count + span is logged when world_live
##                      settles. Precedes world_live (the walkable-collision
##                      settle) — the visible ground beats the walkable ground.
##   first_present    — the first GPU frame actually pushed to the display AFTER
##                      an honest near-ground mesh exists (RenderingServer's
##                      frame_post_draw, armed by first_frame_rendered). The wall
##                      moment pixels reach the screen; headless never presents.
##   steady_frame     — the first frame after first_present whose frame time held
##                      at/under STEADY_MS for STEADY_RUN frames running: boot
##                      hitching (shader-compile stalls, mesh-upload spikes) has
##                      subsided. A "warm" PROXY measured from frame cadence, not
##                      a compiler hook — GDScript has no shader-compile signal.
const STEADY_MS := 34.0   # a frame at/under ~30fps — boot hitching has cleared
const STEADY_RUN := 30    # consecutive smooth frames before we call it warm
var _windowed_armed := false
var _steady_run := 0
var _wave_count := 0       # near-ring cell meshes landed this boot window
var _wave_first_ms := -1
var _wave_last_ms := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	# The steady-frame watcher runs in _process; keep it inert until a windowed
	# boot arms it (arm_windowed re-enables), so engine_up..first_present cost
	# nothing per frame and --headless never processes.
	set_process(false)
	mark("engine_up")


## Starts a fresh boot cycle: clears every phase but the process-level
## engine_up (which cannot recur — the engine boots once). Call from
## world_streamer._ready(), the streamer's own one-shot-per-instance hook.
## The FIRST streamer of the process is the boot already in progress — the
## autoload edges on the table (engine_up at 0, kernel_live from
## Terrain._ready) belong to it, and _t0 must stay the engine's zero, so the
## first call is a no-op. Every later streamer is an in-process switch: a
## new boot for phase purposes, re-zeroed here. Phases that don't recur on
## a switch (a kernel that stays live) simply don't appear in that boot's
## table — an absent row is honest, a carried timestamp is not.
func reset_boot() -> void:
	_streamers += 1
	if _streamers <= 1:
		return
	_t0 = Time.get_ticks_msec()
	_fired.clear()
	_edges.clear()
	# A switch is a fresh boot for the windowed phases too: re-arm from zero so
	# the next honest frame times this boot's present/warm, not the last one's.
	_windowed_armed = false
	_steady_run = 0
	_wave_count = 0
	_wave_first_ms = -1
	_wave_last_ms = 0
	set_process(false)
	mark("engine_up")  # the engine is already up: this boot's zero


## Record one phase edge, once. A repeat call (a kernel re-init off a config
## change, a second near-ring settle after an edit) is a silent no-op — the
## phase table is boot-only, not a running log.
func mark(phase: String) -> void:
	if _fired.has(phase):
		return
	_fired[phase] = true
	# Bracket-prefixed on purpose: test.sh's smoke gate filters "[" lines as
	# intentional logging (see runtime/scripts/test.sh FILTER), and the smoke
	# stanza's phase-table print greps this exact prefix.
	var ms := Time.get_ticks_msec() - _t0
	_edges.append({"phase": phase, "ms": ms})
	print("[boot] %s ms=%d" % [phase, ms])


## The table as one wire token: "engine_up:0,kernel_live:214,...". Rides the
## StrataLink `boot` verb as an additive `edges=` field — PaneBoot.read
## (Strata host) walks tokens and skips names it doesn't know, so older
## hosts see exactly the boot line they saw yesterday, and the host's own
## EventSink (the one events.ndjson appender) can start recording the
## phase table without a protocol bump.
func edges_token() -> String:
	var parts := PackedStringArray()
	for e in _edges:
		parts.append("%s:%d" % [e["phase"], e["ms"]])
	return ",".join(parts)


## Arm the WINDOWED phases. Called once by world_streamer at first_frame_rendered
## (the earliest tick an honest near-ground mesh exists). Under --headless there
## is no GPU present, so the two present-derived rows (first_present, steady_frame)
## stay absent — honest, not a hole; only the frame_post_draw hook and the
## per-frame watcher are skipped, leaving the compute table exactly as it was.
func arm_windowed() -> void:
	if _windowed_armed:
		return
	_windowed_armed = true
	if DisplayServer.get_name() == "headless":
		return
	# first_present: the next real frame pushed to the display now that an honest
	# mesh exists. frame_post_draw fires once after that present, then unhooks.
	RenderingServer.frame_post_draw.connect(_on_first_present, CONNECT_ONE_SHOT)
	set_process(true)  # steady-frame watcher; disables itself once it marks


func _on_first_present() -> void:
	mark("first_present")


## Steady-frame watcher — runs ONLY after a windowed arm, and disables itself the
## moment it marks. STEADY_RUN consecutive frames at/under STEADY_MS means the
## boot-time hitching (shader compiles, mesh uploads) has subsided: a warm proxy
## from frame cadence (GDScript exposes no shader-compile completion signal).
func _process(delta: float) -> void:
	if _fired.has("steady_frame"):
		set_process(false)
		return
	if not _fired.has("first_present"):
		return  # wait for pixels on screen before timing warmth
	if delta * 1000.0 <= STEADY_MS:
		_steady_run += 1
		if _steady_run >= STEADY_RUN:
			mark("steady_frame")
			set_process(false)
	else:
		_steady_run = 0


## Tally one near-ring cell mesh landing on the main thread (the streamer calls
## this from _finish_terrain for a near cell during the boot window). Cheap
## counter + first/last timestamps — NOT a [boot] row per cell (that would flood
## the table); the summary lands once at world_live via note_meshed().
func note_wave() -> void:
	if _fired.has("world_live"):
		return
	_wave_count += 1
	var ms := Time.get_ticks_msec() - _t0
	if _wave_first_ms < 0:
		_wave_first_ms = ms
	_wave_last_ms = ms


## Close the near-ring meshing tally. Called by the streamer at the world_live
## settle: the LAST near-cell mesh time (_wave_last_ms) is the near_ring_meshed
## edge — retroactive but honest (we know the last wave only once the ring is
## done). The wave count + span rides its own bracketed log line for the ledger.
func note_meshed() -> void:
	if _fired.has("near_ring_meshed") or _wave_count == 0:
		return
	_fired["near_ring_meshed"] = true
	_edges.append({"phase": "near_ring_meshed", "ms": _wave_last_ms})
	print("[boot] near_ring_meshed ms=%d" % _wave_last_ms)
	print("[boot] mesh_waves cells=%d first=%d last=%d span=%d" % [
		_wave_count, _wave_first_ms, _wave_last_ms, _wave_last_ms - _wave_first_ms])
