#!/bin/sh
# Unit tests + smoke test. Exits nonzero on failure.
cd "$(dirname "$0")/.." || exit 1

echo "== import (refresh class cache) =="
godot --headless --import >/dev/null 2>&1

echo "== unit tests =="
godot --headless -s tests/run_tests.gd || exit 1

echo "== smoke test (240 frames) =="
OUT=$(godot --headless --quit-after 240 2>&1 | grep -vE "^Godot Engine|^Dummy|^\[world\]|^\[save\]|leaked|still in use|object.cpp|resource.cpp")
if [ -n "$OUT" ]; then
	echo "$OUT"
	echo "SMOKE FAIL: unexpected output above"
	exit 1
fi
echo "smoke clean"
