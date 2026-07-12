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


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
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
