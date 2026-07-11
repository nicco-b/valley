#!/bin/sh
# The CONTOUR SUBSTRATE six-run soak matrix (Mission D4, substrate ladder Rung 2).
# Boot tests/soak.tscn SIX times on ONE binary/tree and demand:
#   (a) all SIX SOAK FINGERPRINTs identical — the GDScript twin, the copy-path
#       Contour bridge (STRATA_CONTOUR=1), and the PERSISTENT HELD WORLD path
#       (STRATA_CONTOUR=1 STRATA_CONTOUR_HELD=1) produce a bit-for-bit identical
#       30-day world (never a pinned value — same tree, same binary, same seed);
#   (b) the engagement counters EARN it — flora_ticks 0 on both flag-OFF runs,
#       >0 on all four flag-ON runs; held_ticks 0 everywhere EXCEPT the two
#       +HELD runs, where it climbs to 720 (24h × 30d) — proof the in-place
#       held path actually ran, NOT a silent copy-path fallback.
# The six states: 2× flag-OFF, 2× STRATA_CONTOUR=1, 2× +STRATA_CONTOUR_HELD=1.
# NEVER a live editor port — STRATA_LINK_PORT pinned off the reserved set.
cd "$(dirname "$0")/.." || exit 1

export STRATA_LINK_PORT="${STRATA_LINK_PORT:-47091}"

echo "== import (refresh class cache) =="
godot --headless --import >/dev/null 2>&1

run() { # $1 = "off" | "contour" | "held"
	case "$1" in
		off)     godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1 ;;
		contour) STRATA_CONTOUR=1 godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1 ;;
		held)    STRATA_CONTOUR=1 STRATA_CONTOUR_HELD=1 godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1 ;;
	esac
}

FAIL=0
FPS=""
i=0
for STATE in off off contour contour held held; do
	i=$((i + 1))
	OUT=$(run "$STATE")
	FP=$(echo "$OUT" | grep "SOAK FINGERPRINT" | sed -n 's/.*SOAK FINGERPRINT \([0-9-]*\).*/\1/p')
	FLORA=$(echo "$OUT" | grep "SOAK CONTOUR mode" | grep "flora_ticks" | sed -n 's/.*flora_ticks=\([0-9]*\).*/\1/p')
	HELD=$(echo "$OUT" | grep "SOAK CONTOUR mode" | grep "held_ticks" | sed -n 's/.*held_ticks=\([0-9]*\).*/\1/p')
	PASS=$(echo "$OUT" | grep -c "SOAK PASS")
	echo "  run $i [$STATE]: fp=$FP flora_ticks=$FLORA held_ticks=$HELD pass=$PASS"
	if [ "$PASS" != "1" ] || [ -z "$FP" ]; then
		echo "  FAIL: run $i ($STATE) did not pass / no fingerprint"; FAIL=1; continue
	fi
	FPS="$FPS $FP"
	# Engagement rules per state.
	case "$STATE" in
		off)
			[ "$FLORA" = "0" ] || { echo "  FAIL: flag-OFF engaged ($FLORA flora_ticks)"; FAIL=1; }
			[ "$HELD" = "0" ]  || { echo "  FAIL: flag-OFF held ($HELD held_ticks)"; FAIL=1; } ;;
		contour)
			[ -n "$FLORA" ] && [ "$FLORA" != "0" ] || { echo "  FAIL: STRATA_CONTOUR did not route ($FLORA flora_ticks)"; FAIL=1; }
			[ "$HELD" = "0" ] || { echo "  FAIL: copy path ran the held tick ($HELD held_ticks)"; FAIL=1; } ;;
		held)
			[ -n "$FLORA" ] && [ "$FLORA" != "0" ] || { echo "  FAIL: +HELD did not route flora ($FLORA)"; FAIL=1; }
			[ -n "$HELD" ] && [ "$HELD" != "0" ]   || { echo "  FAIL: +HELD did not run the in-place tick ($HELD held_ticks)"; FAIL=1; } ;;
	esac
done

# All six fingerprints identical.
FIRST=$(echo $FPS | cut -d' ' -f1)
for FP in $FPS; do
	[ "$FP" = "$FIRST" ] || { echo "SOAK-MATRIX FAIL: fingerprints differ ($FPS)"; FAIL=1; break; }
done

if [ "$FAIL" = "0" ]; then
	echo "SOAK-MATRIX PASS: six identical fingerprints ($FIRST); held_ticks earned on the +HELD runs"
	exit 0
else
	echo "SOAK-MATRIX FAIL"
	exit 1
fi
