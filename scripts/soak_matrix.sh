#!/bin/sh
# The CONTOUR SUBSTRATE six-run soak matrix (Mission D4 opened it for flora; E1d
# extended the persistent HELD WORLD to the other six systems; F1 re-proves it
# under THE DEFAULT FLIP — STRATA_CONTOUR now defaults ON, so the DEFAULT runs
# ENGAGE and the escape hatch STRATA_CONTOUR=0 is the "off" case).
# Boot tests/soak.tscn SIX times on ONE binary/tree and demand:
#   (a) all SIX SOAK FINGERPRINTs identical — the GDScript twin (the =0 hatch),
#       the copy-path Contour bridge (DEFAULT-ON), and the PERSISTENT HELD WORLD
#       path (default-on + STRATA_CONTOUR_HELD=1) produce a bit-for-bit identical
#       30-day world (never a pinned value — same tree, same binary, same seed);
#   (b) EVERY system's engagement counters EARN it, per system:
#       - flora / weather / climate / agent / hydrology / sand: calls 0 on both
#         hatch (=0) runs, >0 on all four routing-ON runs; held_ticks 0 everywhere
#         EXCEPT the two +HELD runs, where it climbs >0 — proof the in-place held
#         path actually ran, NOT a silent copy-path fallback.
#       - story: pure-function VM calls (no §6 world to hold), so it earns the
#         SAME calls>0-on-routing-ON / 0-on-hatch proof, but no held_ticks column.
# The six states (POST-FLIP): 2× off-hatch (STRATA_CONTOUR=0), 2× default-on
# (STRATA_CONTOUR unset — routing ENGAGES by default), 2× default-on +HELD. The
# counters are now earned on the DEFAULT (unset) runs — that IS the flip.
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

run() { # $1 = "off" | "contour" | "held"  (POST-FLIP: default ON, =0 is the hatch)
	case "$1" in
		off)     STRATA_CONTOUR=0 godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1 ;;
		contour) godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1 ;;
		held)    STRATA_CONTOUR_HELD=1 godot --headless --quit-after 20000 res://tests/soak.tscn 2>&1 ;;
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
