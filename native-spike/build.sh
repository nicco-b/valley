#!/bin/sh
# build.sh — build the Contour embed-spike GDExtension end to end (Mission Z2).
#
# The build chain the shipping shape implies, made concrete:
#   1. datum: build the LatticeEmbed static archive (Swift VM + C ABI).
#   2. stage the archive + header beside this extension.
#   3. cmake: build libcontourspike.macos.dylib, linking the archive, the
#      prebuilt godot-cpp, and the OS Swift runtime.
#   4. stage the dylib into probe/bin so probe.gd can load it.
#
# Env: DATUM_DIR (default ~/code/datum). Uses the prebuilt godot-cpp under
# /Users/nicco/code/valley/native/build (see CMakeLists GODOT_NATIVE).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
DATUM_DIR="${DATUM_DIR:-$HOME/code/datum}"

echo "== 1/4 datum: build LatticeEmbed archive =="
( cd "$DATUM_DIR" && rm -rf lattice/.build && ./scripts/build_embed.sh release )

echo "== 2/4 stage archive + header =="
mkdir -p "$HERE/lib" "$HERE/src"
cp "$DATUM_DIR/lattice/.build/release/libLatticeEmbed.a" "$HERE/lib/libLatticeEmbed.a"
cp "$DATUM_DIR/lattice/Sources/CLatticeEmbed/include/lattice_embed.h" "$HERE/src/lattice_embed.h"

echo "== 3/4 cmake build =="
cmake -B "$HERE/build" -S "$HERE" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$HERE/build" -j

echo "== 4/4 stage dylib into probe =="
mkdir -p "$HERE/probe/bin"
cp "$HERE/bin/libcontourspike.macos.dylib" "$HERE/probe/bin/libcontourspike.macos.dylib"
echo "OK -> $HERE/probe/bin/libcontourspike.macos.dylib"
echo "run the probe:"
echo "  godot --headless --path $HERE/probe -s res://probe.gd"
