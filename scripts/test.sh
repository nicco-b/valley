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
SCENE_OUT=$(godot --headless --quit-after 2000 res://tests/scene_tests.tscn 2>&1)
echo "$SCENE_OUT" | grep -E "PASS|FAIL|SCRIPT ERROR"
echo "$SCENE_OUT" | grep -q "SCRIPT ERROR" && exit 1
echo "$SCENE_OUT" | grep -q "SCENE-TESTS PASS" || exit 1

echo "== quest harness + lint (the Campfire) =="
# The Q2 robustness spine (DESIGN_QUESTS §10): the quest linter over
# data/quests + data/threads, then every tests/quests/*.test.json driven
# through the REAL Story machinery headless. Same backstop pattern as
# the scene tests: success is the PASS line, not the exit code.
QUEST_OUT=$(godot --headless --quit-after 4000 res://tests/quest_harness.tscn 2>&1)
echo "$QUEST_OUT" | grep -E "QUEST-HARNESS|LINT|FAIL|SCRIPT ERROR"
echo "$QUEST_OUT" | grep -q "SCRIPT ERROR" && exit 1
echo "$QUEST_OUT" | grep -q "QUEST-HARNESS PASS" || exit 1

echo "== framework manifest lint (the fence, PLAN_FRAMEWORK FW5) =="
# Static text scan over every file framework.json lists: no preloading
# res://assets/ (content), no naming a data/ record's id, no writing an
# un-namespaced valley.* shader-global key. No scene/autoloads needed —
# same `godot -s` shape as the unit-tests pass above. Known pre-FW5 hits
# ride in ALLOWLIST (branch-pending or residue, see tests/framework_lint.gd);
# anything new fails for real.
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
	OUT=$(godot --headless --quit-after 240 "res://$cand" 2>&1 | grep -vE "$FILTER")
	if [ -n "$OUT" ]; then
		echo "$OUT"
		echo "SMOKE FAIL (world $cand): unexpected output above"
		exit 1
	fi
	break
done
echo "smoke clean"
