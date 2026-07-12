#!/bin/sh
# Unit tests + smoke test. Exits nonzero on failure.
cd "$(dirname "$0")/.." || exit 1

echo "== import (refresh class cache) =="
godot --headless --import >/dev/null 2>&1

echo "== unit tests =="
godot --headless -s tests/run_tests.gd || exit 1

echo "== scene tests (autoload context) =="
# --quit-after backstop: if the test script itself fails to parse, the
# scene runs empty and never quits — without this the suite hangs forever.
# Success is the PASS line, not the exit code (quit-after exits 0).
# STRATA_CLOCK_PIN freezes the scene-test world's clock (and thereby weather /
# tide) at a fixed hour — without it the world boots at real wall time and the
# click-together socket gate flakes ~1 in 3 under whatever weather that draws.
# Env-gated + test-only: unset everywhere else (the soak included), so shipping
# behaviour and the determinism fingerprint are untouched (game_clock.gd).
SCENE_OUT=$(STRATA_CLOCK_PIN=9.0 godot --headless --quit-after 2000 res://tests/scene_tests.tscn 2>&1)
echo "$SCENE_OUT" | grep -E "PASS|FAIL|SCRIPT ERROR"
echo "$SCENE_OUT" | grep -q "SCRIPT ERROR" && exit 1
echo "$SCENE_OUT" | grep -q "SCENE-TESTS PASS" || exit 1

echo "== save-load gate (the load-time covenant the soak can't see) =="
# SaveMigration runs at LOAD (save_manager.load_into_world / restore_anchor),
# never on the sim tick — so the soak's fingerprint is structurally blind to it.
# This dedicated gate loads every real fixture through the real save path and
# proves the hatch (_migrate_gd) == flag-ON (the native Contour VM) byte-for-byte
# on the result dict, with the refusal sentences verbatim. Run BOTH ways: POST-
# FLIP the escape hatch STRATA_CONTOUR=0 must PASS on the GDScript twin;
# STRATA_CONTOUR=1 must PASS *and* route the VM (mode 2, no silent fallback)
# wherever the native kernel is live — the gate fails LOUDLY itself if the flag is
# set with a live kernel but does not engage. (Unset would now ENGAGE by default;
# we drive =0 here so the twin half is exercised explicitly, mirroring the flip.)
# Same PASS-line backstop as the scene tests (quit-after exits 0 regardless).
GATE_OFF=$(STRATA_CONTOUR=0 godot --headless --quit-after 2000 res://tests/save_load_gate.tscn 2>&1)
echo "$GATE_OFF" | grep -E "SAVE-LOAD-GATE|  FAIL:"
echo "$GATE_OFF" | grep -q "SCRIPT ERROR" && exit 1
echo "$GATE_OFF" | grep -q "SAVE-LOAD-GATE PASS" || exit 1
echo "$GATE_OFF" | grep -q "SAVE-LOAD-GATE OFF" \
	|| { echo "SAVE-LOAD-GATE FAIL: flag-off run did not report the GDScript twin"; exit 1; }
GATE_ON=$(STRATA_CONTOUR=1 godot --headless --quit-after 2000 res://tests/save_load_gate.tscn 2>&1)
echo "$GATE_ON" | grep -E "SAVE-LOAD-GATE|  FAIL:"
echo "$GATE_ON" | grep -q "SCRIPT ERROR" && exit 1
echo "$GATE_ON" | grep -q "SAVE-LOAD-GATE PASS" || exit 1
if echo "$GATE_ON" | grep -q "SAVE-LOAD-GATE ROUTED"; then
	echo "  save-load gate: STRATA_CONTOUR=1 routed the VM, byte-identical to the flag-off twin"
else
	echo "  save-load gate: no native kernel on this host — GDScript twin only (both runs PASS)"
fi

echo "== held-snapshot gate (substrate Rung 3: save-via-held == save-via-mirror) =="
# F3 (docs/SUBSTRATE.md §3): under STRATA_CONTOUR_HELD=1 a save SOURCES each held
# SINGLETON's OWNED keys from its held world (Contour.world_snapshot) instead of
# the WorldState mirror — proven BYTE-FOR-BYTE identical to the mirror at the
# bridge level over every real singleton module, and pins the MULTIPLEXED-refuses
# and clock-not-sourced contract facts the soak can't see. (The soak's own
# +HELD runs prove the same equality on the real 30-day play state.) SKIPs+PASSes
# where the native kernel is absent. Same PASS-line backstop as the other gates.
HELD_OUT=$(STRATA_CONTOUR=1 STRATA_CONTOUR_HELD=1 godot --headless --quit-after 2000 res://tests/held_snapshot_gate.tscn 2>&1)
echo "$HELD_OUT" | grep -E "HELD-SNAPSHOT-GATE|  FAIL:"
echo "$HELD_OUT" | grep -q "SCRIPT ERROR" && exit 1
echo "$HELD_OUT" | grep -q "HELD-SNAPSHOT-GATE PASS" || exit 1

echo "== restore-into-held gate (substrate Rung 3: a load restores INTO the held world) =="
# G1 (docs/SUBSTRATE.md §2, Rung 3's other half): under STRATA_CONTOUR_HELD=1 a LOAD
# restores the save INTO each held world (reset_held -> world_create seeded from the
# restored mirror), so a timeline resumes from the loaded snapshot, not the pre-load
# trajectory. That path runs at LOAD, before the world exists — the soak is BLIND to
# it, like save_migration. This gate proves the contract at the bridge level over
# every real singleton module + re-pins the migration engagement counter. SKIPs (held
# checks) + PASSes where the native kernel is absent. Same PASS-line backstop.
RESTORE_OUT=$(STRATA_CONTOUR=1 STRATA_CONTOUR_HELD=1 godot --headless --quit-after 2000 res://tests/restore_held_gate.tscn 2>&1)
echo "$RESTORE_OUT" | grep -E "RESTORE-HELD-GATE|  FAIL:"
echo "$RESTORE_OUT" | grep -q "SCRIPT ERROR" && exit 1
echo "$RESTORE_OUT" | grep -q "RESTORE-HELD-GATE PASS" || exit 1

echo "== quest harness + lint (the Campfire) =="
# The Q2 robustness spine (DESIGN_QUESTS §10): the quest linter over
# data/quests + data/threads, then every tests/quests/*.test.json driven
# through the REAL Story machinery headless. Same backstop pattern as
# the scene tests: success is the PASS line, not the exit code.
QUEST_OUT=$(godot --headless --quit-after 4000 res://tests/quest_harness.tscn 2>&1)
echo "$QUEST_OUT" | grep -E "QUEST-HARNESS|LINT|FAIL|SCRIPT ERROR"
echo "$QUEST_OUT" | grep -q "SCRIPT ERROR" && exit 1
echo "$QUEST_OUT" | grep -q "QUEST-HARNESS PASS" || exit 1

echo "== character lint (the cast sheet, CREATION_KIT_REVIEW_V2 #3) =="
# CharacterLint over data/characters (content-empty -> clean) + the shipped
# example fixture (tests/fixtures/characters/mara.json, full + sound), then
# deliberately-broken records that MUST bite with the game's own refusal
# sentences, then the example SPAWNS a living mind (validate_character gates
# spawn_character). Same PASS-line backstop as the scene tests (quit-after
# exits 0 regardless of the assertion result).
CHAR_OUT=$(godot --headless --quit-after 2000 res://tests/character_lint.tscn 2>&1)
echo "$CHAR_OUT" | grep -E "CHARACTER-LINT|  FAIL:|  LINT"
echo "$CHAR_OUT" | grep -q "SCRIPT ERROR" && exit 1
echo "$CHAR_OUT" | grep -q "CHARACTER-LINT PASS" || exit 1

echo "== framework manifest lint (the fence, PLAN_FRAMEWORK FW5) =="
# Static text scan over every file framework.json lists: no preloading
# res://assets/ (content), no naming a data/ record's id, no writing an
# un-namespaced valley.* shader-global key, no direct OS.is_debug_build()
# gate, and (TEARDOWN-REAP LAW) no WorkerThreadPool/Thread task without a
# matching _exit_tree reap — four crashes earned that last one. No
# scene/autoloads needed — same `godot -s` shape as the unit-tests pass
# above. Known pre-FW5 hits ride in ALLOWLIST (branch-pending or residue,
# see tests/framework_lint.gd); anything new fails for real.
godot --headless -s tests/framework_lint.gd || exit 1

echo "== determinism trap (fork engine only) =="
# The fork's Engine.set_deterministic_section arms a trap around the sim tick
# (game_clock.gd advance_hours). determinism_trap_probe plants an unseeded
# randf() and a raw wall-clock read in a sim_advance handler; the trap must
# NAME each one with a GDScript backtrace. Stock Godot has no trap → the probe
# prints SKIP and this stanza passes. Assertion is on captured stderr, exactly
# like the scene tests. (Innocence — the whole sim clean under the armed trap
# — is the rest of this script + soak.sh going green.)
DET_OUT=$(godot --headless --quit-after 400 res://tests/determinism_trap_probe.tscn 2>&1)
if echo "$DET_OUT" | grep -q "DET-TRAP SKIP"; then
	echo "  SKIP (stock engine — no determinism trap)"
elif echo "$DET_OUT" | grep -q "DET-TRAP PASS" \
		&& echo "$DET_OUT" | grep -q "Determinism trap: randf() draws from the global unseeded RNG" \
		&& echo "$DET_OUT" | grep -q "Determinism trap: Time.get_unix_time_from_system() reads the real-world wall clock" \
		&& echo "$DET_OUT" | grep -q "sim_advance_hours (res://tests/determinism_trap_probe.gd"; then
	echo "  trap named both crimes with a backtrace"
else
	echo "$DET_OUT"
	echo "DET-TRAP FAIL: trap did not name the planted crimes"
	exit 1
fi

# Filter: engine banners, benign exit-time audio warnings, and our own
# "[system]" log lines (anything bracket-prefixed is intentional logging).
FILTER="^Godot Engine|^Dummy|^\[|leaked|still in use|object.cpp|resource.cpp"

echo "== smoke test: title boot (120 frames) =="
OUT=$(godot --headless --quit-after 120 2>&1 | grep -vE "$FILTER")
if [ -n "$OUT" ]; then
	echo "$OUT"
	echo "SMOKE FAIL (title): unexpected output above"
	exit 1
fi

echo "== smoke test: world (240 frames) =="
# The world scene lives at a project-chosen path: valley's own
# game/world/valley.tscn, a Strata-scaffolded game's main.tscn. Smoke
# whichever THIS project ships (the SKIP-when-absent pattern the tests
# use — the framework file rides every game unchanged).
for cand in game/world/valley.tscn main.tscn; do
	[ -f "$cand" ] || continue
	RAW=$(godot --headless --quit-after 240 "res://$cand" 2>&1)
	OUT=$(echo "$RAW" | grep -vE "$FILTER")
	if [ -n "$OUT" ]; then
		echo "$OUT"
		echo "SMOKE FAIL (world $cand): unexpected output above"
		exit 1
	fi
	# Boot phase table (BootClock, 2026-07-12 boot forensics): one grep-able
	# line per phase edge this boot hit, in the order they landed — engine_up,
	# kernel_live, catchments_done, bathymetry_done, first_frame_rendered,
	# near_ring_settled, world_live. No budget/threshold assertions here on
	# purpose (deliberately deferred to a later taste pass once real numbers
	# exist) — this just prints the table.
	echo "-- boot phase table --"
	echo "$RAW" | grep -E "^\[boot\] "
	break
done
echo "smoke clean"
