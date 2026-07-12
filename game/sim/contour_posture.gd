class_name ContourPosture
extends RefCounted
## THE POSTURE RESOLVER (landing-round DEFAULT FLIP, ruled 2026-07-12): the ONE
## place the runtime reads the contour posture env hatches. Every consumer —
## the world files' _contour_held caches, WorldState's per-key mirror flip,
## SaveManager's covenant guards, and soak.gd's posture decider — routes
## through these two statics so the DEFAULTS live in exactly one file.
##
## RULED DEFAULTS (flipped this round — before it, unset meant held OFF and
## mirror ON):
##   * unset STRATA_CONTOUR_HELD   => HELD ON   (the bridge-owned held world is
##     the sim-tier truth by default)
##   * unset STRATA_CONTOUR_MIRROR => MIRROR OFF (eligible SINGLETON held-owned
##     keys read through to the held world; no second copy is kept)
##
## LEGACY HATCHES (kept both directions, spelled exactly):
##   * STRATA_CONTOUR_HELD=0   => held OFF  (the pre-flip copy path)
##   * STRATA_CONTOUR_MIRROR=1 => mirror ON (the pre-flip per-key mirror copies)
## Any other value (including "1" for HELD / "0" for MIRROR) matches the new
## defaults, so existing =1/=0 spellings from the soak era stay valid.
##
## Statics, read fresh per call (no cached posture here): callers that cache —
## the world files snapshot _contour_held at engage — keep their own lifecycle;
## the resolver itself never memoizes, so a test that sets the env before boot
## always sees the posture it asked for.


## Is the held world engaged? Unset => TRUE (the ruled default). Only the
## explicit legacy hatch STRATA_CONTOUR_HELD=0 turns it off.
static func held_enabled() -> bool:
	return OS.get_environment("STRATA_CONTOUR_HELD") != "0"


## Is the per-key mirror RETIRED for eligible keys (read-through active)?
## Unset => TRUE (the ruled default: no mirror copy). Only the explicit legacy
## hatch STRATA_CONTOUR_MIRROR=1 restores the mirror copies. Note the flip only
## BITES when the held world is live — under held-off every key falls to the
## plain mirror fast path regardless (see world_state.gd §2a).
static func mirror_flipped() -> bool:
	return OS.get_environment("STRATA_CONTOUR_MIRROR") != "1"
