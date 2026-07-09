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
