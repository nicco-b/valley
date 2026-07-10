# The Contour embed-spike GDExtension (Mission Z2 / PLAN_ENGINE §3 E2).
#
# Builds native-spike/bin/libcontourspike.macos.dylib: a godot-cpp extension
# that wraps the datum LatticeEmbed C ABI (the Swift static archive under lib/).
# It links the SAME prebuilt godot-cpp static lib loomkernel uses (read from the
# live checkout) with the EXACT compile defines/flags of that build, so the
# header-inline template code is ABI-identical to the archive — then adds the
# macOS ABI-stable Swift runtime (/usr/lib/swift, OS-provided) via the archive's
# autolink hints.
#
# Build:
#   cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
#   cmake --build build -j
cmake_minimum_required(VERSION 3.24)
project(contour_spike LANGUAGES CXX)

# --- godot-cpp: reuse the operator's prebuilt static lib + headers (read-only).
set(GODOT_NATIVE "/Users/nicco/code/valley/native" CACHE PATH "live valley native dir")
set(GODOTCPP_LIB "${GODOT_NATIVE}/build/bin/libgodot-cpp.macos.template_debug.arm64.a")
set(GODOTCPP_INCLUDES
	"${GODOT_NATIVE}/godot-cpp/include"
	"${GODOT_NATIVE}/build/godot-cpp/gen/include"
	"${GODOT_NATIVE}/godot-cpp/gdextension")

# --- swift runtime libdir (toolchain), for the archive's -lswift* autolink refs.
execute_process(COMMAND xcrun --find swiftc OUTPUT_VARIABLE SWIFTC_PATH OUTPUT_STRIP_TRAILING_WHITESPACE)
get_filename_component(_swift_bin "${SWIFTC_PATH}" DIRECTORY)
get_filename_component(_swift_tc "${_swift_bin}" DIRECTORY)
set(SWIFT_MACOSX "${_swift_tc}/lib/swift/macosx")

add_library(contourspike SHARED
	src/register_types.cpp
	src/contour_kernel.cpp
)
target_include_directories(contourspike PRIVATE ${GODOTCPP_INCLUDES} "${CMAKE_CURRENT_SOURCE_DIR}/src")

# EXACTLY the godot-cpp template_debug build's flags (native/build flags.make),
# so our sources match the prebuilt lib's inline template ABI.
target_compile_definitions(contourspike PRIVATE
	DEBUG_ENABLED GDEXTENSION HOT_RELOAD_ENABLED MACOS_ENABLED THREADS_ENABLED UNIX_ENABLED)
target_compile_options(contourspike PRIVATE
	-O2 -std=c++17 -fPIC -fvisibility=hidden -fno-exceptions -ffp-contract=off)

target_link_libraries(contourspike PRIVATE
	"${GODOTCPP_LIB}"
	"${CMAKE_CURRENT_SOURCE_DIR}/lib/libLatticeEmbed.a")
# The Swift runtime: search dirs so ld resolves the archive's autolink -lswift*.
# Runtime deps bind to absolute /usr/lib/swift/*.dylib (ABI-stable), so no rpath
# is strictly needed, but we add it for belt-and-braces.
target_link_directories(contourspike PRIVATE "/usr/lib/swift" "${SWIFT_MACOSX}")
target_link_options(contourspike PRIVATE -Wl,-rpath,/usr/lib/swift)

set_target_properties(contourspike PROPERTIES
	OUTPUT_NAME "contourspike.macos"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin"
	PREFIX "lib")
