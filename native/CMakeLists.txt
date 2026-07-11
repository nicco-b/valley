# The Loom native kernel (GDExtension). Build:
#   cmake -B native/build -S native -DCMAKE_BUILD_TYPE=Release
#   cmake --build native/build -j
# Output: native/bin/libloomkernel.macos.dylib
# godot-cpp builds against the API dumped from THE local godot binary
# (native/api; regenerate with `godot --headless --dump-extension-api
# --dump-gdextension-interface` inside native/api after engine upgrades).
cmake_minimum_required(VERSION 3.24)
project(loom_native LANGUAGES CXX)

set(GODOTCPP_GDEXTENSION_DIR "${CMAKE_CURRENT_SOURCE_DIR}/api" CACHE PATH "" FORCE)
add_subdirectory(godot-cpp SYSTEM)

add_library(loomkernel SHARED
	src/register_types.cpp
	src/terrain_kernel.cpp
)
target_link_libraries(loomkernel PRIVATE godot::cpp)
target_compile_features(loomkernel PRIVATE cxx_std_17)
# -ffp-contract=off: OUR determinism anchor. The kernel cannot be
# bit-identical to the engine's GDScript path (the official binary's
# fma association in Vector2 math is compiler-specific and
# unreproducible), so the contract is: the kernel is bit-deterministic
# WITH ITSELF, every worker-path consumer uses the kernel, and the
# soak fingerprint changed once at adoption (still bit-identical
# across runs). contract=off keeps our own rebuilds reproducible
# across compiler versions. Divergence vs GDScript is ~1e-5 m
# (tests/kernel_parity.gd gates it at 1e-4/1e-3).
target_compile_options(loomkernel PRIVATE -O2 -ffp-contract=off
	# ENGINE-RESTART (P2): kill cross-image weak-symbol coalescing. Without
	# this, GDCLASS's inline-header statics (get_class_static()'s StringName,
	# initialize_class()'s generation guard) compile as `weak external` in
	# THIS kernel's own translation units, and dyld coalesces them across a
	# second, independently-loaded copy of this same dylib onto whichever
	# image is already resident — the fresh copy inherits "already
	# initialized" state and the resident image's stale class-name strings.
	# The entry symbol stays exported regardless: GDE_EXPORT
	# (godot_cpp/core/defs.hpp) is `__attribute__((visibility("default")))`,
	# which overrides this default per-symbol.
	-fvisibility=hidden -fvisibility-inlines-hidden)
set_target_properties(loomkernel PROPERTIES
	OUTPUT_NAME "loomkernel.macos"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin"
)
