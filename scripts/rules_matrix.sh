#!/bin/sh
# The P1 RULES TRIO four-run determinism matrix (Mission D1b — items/skills/
# budget). For EACH file, boot tests/rules_matrix.tscn four times on ONE binary
# (POST-FLIP: 2× off-hatch STRATA_CONTOUR=0 + 2× =1 — unset now defaults ON, so
# the "off" runs drive the escape hatch explicitly) and demand:
#   (a) all four FINGERPRINTS identical — the routed Contour rules == the GDScript
#       twin, bit-for-bit (items/skills over fingerprinted player.inventory / the
#       skill stat mirror; budget over its read-only grade output);
#   (b) the ENGAGEMENT COUNTER earns it — 0 on both flag-OFF runs, >0 on both
#       flag-ON runs (the flag-ON runs actually routed; NO SILENT FALLBACK).
# Run PER FILE so a failure names its file. Exits nonzero on any mismatch.
cd "$(dirname "$0")/.." || exit 1

echo "== import (refresh class cache) =="
godot --headless --import >/dev/null 2>&1

run() { # $1 = file, $2 = flag (0|1)
	if [ "$2" = "1" ]; then
		STRATA_CONTOUR=1 D1B_MATRIX_FILE="$1" godot --headless --quit-after 8000 res://tests/rules_matrix.tscn 2>&1
	else
		STRATA_CONTOUR=0 D1B_MATRIX_FILE="$1" godot --headless --quit-after 8000 res://tests/rules_matrix.tscn 2>&1
	fi
}

FAIL=0
for FILE in items skills budget; do
	echo "== matrix: $FILE =="
	L_OFF1=$(run "$FILE" 0 | grep "D1B-MATRIX $FILE ")
	L_OFF2=$(run "$FILE" 0 | grep "D1B-MATRIX $FILE ")
	L_ON1=$(run "$FILE" 1 | grep "D1B-MATRIX $FILE ")
	L_ON2=$(run "$FILE" 1 | grep "D1B-MATRIX $FILE ")
	for L in "$L_OFF1" "$L_OFF2" "$L_ON1" "$L_ON2"; do
		if [ -z "$L" ]; then
			echo "  $FILE FAIL: a run produced no matrix line (crash / refusal?)"; FAIL=1; continue 2
		fi
		echo "  $L"
	done
	FP_OFF1=$(echo "$L_OFF1" | sed -n 's/.*fp=\([-0-9]*\).*/\1/p')
	FP_OFF2=$(echo "$L_OFF2" | sed -n 's/.*fp=\([-0-9]*\).*/\1/p')
	FP_ON1=$(echo "$L_ON1" | sed -n 's/.*fp=\([-0-9]*\).*/\1/p')
	FP_ON2=$(echo "$L_ON2" | sed -n 's/.*fp=\([-0-9]*\).*/\1/p')
	C_OFF1=$(echo "$L_OFF1" | sed -n 's/.*calls=\([0-9]*\).*/\1/p')
	C_ON1=$(echo "$L_ON1" | sed -n 's/.*calls=\([0-9]*\).*/\1/p')
	C_ON2=$(echo "$L_ON2" | sed -n 's/.*calls=\([0-9]*\).*/\1/p')
	if [ "$FP_OFF1" != "$FP_OFF2" ] || [ "$FP_OFF1" != "$FP_ON1" ] || [ "$FP_OFF1" != "$FP_ON2" ]; then
		echo "  $FILE FAIL: fingerprints differ (off=$FP_OFF1/$FP_OFF2 on=$FP_ON1/$FP_ON2) — routed rule != twin"; FAIL=1; continue
	fi
	if [ "$C_OFF1" != "0" ]; then
		echo "  $FILE FAIL: flag-OFF engaged ($C_OFF1 calls) — should be pure GDScript"; FAIL=1; continue
	fi
	if [ -z "$C_ON1" ] || [ "$C_ON1" = "0" ] || [ "$C_ON2" = "0" ]; then
		echo "  $FILE FAIL: flag-ON did not route (calls on1=$C_ON1 on2=$C_ON2) — counter must earn it"; FAIL=1; continue
	fi
	echo "  $FILE OK: four fingerprints == $FP_OFF1, engaged flag-ON ($C_ON1 Contour calls) vs 0 flag-OFF"
done

if [ "$FAIL" = "0" ]; then echo "RULES-MATRIX PASS (items/skills/budget: identical fingerprints, counters earned)"; exit 0
else echo "RULES-MATRIX FAIL"; exit 1; fi
