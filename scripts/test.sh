#!/bin/sh
# Unit tests + smoke test. Exits nonzero on failure.
cd "$(dirname "$0")/.." || exit 1

echo "== import (refresh class cache) =="
godot --headless --import >/dev/null 2>&1

echo "== unit tests =="
godot --headless -s tests/run_tests.gd || exit 1

echo "== scene tests (autoload context) =="
godot --headless res://tests/scene_tests.tscn 2>&1 | grep -E "PASS|FAIL"
godot --headless res://tests/scene_tests.tscn >/dev/null 2>&1 || exit 1

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
