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
OUT=$(godot --headless --quit-after 240 res://game/world/valley.tscn 2>&1 | grep -vE "$FILTER")
if [ -n "$OUT" ]; then
	echo "$OUT"
	echo "SMOKE FAIL (world): unexpected output above"
	exit 1
fi
echo "smoke clean"
