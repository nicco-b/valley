#!/bin/sh
# build.sh — build the production Contour kernel end to end (PLAN_ENGINE §3 E2).
#
# The graduation of native-spike/build.sh onto loomkernel's discipline. Builds
# BOTH configs the shipped framework needs (loomkernel's debug/release pair):
#   1. datum: build the LatticeEmbed static archive (Swift VM + C ABI), release.
#   2. stage the archive + header beside this extension (lib/, src/).
#   3. cmake template_debug   -> bin/libcontourkernel.macos.dylib
#   4. cmake template_release -> bin/libcontourkernel.macos.release.dylib
#      (the named release-link gap: -DGODOTCPP_TARGET=template_release, the
#       exact loomkernel shipyard recipe).
#
# Reuses loomkernel's godot-cpp checkout at ../godot-cpp and the API dump at
# ../api (both gitignored/regenerable — clone/dump per native/CMakeLists.txt).
# Env: DATUM_DIR (default ~/code/datum).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
DATUM_DIR="${DATUM_DIR:-$HOME/code/datum}"

echo "== 1/4 datum: build LatticeEmbed archive (release) =="
( cd "$DATUM_DIR" && rm -rf lattice/.build && ./scripts/build_embed.sh release )

echo "== 2/4 stage archive + header =="
mkdir -p "$HERE/lib" "$HERE/src"
cp "$DATUM_DIR/lattice/.build/release/libLatticeEmbed.a" "$HERE/lib/libLatticeEmbed.a"
cp "$DATUM_DIR/lattice/Sources/CLatticeEmbed/include/lattice_embed.h" "$HERE/src/lattice_embed.h"

echo "== 3/4 cmake build: template_debug =="
cmake -B "$HERE/build-debug" -S "$HERE" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$HERE/build-debug" -j

echo "== 4/4 cmake build: template_release (the release-link gap) =="
cmake -B "$HERE/build-release" -S "$HERE" -DCMAKE_BUILD_TYPE=Release \
	-DGODOTCPP_TARGET=template_release >/dev/null
cmake --build "$HERE/build-release" -j

echo "OK ->"
ls -1 "$HERE/bin/"*.dylib
