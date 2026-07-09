class_name DevMode
## The ONE dev-gate truth (PLAN_SHIP §2). The whole Strata↔pane control
## plane — the link, the Toolkit, hot reload, the debug keys — used to gate
## on OS.is_debug_build() directly, which made "dev tools on" an accident of
## the engine's build flavor. This makes the signal EXPLICIT while preserving
## today's behavior at every launch path.
##
## Static-only — no autoload, no node. Gate sites call DevMode.active().
## compute() is the pure decision (unit-testable headless, zero engine
## state); active() is the cached live reader over the real engine signals.
##
## Precedence, first hit wins:
##   1. "strata_no_dev" feature  → OFF  (the ship preset's kill switch —
##      beats everything, so a shipped binary cannot be re-armed)
##   2. "strata_dev" feature     → ON   (explicit opt-in per export preset)
##   3. "--strata-dev" user arg  → ON   (Strata's pane/Play launches;
##      also the editor-run escape hatch)
##   4. OS.is_debug_build()      → legacy default (editor + template_debug
##      stay dev; template_release stays clean) — behavior-preserving.
##
## (OS.has_feature is the documented carrier for export-preset
## custom_features — the Godot-native mechanism, no engine change, no fork
## patch. The FW5 manifest lint forbids OS.is_debug_build() in every other
## framework file: DevMode is the one door.)


static func compute(features: PackedStringArray,
		user_args: PackedStringArray, debug_build: bool) -> bool:
	if features.has("strata_no_dev"): return false
	if features.has("strata_dev"): return true
	if user_args.has("--strata-dev"): return true
	return debug_build


static var _cached := -1  # -1 unset / 0 off / 1 on


static func active() -> bool:
	if _cached == -1:
		var feats := PackedStringArray()
		for f in ["strata_no_dev", "strata_dev"]:
			if OS.has_feature(f): feats.append(f)
		_cached = 1 if compute(feats, OS.get_cmdline_user_args(),
				OS.is_debug_build()) else 0
	return _cached == 1
