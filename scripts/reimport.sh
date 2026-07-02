#!/bin/sh
# Reimport assets. Usage: reimport.sh [name-fragment]
# With a name fragment, force-reimports matching assets by clearing their
# cache first (needed when only .import settings changed — Godot skips
# unchanged sources otherwise).
cd "$(dirname "$0")/.." || exit 1
if [ -n "$1" ]; then
	rm -f .godot/imported/*"$1"*
	echo "cleared cache matching '$1'"
fi
godot --headless --import 2>&1 | grep -iE "error|fail" | head -5
echo "import done"
