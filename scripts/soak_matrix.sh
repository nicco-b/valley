#!/bin/sh
# The CONTOUR SUBSTRATE six-run soak matrix (Mission D4 opened it for flora; this
# wave — E1d — extends the persistent HELD WORLD to the other six Contour systems).
# Boot tests/soak.tscn SIX times on ONE binary/tree and demand:
#   (a) all SIX SOAK FINGERPRINTs identical — the GDScript twin, the copy-path
#       Contour bridge (STRATA_CONTOUR=1), and the PERSISTENT HELD WORLD path
#       (STRATA_CONTOUR=1 STRATA_CONTOUR_HELD=1) produce a bit-for-bit identical
#       30-day world (never a pinned value — same tree, same binary, same seed);
#   (b) EVERY system's engagement counters EARN it, per system:
#       - flora / weather / climate / agent / hydrology / sand: calls 0 on both
#         flag-OFF runs, >0 on all four flag-ON runs; held_ticks 0 everywhere
#         EXCEPT the two +HELD runs, where it climbs >0 — proof the in-place held
#         path actually ran, NOT a silent copy-path fallback.
#       - story: pure-function VM calls (no §6 world to hold), so it earns the
#         SAME calls>0-on-flag-ON / 0-on-flag-OFF proof, but no held_ticks column.
# The six states: 2× flag-OFF, 2× STRATA_CONTOUR=1, 2× +STRATA_CONTOUR_HELD=1.
# NEVER a live editor port — STRATA_LINK_PORT pinned off the reserved set.
cd "$(dirname "$0")/.." || exit 1

export STRATA_LINK_PORT="${STRATA_LINK_PORT:-47091}"

# The systems under proof: name;grep-tag;calls-field;has-held-world(1/0). The tag
# uniquely selects that system's SOAK CONTOUR line (flora keeps the original
# "SOAK CONTOUR mode" prefix; every other system has a "SOAK CONTOUR-<SYS>" one).
SYS_FILE=$(mktemp)
cat > "$SYS_FILE" <<'EOF'
flora;SOAK CONTOUR mode;flora_ticks;1
weather;SOAK CONTOUR-WEATHER;weather_ticks;1
climate;SOAK CONTOUR-CLIMATE;climate_ticks;1
story;SOAK CONTOUR-STORY;story_calls;0
agent;SOAK CONTOUR-AGENT;agent_ticks;1
hydrology;SOAK CONTOUR-HYDROLOGY;hydrology_ticks;1
sand;SOAK CONTOUR-SAND;sand_ticks;1
EOF

echo "== import (refresh class cache) =="
godot --headless --import >/dev/null 2>&1

run() { # $1 = "off" | "contour" | "held"
	case "$1" in
		off)     godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1 ;;
		contour) STRATA_CONTOUR=1 godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1 ;;
		held)    STRATA_CONTOUR=1 STRATA_CONTOUR_HELD=1 godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1 ;;
	esac
}

# Extract a numeric "<field>=<n>" from the one SOAK line carrying <tag>. Empty
# when the tag/field is absent (a missing system line => a loud FAIL below).
field() { # $1=output  $2=tag  $3=field
	printf '%s\n' "$1" | grep "$2" | sed -n "s/.*$3=\([0-9]*\).*/\1/p" | head -1
}

FAIL=0
FPS=""
i=0
for STATE in off off contour contour held held; do
	i=$((i + 1))
	OUT=$(run "$STATE")
	FP=$(printf '%s\n' "$OUT" | grep "SOAK FINGERPRINT" | sed -n 's/.*SOAK FINGERPRINT \([0-9-]*\).*/\1/p')
	PASS=$(printf '%s\n' "$OUT" | grep -c "SOAK PASS")
	if [ "$PASS" != "1" ] || [ -z "$FP" ]; then
		echo "  run $i [$STATE]: FAIL — did not pass / no fingerprint"; FAIL=1; continue
	fi
	FPS="$FPS $FP"
	# Per-system engagement rules for this state.
	LINE="  run $i [$STATE]: fp=$FP"
	while IFS=';' read -r NAME TAG CALLF HASHELD; do
		[ -z "$NAME" ] && continue
		CALLS=$(field "$OUT" "$TAG" "$CALLF")
		LINE="$LINE  $NAME.calls=${CALLS:-?}"
		HELD=""
		if [ "$HASHELD" = "1" ]; then
			HELD=$(field "$OUT" "$TAG" "held_ticks")
			LINE="$LINE/held=${HELD:-?}"
		fi
		case "$STATE" in
			off)
				[ "$CALLS" = "0" ] || { echo "  FAIL: flag-OFF $NAME engaged (calls=$CALLS)"; FAIL=1; }
				if [ "$HASHELD" = "1" ]; then
					[ "$HELD" = "0" ] || { echo "  FAIL: flag-OFF $NAME held (held_ticks=$HELD)"; FAIL=1; }
				fi ;;
			contour)
				{ [ -n "$CALLS" ] && [ "$CALLS" != "0" ]; } || { echo "  FAIL: STRATA_CONTOUR did not route $NAME (calls=$CALLS)"; FAIL=1; }
				if [ "$HASHELD" = "1" ]; then
					[ "$HELD" = "0" ] || { echo "  FAIL: copy path ran $NAME held tick (held_ticks=$HELD)"; FAIL=1; }
				fi ;;
			held)
				{ [ -n "$CALLS" ] && [ "$CALLS" != "0" ]; } || { echo "  FAIL: +HELD did not route $NAME (calls=$CALLS)"; FAIL=1; }
				if [ "$HASHELD" = "1" ]; then
					{ [ -n "$HELD" ] && [ "$HELD" != "0" ]; } || { echo "  FAIL: +HELD did not run $NAME in-place tick (held_ticks=$HELD)"; FAIL=1; }
				fi ;;
		esac
	done < "$SYS_FILE"
	echo "$LINE"
done
rm -f "$SYS_FILE"

# All six fingerprints identical.
FIRST=$(echo $FPS | cut -d' ' -f1)
for FP in $FPS; do
	[ "$FP" = "$FIRST" ] || { echo "SOAK-MATRIX FAIL: fingerprints differ ($FPS)"; FAIL=1; break; }
done

if [ "$FAIL" = "0" ]; then
	echo "SOAK-MATRIX PASS: six identical fingerprints ($FIRST); every system's held_ticks earned on the +HELD runs (story via calls, no world to hold)"
	exit 0
else
	echo "SOAK-MATRIX FAIL"
	exit 1
fi
