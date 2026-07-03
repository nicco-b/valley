#!/bin/sh
# World soak: run the simulation 30 game-days headless, twice, and demand
# (a) every invariant holds, (b) both runs produce the SAME fingerprint —
# determinism is a build requirement, not an aspiration. Exits nonzero on
# any failure. Slower than test.sh; run before merging sim work.
cd "$(dirname "$0")/.." || exit 1

echo "== import (refresh class cache) =="
godot --headless --import >/dev/null 2>&1

run_soak() {
	godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1
}

echo "== soak run 1 =="
OUT1=$(run_soak)
echo "$OUT1" | grep -E "SOAK"
echo "$OUT1" | grep -q "SOAK PASS" || exit 1

echo "== soak run 2 (determinism) =="
OUT2=$(run_soak)
echo "$OUT2" | grep -E "SOAK PASS|SOAK FAIL|INVARIANT"
echo "$OUT2" | grep -q "SOAK PASS" || exit 1

FP1=$(echo "$OUT1" | grep "SOAK FINGERPRINT" | tail -1)
FP2=$(echo "$OUT2" | grep "SOAK FINGERPRINT" | tail -1)
if [ "$FP1" != "$FP2" ] || [ -z "$FP1" ]; then
	echo "SOAK FAIL: fingerprints differ — the world is not deterministic"
	echo "  run1: $FP1"
	echo "  run2: $FP2"
	exit 1
fi
echo "soak clean: deterministic across runs ($FP1)"
