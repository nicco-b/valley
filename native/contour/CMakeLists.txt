# The Contour kernel (GDExtension) — PLAN_ENGINE §3 E2, the production embed.
#
# The graduation of native-spike/CMakeLists.txt onto loomkernel's discipline.
# Where the spike hand-linked a prebuilt template_debug godot-cpp .a with copied
# flags, this reuses loomkernel's OWN godot-cpp checkout (../godot-cpp) via
# add_subdirectory — the SAME chain native/CMakeLists.txt uses — so godot-cpp is
# built fresh and ABI-consistent for EACH config, template_debug AND
# template_release. The release config was the named gap: loomkernel's shipyard
# recipe is `cmake -DGODOTCPP_TARGET=template_release`; here that flag both
# builds the template_release godot-cpp lib and names the release dylib.
#
# Build (both configs) via build.sh, or by hand:
#   cmake -B build-debug   -S . -DCMAKE_BUILD_TYPE=Release
#   cmake -B build-release -S . -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=template_release
#   cmake --build build-<cfg> -j
# Output: bin/libcontourkernel.macos.dylib (debug), bin/libcontourkernel.macos.release.dylib (release)
cmake_minimum_required(VERSION 3.24)
project(contour_native LANGUAGES CXX)

# Reuse loomkernel's godot-cpp checkout + the SAME API dump (../api). godot-cpp
# selects template_debug (default) or template_release from GODOTCPP_TARGET —
# the loomkernel recipe, unchanged. Give it an explicit binary dir since the
# source lives one level up.
set(GODOTCPP_GDEXTENSION_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../api" CACHE PATH "" FORCE)
add_subdirectory(../godot-cpp godot-cpp SYSTEM)

# --- swift runtime libdir (toolchain), for the archive's -lswift* autolink refs.
execute_process(COMMAND xcrun --find swiftc OUTPUT_VARIABLE SWIFTC_PATH OUTPUT_STRIP_TRAILING_WHITESPACE)
get_filename_component(_swift_bin "${SWIFTC_PATH}" DIRECTORY)
get_filename_component(_swift_tc "${_swift_bin}" DIRECTORY)
set(SWIFT_MACOSX "${_swift_tc}/lib/swift/macosx")

add_library(contourkernel SHARED
	src/register_types.cpp
	src/contour_kernel.cpp
)
target_include_directories(contourkernel PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(contourkernel PRIVATE
	godot::cpp
	"${CMAKE_CURRENT_SOURCE_DIR}/lib/libLatticeEmbed.a")
target_compile_features(contourkernel PRIVATE cxx_std_17)

# -ffp-contract=off — loomkernel's determinism anchor, pinned here too. Our
# sources only byte-copy IEEE-754 patterns and cast real_t<->double for the
# vector Float32 boundary (no fma-eligible float arithmetic; the VM's actual
# float math lives in the Swift archive, built once and linked into BOTH
# configs). Pinning the flag guarantees a release -O3 cannot introduce
# contraction into those casts — which is WHY 88/88 corpus parity holds
# bit-identically on template_debug AND template_release (the Swift math is the
# same archive; the C++ boundary is contraction-free in either config). -O2
# matches loomkernel (debugger-friendly backtraces over the marginal -O3 win).
target_compile_options(contourkernel PRIVATE -O2 -ffp-contract=off
	# ENGINE-RESTART (P2): kill cross-image weak-symbol coalescing — same
	# rationale as loomkernel's native/CMakeLists.txt. Required (not merely
	# preferred) for contour: its Swift/objc-pinned image can never be
	# unloaded, so a fresh per-game copy always coexists with a resident one
	# and would otherwise coalesce onto it. The entry symbol stays exported:
	# GDE_EXPORT (godot_cpp/core/defs.hpp) is
	# `__attribute__((visibility("default")))`, overriding this per-symbol.
	-fvisibility=hidden -fvisibility-inlines-hidden)

# The Swift runtime: absolute /usr/lib/swift/*.dylib (ABI-stable) resolves the
# archive's autolink -lswift* refs; the rpath is belt-and-braces.
target_link_directories(contourkernel PRIVATE "/usr/lib/swift" "${SWIFT_MACOSX}")
target_link_options(contourkernel PRIVATE -Wl,-rpath,/usr/lib/swift)

# Output name mirrors loomkernel's bin/ pair: the default (template_debug) build
# emits libcontourkernel.macos.dylib; the template_release build emits
# libcontourkernel.macos.release.dylib. loomkernel's shipyard commit renamed the
# release build by hand — here the CMake names it from GODOTCPP_TARGET, so the
# release link is a first-class config, not a manual step.
if(GODOTCPP_TARGET STREQUAL "template_release")
	set(_contour_out "contourkernel.macos.release")
else()
	set(_contour_out "contourkernel.macos")
endif()
set_target_properties(contourkernel PROPERTIES
	OUTPUT_NAME "${_contour_out}"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin"
	PREFIX "lib"
)
